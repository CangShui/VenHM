import { ComicDetails } from '../model/ComicDetails';
import { FollowUpdate, FollowUpdatesDao } from '../storage/FollowUpdatesDao';
import { SourceManager } from '../source/SourceManager';
import { AuthLogScope } from '../source/AuthLogScope';

/** Manual foreground queue, never a scheduled/background service. */
export class FollowUpdates {
  private static checking: boolean = false;

  static async follow(sourceKey: string, comicId: string, title: string, cover: string): Promise<void> {
    await FollowUpdatesDao.follow(sourceKey, comicId, title, cover);
  }

  static fingerprint(details: ComicDetails): string {
    const chapters = details.chapters;
    const date = details.findUpdateTime() ?? '';
    if ((chapters === undefined || chapters.length === 0) && date.length === 0) {
      throw new Error('源未提供章节或有效更新日期，不能判断更新');
    }
    // Persist a deterministic chapter/date signature, no image/request URLs or headers.
    const signals: string[] = [date];
    if (chapters !== undefined) {
      if (chapters.isGrouped) {
        for (const group of chapters.groupNames) {
          signals.push(group);
          for (const id of chapters.getGroup(group).keys()) { signals.push(id, chapters.getGroup(group).get(id) ?? ''); }
        }
      } else {
        for (const id of chapters.ids) { signals.push(id, chapters.titleOf(id) ?? ''); }
      }
    }
    // Two independent 32-bit FNV-style accumulators; no raw chapter URLs in the DB.
    const text = JSON.stringify(signals);
    let a = 2166136261;
    let b = 2246822519;
    for (let i = 0; i < text.length; i++) {
      a = Math.imul(a ^ text.charCodeAt(i), 16777619) >>> 0;
      b = Math.imul(b ^ text.charCodeAt(i), 3266489917) >>> 0;
    }
    return `v1:${signals.length}:${a.toString(16)}:${b.toString(16)}`;
  }

  static async checkAll(onResult: (row: FollowUpdate) => void = (row: FollowUpdate): void => {},
    shouldContinue: () => boolean = (): boolean => true): Promise<void> {
    if (FollowUpdates.checking) { throw new Error('已有手动追更检查在执行'); }
    FollowUpdates.checking = true;
    try {
      const rows = await FollowUpdatesDao.list();
      let index = 0;
      const worker = async (): Promise<void> => {
        while (shouldContinue() && index < rows.length) {
          const row = rows[index++];
          let fingerprint = '';
          let failure = '';
          const scope = AuthLogScope.enter('follow-manual-read');
          try {
            const source = SourceManager.find(row.sourceKey);
            if (source === undefined || source.loadComicInfo === undefined) { failure = '原始漫画源不可用或未提供详情接口'; }
            else {
              const result = await source.loadComicInfo(row.comicId);
              if (result.error) { failure = '详情检查失败，请检查源或登录状态后重试'; }
              else { fingerprint = FollowUpdates.fingerprint(result.data); }
            }
          } catch (error) { failure = '检查失败或源没有章节/有效更新日期，无法判断更新'; }
          finally { AuthLogScope.leave(scope); }
          if (!shouldContinue()) { return; }
          await FollowUpdatesDao.record(row, fingerprint, failure);
          const current = await FollowUpdatesDao.find(row.sourceKey, row.comicId);
          if (current !== undefined && shouldContinue()) { onResult(current); }
        }
      };
      // Exactly two in-flight read-only comic checks maximum.
      await Promise.all([worker(), worker()]);
    } finally { FollowUpdates.checking = false; }
  }
}
