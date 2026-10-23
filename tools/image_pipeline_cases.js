'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/image-pipeline-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
fs.writeFileSync(log,'[请求到达] TraceID=image-pipeline-tests production parser/pipeline/HTTP adapter; no real network/accounts\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function environment(){
  const calls=[],callbacks=[],events=[],released=[];
  class Config{url='';headers=new Map();modifyImage='';method='GET';data;onResponse;onLoadFailed;unsupported=[]}
  class Options{headers=new Map();asBytes=false;retries=1;traceId=''}
  const ctx=vm.createContext({
    Uint8Array,ArrayBuffer,Map,
    ImageRequestConfig:Config,HttpRequestOptions:Options,
    AppContext:{localComicDir:'/local'},
    Log:{audit:(t,s,m)=>{events.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}},
    isFunction:v=>typeof v==='function',invokeFunction:async(f,args)=>{callbacks.push(f);return await f(...args)},
    http:{RequestMethod:Object.fromEntries(['GET','POST','PUT','PATCH','DELETE','OPTIONS','HEAD'].map(m=>[m,m]))},
    HttpClient:{request:async(u,m,o)=>{calls.push({u,m,o});return {ok:true,status:200,bytes:Uint8Array.from([1,2,3,4]).buffer}}},
    ImageTransforms:{apply:async(b,s)=>b},
    image:{createImageSource:b=>({createPixelMap:async()=>{
      if(new Uint8Array(b)[0]!==1)throw Error('bad image');
      return {getImageInfo:async()=>({size:{width:3,height:5}}),release:async()=>released.push('pixel')}
    },release:async()=>released.push('decoder')})}
  });
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/source/ImageConfigParser.ets')+'\n'+
    read('entry/src/main/ets/network/ImagePipeline.ets'),{mode:'transform'})+
    '\nglobalThis.Parser=ImageConfigParser;globalThis.Pipeline=ImagePipeline;',ctx);
  return {ctx,calls,callbacks,events,released,config:v=>ctx.Parser.parse(v,'https://fixture.invalid/image','pipeline-tests')};
}
let count=0;
async function test(name,run){await run();count++;fs.appendFileSync(log,`[响应返回] TraceID=image-pipeline-tests PASS ${name}\n`)}
(async()=>{
  await test('POST headers/string body preserved; no implicit JSON header/body or unsafe transport retry',async()=>{
    const e=environment(),c=e.config({method:'post',data:'a=1',headers:{'Content-Type':'application/x-www-form-urlencoded'}});
    await e.ctx.Pipeline.fetch(c,'pipeline-tests');
    assert.equal(e.calls[0].m,'POST');assert.equal(e.calls[0].o.rawBody,'a=1');
    assert.equal(e.calls[0].o.jsonBody,undefined);assert.equal(e.calls[0].o.retries,0);
    assert.equal(e.calls[0].o.headers.get('Content-Type'),'application/x-www-form-urlencoded');
  });
  await test('all declared SDK request methods preserved; unknown method never falls back GET',async()=>{
    const e=environment();for(const m of ['GET','PUT','PATCH','DELETE','HEAD','OPTIONS']){
      await e.ctx.Pipeline.fetch(e.config({method:m}),'pipeline-tests');assert.equal(e.calls.at(-1).m,m);
    }
    assert.throws(()=>e.config({method:'TRACE'}));assert.throws(()=>e.config({method:7}));
  });
  await test('binary subviews, JSON objects, and empty strings retain distinct request types',async()=>{
    const e=environment(),bytes=Uint8Array.from([9,1,2,8]).subarray(1,3);
    const binary=e.ctx.Pipeline.requestOptions(e.config({data:bytes}),'t');
    assert.deepEqual([...binary.extraData],[1,2]);
    const object=e.ctx.Pipeline.requestOptions(e.config({data:{a:1}}),'t');assert.equal(object.jsonBody,'{"a":1}');
    assert.equal(e.ctx.Pipeline.requestOptions(e.config({data:''}),'t').rawBody,'');
  });
  await test('async onResponse is awaited and exact typed-array subview returned',async()=>{
    const e=environment(),c=e.config({onResponse:async b=>Uint8Array.from([9,...b,8]).subarray(1,5)});
    const bytes=await e.ctx.Pipeline.fetch(c,'pipeline-tests');
    assert.deepEqual([...new Uint8Array(bytes)],[1,2,3,4]);assert.equal(e.callbacks.length,1);
  });
  await test('response callback runs before pixel modification',async()=>{
    const e=environment(),order=[];
    e.ctx.ImageTransforms.apply=async(b,s)=>{order.push('modify');assert.equal(new Uint8Array(b)[0],1);assert.equal(s,'script');return b};
    await e.ctx.Pipeline.fetch(e.config({modifyImage:'script',onResponse:()=>{order.push('response');return [1,2,3,4]}}),'t');
    assert.deepEqual(order,['response','modify']);
  });
  await test('onResponse rejects null/string/fractional/nonfinite data before decode',async()=>{
    for(const bad of [null,'not bytes',[Infinity],[1.5]]){
      const e=environment();await assert.rejects(e.ctx.Pipeline.fetch(e.config({onResponse:()=>bad}),'t'));
    }
  });
  await test('integer response lists wrap bytes like upstream Uint8List.fromList',async()=>{
    const e=environment();assert.deepEqual([...new Uint8Array(e.ctx.Pipeline.bytes([-1,256,257]))],[255,0,1]);
  });
  await test('nonfunction callbacks ignored like upstream JSInvokable checks',async()=>{
    const e=environment(),c=e.config({onResponse:'not callback',onLoadFailed:{fake:true}});
    assert.equal(c.onResponse,undefined);assert.equal(c.onLoadFailed,undefined);
    await e.ctx.Pipeline.fetch(c,'t');assert.equal(e.callbacks.length,0);
  });
  await test('HTTP failure invokes async recovery with no arguments and replaces whole config',async()=>{
    const e=environment();let failures=0;
    e.ctx.HttpClient.request=async(u,m,o)=>{e.calls.push({u,m,o});return ++failures===1?{ok:false,status:403}:{ok:true,bytes:Uint8Array.from([1]).buffer}};
    const c=e.config({headers:{secret:'old'},onLoadFailed:async function(){
      assert.equal(arguments.length,0);return {url:'https://fixture.invalid/recovered',method:'POST',data:'new',headers:{new:'value'}};
    }});
    await e.ctx.Pipeline.fetch(c,'t');assert.equal(e.calls.length,2);
    assert.equal(e.calls[1].u,'https://fixture.invalid/recovered');assert.equal(e.calls[1].m,'POST');
    assert.equal(e.calls[1].o.headers.has('secret'),false);assert.equal(e.calls[1].o.rawBody,'new');
  });
  await test('five recoveries maximum; six attempts even if callback reinstalls itself',async()=>{
    const e=environment();let recover=0,network=0;
    e.ctx.HttpClient.request=async()=>{network++;throw Error('failed')};
    const hook=()=>{recover++;return {onLoadFailed:hook}};
    await assert.rejects(e.ctx.Pipeline.fetch(e.config({onLoadFailed:hook}),'t'));
    assert.equal(network,6);assert.equal(recover,5);
  });
  await test('null/malformed recovery does not retry bare GET',async()=>{
    for(const invalid of [null,[],42,{method:'TRACE'}]){
      const e=environment();e.ctx.HttpClient.request=async()=>{e.calls.push('request');throw Error('original')};
      await assert.rejects(e.ctx.Pipeline.fetch(e.config({onLoadFailed:()=>invalid}),'t'));
      assert.equal(e.calls.length,1);
    }
  });
  await test('decode failure can recover; all native image resources released',async()=>{
    const e=environment();e.ctx.HttpClient.request=async()=>({ok:true,bytes:Uint8Array.from([9]).buffer});
    const bytes=await e.ctx.Pipeline.fetch(e.config({onLoadFailed:()=>({onResponse:()=>[1,2]})}),'t');
    assert.deepEqual([...new Uint8Array(bytes)],[1,2]);assert.equal(e.released.filter(x=>x==='decoder').length,2);
  });
  await test('cancellation of pending request never calls recovery or starts new request',async()=>{
    const e=environment();let go=true,release;
    e.ctx.HttpClient.request=()=>new Promise(r=>release=r);
    const run=e.ctx.Pipeline.fetch(e.config({onLoadFailed:()=>{throw Error('must not recover')}}),'t',()=>go);
    await new Promise(r=>setImmediate(r));go=false;release({ok:false,status:500});
    await assert.rejects(run,/CANCELLED/);assert.equal(e.callbacks.length,0);
  });
  await test('matching TraceID crosses parser/request/callback/decode logs without credentials',async()=>{
    const e=environment();await e.ctx.Pipeline.fetch(e.config({headers:{Authorization:'fixture-secret'},onResponse:b=>b}),'pipeline-tests');
    assert.ok(e.events.every(x=>x.t==='pipeline-tests'));
    assert.equal(e.calls[0].o.traceId,'pipeline-tests');
    assert.ok(!fs.readFileSync(log,'utf8').includes('fixture-secret'));
  });
  console.log(`PASS ${count} production image config/pipeline cases; actual HTTP/QuickJS still require device probe.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
