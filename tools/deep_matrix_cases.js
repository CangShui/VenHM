'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/deep-matrix-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=deep-tests production runner and image routing with deterministic fakes\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
function environment({failCover=false,brokenPart=false,unsupported=false}={}){
  const reports=[],requests=[],screen=[],files=new Map();
  const make=id=>({id,title:'Title',cover:'cover',sourceKey:'fixture'});
  const result=(data,sub)=>({error:false,dataOrNull:data,subData:sub,get subDataString(){return sub==null?undefined:String(sub)}});
  const source={key:'fixture',name:'Fixture',version:'1.0.0',explorePages:[{}],
    search:{cursorOnly:false,loadPage:async(k,p)=>result([make(k+p)],2)},
    loadComicInfo:async()=>result({title:'Title',cover:'cover',findAuthor:()=>undefined,
      chapters:{length:5,ids:['0','1','2','3','4'],isGrouped:true,groupNames:['a','b','c'],
        getGroup:n=>new Map([[n==='a'?'0':n==='b'?'2':'3',n]])}}),
    loadComicPages:async(id,ep)=>result(Array.from({length:6},(_,i)=>`image-${ep}-${i}`)),
    categoryComics:{optionsLoader:async()=>result([]),load:async(category,param,options,page)=>result([make(category+page)])},
    loadCategoryData:async()=>({parts:[{title:'One',items:[{label:'A',page:'category',attributes:new Map([['category','a']])}]}]})
  };
  const context=vm.createContext({
    Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`),info:(tag,line)=>reports.push(line),warn:(tag,line)=>reports.push(line)},
    SourceDao:{list:async()=>[{key:'fixture'}]},SourceManager:{find:k=>k==='fixture'?source:undefined},
    AppContext:{filesDir:'/sandbox',context:{}},
    SourceSelfTest:{isRunning:false,stopAfterCurrentSource:()=>{}},
    window:{getLastWindow:async()=>({getWindowProperties:()=>({isKeepScreenOn:false}),setWindowKeepScreenOn:async v=>screen.push(v)})},
    fs:{OpenMode:{CREATE:1,READ_WRITE:2,APPEND:4},openSync:p=>({fd:p}),writeSync:(p,s)=>files.set(p,(files.get(p)||'')+s),closeSync:()=>{}},
    ImageRequests:{resolve:async(s,u,t,c,e)=>{requests.push({url:u,thumbnail:t,ep:e});if(unsupported)throw Error('IMAGE_CONFIG_UNSUPPORTED: modifyImage');return {url:u,headers:new Map(),modifyImage:''}}},
    ImagePipeline:{fetch:async config=>{
      if(failCover&&config.url==='cover')throw Error('image HTTP 403');return new ArrayBuffer(128);}},
    HttpClient:{getBytes:async u=>({ok:!(failCover&&u==='cover'),status:failCover&&u==='cover'?403:200,bytes:new ArrayBuffer(128)})},
    image:{createImageSource:()=>({createPixelMap:async()=>({getImageInfo:async()=>({size:{width:100,height:200}}),release:async()=>{}}),release:async()=>{}})},
    parseComicList:(items,k)=>Array.isArray(items)?items.map(x=>({id:x.id||'',title:x.title||'',cover:x.cover||'',sourceKey:k})):[],
    ComicSource:{sources:{fixture:{key:'fixture',name:'Fixture',version:'1.0.0',settings:{},explore:[
      {type:'singlePageWithMultiPart',load:async()=>({'one':[make('one')],'two':brokenPart?[]:[make('two')]})}
    ]}}},
    Math:Object.assign(Object.create(Math),{random:()=>0})
  });
  context.JsEngine={callJson:async code=>await vm.runInContext(code,context)};
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/source/SourceAcceptance.ets'),{mode:'transform'})+'\nglobalThis.Runner=SourceAcceptance;',context);
  return {context,Runner:context.Runner,source,requests,reports,screen,files};
}
let count=0;
async function test(name,body){await body();count++;fs.appendFileSync(log,`[响应返回] TraceID=deep-tests PASS ${name}\n`)}
(async()=>{
  await test('matrix samples all groups and first/middle/last images',async()=>{
    const e=environment();await e.Runner.run();
    assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
    assert.ok(e.requests[0].thumbnail);
    const eps=new Set(e.requests.filter(x=>!x.thumbnail).map(x=>x.ep));
    assert.ok(eps.has('0')&&eps.has('4')&&eps.has('1')&&eps.has('2')&&eps.has('3'));
    for(const ep of eps){
      const urls=e.requests.filter(x=>x.ep===ep&&!x.thumbnail).map(x=>x.url);
      assert.deepEqual(urls,[`image-${ep}-0`,`image-${ep}-3`,`image-${ep}-5`]);
    }
  });
  await test('shared L0 gaps and untested login cannot be promoted to PASS',async()=>{
    const e=environment();const rows=await e.Runner.run();
    assert.equal(e.Runner.rows[0].l0,'PARTIAL_COMMON_CONTRACTS');
    assert.equal(e.Runner.rows[0].l4,'NOT_TESTED_REAL_LOGIN');
    assert.ok(!rows.some(r=>r.includes(' | PASS | ')));
    assert.deepEqual(e.screen,[true,false]);
  });
  await test('one empty explore part remains failed even when chain succeeds',async()=>{
    const e=environment({brokenPart:true});await e.Runner.run();
    assert.equal(e.Runner.rows[0].explore,'FAIL_OR_UNSUPPORTED_TYPE');
    assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
  });
  await test('part loaders receive zero arguments, not one undefined argument',async()=>{
    const e=environment();
    e.context.ComicSource.sources.fixture.explore[0].load=async function(){
      assert.equal(arguments.length,0);return {part:[{id:'c',title:'t',cover:'u'}]};
    };
    await e.Runner.run();
    assert.match(e.Runner.rows[0].explore,/SAMPLED_PAGES_PARTS/);
  });
  await test('cover failure does not skip chapter/image samples',async()=>{
    const e=environment({failCover:true});await e.Runner.run();
    assert.equal(e.Runner.rows[0].l3,'FAIL_IMAGES_OR_CHAPTERS');
    assert.ok(e.requests.length>10);
    assert.equal(e.Runner.rows[0].classification,'HTTP_FAILURE_OBSERVED',
      '403 is observed HTTP failure requiring attribution, never proof of a source/site exemption');
  });
  await test('unsupported required image transform is application gap',async()=>{
    const e=environment({unsupported:true});await e.Runner.run();
    assert.equal(e.Runner.rows[0].classification,'A_APPLICATION_IMAGE_GAP');
    assert.equal(e.Runner.rows[0].l3,'FAIL_APPLICATION_IMAGE_GAP');
  });
  await test('metadata failure prevents higher stages',async()=>{
    const e=environment();e.context.ComicSource.sources.fixture.key='different';
    await e.Runner.run();assert.equal(e.Runner.rows[0].l1,'FAIL_METADATA');assert.equal(e.requests.length,0);
  });
  await test('every installed but unregistered source gets a failure row',async()=>{
    const e=environment();e.context.SourceDao.list=async()=>[{key:'missing'}];
    await e.Runner.run();assert.equal(e.Runner.rows.length,1);assert.equal(e.Runner.rows[0].l1,'FAIL_REGISTRATION');
  });
  await test('same second search page is rejected',async()=>{
    const e=environment();e.source.search.loadPage=async()=>({error:false,dataOrNull:[{id:'same',title:'T',cover:'C'}]});
    await e.Runner.run();assert.equal(e.Runner.rows[0].search,'FAIL_OR_NEEDS_CONFIGURATION');
    assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK_SEARCH_NOT_PASSED','a valid public candidate still exercises downstream without hiding search failure');
  });
  await test('one keyword request failure is not hidden by another successful keyword or reading chain',async()=>{
    const e=environment(),original=e.source.search.loadPage;
    e.source.search.loadPage=async(k,p,o)=>{if(k==='魔法')return {error:true,errorMessage:'HTTP 403'};return original(k,p,o)};
    await e.Runner.run();assert.equal(e.Runner.rows[0].search,'PARTIAL_KEYWORD_REQUEST_FAILURE');
    assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');assert.equal(e.Runner.rows[0].classification,'HTTP_FAILURE_OBSERVED');
  });
  await test('finite maxPage1 search does not invent a second page or blame one-shot source',async()=>{
    const e=environment(),calls=[];
    e.source.search.loadPage=async(k,page)=>{calls.push([k,page]);if(page!==1)throw Error('nonexistent page requested');
      return {error:false,dataOrNull:[{id:'finite',title:'T',cover:'C'}],subData:1,get subDataString(){return '1'}}};
    await e.Runner.run();assert.deepEqual(calls,[['a',1],['魔法',1]]);
    assert.equal(e.Runner.rows[0].search,'TWO_KEYWORDS_SAMPLED_ONE_PASSED');assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
    assert.match([...e.files.values()].join(''),/declaredEnd=true/);
  });
  await test('cursor ending after first valid page is finite, not a missing-cursor migration failure',async()=>{
    const e=environment();let second=0;
    e.source.search={cursorOnly:true,loadPage:async()=>({error:false,dataOrNull:[{id:'finite',title:'T',cover:'C'}]}),
      loadNext:async()=>{second++;throw Error('must not ask ended cursor')}};
    await e.Runner.run();assert.equal(second,0);assert.equal(e.Runner.rows[0].search,'TWO_KEYWORDS_SAMPLED_ONE_PASSED');
  });
  await test('category invokes options and target loaders with preserved routing',async()=>{
    const e=environment(),calls=[];
    const option=(entries,extra={})=>({options:new Map(entries),notShowWhen:[],...extra});
    e.source.loadCategoryData=async()=>({parts:[{title:'Options',items:[
      {label:'Default',page:'category',attributes:new Map([['category','a'],['param','exact-param']]),initialOptions:[]},
      {label:'Explicit',page:'category',attributes:new Map([['category','a']]),initialOptions:['popular']}
    ]}]});
    e.source.categoryComics.optionsLoader=async(category,param)=>{
      calls.push(['options',category,param]);return {error:false,dataOrNull:[
        option([['hidden','Hidden']],{notShowWhen:['a']}),
        option([['other','Other']],{showWhen:['other-category']}),
        option([['latest','Latest'],['popular','Popular']],{showWhen:['a']})]};
    };
    e.source.categoryComics.load=async(category,param,options,page)=>{
      calls.push(['load',category,param,Array.from(options),page]);return {error:false,dataOrNull:[{id:'c',title:'T',cover:'C'}]};
    };
    await e.Runner.run();
    assert.deepEqual(calls,[['options','a','exact-param'],['load','a','exact-param',['latest'],1],
      ['options','a',undefined],['load','a',undefined,['popular'],1]]);
    assert.equal(e.Runner.rows[0].category,'PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE');
  });
  await test('category target failure preserves later item/part search and chain evidence',async()=>{
    const e=environment(),calls=[],searches=[];
    const target=category=>({label:category,page:'category',attributes:new Map([['category',category]])});
    e.source.loadCategoryData=async()=>({parts:[{title:'First',items:[target('bad'),target('later-item')]},
      {title:'Second',items:[target('later-part')]}]});
    const search=e.source.search.loadPage;e.source.search.loadPage=async(k,p,o)=>{searches.push([k,p]);return search(k,p,o);};
    e.source.categoryComics.load=async category=>{
      calls.push(category);if(category==='bad')throw Error('synthetic opaque category fault');
      return {error:false,dataOrNull:[{id:category,title:'T',cover:'C'}]};
    };
    await e.Runner.run();
    assert.deepEqual(calls,['bad','later-item','later-part']);
    assert.deepEqual(searches,[['a',1],['a',2],['魔法',1],['魔法',2]]);
    assert.match(e.Runner.rows[0].category,/^FAIL/);assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
    assert.equal(e.Runner.rows[0].classification,'UNDETERMINED','a healthy chain cannot erase an unknown category failure');
    const text=[...e.files.values()].join('');
    assert.match(text,/synthetic opaque category fault/);assert.match(text,/part=Second sampled=1 executable=1/);
  });
  await test('category option failure is isolated and identifies pre-target phase',async()=>{
    const e=environment(),loads=[];
    e.source.loadCategoryData=async()=>({parts:[{title:'One',items:['bad','good'].map(category=>
      ({label:category,page:'category',attributes:new Map([['category',category]])}))}]});
    e.source.categoryComics.optionsLoader=async category=>category==='bad'
      ?{error:true,errorMessage:'synthetic option fault'}:{error:false,dataOrNull:[]};
    e.source.categoryComics.load=async category=>{loads.push(category);return {error:false,dataOrNull:[{id:'c',title:'T',cover:'C'}]};};
    await e.Runner.run();assert.deepEqual(loads,['good']);assert.match(e.Runner.rows[0].category,/^FAIL/);
    const text=[...e.files.values()].join('');assert.match(text,/phase=options/);assert.match(text,/synthetic option fault/);
  });
  await test('unknown category and source errors are not automatic application or site exemptions',async()=>{
    for(const message of ['undefined is not callable','TypeError: not a function','synthetic opaque fault',
      'record 4012 failed','TypeError: cannot read property network of undefined']){
      const e=environment();e.source.categoryComics.load=async()=>{throw Error(message)};
      await e.Runner.run();assert.match(e.Runner.rows[0].category,/^FAIL/);
      assert.equal(e.Runner.rows[0].classification,'UNDETERMINED',message);
    }
  });
  await test('SDK parameter code 401 is not promoted to an HTTP auth/site exemption',async()=>{
    const e=environment();e.source.categoryComics.load=async()=>{throw Error('SDK code 401: invalid parameter')};
    await e.Runner.run();assert.match(e.Runner.rows[0].category,/^FAIL/);
    assert.equal(e.Runner.rows[0].classification,'TRANSPORT_OR_SDK_ERROR_OBSERVED');
    assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
  });
  await test('landing failure leaves search and independent reading chain sampled',async()=>{
    const e=environment();e.source.loadCategoryData=async()=>{throw Error('synthetic landing fault')};
    await e.Runner.run();assert.match(e.Runner.rows[0].category,/^FAIL/);
    assert.equal(e.Runner.rows[0].search,'TWO_KEYWORDS_SAMPLED_ONE_PASSED');assert.equal(e.Runner.rows[0].l3,'SAMPLE_CHAIN_OK');
    assert.equal(e.Runner.rows[0].classification,'UNDETERMINED');
    assert.match([...e.files.values()].join(''),/phase=landing/);
  });
  await test('row evidence is actually appended to file',async()=>{
    const e=environment();await e.Runner.run();
    const text=[...e.files.values()].join('');
    assert.ok(text.includes('"stage":"ROW"')&&text.includes('"stage":"L3_IMAGE"')&&text.includes('"stage":"END"'));
  });
  const code=read('entry/src/main/ets/source/ImageRequests.ets');
  const c=vm.createContext({Log:{audit:()=>{}},ImageRequestConfig:class{url='';headers=new Map();unsupported=[];modifyImage=''}});
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Requests=ImageRequests;',c);
  await test('thumbnail hook and page hook remain separate',async()=>{
    const calls=[],source={key:'x',getThumbnailConfig:async u=>{calls.push('thumb');return {url:u+'-thumb',headers:new Map(),unsupported:[],modifyImage:''}},
      getImageConfig:async u=>{calls.push('page');return {url:u+'-page',headers:new Map(),unsupported:[],modifyImage:''}}};
    const thumb=await c.Requests.resolve(source,'u',true,'comic','ep','trace');
    const page=await c.Requests.resolve(source,'u',false,'comic','ep','trace');
    assert.equal(thumb.url,'u-thumb');assert.equal(page.url,'u-page');assert.deepEqual(calls,['thumb','page']);
  });
  await test('hook failure never falls back to an unconfigured download',async()=>{
    await assert.rejects(c.Requests.resolve({key:'x',getThumbnailConfig:async()=>{throw Error('hook failed')}},'u',true,'','', 't'));
  });
  console.log(`PASS ${count} production deep-matrix/image-routing cases (not site/login acceptance).`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
