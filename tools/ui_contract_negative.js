'use strict';
// Negative control: build a deliberately broken mini-project and prove the UI
// contract harness fails on it. Without this, a green run could be vacuous.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const tmp=path.join(root,'logs','ui-contract-negative');
fs.rmSync(tmp,{recursive:true,force:true});
const put=(rel,body)=>{const f=path.join(tmp,rel);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,body)};
const ets='entry/src/main/ets';

// Registered page A, but its button routes to an unregistered page.
put(`${ets}/pages/A.ets`,`@Entry\n@Component\nstruct A {\n  build() {\n    Column() {\n      Button('go').onClick(() => { router.pushUrl({ url: 'pages/Ghost' }); })\n    }\n  }\n}\n`);
put(`${ets}/features/SearchView.ets`,``);
put(`${ets}/features/ExploreView.ets`,``);
put(`${ets}/features/CategoryView.ets`,``);
put(`${ets}/features/AggregatedSearchSession.ets`,``);
put(`${ets}/features/AggregatedSearchList.ets`,``);
put(`${ets}/features/BackgroundDownloadCoordinator.ets`,``);
put(`${ets}/features/DownloadQueue.ets`,``);
put('entry/src/main/resources/base/profile/main_pages.json',JSON.stringify({src:['pages/A']}));

const run=cp.spawnSync(process.execPath,[path.join(__dirname,'ui_contract_cases.js')],
  {cwd:__dirname,encoding:'utf8',env:Object.assign({},process.env,{UI_CONTRACT_ROOT:tmp})});
const out=(run.stdout||'')+(run.stderr||'');
assert.equal(run.status,1,'broken project must fail the contract harness');
assert.match(out,/unregistered pages\/Ghost/,'ghost route was not reported');
assert.match(out,/UI_CONTRACT_FAIL/,'no failure summary emitted');
console.log('PASS negative control: broken route detected, harness exits 1');
console.log('UI_CONTRACT_NEGATIVE_PASS; no production file changed, no device/network');
