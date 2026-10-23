'use strict';
// Production ArkTS adapters/sessions/page methods transformed by Node. Controlled
// fakes only: no SDK/device/live-site/account acceptance and no external network.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/details-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
fs.writeFileSync(log,'Production details adapter/media/comments/viewer/page methods. No network/device/accounts.\n');
const ctx=vm.createContext({Error,Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}});
ctx.JsEngine={callJson:async code=>vm.runInContext(code,ctx)};
const files=['foundation/Extensions','model/Comic','model/Res','features/SourceFailure','source/DetailsCapabilities','source/JsDetailsAdapter','features/DetailsMedia','features/DetailsComments'];
vm.runInContext(stripTypeScriptTypes(files.map(p=>clean('entry/src/main/ets/'+p+'.ets')).join('\n'),{mode:'transform'})+'\nglobalThis.T={Comment,Res,JsDetailsAdapter,DetailsMedia,DetailsComments,DetailsSharePayload,DetailsImageRegion,DetailsViewerTransform};globalThis.ComicSource={sources:{}};',ctx);
const {Comment,Res,JsDetailsAdapter:A,DetailsMedia:M,DetailsComments:C,DetailsSharePayload:S,DetailsImageRegion:R,DetailsViewerTransform:V}=ctx.T;
const defer=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {resolve,reject,promise}};
const comment=(id='c')=>Object.assign(new Comment(),{id,userName:'Fixture',content:'text',score:5,isLiked:false,voteStatus:0,replyCount:0});
const params=(extra={})=>({sourceKey:'a',comicId:'book',title:'Title',...extra});
function source(data){return {key:'a',detailsMedia:data,loadComicComments:data.loadComments,loadChapterComments:data.loadChapterComments}}
function page(file,name,scope={}){let code=clean('entry/src/main/ets/'+file+'.ets');code=code.slice(0,code.indexOf('  build() {'))+'}';code=code.replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct '+name,'class '+name);const context=vm.createContext({Error,...ctx.T,...scope});vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+`\nglobalThis.P=${name};`,context);return new context.P()}
let count=0;async function test(name,run){await run();count++;fs.appendFileSync(log,'PASS '+name+'\n')}
(async()=>{
 await test('capability factory does not invent methods and exact quoted source/optional null arguments',async()=>{
  const empty=A.create('absent','fixture',{});assert.equal(empty.loadComments,undefined);assert.equal(empty.sendComment,undefined);assert.equal(empty.loadComicThumbnail,undefined);
  const key='a";globalThis.injected=true;//',calls=[];ctx.ComicSource.sources[key]={comic:{loadComments:async(...args)=>{calls.push(args);return {comments:[{id:'1',content:'body',replyCount:0}],maxPage:2}}}};
  const d=A.create(key,'fixture',{loadComments:true});const r=await d.loadComments('b"',undefined,1,undefined);assert.equal(r.error,false);assert.equal(r.data[0].id,'1');assert.equal(r.subData,2);assert.deepEqual(calls,[['b"',null,1,null]]);assert.equal(ctx.injected,undefined);
 });
 await test('thumbnail cursor null/opaque/null and strict envelope validation',async()=>{
  const calls=[];ctx.ComicSource.sources.a={comic:{loadThumbnails:async(id,next)=>{calls.push([id,next]);return {thumbnails:['sprite@x=0-100&y=0-200'],next:next===null?'opaque:/?token=x':null}}}};
  const m=new M();m.start('b',['static'],A.create('a','fixture',{loadThumbnails:true}));await m.more();await m.more();assert.deepEqual(calls,[['b',null],['b','opaque:/?token=x']]);assert.equal(m.images.length,3);assert.equal(m.ended,true);
  for(const value of [null,[],{}, {thumbnails:[3]}, {thumbnails:['ok'],next:2}]){ctx.ComicSource.sources.a.comic.loadThumbnails=async()=>value;assert.equal((await A.create('a','f',{loadThumbnails:true}).loadComicThumbnail('x',null)).error,true)}
  for(const value of [null,[],{}, {comments:[null]}, {comments:[[]]}, {comments:[],maxPage:'2'}]){ctx.ComicSource.sources.a.comic.loadComments=async()=>value;assert.equal((await A.create('a','f',{loadComments:true}).loadComments('x',undefined,1,undefined)).error,true)}
 });
 await test('media repeated-cursor cycle terminates, retry preserves cursor/static positions',async()=>{
  const calls=[];let fail=true;const m=new M();m.start('b',['same'],{loadComicThumbnail:async(id,next)=>{calls.push(next);if(next==='A'&&fail)return Res.fail('HTTP 503 private body');return Res.ok(['same'],next===null?'A':next==='A'?'B':'A')}});await m.more();await m.more();assert.equal(m.images.length,2);assert.ok(m.error);fail=false;await m.more();await m.more();assert.equal(m.ended,true);assert.deepEqual(calls,[null,'A','A','B']);assert.equal(m.images.length,4);
 });
 await test('media source reset and hide ignore late results/errors/finally',async()=>{
  const old=defer(),fresh=defer(),m=new M();m.start('old',[],{loadComicThumbnail:()=>old.promise});const a=m.more();m.start('new',['new'],{loadComicThumbnail:()=>fresh.promise});const b=m.more();old.reject(Error('late private'));await a;assert.equal(m.loading,true);assert.equal(m.error,'');fresh.resolve(Res.ok(['fresh']));await b;assert.deepEqual(Array.from(m.images),['new','fresh']);
  const late=defer();m.start('x',['kept'],{loadComicThumbnail:()=>late.promise});const c=m.more();m.invalidate();late.resolve(Res.ok(['late']));await c;assert.deepEqual(Array.from(m.images),['kept']);assert.equal(m.loading,false);
 });
 await test('send returns any completed value as upstream success; like/vote argument positions and numeric truncation',async()=>{
  const calls=[];ctx.ComicSource.sources.a={comic:{sendComment:async(...args)=>{calls.push(['send',...args]);return false},sendChapterComment:async(...args)=>{calls.push(['chapter',...args])},likeComment:async(...args)=>{calls.push(['like',...args]);return 'ok'},voteComment:async(...args)=>{calls.push(['vote',...args]);return 9.9}}};
  const d=A.create('a','f',{sendComment:true,sendChapterComment:true,likeComment:true,voteComment:true});assert.equal((await d.sendComment('b',undefined,'message"',undefined)).data,true);assert.equal((await d.sendChapterComment('b','ep','reply','parent')).data,true);assert.equal((await d.likeComment('b','s','c',false)).data,0);assert.equal((await d.voteComment('b',undefined,'c',true,true)).data,9);assert.deepEqual(calls,[['send','b',null,'message"',null],['chapter','b','ep','reply','parent'],['like','b','s','c',false],['vote','b',null,'c',true,true]]);
 });
 await test('load/init never writes; list pagination replies chapter source locking and unknown maximum termination',async()=>{
  const calls=[],d={loadComments:async(...args)=>{calls.push(args);return Res.ok(args[2]===1?[comment()]:[])},sendComment:async()=>{throw Error('must not write')}};
  const c=new C();c.start(source(d),params({subId:'sub',replyTo:'parent'}));await c.more();await c.more();assert.equal(c.ended,true);assert.deepEqual(calls,[['book','sub',1,'parent'],['book','sub',2,'parent']]);
  c.start(source({loadChapterComments:async(...args)=>{calls.push(args);return Res.ok([comment()],1)}}),params({epId:'ep'}));await c.more();assert.deepEqual(calls.at(-1),['book','ep',1,undefined]);assert.equal(c.ended,true);
  c.start({...source(d),key:'other'},params());await c.more();assert.ok(c.error);assert.equal(c.rows.length,0);
 });
 await test('append failure retains page and retries identical request; duplicated IDs stop endless loader',async()=>{
  let fail=true;const pages=[],c=new C();c.start(source({loadComments:async(id,sub,p)=>{pages.push(p);if(p===2&&fail)return Res.fail('HTTP 503 private');return Res.ok([comment()])}}),params());await c.more();await c.more();assert.equal(c.page,1);assert.equal(c.rows.length,1);fail=false;await c.more();assert.deepEqual(pages,[1,2,2]);assert.equal(c.ended,true);assert.equal(c.error,'');
 });
 await test('mutations explicit busy serialized; send preserves draft on failure and refreshes only on success',async()=>{
  const pending=defer();let writes=0,reads=0,fail=true;const c=new C();c.start(source({loadComments:async()=>{reads++;return Res.ok([comment()],1)},sendComment:async()=>{writes++;if(fail)return Res.fail('HTTP 403 secret');return pending.promise}}),params());await c.more();assert.equal(writes,0);assert.equal(await c.send('   '),false);assert.equal(await c.send('draft'),false);assert.equal(reads,1);assert.ok(c.error);fail=false;const a=c.send('draft');assert.equal(c.writing,true);assert.equal(await c.send('doubletap'),false);pending.resolve(Res.ok(true));assert.equal(await a,true);assert.equal(writes,2);assert.equal(reads,2);assert.equal(c.writing,false);
 });
 await test('like toggles local count, vote score/cancel exact; no missing-ID or undeclared writes',async()=>{
  const calls=[],c=new C();c.start(source({loadComments:async()=>Res.ok([comment()],1),likeComment:async(...args)=>{calls.push(args);return Res.ok(999)},voteComment:async(...args)=>{calls.push(args);return Res.ok(20)}}),params({subId:'sub'}));await c.more();const row=c.rows[0];await c.react(row,'like');assert.equal(row.isLiked,true);assert.equal(row.score,6);await c.react(row,'like');assert.equal(row.score,5);await c.react(row,'up');assert.equal(row.voteStatus,1);assert.equal(row.score,20);await c.react(row,'up');assert.equal(row.voteStatus,0);await c.react(row,'down');assert.equal(row.voteStatus,-1);assert.deepEqual(calls.at(-2),['book','sub','c',true,true]);assert.deepEqual(calls.at(-1),['book','sub','c',false,false]);await c.react(comment(), 'like');assert.equal(calls.length,5);
 });
 await test('comments hide rejects late read/write and never reloads late successful write',async()=>{
  const readWait=defer(),writeWait=defer();let reads=0;const c=new C();c.start(source({loadComments:async()=>{reads++;return reads===1?Res.ok([comment()],1):readWait.promise},sendComment:()=>writeWait.promise}),params());await c.more();const a=c.send('draft');c.invalidate();writeWait.resolve(Res.ok(true));assert.equal(await a,false);assert.equal(reads,1);assert.equal(c.rows.length,1);const b=c.more(true);c.invalidate();readWait.resolve(Res.ok([comment('late')],1));await b;assert.equal(c.rows[0].id,'c');
 });
 await test('share fail-closed URL sanitation; title-only fallback never serializes source state',async()=>{
  assert.equal(S.create('Title','https://public.invalid/g/1/abc/').url,'https://public.invalid/g/1/abc/');
  for(const bad of ['javascript:alert(1)','file:///private','http://user:pass@host/path','https://host/path?token=secret','https://host/#auth','https://host\\@evil/x','https://host/%0aAuthorization']){const p=S.create('Title',bad);assert.equal(p.url,'');assert.equal(p.text,'Title')}
  assert.equal(S.create('A\nB').title,'A B');assert.equal(S.create('Title','https://ok.invalid:443/path').url,'https://ok.invalid:443/path');
 });
 await test('share falls back to absolute comic id then source site origin, never an app route',async()=>{
  assert.equal(S.create('T','https://site.invalid/g/9/').url,'https://site.invalid/g/9/');
  assert.equal(S.create('T',undefined,'https://e-hentai.invalid/g/1/abc/').url,'https://e-hentai.invalid/g/1/abc/');
  assert.equal(S.create('T','','https://e-hentai.invalid/g/1/abc/').url,'https://e-hentai.invalid/g/1/abc/');
  const site=S.create('T',undefined,'101','wnacg.invalid');assert.equal(site.url,'https://wnacg.invalid');assert.equal(site.text,'T\nhttps://wnacg.invalid');
  assert.equal(S.create('T',undefined,'101','https://wnacg.invalid/').url,'https://wnacg.invalid');
  const bad=S.create('T','javascript:alert(1)','/relative/path','');assert.equal(bad.url,'');assert.equal(bad.text,'T');
  assert.equal(S.create('T',undefined,undefined,undefined).text,'T');
  assert.equal(S.create('T','https://site.invalid/g/1/',undefined,'other.invalid').url,'https://site.invalid/g/1/');
  const r=R.parse('https://img.invalid/s.jpg@x=100-200&y=0-150');assert.equal(r.url,'https://img.invalid/s.jpg');assert.equal(r.width,100);assert.equal(r.height,150);assert.equal(r.x,100);assert.equal(r.cropped,true);assert.equal(R.parse('https://x@host/y').cropped,false);assert.equal(R.parse('x@x=5-2').cropped,false);assert.equal(V.scale(9),4);assert.equal(V.scale(NaN),1);assert.equal(V.offset(999,100,2),50);assert.equal(V.offset(-999,100,2),-50);assert.equal(V.offset(10,100,1),0);
 });
 await test('viewer production navigation/reset locks source and does not call loadEp',async()=>{
  let finds=[];const p=page('pages/ImageViewerPage','ImageViewerPage',{AppInit:{init:async()=>{}},SourceManager:{find:key=>{finds.push(key);return key==='a'?{}:undefined}}});p.params={sourceKey:'a',comicId:'book',title:'T',images:['one','two'],index:0};await p.initialize();assert.equal(p.ready,true);p.widthValue=100;p.heightValue=200;p.zoom(3);assert.equal(p.scaleValue,3);p.move(1);assert.equal(p.index,1);assert.equal(p.scaleValue,1);p.move(1);assert.equal(p.index,1);p.onPageHide();p.move(-1);assert.equal(p.index,1);assert.deepEqual(finds,['a']);assert.doesNotMatch(read('entry/src/main/ets/pages/ImageViewerPage.ets'),/loadComicPages\(|loadEp\(/);
 });
 await test('comments production page routes replies on original source and clears draft only confirmed send',async()=>{
  const routes=[],p=page('pages/CommentsPage','CommentsPage',{AppInit:{init:async()=>{}},SourceManager:{find:()=>source({loadComments:async()=>Res.ok([comment()],1),sendComment:async()=>Res.ok(true)})},router:{pushUrl:async r=>routes.push(r)},promptAction:{showToast:()=>{}}});p.params=params({subId:'s'});await p.initialize();assert.equal(p.comments.length,1);p.openReplies(p.comments[0]);assert.equal(routes[0].params.sourceKey,'a');assert.equal(routes[0].params.replyTo,'c');assert.equal(routes[0].params.subId,'s');p.draft='draft';await p.send();assert.equal(p.draft,'');p.onPageHide();assert.equal(p.loading,false);
 });
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/private body|token=x|message"|Authorization/);
 console.log(`PASS ${count} production details adapter/media/comments/viewer/page cases; no SDK/device/network/account acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
