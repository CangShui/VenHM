#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>
#include "js_engine.h"
#include "lifetime_registry.h"
#include "trace_context.h"

static FILE* audit;
static int assertions = 0, finalized = 0;
static JSClassID tracker_class;
static void Check(bool ok, const char* name) {
  std::fprintf(audit, "TraceID=native-lifetime-tests [%s] %s\n", ok ? "PASS" : "FAIL", name);
  std::fflush(audit); if (!ok) std::exit(2); ++assertions;
}
static void Finalize(JSRuntime*, JSValue) { ++finalized; }
static JSValue ReturnTrace(JSContext* ctx, JSValueConst, int, JSValueConst*, int, JSValueConst*) {
  const std::string trace = venera::TraceOf(ctx); return JS_NewStringLen(ctx, trace.data(), trace.size());
}
static void Tracker(venera::QuickJsRuntime& rt) {
  JS_NewClassID(rt.runtime(), &tracker_class);
  JSClassDef def{}; def.class_name = "LifetimeTestTracker"; def.finalizer = Finalize;
  Check(JS_NewClass(rt.runtime(), tracker_class, &def) == 0, "synthetic tracker registered in actual QuickJS");
}
static JSValue Function(JSContext* ctx) {
  JSValue payload = JS_NewObjectClass(ctx, tracker_class);
  JSValue fn = JS_NewCFunctionData(ctx, ReturnTrace, 0, 0, 1, &payload);
  JS_FreeValue(ctx, payload); return fn;
}
static void Collect(venera::QuickJsRuntime& rt) { JS_RunGC(rt.runtime()); }
int main(int argc, char** argv) {
  audit = argc > 1 ? std::fopen(argv[1], "w") : stdout; if (!audit) return 3;
  std::fprintf(audit, "Production LifetimeRegistry + QuickJS; synthetic values only; NOT phone/NAPI ordering evidence.\n");
  {
    venera::QuickJsRuntime rt; Tracker(rt); auto* ctx = rt.context();
    auto registry = std::make_shared<venera::LifetimeRegistry>(ctx, 7);
    Check(registry->Active() && registry->LiveRoots() == 0, "new owner generation starts with no roots");
    JSValue fn = Function(ctx); auto root = registry->Own(fn, JS_UNDEFINED, "owner-A");
    JS_FreeValue(ctx, fn); Collect(rt);
    Check(finalized == 0 && registry->Valid(root) && registry->LiveRoots() == 1, "registry duplicates actual JS root after caller drops reference");
    int token = 0;
    Check(registry->BindExternal(&token, root), "external token registered before lookup");
    Check(registry->LookupExternal(&token) == root && registry->ExternalCount() == 1, "known external membership returns owned root");
    Check(!registry->LookupExternal(reinterpret_cast<const void*>(1)), "foreign pointer rejected without reading invalid address");
    Check(!registry->BindExternal(&token, root), "duplicate external token rejected");
    {
      venera::TraceScope scope(ctx, root->trace);
      JSValue result = JS_Call(ctx, root->first, JS_UNDEFINED, 0, nullptr);
      Check(rt.JsonStringify(result) == "\"owner-A\"", "captured owner trace remains available for native invocation");
      JS_FreeValue(ctx, result);
    }
    registry->ReleaseExternal(&token); Collect(rt);
    Check(finalized == 1 && registry->LiveRoots() == 0 && registry->ExternalCount() == 0, "external release frees exact JS root once");
    Check(root->ctx == nullptr && JS_IsUndefined(root->first) && !registry->Valid(root), "released holder becomes inert tombstone");
    registry->ReleaseExternal(&token); registry->Release(root); Collect(rt);
    Check(finalized == 1, "duplicate external/finalizer release does not free twice");
    Check(!registry->Claim(root), "late callback cannot claim released root");

    JSValue pair[2]; JSValue promise = JS_NewPromiseCapability(ctx, pair);
    auto capability = registry->Own(pair[0], pair[1], "promise-owner");
    JS_FreeValue(ctx, pair[0]); JS_FreeValue(ctx, pair[1]);
    Check(registry->Claim(capability) && !registry->Claim(capability), "resolve/reject capability has exactly one winner before user code");
    JSValue value = JS_NewInt32(ctx, 42);
    JSValue returned = JS_Call(ctx, capability->first, JS_UNDEFINED, 1, &value);
    JS_FreeValue(ctx, returned); JS_FreeValue(ctx, value); rt.PumpJobs();
    Check(JS_PromiseState(ctx, promise) == JS_PROMISE_FULFILLED, "winning production capability settles actual QuickJS promise");
    JSValue answer = JS_PromiseResult(ctx, promise); int32_t number = 0; JS_ToInt32(ctx, &number, answer);
    Check(number == 42, "fulfilled promise returns exact synthetic value");
    JS_FreeValue(ctx, answer); JS_FreeValue(ctx, promise); registry->Release(capability);
    Check(registry->LiveRoots() == 0 && !registry->Claim(capability), "settled capability release prevents subsequent callbacks");

    JSValue kept = Function(ctx); auto old = registry->Own(kept); JS_FreeValue(ctx, kept);
    venera::LifetimeRegistry another(ctx, 8);
    Check(!another.Valid(old) && !another.Claim(old), "same context different epoch cannot adopt old owner root");
    auto fake = std::make_shared<venera::LifetimeRoot>(); fake->ctx=ctx; fake->generation=7; fake->id=old->id;
    Check(!registry->Valid(fake), "forged root identity rejected despite matching context/id/generation");
    registry->Shutdown(); Collect(rt);
    Check(finalized == 2 && !registry->Active() && registry->LiveRoots() == 0, "shutdown invalidates and frees outstanding JS roots before context destruction");
    Check(!registry->Own(JS_UNDEFINED) && !registry->LookupExternal(&token), "closed registry cannot resurrect roots/external lookup");
    registry->Shutdown(); registry->Release(old);
    Check(finalized == 2, "shutdown and late release are idempotent");
  }
  std::shared_ptr<venera::LifetimeRegistry> late_registry;
  std::vector<venera::LifetimeRegistry::RootPtr> late_roots;
  {
    auto rt = std::make_unique<venera::QuickJsRuntime>(); Tracker(*rt);
    late_registry = std::make_shared<venera::LifetimeRegistry>(rt->context(), 9);
    for (int i=0;i<128;++i) {
      JSValue fn = Function(rt->context()); late_roots.push_back(late_registry->Own(fn)); JS_FreeValue(rt->context(),fn);
    }
    Check(late_registry->LiveRoots()==128 && finalized==2, "stress: 128 unresolved roots remain owned until shutdown");
    late_registry->Shutdown(); Collect(*rt);
    Check(finalized==130 && late_registry->LiveRoots()==0, "stress shutdown releases all 128 native JS payloads");
    rt.reset();
  }
  bool all_inert = true;
  for (auto& root : late_roots) all_inert &= root->ctx==nullptr && !late_registry->Valid(root);
  Check(all_inert, "all128 holders remain inert after real context/runtime destruction");
  late_roots.clear(); late_registry.reset();
  Check(finalized==130, "late C++ holder/finalizer destruction never touches freed QuickJS context");
  std::fprintf(audit,"NATIVE_LIFETIME_PASS assertions=%d finalized=%d\n", assertions, finalized);
  if (audit != stdout) std::fclose(audit);
  std::printf("NATIVE_LIFETIME_PASS assertions=%d finalized=%d\n", assertions, finalized); return 0;
}
