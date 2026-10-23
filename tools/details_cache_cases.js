'use strict';
// End-to-end details cache through the REAL JsComicSource adapter.
// Proves the user's symptom ("covers/details reload on every app start") is fixed:
// a second launch with a fresh in-memory state and the same cache directory must
// paint details from disk with ZERO script calls.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),os=require('node:os');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..');
const log=path.join(root,'logs/details-cache-cases.log');
fs.writeFileSync(log,'Details cache through real JsComicSource adapter; temp dirs + fake engine; no device/network.\n');
const deps=require('./vm_deps');
const {fakeFs,utilFake}=require('./cache_fakes');
const read=f=>fs.readFileSync(path.join(root,f),'utf8').replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'venera-details-cache-'));
let count=0,finished=false;const EXPECTED=5;
async function test(name,body){let timer;try{
  await Promise.race([Promise.resolve().then(body),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('WATCHDOG '+name)),3000)})]);
  count++;console.log('PASS '+name);fs.appendFileSync(log,'PASS '+name+'\n');
}finally{clearTimeout(timer)}}
process.on('beforeExit',()=>{if(!finished){console.error('DETAILS_CACHE_INCOMPLETE count='+count);process.exitCode=1}});

// One "process": fresh module instances, fresh memory, SAME cache directory.
function launch(){
  const calls=[];
  const context=vm.createContext({Map,Set,JSON,Promise,Date,ArrayBuffer,Uint8Array,console,
    setTimeout:(fn)=>{fn();return 0},clearTimeout:()=>{},
    Log:{audit:()=>{},warn:()=>{},info:()=>{},error:()=>{}},
    APP_VERSION:'1.17.0',parseComic:o=>o,parseComicList:l=>l,parseStringList:l=>Array.isArray(l)?l:[],
    toStringOrNull:v=>typeof v==='string'?v:null,toIntOrNull:v=>typeof v==='number'?v:null,
    CookieJar:{header:()=>''},
    JsEngine:{isAvailable:true,evaluate:()=>'',
      callJson:async(code)=>{calls.push(code);
        return /loadEp/.test(code)?{images:['https://img.invalid/1.jpg','https://img.invalid/2.jpg']}:detailsPayload();}},
    SourceManager:{find:()=>undefined,all:()=>[]},
    Settings:{getString:(k,f)=>f,setString:async()=>{}},
    AppContext:{imageCacheDir:dir},
    fs:fakeFs(),util:utilFake(),
  });
  vm.runInContext(stripTypeScriptTypes(
    read('entry/src/main/ets/foundation/CacheStore.ets')+'\n'+
    deps.join(deps.SOURCE_FILES),{mode:'transform'})+
    '\nglobalThis.Store=CacheStore;globalThis.Payload=PayloadCache;globalThis.Adapter=JsComicSource;'+
    '\nglobalThis.ComicSource=ComicSource;',context);
  // Real store + payload cache over the shared temp dir, wired like CacheManager.
  const store=new context.Store(dir,'.img',1024*1024*1024);
  context.CacheManager={payloads:()=>new context.Payload(store)};
  const source=new context.Adapter('fixture','Fixture','1.0.0','<fixture>');
  source.configure({loadInfo:true,loadEp:true},[],[]);
  return {context,source,calls,store};
}
function detailsPayload(){
  return {title:'Fixture Comic',cover:'https://img.invalid/c.jpg',
    tags:{genre:['action'],artist:['someone']},
    chapters:{Vol1:{a:'Chapter A',b:'Chapter B'}},
    comments:[],url:'https://site.invalid/g/9/'};
}

(async()=>{
  await test('first launch loads details over the adapter and writes the cache',async()=>{
    const {source,calls}=launch();
    const result=await source.loadComicInfo('comic-1');
    assert.equal(result.error,false,'first load must succeed');
    assert.equal(calls.length,1,'exactly one script call on a cold cache');
    assert.equal(result.dataOrNull.title,'Fixture Comic');
    assert.notEqual(result.dataOrNull.chapters,undefined,'chapters must be parsed from the source payload');
  });

  await test('second launch paints details from disk with ZERO script calls',async()=>{
    const {source,calls}=launch();
    const cached=await source.loadCachedComicInfo('comic-1');
    assert.notEqual(cached,undefined,'cached details must survive a new launch');
    assert.equal(calls.length,0,'cache hit must not touch the source script');
    assert.equal(cached.title,'Fixture Comic');
    // Maps survive because the raw source JSON was cached, not the parsed model.
    assert.deepEqual(Array.from(cached.tags.get('genre')??[]),['action']);
    assert.equal(cached.url,'https://site.invalid/g/9/');
  });

  await test('a cache hit still refreshes over the network and does not stay stale',async()=>{
    const {source,calls}=launch();
    assert.notEqual(await source.loadCachedComicInfo('comic-1'),undefined);
    const fresh=await source.loadComicInfo('comic-1');
    assert.equal(fresh.error,false);
    assert.equal(calls.length,1,'refresh must reach the script exactly once');
  });

  await test('page list write-through caches the chapter images without changing the live result',async()=>{
    const {source,calls,context}=launch();
    const pages=await source.loadComicPages('comic-1','a');
    assert.equal(pages.error,false);
    assert.equal(calls.length,1);
    const payloads=context.CacheManager.payloads();
    const cached=payloads.pageList('fixture','comic-1','a');
    assert.notEqual(cached,undefined,'page list should be cached for reference');
    assert.deepEqual(Array.from(cached),Array.from(pages.dataOrNull));
  });

  await test('an unknown comic is a cache miss, not a false hit',async()=>{
    const {source,calls}=launch();
    assert.equal(await source.loadCachedComicInfo('never-seen'),undefined);
    assert.equal(calls.length,0,'a miss must not invent data or call the script');
  });

  assert.equal(count,EXPECTED);finished=true;
  fs.rmSync(dir,{recursive:true,force:true});
  console.log(`PASS ${count} details-cache cases through the real source adapter (temp cache dir, fake engine; no device/network).`);
})().catch(error=>{fs.appendFileSync(log,error.stack+'\n');console.error(error);process.exitCode=1});
