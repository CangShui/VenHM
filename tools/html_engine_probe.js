/*
 * Local harness for entry/src/main/resources/rawfile/html_engine.js.
 *
 * The engine answers `sendMessage({method:'html', ...})` inside QuickJS. This
 * script reproduces that contract in Node so the hand-written parser/selector
 * can be tested against real pages without a device round-trip.
 *
 *   node tools/html_engine_probe.js <file.html> [selector ...]
 */
const fs = require('fs');
const path = require('path');

const enginePath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources',
  'rawfile', 'html_engine.js');

let captured = null;
globalThis.sendMessage = function (message) {
  captured = message;
  return null;
};

// eslint-disable-next-line no-eval
eval(fs.readFileSync(enginePath, 'utf8'));

const send = globalThis.sendMessage;
if (send === undefined || globalThis.__veneraHtmlEngineLoaded !== true) {
  console.error('engine did not load');
  process.exit(2);
}

const file = process.argv[2];
const selectors = process.argv.slice(3);
if (!file) {
  console.error('usage: node tools/html_engine_probe.js <file.html> [selector ...]');
  process.exit(2);
}
const html = fs.readFileSync(file, 'utf8');

function call(message) {
  return send(message);
}

const docKey = call({ method: 'html', function: 'parse', key: 0, data: html });
console.log('parse ->', JSON.stringify(docKey));

function describe(key) {
  const text = call({ method: 'html', function: 'getText', key, doc: docKey });
  const attrs = call({ method: 'html', function: 'getAttributes', key, doc: docKey });
  return `key=${key} text=${JSON.stringify(String(text).slice(0, 60))} attrs=${JSON.stringify(attrs)}`;
}

for (const selector of selectors) {
  console.log(`\n=== ${selector} ===`);
  let all;
  try {
    all = call({ method: 'html', function: 'querySelectorAll', key: docKey, query: selector });
  } catch (error) {
    console.log('  THREW', error && error.message ? error.message : String(error));
    continue;
  }
  console.log('  count:', Array.isArray(all) ? all.length : JSON.stringify(all));
  if (Array.isArray(all)) {
    for (const key of all.slice(0, 12)) {
      console.log('   ', describe(key));
    }
  }
}

// Diagnostics for the manhuagui chapter list specifically.
console.log('\n=== diagnostics ===');
for (const probe of ['.chapter', '.chapter-list', '.chapter h4', '.chapter h4 span', 'li', 'li a']) {
  const keys = call({ method: 'html', function: 'querySelectorAll', key: docKey, query: probe });
  console.log(`  ${probe}: ${Array.isArray(keys) ? keys.length : JSON.stringify(keys)}`);
}
