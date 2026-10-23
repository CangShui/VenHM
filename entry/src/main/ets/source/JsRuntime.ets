/**
 * JS comic-source runtime contract.
 *
 * VeneraNext runs every comic source as a QuickJS script against
 * `assets/init.js`. Reproducing that on HarmonyOS requires a native module that
 * compiles QuickJS and exposes it over NAPI. This file fixes the contract the
 * rest of the port codes against, so the native module can be dropped in
 * without touching the source/UI layers.
 *
 * ---------------------------------------------------------------------------
 * STATUS
 * ---------------------------------------------------------------------------
 * Milestone 1 (done): QuickJS 0.17.0 is compiled into `libvenerajs.so` from
 * entry/src/main/cpp and exposes `quickjsVersion()` + `evaluate(code, name)`.
 * JsEngine.init() runs a smoke script so the UI can prove the engine works.
 *
 * Milestone 2 (next): the `sendMessage` dispatch table below, JSInvokable
 * handles and the ComicSourceParser that turns a script into a live source.
 *
 * ---------------------------------------------------------------------------
 * WHAT THE NATIVE MODULE MUST PROVIDE (contract with assets/init.js)
 * ---------------------------------------------------------------------------
 * `assets/init.js` is kept byte-identical to upstream. It calls exactly one
 * native entry point, the global function `sendMessage(message)`, plus one
 * global variable `appVersion`. The message dispatch table that must be
 * implemented (names and parameter spellings are part of the contract):
 *
 *   method            sync?   parameters
 *   ----------------  ------  ------------------------------------------------
 *   log               sync    level, title, content
 *   load_data         sync    key, data_key
 *   save_data         sync    key, data_key, data        (reject data_key="setting")
 *   delete_data       sync    key, data_key
 *   http              async   url, http_method, headers, data, extra, bytes
 *   html              sync    function + 21 sub-actions (parse/querySelector/...)
 *   convert           sync    type + utf8|gbk|base64|md5|sha1|sha256|sha512|
 *                             hmac|aes-ecb|aes-cbc|aes-cfb|aes-ofb|rsa
 *   random            sync    min, max, type
 *   cookie            sync    function + set|get|delete, url, cookies
 *   uuid              sync    -
 *   load_setting      sync    key, setting_key
 *   isLogged          sync    key
 *   delay             async   time
 *   UI                async   function + showMessage|showDialog|launchUrl|
 *                             showLoading|cancelLoading|showInputDialog|
 *                             showSelectDialog
 *   getLocale         sync    -
 *   getPlatform       sync    -
 *   setClipboard      async   text
 *   getClipboard      async   -
 *   compute           async   function, args
 *   image             sync    (second engine, custom image processing)
 *
 * Additionally required:
 *  - a JS-function handle type equivalent to Dart's `JSInvokable`
 *    (invoke/free/dispose) because sources pass callbacks back (UI.showDialog
 *    actions, showLoading onCancel, showInputDialog validator, dynamic
 *    category loaders, function values inside `settings`);
 *  - zero-copy ArrayBuffer <-> native byte arrays for `convert`/`http` bodies;
 *  - `ComicSource.sources` stays a plain JS registry written by the parser
 *    (`ComicSource.sources[key] = instance`);
 *  - the parser sequence: sourceClassName regex -> instantiate -> read
 *    name/key/version/minAppVersion -> key validation -> register.
 */
import { JsEngine } from './JsEngine';

export interface JsRuntime {
  evaluate(code: string, name?: string): Object | undefined;
  dispose(): void;
}

/**
 * Availability probe used by the UI to explain why JS sources are missing.
 * Backed by the real native module (JsEngine); it reports unavailable only when
 * libvenerajs.so failed to load or the smoke evaluation threw.
 */
export class JsRuntimeStatus {
  static get isAvailable(): boolean {
    return JsEngine.isAvailable;
  }

  static get engineVersion(): string {
    return JsEngine.version;
  }

  static get smokeResult(): string {
    return JsEngine.smoke;
  }

  static get unavailableReason(): string {
    const error = JsEngine.error;
    return error.length > 0
      ? `QuickJS 原生模块加载失败: ${error}`
      : 'QuickJS 原生模块尚未初始化';
  }
}
