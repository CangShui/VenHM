'use strict';
// UI-only work fence. Uses DevEco's ArkTS parser, not regex to extract methods.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const sdk='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader';
const ts=require(sdk+'/node_modules/typescript/lib/typescript.js');
const cfg=ts.parseConfigFileTextToJson(sdk+'/tsconfig.json',fs.readFileSync(sdk+'/tsconfig.json','utf8'));
if(cfg.error)throw Error('SDK ArkUI parser configuration invalid');
const parserOptions=cfg.config.compilerOptions;
const root=path.resolve(__dirname,'..');
const dir=path.join(root,'logs/ui-refresh-20261021');
const baseline=path.join(dir,'baseline.json');
const allowedFeatures=new Set(['HomeView.ets','BookshelfView.ets','ExploreView.ets','CategoryView.ets','SearchView.ets','SettingsView.ets']);
function files(dir){return fs.readdirSync(path.join(root,dir),{withFileTypes:true}).flatMap(entry=>entry.isDirectory()?files(dir+'/'+entry.name):[dir+'/'+entry.name])}
function digest(text){return crypto.createHash('sha256').update(text).digest('hex')}
function methodRecords(file,text){
 const ast=ts.createSourceFile(file,text,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS??ts.ScriptKind.TS,parserOptions),out={};
 function walk(n){
  if(ts.isMethodDeclaration(n)&&n.name){
   const name=n.name.getText(ast),decorators=ts.getDecorators?ts.getDecorators(n):n.decorators;
   const builder=(decorators||[]).some(d=>d.getText(ast).includes('Builder'));
   // Build/builder methods are the only bodies UI redesign is allowed to replace.
   if(name!=='build'&&!builder){out[name]=digest(n.getText(ast).replace(/\s+/g,' ').trim())}
  }
  ts.forEachChild(n,walk);
 }
 walk(ast);return out;
}
function capture(){
 const backend={},viewMethods={},routes={};
 for(const file of files('entry/src/main/ets')){
  if(!file.endsWith('.ets'))continue;
  const text=fs.readFileSync(path.join(root,file),'utf8');
  const view=file.includes('/pages/')||file.includes('/components/')||allowedFeatures.has(path.basename(file));
  if(!view)backend[file]=digest(text);
  else{
   const methods=methodRecords(file,text);if(Object.keys(methods).length)viewMethods[file]=methods;
   routes[file]=[...text.matchAll(/url:\s*'([^']+)'/g)].map(m=>m[1]).sort();
  }
 }
 for(const file of ['AppScope/app.json5','entry/src/main/module.json5','entry/src/main/resources/base/profile/main_pages.json'])backend[file]=digest(fs.readFileSync(path.join(root,file)));
 return {backend,viewMethods,routes};
}
if(process.argv.includes('--record')){
 if(fs.existsSync(baseline))throw Error('UI baseline already exists; do not overwrite before audit');
 fs.mkdirSync(dir,{recursive:true});const state=capture();fs.writeFileSync(baseline,JSON.stringify(state,null,2));
 console.log(`UI_BASELINE_RECORDED backend=${Object.keys(state.backend).length} views=${Object.keys(state.viewMethods).length}`);
}else{
 const before=JSON.parse(fs.readFileSync(baseline,'utf8')),now=capture();
 const changes=[];
 for(const [file,hash]of Object.entries(before.backend))if(now.backend[file]!==hash)changes.push('BACKEND '+file);
 for(const [file,methods]of Object.entries(before.viewMethods)){
  // Index's tabBar/topBar are builders; no business methods may change elsewhere.
  for(const [name,hash]of Object.entries(methods))if(now.viewMethods[file]?.[name]!==hash)changes.push('METHOD '+file+'::'+name);
 }
 for(const [file,targets]of Object.entries(before.routes)){
  for(const target of new Set(targets))if(!now.routes[file]?.includes(target))changes.push('ROUTE '+file+' -> '+target);
 }
 fs.writeFileSync(path.join(dir,'guard-result.json'),JSON.stringify({backendFiles:Object.keys(before.backend).length,businessViews:Object.keys(before.viewMethods).length,changes},null,2));
 assert.deepEqual(changes,[],'UI-only fence violated');
 console.log(`PASS ${Object.keys(before.backend).length} backend files byte-identical, all existing business methods and route targets preserved`);
}
