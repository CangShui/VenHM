'use strict';
// New request scope: viewport dispatch/menu only. No historical baseline rewrite.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/legado-interaction-20261023');
const sdk='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader';
const ts=require(sdk+'/node_modules/typescript/lib/typescript.js');const options=ts.parseConfigFileTextToJson(sdk+'/tsconfig.json',fs.readFileSync(sdk+'/tsconfig.json','utf8')).config.compilerOptions;
const read=f=>fs.readFileSync(path.join(root,f),'utf8'),hash=s=>crypto.createHash('sha256').update(s).digest('hex');
function methods(text){const file=ts.createSourceFile('ReaderPage.ets',text,ts.ScriptTarget.Latest,true,ts.ScriptKind.ETS,options),result={};function walk(n){if(ts.isMethodDeclaration(n)&&n.name){const name=n.name.getText(file),decorators=ts.getDecorators?ts.getDecorators(n):n.decorators;if(name!=='build'&&!(decorators||[]).some(d=>d.getText(file).includes('Builder')))result[name]=n.getText(file)}ts.forEachChild(n,walk)}walk(file);return result}
const before=methods(read('logs/legado-interaction-20261023/ReaderPage.before.ets')),now=methods(read('entry/src/main/ets/pages/ReaderPage.ets'));
const allowed=new Set(['aboutToAppear','imageTapEnabled','onImageSingleTap','dismissReaderMenu','onBackPress','releaseReaderControls','autoStep','syncVolumeKeys']);
const differences=[];let checked=0;for(const [name,body]of Object.entries(before)){if(allowed.has(name))continue;checked++;if(now[name]!==body)differences.push('NON_UI_READER '+name)}
// Auto-pager gets only a UI visibility pause guard; its actual page/scroll logic is frozen.
const normalizedAuto=now.autoStep.replace('this.toolbarVisible || this.showChapters || ','').replace(/\s+/g,' ').trim();assert.equal(normalizedAuto,before.autoStep.replace(/\s+/g,' ').trim());
const normalizedKeys=now.syncVolumeKeys.replace('this.toolbarVisible || ','').replace(/\s+/g,' ').trim();assert.equal(normalizedKeys,before.syncVolumeKeys.replace(/\s+/g,' ').trim());
const backend=JSON.parse(read('logs/ui-refresh-20261021/baseline.json')).backend;
for(const [file,sha]of Object.entries(backend))if(hash(fs.readFileSync(path.join(root,file)))!==sha)differences.push('BACKEND '+file);
// Shared image IO/cache/lifecycle methods are also frozen against the original
// UI baseline; only tap delivery and the explicit reader-double-tap callback differ.
const widgetPath='entry/src/main/ets/components/ComicWidgets.ets';
const originalWidget=JSON.parse(read('logs/ui-refresh-20261021/baseline.json')).viewMethods[widgetPath];
const widgetNow=methods(read(widgetPath));let widgetChecked=0;
for(const [name,sha]of Object.entries(originalWidget)){
 if(name==='queueSingleTap')continue;
 const body=(widgetNow[name]||'').replace('this.onReaderDoubleTap?.();','').replace(/\s+/g,' ').trim();
 widgetChecked++;if(hash(body)!==sha)differences.push('SHARED_IMAGE_NON_TAP '+name);
}
const data={protectedReaderMethods:checked,protectedImageMethods:widgetChecked,backendFiles:Object.keys(backend).length,allowedReaderInteractionChanges:[...allowed],differences};fs.writeFileSync(path.join(folder,'scope-result.json'),JSON.stringify(data,null,2));assert.deepEqual(differences,[]);
console.log(`PASS ${checked} original non-interaction reader methods and ${Object.keys(backend).length} backend/config files unchanged; auto-step only pauses for visible chrome`);
