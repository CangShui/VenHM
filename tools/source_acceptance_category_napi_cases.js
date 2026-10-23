'use strict';
// SourceAcceptance -> JsComicSource -> actual production host NAPI/QuickJS.
// Controlled fixtures only: NOT ArkTS bytecode, device SDK or live-site acceptance.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/source-acceptance-category-napi-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import[\s\S]*?from [^;]+;\r?\n/gm,'').replace(/\bexport /g,'');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));
fs.writeFileSync(log,'Production category runner/adapter, real host NAPI; synthetic HTTP, no network or credentials. NOT device/ArkTS evidence.\n');
const reports=[],requests=[];
const html='<div class="grid"><div class="gallary_wrap"><ul class="cc"><li><div class="pic_box"><a href="/photos-index-aid-123.html"><img src="//fixture.invalid/cover.jpg"></a></div><div class="info"><div class="title"><a>Fixture</a></div><div class="info_col">Fixture info</div></div></li></ul></div></div><div class="f_left paginator"><a>1</a><a>2</a></div>';
native.setMessageHandler(message=>{
  if(message.method==='load_setting')return message.setting_key==='domainSelection'?'0':message.setting_key==='domain0'?'fixture.invalid':null;
  if(message.method==='http'){requests.push(message);return Promise.resolve({status:200,body:html,headers:{}});}
  if(message.method==='getPlatform')return 'ohos';
  if(message.method==='log')return null;
  throw Error('Unexpected fixture host method: '+message.method);
});
native.setGlobalString('appVersion','1.17.0');
native.evaluate(read('entry/src/main/resources/rawfile/init.js'),'<init>');
native.evaluate(read('entry/src/main/resources/rawfile/sendmessage_shim.js'),'<shim>');
native.evaluate(read('entry/src/main/resources/rawfile/html_engine.js'),'<html>');
const context=vm.createContext({
  Log:{audit:(trace,stage,note)=>{reports.push({stage,note});fs.appendFileSync(log,stage+' '+note+'\n');},info:()=>{},warn:()=>{}},
  JsEngine:{callJson:(code,name,trace)=>native.callJson(code,name||'<category-probe>',trace||'category-napi-tests')},
  SourceDataStore:{get:()=>undefined},
  toStringOrNull:value=>typeof value==='string'?value:undefined,
  toIntOrNull:value=>typeof value==='number'?value:undefined,
  parseStringList:value=>Array.isArray(value)?value.filter(item=>typeof item==='string'):[],
  parseComicList:(value,key)=>Array.isArray(value)?value.map(item=>({...item,sourceKey:key})):[],
  APP_VERSION:'1.17.0'
});
vm.runInContext(stripTypeScriptTypes([
  'entry/src/main/ets/foundation/Extensions.ets','entry/src/main/ets/foundation/Semver.ets',
  'entry/src/main/ets/model/Comic.ets','entry/src/main/ets/model/ComicDetails.ets',
  'entry/src/main/ets/model/BrowserLogin.ets','entry/src/main/ets/features/SourceFailure.ets',
  'entry/src/main/ets/source/AuthLogScope.ets','entry/src/main/ets/source/DetailsCapabilities.ets',
  'entry/src/main/ets/source/JsDetailsAdapter.ets','entry/src/main/ets/source/RankingData.ets',
  'entry/src/main/ets/source/JsRankingAdapter.ets','entry/src/main/ets/source/JsFavoritesAdapter.ets',
  'entry/src/main/ets/model/Res.ets','entry/src/main/ets/source/ComicSource.ets',
  'entry/src/main/ets/source/JsComicSource.ets','entry/src/main/ets/source/SourceAcceptance.ets'
].map(clean).join('\n'),{mode:'transform'})+'\nglobalThis.Adapter=JsComicSource;globalThis.Runner=SourceAcceptance;',context);
function source(key){const value=new context.Adapter(key,key,'1.0.0','<category-napi-fixture>');value.configure({category:true,categoryLoad:true,categoryLanding:true},[],[]);return value;}
let count=0;
async function test(name,body){await body();count++;fs.appendFileSync(log,'PASS '+name+'\n');}
(async()=>{
  await test('generated host static category method remains callable through real adapter',async()=>{
    native.evaluate(`ComicSource.sources.fixture={category:{parts:[{name:'Dynamic',type:'dynamic',loader:async()=>[
      {label:'One',target:{page:'category',attributes:{category:'a',param:'exact'}}}]}]},categoryComics:{
      optionLoader:async(c,p)=>{if(c!=='a'||p!=='exact')throw Error('route changed');return [{label:'Sort',options:['new-New','old-Old']}];},
      load:async(c,p,o,n)=>{if(o[0]!=='new'||n!==1)throw Error('options changed');return {comics:[{id:'1',title:'Title',cover:'cover'}]};}
    }};`,'<fixture>');
    assert.equal(typeof context.Runner.category,'function');
    assert.equal(await context.Runner.category(source('fixture')),'PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE');
  });
  await test('QuickJS target TypeError is retained with load phase and later part succeeds',async()=>{
    native.evaluate(`ComicSource.sources.fixture.category.parts=[
      {name:'First',categories:['bad'],itemType:'category'},
      {name:'Later',categories:['good'],itemType:'category'}];
      ComicSource.sources.fixture.categoryComics.optionLoader=async()=>[];
      ComicSource.sources.fixture.categoryComics.load=async(c)=>{if(c==='bad'){let missing;missing();}return {comics:[{id:'2',title:'Title',cover:'cover'}]};};`,'<fixture-fault>');
    assert.equal(await context.Runner.category(source('fixture')),'FAIL_TARGETS');
    assert.ok(reports.some(item=>item.stage==='L2_CATEGORY_TARGET_FAIL'&&/part=1 item=1 phase=load/.test(item.note)));
    assert.ok(reports.some(item=>/part=Later sampled=1 executable=1/.test(item.note)));
  });
  await test('installed WNACG unchanged category method executes with controlled HTML via real NAPI',async()=>{
    native.evaluate(read('logs/user8-installed-scripts/wnacg.js')+'\nComicSource.sources.wnacg=new Wnacg();','<installed-wnacg>');
    assert.equal(await context.Runner.category(source('wnacg')),'PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE');
    assert.equal(requests.length,9,'first two targets per source part, one in Latest');
  });
  console.log(`PASS ${count} category production-adapter/real-host-NAPI cases; no device or live-site acceptance.`);
})().catch(error=>{fs.appendFileSync(log,error.stack+'\n');console.error(error);process.exitCode=1;});
