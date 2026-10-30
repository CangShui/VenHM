'use strict';
// Current privacy contract. Historical docs/tests are evidence, not runtime features.
// Executes production migration against a fake Harmony RdbStore backed by in-memory SQLite;
// this is not an SDK build or device relationalStore acceptance.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const runtime = path.join(root, 'entry/src/main');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const databasePath = 'entry/src/main/ets/storage/Database.ets';
const databaseRaw = read(databasePath);
const source = databaseRaw.replace(/^import\b.*;\r?\n/gm, '').replace(/\bexport /g, '');
const context = vm.createContext({ Log: { info() {}, audit() {} } });
vm.runInContext(stripTypeScriptTypes(source, { mode: 'transform' }) + '\nglobalThis.DB = Database;', context);
const retired = ['reader_stats_legacy', 'reader_stats_segments', 'reader_stats_pages', 'reader_stats_meta', 'picture_favorites'];
const retiredFiles = [
  'storage/ReadingStatsDao.ets', 'features/ReadingStats.ets', 'pages/StatisticsPage.ets',
  'features/DataSync.ets', 'pages/SyncPage.ets', 'features/PictureFavorites.ets',
  'storage/PictureFavoritesDao.ets', 'pages/PictureFavoritesPage.ets'
];
const initRaw = read('entry/src/main/ets/foundation/AppInit.ets');
function fakeCleanup({ root = '/sandbox/files', rootKind = 'directory', directoryKind = 'directory', absent = false, failUnlink = false } = {}) {
  const directory = `${root}/picture_favorites`, calls = [], removed = [];
  const first = `${'a'.repeat(32)}.image`, second = `${'b'.repeat(32)}.image`;
  const link = `${'c'.repeat(32)}.image`, nested = `${'d'.repeat(32)}.image`;
  const names = [first, second, link, nested, 'notes.txt', `${'A'.repeat(32)}.image`, '../escape.image', 'nested/file.image'];
  const entries = new Map([[root, rootKind],
    [`${root}/local_comics/${first}`, 'file'], [`${root}/downloads.json`, 'file'],
    [`${root}/picture_favorites_backup/${first}`, 'file']]);
  if (!absent) {
    entries.set(directory, directoryKind);
    for (const name of names) entries.set(`${directory}/${name}`, name === link ? 'link' : name === nested ? 'directory' : 'file');
  }
  const stat = target => {
    assert.notEqual(entries.get(target), 'link', 'stat must never follow a symbolic link');
    return { isFile: () => entries.get(target) === 'file', isDirectory: () => entries.get(target) === 'directory' };
  };
  const filesystem = {
    accessSync(target) { calls.push(['access', target]); return entries.has(target); },
    lstatSync(target) { calls.push(['lstat', target]); return { isSymbolicLink: () => entries.get(target) === 'link' }; },
    statSync(target) { calls.push(['stat', target]); return stat(target); },
    listFileSync(target) { calls.push(['list', target]); assert.equal(target, directory); return names.filter(name => entries.has(`${directory}/${name}`)); },
    unlinkSync(target) {
      calls.push(['unlink', target]);
      assert.match(target.slice(directory.length + 1), /^[a-f0-9]{32}\.image$/);
      assert.equal(target, `${directory}/${target.split('/').at(-1)}`);
      assert.equal(entries.get(target), 'file');
      if (failUnlink) throw Error('injected unlink failure');
      entries.delete(target); removed.push(target);
    }
  };
  const ctx = vm.createContext({ fs: filesystem, AppContext: { filesDir: root }, Log: { warn() {} } });
  vm.runInContext(stripTypeScriptTypes(initRaw.replace(/^import\b.*;\r?\n/gm, '').replace(/\bexport /g, ''), { mode: 'transform' }) + '\nglobalThis.Init = AppInit;', ctx);
  return { run: () => ctx.Init.removeRetiredPictureCopies(), entries, calls, removed, directory, first, second };
}
let count = 0;
async function test(name, fn) { await fn(); count++; console.log(`PASS ${name}`); }
function filesIn(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? filesIn(file) : [file];
  });
}
function fakeRdb({ old = true, noDropColumn = false, failQuery = false, failErase = false } = {}) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(`CREATE TABLE history (id TEXT NOT NULL, type INTEGER NOT NULL, source_key TEXT NOT NULL DEFAULT '',
    ep_id TEXT, title TEXT NOT NULL DEFAULT '', subtitle TEXT NOT NULL DEFAULT '', cover TEXT NOT NULL DEFAULT '',
    time INTEGER NOT NULL, ep INTEGER NOT NULL DEFAULT 1, page INTEGER NOT NULL DEFAULT 1,
    read_episode TEXT NOT NULL DEFAULT '', max_page INTEGER, chapter_group INTEGER,
    ${old ? 'read_duration_ms INTEGER NOT NULL DEFAULT 0,' : ''} PRIMARY KEY(id,type));
    INSERT INTO history (id,type,source_key,ep_id,title,time,ep,page,read_episode,max_page,chapter_group)
      VALUES ('resume',9,'local','stable-chapter','saved title',123456,2,7,'1,2',20,3),
      ('legacy',4,'',NULL,'legacy title',100,4,8,'',NULL,NULL),
      ('implicit',8,'source-empty','','implicit chapter',120,1,3,'',3,NULL);`);
  if (old) sqlite.exec('UPDATE history SET read_duration_ms = 98765');
  // Includes lookalikes/unknown future tables: prefixes are NOT ownership evidence.
  const protectedTables = ['favorites', 'favorite_folders', 'sources', 'source_data', 'cookies',
    'local_comics', 'downloads', 'download_queue', 'reader_stats_custom', 'picture_favorites_user_backup'];
  for (const table of protectedTables) {
    sqlite.exec(`CREATE TABLE ${table} (id TEXT PRIMARY KEY, payload TEXT); INSERT INTO ${table} VALUES ('keep','protected-data')`);
  }
  if (old) for (const table of retired) {
    sqlite.exec(`CREATE TABLE ${table} (payload TEXT); INSERT INTO ${table} VALUES ('retired-only')`);
  }
  const sql = [];
  let closedResults = 0;
  return {
    sqlite, sql, protectedTables,
    get closedResults() { return closedResults; },
    async executeSql(query) {
      sql.push(query);
      if (/^DROP TABLE/i.test(query)) {
        const match = /^DROP TABLE IF EXISTS ([a-z_]+)$/.exec(query);
        assert.ok(match && retired.includes(match[1]), `unowned destructive SQL: ${query}`);
      }
      if (noDropColumn && /^ALTER TABLE history DROP COLUMN/.test(query)) throw Error('old SQLite: DROP COLUMN unsupported');
      if (failErase && /^UPDATE history/.test(query)) throw Error('injected disk failure');
      sqlite.exec(query);
    },
    async querySql(query) {
      if (failQuery) throw Error('injected schema read failure');
      assert.equal(query, 'PRAGMA table_info(history)');
      const rows = sqlite.prepare(query).all();
      let index = -1;
      return { goToNextRow: () => ++index < rows.length, getColumnIndex: name => name,
        getString: key => rows[index][key], close() { closedResults++; } };
    }
  };
}
const history = store => store.sqlite.prepare('SELECT id,type,source_key,ep_id,title,subtitle,cover,time,ep,page,read_episode,max_page,chapter_group FROM history ORDER BY id').all();
const protectedSnapshot = store => store.protectedTables.map(table => ({ table,
  schema: store.sqlite.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(table).sql,
  rows: store.sqlite.prepare(`SELECT * FROM ${table}`).all() }));
const columns = store => store.sqlite.prepare('PRAGMA table_info(history)').all().map(row => row.name);
const tables = store => store.sqlite.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(row => row.name);

(async () => {
  await test('legacy migration drops exactly the five known owned retired tables; preserves all others byte-for-byte', async () => {
    const store = fakeRdb();
    try {
      const before = protectedSnapshot(store), resume = history(store);
      await context.DB.removeRetiredData(store);
      assert.deepEqual(store.sql.filter(sql => sql.startsWith('DROP TABLE')).map(sql => sql.split(' ').at(-1)), retired);
      assert.ok(retired.every(table => !tables(store).includes(table)));
      assert.deepEqual(protectedSnapshot(store), before);
      assert.deepEqual(history(store), resume);
      assert.ok(!columns(store).includes('read_duration_ms'));
      assert.equal(store.closedResults, 1);
    } finally { store.sqlite.close(); }
  });
  await test('old SQLite erases every duration while preserving history schema, positions and unrelated data', async () => {
    const store = fakeRdb({ noDropColumn: true });
    try {
      const before = protectedSnapshot(store), resume = history(store), schema = columns(store);
      await context.DB.removeRetiredData(store);
      assert.deepEqual(columns(store), schema);
      assert.deepEqual(history(store), resume);
      assert.deepEqual(protectedSnapshot(store), before);
      assert.equal(store.sqlite.prepare('SELECT SUM(read_duration_ms) AS total FROM history').get().total, 0);
      assert.ok(store.sql.includes('UPDATE history SET read_duration_ms = 0'));
      assert.ok(!store.sql.some(sql => /DROP TABLE.*history|DELETE FROM history|CREATE.*history|RENAME/i.test(sql)));
    } finally { store.sqlite.close(); }
  });
  await test('migration is idempotent with modern SQLite and with legacy empty-column fallback', async () => {
    for (const noDropColumn of [false, true]) {
      const store = fakeRdb({ noDropColumn });
      try {
        await context.DB.removeRetiredData(store);
        const before = history(store), protectedBefore = protectedSnapshot(store);
        await context.DB.removeRetiredData(store);
        assert.deepEqual(history(store), before);
        assert.deepEqual(protectedSnapshot(store), protectedBefore);
        assert.equal(store.closedResults, 2);
      } finally { store.sqlite.close(); }
    }
  });
  await test('fresh/current schema never adds or writes a duration column', async () => {
    const store = fakeRdb({ old: false });
    try {
      const before = history(store);
      await context.DB.removeRetiredData(store);
      assert.deepEqual(history(store), before);
      assert.ok(!columns(store).includes('read_duration_ms'));
      assert.ok(store.sql.every(sql => !/ALTER|UPDATE|INSERT|CREATE/i.test(sql)));
      const createTables = databaseRaw.slice(databaseRaw.indexOf('private static async createTables'), databaseRaw.indexOf('static async removeRetiredData'));
      assert.doesNotMatch(createTables, /read_duration_ms|reader_stats_|picture_favorites/);
    } finally { store.sqlite.close(); }
  });
  await test('schema/erasure failures propagate rather than resetting history or publishing a ready database', async () => {
    for (const options of [{ failQuery: true }, { noDropColumn: true, failErase: true }]) {
      const store = fakeRdb(options);
      try {
        const before = history(store);
        await assert.rejects(context.DB.removeRetiredData(store));
        assert.deepEqual(history(store), before);
        assert.equal(store.sqlite.prepare('SELECT SUM(read_duration_ms) AS total FROM history').get().total, 296295);
      } finally { store.sqlite.close(); }
    }
    assert.ok(databaseRaw.indexOf('await Database.removeRetiredData(store)') < databaseRaw.indexOf('Database.store = store'));
  });
  await test('startup removes only the known persisted backup endpoint, not settings/accounts/cookies', async () => {
    const init = read('entry/src/main/ets/foundation/AppInit.ets');
    assert.match(init, /await Settings\.remove\('webdavEndpoint'\)/);
    assert.ok(init.indexOf('await Settings.init()') < init.indexOf("await Settings.remove('webdavEndpoint')"));
    assert.deepEqual([...init.matchAll(/Settings\.remove\('([^']+)'\)/g)].map(match => match[1]), ['webdavEndpoint']);
    assert.ok(init.indexOf('await Database.init()') < init.indexOf('await CookieJar.init()'));
  });
  await test('legacy copy cleanup removes only direct ordinary UUID-format files in the exact private directory', async () => {
    const fixture = fakeCleanup();
    const before = new Map(fixture.entries);
    fixture.run();
    const expected = [`${fixture.directory}/${fixture.first}`, `${fixture.directory}/${fixture.second}`];
    assert.deepEqual(fixture.removed, expected);
    for (const [file, kind] of before) if (!expected.includes(file)) assert.equal(fixture.entries.get(file), kind, file);
    assert.ok(!fixture.calls.some(([operation]) => operation === 'rmdir'));
    fixture.run();
    assert.deepEqual(fixture.removed, expected, 'second cleanup must be idempotent');
    assert.ok(initRaw.indexOf('AppInit.removeRetiredPictureCopies();') < initRaw.indexOf('await Database.init()'));
  });
  await test('cleanup rejects malformed roots and never follows root/directory/file links or recurses', async () => {
    for (const root of ['relative', '/sandbox/../files', '/sandbox/./files', '/sandbox//files', '/sandbox/files/', 'C:\\files']) {
      const fixture = fakeCleanup({ root }); fixture.run();
      assert.equal(fixture.calls.length, 0, root);
    }
    for (const options of [{ rootKind: 'link' }, { rootKind: 'file' }, { directoryKind: 'link' }, { directoryKind: 'file' }, { absent: true }]) {
      const fixture = fakeCleanup(options), before = new Map(fixture.entries); fixture.run();
      assert.deepEqual(fixture.entries, before);
      assert.equal(fixture.removed.length, 0);
    }
  });
  await test('cleanup I/O failure propagates before metadata retirement, allowing startup retry', async () => {
    const fixture = fakeCleanup({ failUnlink: true }), before = new Map(fixture.entries);
    assert.throws(fixture.run, /injected unlink failure/);
    assert.deepEqual(fixture.entries, before);
    const runBody = initRaw.slice(initRaw.indexOf('private static async run()'), initRaw.indexOf('static removeRetiredPictureCopies()'));
    assert.match(runBody, /AppInit\.removeRetiredPictureCopies\(\);\s+await Database\.init\(\)/);
  });
  await test('retired module files/classes/imports/actions and routes are gone across the current runtime', async () => {
    for (const file of retiredFiles) assert.ok(!fs.existsSync(path.join(runtime, 'ets', file)), file);
    const routes = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src;
    for (const page of ['StatisticsPage', 'SyncPage', 'PictureFavoritesPage']) assert.ok(!routes.includes(`pages/${page}`));
    for (const file of filesIn(path.join(runtime, 'ets')).filter(file => file.endsWith('.ets'))) {
      const text = fs.readFileSync(file, 'utf8'), relative = path.relative(root, file);
      assert.doesNotMatch(text, /\b(?:ReadingStats\w*|ReadingDaySegment|ReadingClock|DataSync|SyncSnapshot|SyncTable|PictureFavorites\w*|PictureFavorite|StatisticsPage|SyncPage)\b|阅读统计|图片收藏|WebDAV|TransferUsability\.sync\(/, relative);
      assert.doesNotMatch(text, /readDurationMs|statsSession|statsSequence/, relative);
      if (relative.replaceAll('\\', '/') !== databasePath) {
        assert.doesNotMatch(text, /read_duration_ms|reader_stats_/, relative);
        // One exact legacy path in startup is cleanup, not a surviving module.
        if (relative.endsWith('AppInit.ets')) assert.equal((text.match(/picture_favorites/g) || []).length, 1);
        else assert.doesNotMatch(text, /picture_favorites/, relative);
      }
      if (!relative.endsWith('AppInit.ets')) assert.doesNotMatch(text, /webdavEndpoint|webdavPassword|webdavUsername/, relative);
    }
  });
  await test('ordinary local/network favorites, history, downloads and image viewer remain registered', async () => {
    const routes = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src;
    for (const route of ['pages/NetworkFavoritesPage', 'pages/HistoryPage', 'pages/DownloadsPage', 'pages/ImageViewerPage', 'pages/ReaderPage']) assert.ok(routes.includes(route), route);
    for (const file of ['storage/FavoritesDao.ets', 'storage/HistoryDao.ets', 'features/DownloadQueue.ets', 'source/LocalSource.ets']) assert.ok(fs.existsSync(path.join(runtime, 'ets', file)), file);
    assert.match(read('entry/src/main/ets/features/SettingsView.ets'), /pages\/NetworkFavoritesPage/);
  });
  console.log(`PASS ${count} retirement/privacy cases (production migration, fake RdbStore + in-memory SQLite; no device claims).`);
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
