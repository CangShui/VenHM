#ifndef VENERA_JS_ENGINE_H
#define VENERA_JS_ENGINE_H

#include <string>

#include "quickjs.h"

namespace venera {

/**
 * One QuickJS runtime + context.
 *
 * Mirrors the Dart side's FlutterQjs instance: a single global script runtime
 * plus a separate pool for `compute()` (the pool is a later milestone).
 */
class QuickJsRuntime {
 public:
  QuickJsRuntime();
  ~QuickJsRuntime();

  QuickJsRuntime(const QuickJsRuntime&) = delete;
  QuickJsRuntime& operator=(const QuickJsRuntime&) = delete;

  bool IsValid() const { return context_ != nullptr; }

  /**
   * Evaluate a script in the global scope.
   * Returns true on success and fills `result`; on failure fills `error` with
   * the JS exception message.
   */
  bool Evaluate(const std::string& code, const std::string& filename,
                std::string* result, std::string* error);

  /**
   * Evaluate and hand back the raw JS value (caller owns it and must
   * JS_FreeValue it). Used by callJson, which needs to inspect whether the
   * result is a promise.
   */
  bool EvaluateRaw(const std::string& code, const std::string& filename,
                   JSValue* out, std::string* error);

  /** JSON.stringify(value); returns "null" when stringification fails. */
  std::string JsonStringify(JSValueConst value);

  /**
   * Run queued QuickJS jobs.
   *
   * This is what makes `await` work across the boundary: when an ArkTS promise
   * settles and resolves the JS promise created by sendMessage, the awaiting
   * JS continuation is queued as a job and only runs when the queue is pumped.
   */
  void PumpJobs();

  // Main-realm opt-in only. Called before every job, including nested drains.
  // A false result yields without deleting jobs. Isolated runtimes leave this null.
  using JobPumpGate = bool (*)(void*);
  void SetJobPumpGate(JobPumpGate gate, void* opaque) { job_gate_ = gate; job_gate_opaque_ = opaque; }

  JSContext* context() const { return context_; }
  JSRuntime* runtime() const { return runtime_; }

  /** Version string reported to ArkTS for diagnostics. */
  static std::string QuickJsVersion();

 private:
  JSRuntime* runtime_ = nullptr;
  JSContext* context_ = nullptr;
  JobPumpGate job_gate_ = nullptr;
  void* job_gate_opaque_ = nullptr;
};

}  // namespace venera

#endif  // VENERA_JS_ENGINE_H
