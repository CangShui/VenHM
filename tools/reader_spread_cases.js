'use strict';
/** Executes production ETS helpers/control bodies; no ArkUI/device/build/network. */
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
const raw = read('entry/src/main/ets/pages/ReaderPage.ets');
const reader = (raw.slice(0, raw.indexOf('  @Builder')) + '}')
  .replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace('struct ReaderPage', 'class ReaderPage');
const options = read('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
let tasks = [], calls = [], saves = [], toasts = [], active, failWrite = false;
const context = vm.createContext({
  SwiperController: class { changeIndex(index, animation) { calls.push(['swiper', index, animation]); } },
  Scroller: class {
    scrollToIndex(index, animation) { calls.push(['list', index, animation]); }
    // Production asks the scroller whether the flow already reached the end,
    // and may nudge the viewport by a pixel delta.
    // Tests flip this to simulate reaching the end of a continuous flow.
    isAtEnd() { return globalThis.__listAtEnd === true; }
    scrollBy(x, y) { calls.push(['scrollBy', x, y]); }
  },
  History: class {}, ComicType: { fromKey: () => ({ value: 1 }) },
  HistoryDao: { save: h => { saves.push(h); return Promise.resolve(); } },
  ReaderSettings: { resolve: () => active, setActive: async (id, key, name, value) => {
    if (failWrite) throw new Error('full disk');
    active = Object.assign(new context.Options(), active, { [name]: value });
  } },
  AppInit: { init: async () => {} }, Log: { audit() {}, warn() {}, error() {} },
  promptAction: { showToast: value => toasts.push(value.message) }, ScrollAlign: { START: 0 },
  setTimeout: fn => { tasks.push(fn); return tasks.length; },
  clearTimeout: () => {},
  setInterval: () => 1, clearInterval() {},
  TouchType: { Down: 0 }, router: { pushUrl: async value => { calls.push(['route', value]); } },
  // ArkUI unit helper used by the reader's end-of-flow probe.
  px2vp: (value) => value,
  // Reader status-bar clock/battery read (device API, deterministic in tests).
  batteryInfo: { batterySOC: 100 },
  AppContext: { context: {} },
  // Fullscreen window sequencing is tested independently; spread anchors and
  // source/image identities remain this suite's contract.
  ReaderWindowChrome: class { enter() { return Promise.resolve(); } leave() { return Promise.resolve(); } }
});
const logic = read('entry/src/main/ets/features/ReaderModes.ets') + '\n' +
  read('entry/src/main/ets/features/ReaderSpreads.ets') + '\n' +
  read('entry/src/main/ets/features/ReaderRenderSource.ets') + '\n' +
  read('entry/src/main/ets/features/ReaderVolumeKeys.ets') + '\n' +
  read('entry/src/main/ets/features/ReadingPosition.ets') + '\n' + options + '\n' + reader;
vm.runInContext(stripTypeScriptTypes(logic, { mode: 'transform' }) +
  '\nglobalThis.Spreads=ReaderSpreads;globalThis.Reader=ReaderPage;globalThis.Options=ReaderOptions;', context);
const S = context.Spreads;
const plain = value => JSON.parse(JSON.stringify(value));
let count = 0;
function check(fn) { fn(); count++; }
function flush() { while (tasks.length) tasks.shift()(); }
function readyVisible(p) {
  const indices = p.mode.startsWith('gallery') ? p.displaySpreads[p.sourceToDisplay(p.currentPage)].imageIndices : [p.currentPage];
  for (const actual of indices) p.onImageReady(actual, p.renderGeneration, true);
}
function page(mode = 'galleryLeftToRight', imageCount = 11, size = 3, first = false) {
  tasks = []; calls = []; saves = []; toasts = []; failWrite = false;
  const p = new context.Reader(); p.visible = true; p.loading = false; p.progressReady = true;
  p.images = Array.from({ length: imageCount }, (_, index) => `source-${index}`);
  p.chapterIds = ['chapter-A', 'chapter-B']; p.epId = 'chapter-A';
  p.sourceKey = 'fixture'; p.comicId = 'comic'; p.mode = mode;
  active = new context.Options(); active.readerMode = mode;
  active.readerScreenPicNumberForPortrait = size; active.readerScreenPicNumberForLandscape = 5;
  active.showSingleImageOnFirstPage = first; p.options = active; p.rebuildPresentation();
  readyVisible(p);
  return p;
}
(async () => {
  for (let images = 0; images <= 27; images++) for (let size = 1; size <= 5; size++) {
    for (const first of [false, true]) for (const rtl of [false, true]) check(() => {
      const groups = S.create(images, size, first, rtl);
      const canonical = rtl ? Array.from(groups).reverse() : Array.from(groups);
      assert.deepEqual(canonical.flatMap(group => Array.from(group.imageIndices).sort((a,b) => a-b)),
        Array.from({ length: images }, (_, i) => i));
      if (images && first) assert.equal(canonical[0].end, 1);
      for (let source = 0; source < images; source++) {
        const display = S.sourceToDisplay(source, images, size, first, rtl);
        assert.ok(source >= groups[display].start && source < groups[display].end);
        assert.equal(S.displayToSource(display, images, size, first, rtl), groups[display].start);
      }
      for (let group = 0; group < canonical.length; group++) {
        for (let source = canonical[group].start; source < canonical[group].end; source++) {
          assert.equal(S.nextSource(source, images, size, first, 1), canonical[group + 1]?.start ?? -1);
          assert.equal(S.nextSource(source, images, size, first, -1), canonical[group - 1]?.start ?? -1);
        }
      }
    });
  }
  check(() => {
    assert.deepEqual(plain(S.create(8, 3, true, true)).map(g => g.imageIndices), [[7],[6,5,4],[3,2,1],[0]]);
    assert.equal(S.pageCounter(2, 8, 3, true), '2–4 / 8');
    assert.equal(S.pageCounter(7, 8, 3, true), '8 / 8');
    assert.equal(S.perScreen(2, 5, false), 2); assert.equal(S.perScreen(2, 5, true), 5);
    assert.equal(S.perScreen(NaN, Infinity, false), 1);
    assert.equal(S.perScreen(9, 0, true), 1); assert.equal(S.perScreen(9, 0, false), 5);
    assert.equal(S.displayToSource(99, 8, 3, true), -1);
  });
  check(() => {
    const p = page('galleryRightToLeft', 11, 3, true); p.seekPage(3); flush();
    assert.equal(p.currentPage, 3); assert.equal(saves.at(-1).page, 4);
    assert.equal(saves.at(-1).maxPage, 11); assert.equal(saves.at(-1).epId, 'chapter-A');
    assert.equal(calls.at(-1)[1], 3); // canonical [1,4) in 5 RTL groups
    p.updatePage(3); assert.equal(p.currentPage, 3); // saved exact source, not first in group
    p.stepPage(1); flush(); assert.equal(p.currentPage, 4); assert.equal(saves.at(-1).page, 5);
    assert.equal(p.pageCounter(), '5–7 / 11');
    p.stepPage(-1); assert.equal(p.currentPage, 1);
    assert.deepEqual(Array.from(p.images), Array.from({ length: 11 }, (_, i) => `source-${i}`));
  });
  check(() => {
    const p = page(); p.seekPage(4); p.onViewportSize(1200, 600);
    assert.equal(p.currentPage, 4); assert.equal(p.requestedPage, 5);
    assert.equal(p.imagesPerScreen(), 5); assert.equal(p.restorePage, 0);
    p.updatePage(1); assert.equal(p.currentPage, 4); flush(); p.updatePage(0);
    assert.equal(p.currentPage, 4); p.saveProgress(); flush(); assert.equal(saves.at(-1).page, 5);
    p.onViewportSize(600, 1200); flush(); p.updatePage(1); assert.equal(p.currentPage, 4);
    assert.equal(p.pageCounter(), '4–6 / 11');
  });
  check(() => {
    const p = page(); p.seekPage(7);
    const next = Object.assign(new context.Options(), p.options, { showSingleImageOnFirstPage: true,
      readerScreenPicNumberForPortrait: 2 }); p.applySettings(next); flush();
    p.updatePage(p.sourceToDisplay(7)); assert.equal(p.currentPage, 7); assert.equal(p.requestedPage, 8);
    p.saveProgress(); flush(); assert.equal(saves.at(-1).page, 8);
    p.stepPage(1); assert.equal(p.currentPage, 9);
  });
  check(() => {
    const p = page('continuousTopToBottom'); p.seekPage(7);
    const next = Object.assign(new context.Options(), p.options, { readerSideMargin: 30,
      splitDualPage: true, splitDualPageInvert: true }); p.applySettings(next); flush();
    assert.equal(p.flowWidth(), '40%'); assert.equal(p.currentPage, 7);
    const generation = p.zoomReset; p.onFlowImageSize(1, generation, 200, 1500);
    p.updatePage(3); assert.equal(p.currentPage, 7); flush();
    assert.deepEqual(calls.at(-1).slice(0,2), ['list',7]);
    p.updatePage(7); p.saveProgress(); flush(); assert.equal(saves.at(-1).maxPage, 11);
    p.mode = 'continuousLeftToRight'; assert.equal(p.flowWidth(), '100%');
    p.mode = 'galleryTopToBottom'; assert.equal(p.flowWidth(), '100%');
  });
  check(() => {
    const p = page(); const generation = p.zoomReset;
    p.onImageZoom(0,generation,true); p.onImageZoom(1,generation,true);
    p.onImageZoom(0,generation,false); assert.equal(p.zoomed,true);
    p.onImageZoom(2,generation,false); assert.equal(p.zoomed,true);
    p.onImageZoom(1,generation,false); assert.equal(p.zoomed,false);
    p.onImageZoom(7,generation,true); assert.equal(p.zoomed,false); // hidden group ignored
    p.stepPage(1); p.onImageZoom(3,p.zoomReset,true);
    p.onImageZoom(3,generation,false); assert.equal(p.zoomed,true); // stale child cannot unlock
  });
  check(() => {
    const p = page('continuousTopToBottom');
    p.visibleFirst=0;p.visibleLast=2;p.onImageZoom(2,p.zoomReset,true);assert.equal(p.zoomed,true);
    p.visibleFirst=3;p.visibleLast=4;p.refreshZoomState();assert.equal(p.zoomed,false);
  });
  {
    const p = page(); p.autoReading = true; await p.autoStep();
    assert.equal(p.currentPage, 3); readyVisible(p); await p.autoStep(); assert.equal(p.currentPage, 6);
    p.scrolling=true;await p.autoStep();assert.equal(p.currentPage,6);count++;
  }
  {
    const p = page('galleryRightToLeft'); p.autoReading = true; p.readyImages.clear();
    const generation = p.renderGeneration;
    await p.autoStep(); assert.equal(p.currentPage, 0); // URL list alone never proves decoding
    p.onImageReady(7, generation, true); p.onImageReady(0, generation, true);
    p.onImageReady(1, generation, true); await p.autoStep(); assert.equal(p.currentPage, 0);
    p.onImageReady(2, generation, true); await p.autoStep(); assert.equal(p.currentPage, 3);
    for (const actual of [3,4,5]) p.onImageReady(actual, generation - 1, true);
    await p.autoStep(); assert.equal(p.currentPage, 3); // stale ready cannot unblock newer spread
    p.onImageReady(3, p.renderGeneration, true); p.onImageReady(4, p.renderGeneration, true);
    p.onImageReady(3, generation - 1, false); // stale false cannot remove new-generation readiness
    p.onImageReady(0, p.renderGeneration, false); p.onImageReady(5, p.renderGeneration, true);
    assert.equal(p.visibleImagesReady(), true); await p.autoStep(); assert.equal(p.currentPage, 6);
    readyVisible(p); p.onImageReady(7, p.renderGeneration, false);
    await p.autoStep(); assert.equal(p.currentPage, 6); // sibling reload/error pauses whole visible spread
    p.onImageReady(7, p.renderGeneration, true); await p.autoStep(); assert.equal(p.currentPage, 9); count++;
  }
  {
    const p = page('continuousTopToBottom'); p.autoReading = true; const oldGeneration = p.renderGeneration - 1;
    p.seekPage(2); p.onImageReady(3, p.renderGeneration, true); p.onImageReady(2, oldGeneration, true);
    await p.autoStep(); assert.equal(p.currentPage, 2);
    p.onImageReady(2, p.renderGeneration, true); assert.equal(p.visibleImagesReady(), true);
    // Continuous flow auto-scrolls while it can still move, like upstream.
    globalThis.__listAtEnd = false; calls.length = 0;
    await p.autoStep(); assert.equal(p.currentPage, 2); assert.equal(calls.at(-1)[0], 'scrollBy');
    // At the end of the flow it stops instead of scrolling further.
    globalThis.__listAtEnd = true; p.options.autoReadingAcrossChapters = false;
    await p.autoStep(); assert.equal(p.autoReading, false); assert.equal(p.currentPage, 2);
    globalThis.__listAtEnd = false; count++;
  }
  {
    const p = page(); const before = p.mode; failWrite = true; await p.setMode('galleryRightToLeft');
    assert.equal(p.mode,before);assert.equal(p.settingsSaving,false);assert.equal(toasts.length,1);count++;
    failWrite = false; await p.setMode('galleryRightToLeft');flush();
    assert.equal(p.mode,'galleryRightToLeft');assert.equal(p.currentPage,0);count++;
  }
  {
    const p = page(); p.currentPage=4; p.requestedPage=5;
    active=Object.assign(new context.Options(),p.options,{readerScreenPicNumberForPortrait:2});
    await p.reloadSettings();flush();assert.equal(p.imagesPerScreen(),2);assert.equal(p.currentPage,4);count++;
  }
  {
    const p = page(); const generation = p.zoomReset; const readyGeneration = p.renderGeneration;
    assert.equal(p.visibleImagesReady(), true); p.onPageHide();
    assert.equal(p.zoomReset, generation); assert.equal(p.visibleImagesReady(), true);
    p.onImageReady(0, readyGeneration, false); assert.equal(p.visibleImagesReady(), false);
    p.onImageReady(0, readyGeneration, true); assert.equal(p.visibleImagesReady(), true); // background current-image decode is accepted
    p.onPageShow(); await p.reloadSettings(); flush();
    assert.equal(p.zoomReset, generation); assert.equal(p.visibleImagesReady(), true); count++;
  }
  check(() => {
    assert.match(raw,/url: this\.images\[actual\]/);
    // Rendering is lazy per source identity; grouping itself is unchanged.
    assert.match(raw,/LazyForEach\(this\.spreadSource/);
    assert.match(raw,/LazyForEach\(this\.flowSource/);
    assert.match(raw,/ForEach\(spread\.imageIndices/);
    assert.match(raw,/splitWideImage: this\.isVerticalFlow\(\) && this\.options\.splitDualPage/);
    assert.match(raw,/splitWideImageInvert: this\.isVerticalFlow\(\) && this\.options\.splitDualPageInvert/);
    assert.match(raw,/history\.maxPage = this\.images\.length/);
    assert.match(raw,/params: \{ comicId: this\.comicId, sourceKey: this\.sourceKey \}/);
    assert.match(raw,/this\.reloadSettings\(\)/);
    assert.equal((raw.match(/onReadyChanged: \(value: boolean\) => \{ this\.onImageReady\(actual, generation, value\); \}/g) || []).length, 2);
    assert.match(raw,/this\.onViewportSize\(Number\(area\.width\), Number\(area\.height\)\)/);
  });
  console.log(`PASS ${count} production spread/source-anchor/settings/zoom cases; no ArkUI rendering or device acceptance.`);
})().catch(error => { console.error(error); process.exitCode=1; });
