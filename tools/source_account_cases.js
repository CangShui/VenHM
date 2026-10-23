'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/source-account-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
fs.writeFileSync(log,'[请求到达] TraceID=account-tests production JS account lifecycle; simulated site only, no real login claim\n');
const raw=fs.readFileSync(path.join(root,'entry/src/main/ets/source/JsComicSource.ets'),'utf8');
const source=raw.slice(0,raw.indexOf('export class ComicSourceParser')).replace(/^\s*import\b[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
// JsComicSource now also references the details/favorites adapters; provide
// inert stubs so this account-focused suite exercises only the account paths.
const inertAdapters=`class JsDetailsAdapter{static create(){return {};}}
class JsFavoritesAdapter{static create(){return {};}}`;
function environment(){
  const data=new Map(),calls=[];
  class Base{constructor(key,name){this.key=key;this.name=name}static sources={}}
  class Res{constructor(data){this.dataOrNull=data;this.error=false}static fail(message){const r=new Res();r.error=true;r.errorMessage=message;return r}}
  const ctx=vm.createContext({
    ComicSource:Base,Res,AccountConfig:class{},ImageRequestConfig:class{url='';headers=new Map();unsupported=[];modifyImage='';method='GET'},
    SourceDataStore:{get:(k,n)=>data.get(k+'\0'+n)??null,
      failureEpoch:()=>0,awaitSourceWrites:async()=>{},
      setAndWait:async(k,n,v)=>{calls.push('persist');data.set(k+'\0'+n,v)},
      removeAndWait:async(k,n)=>{calls.push('remove');data.delete(k+'\0'+n)},
      restoreIfCurrent:async(k,n,staged,old)=>{calls.push('restore');if(JSON.stringify(data.get(k+'\0'+n))!==JSON.stringify(staged))return;
        if(old===null)data.delete(k+'\0'+n);else data.set(k+'\0'+n,old)}},
    CookieJar:{importBrowser:(u,c)=>{calls.push('cookie-import');return {changes:c}},
      rollbackBrowser:()=>calls.push('cookie-rollback')},
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),info:()=>{},warn:()=>{}},
    toStringOrNull:v=>typeof v==='string'?v:undefined,
    parseStringList:v=>Array.isArray(v)?v.filter(x=>typeof x==='string'):[]
  });
  ctx.isFunction=v=>typeof v==='function';
  const scopes=fs.readFileSync(path.join(root,'entry/src/main/ets/source/AuthLogScope.ets'),'utf8')
    .replace(/\bexport /g,'');
  vm.runInContext(stripTypeScriptTypes(scopes,{mode:'transform'})+'\nglobalThis.AuthLogScope=AuthLogScope;',ctx);
  const parser=fs.readFileSync(path.join(root,'entry/src/main/ets/source/ImageConfigParser.ets'),'utf8')
    .replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
  vm.runInContext(stripTypeScriptTypes(parser,{mode:'transform'})+'\nglobalThis.ImageConfigParser=ImageConfigParser;',ctx);
  Base.sources.fixture={account:{
    login:async(u,p)=>{assert.equal(u,'fixture-user');assert.equal(p,'fixture-secret');calls.push('site-login');return 'ok'},
    logout:async()=>{calls.push('site-logout')}
  },comic:{onImageLoad:()=>({modifyImage:'let modifyImage=i=>i.copyAndRotate90();'})}};
  ctx.JsEngine={callJson:async code=>await vm.runInContext(code,ctx)};
  vm.runInContext(stripTypeScriptTypes(inertAdapters+'\n'+source,{mode:'transform'})+'\nglobalThis.Source=JsComicSource;',ctx);
  const instance=new ctx.Source('fixture','Fixture','1.0.0','<test>');
  instance.configure({account:true,passwordLogin:true},[],[]);
  return {ctx,instance,data,calls,script:Base.sources.fixture};
}
let count=0;
async function test(name,run){await run();count++;fs.appendFileSync(log,`[响应返回] TraceID=account-tests PASS ${name}\n`)}
(async()=>{
  await test('login waits for database before returning success',async()=>{
    const e=environment();let release,done=false;
    e.ctx.SourceDataStore.setAndWait=()=>new Promise(r=>{release=r});
    const run=e.instance.account.login('fixture-user','fixture-secret').then(r=>{done=true;return r});
    await new Promise(r=>setImmediate(r));assert.equal(done,false);release();
    assert.equal((await run).dataOrNull,true);
  });
  await test('database failure does not become login success',async()=>{
    const e=environment();e.ctx.SourceDataStore.setAndWait=async()=>{throw Error('db failure')};
    assert.equal((await e.instance.account.login('fixture-user','fixture-secret')).error,true);
    assert.equal(e.instance.isLogged,false);
  });
  await test('site rejection never stores account',async()=>{
    const e=environment();e.script.account.login=async()=>{throw Error('site rejection')};
    assert.equal((await e.instance.account.login('fixture-user','fixture-secret')).error,true);
    assert.equal(e.calls.includes('persist'),false);
  });
  await test('same source concurrent login/logout is rejected, no new session wiped',async()=>{
    const e=environment();let release;e.script.account.login=()=>new Promise(r=>release=r);
    const run=e.instance.account.login('fixture-user','fixture-secret');
    await new Promise(r=>setImmediate(r));await assert.rejects(e.instance.account.logout());
    assert.equal((await e.instance.account.login('fixture-user','fixture-secret')).error,true);
    release('ok');await run;assert.equal(e.instance.isLogged,true);
  });
  await test('logout awaits async hook before account removal and UI success',async()=>{
    const e=environment();await e.instance.account.login('fixture-user','fixture-secret');
    let release;e.script.account.logout=()=>new Promise(r=>release=r);
    const run=e.instance.account.logout();await new Promise(r=>setImmediate(r));
    assert.equal(e.instance.isLogged,true);assert.equal(e.calls.includes('remove'),false);
    release();await run;assert.equal(e.instance.isLogged,false);
  });
  await test('logout hook failure retains account rather than false success',async()=>{
    const e=environment();await e.instance.account.login('fixture-user','fixture-secret');
    e.script.account.logout=async()=>{throw Error('logout failure')};
    await assert.rejects(e.instance.account.logout());assert.equal(e.instance.isLogged,true);
  });
  await test('web/cookie-only account does not get nonexistent password login',async()=>{
    const e=environment();e.instance.configure({account:true,passwordLogin:false},[],[]);
    assert.equal(e.instance.account.login,undefined);
  });
  await test('modifyImage string preserved; invalid type rejected',async()=>{
    const e=environment(),c=await e.instance.getImageConfig?.('url','id','ep') ??
      await e.instance.jsImageConfig('url','id','ep');
    assert.equal(c.modifyImage,'let modifyImage=i=>i.copyAndRotate90();');
    assert.equal(c.unsupported.length,0);
    e.script.comic.onImageLoad=()=>({modifyImage:()=>{}});
    await assert.rejects(e.instance.jsImageConfig('url','id','ep'));
  });
  await test('parser account metadata wires cookie/web-only login without password path',async()=>{
    const e=environment();e.instance.configure({account:true,passwordLogin:false},[],[],{
      webUrl:'https://fixture.invalid/login',hasWebCheck:true,cookieFields:['first','second'],hasCookieValidate:true});
    assert.equal(e.instance.account.login,undefined);
    assert.equal(typeof e.instance.account.validateCookies,'function');assert.equal(typeof e.instance.account.finishWebLogin,'function');
    assert.deepEqual(Array.from(e.instance.account.cookieFields),['first','second']);
  });
  await test('Cookie fields stay ordered and true validation awaits durable ok marker',async()=>{
    const e=environment();e.instance.configure({account:true,passwordLogin:false},[],[],{cookieFields:['a','b'],hasCookieValidate:true});
    e.script.account.loginWithCookies={validate:async values=>{assert.deepEqual(Array.from(values),['one','two']);return true}};
    assert.equal((await e.instance.account.validateCookies(['one','two'])).dataOrNull,true);
    assert.equal(e.data.get('fixture\0account'),'ok');
  });
  await test('Cookie false/nonbool/error/count mismatch never commits account marker',async()=>{
    for(const mode of [false,'true','error']){
      const e=environment();e.instance.configure({account:true},[],[],{cookieFields:['a'],hasCookieValidate:true});
      let invoked=0;e.script.account.loginWithCookies={validate:async()=>{invoked++;if(mode==='error')throw Error('invalid');return mode}};
      assert.equal((await e.instance.account.validateCookies(['one'])).dataOrNull===true,false);
      assert.equal(e.instance.isLogged,false);
      await e.instance.account.validateCookies(['one','two']);assert.equal(invoked,1);
    }
  });
  function web(e,hook=async()=>{}){
    e.instance.configure({account:true},[],[],{webUrl:'https://fixture.invalid/login',hasWebCheck:true});
    e.script.account.loginWithWebview={checkStatus:(u,t)=>u==='https://fixture.invalid/done'&&t==='Done',onLoginSuccess:hook};
    return {url:'https://fixture.invalid/done',title:'Done',cookies:[],localStorage:{accessToken:'fixture-session'}};
  }
  await test('Web callback sees storage/cookies before marker and is awaited',async()=>{
    const e=environment();let release;
    const snapshot=web(e,async()=>{
      assert.equal(e.data.get('fixture\0_localStorage').accessToken,'fixture-session');
      assert.equal(e.calls.includes('cookie-import'),true);assert.equal(e.instance.isLogged,false);
      await new Promise(r=>release=r);
    });
    const run=e.instance.account.finishWebLogin(snapshot,()=>true,'account-tests');await new Promise(r=>setImmediate(r));
    assert.equal(e.instance.isLogged,false);assert.equal(typeof release,'function',`callback not reached; stages=${e.calls.join(',')}`);
    release();assert.equal((await run).dataOrNull,true);assert.equal(e.instance.isLogged,true);
  });
  await test('Web status requires boolean true and is rechecked at commit',async()=>{
    const e=environment(),snapshot=web(e);snapshot.title='Not logged';
    assert.equal((await e.instance.account.finishWebLogin(snapshot,()=>true)).dataOrNull,false);
    assert.equal(e.calls.includes('cookie-import'),false);
    e.script.account.loginWithWebview.checkStatus=()=> 'true';
    assert.equal(await e.instance.account.checkLoginStatus(snapshot.url,'Done'),false);
  });
  await test('Web callback failure rolls back staging, retaining confirmed old data',async()=>{
    const e=environment();e.data.set('fixture\0_localStorage',{old:'prior'});
    const snapshot=web(e,async()=>{throw Error('fixture callback failure')});
    assert.equal((await e.instance.account.finishWebLogin(snapshot,()=>true)).error,true);
    assert.equal(e.data.get('fixture\0_localStorage').old,'prior');assert.equal(e.calls.includes('cookie-rollback'),true);
    assert.equal(e.instance.isLogged,false);
  });
  await test('Web close during callback never leaves ok marker',async()=>{
    const e=environment();let alive=true,release;
    const snapshot=web(e,async()=>await new Promise(r=>release=r));
    const run=e.instance.account.finishWebLogin(snapshot,()=>alive);await new Promise(r=>setImmediate(r));
    alive=false;release();assert.equal((await run).error,true);assert.equal(e.instance.isLogged,false);
  });
  await test('late account marker persistence after Web close is restored',async()=>{
    const e=environment();let alive=true;
    const snapshot=web(e);
    const original=e.ctx.SourceDataStore.setAndWait;
    e.ctx.SourceDataStore.setAndWait=async(k,n,v)=>{await original(k,n,v);if(n==='account')alive=false};
    assert.equal((await e.instance.account.finishWebLogin(snapshot,()=>alive)).error,true);
    assert.equal(e.instance.isLogged,false);
  });
  await test('failed queued script token writes prevent password/Web success markers',async()=>{
    const e=environment();e.ctx.SourceDataStore.awaitSourceWrites=async()=>{throw Error('queued write failed')};
    assert.equal((await e.instance.account.login('fixture-user','fixture-secret')).error,true);
    assert.equal(e.instance.isLogged,false);
    const snapshot=web(e);assert.equal((await e.instance.account.finishWebLogin(snapshot,()=>true)).error,true);
    assert.equal(e.instance.isLogged,false);
    assert.equal(e.ctx.AuthLogScope.current(),undefined);
  });
  await test('relogin only uses a saved username/password tuple, never a Web/Cookie ok marker',async()=>{
    const e=environment();assert.equal(e.instance.account.canRelogin(),false);
    assert.equal((await e.instance.account.relogin()).error,true);
    await e.instance.account.login('fixture-user','fixture-secret');assert.equal(e.instance.account.canRelogin(),true);
    assert.equal((await e.instance.account.relogin('account-tests')).dataOrNull,true);
    e.data.set('fixture\0account','ok');assert.equal(e.instance.account.canRelogin(),false);
    assert.equal((await e.instance.account.relogin()).error,true);
  });
  await test('declared zero-field Cookie validation remains a supported explicit path',async()=>{
    const e=environment();e.instance.configure({account:true},[],[],{cookieFields:[],hasCookieValidate:true});
    e.script.account.loginWithCookies={validate:async v=>v.length===0};
    assert.equal((await e.instance.account.validateCookies([])).dataOrNull,true);
  });
  assert.ok(!fs.readFileSync(log,'utf8').includes('fixture-secret'));
  console.log(`PASS ${count} production account durability/concurrency/config cases; not real account acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
