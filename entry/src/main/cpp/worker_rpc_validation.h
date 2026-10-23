#ifndef VENERA_WORKER_RPC_VALIDATION_H
#define VENERA_WORKER_RPC_VALIDATION_H
#include "quickjs.h"
#include <algorithm>
#include <vector>

namespace venera {
// Worker host RPC uses the existing recursive ArkTS bridge, not the structured
// compute transport. Reject unsafe trees instead of overflowing its UI stack.
inline bool CheckWorkerRpcTreeImpl(JSContext* ctx, JSValueConst value,
                                   std::vector<void*>& path, size_t& nodes) {
  if (++nodes > 65536 || path.size() >= 64) return false;
  if (!JS_IsObject(value)) return !JS_IsException(value) && !JS_IsBigInt(value);
  if (JS_IsArrayBuffer(value)) {
    size_t length = 0;
    auto* bytes = JS_GetArrayBuffer(ctx, &length, value);
    return (bytes || !length) && length <= 64 * 1024 * 1024;
  }
  if (JS_GetTypedArrayType(value) >= 0) {
    size_t offset = 0, length = 0, element = 0;
    JSValue buffer = JS_GetTypedArrayBuffer(ctx, value, &offset, &length, &element);
    bool ok = !JS_IsException(buffer) && length <= 64 * 1024 * 1024;
    JS_FreeValue(ctx, buffer); return ok;
  }
  if (JS_IsProxy(value) || JS_IsFunction(ctx, value)) return false;
  if (JS_IsArray(value)) {
    JSValue size = JS_GetPropertyStr(ctx, value, "length"); uint32_t length = 0;
    bool ok = !JS_IsException(size) && JS_ToUint32(ctx, &length, size) == 0 && length <= 65536;
    JS_FreeValue(ctx, size); if (!ok) return false;
  }
  JSValue plain = JS_NewObject(ctx), array = JS_NewArray(ctx);
  bool allowed = !JS_IsException(plain) && !JS_IsException(array) &&
    (JS_GetClassID(value) == JS_GetClassID(plain) || JS_GetClassID(value) == JS_GetClassID(array));
  JS_FreeValue(ctx, plain); JS_FreeValue(ctx, array);
  if (!allowed) return false; // Map/Set/exotics require an identity-aware bridge.
  void* identity = JS_VALUE_GET_PTR(value);
  if (std::find(path.begin(), path.end(), identity) != path.end()) return false;
  path.push_back(identity);
  JSPropertyEnum* names = nullptr; uint32_t count = 0;
  bool ok = JS_GetOwnPropertyNames(ctx, &names, &count, value, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) == 0;
  if (ok && count > 65536 - nodes) ok = false;
  for (uint32_t i = 0; i < count; ++i) {
    if (ok) {
      JSPropertyDescriptor desc{};
      int found = JS_GetOwnProperty(ctx, &desc, value, names[i].atom);
      if (found < 0) ok = false;
      else if (found) {
        ok = !(desc.flags & JS_PROP_GETSET) && CheckWorkerRpcTreeImpl(ctx, desc.value, path, nodes);
        JS_FreeValue(ctx, desc.value); JS_FreeValue(ctx, desc.getter); JS_FreeValue(ctx, desc.setter);
      }
    }
    JS_FreeAtom(ctx, names[i].atom);
  }
  js_free(ctx, names); path.pop_back(); return ok;
}
inline bool CheckWorkerRpcTree(JSContext* ctx, JSValueConst value) {
  std::vector<void*> path; path.reserve(64); size_t nodes = 0;
  return CheckWorkerRpcTreeImpl(ctx, value, path, nodes);
}
}
#endif
