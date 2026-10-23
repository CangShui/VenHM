'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/rpc-trace-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=rpc-trace-tests production ArkTS receiver with trusted native metadata; native ownership tested separately\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
function environment(){
  const audits=[],httpCalls=[],data=[],dialogs=[],infos=[];
  const ctx=vm.createContext({
    Object,Map,ArrayBuffer,Uint8Array,
    Log:{audit:(t,s,m)=>{audits.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},info:(t,m)=>infos.push({t,m}),warn:()=>{},error:()=>{}},
    recordToHeaders:v=>new Map(Object.entries(v||{})),
    HttpRequestOptions:class{traceId='';headers=new Map();retries=1},
    HttpClient:{request:async(u,m,o)=>{httpCalls.push({u,m,o});return {status:200,headers:new Map(),body:'synthetic'}}},
    http:{RequestMethod:{GET:'GET',POST:'POST'}},
    SourceDataStore:{set:(k,n,v,t)=>data.push({k,n,v,t}),remove:(k,n,t)=>data.push({k,n,t})},
    UiBridge:{showDialog:(t,c,a,id)=>{dialogs.push(id);return Promise.resolve(0)}}
  });
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/source/AuthLogScope.ets')+'\n'+
    read('entry/src/main/ets/source/JsMessageHandler.ets'),{mode:'transform'})+
    '\nglobalThis.Handler=JsMessageHandler;globalThis.Scope=AuthLogScope;',ctx);
  return {ctx,Handler:ctx.Handler,audits,httpCalls,data,dialogs,infos};
}
let count=0;
async function test(name,run){await run();count++;fs.appendFileSync(log,`[响应返回] TraceID=rpc-trace-tests PASS ${name}\n`)}
(async()=>{
  await test('native trace reaches HTTP adapter and response across overlapping requests',async()=>{
    const e=environment(),pending=[];
    e.ctx.HttpClient.request=(u,m,o)=>{e.httpCalls.push({u,m,o});return new Promise(r=>pending.push(r))};
    const a=e.Handler.handleMessage({method:'http',url:'u',__veneraTraceId:'A'});
    const b=e.Handler.handleMessage({method:'http',url:'v',__veneraTraceId:'B'});
    pending[1]({status:200,headers:new Map(),body:'B'});await b;
    pending[0]({status:200,headers:new Map(),body:'A'});await a;
    assert.deepEqual(e.httpCalls.map(x=>x.o.traceId),['A','B']);
    assert.deepEqual(e.audits.filter(x=>x.s==='原生RPC响应').map(x=>x.t),['B','A']);
  });
  await test('sync source saves/deletes retain parent trace',async()=>{
    const e=environment();e.Handler.handleMessage({method:'save_data',key:'fixture',data_key:'token',data:'synthetic',__veneraTraceId:'AUTH'});
    e.Handler.handleMessage({method:'delete_data',key:'fixture',data_key:'token',__veneraTraceId:'AUTH'});
    assert.ok(e.data.every(x=>x.t==='AUTH'));assert.ok(e.audits.every(x=>x.t==='AUTH'));
  });
  await test('UI request receives source trace, not unrelated generated dialog trace',async()=>{
    const e=environment();await e.Handler.handleMessage({method:'UI',function:'showDialog',title:'fixture',actions:[],__veneraTraceId:'UI_OWNER'});
    assert.deepEqual(e.dialogs,['UI_OWNER']);
  });
  await test('auth logging suppression matches owner instead of global current concurrent login',async()=>{
    const e=environment(),frame=e.ctx.Scope.enter('AUTH');
    e.Handler.handleMessage({method:'log',level:'info',title:'x',content:'synthetic-secret',__veneraTraceId:'AUTH'});
    e.Handler.handleMessage({method:'log',level:'info',title:'x',content:'public-background',__veneraTraceId:'OTHER'});
    assert.equal(e.infos.length,1);assert.equal(e.infos[0].m,'public-background');
    assert.ok(!JSON.stringify(e.audits).includes('synthetic-secret'));e.ctx.Scope.leave(frame);
  });
  await test('sync rejection and async rejection both audit same native parent trace',async()=>{
    const e=environment();assert.throws(()=>e.Handler.handleMessage({method:'save_data',key:'x',data_key:'setting',__veneraTraceId:'DENIED'}));
    await assert.rejects(e.Handler.handleMessage({method:'compute',__veneraTraceId:'ASYNC_DENIED'}));
    assert.ok(e.audits.some(x=>x.t==='DENIED'&&x.s==='原生RPC拒绝/异常'));
    assert.ok(e.audits.some(x=>x.t==='ASYNC_DENIED'&&x.s==='原生RPC异常'));
  });
  await test('source HTTP default UA matches fixed upstream and never overrides explicit case-insensitive header',async()=>{
    const e=environment();
    await e.Handler.handleMessage({method:'http',url:'public',headers:{},__veneraTraceId:'UA'});
    assert.equal(e.httpCalls[0].o.headers.get('User-Agent'),'VeneraNext/v1.17.0');
    await e.Handler.handleMessage({method:'http',url:'public',headers:{'uSeR-aGeNt':'SourceExplicitUA'},__veneraTraceId:'UA'});
    assert.equal(e.httpCalls[1].o.headers.get('uSeR-aGeNt'),'SourceExplicitUA');
    assert.equal(e.httpCalls[1].o.headers.has('User-Agent'),false);
  });
  await test('untraced native startup/invalid metadata get independent safe fallback',async()=>{
    const e=environment();e.Handler.handleMessage({method:'getPlatform',__veneraTraceId:''});
    e.Handler.handleMessage({method:'getPlatform',__veneraTraceId:'https://credential.invalid/'});
    assert.ok(e.audits.every(x=>x.t.startsWith('rpc-')));assert.ok(new Set(e.audits.map(x=>x.t)).size===2);
  });
  console.log(`PASS ${count} production RPC trace propagation cases; NAPI/current app device probe still separate.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
