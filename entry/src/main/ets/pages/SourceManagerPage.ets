import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { SourceRepositories, SourceRepository } from '../source/SourceRepository';
import { SourceInstaller } from '../source/SourceInstaller';
import { InstalledSource } from '../storage/SourceDao';
import { JsRuntimeStatus } from '../source/JsRuntime';
import { JsEngine } from '../source/JsEngine';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { RepositoryParams } from '../model/RouteParams';
import { Log } from '../foundation/Log';
import { UiTheme, UiIcon, UiSettingsRow, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/**
 * Comic source management hub.
 *
 * Dart original: lib/features/comic_source/comic_source_page.dart (1238 lines)
 * with repository browsing, install-from-URL/file, script editing and per-source
 * settings. The port keeps: runtime status, built-in sources, installed scripts
 * and repository management. Script editing and per-source settings are later
 * modules.
 */
@Entry
@Component
struct SourceManagerPage {
  @State builtinSources: ComicSource[] = [];
  @State installedSources: InstalledSource[] = [];
  @State repositories: SourceRepository[] = [];
  @State repoUrlInput: string = '';
  @State loading: boolean = true;
  @State initError: string = '';
  @State loadErrors: string[] = [];
  @State loggedKeys: string[] = [];
  @State accountBusy: boolean = false;
  private disposed: boolean = false;
  private reloadVersion: number = 0;

  /** Open the account/password dialog for a source that declares login. */
  private openLogin(source: ComicSource): void {
    if (this.accountBusy) { return; }
    if (!source.account?.canLogin) {
      promptAction.showToast({ message: '该源未声明可用登录路径' });
      Log.audit(`source-login-ui-${Date.now()}`, '登录入口拒绝', '无密码/Cookie/Web契约，未调用不存在的login');
      return;
    }
    router.pushUrl({ url: 'pages/SourceAccountPage', params: { key: source.key } }).catch((error: Object) => {
      Log.audit('source-account-open', '账号路由异常', '未打开账号页面，路由不含凭据');
    });
  }

  private async doLogout(source: ComicSource): Promise<void> {
    if (this.accountBusy) { return; }
    const config = source.account;
    if (config?.logout === undefined) { return; }
    this.accountBusy = true;
    try {
      await config.logout();
      if (!this.disposed) { promptAction.showToast({ message: '已退出登录' }); }
    } catch (error) {
      if (!this.disposed) { promptAction.showToast({ message: '退出失败，未确认清除账号；请重试', duration: 4000 }); }
    } finally { if (!this.disposed) { this.accountBusy = false; } }
    if (!this.disposed) { this.reload(); }
  }

  private async relogin(source: ComicSource): Promise<void> {
    if (this.accountBusy || source.account?.relogin === undefined) { return; }
    this.accountBusy = true;
    const trace = `source-relogin-ui-${Date.now()}-${source.key}`;
    try {
      const result = await source.account.relogin(trace);
      if (!this.disposed) { promptAction.showToast({ message: result.error ? '重新登录失败，请手工登录' : '重新登录已确认' }); }
    } catch (error) { Log.audit(trace, '重新登录UI异常', '不记录已保存的账号/密码'); }
    finally { if (!this.disposed) { this.accountBusy = false; this.reload(); } }
  }

  aboutToAppear(): void {
    this.disposed = false;
    this.accountBusy = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.reload();
  }
  onPageShow(): void {
    if (!this.disposed) { this.reload(); }
  }
  aboutToDisappear(): void {
    this.disposed = true;
    this.reloadVersion++;
  }

  async reload(): Promise<void> {
    const version = ++this.reloadVersion;
    const trace = `source-page-reload-${Date.now()}-${version}`;
    Log.audit(trace, '源页面读取到达', '等待初始化/已安装列表；晚到响应不覆盖新页面');
    this.loading = true;
    try {
      await AppInit.init();
      const installed = await SourceInstaller.listInstalled();
      if (this.disposed || version !== this.reloadVersion) {
        Log.audit(trace, '源页面读取丢弃', '页面退出或已有更新请求；不更新界面');
        return;
      }
      this.builtinSources = SourceManager.all().slice();
      this.loggedKeys = this.builtinSources.filter((source: ComicSource) => source.isLogged).map((source: ComicSource) => source.key);
      this.installedSources = installed;
      this.repositories = SourceRepositories.all();
      this.loadErrors = SourceManager.errors;
      this.initError = '';
      Log.audit(trace, '源页面读取返回', `源数=${this.builtinSources.length}；已安装=${installed.length}；加载错误=${this.loadErrors.length}`);
    } catch (error) {
      if (!this.disposed && version === this.reloadVersion) {
        this.initError = error instanceof Error ? error.message : String(error);
      }
      Log.audit(trace, '源页面读取异常', '读取失败，不覆盖后续请求或已退出页面');
    } finally {
      if (!this.disposed && version === this.reloadVersion) { this.loading = false; }
    }
  }

  async addRepository(): Promise<void> {
    const value = this.repoUrlInput.trim();
    if (value.length === 0) {
      promptAction.showToast({ message: '请输入仓库地址' });
      return;
    }
    try {
      SourceRepositories.normalizeUrl(value);
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : String(error) });
      return;
    }
    try {
      await SourceRepositories.add('', value);
      this.repoUrlInput = '';
      this.repositories = SourceRepositories.all();
      promptAction.showToast({ message: '仓库已添加，点「浏览」加载源列表' });
    } catch (error) {
      promptAction.showToast({ message: `添加失败: ${error}` });
    }
  }

  private openRepository(repo: SourceRepository): void {
    const params: RepositoryParams = {
      repositoryId: repo.id,
      repositoryName: repo.name,
      repositoryUrl: repo.url
    };
    router.pushUrl({ url: 'pages/SourceRepositoryPage', params: params })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开失败: ${error}` });
      });
  }

  private openSourceSettings(key: string): void {
    router.pushUrl({ url: 'pages/SourceSettingsPage', params: { key: key } })
      .catch((error: Object) => {
        promptAction.showToast({ message: `打开源设置失败: ${error}` });
      });
  }

  @Builder
  groupHeader(title: string) {
    UiSectionHeading({ title: title })
  }

  @Builder
  capabilityRow(label: string, supported: boolean) {
    Row({ space: 5 }) {
      Text(supported ? '✓' : '✗').fontSize(12).fontColor(supported ? UiTheme.success : '#BCC2CC')
      Text(label).fontSize(12).fontColor(UiTheme.secondary)
    }.margin({ right: 14, bottom: 8 })
  }

  build() {
    Column() {
      UiPageHeader({ title: '源管理', subtitle: '漫画源、脚本与源仓库', onBack: () => {
        router.back();
      } })
      Row() {
        Text(this.loading ? '正在读取漫画源…' : `已加载 ${this.builtinSources.length} 个源`)
          .fontSize(13).fontColor(UiTheme.secondary).layoutWeight(1)
        Button('刷新').attributeModifier(UiStyles.quiet).onClick(() => {
          this.reload();
        })
      }.width('100%').padding({ left: 24, right: 20, bottom: 12 })
      Scroll() {
        Column() {
          if (this.initError.length > 0) {
            Text(`初始化失败: ${this.initError}`).fontSize(13).fontColor(UiTheme.danger).lineHeight(20)
              .width('100%').padding(18).backgroundColor(UiTheme.dangerSoft).borderRadius(18)
          }
          if (this.loadErrors.length > 0) {
            Column({ space: 6 }) {
              Text(`有 ${this.loadErrors.length} 个脚本加载失败`).fontSize(13).fontWeight(FontWeight.Medium).fontColor(UiTheme.danger)
              ForEach(this.loadErrors, (item: string) => {
                Text(item).fontSize(12).fontColor(UiTheme.danger).lineHeight(18)
              }, (item: string) => item)
            }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
              .backgroundColor(UiTheme.dangerSoft).borderRadius(18).margin({ top: 12 })
          }

          this.groupHeader('扩展运行时')
          Column({ space: 12 }) {
            Row({ space: 14 }) {
              Stack() { UiIcon({ name: 'layers', color: '#7A64CB', iconSize: 23 }) }
                .width(46).height(46).borderRadius(15).backgroundColor('#F0EBFC')
              Text('QuickJS 漫画源脚本').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).layoutWeight(1)
              Text(JsRuntimeStatus.isAvailable ? '可用' : '未接入').fontSize(12)
                .fontColor(JsRuntimeStatus.isAvailable ? UiTheme.success : '#D69A2D')
            }.width('100%')
            if (JsRuntimeStatus.isAvailable) {
              Text(`引擎版本: ${JsRuntimeStatus.engineVersion}`).fontSize(12).fontColor(UiTheme.secondary)
              Text(`自检 evaluate(): ${JsRuntimeStatus.smokeResult}`).fontSize(12).fontColor(UiTheme.secondary)
            } else {
              Text(JsRuntimeStatus.unavailableReason).fontSize(12).fontColor(UiTheme.danger).lineHeight(20)
            }
            Text(`源脚本目录: ${AppContext.sourceDir}`).fontSize(11).fontColor(UiTheme.muted).lineHeight(18)
            Button('重新自检').attributeModifier(UiStyles.secondary).onClick(() => {
              try {
                const result = JsEngine.evaluate(
                  '(() => { const a = [1,2,3].map(x => x * 2); ' +
                  'return JSON.stringify({sum: a.reduce((p,c) => p+c, 0), n: a.length}); })()',
                  '<smoke>');
                promptAction.showToast({ message: `自检结果: ${result}`, duration: 4000 });
              } catch (error) {
                promptAction.showToast({
                  message: `自检失败: ${error instanceof Error ? error.message : error}`,
                  duration: 4000
                });
              }
            })
          }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)

          this.groupHeader('源仓库')
          Column() {
            Column({ space: 14 }) {
              Text('添加源仓库').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
              TextInput({ placeholder: 'https://cdn.jsdelivr.net/gh/.../index.json', text: this.repoUrlInput })
                .height(50).fontSize(13).backgroundColor(UiTheme.page).borderRadius(14)
                .onChange((value: string) => {
                  this.repoUrlInput = value;
                })
              Flex({ wrap: FlexWrap.Wrap }) {
                Button('添加仓库').attributeModifier(UiStyles.primary).margin({ right: 10, bottom: 8 }).onClick(() => {
                  this.addRepository();
                })
                Button('填入 venera-configs').attributeModifier(UiStyles.secondary).margin({ bottom: 8 }).onClick(() => {
                  this.repoUrlInput = 'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json';
                })
              }.width('100%')
            }.width('100%').padding(20)
            ForEach(this.repositories, (repo: SourceRepository) => {
              Column() {
                Divider().color(UiTheme.line).margin({ left: 80, right: 18 })
                UiSettingsRow({ title: repo.name, subtitle: repo.url, icon: 'globe', value: '浏览', onTap: () => {
                  this.openRepository(repo);
                } })
              }.width('100%')
            }, (repo: SourceRepository) => repo.id)
          }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius).clip(true)

          this.groupHeader(`已安装脚本（${this.installedSources.length}）`)
          if (this.installedSources.length === 0) {
            Text('还没有安装任何 .js 源。先添加仓库，再浏览并安装。')
              .fontSize(13).fontColor(UiTheme.muted).lineHeight(21).width('100%').padding(22)
              .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          } else {
            Column({ space: 12 }) {
              ForEach(this.installedSources, (item: InstalledSource) => {
                Column({ space: 12 }) {
                  Row() {
                    Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).layoutWeight(1)
                    Text(`v${item.version}`).fontSize(12).fontColor(UiTheme.muted)
                  }.width('100%').constraintSize({ minHeight: 32 })
                  Text(`${item.key} · ${item.fileName}`).fontSize(12).fontColor(UiTheme.muted).lineHeight(18)
                  Button('源设置 ›').attributeModifier(UiStyles.secondary).onClick(() => {
                    this.openSourceSettings(item.key);
                  })
                }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
                  .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
              }, (item: InstalledSource) => item.key)
            }.width('100%')
          }

          this.groupHeader(`内置源（${this.builtinSources.length}）`)
          Column({ space: 12 }) {
            ForEach(this.builtinSources, (source: ComicSource) => {
              Column({ space: 12 }) {
                Row({ space: 14 }) {
                  Stack() { UiIcon({ name: 'book', iconSize: 23, color: UiTheme.accent }) }
                    .width(46).height(46).borderRadius(15).backgroundColor(UiTheme.accentSoft)
                  Column({ space: 5 }) {
                    Text(source.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
                    Text(source.key).fontSize(12).fontColor(UiTheme.muted)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(`v${source.version}`).fontSize(12).fontColor(UiTheme.muted)
                }.width('100%').constraintSize({ minHeight: 48 })
                Flex({ wrap: FlexWrap.Wrap }) {
                  this.capabilityRow('搜索', source.supportsSearch)
                  this.capabilityRow('探索', source.supportsExplore)
                  this.capabilityRow('详情', source.loadComicInfo !== undefined)
                  this.capabilityRow('章节', source.loadComicPages !== undefined)
                  this.capabilityRow('分类', source.supportsCategory)
                }.width('100%')
                if (source.account !== undefined) {
                  Divider().color(UiTheme.line)
                  Text(this.loggedKeys.includes(source.key) ? '已登录' : '未登录')
                    .fontSize(12).fontColor(this.loggedKeys.includes(source.key) ? UiTheme.success : UiTheme.muted)
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Button(this.loggedKeys.includes(source.key) ? '退出登录' : '登录')
                      .attributeModifier(this.loggedKeys.includes(source.key) ? UiStyles.secondary : UiStyles.quiet)
                      .enabled(!this.accountBusy).margin({ right: 10, bottom: 8 })
                      .onClick(() => {
                        if (source.isLogged) {
                          this.doLogout(source);
                        } else {
                          this.openLogin(source);
                        }
                      })
                    if (this.loggedKeys.includes(source.key) && source.account.canRelogin?.() === true) {
                      Button('重新登录').attributeModifier(UiStyles.secondary).enabled(!this.accountBusy).margin({ bottom: 8 })
                        .onClick(() => { this.relogin(source); })
                    }
                  }.width('100%')
                }
              }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
                .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
            }, (source: ComicSource) => source.key)
          }.width('100%')
        }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
