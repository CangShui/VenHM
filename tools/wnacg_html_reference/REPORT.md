# WNACG public HTML / port-rule distinction — scoped findings

## Status and exact scope

**WNACG 1.0.6 phone search remains unresolved; no full-source PASS and no upstream-rule exemption.** Two concrete HTML-port defects were independently proved and fixed, but neither explains WNACG's phone empty results. Only [html_engine.js](<entry/src/main/resources/rawfile/html_engine.js>) was modified; new scripts/evidence are scoped to this directory. No JsComicSource, acceptance/UI/network/native-C++ changes, app/addon rebuilds, device actions, source_data, account data, or account cookies were performed.

Installed source identity: [wnacg.js](<logs/user8-installed-scripts/wnacg.js>), SHA256 `545a6d818d012c1e5799d6aaf7ecd09798969acb840166ee7c56de6d02201df0`. Actual installed version is 1.0.6.

## Exact baseline failure mechanism

[Installed search](<logs/user8-installed-scripts/wnacg.js#L476-L498>) first rejects non-200 status, queries `div.grid div.gallary_wrap > ul.cc > li`, and then **unconditionally accesses `document.querySelectorAll("p.result > b")[0].text` (491)**. When that selector has zero matches, index 0 is undefined and the recorded TypeError follows. This is independent of pagination numerical conversion or Comic attributes: execution has not reached `Math.ceil` yet, and no comic attribute accesses occur when the comic list is empty.

[Installed exploration](<logs/user8-installed-scripts/wnacg.js#L203-L232>) permits both `div.title_sort` and `div.bodywrap` to have zero matches: 0 equals 0, so it returns `[]` silently. This explains the empty-exploration symptom for a non-listing DOM without requiring a parser failure.

[Phone baseline](<logs/user8-baseline-matrix-app-log-20261014.log#L947-L979>) shows ASCII request no explicit headers, Cookie attachment false, HTTP200/text length42823, then both querySelectorAll calls return0. CJK request similarly [returns200/text length42769](<logs/user8-baseline-matrix-app-log-20261014.log#L980-L991>). Exact phone response bytes, selected public domain, and final URL were not captured in the baseline. Therefore the origin of the missing DOM remains **UNRESOLVED_PUBLIC_DOM_OR_PORT_OR_RESPONSE_ADAPTATION**, not definitively RULE_CHANGED.

The search exception skips source `document.dispose()` (494). A source-exception cleanup weakness exists, but activities367 is a shared count and cannot be attributed solely to WNACG. No eviction/cleanup workaround was introduced.

## Independent equivalent-parser evidence

The same public captured bytes are parsed independently with bundled Python **lxml.html/libxml2 XPath** and production **init.js + html_engine.js**, both in Node VM and **actual existing NAPI/QuickJS addon**. No addon rebuild was performed. Exact public hashes and counts: [lxml reference](<tools/wnacg_html_reference/lxml-reference.json>), [before A/B](<tools/wnacg_html_reference/comparison-before.json>), [after A/B](<tools/wnacg_html_reference/comparison-after.json>).

| Public fixture | SHA256 | Standard / production result |
|---|---|---|
| [Historical search](<logs/upstream/wnacg-search-page.html>) | `380f6bb9a4c57d4192cc17953140a2db366480222f1c2baab3879a4472827577` | `p.result > b`:2, text40,386 and337,577; comic list24; a[href]96. No count divergence before or after. Exact installed source returns24 valid comics/maxPage1683 in VM and actual QuickJS. Historical fixture HTTP200 is a replay assumption, not a newly recorded response status. |
| [Historical domain publication](<logs/upstream/wnacg-domain-page.html>) | `2a8f01376dd4f1043aa8788c0c3e63b49e278ced897e4408073b84c72659f0a5` | a[href]6; home blocks0, search totals0, comics0 in all parsers. Replaying this non-listing DOM with fixture status200 produces exploration[] and the same search TypeError in VM and QuickJS. This demonstrates a possible mechanism only; it does **not** prove the phone received this page. |
| [New public default captures](<tools/wnacg_html_reference/capture-proof.json>) | all `2938e9f1284180959e33ab1718d0793a72ff6e4cdb8108c34dcd14e69446de5c` | HTTP403/text/plain/17bytes; all requested listing selectors0 in standard and production. Installed source replay preserves actual403 and throws Invalid Status Code403, **not** baseline TypeError. |

### Current public HTTP proof / safety boundary

[Credential-free capture script](<tools/wnacg_html_reference/capture.py>) fetched **only URLs derived from installed rule public defaults/templates** at 2026-10-14 08:44:56–08:45:03 UTC:

- `https://wnacg.com` → `https://www.wnacg.com/`,403.
- Installed search template with ASCIIa/page1 → corresponding www.wnacg.com URL,403.
- Same template with encoded魔法/page1 → corresponding www.wnacg.com URL,403.
- Installed refresh URL `https://wn01.link/` → `https://wnacg01.link//`,403.

No credentials/private headers were supplied, no challenge-solving/auth retries/alternate-domain/root circumvention occurred. **Classification: HTTP_ACCESS_OR_FILTER_BLOCK, high confidence for this host fetch only; not SOURCE_BAD.** Whether generated by upstream, edge, or host filtering is not proven. These403 responses cannot be substituted for the phone200 DOM when assigning the phone failure taxonomy.

## Concrete port fixes and A/B regressions

1. **HTML_NODE_CONVERSION_CONTRACT_MISMATCH — high confidence, fixed.** [init.js HtmlNode.toElement](<entry/src/main/resources/rawfile/init.js#L979-L991>) sends `node_toElement`; engine previously handled only `node_to_element`. Production [engine now accepts both](<entry/src/main/resources/rawfile/html_engine.js#L747-L753>). Before: every element-node conversion returnsnull. After: text/comment→null, element→correct HtmlElement. WNACG installed source does not use nodes/toElement; this is not its search root cause.
2. **CSS_EXPLICIT_COMBINATOR_WHITESPACE_PORT_BUG — high confidence, fixed.** [tokenizer](<entry/src/main/resources/rawfile/html_engine.js#L278-L298>) previously reset `>`, `+`, `~` into descendant relation when whitespace followed the operator. `p.result > b` incorrectly included a nested `span > b`. Preserve operator when no preceding compound is flushed. Independent lxml XPath oracle and VM/native A/B show direct-child, adjacent-sibling, and general-sibling expectations fail before and pass after. This patch can remove false positives, not explain previously zero WNACG totals on the historical DOM.

[Scoped comparison cases](<tools/wnacg_html_reference/compare.js>) and [independent microcase oracle](<tools/wnacg_html_reference/oracle.py>) also prove bracket/dot attributes return the same href, `children` excludes text/comments, `nodes` preserves ordered text/comment/element children, and `nextElementSibling` skips non-elements. The installed WNACG rule uses **bracket** attributes, not dot attributes; it has no nextSibling/nodes/toElement access. `HtmlElement.nextElementSibling`, not generic nextSibling, is the upstream public API.

A/B `--before` reconstructs the two scoped prepatch behavioral hunks in memory only; it does not mutate production. JSON engine SHA256 for this mode identifies the reconstructed behavioral baseline, not an original binary/artifact. Both runtimes have zero public-selector count mismatches against lxml. Three microcases per runtime now pass. Existing [html_engine_cases](<tools/html_engine_cases.js>)6 assertions and [HTML lifecycle cases](<tools/html_lifecycle_cases.js>)11 cases passed after the production patch.

## E-Hentai handoff (parent-owned)

[Installed E-Hentai1.2.0](<logs/user8-installed-scripts/ehentai.js#L390-L434>) exposes exploration `loadNext` only; direct `load` calls yield not-a-function before HTTP. [search.loadNext](<logs/user8-installed-scripts/ehentai.js#L487-L489>) immediately JSON.parse(options[0]); missing default multi-select option from [optionList](<logs/user8-installed-scripts/ehentai.js#L512-L533>) yields JSONundefined before HTTP/HTML. Parent independently owns/fixes dispatcher and option metadata. No auth/403/upstream-bad conclusion applies to these baseline pre-network errors.

## Required next evidence for WNACG

Parent network owner should capture only the exact failing **public unauthenticated** phone200 body, response status/finalURL/contentType/hash, with Cookie=false independently enforced/proven. Run that byte-identical capture through this lxml/production/native comparison. If standard and production are both0 on the exact listing selectors, investigate public response landing-page/domain/rule layout and report upstream/response non-listing failure, not port-parser failure. If independent parser finds nodes but production misses them, the differential requires an additional scoped port fix and A/B before calling the rule bad. No current full-source PASS or exemption is justified.

## Reproduction (host-only, no builds)

```powershell
# Bundled executables; rerunning capture makes real public requests, so do not
# rerun it to bypass a previously observed403.
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' tools/wnacg_html_reference/oracle.py
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe' tools/wnacg_html_reference/compare.js --before --out=comparison-before.json
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe' tools/wnacg_html_reference/compare.js --assert --out=comparison-after.json
```
