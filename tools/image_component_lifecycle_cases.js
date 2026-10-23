'use strict';
// Production AsyncComicImage lifecycle under the ImageLease contract: the
// component retires only its own idempotent lease and never releases a shared
// decoded PixelMap. PixelMap/ImageLoader SDK calls are mocked; no device proof.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/image-component-lifecycle-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=image-component-tests production AsyncComicImage lease lifecycle; SDK mocked\n');
const raw=fs.readFileSync(path.join(root,'entry/src/main/ets/components/ComicWidgets.ets'),'utf8');
const source=(raw.slice(0,raw.indexOf('  build() {'))+'}').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'')
  .replace(/@(?:Entry|Component|State|Prop)\s*|@Watch\('[^']+'\)\s*/g,'').replace('struct AsyncComicImage','class AsyncComicImage');
function environment(){
  const requests=[],rejections=[],warnings=[],cancels=[],configs=[],resolved=[];
  const ctx=vm.createContext({
    ImageFit:{Cover:1},ImageRequestConfig:class{url='';method='GET';headers=new Map();modifyImage=''},
    SourceManager:{find:key=>({key})},ImageRequests:{resolve:async(source,url,thumbnail,comicId,epId)=>{
      resolved.push({source:source.key,url,thumbnail,comicId,epId});return {url,method:'GET'};
    }},
    ImageLoader:{cancelOwned:trace=>cancels.push(trace),
      acquireRequest:(config,trace,active,thumbnail)=>{
        configs.push({config,trace,active,thumbnail});
        return new Promise((resolve,reject)=>{requests.push(resolve);rejections.push(reject)});
      }},
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),warn:(t,m)=>warnings.push(m)}
  });
  const geometry=fs.readFileSync(path.join(root,'entry/src/main/ets/features/ReaderImageLayout.ets'),'utf8').replace(/\bexport /g,'');
  vm.runInContext(stripTypeScriptTypes(geometry+'\n'+source,{mode:'transform'})+'\nglobalThis.Component=AsyncComicImage;',ctx);
  const p=new ctx.Component();p.url='u';p.sourceKey='fixture';
  return {p,requests,rejections,warnings,cancels,configs,resolved};
}
/** Distinct leases over one decoded map, mirroring one lease per consumer. */
function pixel(){
  const state={leaseReleases:0,mapReleases:0};
  const map={getImageInfo:async()=>({size:{width:10,height:20}}),release:async()=>{state.mapReleases++}};
  const lease={pixelMap:map,release:()=>{state.leaseReleases++}};
  return {lease,map,state,count:()=>state.leaseReleases,mapCount:()=>state.mapReleases};
}
const tick=()=>new Promise(r=>setImmediate(r));let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=image-component-tests PASS ${name}\n`)}
async function loaded(){const e=environment(),a=pixel();e.p.aboutToAppear();await tick();e.requests[0](a.lease);await tick();return {e,a}}
function change(e,url='v'){e.p.url=url;e.p.reloadImage()}
(async()=>{
  await test('same-identity reuse preserves decoded JM image without cancel or second fetch',async()=>{
    const {e,a}=await loaded();e.p.aboutToReuse({url:'u'});await tick();
    assert.strictEqual(e.p.pixelMap,a.map,'same-identity reuse must not blank a decoded image');
    assert.equal(e.requests.length,1,'same identity must not reload/retransform');
    assert.equal(a.count(),0,'reuse must not retire the current lease');assert.equal(e.cancels.length,0);
  });
  await test('watcher plus reuse plus appear notifications issue exactly one final-identity request',async()=>{
    const e=environment();e.p.aboutToAppear();e.p.reloadImage();e.p.aboutToReuse({url:'u'});e.p.aboutToAppear();await tick();
    assert.equal(e.requests.length,1);assert.equal(e.cancels.length,0);
    change(e);e.p.aboutToReuse({url:'v',sourceKey:'jm',comicId:'comic',epId:'episode',thumbnail:false});e.p.reloadImage();await tick();
    assert.equal(e.requests.length,2);assert.equal(e.cancels.length,1);assert.deepEqual(e.resolved.at(-1),{source:'jm',url:'v',thumbnail:false,comicId:'comic',epId:'episode'});
    assert.equal(e.configs.at(-1).thumbnail,false,'thumbnail must be snapshotted for the request, not read late');
  });
  await test('every request input is watched; presentation inputs are not request identity',async()=>{
    for(const field of ['url','sourceKey','comicId','epId','thumbnail'])assert.match(raw,new RegExp("@Prop @Watch\\('reloadImage'\\) "+field+':'));
    const {e,a}=await loaded();e.p.naturalHeight=true;e.p.splitWideImage=true;e.p.zoomReset++;e.p.resetZoom();e.p.reloadImage();await tick();
    assert.equal(e.requests.length,1);assert.strictEqual(e.p.pixelMap,a.map);assert.equal(e.cancels.length,0);
    for(const field of ['sourceKey','comicId','epId','thumbnail']){e.p[field]=field==='thumbnail'?!e.p[field]:e.p[field]+'x';e.p.reloadImage();await tick()}
    assert.equal(e.requests.length,5);
  });
  await test('lease retired exactly once on disappear without releasing the decoded map',async()=>{
    const {e,a}=await loaded();e.p.aboutToDisappear();e.p.aboutToDisappear();await tick();
    assert.equal(a.count(),1);assert.equal(a.mapCount(),0,'the loader owns the map, not the widget');
    assert.equal(e.cancels.length,0);assert.equal(e.p.pixelMap,undefined);
  });
  await test('two consumers of one shared image never release its PixelMap',async()=>{
    const e=environment(),f=environment(),shared=pixel(),eLease={pixelMap:shared.map,release:()=>{shared.state.leaseReleases++}};
    const fLease={pixelMap:shared.map,release:()=>{shared.state.leaseReleases++}};
    e.p.aboutToAppear();f.p.aboutToAppear();await tick();e.requests[0](eLease);f.requests[0](fLease);await tick();
    e.p.aboutToDisappear();await tick();
    assert.strictEqual(f.p.pixelMap,shared.map,'the other consumer must keep rendering');
    assert.equal(shared.mapCount(),0,'no consumer may release a shared decoded map');
  });
  await test('stale request cannot replace new image; only its own lease is retired',async()=>{
    const e=environment(),a=pixel(),b=pixel();e.p.aboutToAppear();await tick();change(e);await tick();
    e.requests[1](b.lease);await tick();e.requests[0](a.lease);await tick();
    assert.strictEqual(e.p.pixelMap,b.map);assert.equal(a.count(),1);assert.equal(b.count(),0);assert.equal(e.cancels.length,1);
    e.p.aboutToDisappear();await tick();assert.equal(b.count(),1);assert.equal(e.cancels.length,1);
  });
  await test('disappear during natural-size query retires the late lease without cancelling a decoded trace',async()=>{
    const e=environment(),a=pixel();let finish;e.p.naturalHeight=true;a.map.getImageInfo=()=>new Promise(r=>finish=r);
    e.p.aboutToAppear();await tick();e.requests[0](a.lease);await tick();e.p.aboutToDisappear();
    finish({size:{width:10,height:20}});await tick();assert.equal(a.count(),1);assert.equal(a.mapCount(),0);assert.equal(e.cancels.length,0);
  });
  await test('layout ratio update and zoom reset never reload or retire the current lease',async()=>{
    const e=environment(),a=pixel();e.p.naturalHeight=true;const ready=[];e.p.onReadyChanged=v=>ready.push(v);
    e.p.aboutToAppear();await tick();e.requests[0](a.lease);await tick();assert.equal(e.p.decodedRatio,.5);
    for(let i=0;i<20;i++){e.p.zoomReset++;e.p.resetZoom();e.p.reloadImage();e.p.aboutToReuse({url:'u'})}await tick();
    assert.equal(e.requests.length,1);assert.equal(e.cancels.length,0);assert.equal(a.count(),0);assert.equal(ready.at(-1),true);
  });
  await test('decoded readiness publishes only after current commit and clears on changed identity or exit',async()=>{
    const e=environment(),a=pixel();const ready=[];e.p.onReadyChanged=v=>ready.push(v);
    e.p.aboutToAppear();assert.equal(ready.at(-1),false);await tick();e.requests[0](a.lease);await tick();assert.equal(ready.at(-1),true);
    e.p.resetZoom();assert.equal(ready.at(-1),true);change(e);await tick();assert.equal(ready.at(-1),false);e.p.aboutToDisappear();assert.equal(ready.at(-1),false);
  });
  await test('cached readiness waits for newest callback props and obsolete queued generation is ignored',async()=>{
    const {e}=await loaded();const seen=[];
    e.p.onReadyChanged=()=>seen.push('old');e.p.zoomReset=2;e.p.resetZoom();e.p.onReadyChanged=ready=>seen.push(ready?'new-ready':'new-pending');
    await tick();assert.deepEqual(seen,['new-ready']);seen.length=0;e.p.resetZoom();change(e);await tick();assert.equal(seen.at(-1),'new-pending');
    e.p.aboutToDisappear();
  });
  await test('failed native-size query retires the uncommitted lease and stops loading',async()=>{
    const e=environment(),a=pixel();e.p.naturalHeight=true;a.map.getImageInfo=async()=>{throw Error('fixture failure')};
    e.p.aboutToAppear();await tick();e.requests[0](a.lease);await tick();assert.equal(a.count(),1);assert.equal(e.p.failed,true);assert.equal(e.p.pixelMap,undefined);
    e.p.aboutToReuse({url:'u'});e.p.reloadImage();await tick();assert.equal(e.requests.length,1,'failure must not enter a refetch loop');assert.equal(e.cancels.length,0);
  });
  await test('request rejection is terminal and does not cancel an already failed trace',async()=>{
    const e=environment();e.p.aboutToAppear();await tick();e.rejections[0](Error('HTTP fixture rejection'));await tick();
    assert.equal(e.p.failed,true);assert.equal(e.p.pixelMap,undefined);e.p.aboutToDisappear();assert.equal(e.cancels.length,0);
  });
  await test('readiness callback exception never invalidates committed decoded ownership',async()=>{
    const e=environment(),a=pixel();e.p.onReadyChanged=()=>{throw Error('UI callback fixture')};e.p.aboutToAppear();await tick();e.requests[0](a.lease);await tick();
    assert.equal(e.p.failed,false);assert.strictEqual(e.p.pixelMap,a.map);assert.equal(a.count(),0);e.p.aboutToDisappear();await tick();assert.equal(a.count(),1);
  });
  await test('stale completion cannot erase cancellation ownership of newer pending trace',async()=>{
    const e=environment(),a=pixel();e.p.aboutToAppear();await tick();change(e);await tick();e.requests[0](a.lease);await tick();e.p.aboutToDisappear();
    assert.equal(e.cancels.length,2);assert.notEqual(e.cancels[0],e.cancels[1]);assert.equal(a.count(),1);
  });
  await test('queued reload after disappear never restarts loading',async()=>{
    const e=environment();e.p.aboutToAppear();await tick();change(e);e.p.aboutToDisappear();await tick();assert.equal(e.requests.length,1);
  });
  console.log(`PASS ${count} production image component lease/race cases; ArkUI/SDK device checks pending.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
