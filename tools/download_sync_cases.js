'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/download-sync-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=download-sync-tests production modules; no real files/server/user records\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function downloads(){
  return require('./download_test_harness').downloads((t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`));
}
function sync(){
  const transactions=[],insertions=[],requests=[];let fail=false;
  const ctx=vm.createContext({
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},
    Settings:{readerMode:'galleryRightToLeft'},
    Database:{query:async()=>({goToNextRow:()=>false,close:()=>{}}),rdb:{
      beginTransaction:()=>transactions.push('begin'),commit:()=>transactions.push('commit'),rollBack:()=>transactions.push('rollback'),
      executeSync:(sql,args)=>{if(fail)throw Error('DB fail');insertions.push({sql,args})}}},
    http:{RequestMethod:{PUT:'PUT',GET:'GET'}},
    HttpRequestOptions:class{headers=new Map();retries=1},
    util:{TextEncoder:class{encodeInto(t){return Buffer.from(t)}},Base64Helper:class{encodeToStringSync(b){return Buffer.from(b).toString('base64')}}},
    HttpClient:{request:async(u,m,o)=>{requests.push({u,m,o});return {ok:true,status:200,body:JSON.stringify({format:'venera-hm-reader-data',version:1,tables:[]})}}}
  });
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/features/DataSync.ets'),{mode:'transform'})+'\nglobalThis.Sync=DataSync;',ctx);
  return {ctx,Sync:ctx.Sync,transactions,insertions,requests,setFail:v=>fail=v};
}
let count=0;
async function test(name,run){await run();count++;fs.appendFileSync(log,`[响应返回] TraceID=download-sync-tests PASS ${name}\n`);}
(async()=>{
  await test('task creation is paused and duplicate requests do not duplicate tasks',async()=>{
    const e=downloads(),a=await e.Queue.add('fixture','comic'),b=await e.Queue.add('fixture','comic');
    assert.equal(a.id,b.id);assert.equal(e.Queue.tasks.length,1);assert.equal(a.status,'paused');assert.equal(e.calls.length,0);
  });
  await test('concurrent same-comic adds coalesce before detail request returns',async()=>{
    const e=downloads(),tasks=await Promise.all(Array.from({length:8},()=>e.Queue.add('fixture','comic')));
    assert.equal(new Set(tasks.map(t=>t.id)).size,1);assert.equal(e.Queue.tasks.length,1);
  });
  await test('download decodes four real-page candidates and checkpoints each page',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    assert.equal(task.status,'completed');assert.equal(task.savedPages,4);assert.equal(task.chapter,2);
    assert.deepEqual(e.calls,['a-1','a-2','b-1','b-2']);
    assert.equal([...e.files.keys()].filter(p=>p.endsWith('.png')).length,4);
    assert.ok([...e.files.keys()].every(p=>!p.endsWith('.part')));
  });
  await test('pause while request is pending discards late page and resume redownloads it',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),pending=[];
    e.ctx.HttpClient.getBytes=u=>new Promise(r=>{e.calls.push(u);pending.push(r)});
    const run=e.Queue.resume(task.id);await new Promise(r=>setImmediate(r));
    // The bounded page pool issued the whole first chapter batch; pause must discard every late one.
    assert.equal(pending.length,2);
    e.Queue.pause(task.id);for(const r of pending.splice(0))r({ok:true,bytes:new ArrayBuffer(128)});await run;
    assert.equal(task.status,'paused');assert.equal(task.savedPages,0);assert.equal(task.page,0);
    e.ctx.HttpClient.getBytes=async u=>{e.calls.push(u);return {ok:true,bytes:new ArrayBuffer(128)}};
    await e.Queue.resume(task.id);assert.equal(task.savedPages,4);assert.equal(e.calls.filter(u=>u==='a-1').length,2);
  });
  await test('accepted native transfer continues in background; foreground does not auto-start a paused task',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic'),pending=[];
    e.ctx.HttpClient.getBytes=u=>new Promise(r=>{e.calls.push(u);pending.push(r)});
    const run=e.Queue.resume(task.id);await new Promise(r=>setImmediate(r));
    assert.equal(e.Coordinator.held(task.id),true);
    await e.Queue.setForeground(false);assert.equal(task.status,'running');
    e.Queue.pause(task.id);
    const issued=e.calls.length;assert.equal(issued,2,'the page pool issued one chapter batch');
    for(const r of pending.splice(0))r({ok:true,bytes:new ArrayBuffer(128)});await run;
    await assert.rejects(e.Queue.resume(task.id),/后台/);
    assert.equal(task.savedPages,0);await e.Queue.setForeground(true);
    assert.equal(task.status,'paused');assert.equal(e.calls.length,issued);assert.equal(e.service.stops.length,1);
  });
  await test('explicit pauseAll covers checkpoint validation as well as running downloads',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');task.status='checking';
    e.Queue.pauseAll('page hide');assert.equal(task.status,'paused');
    assert.equal(e.calls.length,0);
  });
  await test('invalid image bytes cannot become a completed page',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');
    e.ctx.image.createImageSource=()=>({getImageInfo:async()=>{throw Error('not image')},release:async()=>{}});
    await assert.rejects(e.Queue.resume(task.id));assert.equal(task.status,'failed');assert.equal(task.savedPages,0);
  });
  await test('unsupported required image transform fails rather than storing scrambled pages',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');
    e.ctx.ImageRequests.resolve=async()=>{throw Error('IMAGE_CONFIG_UNSUPPORTED: modifyImage')};
    await assert.rejects(e.Queue.resume(task.id));assert.equal(e.calls.length,0);
  });
  await test('foreign ownership marker prevents any network/write work',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');
    e.files.set(`/app/files/local_comics/${task.id}/download.json`,JSON.stringify({owner:'foreign'}));
    await assert.rejects(e.Queue.resume(task.id));assert.equal(e.calls.length,0);
  });
  await test('cancel does not delete completed page files',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    const before=e.files.size;e.Queue.cancel(task.id);
    assert.equal(e.files.size,before);await e.Queue.resume(task.id);assert.equal(e.calls.length,4);
  });
  await test('diagnostics cleanup refuses ordinary downloads',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');
    assert.throws(()=>e.Queue.cleanupProbe(task.id));assert.ok(e.files.has(`/app/files/local_comics/${task.id}/download.json`));
  });
  await test('completed task validation checks disk without network',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    const before=e.calls.length;await e.Queue.resume(task.id);
    assert.equal(task.status,'completed');assert.equal(task.savedPages,4);assert.equal(e.calls.length,before);
  });
  await test('missing checkpoint page rewinds and redownloads without deleting later files',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    e.files.delete(`/app/files/local_comics/${task.id}/0001/000002.png`);
    await e.Queue.resume(task.id);assert.equal(task.status,'completed');assert.equal(task.savedPages,4);
    assert.equal(e.calls.length,7);assert.equal(e.calls.filter(u=>u==='a-1').length,1);
  });
  await test('invalid fractional/nonnumeric checkpoint rejected before network writes',async()=>{
    for(const invalid of [0.5,NaN,-1]){
      const e=downloads(),task=await e.Queue.add('fixture','comic');task.page=invalid;
      await assert.rejects(e.Queue.resume(task.id));assert.equal(e.calls.length,0);
    }
  });
  await test('pause during asynchronous checkpoint validation cannot restart network',async()=>{
    const e=downloads(),task=await e.Queue.add('fixture','comic');await e.Queue.resume(task.id);
    let release;e.ctx.image.createImageSource=()=>({createPixelMap:()=>new Promise(r=>{release=r}),release:async()=>{}});
    const run=e.Queue.resume(task.id);await new Promise(r=>setImmediate(r));
    assert.equal(task.status,'checking');e.Queue.pause(task.id);
    // The validator will read other pages too; return subsequent info immediately.
    e.ctx.image.createImageSource=()=>({createPixelMap:async()=>({getImageInfo:async()=>({size:{width:10,height:20}}),release:async()=>{}}),release:async()=>{}});
    release({getImageInfo:async()=>({size:{width:10,height:20}}),release:async()=>{}});await run;
    assert.equal(task.status,'paused');assert.equal(e.calls.length,4);
  });
  await test('invalid/credential-bearing/non-HTTPS endpoints are rejected',async()=>{
    const e=sync();
    for(const url of ['http://server/dav','https://u:p@server/dav','https://server/dav?token=x','https://server/dav#x','https://ser ver/dav']){
      assert.throws(()=>e.Sync.endpoint(url));
    }
    assert.equal(e.Sync.endpoint('https://server/dav/'),'https://server/dav/venera-hm-reader-data-v1.json');
  });
  await test('backup exports only whitelisted tables and no source credentials/cookies',async()=>{
    const e=sync(),snapshot=await e.Sync.exportSnapshot('test');
    assert.deepEqual(Array.from(snapshot.tables,t=>t.name),['favorite_folders','favorites','history']);
    assert.ok(!JSON.stringify(snapshot).includes('source_data'));assert.ok(!JSON.stringify(snapshot).includes('cookies'));
  });
  await test('foreign table/schema/type corruption rejected before transaction begins',async()=>{
    const e=sync();
    assert.throws(()=>e.Sync.mergeSnapshot({format:'venera-hm-reader-data',version:1,tables:[{name:'source_data',columns:[],rows:[]}]},'t'));
    assert.deepEqual(e.transactions,[]);
    assert.throws(()=>e.Sync.validate({format:'venera-hm-reader-data',version:2,tables:[]}));
    assert.throws(()=>e.Sync.validate({format:'venera-hm-reader-data',version:1,tables:[{name:'favorite_folders',columns:['name','display_order'],rows:[[null,0]]}]}));
  });
  await test('merge uses insert-ignore, never replaces or deletes local records',async()=>{
    const e=sync(),backup={format:'venera-hm-reader-data',version:1,tables:[{name:'favorite_folders',columns:['name','display_order'],rows:[['Probe',1]]}]};
    assert.equal(e.Sync.mergeSnapshot(backup,'merge'),1);
    assert.match(e.insertions[0].sql,/INSERT OR IGNORE/);
    assert.doesNotMatch(e.insertions[0].sql,/REPLACE|DELETE/);
    assert.deepEqual(e.transactions,['begin','commit']);
  });
  await test('import failure rolls back transaction',async()=>{
    const e=sync();e.setFail(true);
    assert.throws(()=>e.Sync.mergeSnapshot({format:'venera-hm-reader-data',version:1,tables:[{name:'favorite_folders',columns:['name','display_order'],rows:[['Probe',1]]}]},'t'));
    assert.deepEqual(e.transactions,['begin','rollback']);
  });
  await test('upload/download use PUT/GET and session-only basic header',async()=>{
    const e=sync();await e.Sync.upload('https://server/dav','fixture','secret');await e.Sync.downloadAndMerge('https://server/dav','fixture','secret');
    assert.deepEqual(e.requests.map(r=>r.m),['PUT','GET']);
    assert.equal(e.requests[0].o.headers.get('Authorization'),'Basic '+Buffer.from('fixture:secret').toString('base64'));
    assert.ok(!e.requests[0].o.jsonBody.includes('secret'));
  });
  console.log(`PASS ${count} production download/sync safety/transport cases; not real WebDAV acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
