'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/account-page-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=account-page-tests production page logic; ArkWeb/SDK mocked, no real account claim\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
function page(file,name,scope){
  const raw=read(file),code=(raw.slice(0,raw.indexOf('  build() {'))+'}')
    .replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace(`struct ${name}`,`class ${name}`);
  scope.Log={audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)};
  const ctx=vm.createContext(scope);
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+`\nglobalThis.Page=${name};`,ctx);
  return {ctx,p:new ctx.Page()};
}
const tick=()=>new Promise(r=>setImmediate(r));let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=account-page-tests PASS ${name}\n`)}
function web(){
  const routes=[],captures=[],finishes=[];let url='https://fixture.invalid/done',title='Done';
  const source={key:'fixture',account:{checkLoginStatus:async()=>true,finishWebLogin:async(snapshot,current)=>{finishes.push(snapshot);assert.equal(current(),true);return {error:false,dataOrNull:true}}}};
  const e=page('entry/src/main/ets/pages/SourceWebLoginPage.ets','SourceWebLoginPage',{
    webview:{WebviewController:class{getUrl(){return url}getTitle(){return title}}},
    BrowserLoginSession:{httpUrl:()=>({}),host:()=> 'fixture.invalid',capture:async(c,u,t)=>{captures.push({u,t});return {url:u,title:t,cookies:[],localStorage:{}}},end:()=>{}},
    router:{back:()=>routes.push('back')}
  });e.p.source=source;e.p.sessionReady=true;e.p.trace='account-page-tests';
  return {...e,source,routes,captures,finishes,setPage:(u,t)=>{url=u;title=t}};
}
(async()=>{
  await test('password failure preserves masked draft and stays on login page',async()=>{
    const routes=[];
    const e=page('entry/src/main/ets/pages/SourceAccountPage.ets','SourceAccountPage',{router:{back:()=>routes.push('back')}});
    e.p.user='synthetic-user';e.p.password='synthetic-password';e.p.source={key:'fixture',account:{login:async()=>({error:true})}};
    await e.p.submit(false);assert.equal(e.p.password,'synthetic-password');assert.equal(routes.length,0);assert.equal(e.p.busy,false);
  });
  await test('Cookie true clears drafts and closes only after durable result',async()=>{
    let resolve;const routes=[];
    const e=page('entry/src/main/ets/pages/SourceAccountPage.ets','SourceAccountPage',{router:{back:()=>routes.push('back')}});
    e.p.cookieValues=['synthetic-cookie'];e.p.source={key:'fixture',account:{validateCookies:()=>new Promise(r=>resolve=r)}};
    const run=e.p.submit(true);await tick();assert.equal(routes.length,0);resolve({error:false,dataOrNull:true});await run;
    assert.equal(e.p.cookieValues[0],'');assert.equal(routes.length,1);
  });
  await test('account response after page exit does not route or rewrite state',async()=>{
    let resolve;const routes=[];
    const e=page('entry/src/main/ets/pages/SourceAccountPage.ets','SourceAccountPage',{router:{back:()=>routes.push('back')}});
    e.p.password='synthetic';e.p.source={key:'fixture',account:{login:()=>new Promise(r=>resolve=r)}};
    const run=e.p.submit(false);await tick();e.p.aboutToDisappear();resolve({error:false,dataOrNull:true});await run;
    assert.equal(routes.length,0);assert.equal(e.p.status,'');
  });
  await test('Web false condition does not export cookies/storage',async()=>{
    const e=web();e.source.account.checkLoginStatus=async()=>false;e.p.requestCheck();await tick();
    assert.equal(e.captures.length,0);assert.equal(e.finishes.length,0);assert.equal(e.routes.length,0);
  });
  await test('Web changing title while check pending discards old result and runs latest',async()=>{
    const e=web(),checks=[];e.source.account.checkLoginStatus=()=>new Promise(r=>checks.push(r));
    e.p.requestCheck();await tick();e.setPage('https://fixture.invalid/changed','Changed');e.p.requestCheck();
    checks[0](true);await tick();assert.equal(e.captures.length,0);checks[1](false);await tick();
    assert.equal(e.finishes.length,0);assert.equal(e.p.checking,false);
  });
  await test('Web cancel while capture pending prevents credential commit',async()=>{
    const e=web();let release;e.ctx.BrowserLoginSession.capture=()=>new Promise(r=>release=r);
    e.p.requestCheck();await tick();e.p.cancel();release({url:'u',title:'t'});await tick();
    assert.equal(e.finishes.length,0);assert.equal(e.routes.length,0);
  });
  await test('Web success closes only after session callback result confirms true',async()=>{
    const e=web();let release;e.source.account.finishWebLogin=()=>new Promise(r=>release=r);
    e.p.requestCheck();await tick();assert.equal(e.routes.length,0);release({error:false,dataOrNull:true});await tick();
    assert.deepEqual(e.routes,['back']);
  });
  await test('Web capture failure stays on page and permits retry, never fake logged',async()=>{
    const e=web();e.ctx.BrowserLoginSession.capture=async()=>{throw Error('SDK mismatch')};
    e.p.requestCheck();await tick();assert.equal(e.routes.length,0);assert.equal(e.p.checking,false);assert.ok(e.p.error);
  });
  await test('account page returns from Web login when persisted source state is confirmed',async()=>{
    const routes=[];
    const e=page('entry/src/main/ets/pages/SourceAccountPage.ets','SourceAccountPage',{router:{back:()=>routes.push('back')}});
    e.p.source={isLogged:true};e.p.webOpened=true;e.p.onPageShow();assert.deepEqual(routes,['back']);
  });
  assert.ok(!fs.readFileSync(log,'utf8').includes('synthetic-password'));
  console.log(`PASS ${count} production account/Web page races; no native browser or real login acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
