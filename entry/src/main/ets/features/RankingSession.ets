import { Comic } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';
import { RankingData } from '../source/RankingData';
import { Res } from '../model/Res';
import { SourceFailure } from './SourceFailure';
import { Log } from '../foundation/Log';

/** One source-locked ranking; owns option changes, pagination and stale responses. */
export class RankingSession {
  sourceKey: string = '';
  options: Map<string, string> = new Map<string, string>();
  option: string = '';
  results: Comic[] = [];
  loading: boolean = false;
  error: string = '';
  page: number = 0;
  ended: boolean = false;
  private version: number = 0;
  private data?: RankingData;
  private cursor: string | null = null;
  private seenCursors: string[] = [];
  private initialized: boolean = false;

  /** Called on hide/disappear; preserve committed state, invalidate pending finally. */
  invalidatePending(): void { this.version++; this.loading = false; }

  async start(source: ComicSource): Promise<boolean> {
    const version = ++this.version;
    this.sourceKey = source.key;
    this.data = source.categoryComics?.rankingData;
    this.options = new Map<string, string>();
    this.option = ''; this.initialized = false; this.reset(); this.loading = true;
    try {
      const data = this.data;
      if (data === undefined) { throw new Error('该源未提供排行榜'); }
      if (data.load === undefined && data.loadWithNext === undefined) { throw new Error('该源未提供排行加载方法（load/loadWithNext）'); }
      let options = data.options;
      if (data.optionsLoader !== undefined) {
        const loaded = await data.optionsLoader();
        if (version !== this.version) { return false; }
        if (loaded.error || loaded.dataOrNull === undefined) { throw new Error('排行选项加载失败，请重试'); }
        options = loaded.dataOrNull;
      }
      if (options.size === 0) { throw new Error('该源的排行选项为空，请重试'); }
      this.options = new Map<string, string>(options);
      this.option = Array.from(options.keys())[0];
      this.initialized = true;
      return await this.fetch(version);
    } catch (error) {
      if (version !== this.version) { return false; }
      this.error = error instanceof Error ? error.message : '排行初始化失败，请重试';
      return true;
    } finally { if (version === this.version) { this.loading = false; } }
  }

  async select(option: string): Promise<boolean> {
    if (!this.initialized || !this.options.has(option) || option === this.option) { return false; }
    const version = ++this.version;
    this.option = option; this.reset(); this.loading = true;
    return await this.fetch(version);
  }

  async more(): Promise<boolean> {
    if (this.loading || this.ended || !this.initialized) { return false; }
    this.loading = true;
    return await this.fetch(++this.version);
  }

  /** Retry does not clear committed rows/page/cursor, including failed second pages. */
  async retry(): Promise<boolean> {
    if (this.loading || !this.initialized) { return false; }
    if (this.ended && this.results.length === 0) { this.reset(); }
    this.loading = true;
    return await this.fetch(++this.version);
  }

  get ready(): boolean { return this.initialized; }

  private reset(): void {
    this.results = []; this.error = ''; this.page = 0; this.cursor = null;
    this.seenCursors = []; this.ended = false;
  }

  private async fetch(version: number): Promise<boolean> {
    const data = this.data;
    const page = this.page + 1;
    const option = this.option;
    const trace = `ranking-${Date.now()}-${version}-${page}`;
    this.error = '';
    Log.audit(trace, '排行请求到达', `页=${page}；不记录选项/游标内容；不替换原始源`);
    try {
      if (data === undefined) { throw new Error('RANKING_DATA_MISSING'); }
      let result: Res<Comic[]>;
      if (data.load !== undefined) { result = await data.load(option, page); }
      else if (data.loadWithNext !== undefined) { result = await data.loadWithNext(option, this.cursor); }
      else { throw new Error('RANKING_LOADER_MISSING'); }
      if (version !== this.version) { return false; }
      if (result.error) { throw new Error(result.errorMessage ?? '排行请求失败'); }
      const items = result.dataOrNull;
      if (items === undefined) { throw new Error('RANKING_COMICS_MISSING'); }
      if (items.some((comic: Comic) => comic.sourceKey !== this.sourceKey || comic.id.length === 0)) {
        throw new Error('RANKING_RESULT_SOURCE_MISMATCH');
      }
      const merged = this.results.slice();
      let added = 0;
      for (const comic of items) {
        if (!merged.some((existing: Comic) => existing.sourceKey === comic.sourceKey && existing.id === comic.id)) {
          merged.push(comic); added++;
        }
      }
      const next = typeof result.subData === 'string' ? result.subData as string : null;
      const cursorMode = data.load === undefined;
      const loop = cursorMode && next !== null && this.seenCursors.includes(next);
      const max = typeof result.subData === 'number' ? result.subData as number : undefined;
      this.results = merged; this.page = page; this.cursor = next;
      this.ended = items.length === 0 || added === 0 || (cursorMode ? next === null || next.length === 0 || loop : max !== undefined && page >= max);
      if (cursorMode && next !== null) { this.seenCursors.push(next); }
      Log.audit(trace, '排行响应返回', `接收=${items.length}；新增=${added}；累计=${merged.length}；结束=${this.ended}`);
      return true;
    } catch (error) {
      if (version !== this.version) { return false; }
      this.error = `排行加载失败：${SourceFailure.message(error)}（诊断 ${trace}）`;
      Log.audit(trace, '排行异常', '保留已提交结果/页码/游标以便重试；正文不落盘');
      return true;
    } finally {
      // An old option/source request must never hide the current request's spinner.
      if (version === this.version) { this.loading = false; }
    }
  }
}
