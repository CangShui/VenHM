'use strict';
// Local-only regression suite: real pure ArkTS helpers, SDK declarations/parser,
// packaged SVG XML/geometry and actual call sites. No native rendering claims.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const devEco = process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio';
const sdk = path.join(devEco, 'sdk/default/openharmony/ets');
const loader = path.join(sdk, 'build-tools/ets-loader');
const ts = require(path.join(loader, 'node_modules/typescript/lib/typescript.js'));
const { XMLParser, XMLValidator } = require(path.join(devEco,
  'tools/hvigor/hvigor-ohos-plugin/node_modules/fast-xml-parser'));
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const kitFile = 'entry/src/main/ets/components/UiKit.ets';
const metricsFile = 'entry/src/main/ets/components/UiIconMetrics.ets';
const kit = read(kitFile), metrics = read(metricsFile);
const options = ts.parseConfigFileTextToJson(path.join(loader, 'tsconfig.json'),
  fs.readFileSync(path.join(loader, 'tsconfig.json'), 'utf8')).config.compilerOptions;
const tree = (file, text) => ts.createSourceFile(file, text, ts.ScriptTarget.Latest,
  true, ts.ScriptKind.ETS, options);
const walk = (node, visit) => { visit(node); ts.forEachChild(node, child => walk(child, visit)); };
const kitTree = tree(kitFile, kit);
function declaration(name) {
  const node = kitTree.statements.find(n => n.name && n.name.getText(kitTree) === name);
  assert.ok(node, 'missing declaration ' + name);
  return node.getText(kitTree);
}
function compile(source) {
  const result = ts.transpileModule(source, { fileName: 'UiIconLocal.ts', reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const sandbox = { exports: {}, $r: value => value };
  vm.createContext(sandbox);
  vm.runInContext(result.outputText, sandbox, { timeout: 1000 });
  return sandbox.exports;
}
const { uiIconSize, uiIconTintMatrix } = compile(metrics);
const { uiIconPath, uiIconResource } = compile(declaration('uiIconPath') + '\n' + declaration('uiIconResource'));
const icon = declaration('UiIcon');
const names = [...declaration('uiIconResource').matchAll(/case '([^']+)':/g)].map(m => m[1]);
const legacyNames = [...declaration('uiIconPath').matchAll(/case '([^']+)':/g)].map(m => m[1]);
const mediaDir = 'entry/src/main/resources/base/media';
const svgNames = fs.readdirSync(path.join(root, mediaDir)).filter(f => /^ui_icon_.*\.svg$/.test(f));
const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '', parseAttributeValue: false });
const assets = new Map();
for (const filename of svgNames) {
  const xml = read(mediaDir + '/' + filename);
  assert.equal(XMLValidator.validate(xml), true, filename + ' must be well-formed XML');
  assets.set(filename.slice('ui_icon_'.length, -4), { xml, svg: parser.parse(xml).svg });
}
let passed = 0;
function test(name, action) { action(); passed++; console.log('PASS ' + name); }
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-10, `${a} != ${b}`);
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const allFiles = directory => fs.readdirSync(path.join(root, directory), { withFileTypes: true })
  .flatMap(entry => entry.isDirectory() ? allFiles(directory + '/' + entry.name) : [directory + '/' + entry.name]);
const appFiles = allFiles('entry/src/main/ets').filter(file => file.endsWith('.ets'));
const appTrees = appFiles.map(file => ({ file, text: read(file) })).map(record => ({ ...record, ast: tree(record.file, record.text) }));
const calls = [];
for (const record of appTrees) walk(record.ast, node => {
  if (!node.expression || node.expression.getText(record.ast) !== 'UiIcon' || !node.arguments) return;
  assert.equal(node.arguments.length, 1, record.file);
  const props = node.arguments[0];
  assert.ok(ts.isObjectLiteralExpression(props), record.file + ' icon props must be inspectable');
  calls.push({ ...record, node, props });
});
function applyMatrix(matrix, input) {
  return [0, 1, 2, 3].map(row => matrix[row * 5] * input[0] + matrix[row * 5 + 1] * input[1] +
    matrix[row * 5 + 2] * input[2] + matrix[row * 5 + 3] * input[3] + matrix[row * 5 + 4]);
}

// Exact line/cubic/axis-aligned elliptical-arc extrema for the commands used by
// all packaged icons. Unsupported syntax fails rather than silently shrinking bounds.
function pathBounds(commands) {
  const tokens = commands.match(/[MLCAZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g) || [];
  assert.equal(tokens.join(''), commands.replace(/\s+/g, ''), 'unsupported SVG path token');
  const points = [];
  let index = 0, current = [0, 0], start = [0, 0];
  const point = (x, y) => { assert.ok(Number.isFinite(x) && Number.isFinite(y)); points.push([x, y]); };
  const number = () => { const value = Number(tokens[index++]); assert.ok(Number.isFinite(value)); return value; };
  const cubic = (a, b, c, d, t) => (1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t*t*c + t**3*d;
  const roots = (a, b, c, d) => {
    const A = -a + 3*b - 3*c + d, B = 2*(a - 2*b + c), C = b-a;
    if (Math.abs(A) < 1e-12) return Math.abs(B) < 1e-12 ? [] : [-C/B];
    const disc = B*B - 4*A*C;
    return disc < 0 ? [] : [(-B+Math.sqrt(disc))/(2*A), (-B-Math.sqrt(disc))/(2*A)];
  };
  const tau = 2*Math.PI, wrap = angle => ((angle % tau) + tau) % tau;
  while (index < tokens.length) {
    const command = tokens[index++];
    if (command === 'M' || command === 'L') {
      current = [number(), number()]; point(...current);
      if (command === 'M') start = [...current];
    } else if (command === 'Z') {
      current = [...start]; point(...current);
    } else if (command === 'C') {
      const first = [number(), number()], second = [number(), number()], end = [number(), number()];
      const candidates = [0, 1, ...roots(current[0], first[0], second[0], end[0]),
        ...roots(current[1], first[1], second[1], end[1])];
      for (const t of candidates.filter(t => t >= 0 && t <= 1)) point(
        cubic(current[0], first[0], second[0], end[0], t), cubic(current[1], first[1], second[1], end[1], t));
      current = end;
    } else if (command === 'A') {
      let rx = Math.abs(number()), ry = Math.abs(number());
      const rotation = number(), large = number(), sweep = number(), end = [number(), number()];
      assert.equal(rotation, 0); assert.ok([0, 1].includes(large) && [0, 1].includes(sweep));
      assert.ok(rx > 0 && ry > 0);
      const dx = (current[0]-end[0])/2, dy = (current[1]-end[1])/2;
      const scale = dx*dx/(rx*rx) + dy*dy/(ry*ry);
      if (scale > 1) { rx *= Math.sqrt(scale); ry *= Math.sqrt(scale); }
      const denominator = rx*rx*dy*dy + ry*ry*dx*dx;
      assert.ok(denominator > 0);
      const factor = (large === sweep ? -1 : 1) * Math.sqrt(Math.max(0,
        (rx*rx*ry*ry - rx*rx*dy*dy - ry*ry*dx*dx) / denominator));
      const cx = factor*rx*dy/ry + (current[0]+end[0])/2;
      const cy = -factor*ry*dx/rx + (current[1]+end[1])/2;
      const startAngle = Math.atan2((current[1]-cy)/ry, (current[0]-cx)/rx);
      const endAngle = Math.atan2((end[1]-cy)/ry, (end[0]-cx)/rx);
      let delta = endAngle-startAngle;
      if (sweep && delta < 0) delta += tau;
      if (!sweep && delta > 0) delta -= tau;
      point(...current); point(...end);
      for (const angle of [0, Math.PI/2, Math.PI, 3*Math.PI/2]) {
        const distance = sweep ? wrap(angle-startAngle) : wrap(startAngle-angle);
        if (distance <= Math.abs(delta) + 1e-10) point(cx+rx*Math.cos(angle), cy+ry*Math.sin(angle));
      }
      current = end;
    } else assert.fail('unsupported command ' + command);
  }
  assert.ok(points.length > 1);
  return { left: Math.min(...points.map(p => p[0])), right: Math.max(...points.map(p => p[0])),
    top: Math.min(...points.map(p => p[1])), bottom: Math.max(...points.map(p => p[1])) };
}

test('actual SDK ArkUI parser accepts UiKit and pure metric helper', () => {
  for (const [file, text] of [[kitFile, kit], [metricsFile, metrics]]) {
    const errors = tree(file, text).parseDiagnostics || [];
    assert.equal(errors.length, 0, errors.map(d => ts.flattenDiagnosticMessageText(d.messageText, ' ')).join('; '));
  }
});
test('pure size helper defaults invalid values and clamps positive sizes to 16..72vp', () => {
  for (const value of [NaN, Infinity, -Infinity, -1, -100, -0, 0, undefined, null, '24'])
    assert.equal(uiIconSize(value), 24, String(value));
  for (const value of [Number.MIN_VALUE, 1, 15.99]) assert.equal(uiIconSize(value), 16);
  for (const value of [72.01, 100, Number.MAX_VALUE]) assert.equal(uiIconSize(value), 72);
  assert.equal(uiIconSize(21.5), 21.5);
});
test('all existing glyph sizes including empty-state 68 remain unchanged without font/density factors', () => {
  for (const value of [16, 17, 19, 21, 22, 23, 24, 30, 68, 72]) assert.equal(uiIconSize(value), value);
  assert.doesNotMatch(metrics, /(?:fontScale|fontSize|density|px2vp|vp2px|fp2px|display|window)\s*[.(]/);
  assert.doesNotMatch(metrics, /^import\s/m);
});
test('tint matrices are finite 20-number row-first filters with exact white-to-blue/gray/white RGB', () => {
  for (const color of ['#087FF5', '#8B919D', '#FFFFFF', '#171A21', '#000000', '#05aa7b', '#A6ACB6']) {
    const matrix = Array.from(uiIconTintMatrix(color));
    assert.equal(matrix.length, 20); assert.ok(matrix.every(Number.isFinite));
    const channels = [1, 3, 5].map(offset => parseInt(color.slice(offset, offset+2), 16));
    for (const alpha of [0, 0.125, 0.5, 1, 127, 255]) {
      const output = applyMatrix(matrix, [255, 255, 255, alpha]);
      channels.forEach((channel, i) => close(output[i], channel)); close(output[3], alpha);
    }
    assert.deepEqual(matrix.slice(15), [0, 0, 0, 1, 0]);
    for (const offset of [4, 9, 14, 19]) assert.equal(matrix[offset], 0);
  }
});
test('invalid tint values deterministically fall back without NaN or alpha changes', () => {
  const fallback = Array.from(uiIconTintMatrix('#171A21'));
  for (const invalid of ['', '#FFF', '#GG0000', 'red', '#00112233', undefined, null, ' #087FF5'])
    assert.deepEqual(Array.from(uiIconTintMatrix(invalid)), fallback);
});
test('installed SDK explicitly supports ColorFilter(number[]) and Image.colorFilter(ColorFilter)', () => {
  const image = fs.readFileSync(path.join(sdk, 'component/image.d.ts'), 'utf8');
  const units = fs.readFileSync(path.join(sdk, 'component/units.d.ts'), 'utf8');
  assert.match(image, /colorFilter\(value: ColorFilter \| DrawingColorFilter\): ImageAttribute;/);
  assert.match(units, /declare class ColorFilter[\s\S]*?constructor\(value: number\[\]\);/);
  assert.match(units, /4\*5 color matrix values[\s\S]*?matrix is row-first/);
});
test('all 24 named resources resolve statically to existing SVGs with unknown-name grid fallback', () => {
  assert.equal(names.length, 24); assert.equal(new Set(names).size, 24);
  assert.deepEqual([...names].sort(), [...legacyNames, 'grid'].sort());
  assert.deepEqual([...assets.keys()].sort(), [...names].sort());
  for (const name of names) assert.equal(uiIconResource(name), 'app.media.ui_icon_' + name);
  for (const unknown of ['', 'not-an-icon', '../book', 'BOOK', undefined])
    assert.equal(uiIconResource(unknown), 'app.media.ui_icon_grid');
  assert.doesNotMatch(declaration('uiIconResource'), /\$rawfile|https?:|data:|\$r\([^']|\+|`/);
});
test('every available icon asset has XML 24x24 intrinsics/viewBox and white fill-none rounded strokes', () => {
  for (const [name, { xml, svg }] of assets) {
    assert.ok(svg, name); assert.equal(svg.xmlns, 'http://www.w3.org/2000/svg');
    assert.equal(svg.width, '24'); assert.equal(svg.height, '24'); assert.equal(svg.viewBox, '0 0 24 24');
    assert.ok(!Array.isArray(svg.path), name); const vector = svg.path;
    assert.equal(vector.fill, 'none'); assert.equal(vector.stroke, '#FFFFFF');
    assert.equal(vector['stroke-width'], '1.8'); assert.equal(vector['stroke-linecap'], 'round');
    assert.equal(vector['stroke-linejoin'], 'round');
    // The legacy cloud stroke extended 0.025 units left of its viewport.
    // Only its new packaged curve is inset; the compatibility helper is unchanged.
    const expected = name === 'cloud' ? uiIconPath(name).replace('C-1 11 0 18 7 18', 'C0 11 1 18 7 18') : uiIconPath(name);
    assert.equal(vector.d, expected);
    assert.doesNotMatch(xml, /<(?:script|image|text|foreignObject|use|style)\b|\b(?:transform|href|font-size)=|<!DOCTYPE/);
    assert.deepEqual(Object.keys(svg).sort(), ['height', 'path', 'viewBox', 'width', 'xmlns'].sort());
  }
});
test('exact SVG stroke bounds remain within 24 coordinates at caller sizes including 68vp', () => {
  for (const [name, { svg }] of assets) {
    const bounds = pathBounds(svg.path.d), halfStroke = Number(svg.path['stroke-width'])/2;
    assert.ok(bounds.left-halfStroke >= -1e-9 && bounds.top-halfStroke >= -1e-9 &&
      bounds.right+halfStroke <= 24+1e-9 && bounds.bottom+halfStroke <= 24+1e-9,
      name + ' stroke escapes 24x24: ' + JSON.stringify(bounds));
    for (const requested of [16, 17, 19, 21, 23, 24, 68, 999]) {
      const size = uiIconSize(requested), scale = size/24;
      assert.ok((bounds.right-bounds.left+2*halfStroke)*scale <= size+1e-9, name);
      assert.ok((bounds.bottom-bounds.top+2*halfStroke)*scale <= size+1e-9, name);
    }
  }
});
test('actual UiIcon build uses native Image/Contain/matrix and no runtime Shape/Path/font renderer', () => {
  assert.match(icon, /Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.match(icon, /Image\(uiIconResource\(this\.name\)\)/);
  assert.match(icon, /\.objectFit\(ImageFit\.Contain\)/);
  assert.match(icon, /\.colorFilter\(new ColorFilter\(uiIconTintMatrix\(this\.color\)\)\)/);
  assert.doesNotMatch(icon, /\b(?:Shape|Path|Text|SymbolGlyph)\s*\(|viewPort|fillColor|data:|uiIconPath|fontScale|fontSize/);
  assert.doesNotMatch(icon, /\.layoutWeight\(|%|vp2px|px2vp|fp2px/);
});
test('inner Image and outer Stack share tight clamped square dimensions with flex expansion disabled', () => {
  assert.equal((icon.match(/\.width\(uiIconSize\(this\.iconSize\)\)/g) || []).length, 2);
  assert.equal((icon.match(/\.height\(uiIconSize\(this\.iconSize\)\)/g) || []).length, 2);
  assert.equal((icon.match(/\.constraintSize\(/g) || []).length, 2);
  for (const bound of ['minWidth', 'maxWidth', 'minHeight', 'maxHeight'])
    assert.equal((icon.match(new RegExp(bound + ': uiIconSize\\(this\\.iconSize\\)', 'g')) || []).length, 2, bound);
  assert.match(icon, /\.flexGrow\(0\)\.flexShrink\(0\)/);
  assert.match(icon, /\.hitTestBehavior\(HitTestMode\.None\)\.accessibilityLevel\('no'\)/);
});
test('UiIcon public name/color/iconSize contract and actual caller properties are unchanged', () => {
  assert.deepEqual([...icon.matchAll(/@Prop\s+([^;]+);/g)].map(match => match[1]),
    ["name: string = 'book'", "color: string = '#171A21'", 'iconSize: number = 24']);
  const rawCallCount = appTrees.reduce((total, record) => total + (record.text.match(/\bUiIcon\(/g) || []).length, 0);
  assert.equal(calls.length, rawCallCount, 'SDK AST must inspect every UiIcon call');
  assert.ok(calls.length >= 26, 'actual caller scan incomplete');
  const observedSizes = new Set();
  for (const call of calls) {
    for (const prop of call.props.properties) {
      assert.ok(ts.isPropertyAssignment(prop), call.file);
      const name = prop.name.getText(call.ast); assert.ok(['name', 'color', 'iconSize'].includes(name), call.file + ':' + name);
      if (name === 'name' && ts.isStringLiteral(prop.initializer)) assert.ok(names.includes(prop.initializer.text), call.file);
      if (name === 'iconSize' && ts.isNumericLiteral(prop.initializer)) {
        const size = Number(prop.initializer.text); observedSizes.add(size); assert.equal(uiIconSize(size), size, call.file);
      }
    }
  }
  for (const size of [16, 17, 19, 21, 22, 23, 24, 30, 68]) assert.ok(observedSizes.has(size), String(size));
});
test('constant icon names in UiIcon/settings rows/navigation wrappers are all packaged', () => {
  const constantNames = new Set();
  for (const record of appTrees) {
    for (const match of record.text.matchAll(/UiIcon\(\{\s*name:\s*'([^']+)'/g)) constantNames.add(match[1]);
    for (const match of record.text.matchAll(/\bicon:\s*'([^']+)'/g)) constantNames.add(match[1]);
    for (const match of record.text.matchAll(/this\.navigationItem\('[^']*',\s*'([^']+)'/g)) constantNames.add(match[1]);
  }
  assert.ok(constantNames.size >= 18, 'wrapper audit incomplete');
  for (const name of constantNames) assert.ok(names.includes(name), 'unpackaged caller constant: ' + name);
});
test('44/46vp targets remain outside UiIcon and empty-state glyph remains explicitly 68vp', () => {
  assert.doesNotMatch(icon, /\.(?:width|height)\((?:44|46)\)/);
  assert.match(kit, /UiIcon\(\{ name: 'back', iconSize: 21 \}\)[\s\S]*?\.width\(44\)\.height\(44\)/);
  assert.match(kit, /Stack\(\) \{ UiIcon\(\{ name: this\.icon, color: this\.tint, iconSize: 23 \}\) \}[\s\S]*?\.width\(46\)\.height\(46\)/);
  assert.match(read('entry/src/main/ets/components/ComicWidgets.ets'), /UiIcon\(\{ name: 'folder', color: '#70AFE9', iconSize: 68 \}\)/);
});
test('compatibility path helper, theme and non-icon UiKit components remain byte-identical', () => {
  assert.equal(hash(declaration('uiIconPath')), 'e8a250b686467c2b0fc55ed617b320b5bf5dd2b8def6b02f6c669806971e74bd');
  assert.equal(hash(declaration('UiTheme')), 'f3710babc182f9f19137ce7d7eff107286d6dc64ae5cf801b0ba3d665b977300');
  const suffix = kit.slice(kit.indexOf('@Component\nexport struct UiPageHeader'));
  assert.equal(hash(suffix), 'd2eebf8a9c2e47c21082df8503bcfd4acb7188c50f4e00ac06c1b9bee228faa0');
});
test('negative controls reject legacy viewport renderer, malformed assets and alpha-destroying tint', () => {
  assert.throws(() => assert.doesNotMatch('Shape() { Path() }.viewPort({ width: 24 })', /Shape\s*\(|Path\s*\(|viewPort/));
  assert.notEqual(XMLValidator.validate('<svg><path></svg>'), true);
  const badAlpha = Array.from(uiIconTintMatrix('#087FF5')); badAlpha[18] = 0;
  assert.throws(() => close(applyMatrix(badAlpha, [255, 255, 255, 0.5])[3], 0.5));
  assert.throws(() => {
    const bounds = pathBounds('M0 0 L48 48'); assert.ok(bounds.right <= 24 && bounds.bottom <= 24);
  });
});
assert.equal(passed, 16);
console.log(`PASS ${passed} UI icon size/tint/asset/renderer contracts; ${assets.size} packaged SVGs; ${calls.length} actual UiIcon callers; no device/install/HDC; synchronous cases (no async watchdog needed)`);
