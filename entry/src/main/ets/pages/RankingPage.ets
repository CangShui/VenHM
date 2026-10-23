import { router } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { ComicDetailsParams, RankingParams } from '../model/RouteParams';
import { SourceManager } from '../source/SourceManager';
import { RankingSession } from '../features/RankingSession';
import { ComicCell, EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { UiTheme, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Entry params, never SelectedSource, determine all requests and detail routes. */
@Entry
@Component
struct RankingPage {
  @State sourceName: string = '';
  @State comics: Comic[] = [];
  @State options: SelectOption[] = [];
  @State optionIndex: number = -1;
  @State optionLabel: string = '';
  @State loading: boolean = true;
  @State error: string = '';
  @State ended: boolean = false;
  private params: RankingParams = { sourceKey: '' };
  private session: RankingSession = new RankingSession();
  private version: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.params = router.getParams() as RankingParams;
    this.initialize();
  }

  aboutToDisappear(): void { this.hide(); }
  onPageHide(): void { this.hide(); }
  private hide(): void {
    this.disposed = true; this.version++; this.session.invalidatePending(); this.loading = false;
  }

  onPageShow(): void {
    const hidden = this.disposed; this.disposed = false;
    if (hidden && (!this.session.ready || this.session.page === 0)) { this.retry(); }
  }

  private current(version: number): boolean { return !this.disposed && version === this.version; }

  private sync(): void {
    this.comics = this.session.results.slice(); this.loading = this.session.loading;
    this.error = this.session.error; this.ended = this.session.ended;
    this.options = Array.from(this.session.options.values()).map((label: string): SelectOption => {
      const item: SelectOption = { value: label }; return item;
    });
    this.optionIndex = Array.from(this.session.options.keys()).indexOf(this.session.option);
    this.optionLabel = this.session.options.get(this.session.option) ?? '';
  }

  private async initialize(): Promise<void> {
    const version = ++this.version;
    this.loading = true; this.error = ''; this.comics = []; this.options = []; this.ended = false;
    try {
      await AppInit.init();
      if (!this.current(version)) { return; }
      const source = SourceManager.find(this.params?.sourceKey ?? '');
      if (source === undefined) { throw new Error('原始漫画源已不可用；不会改用其他源'); }
      this.sourceName = source.name;
      const pending = this.session.start(source); this.sync();
      await pending;
      if (this.current(version)) { this.sync(); }
    } catch (error) {
      if (!this.current(version)) { return; }
      this.error = error instanceof Error ? error.message : '排行初始化失败，请重试'; this.loading = false;
      Log.audit('ranking-init', '排行页面异常', '未更换源；不打印异常正文');
    }
  }

  private async action(option?: string): Promise<void> {
    if (this.disposed || (option === undefined && (this.session.loading || this.session.ended)) ||
      (option !== undefined && (!this.session.options.has(option) || option === this.session.option))) { return; }
    if (SourceManager.find(this.params.sourceKey) === undefined) { this.error = '原始漫画源已不可用；不会改用其他源'; return; }
    const version = ++this.version;
    const pending = option !== undefined ? this.session.select(option) : this.session.more();
    this.sync(); await pending;
    if (this.current(version)) { this.sync(); }
  }

  private async retry(): Promise<void> {
    if (!this.session.ready) { await this.initialize(); return; }
    if (this.loading || this.disposed) { return; }
    if (SourceManager.find(this.params.sourceKey) === undefined) { this.error = '原始漫画源已不可用；不会改用其他源'; return; }
    const version = ++this.version;
    const pending = this.session.retry(); this.sync(); await pending;
    if (this.current(version)) { this.sync(); }
  }

  private openComic(comic: Comic): void {
    if (this.disposed || comic.sourceKey !== this.params.sourceKey || SourceManager.find(this.params.sourceKey) === undefined) {
      this.error = '该结果的原始源已不可用'; return;
    }
    const params: ComicDetailsParams = { sourceKey: this.params.sourceKey, comicId: comic.id, title: comic.title, cover: comic.cover };
    const version = this.version;
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch(() => {
      if (this.current(version)) { this.error = '无法打开漫画详情，请重试'; }
      Log.audit('ranking-detail', '排行详情跳转异常', '未改用其他源；不打印异常正文');
    });
  }

  build() {
    Column() {
      UiPageHeader({ title: '排行榜', subtitle: this.sourceName, onBack: () => { router.back(); } })
      Column({ space: 8 }) {
      if (this.options.length > 0) {
        Select(this.options).selected(this.optionIndex).value(this.optionLabel).width('100%').height(56)
          .font({ size: 15 }).fontColor(UiTheme.ink).backgroundColor(UiTheme.surface).borderRadius(20).padding({ left: 16, right: 16 })
          .onSelect((index: number) => {
            const keys = Array.from(this.session.options.keys());
            if (index >= 0 && index < keys.length) { this.action(keys[index]); }
          })
      }
      if (this.loading && this.comics.length === 0) {
        LoadingView({ message: '正在加载排行…' }).layoutWeight(1)
      } else if (this.error.length > 0 && this.comics.length === 0) {
        ErrorView({ message: this.error, onRetry: () => { this.retry(); } }).layoutWeight(1)
      } else if (this.comics.length === 0) {
        EmptyView({ message: '该排行暂无漫画' }).layoutWeight(1)
        Button('重试').attributeModifier(UiStyles.secondary).margin({ bottom: 16 }).onClick(() => { this.retry(); })
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
          Button('重试').attributeModifier(UiStyles.secondary).enabled(!this.loading).onClick(() => { this.retry(); })
        }
        Button(this.loading ? '加载中…' : (this.ended ? '已到末页' : '加载更多')).attributeModifier(UiStyles.primary).margin({ top: 8, bottom: 16 })
          .enabled(!this.loading && !this.ended).onClick(() => { this.action(); })
      }
      }.width('100%').layoutWeight(1).padding({ left: UiTheme.gutter, right: UiTheme.gutter })
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
