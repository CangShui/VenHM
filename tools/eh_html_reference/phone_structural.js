'use strict';
// Offline counts and source-style preflight ONLY. No addon; no source list call.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),spec=JSON.parse(fs.readFileSync(path.join(__dirname,'probe_spec.json'),'utf8'));
const engine=fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/html_engine.js'),'utf8');
const ctx=vm.createContext({sendMessage:m=>{if(m.method==='log')return null;throw Error('REFUSED_HOST_CALL');}});
vm.runInContext(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/init.js'),'utf8'),ctx,{timeout:1000});
vm.runInContext(engine,ctx,{timeout:1000});
ctx.spec=spec;
const rows=[];
for(let i=0;i<4;i++){
 const file=path.join(__dirname,'phone-public','phone-'+i+'.html'),html=fs.readFileSync(file,'utf8');ctx.html=html;
 const result=vm.runInContext(`(()=>{const d=new HtmlDocument(html);try{const counts=Object.fromEntries(spec.selectors.concat(spec.landmarks).map(q=>[q,d.querySelectorAll(q).length]));const direct={};for(const mode of ['gltc','glte','gltm']){const rows=d.querySelectorAll('table.itg.'+mode+' > tr');direct[mode]={rows:rows.length,childrenHistogram:{},styleNonempty:0,styleMissingOrEmpty:0,compactRequiredShapeOk:0};for(const r of rows){const n=r.children.length;direct[mode].childrenHistogram[n]=(direct[mode].childrenHistogram[n]||0)+1;const style=mode==='gltc'?(()=>{try{return r.children[1].children[2].children[1].attributes.style;}catch(_){return undefined;}})():r.querySelector(mode==='glte'?'td.gl2e > div > div.gl3e > div.ir':'td.gl4m > div.ir')?.attributes.style;if(typeof style==='string'&&style.length>0)direct[mode].styleNonempty++;else direct[mode].styleMissingOrEmpty++;if(mode==='gltc'){try{const c=r.children;const ok=typeof c[0].children[0].text==='string'&&typeof c[1].children[2].children[0].text==='string'&&typeof c[1].children[2].children[1].attributes.style==='string'&&typeof c[1].children[1].children[0].children[0].attributes.src==='string'&&typeof c[2].children[0].children[0].text==='string'&&typeof c[2].children[0].attributes.href==='string'&&c[2].children[0].children[1].children.every(n=>typeof n.attributes.title==='string');if(ok)direct[mode].compactRequiredShapeOk++;}catch(_){}}}}return {counts,direct,nextPresent:!!d.querySelector('a#dnext')};}finally{d.dispose();}})()`,ctx,{timeout:1000});
 const rawMarkers=['<table','<tbody','</tbody','<tr','<thead','<tfoot'].map(s=>[s,(html.toLowerCase().match(new RegExp(s+'(?:\\s|>)','g'))||[]).length]);
 const clues={};for(const [name,re]of [['listingTable',/<table\b[^>]*class\s*=\s*["'][^"']*\bitg\b/i],['explicitTbody',/<tbody(?:\s|>)/i],['firstTr',/<tr(?:\s|>)/i]]){const m=re.exec(html);clues[name]=m?{line:html.slice(0,m.index).split('\n').length,column:m.index-html.lastIndexOf('\n',m.index)}:null;}
 rows.push({index:i,utf8Bytes:Buffer.byteLength(html),characters:html.length,sha256:crypto.createHash('sha256').update(html).digest('hex'),firstCharIsAngle:html[0]==='<',rawMarkers:Object.fromEntries(rawMarkers),lineClues:clues,...result});
 console.log(JSON.stringify({index:i,bytes:Buffer.byteLength(html),roots:Object.fromEntries(Object.entries(spec.modeRoots).map(([k,q])=>[k,result.counts[q]])),direct:result.direct,nextPresent:result.nextPresent,rawMarkers:Object.fromEntries(rawMarkers),lineClues:clues}));
}
fs.writeFileSync(path.join(__dirname,'phone_structural_results.json'),JSON.stringify({engineSha256:crypto.createHash('sha256').update(engine).digest('hex'),engine:'production HtmlDocument in bounded NodeVM; NO NAPI/source parser execution',rows},null,2)+'\n');
