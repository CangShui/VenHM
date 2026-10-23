'use strict';
/** Local production-method + render-contract regression. Does not emulate ArkUI rendering or run SDK/device/network. */
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const raw=read('entry/src/main/ets/pages/ReaderPage.ets');
const reader=(raw.slice(0,raw.indexOf('  @Builder'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct ReaderPage','class ReaderPage');
let now=1000,seq=0,tasks=new Map(),saves=[],calls=[],failures=0,count=0;
const ctx=vm.createContext({Date:class extends Date{static now(){return now;}},
 setTimeout:(fn,delay)=>{const id=++seq;tasks.set(id,{fn,at:now+delay});return id;},clearTimeout:id=>tasks.delete(id),
 setInterval:()=>1,clearInterval(){},SwiperController:class{changeIndex(i){calls.push(['swiper',i]);}},
 Scroller:class{scrollToIndex(i){calls.push(['list',i]);}},ScrollAlign:{START:0},History:class{},
 HistoryDao:{save:async h=>{saves.push(h);}},ComicType:{fromKey:()=>({value:1})},
 Log:{audit(){},warn(){},error(){}},promptAction:{showToast(){}},ReaderSettings:{},AppContext:{context:{}}
});
const helperPath='entry/src/main/ets/features/ReaderRenderSource.ets';
const helpers=['ReaderModes','ReaderSpreads','ReadingPosition','ReaderTapPolicy'].map(n=>read(`entry/src/main/ets/features/${n}.ets`)).join('\n')+
 (fs.existsSync(path.join(root,helperPath))?'\n'+read(helperPath):'');
const options=read('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
vm.runInContext(stripTypeScriptTypes(helpers+'\n'+options+'\n'+reader,{mode:'transform'})+'\nglobalThis.Reader=ReaderPage;',ctx);
function tick(ms){now+=ms;for(const [id,t] of Array.from(tasks))if(t.at<=now){tasks.delete(id);t.fn();}}
function page(n=1000,mode='galleryLeftToRight',size=1){tasks.clear();saves=[];calls=[];const p=new ctx.Reader();
 p.loading=false;p.progressReady=true;p.mode=mode;p.epId='ch';p.chapterIds=['ch','next'];p.sourceKey='s';p.comicId='c';
 p.images=Array.from({length:n},(_,i)=>`page-${i}`);p.options.readerScreenPicNumberForPortrait=size;p.rebuildPresentation();return p;}
function test(name,fn){try{fn();count++;console.log('PASS '+name);}catch(e){failures++;console.error('FAIL '+name+': '+e.message);}}
test('List and Swiper lazily construct pages with one-neighbor cache, never chapter-wide ForEach',()=>{
 const list=raw.slice(raw.indexOf('  continuousList()'),raw.indexOf('  galleryImage('));
 const swiper=raw.slice(raw.indexOf('  gallerySwiper()'),raw.indexOf('  build()'));
 assert.match(list,/LazyForEach\(this\.flowSource/);assert.match(swiper,/LazyForEach\(this\.spreadSource/);
 assert.match(list,/\.cachedCount\(1\)/);assert.match(swiper,/\.cachedCount\(1\)/);
 assert.doesNotMatch(raw,/ForEach\(this\.display(?:Images|Spreads)/);
 assert.doesNotMatch(swiper,/\.lazy\(/,'Swiper API21 uses LazyForEach, not invented .lazy API');
});
test('500/1000-page source is persistent, indexed, and demand window starts only bounded image tasks',()=>{
 for(const n of [500,1000])for(const size of [1,3,5]){
  const p=page(n,'galleryRightToLeft',size),source=p.spreadSource;assert.ok(source);
  let requested=0;const index=p.sourceToDisplay(0),items=[];
  for(let i=Math.max(0,index-1);i<=Math.min(source.totalCount()-1,index+1);i++){const item=source.getData(i);requested+=item.spread.imageIndices.length;items.push(item);}
  assert.ok(requested<=3*size);assert.ok(requested<n);assert.equal(source.totalCount(),Math.ceil(n/size));
  const identity=items[0];p.seekPage(size);assert.equal(p.spreadSource,source);assert.equal(source.getData(Math.max(0,index-1)),identity);
 }
 const p=page(1000,'waterfallTopToBottom');assert.equal(p.flowSource.totalCount(),1000);
 const window=[10,11,12].map(i=>p.flowSource.getData(i));assert.equal(window.length,3);
 assert.equal(window[1].actual,11);assert.equal(window[1].url,'page-11');
});
test('page flip resets transforms but not keyed image identity/readiness nor requests; chapter resets source identity',()=>{
 const p=page();const s=p.spreadSource;const first=s.getData(0),generation=p.renderGeneration;
 p.onImageReady(1,generation,true);p.seekPage(1);assert.equal(s.getData(0),first);assert.ok(p.readyImages.has(1));
 assert.equal(p.renderGeneration,generation);assert.ok(p.zoomReset>1);
 p.epId='next';p.rebuildPresentation();assert.notEqual(p.spreadSource.getData(0).key,first.key);
 assert.notEqual(p.renderGeneration,generation);assert.equal(p.readyImages.size,0);
 p.onImageReady(1,generation,true);assert.equal(p.readyImages.size,0);
});
test('rotation/regroup preserves canonical source anchor, RTL grouping, and unchanged flow identity',()=>{
 const p=page(1000,'galleryRightToLeft',2);p.seekPage(723);const src=p.spreadSource;
 p.options.readerScreenPicNumberForLandscape=5;p.landscape=true;p.relayout();assert.equal(p.currentPage,723);
 const spread=src.getData(p.sourceToDisplay(723)).spread;assert.ok(spread.imageIndices.includes(723));
 assert.deepEqual(Array.from(spread.imageIndices),[724,723,722,721,720]);
 const f=page(1000,'waterfallTopToBottom'),row=f.flowSource.getData(500);f.landscape=true;f.relayout();
 assert.equal(f.flowSource.getData(500),row);assert.equal(f.flowSource.getData(500).key,row.key);
});
test('progress is coalesced off callback stack, latest source page/duration flushes at timer and final hide',()=>{
 const p=page();p.clock.start(now);for(let i=1;i<100;i++)p.seekPage(i);
 assert.equal(saves.length,0,'no disk persistence from page-turn stack');assert.equal(tasks.size,1,'one pending progress flush');
 tick(1000);assert.equal(saves.length,1);assert.equal(saves[0].page,100);assert.equal(saves[0].readDurationMs,1000);
 p.seekPage(500);tick(25);p.onPageHide();assert.equal(saves.length,2);assert.equal(saves[1].page,501);assert.equal(saves[1].readDurationMs,25);
 tick(2000);assert.equal(saves.length,2,'no stale pending write after hide');
});
test('chapter-switch forced flush preserves outgoing chapter even with a pending timer',()=>{
 const p=page();p.clock.start(now);p.seekPage(20);tick(10);p.saveProgress(true);
 assert.equal(saves.length,1);assert.equal(saves[0].epId,'ch');assert.equal(saves[0].page,21);
 p.epId='next';p.currentPage=0;p.rebuildPresentation();p.clock.start(now);p.saveProgress();tick(1000);
 assert.equal(saves.length,2);assert.equal(saves[1].epId,'next');assert.equal(saves[1].page,1);assert.equal(saves[1].readDurationMs,1000);
});
console.log(`${count} passed, ${failures} failed; bounded demand simulation + production render contracts, not device mount measurement.`);
if(failures)process.exitCode=1;
