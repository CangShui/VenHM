'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const logFile = path.join(root, 'logs', 'html-lifecycle-cases.log');
fs.mkdirSync(path.dirname(logFile), { recursive: true });
fs.writeFileSync(logFile, '[请求到达] TraceID=html-tests unchanged upstream HtmlDocument plus production engine\n');
const messages = [];
const context = vm.createContext({
  sendMessage: message => {
    messages.push(message);
    if (message.method === 'log') fs.appendFileSync(logFile, message.content + '\n');
    return null;
  },
});
const raw = path.join(root, 'entry/src/main/resources/rawfile');
vm.runInContext(fs.readFileSync(path.join(raw, 'init.js'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(raw, 'html_engine.js'), 'utf8'), context);
let cases = 0;
function check(name, code) {
  fs.appendFileSync(logFile, `[业务入口] TraceID=html-tests ${name}\n`);
  assert.equal(vm.runInContext(code, context), true, name);
  cases++;
  fs.appendFileSync(logFile, `[响应返回] TraceID=html-tests PASS ${name}\n`);
}
try {
  check('12 concurrently live upstream documents retain earlier handles', `(() => {
    const docs=[];
    try {
      for(let i=0;i<12;i++) docs.push(new HtmlDocument('<div id="value">'+i+'</div>'));
      return docs.every((d,i)=>d.querySelector('#value').text===String(i));
    } finally { docs.forEach(d=>d.dispose()); }
  })()`);
  check('disposing one document does not invalidate another', `(() => {
    const first=new HtmlDocument('<p>A</p>'),second=new HtmlDocument('<p>B</p>');
    first.dispose();
    try { return first.querySelector('p')===null && second.querySelector('p').text==='B'; }
    finally { second.dispose(); }
  })()`);
  check('decimal/hex/uppercase-hex astral references preserve code points', `(() => {
    const d=new HtmlDocument('<p>&#128512; &#x1F642; &#X1F680;</p>');
    try { return d.querySelector('p').text==='😀 🙂 🚀'; } finally { d.dispose(); }
  })()`);
  check('invalid Unicode code points become replacement characters', `(() => {
    const d=new HtmlDocument('<p>&#0; &#xD800; &#1114112;</p>');
    try { return d.querySelector('p').text==='� � �'; } finally { d.dispose(); }
  })()`);
  check('attributes decode supplementary references too', `(() => {
    const d=new HtmlDocument('<a title="&#x1F642;">x</a>');
    try { return d.querySelector('a').attributes.title==='🙂'; } finally { d.dispose(); }
  })()`);
  check('attribute URL entities are decoded once, not sent as amp;', `(() => {
    const d=new HtmlDocument('<a href="/search?a=1&amp;b=2" title="&amp;lt;">x</a>');
    try { const attrs=d.querySelector('a').attributes;
      return attrs.href==='/search?a=1&b=2' && attrs.title==='&lt;'; } finally { d.dispose(); }
  })()`);
  check('serialization preserves literal text and escaped attributes', `(() => {
    const d=new HtmlDocument('<div>&lt;test&gt;<a title="a&amp;&quot;b">x</a><img src="a"></div>');
    try { return d.querySelector('div').innerHTML==='&lt;test&gt;<a title="a&amp;&quot;b">x</a><img src="a">'; }
    finally { d.dispose(); }
  })()`);
  check('script raw text is not entity-decoded or escaped during serialization', `(() => {
    const d=new HtmlDocument('<script>if(a<b) x="&amp;";</script>');
    try { return d.querySelector('script').innerHTML==='if(a<b) x="&amp;";'; }
    finally { d.dispose(); }
  })()`);
  check('fallback parse key and explicit numeric key cannot alias', `(() => {
    const fallback=sendMessage({method:'html',function:'parse',data:'<p>fallback</p>'});
    const numeric=sendMessage({method:'html',function:'parse',key:999,data:'<p>numeric</p>'});
    const read=(key)=>{const node=sendMessage({method:'html',function:'querySelector',key,query:'p'});
      return sendMessage({method:'html',function:'getText',key:node,doc:key});};
    try { return read(fallback)==='fallback' && read(numeric)==='numeric'; }
    finally { sendMessage({method:'html',function:'dispose',key:fallback});
      sendMessage({method:'html',function:'dispose',key:numeric}); }
  })()`);
  const reports=messages.filter(m=>m.title==='HtmlAudit');
  assert.ok(reports.length>0);
  assert.match(reports.at(-1).content,/活动文档数=0/,'dispose removes canonical entries, no leaked aliases');
  const traces=new Map();
  for(const report of reports) {
    const trace=report.content.match(/^TraceID=(\S+)/)[1];
    if(!traces.has(trace)) traces.set(trace,[]);
    traces.get(trace).push(report.content);
  }
  for(const entries of traces.values()) {
    assert.equal(entries.length,2,'request and response share one TraceID');
    assert.match(entries[0],/请求到达/);
    assert.match(entries[1],/响应返回/);
  }
  cases+=2;
  const summary=`PASS ${cases} HTML lifetime/Unicode/audit cases; no real-site equivalence claim.`;
  fs.appendFileSync(logFile, `[响应返回] TraceID=html-tests ${summary}\n`);
  console.log(summary);
} catch(error) {
  fs.appendFileSync(logFile, `[异常] TraceID=html-tests ${error.stack}\n`);
  throw error;
}
