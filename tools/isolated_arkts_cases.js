'use strict';
// Production ArkTS lifecycle tests. NAPI/ImageKit are controlled fakes, not native/device evidence.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..');
const source = relative => fs.readFileSync(path.join(root, relative), 'utf8')
  .replace(/^import[\s\S]*?from [^;]+;\r?\n/gm, '').replace(/\bexport /g, '');
const load = (ctx, relative, name) => {
  vm.runInContext(stripTypeScriptTypes(source(relative), {mode:'transform'}) + `\nglobalThis.Subject=${name};`, ctx);
  return ctx.Subject;
};
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((a,b)=>{resolve=a;reject=b}); return {promise,resolve,reject}; }
let count = 0;
async function test(name, body) { await body(); count++; console.log(`PASS ${name}`); }
function images() {
  const jobs=[], cancelled=[], releases={source:0,input:0,output:0,packer:0};
  const audits=[];
  const ctx=vm.createContext({Set,Uint8Array,ArrayBuffer,Promise,
    Log:{audit:(...args)=>audits.push(args)}, ImageScriptBridge:{byteSize:(w,h)=>w*h*4},
    transformIsolated:async(rgba,width,height,script,trace)=>{
      const d=deferred(); jobs.push({trace,d}); await d.promise; return {rgba,width,height};
    },cancelIsolated:trace=>{cancelled.push(trace);let n=0;for(const j of jobs)if(j.trace===trace){j.d.reject(Error('native cancel'));n++}return n},
    image:{PixelMapFormat:{RGBA_8888:3},AlphaType:{PREMUL:2,UNPREMUL:3},
      createImageSource:()=>({getImageInfo:async()=>({size:{width:1,height:1}}),
        createPixelMap:async()=>({getImageInfo:async()=>({alphaType:3}),readPixelsToBuffer:async()=>{},release:async()=>releases.input++}),
        release:async()=>releases.source++}),
      createPixelMap:async()=>({release:async()=>releases.output++}),
      createImagePacker:()=>({packToData:async()=>new ArrayBuffer(4),release:async()=>releases.packer++})}
  });
  const Transforms=load(ctx,'entry/src/main/ets/network/ImageTransforms.ets','ImageTransforms');
  return {ctx,Transforms,jobs,cancelled,releases,audits};
}
(async()=>{
  await test('queued trace cancellation rejects promptly without waiting for four active jobs',async()=>{
    const e=images(), raw=new ArrayBuffer(4);
    const active=Array.from({length:4},(_,i)=>e.Transforms.apply(raw,'script',`keep-${i}`));
    await tick();assert.equal(e.jobs.length,4);
    const queued=e.Transforms.apply(raw,'script','queued');const rejected=assert.rejects(queued,/CANCELLED/);
    await tick();e.Transforms.cancel('queued');await rejected;
    assert.equal(e.jobs.length,4);e.jobs.forEach(j=>j.d.resolve());await Promise.all(active);
    const recovered=e.Transforms.apply(raw,'script','recovered');await tick();e.jobs.at(-1).d.resolve();await recovered;
    assert.equal(e.Transforms.active,0);assert.equal(e.Transforms.requests.size,0);
  });
  await test('request admission caps all active plus queued requests at 32 and recovers after cancel',async()=>{
    const e=images(),raw=new ArrayBuffer(4),pending=[];
    for(let i=0;i<32;i++)pending.push(e.Transforms.apply(raw,'script',`bounded-${i}`).then(()=>false,()=>true));
    await tick();assert.equal(e.Transforms.requests.size,32);assert.equal(e.jobs.length,4);
    await assert.rejects(e.Transforms.apply(raw,'script','over-cap'),/ADMISSION_LIMIT/);
    assert.equal(e.Transforms.encodedRetained,128);
    for(let i=0;i<32;i++)e.Transforms.cancel(`bounded-${i}`);
    assert((await Promise.all(pending)).every(Boolean));
    assert.equal(e.Transforms.encodedRetained,0);assert.equal(e.Transforms.decodedRetained,0);assert.equal(e.Transforms.requests.size,0);
    const recovered=e.Transforms.apply(raw,'script','cap-recovered');await tick();e.jobs.at(-1).d.resolve();await recovered;
  });
  await test('oversized encoded input fails before decoder allocation; aggregate retained inputs capped at 128MiB',async()=>{
    const e=images(),limit=128*1024*1024;let decoders=0;const create=e.ctx.image.createImageSource;
    e.ctx.image.createImageSource=(...args)=>{decoders++;return create(...args)};
    await assert.rejects(e.Transforms.apply({byteLength:limit+1},'script','too-large'),/ADMISSION_LIMIT/);
    assert.equal(decoders,0);assert.equal(e.Transforms.encodedRetained,0);
    const a=e.Transforms.apply({byteLength:limit/2},'script','encoded-A').then(()=>false,()=>true);
    const b=e.Transforms.apply({byteLength:limit/2},'script','encoded-B').then(()=>false,()=>true);
    await assert.rejects(e.Transforms.apply({byteLength:1},'script','encoded-over'),/ADMISSION_LIMIT/);
    await tick();assert.equal(decoders,2);assert.equal(e.Transforms.encodedRetained,limit);
    e.Transforms.cancel('encoded-A');e.Transforms.cancel('encoded-B');assert.equal(await a,true);assert.equal(await b,true);
    assert.equal(e.Transforms.encodedRetained,0);assert.equal(e.Transforms.decodedRetained,0);
  });
  await test('aggregate RGBA reservation rejects before second PixelMap/buffer allocation and recovers',async()=>{
    const e=images(),reserve=80*1024*1024;let decoded=0,buffers=0;const create=e.ctx.image.createImageSource;
    e.ctx.ImageScriptBridge.byteSize=()=>reserve;
    // Virtual sizes exercise admission arithmetic without allocating giant host buffers.
    e.ctx.ArrayBuffer=function(){buffers++;return new ArrayBuffer(4)};
    e.ctx.image.createImageSource=(...args)=>{const decoder=create(...args),pixels=decoder.createPixelMap;
      decoder.createPixelMap=(...opts)=>{decoded++;return pixels(...opts)};return decoder};
    const a=e.Transforms.apply(new ArrayBuffer(4),'script','rgba-A').then(()=>false,()=>true);await tick();
    assert.equal(e.Transforms.decodedRetained,reserve);assert.equal(decoded,1);assert.equal(buffers,1);
    await assert.rejects(e.Transforms.apply(new ArrayBuffer(4),'script','rgba-B'),/RGBA_LIMIT/);
    assert.equal(decoded,1);assert.equal(buffers,1);assert.equal(e.Transforms.decodedRetained,reserve);
    e.Transforms.cancel('rgba-A');assert.equal(await a,true);assert.equal(e.Transforms.decodedRetained,0);assert.equal(e.Transforms.encodedRetained,0);
    e.ctx.ArrayBuffer=ArrayBuffer;e.ctx.ImageScriptBridge.byteSize=(w,h)=>w*h*4;
    const recovered=e.Transforms.apply(new ArrayBuffer(4),'script','rgba-recovered');await tick();e.jobs.at(-1).d.resolve();await recovered;
    assert.equal(e.Transforms.decodedRetained,0);assert.equal(e.Transforms.encodedRetained,0);
  });
  await test('decoded ImageKit input is released once before native surface allocation',async()=>{
    const e=images();
    e.ctx.transformIsolated=async(rgba,width,height)=>{
      assert.equal(e.releases.input,1);assert.equal(e.releases.source,1);
      return {rgba,width,height};
    };
    await e.Transforms.apply(new ArrayBuffer(4),'script','input-lifetime');
    assert.equal(e.releases.input,1);assert.equal(e.releases.source,1);
    assert.equal(e.releases.output,1);assert.equal(e.releases.packer,1);
  });
  await test('decoded input release rejection still releases source once and prevents native dispatch',async()=>{
    const e=images();
    e.ctx.image.createImageSource=()=>({getImageInfo:async()=>({size:{width:1,height:1}}),
      createPixelMap:async()=>({getImageInfo:async()=>({alphaType:3}),readPixelsToBuffer:async()=>{},
        release:async()=>{e.releases.input++;throw Error('input release failure')}}),
      release:async()=>e.releases.source++});
    await assert.rejects(e.Transforms.apply(new ArrayBuffer(4),'script','release-error'),/input release failure/);
    assert.equal(e.releases.input,1);assert.equal(e.releases.source,1);assert.equal(e.jobs.length,0);
  });
  await test('native executing cancellation only affects matching trace and releases decoder resources',async()=>{
    const e=images(),raw=new ArrayBuffer(4);
    const cancelled=e.Transforms.apply(raw,'script','A'), kept=e.Transforms.apply(raw,'script','B');
    const rejection=assert.rejects(cancelled,/cancel/);await tick();e.Transforms.cancel('A');
    e.jobs.find(j=>j.trace==='B').d.resolve();await rejection;await kept;
    assert.equal(e.releases.input,2);assert.equal(e.releases.source,2);assert.equal(e.Transforms.active,0);
  });
  await test('cancel during decode before native registry exists never dispatches stale script',async()=>{
    const e=images(),info=deferred();
    e.ctx.image.createImageSource=()=>({getImageInfo:()=>info.promise,release:async()=>e.releases.source++});
    const pending=e.Transforms.apply(new ArrayBuffer(4),'script','decode');const rejection=assert.rejects(pending,/CANCELLED/);
    await tick();e.Transforms.cancel('decode');info.resolve({size:{width:1,height:1}});await rejection;
    assert.equal(e.jobs.length,0);assert.equal(e.releases.source,1);assert.equal(e.Transforms.active,0);
  });
  await test('cancel during PNG encoding rejects instead of publishing stale bytes',async()=>{
    const e=images(),encoded=deferred();e.ctx.image.createImagePacker=()=>({packToData:()=>encoded.promise,release:async()=>e.releases.packer++});
    const pending=e.Transforms.apply(new ArrayBuffer(4),'script','encode');const rejection=assert.rejects(pending,/CANCELLED/);
    await tick();e.jobs[0].d.resolve();await tick();
    assert.equal(e.Transforms.encodedRetained,4);assert.equal(e.Transforms.decodedRetained,4);
    e.Transforms.cancel('encode');encoded.resolve(new ArrayBuffer(4));await rejection;
    assert.equal(e.releases.output,1);assert.equal(e.releases.packer,1);assert.equal(e.Transforms.active,0);
    assert.equal(e.Transforms.encodedRetained,0);assert.equal(e.Transforms.decodedRetained,0);
    assert(!e.audits.some(a=>a[1]==='图片变换返回'));
  });
  await test('caller continuation checked after final encode even without explicit cancel',async()=>{
    const e=images(),encoded=deferred();let current=true;
    e.ctx.image.createImagePacker=()=>({packToData:()=>encoded.promise,release:async()=>e.releases.packer++});
    const pending=e.Transforms.apply(new ArrayBuffer(4),'script','continuation',()=>current);
    const rejection=assert.rejects(pending,/CANCELLED/);await tick();e.jobs[0].d.resolve();await tick();current=false;
    encoded.resolve(new ArrayBuffer(4));await rejection;assert.equal(e.releases.output,1);
  });
  await test('packer creation failure still releases transformed PixelMap',async()=>{
    const e=images();e.ctx.image.createImagePacker=()=>{throw Error('packer unavailable')};
    const pending=e.Transforms.apply(new ArrayBuffer(4),'script','packer');const rejection=assert.rejects(pending,/packer unavailable/);
    await tick();e.jobs[0].d.resolve();await rejection;assert.equal(e.releases.output,1);assert.equal(e.releases.source,1);
  });
  await test('empty-script requests still respect caller cancellation',async()=>{
    const e=images();await assert.rejects(e.Transforms.apply(new ArrayBuffer(4),'','empty',()=>false),/CANCELLED/);assert.equal(e.jobs.length,0);
  });
  await test('shareable transformed GET coalesces one producer for independently leased consumers',async()=>{
    const e=images();let produces=0,released=0;
    const Loader=load(e.ctx,'entry/src/main/ets/network/ImageLoader.ets','ImageLoader');
    e.ctx.imageCacheKey=()=> 'fixture-identity';
    e.ctx.CookieJar={header:()=>''};
    const config={method:'GET',url:'https://fixture.invalid/image',modifyImage:'script',headers:new Map()};
    assert.equal(Loader.ownsRequest(config),false,'pure GET plus transform is shareable across consumers');
    const decoded={release:async()=>{released++}};
    Loader.produceShared=async()=>{produces++;return decoded};
    const [a,b]=await Promise.all([Loader.acquireRequest(config,'A'),Loader.acquireRequest(config,'B')]);
    assert.notStrictEqual(a,b,'each consumer owns its own idempotent lease');
    assert.strictEqual(a.pixelMap,decoded);assert.equal(produces,1,'one download/transform per identity, not per consumer');
    a.release();assert.strictEqual(b.pixelMap,decoded,'retiring one lease must not disturb another consumer');
    b.release();assert.equal(released,0,'the loader owns the decoded map, never the lease');
  });
  await test('cancelled final owned decode releases PixelMap before rejecting',async()=>{
    const e=images(),decode=deferred();let current=true;
    e.ctx.ImagePipeline={fetch:async()=>new ArrayBuffer(4)};
    e.ctx.image.createImageSource=()=>({createPixelMap:()=>decode.promise,release:async()=>e.releases.source++});
    const Loader=load(e.ctx,'entry/src/main/ets/network/ImageLoader.ets','ImageLoader');
    const pending=Loader.loadRequest({method:'POST',modifyImage:''},'owned',()=>current);const rejection=assert.rejects(pending,/CANCELLED/);
    await tick();current=false;decode.resolve({release:async()=>e.releases.output++});await rejection;
    assert.equal(e.releases.output,1);assert.equal(e.releases.source,1);
  });
  await test('cancelled shared consumer rejects without releasing cache-owned PixelMap',async()=>{
    const e=images(),shared=deferred();let current=true;
    const Loader=load(e.ctx,'entry/src/main/ets/network/ImageLoader.ets','ImageLoader');Loader.load=()=>shared.promise;
    const pending=Loader.loadRequest({method:'GET',modifyImage:''},'shared',()=>current);const rejection=assert.rejects(pending,/CANCELLED/);
    current=false;shared.resolve({release:async()=>e.releases.output++});await rejection;assert.equal(e.releases.output,0);
  });
  await test('JsEngine configuration precedes contracts and concurrent init runs once',async()=>{
    const events=[],gate=deferred();
    const ctx=vm.createContext({Promise,Uint8Array,ArrayBuffer,APP_VERSION:'1.17.0',
      quickjsVersion:()=>{events.push('version');return 'fake'},setGlobalString:()=>{},setMessageHandler:()=>{},
      evaluate:(_code,file)=>{events.push(file);return 'synthetic smoke'},configureIsolated:(init,html,rpc,audit)=>{
        events.push('configure');assert.equal(init,'init.js');assert.equal(html,'html_engine.js');assert.equal(rpc({}),null);audit('t','s','m');},
      JsMessageHandler:{handleMessage:()=>null},Log:{audit:()=>{},info:()=>{},error:()=>{},warn:()=>{}},
      AppContext:{context:{resourceManager:{getRawFileContent:async name=>name}}},
      util:{TextDecoder:{create:()=>({decodeToString:value=>value})}}
    });
    const Engine=load(ctx,'entry/src/main/ets/source/JsEngine.ets','JsEngine');
    Engine.verifyBridgeContracts=async()=>{events.push('bridge');await gate.promise};
    Engine.verifyIsolatedContracts=async()=>events.push('isolated');
    const first=Engine.init(),second=Engine.init();await tick();assert.equal(events.filter(e=>e==='version').length,1);
    assert(events.indexOf('configure')<events.indexOf('bridge'));assert.equal(Engine.isAvailable,false);
    gate.resolve();await Promise.all([first,second]);assert.equal(Engine.isAvailable,true);assert.equal(Engine.isScriptLoaded,true);
    assert(events.indexOf('isolated')<events.indexOf('<smoke>'));
  });
  await test('failed isolated contract leaves engine unavailable and permits initialization retry',async()=>{
    const evaluations=[];
    const ctx=vm.createContext({Promise,APP_VERSION:'1.17.0',quickjsVersion:()=>'',setGlobalString:()=>{},setMessageHandler:()=>{},
      configureIsolated:()=>{},evaluate:(_code,file)=>{evaluations.push(file);return ''},JsMessageHandler:{handleMessage:()=>null},Log:{info:()=>{},error:()=>{}},
      AppContext:{context:{resourceManager:{getRawFileContent:async()=>''}}},util:{TextDecoder:{create:()=>({decodeToString:v=>v})}}});
    const Engine=load(ctx,'entry/src/main/ets/source/JsEngine.ets','JsEngine');Engine.verifyBridgeContracts=async()=>{};
    Engine.verifyIsolatedContracts=async()=>{throw Error('synthetic contract failed')};await Engine.init();
    assert.equal(Engine.isAvailable,false);assert.equal(Engine.isScriptLoaded,false);
    Engine.verifyIsolatedContracts=async()=>{};await Engine.init();assert.equal(Engine.isAvailable,true);assert.equal(Engine.error,'');
    for(const file of ['<init>','<sendmessage_shim>','<html_engine>'])assert.equal(evaluations.filter(v=>v===file).length,1);
  });
  await test('startup probes execute their actual generated JS against upstream init/html (bridge mocked)',async()=>{
    const init=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/init.js'),'utf8');
    const html=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/html_engine.js'),'utf8');
    const pending=new Map(),audits=[];let computeCalls=0;
    const ctx=vm.createContext({Promise,Map,Set,Uint8Array,ArrayBuffer,APP_VERSION:'1.17.0',
      Log:{audit:(...args)=>audits.push(args)},
      transformIsolated:async(raw,width,height,script,trace)=>{
        if(script.includes('while (true)')){const d=deferred();pending.set(trace,d);return d.promise}
        if(script.includes('copyAndRotate90')){
          const input=new Uint8Array(raw),output=new Uint8Array(raw.byteLength);
          for(let y=0;y<height;y++)for(let x=0;x<width;x++)output.set(input.subarray((y*width+x)*4,(y*width+x+1)*4),(x*height+height-y-1)*4);
          return {width:height,height:width,rgba:output.buffer};
        }
        return {width,height,rgba:raw};
      },cancelIsolated:trace=>{const d=pending.get(trace);if(!d)return 0;d.reject(Error('cancelled'));pending.delete(trace);return 1},
      compute:async(code,...args)=>{
        computeCalls++;
        const worker=vm.createContext({Promise,Map,Set,Uint8Array,ArrayBuffer,appVersion:'1.17.0',
          sendMessage:message=>{structuredClone(message);if(message.method==='getPlatform')return 'ohos';
            if(message.method==='delay')return Promise.resolve(null);if(message.method==='log')return null;throw Error('unsupported host message')}});
        vm.runInContext(init,worker);vm.runInContext(html,worker);
        const fn=vm.runInContext(code,worker);if(typeof fn!=='function')throw Error('not function');
        return structuredClone(await fn(...structuredClone(args)));
      }
    });
    ctx.evaluate=(code)=>vm.runInContext(code,ctx);ctx.callJsonNative=async(code)=>vm.runInContext(code,ctx);
    const Engine=load(ctx,'entry/src/main/ets/source/JsEngine.ets','JsEngine');
    await Engine.verifyIsolatedContracts();assert.equal(computeCalls,9);
    assert(audits.some(args=>args[1]==='compute验收返回'));assert(audits.some(args=>args[1]==='隔离像素验收返回'));
    assert.equal(ctx.__veneraMainOnlyProbe,undefined);assert.equal(pending.size,0);
  });
  console.log(`PASS ${count} production ArkTS isolated lifecycle cases; native threads/SDK/device not mocked into evidence.`);
})().catch(error=>{console.error(error);process.exitCode=1});
