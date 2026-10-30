'use strict';
// Current scope: ordinary local favorites, follow updates and network favorites. Retired picture-only cases removed.
// No SDK/device/accounts/network/app userdata; adapters only map platform APIs to host fixtures.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),vm=require('node:vm'),assert=require('node:assert/strict');
const {DatabaseSync}=require('node:sqlite');const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'venera-collections-')),log=path.join(root,'logs/collections-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
fs.writeFileSync(log,'Production collection DAL/services/session. Actual isolated SQLite + fixture files, controlled source callbacks; no SDK/device/live account/network.\n');
const sqlite=new DatabaseSync(path.join(temp,'fixture.sqlite'));let openCount=0;
const rdb={executeSync:(sql,args=[])=>sqlite.prepare(sql).run(...args),executeSql:async(sql,args=[])=>sqlite.prepare(sql).run(...args),querySql:async(sql,args=[])=>{
 const stmt=sqlite.prepare(sql),names=stmt.columns().map(c=>c.name),rows=stmt.all(...args);let i=-1;
 return {goToFirstRow:()=>{i=0;return rows.length>0},goToNextRow:()=>++i<rows.length,getColumnIndex:n=>names.indexOf(n),getString:c=>String(rows[i][names[c]]??''),getLong:c=>Number(rows[i][names[c]]),close:()=>{}};
}};
const sources=new Map();const calls=[];
const ctx=vm.createContext({Error,Map,Set,Promise,Date,JSON,Number,Math,ArrayBuffer,Uint8Array,
 relationalStore:{SecurityLevel:{S1:1},getRdbStore:async()=>{openCount++;return rdb}},
 AppContext:{context:{},filesDir:temp},Log:{info:()=>{},audit:()=>{},warn:()=>{}},
 SourceManager:{find:k=>sources.get(k)}
});
vm.runInContext(stripTypeScriptTypes([
 'entry/src/main/ets/foundation/Extensions.ets','entry/src/main/ets/model/Comic.ets','entry/src/main/ets/model/ComicDetails.ets',
 'entry/src/main/ets/model/Res.ets','entry/src/main/ets/storage/Database.ets','entry/src/main/ets/source/AuthLogScope.ets',
 'entry/src/main/ets/model/ComicType.ets','entry/src/main/ets/storage/FavoritesDao.ets',
 'entry/src/main/ets/storage/FollowUpdatesDao.ets','entry/src/main/ets/features/FollowUpdates.ets',
 'entry/src/main/ets/source/ComicSource.ets','entry/src/main/ets/source/JsFavoritesAdapter.ets','entry/src/main/ets/features/NetworkFavoritesSession.ets'
].map(clean).join('\n'),{mode:'transform'})+'\nglobalThis.T={Database,FavoriteItem,FavoritesDao,FollowUpdate,FollowUpdatesDao,FollowUpdates,ComicDetails,ComicChapters,ComicSource,Res,JsFavoritesAdapter,NetworkFavoritesSession};',ctx);
const T=ctx.T,ok=(v,s)=>T.Res.ok(v,s),defer=()=>{let resolve;return {promise:new Promise(r=>resolve=r),resolve:v=>resolve(v)}};
ctx.JsEngine={callJson:async code=>vm.runInContext(code,ctx)};
vm.runInContext('ComicSource.sources={};',ctx);
let count=0;async function test(name,fn){await fn();count++;fs.appendFileSync(log,'PASS '+name+'\n')}
(async()=>{
 await test('production DB initializes once and own tables preserve existing history/favorite records',async()=>{
  await Promise.all([T.Database.init(),T.FollowUpdatesDao.init()]);assert.equal(openCount,1);
  sqlite.prepare("INSERT INTO history(id,type,title,time) VALUES ('fixture',1,'untouched',1)").run();
  sqlite.prepare("INSERT INTO favorites(id,type,name,time) VALUES ('fixture',1,'untouched','1')").run();
  await T.Database.init();await T.FollowUpdatesDao.init();
  assert.equal(sqlite.prepare('SELECT count(*) n FROM history').get().n,1);assert.equal(sqlite.prepare('SELECT count(*) n FROM favorites').get().n,1);
 });
 await test('ordinary local favorite folders/add/dedup/copy/remove preserve source identity',async()=>{
   await T.FavoritesDao.createFolder('retained-folder');
   const item=new T.FavoriteItem();Object.assign(item,{id:'local-favorite',name:'Local retained',sourceKey:'local',folder:'retained-folder',time:'2026-01-01'});
   assert.equal(await T.FavoritesDao.add(item),true);assert.equal(await T.FavoritesDao.add(item),false);
   assert.equal((await T.FavoritesDao.list('retained-folder'))[0].sourceKey,'local');
   await T.FavoritesDao.createFolder('copy-folder');
   assert.equal(await T.FavoritesDao.copyFavorite('retained-folder','copy-folder',item.id,item.type.value),true);
   await T.FavoritesDao.remove(item.id,item.type.value,'retained-folder');
   assert.equal(await T.FavoritesDao.isFavoriteIn('retained-folder',item.id,item.type.value),false);
   assert.equal(await T.FavoritesDao.isFavoriteIn('copy-folder',item.id,item.type.value),true);
   await T.FavoritesDao.removeEverywhere(item.id,item.type.value);
   assert.equal(await T.FavoritesDao.isFavorite(item.id,item.type.value),false);
 });
 const detail=(ids,date='2026-01-01')=>{const d=new T.ComicDetails();d.chapters=T.ComicChapters.flatOf(new Map(ids.map(id=>[id,'Chapter '+id])));d.updateTime=date;return d};
 await test('follow subscribe is local only, first check baseline not unread; changes/readmark/failure persist',async()=>{
  let remoteCalls=0,current=detail(['1']);sources.set('a',{key:'a',loadComicInfo:async()=>{remoteCalls++;return ok(current)}});
  await T.FollowUpdates.follow('a','follow','Follow','');assert.equal(remoteCalls,0);
  await T.FollowUpdates.checkAll();let row=await T.FollowUpdatesDao.find('a','follow');assert.equal(remoteCalls,1);assert.equal(row.unread,false);assert.ok(row.baseline);
  current=detail(['1','2']);await T.FollowUpdates.checkAll();row=await T.FollowUpdatesDao.find('a','follow');assert.equal(row.unread,true);
  sources.get('a').loadComicInfo=async()=>{throw Error('private remote body')};await T.FollowUpdates.checkAll();row=await T.FollowUpdatesDao.find('a','follow');assert.equal(row.unread,true);assert.ok(row.error);assert.doesNotMatch(row.error,/private/);
  await T.FollowUpdatesDao.markRead('a','follow');row=await T.FollowUpdatesDao.find('a','follow');assert.equal(row.unread,false);
  sources.get('a').loadComicInfo=async()=>ok(new T.ComicDetails());await T.FollowUpdates.checkAll();assert.ok((await T.FollowUpdatesDao.find('a','follow')).error);
 });
 await test('follow bounded concurrency and per-comic errors, source identity collisions remain distinct',async()=>{
  await T.FollowUpdatesDao.unfollow('a','follow');let active=0,max=0;
  sources.set('a',{key:'a',loadComicInfo:async id=>{active++;max=Math.max(max,active);await new Promise(r=>setImmediate(r));active--;return id==='bad'?T.Res.fail('private'):ok(detail([id]))}});
  for(const id of ['same','two','bad','four','five'])await T.FollowUpdates.follow('a',id,id,'');
  await T.FollowUpdates.follow('b','same','B','');sources.set('b',{key:'b'});const results=[];
  await T.FollowUpdates.checkAll(r=>results.push(r));assert.equal(max,2);assert.equal(results.length,6);
  const rows=await T.FollowUpdatesDao.list();assert.equal(rows.filter(r=>r.error).length,2);assert.equal(rows.filter(r=>r.comicId==='same').length,2);
 });
 await test('removed subscription is not resurrected by pending result; cancellation stops queue and overlapping checks rejected',async()=>{
  for(const row of await T.FollowUpdatesDao.list())await T.FollowUpdatesDao.unfollow(row.sourceKey,row.comicId);
  const wait=defer();let calls=0,continueFlag=true;sources.set('a',{key:'a',loadComicInfo:async()=>{calls++;await wait.promise;return ok(detail(['1']))}});
  for(let i=0;i<5;i++)await T.FollowUpdates.follow('a','q'+i,'Q','');
  const running=T.FollowUpdates.checkAll(()=>{},()=>continueFlag);await new Promise(r=>setImmediate(r));assert.equal(calls,2);
  await assert.rejects(()=>T.FollowUpdates.checkAll(),/已有/);await T.FollowUpdatesDao.unfollow('a','q0');continueFlag=false;wait.resolve();await running;
  assert.equal(calls,2);assert.equal(await T.FollowUpdatesDao.find('a','q0'),undefined);assert.equal((await T.FollowUpdatesDao.list()).filter(r=>r.checkedAt>0).length,0);
 });
 await test('production favorites adapter nullable argument order account gate safe favId compatibility and no implicit mutation',async()=>{
  const script={favorites:{loadFolders:async id=>{assert.equal(id,null);return {folders:{f:'Folder'},favorited:['f']}},loadNext:async(next,folder)=>({comics:[{id:next===null?'1':'2'}],next:next===null?'opaque-secret':null}),addOrDelFavorite:async function(...args){calls.push(args)}}};
  T.ComicSource.sources.a=script;sources.set('a',{key:'a',isLogged:false});let data=T.JsFavoritesAdapter.create('a','fixture',false,true,true,true,true);
  assert.equal((await data.loadFolders()).error,true);sources.get('a').isLogged=true;assert.equal((await data.loadFolders()).data.get('f'),'Folder');
  const session=new T.NetworkFavoritesSession();sources.get('a').favoriteData=data;await session.start(sources.get('a'));assert.equal(session.page,1);assert.equal(session.next,'opaque-secret');await session.more();assert.equal(session.ended,true);assert.equal(session.results.length,2);
  let writes=0;script.favorites.addOrDelFavorite=async function(id,folder,adding,favId){writes++;assert.equal(favId,'remote-id')};
  assert.equal((await data.addOrDelFavorite('1','f',false,undefined)).error,true);assert.equal(writes,0);
  assert.equal((await data.addOrDelFavorite('1','f',false,'remote-id')).error,false);assert.equal(writes,1);
  script.favorites.addOrDelFavorite=async function(id,folder,adding){assert.equal(arguments.length,3);writes++};
  await data.addOrDelFavorite('1','f',true,'not-used');assert.equal(writes,2);
 });
 await test('favorites session retries same page, ignores stale folder responses, cycle termination and cross-source rows',async()=>{
  const one=defer(),two=defer(),s=new T.NetworkFavoritesSession();const source={key:'a',isLogged:true,favoriteData:{multiFolder:false,loadComic:async(page,folder)=>folder==='old'?one.promise:two.promise}};
  s.source=source;const old=s.select('old'),fresh=s.select('new');one.resolve(ok([{id:'old',sourceKey:'a'}],2));await old;assert.equal(s.loading,true);two.resolve(ok([{id:'new',sourceKey:'a'}],2));await fresh;assert.equal(s.results[0].id,'new');
  let fail=true,pages=[];source.favoriteData.loadComic=async page=>{pages.push(page);if(fail)throw Error('private');return ok([{id:'next',sourceKey:'a'}],2)};
  await s.more();assert.equal(s.page,1);assert.equal(s.results.length,1);fail=false;await s.more();assert.equal(s.page,2);assert.deepEqual(pages,[2,2]);
  await s.start({key:'a',isLogged:true,favoriteData:{multiFolder:false,loadComic:async()=>ok([{id:'bad',sourceKey:'b'}])}});assert.ok(s.error);assert.equal(s.results.length,0);
  let n=0;await s.start({key:'a',isLogged:true,favoriteData:{multiFolder:false,loadNext:async()=>ok([{id:String(++n),sourceKey:'a'}],'same')}});await s.more();assert.equal(s.ended,true);
 });
 assert.equal(sqlite.prepare('SELECT title FROM history WHERE id=?').get('fixture').title,'untouched');
 assert.equal(sqlite.prepare('SELECT name FROM favorites WHERE id=?').get('fixture').name,'untouched');
 console.log(`PASS ${count} retained local favorites/follow/network collection DAL/service/session cases (no picture-favorite or backup cases); no SDK/device/network acceptance.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1}).finally(()=>{sqlite.close();if(temp.startsWith(os.tmpdir()+path.sep+'venera-collections-'))fs.rmSync(temp,{recursive:true,force:true})});
