/**
 * Native surface of `libvenerajs.so` (entry/src/main/cpp/napi_init.cpp).
 *
 * Values cross the realm boundary as real objects, converted deeply by
 * value_bridge.h - not as JSON strings. `setMessageHandler` may therefore
 * answer synchronously (load_data / convert / getLocale ...) or with a promise
 * (http / delay / UI ...).
 */
export type JsMessageResult = Object | null | Promise<Object | null>;
export type JsMessageHandler = (message: Object) => JsMessageResult;

export const quickjsVersion: () => string;
/** Aggregate diagnostic counts only; no source names, parameters or credentials. */
export interface RuntimeStats {
  generation: number;
  ownedRoots: number;
  externalHandles: number;
  pendingCalls: number;
  active: boolean;
  activeEntries: number;
  ownershipUncertain: boolean;
  deferredCleanupFailures: number;
}
export const runtimeStats: () => RuntimeStats;
/** UTF-8 text encoded to GBK bytes using a bundled Unicode mapping. */
export const encodeGbk: (text: string) => ArrayBuffer;
export const evaluate: (code: string, filename?: string) => string;
export const setMessageHandler: (handler: JsMessageHandler) => void;
export const setGlobalString: (name: string, value: string) => void;
/**
 * Evaluates in QuickJS and resolves with the result converted deeply.
 * A `Map` arrives as a plain object, `Set` as an array and bytes as a
 * `Uint8Array` - `JSON.stringify` semantics would have flattened a Map to `{}`.
 */
export const callJson: (code: string, filename?: string, trace?: string) => Promise<Object>;
/**
 * Calls a JS function that a script handed to the app (UI dialog actions,
 * validators, dynamic setting loaders). `handle` is the opaque type-tagged,
 * NAPI-wrapped object value_bridge produced for that function (not a raw external).
 * Resolves with the converted return
 * value, awaiting it when the function returns a promise.
 */
export const invokeFunction: (handle: Object, args: Object[], trace?: string) => Promise<Object>;
/** True only for an actual JS callback; plain object/string is not callable. */
export const isFunction: (value: Object) => boolean;
/** Bounded gzip/zlib-or-raw-deflate/Brotli decoder; throws on malformed, truncated or trailing data. */
export const decodeHttpBody: (bytes: ArrayBuffer, encoding: string, byteLimit: number) => ArrayBuffer;
export interface IsolatedPixels { width: number; height: number; rgba: ArrayBuffer; }
/**
 * Main-thread setup, before any source compute or image task. init/html are the
 * same bundled scripts as the main engine. Host RPC and audit callbacks run on
 * the ArkTS/main NAPI thread; workers do not touch ArkTS/NAPI objects off-thread.
 * Function-valued RPC/results cannot be structured-cloned: remote callback
 * proxies and persistent compute-global parity with upstream are NOT supported.
 */
export const configureIsolated: (init: string, html: string, handler: JsMessageHandler,
  audit: (trace: string, phase: string, message: string) => void) => void;
/**
 * Copies first-frame RGBA to an independent image session, runs modifyImage,
 * and returns real straight-RGBA pixels, never an unchanged fallback on error.
 * timeoutMs is native-clamped to 1..60000 (default 10000); rejection includes
 * script failure, cancellation, timeout, queue saturation and memory budget.
 */
export const transformIsolated: (rgba: ArrayBuffer, width: number, height: number,
  script: string, trace: string, premultiplied: boolean, timeoutMs?: number) => Promise<IsolatedPixels>;
/** Marks currently registered native jobs with this exact nonempty trace. */
export const cancelIsolated: (trace: string) => number;
