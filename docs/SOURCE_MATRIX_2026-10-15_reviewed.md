# 逐源矩阵观察报告：已完成手机记录的逐阶段复核，不是最新UA修正包验收

原始设备证据：[deep-1792033074497.jsonl](<../logs/user8-device-matrix/deep-1792033074497.jsonl>)。这里只执行公开只读取样，不登录、不发布、不变更网络收藏。

## 完整性与判定边界

- 已输出源行：**20 / 20**；END标记：**有**；坏JSON行：**0**。
- 本轮遍历完整性：**完整遍历已列源**。
- 详情/章节/取样图片链路成功：**8**（允许来自探索/分类候选；不等于搜索通过）。
- 已观测L1/探索/实际分类目标/搜索/阅读链路取样均无失败：**5**。
- **L0仍为部分契约，L4/L5真实账号和站点专项未测。无一行可因此升格为全部功能PASS。**
- 旧“链路通过7个”忽略了nhentai/ykmh分类失败，也忽略Komiic的独立阅读链路；现将阶段分开展示。
- 只有错误关键词不是定责证据；HTTP403可能涉及我们的UA/请求适配，不能作为源坏或上游豁免。

## 全部源逐阶段观察

| 源 | L1 | 探索 | 分类（实际请求） | 搜索 | 阅读链路 | 观察分类/待定位 |
|---|---|---|---|---|---|---|
| `hcomic` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `komga` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | CONFIGURATION_REQUIRED_OBSERVED；观察到配置缺失；还需区分用户未配置与默认值迁移缺失 |
| `Komiic` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | FAIL_OR_NEEDS_CONFIGURATION | SAMPLE_CHAIN_OK_SEARCH_NOT_PASSED | PAGINATION_COMPARISON_REQUIRED；安装源search.load虽然接收page参数，但只发送keyword变量且明确返回maxPage:1。这是有限的一次性搜索，不应强求第二页不同；此前矩阵的分页失败是验证器误判，已修正并加回归，新的手机矩阵仍待复测。原始记录的阅读链路已完成。 |
| `manga_dex` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `picacg` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | LOGIN_REQUIRED_OBSERVED；源报告需要登录；未输入真实账号，不能验证登录后路径 |
| `comick` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | FAIL_OR_NEEDS_CONFIGURATION | FAIL_IMAGES_OR_CHAPTERS | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `ehentai` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_EMPTY_PARTS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；已复现迁移层未支持explore.loadNext和未填multi-select默认JSON值导致调用前失败；这些调用契约已修。新包不再出现相同错误，但0结果尚不能推定为登录问题。默认Phone UA也可能改变HTML，按原版UA复测后再归因。 |
| `hitomi` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `nhentai` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL_TARGETS | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；原始记录阅读链路成功，但分类FAIL_TARGETS，不能整体标为无公开失败。新的逐目标阶段日志将保留失败后继续其他part。 |
| `ykmh` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；原始记录阅读链路成功，但分类FAIL，不能用链路成功覆盖分类错误。 |
| `zaimanhua` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | FAIL_CHAIN | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `baozi` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `happy` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `shonen_jump_plus` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | NOT_APPLICABLE | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；旧矩阵只有JSON '<'错误；后来的另一次手机日志在同Trace的POST后记录HTTP403再发生JSON错误。源token函数未检查status就JSON.parse。仅能说明那次观察到403 HTML，不能凭主机不同网络403就给旧矩阵定责，更不能证明具体WAF或排除请求适配。 |
| `copy_manga` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `ManHuaGui` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `manwaba` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | FAIL_IMAGES_OR_CHAPTERS | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `ikmmh` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `jm` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `wnacg` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；已证明的是当前安装规则与手机返回的移动模板不匹配，不能直接说站点改版且应用无错。移植网络层给空headers注入Phone UA，固定原版app_dio使用VeneraNext/v1.17.0；这是已确认的请求契约迁移差异。已恢复源默认UA，当前同手机结果待新包公开探针核对。 |

## 失败点与可复现定位

### `hcomic`

- `L2_SEARCH`：a:p1=10 p2=10 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=10 p2=10 cursorOnly=false different=true
- `L2_DETAILS`：title=true cover=true author=false chapters=1
- `L3_IMAGE`：cover decoded=1068x1516 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/25 decoded=1068x1516 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=13/25 decoded=1032x1511 thumbnail=false modified=false；解码不等于真实内容人工验收

### `komga`

- `L2_EXPLORE`：page=1 TypeError: Setting not found: default_username
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a: TypeError: Setting not found: default_username
- `L2_SEARCH`：魔法: TypeError: Setting not found: default_username

### `Komiic`

安装源search.load虽然接收page参数，但只发送keyword变量且明确返回maxPage:1。这是有限的一次性搜索，不应强求第二页不同；此前矩阵的分页失败是验证器误判，已修正并加回归，新的手机矩阵仍待复测。原始记录的阅读链路已完成。

**证据适用范围：** 不改写旧JSONL中different=false的历史观察；不能由源静态契约直接把新的手机搜索标成PASS。

- 对照证据：[Komiic.js](<../logs/user8-installed-scripts/Komiic.js>)
- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 对照证据：[deep_matrix_cases.js](<../tools/deep_matrix_cases.js>)
- `L2_SEARCH`：魔法:p1=100 p2=100 cursorOnly=false different=false
- `L3_IMAGE`：cover decoded=180x240 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/24 decoded=836x1200 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=13/24 decoded=836x1200 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=24/24 decoded=1000x1500 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=7 page=1/21 decoded=853x1200 thumbnail=false modified=false；解码不等于真实内容人工验收

### `manga_dex`

- `L2_SEARCH`：a:p1=20 p2=20 cursorOnly=false different=true
- `L2_SEARCH`：魔法: Error: Network response was not ok
- `L3_IMAGE`：cover decoded=256x364 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/45 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=23/45 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=45/45 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收

### `picacg`

- `L2_EXPLORE`：page=1 Not logged in
- `L2_EXPLORE`：page=2 Not logged in
- `L2_EXPLORE`：page=3 Not logged in
- `L2_EXPLORE`：page=4 Not logged in
- `L2_EXPLORE`：page=5 Not logged in
- `L2_CATEGORY`：undefined is not callable

### `comick`

- `L2_SEARCH`：a: Invalid status code: 422
- `L2_SEARCH`：魔法: Invalid status code: 400
- `CHAIN_CANDIDATE`：搜索未通过，改用公开探索/分类候选独立测阅读链路；搜索失败状态仍保留
- `L3_IMAGE`：cover decoded=280x400 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/74 decoded=800x1500 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE_FAIL`：chapter=1 page=38 图片HTTP 403

### `ehentai`

已复现迁移层未支持explore.loadNext和未填multi-select默认JSON值导致调用前失败；这些调用契约已修。新包不再出现相同错误，但0结果尚不能推定为登录问题。默认Phone UA也可能改变HTML，按原版UA复测后再归因。

**证据适用范围：** 单元控制HTTP证明的是调用契约修复，不等于真实EH账号/搜索/阅读通过。

- 对照证据：[ehentai.js](<../logs/user8-installed-scripts/ehentai.js>)
- 对照证据：[source_contract_ui_cases.js](<../tools/source_contract_ui_cases.js>)
- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 见上表阶段状态；不能以最后一条成功图片解码覆盖前面的失败。

### `hitomi`

- `L2_SEARCH`：a:p1=25 p2=25 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=25 p2=25 cursorOnly=false different=true
- `L2_DETAILS`：title=true cover=true author=false chapters=0
- `L3_IMAGE`：cover decoded=640x360 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/115 decoded=1920x1080 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=58/115 decoded=1920x1080 thumbnail=false modified=false；解码不等于真实内容人工验收

### `nhentai`

原始记录阅读链路成功，但分类FAIL_TARGETS，不能整体标为无公开失败。新的逐目标阶段日志将保留失败后继续其他part。

**证据适用范围：** 手机phase日志需重跑新包后确认是目标协议、动态选项、网络还是源错误。

- 对照证据：[deep-1792033074497.jsonl](<../logs/user8-device-matrix/deep-1792033074497.jsonl>)
- `L2_SEARCH`：a:p1=25 p2=25 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=25 p2=25 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=700x971 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/71 decoded=1280x1776 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=36/71 decoded=1280x1776 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=71/71 decoded=1280x1776 thumbnail=false modified=false；解码不等于真实内容人工验收

### `ykmh`

原始记录阅读链路成功，但分类FAIL，不能用链路成功覆盖分类错误。

**证据适用范围：** 只记录观测结果，不凭异常字符串豁免迁移缺口。

- 对照证据：[deep-1792033074497.jsonl](<../logs/user8-device-matrix/deep-1792033074497.jsonl>)
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a:p1=36 p2=36 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=36 p2=36 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=328x422 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/48 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=25/48 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收

### `zaimanhua`

- `L2_SEARCH`：a:p1=20 p2=20 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=20 p2=20 cursorOnly=false different=true
- `L3_ERROR`：Error: 漫画不存在或已被删除

### `baozi`

- `L2_EXPLORE`：page=1 Invalid status code: 403
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a: Invalid status code: 403
- `L2_SEARCH`：魔法: Invalid status code: 403

### `happy`

- `L2_EXPLORE`：page=1 网络请求失败: code 2300999: Internal error
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a: 网络请求失败: code 2300999: Internal error
- `L2_SEARCH`：魔法: 网络请求失败: code 2300999: Internal error

### `shonen_jump_plus`

旧矩阵只有JSON '<'错误；后来的另一次手机日志在同Trace的POST后记录HTTP403再发生JSON错误。源token函数未检查status就JSON.parse。仅能说明那次观察到403 HTML，不能凭主机不同网络403就给旧矩阵定责，更不能证明具体WAF或排除请求适配。

**证据适用范围：** SDK code401 Parameter error不是HTTP401；真实令牌/账号/后续GraphQL路径未验证。

- 对照证据：[shonen_jump_plus.js](<../logs/user8-installed-scripts/shonen_jump_plus.js>)
- 对照证据：[user8-newbuild-startup-20261014.log](<../logs/user8-newbuild-startup-20261014.log>)
- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- `L2_EXPLORE`：page=1 SyntaxError: unexpected token: '<'
- `L2_SEARCH`：a: SyntaxError: unexpected token: '<'
- `L2_SEARCH`：魔法: SyntaxError: unexpected token: '<'

### `copy_manga`

- `L2_SEARCH`：魔法:p1=30 p2=30 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=270x348 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/31 decoded=991x1400 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=16/31 decoded=991x1400 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=31/31 decoded=991x1400 thumbnail=false modified=false；解码不等于真实内容人工验收

### `ManHuaGui`

- `L2_EXPLORE`：page=1 网络请求失败: code 2300028: Operation timeout
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a: 网络请求失败: code 2300028: Operation timeout
- `L2_SEARCH`：魔法: 网络请求失败: code 2300028: Operation timeout

### `manwaba`

- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：魔法: Invalid status code: 400, body: 
- `CHAIN_CANDIDATE`：搜索未通过，改用公开探索/分类候选独立测阅读链路；搜索失败状态仍保留
- `L2_DETAILS`：title=true cover=true author=false chapters=30
- `L3_IMAGE_FAIL`：cover Decode failed. e.g.,Decode image header failed.
- `L3_IMAGE_FAIL`：chapter=1 page=1 Decode failed. e.g.,Decode image header failed.

### `ikmmh`

- `L2_EXPLORE`：page=1 Error: 探索页面加载失败：加载探索页面失败，状态码：403
- `L2_CATEGORY`：undefined is not callable

### `jm`

- `L2_SEARCH`：魔法:p1=80 p2=80 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=400x533 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/62 decoded=720x3600 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=32/62 decoded=720x3600 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=62/62 decoded=720x1516 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=23 page=1/45 decoded=720x3008 thumbnail=false modified=true；解码不等于真实内容人工验收

### `wnacg`

已证明的是当前安装规则与手机返回的移动模板不匹配，不能直接说站点改版且应用无错。移植网络层给空headers注入Phone UA，固定原版app_dio使用VeneraNext/v1.17.0；这是已确认的请求契约迁移差异。已恢复源默认UA，当前同手机结果待新包公开探针核对。

**证据适用范围：** 276个selector同导出响应文本比较在lxml/生产HTML/实际主机NAPI一致；不代表原始wire字节、所有页面、所有UA/域名或详情阅读均通过。未自动覆盖安装源脚本。

- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 对照证据：[mobile-replay.json](<../tools/wnacg_html_reference/mobile-replay.json>)
- 对照证据：[phone-1.proof.json](<../tools/wnacg_html_reference/phone/phone-1.proof.json>)
- 对照证据：[app_dio-7110c19.dart](<../logs/upstream/app_dio-7110c19.dart>)
- `L2_CATEGORY`：undefined is not callable
- `L2_SEARCH`：a: TypeError: cannot read property 'text' of undefined
- `L2_SEARCH`：魔法: TypeError: cannot read property 'text' of undefined

## 下一步与尚未验证

- 未完成阶段继续独立复测；源内配置/真实账号需要用户设备操作，不在本报告伪造登录后结果。
- 页面选源、tag导航、loading/error、剪贴板、左右单击与正文到详情需另附当前签名包真机UI证据。
- 同源跨网络时点结果变化不是修复因果证明；“5变7”不能直接全部归功于迁移修复。
- 证据受原始响应、UA、域名、时间、源码版本和取样范围约束；后续更新应保留旧报告，不能改写历史原始记录。
