'use strict';
// Snapshot-directed Venera-only UI driver. No shell pipes or unobserved clicks.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'..'),device='<device-id>';
const hdc='C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const cli=path.join(process.env.TEMP,'venera-devecocli-1.3.5/node_modules/@deveco/deveco-cli/cli.js');
const out=path.join(root,'logs/user8-ui');fs.mkdirSync(out,{recursive:true});
const stamp=()=>Date.now()+'-'+Math.random().toString(16).slice(2,6);
function exec(file,args,label){
  const base=path.join(out,stamp()+'-'+label),o=fs.openSync(base+'.out','w'),e=fs.openSync(base+'.err','w');
  let result;try{result=cp.spawnSync(file,args,{cwd:root,stdio:['ignore',o,e],timeout:30000})}finally{fs.closeSync(o);fs.closeSync(e)}
  if(result.error||result.status!==0)throw Error(`command failed ${label}; inspect ${base}.err`);
  return {body:fs.readFileSync(base+'.out','utf8'),file:base+'.out'};
}
function focus(){
  const pid=exec(hdc,['-t',device,'shell','pidof','com.venerahm.reader'],'pid').body.trim().split(/\s+/)[0];
  if(!/^\d+$/.test(pid))throw Error('Venera process not available');
  const wm=exec(hdc,['-t',device,'shell','hidumper -s WindowManagerService -a "-a"'],'focus').body;
  const id=wm.match(/^Focus window:\s*(\d+)/m)?.[1];
  const owner=wm.split(/\r?\n/).find(line=>{const parts=line.trim().split(/\s+/);return parts[2]===pid&&parts[3]===id});
  if(!owner)throw Error('Foreground is not Venera; no UI captured or clicked');
}
// Extract the first balanced top-level array/object, ignoring string literals.
function parseLayout(raw,file){
  const text=raw.replace(/^\uFEFF/,'');
  const start=text.search(/[[{]/);
  if(start<0)throw Error('Layout has no JSON document; no click ('+file+')');
  const open=text[start],close=open==='['?']':'}';
  let depth=0,inString=false,escaped=false;
  for(let i=start;i<text.length;i++){
    const ch=text[i];
    if(inString){ if(escaped){escaped=false} else if(ch==='\\'){escaped=true} else if(ch==='"'){inString=false} continue }
    if(ch==='"'){inString=true;continue}
    if(ch===open)depth++;
    else if(ch===close){depth--;if(depth===0)return JSON.parse(text.slice(start,i+1))}
  }
  throw Error('Layout JSON truncated; no click ('+file+')');
}
function flatten(tree){const all=[];const walk=n=>{all.push(n);for(const c of n.children||[])walk(c)};for(const n of Array.isArray(tree)?tree:[tree])walk(n);return all}
function snapshot(){focus();const r=exec(process.execPath,[cli,'ui','layout','--device',device,'--format','json'],'layout');
  // The CLI may emit a UTF-8 BOM and may append progress/log lines after the
  // JSON document, so extract the first complete top-level array before parsing.
  const tree=parseLayout(r.body,r.file);
  const nodes=flatten(tree);fs.writeFileSync(path.join(out,'latest.json'),JSON.stringify(tree,null,2));
  return {tree,nodes,file:r.file};
}
const args=process.argv.slice(2),mode=args.shift()||'snapshot';
if(mode==='snapshot'){
  const s=snapshot();console.log('SNAPSHOT',path.relative(root,s.file));
  const filter=args[0]?new RegExp(args[0]):null;
  console.log(JSON.stringify(s.nodes.filter(n=>(n.text||n.type==='Select'||n.type==='Image')&&(!filter||filter.test(n.text||n.type))).map(n=>({type:n.type,text:n.text||'',id:n.id||'',bounds:n.bounds,clickable:!!n.clickable})),null,2));
}else if(mode==='click'||mode==='long'){
  const text=args[0],nth=args[1]===undefined?undefined:Number(args[1]),s=snapshot();
  let matches=s.nodes.filter(n=>n.text===text&&n.bounds);
  if(matches.length>1){const clickable=matches.filter(n=>n.clickable);if(clickable.length===1)matches=clickable}
  const node=nth===undefined?(matches.length===1?matches[0]:null):matches[nth];
  if(!node)throw Error(`Expected unique observed text ${JSON.stringify(text)}, matches=${matches.length}`);
  const b=node.bounds;if(b[1]<0||b[3]>2832||b[2]<=b[0]||b[3]<=b[1])throw Error('Target not visible');
  const x=Math.round((b[0]+b[2])/2),y=Math.round((b[1]+b[3])/2);focus();
  const cmd=mode==='long'?'longclick':'click';
  const r=exec(process.execPath,[cli,'ui',cmd,String(x),String(y),'--device',device],mode);console.log(mode,text,x,y,r.body.trim());
}else if(mode==='point'){
  const x=Number(args[0]),y=Number(args[1]);const s=snapshot();
  if(!s.nodes.some(n=>n.bounds&&n.bounds[0]<=x&&n.bounds[2]>=x&&n.bounds[1]<=y&&n.bounds[3]>=y))throw Error('Point not in observed layout');
  const r=exec(process.execPath,[cli,'ui','click',String(x),String(y),'--device',device],'point');console.log(r.body.trim());
}else if(mode==='back'){
  snapshot();console.log(exec(hdc,['-t',device,'shell','uitest uiInput keyEvent Back'],'back').body.trim());
}else if(mode==='swipe'){
  snapshot();console.log(exec(process.execPath,[cli,'ui','swipe',...args,'--device',device],'swipe').body.trim());
}else throw Error('Unknown action; use snapshot/click/long/point/back/swipe');
