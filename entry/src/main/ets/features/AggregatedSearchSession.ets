import { Comic } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';
import { SearchFilterPolicy } from './SearchFilterPolicy';
import { SourceFailure } from './SourceFailure';
import { Log } from '../foundation/Log';

export class AggregatedSearchGroup {
  sourceKey: string = '';
  sourceName: string = '';
  status: string = 'queued';
  results: Comic[] = [];
  error: string = '';
  uiVersion: number = 0;
}

class AggregatedSearchTask {
  run: () => Promise<void>;
  discarded: () => void;
  constructor(run: () => Promise<void>, discarded: () => void = (): void => {}) {
    this.run = run; this.discarded = discarded;
  }
}

/** Starts every selected source's first page without an artificial concurrency
 * ceiling. Restart/cancel invalidates old results; no separate search window. */
export class AggregatedSearchSession {
  groups: AggregatedSearchGroup[] = [];
  keyword: string = '';
  running: boolean = false;
  private version: number = 0;
  private changed?: () => void;
  private sources: Map<string, ComicSource> = new Map<string, ComicSource>();
  private tasks: AggregatedSearchTask[] = [];
  private remaining: number = 0;
  private complete?: () => void;

  cancel(): void {
    this.version++;
    const discarded = this.tasks; this.tasks = [];
    for (const task of discarded) { task.discarded(); }
    this.remaining = 0; this.running = false;
    for (const group of this.groups) { if (group.status === 'queued' || group.status === 'loading') { group.status = 'cancelled'; } }
    this.changed = undefined;
    const done = this.complete; this.complete = undefined; done?.();
  }

  start(sources: ComicSource[], keyword: string, changed?: () => void): Promise<void> {
    this.cancel();
    const version = this.version;
    this.keyword = keyword; this.groups = []; this.sources.clear(); this.changed = changed;
    const seen = new Set<string>();
    for (const source of sources) {
      if (seen.has(source.key) || source.search?.loadPage === undefined) { continue; }
      seen.add(source.key); this.sources.set(source.key, source);
      const group = new AggregatedSearchGroup(); group.sourceKey = source.key; group.sourceName = source.name;
      this.groups.push(group);
    }
    this.remaining = this.groups.length; this.running = this.remaining > 0;
    if (!this.running) { this.notify(version); return Promise.resolve(); }
    const result = new Promise<void>((resolve: () => void) => { this.complete = resolve; });
    for (const group of this.groups) {
      const source = this.sources.get(group.sourceKey);
      if (source !== undefined) { this.tasks.push(new AggregatedSearchTask(() => this.fetch(source, group, keyword, version))); }
    }
    this.notify(version); this.pump(); return result;
  }

  async retry(sourceKey: string): Promise<void> {
    const group = this.groups.find((entry: AggregatedSearchGroup) => entry.sourceKey === sourceKey);
    const source = this.sources.get(sourceKey);
    if (group === undefined || source === undefined || group.status === 'loading' || group.status === 'queued') { return; }
    group.status = 'queued'; group.error = ''; this.remaining++; this.running = true;
    const version = this.version;
    await new Promise<void>((resolve: () => void) => {
      this.tasks.push(new AggregatedSearchTask(async () => {
        try { await this.fetch(source, group, this.keyword, version); } finally { resolve(); }
      }, resolve));
      this.notify(version); this.pump();
    });
  }

  private notify(version: number): void {
    if (version !== this.version) { return; }
    try { this.changed?.(); }
    catch (error) { Log.audit('aggregated-search-ui', '聚合界面通知异常', '源请求结果保留；未输出关键词/响应/错误正文'); }
  }
  private pump(): void {
    // No artificial concurrency ceiling: every selected source is queried at once.
    while (this.tasks.length > 0) {
      const task = this.tasks.shift();
      if (task === undefined) { break; }
      task.run().catch(() => {}).finally(() => { this.pump(); });
    }
  }
  private async fetch(source: ComicSource, group: AggregatedSearchGroup, keyword: string, version: number): Promise<void> {
    if (version !== this.version) { return; }
    group.status = 'loading'; this.notify(version);
    try {
      const search = source.search;
      if (search?.loadPage === undefined) { throw new Error('搜索能力已不可用'); }
      let metadata = search.searchOptions ?? [];
      if (search.optionsLoader !== undefined) {
        const loaded = await search.optionsLoader();
        if (version !== this.version) { return; }
        if (loaded.error || loaded.dataOrNull === undefined) { throw new Error('筛选配置不可用'); }
        metadata = loaded.dataOrNull;
      }
      const options = SearchFilterPolicy.defaults(metadata);
      const result = await search.loadPage(keyword, 1, options);
      if (version !== this.version) { return; }
      if (result.error) { throw new Error(result.errorMessage ?? '搜索失败'); }
      const rows = result.dataOrNull ?? [];
      const valid: Comic[] = [];
      for (const comic of rows) {
        if (comic.sourceKey !== source.key || comic.id.length === 0) { throw new Error('源返回了不匹配的漫画身份'); }
        if (!valid.some((old: Comic) => old.id === comic.id)) { valid.push(comic); }
      }
      group.results = valid.slice(0, 12); group.status = valid.length > 0 ? 'ready' : 'empty'; group.error = '';
    } catch (error) {
      if (version !== this.version) { return; }
      group.results = []; group.status = 'failed'; group.error = SourceFailure.message(error);
    } finally {
      if (version === this.version) {
        this.remaining--; this.running = this.remaining > 0; this.notify(version);
        if (!this.running) { const done = this.complete; this.complete = undefined; done?.(); }
      }
    }
  }
}
