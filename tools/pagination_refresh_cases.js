'use strict';
// Default: production .ets methods + deterministic local fixtures only. No SDK build,
// HTTP, device, login hooks, saved cookies, credentials or user database access.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/pagination-refresh-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'Production pagination methods; LOCAL FIXTURES ONLY; not device/site/login acceptance.\n');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const clean=s=>s.replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const load=f=>clean(read(f));
const page=(file,name,cut)=>{let s=load(file);s=s.slice(0,s.indexOf(cut))+'}';return s.replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct '+name,'class '+name)};
const tick=()=>new Promise(r=>setImmediate(r));
const deferred=()=>{let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j});return{promise,resolve,reject}};
const item=(id,key='')=>({id,sourceKey:key,title:id,cover:'',subtitle:''});
const plain=v=>JSON.parse(JSON.stringify(v));
function environment(){
 let sources=[];
 const c=vm.createContext({console,TextInputController:class{stopEditing(){}},
  SourceManager:{all:()=>sources,searchable:()=>sources.filter(s=>s.search),find:key=>sources.find(s=>s.key===key)},
  AppInit:{init:async()=>{}},SearchHistoryDao:{remember:async()=>{},list:async()=>[]},
  Settings:{getString:(k,d)=>d,setString:async()=>{}},promptAction:{showToast(){}},
  Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),warn(){},info(){}},router:{pushUrl:async()=>{}}});
 const files=['model/Res.ets','features/SourceFailure.ets','source/ComicSource.ets','features/SelectedSource.ets',
  'features/SearchFilterPolicy.ets','features/SearchSession.ets','features/AggregatedSearchSession.ets','features/AggregatedSearchList.ets'];
 let code=files.map(f=>load('entry/src/main/ets/'+f)).join('\n');
 code+='\n'+page('entry/src/main/ets/features/SearchView.ets','SearchView','  @Builder');
 code+='\n'+page('entry/src/main/ets/features/ExploreView.ets','ExploreView','  @Builder');
 code+='\n'+page('entry/src/main/ets/pages/CategoryComicsPage.ets','CategoryComicsPage','  build() {');
 vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Types={SearchView,ExploreView,CategoryComicsPage,Res,SelectedSource};',c);
 return{c,types:c.Types,setSources:s=>{sources=s},ok:(v,next)=>new c.Types.Res(v,undefined,next)};
}
function fixture(kind,loader,cursorOnly=false){
 const e=environment();
 function source(key,fn){const s={key,name:key,explorePages:[]};
  const search={cursorOnly,loadPage:async(k,p,o)=>fn(p,{keyword:k,options:plain(o),key}),
   loadNext:async(k,next,o)=>fn(next,{keyword:k,options:plain(o),key})};
  if(kind==='explore')s.explorePages=[{cursorOnly,type:0,loadPage:p=>fn(p,{key}),loadNext:next=>fn(next,{key})}];
  else if(kind==='category'&&!cursorOnly)s.categoryComics={options:[],load:(cat,param,o,p)=>fn(p,{category:cat,param,options:plain(o),key})};
  else s.search=search;return s;}
 let active=source('a',loader);e.setSources([active]);
 const p=new e.types[kind==='search'?'SearchView':kind==='explore'?'ExploreView':'CategoryComicsPage']();
 function select(key){if(kind==='category')p.params={sourceKey:key,label:'tag',page:cursorOnly?'search':'category',category:'cat',param:'param',keyword:'query',options:['filter']};
  else {p.selectedSourceKey=key;if(kind==='search'){p.filtersSourceKey=key;p.keyword='query';p.filterGroups=[];p.filterValues=[];}}}
 // Category initial options require one declared option when using a category target.
 if(kind==='category'&&!cursorOnly)active.categoryComics.options=[{label:'order',options:new Map([['filter','Filter']]),notShowWhen:[]}];
 select('a');if(kind==='explore')p.initialized=true;
 const first=()=>kind==='search'?p.doSearch():kind==='explore'?p.loadPage(1):p.load(1,true);
 const more=()=>kind==='search'?p.loadMore():kind==='explore'?p.loadPage(p.currentPage+1):p.load(p.currentPage+1);
 const rows=()=>kind==='search'?p.results:p.comics;
 const ended=()=>kind==='search'?p.ended:kind==='explore'?!p.hasMore:p.ended;
 const committed=()=>kind==='search'?p.session.page:p.currentPage;
 const pending=()=>kind==='search'?p.loadingMore:p.loading;
 function switchSource(fn){active=source('b',fn);if(kind==='category'&&!cursorOnly)active.categoryComics.options=[{label:'order',options:new Map([['filter','Filter']]),notShowWhen:[]}];e.setSources([active]);select('b');return first();}
 return{e,p,first,more,rows,ended,committed,pending,switchSource,active};
}
let count=0,finished=false;const EXPECTED=49;
process.on('beforeExit',()=>{if(!finished){console.error(`PAGINATION_INCOMPLETE count=${count}/${EXPECTED}`);process.exitCode=1}});
async function test(name,fn){let timer;try{await Promise.race([Promise.resolve().then(fn),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('ASYNC_WATCHDOG '+name)),4000)})]);count++;fs.appendFileSync(log,'PASS '+name+'\n')}finally{clearTimeout(timer)}}
const inventory=[];
(async()=>{
 for(const kind of ['search','explore','category']){
  await test(kind+' page 1,2,3 via actual reachEnd and maxPage gate',async()=>{
   const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok([item('p'+p)],3)});
   await f.first();f.p.reachEnd();await tick();f.p.reachEnd();await tick();f.p.reachEnd();await tick();
   assert.deepEqual(calls,[1,2,3]);assert.equal(f.committed(),3);assert.equal(f.ended(),true);assert.equal(f.rows().length,3);
  });
  await test(kind+' maxPage zero and short first page remain pageable through third',async()=>{
   const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok(p<=3?[item('p'+p)]:[],0)});
   await f.first();assert.equal(f.ended(),false);await f.more();await f.more();assert.equal(f.rows().length,3);assert.equal(f.ended(),false);
   await f.more();assert.equal(f.ended(),true);assert.deepEqual(calls,[1,2,3,4]);
  });
  await test(kind+' absent/zero/string zero/negative/nonfinite max does not mean EOF',async()=>{
   for(const max of [undefined,0,'0',-1,'invalid',Infinity]){let f;f=fixture(kind,async p=>f.e.ok([item('p'+p)],max));await f.first();await f.more();await f.more();assert.equal(f.rows().length,3);assert.equal(f.ended(),false);}
  });
  await test(kind+' dedup normalize source and pause duplicate-only automatic paging without false EOF',async()=>{
   const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok(p<3?[item('same'),item('same','a')]:[item('third')],0)});
   await f.first();await f.more();assert.equal(f.rows().length,1);assert.equal(f.ended(),false);assert.equal(f.committed(),2);
   f.p.reachEnd();await tick();assert.deepEqual(calls,[1,2]);await f.more();assert.equal(f.rows().length,2);assert.deepEqual(calls,[1,2,3]);
  });
  await test(kind+' append error retains results and explicit retry requests same page',async()=>{
   const calls=[];let fail=true,f;f=fixture(kind,async p=>{calls.push(p);if(p===2&&fail)throw Error('fixture timeout');return f.e.ok([item('p'+p)],3)});
   await f.first();const pending=f.more();assert.equal(f.pending(),true);await pending;assert.equal(f.rows().length,1);assert.equal(f.committed(),1);assert.ok(f.p.error);
   f.p.reachEnd();await tick();assert.deepEqual(calls,[1,2]);fail=false;await f.more();assert.equal(f.p.error,'');assert.deepEqual(calls,[1,2,2]);
  });
  await test(kind+' synchronous loading gate prevents concurrent next requests',async()=>{
   const gate=deferred(),calls=[];let f;f=fixture(kind,p=>{calls.push(p);return p===1?Promise.resolve(f.e.ok([item('one')],3)):gate.promise});
   await f.first();const pending=f.more();await f.more();f.p.reachEnd();await tick();assert.deepEqual(calls,[1,2]);gate.resolve(f.e.ok([item('two')],3));await pending;
  });
  await test(kind+' source switch discards stale page-one success',async()=>{
   const gate=deferred();let f;f=fixture(kind,()=>gate.promise);const old=f.first();await tick();await f.switchSource(async()=>f.e.ok([item('new','b')],1));
   gate.resolve(f.e.ok([item('old','a')],3));await old;assert.deepEqual(plain(f.rows()).map(c=>c.id),['new']);assert.equal(f.p.error,'');
  });
  await test(kind+' source switch discards old append rejection and finally',async()=>{
   const oldGate=deferred(),newGate=deferred();let f;f=fixture(kind,p=>p===1?Promise.resolve(f.e.ok([item('old')],3)):oldGate.promise);
   await f.first();const old=f.more();await tick();const current=f.switchSource(()=>newGate.promise);await tick();oldGate.reject(Error('old fixture error'));await old;
   assert.equal(f.p.loading,true);assert.equal(f.p.error,'');newGate.resolve(f.e.ok([item('new','b')],1));await current;assert.equal(f.rows()[0].id,'new');assert.equal(f.p.loading,false);
  });
  await test(kind+' leaving cancels pending writes and returning can retry unchanged page',async()=>{
   const gate=deferred();let f,fail=true;f=fixture(kind,p=>p===1?Promise.resolve(f.e.ok([item('one')],3)):fail?gate.promise:Promise.resolve(f.e.ok([item('two')],3)));
   await f.first();const pending=f.more();await tick();f.p.aboutToDisappear();gate.resolve(f.e.ok([item('late')],3));await pending;
   assert.equal(f.rows().length,1);assert.equal(f.pending(),false);f.p.disposed=false;fail=false;await f.more();assert.equal(f.rows()[1].id,'two');
  });
  await test(kind+' cursor first then exact opaque second/third cursor and terminal null',async()=>{
   const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok([item('p'+calls.length)],p===1?'cursor-2':p==='cursor-2'?'cursor-3':null)},true);
   await f.first();await f.more();await f.more();assert.deepEqual(calls,[1,'cursor-2','cursor-3']);assert.equal(f.rows().length,3);assert.equal(f.ended(),true);
  });
 }
 await test('all pagers reject missing payload and missing stable IDs without advancing',async()=>{
  for(const kind of ['search','explore','category'])for(const malformed of [undefined,[item('')]]){
   let f;f=fixture(kind,async p=>f.e.ok(p===1?[item('one')]:malformed,3));await f.first();await f.more();assert.ok(f.p.error);assert.equal(f.committed(),1);assert.equal(f.rows().length,1);
  }
 });
 await test('explore/category page and disposed gates reject jumps or hidden requests',async()=>{
  for(const kind of ['explore','category']){const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok([item('p'+p)],4)});
   const load=p=>kind==='explore'?f.p.loadPage(p):f.p.load(p);await load(2);assert.equal(calls.length,0);await f.first();await load(3);assert.deepEqual(calls,[1]);f.p.disposed=true;await load(2);assert.deepEqual(calls,[1]);}
 });
 await test('explicit single-part explore contract does not invent extra pages',async()=>{
  for(const type of [1]){const calls=[];let f;f=fixture('explore',async p=>{calls.push(p);return f.e.ok([item('one')],0)});f.active.explorePages[0].type=type;await f.first();await f.more();assert.equal(f.ended(),true);assert.deepEqual(calls,[1]);}
 });
 await test('all three bounded result Grids wire native reach-end plus explicit retry/more controls',async()=>{
  for(const file of ['features/SearchView.ets','features/ExploreView.ets','pages/CategoryComicsPage.ets']){const s=read('entry/src/main/ets/'+file);assert.match(s,/\.onReachEnd\(\(\) => \{ this\.reachEnd\(\); \}\)/);assert.match(s,/\.layoutWeight\(1\)/);assert.match(s,/height\('100%'\)/);assert.match(s,/加载更多/);assert.match(s,/重试/);assert.doesNotMatch(s,/boundScroll|WaterFall/);}
 });
 await test('shared selection and category original-source lock/ranking entry remain intact',async()=>{
  const e=environment();e.setSources([{key:'a'},{key:'b'}]);const seen=[],id=e.types.SelectedSource.subscribe(k=>seen.push(k));e.types.SelectedSource.select('b');assert.deepEqual(seen,['b']);e.types.SelectedSource.unsubscribe(id);
  const category=read('entry/src/main/ets/features/CategoryView.ets');assert.match(category,/RankingPage/);assert.match(category,/SelectedSource/);
  const f=fixture('category',async()=>f.e.ok([item('locked')],1));e.types.SelectedSource.select('b');await f.first();assert.equal(f.rows()[0].sourceKey,'a');
 });
 await test('all pagers repeated opaque cursor terminates without looping',async()=>{
  for(const kind of ['search','explore','category']){const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok([item('p'+calls.length)],'repeat')},true);await f.first();await f.more();await f.more();assert.equal(f.ended(),true);assert.deepEqual(calls,[1,'repeat']);}
 });
 await test('all pagers cursor append failures retry exact cursor without discarding prior results',async()=>{
  for(const kind of ['search','explore','category']){const calls=[];let fail=true,f;f=fixture(kind,async p=>{calls.push(p);if(p==='opaque'&&fail)throw Error('fixture timeout');return f.e.ok([item('p'+calls.length)],p===1?'opaque':null)},true);
   await f.first();await f.more();assert.equal(f.committed(),1);assert.equal(f.rows().length,1);fail=false;await f.more();assert.deepEqual(calls,[1,'opaque','opaque']);assert.equal(f.rows().length,2);assert.equal(f.ended(),true);}
 });
 await test('explore section switch discards old section cursor and loading finally',async()=>{
  const oldGate=deferred(),newGate=deferred();let f;f=fixture('explore',()=>oldGate.promise,true);
  f.active.explorePages.push({cursorOnly:true,type:0,loadPage:()=>newGate.promise});const old=f.first();f.p.pageIndex=1;const current=f.first();oldGate.resolve(f.e.ok([item('old')],'old-cursor'));await old;
  assert.equal(f.p.loading,true);assert.equal(f.rows().length,0);newGate.resolve(f.e.ok([item('new')],'new-cursor'));await current;assert.equal(f.p.nextCursor,'new-cursor');assert.equal(f.rows()[0].id,'new');
 });
 await test('all pagers refresh same source invalidates old first-page response',async()=>{
  for(const kind of ['search','explore','category']){const oldGate=deferred();let calls=0,f;f=fixture(kind,()=>++calls===1?oldGate.promise:Promise.resolve(f.e.ok([item('fresh')],3)));
   const old=f.first();await tick();await f.first();oldGate.resolve(f.e.ok([item('old')],1));await old;assert.equal(f.rows()[0].id,'fresh');assert.equal(f.ended(),false);}
 });
 await test('all pagers first-page error clears loading and can be explicitly retried',async()=>{
  for(const kind of ['search','explore','category']){let fail=true,f;f=fixture(kind,async()=>{if(fail)throw Error('fixture offline');return f.e.ok([item('recovered')],3)});
   await f.first();assert.ok(f.p.error);assert.equal(f.p.loading,false);assert.equal(f.rows().length,0);fail=false;await f.first();assert.equal(f.p.error,'');assert.equal(f.rows()[0].id,'recovered');}
 });
 await test('search filter change cancels old pending page before fresh search',async()=>{
  const gate=deferred();let f;f=fixture('search',()=>gate.promise);const old=f.first();await tick();f.p.changeFilter(0,'invalid');
  // A real valid filter selection uses the production policy and cancels the session.
  f.p.filterGroups=[{label:'sort',type:'select',options:new Map([['new','New'],['old','Old']])}];f.p.filterValues=['old'];f.p.filterError='';f.p.changeFilter(0,'new');
  gate.resolve(f.e.ok([item('old')],3));await old;assert.equal(f.rows().length,0);assert.equal(f.p.searched,false);assert.equal(f.p.filterValues[0],'new');
 });
 await test('automatic callbacks after disposal or unavailable search source cannot request more',async()=>{
  for(const kind of ['search','explore','category']){const calls=[];let f;f=fixture(kind,async p=>{calls.push(p);return f.e.ok([item('p'+p)],3)});await f.first();f.p.aboutToDisappear();f.p.reachEnd();await tick();assert.deepEqual(calls,[1]);}
  const calls=[];let f;f=fixture('search',async p=>{calls.push(p);return f.e.ok([item('p'+p)],3)});await f.first();f.e.setSources([]);await f.more();assert.deepEqual(calls,[1]);
 });
 await test('queued reach-end during initial or refreshed first page never duplicates page one',async()=>{
  for(const kind of ['search','explore','category']){const gate=deferred(),calls=[];let f;f=fixture(kind,p=>{calls.push(p);return gate.promise});
   const first=f.first();await tick();f.p.reachEnd();await tick();assert.deepEqual(calls,[1]);gate.resolve(f.e.ok([item('one')],3));await first;assert.equal(f.committed(),1);}
 });
 // Existing public scripts only; no init()/login()/validate()/web callbacks invoked.
 // Production parser's scheduled init is explicitly suppressed and counted.
 const expected={wnacg:{settings:4,password:true},ehentai:{settings:3,web:true,cookie:4},Komiic:{settings:0,password:true},manwaba:{settings:0},shonen_jump_plus:{settings:0},ykmh:{settings:0}};
 for(const [key,want] of Object.entries(expected))await test('public metadata inventory '+key+' parser/settings read without auth or network',async()=>{
  const deps=require('./vm_deps'),data=new Map();let scheduled=0,networkCalls=0;
  const blocked=()=>{networkCalls++;throw Error('Network forbidden in metadata fixture')};
  const c=vm.createContext({Map,JSON,ArrayBuffer,Uint8Array,console,APP_VERSION:'1.17.0',randomInt:()=>0,
   setTimeout:()=>{scheduled++;return 0},Network:new Proxy({},{get:()=>blocked}),fetch:blocked,
   SourceDataStore:{get:()=>null,set:(k,n,v)=>data.set(k+'\0'+n,v)},CookieJar:{},
   Log:{audit(){},warn(){},info(){}},});
  c.JsEngine={isAvailable:true,evaluate:code=>String(vm.runInContext(code,c,{timeout:1000})),callJson:async code=>await vm.runInContext(code,c,{timeout:1000})};
  vm.runInContext(stripTypeScriptTypes(deps.join(deps.SOURCE_FILES)+'\n'+load('entry/src/main/ets/source/SourceSettings.ets'),{mode:'transform'})+'\nComicSource.sources={};globalThis.Parser=ComicSourceParser;globalThis.ReadSettings=SourceSettings;',c);
  const file='logs/user8-installed-scripts/'+key+'.js',script=read(file),source=await c.Parser.parse(script,'<public-script-fixture>');
  const settings=await c.ReadSettings.read(key,'metadata-only');assert.equal(settings.length,want.settings);assert.ok(settings.every(f=>f.schemaError===''));
  const modes={password:typeof source.account?.login==='function',web:typeof source.account?.finishWebLogin==='function',cookieFields:source.account?.cookieFields?.length??0};
  assert.equal(modes.password,!!want.password);assert.equal(modes.web,!!want.web);assert.equal(modes.cookieFields,want.cookie??0);
  assert.equal(typeof source.account?.validateCookies==='function',!!want.cookie);
  assert.equal(source.account?.canLogin??false,!!(want.password||want.web||want.cookie));assert.equal(networkCalls,0);
  inventory.push({key,file,settings:settings.map(f=>({key:f.key,type:f.type})),declaredModes:modes,verified:'production parser wiring + read-only settings metadata in local VM only',realLoginTested:false,networkCalls,scheduledInitSuppressed:scheduled});
 });
 fs.writeFileSync(path.join(root,'logs/pagination-source-capabilities.json'),JSON.stringify({scope:'six existing public script fixtures; not device-installed enumeration',sources:inventory,counts:{sources:6,settings:2,settingsFields:7,accounts:3,password:2,web:1,cookie:1,realLoginTested:0}},null,2)+'\n');
 assert.equal(count,EXPECTED,'final test count must match the fixed finish guard');finished=true;
 const report=`PASS ${count}/${EXPECTED} pagination refresh cases; local production-method fixtures only; real logins tested=0.`;fs.appendFileSync(log,report+'\n');console.log(report);
})().catch(error=>{console.error(error);fs.appendFileSync(log,String(error.stack)+'\n');process.exitCode=1});
