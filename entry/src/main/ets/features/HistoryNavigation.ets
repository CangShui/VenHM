import { router } from '@kit.ArkUI';
import { ComicType } from '../model/ComicType';
import { ComicDetailsParams, ReaderParams } from '../model/RouteParams';
import { History } from '../storage/HistoryDao';
import { SourceManager } from '../source/SourceManager';

/** Never guess the first installed source for an unresolvable history record. */
export class HistoryNavigation {
  static sourceKey(item: History): string | undefined {
    return HistoryNavigation.resolveKey(item, SourceManager.all().map((source) => source.key));
  }

  /** Pure resolver, also exercised by the offline usability tests. */
  static resolveKey(item: History, installedKeys: string[]): string | undefined {
    if (item.storedSourceKey.length > 0) {
      if (ComicType.fromKey(item.storedSourceKey).value !== item.type.value) {
        return undefined;
      }
      return installedKeys.indexOf(item.storedSourceKey) >= 0 ? item.storedSourceKey : undefined;
    }
    const matches = installedKeys.filter((key: string) => ComicType.fromKey(key).value === item.type.value);
    // Legacy hashes are only accepted when exactly one registered key matches.
    return matches.length === 1 ? matches[0] : undefined;
  }

  static sourceName(item: History): string {
    const key = HistoryNavigation.sourceKey(item);
    if (key === undefined) {
      return `源不可用（${item.storedSourceKey || item.type.value}）`;
    }
    return SourceManager.find(key)?.name ?? key;
  }

  private static requireSource(item: History): string {
    const key = HistoryNavigation.sourceKey(item);
    if (key === undefined) {
      throw new Error('原漫画源未安装或无法识别，请先恢复对应源；历史记录已保留');
    }
    return key;
  }

  static async openDetails(item: History): Promise<void> {
    const params: ComicDetailsParams = {
      sourceKey: HistoryNavigation.requireSource(item),
      comicId: item.id, title: item.title, cover: item.cover
    };
    await router.pushUrl({ url: 'pages/ComicDetailsPage', params: params });
  }

  static async resume(item: History): Promise<void> {
    const params: ReaderParams = {
      sourceKey: HistoryNavigation.requireSource(item),
      comicId: item.id, title: item.title, cover: item.cover,
      epId: item.epId, epIndex: item.ep, page: item.page, resume: true
    };
    await router.pushUrl({ url: 'pages/ReaderPage', params: params });
  }
}
