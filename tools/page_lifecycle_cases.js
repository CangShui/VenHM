'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/page-lifecycle-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
fs.writeFileSync(log,'[请求到达] TraceID=page-life-tests production lifecycle bodies, deterministic SDK/init fakes\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function page(relative,name,scope,marker='  build() {'){
  const raw=read(relative),cut=raw.indexOf(marker);
  const body=(raw.slice(0,cut)+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace(`struct ${name}`,`class ${name}`);
  scope.Log={audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)};
  const ctx=vm.createContext(scope);
  vm.runInContext(stripTypeScriptTypes(body,{mode:'transform'})+`\nglobalThis.Page=${name};`,ctx);
  return {ctx,p:new ctx.Page()};
}
const tick=()=>new Promise(r=>setImmediate(r));
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=page-life-tests PASS ${name}\n`)}
(async()=>{
  await test('download async initialization returning after disappear cannot spawn timer',async()=>{
    let resolve;const timers=[],pauses=[];
    const e=page('entry/src/main/ets/pages/DownloadsPage.ets','DownloadsPage',{
      AppContext:{ensureInitialized:()=>{}},AppInit:{init:()=>new Promise(r=>resolve=r)},
      DownloadQueue:{tasks:[],init:()=>{},pauseAll:r=>pauses.push(r)},
      setInterval:()=>{timers.push(1);return 1},clearInterval:()=>{}});
    e.p.getUIContext=()=>({getHostContext:()=>({})});e.p.aboutToAppear();e.p.aboutToDisappear();resolve();await tick();
    assert.equal(timers.length,0);assert.equal(pauses.length,0);
  });
  await test('download page hide clears only UI timer; native queue ownership survives navigation',async()=>{
    const timers=[],cleared=[],pauses=[];
    const e=page('entry/src/main/ets/pages/DownloadsPage.ets','DownloadsPage',{
      AppContext:{ensureInitialized:()=>{}},AppInit:{init:async()=>{}},
      DownloadQueue:{tasks:[],init:()=>{},pauseAll:r=>pauses.push(r)},
      setInterval:()=>{timers.push(1);return timers.length},clearInterval:id=>cleared.push(id)});
    e.p.getUIContext=()=>({getHostContext:()=>({})});e.p.aboutToAppear();await tick();e.p.onPageHide();
    assert.deepEqual(cleared,[1]);assert.equal(pauses.length,0);e.p.onPageShow();assert.equal(timers.length,2);
    e.p.onPageShow();assert.equal(timers.length,2);e.p.aboutToDisappear();
  });
  await test('source page late list response after disappear cannot modify UI fields',async()=>{
    let resolve;const e=page('entry/src/main/ets/pages/SourceManagerPage.ets','SourceManagerPage',{
      AppInit:{init:async()=>{}},SourceInstaller:{listInstalled:()=>new Promise(r=>resolve=r)},
      SourceManager:{all:()=>['source'],errors:[]},SourceRepositories:{all:()=>['repo']}
    },'  @Builder');
    const run=e.p.reload();await tick();e.p.aboutToDisappear();resolve(['late']);await run;
    assert.equal(e.p.installedSources.length,0);assert.equal(e.p.repositories.length,0);
  });
  await test('source refresh responses cannot overwrite newer request result',async()=>{
    const releases=[];
    const e=page('entry/src/main/ets/pages/SourceManagerPage.ets','SourceManagerPage',{
      AppInit:{init:async()=>{}},SourceInstaller:{listInstalled:()=>new Promise(r=>releases.push(r))},
      SourceManager:{all:()=>[],errors:[]},SourceRepositories:{all:()=>[]}
    },'  @Builder');
    const old=e.p.reload();await tick();const next=e.p.reload();await tick();
    releases[1](['new']);await next;releases[0](['old']);await old;
    assert.deepEqual(Array.from(e.p.installedSources),['new']);assert.equal(e.p.loading,false);
  });
  await test('UIAbility background/foreground uses async lease gate and never auto-resumes',async()=>{
    // setForeground is async now: it may acquire/release a native DATA_TRANSFER lease.
    const states=[],shutdowns=[],ctx=vm.createContext({UIAbility:class{},
      DownloadQueue:{setForeground:async v=>{states.push(v);},shutdown:async reason=>{shutdowns.push(reason);}},
      router:{pushUrl:async()=>{}},Log:{info:()=>{},warn:()=>{}}});
    const body=read('entry/src/main/ets/entryability/EntryAbility.ets').replace('default class EntryAbility','class EntryAbility');
    vm.runInContext(stripTypeScriptTypes(body,{mode:'transform'})+'\nglobalThis.Ability=EntryAbility;',ctx);
    const ability=new ctx.Ability();ability.onBackground();ability.onForeground();await tick();
    assert.deepEqual(states,[false,true]);
    ability.onDestroy();await tick();assert.deepEqual(shutdowns,['UIAbility 销毁']);
    // A notification tap routes to the list only; it must not start any transfer.
    ability.onNewWant({parameters:{openDownloads:true}},{});await tick();assert.deepEqual(states,[false,true]);
  });
  console.log(`PASS ${count} production page/ability lifecycle race cases; actual OS background probe pending.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
