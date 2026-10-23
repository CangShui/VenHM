'use strict';
const fs=require('node:fs'),path=require('node:path'),z=require('node:zlib');
const root=path.resolve(__dirname,'..'),out=path.join(root,'logs/http-codec-vectors');
fs.mkdirSync(out,{recursive:true});
const plain=Buffer.from('{"message":"魔法 😀","source":"synthetic"}');
const cases=[];
function add(name,codec,input,expected,limit=1024*1024,pass=true){
  fs.writeFileSync(path.join(out,name+'.bin'),input);
  fs.writeFileSync(path.join(out,name+'.expected'),expected||Buffer.alloc(0));
  cases.push([name,codec,name+'.bin',name+'.expected',limit,pass?1:0].join('|'));
}
const gzip=z.gzipSync(plain),br=z.brotliCompressSync(plain),def=z.deflateSync(plain),raw=z.deflateRawSync(plain);
add('gzip','gzip',gzip,plain);
add('x-gzip','x-gzip',gzip,plain);
add('gzip-concatenated','gzip',Buffer.concat([gzip,gzip]),Buffer.concat([plain,plain]));
add('deflate-zlib','deflate',def,plain);
add('deflate-raw','deflate',raw,plain);
const defBad=Buffer.from(def);defBad[defBad.length-1]^=1;add('deflate-adler','deflate',defBad,null,1024,false);
add('deflate-truncated','deflate',def.subarray(0,def.length-2),null,1024,false);
add('deflate-trailing','deflate',Buffer.concat([def,Buffer.from([0,1])]),null,1024,false);
add('brotli','br',br,plain);
add('gzip-truncated','gzip',gzip.subarray(0,gzip.length-4),null,1024,false);
const bad=Buffer.from(gzip);bad[bad.length-8]^=1;add('gzip-crc','gzip',bad,null,1024,false);
add('gzip-trailing','gzip',Buffer.concat([gzip,Buffer.from([0,1])]),null,1024,false);
add('brotli-truncated','br',br.subarray(0,br.length-2),null,1024,false);
add('brotli-trailing','br',Buffer.concat([br,Buffer.from([0,1])]),null,1024,false);
add('gzip-limit','gzip',z.gzipSync(Buffer.alloc(4096,65)),null,512,false);
add('brotli-limit','br',z.brotliCompressSync(Buffer.alloc(4096,65)),null,512,false);
add('unsupported','zstd',gzip,null,1024,false);
fs.writeFileSync(path.join(out,'cases.txt'),cases.join('\n')+'\n');
fs.writeFileSync(path.join(root,'logs/http-codec-vector-generation.log'),
  `TraceID=http-codec-vectors [响应返回] ${cases.length} Node standard codec vectors; synthetic data only\n`);
console.log(`Generated ${cases.length} independent HTTP codec vectors.`);
