'use strict';
// Real ReaderPage + ReaderClickZones against deterministic UI fakes only.
// Behaviour targets the default nine-zone reading contract of the pinned public
// reference (Luoyacheng/legado-E 8b87c5a); destination UI is our own.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/legado-interaction-20261023');fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const rawReader=read('entry/src/main/ets/pages/ReaderPage.ets'),reader=(rawReader.slice(0,rawReader.indexOf('  @Builder'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct ReaderPage','class ReaderPage');
const options=read('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
let now=1000,sequence=0,timers=new Map(),calls=[],saves=[],scrollerState={x:0,y:0,atEnd:false};
const c=vm.createContext({Date:class extends Date{static now(){return now}},setTimeout:(fn,delay)=>{const id=++sequence;timers.set(id,{fn,at:now+delay});return id},clearTimeout:id=>timers.delete(id),setInterval:()=>1,clearInterval(){},
 SwiperController:class{changeIndex(i){calls.push(['swiper',i])}},Scroller:class{scrollToIndex(i,animate,align){calls.push(['list',i,align])}currentOffset(){return {xOffset:scrollerState.x,yOffset:scrollerState.y}}isAtEnd(){return scrollerState.atEnd}scrollBy(x,y){calls.push(['scrollBy',x,y]);scrollerState.x+=x;scrollerState.y+=y}},
 History:class{},ComicType:{fromKey:()=>({value:1})},HistoryDao:{save:async h=>saves.push(h)},ImageFit:{Cover:0},ImageRequestConfig:class{},ImageLoader:{cancelOwned(){}},ReaderSettings:{},AppContext:{context:{},ensureInitialized(){}},
 ReaderWindowChrome:class{enter(){calls.push(['window-enter']);return Promise.resolve()}leave(){calls.push(['window-leave']);return Promise.resolve()}},
 router:{getParams:()=>({}),back:()=>calls.push(['back'])},Log:{audit(){},warn(){},error(){}},promptAction:{showToast(){}},TouchType:{Down:0,Move:1,Up:2,Cancel:3},px2vp:v=>v,batteryInfo:{batterySOC:100},ScrollAlign:{START:0,END:1}});
const helpers=['ReaderTapPolicy','ReaderGesturePolicy','ReaderModes','ReaderSpreads','ReaderRenderSource','ReaderVolumeKeys','ReaderWorkload','ReadingPosition','ReaderImageLayout'].map(n=>read('entry/src/main/ets/features/'+n+'.ets')).join('\n');
const zones=read('entry/src/main/ets/components/ReaderClickZones.ets');
const rawImage=read('entry/src/main/ets/components/ComicWidgets.ets'),image=(rawImage.slice(0,rawImage.indexOf('  build() {'))+'}').replace(/@(?:Entry|Component|State|Prop)\s*|@Watch\('[^']+'\)\s*/g,'').replace('struct AsyncComicImage','class AsyncComicImage');
vm.runInContext(stripTypeScriptTypes(helpers+'\n'+zones+'\n'+options+'\n'+reader+'\n'+image,{mode:'transform'})+'\nglobalThis.Reader=ReaderPage;globalThis.Picture=AsyncComicImage;globalThis.Zones=ReaderClickZones;globalThis.Gesture=ReaderCanvasGesture;',c,{timeout:1000});
function tick(ms){now+=ms;for(const [id,t]of [...timers])if(t.at<=now){timers.delete(id);t.fn()}}
function ready(p){const indices=p.mode.startsWith('gallery')?p.displaySpreads[p.sourceToDisplay(p.currentPage)].imageIndices:[p.currentPage];for(const i of indices)p.onImageReady(i,p.renderGeneration,true)}
function page(mode='galleryLeftToRight',count=1){calls=[];saves=[];timers.clear();scrollerState={x:0,y:0,atEnd:false};
 const p=new c.Reader();p.mode=mode;p.images=['a','b','c','d','e','f','g'];p.chapterIds=['ch','ch2'];p.epId='ch';p.sourceKey='source';p.comicId='comic';p.title='Title';
 p.loading=false;p.progressReady=true;p.visible=true;p.viewportWidth=400;p.viewportHeight=800;p.viewportTop=0;p.viewportLeft=0;
 p.options.readerScreenPicNumberForPortrait=count;p.rebuildPresentation();ready(p);return p}
let count=0,finished=false;const results=[];
async function test(name,fn){let timer;try{await Promise.race([Promise.resolve().then(fn),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),3000)})]);count++;results.push({name,pass:true});console.log('PASS '+name)}finally{clearTimeout(timer)}}
process.on('beforeExit',()=>{if(!finished){console.error('READER_IMMERSIVE_INCOMPLETE count='+count);process.exitCode=1}});
const Z=c.Zones;
(async()=>{
 await test('default nine-zone map matches the reference defaults exactly',()=>{
  const at=(x,y)=>Z.action(x,y,true,false,false);
  assert.deepEqual([at(.1,.1),at(.5,.1),at(.9,.1)],['previous','previous','next']);
  assert.deepEqual([at(.1,.5),at(.5,.5),at(.9,.5)],['previous','menu','next']);
  assert.deepEqual([at(.1,.9),at(.5,.9),at(.9,.9)],['previous','next','next']);
 });
 await test('zone boundaries are one-third of the viewport with no overlap quirk',()=>{
  assert.equal(Z.action(.3299,.5,true,false,false),'previous');
  assert.equal(Z.action(.33,.5,true,false,false),'menu');
  assert.equal(Z.action(.6599,.5,true,false,false),'menu');
  assert.equal(Z.action(.66,.5,true,false,false),'next');
  assert.equal(Z.action(.5,.3299,true,false,false),'previous');
  assert.equal(Z.action(.5,.66,true,false,false),'next');
 });
 await test('right-to-left mirrors turn columns but keeps the centre menu column',()=>{
  assert.equal(Z.action(.1,.5,true,true,false),'next');
  assert.equal(Z.action(.9,.5,true,true,false),'previous');
  assert.equal(Z.action(.1,.1,true,true,false),'next');
  assert.equal(Z.action(.5,.5,true,true,false),'menu');
  assert.equal(Z.action(.5,.9,true,true,false),'next');
 });
 await test('reverse preference flips turn direction without moving the menu zone',()=>{
  assert.equal(Z.action(.9,.5,true,false,true),'previous');
  assert.equal(Z.action(.1,.5,true,false,true),'next');
  assert.equal(Z.action(.5,.5,true,false,true),'menu');
 });
 await test('turning disabled still allows the centre menu and rejects offscreen input',()=>{
  assert.equal(Z.action(.5,.5,false,false,false),'menu');
  assert.equal(Z.action(.9,.5,false,false,false),'none');
  for(const pair of [[NaN,.5],[.5,NaN],[-.01,.5],[1,.5],[.5,-.01],[.5,1]])assert.equal(Z.action(pair[0],pair[1],true,false,false),'none');
 });
 await test('fresh reader starts with the menu hidden and no chapter sheet',()=>{
  const p=page();assert.equal(p.toolbarVisible,false);assert.equal(p.showChapters,false);
  assert.doesNotMatch(rawReader,/\btopBar\(\)/);assert.doesNotMatch(rawReader,/Text\('显示工具栏'\)/);
 });
 await test('centre tap reveals the menu and never turns a page',()=>{
  const p=page();p.onReaderViewportTap(.5,.5);assert.equal(p.toolbarVisible,true);assert.equal(p.currentPage,0);assert.deepEqual(calls,[]);
 });
 await test('menu open consumes a body tap: closes only, no page turn',()=>{
  for(const [x,y]of [[.9,.5],[.1,.5],[.9,.9]]){const p=page();p.toolbarVisible=true;p.onReaderViewportTap(x,y);
   assert.equal(p.toolbarVisible,false);assert.equal(p.currentPage,0);assert.deepEqual(calls,[]);assert.equal(saves.length,0)}
 });
 await test('transition guard blocks a second tap from instantly reopening the menu',()=>{
  const p=page();p.toolbarVisible=true;p.onReaderViewportTap(.5,.5);assert.equal(p.toolbarVisible,false);
  p.onReaderViewportTap(.5,.5);assert.equal(p.toolbarVisible,false);
  tick(200);p.onReaderViewportTap(.5,.5);assert.equal(p.toolbarVisible,true);
 });
 await test('side taps turn exactly one page in every mode when the menu is hidden',()=>{
  for(const mode of ['galleryLeftToRight','galleryTopToBottom']){const p=page(mode,1);p.onReaderViewportTap(.9,.5);
   assert.equal(p.currentPage,1,mode);assert.equal(calls.at(-1)[0],mode.startsWith('gallery')?'swiper':'list')}
 });
 await test('top row turns previous while the bottom centre advances',()=>{
  const p=page('galleryLeftToRight',1);p.currentPage=3;ready(p);p.onReaderViewportTap(.1,.1);assert.equal(p.currentPage,2);
  ready(p);p.onReaderViewportTap(.5,.9);assert.equal(p.currentPage,3);
 });
 await test('continuous modes scroll one visible screen instead of one whole long image',()=>{
  const p=page('continuousTopToBottom');p.onReaderViewportTap(.9,.5);
  assert.deepEqual(calls.at(-1),['scrollBy',0,800]);assert.equal(p.currentPage,0);
  const q=page('continuousTopToBottom');scrollerState.y=1600;q.onReaderViewportTap(.5,.1);
  assert.deepEqual(calls.at(-1),['scrollBy',0,-800]);
 });
 await test('scrolling at the top edge switches chapter instead of overscrolling',()=>{
  const p=page('continuousTopToBottom');p.chapterIds=['previous','ch','ch2'];scrollerState={x:0,y:0,atEnd:false};
  let switched=false;p.switchChapter=()=>{switched=true};
  p.onReaderViewportTap(.1,.5);assert.equal(switched,true);
 });
 await test('scrolling at the end switches chapter while mid-scroll still scrolls',()=>{
  const p=page('continuousTopToBottom');scrollerState={x:0,y:400,atEnd:true};
  let switched=0;p.switchChapter=offset=>{switched=offset};
  p.onReaderViewportTap(.9,.5);assert.equal(switched,1);
  scrollerState={x:0,y:400,atEnd:false};calls=[];p.onReaderViewportTap(.9,.5);assert.equal(calls.at(-1)[0],'scrollBy');
 });
 await test('menu is reachable in blank or loading states but paging is gated',()=>{
  const p=page();p.readyImages.clear();p.onReaderViewportTap(.5,.5);assert.equal(p.toolbarVisible,true,'menu needs no loaded image');
  const q=page();q.readyImages.clear();q.onReaderViewportTap(.9,.5);assert.equal(q.currentPage,0,'turn needs readiness');
  const r=page();r.loading=true;r.onReaderViewportTap(.5,.5);assert.equal(r.toolbarVisible,true);
  const s=page();s.loading=true;s.onReaderViewportTap(.9,.5);assert.equal(s.currentPage,0);
 });
 await test('manual scrolling, zoom, layout and chapter sheet suppress zone actions',()=>{
  for(const [key,value]of [['scrolling',true],['layoutPending',true],['showChapters',true]]){const p=page();p[key]=value;p.onReaderViewportTap(.9,.5);assert.equal(p.currentPage,0,key)}
  const z=page();z.zoomed=true;z.onReaderViewportTap(.9,.5);assert.equal(z.currentPage,0);z.onReaderViewportTap(.5,.5);assert.equal(z.toolbarVisible,true);
  const hidden=page();hidden.visible=false;hidden.onReaderViewportTap(.5,.5);assert.equal(hidden.toolbarVisible,false);
 });
 await test('surface touch delivers one delayed tap in viewport coordinates',()=>{
  const p=page();const ev=(type,x,y,touches=1)=>({type,touches:type===2?[]:[{windowX:x,windowY:y}],changedTouches:type===2?[{windowX:x,windowY:y}]:[]});
  p.onReaderSurfaceTouch(ev(0,200,400));p.onReaderSurfaceTouch(ev(2,200,400));assert.equal(p.toolbarVisible,false);
  tick(349);assert.equal(p.toolbarVisible,false);tick(1);assert.equal(p.toolbarVisible,true);
 });
 await test('surface touch ignores drags, multi-touch, menu-open and animation guards',()=>{
  const ev=(type,x,y,touches=1)=>({type,touches:type===2?[]:Array.from({length:touches},()=>({windowX:x,windowY:y})),changedTouches:type===2?[{windowX:x,windowY:y}]:[]});
  const drag=page();drag.onReaderSurfaceTouch(ev(0,200,400));drag.onReaderSurfaceTouch({type:1,touches:[{windowX:260,windowY:400}],changedTouches:[]});drag.onReaderSurfaceTouch(ev(2,260,400));tick(400);assert.equal(drag.toolbarVisible,false);
  const pinch=page();pinch.onReaderSurfaceTouch(ev(0,200,400,2));pinch.onReaderSurfaceTouch(ev(2,200,400));tick(400);assert.equal(pinch.toolbarVisible,false);
  const open=page();open.toolbarVisible=true;open.onReaderSurfaceTouch(ev(0,200,400));open.onReaderSurfaceTouch(ev(2,200,400));tick(400);assert.equal(open.toolbarVisible,true);
  const cancelled=page();cancelled.onReaderSurfaceTouch(ev(0,200,400));cancelled.onReaderSurfaceTouch({type:3,touches:[],changedTouches:[]});tick(400);assert.equal(cancelled.toolbarVisible,false);
 });
 await test('a rapid second contact is not treated as a page or menu tap',()=>{
  const g=new c.Gesture();g.begin(200,400,1000,1);assert.equal(g.end(200,400,1030,0),true);
  g.begin(202,402,1100,1);assert.equal(g.end(202,402,1130,0),false);
  g.begin(202,402,1600,1);assert.equal(g.end(202,402,1630,0),true);
 });
 await test('long press duration and stale timestamps never become taps',()=>{
  const g=new c.Gesture();g.begin(200,400,1000,1);assert.equal(g.end(200,400,1600,0),false);
  const h=new c.Gesture();h.begin(200,400,2000,1);assert.equal(h.end(200,400,1990,0),false);
  const i=new c.Gesture();i.begin(NaN,400,2000,1);assert.equal(i.end(NaN,400,2010,0),false);
 });
 await test('dismiss and reveal cancel pending timers so no stale action fires',()=>{
  const ev=(type,x,y)=>({type,touches:type===2?[]:[{windowX:x,windowY:y}],changedTouches:type===2?[{windowX:x,windowY:y}]:[]});
  const p=page();p.onReaderSurfaceTouch(ev(0,200,400));p.onReaderSurfaceTouch(ev(2,200,400));p.dismissReaderMenu();tick(400);assert.equal(p.toolbarVisible,false);
  const q=page();q.showChapters=true;q.showChapters=false;q.revealReaderMenu();assert.equal(q.toolbarVisible,true);
 });
 await test('back closes menu or chapter sheet first, then stops auto reading',()=>{
  const p=page();p.showChapters=true;assert.equal(p.onBackPress(),true);assert.equal(p.showChapters,false);
  p.toolbarVisible=true;assert.equal(p.onBackPress(),true);assert.equal(p.toolbarVisible,false);
  p.autoReading=true;assert.equal(p.onBackPress(),true);assert.equal(p.autoReading,false);
  assert.equal(p.onBackPress(),false);
 });
 await test('opening the menu pauses auto-step and closing resumes the same intent',async()=>{
  const p=page('continuousTopToBottom');p.autoReading=true;p.toolbarVisible=true;calls=[];
  await p.autoStep();assert.deepEqual(calls,[],'menu visible must pause auto');
  p.toolbarVisible=false;await p.autoStep();assert.equal(calls.length>0,true,'hidden menu resumes auto');
  assert.equal(p.autoReading,true);
 });
 await test('chapter sheet opens from the menu and closes without restoring the menu',()=>{
  const p=page();p.revealReaderMenu();p.openReaderChapterMenu();assert.equal(p.showChapters,true);assert.equal(p.toolbarVisible,false);
  p.onBackPress();assert.equal(p.showChapters,false);assert.equal(p.toolbarVisible,false);
 });
 await test('show and hide never reset image identity, generation, zoom or readiness',()=>{
  const p=page(),generation=p.renderGeneration,zoom=p.zoomReset,source=p.spreadSource,images=p.images,readyCount=p.readyImages.size;
  p.revealReaderMenu();p.dismissReaderMenu();p.revealReaderMenu();
  assert.equal(p.renderGeneration,generation);assert.equal(p.zoomReset,zoom);assert.strictEqual(p.spreadSource,source);
  assert.strictEqual(p.images,images);assert.equal(p.readyImages.size,readyCount);assert.equal(saves.length,0);
 });
 await test('canvas is a fullscreen sibling and the menu overlay consumes outside taps',()=>{
  const build=rawReader.slice(rawReader.lastIndexOf('  build() {'));
  assert.match(build,/onReaderSurfaceTouch/);assert.match(build,/height\('100%'\)\.backgroundColor\(Color\.Black\)/);
  assert.match(build,/hitTestBehavior\(HitTestMode\.Block\)\.onClick\(\(\) => \{ this\.dismissReaderMenu\(\); \}\)/);
  assert.match(build,/if \(this\.toolbarVisible && !this\.showChapters\)/);assert.match(build,/expandSafeArea/);
  const canvas=build.slice(build.indexOf('      Column()'),build.indexOf("}.width('100%').height('100%').backgroundColor(Color.Black)"));
  assert.doesNotMatch(canvas,/bottomBar|topBar|toolbarVisible/);
 });
 await test('images no longer dispatch their own single tap; native zoom stays enabled',()=>{
  assert.doesNotMatch(rawReader,/onSingleTap:/);assert.doesNotMatch(rawReader,/menuTapWhenZoomed/);
  assert.equal((rawReader.match(/singleTapEnabled: false/g)||[]).length,2);
  assert.equal((rawReader.match(/zoomEnabled: true/g)||[]).length,2);
  assert.equal((rawReader.match(/doubleTapZoomEnabled: this\.options\.enableDoubleTapToZoom/g)||[]).length,2);
 });
 await test('user-requested reader bottom panel contains navigation, settings, mode, speed and details',()=>{
  const panel=rawReader.slice(rawReader.indexOf('  bottomBar()'),rawReader.indexOf('  flowImage('));
  for(const call of ['returnToPrevious','switchChapter','openReaderSettings','openComicDetails','openAutoSpeedMenu','showModeMenu = true','setBrightnessValue'])assert.ok(panel.includes(call),call);
 assert.match(panel,/TransitionEffect\.move\(TransitionEdge\.BOTTOM\)/);
  assert.match(panel,/openReaderChapterMenu/);
 });
 await test('settings explain the nine-zone contract and drop the dead region slider',()=>{
  const settings=read('entry/src/main/ets/pages/ReaderSettingsPage.ets');
  assert.match(settings,/已隐藏|进入正文时菜单隐藏/);assert.match(settings,/九宫格/);
  assert.doesNotMatch(settings,/sliderOption\('左右翻页区域/);assert.doesNotMatch(settings,/choiceOption\('中间点击'/);
 });
 await test('page exit clears pending taps, hides chrome and releases its actual UI owner',async()=>{
  const p=page();p.enterReaderFullscreen();await Promise.resolve();p.toolbarVisible=true;p.visible=false;p.releaseReaderControls();
  assert.equal(p.toolbarVisible,false);assert.ok(calls.some(row=>row[0]==='window-enter'));assert.ok(calls.some(row=>row[0]==='window-leave'));
 });
 await test('viewport resize rejects an already queued tap rather than using old coordinates',()=>{
  const p=page();const ev=type=>({type,touches:type===2?[]:[{windowX:200,windowY:400}],changedTouches:type===2?[{windowX:200,windowY:400}]:[]});
  p.onReaderSurfaceTouch(ev(0));p.onReaderSurfaceTouch(ev(2));assert.ok(p.canvasTapTimer>=0);
  p.viewportWidth=800;tick(400);assert.equal(p.toolbarVisible,false);assert.deepEqual(calls,[]);
 });
 const touch=(type,x=200,y=400,id=1,others=[])=>{
  const point={id,type,windowX:x,windowY:y};
  return {type,touches:[point,...others],changedTouches:[point]};
 };
 await test('native Up still containing the released finger is recognized as a single tap',()=>{
  const p=page();p.onReaderSurfaceTouch(touch(0));p.onReaderSurfaceTouch(touch(2));tick(400);
  assert.equal(p.toolbarVisible,true);assert.equal(p.currentPage,0);
 });
 await test('Up with another still-held ID is rejected even when all native types equal Up',()=>{
  const p=page();p.onReaderSurfaceTouch(touch(0));
  p.onReaderSurfaceTouch(touch(2,200,400,1,[{id:2,type:2,windowX:240,windowY:400}]));tick(400);
  assert.equal(p.toolbarVisible,false);assert.equal(p.currentPage,0);
 });
 await test('tiny release jitter across a zone boundary still uses the original Down zone',()=>{
  const p=page();p.onReaderSurfaceTouch(touch(0,134,400));p.onReaderSurfaceTouch(touch(2,131,400));tick(400);
  assert.equal(p.toolbarVisible,true);assert.equal(p.currentPage,0);
 });
 await test('native image double-tap always cancels parent singles for zoom in, zoom out and zoom-disabled',()=>{
  for(const state of [1,2,0]){
   const p=page(),q=new c.Picture();q.pixelMap={};q.zoomEnabled=true;q.doubleTapZoomEnabled=state!==0;q.scaleValue=state===2?2:1;
   q.onReaderDoubleTap=()=>p.cancelCanvasTap();q.onZoomChanged=value=>p.onImageZoom(0,p.zoomReset,value);
   const x=state===2?360:200;p.onReaderSurfaceTouch(touch(0,x));p.onReaderSurfaceTouch(touch(2,x));
   assert.ok(p.canvasTapTimer>=0);q.handleDoubleTap();tick(400);
   assert.equal(p.toolbarVisible,false);assert.equal(p.currentPage,0);assert.equal(q.scaleValue,state===1?2:1);
  }
 });
 await test('two native-style contacts 40vp apart are not reinterpreted as a menu tap',()=>{
  const p=page();p.onReaderSurfaceTouch(touch(0,200));p.onReaderSurfaceTouch(touch(2,200));tick(100);
  p.onReaderSurfaceTouch(touch(0,240));p.onReaderSurfaceTouch(touch(2,240));tick(400);
  assert.equal(p.toolbarVisible,false);assert.equal(p.currentPage,0);
 });
 await test('geometry invalidation while the finger is held cancels the contact itself',()=>{
  const p=page();p.onReaderSurfaceTouch(touch(0));p.cancelCanvasTap();p.viewportWidth=800;
  p.onReaderSurfaceTouch(touch(2));tick(400);assert.equal(p.toolbarVisible,false);assert.deepEqual(calls,[]);
 });
 await test('zoom/load generation changes between Down and Up cannot be absorbed as a new tap',()=>{
  for(const field of ['zoomReset','loadVersion']){const p=page();p.onReaderSurfaceTouch(touch(0));p[field]++;
   p.onReaderSurfaceTouch(touch(2));tick(400);assert.equal(p.toolbarVisible,false,field);assert.equal(p.currentPage,0)}
 });
 await test('retry control consumes a queued canvas tap and only retries loading',()=>{
  const p=page();p.load=()=>calls.push(['retry']);p.onReaderSurfaceTouch(touch(0));p.onReaderSurfaceTouch(touch(2));
  p.retryReaderContent();tick(400);assert.deepEqual(calls,[['retry']]);assert.equal(p.toolbarVisible,false);
 });
 await test('volume callback cannot page behind a modal toolbar or stop auto-reading there',()=>{
  const p=page();p.syncVolumeKeys();p.toolbarVisible=true;p.autoReading=true;p.volumeKeys.turn(1);
  assert.equal(p.currentPage,0);assert.equal(p.autoReading,true);p.toolbarVisible=false;p.volumeKeys.turn(1);assert.equal(p.currentPage,1);
 });
 await test('page-level previous chapter lands on last source image and stale loads cannot seek',async()=>{
  for(const mode of ['galleryLeftToRight','galleryRightToLeft','continuousTopToBottom']){
   const p=page(mode);p.chapterIds=['previous','ch'];p.switchChapter=async()=>{p.loadVersion++;p.epId='previous';p.images=['x','y','z'];p.currentPage=0;p.rebuildPresentation()};
   await p.turnReaderChapter(-1);assert.equal(p.currentPage,2,mode);
   if(mode==='continuousTopToBottom')assert.deepEqual(calls.at(-1),['list',2,1]);
  }
  const q=page();q.chapterIds=['previous','ch'];q.switchChapter=async()=>{q.loadVersion+=2;q.epId='previous'};
  await q.turnReaderChapter(-1);assert.equal(q.currentPage,0);
 });
 await test('previous long chapter retains END after image-height changes until next user contact',async()=>{
  const p=page('continuousTopToBottom');p.chapterIds=['previous','ch'];
  p.switchChapter=async()=>{p.loadVersion++;p.epId='previous';p.images=['x','y'];p.rebuildPresentation()};
  await p.turnReaderChapter(-1);p.layoutPending=true;p.alignPreviousChapterEnd();
  assert.equal(p.layoutPending,false);assert.deepEqual(calls.at(-1),['list',1,1]);
  p.onReaderSurfaceTouch(touch(0));const before=calls.length;p.alignPreviousChapterEnd();assert.equal(calls.length,before);
 });
 await test('menu stays visible while idle and hiding never starts disabled auto-reading',async()=>{
  const p=page();p.revealReaderMenu();tick(20000);assert.equal(p.toolbarVisible,true);assert.equal(p.autoReading,false);
  p.dismissReaderMenu();await p.autoStep();assert.equal(p.autoReading,false);assert.deepEqual(calls,[]);
 });
 assert.equal(count,43);finished=true;
 fs.writeFileSync(path.join(folder,'reader-cases.json'),JSON.stringify({cases:count,results,scope:'real production ReaderPage/ReaderClickZones methods with UI fakes; no phone'},null,2));
 console.log('PASS 43 nine-zone reader menu/paging/gesture/identity contracts; no device/install');
})().catch(error=>{console.error(error);process.exitCode=1});
