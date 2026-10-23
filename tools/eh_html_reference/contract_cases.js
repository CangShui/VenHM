'use strict';
// Actual pre-existing production Node NAPI + QuickJS + raw production HtmlDocument.
// Full installed source evaluated unchanged. No source/HTML/native/adapter edits.
// ONLY synthetic responses or explicitly supplied local fixture; never HTTP.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto'),vm=require('node:vm');
const root=path.resolve(__dirname,'../..'),spec=JSON.parse(fs.readFileSync(path.join(__dirname,'probe_spec.json'),'utf8'));
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const source=read(spec.source),sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));
const captures=[],reports=[],fixtures=[];let response={status:200,body:'<html></html>'},intercept=false;
const allowed=new Set(spec.publicInitialRequests.map(r=>r.url));
function validate(url){const u=new URL(url);if(u.protocol!=='https:'||u.hostname!=='e-hentai.org'||u.username||u.password||u.port||u.hash||!allowed.has(url))throw Error('REFUSED_NONPUBLIC_REQUEST');}
native.setMessageHandler(message=>{
  if(message.method==='load_setting')return spec.settings[message.setting_key]??null;
  if(message.method==='isLogged')return false;
  if(message.method==='log'||message.method==='UI')return null;
  if(message.method==='getPlatform')return 'ohos';
  if(message.method==='http'){
    validate(message.url);
    const headers=message.headers instanceof Map?Object.fromEntries(message.headers):message.headers||{};
    assert.equal(Object.keys(headers).length,0,'source list call must have no explicit headers');
    assert.equal(message.http_method,'GET');
    // Only exact safe public URLs get stored. Never stringify message/headers/data.
    captures.push({url:message.url,method:message.http_method,sourceHeadersEmpty:true});
    if(intercept)return Promise.reject(Error('OFFLINE_CAPTURE_ONLY_BEFORE_HTTP'));
    return Promise.resolve({...response,headers:{}});
  }
  throw Error('Unexpected offline host method '+message.method);
});
native.setGlobalString('appVersion','1.17.0');
for(const p of ['init.js','sendmessage_shim.js','html_engine.js'])native.evaluate(read('entry/src/main/resources/rawfile/'+p),'<production-'+p+'>');
native.evaluate(source+'\nglobalThis.fixtureSource=new Ehentai();','<installed-ehentai-unchanged>');
native.evaluate('globalThis.probeSpec='+JSON.stringify(spec)+';globalThis.safeCountQuery='+spec.safeCountQuery+';','<probe>');
const run=code=>native.callJson(code,'<eh-offline-contract>','eh-offline-contract');
const inject=html=>native.setGlobalString('fixtureHtml',html);
const doc=content=>'<!DOCTYPE html><html><head><title>Controlled synthetic EH shape</title></head><body>'+content+'<a id="dnext" href="/?synthetic=next">Next</a></body></html>';
const img='<img src="https://fixture.invalid/cover.jpg">';
const rate='<div class="ir" style="background-position:0px -1px;"></div>';
const date='2026-01-02 03:04';
function compact(rank=false){return '<table class="itg gltc"><tbody><tr>'+(rank?'<td>1</td>':'')+'<td><div class="cs">Manga</div></td><td><div></div><div><a>'+img+'</a></div><div><div>'+date+'</div>'+rate+'</div></td><td><a href="https://fixture.invalid/item/1"><div class="glink">Fixture &amp; title</div><div><div title="language:english">EN</div><div title="female:synthetic">Tag</div></div></a></td><td><div><a>Uploader</a></div><div>12 pages</div></td></tr></tbody></table>';}
const thumb='<div class="gl1t"><a href="https://fixture.invalid/item/1">Fixture &amp; title</a>'+img+'<div class="gl5t"><div><div class="cs">Manga</div><div>'+date+'</div>'+rate+'<div>12 pages</div></div></div></div>';
const extended='<table class="itg glte"><tbody><tr><td class="gl1e"><div><a href="https://fixture.invalid/item/1">'+img+'</a></div></td><td class="gl2e"><div><a><div><div class="glink">Fixture &amp; title</div></div></a><div class="gl3e"><div class="cn">Manga</div><div>'+date+'</div><div><a>Uploader</a></div>'+rate+'<div>12 pages</div></div><div class="gt" title="language:english">EN</div><div class="gtl" title="female:synthetic">Tag</div></div></td></tr></tbody></table>';
const minimal='<table class="itg gltm"><tbody><tr><td class="gl1m"><div class="cs">Manga</div></td><td class="gl2m"><div>'+date+'</div><div><div>'+img+'</div></div></td><td class="gl3m"><a href="https://fixture.invalid/item/1"><div class="glink">Fixture &amp; title</div></a></td><td class="gl4m">'+rate+'</td><td class="gl5m"><div><a>Uploader</a></div></td></tr></tbody></table>';
async function test(name,html,expected,leader=false,fields){
  response={status:200,body:html};inject(html);
  const result=await run('fixtureSource.getGalleries("https://e-hentai.org",'+leader+')');
  assert.equal(result.comics.length,expected,name);
  if(fields)for(const [k,v]of Object.entries(fields))assert.deepEqual(result.comics[0][k],v,name+' '+k);
  const probe=await run('safeCountQuery(fixtureHtml,probeSpec)');
  // Console/report contains field validity only, not IDs, links or content.
  reports.push({name,fixtureClass:'SYNTHETIC_NOT_CAPTURED_SITE_HTML',expected,items:result.comics.length,nextPresent:!!result.next,fieldTypes:result.comics[0]?Object.fromEntries(Object.entries(result.comics[0]).map(([k,v])=>[k,v===null?'null':Array.isArray(v)?'array':typeof v])):{},probe});
  fixtures.push({name,html,counts:probe.counts});
  console.log('PASS '+name+' items='+result.comics.length);
}
(async()=>{
  const parser=source.slice(source.indexOf('async getGalleries('),source.indexOf('// explore page list'));
  const actual=[...new Set([...parser.matchAll(/querySelector(?:All)?\(\s*(["'])(.*?)\1/g)].map(m=>m[2]))];
  assert.deepEqual(actual,spec.selectors,'capture spec enumerates EVERY selector in list parser');
  // Prove request builder itself; host refuses before any HTTP implementation.
  intercept=true;
  const calls=['fixtureSource.explore[0].loadNext(null)','fixtureSource.explore[1].loadNext(null)',...['a','魔法'].map(k=>'fixtureSource.search.loadNext('+JSON.stringify(k)+','+JSON.stringify(spec.defaultOptions)+',null)')];
  for(const call of calls)await assert.rejects(run(call),/OFFLINE_CAPTURE_ONLY_BEFORE_HTTP/);
  assert.deepEqual(captures.map(c=>c.url),spec.publicInitialRequests.map(r=>r.url));
  intercept=false;
  const watchedBefore=captures.length;
  // UI.showMessage method shape is supplied by real init; host can be called.
  const watched=await run('fixtureSource.explore[2].loadNext(null)');
  assert.equal(watched.comics.length,0);assert.equal(captures.length,watchedBefore);
  await test('compact-valid',doc(compact()),1,false,{title:'Fixture & title',cover:'https://fixture.invalid/cover.jpg',stars:5,maxPage:12,language:'english',tags:['female:synthetic']});
  await test('compact-leaderboard-offset',doc(compact(true)),1,true,{title:'Fixture & title'});
  await test('compact-data-src',doc(compact().replace(img,'<img src="data:image/gif;base64,synthetic" data-src="https://fixture.invalid/lazy.jpg">')),1,false,{cover:'https://fixture.invalid/lazy.jpg'});
  await test('thumbnail-valid',doc(thumb),1,false,{title:'Fixture & title',stars:5,maxPage:12});
  await test('extended-valid',doc(extended),1,false,{title:'Fixture & title',stars:5,maxPage:12,language:'english',tags:['language:english','female:synthetic']});
  await test('minimal-valid',doc(minimal),1,false,{title:'Fixture & title',stars:5});
  await test('minimal-data-src',doc(minimal.replace(img,'<img src="data:image/gif;base64,synthetic" data-src="https://fixture.invalid/lazy.jpg">')),1,false,{cover:'https://fixture.invalid/lazy.jpg'});
  await test('all-four-modes',doc(compact()+thumb+extended+minimal),4);
  for(const [name,html]of [['compact',compact()],['extended',extended],['minimal',minimal]])await test(name+'-no-explicit-tbody',doc(html.replace('<tbody>','').replace('</tbody>','')),0);
  await test('compact-required-tag-container-missing',doc(compact().replace('<div><div title="language:english">EN</div><div title="female:synthetic">Tag</div></div>','')),0);
  await test('minimal-missing-image',doc(minimal.replace(img,'')),0);
  // Keep nonempty rating style: an EMPTY style hangs the unchanged source helper.
  await test('thumbnail-other-fields-missing-with-style',doc('<div class="gl1t"><div class="gl5t"><div>'+rate+'</div></div></div>'),1,false,{title:'Unknown',cover:''});
  await test('extended-other-fields-missing-with-style',doc('<table class="itg glte"><tbody><tr><td class="gl2e"><div><div class="gl3e">'+rate+'</div></div></td></tr></tbody></table>'),1,false,{title:'Unknown',cover:''});
  const isolated=vm.createContext({ComicSource:class {}});
  vm.runInContext(source+';globalThis.isolatedSource=new Ehentai()',isolated,{timeout:1000});
  assert.throws(()=>vm.runInContext('isolatedSource.getStarsFromPosition("")',isolated,{timeout:25}),/Script execution timed out/);
  const emptyStyleLoop='PROVEN unchanged helper on empty string exceeds 25ms VM watchdog; not exercised unbounded in NAPI';
  reports.push({name:'empty-style-source-loop',fixtureClass:'BOUNDED_NODE_VM_FULL_SOURCE_NOT_NAPI',evidence:emptyStyleLoop});
  await test('unrecognized-mode-roots',doc('<table class="itg gltx"><tbody><tr><td>Fixture</td></tr></tbody></table>'),0);
  await test('200-html-without-any-list',doc('<main>Controlled no-list document</main>'),0);
  await test('compact-whitespace-comments',doc(compact().replace(/></g,'> \n<!-- synthetic comment --> <')),1,false,{title:'Fixture & title'});
  inject('<div id="model"> text <!--comment--><span>A</span><b>B</b></div>');
  const model=await run('(()=>{const d=new HtmlDocument(fixtureHtml);const e=d.querySelector("#model");const r={children:e.children.map(c=>c.localName),nodeTypes:e.nodes.map(n=>n.type),arrayFind:typeof e.children.find,attrsType:typeof e.attributes,textType:typeof e.text,dateFinite:!isNaN(Date.parse('+JSON.stringify(date)+'))};d.dispose();return r;})()');
  assert.deepEqual(model.children,['span','b']);assert.deepEqual(model.nodeTypes,['text','comment','element','element']);assert.equal(model.arrayFind,'function');assert.equal(model.attrsType,'object');assert.equal(model.textType,'string');assert.equal(model.dateFinite,true);
  const guards=[];
  for(const [name,status,body,pattern] of [['non-200',403,'<html></html>',/Invalid status code: 403/],['leading-whitespace',200,' \n<html></html>',/Failed to load page/],['text-only',200,'controlled plain text',/Failed to load page/]]){response={status,body};await assert.rejects(run('fixtureSource.getGalleries("https://e-hentai.org",false)'),pattern);guards.push(name);}
  // Optional local captured page; never prints title, HTML, IDs, next or hrefs.
  if(process.argv[2]){
    const file=path.resolve(process.argv[2]),html=fs.readFileSync(file,'utf8');response={status:200,body:html};inject(html);
    // Main production NAPI is synchronous: reject dangerous unknown styles BEFORE
    // calling unchanged source. Node timers cannot interrupt that native loop.
    const unsafeStyles=await run(`(()=>{const d=new HtmlDocument(fixtureHtml);let n=0;try{for(const [root,style] of [["div.gl1t","div.gl5t > div > div.ir"],["table.itg.glte > tbody > tr","td.gl2e > div > div.gl3e > div.ir"],["table.itg.gltm > tbody > tr","td.gl4m > div.ir"]])for(const e of d.querySelectorAll(root))if(!(e.querySelector(style)?.attributes.style??""))n++;for(const e of d.querySelectorAll("table.itg.gltc > tbody > tr")){try{if(e.children[1].children[2].children[1].attributes.style==="")n++;}catch(_){}}return n;}finally{d.dispose();}})()`);
    assert.equal(unsafeStyles,0,'REFUSED source replay: matched rows may hit unchanged empty-style infinite loop; use structural probe only');
    const result=await run('fixtureSource.getGalleries("https://e-hentai.org",false)');
    const probe=await run('safeCountQuery(fixtureHtml,probeSpec)');
    reports.push({name:'local-capture',fixtureClass:'USER_SUPPLIED_LOCAL_CAPTURE_PROVENANCE_NOT_ASSUMED',htmlSha256:sha(html),items:result.comics.length,nextPresent:!!result.next,probe});
    fixtures.push({name:'local-capture',html,counts:probe.counts});
    console.log('LOCAL_CAPTURE items='+result.comics.length+'; no site/auth inference');
  }
  const summary={sourceVersion:'1.2.0',sourceSha256:sha(source),sourceUnchanged:true,engine:'actual existing Node NAPI / QuickJS + production init.js, sendmessage_shim.js, html_engine.js',sourceHeaders:{},initialRequests:captures.slice(0,4),networkCalls:0,fixtureCases:reports.length,guards,model,reports};
  fs.writeFileSync(path.join(__dirname,'results.json'),JSON.stringify(summary,null,2)+'\n');
  // Local input bodies only; this file MUST NOT be printed by consumer tools.
  fs.writeFileSync(path.join(__dirname,'oracle_input.json'),JSON.stringify(fixtures)+'\n');
  console.log('EH_OFFLINE_CONTRACT_PASS cases='+reports.length+' guards='+guards.length+' networkCalls=0; NOT device/site/auth proof');
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
// Production addon owns loop handles; terminate only this standalone test.
// Teardown path itself is separately covered by tools/napi_host_cases.js.
setTimeout(()=>{console.error('EH_OFFLINE_CONTRACT_TIMEOUT');process.exit(1);},20000).unref();
