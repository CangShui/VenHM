# Venera embedding extension: asynchronous request context

The vendored engine is not byte-identical to upstream.

This extension adds `JS_GetAsyncContext` / `JS_SetAsyncContext` and keeps an
embedding-owned JS value with:

1. Each queued microtask/job, captured when enqueued.
2. Each Promise reaction, captured when `then`/`await` registers the continuation.

At execution the reaction's registration context takes precedence over the
resolver's job context. Previous context is restored on normal/error paths.
Retained values are freed with jobs/reactions, and reaction contexts participate
in the Promise GC marker. Venera uses strings only, not a JS-visible mutable
global or hidden property on source objects.

This is necessary because this upstream snapshot's Promise BEFORE/AFTER hook
does not wrap every ordinary Promise reaction/await continuation. Merely setting
one global “current login trace” would misattribute concurrent requests.

The production engine is exercised by `tools/native_runtime_tests/trace_cases.cpp`
compiled as a native host executable. `logs/native-runtime-host/audit.log` records
interleaving/shared-Promise/catch-finally/nested/GC evidence. This does not replace
the packaged HarmonyOS NAPI startup or real application acceptance.
