'use strict';
// Production reader/preferences/history/logging, deterministic SDK fakes only.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');const clean=f=>read(f).replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const raw=read('entry/src/main/ets/pages/ReaderPage.ets');const reader=(clean('entry/src/main/ets/pages/ReaderPage.ets').split('  @Builder')[0]+'}').replace(/@(?:Entry|Component|State)\s*/g,'').replace('struct ReaderPage','class ReaderPage');
function env(initial={}){
 const prefs=new Map(Object.entries(initial)),writes=[],intervals=new Map(),actions=[],timeouts=new Map();let sequence=0,fail=false,now=1000;
 const c=vm.createContext({Promise,Map,Set,Math,Number,Date:class extends Date{static now(){return now}},
  Settings:{getString:(k,f)=>typeof prefs.get(k)==='string'?prefs.get(k):f,getInt:(k,f)=>typeof prefs.get(k)==='number'?Math.trunc(prefs.get(k)):f,
   getBool:(k,f)=>typeof prefs.get(k)==='boolean'?prefs.get(k):f,setString:async(k,v)=>{if(fail){fail=false;throw Error('fixture-write-failure')}writes.push([k,v]);prefs.set(k,v)}},
  setInterval:(fn,delay)=>{const id=++sequence;intervals.set(id,{fn,delay});return id},clearInterval:id=>intervals.delete(id),
  setTimeout:(fn,delay)=>{const id=++sequence;timeouts.set(id,{fn,delay});return id},clearTimeout:id=>timeouts.delete(id),
  SwiperController:class{changeIndex(i){actions.push(['swiper',i])}},Scroller:class{scrollToIndex(i){actions.push(['list',i])}currentOffset(){return{xOffset:800,yOffset:1600}}isAtEnd(){return false}scrollBy(x,y){actions.push(['scroll',x,y])}},
  inputConsumer:{on(){},off(){}},KeyCode:{KEYCODE_VOLUME_UP:1,KEYCODE_VOLUME_DOWN:2},
  History:class{},HistoryDao:{save:async h=>actions.push(['history',h])},ComicType:{fromKey:()=>({value:1})},
  AppInit:{init:async()=>{}},AppContext:{context:{}},Log:{audit(){},warn(){},error(){}},promptAction:{showToast(){}},
  window:{getLastWindow:async()=>({getWindowProperties:()=>({brightness:.5,isKeepScreenOn:false}),setWindowBrightness:async()=>{},setWindowKeepScreenOn:async()=>{}})},
  ReaderWindowChrome:class{enter(){return Promise.resolve()}leave(){return Promise.resolve()}},batteryInfo:{batterySOC:99},ScrollAlign:{START:0,END:1},TouchType:{Down:0,Move:1,Up:2,Cancel:3},router:{getParams:()=>({})}});
 const helpers=['ReaderModes','ReaderSpreads','ReaderRenderSource','ReaderVolumeKeys','ReaderWorkload','ReadingPosition','ReaderImageLayout'].map(n=>clean('entry/src/main/ets/features/'+n+'.ets')).join('\n');
 vm.runInContext(stripTypeScriptTypes(helpers+'\n'+clean('entry/src/main/ets/components/ReaderClickZones.ets')+'\n'+clean('entry/src/main/ets/foundation/ReaderSettings.ets')+'\n'+reader,{mode:'transform'})+'\nglobalThis.R=ReaderPage;globalThis.Prefs=ReaderSettings;',c,{timeout:2000});
 const p=new c.R();p.sourceKey='fixture';p.comicId='comic';p.epId='ch';p.chapterIds=['ch'];p.mode='galleryLeftToRight';p.loading=false;p.progressReady=true;p.visible=true;p.images=['a','b','c'];p.viewportWidth=400;p.viewportHeight=800;p.rebuildPresentation();for(let i=0;i<3;i++)p.onImageReady(i,p.renderGeneration,true);
 return{c,p,prefs,writes,intervals,actions,failNext:()=>{fail=true},setNow:n=>{now=n}};
}
let count=0,finished=false;const results=[];async function test(name,fn){let guard;try{await Promise.race([Promise.resolve().then(fn),new Promise((_,reject)=>{guard=setTimeout(()=>reject(Error('WATCHDOG '+name)),5000)})]);count++;results.push({name,pass:true});console.log('PASS '+name)}finally{clearTimeout(guard)}}
process.on('beforeExit',()=>{if(!finished){console.error('READER_SPEED_PRIVACY_INCOMPLETE '+count);process.exitCode=1}});
(async()=>{
 await test('speed popup is a 0.1-to-10s draft slider with endpoints and a separate confirm',()=>{
  const popup=raw.slice(raw.indexOf('  speedMenuOverlay()'),raw.indexOf('  modeMenuOverlay()'));
  assert.match(popup,/Slider\(\{ value: this\.speedDraft, min: 0\.1, max: 10, step: 0\.1 \}\)/);assert.match(popup,/Text\('0\.1s'\)/);assert.match(popup,/Text\('10s'\)/);
  assert.match(popup,/selectAutoSpeed\(this\.speedDraft\)/);assert.doesNotMatch(popup,/ForEach\(\[2, 3, 5/);
  const moving=popup.slice(popup.indexOf('.onChange'),popup.indexOf('Row()',popup.indexOf('.onChange')));assert.doesNotMatch(moving,/setActive|selectAutoSpeed|setInterval/);
 });
 await test('opening or cancelling a speed draft does not start a timer or change preferences',()=>{
  const e=env();e.p.toolbarVisible=true;e.p.openAutoSpeedMenu();e.p.speedDraft=.1;e.p.showSpeedMenu=false;
  assert.equal(e.p.autoReading,false);assert.equal(e.p.options.autoPageTurningInterval,5);assert.equal(e.intervals.size,0);assert.equal(e.writes.length,0);
 });
 await test('confirming 0.1 seconds closes menus and creates exactly a 100ms timer',()=>{
  const e=env();e.p.toolbarVisible=true;e.p.openAutoSpeedMenu();e.p.selectAutoSpeed(.1);
  assert.equal(e.p.toolbarVisible,false);assert.equal(e.p.showSpeedMenu,false);assert.equal(e.p.autoReading,true);assert.equal(e.intervals.size,1);
  assert.equal([...e.intervals.values()][0].delay,100);assert.equal(e.p.options.autoPageTurningInterval,.1);assert.equal(e.writes.length,0);
 });
 await test('applying 10 seconds replaces the old timer, never accumulates timers',()=>{
  const e=env();e.p.selectAutoSpeed(.1);e.p.toolbarVisible=true;e.p.openAutoSpeedMenu();e.p.selectAutoSpeed(10);
  assert.equal(e.intervals.size,1);assert.equal([...e.intervals.values()][0].delay,10000);assert.equal(e.writes.length,0);
 });
 await test('decimal preferences persist without integer truncation and reject illegal precision',async()=>{
  const e=env();await e.c.Prefs.set('global','','','autoPageTurningInterval',.1);assert.equal(e.c.Prefs.resolve('comic','fixture').autoPageTurningInterval,.1);
  await e.c.Prefs.set('global','','','autoPageTurningInterval',1.7);const cold=env(Object.fromEntries(e.prefs));assert.equal(cold.c.Prefs.resolve('comic','fixture').autoPageTurningInterval,1.7);
  for(const bad of [0,10.1,.15,NaN,Infinity])await assert.rejects(e.c.Prefs.set('global','','','autoPageTurningInterval',bad));
 });
 await test('old 30-second preferences clamp only on read without modifying other settings',()=>{
  const e=env({autoReadIntervalSeconds:30,readerMode:'galleryRightToLeft'});const o=e.c.Prefs.resolve('comic','fixture');assert.equal(o.autoPageTurningInterval,10);assert.equal(o.readerMode,'galleryRightToLeft');assert.equal(e.writes.length,0);
 });
 await test('comic mode menu writes only that source/comic independent override, never global/device',async()=>{
  const e=env();await e.c.Prefs.set('global','','','readerMode','galleryLeftToRight');
  await e.p.selectComicMode('galleryTopToBottom');assert.equal(e.p.mode,'galleryTopToBottom');assert.equal(e.c.Prefs.enabled('comic','comic','fixture'),false);
  assert.equal(e.c.Prefs.resolve('comic','fixture').readerMode,'galleryTopToBottom');assert.equal(e.c.Prefs.resolve('other','fixture').readerMode,'galleryLeftToRight');
  assert.equal(e.c.Prefs.resolve('comic','other-source').readerMode,'galleryLeftToRight');assert.equal(e.c.Prefs.resolveForScope('global','','').readerMode,'galleryLeftToRight');
 });
 await test('failed comic mode write preserves old mode and global preferences',async()=>{
  const e=env();const global=e.c.Prefs.resolveForScope('global','','').readerMode;e.failNext();await e.p.selectComicMode('galleryTopToBottom');assert.equal(e.p.mode,'galleryLeftToRight');assert.equal(e.c.Prefs.resolveForScope('global','','').readerMode,global);
 });
 await test('speed popup uses sibling background layers so slider/inner clicks cannot bubble-dismiss it',()=>{
  const build=raw.slice(raw.lastIndexOf('  build() {'));const start=build.indexOf('      if (this.showSpeedMenu)');const section=build.slice(start,build.indexOf('      if (this.showModeMenu)',start));
  assert.match(section,/Stack\(\{ alignContent: Alignment\.Center \}\)/);assert.match(section,/Column\(\)\.width\('100%'\).*height\('100%'\)/);
  assert.match(section,/this\.speedMenuOverlay\(\)/);assert.doesNotMatch(section,/justifyContent\(FlexAlign\.Center\).*onClick/s);
 });
 await test('history writes only a resumable position with 12 matching SQL values, no duration or count',async()=>{
  const sql=[];const c=vm.createContext({Database:{rdb:{executeSync:(query,args)=>sql.push([query,args])}},ComicType:{local:{value:0,isLocal:true},fromKey:()=>({value:1})},Log:{warn(){}}});
  vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/storage/HistoryDao.ets'),{mode:'transform'})+'\nglobalThis.H=History;globalThis.Dao=HistoryDao;',c);
  const h=new c.H();h.id='comic';h.type={value:1};h.storedSourceKey='fixture';h.time=1;await c.Dao.save(h);
  assert.equal(sql.length,1);assert.equal(sql[0][1].length,12);assert.doesNotMatch(sql[0][0],/duration|statistics|reader_stats|read_count/i);assert.equal('readDurationMs' in h,false);
 });
 await test('production action/info/debug logging performs no disk writes or behavioural traces',()=>{
  const operations=[],warnings=[];const c=vm.createContext({fs:{openSync:()=>operations.push('open'),writeSync:()=>operations.push('write')},hilog:{debug:()=>operations.push('debug'),info:()=>operations.push('info'),warn:(...x)=>warnings.push(x),error:(...x)=>warnings.push(x)}});
  vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/foundation/Log.ets'),{mode:'transform'})+'\nglobalThis.L=Log;',c);
  c.L.audit('trace','page','fixture');c.L.info('reader','fixture');c.L.debug('reader','fixture');assert.deepEqual(operations,[]);assert.equal(c.L.isTracePersisted('trace'),false);
  c.L.warn('fixture','operation failed');assert.equal(warnings.length,1);assert.deepEqual(operations,[]);
 });
 await test('legacy diagnostic log cleanup removes exact ordinary owned names only',()=>{
  const deleted=[],files=new Set(['/app/files/logs/app-dev-2026-01-02.log','/app/files/logs/app-dev-2026-01-03.log','/app/files/logs/notes.log']);
  const c=vm.createContext({fs:{accessSync:()=>true,lstatSync:p=>({isSymbolicLink:()=>p.endsWith('03.log')}),statSync:p=>({isDirectory:()=>p==='/app/files/logs',isFile:()=>files.has(p)}),listFileSync:()=>['app-dev-2026-01-02.log','app-dev-2026-01-03.log','notes.log','../private'],unlinkSync:p=>deleted.push(p)},hilog:{warn(){},error(){}}});
  vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/foundation/Log.ets'),{mode:'transform'})+'\nglobalThis.L=Log;',c);c.L.configureFileLogging('/app/files');assert.deepEqual(deleted,['/app/files/logs/app-dev-2026-01-02.log']);
 });
 await test('failed position writes remain retryable and a late old failure cannot invalidate newer success',async()=>{
  const e=env();e.c.HistoryDao.save=async()=>{throw Error('fixture-db-full')};e.p.saveProgress(true);await Promise.resolve();await Promise.resolve();
  assert.equal(e.p.lastSavedPage,-1);let retried=0;e.c.HistoryDao.save=async()=>{retried++};e.p.saveProgress(true);await Promise.resolve();assert.equal(retried,1);assert.equal(e.p.lastSavedPage,0);
  const f=env();let rejectOld;let calls=0;f.c.HistoryDao.save=()=>{calls++;return calls===1?new Promise((_,reject)=>{rejectOld=reject}):Promise.resolve()};
  f.p.saveProgress(true);f.p.seekPage(1);f.p.saveProgress(true);f.p.seekPage(0);f.p.saveProgress(true);
  rejectOld(Error('old-failure'));await Promise.resolve();await Promise.resolve();assert.equal(f.p.lastSavedPage,0);assert.equal(calls,3);
 });
 assert.equal(count,13);finished=true;const folder=path.join(root,'logs/privacy-pagination-20261029');fs.mkdirSync(folder,{recursive:true});fs.writeFileSync(path.join(folder,'reader-speed-privacy.json'),JSON.stringify({cases:count,results,evidence:'production reader/preferences/history/log methods with controlled SDK fakes; no device'},null,2));
 console.log('PASS 13 reader decimal-speed/comic-scope/privacy contracts; local production methods only');
})().catch(error=>{console.error(error);process.exitCode=1});
