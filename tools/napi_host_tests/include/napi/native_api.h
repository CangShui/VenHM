#ifndef VENERA_HOST_TEST_NATIVE_API_H
#define VENERA_HOST_TEST_NATIVE_API_H
// Host-test shim for the NAPI subset used by production sources. This is NOT
// compiled into the HarmonyOS application; SDK builds use the genuine header.
#include <node_api.h>
#define VENERA_HOST_NAPI_TESTS 1
#endif
