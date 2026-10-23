#include "isolated_engine.h"
#include "trace_context.h"
#include <cmath>
#include <cstring>
#include <stdexcept>

namespace venera {
namespace {
std::string String(JSContext* ctx, JSValueConst value) {
  const char* text = JS_ToCString(ctx, value);
  std::string result = text ? text : "";
  if (text) JS_FreeCString(ctx, text);
  return result;
}
std::string Property(JSContext* ctx, JSValueConst object, const char* key) {
  JSValue value = JS_GetPropertyStr(ctx, object, key);
  std::string result = String(ctx, value);
  JS_FreeValue(ctx, value);
  return result;
}
}
IsolatedEngine::IsolatedEngine(IsolatedControl* control, size_t js_memory_limit, size_t pixel_limit,
                               IsolatedRpc rpc)
    : control_(control), rpc_(std::move(rpc)), pixel_limit_(pixel_limit) {
  if (!runtime_.IsValid()) throw std::runtime_error("isolated runtime creation failed");
  JS_SetMemoryLimit(runtime_.runtime(), js_memory_limit);
  JS_SetMaxStackSize(runtime_.runtime(), 1024 * 1024);
  JS_SetInterruptHandler(runtime_.runtime(), Interrupt, control_);
  JS_SetContextOpaque(runtime_.context(), this);
}
int IsolatedEngine::Interrupt(JSContext*, void* opaque) {
  return static_cast<IsolatedControl*>(opaque)->Expired() ? 1 : 0;
}
std::string IsolatedEngine::Exception(JSContext* ctx) {
  JSValue value = JS_GetException(ctx);
  std::string message = String(ctx, value);
  JS_FreeValue(ctx, value);
  return message.empty() ? "isolated JavaScript error" : message;
}
bool IsolatedEngine::Pump(std::string* error) {
  // A Promise chain can keep re-enqueuing short jobs without ever hitting the
  // QuickJS bytecode interrupt interval. Bound the scheduler as well as JS CPU.
  while (JS_IsJobPending(runtime_.runtime())) {
    if (control_->Expired()) { *error = "isolated jobs cancelled or timed out"; return false; }
    JSContext* ctx = nullptr;
    if (JS_ExecutePendingJob(runtime_.runtime(), &ctx) < 0) {
      *error = Exception(ctx ? ctx : runtime_.context()); return false;
    }
  }
  return true;
}
bool IsolatedEngine::Evaluate(const std::string& code, const char* name, JSValue* value, std::string* error) {
  if (control_->Expired()) { *error = "isolated execution cancelled or timed out"; return false; }
  JSContext* ctx = runtime_.context();
  JSValue result = JS_Eval(ctx, code.data(), code.size(), name, JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(result)) { *error = Exception(ctx); return false; }
  if (!Pump(error) || control_->Expired()) {
    JS_FreeValue(ctx, result);
    if (error->empty()) *error = "isolated execution cancelled or timed out";
    return false;
  }
  *value = result;
  return true;
}
bool IsolatedEngine::Init(const std::string& init, const std::string& html, std::string* error) {
  if (control_->Expired()) { *error = "isolated initialization cancelled or timed out"; return false; }
  JSContext* ctx = runtime_.context();
  TraceScope scope(ctx, control_->trace);
  JSValue global = JS_GetGlobalObject(ctx);
  JS_SetPropertyStr(ctx, global, "sendMessage", JS_NewCFunction(ctx, SendMessage, "sendMessage", 1));
  JS_SetPropertyStr(ctx, global, "appVersion", JS_NewString(ctx, "1.17.0"));
  JS_FreeValue(ctx, global);
  JSValue value;
  if (!Evaluate(init, "<isolated-init>", &value, error)) return false;
  JS_FreeValue(ctx, value);
  if (!html.empty()) {
    if (!Evaluate(html, "<isolated-html>", &value, error)) return false;
    JS_FreeValue(ctx, value);
  }
  return true;
}
JSValue IsolatedEngine::SendMessage(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
  auto* self = static_cast<IsolatedEngine*>(JS_GetContextOpaque(ctx));
  if (!self || argc == 0) return JS_NULL;
  if (self->control_->Expired()) return JS_ThrowInternalError(ctx, "isolated job cancelled or timed out");
  try { return self->Handle(ctx, argv[0]); }
  catch (const std::exception& e) {
    // JS exception is returned to caller, but its potentially sensitive text is
    // never part of the worker's developer audit.
    self->Audit("请求拒绝/异常；未输出脚本参数或异常原文");
    return JS_ThrowInternalError(ctx, "%s", e.what());
  }
}
JSValue IsolatedEngine::Handle(JSContext* ctx, JSValueConst message) {
  if (++bridge_calls_ > 16384) throw std::runtime_error("isolated bridge operation budget exceeded");
  const std::string method = Property(ctx, message, "method");
  if (method == "image" && pixel_mode_) return Image(ctx, message);
  if (pixel_mode_) return JS_NULL; // Matches upstream image_processing's receiver.
  Audit("compute请求到达主机桥；参数内容不落盘");
  if (!rpc_) return JS_ThrowInternalError(ctx, "isolated host RPC unavailable");
  return rpc_(ctx, message);
}
bool IsolatedEngine::Serialize(JSContext* ctx, JSValueConst value, std::vector<uint8_t>* output, std::string* error) {
  size_t length = 0;
  // No bytecode, SharedArrayBuffer or pointers cross threads. Structured data
  // preserves arrays/maps/sets/typed arrays/references instead of JSON-flattening.
  uint8_t* data = JS_WriteObject(ctx, &length, value, JS_WRITE_OBJ_REFERENCE);
  if (!data) { *error = Exception(ctx); return false; }
  if (length > 64 * 1024 * 1024) {
    js_free(ctx, data); *error = "isolated transfer exceeds 64MiB"; return false;
  }
  try { output->assign(data, data + length); }
  catch (...) { js_free(ctx, data); throw; }
  js_free(ctx, data);
  return true;
}
bool IsolatedEngine::Settle(JSValue value, JSValue* settled, std::string* error) {
  JSContext* ctx = runtime_.context();
  while (JS_IsPromise(value)) {
    auto state = JS_PromiseState(ctx, value);
    if (state == JS_PROMISE_PENDING) {
      if (control_->Expired()) { *error = "isolated job cancelled or timed out"; JS_FreeValue(ctx, value); return false; }
      if (!JS_IsJobPending(runtime_.runtime())) {
        *error = "isolated Promise cannot settle (no host request or queued job)";
        JS_FreeValue(ctx, value); return false;
      }
      if (!Pump(error)) { JS_FreeValue(ctx, value); return false; }
      continue;
    }
    JSValue result = JS_PromiseResult(ctx, value);
    JS_FreeValue(ctx, value);
    if (state == JS_PROMISE_REJECTED) {
      *error = String(ctx, result); JS_FreeValue(ctx, result); return false;
    }
    value = result;
  }
  *settled = value;
  return true;
}
bool IsolatedEngine::Compute(const std::string& code, const std::vector<uint8_t>& args, IsolatedResult* output) {
  audit_ = &output->audit; pixel_mode_ = false;
  JSContext* ctx = runtime_.context();
  TraceScope scope(ctx, control_->trace);
  JSValue function;
  Audit("compute业务到达独立引擎；不读取主引擎全局/源实例");
  if (!Evaluate(code, "<compute-function>", &function, &output->error)) return false;
  if (!JS_IsFunction(ctx, function)) { JS_FreeValue(ctx, function); output->error = "compute source must evaluate to a function"; return false; }
  JSValue array = JS_ReadObject(ctx, args.data(), args.size(), JS_READ_OBJ_REFERENCE);
  if (JS_IsException(array)) { output->error = Exception(ctx); JS_FreeValue(ctx, function); return false; }
  JSValue length = JS_GetPropertyStr(ctx, array, "length");
  uint32_t count = 0;
  JS_ToUint32(ctx, &count, length); JS_FreeValue(ctx, length);
  if (!JS_IsArray(array) || count > 65536) {
    JS_FreeValue(ctx, array); JS_FreeValue(ctx, function); output->error = "compute args must be an array"; return false;
  }
  std::vector<JSValue> values;
  for (uint32_t i = 0; i < count; i++) values.push_back(JS_GetPropertyUint32(ctx, array, i));
  JSValue result = JS_Call(ctx, function, JS_UNDEFINED, count, values.empty() ? nullptr : values.data());
  for (auto& value : values) JS_FreeValue(ctx, value);
  JS_FreeValue(ctx, array); JS_FreeValue(ctx, function);
  if (JS_IsException(result)) { output->error = Exception(ctx); return false; }
  if (!Pump(&output->error)) { JS_FreeValue(ctx, result); return false; }
  JSValue settled;
  if (!Settle(result, &settled, &output->error)) return false;
  if (control_->Expired() || bridge_calls_ > 16384) {
    JS_FreeValue(ctx, settled); output->error = "compute cancelled, timed out or exceeded bridge budget"; return false;
  }
  bool ok = Serialize(ctx, settled, &output->serialized, &output->error);
  JS_FreeValue(ctx, settled);
  Audit(ok ? "compute响应已结构化复制；独立引擎将释放" : "compute返回值不能跨线程；未伪造成功");
  return ok;
}
uint32_t IsolatedEngine::Number(JSContext* ctx, JSValueConst object, const char* key) {
  JSValue value = JS_GetPropertyStr(ctx, object, key);
  double number = 0;
  bool ok = JS_IsNumber(value) && JS_ToFloat64(ctx, &number, value) == 0 &&
    std::isfinite(number) && number >= 0 && number <= UINT32_MAX && std::floor(number) == number;
  JS_FreeValue(ctx, value);
  if (!ok) throw std::runtime_error("image coordinate/dimension must be a nonnegative integer");
  return static_cast<uint32_t>(number);
}
PixelSurface IsolatedEngine::Empty(uint32_t width, uint32_t height) {
  if (width > pixel_limit_ / 4 || (width && height > pixel_limit_ / (uint64_t(width) * 4)))
    throw std::runtime_error("isolated pixel dimensions exceed budget");
  uint64_t size = static_cast<uint64_t>(width) * height * 4;
  if (size > pixel_limit_ || allocated_ > pixel_limit_ - size) throw std::runtime_error("isolated pixel budget exceeded");
  PixelSurface result{width, height, std::vector<uint8_t>(static_cast<size_t>(size))};
  return result;
}
uint32_t IsolatedEngine::Put(PixelSurface value) {
  if (value.width > pixel_limit_ / 4 || (value.width && value.height > pixel_limit_ / (uint64_t(value.width) * 4)))
    throw std::runtime_error("pixel dimensions exceed budget");
  uint64_t size = static_cast<uint64_t>(value.width) * value.height * 4;
  if (size != value.rgba.size() || size > pixel_limit_ || allocated_ > pixel_limit_ - size)
    throw std::runtime_error("pixel size or budget mismatch");
  allocated_ += value.rgba.size();
  uint32_t key = next_key_++;
  images_.emplace(key, std::move(value));
  Audit("创建会话内图片句柄；当前累计字节=" + std::to_string(allocated_));
  return key;
}
void IsolatedEngine::Copy(PixelSurface& dst, uint32_t x, uint32_t y, const PixelSurface& src,
                         uint32_t sx, uint32_t sy, uint32_t width, uint32_t height) {
  if (uint64_t(x) + width > dst.width || uint64_t(y) + height > dst.height ||
      uint64_t(sx) + width > src.width || uint64_t(sy) + height > src.height)
    throw std::runtime_error("image rectangle outside bounds");
  for (uint32_t row = 0; row < height; row++) {
    if (control_->Expired()) throw std::runtime_error("image operation cancelled or timed out");
    size_t from = (size_t(sy + row) * src.width + sx) * 4;
    size_t to = (size_t(y + row) * dst.width + x) * 4;
    if (&dst != &src) std::memcpy(dst.rgba.data() + to, src.rgba.data() + from, size_t(width) * 4);
    else for (size_t i = 0; i < size_t(width) * 4; i++) dst.rgba[to + i] = src.rgba[from + i];
  }
}
JSValue IsolatedEngine::Image(JSContext* ctx, JSValueConst m) {
  const std::string op = Property(ctx, m, "function");
  Audit("图片桥请求到达；只记录操作阶段，不记录像素或脚本原文");
  if (op == "emptyImage") return JS_NewUint32(ctx, Put(Empty(Number(ctx, m, "width"), Number(ctx, m, "height"))));
  auto found = images_.find(Number(ctx, m, "key"));
  if (found == images_.end()) return JS_NULL;
  auto& source = found->second;
  if (op == "getWidth") return JS_NewUint32(ctx, source.width);
  if (op == "getHeight") return JS_NewUint32(ctx, source.height);
  if (op == "copyAndRotate90") {
    auto result = Empty(source.height, source.width);
    for (uint32_t y = 0; y < source.height; y++) {
      if (control_->Expired()) throw std::runtime_error("image operation cancelled or timed out");
      for (uint32_t x = 0; x < source.width; x++) {
        size_t a = (size_t(y) * source.width + x) * 4;
        size_t b = (size_t(x) * source.height + source.height - y - 1) * 4;
        std::memcpy(result.rgba.data() + b, source.rgba.data() + a, 4);
      }
    }
    return JS_NewUint32(ctx, Put(std::move(result)));
  }
  if (op == "copyRange") {
    auto result = Empty(Number(ctx, m, "width"), Number(ctx, m, "height"));
    Copy(result, 0, 0, source, Number(ctx, m, "x"), Number(ctx, m, "y"), result.width, result.height);
    return JS_NewUint32(ctx, Put(std::move(result)));
  }
  if (op == "fillImageAt" || op == "fillImageRangeAt") {
    auto other = images_.find(Number(ctx, m, "image"));
    if (other == images_.end()) return JS_NULL;
    bool full = op == "fillImageAt";
    Copy(source, Number(ctx, m, "x"), Number(ctx, m, "y"), other->second,
      full ? 0 : Number(ctx, m, "srcX"), full ? 0 : Number(ctx, m, "srcY"),
      full ? other->second.width : Number(ctx, m, "width"), full ? other->second.height : Number(ctx, m, "height"));
    return JS_NULL;
  }
  throw std::runtime_error("unknown image bridge operation");
}
bool IsolatedEngine::Modify(const std::string& code, PixelSurface input, bool premul, IsolatedResult* output) {
  audit_ = &output->audit; pixel_mode_ = true;
  JSContext* ctx = runtime_.context();
  TraceScope scope(ctx, control_->trace);
  Audit("图片业务到达独立引擎；源脚本与主引擎全局隔离");
  if (input.width > pixel_limit_ / 4 || (input.width && input.height > pixel_limit_ / (uint64_t(input.width) * 4)) ||
    uint64_t(input.width) * input.height * 4 != input.rgba.size()) {
    output->error = "input pixel dimensions/byte count invalid"; return false;
  }
  if (premul) {
    for (size_t i = 0; i < input.rgba.size(); i += 4) {
      if ((i & 0xffff) == 0 && control_->Expired()) { output->error = "image alpha conversion cancelled"; return false; }
      const uint32_t alpha = input.rgba[i + 3];
      for (int c = 0; c < 3; c++) input.rgba[i + c] = alpha ?
        static_cast<uint8_t>(std::min<uint32_t>(255, (input.rgba[i + c] * 255 + alpha / 2) / alpha)) : 0;
    }
  }
  try {
    uint32_t key = Put(std::move(input));
    JSValue value;
    // init.js remains byte-identical; no fake Image replacement is injected.
    if (!Evaluate(code + "\n;modifyImage(new Image(" + std::to_string(key) + "))",
        "<isolated-image>", &value, &output->error)) return false;
    if (JS_IsPromise(value)) { JS_FreeValue(ctx, value); output->error = "upstream modifyImage must return Image synchronously"; return false; }
    uint32_t result = 0;
    try { result = Number(ctx, value, "key"); }
    catch (...) { JS_FreeValue(ctx, value); throw; }
    JS_FreeValue(ctx, value);
    if (control_->Expired() || bridge_calls_ > 16384)
      throw std::runtime_error("image cancelled, timed out or exceeded bridge budget");
    auto found = images_.find(result);
    if (found == images_.end() || found->second.width == 0 || found->second.height == 0)
      throw std::runtime_error("modifyImage did not return a live nonempty Image");
    output->pixels = std::move(found->second);
    Audit("图片响应返回；实际像素尺寸=" + std::to_string(output->pixels.width) + "x" + std::to_string(output->pixels.height));
    return true;
  } catch (const std::exception& e) { output->error = e.what(); return false; }
}
}
