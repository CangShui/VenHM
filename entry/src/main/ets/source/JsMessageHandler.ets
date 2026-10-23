import { util } from '@kit.ArkTS';
import { encodeGbk } from 'libvenerajs.so';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { Want, common } from '@kit.AbilityKit';
import { HttpClient, HttpRequestOptions, HttpResponse, recordToHeaders } from '../network/HttpClient';
import { CookieJar } from '../network/CookieJar';
import { SourceDataStore } from './SourceDataStore';
import { UiAction, UiBridge } from './UiBridge';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { ImageScriptBridge } from './ImageScriptBridge';
import { AuthLogScope } from './AuthLogScope';

/**
 * `sendMessage` dispatch table - the ArkTS half of the JS runtime contract.
 *
 * Dart original: lib/foundation/js_engine.dart `_messageReceiver`.
 *
 * Messages and answers cross the QuickJS/ArkTS realm boundary as real values,
 * converted deeply by the native bridge (entry/src/main/cpp/value_bridge.h) -
 * the equivalent of upstream's direct Dart<->JSValue conversion. The method is
 * deliberately NOT async: init.js needs synchronous returns for load_data /
 * convert / random / uuid / getLocale, while http / delay / UI must return
 * promises. Making the whole function async would turn every reply into a
 * promise and break the synchronous half.
 */
export type JsMessageResult = Object | null | Promise<Object | null>;

export class JsMessageHandler {
  private static nextTrace: number = 0;
  /** Entry point invoked from the native QuickJS bridge. */
  static handleMessage(message: Object): JsMessageResult {
    const record = message as Record<string, Object>;
    const nativeTrace = JsMessageHandler.stringOf(record['__veneraTraceId']);
    const trace = nativeTrace && /^[a-zA-Z0-9_.:-]{1,160}$/.test(nativeTrace) ? nativeTrace :
      `rpc-${Date.now()}-${JsMessageHandler.nextTrace++}`;
    try {
      const result = JsMessageHandler.dispatch(record, trace);
      if (result instanceof Promise) {
        return result.then((value: Object | null): Object | null => {
          Log.audit(trace, '原生RPC响应', `异步完成；类型=${value === null ? 'null' : typeof value}；内容不落盘`);
          return value;
        }).catch((error: Object): Object | null => {
          Log.audit(trace, '原生RPC异常', '异步请求失败，错误原文可能含凭据，未写日志');
          throw new Error(error instanceof Error ? error.message : String(error));
        });
      }
      Log.audit(trace, '原生RPC响应', `同步完成；类型=${result === null ? 'null' : typeof result}；内容不落盘`);
      return result;
    } catch (error) {
      Log.audit(trace, '原生RPC拒绝/异常', '同步请求被拒绝或执行失败；不记录参数/原文');
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  private static dispatch(record: Record<string, Object>, trace: string): JsMessageResult {
    const nativeTrace = JsMessageHandler.stringOf(record['__veneraTraceId']);
    const methodValue = record['method'];
    if (typeof methodValue !== 'string') {
      Log.audit(trace, '原生RPC拒绝', '缺少字符串method；未进入业务');
      return null;
    }
    const method = methodValue as string;
    const safeMethod = ['log', 'load_data', 'save_data', 'delete_data', 'load_setting', 'isLogged',
      'http', 'image', 'convert', 'random', 'uuid', 'delay', 'cookie', 'getLocale', 'getPlatform',
      'setClipboard', 'getClipboard', 'html', 'UI', 'compute'].includes(method) ? method : 'unknown-method';
    const sourceKey = JsMessageHandler.stringOf(record['key']);
    // High-volume HTML is handled inside JS; this covers every actual native RPC.
    Log.audit(trace, '原生RPC到达', `方法=${safeMethod}；源=${sourceKey === undefined ? '无源键' : '有源键'}；参数原文不落盘`);

    switch (method) {
      case 'log': {
        const level = JsMessageHandler.stringOf(record['level']);
        const sensitive = nativeTrace === undefined ? AuthLogScope.current() :
          AuthLogScope.owns(nativeTrace) ? trace : undefined;
        if (sensitive !== undefined) {
          const safeLevel = level === 'error' ? 'error' : level === 'info' ? 'info' : level === 'warn' ? 'warn' : 'other';
          Log.audit(sensitive, '源日志脱敏', `等级=${safeLevel}；账号操作期间省略源自行打印的标题/原文，避免回显密码或Token`);
          return null;
        }
        const title = JsMessageHandler.stringOf(record['title']) ?? 'Source';
        const content = record['content'] === undefined ? '' : String(record['content']);
        if (level === 'error') {
          Log.error(title, content);
        } else if (level === 'info') {
          Log.info(title, content);
        } else {
          Log.warn(title, content);
        }
        return null;
      }
      case 'load_data': {
        if (sourceKey === undefined) {
          return null;
        }
        return SourceDataStore.get(sourceKey, JsMessageHandler.stringOf(record['data_key']) ?? '');
      }
      case 'save_data': {
        if (sourceKey === undefined) {
          return null;
        }
        const dataKey = JsMessageHandler.stringOf(record['data_key']) ?? '';
        if (dataKey === 'setting') {
          throw new Error('setting is not allowed to be saved');
        }
        SourceDataStore.set(sourceKey, dataKey, record['data'], trace);
        return null;
      }
      case 'delete_data': {
        if (sourceKey !== undefined) {
          SourceDataStore.remove(sourceKey, JsMessageHandler.stringOf(record['data_key']) ?? '', trace);
        }
        return null;
      }
      case 'load_setting': {
        if (sourceKey === undefined) {
          throw new Error('load_setting requires a source key');
        }
        const settingKey = JsMessageHandler.stringOf(record['setting_key']) ?? '';
        const settings = SourceDataStore.get(sourceKey, 'settings');
        if (settings !== undefined && settings !== null) {
          const asRecord = settings as Record<string, Object>;
          const value = asRecord[settingKey];
          if (value !== undefined && value !== null) {
            return value;
          }
        }
        // Fall back to the default declared in the script's `settings` object,
        // which the parser stored at install time. Upstream order is:
        // user value -> declared default -> throw.
        const declared = SourceDataStore.get(sourceKey, 'setting_defaults');
        if (declared !== undefined && declared !== null) {
          const defaults = declared as Record<string, Object>;
          const fallback = defaults[settingKey];
          if (fallback !== undefined && fallback !== null) {
            return fallback;
          }
        }
        throw new Error(`Setting not found: ${settingKey}`);
      }
      case 'isLogged': {
        if (sourceKey === undefined) {
          return false;
        }
        const account = SourceDataStore.get(sourceKey, 'account');
        return account !== undefined && account !== null;
      }
      case 'http':
        return JsMessageHandler.http(record, trace);
      case 'image':
        return ImageScriptBridge.handle(record);
      case 'convert':
        return JsMessageHandler.convert(record);
      case 'random': {
        const min = JsMessageHandler.numberOf(record['min']) ?? 0;
        const max = JsMessageHandler.numberOf(record['max']) ?? 1;
        if (JsMessageHandler.stringOf(record['type']) === 'int') {
          return Math.floor(Math.random() * (max - min + 1)) + min;
        }
        return Math.random() * (max - min) + min;
      }
      case 'uuid':
        return util.generateRandomUUID(true);
      case 'delay':
        return JsMessageHandler.delay(JsMessageHandler.numberOf(record['time']) ?? 0)
          .then((value: Object): Object | null => null);
      case 'cookie': {
        const action = JsMessageHandler.stringOf(record['function']);
        const cookieUrl = JsMessageHandler.stringOf(record['url']) ?? '';
        if (action === 'get') {
          return CookieJar.get(cookieUrl);
        }
        if (action === 'set') {
          const list = record['cookies'];
          if (Array.isArray(list)) {
            CookieJar.set(cookieUrl, list as Object[]);
          }
        } else if (action === 'delete') {
          CookieJar.delete(cookieUrl);
        }
        return null;
      }
      case 'getLocale':
        return 'zh_CN';
      case 'getPlatform':
        return 'ohos';
      case 'setClipboard':
        return null;
      case 'getClipboard':
        return Promise.resolve(null);
      case 'html':
        Log.warn('JsMessageHandler', 'html() is not implemented yet');
        return null;
      case 'UI':
        return JsMessageHandler.ui(record, trace);
      case 'compute':
        // Main-source calls MUST be intercepted natively before conversion so
        // Map/Set/cycles/typed-array offsets are preserved. Never evaluate a
        // fallback on ArkUI/main QuickJS. Worker-to-worker compute is also not
        // routed recursively through this host channel.
        Log.audit(trace, 'compute路由拒绝', 'compute未经过源原生入口或来自工作会话；不退回主线程执行');
        return Promise.reject(new Error('compute requires the native source entry; nested worker compute is unsupported'));
      default:
        Log.audit(trace, '原生RPC未进入业务', '未知方法，按原版返回null；未默默执行其他功能');
        return null;
    }
  }

  /**
   * `UI` - dialogs and external links requested by a script.
   *
   * Dart original: lib/components/js_ui.dart. Callbacks (dialog actions, input
   * validators, loading onCancel) arrive as opaque JS function handles and are
   * invoked through JsEngine.invokeFunction.
   */
  private static ui(record: Record<string, Object>, trace: string): Object | null {
    const fn = JsMessageHandler.stringOf(record['function']);
    if (fn === 'showMessage') {
      promptAction.showToast({
        message: JsMessageHandler.stringOf(record['message']) ?? '',
        duration: 3000
      });
      return null;
    }
    if (fn === 'launchUrl') {
      const url = JsMessageHandler.stringOf(record['url']) ?? '';
      if (url.length > 0) {
        try {
          const abilityContext = AppContext.context as common.UIAbilityContext;
          const want: Want = { action: 'ohos.want.action.viewData', uri: url };
          abilityContext.startAbility(want).catch((error: Object) => {
            Log.warn('JsMessageHandler', `launchUrl failed: ${error}`);
          });
        } catch (error) {
          Log.warn('JsMessageHandler', `launchUrl failed: ${error}`);
        }
      }
      return null;
    }
    if (fn === 'showDialog') {
      const title = JsMessageHandler.stringOf(record['title']) ?? '';
      const content = JsMessageHandler.stringOf(record['content']) ?? '';
      return UiBridge.showDialog(title, content, JsMessageHandler.readActions(record['actions']), trace);
    }
    if (fn === 'showInputDialog') {
      const title = JsMessageHandler.stringOf(record['title']);
      if (title === undefined) {
        return null;
      }
      const validator = record['validator'];
      // Upstream ignores a validator that is neither null nor a function.
      const valid = validator === undefined || validator === null ||
        typeof validator === 'object';
      if (!valid) {
        return null;
      }
      const image = record['image'];
      const imageUrl = typeof image === 'string' ? image as string : '';
      return UiBridge.showInputDialog(title,
        validator === null ? undefined : validator, imageUrl, trace);
    }
    if (fn === 'showSelectDialog') {
      const title = JsMessageHandler.stringOf(record['title']);
      if (title === undefined) {
        return null;
      }
      const options = record['options'];
      if (!Array.isArray(options)) {
        return null;
      }
      const list: string[] = (options as Object[]).filter(
        (item: Object) => typeof item === 'string').map((item: Object) => item as string);
      const initial = JsMessageHandler.numberOf(record['initialIndex']);
      return UiBridge.showSelectDialog(title, list,
        initial === undefined ? -1 : Math.floor(initial), trace);
    }
    if (fn === 'showLoading') {
      const onCancel = record['onCancel'];
      return UiBridge.showLoading(
        onCancel === undefined || onCancel === null ? undefined : onCancel, trace);
    }
    if (fn === 'cancelLoading') {
      const id = JsMessageHandler.numberOf(record['id']);
      if (id !== undefined) {
        UiBridge.cancelLoading(Math.floor(id));
      }
      return null;
    }
    Log.warn('JsMessageHandler', `UI.${fn} is not implemented yet`);
    return null;
  }

  /** Dialog actions arrive as `{text, style, callback}`; keep the callable ones. */
  private static readActions(value: Object | undefined): UiAction[] {
    const actions: UiAction[] = [];
    if (!Array.isArray(value)) {
      return actions;
    }
    for (const entry of value as Object[]) {
      if (entry === null || entry === undefined || typeof entry !== 'object') {
        continue;
      }
      const record = entry as Record<string, Object>;
      const action = new UiAction();
      action.text = JsMessageHandler.stringOf(record['text']) ?? '';
      action.style = JsMessageHandler.stringOf(record['style']) ?? 'text';
      const callback = record['callback'];
      if (callback !== undefined && callback !== null) {
        action.callback = callback;
      }
      actions.push(action);
    }
    return actions;
  }

  // ---------------------------------------------------------------- helpers

  private static stringOf(value: Object | undefined): string | undefined {
    return typeof value === 'string' ? value as string : undefined;
  }

  private static numberOf(value: Object | undefined): number | undefined {
    return typeof value === 'number' ? value as number : undefined;
  }

  private static delay(ms: number): Promise<Object> {
    return new Promise<Object>((resolve: (value: Object) => void) => {
      setTimeout(() => {
        resolve('');
      }, ms < 0 ? 0 : ms);
    });
  }

  /**
   * `http` - async. Mirrors the Dart result shape:
   *   { status, headers, body } on success, { error } on failure.
   * assets/init.js throws when `error` is present.
   */
  private static async http(record: Record<string, Object>, trace: string): Promise<Object> {
    const url = JsMessageHandler.stringOf(record['url']) ?? '';
    const methodName = (JsMessageHandler.stringOf(record['http_method']) ?? 'GET').toUpperCase();
    const wantBytes = record['bytes'] === true;
    const headers = recordToHeaders(record['headers']);
    // Fixed upstream RHttpAdapter sets VeneraNext/v1.17.0 when source scripts
    // omit User-Agent. A forced Phone browser UA selects mobile HTML templates
    // and breaks otherwise-correct desktop source selectors. Keep explicit UAs.
    if (!Array.from(headers.keys()).some((name: string) => name.toLowerCase() === 'user-agent')) {
      headers.set('User-Agent', 'VeneraNext/v1.17.0');
    }
    const data = record['data'];

    const options = new HttpRequestOptions();
    options.traceId = trace;
    options.headers = headers;
    options.asBytes = wantBytes;
    if (data !== undefined && data !== null) {
      if (typeof data === 'string') {
          options.rawBody = data as string;
      } else if (data instanceof Uint8Array) {
        // A script POSTing bytes (fetchBytes + form upload) must send the raw
        // payload; the old bridge stringified it into a JSON blob of indices.
        options.extraData = data as Uint8Array;
      } else if (data instanceof ArrayBuffer) {
        options.extraData = new Uint8Array(data as ArrayBuffer);
      } else {
        try {
          options.jsonBody = JSON.stringify(data);
        } catch (error) {
          options.formBody = String(data);
        }
      }
    }

    const result: Record<string, Object> = {};
    try {
      const response: HttpResponse =
        await HttpClient.request(url, JsMessageHandler.requestMethod(methodName), options);
      result.status = response.status;
      const headerRecord: Record<string, string> = {};
      for (const name of response.headers.keys()) {
        headerRecord[name] = response.headers.get(name) as string;
      }
      result.headers = headerRecord;
      if (wantBytes && response.bytes !== undefined) {
        // Real bytes cross the bridge as an ArrayBuffer, which is what scripts
        // wrap in `new Uint8Array(...)` or `new DataView(...)`.
        result.body = response.bytes;
      } else {
        result.body = response.body;
      }
    } catch (error) {
      result.error = error instanceof Error ? error.message : String(error);
    }
    return result;
  }

  private static requestMethod(name: string): http.RequestMethod {
    switch (name) {
      case 'GET':
        return http.RequestMethod.GET;
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      case 'PATCH':
        // Forward wire compatibility: this SDK omits the enum member but
        // NetStack supports PATCH. Runtime rejection remains a real SDK error.
        return 'PATCH' as http.RequestMethod;
      case 'OPTIONS':
        return http.RequestMethod.OPTIONS;
      default:
        throw new Error('不支持的HTTP方法；未静默改为GET');
    }
  }

  // ------------------------------------------------------------- conversion

  private static convert(record: Record<string, Object>): Object | null {
    const type = JsMessageHandler.stringOf(record['type']);
    if (type === undefined) {
      return null;
    }
    try {
      switch (type) {
        case 'utf8': {
          if (record['isEncode'] === true) {
            return JsMessageHandler.toBytes(record['value']);
          }
          return JsMessageHandler.decodeUtf8(JsMessageHandler.toBytes(record['value']));
        }
        case 'gbk': {
          if (record['isEncode'] === true) {
            const text = JsMessageHandler.stringOf(record['value']);
            return text === undefined ? null : encodeGbk(text);
          }
          return JsMessageHandler.decodeWith('gbk', JsMessageHandler.toBytes(record['value']));
        }
        case 'base64': {
          if (record['isEncode'] === true) {
            return JsMessageHandler.base64Encode(JsMessageHandler.toBytes(record['value']));
          }
          const text = typeof record['value'] === 'string'
            ? record['value'] as string
            : JsMessageHandler.decodeUtf8(JsMessageHandler.toBytes(record['value']));
          return JsMessageHandler.base64Decode(text);
        }
        case 'md5':
          return JsMessageHandler.digest('MD5', record['value']);
        case 'sha1':
          return JsMessageHandler.digest('SHA1', record['value']);
        case 'sha256':
          return JsMessageHandler.digest('SHA256', record['value']);
        case 'sha512':
          return JsMessageHandler.digest('SHA512', record['value']);
        case 'hmac': {
          const hash = (JsMessageHandler.stringOf(record['hash']) ?? 'sha256').toUpperCase();
          const bytes = JsMessageHandler.hmac(hash, JsMessageHandler.toBytes(record['key']),
            JsMessageHandler.toBytes(record['value']));
          if (record['isString'] === true) {
            return JsMessageHandler.toHex(bytes);
          }
          return bytes;
        }
        case 'aes-ecb':
        case 'aes-cbc':
        case 'aes-cfb':
        case 'aes-ofb':
          return JsMessageHandler.aes(type, record);
        case 'rsa':
          return JsMessageHandler.rsa(record);
        default:
          return record['value'];
      }
    } catch (error) {
      Log.error('JsMessageHandler', `convert(${type}) failed: ${error}`);
      return null;
    }
  }

  /**
   * Bytes arrive from QuickJS as a real Uint8Array/ArrayBuffer now, so the
   * `{__bytes__: base64}` side-channel the JSON bridge needed is gone.
   */
  private static toBytes(value: Object | undefined): Uint8Array {
    if (value === undefined || value === null) {
      return new Uint8Array(0);
    }
    if (value instanceof Uint8Array) {
      return value as Uint8Array;
    }
    if (value instanceof ArrayBuffer) {
      return new Uint8Array(value as ArrayBuffer);
    }
    if (typeof value === 'string') {
      const encoder = new util.TextEncoder();
      return encoder.encodeInto(value as string);
    }
    return new Uint8Array(0);
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    return JsMessageHandler.decodeWith('utf-8', bytes);
  }

  /** Never disguise a failed GBK decode as a successful UTF-8 conversion. */
  private static decodeWith(charset: string, bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create(charset);
    return decoder.decodeToString(bytes);
  }

  /** Encrypt one 16-byte block with raw AES-ECB for CFB/OFB feedback. */
  private static aesBlock(keyAlg: string, key: cryptoFramework.SymKey,
                          input: Uint8Array): Uint8Array {
    const cipher = cryptoFramework.createCipher(`${keyAlg}|ECB|NoPadding`);
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, null);
    return cipher.doFinalSync({ data: input }).data;
  }

  /**
   * Match pointycastle's raw block processing (js_engine.dart:442-508).
   * ECB/CBC must not add or strip PKCS7 bytes; CFB/OFB process exactly
   * `blockSize` bytes per iteration and update a 16-byte feedback register.
   */
  private static aes(mode: string, record: Record<string, Object>): Object | null {
    const value = JsMessageHandler.toBytes(record['value']);
    const key = JsMessageHandler.toBytes(record['key']);
    const isEncode = record['isEncode'] === true;

    let keyAlg = '';
    if (key.length === 16) {
      keyAlg = 'AES128';
    } else if (key.length === 24) {
      keyAlg = 'AES192';
    } else if (key.length === 32) {
      keyAlg = 'AES256';
    } else {
      Log.error('JsMessageHandler', `AES key must be 16/24/32 bytes, got ${key.length}`);
      return null;
    }

    const blockMode = mode === 'aes-ecb' || mode === 'aes-cbc';
    const segmentSize = JsMessageHandler.numberOf(record['blockSize']);
    if (blockMode && value.length % 16 !== 0) {
      Log.warn('JsMessageHandler', `${mode} requires a whole number of 16-byte blocks`);
      return null;
    }
    if (!blockMode && (segmentSize === undefined || segmentSize < 1 ||
        segmentSize > 16 || Math.trunc(segmentSize) !== segmentSize ||
        value.length % segmentSize !== 0)) {
      Log.warn('JsMessageHandler', `${mode} requires 1..16-byte aligned blockSize`);
      return null;
    }
    if (value.length === 0) {
      return new Uint8Array(0);
    }
    try {
      const keyGenerator = cryptoFramework.createSymKeyGenerator(keyAlg);
      const symKey = keyGenerator.convertKeySync({ data: key });
      if (!blockMode) {
        // OFB receives only KeyParameter in the original, hence a zero IV.
        const iv = mode === 'aes-ofb' ? new Uint8Array(16)
          : JsMessageHandler.toBytes(record['iv']);
        if (iv.length !== 16) {
          Log.warn('JsMessageHandler', `AES ${mode} needs a 16-byte iv`);
          return null;
        }
        const feedback = new Uint8Array(16);
        feedback.set(iv);
        const output = new Uint8Array(value.length);
        const size = segmentSize as number;
        for (let offset = 0; offset < value.length; offset += size) {
          const stream = JsMessageHandler.aesBlock(keyAlg, symKey, feedback);
          for (let i = 0; i < size; i++) {
            output[offset + i] = value[offset + i] ^ stream[i];
          }
          for (let i = 0; i < 16 - size; i++) {
            feedback[i] = feedback[i + size];
          }
          for (let i = 0; i < size; i++) {
            feedback[16 - size + i] = mode === 'aes-ofb' ? stream[i]
              : (isEncode ? output[offset + i] : value[offset + i]);
          }
        }
        return output;
      }
      const cipher = cryptoFramework.createCipher(
        `${keyAlg}|${mode === 'aes-ecb' ? 'ECB' : 'CBC'}|NoPadding`);
      const operation = isEncode ? cryptoFramework.CryptoMode.ENCRYPT_MODE
        : cryptoFramework.CryptoMode.DECRYPT_MODE;
      if (mode === 'aes-cbc') {
        const iv = JsMessageHandler.toBytes(record['iv']);
        if (iv.length !== 16) {
          Log.warn('JsMessageHandler', 'AES CBC needs a 16-byte iv');
          return null;
        }
        const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
        cipher.initSync(operation, symKey, params);
      } else {
        cipher.initSync(operation, symKey, null);
      }
      return cipher.doFinalSync({ data: value }).data;
    } catch (error) {
      Log.error('JsMessageHandler', `AES ${mode} failed: ${error}`);
      return null;
    }
  }

  // ------------------------------------------------------------------- RSA

  /**
   * RSA private-key decryption.
   *
   * Dart original: js_engine.dart:509-517 (`case "rsa"`), `_parsePrivateKey`
   * (:527-543) and `_processInBlocks` (:545-562).
   *
   * The Dart side base64-decodes a PKCS#8 PrivateKeyInfo, takes the inner
   * PKCS#1 RSAPrivateKey and decrypts with PKCS1 (v1.5) padding, consuming the
   * input in `inputBlockSize` (= modulus length) chunks and concatenating the
   * plaintexts. The platform key importer accepts the same PKCS#8 DER, and one
   * `doFinal` call decrypts exactly one modulus-sized block, so the chunking is
   * explicit here.
   */
  private static rsa(record: Record<string, Object>): Object | null {
    if (record['isEncode'] === true) {
      // Upstream only implements the decrypt direction and returns null here.
      return null;
    }
    const der = JsMessageHandler.rsaKeyBytes(record['key']);
    const value = JsMessageHandler.toBytes(record['value']);
    if (der.length === 0 || value.length === 0) {
      Log.warn('JsMessageHandler', 'convert(rsa): empty private key or value');
      return null;
    }
    const modulusLength = JsMessageHandler.pkcs8ModulusLength(der);
    const spec = modulusLength > 0 ? JsMessageHandler.rsaKeySpec(modulusLength * 8) : '';
    if (spec.length === 0) {
      Log.warn('JsMessageHandler',
        `convert(rsa): unsupported private key (modulus ${modulusLength} bytes)`);
      return null;
    }
    if (value.length % modulusLength !== 0) {
      // pointycastle throws on a partial block and the Dart wrapper turns that
      // into null; truncating silently would hand the script wrong bytes.
      Log.warn('JsMessageHandler',
        `convert(rsa): ${value.length} bytes is not a whole number of ${modulusLength}-byte blocks`);
      return null;
    }
    try {
      const generator = cryptoFramework.createAsyKeyGenerator(spec);
      const privateKeyBlob: cryptoFramework.DataBlob = { data: der };
      const keyPair = generator.convertKeySync(null, privateKeyBlob);
      const cipher = cryptoFramework.createCipher(`${spec}|PKCS1`);
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, keyPair.priKey, null);
      const blocks: Uint8Array[] = [];
      let total = 0;
      for (let offset = 0; offset < value.length; offset += modulusLength) {
        const input: cryptoFramework.DataBlob = {
          data: value.subarray(offset, offset + modulusLength)
        };
        const block = cipher.doFinalSync(input).data;
        blocks.push(block);
        total += block.length;
      }
      // Upstream pre-allocates numBlocks*outputBlockSize and leaves the unused
      // tail zeroed; only the concatenated plaintext is meaningful to scripts
      // (jm-style sources scan for the first '{'), so return exactly that.
      const output = new Uint8Array(total);
      let written = 0;
      for (let i = 0; i < blocks.length; i++) {
        output.set(blocks[i], written);
        written += blocks[i].length;
      }
      return output;
    } catch (error) {
      Log.error('JsMessageHandler', `convert(rsa) failed: ${error}`);
      return null;
    }
  }

  /**
   * PKCS#8 DER private key. Upstream's `_parsePrivateKey` takes a base64
   * string; raw DER bytes are accepted too so a source that hands the key over
   * as an ArrayBuffer (as init.js documents it) still works.
   */
  private static rsaKeyBytes(value: Object | undefined): Uint8Array {
    if (typeof value === 'string') {
      return JsMessageHandler.base64Decode(value as string);
    }
    return JsMessageHandler.toBytes(value);
  }

  /** OHOS key specs are size-tagged, so round the modulus up to a known one. */
  private static rsaKeySpec(bits: number): string {
    if (bits <= 1024) {
      return 'RSA1024';
    }
    if (bits <= 2048) {
      return 'RSA2048';
    }
    if (bits <= 3072) {
      return 'RSA3072';
    }
    if (bits <= 4096) {
      return 'RSA4096';
    }
    if (bits <= 8192) {
      return 'RSA8192';
    }
    return '';
  }

  /**
   * One DER element as [tag, contentStart, contentLength, nextOffset]; empty
   * when the bytes do not hold a complete element.
   */
  private static derElement(bytes: Uint8Array, offset: number): number[] {
    if (offset < 0 || offset + 2 > bytes.length) {
      return [];
    }
    const tag = bytes[offset];
    let position = offset + 1;
    let length = bytes[position];
    position++;
    if ((length & 0x80) !== 0) {
      const count = length & 0x7f;
      if (count === 0 || count > 4 || position + count > bytes.length) {
        return [];
      }
      length = 0;
      for (let i = 0; i < count; i++) {
        length = (length << 8) | bytes[position];
        position++;
      }
    }
    if (position + length > bytes.length) {
      return [];
    }
    return [tag, position, length, position + length];
  }

  /**
   * Modulus length in bytes for a PKCS#8 RSAPrivateKey:
   * SEQ { INTEGER version, SEQ algorithm, OCTET STRING { SEQ { INTEGER 0,
   * INTEGER n, ... } } }. Returns 0 for anything else.
   */
  private static pkcs8ModulusLength(der: Uint8Array): number {
    const outer = JsMessageHandler.derElement(der, 0);
    if (outer.length === 0 || outer[0] !== 0x30) {
      return 0;
    }
    const version = JsMessageHandler.derElement(der, outer[1]);
    if (version.length === 0) {
      return 0;
    }
    const algorithm = JsMessageHandler.derElement(der, version[3]);
    if (algorithm.length === 0 || algorithm[0] !== 0x30) {
      return 0;
    }
    const inner = JsMessageHandler.derElement(der, algorithm[3]);
    if (inner.length === 0 || inner[0] !== 0x04) {
      return 0;
    }
    const pkcs1 = JsMessageHandler.derElement(der, inner[1]);
    if (pkcs1.length === 0 || pkcs1[0] !== 0x30) {
      return 0;
    }
    const pkcs1Version = JsMessageHandler.derElement(der, pkcs1[1]);
    if (pkcs1Version.length === 0) {
      return 0;
    }
    const modulus = JsMessageHandler.derElement(der, pkcs1Version[3]);
    if (modulus.length === 0 || modulus[0] !== 0x02) {
      return 0;
    }
    let length = modulus[2];
    // ASN.1 prepends a zero sign byte to a value whose top bit is set, so a
    // 1024-bit modulus reports 129 bytes here and 128 bits/8 below.
    if (length > 1 && der[modulus[1]] === 0) {
      length--;
    }
    return length;
  }

  private static digest(algorithm: string, value: Object | undefined): Uint8Array {
    const md = cryptoFramework.createMd(algorithm);
    md.updateSync({ data: JsMessageHandler.toBytes(value) });
    return md.digestSync().data;
  }

  private static hmac(algorithm: string, key: Uint8Array, value: Uint8Array): Uint8Array {
    const keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = keyGenerator.convertKeySync({ data: key });
    const mac = cryptoFramework.createMac(algorithm);
    mac.initSync(symKey);
    mac.updateSync({ data: value });
    return mac.doFinalSync().data;
  }

  private static toHex(bytes: Uint8Array): string {
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      const hex = bytes[i].toString(16);
      out += hex.length === 1 ? `0${hex}` : hex;
    }
    return out;
  }

  private static readonly BASE64_CHARS: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  private static base64Encode(bytes: Uint8Array): string {
    const table = JsMessageHandler.BASE64_CHARS;
    let out = '';
    for (let i = 0; i < bytes.length; i += 3) {
      const b0 = bytes[i];
      const has1 = i + 1 < bytes.length;
      const has2 = i + 2 < bytes.length;
      const b1 = has1 ? bytes[i + 1] : 0;
      const b2 = has2 ? bytes[i + 2] : 0;
      out += table[b0 >> 2];
      out += table[((b0 & 3) << 4) | (b1 >> 4)];
      out += has1 ? table[((b1 & 15) << 2) | (b2 >> 6)] : '=';
      out += has2 ? table[b2 & 63] : '=';
    }
    return out;
  }

  private static base64Decode(text: string): Uint8Array {
    const table = JsMessageHandler.BASE64_CHARS;
    const clean = text.replace(new RegExp('[^A-Za-z0-9+/]', 'g'), '');
    const outLength = Math.floor(clean.length * 3 / 4);
    const out = new Uint8Array(outLength);
    let written = 0;
    for (let i = 0; i < clean.length; i += 4) {
      const c0 = table.indexOf(clean[i]);
      const c1 = i + 1 < clean.length ? table.indexOf(clean[i + 1]) : 0;
      const c2 = i + 2 < clean.length ? table.indexOf(clean[i + 2]) : 0;
      const c3 = i + 3 < clean.length ? table.indexOf(clean[i + 3]) : 0;
      if (written < outLength) {
        out[written++] = (c0 << 2) | (c1 >> 4);
      }
      if (written < outLength) {
        out[written++] = ((c1 & 15) << 4) | (c2 >> 2);
      }
      if (written < outLength) {
        out[written++] = ((c2 & 3) << 6) | c3;
      }
    }
    return out;
  }
}
