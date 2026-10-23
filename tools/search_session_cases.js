'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/search-session-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=search-tests production session plus deterministic source fakes\n');
const load=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const resultCode=load('entry/src/main/ets/model/Res.ets');
const sessionCode=load('entry/src/main/ets/features/SearchSession.ets');
const ctx=vm.createContext({Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}});
vm.runInContext(stripTypeScriptTypes(resultCode+'\n'+sessionCode,{mode:'transform'})+'\nglobalThis.Session=SearchSession;globalThis.Result=Res;',ctx);
const item=(id,key='a')=>({id,sourceKey:key,title:id,cover:'cover'});
const ok=(items,next)=>new ctx.Result(items,undefined,next);
const tick=()=>new Promise(r=>setImmediate(r));
let count=0;
async function test(name,run){await run();count++;fs.appendFileSync(log,`[响应返回] TraceID=search-tests PASS ${name}\n`);}
(async()=>{
  await test('page pagination and explicit max page stop',async()=>{
    const calls=[],s=new ctx.Session();
    const source={key:'a',search:{loadPage:async(k,p,o)=>{calls.push([k,p,o]);return ok([item('p'+p)],2)}}};
    await s.start(source,'query');await s.more();
    assert.equal(s.results.length,2);assert.equal(s.page,2);assert.equal(s.ended,true);
    await s.more();assert.equal(calls.length,2);assert.equal(calls[1][1],2);
  });
  await test('cursor-only first adapter then returned cursor',async()=>{
    const calls=[],s=new ctx.Session();
    const source={key:'a',search:{cursorOnly:true,
      loadPage:async()=>ok([item('one')],'cursor-1'),
      loadNext:async(k,c,o)=>{calls.push([k,c,o]);return ok([item('two')],null)}}};
    await s.start(source,'query');await s.more();
    assert.equal(calls[0][1],'cursor-1');assert.equal(s.results.length,2);assert.equal(s.ended,true);
  });
  await test('repeated cursor stops automatic infinite loading',async()=>{
    const s=new ctx.Session();
    const source={key:'a',search:{cursorOnly:true,loadPage:async()=>ok([item('one')],'same'),
      loadNext:async()=>ok([item('two')],'same')}};
    await s.start(source,'q');await s.more();assert.equal(s.ended,true);
  });
  await test('empty next page preserves prior comics',async()=>{
    const s=new ctx.Session();
    await s.start({key:'a',search:{loadPage:async(k,p)=>ok(p===1?[item('one')]:[])}},'q');
    await s.more();assert.equal(s.results.length,1);assert.equal(s.ended,true);
  });
  await test('duplicate-only page stops without duplicate grid keys',async()=>{
    const s=new ctx.Session();
    await s.start({key:'a',search:{loadPage:async()=>ok([item('one'),item('one')])}},'q');
    await s.more();assert.equal(s.results.length,1);assert.equal(s.ended,true);
  });
  await test('append failure preserves state and retries same page',async()=>{
    const s=new ctx.Session();let fail=true;const calls=[];
    const source={key:'a',search:{loadPage:async(k,p)=>{calls.push(p);if(p===2&&fail)throw Error('network');
      return ok([item('p'+p)],3)}}};
    await s.start(source,'q');await s.more();
    assert.equal(s.results.length,1);assert.equal(s.page,1);assert.match(s.error,/network/);
    fail=false;await s.more();assert.equal(s.page,2);assert.equal(s.error,'');
    assert.deepEqual(calls,[1,2,2]);
  });
  await test('late old source response cannot replace new source',async()=>{
    const s=new ctx.Session();let release;
    const old=s.start({key:'a',search:{loadPage:()=>new Promise(r=>release=r)}},'old');
    await s.start({key:'b',search:{loadPage:async()=>ok([item('new','b')],1)}},'new');
    release(ok([item('old')],1));assert.equal(await old,false);
    assert.equal(s.sourceKey,'b');assert.equal(s.results[0].id,'new');
  });
  await test('late error cannot contaminate newer request',async()=>{
    const s=new ctx.Session();let reject;
    const old=s.start({key:'a',search:{loadPage:()=>new Promise((r,j)=>reject=j)}},'old');
    await s.start({key:'b',search:{loadPage:async()=>ok([item('new','b')],1)}},'new');
    reject(Error('old error'));await old;assert.equal(s.error,'');
  });
  await test('cancelled keyword request cannot repopulate results',async()=>{
    const s=new ctx.Session();let release;
    const old=s.start({key:'a',search:{loadPage:()=>new Promise(r=>release=r)}},'old');
    s.cancel();release(ok([item('old')],1));await old;
    assert.equal(s.results.length,0);assert.equal(s.searched,false);
  });
  await test('concurrent load-more calls issue one request',async()=>{
    const s=new ctx.Session();let calls=0,release;
    const source={key:'a',search:{loadPage:async(k,p)=>{calls++;if(p===1)return ok([item('one')],3);
      return await new Promise(r=>release=r)}}};
    await s.start(source,'q');const pending=s.more();await s.more();await tick();
    assert.equal(calls,2);release(ok([item('two')],3));await pending;
  });
  await test('leaving for details keeps results but drops pending work',async()=>{
    const s=new ctx.Session();let release;
    const source={key:'a',search:{loadPage:async(k,p)=>p===1?ok([item('one')],3):await new Promise(r=>release=r)}};
    await s.start(source,'q');const more=s.more();s.invalidatePending();
    release(ok([item('two')],3));await more;
    assert.equal(s.results.length,1);assert.equal(s.sourceKey,'a');assert.equal(s.loadingMore,false);
  });
  await test('source parser preserves cursor-only provenance',async()=>{
    const source=fs.readFileSync(path.join(root,'entry/src/main/ets/source/JsComicSource.ets'),'utf8');
    assert.match(source,/page\.cursorOnly = !hasPage && hasNext/);
    const view=fs.readFileSync(path.join(root,'entry/src/main/ets/features/SearchView.ets'),'utf8');
    assert.match(view,/comic\.sourceKey\.length > 0 \? comic\.sourceKey : this\.session\.sourceKey/);
    assert.doesNotMatch(view,/sourceKey: source === undefined \? comic\.sourceKey : source\.key/);
  });
  await test('production deep cursor probe is reachable and preserves argument order',async()=>{
    const code=load('entry/src/main/ets/source/SourceSelfTest.ets');
    const calls=[],reports=[];
    const sandbox=vm.createContext({
      ComicSource:{sources:{cursor:{search:{loadNext:async(k,options,next)=>{
        calls.push([k,options,next]);return {comics:[item(next===null?'one':'two')],next:next===null?'bookmark':null};
      }}}}},
      Log:{info:(tag,line)=>reports.push(line),warn:(tag,line)=>reports.push(line)}
    });
    sandbox.JsEngine={callJson:async code=>await vm.runInContext(code,sandbox)};
    vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Probe=SourceSelfTest;',sandbox);
    await sandbox.Probe.probeSearchNext({key:'cursor',search:{cursorOnly:true,loadPage:async()=>ok([]),loadNext:async()=>ok([])}});
    assert.equal(calls.length,2,'loadPage adapter must not make probe unreachable');
    assert.ok(Array.isArray(calls[0][1]));
    assert.equal(calls[0][2],null);
    assert.equal(calls[1][2],'bookmark');
    assert.ok(reports.some(line=>line.includes('cursor path OK')));
  });
  const report=`PASS ${count} search pagination/race/source-identity cases; not device rendering.`;
  fs.appendFileSync(log,report+'\n');console.log(report);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
