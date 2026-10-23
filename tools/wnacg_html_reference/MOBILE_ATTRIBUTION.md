# Exact installed-source attribution: offline phone-response replay

## Scope and reproducibility

New evidence is limited to offline parsing/contracts, not device/UI/build/network acceptance. No new network calls, account data, private headers, installed-source modifications or production adapter changes were performed. The new helper is **a reviewed-site-script proposal only**, never auto-loaded by the app.

- [mobile_oracle.py](<mobile_oracle.py>) generates [mobile-oracle.json](<mobile-oracle.json>) using bundled Python/lxml 6.1.3, libxml2 2.11.9. It reads each exact exported phone response as bytes, hashes it, strictly decodes UTF-8, then uses independent XPath equivalents for **every one of the 30 unique literal installed WNACG selectors**, plus 16 actual mobile selectors. It independently parses every mobile card.
- [mobile_replay.js](<mobile_replay.js>) generates [mobile-replay.json](<mobile-replay.json>) and [mobile-replay.log](<mobile-replay.log>). It evaluates the full, unchanged four installed scripts, production init.js/html_engine.js, and in its second runtime the existing **actual Node NAPI/QuickJS addon**. Only Network and source state are fixture-stubbed; no source functions are copied/reimplemented for installed-rule replay. File hashes for captures, exact installed scripts, production engine/init/shim and addon are recorded.
- Reproduce from repository root with bundled executables returned by `load_workspace_dependencies`: `python tools/wnacg_html_reference/mobile_oracle.py`, then `node tools/wnacg_html_reference/mobile_replay.js`. Last run: **exit 0**, no background work.

## WNACG: what is proved

| Exported phone response | Independent mobile model | Full unchanged source / actual NAPI result | All-selector divergence |
|---|---|---|---|
| [phone-0.html](<phone/phone-0.html>) | 5 imgBox sections, 6 cards each, 30 cards total | `explore[0].load(null)` returns `[]` | 0 / 46 |
| [phone-1.html](<phone/phone-1.html>) | search ASCII: 24 cards | `search.load("a",[],1)` throws `TypeError: cannot read property 'text' of undefined` | 0 / 46 |
| [phone-2.html](<phone/phone-2.html>) | search CJK: 24 cards | `search.load("魔法",[],1)` same error | 0 / 46 |

Node VM and actual NAPI match lxml on all 138 selector/file pairs each; this is stronger than inferring a source defect from one zero selector or a host-side 403.

The observed mobile markup is substantive server-rendered comic data, not an empty challenge: `/themes/mo/` assets; home `div.imgBox > div.Sub_H2` / `span.Title`, `ul.col_3_2 > li` / `a.ImgA` / `a.txtA` / `span.info`; search `ul#classify_container > li`, `a.ImgA > span` title overlays. Search has a real `div.f_left.paginator > a` (9 links), but no `p.result > b` total.

The installed [wnacg.js](<../../logs/user8-installed-scripts/wnacg.js#L167-L182>) instead requires desktop `div.pic_box`, `div.info`, `div.title_sort`, `div.bodywrap`, `div.grid div.gallary_wrap > ul.cc > li`. Those nodes really are absent in these captures in BOTH independent and production parsers; the parser is not swallowing their class names.

First failure/empty stage:

1. Home [lines 208–231](<../../logs/user8-installed-scripts/wnacg.js#L208-L231>): `titleBlocks.length === comicBlocks.length === 0`, so the mismatch guard passes and returns empty output. Not a parse exception, and not evidence that the website has no content.
2. Search [lines 485–493](<../../logs/user8-installed-scripts/wnacg.js#L485-L493>): desktop card selector is empty, then `[0].text` on nonexistent `p.result > b` throws. This exactly reproduces the phone baseline error. A fix only to `p.result` would still leave zero comics: card/title/image/section selection must support the delivered model too.
3. Detail/reader/account selectors also counted as part of all-selector inspection, but their absence on a home/search document is **not** a finding that the real detail/reader pages are broken. No detail/reader captures are supplied here; those stages remain unverified.

### Attribution limit: mobile delivery versus site redesign

The mismatch is proven **for these delivered mobile response texts**, not a general “entire source is stale” conclusion. Current [HttpClient.ets:98–99,165–166](<../../entry/src/main/ets/network/HttpClient.ets#L98-L99>) supplies a Phone/OpenHarmony UA when the caller provides none; exact installed WNACG calls provide `{}`. This makes UA/template selection a plausible app-side compatibility factor. Static captures do not prove the site chooses mobile solely because of UA, nor prove the upstream Android/Dart default gets desktop HTML. No controlled same-URL UA A/B was performed. Preserve this uncertainty; do not blame a global redesign or user/network choice as established fact.

### Charset, images, URL prefixes, script robustness

- All 3 exported files strictly decode as UTF-8, have zero U+FFFD replacements, declare `text/html; charset=utf-8` in meta, and their UTF-16 lengths exactly match the character counts in [phone-0.proof.json](<phone/phone-0.proof.json>), [phone-1.proof.json](<phone/phone-1.proof.json>), [phone-2.proof.json](<phone/phone-2.proof.json>). Public status200 and no cookie read/write are recorded there.
- Proof files do **not** contain HTTP Content-Type charset or original response entity bytes. These are hashed UTF-8 exports of decoded response text, not an audit of pre-decoding wire bytes. Therefore a prior HTTP charset error is not conclusively excluded. However charset is not an explanation for the absent ASCII desktop structural class names when real mobile cards decode/parse correctly.
- Captured comic cover URLs are all protocol-relative `//t4.qy0.ru/...`; source-style `https:` prefix works for these. Advertisements/logo/analytics images include other prefixes; never treat all `img` as comic covers. Full-page image stats are in oracle JSON (39 home images: 32 protocol-relative,6 root-relative,1 absolute; each search:27 total,24 protocol-relative,2 root-relative,1 absolute).
- A jquery.lazyload script is present, but the supplied cards already contain real `src`; **zero** images have `data-original` or `data-src`. Do not invent a lazyload-caused capture failure. Proposal additionally supports those attributes for future templates and verifies that with a synthetic card.
- Production/lxml counts also agree on script/style nodes; full actual captures are parsed including inline JavaScript containing `<`, `>`, HTML string fragments, comments and CSS. Added synthetic regression verifies HTML-looking text inside script/style creates no fake desktop nodes, scripts are not executed, and actual following card still parses.

## Curated WNACG compatibility route (not “wait upstream”)

[mobile_compat_proposal.js](<mobile_compat_proposal.js>) is a new, non-autoloaded **source-side** helper. It parses supplied mobile home/search layouts. In both runtimes every card's id/title/cover/description matches independent lxml: home 5×6, both searches24; all covers are normalized valid HTTPS URLs. It rejects unsupported templates with the explicit error `WNACG unsupported HTML template (stage). HTTP success is not a parsed comic page; check domain/template or use a reviewed source update.`

Recommended bounded integration into a reviewed site-script revision (NOT mutation of installed scripts or generic JsComicSource):

1. Keep existing desktop parse branch when positively recognized; original desktop synthetic fixture still returns1 section/1 comic in replay. For mobile home positively recognize imgBox/Sub_H2/col_3_2; parse sections/headings/more links with helper. Unrecognized nonempty HTTP200 pages throw the explicit template error instead of returning blank success.
2. Add mobile search card branch using classify_container/ImgA/span; desktop branch remains separate. Use **cursor/loadNext** pagination or an equivalent source-local page-to-next cache. Preserve exact server next href including `c=...` cursor. Supplied search pager shows pages2–10 only, **not a maximum page count**; do not invent maxPage10 or silently cap real results. There is no p.result total to derive a maximum from.
3. Normalize protocol-relative/absolute/root-relative covers without blindly prepending `https:`; prefer data-original/data-src only when present; same-origin-only section/pagination navigation; reject unsupported URL schemes/cross-origin navigational links. Never execute website scripts.
4. Before an actual “WNACG usable” claim, obtain public no-account category/detail/series/gallery captures and test the exact detail/reader script. Existing loadEp uses a very broad raw URL regex and cannot be certified from home/search fixtures. No reader/image fetch/decode was performed here. Review empty-result sentinel semantics on a real no-results page and a later cursor page too.
5. Publish this as an explicit curated update with original source hash/version provenance and user-visible update choice; do not silently rewrite installed content. An app-UA adjustment is an alternative only after controlled public-UA evidence proves it works and it does not invalidate webview/session consistency.

This delivers a tested concrete repair path and useful unsupported-page diagnostics, while correctly stopping short of claiming full live source restoration.

## Komiic: finite one-shot search, not an app pagination failure

Exact [Komiic.js:252–299](<../../logs/user8-installed-scripts/Komiic.js#L252-L299>) accepts `page` but never uses it. GraphQL `searchComicAndAuthorQuery` declares only `$keyword` and passes only keyword. It returns `maxPage:1`. In contrast explore/category/ranking explicitly calculate offsets from page.

Full-source fixture replay in both runtimes invokes pages1 and2, confirms byte-equivalent serialized request objects, same IDs and maxPages `[1,1]`. Therefore the baseline [matrix:22–24](<../../logs/user8-baseline-full-matrix-20261014.jsonl#L22-L24>) `魔法:p1=100 p2=100 different=false` is consistent with deliberate single-response search, not proof of app false pagination. ASCII `p1=0` is a sampled query result, not by itself a broken API. Correct test behavior: respect finite maximum and do not require page2 to differ. This does not prove the upstream API returns unlimited/complete search results; script exposes only its one response. Newer transport `code2300999` is separate temporal evidence and not erased by correcting the old classification.

## ehentai: cursor and option caller contracts

Exact [ehentai.js:390–434](<../../logs/user8-installed-scripts/ehentai.js#L390-L434>) exposes explore `loadNext`, not `load`; [487–508](<../../logs/user8-installed-scripts/ehentai.js#L487-L508>) search begins `JSON.parse(options[0])` and also uses loadNext. Passing `[]` means `JSON.parse(undefined)` fails before network. Both full-source runtimes reproduce baseline `unexpected token: 'undefined'`; a properly JSON-string-encoded multi-select list reaches fixture Network.get. This is **caller/test-contract attribution**, not proof login/network/gallery parsing works live. Search option defaults and cursor adapter support must be respected; no automatic source edit is warranted merely for the baseline errors.

## shonen_jump_plus: preserve exact and time-scoped evidence

Baseline [matrix:119–123](<../../logs/user8-baseline-full-matrix-20261014.jsonl#L119-L123>) records `SyntaxError: unexpected token: '<'` for home and both searches; by itself it does NOT prove HTTP403, a CDN/WAF identity, or phone root cause. Host403 on a different network cannot establish these.

Stronger **separate/newer phone log** [startup:1057–1066](<../../logs/user8-newbuild-startup-20261014.log#L1057-L1066>) ties the same TraceID to POST HTTP403, textlen146, then source home SyntaxError `<`; [1087–1106](<../../logs/user8-newbuild-startup-20261014.log#L1087-L1106>) similarly ties both searches. Body is not saved. This is evidence of actual phone HTTP403 in THAT run; still not proof which upstream/security/network factor caused it, or that baseline necessarily had403.

Exact [script:281–293](<../../logs/user8-installed-scripts/shonen_jump_plus.js#L281-L293>) blindly JSON-parses token response without status/body validation; full-source synthetic403-HTML replay produces exactly NAPI `unexpected token: '<'`, with first request `/api/v1/user_account/access_token`. This proves the error-masking mechanism is possible for supplied source, not the original response body or baseline HTTP status. Recommended reviewed source update: validate status then JSON shape, report `Shonen Jump+ token request failed (HTTP403/non-JSON)` without response body/token/header disclosure. No automatic source edit here. Earlier [appdev log:4676–4683](<../../logs/user8-newbuild-appdev-20261014.log#L4676-L4683>) contains SDK `code401: Parameter error`, which is **not HTTP401** and must not be conflated with later403.

## Remaining limits

No conclusion here establishes all-source compatibility or all WNACG reading. The tests isolate source/template mismatch, finite search and caller-contract mistakes. Public detail/reader/category/later-cursor acceptance, actual image bytes, original wire charset and a controlled-UA comparison remain outstanding. Parent-owned report/matrix adapter changes are outside this delegation.
