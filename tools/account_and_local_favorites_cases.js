'use strict';
// Production page/business methods with local fixtures only. No account data,
// cookies, network, SDK build or device is used.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..');
const folder=path.join(root,'logs/account-local-favorites-20261029');
fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
const tick=()=>new Promise(r=>setImmediate(r));
let count=0,finished=false;
const EXPECTED=16;
process.on('beforeExit',()=>{if(!finished){console.error(`ACCOUNT_LOCAL_FAVORITES_INCOMPLETE ${count}/${EXPECTED}`);process.exitCode=1}});
async function test(name,fn){let guard;try{
  await Promise.race([Promise.resolve().then(fn),new Promise((_,reject)=>{guard=setTimeout(()=>reject(Error('WATCHDOG '+name)),4000)})]);
  count++;console.log('PASS '+name);
}finally{clearTimeout(guard)}}

function accountPage(){
  const raw=clean('entry/src/main/ets/pages/SourceAccountPage.ets');
  const code=(raw.slice(0,raw.indexOf('  build() {'))+'}')
    .replace(/@Entry\s*|@Component\s*|@State\s*/g,'').replace('struct SourceAccountPage','class SourceAccountPage');
  const state={params:{},routes:[],sources:[]};
  const ctx=vm.createContext({
    router:{getParams:()=>state.params,back:()=>state.routes.push('back'),pushUrl:async()=>{}},
    AppInit:{init:async()=>{}},AppContext:{ensureInitialized(){},context:{}},
    SourceManager:{find:key=>state.sources.find(s=>s.key===key)},
    Log:{audit(){},warn(){},error(){}},Res:class{constructor(d){this.dataOrNull=d;this.error=false}},
    BrowserLoginSession:{httpUrl(){},host:()=>'fixture.invalid'},
    common:{},UiTheme:{},UiIcon:function(){},UiPageHeader:function(){},UiSectionHeading:function(){},
    UiStyles:{},LoadingProgress:function(){},TextInput:function(){},Button:function(){},Text:function(){},
    Column:function(){},Row:function(){},Scroll:function(){},Stack:function(){},ForEach:function(){},Flex:function(){},
    InputType:{Password:1},FlexAlign:{},HorizontalAlign:{},FontWeight:{Medium:1}
  });
  vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Page=SourceAccountPage;',ctx);
  const p=new ctx.Page();
  // ArkUI provides this in the real page; the harness supplies the host context.
  p.getUIContext=()=>({getHostContext:()=>({})});
  return {p,state};
}

let finishedLocal=false;
process.on('exit',()=>{ if(!finishedLocal && count!==EXPECTED){ /* beforeExit already reported */ } });
(async()=>{
  // ---- account entry / capability reporting -------------------------------
  await test('source manager entry with key loads the declared account page',async()=>{
    const e=accountPage();
    e.state.params={key:'ehentai'};
    e.state.sources=[{key:'ehentai',name:'E-Hentai',account:{loginWebsite:'https://fixture.invalid',cookieFields:['a','b']}}];
    await e.p.aboutToAppear();await tick();
    assert.equal(e.p.error,'');assert.equal(e.p.source?.key,'ehentai');assert.deepEqual(Array.from(e.p.cookieValues),['','']);
  });

  await test('network-favourites entry passing sourceKey resolves the same source',async()=>{
    const e=accountPage();
    e.state.params={sourceKey:'Komiic'};
    e.state.sources=[{key:'Komiic',name:'Komiic',account:{login:async()=>({error:false,dataOrNull:true})}}];
    await e.p.aboutToAppear();await tick();
    assert.equal(e.p.error,'');assert.equal(e.p.source?.key,'Komiic');
  });

  await test('missing source identifier gives an actionable message, not a false account claim',async()=>{
    const e=accountPage();e.state.params={};
    await e.p.aboutToAppear();await tick();
    assert.match(e.p.error,/没有收到漫画源标识/);
    assert.doesNotMatch(e.p.error,/未声明账号功能/);
  });

  await test('unknown source is reported as not loaded instead of lacking an account',async()=>{
    const e=accountPage();e.state.params={key:'ehentai'};e.state.sources=[];
    await e.p.aboutToAppear();await tick();
    assert.match(e.p.error,/尚未加载完成/);
    assert.doesNotMatch(e.p.error,/未声明账号功能/);
  });

  await test('a source without any login declaration reports that exact cause',async()=>{
    const e=accountPage();e.state.params={key:'manwaba'};
    e.state.sources=[{key:'manwaba',name:'manwaba'}];
    await e.p.aboutToAppear();await tick();
    assert.match(e.p.error,/该源未声明登录功能/);
  });

  await test('both password and cookie sources keep their configured fields',async()=>{
    const e=accountPage();e.state.params={key:'password-source'};
    e.state.sources=[{key:'password-source',name:'P',account:{login:async()=>({error:false,dataOrNull:true}),cookieFields:[]}}];
    await e.p.aboutToAppear();await tick();
    assert.equal(e.p.source?.account?.login!==undefined,true);
    const w=accountPage();w.state.params={sourceKey:'web-source'};
    w.state.sources=[{key:'web-source',name:'W',account:{loginWebsite:'https://fixture.invalid',cookieFields:['igneous','ipb_member_id']}}];
    await w.p.aboutToAppear();await tick();
    assert.deepEqual(Array.from(w.p.cookieValues),['','']);
    assert.equal(w.p.source?.account?.loginWebsite,'https://fixture.invalid');
  });

  // ---- registry freshness -------------------------------------------------
  await test('registering the same key replaces a stale instance instead of keeping it',()=>{
    const ctx=vm.createContext({Log:{warn(){},info(){},error(){}},fs:{},SourceDao:{list:async()=>[]},
      SourceInstaller:{scriptPath:k=>`/x/${k}.js`},SourceDataStore:{preload:async()=>{}},
      ComicSourceParser:{parse:async()=>({key:'ehentai',account:{}})},JsEngine:{isAvailable:false},
      LocalSource:class{constructor(){this.key='local';this.name='本地漫画';}},firstWhereOrNull:(a,f)=>a.find(f)});
    vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/source/SourceManager.ets'),{mode:'transform'})
      +'\nglobalThis.SM=SourceManager;',ctx);
    const SM=ctx.SM;
    SM.register({key:'local',name:'本地漫画'});
    SM.register({key:'ehentai',name:'旧实例'});
    assert.equal(SM.find('ehentai').name,'旧实例');
    SM.register({key:'ehentai',name:'新实例',account:{login(){}}});
    assert.equal(SM.all().filter(s=>s.key==='ehentai').length,1);
    assert.equal(SM.find('ehentai').name,'新实例');
    assert.equal(SM.find('ehentai').account!==undefined,true);
  });

  await test('reloadInstalled keeps built-in local source and clears stale script sources',()=>{
    const ctx=vm.createContext({Log:{warn(){},info(){},error(){}},fs:{accessSync:()=>false},SourceDao:{list:async()=>[]},
      SourceInstaller:{scriptPath:k=>`/x/${k}.js`},SourceDataStore:{preload:async()=>{}},
      ComicSourceParser:{parse:async()=>({key:'x',name:'x'})},JsEngine:{isAvailable:false},
      LocalSource:class{constructor(){this.key='local';this.name='本地漫画';}},firstWhereOrNull:(a,f)=>a.find(f)});
    vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/source/SourceManager.ets'),{mode:'transform'})
      +'\nglobalThis.SM=SourceManager;',ctx);
    const SM=ctx.SM;
    SM.register({key:'local',name:'本地漫画'});
    SM.register({key:'gone',name:'已卸载'});
    return SM.reloadInstalled().then(()=>{
      const keys=Array.from(SM.all(),s=>s.key);
      assert.deepEqual(keys,['local']);
    });
  });

  await test('repository install path reloads the registry so new capabilities appear',()=>{
    const src=read('entry/src/main/ets/pages/SourceRepositoryPage.ets');
    assert.match(src,/await SourceManager\.reloadInstalled\(\)/);
    assert.match(src,/SourceInstaller\.install\(entry\)[\s\S]{0,260}reloadInstalled\(\)/);
  });

  // ---- local favourites own update tracking ------------------------------
  function localFavorites(){
    const favourites=[],follows=new Map();
    const ctx=vm.createContext({
      ComicType:{fromKey:key=>({value:key==='local'?0:1})},
      FavoriteItem:class{constructor(){this.id='';this.name='';this.author='';this.tags=[];this.coverPath='';this.folder='';this.time='';this.sourceKey='';this.type={value:1};}
        static now(){return '2026-10-29 00:00:00'}syncComicFields(){}},
      FavoritesDao:{isFavorite:async(id,type)=>favourites.some(f=>f.id===id&&f.type===type),
        add:async item=>{if(favourites.some(f=>f.id===item.id&&f.folder===item.folder&&f.type.value===item.type.value))return false;
          favourites.push({id:item.id,folder:item.folder,type:item.type.value,name:item.name,cover:item.coverPath});return true}},
      FollowUpdatesDao:{init:async()=>{},
        list:async()=>Array.from(follows.values()),
        follow:async(sourceKey,comicId,title,cover)=>{if(!follows.has(`${sourceKey}/${comicId}`))follows.set(`${sourceKey}/${comicId}`,{sourceKey,comicId,title,cover});},
        unfollow:async(sourceKey,comicId)=>{follows.delete(`${sourceKey}/${comicId}`);}},
      FollowUpdates:{checkAll:async(onResult)=>{for(const row of follows.values())onResult(row);}},
      Log:{info(){},warn(){}}
    });
    vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/features/LocalFavorites.ets'),{mode:'transform'})
      +'\nglobalThis.LF=LocalFavorites;',ctx);
    return {LF:ctx.LF,favourites,follows};
  }

  await test('old manual-follow rows migrate into the default local favourite folder once',async()=>{
    const l=localFavorites();
    l.follows.set('ehentai/123',{sourceKey:'ehentai',comicId:'123',title:'旧追更',cover:'c'});
    await l.LF.ensureMigrated();
    assert.equal(l.favourites.length,1);
    assert.deepEqual([l.favourites[0].id,l.favourites[0].folder,l.favourites[0].name],['123','','旧追更']);
    await l.LF.ensureMigrated();
    assert.equal(l.favourites.length,1,'migration must be idempotent');
  });

  await test('an already favourited comic is never duplicated by migration',async()=>{
    const l=localFavorites();
    l.favourites.push({id:'123',folder:'收藏夹A',type:1,name:'已有',cover:'c'});
    l.follows.set('ehentai/123',{sourceKey:'ehentai',comicId:'123',title:'旧追更',cover:'c'});
    await l.LF.ensureMigrated();
    assert.equal(l.favourites.length,1);
    assert.equal(l.favourites[0].folder,'收藏夹A');
  });

  await test('favouriting enables update tracking; last removal stops it',async()=>{
    const l=localFavorites();
    await l.LF.track('ehentai','123','标题','封面');
    assert.equal(l.follows.size,1);
    l.favourites.push({id:'123',folder:'A',type:1,name:'标题',cover:'封面'});
    l.favourites.push({id:'123',folder:'B',type:1,name:'标题',cover:'封面'});
    await l.LF.syncRemoval('ehentai','123',1);
    assert.equal(l.follows.size,1,'another folder still holds the comic');
    l.favourites.splice(0,2);
    await l.LF.syncRemoval('ehentai','123',1);
    assert.equal(l.follows.size,0,'no folder holds the comic, tracking stops');
  });

  await test('manual check covers the favourite set and never schedules itself',async()=>{
    const l=localFavorites();
    l.follows.set('ehentai/1',{sourceKey:'ehentai',comicId:'1',title:'a',cover:''});
    const seen=[];await l.LF.checkUpdates(row=>seen.push(row.comicId));
    assert.deepEqual(seen,['1']);
    const src=read('entry/src/main/ets/features/LocalFavorites.ets');
    assert.doesNotMatch(src,/setInterval\(|setTimeout\(/);
  });

  await test('local and network favourite actions share one level row on the details page',()=>{
    const panel=read('entry/src/main/ets/components/CollectionActionsPanel.ets');
    assert.match(panel,/Button\(this\.localFavoriteLabel\)/);
    assert.match(panel,/Button\('网络收藏'\)/);
    assert.match(panel,/Row\(\{ space: 10 \}\)[\s\S]{0,400}Button\('网络收藏'\)/);
    const details=read('entry/src/main/ets/pages/ComicDetailsPage.ets');
    assert.doesNotMatch(details,/Text\(this\.isFavorite \? '已收藏' : '收藏'\)/);
    assert.match(details,/onLocalFavorite: \(\) => \{ this\.showFolderPanel = !this\.showFolderPanel; \}/);
    assert.match(details,/localFavoriteLabel: this\.isFavorite \? '已加入本地收藏' : '本地收藏'/);
    const settings=read('entry/src/main/ets/features/SettingsView.ets');
    assert.match(settings,/title: '本地收藏'/);
    const page=read('entry/src/main/ets/pages/FollowUpdatesPage.ets');
    assert.match(page,/title: '本地收藏'/);
    assert.doesNotMatch(page,/手动追更|取消追更/);
  });

  await test('details page tracks favourites and untracks only after the last folder leaves',()=>{
    const src=read('entry/src/main/ets/pages/ComicDetailsPage.ets');
    assert.match(src,/import \{ LocalFavorites \} from '\.\.\/features\/LocalFavorites';/);
    assert.match(src,/if \(added\) \{ await LocalFavorites\.track\(/);
    assert.match(src,/await LocalFavorites\.syncRemoval\(this\.sourceKey, this\.comicId, this\.typeValue\(\)\)/);
  });

  await test('retired collection/backup modules stay absent from the runtime',()=>{
    for(const f of ['entry/src/main/ets/features/PictureFavorites.ets','entry/src/main/ets/features/DataSync.ets',
      'entry/src/main/ets/features/ReadingStats.ets','entry/src/main/ets/pages/StatisticsPage.ets']){
      assert.equal(fs.existsSync(path.join(root,f)),false,f);
    }
  });

  assert.equal(count,EXPECTED);finished=true;finishedLocal=true;
  fs.writeFileSync(path.join(folder,'cases.json'),JSON.stringify({cases:count,evidence:'production page/business methods with local fixtures; no login, cookies, network or device'},null,2));
  console.log(`PASS ${count} account-entry and local-favourite/update contracts; no login, credentials, network or device`);
})().catch(error=>{console.error(error);process.exitCode=1});
