#ifndef VENERA_TRACE_CONTEXT_H
#define VENERA_TRACE_CONTEXT_H
#include <string>
#include <cstdint>
#include <new>
#include "quickjs.h"

namespace venera {
// Async context is native-owned and NEVER exposed to source JS. Legacy string
// contexts (notably isolated runtimes) remain valid. The null-prototype envelope
// has only native-defined own data fields: these reads cannot invoke user JS.
inline uint64_t MainCallOwnerOf(JSContext* ctx) {
  JSValueConst context = JS_GetAsyncContext(ctx);
  if (!JS_IsObject(context)) return 0;
  JSValue value = JS_GetPropertyUint32(ctx, context, 1);
  int64_t owner = 0;
  if (JS_IsNumber(value)) JS_ToInt64(ctx, &owner, value);
  JS_FreeValue(ctx, value);
  return owner > 0 ? static_cast<uint64_t>(owner) : 0;
}
inline std::string TraceOf(JSContext* ctx) {
  JSValue value = JS_DupValue(ctx, JS_GetAsyncContext(ctx));
  if (JS_IsObject(value)) {
    JSValue trace = JS_GetPropertyUint32(ctx, value, 0);
    JS_FreeValue(ctx, value); value = trace;
  }
  if (!JS_IsString(value)) { JS_FreeValue(ctx, value); return {}; }
  const char* text = JS_ToCString(ctx, value);
  std::string result = text ? text : "";
  if (text) JS_FreeCString(ctx, text);
  JS_FreeValue(ctx, value);
  return result;
}

/** Jobs/reactions retain the entire native context, not just its public trace. */
class TraceScope {
 public:
  TraceScope(JSContext* ctx, const std::string& trace) : TraceScope(ctx, trace, MainCallOwnerOf(ctx)) {}
  // Explicit zero means unowned; only the two-argument form inherits an owner.
  TraceScope(JSContext* ctx, const std::string& trace, uint64_t owner) : ctx_(ctx),
      previous_(JS_UNDEFINED) {
    JSValue value = trace.empty() ? JS_UNDEFINED : JS_NewStringLen(ctx, trace.data(), trace.size());
    if (JS_IsException(value)) throw std::bad_alloc();
    if (owner) {
      JSValue envelope = JS_NewObjectProto(ctx, JS_NULL);
      // Fail closed rather than execute under a context with a lost owner.
      if (JS_IsException(envelope)) { JS_FreeValue(ctx, value); throw std::bad_alloc(); }
      if (JS_SetPropertyUint32(ctx, envelope, 0, value) < 0 ||
          JS_SetPropertyUint32(ctx, envelope, 1, JS_NewInt64(ctx, static_cast<int64_t>(owner))) < 0) {
        JS_FreeValue(ctx, envelope); throw std::bad_alloc();
      }
      value = envelope;
    }
    previous_ = JS_DupValue(ctx, JS_GetAsyncContext(ctx));
    JS_SetAsyncContext(ctx_, value);
    JS_FreeValue(ctx_, value);
  }
  ~TraceScope() {
    JS_SetAsyncContext(ctx_, previous_);
    JS_FreeValue(ctx_, previous_);
  }
  TraceScope(const TraceScope&) = delete;
  TraceScope& operator=(const TraceScope&) = delete;
 private:
  JSContext* ctx_;
  JSValue previous_;
};
}
#endif
