import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { SourceManager } from '../source/SourceManager';
import { ComicSource } from '../source/ComicSource';
import { BrowserLoginSession } from '../features/BrowserLoginSession';
import { Log } from '../foundation/Log';
import { HttpClient } from '../network/HttpClient';
import { UiTheme } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Browser login uses original checkStatus(url,title) and awaits all session writes/callbacks. */
@Entry
@Component
struct SourceWebLoginPage {
  @State source: ComicSource | undefined = undefined;
  @State initialUrl: string = '';
  @State host: string = '';
  @State ready: boolean = false;
  @State checking: boolean = false;
  @State error: string = '';
  @State status: string = '请在网页中自行完成登录';
  private controller: webview.WebviewController = new webview.WebviewController();
  private trace: string = '';
  private version: number = 0;
  private disposed: boolean = false;
  private dirty: boolean = false;
  private sessionReady: boolean = false;

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    this.disposed = false;
    this.trace = `web-login-${Date.now()}`;
    const params = router.getParams() as Record<string, Object>;
    const key = typeof params?.['key'] === 'string' ? params['key'] as string : '';
    AppInit.init().then(() => {
      if (this.disposed) { return; }
      const source = SourceManager.find(key);
      const account = source?.account;
      if (source === undefined || account?.loginWebsite === undefined || account.checkLoginStatus === undefined ||
        account.finishWebLogin === undefined) { throw new Error('源未声明完整网页登录契约'); }
      this.source = source; this.initialUrl = account.loginWebsite;
      BrowserLoginSession.httpUrl(this.initialUrl);
      BrowserLoginSession.reserve(this.initialUrl, this.trace);
      this.host = BrowserLoginSession.host(this.initialUrl);
      this.ready = true;
      Log.audit(this.trace, '网页登录入口', `源=${source.key}；隔离浏览器准备；URL/账号不落盘`);
    }).catch((error: Object) => {
      if (!this.disposed) { this.error = '网页登录初始化失败，源配置可能无效'; }
      Log.audit(this.trace, '网页登录入口异常', '未进入会话导出；不记录网页URL与正文');
    });
  }

  private attach(): void {
    if (this.disposed) { return; }
    try {
      this.controller.setCustomUserAgent(HttpClient.defaultUserAgent());
      BrowserLoginSession.begin(this.initialUrl, this.trace);
      this.sessionReady = true;
    } catch (error) { this.error = '隔离会话准备失败，请退出后重试'; }
  }

  private cancel(): void {
    this.disposed = true; this.version++;
    BrowserLoginSession.end(this.trace);
    Log.audit(this.trace, '网页登录取消/退出', '不继续导出或标记登录；不清除其他账号/正常浏览器Cookie');
  }
  aboutToDisappear(): void { this.cancel(); }
  onBackPress(): boolean { this.cancel(); return false; }

  private current(version: number, url: string, title: string): boolean {
    if (this.disposed || version !== this.version) { return false; }
    try { return this.controller.getUrl() === url && this.controller.getTitle() === title; }
    catch (error) { return false; }
  }

  private requestCheck(): void {
    if (this.disposed || !this.sessionReady) { return; }
    this.dirty = true; this.version++;
    if (!this.checking) { this.runCheck(); }
  }

  private async runCheck(): Promise<void> {
    this.checking = true;
    try {
      while (this.dirty && !this.disposed) {
        this.dirty = false;
        const version = this.version;
        const url = this.controller.getUrl();
        const title = this.controller.getTitle();
        const account = this.source?.account;
        if (account?.checkLoginStatus === undefined || account.finishWebLogin === undefined) { throw new Error('网页登录契约丢失'); }
        BrowserLoginSession.httpUrl(url);
        this.host = BrowserLoginSession.host(url);
        if (!await account.checkLoginStatus(url, title, this.trace) || !this.current(version, url, title)) { continue; }
        this.status = '站点条件已满足，正在保存会话…';
        const snapshot = await BrowserLoginSession.capture(this.controller, url, title, this.trace);
        if (!this.current(version, url, title)) { continue; }
        const result = await account.finishWebLogin(snapshot, (): boolean => this.current(version, url, title), this.trace);
        if (this.disposed) { return; }
        if (result.error || result.dataOrNull !== true) {
          this.error = result.errorMessage ?? '当前页面还未满足登录条件';
          this.status = '会话未确认，请检查网页后重试';
          continue;
        }
        this.status = '登录已确认并保存';
        Log.audit(this.trace, '网页登录UI返回', '会话/回调/账号标记全部确认；关闭当前登录页');
        BrowserLoginSession.end(this.trace);
        router.back();
        return;
      }
    } catch (error) {
      if (!this.disposed) { this.error = '会话读取或校验失败，未确认登录；请重试'; this.status = '需要重试或旧系统Cookie桥适配'; }
      Log.audit(this.trace, '网页登录校验异常', '没有打印Cookie/localStorage/URL/标题；不冒充登录成功');
    } finally {
      if (!this.disposed) {
        this.checking = false;
        if (this.dirty) { this.runCheck(); }
      }
    }
  }

  build() {
    Column() {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Button('取消').attributeModifier(UiStyles.secondary).onClick(() => { this.cancel(); router.back(); })
          Text(this.source?.name ?? '网页登录').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(`当前站点：${this.host}`).fontSize(12).fontColor(UiTheme.secondary).margin({ right: 12, bottom: 8 })
          Button('重新检查').attributeModifier(UiStyles.quiet).margin({ bottom: 8 }).enabled(!this.checking)
            .onClick(() => { this.error = ''; this.requestCheck(); })
        }.width('100%')
        Text(this.status).fontSize(12).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
        if (this.error.length > 0) {
          Text(this.error).fontColor(UiTheme.danger).fontSize(12).lineHeight(20).width('100%').padding(12)
            .backgroundColor(UiTheme.dangerSoft).borderRadius(14)
        }
      }.padding({ left: 20, right: 20, top: 12, bottom: 16 }).width('100%').backgroundColor(UiTheme.page)
      if (this.ready) {
        Web({ src: this.initialUrl, controller: this.controller, incognitoMode: true })
          .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
          .mixedMode(MixedMode.None).layoutWeight(1).width('100%')
          .onControllerAttached(() => { this.attach(); })
          .onPageEnd(() => { this.requestCheck(); })
          .onTitleReceive(() => { this.requestCheck(); })
          .onUrlLoadIntercept((event) => {
            if (event === undefined) { return false; }
            try {
              const address = typeof event.data === 'string' ? event.data : event.data.getRequestUrl();
              BrowserLoginSession.httpUrl(address); return false;
            }
            catch (error) {
              Log.audit(this.trace, '网页导航拒绝', '拒绝非HTTP(S)/含凭据URI；不打开外部程序');
              return true;
            }
          })
      } else { LoadingProgress().width(32).height(32) }
    }.width('100%').height('100%')
  }
}
