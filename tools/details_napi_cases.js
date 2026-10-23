'use strict';
// Existing host addon only; FULL UNCHANGED installed scripts + production ArkTS
// adapter/session. In-memory host HTTP fixtures, no sockets/accounts/device/SDK.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/details-napi-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8'),clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const native=require(path.join(root,'logs/napi-host/venerajs.node'));fs.writeFileSync(log,'Production details + existing NAPI + full unchanged installed scripts. In-memory HTTP, synthetic text only. No actual network/accounts/device/SDK evidence.\n');
const requests=[];let rejectNext=false;
const wnHtml=n=>`<div class="pic_box tb"><a><img src="//images.invalid/${n}.jpg"></a></div><div class="f_left paginator"><a class="${n===2?'thispage':''}">2</a></div>`;
const ehHtml=`<div class="gdtm"><div style="width:100px;height:150px;background:transparent url(https://images.invalid/sprite.jpg) -100px 0px"></div></div><table class="ptb"><tbody><tr><td><a href="?p=0">1</a></td></tr></tbody></table><a name="c123"></a><div class="c1"><div class="c3">Posted on 01 January 2026 by <a>Fixture User</a></div><div class="c5"><span>7</span></div><div class="c6">Fixture <b>comment</b></div></div>`;
native.setMessageHandler(m=>{
 if(m.method==='load_setting')return m.setting_key==='domainSelection'?'0':m.setting_key==='domain0'?'fixture.invalid':m.setting_key==='domain'?'e-hentai.org':null;
 if(m.method==='load_data'||m.method==='log')return null;if(m.method==='getPlatform')return 'ohos';
 if(m.method!=='http')throw Error('Unexpected fixture host method '+m.method);
 requests.push(m);if(rejectNext){rejectNext=false;return Promise.resolve({status:503,body:'private fixture failure body',headers:{}})}
 const wn=m.url.match(/^https:\/\/fixture\.invalid\/photos-index-page-(\d+)-aid-42\.html$/);if(wn)return Promise.resolve({status:200,body:wnHtml(Number(wn[1])),headers:{}});
 if(m.url==='https://e-hentai.org/g/42/fixture/'||m.url==='https://e-hentai.org/g/42/fixture/?hc=1')return Promise.resolve({status:200,body:ehHtml,headers:{}});
 if(m.url==='https://komiic.com/api/query'){
  assert.equal(m.http_method,'POST');const p=typeof m.data==='string'?JSON.parse(m.data):m.data;
  const name=p.operationName;assert.ok(['getMessagesByComicId','messageChan','addMessageToComic'].includes(name));
  if(name==='addMessageToComic'){assert.equal(p.variables.message,'Synthetic fixture comment');assert.equal(p.variables.replyToId,'reply-parent');return Promise.resolve({status:200,body:JSON.stringify({data:{addMessageToComic:{id:'new'}}}),headers:{}})}
  if(name==='getMessagesByComicId'){assert.equal(p.variables.comicId,'book');assert.ok([0,100].includes(p.variables.pagination.offset))}else assert.equal(p.variables.messageId,'reply-parent');
  const rows=name==='getMessagesByComicId'&&p.variables.pagination.offset===100?[]:[{id:name==='messageChan'?'reply':'comment',account:{nickname:'Fixture',profileImageUrl:'https://images.invalid/avatar.jpg'},message:'Synthetic content',dateUpdated:'2026-01-01'}];
  return Promise.resolve({status:200,body:JSON.stringify({data:{[name]:rows}}),headers:{}});
 }
 throw Error('Unexpected request denied; no real network fallback');
});
native.setGlobalString('appVersion','1.17.0');for(const f of ['init.js','sendmessage_shim.js','html_engine.js'])native.evaluate(read('entry/src/main/resources/rawfile/'+f),'<'+f+'>');
for(const [f,cls,key]of [['wnacg','Wnacg','wnacg'],['ehentai','Ehentai','ehentai'],['Komiic','Komiic','Komiic']])native.evaluate(read('logs/user8-installed-scripts/'+f+'.js')+`\nComicSource.sources[${JSON.stringify(key)}]=new ${cls}();`,'<unchanged-installed-'+f+'>');
const ctx=vm.createContext({Error,JsEngine:{callJson:(c,p,t)=>native.callJson(c,p,t)},Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}});
vm.runInContext(stripTypeScriptTypes(['foundation/Extensions','model/Comic','model/Res','features/SourceFailure','source/DetailsCapabilities','source/JsDetailsAdapter','features/DetailsMedia','features/DetailsComments'].map(p=>clean('entry/src/main/ets/'+p+'.ets')).join('\n'),{mode:'transform'})+'\nglobalThis.T={JsDetailsAdapter,DetailsMedia,DetailsComments};',ctx);
const {JsDetailsAdapter:A,DetailsMedia:M,DetailsComments:C}=ctx.T;
const source=(key,flags)=>{const d=A.create(key,'<installed-details-fixture>',flags);return {key,detailsMedia:d,loadComicComments:d.loadComments,loadChapterComments:d.loadChapterComments}};
let count=0;async function test(name,run){await run();count++;fs.appendFileSync(log,'PASS '+name+'\n')}
(async()=>{
 await test('unchanged WN thumbnails real HTML + opaque numeric-string next + terminal cursor',async()=>{
  const m=new M();m.start('42',[],source('wnacg',{loadThumbnails:true}).detailsMedia);await m.more();assert.equal(m.error,'');assert.equal(m.images[0],'https://images.invalid/1.jpg');assert.equal(m.ended,false);await m.more();assert.equal(m.images[1],'https://images.invalid/2.jpg');assert.equal(m.ended,true);assert.equal(requests[0].url,'https://fixture.invalid/photos-index-page-1-aid-42.html');assert.equal(requests[1].url,'https://fixture.invalid/photos-index-page-2-aid-42.html');assert.ok(requests.every(r=>!r.url.includes('photos-gallery')));
 });
 await test('unchanged WN callback failure keeps loaded previews and retries same cursor',async()=>{
  const m=new M();m.start('42',['static'],source('wnacg',{loadThumbnails:true}).detailsMedia);await m.more();rejectNext=true;await m.more();assert.equal(m.images.length,2);assert.ok(m.error);await m.more();assert.equal(m.images.length,3);assert.equal(m.ended,true);assert.equal(requests.at(-1).url,requests.at(-2).url);
 });
 await test('unchanged EH sprite thumbnail syntax and real comments model parsed via HTML bridge',async()=>{
  const s=source('ehentai',{loadThumbnails:true,loadComments:true}),thumb=await s.detailsMedia.loadComicThumbnail('https://e-hentai.org/g/42/fixture/',null);assert.equal(thumb.error,false);assert.equal(thumb.data[0],'https://images.invalid/sprite.jpg@x=100-200&y=0-150');
  const c=new C();c.start(s,{sourceKey:'ehentai',comicId:'https://e-hentai.org/g/42/fixture/',title:'Fixture'});await c.more();assert.equal(c.error,'');assert.equal(c.rows[0].id,'123');assert.equal(c.rows[0].score,7);assert.equal(c.rows[0].userName,'Fixture User');assert.match(c.rows[0].content,/<b>comment<\/b>/);assert.equal(c.ended,true);
 });
 await test('unchanged Komiic GraphQL comments offset and replies contract, no writes on reads',async()=>{
  const s=source('Komiic',{loadComments:true,sendComment:true}),c=new C();c.start(s,{sourceKey:'Komiic',comicId:'book',title:'Fixture'});await c.more();assert.equal(c.error,'');assert.equal(c.rows[0].id,'comment');assert.equal(c.rows[0].replyCount,0);await c.more();assert.equal(c.ended,true);
  c.start(s,{sourceKey:'Komiic',comicId:'book',title:'Fixture',replyTo:'reply-parent'});await c.more();assert.equal(c.rows[0].id,'reply');assert.ok(requests.filter(r=>r.url.includes('komiic')).every(r=>!String(r.data).includes('addMessageToComic')));
 });
 await test('explicit synthetic send through unchanged Komiic callback; no credentials or real account',async()=>{
  const s=source('Komiic',{loadComments:true,sendComment:true}),c=new C();c.start(s,{sourceKey:'Komiic',comicId:'book',title:'Fixture',replyTo:'reply-parent'});await c.more();const before=requests.length;assert.equal(await c.send('Synthetic fixture comment'),true);assert.equal(requests.length,before+2);assert.equal(c.rows[0].id,'reply');assert.equal(c.writing,false);
 });
 await test('actual QuickJS chapter/send/like/vote positional contract synthetic declared source',async()=>{
  native.evaluate(`ComicSource.sources.details_fixture={comic:{loadChapterComments:async(id,ep,page,reply)=>{if(id!=='book'||ep!=='ep'||page!==1||reply!==null)throw Error('bad chapter arguments');return {comments:[{id:'c',content:'fixture',score:2}],maxPage:1}},sendChapterComment:async(id,ep,body,reply)=>{if(id!=='book'||ep!=='ep'||body!=='fixture'||reply!==null)throw Error('bad send args')},likeComment:async(id,sub,c,like)=>{if(id!=='book'||sub!==null||c!=='c'||like!==true)throw Error('bad like');return 4},voteComment:async(id,sub,c,up,cancel)=>{if(id!=='book'||sub!==null||c!=='c'||up!==false||cancel!==true)throw Error('bad vote');return 8}}};`,'<synthetic-contract>');
  const d=A.create('details_fixture','<synthetic>',{loadChapterComments:true,sendChapterComment:true,likeComment:true,voteComment:true});assert.equal((await d.loadChapterComments('book','ep',1,undefined)).data[0].id,'c');assert.equal((await d.sendChapterComment('book','ep','fixture',undefined)).data,true);assert.equal((await d.likeComment('book',undefined,'c',true)).data,4);assert.equal((await d.voteComment('book',undefined,'c',false,true)).data,8);
 });
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/private fixture failure body|Synthetic fixture comment/);console.log(`PASS ${count} production details / actual existing NAPI / full unchanged installed-script cases; ${requests.length} controlled HTTP requests, zero real network.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
