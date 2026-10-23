/*
 * Bridge between assets/init.js and the native QuickJS runtime.
 *
 * init.js calls the global `sendMessage(object)` and expects either a value or a
 * promise. The native entry point `__nativeSendMessage` now converts values
 * deeply in both directions (entry/src/main/cpp/value_bridge.h), exactly like
 * upstream's flutter_qjs converts Dart values directly, so there is nothing
 * left to serialise here.
 *
 * Historical note: this file used to base64-tag byte payloads, fold `Map`/`Set`
 * into plain objects and JSON.stringify/parse every message. That was lossy in
 * ways upstream never had to deal with, so it is gone. The file is kept as the
 * single place where the native entry point is bound to the name init.js
 * expects.
 */
(() => {
  const native = globalThis.__nativeSendMessage;

  globalThis.sendMessage = function (message) {
    return native(message);
  };
})();
