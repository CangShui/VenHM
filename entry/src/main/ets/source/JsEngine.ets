import { quickjsVersion, evaluate, setMessageHandler, setGlobalString,
  callJson as callJsonNative, invokeFunction as invokeFunctionNative, configureIsolated,
  transformIsolated, cancelIsolated, IsolatedPixels } from 'libvenerajs.so';
import { util } from '@kit.ArkTS';
import { AppContext, APP_VERSION } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { JsMessageHandler, JsMessageResult } from './JsMessageHandler';

/**
 * ArkTS facade over the native QuickJS module (entry/src/main/cpp).
 *
 * Dart original: lib/foundation/js_engine.dart. Initialization order matches the
 * Dart version: inject `appVersion`, register the `sendMessage` receiver, then
 * evaluate `assets/init.js` (kept byte-identical to upstream).
 */
export class JsEngine {
  private static available: boolean = false;
  private static engineVersion: string = '';
  private static smokeResult: string = '';
  private static initError: string = '';
  private static initScriptLoaded: boolean = false;
  private static initFuture: Promise<void> | undefined = undefined;
  private static initEvaluated: boolean = false;
  private static shimEvaluated: boolean = false;
  private static htmlEvaluated: boolean = false;

  static async init(): Promise<void> {
    if (JsEngine.initScriptLoaded) { return; }
    if (JsEngine.initFuture !== undefined) { return await JsEngine.initFuture; }
    const pending = JsEngine.initialize();
    JsEngine.initFuture = pending;
    try { await pending; } finally { JsEngine.initFuture = undefined; }
  }

  private static async initialize(): Promise<void> {
    JsEngine.initError = '';
    try {
      JsEngine.engineVersion = quickjsVersion();
      setGlobalString('appVersion', APP_VERSION);
      // The native side converts the message and the answer deeply, so this is
      // a plain value in / value out call (no JSON on either side).
      setMessageHandler((message: Object): JsMessageResult =>
        JsMessageHandler.handleMessage(message));

      const initJs = await JsEngine.readRawFile('init.js');
      if (!JsEngine.initEvaluated) {
        evaluate(initJs, '<init>');
        JsEngine.initEvaluated = true;
      }
      // Binds the native entry point to the `sendMessage` name init.js expects.
      const shim = await JsEngine.readRawFile('sendmessage_shim.js');
      if (!JsEngine.shimEvaluated) {
        evaluate(shim, '<sendmessage_shim>');
        JsEngine.shimEvaluated = true;
      }
      // HTML/CSS selector engine: answers `html` messages inside QuickJS so
      // scraping sources work without a native DOM.
      const htmlEngine = await JsEngine.readRawFile('html_engine.js');
      if (!JsEngine.htmlEvaluated) {
        evaluate(htmlEngine, '<html_engine>');
        JsEngine.htmlEvaluated = true;
      }
      configureIsolated(initJs, htmlEngine,
        (message: Object): JsMessageResult => JsMessageHandler.handleMessage(message),
        (trace: string, phase: string, message: string): void => { Log.audit(trace, phase, message); });
      await JsEngine.verifyBridgeContracts();
      await JsEngine.verifyIsolatedContracts();

      JsEngine.smokeResult = evaluate(
        '(() => { const a = [1,2,3].map(x => x * 2); ' +
        'return JSON.stringify({sum: a.reduce((p,c) => p+c, 0), n: a.length, ' +
        'hasComicSource: typeof ComicSource === "function", ' +
        'hasSendMessage: typeof sendMessage === "function", ' +
        'hasHtml: globalThis.__veneraHtmlEngineLoaded === true, ' +
        'appVersion: appVersion}); })()',
        '<smoke>');
      JsEngine.initScriptLoaded = true;
      JsEngine.available = true;
      Log.info('JsEngine',
        `QuickJS ${JsEngine.engineVersion} + init.js ready, smoke=${JsEngine.smokeResult}`);
    } catch (error) {
      JsEngine.available = false;
      JsEngine.initError = error instanceof Error ? error.message : String(error);
      Log.error('JsEngine', `initialization failed: ${JsEngine.initError}`);
    }
  }

  /**
   * Call a JS function a source handed back to the app (dialog actions,
   * validators, dynamic setting loaders). Without this the callbacks arrive as
   * opaque handles and every interactive source API silently does nothing.
   */
  static async invokeFunction(handle: Object, args: Object[], trace?: string): Promise<Object> {
    if (!JsEngine.available) {
      throw new Error('QuickJS 尚未初始化');
    }
    return await invokeFunctionNative(handle, args, trace);
  }

  /** Offline regression: two pending callJson requests must settle independently. */
  private static async verifyBridgeContracts(): Promise<void> {
    const first: Promise<Object> = callJsonNative(
      'new Promise(resolve => { globalThis.__veneraProbeFirst = resolve; })', '<bridge-a>');
    const second: Promise<Object> = callJsonNative(
      'new Promise(resolve => { globalThis.__veneraProbeSecond = resolve; })', '<bridge-b>');
    evaluate('globalThis.__veneraProbeSecond("B"); globalThis.__veneraProbeFirst("A"); ' +
      'delete globalThis.__veneraProbeFirst; delete globalThis.__veneraProbeSecond;', '<bridge-settle>');
    const results: Object[] = await Promise.all([first, second]);
    if (results[0] !== 'A' || results[1] !== 'B') {
      throw new Error(`QuickJS Promise 结果串线: ${results[0]}, ${results[1]}`);
    }
    const slice: Object = await callJsonNative(
      'Convert.encodeBase64(new Uint8Array([1, 2, 3]).subarray(1, 2))', '<bridge-slice>');
    if (slice !== 'Ag==') {
      throw new Error(`QuickJS TypedArray 子视图搬运错误: ${slice}`);
    }
    Log.info('JsEngine', 'bridge contracts OK: concurrent promises and typed-array slice');
    const traceA: Object = await callJsonNative(
      '(async()=>{const before=__veneraCurrentTrace();await sendMessage({method:"delay",time:5});' +
      'return [before,__veneraCurrentTrace()];})()', '<trace-a>', 'bridge-trace-A');
    const jobs: Promise<Object>[] = [
      callJsonNative('(async()=>{await sendMessage({method:"delay",time:8});return __veneraCurrentTrace();})()',
        '<trace-a-concurrent>', 'bridge-trace-A'),
      callJsonNative('(async()=>{await sendMessage({method:"delay",time:1});return __veneraCurrentTrace();})()',
        '<trace-b-concurrent>', 'bridge-trace-B')
    ];
    const traceResults = await Promise.all(jobs);
    const callback: Object = await callJsonNative('(()=>()=>__veneraCurrentTrace())()', '<trace-handle>', 'bridge-trace-handle');
    const callbackOwner: Object = await invokeFunctionNative(callback, []);
    if (!Array.isArray(traceA) || traceA[0] !== 'bridge-trace-A' || traceA[1] !== 'bridge-trace-A' ||
      traceResults[0] !== 'bridge-trace-A' || traceResults[1] !== 'bridge-trace-B' || callbackOwner !== 'bridge-trace-handle') {
      throw new Error('Native async trace ownership contract failed');
    }
    Log.info('JsEngine', 'native trace contracts OK (await/concurrent/captured callback ownership)');
    const html: Object | null = await callJsonNative(
      '(() => { const docs=[]; try { for(let i=0;i<12;i++) docs.push(new HtmlDocument(' +
      '"<p id=\\"probe\\">&#128512; &#x1F642; &#X1F680;</p>")); ' +
      'return docs.every(d=>d.querySelector("#probe").text==="😀 🙂 🚀"); ' +
      '} finally { docs.forEach(d=>d.dispose()); } })()', '<html-lifetime-contract>');
    if (html !== true) {
      throw new Error('HTML文档生命周期或Unicode实体回归失败');
    }
    Log.info('JsEngine', 'HTML live-document/Unicode contracts OK (12 live documents, then disposed)');
    const callbackValue: Object = await callJsonNative(
      '(() => { const s={settings:{probe:{count:0, callback:function(){' +
      'this.count++; return Promise.resolve(this.count);}}}};' +
      'return s.settings.probe.callback(); })()', '<setting-callback>');
    if (callbackValue !== 1) {
      throw new Error(`源设置 callback 的 this/异步返回错位: ${callbackValue}`);
    }
    Log.info('JsEngine', 'source-setting async callback contract OK');
    // A script callback must survive JS -> ArkTS -> JS. callJson resolves a
    // returned function into an opaque handle; invokeFunction is the other half.
    const callbackHandle: Object = await callJsonNative(
      '(function (a, b) { return a + b; })', '<probe-fn>');
    const callbackSum: Object = await invokeFunctionNative(callbackHandle, [20, 22]);
    if (callbackSum !== 42) {
      throw new Error(`invokeFunction 回程错误: ${callbackSum}`);
    }
    const asyncHandle: Object = await callJsonNative(
      '((n) => Promise.resolve(n * 2))', '<probe-async-fn>');
    const asyncValue: Object = await invokeFunctionNative(asyncHandle, [21]);
    if (asyncValue !== 42) {
      throw new Error(`invokeFunction 未等待 Promise: ${asyncValue}`);
    }
    const thrown: string = await invokeFunctionNative(
      await callJsonNative('(() => { throw new Error("probe-failure"); })', '<probe-throw>'), [])
      .then((): string => 'no-error', (error: Object): string => String(error));
    if (thrown.indexOf('probe-failure') < 0) {
      throw new Error(`invokeFunction 未回传异常: ${thrown}`);
    }
    Log.info('JsEngine', 'invokeFunction round-trip OK (sync, async, throw)');
    try {
      const cookie: string = evaluate('(() => { const u = "https://probe.venera.invalid/"; ' +
        'try { Network.setCookies(u, [new Cookie({name:"probe",value:"yes"})]); ' +
        'const a = Network.getCookies(u); return a.length === 1 && ' +
        'a[0].name === "probe" && a[0].value === "yes" && a[0].path === "/"; ' +
        '} finally { Network.deleteCookies(u); } })()', '<cookie-bridge>');
      if (cookie === 'true') {
        Log.info('JsEngine', 'cookie JS bridge set/get/delete OK');
      } else {
        Log.warn('JsEngine', `cookie JS bridge FAILED: ${cookie}`);
      }
    } catch (error) {
      Log.warn('JsEngine', `cookie JS bridge unavailable: ${error}`);
    }
    // AES is separately reported; a missing device cipher must not disable
    // every comic source. A 16-byte block must stay 16 bytes (NoPadding).
    try {
      const aes: string = evaluate('(() => { const b = new Uint8Array(16); ' +
        'const e = Convert.encryptAesEcb(b, b); ' +
        'return e ? Convert.hexEncode(e) : "unsupported"; })()', '<aes-contract>');
      Log.info('JsEngine', `AES-128 ECB zero-block=${aes} expected=66e94bd4ef8a2c3b884cfa59ca342b2e`);
      const modes: string = evaluate('(() => { const p = Uint8Array.from({length:16}, (_,i) => i); ' +
        'const k = new Uint8Array(16), iv = new Uint8Array(16); ' +
        'return [Convert.encryptAesEcb(p,k), Convert.encryptAesCbc(p,k,iv), ' +
        'Convert.encryptAesCfb(p,k,iv,1), Convert.encryptAesOfb(p,k,16)]' +
        '.map(x => x ? Convert.hexEncode(x) : "unsupported").join("|"); })()', '<aes-modes>');
      const expected = '7aca0fd9bcd6ec7c9f97466616e6a282|' +
        '7aca0fd9bcd6ec7c9f97466616e6a282|' +
        '66172196b987680c3616f2f5b8a34f26|' +
        '66e849d7eb8f2a3c8045f052c6392521';
      if (aes !== '66e94bd4ef8a2c3b884cfa59ca342b2e' || modes !== expected) {
        Log.warn('JsEngine', `AES mode vector MISMATCH: ${modes}`);
      } else {
        Log.info('JsEngine', 'AES-128 ECB/CBC/CFB8/OFB128 vectors OK');
      }
      const gbk: string = evaluate('Convert.hexEncode(Convert.encodeGbk("中"))', '<gbk-contract>');
      if (gbk === 'd6d0') {
        Log.info('JsEngine', 'GBK encode Chinese vector OK: 中=d6d0');
      } else {
        Log.warn('JsEngine', `GBK encode Chinese vector MISMATCH: ${gbk}`);
      }
    } catch (error) {
      Log.warn('JsEngine', `AES contract unavailable: ${error}`);
    }
    // RSA (js_engine.dart `case "rsa"`): base64 PKCS#8 key, PKCS1 v1.5
    // decryption, modulus-sized blocks. Vector generated and cross-checked by
    // tools/rsa_reference_vectors.js (node privateDecrypt on the same bytes).
    try {
      const ciphertext = 'pCYmePLCUzGGJkUwajglGiYQioc989Sw7cCLvloi7KEoF+9v95Xh1P1P9VvsE+yRPcA4GGIrKtfl1xmN68W54LL59EjKN67FK5KNYhGoaO4WIXC4EzGX8BtZGJZJbE13J1nDCC27pfFPD7BWs/LuS6gj5ploQRtNrWSZqAOnJ7s=';
      const privateKey = 'MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAMfvZcwn+3wtqpriKBsosBv8Ycl/6Z1Ea5USlaNWF1r3WvrUXbgll5OnBgj8W7nBVLwAm/0BLDU8VinAucucze1wFSPrcWhe0yN63vG7v1Vm7214pG4lJ6gC0B9e1EwlJQXyLbx1NlRDtwFNdQfIoZJMpkWOfZRzENKQ2yoS6rWNAgMBAAECgYBVowXgT1PZmZnUo3/4OhJMumqMK1y9/vtxq7cqcgqo7QAsJeBKqtdk6AqeuLD1PIj1yfEGioUL/F8PnTw3qV9OTUTO7JLNCST3G/H/2AqqxqhP+vyRtlaAb9WxMO9Io+cOO5WN1x8fuAQ44elSAxrHCrrMiSUtK3zk2O98cJ4MoQJBAO2Mr1D+yqEkgtkVipErp/SLcrF/D/W1oS80K+n7gUNBV8L0whJQhfsAbLuQblqORnDR4F1TYaMZo5KevzxX0PkCQQDXds6aOzn7DtRHIGE6n3iTqJTfDYpxucYOIRukMTGmpCkFe8a3hR6urB716pUjzA04QnV6+4oABFAbwOfHDoI1AkAPmb2pxBHqo0s0loWTIxrUpJPTtFSH/nWnc/WuWCYVFKV+2DQmn8MsyMpbRxD4QX++yQnDF0bCP1zOtD466EmBAkBO00AyXIiRuJMgkk//ymeqXXpZP/LuODCk6qfaIcUwWc5IG0hPy3u2G3IYNYHqXrRXaLjiDTQnXWyROrmQsVYhAkEArn/khbCs7ShDS7flw7wSVEGdxZs3aNc6BEhDDtpcreChNFLs8eCGLBDyEEk8WDyCsw4q2qQcHOOTFlCO+x/2yA==';
      const expected = '{"code":0,"data":{"key":"venera-rsa-vector"}}';
      const rsa: string = evaluate(`(() => { const ct = Convert.decodeBase64('${ciphertext}'); ` +
        `const out = Convert.decryptRsa(ct, '${privateKey}'); ` +
        'return out ? Convert.decodeUtf8(out) : "null"; })()', '<rsa-contract>');
      if (rsa === expected) {
        Log.info('JsEngine', 'RSA-1024 PKCS1 decrypt vector OK');
      } else {
        Log.warn('JsEngine', `RSA PKCS1 decrypt vector MISMATCH: ${rsa}`);
      }
    } catch (error) {
      Log.warn('JsEngine', `RSA contract unavailable: ${error}`);
    }
  }

  /** Synthetic real-NAPI checks, deliberately through upstream compute(), not a parallel test-only API. */
  private static async verifyIsolatedContracts(): Promise<void> {
    const trace = 'startup-isolated-contract';
    Log.audit(trace, '隔离验收到达', '仅固定合成数据；验证源compute入口、主机RPC、独立像素、取消和恢复');
    evaluate('globalThis.__veneraMainOnlyProbe = true;', '<isolated-main-marker>');
    let checks: Object;
    try {
      checks = await callJsonNative('Promise.all([' +
        'compute("async (n) => { await sendMessage({method: \'delay\', time: 1}); ' +
        'const d = new HtmlDocument(\'<p id=probe>worker</p>\'); try { ' +
        'return n === 21 && typeof __veneraMainOnlyProbe === \'undefined\' && ' +
        'typeof ComicSource === \'function\' && appVersion === \'1.17.0\' && ' +
        'sendMessage({method: \'getPlatform\'}) === \'ohos\' && ' +
        'd.querySelector(\'#probe\').text === \'worker\'; } finally { d.dispose(); }}", 21),' +
        'compute("(bytes, map, set) => bytes.length === 1 && bytes[0] === 2 && ' +
        'map instanceof Map && map.get(\'answer\') === 42 && set.has(7)",' +
        'new Uint8Array([1,2,3]).subarray(1,2), new Map([["answer",42]]), new Set([7]))' +
        ']).then(values => values.every(v => v === true))', '<source-compute-contract>', trace);
    } finally {
      evaluate('delete globalThis.__veneraMainOnlyProbe;', '<isolated-main-cleanup>');
    }
    if (checks !== true) { throw new Error('Source compute isolation/host RPC/structured clone contract failed'); }
    const cloned: Object = await callJsonNative('(async () => { const input = {n: 1}; input.self = input; ' +
      'const out = await compute("(x) => { x.n=2; return {x, map:new Map([[\'x\',x]]), ' +
      'set:new Set([9]), bytes:new Uint8Array([4,5,6]).subarray(1,2)}; }", input); ' +
      'return input.n === 1 && out.x.n === 2 && out.x.self === out.x && out.map instanceof Map && ' +
      'out.map.get("x") === out.x && out.set.has(9) && out.bytes.length === 1 && out.bytes[0] === 5; })()',
      '<source-compute-roundtrip>', trace);
    const unsupported: Object = await callJsonNative('(async () => { let refused=0; const tasks=[' +
      '() => compute("42"), () => compute("() => () => 1"), () => compute("x => x", () => 1), ' +
      '() => compute("() => sendMessage({method:\'UI\',function:\'showDialog\',actions:[{callback:()=>1}]})")]; ' +
      'for(const task of tasks) { try { await task(); } catch (_) { refused++; } } return refused === tasks.length; })()',
      '<source-compute-unsupported>', trace);
    if (cloned !== true || unsupported !== true) { throw new Error('Source compute clone/unsupported callback contract failed'); }
    const rejected: Object = await callJsonNative(
      'compute("() => { throw new Error(\'synthetic-compute-reject\'); }")' +
      '.then(() => false, () => true)', '<source-compute-reject>', trace);
    const recovered: Object = await callJsonNative('compute("(a,b) => a+b", 20, 22)',
      '<source-compute-recover>', trace);
    if (rejected !== true || recovered !== 42) { throw new Error('Source compute reject/recovery contract failed'); }
    Log.audit(trace, 'compute验收返回', 'PASS · 源compute原生入口/并发/主引擎隔离/HTML/同步和异步主机RPC/Map和Set及子视图/异常恢复；不声明持久全局或远程回调等价');

    const rgba = new Uint8Array([11,21,31,255,12,22,32,255,13,23,33,255,14,24,34,255,15,25,35,255,16,26,36,255]);
    const rotated: IsolatedPixels = await transformIsolated(rgba.buffer, 2, 3,
      'let modifyImage = i => i.copyAndRotate90();', trace, false, 2000);
    const expected = [15,25,35,255,13,23,33,255,11,21,31,255,16,26,36,255,14,24,34,255,12,22,32,255];
    const pixels = new Uint8Array(rotated.rgba);
    if (rotated.width !== 3 || rotated.height !== 2 || pixels.length !== expected.length) {
      throw new Error('Isolated image dimensions contract failed');
    }
    for (let i = 0; i < pixels.length; i++) {
      if (pixels[i] !== expected[i]) { throw new Error('Isolated image RGBA rotation contract failed'); }
    }
    const cancelTrace = 'startup-isolated-cancel';
    const cancelled: Promise<boolean> = transformIsolated(rgba.buffer, 2, 3,
      'let modifyImage = i => { while (true) {} return i; };', cancelTrace, false, 2000)
      .then((): boolean => false, (): boolean => true);
    // Queueing is synchronous; immediate cancellation also exercises a not-yet-running job.
    const cancellationCount: number = cancelIsolated(cancelTrace);
    const next: Promise<IsolatedPixels> = transformIsolated(rgba.buffer, 2, 3, 'let modifyImage = i => i;',
      'startup-isolated-unrelated', false, 2000);
    if (cancellationCount < 1 || !await cancelled) { throw new Error('Isolated image cancellation contract failed'); }
    const identity: IsolatedPixels = await next;
    if (identity.width !== 2 || identity.height !== 3 || new Uint8Array(identity.rgba)[0] !== 11) {
      throw new Error('Unrelated isolated image failed after cancellation');
    }
    Log.audit(trace, '隔离像素验收返回', 'PASS · 2×3真实原生RGBA旋转/匹配Trace取消/无关Trace继续成功；不代表ImageKit编解码或真实JM验收');
  }

  private static async readRawFile(name: string): Promise<string> {
    const data: Uint8Array = await AppContext.context.resourceManager.getRawFileContent(name);
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(data);
  }

  static get isAvailable(): boolean {
    return JsEngine.available;
  }

  static get isScriptLoaded(): boolean {
    return JsEngine.initScriptLoaded;
  }

  static get version(): string {
    return JsEngine.engineVersion;
  }

  static get smoke(): string {
    return JsEngine.smokeResult;
  }

  static get error(): string {
    return JsEngine.initError;
  }

  /** Evaluate a script synchronously; returns its string form. */
  static evaluate(code: string, filename: string): string {
    if (!JsEngine.available) {
      throw new Error(`QuickJS 不可用: ${JsEngine.initError}`);
    }
    return evaluate(code, filename);
  }

  /**
   * Evaluate an expression and resolve with its value, converted deeply by the
   * native bridge (a `Map` arrives as an object, bytes as a `Uint8Array`).
   * Source callbacks are async, so this waits for the returned promise.
   *
   * `null`/`undefined` resolve to `null` so callers can tell "no result" from an
   * empty object.
   */
  static async callJson(code: string, filename: string, trace?: string): Promise<Object | null> {
    if (!JsEngine.available) {
      throw new Error(`QuickJS 不可用: ${JsEngine.initError}`);
    }
    const id = trace ?? `js-${Date.now()}-${util.generateRandomUUID(true)}`;
    Log.audit(id, '脚本请求到达', '表达式/参数可能含凭据，原文不落盘；异步continuation按注册时上下文隔离');
    let value: Object | null;
    try { value = await callJsonNative(code, filename, id); }
    catch (error) { Log.audit(id, '脚本请求异常', '执行或Promise失败，未输出脚本参数/错误原文'); throw new Error(String(error)); }
    Log.audit(id, '脚本响应返回', `类型=${value === null ? 'null' : typeof value}；不记录返回内容`);
    return value === undefined ? null : value;
  }
}
