import { router } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { Res } from '../model/Res';
import { CategoryComicsParams, ComicDetailsParams } from '../model/RouteParams';
import { CategoryComicsOptions, ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { ComicCell, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { SourceFailure } from '../features/SourceFailure';
import { UiTheme, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Source-locked results for both explicit categories and source tag search targets. */
@Entry
@Component
struct CategoryComicsPage {
  @State label: string = '';
  @State comics: Comic[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State currentPage: number = 0;
  @State ended: boolean = false;
  @State options: CategoryComicsOptions[] = [];
  @State optionValues: string[] = [];
  private params: CategoryComicsParams = { sourceKey: '', label: '', page: '' };
  private disposed: boolean = false;
  private version: number = 0;
  private cursor?: string;

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.params = router.getParams() as CategoryComicsParams;
    this.label = this.params?.label ?? '';
    this.load(1, true);
  }

  aboutToDisappear(): void { this.disposed = true; this.version++; this.loading = false; }

  onPageHide(): void { this.disposed = true; this.version++; this.loading = false; }

  onPageShow(): void {
    const wasHidden = this.disposed; this.disposed = false;
    if (wasHidden && this.comics.length === 0) { this.load(1, true); }
  }

  private current(version: number): boolean { return !this.disposed && version === this.version; }

  private async load(page: number, initializeOptions: boolean = false): Promise<void> {
    if (page > 1 && (this.loading || this.ended)) { return; }
    const version = ++this.version;
    const trace = `category-results-${Date.now()}-${version}`;
    // Set loading synchronously before initialization/options/source callbacks.
    this.loading = true; this.error = '';
    if (page === 1) { this.comics = []; this.currentPage = 0; this.cursor = undefined; this.ended = false; }
    Log.audit(trace, '分类标签加载到达', `页=${page}；目标类型=${this.params?.page}；参数/正文不落盘`);
    try {
      await AppInit.init();
      if (!this.current(version)) { return; }
      const source = SourceManager.find(this.params?.sourceKey ?? '');
      if (source === undefined) { throw new Error('原始漫画源已不可用；不会改用当前选中的其他源'); }
      let result: Res<Comic[]>;
      if (this.params.page === 'category') {
        const data = source.categoryComics;
        const category = this.params.category;
        if (data?.load === undefined) { throw new Error(`${source.name} 不支持分类列表`); }
        if (category === undefined || category.length === 0) { throw new Error('分类目标参数为空'); }
        if (initializeOptions) {
          let options = data.options ?? [];
          if (data.optionsLoader !== undefined) {
            const loaded = await data.optionsLoader(category, this.params.param);
            if (!this.current(version)) { return; }
            if (loaded.error || loaded.dataOrNull === undefined) { throw new Error(`分类选项加载失败：${SourceFailure.message(loaded.errorMessage)}（诊断 ${trace}）`); }
            options = loaded.dataOrNull;
          }
          this.options = options.filter((option: CategoryComicsOptions) =>
            !option.notShowWhen.includes(category) && (option.showWhen === undefined || option.showWhen.includes(category)));
          const initial = this.params.options ?? [];
          if (this.options.some((option: CategoryComicsOptions) => option.options.size === 0)) {
            throw new Error('源提供的分类选项为空，请重试');
          }
          if (initial.length > 0 && (initial.length !== this.options.length ||
            this.options.some((option: CategoryComicsOptions, index: number) => !option.options.has(initial[index])))) {
            throw new Error('源提供的初始分类选项无效；不会静默替换为其他选项');
          }
          this.optionValues = initial.length > 0 ? initial.slice() :
            this.options.map((option: CategoryComicsOptions) => Array.from(option.options.keys())[0] ?? '');
        }
        result = await data.load(category, this.params.param, this.optionValues.slice(), page);
      } else if (this.params.page === 'search') {
        const search = source.search;
        const keyword = this.params.keyword;
        if (search?.loadPage === undefined) { throw new Error(`${source.name} 不支持标签搜索`); }
        if (keyword === undefined || (keyword.length === 0 && (this.params.options?.length ?? 0) === 0)) {
          throw new Error('搜索目标文本和筛选选项均为空');
        }
        if (page > 1 && search.cursorOnly) {
          if (this.cursor === undefined || search.loadNext === undefined) { throw new Error('源未提供下一页游标'); }
          result = await search.loadNext(keyword, this.cursor, this.params.options?.slice() ?? []);
        } else { result = await search.loadPage(keyword, page, this.params.options?.slice() ?? []); }
      } else { throw new Error('源提供的目标类型不受支持'); }
      if (!this.current(version)) { Log.audit(trace, '分类结果拦截', '页面已变化；丢弃旧结果'); return; }
      if (result.error) { throw new Error(`分类/标签加载失败：${SourceFailure.message(result.errorMessage)}（诊断 ${trace}）`); }
      const items = result.dataOrNull;
      if (items === undefined || items.length === 0) {
        if (page === 1) { throw new Error('该分类/标签返回空数据，请重试'); }
        this.ended = true;
        Log.audit(trace, '分类响应返回', '后续页为空，列表结束'); return;
      }
      const merged: Comic[] = page === 1 ? [] : this.comics.slice();
      let added: number = 0;
      for (const comic of items) {
        if (comic.id.length === 0) { throw new Error('列表缺少稳定漫画ID，请重试'); }
        if (comic.sourceKey.length === 0) { comic.sourceKey = source.key; }
        if (!merged.some((existing: Comic) => existing.sourceKey === comic.sourceKey && existing.id === comic.id)) {
          merged.push(comic); added++;
        }
      }
      const next = result.subDataString;
      const max = next !== undefined ? Number(next) : NaN;
      this.ended = added === 0 || (this.params.page === 'search' && source.search?.cursorOnly
        ? next === undefined || next.length === 0 || next === this.cursor
        : !isNaN(max) && page >= max);
      this.cursor = next; this.currentPage = page; this.comics = merged;
      Log.audit(trace, '分类响应返回', `接收=${items.length}；新增=${added}；已到末页=${this.ended}`);
    } catch (error) {
      if (!this.current(version)) { return; }
      this.error = error instanceof Error ? error.message : '分类/标签加载失败，请重试';
      Log.audit(trace, '分类标签异常', '能力缺失、选项/列表空值或回调失败；保留已加载结果；不记录异常正文');
    } finally {
      if (this.current(version)) { this.loading = false; }
    }
  }

  private retry(): void { this.load(this.comics.length > 0 ? this.currentPage + 1 : 1, this.comics.length === 0); }

  private openComic(comic: Comic): void {
    const key = comic.sourceKey || this.params.sourceKey;
    if (this.disposed || SourceManager.find(key) === undefined) { this.error = '该结果的原始源已不可用'; return; }
    const params: ComicDetailsParams = { sourceKey: key, comicId: comic.id, title: comic.title, cover: comic.cover };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch((error: Object) => {
      if (!this.disposed) { this.error = '无法打开漫画详情，请重试'; }
      Log.audit('category-detail', '分类详情跳转异常', '不记录异常正文');
    });
  }

  build() {
    Column() {
      UiPageHeader({ title: this.label || '分类/标签结果', subtitle: '当前漫画源的分类结果', onBack: () => { router.back(); } })
      Column({ space: 8 }) {
      ForEach(this.options, (option: CategoryComicsOptions, index: number) => {
        Row({ space: 8 }) {
          Text(option.label).fontSize(13).fontColor(UiTheme.secondary)
          Select(Array.from(option.options.values()).map((label: string) => {
            const select: SelectOption = { value: label }; return select;
          }))
            .selected(Array.from(option.options.keys()).indexOf(this.optionValues[index]))
            .value(option.options.get(this.optionValues[index]) ?? '')
            .layoutWeight(1).height(48).font({ size: 14 }).fontColor(UiTheme.ink).backgroundColor(UiTheme.surface).borderRadius(14).enabled(!this.loading)
            .onSelect((selected: number) => {
              const values = this.optionValues.slice();
              values[index] = Array.from(option.options.keys())[selected];
              this.optionValues = values; this.load(1);
            })
        }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 18, right: 12, top: 6, bottom: 6 })
          .backgroundColor(UiTheme.surface).borderRadius(20)
      }, (option: CategoryComicsOptions, index: number) => `${index}:${option.label}`)
      if (this.loading && this.comics.length === 0) {
        LoadingView({ message: '正在加载分类/标签…' }).layoutWeight(1)
      } else if (this.error.length > 0 && this.comics.length === 0) {
        ErrorView({ message: this.error, onRetry: () => { this.retry(); } }).layoutWeight(1)
      } else {
        Grid() {
          ForEach(this.comics, (comic: Comic) => {
            GridItem() {
              ComicCell({ title: comic.title, subtitle: comic.subtitle, coverUrl: comic.cover,
                sourceKey: comic.sourceKey, comicId: comic.id, onTapCell: () => { this.openComic(comic); } })
            }
          }, (comic: Comic) => `${comic.sourceKey}@${comic.id}`)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(12).rowsGap(18).padding({ top: 12, bottom: 12 }).layoutWeight(1).width('100%')
        if (this.error.length > 0) {
          Text(this.error).fontSize(13).fontColor(UiTheme.danger).lineHeight(20).padding(14).width('100%').backgroundColor(UiTheme.dangerSoft).borderRadius(16)
          Button('重试').attributeModifier(UiStyles.secondary).onClick(() => { this.retry(); })
        }
        Button(this.loading ? '加载中…' : (this.ended ? '已到末页' : '加载更多')).attributeModifier(UiStyles.primary).margin({ top: 8, bottom: 16 })
          .enabled(!this.loading && !this.ended).onClick(() => { this.load(this.currentPage + 1); })
      }
      }.width('100%').layoutWeight(1).padding({ left: UiTheme.gutter, right: UiTheme.gutter })
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
