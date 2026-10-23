'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),z=require('node:zlib'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/content-decoding-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=content-decoding-tests production policy/HTTP facade; native decoder independently tested by C++ vectors\n');
const calls=[],events=[],ctx=vm.createContext({
  Log:{audit:(t,s,m)=>{events.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)}},
  decodeHttpBody:(b,e,limit)=>{
    calls.push(e);const bytes=Buffer.from(b);
    const result=e==='br'?z.brotliDecompressSync(bytes):e==='deflate'?z.inflateSync(bytes):z.gunzipSync(bytes);
    if(result.length>limit)throw Error('configured limit');
    const copy=new Uint8Array(result.length);copy.set(result);return copy.buffer;
  }
});
const code=fs.readFileSync(path.join(root,'entry/src/main/ets/network/ContentDecoding.ets'),'utf8')
  .replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(stripTypeScriptTypes(code,{mode:'transform'})+'\nglobalThis.Decode=ContentDecoding;',ctx);
function buffer(v){const a=new Uint8Array(v.length);a.set(v);return a.buffer}
let count=0;
function test(name,run){run();count++;fs.appendFileSync(log,`[响应返回] TraceID=content-decoding-tests PASS ${name}\n`)}
const plain=Buffer.from('{"value":"魔法"}');
test('SDK-decoded response with encoding header must not be decoded twice',()=>{
  const bytes=buffer(plain);assert.strictEqual(ctx.Decode.decode(bytes,'gzip','t',1024,true),bytes);assert.equal(calls.length,0);
});
test('explicit raw gzip/zlib/Brotli branches decode exact bytes',()=>{
  for(const [codec,data] of [['gzip',z.gzipSync(plain)],['deflate',z.deflateSync(plain)],['br',z.brotliCompressSync(plain)]]){
    assert.deepEqual(Buffer.from(ctx.Decode.decode(buffer(data),codec,'t',1024,false)),plain);
  }
});
test('stacked content encodings decode reverse listed order',()=>{
  calls.length=0;const encoded=z.brotliCompressSync(z.gzipSync(plain));
  assert.deepEqual(Buffer.from(ctx.Decode.decode(buffer(encoded),'gzip, br','t',1024,false)),plain);
  assert.deepEqual(calls,['br','gzip']);
});
test('identity/absent encoding returns bytes unchanged',()=>{
  const bytes=buffer(plain);assert.strictEqual(ctx.Decode.decode(bytes,'identity','t',1024,false),bytes);
});
test('unknown raw encoding/limit/corrupt stream rejected before parser',()=>{
  assert.throws(()=>ctx.Decode.decode(buffer(plain),'zstd','t',1024,false));
  assert.throws(()=>ctx.Decode.decode(buffer(z.gzipSync(plain)),'gzip','t',1,false));
  assert.throws(()=>ctx.Decode.decode(buffer(plain),'gzip','t',1024,false));
});
test('decoding events carry trace and no raw text/body',()=>{
  assert.ok(events.every(e=>['t'].includes(e.t)));assert.ok(events.every(e=>!e.m.includes('魔法')));
});
console.log(`PASS ${count} production content-encoding policy cases; no claim SDK transport tested.`);
