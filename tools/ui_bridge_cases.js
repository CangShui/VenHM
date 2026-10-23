'use strict';

// Executes the production UiBridge ETS control flow with a fake scoped
// PromptAction. It cannot prove ArkUI rendering; the device test does that.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..');
const logPath = path.join(root, 'logs', 'ui-bridge-cases.log');
fs.mkdirSync(path.dirname(logPath), { recursive: true });
fs.writeFileSync(logPath, '[请求到达] TraceID=ui-bridge-tests production control-flow regression\n');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/source/UiBridge.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
const code = stripTypeScriptTypes(source, { mode: 'transform' });
const tick = () => new Promise(resolve => setImmediate(resolve));
let count = 0;

function makeBridge({ delayed = false, fail = false, callback } = {}) {
  const opened = [], closed = [], pending = [], seen = [], audits = [];
  const scope = {
    Log: { audit: (trace, stage, message) => {
      audits.push({ trace, stage, message });
      fs.appendFileSync(logPath, `TraceID=${trace} [${stage}] ${message}\n`);
    } },
    JsEngine: { invokeFunction: async (handle, args) => callback ? callback(handle, args) : 42 },
  };
  vm.createContext(scope);
  vm.runInContext(code + '\nglobalThis.Bridge = UiBridge;', scope);
  const Bridge = scope.Bridge;
  const host = {
    getPromptAction: () => ({
      openCustomDialog: options => {
        opened.push(options);
        options.builder();
        if (fail) return Promise.reject(new Error('mock-open-failed'));
        if (delayed) return new Promise(resolve => pending.push(resolve));
        return Promise.resolve(opened.length);
      },
      closeCustomDialog: id => closed.push(id),
    }),
  };
  Bridge.registerBuilder(() => seen.push(Bridge.currentRequest()), host);
  return { Bridge, opened, closed, pending, seen, audits, host };
}

async function check(name, action) {
  fs.appendFileSync(logPath, `[业务入口] TraceID=ui-bridge-tests case=${name}\n`);
  await action();
  count++;
  fs.appendFileSync(logPath, `[响应返回] TraceID=ui-bridge-tests PASS ${name}\n`);
}

(async () => {
  await check('component-owned builder registration', async () => {
    const index = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
    assert.match(index, /UiBridge\.registerBuilder\(\(\): void => this\.sourceDialog\(\), this\.getUIContext\(\)\)/);
    assert.match(index, /@Builder\s+sourceDialog\(\)/);
    const init = fs.readFileSync(path.join(root, 'entry/src/main/ets/foundation/AppInit.ets'), 'utf8');
    assert.doesNotMatch(init, /installUiDialog/);
  });
  await check('input resolves and closes via scoped UIContext', async () => {
    const { Bridge, opened, closed, audits } = makeBridge();
    const answer = Bridge.showInputDialog('fixture', undefined, '');
    await tick();
    assert.equal(opened.length, 1);
    Bridge.finishInput('42');
    assert.equal(await answer, '42');
    assert.deepEqual(closed, [1]);
    assert.equal(Bridge.currentRequest(), undefined);
    const traces = new Set(audits.filter(a => a.trace !== 'ui-host').map(a => a.trace));
    assert.equal(traces.size, 1, 'one TraceID for request/render/response');
    assert.ok(audits.some(a => a.stage === '响应返回'));
  });
  await check('serial queue does not overlap dialogs', async () => {
    const { Bridge, opened, closed } = makeBridge();
    const first = Bridge.showInputDialog('first', undefined, '');
    const second = Bridge.showSelectDialog('second', ['a', 'b'], 1);
    await tick();
    assert.equal(opened.length, 1);
    Bridge.cancelAnswer();
    assert.equal(await first, null);
    await tick();
    assert.equal(opened.length, 2);
    assert.deepEqual(closed, [1]);
    Bridge.finishSelect(1);
    assert.equal(await second, 1);
    assert.deepEqual(closed, [1, 2]);
  });
  await check('empty options are rejected without rendering', async () => {
    const { Bridge, opened } = makeBridge();
    assert.equal(await Bridge.showSelectDialog('empty', [], 0), null);
    assert.equal(opened.length, 0);
  });
  await check('invalid initial index is discarded', async () => {
    const { Bridge } = makeBridge();
    const answer = Bridge.showSelectDialog('select', ['a'], 99);
    await tick();
    assert.equal(Bridge.currentRequest().initialIndex, -1);
    Bridge.cancelAnswer();
    assert.equal(await answer, null);
  });
  await check('same-tick loading cancellation never opens', async () => {
    const { Bridge, opened } = makeBridge();
    const id = Bridge.showLoading(undefined);
    Bridge.cancelLoading(id);
    await tick();
    assert.equal(opened.length, 0);
    const next = Bridge.showDialog('next', '', []);
    await tick();
    assert.equal(opened.length, 1);
    Bridge.finishDialog(-1);
    assert.equal(await next, -1);
  });
  await check('visible loading cancellation closes and releases queue', async () => {
    const { Bridge, closed } = makeBridge();
    const id = Bridge.showLoading(undefined);
    await tick();
    Bridge.cancelLoading(id);
    await tick();
    assert.deepEqual(closed, [1]);
    assert.equal(Bridge.currentRequest(), undefined);
  });
  await check('cancel while opening closes late dialog before next opens', async () => {
    const { Bridge, pending, opened, closed } = makeBridge({ delayed: true });
    const id = Bridge.showLoading(undefined);
    await tick();
    Bridge.cancelLoading(id);
    const next = Bridge.showInputDialog('next', undefined, '');
    await tick();
    assert.equal(opened.length, 1, 'queue waits for pending open to close');
    pending.shift()(11);
    await tick();
    assert.deepEqual(closed, [11]);
    assert.equal(opened.length, 2);
    pending.shift()(12);
    await tick();
    Bridge.cancelAnswer();
    assert.equal(await next, null);
    assert.deepEqual(closed, [11, 12]);
  });
  await check('answer while opening closes late dialog with original result', async () => {
    const { Bridge, pending, closed } = makeBridge({ delayed: true });
    const answer = Bridge.showInputDialog('early', undefined, '');
    await tick();
    Bridge.finishInput('42');
    pending.shift()(7);
    assert.equal(await answer, '42');
    assert.deepEqual(closed, [7]);
  });
  await check('open failures settle null and do not poison queue', async () => {
    const { Bridge } = makeBridge({ fail: true });
    assert.equal(await Bridge.showInputDialog('fail1', undefined, ''), null);
    assert.equal(await Bridge.showInputDialog('fail2', undefined, ''), null);
    assert.equal(Bridge.currentRequest(), undefined);
  });
  await check('onCancel waits for callback and ignores duplicate cancellation', async () => {
    let calls = 0, release;
    const { Bridge, closed } = makeBridge({ callback: () => {
      calls++;
      return new Promise(resolve => { release = resolve; });
    } });
    Bridge.showLoading({});
    await tick();
    const cancel = Bridge.cancelLoadingRequest();
    await Bridge.cancelLoadingRequest();
    assert.equal(calls, 1);
    assert.equal(closed.length, 0);
    release(null);
    await cancel;
    await tick();
    assert.deepEqual(closed, [1]);
  });
  await check('onCancel exception still releases the dialog', async () => {
    const { Bridge, closed } = makeBridge({ callback: () => Promise.reject(new Error('fixture-throw')) });
    Bridge.showLoading({});
    await tick();
    await Bridge.cancelLoadingRequest();
    await tick();
    assert.deepEqual(closed, [1]);
  });
  await check('unknown cancellation cannot close an unrelated input', async () => {
    const { Bridge, closed } = makeBridge();
    const answer = Bridge.showInputDialog('input', undefined, '');
    await tick();
    Bridge.cancelLoading(99999);
    assert.equal(closed.length, 0);
    Bridge.cancelAnswer();
    assert.equal(await answer, null);
  });
  await check('self-test awaits callbacks with unchanged void showDialog API', async () => {
    const selfTest = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/UiUsability.ets'), 'utf8')
      .replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
    let inputs = 0, selects = 0, loading = 0;
    const context = vm.createContext({
      sendMessage: message => {
        if (message.method === 'delay') return Promise.resolve();
        assert.equal(message.method, 'UI');
        switch (message.function) {
          case 'showInputDialog': return Promise.resolve(inputs++ === 0 ? '42' : null);
          case 'showSelectDialog': return Promise.resolve(selects++ === 0 ? 2 : null);
          case 'showDialog': {
            if (message.actions.length > 0) {
              Promise.resolve().then(() => message.actions.at(-1).callback());
            }
            return Promise.resolve(null);
          }
          case 'showLoading': {
            const id = loading++;
            if (message.onCancel) Promise.resolve().then(message.onCancel);
            return id;
          }
          case 'cancelLoading':
          case 'showMessage': return null;
          default: throw new Error(`Unhandled UI action ${message.function}`);
        }
      },
    });
    vm.runInContext(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/init.js'), 'utf8'), context);
    vm.runInContext(stripTypeScriptTypes(selfTest, { mode: 'transform' }), context);
    const result = await vm.runInContext('eval(UiUsability.script)', context);
    assert.match(result, /^PASS \| input=42 \| select=2 \| dialog=1/);
    assert.match(result, /cancelInput=null \| cancelSelect=null \| onCancel=1$/);
    assert.equal(loading, 3);
  });
  const summary = `PASS ${count} production UI-bridge cases (not ArkUI rendering).`;
  fs.appendFileSync(logPath, `[响应返回] TraceID=ui-bridge-tests ${summary}\n`);
  console.log(summary);
})().catch(error => {
  fs.appendFileSync(logPath, `[异常] TraceID=ui-bridge-tests ${error.stack}\n`);
  console.error(error);
  process.exitCode = 1;
});
