import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { Comic } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { NetworkFavoritesSession } from '../features/NetworkFavoritesSession';
import { ComicDetailsParams, NetworkFavoritesParams } from '../model/RouteParams';
import { LoadingView } from '../components/ComicWidgets';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct NetworkFavoritesPage {
  @State sourceKey: string = '';
  @State sources: ComicSource[] = [];
  @State comics: Comic[] = [];
  @State folderIds: string[] = [];
  @State folderNames: string[] = [];
  @State folderIndex: number = 0;
  @State loading: boolean = false;
  @State ended: boolean = false;
  @State error: string = '';
  private session: NetworkFavoritesSession = new NetworkFavoritesSession();
  private disposed: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    const params = router.getParams() as NetworkFavoritesParams;
    this.sourceKey = params?.sourceKey ?? '';
    this.initialize();
  }
  onPageShow(): void { this.disposed = false; }
  onPageHide(): void { this.disposed = true; this.revision++; this.session.invalidate(); this.loading = false; }
  aboutToDisappear(): void { this.onPageHide(); }

  private async initialize(): Promise<void> {
    try {
      await AppInit.init();
      if (this.disposed) { return; }
      this.sources = SourceManager.all().filter((source: ComicSource) => source.favoriteData !== undefined);
      if (this.sourceKey.length === 0 && this.sources.length > 0) { this.sourceKey = this.sources[0].key; }
      await this.refresh();
    } catch (error) { this.error = '初始化网络收藏失败'; }
  }

  private copyState(): void {
    if (this.disposed) { return; }
    this.comics = this.session.results.slice();
    this.folderIds = Array.from(this.session.folders.keys());
    this.folderNames = Array.from(this.session.folders.values());
    this.folderIndex = this.folderIds.indexOf(this.session.folder ?? '');
    this.loading = this.session.loading;
    this.ended = this.session.ended;
    this.error = this.session.error;
  }

  private async refresh(): Promise<void> {
    const token = ++this.revision;
    this.loading = true;
    this.error = '';
    await this.session.start(SourceManager.find(this.sourceKey));
    if (!this.disposed && token === this.revision) { this.copyState(); }
  }

  private async more(folderIndex?: number): Promise<void> {
    if (this.loading) { return; }
    const token = ++this.revision;
    this.loading = true;
    if (folderIndex !== undefined) { await this.session.select(this.folderIds[folderIndex]); }
    else { await this.session.more(); }
    if (!this.disposed && token === this.revision) { this.copyState(); }
  }

  private open(comic: Comic): void {
    if (comic.sourceKey !== this.sourceKey) { return; }
    const params: ComicDetailsParams = { sourceKey: this.sourceKey, comicId: comic.id, title: comic.title, cover: comic.cover };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch(() => { this.error = '打开漫画失败'; });
  }

  private async remove(comic: Comic): Promise<void> {
    if (this.loading || comic.sourceKey !== this.sourceKey) { return; }
    const source = SourceManager.find(this.sourceKey);
    const data = source?.favoriteData;
    if (source === undefined || !source.isLogged) { this.error = '请先登录此漫画源'; return; }
    if (data?.addOrDelFavorite === undefined) { this.error = '此源不支持远端移除'; return; }
    if (data.multiFolder && this.session.folder === undefined) { this.error = '请先选择明确的收藏夹'; return; }
    this.loading = true;
    try {
      const confirm = await promptAction.showDialog({ title: '移除远端收藏',
        message: '仅从当前远端收藏夹移除，不影响本地收藏。是否继续？',
        buttons: [{ text: '取消', color: '#666666' }, { text: '移除', color: '#D93025' }] });
      if (confirm.index !== 1 || !source.isLogged) { return; }
      const result = await data.addOrDelFavorite(comic.id, this.session.folder ?? '', false, comic.favoriteId);
      if (result.error || result.dataOrNull !== true) { this.error = result.errorMessage ?? '未确认远端移除'; return; }
      // Re-read rather than optimistic deletion: some sources cannot remove from an all-folder view.
      await this.session.select(this.session.folder);
      this.copyState();
    } catch (error) { this.error = '远端移除失败，请刷新后重试'; }
    finally { this.loading = false; }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '网络收藏', subtitle: '当前漫画源的远端书架', onBack: () => { router.back(); } })
        Column({ space: 16 }) {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Stack() { UiIcon({ name: 'cloud', color: '#8A68C7', iconSize: 23 }) }
              .width(46).height(46).borderRadius(15).backgroundColor('#F0EAFA')
            Text('来源与收藏夹').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
          }.width('100%')
          Button('刷新').attributeModifier(UiStyles.quiet).height(44).enabled(!this.loading).onClick(() => { this.refresh(); })
          Text('只浏览当前源账号的收藏；不会同步写入远端或自动改用本地收藏。').fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
          if (this.sources.length > 0) {
            Select(this.sources.map((source: ComicSource): SelectOption => {
              const option: SelectOption = { value: source.name }; return option;
            }))
              .selected(this.sources.findIndex((source: ComicSource) => source.key === this.sourceKey))
              .enabled(!this.loading)
              .fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent).optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface).selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface).onSelect((index: number) => { this.sourceKey = this.sources[index].key; this.refresh(); })
              .height(44).font({ size: 14 }).fontColor(UiTheme.ink)
          }
          if (this.folderIds.length > 0) {
            Select(this.folderNames.map((name: string): SelectOption => {
              const option: SelectOption = { value: name }; return option;
            }))
              .selected(this.folderIndex).enabled(!this.loading).fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent).optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface).selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface).onSelect((index: number) => { this.more(index); })
              .height(44).font({ size: 14 }).fontColor(UiTheme.ink)
          }
          Button('当前源账号 / 登录').attributeModifier(UiStyles.secondary).onClick(() => {
            router.pushUrl({ url: 'pages/SourceAccountPage', params: { key: this.sourceKey } })
              .catch(() => { this.error = '打开账号失败'; });
          })
        }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        if (this.error.length > 0) { Text(this.error).fontColor(UiTheme.danger).fontSize(13).lineHeight(20).width('100%').padding(16).backgroundColor(UiTheme.dangerSoft).borderRadius(16) }
        if (this.loading) { LoadingView({ message: '读取网络收藏…' }) }
        ForEach(this.comics, (comic: Comic) => {
          Column({ space: 14 }) {
            Column({ space: 8 }) {
              Text(comic.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%').maxLines(2)
              Text(comic.subtitle).fontSize(13).fontColor(UiTheme.secondary).width('100%').maxLines(2)
            }.width('100%').alignItems(HorizontalAlign.Start).constraintSize({ minHeight: 44 }).onClick(() => { this.open(comic); })
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('打开').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { this.open(comic); })
              Button('移除').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 }).enabled(!this.loading).onClick(() => { this.remove(comic); })
            }.width('100%')
          }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }, (comic: Comic) => `${comic.sourceKey}@${comic.id}`)
        if (!this.loading && this.error.length === 0 && this.comics.length === 0) { Text('当前远端收藏夹没有漫画，或没有声明网络收藏的源').fontSize(14).lineHeight(22).fontColor(UiTheme.secondary).width('100%').padding(24).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius) }
        Button(this.ended ? '已加载完毕' : this.error.length > 0 ? '重试当前页' : '加载下一页')
          .attributeModifier(UiStyles.secondary).enabled(!this.loading && !this.ended).onClick(() => { this.more(); })
      }.padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset }).width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
