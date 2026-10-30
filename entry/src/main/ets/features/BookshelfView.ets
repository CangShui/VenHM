import { UiTheme, UiIcon } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { ComicDetailsParams } from '../model/RouteParams';
import { FavoriteFolder, FavoriteItem, FavoritesDao } from '../storage/FavoritesDao';
import { SourceManager } from '../source/SourceManager';
import { ComicCell, EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { ShelfCommands } from './ShelfCommands';
import { LocalLibrarySignal } from './LocalLibrarySignal';

/**
 * Bookshelf tab.
 *
 * Dart original: lib/features/favorites/local_favorites_page.dart plus
 * favorite_actions.dart (folder create/rename/delete, reorder, move and copy).
 * Drag-and-drop reordering is replaced by explicit up/down actions because
 * ArkUI list dragging is not wired yet; the resulting order semantics match
 * Dart's `reorder` (display_order = list index).
 */
@Component
export struct BookshelfView {
  @State segmentIndex: number = 0;
  @State folders: FavoriteFolder[] = [];
  @State currentFolder: string = '';
  @State favorites: FavoriteItem[] = [];
  @State localComics: Comic[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State panelMode: string = '';
  @State draft: string = '';
  @State panelError: string = '';
  @State busy: boolean = false;

  @Prop @Watch('onHostChanged') hostRevision: number = 0;
  @Prop @Watch('onHostChanged') active: boolean = true;
  private visible: boolean = false;
  private appeared: boolean = false;
  private refreshToken: number = 0;
  private disposed: boolean = false;
  private reloadToken: number = 0;
  private localToken: number = 0;
  private readonly onChanged: () => void = () => {
    if (!this.disposed && this.visible && !this.busy) {
      this.reloadFavorites();
    }
  };
  private readonly onLocalLibraryChanged: () => void = () => { this.reloadLocalComics(); };
  private readonly onNewFolderCommand: () => void = () => { this.openNewFolderEditor(); };

  aboutToAppear(): void {
    this.appeared = true;
    this.disposed = false;
    this.visible = this.active;
    FavoritesDao.addListener(this.onChanged);
    LocalLibrarySignal.addListener(this.onLocalLibraryChanged);
    ShelfCommands.addListener(this.onNewFolderCommand);
    this.refresh();
  }

  /** Download completed or was deleted: the sandbox folder list changed. */
  private async reloadLocalComics(): Promise<void> {
    const token = ++this.localToken;
    if (!this.appeared || this.disposed || !this.active || !this.visible) { return; }
    try {
      await AppInit.init();
      if (!this.appeared || this.disposed || !this.active || !this.visible || token !== this.localToken) { return; }
      const local = SourceManager.find('local');
      if (local === undefined) { return; }
      const explore = local.explorePages.length > 0 ? local.explorePages[0] : undefined;
      if (explore === undefined || explore.loadPage === undefined) { return; }
      const result = await explore.loadPage(1);
      if (!this.appeared || this.disposed || !this.active || !this.visible || token !== this.localToken) { return; }
      this.localComics = result.dataOrNull ?? [];
    } catch (error) {
      Log.warn('BookshelfView', `local comics refresh failed: ${error}`);
    }
  }

  private onHostChanged(): void {
    this.visible = this.active;
    this.localToken++; this.reloadToken++; this.refreshToken++;
    if (this.appeared && !this.disposed && this.active) { this.refresh(); }
  }

  onPageShow(): void {
    this.visible = true;
    this.refresh();
  }

  onPageHide(): void {
    this.visible = false;
    this.localToken++; this.reloadToken++; this.refreshToken++;
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.refreshToken++;
    this.disposed = true;
    this.visible = false;
    this.reloadToken++;
    this.localToken++;
    FavoritesDao.removeListener(this.onChanged);
    LocalLibrarySignal.removeListener(this.onLocalLibraryChanged);
    ShelfCommands.removeListener(this.onNewFolderCommand);
  }

  async refresh(): Promise<void> {
    const request = ++this.refreshToken;
    if (!this.appeared || this.disposed || !this.active || !this.visible) { return; }
    this.loading = true;
    this.error = '';
    try {
      // Index.aboutToAppear() kicks AppInit off without awaiting it, so a tab
      // can be built before preferences/RDB are ready. Awaiting here is a no-op
      // once initialization has completed.
      await AppInit.init();
      if (!this.appeared || this.disposed || !this.active || !this.visible || request !== this.refreshToken) { return; }
      await this.reloadFavorites();
      if (!this.appeared || this.disposed || !this.active || !this.visible || request !== this.refreshToken) { return; }
      await this.reloadLocalComics();
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
      Log.error('BookshelfView', this.error);
    } finally {
      if (request === this.refreshToken && this.appeared) { this.loading = false; }
    }
  }

  private async reloadFavorites(): Promise<void> {
    const token = ++this.reloadToken;
    if (!this.appeared || this.disposed || !this.active || !this.visible) { return; }
    const folders = await FavoritesDao.listFolders();
    if (!this.appeared || this.disposed || !this.active || !this.visible || token !== this.reloadToken) {
      return;
    }
    this.folders = folders;
    // Keep the selection when it still exists; otherwise fall back to the first.
    if (folders.length > 0 && !folders.some((f: FavoriteFolder) => f.name === this.currentFolder)) {
      this.currentFolder = folders[0].name;
    }
    const items = await FavoritesDao.list(this.currentFolder);
    if (!this.appeared || this.disposed || !this.active || !this.visible || token !== this.reloadToken) {
      return;
    }
    this.favorites = items;
  }

  private keyOf(item: FavoriteItem): string {
    return `${item.type.value}:${item.id}`;
  }

  private currentFolderLabel(): string {
    const match = this.folders.filter((item: FavoriteFolder) => item.name === this.currentFolder);
    return match.length > 0 ? match[0].displayName : '默认收藏夹';
  }

  private openComic(comic: Comic, sourceKey: string): void {
    const params: ComicDetailsParams = {
      sourceKey: sourceKey,
      comicId: comic.id,
      title: comic.title,
      cover: comic.cover
    };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开失败: ${error}` });
      });
  }

  /** Opened from the shared "+" button; also resets any half-typed rename. */
  private openNewFolderEditor(): void {
    this.panelMode = 'new';
    this.draft = '';
    this.panelError = '';
  }

  /** Long press on a folder chip: the destructive/reorder actions live here. */
  private async folderMenu(folder: FavoriteFolder): Promise<void> {
    this.currentFolder = folder.name;
    this.panelMode = '';
    const name = folder.displayName;
    try {
      const result = await promptAction.showActionMenu({
        title: name,
        buttons: [
          { text: '重命名', color: '#0A59F7' },
          { text: '前移', color: '#0A59F7' },
          { text: '后移', color: '#0A59F7' },
          { text: '删除此收藏夹', color: '#D93025' }
        ]
      });
      if (folder.name.length === 0 && (result.index === 0 || result.index === 3)) {
        promptAction.showToast({ message: '默认收藏夹不能重命名或删除' });
        return;
      }
      if (result.index === 0) {
        this.panelMode = 'rename';
        this.draft = folder.name;
        this.panelError = '';
      } else if (result.index === 1) {
        this.moveFolder(-1);
      } else if (result.index === 2) {
        this.moveFolder(1);
      } else if (result.index === 3) {
        this.confirmDeleteFolder();
      }
    } catch (error) { /* user cancelled the long-press menu */ }
  }

  // ---- folder operations ----

  private async createFolder(): Promise<void> {
    const name = this.draft.trim();
    if (name.length === 0) {
      this.panelError = '收藏夹名不能为空';
      return;
    }
    try {
      await FavoritesDao.createFolder(name);
      this.currentFolder = name;
      this.draft = '';
      this.panelError = '';
      this.panelMode = '';
      await this.reloadFavorites();
      promptAction.showToast({ message: `已创建「${name}」` });
    } catch (error) {
      this.panelError = error instanceof Error ? error.message : String(error);
    }
  }

  private async renameFolder(): Promise<void> {
    const name = this.draft.trim();
    if (name.length === 0) {
      this.panelError = '收藏夹名不能为空';
      return;
    }
    try {
      const before = this.currentFolder;
      await FavoritesDao.renameFolder(before, name);
      this.currentFolder = name;
      this.draft = '';
      this.panelError = '';
      this.panelMode = '';
      await this.reloadFavorites();
      promptAction.showToast({ message: '已重命名' });
    } catch (error) {
      this.panelError = error instanceof Error ? error.message : String(error);
    }
  }

  private async confirmDeleteFolder(): Promise<void> {
    const label = this.currentFolderLabel();
    try {
      const result = await promptAction.showDialog({
        title: `删除收藏夹「${label}」`,
        message: '该收藏夹及其中的收藏记录会被删除，漫画源中的漫画本身不受影响。删除后无法恢复。',
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '删除收藏夹', color: '#D93025' }
        ]
      });
      if (result.index !== 1) {
        return;
      }
      await FavoritesDao.deleteFolder(this.currentFolder);
      this.currentFolder = '';
      await this.reloadFavorites();
      promptAction.showToast({ message: '已删除收藏夹' });
    } catch (error) {
      promptAction.showToast({ message: `删除失败: ${error}` });
    }
  }

  private async moveFolder(offset: number): Promise<void> {
    const names = this.folders.map((item: FavoriteFolder) => item.name);
    const index = names.indexOf(this.currentFolder);
    const next = index + offset;
    if (index < 0 || next < 0 || next >= names.length) {
      promptAction.showToast({ message: offset > 0 ? '已经在最后' : '已经在最前' });
      return;
    }
    const reordered = names.slice();
    const moved = reordered.splice(index, 1)[0];
    reordered.splice(next, 0, moved);
    try {
      await FavoritesDao.updateFolderOrder(reordered);
      await this.reloadFavorites();
    } catch (error) {
      promptAction.showToast({ message: `排序失败: ${error}` });
    }
  }

  // ---- comic operations ----

  @Builder
  folderBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.folders, (folder: FavoriteFolder) => {
          Text(`${folder.displayName}（${folder.count}）`)
            .fontSize(13)
            .fontColor(this.currentFolder === folder.name ? '#0A59F7' : '#666666')
            .fontWeight(this.currentFolder === folder.name ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: 20, right: 20, top: 6, bottom: 6 })
            .backgroundColor(this.currentFolder === folder.name ? '#E8F0FE' : '#F1F3F5')
            .borderRadius(18)
            .onClick(() => {
              this.currentFolder = folder.name;
              this.panelMode = '';
              this.reloadFavorites();
            })
            .gesture(LongPressGesture({ repeat: false }).onAction(() => { this.folderMenu(folder); }))
        }, (folder: FavoriteFolder) => folder.name)
      }
      .padding({ left: 20, right: 20 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
  }

  @Builder
  segmentBar() {
    Row({ space: 8 }) {
      this.segmentButton('收藏', 0)
      this.segmentButton('本地', 1)
      Button('刷新').attributeModifier(UiStyles.secondary)
        .fontSize(13)
        .height(44)
        .backgroundColor('#F1F3F5')
        .fontColor('#333333')
        .onClick(() => {
          this.refresh();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  @Builder
  segmentButton(title: string, index: number) {
    Text(title)
      .fontSize(14)
      .fontColor(this.segmentIndex === index ? '#0A59F7' : '#666666')
      .fontWeight(this.segmentIndex === index ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 20, right: 20, top: 6, bottom: 6 })
      .backgroundColor(this.segmentIndex === index ? '#E8F0FE' : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.segmentIndex = index;
        if (index === 1 && this.localComics.length === 0) {
          this.refresh();
        }
      })
  }

  @Builder
  panel() {
    Column({ space: 8 }) {
      if (this.panelMode === 'new' || this.panelMode === 'rename') {
        Column({ space: 12 }) {
          TextInput({
            placeholder: this.panelMode === 'new' ? '新收藏夹名称' : '新的收藏夹名称',
            text: this.draft
          })
            .width('100%').height(48).fontSize(14).backgroundColor('#F1F3F7').borderRadius(15)
            .onChange((value: string) => { this.draft = value; })
          Button(this.panelMode === 'new' ? '创建' : '保存').attributeModifier(UiStyles.primary).width('100%')
            .fontSize(14).height(44)
            .onClick(() => {
              if (this.panelMode === 'new') {
                this.createFolder();
              } else {
                this.renameFolder();
              }
            })
          Button('取消').attributeModifier(UiStyles.secondary)
            .fontSize(13).height(44)
            .backgroundColor('#F1F3F5').fontColor('#333333')
            .onClick(() => { this.panelMode = ''; this.panelError = ''; })
        }
        .width('100%')
      }
      if (this.panelError.length > 0) {
        Text(this.panelError).fontSize(12).fontColor('#D93025').width('100%')
      }
    }
    .width('calc(100% - 40vp)')
    .padding(16)
    .backgroundColor(UiTheme.surface).borderRadius(24).margin({ left: 20, right: 20, bottom: 12 })
  }

  @Builder
  comicGrid(items: Comic[], isLocal: boolean) {
    Grid() {
      ForEach(items, (item: Comic) => {
        GridItem() {
          if (isLocal) {
            ComicCell({
              title: item.title,
              subtitle: item.subtitle,
              coverUrl: item.cover,
              sourceKey: 'local',
              comicId: item.id,
              onTapCell: () => {
                this.openComic(item, 'local');
              }
            })
          } else {
            ComicCell({
              title: item.title,
              subtitle: item.subtitle,
              coverUrl: item.cover,
              sourceKey: item.sourceKey,
              comicId: item.id,
              onTapCell: () => { this.openComic(item, item.sourceKey); }
            })
          }
        }
      }, (item: Comic) => `${isLocal ? 'local' : item.sourceKey}@${item.id}`)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(10)
    .rowsGap(14)
    .padding({ left: 20, right: 20, bottom: 12 })
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.segmentBar()

      if (this.loading) {
        LoadingView({ message: '正在加载书架…' })
          .layoutWeight(1)
      } else if (this.error.length > 0) {
        ErrorView({
          message: this.error,
          onRetry: () => {
            this.refresh();
          }
        })
          .layoutWeight(1)
      } else if (this.segmentIndex === 0) {
        this.folderBar()
        if (this.panelMode.length > 0) {
          this.panel()
        }
        if (this.favorites.length === 0) {
          EmptyView({ message: '这个收藏夹还是空的。在漫画详情页点「收藏」即可加入。' })
            .layoutWeight(1)
        } else {
          this.comicGrid(this.favorites, false)
        }
      } else {
        if (this.localComics.length === 0) {
          EmptyView({ message: '本地目录为空。把图片放进沙箱 local_comics/<漫画名>/ 后点刷新。' })
            .layoutWeight(1)
        } else {
          this.comicGrid(this.localComics, true)
        }
      }
    }
    .width('100%')
    .height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })
  }
}
