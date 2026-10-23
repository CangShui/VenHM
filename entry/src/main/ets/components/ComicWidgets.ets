import { image } from '@kit.ImageKit';
import { ImageLoader, ImageLease } from '../network/ImageLoader';
import { UiTheme, UiIcon } from './UiKit';
import { UiStyles } from './UiModifiers';
import { SourceManager } from '../source/SourceManager';
import { Log } from '../foundation/Log';
import { ImageRequests } from '../source/ImageRequests';
import { ImageRequestConfig } from '../source/ComicSource';
import { ReaderImageLayout } from '../features/ReaderImageLayout';
import { ReaderTapPolicy } from '../features/ReaderTapPolicy';

/** Resolved request for one image (url possibly rewritten by the source). */
class ImageRequest {
  private static sequence: number = 0;
  static uniqueTrace(): string { return `image-${Date.now()}-${ImageRequest.sequence++}`; }
  config: ImageRequestConfig = new ImageRequestConfig();
  trace: string = '';
}

/**
 * Shared UI building blocks.
 *
 * Dart originals live in lib/features/comic_widgets/comic_tile.dart,
 * lib/components/loading.dart and lib/components/image.dart. The ArkUI versions
 * are intentionally much smaller: no shimmer, no hero animation, no
 * CustomPainter badges - those are later modules per the migration plan.
 *
 * ArkTS note: `@Prop` is used with primitive types only, and callers size these
 * components by wrapping them in a container instead of applying universal
 * attributes to a custom component. Both choices avoid ArkTS/ArkUI restrictions
 * that would otherwise show up as compile errors.
 */

/** Loads a URL (file:// or http) into a PixelMap and renders it. */
@Component
export struct AsyncComicImage {
  @Prop @Watch('reloadImage') url: string = '';
  @Prop objectFit: ImageFit = ImageFit.Cover;
  /** Continuous reading uses the decoded aspect ratio, never cropped poster sizing. */
  @Prop naturalHeight: boolean = false;
  @State decodedRatio: number = 2 / 3;
  /** When set, the source's onImageLoad hook supplies headers / a new url. */
  @Prop @Watch('reloadImage') sourceKey: string = '';
  @Prop @Watch('reloadImage') comicId: string = '';
  @Prop @Watch('reloadImage') epId: string = '';
  @Prop @Watch('reloadImage') thumbnail: boolean = true;
  @Prop zoomEnabled: boolean = false;
  @Prop doubleTapZoomEnabled: boolean = true;
  @Prop @Watch('resetZoom') splitWideImage: boolean = false;
  @Prop @Watch('resetZoom') splitWideImageInvert: boolean = false;
  @Prop @Watch('resetZoom') zoomReset: number = 0;
  onZoomChanged?: (zoomed: boolean) => void;
  onReadyChanged?: (ready: boolean) => void;
  /** The reader owns a separate window-wide single-tap dispatcher. */
  onReaderDoubleTap?: () => void;
  @Prop @Watch('cancelSingleTap') singleTapEnabled: boolean = false;
  /** Fraction within this untransformed image viewport, not global/device pixels. */
  onSingleTap?: (normalizedX: number, globalY?: number) => void;
  /** Reader chrome may open/close while zoomed; pan/pinch/double tap still cancel singles. */
  @Prop menuTapWhenZoomed: boolean = false;
  private tapWidth: number = 0;
  private singleTapTimer: number = -1;
  private tapVersion: number = 0;
  private suppressSingleUntil: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchMoved: boolean = false;
  @State scaleValue: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  private baseScale: number = 1;
  private baseX: number = 0;
  private baseY: number = 0;
  private requestVersion: number = 0;
  private reloadVersion: number = 0;
  private requestIdentity: string = '';
  private loadStarted: boolean = false;
  private readinessVersion: number = 0;
  private disposed: boolean = false;
  private gestureTrace: string = '';
  private ownedLease?: ImageLease;
  private ownedTrace: string = '';

  private releaseOwned(): void {
    if (this.ownedTrace.length > 0) { ImageLoader.cancelOwned(this.ownedTrace); this.ownedTrace = ''; }
    const lease = this.ownedLease;
    this.ownedLease = undefined;
    // The loader owns decoded maps. Retire only this consumer's idempotent lease;
    // another visible/reused component may be rendering the same cached map.
    lease?.release();
  }
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.load();
  }

  aboutToDisappear(): void {
    this.cancelSingleTap();
    this.disposed = true;
    this.requestVersion++;
    this.reloadVersion++;
    this.loadStarted = false;
    this.pixelMap = undefined;
    this.releaseOwned();
    this.notifyReady(false);
  }

  private identity(): string {
    // Only request inputs belong here. Layout/zoom/readiness must never refetch.
    // Length-prefixing avoids collisions without logging URLs or source data.
    return [this.url, this.sourceKey, this.comicId, this.epId, this.thumbnail ? '1' : '0']
      .map((part: string): string => `${part.length}:${part}`).join('');
  }

  private notifyReady(ready: boolean): void {
    try { this.onReadyChanged?.(ready); }
    catch (error) { Log.audit('image-ready', '就绪回调异常', '布局通知失败，未修改图片请求或打印回调数据'); }
  }

  private reloadImage(): void {
    // ArkUI can update watched sibling props one by one. Resolve only the final
    // input tuple, and merge the url watcher with aboutToReuse's notification.
    const reload = ++this.reloadVersion;
    Promise.resolve().then((): void => {
      if (this.disposed || reload !== this.reloadVersion) { return; }
      if (!this.loadStarted || this.requestIdentity !== this.identity()) { this.resetZoom(); }
      this.load();
    }).catch((): void => { Log.audit('image-reload', '图片更新异常', '属性更新通知失败'); });
  }

  private resetZoom(): void {
    this.cancelSingleTap();
    this.scaleValue = 1;
    this.baseScale = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.baseX = 0;
    this.baseY = 0;
    this.onZoomChanged?.(false);
    const readiness = ++this.readinessVersion;
    const request = this.requestVersion;
    const generation = this.zoomReset;
    // Read the current callback after the full prop update; watchers may fire
    // before ArkUI has replaced sibling callback props. Never remount/refetch.
    Promise.resolve().then((): void => {
      if (this.disposed || readiness !== this.readinessVersion || request !== this.requestVersion || generation !== this.zoomReset) { return; }
      this.notifyReady(this.pixelMap !== undefined && !this.failed);
    }).catch((): void => { Log.audit('image-ready', '就绪回调异常', '布局通知失败，未修改图片请求或打印回调数据'); });
  }

  private applyScale(scale: number): void {
    if (this.gestureTrace.length === 0) { this.gestureTrace = `image-gesture-${Date.now()}-${this.requestVersion}`; }
    const before = this.scaleValue;
    this.scaleValue = Math.max(1, Math.min(4, scale));
    if (this.scaleValue === 1) {
      this.offsetX = 0;
      this.offsetY = 0;
    }
    this.onZoomChanged?.(this.scaleValue > 1);
    Log.audit(this.gestureTrace, '图片缩放返回', `原比例=${before}；请求比例=${scale}；新比例=${this.scaleValue}；父阅读器锁定翻页=${this.scaleValue > 1}`);
  }

  aboutToReuse(params: Record<string, Object>): void {
    // Reused components can receive a new episode/source with the same URL.
    // Watchers and this hook share one coalesced update, never two load() calls.
    if (typeof params.url === 'string') { this.url = params.url as string; }
    if (typeof params.sourceKey === 'string') { this.sourceKey = params.sourceKey as string; }
    if (typeof params.comicId === 'string') { this.comicId = params.comicId as string; }
    if (typeof params.epId === 'string') { this.epId = params.epId as string; }
    if (typeof params.thumbnail === 'boolean') { this.thumbnail = params.thumbnail as boolean; }
    this.disposed = false;
    this.reloadImage();
  }

  private async resolveRequest(url: string, sourceKey: string, comicId: string,
    epId: string, thumbnail: boolean): Promise<ImageRequest> {
    const request = new ImageRequest();
    request.config.url = url;
    request.trace = ImageRequest.uniqueTrace();
    if (sourceKey.length === 0) { return request; }
    const source = SourceManager.find(sourceKey);
    request.config = await ImageRequests.resolve(source, url, thumbnail,
      comicId, epId, request.trace);
    return request;
  }

  private load(): void {
    const identity = this.identity();
    if (this.disposed || (this.loadStarted && this.requestIdentity === identity)) { return; }
    this.loadStarted = true;
    this.requestIdentity = identity;
    this.cancelSingleTap();
    const version = ++this.requestVersion;
    this.pixelMap = undefined;
    this.notifyReady(false);
    this.releaseOwned();
    const thumbnail = this.thumbnail;
    let trace: string = '';
    let received: ImageLease | undefined = undefined;
    if (this.url.length === 0) {
      this.failed = true;
      return;
    }
    this.failed = false;
    this.resolveRequest(this.url, this.sourceKey, this.comicId, this.epId, this.thumbnail)
      .then((request: ImageRequest) => {
        if (this.disposed || version !== this.requestVersion || identity !== this.identity()) { throw new Error('STALE_IMAGE_REQUEST'); }
        trace = request.trace;
        this.ownedTrace = trace;
        return ImageLoader.acquireRequest(request.config, trace,
          (): boolean => !this.disposed && version === this.requestVersion && identity === this.identity(), thumbnail);
      })
      .then(async (lease: ImageLease) => {
        received = lease;
        const value = lease.pixelMap;
        // A decoded transform is settled: retirement releases its PixelMap but
        // must not cancel a completed trace (or poison a later cache consumer).
        if (this.ownedTrace === trace) { this.ownedTrace = ''; }
        if (this.disposed || version !== this.requestVersion || identity !== this.identity()) {
          received = undefined;
          lease.release();
          return;
        }
        if (this.naturalHeight) {
          const info = await value.getImageInfo();
          if (this.disposed || version !== this.requestVersion || identity !== this.identity()) {
            received = undefined;
          lease.release();
            return;
          }
          if (!ReaderImageLayout.validSize(info.size.width, info.size.height)) { throw new Error('阅读图片尺寸无效'); }
          this.decodedRatio = info.size.width / info.size.height;
        }
        this.pixelMap = value;
        this.ownedLease = lease;
        this.notifyReady(true);
      })
      .catch((error: Object) => {
        if (this.ownedTrace === trace) { this.ownedTrace = ''; }
        // A late lease that lost the race must be retired exactly once; the
        // loader keeps the decoded map alive for whichever consumer won.
        if (received !== undefined) {
          const uncommitted = received;
          received = undefined;
          uncommitted.release();
        }
        if (this.disposed || version !== this.requestVersion || identity !== this.identity()) { return; }
        Log.warn('AsyncComicImage', 'load failed; request data omitted');
        this.pixelMap = undefined;
        this.failed = true;
        this.notifyReady(false);
      });
  }

  private splitActive(): boolean {
    return this.naturalHeight && this.splitWideImage && this.decodedRatio > 1;
  }
  private presentationRatio(): number {
    return ReaderImageLayout.displayRatio(this.decodedRatio, 1, this.splitActive());
  }
  private splitPosition(top: boolean): number | string {
    return top !== this.splitWideImageInvert ? '-100%' : 0;
  }

  private cancelSingleTap(): void {
    this.tapVersion++;
    if (this.singleTapTimer >= 0) { clearTimeout(this.singleTapTimer); this.singleTapTimer = -1; }
  }

  private trackTapTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      // A second contact/tap also invalidates the first delayed single.
      this.cancelSingleTap();
      this.touchMoved = event.touches.length !== 1;
      if (event.touches.length > 0) {
        this.touchStartX = event.touches[0].x;
        this.touchStartY = event.touches[0].y;
      }
    } else if (event.type === TouchType.Move) {
      if (event.touches.length !== 1 || Math.abs(event.touches[0].x - this.touchStartX) > 8 ||
        Math.abs(event.touches[0].y - this.touchStartY) > 8) {
        this.touchMoved = true;
        this.cancelSingleTap();
      }
    } else if (event.type === TouchType.Cancel) {
      this.touchMoved = true;
      this.cancelSingleTap();
    }
  }

  private queueSingleTap(event: GestureEvent): void {
    this.cancelSingleTap();
    if (!this.singleTapEnabled || this.disposed || this.touchMoved || (this.scaleValue > 1 && !this.menuTapWhenZoomed) ||
      this.pixelMap === undefined || this.failed || Date.now() <= this.suppressSingleUntil || event.fingerList.length !== 1) { return; }
    const x = ReaderTapPolicy.normalizeX(event.fingerList[0].localX, this.tapWidth);
    const globalY = event.fingerList[0].globalY;
    if (x < 0) { return; }
    const version = this.tapVersion;
    const request = this.requestVersion;
    const generation = this.zoomReset;
    this.singleTapTimer = setTimeout((): void => {
      this.singleTapTimer = -1;
      if (version !== this.tapVersion || request !== this.requestVersion || generation !== this.zoomReset ||
        !this.singleTapEnabled || this.disposed || this.touchMoved || (this.scaleValue > 1 && !this.menuTapWhenZoomed) ||
        this.pixelMap === undefined || this.failed || Date.now() <= this.suppressSingleUntil) { return; }
      this.onSingleTap?.(x, globalY);
    }, ReaderTapPolicy.delayMs);
  }

  private handleDoubleTap(): void {
    this.cancelSingleTap();
    // Parallel Tap1 may deliver after Tap2; it must not create another pending turn.
    this.suppressSingleUntil = Date.now() + ReaderTapPolicy.delayMs;
    this.onReaderDoubleTap?.();
    if (this.zoomEnabled && this.doubleTapZoomEnabled && this.pixelMap !== undefined && !this.failed) {
      this.applyScale(this.scaleValue > 1 ? 1 : 2);
    }
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        if (this.splitActive()) {
          Column({ space: 0 }) {
            this.splitPane(true)
            this.splitPane(false)
          }
          .width('100%').height('100%')
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
        } else {
          Image(this.pixelMap)
            .width('100%')
            .height('100%')
            .objectFit(this.objectFit)
            .scale({ x: this.scaleValue, y: this.scaleValue })
            .translate({ x: this.offsetX, y: this.offsetY })
        }
      } else {
        Column() {
          if (this.failed) {
            Text('图片加载失败')
              .fontSize(11)
              .fontColor('#999999')
          } else {
            LoadingProgress()
              .width(24)
              .height(24)
              .color('#AAAAAA')
          }
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height(this.naturalHeight ? undefined : '100%')
    .aspectRatio(this.naturalHeight ? this.presentationRatio() : undefined)
    .backgroundColor('#F0F0F0')
    .clip(true)
    .onAreaChange((oldArea: Area, area: Area) => {
      const width = Number(area.width);
      if (width !== this.tapWidth) { this.cancelSingleTap(); this.tapWidth = width; }
    })
    .onTouch((event: TouchEvent) => { this.trackTapTouch(event); })
    .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => {
      if (info.type === GestureControl.GestureType.TAP_GESTURE) {
        return this.zoomEnabled || this.singleTapEnabled ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
      }
      if (!this.zoomEnabled || (info.type === GestureControl.GestureType.PAN_GESTURE && this.scaleValue <= 1)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
    .gesture(
      GestureGroup(GestureMode.Parallel,
        TapGesture({ count: 2 }).onAction(() => { this.handleDoubleTap(); }),
        TapGesture({ count: 1 }).onAction((event: GestureEvent) => { this.queueSingleTap(event); }),
        PinchGesture().onActionStart(() => { this.cancelSingleTap(); this.touchMoved = true; this.baseScale = this.scaleValue; })
          .onActionUpdate((event: GestureEvent) => {
            if (this.zoomEnabled) { this.applyScale(this.baseScale * event.scale); }
          }),
        PanGesture().onActionStart(() => { this.cancelSingleTap(); this.touchMoved = true; this.baseX = this.offsetX; this.baseY = this.offsetY; })
          .onActionUpdate((event: GestureEvent) => {
            if (this.zoomEnabled && this.scaleValue > 1) {
              this.offsetX = Math.max(-1500, Math.min(1500, this.baseX + event.offsetX));
              this.offsetY = Math.max(-1500, Math.min(1500, this.baseY + event.offsetY));
            }
          })
      )
    )
  }
  /** Same texture twice, clipped geometrically; no PNG/crop/RGBA allocation.
   * Percentage offset preserves fractional half-pixel boundaries for odd widths.
   */
  @Builder
  splitPane(top: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.pixelMap)
        .width('200%').height('100%')
        .objectFit(ImageFit.Fill)
        .position({ x: this.splitPosition(top), y: 0 })
    }
    .width('100%').height('50%').clip(true)
  }
}

/**
 * Grid cell for one comic.
 * Only primitives cross the component boundary; the tap handler is a closure
 * created by the parent, so no interface type is used in a decorator.
 */
@Component
export struct ComicCell {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop coverUrl: string = '';
  /** Needed so the source's onImageLoad headers are applied to the cover too. */
  @Prop sourceKey: string = '';
  @Prop comicId: string = '';
  onTapCell?: () => void;

  build() {
    Column({ space: 9 }) {
      Column() {
        AsyncComicImage({
          url: this.coverUrl,
          sourceKey: this.sourceKey,
          comicId: this.comicId
        })
      }
      .width('100%')
      // Poster shape. Without an explicit ratio the cell collapsed into a strip
      // inside the grid.
      .aspectRatio(0.72)
      .borderRadius(16)
      .clip(true)

      Text(this.title)
        .fontSize(14).fontWeight(FontWeight.Medium).lineHeight(20)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .fontColor(UiTheme.ink)

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(11)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(UiTheme.secondary)
          .width('100%')
      }
    }
    .width('100%')
    .onClick(() => {
      const handler = this.onTapCell;
      if (handler !== undefined) {
        handler();
      }
    })
  }
}

@Component
export struct LoadingView {
  @Prop message: string = '加载中…';

  build() {
    Column({ space: 12 }) {
      LoadingProgress().width(32).height(32).color(UiTheme.accent)
      Text(this.message).fontSize(14).fontColor(UiTheme.secondary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct EmptyView {
  @Prop message: string = '暂无内容';

  build() {
    Column({ space: 16 }) {
      Stack() { UiIcon({ name: 'folder', color: '#70AFE9', iconSize: 68 }) }
        .width(128).height(128).backgroundColor('#EAF2FD').borderRadius(38)
      Text('这里还没有内容').fontSize(19).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
      Text(this.message)
        .fontSize(13).lineHeight(22)
        .fontColor(UiTheme.secondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ErrorView {
  @Prop message: string = '出错了';
  onRetry?: () => void;

  build() {
    Column({ space: 12 }) {
      Text(this.message)
        .fontSize(14)
        .fontColor(UiTheme.secondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
      Button('重试').attributeModifier(UiStyles.secondary)
        .fontSize(14)
        .onClick(() => {
          const retry = this.onRetry;
          if (retry !== undefined) {
            retry();
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
