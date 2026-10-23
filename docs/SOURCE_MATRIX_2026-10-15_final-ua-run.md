# 逐源矩阵观察报告：原版UA修正包：手机20源完整遍历，公开阶段保留失败

原始设备证据：[deep-1792051137357.jsonl](<../logs/user8-device-matrix/deep-1792051137357.jsonl>)。这里只执行公开只读取样，不登录、不发布、不变更网络收藏。

## 完整性与判定边界

- 已输出源行：**20 / 20**；END标记：**有**；坏JSON行：**0**。
- 本轮遍历完整性：**完整遍历已列源**。
- 详情/章节/取样图片链路成功：**7**（允许来自探索/分类候选；不等于搜索通过）。
- 已观测L1/探索/实际分类目标/搜索/阅读链路取样均无失败：**4**。
- **L0仍为部分契约，L4/L5真实账号和站点专项未测。无一行可因此升格为全部功能PASS。**
- 旧“链路通过7个”忽略了nhentai/ykmh分类失败，也忽略Komiic的独立阅读链路；现将阶段分开展示。
- 只有错误关键词不是定责证据；HTTP403可能涉及我们的UA/请求适配，不能作为源坏或上游豁免。

## 全部源逐阶段观察

| 源 | L1 | 探索 | 分类（实际请求） | 搜索 | 阅读链路 | 观察分类/待定位 |
|---|---|---|---|---|---|---|
| `hcomic` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `komga` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | CONFIGURATION_REQUIRED_OBSERVED；观察到配置缺失；还需区分用户未配置与默认值迁移缺失 |
| `Komiic` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；安装源search.load虽然接收page参数，但只发送keyword变量且明确返回maxPage:1。这是有限的一次性搜索，不应强求第二页不同；此前矩阵的分页失败是验证器误判，已修正并加回归。最新手机run实际记录p1=100 declaredEnd=true，分类/探索/搜索与取样阅读链路成功。 |
| `manga_dex` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | FAIL_IMAGES_OR_CHAPTERS | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `picacg` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | LOGIN_REQUIRED_OBSERVED；源报告需要登录；未输入真实账号，不能验证登录后路径 |
| `comick` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | FAIL_OR_NEEDS_CONFIGURATION | FAIL_IMAGES_OR_CHAPTERS | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `ehentai` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_EMPTY_PARTS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；已复现迁移层未支持explore.loadNext和未填multi-select默认JSON值导致调用前失败；这些调用契约已修。新包不再出现相同错误，但0结果尚不能推定为登录问题。默认Phone UA也可能改变HTML，按原版UA复测后再归因。 |
| `hitomi` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL_TARGETS | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `nhentai` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；旧run阅读链路成功但分类FAIL_TARGETS，不能整体标为无公开失败；最新原版UA手机run分类实际目标成功，探索/两词取样/阅读链路成功。两轮网络时点不同，不能把所有变化直接算单项修复因果。 |
| `ykmh` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL_TARGETS | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；最新手机run分类phase=load报ReferenceError: temp is not defined。完整安装脚本的categoryComics.load第303行直接赋值未声明temp；标准Node VM与实际NAPI在清洁全局环境均发HTTP前复现，只有内存测试加入let后才到达模拟网络。这是可复现的源脚本变量缺陷，未改安装源；搜索/阅读链路成功不能掩盖该分类失败。 |
| `zaimanhua` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | FAIL_CHAIN | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `baozi` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `happy` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `shonen_jump_plus` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | NOT_APPLICABLE | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；旧矩阵只有JSON '<'错误；后来的另一次手机日志在同Trace的POST后记录HTTP403再发生JSON错误。源token函数未检查status就JSON.parse。仅能说明那次观察到403 HTML，不能凭主机不同网络403就给旧矩阵定责，更不能证明具体WAF或排除请求适配。 |
| `copy_manga` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | FAIL_CHAIN | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `ManHuaGui` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | TRANSPORT_OR_SDK_ERROR_OBSERVED；SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位 |
| `manwaba` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | FAIL_IMAGES_OR_CHAPTERS | HTTP_FAILURE_OBSERVED；观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点 |
| `ikmmh` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | FAIL_TARGETS | FAIL_OR_NEEDS_CONFIGURATION | BLOCKED_NO_PUBLIC_CANDIDATE | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `jm` | METADATA_OK | SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照 |
| `wnacg` | METADATA_OK | FAIL_OR_UNSUPPORTED_TYPE | PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE | TWO_KEYWORDS_SAMPLED_ONE_PASSED | SAMPLE_CHAIN_OK | UNDETERMINED；已确认迁移默认Phone UA与固定原版VeneraNext/v1.17.0不一致。恢复源UA后同手机公开200搜索返回24条桌面结构，真实UI搜索24→48、详情和121页正文1→2；最新20源run分类9个取样目标成功、两词前两页24/24且不同、阅读链路成功。探索首页仍空，不能宣称整个源全功能通过；旧源过期归因已撤回。 |

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
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load TypeError: Setting not found: default_username
- `L2_SEARCH`：a: TypeError: Setting not found: default_username
- `L2_SEARCH`：魔法: TypeError: Setting not found: default_username

### `Komiic`

安装源search.load虽然接收page参数，但只发送keyword变量且明确返回maxPage:1。这是有限的一次性搜索，不应强求第二页不同；此前矩阵的分页失败是验证器误判，已修正并加回归。最新手机run实际记录p1=100 declaredEnd=true，分类/探索/搜索与取样阅读链路成功。

**证据适用范围：** 不改写旧JSONL中different=false的历史观察；不能由源静态契约直接把新的手机搜索标成PASS。

- 对照证据：[Komiic.js](<../logs/user8-installed-scripts/Komiic.js>)
- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 对照证据：[deep_matrix_cases.js](<../tools/deep_matrix_cases.js>)
- `L3_IMAGE`：cover decoded=180x240 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/24 decoded=836x1200 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=13/24 decoded=836x1200 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=24/24 decoded=1000x1500 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=7 page=1/21 decoded=853x1200 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=7 page=11/21 decoded=853x1200 thumbnail=false modified=false；解码不等于真实内容人工验收

### `manga_dex`

- `L2_SEARCH`：a:p1=20 p2=20 cursorOnly=false different=true
- `L2_SEARCH`：魔法: Error: Network response was not ok
- `L3_IMAGE`：cover decoded=256x144 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/58 decoded=2304x3072 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=30/58 decoded=1438x2064 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=58/58 decoded=1438x2064 thumbnail=false modified=false；解码不等于真实内容人工验收

### `picacg`

- `L2_EXPLORE`：page=1 Not logged in
- `L2_EXPLORE`：page=2 Not logged in
- `L2_EXPLORE`：page=3 Not logged in
- `L2_EXPLORE`：page=4 Not logged in
- `L2_EXPLORE`：page=5 Not logged in
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load 网络请求失败: code 2300999: Internal error

### `comick`

- `L2_EXPLORE`：page=1 网络请求失败: code 2300999: Internal error
- `L2_SEARCH`：a: Invalid status code: 422
- `L2_SEARCH`：魔法: Invalid status code: 400
- `CHAIN_CANDIDATE`：搜索未通过，改用公开探索/分类候选独立测阅读链路；搜索失败状态仍保留
- `L3_IMAGE`：cover decoded=480x623 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE_FAIL`：chapter=1 page=1 图片HTTP 403

### `ehentai`

已复现迁移层未支持explore.loadNext和未填multi-select默认JSON值导致调用前失败；这些调用契约已修。新包不再出现相同错误，但0结果尚不能推定为登录问题。默认Phone UA也可能改变HTML，按原版UA复测后再归因。

**证据适用范围：** 单元控制HTTP证明的是调用契约修复，不等于真实EH账号/搜索/阅读通过。

- 对照证据：[ehentai.js](<../logs/user8-installed-scripts/ehentai.js>)
- 对照证据：[source_contract_ui_cases.js](<../tools/source_contract_ui_cases.js>)
- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 见上表阶段状态；不能以最后一条成功图片解码覆盖前面的失败。

### `hitomi`

- `L2_CATEGORY_TARGET_FAIL`：part=2 item=1 phase=load 网络请求失败: code 2300999: Internal error
- `L2_SEARCH`：a: 网络请求失败: code 2300999: Internal error
- `L2_SEARCH`：魔法:p1=25 p2=25 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=458x640 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/29 decoded=960x1342 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=15/29 decoded=960x1343 thumbnail=false modified=false；解码不等于真实内容人工验收

### `nhentai`

旧run阅读链路成功但分类FAIL_TARGETS，不能整体标为无公开失败；最新原版UA手机run分类实际目标成功，探索/两词取样/阅读链路成功。两轮网络时点不同，不能把所有变化直接算单项修复因果。

**证据适用范围：** 手机phase日志需重跑新包后确认是目标协议、动态选项、网络还是源错误。

- 对照证据：[deep-1792033074497.jsonl](<../logs/user8-device-matrix/deep-1792033074497.jsonl>)
- `L2_SEARCH`：a:p1=25 p2=25 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=25 p2=25 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=700x979 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/100 decoded=1280x1790 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=51/100 decoded=1280x1790 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=100/100 decoded=1280x1790 thumbnail=false modified=false；解码不等于真实内容人工验收

### `ykmh`

最新手机run分类phase=load报ReferenceError: temp is not defined。完整安装脚本的categoryComics.load第303行直接赋值未声明temp；标准Node VM与实际NAPI在清洁全局环境均发HTTP前复现，只有内存测试加入let后才到达模拟网络。这是可复现的源脚本变量缺陷，未改安装源；搜索/阅读链路成功不能掩盖该分类失败。

**证据适用范围：** 只记录观测结果，不凭异常字符串豁免迁移缺口。

- 对照证据：[deep-1792033074497.jsonl](<../logs/user8-device-matrix/deep-1792033074497.jsonl>)
- 对照证据：[ykmh.js](<../logs/user8-installed-scripts/ykmh.js>)
- 对照证据：[ykmh-category-attribution-20261015.json](<../logs/ykmh-category-attribution-20261015.json>)
- 对照证据：[ykmh_category_attribution_cases.js](<../tools/ykmh_category_attribution_cases.js>)
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load ReferenceError: temp is not defined
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load ReferenceError: temp is not defined
- `L2_SEARCH`：a:p1=36 p2=36 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=36 p2=36 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=328x422 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/48 decoded=1284x1826 thumbnail=false modified=false；解码不等于真实内容人工验收

### `zaimanhua`

- `L2_SEARCH`：a:p1=20 p2=20 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=20 p2=20 cursorOnly=false different=true
- `L3_ERROR`：Error: 漫画不存在或已被删除

### `baozi`

- `L2_EXPLORE`：page=1 Invalid status code: 403
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load Invalid status code: 403
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load Invalid status code: 403
- `L2_SEARCH`：a: Invalid status code: 403
- `L2_SEARCH`：魔法: Invalid status code: 403

### `happy`

- `L2_EXPLORE`：page=1 网络请求失败: code 2300999: Internal error
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load 网络请求失败: code 2300999: Internal error
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load 网络请求失败: code 2300999: Internal error
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
- `L3_ERROR`：Invalid status code: 210

### `ManHuaGui`

- `L2_EXPLORE`：page=1 网络请求失败: code 2300028: Operation timeout
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load 网络请求失败: code 2300028: Operation timeout
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load 网络请求失败: code 2300028: Operation timeout
- `L2_SEARCH`：a: 网络请求失败: code 2300028: Operation timeout
- `L2_SEARCH`：魔法: 网络请求失败: code 2300028: Operation timeout

### `manwaba`

- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load Invalid status code: 500, body: 服务器发生内部错误，请稍后再试或联系管理员。
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load Invalid status code: 500, body: 服务器发生内部错误，请稍后再试或联系管理员。
- `L2_SEARCH`：魔法: Invalid status code: 400, body: 
- `CHAIN_CANDIDATE`：搜索未通过，改用公开探索/分类候选独立测阅读链路；搜索失败状态仍保留
- `L2_DETAILS`：title=true cover=true author=false chapters=30
- `L3_IMAGE_FAIL`：cover Decode failed. e.g.,Decode image header failed.

### `ikmmh`

- `L2_EXPLORE`：page=1 Error: 探索页面加载失败：加载探索页面失败，状态码：403
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=1 phase=load Error: 分类加载失败：分类请求失败，状态码：403
- `L2_CATEGORY_TARGET_FAIL`：part=1 item=2 phase=load Error: 分类加载失败：分类请求失败，状态码：403
- `L2_CATEGORY_TARGET_FAIL`：part=2 item=1 phase=load Error: 分类加载失败：unexpected token: '<'
- `L2_CATEGORY_TARGET_FAIL`：part=2 item=2 phase=load Error: 分类加载失败：unexpected token: '<'

### `jm`

- `L2_SEARCH`：魔法:p1=80 p2=80 cursorOnly=false different=true
- `L3_IMAGE`：cover decoded=400x533 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/285 decoded=720x500 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=143/285 decoded=720x700 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=285/285 decoded=720x255 thumbnail=false modified=true；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=36 page=1/151 decoded=720x500 thumbnail=false modified=true；解码不等于真实内容人工验收

### `wnacg`

已确认迁移默认Phone UA与固定原版VeneraNext/v1.17.0不一致。恢复源UA后同手机公开200搜索返回24条桌面结构，真实UI搜索24→48、详情和121页正文1→2；最新20源run分类9个取样目标成功、两词前两页24/24且不同、阅读链路成功。探索首页仍空，不能宣称整个源全功能通过；旧源过期归因已撤回。

**证据适用范围：** 276个selector同导出响应文本比较在lxml/生产HTML/实际主机NAPI一致；不代表原始wire字节、所有页面、所有UA/域名或详情阅读均通过。未自动覆盖安装源脚本。

- 对照证据：[MOBILE_ATTRIBUTION.md](<../tools/wnacg_html_reference/MOBILE_ATTRIBUTION.md>)
- 对照证据：[mobile-replay.json](<../tools/wnacg_html_reference/mobile-replay.json>)
- 对照证据：[phone-1.proof.json](<../tools/wnacg_html_reference/phone/phone-1.proof.json>)
- 对照证据：[app_dio-7110c19.dart](<../logs/upstream/app_dio-7110c19.dart>)
- 对照证据：[phone-1.proof.json](<../tools/wnacg_html_reference/phone-upstream-ua/phone-1.proof.json>)
- 对照证据：[verified-ui-evidence-20261015.json](<../logs/user8-ui/verified-ui-evidence-20261015.json>)
- `L2_SEARCH`：a:p1=24 p2=24 cursorOnly=false different=true
- `L2_SEARCH`：魔法:p1=24 p2=24 cursorOnly=false different=true
- `L2_DETAILS`：title=true cover=true author=false chapters=0
- `L3_IMAGE`：cover decoded=300x400 thumbnail=true modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=1/66 decoded=768x1024 thumbnail=false modified=false；解码不等于真实内容人工验收
- `L3_IMAGE`：chapter=1 page=34/66 decoded=1024x1024 thumbnail=false modified=false；解码不等于真实内容人工验收

## 内建本地源（与20个远程脚本分列）

- SourceManager另注册LocalSource；不在SourceDao安装脚本表中，因此不出现在上述20个ROW。
- 本地导入/目录持久化/本地图片阅读不由远程矩阵覆盖；当前签名包未重新逐项验收，状态NOT_TESTED_CURRENT_PACKAGE。
- 设置页21个源=20个安装脚本+1个内建本地源；不能把本地源静默算通过，也不能把它当第21个联网源。

## 下一步与尚未验证

- 未完成阶段继续独立复测；源内配置/真实账号需要用户设备操作，不在本报告伪造登录后结果。
- 页面选源、tag导航、loading/error、剪贴板、左右单击与正文到详情需另附当前签名包真机UI证据。
- 同源跨网络时点结果变化不是修复因果证明；“5变7”不能直接全部归功于迁移修复。
- 证据受原始响应、UA、域名、时间、源码版本和取样范围约束；后续更新应保留旧报告，不能改写历史原始记录。
