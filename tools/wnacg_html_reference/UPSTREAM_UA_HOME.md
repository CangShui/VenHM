# Original-UA HOME: exact first failure, bounded offline proof

## Finding and repair decision

**HOME was not absent and did not need an alternate path. The first demonstrated failure is duplicate-attribute tokenization.** The exported original-UA HOME contains `<div class="title_sort" class="cc">` and `<div class="bodywrap" class="cc">` (12 duplicate-class wrappers). The old production tokenizer retained the **last** attribute; lxml and Chromium's inert DOMParser retain the **first**, including empty values and ASCII-case-insensitive duplicate names. The original installed rule queries `div.title_sort` and `div.bodywrap`; losing both classes gives 0/0. Its equality check accepts 0/0, its loop is skipped, and it returns `[]`.

- First failing observation: [unchanged source:209–213](<../../logs/user8-installed-scripts/wnacg.js#L209-L213>), not HTTP status, card IDs, pagination, base-path selection, or page scripts.
- Exact malformed tags: [HOME:236](<phone-upstream-ua/phone-0.html#L236>) and [HOME:250](<phone-upstream-ua/phone-0.html#L250>).
- Correct minimal repair is generic parser first-attribute-wins, **not source-specific normalization**. Parent applied it separately to [production tokenizer:60–75](<../../entry/src/main/resources/rawfile/html_engine.js#L60-L75>), including null-prototype attribute maps and own-key guarding. Parent also made returned attribute maps preserve `__proto__`/`constructor` as ordinary attributes.
- This subtask changed no installed script, production JS, JsComicSource, native implementation, UI, or main docs. It ran no network/device/build actions. Parent explicitly chose generic parser repair over a new compatibility source helper after the first-failure evidence. No new source helper was installed or needed to recover this HOME.

Minimal reviewed parser behavior, applied by parent (not this diagnostic):

```js
const attrs = Object.create(null);
// Attribute names have already been lowercased.
if (!Object.prototype.hasOwnProperty.call(attrs, name)) {
  attrs[name] = decodeEntities(value);
}
```

A source-only defensive improvement remains optional and is **not the repair**: after the original exploration loop, reject an empty result or a section with zero comics with an explicit unsupported-HOME/template error rather than returning success `[]`. Do not strip/merge duplicate attributes in WNACG alone. Do not make a generic port defect a source exemption.

## Exact fixture and URL limitations

[Original-UA capture proof](<phone-upstream-ua/phone-0.proof.json>) records requested `https://wnacg.com`, HTTP200, `VeneraNext/v1.17.0`, 57,881 UTF-16 units, UTF-8 content type, and no sent/updated cookie jar. [Exact exported HOME](<phone-upstream-ua/phone-0.html>) SHA256:

`df7fddaed8c6bd5a4dc9931e417708bc627b4e370cce8802eab15fa69697b5fd`

The proof does **not** record final URL, redirect chain, headers beyond the charset field, or original wire bytes. Thus a redirect chain is unknown, not proven correct or wrong. The captured body itself is a complete desktop HOME with HOME title, root navigation, headings and 66 card occurrences. There is no evidence requiring another HOME path. Its hidden `www.wnacg.com/cdn-cgi/content` anchor is not redirect proof.

[Later matrix:2](<../../logs/user8-device-matrix/deep-1792051137357.jsonl#L2>) records a separate HOME capture with 57,880 characters. Do not claim byte identity with the supplied 57,881-unit exported fixture or with the later source request. The replay proves this fixture's mechanism and the generic repair, not an unexported response's hash.

Public base/default-path tests prove:

1. Entire unchanged source reads settings `domainSelection=0`, `domain0=wnacg.com`, returns public base `https://wnacg.com`, and requests that exact string with `{}` headers. The HTTP URL's absent path means `/`; no helper appends `/home` or rewrites to another endpoint.
2. `HtmlDocument` returns relative `href="albums.html"` and scheme-relative `src="//img.example/a.webp"` unchanged. It is a parser, not a browser URL resolver. Neither tested VM nor actual QuickJS exposes a global `URL` constructor by default.
3. The original positive desktop branch preserves `viewMore="category:TITLE@/albums.html"`; it intentionally passes a root-relative category parameter, not an invented absolute/synthetic schema. Existing `parseComic` adds `https:` to protocol-relative covers.
4. HTML `<script>` and `<style>` raw text does not create fake HOME nodes, and inline scripts are not executed. A browser that lazy-loads images or runs jQuery is not a prerequisite for these captured static cards.

## Same bytes, full unchanged source: before/after

[Replay implementation](<home_replay.js>) evaluates the entire installed source byte-for-byte, using real production `init.js` and `html_engine.js` in **Node VM** and **actual prebuilt NAPI/QuickJS**. Only Network.get is fixture-stubbed. No copied WNACG parse algorithm acts as the implementation under test. Current production is the parent's generic repaired engine; `before` reconstructs only the previous last-wins tokenizer hunk in memory. The test never writes production.

[Replay results](<home_replay.json>) and [run log](<home_replay.log>):

| Exact fixture | Before, both runtimes | Current parent-repaired production, both runtimes |
|---|---|---|
| Original-UA HOME | heading0 / body0; unchanged exploration `[]` | heading6 / body6; six parts / 66 comics |
| Old PhoneUA HOME | unchanged exploration `[]` | still `[]`; no pretend mobile-support claim |
| Original-UA search `a` | 24 comics | 24 comics, all card fields and maxPage equal independent lxml |
| Original-UA search `魔法` | 24 comics | 24 comics, all card fields and maxPage equal independent lxml |
| Valid synthetic desktop HOME without duplicate attrs | one section / one comic | same positive original branch and category schema |

Every recovered HOME section name, card order, ID, normalized title, cover URL, normalized description and viewMore equals independent lxml-owned records. Comparison only normalizes whitespace; source description's documented newline/tab deletion is honored. Production source hash is recorded in the replay; installed source hash remains `545a6d818d012c1e5799d6aaf7ecd09798969acb840166ee7c56de6d02201df0`.

Prototype-name edge is tested **inside each runtime**, not with a JavaScript object literal whose `__proto__` initializer silently disappears from `Object.keys`. Both VM and actual QuickJS expose an own `__proto__="safe"` attribute and stringify it correctly. The prebuilt NAPI `callJson` host-object export drops this key when returning a raw object to Node; string-based internal checks isolate that harness export boundary. This does not affect HOME, and no native change was attempted.

### Expected complete HOME output

| Section | Count | Ordered card IDs |
|---|---:|---|
| 最新更新 | 6 | 395948, 395902, 395901, 395900, 395899, 395898 |
| 同人誌CG畫集 | 12 | 395948, 395902, 395900, 395897, 395896, 395895, 395894, 395893, 395892, 395891, 395890, 395889 |
| 單行漫畫 | 12 | 395880, 395878, 395859, 395682, 395616, 395614, 395464, 395406, 395387, 395379, 395374, 395325 |
| 雜誌短篇 | 12 | 395899, 395898, 395873, 395872, 395871, 395870, 395869, 395868, 395862, 395855, 395854, 395852 |
| 韓國漫畫 | 12 | 395674, 394624, 394610, 390073, 390064, 390063, 390056, 390053, 390042, 390041, 390038, 390033 |
| Cosplay寫真 | 12 | 395879, 395877, 395863, 395856, 395845, 395844, 395772, 395684, 395683, 395615, 395472, 395471 |

These are 66 occurrences, not a claim of 66 globally unique IDs (HOME sections intentionally repeat some cards).

## Independent oracle: important malformed-tree limit

[Independent Python lxml/XPath oracle](<home_oracle.py>) and [full oracle data](<home_oracle.json>) do not import or copy the JS parser/source implementation. lxml retains the first duplicate class and finds six headings/six wrapper classes. However, this HOME also omits closing `</div>` for card `div.info`. **libxml2 is not an HTML5 treebuilder.** It nests subsequent `li` and later HOME wrappers. Its literal selector equivalent `div.gallary_wrap > ul.cc > li` returns **6**, whereas production's end-tag stack recovery yields **66**. This is disclosed, not hidden as selector parity.

To independently extract the complete lxml content, select every card `li` and assign it to its **nearest ancestor gallery UL**. This avoids nested-section double counting and recovers counts 6/12/12/12/12/12 with all 66 records. Never use naive per-wrapper all-descendant records; that creates cross-section duplicates.

Chromium DOMParser **microcase** independently returned first class `first`, empty first `src`, first href `/safe`, scripts not executed. Full-fixture Chromium verification is **NOT claimed**: browser unsafe code lacks `require`/dynamic-import callback, and its filename loader explicitly denied this workspace file as outside browser allowed roots. No copy/retry/bypass of that denied access was attempted. [Browser test template](<home_browser_test.js>) and [embedded exact-fixture test](<home_browser_generated.js>) are provided for a correctly authorized runner; the latter was generated but **not executed** here.

## Prior PhoneUA HOME versus original-UA HOME

| Structural evidence | Prior PhoneUA capture | Original-UA capture |
|---|---|---|
| Document title | 紳士漫畫移動版-專注分享漢化本子 | 紳士漫畫-專註分享漢化本子\|邪惡漫畫 |
| Theme path | `/themes/mo/images/` | `/themes/weitu/images/` |
| Section wrappers | `div.imgBox` ×5 | `div.title_sort` / `div.bodywrap` ×6 each (first duplicate attrs) |
| Headings | `div.Sub_H2 > span.Title` | `div.title_h2` |
| Card lists | `ul.col_3_2 > li`, 30 cards | `div.gallary_wrap > ul.cc`, 66 card occurrences |
| Names/counts | 最新上架6; 同人志6; 單行本6; 雜誌·短篇6; 韓漫6 | table above |

Both are static, real HOME templates, not blank/error pages. The UA restoration selects the desktop-compatible source template; the remaining original-UA empty-HOME failure is an independently demonstrated port tokenizer bug. This does not justify blanket site blame or a source update to paper over it.

## Reproduction and ownership

```powershell
$env:PYTHONIOENCODING='utf-8'
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' tools/wnacg_html_reference/home_oracle.py
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe' tools/wnacg_html_reference/home_replay.js
```

No network required. The Python script also regenerates the embedded browser test; do not run a capture script. Parent reports common engine tests14, lifecycle11, source contracts11 passing after its fix; this subtask did not rerun lifecycle commands that would overwrite parent-owned logs outside the permitted directory. Phone validation, fresh exact-matrix capture/hash if needed, main docs/UI/code and deployment remain parent-owned.
