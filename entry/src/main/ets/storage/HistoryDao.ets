import { relationalStore } from '@kit.ArkData';
import { Database } from './Database';
import { ComicType } from '../model/ComicType';
import { Log } from '../foundation/Log';

/** Reading position is 1-based; epId distinguishes stable IDs from legacy indexes. */
export class History {
  id: string = '';
  type: ComicType = ComicType.local;
  storedSourceKey: string = '';
  epId?: string;
  title: string = '';
  subtitle: string = '';
  cover: string = '';
  time: number = 0;
  ep: number = 1;
  page: number = 1;
  group?: number;
  maxPage?: number;
  /** On save this is a delta; on read this is the accumulated duration. */
  readDurationMs: number = 0;

  get sourceKey(): string {
    return this.storedSourceKey || (this.type.isLocal ? 'local' : `type:${this.type.value}`);
  }

  description(): string {
    const groupPart = this.group === undefined ? '' : `第 ${this.group} 组 · `;
    return `${groupPart}第 ${this.ep} 章 · 第 ${this.page} 页`;
  }
}

export class HistoryDao {
  private static readonly columns: string =
    'id,type,source_key,ep_id,title,subtitle,cover,time,ep,page,max_page,chapter_group,read_duration_ms';
  private static listeners: Array<() => void> = [];

  static addListener(listener: () => void): void {
    if (HistoryDao.listeners.indexOf(listener) < 0) {
      HistoryDao.listeners.push(listener);
    }
  }

  static removeListener(listener: () => void): void {
    HistoryDao.listeners = HistoryDao.listeners.filter((item: () => void) => item !== listener);
  }

  private static changed(): void {
    for (const listener of HistoryDao.listeners) {
      try {
        listener();
      } catch (error) {
        Log.warn('HistoryDao', `listener failed: ${error}`);
      }
    }
  }

  /**
   * One ordered atomic write: no SELECT/REPLACE race on fast page changes.
   * Preserve upstream's read_episode column instead of resetting it on save.
   */
  static async save(history: History): Promise<void> {
    if (history.id.length === 0 || !Number.isFinite(history.ep) || history.ep < 1 ||
        !Number.isFinite(history.page) || history.page < 1 ||
        !Number.isFinite(history.time) || !Number.isFinite(history.readDurationMs)) {
      throw new Error('无效的阅读进度');
    }
    if (history.storedSourceKey.length > 0 &&
        ComicType.fromKey(history.storedSourceKey).value !== history.type.value) {
      throw new Error('历史记录的漫画源与类型不一致');
    }
    Database.rdb.executeSync(
      'INSERT INTO history (' + HistoryDao.columns + ') VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ' +
      'ON CONFLICT(id,type) DO UPDATE SET ' +
      "source_key=CASE WHEN excluded.source_key='' THEN history.source_key ELSE excluded.source_key END," +
      'ep_id=COALESCE(excluded.ep_id,history.ep_id),' +
      'title=excluded.title,subtitle=excluded.subtitle,cover=excluded.cover,' +
      'time=excluded.time,ep=excluded.ep,page=excluded.page,max_page=excluded.max_page,' +
      'chapter_group=excluded.chapter_group,' +
      'read_duration_ms=history.read_duration_ms+excluded.read_duration_ms',
      [history.id, history.type.value, history.storedSourceKey, history.epId ?? null,
        history.title, history.subtitle, history.cover, history.time, Math.floor(history.ep),
        Math.floor(history.page), history.maxPage ?? null, history.group ?? null,
        Math.max(0, history.readDurationMs)]);
    HistoryDao.changed();
  }

  static async find(id: string, type: number): Promise<History | undefined> {
    const result = await Database.query(
      `SELECT ${HistoryDao.columns} FROM history WHERE id = ? AND type = ?`, [id, type]);
    try {
      return result.goToFirstRow() ? HistoryDao.fromRow(result) : undefined;
    } finally {
      result.close();
    }
  }

  static async list(limit: number, offset: number = 0): Promise<History[]> {
    const result = await Database.query(
      `SELECT ${HistoryDao.columns} FROM history ORDER BY time DESC, type, id LIMIT ? OFFSET ?`,
      [Math.max(1, Math.floor(limit)), Math.max(0, Math.floor(offset))]);
    const items: History[] = [];
    try {
      while (result.goToNextRow()) {
        items.push(HistoryDao.fromRow(result));
      }
    } finally {
      result.close();
    }
    return items;
  }

  static async remove(id: string, type: number): Promise<void> {
    Database.rdb.executeSync('DELETE FROM history WHERE id = ? AND type = ?', [id, type]);
    HistoryDao.changed();
  }

  static async removeMany(items: History[]): Promise<void> {
    // No awaits inside this short transaction: page saves cannot interleave.
    Database.rdb.beginTransaction();
    try {
      for (const item of items) {
        Database.rdb.executeSync('DELETE FROM history WHERE id = ? AND type = ?', [item.id, item.type.value]);
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    HistoryDao.changed();
  }

  static async clear(): Promise<void> {
    Database.rdb.executeSync('DELETE FROM history');
    HistoryDao.changed();
  }

  private static fromRow(result: relationalStore.ResultSet): History {
    const history = new History();
    history.id = result.getString(result.getColumnIndex('id'));
    history.type = ComicType.fromValue(result.getLong(result.getColumnIndex('type')));
    history.storedSourceKey = result.getString(result.getColumnIndex('source_key'));
    const epIdColumn = result.getColumnIndex('ep_id');
    history.epId = result.isColumnNull(epIdColumn) ? undefined : result.getString(epIdColumn);
    history.title = result.getString(result.getColumnIndex('title'));
    history.subtitle = result.getString(result.getColumnIndex('subtitle'));
    history.cover = result.getString(result.getColumnIndex('cover'));
    history.time = result.getLong(result.getColumnIndex('time'));
    history.ep = result.getLong(result.getColumnIndex('ep'));
    history.page = result.getLong(result.getColumnIndex('page'));
    const maxPage = result.getColumnIndex('max_page');
    history.maxPage = result.isColumnNull(maxPage) ? undefined : result.getLong(maxPage);
    const group = result.getColumnIndex('chapter_group');
    history.group = result.isColumnNull(group) ? undefined : result.getLong(group);
    history.readDurationMs = result.getLong(result.getColumnIndex('read_duration_ms'));
    return history;
  }
}
