import { Database } from '../storage/Database';
import { Log } from '../foundation/Log';
import { AuthLogScope } from './AuthLogScope';

/**
 * Per-source persistent data (`load_data` / `save_data` / `delete_data`).
 *
 * Dart original: `ComicSource.loadData/saveData` wrote
 * `<dataPath>/comic_source/<key>.data` as JSON. The port keeps the same
 * key/value shape in the `source_data` table plus an in-memory map, because the
 * JS side calls these synchronously and cannot await a query.
 */
export class SourceDataStore {
  private static readonly cache: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  private static writeTail: Promise<void> = Promise.resolve();
  private static sequence: number = 0;
  private static readonly revisions: Map<string, number> = new Map<string, number>();
  private static readonly committed: Map<string, string> = new Map<string, string>();
  private static readonly failures: Map<string, number> = new Map<string, number>();
  private static failureSequence: number = 0;
  private static errorCode(error: Object): string {
    const value = (error as Record<string, Object>)['code'];
    return typeof value === 'number' && Number.isFinite(value) ? String(value) : 'unknown';
  }

  static failureEpoch(sourceKey: string): number { return SourceDataStore.failures.get(sourceKey) ?? 0; }

  /** Script saveData is synchronous at its API surface, but login cannot ignore failed queued writes. */
  static async awaitSourceWrites(sourceKey: string, baseline: number, trace: string): Promise<void> {
    const barrier = SourceDataStore.writeTail;
    await barrier;
    if (SourceDataStore.failureEpoch(sourceKey) > baseline) {
      Log.audit(trace, '源持久化屏障拒绝', '此源回调期间有异步保存/删除失败；不提前宣布登录成功');
      throw new Error('源会话数据未全部保存');
    }
    Log.audit(trace, '源持久化屏障返回', '回调已排队的数据写入完成，没有本轮源写入失败');
  }

  /** Serialize writes/deletes so a slow old write cannot overwrite a new value. */
  private static enqueue(sql: string, args: string[], trace: string): Promise<void> {
    const write = SourceDataStore.writeTail.then(async (): Promise<void> => {
      Log.audit(trace, '数据库写入', '执行source_data参数化写入/删除；不记录设置内容或凭据');
      await Database.execute(sql, args);
      Log.audit(trace, '数据库完成', 'source_data操作成功');
    });
    SourceDataStore.writeTail = write.then((): void => {}, (): void => {});
    return write;
  }

  /** Load one source's data into memory. Call before parsing its script. */
  static async preload(sourceKey: string): Promise<void> {
    if (SourceDataStore.cache.has(sourceKey)) {
      return;
    }
    const map = new Map<string, string>();
    try {
      const result = await Database.query(
        'SELECT data_key, data_value FROM source_data WHERE source_key = ?', [sourceKey]);
      try {
        while (result.goToNextRow()) {
          const key = result.getString(result.getColumnIndex('data_key'));
          const value = result.getString(result.getColumnIndex('data_value'));
          map.set(key, value);
          SourceDataStore.committed.set(`${sourceKey}\u0000${key}`, value);
        }
      } finally {
        result.close();
      }
    } catch (error) {
      Log.warn('SourceDataStore', `preload ${sourceKey} failed: ${error}`);
    }
    SourceDataStore.cache.set(sourceKey, map);
  }

  private static mapFor(sourceKey: string): Map<string, string> {
    let map = SourceDataStore.cache.get(sourceKey);
    if (map === undefined) {
      map = new Map<string, string>();
      SourceDataStore.cache.set(sourceKey, map);
    }
    return map;
  }

  /**
   * Value as the script stored it (JSON decoded), or null when absent.
   *
   * `null` rather than `undefined` because this value is handed straight back
   * to the JS bridge, whose answer type is `Object | null`.
   */
  static get(sourceKey: string, dataKey: string): Object | null {
    const raw = SourceDataStore.mapFor(sourceKey).get(dataKey);
    if (raw === undefined) {
      return null;
    }
    try {
      return JSON.parse(raw) as Object;
    } catch (error) {
      return raw;
    }
  }

  /** Synchronous write to memory, asynchronous persistence. */
  static set(sourceKey: string, dataKey: string, value: Object | undefined, trace?: string): void {
    SourceDataStore.writeValue(sourceKey, dataKey, value,
      trace ?? `source-data-${Date.now()}-${SourceDataStore.sequence++}`).catch((error: Object) => {
      Log.warn('SourceDataStore', `persist ${sourceKey}/${dataKey} failed; raw error omitted to protect stored credentials`);
    });
  }

  /** UI callers must await persistence before displaying "saved". */
  static async setAndWait(sourceKey: string, dataKey: string, value: Object,
    trace: string): Promise<void> {
    await SourceDataStore.writeValue(sourceKey, dataKey, value, trace);
  }

  private static async writeValue(sourceKey: string, dataKey: string,
    value: Object | undefined, trace: string): Promise<void> {
    let raw = 'null';
    if (value !== undefined) {
      try {
        raw = JSON.stringify(value);
      } catch (error) {
        raw = JSON.stringify(String(value));
      }
    }
    const map = SourceDataStore.mapFor(sourceKey);
    const identity = `${sourceKey}\u0000${dataKey}`;
    const revision = ++SourceDataStore.sequence;
    SourceDataStore.revisions.set(identity, revision);
    map.set(dataKey, raw);
    Log.audit(trace, '内存更新', `源=${sourceKey}；数据键=${AuthLogScope.owns(trace) ? '账号路径省略' : dataKey}；版本=${revision}；等待有序落盘`);
    try {
      await SourceDataStore.enqueue(
      'INSERT OR REPLACE INTO source_data (source_key, data_key, data_value) VALUES (?, ?, ?)',
        [sourceKey, dataKey, raw], trace);
      SourceDataStore.committed.set(identity, raw);
    } catch (error) {
      SourceDataStore.failures.set(sourceKey, ++SourceDataStore.failureSequence);
      // Never undo a later user/script update while recovering this failed one.
      if (SourceDataStore.revisions.get(identity) === revision) {
        const old = SourceDataStore.committed.get(identity);
        if (old === undefined) {
          map.delete(dataKey);
        } else {
          map.set(dataKey, old);
        }
      }
      Log.audit(trace, '数据库异常', `code=${SourceDataStore.errorCode(error)}；写入失败，未被后续修改覆盖时恢复旧值；不输出可能含会话内容的原文`);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static remove(sourceKey: string, dataKey: string, trace?: string): void {
    const id = trace ?? `source-data-delete-${Date.now()}-${SourceDataStore.sequence++}`;
    SourceDataStore.removeAndWait(sourceKey, dataKey, id).catch((error: Object) => {
      Log.warn('SourceDataStore', `delete ${sourceKey}/${dataKey} failed; raw error omitted to protect stored credentials`);
    });
  }

  static async removeAndWait(sourceKey: string, dataKey: string, trace: string): Promise<void> {
    const identity = `${sourceKey}\u0000${dataKey}`;
    const revision = ++SourceDataStore.sequence;
    SourceDataStore.revisions.set(identity, revision);
    const map = SourceDataStore.mapFor(sourceKey);
    map.delete(dataKey);
    Log.audit(trace, '删除到达', `源=${sourceKey}；数据键=${AuthLogScope.owns(trace) ? '账号路径省略' : dataKey}；版本=${revision}；等待数据库删除`);
    try {
      await SourceDataStore.enqueue('DELETE FROM source_data WHERE source_key = ? AND data_key = ?',
        [sourceKey, dataKey], trace);
      SourceDataStore.committed.delete(identity);
      Log.audit(trace, '删除返回', '内存与数据库删除均已确认');
    } catch (error) {
      SourceDataStore.failures.set(sourceKey, ++SourceDataStore.failureSequence);
      if (SourceDataStore.revisions.get(identity) === revision) {
        const old = SourceDataStore.committed.get(identity);
        if (old === undefined) { map.delete(dataKey); } else { map.set(dataKey, old); }
      }
      Log.audit(trace, '删除异常', `code=${SourceDataStore.errorCode(error)}；未覆盖更新操作；恢复最后落盘值，不能声称退出登录/删除成功`);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  /** Roll back staging only when no script/later user operation changed the staged value. */
  static async restoreIfCurrent(sourceKey: string, dataKey: string, staged: Object,
    previous: Object | null, trace: string): Promise<void> {
    const raw = SourceDataStore.mapFor(sourceKey).get(dataKey);
    if (raw !== JSON.stringify(staged)) {
      Log.audit(trace, '登录暂存回滚跳过', '源脚本或更新操作已修改该键，保留新值');
      return;
    }
    if (previous === null) { await SourceDataStore.removeAndWait(sourceKey, dataKey, trace); }
    else { await SourceDataStore.setAndWait(sourceKey, dataKey, previous, trace); }
    Log.audit(trace, '登录暂存回滚返回', '恢复本次暂存前的数据，不记录登录内容');
  }
}
