'use strict';
// Automatic chapter change: hint + seamless swap. Executes the real
// turnReaderChapter method and inspects goToChapter/build wiring. Local
// fixtures only: no network, no device, no user data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/reader-chapter-switch-20261101');
fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
let count=0,finished=false;const EXPECTED=6;
process.on('beforeExit',()=>{if(!finished){console.error(`CHAPTER_SWITCH_INCOMPLETE ${count}/${EXPECTED}`);process.exitCode=1}});
async function test(name,fn){
  let timer;
  try{
    await Promise.race([Promise.resolve().then(fn),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),4000)})]);
    count++;console.log('PASS '+name);
  }finally{clearTimeout(timer)}
}
function methodSource(text,signature){
  const start=text.indexOf(signature);
  if(start<0)throw new Error('method not found: '+signature);
  let depth=0;
  for(let i=start;i<text.length;i++){
    if(text[i]==='{')depth++;
    else if(text[i]==='}'){depth--;if(depth===0)return text.slice(start,i+1)}
  }
  throw new Error('unbalanced: '+signature);
}

/** Host-side toast capture: the production method calls promptAction itself. */
function harness(options){
  const toasts=[];
  const page=read('entry/src/main/ets/pages/ReaderPage.ets');
  const body=methodSource(page,'private async turnReaderChapter(offset: number): Promise<void> {');
  const code=stripTypeScriptTypes('class H {\n'+body+'\n}',{mode:'transform'})
    +'\nglobalThis.make=(options)=>{'
    +'const h=Object.create(H.prototype);'
    +'h.chapterIds=["c1","c2"];h.epId="c1";h.disposed=false;h.visible=true;h.loading=false;'
    +'h.progressReady=true;h.error="";h.loadVersion=0;h.images=["a"];h.mode="waterfallTopToBottom";'
    +'h.currentPage=0;h.previousEndLoad=-1;h.switched=[];h.title="第2话";'
    +'h.currentChapterIndex=()=>h.chapterIds.indexOf(h.epId);'
    +'h.chapterTitle=()=>h.title;'
    +'h.switchChapter=async(offset)=>{h.switched.push(offset);'
    +'  if(options.fail){h.error="章节加载失败";h.loadVersion+=1;return;}'
    +'  h.epId=offset>0?"c2":"c1";h.loadVersion+=1;h.images=["b","c"];h.progressReady=true;'
    +'  h.currentPage=0;};'
    +'h.seekPage=()=>{h.sought=true};h.alignPreviousChapterEnd=()=>{};'
    +'return h};'
    +'\nglobalThis.ReaderModes={isGallery:()=>false};';
  const ctx=vm.createContext({
    console, setTimeout, clearTimeout,
    promptAction:{ showToast:(o)=>{ toasts.push(o && o.message); } }
  });
  vm.runInContext(code,ctx);
  return {h:ctx.make(options||{}),toasts};
}

(async()=>{
  await test('turning past the last page announces the automatic next chapter once',async()=>{
    const {h,toasts}=harness({});
    await h.turnReaderChapter(1);
    assert.deepEqual(Array.from(h.switched),[1]);
    assert.equal(toasts.length,1,'exactly one hint per automatic change');
    assert.match(toasts[0],/已自动进入下一章/);
    assert.match(toasts[0],/第2话/,'the hint names the chapter when it is short');
  });

  await test('a long chapter title falls back to the short generic hint',async()=>{
    const {h,toasts}=harness({});
    h.title='这是一个非常非常长的章节标题用来验证截断逻辑是否被正确处理了';
    await h.turnReaderChapter(1);
    assert.equal(toasts[0],'已自动进入下一章');
  });

  await test('no hint when the next chapter fails to load',async()=>{
    const {h,toasts}=harness({fail:true});
    await h.turnReaderChapter(1);
    assert.equal(toasts.length,0,'a failed load must not claim success');
    assert.equal(h.error,'章节加载失败');
  });

  await test('going back does not announce an automatic next chapter',async()=>{
    const {h,toasts}=harness({});
    h.epId='c2';
    await h.turnReaderChapter(-1);
    assert.equal(toasts.length,0);
    assert.equal(h.sought,true,'previous chapter still lands on its last page');
  });

  await test('goToChapter keeps rendered pages and only shows the loader on a cold open',()=>{
    const page=read('entry/src/main/ets/pages/ReaderPage.ets');
    const body=methodSource(page,'private async goToChapter(next: number): Promise<void> {');
    assert.match(body,/this\.chapterTransition = this\.images\.length > 0;/);
    assert.match(body,/this\.chapterTransition = false;/);
    assert.match(body,/offset > 0[\s\S]{0,90}scheduleAnchorRestore\(\)/);
    assert.match(page,/if \(this\.loading && !\(this\.chapterTransition && this\.images\.length > 0\)\) \{/);
    assert.match(page,/@State chapterTransition: boolean = false;/);
  });

  await test('auto reading across chapters does not spam the page-turn hint',()=>{
    const page=read('entry/src/main/ets/pages/ReaderPage.ets');
    const auto=methodSource(page,'private async autoStep(): Promise<void> {');
    assert.match(auto,/await this\.switchChapter\(1\);/);
    assert.doesNotMatch(auto,/turnReaderChapter/,'auto mode must not reuse the hinting path');
    assert.doesNotMatch(auto,/showToast/);
  });

  assert.equal(count,EXPECTED);finished=true;
  fs.writeFileSync(path.join(folder,'cases.json'),JSON.stringify({cases:count,scope:'production turnReaderChapter + goToChapter/build wiring'},null,2));
  console.log(`PASS ${count} automatic chapter-change contracts`);
})().catch(error=>{console.error(error);process.exitCode=1});
