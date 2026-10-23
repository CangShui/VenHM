import { router } from '@kit.ArkUI';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { SourceManager } from '../source/SourceManager';
import { DetailsViewerParams } from '../source/DetailsCapabilities';
import { DetailsViewerTransform } from '../features/DetailsMedia';
import { DetailsMediaImage } from '../features/DetailsMediaImage';

/** Cover/preview gallery. Only the currently visible image is acquired, no loadEp. */
@Entry
@Component
struct ImageViewerPage {
  @State params: DetailsViewerParams = { sourceKey: '', comicId: '', title: '', images: [], index: 0, thumbnail: true };
  @State index: number = 0;
  @State error: string = '';
  @State scaleValue: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State widthValue: number = 1;
  @State heightValue: number = 1;
  @State ready: boolean = false;
  private baseScale: number = 1;
  private baseX: number = 0;
  private baseY: number = 0;
  private disposed: boolean = false;
  private version: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as DetailsViewerParams;
    if (params !== undefined && params !== null && Array.isArray(params.images)) {
      this.params = params; this.index = Math.max(0, Math.min(params.images.length - 1, params.index ?? 0));
    }
    this.initialize();
  }
  onPageHide(): void { this.disposed = true; this.version++; this.ready = false; }
  aboutToDisappear(): void { this.onPageHide(); }
  onPageShow(): void { if (this.disposed) { this.disposed = false; this.initialize(); } }
  private async initialize(): Promise<void> {
    const version = ++this.version;
    try {
      await AppInit.init();
      if (this.disposed || version !== this.version) { return; }
      if (SourceManager.find(this.params.sourceKey) === undefined) { throw new Error('原始漫画源已不可用'); }
      if (this.params.images.length === 0 || this.current().length === 0) { throw new Error('没有可查看的图片'); }
      this.error = ''; this.ready = true;
    } catch (error) { if (!this.disposed && version === this.version) { this.error = '没有可用图片或原始漫画源已不可用'; } }
  }
  private current(): string { return this.params.images[this.index] ?? ''; }
  private reset(): void { this.scaleValue = 1; this.offsetX = 0; this.offsetY = 0; this.baseScale = 1; this.baseX = 0; this.baseY = 0; }
  private move(delta: number): void {
    const target = this.index + delta;
    if (this.disposed || target < 0 || target >= this.params.images.length) { return; }
    this.reset(); this.index = target;
  }
  private zoom(value: number): void {
    this.scaleValue = DetailsViewerTransform.scale(value);
    this.offsetX = DetailsViewerTransform.offset(this.offsetX, this.widthValue, this.scaleValue);
    this.offsetY = DetailsViewerTransform.offset(this.offsetY, this.heightValue, this.scaleValue);
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('关闭').height(44).fontSize(14).fontColor('#F2F3F5').backgroundColor('#30343C').borderRadius(14).padding({ left: 16, right: 16 }).onClick(() => { router.back(); })
        Text(this.params.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(`${this.index + 1}/${this.params.images.length}`).fontSize(12).fontColor('#C7CDD7')
      }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).backgroundColor('#20242B')
      if (this.error.length > 0) {
        Text(this.error).fontColor(Color.White).layoutWeight(1)
      } else if (this.ready) {
        Stack() {
          DetailsMediaImage({ url: this.current(), sourceKey: this.params.sourceKey, comicId: this.params.comicId })
            .scale({ x: this.scaleValue, y: this.scaleValue })
            .translate({ x: this.offsetX, y: this.offsetY })
        }.width('100%').layoutWeight(1).clip(true)
          .onAreaChange((oldValue: Area, value: Area) => { this.widthValue = Number(value.width); this.heightValue = Number(value.height); })
          .gesture(GestureGroup(GestureMode.Parallel,
            PinchGesture().onActionStart(() => { this.baseScale = this.scaleValue; })
              .onActionUpdate((event: GestureEvent) => { this.zoom(this.baseScale * event.scale); }),
            PanGesture().onActionStart(() => { this.baseX = this.offsetX; this.baseY = this.offsetY; })
              .onActionUpdate((event: GestureEvent) => {
                this.offsetX = DetailsViewerTransform.offset(this.baseX + event.offsetX, this.widthValue, this.scaleValue);
                this.offsetY = DetailsViewerTransform.offset(this.baseY + event.offsetY, this.heightValue, this.scaleValue);
              }),
            TapGesture({ count: 2 }).onAction(() => { if (this.scaleValue > 1) { this.reset(); } else { this.zoom(2); } })
          ))
      } else { LoadingProgress().layoutWeight(1) }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        Button('上一张').height(44).fontSize(14).fontColor('#F2F3F5').backgroundColor('#30343C').borderRadius(14).padding({ left: 18, right: 18 }).margin({ right: 8, bottom: 8 }).enabled(this.index > 0).onClick(() => { this.move(-1); })
        Button('复位').height(44).fontSize(14).fontColor('#F2F3F5').backgroundColor('#30343C').borderRadius(14).padding({ left: 18, right: 18 }).margin({ right: 8, bottom: 8 }).onClick(() => { this.reset(); })
        Button('下一张').height(44).fontSize(14).fontColor('#F2F3F5').backgroundColor('#30343C').borderRadius(14).padding({ left: 18, right: 18 }).margin({ bottom: 8 }).enabled(this.index + 1 < this.params.images.length).onClick(() => { this.move(1); })
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 4 }).backgroundColor('#20242B')
      Text('双指缩放 · 放大后拖动 · 双击放大/复位').fontSize(12).fontColor('#A9B0BC').width('100%').textAlign(TextAlign.Center).padding({ left: 16, right: 16, bottom: 16 }).backgroundColor('#20242B')
    }.width('100%').height('100%').backgroundColor('#111111')
  }
}
