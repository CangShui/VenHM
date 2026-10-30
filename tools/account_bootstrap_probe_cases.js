'use strict';
// Read-only audit probe: production parser/registry/page methods transpiled to Node.
// No auth callbacks, script init(), network/cookie bridge, real DB or device access.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const { SOURCE_FILES, join, read } = require('./vm_deps');
const root = path.resolve(__dirname, '..');
const logPath = path.join(root, 'logs/account-bootstrap-probe-cases.log');
const lines = ['READ-ONLY Node production-method probe. No auth/network/cookies/device/datastores.'];
let tests = 0;
function note(message) { lines.push(message); console.log(message); }
async function test(name, fn) { await fn(); tests++; note(`PASS ${name}`); }
function compile(code) { return stripTypeScriptTypes(code, { mode: 'transform' }); }
function pageCode(file, name) {
  const raw = read(file);
  return (raw.slice(0, raw.indexOf('  build() {')) + '}')
    .replace(/@Entry\s*|@Component\s*|@State\s*/g, '')
    .replace(`struct ${name}`, `class ${name}`);
}
function environment() {
  const scheduled = [], dao = [], files = new Map(), routes = [], summaries = [];
  let listCalls = 0, bridgeCalls = 0;
  const js = vm.createContext({
    appVersion: '1.17.0',
    sendMessage() { bridgeCalls++; throw Error('Host bridge forbidden in metadata-only probe'); }
  });
  vm.runInContext(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/init.js'), 'utf8'), js);
  const ctx = vm.createContext({
    APP_VERSION: '1.17.0',
    Log: { info() {}, warn() {}, error() {}, audit() {} },
    JsEngine: {
      isAvailable: true, error: '',
      evaluate(code, name) {
        const result = vm.runInContext(code, js, { filename: name });
        if (typeof result === 'string' && result.startsWith('{"name"')) summaries.push(JSON.parse(result));
        return String(result); // Production native Evaluate returns ValueToString, not JSON-wrap.
      },
      callJson() { throw Error('No script callback/init execution is allowed'); }
    },
    SourceDataStore: { preload: async () => {}, set() {}, get() { return null; } },
    SourceDao: { list: async () => { listCalls++; return dao.slice(); } },
    SourceInstaller: { scriptPath: key => `fixture/${key}.js`, listInstalled: async () => dao.slice() },
    fs: { accessSync: p => files.has(p), readTextSync: p => files.get(p) },
    setTimeout(fn) { scheduled.push(fn); return scheduled.length; },
    router: { getParams: () => ({}), pushUrl: async value => { routes.push(value); }, back() {} },
    AppInit: { init: async () => {} },
    AppContext: { ensureInitialized() {} },
    promptAction: { showToast() {} },
    SourceRepositories: { all: () => [] }
  });
  const code = join(SOURCE_FILES) + '\nclass LocalSource extends ComicSource { constructor(){super("local","Local");} }\n' +
    read('entry/src/main/ets/source/SourceManager.ets') + '\n' +
    pageCode('entry/src/main/ets/pages/SourceAccountPage.ets', 'SourceAccountPage') + '\n' +
    pageCode('entry/src/main/ets/pages/SourceManagerPage.ets', 'SourceManagerPage').replace(/\s+@Builder[\s\S]*$/, '\n}') + '\n' +
    'globalThis.auditExports={ComicSource,ComicSourceParser,SourceManager,SourceAccountPage,SourceManagerPage};';
  vm.runInContext(compile(code), ctx);
  return { ctx, js, ...ctx.auditExports, scheduled, dao, files, routes, summaries,
    bridgeCalls: () => bridgeCalls, listCalls: () => listCalls };
}
const fixture = key => fs.readFileSync(path.join(root, `logs/user8-installed-scripts/${key}.js`), 'utf8');
function useInstalled(e, keys) {
  for (const key of keys) { e.dao.push({ key, name: key }); e.files.set(`fixture/${key}.js`, fixture(key)); }
}
async function showAccount(e, params) {
  const page = new e.SourceAccountPage();
  page.getUIContext = () => ({ getHostContext() { return {}; } });
  e.ctx.router.getParams = () => params;
  page.aboutToAppear();
  await new Promise(resolve => setImmediate(resolve));
  return page;
}
(async () => {
  await test('production parser reused one init.js realm for ehentai/Komiic/wnacg twice: accounts and closures preserved', async () => {
    const e = environment();
    for (let round = 0; round < 2; round++) {
      for (const key of ['ehentai', 'Komiic', 'wnacg']) {
        const source = await e.ComicSourceParser.parse(fixture(key), `<fixture-${key}-${round}>`);
        assert.equal(source.key, key); assert.ok(source.account); assert.equal(source.account.canLogin, true);
        assert.equal(typeof source.account.logout, 'function');
        if (key === 'ehentai') {
          assert.equal(source.account.login, undefined);
          assert.equal(typeof source.account.validateCookies, 'function');
          assert.equal(typeof source.account.finishWebLogin, 'function');
          assert.equal(source.account.cookieFields.length, 4);
        } else { assert.equal(typeof source.account.login, 'function'); }
        e.SourceManager.register(source);
      }
    }
    assert.equal(e.SourceManager.all().length, 3);
    assert.equal(e.summaries.length, 6); assert.ok(e.summaries.every(s => s.has.account === true));
    assert.equal(e.bridgeCalls(), 0); assert.equal(e.scheduled.length, 6);
  });
  await test('production manager init + openLogin route + production account aboutToAppear works for both sites', async () => {
    const e = environment(); useInstalled(e, ['ehentai', 'Komiic']);
    await e.SourceManager.init();
    const managerPage = new e.SourceManagerPage();
    for (const key of ['ehentai', 'Komiic']) {
      managerPage.openLogin(e.SourceManager.find(key));
      const route = e.routes.at(-1);
      assert.equal(route.url, 'pages/SourceAccountPage'); assert.equal(route.params.key, key);
      const accountPage = await showAccount(e, route.params);
      assert.equal(accountPage.error, ''); assert.equal(accountPage.loading, false);
      assert.equal(accountPage.source.key, key); assert.ok(accountPage.source.account);
    }
    assert.equal(e.bridgeCalls(), 0);
  });
  await test('sourceKey-only routes reproduce exact error for BOTH real account-declaring fixtures', async () => {
    const e = environment(); useInstalled(e, ['ehentai', 'Komiic']); await e.SourceManager.init();
    for (const key of ['ehentai', 'Komiic']) {
      assert.ok(e.SourceManager.find(key).account);
      const page = await showAccount(e, { sourceKey: key });
      assert.equal(page.source, undefined); assert.equal(page.error, 'Error: 源未声明账号功能');
    }
  });
  await test('current page conflates unknown/missing/wrong-case source with existing source lacking account', async () => {
    const e = environment(); useInstalled(e, ['Komiic']); await e.SourceManager.init();
    for (const params of [{}, { key: 'missing' }, { key: 'komiic' }, { key: 'local' }]) {
      const page = await showAccount(e, params); assert.equal(page.error, 'Error: 源未声明账号功能');
    }
  });
  await test('manager initialized cache ignores DAO additions on re-init; correct key still has missing-source account error', async () => {
    const e = environment(); await e.SourceManager.init();
    useInstalled(e, ['ehentai', 'Komiic']); await e.SourceManager.init();
    assert.equal(e.listCalls(), 1); assert.equal(e.dao.length, 2); assert.equal(e.SourceManager.all().length, 1);
    for (const key of ['ehentai', 'Komiic']) {
      const page = await showAccount(e, { key }); assert.equal(page.source, undefined);
      assert.equal(page.error, 'Error: 源未声明账号功能');
    }
  });
  await test('duplicate registration retains old no-account ArkTS source even after fresh parser creates account source', async () => {
    const e = environment();
    const old = new e.ComicSource('Komiic', 'stale metadata'); e.SourceManager.register(old);
    const fresh = await e.ComicSourceParser.parse(fixture('Komiic'), '<fixture-Komiic>');
    assert.ok(fresh.account); e.SourceManager.register(fresh);
    assert.equal(e.SourceManager.find('Komiic'), old); assert.equal(old.account, undefined);
    const page = await showAccount(e, { key: 'Komiic' });
    assert.equal(page.source, old); assert.equal(page.error, 'Error: 源未声明账号功能');
    assert.equal(vm.runInContext('typeof ComicSource.sources.Komiic.account.login', e.js), 'function');
  });
  note(`PASS ${tests} read-only audit cases. ArkUI @State/NAPI behavior NOT emulated or proven.`);
  fs.writeFileSync(logPath, lines.join('\n') + '\n');
})().catch(error => { note(error.stack); fs.writeFileSync(logPath, lines.join('\n') + '\n'); process.exitCode = 1; });
