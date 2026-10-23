'use strict';
// Actual production DTO/adapter/policy/session/view methods with controlled fixtures.
// No SDK, phone, accounts or real HTTP evidence is produced by this test.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const log=path.join(root,'logs/search-filters-cases.log');fs.writeFileSync(log,'Production search filters; controlled JS metadata + UI SDK fakes; no network/device.\n');
const read=f=>fs.readFileSync(path.join(root,f),'utf8').replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const tick=()=>new Promise(r=>setImmediate(r));
function deferred(){let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j});return{promise,resolve,reject}}
function env(){
 let sources=[];const calls=[],audits=[];
 const c=vm.createContext({Map,JSON,ArrayBuffer,Uint8Array,console,TextInputController:class{stopEditing(){}},
  SourceManager:{searchable:()=>sources.filter(s=>s.search?.loadPage),all:()=>sources,find:k=>sources.find(s=>s.key===k)},AppInit:{init:async()=>{}},
  SearchHistoryDao:{remember:async()=>{},list:async()=>[],remove:async()=>{},clear:async()=>{}},SearchHistoryEntry:class{},
  // SelectedSource persists the shared selection through Settings.
  Settings:{getString:(key,fallback)=>fallback,setString:async()=>{}},promptAction:{showToast(){}},
  // The search page now shares SelectedSource with explore/category and hosts
  // aggregated search inline, so the harness loads those production modules too.
  Log:{audit:(...v)=>audits.push(v),warn(){},info(){}},router:{pushUrl:async()=>{}},promptAction:{showToast(){}}});
 const view=read('entry/src/main/ets/features/SearchView.ets').split('  @Builder')[0]+'}';
 const code=read('entry/src/main/ets/model/Res.ets')+'\n'+read('entry/src/main/ets/source/ComicSource.ets')+'\n'+
  read('entry/src/main/ets/source/JsSearchOptionsAdapter.ets')+'\n'+read('entry/src/main/ets/features/SearchFilterPolicy.ets')+'\n'+
  read('entry/src/main/ets/features/SourceFailure.ets')+'\n'+
  read('entry/src/main/ets/features/SearchSession.ets')+'\n'+
  read('entry/src/main/ets/features/AggregatedSearchSession.ets')+'\n'+
  read('entry/src/main/ets/features/AggregatedSearchList.ets')+'\n'+
  read('entry/src/main/ets/features/SelectedSource.ets')+'\n'+
  view.replace(/@Component\s*|@State\s*/g,'').replace('struct SearchView','class SearchView');
 vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nComicSource.sources={};globalThis.DTO=SearchOptions;globalThis.Result=Res;globalThis.Adapter=JsSearchOptionsAdapter;globalThis.Policy=SearchFilterPolicy;globalThis.Session=SearchSession;globalThis.View=SearchView;globalThis.Sources=ComicSource;globalThis.Shared=SelectedSource;globalThis.Aggregate=AggregatedSearchSession;globalThis.AggregateList=AggregatedSearchList;',c);
 c.JsEngine={callJson:async(code,name,trace)=>{calls.push({name,trace});return await vm.runInContext(code,c)}};
 return{c,calls,audits,sources:v=>{sources=v},view:()=>new c.View()};
}
let count=0,finished=false;const EXPECTED=25;
async function test(name,body){let timer;try{await Promise.race([Promise.resolve().then(body),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),3000)})]);count++;fs.appendFileSync(log,'PASS '+name+'\n')}finally{clearTimeout(timer)}}
process.on('beforeExit',()=>{if(!finished){console.error('SEARCH_FILTERS_INCOMPLETE count='+count);process.exitCode=1}});
const plain=v=>JSON.parse(JSON.stringify(v));
const item=(id,key='fixture')=>({id,sourceKey:key,title:id,cover:'https://example.invalid/x'});
async function options(e){
 vm.runInContext(`ComicSource.sources.fixture={search:{optionList:[
  {label:'Categories',type:'multi-select',options:['0-Misc','1-One-with-dash','2-Two'],default:['0','1']},
  {label:'Order',options:['latest-Latest','popular-Popular']},
  {label:'Language',type:'dropdown',options:['-Any','en-English','zh-Chinese'],default:''}
 ]}};`,e.c);
 const r=await e.c.Adapter.load('fixture','<fixture>');assert.equal(r.error,false);return r.dataOrNull;
}
(async()=>{
 await test('adapter parses all three types first dash empty key and JSON multi default',async()=>{
  const e=env(),groups=await options(e);assert.equal(groups.length,3);assert.equal(groups[0].options.get('1'),'One-with-dash');assert.equal(groups[2].options.has(''),true);assert.equal(groups[0].defaultVal,'["0","1"]');assert.equal(groups[1].type,'select');
  assert.deepEqual(plain(e.c.Policy.defaults(groups)),['["0","1"]','latest','']);
 });
 await test('multi-select toggles exactly ordered JSON, reset restores declared values',async()=>{
  const e=env(),g=await options(e),initial=e.c.Policy.defaults(g);let changed=e.c.Policy.change(g,initial,0,'1');
  assert.deepEqual(plain(changed),['["0"]','latest','']);changed=e.c.Policy.change(g,changed,0,'2');assert.equal(changed[0],'["0","2"]');
  assert.equal(e.c.Policy.selected(g[0],changed[0],'2'),true);assert.equal(initial[0],'["0","1"]');assert.deepEqual(plain(e.c.Policy.defaults(g)),plain(initial));
 });
 await test('empty multi selection stays [] and no-filter dropdown stays empty string',async()=>{
  const e=env(),g=await options(e);let v=e.c.Policy.defaults(g);v=e.c.Policy.change(g,v,0,'0');v=e.c.Policy.change(g,v,0,'1');assert.equal(v[0],'[]');
  v=e.c.Policy.change(g,v,2,'zh');assert.equal(v[2],'zh');v=e.c.Policy.change(g,v,2,'');assert.equal(v[2],'');
 });
 await test('invalid source type/options/default or changed positional values fail explicitly',async()=>{
  const e=env(),g=await options(e);assert.throws(()=>e.c.Policy.validate(g,['[]']));assert.throws(()=>e.c.Policy.change(g,e.c.Policy.defaults(g),1,'missing'));
  g[0].defaultVal='["not-present"]';assert.throws(()=>e.c.Policy.defaults(g));
  for(const raw of ['{type:"unknown",options:["a-A"]}','{type:"multi-select",options:42}','{options:[3]}']){
   vm.runInContext('ComicSource.sources.fixture.search.optionList=['+raw+']',e.c);const result=await e.c.Adapter.load('fixture','<fixture>');assert.equal(result.error,true);
  }
 });
 await test('source getter failure returns redacted metadata error no source exception text in audit',async()=>{
  const e=env();vm.runInContext('ComicSource.sources.fixture={search:{get optionList(){throw Error("PRIVATE_TOKEN_BODY")}}}',e.c);
  const result=await e.c.Adapter.load('fixture','<fixture>');assert.equal(result.error,true);assert.doesNotMatch(result.errorMessage,/PRIVATE_TOKEN_BODY/);assert.doesNotMatch(JSON.stringify(e.audits),/PRIVATE_TOKEN_BODY/);
 });
 await test('submitted options snapshot survives caller and source mutations on page pagination',async()=>{
  const e=env(),calls=[],s=new e.c.Session(),source={key:'fixture',search:{loadPage:async(k,p,o)=>{calls.push([k,p,[...o]]);o[0]='source-mutated';return new e.c.Result([item(String(p))],undefined,3)}}};
  const selected=['["1"]','latest',''];await s.start(source,'term',selected);selected[0]='caller-mutated';await s.more();
  assert.deepEqual(calls,[['term',1,['["1"]','latest','']],['term',2,['["1"]','latest','']]]);
 });
 await test('cursor pagination retains identical filters and opaque cursor; page1 default never overwrites',async()=>{
  const e=env(),calls=[],s=new e.c.Session(),source={key:'fixture',search:{cursorOnly:true,
   loadPage:async(k,p,o)=>{calls.push([p,[...o]]);return new e.c.Result([item('first')],undefined,'opaque?token=not-logged')},
   loadNext:async(k,n,o)=>{calls.push([n,[...o]]);return new e.c.Result([item('second')],undefined,undefined)}}};
  await s.start(source,'term',['[]','popular','zh']);await s.more();assert.deepEqual(calls,[[1,['[]','popular','zh']],['opaque?token=not-logged',['[]','popular','zh']]]);assert.equal(s.ended,true);
 });
 await test('later filtered query wins over stale previous result and finally',async()=>{
  const e=env(),gate=deferred(),s=new e.c.Session();const old={key:'old',search:{loadPage:()=>gate.promise}},current={key:'new',search:{loadPage:async()=>new e.c.Result([item('current','new')],undefined,1)}};
  const first=s.start(old,'same',['old']);await s.start(current,'same',['new']);gate.resolve(new e.c.Result([item('stale','old')],undefined,1));await first;
  assert.equal(s.sourceKey,'new');assert.equal(s.results[0].id,'current');assert.equal(s.loading,false);
 });
 await test('UI source change discards late old option defaults, no network on chip changes',async()=>{
  const e=env(),old=deferred(),g=await options(e);const a={key:'a',name:'A',search:{loadPage:async()=>new e.c.Result([]),optionsLoader:()=>old.promise}},b={key:'b',name:'B',search:{loadPage:async()=>new e.c.Result([]),searchOptions:g}};
  e.sources([a,b]);const p=e.view();p.loadSources();assert.equal(p.filterLoading,true);
  // Dropdown index 0 is the aggregated entry, so source 'b' is index 2.
  p.selectSource(2);await tick();assert.equal(p.selectedSourceKey,'b');assert.deepEqual(plain(p.filterValues),['["0","1"]','latest','']);
  old.resolve(new e.c.Result([]));await tick();assert.equal(p.filterGroups.length,3);assert.equal(p.filtersSourceKey,'b');p.changeFilter(0,'1');assert.equal(p.session.searched,false);assert.equal(p.filterValues[0],'["0"]');
 });
 await test('UI source key survives ordering changes, removed source does not silently substitute',async()=>{
  const e=env(),a={key:'a',name:'A',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}},b={key:'b',name:'B',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}};
  e.sources([a,b]);const p=e.view();p.loadSources();await tick();e.sources([b,a]);p.loadSources();assert.equal(p.selectedSourceKey,'a');assert.equal(p.selectedIndex,2);
  // A removed source must not make search change the shared user selection.
  e.sources([b]);p.loadSources();await tick();assert.equal(p.selectedSourceKey,'a');assert.equal(e.c.Shared.current(),'a');assert.equal(p.selectedIndex,-1);assert.match(p.error+' '+p.filterError,/已移除/);
 });
 await test('UI invalid filter metadata blocks search and visible retry recovers',async()=>{
  const e=env();let fail=true,requests=0;const source={key:'fixture',name:'Fixture',search:{optionsLoader:async()=>fail?e.c.Result.fail('private'):new e.c.Result([]),loadPage:async()=>{requests++;return new e.c.Result([item('ok')],undefined,1)}}};
  e.sources([source]);const p=e.view();p.loadSources();await tick();await p.doSearch();assert.equal(requests,0);assert.ok(p.filterError.length>0);fail=false;await p.reloadFilters();await p.doSearch();assert.equal(requests,1);assert.equal(p.results[0].id,'ok');
 });
 await test('disposed view drops option load and stale initialization without updating another page',async()=>{
  const e=env(),gate=deferred();e.sources([{key:'fixture',name:'Fixture',search:{optionsLoader:()=>gate.promise,loadPage:async()=>new e.c.Result([])}}]);
  const p=e.view();p.loadSources();p.aboutToDisappear();gate.resolve(new e.c.Result([]));await tick();assert.equal(p.filtersSourceKey,'');assert.equal(p.filterLoading,false);
 });
 await test('aggregated entry displays selected index and returning to same source works',async()=>{
  const e=env(),a={key:'a',name:'A',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}};e.sources([a]);const p=e.view();p.loadSources();await tick();
  p.selectSource(0);assert.equal(p.aggregated,true);assert.equal(p.selectedIndex,0);p.selectSource(1);await tick();assert.equal(p.aggregated,false);assert.equal(p.selectedIndex,1);assert.equal(e.c.Shared.current(),'a');
 });
 await test('nonsearchable installed source stays selected without silently changing shared source',async()=>{
  const e=env(),unsupported={key:'no-search',name:'No Search'},a={key:'a',name:'A',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}};e.sources([unsupported,a]);e.c.Shared.select('no-search');const p=e.view();p.loadSources();await tick();
  assert.equal(p.selectedSourceKey,'no-search');assert.equal(e.c.Shared.current(),'no-search');assert.equal(p.selectedIndex,1);assert.equal(p.sourceOptions[1],'No Search');assert.match(p.error+' '+p.filterError,/不支持搜索/);
 });
 await test('eight selected sources all start without artificial concurrency ceiling and failures remain isolated',async()=>{
  const e=env(),gates=Array.from({length:8},deferred),started=[],sources=gates.map((gate,i)=>({key:'g'+i,name:'G'+i,search:{loadPage:async()=>{started.push(i);return gate.promise}}}));
  const session=new e.c.Aggregate(),pending=session.start(sources,'term');await tick();assert.equal(started.length,8);gates.forEach((gate,i)=>gate.resolve(i===3?e.c.Result.fail('HTTP 403'):new e.c.Result([item(String(i),'g'+i)],undefined,1)));await pending;
  assert.equal(session.groups.length,8);assert.equal(session.groups[3].status,'failed');assert.equal(session.groups[7].status,'ready');assert.equal(session.running,false);
 });
 await test('search explore and category production views all follow one key in every direction',async()=>{
  const e=env();const make=(key)=>{const s=new e.c.Sources(key,key);s.search={searchOptions:[],loadPage:async()=>new e.c.Result([item(key,key)],undefined,1)};s.explorePages=[{title:key,type:0,loadPage:async()=>new e.c.Result([item(key,key)],undefined,1)}];s.categoryData={parts:[{title:'Part',items:[{label:'Tag'}]}]};return s};
  e.sources([make('a'),make('b')]);
  const load=(file,name,cut)=>{const code=(read(file).split(cut)[0]+'}').replace(/@Component\s*|@State\s*/g,'').replace('struct '+name,'class '+name);vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.'+name+'Export='+name+';',e.c);return e.c[name+'Export']};
  const Explore=load('entry/src/main/ets/features/ExploreView.ets','ExploreView','  @Builder'),Category=load('entry/src/main/ets/features/CategoryView.ets','CategoryView','  build() {');const p=e.view(),x=new Explore(),c=new Category();p.aboutToAppear();x.aboutToAppear();c.aboutToAppear();await tick();await tick();
  p.selectSource(2);await tick();assert.deepEqual([p.selectedSourceKey,x.selectedSourceKey,c.selectedSourceKey],['b','b','b']);e.c.Shared.select('a');await tick();assert.deepEqual([p.selectedSourceKey,x.selectedSourceKey,c.selectedSourceKey],['a','a','a']);
  p.aboutToDisappear();x.aboutToDisappear();c.aboutToDisappear();
 });
 await test('late single-source option metadata cannot disable or replace active aggregate mode',async()=>{
  const e=env(),metadata=deferred(),response=deferred(),s={key:'a',name:'A',search:{optionsLoader:()=>metadata.promise,loadPage:()=>response.promise}};e.sources([s]);const p=e.view();p.loadSources();p.selectSource(0);const query=p.doSearch();await tick();assert.equal(p.selectedIndex,0);
  metadata.resolve(new e.c.Result([]));await tick();assert.equal(p.aggregated,true);assert.equal(p.filterLoading,false);response.resolve(new e.c.Result([item('ok','a')],undefined,1));await query;assert.equal(p.groups[0].status,'ready');
 });
 await test('old aggregate await completion cannot clear newer single-source loading',async()=>{
  const e=env(),aGate=deferred(),bGate=deferred(),a={key:'a',name:'A',search:{searchOptions:[],loadPage:()=>aGate.promise}},b={key:'b',name:'B',search:{searchOptions:[],loadPage:()=>bGate.promise}};e.sources([a,b]);const p=e.view();p.loadSources();p.selectSource(0);const aggregate=p.doSearch();await tick();p.selectSource(2);await tick();const single=p.doSearch();assert.equal(p.loading,true);await aggregate;assert.equal(p.loading,true);aGate.resolve(new e.c.Result([item('old','a')],undefined,1));bGate.resolve(new e.c.Result([item('new','b')],undefined,1));await single;assert.equal(p.results[0].id,'new');assert.equal(p.groups.length,0);
 });
 await test('restarting aggregate query keeps only current keyword groups after old completion',async()=>{
  const e=env(),gates={old:deferred(),next:deferred()};e.sources([{key:'a',name:'A',search:{searchOptions:[],loadPage:(keyword)=>gates[keyword].promise}}]);const p=e.view();p.loadSources();p.selectSource(0);p.keyword='old';const first=p.doSearch();p.keyword='next';const next=p.doSearch();await first;assert.equal(p.loading,true);gates.next.resolve(new e.c.Result([item('next','a')],undefined,1));await next;gates.old.resolve(new e.c.Result([item('old','a')],undefined,1));await tick();assert.equal(p.groups[0].results[0].id,'next');
 });
 await test('repeated search appear keeps exactly one shared selection listener',async()=>{
  const e=env();let calls=0;const a={key:'a',name:'A',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}},b={key:'b',name:'B',search:{optionsLoader:async()=>{calls++;return new e.c.Result([])},loadPage:async()=>new e.c.Result([])}};e.sources([a,b]);const p=e.view();p.aboutToAppear();await tick();p.aboutToAppear();await tick();e.c.Shared.select('b');await tick();assert.equal(calls,1);p.aboutToDisappear();
 });
 await test('aggregate applies each sources own default options without sharing filter arrays',async()=>{
  const e=env(),g=await options(e),seen=[];const sources=['a','b'].map(key=>({key,name:key,search:{searchOptions:g,loadPage:async(k,p,o)=>{seen.push([key,[...o]]);o[0]='mutated';return new e.c.Result([item(key,key)],undefined,1)}}}));await new e.c.Aggregate().start(sources,'term');assert.equal(seen.length,2);assert.deepEqual(seen[0][1],['["0","1"]','latest','']);assert.deepEqual(seen[1][1],seen[0][1]);
 });
 await test('throwing UI observer never hides successful sources or prevents aggregate completion',async()=>{
  const e=env(),session=new e.c.Aggregate();await session.start([{key:'a',name:'A',search:{loadPage:async()=>new e.c.Result([item('ok','a')],undefined,1)}}],'term',()=>{throw Error('UI-private-message')});assert.equal(session.groups[0].status,'ready');assert.equal(session.running,false);assert.doesNotMatch(JSON.stringify(e.audits),/UI-private-message/);
 });
 await test('aggregate local list updates only changed source and retains other decoded-card identity',async()=>{
  const e=env(),list=new e.c.AggregateList(),events=[];list.registerDataChangeListener({onDataReloaded:()=>events.push('reload'),onDataChanged:i=>events.push(i)});const groups=[{sourceKey:'a',sourceName:'A',status:'loading',error:'',results:[]},{sourceKey:'b',sourceName:'B',status:'loading',error:'',results:[]}];list.update(groups);const keep=list.getData(1);events.length=0;groups[0].status='ready';groups[0].results=[item('ok','a')];list.update(groups);assert.deepEqual(events,[0]);assert.strictEqual(list.getData(1),keep);
 });
 await test('aggregate more uses committed keyword and exact entry source, not input draft',async()=>{
  const e=env(),routes=[];e.sources([{key:'a',name:'A',search:{loadPage:async()=>new e.c.Result([])}}]);e.c.router.pushUrl=async route=>{routes.push(route)};const p=e.view();p.loadSources();p.aggregate.keyword='submitted';p.keyword='draft';p.moreOf({sourceKey:'a',sourceName:'A'});assert.equal(routes[0].params.keyword,'submitted');assert.equal(routes[0].params.sourceKey,'a');
 });
 await test('same real source explicitly reselected elsewhere exits aggregate and one failed listener cannot block peers',async()=>{
  const e=env(),a={key:'a',name:'A',search:{searchOptions:[],loadPage:async()=>new e.c.Result([])}};e.sources([a]);const p=e.view();p.aboutToAppear();await tick();p.selectSource(0);assert.equal(p.aggregated,true);e.c.Shared.subscribe(()=>{throw Error('observer-private')});let observed='';e.c.Shared.subscribe(key=>{observed=key});e.c.Shared.select('a');await tick();assert.equal(p.aggregated,false);assert.equal(p.selectedIndex,1);assert.equal(observed,'a');assert.doesNotMatch(JSON.stringify(e.audits),/observer-private/);p.aboutToDisappear();
 });
 assert.equal(count,EXPECTED);finished=true;
 console.log(`PASS ${count} production search filters/defaults/shared-source/inline-aggregate contracts; no device/real HTTP acceptance.`);
})().catch(error=>{fs.appendFileSync(log,error.stack+'\n');console.error(error);process.exitCode=1});
