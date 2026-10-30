import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { ComicDetailsParams, ReaderParams } from '../model/RouteParams';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { History, HistoryDao } from '../storage/HistoryDao';
import { ComicType } from '../model/ComicType';
import { AsyncComicImage, ErrorView, LoadingView } from '../components/ComicWidgets';
import { ReaderOptions, ReaderSettings } from '../foundation/ReaderSettings';
import { ReaderSpread, ReaderSpreads } from '../features/ReaderSpreads';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { ReadingPosition } from '../features/ReadingPosition';
import { ChapterInfo, ReaderModes, READER_MODES } from '../features/ReaderModes';
import { ChapterEntry, ChapterSection, ChapterNavigation } from '../features/ChapterNavigation';
import { ReaderRenderItem, ReaderRenderSource } from '../features/ReaderRenderSource';
import { ReaderVolumeKeys } from '../features/ReaderVolumeKeys';
import { ReaderWorkload } from '../features/ReaderWorkload';
import batteryInfo from '@ohos.batteryInfo';
import { ReaderWindowChrome } from '../components/ReaderWindowChrome';
import { ReaderClickZones, ReaderCanvasGesture } from '../components/ReaderClickZones';

/** Paged / continuous reader. Persist only a validated, successfully loaded chapter. */
@Entry
@Component
struct ReaderPage {
  @State sourceKey: string = '';
  @State comicId: string = '';
  @State title: string = '';
  @State epId: string = '';
  @State chapterIds: string[] = [];
  @State chapterTitles: string[] = [];
  @State chapterSections: ChapterSection[] = [];
  @State images: string[] = [];
  /** Rendered order: right-to-left modes reverse it, exactly like upstream. */
  @State displayImages: string[] = [];
  @State displaySpreads: ReaderSpread[] = [];
  private flowSource: ReaderRenderSource = new ReaderRenderSource();
  private spreadSource: ReaderRenderSource = new ReaderRenderSource();
  /** Image lifetime is independent of the page-turn transform reset token. */
  private renderGeneration: number = 0;
  private renderScope: string = '';
  private renderedImages: string[] = [];
  @State options: ReaderOptions = new ReaderOptions();
  @State landscape: boolean = false;
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private viewportTop: number = 0;
  private viewportLeft: number = 0;
  private canvasGesture?: ReaderCanvasGesture;
  private canvasTapTimer: number = -1;
  private canvasTapVersion: number = 0;
  private canvasDownGeneration: number = -1;
  private canvasDownLoad: number = -1;
  private previousEndLoad: number = -1;
  private previousEndRender: number = -1;
  private previousEndPage: number = -1;
  private menuTransitionUntil: number = 0;
  private zoomedImages: Set<number> = new Set<number>();
  /** Decoded readiness belongs to one render generation, never a URL-list load. */
  private readyImages: Set<number> = new Set<number>();
  private visibleFirst: number = 0;
  private visibleLast: number = 0;
  /** Guards anchor restores that would otherwise fight the reader's scrolling. */
  private lastUserScrollAt: number = 0;
  @State private scrolling: boolean = false;
  @State private layoutPending: boolean = false;
  private layoutVersion: number = 0;
  @State settingsSaving: boolean = false;
  @State leavingReader: boolean = false;
  private settingsReloadVersion: number = 0;
  /** Always the actual SOURCE image index, never a spread/visual index. */
  @State currentPage: number = 0;
  @State loading: boolean = true;
  @State error: string = '';
  @State mode: string = 'waterfallTopToBottom';
  @State showChapters: boolean = false;
  @State showSpeedMenu: boolean = false;
  @State showModeMenu: boolean = false;
  @State speedDraft: number = 5;
  @State autoReading: boolean = false;
  @State zoomed: boolean = false;
  @State zoomReset: number = 0;
  private autoTimer: number = -1;
  private autoTrace: string = '';
  private keepScreenWindow?: window.Window;
  private oldKeepScreenOn: boolean = false;
  private keepScreenTail: Promise<void> = Promise.resolve();
  @State readerBrightness: number = -1;
  private oldBrightness: number = -1;
  private brightnessWindow?: window.Window;
  private brightnessTail: Promise<void> = Promise.resolve();

  private swiperController: SwiperController = new SwiperController();
  private listScroller: Scroller = new Scroller();
  private cover: string = '';
  private subtitle: string = '';
  private requestedEpId?: string;
  private requestedEpIndex?: number;
  private requestedPage?: number;
  private resumeRequested: boolean = false;
  private modeInitialized: boolean = false;
  private loadVersion: number = 0;
  /** Runtime-only resource lease, never persisted or used for statistics. */
  private readonly workloadOwner: string = `reader-window-${Date.now()}-${Math.random()}`;
  private disposed: boolean = false;
  @State private visible: boolean = true;
  @State progressReady: boolean = false;
  private lastSavedChapter: number = -1;
  private lastSavedPage: number = -1;
  private progressWriteVersion: number = 0;
  private progressTimer: number = -1;
  private restorePage: number = -1;
  private volumeKeys?: ReaderVolumeKeys;
  @State private volumeError: string = '';
  @State private toolbarVisible: boolean = false;
  private windowChrome?: ReaderWindowChrome;
  @State private immersiveError: string = '';
  @State private pressImage: number = -1;
  @State private pressX: number = 50;
  @State private pressY: number = 50;
  @State private clockInfo: string = '';
  private infoTimer: number = -1;

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.disposed = false;
    this.visible = true;
    this.toolbarVisible = false;
    this.showChapters = false;
    this.menuTransitionUntil = 0;
    const params = router.getParams() as ReaderParams;
    if (params !== undefined && params !== null) {
      this.sourceKey = params.sourceKey ?? '';
      this.comicId = params.comicId ?? '';
      this.title = params.title ?? '';
      this.cover = params.cover ?? '';
      this.requestedEpId = params.epId;
      this.requestedEpIndex = params.epIndex;
      this.requestedPage = params.page;
      this.resumeRequested = params.resume === true;
    }
    this.load();
    this.enterReaderFullscreen();
  }

  onPageShow(): void {
    this.visible = true;
    this.leavingReader = false;
    this.enterReaderFullscreen();
    this.reloadSettings();
    this.startReaderInfo();

  }

  onPageHide(): void {
    this.visible = false;
    this.releaseReaderControls();
    this.layoutVersion++;
    this.layoutPending = false;
    this.scrolling = false;
    this.stopAutoRead('页面隐藏');
    this.restoreBrightness();
    this.saveProgress(true);
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.releaseReaderControls();
    this.stopAutoRead('页面退出');
    this.restoreBrightness();
    this.saveProgress(true);
    this.disposed = true;
    this.loadVersion++;
  }

  private dismissReaderMenu(): void {
    this.cancelCanvasTap();
    this.showChapters = false;
    this.showSpeedMenu = false;
    this.showModeMenu = false;
    this.toolbarVisible = false;
    this.menuTransitionUntil = Date.now() + 180;
  }

  private revealReaderMenu(): void {
    this.cancelCanvasTap();
    this.showSpeedMenu = false;
    this.showModeMenu = false;
    this.toolbarVisible = true;
    this.menuTransitionUntil = Date.now() + 180;
    // autoStep pauses while this overlay is visible; its user's running intent
    // is retained so dismissing the menu resumes instead of disabling auto-read.
  }

  private openReaderChapterMenu(): void {
    if (!this.progressReady || this.loading) { return; }
    this.dismissReaderMenu();
    this.showChapters = true;
  }

  onBackPress(): boolean {
    if (this.showSpeedMenu || this.showModeMenu) {
      this.showSpeedMenu = false;
      this.showModeMenu = false;
      return true;
    }
    if (this.showChapters || this.toolbarVisible) { this.dismissReaderMenu(); return true; }
    if (this.autoReading) { this.stopAutoRead('用户返回停止自动阅读'); return true; }
    return false;
  }

  private isCurrentLoad(version: number): boolean {
    return !this.disposed && version === this.loadVersion;
  }

  private async load(): Promise<void> {
    this.saveProgress(true);
    const version = ++this.loadVersion;
    this.progressReady = false;
    this.loading = true;
    this.error = '';
    try {
      await AppInit.init();
      if (!this.isCurrentLoad(version)) {
        return;
      }
      if (!this.modeInitialized) {
        this.options = ReaderSettings.resolve(this.comicId, this.sourceKey);
        this.mode = ReaderModes.normalize(this.options.readerMode);
        this.modeInitialized = true;
      }
      const source = SourceManager.find(this.sourceKey);
      if (source === undefined) {
        throw new Error(`漫画源不存在: ${this.sourceKey}`);
      }
      await this.loadChapters(source, version);
      if (!this.isCurrentLoad(version)) {
        return;
      }
      if (this.resumeRequested) {
        const history = await HistoryDao.find(this.comicId, ComicType.fromKey(source.key).value);
        if (!this.isCurrentLoad(version)) {
          return;
        }
        if (history !== undefined) {
          this.requestedEpId = history.epId;
          this.requestedEpIndex = history.ep;
          this.requestedPage = history.page;
          if (this.title.length === 0) {
            this.title = history.title;
          }
          if (this.cover.length === 0) {
            this.cover = history.cover;
          }
          if (this.subtitle.length === 0) {
            this.subtitle = history.subtitle;
          }
        }
      }
      const position = ReadingPosition.resolveChapter(this.chapterIds, this.requestedEpId, this.requestedEpIndex);
      if (position.error.length > 0) {
        throw new Error(position.error);
      }
      await this.loadPages(source, this.chapterIds[position.chapterIndex], this.requestedPage, version);
    } catch (error) {
      if (this.isCurrentLoad(version)) {
        this.error = error instanceof Error ? error.message : String(error);
        Log.error('ReaderPage', this.error);
      }
    } finally {
      if (this.isCurrentLoad(version)) {
        this.loading = false;
        this.syncVolumeKeys();
      }
    }
  }

  private async loadChapters(source: ComicSource, version: number): Promise<void> {
    if (source.loadComicInfo === undefined) {
      throw new Error(`${source.name} 不支持详情加载，无法确认章节`);
    }
    const result = await source.loadComicInfo(this.comicId);
    if (!this.isCurrentLoad(version)) {
      return;
    }
    if (result.error) {
      throw new Error(result.errorMessage ?? '详情加载失败，无法确认章节');
    }
    const details: ComicDetails | undefined = result.dataOrNull;
    if (details === undefined) {
      throw new Error('详情返回空数据，无法确认章节；原阅读记录已保留。');
    }
    this.sourceKey = source.key;
    if (details.title.length > 0) {
      this.title = details.title;
    }
    if (details.cover.length > 0) {
      this.cover = details.cover;
    }
    this.subtitle = details.findAuthor() ?? details.subTitle ?? this.subtitle;
    const chapters: ComicChapters | undefined = details.chapters;
    if (chapters !== undefined && chapters.length > 0) {
      this.chapterIds = chapters.ids;
      this.chapterTitles = chapters.titles;
      this.chapterSections = ChapterNavigation.sections(chapters, false, `reader-chapters-${Date.now()}`);
      return;
    }
    // Only a successful, nonempty detail object may identify an implicit chapter.
    // A source error / missing detail object must never masquerade as this case.
    this.chapterIds = [''];
    this.chapterTitles = [this.title];
    const implicit = new ChapterSection();
    const entry = new ChapterEntry();
    entry.id = ''; entry.title = this.title; entry.canonicalIndex = 0;
    implicit.entries = [entry]; this.chapterSections = [implicit];
  }

  private async loadPages(source: ComicSource, epId: string, page: number | undefined,
    version: number): Promise<void> {
    const position = ReadingPosition.resolveChapter(this.chapterIds, epId);
    if (position.error.length > 0) {
      throw new Error(position.error);
    }
    if (source.loadComicPages === undefined) {
      throw new Error(`${source.name} 不支持章节加载`);
    }
    const result = await source.loadComicPages(this.comicId, epId);
    if (!this.isCurrentLoad(version)) {
      return;
    }
    if (result.error) {
      throw new Error(result.errorMessage ?? '章节加载失败');
    }
    const images: string[] = result.dataOrNull ?? [];
    const pageIndex = ReadingPosition.pageIndex(page, images.length);
    if (pageIndex < 0 || images.some((url: string) => url.trim().length === 0)) {
      throw new Error('该章节没有有效图片；原阅读记录已保留。');
    }
    // Commit together only after validating the response. Until here ep/page
    // still refer to the previous successful chapter, whose history is retained.
    this.epId = epId;
    this.currentPage = pageIndex;
    this.images = images;
    this.rebuildPresentation();
    this.restorePage = this.sourceToDisplay(pageIndex);
    this.requestedEpId = epId;
    this.requestedEpIndex = undefined;
    this.requestedPage = pageIndex + 1;
    this.resumeRequested = false;
    this.progressReady = true;
    this.lastSavedChapter = -1;
    this.lastSavedPage = -1;
    if (this.visible) {
    }
    this.saveProgress();
  }

  private currentChapterIndex(): number {
    return this.chapterIds.indexOf(this.epId);
  }

  private async switchChapter(offset: number): Promise<void> {
    const index = this.currentChapterIndex();
    if (index < 0) {
      return;
    }
    const next = index + offset;
    if (next < 0 || next >= this.chapterIds.length) {
      promptAction.showToast({ message: offset > 0 ? '已经是最后一章' : '已经是第一章' });
      return;
    }
    await this.goToChapter(next);
  }

  /** Jump straight to a chapter index, used by the chapter list overlay. */
  private async goToChapter(next: number): Promise<void> {
    // A second tap cannot start another request or mutate the in-flight target.
    if (this.loading || this.disposed || !this.progressReady) {
      return;
    }
    if (next < 0 || next >= this.chapterIds.length || next === this.currentChapterIndex()) {
      this.showChapters = false;
      return;
    }
    this.showChapters = false;
    this.resetZoom();
    // DAO writes synchronously before returning its Promise. Flush the OLD
    // chapter before changing the request, and exclude network time from reading.
    this.saveProgress(true);
    this.progressReady = false;
    this.loading = true;
    this.error = '';
    this.requestedEpId = this.chapterIds[next];
    this.requestedEpIndex = undefined;
    this.requestedPage = 1;
    this.resumeRequested = false;
    const version = ++this.loadVersion;
    try {
      const source = SourceManager.find(this.sourceKey);
      if (source === undefined) {
        throw new Error(`漫画源不存在: ${this.sourceKey}`);
      }
      await this.loadPages(source, this.requestedEpId, 1, version);
    } catch (error) {
      if (this.isCurrentLoad(version)) {
        this.error = error instanceof Error ? error.message : String(error);
        Log.error('ReaderPage', this.error);
      }
    } finally {
      if (this.isCurrentLoad(version)) {
        this.loading = false;
        this.syncVolumeKeys();
      }
    }
  }

  /** Page-turn callbacks schedule metadata only; HistoryDao performs synchronous disk IO. */
  private saveProgress(flushNow: boolean = false): void {
    if (flushNow) {
      if (this.progressTimer >= 0) { clearTimeout(this.progressTimer); this.progressTimer = -1; }
      this.flushProgress();
      return;
    }
    if (this.progressTimer >= 0 || !this.progressReady || this.disposed) { return; }
    this.progressTimer = setTimeout(() => {
      this.progressTimer = -1;
      this.flushProgress();
    }, 500);
  }

  private flushProgress(): void {
    const now = Date.now();
    const chapter = this.currentChapterIndex();
    if (!this.progressReady || chapter < 0 || this.images.length === 0 ||
      this.currentPage < 0 || this.currentPage >= this.images.length) {
      return;
    }
    // Only save the position needed to resume; no reading-time or event statistics.
    if (this.currentPage === this.lastSavedPage && chapter === this.lastSavedChapter ) {
      return;
    }
    const history = new History();
    history.id = this.comicId;
    history.type = ComicType.fromKey(this.sourceKey);
    history.storedSourceKey = this.sourceKey;
    history.epId = this.epId;
    history.title = this.title;
    history.subtitle = this.subtitle;
    history.cover = this.cover;
    history.time = now;
    history.ep = chapter + 1;
    history.page = this.currentPage + 1;
    history.maxPage = this.images.length;
    this.lastSavedPage = this.currentPage;
    this.lastSavedChapter = chapter;
    const writeVersion = ++this.progressWriteVersion;
    HistoryDao.save(history).catch((error: Object) => {
      if (writeVersion === this.progressWriteVersion) {
        this.lastSavedPage = -1; this.lastSavedChapter = -1;
      }
      Log.warn('ReaderPage', 'resume position save failed; next flush may retry');
      if (!this.disposed) {
        promptAction.showToast({ message: '阅读进度保存失败，请检查存储空间。' });
      }
    });
  }

  private imagesPerScreen(): number {
    return ReaderModes.isGallery(this.mode) ? ReaderSpreads.perScreen(
      this.options.readerScreenPicNumberForPortrait, this.options.readerScreenPicNumberForLandscape,
      this.landscape) : 1;
  }

  private sourceToDisplay(actual: number): number {
    return ReaderModes.isGallery(this.mode) ? ReaderSpreads.sourceToDisplay(actual, this.images.length,
      this.imagesPerScreen(), this.options.showSingleImageOnFirstPage, ReaderModes.isReversed(this.mode)) :
      ReaderModes.toDisplayIndex(this.mode, actual, this.images.length);
  }

  private rebuildPresentation(): void {
    this.resetZoom();
    // Rotation is a layout change, not a new image request lifetime. Mode changes
    // may replace containers, while chapter/reload must reject late old callbacks.
    const scope = `${this.sourceKey}:${this.comicId}:${this.epId}:${this.loadVersion}:${this.mode}`;
    if (scope !== this.renderScope || this.renderedImages !== this.images) {
      this.renderScope = scope;
      this.renderedImages = this.images;
      this.renderGeneration++;
      this.readyImages.clear();
    }
    this.displayImages = ReaderModes.displayOrder(this.mode, this.images);
    this.displaySpreads = ReaderSpreads.create(this.images.length, this.imagesPerScreen(),
      this.options.showSingleImageOnFirstPage, ReaderModes.isReversed(this.mode));
    this.flowSource.setFlow(scope, this.images, this.mode, this.renderGeneration);
    this.spreadSource.setSpreads(scope, this.displaySpreads, this.renderGeneration);
    this.visibleFirst = this.sourceToDisplay(this.currentPage);
    this.visibleLast = this.visibleFirst;
  }

  private resetZoom(): void {
    this.layoutVersion++;
    this.layoutPending = false;
    this.zoomedImages.clear();
    this.pressImage = -1;
    this.zoomed = false;
    this.zoomReset++;
  }

  private isVisibleImage(actual: number): boolean {
    if (ReaderModes.isGallery(this.mode)) {
      return this.sourceToDisplay(actual) === this.sourceToDisplay(this.currentPage);
    }
    const display = this.sourceToDisplay(actual);
    return display >= this.visibleFirst && display <= this.visibleLast;
  }

  private onImageReady(actual: number, generation: number, value: boolean): void {
    if (generation !== this.renderGeneration || this.disposed || !Number.isFinite(actual) ||
      Math.floor(actual) !== actual || actual < 0 || actual >= this.images.length) { return; }
    // LazyForEach's bounded cached neighbors may finish before becoming current.
    // Keep their readiness; a counter update must not demand another decode.

    if (value) { this.readyImages.add(actual); } else { this.readyImages.delete(actual); }
  }

  private visibleImagesReady(): boolean {
    if (!ReaderModes.isGallery(this.mode)) { return this.readyImages.has(this.currentPage); }
    const spread = this.displaySpreads[this.sourceToDisplay(this.currentPage)];
    return spread !== undefined && spread.imageIndices.length > 0 &&
      spread.imageIndices.every((actual: number) => this.readyImages.has(actual));
  }

  private onImageZoom(actual: number, generation: number, value: boolean): void {
    if (generation !== this.zoomReset || this.disposed || !this.isVisibleImage(actual)) { return; }
    if (value) { this.zoomedImages.add(actual); } else { this.zoomedImages.delete(actual); }
    this.refreshZoomState();
  }

  private refreshZoomState(): void {
    let zoomed = this.pressImage >= 0;
    this.zoomedImages.forEach((actual: number) => {
      if (this.isVisibleImage(actual)) { zoomed = true; }
    });
    this.zoomed = zoomed;
  }

  private updatePage(displayIndex: number): void {
    const count = ReaderModes.isGallery(this.mode) ? this.displaySpreads.length : this.displayImages.length;
    if (this.disposed || !this.visible || this.loading || !this.progressReady || this.layoutPending ||
      !Number.isFinite(displayIndex) || Math.floor(displayIndex) !== displayIndex ||
      displayIndex < 0 || displayIndex >= count) { return; }
    if (this.restorePage >= 0) {
      if (displayIndex !== this.restorePage) { return; }
      this.restorePage = -1;
    }
    // A regrouping callback for the SAME spread must not replace the source
    // image restored from history with the beginning of its new group.
    if (ReaderModes.isGallery(this.mode) && displayIndex === this.sourceToDisplay(this.currentPage)) { return; }
    const actual = ReaderModes.isGallery(this.mode) ? ReaderSpreads.displayToSource(displayIndex,
      this.images.length, this.imagesPerScreen(), this.options.showSingleImageOnFirstPage,
      ReaderModes.isReversed(this.mode)) : ReaderModes.toActualIndex(this.mode, displayIndex, this.images.length);
    if (actual !== this.currentPage) {
      this.resetZoom();
      this.currentPage = actual;
      this.requestedPage = actual + 1;
      this.saveProgress();
    }
  }

  private seekPage(actual: number): void {
    if (this.loading || !this.progressReady || this.disposed || !this.visible ||
      !Number.isFinite(actual) || Math.floor(actual) !== actual || actual < 0 || actual >= this.images.length) { return; }
    this.resetZoom();
    this.currentPage = actual;
    this.requestedPage = actual + 1;
    const display = this.sourceToDisplay(actual);
    this.restorePage = display;
    this.saveProgress();
    if (ReaderModes.isGallery(this.mode)) {
      this.swiperController.changeIndex(display, this.options.enablePageAnimation);
    } else {
      this.listScroller.scrollToIndex(display, this.options.enablePageAnimation);
    }
    Log.audit(`reader-seek-${Date.now()}`, '跳页', `存储页=${actual + 1}；显示索引=${display}；模式=${this.mode}`);
  }

  private adjacentSource(offset: number): number {
    if (ReaderModes.isGallery(this.mode)) {
      return ReaderSpreads.nextSource(this.currentPage, this.images.length, this.imagesPerScreen(),
        this.options.showSingleImageOnFirstPage, offset);
    }
    const next = this.currentPage + offset;
    return next >= 0 && next < this.images.length ? next : -1;
  }

  private stepPage(offset: number): void {
    const next = this.adjacentSource(offset);
    if (next >= 0) { this.seekPage(next); }
  }

  private retryReaderContent(): void {
    this.cancelCanvasTap(); this.canvasGesture?.cancel();
    this.load();
  }

  private cancelCanvasTap(): void {
    this.canvasTapVersion++;
    this.canvasGesture?.cancel();
    if (this.canvasTapTimer >= 0) { clearTimeout(this.canvasTapTimer); this.canvasTapTimer = -1; }
  }

  /** Read raw touch bubbling from the stable canvas, never intercept native
   * pinch/swipe recognizers. This also covers margins and unloaded pictures. */
  private onReaderSurfaceTouch(event: TouchEvent): void {
    const finger = event.type === TouchType.Up ? event.changedTouches[0] : event.touches[0];
    if (event.type === TouchType.Down) {
      this.cancelCanvasTap(); this.canvasGesture?.cancel();
      this.previousEndLoad = -1;
      if (!this.visible || this.disposed || this.leavingReader || this.toolbarVisible || this.showChapters ||
        Date.now() < this.menuTransitionUntil || finger === undefined) { return; }
      if (this.canvasGesture === undefined) { this.canvasGesture = new ReaderCanvasGesture(); }
      this.canvasDownGeneration = this.zoomReset;
      this.canvasDownLoad = this.loadVersion;
      this.canvasGesture.begin(finger.windowX, finger.windowY, Date.now(), event.touches.length);
    } else if (event.type === TouchType.Move) {
      if (finger !== undefined) { this.canvasGesture?.move(finger.windowX, finger.windowY, event.touches.length); }
    } else if (event.type === TouchType.Cancel) {
      this.cancelCanvasTap(); this.canvasGesture?.cancel();
    } else if (event.type === TouchType.Up) {
      if (finger === undefined || this.canvasGesture === undefined) { return; }
      if (this.canvasDownGeneration !== this.zoomReset || this.canvasDownLoad !== this.loadVersion) {
        this.cancelCanvasTap(); return;
      }
      // ArkUI may retain the released contact in touches on Up. Count only
      // contacts that were NOT released/cancelled by this event, not list length.
      const remaining = event.touches.filter((touch: TouchObject) =>
        !event.changedTouches.some((changed: TouchObject) => changed.id === touch.id)).length;
      if (!this.canvasGesture.end(finger.windowX, finger.windowY, Date.now(), remaining)) { return; }
      const width = this.viewportWidth; const height = this.viewportHeight;
      if (width <= 0 || height <= 0) { return; }
      const x = (this.canvasGesture.downX - this.viewportLeft) / width;
      const y = (this.canvasGesture.downY - this.viewportTop) / height;
      const version = this.canvasTapVersion; const generation = this.zoomReset;
      const load = this.loadVersion;
      this.canvasTapTimer = setTimeout((): void => {
        this.canvasTapTimer = -1;
        if (version !== this.canvasTapVersion || generation !== this.zoomReset || load !== this.loadVersion ||
          width !== this.viewportWidth || height !== this.viewportHeight) { return; }
        this.onReaderViewportTap(x, y);
      }, ReaderCanvasGesture.delayMs);
    }
  }

  /** Independent of individual image readiness: menu access must remain usable
   * in blank margins, on loading/error screens and in multi-image layouts. */
  private onReaderViewportTap(x: number, y: number): void {
    if (!this.visible || this.disposed || this.leavingReader || Date.now() < this.menuTransitionUntil) { return; }
    const action = ReaderClickZones.action(x, y, this.options.enableTapToTurnPages,
      this.mode === 'galleryRightToLeft' || this.mode === 'continuousRightToLeft', this.options.reverseTapToTurnPages);
    if (action === 'none') { return; }
    if (this.toolbarVisible || this.showChapters) { this.dismissReaderMenu(); return; }
    if ((this.scrolling && !this.autoReading) || this.layoutPending) { return; }
    if (action === 'menu') { this.revealReaderMenu(); return; }
    if (this.zoomed || this.loading || !this.progressReady || this.error.length > 0 ||
      !this.visibleImagesReady()) { return; }
    this.stopAutoRead('用户点击阅读区域翻页');
    this.turnReaderViewport(action === 'next' ? 1 : -1);
  }

  private turnReaderViewport(offset: number): void {
    if (ReaderModes.isGallery(this.mode)) {
      if (this.adjacentSource(offset) >= 0) { this.stepPage(offset); }
      else { this.turnReaderChapter(offset); }
      return;
    }
    // Like Legado's image scroll delegate: one tap scrolls one VISIBLE screen,
    // not one possibly several-screen-tall image. Scroll callbacks save progress.
    const vertical = ReaderModes.isVertical(this.mode);
    const distance = vertical ? this.viewportHeight : this.viewportWidth;
    if (!Number.isFinite(distance) || distance <= 0) { return; }
    const position = this.listScroller.currentOffset();
    const axisOffset = vertical ? position.yOffset : position.xOffset;
    const reversed = ReaderModes.isReversed(this.mode);
    const sign = reversed ? -offset : offset;
    if (sign < 0 && axisOffset <= 0) { this.turnReaderChapter(offset); return; }
    if (sign > 0 && this.listScroller.isAtEnd()) { this.turnReaderChapter(offset); return; }
    this.listScroller.scrollBy(vertical ? 0 : sign * distance, vertical ? sign * distance : 0);
  }

  private setBrightnessValue(percent: number): void {
    const val = Math.max(0.1, Math.min(1.0, percent / 100));
    this.brightnessTail = this.brightnessTail.then(async (): Promise<void> => {
      if (this.disposed || !this.visible) { return; }
      if (this.brightnessWindow === undefined) {
        const host = await window.getLastWindow(AppContext.context);
        if (this.disposed || !this.visible) { return; }
        this.brightnessWindow = host;
        this.oldBrightness = host.getWindowProperties().brightness;
      }
      await this.brightnessWindow.setWindowBrightness(val);
      this.readerBrightness = val;
    }).catch((error: Object) => { Log.warn('ReaderPage', 'slider brightness setting failed'); });
  }

  private openAutoSpeedMenu(): void {
    this.cancelCanvasTap();
    this.speedDraft = Math.round(Math.max(0.1, Math.min(10, this.options.autoPageTurningInterval)) * 10) / 10;
    this.showSpeedMenu = true;
  }

  private selectAutoSpeed(seconds: number): void {
    if (!Number.isFinite(seconds) || this.disposed || !this.visible || this.loading || !this.progressReady) { return; }
    const selected = Math.round(Math.max(0.1, Math.min(10, seconds)) * 10) / 10;
    this.stopAutoRead('调整每页停留时间');
    this.options.autoPageTurningInterval = selected;
    this.speedDraft = selected;
    // Apply this reading session's speed without mutating global/device prefs.
    this.dismissReaderMenu();
    this.toggleAutoRead();
  }

  private async selectComicMode(targetMode: string): Promise<void> {
    this.showModeMenu = false;
    await this.setMode(targetMode);
  }

  private async turnReaderChapter(offset: number): Promise<void> {
    const next = this.currentChapterIndex() + offset;
    if (next < 0 || next >= this.chapterIds.length) { return; }
    const target = this.chapterIds[next]; const load = this.loadVersion;
    this.previousEndLoad = -1;
    await this.switchChapter(offset);
    if (this.disposed || !this.visible || this.loading || !this.progressReady || this.error.length > 0 ||
      this.epId !== target || this.loadVersion !== load + 1 || this.images.length === 0) { return; }
    if (offset < 0) {
      this.seekPage(this.images.length - 1);
      if (!ReaderModes.isGallery(this.mode)) {
        this.previousEndLoad = this.loadVersion;
        this.previousEndRender = this.renderGeneration;
        this.previousEndPage = this.currentPage;
        this.alignPreviousChapterEnd();
      }
    }
  }

  private alignPreviousChapterEnd(): void {
    if (this.previousEndLoad !== this.loadVersion || this.previousEndRender !== this.renderGeneration ||
      this.previousEndPage !== this.currentPage || !this.visible || this.disposed || this.loading ||
      !this.progressReady || ReaderModes.isGallery(this.mode)) { return; }
    // Image decode can resize this last (possibly tall) page. Keep END aligned
    // until the next user contact, and invalidate an older START restore task.
    this.layoutVersion++; this.layoutPending = false;
    const display = this.sourceToDisplay(this.currentPage);
    this.restorePage = display;
    this.listScroller.scrollToIndex(display, false, ScrollAlign.END);
  }

  private previousRouteIsThisDetails(): boolean {
    const current = router.getState();
    if (current.index <= 1) { return false; }
    const previous = router.getStateByIndex(current.index - 1);
    if (previous === undefined) { return false; }
    // RouterState.name is documented as the file name: accept its explicit
    // script/source extension too, even if path is only the containing folder.
    const isDetails = /^ComicDetailsPage(?:\.(?:js|ets))?$/.test(previous.name) ||
      /^\/?pages\/ComicDetailsPage(?:\.(?:js|ets))?$/.test(previous.path);
    const params = previous.params as ComicDetailsParams;
    const hasParams = params !== undefined && params !== null;
    const sameComic = hasParams && params.sourceKey === this.sourceKey && params.comicId === this.comicId;
    Log.audit(`reader-details-route-${Date.now()}`, '详情前驱路由核对',
      `前驱序号=${current.index - 1}；详情页=${isDetails}；有参数=${hasParams}；同漫画=${sameComic}；不记录参数内容`);
    return isDetails && sameComic;
  }

  /** Details is not generic Back: continue-reading may have come directly from Home/History. */
  private async openComicDetails(): Promise<void> {
    if (this.leavingReader || this.disposed || this.sourceKey.length === 0 || this.comicId.length === 0) { return; }
    const params: ComicDetailsParams = { sourceKey: this.sourceKey, comicId: this.comicId,
      title: this.title, cover: this.cover };
    this.leavingReader = true;
    this.visible = false;
    this.releaseReaderControls();
    this.stopAutoRead('返回漫画详情');
    this.saveProgress(true);
    this.restoreBrightness();
    try {
      await this.brightnessTail;
      await this.keepScreenTail;
      if (this.disposed) { return; }
      if (this.previousRouteIsThisDetails()) { router.back(); }
      else {
        // Replace only Reader, preserving the originating Home/History route beneath.
        // Pushing would retain a stale Reader and create Details→Reader→Details loops.
        await router.replaceUrl({ url: 'pages/ComicDetailsPage', params: params });
      }
    } catch (error) {
      this.leavingReader = false;
      if (!this.disposed) {
        this.visible = true;
        Log.error('ReaderPage', 'cannot return to comic details');
        promptAction.showToast({ message: '无法打开漫画详情，请重试。' });
      }
    }
  }

  private returnToPrevious(): void {
    if (this.leavingReader || this.disposed) { return; }
    this.leavingReader = true;
    this.visible = false;
    this.releaseReaderControls();
    this.stopAutoRead('普通返回');
    this.saveProgress(true);
    this.restoreBrightness();
    this.disposed = true;
    this.loadVersion++;
    router.back();
  }

  private pageCounter(): string {
    return this.progressReady ? ReaderSpreads.pageCounter(this.currentPage, this.images.length,
      this.imagesPerScreen(), ReaderModes.isGallery(this.mode) && this.options.showSingleImageOnFirstPage) : '— / —';
  }

  private cycleBrightness(): void {
    const values = [-1, 0.35, 0.7, 1];
    const index = values.indexOf(this.readerBrightness);
    const next = values[(index + 1) % values.length];
    this.brightnessTail = this.brightnessTail.then(async (): Promise<void> => {
      if (this.disposed || !this.visible) { return; }
      if (this.brightnessWindow === undefined) {
        const host = await window.getLastWindow(AppContext.context);
        if (this.disposed || !this.visible) { return; }
        this.brightnessWindow = host;
        this.oldBrightness = host.getWindowProperties().brightness;
      }
      await this.brightnessWindow.setWindowBrightness(next);
      this.readerBrightness = next;
      Log.audit(`reader-brightness-${Date.now()}`, '窗口亮度', `值=${next}；只修改本应用窗口，退出时恢复`);
    }).catch((error: Object) => { Log.warn('ReaderPage', 'window brightness operation failed'); });
  }

  private restoreBrightness(): void {
    this.brightnessTail = this.brightnessTail.then(async (): Promise<void> => {
      const host = this.brightnessWindow;
      if (host === undefined) { return; }
      await host.setWindowBrightness(this.oldBrightness);
      this.brightnessWindow = undefined;
      this.readerBrightness = -1;
      Log.audit(`reader-brightness-${Date.now()}`, '窗口亮度恢复', '恢复进入前的窗口亮度，不修改系统设置');
    }).catch((error: Object) => { Log.warn('ReaderPage', 'cannot restore reader window brightness'); });
  }

  private stopAutoRead(reason: string): void {
    if (this.autoTimer >= 0) {
      clearInterval(this.autoTimer);
      this.autoTimer = -1;
    }
    if (this.autoReading) {
      Log.audit(this.autoTrace, '自动阅读停止', reason);
    }
    this.autoReading = false;
    this.syncAutoKeepScreenOn();
  }

  private syncAutoKeepScreenOn(): void {
    this.keepScreenTail = this.keepScreenTail.then(async (): Promise<void> => {
      if (this.autoReading && this.visible && !this.disposed) {
        if (this.keepScreenWindow === undefined) {
          const host = await window.getLastWindow(AppContext.context);
          if (!this.autoReading || !this.visible || this.disposed) { return; }
          this.oldKeepScreenOn = host.getWindowProperties().isKeepScreenOn;
          await host.setWindowKeepScreenOn(true);
          this.keepScreenWindow = host;
          Log.audit(this.autoTrace, '自动阅读亮屏', '暂时保持本应用窗口亮屏，暂停/退出后恢复原值');
        }
      } else if (this.keepScreenWindow !== undefined) {
        await this.keepScreenWindow.setWindowKeepScreenOn(this.oldKeepScreenOn);
        this.keepScreenWindow = undefined;
        Log.audit(this.autoTrace, '自动阅读亮屏恢复', '恢复原窗口亮屏策略；不解除锁屏或修改系统设置');
      }
    }).catch((error: Object) => { Log.audit(this.autoTrace, '自动阅读亮屏异常', '窗口策略操作失败；计时器停止与页面退出保护仍生效'); });
  }

  private async autoStep(): Promise<void> {
    if (!this.autoReading || this.toolbarVisible || this.showChapters || this.loading || !this.progressReady ||
      this.disposed || !this.visible || this.zoomed) {
      return;
    }
    if (this.scrolling || this.layoutPending || !this.visibleImagesReady()) { return; }
    if (!ReaderModes.isGallery(this.mode)) {
      const position = this.listScroller.currentOffset();
      const reversed = ReaderModes.isReversed(this.mode);
      const atEnd = reversed ? position.xOffset <= 0 : this.listScroller.isAtEnd();
      if (atEnd && !this.options.autoReadingAcrossChapters) { this.stopAutoRead('连续阅读已到末尾'); return; }
      if (atEnd && this.currentChapterIndex() + 1 >= this.chapterIds.length) { this.stopAutoRead('已到最后一章末页'); return; }
      this.turnReaderViewport(1);
      return;
    }
    const next = this.adjacentSource(1);
    if (next >= 0) {
      this.seekPage(next);
    } else if (this.options.autoReadingAcrossChapters && this.currentChapterIndex() + 1 < this.chapterIds.length) {
      await this.switchChapter(1);
    } else {
      this.stopAutoRead('已到最后一章末页');
    }
  }

  private toggleAutoRead(): void {
    if (this.autoReading) {
      this.stopAutoRead('用户暂停');
      return;
    }
    if (this.loading || !this.progressReady || this.disposed || !this.visible) {
      return;
    }
    this.autoReading = true;
    this.autoTrace = `reader-auto-${Date.now()}`;
    const interval = this.options.autoPageTurningInterval;
    const seconds = Number.isFinite(interval) ? Math.max(0.1, Math.min(10, interval)) : 5;
    Log.audit(this.autoTrace, '自动阅读开始', `间隔=${seconds}秒；后台/缩放/加载期间不翻页`);
    this.syncAutoKeepScreenOn();
    const delay = Math.round(seconds * 1000);
    this.autoTimer = setInterval(() => { this.autoStep().catch((error: Object) => { this.stopAutoRead('自动滚动不可用'); }); }, delay);
  }

  private async reloadSettings(): Promise<void> {
    const version = ++this.settingsReloadVersion;
    try {
      await AppInit.init();
      if (version !== this.settingsReloadVersion || this.disposed || !this.visible) { return; }
      this.applySettings(ReaderSettings.resolve(this.comicId, this.sourceKey));
      this.modeInitialized = true;
    } catch (error) {
      Log.error('ReaderPage', `reader settings reload failed: ${String(error)}`);
      if (!this.disposed && this.visible) { promptAction.showToast({ message: '阅读设置加载失败，请重试。' }); }
    }
  }

  private applySettings(options: ReaderOptions): void {
    const reflow = this.mode !== ReaderModes.normalize(options.readerMode) ||
      this.options.readerScreenPicNumberForPortrait !== options.readerScreenPicNumberForPortrait ||
      this.options.readerScreenPicNumberForLandscape !== options.readerScreenPicNumberForLandscape ||
      this.options.showSingleImageOnFirstPage !== options.showSingleImageOnFirstPage ||
      this.options.splitDualPage !== options.splitDualPage ||
      this.options.splitDualPageInvert !== options.splitDualPageInvert ||
      this.options.readerSideMargin !== options.readerSideMargin || this.options.limitImageWidth !== options.limitImageWidth;
    this.options = options;
    this.mode = ReaderModes.normalize(options.readerMode);
    this.syncVolumeKeys();
    this.applyReaderBrightness();
    if (this.autoReading) { this.stopAutoRead('阅读设置已变更'); }
    if (reflow) { this.relayout(); }
  }

  /** Persist atomically before changing live presentation; never silently ignore failures. */
  private async setMode(next: string): Promise<void> {
    const normalized = ReaderModes.normalize(next);
    if (normalized === this.mode || this.settingsSaving) { return; }
    this.settingsSaving = true;
    try {
      await ReaderSettings.set('comic', this.comicId, this.sourceKey, 'readerMode', normalized);
      if (!this.disposed) { this.applySettings(ReaderSettings.resolve(this.comicId, this.sourceKey)); }
    } catch (error) {
      Log.error('ReaderPage', `reader mode persistence failed: ${String(error)}`);
      if (!this.disposed) { promptAction.showToast({ message: '阅读模式保存失败，已保留原设置。' }); }
    } finally {
      this.settingsSaving = false;
    }
  }

  private openReaderSettings(): void {
    this.stopAutoRead('打开阅读设置');
    router.pushUrl({ url: 'pages/ReaderSettingsPage', params: { comicId: this.comicId, sourceKey: this.sourceKey } })
      .catch((error: Object) => {
        Log.error('ReaderPage', `cannot open reader settings: ${String(error)}`);
        promptAction.showToast({ message: '无法打开阅读设置。' });
      });
  }

  private isVerticalFlow(): boolean {
    return this.mode === 'continuousTopToBottom' || this.mode === 'waterfallTopToBottom';
  }

  private flowWidth(): string {
    const margin = Number.isFinite(this.options.readerSideMargin) ?
      Math.max(0, Math.min(30, this.options.readerSideMargin)) : 0;
    return this.isVerticalFlow() ? `${100 - 2 * margin}%` : '100%';
  }

  private onViewportSize(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 ||
      (width === this.viewportWidth && height === this.viewportHeight)) { return; }
    this.viewportWidth = width;
    this.viewportHeight = height;
    this.landscape = width > height;
    this.relayout();
  }

  private relayout(): void {
    this.scrolling = false;
    this.rebuildPresentation();
    this.scheduleAnchorRestore();
  }

  private scheduleAnchorRestore(): void {
    if (!this.progressReady || this.loading || this.disposed || !this.visible) { return; }
    this.restorePage = this.sourceToDisplay(this.currentPage);
    this.layoutPending = true;
    const version = ++this.layoutVersion;
    const generation = this.zoomReset;
    setTimeout(() => {
      if (version !== this.layoutVersion || generation !== this.zoomReset || this.disposed || !this.visible) { return; }
      this.layoutPending = false;
      if (ReaderModes.isGallery(this.mode)) {
        this.swiperController.changeIndex(this.sourceToDisplay(this.currentPage), false);
      } else { this.restoreWaterfall(); }
    }, 0);
  }

  private onFlowImageSize(display: number, generation: number, oldHeight: number, height: number): void {
    if (generation !== this.renderGeneration || !this.isVerticalFlow() || this.scrolling ||
      oldHeight === height || Date.now() - this.lastUserScrollAt < 600) { return; }
    // Only a change strictly ABOVE the first visible item shifts the reader and
    // needs an anchor restore. Restoring for the visible item itself (its own
    // decode completes or a tall page re-lays out) pulled the list back to that
    // item's top on every change, which made scrolling down feel like it bounced.
    if (display >= this.visibleFirst) { return; }
    this.scheduleAnchorRestore();
  }

  private restoreWaterfall(): void {
    if (this.progressReady && this.images.length > 0 && this.visible && !this.disposed) {
      this.listScroller.scrollToIndex(this.sourceToDisplay(this.currentPage), false, ScrollAlign.START);
    }
  }

  private releaseRestoreOnTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.layoutVersion++;
      this.layoutPending = false;
      this.restorePage = -1;
    }
  }

  private chapterTitle(): string {
    const index = this.currentChapterIndex();
    return index >= 0 && index < this.chapterTitles.length ? this.chapterTitles[index] : '';
  }

  private syncVolumeKeys(): void {
    if (this.volumeKeys === undefined && this.visible && !this.disposed && this.progressReady && !this.loading && this.error.length === 0) {
      this.volumeKeys = new ReaderVolumeKeys((offset: number): void => {
        if (!this.visible || this.disposed || this.loading || !this.progressReady || this.toolbarVisible || this.showChapters || this.zoomed) { return; }
        this.stopAutoRead('音量键翻页'); this.stepPage(offset);
      });
    }
    try {
      this.volumeKeys?.sync(this.visible && !this.disposed && !this.leavingReader && this.progressReady && !this.loading && this.error.length === 0,
        this.options.enableTurnPageByVolumeKey);
      this.volumeError = '';
    } catch (error) { this.volumeError = '此设备音量键拦截不可用；未更改系统音量。'; }
  }
  private enterReaderFullscreen(): void {
    if (!this.visible || this.disposed || this.leavingReader) { return; }
    ReaderWorkload.setReaderVisible(true, this.workloadOwner);
    if (this.windowChrome === undefined) { this.windowChrome = new ReaderWindowChrome(); }
    const owner = this.windowChrome;
    owner.enter(AppContext.context).then(() => {
      if (this.visible && !this.disposed && this.windowChrome === owner) { this.immersiveError = ''; }
    }).catch(() => {
      if (this.visible && !this.disposed && this.windowChrome === owner) {
        this.immersiveError = '系统未允许隐藏状态栏；正文浮层仍可收起。';
      }
      Log.warn('ReaderPage', 'reader fullscreen entry unavailable; no request data logged');
    });
  }

  private releaseReaderControls(): void {
    ReaderWorkload.setReaderVisible(false, this.workloadOwner);
    this.cancelCanvasTap(); this.canvasGesture?.cancel();
    this.toolbarVisible = false; this.showChapters = false;
    this.showSpeedMenu = false; this.showModeMenu = false;
    const owner = this.windowChrome;
    if (owner !== undefined) {
      owner.leave().then(() => {
        // A failed details navigation may have returned to this same reader.
        // Restore first, then acquire again only while this page is visible.
        if (this.visible && !this.disposed && !this.leavingReader && this.windowChrome === owner) {
          this.enterReaderFullscreen();
        }
      }).catch(() => { Log.warn('ReaderPage', 'reader fullscreen restoration failed'); });
    }
    this.pressImage = -1;
    if (this.infoTimer >= 0) { clearInterval(this.infoTimer); this.infoTimer = -1; }
    try { this.volumeKeys?.release(); } catch (error) { Log.warn('ReaderPage', 'volume key release failed'); }
  }
  private startReaderInfo(): void {
    if (this.infoTimer >= 0) { clearInterval(this.infoTimer); }
    this.updateReaderInfo();
    this.infoTimer = setInterval(() => { if (this.visible && !this.disposed) { this.updateReaderInfo(); } }, 30000);
  }
  private updateReaderInfo(): void {
    const now = new Date();
    this.clockInfo = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')} · ${batteryInfo.batterySOC}%`;
  }
  private applyReaderBrightness(): void {
    if (!this.options.readerBrightnessEnabled) { this.restoreBrightness(); return; }
    const next = this.options.readerBrightness / 100;
    this.brightnessTail = this.brightnessTail.then(async (): Promise<void> => {
      if (this.disposed || !this.visible) { return; }
      if (this.brightnessWindow === undefined) {
        const host = await window.getLastWindow(AppContext.context);
        if (this.disposed || !this.visible) { return; }
        this.brightnessWindow = host; this.oldBrightness = host.getWindowProperties().brightness;
      }
      await this.brightnessWindow.setWindowBrightness(next); this.readerBrightness = next;
    }).catch((error: Object) => { Log.warn('ReaderPage', 'reader brightness setting failed'); });
  }
  private onImageLongPress(actual: number, generation: number, event: GestureEvent): void {
    if (this.disposed || !this.visible || this.loading || !this.progressReady || generation !== this.zoomReset ||
      !this.isVisibleImage(actual) || this.scrolling || this.showChapters || !this.readyImages.has(actual)) { return; }
    if (this.options.longPressAction === 'autoReading') { this.toggleAutoRead(); }
    else if (this.options.longPressAction === 'menu') { this.showImageMenu(actual); }
    else if (this.options.longPressAction === 'zoom') {
      this.stopAutoRead('长按缩放'); this.pressImage = actual;
      this.pressX = 50; this.pressY = 50;
      if (this.options.longPressZoomPosition === 'press' && event.fingerList.length > 0) {
        // Global touch point converted to image fraction via the wrapper's bounds.
        this.pressX = Math.max(0, Math.min(100, event.fingerList[0].localX / Math.max(1, this.viewportWidth / this.imagesPerScreen()) * 100));
        this.pressY = Math.max(0, Math.min(100, event.fingerList[0].localY / Math.max(1, this.viewportHeight) * 100));
      }
      this.zoomed = true;
    }
  }
  private endImageLongPress(): void { this.pressImage = -1; this.refreshZoomState(); }
  private async showImageMenu(actual: number): Promise<void> {
    if (actual < 0 || actual >= this.images.length || !this.visible || this.disposed) { return; }
    this.stopAutoRead('打开阅读操作');
    try {
      const choice = await promptAction.showActionMenu({ title: `第 ${actual + 1} 页`, buttons: [
        { text: '阅读设置', color: '#333333' }, { text: '自动翻页速度', color: '#1E88E5' } ] });
      if (!this.visible || this.disposed) { return; }
      if (choice.index === 0) { this.openReaderSettings(); }
      else { this.revealReaderMenu(); this.openAutoSpeedMenu(); }
    } catch (error) { /* Explicit user cancellation does nothing. */ }
  }

  /** "第 n/N 章 · 章节名" — the bottom bar carries the page counter instead. */
  private chapterLabel(): string {
    const info = this.currentChapterInfo();
    if (info.index < 0) {
      return this.chapterTitle();
    }
    const name = this.chapterTitle();
    const prefix = `第 ${info.index + 1}/${info.total} 章`;
    return name.length > 0 ? `${prefix} · ${name}` : prefix;
  }

  private currentChapterInfo(): ChapterInfo {
    const info = new ChapterInfo();
    info.index = this.currentChapterIndex();
    info.total = this.chapterIds.length;
    return info;
  }

  @Builder
  chapterListOverlay() {
    Column() {
      Row() {
        Text('目录').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('关闭').height(44).fontSize(13).fontColor('#CEDCF5').backgroundColor('#30343C').borderRadius(14).padding({ left: 16, right: 16 }).onClick(() => {
          this.showChapters = false;
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      List({ initialIndex: Math.max(0, this.currentChapterIndex()) }) {
        ForEach(this.chapterSections, (section: ChapterSection) => {
          ForEach(section.entries, (entry: ChapterEntry) => {
            ListItem() {
              Column() {
                if (section.name.length > 0 && section.entries[0].id === entry.id) {
                  Text(section.name).fontSize(13).fontColor('#A9B0BC').width('100%').padding({ left: 20, right: 20, top: 16, bottom: 8 })
                }
                Row({ space: 8 }) {
                  Text(`${entry.canonicalIndex + 1}`).fontSize(12).fontColor('#888888').width(32)
                  Text(entry.title || entry.id).fontSize(14)
                    .fontColor(entry.id === this.epId ? '#82B1FF' : '#EEEEEE').layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (entry.id === this.epId) { Text('阅读中').fontSize(11).fontColor('#82B1FF') }
                }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 20, right: 20, top: 14, bottom: 14 })
                  .onClick(() => { this.goToChapter(entry.canonicalIndex); })
              }.width('100%')
            }
          }, (entry: ChapterEntry) => `chapter-${entry.canonicalIndex}-${entry.id}`)
        }, (section: ChapterSection) => `chapter-group-${section.name}`)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0.5, color: '#333333' })
    }
    .width('100%')
    .height('70%')
    .backgroundColor('#20242B')
    .borderRadius({ topLeft: 24, topRight: 24 }).clip(true)
  }

  /** Popups in the center of the screen for auto speed and reader mode selection */
  @Builder
  speedMenuOverlay() {
    Column({ space: 18 }) {
      Text('自动翻页').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F1F4FA').width('100%')
      Text(`每页停留 ${this.speedDraft.toFixed(1)} 秒`).fontSize(24).fontWeight(FontWeight.Medium)
        .fontColor('#A9CDFF').width('100%').textAlign(TextAlign.Center)
      Slider({ value: this.speedDraft, min: 0.1, max: 10, step: 0.1 })
        .width('100%').height(44).selectedColor('#087FF5').trackColor('#3A404D').blockColor('#FFFFFF')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (Number.isFinite(value)) { this.speedDraft = Math.round(Math.max(0.1, Math.min(10, value)) * 10) / 10; }
        })
      Row() {
        Text('0.1s').fontSize(12).fontColor('#A7B1C1').layoutWeight(1)
        Text('10s').fontSize(12).fontColor('#A7B1C1')
      }.width('100%')
      Text('连续/瀑布模式每次前进一屏。图片未就绪、滚动或缩放时等待，避免跳过未显示内容。')
        .fontSize(12).fontColor('#A7B1C1').width('100%').lineHeight(19)
      Row({ space: 10 }) {
        Button('取消').height(44).layoutWeight(1).fontSize(14).fontColor('#F1F4FA')
          .backgroundColor('#2B3039').borderRadius(12).onClick(() => { this.showSpeedMenu = false; })
        Button(this.autoReading ? '应用速度' : '开始翻页').height(44).layoutWeight(1).fontSize(14).fontColor('#FFFFFF')
          .backgroundColor('#087FF5').borderRadius(12).enabled(this.progressReady && !this.loading)
          .onClick(() => { this.selectAutoSpeed(this.speedDraft); })
      }.width('100%')
      if (this.autoReading) {
        Button('停止自动翻页').height(44).width('100%').fontSize(14).fontColor('#FFC6C6')
          .backgroundColor('#452B31').borderRadius(12).onClick(() => { this.stopAutoRead('用户停止自动翻页'); this.dismissReaderMenu(); })
      }
    }.width('86%').constraintSize({ maxWidth: 440 }).padding(20).backgroundColor('#F2191D24')
      .borderRadius(20).border({ width: 1, color: '#3A404D' }).shadow({ radius: 24, color: '#80000000' })
      .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  modeMenuOverlay() {
    Column({ space: 12 }) {
      Text('翻页模式（仅对当前漫画有效）').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F1F4FA').width('100%')
      ForEach(READER_MODES, (m: string) => {
        Row() {
          Text(ReaderModes.label(m))
            .fontSize(14)
            .fontColor(this.mode === m ? '#087FF5' : '#F1F4FA')
            .fontWeight(this.mode === m ? FontWeight.Medium : FontWeight.Regular)
            .layoutWeight(1)
          if (this.mode === m) {
            Text('当前').fontSize(12).fontColor('#087FF5')
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.mode === m ? '#29394E' : '#2B3039')
        .borderRadius(12)
        .onClick(() => {
          this.selectComicMode(m);
        })
      }, (m: string) => `mode-${m}`)
      Button('关闭')
        .width('100%')
        .height(40)
        .fontSize(13)
        .fontColor('#F1F4FA')
        .backgroundColor('#2B3039')
        .borderRadius(12)
        .onClick(() => { this.showModeMenu = false; })
    }
    .width('86%')
    .padding(20)
    .backgroundColor('#F2191D24')
    .borderRadius(20)
    .border({ width: 1, color: '#3A404D' })
    .shadow({ radius: 24, color: '#80000000' })
  }

  /** A single bottom overlay. It never participates in the image canvas layout. */
  @Builder
  bottomBar() {
    Scroll() {
      Column({ space: 12 }) {
        Row().width(36).height(4).borderRadius(2).backgroundColor('#69717F').alignSelf(ItemAlign.Center)

        // Top Row: [返回] | Title & Chapter | [详情]
        Row({ space: 10 }) {
          Button('返回').height(44).fontSize(13).fontColor('#F1F4FA').backgroundColor('#2B3039')
            .borderRadius(14).padding({ left: 16, right: 16 }).onClick(() => { this.returnToPrevious(); })
          Column({ space: 4 }) {
            Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#F1F4FA')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(this.chapterLabel()).fontSize(12).fontColor('#A7B1C1').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            .onClick(() => {
              if (this.progressReady && !this.loading) { this.openReaderChapterMenu(); }
            })
          Button('详情').height(44).fontSize(13).fontColor('#C4D9FA').backgroundColor('#2B3039')
            .borderRadius(14).padding({ left: 16, right: 16 })
            .enabled(!this.leavingReader && this.sourceKey.length > 0 && this.comicId.length > 0)
            .onClick(() => { this.dismissReaderMenu(); this.openComicDetails(); })
        }.width('100%')

        // Chapter Nav Row: [上一章] [目录] [下一章]
        Row({ space: 8 }) {
          Button('上一章').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.switchChapter(-1); })
          Button('目录').height(44).fontSize(13).fontColor('#A9CDFF').backgroundColor('#29394E').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.openReaderChapterMenu(); })
          Button('下一章').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.switchChapter(1); })
        }.width('100%')

        // Action Row: [设置] [自动翻页] [翻页模式]
        Row({ space: 8 }) {
          Button('设置').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.settingsSaving).onClick(() => { this.dismissReaderMenu(); this.openReaderSettings(); })
          Button(this.autoReading ? `自动 (${this.options.autoPageTurningInterval}s)` : '自动翻页')
            .height(44).fontSize(13).fontColor(this.autoReading ? '#A9CDFF' : '#F2F3F5')
            .backgroundColor(this.autoReading ? '#29394E' : '#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => {
              this.openAutoSpeedMenu();
            })
          Button('翻页模式').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady && !this.settingsSaving)
            .onClick(() => {
              this.showModeMenu = true;
            })
        }.width('100%')

        // Bottom Row: Brightness Slider
        Row({ space: 10 }) {
          Text('亮度').fontSize(12).fontColor('#A7B1C1')
          Slider({
            value: this.readerBrightness < 0 ? 50 : Math.round(this.readerBrightness * 100),
            min: 10,
            max: 100,
            step: 1
          })
            .layoutWeight(1)
            .selectedColor('#087FF5')
            .trackColor('#3A404D')
            .blockColor('#FFFFFF')
            .onChange((val: number, mode: SliderChangeMode) => {
              this.setBrightnessValue(val);
            })
          Text(`${this.readerBrightness < 0 ? '跟随' : Math.round(this.readerBrightness * 100) + '%'}`)
            .fontSize(12).fontColor('#C4D9FA').width(36).textAlign(TextAlign.End)
        }.width('100%').padding({ left: 4, right: 4, top: 4 })

        if (this.volumeError.length > 0) { Text(this.volumeError).fontSize(11).fontColor('#FFCA80').width('100%') }
        if (this.immersiveError.length > 0) { Text(this.immersiveError).fontSize(11).fontColor('#FFCA80').width('100%') }
      }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 28 }).alignItems(HorizontalAlign.Start)
    }.width('100%').constraintSize({ maxHeight: this.landscape ? '76%' : '60%' })
      .backgroundColor('#F2191D24').borderRadius({ topLeft: 24, topRight: 24 })
      .scrollBar(BarState.Off)
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)
        .animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  flowImage(url: string, display: number, actual: number, generation: number, zoomGeneration: number) {
    Column() {
      AsyncComicImage({
        url: url,
        thumbnail: false,
        zoomEnabled: true,
        doubleTapZoomEnabled: this.options.enableDoubleTapToZoom,
        // Window-level tap dispatcher owns single taps, including blank margins.
        // This child retains only its native double-tap/pinch/pan behavior.
        singleTapEnabled: false,
        onReaderDoubleTap: () => { this.cancelCanvasTap(); },
        zoomReset: zoomGeneration,
        onZoomChanged: (value: boolean) => { this.onImageZoom(actual, zoomGeneration, value); },
        onReadyChanged: (value: boolean) => { this.onImageReady(actual, generation, value); },
        naturalHeight: this.isVerticalFlow(),
        splitWideImage: this.isVerticalFlow() && this.options.splitDualPage,
        splitWideImageInvert: this.isVerticalFlow() && this.options.splitDualPageInvert,
        objectFit: ImageFit.Contain,
        sourceKey: this.sourceKey,
        comicId: this.comicId,
        epId: this.epId
      })
    }
    .width('100%')
    .height(this.isVerticalFlow() ? undefined : '100%')
    .scale({ x: this.pressImage === actual ? 2 : 1, y: this.pressImage === actual ? 2 : 1, centerX: `${this.pressX}%`, centerY: `${this.pressY}%` })
    .parallelGesture(LongPressGesture({ repeat: false, duration: 500 })
      .onAction((event: GestureEvent) => { this.onImageLongPress(actual, zoomGeneration, event); })
      .onActionEnd(() => { this.endImageLongPress(); })
      .onActionCancel(() => { this.endImageLongPress(); }))
    .onAreaChange((oldArea: Area, area: Area) => {
      this.onFlowImageSize(display, generation, Number(oldArea.height), Number(area.height));
      // The previous-chapter END anchor is only meaningful while it is armed.
      if (this.previousEndLoad >= 0 && Number(oldArea.height) !== Number(area.height)) {
        this.alignPreviousChapterEnd();
      }
    })
  }

  /** Waterfall / continuous modes scroll a list; the rest page with a Swiper. */
  @Builder
  continuousList() {
    List({
      space: 4,
      scroller: this.listScroller,
      initialIndex: ReaderModes.toDisplayIndex(this.mode, this.currentPage, this.images.length)
    }) {
      LazyForEach(this.flowSource, (item: ReaderRenderItem) => {
        ListItem() {
          this.flowImage(item.url, item.display, item.actual, item.generation, this.zoomReset)
        }
      }, (item: ReaderRenderItem) => item.key)
    }
    .layoutWeight(1)
    .width(this.flowWidth())
    .constraintSize({ maxWidth: this.isVerticalFlow() && this.options.limitImageWidth ? 900 : undefined })
    .cachedCount(1)
    .listDirection(ReaderModes.isVertical(this.mode) ? Axis.Vertical : Axis.Horizontal)
    .enableScrollInteraction(!this.zoomed)
    .onAppear(() => {
      this.restoreWaterfall();
      this.alignPreviousChapterEnd();
    })
    .onTouch((event: TouchEvent) => {
      this.releaseRestoreOnTouch(event);
    })
    .onScrollStart(() => { this.scrolling = true; this.lastUserScrollAt = Date.now(); if (!this.autoReading) { this.cancelCanvasTap(); } })
    .onScrollStop(() => { this.scrolling = false; this.lastUserScrollAt = Date.now(); })
    .onScrollIndex((first: number, last: number) => {
      this.visibleFirst = first;
      this.visibleLast = last;
      this.updatePage(first);
      this.refreshZoomState();
    })
  }

  @Builder
  galleryImage(actual: number, generation: number, zoomGeneration: number) {
    Column() {
      AsyncComicImage({
        url: this.images[actual],
        thumbnail: false,
        zoomEnabled: true,
        doubleTapZoomEnabled: this.options.enableDoubleTapToZoom,
        // Window-level tap dispatcher owns single taps, including blank margins.
        // This child retains only its native double-tap/pinch/pan behavior.
        singleTapEnabled: false,
        onReaderDoubleTap: () => { this.cancelCanvasTap(); },
        zoomReset: zoomGeneration,
        onZoomChanged: (value: boolean) => { this.onImageZoom(actual, zoomGeneration, value); },
        onReadyChanged: (value: boolean) => { this.onImageReady(actual, generation, value); },
        objectFit: ImageFit.Contain,
        sourceKey: this.sourceKey,
        comicId: this.comicId,
        epId: this.epId
      })
    }
    .layoutWeight(1)
    .width(this.mode === 'galleryTopToBottom' ? '100%' : undefined)
    .height(this.mode === 'galleryTopToBottom' ? undefined : '100%')
    .scale({ x: this.pressImage === actual ? 2 : 1, y: this.pressImage === actual ? 2 : 1, centerX: `${this.pressX}%`, centerY: `${this.pressY}%` })
    .parallelGesture(LongPressGesture({ repeat: false, duration: 500 })
      .onAction((event: GestureEvent) => { this.onImageLongPress(actual, zoomGeneration, event); })
      .onActionEnd(() => { this.endImageLongPress(); })
      .onActionCancel(() => { this.endImageLongPress(); }))
  }

  @Builder
  gallerySpread(spread: ReaderSpread, generation: number, zoomGeneration: number) {
    if (this.mode === 'galleryTopToBottom') {
      Column() {
        ForEach(spread.imageIndices, (actual: number) => {
          this.galleryImage(actual, generation, zoomGeneration)
        }, (actual: number) => `${this.renderScope}:image:${actual}`)
      }.width('100%').height('100%')
    } else {
      Row() {
        ForEach(spread.imageIndices, (actual: number) => {
          this.galleryImage(actual, generation, zoomGeneration)
        }, (actual: number) => `${this.renderScope}:image:${actual}`)
      }.width('100%').height('100%')
    }
  }

  @Builder
  gallerySwiper() {
    Swiper(this.swiperController) {
      LazyForEach(this.spreadSource, (item: ReaderRenderItem) => {
        this.gallerySpread(item.spread, item.generation, this.zoomReset)
      }, (item: ReaderRenderItem) => item.key)
    }
    .vertical(this.mode === 'galleryTopToBottom')
    .cachedCount(1)
    .index(this.sourceToDisplay(this.currentPage))
    .duration(this.options.enablePageAnimation ? 200 : 0)
    .loop(false)
    .disableSwipe(this.zoomed)
    .onAnimationStart(() => { this.scrolling = true; this.cancelCanvasTap(); })
    .onAnimationEnd(() => { this.scrolling = false; })
    .indicator(false)
    .layoutWeight(1)
    .width('100%')
    .onTouch((event: TouchEvent) => {
      this.releaseRestoreOnTouch(event);
    })
    .onChange((index: number) => {
      this.updatePage(index);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Stable fullscreen canvas. Menu visibility never changes this subtree's
      // geometry, keys, data source, renderGeneration or image request identity.
      Column() {
        if (this.loading) {
          LoadingView({ message: '正在加载章节…' }).layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (this.error.length > 0) {
          ErrorView({ message: this.error, onRetry: () => { this.retryReaderContent(); } })
            .layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (this.images.length === 0) {
          ErrorView({ message: '该章节没有图片' }).layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (ReaderModes.isGallery(this.mode)) {
          this.gallerySwiper()
        } else {
          this.continuousList()
        }
      }.width('100%').height('100%').backgroundColor(Color.Black)
        .onTouch((event: TouchEvent) => { this.onReaderSurfaceTouch(event); })
      if (this.toolbarVisible && !this.showChapters) {
        // A modal sibling consumes outside taps even while images are loading
        // or the touch is in letterboxing. Closing never also turns a page.
        Column().width('100%').height('100%').backgroundColor('#01000000')
          .hitTestBehavior(HitTestMode.Block).onClick(() => { this.dismissReaderMenu(); })
        this.bottomBar()
      }
      if (this.showChapters && !this.loading && this.error.length === 0) {
        Column().width('100%').height('100%').backgroundColor('#45000000')
          .onClick(() => { this.dismissReaderMenu(); })
        this.chapterListOverlay()
      }
      if (this.showSpeedMenu) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width('100%').height('100%').backgroundColor('#66000000')
            .hitTestBehavior(HitTestMode.Block).onClick(() => { this.showSpeedMenu = false; })
          this.speedMenuOverlay()
        }.width('100%').height('100%')
      }
      if (this.showModeMenu) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width('100%').height('100%').backgroundColor('#66000000')
            .hitTestBehavior(HitTestMode.Block).onClick(() => { this.showModeMenu = false; })
          this.modeMenuOverlay()
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, area: Area) => {
        const top = Number(area.globalPosition.y);
        const left = Number(area.globalPosition.x);
        if (Number(area.width) !== this.viewportWidth || Number(area.height) !== this.viewportHeight ||
          top !== this.viewportTop || left !== this.viewportLeft) { this.cancelCanvasTap(); }
        this.viewportTop = Number.isFinite(top) ? top : 0;
        this.viewportLeft = Number.isFinite(left) ? left : 0;
        this.onViewportSize(Number(area.width), Number(area.height));
      })
  }
}
