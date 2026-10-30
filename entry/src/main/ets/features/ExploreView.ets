import { UiTheme, UiIcon } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { ComicDetailsParams } from '../model/RouteParams';
import { ComicSource, ExplorePageData, ExplorePageType } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { Res } from '../model/Res';
import { ComicCell, EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { SelectedSource } from './SelectedSource';

/**
 * Discovery tab - shows a source's content directly, without searching.
 *
 * Dart original: lib/features/discovery/explore_page.dart plus the 发现 entry on
 * the home page. VeneraNext renders one section per `ComicSource.explorePages`
 * entry (title + list type) and loads page 1 immediately, which is the behaviour
 * restored here.
 */
@Component
export struct ExploreView {
  @State sourceNames: string[] = [];
  @State sourceIndex: number = 0;
  @State pageTitles: string[] = [];
  @State pageIndex: number = 0;
  @State comics: Comic[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State currentPage: number = 0;
  @State hasMore: boolean = true;
  private autoPaused: boolean = false;
  @State ready: boolean = false;

  @State selectedSourceKey: string = '';
  private sourceKeys: string[] = [];
  private disposed: boolean = false;
  private version: number = 0;
  private subscription: number = 0;
  private initialized: boolean = false;
  private nextCursor?: string;

  aboutToAppear(): void {
    this.disposed = false;
    SelectedSource.unsubscribe(this.subscription);
    this.ready = false;
    const version = ++this.version;
    AppInit.init().then(() => {
      if (this.disposed || version !== this.version) { return; }
      this.selectedSourceKey = SelectedSource.initialize();
      this.ready = true; this.initialized = true;
      this.subscription = SelectedSource.subscribe((key: string) => {
        if (!this.disposed) { this.selectedSourceKey = key; this.reloadSources(); }
      });
      this.reloadSources();
    }).catch((error: Object) => {
      if (this.disposed || version !== this.version) { return; }
      this.error = '初始化失败，请重试'; this.ready = true;
      Log.audit('explore-init', '初始化异常', '不记录异常正文');
    });
  }

  aboutToDisappear(): void {
    this.disposed = true; this.version++; this.loading = false;
    SelectedSource.unsubscribe(this.subscription);
  }

  private currentSource(): ComicSource | undefined {
    return SourceManager.find(this.selectedSourceKey);
  }

  private currentPageData(): ExplorePageData | undefined {
    const source = this.currentSource();
    if (source === undefined || this.pageIndex >= source.explorePages.length) {
      return undefined;
    }
    return source.explorePages[this.pageIndex];
  }

  private reloadSources(): void {
    if (!this.initialized) { this.aboutToAppear(); return; }
    const list = SourceManager.all();
    this.sourceKeys = list.map((source: ComicSource) => source.key);
    this.sourceNames = list.map((source: ComicSource) => source.name);
    this.sourceIndex = this.sourceKeys.indexOf(this.selectedSourceKey);
    this.loadPageTitles();
    this.loadFirstPage();
  }

  private loadPageTitles(): void {
    const source = this.currentSource();
    const titles: string[] = [];
    if (source !== undefined) {
      for (let i = 0; i < source.explorePages.length; i++) {
        titles.push(source.explorePages[i].title);
      }
    }
    this.pageTitles = titles;
    this.pageIndex = 0;
  }

  private loadFirstPage(): void {
    if (!this.initialized) { this.aboutToAppear(); return; }
    this.comics = [];
    this.currentPage = 0;
    this.hasMore = true;
    this.autoPaused = false;
    this.nextCursor = undefined;
    this.loadPage(1);
  }

  private async loadPage(page: number): Promise<void> {
    if (this.disposed || page < 1 ||
      (page > 1 && (this.loading || !this.hasMore || this.currentPage < 1 || page !== this.currentPage + 1))) { return; }
    const sourceKey = this.selectedSourceKey;
    const pageIndex = this.pageIndex;
    const version = ++this.version;
    if (page === 1) {
      this.comics = []; this.currentPage = 0; this.nextCursor = undefined;
      this.hasMore = true; this.autoPaused = false;
    }
    const trace = `explore-${Date.now()}-${version}`;
    this.loading = true;
    this.error = '';
    Log.audit(trace, '探索加载到达', `页=${page}；参数内容不落盘`);
    try {
      const source = this.currentSource();
      const explore = this.currentPageData();
      if (source === undefined) { throw new Error('选中的源已不可用，请选择其他源'); }
      if (explore === undefined || explore.loadPage === undefined) {
        throw new Error(`选中的源 ${source.name} 不支持探索`);
      }
      let result: Res<Comic[]>;
      if (page > 1 && explore.cursorOnly) {
        if (this.nextCursor === undefined || explore.loadNext === undefined) {
          throw new Error('该探索源未提供有效下一页游标/加载能力');
        }
        result = await explore.loadNext(this.nextCursor);
      } else {
        // Parent adapter calls a cursor-only source's first loadNext(null), not page number 1.
        result = await explore.loadPage(page);
      }
      if (this.disposed || version !== this.version || sourceKey !== this.selectedSourceKey ||
        pageIndex !== this.pageIndex || source !== this.currentSource()) { return; }
      if (result.error) {
        throw new Error(this.diagnostic(result.errorMessage ?? '探索加载失败，请重试'));
      }
      const items = result.dataOrNull;
      if (items === undefined) { throw new Error('源未返回有效列表，请重试'); }
      const merged: Comic[] = page === 1 ? [] : this.comics.slice();
      let added: number = 0;
      for (const comic of items) {
        if (comic.id.length === 0) { throw new Error('列表缺少稳定漫画ID，请重试'); }
        if (comic.sourceKey.length === 0) { comic.sourceKey = source.key; }
        if (!merged.some((existing: Comic) => existing.id === comic.id && existing.sourceKey === comic.sourceKey)) {
          merged.push(comic); added++;
        }
      }
      this.comics = merged;
      this.currentPage = page;
      const next = result.subDataString;
      if (explore.cursorOnly) {
        this.hasMore = next !== undefined && next.length > 0 && next !== this.nextCursor;
        this.nextCursor = next;
      } else {
        const max = next === undefined ? NaN : Number(next);
        // 0/absent/non-finite maxPage is unknown, not a one-page contract.
        this.hasMore = !(Number.isFinite(max) && max > 0 && page >= max);
      }
      this.hasMore = this.hasMore && items.length > 0 &&
        (explore.cursorOnly || explore.type === ExplorePageType.multiPageComicList);
      this.autoPaused = this.hasMore && added === 0;
      Log.audit(trace, '探索响应返回', `条数=${items.length}；更多=${this.hasMore}`);
    } catch (error) {
      if (this.disposed || version !== this.version) { return; }
      this.error = this.diagnostic(error instanceof Error ? error.message : '探索加载失败，请重试');
      Log.audit(trace, '探索异常', '未记录请求/正文；可以重试');
    } finally {
      if (!this.disposed && version === this.version) { this.loading = false; }
    }
  }

  private reachEnd(): void {
    if (!this.loading && this.currentPage > 0 && this.error.length === 0 && !this.autoPaused) {
      this.loadPage(this.currentPage + 1);
    }
  }

  private diagnostic(message: string): string {
    return message.replace(/https?:\/\/[^\s<>"']+/gi, '[URL已隐藏]');
  }

  private openComic(comic: Comic): void {
    const key = comic.sourceKey || this.selectedSourceKey;
    if (this.disposed || SourceManager.find(key) === undefined) { this.error = '结果的原始源不可用，请刷新'; return; }
    const params: ComicDetailsParams = {
      sourceKey: key,
      comicId: comic.id,
      title: comic.title,
      cover: comic.cover
    };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开失败: ${error}` });
      });
  }

  @Builder
  sourceSelector() {
    Row({ space: 8 }) {
      Select(this.sourceNames.map((label: string) => {
        const option: SelectOption = { value: label };
        return option;
      }))
        .selected(this.sourceIndex)
        .value(this.sourceIndex >= 0 ? this.sourceNames[this.sourceIndex] : '所选源不可用')
        .font({ size: 14 }).height(48).borderRadius(18).backgroundColor(UiTheme.surface)
        .layoutWeight(1)
        .fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent).optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface).selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface).onSelect((index: number) => {
          if (index >= 0 && index < this.sourceKeys.length) { SelectedSource.select(this.sourceKeys[index]); }
        })

      Button('刷新').attributeModifier(UiStyles.secondary)
        .fontSize(13)
        .height(44)
        .backgroundColor('#F1F3F5')
        .fontColor('#333333')
        .onClick(() => {
          this.reloadSources();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 4 })
  }

  @Builder
  pageTabs() {
    if (this.pageTitles.length > 1) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.pageTitles, (title: string, index: number) => {
            Text(title)
              .fontSize(13)
              .fontColor(this.pageIndex === index ? '#0A59F7' : '#666666')
              .backgroundColor(this.pageIndex === index ? UiTheme.accentSoft : UiTheme.surface)
              .borderRadius(16)
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
              .onClick(() => {
                this.pageIndex = index;
                this.loadFirstPage();
              })
          }, (title: string) => title)
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  build() {
    Column() {
      this.sourceSelector()
      this.pageTabs()

      if (!this.ready) {
        LoadingView({ message: '正在初始化…' }).layoutWeight(1)
      } else if (this.loading && this.comics.length === 0) {
        LoadingView({ message: '正在加载内容…' }).layoutWeight(1)
      } else if (this.error.length > 0 && this.comics.length === 0) {
        ErrorView({
          message: this.error,
          onRetry: () => {
            this.loadFirstPage();
          }
        }).layoutWeight(1)
      } else if (this.comics.length === 0) {
        EmptyView({ message: '该探索页没有返回内容' }).layoutWeight(1)
      } else {
        Grid() {
          ForEach(this.comics, (item: Comic) => {
            GridItem() {
              ComicCell({
                title: item.title,
                subtitle: item.subtitle,
                coverUrl: item.cover,
                sourceKey: item.sourceKey,
                comicId: item.id,
                onTapCell: () => {
                  this.openComic(item);
                }
              })
            }
          }, (item: Comic) => `${item.sourceKey}@${item.id}`)
          GridItem() {
            Column({ space: 10 }) {
              if (this.error.length > 0) {
                Text(this.error).fontSize(12).fontColor('#D93025').width('100%').textAlign(TextAlign.Center)
              }
              Text(`已加载 ${this.comics.length} 条`).fontSize(12).fontColor(UiTheme.muted)
              Button(this.loading ? '加载中…' : (!this.hasMore ? '已到末页' : (this.error.length > 0 ? '重试加载更多' : '加载更多')))
                .attributeModifier(UiStyles.secondary).enabled(!this.loading && this.hasMore)
                .onClick(() => { this.loadPage(this.currentPage + 1); })
            }.width('100%').padding({ top: 10, bottom: 28 }).alignItems(HorizontalAlign.Center)
          }.columnStart(0).columnEnd(2)

        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(14)
        .padding({ left: 20, right: 20, bottom: 12 })
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => { this.reachEnd(); })

      }
    }
    .width('100%')
    .height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })
  }
}
