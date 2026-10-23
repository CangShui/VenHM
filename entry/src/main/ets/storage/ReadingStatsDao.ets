import { Database } from './Database';
import { History } from './HistoryDao';
import { ReadingStats } from '../features/ReadingStats';

export class ReadingStatsRow {
  key: string = '';
  sourceKey: string = '';
  comicId: string = '';
  title: string = '';
  durationMs: number = 0;
  pages: number = 0;
  chapters: number = 0;
}
export class ReadingStatsSnapshot {
  total: ReadingStatsRow = new ReadingStatsRow();
  undatedMs: number = 0;
  days: ReadingStatsRow[] = [];
  comics: ReadingStatsRow[] = [];
  sources: ReadingStatsRow[] = [];
}
/** Additive schema only. Legacy duration is a frozen baseline, NEVER summed with live history again. */
export class ReadingStatsDao {
  private static ready: boolean = false;
  private static ensure(): void {
    if (ReadingStatsDao.ready) { return; }
    Database.rdb.executeSync('CREATE TABLE IF NOT EXISTS reader_stats_legacy (source_key TEXT NOT NULL,comic_id TEXT NOT NULL,title TEXT NOT NULL,duration_ms INTEGER NOT NULL,PRIMARY KEY(source_key,comic_id))');
    Database.rdb.executeSync('CREATE TABLE IF NOT EXISTS reader_stats_segments (event_id TEXT NOT NULL,day TEXT NOT NULL,source_key TEXT NOT NULL,comic_id TEXT NOT NULL,title TEXT NOT NULL,duration_ms INTEGER NOT NULL,PRIMARY KEY(event_id,day))');
    Database.rdb.executeSync('CREATE TABLE IF NOT EXISTS reader_stats_pages (day TEXT NOT NULL,source_key TEXT NOT NULL,comic_id TEXT NOT NULL,ep_id TEXT NOT NULL,page INTEGER NOT NULL,PRIMARY KEY(day,source_key,comic_id,ep_id,page))');
    // A singleton marker makes this an actual one-time import, including later launches.
    Database.rdb.executeSync('CREATE TABLE IF NOT EXISTS reader_stats_meta (key TEXT PRIMARY KEY,value INTEGER NOT NULL)');
    Database.rdb.beginTransaction();
    try {
      Database.rdb.executeSync("INSERT OR IGNORE INTO reader_stats_legacy SELECT CASE WHEN source_key='' THEN 'type:'||type ELSE source_key END,id,title,MAX(0,read_duration_ms) FROM history WHERE NOT EXISTS (SELECT 1 FROM reader_stats_meta WHERE key='baseline')");
      Database.rdb.executeSync("INSERT OR IGNORE INTO reader_stats_meta VALUES ('baseline',1)");
      Database.rdb.commit(); ReadingStatsDao.ready = true;
    } catch (error) { Database.rdb.rollBack(); throw new Error('阅读统计初始化失败，未修改历史'); }
  }
  /** Called BEFORE HistoryDao.save: import old duration before the first new delta. Idempotent event token. */
  static record(history: History, token: string): void {
    ReadingStatsDao.ensure();
    if (token.length === 0 || history.id.length === 0 || history.sourceKey.length === 0 || history.page < 1) { throw new Error('无效的阅读统计身份'); }
    const segments = ReadingStats.split(history.time, history.readDurationMs);
    const ep = history.epId === undefined ? `index:${history.ep}` : `id:${history.epId}`;
    Database.rdb.beginTransaction();
    try {
      for (const segment of segments) {
        Database.rdb.executeSync('INSERT OR IGNORE INTO reader_stats_segments VALUES (?,?,?,?,?,?)',
          [token, segment.day, history.sourceKey, history.id, history.title, segment.durationMs]);
      }
      Database.rdb.executeSync('INSERT OR IGNORE INTO reader_stats_pages VALUES (?,?,?,?,?)',
        [ReadingStats.day(history.time), history.sourceKey, history.id, ep, history.page]);
      Database.rdb.commit();
    } catch (error) { Database.rdb.rollBack(); throw new Error('阅读统计保存失败'); }
  }
  static async snapshot(): Promise<ReadingStatsSnapshot> {
    ReadingStatsDao.ensure();
    const snapshot = new ReadingStatsSnapshot();
    const duration = await Database.query('SELECT source_key,comic_id,title,SUM(duration_ms) AS duration FROM (SELECT source_key,comic_id,title,duration_ms FROM reader_stats_legacy UNION ALL SELECT source_key,comic_id,title,duration_ms FROM reader_stats_segments) GROUP BY source_key,comic_id');
    try {
      while (duration.goToNextRow()) {
        const row = new ReadingStatsRow(); row.sourceKey = duration.getString(0); row.comicId = duration.getString(1);
        row.key = `${encodeURIComponent(row.sourceKey)}:${encodeURIComponent(row.comicId)}`;
        row.title = duration.getString(2); row.durationMs = duration.getLong(3); snapshot.comics.push(row);
      }
    } finally { duration.close(); }
    const pages = await Database.query('SELECT source_key,comic_id,COUNT(*) AS pages,COUNT(DISTINCT ep_id) AS chapters FROM (SELECT DISTINCT source_key,comic_id,ep_id,page FROM reader_stats_pages) GROUP BY source_key,comic_id');
    try {
      while (pages.goToNextRow()) {
        const source = pages.getString(0); const comic = pages.getString(1);
        let row = snapshot.comics.find((item: ReadingStatsRow) => item.sourceKey === source && item.comicId === comic);
        if (row === undefined) { row = new ReadingStatsRow(); row.sourceKey = source; row.comicId = comic;
          row.key = `${encodeURIComponent(source)}:${encodeURIComponent(comic)}`; row.title = comic; snapshot.comics.push(row); }
        row.pages = pages.getLong(2); row.chapters = pages.getLong(3);
      }
    } finally { pages.close(); }
    const days = await Database.query('SELECT day,SUM(duration_ms) FROM reader_stats_segments GROUP BY day ORDER BY day DESC');
    try { while (days.goToNextRow()) { const row = new ReadingStatsRow(); row.key = days.getString(0); row.durationMs = days.getLong(1); snapshot.days.push(row); } }
    finally { days.close(); }
    const dailyPages = await Database.query('SELECT day,COUNT(*),COUNT(DISTINCT source_key||char(0)||comic_id||char(0)||ep_id) FROM reader_stats_pages GROUP BY day');
    try {
      while (dailyPages.goToNextRow()) {
        const day = dailyPages.getString(0); let row = snapshot.days.find((item: ReadingStatsRow) => item.key === day);
        if (row === undefined) { row = new ReadingStatsRow(); row.key = day; snapshot.days.push(row); }
        row.pages = dailyPages.getLong(1); row.chapters = dailyPages.getLong(2);
      }
    } finally { dailyPages.close(); }
    const legacy = await Database.query('SELECT COALESCE(SUM(duration_ms),0) FROM reader_stats_legacy');
    try { if (legacy.goToFirstRow()) { snapshot.undatedMs = legacy.getLong(0); } } finally { legacy.close(); }
    for (const comic of snapshot.comics) {
      snapshot.total.durationMs += comic.durationMs; snapshot.total.pages += comic.pages; snapshot.total.chapters += comic.chapters;
      let source = snapshot.sources.find((item: ReadingStatsRow) => item.key === comic.sourceKey);
      if (source === undefined) { source = new ReadingStatsRow(); source.key = comic.sourceKey; source.title = comic.sourceKey; snapshot.sources.push(source); }
      source.durationMs += comic.durationMs; source.pages += comic.pages; source.chapters += comic.chapters;
    }
    snapshot.days.sort((a: ReadingStatsRow, b: ReadingStatsRow) => b.key.localeCompare(a.key));
    snapshot.comics.sort((a: ReadingStatsRow, b: ReadingStatsRow) => b.durationMs - a.durationMs);
    return snapshot;
  }
}
