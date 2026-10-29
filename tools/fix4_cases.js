'use strict';
// Regression for the four user-reported defects: fullscreen window, stale local
// library after deleting a download, vertical-continuous scroll bounce, and
// unreadable dropdown text under a dark system theme.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/fix4-20261023');fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const raw=p=>read(p).replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
let count=0;
function check(name,fn){fn();count++;console.log('PASS '+name)}

// 1) Fullscreen window: layout must be enabled and app pinned to light mode.
check('application enables fullscreen layout with transparent system bars and light-only colour mode',()=>{
  const src=read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(src,/setWindowLayoutFullScreen\(true\)/);
  assert.match(src,/setWindowBackgroundColor\(WINDOW_BACKGROUND\)/);
  assert.match(src,/statusBarColor: '#00000000'/);
  assert.match(src,/navigationBarColor: '#00000000'/);
  assert.match(src,/COLOR_MODE_LIGHT/);
  assert.doesNotMatch(src,/COLOR_MODE_NOT_SET/);
  assert.match(src,/this\.applyImmersiveLayout\(windowStage\);\s*\n\s*windowStage\.loadContent/);
});

// 2) Dropdown text must never depend on the system theme.
check('every Select pins its own text, option and menu colours',()=>{
  const files=new Map();
  const walk=dir=>{for(const e of fs.readdirSync(path.join(root,dir),{withFileTypes:true})){
    const rel=`${dir}/${e.name}`;if(e.isDirectory())walk(rel);else if(e.name.endsWith('.ets'))files.set(rel,read(rel));}};
  walk('entry/src/main/ets');
  let selects=0;
  for(const [file,text] of files){
    const declared=(text.match(/^\s*Select\(/gm)||[]).length;
    if(declared===0)continue;
    const styled=(text.match(/optionFontColor/g)||[]).length;
    const chain=(text.match(/fontColor\(UiTheme\.ink\)\.selectedOptionFontColor/g)||[]).length;
    assert.equal(chain,declared,`${file}: ${declared} Select but ${chain} styled`);
    selects+=declared;
  }
  assert.equal(selects,10,'expected ten Select components');
});

// 3) Deleting a download must notify cached local-comic lists.
check('download deletion and completion notify the local library, and both tabs listen',()=>{
  const queue=read('entry/src/main/ets/features/DownloadQueue.ets');
  assert.match(queue,/import \{ LocalLibrarySignal \} from '\.\/LocalLibrarySignal'/);
  const del=queue.slice(queue.indexOf('static async deleteTask'),queue.indexOf('static async resume'));
  assert.match(del,/LocalLibrarySignal\.notify\(\)/);
  const run=queue.slice(queue.indexOf('if (DownloadQueue.live(task, generation) && task.chapter === task.chapterIds.length)'));
  assert.match(run.slice(0,320),/LocalLibrarySignal\.notify\(\)/);
  for(const file of ['entry/src/main/ets/features/HomeView.ets','entry/src/main/ets/features/BookshelfView.ets']){
    const text=read(file);
    assert.match(text,/LocalLibrarySignal\.addListener/);
    assert.match(text,/LocalLibrarySignal\.removeListener/);
    assert.match(text,/reloadLocal/);
  }
});

check('local library signal fans out to listeners and isolates a failing one',()=>{
  const ctx=vm.createContext({});
  vm.runInContext(stripTypeScriptTypes(raw('entry/src/main/ets/features/LocalLibrarySignal.ets'),{mode:'transform'})
    +'\nglobalThis.Signal=LocalLibrarySignal;',ctx);
  const S=ctx.Signal;const hits=[];
  const a=()=>hits.push('a');
  const boom=()=>{throw Error('listener failure');};
  const b=()=>hits.push('b');
  S.addListener(a);S.addListener(boom);S.addListener(b);S.addListener(a);
  S.notify();
  assert.deepEqual(hits,['a','b'],'duplicate listener registered once, failure isolated');
  S.removeListener(a);hits.length=0;S.notify();
  assert.deepEqual(hits,['b']);
  S.removeListener(boom);S.removeListener(b);hits.length=0;S.notify();
  assert.deepEqual(hits,[]);
});

// 4) Vertical continuous scrolling must not be pulled back by late layout.
function readerHarness(){
  const rawReader=read('entry/src/main/ets/pages/ReaderPage.ets');
  const reader=(rawReader.slice(0,rawReader.indexOf('  @Builder'))+'}')
    .replace(/^import .*;\r?\n/gm,'')
    .replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct ReaderPage','class ReaderPage');
  const options=raw('entry/src/main/ets/foundation/ReaderSettings.ets').split('class ReaderProfile')[0];
  let now=1000;
  const ctx=vm.createContext({
    Date:class extends Date{static now(){return now;}},
    setTimeout:()=>0,clearTimeout(){},setInterval:()=>0,clearInterval(){},
    SwiperController:class{changeIndex(){}},Scroller:class{scrollToIndex(){}currentOffset(){return{xOffset:0,yOffset:0}}isAtEnd(){return false}scrollBy(){}},
    History:class{},ComicType:{fromKey:()=>({value:1})},HistoryDao:{save:async()=>{}},
    ImageFit:{Cover:0},ImageRequestConfig:class{},ImageLoader:{cancelOwned(){}},ReaderSettings:{},
    AppContext:{context:{},ensureInitialized(){}},
    ReaderWindowChrome:class{enter(){return Promise.resolve()}leave(){return Promise.resolve()}},
    router:{getParams:()=>({}),getState:()=>({index:1}),getStateByIndex:()=>undefined,back(){},replaceUrl:async()=>{}},
    Log:{audit(){},warn(){},error(){}},promptAction:{showToast(){}},
    TouchType:{Down:0,Move:1,Up:2,Cancel:3},px2vp:v=>v,batteryInfo:{batterySOC:100},ScrollAlign:{START:0,END:1}
  });
  const helpers=['ReaderModes','ReaderSpreads','ReaderRenderSource','ReaderVolumeKeys','ReadingPosition','ReaderImageLayout','ReaderTapPolicy','ReaderGesturePolicy']
    .map(n=>raw(`entry/src/main/ets/features/${n}.ets`)).join('\n');
  vm.runInContext(stripTypeScriptTypes(helpers+'\n'+raw('entry/src/main/ets/components/ReaderClickZones.ets')+'\n'
    +options+'\n'+reader,{mode:'transform'})+'\nglobalThis.Reader=ReaderPage;',ctx);
  return {ctx,setNow:v=>{now=v;}};
}
function flowPage(h,mode='continuousTopToBottom'){
  const p=new h.ctx.Reader();
  p.mode=mode;p.images=['a','b','c','d','e'];p.chapterIds=['ch'];p.epId='ch';
  p.sourceKey='s';p.comicId='c';p.loading=false;p.progressReady=true;p.visible=true;
  p.viewportWidth=400;p.viewportHeight=800;p.options.readerScreenPicNumberForPortrait=1;
  p.rebuildPresentation();
  for(let i=0;i<5;i++)p.onImageReady(i,p.renderGeneration,true);
  p.visibleFirst=2;p.visibleLast=3;p.currentPage=2;p.renderGeneration=p.renderGeneration;
  p.layoutPending=false;p.restorePage=-1;
  return p;
}

check('a size change on the visible item no longer yanks vertical-continuous scrolling back',()=>{
  const h=readerHarness();
  const p=flowPage(h);
  p.onFlowImageSize(2,p.renderGeneration,100,140); // the item the user is reading
  assert.equal(p.layoutPending,false,'no anchor restore for the visible item');
  p.onFlowImageSize(3,p.renderGeneration,0,200);   // an item below
  assert.equal(p.layoutPending,false,'no anchor restore for items below');
});

check('a size change strictly above the viewport still restores the reading anchor',()=>{
  const h=readerHarness();
  const p=flowPage(h);
  p.onFlowImageSize(0,p.renderGeneration,0,300);
  assert.equal(p.layoutPending,true);
  assert.equal(p.restorePage,p.sourceToDisplay(p.currentPage));
});

check('scrolling and the post-scroll cooldown suppress anchor restores',()=>{
  const h=readerHarness();
  const p=flowPage(h);
  p.scrolling=true;
  p.onFlowImageSize(0,p.renderGeneration,0,300);
  assert.equal(p.layoutPending,false,'restore suppressed while scrolling');
  p.scrolling=false;
  p.lastUserScrollAt=Date.now();
  p.onFlowImageSize(0,p.renderGeneration,0,300);
  assert.equal(p.layoutPending,false,'restore suppressed right after a scroll');
  h.setNow(Date.now()+700);
  p.onFlowImageSize(0,p.renderGeneration,0,301);
  assert.equal(p.layoutPending,true,'restore resumes once the cooldown expires');
});

check('gallery modes and stale generations never schedule anchor restores',()=>{
  const h=readerHarness();
  const p=flowPage(h,'galleryLeftToRight');
  p.onFlowImageSize(0,p.renderGeneration,0,300);
  assert.equal(p.layoutPending,false,'gallery is unaffected');
  const q=flowPage(h);
  q.onFlowImageSize(0,q.renderGeneration-1,0,300);
  assert.equal(q.layoutPending,false,'stale render generation ignored');
  const r=flowPage(h);
  r.onFlowImageSize(0,r.renderGeneration,300,300);
  assert.equal(r.layoutPending,false,'unchanged height ignored');
});

fs.writeFileSync(path.join(folder,'fix4-cases.json'),JSON.stringify({
  cases:count,
  scope:'four reported defects; production sources plus a VM-run reader/signal harness; no device'
},null,2));
console.log(`PASS ${count} regression cases for fullscreen layout, local-library refresh, scroll bounce and dropdown colours; no device/install`);
