import { SourceDataStore } from '../source/SourceDataStore';
import { ComicSourceParser } from '../source/JsComicSource';
import { SourceManager } from '../source/SourceManager';
import { JsEngine } from '../source/JsEngine';
import { Settings } from '../foundation/Settings';
import { CookieJar } from '../network/CookieJar';
import { HttpClient, HttpRequestOptions } from '../network/HttpClient';
import { http } from '@kit.NetworkKit';
import { Log } from '../foundation/Log';

/** Opt-in synthetic auth fixture, never installed as a real source and never a real-login PASS. */
export class SourceAccountUsability {
  static readonly key: string = '__HM_AUTH_USABILITY__';
  private static readonly owner: string = 'hm-auth-fixture-v1';
  private static readonly flag: string = 'sourceAccountUsabilityEnabled';
  private static readonly base: string = 'http://127.0.0.1:29091';

  private static async register(name: string): Promise<void> {
    if (!/^hm_auth_[0-9]+_[0-9]+$/.test(name)) { throw new Error('合成账号Cookie标识不合法'); }
    if (SourceManager.find(SourceAccountUsability.key) !== undefined) { return; }
    const verify = JSON.stringify(`${SourceAccountUsability.base}/auth/verify?name=${name}`);
    const login = JSON.stringify(`${SourceAccountUsability.base}/auth/login?name=${name}`);
    const done = JSON.stringify(`${SourceAccountUsability.base}/auth/done?name=${name}`);
    const key = JSON.stringify(SourceAccountUsability.key);
    const cookieName = JSON.stringify(name);
    const script = `class HMAuthFixture extends ComicSource { key=${key};name="本机合成账号桥验收";version="1.0.0";` +
      `account={loginWithCookies:{fields:["合成Cookie（输入synthetic）"],validate:async(values)=>{` +
      `if(values.length!==1)return false;Network.setCookies(${verify},[new Cookie({name:${cookieName},value:values[0]})]);` +
      `return (await Network.get(${verify})).status===200;}},` +
      `loginWithWebview:{url:${login},checkStatus:(u,t)=>u===${done}&&t==="Synthetic auth done",` +
      `onLoginSuccess:async()=>{if(this.loadData("_localStorage")?.probeToken!=="synthetic-token")throw Error("storage mismatch");` +
      `if(!Network.getCookies(${verify}).some(c=>c.name===${cookieName}&&c.httpOnly))throw Error("httpOnly mismatch");` +
      `if((await Network.get(${verify})).status!==200)throw Error("HTTP cookie mismatch");` +
      `this.saveData("verified",true);}},logout:()=>{this.deleteData("_localStorage");this.deleteData("verified");}};}`;
    const source = await ComicSourceParser.parse(script, '<synthetic-account-fixture>');
    const logout = source.account?.logout;
    if (source.account !== undefined && logout !== undefined) {
      source.account.logout = async (): Promise<void> => {
        await logout();
        CookieJar.deleteNamed(SourceAccountUsability.base, [name], 'auth-fixture-logout');
      };
    }
    SourceManager.register(source);
  }

  static async prepare(): Promise<string> {
    const trace = `auth-fixture-${Date.now()}`;
    const options = new HttpRequestOptions(); options.traceId = trace; options.retries = 0;
    options.connectTimeoutMs = 3000; options.readTimeoutMs = 3000;
    const health = await HttpClient.request(`${SourceAccountUsability.base}/health`, http.RequestMethod.GET, options);
    if (!health.ok || health.body !== '{"fixture":"venera-hm-image-v1"}') { throw new Error('需要本机CLI测试服务器，未注册合成账号'); }
    await SourceDataStore.preload(SourceAccountUsability.key);
    const previousOwner = SourceDataStore.get(SourceAccountUsability.key, '_owner');
    if (previousOwner !== null && previousOwner !== SourceAccountUsability.owner) { throw new Error('拒绝覆盖非本验收源数据'); }
    if (SourceManager.find(SourceAccountUsability.key) !== undefined && previousOwner !== SourceAccountUsability.owner) {
      throw new Error('合成账号源标识与既有源冲突');
    }
    let name = SourceDataStore.get(SourceAccountUsability.key, '_probe_cookie');
    if (typeof name !== 'string') {
      name = `hm_auth_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
      await SourceDataStore.setAndWait(SourceAccountUsability.key, '_probe_cookie', name, trace);
    }
    await SourceDataStore.setAndWait(SourceAccountUsability.key, '_owner', SourceAccountUsability.owner, trace);
    await Settings.setBool(SourceAccountUsability.flag, true);
    await SourceAccountUsability.register(name as string);
    Log.audit(trace, '合成账号准备返回', '只注册本机模拟站点；验证真实ArkWeb/HTTP/RDB桥，不等于真实源登录');
    return SourceAccountUsability.key;
  }

  static async restoreIfEnabled(): Promise<void> {
    if (!Settings.getBool(SourceAccountUsability.flag, false)) { return; }
    await SourceDataStore.preload(SourceAccountUsability.key);
    if (SourceDataStore.get(SourceAccountUsability.key, '_owner') !== SourceAccountUsability.owner) {
      throw new Error('合成账号恢复所有权不符');
    }
    const name = SourceDataStore.get(SourceAccountUsability.key, '_probe_cookie');
    if (typeof name !== 'string') { throw new Error('合成账号缺少Cookie身份'); }
    await SourceAccountUsability.register(name);
    Log.audit('auth-fixture-restore', '合成账号重启恢复', '仅恢复模拟源注册；没有自动登录或联网');
  }

  static async cleanup(): Promise<void> {
    const trace = `auth-fixture-cleanup-${Date.now()}`;
    await SourceDataStore.preload(SourceAccountUsability.key);
    const owner = SourceDataStore.get(SourceAccountUsability.key, '_owner');
    if (owner === null) { await Settings.remove(SourceAccountUsability.flag); return; }
    if (owner !== SourceAccountUsability.owner) { throw new Error('拒绝清理非本机合成账号数据'); }
    const name = SourceDataStore.get(SourceAccountUsability.key, '_probe_cookie');
    if (typeof name !== 'string' || !/^hm_auth_[0-9]+_[0-9]+$/.test(name)) { throw new Error('合成账号Cookie身份无效'); }
    await SourceDataStore.awaitSourceWrites(SourceAccountUsability.key, SourceDataStore.failureEpoch(SourceAccountUsability.key), trace);
    CookieJar.deleteNamed(SourceAccountUsability.base, [name], trace);
    for (const key of ['_localStorage', 'verified', 'account', 'setting_defaults', '_probe_cookie', '_owner']) {
      await SourceDataStore.removeAndWait(SourceAccountUsability.key, key, trace);
    }
    await Settings.remove(SourceAccountUsability.flag);
    SourceManager.unregister(SourceAccountUsability.key);
    JsEngine.evaluate(`delete ComicSource.sources[${JSON.stringify(SourceAccountUsability.key)}]`, '<auth-fixture-cleanup>');
    Log.audit(trace, '合成账号清理返回', '只删除owner匹配源数据和随机名称Cookie；不清localhost其他会话/收藏/历史');
  }
}
