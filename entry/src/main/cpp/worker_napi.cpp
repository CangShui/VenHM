#include "worker_napi.h"
#include "worker_rpc_validation.h"
#include "isolated_engine.h"
#include "trace_context.h"
#include "value_bridge.h"
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>
#include <cstring>
#include <stdexcept>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>

namespace venera {
namespace {
// Bounds native payloads, including results waiting for the UI event loop.
// This is a transport budget, not a total-process/QuickJS heap budget.
constexpr size_t kTransferBudget = 384 * 1024 * 1024;
constexpr size_t kComputeResultBudget = 64 * 1024 * 1024;
constexpr size_t kPixelBudget = 128 * 1024 * 1024;
std::mutex budget_mutex;
size_t reserved_bytes = 0, reserved_jobs = 0;
std::atomic<bool> closing{false};
struct Job;
struct Rpc {
  std::shared_ptr<IsolatedControl> control;
  std::mutex mutex;
  std::condition_variable condition;
  std::vector<uint8_t> message, result;
  std::string error;
  bool ready = false;
  bool settling = false; // Claimed on UI thread; never hold mutex across user code.
  bool promise = false;
};
struct Event {
  std::shared_ptr<Job> job;
  std::shared_ptr<Rpc> rpc;
};
struct Job {
  bool image = false, premul = false, from_js = false;
  uint32_t timeout = 10000;
  size_t image_pixel_limit = kPixelBudget;
  std::string code;
  std::vector<uint8_t> args;
  PixelSurface pixels;
  std::shared_ptr<IsolatedControl> control = std::make_shared<IsolatedControl>();
  IsolatedResult result;
  napi_deferred deferred = nullptr;
  napi_threadsafe_function channel = nullptr;
  JSContext* caller = nullptr;
  JSValue resolve = JS_UNDEFINED, reject = JS_UNDEFINED;
  size_t reservation = 0;
  bool admitted = false; // Count stays reserved even if retained byte count is zero.
  bool settled = false; // Delivered or abandoned; UI-thread only.
  bool completing = false; // Reentrant completion is not a second delivery.
  ~Job() {
    if (admitted) {
      std::lock_guard<std::mutex> lock(budget_mutex);
      reserved_bytes -= reservation; --reserved_jobs;
    }
  }
};
bool Reserve(const std::shared_ptr<Job>& job, size_t input, size_t output) {
  if (input > kTransferBudget || output > kTransferBudget - input) return false;
  const size_t size = input + output;
  std::lock_guard<std::mutex> lock(budget_mutex);
  if (closing.load() || reserved_jobs >= 32 || size > kTransferBudget - reserved_bytes) return false;
  reserved_bytes += size; ++reserved_jobs; job->reservation = size; job->admitted = true; return true;
}
void TrimReservation(const std::shared_ptr<Job>& job, size_t input, size_t output) {
  const size_t needed = input + output;
  std::lock_guard<std::mutex> lock(budget_mutex);
  if (needed < job->reservation) { reserved_bytes -= job->reservation - needed; job->reservation = needed; }
}
void FreeCaller(const std::shared_ptr<Job>& job) {
  if (!job->caller) return;
  JS_FreeValue(job->caller, job->resolve); JS_FreeValue(job->caller, job->reject);
  job->resolve = JS_UNDEFINED; job->reject = JS_UNDEFINED; job->caller = nullptr;
}
struct Slot {
  std::mutex mutex;
  std::condition_variable condition;
  std::deque<std::shared_ptr<Job>> queue;
  std::thread thread;
  size_t pending = 0;
  bool stop = false;
};
class Pool;
std::unique_ptr<Pool> pool;
napi_ref handler = nullptr, audit_handler = nullptr;
napi_env main_env = nullptr;
std::mutex registry_mutex;
std::vector<std::weak_ptr<Job>> registry;

bool ReadString(napi_env env, napi_value value, std::string* out) {
  napi_valuetype type = napi_undefined;
  if (!value || napi_typeof(env, value, &type) != napi_ok || type != napi_string) return false;
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > 8 * 1024 * 1024) return false;
  std::vector<char> buffer(length + 1);
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) return false;
  out->assign(buffer.data(), length); return true;
}
std::string Property(JSContext* ctx, JSValueConst value, const char* key) {
  JSValue property = JS_GetPropertyStr(ctx, value, key);
  const char* string = JS_ToCString(ctx, property);
  std::string result = string ? string : "";
  if (string) JS_FreeCString(ctx, string);
  JS_FreeValue(ctx, property); return result;
}
void ClearException(napi_env env) {
  bool pending = false; napi_is_exception_pending(env, &pending);
  if (pending) { napi_value ignored; napi_get_and_clear_last_exception(env, &ignored); }
}
void Audit(napi_env env, const std::string& trace, const char* phase, const std::string& message) {
  if (!env || !audit_handler) return;
  napi_value fn, global, args[3], ignored;
  if (napi_get_reference_value(env, audit_handler, &fn) == napi_ok &&
      napi_get_global(env, &global) == napi_ok &&
      napi_create_string_utf8(env, trace.data(), trace.size(), &args[0]) == napi_ok &&
      napi_create_string_utf8(env, phase, NAPI_AUTO_LENGTH, &args[1]) == napi_ok &&
      napi_create_string_utf8(env, message.data(), message.size(), &args[2]) == napi_ok)
    napi_call_function(env, global, fn, 3, args, &ignored);
  ClearException(env); // Logger failure must not change worker result.
}
// Generic value_bridge has no identity table. Compute bypasses it; host RPC
// intentionally accepts bounded trees only, never cycles/external handles.
bool CheckNapiTree(napi_env env, napi_value value, std::vector<napi_value>& path, size_t& nodes, size_t& bytes) {
  if (!value || ++nodes > 65536 || path.size() >= 64) return false;
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, value, &type) != napi_ok) return false;
  if (type == napi_external || type == napi_function || type == napi_symbol || type == napi_bigint) return false;
  if (type == napi_string) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > kComputeResultBudget - bytes) return false;
    bytes += length; return true;
  }
  if (type != napi_object) return true;
  bool buffer = false, typed = false, promise = false;
  if (napi_is_arraybuffer(env, value, &buffer) != napi_ok || napi_is_typedarray(env, value, &typed) != napi_ok ||
      napi_is_promise(env, value, &promise) != napi_ok || promise) return false;
  if (buffer || typed) {
    size_t length = 0; void* data = nullptr;
    if (buffer) {
      if (napi_get_arraybuffer_info(env, value, &data, &length) != napi_ok) return false;
    } else {
      napi_typedarray_type elementType; size_t count = 0, offset = 0; napi_value backing = nullptr;
      if (napi_get_typedarray_info(env, value, &elementType, &count, &data, &backing, &offset) != napi_ok) return false;
      const size_t size = TypedArrayElementSize(elementType);
      if (count > (kComputeResultBudget - bytes) / size) return false;
      length = count * size;
    }
    if ((!data && length) || length > kComputeResultBudget - bytes) return false;
    bytes += length; return true;
  }
  bool array = false; uint32_t length = 0;
  if (napi_is_array(env, value, &array) != napi_ok ||
      (array && (napi_get_array_length(env, value, &length) != napi_ok || length > 65536))) return false;
  for (auto ancestor : path) {
    bool same = false;
    if (napi_strict_equals(env, ancestor, value, &same) != napi_ok || same) return false;
  }
  const std::string kind = ValueClassName(env, value);
  const bool collection = kind == "Map" || kind == "Set";
  if (!collection && !kind.empty() && kind != "Object" && kind != "Array") return false;
  path.push_back(value);
  if (collection) {
    napi_value method = nullptr, iterator = nullptr, next = nullptr;
    bool ok = napi_get_named_property(env, value, kind == "Map" ? "entries" : "values", &method) == napi_ok &&
      napi_call_function(env, value, method, 0, nullptr, &iterator) == napi_ok &&
      napi_get_named_property(env, iterator, "next", &next) == napi_ok;
    bool done = false;
    while (ok && !done) {
      napi_value step = nullptr, finished = nullptr, item = nullptr;
      ok = nodes < 65536 && napi_call_function(env, iterator, next, 0, nullptr, &step) == napi_ok &&
        napi_get_named_property(env, step, "done", &finished) == napi_ok &&
        napi_get_value_bool(env, finished, &done) == napi_ok;
      if (ok && !done) ok = napi_get_named_property(env, step, "value", &item) == napi_ok &&
        CheckNapiTree(env, item, path, nodes, bytes);
    }
    path.pop_back(); return ok;
  }
  napi_value keys = nullptr; uint32_t count = 0;
  bool ok = napi_get_property_names(env, value, &keys) == napi_ok &&
    napi_get_array_length(env, keys, &count) == napi_ok && count <= 65536 - nodes;
  for (uint32_t i = 0; ok && i < count; ++i) {
    napi_value key = nullptr, item = nullptr;
    ok = napi_get_element(env, keys, i, &key) == napi_ok && CheckNapiTree(env, key, path, nodes, bytes) &&
      napi_get_property(env, value, key, &item) == napi_ok && CheckNapiTree(env, item, path, nodes, bytes);
  }
  path.pop_back(); return ok;
}
bool Marshal(napi_env env, napi_value value, std::vector<uint8_t>* bytes, std::string* error) {
  MainRuntimeLease lease;
  if (!lease.held || !IsLifetimeEnvironment(env)) { *error = "main runtime unavailable"; return false; }
  auto* runtime = CurrentRuntime();
  if (!runtime || !runtime->IsValid() || closing.load()) { *error = "main runtime unavailable"; return false; }
  std::vector<napi_value> path; path.reserve(64); size_t nodes = 0, byte_count = 0;
  if (!CheckNapiTree(env, value, path, nodes, byte_count)) { *error = "host result must be a bounded cloneable tree"; return false; }
  JSContext* ctx = runtime->context();
  JSValue object = NapiToJs(env, ctx, value);
  bool pending = false, ok = false;
  try {
    ok = napi_is_exception_pending(env, &pending) == napi_ok && !pending &&
      !JS_IsException(object) && IsolatedEngine::Serialize(ctx, object, bytes, error);
  } catch (...) { JS_FreeValue(ctx, object); throw; }
  JS_FreeValue(ctx, object);
  if (!ok) { JSValue exception = JS_GetException(ctx); JS_FreeValue(ctx, exception); }
  return ok;
}
void DeliverRpc(napi_env env, const std::shared_ptr<Rpc>& rpc, napi_value value, bool reject) {
  {
    std::lock_guard<std::mutex> lock(rpc->mutex);
    if (rpc->ready || rpc->settling) return;
    rpc->settling = true; // Claim before getters/loser callbacks can reenter.
  }
  std::vector<uint8_t> result;
  std::string error;
  try {
    // Marshal calls NAPI getters/iterators. Holding rpc->mutex here can deadlock
    // a loser callback, or cleanup joining a worker waiting on that same mutex.
    if (rpc->control->Expired()) error = "isolated host result cancelled";
    else if (reject) error = "isolated host RPC failed"; // No credentials/error text.
    else if (!Marshal(env, value, &result, &error)) {
      if (error.empty()) error = "isolated host result cannot cross thread";
      ClearException(env);
    }
    if (rpc->control->Expired()) error = "isolated host result cancelled";
  } catch (...) {
    rpc->control->cancelled.store(true);
    // Avoid allocating while reporting bad_alloc; the cancellation flag is the
    // failure signal even if no error string can be constructed.
    result.clear(); error.clear();
  }
  {
    std::lock_guard<std::mutex> lock(rpc->mutex);
    if (!rpc->ready) {
      if (rpc->control->cancelled.load()) result.clear();
      rpc->result.swap(result); rpc->error.swap(error);
      rpc->ready = true;
    }
    rpc->settling = false;
  }
  rpc->condition.notify_all();
}
struct Callback { std::shared_ptr<Rpc> rpc; bool reject; };
void FinalizeCallback(napi_env, void* data, void*) { delete static_cast<Callback*>(data); }
napi_value RpcSettled(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value arg; void* data;
  arg = nullptr; data = nullptr;
  if (napi_get_cb_info(env, info, &argc, &arg, nullptr, &data) != napi_ok || !data) return nullptr;
  auto* callback = static_cast<Callback*>(data);
  try {
    if (argc == 0 && napi_get_null(env, &arg) != napi_ok) return nullptr;
    DeliverRpc(env, callback->rpc, arg, callback->reject);
  } catch (...) {
    std::lock_guard<std::mutex> lock(callback->rpc->mutex);
    callback->rpc->ready = true; callback->rpc->control->cancelled.store(true);
    callback->rpc->condition.notify_all();
  }
  return JsUndefined(env);
}
void DispatchRpc(napi_env env, napi_value callback, const std::shared_ptr<Job>& job, const std::shared_ptr<Rpc>& rpc) {
  MainRuntimeLease lease;
  if (!lease.held || !IsLifetimeEnvironment(env) || closing.load() || rpc->control->Expired() || !CurrentRuntime()) { DeliverRpc(env, rpc, nullptr, true); return; }
  JSContext* ctx = CurrentRuntime()->context();
  JSValue message = JS_ReadObject(ctx, rpc->message.data(), rpc->message.size(), JS_READ_OBJ_REFERENCE);
  // Reuse the job's result allowance for each RPC; callbacks must not retain
  // large serialized requests after conversion or large replies after decode.
  std::vector<uint8_t>().swap(rpc->message);
  if (JS_IsException(message)) {
    JSValue error = JS_GetException(ctx); JS_FreeValue(ctx, error);
    DeliverRpc(env, rpc, nullptr, true); return;
  }
  // Function-valued worker messages require a remote callback proxy; structured
  // serialization rejects them explicitly instead of handing invalid handles to UI.
  napi_value value = JsToNapi(env, ctx, message); JS_FreeValue(ctx, message);
  napi_value trace = nullptr, global = nullptr, result = nullptr;
  if (!value || napi_create_string_utf8(env, rpc->control->trace.data(), rpc->control->trace.size(), &trace) != napi_ok ||
      napi_set_named_property(env, value, "__veneraTraceId", trace) != napi_ok ||
      napi_get_global(env, &global) != napi_ok ||
      napi_call_function(env, global, callback, 1, &value, &result) != napi_ok) {
    ClearException(env); DeliverRpc(env, rpc, nullptr, true); return;
  }
  bool promise = false;
  if (napi_is_promise(env, result, &promise) != napi_ok) { DeliverRpc(env, rpc, nullptr, true); return; }
  { std::lock_guard<std::mutex> lock(rpc->mutex); rpc->promise = promise; }
  if (!promise) { DeliverRpc(env, rpc, result, false); return; }
  napi_value then = nullptr, handlers[2] = {nullptr, nullptr}, ignored = nullptr;
  if (napi_get_named_property(env, result, "then", &then) != napi_ok) { DeliverRpc(env, rpc, nullptr, true); return; }
  for (int i = 0; i < 2; i++) {
    auto* data = new (std::nothrow) Callback{rpc, i == 1};
    if (!data) { DeliverRpc(env, rpc, nullptr, true); return; }
    if (napi_create_function(env, "isolatedRpcSettle", NAPI_AUTO_LENGTH, RpcSettled, data, &handlers[i]) != napi_ok ||
        !AttachCallbackFinalizer(env, handlers[i], data, FinalizeCallback)) {
      delete data; ClearException(env); DeliverRpc(env, rpc, nullptr, true); return;
    }
  }
  if (napi_call_function(env, result, then, 2, handlers, &ignored) != napi_ok) {
    ClearException(env); DeliverRpc(env, rpc, nullptr, true);
  }
}
bool Reject(napi_env env, napi_deferred deferred, const char* error) {
  ClearException(env);
  napi_value value = nullptr;
  if (napi_create_string_utf8(env, error, NAPI_AUTO_LENGTH, &value) != napi_ok) {
    ClearException(env);
    if (napi_get_undefined(env, &value) != napi_ok) return false;
  }
  return napi_reject_deferred(env, deferred, value) == napi_ok;
}
void RejectCaller(const std::shared_ptr<Job>& job, const char* message) {
  MainRuntimeLease lease;
  if (!lease.held || !job->caller) return;
  JSContext* ctx = job->caller;
  JSValue reason = JS_NewString(ctx, message);
  if (JS_IsException(reason)) reason = JS_GetException(ctx);
  JSValue reject = JS_DupValue(ctx, job->reject);
  JSValue returned = JS_Call(ctx, reject, JS_UNDEFINED, 1, &reason);
  JS_FreeValue(ctx, returned); JS_FreeValue(ctx, reason); JS_FreeValue(ctx, reject);
  FreeCaller(job); // Reentrant shutdown may already have cleared these roots.
}
// A successful NAPI settlement consumes the deferred. Publish that fact before
// any logging, job pumping or exception handler can attempt another delivery.
bool DeliverDeferred(napi_env env, const std::shared_ptr<Job>& job, napi_value value) {
  if (job->settled || !job->deferred || closing.load() || !env || env != main_env) return false;
  if (napi_resolve_deferred(env, job->deferred, value) != napi_ok) return false;
  job->deferred = nullptr; job->settled = true;
  return true;
}
bool RejectDeferred(napi_env env, const std::shared_ptr<Job>& job, const char* error) {
  if (job->settled || !job->deferred || closing.load() || !env || env != main_env) return false;
  if (!Reject(env, job->deferred, error)) return false;
  job->deferred = nullptr; job->settled = true;
  return true;
}
void FailCompletion(napi_env env, const std::shared_ptr<Job>& job, const char* error) noexcept {
  if (job->settled || !env || env != main_env || closing.load()) return;
  try {
    if (!job->from_js) RejectDeferred(env, job, error);
    else {
      // Claim before JS_Call; promise resolution can execute reentrant work.
      job->settled = true;
      RejectCaller(job, error);
    }
  } catch (...) { /* No C++ exception may escape the NAPI callback/finalizer. */ }
}
void Complete(napi_env env, const std::shared_ptr<Job>& job) {
  if (job->settled || job->completing || closing.load() || !env || env != main_env) return;
  MainRuntimeLease lease; // Outlives all QuickJS locals/TraceScope below.
  if ((job->from_js || !job->image) && (!lease.held || !IsLifetimeEnvironment(env))) return;
  struct CompletionScope {
    Job& job;
    explicit CompletionScope(Job& value) : job(value) { job.completing = true; }
    ~CompletionScope() { job.completing = false; }
  } completion(*job);
  auto& result = job->result;
  try {
    Audit(env, job->control->trace, "独立引擎后台执行", "处理已完成；步骤数=" + std::to_string(result.audit.size()));
    for (const auto& step : result.audit) Audit(env, job->control->trace, "独立引擎步骤", step);
  } catch (...) { /* Logger allocation failure must not change delivery. */ }
  if (job->settled || closing.load() || env != main_env) return; // Auditor can reenter cleanup.
  std::string error = result.error;
  if (job->control->cancelled.load()) error = "isolated job cancelled";
  if (job->from_js) {
    auto* runtime = CurrentRuntime();
    if (!job->caller || !runtime || runtime->context() != job->caller) return;
    JSContext* ctx = job->caller;
    TraceScope scope(ctx, job->control->trace);
    JSValue value;
    if (error.empty()) {
      value = JS_ReadObject(ctx, result.serialized.data(), result.serialized.size(), JS_READ_OBJ_REFERENCE);
      if (JS_IsException(value)) { value = JS_GetException(ctx); error = "isolated result decoding failed"; }
    } else { value = JS_NewString(ctx, error.c_str()); }
    JSValue capability = JS_DupValue(ctx, error.empty() ? job->resolve : job->reject);
    job->settled = true; // Capability is delivered once, before reentrant work.
    JSValue returned = JS_Call(ctx, capability, JS_UNDEFINED, 1, &value);
    JS_FreeValue(ctx, returned); JS_FreeValue(ctx, value); JS_FreeValue(ctx, capability);
    FreeCaller(job);
    if (!closing.load() && CurrentRuntime() == runtime) runtime->PumpJobs();
  } else {
    napi_value value = nullptr;
    if (!error.empty()) {
      RejectDeferred(env, job, error.c_str());
    } else if (job->image) {
      napi_value width = nullptr, height = nullptr, rgba = nullptr; void* buffer = nullptr;
      bool ok = result.pixels.rgba.size() <= kPixelBudget &&
        napi_create_object(env, &value) == napi_ok &&
        napi_create_uint32(env, result.pixels.width, &width) == napi_ok &&
        napi_create_uint32(env, result.pixels.height, &height) == napi_ok &&
        napi_create_arraybuffer(env, result.pixels.rgba.size(), &buffer, &rgba) == napi_ok &&
        (result.pixels.rgba.empty() || buffer);
      if (ok && !result.pixels.rgba.empty()) std::memcpy(buffer, result.pixels.rgba.data(), result.pixels.rgba.size());
      ok = ok && napi_set_named_property(env, value, "width", width) == napi_ok &&
        napi_set_named_property(env, value, "height", height) == napi_ok &&
        napi_set_named_property(env, value, "rgba", rgba) == napi_ok;
      if (!ok || !DeliverDeferred(env, job, value)) {
        error = "cannot allocate or deliver isolated image result"; RejectDeferred(env, job, error.c_str());
      }
    } else {
      JSContext* ctx = CurrentRuntime()->context();
      JSValue decoded = JS_ReadObject(ctx, result.serialized.data(), result.serialized.size(), JS_READ_OBJ_REFERENCE);
      if (JS_IsException(decoded)) {
        JSValue exception = JS_GetException(ctx); JS_FreeValue(ctx, exception);
        error = "isolated result decoding failed";
        RejectDeferred(env, job, error.c_str());
      } else {
        try {
          value = JsToNapi(env, ctx, decoded);
          bool pending = false;
          if (!value || napi_is_exception_pending(env, &pending) != napi_ok || pending ||
              !DeliverDeferred(env, job, value)) {
            error = "cannot convert isolated compute result"; RejectDeferred(env, job, error.c_str());
          }
        } catch (...) { JS_FreeValue(ctx, decoded); throw; }
        JS_FreeValue(ctx, decoded);
      }
    }
  }
  try {
    Audit(env, job->control->trace, job->settled && error.empty() ? "独立引擎响应返回" : "独立引擎拒绝/异常",
      job->settled && error.empty() ? "成功；仅返回结构化结果/真实像素，不记录内容" : "失败/取消/超时；没有退回主线程执行或返回原始乱序图");
  } catch (...) { /* In particular, never reject a consumed deferred for logging. */ }
}
void Channel(napi_env env, napi_value callback, void*, void* data) {
  std::unique_ptr<Event> event(static_cast<Event*>(data));
  if (!event) return;
  if (!env || !callback || closing.load()) { event->job->control->cancelled.store(true); return; }
  try {
    if (event->rpc) DispatchRpc(env, callback, event->job, event->rpc);
    else Complete(env, event->job);
  } catch (...) {
    event->job->control->cancelled.store(true);
    if (event->rpc) {
      std::lock_guard<std::mutex> lock(event->rpc->mutex);
      event->rpc->ready = true; event->rpc->condition.notify_all();
    } else {
      FailCompletion(env, event->job, "isolated completion allocation failed");
    }
  }
}
void FinalizeChannel(napi_env env, void* data, void*) {
  std::unique_ptr<std::shared_ptr<Job>> owner(static_cast<std::shared_ptr<Job>*>(data));
  if (!owner) return;
  // TSFN owns the job through delivery/finalization, so a failed enqueue cannot
  // destroy a promise's handles on a producer thread or leak its reservation.
  if (env && env == main_env && !closing.load() && !(*owner)->settled) {
    try {
      (*owner)->result.error = "isolated completion channel failed";
      Complete(env, *owner);
    } catch (...) {
      FailCompletion(env, *owner, "isolated completion failed");
    }
  }
  FreeCaller(*owner);
}
JSValue RpcCall(const std::shared_ptr<Job>& job, JSContext* ctx, JSValueConst message) {
  // Workers synchronously wait for host RPC. Recursively queueing compute can
  // exhaust every slot with parents waiting for children; never wait for timeout.
  if (Property(ctx, message, "method") == "compute")
    return JS_ThrowTypeError(ctx, "nested compute is unsupported in an isolated worker");
  if (!CheckWorkerRpcTree(ctx, message))
    return JS_ThrowTypeError(ctx, "worker host RPC requires a bounded noncyclic tree without callbacks or exotic objects");
  auto rpc = std::make_shared<Rpc>(); rpc->control = job->control;
  if (!IsolatedEngine::Serialize(ctx, message, &rpc->message, &rpc->error))
    return JS_ThrowTypeError(ctx, "worker host message cannot be cloned (function callbacks need a proxy)");
  auto* event = new Event{job, rpc};
  if (napi_call_threadsafe_function(job->channel, event, napi_tsfn_nonblocking) != napi_ok) {
    delete event; return JS_ThrowInternalError(ctx, "isolated host channel closed");
  }
  std::unique_lock<std::mutex> lock(rpc->mutex);
  while (!rpc->ready && !job->control->Expired()) rpc->condition.wait_for(lock, std::chrono::milliseconds(20));
  if (!rpc->ready) return JS_ThrowInternalError(ctx, "isolated host request cancelled or timed out");
  if (!rpc->error.empty()) return JS_ThrowInternalError(ctx, "%s", rpc->error.c_str());
  JSValue result = JS_ReadObject(ctx, rpc->result.data(), rpc->result.size(), JS_READ_OBJ_REFERENCE);
  std::vector<uint8_t>().swap(rpc->result);
  if (JS_IsException(result)) return result;
  if (rpc->promise) {
    JSValue promise = JS_NewSettledPromise(ctx, false, result); JS_FreeValue(ctx, result); return promise;
  }
  return result;
}
class Pool {
 public:
  std::string init, html;
  Slot slots[4];
  explicit Pool(std::string a, std::string b) : init(std::move(a)), html(std::move(b)) {
    try {
      for (auto& slot : slots) slot.thread = std::thread([this, &slot] { Loop(slot); });
    } catch (...) { Stop(); throw; }
  }
  ~Pool() { Stop(); }
  void Stop() {
    for (auto& slot : slots) {
      std::lock_guard<std::mutex> lock(slot.mutex); slot.stop = true;
      for (auto& job : slot.queue) job->control->cancelled.store(true);
      slot.condition.notify_all();
    }
    for (auto& slot : slots) if (slot.thread.joinable()) slot.thread.join();
  }
  bool Queue(const std::shared_ptr<Job>& job) {
    Slot* chosen = &slots[0];
    size_t least = SIZE_MAX;
    for (auto& slot : slots) {
      std::lock_guard<std::mutex> lock(slot.mutex);
      if (slot.pending < least) { chosen = &slot; least = slot.pending; }
    }
    size_t total = 0; for (auto& slot : slots) { std::lock_guard<std::mutex> lock(slot.mutex); total += slot.pending; }
    if (total >= 32) return false;
    { std::lock_guard<std::mutex> lock(chosen->mutex);
      if (chosen->stop || closing.load()) return false;
      chosen->queue.push_back(job); chosen->pending++;
    }
    chosen->condition.notify_one(); return true;
  }
 private:
  void Loop(Slot& slot) {
    for (;;) {
      std::shared_ptr<Job> job;
      {
        std::unique_lock<std::mutex> lock(slot.mutex);
        slot.condition.wait(lock, [&] { return slot.stop || !slot.queue.empty(); });
        if (slot.stop && slot.queue.empty()) break;
        job = slot.queue.front(); slot.queue.pop_front();
      }
      job->control->deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(job->timeout);
      try {
        if (job->control->cancelled.load()) throw std::runtime_error("isolated task cancelled before execution");
        IsolatedRpc rpc = [job](JSContext* ctx, JSValueConst message) { return RpcCall(job, ctx, message); };
        if (job->image) {
          IsolatedEngine engine(job->control.get(), 64 * 1024 * 1024, job->image_pixel_limit);
          if (engine.Init(init, "", &job->result.error)) engine.Modify(job->code, std::move(job->pixels), job->premul, &job->result);
        } else {
          // Pool threads, NOT realms: pending microtasks/globals from a previous
          // successful call must never inherit the next job's RPC/control owner.
          // This deliberately differs from upstream's persistent JS isolates.
          IsolatedEngine engine(job->control.get(), 128 * 1024 * 1024, 0, rpc);
          if (engine.Init(init, html, &job->result.error)) engine.Compute(job->code, job->args, &job->result);
        }
      } catch (...) {
        // Avoid throwing a second bad_alloc while reporting worker failure.
        job->control->cancelled.store(true);
        try { job->result.error = "isolated native execution failed"; } catch (...) {}
      }
      std::vector<uint8_t>().swap(job->args); std::vector<uint8_t>().swap(job->pixels.rgba);
      // Engine/input buffers are gone: retain only the actual completed payload,
      // not the unused worst-case output quota until TSFN finalization. A tiny
      // completed result may resume its caller before that finalizer runs.
      size_t retained = job->result.serialized.size() + job->result.pixels.rgba.size() + job->result.error.size();
      for (const auto& step : job->result.audit) retained += step.size();
      TrimReservation(job, job->code.size() + job->control->trace.size(), retained);
      auto* completed = new (std::nothrow) Event{job, nullptr};
      if (!completed || napi_call_threadsafe_function(job->channel, completed, napi_tsfn_nonblocking) != napi_ok) {
        delete completed;
        job->control->cancelled.store(true);
      }
      napi_release_threadsafe_function(job->channel, napi_tsfn_release);
      { std::lock_guard<std::mutex> lock(slot.mutex); slot.pending--; }
    }
  }
};
void Cleanup() {
  closing.store(true);
  {
    std::lock_guard<std::mutex> lock(registry_mutex);
    for (auto& weak : registry) if (auto job = weak.lock()) job->control->cancelled.store(true);
  }
  // Cancellation wakes RPC waits within 20ms. Join before freeing any caller
  // handles or the main runtime; queued null-env TSFN callbacks only cancel.
  pool.reset();
  {
    std::lock_guard<std::mutex> lock(registry_mutex);
    for (auto& weak : registry) if (auto job = weak.lock()) { FreeCaller(job); job->settled = true; }
    registry.clear();
  }
  if (main_env && handler) napi_delete_reference(main_env, handler);
  if (main_env && audit_handler) napi_delete_reference(main_env, audit_handler);
  handler = nullptr; audit_handler = nullptr; main_env = nullptr;
}
bool Queue(napi_env env, const std::shared_ptr<Job>& job) {
  if (!pool || !handler || closing.load() || env != main_env || !job->reservation) return false;
  napi_value callback = nullptr, resource = nullptr;
  if (napi_get_reference_value(env, handler, &callback) != napi_ok ||
      napi_create_string_utf8(env, job->image ? "VeneraImageWorker" : "VeneraComputeWorker", NAPI_AUTO_LENGTH, &resource) != napi_ok) return false;
  auto* owner = new (std::nothrow) std::shared_ptr<Job>(job);
  if (!owner) return false;
  // One producer reference; worker releases it exactly once. The finalizer owns
  // the UI capability until every event is drained, even after enqueue failure.
  if (napi_create_threadsafe_function(env, callback, nullptr, resource, 2, 1, owner, FinalizeChannel, nullptr, Channel, &job->channel) != napi_ok) {
    delete owner; return false;
  }
  try {
    {
      std::lock_guard<std::mutex> lock(registry_mutex);
      registry.erase(std::remove_if(registry.begin(), registry.end(), [](auto& weak) { return weak.expired(); }), registry.end());
      registry.push_back(job);
    }
    Audit(env, job->control->trace, "独立引擎请求到达",
      "后台线程池；每任务独立上下文；输入/结果准入已预留；不记录代码/参数/像素原文");
    if (pool->Queue(job)) return true;
  } catch (...) {}
  job->settled = true;
  napi_release_threadsafe_function(job->channel, napi_tsfn_abort);
  job->channel = nullptr; return false;
}
void Failure(napi_env env, napi_deferred deferred, const char* error) { Reject(env, deferred, error); }
bool ReadUint(napi_env env, napi_value value, uint32_t* out) {
  double number = 0;
  if (napi_get_value_double(env, value, &number) != napi_ok || !std::isfinite(number) ||
      number < 0 || number > UINT32_MAX || std::floor(number) != number) return false;
  *out = static_cast<uint32_t>(number); return true;
}
bool Timeout(napi_env env, size_t argc, napi_value* args, size_t index, uint32_t* timeout) {
  if (argc > index && !ReadUint(env, args[index], timeout)) return false;
  *timeout = std::max<uint32_t>(1, std::min<uint32_t>(60000, *timeout)); return true;
}
}
void ShutdownIsolated(napi_env) { Cleanup(); }
napi_value ConfigureIsolated(napi_env env, napi_callback_info info) try {
  size_t argc = 4; napi_value args[4] = {};
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok) return nullptr;
  std::string init, html;
  napi_valuetype type;
  if (argc != 4 || !ReadString(env, args[0], &init) || !ReadString(env, args[1], &html) ||
    napi_typeof(env, args[2], &type) != napi_ok || type != napi_function) {
    napi_throw_type_error(env, nullptr, "configureIsolated needs init/html/handler/auditor"); return nullptr;
  }
  if (napi_typeof(env, args[3], &type) != napi_ok || type != napi_function) {
    napi_throw_type_error(env, nullptr, "configureIsolated auditor must be a function"); return nullptr;
  }
  if (closing.load() || (main_env && main_env != env)) {
    napi_throw_error(env, nullptr, "isolated runtime closing or owned by another environment"); return nullptr;
  }
  if (pool) {
    // Changing handlers/bootstrap with live work would route old RPC to new state.
    if (pool->init != init || pool->html != html) {
      napi_throw_error(env, nullptr, "isolated runtime is already configured with different bootstrap"); return nullptr;
    }
    return JsUndefined(env);
  }
  napi_ref next_handler = nullptr, next_audit = nullptr;
  if (napi_create_reference(env, args[2], 1, &next_handler) != napi_ok) return nullptr;
  if (napi_create_reference(env, args[3], 1, &next_audit) != napi_ok) {
    napi_delete_reference(env, next_handler); return nullptr;
  }
  try { pool = std::make_unique<Pool>(std::move(init), std::move(html)); }
  catch (...) {
    napi_delete_reference(env, next_handler); napi_delete_reference(env, next_audit); throw;
  }
  handler = next_handler; audit_handler = next_audit; main_env = env;
  return JsUndefined(env);
} catch (...) { napi_throw_error(env, nullptr, "cannot configure isolated native workers"); return nullptr; }
napi_value ComputeIsolated(napi_env env, napi_callback_info info) {
  napi_value promise = nullptr; napi_deferred deferred = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok) return nullptr;
  try {
    size_t argc = 4; napi_value args[4] = {};
    auto job = std::make_shared<Job>(); job->deferred = deferred;
    bool array = false; std::string error;
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 3 ||
        !ReadString(env, args[0], &job->code) || !ReadString(env, args[2], &job->control->trace) ||
        napi_is_array(env, args[1], &array) != napi_ok || !array ||
        !Timeout(env, argc, args, 3, &job->timeout)) {
      Failure(env, deferred, "invalid compute code/args/timeout"); return promise;
    }
    // Reserve maximum input + result before the recursive ArkTS copy/serializer.
    if (!Reserve(job, job->code.size() + job->control->trace.size() + kComputeResultBudget, kComputeResultBudget)) {
      Failure(env, deferred, "isolated queue byte/count budget exceeded"); return promise;
    }
    if (!Marshal(env, args[1], &job->args, &error)) {
      Failure(env, deferred, "unclonable compute arguments"); return promise;
    }
    TrimReservation(job, job->code.size() + job->control->trace.size() + job->args.size(), kComputeResultBudget);
    if (!Queue(env, job)) Failure(env, deferred, "isolated runtime unavailable or queue full");
  } catch (...) { Failure(env, deferred, "isolated compute allocation failed"); }
  return promise;
}
napi_value TransformIsolated(napi_env env, napi_callback_info info) {
  napi_value promise = nullptr; napi_deferred deferred = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok) return nullptr;
  try {
    size_t argc = 7; napi_value args[7] = {};
    auto job = std::make_shared<Job>(); job->image = true; job->deferred = deferred;
    bool buffer = false; void* rgba = nullptr; size_t length = 0;
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 6 ||
        napi_is_arraybuffer(env, args[0], &buffer) != napi_ok || !buffer ||
        !ReadString(env, args[3], &job->code) || !ReadString(env, args[4], &job->control->trace) ||
        !ReadUint(env, args[1], &job->pixels.width) || !ReadUint(env, args[2], &job->pixels.height) ||
        napi_get_value_bool(env, args[5], &job->premul) != napi_ok ||
        napi_get_arraybuffer_info(env, args[0], &rgba, &length) != napi_ok ||
        !Timeout(env, argc, args, 6, &job->timeout)) {
      Failure(env, deferred, "invalid isolated image arguments"); return promise;
    }
    if (!job->pixels.width || !job->pixels.height || job->pixels.width > kPixelBudget / 4 ||
        job->pixels.height > kPixelBudget / (uint64_t(job->pixels.width) * 4) ||
        uint64_t(job->pixels.width) * job->pixels.height * 4 != length || !rgba) {
      Failure(env, deferred, "image byte count/dimensions exceed isolated budget"); return promise;
    }
    // Admission MUST precede the 128MiB copy. Retain the output allowance until
    // UI completion/finalization, not merely until worker execution finishes.
    job->image_pixel_limit = IsolatedImagePixelBudget(length);
    if (!Reserve(job, length + job->code.size() + job->control->trace.size(), job->image_pixel_limit)) {
      Failure(env, deferred, "isolated queue byte/count budget exceeded"); return promise;
    }
    job->pixels.rgba.assign(static_cast<uint8_t*>(rgba), static_cast<uint8_t*>(rgba) + length);
    if (!Queue(env, job)) Failure(env, deferred, "isolated runtime unavailable or queue full");
  } catch (...) { Failure(env, deferred, "isolated image allocation failed"); }
  return promise;
}
napi_value CancelIsolated(napi_env env, napi_callback_info info) try {
  size_t argc = 1; napi_value arg = nullptr;
  if (napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr) != napi_ok) return nullptr;
  std::string trace; uint32_t count = 0;
  if (argc && ReadString(env, arg, &trace) && !trace.empty()) {
    std::lock_guard<std::mutex> lock(registry_mutex);
    for (auto& weak : registry) if (auto job = weak.lock()) {
      if (job->control->trace == trace) { job->control->cancelled.store(true); count++; }
    }
  }
  Audit(env, trace, "独立引擎取消到达", "只标记对应Trace的任务数=" + std::to_string(count));
  napi_value result = nullptr;
  if (napi_create_uint32(env, count, &result) != napi_ok) return nullptr;
  return result;
} catch (...) { napi_throw_error(env, nullptr, "isolated cancellation allocation failed"); return nullptr; }
JSValue QueueComputeFromJs(napi_env env, JSContext* ctx, JSValueConst message) try {
  if (!CurrentRuntime() || CurrentRuntime()->context() != ctx || closing.load())
    return JS_ThrowInternalError(ctx, "isolated compute requires the live main runtime");
  auto job = std::make_shared<Job>(); job->from_js = true; job->control->trace = TraceOf(ctx);
  JSValue code = JS_GetPropertyStr(ctx, message, "function");
  if (JS_IsException(code)) return code;
  if (!JS_IsString(code)) { JS_FreeValue(ctx, code); return JS_ThrowTypeError(ctx, "compute function must be a string"); }
  size_t length = 0; const char* text = JS_ToCStringLen(ctx, &length, code); JS_FreeValue(ctx, code);
  if (!text) return JS_EXCEPTION;
  if (length > 8 * 1024 * 1024) { JS_FreeCString(ctx, text); return JS_ThrowTypeError(ctx, "compute source exceeds budget"); }
  try { job->code.assign(text, length); } catch (...) { JS_FreeCString(ctx, text); throw; }
  JS_FreeCString(ctx, text);
  if (!Reserve(job, job->code.size() + job->control->trace.size() + kComputeResultBudget, kComputeResultBudget))
    return JS_ThrowInternalError(ctx, "isolated compute queue byte/count budget exceeded");
  JSValue args = JS_GetPropertyStr(ctx, message, "args");
  if (JS_IsException(args)) return args;
  if (JS_IsNull(args) || JS_IsUndefined(args)) { JS_FreeValue(ctx, args); args = JS_NewArray(ctx); }
  bool serialized = false;
  try { serialized = JS_IsArray(args) && IsolatedEngine::Serialize(ctx, args, &job->args, &job->result.error); }
  catch (...) { JS_FreeValue(ctx, args); throw; }
  JS_FreeValue(ctx, args);
  if (!serialized) return JS_ThrowTypeError(ctx, "compute args must be a cloneable list");
  TrimReservation(job, job->code.size() + job->control->trace.size() + job->args.size(), kComputeResultBudget);
  JSValue pair[2] = {JS_UNDEFINED, JS_UNDEFINED}; JSValue promise = JS_NewPromiseCapability(ctx, pair);
  if (JS_IsException(promise)) return promise;
  job->caller = ctx; job->resolve = pair[0]; job->reject = pair[1];
  if (!Queue(env, job)) {
    FreeCaller(job); JS_FreeValue(ctx, promise);
    return JS_ThrowInternalError(ctx, "isolated compute queue unavailable/full");
  }
  return promise;
} catch (...) { return JS_ThrowInternalError(ctx, "isolated compute allocation failed"); }
}
