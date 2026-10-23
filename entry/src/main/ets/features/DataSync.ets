import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Database } from '../storage/Database';
import { Settings } from '../foundation/Settings';
import { HttpClient, HttpRequestOptions } from '../network/HttpClient';
import { Log } from '../foundation/Log';

export class SyncTable {
  name: string = '';
  columns: string[] = [];
  rows: relationalStore.ValueType[][] = [];
}

export class SyncSnapshot {
  format: string = 'venera-hm-reader-data';
  version: number = 1;
  createdAt: number = Date.now();
  readerMode: string = '';
  tables: SyncTable[] = [];
}

/** Explicit backup/merge; no credentials/cookies/source_data are exported. */
export class DataSync {
  static readonly schemas: Map<string, string[]> = new Map<string, string[]>([
    ['favorite_folders', ['name', 'display_order']],
    ['favorites', ['id', 'type', 'source_key', 'name', 'author', 'tags', 'cover_path', 'folder', 'time', 'display_order']],
    ['history', ['id', 'type', 'title', 'subtitle', 'cover', 'time', 'ep', 'page', 'read_episode',
      'max_page', 'chapter_group', 'read_duration_ms', 'source_key', 'ep_id']]
  ]);
  private static busy: boolean = false;

  static endpoint(base: string): string {
    const trimmed = base.trim().replace(/\/+$/, '');
    if (!/^https:\/\/[^/?#]+(?:\/[^?#]*)?$/.test(trimmed) || /[\x00-\x20]/.test(trimmed) ||
        trimmed.split('/')[2].includes('@')) {
      throw new Error('请使用不含账号、查询参数或片段的HTTPS WebDAV目录地址');
    }
    return `${trimmed}/venera-hm-reader-data-v1.json`;
  }

  private static options(user: string, password: string): HttpRequestOptions {
    const options = new HttpRequestOptions();
    options.retries = 0;
    options.headers.set('Accept', 'application/json');
    if (user.length > 0 || password.length > 0) {
      const bytes = new util.TextEncoder().encodeInto(`${user}:${password}`);
      const base64 = new util.Base64Helper().encodeToStringSync(bytes);
      options.headers.set('Authorization', `Basic ${base64}`);
    }
    return options;
  }

  static async exportSnapshot(trace: string): Promise<SyncSnapshot> {
    const snapshot = new SyncSnapshot();
    snapshot.readerMode = Settings.readerMode;
    for (const name of DataSync.schemas.keys()) {
      const table = new SyncTable();
      table.name = name;
      table.columns = (DataSync.schemas.get(name) as string[]).slice();
      const rows = await Database.query(`SELECT ${table.columns.join(',')} FROM ${name}`);
      try {
        while (rows.goToNextRow()) {
          if (table.rows.length >= 50000) { throw new Error('数据量超过备份上限，未上传'); }
          const row: relationalStore.ValueType[] = [];
          for (let i = 0; i < table.columns.length; i++) {
            row.push(rows.isColumnNull(i) ? null : rows.getValue(i));
          }
          table.rows.push(row);
        }
      } finally { rows.close(); }
      snapshot.tables.push(table);
      Log.audit(trace, '同步读取', `表=${name}；行数=${table.rows.length}；不读取账号、Cookie和源私有数据`);
    }
    return snapshot;
  }

  static validate(raw: Object): SyncTable[] {
    const data = raw as Record<string, Object>;
    if (data['format'] !== 'venera-hm-reader-data' || data['version'] !== 1 || !Array.isArray(data['tables'])) {
      throw new Error('备份格式或版本不支持');
    }
    const seen = new Set<string>();
    const tables: SyncTable[] = [];
    for (const item of data['tables'] as Object[]) {
      if (item === null || typeof item !== 'object') { throw new Error('备份表定义无效'); }
      const value = item as Record<string, Object>;
      const name = value['name'];
      if (typeof name !== 'string' || !DataSync.schemas.has(name) || seen.has(name)) {
        throw new Error('备份包含未授权表或重复表');
      }
      const expected = DataSync.schemas.get(name) as string[];
      if (!Array.isArray(value['columns']) || (value['columns'] as Object[]).join(',') !== expected.join(',')) {
        throw new Error('备份字段与白名单不一致');
      }
      const rawRows = value['rows'];
      if (!Array.isArray(rawRows) || rawRows.length > 50000) { throw new Error('备份行数无效'); }
      const table = new SyncTable();
      table.name = name;
      table.columns = expected.slice();
      for (const row of rawRows as Object[]) {
        if (!Array.isArray(row) || row.length !== expected.length) { throw new Error('备份行字段数量不一致'); }
        const cells: relationalStore.ValueType[] = [];
        for (const cell of row as Object[]) {
          if (cell === null || typeof cell === 'string' || typeof cell === 'number' && Number.isFinite(cell)) {
            if (typeof cell === 'string' && cell.length > 1000000) { throw new Error('备份单元格过长'); }
            cells.push(cell as relationalStore.ValueType);
          } else { throw new Error('备份单元格类型无效'); }
        }
        for (let index = 0; index < expected.length; index++) {
          const column = expected[index];
          const cell = cells[index];
          const numeric = ['type', 'display_order', 'time', 'ep', 'page', 'max_page',
            'chapter_group', 'read_duration_ms'].includes(column) &&
            !(name === 'favorites' && column === 'time');
          const nullable = ['max_page', 'chapter_group', 'ep_id'].includes(column);
          if (cell === null && nullable) { continue; }
          if (numeric) {
            if (typeof cell !== 'number' || !Number.isSafeInteger(cell)) {
              throw new Error(`备份数字字段无效：${column}`);
            }
            if (['ep', 'page'].includes(column) && cell < 1 ||
              ['time', 'max_page', 'chapter_group', 'read_duration_ms'].includes(column) && cell < 0) {
              throw new Error(`备份字段越界：${column}`);
            }
          } else if (typeof cell !== 'string') { throw new Error(`备份文本字段无效：${column}`); }
          if (column === 'id' && cell === '') { throw new Error('备份漫画ID为空'); }
          if (name === 'favorite_folders' && column === 'name' &&
            typeof cell === 'string' && (cell.length > 50 || cell.includes('"'))) {
            throw new Error('备份收藏夹名无效');
          }
        }
        table.rows.push(cells);
      }
      seen.add(name);
      tables.push(table);
    }
    return tables;
  }

  static mergeSnapshot(raw: Object, trace: string): number {
    const tables = DataSync.validate(raw);
    let inserted = 0;
    Database.rdb.beginTransaction();
    try {
      for (const table of tables) {
        for (const row of table.rows) {
          if (table.name === 'favorites') {
            const folder = row[table.columns.indexOf('folder')];
            Database.rdb.executeSync('INSERT OR IGNORE INTO favorite_folders (name,display_order) VALUES (?,0)', [folder]);
          }
          // Never replace local records on conflict. This is conservative
          // restore/merge, not a timestamp-based bidirectional conflict engine.
          Database.rdb.executeSync(
            `INSERT OR IGNORE INTO ${table.name} (${table.columns.join(',')}) VALUES (${table.columns.map(() => '?').join(',')})`, row);
          inserted++;
        }
        Log.audit(trace, '同步合并', `表=${table.name}；提交行数=${table.rows.length}；冲突保留本地记录`);
      }
      Database.rdb.commit();
      return inserted;
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static async upload(base: string, user: string, password: string): Promise<void> {
    if (DataSync.busy) { throw new Error('已有同步操作'); }
    const endpoint = DataSync.endpoint(base);
    DataSync.busy = true;
    const trace = `sync-upload-${Date.now()}`;
    try {
      const snapshot = await DataSync.exportSnapshot(trace);
      const options = DataSync.options(user, password);
      options.jsonBody = JSON.stringify(snapshot);
      const response = await HttpClient.request(endpoint, http.RequestMethod.PUT, options);
      if (!response.ok) { throw new Error(`WebDAV上传HTTP ${response.status}`); }
      Log.audit(trace, '同步上传完成', '阅读历史/收藏备份已上传；账号和Cookie未导出');
    } catch (error) {
      Log.audit(trace, '同步上传异常', '上传失败；未记录地址认证信息，不报告成功');
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally { DataSync.busy = false; }
  }

  static async downloadAndMerge(base: string, user: string, password: string): Promise<number> {
    if (DataSync.busy) { throw new Error('已有同步操作'); }
    const endpoint = DataSync.endpoint(base);
    DataSync.busy = true;
    const trace = `sync-restore-${Date.now()}`;
    try {
      const response = await HttpClient.request(endpoint, http.RequestMethod.GET, DataSync.options(user, password));
      if (!response.ok) { throw new Error(`WebDAV下载HTTP ${response.status}`); }
      if (response.body.length > 20000000) { throw new Error('备份超过20MB，未导入'); }
      const raw = JSON.parse(response.body) as Object;
      const count = DataSync.mergeSnapshot(raw, trace);
      Log.audit(trace, '同步恢复完成', `处理行数=${count}；冲突保留本地数据；未导入账号`);
      return count;
    } catch (error) {
      Log.audit(trace, '同步恢复异常', '下载/验证/合并失败；验证先于事务，事务失败回滚');
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally { DataSync.busy = false; }
  }
}
