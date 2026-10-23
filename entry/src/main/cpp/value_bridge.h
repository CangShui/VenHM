#ifndef VENERA_VALUE_BRIDGE_H
#define VENERA_VALUE_BRIDGE_H

/*
 * Deep value marshalling between the embedded QuickJS realm and the ArkTS realm.
 *
 * Why this exists: the first bridge carried values as JSON strings, which is
 * lossy in ways the original Flutter build never had to deal with (there,
 * flutter_qjs converts Dart values and JSValue directly). JSON turned `new Map()`
 * into `{}`, turned an ArrayBuffer into `{}`, forced byte payloads through a
 * base64 side-channel and double-stringified strings. Every one of those was a
 * bug class that does not exist upstream.
 *
 * This header implements the faithful conversion instead:
 *   JSValue  -> napi_value   (undefined/null/bool/number/string/ArrayBuffer/
 *                             typed array/Array/plain object/function handle)
 *   napi_value -> JSValue    (the same shapes, plus ArkTS typed arrays)
 *
 * Functions crossing the boundary use type-tagged plain objects with napi_wrap
 * and registry-owned JSValue roots (opaque Dart-JSInvokable-like holders).
 * Raw externals, untagged wrappers and wrong-generation holders are rejected
 * before any native payload dereference; ArkTS only sees an opaque Object.
 */

#include <cstring>
#include <string>

#include "js_engine.h"
#include "napi/native_api.h"
#include "quickjs.h"
#include "trace_context.h"
#include "lifetime_registry.h"
#include <memory>
#include <vector>
#include <algorithm>

namespace venera {

/** Finalizer-only payload. Invocation validates membership BEFORE any dereference. */
struct JsFunctionHandle {
  std::shared_ptr<LifetimeRegistry> registry;
  LifetimeRegistry::RootPtr root;
};
QuickJsRuntime* CurrentRuntime();
std::shared_ptr<LifetimeRegistry> CurrentLifetimeRegistry();
bool IsLifetimeEnvironment(napi_env env);
bool EnterMainRuntimeLease();
void LeaveMainRuntimeLease() noexcept;
/** Wrap every native frame that calls into main QuickJS (worker completion too). */
struct MainRuntimeLease {
  bool held;
  MainRuntimeLease() : held(EnterMainRuntimeLease()) {}
  ~MainRuntimeLease() { if (held) LeaveMainRuntimeLease(); }
  MainRuntimeLease(const MainRuntimeLease&) = delete;
};
inline LifetimeRegistry::RootPtr LookupFunctionHandle(napi_env env, JSContext* ctx, const void* token) {
  auto registry = CurrentLifetimeRegistry();
  if (!IsLifetimeEnvironment(env) || !registry || registry->context() != ctx) return {};
  auto root = registry->LookupExternal(token);
  return root && JS_IsFunction(ctx, root->first) ? root : LifetimeRegistry::RootPtr{};
}
inline constexpr napi_type_tag kFunctionHandleTag{0x2b6c7e9a503d4f11ULL, 0xb4d1860fe82c39a7ULL};
inline bool IsFunctionWrapper(napi_env env, napi_value value) {
  napi_valuetype type = napi_undefined; bool tagged = false;
  return value && napi_typeof(env, value, &type) == napi_ok && type == napi_object &&
    napi_check_object_type_tag(env, value, &kFunctionHandleTag, &tagged) == napi_ok && tagged;
}
inline LifetimeRegistry::RootPtr LookupFunctionValue(napi_env env, JSContext* ctx, napi_value value) {
  void* token = nullptr;
  if (!IsLifetimeEnvironment(env) || !IsFunctionWrapper(env, value) ||
      napi_unwrap(env, value, &token) != napi_ok) return {};
  return LookupFunctionHandle(env, ctx, token); // membership before any token dereference
}
/** Attach lifetime to a PLAIN OBJECT retained by an immutable unique-symbol
 * property on the callback. Ark only guarantees add_finalizer for objects.
 * true transfers data ownership to finalizer; false leaves ownership at caller.
 * The callback must not be exposed until this function has returned true.
 */
inline bool AttachCallbackFinalizer(napi_env env, napi_value callback, void* data, napi_finalize finalize) {
  napi_value anchor = nullptr, symbol = nullptr, description = nullptr;
  if (!data || !finalize || napi_create_object(env, &anchor) != napi_ok ||
      napi_create_string_utf8(env, "Venera callback lifetime", NAPI_AUTO_LENGTH, &description) != napi_ok ||
      napi_create_symbol(env, description, &symbol) != napi_ok) return false;
  napi_property_descriptor property{};
  property.name = symbol; property.value = anchor;
  property.attributes = napi_default; // non-writable, non-enumerable, non-configurable
  if (napi_define_properties(env, callback, 1, &property) != napi_ok) return false;
  return napi_add_finalizer(env, anchor, data, finalize, nullptr, nullptr) == napi_ok;
}
inline void FinalizeFunctionHandle(napi_env, void* data, void*) {
  auto* handle = static_cast<JsFunctionHandle*>(data);
  if (!handle) return;
  handle->registry->ReleaseExternal(data); // no JS touch after registry Shutdown
  delete handle;
}

inline napi_value JsToNapi(napi_env env, JSContext* ctx, JSValueConst value);

inline JSValue NapiToJs(napi_env env, JSContext* ctx, napi_value value);

// Recursive guards execute DURING conversion (not a preflight double-read).
// All nested reads, including mutated getters/iterators, share this budget.
struct BridgeWalk {
  size_t depth = 0, nodes = 0, bytes = 0;
  bool failed = false;
  std::vector<void*> js_path;
  std::vector<napi_value> napi_path;
  bool AddBytes(size_t size) {
    if (size > 64 * 1024 * 1024 - bytes) { failed = true; return false; }
    bytes += size; return true;
  }
};
inline BridgeWalk*& JsBridgeWalk() { static thread_local BridgeWalk* walk = nullptr; return walk; }
inline BridgeWalk*& NapiBridgeWalk() { static thread_local BridgeWalk* walk = nullptr; return walk; }
struct BridgeWalkScope {
  BridgeWalk local;
  BridgeWalk*& slot;
  bool owner;
  size_t js_size, napi_size;
  explicit BridgeWalkScope(BridgeWalk*& state) : slot(state), owner(!state) {
    if (owner) slot = &local;
    js_size = slot->js_path.size(); napi_size = slot->napi_path.size();
    if (++slot->depth > 64 || ++slot->nodes > 65536) slot->failed = true;
  }
  ~BridgeWalkScope() {
    slot->js_path.resize(js_size); slot->napi_path.resize(napi_size); --slot->depth;
    if (owner) slot = nullptr;
  }
};
void MarkRuntimeOwnershipUncertain();
inline size_t TypedArrayElementSize(napi_typedarray_type type);
inline napi_value JsToNapiInner(napi_env env, JSContext* ctx, JSValueConst value);
inline JSValue NapiToJsInner(napi_env env, JSContext* ctx, napi_value value);
inline napi_value JsToNapi(napi_env env, JSContext* ctx, JSValueConst value) {
  BridgeWalkScope scope(JsBridgeWalk()); auto* walk = JsBridgeWalk();
  try {
    if (JS_IsException(value) || JS_IsProxy(value)) walk->failed = true;
    if (JS_IsObject(value)) {
      void* identity = JS_VALUE_GET_PTR(value);
      if (std::find(walk->js_path.begin(), walk->js_path.end(), identity) != walk->js_path.end()) walk->failed = true;
      else walk->js_path.push_back(identity);
    }
    if (JS_IsString(value)) {
      size_t length = 0; const char* text = JS_ToCStringLen(ctx, &length, value);
      if (!text) walk->failed = true; else { walk->AddBytes(length); JS_FreeCString(ctx, text); }
    }
    if (JS_IsArrayBuffer(value)) {
      size_t length = 0; auto* data = JS_GetArrayBuffer(ctx, &length, value);
      if (!data && length) walk->failed = true; walk->AddBytes(length);
    } else if (JS_GetTypedArrayType(value) >= 0) {
      size_t offset = 0, length = 0, size = 0;
      JSValue backing = JS_GetTypedArrayBuffer(ctx, value, &offset, &length, &size);
      if (JS_IsException(backing)) walk->failed = true; else walk->AddBytes(length);
      JS_FreeValue(ctx, backing);
    }
    if (JS_IsArray(value)) {
      JSValue length = JS_GetPropertyStr(ctx, value, "length"); uint32_t count = 0;
      if (JS_IsException(length) || JS_ToUint32(ctx, &count, length) || count > 65536) walk->failed = true;
      JS_FreeValue(ctx, length);
    }
    if (!walk->failed) {
      napi_value result = JsToNapiInner(env, ctx, value); bool pending = false;
      if (result && napi_is_exception_pending(env, &pending) == napi_ok && !pending && !walk->failed && !JS_HasException(ctx)) return result;
      walk->failed = true;
    }
  } catch (...) { MarkRuntimeOwnershipUncertain(); walk->failed = true; }
  JSValue exception = JS_GetException(ctx); JS_FreeValue(ctx, exception);
  bool pending = false; napi_is_exception_pending(env, &pending);
  if (!pending) napi_throw_type_error(env, nullptr, "JS value exceeds bridge limits or is cyclic/unconvertible");
  return nullptr;
}
inline JSValue NapiToJs(napi_env env, JSContext* ctx, napi_value value) {
  BridgeWalkScope scope(NapiBridgeWalk()); auto* walk = NapiBridgeWalk();
  try {
    if (!value) return JS_UNDEFINED;
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type == napi_function || type == napi_symbol) walk->failed = true;
    if (type == napi_object) {
      for (auto ancestor : walk->napi_path) {
        bool same = false;
        if (napi_strict_equals(env, ancestor, value, &same) != napi_ok || same) { walk->failed = true; break; }
      }
      walk->napi_path.push_back(value);
      bool array = false;
      if (napi_is_array(env, value, &array) != napi_ok) walk->failed = true;
      if (array) { uint32_t count = 0; if (napi_get_array_length(env, value, &count) != napi_ok || count > 65536) walk->failed = true; }
      bool buffer = false, typed = false;
      if (napi_is_arraybuffer(env, value, &buffer) != napi_ok || napi_is_typedarray(env, value, &typed) != napi_ok) walk->failed = true;
      if (buffer) { void* data = nullptr; size_t length = 0;
        if (napi_get_arraybuffer_info(env, value, &data, &length) != napi_ok) walk->failed = true; else walk->AddBytes(length); }
      if (typed) { napi_typedarray_type kind; size_t count = 0, offset = 0; void* data = nullptr; napi_value backing = nullptr;
        if (napi_get_typedarray_info(env, value, &kind, &count, &data, &backing, &offset) != napi_ok || count > 64 * 1024 * 1024 / TypedArrayElementSize(kind)) walk->failed = true;
        else walk->AddBytes(count * TypedArrayElementSize(kind));
      }
    } else if (type == napi_string) { size_t length = 0;
      if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) walk->failed = true; else walk->AddBytes(length); }
    if (!walk->failed) {
      JSValue result = NapiToJsInner(env, ctx, value); bool pending = false;
      if (!JS_IsException(result) && napi_is_exception_pending(env, &pending) == napi_ok && !pending && !walk->failed && !JS_HasException(ctx)) return result;
      JS_FreeValue(ctx, result); walk->failed = true;
    }
  } catch (...) { MarkRuntimeOwnershipUncertain(); walk->failed = true; }
  return JS_ThrowTypeError(ctx, "host value exceeds bridge limits or is cyclic/unconvertible");
}

/** Byte width of one element of an ArkTS typed array. */
inline size_t TypedArrayElementSize(napi_typedarray_type type) {
  switch (type) {
    case napi_int8_array:
    case napi_uint8_array:
    case napi_uint8_clamped_array:
      return 1;
    case napi_int16_array:
    case napi_uint16_array:
      return 2;
    case napi_int32_array:
    case napi_uint32_array:
    case napi_float32_array:
      return 4;
    case napi_float64_array:
    case napi_bigint64_array:
    case napi_biguint64_array:
      return 8;
    default:
      return 1;
  }
}

/** True when `value` is an ArkTS `Uint8Array` (the shape source scripts expect). */
inline bool IsUint8ArrayValue(napi_env env, napi_value value) {
  bool isTypedArray = false;
  if (napi_is_typedarray(env, value, &isTypedArray) != napi_ok || !isTypedArray) {
    return false;
  }
  napi_typedarray_type elementType = napi_uint8_array;
  size_t length = 0;
  void* data = nullptr;
  napi_value buffer = nullptr;
  size_t offset = 0;
  if (napi_get_typedarray_info(env, value, &elementType, &length, &data, &buffer, &offset) !=
      napi_ok) {
    return false;
  }
  return elementType == napi_uint8_array || elementType == napi_uint8_clamped_array;
}

/**
 * Builds a QuickJS `Uint8Array` over a copy of `bytes`.
 *
 * Scripts call `.buffer`, `.slice()` and `Convert.hexEncode()` on these values,
 * so handing them a bare ArrayBuffer would break the very byte paths this
 * bridge exists to fix.
 */
inline JSValue NewJsBytes(JSContext* ctx, const uint8_t* bytes, size_t length) {
  JSValue arrayBuffer = JS_NewArrayBufferCopy(ctx, bytes, length);
  if (JS_IsException(arrayBuffer)) {
    return arrayBuffer;
  }
  JSValue global = JS_GetGlobalObject(ctx);
  JSValue ctor = JS_GetPropertyStr(ctx, global, "Uint8Array");
  JS_FreeValue(ctx, global);
  if (!JS_IsFunction(ctx, ctor)) {
    JS_FreeValue(ctx, ctor);
    return arrayBuffer;
  }
  JSValue argument = arrayBuffer;
  JSValue view = JS_CallConstructor(ctx, ctor, 1, &argument);
  JS_FreeValue(ctx, ctor);
  JS_FreeValue(ctx, arrayBuffer);
  return view;
}

inline napi_value JsUndefined(napi_env env) {
  napi_value out = nullptr;
  napi_get_undefined(env, &out);
  return out;
}

/** JSValue -> napi_value. Arrays and objects are converted recursively. */
inline napi_value JsToNapiInner(napi_env env, JSContext* ctx, JSValueConst value) {
  if (JS_IsUndefined(value)) {
    return JsUndefined(env);
  }
  if (JS_IsNull(value)) {
    napi_value out = nullptr;
    napi_get_null(env, &out);
    return out;
  }
  if (JS_IsBool(value)) {
    napi_value out = nullptr;
    napi_get_boolean(env, JS_ToBool(ctx, value) == 1, &out);
    return out;
  }
  if (JS_IsNumber(value)) {
    double number = 0;
    JS_ToFloat64(ctx, &number, value);
    napi_value out = nullptr;
    napi_create_double(env, number, &out);
    return out;
  }
  if (JS_IsBigInt(value)) {
    // ArkTS has no BigInt, so a bigint is carried as its numeric value (the
    // same lossy-but-usable shape JSON.stringify produced).
    int64_t number = 0;
    JS_ToInt64(ctx, &number, value);
    napi_value out = nullptr;
    napi_create_int64(env, number, &out);
    return out;
  }
  if (JS_IsString(value)) {
    const char* text = JS_ToCString(ctx, value);
    napi_value out = nullptr;
    napi_create_string_utf8(env, text == nullptr ? "" : text, NAPI_AUTO_LENGTH, &out);
    if (text != nullptr) {
      JS_FreeCString(ctx, text);
    }
    return out;
  }
  if (JS_IsArrayBuffer(value)) {
    size_t length = 0;
    uint8_t* data = JS_GetArrayBuffer(ctx, &length, value);
    void* target = nullptr;
    napi_value out = nullptr;
    napi_create_arraybuffer(env, length, &target, &out);
    if (data != nullptr && target != nullptr && length > 0) {
      memcpy(target, data, length);
    }
    return out;
  }
  // Typed arrays (Uint8Array is what scripts actually produce) travel as the
  // underlying ArrayBuffer so ArkTS sees real bytes rather than an object.
  // JS_GetTypedArrayBuffer raises a QuickJS exception on a non-typed-array, so
  // the type is probed first - leaving that exception pending corrupted the
  // next evaluation.
  if (JS_GetTypedArrayType(value) >= 0) {
    size_t byteOffset = 0;
    size_t byteLength = 0;
    size_t bytesPerElement = 0;
    JSValue buffer =
        JS_GetTypedArrayBuffer(ctx, value, &byteOffset, &byteLength, &bytesPerElement);
    if (JS_IsException(buffer)) {
      JS_FreeValue(ctx, buffer);
      return JsUndefined(env);
    }
    size_t bufferLength = 0;
    uint8_t* bytes = JS_GetArrayBuffer(ctx, &bufferLength, buffer);
    if ((bytes == nullptr && byteLength > 0) || byteOffset > bufferLength ||
        byteLength > bufferLength - byteOffset) {
      JS_FreeValue(ctx, buffer);
      return JsUndefined(env);
    }
    void* target = nullptr;
    napi_value out = nullptr;
    napi_create_arraybuffer(env, byteLength, &target, &out);
    if (byteLength > 0 && target != nullptr) {
      memcpy(target, bytes + byteOffset, byteLength);
    }
    JS_FreeValue(ctx, buffer);
    return out;
  }

  if (JS_IsFunction(ctx, value)) {
    auto registry = CurrentLifetimeRegistry();
    if (!IsLifetimeEnvironment(env) || !registry || registry->context() != ctx) {
      napi_throw_error(env, nullptr, "function realm is not active"); return nullptr;
    }
    auto root = registry->Own(value, JS_UNDEFINED, TraceOf(ctx));
    JsFunctionHandle* handle = nullptr;
    napi_value out = nullptr;
    try {
      handle = new JsFunctionHandle{registry, root};
      if (napi_create_object(env, &out) != napi_ok ||
          napi_type_tag_object(env, out, &kFunctionHandleTag) != napi_ok ||
          !registry->BindExternal(handle, root) ||
          napi_wrap(env, out, handle, FinalizeFunctionHandle, nullptr, nullptr) != napi_ok) {
        registry->ReleaseExternal(handle); registry->Release(root); delete handle; return nullptr;
      }
    } catch (...) {
      registry->ReleaseExternal(handle); registry->Release(root); delete handle;
      throw;
    }
    return out;
  }

  if (JS_IsArray(value)) {
    JSValue lengthValue = JS_GetPropertyStr(ctx, value, "length");
    int64_t length = 0;
    JS_ToInt64(ctx, &length, lengthValue);
    JS_FreeValue(ctx, lengthValue);
    napi_value out = nullptr;
    napi_create_array_with_length(env, static_cast<size_t>(length), &out);
    for (int64_t i = 0; i < length && !JsBridgeWalk()->failed; i++) {
      JSValue item = JS_GetPropertyUint32(ctx, value, static_cast<uint32_t>(i));
      napi_value converted = JsToNapi(env, ctx, item);
      if (converted) napi_set_element(env, out, static_cast<uint32_t>(i), converted);
      JS_FreeValue(ctx, item);
    }
    return out;
  }

  if (JS_IsObject(value)) {
    // Map/Set are not plain objects. JSON.stringify flattened a Map to {}
    // (silently erasing every chapter list) and a Set to {} as well; read them
    // through their own API so nothing is lost. A Date is left to the generic
    // path below, which stringifies it exactly like JSON.stringify did.
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue mapCtor = JS_GetPropertyStr(ctx, global, "Map");
    JSValue setCtor = JS_GetPropertyStr(ctx, global, "Set");
    const bool isMap = JS_IsFunction(ctx, mapCtor) && JS_IsInstanceOf(ctx, value, mapCtor) == 1;
    const bool isSet = JS_IsFunction(ctx, setCtor) && JS_IsInstanceOf(ctx, value, setCtor) == 1;
    JS_FreeValue(ctx, setCtor);
    JS_FreeValue(ctx, mapCtor);
    JS_FreeValue(ctx, global);

    napi_value out = nullptr;

    if (isSet) {
      // Sets become arrays: that is what the JSON bridge used to produce, so
      // downstream ArkTS keeps seeing a list.
      napi_create_array(env, &out);
      JSValue valuesFn = JS_GetPropertyStr(ctx, value, "values");
      if (JS_IsFunction(ctx, valuesFn)) {
        JSValue iterator = JS_Call(ctx, valuesFn, value, 0, nullptr);
        if (!JS_IsException(iterator)) {
          JSValue nextFn = JS_GetPropertyStr(ctx, iterator, "next");
          uint32_t index = 0;
          while (JS_IsFunction(ctx, nextFn) && !JsBridgeWalk()->failed) {
            if (++JsBridgeWalk()->nodes > 65536) { JsBridgeWalk()->failed = true; break; }
            JSValue step = JS_Call(ctx, nextFn, iterator, 0, nullptr);
            if (JS_IsException(step)) {
              JsBridgeWalk()->failed = true; JS_FreeValue(ctx, step);
              break;
            }
            JSValue done = JS_GetPropertyStr(ctx, step, "done");
            if (JS_IsException(done)) { JsBridgeWalk()->failed = true; JS_FreeValue(ctx, done); JS_FreeValue(ctx, step); break; }
            const bool finished = JS_ToBool(ctx, done) == 1;
            JS_FreeValue(ctx, done);
            if (finished) {
              JS_FreeValue(ctx, step);
              break;
            }
            JSValue item = JS_GetPropertyStr(ctx, step, "value");
            napi_value converted = JsToNapi(env, ctx, item);
            if (converted) napi_set_element(env, out, index++, converted);
            JS_FreeValue(ctx, item);
            JS_FreeValue(ctx, step);
          }
          JS_FreeValue(ctx, nextFn);
        }
        JS_FreeValue(ctx, iterator);
      }
      JS_FreeValue(ctx, valuesFn);
      return out;
    }

    napi_create_object(env, &out);

    if (isMap) {
      JSValue entriesFn = JS_GetPropertyStr(ctx, value, "entries");
      if (JS_IsFunction(ctx, entriesFn)) {
        JSValue iterator = JS_Call(ctx, entriesFn, value, 0, nullptr);
        if (!JS_IsException(iterator)) {
          JSValue nextFn = JS_GetPropertyStr(ctx, iterator, "next");
          while (JS_IsFunction(ctx, nextFn) && !JsBridgeWalk()->failed) {
            if (++JsBridgeWalk()->nodes > 65536) { JsBridgeWalk()->failed = true; break; }
            JSValue step = JS_Call(ctx, nextFn, iterator, 0, nullptr);
            if (JS_IsException(step)) {
              JsBridgeWalk()->failed = true; JS_FreeValue(ctx, step);
              break;
            }
            JSValue done = JS_GetPropertyStr(ctx, step, "done");
            if (JS_IsException(done)) { JsBridgeWalk()->failed = true; JS_FreeValue(ctx, done); JS_FreeValue(ctx, step); break; }
            bool finished = JS_ToBool(ctx, done) == 1;
            JS_FreeValue(ctx, done);
            if (finished) {
              JS_FreeValue(ctx, step);
              break;
            }
            JSValue pair = JS_GetPropertyStr(ctx, step, "value");
            JSValue keyValue = JS_GetPropertyUint32(ctx, pair, 0);
            JSValue entryValue = JS_GetPropertyUint32(ctx, pair, 1);
            size_t key_length = 0;
            const char* key = JS_ToCStringLen(ctx, &key_length, keyValue);
            if (key != nullptr) {
              if (!JsBridgeWalk()->AddBytes(key_length)) { JS_FreeCString(ctx, key); key = nullptr; }
            }
            if (key != nullptr) {
              napi_value converted = JsToNapi(env, ctx, entryValue);
              if (converted) napi_set_named_property(env, out, key, converted);
              JS_FreeCString(ctx, key);
            }
            JS_FreeValue(ctx, keyValue);
            JS_FreeValue(ctx, entryValue);
            JS_FreeValue(ctx, pair);
            JS_FreeValue(ctx, step);
          }
          JS_FreeValue(ctx, nextFn);
        }
        JS_FreeValue(ctx, iterator);
      }
      JS_FreeValue(ctx, entriesFn);
      return out;
    }

    JSPropertyEnum* names = nullptr;
    uint32_t count = 0;
    if (JS_GetOwnPropertyNames(ctx, &names, &count, value,
                               JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) == 0) {
      for (uint32_t i = 0; i < count; i++) {
        JSValue key_value = JsBridgeWalk()->failed ? JS_UNDEFINED : JS_AtomToString(ctx, names[i].atom);
        size_t key_length = 0;
        const char* key = JsBridgeWalk()->failed ? nullptr : JS_ToCStringLen(ctx, &key_length, key_value);
        JS_FreeValue(ctx, key_value);
        if (key && !JsBridgeWalk()->AddBytes(key_length)) { JS_FreeCString(ctx, key); key = nullptr; }
        if (key != nullptr) {
          JSValue item = JS_GetProperty(ctx, value, names[i].atom);
          napi_value converted = JsToNapi(env, ctx, item);
          if (converted) napi_set_named_property(env, out, key, converted);
          JS_FreeValue(ctx, item);
          JS_FreeCString(ctx, key);
        }
        JS_FreeAtom(ctx, names[i].atom);
      }
      js_free(ctx, names);
    }
    return out;
  }

  return JsUndefined(env);
}

/**
 * Name of an object's constructor, or an empty string when there is none.
 *
 * Used to recognise the ArkTS collection types: a `Map` returned by ArkTS has
 * no enumerable own properties, so the generic object walk below would turn it
 * into `{}`.
 */
inline std::string ValueClassName(napi_env env, napi_value value) {
  napi_value constructor = nullptr;
  if (napi_get_named_property(env, value, "constructor", &constructor) != napi_ok ||
      constructor == nullptr) {
    return std::string();
  }
  napi_value name = nullptr;
  if (napi_get_named_property(env, constructor, "name", &name) != napi_ok || name == nullptr) {
    return std::string();
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, name, nullptr, 0, &length) != napi_ok) {
    return std::string();
  }
  if (length > 64 * 1024 * 1024 || (NapiBridgeWalk() && !NapiBridgeWalk()->AddBytes(length))) {
    napi_throw_type_error(env, nullptr, "host class name exceeds bridge byte budget"); return {};
  }
  std::string text(length + 1, '\0');
  napi_get_value_string_utf8(env, name, &text[0], length + 1, &length);
  text.resize(length);
  return text;
}

/** Reads one property by name; the result is JS_UNDEFINED when it is missing. */
inline JSValue NapiProperty(napi_env env, JSContext* ctx, napi_value value, const char* name) {
  napi_value item = nullptr;
  if (napi_get_named_property(env, value, name, &item) != napi_ok || item == nullptr) {
    return JS_UNDEFINED;
  }
  return NapiToJs(env, ctx, item);
}

/** Walks a `Map`/`Set` iterator, calling `emit` for every yielded value. */
template <typename Emit>
inline void ForEachIteratorValue(napi_env env, napi_value container, const char* method,
                                 Emit emit) {
  napi_value iteratorFn = nullptr;
  if (napi_get_named_property(env, container, method, &iteratorFn) != napi_ok ||
      iteratorFn == nullptr) {
    return;
  }
  napi_value iterator = nullptr;
  if (napi_call_function(env, container, iteratorFn, 0, nullptr, &iterator) != napi_ok ||
      iterator == nullptr) {
    return;
  }
  napi_value nextFn = nullptr;
  if (napi_get_named_property(env, iterator, "next", &nextFn) != napi_ok || nextFn == nullptr) {
    return;
  }
  for (;;) {
    if (NapiBridgeWalk()->failed) return;
    napi_value step = nullptr;
    if (napi_call_function(env, iterator, nextFn, 0, nullptr, &step) != napi_ok || step == nullptr) {
      return;
    }
    napi_value done = nullptr;
    bool finished = true;
    if (napi_get_named_property(env, step, "done", &done) == napi_ok && done != nullptr) {
      napi_get_value_bool(env, done, &finished);
    }
    if (finished) {
      return;
    }
    napi_value item = nullptr;
    if (napi_get_named_property(env, step, "value", &item) != napi_ok || item == nullptr) {
      return;
    }
    if (++NapiBridgeWalk()->nodes > 65536) { NapiBridgeWalk()->failed = true; return; }
    emit(item);
  }
}

/**
 * Builds a QuickJS value from an ArkTS `Map` (object with string keys) or
 * `Set` (array), the two collection shapes source scripts expect. Nested
 * collections are handled because the recursion goes through NapiToJs.
 */
inline JSValue NapiCollectionToJs(napi_env env, JSContext* ctx, napi_value value,
                                  bool isSet) {
  if (isSet) {
    JSValue array = JS_NewArray(ctx);
    uint32_t index = 0;
    ForEachIteratorValue(env, value, "values", [&](napi_value item) {
      JSValue converted = NapiToJs(env, ctx, item);
      if (!JS_IsException(converted)) JS_SetPropertyUint32(ctx, array, index++, converted);
    });
    return array;
  }
  JSValue object = JS_NewObject(ctx);
  ForEachIteratorValue(env, value, "entries", [&](napi_value pair) {
    napi_value key = nullptr;
    napi_value item = nullptr;
    if (napi_get_element(env, pair, 0, &key) != napi_ok ||
        napi_get_element(env, pair, 1, &item) != napi_ok) {
      return;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, key, nullptr, 0, &length) != napi_ok) {
      return;
    }
    if (!NapiBridgeWalk()->AddBytes(length)) return;
    std::string name(length + 1, '\0');
    napi_get_value_string_utf8(env, key, &name[0], length + 1, &length);
    name.resize(length);
    JSValue converted = NapiToJs(env, ctx, item);
    if (!JS_IsException(converted)) JS_SetPropertyStr(ctx, object, name.c_str(), converted);
  });
  return object;
}

/** napi_value -> JSValue, the inverse of JsToNapi. */
inline JSValue NapiToJsInner(napi_env env, JSContext* ctx, napi_value value) {
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, value, &type) != napi_ok) {
    return JS_UNDEFINED;
  }
  switch (type) {
    case napi_undefined:
      return JS_UNDEFINED;
    case napi_null:
      return JS_NULL;
    case napi_boolean: {
      bool flag = false;
      napi_get_value_bool(env, value, &flag);
      return JS_NewBool(ctx, flag);
    }
    case napi_number: {
      double number = 0;
      napi_get_value_double(env, value, &number);
      return JS_NewFloat64(ctx, number);
    }
    case napi_string: {
      size_t length = 0;
      napi_get_value_string_utf8(env, value, nullptr, 0, &length);
      // length + 1: napi_get_value_string_utf8 always NUL-terminates, and
      // writing that byte into a length-sized std::string corrupted the heap.
      std::string text(length + 1, '\0');
      napi_get_value_string_utf8(env, value, &text[0], length + 1, &length);
      text.resize(length);
      return JS_NewStringLen(ctx, text.c_str(), length);
    }
    case napi_bigint: {
      int64_t number = 0;
      bool lossless = false;
      napi_get_value_bigint_int64(env, value, &number, &lossless);
      return JS_NewInt64(ctx, number);
    }
    case napi_external:
      return JS_ThrowTypeError(ctx, "raw external callbacks are not trusted function wrappers");
    default:
      break;
  }

  if (type == napi_object && IsFunctionWrapper(env, value)) {
    auto root = LookupFunctionValue(env, ctx, value);
    if (!root) return JS_ThrowTypeError(ctx, "expired or wrong-generation function wrapper");
    return JS_DupValue(ctx, root->first);
  }
  bool isArray = false;
  napi_is_array(env, value, &isArray);
  if (isArray) {
    uint32_t length = 0;
    napi_get_array_length(env, value, &length);
    JSValue array = JS_NewArray(ctx);
    for (uint32_t i = 0; i < length && !NapiBridgeWalk()->failed; i++) {
      napi_value item = nullptr;
      napi_get_element(env, value, i, &item);
      JSValue converted = NapiToJs(env, ctx, item);
      if (!JS_IsException(converted)) JS_SetPropertyUint32(ctx, array, i, converted);
    }
    return array;
  }

  bool isBuffer = false;
  napi_is_arraybuffer(env, value, &isBuffer);
  if (isBuffer) {
    // An ArkTS ArrayBuffer must stay an ArrayBuffer: scripts do
    // `new DataView(resp.body)` and `new Uint8Array(res.body)`, and the first
    // form throws "ArrayBuffer object expected" if handed a typed array.
    void* data = nullptr;
    size_t length = 0;
    napi_get_arraybuffer_info(env, value, &data, &length);
    return JS_NewArrayBufferCopy(ctx, static_cast<const uint8_t*>(data), length);
  }

  bool isTypedArray = false;
  napi_is_typedarray(env, value, &isTypedArray);
  if (isTypedArray) {
    // A typed array stays a Uint8Array: scripts call `.slice()`, `.buffer` and
    // `Convert.hexEncode()` on these.
    napi_typedarray_type elementType = napi_uint8_array;
    size_t elementCount = 0;
    void* data = nullptr;
    napi_value buffer = nullptr;
    size_t offset = 0;
    napi_get_typedarray_info(env, value, &elementType, &elementCount, &data, &buffer, &offset);
    // `elementCount` counts elements, not bytes: treating a Float64Array's 3
    // elements as 3 bytes truncated every non-Uint8 view.
    size_t byteLength = elementCount * TypedArrayElementSize(elementType);
    return NewJsBytes(ctx, static_cast<const uint8_t*>(data), byteLength);
  }

  bool isPromise = false;
  napi_is_promise(env, value, &isPromise);
  if (isPromise) {
    // Promises are handled by the caller (it needs the deferred machinery).
    return JS_UNDEFINED;
  }

  // Plain object: copy enumerable own properties.
  napi_value keys = nullptr;
  if (napi_get_property_names(env, value, &keys) != napi_ok) {
    return JS_UNDEFINED;
  }
  uint32_t count = 0;
  napi_get_array_length(env, keys, &count);
  // ArkTS collections have no enumerable own properties, so they must be read
  // through their own API or a grouped chapter list arrives as `{}` (which is
  // exactly the shape that made ManHuaGui look like a single-chapter comic).
  const std::string className = ValueClassName(env, value);
  if (className == "Map" || className == "WeakMap") {
    return NapiCollectionToJs(env, ctx, value, false);
  }
  if (className == "Set" || className == "WeakSet") {
    return NapiCollectionToJs(env, ctx, value, true);
  }
  JSValue object = JS_NewObject(ctx);
  for (uint32_t i = 0; i < count && !NapiBridgeWalk()->failed; i++) {
    napi_value key = nullptr;
    napi_get_element(env, keys, i, &key);
    std::string name;
    size_t length = 0;
    if (napi_get_value_string_utf8(env, key, nullptr, 0, &length) != napi_ok) {
      continue;
    }
    if (!NapiBridgeWalk()->AddBytes(length)) break;
    name.resize(length + 1);
    napi_get_value_string_utf8(env, key, &name[0], length + 1, &length);
    name.resize(length);
    napi_value item = nullptr;
    if (napi_get_named_property(env, value, name.c_str(), &item) != napi_ok) {
      continue;
    }
    JSValue converted = NapiToJs(env, ctx, item);
    if (!JS_IsException(converted)) JS_SetPropertyStr(ctx, object, name.c_str(), converted);
  }
  return object;
}

}  // namespace venera

#endif  // VENERA_VALUE_BRIDGE_H
