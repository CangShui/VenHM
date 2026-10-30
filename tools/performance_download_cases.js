'use strict';
// Production queue + image parser/pipeline + reader activity signal, controlled SDK/filesystem only.
// Counts requested decoder output targets and ledger writes; these are NOT device frame/memory timings.
const assert=require('node:assert/strict');
const {downloads,tick,deferred}=require('./download_test_harness');
let count=0,finished=false;
async function test(name,run){
  let timer;
  try{await Promise.race([run(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),5000)})]);}
  finally{clearTimeout(timer);}
  count++;console.log('PASS '+name);
}
process.on('beforeExit',()=>{if(!finished){console.error('FAIL missing final performance-download PASS marker');process.exitCode=1;}});
async function waitFor(predicate,label){for(let i=0;i<400;i++){if(predicate())return;await tick();}throw Error('TIMEOUT '+label);}
const bytes=()=>({ok:true,status:200,bytes:new ArrayBuffer(128)});
const pagePath=(task,n)=>`/app/files/local_comics/${task.id}/0001/${String(n).padStart(6,'0')}.png`;
const ledgerWrites=e=>e.writes.filter(p=>p.endsWith('/downloads.json.tmp')).length;
function fixture(pages){
  const e=downloads();
  e.ctx.SourceManager={find:key=>key==='fixture'?{
    loadComicInfo:async id=>({error:false,dataOrNull:{title:id,chapters:{length:1,ids:['c1'],titles:['C1']}}}),
    loadComicPages:async id=>({error:false,dataOrNull:Array.from({length:pages},(_,i)=>`${id}/${i+1}`)})
  }:undefined};
  return e;
}
function assertBounded(calls){
  for(const call of calls){assert.equal(call.options?.desiredSize.width,64);assert.equal(call.options?.desiredSize.height,64);}
}
(async()=>{
  await test('one real bounded decode per downloaded page, bounded disk reconciliation, and one checkpoint per batch',async()=>{
    const e=fixture(12),task=await e.Queue.add('fixture','counts');
    const before=ledgerWrites(e);await e.Queue.resume(task.id);
    assert.equal(task.status,'completed');assert.equal(task.savedPages,12);
    assert.equal(e.decodeCalls.length,12,'verified production fetch must not be fully decoded again by queue');
    assertBounded(e.decodeCalls);
    const firstRunWrites=ledgerWrites(e)-before;
    assert.equal(firstRunWrites,10,'six lifecycle/chapter writes plus four verified-prefix batch writes');
    const requests=e.calls.length;
    await e.Queue.resume(task.id);
    assert.equal(e.calls.length,requests,'completed reconciliation never requests network');
    assert.equal(e.decodeCalls.length,24,'each checkpointed disk page still gets a real decode');
    assertBounded(e.decodeCalls.slice(12));
    console.log(`MEASURE 12 pages: download decodes=12 (one/page), validation target=64x64, checkpoint batch writes=4, total resume ledger writes=${firstRunWrites}; disk recheck decodes=12, extra HTTP=0`);
  });
  await test('header-readable but undecodable bytes cannot be atomically stored or checkpointed',async()=>{
    const e=fixture(3),task=await e.Queue.add('fixture','corrupt');let decoded=0,headers=0;
    e.ctx.image.createImageSource=()=>({getImageInfo:async()=>{headers++;return {size:{width:3000,height:5000},mimeType:'image/png'}},
      createPixelMap:async options=>{decoded++;assert.equal(options.desiredSize.width,64);throw Error('corrupt scan data');},release:async()=>{}});
    await assert.rejects(e.Queue.resume(task.id),/corrupt scan data/);
    assert.equal(decoded,3);assert.equal(headers,0,'reject inside real pipeline, not a metadata-only queue fallback');
    assert.equal(task.savedPages,0);assert.equal(task.status,'failed');
    assert.equal([...e.files.keys()].some(p=>p.endsWith('.png')||p.endsWith('.part')),false);
  });
  await test('successful leading pages checkpoint once even when a later decode fails; retry rechecks prefix',async()=>{
    const e=fixture(3),task=await e.Queue.add('fixture','partial');
    e.ctx.HttpClient.getBytes=async url=>{const b=new Uint8Array(128);b[0]=Number(url.split('/')[1]);return {ok:true,bytes:b.buffer};};
    const source=e.ctx.image.createImageSource;
    e.ctx.image.createImageSource=input=>{
      if(input instanceof ArrayBuffer&&new Uint8Array(input)[0]===2)return {createPixelMap:async()=>{throw Error('second page decode failed')},release:async()=>{}};
      return source(input);
    };
    await assert.rejects(e.Queue.resume(task.id),/second page decode failed/);
    assert.equal(task.page,1);assert.equal(task.savedPages,1);assert.equal(task.status,'failed');
    const diskTask=JSON.parse(e.files.get('/app/files/downloads.json'))[0];
    assert.equal(diskTask.page,1);assert.equal(diskTask.savedPages,1);
    assert.equal(e.files.has(pagePath(task,1)),true);assert.equal(e.files.has(pagePath(task,2)),false);
    assert.equal(e.files.has(pagePath(task,3)),true,'later valid but uncheckpointed page remains safe');
    e.ctx.image.createImageSource=source;
    await e.Queue.resume(task.id);assert.equal(task.status,'completed');assert.equal(task.savedPages,3);
    for(let p=1;p<=3;p++)assert.equal(e.files.has(pagePath(task,p)),true);
  });
  await test('owner-based visibility is idempotent and one reader cannot clear another reader',async()=>{
    const e=fixture(1),signal=e.Workload;
    assert.equal(signal.isReaderVisible(),false);
    signal.setReaderVisible(true,'A');signal.setReaderVisible(true,'A');signal.setReaderVisible(true,'B');
    signal.setReaderVisible(false,'A');signal.setReaderVisible(false,'A');assert.equal(signal.isReaderVisible(),true);
    signal.setReaderVisible(false,'missing');assert.equal(signal.isReaderVisible(),true);
    signal.setReaderVisible(false,'B');assert.equal(signal.isReaderVisible(),false);
    signal.setReaderVisible(true);signal.setReaderVisible(false);assert.equal(signal.isReaderVisible(),false);
    assert.equal(e.writes.length,0,'activity signal has no persistence or logging IO');
  });
  await test('reader activity lowers page workers from nine to three across three tasks without lowering task cap',async()=>{
    const maxima=[];
    for(const active of [false,true]){
      const e=fixture(6),tasks=[];for(const id of ['A','B','C'])tasks.push(await e.Queue.add('fixture',id));
      e.Workload.setReaderVisible(active,'reader');
      const gate=deferred();let inflight=0,max=0;
      const taskIds=new Set();
      e.ctx.HttpClient.getBytes=async url=>{taskIds.add(url.split('/')[0]);inflight++;max=Math.max(max,inflight);await gate.promise;inflight--;return bytes();};
      const runs=tasks.map(task=>e.Queue.resume(task.id));
      const expected=active?3:9;
      await waitFor(()=>inflight===expected,'initial worker pool '+expected);
      assert.equal(taskIds.size,3,'all three task slots stay admitted');assert.equal(e.Queue.MAX_CONCURRENT_TASKS,3);
      gate.resolve();await Promise.all(runs);assert.equal(max,expected);
      for(const task of tasks){assert.equal(task.status,'completed');assert.equal(task.savedPages,6);}
      maxima.push(max);
    }
    console.log(`MEASURE same 3 admitted tasks: max simultaneous page requests outside reader=${maxima[0]}, reader visible=${maxima[1]}`);
  });
  await test('visibility changes take effect at next batch, restoring original parallelism after leave',async()=>{
    const e=fixture(9),task=await e.Queue.add('fixture','transition');
    const gates=[deferred(),deferred(),deferred()];let issued=0;
    e.ctx.HttpClient.getBytes=async()=>{issued++;const gate=issued<=3?gates[0]:issued===4?gates[1]:gates[2];await gate.promise;return bytes();};
    const run=e.Queue.resume(task.id);
    await waitFor(()=>issued===3,'original three workers');e.Workload.setReaderVisible(true,'reader');gates[0].resolve();
    await waitFor(()=>issued===4,'one worker after reader entry');await tick();assert.equal(issued,4);
    e.Workload.setReaderVisible(false,'reader');gates[1].resolve();
    await waitFor(()=>issued===7,'three workers after reader leave');assert.equal(task.page,4);
    gates[2].resolve();await run;assert.equal(task.savedPages,9);assert.equal(task.status,'completed');
  });
  await test('pause during bounded pipeline decode discards bytes without onLoadFailed or partial writes',async()=>{
    const e=fixture(3),task=await e.Queue.add('fixture','cancel');let recovering=0,decoding=0;
    const resolve=e.ctx.ImageRequests.resolve;
    e.ctx.ImageRequests.resolve=async(...args)=>{const config=await resolve(...args);config.onLoadFailed=()=>{recovering++;return config;};return config;};
    const gate=deferred(),source=e.ctx.image.createImageSource;
    e.ctx.image.createImageSource=input=>{const decoder=source(input),decode=decoder.createPixelMap;
      decoder.createPixelMap=async options=>{decoding++;await gate.promise;return decode(options);};return decoder;};
    const run=e.Queue.resume(task.id);await waitFor(()=>decoding===3,'bounded decodes in flight');e.Queue.pause(task.id);gate.resolve();await run;
    assert.equal(recovering,0);assert.equal(task.status,'paused');assert.equal(task.page,0);assert.equal(task.savedPages,0);
    assert.equal([...e.files.keys()].some(p=>p.endsWith('.png')||p.endsWith('.part')),false);
  });
  await test('atomic rename precedes prefix persistence; interrupted ledger leaves safe uncheckpointed pages',async()=>{
    const e=fixture(3),task=await e.Queue.add('fixture','crash');const write=e.ctx.fs.writeSync;let interrupted=false;
    e.ctx.fs.writeSync=(path,body)=>{
      if(path.endsWith('/downloads.json.tmp')&&(interrupted||JSON.parse(body)[0].page===3)){interrupted=true;throw Error('simulated process interruption');}
      return write(path,body);
    };
    await assert.rejects(e.Queue.resume(task.id),/simulated process interruption/);
    assert.equal(interrupted,true);const diskTask=JSON.parse(e.files.get('/app/files/downloads.json'))[0];
    assert.equal(diskTask.page,0);assert.equal(diskTask.savedPages,0);
    for(let p=1;p<=3;p++)assert.equal(e.files.has(pagePath(task,p)),true,'atomic final file may safely precede ledger');
    assert.equal([...e.files.keys()].some(p=>p.endsWith('.part')),false);
    const restarted=fixture(3);for(const dir of e.dirs)restarted.dirs.add(dir);for(const [path,body]of e.files)restarted.files.set(path,body);
    restarted.Queue.init();const restored=restarted.Queue.tasks[0];assert.equal(restored.status,'paused');
    await restarted.Queue.resume(restored.id);assert.equal(restored.status,'completed');assert.equal(restored.savedPages,3);
    assert.equal(restarted.calls.length,3,'uncheckpointed tail safely redownloaded, not blindly trusted');
  });
  finished=true;console.log(`PASS ${count} production download performance/safety cases; controlled SDK targets/IO counts only, not device FPS or codec peak-memory measurements.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
