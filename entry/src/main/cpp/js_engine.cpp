#include "js_engine.h"

namespace venera {

namespace {

/** Convert a JS value to a UTF-8 string; empty string when not convertible. */
std::string ValueToString(JSContext* ctx, JSValueConst value) {
  const char* text = JS_ToCString(ctx, value);
  if (text == nullptr) {
    return std::string();
  }
  std::string out(text);
  JS_FreeCString(ctx, text);
  return out;
}

}  // namespace

QuickJsRuntime::QuickJsRuntime() {
  runtime_ = JS_NewRuntime();
  if (runtime_ == nullptr) {
    return;
  }
  context_ = JS_NewContext(runtime_);
  if (context_ == nullptr) {
    JS_FreeRuntime(runtime_);
    runtime_ = nullptr;
  }
}

QuickJsRuntime::~QuickJsRuntime() {
  if (context_ != nullptr) {
    JS_FreeContext(context_);
    context_ = nullptr;
  }
  if (runtime_ != nullptr) {
    JS_FreeRuntime(runtime_);
    runtime_ = nullptr;
  }
}

bool QuickJsRuntime::EvaluateRaw(const std::string& code, const std::string& filename,
                                 JSValue* out, std::string* error) {
  if (context_ == nullptr) {
    if (error != nullptr) {
      *error = "QuickJS context is not available";
    }
    return false;
  }
  JSValue value = JS_Eval(context_, code.c_str(), code.size(), filename.c_str(),
                          JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(value)) {
    JSValue exception = JS_GetException(context_);
    if (error != nullptr) {
      std::string message = ValueToString(context_, exception);
      if (message.empty()) {
        message = "unknown JavaScript exception";
      }
      JSValue stack = JS_GetPropertyStr(context_, exception, "stack");
      if (!JS_IsUndefined(stack) && !JS_IsNull(stack)) {
        message += "\n";
        message += ValueToString(context_, stack);
      }
      JS_FreeValue(context_, stack);
      *error = message;
    }
    JS_FreeValue(context_, exception);
    JS_FreeValue(context_, value);
    return false;
  }
  // Give queued continuations a chance to run before handing the value back.
  PumpJobs();
  if (out != nullptr) {
    *out = value;
  } else {
    JS_FreeValue(context_, value);
  }
  return true;
}

std::string QuickJsRuntime::JsonStringify(JSValueConst value) {
  if (context_ == nullptr) {
    return std::string("null");
  }
  JSValue global = JS_GetGlobalObject(context_);
  JSValue json = JS_GetPropertyStr(context_, global, "JSON");
  JSValue stringify = JS_GetPropertyStr(context_, json, "stringify");
  std::string out = "null";
  if (JS_IsFunction(context_, stringify)) {
    JSValue result = JS_Call(context_, stringify, json, 1, &value);
    if (JS_IsException(result)) {
      JSValue exception = JS_GetException(context_);
      JS_FreeValue(context_, exception);
    } else {
      const char* text = JS_ToCString(context_, result);
      if (text != nullptr) {
        out.assign(text);
        JS_FreeCString(context_, text);
      }
    }
    JS_FreeValue(context_, result);
  }
  JS_FreeValue(context_, stringify);
  JS_FreeValue(context_, json);
  JS_FreeValue(context_, global);
  return out;
}

void QuickJsRuntime::PumpJobs() {
  if (runtime_ == nullptr) {
    return;
  }
  JSContext* ctx = nullptr;
  int status = 0;
  // JS_ExecutePendingJob returns > 0 while jobs were executed, 0 when the queue
  // is empty and < 0 on error.
  while (JS_IsJobPending(runtime_)) {
    if (job_gate_ && !job_gate_(job_gate_opaque_)) return;
    status = JS_ExecutePendingJob(runtime_, &ctx);
    if (status <= 0) return;
  }
}

bool QuickJsRuntime::Evaluate(const std::string& code, const std::string& filename,
                              std::string* result, std::string* error) {
  JSValue value = JS_UNDEFINED;
  if (!EvaluateRaw(code, filename, &value, error)) {
    return false;
  }
  if (result != nullptr) {
    if (JS_IsUndefined(value)) {
      *result = "undefined";
    } else {
      *result = ValueToString(context_, value);
    }
  }
  JS_FreeValue(context_, value);
  return true;
}

std::string QuickJsRuntime::QuickJsVersion() {
  const char* version = JS_GetVersion();
  return version == nullptr ? std::string("unknown") : std::string(version);
}

}  // namespace venera
