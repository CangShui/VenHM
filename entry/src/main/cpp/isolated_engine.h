#ifndef VENERA_ISOLATED_ENGINE_H
#define VENERA_ISOLATED_ENGINE_H
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>
#include "js_engine.h"

namespace venera {
// Reserve a realistic per-image upper bound rather than 128MiB for every
// thumbnail. Four small transforms must not deterministically fail admission.
// Each job still has a hard 128MiB ceiling; cumulative surfaces count together.
inline size_t IsolatedImagePixelBudget(size_t input_bytes) {
  constexpr size_t ceiling = 128 * 1024 * 1024, floor = 32 * 1024 * 1024;
  if (input_bytes > ceiling) return 0;
  size_t scaled = input_bytes > ceiling / 4 ? ceiling : input_bytes * 4;
  return scaled < floor ? floor : scaled;
}
struct IsolatedControl {
  IsolatedControl() = default;
  IsolatedControl(IsolatedControl&& other) noexcept : cancelled(other.cancelled.load()),
      deadline(other.deadline), trace(std::move(other.trace)) {}
  IsolatedControl(const IsolatedControl&) = delete;
  std::atomic<bool> cancelled{false};
  std::chrono::steady_clock::time_point deadline;
  std::string trace;
  bool Expired() const { return cancelled.load() || std::chrono::steady_clock::now() >= deadline; }
};
struct PixelSurface {
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> rgba;
};
struct IsolatedResult {
  std::vector<uint8_t> serialized;
  PixelSurface pixels;
  std::vector<std::string> audit;
  std::string error;
};
using IsolatedRpc = std::function<JSValue(JSContext*, JSValueConst)>;

/** Per-job engine, owned/used/freed on its native worker thread; never shares global source state. */
class IsolatedEngine {
 public:
  IsolatedEngine(IsolatedControl* control, size_t js_memory_limit, size_t pixel_limit,
                 IsolatedRpc rpc = {});
  bool Init(const std::string& init, const std::string& html, std::string* error);
  bool Compute(const std::string& code, const std::vector<uint8_t>& args, IsolatedResult* output);
  bool Modify(const std::string& code, PixelSurface input, bool premultiplied, IsolatedResult* output);
  static bool Serialize(JSContext* ctx, JSValueConst value, std::vector<uint8_t>* output, std::string* error);
 private:
  QuickJsRuntime runtime_;
  IsolatedControl* control_;
  IsolatedRpc rpc_;
  size_t pixel_limit_;
  size_t allocated_ = 0;
  size_t bridge_calls_ = 0;
  uint32_t next_key_ = 1;
  std::map<uint32_t, PixelSurface> images_;
  std::vector<std::string>* audit_ = nullptr;
  bool pixel_mode_ = false;
  static int Interrupt(JSContext*, void* opaque);
  static JSValue SendMessage(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv);
  JSValue Handle(JSContext* ctx, JSValueConst message);
  JSValue Image(JSContext* ctx, JSValueConst message);
  bool Settle(JSValue value, JSValue* settled, std::string* error);
  bool Evaluate(const std::string& code, const char* name, JSValue* value, std::string* error);
  bool Pump(std::string* error);
  static std::string Exception(JSContext* ctx);
  uint32_t Number(JSContext* ctx, JSValueConst object, const char* key);
  PixelSurface Empty(uint32_t width, uint32_t height);
  uint32_t Put(PixelSurface pixels);
  void Copy(PixelSurface& dest, uint32_t x, uint32_t y, const PixelSurface& src,
            uint32_t sx, uint32_t sy, uint32_t width, uint32_t height);
  void Audit(const std::string& line) {
    if (!audit_) return;
    audit_->push_back(line);
  }
};
}
#endif
