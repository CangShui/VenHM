'use strict';
// Executes production startup-source policy and settings-save methods, not just text checks.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function self(initial={}){
 const store=new Map(Object.entries(initial));let bodies=0,flushes=0;
 const c=vm.createContext({Settings:{getBool:(k,f)=>store.has(k)?store.get(k):f}});
 vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/source/SourceSelfTest.ets'),{mode:'transform'})+'\nglobalThis.Subject=SourceSelfTest;',c);
 c.Subject.runBody=async()=>{bodies++};c.Subject.flush=()=>{flushes++};return{c,store,get bodies(){return bodies},get flushes(){return flushes}};
}
let count=0;async function test(n,fn){await fn();count++;console.log('PASS '+n)}
(async()=>{
 await test('ordinary launch without explicit preference does not crawl sources or write a report',async()=>{const e=self();await e.c.Subject.run();assert.equal(e.bodies,0);assert.equal(e.flushes,0);assert.equal(e.c.Subject.isRunning,false)});
 await test('deep sampling alone never opts normal launch into networking',async()=>{const e=self({sourceSelfTestDeep:true});await e.c.Subject.run();assert.equal(e.bodies,0)});
 await test('existing explicit opt-in preserved and errors release startup runner',async()=>{const e=self({sourceSelfTest:true});await e.c.Subject.run();assert.equal(e.bodies,1);assert.equal(e.flushes,1);e.c.Subject.runBody=async()=>{throw Error('controlled')};await assert.rejects(e.c.Subject.run());assert.equal(e.c.Subject.isRunning,false);assert.equal(e.flushes,2)});
 const code=read('entry/src/main/ets/pages/UsabilityPage.ets');
 const body=(code.slice(0,code.indexOf('  build() {'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct UsabilityPage','class UsabilityPage');
 function page(){let fail=false,release,stops=0;const gate=new Promise(r=>{release=r}),writes=[],toasts=[];
  const c=vm.createContext({Settings:{setBool:async(k,v)=>{writes.push([k,v]);await gate;if(fail)throw Error('private diagnostic') }},SourceSelfTest:{stopAfterCurrentSource:()=>stops++},promptAction:{showToast:x=>toasts.push(x.message)}});
  vm.runInContext(stripTypeScriptTypes(body,{mode:'transform'})+'\nglobalThis.Subject=UsabilityPage;',c);
  return{p:new c.Subject(),writes,toasts,release,fail:()=>{fail=true},get stops(){return stops}};
 }
 await test('startup toggle confirms only after preferences flush and blocks concurrent saves',async()=>{const e=page();const saved=e.p.saveStartupOption('sourceSelfTest',true);assert.equal(e.p.savingStartup,true);assert.equal(e.p.startupSelfTest,false);await e.p.saveStartupOption('sourceSelfTest',false);assert.equal(e.writes.length,1);e.release();await saved;assert.equal(e.p.startupSelfTest,true);assert.equal(e.p.savingStartup,false)});
 await test('preference failure retains prior state and stopping requires successful disable',async()=>{const e=page();e.p.startupSelfTest=true;e.fail();const saved=e.p.saveStartupOption('sourceSelfTest',false);e.release();await saved;assert.equal(e.p.startupSelfTest,true);assert.equal(e.stops,0);assert.equal(e.toasts.length,1);const good=page();good.p.startupSelfTest=true;const disabled=good.p.saveStartupOption('sourceSelfTest',false);good.release();await disabled;assert.equal(good.p.startupSelfTest,false);assert.equal(good.stops,1)});
 console.log(`PASS ${count} startup source-network opt-in contracts; no actual source/network/device operation.`);
})().catch(e=>{console.error(e);process.exitCode=1});
