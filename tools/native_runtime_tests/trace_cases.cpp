#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>
#include "js_engine.h"
#include "trace_context.h"

static std::map<std::string, JSValue> resolving;
static std::map<std::string, JSValue> rejecting;
static std::vector<std::string> events;
static FILE* output = nullptr;
static int assertions = 0;
static venera::QuickJsRuntime* active_runtime = nullptr;
static JSValue job(JSContext* ctx, int argc, JSValueConst* argv) {
  const char* c = argc ? JS_ToCString(ctx, argv[0]) : nullptr;
  std::string label = c ? c : "";
  if (c) JS_FreeCString(ctx, c);
  events.push_back(venera::TraceOf(ctx) + ":" + label);
  if (label == "outer") {
    active_runtime->PumpJobs();
    events.push_back(venera::TraceOf(ctx) + ":restored-after-nested");
  }
  return JS_UNDEFINED;
}
static void audit(const char* phase, const std::string& text) {
  std::fprintf(output, "TraceID=native-trace-tests [%s] %s\n", phase, text.c_str());
  std::fflush(output);
}
static std::string text(JSContext* ctx, JSValueConst value) {
  const char* c = JS_ToCString(ctx, value);
  std::string result = c ? c : "";
  if (c) JS_FreeCString(ctx, c);
  return result;
}
static JSValue emit(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
  std::string label = argc ? text(ctx, argv[0]) : "";
  events.push_back(venera::TraceOf(ctx) + ":" + label);
  audit("原生消息", events.back());
  return JS_UNDEFINED;
}
static JSValue defer(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
  const auto key = text(ctx, argv[0]);
  JSValue pair[2];
  JSValue promise = JS_NewPromiseCapability(ctx, pair);
  resolving.emplace(key, pair[0]); rejecting.emplace(key, pair[1]);
  return promise;
}
static void check(bool pass, const char* label) {
  if (!pass) { audit("FAIL", label); std::exit(2); }
  assertions++; audit("PASS", label);
}
static void evaluate(venera::QuickJsRuntime& rt, const std::string& code, const std::string& trace = "") {
  venera::TraceScope scope(rt.context(), trace);
  JSValue value;
  std::string error;
  check(rt.EvaluateRaw(code, "<native-trace-case>", &value, &error), error.empty() ? "JS execution" : error.c_str());
  JS_FreeValue(rt.context(), value);
}
static void settle(venera::QuickJsRuntime& rt, const std::string& key, bool fail = false) {
  venera::TraceScope scope(rt.context(), "resolver-noise");
  auto& selected = fail ? rejecting : resolving;
  check(selected.count(key) == 1, "deferred key exists");
  JSValue result = JS_Call(rt.context(), selected.at(key), JS_UNDEFINED, 0, nullptr);
  check(!JS_IsException(result), "deferred settles");
  JS_FreeValue(rt.context(), result);
  JS_FreeValue(rt.context(), resolving.at(key)); JS_FreeValue(rt.context(), rejecting.at(key));
  resolving.erase(key); rejecting.erase(key);
  rt.PumpJobs();
}
int main(int argc, char** argv) {
  output = argc > 1 ? std::fopen(argv[1], "w") : stdout;
  if (!output) return 3;
  audit("请求到达", "Production QuickJS+trace context; synthetic values only; no application data/UI.");
  {
    venera::QuickJsRuntime rt;
    check(rt.IsValid(), "runtime created");
    JSContext* ctx = rt.context();
    active_runtime = &rt;
    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "emit", JS_NewCFunction(ctx, emit, "emit", 1));
    JS_SetPropertyStr(ctx, global, "defer", JS_NewCFunction(ctx, defer, "defer", 1));
    JS_FreeValue(ctx, global);

    evaluate(rt, "(async()=>{emit('before');await defer('a1');emit('after1');await defer('a2');emit('after2')})()", "A");
    evaluate(rt, "(async()=>{emit('before');await defer('b1');emit('after1');await Promise.resolve();emit('after2')})()", "B");
    settle(rt, "b1"); settle(rt, "a1"); settle(rt, "a2");
    check(events == std::vector<std::string>{"A:before","B:before","B:after1","B:after2","A:after1","A:after2"},
          "await interleaving never steals another request/resolver context");
    check(venera::TraceOf(ctx).empty(), "root context restored after pumping");

    events.clear();
    evaluate(rt, "globalThis.shared=defer('shared');shared.then(()=>emit('created-A'))", "A");
    evaluate(rt, "shared.then(()=>emit('registered-B'));(async()=>{await shared;emit('await-C')})()", "B");
    settle(rt, "shared");
    check(events == std::vector<std::string>{"A:created-A","B:registered-B","B:await-C"},
          "shared promise reactions use registration context, not resolver/promise origin");

    events.clear();
    evaluate(rt, "(async()=>{try{await defer('reject')}catch(e){emit('caught')}finally{await Promise.resolve();emit('finally')}})()", "E");
    settle(rt, "reject", true);
    check(events == std::vector<std::string>{"E:caught","E:finally"}, "catch/finally retains context");
    check(venera::TraceOf(ctx).empty(), "exception path leaves no global trace");

    events.clear();
    evaluate(rt, "Promise.resolve().then(()=>{emit('nested1');return Promise.resolve()}).then(()=>emit('nested2'))", "N");
    check(events == std::vector<std::string>{"N:nested1","N:nested2"}, "nested then/assimilation context retained");
    events.clear();
    evaluate(rt, "emit('outside');Promise.resolve().then(()=>emit('outside-job'))");
    check(events == std::vector<std::string>{":outside",":outside-job"}, "untraced background work remains untraced");

    events.clear();
    evaluate(rt, "Promise.all([defer('all1'),defer('all2')]).then(()=>emit('all'))", "ALL");
    settle(rt, "all2"); settle(rt, "all1");
    check(events == std::vector<std::string>{"ALL:all"}, "Promise.all retains independent caller");

    events.clear();
    {
      venera::TraceScope a(ctx, "JOB_A");
      JSValue label = JS_NewString(ctx, "outer");
      check(JS_EnqueueJob(ctx, job, 1, &label) == 0, "generic job A queued");
      JS_FreeValue(ctx, label);
    }
    {
      venera::TraceScope b(ctx, "JOB_B");
      JSValue label = JS_NewString(ctx, "inner");
      check(JS_EnqueueJob(ctx, job, 1, &label) == 0, "generic job B queued");
      JS_FreeValue(ctx, label);
    }
    rt.PumpJobs();
    check(events == std::vector<std::string>{"JOB_A:outer","JOB_B:inner","JOB_A:restored-after-nested"},
          "reentrant job pumping restores outer owner after another request");
    check(venera::TraceOf(ctx).empty(), "generic job pumping leaves no global context");

    evaluate(rt, "defer('pending').then(()=>emit('never'))", "PENDING");
    JS_FreeValue(ctx, resolving.at("pending")); JS_FreeValue(ctx, rejecting.at("pending"));
    resolving.clear(); rejecting.clear();
    JS_RunGC(rt.runtime());
    check(venera::TraceOf(ctx).empty(), "GC with pending reaction does not change context");
  }
  audit("响应返回", "NATIVE_TRACE_PASS assertions=" + std::to_string(assertions));
  if (output != stdout) std::fclose(output);
  std::printf("NATIVE_TRACE_PASS assertions=%d\n", assertions);
  return 0;
}
