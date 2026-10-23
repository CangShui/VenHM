'use strict';
// Entire archived source in clean engines; no live HTTP/account/device mutation.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const source=read('logs/user8-installed-scripts/ykmh.js');
const init=read('entry/src/main/resources/rawfile/init.js');
const html=read('entry/src/main/resources/rawfile/html_engine.js');
const out={scope:'offline full archived installed source; fixture-only one-token edit is NOT installed or published',sourceSha256:crypto.createHash('sha256').update(source).digest('hex'),runtimes:[]};
async function run(name,runner){
  runner.eval('(()=>{'+source+'\nglobalThis.originalYkmh=new YKMHSource();})()');
  runner.eval('globalThis.requests=0;Network.get=async()=>{requests++;return {status:200,body:"<html></html>"}};delete globalThis.temp;');
  const before=await runner.run('(async()=>{let error;try{await originalYkmh.categoryComics.load("test",undefined,["update","0"],1)}catch(e){error=String(e)}return{error,requests,hasGlobalTemp:typeof globalThis.temp!=="undefined"}})()');
  assert.match(before.error,/temp.*not defined/);assert.equal(before.requests,0);assert.equal(before.hasGlobalTemp,false);
  assert.equal((source.match(/temp = options\[1\]/g)||[]).length,1);
  const fixtureOnly=source.replace('temp = options[1]','let temp = options[1]');
  runner.eval('(()=>{'+fixtureOnly+'\nglobalThis.fixtureOnlyYkmh=new YKMHSource();})()');
  const after=await runner.run('(async()=>{const r=await fixtureOnlyYkmh.categoryComics.load("test",undefined,["update","0"],1);return{requests,comics:r.comics.length,maxPage:r.maxPage,hasGlobalTemp:typeof globalThis.temp!=="undefined"}})()');
  assert.equal(after.requests,1);assert.equal(after.hasGlobalTemp,false);
  out.runtimes.push({name,unchangedSource:before,fixtureOnlyDeclarationAdded:after});
}
(async()=>{
 const context=vm.createContext({sendMessage:m=>{if(m.method==='log'||m.method==='getPlatform')return null;throw Error('Unexpected message '+m.method)}});
 vm.runInContext(init,context);vm.runInContext(html,context);
 await run('standard Node VM',{eval:s=>vm.runInContext(s,context),run:s=>Promise.resolve(vm.runInContext(s,context))});
 const native=require(path.join(root,'logs/napi-host/venerajs.node'));
 native.setMessageHandler(m=>{if(m.method==='log'||m.method==='getPlatform')return null;throw Error('Unexpected bridge '+m.method)});
 native.setGlobalString('appVersion','1.17.0');native.evaluate(read('entry/src/main/resources/rawfile/sendmessage_shim.js'));native.evaluate(init);native.evaluate(html);
 await run('actual prebuilt NAPI/QuickJS',{eval:s=>native.evaluate(s),run:s=>native.callJson(s,'<ykmh-offline-attribution>','ykmh-attribution')});
 fs.writeFileSync(path.join(root,'logs/ykmh-category-attribution-20261015.json'),JSON.stringify(out,null,2));
 console.log('PASS 2 full-source standard-engine/NAPI paired replays: original temp undeclared before HTTP; fixture-only let reaches mock network. No installed script mutation.');
})().catch(e=>{console.error(e);process.exitCode=1});
