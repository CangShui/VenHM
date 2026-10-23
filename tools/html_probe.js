/*
 * Structural probe for a page fetched for one of the source scripts.
 *
 * The engine answers `sendMessage({method:'html', ...})`; this harness reproduces
 * that contract in Node so selectors used by a source can be checked against the
 * real markup without a device round-trip.
 *
 *   node tools/html_probe.js <file.html> [selector ...]
 */
const fs = require('fs');
const path = require('path');

const enginePath = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources',
  'rawfile', 'html_engine.js');

globalThis.sendMessage = function () {
  return null;
};

// eslint-disable-next-line no-eval
eval(fs.readFileSync(enginePath, 'utf8'));

const send = globalThis.sendMessage;
const file = process.argv[2];
const selectors = process.argv.slice(3);
const html = fs.readFileSync(file, 'utf8');
const doc = send({ method: 'html', function: 'parse', key: 0, data: html });
console.log('document key:', JSON.stringify(doc));

function textOf(key) {
  return String(send({ method: 'html', function: 'getText', key, doc }));
}

for (const selector of selectors) {
  const keys = send({ method: 'html', function: 'querySelectorAll', key: doc, query: selector });
  const list = Array.isArray(keys) ? keys : [];
  console.log(`\n${selector} -> ${list.length}`);
  for (const key of list.slice(0, 20)) {
    const attrs = send({ method: 'html', function: 'getAttributes', key, doc });
    console.log(`  key=${key} text=${JSON.stringify(textOf(key).slice(0, 50))} attrs=${JSON.stringify(attrs)}`);
  }
}
