import { Database } from './Database';

export class FollowUpdate {
  sourceKey: string = '';
  comicId: string = '';
  title: string = '';
  cover: string = '';
  baseline: string = '';
  current: string = '';
  checkedAt: number = 0;
  subscribedAt: number = 0;
  error: string = '';
  get unread(): boolean { return this.baseline.length > 0 && this.current.length > 0 && this.baseline !== this.current; }
}

export class FollowUpdatesDao {
  static async init(): Promise<void> {
    await Database.init();
    await Database.execute('CREATE TABLE IF NOT EXISTS follow_updates (' +
      'source_key TEXT NOT NULL, comic_id TEXT NOT NULL, title TEXT NOT NULL, cover TEXT NOT NULL, ' +
      "baseline TEXT NOT NULL DEFAULT '', current_fingerprint TEXT NOT NULL DEFAULT '', " +
      "checked_at INTEGER NOT NULL DEFAULT 0, subscribed_at INTEGER NOT NULL, last_error TEXT NOT NULL DEFAULT '', " +
      'PRIMARY KEY (source_key,comic_id))');
  }

  static async list(): Promise<FollowUpdate[]> {
    await FollowUpdatesDao.init();
    const result = await Database.query('SELECT * FROM follow_updates ORDER BY subscribed_at DESC');
    const rows: FollowUpdate[] = [];
    try {
      while (result.goToNextRow()) {
        const row = new FollowUpdate();
        row.sourceKey = result.getString(result.getColumnIndex('source_key'));
        row.comicId = result.getString(result.getColumnIndex('comic_id'));
        row.title = result.getString(result.getColumnIndex('title'));
        row.cover = result.getString(result.getColumnIndex('cover'));
        row.baseline = result.getString(result.getColumnIndex('baseline'));
        row.current = result.getString(result.getColumnIndex('current_fingerprint'));
        row.checkedAt = result.getLong(result.getColumnIndex('checked_at'));
        row.subscribedAt = result.getLong(result.getColumnIndex('subscribed_at'));
        row.error = result.getString(result.getColumnIndex('last_error'));
        rows.push(row);
      }
    } finally { result.close(); }
    return rows;
  }

  static async find(sourceKey: string, comicId: string): Promise<FollowUpdate | undefined> {
    return (await FollowUpdatesDao.list()).find((row: FollowUpdate) => row.sourceKey === sourceKey && row.comicId === comicId);
  }

  static async follow(sourceKey: string, comicId: string, title: string, cover: string): Promise<void> {
    if (sourceKey.length === 0 || comicId.length === 0) { throw new Error('缺少追更漫画标识'); }
    await FollowUpdatesDao.init();
    await Database.execute('INSERT OR IGNORE INTO follow_updates ' +
      '(source_key,comic_id,title,cover,subscribed_at) VALUES (?,?,?,?,?)', [sourceKey, comicId, title, cover, Date.now()]);
  }

  static async unfollow(sourceKey: string, comicId: string): Promise<void> {
    await FollowUpdatesDao.init();
    await Database.execute('DELETE FROM follow_updates WHERE source_key=? AND comic_id=?', [sourceKey, comicId]);
  }

  static async record(row: FollowUpdate, fingerprint: string, failure: string): Promise<void> {
    await FollowUpdatesDao.init();
    // UPDATE, not upsert: an in-flight check must never resurrect a removed subscription.
    if (failure.length > 0) {
      await Database.execute('UPDATE follow_updates SET checked_at=?,last_error=? WHERE source_key=? AND comic_id=? AND subscribed_at=?',
        [Date.now(), failure, row.sourceKey, row.comicId, row.subscribedAt]);
    } else {
      await Database.execute("UPDATE follow_updates SET baseline=CASE WHEN baseline='' THEN ? ELSE baseline END, " +
        "current_fingerprint=?,checked_at=?,last_error='' WHERE source_key=? AND comic_id=? AND subscribed_at=?",
        [fingerprint, fingerprint, Date.now(), row.sourceKey, row.comicId, row.subscribedAt]);
    }
  }

  static async markRead(sourceKey: string, comicId: string): Promise<void> {
    await FollowUpdatesDao.init();
    await Database.execute("UPDATE follow_updates SET baseline=current_fingerprint WHERE source_key=? AND comic_id=? AND current_fingerprint<>''",
      [sourceKey, comicId]);
  }
}
