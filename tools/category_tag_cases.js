'use strict';
// Executes production ArkTS helpers/lifecycle bodies with deterministic SDK/source fakes.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '..'), log = path.join(root, 'logs/category-tag-cases.log');
fs.mkdirSync(path.dirname(log), { recursive: true });
fs.writeFileSync(log, '[请求到达] TraceID=category-tag-tests production methods; deterministic fakes, not device evidence\n');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const clean = code => code.replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
const audit = (trace, stage, message) => fs.appendFileSync(log, `TraceID=${trace} [${stage}] ${message}\n`);
function load(file, name, scope = {}, cut) {
  let code = clean(read(file));
  if (name === 'ComicDetailsPage') {
    const start = code.indexOf('  @Builder\n  favoritePanel()');
    const end = code.indexOf('  private async copyMetadata');
    if (start >= 0 && end > start) code = code.slice(0, start) + code.slice(end);
  }
  if (cut) code = code.slice(0, code.indexOf(cut)) + '}';
  code = code.replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace(`struct ${name}`, `class ${name}`);
  const ctx = vm.createContext({ Log: { audit }, ...scope });
  const diagnostic = name === 'SourceFailure' ? '' : clean(read('entry/src/main/ets/features/SourceFailure.ets'));
  // The details page now imports media/share modules that this tag/category
  // suite does not exercise; their real behaviour lives in tools/details_cases.js.
  const stubs = name === 'ComicDetailsPage' ? require('./vm_deps').DETAILS_STUBS : '';
  vm.runInContext(stripTypeScriptTypes(stubs + '\n' + diagnostic + '\n' + code, { mode: 'transform' }) + `\nglobalThis.Target=${name};`, ctx);
  return { ctx, Type: ctx.Target };
}
const Res = load('entry/src/main/ets/model/Res.ets', 'Res').Type;
const ok = (items, max) => new Res(items, undefined, max);
const comic = (id, sourceKey = 'original') => ({ id, sourceKey, title: id, cover: '', subtitle: '' });
const tick = () => new Promise(r => setImmediate(r));
const defer = () => { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; };
const pages = 'entry/src/main/ets/pages/CategoryComicsPage.ets';
function results(source) {
  const params = { sourceKey: 'original', label: 'display', page: 'category', category: 'actual-category', param: 'actual-param' };
  const e = load(pages, 'CategoryComicsPage', { SourceManager: { find: key => key === source.key ? source : undefined }, AppInit: { init: async () => {} } }, '  build() {');
  const p = new e.Type(); p.params = params; return p;
}
let count = 0;
async function test(name, fn) { await fn(); count++; fs.appendFileSync(log, `[响应返回] TraceID=category-tag-tests PASS ${name}\n`); }
(async () => {
  await test('source diagnostics keep technical evidence without secret/body echoes or SDK/HTTP confusion',async()=>{
    const failure=load('entry/src/main/ets/features/SourceFailure.ets','SourceFailure').Type;
    assert.match(failure.message('HTTP 403 body: secret'),/HTTP 403/);
    assert.match(failure.message('code 401 Parameter error'),/SDK.*401/);
    assert.doesNotMatch(failure.message('code 401 Parameter error'),/HTTP 401/);
    for(const text of ['Bearer private-token','Cookie: secret=data','arbitrary account=john@example.com','<html>private page</html>']){
      const message=failure.message(text);assert.doesNotMatch(message,/private|secret|john|html|Bearer|Cookie/);
    }
    assert.match(failure.message('TypeError: cannot read property token of undefined'),/TypeError/);
    assert.match(failure.message('Setting not found: default_username'),/设置/);
  });
  await test('shared key restoration, reorder, unsubscribe, ordered persistence and explicit unavailable key', async () => {
    const writes = [], persisted = { value: 'b' }, gates = [];
    let sources = [{ key: 'a' }, { key: 'b' }];
    const e = load('entry/src/main/ets/features/SelectedSource.ets', 'SelectedSource', {
      Settings: { getString: () => persisted.value, setString: async (key, value) => { writes.push(value); const gate = defer(); gates.push(gate); await gate.promise; persisted.value = value; } },
      SourceManager: { all: () => sources }
    });
    const s = e.Type, observed = [];
    assert.equal(s.initialize(), 'b'); sources.reverse(); assert.equal(s.initialize(), 'b');
    const id = s.subscribe(key => observed.push(key)); s.select('a'); s.select('removed'); await tick();
    assert.equal(s.current(), 'removed'); assert.deepEqual(observed, ['a', 'removed']); assert.deepEqual(writes, ['a']);
    gates[0].resolve(); await tick(); assert.deepEqual(writes, ['a', 'removed']); gates[1].resolve(); await tick();
    assert.equal(persisted.value, 'removed'); assert.equal(s.initialize(), 'removed');
    s.unsubscribe(id); s.select('b'); await tick(); gates[2].resolve(); await tick(); assert.equal(observed.length, 2);
  });
  await test('preference failure is visible and same-key selection retries persistence', async () => {
    const toasts=[],writes=[];let fail=true;
    const s=load('entry/src/main/ets/features/SelectedSource.ets','SelectedSource',{
      Settings:{getString:()=> 'a',setString:async(k,v)=>{writes.push(v);if(fail)throw Error('private body');}},
      SourceManager:{all:()=>[{key:'a'}]},promptAction:{showToast:t=>toasts.push(t.message)}
    }).Type;
    s.initialize();s.select('b');await tick();assert.equal(s.current(),'b');assert.equal(toasts.length,1);
    fail=false;s.select('b');await tick();assert.deepEqual(writes,['b','b']);assert.equal(toasts.length,1);
    assert.doesNotMatch(fs.readFileSync(log,'utf8'),/private body/);
  });
  await test('both tabs subscribe and select a single key despite capability differences', async () => {
    const sources = [{ key: 'a', name: 'A', explorePages: [], loadCategoryData: async () => ({ parts: [{ items: [{}] }] }) },
      { key: 'b', name: 'B', explorePages: [{ title: 'B', loadPage: async () => ok([comic('b','b')],1) }] }];
    const shared = load('entry/src/main/ets/features/SelectedSource.ets', 'SelectedSource', {
      Settings: { getString: () => 'a', setString: async () => {} }, SourceManager: { all: () => sources }
    }).Type;
    const scope = { AppInit: { init: async () => {} }, SelectedSource: shared,
      SourceManager: { all: () => sources, find: k => sources.find(s => s.key === k) }, ExplorePageType: { multiPageComicList: 0 } };
    const explore = new (load('entry/src/main/ets/features/ExploreView.ets', 'ExploreView', scope, '  @Builder').Type)();
    const category = new (load('entry/src/main/ets/features/CategoryView.ets', 'CategoryView', scope, '  build() {').Type)();
    explore.aboutToAppear(); category.aboutToAppear(); await tick();
    assert.equal(explore.selectedSourceKey, 'a'); assert.match(explore.error, /不支持探索/);
    assert.equal(category.selectedSourceKey, 'a'); shared.select('b'); await tick();
    assert.equal(explore.selectedSourceKey, 'b'); assert.equal(category.selectedSourceKey, 'b'); assert.match(category.error, /不支持分类/);
    assert.equal(category.sourceNames.length, 2); assert.equal(explore.sourceNames.length, 2);
    explore.aboutToDisappear(); category.aboutToDisappear(); shared.select('a'); assert.equal(category.selectedSourceKey, 'b');
  });
  await test('explore cursor adapter first then opaque URL cursor with redacted retryable diagnostics', async () => {
    const calls=[];let fail=true;const cursor='https://fixture.invalid/next?token=private';
    const source={key:'original',explorePages:[{cursorOnly:true,type:0,
      loadPage:async page=>{calls.push(['first',page]);return ok([comic('one')],cursor);},
      loadNext:async next=>{calls.push(['next',next]);if(fail)return Res.fail('SCRIPT200TagMissing '+cursor);return ok([comic('two')],null);}
    }]};
    const p=new (load('entry/src/main/ets/features/ExploreView.ets','ExploreView',{
      SourceManager:{find:()=>source},ExplorePageType:{multiPageComicList:0}
    },'  @Builder').Type)();p.selectedSourceKey='original';p.initialized=true;
    await p.loadPage(1);assert.equal(p.hasMore,true);assert.equal(p.nextCursor,cursor);
    await p.loadPage(2);assert.match(p.error,/SCRIPT200TagMissing/);assert.doesNotMatch(p.error,/token=private/);
    assert.equal(p.currentPage,1);assert.equal(p.nextCursor,cursor);assert.equal(p.comics.length,1);
    fail=false;await p.loadPage(2);assert.deepEqual(calls,[['first',1],['next',cursor],['next',cursor]]);
    assert.equal(p.currentPage,2);assert.equal(p.comics.length,2);assert.equal(p.hasMore,false);
    p.loadFirstPage();assert.equal(p.nextCursor,undefined);await tick();assert.equal(p.hasMore,true);
  });
  await test('explore late old cursor response cannot overwrite the newer source cursor', async () => {
    const old=defer();let source={key:'old',explorePages:[{cursorOnly:true,type:0,loadPage:()=>old.promise}]};
    const p=new (load('entry/src/main/ets/features/ExploreView.ets','ExploreView',{
      SourceManager:{find:()=>source},ExplorePageType:{multiPageComicList:0}
    },'  @Builder').Type)();p.selectedSourceKey='old';
    const first=p.loadPage(1);source={key:'new',explorePages:[{cursorOnly:true,type:0,loadPage:async()=>ok([comic('new','new')],'new-cursor')}]};
    p.selectedSourceKey='new';await p.loadPage(1);old.resolve(ok([comic('old','old')],'old-cursor'));await first;
    assert.equal(p.nextCursor,'new-cursor');assert.equal(p.comics[0].id,'new');
  });
  await test('explore numeric max-page pagination remains separate from cursor mode', async () => {
    const pages=[],source={key:'original',explorePages:[{cursorOnly:false,type:0,loadPage:async page=>{pages.push(page);return ok([comic('p'+page)],2);}}]};
    const p=new (load('entry/src/main/ets/features/ExploreView.ets','ExploreView',{
      SourceManager:{find:()=>source},ExplorePageType:{multiPageComicList:0}
    },'  @Builder').Type)();p.selectedSourceKey='original';await p.loadPage(1);assert.equal(p.hasMore,true);
    await p.loadPage(2);assert.equal(p.hasMore,false);await p.loadPage(3);assert.deepEqual(pages,[1,2]);
  });
  await test('category absence, synchronous throw and empty data end loading with visible errors', async () => {
    for (const source of [{ key: 'original' }, { key: 'original', loadCategoryData: () => { throw Error('fixture'); } },
      { key: 'original', loadCategoryData: async () => ({ parts: [] }) }]) {
      const p = new (load('entry/src/main/ets/features/CategoryView.ets', 'CategoryView', { SourceManager: { find: () => source } }, '  build() {').Type)();
      p.selectedSourceKey = 'original'; await p.loadCategories(); assert.equal(p.loading, false); assert.ok(p.error);
    }
  });
  await test('category loading starts synchronously and stale finally cannot stop a new request', async () => {
    const first = defer(), second = defer(); let calls = 0;
    const source = { loadCategoryData: () => ++calls === 1 ? first.promise : second.promise };
    const p = new (load('entry/src/main/ets/features/CategoryView.ets', 'CategoryView', { SourceManager: { find: () => source } }, '  build() {').Type)();
    const old = p.loadCategories(); assert.equal(p.loading, true); const current = p.loadCategories();
    first.resolve({ parts: [{ title:'old', items:[{}] }] }); await old; assert.equal(p.loading, true); assert.equal(p.category, undefined);
    second.resolve({ parts: [{ title:'new', items:[{}] }] }); await current; assert.equal(p.loading, false); assert.equal(p.category.parts[0].title, 'new');
  });
  await test('results pass exact category param options and page; option changes reset page one', async () => {
    const calls = [], p = results({ key: 'original', categoryComics: {
      options: [{ label: 'Sort', options: new Map([['latest','Latest'],['popular','Popular']]), notShowWhen: [] }],
      load: async (category,param,options,page) => { calls.push([category,param,Array.from(options),page]); return ok([comic('p'+page)],3); }
    } });
    const pending = p.load(1,true); assert.equal(p.loading,true); await pending; await p.load(2);
    assert.deepEqual(calls, [['actual-category','actual-param',['latest'],1],['actual-category','actual-param',['latest'],2]]);
    p.optionValues = ['popular']; await p.load(1); assert.equal(p.comics.length,1); assert.equal(calls[2][2][0],'popular');
  });
  await test('dynamic option loading filters visibility and preserves key order', async () => {
    const calls=[],p=results({ key:'original',categoryComics:{
      optionsLoader:async(category,param)=>{calls.push([category,param]);return ok([
        {label:'hidden',options:new Map([['x','X']]),notShowWhen:['actual-category']},
        {label:'shown',options:new Map([['key-with-dash','label']]),notShowWhen:[],showWhen:['actual-category']}]);},
      load:async(c,param,options)=>{calls.push(Array.from(options));return ok([comic('one')],1);}
    }});
    await p.load(1,true);assert.equal(p.options.length,1);assert.deepEqual(calls,[['actual-category','actual-param'],['key-with-dash']]);
  });
  await test('source initial category option keys win over defaults and invalid arrays fail explicitly', async () => {
    for(const initial of [['popular'],['invalid-key'],['popular','unexpected']]) {
      const calls=[],p=results({key:'original',categoryComics:{
        options:[{label:'sort',options:new Map([['latest','Latest'],['popular','Popular']]),notShowWhen:[]}],
        load:async(c,param,options)=>{calls.push(Array.from(options));return ok([comic('one')],1);}
      }});
      p.params.options=initial;await p.load(1,true);
      if(initial.length===1&&initial[0]==='popular'){assert.deepEqual(calls,[['popular']]);assert.equal(p.error,'');}
      else{assert.equal(calls.length,0);assert.match(p.error,/初始分类选项无效/);assert.equal(p.loading,false);}
    }
  });
  await test('modern text target and search options arrays survive routing and cursor pagination', async () => {
    class CategoryItem { constructor(){this.label='tag';this.page='search';this.attributes=new Map([['text','exact text'],['keyword','wrong fallback']]);this.initialOptions=['option-one','option-two'];} }
    const T=load('entry/src/main/ets/features/TagRouting.ets','TagRouting',{CategoryItem}).Type;
    const item=new CategoryItem(),params=T.params('original',item);item.initialOptions[0]='mutated';
    assert.equal(params.keyword,'exact text');assert.deepEqual(Array.from(params.options),['option-one','option-two']);
    const calls=[],p=results({key:'original',search:{cursorOnly:true,
      loadPage:async(k,page,o)=>{calls.push([k,page,Array.from(o)]);return ok([comic('one')],'next');},
      loadNext:async(k,next,o)=>{calls.push([k,next,Array.from(o)]);return ok([comic('two')],null);}
    }});p.params=params;await p.load(1,true);await p.load(2);
    assert.deepEqual(calls,[['exact text',1,['option-one','option-two']],['exact text','next',['option-one','option-two']]]);
  });
  await test('EH category-only empty keyword search preserves filters but missing/no-op targets fail', async () => {
    class CategoryItem {constructor(){this.label='Category';this.page='search';this.attributes=new Map([['keyword','']]);this.initialOptions=['1','',''];}}
    const T=load('entry/src/main/ets/features/TagRouting.ets','TagRouting',{CategoryItem}).Type;
    const item=new CategoryItem(),params=T.params('original',item);assert.equal(params.keyword,'');
    const calls=[],p=results({key:'original',search:{cursorOnly:false,
      loadPage:async(k,page,o)=>{calls.push([k,page,Array.from(o)]);return ok([comic('filtered')],1);}
    }});p.params=params;await p.load(1,true);assert.deepEqual(calls,[['',1,['1','','']]]);assert.equal(p.error,'');
    item.initialOptions=[];assert.throws(()=>T.params('original',item),/筛选选项/);
    item.attributes.delete('keyword');item.initialOptions=['1','',''];assert.throws(()=>T.params('original',item),/筛选选项/);
    for(const bad of [{keyword:'',options:[]},{keyword:undefined,options:['1','','']}]){
      p.params={sourceKey:'original',label:'Category',page:'search',...bad};await p.load(1,true);
      assert.ok(p.error);assert.equal(p.loading,false);assert.equal(calls.length,1);
    }
  });
  await test('option error, capability absence, result error and empty list have retryable errors', async () => {
    for (const source of [{ key:'original' }, { key:'original',categoryComics:{load:async()=>ok([])} },
      { key:'original',categoryComics:{load:async()=>Res.fail('fixture')} },
      { key:'original',categoryComics:{optionsLoader:async()=>Res.fail('fixture'),load:async()=>ok([comic('one')])} }]) {
      const p=results(source);await p.load(1,true);assert.equal(p.loading,false);assert.ok(p.error);
    }
  });
  await test('append failure preserves comics and retries same real page', async () => {
    const calls=[];let fail=true;const p=results({key:'original',categoryComics:{load:async(c,param,o,page)=>{
      calls.push(page);if(page===2&&fail)throw Error('fixture');return ok([comic('p'+page)],3);
    }}});
    await p.load(1,true);await p.load(2);assert.equal(p.currentPage,1);assert.equal(p.comics.length,1);assert.ok(p.error);
    fail=false;p.retry();await tick();assert.deepEqual(calls,[1,2,2]);assert.equal(p.currentPage,2);assert.equal(p.error,'');
  });
  await test('late result/options callback and stale finally do not mutate newer results', async () => {
    const old=defer(),next=defer();let calls=0;
    const p=results({key:'original',categoryComics:{load:()=>++calls===1?old.promise:next.promise}});
    const first=p.load(1,true);await tick();const second=p.load(1,true);await tick();
    old.resolve(ok([comic('old')],1));await first;assert.equal(p.loading,true);assert.equal(p.comics.length,0);
    next.resolve(ok([comic('new')],1));await second;assert.equal(p.comics[0].id,'new');assert.equal(p.loading,false);
  });
  await test('hidden result page ignores pending network response and duplicate more is coalesced', async () => {
    const gate=defer();let calls=0;
    const p=results({key:'original',categoryComics:{load:async(c,param,o,page)=>{calls++;return page===1?ok([comic('one')],3):gate.promise;}}});
    await p.load(1,true);const pending=p.load(2);await tick();await p.load(2);assert.equal(calls,2);
    p.onPageHide();gate.resolve(ok([comic('late')],3));await pending;assert.equal(p.comics.length,1);assert.equal(p.loading,false);
  });
  await test('source-locked search target uses exact keyword and cursor pagination', async () => {
    const calls=[],p=results({key:'original',search:{cursorOnly:true,loadPage:async(k,page,o)=>{calls.push([k,page]);return ok([comic('one')],'cursor');},
      loadNext:async(k,cursor,o)=>{calls.push([k,cursor]);return ok([comic('two')],null);}}});
    p.params={sourceKey:'original',label:'label',page:'search',keyword:'artist:name:with:colon'};
    await p.load(1,true);await p.load(2);assert.deepEqual(calls,[['artist:name:with:colon',1],['artist:name:with:colon','cursor']]);assert.equal(p.ended,true);
  });
  await test('tag contracts preserve namespaces and source-provided category name/param, never guessed label', async () => {
    class CategoryItem { constructor(){this.label='';this.page='category';this.attributes=new Map();this.initialOptions=[];} }
    const routes=[],e=load('entry/src/main/ets/features/TagRouting.ets','TagRouting',{CategoryItem,router:{pushUrl:async r=>routes.push(r)}});
    const T=e.Type,tag=T.tags({tags:new Map([['artist',['name:with:colon']]])})[0];
    assert.equal(tag.namespace,'artist');assert.equal(tag.value,'name:with:colon');
    let args;const target=await T.resolve({key:'original',tagTarget:async(ns,value)=>{args=[ns,value];const item=new CategoryItem();item.attributes.set('category','actual-internal-category');item.attributes.set('param','internal-id');return item;}},tag);
    await T.open('original',target,'test');assert.deepEqual(args,['artist','name:with:colon']);assert.equal(routes[0].params.sourceKey,'original');
    assert.equal(routes[0].params.category,'actual-internal-category');assert.equal(routes[0].params.param,'internal-id');
    assert.throws(()=>T.params('original',new CategoryItem()),/缺少/);
    await assert.rejects(()=>T.resolve({tagTarget:async()=>undefined},tag),/未提供/);
  });
  await test('tag fallback is explicit original-source search and unsupported source fails', async () => {
    class CategoryItem { constructor(){this.label='';this.page='';this.attributes=new Map();this.initialOptions=[];} }
    const T=load('entry/src/main/ets/features/TagRouting.ets','TagRouting',{CategoryItem}).Type;
    const tag={namespace:'artist',value:'name:colon',label:'artist:name:colon'};
    const target=await T.resolve({supportsSearch:true},tag);assert.equal(target.page,'search');assert.equal(target.attributes.get('keyword'),'artist:name:colon');
    await assert.rejects(()=>T.resolve({supportsSearch:false},tag),/不支持/);
  });
  await test('clipboard writes full title/author/tag without logging text; exclusive tap/longpress binds', async () => {
    const copies=[],toasts=[],e=load('entry/src/main/ets/pages/ComicDetailsPage.ets','ComicDetailsPage',{
      pasteboard:{MIMETYPE_TEXT_PLAIN:'text/plain',createData:(mime,value)=>({mime,value}),getSystemPasteboard:()=>({setData:async data=>copies.push(data.value)})},
      promptAction:{showToast:t=>toasts.push(t.message)}
    },'  @Builder');
    const p=new e.Type();for(const [value,field] of [['title:complete','标题'],['author:complete','作者'],['artist:tag:complete','标签']])await p.copyMetadata(value,field);
    assert.deepEqual(copies,['title:complete','author:complete','artist:tag:complete']);assert.equal(toasts.length,3);
    const code=read('entry/src/main/ets/pages/ComicDetailsPage.ets');assert.match(code,/GestureGroup\(GestureMode.Exclusive,[\s\S]*LongPressGesture[\s\S]*TapGesture/);
    assert.match(code,/origin: 'details'/);assert.ok(JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src.includes('pages/CategoryComicsPage'));
    assert.doesNotMatch(fs.readFileSync(log,'utf8'),/title:complete|author:complete|artist:tag:complete/);
  });
  const report=`PASS ${count} production shared-source/category/tag/clipboard cases; no full build or device UI run.`;
  fs.appendFileSync(log,report+'\n');console.log(report);
})().catch(e=>{fs.appendFileSync(log,e.stack+'\n');console.error(e);process.exitCode=1;});
