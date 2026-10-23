#include <node_api.h>
// Separate addon: this opaque payload is deliberately NOT a Venera handle.
// Calling Venera isFunction/invoke with it must not dereference arbitrary data.
static int foreign_payload = 123;
static napi_value MakeForeign(napi_env env, napi_callback_info) {
  napi_value value = nullptr;
  if (napi_create_external(env, &foreign_payload, nullptr, nullptr, &value) != napi_ok) return nullptr;
  return value;
}
static napi_value MakeAlias(napi_env env, napi_callback_info info) {
  size_t argc=1; napi_value input=nullptr; void* payload=nullptr;
  if(napi_get_cb_info(env,info,&argc,&input,nullptr,nullptr)!=napi_ok || argc!=1 ||
      napi_unwrap(env,input,&payload)!=napi_ok) return nullptr;
  napi_value value=nullptr;
  if(napi_create_external(env,payload,nullptr,nullptr,&value)!=napi_ok) return nullptr;
  return value; // aliases a valid pointer, but is not an authentic wrapped object
}
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor p[] = {
    {"makeForeign", nullptr, MakeForeign, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"makeAlias", nullptr, MakeAlias, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, 2, p); return exports;
}
NAPI_MODULE(foreign_external, Init)
