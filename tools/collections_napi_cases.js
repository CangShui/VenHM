'use strict';
// Existing NAPI/QuickJS addon, FULL UNCHANGED installed source scripts and production adapter/session.
// All HTTP intercepted in-memory; fixture-only account marker, no login, no sockets, no C++ rebuild.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/collections-napi-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8'),clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));fs.writeFileSync(log,'Production favorites adapter/session + actual existing host NAPI and full unchanged installed WN/Komiic/EH scripts. In-memory HTTP fixtures only, no real accounts/network/device/SDK.\n');
const requests=[],sources=new Map();let failNext=false;
const wnHtml=id=>`<div class="asTB"><div class="asTBcell thumb"><div><img src="//fixture.invalid/cover.jpg"></div></div><div class="box_cel u_listcon"><p class="l_catg"><span>創建時間：2026-01-01</span></p><p class="l_title"><a href="/photos-index-aid-${id}.html">Fixture ${id}</a></p><p class="alopt"><a onclick="users-fav_del-id-${id+1000}.html">Delete</a></p></div></div><div class="f_left paginator"><a>1</a><a>2</a></div>`;
const ehHtml=(id,next)=>`<div class="fp"><span>1</span><span>x</span><span>Fixture folder</span></div><div class="gl1t"><a href="https://e-hentai.org/g/${id}/fixture/">EH fixture ${id}</a><img src="https://fixture.invalid/cover.jpg"><div class="gl5t"><div><div class="cs">Manga</div><div>2026-01-01</div><div class="ir" style="background-position:0px -1px"></div><div>20 pages</div></div></div></div>${next?'<a id="dnext" href="https://e-hentai.org/favorites.php?next=opaque-private">Next</a>':''}`;
native.setMessageHandler(message=>{
 if(message.method==='load_setting')return message.setting_key==='domainSelection'?'0':message.setting_key==='domain0'?'fixture.invalid':message.setting_key==='domain'?'e-hentai.org':null;
 if(message.method==='load_data')return null;if(message.method==='getPlatform')return 'ohos';if(message.method==='log')return null;
 // The real app provides these host helpers; the unchanged WN deletion path uses
 // a random nonce, so a fixture missing them would fail for the wrong reason.
 if(message.method==='random'||message.method==='randomInt')return 0;
 if(message.method==='isLogged')return true;
 if(message.method!=='http')throw Error('Unexpected fixture host method '+message.method);
 requests.push(message);if(failNext){failNext=false;return Promise.resolve({status:503,body:'private-response',headers:{}})}
 const response=body=>Promise.resolve({status:200,body:typeof body==='string'?body:JSON.stringify(body),headers:{}});
 if(message.url==='https://fixture.invalid/users-addfav-id-210814.html')return response('<select><option value="">Choose</option><option value="f">Fixture folder</option></select>');
 if(/^https:\/\/fixture\.invalid\/users-users_fav-page-[12]-c-f\.html\.html$/.test(message.url))return response(wnHtml(message.url.includes('page-1')?101:102));
 if(message.url==='https://fixture.invalid/users-save_fav-id-101.html'){assert.equal(message.http_method,'POST');assert.equal(message.data,'favc_id=f');return response('ok')}
 if(/^https:\/\/fixture\.invalid\/users-fav_del-id-1101\.html\?ajax=true&_t=/.test(message.url))return response('ok');
 if(message.url==='https://komiic.com/api/query'){
  const body=typeof message.data==='string'?JSON.parse(message.data):message.data;assert.equal(message.http_method,'POST');
  switch(body.operationName){
   case 'myFolder':return response({data:{folders:[{id:'folder',name:'Fixture'}]}});
   case 'comicInAccountFolders':assert.equal(body.variables.comicId,'c1');return response({data:{comicInAccountFolders:['folder']}});
   case 'folderComicIds':assert.equal(body.variables.folderId,'folder');return response({data:{folderComicIds:{comicIds:body.variables.pagination.offset===0?['c1']:[]}}});
   case 'comicByIds':return response({data:{comicByIds:[{id:'c1',title:'Komiic fixture',imageUrl:'https://fixture.invalid/k.jpg',authors:[],categories:[],dateUpdated:'2026-01-01T00:00:00Z'}]}});
   case 'addComicToFolder':case 'removeComicToFolder':assert.deepEqual(body.variables,{comicId:'c1',folderId:'folder'});return response({data:{[body.operationName]:true}});
  }
 }
 if(message.url==='https://e-hentai.org/favorites.php')return response(ehHtml(201,true));
 // The unchanged EH source scopes the first page to favcat=0.
 if(message.url==='https://e-hentai.org/favorites.php?favcat=0')return response(ehHtml(201,true));
 if(message.url==='https://e-hentai.org/favorites.php?next=opaque-private')return response(ehHtml(202,false));
 // Reject every unlisted request. Never fall through to a real HTTP client.
 // Include the fixture URL so a missing route is diagnosable (no secrets here).
 throw Error('No fixture for unexpected HTTP: '+(message.url||'')+' ; real network disabled');
});
native.setGlobalString('appVersion','1.17.0');for(const p of ['init.js','sendmessage_shim.js','html_engine.js'])native.evaluate(read('entry/src/main/resources/rawfile/'+p),'<'+p+'>');
for(const [file,cls,key] of [['wnacg','Wnacg','wnacg'],['Komiic','Komiic','Komiic'],['ehentai','Ehentai','ehentai']])native.evaluate(read(`logs/user8-installed-scripts/${file}.js`)+`\nComicSource.sources[${JSON.stringify(key)}]=new ${cls}();`,'<unchanged-favorites-'+file+'>');
const ctx=vm.createContext({Error,Map,Set,Date,Promise,SourceManager:{find:k=>sources.get(k)},JsEngine:{callJson:async(code,file)=>{try{return await native.callJson(code,file,'collections-fixture')}
  catch(error){console.error('JS_CALL_FAIL='+(error instanceof Error?error.message:String(error)));throw error;}}},Log:{info:()=>{},audit:()=>{}}});
vm.runInContext(stripTypeScriptTypes(['entry/src/main/ets/foundation/Extensions.ets','entry/src/main/ets/model/Comic.ets','entry/src/main/ets/model/Res.ets','entry/src/main/ets/source/AuthLogScope.ets','entry/src/main/ets/source/ComicSource.ets','entry/src/main/ets/source/JsFavoritesAdapter.ets','entry/src/main/ets/features/NetworkFavoritesSession.ets'].map(clean).join('\n'),{mode:'transform'})+'\nglobalThis.T={JsFavoritesAdapter,NetworkFavoritesSession};',ctx);
const source=(key,page,next)=>{const s={key,isLogged:true,favoriteData:ctx.T.JsFavoritesAdapter.create(key,'<unchanged-'+key+'>',page,next,true,true,true)};sources.set(key,s);return s};
let count=0;async function test(name,run){await run();count++;fs.appendFileSync(log,'PASS '+name+'\n')}
(async()=>{
 await test('unchanged WN folders/HTML pages favoriteId parsed; exact page+folder contract source locked',async()=>{
  const src=source('wnacg',true,false),s=new ctx.T.NetworkFavoritesSession();await s.start(src);assert.equal(s.error,'');assert.equal(s.folder,'f');assert.equal(s.results[0].favoriteId,'1101');assert.equal(s.results[0].sourceKey,'wnacg');await s.more();assert.equal(s.results[1].id,'102');assert.equal(s.ended,true);
  assert.equal(requests.filter(r=>r.http_method==='POST').length,0);
 });
 await test('unchanged WN declared arity4: missing favId refuses before HTTP; explicit known id safe deletion, add explicit',async()=>{
  assert.equal(await native.callJson('ComicSource.sources.wnacg.favorites.addOrDelFavorite.length','<arity>','fixture'),4);
  const d=sources.get('wnacg').favoriteData,before=requests.length;
  const missing=await d.addOrDelFavorite('101','f',false,undefined);assert.equal(missing.error,true);assert.match(missing.errorMessage,/记录ID/);assert.equal(requests.length,before);
  assert.equal((await d.addOrDelFavorite('101','f',false,'1101')).error,false);assert.match(requests.at(-1).url,/fav_del-id-1101/);
  assert.equal((await d.addOrDelFavorite('101','f',true,undefined)).error,false);assert.equal(requests.at(-1).data,'favc_id=f');
  assert.equal(requests.some(r=>r.url.includes('undefined')),false);
 });
 await test('unchanged Komiic declared arity3: real GraphQL folder membership/pagination and explicit mutation body',async()=>{
  assert.equal(await native.callJson('ComicSource.sources.Komiic.favorites.addOrDelFavorite.length','<arity>','fixture'),3);
  const src=source('Komiic',true,false),d=src.favoriteData;const folders=await d.loadFolders('c1');assert.equal(folders.error,false);assert.equal(folders.data.get('folder'),'Fixture');assert.equal(folders.subData[0],'folder');
  const s=new ctx.T.NetworkFavoritesSession();await s.start(src);assert.equal(s.error,'');assert.equal(s.results[0].id,'c1');await s.more();assert.equal(s.ended,true);
  assert.equal((await d.addOrDelFavorite('c1','folder',true,'ignored-for-arity3')).error,false);assert.equal((await d.addOrDelFavorite('c1','folder',false,undefined)).error,false);
  // The native bridge may hand the body back already parsed, like the handler above.
  const last=requests.at(-1),lastBody=typeof last.data==='string'?JSON.parse(last.data):last.data;
  assert.equal(lastBody.operationName,'removeComicToFolder');
 });
 await test('unchanged EH Map folder bridge and cursor first-null/opaque-next terminate source-locked',async()=>{
  const s=new ctx.T.NetworkFavoritesSession();await s.start(source('ehentai',false,true));assert.equal(s.error,'');assert.equal(s.folder,'0');assert.equal(s.results[0].id,'https://e-hentai.org/g/201/fixture/');assert.equal(s.next,'https://e-hentai.org/favorites.php?next=opaque-private');
  await s.more();assert.equal(s.results.length,2);assert.equal(s.ended,true);assert.equal(s.results[1].sourceKey,'ehentai');
 });
 await test('real NAPI failure retains committed page for same-request retry; account gate no request or fallback',async()=>{
  const src=sources.get('wnacg'),s=new ctx.T.NetworkFavoritesSession();await s.start(src);failNext=true;await s.more();assert.equal(s.page,1);assert.equal(s.results.length,1);assert.ok(s.error);const failed=requests.at(-1).url;await s.more();assert.equal(s.page,2);assert.equal(requests.at(-1).url,failed);
  src.isLogged=false;const before=requests.length;assert.equal((await src.favoriteData.loadComic(1,'f')).error,true);assert.equal((await src.favoriteData.addOrDelFavorite('101','f',true)).error,true);assert.equal(requests.length,before);
  assert.doesNotMatch(fs.readFileSync(log,'utf8'),/private-response|opaque-private|Authorization|Bearer/);
 });
 console.log(`PASS ${count} actual NAPI complete-source favorites fixtures; no live account/network/device acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
