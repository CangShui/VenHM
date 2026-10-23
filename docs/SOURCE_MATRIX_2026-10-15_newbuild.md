# 历史逐源矩阵报告（2026-10-15，20源遍历；旧归因已纠正）

> **请勿沿用下述“源过期/迁移无错”及“7个全流程通过”的归因。** 当前以
> [逐阶段复核报告](<SOURCE_MATRIX_2026-10-15_reviewed.md>)和[真机点验与UA纠正](<USER8_DEVICE_REVIEW_20261015.md>)为准。
> 已证明移植默认Phone UA导致WNACG收到不同移动模板；恢复原版默认UA后手机实际搜索24→48并进入121页正文。
> Komiic是maxPage1的一次性搜索；nhentai/ykmh分类失败不能被阅读链路成功覆盖。以下仅保留历史记录，不是当前验收结论。

> 证据文件：`logs\user8-device-matrix\deep-1792033074497.jsonl`。这是**公开只读**矩阵；不含登录、发布、收藏写入，也不代表 L4/L5 或真实账号通过。

## 取样链路通过（7）

| 源 | 探索 | 分类 | 搜索 | L3 |
|---|---|---|---|---|
| `hcomic` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `manga_dex` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `hitomi` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `nhentai` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL_TARGETS | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `ykmh` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `copy_manga` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |
| `jm` | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK |

## 未通过/未完成（13）

| 源 | 归因 | 说明 | 最后阶段证据（已脱敏） |
|---|---|---|---|
| `wnacg` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | 魔法: TypeError: cannot read property 'text' of undefined |
| `komga` | C_SITE_AUTH_OR_NETWORK_BLOCK | 需要登录或源配置（继续排查，不是豁免） | 魔法: TypeError: Setting not found: default_username |
| `Komiic` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | chapter=3 page=21/21 decoded=1000x1333 thumbnail=false modified=false；解码不等于真实内容人工验收 |
| `picacg` | C_SITE_AUTH_OR_NETWORK_BLOCK | 需要登录或源配置（继续排查，不是豁免） | 魔法: Error: Not logged in |
| `comick` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | chapter=30 page=97 图片HTTP 403 |
| `ehentai` | UNDETERMINED | 证据不足，需更细取样 | 魔法:p1=0 broken=0 |
| `zaimanhua` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | Error: 漫画不存在或已被删除 |
| `baozi` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: Invalid status code: 403 |
| `happy` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: 网络请求失败: code 2300999: Internal error |
| `shonen_jump_plus` | B_NEEDS_UPSTREAM_COMPARISON | 源规则/分页/非JSON正文需与原版或标准客户端对照后定性 | 魔法: SyntaxError: unexpected token: '<' |
| `ManHuaGui` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法: 网络请求失败: code 2300028: Operation timeout |
| `manwaba` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | chapter=23 page=29 Decode failed. e.g.,Decode image header failed. |
| `ikmmh` | C_SITE_AUTH_OR_NETWORK_BLOCK | 站点/网络/登录限制（需继续排查，不是豁免） | 魔法:p1=0 broken=0 |

## 决定性归因：绅士漫画 wnacg（本轮实测）

手机在**无 Cookie、公开路径**下对当前默认域名抓到 3 份 **HTTP 200** 响应
（30994 / 42559 / 42833 字符；本机同 URL 为 403，说明网络出口不同）。
用**独立解析器（lxml/libxml2，非本工程引擎）**对手机同一份字节解析：

| 选择器 | 独立解析器命中 |
|---|---|
| `p.result > b` | **0** |
| `div.grid div.gallary_wrap > ul.cc > li` | **0** |
| `div.title_sort` / `div.bodywrap` | 0 |
| `a[href]` | 58 |

页面确实是真实的绅士漫画搜索结果页（可见“搜索結果 … 同人誌 4623 中文 11426”），
但站点已**不再使用 `gallary_wrap`/`class="cc"` 这套结果列表标记**。
因此结论是：

- **不是本工程 HTML 引擎解析错误**（独立解析器结果一致为 0）。
- **是源脚本选择器相对站点当前标记已过期**（`wnacg.js` 1.0.6 期望旧结构）；
  脚本第 491 行又对空结果直接取 `p.result > b[0].text`，于是抛
  `cannot read property 'text' of undefined`。
- 修复方式应是**更新该源脚本/等待源仓库更新**，不是改应用桥或解析器；
  应用侧可做的是给出可读错误而不是裸 TypeError。

## 与上一轮构建的对比（同一套矩阵）

| | 上一轮包 | 本轮修正包 |
|---|---|---|
| 取样链路通过 | 5 | **7**（新增 manga_dex、copy_manga） |
| 分类阶段 | 仅静态标签 | 多数源出现 `PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE`（**真实发起**分类请求） |
| ehentai | `not a function` + `JSON.parse(undefined)`（A 类迁移缺口） | 不再出现；现为 0 结果（需登录/换词），归 UNDETERMINED |
| 到达图片解码 | 少 | Komiic 到 chapter3 page21/21 解码 1000x1333；comick 到 chapter30 page97（图片403）；manwaba 到 chapter23 page29 |

说明：本轮修的迁移缺口（游标探索、搜索默认选项、分类真实请求、逐阶段隔离）**产生了可测量的真实改善**。

## 归因含义

- `A_APPLICATION_*`：迁移层缺陷，**必须修**，不能记成源问题。
- `B_NEEDS_UPSTREAM_COMPARISON`：源脚本对空结果直接取字段，或分页参数未生效；必须在**同一份响应**上与独立解析器/原版语义对照后才能定性。
- `C_SITE_AUTH_OR_NETWORK_BLOCK`：401/403/422/超时/需要登录或源配置；**禁止**当作上游豁免，必须继续排查到能区分 A/B/C。
- `UNDETERMINED`：证据不足，需要更细取样或换候选，不得写成通过。
