'use strict';
// Actual existing host NAPI/QuickJS + production ArkTS adapter/session/parser +
// FULL UNCHANGED installed scripts. HTTP is intercepted in-memory, no sockets.
// This is neither a device test nor ArkTS SDK compilation nor live-site evidence.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/ranking-napi-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));
fs.writeFileSync(log,'Production ranking adapter/session through actual host NAPI and unchanged installed scripts. In-memory synthetic HTTP only; no account/network/device acceptance.\n');
const requests=[];let rejectNext=false,ehDomain='e-hentai.org';
const wnHtml=(id,max=2)=>`<div class="grid"><div class="gallary_wrap"><ul class="cc"><li><div class="pic_box"><a href="/photos-index-aid-${id}.html"><img src="//fixture.invalid/cover.jpg"></a></div><div class="info"><div class="title"><a>Fixture ${id}</a></div><div class="info_col">Fixture info</div></div></li></ul></div></div><div class="f_left paginator"><a>1</a><a>${max}</a></div>`;
const ehHtml=id=>`<div class="gl1t"><a href="https://e-hentai.org/g/${id}/fixture/">EH fixture ${id}</a><img src="https://fixture.invalid/cover.jpg"><div class="gl5t"><div><div class="cs">Manga</div><div>2026-01-01</div><div class="ir" style="background-position:0px -1px"></div><div>20 pages</div></div></div></div>`;
native.setMessageHandler(message=>{
  if(message.method==='load_setting'){
    return message.setting_key==='domainSelection'?'0':message.setting_key==='domain0'?'fixture.invalid':message.setting_key==='domain'?ehDomain:null;
  }
  if(message.method==='load_data')return null;
  if(message.method==='getPlatform')return 'ohos';
  if(message.method==='log')return null;
  if(message.method!=='http')throw Error('Unexpected fixture host method: '+message.method);
  requests.push(message);
  if(rejectNext){rejectNext=false;return Promise.resolve({status:503,body:'private failure body',headers:{}})}
  if(/^https:\/\/fixture\.invalid\/albums-favorite_ranking-page-\d+-type-(day|week|month)\.html$/.test(message.url)){
    const page=Number(message.url.match(/page-(\d+)/)[1]);const option=message.url.match(/type-(\w+)/)[1];
    return Promise.resolve({status:200,body:wnHtml((option==='day'?100:200)+page),headers:{}});
  }
  if(/^https:\/\/e-hentai\.org\/toplist\.php\?tl=(15|13|12|11)&p=\d+$/.test(message.url)){
    const url=new URL(message.url);return Promise.resolve({status:200,body:ehHtml(300+Number(url.searchParams.get('p'))),headers:{}});
  }
  if(message.url==='https://komiic.com/api/query'){
    assert.equal(message.http_method,'POST');const payload=typeof message.data==='string'?JSON.parse(message.data):message.data;
    assert.equal(payload.operationName,'hotComics');assert.equal(payload.variables.pagination.limit,20);
    const offset=payload.variables.pagination.offset,order=payload.variables.pagination.orderBy;
    assert.ok(['MONTH_VIEWS','VIEWS'].includes(order));
    const comics=offset>=40?[]:[{id:order+'-'+offset,title:'Komiic fixture',status:'ONGOING',year:2026,imageUrl:'https://fixture.invalid/k.jpg',authors:[{name:'Fixture author'}],categories:[{name:'Fixture tag'}],dateUpdated:'2026-01-01T00:00:00Z'}];
    return Promise.resolve({status:200,body:JSON.stringify({data:{hotComics:comics}}),headers:{}});
  }
  throw Error('No fixture for unexpected request; real network is never used');
});
native.setGlobalString('appVersion','1.17.0');
for(const p of ['init.js','sendmessage_shim.js','html_engine.js'])native.evaluate(read('entry/src/main/resources/rawfile/'+p),'<'+p+'>');
for(const [file,cls,key] of [['wnacg','Wnacg','wnacg'],['ehentai','Ehentai','ehentai'],['Komiic','Komiic','Komiic']]){
  native.evaluate(read(`logs/user8-installed-scripts/${file}.js`)+`\nComicSource.sources[${JSON.stringify(key)}]=new ${cls}();`, '<unchanged-installed-'+file+'>');
}
const context=vm.createContext({Error,APP_VERSION:'1.17.0',setTimeout:()=>0,
  SourceDataStore:{get:()=>undefined,set:()=>{}},
  Log:{info:()=>{},warn:()=>{},audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},
  JsEngine:{isAvailable:true,evaluate:(code,name)=>native.evaluate(code,name),callJson:(code,name,trace)=>native.callJson(code,name,trace||'ranking-napi-test')}});
vm.runInContext(stripTypeScriptTypes([
  'entry/src/main/ets/foundation/Extensions.ets','entry/src/main/ets/model/Comic.ets','entry/src/main/ets/model/Res.ets',
  'entry/src/main/ets/features/SourceFailure.ets','entry/src/main/ets/source/RankingData.ets',
  'entry/src/main/ets/source/JsRankingAdapter.ets','entry/src/main/ets/features/RankingSession.ets',
  'entry/src/main/ets/foundation/Semver.ets','entry/src/main/ets/model/ComicDetails.ets',
  'entry/src/main/ets/model/BrowserLogin.ets','entry/src/main/ets/source/AuthLogScope.ets',
  'entry/src/main/ets/source/DetailsCapabilities.ets','entry/src/main/ets/source/JsDetailsAdapter.ets',
  'entry/src/main/ets/source/JsFavoritesAdapter.ets','entry/src/main/ets/source/ComicSource.ets',
  'entry/src/main/ets/source/JsComicSource.ets'
].map(clean).join('\n'),{mode:'transform'})+'\nglobalThis.T={JsRankingAdapter,RankingSession,JsComicSource,ComicSourceParser};',context);
const source=key=>{const s=new context.T.JsComicSource(key,key,'1.0.0','<installed-ranking-fixture>');s.configure({category:true,categoryLanding:true,categoryLoad:false,ranking:true,rankingLoad:true},[],[]);return s};
let count=0;async function test(name,run){await run();count++;fs.appendFileSync(log,'PASS '+name+'\n')}
(async()=>{
  await test('unchanged WN ranking real HTML parser, max pages and selection reset',async()=>{
    const s=new context.T.RankingSession();await s.start(source('wnacg'));assert.equal(s.error,'');assert.equal(s.option,'day');assert.equal(s.results[0].id,'101');
    await s.more();assert.equal(s.page,2);assert.equal(s.results.length,2);assert.equal(s.ended,true);
    await s.select('week');assert.equal(s.results.length,1);assert.equal(s.results[0].id,'201');
    assert.equal(requests[0].url,'https://fixture.invalid/albums-favorite_ranking-page-1-type-day.html');
    assert.equal(requests[1].url,'https://fixture.invalid/albums-favorite_ranking-page-2-type-day.html');
  });
  await test('unchanged EH rank-only category, zero-based HTTP page and source-locked parsed comics',async()=>{
    const eh=source('ehentai'),metadata=await eh.loadCategoryData();assert.equal(metadata.parts.length,0);assert.equal(metadata.enableRankingPage,true);assert.equal(eh.supportsCategory,true);assert.equal(eh.categoryComics.load,undefined);
    const s=new context.T.RankingSession();await s.start(eh);assert.equal(s.error,'');assert.equal(s.option,'15');assert.equal(s.results[0].id,'https://e-hentai.org/g/300/fixture/');
    assert.equal(s.results[0].sourceKey,'ehentai');assert.equal(s.ended,false);await s.more();assert.equal(s.results[1].id,'https://e-hentai.org/g/301/fixture/');
    assert.ok(requests.some(r=>r.url==='https://e-hentai.org/toplist.php?tl=15&p=0'));
    assert.ok(requests.some(r=>r.url==='https://e-hentai.org/toplist.php?tl=15&p=1'));
    ehDomain='exhentai.org';await s.select('13');assert.match(s.results[0].id,/exhentai\.org/);ehDomain='e-hentai.org';
  });
  await test('unchanged Komiic GraphQL ranking offsets/order; unknown max ends on empty page',async()=>{
    const s=new context.T.RankingSession();await s.start(source('Komiic'));assert.equal(s.error,'');assert.equal(s.results[0].id,'MONTH_VIEWS-0');
    await s.more();assert.equal(s.results[1].id,'MONTH_VIEWS-20');await s.more();assert.equal(s.page,3);assert.equal(s.ended,true);assert.equal(s.results.length,2);
    await s.select('VIEWS');assert.equal(s.results[0].id,'VIEWS-0');assert.equal(s.results.length,1);
  });
  await test('real NAPI HTTP failure retains committed ranking page and retries same installed request',async()=>{
    const s=new context.T.RankingSession();await s.start(source('wnacg'));rejectNext=true;await s.more();assert.equal(s.page,1);assert.equal(s.results.length,1);assert.match(s.error,/503/);
    await s.retry();assert.equal(s.page,2);assert.equal(s.error,'');assert.equal(requests.at(-1).url,requests.at(-2).url);
    assert.doesNotMatch(fs.readFileSync(log,'utf8'),/private failure body/);
  });
  await test('real QuickJS loadWithNext null/opaque cursor contract (synthetic source; installed samples are page-only)',async()=>{
    native.evaluate(`ComicSource.sources.cursor_fixture={categoryComics:{ranking:{options:['a-A-label'],loadWithNext:async(option,next)=>{
      if(option!=='a')throw Error('option changed');if(next!==null&&next!=='opaque:/?after=a%2Fb')throw Error('cursor changed');
      return {comics:[{id:next===null?'first':'second'}],next:next===null?'opaque:/?after=a%2Fb':null};}}}};`,'<synthetic-cursor>');
    const s=new context.T.RankingSession();await s.start({key:'cursor_fixture',categoryComics:{rankingData:context.T.JsRankingAdapter.create('cursor_fixture','<cursor>',false,true)}});
    assert.equal(s.error,'');await s.more();assert.equal(s.results.length,2);assert.equal(s.ended,true);
  });
  await test('full unchanged installed scripts through production parser summary and factory registration',async()=>{
    for(const key of ['wnacg','ehentai','Komiic']){
      // Unrelated source init timers deliberately not scheduled in this ranking-only fixture.
      const parsed=await context.T.ComicSourceParser.parse(read(`logs/user8-installed-scripts/${key}.js`),'<parser-installed-'+key+'>');
      assert.ok(parsed.categoryComics.rankingData);assert.equal(typeof parsed.categoryComics.rankingData.load,'function');assert.equal(parsed.categoryComics.rankingData.loadWithNext,undefined);
      const metadata=await parsed.loadCategoryData();assert.equal(metadata.enableRankingPage,true);
      const s=new context.T.RankingSession();await s.start(parsed);assert.equal(s.error,'');assert.ok(s.results.length>0);assert.equal(s.results[0].sourceKey,key);
    }
    const bad=await context.T.ComicSourceParser.parse('class MissingRanking extends ComicSource { key="missingranking"; name="Missing";category={parts:[],enableRankingPage:true};categoryComics={ranking:{options:["day-Day"],loadNext:async()=>{throw Error("must not call")}}};}', '<missing-ranking>');
    assert.ok(bad.categoryComics.rankingData);assert.equal(bad.categoryComics.rankingData.load,undefined);assert.equal(bad.categoryComics.rankingData.loadWithNext,undefined);
    const s=new context.T.RankingSession();await s.start(bad);assert.equal(s.loading,false);assert.match(s.error,/load\/loadWithNext/);
  });
  console.log(`PASS ${count} production ranking / actual host NAPI / unchanged installed-script fixture cases; ${requests.length} controlled HTTP requests, zero actual network.`);
})().catch(error=>{fs.appendFileSync(log,error.stack+'\n');console.error(error);process.exitCode=1});
