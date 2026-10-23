'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/chapter-navigation-cases.log');
fs.mkdirSync(path.dirname(log),{recursive:true});fs.writeFileSync(log,'[请求到达] TraceID=chapter-tests production chapter model/navigation/details controls; no device UI claim\n');
const read=p=>fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
const model=read('entry/src/main/ets/model/Comic.ets');
const chapterModel=model.slice(model.indexOf('class ComicChapters {'),model.indexOf('/** Parses one comic object'));
const raw=read('entry/src/main/ets/pages/ComicDetailsPage.ets');
const details=(raw.slice(0,raw.indexOf('  @Builder'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*/g,'')
  .replace('struct ComicDetailsPage','class ComicDetailsPage');
const routes=[],events=[],ctx=vm.createContext({
  Map,Set,Log:{audit:(t,s,m)=>{events.push({t,s,m});fs.appendFileSync(log,`TraceID=${t} [${s}] ${m}\n`)},error:()=>{},warn:()=>{}},
  SourceManager:{find:k=>k==='other'?{}:undefined},
  router:{pushUrl:async r=>routes.push(r)},
  ComicType:{fromKey:()=>({value:1})}
});
const deps=require('./vm_deps');
vm.runInContext(stripTypeScriptTypes(deps.DETAILS_STUBS+'\n'+chapterModel+'\n'+read('entry/src/main/ets/features/ChapterNavigation.ets')+'\n'+details,{mode:'transform'})+
  '\nglobalThis.Chapters=ComicChapters;globalThis.Nav=ChapterNavigation;globalThis.Page=ComicDetailsPage;',ctx);
let count=0;
async function test(name,fn){await fn();count++;fs.appendFileSync(log,`[响应返回] TraceID=chapter-tests PASS ${name}\n`)}
(async()=>{
  await test('group and canonical ID order preserved with empty groups ignored',async()=>{
    const c=ctx.Chapters.groupedOf(new Map([['Vol1',new Map([['a','A'],['b','B']])],['empty',new Map()],['Vol2',new Map([['c','C']])]]));
    const sections=ctx.Nav.sections(c,false,'chapter-tests');
    assert.deepEqual(Array.from(sections,s=>s.name),['Vol1','Vol2']);
    assert.deepEqual(Array.from(sections.flatMap(s=>s.entries),e=>[e.id,e.canonicalIndex]),[['a',0],['b',1],['c',2]]);
  });
  await test('reverse is presentation only, never mutates IDs/stored ordinals',async()=>{
    const c=ctx.Chapters.flatOf(new Map([['a','A'],['b','B'],['c','C']]));
    const reversed=ctx.Nav.sections(c,true,'chapter-tests')[0].entries;
    assert.deepEqual(Array.from(reversed,e=>e.id),['c','b','a']);
    assert.deepEqual(Array.from(reversed,e=>e.canonicalIndex),[2,1,0]);
    assert.deepEqual(Array.from(c.ids),['a','b','c']);
  });
  await test('duplicate ID across groups displayed once with stable canonical index',async()=>{
    const c=ctx.Chapters.groupedOf(new Map([['one',new Map([['a','A'],['shared','S1']])],['two',new Map([['shared','S2'],['b','B']])]]));
    const entries=ctx.Nav.sections(c,false,'chapter-tests').flatMap(s=>s.entries);
    assert.equal(entries.filter(e=>e.id==='shared').length,1);assert.equal(entries.find(e=>e.id==='b').canonicalIndex,2);
  });
  await test('undefined/empty chapter model safely yields no groups',async()=>{
    assert.equal(ctx.Nav.sections(undefined,false,'chapter-tests').length,0);
    assert.equal(ctx.Nav.sections(ctx.Chapters.empty(),false,'chapter-tests').length,0);
  });
  await test('detail group collapse and reverse do not change source chapter object',async()=>{
    const p=new ctx.Page(),c=ctx.Chapters.groupedOf(new Map([['group',new Map([['a','A'],['b','B']])]]));
    p.details={chapters:c};p.toggleGroup('group');assert.equal(p.collapsedGroups.includes('group'),true);
    p.toggleGroup('group');assert.equal(p.collapsedGroups.length,0);p.toggleChapterOrder();
    assert.deepEqual(Array.from(p.chapterSections[0].entries,e=>e.id),['b','a']);assert.deepEqual(Array.from(c.ids),['a','b']);
  });
  await test('recommendations route by their own source, never current detail source',async()=>{
    const p=new ctx.Page();p.sourceKey='current';p.openRecommendation({id:'rec',sourceKey:'other',title:'R',cover:'C'});
    await new Promise(r=>setImmediate(r));assert.equal(routes.at(-1).params.sourceKey,'other');
  });
  await test('unavailable/empty/disposed recommended routes rejected before navigation',async()=>{
    routes.length=0;const p=new ctx.Page();
    for(const comic of [{id:'',sourceKey:'other'},{id:'rec',sourceKey:''},{id:'rec',sourceKey:'missing'}])p.openRecommendation(comic);
    p.disposed=true;p.openRecommendation({id:'rec',sourceKey:'other'});assert.equal(routes.length,0);
  });
  console.log(`PASS ${count} production grouped chapters/recommendation routing cases; device UI pending.`);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1});
