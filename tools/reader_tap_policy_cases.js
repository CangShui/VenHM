'use strict';
/** Production helper + ReaderPage/AsyncComicImage method tests. No build/device/ArkUI acceptance. */
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
const rawReader = read('entry/src/main/ets/pages/ReaderPage.ets');
const reader = (rawReader.slice(0, rawReader.indexOf('  @Builder')) + '}')
  .replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace('struct ReaderPage', 'class ReaderPage');
const rawImage = read('entry/src/main/ets/components/ComicWidgets.ets');
const image = (rawImage.slice(0, rawImage.indexOf('  build() {')) + '}')
  .replace(/@(?:Entry|Component|State|Prop)\s*|@Watch\('[^']+'\)\s*/g, '').replace('struct AsyncComicImage', 'class AsyncComicImage');
const options = read('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
let now = 1000, sequence = 0, tasks = new Map(), calls = [], saves = [], stack = [], failRoute = false;
const ctx = vm.createContext({
  Date: class extends Date { static now() { return now; } },
  setTimeout: (fn, delay) => { const id = ++sequence; tasks.set(id, { fn, at: now + delay }); return id; },
  clearTimeout: id => tasks.delete(id), setInterval: () => 1, clearInterval() {},
  SwiperController: class { changeIndex(i) { calls.push(['swiper', i]); } },
  Scroller: class {
    scrollToIndex(i) { calls.push(['list', i]); }
    currentOffset() { return { xOffset: 800, yOffset: 1600 }; }
    isAtEnd() { return false; }
    scrollBy(x, y) { calls.push(['scrollBy', x, y]); }
  },
  History: class {}, ComicType: { fromKey: () => ({ value: 1 }) }, HistoryDao: { save: async h => saves.push(h) },
  ImageFit: { Cover: 0 }, ImageRequestConfig: class {}, ImageLoader: { cancelOwned() {} },
  ReaderSettings: {}, AppContext: { context: {} },
  Log: { audit() {}, warn() {}, error() {} }, promptAction: { showToast: () => calls.push(['toast']) },
  TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 },
  router: { getState: () => stack.at(-1), getStateByIndex: i => stack[i - 1],
    back: () => calls.push(['back']), replaceUrl: async p => { if (failRoute) throw Error('route failure'); calls.push(['replace', p]); } }
});
const helpers = ['ReaderTapPolicy', 'ReaderGesturePolicy', 'ReaderModes', 'ReaderSpreads', 'ReaderRenderSource', 'ReaderVolumeKeys', 'ReaderWorkload', 'ReadingPosition', 'ReaderImageLayout']
  .map(name => read(`entry/src/main/ets/features/${name}.ets`)).join('\n') + '\n' +
  read('entry/src/main/ets/components/ReaderClickZones.ets');
vm.runInContext(stripTypeScriptTypes(helpers + '\n' + options + '\n' + reader + '\n' + image, { mode: 'transform' }) +
  '\nglobalThis.Policy=ReaderTapPolicy;globalThis.Reader=ReaderPage;globalThis.Image=AsyncComicImage;globalThis.Options=ReaderOptions;', ctx);
const P = ctx.Policy;
let count = 0;
async function test(name, fn) { await fn(); count++; console.log(`PASS ${name}`); }
function tick(ms) { now += ms; for (const [id, task] of Array.from(tasks)) if (task.at <= now) { tasks.delete(id); task.fn(); } }
function page(mode = 'galleryLeftToRight', size = 1) {
  calls = []; saves = []; failRoute = false;
  const p = new ctx.Reader(); p.mode = mode; p.images = ['a','b','c','d','e','f','g']; p.chapterIds = ['ch']; p.epId = 'ch';
  p.sourceKey = 'source'; p.comicId = 'comic'; p.title = 'Title'; p.cover = 'Cover'; p.loading = false; p.progressReady = true;
  // Page-turn contracts start in immersive mode; entry-menu behaviour is
  // explicitly exercised by reader_immersive_cases.js instead of bypassed there.
  p.toolbarVisible = false;
  p.options.readerScreenPicNumberForPortrait = size; p.rebuildPresentation(); ready(p); return p;
}
function ready(p) { const indices = p.mode.startsWith('gallery') ? p.displaySpreads[p.sourceToDisplay(p.currentPage)].imageIndices : [p.currentPage];
  for (const i of indices) p.onImageReady(i, p.renderGeneration, true); }
function component() { tasks.clear(); const p = new ctx.Image(); p.singleTapEnabled = true; p.pixelMap = {}; p.tapWidth = 400;
  p.onSingleTap = x => calls.push(['tap', x]); calls = []; return p; }
const gesture = x => ({ fingerList: [{ localX: x }] });
const touch = (type, x = 20, y = 20, fingers = 1) => ({ type, touches: Array.from({length:fingers}, () => ({x,y})) });
(async () => {
  await test('local coordinate normalization rejects unavailable/outside viewport and uses image width', () => {
    assert.equal(P.normalizeX(20, 400), .05); for (const [x,w] of [[NaN,400],[1,0],[-1,400],[401,400]]) assert.equal(P.normalizeX(x,w), -1);
  });
  await test('all seven modes support requested horizontal side regions; RTL semantics and reverse preference', () => {
    for (const mode of ['galleryLeftToRight','galleryRightToLeft','galleryTopToBottom','continuousLeftToRight','continuousRightToLeft','continuousTopToBottom','waterfallTopToBottom']) {
      const rtl = mode.includes('RightToLeft'), sign = rtl ? -1 : 1;
      assert.equal(P.step(mode,.1,true,false), -sign); assert.equal(P.step(mode,.9,true,false), sign);
      assert.equal(P.step(mode,.1,true,true), sign); assert.equal(P.step(mode,.9,true,true), -sign);
      for (const x of [.3,.5,.7]) assert.equal(P.step(mode,x,true,false), 0);
      assert.equal(P.step(mode,.9,false,false), 0);
    }
  });
  await test('spread coordinates avoid treating middle images as outer edges', () => {
    assert.equal(P.spreadX(.9, 1, 3), 1.9/3); assert.equal(P.step('galleryLeftToRight', P.spreadX(.9,1,3),true,false),0);
    assert.equal(P.spreadX(.9, -1,3),-1); assert.equal(P.spreadX(.9,2,3),2.9/3);
  });
  await test('gallery tap advances one actual spread and retains source/history identities', () => {
    const p = page('galleryLeftToRight',3); p.onReaderViewportTap(.9,.5); tick(500);
    assert.equal(p.currentPage,3); assert.equal(saves.at(-1).page,4); assert.equal(saves.at(-1).epId,'ch'); assert.deepEqual(calls.at(-1),['swiper',1]);
    ready(p); p.onReaderViewportTap(.1,.5); assert.equal(p.currentPage,0);
  });
  await test('RTL left advances canonical spread; RTL right returns; reverse toggles semantics', () => {
    const p = page('galleryRightToLeft',3);
    p.onReaderViewportTap(.1,.5); assert.equal(p.currentPage,3); ready(p);
    p.onReaderViewportTap(.9,.5); assert.equal(p.currentPage,0);
    ready(p); p.options.reverseTapToTurnPages = true; p.onReaderViewportTap(.9,.5); assert.equal(p.currentPage,3);
  });
  await test('viewport center opens modal menu; outside dismiss consumes tap; next grid action pages or scrolls one screen', () => {
    for (const mode of ['galleryTopToBottom','continuousTopToBottom','waterfallTopToBottom','continuousLeftToRight']) {
      const p=page(mode); p.viewportWidth=400; p.viewportHeight=800;
      p.onReaderViewportTap(.5,.5); assert.equal(p.currentPage,0); assert.equal(p.toolbarVisible,true);
      tick(200);p.onReaderViewportTap(.9,.5); assert.equal(p.currentPage,0); assert.equal(p.toolbarVisible,false);
      tick(200);p.onReaderViewportTap(.9,.5);
      if(mode.startsWith('gallery')){assert.equal(p.currentPage,1);assert.equal(calls.at(-1)[0],'swiper')}
      else{assert.equal(p.currentPage,0);assert.deepEqual(calls.at(-1),mode==='continuousLeftToRight'?['scrollBy',400,0]:['scrollBy',0,800])}
    }
  });
  await test('zoom/loading/hidden/disposed/scroll/layout/chapter overlay/readiness gates still block page turns', () => {
    for (const [key,value] of [['zoomed',true],['loading',true],['visible',false],['disposed',true],['scrolling',true],['layoutPending',true],['showChapters',true],['progressReady',false],['leavingReader',true]]) {
      const p=page(); p[key]=value; p.onReaderViewportTap(.9,.5); assert.equal(p.currentPage,0,key);
    }
    const p=page('galleryLeftToRight',3); p.readyImages.delete(1); p.onReaderViewportTap(.9,.5); assert.equal(p.currentPage,0);
    assert.doesNotMatch(rawReader,/onSingleTap:/,'stale image-level taps must not bypass viewport load/generation arbitration');
  });
  await test('Tap1 is deferred exactly 200ms and delivers normalized local position', () => {
    const p=component(); p.trackTapTouch(touch(0)); p.queueSingleTap(gesture(380)); tick(199); assert.equal(calls.length,0);
    tick(1); assert.deepEqual(calls,[['tap',.95]]);
  });
  await test('Tap2 cancels pending Tap1 and later parallel Tap1 even with double zoom disabled', () => {
    const p=component(); p.doubleTapZoomEnabled=false; p.trackTapTouch(touch(0)); p.queueSingleTap(gesture(380)); tick(100);
    p.trackTapTouch(touch(0)); p.handleDoubleTap(); p.queueSingleTap(gesture(380)); tick(300); assert.equal(calls.length,0);
  });
  await test('drag, pinch contacts, touch cancel, reset/reload/disappear, and disable invalidate deferred singles', () => {
    for (const cancel of [p=>p.trackTapTouch(touch(1,40)),p=>p.trackTapTouch(touch(0,20,20,2)),p=>p.trackTapTouch(touch(3)),
      p=>p.resetZoom(),p=>p.aboutToDisappear(),p=>{p.singleTapEnabled=false;p.cancelSingleTap();},p=>{p.requestVersion++;}]) {
      const p=component(); p.trackTapTouch(touch(0)); p.queueSingleTap(gesture(380)); cancel(p); tick(300); assert.equal(calls.length,0);
    }
    const p=component(); p.trackTapTouch(touch(0)); p.trackTapTouch(touch(1,40)); p.queueSingleTap(gesture(380)); tick(300); assert.equal(calls.length,0);
  });
  await test('double tap preserves existing zoom and never turns a page', () => {
    const p=component(); p.zoomEnabled=true; p.trackTapTouch(touch(0)); p.queueSingleTap(gesture(20)); p.handleDoubleTap(); tick(300);
    assert.equal(p.scaleValue,2); assert.equal(calls.length,0); p.handleDoubleTap(); assert.equal(p.scaleValue,1);
  });
  await test('matching immediate details predecessor uses Back only after progress and cleanup', async () => {
    const p=page(); now+=20; stack=[{index:1,name:'ComicDetailsPage',path:'pages/ComicDetailsPage',params:{sourceKey:'source',comicId:'comic'}},{index:2,name:'ReaderPage'}];
    p.autoReading=true; p.autoTimer=1; await p.openComicDetails(); assert.deepEqual(calls,[['back']]); assert.equal(p.autoReading,false);
    assert.equal(saves.at(-1).page,1); assert.equal('readDurationMs' in saves.at(-1),false); assert.equal(p.visible,false);
  });
  await test('SDK file-name route identity includes js/ets extension even with directory-only path', async()=>{
    for(const name of ['ComicDetailsPage.js','ComicDetailsPage.ets']){
      const p=page();stack=[{index:1,name,path:'pages/',params:{sourceKey:'source',comicId:'comic'}},{index:2,name:'ReaderPage'}];
      await p.openComicDetails();assert.deepEqual(calls,[['back']]);
    }
    const p=page();stack=[{index:1,name:'ComicDetailsPageFake.js',path:'pages/',params:{sourceKey:'source',comicId:'comic'}},{index:2,name:'ReaderPage'}];
    await p.openComicDetails();assert.equal(calls[0][0],'replace');
  });
  await test('continue-reading and mismatching details replace Reader with stable typed details params', async () => {
    for (const previous of [{name:'Index',path:'pages/Index',params:{}},{name:'ComicDetailsPage',path:'pages/ComicDetailsPage',params:{sourceKey:'other',comicId:'comic'}}]) {
      const p=page(); stack=[{...previous,index:1},{index:2,name:'ReaderPage'}]; await p.openComicDetails();
      assert.deepEqual(JSON.parse(JSON.stringify(calls)),[['replace',{url:'pages/ComicDetailsPage',params:{sourceKey:'source',comicId:'comic',title:'Title',cover:'Cover'}}]]);
      await p.openComicDetails(); assert.equal(calls.length,1);
    }
  });
  await test('details route failure restores reader availability; ordinary Back still returns origin', async () => {
    const p=page(); stack=[{index:1,name:'Index',params:{}},{index:2,name:'ReaderPage'}]; failRoute=true;
    await p.openComicDetails(); assert.equal(p.visible,true); assert.equal(p.leavingReader,false); assert.equal(p.disposed,false);
    calls=[]; p.returnToPrevious(); assert.deepEqual(calls,[['back']]); assert.equal(p.disposed,true);
  });
  await test('tap options default upstream true/false, inherit layers, cold-load, and explicit reset', async () => {
    function settings(initial = {}) {
      const values = new Map(Object.entries(initial));
      const c = vm.createContext({ Settings: { getString:(k,f)=>typeof values.get(k)==='string'?values.get(k):f,
        getBool:(k,f)=>typeof values.get(k)==='boolean'?values.get(k):f, getInt:(k,f)=>typeof values.get(k)==='number'?values.get(k):f,
        setString:async(k,v)=>values.set(k,v) } });
      vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/features/ReaderModes.ets')+'\n'+read('entry/src/main/ets/foundation/ReaderSettings.ets'),{mode:'transform'})+'\nglobalThis.SettingsSubject=ReaderSettings;',c);
      return { s:c.SettingsSubject, values };
    }
    const e=settings(); let o=e.s.resolve('comic','source'); assert.equal(o.enableTapToTurnPages,true); assert.equal(o.reverseTapToTurnPages,false);
    await e.s.set('global','','','enableTapToTurnPages',false); await e.s.set('device','','','reverseTapToTurnPages',true); await e.s.setEnabled('device',true);
    o=e.s.resolve('comic','source'); assert.equal(o.enableTapToTurnPages,false); assert.equal(o.reverseTapToTurnPages,true);
    await e.s.setEnabled('comic',true,'comic','source'); await e.s.set('comic','comic','source','enableTapToTurnPages',true); await e.s.set('comic','comic','source','reverseTapToTurnPages',false);
    o=e.s.resolve('comic','source'); assert.equal(o.enableTapToTurnPages,true); assert.equal(o.reverseTapToTurnPages,false);
    const cold=settings(Object.fromEntries(e.values)); assert.equal(cold.s.resolve('comic','source').enableTapToTurnPages,true);
    await e.s.reset('comic','comic','source'); assert.equal(e.s.resolve('comic','source').enableTapToTurnPages,false);
    await e.s.reset('device'); await e.s.reset('global'); o=e.s.resolve('comic','source'); assert.equal(o.enableTapToTurnPages,true); assert.equal(o.reverseTapToTurnPages,false);
    await assert.rejects(e.s.set('global','','','enableTapToTurnPages','true'));
  });
  console.log(`PASS ${count} reader tap/policy/routing production cases; SDK gesture recognition and device UI remain separate.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
