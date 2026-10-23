'use strict';
// Tests the production public capture's request and data-handling boundaries.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..');
const code=fs.readFileSync(path.join(root,'entry/src/main/ets/source/SourceAcceptance.ets'),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function env(status=200,fail=false){
 const files=new Map(),requests=[],audits=[],keys=[];
 const c=vm.createContext({
  AppContext:{filesDir:'/only-app-diagnostics'},
  SourceManager:{find:key=>{keys.push(key);return key==='ehentai'?{key}:undefined}},
  HttpRequestOptions:class{constructor(){this.headers=new Map()}},http:{RequestMethod:{GET:'GET'}},
  HttpClient:{request:async(url,method,o)=>{requests.push({url,method,o});if(fail)throw Error('code 2300028 Timeout');return{status,headers:new Map([['Content-Type','text/html; charset=UTF-8']]),body:'<html>public fixture</html>'}}},
  Log:{audit:(t,s,n)=>audits.push([s,n]),info:()=>{}},
  fs:{OpenMode:{CREATE:1,READ_WRITE:2,APPEND:4},openSync:p=>({fd:p}),writeSync:(p,s)=>files.set(p,(files.get(p)||'')+s),closeSync:()=>{}}
 });
 vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Target=SourceAcceptance;',c);
 return{c,target:c.Target,files,requests,audits,keys};
}
let count=0;async function test(name,fn){await fn();count++;console.log('PASS '+name)}
(async()=>{
 await test('reject arbitrary sources before network or filesystem writes',async()=>{const e=env();await assert.rejects(e.target.runPublicTemplateProbe('private-source'));assert.equal(e.requests.length,0);assert.equal(e.files.size,0)});
 await test('only four fixed public EH paths no source settings/ex/account/watch APIs',async()=>{
  const e=env();await e.target.runPublicTemplateProbe('ehentai');assert.deepEqual(e.requests.map(r=>r.url),['https://e-hentai.org','https://e-hentai.org/popular','https://e-hentai.org/?f_search=a','https://e-hentai.org/?f_search=%E9%AD%94%E6%B3%95']);
  assert.ok(e.keys.every(k=>k==='ehentai'));assert.equal(e.requests.length,4);
  for(const r of e.requests){assert.equal(r.method,'GET');assert.equal(r.o.headers.size,1);assert.equal(r.o.headers.get('User-Agent'),'VeneraNext/v1.17.0');assert.equal(r.o.useCookieJar,false);assert.equal(r.o.retries,0);assert.equal(r.o.maxDecodedBytes,2*1024*1024);assert.equal(r.o.connectTimeoutMs,8000);assert.equal(r.o.readTimeoutMs,12000)}
  for(const [file,text]of e.files){assert.ok(file.startsWith('/only-app-diagnostics/'));if(file.endsWith('.proof.json')){const p=JSON.parse(text);assert.equal(p.redirectChainKnown,false);assert.equal(p.exportIsDecodedTextNotWireBytes,true);assert.equal(p.cookieJarSent,false);assert.equal(p.cookieJarUpdated,false);assert.equal(p.responseCharsetHeader,'text/html; charset=UTF-8')}}
  assert.ok(!JSON.stringify(e.audits).includes('<html>'));assert.equal(e.target.running,false);
 });
 await test('401 and403 stop immediately no alternate-host retry or body export',async()=>{
  for(const status of [401,403]){const e=env(status);await e.target.runPublicTemplateProbe('ehentai');assert.equal(e.requests.length,1);assert.ok([...e.files.keys()].some(k=>k.endsWith('.proof.json')));assert.ok(![...e.files.keys()].some(k=>k.endsWith('.html')));assert.equal(e.target.running,false)}
 });
 await test('SDK rejection bounded to one attempt and leaves UI available',async()=>{const e=env(200,true);await e.target.runPublicTemplateProbe('ehentai');assert.equal(e.requests.length,1);assert.equal(e.target.running,false);assert.ok(e.audits.some(([s])=>s==='PUBLIC_CAPTURE_FAIL'))});
 await test('active matrix blocks probe without requests or replacing its run',async()=>{const e=env();e.target.running=true;await assert.rejects(e.target.runPublicTemplateProbe('ehentai'));assert.equal(e.requests.length,0);assert.equal(e.files.size,0)});
 console.log(`PASS ${count} production public-template capture boundary cases; no actual HTTP/device action.`);
})().catch(e=>{console.error(e);process.exitCode=1});
