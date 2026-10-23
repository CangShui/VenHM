import { Database } from './Database';

export class SearchHistoryEntry {
  term: string = '';
  usedAt: number = 0;
}

/** User-submitted keywords only; never included in network/audit logs. */
export class SearchHistoryDao {
  private static ready: boolean = false;
  private static opening?: Promise<void>;
  private static tail: Promise<void> = Promise.resolve();
  private static async init(): Promise<void> {
    if (SearchHistoryDao.ready) { return; }
    if (SearchHistoryDao.opening !== undefined) { return SearchHistoryDao.opening; }
    SearchHistoryDao.opening = SearchHistoryDao.open();
    try { await SearchHistoryDao.opening; } finally { SearchHistoryDao.opening = undefined; }
  }
  private static async open(): Promise<void> {
    await Database.init();
    await Database.rdb.executeSql('CREATE TABLE IF NOT EXISTS search_history (' +
      'term TEXT PRIMARY KEY NOT NULL, used_at INTEGER NOT NULL)');
    SearchHistoryDao.ready = true;
  }
  static async list(): Promise<SearchHistoryEntry[]> {
    await SearchHistoryDao.init();
    await SearchHistoryDao.tail;
    const rows = await Database.rdb.querySql('SELECT term, used_at FROM search_history ORDER BY used_at DESC, term ASC LIMIT 100');
    const result: SearchHistoryEntry[] = [];
    try {
      while (rows.goToNextRow()) {
        const item = new SearchHistoryEntry();
        item.term = rows.getString(rows.getColumnIndex('term'));
        item.usedAt = rows.getLong(rows.getColumnIndex('used_at'));
        result.push(item);
      }
    } finally { rows.close(); }
    return result;
  }
  private static enqueue(operation: () => Promise<void>): Promise<void> {
    const next = SearchHistoryDao.tail.then(operation);
    SearchHistoryDao.tail = next.catch(() => {});
    return next;
  }
  static async remember(term: string): Promise<void> {
    if (term.trim().length === 0) { return; }
    if (term.length > 4096) { throw new Error('搜索文本过长，未保存历史'); }
    await SearchHistoryDao.init();
    const time = Date.now();
    await SearchHistoryDao.enqueue(async () => {
      await Database.rdb.executeSql('INSERT OR REPLACE INTO search_history(term, used_at) VALUES (?, ?)', [term, time]);
      await Database.rdb.executeSql('DELETE FROM search_history WHERE term NOT IN (' +
        'SELECT term FROM search_history ORDER BY used_at DESC, term ASC LIMIT 100)');
    });
  }
  static async remove(term: string): Promise<void> {
    await SearchHistoryDao.init();
    await SearchHistoryDao.enqueue(async () => { await Database.rdb.executeSql('DELETE FROM search_history WHERE term = ?', [term]); });
  }
  static async clear(): Promise<void> {
    await SearchHistoryDao.init();
    await SearchHistoryDao.enqueue(async () => { await Database.rdb.executeSql('DELETE FROM search_history'); });
  }
}
