'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/auth-log-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=auth-log-tests production sensitive source logging scope; synthetic credentials only\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
const outputs=[],ctx=vm.createContext({
  Log:{audit:(t,s,m)=>{outputs.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},
    info:(t,m)=>outputs.push({t,m}),warn:(t,m)=>outputs.push({t,m}),error:(t,m)=>outputs.push({t,m})}
});
vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/source/AuthLogScope.ets')+'\n'+
  read('entry/src/main/ets/source/JsMessageHandler.ets'),{mode:'transform'})+
  '\nglobalThis.Scope=AuthLogScope;globalThis.Handler=JsMessageHandler;',ctx);
let count=0;
function test(name,fn){fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=auth-log-tests PASS ${name}\n`)}
test('credential-bearing source title/content/arbitrary level omitted during auth',()=>{
  const frame=ctx.Scope.enter('auth-log-tests');
  ctx.Handler.handleMessage({method:'log',level:'fixture-password',title:'fixture-password',content:'fixture-password',__veneraTraceId:'auth-log-tests'});
  assert.equal(outputs[0].t,'auth-log-tests');assert.ok(!JSON.stringify(outputs).includes('fixture-password'));ctx.Scope.leave(frame);
});
test('nested Web check scope does not prematurely release outer login suppression',()=>{
  const outer=ctx.Scope.enter('outer'),inner=ctx.Scope.enter('inner');
  assert.equal(ctx.Scope.current(),'inner');ctx.Scope.leave(inner);assert.equal(ctx.Scope.current(),'outer');
  ctx.Scope.leave(outer);assert.equal(ctx.Scope.current(),undefined);
});
test('ordinary source logging resumes after scope exits',()=>{
  outputs.length=0;ctx.Handler.handleMessage({method:'log',level:'info',title:'public',content:'public diagnostic'});
  assert.ok(outputs.some(x=>x.m==='public diagnostic'));
});
test('late auth-owned callback remains redacted after root call completed',()=>{
  outputs.length=0;
  const frame=ctx.Scope.enter('old-auth');
  ctx.Scope.leave(frame);
  ctx.Handler.handleMessage({method:'log',level:'info',title:'fixture',content:'fixture-late-secret',__veneraTraceId:'old-auth'});
  assert.ok(!JSON.stringify(outputs).includes('fixture-late-secret'));
  assert.equal(ctx.Scope.current(),undefined);
});
console.log(`PASS ${count} production auth source-log scope cases; no real account test.`);
