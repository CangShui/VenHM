'use strict';
// Negative controls run mutated test code IN MEMORY, never production files.
// They prove a hung awaited promise cannot masquerade as a passing exit0.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),out=path.join(root,'logs/local-search-download-20261017');fs.mkdirSync(out,{recursive:true});
const cases=[
 {file:'background_download_cases.js',from:'Promise.race([run(),',to:'Promise.race([new Promise(()=>{}),',marker:'missing final background/queue PASS'},
 {file:'search_filters_cases.js',from:'Promise.resolve().then(body)',to:'new Promise(()=>{})',marker:'SEARCH_FILTERS_INCOMPLETE'}
];
for(const test of cases){
 let code=fs.readFileSync(path.join(__dirname,test.file),'utf8');assert.ok(code.includes(test.from),'test entry changed; revise negative control');
 code=code.replace(test.from,test.to).replace(/3000/g,'75');
 const stdout=path.join(out,'negative-'+test.file+'.stdout.log'),stderr=path.join(out,'negative-'+test.file+'.stderr.log');
 const o=fs.openSync(stdout,'w'),e=fs.openSync(stderr,'w');let child;
 try{child=cp.spawnSync(process.execPath,['--eval',code],{cwd:__dirname,timeout:5000,stdio:['ignore',o,e]});}finally{fs.closeSync(o);fs.closeSync(e)}
 assert.equal(child.error,undefined,'external watchdog fired; internal guard did not work');assert.equal(child.status,1,'unsettled test must fail');
 const errors=fs.readFileSync(stderr,'utf8');assert.match(errors,/WATCHDOG/);assert.ok(errors.includes(test.marker),'missing final-completion failure');
 console.log('PASS negative hung-promise control '+test.file+' failed deterministically, not false exit0');
}
console.log('LOCAL_WATCHDOG_PASS cases=2; no production edit/device/network/install');
