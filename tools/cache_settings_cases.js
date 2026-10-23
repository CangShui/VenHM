'use strict';
/**
 * CacheSettings / CacheManager cases.
 *
 * Runs the real .ets sources (types stripped) with a fake `Settings` preference
 * store and a REAL temp filesystem for the cache, download and history
 * directories. Proves the default 1 GiB cap, persistence, rejection of invalid
 * values, and that clearing the cache never deletes downloads or history.
 */
const fsNode = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');

const root = path.resolve(__dirname, '..');
const log = path.join(root, 'logs/cache-settings-cases.log');
fsNode.mkdirSync(path.dirname(log), { recursive: true });
fsNode.writeFileSync(log, 'CacheSettings/CacheManager; fake preferences, real temp filesystem, no device.\n');

const read = p => fsNode.readFileSync(path.join(root, p), 'utf8')
  .replace(/^import .*;\r?\n/gm, '')
  .replace(/\bexport /g, '');

const GIB = 1024 * 1024 * 1024;

// ---- harness ---------------------------------------------------------------

const tempDirs = [];
function tempRoot(label) {
  const dir = fsNode.mkdtempSync(path.join(os.tmpdir(), `venera-cache-settings-${label}-`));
  tempDirs.push(dir);
  return dir;
}

function bytesOf(length, fill) {
  return Uint8Array.from(new Array(length).fill(fill)).buffer;
}

function fakeFs() {
  const OM = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
  return {
    OpenMode: OM,
    accessSync: p => { try { fsNode.accessSync(p); return true; } catch (error) { return false; } },
    mkdirSync: (p, recursive) => { fsNode.mkdirSync(p, { recursive: recursive === true }); },
    openSync: (p, mode) => {
      if ((mode & OM.CREATE) !== 0) {
        fsNode.mkdirSync(path.dirname(p), { recursive: true });
        fsNode.closeSync(fsNode.openSync(p, (mode & OM.TRUNC) !== 0 ? 'w' : 'a'));
      }
      return { fd: fsNode.openSync(p, (mode & OM.WRITE_ONLY) !== 0 ? 'r+' : 'r') };
    },
    closeSync: handle => { try { fsNode.closeSync(handle.fd); } catch (error) { /* already closed */ } },
    readSync: (fd, buffer) => fsNode.readSync(fd, Buffer.from(buffer), 0, buffer.byteLength, 0),
    writeSync: (fd, data) => {
      if (typeof data === 'string') {
        fsNode.writeSync(fd, data, 0, 'utf8');
        return Buffer.byteLength(data);
      }
      const view = Buffer.from(data);
      fsNode.writeSync(fd, view, 0, view.length, 0);
      return view.length;
    },
    statSync: p => {
      const stat = fsNode.statSync(p);
      return {
        size: stat.size,
        mtime: stat.mtimeMs,
        isFile: () => stat.isFile(),
        isDirectory: () => stat.isDirectory()
      };
    },
    unlinkSync: p => fsNode.unlinkSync(p),
    renameSync: (from, to) => fsNode.renameSync(from, to),
    listFileSync: p => fsNode.readdirSync(p),
    readTextSync: p => fsNode.readFileSync(p, 'utf8')
  };
}

function utilFake() {
  return {
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
    TextDecoder: {
      create: charset => ({ decodeToString: value => new TextDecoder(charset).decode(value) })
    }
  };
}

/**
 * Preference store shared by every sandbox in a case, so "restart" is a new vm
 * context reading the same persisted values.
 */
function preferenceState(initial) {
  return { values: new Map(Object.entries(initial ?? {})), writes: [], mode: 'ready' };
}

function settingsSandbox(options) {
  const state = options.state;
  const dirs = {
    filesDir: options.filesDir,
    cacheDir: options.cacheDir,
    imageCacheDir: path.join(options.cacheDir, 'images')
  };
  const context = vm.createContext({
    fs: fakeFs(),
    util: utilFake(),
    Log: { audit: () => {}, info: () => {}, warn: () => {}, error: () => {} },
    ArrayBuffer,
    Uint8Array,
    AppContext: dirs,
    Settings: {
      getInt: (key, fallback) => {
        if (state.mode === 'uninitialized') { throw new Error('Settings.init() has not been called'); }
        const value = state.values.get(key);
        return typeof value === 'number' ? Math.trunc(value) : fallback;
      },
      setInt: async (key, value) => {
        if (state.mode === 'uninitialized') { throw new Error('Settings.init() has not been called'); }
        state.writes.push({ key: key, value: value });
        state.values.set(key, value);
      }
    }
  });
  const script = read('entry/src/main/ets/foundation/CacheStore.ets') + '\n' +
    read('entry/src/main/ets/storage/CacheSettings.ets');
  vm.runInContext(stripTypeScriptTypes(script, { mode: 'transform' }) +
    '\nglobalThis.CacheStore=CacheStore;globalThis.PayloadCache=PayloadCache;globalThis.CacheStats=CacheStats;' +
    'globalThis.CacheSettings=CacheSettings;globalThis.CacheManager=CacheManager;globalThis.CacheLimitOption=CacheLimitOption;',
  context);
  return {
    context,
    CacheSettings: context.CacheSettings,
    CacheManager: context.CacheManager,
    dirs
  };
}

function workspace(label) {
  const dir = tempRoot(label);
  const filesDir = path.join(dir, 'files');
  const cacheDir = path.join(dir, 'cache');
  fsNode.mkdirSync(filesDir, { recursive: true });
  fsNode.mkdirSync(cacheDir, { recursive: true });
  return { dir, filesDir, cacheDir };
}

function cachedFiles(cacheDir) {
  const images = path.join(cacheDir, 'images');
  if (!fsNode.existsSync(images)) { return []; }
  return fsNode.readdirSync(images).filter(name => name.endsWith('.img'));
}

// ---- case runner -----------------------------------------------------------

let count = 0;
let finished = false;
const WATCHDOG_MS = 3000;

async function test(name, body) {
  let timer = undefined;
  const watchdog = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error(`watchdog: case "${name}" exceeded ${WATCHDOG_MS}ms`)), WATCHDOG_MS);
  });
  try {
    await Promise.race([body(), watchdog]);
  } finally {
    clearTimeout(timer);
  }
  count++;
  fsNode.appendFileSync(log, `[PASS] ${name}\n`);
}

process.on('beforeExit', () => {
  if (finished) {
    return;
  }
  console.error(`FAIL cache_settings_cases: exited without the final PASS marker (${count} cases completed)`);
  process.exitCode = 1;
});

(async () => {
  await test('default limit is 1 GiB and is applied to the shared store', async () => {
    const area = workspace('default');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    assert.equal(sandbox.CacheSettings.DEFAULT_LIMIT_BYTES, GIB);
    assert.equal(sandbox.CacheSettings.limitBytes(), GIB);
    assert.equal(state.writes.length, 0, 'reading the default must not write a preference');
    const store = sandbox.CacheManager.imageStore();
    assert.equal(store.maxBytes(), GIB, 'the live cache really is capped at 1 GiB');
    assert.equal(store.directoryPath, path.join(area.cacheDir, 'images'));
  });

  await test('a chosen limit is persisted and re-read by a fresh process', async () => {
    const area = workspace('persist');
    const state = preferenceState();
    const first = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const accepted = await first.CacheManager.setLimit(2 * GIB);
    assert.equal(accepted, 2 * GIB);
    assert.deepEqual(state.writes.map(entry => entry.value), [2 * GIB]);
    assert.equal(first.CacheManager.imageStore().maxBytes(), 2 * GIB, 'limit applied to the live store');
    const second = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    assert.equal(second.CacheSettings.limitBytes(), 2 * GIB);
    assert.equal(second.CacheManager.imageStore().maxBytes(), 2 * GIB, 'restart keeps the chosen cap');
  });

  await test('invalid, negative, non-finite and out-of-range limits are rejected', async () => {
    const area = workspace('reject');
    const state = preferenceState({ cacheMaxBytes: 512 * 1024 * 1024 });
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const rejected = [-1, 0, -GIB, Number.NaN, Number.POSITIVE_INFINITY, 1e18, 1024, 1.5];
    for (const value of rejected) {
      await assert.rejects(sandbox.CacheSettings.setLimitBytes(value), /缓存上限无效/,
        `expected rejection for ${value}`);
    }
    assert.equal(state.writes.length, 0, 'rejected values are never persisted');
    assert.equal(state.values.get('cacheMaxBytes'), 512 * 1024 * 1024, 'stored limit unchanged');
    assert.equal(sandbox.CacheSettings.limitBytes(), 512 * 1024 * 1024);
  });

  await test('an invalid stored preference falls back to the 1 GiB default', async () => {
    for (const stored of [-5, 0, Number.NaN, 1e18, 'huge']) {
      const area = workspace('fallback');
      const state = preferenceState({ cacheMaxBytes: stored });
      const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
      assert.equal(sandbox.CacheSettings.limitBytes(), GIB, `stored ${String(stored)} must fall back`);
      assert.equal(sandbox.CacheManager.imageStore().maxBytes(), GIB);
    }
  });

  await test('an uninitialized preference store still yields the default cap', async () => {
    const area = workspace('uninitialized');
    const state = preferenceState();
    state.mode = 'uninitialized';
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    assert.equal(sandbox.CacheSettings.limitBytes(), GIB, 'image loading must not depend on Settings.init()');
    assert.equal(sandbox.CacheManager.imageStore().maxBytes(), GIB);
  });

  await test('selectable options cover 256 MB .. 4 GB and include the default', async () => {
    const area = workspace('options');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const options = Array.from(sandbox.CacheSettings.options())
      .map(option => ({ label: option.label, bytes: option.bytes }));
    assert.deepEqual(options, [
      { label: '256 MB', bytes: 256 * 1024 * 1024 },
      { label: '512 MB', bytes: 512 * 1024 * 1024 },
      { label: '1 GB', bytes: GIB },
      { label: '2 GB', bytes: 2 * GIB },
      { label: '4 GB', bytes: 4 * GIB }
    ]);
    assert.ok(options.some(option => option.bytes === sandbox.CacheSettings.DEFAULT_LIMIT_BYTES));
    for (const option of options) {
      assert.equal(sandbox.CacheSettings.isValidLimit(option.bytes), true, `${option.label} must be selectable`);
    }
    assert.equal(sandbox.CacheSettings.label(Math.round(1.5 * GIB)), '1.5 GB');
    assert.equal(sandbox.CacheSettings.label(0), '0 MB');
  });

  await test('cache statistics reflect stored payloads and reset after clear', async () => {
    const area = workspace('stats');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const store = sandbox.CacheManager.imageStore();
    store.put('cover-1', bytesOf(100, 1));
    store.put('cover-2', bytesOf(60, 2));
    const stats = store.stats();
    assert.equal(stats.bytes, 160);
    assert.equal(stats.entries, 2);
    assert.equal(stats.maxBytes, GIB);
    const cleared = sandbox.CacheManager.clear();
    assert.equal(cleared.bytes, 0);
    assert.equal(cleared.entries, 0);
    assert.equal(sandbox.CacheManager.stats().bytes, 0);
    assert.deepEqual(cachedFiles(area.cacheDir), []);
  });

  await test('clearing the cache never deletes downloads, history or other files', async () => {
    const area = workspace('clear-isolation');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    // Download and history stores live under filesDir, not the cache directory.
    const downloadPage = path.join(area.filesDir, 'local_comics', '42', 'ch1', '001.jpg');
    fsNode.mkdirSync(path.dirname(downloadPage), { recursive: true });
    fsNode.writeFileSync(downloadPage, Buffer.from([9, 8, 7]));
    const ledger = path.join(area.filesDir, 'downloads.json');
    fsNode.writeFileSync(ledger, '{"tasks":[]}');
    const history = path.join(area.filesDir, 'venera.db');
    fsNode.writeFileSync(history, 'history-bytes');
    const store = sandbox.CacheManager.imageStore();
    store.put('cover', bytesOf(128, 3));
    sandbox.CacheManager.payloads().putDetails('src', '42', '{"title":"x"}');
    assert.equal(store.entryCount(), 2);
    const before = sandbox.CacheManager.stats();
    assert.ok(before.bytes > 0);

    sandbox.CacheManager.clear();

    assert.deepEqual(cachedFiles(area.cacheDir), [], 'cache payloads gone');
    assert.equal(fsNode.existsSync(downloadPage), true, 'downloaded page survives');
    assert.deepEqual(Array.from(fsNode.readFileSync(downloadPage)), [9, 8, 7]);
    assert.equal(fsNode.readFileSync(ledger, 'utf8'), '{"tasks":[]}', 'download ledger survives');
    assert.equal(fsNode.readFileSync(history, 'utf8'), 'history-bytes', 'reading history survives');
    assert.equal(sandbox.CacheManager.payloads().getDetails('src', '42'), undefined);
    assert.equal(sandbox.CacheManager.stats().bytes, 0);
  });

  await test('payload helpers share the same capped store and survive a restart', async () => {
    const area = workspace('payload');
    const state = preferenceState();
    const first = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    first.CacheManager.payloads().putDetails('src', 'comic-1', '{"title":"缓存详情"}');
    first.CacheManager.payloads().putPages('src', 'comic-1', 'ch-1', '["p1","p2"]');
    first.CacheManager.imageStore().flush();
    const second = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    assert.equal(second.CacheManager.payloads().getDetails('src', 'comic-1'), '{"title":"缓存详情"}');
    assert.equal(second.CacheManager.payloads().getPages('src', 'comic-1', 'ch-1'), '["p1","p2"]');
    assert.ok(second.CacheManager.stats().entries >= 2);
  });

  await test('a lowered cap evicts through the manager and keeps the newest payload', async () => {
    const area = workspace('evict');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const store = sandbox.CacheManager.imageStore();
    store.put('old', bytesOf(40, 1));
    store.put('older', bytesOf(40, 2));
    store.put('newest', bytesOf(40, 3));
    // The page-level minimum is 256 MB, so exercise the mechanism with a small
    // cap on the same instance: exactly what setLimit does after persisting.
    const evicted = store.setMaxBytes(50);
    assert.equal(evicted, 2);
    assert.equal(store.entryCount(), 1);
    assert.equal(store.has('newest'), true);
    assert.equal(store.has('old'), false);
    assert.equal(sandbox.CacheManager.stats().bytes, 40);
    // Restoring a valid page-level cap keeps working and is persisted.
    await sandbox.CacheManager.setLimit(512 * 1024 * 1024);
    assert.equal(sandbox.CacheManager.imageStore().maxBytes(), 512 * 1024 * 1024);
    assert.equal(state.values.get('cacheMaxBytes'), 512 * 1024 * 1024);
  });

  await test('the same directory always yields one shared store instance', async () => {
    const area = workspace('shared');
    const state = preferenceState();
    const sandbox = settingsSandbox({ state: state, filesDir: area.filesDir, cacheDir: area.cacheDir });
    const first = sandbox.CacheManager.imageStore();
    const second = sandbox.CacheManager.imageStore();
    assert.strictEqual(first, second);
    first.put('a', bytesOf(16, 4));
    assert.equal(second.entryCount(), 1, 'one accounting instance, not two');
    assert.equal(sandbox.context.CacheStore.shared(path.join(area.cacheDir, 'images'), '.img').entryCount(), 1,
      'CacheStore.shared returns the same instance for the same directory');
  });

  console.log(`PASS ${count} cache settings / manager cases ` +
    '(fake preferences, real temp filesystem; not device proof).');
  finished = true;
  for (const dir of tempDirs) {
    try { fsNode.rmSync(dir, { recursive: true, force: true }); } catch (error) { /* best effort */ }
  }
})().catch(error => {
  fsNode.appendFileSync(log, `${error.stack}\n`);
  console.error(error);
  process.exitCode = 1;
});
