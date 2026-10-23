# QuickJS runtime + NAPI bridge for Venera HM comic source scripts.
#
# The Flutter build used flutter_qjs (an NDK build of QuickJS plus Dart FFI).
# HarmonyOS has no such binding, so this module compiles the QuickJS sources
# directly into a shared library and exposes them to ArkTS over NAPI.

cmake_minimum_required(VERSION 3.5.0)
project(venera_js C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(QJS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/quickjs)

# ---------------------------------------------------------------- QuickJS core
add_library(quickjs STATIC
    ${QJS_DIR}/dtoa.c
    ${QJS_DIR}/libregexp.c
    ${QJS_DIR}/libunicode.c
    ${QJS_DIR}/quickjs.c
)
target_include_directories(quickjs PUBLIC ${QJS_DIR})
target_compile_definitions(quickjs PRIVATE
    CONFIG_VERSION="0.17.0"
    _GNU_SOURCE
)
# libm is required for the math builtins; OHOS also provides liblog.
target_link_libraries(quickjs PUBLIC m)

# ------------------------------------------------------------------- NAPI glue
add_library(venera_brotli STATIC
    brotli/c/common/constants.c brotli/c/common/context.c
    brotli/c/common/dictionary.c brotli/c/common/platform.c
    brotli/c/common/shared_dictionary.c brotli/c/common/transform.c
    brotli/c/dec/bit_reader.c brotli/c/dec/decode.c
    brotli/c/dec/huffman.c brotli/c/dec/prefix.c
    brotli/c/dec/state.c brotli/c/dec/static_init.c)
target_include_directories(venera_brotli PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/brotli/c/include")
target_compile_definitions(venera_brotli PRIVATE BROTLI_BUILD_PORTABLE)
set_target_properties(venera_brotli PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(venerajs SHARED
    napi_init.cpp
    js_engine.cpp
    isolated_engine.cpp
    worker_napi.cpp
)
target_include_directories(venerajs PRIVATE ${QJS_DIR})
target_link_libraries(venerajs PUBLIC libace_napi.z.so quickjs venera_brotli z)
