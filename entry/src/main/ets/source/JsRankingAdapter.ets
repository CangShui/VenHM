import { Comic, parseComicList } from '../model/Comic';
import { Res } from '../model/Res';
import { JsEngine } from './JsEngine';
import { RankingData } from './RankingData';
import { Log } from '../foundation/Log';
import { SourceFailure } from '../features/SourceFailure';

/** Fixed upstream 7110c19: no loadNext alias and no code generated from raw labels. */
export class JsRankingAdapter {
  static create(key: string, scriptPath: string, hasPage: boolean, hasCursor: boolean): RankingData {
    const data = new RankingData();
    const target = `ComicSource.sources[${JSON.stringify(key)}].categoryComics.ranking`;
    data.optionsLoader = async (): Promise<Res<Map<string, string>>> => {
      try {
        const raw = await JsEngine.callJson(`${target}.options`, scriptPath, `ranking-options-${Date.now()}`);
        return Res.ok<Map<string, string>>(JsRankingAdapter.parseOptions(raw));
      } catch (error) {
        Log.audit('ranking-options', '排行选项异常', '元数据缺失/格式错误/桥接失败；不打印源正文');
        return Res.fail<Map<string, string>>('排行选项加载失败，请检查源声明后重试');
      }
    };
    if (hasPage) {
      data.load = (option: string, page: number): Promise<Res<Comic[]>> =>
        JsRankingAdapter.request(`${target}.load(${JSON.stringify(option)},${page})`, key, scriptPath, false);
    } else if (hasCursor) {
      data.loadWithNext = (option: string, next: string | null): Promise<Res<Comic[]>> =>
        JsRankingAdapter.request(`${target}.loadWithNext(${JSON.stringify(option)},${JSON.stringify(next)})`, key, scriptPath, true);
    }
    return data;
  }

  /** Split only the first dash; Map preserves upstream order and last duplicate value. */
  static parseOptions(raw: Object | undefined | null): Map<string, string> {
    if (!Array.isArray(raw)) { throw new Error('RANKING_OPTIONS_NOT_ARRAY'); }
    const options = new Map<string, string>();
    for (const item of raw as Object[]) {
      if (typeof item !== 'string') { throw new Error('RANKING_OPTION_NOT_STRING'); }
      const value = item as string;
      const dash = value.indexOf('-');
      if (value.length === 0 || dash < 0) { continue; }
      options.set(value.substring(0, dash), value.substring(dash + 1));
    }
    if (options.size === 0) { throw new Error('RANKING_OPTIONS_EMPTY'); }
    return options;
  }

  private static async request(code: string, key: string, scriptPath: string, cursor: boolean): Promise<Res<Comic[]>> {
    const trace = `ranking-request-${Date.now()}`;
    try {
      const raw = await JsEngine.callJson(code, scriptPath, trace);
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        throw new Error('RANKING_RESULT_NOT_OBJECT');
      }
      const record = raw as Record<string, Object>;
      const list = record['comics'];
      if (!Array.isArray(list) || !(list as Object[]).every((item: Object) =>
        item !== null && typeof item === 'object' && !Array.isArray(item))) {
        throw new Error('RANKING_COMICS_NOT_ARRAY');
      }
      const comics: Comic[] = parseComicList(list, key);
      if (comics.some((comic: Comic) => comic.id.length === 0)) { throw new Error('RANKING_COMIC_ID_EMPTY'); }
      const sub = cursor ? record['next'] : record['maxPage'];
      if (sub !== undefined && sub !== null) {
        if (cursor && typeof sub !== 'string') { throw new Error('RANKING_CURSOR_NOT_STRING'); }
        if (!cursor && (typeof sub !== 'number' || !Number.isFinite(sub as number) ||
          (sub as number) < 1 || Math.floor(sub as number) !== sub)) { throw new Error('RANKING_MAX_PAGE_INVALID'); }
      }
      return Res.ok<Comic[]>(comics, sub === null ? undefined : sub);
    } catch (error) {
      Log.audit(trace, '排行请求异常', '脚本、返回结构或桥接失败；游标/标签/服务器正文不落盘');
      return Res.fail<Comic[]>(`排行请求失败：${SourceFailure.message(error)}`);
    }
  }
}
