#ifndef VENERA_WORKER_NAPI_H
#define VENERA_WORKER_NAPI_H
#include "napi/native_api.h"
#include "quickjs.h"
namespace venera {
napi_value ConfigureIsolated(napi_env env, napi_callback_info info);
napi_value ComputeIsolated(napi_env env, napi_callback_info info);
napi_value TransformIsolated(napi_env env, napi_callback_info info);
napi_value CancelIsolated(napi_env env, napi_callback_info info);
/** Main-thread environment cleanup: cancel/join producers and release caller capabilities. */
void ShutdownIsolated(napi_env env);
/** Called before converting source compute args into ArkTS; preserves structured cycles/types. */
JSValue QueueComputeFromJs(napi_env env, JSContext* ctx, JSValueConst message);
}
#endif
