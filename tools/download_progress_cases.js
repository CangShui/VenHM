'use strict';
// Progress bar data, multi-task concurrency and per-task parallel page fetching.
// Production DownloadQueue runs in a vm against controlled SDK/filesystem fakes only:
// no device, no hdc, no account, no real site, no user filesystem.
const assert=require('node:assert/strict');
const {downloads,tick,deferred}=require('./download_test_harness');
const bytes=()=>({ok:true,bytes:new ArrayBuffer(128)});
const folderOf=task=>`/app/files/local_comics/${task.id}`;
const pagePath=(task,chapter,page,ext='png')=>`${folderOf(task)}/${String(chapter).padStart(4,'0')}/${String(page).padStart(6,'0')}.${ext}`;
const shortName=comicId=>comicId.replace('comic','');

let count=0;
let finished=false;
// The timer keeps the event loop alive, so a never-resolving fake cannot exit 0 silently.
async function test(name,run){
  let timer;
  try{
    await Promise.race([run(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),3000)})]);
  }finally{clearTimeout(timer)}
  count++;console.log('PASS '+name);
}
process.on('beforeExit',()=>{if(!finished){console.error('FAIL missing final download-progress PASS marker');process.exitCode=1}});

/** Deterministic source: every comic has the same chapter shape, URLs identify task/chapter/page. */
function installSource(e,chapters,pages){
  const ids=[],titles=[];
  for(let i=1;i<=chapters;i++){ids.push('c'+i);titles.push('C'+i);}
  e.ctx.SourceManager={find:key=>key!=='fixture'?undefined:{
    loadComicInfo:async id=>({error:false,dataOrNull:{title:'T-'+id,chapters:{length:chapters,ids:ids.slice(),titles:titles.slice()}}}),
    loadComicPages:async (id,ep)=>{
      const urls=[];
      for(let page=1;page<=pages;page++)urls.push(`${id}/${ep}/${page}`);
      return {error:false,dataOrNull:urls};
    }
  }};
  return e;
}
const urlsFor=(comicId,chapters,pages)=>{
  const out=[];
  for(let ch=1;ch<=chapters;ch++)for(let page=1;page<=pages;page++)out.push(`${comicId}/c${ch}/${page}`);
  return out;
};

/** Releasable gates keyed by an arbitrary label (task name or full page URL). */
function gateBoard(){
  const slots=new Map();
  const slot=label=>{if(!slots.has(label))slots.set(label,{d:deferred(),open:false});return slots.get(label);};
  const board={
    wait(label){const s=slot(label);return s.open?Promise.resolve():s.d.promise;},
    release(label){const s=slot(label);if(!s.open){s.open=true;s.d.resolve();}},
    releaseAll(){for(const label of [...slots.keys()])board.release(label);},
    isOpen(label){return slots.has(label)&&slots.get(label).open;}
  };
  return board;
}

/** Records every persisted ledger checkpoint so contiguity can be checked on disk state, not just memory. */
function recordCheckpoints(e,into){
  const writeSync=e.ctx.fs.writeSync;
  e.ctx.fs.writeSync=(path,body)=>{
    const written=writeSync(path,body);
    if(typeof body==='string'&&path.endsWith('downloads.json.tmp')){
      const ledger=JSON.parse(body);
      if(Array.isArray(ledger)&&ledger.length>0){
        into.push({chapter:ledger[0].chapter,page:ledger[0].page,saved:ledger[0].savedPages});
      }
    }
    return written;
  };
}

async function waitFor(predicate,label){
  for(let i=0;i<400;i++){if(predicate())return;await tick();}
  throw Error('TIMEOUT '+label);
}

(async()=>{
  await test('three tasks download concurrently under the cap and a fourth waits for a slot',async()=>{
    const e=installSource(downloads(),2,3);
    const tasks=[];
    for(const name of ['A','B','C','D'])tasks.push(await e.Queue.add('fixture','comic'+name));
    assert.equal(tasks.length,4);
    assert.equal(e.Queue.MAX_CONCURRENT_TASKS,3,'the task cap is a named constant');
    assert.equal(e.Queue.PAGE_WORKERS,3,'the page pool is a named constant');

    const gates=gateBoard(),events=[],inFlight=new Set();
    let maxTasks=0;
    e.ctx.HttpClient.getBytes=async url=>{
      const name=shortName(url.split('/')[0]);
      inFlight.add(name);maxTasks=Math.max(maxTasks,inFlight.size);events.push(['req',name]);
      await gates.wait(name);
      inFlight.delete(name);
      return bytes();
    };
    const runs=tasks.map(task=>e.Queue.resume(task.id).then(()=>{events.push(['done',shortName(task.comicId)]);}));

    await waitFor(()=>tasks[3].queued===true&&maxTasks===3,'three admitted tasks');
    assert.equal(maxTasks,3,'never more than MAX_CONCURRENT_TASKS tasks download at once');
    assert.equal(tasks[3].queued,true,'the fourth task waits instead of failing');
    assert.equal(tasks[3].status,'paused','a queued task is not reported as running');
    assert.equal(events.some(entry=>entry[0]==='req'&&entry[1]==='D'),false,'a queued task issues no page request');

    gates.release('A');
    await waitFor(()=>events.some(entry=>entry[0]==='req'&&entry[1]==='D'),'fourth task admitted after a free slot');
    const doneA=events.findIndex(entry=>entry[0]==='done'&&entry[1]==='A');
    const firstD=events.findIndex(entry=>entry[0]==='req'&&entry[1]==='D');
    assert.ok(doneA>=0&&doneA<firstD,'the fourth task starts only after one of the three finished');
    assert.equal(maxTasks,3,'still capped while the queued task joins');

    gates.releaseAll();
    await Promise.all(runs);
    for(const task of tasks){
      assert.equal(task.status,'completed');
      assert.equal(task.savedPages,6);
      assert.equal(task.chapter,2);
      assert.equal(task.queued,false);
    }
  });

  await test('a paused queued task never starts and never releases the running task lease',async()=>{
    const e=installSource(downloads(),1,2);
    const tasks=[];
    for(const name of ['A','B','C','D'])tasks.push(await e.Queue.add('fixture','comic'+name));
    const gates=gateBoard();
    let issuedD=0;
    e.ctx.HttpClient.getBytes=async url=>{
      if(url.startsWith('comicD/'))issuedD++;
      await gates.wait(shortName(url.split('/')[0]));
      return bytes();
    };
    const runs=tasks.map(task=>e.Queue.resume(task.id).catch(()=>{}));
    const leaseOwner=()=>tasks.slice(0,3).find(task=>e.Coordinator.held(task.id));
    await waitFor(()=>tasks[3].queued===true&&leaseOwner()!==undefined,'fourth task queued with a lease owner');
    const owner=leaseOwner();
    assert.ok(owner!==undefined,'exactly one running task holds the single lease');
    assert.equal(tasks.slice(0,3).filter(task=>e.Coordinator.held(task.id)).length,1,'only one lease at a time');

    e.Queue.pause(tasks[3].id);
    assert.equal(tasks[3].queued,false,'a paused waiter leaves the queue immediately');
    assert.equal(tasks[3].status,'paused');
    assert.equal(e.Coordinator.held(owner.id),true,'pausing a waiter must not release another task lease');

    gates.releaseAll();
    await Promise.all(runs);
    assert.equal(issuedD,0,'a paused queued task never issues a request');
    assert.equal(tasks[3].savedPages,0);
    assert.equal(tasks[3].status,'paused');
    for(const task of tasks.slice(0,3))assert.equal(task.status,'completed');
  });

  await test('one task fetches several pages of a chapter at the same time',async()=>{
    const e=installSource(downloads(),1,4),task=await e.Queue.add('fixture','comicP');
    const gate=deferred();
    let simultaneous=0,maxSimultaneous=0,issued=0;
    e.ctx.HttpClient.getBytes=async ()=>{
      issued++;simultaneous++;maxSimultaneous=Math.max(maxSimultaneous,simultaneous);
      await gate.promise;
      simultaneous--;
      return bytes();
    };
    const run=e.Queue.resume(task.id);
    await waitFor(()=>simultaneous>=2,'parallel page requests');
    assert.ok(maxSimultaneous>1,`expected more than one simultaneous page request, saw ${maxSimultaneous}`);
    assert.equal(maxSimultaneous,e.Queue.PAGE_WORKERS,'the pool is bounded by PAGE_WORKERS');
    gate.resolve();
    await run;
    assert.equal(issued,4);
    assert.equal(task.status,'completed');
    assert.equal(task.savedPages,4);
  });

  await test('checkpoint never skips a page when pages complete out of order',async()=>{
    const e=installSource(downloads(),1,3),task=await e.Queue.add('fixture','comicO');
    const checkpoints=[];
    recordCheckpoints(e,checkpoints);
    const gates=gateBoard();
    let issued=0;
    e.ctx.HttpClient.getBytes=async url=>{issued++;await gates.wait(url);return bytes();};
    const run=e.Queue.resume(task.id);
    await waitFor(()=>issued===3,'whole page batch in flight');
    assert.equal(task.page,0);
    assert.equal(task.savedPages,0);
    const writtenBefore=checkpoints.length;

    const [first,second,third]=urlsFor('comicO',1,3);
    // Pages 3 and 2 finish first: their files may land, the checkpoint must not move.
    gates.release(third);gates.release(second);
    await waitFor(()=>e.files.has(pagePath(task,1,3))&&e.files.has(pagePath(task,1,2)),'late pages written');
    assert.equal(e.files.has(pagePath(task,1,1)),false,'the first page is still missing');
    assert.equal(task.page,0,'out-of-order completion must not advance the checkpoint');
    assert.equal(task.savedPages,0,'savedPages stays a contiguous prefix');
    assert.ok(checkpoints.slice(writtenBefore).every(entry=>entry.page===0&&entry.saved===0),
      'no persisted checkpoint advanced past the missing first page');

    gates.release(first);
    await run;
    assert.equal(task.status,'completed');
    assert.equal(task.savedPages,3);
    assert.equal(task.chapter,1,'chapter rolled over after the last page');
    assert.equal(task.page,0);
    assert.deepEqual([1,2,3].map(page=>e.files.has(pagePath(task,1,page))),[true,true,true]);
    // Persisted checkpoints advance one page at a time, never by a jump.
    for(let index=1;index<checkpoints.length;index++){
      const previous=checkpoints[index-1],current=checkpoints[index];
      assert.ok(current.saved<=previous.saved+1,`savedPages jumped ${previous.saved} -> ${current.saved}`);
      if(current.chapter===previous.chapter){assert.ok(current.page<=previous.page+1,`page jumped ${previous.page} -> ${current.page}`);}
      else{assert.equal(current.chapter,previous.chapter+1,'chapters advance one at a time');}
    }
    assert.deepEqual(checkpoints.map(entry=>`${entry.chapter}/${entry.page}`).filter((value,index,all)=>all.indexOf(value)===index),
      ['0/0','0/1','0/2','0/3','1/0']);

    // A failed earlier page must never let the later pages of the same batch be checkpointed.
    const failed=installSource(downloads(),1,3),failedTask=await failed.Queue.add('fixture','comicF');
    const failedCheckpoints=[];
    recordCheckpoints(failed,failedCheckpoints);
    failed.ctx.HttpClient.getBytes=async url=>{
      if(url==='comicF/c1/1')throw Error('image HTTP failed');
      return bytes();
    };
    await assert.rejects(failed.Queue.resume(failedTask.id),/image HTTP failed/);
    assert.equal(failedTask.status,'failed');
    assert.equal(failedTask.page,0,'a failed earlier page must not advance the checkpoint');
    assert.equal(failedTask.savedPages,0,'savedPages must stay the verified prefix');
    assert.equal(failed.files.has(pagePath(failedTask,1,2)),true,'the later page was fetched');
    assert.equal(failed.files.has(pagePath(failedTask,1,3)),true,'the later page was fetched');
    assert.equal(failed.files.has(pagePath(failedTask,1,1)),false);
    assert.ok(failedCheckpoints.every(entry=>entry.page===0&&entry.saved===0),
      'no persisted checkpoint skipped the failed page');
  });

  await test('pause during a parallel batch stops advancing and discards late results',async()=>{
    const e=installSource(downloads(),1,3),task=await e.Queue.add('fixture','comicX');
    const gates=gateBoard();
    let issued=0;
    e.ctx.HttpClient.getBytes=async url=>{issued++;await gates.wait(url);return bytes();};
    const run=e.Queue.resume(task.id);
    await waitFor(()=>issued===3,'whole batch in flight');
    assert.equal(task.status,'running');

    e.Queue.pause(task.id);
    assert.equal(task.status,'paused');
    assert.equal(task.page,0);
    assert.equal(task.savedPages,0);
    gates.releaseAll();
    await run;
    assert.equal(task.status,'paused');
    assert.equal(task.page,0,'a paused batch never advances the checkpoint');
    assert.equal(task.savedPages,0);
    assert.equal([...e.files.keys()].some(path=>path.endsWith('.png')),false,'late page bytes are discarded');
    assert.equal([...e.files.keys()].some(path=>path.endsWith('.part')),false,'no partial file survives');
    assert.equal(issued,3,'no new request after the pause');

    // Same rule one step later: a response that was already decoded must not be written either.
    const late=installSource(downloads(),1,3),lateTask=await late.Queue.add('fixture','comicL');
    const decode=deferred();
    let decoding=0;
    late.ctx.image.createImageSource=()=>({
      getImageInfo:async ()=>{decoding++;await decode.promise;return {size:{width:10,height:20},mimeType:'image/png'}},
      createPixelMap:async()=>({release:async()=>{}}),
      release:async()=>{}
    });
    const lateRun=late.Queue.resume(lateTask.id);
    await waitFor(()=>decoding===3,'whole batch decoding');
    late.Queue.pause(lateTask.id);
    assert.equal(lateTask.page,0);
    decode.resolve();
    await lateRun;
    assert.equal(lateTask.status,'paused');
    assert.equal(lateTask.page,0,'a paused batch never advances the checkpoint');
    assert.equal(lateTask.savedPages,0);
    assert.equal([...late.files.keys()].some(path=>path.endsWith('.png')),false,'a late decoded page is not written');
    assert.equal([...late.files.keys()].some(path=>path.endsWith('.part')),false,'no partial file survives');
  });

  await test('restart awaits the old runner, then resets to chapter/page 0 and redownloads',async()=>{
    const e=installSource(downloads(),2,2),task=await e.Queue.add('fixture','comicR');
    const gate=deferred();
    let gated=false,issued=0;
    e.ctx.HttpClient.getBytes=async ()=>{
      issued++;
      if(!gated){gated=true;await gate.promise;}
      return bytes();
    };
    const run=e.Queue.resume(task.id);
    await waitFor(()=>gated===true,'first page in flight');
    let restarted=false;
    const restart=e.Queue.restart(task.id).then(()=>{restarted=true;});
    await tick();await tick();await tick();
    assert.equal(restarted,false,'restart must await the exact old runner');
    assert.equal(task.page,0,'checkpoint already reset to chapter/page 0');
    assert.equal(task.savedPages,0);

    gate.resolve();
    await run;
    await restart;
    assert.equal(restarted,true);
    assert.equal(task.status,'completed');
    assert.equal(task.savedPages,4);
    assert.equal(task.chapter,2);
    assert.equal(task.page,0);
    assert.equal(issued,6,'the aborted batch plus the complete restart, nothing else');
    assert.equal([...e.files.keys()].filter(path=>path.endsWith('.png')).length,4);
  });

  await test('delete waits for the running task and removes only its own DL folder',async()=>{
    const e=installSource(downloads(),2,2);
    const keep=await e.Queue.add('fixture','comicKeep'),drop=await e.Queue.add('fixture','comicDrop');
    const imported='/app/files/local_comics/imported/page.png',history='/app/files/history.rdb';
    e.files.set(imported,'user');e.files.set(history,'history');
    await e.Queue.resume(keep.id);
    assert.equal(keep.status,'completed');

    const gate=deferred();
    e.ctx.HttpClient.getBytes=async ()=>{await gate.promise;return bytes();};
    const run=e.Queue.resume(drop.id);
    await waitFor(()=>e.Coordinator.held(drop.id)===true,'second task running with the lease');
    let deleted=false;
    const deletion=e.Queue.deleteTask(drop.id).then(()=>{deleted=true;});
    await tick();await tick();
    assert.equal(deleted,false,'delete awaits the old runner');
    assert.deepEqual(e.deleted,[],'nothing is unlinked before the runner exits');

    gate.resolve();
    await run;
    await deletion;
    assert.equal(deleted,true);
    assert.deepEqual(e.deleted,[folderOf(drop)],'only the owned DL folder is removed');
    assert.equal(e.Queue.tasks.length,1);
    assert.equal(e.Queue.tasks[0].id,keep.id);
    assert.equal([...e.files.keys()].filter(path=>path.startsWith(folderOf(keep)+'/')).length,5,'kept task keeps marker plus 4 pages');
    assert.equal(e.files.get(imported),'user');
    assert.equal(e.files.get(history),'history');
    assert.equal([...e.files.keys()].some(path=>path.startsWith(folderOf(drop)+'/')),false);
  });

  await test('progress percentage is monotonic, chapter based while totals are unknown, and never exceeds 100',async()=>{
    const e=installSource(downloads(),2,4),task=await e.Queue.add('fixture','comicG');
    const gates=gateBoard();
    e.ctx.HttpClient.getBytes=async url=>{await gates.wait(url);return bytes();};
    const samples=[];
    const sample=()=>{
      const progress=e.Queue.progress(task);
      assert.ok(progress.percent>=0&&progress.percent<=100,`percent in range: ${progress.percent}`);
      samples.push({percent:progress.percent,indeterminate:progress.indeterminate,totalPages:progress.totalPages,
        knownChapters:progress.knownChapters,totalChapters:progress.totalChapters,savedPages:progress.savedPages});
    };
    const run=e.Queue.resume(task.id);
    await tick();await tick();
    sample();
    assert.equal(samples[0].percent,0);
    assert.equal(samples[0].indeterminate,true,'page totals are unknown before every chapter is fetched');
    assert.equal(samples[0].totalPages,0,'no invented total page count');
    assert.equal(samples[0].totalChapters,2);

    for(const url of urlsFor('comicG',2,4)){gates.release(url);await tick();sample();}
    await run;

    for(let index=1;index<samples.length;index++){
      assert.ok(samples[index].percent>=samples[index-1].percent,
        `percent must not decrease: ${samples[index-1].percent} -> ${samples[index].percent}`);
    }
    assert.ok(samples.some(entry=>entry.percent>0&&entry.percent<100),'intermediate percentages are visible');
    const final=e.Queue.progress(task);
    assert.equal(final.percent,100);
    assert.equal(final.savedPages,8);
    assert.equal(final.totalPages,8,'the total is reported once every chapter page count is known');
    assert.equal(final.knownChapters,2);
    assert.equal(final.indeterminate,false);
    assert.equal(task.status,'completed');
  });

  assert.equal(count,8,'all registered progress/concurrency cases must finish');
  finished=true;
  console.log(`PASS ${count} download progress/concurrency cases (cap 3 tasks, 3 pages per task); no device, no real site, no hdc.`);
})().catch(error=>{console.error(error);process.exitCode=1});
