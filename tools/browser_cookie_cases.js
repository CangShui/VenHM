'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/browser-cookie-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=browser-cookie-tests production CookieJar/browser bridge; isolated SQL/ArkWeb fakes, no user cookies\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
function jar(){
  const rows=new Map(),ops=[];let failAt=-1,writes=0,snapshot;
  const ctx=vm.createContext({URL,Map,Set,
    url:{URL:{parseURL:v=>new URL(v)}},
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),warn:()=>{}},
    Database:{rdb:{beginTransaction:()=>{snapshot=new Map(rows);ops.push('begin')},commit:()=>ops.push('commit'),
      rollBack:()=>{rows.clear();for(const [k,v]of snapshot)rows.set(k,v);ops.push('rollback')},
      executeSync:(sql,args)=>{if(++writes===failAt)throw Error('fixture SQL fail');
        const key=sql.startsWith('DELETE')?args.slice(0,3).join('\0'):[args[0],args[2],args[3]].join('\0');
        if(sql.startsWith('DELETE'))rows.delete(key);else rows.set(key,args.slice())}}},
  });
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/model/BrowserLogin.ets')+'\n'+
    read('entry/src/main/ets/network/CookieJar.ets'),{mode:'transform'})+
    '\nglobalThis.Jar=CookieJar;globalThis.Cookie=BrowserCookie;',ctx);
  return {ctx,Jar:ctx.Jar,rows,ops,setFailureAfter:n=>failAt=writes+n};
}
function cookie(overrides={}){return {name:'auth',value:'fixture-secret',domain:'.fixture.invalid',path:'/api',
  hostOnly:false,secure:true,httpOnly:true,expiresAt:Date.now()+60000,sameSite:'Lax',...overrides}}
function browser(){
  const cleared=[],writes=[],seed=[],all=[];const deviceInfo={sdkApiVersion:26};
  const ctx=vm.createContext({
    URL,url:{URL:{parseURL:v=>new URL(v)}},deviceInfo,
    CookieJar:{browserCookies:()=>seed},Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},
    webview:{WebHttpCookieSameSitePolicy:{NONE:0,LAX:1,STRICT:2},WebCookieManager:{
      clearAllCookiesSync:p=>cleared.push(p),configCookieSync:(u,v,p,httpOnly)=>writes.push({u,v,p,httpOnly}),
      fetchAllCookies:async()=>all,fetchCookieSync:()=> 'auth=synthetic'}}
  });
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/model/BrowserLogin.ets')+'\n'+
    read('entry/src/main/ets/features/BrowserLoginSession.ets'),{mode:'transform'})+
    '\nglobalThis.Session=BrowserLoginSession;',ctx);
  const controller={runJavaScript:async()=>JSON.stringify({url:'https://fixture.invalid/done',title:'Done',storage:{accessToken:'synthetic'}})};
  return {ctx,Session:ctx.Session,cleared,writes,seed,all,controller,deviceInfo};
}
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=browser-cookie-tests PASS ${name}\n`)}
(async()=>{
  await test('browser import preserves domain/path/secure/httpOnly/expiry and native cold row',async()=>{
    const e=jar(),c=cookie();e.Jar.importBrowser('https://sub.fixture.invalid/done',[c],'browser-cookie-tests');
    assert.equal(e.Jar.header('https://sub.fixture.invalid/api/x'),'auth=fixture-secret');
    assert.equal(e.Jar.header('http://sub.fixture.invalid/api/x'),'');assert.equal(e.Jar.header('https://sub.fixture.invalid/other'),'');
    const row=[...e.rows.values()][0];assert.equal(row[3],'/api');assert.equal(row[4],0);assert.equal(row[5],1);assert.equal(row[6],1);
    assert.equal(row[8],'Lax');
    assert.equal(row[7],c.expiresAt);assert.deepEqual(e.ops,['begin','commit']);
  });
  await test('host-only cookie never sent to sibling or child hosts',async()=>{
    const e=jar();e.Jar.importBrowser('https://fixture.invalid/done',[cookie({domain:'fixture.invalid',hostOnly:true,path:'/'})],'t');
    assert.equal(e.Jar.header('https://sub.fixture.invalid/'),'');assert.equal(e.Jar.header('https://unrelated.invalid/'),'');
  });
  await test('browser foreign-domain/invalid/header-injection import rejected before transaction',async()=>{
    for(const c of [cookie({domain:'.unrelated.invalid'}),cookie({name:'bad\nname'}),cookie({value:'bad\r\nvalue'}),cookie({path:'bad'}),cookie({expiresAt:NaN})]){
      const e=jar();assert.throws(()=>e.Jar.importBrowser('https://fixture.invalid/',[c],'t'));
      assert.equal(e.rows.size,0);assert.equal(e.ops.length,0);
    }
  });
  await test('multi-cookie SQL failure restores DB and in-memory jar atomically',async()=>{
    const e=jar();e.Jar.set('https://fixture.invalid/',[{name:'before',value:'old'}]);const before=new Map(e.rows);
    e.setFailureAfter(2);assert.throws(()=>e.Jar.importBrowser('https://fixture.invalid/',[cookie({path:'/'}),cookie({name:'second',path:'/'})],'t'));
    assert.deepEqual(e.rows,before);assert.equal(e.Jar.header('https://fixture.invalid/'),'before=old');assert.ok(e.ops.includes('rollback'));
  });
  await test('receipt rollback restores only own changes, preserving later network update',async()=>{
    const e=jar();e.Jar.set('https://fixture.invalid/',[{name:'auth',value:'prior'}]);
    const receipt=e.Jar.importBrowser('https://fixture.invalid/',[cookie({domain:'fixture.invalid',hostOnly:true,path:'/',secure:false})],'t');
    e.Jar.rollbackBrowser(receipt,'t');assert.equal(e.Jar.header('https://fixture.invalid/'),'auth=prior');
    const newer=e.Jar.importBrowser('https://fixture.invalid/',[cookie({domain:'fixture.invalid',hostOnly:true,path:'/',secure:false})],'t');
    e.Jar.receive('https://fixture.invalid/',{'Set-Cookie':'auth=later; Path=/'});e.Jar.rollbackBrowser(newer,'t');
    assert.equal(e.Jar.header('https://fixture.invalid/'),'auth=later');
  });
  await test('explicit script cross-domain cookies support ehentai/exhentai, unlike browser imports',async()=>{
    const e=jar();e.Jar.set('https://e-hentai.org/',[{name:'auth',value:'one',domain:'.exhentai.org'}]);
    assert.equal(e.Jar.header('https://exhentai.org/'),'auth=one');assert.equal(e.Jar.header('https://e-hentai.org/'),'');
  });
  await test('explicit plain Domain is a domain cookie, not falsely host-only',async()=>{
    const e=jar();e.Jar.set('https://fixture.invalid/',[{name:'auth',value:'one',domain:'fixture.invalid'}]);
    assert.equal(e.Jar.header('https://sub.fixture.invalid/'),'auth=one');
  });
  await test('persisted Cookie row reload keeps SameSite and browser attributes',async()=>{
    const e=jar();e.Jar.importBrowser('https://fixture.invalid/done',[cookie()],'t');
    const columns=['name','value','domain','path','host_only','secure','http_only','expires_at_ms','same_site'];
    e.ctx.Database.query=async()=>{const values=[...e.rows.values()];let i=-1;return {
      goToNextRow:()=>++i<values.length,getColumnIndex:k=>columns.indexOf(k),getString:j=>values[i][j],getLong:j=>values[i][j],close:()=>{}}};
    e.Jar.entries.clear();await e.Jar.init();const restored=e.Jar.browserCookies('https://fixture.invalid/login')[0];
    assert.equal(restored.sameSite,'Lax');assert.equal(restored.httpOnly,true);assert.equal(restored.path,'/api');
  });
  await test('owned fixture Cookie cleanup preserves other localhost/host sessions',async()=>{
    const e=jar();e.Jar.set('http://127.0.0.1/',[{name:'hm_auth_1_2',value:'synthetic'},{name:'user-session',value:'kept'}]);
    e.Jar.deleteNamed('http://127.0.0.1:29091/',['hm_auth_1_2'],'t');
    assert.equal(e.Jar.header('http://127.0.0.1/'),'user-session=kept');
  });
  await test('isolated browser profile reservation prevents parallel login before Web creation',async()=>{
    const e=browser();e.Session.reserve('https://fixture.invalid/login','first');
    assert.throws(()=>e.Session.reserve('https://other.invalid/login','second'));
    e.Session.end('second');assert.throws(()=>e.Session.reserve('https://other.invalid/login','second'));
    e.Session.end('first');assert.ok(e.cleared.every(v=>v===true));
  });
  await test('browser seeds metadata including path/Secure/HttpOnly, never normal profile',async()=>{
    const e=browser();e.seed.push(cookie());e.Session.begin('https://fixture.invalid/login','t');
    assert.match(e.writes[0].v,/Path=\/api/);assert.match(e.writes[0].v,/Secure/);assert.match(e.writes[0].v,/HttpOnly/);
    assert.equal(e.writes[0].p,true);e.Session.end('t');assert.ok(e.cleared.every(v=>v===true));
  });
  await test('full browser capture filters unrelated auth-provider cookies and preserves metadata',async()=>{
    const e=browser();e.Session.begin('https://fixture.invalid/login','t');
    const raw={name:'auth',value:'synthetic',domain:'.fixture.invalid',path:'/api',isSessionCookie:false,
      expiresDate:new Date(Date.now()+60000).toUTCString(),isSecure:true,isHttpOnly:true,samesitePolicy:1};
    e.all.push(raw,{...raw,name:'unrelated',domain:'.identity.invalid'});
    const result=await e.Session.capture(e.controller,'https://fixture.invalid/done','Done','t');
    assert.equal(result.cookies.length,1);assert.equal(result.cookies[0].httpOnly,true);
    assert.equal(result.cookies[0].path,'/api');assert.equal(result.localStorage.accessToken,'synthetic');e.Session.end('t');
  });
  await test('API23 facade preserves metadata without requiring enum export in compile SDK',async()=>{
    const e=browser();delete e.ctx.webview.WebHttpCookieSameSitePolicy;e.Session.begin('https://fixture.invalid/login','t');
    e.all.push({name:'auth',value:'synthetic',domain:'fixture.invalid',path:'/',isSessionCookie:true,
      expiresDate:'',isSecure:true,isHttpOnly:true,samesitePolicy:2});
    const result=await e.Session.capture(e.controller,'https://fixture.invalid/done','Done','t');
    assert.equal(result.cookieMetadataComplete,true);assert.equal(result.cookies[0].sameSite,'Strict');
    assert.equal(result.cookies[0].httpOnly,true);e.Session.end('t');
  });
  await test('new-system missing metadata API rejects rather than falsely reporting complete attributes',async()=>{
    const e=browser();delete e.ctx.webview.WebCookieManager.fetchAllCookies;e.Session.begin('https://fixture.invalid/login','t');
    await assert.rejects(e.Session.capture(e.controller,'https://fixture.invalid/done','Done','t'),/API23/);e.Session.end('t');
  });
  await test('JSON return wrapping handled; changed page/storage formats rejected',async()=>{
    const e=browser(),json=JSON.stringify({url:'u',title:'t',storage:{key:'value'}});
    assert.equal(e.Session.parseStorage(JSON.stringify(json),'u','t').key,'value');
    assert.throws(()=>e.Session.parseStorage(json,'changed','t'));
    assert.throws(()=>e.Session.parseStorage(JSON.stringify({url:'u',title:'t',storage:{key:42}}),'u','t'));
  });
  await test('legacy API21 Cookie transfer remains available and explicitly incomplete metadata',async()=>{
    const e=browser();e.deviceInfo.sdkApiVersion=21;e.Session.begin('https://fixture.invalid/login','t');
    e.ctx.webview.WebCookieManager.fetchCookieSync=u=>u.startsWith('https://')?'auth=synthetic':'';
    const result=await e.Session.capture(e.controller,'https://fixture.invalid/done','Done','t');
    assert.equal(result.cookies.length,1);assert.equal(result.cookieMetadataComplete,false);
    assert.equal(result.cookies[0].secure,true);assert.equal(result.cookies[0].httpOnly,true);e.Session.end('t');
  });
  await test('legacy restricted Path is observed instead of always widened to root',async()=>{
    const e=browser();e.deviceInfo.sdkApiVersion=21;e.Session.begin('https://fixture.invalid/login','t');
    e.controller.runJavaScript=async()=>JSON.stringify({url:'https://fixture.invalid/auth/done',title:'Done',storage:{},cookie:'auth=synthetic'});
    e.ctx.webview.WebCookieManager.fetchCookieSync=u=>u.startsWith('https://')&&new URL(u).pathname.startsWith('/auth')?'auth=synthetic':'';
    const result=await e.Session.capture(e.controller,'https://fixture.invalid/auth/done','Done','t');
    assert.equal(result.cookies[0].path,'/auth');assert.equal(result.cookies[0].httpOnly,false);
    assert.equal(result.cookies[0].metadataComplete,false);e.Session.end('t');
  });
  await test('legacy parent-domain propagation requires browser parent+sibling confirmation',async()=>{
    const e=browser();e.deviceInfo.sdkApiVersion=21;e.Session.begin('https://forums.fixture.invalid/login','t');
    e.controller.runJavaScript=async()=>JSON.stringify({url:'https://forums.fixture.invalid/done',title:'Done',storage:{},cookie:''});
    e.ctx.webview.WebCookieManager.fetchCookieSync=u=>new URL(u).hostname.endsWith('fixture.invalid')?'auth=synthetic':'';
    const result=await e.Session.capture(e.controller,'https://forums.fixture.invalid/done','Done','t');
    assert.equal(result.cookies[0].domain,'.fixture.invalid');assert.equal(result.cookies[0].hostOnly,false);e.Session.end('t');
  });
  await test('unsafe scheme and userinfo rejected, no browser credentials stored in URI',async()=>{
    const e=browser();for(const u of ['file:///private','javascript:alert(1)','https://user:pass@fixture.invalid/'])
      assert.throws(()=>e.Session.httpUrl(u));
  });
  assert.ok(!fs.readFileSync(log,'utf8').includes('fixture-secret'));
  console.log(`PASS ${count} production browser cookie/session cases; ArkWeb APIs/real login still pending.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
