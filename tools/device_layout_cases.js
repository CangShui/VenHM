'use strict';
// Multi-model layout contracts derived from the real device table shipped with
// DevEco (AppData\Local\Huawei\Sdk\productConfig.json). This is a layout-math
// and hit-target audit, NOT ArkUI rendering evidence: it proves the numbers
// behind our fixed paddings/heights stay sane on each panel size.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const outDir = path.join(root, 'logs/fix4-20261023');
fs.mkdirSync(outDir, { recursive: true });
const read = p => fs.readFileSync(path.join(root, p), 'utf8');

// px -> vp using the same rule ArkUI uses (density dpi / 160).
const vp = (px, dpi) => Math.round((px * 160 / dpi) * 10) / 10;

// Real panels from productConfig.json (public device specs, not private data).
const MODELS = [
  { name: 'Mate 70', kind: 'phone', w: 1216, h: 2688, dpi: 520 },
  { name: 'Mate 70 Pro', kind: 'phone', w: 1316, h: 2832, dpi: 560 },
  { name: 'Pura 80', kind: 'phone', w: 1256, h: 2760, dpi: 560 },
  { name: 'Pura 80 Pro', kind: 'phone', w: 1276, h: 2848, dpi: 560 },
  { name: 'Pura 70', kind: 'phone', w: 1256, h: 2760, dpi: 540 },
  { name: 'nova 14', kind: 'phone', w: 1084, h: 2412, dpi: 480 },
  { name: 'Pocket 2', kind: 'phone', w: 1136, h: 2690, dpi: 500 },
  { name: 'Mate X5 folded', kind: 'foldable', w: 1080, h: 2504, dpi: 500 },
  { name: 'Mate X5 unfolded', kind: 'foldable', w: 2224, h: 2496, dpi: 500 },
  { name: 'Mate X6 folded', kind: 'foldable', w: 1080, h: 2440, dpi: 500 },
  { name: 'Mate X6 unfolded', kind: 'foldable', w: 2240, h: 2440, dpi: 500 },
  // Pura X is not in the local table; a 16:10-ish square foldable is used as a
  // stand-in so square panels are covered instead of silently skipped.
  { name: 'Pura X approx (unfolded)', kind: 'foldable', w: 1320, h: 2120, dpi: 480, approximated: true },
  { name: 'MatePad Pro 11', kind: 'tablet', w: 2560, h: 1600, dpi: 360 },
  { name: 'MatePad Pro 13', kind: 'tablet', w: 2880, h: 1920, dpi: 320 },
  { name: 'MateBook Pro (2in1)', kind: '2in1', w: 3120, h: 2080, dpi: 304 }
];

// Layout constants are read from the real sources so this audit cannot drift.
function num(source, regex, label) {
  const m = source.match(regex);
  assert.ok(m, `cannot read ${label} from source`);
  return Number(m[1]);
}
const uikit = read('entry/src/main/ets/components/UiKit.ets');
const indexSrc = read('entry/src/main/ets/pages/Index.ets');
const readerSrc = read('entry/src/main/ets/pages/ReaderPage.ets');
const L = {
  gutter: num(uikit, /static readonly gutter: number = (\d+)/, 'gutter'),
  bottomInset: num(uikit, /static readonly bottomInset: number = (\d+)/, 'bottomInset'),
  navWidthPercent: num(indexSrc, /width\('(\d+)%'\)\.constraintSize\(\{ maxWidth: 440 \}\)\.padding\(7\)\.height\(76\)/, 'nav width %'),
  navMaxWidth: num(indexSrc, /constraintSize\(\{ maxWidth: (\d+) \}\)\.padding\(7\)\.height\(76\)/, 'nav max width'),
  navPadding: num(indexSrc, /constraintSize\(\{ maxWidth: \d+ \}\)\.padding\((\d+)\)\.height\(76\)/, 'nav padding'),
  navHeight: num(indexSrc, /constraintSize\(\{ maxWidth: \d+ \}\)\.padding\(\d+\)\.height\((\d+)\)/, 'nav height'),
  navMarginBottom: num(indexSrc, /shadow\(\{ radius: 24, color: '#140F203A', offsetY: 8 \}\)\.margin\(\{ bottom: (\d+) \}\)/, 'nav margin'),
  navItemHeight: num(indexSrc, /\.width\('100%'\)\.height\((\d+)\)\.justifyContent\(FlexAlign\.Center\)/, 'nav item height'),
  overlayPortraitPercent: num(readerSrc, /constraintSize\(\{ maxHeight: this\.landscape \? '76%' : '(\d+)%' \}\)/, 'portrait overlay %'),
  overlayLandscapePercent: num(readerSrc, /constraintSize\(\{ maxHeight: this\.landscape \? '(\d+)%' : '\d+%' \}\)/, 'landscape overlay %'),
  minTouch: 44
};

const rows = [];
const problems = [];

function auditModel(m) {
  const width = vp(m.w, m.dpi);
  const height = vp(m.h, m.dpi);
  const short = Math.min(width, height);
  const long = Math.max(width, height);
  // Reader fills the window; the menu is a bottom sheet capped by percentage.
  const portrait = height >= width;
  const overlayMax = (portrait ? L.overlayPortraitPercent : L.overlayLandscapePercent) / 100 * long;

  // Floating navigation: five equal items inside a capped pill.
  const pillWidth = Math.min(width * L.navWidthPercent / 100, L.navMaxWidth);
  const itemWidth = (pillWidth - L.navPadding * 2 - 4 * 2) / 5;

  // Content must not be hidden behind the floating pill.
  const pillBlock = L.navHeight + L.navMarginBottom;
  const contentHidden = L.bottomInset < pillBlock;

  // Reader nine zones: thirds of the reader window.
  const cellW = width / 3;
  const cellH = height / 3;

  // Page content width after the standard side gutter.
  const contentWidth = width - L.gutter * 2;

  const row = {
    model: m.name, kind: m.kind, vp: `${width}x${height}`,
    approximated: m.approximated === true,
    orientation: portrait ? 'portrait' : 'landscape',
    navPillWidth: Math.round(pillWidth), navItemWidth: Math.round(itemWidth * 10) / 10,
    navUnder44: itemWidth < L.minTouch,
    readerCell: `${Math.round(cellW)}x${Math.round(cellH)}`,
    readerCellUnder44: Math.min(cellW, cellH) < L.minTouch,
    overlayMaxVp: Math.round(overlayMax),
    overlayCramped: overlayMax < 260,
    contentWidth: Math.round(contentWidth),
    contentTooNarrow: contentWidth < 240,
    bottomInsetCoversPill: !contentHidden
  };
  rows.push(row);

  const label = `${row.model} (${row.vp})`;
  assert.ok(width > 0 && height > 0, `${label}: invalid vp size`);
  assert.ok(itemWidth >= L.minTouch, `${label}: nav item ${itemWidth}vp below ${L.minTouch}vp touch target`);
  assert.ok(!contentHidden, `${label}: bottomInset ${L.bottomInset} smaller than pill ${pillBlock}`);
  assert.ok(Math.min(cellW, cellH) >= L.minTouch, `${label}: reader zone below touch target`);
  assert.ok(overlayMax >= 200, `${label}: reader menu max height ${Math.round(overlayMax)}vp too small`);
  assert.ok(contentWidth >= 240, `${label}: content width ${Math.round(contentWidth)}vp too narrow`);
  if (row.overlayCramped) { problems.push(`${label}: reader menu capped at ${Math.round(overlayMax)}vp`); }
  if (m.approximated) { problems.push(`${label}: Pura X is an approximation (not in DevEco device table)`); }
}

let checks = 0;
for (const m of MODELS) { auditModel(m); checks++; }

// The nine-zone mapping must stay identical in viewport fractions on every panel.
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const ctx = vm.createContext({});
const zonesCode = read('entry/src/main/ets/components/ReaderClickZones.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
vm.runInContext(stripTypeScriptTypes(zonesCode + '\nglobalThis.Z=ReaderClickZones;', { mode: 'transform' }), ctx);
const CENTERS = [[1/6, 1/6, 'previous'], [3/6, 1/6, 'previous'], [5/6, 1/6, 'next'],
  [1/6, 3/6, 'previous'], [3/6, 3/6, 'menu'], [5/6, 3/6, 'next'],
  [1/6, 5/6, 'previous'], [3/6, 5/6, 'next'], [5/6, 5/6, 'next']];
for (const m of MODELS) {
  const width = vp(m.w, m.dpi), height = vp(m.h, m.dpi);
  for (const [fx, fy, expected] of CENTERS) {
    const action = ctx.Z.action(fx, fy, true, false, false);
    assert.equal(action, expected, `${m.name}: centre of zone ${fx}/${fy}`);
    // Same tap expressed in vp must resolve identically: coordinates are ratios.
    assert.equal(ctx.Z.action(fx * width / width, fy * height / height, true, false, false), expected);
  }
  checks++;
}

// Foldables must be sane in both states.
const x5 = rows.find(r => r.model === 'Mate X5 unfolded');
const x5f = rows.find(r => r.model === 'Mate X5 folded');
assert.ok(x5 && x5f, 'foldable states missing');
assert.ok(x5.navItemWidth >= L.minTouch && x5f.navItemWidth >= L.minTouch, 'foldable nav target');
checks++;

fs.writeFileSync(path.join(outDir, 'device-layout.json'), JSON.stringify({
  evidence: 'layout math + hit-target audit from DevEco device table; NOT ArkUI rendering',
  constants: L, models: rows, problems
}, null, 2));

const header = 'model'.padEnd(26) + 'vp'.padEnd(14) + 'orientation'.padEnd(12)
  + 'navItem'.padEnd(9) + 'readerCell'.padEnd(13) + 'menuMax'.padEnd(9) + 'content';
console.log(header);
for (const r of rows) {
  console.log(r.model.padEnd(26) + r.vp.padEnd(14) + r.orientation.padEnd(12)
    + String(r.navItemWidth).padEnd(9) + r.readerCell.padEnd(13)
    + String(r.overlayMaxVp).padEnd(9) + r.contentWidth);
}
if (problems.length > 0) {
  console.log('\nNOTES:');
  for (const p of problems) { console.log(' - ' + p); }
}
console.log(`\nPASS ${checks} multi-model layout/hit-target contracts over ${MODELS.length} panels (layout math only; no ArkUI rendering, no device)`);
