'use strict';
// Contracts for the three reported reader issues. Executes the real production
// turn method from ReaderPage and inspects the shipped UI source; no device,
// no network, no user data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/reader-bounce-page-slider-20261030');
fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
let count=0,finished=false;const EXPECTED=12;
process.on('beforeExit',()=>{if(!finished){console.error(`READER_CONTRACTS_INCOMPLETE ${count}/${EXPECTED}`);process.exitCode=1}});
function test(name,fn){fn();count++;console.log('PASS '+name)}

/** Extract one method body from ReaderPage by brace counting. */
function methodSource(text,signature){
  const start=text.indexOf(signature);
  if(start<0)throw new Error('method not found: '+signature);
  let depth=0;
  for(let i=start;i<text.length;i++){
    const ch=text[i];
    if(ch==='{')depth++;
    else if(ch==='}'){
      depth--;
      if(depth===0)return text.slice(start,i+1);
    }
  }
  throw new Error('unbalanced method: '+signature);
}

function turnHarness(mode,scroller){
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const body=methodSource(page,'private turnReaderViewport(offset: number): void {');
  const code=stripTypeScriptTypes(clean('entry/src/main/ets/features/ReaderModes.ets'),{mode:'transform'})
    +'\n'+stripTypeScriptTypes('class H {\n'+body+'\n}',{mode:'transform'})
    +'\nglobalThis.make=(mode,scroller)=>{const h=Object.create(H.prototype);h.mode=mode;h.listScroller=scroller;'
    +'h.viewportHeight=1000;h.viewportWidth=600;h.options={enablePageAnimation:false};'
    +'h.chapters=[];h.turnReaderChapter=(o)=>{h.chapterTurns.push(o)};h.chapterTurns=[];'
    +'h.adjacentSource=(o)=>-1;h.stepPage=(o)=>{h.steps.push(o)};h.steps=[];return h};'
    +'\nglobalThis.ReaderModes=ReaderModes;';
  const ctx=vm.createContext({console});
  vm.runInContext(code,ctx);
  return ctx.make(mode,scroller);
}

function scroller(opts={}){
  const calls={scrollPage:[],scrollBy:[],scrollToIndex:[]};
  return {calls,
    currentOffset:()=>({xOffset:opts.x??0,yOffset:opts.y??0}),
    isAtEnd:()=>opts.atEnd===true,
    scrollPage:(o)=>calls.scrollPage.push(o),
    scrollBy:(x,y)=>calls.scrollBy.push([x,y]),
    scrollToIndex:(i,a)=>calls.scrollToIndex.push(i)};
}

// ---------------------------------------------------------------- 1. bounce
test('vertical waterfall turns the page with a bounded scrollPage, never scrollBy',()=>{
  const s=scroller();const h=turnHarness('waterfallTopToBottom',s);
  h.turnReaderViewport(1);
  assert.equal(s.calls.scrollBy.length,0,'scrollBy overshoots and springs back');
  assert.deepEqual(JSON.parse(JSON.stringify(s.calls.scrollPage)),[{next:true,animation:false}]);
  assert.equal(h.chapterTurns.length,0);
});

test('vertical continuous mode scrolls backwards without overscroll',()=>{
  const s=scroller({y:800});const h=turnHarness('continuousTopToBottom',s);
  h.turnReaderViewport(-1);
  assert.deepEqual(JSON.parse(JSON.stringify(s.calls.scrollPage)),[{next:false,animation:false}]);
});

test('vertical gallery mode still pages through the swiper path',()=>{
  const s=scroller();const h=turnHarness('galleryTopToBottom',s);
  h.turnReaderViewport(1);
  assert.equal(s.calls.scrollPage.length,0,'gallery modes must not scroll the list');
  assert.equal(h.chapterTurns.length,1,'no adjacent page means chapter turn');
});

test('reaching the edge still switches chapter instead of bouncing',()=>{
  const top=scroller({y:0});const h1=turnHarness('waterfallTopToBottom',top);
  h1.turnReaderViewport(-1);
  assert.equal(h1.chapterTurns[0],-1);
  const end=scroller({atEnd:true});const h2=turnHarness('waterfallTopToBottom',end);
  h2.turnReaderViewport(1);
  assert.equal(h2.chapterTurns[0],1);
  assert.equal(top.calls.scrollPage.length+end.calls.scrollPage.length,0);
});

test('reversed horizontal mode asks for the previous list page',()=>{
  const s=scroller({x:500});const h=turnHarness('continuousRightToLeft',s);
  h.turnReaderViewport(1);
  assert.deepEqual(JSON.parse(JSON.stringify(s.calls.scrollPage)),[{next:false,animation:false}]);
});

test('the list and swiper disable the spring edge effect for up-down modes',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  assert.match(page,/\.edgeEffect\(ReaderModes\.isVertical\(this\.mode\) \? EdgeEffect\.None : EdgeEffect\.Spring\)/);
  assert.match(page,/\.effectMode\(this\.mode === 'galleryTopToBottom' \? EdgeEffect\.None : EdgeEffect\.Spring\)/);
});

// ---------------------------------------------------------------- 2. slider
test('page slider sits above the brightness slider and jumps on release',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const pageRow=page.indexOf("Text('页码')");
  const brightRow=page.indexOf("Text('亮度')");
  assert.ok(pageRow>0&&brightRow>pageRow,'page slider must come first');
  const block=page.slice(pageRow,brightRow);
  assert.match(block,/max: Math\.max\(1, this\.images\.length\)/);
  assert.match(block,/enabled\(this\.images\.length > 1 && this\.progressReady && !this\.loading\)/);
  assert.match(block,/if \(mode === SliderChangeMode\.End \|\| mode === SliderChangeMode\.Click\) \{/);
  assert.match(block,/this\.seekPage\(this\.pageSlider - 1\)/);
  assert.match(page,/this\.pageSlider = actual \+ 1;/);
  assert.match(page,/this\.pageSlider = pageIndex \+ 1;/);
});

// ---------------------------------------------------------------- 3. retry
test('a failed page shows a centred retry button that reloads that page',()=>{
  const widgets=read('entry/src/main/ets/components/ComicWidgets.ets');
  assert.match(widgets,/if \(this\.failed\) \{[\s\S]{0,320}Button\('重试'\)/);
  const retry=methodSource(widgets,'private retryImage(): void {');
  assert.match(retry,/this\.failed = false;/);
  assert.match(retry,/this\.load\(\);/);
  assert.match(widgets,/\.onClick\(\(\) => \{ this\.retryImage\(\); \}\)/);
  assert.doesNotMatch(retry,/this\.url/,'retry must not log or rewrite the image url');
});

test('the slider jump rejects out-of-range or fractional page numbers',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const body=methodSource(page,'private seekPage(actual: number): void {');
  assert.match(body,/actual < 0 \|\| actual >= this\.images\.length/);
  assert.match(body,/Math\.floor\(actual\) !== actual/);
  assert.match(body,/this\.pageSlider = actual \+ 1;/);
  assert.match(body,/this\.saveProgress\(\);/);
});

test('auto-speed dialog lets its slider and buttons receive taps',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const dialog=methodSource(page,'speedMenuOverlay() {');
  assert.match(dialog,/Slider\(\{ value: this\.speedDraft/, 'the slider must be inside the dialog');
  assert.match(dialog,/Button\('取消'\)/, 'cancel button present');
  assert.match(dialog,/this\.selectAutoSpeed\(this\.speedDraft\)/, 'apply button present');
  // HitTestMode.Block on the panel root swallows every child touch.
  assert.doesNotMatch(dialog,/hitTestBehavior\(HitTestMode\.Block\)/);
  assert.match(dialog,/hitTestBehavior\(HitTestMode\.Default\)/);
});

test('only the dismiss masks keep blocking hit tests',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const blocks=(page.match(/hitTestBehavior\(HitTestMode\.Block\)/g)||[]).length;
  assert.equal(blocks,3,'the three overlay masks still block the reader behind them');
  const speed=page.slice(page.indexOf("if (this.showSpeedMenu) {"));
  assert.match(speed,/hitTestBehavior\(HitTestMode\.Block\)\.onClick\(\(\) => \{ this\.showSpeedMenu = false; \}\)/);
});

test('opening the auto-speed dialog closes the bottom bar and its scrim',()=>{
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const body=methodSource(page,'private openAutoSpeedMenu(): void {');
  assert.match(body,/this\.toolbarVisible = false;/, 'the blocking scrim must be gone before the dialog opens');
  assert.match(body,/this\.showSpeedMenu = true;/);
});

assert.equal(count,EXPECTED);finished=true;
fs.writeFileSync(path.join(folder,'cases.json'),JSON.stringify({cases:count,scope:'production turnReaderViewport + reader/page/image source contracts'},null,2));
console.log(`PASS ${count} reader contracts: no bounce in up/down modes, page slider, per-image retry`);
