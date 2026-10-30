'use strict';
// Read-only production-method regression: in-memory FS/DAO/ArkUI fakes only.
// No SDK build, device, network, application sandbox or user records are touched.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/local-library-refresh-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'LOCAL FIXTURES ONLY: production LocalSource/HomeView/BookshelfView/LocalLibrarySignal methods; not device/render acceptance.\n');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const clean=s=>s.replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const load=f=>clean(read('entry/src/main/ets/'+f));
function view(file,name,cut='  @Builder'){
 let s=load(file),at=s.indexOf(cut);assert.ok(at>=0,'missing cut for '+name);s=s.slice(0,at)+'}';
 return s.replace(/@Watch\('[^']+'\)\s*/g,'').replace(/@Entry\s*|@Component\s*|@State\s*|@Prop\s*/g,'').replace('struct '+name,'class '+name);
}
const tick=()=>new Promise(r=>setImmediate(r));
const deferred=()=>{let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j});return{promise,resolve,reject}};
const plain=v=>JSON.parse(JSON.stringify(v));
function memoryFS(){
 const files=new Map(),dirs=new Set(['/app/files/local_comics']),calls=[];
 const parent=p=>p.slice(0,p.lastIndexOf('/'));
 const mkdir=p=>{if(p&&p!=='/'&&!dirs.has(p)){mkdir(parent(p));dirs.add(p)}};
 const file=(p,text='image-fixture')=>{mkdir(parent(p));files.set(p,text)};
 const remove=p=>{for(const k of files.keys())if(k===p||k.startsWith(p+'/'))files.delete(k);for(const k of dirs)if(k===p||k.startsWith(p+'/'))dirs.delete(k)};
 const api={accessSync:p=>files.has(p)||dirs.has(p),mkdirSync:p=>mkdir(p),
  listFileSync:p=>{calls.push(['list',p]);return [...new Set([...files.keys(),...dirs].filter(k=>k.startsWith(p+'/')&&!k.slice(p.length+1).includes('/')).map(k=>k.slice(p.length+1)))]},
  statSync:p=>{calls.push(['stat',p]);if(!files.has(p)&&!dirs.has(p))throw Error('fixture missing');return{isFile:()=>files.has(p),isDirectory:()=>dirs.has(p)}},
  readTextSync:p=>{calls.push(['read',p]);if(!files.has(p))throw Error('fixture missing');return files.get(p)}};
 return{api,files,dirs,calls,file,mkdir,remove};
}
function environment(){
 const disk=memoryFS(),db={history:0,favorites:0,folders:0},initCalls=[],sourceCalls=[],historyListeners=new Set(),favoriteListeners=new Set();
 const c=vm.createContext({console,fs:disk.api,AppContext:{localComicDir:'/app/files/local_comics'},
  AppInit:{init:async()=>{initCalls.push('init')}},
  Log:{audit(){},info(){},warn(){},error(){}},router:{pushUrl:async()=>{}},promptAction:{showToast(){}},
  HistoryDao:{addListener:f=>historyListeners.add(f),removeListener:f=>historyListeners.delete(f),list:async()=>{db.history++;return[]}},
  FavoritesDao:{addListener:f=>favoriteListeners.add(f),removeListener:f=>favoriteListeners.delete(f),list:async()=>{db.favorites++;return[]},listFolders:async()=>{db.folders++;return[]}},
  TabsController:class{changeIndex(){}},UiBridge:{registerBuilder(){}},
 });
 const code=['model/Res.ets','model/Comic.ets','source/ComicSource.ets','source/LocalSource.ets','features/LocalLibrarySignal.ets','features/ShelfCommands.ets'].map(load).join('\n')+'\n'+
  view('features/HomeView.ets','HomeView')+'\n'+view('features/BookshelfView.ets','BookshelfView')+'\n'+view('pages/Index.ets','Index');
 vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.T={LocalSource,LocalLibrarySignal,ShelfCommands,HomeView,BookshelfView,Index,Res};',c);
 const local=new c.T.LocalSource(),scan=local.explorePages[0].loadPage;
 local.explorePages[0].loadPage=async p=>{sourceCalls.push(p);return await scan(p)};
 c.SourceManager={find:k=>k==='local'?local:undefined};
 return{c,disk,db,initCalls,sourceCalls,historyListeners,favoriteListeners,local,signal:c.T.LocalLibrarySignal,
  ok:v=>new c.T.Res(v),scan:async()=>plain((await local.explorePages[0].loadPage(1)).dataOrNull),
  comic:(name='comic')=>disk.file('/app/files/local_comics/'+name+'/1.png'),
  home:()=>new c.T.HomeView(),shelf:()=>new c.T.BookshelfView(),index:()=>new c.T.Index()};
}
const viewSetup=kind=>{const e=environment(),p=kind==='home'?e.home():e.shelf();return{e,p,
 local:()=>kind==='home'?p.reloadLocal():p.reloadLocalComics(),full:()=>kind==='home'?p.reload():p.refresh(),
 activate:()=>{p.active=true;p.appeared=true;if(kind!=='home'){p.disposed=false;p.visible=true;}},
 hide:()=>{p.active=false;p.onHostChanged()},rows:()=>plain(p.localComics)};};
let count=0,passed=0,finished=false;const EXPECTED=45,failures=[];
process.on('beforeExit',()=>{if(!finished){console.error(`LOCAL_LIBRARY_INCOMPLETE count=${count}/${EXPECTED}`);process.exitCode=1}});
async function test(name,fn){let timer;try{await Promise.race([Promise.resolve().then(fn),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('ASYNC_WATCHDOG '+name)),4000)})]);passed++;fs.appendFileSync(log,'PASS '+name+'\n')}catch(error){failures.push({name,error:String(error.stack)});fs.appendFileSync(log,'FAIL '+name+'\n'+error.stack+'\n')}finally{clearTimeout(timer);count++}}
(async()=>{
 await test('LocalSource empty root returns zero rather than a synthetic sample',async()=>{const e=environment();assert.equal((await e.scan()).length,0)});
 await test('empty and metadata-only task folders are not readable comics',async()=>{const e=environment();e.disk.mkdir('/app/files/local_comics/empty');e.disk.file('/app/files/local_comics/DL_1_2/download.json','{"owner":"DL_1_2","title":"placeholder"}');assert.equal((await e.scan()).length,0)});
 await test('strict legacy diagnostic name with exact ownership marker is excluded without deletion',async()=>{const e=environment(),name='HM_OFFLINE_READER_123_456';e.comic(name);e.disk.file('/app/files/local_comics/'+name+'/.venera-usability',name);assert.equal((await e.scan()).length,0);assert.equal(e.disk.files.has('/app/files/local_comics/'+name+'/1.png'),true)});
 await test('same strict diagnostic name without owned marker retains real images',async()=>{const e=environment();e.comic('HM_OFFLINE_READER_123_456');assert.equal((await e.scan())[0].id,'HM_OFFLINE_READER_123_456')});
 await test('wrong or newline-suffixed marker never hides a real comic',async()=>{for(const marker of ['someone-else','HM_OFFLINE_READER_123_456\n']){const e=environment(),name='HM_OFFLINE_READER_123_456';e.comic(name);e.disk.file('/app/files/local_comics/'+name+'/.venera-usability',marker);assert.equal((await e.scan()).length,1)}});
 await test('lookalike diagnostic names are never excluded even with matching marker',async()=>{for(const name of ['HM_OFFLINE_READER_1_2_extra','HM_OFFLINE_READER_1','HM_OFFLINE_READER_x_2','user_HM_OFFLINE_READER_1_2']){const e=environment();e.comic(name);e.disk.file('/app/files/local_comics/'+name+'/.venera-usability',name);assert.equal((await e.scan()).length,1)}});
 await test('directory named with image extension is not an image file',async()=>{const e=environment();e.disk.mkdir('/app/files/local_comics/not-readable/fake.jpg');assert.equal((await e.scan()).length,0)});
 await test('later chapter image supplies cover when root and first chapter are empty',async()=>{const e=environment();e.disk.mkdir('/app/files/local_comics/chaptered/01');e.disk.file('/app/files/local_comics/chaptered/02/10.jpg');e.disk.file('/app/files/local_comics/chaptered/02/2.jpg');const rows=await e.scan();assert.equal(rows.length,1);assert.match(rows[0].cover,/02\/2\.jpg$/)});
 await test('all declared image extensions include uppercase while hidden and unsupported files do not count',async()=>{for(const ext of ['JPG','jpeg','png','webp','gif','bmp','avif']){const e=environment();e.disk.file('/app/files/local_comics/real/1.'+ext);assert.equal((await e.scan()).length,1)}const e=environment();e.disk.file('/app/files/local_comics/hidden/.1.png');e.disk.file('/app/files/local_comics/other/1.txt');assert.equal((await e.scan()).length,0)});
 await test('download title metadata applies only to exact matching owner',async()=>{const e=environment();e.comic('DL_1_2');e.disk.file('/app/files/local_comics/DL_1_2/download.json',JSON.stringify({owner:'DL_1_2',title:'Actual title'}));assert.equal((await e.scan())[0].title,'Actual title');e.disk.files.set('/app/files/local_comics/DL_1_2/download.json',JSON.stringify({owner:'foreign',title:'Wrong title'}));assert.equal((await e.scan())[0].title,'DL_1_2')});
 await test('delete readable folders changes count two to one to zero despite leftover placeholder and owned sample',async()=>{const e=environment();e.comic('a');e.comic('b');e.disk.mkdir('/app/files/local_comics/placeholder');const n='HM_OFFLINE_READER_1_2';e.comic(n);e.disk.file('/app/files/local_comics/'+n+'/.venera-usability',n);assert.equal((await e.scan()).length,2);e.disk.remove('/app/files/local_comics/a');assert.equal((await e.scan()).length,1);e.disk.remove('/app/files/local_comics/b');assert.equal((await e.scan()).length,0)});
 await test('eight real comics survive scan and natural first-cover selection without preview truncation',async()=>{const e=environment();for(let i=1;i<=8;i++)e.comic('comic-'+i);const rows=await e.scan();assert.equal(rows.length,8);assert.equal(new Set(rows.map(r=>r.id)).size,8)});
 await test('signal deduplicates listener registration but each notify is delivered',async()=>{const e=environment();let n=0;const f=()=>n++;e.signal.addListener(f);e.signal.addListener(f);e.signal.notify();e.signal.notify();assert.equal(n,2);e.signal.removeListener(f);e.signal.removeListener(f);e.signal.notify();assert.equal(n,2)});
 await test('signal isolates synchronous listener failures and uses stable notification snapshot',async()=>{const e=environment(),seen=[];const other=()=>seen.push('other');e.signal.addListener(()=>{seen.push('first');e.signal.removeListener(other);throw Error('fixture listener')});e.signal.addListener(other);e.signal.notify();assert.deepEqual(seen,['first','other']);e.signal.notify();assert.deepEqual(seen,['first','other','first'])});
 await test('signal carries no data and causes no work without view subscriptions',async()=>{const e=environment();e.signal.notify();e.signal.notify();await tick();assert.equal(e.initCalls.length,0);assert.equal(e.disk.calls.length,0);assert.deepEqual(e.db,{history:0,favorites:0,folders:0})});
 for(const kind of ['home','shelf']){
  await test(kind+' delete signal refreshes readable count one to zero',async()=>{const {e,p}=viewSetup(kind);e.comic();p.aboutToAppear();await tick();assert.equal(p.localComics.length,1);e.disk.remove('/app/files/local_comics/comic');e.signal.notify();await tick();assert.equal(p.localComics.length,0);p.aboutToDisappear()});
  await test(kind+' old delayed scan cannot overwrite newer deletion result',async()=>{const f=viewSetup(kind),gate=deferred();f.activate();let calls=0;f.e.local.explorePages[0].loadPage=()=>++calls===1?gate.promise:Promise.resolve(f.e.ok([]));const old=f.local();await tick();await f.local();gate.resolve(f.e.ok([{id:'deleted',sourceKey:'local'}]));await old;assert.equal(f.rows().length,0)});
  await test(kind+' stale init completion cannot start another cover scan',async()=>{const f=viewSetup(kind),gate=deferred();f.activate();let calls=0;f.e.c.AppInit.init=()=>++calls===1?gate.promise:Promise.resolve();const old=f.local();await tick();await f.local();const scans=f.e.sourceCalls.length;gate.resolve();await old;assert.equal(f.e.sourceCalls.length,scans)});
  await test(kind+' hidden initial appear does not list database or scan covers',async()=>{const f=viewSetup(kind);f.p.active=false;f.p.aboutToAppear();await tick();assert.deepEqual(f.e.db,{history:0,favorites:0,folders:0});assert.equal(f.e.disk.calls.length,0);f.p.aboutToDisappear()});
  await test(kind+' hidden notify does not list database or scan covers',async()=>{const f=viewSetup(kind);f.p.aboutToAppear();await tick();f.hide();const db={...f.e.db},scans=f.e.sourceCalls.length;f.e.signal.notify();for(const listener of f.e.historyListeners)listener();for(const listener of f.e.favoriteListeners)listener();await tick();assert.deepEqual(f.e.db,db);assert.equal(f.e.sourceCalls.length,scans);f.p.aboutToDisappear()});
  await test(kind+' hiding while init is pending prevents later database and cover work',async()=>{const f=viewSetup(kind),gate=deferred();f.e.c.AppInit.init=()=>gate.promise;f.p.aboutToAppear();await tick();f.hide();gate.resolve();await tick();assert.deepEqual(f.e.db,{history:0,favorites:0,folders:0});assert.equal(f.e.sourceCalls.length,0);f.p.aboutToDisappear()});
  await test(kind+' hiding during pending local scan discards stale returned rows',async()=>{const f=viewSetup(kind),gate=deferred();f.activate();f.e.local.explorePages[0].loadPage=()=>gate.promise;const old=f.local();await tick();f.hide();gate.resolve(f.e.ok([{id:'late'}]));await old;assert.equal(f.rows().length,0)});
  await test(kind+' host watcher returning from hidden state rescans deleted library',async()=>{const f=viewSetup(kind);f.e.comic();f.p.aboutToAppear();await tick();assert.equal(f.rows().length,1);f.hide();f.e.disk.remove('/app/files/local_comics/comic');f.e.signal.notify();await tick();assert.equal(f.rows().length,1);f.p.active=true;f.p.hostRevision++;f.p.onHostChanged();await tick();assert.equal(f.rows().length,0);f.p.aboutToDisappear()});
  await test(kind+' disappear unsubscribes and repeated appearance does not multiply notifications',async()=>{const f=viewSetup(kind);f.p.aboutToAppear();f.p.aboutToAppear();await tick();const before=f.e.sourceCalls.length;f.e.signal.notify();await tick();assert.equal(f.e.sourceCalls.length-before,1);f.p.aboutToDisappear();const scans=f.e.sourceCalls.length;f.e.signal.notify();await tick();assert.equal(f.e.sourceCalls.length,scans)});
  await test(kind+' repeated notify old response cannot replace latest library state',async()=>{const f=viewSetup(kind);f.p.aboutToAppear();await tick();const first=deferred(),second=deferred();let calls=0;f.e.local.explorePages[0].loadPage=()=>++calls===1?first.promise:second.promise;f.e.signal.notify();await tick();f.e.signal.notify();await tick();second.resolve(f.e.ok([]));await tick();first.resolve(f.e.ok([{id:'old'}]));await tick();assert.equal(f.rows().length,0);f.p.aboutToDisappear()});
  await test(kind+' host watcher before component appearance cannot start work',async()=>{const f=viewSetup(kind);f.p.active=true;f.p.hostRevision++;f.p.onHostChanged();await tick();assert.deepEqual(f.e.db,{history:0,favorites:0,folders:0});assert.equal(f.e.sourceCalls.length,0)});
  await test(kind+' hiding during database listing prevents subsequent list and cover work',async()=>{const f=viewSetup(kind),gate=deferred();f.activate();if(kind==='home')f.e.c.HistoryDao.list=()=>{f.e.db.history++;return gate.promise};else f.e.c.FavoritesDao.listFolders=()=>{f.e.db.folders++;return gate.promise};const old=f.full();await tick();f.hide();gate.resolve([]);await old;assert.equal(f.e.db.favorites,0);assert.equal(f.e.sourceCalls.length,0)});
  await test(kind+' old full refresh finally cannot stop a newer visible refresh spinner',async()=>{const f=viewSetup(kind),oldGate=deferred(),newGate=deferred();f.activate();let calls=0;f.e.c.AppInit.init=()=>{calls++;return calls===1?oldGate.promise:calls===2?newGate.promise:Promise.resolve()};const old=f.full();await tick();f.hide();f.p.active=true;f.p.onHostChanged();await tick();assert.equal(f.p.loading,true);oldGate.resolve();await old;const stillLoading=f.p.loading;newGate.resolve();await tick();assert.equal(stillLoading,true);assert.equal(f.p.loading,false)});
 }
 await test('Index entry show/hide toggles resident-tab active bridge and increments refresh revision',async()=>{const e=environment(),p=e.index();const old=p.hostRevision;p.onPageHide();assert.equal(p.hostVisible,false);p.onPageShow();assert.equal(p.hostVisible,true);assert.equal(p.hostRevision,old+1);const s=read('entry/src/main/ets/pages/Index.ets');assert.match(s,/HomeView\([\s\S]*?hostRevision: this\.hostRevision, active: this\.hostVisible && this\.currentIndex === 0/);assert.match(s,/BookshelfView\([\s\S]*?hostRevision: this\.hostRevision, active: this\.hostVisible && this\.currentIndex === 1/)});
 await test('Home local strip source structure uses all items in horizontal Scroll and no slice six',async()=>{const s=read('entry/src/main/ets/features/HomeView.ets'),start=s.indexOf('  localStrip()'),end=s.indexOf('  build()',start),strip=s.slice(start,end);assert.match(strip,/Scroll\(\)/);assert.match(strip,/ForEach\(this\.localComics,/);assert.match(strip,/ScrollDirection\.Horizontal/);assert.doesNotMatch(strip,/slice\(/);assert.doesNotMatch(s,/localComics\.slice/);const f=viewSetup('home');for(let i=0;i<9;i++)f.e.comic('real-'+i);f.p.aboutToAppear();await tick();assert.equal(f.rows().length,9);f.p.aboutToDisappear()});
 await test('production queue completion and deletion signal refresh Home against same fake filesystem',async()=>{const q=require('./download_test_harness').downloads(),e=environment();e.c.fs=q.ctx.fs;q.ctx.LocalLibrarySignal=e.signal;const home=e.home();home.aboutToAppear();await tick();assert.equal(home.localComics.length,0);const task=await q.Queue.add('fixture','comic');await q.Queue.resume(task.id);await tick();assert.equal(home.localComics.length,1);const before=q.calls.length;await q.Queue.deleteTask(task.id);await tick();assert.equal(home.localComics.length,0);assert.equal(q.calls.length,before);home.aboutToDisappear()});
 await test('production queue deletion refreshes Bookshelf while preserving unrelated imported comic',async()=>{const q=require('./download_test_harness').downloads(),e=environment();e.c.fs=q.ctx.fs;q.ctx.LocalLibrarySignal=e.signal;q.dirs.add('/app/files/local_comics/imported');q.files.set('/app/files/local_comics/imported/1.png','image');const shelf=e.shelf();shelf.aboutToAppear();await tick();assert.equal(shelf.localComics.length,1);const task=await q.Queue.add('fixture','comic');await q.Queue.resume(task.id);await tick();assert.equal(shelf.localComics.length,2);await q.Queue.deleteTask(task.id);await tick();assert.equal(shelf.localComics.length,1);assert.equal(shelf.localComics[0].id,'imported');assert.equal(q.files.has('/app/files/local_comics/imported/1.png'),true);shelf.aboutToDisappear()});
 assert.equal(count,EXPECTED,'fixed final case count');finished=true;
 const report=`${failures.length?'FAIL':'PASS'} ${passed}/${EXPECTED} local library refresh cases; executed=${count}; local production-method fixtures only; no SDK/device/network/user data.`;
 console.log(report);fs.appendFileSync(log,report+'\n');
 if(failures.length){for(const f of failures)console.error('FAIL '+f.name+'\n'+f.error);process.exitCode=1;}
})().catch(error=>{console.error(error);fs.appendFileSync(log,String(error.stack)+'\n');process.exitCode=1});
