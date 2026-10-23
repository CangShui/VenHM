import { Comic } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';

/** Source-locked, manually paginated read session. Mutations live only in explicit UI actions. */
export class NetworkFavoritesSession {
  source?: ComicSource;
  folders: Map<string, string> = new Map<string, string>();
  folder?: string;
  results: Comic[] = [];
  page: number = 0;
  next: string | null = null;
  ended: boolean = false;
  loading: boolean = false;
  error: string = '';
  private generation: number = 0;
  private cursors: Set<string> = new Set<string>();

  invalidate(): void { this.generation++; this.loading = false; }

  async start(source: ComicSource | undefined): Promise<void> {
    this.invalidate();
    this.source = source;
    this.results = [];
    this.folders = new Map<string, string>();
    this.folder = undefined;
    this.error = '';
    if (source === undefined) { this.error = '原始漫画源已不可用；不会自动切换其他源'; return; }
    if (!source.isLogged) { this.error = '请先登录此漫画源，再点击刷新'; return; }
    const data = source.favoriteData;
    if (data === undefined || (data.loadComic === undefined && data.loadNext === undefined)) {
      this.error = '此漫画源未声明可用的网络收藏列表'; return;
    }
    const token = this.generation;
    if (data.multiFolder) {
      if (data.loadFolders === undefined) { this.error = '源声明多收藏夹，但没有 loadFolders'; return; }
      this.loading = true;
      try {
        const result = await data.loadFolders();
        if (token !== this.generation) { return; }
        if (result.error) { throw new Error(result.errorMessage); }
        this.folders = result.data;
        if (this.folders.size === 0) { this.error = '此账号没有可用的远端收藏夹'; this.ended = true; return; }
        this.folder = Array.from(this.folders.keys())[0];
      } catch (error) {
        if (token === this.generation) { this.error = '收藏夹加载失败；请检查登录状态后重试'; }
        return;
      } finally { if (token === this.generation) { this.loading = false; } }
    }
    if (token === this.generation) { await this.select(this.folder); }
  }

  async select(folder?: string): Promise<void> {
    this.invalidate();
    this.folder = folder;
    this.results = [];
    this.page = 0;
    this.next = null;
    this.cursors.clear();
    this.ended = false;
    this.error = '';
    await this.more();
  }

  async more(): Promise<void> {
    if (this.loading || this.ended) { return; }
    const source = this.source;
    const data = source?.favoriteData;
    if (source === undefined || !source.isLogged) { this.error = '请先登录此漫画源'; return; }
    if (data === undefined || (data.loadComic === undefined && data.loadNext === undefined)) { this.error = '源没有网络收藏列表'; return; }
    const token = ++this.generation;
    this.loading = true;
    this.error = '';
    try {
      const cursor = data.loadComic === undefined;
      const result = data.loadComic !== undefined ? await data.loadComic(this.page + 1, this.folder)
        : await data.loadNext!(this.next, this.folder);
      if (token !== this.generation) { return; }
      if (result.error) { this.error = result.errorMessage ?? '网络收藏加载失败'; return; }
      const rows = result.data;
      if (rows.some((row: Comic) => row.sourceKey !== source.key || row.id.length === 0)) { throw new Error('SOURCE_MISMATCH'); }
      const seen = new Set<string>(this.results.map((row: Comic) => row.id));
      const added: Comic[] = [];
      for (const row of rows) { if (!seen.has(row.id)) { seen.add(row.id); added.push(row); } }
      this.results = this.results.concat(added);
      this.page++;
      if (cursor) {
        const next = typeof result.subData === 'string' && result.subData.length > 0 ? result.subData : null;
        this.ended = next === null || this.cursors.has(next) || rows.length === 0 || added.length === 0;
        if (next !== null) { this.cursors.add(next); }
        this.next = next;
      } else {
        this.ended = (typeof result.subData === 'number' && this.page >= result.subData) || rows.length === 0 || added.length === 0;
      }
    } catch (error) { if (token === this.generation) { this.error = '网络收藏加载失败；已加载的记录保留，可重试同一页'; } }
    finally { if (token === this.generation) { this.loading = false; } }
  }
}
