'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..');
const log = path.join(root, 'logs', 'source-settings-cases.log');
fs.mkdirSync(path.dirname(log), { recursive: true });
fs.writeFileSync(log, '[请求到达] TraceID=settings-tests production logic, fake JS/DB; no real accounts\n');
function load(relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
}
let page = load('entry/src/main/ets/pages/SourceSettingsPage.ets');
page = (page.slice(0, page.indexOf('  build() {')) + '}')
  .replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace('struct SourceSettingsPage', 'class SourceSettingsPage');
const code = [
  load('entry/src/main/ets/source/AuthLogScope.ets'),
  load('entry/src/main/ets/source/SourceDataStore.ets'),
  load('entry/src/main/ets/source/SourceSettings.ets'), page
].map(s => stripTypeScriptTypes(s, { mode: 'transform' })).join('\n');
const tick = () => new Promise(resolve => setImmediate(resolve));
let count = 0;
function env() {
  const db = new Map(), sqlCalls = [], audits = [], toasts = [], failures = [];
  let gate;
  const scope = {
    console,
    Log: {
      audit: (trace, stage, message) => {
        audits.push(message);
        fs.appendFileSync(log, `TraceID=${trace} [${stage}] ${message}\n`);
      },
      warn: (tag, message) => fs.appendFileSync(log, `[警告] ${tag} ${message}\n`),
      error: (tag, message) => fs.appendFileSync(log, `[异常] ${tag} ${message}\n`)
    },
    Database: {
      execute: async (sql, args) => {
        sqlCalls.push({ sql, args });
        if (gate) await gate;
        if (failures.shift()) throw new Error('fixture DB failure');
        const key = args[0] + '\0' + args[1];
        if (sql.startsWith('DELETE')) db.delete(key);
        else db.set(key, args[2]);
      },
      query: async (sql, args) => {
        const rows = [...db].filter(([key]) => key.startsWith(args[0] + '\0'));
        let index = -1;
        return {
          goToNextRow: () => ++index < rows.length,
          getColumnIndex: name => name === 'data_key' ? 0 : 1,
          getString: col => col === 0 ? rows[index][0].split('\0')[1] : rows[index][1],
          close: () => {}
        };
      }
    },
    promptAction: { showToast: data => toasts.push(data.message) },
    AppInit: { init: async () => {} },
    SourceManager: { find: key => ({ key, name: 'fixture' }) },
    ComicSource: { sources: {} },
  };
  vm.createContext(scope);
  scope.JsEngine = { callJson: async script => await vm.runInContext(script, scope) };
  vm.runInContext(code + '\nglobalThis.Store=SourceDataStore;globalThis.Service=SourceSettings;globalThis.Page=SourceSettingsPage;', scope);
  scope.readSetting = key => scope.Store.get('fixture', 'settings')?.[key];
  vm.runInContext(`
    ComicSource.sources.fixture = {revision:0, get settings() {
      const source=this;
      return {
        input:{type:'input',title:'Input',default:'ok',validator:'^ok$'},
        mode:{type:'switch',title:'Mode',default:false},
        choice:{type:'select',title:'Choice-'+source.revision,default:0,
          get options(){ return readSetting('mode') ? [{value:false,text:'False'},{value:'new',text:'New'}]
            : [{value:0,text:'Zero'},{value:'0',text:'String zero'}]; }},
        extended:{type:'input',title:'Extended',required:'42',
          validator:async function(v){return v===this.required ? null : 'Need 42';}},
        reset:{type:'callback',title:'Reset',token:'receiver',
          callback:async function(){if(this.token!=='receiver')throw Error('wrong receiver');source.revision++;}},
        invalid:{type:'select',options:[{value:{bad:true},text:'bad'}]},
        empty:{type:'select',options:[],default:'gone'}
      };
    }};
  `, scope);
  return {
    ...scope, context: scope, db, sqlCalls, audits, toasts, failures,
    setGate: promise => { gate = promise; }
  };
}
async function check(name, action) {
  fs.appendFileSync(log, `[业务入口] TraceID=settings-tests case=${name}\n`);
  await action();
  count++;
  fs.appendFileSync(log, `[响应返回] TraceID=settings-tests PASS ${name}\n`);
}

(async () => {
  await check('read settings/options getters preserves number and string types', async () => {
    const e=env(), fields=await e.Service.read('fixture','read');
    const choice=fields.find(f=>f.key==='choice');
    assert.equal(choice.options[0].value,0);
    assert.equal(choice.options[1].value,'0');
    assert.notEqual(choice.options[0].value,choice.options[1].value);
  });
  await check('invalid field cannot hide valid fields', async () => {
    const e=env(), fields=await e.Service.read('fixture','read');
    assert.ok(fields.find(f=>f.key==='invalid').schemaError);
    assert.equal(fields.find(f=>f.key==='input').schemaError,'');
    assert.equal(fields.find(f=>f.key==='empty').options.length,0);
  });
  await check('saved false and zero override defaults', async () => {
    const e=env(), fields=await e.Service.read('fixture','read');
    const mode=fields.find(f=>f.key==='mode'),choice=fields.find(f=>f.key==='choice');
    mode.defaultValue=true;
    assert.equal(e.Service.effective(mode,{mode:false}),false);
    choice.defaultValue=7;
    assert.equal(e.Service.effective(choice,{choice:0}),0);
  });
  await check('missing selection remains -1, never picks first option silently', async () => {
    const e=env(), fields=await e.Service.read('fixture','read');
    assert.equal(e.Service.selectedIndex(fields.find(f=>f.key==='choice'),{choice:'missing'}),-1);
    assert.equal(e.Service.selectedIndex(fields.find(f=>f.key==='choice'),{choice:'0'}),1);
  });
  await check('regex validation passes and rejects before saving', async () => {
    const e=env();
    assert.equal(await e.Service.validate('fixture','input','ok','regex'),'');
    assert.equal(await e.Service.validate('fixture','input','no','regex'),'输入格式不正确');
    assert.equal(e.sqlCalls.length,0);
  });
  await check('function validator retains receiver and awaits async result', async () => {
    const e=env();
    assert.equal(await e.Service.validate('fixture','extended','42','func'),'');
    assert.equal(await e.Service.validate('fixture','extended','41','func'),'Need 42');
  });
  await check('validator values are safely quoted and excluded from logs', async () => {
    const e=env(), value='credential-test-secret-value"); globalThis.injected=true; //';
    await e.Service.validate('fixture','input',value,'quote');
    assert.equal(e.context.injected,undefined);
    assert.ok(!e.audits.join('\n').includes('credential-test-secret-value'));
  });
  await check('invalid regex rejects with an exception', async () => {
    const e=env();
    vm.runInContext("ComicSource.sources.fixture={settings:{input:{validator:'['}}}",e.context);
    await assert.rejects(e.Service.validate('fixture','input','x','invalid'));
  });
  await check('boolean validator result is not silently treated as acceptance', async () => {
    const e=env();
    vm.runInContext("ComicSource.sources.fixture={settings:{input:{validator:()=>true}}}",e.context);
    await assert.rejects(e.Service.validate('fixture','input','x','bool'));
  });
  await check('callback preserves receiver and fresh read updates title', async () => {
    const e=env();
    await e.Service.runCallback('fixture','reset','callback');
    const fields=await e.Service.read('fixture','read');
    assert.equal(fields.find(f=>f.key==='choice').title,'Choice-1');
  });
  await check('commit waits for database and rerun observes dynamic options', async () => {
    const e=env();
    let release; e.setGate(new Promise(r=>release=r));
    let done=false;
    const write=e.Service.commit('fixture','mode',true,'save').then(()=>{done=true;});
    await tick();
    assert.equal(done,false);
    release(); await write; e.setGate(undefined);
    const fields=await e.Service.read('fixture','read');
    assert.equal(fields.find(f=>f.key==='choice').options[0].value,false);
    assert.equal(JSON.parse(e.db.get('fixture\0settings')).mode,true);
  });
  await check('synchronous script set sees cache immediately', async () => {
    const e=env();
    e.Store.set('fixture','data',{value:1});
    assert.equal(e.Store.get('fixture','data').value,1);
    await tick();
    assert.equal(JSON.parse(e.db.get('fixture\0data')).value,1);
  });
  await check('writes are serialized and preserve latest value', async () => {
    const e=env(); let release;
    e.setGate(new Promise(r=>release=r));
    const first=e.Store.setAndWait('fixture','data',{value:1},'a');
    const second=e.Store.setAndWait('fixture','data',{value:2},'b');
    await tick();
    assert.equal(e.sqlCalls.length,1);
    release(); await Promise.all([first,second]);
    assert.equal(JSON.parse(e.db.get('fixture\0data')).value,2);
  });
  await check('failed write restores last durable value, not transient cache', async () => {
    const e=env();
    await e.Store.setAndWait('fixture','data',{value:0},'baseline');
    e.failures.push(true,true);
    const a=e.Store.setAndWait('fixture','data',{value:1},'bad-a');
    const b=e.Store.setAndWait('fixture','data',{value:2},'bad-b');
    await Promise.allSettled([a,b]);
    assert.equal(e.Store.get('fixture','data').value,0);
    assert.equal(JSON.parse(e.db.get('fixture\0data')).value,0);
    await e.Store.setAndWait('fixture','data',{value:3},'recovery');
    assert.equal(e.Store.get('fixture','data').value,3);
  });
  await check('older failure does not undo newer pending value', async () => {
    const e=env(); e.failures.push(true,false);
    await Promise.allSettled([
      e.Store.setAndWait('fixture','data',{value:1},'a'),
      e.Store.setAndWait('fixture','data',{value:2},'b')
    ]);
    assert.equal(e.Store.get('fixture','data').value,2);
    assert.equal(JSON.parse(e.db.get('fixture\0data')).value,2);
  });
  await check('queued delete cannot be overwritten by older write', async () => {
    const e=env(); let release;
    e.setGate(new Promise(r=>release=r));
    e.Store.set('fixture','data',{value:1});
    e.Store.remove('fixture','data');
    release(); await tick();
    assert.equal(e.Store.get('fixture','data'),null);
    assert.equal(e.db.has('fixture\0data'),false);
  });
    await check('failed awaited delete restores confirmed value, not false logged-out state', async () => {
      const e=env();await e.Store.setAndWait('fixture','data',{value:9},'seed-delete');
      e.failures.push(true);
      await assert.rejects(e.Store.removeAndWait('fixture','data','failed-delete'));
      assert.equal(e.Store.get('fixture','data').value,9);
      assert.equal(JSON.parse(e.db.get('fixture\0data')).value,9);
    });
    await check('source persistence barrier catches swallowed script writes and allows fresh retry', async () => {
      const e=env();const start=e.Store.failureEpoch('fixture');e.failures.push(true);
      e.Store.set('fixture','token',{value:'synthetic'});
      await assert.rejects(e.Store.awaitSourceWrites('fixture',start,'token-barrier'));
      const retry=e.Store.failureEpoch('fixture');await e.Store.setAndWait('fixture','token',{value:'recovered'},'retry');
      await e.Store.awaitSourceWrites('fixture',retry,'retry-barrier');
    });
    await check('conditional login staging rollback never overwrites newer script data', async () => {
      const e=env();await e.Store.setAndWait('fixture','_localStorage',{old:1},'old');
      await e.Store.setAndWait('fixture','_localStorage',{staged:1},'stage');
      await e.Store.setAndWait('fixture','_localStorage',{newer:1},'newer');
      await e.Store.restoreIfCurrent('fixture','_localStorage',{staged:1},{old:1},'restore');
      assert.equal(e.Store.get('fixture','_localStorage').newer,1);
    });
  await check('input rejection keeps draft and does not save', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false;
    page.fields=await e.Service.read('fixture','read');
    page.drafts.set('input','bad');
    await page.saveInput(page.fields.find(f=>f.key==='input'));
    assert.match(page.error,/输入格式不正确/);
    assert.equal(e.sqlCalls.length,0);
    assert.equal(page.drafts.get('input'),'bad');
    assert.equal(page.busyKey,'');
  });
  await check('successful input saves then refreshes without losing other drafts', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false;
    page.fields=await e.Service.read('fixture','read');
    page.drafts.set('input','ok'); page.drafts.set('extended','unsaved');
    await page.saveInput(page.fields.find(f=>f.key==='input'));
    assert.equal(page.saved.input,'ok');
    assert.equal(page.drafts.has('input'),false);
    assert.equal(page.drafts.get('extended'),'unsaved');
    assert.equal(page.schemaRevision,1);
    assert.deepEqual(e.toasts,['已保存']);
  });
  await check('database failure never displays saved and retains draft', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false;
    page.fields=await e.Service.read('fixture','read');
    page.drafts.set('input','ok'); e.failures.push(true);
    await page.saveInput(page.fields.find(f=>f.key==='input'));
    assert.match(page.error,/fixture DB failure/);
    assert.equal(page.drafts.get('input'),'ok');
    assert.equal(e.toasts.length,0);
    assert.equal(page.busyKey,'');
  });
  await check('invalid selection index does not persist anything', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false;
    const fields=await e.Service.read('fixture','read');
    await page.choose(fields.find(f=>f.key==='choice'),99);
    assert.equal(e.sqlCalls.length,0);
  });
  await check('busy guard prevents overlapping edits', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false; page.busyKey='other';
    const fields=await e.Service.read('fixture','read');
    await page.saveInput(fields.find(f=>f.key==='input'));
    assert.equal(e.sqlCalls.length,0);
  });
  await check('page exit during validation prevents persistence', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.loading=false;
    const fields=await e.Service.read('fixture','read');
    const save=page.saveValue(fields.find(f=>f.key==='extended'),'42',true);
    page.aboutToDisappear();
    await save;
    assert.equal(e.sqlCalls.length,0);
  });
  await check('schema reread never clears unsubmitted draft', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture'; page.drafts.set('input','draft');
    await page.loadSettings();
    assert.equal(page.drafts.get('input'),'draft');
  });
  await check('async option function is awaited with its receiver', async () => {
    const e=env();
    vm.runInContext("ComicSource.sources.fixture={settings:{choice:{type:'select',id:'bound',options:async function(){return [{value:false,text:this.id}]}}}}",e.context);
    const fields=await e.Service.read('fixture','options');
    assert.equal(fields[0].options[0].value,false);
    assert.equal(fields[0].options[0].text,'bound');
  });
  await check('callback exception releases busy state without success toast', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture';page.loading=false;
    page.fields=await e.Service.read('fixture','read');
    vm.runInContext("ComicSource.sources.fixture={settings:{reset:{callback:async()=>{throw Error('callback failed')}}}}",e.context);
    await page.runCallback(page.fields.find(f=>f.key==='reset'));
    assert.match(page.error,/callback failed/);
    assert.equal(page.busyKey,'');
    assert.equal(e.toasts.length,0);
  });
  await check('outer getter failure is visible rather than an empty successful page', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture';
    vm.runInContext("ComicSource.sources.fixture={get settings(){throw Error('getter failed')}}",e.context);
    await page.loadSettings();
    assert.match(page.error,/getter failed/);
    assert.equal(page.loading,false);
  });
  await check('late schema load cannot overwrite a more recent refresh', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture';
    const pending=[];
    e.Service.read=()=>new Promise(resolve=>pending.push(resolve));
    const first=page.loadSettings('first');
    await tick();
    const second=page.loadSettings('second');
    await tick();
    pending[1]([{key:'new'}]);await second;
    pending[0]([{key:'old'}]);await first;
    assert.equal(page.fields[0].key,'new');
  });
  await check('successful persistence with failed reread shows the refresh error', async () => {
    const e=env(), page=new e.Page();
    page.sourceKey='fixture';page.loading=false;
    page.fields=await e.Service.read('fixture','read');
    e.Service.read=async()=>{throw new Error('refresh failed')};
    const field=page.fields.find(f=>f.key==='mode');
    await page.saveValue(field,true,false);
    assert.equal(e.Store.get('fixture','settings').mode,true);
    assert.match(page.error,/refresh failed/);
    assert.equal(e.toasts.length,0);
  });
  const summary=`PASS ${count} production source-setting/storage/page cases (not ArkUI rendering).`;
  fs.appendFileSync(log, `[响应返回] TraceID=settings-tests ${summary}\n`);
  console.log(summary);
})().catch(error=>{
  fs.appendFileSync(log, `[异常] TraceID=settings-tests ${error.stack}\n`);
  console.error(error); process.exitCode=1;
});
