import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { ReaderOptions, ReaderSettings, ReaderSettingScope, ReaderSettingValue } from '../foundation/ReaderSettings';
import { ReaderModes, READER_MODES } from '../features/ReaderModes';
import { UiTheme, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

interface ReaderSettingsParams { comicId?: string; sourceKey?: string; }
/** Settings whose effects are actually consumed by ReaderPage/AsyncComicImage. */
@Entry
@Component
struct ReaderSettingsPage {
  @State options: ReaderOptions = new ReaderOptions();
  @State scope: ReaderSettingScope = 'global';
  @State profileEnabled: boolean = true;
  @State busy: boolean = true;
  @State error: string = '';
  @State comicId: string = '';
  @State sourceKey: string = '';
  private disposed: boolean = false;
  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.disposed = false;
    const params = router.getParams() as ReaderSettingsParams;
    this.comicId = params?.comicId ?? ''; this.sourceKey = params?.sourceKey ?? '';
    this.scope = this.comicId.length > 0 && this.sourceKey.length > 0 ? 'comic' : 'global';
    this.initialize();
  }
  aboutToDisappear(): void { this.disposed = true; }
  private async initialize(): Promise<void> {
    try { await AppInit.init(); if (!this.disposed) { this.refresh(); } }
    catch (error) { if (!this.disposed) { this.error = String(error); } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  private refresh(): void {
    this.options = ReaderSettings.resolveForScope(this.scope, this.comicId, this.sourceKey);
    this.profileEnabled = ReaderSettings.enabled(this.scope, this.comicId, this.sourceKey);
  }
  private refreshSafe(): void {
    try { this.refresh(); } catch (error) { this.error = String(error); }
  }
  private selectScope(scope: ReaderSettingScope): void {
    if (this.busy || this.disposed) { return; }
    this.scope = scope; this.error = '';
    try { this.refresh(); } catch (error) { this.error = String(error); }
  }
  private async save(name: string, value: ReaderSettingValue): Promise<void> {
    if (this.busy || this.disposed) { return; }
    this.busy = true; this.error = '';
    try {
      await ReaderSettings.set(this.scope, this.comicId, this.sourceKey, name, value);
      if (!this.disposed) { this.refresh(); promptAction.showToast({ message: '阅读设置已确认保存' }); }
    } catch (error) {
      if (!this.disposed) { this.error = String(error); this.refreshSafe(); }
    } finally { if (!this.disposed) { this.busy = false; } }
  }
  private async saveProfileEnabled(value: boolean): Promise<void> {
    if (this.busy || this.disposed) { return; }
    this.busy = true; this.error = '';
    try { await ReaderSettings.setEnabled(this.scope, value, this.comicId, this.sourceKey); if (!this.disposed) { this.refresh(); } }
    catch (error) { if (!this.disposed) { this.error = String(error); this.refreshSafe(); } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  private async reset(): Promise<void> {
    if (this.busy || this.disposed) { return; }
    const scope = this.scope;
    const confirmed = await promptAction.showDialog({ title: '重置当前阅读设置层？',
      message: '只重置当前范围的阅读选项，不删除历史、收藏、账号或其他漫画配置。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '重置', color: '#D93025' }] });
    if (confirmed.index !== 1 || this.disposed || this.busy || this.scope !== scope) { return; }
    this.busy = true; this.error = '';
    try { await ReaderSettings.reset(scope, this.comicId, this.sourceKey); if (!this.disposed) { this.refresh(); } }
    catch (error) { if (!this.disposed) { this.error = String(error); this.refreshSafe(); } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  private canEditOptions(): boolean { return !this.busy && (this.scope === 'global' || this.profileEnabled); }
  @Builder
  switchOption(title: string, name: string, value: boolean) {
    Row({ space: 14 }) {
      Text(title).fontSize(15).fontColor(UiTheme.ink).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(UiTheme.accent).enabled(this.canEditOptions())
        .onChange((next: boolean) => { this.save(name, next); })
    }.width('100%').constraintSize({ minHeight: 60 }).padding({ top: 12, bottom: 12 })
  }
  @Builder
  countOption(title: string, name: string, value: number, max: number) {
    Column({ space: 10 }) {
      Text(title).fontSize(15).fontColor(UiTheme.ink).width('100%')
      Row({ space: 12 }) {
        Text(`${value}`).fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.accent).layoutWeight(1)
        Button('−').attributeModifier(UiStyles.secondary).width(44).enabled(this.canEditOptions() && value > 1).onClick(() => { this.save(name, Math.min(value - 1, max)); })
        Button('+').attributeModifier(UiStyles.secondary).width(44).enabled(this.canEditOptions() && value < max).onClick(() => { this.save(name, value + 1); })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 60 }).padding({ top: 14, bottom: 14 })
  }
  @Builder
  choiceOption(title: string, name: string, value: string, choices: string[], labels: string[]) {
    Column({ space: 10 }) {
      Text(title).fontSize(15).fontColor(UiTheme.ink).width('100%')
      Button(labels[Math.max(0, choices.indexOf(value))]).attributeModifier(UiStyles.secondary).enabled(this.canEditOptions())
        .onClick(() => { this.save(name, choices[(choices.indexOf(value) + 1) % choices.length]); })
    }.alignItems(HorizontalAlign.Start).width('100%').constraintSize({ minHeight: 60 }).padding({ top: 14, bottom: 14 })
  }
  @Builder
  sliderOption(title: string, name: string, value: number, min: number, max: number, step: number) {
    Column({ space: 10 }) {
      Text(`${title}：${value}`).fontSize(15).fontColor(UiTheme.ink).width('100%')
      Slider({ value: value, min: min, max: max, step: step }).selectedColor(UiTheme.accent).enabled(this.canEditOptions())
        .onChange((next: number, mode: SliderChangeMode) => { if (mode === SliderChangeMode.End) { this.save(name, Math.round(next)); } })
    }.width('100%').padding({ top: 14, bottom: 14 })
  }
  build() {
    Column() {
      UiPageHeader({ title: '阅读器设置', subtitle: '按全局、设备或漫画分别配置', onBack: () => { router.back(); } })
      Scroll() {
        Column() {
          Column({ space: 12 }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('全局').attributeModifier(this.scope === 'global' ? UiStyles.primary : UiStyles.secondary)
                .enabled(!this.busy).margin({ right: 8, bottom: 8 }).onClick(() => { this.selectScope('global'); })
              Button('此设备').attributeModifier(this.scope === 'device' ? UiStyles.primary : UiStyles.secondary)
                .enabled(!this.busy).margin({ right: 8, bottom: 8 }).onClick(() => { this.selectScope('device'); })
              if (this.comicId.length > 0 && this.sourceKey.length > 0) {
                Button('此漫画').attributeModifier(this.scope === 'comic' ? UiStyles.primary : UiStyles.secondary)
                  .enabled(!this.busy).margin({ bottom: 8 }).onClick(() => { this.selectScope('comic'); })
              }
            }.width('100%')
            Text('显示所选层及其继承值；阅读时优先级为漫画 → 此设备 → 全局。保存只写入所选层，关闭档案时普通选项继承。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            if (this.scope !== 'global') {
              Row({ space: 12 }) {
                Text(this.scope === 'comic' ? '启用此漫画其他阅读选项' : '启用此设备阅读选项').fontSize(15).fontColor(UiTheme.ink).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.profileEnabled }).selectedColor(UiTheme.accent).enabled(!this.busy)
                  .onChange((value: boolean) => { this.saveProfileEnabled(value); })
              }.width('100%').constraintSize({ minHeight: 48 }).padding({ top: 8, bottom: 8 })
            }
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '阅读模式' })
          Column() {
            Text('此漫画的模式覆盖独立于其他选项开关').fontSize(12).fontColor(UiTheme.secondary).width('100%').margin({ bottom: 10 })
            ForEach(READER_MODES, (mode: string) => {
              Row() {
                Text(ReaderModes.label(mode)).fontSize(15).fontColor(UiTheme.ink).layoutWeight(1)
                Text(this.options.readerMode === mode ? '●' : '○').fontSize(20)
                  .fontColor(this.options.readerMode === mode ? UiTheme.accent : '#CCD2DC')
              }.width('100%').constraintSize({ minHeight: 52 }).padding({ top: 12, bottom: 12 })
                .enabled(!this.busy).onClick(() => { this.save('readerMode', mode); })
            }, (mode: string) => mode)
            if (this.scope === 'comic') {
              Button('此漫画模式继承设备/全局').attributeModifier(UiStyles.secondary).enabled(!this.busy)
                .margin({ top: 10 }).onClick(() => { this.save('readerModeOverride', 'default'); })
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '图片与版式' })
          Column() {
            this.countOption('竖屏画廊每屏图片', 'readerScreenPicNumberForPortrait', this.options.readerScreenPicNumberForPortrait, 5)
            Divider().color(UiTheme.line)
            this.countOption('横屏画廊每屏图片', 'readerScreenPicNumberForLandscape', this.options.readerScreenPicNumberForLandscape, 5)
            Divider().color(UiTheme.line)
            this.switchOption('画廊首张单独一屏', 'showSingleImageOnFirstPage', this.options.showSingleImageOnFirstPage)
            this.switchOption('纵向连续/瀑布流拆分宽图', 'splitDualPage', this.options.splitDualPage)
            this.switchOption('交换宽图上下两半顺序', 'splitDualPageInvert', this.options.splitDualPageInvert)
            Text('宽图拆分保持原图片页身份；默认右半在上、左半在下，不影响下载文件或画廊模式。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            Text(`纵向边距：每侧 ${this.options.readerSideMargin}%`).fontSize(15).fontColor(UiTheme.ink).width('100%').padding({ top: 20 })
            Slider({ value: this.options.readerSideMargin, min: 0, max: 30, step: 1 }).selectedColor(UiTheme.accent).enabled(this.canEditOptions())
              .onChange((value: number, mode: SliderChangeMode) => { if (mode === SliderChangeMode.End) { this.save('readerSideMargin', Math.round(value)); } })
            this.switchOption('限制纵向图片最大宽度（900vp）', 'limitImageWidth', this.options.limitImageWidth)
          }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 12 }).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '点击与手势' })
          Column() {
            this.switchOption('点击区域翻页', 'enableTapToTurnPages', this.options.enableTapToTurnPages)
            this.switchOption('反转点击翻页方向', 'reverseTapToTurnPages', this.options.reverseTapToTurnPages)
            Text('正文按整个阅读窗口分成九宫格（各占三分之一），不按单张图片重复分区。默认：')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            Text('上排 上一页 · 上一页 · 下一页\n中排 上一页 · 菜单 · 下一页\n下排 上一页 · 下一页 · 下一页')
              .fontSize(12).fontColor(UiTheme.ink).lineHeight(20).width('100%')
            Text('进入正文时菜单隐藏；点正中显示菜单，点其他任意位置翻页。菜单打开时点正文只关闭菜单，不会同时翻页。长图模式一次翻动一屏；缩放、滚动和加载中不误翻页。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            this.switchOption('双击缩放（不关闭pinch/pan）', 'enableDoubleTapToZoom', this.options.enableDoubleTapToZoom)
            this.switchOption('画廊跳页动画', 'enablePageAnimation', this.options.enablePageAnimation)
            this.choiceOption('长按图片', 'longPressAction', this.options.longPressAction,
              ['zoom', 'autoReading', 'menu', 'none'], ['按住2倍缩放', '开始/暂停自动阅读', '图片操作菜单', '不操作'])
            this.choiceOption('长按缩放锚点', 'longPressZoomPosition', this.options.longPressZoomPosition,
              ['press', 'center'], ['按下位置', '图片中心'])
            Text('长按缩放松手即恢复；原有双击缩放、双指缩放和放大拖动仍保留。图片菜单/收藏按钮是显式动作，不自动收藏，不改变源图片页身份。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            this.switchOption('音量键翻页（仅阅读器前台）', 'enableTurnPageByVolumeKey', this.options.enableTurnPageByVolumeKey)
            Text('仅在章节已加载、阅读器显示时注册系统按键消费；关闭/离开立即释放。上键上一页、下键下一页。不修改设备音量，不使用音量变化轮询。设备不支持时阅读器会提示。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
          }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 20 }).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '阅读显示' })
          Column() {
            this.switchOption('启用阅读器窗口亮度', 'readerBrightnessEnabled', this.options.readerBrightnessEnabled)
            this.sliderOption('阅读亮度（百分比）', 'readerBrightness', this.options.readerBrightness, 20, 100, 1)
            this.switchOption('显示页码', 'showPageNumberInReader', this.options.showPageNumberInReader)
            this.switchOption('显示时间与电量', 'enableClockAndBatteryInfoInReader', this.options.enableClockAndBatteryInfoInReader)
          }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 8 }).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '自动阅读' })
          Column() {
            this.countOption('自动翻页间隔（秒，原版1–20）', 'autoPageTurningInterval', this.options.autoPageTurningInterval, 20)
            this.switchOption('自动阅读允许跨章节', 'autoReadingAcrossChapters', this.options.autoReadingAcrossChapters)
            this.choiceOption('纵向连续模式自动滚动', 'autoScrollStyle', this.options.autoScrollStyle, ['smooth', 'stepped'], ['平滑', '分步'])
            this.sliderOption('平滑速度（像素/秒）', 'autoScrollSpeed', this.options.autoScrollSpeed, 10, 1000, 10)
            this.sliderOption('分步频率（次/秒）', 'autoScrollFrequency', this.options.autoScrollFrequency, 1, 10, 1)
            this.sliderOption('分步距离（像素）', 'autoScrollDistance', this.options.autoScrollDistance, 10, 500, 10)
            Text('自动滚动仅用于纵向连续/瀑布流；画廊与横向连续模式按翻页间隔。加载、缩放、后台不自动移动。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
          }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 20 }).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '原版设置支持范围' })
          Column({ space: 10 }) {
            Text('已绑定：模式/分屏/拆宽图/边距/宽度、点击与动画、双击与长按、自动翻页与纵向滚动、亮度、音量键、页码、时间电量；全局/设备/漫画分层保存。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            Text('未移植（不提供无效开关）：自动版式检测与按版式模式、墨水屏硬件刷新、鼠标滚轮倍率、系统状态栏、预加载数量、自定义图片处理、章节评论/章末评论、快捷双击或滑动收藏。预加载继续使用已验证的单邻居懒加载窗口；图片收藏请使用明确按钮或菜单。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(UiTheme.danger).width('100%').padding(18)
              .backgroundColor(UiTheme.dangerSoft).borderRadius(18).margin({ top: 16 })
          }
          Button('重置当前设置层').attributeModifier(UiStyles.danger).enabled(!this.busy).onClick(() => { this.reset(); }).margin({ top: 20 })
        }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
