'use strict';
// Actual production NAPI/TSFN code running under Node on Windows. Host handler
// responses are synthetic; this does NOT claim ArkTS/ImageKit/phone acceptance.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const zlib=require('node:zlib');
const root=path.resolve(__dirname,'..'),addonPath=path.join(root,'logs/napi-host/venerajs.node');
const foreignPath=path.join(root,'logs/napi-host/foreign_external.node');
const auditPath=path.join(root,'logs/napi-host/audit.log');
const init=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/init.js'),'utf8');
const shim=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/sendmessage_shim.js'),'utf8');
const html=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/html_engine.js'),'utf8');
const native=require(addonPath);
let count=0,held=[],readCount=0,foreign;
const events=[];
function handler(message){
  events.push({method:message.method,trace:message.__veneraTraceId});
  switch(message.method){
    case 'delay': return new Promise(resolve=>setTimeout(()=>resolve(null),message.time));
    case 'getPlatform': return 'ohos';
    case 'log': return null;
    case 'double': {
      const p=Promise.resolve();p.then=(resolve,reject)=>{held.push({resolve,reject});resolve(42);reject(Error('synthetic losing callback'));resolve(99)};return p;
    }
    case 'winnerThrow': {const p=Promise.resolve();p.then=(resolve)=>{resolve(42);throw Error('synthetic throw after winner')};return p;}
    case 'doubleReentry': {
      const p=Promise.resolve();p.then=(resolve,reject)=>{held.push({resolve,reject});resolve({get n(){reject(Error('synthetic getter loser'));return 42}})};return p;
    }
    case 'never': return new Promise(()=>{});
    case 'cycle': {const x={};x.self=x;return x;}
    case 'foreign': return foreign;
    case 'changedGetter': return {get payload(){readCount++;return readCount===1?123:foreign}};
    case 'changedCycle': {const x={};x.self=x;return {get payload(){readCount++;return readCount===1?123:x}};}
    case 'http': return Promise.resolve({status:200,body:'synthetic-http',headers:new Map([['x-probe','ok']])});
    default: throw Error('unexpected synthetic host method');
  }
}
function configure(){
  native.setMessageHandler(handler);native.setGlobalString('appVersion','1.17.0');
  native.evaluate(init,'<host-init>');native.evaluate(shim,'<host-shim>');native.evaluate(html,'<host-html>');
  native.configureIsolated(init,html,handler,()=>{});
}
const delay=n=>new Promise(r=>setTimeout(r,n));
async function bounded(promise,ms=4000){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('host test timed out')),ms)})])}finally{clearTimeout(timer)}}
async function test(name,run){await bounded(run());count++;const line=`TraceID=napi-host-tests [PASS] ${name}\n`;fs.appendFileSync(auditPath,line);console.log(line.trim())}
async function gc(){if(!global.gc)throw Error('run with --expose-gc');for(let i=0;i<8;i++){global.gc();await new Promise(r=>setImmediate(r))}}

if(process.argv.includes('--shutdown-child')){
  configure();
  // Keep externals and never-settling bridge callbacks alive until real Node
  // environment cleanup. The production registry must invalidate their JS roots
  // before deleting the main QuickJS context; late finalizers must be inert.
  const promises=[];
  for(let i=0;i<40;i++)promises.push(native.callJson('()=>42','<held-function>','cleanup-owner'));
  Promise.all(promises).then(handles=>{
    global.cleanupHandles=handles;
    for(let i=0;i<20;i++)native.callJson('sendMessage({method:"never"})','<never>','cleanup-owner').catch(()=>{});
    console.log('HOST_SHUTDOWN_CHILD_READY synthetic roots retained until actual env cleanup');
  }).catch(error=>{console.error(error);process.exitCode=1});
}else{
  fs.mkdirSync(path.dirname(auditPath),{recursive:true});fs.writeFileSync(auditPath,'Actual production Node NAPI/TSFN addon; no application/user data; NOT OHOS/ArkTS finalizer-order evidence.\n');
  configure();foreign=require(foreignPath).makeForeign();
  (async()=>{
    await test('production addon initialized and diagnostic counts available',async()=>{
      assert.equal(typeof native.runtimeStats,'function');assert.equal(native.runtimeStats().active,true);assert.equal(native.quickjsVersion(),'0.17.0');
      assert.equal(native.evaluate('typeof ComicSource+":"+APP.version'), 'function:1.17.0');
    });
    await test('real NAPI GBK and native compression decoder exports return independent oracle bytes',async()=>{
      assert.deepEqual([...new Uint8Array(native.encodeGbk('中'))],[0xd6,0xd0]);
      const payload=Buffer.from('synthetic codec NAPI probe');
      for(const [wire,compress] of [['gzip',zlib.gzipSync],['deflate',zlib.deflateSync],['br',zlib.brotliCompressSync]]){
        const bytes=compress(payload);const raw=bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength);
        assert.deepEqual(Buffer.from(native.decodeHttpBody(raw,wire,1024)),payload);
        assert.throws(()=>native.decodeHttpBody(raw,wire,2));
      }
    });
    await test('foreign external rejected safely in function probe/invocation/host conversion',async()=>{
      assert.equal(native.isFunction(foreign),false);await assert.rejects(native.invokeFunction(foreign,[]));
      await assert.rejects(native.callJson('sendMessage({method:"foreign"})','<foreign>','foreign-owner'));
      assert.equal(await native.callJson('42'),42);
    });
    await test('actual function handles retain owner trace, survive invocation and release after GC',async()=>{
      let handle=await native.callJson('()=>__veneraCurrentTrace()','<handle>','handle-owner');
      assert.equal(native.isFunction(handle),true);assert.equal(await native.invokeFunction(handle,[]),'handle-owner');
      handle=null;await gc();assert.equal(native.runtimeStats().externalHandles,0);
    });
    await test('same native pointer in a forged external cannot impersonate authentic tagged wrapper',async()=>{
      let handle=await native.callJson('()=>42','<authentic-handle>','authentic-owner');
      assert.equal(typeof handle,'object');assert.equal(native.isFunction(handle),true);
      const alias=require(foreignPath).makeAlias(handle);assert.equal(native.isFunction(alias),false);
      await assert.rejects(native.invokeFunction(alias,[]));assert.equal(await native.invokeFunction(handle,[]),42);
      handle=null;await gc();
    });
    await test('cyclic callback arguments reject before invoking source function',async()=>{
      native.evaluate('globalThis.__unexpectedInvoke=false');
      let handle=await native.callJson('()=>{globalThis.__unexpectedInvoke=true;return 42}');
      const cycle={};cycle.self=cycle;await assert.rejects(native.invokeFunction(handle,[cycle]));
      assert.equal(native.evaluate('__unexpectedInvoke'),'false');native.evaluate('delete globalThis.__unexpectedInvoke');handle=null;await gc();
    });
    await test('host Promise double/late resolve and reject callbacks settle exactly once without UAF',async()=>{
      assert.equal(await native.callJson('sendMessage({method:"double"})','<double>','double-owner'),42);
      for(const cb of held){cb.reject(Error('synthetic late failure'));cb.resolve(777)}
      held=[];await gc();assert.equal(await native.callJson('21+21'),42);
    });
    await test('synchronous Promise winner survives subsequent then throw and clears pending error',async()=>{
      assert.equal(await native.callJson('sendMessage({method:"winnerThrow"})','<winner-throw>','winner-owner'),42);
      assert.equal(await native.callJson('42'),42);
    });
    await test('rejection reasons with throwing toString do not poison later requests',async()=>{
      await assert.rejects(native.callJson('Promise.reject({toString(){throw Error("synthetic stringify failure")}})'));
      assert.equal(await native.callJson('42'),42);
      let handle=await native.callJson('()=>{throw {toString(){throw Error("synthetic callback stringify failure")}}}');
      await assert.rejects(native.invokeFunction(handle,[]));assert.equal(await native.callJson('42'),42);handle=null;await gc();
    });
    await test('cyclic source result and cyclic host value reject rather than overflowing recursive bridge',async()=>{
      await assert.rejects(native.callJson('(()=>{const x={};x.self=x;return x})()'));
      await assert.rejects(native.callJson('sendMessage({method:"cycle"})'));
      assert.equal(await native.callJson('42'),42);
    });
    await test('core clone cycles/maps/sets and byte subviews survive actual source-compute NAPI roundtrip',async()=>{
      const code='(async()=>{const x={n:1};x.self=x;const out=await compute("x=>{x.n=2;return {x,map:new Map([[\'x\',x]]),set:new Set([7]),bytes:new Uint8Array([9,1,8]).subarray(1,2)}}",x);return x.n===1&&out.x.n===2&&out.x.self===out.x&&out.map.get("x")===out.x&&out.set.has(7)&&out.bytes.length===1&&out.bytes[0]===1})()';
      assert.equal(await native.callJson(code,'<compute-clone>','clone-owner'),true);
    });
    await test('four actual compute workers propagate independent RPC trace ownership',async()=>{
      const results=await Promise.all(Array.from({length:4},(_,i)=>native.callJson('compute("async n=>{await sendMessage({method:\'delay\',time:2});return n*2}",'+i+')','<parallel>',`worker-${i}`)));
      assert.deepEqual(results,[0,2,4,6]);for(let i=0;i<4;i++)assert(events.some(e=>e.method==='delay'&&e.trace===`worker-${i}`));
    });
    await test('worker Promise double/late callbacks and getter reentry cannot deadlock RPC settlement',async()=>{
      assert.equal(await native.callJson('compute("async()=>await sendMessage({method:\'double\'})")','<worker-double>','worker-double-owner'),42);
      assert.equal(await native.callJson('compute("async()=>{const v=await sendMessage({method:\'doubleReentry\'});return v.n}")','<worker-getter-reentry>','worker-reentry-owner'),42);
      for(const cb of held){cb.reject(Error('synthetic late failure'));cb.resolve(777)}held=[];await gc();
      assert.equal(await native.callJson('compute("()=>42")'),42);
    });
    await test('actual worker host HTTP-shaped Map response and synthetic async delay work',async()=>{
      assert.equal(await native.callJson('compute("async()=>{const r=await sendMessage({method:\'http\'});return r.status===200&&r.body===\'synthetic-http\'&&r.headers[\'x-probe\']===\'ok\'}")','<http-rpc>','http-owner'),true);
    });
    await test('nested compute and worker remote callbacks fail promptly without four-slot deadlock',async()=>{
      await assert.rejects(native.callJson('compute("()=>compute(\'()=>42\')")','<nested>','nested-owner'));
      await assert.rejects(native.callJson('compute("()=>sendMessage({method:\'UI\',callback:()=>1})")','<callback>','callback-owner'));
      assert.equal(await native.callJson('compute("()=>42")'),42);
    });
    await test('host getter graph changes cannot bypass safe recursive bridge',async()=>{
      readCount=0;await assert.rejects(native.callJson('compute("()=>sendMessage({method:\'changedGetter\'})")'));
      readCount=0;await assert.rejects(native.callJson('compute("()=>sendMessage({method:\'changedCycle\'})")'));
      assert.equal(await native.callJson('42'),42);
    });
    await test('four real small image jobs fit admission and produce exact RGBA rotation',async()=>{
      const input=Uint8Array.from([11,21,31,255,12,22,32,255,13,23,33,255,14,24,34,255,15,25,35,255,16,26,36,255]).buffer;
      const jobs=Array.from({length:4},(_,i)=>native.transformIsolated(input,2,3,'let modifyImage=i=>i.copyAndRotate90();',`image-${i}`,false,2000));
      const out=await Promise.all(jobs),expected=[15,25,35,255,13,23,33,255,11,21,31,255,16,26,36,255,14,24,34,255,12,22,32,255];
      for(const item of out){assert.equal(item.width,3);assert.equal(item.height,2);assert.deepEqual([...new Uint8Array(item.rgba)],expected)}
    });
    await test('actual native CPU/microtask limits keep host event loop responsive and recover',async()=>{
      const raw=new Uint8Array([1,2,3,255]).buffer;let beats=0;const heartbeat=setInterval(()=>beats++,5);
      try{
        await assert.rejects(native.transformIsolated(raw,1,1,'let modifyImage=i=>{while(true){}};','cpu-timeout',false,100));
        await assert.rejects(native.transformIsolated(raw,1,1,'const f=()=>Promise.resolve().then(f);f();let modifyImage=i=>i;','job-timeout',false,100));
        assert(beats>3);assert.equal((await native.transformIsolated(raw,1,1,'let modifyImage=i=>i;','recovered',false,2000)).width,1);
      }finally{clearInterval(heartbeat)}
    });
    await test('matching Trace cancellation interrupts live native compute and not unrelated images',async()=>{
      const cancelled=native.callJson('compute("()=>{while(true){}}")','<cancel>','cancel-owner');const rejection=assert.rejects(cancelled);
      await delay(25);assert(native.cancelIsolated('cancel-owner')>=1);await rejection;
      assert.equal((await native.transformIsolated(new Uint8Array([1,2,3,255]).buffer,1,1,'let modifyImage=i=>i;','unrelated',false,2000)).width,1);
    });
    await test('actual garbage collection releases hundreds of external handles without disabling next request',async()=>{
      let handles=await Promise.all(Array.from({length:300},()=>native.callJson('()=>42')));assert.equal(handles.length,300);handles=null;
      await gc();const stats=native.runtimeStats();assert.equal(stats.externalHandles,0);assert.equal(stats.ownedRoots,0);
      assert.equal(stats.pendingCalls,0);assert.equal(stats.ownershipUncertain,false);assert.equal(await native.callJson('42'),42);
    });
    await test('actual environment cleanup with live externals/unsettled bridges exits cleanly',async()=>{
      const child=spawnSync(process.execPath,['--expose-gc',__filename,'--shutdown-child'],{stdio:'inherit',timeout:5000});
      assert.equal(child.error,undefined);assert.equal(child.status,0);
    });
    fs.appendFileSync(auditPath,`NAPI_HOST_PASS cases=${count}\n`);console.log(`NAPI_HOST_PASS cases=${count}; actual Node NAPI/TSFN, NOT phone ArkTS/ImageKit evidence.`);
  })().catch(error=>{fs.appendFileSync(auditPath,`[FAIL] ${String(error)}\n`);console.error(error);process.exitCode=1});
}
