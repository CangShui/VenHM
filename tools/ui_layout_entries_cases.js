'use strict';
// UI entry/layout contracts for the three reported issues. Source-level and
// production-method checks only: no SDK build, device, network or user data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'logs/ui-detail-bookshelf-20261030');
fs.mkdirSync(folder,{recursive:true});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const clean=p=>read(p).replace(/^import\b.*;\r?\n/gm,'').replace(/\bexport /g,'');
let count=0,finished=false;const EXPECTED=10;
process.on('beforeExit',()=>{if(!finished){console.error(`UI_LAYOUT_INCOMPLETE ${count}/${EXPECTED}`);process.exitCode=1}});
function test(name,fn){fn();count++;console.log('PASS '+name)}
const between=(text,from,to)=>{const a=text.indexOf(from),b=text.indexOf(to,a+1);if(a<0||b<0)throw Error(`slice not found: ${from.slice(0,40)}`);return text.slice(a,b)};

// ---------------------------------------------------------------- 1. details
test('details page shows no orphan favourite button and hands the action to the panel',()=>{
  const details=read('entry/src/main/ets/pages/ComicDetailsPage.ets');
  assert.doesNotMatch(details,/Blank\(\)\s*\n\s*Text\(this\.isFavorite/);
  assert.match(details,/onLocalFavorite: \(\) => \{ this\.showFolderPanel = !this\.showFolderPanel; \}/);
  assert.match(details,/if \(this\.showFolderPanel\) \{\s*\n\s*this\.favoritePanel\(\)/);
});

test('local and network favourite buttons render as one equal row inside the panel',()=>{
  const panel=read('entry/src/main/ets/components/CollectionActionsPanel.ets');
  const row=between(panel,'Row({ space: 10 }) {','}.width(\'100%\')');
  assert.match(row,/Button\(this\.localFavoriteLabel\)/);
  assert.match(row,/Button\('网络收藏'\)/);
  assert.equal((row.match(/layoutWeight\(1\)/g)||[]).length,2,'both buttons share the row equally');
  assert.match(row,/onClick\(\(\) => \{ this\.onLocalFavorite\?\.\(\); \}\)/);
});

// ---------------------------------------------------------------- 2. bookshelf
test('bookshelf no longer renders the removed network/local collection buttons',()=>{
  const shelf=read('entry/src/main/ets/features/BookshelfView.ets');
  assert.doesNotMatch(shelf,/Button\('网络收藏'\)/);
  assert.doesNotMatch(shelf,/Button\('本地收藏'\)/);
});

test('bookshelf drops the inline new/rename/delete/move toolbar rows',()=>{
  const shelf=read('entry/src/main/ets/features/BookshelfView.ets');
  for(const label of ['新建收藏夹','重命名','删除夹','前移','后移']){
    assert.doesNotMatch(shelf,new RegExp(`Text\\('${label}'\\)`),label);
  }
  // Multi-select was removed together with its toolbar: no button and no state.
  assert.doesNotMatch(shelf,/多选/);
  assert.doesNotMatch(shelf,/selectedKeys|multiSelect|selectionBar|actionBar/);
});

test('folder long press opens rename/move/delete menu with the default-folder guard',()=>{
  const shelf=read('entry/src/main/ets/features/BookshelfView.ets');
  assert.match(shelf,/\.gesture\(LongPressGesture\(\{ repeat: false \}\)\.onAction\(\(\) => \{ this\.folderMenu\(folder\); \}\)\)/);
  const menu=between(shelf,'private async folderMenu(folder: FavoriteFolder)','// ---- folder operations ----');
  for(const action of ['重命名','前移','后移','删除此收藏夹'])assert.ok(menu.includes(action),action);
  assert.match(menu,/showActionMenu/);
  assert.match(menu,/默认收藏夹不能重命名或删除/);
  assert.match(menu,/this\.moveFolder\(-1\)/);
  assert.match(menu,/this\.moveFolder\(1\)/);
  assert.match(menu,/this\.confirmDeleteFolder\(\)/);
});

test('top bar "+" sits level with the search icon and only on the bookshelf tab',()=>{
  const index=read('entry/src/main/ets/pages/Index.ets');
  const bar=between(index,'topBar() {','}.width(\'100%\').padding');
  const plus=bar.indexOf('action_new_folder'),search=bar.indexOf('action_search');
  assert.ok(plus>0&&search>plus,'+ must precede/align with search in the same row');
  assert.match(bar,/UiIcon\(\{ name: 'plus', iconSize: 21 \}\)/);
  assert.match(bar,/visibility\(this\.currentIndex === 1 \? Visibility\.Visible : Visibility\.None\)/);
  assert.match(bar,/ShelfCommands\.newFolder\(\)/);
});

test('shelf command bus opens the new-folder editor only while the shelf is alive',()=>{
  const shelf=read('entry/src/main/ets/features/BookshelfView.ets');
  assert.match(shelf,/ShelfCommands\.addListener\(this\.onNewFolderCommand\)/);
  assert.match(shelf,/ShelfCommands\.removeListener\(this\.onNewFolderCommand\)/);
  assert.match(shelf,/private openNewFolderEditor\(\): void \{[^}]*this\.panelMode = 'new'/);
  const ctx=vm.createContext({});
  vm.runInContext(stripTypeScriptTypes(clean('entry/src/main/ets/features/ShelfCommands.ets'),{mode:'transform'})
    +'\nglobalThis.S= ShelfCommands;',ctx);
  const S=ctx.S;let hits=0;const listener=()=>{hits++};
  S.addListener(listener);S.addListener(listener);S.newFolder();
  assert.equal(hits,1,'duplicate registration must not fire twice');
  S.removeListener(listener);S.newFolder();assert.equal(hits,1,'removed listener is not called');
});

// ---------------------------------------------------------------- 3. footers
test('explore/search/category keep count and load-more inside the scrolling grid',()=>{
  const files=[
    'entry/src/main/ets/features/ExploreView.ets',
    'entry/src/main/ets/features/SearchView.ets',
    'entry/src/main/ets/pages/CategoryComicsPage.ets'
  ];
  for(const file of files){
    const text=read(file);
    const gridStart=text.indexOf('Grid() {');
    const gridEnd=text.indexOf('.columnsTemplate',gridStart);
    assert.ok(gridStart>0&&gridEnd>gridStart,file);
    const grid=text.slice(gridStart,gridEnd);
    assert.match(grid,/'加载更多'|'已到末页'|'重试加载更多'/,file+' load-more button inside grid');
    assert.match(grid,/columnStart\(0\)\.columnEnd\(2\)/,file+' full-width footer row');
    // Nothing after the grid may still render the footer.
    const tail=text.slice(gridEnd);
    assert.doesNotMatch(tail,/'已加载 |'加载更多'/,file+' footer must not be pinned below the grid');
  }
});

test('footer grid item keeps the horizontal page padding so it aligns with cards',()=>{
  for(const file of ['entry/src/main/ets/features/ExploreView.ets','entry/src/main/ets/features/SearchView.ets']){
    const text=read(file);
    const gridStart=text.indexOf('Grid() {');
    const gridEnd=text.indexOf('.columnsTemplate',gridStart);
    const grid=text.slice(gridStart,gridEnd);
    assert.match(grid,/padding\(\{ top: 10, bottom: 28 \}\)/,file);
    assert.match(grid,/alignItems\(HorizontalAlign\.Center\)/,file);
  }
});

test('retired footer containers do not reintroduce a permanent bottom block',()=>{
  const explore=read('entry/src/main/ets/features/ExploreView.ets');
  // The page still reserves space for the floating navigation, but that is
  // page padding, not a footer card pinned above it.
  assert.match(explore,/padding\(\{ bottom: UiTheme\.bottomInset \}\)/);
  assert.doesNotMatch(explore,/'加载更多'\)\)\s*\n\s*\.attributeModifier\(UiStyles\.secondary\)\.margin\(\{ bottom: 16 \}\)/);
});

assert.equal(count,EXPECTED);finished=true;
fs.writeFileSync(path.join(folder,'cases.json'),JSON.stringify({cases:count,scope:'details favourite row, bookshelf toolbar/long-press, grid footers; source + VM only'},null,2));
console.log(`PASS ${count} UI entry/layout contracts for the three reported issues; no device or rendering acceptance`);
