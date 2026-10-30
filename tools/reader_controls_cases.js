'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/reader-controls-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=reader-controls-tests production methods, not gesture rendering\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const raw=read('entry/src/main/ets/pages/ReaderPage.ets');
const reader=(raw.slice(0,raw.indexOf('  @Builder'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct ReaderPage','class ReaderPage');
const controls=[],timers=new Map(),history=[],timerDelays=[];
const ctx=vm.createContext({
  SwiperController:class{changeIndex(i){controls.push(['swiper',i])}},
  Scroller:class{scrollToIndex(i){controls.push(['list',i])}currentOffset(){return {xOffset:100,yOffset:100}}isAtEnd(){return false}scrollBy(x,y){controls.push(['scrollBy',x,y])}},
  ReaderSettings:{resolve:()=>({readerMode:'galleryRightToLeft'}),set:async()=>{}},History:class{},ComicType:{fromKey:()=>({value:1})},HistoryDao:{save:async h=>history.push(h)},
  Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),warn:()=>{},error:()=>{}},
  AppContext:{context:{}},window:{getLastWindow:async()=>({getWindowProperties:()=>({brightness:0.55,isKeepScreenOn:false}),
    setWindowBrightness:async v=>controls.push(['brightness',v]),setWindowKeepScreenOn:async v=>controls.push(['keepScreen',v])})},
  promptAction:{showToast:()=>{}},setInterval:(fn,delay)=>{timers.set(1,fn);timerDelays.push(delay);return 1},clearInterval:id=>timers.delete(id),
  // Progress writes are coalesced in production; this control-flow suite asserts
  // the resulting record, so run the scheduled flush immediately.
  setTimeout:fn=>{fn();return 1},clearTimeout:()=>{}
});
const options=read('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
const logic=read('entry/src/main/ets/features/ReaderWorkload.ets')+'\n'+
  read('entry/src/main/ets/features/ReaderVolumeKeys.ets')+'\n'+
  read('entry/src/main/ets/features/ReaderModes.ets')+'\n'+read('entry/src/main/ets/features/ReaderSpreads.ets')+'\n'+
  read('entry/src/main/ets/features/ReaderRenderSource.ets')+'\n'+
  read('entry/src/main/ets/features/ReadingPosition.ets')+'\n'+options+'\n'+
  read('entry/src/main/ets/features/ChapterNavigation.ets')+'\n'+reader;
vm.runInContext(stripTypeScriptTypes(logic,{mode:'transform'})+'\nglobalThis.Reader=ReaderPage;',ctx);
function page(){
  const p=new ctx.Reader();p.loading=false;p.progressReady=true;p.images=['a','b','c'];p.displayImages=['c','b','a'];
  p.chapterIds=['ch'];p.chapterTitles=['Chapter'];p.epId='ch';p.mode='galleryRightToLeft';p.sourceKey='fixture';p.comicId='sample';p.rebuildPresentation();p.onImageReady(p.currentPage,p.renderGeneration,true);return p;
}
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=reader-controls-tests PASS ${name}\n`)}
(async()=>{
  await test('auto reading restores original keep-screen policy on pause',async()=>{
    controls.length=0;const p=page();p.toggleAutoRead();await p.keepScreenTail;
    assert.deepEqual(controls.at(-1),['keepScreen',true]);
    p.stopAutoRead('pause');await p.keepScreenTail;assert.deepEqual(controls.at(-1),['keepScreen',false]);
  });
  await test('RTL seek maps stored page to correct display index',async()=>{
    controls.length=0;const p=page();p.seekPage(2);
    assert.equal(p.currentPage,2);assert.deepEqual(controls.at(-1),['swiper',0]);assert.equal(p.zoomed,false);
  });
  await test('continuous seek uses scroller rather than swiper',async()=>{
    controls.length=0;const p=page();p.mode='continuousRightToLeft';p.seekPage(1);
    assert.deepEqual(controls.at(-1),['list',1]);
  });
  await test('invalid seek never overwrites reading position',async()=>{
    const p=page();p.seekPage(-1);p.seekPage(99);assert.equal(p.currentPage,0);
  });
  await test('auto reading advances canonical page order',async()=>{
    const p=page();p.toggleAutoRead();await p.autoStep();
    assert.equal(p.currentPage,1);assert.equal(p.autoReading,true);p.stopAutoRead('test');
  });
  await test('all seven modes use seconds-based 100ms to 10s delays with finite fallback and clamping',async()=>{
    const modes=['galleryRightToLeft','galleryLeftToRight','galleryTopToBottom','waterfallTopToBottom',
      'continuousTopToBottom','continuousLeftToRight','continuousRightToLeft'];
    for(const mode of modes) for(const [interval,delay] of [[0.1,100],[1.7,1700],[10,10000],[0,100],[50,10000],[NaN,5000]]) {
      const p=page();p.mode=mode;p.options.autoPageTurningInterval=interval;p.toggleAutoRead();
      assert.equal(p.autoReading,true,mode);assert.equal(timerDelays.at(-1),delay,mode);
      p.stopAutoRead('fixture');await p.keepScreenTail;
    }
  });
  await test('continuous turns scroll exactly one viewport in the correct axis/direction without inventing a page',async()=>{
    for(const [mode,x,y] of [['waterfallTopToBottom',0,900],['continuousTopToBottom',0,900],
      ['continuousLeftToRight',600,0],['continuousRightToLeft',-600,0]]) {
      const p=page();p.mode=mode;p.viewportWidth=600;p.viewportHeight=900;controls.length=0;
      p.turnReaderViewport(1);assert.deepEqual(controls.at(-1),['scrollBy',x,y],mode);
      assert.equal(p.currentPage,0,'only visibility callbacks advance the stored position');
    }
  });
  await test('auto reading is paused while zoomed or loading',async()=>{
    const p=page();p.toggleAutoRead();p.zoomed=true;await p.autoStep();assert.equal(p.currentPage,0);
    p.zoomed=false;p.loading=true;await p.autoStep();assert.equal(p.currentPage,0);p.stopAutoRead('test');
  });
  await test('last chapter end stops timer',async()=>{
    const p=page();p.currentPage=2;p.onImageReady(2,p.renderGeneration,true);p.toggleAutoRead();await p.autoStep();
    assert.equal(p.autoReading,false);assert.equal(timers.size,0);
  });
  await test('background lifecycle stops automatic page changes',async()=>{
    const p=page();p.toggleAutoRead();p.onPageHide();await p.autoStep();
    assert.equal(p.autoReading,false);assert.equal(p.currentPage,0);assert.equal(timers.size,0);
  });
  await test('reader images explicitly use page hooks and zoom gesture support',async()=>{
    assert.equal((raw.match(/thumbnail: false/g)||[]).length,2);
    assert.equal((raw.match(/zoomEnabled: true/g)||[]).length,2);
    assert.match(raw,/\.disableSwipe\(this\.zoomed\)/);
    assert.match(raw,/\.enableScrollInteraction\(!this\.zoomed\)/);
    const images=read('entry/src/main/ets/components/ComicWidgets.ets');
    assert.match(images,/GestureType\.PAN_GESTURE && this\.scaleValue <= 1/);
    assert.match(images,/version !== this\.requestVersion/);
  });
  await test('window brightness override is restored on page hide',async()=>{
    controls.length=0;const p=page();p.cycleBrightness();await p.brightnessTail;
    assert.equal(p.readerBrightness,0.35);p.onPageHide();await p.brightnessTail;
    assert.equal(p.readerBrightness,-1);assert.deepEqual(controls,[['brightness',0.35],['brightness',0.55]]);
  });
  console.log(`PASS ${count} reader auto/seek/zoom lifecycle cases (not device pinch/drag acceptance).`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
