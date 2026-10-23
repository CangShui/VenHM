# 漫画源验收完整流程（逐级细则）

> **2026-10-15纠正：错误关键词不是定责证据，完整遍历不是全部功能通过。** 以
> [真机点验与UA纠正](<USER8_DEVICE_REVIEW_20261015.md>)和[逐阶段复核报告](<SOURCE_MATRIX_2026-10-15_reviewed.md>)为准。
> 已确认固定原版默认UA与移植Phone UA不一致，恢复后WNACG同手机实际搜索24→48并进入121页正文；探索首页仍空。
> Komiic搜索maxPage1，验证器已停止要求不存在的第二页；SDK401不是HTTP401；分类按item/part/phase保留失败，不能被链路成功掩盖。
> 下面的2026-10-14归因标签是历史快照，不得据此免除迁移适配排查。

> **2026-10-14 逐源归因更新（本轮）**：矩阵现在按阶段隔离并给每个源一个 `classification`，
> 不再把工具自身错误算成源问题：
> `A_APPLICATION_BRIDGE_OR_DISPATCH_GAP`（桥/解析/分发缺口，必须修）·
> `A_APPLICATION_IMAGE_GAP` · `B_SOURCE_RULE_NEEDS_DOM_COMPARISON`（源脚本对空结果不设防，
> 需用**同一份响应**在独立解析器与自建HTML引擎上对照后才能定性）·
> `C_SITE_AUTH_OR_NETWORK_BLOCK`（401/403/422/超时/网络；**仍需继续排查，绝不是豁免**）·
> `NO_PUBLIC_FAILURE_OBSERVED`（公开阶段无失败；L4/L5 仍未测）。
>
> 已确认的**迁移层缺陷**（非源问题）：E-Hentai 只声明 `explore.loadNext` 却被迁移层硬调 `load`
> （`not a function`），以及搜索未把源 `search.optionList` 的默认值按位置传入
> （`JSON.parse(undefined)`）。两者已修并有回归。
>
> 绅士漫画 wnacg：其搜索脚本对 `p.result > b` 空结果直接取 `[0].text`（无保护），
> 但当前公开默认域名直连在本机独立测试返回 **HTTP 403**，因此**不得判为源规则损坏**；
> 代码已加入无 Cookie、有上限、遇403即停的公开HTML诊断，用于取得与手机完全相同的响应再做双解析器对照。
> **本轮最终逐源结论因设备断连未完成。**

> **最终修复更新**：UI builder崩溃已经修复；设备冷启动后五种对话框API的无副作用脚本自检PASS，
> 包括校验、取消、异步按钮、加载取消队列及onCancel；日志文件实际读回通过。
> 验证范围与证据见HANDOVER置顶修复记录；真实站点/验证码图片/完整深度源矩阵仍待验收。

> **2026-10-13 21:14更新**：CLI签名与新包覆盖安装已完成。`invokeFunction`同步/异步/异常回程、
> RSA1024单块参考向量已上板通过；UI对话框自检触发`observeComponentCreation2 of undefined`崩溃，
> 判为应用缺陷、未通过。深度矩阵仍未运行。下方“未上板”标记为此前快照，最新证据见HANDOVER置顶记录。

> 适用对象：Venera-HM（鸿蒙移植版）中每一个已安装的 `.js` 漫画源。
> 目的：把「这个源能不能用」拆成**可复现、可判定、可追责**的等级，并明确**每一项要测到多细**。
> 本文是验收标准，不是进度汇报；当前实现到哪一级见文末「现状」。

---

## 0. 一句话原则

**源矩阵只能证明源运行链路；应用自身缺陷不得记为源问题。**
任何一项失败必须先归入下列三类之一，并给出对应证据，才能写进结论。

| 分类 | 含义 | 需要的证据 | 处理方式 |
|---|---|---|---|
| **A 应用缺陷** | HM 的桥/HTML/加密/存储/UI/网络层错 | 同一输入在原版（或等价最小脚本）下通过；或逻辑回归可复现 | **必须修**，不得豁免 |
| **B 源兼容缺陷** | 同一条规则在原版可用、HM 不可用 | 原版对照 + 上游脚本逐行比对 + 失败点定位到具体 API | **必须修**，不得豁免 |
| **C 站点/规则自身问题** | 上游代码或站点本身即坏 | 见 §6 的强证据要求 | 可标记为「上游即坏」并跳过 |

**禁止**把 `401 / 403 / 422 / 超时 / 连接失败` 直接判为 C。这些首先说明**未登录、需配置、被风控或网络不通**，必须继续排查到能区分 A/B/C。

---

## 1. 验收等级 L0–L5

按依赖顺序执行；低等级失败时高等级结果无效。

| 等级 | 名称 | 依赖 | 是否需要外网 |
|---|---|---|---|
| **L0** | 离线契约 | 无 | 否 |
| **L1** | 注册与解析 | L0 | 否 |
| **L2** | 静态元数据 | L1 | 是 |
| **L3** | 全链路 | L2 | 是 |
| **L4** | 交互能力 | L3 | 是 |
| **L5** | 站点专项能力 | L3 | 是 |

一个源只有 **L0–L3 全通过**才可标 `PASS`；L4/L5 单独标注，不参与 `PASS` 判定但必须记录。

---

## 2. L0 离线契约（不联网，每次启动自动跑）

**要测什么**：桥、HTML 引擎、编码、加密、Cookie、设置、UI 回调。这些是**所有源共用**的底座，必须在任何源之前全绿。

| 项 | 判定标准 | 当前实现 |
|---|---|---|
| QuickJS 可用 | `quickjsVersion()` 有值，`init.js` 求值不抛 | ✅ `JsEngine.init` |
| 并发 Promise 不串线 | 两个并发 `callJson` 各自结算，结果互换后仍正确 | ✅ 启动自检 |
| TypedArray 子视图 | `subarray(1,2)` 的 base64 只含 1 字节 | ✅ 启动自检 |
| JS 函数句柄回程 | 同步返回、Promise、异常回传正确 | ✅ 新包启动三类往返通过，见HANDOVER置顶记录 |
| 设置 callback | `this` 绑定正确、Promise 回程正确 | ✅ 启动自检 |
| AES-128 四模式 | ECB/CBC/CFB8/OFB 与 OpenSSL 参考向量一致 | ✅ 设备向量 |
| GBK 编码 | `中 → d6d0` | ✅ 设备向量 |
| RSA | 与参考向量一致 | 🟡 RSA1024单块设备向量通过；其他模长/多块待验 |
| Cookie jar | host-only/Domain/Path/Secure/Max-Age/过期/重启持久 | ✅ 离线回归 |
| Cookie 与 HTTP 联动 | 请求自动带 Cookie、响应多条 Set-Cookie 正确入库 | ⚠️ 仅离线；真实响应未验 |
| 源设置读写 | 字符串/数字/布尔/select/callback 保存并跨重启读回 | ✅ 部分（设备验证过 3 类） |
| UI 对话框 | 五种API可用，回调、取消、校验及队列正确 | 🟡 无副作用脚本设备自检通过；真实登录/验证码图待验 |
| HTML 引擎 | 见 §5.6 的用例集 | 🟡 覆盖不足 |

**L0 判定**：上表 ✅ 项全过；⚠️ 项必须补设备验证后才可写「通过」。

---

## 3. L1 注册与解析（不联网）

对**每一个**已安装源逐项检查，缺一项即 L1 失败：

| 检查项 | 判定标准 |
|---|---|
| 脚本可解析 | `ComicSourceParser.parse` 不抛异常 |
| 类名识别 | `sourceClassName` 正则命中且实例化成功 |
| `key` 合法 | 非空、与文件名/安装记录一致、未与内置源冲突 |
| `name` / `version` | 非空；`version` 可被 semver 比较 |
| `minAppVersion` | ≤ 本应用上报版本（`APP_VERSION`，当前 1.17.0）；超限应显式报「版本过低」而不是静默失败 |
| 能力标志 | `search` / `explorePages` / `loadComicInfo` / `loadComicPages` / `loadCategoryData` / `getImageConfig` / `getThumbnailConfig` 是否定义，逐项记录 |
| `settings` schema | 每个设置项能取出 `title/type/default`；`type` ∈ input/select/switch/callback；select 的 `options[].value` 类型保留（字符串/数字/布尔） |
| `account` 定义 | 是否有 `login`/`logout`/`isLogged`，登录方式是「账号密码」还是「WebView/Cookie」 |
| `init()` | 注册后按上游时序调用；异常被捕获并记录，不影响其他源 |
| 翻译表 | `translation` 是否含 `zh_CN`（缺失不算失败，但要记录 UI 会显示原文） |

**记录格式**：`<key> | L1 | 能力位图 | settings 项数 | account 方式 | init 结果`

---

## 4. L2 静态元数据（联网，逐段逐页）

### 4.1 explore（发现页）

- **全部** `explorePages` 都要测，不能只测第 1 个。
- 每个 explore 页：至少测 **第 1 页 + 第 2 页**（若存在分页）。
- `singlePageWithMultiPart` / `multiPartPage` / `mixed` / `multiPageComicList`：**每个 part 都要有非空数据**；part 标题、part 内条目数逐项记录。
- 每个条目检查 `id` / `title` / `cover` **三者非空**；任一为空计入 `broken`。
- 判定：`broken == 0` 且总条目 > 0 才算该 part 通过。

### 4.2 category（分类）

- **全部** `parts` 都要测；每个 part 至少取 **前 2 个 item**。
- 每个 item 必须有 `name`，且 `target` 能解析出可执行动作（`category` / `param` / `search` 等）。
- 随机分组、动态分类 loader（`category.loader`）需**单独**验证：调用一次并确认返回结构与上游一致。
- 判定：所有 part 全部 item 的 `name` + `target` 均可用。

### 4.3 search（搜索）

**深度要求（用户重点）**：

| 维度 | 最低要求 |
|---|---|
| 关键词数 | **≥ 2 个**，且至少 1 个为 CJK、1 个为 ASCII 数字或字母 |
| 每关键词页数 | **≥ 2 页**（验证分页参数真的生效） |
| `loadNext` 游标源 | 必须额外测「只提供 `loadNext`」的路径：首次传 `null`，第二次传上一页返回的游标 |
| 结果字段 | 首页每一条检查 `id/title/cover` 非空 |
| 结果数量单调性 | 第 2 页结果与第 1 页**不得完全相同**（否则说明分页未生效） |
| 空结果处理 | 无结果时必须是「0 条」而不是异常 |

判定：任一关键词在第 2 页仍返回非空且与第 1 页不同 → 该关键词通过；**至少一个关键词通过** → search 通过。

> 关键词扫描（`sourceSelfTestKeywordSweep`）用于区分「移植坏了」和「该关键词本来没结果」，必须记录每个源**第一个能出结果的关键词**。

### 4.4 详情字段完整度（记录，不判定失败）

对详情页逐字段记录「有/无」，用于定位 UI 空白：

`title`（必需）、`cover`（必需）、`author`、`updateTime`、`tags`、`description`、`chapters`、`recommend`、`commentCount`。

`title` 或 `cover` 为空 → L2 失败；其余缺失只记录。

---

## 5. L3 全链路（判定 PASS 的核心）

链路：`search → loadComicInfo → chapters → loadComicPages → 图片解码`

### 5.1 章节取样深度

| 场景 | 要求 |
|---|---|
| 单章节漫画（无章节列表） | 必须按「隐式单章」路径测一次（`epId=''`） |
| 2 章 | 第 1 章 + 第 2 章 |
| ≥3 章 | **第 1 章 + 最后一章 + 中间随机 1 章**（共 ≥3 章） |
| 分组章节 | 每个 group 至少 1 章；`chapter_group` 语义要与上游一致 |

### 5.2 每章图片取样深度

每章至少下载并**解码** 3 张：**首张、中间张、末张**。

- 首张 = `images[0]`；末张 = `images[images.length-1]`；中间张 = `images[floor(len/2)]`。
- 每张必须：HTTP 2xx、字节数 ≥ 64、**ImageKit `getImageInfo` 解出真实宽高 > 0**。
- 只验字节数不算通过：错误页/截断文件也会 > 64 字节。

### 5.3 图片请求钩子

- `getImageConfig`（`onImageLoad`）：每个源都要走一遍，确认 `url` 改写与 `headers` 注入生效；抛异常要能被捕获并记为源失败。
- `getThumbnailConfig`（`onThumbnailLoad`）：至少 1 次。
- 图片需要解密的源（`modifyImage` 等）：必须验证解密后仍能解码出真实尺寸。

### 5.4 判定

```
<key> | PASS | search->details->N pages, cover+first+last decoded
```

必须**同时**满足：search 有结果且字段完整 → 详情 title/cover 非空 → 章节（或隐式单章）可加载 → 章节图片 ≥ 1 → 封面 + 首张 + 末张全部解码成功。

只写「search 返回数组」**不算通过**。

### 5.5 回归要求

任何对下列文件的改动，都必须**重跑全部源的 L3**：
`napi_init.cpp`、`value_bridge.h`、`html_engine.js`、`sendmessage_shim.js`、`JsComicSource.ets`、`ComicSourceParser`、`HttpClient.ets`、`CookieJar.ets`、`ImageLoader.ets`。

### 5.6 HTML 引擎专项（最高风险层）

自建 HTML/CSS 引擎替代了上游 `package:html`，必须用 `tools/html_engine_probe.js` 对**真实页面**逐源验证：

- 选择器：`tag` / `.class` / `#id` / `[attr]` / `[attr=value]` / 后代 / 子代 / 逗号并集 / `:first-child` / `:nth-child(n)`
- 属性读取：`text` / `innerHtml` / `attributes` / `nextSibling` / `children`
- 编码：GBK 页面、`<meta charset>` 缺失、实体转义（`&amp;` 等）
- 判定：对每个网页类源，脚本用到的选择器链路**逐条**在真实页面上命中。

---

## 6. L4 交互能力

| 项 | 深度要求 |
|---|---|
| 登录（账号密码） | 登录前跑 L3；登录后重跑 L3 并**对比差异**；登出后再跑一次确认回退 |
| 登录（WebView/Cookie） | 至少完成一次真实登录，并确认 Cookie 进入持久 jar、重启后仍登录 |
| 设置项 | **每个**设置项：读默认值 → 写测试值 → 强制重启 → 读回 → **恢复原值** |
| `UI.*` 对话框 | 5 个函数逐个真实点击；验证回调被调用、返回值得以回传脚本、取消返回 `null` |
| 源内收藏（网络） | 收藏 / 取消 / 列表三向一致 |
| 评论 | 拉取列表；如支持发布，测一次发布（或明确标注未测） |
| `compute` | 调用一次并确认结果与原版一致 |

**测试数据纪律**：只使用随机命名、带标记的测试数据；测试后必须恢复原值/清理，并在报告中写明「已恢复」。

---

## 7. 判定与豁免规则

**可以判为 C（上游即坏）的条件（需同时满足）**：

1. 从官方发布地址重新下载同版本脚本，**逐行/逐字节**比对与本地一致；
2. 能指出上游代码中的具体缺陷位置（文件:行 + 原因），例如 `this` 指向错误、字段拼写错误；
3. 结论可被第三方复现（给出复现步骤与关键日志）。

**不可以判为 C 的情形**：`401/403/422`、超时、连接重置、需要登录、需要配置代理、VPN 不稳、关键字无结果、站点改版（站点改版属于「规则需更新」，不是「规则即坏」）。

---

## 8. 设备执行流程

```powershell
# 1. 构建（必须设三个环境变量）
$deveco = "C:\Program Files\Huawei\DevEco Studio"
$env:JAVA_HOME="$deveco\jbr"; $env:DEVECO_SDK_HOME="$deveco\sdk"
$env:PATH="$deveco\tools\hvigor\bin;$deveco\tools\ohpm\bin;$deveco\tools\node;$deveco\jbr\bin;$env:PATH"
& "$deveco\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap

# 2. 安装并冷启动（aa start 对已运行应用只是切前台，不会重跑 init）
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
hdc shell "aa force-stop com.venerahm.reader"
hdc shell "aa start -b com.venerahm.reader -a EntryAbility"

# 3. 流式抓日志（hilog -x 是一次性 dump，长自检会被挤掉）
$proc = Start-Process -FilePath hdc -ArgumentList 'shell','hilog' `
        -RedirectStandardOutput "$env:TEMP\hl.log" -NoNewWindow -PassThru
# …等待自检…
Stop-Process -Id $proc.Id -Force
Get-Content "$env:TEMP\hl.log" | Select-String 'SelfTestReport'
```

- 结果同时写入 `filesDir/selftest.txt`，但**沙箱不可读**（`hdc file recv` 报 permission denied），只能走 hilog。
- 屏幕**必须解锁**，否则 `aa start` 返回 `10106102`。
- UI 取证：`uitest dumpLayout` 导出界面树；`snapshot_display -f xxx.jpeg`（**PNG 在本设备不生成文件**）。
- 网络失败必须先确认 VPN/网络状态，再判断是否为应用缺陷。

---

## 9. 记录格式

矩阵每行至少包含：

```
key | L0 | L1 | L2(search/explore/category) | L3(PASS/FAIL+阶段) | L4 | L5 | 分类(A/B/C) | 证据(日志行/截图/命令)
```

`PASS` 行必须附带：搜索关键词、章节数、页数、三张图片的实际尺寸。

---

## 10. 现状（截至本文撰写时，务必以最新日志为准）

| 等级 | 实现状态 |
|---|---|
| L0 | 🟡 桥/AES/GBK/Cookie、invokeFunction及UI模拟脚本设备通过，RSA1024向量通过；真实HTTP/其他向量待验 |
| L1 | 🟡 注册解析已实现；**能力位图/设置项数/账号方式现在每次启动自动输出**（`<key> \| L1 \| …`）；`minAppVersion` 与翻译表仍未输出 |
| L2 | 🟡 取样代码已按本文写好（全部 explore 页 + 第 2 页 + part 结构、全部 category part 前 2 项、2 关键词 × 2 页、loadNext 两跳），但**只在 `sourceSelfTestDeep=true` 时执行，且未上板** |
| L3 | 🟡 深度取样已实现（章节首/中/末、每章首/中/末三张解码）；默认启动仍是单章 + 封面/首张/末张；**均未上板** |
| L4 | 🟡 UI五API模拟脚本与部分静态设置已设备验证；真实登录/网络收藏/评论/compute待做 |
| L5 | ❌ 未实现（HTML 引擎仅少量用例） |

**怎么跑深度矩阵**：`历史 → 离线可用性验收 → 源自检深度取样` 打开（写 `sourceSelfTestDeep`，下次启动生效），
然后强停并冷启动应用，从 hilog 抓 `SelfTestReport`。深度模式每源约多 10 次图片请求，别和 `sourceSelfTestKeywordSweep` 同时开。

**历史设备快照（2026-10-12）**：21 个搜索源中 3 个全链路 PASS；修复 `loadNext` 后新增 ehentai（搜索源 22 个）。这**不是**当前通过率，网络状态会改变结果。

**历史状态**：此前本机未恢复签名；现在CLI签名/新包部署已完成，最新状态见HANDOVER置顶。
手机旧版浅取样及数据库回归见 [DEVICE_ACCEPTANCE_2026-10-13.md](DEVICE_ACCEPTANCE_2026-10-13.md)；
RSA、`invokeFunction`、UI 对话框和新深度矩阵仍待新包上板，不能据旧版结果更新为通过。

---

## 11. 禁止声称清单

- ❌「编译成功」＝ 功能对齐
- ❌「离线向量通过」＝ 源可用
- ❌「搜索返回数组」＝ 源可用
- ❌ 把 A/B 类缺陷写成「源规则问题」
- ❌ 用旧快照的通过数代表当前状态
- ❌ 未恢复测试数据就写「验收完成」
