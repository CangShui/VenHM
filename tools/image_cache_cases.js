'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/image-cache-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
fs.writeFileSync(log,'[请求到达] TraceID=image-cache-tests production cache key/loader, isolated filesystem and transport\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function environment(){
  const files=new Map(),dirs=new Set(),calls=[],releases=[],transforms=[];
  let cookie='';
  const context=vm.createContext({
    Uint8Array,ArrayBuffer,
    AppContext:{imageCacheDir:'/cache/images'},CookieJar:{header:()=>cookie},
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),warn:()=>{}},
    util:{TextEncoder:class{encodeInto(v){return Buffer.from(v)}}},
    cryptoFramework:{createMd:a=>{assert.equal(a,'SHA256');let data;return {updateSync:v=>data=v.data,digestSync:()=>({data:crypto.createHash('sha256').update(data).digest()})}}},
    fs:{OpenMode:{READ_ONLY:1,CREATE:2,READ_WRITE:4,TRUNC:8},
      accessSync:p=>files.has(p)||dirs.has(p),mkdirSync:p=>dirs.add(p),
      openSync:(p,m)=>{if(m&8)files.set(p,new ArrayBuffer(0));if(!files.has(p))throw Error('missing file');return {fd:p}},
      closeSync:()=>{},writeSync:(fd,b)=>files.set(fd,b),
      readSync:(fd,b)=>{new Uint8Array(b).set(new Uint8Array(files.get(fd)));return b.byteLength},
      statSync:p=>({size:files.get(p).byteLength}),
      unlinkSync:p=>files.delete(p),renameSync:(a,b)=>{files.set(b,files.get(a));files.delete(a)}},
    HttpClient:{getBytes:async(u,h)=>{calls.push({u,h});return {ok:true,status:200,bytes:Uint8Array.from([1,2,3,255]).buffer}}},
    ImageTransforms:{apply:async(b,s,t)=>{transforms.push({s,t});return b}},
    image:{createImageSource:source=>({
      createPixelMap:async()=>{
        const bytes=typeof source==='string'?files.get(source):source;
        if(!bytes||new Uint8Array(bytes)[0]===0)throw Error('invalid image');
        return {bytes,release:async()=>releases.push('pixel')};
      },release:async()=>releases.push('decoder')})}
  });
  // ImageLoader now persists through CacheStore; without it the loader degrades
  // to memory-only and the disk-hit assertions would silently stop testing disk.
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/foundation/CacheStore.ets')+'\n'+
    read('entry/src/main/ets/network/ImageCacheKey.ets')+'\n'+
    read('entry/src/main/ets/network/ImageLoader.ets'),{mode:'transform'})+
    '\nglobalThis.Loader=ImageLoader;globalThis.key=imageCacheKey;' +
    'globalThis.__store=new CacheStore("/cache/images",".img",1073741824);' +
    'globalThis.CacheManager={imageStore:()=>globalThis.__store};',context);
  return {context,Loader:context.Loader,key:context.key,files,calls,releases,transforms,setCookie:v=>cookie=v};
}
let count=0;
async function test(name,body){await body();count++;fs.appendFileSync(log,`[响应返回] TraceID=image-cache-tests PASS ${name}\n`)}
(async()=>{
  await test('SHA256 key stable across header order/case but isolates cookies, values and transform',async()=>{
    const e=environment(),a=e.key('https://x/img',new Map([['X-A','1'],['X-B','2']]),'cookie','script');
    assert.match(a,/^[0-9a-f]{64}$/);
    assert.equal(a,e.key('https://x/img',new Map([['x-b','2'],['x-a','1']]),'cookie','script'));
    for(const key of [e.key('https://x/img',new Map([['X-A','different'],['X-B','2']]),'cookie','script'),
      e.key('https://x/img',new Map([['X-A','1'],['X-B','2']]),'other','script'),
      e.key('https://x/img',new Map([['X-A','1'],['X-B','2']]),'cookie','other')])assert.notEqual(a,key);
    assert.ok(!a.includes('cookie')&&!a.includes('script'));
  });
  await test('identity tuple avoids delimiter collision',async()=>{
    const e=environment();assert.notEqual(e.key('url\n[]',new Map(),'',''),e.key('url',new Map(),'\n[]',''));
  });
  await test('memory and disk hits avoid duplicate transport and release all decoders',async()=>{
    const e=environment(),a=await e.Loader.load('u');assert.strictEqual(await e.Loader.load('u'),a);
    e.Loader.clearMemory();await e.Loader.load('u');
    assert.equal(e.calls.length,1);assert.equal(e.releases.filter(x=>x==='decoder').length,2);
    assert.ok([...e.files.keys()].every(p=>!p.endsWith('.part')));
  });
  await test('concurrent same identity coalesced, no two cache writes racing',async()=>{
    const e=environment(),results=await Promise.all(Array.from({length:10},()=>e.Loader.load('u')));
    assert.equal(e.calls.length,1);for(const r of results)assert.strictEqual(r,results[0]);
  });
  await test('corrupt cache deletes only its own item and redownloads once',async()=>{
    const e=environment(),key=e.key('u',new Map(),'');
    e.files.set(`/cache/images/${key}.img`,Uint8Array.from([0]).buffer);
    e.files.set('/cache/images/unrelated.img',Uint8Array.from([0]).buffer);
    await e.Loader.load('u');assert.equal(e.calls.length,1);
    assert.ok(e.files.has('/cache/images/unrelated.img'));
  });
  await test('invalid new body never poisons disk cache; pending request cleared for retry',async()=>{
    const e=environment();e.context.HttpClient.getBytes=async()=>({ok:true,status:200,bytes:Uint8Array.from([0]).buffer});
    await assert.rejects(e.Loader.load('u'));assert.equal(e.files.size,0);
    e.context.HttpClient.getBytes=async()=>({ok:true,status:200,bytes:Uint8Array.from([1]).buffer});
    await e.Loader.load('u');assert.equal(e.files.size,1);
  });
  await test('same URL different account cookie never reuses cached pixels',async()=>{
    const e=environment();e.setCookie('first');await e.Loader.load('u');
    e.setCookie('second');await e.Loader.load('u');assert.equal(e.calls.length,2);assert.equal(e.files.size,2);
  });
  await test('same URL different transform never reuses original/scrambled cache',async()=>{
    const e=environment();await e.Loader.load('u',undefined,'first');await e.Loader.load('u',undefined,'second');
    assert.equal(e.calls.length,2);assert.deepEqual(e.transforms.map(t=>t.s),['first','second']);
  });
  await test('transform failures do not cache original images and can retry',async()=>{
    const e=environment();e.context.ImageTransforms.apply=async()=>{throw Error('script failed')};
    await assert.rejects(e.Loader.load('u',undefined,'transform'));assert.equal(e.files.size,0);
  });
  await test('local files avoid network/cache writes',async()=>{
    const e=environment();e.files.set('/local/image.png',Uint8Array.from([1,2]).buffer);
    await e.Loader.load('file:///local/image.png');assert.equal(e.calls.length,0);assert.equal(e.files.size,1);
  });
  await test('nonGET/body/callback image request uses full pipeline without URL-only cache reuse',async()=>{
    const e=environment(),dynamic=[];e.context.ImagePipeline={fetch:async c=>{dynamic.push(c);return Uint8Array.from([1,2]).buffer}};
    const c={url:'u',method:'POST',headers:new Map(),data:'body',modifyImage:'',unsupported:[]};
    assert.equal(e.Loader.ownsRequest(c),true);
    const a=await e.Loader.loadRequest(c,'one'),b=await e.Loader.loadRequest(c,'two');
    assert.notStrictEqual(a,b);assert.equal(dynamic.length,2);assert.equal(e.files.size,0);assert.equal(e.calls.length,0);
    await a.release();await b.release();
  });
  await test('cancelled dynamic request refused before invoking pipeline',async()=>{
    const e=environment();e.context.ImagePipeline={fetch:async()=>{throw Error('should not fetch')}};
    await assert.rejects(e.Loader.loadRequest({method:'POST'},'cancelled',()=>false),/CANCELLED/);
    assert.equal(e.files.size,0);
  });
  console.log(`PASS ${count} production image cache identity/corruption/concurrency cases (fake filesystem, not device proof).`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
