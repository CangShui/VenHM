/*
 * NAPI entry point for the Venera HM JavaScript runtime.
 *
 * ArkTS imports this as `libvenerajs.so`.
 *
 * REALM NOTE (important): the app's ArkTS code and the embedded QuickJS engine
 * are two different JavaScript realms. `napi_get_global()` returns the ArkTS
 * global object, which source scripts running inside QuickJS cannot see. So:
 *   - globals needed by scripts (sendMessage, appVersion) are installed on the
 *     *QuickJS* global object;
 *   - values crossing the boundary are converted deeply by value_bridge.h, the
 *     same way flutter_qjs converts Dart values directly. JSON strings are NOT
 *     used any more: they turned `new Map()` into `{}` and ArrayBuffer into `{}`.
 *
 * Exported surface:
 *   quickjsVersion(): string
 *   evaluate(code, name?): string
 *   callJson(code, name?): Promise<Object>   evaluate in QuickJS and resolve with
 *                                            the value converted deeply (Map and
 *                                            byte payloads survive)
 *   setMessageHandler(fn): void              fn(message: Object) -> Object |
 *                                            null | Promise<Object | null>;
 *                                            installed into QuickJS as
 *                                            __nativeSendMessage
 *   setGlobalString(name, value): void       define a QuickJS global
 *   isFunction(value): boolean              distinguish callback handles from malformed configs
 */
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>
#include <new>
#include <cmath>
#include <memory>
#include <mutex>
#include <chrono>
#include <cstdlib>
#include "lifetime_registry.h"

#include "gbk_table.h"
#include "js_engine.h"
#include "napi/native_api.h"
#include "value_bridge.h"
#include "trace_context.h"
#include "http_decoding.h"
#include "worker_napi.h"

namespace {

venera::QuickJsRuntime* g_runtime = nullptr;
napi_env g_env = nullptr;
napi_ref g_message_handler = nullptr;
napi_env g_owner_env = nullptr;
uint64_t g_generation = 0;
bool g_closing = false, g_ever_initialized = false, g_ownership_uncertain = false;
venera::QuickJsRuntime* g_retained_on_fault = nullptr;
size_t g_active_entries = 0, g_deferred_cleanup_failures = 0;
std::mutex g_init_mutex;
venera::QuickJsRuntime* g_deferred_destroy = nullptr;
std::shared_ptr<venera::LifetimeRegistry> g_lifetime;
std::shared_ptr<venera::LifetimeRegistry> g_deferred_lifetime;
// Fixed native policy, not a source-controlled/public deadline option. One budget
// spans an uninterrupted outer entry AND its nested drains/callbacks. No lease is
// held during an asynchronous HTTP wait, so network elapsed time is not charged.
constexpr auto kMainEntryBudget = std::chrono::seconds(5);
constexpr size_t kMainDrainJobQuota = 4096;
struct MainBudget {
  std::chrono::steady_clock::time_point deadline;
  size_t jobs = 0;
  uint64_t interrupted_owner = 0;
  bool interrupted = false, yielded = false;
};
MainBudget g_main_budget;
napi_async_work g_pump_work = nullptr;
size_t g_main_interruptions = 0, g_main_drain_yields = 0, g_main_pump_schedule_failures = 0;
void ScheduleMainPump() noexcept;
void CleanupEnvironment(void* data);
void FailMainPump() noexcept;
void RecoverInterruptedCalls() noexcept;
void RejectOwnerCalls(uint64_t owner, const char* reason) noexcept;
int MainInterrupt(JSContext* ctx, void*) {
  if (!g_active_entries || std::chrono::steady_clock::now() < g_main_budget.deadline) return 0;
  if (!g_main_budget.interrupted) {
    g_main_budget.interrupted_owner = venera::MainCallOwnerOf(ctx);
    ++g_main_interruptions;
  }
  g_main_budget.interrupted = true;
  return 1;
}
bool MainJobGate(void*) {
  if (!g_active_entries) return false;
  if (g_closing || g_main_budget.interrupted || ++g_main_budget.jobs > kMainDrainJobQuota ||
      std::chrono::steady_clock::now() >= g_main_budget.deadline) {
    if (!g_main_budget.yielded) ++g_main_drain_yields;
    g_main_budget.yielded = true;
    return false; // Keep the queue intact; resume on a later host event-loop turn.
  }
  return true;
}
void FinishDeferredDestroy() noexcept {
  if (g_active_entries || !g_deferred_destroy) return;
  g_deferred_lifetime->Shutdown();
  auto* runtime = g_deferred_destroy; g_deferred_destroy = nullptr;
  if (g_ownership_uncertain) g_retained_on_fault = runtime;
  else delete runtime;
  g_deferred_lifetime.reset();
}

// One deferred per callJson invocation. A single global deferred caused two
// overlapping source requests to resolve the wrong promise (or hang forever).
struct PendingCall {
  napi_env env;
  napi_deferred deferred;
  uint64_t generation;
  uint64_t owner;
  venera::LifetimeRegistry::RootPtr root;
};
uint64_t g_next_owner = 1;
uint64_t NewMainCallOwner() {
  // Stored as a QuickJS number: never round/reuse an owner after 2^53-1.
  return g_next_owner <= 9007199254740991ULL ? g_next_owner++ : 0;
}
std::unordered_map<int64_t, PendingCall> g_pending_calls;
int64_t g_next_call_id = 1;

venera::QuickJsRuntime* Runtime() {
  if (g_closing || !g_owner_env) return nullptr;
  if (g_runtime == nullptr) {
    auto runtime = std::make_unique<venera::QuickJsRuntime>();
    if (!runtime->IsValid()) return nullptr;
    g_lifetime = std::make_shared<venera::LifetimeRegistry>(runtime->context(), g_generation);
    runtime->SetJobPumpGate(MainJobGate, nullptr);
    g_runtime = runtime.release();
  }
  return g_runtime;
}

}  // namespace

namespace venera {

QuickJsRuntime* CurrentRuntime() {
  return g_runtime; // Finalizers must never resurrect a runtime during teardown.
}
std::shared_ptr<LifetimeRegistry> CurrentLifetimeRegistry() { return g_lifetime; }
void MarkRuntimeOwnershipUncertain() { g_ownership_uncertain = true; }
bool EnterMainRuntimeLease() {
  if (g_closing || !g_runtime) return false;
  if (!g_active_entries) {
    g_main_budget = MainBudget{};
    g_main_budget.deadline = std::chrono::steady_clock::now() + kMainEntryBudget;
    JS_SetInterruptHandler(g_runtime->runtime(), MainInterrupt, nullptr);
  }
  ++g_active_entries; return true;
}
void LeaveMainRuntimeLease() noexcept {
  if (g_active_entries == 1) {
    // Cleanup may already have moved the runtime out of public lookup. Disarm
    // while it is still alive, BEFORE the final active lease permits destruction.
    auto* runtime = g_runtime ? g_runtime : g_deferred_destroy;
    if (runtime) JS_SetInterruptHandler(runtime->runtime(), nullptr, nullptr);
    if (!g_closing && g_main_budget.interrupted) RecoverInterruptedCalls();
    if (!g_closing && runtime && JS_IsJobPending(runtime->runtime())) ScheduleMainPump();
  }
  if (g_active_entries) --g_active_entries;
  FinishDeferredDestroy();
}
bool IsLifetimeEnvironment(napi_env env) {
  return env && env == g_owner_env && !g_closing && g_lifetime && g_lifetime->Active();
}

}  // namespace venera

namespace {

bool ReadString(napi_env env, napi_value value, std::string* out) {
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
    return false;
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return false;
  }
  std::vector<char> buffer(length + 1, '\0');
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &written) != napi_ok) {
    return false;
  }
  out->assign(buffer.data(), written);
  return true;
}

std::string TakePendingException(napi_env env) {
  bool pending = false;
  napi_is_exception_pending(env, &pending);
  if (!pending) {
    return std::string();
  }
  napi_value exception = nullptr;
  if (napi_get_and_clear_last_exception(env, &exception) != napi_ok || exception == nullptr) {
    return std::string("unknown exception");
  }
  napi_value message = nullptr;
  if (napi_get_named_property(env, exception, "message", &message) == napi_ok) {
    std::string text;
    if (ReadString(env, message, &text) && !text.empty()) {
      return text;
    }
  }
  napi_value asString = nullptr;
  if (napi_coerce_to_string(env, exception, &asString) == napi_ok) {
    std::string text;
    if (ReadString(env, asString, &text) && !text.empty()) {
      return text;
    }
  }
  return std::string("unknown exception");
}

void ThrowError(napi_env env, const std::string& message) {
  napi_value text = nullptr;
  napi_value error = nullptr;
  napi_create_string_utf8(env, message.c_str(), message.size(), &text);
  napi_create_error(env, nullptr, text, &error);
  napi_throw(env, error);
}

/** UTF-8 -> GBK. ArkTS TextEncoder supports UTF-8 only. */
napi_value DecodeBody(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  bool arraybuffer = false;
  if (argc < 3 || napi_is_arraybuffer(env, args[0], &arraybuffer) != napi_ok || !arraybuffer) {
    ThrowError(env, "decodeHttpBody expects ArrayBuffer, encoding, byte limit");
    return nullptr;
  }
  std::string encoding;
  uint32_t limit = 0;
  double numeric_limit = 0;
  if (!ReadString(env, args[1], &encoding) || napi_get_value_uint32(env, args[2], &limit) != napi_ok ||
      napi_get_value_double(env, args[2], &numeric_limit) != napi_ok ||
      !std::isfinite(numeric_limit) || numeric_limit != limit || limit == 0 || limit > 512 * 1024 * 1024) {
    ThrowError(env, "invalid compressed response byte limit");
    return nullptr;
  }
  void* bytes = nullptr; size_t length = 0;
  napi_get_arraybuffer_info(env, args[0], &bytes, &length);
  std::vector<uint8_t> decoded; std::string error;
  try {
    if (!venera::DecodeHttpBody(static_cast<uint8_t*>(bytes), length, encoding, limit, &decoded, &error)) {
      ThrowError(env, error);
      return nullptr;
    }
  } catch (const std::bad_alloc&) {
    ThrowError(env, "native HTTP decoder allocation failed");
    return nullptr;
  }
  napi_value result = nullptr; void* destination = nullptr;
  if (napi_create_arraybuffer(env, decoded.size(), &destination, &result) != napi_ok) {
    ThrowError(env, "cannot allocate decoded HTTP response");
    return nullptr;
  }
  if (!decoded.empty()) memcpy(destination, decoded.data(), decoded.size());
  return result;
}

napi_value EncodeGbk(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  std::string input;
  if (argc != 1 || !ReadString(env, args[0], &input)) {
    ThrowError(env, "encodeGbk expects one string");
    return nullptr;
  }
  std::string output;
  output.reserve(input.size());
  for (size_t i = 0; i < input.size();) {
    const uint8_t lead = static_cast<uint8_t>(input[i]);
    if (lead < 0x80) {
      output.push_back(static_cast<char>(lead));
      ++i;
      continue;
    }
    int continuationCount = 0;
    uint32_t point = 0;
    uint32_t minimum = 0;
    if ((lead & 0xe0) == 0xc0) {
      continuationCount = 1; point = lead & 0x1f; minimum = 0x80;
    } else if ((lead & 0xf0) == 0xe0) {
      continuationCount = 2; point = lead & 0x0f; minimum = 0x800;
    } else if ((lead & 0xf8) == 0xf0) {
      continuationCount = 3; point = lead & 0x07; minimum = 0x10000;
    } else {
      ThrowError(env, "Invalid UTF-8 in GBK input");
      return nullptr;
    }
    if (i + continuationCount >= input.size()) {
      ThrowError(env, "Truncated UTF-8 in GBK input");
      return nullptr;
    }
    for (int j = 0; j < continuationCount; ++j) {
      const uint8_t tail = static_cast<uint8_t>(input[i + j + 1]);
      if ((tail & 0xc0) != 0x80) {
        ThrowError(env, "Invalid UTF-8 continuation in GBK input");
        return nullptr;
      }
      point = (point << 6) | (tail & 0x3f);
    }
    i += static_cast<size_t>(continuationCount + 1);
    if (point < minimum || point >= 0x10000 || (point >= 0xd800 && point <= 0xdfff)) {
      ThrowError(env, "GBK cannot encode the supplied Unicode character");
      return nullptr;
    }
    size_t low = 0;
    size_t high = venera::kGbkPairCount;
    while (low < high) {
      const size_t mid = low + (high - low) / 2;
      if (venera::kGbkPairs[mid] >> 16 < point) low = mid + 1;
      else high = mid;
    }
    if (low >= venera::kGbkPairCount || (venera::kGbkPairs[low] >> 16) != point) {
      ThrowError(env, "GBK cannot encode the supplied Unicode character");
      return nullptr;
    }
    const uint16_t pair = static_cast<uint16_t>(venera::kGbkPairs[low]);
    output.push_back(static_cast<char>(pair >> 8));
    output.push_back(static_cast<char>(pair & 0xff));
  }
  const size_t length = output.size();
  napi_value result = nullptr;
  void* bytes = nullptr;
  if (napi_create_arraybuffer(env, length, &bytes, &result) != napi_ok) {
    ThrowError(env, "Cannot allocate GBK output buffer");
    return nullptr;
  }
  if (length > 0) memcpy(bytes, output.data(), length);
  return result;
}

// ---------------------------------------------------------------- callJson

void RejectDeferred(napi_env env, napi_deferred deferred, const char* message) {
  bool pending = false; napi_is_exception_pending(env, &pending);
  if (pending) { napi_value ignored; napi_get_and_clear_last_exception(env, &ignored); }
  napi_value reason = nullptr;
  if (napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &reason) == napi_ok)
    napi_reject_deferred(env, deferred, reason);
}
constexpr const char* kMainInterrupted = "main QuickJS execution interrupted: 5s uninterrupted CPU-wall budget";
void RecoverInterruptedCalls() noexcept {
  // QuickJS intentionally leaves async functions pending after an uncatchable
  // interrupt. Settle ONLY their private owner, never all calls with a trace.
  // No JS conversion/getter/stringification is allowed during this recovery.
  if (g_runtime) {
    JSValue error = JS_GetException(g_runtime->context());
    JS_FreeValue(g_runtime->context(), error);
  }
  RejectOwnerCalls(g_main_budget.interrupted_owner, kMainInterrupted);
}
void RejectOwnerCalls(uint64_t owner, const char* reason) noexcept {
  if (!owner || !g_lifetime) return;
  auto registry = g_lifetime;
  for (auto it = g_pending_calls.begin(); it != g_pending_calls.end();) {
    if (it->second.owner != owner) { ++it; continue; }
    PendingCall pending = it->second;
    it = g_pending_calls.erase(it); // Inert before settlement/root release.
    if (!g_closing && pending.env == g_owner_env) RejectDeferred(pending.env, pending.deferred, reason);
    registry->Release(pending.root);
  }
}
bool HostPumpFault(const char* stage) {
#ifdef VENERA_HOST_NAPI_TESTS
  // Compiled only with tools/napi_host_tests headers, never the SDK build.
  const char* fault = std::getenv("VENERA_HOST_MAIN_PUMP_FAULT");
  return fault && std::strcmp(fault, stage) == 0;
#else
  return false;
#endif
}
void FailMainPump() noexcept {
  if (g_closing || !g_owner_env) return;
  ++g_main_pump_schedule_failures;
  // A broken host scheduler is a GLOBAL backend failure, not a CPU timeout of
  // an arbitrary trace. Fail closed explicitly rather than orphan queued roots.
  napi_env env = g_owner_env;
  auto registry = g_lifetime;
  while (!g_pending_calls.empty()) {
    auto it = g_pending_calls.begin();
    PendingCall pending = it->second; g_pending_calls.erase(it);
    RejectDeferred(env, pending.deferred, "main QuickJS continuation scheduler failed; runtime closed");
    if (registry) registry->Release(pending.root);
  }
  CleanupEnvironment(env); // Active lease keeps context alive until final unwind.
}
void MainPumpExecute(napi_env, void*) {} // Host threadpool only posts a completion.
void MainPumpComplete(napi_env env, napi_status status, void*) {
  napi_async_work work = g_pump_work; g_pump_work = nullptr;
  if (work) napi_delete_async_work(env, work);
  if (env != g_owner_env || g_closing) return;
  if (status != napi_ok || HostPumpFault("complete")) { FailMainPump(); return; }
  venera::MainRuntimeLease lease;
  if (lease.held && g_runtime) g_runtime->PumpJobs();
}
void ScheduleMainPump() noexcept {
  if (g_pump_work || g_closing || !g_owner_env) return;
  napi_value name = nullptr;
  if (HostPumpFault("name") || napi_create_string_utf8(g_owner_env, "VeneraMainJobDrain", NAPI_AUTO_LENGTH, &name) != napi_ok) { FailMainPump(); return; }
  napi_async_work work = nullptr;
  if (HostPumpFault("create") || napi_create_async_work(g_owner_env, nullptr, name, MainPumpExecute, MainPumpComplete, nullptr, &work) != napi_ok) { FailMainPump(); return; }
  if (HostPumpFault("queue") || napi_queue_async_work(g_owner_env, work) != napi_ok) { napi_delete_async_work(g_owner_env, work); FailMainPump(); return; }
  g_pump_work = work; // At most one queued resumption; no busy host polling loop.
}
bool ConversionFailed(napi_env env, napi_value value) {
  bool pending = false;
  return !value || napi_is_exception_pending(env, &pending) != napi_ok || pending;
}
void FinishPending(JSContext* ctx, int argc, JSValueConst* argv, JSValueConst* data, bool reject) {
  int64_t id = 0, generation = 0;
  if (JS_ToInt64(ctx, &id, data[0]) || JS_ToInt64(ctx, &generation, data[1])) return;
  auto found = g_pending_calls.find(id);
  if (found == g_pending_calls.end() || g_closing || !g_lifetime ||
      ctx != g_lifetime->context() || generation != static_cast<int64_t>(g_generation) ||
      found->second.generation != g_generation || found->second.env != g_owner_env) return;
  auto registry = g_lifetime;
  PendingCall pending = found->second;
  g_pending_calls.erase(found); // Claim before conversion/user getters/reentrant callbacks.
  try {
    if (reject) {
      JSValueConst reason = argc ? argv[0] : JS_UNDEFINED;
      const char* text = JS_ToCString(ctx, reason);
      if (!text) { JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error); }
      if (!g_closing && pending.env == g_owner_env)
        RejectDeferred(pending.env, pending.deferred, text ? text : "JavaScript error");
      if (text) JS_FreeCString(ctx, text);
    } else {
      napi_value value = venera::JsToNapi(pending.env, ctx, argc ? argv[0] : JS_UNDEFINED);
      if (g_closing || pending.env != g_owner_env) { registry->Release(pending.root); return; }
      if (ConversionFailed(pending.env, value)) RejectDeferred(pending.env, pending.deferred, "JS result cannot cross realm");
      else napi_resolve_deferred(pending.env, pending.deferred, value);
    }
  } catch (...) { RejectDeferred(pending.env, pending.deferred, "JS result allocation failed"); }
  registry->Release(pending.root);
}
JSValue OnJsSettled(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv, int, JSValueConst* data) {
  venera::MainRuntimeLease lease;
  if (lease.held) FinishPending(ctx, argc, argv, data, false); return JS_UNDEFINED;
}
JSValue OnJsRejected(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv, int, JSValueConst* data) {
  venera::MainRuntimeLease lease;
  if (lease.held) FinishPending(ctx, argc, argv, data, true); return JS_UNDEFINED;
}
void SettleJsResult(napi_env env, napi_deferred deferred, JSValue value) {
  JSContext* ctx = Runtime()->context();
  auto registry = g_lifetime;
  JSValue then = JS_IsObject(value) ? JS_GetPropertyStr(ctx, value, "then") : JS_UNDEFINED;
  if (g_closing) { JS_FreeValue(ctx, then); return; }
  if (JS_IsException(then)) {
    JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
    RejectDeferred(env, deferred, "then lookup failed");
  } else if (JS_IsFunction(ctx, then)) {
    int64_t id = g_next_call_id++;
    venera::LifetimeRegistry::RootPtr root;
    try {
      root = registry->Own(value, then, venera::TraceOf(ctx));
      g_pending_calls.emplace(id, PendingCall{env, deferred, g_generation, venera::MainCallOwnerOf(ctx), root});
    } catch (...) { registry->Release(root); JS_FreeValue(ctx, then); throw; }
    JSValue data[2] = {JS_NewInt64(ctx, id), JS_NewInt64(ctx, static_cast<int64_t>(g_generation))};
    JSValue callbacks[2] = {
      JS_NewCFunctionData2(ctx, OnJsSettled, "onResolve", 1, 0, 2, data),
      JS_NewCFunctionData2(ctx, OnJsRejected, "onReject", 1, 0, 2, data)};
    JS_FreeValue(ctx, data[0]); JS_FreeValue(ctx, data[1]);
    JSValue ignored = JS_EXCEPTION;
    if (!JS_IsException(callbacks[0]) && !JS_IsException(callbacks[1]))
      ignored = JS_Call(ctx, then, value, 2, callbacks);
    if (JS_IsException(ignored)) {
      JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
      auto found = g_pending_calls.find(id);
      if (found != g_pending_calls.end()) {
        auto pending = found->second; g_pending_calls.erase(found); registry->Release(pending.root);
        RejectDeferred(env, deferred, "then() failed");
      }
    }
    JS_FreeValue(ctx, ignored); JS_FreeValue(ctx, callbacks[0]); JS_FreeValue(ctx, callbacks[1]);
    if (!g_closing && g_runtime) g_runtime->PumpJobs();
  } else {
    napi_value result = venera::JsToNapi(env, ctx, value);
    if (g_closing || env != g_owner_env) { JS_FreeValue(ctx, then); return; }
    if (ConversionFailed(env, result)) RejectDeferred(env, deferred, "JS result cannot cross realm");
    else napi_resolve_deferred(env, deferred, result);
  }
  JS_FreeValue(ctx, then);
}

napi_value CallJson(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 3;
  napi_value args[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  napi_value promise = nullptr;
  napi_deferred deferred = nullptr;
  napi_create_promise(env, &deferred, &promise);

  std::string code;
  std::string filename = "<call>";
  if (argc < 1 || !ReadString(env, args[0], &code)) {
    const std::string message = "callJson requires a code string";
    napi_value text = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &text);
    napi_reject_deferred(env, deferred, text);
    return promise;
  }
  if (argc >= 2 && args[1] != nullptr) {
    std::string provided;
    if (ReadString(env, args[1], &provided) && !provided.empty()) {
      filename = provided;
    }
  }

  JSValue value = JS_UNDEFINED;
  std::string error;
  std::string trace;
  if (argc >= 3) ReadString(env, args[2], &trace);
  JSContext* ctx = Runtime()->context();
  const uint64_t owner = NewMainCallOwner();
  if (!owner) { RejectDeferred(env, deferred, "main QuickJS private call owner exhausted"); return promise; }
  venera::TraceScope trace_scope(ctx, trace, owner);
  if (!Runtime()->EvaluateRaw(code, filename, &value, &error)) {
    napi_value text = nullptr;
    napi_create_string_utf8(env, error.c_str(), error.size(), &text);
    napi_reject_deferred(env, deferred, text);
    return promise;
  }

  if (g_main_budget.interrupted && g_main_budget.interrupted_owner == owner) {
    JS_FreeValue(ctx, value);
    RejectDeferred(env, deferred, kMainInterrupted);
    return promise;
  }
  try { if (!g_closing) SettleJsResult(env, deferred, value); }
  catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing) RejectDeferred(env, deferred, "JS result ownership allocation failed");
  }
  JS_FreeValue(ctx, value);
  return promise;
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

/**
 * invokeFunction(handle, args) -> Promise<Object>
 *
 * Source scripts hand callbacks to the app (UI dialog actions, validators,
 * dynamic setting loaders). value_bridge converts a JS function into an
 * external handle, which ArkTS cannot call by itself; this is the missing half
 * of that round trip.
 */
napi_value IsFunction(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  JSContext* ctx = Runtime()->context();
  bool callable = argc && venera::LookupFunctionValue(env, ctx, args[0]);
  napi_value result = nullptr;
  napi_get_boolean(env, callable, &result);
  return result;
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

napi_value InvokeFunction(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 3;
  napi_value args[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  napi_value promise = nullptr;
  napi_deferred deferred = nullptr;
  napi_create_promise(env, &deferred, &promise);

  JSContext* ctx = Runtime()->context();
  std::string trace;
  if (argc >= 3) ReadString(env, args[2], &trace);
  if (trace.empty() && argc > 0) {
    auto root = venera::LookupFunctionValue(env, ctx, args[0]);
    if (root) trace = root->trace;
  }
  const uint64_t owner = NewMainCallOwner();
  if (!owner) { RejectDeferred(env, deferred, "main QuickJS private call owner exhausted"); return promise; }
  venera::TraceScope trace_scope(ctx, trace, owner);
  JSValue function = JS_UNDEFINED;
  if (argc >= 1 && args[0] != nullptr) {
    function = venera::NapiToJs(env, ctx, args[0]);
  }
  if (!JS_IsFunction(ctx, function)) {
    JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
    RejectDeferred(env, deferred, "invokeFunction requires a live JS function handle");
    JS_FreeValue(ctx, function); return promise;
  }

  std::vector<JSValue> callArgs;
  JSValue array = argc >= 2 && args[1] ? venera::NapiToJs(env, ctx, args[1]) : JS_UNDEFINED;
  bool args_ok = !JS_IsException(array) && (argc < 2 || !args[1] || JS_IsArray(array));
  try {
    if (JS_IsArray(array)) {
      JSValue size = JS_GetPropertyStr(ctx, array, "length"); uint32_t length = 0;
      args_ok = JS_ToUint32(ctx, &length, size) == 0 && length <= 65536;
      JS_FreeValue(ctx, size);
      if (args_ok) {
        callArgs.reserve(length);
        for (uint32_t i = 0; i < length; ++i) callArgs.push_back(JS_GetPropertyUint32(ctx, array, i));
      }
    }
  } catch (...) { args_ok = false; }
  JS_FreeValue(ctx, array);
  if (!args_ok || g_closing) {
    for (auto& item : callArgs) JS_FreeValue(ctx, item);
    JS_FreeValue(ctx, function);
    JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
    if (!g_closing) RejectDeferred(env, deferred, "callback arguments cannot cross realm");
    return promise;
  }

  JSValue result = JS_Call(ctx, function, JS_UNDEFINED,
                           static_cast<int>(callArgs.size()),
                           callArgs.empty() ? nullptr : callArgs.data());
  for (auto& item : callArgs) {
    JS_FreeValue(ctx, item);
  }
  JS_FreeValue(ctx, function);

  if (JS_IsException(result)) {
    JSValue exception = JS_GetException(ctx);
    const char* text = JS_ToCString(ctx, exception);
    if (!text) { JSValue nested = JS_GetException(ctx); JS_FreeValue(ctx, nested); }
    if (!g_closing && env == g_owner_env) RejectDeferred(env, deferred, text ? text : "callback threw");
    if (text) JS_FreeCString(ctx, text);
    JS_FreeValue(ctx, exception);
    return promise;
  }

  if (g_main_budget.interrupted && g_main_budget.interrupted_owner == owner) {
    JS_FreeValue(ctx, result);
    RejectDeferred(env, deferred, kMainInterrupted);
    return promise;
  }
  try { if (!g_closing) SettleJsResult(env, deferred, result); }
  catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing) RejectDeferred(env, deferred, "callback result ownership allocation failed");
  }
  JS_FreeValue(ctx, result);
  return promise;
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

// ------------------------------------------------------- sendMessage bridge

/** Shared by the two NAPI callbacks; last NAPI holder GC releases unresolved roots. */
struct QjsBridge {
  napi_env env;
  uint64_t generation;
  uint64_t owner;
  std::shared_ptr<venera::LifetimeRegistry> registry;
  venera::LifetimeRegistry::RootPtr root;
  QjsBridge(napi_env owner, uint64_t gen, std::shared_ptr<venera::LifetimeRegistry> r,
            venera::LifetimeRegistry::RootPtr capability) : env(owner), generation(gen),
      owner(venera::MainCallOwnerOf(capability->ctx)), registry(std::move(r)), root(std::move(capability)) {}
  QjsBridge(const QjsBridge&) = delete;
  ~QjsBridge() { registry->Release(root); }
};
struct QjsCallbackHolder { std::shared_ptr<QjsBridge> bridge; bool reject; };
void FinalizeQjsCallback(napi_env, void* data, void*) { delete static_cast<QjsCallbackHolder*>(data); }
napi_value ArkTsSettled(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held) return venera::JsUndefined(env);
  size_t argc = 1; napi_value arg = nullptr; void* data = nullptr;
  if (napi_get_cb_info(env, info, &argc, &arg, nullptr, &data) != napi_ok || !data) return nullptr;
  auto* holder = static_cast<QjsCallbackHolder*>(data);
  auto bridge = holder->bridge;
  if (!venera::IsLifetimeEnvironment(env) || env != bridge->env || bridge->generation != g_generation ||
      bridge->registry != g_lifetime || !bridge->registry->Claim(bridge->root)) return venera::JsUndefined(env);
  auto root = bridge->root; JSContext* ctx = root->ctx;
  try {
    venera::TraceScope trace(ctx, root->trace, bridge->owner);
    JSValue value = JS_UNDEFINED;
    bool reject = holder->reject;
    try {
      if (reject) {
        std::string message;
        if (argc && arg) {
          if (!ReadString(env, arg, &message)) {
            napi_value text = nullptr;
            if (napi_get_named_property(env, arg, "message", &text) == napi_ok) ReadString(env, text, &message);
            if (message.empty() && napi_coerce_to_string(env, arg, &text) == napi_ok) ReadString(env, text, &message);
          }
        }
        bool pending = false; napi_is_exception_pending(env, &pending);
        if (pending) { napi_value ignored; napi_get_and_clear_last_exception(env, &ignored); }
        value = JS_NewString(ctx, message.empty() ? "sendMessage failed" : message.c_str());
      } else {
        value = venera::NapiToJs(env, ctx, argc ? arg : nullptr);
        bool pending = false; napi_is_exception_pending(env, &pending);
        if (pending || JS_IsException(value)) {
          if (pending) { napi_value ignored; napi_get_and_clear_last_exception(env, &ignored); }
          JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
          value = JS_NewString(ctx, "host result cannot cross realm"); reject = true;
        }
      }
      JSValue returned = JS_Call(ctx, reject ? root->second : root->first, JS_UNDEFINED, 1, &value);
      JS_FreeValue(ctx, returned); JS_FreeValue(ctx, value);
    } catch (...) {
      JS_FreeValue(ctx, value);
      JSValue error = JS_NewString(ctx, "host result allocation failed");
      JSValue returned = JS_Call(ctx, root->second, JS_UNDEFINED, 1, &error);
      JS_FreeValue(ctx, returned); JS_FreeValue(ctx, error);
    }
  } catch (...) {
    // TraceScope allocation failure must never escape a native NAPI callback.
    RejectOwnerCalls(bridge->owner, "host result context allocation failed");
  }
  bridge->registry->Release(root);
  if (!g_closing && g_runtime) g_runtime->PumpJobs();
  return venera::JsUndefined(env);
}
bool MakeQjsCallback(napi_env env, const std::shared_ptr<QjsBridge>& bridge, bool reject, napi_value* result) {
  auto holder = std::make_unique<QjsCallbackHolder>(QjsCallbackHolder{bridge, reject});
  if (napi_create_function(env, reject ? "onReject" : "onResolve", NAPI_AUTO_LENGTH,
                           ArkTsSettled, holder.get(), result) != napi_ok) return false;
  if (!venera::AttachCallbackFinalizer(env, *result, holder.get(), FinalizeQjsCallback)) return false;
  holder.release(); return true;
}

/**
 * The function installed into the QuickJS global as `__nativeSendMessage`.
 * Hands the message to the ArkTS handler as a *value* and returns either the
 * converted result or a QuickJS promise that settles when the ArkTS promise
 * does. No JSON is involved in either direction.
 */
JSValue QjsSendMessage(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv) {
  venera::MainRuntimeLease lease;
  if (!lease.held) return JS_ThrowTypeError(ctx, "main realm is closing");
  if (g_message_handler == nullptr || g_env == nullptr) {
    return JS_ThrowTypeError(ctx, "sendMessage handler is not registered");
  }
  JSValueConst message = (argc > 0) ? argv[0] : JS_UNDEFINED;
  // Intercept before value_bridge: recursive ArkTS conversion would lose
  // structured cycles/typed identities and source compute must never run here.
  if (JS_IsObject(message)) {
    JSValue method = JS_GetPropertyStr(ctx, message, "method");
    if (JS_IsException(method)) return method;
    if (JS_IsString(method)) {
      const char* text = JS_ToCString(ctx, method);
      if (!text) { JS_FreeValue(ctx, method); return JS_EXCEPTION; }
      const bool compute = std::strcmp(text, "compute") == 0;
      JS_FreeCString(ctx, text); JS_FreeValue(ctx, method);
      if (compute) return venera::QueueComputeFromJs(g_env, ctx, message);
    } else { JS_FreeValue(ctx, method); }
  }
  napi_value argument = venera::JsToNapi(g_env, ctx, message);
  if (g_closing) return JS_UNDEFINED;
  if (ConversionFailed(g_env, argument)) {
    TakePendingException(g_env); return JS_ThrowTypeError(ctx, "sendMessage argument cannot cross realm");
  }
  // Overwrite any source-provided field. The owner is captured by the engine,
  // not inferred from a mutable global or an HTTP URL.
  const std::string trace = venera::TraceOf(ctx);
  napi_valuetype argument_type = napi_undefined;
  napi_typeof(g_env, argument, &argument_type);
  if (argument_type == napi_object) {
    napi_value trace_value = nullptr;
    napi_create_string_utf8(g_env, trace.c_str(), trace.size(), &trace_value);
    napi_set_named_property(g_env, argument, "__veneraTraceId", trace_value);
  }

  napi_value handler = nullptr;
  napi_get_reference_value(g_env, g_message_handler, &handler);
  napi_value global = nullptr;
  napi_get_global(g_env, &global);

  napi_value result = nullptr;
  napi_status status = napi_call_function(g_env, global, handler, 1, &argument, &result);
  if (status != napi_ok) {
    const std::string message = TakePendingException(g_env);
    return JS_ThrowTypeError(ctx, "%s",
                             message.empty() ? "sendMessage handler failed" : message.c_str());
  }
  if (g_closing || result == nullptr) {
    return JS_UNDEFINED;
  }

  // The handler is deliberately not async: load_data / convert / getLocale must
  // answer synchronously or init.js receives a promise where it wants a value.
  // Only http / delay / UI / getClipboard return promises.
  bool isPromise = false;
  napi_is_promise(g_env, result, &isPromise);
  if (!isPromise) {
    return venera::NapiToJs(g_env, ctx, result);
  }

  JSValue resolving[2] = {JS_UNDEFINED, JS_UNDEFINED};
  JSValue promise = JS_NewPromiseCapability(ctx, resolving);
  if (JS_IsException(promise)) return promise;
  std::shared_ptr<QjsBridge> bridge;
  try {
    auto root = g_lifetime->Own(resolving[0], resolving[1], trace);
    try { bridge = std::make_shared<QjsBridge>(g_env, g_generation, g_lifetime, root); }
    catch (...) { g_lifetime->Release(root); throw; }
  } catch (...) {
    JS_FreeValue(ctx, resolving[0]); JS_FreeValue(ctx, resolving[1]); JS_FreeValue(ctx, promise);
    return JS_ThrowInternalError(ctx, "cannot allocate host promise ownership");
  }
  JS_FreeValue(ctx, resolving[0]); JS_FreeValue(ctx, resolving[1]);
  napi_value then = nullptr, callbacks[2] = {nullptr, nullptr}, ignored = nullptr;
  bool ok = false;
  try {
    ok = napi_get_named_property(g_env, result, "then", &then) == napi_ok &&
      MakeQjsCallback(g_env, bridge, false, &callbacks[0]) && MakeQjsCallback(g_env, bridge, true, &callbacks[1]) &&
      napi_call_function(g_env, result, then, 2, callbacks, &ignored) == napi_ok;
  } catch (...) { ok = false; }
  if (!ok && !g_closing) TakePendingException(bridge->env);
  if (!ok && !g_closing && bridge->registry->Claim(bridge->root)) {
    JSValue error = JS_NewString(ctx, "host promise subscription failed");
    JSValue returned = JS_Call(ctx, bridge->root->second, JS_UNDEFINED, 1, &error);
    JS_FreeValue(ctx, returned); JS_FreeValue(ctx, error);
    bridge->registry->Release(bridge->root);
  }
  if (!g_closing && g_runtime) g_runtime->PumpJobs();
  return promise;
}

JSValue QjsCurrentTrace(JSContext* ctx, JSValueConst, int, JSValueConst*) {
  const auto trace = venera::TraceOf(ctx);
  return JS_NewStringLen(ctx, trace.data(), trace.size());
}

napi_value SetMessageHandler(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1 || args[0] == nullptr) {
    ThrowError(env, "setMessageHandler requires a function");
    return nullptr;
  }
  if (g_message_handler != nullptr) {
    napi_delete_reference(env, g_message_handler);
    g_message_handler = nullptr;
  }
  napi_create_reference(env, args[0], 1, &g_message_handler);
  g_env = env;

  // Install into the *QuickJS* global, not the ArkTS one.
  JSContext* ctx = Runtime()->context();
  if (ctx != nullptr) {
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue fn = JS_NewCFunction(ctx, QjsSendMessage, "__nativeSendMessage", 1);
    JS_SetPropertyStr(ctx, global, "__nativeSendMessage", fn);
    JS_SetPropertyStr(ctx, global, "__veneraCurrentTrace",
                      JS_NewCFunction(ctx, QjsCurrentTrace, "__veneraCurrentTrace", 0));
    JS_FreeValue(ctx, global);
  }

  return venera::JsUndefined(env);
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

napi_value SetGlobalString(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  std::string name;
  std::string value;
  if (argc < 2 || !ReadString(env, args[0], &name) || !ReadString(env, args[1], &value)) {
    ThrowError(env, "setGlobalString(name, value) expects two strings");
    return nullptr;
  }
  JSContext* ctx = Runtime()->context();
  if (ctx != nullptr) {
    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, name.c_str(), JS_NewString(ctx, value.c_str()));
    JS_FreeValue(ctx, global);
  }
  return venera::JsUndefined(env);
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

napi_value QuickJsVersion(napi_env env, napi_callback_info info) {
  napi_value result = nullptr;
  const std::string version = venera::QuickJsRuntime::QuickJsVersion();
  napi_create_string_utf8(env, version.c_str(), version.size(), &result);
  return result;
}

napi_value Evaluate(napi_env env, napi_callback_info info) {
  venera::MainRuntimeLease lease;
  if (!lease.held || env != g_owner_env) { napi_throw_error(env, nullptr, "main QuickJS environment is closed or foreign"); return nullptr; }
  try {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  std::string code;
  if (argc < 1 || !ReadString(env, args[0], &code)) {
    ThrowError(env, "evaluate() requires a code string");
    return nullptr;
  }
  std::string filename = "<eval>";
  if (argc >= 2 && args[1] != nullptr) {
    std::string provided;
    if (ReadString(env, args[1], &provided) && !provided.empty()) {
      filename = provided;
    }
  }

  std::string result;
  std::string error;
  if (!Runtime()->Evaluate(code, filename, &result, &error)) {
    ThrowError(env, error);
    return nullptr;
  }
  if (g_main_budget.interrupted) { ThrowError(env, kMainInterrupted); return nullptr; }
  napi_value output = nullptr;
  napi_create_string_utf8(env, result.c_str(), result.size(), &output);
  return output;
  } catch (...) {
    venera::MarkRuntimeOwnershipUncertain();
    if (!g_closing && env == g_owner_env) napi_throw_error(env, nullptr, "main runtime native allocation failed");
    return nullptr;
  }
}

napi_value RuntimeStats(napi_env env, napi_callback_info) {
  napi_value result = nullptr, value = nullptr;
  if (napi_create_object(env, &result) != napi_ok) return nullptr;
  napi_create_double(env, static_cast<double>(g_generation), &value); napi_set_named_property(env, result, "generation", value);
  napi_create_double(env, g_lifetime ? g_lifetime->LiveRoots() : 0, &value); napi_set_named_property(env, result, "ownedRoots", value);
  napi_create_double(env, g_lifetime ? g_lifetime->ExternalCount() : 0, &value); napi_set_named_property(env, result, "externalHandles", value);
  napi_create_double(env, g_pending_calls.size(), &value); napi_set_named_property(env, result, "pendingCalls", value);
  napi_get_boolean(env, venera::IsLifetimeEnvironment(env), &value); napi_set_named_property(env, result, "active", value);
  napi_get_boolean(env, g_ownership_uncertain, &value); napi_set_named_property(env, result, "ownershipUncertain", value);
  napi_create_double(env, g_active_entries, &value); napi_set_named_property(env, result, "activeEntries", value);
  napi_create_double(env, g_deferred_cleanup_failures, &value); napi_set_named_property(env, result, "deferredCleanupFailures", value);
  napi_create_double(env, g_main_interruptions, &value); napi_set_named_property(env, result, "mainInterruptions", value);
  napi_create_double(env, g_main_drain_yields, &value); napi_set_named_property(env, result, "mainDrainYields", value);
  napi_create_double(env, g_main_pump_schedule_failures, &value); napi_set_named_property(env, result, "mainPumpScheduleFailures", value);
  return result; // Counts only; no script/function/credential text.
}
void CleanupEnvironment(void* data) {
  napi_env env = static_cast<napi_env>(data);
  if (env != g_owner_env || g_closing) return;
  g_closing = true; // Late NAPI holders are inert BEFORE worker join/root release.
  // Completion owns/deletes the async-work handle and checks g_closing before
  // touching QuickJS. Never delete a possibly running handle during cleanup.
  if (g_pump_work) napi_cancel_async_work(env, g_pump_work);
  venera::ShutdownIsolated(env);
  // napi_deferred may own a backend Persistent resolver allocated separately.
  // Attempt supported settlement before discarding tokens, but NEVER claim a
  // portable free if the closing backend refuses NAPI work (no public destroy).
  napi_value undefined = nullptr;
  bool can_settle = napi_get_undefined(env, &undefined) == napi_ok;
  for (auto& call : g_pending_calls) {
    if (!can_settle || call.second.env != env ||
        napi_reject_deferred(env, call.second.deferred, undefined) != napi_ok) ++g_deferred_cleanup_failures;
    if (g_lifetime) g_lifetime->Release(call.second.root);
  }
  g_pending_calls.clear(); // All our roots/tokens inert; backend refusal count remains explicit.
  if (g_message_handler) napi_delete_reference(env, g_message_handler);
  g_message_handler = nullptr; g_env = nullptr;
  // Active native/QJS stacks (TraceScope/local values) must unwind before roots
  // are invalidated and context destroyed. Public lookup is already closed.
  g_deferred_lifetime = std::move(g_lifetime);
  g_deferred_destroy = g_runtime; g_runtime = nullptr; g_owner_env = nullptr;
  FinishDeferredDestroy();
}
napi_value Init(napi_env env, napi_value exports) {
  std::lock_guard<std::mutex> lock(g_init_mutex);
  // worker_napi is process-global/permanently closed at cleanup. Until workers
  // support generations, a second environment/reinitialization is unsupported.
  if (g_ever_initialized) {
    napi_throw_error(env, nullptr, "Venera main runtime already owned or permanently closed"); return nullptr;
  }
  g_owner_env = env; ++g_generation;
  if (napi_add_env_cleanup_hook(env, CleanupEnvironment, env) != napi_ok) { g_owner_env = nullptr; return nullptr; }
  g_ever_initialized = true;
  if (!Runtime()) { napi_throw_error(env, nullptr, "main QuickJS initialization failed"); return nullptr; }
  napi_property_descriptor properties[] = {
      {"runtimeStats", nullptr, RuntimeStats, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"quickjsVersion", nullptr, QuickJsVersion, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"encodeGbk", nullptr, EncodeGbk, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"decodeHttpBody", nullptr, DecodeBody, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"configureIsolated", nullptr, venera::ConfigureIsolated, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"transformIsolated", nullptr, venera::TransformIsolated, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"cancelIsolated", nullptr, venera::CancelIsolated, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"evaluate", nullptr, Evaluate, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"callJson", nullptr, CallJson, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"invokeFunction", nullptr, InvokeFunction, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"isFunction", nullptr, IsFunction, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"setMessageHandler", nullptr, SetMessageHandler, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"setGlobalString", nullptr, SetGlobalString, nullptr, nullptr, nullptr,
       napi_default, nullptr},
  };
  napi_define_properties(env, exports,
                         sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

}  // namespace

static napi_module veneraJsModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "venerajs",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVeneraJsModule(void) {
  napi_module_register(&veneraJsModule);
}
