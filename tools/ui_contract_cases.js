'use strict';
// Device-free UI contract checks: catches the class of regressions that would
// otherwise only surface on a phone (missing entry control, route pointing at a
// deleted page, one tab drifting off the shared source, a resurrected blind stop).
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
// UI_CONTRACT_ROOT lets a negative control run this same logic against a
// deliberately broken tree, proving the checks can actually fail.
const root=process.env.UI_CONTRACT_ROOT?path.resolve(process.env.UI_CONTRACT_ROOT):path.resolve(__dirname,'..');
// Keep the evidence log in the real workspace even when checking a temp tree.
const log=path.join(path.resolve(__dirname,'..'),'logs/ui-contract-cases.log');
fs.writeFileSync(log,'UI contract/route integrity from production sources; no rendering, device, network or account.\n');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const walk=(dir,out=[])=>{for(const e of fs.readdirSync(path.join(root,dir),{withFileTypes:true})){
  const rel=`${dir}/${e.name}`;if(e.isDirectory())walk(rel,out);else if(e.name.endsWith('.ets'))out.push(rel);}return out};
const files=walk('entry/src/main/ets');
let count=0;const fail=[];
function test(name,body){try{body();count++;console.log('PASS '+name);fs.appendFileSync(log,'PASS '+name+'\n')}
 catch(error){fail.push(name);console.error('FAIL '+name+' :: '+(error&&error.message));fs.appendFileSync(log,'FAIL '+name+' :: '+(error&&error.message)+'\n')}}

const pages=JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src;

test('every registered page exists as a file with a matching @Entry struct',()=>{
  for(const page of pages){
    const file=`entry/src/main/ets/${page}.ets`;
    assert.ok(fs.existsSync(path.join(root,file)),`registered page missing file: ${page}`);
    const code=read(file);const struct=page.split('/').pop();
    assert.match(code,new RegExp(`@Entry[\\s\\S]{0,80}struct ${struct}\\b`),`${page} has no @Entry struct ${struct}`);
  }
});

test('every router.pushUrl target is registered and backed by a real page',()=>{
  const registered=new Set(pages);
  for(const file of files){
    const code=read(file);
    const re=/router\.(?:pushUrl|replaceUrl)\(\s*\{\s*url:\s*'([^']+)'/g;let m;
    while((m=re.exec(code))!==null){
      const target=m[1];assert.ok(registered.has(target),`${file} routes to unregistered ${target}`);
      assert.ok(fs.existsSync(path.join(root,`entry/src/main/ets/${target}.ets`)),`${file} routes to missing ${target}`);
    }
  }
});

test('no source references the removed standalone aggregate page',()=>{
  for(const file of files){
    const code=read(file);
    assert.doesNotMatch(code,/AggregatedSearchPage/,'stale reference to removed aggregate page in '+file);
  }
});

test('search exposes aggregate inside the source dropdown and has no separate aggregate button',()=>{
  const code=read('entry/src/main/ets/features/SearchView.ets');
  assert.match(code,/aggregateLabel: string = '聚合搜索（全部源）'/,'aggregate dropdown label missing');
  assert.match(code,/this\.sourceOptions = \[this\.aggregateLabel\]\.concat/,'aggregate is not first dropdown option');
  assert.doesNotMatch(code,/Button\('聚合'\)/,'standalone aggregate button still present');
  assert.match(code,/Select\(this\.sourceOptions/,'source dropdown not rendered from shared option list');
});

test('search, explore and category all bind the one shared SelectedSource',()=>{
  for(const [file,label] of [['entry/src/main/ets/features/SearchView.ets','search'],
    ['entry/src/main/ets/features/ExploreView.ets','explore'],
    ['entry/src/main/ets/features/CategoryView.ets','category']]){
    const code=read(file);
    assert.match(code,/SelectedSource\./,'%s does not use SelectedSource'.replace('%s',label));
    assert.match(code,/SelectedSource\.subscribe\(/,'%s does not subscribe to shared source'.replace('%s',label));
    assert.match(code,/SelectedSource\.select\(/,'%s never publishes its own selection'.replace('%s',label));
  }
});

test('removing or degrading a source never silently rewrites the shared key',()=>{
  const code=read('entry/src/main/ets/features/SearchView.ets');
  assert.doesNotMatch(code,/SelectedSource\.select\(this\.sourceKeys\[0\]\)/,'search still silently swaps to another source');
  assert.match(code,/原先选择的源已移除/,'removed-source notice missing');
  assert.match(code,/不支持搜索/,'non-searchable source notice missing');
});

test('aggregate session has no artificial concurrency ceiling',()=>{
  const code=read('entry/src/main/ets/features/AggregatedSearchSession.ets');
  assert.doesNotMatch(code,/active\s*<\s*3/,'three-source ceiling still present');
  assert.doesNotMatch(code,/private active: number/,'leftover active counter');
  assert.match(code,/while \(this\.tasks\.length > 0\)/,'pump no longer drains all queued sources');
});

test('aggregate list updates only changed partitions through LazyForEach',()=>{
  const view=read('entry/src/main/ets/features/SearchView.ets');
  assert.match(view,/LazyForEach\(this\.aggregateList/,'aggregate groups are not lazy-rendered');
  const list=read('entry/src/main/ets/features/AggregatedSearchList.ets');
  assert.match(list,/implements IDataSource/,'aggregate list is not a real data source');
  assert.match(list,/onDataChanged\(index\)/,'aggregate list never sends partial updates');
});

test('background task uses the documented DATA_TRANSFER submode and no blind recovery',()=>{
  const code=read('entry/src/main/ets/features/BackgroundDownloadCoordinator.ets');
  assert.match(code,/SUBMODE_LIVE_VIEW_NOTIFICATION/,'DATA_TRANSFER submode missing');
  assert.doesNotMatch(code,/backgroundTaskSubmodes\s*=\s*\[\s*\]/,'empty submode array reintroduced');
  assert.doesNotMatch(code,/startWithRecovery/,'blind stale-task retry reintroduced');
  assert.doesNotMatch(code,/stopBackgroundRunning\(AppContext\.context\)/,'all-task stop without exact id reintroduced');
});

test('a refused background lease still lets an explicit foreground download run',()=>{
  const code=read('entry/src/main/ets/features/DownloadQueue.ets');
  assert.match(code,/if \(!DownloadQueue\.foreground\)/,'foreground fallback branch missing');
  assert.match(code,/后台许可不可用/,'foreground fallback audit missing');
});

test('download control keeps generation and late-runner ownership',()=>{
  const code=read('entry/src/main/ets/features/DownloadQueue.ets');
  assert.match(code,/private static live\(/,'generation liveness guard missing');
  assert.match(code,/DownloadQueue\.mutating/,'restart/delete mutual exclusion missing');
  assert.match(code,/await request;/,'restart/delete no longer awaits the old runner');
});

test('every page with buttons wires a handler and no page is left as a stub',()=>{
  for(const page of pages){
    const code=read(`entry/src/main/ets/${page}.ets`);
    const buttons=(code.match(/Button\(/g)||[]).length;
    if(buttons>0){assert.match(code,/\.onClick\(/,'%s has buttons but no onClick'.replace('%s',page));}
    assert.doesNotMatch(code,/TODO|FIXME/,'%s still contains TODO/FIXME'.replace('%s',page));
  }
});

test('app icon uses the layered icon with real upstream 1024 layers',()=>{
  const app=read('AppScope/app.json5');
  assert.match(app,/"icon":\s*"\$media:layered_image"/,'app icon is not the layered icon');
  const cfg=JSON.parse(read('AppScope/resources/base/media/layered_image.json'))['layered-image'];
  for(const key of ['background','foreground']){
    assert.ok(cfg[key],`layered icon missing ${key}`);
    const file=`AppScope/resources/base/media/${cfg[key].split(':').pop()}.png`;
    assert.ok(fs.existsSync(path.join(root,file)),`layered ${key} file missing: ${file}`);
    const size=fs.statSync(path.join(root,file)).size;
    assert.ok(size>3000,`layered ${key} looks like a placeholder (${size} bytes)`);
  }
});

test('share payload receives the comic id and source domain so the original site is shared',()=>{
  const code=read('entry/src/main/ets/pages/ComicDetailsPage.ets');
  assert.match(code,/DetailsSharePayload\.create\([^)]*this\.comicId/,'share does not pass the comic id fallback');
  assert.match(code,/linkHandler\?\.domains/,'share does not fall back to the source site domain');
  assert.doesNotMatch(code,/DetailsSharePayload\.create\([^)]*pages\//,'share must never use an app route');
});

const total=14;
assert.equal(count+fail.length,total,`expected ${total} checks, ran ${count+fail.length}`);
if(fail.length>0){console.error(`UI_CONTRACT_FAIL ${fail.length}/${total}`);process.exitCode=1}
else console.log(`PASS ${count} production UI-contract/route/shared-source/background checks; no rendering, device or network.`);
