import { router } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { Log } from '../foundation/Log';
import { Res } from '../model/Res';
import { BrowserLoginSession } from '../features/BrowserLoginSession';
import { common } from '@kit.AbilityKit';
import { UiTheme, UiIcon, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Original password/cookie/web paths; credentials remain in this page, never route parameters. */
@Entry
@Component
struct SourceAccountPage {
  @State source: ComicSource | undefined = undefined;
  @State loading: boolean = true;
  @State busy: boolean = false;
  @State error: string = '';
  @State status: string = '';
  @State user: string = '';
  @State password: string = '';
  @State cookieValues: string[] = [];
  private disposed: boolean = false;
  private version: number = 0;
  private webOpened: boolean = false;

  onPageShow(): void {
    if (this.webOpened && this.source?.isLogged && !this.disposed) {
      this.webOpened = false;
      Log.audit('account-web-return', '网页登录页面返回', '已确认账号标记，返回源管理；不传递浏览器凭据');
      router.back();
    }
  }

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as Record<string, Object>;
    // Entries from network favourites / collection panel pass 'sourceKey',
    // the source manager passes 'key'. Accept either instead of silently
    // looking up an empty source key.
    const rawKey = params?.['key'];
    const rawSourceKey = params?.['sourceKey'];
    const key = typeof rawKey === 'string' && rawKey.length > 0 ? rawKey
      : (typeof rawSourceKey === 'string' ? rawSourceKey : '');
    if (key.length === 0) {
      this.error = '没有收到漫画源标识，请从源管理或书架重新进入';
      this.loading = false;
      return;
    }
    this.load(key);
  }
  aboutToDisappear(): void { this.disposed = true; this.version++; }
  onBackPress(): boolean { this.disposed = true; this.version++; return false; }

  private async load(key: string): Promise<void> {
    const version = ++this.version;
    try {
      await AppInit.init();
      if (this.disposed || version !== this.version) { return; }
      const source = SourceManager.find(key);
      if (source === undefined) {
        // A stale registry or a not-yet-parsed script is NOT "no account".
        throw new Error('漫画源尚未加载完成，请返回源管理刷新后重试');
      }
      this.source = source;
      if (source.account === undefined) { throw new Error('该源未声明登录功能'); }
      this.cookieValues = (source.account.cookieFields ?? []).map((): string => '');
    } catch (error) { if (!this.disposed) { this.error = String(error); } }
    finally { if (!this.disposed && version === this.version) { this.loading = false; } }
  }

  private async submit(cookies: boolean): Promise<void> {
    const source = this.source;
    if (this.busy || this.disposed || source?.account === undefined) { return; }
    const version = this.version;
    const trace = `account-page-${Date.now()}-${source.key}`;
    this.busy = true; this.error = ''; this.status = '';
    Log.audit(trace, '账号页面提交到达', `路径=${cookies ? 'Cookie' : '密码'}；不记录输入值`);
    try {
      let result: Res<boolean>;
      if (cookies) {
        if (source.account.validateCookies === undefined) { throw new Error('源未声明Cookie校验'); }
        result = await source.account.validateCookies(this.cookieValues.slice(), trace);
      } else {
        if (source.account.login === undefined) { throw new Error('源未声明密码登录'); }
        result = await source.account.login(this.user, this.password, trace);
      }
      if (this.disposed || version !== this.version) { return; }
      if (result.error || result.dataOrNull !== true) {
        this.error = result.error ? '站点登录或持久化失败，请重试' : 'Cookie校验未通过';
        Log.audit(trace, '账号页面提交拒绝', '不显示登录成功，保留本页草稿便于用户修正');
        return;
      }
      this.user = ''; this.password = ''; this.cookieValues = this.cookieValues.map((): string => '');
      this.status = '登录已确认并保存';
      Log.audit(trace, '账号页面提交返回', '成功标记已落盘；清除页面凭据草稿，真实站点能力仍需用户验收');
      router.back();
    } catch (error) {
      if (!this.disposed && version === this.version) { this.error = '登录操作失败，请重试'; }
      Log.audit(trace, '账号页面提交异常', '未输出密码/Cookie或站点原文');
    } finally { if (!this.disposed && version === this.version) { this.busy = false; } }
  }

  private openWeb(): void {
    const key = this.source?.key;
    if (this.busy || this.disposed || key === undefined) { return; }
    this.webOpened = true;
    router.pushUrl({ url: 'pages/SourceWebLoginPage', params: { key: key } }).catch((error: Object) => {
      Log.audit('account-page-web', '网页路由异常', '未打开登录窗口；没有传递账号/密码');
    });
  }

  private async register(): Promise<void> {
    const address = this.source?.account?.registerWebsite;
    if (address === undefined || this.disposed) { return; }
    const trace = `account-register-${Date.now()}`;
    try {
      BrowserLoginSession.httpUrl(address);
      Log.audit(trace, '开户注册链接到达', '仅用户点击时打开系统浏览器；不携带本页账号/Cookie');
      await (AppContext.context as common.UIAbilityContext).startAbility({
        action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: address
      });
      Log.audit(trace, '开户注册链接返回', '系统已处理浏览器打开请求');
    } catch (error) {
      if (!this.disposed) { this.error = '无法打开注册网站'; }
      Log.audit(trace, '开户注册链接拒绝/异常', '网址无效或系统无法处理；未使用不安全scheme');
    }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '账号登录', subtitle: this.source?.name ?? '漫画源账号', onBack: () => { this.disposed = true; this.version++; router.back(); } })
        Column() {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Stack() { UiIcon({ name: 'shield', iconSize: 24, color: UiTheme.accent }) }
                .width(46).height(46).borderRadius(15).backgroundColor(UiTheme.accentSoft)
              Text('凭据仅由你输入').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            }.width('100%')
            Text('请在设备上自行输入账号或Cookie，不要发到聊天。日志只记录步骤与结果，不记录凭据。')
              .fontSize(13).fontColor(UiTheme.secondary).lineHeight(21).width('100%')
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          if (this.loading) { LoadingProgress().width(32).height(32).color(UiTheme.accent).margin({ top: 20 }) }
          if (this.source?.account?.login !== undefined) {
            UiSectionHeading({ title: '账号密码登录' })
            Column({ space: 14 }) {
              TextInput({ placeholder: '账号 / 邮箱', text: this.user }).height(50).fontSize(14)
                .backgroundColor(UiTheme.page).borderRadius(14).enabled(!this.busy)
                .onChange((value: string) => { this.user = value; })
              TextInput({ placeholder: '密码', text: this.password }).type(InputType.Password).height(50).fontSize(14)
                .backgroundColor(UiTheme.page).borderRadius(14).enabled(!this.busy)
                .onChange((value: string) => { this.password = value; })
              Button(this.busy ? '校验中…' : '账号密码登录').attributeModifier(UiStyles.primary)
                .enabled(!this.busy).onClick(() => { this.submit(false); })
            }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
          if (this.source?.account?.validateCookies !== undefined) {
            UiSectionHeading({ title: 'Cookie 登录' })
            Column({ space: 14 }) {
              ForEach(this.source?.account?.cookieFields ?? [], (field: string, index: number) => {
                TextInput({ placeholder: field, text: this.cookieValues[index] ?? '' }).type(InputType.Password)
                  .height(50).fontSize(14).backgroundColor(UiTheme.page).borderRadius(14)
                  .enabled(!this.busy).onChange((value: string) => {
                    const next = this.cookieValues.slice(); next[index] = value; this.cookieValues = next;
                  })
              }, (field: string, index: number) => `${index}-${field}`)
              Button(this.busy ? '校验中…' : '校验Cookie并登录')
                .attributeModifier(this.source?.account?.login !== undefined ? UiStyles.secondary : UiStyles.primary)
                .enabled(!this.busy).onClick(() => { this.submit(true); })
            }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
          if (this.source?.account?.loginWebsite !== undefined) {
            UiSectionHeading({ title: '网页登录' })
            Column({ space: 14 }) {
              Text(`登录站点：${BrowserLoginSession.host(this.source.account.loginWebsite)}`)
                .fontSize(13).fontColor(UiTheme.secondary).lineHeight(20).width('100%')
              Button('网页登录').attributeModifier(UiStyles.secondary).enabled(!this.busy).onClick(() => { this.openWeb(); })
            }.alignItems(HorizontalAlign.Start).width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
          if (this.source?.account?.registerWebsite !== undefined) {
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('打开注册网站').attributeModifier(UiStyles.quiet).enabled(!this.busy).onClick(() => { this.register(); })
            }.width('100%').margin({ top: 20 })
          }
          if (this.source !== undefined && !this.source.account?.canLogin) {
            Text('该源没有可用登录路径').fontSize(14).fontColor(UiTheme.muted).width('100%').padding(20)
          }
          if (this.status.length > 0) {
            Text(this.status).fontSize(13).fontColor(UiTheme.success).width('100%').padding(18)
              .backgroundColor('#E5F7F1').borderRadius(18).margin({ top: 16 })
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(UiTheme.danger).width('100%').padding(18)
              .backgroundColor(UiTheme.dangerSoft).borderRadius(18).margin({ top: 16 })
          }
        }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.width('100%')
    }.width('100%').height('100%').backgroundColor(UiTheme.page).scrollBar(BarState.Off)
  }
}
