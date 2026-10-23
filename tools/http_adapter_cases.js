'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/http-adapter-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=http-adapter-tests production HTTP adapter; SDK mocked, no claim of real empty-body failure cause\n');
function env(){
  const calls=[],events=[];let destroyed=0,response={responseCode:200,header:{},result:Uint8Array.from([1,2]).buffer};
  const ctx=vm.createContext({
    Uint8Array,ArrayBuffer,Map,Buffer,fs:{},
    setTimeout:fn=>fn(),
    util:{TextEncoder:class{encodeInto(s){return Buffer.from(s)}},TextDecoder:{create:()=>({decodeToString:b=>Buffer.from(b).toString('utf8')})}},
    Log:{audit:(t,s,m)=>{events.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},warn:()=>{},error:()=>{}},
    CookieJar:{header:()=> 'fixture-cookie-secret',receive:()=>{}},
    http:{HttpDataType:{ARRAY_BUFFER:1},RequestMethod:{GET:'GET',POST:'POST'},
      createHttp:()=>({request:async(u,o)=>{calls.push({u,o});if(response instanceof Error)throw response;return response},destroy:()=>destroyed++})}
  });
  const code=fs.readFileSync(path.join(root,'entry/src/main/ets/network/HttpClient.ets'),'utf8')
    .replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Client=HttpClient;globalThis.Options=HttpRequestOptions;',ctx);
  return {ctx,calls,events,Client:ctx.Client,Options:ctx.Options,setResponse:v=>response=v,get destroyed(){return destroyed}};
}
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=http-adapter-tests PASS ${name}\n`)}
(async()=>{
  await test('explicit empty raw/JSON/form/byte bodies omit extraData without becoming GET',async()=>{
    for(const [field,value] of [['rawBody',''],['jsonBody',''],['formBody',''],['extraData',new Uint8Array(0)]]){
      const e=env(),o=new e.Options();o[field]=value;o.asBytes=true;o.traceId='http-adapter-tests';
      await e.Client.request('http://fixture.invalid/empty','POST',o);
      assert.equal(e.calls[0].o.method,'POST');assert.equal(Object.hasOwn(e.calls[0].o,'extraData'),false);
      assert.equal(e.destroyed,1);
    }
  });
  await test('raw body is exact and does not force JSON content type',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.rawBody='a=1';
    await e.Client.request('http://fixture.invalid/raw','POST',o);
    assert.equal(e.calls[0].o.extraData,'a=1');assert.equal(e.calls[0].o.header['Content-Type'],undefined);
  });
  await test('binary subview copies only its own bytes, never backing-buffer sentinels',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.extraData=Uint8Array.from([9,1,2,8]).subarray(1,3);
    await e.Client.request('http://fixture.invalid/bytes','POST',o);
    assert.deepEqual([...new Uint8Array(e.calls[0].o.extraData)],[1,2]);
  });
  await test('empty high-priority body does not fall through to unrelated populated body',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.rawBody='';o.jsonBody='unrelated';
    await e.Client.request('http://fixture.invalid/raw','POST',o);
    assert.equal(Object.hasOwn(e.calls[0].o,'extraData'),false);
  });
  await test('explicit content type and caller headers preserved, source headers never mutated',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';
    o.headers.set('Content-Type','application/custom');o.headers.set('Cookie','explicit-secret');o.jsonBody='{}';
    await e.Client.request('https://fixture.invalid/image?token=secret','POST',o);
    assert.equal(o.headers.get('Cookie'),'explicit-secret');
    assert.equal(e.calls[0].o.header.Cookie,'explicit-secret; fixture-cookie-secret');
    assert.equal(e.calls[0].o.header['Content-Type'],'application/custom');
    assert.ok(e.events.every(x=>x.t==='http-adapter-tests'));
    assert.ok(e.events.every(x=>!x.m.includes('explicit-secret')&&!x.m.includes('fixture-cookie-secret')&&!x.m.includes('token=')));
  });
  await test('all failed attempts release HTTP instances and carry the same trace',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';e.setResponse(Error('fixture transport'));
    await assert.rejects(e.Client.request('http://fixture.invalid/fail','GET',o));
    assert.equal(e.calls.length,2);assert.equal(e.destroyed,2);assert.ok(e.events.every(x=>x.t==='http-adapter-tests'));
  });
  await test('case-insensitive declared headers never duplicated or overridden by defaults',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.jsonBody='{}';
    o.headers.set('content-type','application/custom');o.headers.set('USER-AGENT','fixture');
    o.headers.set('accept-encoding','identity');
    await e.Client.request('http://fixture.invalid/image','POST',o);
    const h=e.calls[0].o.header;
    assert.equal(h['Content-Type'],undefined);assert.equal(h['User-Agent'],undefined);assert.equal(h['Accept-Encoding'],undefined);
    assert.equal(h['content-type'],'application/custom');
  });
  await test('SDK response with gzip header but already-decoded bytes is not unwrapped again',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.asBytes=true;
    e.setResponse({responseCode:200,header:{'content-encoding':'gzip'},result:Uint8Array.from([1,2]).buffer});
    const seen=[];e.ctx.ContentDecoding={decode:(b,h,t,n,sdk)=>{seen.push({h,t,sdk});return b}};
    const r=await e.Client.request('http://fixture.invalid/decoded','GET',o);
    assert.deepEqual([...new Uint8Array(r.bytes)],[1,2]);assert.equal(seen[0].sdk,true);
  });
  await test('response encoding names are case-insensitive, not just two preferred spellings',async()=>{
    const e=env(),o=new e.Options();o.traceId='http-adapter-tests';o.asBytes=true;
    e.setResponse({responseCode:200,header:{'CONTENT-ENCODING':'gzip'},result:Uint8Array.from([1,2]).buffer});
    const calls=[];e.ctx.ContentDecoding={decode:(b,h)=>{calls.push(h);return b}};
    await e.Client.request('http://fixture.invalid/decoded','GET',o);assert.deepEqual(calls,['gzip']);
  });
  console.log(`PASS ${count} production HTTP payload/trace/resource cases (SDK mock, real HTTP probe pending).`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
