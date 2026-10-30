'use strict';
const assert=require('node:assert/strict');
const {downloads,tick,deferred}=require('./download_test_harness');
let count=0;
let finished=false;
// A referenced timer prevents Node's false exit-0 when an awaited fake never settles.
async function test(name,run){
  let timer;
  try{await Promise.race([run(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),3000)})]);}
  finally{clearTimeout(timer)}
  count++;console.log('PASS '+name);
}
process.on('beforeExit',()=>{if(!finished){console.error('FAIL missing final background/queue PASS marker');process.exitCode=1}});
const bytes=()=>({ok:true,bytes:new ArrayBuffer(128)});
const folder=t=>`/app/files/local_comics/${t.id}`;
(async()=>{
  await test('add/init/foreground do not start service, WantAgent, or image HTTP',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');
    await e.Queue.setForeground(false);await e.Queue.setForeground(true);e.Queue.init();
    assert.equal(task.status,'paused');assert.equal(e.service.starts.length,0);assert.equal(e.service.agents.length,0);assert.equal(e.calls.length,0);
  });
  await test('explicit resume uses only API21 DATA_TRANSFER and notification WantAgent; completion stops exact native task',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    assert.deepEqual(Array.from(e.service.starts[0].backgroundTaskModes),[1]);
    assert.deepEqual(Array.from(e.service.starts[0].backgroundTaskSubmodes),[3]);
    assert.equal(e.service.agents[0].wants[0].abilityName,'EntryAbility');assert.equal(e.service.agents[0].wants[0].parameters.openDownloads,true);
    assert.equal(task.status,'completed');assert.deepEqual(e.service.stops,[1]);assert.equal(e.events.size,0);assert.equal(e.Coordinator.held(task.id),false);
  });
  await test('accepted transfer completes all pages while ability remains backgrounded',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);if(e.calls.length===1)await gate.promise;return bytes()};
    const run=e.Queue.resume(task.id);await tick();await e.Queue.setForeground(false);gate.resolve();await run;
    assert.equal(task.status,'completed');assert.equal(task.savedPages,4);assert.deepEqual(e.service.stops,[1]);
  });
  await test('permission refusal keeps the foreground download running without claiming a lease',async()=>{
    // Background execution is an enhancement: a denied/unsupported lease must not
    // block a download the user explicitly started while the app is in front.
    const e=downloads(),task=await e.Queue.add('fixture','comic');e.service.failStart=Object.assign(Error('Permission denied'),{code:201});
    await e.Queue.resume(task.id);
    assert.equal(e.Coordinator.held(task.id),false);assert.equal(e.events.size,0);
    assert.match(e.Queue.backgroundStatus(task.id),/201.*Permission denied/);
    assert.match(task.error,/201/);assert.equal(task.status,'completed');assert.equal(e.service.starts.length,1);assert.equal(e.service.stops.length,0);
    // Backgrounding then pauses it with a concrete reason and no silent resume.
    const paused=downloads();const t2=await paused.Queue.add('fixture','comic');
    paused.service.failStart=Object.assign(Error('Permission denied'),{code:201});
    const gate=deferred();paused.ctx.HttpClient.getBytes=async()=>{await gate.promise;return bytes()};
    const running=paused.Queue.resume(t2.id);await tick();
    assert.equal(paused.events.size,0);assert.match(t2.error,/201/);
    await paused.Queue.setForeground(false);assert.equal(t2.status,'paused');assert.match(t2.error,/201/);
    gate.resolve();await running;assert.equal(t2.savedPages,0);
    await paused.Queue.setForeground(true);assert.equal(t2.status,'paused');assert.equal(paused.service.starts.length,1);
  });
  await test('unsupported transfer mode allows foreground only and preserves visible refusal',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');e.service.supported=false;
    await e.Queue.resume(task.id);assert.equal(task.status,'completed');assert.match(task.error,/不支持 DATA_TRANSFER/);
    assert.match(e.Queue.backgroundStatus(task.id),/不支持 DATA_TRANSFER/);assert.equal(e.service.starts.length,0);
    assert.equal(e.calls.length,4);assert.equal(e.service.stops.length,0);assert.equal(e.events.size,0);
  });
  for(const phase of ['is-mode-supported','native-start']){
    await test('persistent 9800005 from '+phase+' never blind-stops or loops and allows explicit foreground retries',async()=>{
      const audit=[],e=downloads((...entry)=>audit.push(entry)),task=await e.Queue.add('fixture','comic');
      const failure=Object.assign(Error('sensitive request token=secret\\nraw stack'),{code:9800005});
      e.service[phase==='is-mode-supported'?'failMode':'failStart']=failure;
      e.service.liveNative.add(999); // A different native owner must survive our refusal.
      await e.Queue.resume(task.id);await e.Queue.restart(task.id);await e.Queue.restart(task.id);
      assert.equal(task.status,'completed');assert.equal(task.savedPages,4);assert.match(task.error,/9800005/);
      assert.match(e.Queue.backgroundStatus(task.id),/9800005/);assert.equal(e.Coordinator.held(task.id),false);
      assert.equal(e.service.modeChecks.length,3);assert.equal(e.service.starts.length,phase==='native-start'?3:0);
      assert.deepEqual(e.service.stops,[]);assert.equal(e.service.liveNative.has(999),true);assert.equal(e.events.size,0);
      const failures=audit.filter(entry=>entry[1]==='后台申请失败');assert.equal(failures.length,3);
      assert.ok(failures.every(entry=>entry[2]===`phase=${phase}；code=9800005`));
      assert.equal(JSON.stringify(audit).includes('secret'),false);assert.equal(JSON.stringify(audit).includes('raw stack'),false);
    });
  }
  await test('known own task is stopped by exact ID before a new failed start; foreign native task survives',async()=>{
    const e=downloads();e.service.liveNative.add(999);
    await e.Coordinator.start('old',()=>{});e.service.failStart=Object.assign(Error('verification'),{code:9800005});
    await assert.rejects(e.Coordinator.start('new',()=>{}),/9800005/);
    assert.deepEqual(e.service.stops,[1]);assert.deepEqual([...e.service.liveNative],[999]);assert.equal(e.events.size,0);
  });
  await test('missing accepted native ID never triggers all-task stop or claims background lease',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');e.service.invalidId=true;e.service.liveNative.add(999);
    await e.Queue.resume(task.id);assert.equal(task.status,'completed');assert.match(task.error,/任务标识/);
    assert.equal(e.Coordinator.held(task.id),false);assert.deepEqual(e.service.stops,[]);assert.equal(e.service.liveNative.has(999),true);
  });
  await test('leaving foreground during unaccepted native start revokes lease and stops late accepted task',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();e.service.startGate=gate;
    const run=e.Queue.resume(task.id);await tick();assert.equal(task.status,'starting');await e.Queue.setForeground(false);
    assert.equal(task.status,'paused');gate.resolve();await run;
    assert.equal(task.savedPages,0);assert.equal(e.calls.length,0);assert.equal(e.Coordinator.held(task.id),false);assert.deepEqual(e.service.stops,[1]);
  });
  await test('direct stop during pending native start waits and releases exact late accepted ID once',async()=>{
    const audit=[],e=downloads((...entry)=>audit.push(entry)),gate=deferred();e.service.startGate=gate;e.service.liveNative.add(999);
    const started=e.Coordinator.start('pending',()=>{});const rejected=assert.rejects(started,/取消/);await tick();
    let stopped=false;const stop=e.Coordinator.stop().then(()=>stopped=true);await tick();assert.equal(stopped,false);
    assert.equal(e.Coordinator.held('pending'),false);gate.resolve();await rejected;await stop;
    assert.deepEqual(e.service.stops,[1]);assert.deepEqual([...e.service.liveNative],[999]);assert.equal(e.events.size,0);
    assert.ok(audit.some(entry=>entry[2]==='accepted-after-cancel'));
  });
  await test('unrelated cancel/suspend while native start pending cannot cancel this owner',async()=>{
    const e=downloads(),gate=deferred();e.service.startGate=gate;let failures=0;
    const started=e.Coordinator.start('pending',()=>failures++);await tick();
    e.events.get('continuousTaskCancel')({id:999,reason:4});
    e.events.get('continuousTaskSuspend')({continuousTaskId:999,suspendState:true,suspendReason:4});
    gate.resolve();await started;assert.equal(failures,0);assert.equal(e.Coordinator.held('pending'),true);
    await e.Coordinator.stop();assert.deepEqual(e.service.stops,[1]);assert.equal(e.events.size,0);
  });
  await test('pause while WantAgent is pending never invokes native start',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();e.service.agentGate=gate;
    const run=e.Queue.resume(task.id);await tick();e.Queue.pause(task.id);gate.resolve();await run;
    assert.equal(task.status,'paused');assert.equal(e.service.starts.length,0);assert.equal(e.calls.length,0);assert.equal(e.events.size,0);
  });
  for(const event of ['continuousTaskCancel','continuousTaskSuspend']){
    await test('system '+event+' pauses, reports reason, releases service, and discards late HTTP',async()=>{
      const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
      e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);await gate.promise;return bytes()};
      const run=e.Queue.resume(task.id);await tick();
      // The bounded page pool has already issued the whole first chapter batch.
      const issued=e.calls.length;assert.equal(issued,2,'first chapter batch is fetched by the page pool');
      e.events.get(event)(event==='continuousTaskCancel'?{id:1,reason:4}:{continuousTaskId:1,suspendState:true,suspendReason:4});
      assert.equal(task.status,'paused');assert.match(task.error,/原因=4/);assert.equal(e.Coordinator.held(task.id),false);
      gate.resolve();await run;assert.equal(task.savedPages,0);assert.equal(e.calls.length,issued);assert.deepEqual(e.service.stops,[1]);assert.equal(e.events.size,0);
    });
  }
  await test('callback for unrelated native task does not affect accepted transfer',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);if(e.calls.length===1)await gate.promise;return bytes()};
    const run=e.Queue.resume(task.id);await tick();e.events.get('continuousTaskCancel')({id:999,reason:4});
    assert.equal(task.status,'running');gate.resolve();await run;assert.equal(task.status,'completed');
  });
  await test('delete waits for old HTTP runner; blocks resume; only own DL folder is removed, history/local files stay',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
    const local='/app/files/local_comics/imported/page.png',history='/app/files/history.rdb';e.files.set(local,'user');e.files.set(history,'history');
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);await gate.promise;return bytes()};
    const run=e.Queue.resume(task.id);await tick();let done=false;const deletion=e.Queue.deleteTask(task.id).then(()=>done=true);await tick();
    assert.equal(done,false);assert.equal(e.deleted.length,0);await assert.rejects(e.Queue.resume(task.id),/重置\/删除/);
    gate.resolve();await run;await deletion;
    assert.equal(e.Queue.tasks.length,0);assert.equal(e.files.get(local),'user');assert.equal(e.files.get(history),'history');assert.equal(task.savedPages,0);
    assert.deepEqual(e.deleted,[folder(task)]);assert.equal([...e.files.keys()].some(p=>p.startsWith(folder(task)+'/')),false);
  });
  await test('delete waits for asynchronous decoder release; old decoder cannot write after task removal',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();let decoding=false;
    e.ctx.image.createImageSource=()=>({getImageInfo:async()=>{decoding=true;await gate.promise;return {size:{width:10,height:20},mimeType:'image/png'}},createPixelMap:async()=>({getImageInfo:async()=>({size:{width:10,height:20}}),release:async()=>{}}),release:async()=>{}});
    const run=e.Queue.resume(task.id);await tick();assert.equal(decoding,true);
    const deletion=e.Queue.deleteTask(task.id);await tick();assert.equal(e.deleted.length,0);gate.resolve();await run;await deletion;
    assert.equal(e.writes.some(p=>p.endsWith('.part')),false);assert.equal(e.Queue.tasks.length,0);
  });
  await test('generation guard rejects stale HTTP even if task status is changed back to running',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);await gate.promise;return bytes()};
    const run=e.Queue.resume(task.id);await tick();e.Queue.pause(task.id);task.status='running';
    await assert.rejects(e.Queue.resume(task.id),/尚在退出/);gate.resolve();await run;
    assert.equal(task.savedPages,0);assert.equal(e.writes.some(p=>p.endsWith('.part')),false);
  });
  await test('restart awaits old runner then starts chapter/page zero, preserving files until verified replacement',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    const old=e.files.get(`${folder(task)}/0001/000001.png`),gate=deferred();let first=true;
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);if(first){first=false;await gate.promise}return bytes()};
    const restart=e.Queue.restart(task.id);await tick();
    assert.equal(task.savedPages,0);assert.equal(task.page,0);assert.strictEqual(e.files.get(`${folder(task)}/0001/000001.png`),old);
    assert.equal(e.deleted.length,0);gate.resolve();await restart;
    // 4 initial pages + the 4 pages of the restarted run (one batch per chapter).
    assert.equal(task.status,'completed');assert.equal(task.savedPages,4);assert.equal(e.calls.length,8);
    assert.deepEqual(e.calls.slice(4),['a-1','a-2','b-1','b-2']);
  });
  await test('restart active runner does not let its old response enter the new generation',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();let old=true;
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);if(old){old=false;await gate.promise}return bytes()};
    const run=e.Queue.resume(task.id);await tick();const restarted=e.Queue.restart(task.id);await tick();
    assert.equal(e.service.starts.length,1);assert.equal(task.savedPages,0);gate.resolve();await run;await restarted;
    assert.equal(task.status,'completed');assert.equal(task.savedPages,4);
    // The aborted runner issued its whole first batch (2 pages); the restarted run redoes all 4.
    assert.deepEqual(e.calls,['a-1','a-2','a-1','a-2','b-1','b-2']);assert.deepEqual(e.service.stops,[1,2]);
  });
  await test('process-death restore pauses records with no native service or network and keeps checkpoint/files',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);task.status='running';task.chapter=1;task.page=1;task.savedPages=3;
    e.files.set('/app/files/downloads.json',JSON.stringify(e.Queue.tasks));const restored=downloads();
    for(const [p,v]of e.files)restored.files.set(p,v);for(const p of e.dirs)restored.dirs.add(p);
    restored.Queue.init();assert.equal(restored.Queue.tasks[0].status,'paused');assert.equal(restored.Queue.tasks[0].savedPages,3);
    assert.equal(restored.service.starts.length,0);assert.equal(restored.service.agents.length,0);assert.equal(restored.calls.length,0);assert.equal(restored.deleted.length,0);
    await restored.Queue.resume(task.id);assert.equal(restored.Queue.tasks[0].status,'completed');assert.deepEqual(restored.calls,['b-2']);
  });
  await test('invalid ids, roots, ownership and symlink descendants rejected before SDK recursive deletion',async()=>{
    for(const mode of ['id','root','owner','link']){
      const e=downloads(),task=await e.Queue.add('fixture','comic');
      if(mode==='id')task.id='../imported';
      if(mode==='root')e.ctx.AppContext.localComicDir='/app/files/local_comics/../other';
      if(mode==='owner')e.files.set(`${folder(task)}/download.json`,JSON.stringify({owner:'foreign'}));
      if(mode==='link')e.symlinks.add(`${folder(task)}/0001`);
      await assert.rejects(e.Queue.deleteTask(task.id));assert.equal(e.deleted.length,0);assert.equal(e.Queue.tasks.length,1);
    }
  });
  await test('partial cleanup touches strict own page .part files only; final images and unrelated local partials survive',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');e.dirs.add(`${folder(task)}/0001`);
    const own=`${folder(task)}/0001/000001.png.part`,other='/app/files/local_comics/imported/000001.png.part',odd=`${folder(task)}/0001/notes.part`;
    e.files.set(own,'partial');e.files.set(other,'other');e.files.set(odd,'notes');await e.Queue.resume(task.id);
    assert.equal(e.files.has(own),false);assert.equal(e.files.get(other),'other');assert.equal(e.files.get(odd),'notes');assert.deepEqual(e.deleted,[own]);
  });
  await test('short/failed page write cleans own .part and does not advance checkpoint',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),write=e.ctx.fs.writeSync;
    e.ctx.fs.writeSync=(p,b)=>{const n=write(p,b);return p.endsWith('.part')?n-1:n};
    await assert.rejects(e.Queue.resume(task.id),/不完整/);assert.equal(task.savedPages,0);assert.equal([...e.files.keys()].some(p=>p.endsWith('.part')),false);assert.deepEqual(e.service.stops,[1]);
  });
  await test('stop failure is visible and must be released before accepting another native start',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');e.service.failStop=Object.assign(Error('service unavailable'),{code:9800004});
    await assert.rejects(e.Queue.resume(task.id),/9800004/);assert.match(task.error,/9800004/);assert.equal(e.Coordinator.held(task.id),false);
    e.service.failStop=null;await e.Queue.restart(task.id);assert.equal(task.status,'completed');assert.equal(e.service.starts.length,2);assert.ok(e.service.stops.filter(id=>id===1).length>=2);
  });
  await test('ability destruction pauses, releases service, awaits inflight, never auto-starts on foreground',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),gate=deferred();
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);await gate.promise;return bytes()};
    const run=e.Queue.resume(task.id);await tick();let done=false;const shutdown=e.Queue.shutdown('destroy').then(()=>done=true);await tick();
    const issued=e.calls.length;assert.equal(issued,2,'the page pool issued one chapter batch before the shutdown');
    assert.equal(task.status,'paused');assert.equal(done,false);assert.equal(e.Coordinator.held(task.id),false);
    gate.resolve();await run;await shutdown;await e.Queue.setForeground(true);assert.equal(task.savedPages,0);assert.equal(e.service.starts.length,1);assert.equal(e.calls.length,issued);
  });
  assert.equal(count,27,'all registered production cases must finish');
  finished=true;
  console.log(`PASS ${count} production background/queue race safety cases; actual OS permission/scheduling remains unverified.`);
})().catch(e=>{console.error(e);process.exitCode=1});
