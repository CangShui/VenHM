import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContext } from '../foundation/AppContext';
import { Settings } from '../foundation/Settings';
import { Database } from '../storage/Database';
import { History, HistoryDao } from '../storage/HistoryDao';
import { ComicType } from '../model/ComicType';
import { HistoryNavigation } from './HistoryNavigation';
import { ReadingPosition, ReadingClock } from './ReadingPosition';
import { ImageLoader } from '../network/ImageLoader';
import { Log } from '../foundation/Log';

/** Opt-in tests. Temporary SQL rows are isolated by fresh IDs and always removed. */
export class HistoryUsability {
  private static readonly fixtureKey: string = 'historyUsabilityFixture';

  private static check(value: boolean, label: string): void {
    if (!value) {
      throw new Error(label);
    }
  }

  static async run(): Promise<string[]> {
    const reports: string[] = [];
    const id = `__history_probe_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
    const source = '__history_offline_probe__';
    const record = new History();
    record.id = id;
    record.type = ComicType.fromKey(source);
    record.storedSourceKey = source;
    record.epId = 'chapter-2';
    record.title = 'isolated history test';
    record.ep = 2;
    record.page = 2;
    record.time = Date.now();
    record.readDurationMs = 10;
    // Refuse accidental collisions instead of replacing anything pre-existing.
    HistoryUsability.check(await HistoryDao.find(id, record.type.value) === undefined, '测试标识冲突');
    try {
      await HistoryDao.save(record);
      Database.rdb.executeSync('UPDATE history SET read_episode = ? WHERE id = ? AND type = ?',
        ['1,2', id, record.type.value]);
      const writes: Promise<void>[] = [];
      for (let index = 0; index < 12; index++) {
        record.page = index + 1;
        record.readDurationMs = 5;
        writes.push(HistoryDao.save(record));
      }
      await Promise.all(writes);
      const saved = await HistoryDao.find(id, record.type.value);
      HistoryUsability.check(saved !== undefined, '历史未持久化');
      if (saved === undefined) {
        throw new Error('历史未持久化');
      }
      HistoryUsability.check(saved.page === 12 && saved.readDurationMs === 70,
        '快速翻页丢失进度或阅读时长');
      HistoryUsability.check(saved.storedSourceKey === source && saved.epId === 'chapter-2', '源或章节ID丢失');
      HistoryUsability.check(saved.maxPage === undefined && saved.group === undefined, 'NULL字段语义改变');
      const rows = await Database.query('SELECT read_episode FROM history WHERE id = ? AND type = ?',
        [id, record.type.value]);
      try {
        HistoryUsability.check(rows.goToFirstRow() && rows.getString(0) === '1,2', '已读章节被重置');
      } finally {
        rows.close();
      }
      reports.push('PASS · 快速连续12次保存：末页12、时长70ms、源/章节ID/NULL/已读章节保留');

      const legacy = new History();
      legacy.type = ComicType.fromKey('correct_source');
      HistoryUsability.check(HistoryNavigation.resolveKey(legacy, ['wrong_source', 'correct_source']) ===
        'correct_source', '旧hash记录匹配了错误源');
      HistoryUsability.check(HistoryNavigation.resolveKey(legacy, ['wrong_source']) === undefined,
        '缺失源不应回退到其它源');
      legacy.storedSourceKey = 'wrong_source';
      HistoryUsability.check(HistoryNavigation.resolveKey(legacy, ['wrong_source']) === undefined,
        '不一致源key/hash应被拒绝');
      reports.push('PASS · 旧记录hash准确匹配、缺失源/冲突源拒绝跳转');

      HistoryUsability.check(ReadingPosition.resolveChapter(['a', 'b'], 'b', 1).chapterIndex === 1,
        '稳定ID未优先于索引');
      HistoryUsability.check(ReadingPosition.resolveChapter(['a', 'b'], undefined, 2).chapterIndex === 1,
        '旧记录第2章恢复失败');
      HistoryUsability.check(ReadingPosition.resolveChapter([''], '', 1).chapterIndex === 0,
        '空ID单章节恢复失败');
      HistoryUsability.check(ReadingPosition.resolveChapter(['a'], 'missing', 1).error.length > 0,
        '失效章节不应静默跳到第一章');
      HistoryUsability.check(ReadingPosition.resolveChapter(['a'], undefined, 9).error.length > 0,
        '越界旧章节不应静默跳到第一章');
      HistoryUsability.check(ReadingPosition.pageIndex(3, 4) === 2 &&
        ReadingPosition.pageIndex(99, 4) === 3 && ReadingPosition.pageIndex(1, 0) === -1,
        '页码边界失败');
      const clock = new ReadingClock();
      clock.start(1000);
      HistoryUsability.check(clock.take(1050, false) === 50 && clock.take(1100, true) === 50 &&
        clock.take(1150, true) === 0, '同页退出或重复退出时长失败');
      reports.push('PASS · 稳定ID/旧索引/空ID/失效章节/页码越界/阅读时长无重复');

      // NULL distinguishes a legacy record from a legitimate empty chapter ID.
      record.epId = '';
      record.readDurationMs = 0;
      await HistoryDao.save(record);
      const implicit = await HistoryDao.find(id, record.type.value);
      HistoryUsability.check(implicit?.epId === '', '空ID被误当成缺失字段');
      await HistoryDao.removeMany([record]);
      HistoryUsability.check(await HistoryDao.find(id, record.type.value) === undefined, '批量删除未落盘');
      reports.push('PASS · 空章节ID持久化及定向批量删除');
    } finally {
      await HistoryDao.remove(id, record.type.value);
    }
    for (const report of reports) {
      Log.info('HistoryUsability', report);
    }
    return reports;
  }

  static fixtureId(): string {
    return Settings.getString(HistoryUsability.fixtureKey, '');
  }

  private static ownedPath(id: string): string {
    if (!/^HM_OFFLINE_READER_[0-9]+_[0-9]+$/.test(id)) {
      throw new Error('拒绝操作非测试目录');
    }
    return `${AppContext.localComicDir}/${id}`;
  }

  static async prepareFixture(): Promise<History> {
    let id = HistoryUsability.fixtureId();
    if (id.length === 0) {
      id = `HM_OFFLINE_READER_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
      const path = HistoryUsability.ownedPath(id);
      if (fs.accessSync(path)) {
        throw new Error('测试目录冲突');
      }
      fs.mkdirSync(path, true);
      const marker = fs.openSync(`${path}/.venera-usability`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(marker.fd, id);
      } finally {
        fs.closeSync(marker);
      }
      await Settings.setString(HistoryUsability.fixtureKey, id);
    }
    const path = HistoryUsability.ownedPath(id);
    HistoryUsability.check(fs.readTextSync(`${path}/.venera-usability`) === id, '测试目录标记不匹配');
    for (let chapter = 1; chapter <= 2; chapter++) {
      const dir = `${path}/Chapter_${chapter}`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      for (let page = 1; page <= 3; page++) {
        const bytes = await AppContext.context.resourceManager.getRawFileContent(`usability/c${chapter}p${page}.png`);
        const file = fs.openSync(`${dir}/${page}.png`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
        } finally {
          fs.closeSync(file);
        }
      }
    }
    const sample = new History();
    sample.id = id;
    sample.type = ComicType.local;
    sample.storedSourceKey = 'local';
    sample.title = '离线阅读验收样本（2章×3页）';
    sample.cover = `file://${path}/Chapter_1/1.png`;
    const pixels = await ImageLoader.load(sample.cover);
    const info = await pixels.getImageInfo();
    HistoryUsability.check(info.size.width === 600 && info.size.height === 900, '本地图片解码尺寸错误');
    Log.info('HistoryUsability', 'PASS · 本地样本封面 ImageKit 解码600×900；可用于真实页面操作');
    return sample;
  }

  static async cleanupFixture(): Promise<void> {
    const id = HistoryUsability.fixtureId();
    if (id.length === 0) {
      return;
    }
    const path = HistoryUsability.ownedPath(id);
    if (fs.accessSync(path)) {
      // Verify exact app-owned path AND marker before any recursive deletion.
      HistoryUsability.check(fs.readTextSync(`${path}/.venera-usability`) === id, '拒绝清理无标记目录');
      fs.rmdirSync(path);
    }
    await HistoryDao.remove(id, ComicType.local.value);
    await Settings.remove(HistoryUsability.fixtureKey);
  }
}
