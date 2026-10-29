'use strict';
// Every Select ends with `.onSelect(...)` in this project, so append the shared
// light-mode colour chain there: no system/dark theme can paint white text on
// our light surfaces or an unstyled dropdown background.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const CHAIN = '.fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent)'
  + '.optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface)'
  + '.selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface)';

const expected = {
  'entry/src/main/ets/features/SearchView.ets': 2,
  'entry/src/main/ets/features/CategoryView.ets': 1,
  'entry/src/main/ets/features/ExploreView.ets': 1,
  'entry/src/main/ets/pages/RankingPage.ets': 1,
  'entry/src/main/ets/pages/CategoryComicsPage.ets': 1,
  'entry/src/main/ets/pages/NetworkFavoritesPage.ets': 2,
  'entry/src/main/ets/components/CollectionActionsPanel.ets': 1,
  'entry/src/main/ets/pages/SourceSettingsPage.ets': 1
};

let total = 0;
for (const [file, count] of Object.entries(expected)) {
  const full = path.join(root, file);
  const text = fs.readFileSync(full, 'utf8');
  const found = text.split('.onSelect(').length - 1;
  if (found !== count) { throw new Error(`${file}: expected ${count} Select tails, found ${found}`); }
  if (text.includes(CHAIN)) { throw new Error(`${file}: colour chain already present`); }
  fs.writeFileSync(full, text.split('.onSelect(').join(`${CHAIN}.onSelect(`));
  total += count;
  console.log(`PATCHED ${file} (${count})`);
}
if (total !== 10) { throw new Error(`expected 10 Selects, patched ${total}`); }
console.log('SELECT_COLOR_CHAIN_APPLIED=10');
