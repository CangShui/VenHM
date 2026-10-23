import { image } from '@kit.ImageKit';
import { ImageLoader, ImageLease } from '../network/ImageLoader';
import { SourceManager } from '../source/SourceManager';
import { ImageRequests } from '../source/ImageRequests';
import { DetailsImageRegion } from './DetailsMedia';

/** Read-only sprite viewport. Never crop/mutate the loader's shared PixelMap. */
@Component
export struct DetailsMediaImage {
  @Prop @Watch('reload') url: string = '';
  @Prop @Watch('reload') sourceKey: string = '';
  @Prop @Watch('reload') comicId: string = '';
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;
  @State imageWidth: number = 1;
  @State imageHeight: number = 1;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;
  @State region: DetailsImageRegion = new DetailsImageRegion();
  private lease?: ImageLease;
  private trace: string = '';
  private version: number = 0;
  private disposed: boolean = false;


  aboutToAppear(): void { this.disposed = false; this.reload(); }
  aboutToDisappear(): void { this.disposed = true; this.version++; this.release(); }
  private release(): void {
    this.pixelMap = undefined;
    if (this.trace.length > 0) { ImageLoader.cancelOwned(this.trace); this.trace = ''; }
    this.lease?.release(); this.lease = undefined;
  }
  private reload(): void {
    const version = ++this.version;
    Promise.resolve().then(async (): Promise<void> => {
      if (this.disposed || version !== this.version) { return; }
      this.release(); this.failed = false;
      this.region = DetailsImageRegion.parse(this.url);
      const trace = `details-media-image-${Date.now()}-${version}-${Math.random()}`;
      this.trace = trace;
      let acquired: ImageLease | undefined;
      try {
        const source = SourceManager.find(this.sourceKey);
        if (source === undefined) { throw new Error('Original source unavailable'); }
        const request = await ImageRequests.resolve(source, this.region.url, true, this.comicId, '', trace);
        if (this.disposed || version !== this.version) { return; }
        acquired = await ImageLoader.acquireRequest(request, trace, (): boolean => !this.disposed && version === this.version, true);
        const info = await acquired.pixelMap.getImageInfo();
        if (this.disposed || version !== this.version) { acquired.release(); return; }
        if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('Invalid image dimensions'); }
        this.imageWidth = info.size.width; this.imageHeight = info.size.height;
        this.lease = acquired; this.pixelMap = acquired.pixelMap; acquired = undefined;
        if (this.trace === trace) { this.trace = ''; }
      } catch (error) {
        acquired?.release();
        if (!this.disposed && version === this.version) { this.failed = true; }
      }
    }).catch((): void => { if (!this.disposed && version === this.version) { this.failed = true; } });
  }
  private cropWidth(): number { return this.region.cropped ? this.region.width : this.imageWidth; }
  private cropHeight(): number { return this.region.cropped && this.region.height > 0 ? this.region.height : this.imageHeight; }
  private factor(): number { return Math.min(this.viewportWidth / this.cropWidth(), this.viewportHeight / this.cropHeight()); }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .width(this.imageWidth * this.factor()).height(this.imageHeight * this.factor())
          .objectFit(ImageFit.Fill)
          .position({ x: (this.viewportWidth - this.cropWidth() * this.factor()) / 2 - this.region.x * this.factor(),
            y: (this.viewportHeight - this.cropHeight() * this.factor()) / 2 - this.region.y * this.factor() })
      } else if (this.failed) {
        Column({ space: 6 }) {
          Text('图片加载失败').fontSize(12).fontColor('#888888')
          Button('重试').fontSize(12).onClick(() => { this.reload(); })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        Column() { LoadingProgress().width(24).height(24) }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').clip(true)
      .onAreaChange((oldValue: Area, value: Area) => {
        this.viewportWidth = Math.max(1, Number(value.width)); this.viewportHeight = Math.max(1, Number(value.height));
      })
  }
}
