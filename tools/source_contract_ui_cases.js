'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const log=path.join(root,'logs/source-contract-ui-cases.log');fs.writeFileSync(log,'Production JsComicSource option/cursor/tag/category contracts, controlled source data/bridge only. NOT phone or real site PASS.\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import[\s\S]*?from [^;]+;\r?\n/gm,'').replace(/\bexport /g,'');
const calls=[];const c=vm.createContext({Map,JSON,ArrayBuffer,Uint8Array,setTimeout:()=>0,
  Log:{audit:()=>{},warn:()=>{},info:()=>{},error:()=>{}},
  SourceDataStore:{get:()=>undefined,set:()=>{}},APP_VERSION:'1.17.0',
  toStringOrNull:v=>typeof v==='string'?v:undefined,toIntOrNull:v=>typeof v==='number'?v:undefined,
  parseStringList:v=>Array.isArray(v)?v.filter(x=>typeof x==='string'):[],parseComicList:(v,k)=>(v||[]).map(x=>({...x,sourceKey:k})),parseComic:(v,k)=>({...v,sourceKey:k})
});
c.JsEngine={callJson:async(code,_name,trace)=>{calls.push({code,trace});return await vm.runInContext(code,c)},evaluate:code=>String(vm.runInContext(code,c)),isAvailable:true};
const deps=require('./vm_deps');
vm.runInContext(stripTypeScriptTypes(deps.join(deps.SOURCE_FILES),{mode:'transform'})+'\nglobalThis.Subject=JsComicSource;',c);
vm.runInContext('ComicSource.sources={fixture:{search:{},explore:[],category:{title:"Tags",parts:[]},categoryComics:{},comic:{}}};globalThis.fixture=ComicSource.sources.fixture;',c);
let count=0;async function test(name,body){await body();count++;fs.appendFileSync(log,`TraceID=source-contract-tests [PASS] ${name}\n`)}
function source(){return new c.Subject('fixture','Fixture','1.0.0','<fixture>')}
(async()=>{
  await test('E-Hentai multi-select defaults serialized JSON, dropdown absent remains null',async()=>{
    c.fixture.search.optionList=[{type:'multi-select',default:['0','1'],options:['0-Misc','1-Test']},{type:'dropdown',options:['-none','1-one']},{type:'dropdown',options:['-none']}];
    c.fixture.search.loadNext=async(k,opts,next)=>{assert.deepEqual(JSON.parse(opts[0]),['0','1']);assert.equal(opts[1],null);assert.equal(opts[2],null);assert.equal(next,null);return {comics:[{id:'c',title:'T',cover:'u'}],next:'opaque-url'}};
    const s=source();s.configure({searchNext:true},[],[]);const r=await s.search.loadPage('a',1,[]);assert.equal(r.error,false);assert.equal(r.subDataString,'opaque-url');
  });
  await test('explicit search options preserved while unspecified trailing groups retain defaults',async()=>{
    c.fixture.search.loadNext=async(k,opts,next)=>{assert.equal(opts[0],'1');assert.equal(opts[1],'4');assert.equal(opts[2],null);assert.equal(next,'opaque-next');return {comics:[],next:null}};
    const s=source();s.configure({searchNext:true},[],[]);const r=await s.search.loadNext('a','opaque-next',['1','4']);assert.equal(r.error,false);
  });
  await test('select default key derived before first dash and labels keep remaining hyphens',async()=>{
    c.fixture.search.optionList=[{type:'select',options:['v-alpha-beta','w-other']}];c.fixture.search.load=async(k,opts,page)=>{assert.equal(opts[0],'v');assert.equal(page,2);return {comics:[],maxPage:2}};
    const s=source();s.configure({search:true},[],[]);assert.equal((await s.search.loadPage('a',2,[])).error,false);
  });
  await test('cursor-only exploration calls loadNext(null), then preserves opaque next',async()=>{
    const seen=[];c.fixture.explore=[{type:'multiPageComicList',loadNext:async next=>{seen.push(next);return {comics:[{id:'c',title:'T',cover:'u'}],next:next===null?'https://opaque.next/':null}}}];
    const s=source();s.configure({explore:true},['Latest'],['multiPageComicList'],undefined,[true]);assert.equal(s.explorePages[0].cursorOnly,true);
    const r=await s.explorePages[0].loadPage(1);await s.explorePages[0].loadNext(r.subDataString);assert.deepEqual(seen,[null,'https://opaque.next/']);
  });
  await test('modern namespaced tag target keeps blank search keyword and initial options',async()=>{
    c.fixture.comic.onClickTag=async(ns,tag)=>{assert.equal(ns,'Category');assert.equal(tag,'Manga');return {page:'search',attributes:{keyword:'',options:['2','','']}}};
    const s=source();s.configure({onClickTag:true},[],[]);const t=await s.tagTarget('Category','Manga');assert.equal(t.page,'search');assert.equal(t.attributes.get('keyword'),'');assert.deepEqual(Array.from(t.initialOptions),['2','','']);
  });
  await test('legacy onClickTag action preserves embedded colon/param, no category guessing',async()=>{
    c.fixture.comic.onClickTag=(ns,tag)=>({action:'category',keyword:tag,param:ns});const s=source();s.configure({onClickTag:true},[],[]);
    const t=await s.tagTarget('artist','a:b');assert.equal(t.attributes.get('category'),'a:b');assert.equal(t.attributes.get('param'),'artist');
  });
  await test('malformed tag hook result rejects instead of silent generic search',async()=>{
    c.fixture.comic.onClickTag=()=>({page:'category',attributes:{category:42}});const s=source();s.configure({onClickTag:true},[],[]);await assert.rejects(s.tagTarget('ns','v'));
  });
  await test('static and dynamic option loader results parse first dash and conditional display',async()=>{
    c.fixture.categoryComics={optionList:[{label:'Order',options:['new-New-items','-none','bad'],showWhen:['Latest'],notShowWhen:['Hidden']}]};
    const s=source();s.configure({category:true,categoryLoad:false},[],[]);const r=await s.categoryComics.optionsLoader('Latest');assert.equal(r.error,false);
    assert.equal(r.dataOrNull[0].options.get('new'),'New-items');assert.equal(r.dataOrNull[0].options.get(''),'none');assert.deepEqual(Array.from(r.dataOrNull[0].showWhen),['Latest']);
    c.fixture.categoryComics.optionLoader=async(category,param)=>{assert.equal(category,'c');assert.equal(param,'p');return [{label:'L',options:['k-K']} ]};assert.equal((await s.categoryComics.optionsLoader('c','p')).error,false);
  });
  await test('dynamic category loader and legacy namespaced search landing preserved',async()=>{
    c.fixture.category={title:'Tags',parts:[{name:'Dyn',type:'dynamic',loader:async()=>[{label:'X',target:{page:'category',attributes:{category:'c',param:'p',options:['k']}}}]},{name:'artist',type:'fixed',itemType:'search_with_namespace',categories:['a:b']} ]};
    const s=source();s.configure({categoryLanding:true},[],[]);const d=await s.loadCategoryData();assert.equal(d.parts.length,2);assert.equal(d.parts[0].items[0].attributes.get('param'),'p');assert.deepEqual(Array.from(d.parts[0].items[0].initialOptions),['k']);assert.equal(d.parts[1].items[0].attributes.get('keyword'),'artist:a:b');assert.equal(s.supportsCategory,true);
  });
  await test('malformed dynamic category options propagate explicit UI-facing errors',async()=>{
    c.fixture.category={title:'Tags',parts:[{name:'Dyn',type:'dynamic',loader:async()=>42}]};const s=source();s.configure({categoryLanding:true},[],[]);await assert.rejects(s.loadCategoryData());
    c.fixture.categoryComics={optionLoader:async()=>({})};s.configure({category:true},[],[]);assert.equal((await s.categoryComics.optionsLoader('c')).error,true);
  });
  await test('demo registration/UI/source/config references absent, old user data not cleared',async()=>{
    for(const p of ['entry/src/main/ets/source/SourceManager.ets','entry/src/main/ets/features/SettingsView.ets','entry/src/main/ets/foundation/Settings.ets'])assert.doesNotMatch(read(p),/DemoApiSource|apiBaseUrl|demoApiBaseUrl|演示源 API/);
    assert.equal(fs.existsSync(path.join(root,'entry/src/main/ets/source/DemoApiSource.ets')),false);assert.doesNotMatch(read('entry/src/main/ets/source/SourceManager.ets'),/DELETE FROM|clearAllCookies|uninstall/);
  });
  console.log(`PASS ${count} production source contract/tag/default/cursor/demo cases; phone network/UI still separate.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
