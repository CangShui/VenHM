import { url } from '@kit.ArkTS';
import { Database } from '../storage/Database';
import { Log } from '../foundation/Log';
import { BrowserCookie } from '../model/BrowserLogin';

/** Cookie state shared by QuickJS Network.* and @ohos.net.http. */
class CookieEntry {
  name: string = '';
  value: string = '';
  domain: string = '';
  path: string = '/';
  hostOnly: boolean = true;
  secure: boolean = false;
  httpOnly: boolean = false;
  /** 0 denotes a session cookie, otherwise epoch milliseconds. */
  expiresAt: number = 0;
  sameSite: string = '';
}

class CookieChange {
  key: string = '';
  previous?: CookieEntry;
  revision: number = 0;
}
export class CookieImportReceipt {
  changes: CookieChange[] = [];
}

/**
 * The original CookieJarSql was a SQLite store used by Dio's interceptor.
 * @ohos.net.http has no such interceptor, so the same jar is applied by
 * HttpClient explicitly. Script set/delete stay synchronous: executeSync
 * persists them before the QuickJS call returns.
 */
export class CookieJar {
  private static readonly entries: Map<string, CookieEntry> = new Map<string, CookieEntry>();
  private static ready: boolean = false;
  private static sequence: number = 0;
  private static readonly revisions: Map<string, number> = new Map<string, number>();

  static async init(): Promise<void> {
    if (CookieJar.ready) {
      return;
    }
    const rows = await Database.query(
      'SELECT name, value, domain, path, host_only, secure, http_only, expires_at_ms, same_site FROM cookies');
    try {
      while (rows.goToNextRow()) {
        const entry = new CookieEntry();
        entry.name = rows.getString(rows.getColumnIndex('name'));
        entry.value = rows.getString(rows.getColumnIndex('value'));
        entry.domain = rows.getString(rows.getColumnIndex('domain'));
        entry.path = rows.getString(rows.getColumnIndex('path'));
        entry.hostOnly = rows.getLong(rows.getColumnIndex('host_only')) !== 0;
        entry.secure = rows.getLong(rows.getColumnIndex('secure')) !== 0;
        entry.httpOnly = rows.getLong(rows.getColumnIndex('http_only')) !== 0;
        entry.expiresAt = rows.getLong(rows.getColumnIndex('expires_at_ms'));
        entry.sameSite = rows.getString(rows.getColumnIndex('same_site'));
        if (entry.expiresAt === 0 || entry.expiresAt > Date.now()) {
          CookieJar.entries.set(CookieJar.id(entry), entry);
        }
      }
    } finally {
      rows.close();
    }
    CookieJar.ready = true;
  }

  private static id(entry: CookieEntry): string {
    return `${entry.name}\n${entry.domain}\n${entry.path}`;
  }

  private static parsed(input: string): url.URL | null {
    try {
      const parsed = url.URL.parseURL(input);
      if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') ||
          parsed.hostname.length === 0) {
        return null;
      }
      return parsed;
    } catch (error) {
      return null;
    }
  }

  private static domainMatches(host: string, cookie: CookieEntry): boolean {
    const domain = cookie.domain.startsWith('.') ? cookie.domain.substring(1) : cookie.domain;
    return host === domain || (!cookie.hostOnly && host.endsWith(`.${domain}`));
  }

  private static pathMatches(requestPath: string, cookiePath: string): boolean {
    if (cookiePath === '/' || requestPath === cookiePath) {
      return true;
    }
    if (!requestPath.startsWith(cookiePath)) {
      return false;
    }
    return cookiePath.endsWith('/') || requestPath.charAt(cookiePath.length) === '/';
  }

  private static removeEntry(entry: CookieEntry): void {
    Database.rdb.executeSync(
      'DELETE FROM cookies WHERE name = ? AND domain = ? AND path = ?',
      [entry.name, entry.domain, entry.path]);
    CookieJar.entries.delete(CookieJar.id(entry));
    CookieJar.revisions.set(CookieJar.id(entry), ++CookieJar.sequence);
  }

  private static save(entry: CookieEntry): void {
    if (entry.expiresAt !== 0 && entry.expiresAt <= Date.now()) {
      CookieJar.removeEntry(entry);
      return;
    }
    Database.rdb.executeSync(
      'INSERT OR REPLACE INTO cookies (' +
        'name,value,domain,path,host_only,secure,http_only,expires_at_ms,same_site)' +
        ' VALUES (?,?,?,?,?,?,?,?,?)',
      [entry.name, entry.value, entry.domain, entry.path, entry.hostOnly ? 1 : 0,
        entry.secure ? 1 : 0, entry.httpOnly ? 1 : 0, entry.expiresAt, entry.sameSite]);
    CookieJar.entries.set(CookieJar.id(entry), entry);
    CookieJar.revisions.set(CookieJar.id(entry), ++CookieJar.sequence);
  }

  /** Scope/attribute-preserving browser import, atomic before source success callback. */
  static importBrowser(urlText: string, cookies: BrowserCookie[], trace: string): CookieImportReceipt {
    Log.audit(trace, '浏览器Cookie导入到达', `条数=${cookies.length}；名称/值/域名内容不落盘`);
    const request = CookieJar.parsed(urlText);
    if (request === null) { throw new Error('浏览器Cookie来源必须为HTTP(S)'); }
    const prepared: CookieEntry[] = [];
    const keys = new Set<string>();
    for (const raw of cookies) {
      const entry = new CookieEntry();
      entry.name = raw.name; entry.value = raw.value; entry.domain = raw.domain.toLowerCase();
      entry.path = raw.path; entry.hostOnly = raw.hostOnly; entry.secure = raw.secure;
      entry.httpOnly = raw.httpOnly; entry.expiresAt = raw.expiresAt;
      entry.sameSite = raw.sameSite;
      if (!/^[!#$%&'*+\-.^_`|~0-9a-zA-Z]+$/.test(entry.name) || /[\r\n;]/.test(entry.value) ||
        !entry.path.startsWith('/') || /[\r\n;]/.test(entry.path) || !CookieJar.domainMatches(request.hostname.toLowerCase(), entry) ||
        !['', 'Lax', 'Strict', 'None'].includes(entry.sameSite) ||
        !Number.isFinite(entry.expiresAt) || entry.expiresAt < 0 || (entry.secure && request.protocol !== 'https:')) {
        Log.audit(trace, '浏览器Cookie导入拒绝', '格式/域名/安全属性不符合当前来源；未写数据库');
        throw new Error('浏览器Cookie作用域或格式不合法');
      }
      const key = CookieJar.id(entry);
      if (keys.has(key)) { throw new Error('浏览器Cookie存在重复身份'); }
      keys.add(key); prepared.push(entry);
    }
    const receipt = new CookieImportReceipt();
    Database.rdb.beginTransaction();
    try {
      for (const entry of prepared) {
        const change = new CookieChange();
        change.key = CookieJar.id(entry); change.previous = CookieJar.entries.get(change.key);
        receipt.changes.push(change);
        CookieJar.save(entry);
        change.revision = CookieJar.revisions.get(change.key) ?? 0;
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      for (const change of receipt.changes) {
        if (change.previous === undefined) { CookieJar.entries.delete(change.key); }
        else { CookieJar.entries.set(change.key, change.previous); }
        CookieJar.revisions.set(change.key, ++CookieJar.sequence);
      }
      Log.audit(trace, '浏览器Cookie数据库异常', '本次导入事务回滚，内存恢复，不影响其他域会话');
      throw new Error('浏览器Cookie保存失败');
    }
    Log.audit(trace, '浏览器Cookie导入返回', `事务已提交=${receipt.changes.length}条；原生完整属性=${cookies.every((cookie: BrowserCookie) => cookie.metadataComplete !== false)}；保留已导出的作用域/属性，旧系统未知属性不伪称已获取`);
    return receipt;
  }

  static rollbackBrowser(receipt: CookieImportReceipt, trace: string): void {
    let restored = 0; let superseded = 0;
    for (const change of receipt.changes) {
      if (CookieJar.revisions.get(change.key) !== change.revision) { superseded++; continue; }
      if (change.previous !== undefined) { CookieJar.save(change.previous); }
      else {
        const current = CookieJar.entries.get(change.key);
        if (current !== undefined) { CookieJar.removeEntry(current); }
      }
      restored++;
    }
    Log.audit(trace, '浏览器Cookie回滚返回', `恢复本次导入=${restored}；保留之后其他请求更新=${superseded}；不清全局Cookie`);
  }

  /** Cookie attributes for seeding an isolated WebView, including other paths on this host. */
  static browserCookies(urlText: string): BrowserCookie[] {
    const request = CookieJar.parsed(urlText);
    if (request === null) { return []; }
    const values: BrowserCookie[] = [];
    for (const entry of CookieJar.entries.values()) {
      if (!CookieJar.domainMatches(request.hostname.toLowerCase(), entry) ||
        (entry.expiresAt > 0 && entry.expiresAt <= Date.now()) ||
        (entry.secure && request.protocol !== 'https:')) { continue; }
      const cookie = new BrowserCookie();
      cookie.name = entry.name; cookie.value = entry.value; cookie.domain = entry.domain; cookie.path = entry.path;
      cookie.hostOnly = entry.hostOnly; cookie.secure = entry.secure; cookie.httpOnly = entry.httpOnly;
      cookie.expiresAt = entry.expiresAt; cookie.sameSite = entry.sameSite; values.push(cookie);
    }
    return values;
  }

  private static accepted(cookie: CookieEntry, request: url.URL): boolean {
    const hostname = request.hostname.toLowerCase();
    return CookieJar.domainMatches(hostname, cookie) &&
      CookieJar.pathMatches(request.pathname || '/', cookie.path) &&
      (!cookie.secure || request.protocol === 'https:') &&
      (cookie.expiresAt === 0 || cookie.expiresAt > Date.now());
  }

  private static matching(request: url.URL): CookieEntry[] {
    const found: CookieEntry[] = [];
    for (const entry of CookieJar.entries.values()) {
      if (entry.expiresAt !== 0 && entry.expiresAt <= Date.now()) {
        CookieJar.removeEntry(entry);
      } else if (CookieJar.accepted(entry, request)) {
        found.push(entry);
      }
    }
    found.sort((left: CookieEntry, right: CookieEntry): number =>
      right.path.length - left.path.length || right.domain.length - left.domain.length);
    return found;
  }

  /** Upstream Network.setCookies(url, cookies): synchronous and persistent. */
  static set(urlText: string, cookies: Object[]): void {
    const request = CookieJar.parsed(urlText);
    if (request === null) {
      throw new Error('Cookie URL must be absolute http(s)');
    }
    const host = request.hostname.toLowerCase();
    for (let i = 0; i < cookies.length; i++) {
      const raw = cookies[i] as Record<string, Object>;
      if (typeof raw['name'] !== 'string' || typeof raw['value'] !== 'string') {
        continue;
      }
      const entry = new CookieEntry();
      entry.name = raw['name'] as string;
      entry.value = raw['value'] as string;
      const requestedDomain = raw['domain'];
      if (typeof requestedDomain === 'string' && requestedDomain.length > 0) {
        const domain = (requestedDomain as string).toLowerCase();
        const plain = domain.startsWith('.') ? domain.substring(1) : domain;
        if (!/^[a-z0-9.-]+$/.test(plain) || plain.length === 0 ||
            (plain.indexOf('.') < 0 && plain !== 'localhost')) {
          throw new Error('Cookie显式域名格式无效');
        }
        // The trusted source API permits explicit cross-domain Cookie ownership
        // (e-hentai/exhentai is an upstream example). Browser imports stay strict.
        if (host !== plain && !host.endsWith(`.${plain}`)) {
          Log.audit('source-cookie-explicit-domain', '源Cookie指定域', '脚本显式指定其他域，按原版API保存；不用于浏览器导入路径');
        }
        entry.domain = domain;
        // An explicitly supplied Domain denotes a domain cookie; a leading dot
        // is optional in RFC6265. No Domain supplied remains host-only.
        entry.hostOnly = false;
      } else {
        entry.domain = host;
      }
      // Upstream's JS callback only copies name/value/domain and uses '/'.
      CookieJar.save(entry);
    }
  }

  /** Upstream Network.getCookies(url), including metadata for callers. */
  static get(urlText: string): Object[] {
    const request = CookieJar.parsed(urlText);
    if (request === null) {
      return [];
    }
    const result: Object[] = [];
    for (const entry of CookieJar.matching(request)) {
      const record: Record<string, Object> = {};
      record['name'] = entry.name;
      record['value'] = entry.value;
      record['domain'] = entry.domain;
      record['path'] = entry.path;
      record['secure'] = entry.secure;
      record['httpOnly'] = entry.httpOnly;
      record['session'] = entry.expiresAt === 0;
      if (entry.expiresAt !== 0) {
        record['expires'] = entry.expiresAt;
      }
      result.push(record);
    }
    return result;
  }

  /** CookieJarSql.deleteUri deletes the host and eligible parent domains. */
  static delete(urlText: string): void {
    const request = CookieJar.parsed(urlText);
    if (request === null) {
      return;
    }
    const host = request.hostname.toLowerCase();
    for (const entry of CookieJar.entries.values()) {
      if (CookieJar.domainMatches(host, entry)) {
        CookieJar.removeEntry(entry);
      }
    }
  }

  /** Scoped cleanup for owned diagnostics; unlike delete(url), does not erase a host's other cookies. */
  static deleteNamed(urlText: string, names: string[], trace: string): void {
    const request = CookieJar.parsed(urlText);
    if (request === null) { throw new Error('定向Cookie删除URL无效'); }
    let removed = 0;
    for (const entry of CookieJar.entries.values()) {
      if (CookieJar.domainMatches(request.hostname.toLowerCase(), entry) && names.includes(entry.name)) {
        CookieJar.removeEntry(entry); removed++;
      }
    }
    Log.audit(trace, 'Cookie定向删除', `只删除指定名称=${removed}；不清空当前域其他账号Cookie`);
  }

  /** Cookie header for @ohos.net.http; one best match per name. */
  static header(urlText: string): string {
    const request = CookieJar.parsed(urlText);
    if (request === null) {
      return '';
    }
    const selected: Map<string, CookieEntry> = new Map<string, CookieEntry>();
    for (const entry of CookieJar.matching(request)) {
      const previous = selected.get(entry.name);
      if (previous === undefined || entry.path.length > previous.path.length ||
          (entry.path.length === previous.path.length && entry.hostOnly && !previous.hostOnly)) {
        selected.set(entry.name, entry);
      }
    }
    const pairs: string[] = [];
    for (const entry of selected.values()) {
      pairs.push(`${entry.name}=${entry.value}`);
    }
    return pairs.join('; ');
  }

  /** Persist raw Set-Cookie values, including non-2xx responses. */
  static receive(urlText: string, headers: Object): void {
    const request = CookieJar.parsed(urlText);
    if (request === null || headers === null || headers === undefined) {
      return;
    }
    const record = headers as Record<string, Object>;
    for (const key of Object.keys(record)) {
      if (key.toLowerCase() !== 'set-cookie') {
        continue;
      }
      const raw = record[key];
      if (Array.isArray(raw)) {
        for (const line of raw as string[]) {
          CookieJar.parseSetCookie(request, String(line));
        }
      } else if (typeof raw === 'string') {
        // A response adapter may have combined multiple Set-Cookie fields.
        // Split only before a cookie name=; the comma in Expires is retained.
        for (const line of (raw as string).split(/,(?=\s*[^;,=\s]+\s*=)/)) {
          CookieJar.parseSetCookie(request, line.trim());
        }
      }
    }
  }

  /** Offline regression using reserved .invalid hosts; no network or real accounts. */
  static async selfTest(): Promise<void> {
    const main = 'https://test.example.invalid/a';
    const other = 'https://unrelated.invalid/';
    try {
      const hostOnly: Record<string, Object> = {};
      hostOnly['name'] = 'host_only_probe';
      hostOnly['value'] = 'local';
      const domain: Record<string, Object> = {};
      domain['name'] = 'domain_probe';
      domain['value'] = 'shared';
      domain['domain'] = '.example.invalid';
      CookieJar.set(main, [hostOnly, domain]);
      if (CookieJar.get(main).length !== 2 ||
          CookieJar.header('https://sub.example.invalid/a').indexOf('domain_probe=shared') < 0 ||
          CookieJar.header('https://sub.example.invalid/a').indexOf('host_only_probe=') >= 0 ||
          CookieJar.header('https://notexample.invalid/a').indexOf('domain_probe=') >= 0) {
        throw new Error('Cookie host/domain scope failed');
      }
      const response: Record<string, Object> = {};
      response['Set-Cookie'] = [
        'scoped=ok; Path=/a; Secure; Expires=Wed, 21 Oct 2035 07:28:00 GMT',
        'erased=gone; Path=/a; Expires=Wed, 21 Oct 2035 07:28:00 GMT; Max-Age=0'
      ];
      CookieJar.receive(main, response);
      if (CookieJar.header('https://test.example.invalid/a/x').indexOf('scoped=ok') < 0 ||
          CookieJar.header('http://test.example.invalid/a/x').indexOf('scoped=ok') >= 0 ||
          CookieJar.header('https://test.example.invalid/abc').indexOf('scoped=ok') >= 0 ||
          CookieJar.header('https://test.example.invalid/a/x').indexOf('erased=') >= 0) {
        throw new Error('Cookie path/secure/expiry rule failed');
      }
      const rows = await Database.query(
        'SELECT COUNT(*) AS c FROM cookies WHERE name = ? AND domain = ?',
        ['domain_probe', '.example.invalid']);
      try {
        if (!rows.goToFirstRow() || rows.getLong(rows.getColumnIndex('c')) !== 1) {
          throw new Error('Cookie persistence row missing');
        }
      } finally {
        rows.close();
      }
      // Force a cold-cache reload from SQLite before scripts start; checking
      // the SQL row alone would not prove that a restart can restore cookies.
      CookieJar.entries.clear();
      CookieJar.ready = false;
      await CookieJar.init();
      if (CookieJar.header(main).indexOf('host_only_probe=local') < 0 ||
          CookieJar.header('https://sub.example.invalid/a').indexOf('domain_probe=shared') < 0) {
        throw new Error('Cookie reload from SQLite lost a saved cookie');
      }
      const keep: Record<string, Object> = {};
      keep['name'] = 'unrelated_probe';
      keep['value'] = 'kept';
      CookieJar.set(other, [keep]);
      CookieJar.delete(main);
      if (CookieJar.get(main).length !== 0 || CookieJar.get(other).length !== 1) {
        throw new Error('Cookie URL deletion touched unrelated host');
      }
    } finally {
      if (!CookieJar.ready) {
        await CookieJar.init();
      }
      CookieJar.delete(main);
      CookieJar.delete(other);
    }
  }

  private static parseSetCookie(request: url.URL, line: string): void {
    const tokens = line.split(';');
    const first = tokens[0];
    const separator = first.indexOf('=');
    if (separator <= 0) {
      return;
    }
    const entry = new CookieEntry();
    entry.name = first.substring(0, separator).trim();
    entry.value = first.substring(separator + 1).trim();
    entry.domain = request.hostname.toLowerCase();
    const path = request.pathname || '/';
    entry.path = path.lastIndexOf('/') > 0 ? path.substring(0, path.lastIndexOf('/')) : '/';
    let maxAge: number | undefined = undefined;
    for (let i = 1; i < tokens.length; i++) {
      const token = tokens[i].trim();
      const divider = token.indexOf('=');
      const name = (divider < 0 ? token : token.substring(0, divider)).trim().toLowerCase();
      const value = divider < 0 ? '' : token.substring(divider + 1).trim();
      if (name === 'domain' && value.length > 0) {
        const domain = value.toLowerCase().replace(/^\./, '');
        const host = request.hostname.toLowerCase();
        if ((host !== domain && !host.endsWith(`.${domain}`)) ||
            (domain.indexOf('.') < 0 && domain !== 'localhost')) {
          Log.warn('CookieJar', 'Ignored unrelated Set-Cookie domain');
          return;
        }
        entry.domain = `.${domain}`;
        entry.hostOnly = false;
      } else if (name === 'path' && value.startsWith('/')) {
        entry.path = value;
      } else if (name === 'max-age') {
        const seconds = parseInt(value, 10);
        if (!isNaN(seconds)) {
          maxAge = seconds;
        }
      } else if (name === 'expires') {
        const millis = Date.parse(value);
        if (!isNaN(millis)) {
          entry.expiresAt = millis;
        }
      } else if (name === 'secure') {
        entry.secure = true;
      } else if (name === 'httponly') {
        entry.httpOnly = true;
      } else if (name === 'samesite') {
        const normalized = value.toLowerCase();
        entry.sameSite = normalized === 'strict' ? 'Strict' : normalized === 'lax' ? 'Lax' :
          normalized === 'none' ? 'None' : '';
      }
    }
    if (maxAge !== undefined) {
      entry.expiresAt = maxAge <= 0 ? Date.now() - 1 : Date.now() + maxAge * 1000;
    }
    CookieJar.save(entry);
  }
}
