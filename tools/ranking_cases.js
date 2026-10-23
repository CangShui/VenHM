'use strict';
// Production ArkTS data/adapter/session and page lifecycle methods, transformed by
// Node only. Controlled fakes; NOT SDK bytecode/device/live-site evidence.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/ranking-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
fs.writeFileSync(log,'Production ranking contracts, source-locked lifecycle and controlled bridge. No network/device/credentials.\n');
const audit=(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`);
const ctx=vm.createContext({Log:{audit},Map,Error});
ctx.JsEngine={callJson:async code=>vm.runInContext(code,ctx)};
vm.runInContext(stripTypeScriptTypes([
  'entry/src/main/ets/foundation/Extensions.ets','entry/src/main/ets/model/Comic.ets',
  'entry/src/main/ets/model/Res.ets','entry/src/main/ets/features/SourceFailure.ets',
  'entry/src/main/ets/source/RankingData.ets','entry/src/main/ets/source/JsRankingAdapter.ets',
  'entry/src/main/ets/features/RankingSession.ets'
].map(clean).join('\n'),{mode:'transform'})+'\nglobalThis.T={Res,RankingData,JsRankingAdapter,RankingSession};globalThis.ComicSource={sources:{}};',ctx);
const {Res,RankingData,JsRankingAdapter:Adapter,RankingSession:Session}=ctx.T;
const ok=(items,next)=>Res.ok(items,next),item=(id,key='a')=>({id,sourceKey:key,title:id,cover:'',subtitle:''});
const defer=()=>{let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j});return {promise,resolve,reject}};
const tick=()=>new Promise(r=>setImmediate(r));
const source=(data,key='a')=>({key,name:key,categoryComics:{rankingData:data}});
const data=(load,loadWithNext)=>{const d=new RankingData();d.options=new Map([['day','Day'],['week','Week']]);d.load=load;d.loadWithNext=loadWithNext;return d};
function page(file,name,scope){
  let code=clean(file);code=code.slice(0,code.indexOf('  build() {'))+'}';
  code=code.replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace(`struct ${name}`,`class ${name}`);
  const c=vm.createContext({Log:{audit},Error,...scope});
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+`\nglobalThis.Subject=${name};`,c);return new c.Subject();
}
let count=0;async function test(name,fn){await fn();count++;fs.appendFileSync(log,`PASS ${name}\n`)}
(async()=>{
  await test('upstream first-dash option parsing preserves order labels duplicate semantics and blank key',async()=>{
    const parsed=Adapter.parseOptions(['day-Day-label','invalid','','-Blank','day-Updated-label']);
    assert.deepEqual(Array.from(parsed),[['day','Updated-label'],['','Blank']]);
    for(const bad of [null,{},[],['bad'],[42]])assert.throws(()=>Adapter.parseOptions(bad));
  });
  await test('production adapter quotes source/option and page wins; never evaluates labels or loadNext alias',async()=>{
    const key='x\";globalThis.injected=true;//',option='v\"\\\n';let pageCalls=0,cursorCalls=0;
    ctx.ComicSource.sources[key]={categoryComics:{ranking:{options:[option+'-unsafe-label'],load:async(o,p)=>{assert.equal(o,option);assert.equal(p,1);pageCalls++;return {comics:[{id:'c',sourceKey:'evil',title:'T'}],maxPage:1}},loadWithNext:async()=>{cursorCalls++}}}};
    const d=Adapter.create(key,'fixture',true,true);assert.equal(d.loadWithNext,undefined);
    assert.equal((await d.optionsLoader()).error,false);const r=await d.load(option,1);
    assert.equal(r.error,false);assert.equal(r.data[0].sourceKey,key);assert.equal(pageCalls,1);assert.equal(cursorCalls,0);assert.equal(ctx.injected,undefined);
    ctx.ComicSource.sources.a={categoryComics:{ranking:{options:['x-X'],loadNext:()=>{throw Error('must not alias')}}}};
    const missing=Adapter.create('a','fixture',false,false);assert.equal(missing.load,undefined);assert.equal(missing.loadWithNext,undefined);
    const s=new Session();await s.start(source(missing));assert.match(s.error,/load\/loadWithNext/);assert.equal(s.loading,false);
  });
  await test('adapter cursor first null opaque cursor preserved and returned null ends',async()=>{
    const calls=[],cursor='https://opaque.invalid/path?token=private&after=a%2Fb';
    ctx.ComicSource.sources.a={categoryComics:{ranking:{options:['day-Day'],loadWithNext:async(o,n)=>{calls.push([o,n]);return {comics:[{id:n===null?'1':'2'}],next:n===null?cursor:null}}}}};
    const s=new Session();await s.start(source(Adapter.create('a','fixture',false,true)));await s.more();
    assert.deepEqual(calls,[['day',null],['day',cursor]]);assert.equal(s.results.length,2);assert.equal(s.ended,true);
    assert.doesNotMatch(fs.readFileSync(log,'utf8'),/token=private/);
  });
  await test('adapter malformed results and errors produce explicit Res failure',async()=>{
    const bad=[null,[],{}, {comics:null},{comics:[null]},{comics:[{}]},{comics:[{id:'x'}],maxPage:'2'},{comics:[{id:'x'}],maxPage:0}];
    for(const value of bad){ctx.ComicSource.sources.a={categoryComics:{ranking:{load:async()=>value}}};assert.equal((await Adapter.create('a','fixture',true,false).load('day',1)).error,true)}
    ctx.ComicSource.sources.a={categoryComics:{ranking:{load:async()=>{throw Error('HTTP 403 private-body')}}}};
    const r=await Adapter.create('a','fixture',true,false).load('day',1);assert.equal(r.error,true);assert.match(r.errorMessage,/403/);assert.doesNotMatch(r.errorMessage,/private-body/);
    ctx.ComicSource.sources.a={categoryComics:{ranking:{loadWithNext:async()=>({comics:[],next:42})}}};
    assert.equal((await Adapter.create('a','fixture',false,true).loadWithNext('day',null)).error,true);
  });
  await test('single maxPage one stops, null maxPage continues, options default first and reset',async()=>{
    const calls=[],s=new Session();await s.start(source(data(async(o,p)=>{calls.push([o,p]);return ok([item(o+p)],o==='day'?1:null)})));
    assert.equal(s.option,'day');assert.equal(s.ended,true);await s.more();assert.equal(calls.length,1);
    await s.select('week');assert.equal(s.page,1);assert.equal(s.results.length,1);assert.equal(s.ended,false);await s.more();
    assert.deepEqual(calls,[['day',1],['week',1],['week',2]]);
  });
  await test('dedup same-source id only, foreign source rows rejected rather than cross-source details',async()=>{
    const s=new Session();await s.start(source(data(async()=>ok([item('x'),item('x')]))));assert.equal(s.results.length,1);
    await s.more();assert.equal(s.results.length,1);assert.equal(s.ended,true);
    await s.start(source(data(async()=>ok([item('x','other')]))));assert.equal(s.results.length,0);assert.ok(s.error);assert.equal(s.page,0);
  });
  await test('cursor multi-token cycles and empty subsequent page stop without discarding rows',async()=>{
    let n=0;const s=new Session();await s.start(source(data(undefined,async()=>ok([item(String(++n))],n===1?'A':n===2?'B':'A'))));
    await s.more();assert.equal(s.ended,false);await s.more();assert.equal(s.ended,true);assert.equal(s.results.length,3);
    await s.start(source(data(async(o,p)=>ok(p===1?[item('one')]:[]))));await s.more();assert.equal(s.ended,true);assert.equal(s.results.length,1);
  });
  await test('empty first page retry restarts first page and missing data/metadata fail visibly',async()=>{
    const calls=[],s=new Session();await s.start(source(data(async(o,p)=>{calls.push(p);return ok([],1)})));assert.equal(s.ended,true);await s.retry();assert.deepEqual(calls,[1,1]);
    for(const sourceValue of [{key:'a'},source(data(undefined,undefined)),source(Object.assign(data(async()=>ok([])),{options:new Map()})),source(Object.assign(data(async()=>ok([])),{optionsLoader:async()=>Res.fail('private')}))]){
      await s.start(sourceValue);assert.ok(s.error);assert.equal(s.loading,false);assert.equal(s.results.length,0);
    }
  });
  await test('append failure keeps page rows cursor and retries exactly same request',async()=>{
    const calls=[],s=new Session();let fail=true;
    await s.start(source(data(undefined,async(o,n)=>{calls.push(n);if(n!==null&&fail)throw Error('HTTP 503 private');return ok([item(n===null?'one':'two')],n===null?'opaque':null)})));
    await s.more();assert.equal(s.page,1);assert.equal(s.results.length,1);assert.ok(s.error);fail=false;await s.retry();
    assert.deepEqual(calls,[null,'opaque','opaque']);assert.equal(s.page,2);assert.equal(s.error,'');assert.equal(s.ended,true);
  });
  await test('option race old result and finally cannot replace or hide newer loading',async()=>{
    const first=defer(),second=defer(),s=new Session();const d=data(o=>o==='day'?first.promise:second.promise);
    const a=s.start(source(d));assert.equal(s.loading,true);const b=s.select('week');first.resolve(ok([item('old')],1));await a;
    assert.equal(s.loading,true);assert.equal(s.results.length,0);second.resolve(ok([item('new')],1));await b;
    assert.equal(s.option,'week');assert.equal(s.results[0].id,'new');assert.equal(s.loading,false);
  });
  await test('old source errors and late option metadata ignored; invalidate preserves committed rows',async()=>{
    const old=defer(),next=defer(),s=new Session();const a=s.start(source(data(()=>old.promise)));
    const b=s.start(source(data(()=>next.promise),'b'));old.reject(Error('old secret'));await a;assert.equal(s.loading,true);assert.equal(s.error,'');
    next.resolve(ok([item('new','b')],2));await b;s.invalidatePending();assert.equal(s.results.length,1);
    const metadata=defer(),d=data(async()=>{throw Error('old loader must not run')});d.optionsLoader=()=>metadata.promise;
    const c=s.start(source(d));await s.start(source(data(async()=>ok([item('current')],1))));metadata.resolve(ok(new Map([['bad','Bad']])));await c;
    assert.equal(s.option,'day');assert.equal(s.results[0].id,'current');
  });
  await test('rank-only category allowed and ranking navigation locks exact original source',async()=>{
    const routes=[],current={key:'eh',categoryData:{parts:[],enableRankingPage:true}},p=page('entry/src/main/ets/features/CategoryView.ets','CategoryView',{
      SourceManager:{find:key=>key==='eh'?current:undefined},router:{pushUrl:async value=>routes.push(value)}
    });p.selectedSourceKey='eh';await p.loadCategories();assert.equal(p.error,'');assert.equal(p.category.parts.length,0);p.openRanking();await tick();assert.equal(routes[0].params.sourceKey,'eh');assert.equal(routes[0].url,'pages/RankingPage');
    assert.match(read('entry/src/main/ets/features/CategoryView.ets'),/Button\('排行榜'\)/);
  });
  await test('page keeps entry source on retry/details and hide rejects late result',async()=>{
    const routes=[],src=source(data(async(o,p)=>ok([item('one')],2))),p=page('entry/src/main/ets/pages/RankingPage.ets','RankingPage',{
      RankingSession:Session,AppInit:{init:async()=>{}},SourceManager:{find:k=>k==='a'?src:undefined},router:{pushUrl:async value=>routes.push(value)}
    });p.params={sourceKey:'a'};await p.initialize();assert.equal(p.comics[0].sourceKey,'a');p.openComic(p.comics[0]);await tick();assert.equal(routes[0].params.sourceKey,'a');
    p.openComic(item('bad','other'));assert.equal(routes.length,1);const wait=defer();src.categoryComics.rankingData.load=()=>wait.promise;
    const request=p.action();assert.equal(p.loading,true);p.onPageHide();wait.resolve(ok([item('late')],2));await request;assert.equal(p.comics.length,1);assert.equal(p.loading,false);
    p.onPageShow();assert.equal(p.comics.length,1);assert.equal(p.disposed,false);
  });
  await test('page concurrent option changes ignore old errors/finally and same-option no-op cannot orphan spinner',async()=>{
    const src=source(data(async()=>ok([item('initial')],3))),p=page('entry/src/main/ets/pages/RankingPage.ets','RankingPage',{
      RankingSession:Session,AppInit:{init:async()=>{}},SourceManager:{find:()=>src}
    });p.params={sourceKey:'a'};await p.initialize();const old=defer(),current=defer();src.categoryComics.rankingData.load=o=>o==='week'?old.promise:current.promise;
    const a=p.action('week'),b=p.action('day');await p.action('day');old.reject(Error('late'));await a;assert.equal(p.loading,true);assert.equal(p.error,'');
    current.resolve(ok([item('current')],1));await b;assert.equal(p.loading,false);assert.equal(p.comics[0].id,'current');
  });
  await test('declared ranking missing methods is visible in production page; source never auto-replaced',async()=>{
    const finds=[],src=source(data(undefined,undefined),'broken'),p=page('entry/src/main/ets/pages/RankingPage.ets','RankingPage',{
      RankingSession:Session,AppInit:{init:async()=>{}},SourceManager:{find:key=>{finds.push(key);return key==='broken'?src:undefined}}
    });p.params={sourceKey:'broken'};await p.initialize();assert.equal(p.loading,false);assert.match(p.error,/load\/loadWithNext/);assert.equal(p.comics.length,0);assert.deepEqual(finds,['broken']);
    assert.match(read('entry/src/main/ets/pages/RankingPage.ets'),/ErrorView\(\{ message: this.error/);
    assert.match(read('entry/src/main/ets/pages/RankingPage.ets'),/enabled\(!this.loading && !this.ended\)/);
    const missing=page('entry/src/main/ets/pages/RankingPage.ets','RankingPage',{
      RankingSession:Session,AppInit:{init:async()=>{}},SourceManager:{find:key=>{finds.push(key);return undefined}}
    });missing.params={sourceKey:'removed'};await missing.initialize();assert.equal(missing.loading,false);assert.match(missing.error,/原始漫画源已不可用/);assert.equal(finds.at(-1),'removed');
  });
  console.log(`PASS ${count} production ranking adapter/session/UI-lifecycle cases; no SDK/device/network acceptance.`);
})().catch(error=>{fs.appendFileSync(log,error.stack+'\n');console.error(error);process.exitCode=1});
