'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/cookie-schema-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=cookie-schema-tests production additive migration, SQL store mocked; not native RDB acceptance\n');
const raw=fs.readFileSync(path.join(root,'entry/src/main/ets/storage/Database.ets'),'utf8');
const source=raw.replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
const ctx=vm.createContext({Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}});
vm.runInContext(stripTypeScriptTypes(source,{mode:'transform'})+'\nglobalThis.DB=Database;',ctx);
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=cookie-schema-tests PASS ${name}\n`)}
function store(names){
  const sql=[],data=new Map([['existing',{value:'synthetic',path:'/restricted'}]]);let closed=false;
  return {sql,data,get closed(){return closed},executeSql:async q=>{sql.push(q);if(q.startsWith('ALTER'))names.push('same_site')},
    querySql:async q=>{assert.equal(q,'PRAGMA table_info(cookies)');let index=-1;
      return {goToNextRow:()=>++index<names.length,getColumnIndex:()=>0,getString:()=>names[index],close:()=>closed=true}}};
}
(async()=>{
  await test('old cookies table gains only default-empty SameSite, credential rows unchanged',async()=>{
    const s=store(['name','value','domain','path','host_only','secure','http_only','expires_at_ms']);
    const before=JSON.stringify([...s.data]);await ctx.DB.ensureCookieSchema(s);
    assert.equal(s.sql.filter(q=>q.startsWith('ALTER')).length,1);assert.equal(JSON.stringify([...s.data]),before);
    assert.ok(s.sql.every(q=>!/\bDELETE\b|\bDROP\b/i.test(q)));assert.equal(s.closed,true);
  });
  await test('already-migrated table is idempotent; no duplicate ALTER',async()=>{
    const s=store(['name','same_site']);await ctx.DB.ensureCookieSchema(s);await ctx.DB.ensureCookieSchema(s);
    assert.equal(s.sql.filter(q=>q.startsWith('ALTER')).length,0);
  });
  await test('schema read failure propagates, never followed by destructive repair',async()=>{
    const s=store(['name']);s.querySql=async()=>{throw Error('RDB busy')};
    await assert.rejects(ctx.DB.ensureCookieSchema(s));assert.equal(s.sql.length,1);
  });
  await test('actual production startup invokes cookie migration before jar loading',async()=>{
    assert.match(raw,/await Database\.ensureCookieSchema\(store\)/);
    const startup=fs.readFileSync(path.join(root,'entry/src/main/ets/foundation/AppInit.ets'),'utf8');
    assert.ok(startup.indexOf('await Database.init()')<startup.indexOf('await CookieJar.init()'));
  });
  console.log(`PASS ${count} production cookie schema migration cases; device RDB cold reload still pending.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
