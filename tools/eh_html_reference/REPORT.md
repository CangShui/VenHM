# EH v1.2.0: bounded offline diagnosis

## Result / scope

**The phone's zero-item cause remains undetermined.** The matrix records zero Explore/Search items, not actual response HTML or a parser exception. No account/auth/site-failure conclusion follows from zero. This work made **zero HTTP requests, zero device calls, and no application/native build**. Only this diagnostic directory was authored; no installed source, SourceAcceptance, JsComicSource, HTML engine or native implementation was edited by this task.

Exact installed [source](<../../logs/user8-installed-scripts/ehentai.js>) version 1.2.0 SHA256: `ef15f80d8090cb9ec1fcb18b502017a47694484e81d51c85e6b06ea162c58e4a`.

Discovery used glob `**/*.{html,htm}` over the workspace: only WNACG public fixture files were present; **no actual EH response fixture** was available. These results are synthetic contracts, not a site/device PASS. Unrelated concurrent agents may be modifying production files; this task did not.

## Reproducible offline evidence

[Runner](<contract_cases.js>) loads the existing real production host addon, production init/shim/HTML engine, and **the full installed source without rewriting any parser/function body**. Its host intercept returns synthetic HTML; request-builder mode rejects before HTTP. The source remains unchanged on disk. It does not substitute a VM-only HTML model for native evidence.

```powershell
node tools/eh_html_reference/contract_cases.js
& 'C:\Users\<user>\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' tools/eh_html_reference/lxml_oracle.py
```

Final output: `EH_OFFLINE_CONTRACT_PASS cases=19 guards=3 networkCalls=0`, then `LXML_OFFLINE_PASS fixtures=18`.

- 18 synthetic HTML cases ran the real native list parser; one additional source-loop case ran the full source synchronously inside bounded `vm.runInContext` (25 ms watchdog), deliberately **not** inside the main native runtime.
- Four valid modes produce one valid item each; combined page produces four. Compact leaderboard `t=1`, compact/minimal lazy `data-src`, comma tag selectors, explicit child combinators, text entities, and whitespace/comments pass.
- All **25 unique selectors** used by `getGalleries` are enumerated in [spec](<probe_spec.json>); runner asserts the extracted source selector list equals that spec.
- Independent [lxml oracle](<lxml_oracle.py>) compares 45 selector/landmark counts over 18 fixtures: **810/810 counts match**. Initial root-HTML mismatch was an oracle scope error (`.//html` excluded its own HTML root); corrected document-scope XPath passes. libxml2/lxml is **not an HTML5 tree builder**, so this agreement does not establish HTML5 compatibility.
- Native type probe confirms `children` are elements only despite text/comments, `nodes` distinguish text/comment/element, attributes are objects, text is string, arrays support `.find`, and QuickJS `Date.parse` accepts the controlled source date shape.
- Installed source does not use `NodeModel` or `.evaluate`; a positional/evaluate bridge defect is **not proven**. No unsupported CSS in these exact modern list selectors was demonstrated.
- Status 403, a body beginning with whitespace rather than `<`, and plain-text body trigger source exceptions (not normal empty-list returns). These are controlled guards, not assertions about the phone response.

Structural-only [native results](<results.json>) and [lxml results](<lxml_results.json>) contain counts, shape/types and synthetic case labels, not actual credentials, real gallery IDs, gallery tokens, next URLs or captured page text. [Oracle inputs](<oracle_input.json>) currently contain **synthetic HTML only**; optional future local replay must keep any real body private and must not print that file.

## Proven potential failure mechanisms — not the phone diagnosis

### 1. HTML5 implicit TBODY mismatch

For compact, extended and minimal, the source roots require `table.itg.MODE > tbody > tr`. Removing explicit `tbody` from each otherwise valid fixture makes production and lxml return **zero items**. They retain `table > tr` instead of inserting a table body.

A separate Chromium **DOMParser** standards oracle, run on `about:blank` without network, tested three mode classes × explicit/absent tbody. All six cases have one `tbody` and one source-root row; direct `table > tr` count is zero. Browser-only [oracle output](<C:/Users/<user>/.dsh/profiles/desktop/tools/eh_html_reference/browser_results.json>) resides in the MCP allowed output root (the browser tool cannot write into the project). No EH page was navigated.

This proves a generic tree-construction difference, **not that actual EH response lacks tbody**. Do not fix production tree behavior or classify the phone failure until an actual captured response demonstrates relevance. It also does not explain thumbnail mode, which has no table-body requirement.

### 2. Source positional assumptions silently drop rows

Compact dereferences fixed element-child paths including `children[2+t].children[0].children[1].children` for tags; removing that tag container drops the matched fixture row under the source's empty catch. Minimal evaluates `coverPath[0]` even if its image query returned no `src`; removing the image likewise drops the matched row. These are source assumptions, not proven native child/type defects. Compact `children` excludes whitespace/comment nodes correctly in the tested production model.

Thumbnail/extended can instead return `Unknown`/empty cover when other fields are missing **if a nonempty rating style exists**. Shape mismatch need not produce a top-level exception. `next` is read independently from `a#dnext`; zero items are not intrinsically proof of a declared end.

### 3. Critical unchanged-source empty-rating-style infinite loop

[Source helper](<../../logs/user8-installed-scripts/ehentai.js#L174-L181>) scans until `;` or `i === position.length`, but increments before the length comparison. For `position === ''`, `i` becomes 1 and can never equal length 0: the loop does not terminate. Thumbnail, extended and minimal call this helper with fallback `''` when the rating style is missing. An explicitly empty compact style can also reach it.

The full source's synchronous helper call `getStarsFromPosition('')` reliably hits the 25 ms VM watchdog. An initial native malformed fixture also stalled and its standalone test job was cancelled; no such unbounded case remains in the final native suite. All valid mode fixtures use nonempty star styles. A Node timer **cannot interrupt a synchronous native QuickJS loop**. Optional captured-body native replay conservatively rejects matched rows with missing/empty relevant styles first. For unknown captures, start with the structural count query, not the source list parser.

This is a source bug/risk, **not evidence of the recorded fast-empty phone symptom**. Do not automatically patch source or enable new parsing branches without a separate execution-budget/interrupt review owned by the parent.

## Exact public capture specification for parent

[Machine-readable spec](<probe_spec.json>) includes all 25 selectors, 20 additional landmarks, four mode roots, a body-content-free count/first-shape script, exact default options, allowlist and capture bounds.

Installed defaults (not a claim that persisted phone settings were inspected):

- `domain = e-hentai.org`, `ehevent = false`, `hvevent = false`.
- Search categories serialize to `["0","1","2","3","4","5","6","7","8","9"]`; minimum stars and language unset (`null`, or equivalent empty dropdown values). The category exclusions sum to zero, so initial URLs have **no** `f_cats`; no stars means no `f_srdd`; no language suffix.
- Source list call uses explicit `{}` headers. The inspected production source handler injects `User-Agent: VeneraNext/v1.17.0`; HTTP transport adds `Accept-Encoding: identity` if absent. Transport-internal headers are not fully characterized by these source contracts.

Actual unchanged request-builder interception asserted these exact initial public URLs and GET with empty source headers:

1. latest: `https://e-hentai.org` (no slash in source; normal wire root slash is equivalent)
2. popular: `https://e-hentai.org/popular`
3. search `a`: `https://e-hentai.org/?f_search=a`
4. search `魔法`: `https://e-hentai.org/?f_search=%E9%AD%94%E6%B3%95`

Watched returns an empty result without HTTP when not logged in and is **not** in the public capture allowlist. Do not capture account/events/favorites/ranking/gallery/API/next-page endpoints.

Safe parent capture requirements: disable both cookie attachment and jar updates; no account/source-data/cookie reads; explicit UA above; GET only; retries 0; max decoded body 2 MiB; finite timeouts; stop on 401/403 without bypass. Save HTML privately rather than dumping bodies. Metadata allowlist: safe initial URL/case, validated allowlisted final URL, status, content type, byte/character counts, SHA256, UA, cookie sent/updated false. Never dump all headers or rejected redirect destinations.

**Disable redirects or validate each hop before following.** If the chosen HTTP SDK cannot guarantee this, do not describe it as zero-redirect or exact-allowlist capture: the parent must select a capable transport or explicitly resolve that safety limitation before capture. Reusing a method that validates only the initial URL does not satisfy the stricter specification.

A credential-free public response may differ from the matrix's original response if stored preferences/cookies were present; the capture is a controlled public template comparator, not guaranteed byte-for-byte matrix reproduction. No network or device step was performed here.

## Next bounded action

When parent-authorized phone transport is ready, capture only the four allowlisted public bodies and metadata, then run the safe structural count script first. Compare actual root/landmark counts and explicit/raw tbody presence with the independent oracle before deciding whether any HTML compatibility or source-assumption fix is relevant. Keep phone EH classification **UNDETERMINED** until that evidence exists.
