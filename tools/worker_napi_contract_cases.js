'use strict';
// Source-contract regressions only. These do NOT execute NAPI/TSFN or replace
// SDK build, host QuickJS tests, allocation-fault injection, or device stress.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const worker = fs.readFileSync(path.join(root, 'entry/src/main/cpp/worker_napi.cpp'), 'utf8');
const init = fs.readFileSync(path.join(root, 'entry/src/main/cpp/napi_init.cpp'), 'utf8');
let count = 0;
function test(name, run) { run(); ++count; console.log(`PASS ${name}`); }
function body(source, start, end) {
  const a = source.indexOf(start); assert.ok(a >= 0, start);
  const b = source.indexOf(end, a + start.length); assert.ok(b > a, end);
  return source.slice(a, b);
}
test('image admission precedes native pixel copy', () => {
  const transform = body(worker, 'napi_value TransformIsolated(', 'napi_value CancelIsolated(');
  assert.ok(transform.indexOf('Reserve(job,') < transform.indexOf('job->pixels.rgba.assign('));
  assert.match(transform, /!job->pixels.width \|\| !job->pixels.height/);
  assert.match(transform, /napi_get_arraybuffer_info\([^\n]+!= napi_ok/);
});
test('transport budget counts retained jobs and bounded maximum result', () => {
  assert.match(worker, /kTransferBudget = 384 \* 1024 \* 1024/);
  assert.match(worker, /reserved_jobs >= 32/);
  assert.match(worker, /size > kTransferBudget - reserved_bytes/);
  const limit = 384 * 1024 * 1024, maximumInput = 128 * 1024 * 1024;
  assert.equal(Math.floor(limit / (maximumInput + maximumInput + 1)), 1);
  assert.ok(32 * maximumInput > limit);
  assert.match(worker, /~Job\(\)[\s\S]*reserved_bytes -= reservation; --reserved_jobs/);
});
test('compute arguments bypass recursive ArkTS bridge', () => {
  const dispatch = body(init, 'JSValue QjsSendMessage(', 'JSValue QjsCurrentTrace(');
  assert.ok(dispatch.indexOf('QueueComputeFromJs(') < dispatch.indexOf('venera::JsToNapi('));
  assert.match(worker, /JS_NewPromiseCapability\(ctx, pair\);\s*if \(JS_IsException\(promise\)\) return promise;/);
});
test('nested compute rejects before a blocking host RPC', () => {
  const rpc = body(worker, 'JSValue RpcCall(', 'class Pool {');
  assert.ok(rpc.indexOf('nested compute is unsupported') < rpc.indexOf('napi_call_threadsafe_function('));
  assert.ok(rpc.indexOf('CheckWorkerRpcTree(') < rpc.indexOf('IsolatedEngine::Serialize('));
});
test('pool threads do not retain stale QuickJS realms', () => {
  assert.match(worker, /Slot slots\[4\]/);
  assert.doesNotMatch(worker, /slot\.engine|\.Reset\(|\.Detach\(/);
  assert.match(worker, /IsolatedEngine engine\(job->control.get\(\), 128 \* 1024 \* 1024, 0, rpc\)/);
});
test('TSFN bounded queue retains job until finalization', () => {
  assert.match(worker, /napi_create_threadsafe_function\([^\n]+resource, 2, 1, owner, FinalizeChannel/);
  assert.match(worker, /napi_release_threadsafe_function\(job->channel, napi_tsfn_release\)/);
  assert.match(worker, /void FinalizeChannel\(/);
  const cleanup = body(worker, 'void Cleanup() {', 'bool Queue(napi_env');
  assert.ok(cleanup.indexOf('cancelled.store(true)') < cleanup.indexOf('pool.reset()'));
  assert.ok(cleanup.indexOf('pool.reset()') < cleanup.indexOf('FreeCaller(job)'));
});
test('failed output ArrayBuffer never reaches memcpy', () => {
  assert.match(worker, /napi_create_arraybuffer\(env, result\.pixels\.rgba\.size\(\), &buffer, &rgba\) == napi_ok/);
  assert.match(worker, /\(result\.pixels\.rgba\.empty\(\) \|\| buffer\)/);
  assert.match(worker, /if \(ok && !result\.pixels\.rgba\.empty\(\)\) std::memcpy/);
});
console.log(`PASS ${count} worker source-contract regressions; runtime/device behavior is NOT tested here.`);
