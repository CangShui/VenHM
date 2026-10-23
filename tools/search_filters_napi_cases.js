'use strict';
// Actual host NAPI/QuickJS metadata reads + full unchanged installed EH request builder.
// Network methods are intercepted in memory; no account or live site operation.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const raw=f=>fs.readFileSync(path.join(root,f),'utf8');
const clean=f=>raw(f).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));
native.setMessageHandler(m=>{if(m.method==='log'||m.method==='getPlatform')return null;throw Error('unexpected external bridge '+m.method)});
native.setGlobalString('appVersion','1.17.0');native.evaluate(raw('entry/src/main/resources/rawfile/sendmessage_shim.js'));
native.evaluate(raw('entry/src/main/resources/rawfile/init.js'));native.evaluate(raw('entry/src/main/resources/rawfile/html_engine.js'));
const c=vm.createContext({Map,Log:{audit(){}}});
c.JsEngine={callJson:(code,name,trace)=>native.callJson(code,name,trace)};
vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/model/Res.ets')+'\n'+clean('entry/src/main/ets/source/ComicSource.ets')+'\n'+clean('entry/src/main/ets/source/JsSearchOptionsAdapter.ets')+'\n'+clean('entry/src/main/ets/features/SearchFilterPolicy.ets'),{mode:'transform'})+'\nglobalThis.Adapter=JsSearchOptionsAdapter;globalThis.Policy=SearchFilterPolicy;',c);
let count=0;async function test(name,body){await body();count++;console.log('PASS '+name)}
(async()=>{
 await test('actual native dynamic metadata getter preserves types empty keys first dash and JSON defaults',async()=>{
  native.evaluate('ComicSource.sources.fixture={search:{get optionList(){return [{label:"类别",type:"multi-select",options:["a-A-with-dash","b-B"],default:["a"]},{type:"dropdown",options:["-全部","x-X"]}]}}}');
  const r=await c.Adapter.load('fixture','<actual-native-filter>');assert.equal(r.error,false);assert.equal(r.dataOrNull[0].options.get('a'),'A-with-dash');assert.equal(r.dataOrNull[1].options.get(''),'全部');assert.equal(c.Policy.defaults(r.dataOrNull)[0],'["a"]');
 });
 await test('actual native getter exception becomes bounded metadata error not private body',async()=>{
  native.evaluate('ComicSource.sources.fixture={search:{get optionList(){throw Error("PRIVATE_BODY_TOKEN")}}}');
  const r=await c.Adapter.load('fixture','<actual-native-filter>');assert.equal(r.error,true);assert.doesNotMatch(r.errorMessage,/PRIVATE_BODY_TOKEN/);
 });
 native.evaluate('ComicSource.prototype.loadData=()=>null;ComicSource.prototype.loadSetting=k=>({domain:"e-hentai.org",ehevent:false,hvevent:false})[k];');
 const installed=raw('logs/user8-installed-scripts/ehentai.js');
 native.evaluate('(()=>{'+installed+'\nComicSource.sources.ehentai=new Ehentai();})()');
 native.evaluate('globalThis.filterRequests=[];Network.get=async(url)=>{filterRequests.push(url);return {status:200,body:"<html><body></body></html>"}};');
 let groups,defaults;
 await test('full unchanged installed EH metadata yields valid default selected categories',async()=>{
  const r=await c.Adapter.load('ehentai','<installed-EH-filter>');assert.equal(r.error,false);groups=r.dataOrNull;defaults=c.Policy.defaults(groups);
  assert.equal(groups.length,3);assert.equal(groups[0].type,'multi-select');assert.deepEqual(JSON.parse(defaults[0]),['0','1','2','3','4','5','6','7','8','9']);assert.equal(defaults[1],'');assert.equal(defaults[2],'');
 });
 await test('full unchanged EH request builder receives no spurious JSON quoted dropdown or null-string filters',async()=>{
  await native.callJson('ComicSource.sources.ehentai.search.loadNext("fixture",'+JSON.stringify(Array.from(defaults))+',null)','<installed-EH-filter>','filter-fixture');
  const requests=await native.callJson('filterRequests');assert.equal(requests.length,1);assert.equal(requests[0],'https://e-hentai.org/?f_search=fixture');
 });
 await test('selected categories use source positional JSON contract and exact bitmask in intercepted request',async()=>{
  const selected=c.Policy.change(groups,defaults,0,'2');
  await native.callJson('ComicSource.sources.ehentai.search.loadNext("fixture",'+JSON.stringify(Array.from(selected))+',null)','<installed-EH-filter>','filter-fixture');
  const requests=await native.callJson('filterRequests');assert.equal(requests.length,2);assert.match(requests[1],/[?&]f_cats=4(?:&|$)/);
 });
 console.log(`PASS ${count} actual host NAPI search-filter metadata / unchanged EH request-builder fixtures; two in-memory requests, zero live HTTP.`);
})().catch(error=>{console.error(error);process.exitCode=1});
