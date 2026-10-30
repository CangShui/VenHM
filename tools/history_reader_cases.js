'use strict';

/**
 * Source-independent regression checks against the current production ETS bodies.
 * Run: node tools/history_reader_cases.js  (Node >= 22.13; tested on 24.14.1).
 *
 * No application build, installed source rules, network or device is used.
 * Node erases types; this does NOT validate ArkTS static restrictions or ArkUI
 * rendering. Reader @Builder methods are excluded; source/DAO/controllers
 * are deterministic fakes. Real waterfall layout must still be tested on-device.
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');

if (typeof stripTypeScriptTypes !== 'function') {
  throw new Error('Use Node >= 22.13 with node:module.stripTypeScriptTypes.');
}
const root = path.resolve(__dirname, '..');
const auditPath = path.join(root, 'logs/history-reader-cases.log');
fs.mkdirSync(path.dirname(auditPath), {recursive:true});
fs.writeFileSync(auditPath, '[请求到达] TraceID=history-reader-tests production methods and chapter presentation; deterministic fakes\n');
const chapterNavigation = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/ChapterNavigation.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
const helperFile = path.join(root, 'entry/src/main/ets/features/ReadingPosition.ets');
const readerFile = path.join(root, 'entry/src/main/ets/pages/ReaderPage.ets');
const helper = fs.readFileSync(helperFile, 'utf8').replace(/export /g, '');
const modes = fs.readFileSync(
  path.join(root, 'entry/src/main/ets/features/ReaderModes.ets'), 'utf8')
  .replace(/export /g, '');
const spreads = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/ReaderSpreads.ets'), 'utf8').replace(/export /g, '');
const workload = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/ReaderWorkload.ets'), 'utf8').replace(/export /g, '');
const renderSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/ReaderRenderSource.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
const volumeKeys = fs.readFileSync(path.join(root, 'entry/src/main/ets/features/ReaderVolumeKeys.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
const options = fs.readFileSync(path.join(root, 'entry/src/main/ets/foundation/ReaderSettings.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '').split('class ReaderProfile')[0];
const readerSource = fs.readFileSync(readerFile, 'utf8');
const builderOffset = readerSource.indexOf('  @Builder');
assert.ok(builderOffset > 0, 'Expected ReaderPage control-flow methods before @Builder');
const reader = (readerSource.slice(0, builderOffset) + '}')
  .replace(/^import .*;\r?\n/gm, '')
  .replace(/@Entry\s*|@Component\s*|@State\s*/g, '')
  .replace('struct ReaderPage', 'class ReaderPage');

let now = 1000;
let saves = [];
let reads = 0;
let calls = [];
let stored;
let source;
let settingsReady = true;
let modeReads = 0;
let modeWrites = [];
let modePreference = 'waterfallTopToBottom';
let layoutTasks = [];
const details = {
  title: 'Authoritative title',
  cover: 'cover-url',
  findAuthor: () => 'Author',
  chapters: { length: 2, ids: ['a', 'b'], titles: ['A', 'B'],isGrouped:false,allChapters:new Map([['a','A'],['b','B']]) }
};

function reset() {
  now = 1000;
  saves = [];
  reads = 0;
  calls = [];
  stored = undefined;
  settingsReady = true;
  modeReads = 0;
  modeWrites = [];
  modePreference = 'waterfallTopToBottom';
  layoutTasks = [];
  source = {
    key: 'real-key',
    name: 'Fixture',
    loadComicInfo: async () => ({ error: false, dataOrNull: details }),
    loadComicPages: async (id, ep) => {
      calls.push(ep);
      return { error: false, dataOrNull: ['img1', 'img2', 'img3', 'img4'] };
    }
  };
}

class FakeDate extends Date {
  static now() { return now; }
}

const env = {
  Date: FakeDate,
  SwiperController: class { changeIndex(index) { this.target = index; } },
  setTimeout: fn => { layoutTasks.push(fn); return layoutTasks.length; },
  clearTimeout: () => {},
  Scroller: class { scrollToIndex(index) { this.target = index; } },
  History: class {},
  ComicType: { fromKey: () => ({ value: 42 }) },
  HistoryDao: {
    find: async () => { reads++; return stored; },
    // Match the DAO contract: write synchronously, then return a Promise.
    save: (history) => { saves.push({ ...history }); return Promise.resolve(); }
  },
  SourceManager: { find: () => source },
  AppInit: { init: async () => { settingsReady = true; } },
  AppContext: { ensureInitialized: () => {}, context: {} },
  // This suite isolates history/settings behaviour; real fullscreen lease
  // ownership/races are tested in reader_window_chrome_cases.js.
  ReaderWindowChrome: class { enter() { return Promise.resolve(); } leave() { return Promise.resolve(); } },
  Settings: {
    get readerMode() {
      if (!settingsReady) throw new Error('Settings.init() has not been called');
      modeReads++;
      return modePreference;
    },
    set readerMode(value) {
      modeWrites.push(value);
      modePreference = value;
    }
  },
  ReaderSettings: {
    resolve: () => {
      const value = new env.ReaderOptions(); value.readerMode = env.Settings.readerMode; return value;
    },
    set: async (scope, comicId, sourceKey, key, value) => {
      assert.deepEqual([scope, comicId, sourceKey, key], ['comic', 'comic', 'real-key', 'readerMode']);
      env.Settings.readerMode = value;
    }
  },
  router: { getParams: () => ({ sourceKey: 'real-key', comicId: 'comic', title: 'Route title' }) },
  Log: { warn: () => {}, error: () => {}, audit: (t,s,m)=>fs.appendFileSync(auditPath,`TraceID=${t} [${s}] ${m}\n`) },
  promptAction: { showToast: () => {} },
  ScrollAlign: { START: 0 },
  TouchType: { Down: 0 }
};
vm.createContext(env);
vm.runInContext(stripTypeScriptTypes(helper + '\n' + workload + '\n' + modes + '\n' + spreads + '\n' + renderSource + '\n' + volumeKeys + '\n' + options + '\n' + chapterNavigation + '\n' + reader +
  '\nthis.ReaderOptions = ReaderOptions; this.Reader = ReaderPage; this.Position = ReadingPosition;' +
  ' this.Modes = ReaderModes; this.MODE_KEYS = READER_MODES;', { mode: 'strip' }), env);

let assertions = 0;
function eq(actual, expected, label) {
  assert.deepEqual(actual, expected, label);
  assertions++;
}
function make() {
  const reader = new env.Reader();
  reader.sourceKey = 'real-key';
  reader.comicId = 'comic';
  reader.title = 'Fallback';
  return reader;
}

function purePositionCases() {
  const p = env.Position;
  eq(p.resolveChapter(['a', 'b']).chapterIndex, 0, 'first read starts at first chapter');
  eq(p.resolveChapter(['b', 'a'], 'a', 1).chapterIndex, 1, 'stable id beats stale ordinal');
  eq(p.resolveChapter(['a', 'b'], undefined, 2).chapterIndex, 1, 'legacy ep is 1-based');
  eq(p.resolveChapter([''], '').chapterIndex, 0, 'empty id is a valid implicit chapter');
  eq(p.resolveChapter(['a'], 'missing', 1).chapterIndex, -1, 'missing id must not use ordinal fallback');
  eq(p.resolveChapter(['a'], '', 1).chapterIndex, -1, 'explicit empty id must match');
  for (const value of [0, -1, 3, 1.5, NaN, Infinity]) {
    eq(p.resolveChapter(['a', 'b'], undefined, value).chapterIndex, -1, 'invalid legacy ordinal');
  }
  eq(p.resolveChapter([]).chapterIndex, -1, 'no chapter means no position');
  for (const value of [undefined, 0, -1, NaN, Infinity]) {
    eq(p.pageIndex(value, 5), 0, 'invalid page falls back to first page');
  }
  eq(p.pageIndex(3, 5), 2, 'persisted page is 1-based');
  eq(p.pageIndex(99, 5), 4, 'page overflow clamps to final page');
  eq(p.pageIndex(1, 0), -1, 'empty chapter has no valid page');


}

async function readerControlFlowCases() {
  reset();
  stored = { epId: undefined, ep: 2, page: 3, title: 'Old', cover: 'Old', subtitle: 'Old' };
  let reader = make();
  reader.resumeRequested = true;
  await reader.load();
  while (layoutTasks.length > 0) { layoutTasks.shift()(); }
  eq([reader.epId, reader.currentPage, reads, calls.join(',')], ['b', 2, 1, 'b'], 'legacy resume');
  eq([saves[0].storedSourceKey, saves[0].ep, saves[0].epId, saves[0].page,
    saves[0].title, saves[0].cover, saves[0].subtitle],
  ['real-key', 2, 'b', 3, 'Authoritative title', 'cover-url', 'Author'], 'authoritative saved metadata');
  eq(saves.length, 1, 'initial progress saves without requiring a page change');
  reader.updatePage(0);
  eq(reader.currentPage, 2, 'transient initial 0 must not erase restored position');
  reader.updatePage(2);
  reader.updatePage(3);
  while (layoutTasks.length > 0) { layoutTasks.shift()(); }
  eq(saves.at(-1).page, 4, 'valid page-change snapshot');
  now = 1500;
  reader.onPageHide();
  eq(saves.at(-1).page, 4, 'same-page exit retains the latest continue-reading page');
  eq(saves.length, 2, 'same-page exit does not record another event');
  let count = saves.length;
  now = 1600;
  reader.aboutToDisappear();
  eq(saves.length, count, 'second exit callback does not duplicate save');

  reset();
  stored = { epId: 'a', ep: 1, page: 4 };
  reader = make();
  reader.requestedEpId = 'b';
  reader.requestedPage = 1;
  await reader.load();
  eq([reader.epId, reader.currentPage, reads], ['b', 0, 0], 'explicit chapter starts at page 1, no history read');

  reset();
  stored = { epId: 'gone', ep: 1, page: 2 };
  reader = make();
  reader.resumeRequested = true;
  await reader.load();
  eq([calls.length, saves.length, reader.error.length > 0], [0, 0, true], 'missing chapter preserves history');

  for (const result of [{ error: true, errorMessage: 'offline' }, { error: false, dataOrNull: undefined }]) {
    reset();
    source.loadComicInfo = async () => result;
    reader = make();
    await reader.load();
    eq([calls.length, saves.length, reader.chapterIds.length, reader.error.length > 0],
      [0, 0, 0, true], 'failed/missing details must not fabricate a single chapter');
  }

  reset();
  source.loadComicPages = async () => ({ error: false, dataOrNull: [] });
  reader = make();
  await reader.load();
  eq([saves.length, reader.progressReady, reader.error.length > 0], [0, false, true], 'empty chapter does not save');

  reset();
  reader = make();
  await reader.load();
  now = 1250;
  let finish;
  let starts = 0;
  source.loadComicPages = () => {
    starts++;
    return new Promise(resolve => { finish = resolve; });
  };
  const switching = reader.switchChapter(1);
  await reader.switchChapter(1);
  eq([starts, reader.epId, saves.at(-1).epId, saves.at(-1).page],
    [1, 'a', 'a', 1], 'fast taps launch once and flush the OLD chapter first');
  now = 4000;
  finish({ error: false, dataOrNull: ['b1', 'b2'] });
  await switching;
  while (layoutTasks.length > 0) { layoutTasks.shift()(); }
  eq([reader.epId, reader.currentPage, saves.at(-1).epId, saves.at(-1).page],
    ['b', 0, 'b', 1], 'new chapter starts at its validated first page');
  now = 4250;
  reader.onPageHide();
  eq([saves.at(-1).epId, saves.at(-1).page], ['b', 1], 'same-page hide retains the new chapter position');

  reset();
  reader = make();
  await reader.load();
  now = 1200;
  let done;
  source.loadComicPages = () => new Promise(resolve => { done = resolve; });
  const leaving = reader.switchChapter(1);
  reader.aboutToDisappear();
  count = saves.length;
  done({ error: false, dataOrNull: ['b1'] });
  await leaving;
  eq([saves.length, reader.epId], [count, 'a'], 'late response after exit cannot commit');

  reset();
  reader = make();
  reader.requestedPage = 3;
  await reader.load();
  reader.restoreWaterfall();
  eq(reader.listScroller.target, 2, 'waterfall controller receives restored zero-based target');

  reset();
  reader = make();
  await reader.load();
  source.loadComicPages = async () => ({ error: true, errorMessage: 'failure' });
  now = 1100;
  await reader.switchChapter(1);
  eq([reader.epId, reader.progressReady, saves.at(-1).epId], ['a', false, 'a'], 'chapter failure preserves old history');
  count = saves.length;
  reader.aboutToDisappear();
  eq(saves.length, count, 'exiting failed chapter does not write invalid progress');
}

async function coldRouteSettingsCase() {
  reset();
  settingsReady = false;
  const reader = make();
  reader.getUIContext = () => ({ getHostContext: () => ({}) });
  const productionLoad = reader.load.bind(reader);
  let pendingLoad;
  reader.load = () => { pendingLoad = productionLoad(); return pendingLoad; };
  // This would throw synchronously if aboutToAppear read Settings before init.
  reader.aboutToAppear();
  await pendingLoad;
  eq([reader.error, reader.mode, modeReads], ['', 'waterfallTopToBottom', 1],
    'cold route reads Settings only after AppInit');
  reader.mode = 'galleryRightToLeft';
  await reader.load();
  eq([reader.mode, modeReads], ['galleryRightToLeft', 1],
    'retry does not reset the user-selected mode');
}

function modeCases() {
  const m = env.Modes;
  eq(env.MODE_KEYS.length, 7, 'all upstream reader modes are present');
  eq(env.MODE_KEYS.map(k => m.normalize(k)), env.MODE_KEYS, 'every mode key is accepted');
  eq(m.normalize('nonsense'), 'waterfallTopToBottom', 'unknown mode falls back like ReaderMode.fromKey');
  eq(m.nextMode('continuousRightToLeft'), 'galleryRightToLeft', 'mode cycle wraps around');
  eq([m.isGallery('galleryTopToBottom'), m.isGallery('waterfallTopToBottom')], [true, false], 'gallery detection');
  eq([m.isWaterfall('waterfallTopToBottom'), m.isContinuous('continuousLeftToRight'), m.isContinuous('galleryRightToLeft')],
    [true, true, false], 'waterfall counts as continuous, gallery does not');
  eq([m.isVertical('galleryTopToBottom'), m.isVertical('galleryLeftToRight'), m.isVertical('waterfallTopToBottom')],
    [true, false, true], 'vertical axis follows the mode name');
  eq([m.isReversed('galleryRightToLeft'), m.isReversed('continuousRightToLeft'), m.isReversed('continuousLeftToRight')],
    [true, true, false], 'only right-to-left modes reverse the list');
  eq(m.toDisplayIndex('galleryRightToLeft', 0, 3), 2, 'first page is last in a reversed list');
  eq(m.toActualIndex('galleryRightToLeft', 2, 3), 0, 'display index maps back for reversed modes');
  eq(m.toDisplayIndex('galleryLeftToRight', 2, 3), 2, 'left-to-right keeps the order');
  eq(m.toDisplayIndex('galleryRightToLeft', 9, 3), 0, 'overflow clamps before reversing');
  eq(m.toDisplayIndex('galleryRightToLeft', 0, 0), 0, 'empty chapter has no page');
  eq(m.displayOrder('galleryRightToLeft', ['a', 'b', 'c']).join(''), 'cba', 'reversed order reverses urls');
  eq(m.displayOrder('galleryLeftToRight', ['a', 'b', 'c']).join(''), 'abc', 'normal order keeps urls');
  const original = ['a', 'b'];
  m.displayOrder('galleryRightToLeft', original);
  eq(original.join(''), 'ab', 'displayOrder must not mutate the source array');
  eq(m.label('galleryRightToLeft').length > 0, true, 'every mode has a label');
}

async function modeRenderingCase() {
  reset();
  const reader = make();
  reader.getUIContext = () => ({ getHostContext: () => ({}) });
  await reader.load();
  eq(reader.mode, 'waterfallTopToBottom', 'mode comes from settings');
  eq(reader.displayImages.join(','), 'img1,img2,img3,img4', 'forward order for a top-to-bottom mode');
  const before = reader.currentPage;
  await reader.setMode('galleryRightToLeft');
  while (layoutTasks.length > 0) { layoutTasks.shift()(); }
  eq([reader.mode, modeWrites.at(-1)], ['galleryRightToLeft', 'galleryRightToLeft'], 'mode change is persisted');
  eq(reader.displayImages.join(','), 'img4,img3,img2,img1', 'reversed mode reverses the rendered pages');
  eq(reader.currentPage, before, 'changing mode keeps the same page');
  eq(reader.restorePage, 3, 'restore target follows the new display order');
  // A page change in a reversed list must still store the real page number.
  reader.updatePage(3);
  eq(reader.restorePage, -1, 'reporting the restored index clears the guard');
  reader.updatePage(1);
  eq([reader.currentPage, reader.requestedPage], [2, 3], 'display index is converted back before saving');
  await reader.setMode('galleryRightToLeft');
  while (layoutTasks.length > 0) { layoutTasks.shift()(); }
  eq(modeWrites.length, 1, 'selecting the current mode is a no-op');
}

(async () => {
  purePositionCases();
  const helperCount = assertions;
  modeCases();
  const modeCount = assertions - helperCount;
  await readerControlFlowCases();
  const controlCount = assertions - helperCount - modeCount;
  await coldRouteSettingsCase();
  await modeRenderingCase();
  const tail = assertions - helperCount - modeCount - controlCount;
  console.log(`PASS ${assertions} production assertions: ${helperCount} position + ` +
    `${modeCount} reader modes + ${controlCount} reader control-flow + ${tail} cold-route/render.`);
  fs.appendFileSync(auditPath,`TraceID=history-reader-tests [响应返回] PASS ${assertions} production assertions\n`);
  console.log('No ArkTS build/source rules/device. ArkUI visual usability and real database durability remain separate acceptance checks.');
})().catch(error => {
  fs.appendFileSync(auditPath,`TraceID=history-reader-tests [异常] ${error.stack}\n`);
  console.error(error);
  process.exitCode = 1;
});
