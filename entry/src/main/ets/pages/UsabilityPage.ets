import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { HistoryUsability } from '../features/HistoryUsability';
import { FavoritesUsability } from '../features/FavoritesUsability';
import { UiUsability } from '../features/UiUsability';
import { HistoryNavigation } from '../features/HistoryNavigation';
import { HistoryDao } from '../storage/HistoryDao';
import { Log } from '../foundation/Log';
import { Settings } from '../foundation/Settings';
import { SourceSettingsUsability } from '../features/SourceSettingsUsability';
import { SourceAcceptance } from '../source/SourceAcceptance';
import { SourceSelfTest } from '../source/SourceSelfTest';
import { TransferUsability } from '../features/TransferUsability';
import { ImagePipelineUsability } from '../features/ImagePipelineUsability';
import { DownloadLifecycleUsability } from '../features/DownloadLifecycleUsability';
import { SourceAccountUsability } from '../features/SourceAccountUsability';
import { UiTheme, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Optional diagnostics, never claims that a logic test proves the entire UI. */
@Entry
@Component
struct UsabilityPage {
  @State busy: boolean = false;
  @State reports: string[] = [];
  @State error: string = '';
  @State progress: string = '';
  @State deepSelfTest: boolean = false;
  @State startupSelfTest: boolean = false;
  @State savingStartup: boolean = false;
  @State matrixStatus: string = '';
  @State matrixActive: boolean = false;
  private matrixTimer: number = -1;

  aboutToDisappear(): void {
    if (this.matrixTimer >= 0) { clearInterval(this.matrixTimer); this.matrixTimer = -1; }
    if (SourceAcceptance.running) { SourceAcceptance.cancel(); }
  }

  private async runPublicTemplateProbe(sourceKey: string = 'wnacg'): Promise<void> {
    if (this.busy || SourceAcceptance.running) { return; }
    this.busy = true; this.error = ''; this.reports = [];
    try { await AppInit.init(); this.reports = await SourceAcceptance.runPublicTemplateProbe(sourceKey); }
    catch (error) { this.error = String(error); }
    finally { this.busy = false; }
  }

  private async runDeepMatrix(): Promise<void> {
    if (this.busy || SourceAcceptance.running) { return; }
    this.busy = true;
    this.matrixActive = true;
    this.error = '';
    this.reports = [];
    this.matrixTimer = setInterval(() => { this.matrixStatus = SourceAcceptance.status; }, 500);
    try {
      await AppInit.init();
      this.reports = await SourceAcceptance.run();
    } catch (error) {
      this.error = String(error);
    } finally {
      clearInterval(this.matrixTimer);
      this.matrixTimer = -1;
      this.matrixStatus = SourceAcceptance.status;
      this.busy = false;
      this.matrixActive = false;
    }
  }

  private async transferProbe(sync: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    this.reports = [];
    try {
      await AppInit.init();
      this.reports = sync ? await TransferUsability.sync() : await TransferUsability.download();
    } catch (error) { this.error = String(error); }
    finally { this.busy = false; }
  }

  private async imageHttpProbe(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.reports = [];
    try { await AppInit.init(); this.reports = await ImagePipelineUsability.run(); }
    catch (error) { this.error = String(error); }
    finally { this.busy = false; }
  }

  private async downloadLifecycleProbe(finish: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.reports = [];
    try { await AppInit.init(); this.reports = finish ? await DownloadLifecycleUsability.finish() : await DownloadLifecycleUsability.prepare(); }
    catch (error) { this.error = String(error); }
    finally { this.busy = false; }
  }

  private async accountFixture(cleanup: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      await AppInit.init();
      if (cleanup) { await SourceAccountUsability.cleanup(); this.reports = ['已清理合成账号验收；未修改真实账号']; }
      else {
        const key = await SourceAccountUsability.prepare();
        await router.pushUrl({ url: 'pages/SourceAccountPage', params: { key: key } });
      }
    } catch (error) { this.error = String(error); }
    finally { this.busy = false; }
  }

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.refresh();
  }

  onPageShow(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    try {
      await AppInit.init();
      if (!this.savingStartup) {
        this.deepSelfTest = Settings.sourceSelfTestDeep;
        this.startupSelfTest = Settings.getBool('sourceSelfTest', false);
      }
      const id = HistoryUsability.fixtureId();
      const saved = id.length > 0 ? await HistoryDao.find(id, 0) : undefined;
      this.progress = saved === undefined ? '尚无样本阅读进度' :
        `${saved.description()} · ID=${saved.epId ?? '(旧记录)'} · 时长 ${saved.readDurationMs}ms`;
    } catch (error) {
      this.error = String(error);
    }
  }

  private async saveStartupOption(key: string, value: boolean): Promise<void> {
    if (this.savingStartup || this.busy) { return; }
    this.savingStartup = true;
    try {
      await Settings.setBool(key, value);
      if (key === 'sourceSelfTest') {
        this.startupSelfTest = value;
        if (!value) { SourceSelfTest.stopAfterCurrentSource(); }
      } else { this.deepSelfTest = value; }
    } catch (error) {
      promptAction.showToast({ message: '源自检设置保存失败，保留上次已保存值，请重试' });
    } finally { this.savingStartup = false; }
  }

  private async run(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    this.reports = [];
    try {
      await AppInit.init();
      this.reports = await HistoryUsability.run();
    } catch (error) {
      this.error = `FAIL · ${error instanceof Error ? error.message : String(error)}`;
      Log.error('HistoryUsability', this.error);
    } finally {
      this.busy = false;
    }
  }

  private async runFavorites(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    this.reports = [];
    try {
      await AppInit.init();
      this.reports = await FavoritesUsability.run();
    } catch (error) {
      this.error = `FAIL · ${error instanceof Error ? error.message : String(error)}`;
      Log.error('FavoritesUsability', this.error);
    } finally {
      this.busy = false;
    }
  }

  /**
   * Needs a person to answer the dialogs, so it stays a manual step. It proves
   * the ArkTS dialog -> JS callback -> JS promise chain that no offline test can.
   */
  private async runUi(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    this.reports = [];
    try {
      await AppInit.init();
      const result = await UiUsability.run();
      this.reports = [`UI 自检结果：${result}`];
    } catch (error) {
      this.error = `FAIL · ${error instanceof Error ? error.message : String(error)}`;
      Log.error('UiUsability', this.error);
    } finally {
      this.busy = false;
    }
  }

  private async sourceSettingsFixture(cleanup: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      await AppInit.init();
      if (cleanup) {
        await SourceSettingsUsability.cleanup();
        this.reports = ['PASS · 已清理离线源设置样本；未修改真实源'];
      } else {
        const key = await SourceSettingsUsability.prepare();
        await router.pushUrl({ url: 'pages/SourceSettingsPage', params: { key: key } });
      }
    } catch (error) {
      this.error = String(error);
    } finally {
      this.busy = false;
    }
  }

  private async sample(resume: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      await AppInit.init();
      const sample = await HistoryUsability.prepareFixture();
      if (resume) {
        await HistoryNavigation.resume(sample);
      } else {
        await HistoryNavigation.openDetails(sample);
      }
    } catch (error) {
      this.error = String(error);
    } finally {
      this.busy = false;
    }
  }

  private async cleanup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const choice = await promptAction.showDialog({
        title: '清理离线样本', message: '仅删除本页生成且带标记的样本目录及其历史，不清除其他漫画或历史。',
        buttons: [{ text: '取消', color: '#666666' }, { text: '清理样本', color: '#D93025' }]
      });
      if (choice.index === 1) {
        await HistoryUsability.cleanupFixture();
        await this.refresh();
      }
    } catch (error) {
      this.error = String(error);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '离线可用性验收', subtitle: '诊断工具与手动验收入口', onBack: () => { router.back(); } })
        Column() {
          Text('离线用例不联网；标注“联网/公开”的按钮会访问外网。均不输入真实账号。数据库样本只操作随机测试记录并清理；本地样本仅在点击后生成。')
            .fontSize(13).fontColor(UiTheme.secondary).lineHeight(21).width('100%').padding(20)
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          UiSectionHeading({ title: '离线逻辑与对话框' })
          Column({ space: 12 }) {
            Button(this.busy ? '执行中…' : '运行历史逻辑回归').attributeModifier(UiStyles.primary).width('100%').enabled(!this.busy)
              .onClick(() => { this.run(); })
            Button(this.busy ? '执行中…' : '运行收藏夹逻辑回归').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy)
              .onClick(() => { this.runFavorites(); })
            Button(this.busy ? '执行中…' : '运行 UI 对话框自检（需手动操作）').attributeModifier(UiStyles.secondary)
              .width('100%').height(56).labelStyle({ maxLines: 2 }).enabled(!this.busy)
              .onClick(() => { this.runUi(); })
            Button('运行离线下载回归').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.transferProbe(false); })
            Button('运行离线同步回归').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.transferProbe(true); })
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '联网与公开模板诊断' })
          Column({ space: 12 }) {
            Button('公开模板诊断（无Cookie，只读）').attributeModifier(UiStyles.secondary).width('100%').height(52).labelStyle({ maxLines: 2 }).enabled(!this.busy)
              .onClick(() => { this.runPublicTemplateProbe(); })
            Button('EH公开模板诊断（无Cookie，只读）').attributeModifier(UiStyles.secondary).width('100%').height(52).labelStyle({ maxLines: 2 }).enabled(!this.busy)
              .onClick(() => { this.runPublicTemplateProbe('ehentai'); })
            Button('运行深度源矩阵（联网，只读）').attributeModifier(UiStyles.secondary).width('100%').height(52).labelStyle({ maxLines: 2 }).enabled(!this.busy)
              .onClick(() => { this.runDeepMatrix(); })
            if (this.matrixStatus.length > 0) {
              Text(this.matrixStatus).fontSize(13).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            }
            if (this.matrixActive) {
              Button('停止深度矩阵').attributeModifier(UiStyles.danger).onClick(() => { SourceAcceptance.cancel(); })
            }
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: 'CLI 本机验收' })
          Column({ space: 12 }) {
            Button('运行本机图片HTTP回归（需CLI测试服务器）').attributeModifier(UiStyles.secondary).width('100%').height(60).labelStyle({ maxLines: 2 }).enabled(!this.busy).onClick(() => { this.imageHttpProbe(); })
            Button('准备下载后台暂停验收（CLI服务器）').attributeModifier(UiStyles.secondary).width('100%').height(56).labelStyle({ maxLines: 2 }).enabled(!this.busy).onClick(() => { this.downloadLifecycleProbe(false); })
            Button('复核并清理后台暂停验收').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.downloadLifecycleProbe(true); })
            Button('打开本机合成账号验收（需CLI服务器）').attributeModifier(UiStyles.secondary).width('100%').height(56).labelStyle({ maxLines: 2 }).enabled(!this.busy).onClick(() => { this.accountFixture(false); })
            Button('清理本机合成账号验收').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.accountFixture(true); })
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '离线样本与阅读进度' })
          Column({ space: 12 }) {
            Button('打开离线源设置样本').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy)
              .onClick(() => { this.sourceSettingsFixture(false); })
            Button('清理离线源设置样本').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy)
              .onClick(() => { this.sourceSettingsFixture(true); })
            Button('打开本地样本详情').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.sample(false); })
            Button('继续阅读本地样本').attributeModifier(UiStyles.secondary).width('100%').enabled(!this.busy).onClick(() => { this.sample(true); })
            Text(this.progress).fontSize(13).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
            Button('刷新进度').attributeModifier(UiStyles.quiet).enabled(!this.busy).onClick(() => { this.refresh(); })
            Text('手动验收：进入第2章翻到第2页 → 返回 → 强制重启 → 从历史继续阅读；检查章节、页码及图片文字。分别测试翻页和瀑布流。')
              .fontSize(13).fontColor(UiTheme.secondary).lineHeight(21).width('100%')
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '启动源自检' })
          Column({ space: 16 }) {
            Button('停止启动源自检（等当前源结束）').attributeModifier(UiStyles.secondary).width('100%').height(56).labelStyle({ maxLines: 2 }).enabled(!this.busy)
              .onClick(() => { SourceSelfTest.stopAfterCurrentSource(); this.matrixStatus = '已请求停止；不再启动后续源'; })
            Row({ space: 12 }) {
              Text('每次启动自动联网源自检（默认关闭）').fontSize(14).fontColor(UiTheme.ink).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.startupSelfTest }).selectedColor(UiTheme.accent)
                .enabled(!this.savingStartup && !this.busy)
                .onChange((value: boolean) => { this.saveStartupOption('sourceSelfTest', value); })
            }.width('100%').constraintSize({ minHeight: 56 })
            Divider().color(UiTheme.line)
            Row({ space: 12 }) {
              Column({ space: 8 }) {
                Text('源自检深度取样（需启用启动自检；下次启动生效）').fontSize(14).fontColor(UiTheme.ink)
                Text('开启后按 SOURCE_ACCEPTANCE 的 L2/L3 取样：全部探索页与第2页、全部分类分组、2 关键词 × 2 页、章节首/中/末与每章 3 张解码图。每源约多 10 次图片请求。')
                  .fontSize(12).fontColor(UiTheme.secondary).lineHeight(20)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.deepSelfTest }).selectedColor(UiTheme.accent)
                .enabled(!this.savingStartup && !this.busy)
                .onChange((value: boolean) => { this.saveStartupOption('sourceSelfTestDeep', value); })
            }.width('100%').constraintSize({ minHeight: 56 })
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          UiSectionHeading({ title: '诊断结果' })
          if (this.error.length > 0) {
            Text(this.error).fontColor(UiTheme.danger).fontSize(13).lineHeight(20).width('100%').padding(18)
              .backgroundColor(UiTheme.dangerSoft).borderRadius(18).margin({ bottom: 12 })
          }
          Scroll() {
            Column({ space: 12 }) {
              ForEach(this.reports, (line: string) => {
                Text(line).fontColor('#176b39').fontSize(13).lineHeight(20).width('100%')
              }, (line: string) => line)
            }.width('100%').padding(20)
          }.height(220).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          Button('清理本页生成的样本').attributeModifier(UiStyles.danger).enabled(!this.busy).margin({ top: 20 })
            .onClick(() => { this.cleanup(); })
        }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.width('100%')
    }.width('100%').height('100%').backgroundColor(UiTheme.page).scrollBar(BarState.Off)
  }
}
