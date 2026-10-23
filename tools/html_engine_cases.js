/*
 * Micro-tests for entry/src/main/resources/rawfile/html_engine.js.
 *
 * Each case is HTML + assertions about what the engine returns. Run with
 * `node tools/html_engine_cases.js`.
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
let failures = 0;
let documentCounter = 0;

function query(html, selector, method) {
  const doc = send({ method: 'html', function: 'parse', key: documentCounter++, data: html });
  return send({ method: 'html', function: method ?? 'querySelectorAll', key: doc, query: selector });
}

function text(html, selector) {
  const doc = send({ method: 'html', function: 'parse', key: documentCounter++, data: html });
  const keys = send({ method: 'html', function: 'querySelectorAll', key: doc, query: selector });
  if (!Array.isArray(keys) || keys.length === 0) {
    return null;
  }
  return String(send({ method: 'html', function: 'getText', key: keys[0], doc }));
}

function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.log(`FAIL ${label}\n  expected ${JSON.stringify(expected)}\n  actual   ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok   ${label} -> ${JSON.stringify(actual)}`);
  }
}

// --- chapter group detection, mirroring the manhuagui selector chain --------
const chapterHtml = `<!DOCTYPE html><html><body>
<div class="book-cont cf">
  <div class="book-title"><h1>鬼灭之刃</h1><h2>subtitle</h2></div>
  <div class="chapter cf mt16">
    <div class="chapter-bar"><h3>章节全集</h3></div>
    <h4><span>单话</span></h4>
    <div class="chapter-list cf mt10" id="chapter-list-0">
      <ul style="display:block">
        <li><a href="/comic/19430/100.html" title="第1话"><span>第1话<i>32p</i><em class="new"></em></span></a></li>
        <li><a href="/comic/19430/101.html" title="第2话"><span>第2话<i>24p</i></span></a></li>
      </ul>
    </div>
    <h4><span>番外篇</span></h4>
    <div class="chapter-list cf mt10" id="chapter-list-1">
      <ul><li><a href="/comic/19430/200.html" title="画集"><span>画集<i>105p</i></span></a></li></ul>
    </div>
  </div>
</div>
</body></html>`;

check('.chapter h4 span count', (query(chapterHtml, '.chapter h4 span') || []).length, 2);
check('.chapter-list count', (query(chapterHtml, '.chapter-list') || []).length, 2);
check('.book-title h1 text', text(chapterHtml, '.book-title h1'), '鬼灭之刃');
check('first chapter li text', text(chapterHtml, '.chapter-list li'), '第1话32p');
check('nested querySelector a', (query(chapterHtml, '.chapter-list li a') || []).length, 3);

// --- attribute reading ------------------------------------------------------
const attrHtml = `<div class="chapter-list cf mt10" id="chapter-list-0"><ul><li>
<a href="/comic/1/2.html" title="t"><span>第1话</span></a></li></ul></div>`;
const docKey = send({ method: 'html', function: 'parse', key: documentCounter++, data: attrHtml });
const anchorKeys = send({ method: 'html', function: 'querySelectorAll', key: docKey, query: 'a' });
const anchorAttrs = send({ method: 'html', function: 'getAttributes', key: anchorKeys[0], doc: docKey });
check('anchor attributes', anchorAttrs, { href: '/comic/1/2.html', title: 't' });

// HTML duplicate attributes are ASCII-case-insensitive FIRST-wins, not
// Object truthiness or last-write-wins. Raw script text is not markup.
const duplicateHtml = `<div CLASS="title_sort" class="cc" id="first" ID="second"><a HREF="/safe" href="javascript:bad">x</a></div>
<div class="" class="hidden">empty</div><img src="//first/a&amp;b" SRC="//second/a"><input disabled disabled="false">
<section constructor="first" CONSTRUCTOR="second" __proto__="plain" toString="literal"></section>
<script>const x='<div class="title_sort" class="fake">not markup</div>'</script>`;
check('duplicate class keeps first case-insensitively', query(duplicateHtml, '.title_sort').length, 1);
check('discarded duplicate class cannot match', query(duplicateHtml, '.cc').length, 0);
check('duplicate id keeps first', query(duplicateHtml, '#first').length, 1);
check('empty first class is not overwritten', query(duplicateHtml, '.hidden').length, 0);
const duplicateDoc = send({method:'html', function:'parse', key:documentCounter++, data:duplicateHtml});
function attrs(selector) { const keys=send({method:'html',function:'querySelectorAll',key:duplicateDoc,query:selector});
  return send({method:'html',function:'getAttributes',key:keys[0],doc:duplicateDoc}); }
check('first href retained', attrs('a').href, '/safe');
check('first src decoded once', attrs('img').src, '//first/a&b');
check('first empty boolean attribute retained', attrs('input').disabled, '');
check('inherited-name attributes are ordinary own data', [attrs('section').constructor,attrs('section').__proto__,attrs('section').tostring], ['first','plain','literal']);

console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
