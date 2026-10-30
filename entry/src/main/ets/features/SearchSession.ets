import { Comic } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';
import { Res } from '../model/Res';
import { Log } from '../foundation/Log';

/** Page/cursor pagination and stale-response isolation; UI mirrors this state. */
export class SearchSession {
  results: Comic[] = [];
  loading: boolean = false;
  loadingMore: boolean = false;
  searched: boolean = false;
  error: string = '';
  sourceKey: string = '';
  page: number = 0;
  ended: boolean = false;
  /** A duplicate-only page is not proof of EOF; require an explicit next attempt. */
  autoPaused: boolean = false;
  private version: number = 0;
  private source?: ComicSource;
  private keyword: string = '';
  private options: string[] = [];
  private cursor?: string;

  /** Leaving for details invalidates pending work, but preserves the result list. */
  invalidatePending(): void {
    this.version++;
    this.loading = false;
    this.loadingMore = false;
  }

  cancel(): void {
    this.version++;
    this.results = [];
    this.loading = false;
    this.loadingMore = false;
    this.searched = false;
    this.error = '';
    this.source = undefined;
    this.sourceKey = '';
    this.page = 0;
    this.cursor = undefined;
    this.options = [];
    this.ended = false;
    this.autoPaused = false;
  }

  async start(source: ComicSource, keyword: string, options: string[] = []): Promise<boolean> {
    this.cancel();
    this.source = source;
    this.sourceKey = source.key;
    this.keyword = keyword;
    this.options = options.slice();
    this.searched = true;
    this.loading = true;
    return await this.fetch(false, this.version);
  }

  async more(): Promise<boolean> {
    if (this.loading || this.loadingMore || this.ended || !this.searched || this.source === undefined) {
      return false;
    }
    this.loadingMore = true;
    return await this.fetch(true, this.version);
  }

  private async fetch(append: boolean, version: number): Promise<boolean> {
    const source = this.source;
    const search = source?.search;
    const trace = `search-${Date.now()}-${version}-${this.page + 1}`;
    Log.audit(trace, '请求到达', `源=${this.sourceKey}；页=${this.page + 1}；追加=${append}；关键词内容不落盘`);
    try {
      if (source === undefined || search?.loadPage === undefined) {
        throw new Error('当前源不支持搜索');
      }
      let result: Res<Comic[]>;
      if (append && search.cursorOnly) {
        if (this.cursor === undefined || search.loadNext === undefined) {
          this.ended = true;
          return true;
        }
        result = await search.loadNext(this.keyword, this.cursor, this.options.slice());
      } else {
        result = await search.loadPage(this.keyword, this.page + 1, this.options.slice());
      }
      if (version !== this.version) {
        Log.audit(trace, '结果拦截', '查询或源已切换，丢弃旧请求，不更新页面');
        return false;
      }
      if (result.error) {
        throw new Error(result.errorMessage ?? '搜索失败');
      }
      const items = result.dataOrNull;
      if (items === undefined) { throw new Error('源未返回有效列表，请重试'); }
      let added = 0;
      const merged: Comic[] = append ? this.results.slice() : [];
      for (const comic of items) {
        if (comic.id.length === 0) { throw new Error('列表缺少稳定漫画ID，请重试'); }
        if (comic.sourceKey.length === 0) { comic.sourceKey = source.key; }
        if (!merged.some((existing: Comic) => existing.id === comic.id && existing.sourceKey === comic.sourceKey)) {
          merged.push(comic);
          added++;
        }
      }
      this.results = merged;
      this.page++;
      this.error = '';
      const next = result.subDataString;
      const repeated = append && search.cursorOnly && next === this.cursor;
      this.cursor = next;
      // A positive finite maxPage is authoritative. 0 means unknown (not EOF),
      // and neither a short page nor a duplicate-only page proves the last page.
      const max = next === undefined ? NaN : Number(next);
      this.ended = items.length === 0 || repeated ||
        (search.cursorOnly ? next === undefined || next.length === 0 :
          Number.isFinite(max) && max > 0 && this.page >= max);
      this.autoPaused = !this.ended && added === 0;
      Log.audit(trace, '响应返回', `接收=${items.length}；新增=${added}；累计=${merged.length}；结束=${this.ended}`);
      return true;
    } catch (error) {
      if (version !== this.version) {
        Log.audit(trace, '结果拦截', '页面已切换，丢弃旧异常');
        return false;
      }
      this.error = error instanceof Error ? error.message : String(error);
      Log.audit(trace, '异常', '搜索或分页失败；保留已显示结果及游标，可以重试');
      return true;
    } finally {
      if (version === this.version) {
        this.loading = false;
        this.loadingMore = false;
      }
    }
  }
}
