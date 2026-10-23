'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/reader-immersive-20261021'),file='entry/src/main/ets/pages/ReaderPage.ets';
const sdk='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader';
const ts=require(sdk+'/node_modules/typescript/lib/typescript.js'),options=ts.parseConfigFileTextToJson(sdk+'/tsconfig.json',fs.readFileSync(sdk+'/tsconfig.json','utf8')).config.compilerOptions;
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
const allowed=new Set(['aboutToAppear','onPageShow','onPageHide','aboutToDisappear','releaseReaderControls','imageTapEnabled','onImageSingleTap']);
function methods(text){const tree=ts.createSourceFile(file,text,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS,options),map={};function walk(n){if(ts.isMethodDeclaration(n)){const name=n.name?.getText(tree),decorators=ts.getDecorators?ts.getDecorators(n):n.decorators;const ui=name==='build'||(decorators||[]).some(d=>d.getText(tree).includes('Builder'));if(name&&!ui&&!allowed.has(name))map[name]=digest(n.getText(tree))}ts.forEachChild(n,walk)}walk(tree);return map}
const baseline=path.join(folder,'scope-baseline.json');
if(process.argv.includes('--record')){
 assert.ok(!fs.existsSync(baseline),'Do not overwrite original reader baseline');fs.mkdirSync(folder,{recursive:true});const text=fs.readFileSync(path.join(root,file),'utf8');const backend=JSON.parse(fs.readFileSync(path.join(root,'logs/ui-refresh-20261021/baseline.json'),'utf8')).backend;
 fs.writeFileSync(baseline,JSON.stringify({originalReader:text,methods:methods(text),backend,allowedReaderInteractionChanges:[...allowed]},null,2));console.log('READER_IMMERSIVE_SCOPE_RECORDED');
}else{
 const old=JSON.parse(fs.readFileSync(baseline,'utf8')),current=methods(fs.readFileSync(path.join(root,file),'utf8')),changes=[];
 for(const [name,sha]of Object.entries(old.methods))if(current[name]!==sha)changes.push('READER_NON_UI '+name);
 for(const [name,sha]of Object.entries(old.backend))if(digest(fs.readFileSync(path.join(root,name)))!==sha)changes.push('BACKEND '+name);
 // All other original view methods remain frozen too. Only ReaderPage's
 // requested chrome lifecycle/tap methods and image single-tap delivery differ.
 const previousUI=JSON.parse(fs.readFileSync(path.join(root,'logs/ui-refresh-20261021/baseline.json'),'utf8'));
 for(const [name,records]of Object.entries(previousUI.viewMethods)){
  if(name===file)continue;
  const code=fs.readFileSync(path.join(root,name),'utf8'),tree=ts.createSourceFile(name,code,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS,options),actual={};
  function walk(n){if(ts.isMethodDeclaration(n)&&n.name)actual[n.name.getText(tree)]=digest(n.getText(tree).replace(/\s+/g,' ').trim());ts.forEachChild(n,walk)}walk(tree);
  for(const [method,sha]of Object.entries(records)){if(name.endsWith('/ComicWidgets.ets')&&method==='queueSingleTap')continue;if(actual[method]!==sha)changes.push('UNRELATED_METHOD '+name+'::'+method)}
 }
 fs.writeFileSync(path.join(folder,'scope-result.json'),JSON.stringify({changes,protectedReaderMethods:Object.keys(old.methods).length,protectedFiles:Object.keys(old.backend).length},null,2));assert.deepEqual(changes,[]);
 console.log(`PASS ${Object.keys(old.methods).length} reader non-UI methods and ${Object.keys(old.backend).length} existing backend/config files unchanged; scoped changes only for new chrome interaction`);
}
