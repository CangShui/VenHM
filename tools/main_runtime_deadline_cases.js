'use strict';
// Actual production NAPI addon; synthetic scripts only, never UI/network/secrets.
// Every case runs in a separate externally bounded process: a Node timer cannot
// interrupt a synchronous native QuickJS call. NOT device or off-UI-thread proof.
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const addon = path.resolve(__dirname, '../logs/napi-host/venerajs.node');
const cases = ['evaluate-loop', 'call-loop', 'callback-loop', 'await-loop',
  'host-await-loop', 'host-await-empty-trace', 'compute-await-loop',
  'microtask-quota', 'hostile-microtasks', 'network-wait', 'nested-entry',
  'pump-fault-name', 'pump-fault-create', 'pump-fault-queue', 'pump-fault-complete'];
const mode = process.argv[2];
if (!mode) {
  for (const name of cases) {
    const result = spawnSync(process.execPath, ['--expose-gc', __filename, name], {
      stdio: 'inherit', timeout: 15000,
      env: { ...process.env, VENERA_HOST_MAIN_PUMP_FAULT: name.startsWith('pump-fault-') ? name.slice(11) : '' }
    });
    assert.equal(result.error, undefined, `external process watchdog: ${name}`);
    assert.equal(result.status, 0, `deadline case failed: ${name}`);
  }
  console.log(`MAIN_RUNTIME_DEADLINE_PASS cases=${cases.length}; actual host NAPI only`);
} else {
  assert(cases.includes(mode));
  const native = require(addon);
  const events = [];
  let nested;
  native.setMessageHandler(message => {
    events.push({ method: message.method, trace: message.__veneraTraceId });
    if (message.method === 'delay') return new Promise(resolve => setTimeout(() => resolve(42), message.ms));
    if (message.method === 'nested') return nested();
    throw Error('unexpected synthetic method');
  });
  const started = Date.now();
  const loop = 'while(true){}';
  const recover = async () => {
    assert.equal(await native.callJson('21+21'), 42);
    const stats = native.runtimeStats();
    assert.equal(stats.activeEntries, 0);
    assert.equal(stats.pendingCalls, 0);
    assert.equal(stats.ownershipUncertain, false);
    assert.equal(stats.mainPumpScheduleFailures, 0);
  };
  const interrupted = error => /interrupt|budget|deadline/i.test(String(error));
  (async () => {
    switch (mode) {
      case 'evaluate-loop':
        assert.throws(() => native.evaluate(loop), interrupted);
        break;
      case 'call-loop':
        await assert.rejects(native.callJson(loop), interrupted);
        break;
      case 'callback-loop': {
        let handle = await native.callJson('()=>{while(true){}}');
        await assert.rejects(native.invokeFunction(handle, []), interrupted);
        handle = null;
        break;
      }
      case 'await-loop':
        await assert.rejects(native.callJson('(async()=>{await Promise.resolve();while(true){}})()'), interrupted);
        break;
      case 'host-await-loop':
      case 'host-await-empty-trace': {
        const trace = mode === 'host-await-loop' ? 'shared-owner' : '';
        // Deliberately share the SAME trace (including empty default elsewhere):
        // rejecting by a trace string would incorrectly cancel unrelated calls.
        const survivor = native.callJson('(async()=>{await __nativeSendMessage({method:"delay",ms:30});return 42})()', '<survivor>', trace);
        const runaway = native.callJson('(async()=>{await __nativeSendMessage({method:"delay",ms:5});while(true){}})()', '<runaway>', trace);
        const rejected = assert.rejects(runaway, interrupted);
        assert.equal(await survivor, 42);
        await rejected;
        assert(events.every(event => event.trace === trace));
        break;
      }
      case 'compute-await-loop': {
        native.configureIsolated('', '', () => { throw Error('unexpected worker RPC'); }, () => {});
        const survivor = native.callJson('(async()=>{await __nativeSendMessage({method:"delay",ms:30});return 42})()', '<compute-survivor>', 'shared-owner');
        const runaway = native.callJson('(async()=>{await __nativeSendMessage({method:"compute",function:"()=>42",args:[]});while(true){}})()', '<compute-runaway>', 'shared-owner');
        const rejected = assert.rejects(runaway, interrupted);
        assert.equal(await survivor, 42);
        await rejected;
        break;
      }
      case 'hostile-microtasks': {
        // An endlessly replenished queue cannot be "terminated" by a quota.
        // Demonstrate bounded host turns; then stop the SYNTHETIC producer.
        const progress = native.callJson('globalThis.__produce=true;globalThis.__ticks=0;globalThis.__f=()=>{__ticks++;if(__produce)Promise.resolve().then(__f)};__f();42');
        assert.equal(await progress, 42);
        await new Promise(resolve => setTimeout(resolve, 30));
        native.evaluate('__produce=false');
        assert(Number(native.evaluate('__ticks')) > 4096);
        assert(native.runtimeStats().mainDrainYields > 0);
        break;
      }
      case 'pump-fault-name':
      case 'pump-fault-create':
      case 'pump-fault-queue':
      case 'pump-fault-complete': {
        const innocent = native.callJson('(async()=>{await __nativeSendMessage({method:"delay",ms:100});return 42})()', '<backend-innocent>');
        const innocentRejected = assert.rejects(innocent, /scheduler failed; runtime closed/);
        const queued = native.callJson('(async()=>{for(let i=0;i<25000;i++)await Promise.resolve();return 42})()', '<backend-quota>');
        await assert.rejects(queued, /scheduler failed; runtime closed/);
        await innocentRejected;
        const stats = native.runtimeStats();
        assert.equal(stats.active, false);
        assert.equal(stats.pendingCalls, 0);
        assert.equal(stats.ownedRoots, 0);
        assert.equal(stats.activeEntries, 0);
        assert.equal(stats.mainPumpScheduleFailures, 1);
        assert.throws(() => native.callJson('42'), /closed/);
        console.log(`MAIN_RUNTIME_CASE_PASS ${mode}`);
        return; // Terminal global backend fault deliberately cannot recover.
      }
      case 'microtask-quota': {
        // More jobs than a single drain quota: completion requires automatic
        // later pumps, not an unrelated evaluate/HTTP event to rescue the queue.
        const progress = native.callJson('(async()=>{for(let i=0;i<25000;i++)await Promise.resolve();return 42})()');
        let beats = 0;
        const heartbeat = setInterval(() => beats++, 1);
        assert.equal(await progress, 42);
        clearInterval(heartbeat);
        assert(beats > 0, 'drain quota must yield to the host event loop');
        break;
      }
      case 'network-wait':
        assert.equal(await native.callJson('(async()=>{await __nativeSendMessage({method:"delay",ms:6100});return 42})()'), 42);
        assert(Date.now() - started >= 6000);
        break;
      case 'nested-entry':
        nested = () => native.evaluate('const n=Date.now();while(Date.now()-n<3500){};42');
        await assert.rejects(native.callJson('(()=>{const n=Date.now();while(Date.now()-n<3000){};return __nativeSendMessage({method:"nested"})})()'), interrupted);
        assert(Date.now() - started < 6500, 'nested entry must not reset its outer budget');
        break;
    }
    // These cases stop the synthetic producer or wait externally, so they do not
    // spend the full uninterrupted 5s CPU budget; the others must.
    if (!['microtask-quota', 'hostile-microtasks', 'network-wait'].includes(mode)) {
      const elapsed = Date.now() - started;
      assert(elapsed >= 4500 && elapsed < 10000, `fixed 5s native budget: ${elapsed}ms`);
    }
    await recover();
    // Collect wrappers and bridge callback anchors before checking root release.
    for (let i = 0; i < 8; i++) { global.gc(); await new Promise(resolve => setImmediate(resolve)); }
    assert.equal(native.runtimeStats().ownedRoots, 0);
    console.log(`MAIN_RUNTIME_CASE_PASS ${mode}`);
  })().catch(error => { console.error(error); process.exitCode = 1; });
}
