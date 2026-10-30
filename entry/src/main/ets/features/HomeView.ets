import { UiTheme, UiIcon } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { ComicDetailsParams } from '../model/RouteParams';
import { FavoriteItem, FavoritesDao } from '../storage/FavoritesDao';
import { History, HistoryDao } from '../storage/HistoryDao';
import { SourceManager } from '../source/SourceManager';
import { HistoryNavigation } from './HistoryNavigation';
import { AsyncComicImage, ComicCell, EmptyView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { LocalLibrarySignal } from './LocalLibrarySignal';

/**
 * Home tab - summary cards, mirroring VeneraNext's home page.
 *
 * Dart original: lib/app_shell/home_page.dart composed nine summary widgets
 * (recent updates, history, local comics, image favorites, sync status, ...).
 * The port shows the three summaries the current modules can supply: continue
 * reading, favorites and local comics.
 */
@Component
export struct HomeView {
  @State history: History[] = [];
  @State favorites: FavoriteItem[] = [];
  @State localComics: Comic[] = [];
  @State loading: boolean = true;
  onOpenTab?: (index: number) => void;
  @Prop @Watch('onHostChanged') hostRevision: number = 0;
  @Prop @Watch('onHostChanged') active: boolean = true;
  private appeared: boolean = false;
  private reloadId: number = 0;

  private historyRefreshId: number = 0;
  private readonly onHistoryChanged: () => void = () => { this.reloadHistory(); };
  private localRefreshId: number = 0;
  private readonly onLocalLibraryChanged: () => void = () => { this.reloadLocal(); };

  aboutToAppear(): void {
    this.appeared = true;
    HistoryDao.addListener(this.onHistoryChanged);
    LocalLibrarySignal.addListener(this.onLocalLibraryChanged);
    this.reload();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.reloadId++;
    HistoryDao.removeListener(this.onHistoryChanged);
    LocalLibrarySignal.removeListener(this.onLocalLibraryChanged);
    this.historyRefreshId++;
    this.localRefreshId++;
  }

  /** Refresh only the sandbox local-comic list (download add/remove). */
  private async reloadLocal(): Promise<void> {
    const requestId = ++this.localRefreshId;
    if (!this.appeared || !this.active) { return; }
    try {
      await AppInit.init();
      if (!this.appeared || !this.active || requestId !== this.localRefreshId) { return; }
      const local = SourceManager.find('local');
      if (local === undefined || local.explorePages.length === 0) { this.localComics = []; return; }
      const explore = local.explorePages[0];
      if (explore.loadPage === undefined) { return; }
      const result = await explore.loadPage(1);
      if (this.appeared && this.active && requestId === this.localRefreshId) {
        this.localComics = result.dataOrNull ?? [];
      }
    } catch (error) {
      Log.warn('HomeView', `local comics refresh failed: ${error}`);
    }
  }

  private async reloadHistory(): Promise<void> {
    const requestId = ++this.historyRefreshId;
    if (!this.appeared || !this.active) { return; }
    try {
      const items = await HistoryDao.list(10);
      if (this.appeared && this.active && requestId === this.historyRefreshId) {
        this.history = items;
      }
    } catch (error) {
      Log.warn('HomeView', `history refresh failed: ${error}`);
    }
  }

  private onHostChanged(): void {
    this.historyRefreshId++; this.localRefreshId++; this.reloadId++;
    if (this.appeared && this.active) { this.reload(); }
  }

  async reload(): Promise<void> {
    const request = ++this.reloadId;
    if (!this.appeared || !this.active) { return; }
    this.loading = true;
    try {
      await AppInit.init();
      if (!this.appeared || !this.active || request !== this.reloadId) { return; }
      const history = await HistoryDao.list(10);
      if (!this.appeared || !this.active || request !== this.reloadId) { return; }
      const favorites = await FavoritesDao.list();
      if (!this.appeared || !this.active || request !== this.reloadId) { return; }
      this.history = history; this.favorites = favorites;
      await this.reloadLocal();
    } catch (error) {
      Log.error('HomeView', 'home refresh unavailable');
    } finally {
      if (request === this.reloadId && this.appeared) { this.loading = false; }
    }
  }

  private openComic(sourceKey: string, comicId: string, title: string, cover: string): void {
    const params: ComicDetailsParams = {
      sourceKey: sourceKey,
      comicId: comicId,
      title: title,
      cover: cover
    };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开失败: ${error}` });
      });
  }

  @Builder
  sectionHeader(title: string, actionLabel: string, tabIndex: number) {
    Row() {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink).layoutWeight(1)
      if (actionLabel.length > 0) {
        Text(actionLabel)
          .fontSize(12).height(40)
          .fontColor(UiTheme.accent)
          .onClick(() => {
            const handler = this.onOpenTab;
            if (handler !== undefined) {
              handler(tabIndex);
            }
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 26, bottom: 16 })
  }

  @Builder
  historyStrip() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.history, (item: History) => {
          Column({ space: 4 }) {
            Column() {
              AsyncComicImage({ url: item.cover, sourceKey: HistoryNavigation.sourceKey(item) ?? '', comicId: item.id })
            }
            .width(108)
            .height(148)
            .borderRadius(16)
            .clip(true)

            Text(item.title)
              .fontSize(12)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(108)
            Text(item.description())
              .fontSize(10)
              .fontColor(UiTheme.muted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(108)
          }
          .onClick(() => {
            HistoryNavigation.resume(item).catch((error: Object) => {
              promptAction.showToast({ message: `继续阅读失败: ${error}` });
            });
          })
        }, (item: History) => `${item.type.value}@${item.id}`)
      }
      .padding({ left: 20, right: 20 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  comicGrid(items: Comic[], isLocal: boolean) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(items, (item: Comic) => {
        Column() {
          ComicCell({
            title: item.title,
            subtitle: item.subtitle,
            coverUrl: item.cover,
            sourceKey: item.sourceKey,
            comicId: item.id,
            onTapCell: () => {
              this.openComic(isLocal ? 'local' : item.sourceKey, item.id, item.title, item.cover);
            }
          })
        }.width('31%').margin({ bottom: 18 })
      }, (item: Comic) => `${isLocal ? 'local' : item.sourceKey}@${item.id}`)
    }.padding({ left: 20, right: 20 }).width('100%')
  }

  @Builder
  localStrip() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(this.localComics, (item: Comic) => {
          Column() {
            ComicCell({ title: item.title, subtitle: item.subtitle, coverUrl: item.cover,
              sourceKey: 'local', comicId: item.id,
              onTapCell: () => { this.openComic('local', item.id, item.title, item.cover); } })
          }.width(116)
        }, (item: Comic) => `local@${item.id}`)
      }.padding({ left: 20, right: 20 })
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          if (this.loading) {
            Row() {
              LoadingProgress().width(28).height(28)
              Text('正在加载首页…').fontSize(13).fontColor(UiTheme.muted).margin({ left: 8 })
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          } else {
            // ---- continue reading ----
            if (this.history.length > 0) {
              this.sectionHeader('继续阅读', '', 0)
              this.historyStrip()
            }

            // ---- favorites ----
            this.sectionHeader(`我的收藏（${this.favorites.length}）`, '查看全部', 1)
            if (this.favorites.length === 0) {
              Text('还没有收藏，在漫画详情页点「收藏」即可加入。')
                .fontSize(13)
                .fontColor(UiTheme.muted)
                .width('100%')
                .padding({ left: 20, right: 20, bottom: 8 })
            } else {
              this.comicGrid(this.favorites.slice(0, 6), false)
            }

            // ---- local comics ----
            this.sectionHeader(`本地漫画（${this.localComics.length}）`, '', 1)
            if (this.localComics.length === 0) {
              Text('本地暂无可阅读漫画。下载保存图片后会自动出现在这里。')
                .fontSize(13)
                .fontColor(UiTheme.muted)
                .width('100%')
                .padding({ left: 20, right: 20, bottom: 24 })
            } else {
              this.localStrip()
            }

            Row().height(UiTheme.bottomInset)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%').backgroundColor(UiTheme.page)
  }
}
