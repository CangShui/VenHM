# 逐源矩阵报告（2026-10-14 上一轮签名包（20源，已完成））

> 证据文件：`logs\user8-baseline-full-matrix-20261014.jsonl`。这是**公开只读**矩阵；不含登录、发布、收藏写入，也不代表 L4/L5 或真实账号通过。

## 取样链路通过（5）

| 源 | 探索 | 分类 | 搜索 | L3 |
|---|---|---|---|---|
| `hcomic` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | STATIC_PARTS_OK_DYNAMIC_NOT_VERIFIED | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `hitomi` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | STATIC_PARTS_OK_DYNAMIC_NOT_VERIFIED | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `nhentai` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | STATIC_PARTS_OK_DYNAMIC_NOT_VERIFIED | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `ykmh` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | STATIC_PARTS_OK_DYNAMIC_NOT_VERIFIED | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `jm` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | STATIC_PARTS_OK_DYNAMIC_NOT_VERIFIED | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |

## 未通过/未完成（15）

| 源 | 归因 | 说明 | 最后阶段证据（已脱敏） |
|---|---|---|---|
| `komga` | C_SITE_AUTH_OR_NETWORK_BLOCK | 需要登录或源配置（继续排查，不是豁免） | 魔法: TypeError: Setting not found: default_username |
| `Komiic` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | 魔法:p1=100 p2=100 cursorOnly=false different=false |
| `manga_dex` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: Error: Network response was not ok |
| `picacg` | C_SITE_AUTH_OR_NETWORK_BLOCK | 需要登录或源配置（继续排查，不是豁免） | 魔法: Error: Not logged in |
| `comick` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: Invalid status code: 400 |
| `ehentai` | A_APPLICATION_BRIDGE_OR_DISPATCH_GAP | 迁移层桥/解析/分发缺口（已用源脚本+调用点确认） | 魔法: SyntaxError: unexpected token: 'undefined' |
| `zaimanhua` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | Error: 漫画不存在或已被删除 |
| `baozi` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: Invalid status code: 403 |
| `happy` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: 网络请求失败: code 2300999: Internal error |
| `shonen_jump_plus` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | 魔法: SyntaxError: unexpected token: '<' |
| `copy_manga` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | Invalid status code: 210 |
| `ManHuaGui` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: 网络请求失败: code 2300028: Operation timeout |
| `manwaba` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: Invalid status code: 400, body:  |
| `ikmmh` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法:p1=0 broken=0 |
| `wnacg` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | 魔法: TypeError: cannot read property 'text' of undefined |

## 归因用的外部复核（本轮新增）

- **shonen_jump_plus**：其 `fetchBearerToken` 对 `/api/v1/user_account/access_token` 的响应**不检查状态码**就 `JSON.parse`。
  用标准主机客户端带同一组公开头部复现该请求，得到 **HTTP 403 + `text/html`**；
  因此 `unexpected token '<'` 的根因是**站点拦截**，不是迁移层桥缺陷（归因规则已按此修正）。
- **wnacg**：当前公开默认域名在本机独立测试返回 **HTTP 403**，同样不得判为源规则损坏；
  其脚本 `wnacg.js:491` 对空结果直接取 `[0].text` 是**源健壮性**问题，需在拿到同一响应后再定性。
- **ehentai**：`explore[].loadNext` 被迁移层硬调 `load`、搜索未传 `search.optionList` 默认值，
  已在源脚本+调用点确认，属于**迁移层缺口**（已修）。
- 结论：**“源脚本对错误响应不设防”与“站点拦截”必须分开记录**；`C_` 类不得当作豁免。

## 归因含义

- `A_APPLICATION_*`：迁移层缺陷，**必须修**，不能记成源问题。
- `B_NEEDS_UPSTREAM_COMPARISON`：源脚本对空结果直接取字段，或分页参数未生效；必须在**同一份响应**上与独立解析器/原版语义对照后才能定性。
- `C_SITE_AUTH_OR_NETWORK_BLOCK`：401/403/422/超时/需要登录或源配置；**禁止**当作上游豁免，必须继续排查到能区分 A/B/C。
- `UNDETERMINED`：证据不足，需要更细取样或换候选，不得写成通过。
