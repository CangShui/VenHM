'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/image-transform-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
fs.writeFileSync(log,'[请求到达] TraceID=image-tests production ImageScriptBridge and unmodified init.js; byte oracle, not device evidence\n');
const text=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const ctx=vm.createContext({Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},Uint8Array,ArrayBuffer});
vm.runInContext(stripTypeScriptTypes(text('entry/src/main/ets/source/ImageScriptBridge.ets'),{mode:'transform'})+
  '\nglobalThis.Bridge=ImageScriptBridge;globalThis.Surface=ImageSurface;',ctx);
ctx.sendMessage=m=>ctx.Bridge.handle(m);
vm.runInContext(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/init.js'),'utf8'),ctx);
function session(width,height,script){
  const bytes=new Uint8Array(width*height*4);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const p=(y*width+x)*4;bytes.set([y*10+x,70+x,90+y,255],p);
  }
  const key=ctx.Bridge.begin(new ctx.Surface(width,height,bytes),'image-tests');
  try {
    const output=vm.runInContext(`(()=>{const image=new Image(${key});${script}})()`,ctx);
    const result=ctx.Bridge.result(output);
    return {width:result.width,height:result.height,bytes:Uint8Array.from(result.bytes),key};
  } finally {ctx.Bridge.end()}
}
let count=0;
function test(name,fn){fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=image-tests PASS ${name}\n`)}
test('all four channels copied without RGB/BGR or alpha loss',()=>{
  const r=session(3,5,'return image.copyRange(1,2,2,2).key;');
  assert.equal(r.width,2);assert.equal(r.height,2);
  assert.deepEqual([...r.bytes],[21,71,92,255,22,72,92,255,31,71,93,255,32,72,93,255]);
});
test('clockwise rotate matches upstream asymmetric oracle',()=>{
  const r=session(3,2,'return image.copyAndRotate90().key;');
  assert.equal(r.width,2);assert.equal(r.height,3);
  assert.deepEqual([...r.bytes.filter((_,i)=>i%4===0)],[10,0,11,1,12,2]);
});
test('JM published script with remainder reorders blocks, not just decodable pixels',()=>{
  // Same algorithm as the installed jm.js; height 11,num4 exercises last-block remainder.
  const r=session(2,11,`const num=4,blockSize=Math.floor(image.height/num),remainder=image.height%num,blocks=[];
    for(let i=0;i<num;i++){const start=i*blockSize;blocks.push({start,end:start+blockSize+(i!==num-1?0:remainder)})}
    const out=Image.empty(image.width,image.height);let y=0;
    for(let i=blocks.length-1;i>=0;i--){const b=blocks[i],h=b.end-b.start;out.fillImageRangeAt(0,y,image,0,b.start,image.width,h);y+=h}
    return out.key;`);
  assert.deepEqual(Array.from({length:11},(_,y)=>r.bytes[y*8]),[60,70,80,90,100,40,50,20,30,0,10]);
});
test('fill full image and empty image start transparent',()=>{
  const r=session(2,2,'const out=Image.empty(3,3);out.fillImageAt(1,1,image);return out.key;');
  assert.deepEqual([...r.bytes.slice(0,12)],Array(12).fill(0));
  assert.equal(r.bytes[(2*3+2)*4],11);
});
test('out of bounds/negative/fractional/NaN dimensions rejected rather than clamped',()=>{
  for(const code of ['image.copyRange(2,0,1,1)','image.copyRange(-1,0,1,1)','Image.empty(1.5,1)',
    'Image.empty(NaN,1)','Image.empty(1000000,1000000)']){
    assert.throws(()=>session(2,2,`return ${code}.key;`));
  }
});
test('invalid fill validates both rectangles before writes',()=>{
  const key=ctx.Bridge.begin(new ctx.Surface(1,1,new Uint8Array([1,2,3,255])),'image-tests');
  try{
    assert.throws(()=>ctx.Bridge.handle({function:'fillImageRangeAt',key,image:key,x:0,y:0,srcX:1,srcY:0,width:1,height:1}));
    assert.deepEqual([...ctx.Bridge.result(key).bytes],[1,2,3,255]);
  }finally{ctx.Bridge.end()}
});
test('outside-session image requests return null and allocate no memory',()=>{
  assert.equal(ctx.Bridge.handle({function:'emptyImage',width:20,height:20}),null);
});
test('expired handles cannot cross request boundaries',()=>{
  const r=session(1,1,'return image.key;');
  const key=ctx.Bridge.begin(new ctx.Surface(1,1,new Uint8Array(4)),'next-request');
  try{assert.notEqual(key,r.key);assert.throws(()=>ctx.Bridge.handle({function:'getWidth',key:r.key}))}
  finally{ctx.Bridge.end()}
});
test('exception releases session; next legitimate transform succeeds',()=>{
  assert.throws(()=>session(1,1,'throw Error("expected");'));
  assert.equal(session(1,1,'return image.key;').width,1);
});
test('memory budget rejected before allocating oversized destination',()=>{
  assert.throws(()=>session(1,1,'return Image.empty(10000,10000).key;'));
});
// Real production ImageTransforms with ImageKit fakes, to verify serialization/finally and script execution.
ctx.callJson=async code=>vm.runInContext(code,ctx);
let nativeActive=0,maxNativeActive=0;
ctx.transformIsolated=async(raw,width,height,script,trace,premul)=>{
  nativeActive++;maxNativeActive=Math.max(maxNativeActive,nativeActive);
  try{
    await new Promise(r=>setTimeout(r,5));
    const worker=vm.createContext({Log:{audit:(t,s,m)=>fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},Uint8Array,ArrayBuffer});
    vm.runInContext(stripTypeScriptTypes(text('entry/src/main/ets/source/ImageScriptBridge.ets'),{mode:'transform'})+
      '\nglobalThis.Bridge=ImageScriptBridge;globalThis.Surface=ImageSurface;',worker);
    worker.sendMessage=m=>worker.Bridge.handle(m);
    vm.runInContext(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/init.js'),'utf8'),worker);
    const bytes=Uint8Array.from(new Uint8Array(raw));
    if(premul)for(let i=0;i<bytes.length;i+=4)for(let c=0;c<3;c++)bytes[i+c]=bytes[i+3]===0?0:Math.min(255,Math.round(bytes[i+c]*255/bytes[i+3]));
    const key=worker.Bridge.begin(new worker.Surface(width,height,bytes),trace);
    try{
      const output=vm.runInContext(script+`\nmodifyImage(new Image(${key})).key;`,worker);
      const surface=worker.Bridge.result(output);const buffer=new ArrayBuffer(surface.bytes.length);new Uint8Array(buffer).set(surface.bytes);
      return {width:surface.width,height:surface.height,rgba:buffer};
    }finally{worker.Bridge.end()}
  }finally{nativeActive--}
};
ctx.cancelIsolated=()=>0;
ctx.image={
  PixelMapFormat:{RGBA_8888:3},AlphaType:{PREMUL:2,UNPREMUL:3},
  createImageSource:b=>({
    getImageInfo:async()=>({size:{width:1,height:1}}),
    createPixelMap:async()=>({getImageInfo:async()=>({alphaType:3}),
      readPixelsToBuffer:async dest=>new Uint8Array(dest).set(new Uint8Array(b)),release:async()=>{}}),
    release:async()=>{}}),
  createPixelMap:async(b,o)=>({bytes:b,options:o,release:async()=>{}}),
  createImagePacker:()=>({packToData:async p=>p.bytes,release:async()=>{}})
};
vm.runInContext(stripTypeScriptTypes(text('entry/src/main/ets/network/ImageTransforms.ets'),{mode:'transform'})+
  '\nglobalThis.Transforms=ImageTransforms;',ctx);
(async()=>{
  const input=Uint8Array.from([10,20,30,255]).buffer;
  const outputs=await Promise.all(Array.from({length:8},()=>ctx.Transforms.apply(input,
    'let modifyImage=image=>image.copyAndRotate90();','concurrent')));
  for(const b of outputs)assert.deepEqual([...new Uint8Array(b)],[10,20,30,255]);
  assert.equal(maxNativeActive,4);
  count++;fs.appendFileSync(log,'[响应返回] TraceID=image-tests PASS four-slot isolated native dispatch (FFI mocked)\n');
  await assert.rejects(ctx.Transforms.apply(input,'let modifyImage=i=>i.copyRange(1,0,1,1);','reject'));
  assert.deepEqual([...new Uint8Array(await ctx.Transforms.apply(input,'let modifyImage=i=>i;','recover'))],[10,20,30,255]);
  count++;fs.appendFileSync(log,'[响应返回] TraceID=image-tests PASS pipeline reject/recover\n');
  ctx.image.createImageSource=b=>({getImageInfo:async()=>({size:{width:1,height:1}}),release:async()=>{},
    createPixelMap:async()=>({getImageInfo:async()=>({alphaType:2}),release:async()=>{},
      readPixelsToBuffer:async dest=>new Uint8Array(dest).set([32,16,8,128])})});
  assert.deepEqual([...new Uint8Array(await ctx.Transforms.apply(input,'let modifyImage=i=>i;','alpha'))],[64,32,16,128]);
  count++;fs.appendFileSync(log,'[响应返回] TraceID=image-tests PASS straight RGBA unpremultiplication\n');
  console.log(`PASS ${count} production image transform pixel/lifecycle cases (device ImageKit still required).`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
