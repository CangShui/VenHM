#ifndef VENERA_LIFETIME_REGISTRY_H
#define VENERA_LIFETIME_REGISTRY_H
#include "quickjs.h"
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>

namespace venera {
/** UI-thread-only roots. The registry MUST be Shutdown before JS_FreeContext.
 * Root destructors intentionally never touch a context: late NAPI holders are
 * inert after shutdown and may be finalized after the realm has been destroyed.
 */
struct LifetimeRoot {
  JSContext* ctx = nullptr;
  JSValue first = JS_UNDEFINED, second = JS_UNDEFINED;
  std::string trace;
  uint64_t generation = 0, id = 0;
  bool claimed = false;
};
class LifetimeRegistry {
 public:
  using RootPtr = std::shared_ptr<LifetimeRoot>;
  LifetimeRegistry(JSContext* ctx, uint64_t generation) : ctx_(ctx), generation_(generation) {}
  ~LifetimeRegistry() { Shutdown(); }
  LifetimeRegistry(const LifetimeRegistry&) = delete;
  LifetimeRegistry& operator=(const LifetimeRegistry&) = delete;
  RootPtr Own(JSValueConst first, JSValueConst second = JS_UNDEFINED, std::string trace = {}) {
    if (!ctx_) return {};
    auto root = std::make_shared<LifetimeRoot>();
    root->trace = std::move(trace); root->generation = generation_; root->id = next_++;
    // Insert before dup: allocation failure must not orphan a QuickJS root.
    roots_.emplace(root->id, root);
    root->ctx = ctx_; root->first = JS_DupValue(ctx_, first); root->second = JS_DupValue(ctx_, second);
    return root;
  }
  bool Valid(const RootPtr& root) const {
    if (!ctx_ || !root || root->ctx != ctx_ || root->generation != generation_) return false;
    auto found = roots_.find(root->id);
    return found != roots_.end() && found->second == root;
  }
  bool Claim(const RootPtr& root) {
    if (!Valid(root) || root->claimed) return false;
    root->claimed = true; return true;
  }
  void Release(const RootPtr& root) noexcept {
    if (!Valid(root)) return;
    // Make late/reentrant holders inert before releasing JS references.
    JSContext* ctx = root->ctx; JSValue first = root->first, second = root->second;
    root->ctx = nullptr; root->first = root->second = JS_UNDEFINED; root->claimed = true;
    roots_.erase(root->id);
    JS_FreeValue(ctx, first); JS_FreeValue(ctx, second);
  }
  bool BindExternal(const void* token, const RootPtr& root) {
    return token && Valid(root) && externals_.emplace(token, root).second;
  }
  RootPtr LookupExternal(const void* token) const {
    // Never inspect token memory; a foreign napi_external may be any address.
    auto found = externals_.find(token);
    return found != externals_.end() && Valid(found->second) ? found->second : RootPtr{};
  }
  void ReleaseExternal(const void* token) noexcept {
    auto found = externals_.find(token);
    if (found == externals_.end()) return;
    auto root = found->second; externals_.erase(found); Release(root);
  }
  void Shutdown() noexcept {
    externals_.clear();
    while (!roots_.empty()) Release(roots_.begin()->second);
    ctx_ = nullptr;
  }
  size_t LiveRoots() const { return roots_.size(); }
  size_t ExternalCount() const { return externals_.size(); }
  bool Active() const { return ctx_ != nullptr; }
  JSContext* context() const { return ctx_; }
  uint64_t generation() const { return generation_; }
 private:
  JSContext* ctx_;
  uint64_t generation_, next_ = 1;
  std::unordered_map<uint64_t, RootPtr> roots_;
  std::unordered_map<const void*, RootPtr> externals_;
};
}
#endif
