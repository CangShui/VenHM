'use strict';
// Read-only replay of a published source against captured HTML. No remote
// requests, credentials, host filesystem APIs or process APIs reach the VM.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const scriptFile = process.argv[2];
const htmlFile = process.argv[3];
if (!scriptFile || !htmlFile) throw new Error('Usage: node tools/html_source_fixture_cases.js <wnacg.js> <captured-search.html>');
const logPath = path.join(root, 'logs', 'html-source-fixture.log');
const source = fs.readFileSync(scriptFile, 'utf8');
const html = fs.readFileSync(htmlFile, 'utf8');
fs.writeFileSync(logPath, '[请求到达] TraceID=html-source-fixture captured-page replay, no external calls\n' +
  'source SHA256=' + crypto.createHash('sha256').update(source).digest('hex') + '\n' +
  'HTML SHA256=' + crypto.createHash('sha256').update(html).digest('hex') + '\n');
const sandbox = vm.createContext({
  fixtureHtml: html,
  sendMessage: msg => {
    if (msg.method === 'log') {
      fs.appendFileSync(logPath, msg.content + '\n');
      return null;
    }
    throw new Error(`Unexpected external API ${msg.method}`);
  },
});
const raw = path.join(root, 'entry/src/main/resources/rawfile');
vm.runInContext(fs.readFileSync(path.join(raw, 'init.js'), 'utf8'), sandbox, {timeout:5000});
vm.runInContext(fs.readFileSync(path.join(raw, 'html_engine.js'), 'utf8'), sandbox, {timeout:5000});
vm.runInContext('Network.get=async()=>({status:200,body:fixtureHtml});',sandbox);
vm.runInContext(source + '\nglobalThis.fixtureSource=new Wnacg(); fixtureSource.loadSetting=k=>({domainSelection:0,domain0:"www.wn001.cfd"})[k];',sandbox,{timeout:5000});
(async()=>{
  const result=await vm.runInContext('fixtureSource.search.load("a",[],1)',sandbox,{timeout:5000});
  assert.equal(result.comics.length,24);
  assert.ok(result.maxPage>1);
  assert.ok(result.comics.every(c=>typeof c.id==='string' && c.id.length>0 && c.title.length>0 && c.cover.length>0));
  const summary=`PASS wnacg published search on captured HTML: ${result.comics.length} valid items, maxPage=${result.maxPage}. Not a device/network PASS.`;
  fs.appendFileSync(logPath, '[响应返回] TraceID=html-source-fixture '+summary+'\n');
  console.log(summary);
})().catch(error=>{
  fs.appendFileSync(logPath,'[异常] TraceID=html-source-fixture '+error.stack+'\n');
  console.error(error);process.exitCode=1;
});
