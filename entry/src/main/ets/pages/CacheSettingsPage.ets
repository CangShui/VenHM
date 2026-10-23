import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { CacheStats } from '../foundation/CacheStore';
import { ImageLoader } from '../network/ImageLoader';
import { CacheLimitOption, CacheManager, CacheSettings } from '../storage/CacheSettings';
import { UiTheme, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/**
 * 缓存管理.
 *
 * Shows what the disk cache currently holds (covers, comic details, chapter
 * pages), lets the user pick the total cap and clear it. Downloads, reading
 * history, favorites, accounts and comic sources are deliberately out of scope
 * here - clearing the cache must never look like "delete my library".
 */
@Entry
@Component
struct CacheSettingsPage {
  @State stats: CacheStats = new CacheStats();
  @State limit: number = CacheSettings.DEFAULT_LIMIT_BYTES;
  @State busy: boolean = true;
  @State error: string = '';
  private disposed: boolean = false;

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.disposed = false;
    this.initialize();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    // Persist the debounced index before the page goes away.
    try {
      CacheManager.imageStore().flush();
    } catch (error) {
      // Leaving the page must never fail because the cache is unavailable.
    }
  }

  private async initialize(): Promise<void> {
    try {
      await AppInit.init();
      if (!this.disposed) { this.refresh(); }
    } catch (error) {
      if (!this.disposed) { this.error = error instanceof Error ? error.message : String(error); }
    } finally {
      if (!this.disposed) { this.busy = false; }
    }
  }

  private refresh(): void {
    try {
      this.limit = CacheSettings.limitBytes();
      const store = CacheManager.imageStore();
      store.flush();
      this.stats = store.stats();
      this.error = '';
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
    }
  }

  private usagePercent(): number {
    if (this.stats.maxBytes <= 0) { return 0; }
    return Math.min(100, Math.round(this.stats.bytes * 100 / this.stats.maxBytes));
  }

  private async selectLimit(bytes: number): Promise<void> {
    if (this.busy || this.disposed || bytes === this.limit) { return; }
    this.busy = true;
    this.error = '';
    try {
      const accepted = await CacheManager.setLimit(bytes);
      if (this.disposed) { return; }
      this.limit = accepted;
      this.refresh();
      promptAction.showToast({ message: `最大缓存已设为 ${CacheSettings.label(accepted)}` });
    } catch (error) {
      if (!this.disposed) {
        this.error = error instanceof Error ? error.message : String(error);
        this.refresh();
      }
    } finally {
      if (!this.disposed) { this.busy = false; }
    }
  }

  private async clearCache(): Promise<void> {
    if (this.busy || this.disposed) { return; }
    const size = CacheSettings.label(this.stats.bytes);
    const confirmed = await promptAction.showDialog({
      title: '清除缓存？',
      message: `将删除已缓存的封面、漫画详情与章节页（当前 ${size}），下次打开会重新下载。\n\n` +
        '不会删除：已下载的漫画文件、阅读历史、收藏、账号和漫画源。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '清除缓存', color: '#D93025' }]
    });
    if (confirmed.index !== 1 || this.disposed || this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      // Disk entries first, then the decoded PixelMaps held in memory: both must
      // go, otherwise the screen keeps showing pictures the cache no longer has.
      const next = CacheManager.clear();
      ImageLoader.clearMemory();
      if (this.disposed) { return; }
      this.stats = next;
      promptAction.showToast({ message: '缓存已清除，下载与阅读历史未改动' });
    } catch (error) {
      if (!this.disposed) { this.error = error instanceof Error ? error.message : String(error); }
    } finally {
      if (!this.disposed) { this.busy = false; }
    }
  }

  @Builder
  limitRow(option: CacheLimitOption) {
    Row() {
      Column({ space: 4 }) {
        Text(option.label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
        if (option.bytes === CacheSettings.DEFAULT_LIMIT_BYTES) {
          Text('默认').fontSize(12).fontColor(UiTheme.muted)
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.limit === option.bytes ? '●' : '○').fontSize(20)
        .fontColor(this.limit === option.bytes ? UiTheme.accent : '#CCD2DC')
    }.width('100%').constraintSize({ minHeight: 56 }).padding({ top: 12, bottom: 12 })
      .enabled(!this.busy).onClick(() => { this.selectLimit(option.bytes); })
  }

  build() {
    Column() {
      UiPageHeader({ title: '缓存管理', subtitle: '管理临时内容，不影响下载与阅读记录', onBack: () => { router.back(); } })
      Scroll() {
        Column() {
          Column({ space: 16 }) {
            Row() {
              Column({ space: 7 }) {
                Text('当前占用').fontSize(13).fontColor(UiTheme.secondary)
                Text(this.busy ? '统计中…' : CacheSettings.label(this.stats.bytes))
                  .fontSize(30).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
                Text(`共 ${this.stats.entries} 项 · 上限 ${CacheSettings.label(this.stats.maxBytes)}`)
                  .fontSize(12).fontColor(UiTheme.muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Text(`${this.usagePercent()}%`).fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.accent)
            }.width('100%')
            Progress({ value: this.usagePercent(), total: 100, type: ProgressType.Linear })
              .color(UiTheme.accent).backgroundColor(UiTheme.accentSoft).width('100%')
            Text('缓存内容：漫画封面、漫画详情、章节图片页。清空后再次打开会重新下载。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
          }.alignItems(HorizontalAlign.Start).width('100%').padding(22)
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '最大缓存' })
          Column() {
            Text('超过上限时自动清理最久未使用的缓存项，再写入新内容；单项超过上限时拒绝写入，不会清空其他缓存。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%').margin({ bottom: 10 })
            ForEach(CacheSettings.options(), (option: CacheLimitOption) => {
              this.limitRow(option)
            }, (option: CacheLimitOption) => `${option.bytes}`)
          }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 8 })
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '缓存维护' })
          Column({ space: 16 }) {
            Text('“清除缓存”只删除封面、详情与章节页缓存。已下载的漫画文件、阅读历史、收藏、账号与漫画源都不受影响；阅读历史与下载请在各自页面管理。')
              .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('清除缓存').attributeModifier(UiStyles.danger).enabled(!this.busy)
                .margin({ right: 10, bottom: 8 }).onClick(() => { this.clearCache(); })
              Button('重新统计').attributeModifier(UiStyles.secondary).enabled(!this.busy)
                .margin({ bottom: 8 }).onClick(() => { this.refresh(); })
            }.width('100%')
          }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(UiTheme.danger).lineHeight(20).width('100%').padding(18)
              .backgroundColor(UiTheme.dangerSoft).borderRadius(18).margin({ top: 16 })
          }
        }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
