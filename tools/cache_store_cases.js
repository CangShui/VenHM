'use strict';
/**
 * CacheStore / PayloadCache / ImageLoader disk-cache cases.
 *
 * Runs the real .ets sources (types stripped) against a REAL temp directory, so
 * file naming, atomic index replacement, restart recovery and LRU eviction are
 * exercised for real. Transport, image decoding and the app sandbox are fakes;
 * nothing here touches a device, an account or a real site.
 *
 * Self-contained on purpose: it must not depend on tools/cache_fakes.js, so a
 * change to another suite's shared fakes can never make this evidence vanish.
 */
const fsNode = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { stripTypeScriptTypes } = require('node:module');

const root = path.resolve(__dirname, '..');
const log = path.join(root, 'logs/cache-store-cases.log');
fsNode.mkdirSync(path.dirname(log), { recursive: true });
fsNode.writeFileSync(log, 'CacheStore/PayloadCache/ImageLoader disk cache; real temp filesystem, fake transport, no device.\n');

const read = p => fsNode.readFileSync(path.join(root, p), 'utf8')
  .replace(/^import .*;\r?\n/gm, '')
  .replace(/\bexport /g, '');

// ---- harness ---------------------------------------------------------------

const tempDirs = [];
function tempDir(label) {
  const dir = fsNode.mkdtempSync(path.join(os.tmpdir(), `venera-cache-${label}-`));
  tempDirs.push(dir);
  return dir;
}

function bytesOf(values) {
  return Uint8Array.from(values).buffer;
}

/** fileIo facade backed by the real filesystem (same paths the app uses). */
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

function logFake(sink) {
  return {
    audit: (trace, stage, message) => { if (sink !== undefined) { sink.push(`${stage}: ${message}`); } },
    info: () => {},
    warn: (tag, message) => { if (sink !== undefined) { sink.push(`WARN ${tag}: ${message}`); } },
    error: () => {}
  };
}

/** One "process": its own module instances and in-memory state, shared disk. */
function cacheSandbox(directory, maxBytes, warnings) {
  const context = vm.createContext({
    fs: fakeFs(),
    util: utilFake(),
    Log: logFake(warnings),
    ArrayBuffer,
    Uint8Array
  });
  vm.runInContext(stripTypeScriptTypes(
    read('entry/src/main/ets/foundation/CacheStore.ets'), { mode: 'transform' }) +
    '\nglobalThis.CacheStore=CacheStore;globalThis.PayloadCache=PayloadCache;globalThis.CacheStats=CacheStats;',
  context);
  const store = new context.CacheStore(directory, '.img', maxBytes);
  return { context, store, PayloadCache: context.PayloadCache };
}

/**
 * One app launch of ImageLoader with its own memory caches, pointed at the same
 * directory. `counter` is shared across launches: it counts real HTTP work.
 */
function imageSandbox(directory, counter, maxBytes) {
  const context = vm.createContext({
    fs: fakeFs(),
    util: utilFake(),
    Log: logFake(),
    ArrayBuffer,
    Uint8Array,
    CookieJar: { header: () => '' },
    cryptoFramework: {
      createMd: algorithm => {
        if (algorithm !== 'SHA256') { throw new Error(`unexpected digest ${algorithm}`); }
        let data = undefined;
        return {
          updateSync: value => { data = value.data; },
          digestSync: () => ({ data: crypto.createHash('sha256').update(Buffer.from(data)).digest() })
        };
      }
    },
    HttpClient: {
      getBytes: async () => {
        counter.fetches++;
        return { ok: true, status: 200, bytes: Uint8Array.from([1, 2, 3, counter.fetches]).buffer };
      }
    },
    ImageTransforms: { apply: async incoming => incoming },
    image: {
      createImageSource: source => ({
        createPixelMap: async () => {
          const raw = source instanceof ArrayBuffer ? source : undefined;
          if (raw === undefined || raw.byteLength === 0 || new Uint8Array(raw)[0] === 0) {
            throw new Error('invalid image bytes');
          }
          counter.decodes++;
          return { bytes: raw, release: async () => {} };
        },
        release: async () => {}
      })
    },
    ImagePipeline: { fetch: async () => bytesOf([1, 2, 3]) }
  });
  const script = read('entry/src/main/ets/network/ImageCacheKey.ets') + '\n' +
    read('entry/src/main/ets/foundation/CacheStore.ets') + '\n' +
    read('entry/src/main/ets/network/ImageLoader.ets');
  vm.runInContext(stripTypeScriptTypes(script, { mode: 'transform' }) +
    '\nglobalThis.ImageLoader=ImageLoader;globalThis.CacheStore=CacheStore;globalThis.imageCacheKey=imageCacheKey;' +
    `globalThis.__store=new CacheStore(${JSON.stringify(directory)}, ".img", ${maxBytes});` +
    'globalThis.CacheManager={imageStore:()=>globalThis.__store};',
  context);
  return { context, Loader: context.ImageLoader, store: context.__store };
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
  console.error(`FAIL cache_store_cases: exited without the final PASS marker (${count} cases completed)`);
  process.exitCode = 1;
});

(async () => {
  await test('put/get round trip keeps bytes, size and entry count', async () => {
    const dir = tempDir('roundtrip');
    const sandbox = cacheSandbox(dir, 1024 * 1024);
    sandbox.store.put('alpha', bytesOf([1, 2, 3, 4]));
    assert.equal(sandbox.store.size(), 4);
    assert.equal(sandbox.store.entryCount(), 1);
    assert.equal(sandbox.store.has('alpha'), true);
    assert.equal(sandbox.store.has('absent'), false);
    assert.equal(sandbox.store.get('absent'), undefined);
    const readBack = sandbox.store.get('alpha');
    assert.ok(readBack !== undefined);
    assert.deepEqual(Array.from(new Uint8Array(readBack)), [1, 2, 3, 4]);
    sandbox.store.flush();
    assert.ok(fsNode.existsSync(path.join(dir, '.cache-index.json')), 'index written by flush()');
    assert.deepEqual(fsNode.readdirSync(dir).filter(name => name.endsWith('.img')), ['alpha.img'],
      'filename-safe key maps to <key>.img, keeping pre-upgrade cover files readable');
  });

  await test('put over the cap evicts least-recently-used entries until it fits', async () => {
    const sandbox = cacheSandbox(tempDir('evict-put'), 10);
    sandbox.store.put('a', bytesOf([1, 1, 1, 1]));
    sandbox.store.put('b', bytesOf([2, 2, 2]));
    sandbox.store.put('c', bytesOf([3, 3]));
    assert.equal(sandbox.store.size(), 9);
    assert.equal(sandbox.store.evictIfNeeded(), 0, 'under the cap: nothing to do');
    sandbox.store.put('d', bytesOf([4, 4, 4]));
    assert.equal(sandbox.store.has('a'), false, 'oldest entry evicted first');
    assert.equal(sandbox.store.has('b'), true);
    assert.equal(sandbox.store.has('c'), true);
    assert.equal(sandbox.store.has('d'), true);
    assert.equal(sandbox.store.size(), 8);
    assert.equal(sandbox.store.evictions(), 1);
  });

  await test('touch makes an entry most-recently-used without rewriting it', async () => {
    const sandbox = cacheSandbox(tempDir('touch'), 10);
    sandbox.store.put('a', bytesOf([1, 1, 1, 1]));
    sandbox.store.put('b', bytesOf([2, 2, 2, 2]));
    sandbox.store.touch('a');
    assert.deepEqual(Array.from(sandbox.store.keysByRecency()), ['b', 'a']);
    sandbox.store.put('c', bytesOf([3, 3, 3, 3]));
    assert.equal(sandbox.store.has('b'), false, 'the touched entry survives, the untouched one goes');
    assert.equal(sandbox.store.has('a'), true);
  });

  await test('byte accounting and LRU order survive a restart via the index', async () => {
    const dir = tempDir('restart');
    const first = cacheSandbox(dir, 1024 * 1024);
    first.store.put('a', bytesOf([1, 1, 1, 1]));
    first.store.put('b', bytesOf([2, 2, 2, 2, 2, 2]));
    first.store.touch('a');
    first.store.flush();
    const second = cacheSandbox(dir, 1024 * 1024);
    assert.equal(second.store.size(), 10);
    assert.equal(second.store.entryCount(), 2);
    assert.deepEqual(Array.from(second.store.keysByRecency()), ['b', 'a'],
      'recency persisted in the index, not guessed from mtime');
    const payload = second.store.get('b');
    assert.ok(payload !== undefined);
    assert.deepEqual(Array.from(new Uint8Array(payload)), [2, 2, 2, 2, 2, 2]);
  });

  await test('missing index is rebuilt from the directory listing', async () => {
    const dir = tempDir('no-index');
    const first = cacheSandbox(dir, 1024 * 1024);
    first.store.put('a', bytesOf([1, 1, 1]));
    first.store.put('b', bytesOf([2, 2]));
    first.store.flush();
    fsNode.unlinkSync(path.join(dir, '.cache-index.json'));
    const second = cacheSandbox(dir, 1024 * 1024);
    assert.equal(second.store.entryCount(), 2);
    assert.equal(second.store.size(), 5);
    assert.ok(second.store.get('a') !== undefined);
  });

  await test('corrupt index is ignored and rebuilt; stale entries never over-report bytes', async () => {
    const dir = tempDir('corrupt-index');
    const first = cacheSandbox(dir, 1024 * 1024);
    first.store.put('a', bytesOf([1, 1, 1, 1]));
    first.store.put('b', bytesOf([2, 2, 2]));
    first.store.flush();
    const indexPath = path.join(dir, '.cache-index.json');
    fsNode.writeFileSync(indexPath, '{"v":1,"seq":9,"entries":[{"k":"a"');
    const second = cacheSandbox(dir, 1024 * 1024);
    assert.equal(second.store.size(), 7, 'rebuilt from files despite the truncated index');
    assert.equal(second.store.entryCount(), 2);
    // A file removed behind the store's back must not stay accounted.
    fsNode.unlinkSync(path.join(dir, 'a.img'));
    const third = cacheSandbox(dir, 1024 * 1024);
    assert.equal(third.store.size(), 3);
    assert.equal(third.store.entryCount(), 1);
    assert.equal(third.store.has('a'), false);
  });

  await test('a single entry larger than the whole cap is refused, nothing else is evicted', async () => {
    const sandbox = cacheSandbox(tempDir('oversize'), 8);
    sandbox.store.put('keep', bytesOf([1, 1, 1, 1]));
    assert.throws(() => sandbox.store.put('huge', bytesOf([9, 9, 9, 9, 9, 9, 9, 9, 9])), /超过上限/);
    assert.equal(sandbox.store.has('keep'), true, 'the refusal must not clear existing cache');
    assert.equal(sandbox.store.size(), 4);
    assert.equal(sandbox.store.entryCount(), 1);
    assert.equal(sandbox.store.has('huge'), false);
  });

  await test('lowering the cap evicts LRU entries immediately', async () => {
    const sandbox = cacheSandbox(tempDir('shrink'), 100);
    sandbox.store.put('a', bytesOf(new Array(30).fill(1)));
    sandbox.store.put('b', bytesOf(new Array(30).fill(2)));
    sandbox.store.put('c', bytesOf(new Array(30).fill(3)));
    assert.equal(sandbox.store.size(), 90);
    const evicted = sandbox.store.setMaxBytes(40);
    assert.equal(evicted, 2);
    assert.equal(sandbox.store.size(), 30);
    assert.equal(sandbox.store.has('c'), true, 'newest entry kept');
    assert.equal(sandbox.store.has('a'), false);
    assert.equal(sandbox.store.maxBytes(), 40);
  });

  await test('clear removes only cache payloads, resets accounting and keeps foreign files', async () => {
    const dir = tempDir('clear');
    const sandbox = cacheSandbox(dir, 1024 * 1024);
    sandbox.store.put('a', bytesOf([1, 1]));
    sandbox.store.put('b', bytesOf([2, 2, 2]));
    sandbox.store.flush();
    const foreign = path.join(dir, 'downloads.json');
    fsNode.writeFileSync(foreign, '{"keep":true}');
    const removed = sandbox.store.clear();
    assert.equal(removed, 2);
    assert.equal(sandbox.store.size(), 0);
    assert.equal(sandbox.store.entryCount(), 0);
    assert.deepEqual(fsNode.readdirSync(dir).filter(name => name.endsWith('.img')), []);
    assert.equal(fsNode.readFileSync(foreign, 'utf8'), '{"keep":true}', 'unrelated files untouched');
    assert.equal(fsNode.existsSync(path.join(dir, '.cache-index.json')), false);
    const restarted = cacheSandbox(dir, 1024 * 1024);
    assert.equal(restarted.store.size(), 0);
    assert.equal(restarted.store.entryCount(), 0);
    assert.equal(restarted.store.get('a'), undefined);
  });

  await test('a damaged payload is a miss that drops only that entry', async () => {
    const dir = tempDir('damaged');
    const first = cacheSandbox(dir, 1024 * 1024);
    first.store.put('a', bytesOf([1, 1, 1]));
    first.store.put('b', bytesOf([2, 2]));
    first.store.flush();
    fsNode.writeFileSync(path.join(dir, 'a.img'), '');
    const second = cacheSandbox(dir, 1024 * 1024);
    assert.equal(second.store.get('a'), undefined, 'read failure is a miss, never a throw');
    assert.equal(second.store.has('b'), true);
    assert.equal(second.store.size(), 2);
    assert.equal(second.store.entryCount(), 1);
  });

  await test('an unusable cache directory never throws out of get/size/has', async () => {
    const dir = tempDir('unusable');
    const notADirectory = path.join(dir, 'not-a-dir');
    fsNode.writeFileSync(notADirectory, 'x');
    const sandbox = cacheSandbox(notADirectory, 1024);
    assert.equal(sandbox.store.get('a'), undefined);
    assert.equal(sandbox.store.has('a'), false);
    assert.equal(sandbox.store.size(), 0);
    assert.equal(sandbox.store.entryCount(), 0);
    assert.throws(() => sandbox.store.put('a', bytesOf([1])), Error, 'writes report failure to the caller');
  });

  await test('payload cache stores namespaced JSON text and survives a restart', async () => {
    const dir = tempDir('payload');
    const first = cacheSandbox(dir, 1024 * 1024);
    const details = JSON.stringify({ title: '漫画', tags: { author: ['某人'] }, chapters: [] });
    const pages = JSON.stringify(['https://fixture.invalid/1.jpg', 'https://fixture.invalid/2.jpg']);
    const writer = new first.PayloadCache(first.store);
    writer.putDetails('src/with:colon', 'comic/42', details);
    writer.putPages('src/with:colon', 'comic/42', 'ch 1', pages);
    first.store.flush();
    const names = fsNode.readdirSync(dir).filter(name => name.endsWith('.img'));
    assert.equal(names.length, 2);
    assert.ok(names.every(name => name.startsWith('x')), 'unsafe keys are hex-encoded into safe filenames');
    const second = cacheSandbox(dir, 1024 * 1024);
    const reader = new second.PayloadCache(second.store);
    assert.equal(reader.getDetails('src/with:colon', 'comic/42'), details);
    assert.equal(reader.getPages('src/with:colon', 'comic/42', 'ch 1'), pages);
    assert.equal(reader.getDetails('other-source', 'comic/42'), undefined, 'namespaces never collide');
    assert.equal(reader.getPages('src/with:colon', 'comic/42', 'ch 2'), undefined);
  });

  await test('typed detail/page helpers round-trip raw source JSON across a restart', async () => {
    const dir = tempDir('typed-payload');
    const rawDetails = { title: 'raw', cover: 'https://fixture.invalid/c.jpg', tags: { author: ['a'] } };
    const images = ['https://fixture.invalid/p1.jpg', 'https://fixture.invalid/p2.jpg'];
    const first = cacheSandbox(dir, 1024 * 1024);
    const writer = new first.PayloadCache(first.store);
    writer.rememberDetail('src', 'c1', rawDetails);
    writer.rememberPageList('src', 'c1', 'ch1', images);
    writer.rememberPageList('src', 'c1', 'empty', []);
    first.store.flush();
    const second = cacheSandbox(dir, 1024 * 1024);
    const reader = new second.PayloadCache(second.store);
    assert.deepEqual(JSON.parse(JSON.stringify(reader.detailPayload('src', 'c1'))), rawDetails);
    assert.deepEqual(Array.from(reader.pageList('src', 'c1', 'ch1')), images);
    assert.equal(reader.pageList('src', 'c1', 'empty'), undefined, 'an empty page list is never cached');
    assert.equal(reader.detailPayload('src', 'c2'), undefined);
    // A malformed payload must read as a miss and be dropped, not throw.
    writer.putDetails('src', 'broken', '{not json');
    assert.equal(reader.detailPayload('src', 'broken'), undefined);
  });

  await test('two launches: the continue-reading cover comes from disk with zero fetches', async () => {
    const dir = tempDir('cover-restart');
    const counter = { fetches: 0, decodes: 0 };
    const launchOne = imageSandbox(dir, counter, 1024 * 1024);
    await launchOne.Loader.load('https://fixture.invalid/cover.jpg');
    assert.equal(counter.fetches, 1, 'launch 1 downloads the cover once');
    launchOne.store.flush();
    assert.ok(fsNode.readdirSync(dir).some(name => name.endsWith('.img')), 'cover bytes on disk');

    const launchTwo = imageSandbox(dir, counter, 1024 * 1024);
    const pixel = await launchTwo.Loader.load('https://fixture.invalid/cover.jpg');
    assert.ok(pixel !== undefined);
    assert.equal(counter.fetches, 1, 'launch 2 performs ZERO fetches: the cover survived the restart');
    assert.equal(counter.decodes, 2, 'launch 2 decodes from disk instead of re-downloading');
    assert.equal(launchTwo.store.size() > 0, true, 'launch 2 accounts the pre-existing file');
  });

  await test('two launches: cached details JSON is not re-requested', async () => {
    const dir = tempDir('details-restart');
    const counter = { requests: 0 };
    const fetchDetails = async () => { counter.requests++; return JSON.stringify({ title: '详情' }); };
    const first = cacheSandbox(dir, 1024 * 1024);
    const firstPayloads = new first.PayloadCache(first.store);
    const fresh = firstPayloads.getDetails('src', '7');
    const launchOne = fresh !== undefined ? fresh : await fetchDetails();
    if (fresh === undefined) { firstPayloads.putDetails('src', '7', launchOne); }
    first.store.flush();
    assert.equal(counter.requests, 1);
    const second = cacheSandbox(dir, 1024 * 1024);
    const secondPayloads = new second.PayloadCache(second.store);
    const cached = secondPayloads.getDetails('src', '7');
    const launchTwo = cached !== undefined ? cached : await fetchDetails();
    assert.equal(counter.requests, 1, 'launch 2 performs ZERO detail requests');
    assert.equal(launchTwo, launchOne);
  });

  await test('an oversized image is still returned when the cache refuses it', async () => {
    const dir = tempDir('image-oversize');
    const counter = { fetches: 0, decodes: 0 };
    const launch = imageSandbox(dir, counter, 2);
    const pixel = await launch.Loader.load('https://fixture.invalid/big.jpg');
    assert.ok(pixel !== undefined, 'cache refusal must not fail the picture');
    assert.equal(counter.fetches, 1);
    assert.equal(launch.store.entryCount(), 0);
    assert.equal(fsNode.readdirSync(dir).filter(name => name.endsWith('.img')).length, 0);
  });

  await test('a corrupt cached image is re-downloaded exactly once and replaced', async () => {
    const dir = tempDir('image-corrupt');
    const counter = { fetches: 0, decodes: 0 };
    const launchOne = imageSandbox(dir, counter, 1024 * 1024);
    await launchOne.Loader.load('https://fixture.invalid/page.jpg');
    launchOne.store.flush();
    const imageFile = fsNode.readdirSync(dir).find(name => name.endsWith('.img'));
    assert.ok(imageFile !== undefined);
    fsNode.writeFileSync(path.join(dir, imageFile), Buffer.alloc(4, 0));
    const launchTwo = imageSandbox(dir, counter, 1024 * 1024);
    await launchTwo.Loader.load('https://fixture.invalid/page.jpg');
    assert.equal(counter.fetches, 2, 'exactly one re-download after the corrupt cache entry');
    const rewritten = fsNode.readFileSync(path.join(dir, imageFile));
    assert.notEqual(rewritten[0], 0, 'the damaged payload was replaced with valid bytes');
  });

  console.log(`PASS ${count} cache store / payload / image-loader disk cache cases ` +
    '(real temp filesystem, fake transport; not device proof).');
  finished = true;
  for (const dir of tempDirs) {
    try { fsNode.rmSync(dir, { recursive: true, force: true }); } catch (error) { /* best effort */ }
  }
})().catch(error => {
  fsNode.appendFileSync(log, `${error.stack}\n`);
  console.error(error);
  process.exitCode = 1;
});
