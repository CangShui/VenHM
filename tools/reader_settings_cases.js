'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/reader-settings-cases.log');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
let count=0;fs.writeFileSync(log,'Production ReaderSettings logic; Preferences fake, no real RDB/phone settings acceptance.\n');
function env(initial={}){
  const values=new Map(Object.entries(initial)),writes=[];let fail=false,gate;
  const ctx=vm.createContext({Settings:{
    getString:(key,fallback)=>typeof values.get(key)==='string'?values.get(key):fallback,
    getInt:(key,fallback)=>typeof values.get(key)==='number'?Math.trunc(values.get(key)):fallback,
    getBool:(key,fallback)=>typeof values.get(key)==='boolean'?values.get(key):fallback,
    setString:async(key,value)=>{writes.push({key,value});if(gate)await gate;if(fail){fail=false;throw Error('synthetic disk flush failure')}values.set(key,value)}
  }});
  vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/features/ReaderModes.ets')+'\n'+read('entry/src/main/ets/foundation/ReaderSettings.ets'),{mode:'transform'})+'\nglobalThis.Subject=ReaderSettings;',ctx);
  return {ctx,s:ctx.Subject,values,writes,fail:()=>{fail=true},gate:p=>{gate=p}};
}
async function test(name,run){await run();count++;fs.appendFileSync(log,`TraceID=reader-settings-tests [PASS] ${name}\n`)}
(async()=>{
  await test('fresh profile matches implemented upstream defaults',async()=>{
    const e=env(),o=e.s.resolve('comic','source');assert.equal(o.readerMode,'waterfallTopToBottom');
    assert.equal(o.autoPageTurningInterval,5);assert.equal(o.readerScreenPicNumberForPortrait,1);assert.equal(o.splitDualPage,false);
    assert.equal(o.autoReadingAcrossChapters,true);assert.equal(o.enableDoubleTapToZoom,true);
  });
  await test('existing HM mode and explicit legacy interval preserved without rewriting keys',async()=>{
    const e=env({readerMode:'galleryRightToLeft',autoReadIntervalSeconds:30});const o=e.s.resolve('comic','source');
    assert.equal(o.readerMode,'galleryRightToLeft');assert.equal(o.autoPageTurningInterval,10);assert.equal(e.writes.length,0);
    await e.s.set('global','','','autoPageTurningInterval',7);assert.equal(e.s.resolve('comic','source').autoPageTurningInterval,7);
    assert.equal(e.values.get('autoReadIntervalSeconds'),30);
  });
  await test('false/zero overrides remain values rather than inherit',async()=>{
    const e=env();await e.s.set('global','','','readerSideMargin',12);await e.s.set('global','','','splitDualPage',true);
    await e.s.setEnabled('comic',true,'comic','source');await e.s.set('comic','comic','source','readerSideMargin',0);
    await e.s.set('comic','comic','source','splitDualPage',false);const o=e.s.resolve('comic','source');assert.equal(o.readerSideMargin,0);assert.equal(o.splitDualPage,false);
  });
  await test('global/device/comic precedence and layer previews work independently',async()=>{
    const e=env();await e.s.set('global','','','readerSideMargin',3);await e.s.set('device','','','readerSideMargin',6);await e.s.setEnabled('device',true);
    await e.s.set('comic','comic','source','readerSideMargin',9);await e.s.setEnabled('comic',true,'comic','source');
    assert.equal(e.s.resolve('comic','source').readerSideMargin,9);assert.equal(e.s.resolveForScope('global','comic','source').readerSideMargin,3);
    assert.equal(e.s.resolveForScope('device','comic','source').readerSideMargin,6);await e.s.setEnabled('comic',false,'comic','source');assert.equal(e.s.resolve('comic','source').readerSideMargin,6);
    await e.s.setEnabled('device',false);assert.equal(e.s.resolve('comic','source').readerSideMargin,3);
  });
  await test('comic mode override independent of other-profile switch; explicit inheritance clears legacy mode',async()=>{
    const e=env();await e.s.set('global','','','readerMode','galleryLeftToRight');await e.s.set('comic','comic','source','readerMode','galleryTopToBottom');
    assert.equal(e.s.enabled('comic','comic','source'),false);assert.equal(e.s.resolve('comic','source').readerMode,'galleryTopToBottom');
    await e.s.set('comic','comic','source','readerModeOverride','default');assert.equal(e.s.resolve('comic','source').readerMode,'galleryLeftToRight');
  });
  await test('source/comic identity encoding cannot collide and unrelated profiles unchanged',async()=>{
    const e=env();await e.s.setEnabled('comic',true,'c:a','s');await e.s.set('comic','c:a','s','readerSideMargin',8);
    assert.equal(e.s.resolve('a','s:c').readerSideMargin,0);assert.equal(e.s.resolve('c:a','s').readerSideMargin,8);
    await e.s.reset('comic','a','s:c');assert.equal(e.s.resolve('c:a','s').readerSideMargin,8);
  });
  await test('invalid type/nonfinite/fractional/range and unknown option reject without writes',async()=>{
    const e=env();for(const [key,value]of[['readerSideMargin',31],['readerSideMargin',1.5],['readerSideMargin',NaN],['readerScreenPicNumberForPortrait',0],['autoPageTurningInterval',21],['splitDualPage','true'],['readerMode','nonsense'],['unsupportedFakeToggle',true]]){
      await assert.rejects(e.s.set('global','','',key,value));
    }assert.equal(e.writes.length,0);
  });
  await test('awaited ordered writes preserve intermediate updates and do not publish before flush',async()=>{
    const e=env();let release;e.gate(new Promise(r=>release=r));const first=e.s.set('global','','','readerSideMargin',4),second=e.s.set('global','','','splitDualPage',true);
    await new Promise(r=>setImmediate(r));assert.equal(e.s.resolve('comic','source').readerSideMargin,0);assert.equal(e.writes.length,1);
    release();await Promise.all([first,second]);const o=e.s.resolve('comic','source');assert.equal(o.readerSideMargin,4);assert.equal(o.splitDualPage,true);
  });
  await test('queued active write resolves scope after preceding enable commit, not before',async()=>{
    const e=env();let release;e.gate(new Promise(r=>release=r));const enable=e.s.setEnabled('device',true);
    const update=e.s.setActive('comic','source','readerSideMargin',7);await new Promise(r=>setImmediate(r));release();await Promise.all([enable,update]);
    assert.equal(e.s.resolve('comic','source').readerSideMargin,7);assert.equal(e.s.resolveForScope('global','comic','source').readerSideMargin,0);
  });
  await test('flush failure rolls back confirmed state and next write can recover',async()=>{
    const e=env();await e.s.set('global','','','readerSideMargin',4);e.fail();await assert.rejects(e.s.set('global','','','readerSideMargin',8));
    assert.equal(e.s.resolve('comic','source').readerSideMargin,4);await e.s.set('global','','','readerSideMargin',9);assert.equal(e.s.resolve('comic','source').readerSideMargin,9);
  });
  await test('active writes follow enabled scope and independent comic mode override',async()=>{
    const e=env();await e.s.setEnabled('device',true);await e.s.setActive('comic','source','readerSideMargin',8);assert.equal(e.s.resolveForScope('global','comic','source').readerSideMargin,0);
    await e.s.set('comic','comic','source','readerMode','galleryLeftToRight');await e.s.setActive('comic','source','readerMode','galleryRightToLeft');
    assert.equal(e.s.resolve('comic','source').readerMode,'galleryRightToLeft');assert.equal(e.s.resolveForScope('device','comic','source').readerMode,'waterfallTopToBottom');
  });
  await test('global explicit reset restores original defaults without deleting legacy/history or comic values',async()=>{
    const e=env({readerMode:'galleryRightToLeft',historyMarker:'keep'});await e.s.set('comic','comic','source','readerMode','galleryLeftToRight');
    await e.s.set('global','','','splitDualPage',true);await e.s.reset('global');assert.equal(e.s.resolve('other','source').readerMode,'waterfallTopToBottom');
    assert.equal(e.s.resolve('comic','source').readerMode,'galleryLeftToRight');assert.equal(e.values.get('readerMode'),'galleryRightToLeft');assert.equal(e.values.get('historyMarker'),'keep');
  });
  await test('persisted profile cold-loads with same local device identity and confirmed options',async()=>{
    const e=env();await e.s.setEnabled('device',true);await e.s.set('device','','','readerSideMargin',11);
    const cold=env(Object.fromEntries(e.values));assert.equal(cold.s.resolve('comic','source').readerSideMargin,11);
    assert.equal(cold.s.load().deviceKey,e.s.load().deviceKey);
  });
  await test('malformed/future profile rejected without overwriting preferences',async()=>{
    for(const record of ['{}','{"version":2}','{"version":1,"deviceKey":"x","global":{},"devices":{"x":{"enabled":"yes","values":{}}},"comics":{}}']){
      const e=env({readerSettingsV1:record});assert.throws(()=>e.s.resolve('comic','source'));assert.equal(e.writes.length,0);assert.equal(e.values.get('readerSettingsV1'),record);
    }
  });
  console.log(`PASS ${count} production scoped reader settings cases; Preferences/ArkUI/device still separate.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
