import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import { url } from '@kit.ArkTS';
import { BrowserCookie, BrowserLoginSnapshot } from '../model/BrowserLogin';
import { CookieJar } from '../network/CookieJar';
import { Log } from '../foundation/Log';

/**
 * API23 contract absent from the installed API21 compile SDK. These explicit
 * facade types preserve the real runtime metadata API on newer devices; they
 * do not invent fields or turn API21 name/value export into full metadata.
 * Reference: https://github.com/openharmony/interface_sdk-js/blob/master/api/@ohos.web.webview.d.ts
 */
interface BrowserCookie23 {
  domain: string;
  path: string;
  name: string;
  value: string;
  expiresDate: string;
  isSessionCookie: boolean;
  isHttpOnly: boolean;
  isSecure: boolean;
  samesitePolicy: number;
}

interface BrowserCookieManager23 {
  fetchAllCookies(incognito: boolean): Promise<BrowserCookie23[]>;
}

// Official WebHttpCookieSameSitePolicy values, introduced with API23.
enum BrowserSameSitePolicy23 { NONE = 0, LAX = 1, STRICT = 2 }

/** One isolated incognito login at a time; no global normal-profile Cookie deletion. */
export class BrowserLoginSession {
  private static active: string = '';
  private static owned: BrowserCookie[] = [];
  private static prepared: boolean = false;

  static reserve(initialUrl: string, trace: string): void {
    BrowserLoginSession.httpUrl(initialUrl);
    if (BrowserLoginSession.active.length > 0 && BrowserLoginSession.active !== trace) {
      throw new Error('已有网页登录窗口，请先退出');
    }
    BrowserLoginSession.active = trace;
  }

  static httpUrl(text: string): url.URL {
    const value = url.URL.parseURL(text);
    if (!['https:', 'http:'].includes(value.protocol) || value.hostname.length === 0 ||
      value.username.length > 0 || value.password.length > 0) { throw new Error('登录网址必须为不含账号密码的HTTP(S)地址'); }
    return value;
  }

  static host(text: string): string {
    try { return BrowserLoginSession.httpUrl(text).hostname; } catch (error) { return ''; }
  }

  private static matches(host: string, cookie: BrowserCookie): boolean {
    const domain = cookie.domain.replace(/^\./, '').toLowerCase();
    return host === domain || (!cookie.hostOnly && host.endsWith(`.${domain}`));
  }

  private static pairs(header: string): Map<string, string> {
    const result = new Map<string, string>();
    for (const part of header.split(';')) {
      const at = part.indexOf('=');
      if (at <= 0) { continue; }
      const name = part.substring(0, at).trim();
      if (!result.has(name)) { result.set(name, part.substring(at + 1).trim()); }
    }
    return result;
  }

  /** API21/22 compatibility with upstream routing/webview.dart's name/value/domain transfer.
   * Lifetime/SameSite cannot be exported by those APIs; do not report this as complete metadata.
   */
  private static legacyCookies(parsed: url.URL, documentCookie: string, trace: string): BrowserCookie[] {
    const header = webview.WebCookieManager.fetchCookieSync(parsed.toString(), true);
    const visible = BrowserLoginSession.pairs(documentCookie);
    const pairs = BrowserLoginSession.pairs(header);
    const cookies: BrowserCookie[] = [];
    const candidates = ['/'];
    const path = parsed.pathname || '/';
    for (let i = 1; i <= path.length; i++) {
      if (i === path.length || path[i] === '/') {
        const prefix = path.substring(0, i);
        if (!candidates.includes(prefix)) { candidates.push(prefix); }
        if (i < path.length && !candidates.includes(`${prefix}/`)) { candidates.push(`${prefix}/`); }
      }
    }
    const cached = new Map<string, Map<string, string>>();
    const lookup = (address: string): Map<string, string> => {
      let values = cached.get(address);
      if (values !== undefined) { return values; }
      try { values = BrowserLoginSession.pairs(webview.WebCookieManager.fetchCookieSync(address, true)); }
      catch (error) { values = new Map<string, string>(); }
      cached.set(address, values);
      return values;
    };
    pairs.forEach((value: string, name: string) => {
      const cookie = new BrowserCookie();
      cookie.name = name; cookie.value = value; cookie.domain = parsed.hostname.toLowerCase();
      cookie.hostOnly = true; cookie.metadataComplete = false;
      // A matching header at a shorter path confirms applicability there. This
      // avoids blindly converting an /auth-only cookie into a root cookie.
      cookie.path = path;
      for (const candidate of candidates) {
        const address = `${parsed.protocol}//${parsed.host}${candidate}`;
        if (lookup(address).get(name) === value) { cookie.path = candidate; break; }
      }
      cookie.httpOnly = visible.get(name) !== value;
      cookie.secure = parsed.protocol === 'https:' &&
        lookup(`http://${parsed.host}${cookie.path}`).get(name) !== value;
      const labels = parsed.hostname.split('.');
      if (!/^[0-9.]+$/.test(parsed.hostname) && !parsed.hostname.includes(':')) {
        for (let skip = 1; labels.length - skip >= 2; skip++) {
          const parent = labels.slice(skip).join('.');
          const port = parsed.port.length > 0 ? `:${parsed.port}` : '';
          const root = `${parsed.protocol}//${parent}${port}${cookie.path}`;
          const sibling = `${parsed.protocol}//hm-cookie-scope-probe.${parent}${port}${cookie.path}`;
          if (lookup(root).get(name) === value && lookup(sibling).get(name) === value) {
            cookie.domain = `.${parent}`; cookie.hostOnly = false;
          } else { break; }
        }
        if (cookie.hostOnly && lookup(`${parsed.protocol}//hm-cookie-scope-probe.${parsed.host}${cookie.path}`).get(name) === value) {
          cookie.domain = `.${parsed.hostname}`; cookie.hostOnly = false;
        }
      }
      cookies.push(cookie);
    });
    Log.audit(trace, '旧系统Cookie兼容导出', `name/value已导出=${cookies.length}；Domain/Path/Secure/HttpOnly观察推导；过期/SameSite未知，使用原版session兼容语义，不宣称完整属性`);
    return cookies;
  }

  private static wire(cookie: BrowserCookie, erase: boolean): string {
    let value = `${cookie.name}=${erase ? '' : cookie.value}; Path=${cookie.path}`;
    if (!cookie.hostOnly) { value += `; Domain=${cookie.domain}`; }
    if (erase) { value += '; Max-Age=0'; }
    else if (cookie.expiresAt > 0) { value += `; Expires=${new Date(cookie.expiresAt).toUTCString()}`; }
    if (cookie.secure) { value += '; Secure'; }
    if (cookie.httpOnly) { value += '; HttpOnly'; }
    if (cookie.sameSite.length > 0) { value += `; SameSite=${cookie.sameSite}`; }
    return value;
  }

  static begin(initialUrl: string, trace: string): void {
    BrowserLoginSession.httpUrl(initialUrl);
    BrowserLoginSession.reserve(initialUrl, trace);
    if (BrowserLoginSession.prepared) { return; }
    BrowserLoginSession.owned = [];
    Log.audit(trace, '浏览器会话到达', '使用incognito隔离空间；不读取/清空正常浏览器配置');
    try {
      // This is the app's single-purpose, exclusively reserved incognito login profile.
      webview.WebCookieManager.clearAllCookiesSync(true);
      for (const cookie of CookieJar.browserCookies(initialUrl)) {
        const target = `${cookie.secure ? 'https' : BrowserLoginSession.httpUrl(initialUrl).protocol.slice(0, -1)}://` +
          `${cookie.domain.replace(/^\./, '')}${cookie.path}`;
        webview.WebCookieManager.configCookieSync(target, BrowserLoginSession.wire(cookie, false), true, true);
        BrowserLoginSession.owned.push(cookie);
      }
      BrowserLoginSession.prepared = true;
      Log.audit(trace, '浏览器会话准备返回', `只注入当前站点Cookie=${BrowserLoginSession.owned.length}；属性和值不落盘`);
    } catch (error) {
      BrowserLoginSession.end(trace);
      throw new Error('网页登录会话准备失败');
    }
  }

  static parseStorage(result: string, expectedUrl: string, expectedTitle: string): Record<string, Object> {
    let value: Object = JSON.parse(result) as Object;
    if (typeof value === 'string') { value = JSON.parse(value) as Object; }
    if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('网页存储读取格式不正确'); }
    const data = value as Record<string, Object>;
    if (data['url'] !== expectedUrl || data['title'] !== expectedTitle) { throw new Error('读取期间网页已变化'); }
    const storage = data['storage'];
    if (storage === null || storage === undefined || typeof storage !== 'object' || Array.isArray(storage)) {
      throw new Error('网页localStorage格式错误');
    }
    const map = storage as Record<string, Object>;
    for (const key of Object.keys(map)) { if (typeof map[key] !== 'string') { throw new Error('网页存储值必须为字符串'); } }
    return map;
  }

  static async capture(controller: webview.WebviewController, pageUrl: string, title: string, trace: string):
    Promise<BrowserLoginSnapshot> {
    if (BrowserLoginSession.active !== trace) { throw new Error('网页登录会话已关闭'); }
    const parsed = BrowserLoginSession.httpUrl(pageUrl);
    const result = await controller.runJavaScript(
      'JSON.stringify({url:location.href,title:document.title,storage:Object.fromEntries(' +
      'Array.from({length:localStorage.length},(_,i)=>localStorage.key(i)).map(k=>[k,localStorage.getItem(k)])),cookie:document.cookie})');
    if (BrowserLoginSession.active !== trace) { throw new Error('网页登录会话已关闭'); }
    const snapshot = new BrowserLoginSnapshot();
    snapshot.url = pageUrl; snapshot.title = title;
    snapshot.localStorage = BrowserLoginSession.parseStorage(result, pageUrl, title);
    if (deviceInfo.sdkApiVersion < 23) {
      let body: Object = JSON.parse(result) as Object;
      if (typeof body === 'string') { body = JSON.parse(body) as Object; }
      const documentCookie = (body as Record<string, Object>)['cookie'];
      snapshot.cookies = BrowserLoginSession.legacyCookies(parsed,
        typeof documentCookie === 'string' ? documentCookie : '', trace);
      snapshot.cookieMetadataComplete = false;
      BrowserLoginSession.owned.push(...snapshot.cookies);
    } else {
      const manager: BrowserCookieManager23 = webview.WebCookieManager as Object as BrowserCookieManager23;
      if (typeof manager.fetchAllCookies !== 'function') {
        throw new Error('当前ArkWeb缺少API23 Cookie属性导出；未将兼容name/value伪称完整属性');
      }
      const cookies: BrowserCookie23[] = await manager.fetchAllCookies(true);
      if (BrowserLoginSession.active !== trace) { throw new Error('网页登录会话已关闭'); }
      for (const raw of cookies) {
        const cookie = new BrowserCookie();
        cookie.name = raw.name; cookie.value = raw.value; cookie.domain = raw.domain;
        cookie.path = raw.path; cookie.hostOnly = !raw.domain.startsWith('.');
        cookie.secure = raw.isSecure; cookie.httpOnly = raw.isHttpOnly;
        cookie.expiresAt = raw.isSessionCookie ? 0 : Date.parse(raw.expiresDate);
        cookie.sameSite = raw.samesitePolicy === BrowserSameSitePolicy23.STRICT ? 'Strict' :
          raw.samesitePolicy === BrowserSameSitePolicy23.LAX ? 'Lax' : 'None';
        if (!BrowserLoginSession.matches(parsed.hostname.toLowerCase(), cookie)) { continue; }
        if (!raw.isSessionCookie && (!Number.isFinite(cookie.expiresAt) || cookie.expiresAt <= 0)) {
          throw new Error('无法确认网页Cookie到期时间；未伪造会话Cookie');
        }
        if ((cookie.secure && parsed.protocol !== 'https:') || (cookie.expiresAt > 0 && cookie.expiresAt <= Date.now())) { continue; }
        BrowserLoginSession.owned.push(cookie);
        snapshot.cookies.push(cookie);
      }
    }
    if (BrowserLoginSession.active !== trace) { throw new Error('网页登录会话已关闭'); }
    Log.audit(trace, '浏览器会话快照返回', `当前站点Cookie=${snapshot.cookies.length}；完整属性=${snapshot.cookieMetadataComplete}；存储项=${Object.keys(snapshot.localStorage).length}；不记录凭据内容`);
    return snapshot;
  }

  static end(trace: string): void {
    if (BrowserLoginSession.active !== trace) { return; }
    let cleaned = 0;
    for (const cookie of BrowserLoginSession.owned) {
      try {
        const target = `${cookie.secure ? 'https' : 'http'}://${cookie.domain.replace(/^\./, '')}${cookie.path}`;
        webview.WebCookieManager.configCookieSync(target, BrowserLoginSession.wire(cookie, true), true, true);
        cleaned++;
      } catch (error) { Log.audit(trace, '浏览器会话清理异常', '仅尝试删除本次incognito会话Cookie；未清除其他源/正常配置'); }
    }
    BrowserLoginSession.owned = [];
    let isolatedCleared = false;
    try { webview.WebCookieManager.clearAllCookiesSync(true); isolatedCleared = true; }
    catch (error) { Log.audit(trace, '隔离空间清理异常', '未触碰正常浏览器；后续登录初始化须再次清理'); }
    BrowserLoginSession.active = '';
    BrowserLoginSession.prepared = false;
    Log.audit(trace, '浏览器会话退出', `本次Cookie删除尝试成功=${cleaned}；独占空间清理确认=${isolatedCleared}；普通配置/HTTP jar已确认账号不删除`);
  }
}
