import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Comic, ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { ComicType } from '../model/ComicType';
import { ComicDetailsParams, ReaderParams } from '../model/RouteParams';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { FavoriteFolder, FavoriteItem, FavoritesDao } from '../storage/FavoritesDao';
import { AsyncComicImage, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { DownloadQueue } from '../features/DownloadQueue';
import { ChapterNavigation, ChapterSection, ChapterEntry } from '../features/ChapterNavigation';
import { pasteboard } from '@kit.BasicServicesKit';
import { DetailTag, TagRouting } from '../features/TagRouting';
import { DetailsMedia, DetailsSharePayload } from '../features/DetailsMedia';
import { DetailsMediaImage } from '../features/DetailsMediaImage';
import { DetailsViewerParams, DetailsCommentsParams } from '../source/DetailsCapabilities';
import { CollectionActionsPanel } from '../components/CollectionActionsPanel';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/**
 * Comic details page.
 *
 * Dart original: lib/features/comic_details/comic_page.dart (1024 lines) plus
 * chapters.dart. Trimmed to: cover + metadata + chapter list + favorite action.
 * Comments, thumbnails, recommendations, archive download and shimmer are later
 * modules (see the migration plan).
 */
@Entry
@Component
struct ComicDetailsPage {
  @State sourceKey: string = '';
  @State comicId: string = '';
  @State title: string = '';
  @State cover: string = '';
  @State details: ComicDetails | undefined = undefined;
  @State loading: boolean = true;
  @State error: string = '';
  @State isFavorite: boolean = false;
  @State folders: FavoriteFolder[] = [];
  @State memberFolders: string[] = [];
  @State showFolderPanel: boolean = false;
  @State newFolderDraft: string = '';
  @State favoriteError: string = '';
  @State favoriteBusy: boolean = false;
  @State downloadBusy: boolean = false;
  @State chapterSections: ChapterSection[] = [];
  @State reverseChapters: boolean = false;
  @State collapsedGroups: string[] = [];
  @State detailTags: DetailTag[] = [];
  @State tagRoutingBusy: boolean = false;
  private tagVersion: number = 0;
  private disposed: boolean = false;
  private loadVersion: number = 0;
  private media: DetailsMedia = new DetailsMedia();
  @State thumbnails: string[] = [];
  @State thumbnailsLoading: boolean = false;
  @State thumbnailsEnded: boolean = true;
  @State thumbnailsError: string = '';
  @State commentsAvailable: boolean = false;
  @State shareBusy: boolean = false;

  aboutToDisappear(): void { this.disposed = true; this.loadVersion++; this.tagVersion++; this.tagRoutingBusy = false;
    this.media.invalidate(); this.thumbnailsLoading = false; this.shareBusy = false; }

  onPageHide(): void {
    this.disposed = true; this.loadVersion++; this.tagVersion++; this.tagRoutingBusy = false;
    this.media.invalidate(); this.thumbnailsLoading = false; this.shareBusy = false;
  }

  onPageShow(): void {
    const wasHidden = this.disposed;
    this.disposed = false;
    if (wasHidden && this.details === undefined) { this.load(); }
  }

  private toggleChapterOrder(): void {
    this.reverseChapters = !this.reverseChapters;
    this.chapterSections = ChapterNavigation.sections(this.chapters(), this.reverseChapters,
      `details-chapters-${Date.now()}`);
  }

  private toggleGroup(name: string): void {
    this.collapsedGroups = this.collapsedGroups.includes(name)
      ? this.collapsedGroups.filter((item: string) => item !== name) : this.collapsedGroups.concat(name);
    Log.audit(`details-group-${Date.now()}`, '章节分组折叠', `折叠组数=${this.collapsedGroups.length}；不改变章节ID/阅读历史`);
  }

  private openRecommendation(comic: Comic): void {
    const trace = `details-recommend-${Date.now()}`;
    if (comic.id.length === 0 || comic.sourceKey.length === 0 || this.disposed ||
      SourceManager.find(comic.sourceKey) === undefined) {
      Log.audit(trace, '推荐跳转拒绝', '缺少稳定ID/源、源不可用或页面已退出；不误用当前源');
      return;
    }
    const params: ComicDetailsParams = { sourceKey: comic.sourceKey, comicId: comic.id, title: comic.title, cover: comic.cover };
    Log.audit(trace, '推荐跳转到达', `目标源=${comic.sourceKey}；ID内容不落盘`);
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).then(() => {
      Log.audit(trace, '推荐跳转返回', '详情路由打开');
    }).catch((error: Object) => { Log.audit(trace, '推荐跳转异常', '无法打开目标详情'); });
  }

  private async queueDownload(): Promise<void> {
    if (this.downloadBusy || this.loading || this.disposed) { return; }
    this.downloadBusy = true;
    try {
      await DownloadQueue.add(this.sourceKey, this.comicId);
      if (this.disposed) { return; }
      await router.pushUrl({ url: 'pages/DownloadsPage' });
    } catch (error) {
      if (!this.disposed) { promptAction.showToast({ message: `加入下载失败：${error}` }); }
    } finally { if (!this.disposed) { this.downloadBusy = false; } }
  }

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as ComicDetailsParams;
    if (params !== undefined && params !== null) {
      this.sourceKey = params.sourceKey ?? '';
      this.comicId = params.comicId ?? '';
      this.title = params.title ?? '';
      this.cover = params.cover ?? '';
    }
    this.load();
  }

  private currentSource(): ComicSource | undefined {
    return SourceManager.find(this.sourceKey);
  }

  async load(): Promise<void> {
    const version = ++this.loadVersion;
    this.loading = true;
    this.error = '';
    this.details = undefined;
    this.media.invalidate(); this.thumbnails = []; this.thumbnailsError = '';
    this.thumbnailsLoading = false; this.thumbnailsEnded = true; this.commentsAvailable = false;
    this.detailTags = []; this.tagVersion++; this.tagRoutingBusy = false;
    try {
      // Reachable directly (deep link / restore), so do not assume the tabs
      // have already finished initializing.
      await AppInit.init();
      if (this.disposed || version !== this.loadVersion) { return; }
    } catch (error) {
      if (this.disposed || version !== this.loadVersion) { return; }
      this.error = error instanceof Error ? error.message : String(error);
      this.loading = false;
      return;
    }
    const source = this.currentSource();
    if (source === undefined) {
      this.error = `漫画源不存在: ${this.sourceKey}`;
      this.loading = false;
      return;
    }
    if (source.loadComicInfo === undefined) {
      this.error = `${source.name} 不支持详情加载`;
      this.loading = false;
      return;
    }
    // Cached details paint instantly (covers/details survive app restart); the
    // network request below still runs so chapter lists are never permanently stale.
    let paintedFromCache = false;
    if (source.loadCachedComicInfo !== undefined) {
      try {
        const cached = await source.loadCachedComicInfo(this.comicId);
        if (this.disposed || version !== this.loadVersion) { return; }
        if (cached !== undefined) {
          this.applyDetails(cached, source, version);
          this.loading = false;
          paintedFromCache = true;
          Log.audit(`details-load-${version}`, '详情缓存命中', '先渲染缓存，随后仍会请求最新数据');
        }
      } catch (error) {
        Log.warn('ComicDetailsPage', 'cached details unavailable; using network only');
      }
    }
    try {
      const result = await source.loadComicInfo(this.comicId);
      if (this.disposed || version !== this.loadVersion) { return; }
      if (result.error) {
        this.error = paintedFromCache ? `显示的是缓存内容；刷新失败：${result.errorMessage ?? '加载失败'}`
          : (result.errorMessage ?? '加载失败');
      } else if (result.dataOrNull === undefined) {
        this.error = '详情返回空数据，无法确认章节，请重试。';
      } else {
        this.applyDetails(result.dataOrNull, source, version);
      }
      await this.reloadFavorites();
    } catch (error) {
      if (this.disposed || version !== this.loadVersion) { return; }
      this.error = error instanceof Error ? error.message : String(error);
      Log.audit(`details-load-${version}`, '详情加载异常', '不记录站点正文或异常内容');
    } finally {
      if (!this.disposed && version === this.loadVersion) { this.loading = false; }
    }
  }

  /** Apply a details payload from cache or network to the page state. */
  private applyDetails(details: ComicDetails, source: ComicSource, version: number): void {
    this.details = details;
    this.detailTags = TagRouting.tags(details);
    this.chapterSections = ChapterNavigation.sections(details.chapters, this.reverseChapters,
      `details-load-${version}`);
    this.collapsedGroups = [];
    this.media.start(this.comicId, details.thumbnails ?? [], source.detailsMedia);
    this.commentsAvailable = source.loadComicComments !== undefined || (details.comments?.length ?? 0) > 0;
    this.syncMedia();
    if (!this.thumbnailsEnded) { this.loadThumbnails(); }
  }

  private syncMedia(): void {
    this.thumbnails = this.media.images.slice(); this.thumbnailsLoading = this.media.loading;
    this.thumbnailsEnded = this.media.ended; this.thumbnailsError = this.media.error;
  }

  private async loadThumbnails(): Promise<void> {
    if (this.disposed || this.currentSource() === undefined) { return; }
    const version = this.loadVersion; const request = this.media.more(); this.syncMedia();
    await request;
    if (!this.disposed && version === this.loadVersion) { this.syncMedia(); }
  }

  private openViewer(images: string[], index: number): void {
    if (this.disposed || images.length === 0 || this.currentSource() === undefined) { return; }
    const params: DetailsViewerParams = { sourceKey: this.sourceKey, comicId: this.comicId,
      title: this.details?.title || this.title, images: images.slice(), index: index, thumbnail: true };
    router.pushUrl({ url: 'pages/ImageViewerPage', params: params }).catch(() => {
      if (!this.disposed) { promptAction.showToast({ message: '无法打开图片查看器' }); }
    });
  }

  private openComments(): void {
    if (this.disposed || !this.commentsAvailable || this.currentSource() === undefined) { return; }
    const params: DetailsCommentsParams = { sourceKey: this.sourceKey, comicId: this.comicId,
      title: this.details?.title || this.title, subId: this.details?.subId, initialComments: this.details?.comments };
    router.pushUrl({ url: 'pages/CommentsPage', params: params }).catch(() => {
      if (!this.disposed) { promptAction.showToast({ message: '无法打开评论' }); }
    });
  }

  private async shareDetails(): Promise<void> {
    if (this.disposed || this.loading || this.shareBusy || this.details === undefined) { return; }
    const version = this.loadVersion; this.shareBusy = true;
    try {
      // Original site address: the comic's own URL, else an absolute comic id,
      // else the source's site domain. Never an app-internal route.
      const source = SourceManager.find(this.sourceKey);
      const domain = source?.linkHandler?.domains.length ? source.linkHandler.domains[0] : '';
      const payload = DetailsSharePayload.create(this.details.title || this.title,
        this.details.url, this.comicId, domain);
      // Never serialize details, cookies, headers, account data, cover request or source state.
      const record: systemShare.SharedRecord = payload.url.length > 0
        ? { utd: uniformTypeDescriptor.UniformDataType.HYPERLINK, content: payload.url, title: payload.title }
        : { utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT, content: payload.text };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE });
    } catch (error) {
      if (!this.disposed && version === this.loadVersion) { promptAction.showToast({ message: '系统分享未完成，请重试；也可长按复制标题' }); }
    } finally { if (!this.disposed && version === this.loadVersion) { this.shareBusy = false; } }
  }

  private typeValue(): number {
    return ComicType.fromKey(this.sourceKey).value;
  }

  private chapters(): ComicChapters | undefined {
    const details = this.details;
    return details === undefined ? undefined : details.chapters;
  }

  private openReader(epId?: string): void {
    const details = this.details;
    if (this.disposed || this.loading || this.error.length > 0 || details === undefined) {
      return;
    }
    const params: ReaderParams = {
      sourceKey: this.sourceKey,
      comicId: this.comicId,
      title: details.title.length > 0 ? details.title : this.title,
      cover: details.cover.length > 0 ? details.cover : this.cover,
      epId: epId,
      resume: epId === undefined,
      origin: 'details',
      page: 1
    };
    router.pushUrl({ url: 'pages/ReaderPage', params: params })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开阅读器失败: ${error}` });
      });
  }

  /** Refresh folder list and which folders currently hold this comic. */
  async reloadFavorites(): Promise<void> {
    const version = this.loadVersion;
    const folders = await FavoritesDao.listFolders();
    const members = await FavoritesDao.foldersOf(this.comicId, this.typeValue());
    if (this.disposed || version !== this.loadVersion) { return; }
    this.folders = folders; this.memberFolders = members;
    this.isFavorite = members.length > 0;
  }

  private isMember(folder: string): boolean {
    return this.memberFolders.indexOf(folder) >= 0;
  }

  /** Upstream's panel toggles membership in exactly one folder per tap. */
  async toggleInFolder(folder: string): Promise<void> {
    if (this.details === undefined || this.favoriteBusy) {
      return;
    }
    this.favoriteBusy = true;
    this.favoriteError = '';
    try {
      if (this.isMember(folder)) {
        await FavoritesDao.remove(this.comicId, this.typeValue(), folder);
      } else {
        const details = this.details;
        const item = FavoriteItem.fromComic({
          id: this.comicId,
          title: details.title.length > 0 ? details.title : this.title,
          subtitle: details.findAuthor() ?? '',
          cover: details.cover.length > 0 ? details.cover : this.cover,
          tags: details.plainTags,
          description: details.description ?? '',
          sourceKey: this.sourceKey
        }, folder);
        await FavoritesDao.add(item);
      }
      await this.reloadFavorites();
    } catch (error) {
      this.favoriteError = error instanceof Error ? error.message : String(error);
      Log.warn('ComicDetailsPage', `favorite toggle failed: ${this.favoriteError}`);
    } finally {
      this.favoriteBusy = false;
    }
  }

  /**
   * Long press = upstream's `quickFavorite`: add to the default folder only,
   * and do nothing when it is already there.
   */
  async quickFavorite(): Promise<void> {
    if (this.details === undefined || this.favoriteBusy) {
      return;
    }
    this.favoriteBusy = true;
    try {
      const details = this.details;
      const item = FavoriteItem.fromComic({
        id: this.comicId,
        title: details.title.length > 0 ? details.title : this.title,
        subtitle: details.findAuthor() ?? '',
        cover: details.cover.length > 0 ? details.cover : this.cover,
        tags: details.plainTags,
        description: details.description ?? '',
        sourceKey: this.sourceKey
      }, '');
      const added = await FavoritesDao.add(item);
      await this.reloadFavorites();
      promptAction.showToast({ message: added ? '已加入默认收藏夹' : '已在默认收藏夹中' });
    } catch (error) {
      promptAction.showToast({ message: `收藏操作失败: ${error}` });
    } finally {
      this.favoriteBusy = false;
    }
  }

  /** Create a folder from the panel, then immediately add this comic to it. */
  async createFolderHere(): Promise<void> {
    const name = this.newFolderDraft.trim();
    if (name.length === 0) {
      this.favoriteError = '收藏夹名不能为空';
      return;
    }
    try {
      await FavoritesDao.createFolder(name);
      this.newFolderDraft = '';
      this.favoriteError = '';
      await this.reloadFavorites();
      await this.toggleInFolder(name);
    } catch (error) {
      this.favoriteError = error instanceof Error ? error.message : String(error);
    }
  }

  @Builder
  favoritePanel() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Text('收藏到收藏夹').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).layoutWeight(1)
        Text('关闭').fontSize(14).fontColor(UiTheme.accent).height(44).padding({ left: 12, right: 12 }).onClick(() => {
          this.showFolderPanel = false;
        })
      }
      .width('100%')

      if (this.favoriteError.length > 0) {
        Text(this.favoriteError).fontSize(12).lineHeight(20).fontColor(UiTheme.danger).width('100%')
      }

      ForEach(this.folders, (folder: FavoriteFolder) => {
        Row({ space: 8 }) {
          Text(folder.displayName).fontSize(14).fontColor(UiTheme.ink).layoutWeight(1)
          Text(this.isMember(folder.name) ? '已收藏' : '未收藏')
            .fontSize(12)
            .fontColor(this.isMember(folder.name) ? UiTheme.success : UiTheme.muted)
          Text(this.isMember(folder.name) ? '移出' : '加入')
            .fontSize(13)
            .fontColor(this.isMember(folder.name) ? UiTheme.danger : UiTheme.accent)
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ top: 10, bottom: 10 })
        .onClick(() => {
          this.toggleInFolder(folder.name);
        })
      }, (folder: FavoriteFolder) => folder.name)

      Column({ space: 10 }) {
        TextInput({ placeholder: '新建收藏夹名称', text: this.newFolderDraft })
          .width('100%')
          .height(44)
          .fontSize(14).backgroundColor(UiTheme.page).borderRadius(16)
          .onChange((value: string) => {
            this.newFolderDraft = value;
          })
        Button('新建并收藏')
          .attributeModifier(UiStyles.quiet).height(44)
          .enabled(!this.favoriteBusy)
          .onClick(() => {
            this.createFolderHere();
          })
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(UiTheme.surface)
    .borderRadius(UiTheme.cardRadius)
  }

  private async copyMetadata(value: string, field: string): Promise<void> {
    if (this.disposed || value.length === 0) { return; }
    const version = this.loadVersion;
    const trace = `details-copy-${Date.now()}`;
    Log.audit(trace, '元数据复制到达', `字段=${field}；文本内容不落盘`);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      await pasteboard.getSystemPasteboard().setData(data);
      if (!this.disposed && version === this.loadVersion) { promptAction.showToast({ message: '已复制' }); }
      Log.audit(trace, '元数据复制返回', '系统剪贴板写入完成；不记录复制内容');
    } catch (error) {
      if (!this.disposed && version === this.loadVersion) { promptAction.showToast({ message: '复制失败，请重试' }); }
      Log.audit(trace, '元数据复制异常', '不记录文本或异常正文');
    }
  }

  private async openTag(tag: DetailTag): Promise<void> {
    if (this.disposed || this.loading || this.tagRoutingBusy) { return; }
    const version = ++this.tagVersion;
    const trace = `details-tag-${Date.now()}-${version}`;
    const key = this.sourceKey;
    this.tagRoutingBusy = true;
    Log.audit(trace, '标签点击到达', '使用详情原始源与完整namespace/tag；值不落盘');
    try {
      const source = SourceManager.find(key);
      if (source === undefined) { throw new Error('详情的原始源已不可用'); }
      const target = await TagRouting.resolve(source, tag);
      if (this.disposed || version !== this.tagVersion || key !== this.sourceKey) { return; }
      await TagRouting.open(key, target, trace);
    } catch (error) {
      if (this.disposed || version !== this.tagVersion) { return; }
      promptAction.showToast({ message: error instanceof Error ? error.message : '标签跳转失败，请重试' });
      Log.audit(trace, '标签跳转异常', '目标不存在/回调异常；未误用其他源或猜测分类');
    } finally {
      if (!this.disposed && version === this.tagVersion) { this.tagRoutingBusy = false; }
    }
  }

  @Builder
  metadataRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).fontColor(UiTheme.muted).width(32)
      Text(value).fontSize(13).lineHeight(20).fontColor(UiTheme.secondary).layoutWeight(1)
        .gesture(LongPressGesture({ repeat: false }).onAction(() => { this.copyMetadata(value, label); }))
    }
    .width('100%').constraintSize({ minHeight: 24 })
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '漫画详情', onBack: () => {
            router.back();
          } })
        Column({ space: 16 }) {
        Row() {
          Blank()
          Text(this.isFavorite ? '已收藏' : '收藏')
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.isFavorite ? UiTheme.success : UiTheme.accent)
            .height(44).padding({ left: 18, right: 18 }).backgroundColor(this.isFavorite ? '#E5F7F0' : UiTheme.accentSoft).borderRadius(15)
            .onClick(() => {
              this.showFolderPanel = !this.showFolderPanel;
            })
            .gesture(LongPressGesture().onAction(() => {
              // Upstream: long press = quick add to the configured folder.
              this.quickFavorite();
            }))
        }.width('100%')

        if (this.showFolderPanel) {
          this.favoritePanel()
        }

        if (this.loading) {
          LoadingView({ message: '正在加载详情…' }).width('100%').padding(24)
        } else if (this.error.length > 0) {
          ErrorView({
            message: this.error,
            onRetry: () => {
              this.load();
            }
          }).width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        } else {
          Column({ space: 18 }) {
            Row({ space: 16 }) {
              Column() {
                AsyncComicImage({ url: this.details?.cover ?? this.cover, sourceKey: this.sourceKey,
                  comicId: this.comicId, thumbnail: true })
              }
              .width(100)
              .height(144)
              .borderRadius(16)
              .clip(true)
              .onClick(() => { this.openViewer([this.details?.cover || this.cover], 0); })

              Column({ space: 8 }) {
                Text(this.details?.title ?? this.title)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
                  .maxLines(3)
                  .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                    this.copyMetadata(this.details?.title || this.title, '标题');
                  }))
                if (this.details !== undefined) {
                  this.metadataRow('作者', this.details.findAuthor() ?? '未知')
                  this.metadataRow('更新', this.details.findUpdateTime() ?? '未知')
                  this.metadataRow('章节', `${this.details.chapters?.length ?? 0}`)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            if (this.detailTags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.detailTags, (tag: DetailTag) => {
                  Text(tag.label)
                    .fontSize(12)
                    .fontColor(UiTheme.secondary)
                    .backgroundColor(UiTheme.page)
                    .borderRadius(12)
                    .constraintSize({ minHeight: 44 })
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .margin({ right: 8, bottom: 8 })
                    // Exclusive recognizers ensure a copy long press cannot also open a tag.
                    .gesture(GestureGroup(GestureMode.Exclusive,
                      LongPressGesture({ repeat: false }).onAction(() => { this.copyMetadata(tag.label, '标签'); }),
                      TapGesture().onAction(() => { this.openTag(tag); })
                    ))
                }, (tag: DetailTag, index: number) => `${index}:${tag.namespace}:${tag.value}`)
              }
              .width('100%')
            }

            if ((this.details?.description ?? '').length > 0) {
              Text(this.details?.description ?? '')
                .fontSize(14).lineHeight(23)
                .fontColor(UiTheme.secondary)
                .width('100%')
            }
          }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          Flex({ wrap: FlexWrap.Wrap }) {
            Button('继续阅读')
              .attributeModifier(UiStyles.primary).width('48%').margin({ right: '2%', bottom: 10 })
              .onClick(() => {
                this.openReader();
              })
            Button(this.downloadBusy ? '正在加入…' : '下载漫画')
              .attributeModifier(UiStyles.secondary).width('48%').margin({ right: '2%', bottom: 10 })
              .enabled(!this.downloadBusy)
              .onClick(() => { this.queueDownload(); })
            Button(this.shareBusy ? '分享中…' : '分享').attributeModifier(UiStyles.secondary).width('48%').margin({ right: '2%', bottom: 10 }).enabled(!this.shareBusy).onClick(() => { this.shareDetails(); })
            if (this.commentsAvailable) {
              Button(`评论${this.details?.commentCount === undefined ? '' : ` (${this.details?.commentCount})`}`)
                .attributeModifier(UiStyles.quiet).height(44).width('48%').margin({ right: '2%', bottom: 10 })
                .onClick(() => { this.openComments(); })
            }
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          CollectionActionsPanel({ sourceKey: this.sourceKey, comicId: this.comicId,
            title: this.details?.title || this.title, cover: this.details?.cover || this.cover })
          if (this.thumbnails.length > 0 || !this.thumbnailsEnded || this.thumbnailsError.length > 0) {
            Column({ space: 14 }) {
              Text('预览（点击放大，不加载完整章节）').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.thumbnails, (url: string, index: number) => {
                    Column({ space: 8 }) {
                      Column() { DetailsMediaImage({ url: url, sourceKey: this.sourceKey, comicId: this.comicId }) }
                        .width(112).height(156).borderRadius(14).clip(true).onClick(() => { this.openViewer(this.thumbnails, index); })
                      Text(`${index + 1}`).fontSize(12).fontColor(UiTheme.muted)
                    }
                  }, (url: string, index: number) => `${index}:${url}`)
                }
              }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
              if (this.thumbnailsError.length > 0) { Text(this.thumbnailsError).fontSize(12).lineHeight(20).fontColor(UiTheme.danger).width('100%') }
              if (!this.thumbnailsEnded) {
                Button(this.thumbnailsLoading ? '预览加载中…' : (this.thumbnailsError.length > 0 ? '重试预览' : '加载更多预览'))
                  .attributeModifier(UiStyles.secondary).enabled(!this.thumbnailsLoading).onClick(() => { this.loadThumbnails(); })
              }
            }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
          Column({ space: 10 }) {
            Row() {
              Text('章节').fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).layoutWeight(1)
              Text(this.reverseChapters ? '倒序' : '正序').fontSize(13).fontColor(UiTheme.accent)
                .height(44).padding({ left: 14, right: 14 }).backgroundColor(UiTheme.accentSoft).borderRadius(13)
                .onClick(() => { this.toggleChapterOrder(); })
            }.width('100%')

            if (this.chapters() === undefined || (this.chapters()?.length ?? 0) === 0) {
              // Single-chapter comic: the reader treats it as one implicit
              // chapter, so say so instead of claiming the source returned none.
              Text('单章节漫画，点上方「继续阅读」恢复进度；首次阅读从第 1 页开始。')
                .fontSize(13).lineHeight(22)
                .fontColor(UiTheme.secondary)
                .width('100%')
            } else {
              ForEach(this.chapterSections, (section: ChapterSection) => {
                if (section.name.length > 0) {
                  Text(`${this.collapsedGroups.includes(section.name) ? '▸' : '▾'} ${section.name} (${section.entries.length})`)
                    .fontSize(14).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%').constraintSize({ minHeight: 48 }).padding({ top: 12, bottom: 12 })
                    .onClick(() => { this.toggleGroup(section.name); })
                }
                if (!this.collapsedGroups.includes(section.name)) {
                  ForEach(section.entries, (entry: ChapterEntry) => {
                    Row({ space: 12 }) {
                      Text(entry.title || entry.id).fontSize(14).fontColor(UiTheme.secondary).layoutWeight(1)
                      UiIcon({ name: 'chevron', iconSize: 16, color: UiTheme.muted })
                    }.width('100%').constraintSize({ minHeight: 52 }).padding({ top: 12, bottom: 12 })
                      .onClick(() => { this.openReader(entry.id); })
                  }, (entry: ChapterEntry) => entry.id)
                }
              }, (section: ChapterSection) => section.name)
            }
          }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          if ((this.details?.recommend?.length ?? 0) > 0) {
            Column({ space: 16 }) {
              Text('相关推荐').fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
              ForEach(this.details?.recommend ?? [], (comic: Comic) => {
                Row({ space: 14 }) {
                  Column() {
                    AsyncComicImage({ url: comic.cover, sourceKey: comic.sourceKey,
                      comicId: comic.id, thumbnail: true })
                  }.width(64).height(88).borderRadius(12).clip(true)
                  Column({ space: 8 }) {
                    Text(comic.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).maxLines(2)
                    Text(comic.subtitle).fontSize(12).fontColor(UiTheme.secondary).maxLines(1)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  UiIcon({ name: 'chevron', iconSize: 16, color: UiTheme.muted })
                }.width('100%').onClick(() => { this.openRecommendation(comic); })
              }, (comic: Comic, index: number) => `${comic.sourceKey}:${comic.id}:${index}`)
            }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
        }
      }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset }).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
