cmake_minimum_required(VERSION 3.16)
project(venera_native_runtime_tests C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CPP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../entry/src/main/cpp")
add_executable(venera_native_runtime_tests
  trace_cases.cpp
  "${CPP_DIR}/js_engine.cpp"
  "${CPP_DIR}/quickjs/dtoa.c"
  "${CPP_DIR}/quickjs/libregexp.c"
  "${CPP_DIR}/quickjs/libunicode.c"
  "${CPP_DIR}/quickjs/quickjs.c")
target_include_directories(venera_native_runtime_tests PRIVATE "${CPP_DIR}" "${CPP_DIR}/quickjs")
target_compile_definitions(venera_native_runtime_tests PRIVATE _GNU_SOURCE CONFIG_VERSION="0.17.0")
target_link_libraries(venera_native_runtime_tests PRIVATE m)
