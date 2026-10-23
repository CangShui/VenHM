# Venera HM 交接文档：环境 + 继续任务

> 目的：任何人（或下一轮的我）读完这份文档就能接着干，不用重新摸索环境、不用重跑一遍踩坑。
> 最后核对：2026-10-23（Legado-E默认九宫格交互适配）。**用户已授权学习并部署；代码、54套回归和SDK完成。用户确认重连授权后，新包已成功覆盖安装；保留数据，未启动/截图/点击，用户自行测试。**

## 2026-10-23 最新：参考Legado-E交互，不复制UI

[完整合同/证据/待安装说明](<LEGADO_READER_INTERACTION_20261023.md>)。固定参考提交8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c，读取实际AppConfig/ReadView/ReadMenu与布局，不凭印象猜规则。
默认整阅读窗口九宫格：上排“上一/上一/下一”；中排“上一/菜单/下一”；下排“上一/下一/下一”。**进入正文菜单隐藏**（覆盖下方上一版本的“进入显示”规则），中心唤出，菜单外点模态消费只关闭，不串发翻页，不设空闲自动收起。原UI风格保留，连续长图按屏滚动，RTL/反转适配，页级上一章去末图/末屏，章节按钮仍保留原到首图语义。

本轮还修了真实平台模型：Up的touches可能仍有释放指，按changedTouches.id排除；原生双击通过通知明确取消父候选，60vp空间阈值和350ms仲裁；按住期间章节/缩放/窗口变更会取消接触；菜单打开不让音量键背后翻页；菜单仅暂停自动阅读，关闭恢复原运行意图。

[新门禁](<../tools/run_legado_reader_local.ps1>)退出0，54套完整回归及负向对照通过，含[43项正文交互/平台触点模型](<../logs/legado-interaction-20261023/reader-cases.json>)。[SDK最终构建](<../logs/legado-interaction-20261023/sdk-build-final.log>)退出0（仍有原有警告）。[范围守卫](<../logs/legado-interaction-20261023/scope-result.json>)确认58个非交互阅读方法、18个共享图片方法、99个既有后端/配置文件受保护；autoStep/key仅允许菜单可见性门禁。历史守卫不得覆盖重录。

待装包：[Legado交互版本](<../dist/reader-legado-interaction-20261023-signed.hap>)，SHA256 `5122ED52F5C9815470D4BF273B50777D4D3DE3C43CC083DB1FE4B82BA2BC201A`，8,214,155字节。设备<device-id>重新在线后校验哈希再使用[覆盖安装脚本](<../tools/install_verified.ps1>)；必须有明确install bundle successfully，绝不把退出0/空设备当成功。HDC初次两次为空时未盲目安装；用户随后确认重连授权，设备与哈希匹配后[覆盖安装证据](<../logs/legado-reader-user-install-20261023.log>)明确成功。**本次新包已覆盖安装，未卸载/清数据/启动/截图/点击，不宣称功能实机验收。** 当前手机应是本次5122ED52版本，而不是下面旧reader-immersive版本。

以下为历史记录，旧交互规则和安装状态不覆盖本段。

## 2026-10-21 最新：全局图标尺寸与单一下方阅读浮层

详见[本轮实现与证据](<READER_IMMERSIVE_ICONS_20261021.md>)。
图标从Shape/Path改为24个明确viewBox的本地SVG+原生Image/Contain+内外固定方框，保留name/color/iconSize接口、16..72vp有效边界和44/46vp外部触摸区，着色使用保留alpha的ColorFilter矩阵。

Reader正文为独立全屏画布，只剩下方弹出浮层：进入显示，任意已就绪图片点击先收起且不翻页，隐藏后点击可见窗口正中唤出。边缘翻页、RTL/多图、双击/捏合缩放保留。慢图不阻止菜单显隐但仍阻止错误翻页，自动滚动可点中部停止并唤出菜单。目录外点击可收起，菜单不占正文布局，也不重置图片身份。阅读器实例拥有窗口沉浸租约，隐藏/退出恢复，晚到操作有串行/代际保护。

[本地门禁](<../tools/run_reader_immersive_local.ps1>)已通过54套完整回归及原有负向对照，含图标16项、阅读交互25项、窗口18项；[最终SDK构建](<../logs/reader-immersive-20261021/sdk-build-final2.log>)退出0。[范围守卫](<../logs/reader-immersive-20261021/scope-result.json>)确认56个非UI阅读方法与99个既有后端/配置文件不变。
本次明确授权改变Reader的UI生命周期/单击行为及图片单击坐标交付，所以不能把下方上一轮“所有非Builder方法完全不变”的历史结论直接用于当前Reader；本轮用精确允许范围守卫，其他既有页面方法仍冻结。

**未实机验证**原生图标像素、系统栏/安全区、真实手势与机型表现。SDK没有精确可见系统栏getter，旧栏状态以isFullScreen/避让区域推断，特殊系统瞬态不能保证精确；不得宣称手机已验收。仅本地归档包：[reader-immersive版本](<../dist/reader-immersive-20261021-signed.hap>)。

以下为上一轮风格改造历史记录。

## 2026-10-21：参考图风格的纯 UI 改造已本地完成

详见[前端改造记录](<UI_REFRESH_20261021.md>)。统一浅灰画布/白色24vp圆角卡/大标题/柔色矢量图标/悬浮导航，重排设置、书架、搜索/探索/分类、详情、下载/缓存/收藏及辅助页；拥挤操作区换行，危险按钮不再与主按钮同为大蓝色。阅读器只改三个工具Builder，正文/手势/复用不动。

施工前后[守卫](<../tools/ui_refresh_guard.js>)确认99个受保护后端/配置文件字节一致，既有非UI方法及路由保留。12个原文快照页面字段/非渲染回调一致。[本地门禁](<../tools/run_ui_refresh_local.ps1>)通过13项UI专项、51套既有回归与负向对照；[最终SDK构建](<../logs/ui-refresh-20261021/sdk-build3.log>)退出0。

[设计预览](<../logs/ui-refresh-20261021/design-overview.png>)仅用于视觉审阅，**不是ArkUI/实机截图**。320/390/768与窄屏放大字体共12个设计布局检查通过；真实字体/系统安全区/键盘/手感待以后用户安排。包已本地归档，**未安装**。本次没有修改源、下载队列、缓存实现、数据库、模型或系统生命周期。

下方2026-10-17功能改动及其安装状态属于历史记录，不得据此安装本次UI包。

## 2026-10-17 本轮：图标、分享原站地址、下载并发、缓存体系

详见[本轮记录](<ROUND_ICON_SHARE_DOWNLOAD_CACHE_20261017.md>)。

- **图标**：取上游 `venera-app/venera` 的 `assets/app_icon.png`（1024）作前景/启动图标，背景用其自适应图标的纯蓝 `(33,67,243)`；
  原图备份 `logs/icon-source/original/`。**包名保持 `com.venerahm.reader`**（用户选择不改）。
- **分享**：上游 `share()` 就是 `title + comic.url`；问题在于多数源不返回 url。现三级回退：
  源 URL → 绝对漫画 id → 源站点域名，始终指向原网站，危险候选仍拒绝。
- **下载**：`MAX_CONCURRENT_TASKS=3` 多任务（第4个排队）、`PAGE_WORKERS=3` 章内并行、
  真实 `Progress` 进度条；检查点严格保持**连续已校验前缀**（乱序完成不跳页）。后台租约仍只有一个，其余走前台并在退后台时暂停。
- **缓存**：新增 `CacheStore`（记账+LRU+默认1GiB上限+原子索引+损坏重建）、`CacheSettingsPage`（上限选择/清除，明确不删下载与历史）；
  详情缓存接在**源层**缓存原始 JSON（解析后模型含 Map 会丢字段），页面先用缓存秒开再刷新，刷新失败保留缓存并提示。

验证：**51 套 + 2 项负向对照通过**；真实 SDK 编译退出 0（`logs/round-icons-downloads-cache-build1.log`，已确认对应最新源码）。
关键证据：`details_cache_cases.js` 用真实源适配器模拟两次启动，第二次详情命中且**脚本调用为 0**，随后刷新仍恰好调用一次。
**未安装、未实机**：进度条渲染、真机并发/内存、三路并行解码、设置页交互均未上机。缓存无 TTL；Cookie 参与图片身份（有意不弱化）。

## 2026-10-17 本地测试环境强化

用户要求“把本地测试环境推进到极致”。结论与新增能力：

- 实测 DevEco `Previewer.exe`（PC 端真实 ArkUI 引擎）可启动并产出渲染帧，但页面仍走旧 JS 前端；
  它依赖 IDE 命名管道驱动的 preview 变体，且本应用页面在 `AppInit` 阶段就需要数据库/文件/网络/native 源引擎，
  预览器无法提供，故未继续逆向。像素观感/手势/帧率仍须实机。
- 新增 `tools/ui_contract_cases.js`（12 项界面契约）：注册页面与 `@Entry` 一致、**所有路由目标已注册且文件存在**、
  无残留已删页面引用、聚合在源下拉框且无独立按钮、搜索/探索/分类共用 `SelectedSource`、
  不静默换源、聚合无并发上限且局部渲染、后台用 `LIVE_VIEW` 子模式无盲停、前台降级、代际与旧 runner 等待、无 TODO 页面。
- 新增 `tools/ui_contract_negative.js`：构造坏路由项目，断言检查器退出 1 并报出未注册路由——证明不是空跑。
- `run_local_search_download_regression.ps1` 现覆盖 **47 套 + 2 项负向对照**，逐套独立进程/超时/退出码/完成摘要。

安装状态：本地包已覆盖安装成功并启动（PID 59580），但随后设备掉线，**界面点验未完成**，需重新连接设备后继续。

> 此前 2026-10-17 记录：用户曾要求先只本地测试，禁止安装/启动/操作手机。

## 2026-10-17：只在本地修正共享选源、同页聚合与9800005

以[本地修复与测试记录](<LOCAL_SEARCH_DOWNLOAD_20261017.md>)为当前状态：搜索/探索/分类共同服务SelectedSource稳定键，搜索下拉包含聚合模式且已去掉独立按钮/页面和3源并发上限；真实源不支持搜索或已移除时不自动换源。用户在另两页重新选择同一个真实源也会使搜索退出聚合跟随该选择。

撤回“9800005证明旧后台任务残留”的归因和盲停/重试方案：API21 DATA_TRANSFER须配LIVE_VIEW子模式；后台拒绝保持错误可见、允许前台下载、退后台暂停。只停止精确已知自有nativeID，不以无ID方式停止其他原生工作。

下载旧测试存在永不结算Promise导致Node提前exit0、剩余用例未跑的假通过问题，已修复。当前搜索25项、后台/队列27项完整完成；本地完整46套均要求退出码/超时/完成摘要，另有2项负向看门狗控制。SDK本地编译通过。**本轮新修补未安装，不能宣称手机9800005消失或后台授权已通过。**

下文2026-10-16等状态是历史快照；其中“聚合3并发/独立窗口”“全部回归通过”等不得替代以上当前合同与完成性检查。历史快照也不能替代最新包真机验收；“WNACG一定源过期/与移植无关”和“Komiic分页坏了”的旧结论已撤回。

## 2026-10-16 第二轮：用户点名的通用功能已实现并本地验证（未安装）

按用户清单完成：聚合搜索（分源并发上限3、独立重试、更多跳原源分页）、搜索历史（持久化/删除/清空）、
详情缩略图（含EH雪碧裁剪）/评论（回复/点赞/投票按声明与用户动作）/系统分享/封面查看器（捏合拖动翻页）、
网络收藏（含4参数源删除安全拒绝）、图片收藏、追更（手动只读、首次建基线）、
阅读器音量键（前台inputConsumer，隐藏即释放）/手势策略/连续模式真实滚动/阅读统计（增量分段去重）、
后台下载（DATA_TRANSFER常驻任务+代际取消+重启/删除/暂停/继续，通知只开列表不自动恢复）。
详见[本轮合同与验证](<BROAD_FEATURES_20261016.md>)。

验证：[45组JS+Python报告/历史手机记录断言](<../logs/broad-features-regression2-20261016.log>)全部通过；
[真实SDK/API21签名构建](<../logs/broad-features-compile3-20261016.log>)退出0；
[签名包](<../dist/broad-features-20261016-signed.hap>) SHA256 `7F8CE9659F9C56AF06A80A516DF69087B7EE086DBCCF0264E99D474B7812FB9E`。
**本轮未安装、未占手机、未输入账号、未访问真实站点**；分享选择器/真实后台授权/真实音量键/跨进程重启仍需真机。
探索“更多”UI、聚合源管理、评论富文本、封面导出未做。此前JM阅读修复仍待长章节与真实帧率专项验收。

## 2026-10-16 最新：继续补通用搜索筛选与分类排行榜，不只修绅士源

用户要求继续完整迁移，当前已实现两条原版通用链路，详见[合同与验证](<DISCOVERY_SEARCH_RANKING_20261016.md>)。
搜索界面支持源optionList的select/multi-select/dropdown、动态读取、默认值、重置、错误/重试；SearchSession保存不可变选项快照，页码和游标分页不再传空选项，切源/改筛选隔离旧结果。
分类页支持enableRankingPage与空parts的rank-only源，排行用稳定sourceKey锁定源，load优先/loadWithNext首null、选项切换、分页/循环游标终止、重试保留状态及正确源详情路由。

验证：搜索生产方法12+实际主机NAPI5；排行生产方法15+实际主机NAPI6（完整未修改WN/EH/Komiic源与生产注册适配链路，所有HTTP为内存桩）。
[全量回归](<../logs/search-ranking-regression-20261016.log>)40组JS+Python报告/历史手机记录断言通过；
[真实SDK签名构建](<../logs/discovery-search-ranking-build-20261016.log>)退出0。
[新包](<../dist/search-ranking-20261016-signed.hap>) SHA256 `14E1E03B04BA9DD770319598BEA9B655BCCF370AF432F1B1489A2308EB98E3A5`。
**未自动安装、未占手机、未输入账号，不拿历史手机点验替新增功能背书。**

此前JM阅读白屏/卡顿修补已覆盖安装并确认首屏；[本地修补记录](<READER_LOCAL_FIX_20261015.md>)中的长章节/实际帧率仍未专项实机验证。
完整目标未完成；搜索历史/聚合/标签建议与翻译、发现分区/更多、详情评论/缩略图/分享、网络收藏/追更、导入后台下载与完整同步继续是待做项。

## 2026-10-15 最新：真机21项点验、修正源请求UA、保留失败不夸大通过

详见 [8项缺陷真机点验与归因纠正](<USER8_DEVICE_REVIEW_20261015.md>)；
[真实UI证据与哈希](<../logs/user8-ui/verified-ui-evidence-20261015.json>)可由
[记录断言脚本](<../tools/user8_ui_evidence.py>)复核。已实际验证选源共享、详情标签进入原源结果、
真实分类loading→失败/重试、正文侧边1→2→1/中央不动、标题/作者/tag长按、系统粘贴标题读回、
首页继续阅读→正文→详情→首页无循环，以及设置无演示API。未穷举RTL/多图/纵向/双指和每个站点标签。

**WNACG请求模板差异是迁移问题，不能怪用户或源**：固定原版默认UA是`VeneraNext/v1.17.0`，
移植层却注入Phone浏览器UA。独立lxml/生产HTML/实际主机NAPI276项对照证明移动模板真实存在而旧selector不命中，
但不证明全站改版。现在已恢复源请求默认UA且尊重源显式UA；未改WebView全局UA或安装源脚本。
同手机无Cookie原版UA探针得到桌面搜索`p.result > b`=2、列表24；随后真实UI搜索24→48、详情与121页正文、单击1→2。
WN探索首页仍空，不能把搜索/阅读恢复说成全部源完整可用。公开探针证据见
[请求UA/响应charset证明](<../tools/wnacg_html_reference/phone-upstream-ua/phone-1.proof.json>)。

**矩阵纠错**：Komiic脚本明确maxPage1，仅一次请求；不应制造第二页并判迁移分页失败。
分类现在按目标独立捕获、记录part/item/phase并继续其他part；无公开失败判定纳入分类。
不凭`not a function`/JSON/401字串定责；HTTP失败、SDK码、登录/设置要求只记观察。
[旧完整run逐阶段复核](<SOURCE_MATRIX_2026-10-15_reviewed.md>)实际为20行/END完整、阅读链路8、各公开取样阶段均未见失败5；
原“通过7”不是全功能通过。原版UA包独立run `deep-1792051137357` 已完成20行+END，
[最终逐阶段报告](<SOURCE_MATRIX_2026-10-15_final-ua-run.md>)给出阅读链路7、公开取样阶段未观察失败4，不是全功能通过；另单列内建本地源当前包未重测。
WN探索首页仍空；ykmh分类phase=load的temp未声明，已用[标准JS和实际NAPI完整源对照](<../logs/ykmh-category-attribution-20261015.json>)复现，未改安装源。

**最新包与验证**：
[SDK直接构建](<../logs/user8-reviewed-direct-hvigor-20261015.log>)真实退出0；
[覆盖安装](<../logs/user8-reviewed-install-20261015.log>)明确install bundle successfully；
[签名包](<../dist/venera-hm-user8-reviewed-20261015-signed.hap>) SHA256
`A7AE48C4A29AC6ECEB7C40CB752B279B1170E3D05C425EE35361FE095324EAE6`。
[32组JS+Python报告契约回归](<../logs/user8-reviewed-regression-20261015.log>)通过；
其中矩阵20、tag/复制22、RPC/UA7、实际主机NAPI分类3。CLI封装挂住后已取消，**未把被取消wrapper当exit0**，SDK直构建另证。
设备曾锁屏10106102，未自动解锁/改开发者模式；用户手动打开后已继续真实测试。

最后又修掉“一关键词成功掩盖另一词请求失败”的汇总问题（`PARTIAL_KEYWORD_REQUEST_FAILURE`），
[最终签名包2](<../dist/venera-hm-user8-reviewed2-20261015-signed.hap>) SHA256
`99C5CBBF8CB28C5642011CF59FFA07E20164C3878F5857B543D96AC5214A6684` 已覆盖安装。
[SDK构建2](<../logs/user8-reviewed-direct-hvigor2-retry-20261015.log>)真实退出0、
[安装2](<../logs/user8-reviewed-install2-20261015.log>)正文成功；仅改变验证器汇总，不变UA和交互，**不把包1手机矩阵伪装成包2重新跑过**。
[最终回归](<../logs/user8-final-regression-20261015.log>)33组JS+Python报告契约+真实手机记录21项断言通过。
完整迁移未完成。下一步：WN探索首页、EH空列表、manwaba响应解码与新包错误UI，再继续RTL/多指/旋转等边界及完整parity缺项。

## 2026-10-14 用户报告的8项缺陷（历史记录，下述归因/未验状态以2026-10-15最新段为准）

用户已授权公开请求真机前台验证（不输入真实账号、不卸载、不清数据）。本轮先修代码，再真机复测；
**真机矩阵跑到一半设备从 HDC 消失（list targets 为空），最终逐源报告尚未完成**，不冒充全源通过。

### 本轮真机实测通过（新包启动契约，实机执行）

新包冷启动后应用自身日志确认下列契约**在设备上真实执行**：
`bridge contracts OK`、`native trace contracts OK`、`HTML live-document/Unicode contracts OK`、
`rdb store ready`、`cookie contracts OK`，以及两条此前从未真机验收的：
- `compute验收返回 PASS`：源 compute 原生入口/并发/主引擎隔离/HTML/同步+异步主机RPC/Map+Set/子视图/异常恢复；
- `隔离像素验收返回 PASS`：2×3 真实原生 RGBA 旋转、匹配 Trace 取消、无关 Trace 继续成功。
证据：`logs/user8-newbuild-appdev-20261014.log`（设备 files/logs 导出）、`logs/user8-newbuild-startup-20261014.log`。
**这不等于真实 ImageKit 编解码/真实站点/JM 内容人工验收**。

### 8项缺陷的代码状态（逐项，含证据与未验边界）

1. **探索/分类共用选源**：新增 `features/SelectedSource.ets` 单例（持久化稳定 sourceKey、订阅/退订、
   ALL 已安装源而非按能力过滤的下标），ExploreView/CategoryView 都用它；能力不匹配时显式提示“所选源不支持”，
   不再静默换源或重置选择。本地21项 `category_tag_cases` 覆盖持久化/跨页共享/不可用源。**真机UI未验**。
2. **详情tag点击跳转**：新增 `features/TagRouting.ets` 与 `pages/CategoryComicsPage.ets`。
   按固定上游 `PageJumpTarget.parse` 支持现代 `{page,attributes}` 与 legacy `{action,keyword,param}`/字符串形式；
   命名空间与含冒号标签不被拆分丢失；源 `comic.onClickTag` 缺失时回退为**原源命名空间搜索**，绝不猜分类名。
   E-Hentai `Category` 标签返回 `keyword:''`+`options:['2','','']` 的过滤目标已专门修好（空关键词仅在有筛选时允许）。
   `ComicSource` 新增 `tagTarget`/`CategoryComicsData.optionsLoader`/`showWhen`/`notShowWhen`/`CategoryItem.initialOptions`，
   `JsComicSource` 已按原版解析这些字段（含动态/随机分类loader与空option key）。本地21+11项通过。**真机点击未验**。
3. **全部源全流程验证与逐源归因**：**本轮新包已在真机跑完全部20源**，逐源报告见
   [SOURCE_MATRIX_2026-10-15_newbuild.md](SOURCE_MATRIX_2026-10-15_newbuild.md)
   （`tools/source_matrix_report.py` 从设备导出的 JSONL 生成，可复现）。
   结果：**取样链路通过 7**（hcomic/manga_dex/hitomi/nhentai/ykmh/copy_manga/jm，比上一轮多 2）；
   分类阶段多数源已出现 `PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE`（真实发起分类请求）；
   Komiic 到 chapter3/page21 解码 1000×1333、comick 到 chapter30/page97（图片403）、manwaba 到 chapter23/page29。
   **绅士漫画 wnacg 已决定性归因**：手机无 Cookie 公开抓取到 3 份 **HTTP 200**（本机同 URL 为 403），
   用**独立解析器**对同一份字节解析，`p.result > b` 与结果列表均为 **0**，而页面确实是真实搜索结果页
   （可见“同人誌 4623 中文 11426”）→ 站点已弃用 `gallary_wrap`/`cc` 旧标记，
   **不是本工程解析引擎错误，而是源脚本选择器过期**；脚本又对空结果直接取 `[0].text`，才抛 TypeError。
   其余归因：`C_SITE_AUTH_OR_NETWORK_BLOCK`（komga 缺配置、picacg 未登录、baozi/comick/ManHuaGui/manwaba/ikmmh/happy 403/400/超时）、
   `B_NEEDS_UPSTREAM_COMPARISON`（Komiic 分页、zaimanhua 取样到已删除漫画、shonen_jump_plus 非JSON正文）、
   `UNDETERMINED`（ehentai 0结果需登录或换词）。**这不是“全部源跑通”**。
   上一轮构建的对照报告见 [SOURCE_MATRIX_2026-10-14.md](SOURCE_MATRIX_2026-10-14.md)（通过5）。
4. **分类tag无加载动画/无报错**：CategoryView 与新的 CategoryComicsPage 都改为进入即同步置 loading、
   只在当前请求的 finally 结束；能力缺失/抛异常/空数据/目标类型未迁移都产生**可见错误+重试**并写脱敏审计，
   不再静默空白。**真机视觉未验**。
5. **图片左右单击翻页**：新增 `features/ReaderTapPolicy.ets` + ReaderPage/ComicWidgets 接入。
   图片本地左右各30%为翻页区、中间不动作；RTL 左=下一张、右=上一张，其他模式（含纵向）按用户要求
   左=上一张、右=下一张；整屏归一化坐标避免多图一屏时误判；200ms 单击/双击仲裁，拖动/双指/取消/重载/
   退出/缩放/加载/隐藏/滚动/目录浮层/未就绪都会取消待定单击；`enableTapToTurnPages`/`reverseTapToTurnPages`
   已进分层设置。本地15项 `reader_tap_policy_cases` 通过。**真机手势未验**。
6. **详情长按复制**：标题/作者等元数据与标签支持长按写入系统剪贴板（完整字符串，不截断）；
   标签用互斥的 LongPress/Tap 识别器，长按复制不会同时触发跳转。本地用例覆盖真实剪贴板调用与手势互斥。
   **真机剪贴板未验**。
7. **正文可回详情**：阅读器新增“详情”入口，先停自动阅读、落盘进度、恢复亮度/亮屏策略；
   若上一路由就是同一 source+comic 的详情页则 `back`，否则用稳定参数 `replaceUrl` 到详情，避免
   “首页→阅读→详情→阅读”循环。普通返回键行为不变。本地15项覆盖匹配/不匹配/失败恢复。**真机未验**。
8. **删除演示API**：删除 `source/DemoApiSource.ets`、`SourceManager` 注册、设置页“演示源 API 地址”全部控件、
   `Settings.apiBaseUrl/demoApiBaseUrl` 接口；不触碰任何已安装真实源、历史、收藏或账号数据。
   本地用例断言文件与引用均不存在。**已随新包构建通过**。

### 本轮自己发现并修掉的“验证器自身制造失败”

新包矩阵暴露出两个由我引入的缺陷，已修并加回归，避免把工具问题算成源问题：
- 分类阶段抛出异常会中断该源后续搜索/链路并把它写成 `FAIL`；现改为**每个阶段独立 try/catch**，
  单阶段异常不再抹掉其他阶段状态，也不会阻塞阅读链路验证。
- 公开HTML诊断未设超时，遇到站点拦截会长时间拖住矩阵（曾报 `code 2300028 Operation timeout`）；
  现限定 8s 连接/12s 读取且遇 403 即停。

### 构建与安装证据（本轮）

- `logs/user8-build1-20261014.log`、`logs/user8-build2-20261014.log`、`logs/user8-build3-20261015.log`
  均 `BUILD SUCCESSFUL`（exit 0）。
- 覆盖安装：`logs/user8-install1-20261014.log`、`logs/user8-install2-20261014.log`、`logs/user8-install3-20261015.log`
  正文均为 `install bundle successfully`；`tools/install_verified.ps1` 双重校验退出码与正文，
  并修掉了“PowerShell 未设置 `$LASTEXITCODE` 时把已验证安装误判为失败”的封装缺陷。
- 本地回归 **31组全部通过**：`logs/user8-regression-20261014.log`（含本轮新增
  `source_contract_ui_cases` 11项、`reader_tap_policy_cases` 15项、`category_tag_cases` 21项）。
- 新增 `tools/summarize_matrix.py`（逐源汇总）、`tools/source_matrix_report.py`（逐源归因报告生成）、
  `tools/wait_user8_run.ps1`（按 runId 等待矩阵真正结束，避免被历史日志误导）。
- **设备本轮曾两次从 HDC 消失**；重连后由用户把 Venera 切到前台，矩阵才跑完。
  设备前台被其他应用占用时**不抢占**，改为询问用户后继续。
- **尚未真机验收**：8项缺陷中的界面/手势/剪贴板/路由细节（共用选源切换、tag点击、分类加载动画与报错、
  左右单击翻页、长按复制、正文→详情入口）以及 demo 删除后的界面观感，需要下一轮在设备前台逐项点验。

## 2026-10-14 阅读器画廊分组、宽图展示与分层设置（上一轮，reader-layout build3已覆盖安装）

完整迁移继续，不把功能清单缩小为编译/模拟测试。此轮对照固定原版reader/appdata，沿用已实现的后台图片脚本管线，
落实实际阅读器交互与设置；遵守用户**只覆盖安装、暂不占手机前台**的选择。

### 对照原版后的两种能力，不混为“把一张图片变成两页”

- **画廊多图一屏**：[ReaderSpreads.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/features/ReaderSpreads.ets>)
  对照原版GalleryModeState：横竖屏独立1–5图、首图可单独、末组不满补齐映射、RTL反转group与组内visual order。
  映射/nextSource/pagecounter O(1)，create O(n)，不在每次paint中反复构建全章导致O(n²)。
  [ReaderPage.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/pages/ReaderPage.ets>)
  实际Row/Column显示同屏多图；按钮/自动阅读进入下一**组**，不是只在当前同屏图内重复递增。
- **纵向宽图拆分显示**：原版只在continuousTopToBottom/waterfallTopToBottom使用，width>height严格判定；
  默认右半在上/左半在下，可交换；仍是**一个源图页**，不是新增逻辑页。
  [ReaderImageLayout.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/features/ReaderImageLayout.ets>)
  保留width/2与height×2的显示比例、奇数像素宽度的fractional中心边界。
  [ComicWidgets.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/components/ComicWidgets.ets>)
  使用同一PixelMap的两层200%纹理、percentage offset与clip；**没有额外crop/copy/PNG/RGBA分配，没有第二次HTTP/source hook**。
  source modifyImage的CPU像素工作仍在上一轮native worker；本次split是原版式视觉布局而非CPU改图。
  GPU采样/percent定位/奇数边界实际渲染**仍需手机验证**，不能拿纯几何断言冒充Canvas像素等价。
- gallery/横屏流不错误拆分；源URL、epId、images/maxPage、下载文件数量与cache identity均不制造synthetic half URL。
  横竖屏/设置重排保持原source index；同group初始callback不把恢复的页改成group start。
  进入不同group存储canonical source start，继续使用真实源页身份。

### 实际生效的设置、竞态与自动阅读保护

- [ReaderSettings.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/foundation/ReaderSettings.ets>)
  global→device→comic覆盖，false/0不丢；comic readerModeOverride独立于其他选项enabled，显式default回到device/global。
  deviceKey为本地随机持久化偏好标识，不读取硬件ID；源/漫画组合identity编码避免冒号碰撞。
  已实现项：模式、portrait/landscape每屏数、首图单屏、split/invert、每侧margin0–30%、自动页间隔1–20秒、
  跨章节开关、doubleTap开关、页动画。旧HM readerMode与显式1–60秒autoReadIntervalSeconds保留，直到用户改新canonical项。
- [ReaderSettingsPage.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/pages/ReaderSettingsPage.ets>)
  已注册真实route，全局设置/reader工具条均可进入，只有primitive sourceKey/comicId route参数。
  各层预览不被更低层覆盖误导；未启用device/comic普通选项禁用，comic模式独立可设。
  有序await put/flush，**确认落盘后**才发布设置与提示；失败保留最后confirmed memory并best-effort恢复偏好值，不伪造Saved。
  active层选择也在ordered commit中完成，避免enable与setActive并发写错层。损坏/未来版本记录明确拒绝，不自动清用户设置。
- parent zoom/readiness按actual image + rendergeneration汇总：一个gallery兄弟reset不能误解锁另一个仍zoomed的图。
  **自动阅读等待整组visible图解码就绪**，纵向等待当前源图；hidden/stale其它图不能解锁。
  cached flow图片的@Watch就绪通知延后到prop更新完成，并用requestVersion/zoomReset/readinessVersion丢弃过期通知，
  不靠remount所有flow图片制造重复POST/source callback。
  hide停止自动阅读但保留合理的解码就绪，show同设置不永久卡住；network/loading/scrolling/layoutpending/zoom期间不自动前进。
- 纵向margin按每侧百分比限制flow宽度，late natural-size回调重对齐相同source image；用户正在scroll/touch时不强行抢回。
  该锚点是**源图片顶端**，不是原版所有sub-image pixel scroll offset/跨章waterfall行为。

### 本轮证据与包

- 固定commit **7110c19c4f3e342cf33d358d6be9058d8abc2505**的23份reader/settings/appdata引用均匹配官方Git blob SHA1：
  [upstream audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-upstream-audit-20261014.json>)。
  数据参考保存在logs/upstream，不执行上游脚本。
- 本地 **28组全部PASS**：[regression](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-layout-regression-20261014.log>)。
  本轮新增/扩大：reader spread **575**、scoped settings **14**、wide geometry/source contracts **10**、component lifecycle **7**；
  reader controls10、history75与其余原回归重跑。Preferences/ArkUI/PixelMap是隔离fake的部分明确标注，**不是手机视觉与持久化验收**。
- 同一生产NAPI addon再跑 **21项真实Node NAPI/TSFN/GC/worker通过**：
  [native integration](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/napi-host/integration.log>)。
  此轮C/C++未改，不重复把前轮native26/isolated82/Trace37/codec17升格手机证明。
- **reader-layout最终build3签名构建exit0 PASS**：
  [build](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-layout-build3-20261014.log>)。
  build1的两项ArkTS类型/组件enabled名字冲突已修；build2验证通过后又补active scope race/readiness watcher guards，build3为最终代码。
  [稳定签名包](<C:/Users/<user>/Desktop/dev/Venera-HM/dist/venera-hm-reader-layout-20261014-signed.hap>)
  SHA256 `E646906C129B9CAD746D226E18666EC2F24CC302597F5AAFC205A9C068EF7B0E`，
  [hash](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-layout-signed3-sha256.txt>)、
  [package audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-layout-package-audit-20261014.json>)。
- 设备连接后仅 **install -r**，同时验证exit0与正文`install bundle successfully`：
  [install](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/reader-layout-install3-20261014.log>)。
  **无卸载/清数据/主动启动/点击/锁屏绕过；未读回旧history38，也未称新UI真机通过**。

### 尚未等价与下一轮

1. 需要用户允许专用设备时段后验证：same-source history restore、1–5屏图/首张/RTL/横竖屏/设置返回、
   wide odd-width GPU clipping/invert、兄弟zoom、等待解码auto门禁、late flow anchor与真实Preferences冷读。
2. 当前Gallery新组存group start，不复刻上游“最后一组history.page直接标最后图”的完成态特殊逻辑；
   新分层设置存HM偏好文档，不是原版appdata备份兼容或跨设备同步实现。
   旧DataSync readerMode字段还是legacy metadata，未用于merge；readerSettingsV1还未加入同步/备份，继续补。
3. 连续/瀑布流auto仍按图片步进，原版smooth/stepped pixels-per-second、waterfall跨章/preload、autoReaderMode layout检测、
   全部手势/长按/音量/eInk/亮度设置与评论仍缺。无死开关冒充这些能力。
4. 完整目标持续：系统后台/归档下载、导入导出/原版备份、双向同步/漫画库、OAuth/infoItems、探索/网络收藏/追更/图片收藏与L1–L5。
   用户选择仍为**只安装不占前台**，继续本地实现，不把Node/API语法/签名安装归类真实手机验收。

## 2026-10-14 主运行时生命周期与真实主机NAPI验证（上一轮，生命周期build4当时覆盖安装）

完整迁移继续进行。此轮收口上一轮主QuickJS process-retained、裸callback data和worker完成态遗留，
不是缩小目标到“主机可运行”。设备先断连，最后复核重连后只覆盖安装新包，遵守用户**暂不占用前台**选择。

### 本轮生产代码

- [lifetime_registry.h](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/lifetime_registry.h>)
  跟踪函数、resolve/reject capability、pending Promise根；注册表所有权、generation/context、一次Claim、
  Release先inert后释放，Shutdown在context销毁前归还所有登记根。未知native payload不被解引用。
- [value_bridge.h](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/value_bridge.h>)
  函数handle改为**private type-tagged普通对象 + napi_wrap**，不是raw external。
  所有isFunction/invoke/回传路径统一tag→unwrap→registry membership检查；同payload伪造raw external也拒绝。
  Callback holder使用**普通对象finalizer anchor**，由callback上不可写/删除、不可枚举的独立Symbol属性保活；
  属性成功发布后才绑定finalizer，失败不转移native data所有权，避免双释放。
- [napi_init.cpp](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/napi_init.cpp>)
  两个NAPI settle callback各有GC holder，共享一个持久状态；先Claim再转换，重复/迟到resolve/reject不触碰旧context。
  正常关闭顺序：禁止新入口→cancel/join workers→释放worker能力→处理pending deferred/JS根→最后活动lease退出后
  registry Shutdown与main QuickJS销毁。MainRuntimeLease覆盖原生/QJS活跃帧，避免TraceScope/local值未退栈就销毁context。
  **正常路径不再一概保留主runtime**；公开diagnostics只有计数，不包括脚本、函数名、参数或凭据。
- 转换防护现在**在读取中单遍执行**，不是只在预检看一次树：depth64/node65536/string+binary+property key总64MiB/path-cycle。
  getter在两次阶段之间变成循环/陌生external也不会越过实际转换保护；Map/Set iterator抛错不会伪造部分成功。
  源compute的JS→worker→JS structured-clone仍保留循环/Map/Set/identity；最终传到ArkTS的循环对象明确拒绝，不冒充支持。
- 实际修复normal JS异常：host then先resolve再throw仍保留赢家结果且清pending NAPI错误；
  rejected/thrown对象的toString自己throw不再污染后续请求；坏callback args在调用源函数前拒绝。
- [worker_napi.cpp](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/worker_napi.cpp>)
  完成中/已交付态分开，NAPI deferred消耗后立即置空；logger allocation异常不再触发二次settle。
  RPC mutex仅保护Claim/commit，**getter/NAPI/转换期间不持锁**，修复getter重入loser callback或关闭join的死锁风险。
  Main runtime lease与局部dup capability保护worker完成帧；已完成任务缩减到**实际保留字节**预留，
  直到TSFN finalization仍保留实际结果/count；不会因小结果积着64MiB maximum allowance而误拒绝后续四路compute。

### 分层验证：已实测，不升级为手机证明

1. **26项生产LifetimeRegistry原生边界断言，130个synthetic payload实际释放PASS**：
   [audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/native-lifetime-host/audit.log>)、
   [result](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/native-lifetime-host/result.log>)。
   实际QuickJS执行，包含130个GC finalizer、shutdown before/free after context、foreign pointer/epoch/identity/onceClaim。
2. **21项真实主机NAPI集成PASS**：[actual Node audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/napi-host/audit.log>)、
   [integration](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/napi-host/integration.log>)。
   [build_napi_host_addon.ps1](<C:/Users/<user>/Desktop/dev/Venera-HM/tools/build_napi_host_addon.ps1>)
   直接编译生产4个C++翻译单元与同一QuickJS/Brotli/host-zlib；只用测试头adapter映射标准Node NAPI。
   官方Node24.14.1 header/import-lib经公开SHA256校验，安装在临时目录，不替换手机库。
   **不是JS模型模拟**：真实NAPI/TSFN/GC/原生threads执行，host handler正文是固定合成数据。
   内容包含typed function wrapper/foreign alias、300个函数GC、double/late callbacks、winner+throw/toStringthrow、
   getter reentry/变形树、四路compute/小图RGBA逐像素、主机event loop heartbeat、CPU/微任务超时和匹配Trace取消、
   GBK/3种codec真实NAPI返回、保留40个函数/20个pending桥直到**实际Node env cleanup**的子进程正常退出。
   最后正常路径GC后 `externalHandles/ownedRoots/pendingCalls` 全部为0、`ownershipUncertain=false`，有真实断言；
   这不是对故障注入或任意未完成业务请求都已释放的承诺。
   重跑驱动：[run_napi_host_tests.ps1](<C:/Users/<user>/Desktop/dev/Venera-HM/tools/run_napi_host_tests.ps1>)。
   **Node/V8退出顺序不等于手机ArkTS/NAPI退出顺序、ImageKit或SDK HTTP通过**；未注入分配故障或验证真机TSFN null-env drain。
3. 同轮生产隔离/RPC **82**、Trace **37**、解码独立向量 **17**再次PASS；**25组本地mock/source回归PASS**：
   [local regression](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/runtime-lifetime-regression-20261014.log>)。
   7项worker source-contract仍只是源码契约，不计入真实NAPI用例。
4. **最终生命周期build4签名构建exit0 PASS**：
   [build](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/runtime-lifetime-build4-20261014.log>)。
   此命名与上一轮isolated-runtime build4不同；不要用前轮包哈希替代。
   [最终签名包快照](<C:/Users/<user>/Desktop/dev/Venera-HM/dist/venera-hm-runtime-lifetime-20261014-signed.hap>)
   SHA256 `B36FD44FCE929575661EB49587F2969845B13A0E665655DC0D2459B73CDF9A0C`：
   [hash](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/runtime-lifetime-signed4-sha256.txt>)、
   [native/init包审计](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/runtime-lifetime-package-audit-20261014.json>)。
5. 最后设备重连，HDC **install -r exit0且正文install bundle successfully**：
   [覆盖安装](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/runtime-lifetime-install4-20261014.log>)。
   **只安装，未主动启动、点击、冷启动/真机验收；未卸载或清数据**。旧history38未读回。
   增加 [install_verified.ps1](<C:/Users/<user>/Desktop/dev/Venera-HM/tools/install_verified.ps1>)：
   ExitCode0+正文成功双重检查，5种success/failure契约PASS；避免上一轮HDC断连仍exit0的假成功。

### NAPI兼容审计与必须保留的边界

- 查明旧GitHub `ace_napi`镜像与现行`arkui_napi`实现不相同；不能把旧镜像的限制写成当前设备事实。
  现行 [ArkUI native_api](https://raw.githubusercontent.com/openharmony/arkui_napi/master/native_engine/native_api.cpp)
  支持define_property的Symbol key/function-object转换；tag与GC finalizer依赖对象语义。
  保守使用普通对象tag/wrap与普通对象callback anchor，不靠Node允许external/function tag/finalizer的行为猜手机。
  [现行参考](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/upstream/arkui_napi_native_api_host_review.cpp>)
  与 [旧镜像参考](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/upstream/ace_napi_native_api_host_review.cpp>)已保存；
  这是公开源码审计，仍不是真机ABI证据。
- 正常关闭归还登记JS根；**std::bad_alloc故障下旧转换临时JSValue还未全部RAII化**，
  `ownershipUncertain`保守保留runtime，不冒称全部OOM路径无泄漏；OOM fault injection尚未做。
- [Node deferred实现](https://raw.githubusercontent.com/nodejs/node/v24.14.1/src/js_native_api_v8.cc)
  显示deferred在settle后消耗。关闭时尝试reject pending token；如backend拒绝，计入deferredCleanupFailures，
  没有跨backend通用deferred destructor，不能因为清map就宣称所有backend native分配被证明释放。
- 同一模块的第二NAPI环境/re-init目前**明确拒绝**，worker generations还未复刻；
  尚未settle的业务请求活着时仍保留pending所有权，不假装在任意时刻取消。
- 原版持久compute池全局、nested compute/远程函数proxy、图片完整缓存/流式进度/性能等价仍缺。
  完整阅读器/下载归档/导入导出/原版备份/双向同步/漫画库/探索评论追更及L1–L5仍继续。
  用户允许专用手机时段后再验证新包NAPI wrapper/async/GC、ImageKit/SDK HTTP、DB/Cookie冷迁移和真实源矩阵；
  继续不占前台、不绕过权限，真实账号由用户在设备输入。

## 2026-10-14 compute 与独立图片运行时（上一轮；isolated build4当时安装，build5当时待重连）

完整迁移仍进行中；本轮不是“全功能完成”。当前实际工作目录为
`<repo>`，不是历史快照的 root 用户目录；当前目录不含 `.git`。

### 生产实现

- **真正后台执行**：[isolated_engine.cpp](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/isolated_engine.cpp>)
  与 [worker_napi.cpp](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/worker_napi.cpp>) 使用最多4个原生线程；
  QuickJS 创建、使用和销毁都在所属 worker。图片像素重排/裁剪/旋转/填充、alpha 转换与脚本不再在主源引擎/UI线程执行。
  每个图片和 compute 任务使用**新上下文**；只保留线程池，不复用任务全局或未完成 Promise。
- 源 `compute(functionString, ...args)` 在主 NAPI 的 sendMessage **转换成 ArkTS 之前**截获，
  使用 QuickJS structured serialization 搬运参数/结果；Map/Set/typed subview/共享引用/循环引用与参数隔离有真实核心断言。
  worker 的普通同步/异步主机 RPC 经 TSFN 返回主线程处理，不在 worker 访问 ArkTS/NAPI 对象。
- **执行限制**：默认10秒后台执行期限（不包含 ArkTS 排队、SDK编解码）；字节码 interrupt 与每条微任务调度均检查期限/取消，
  包括不断自排队的短 Promise job，不能只中断长循环。JS堆上限为图片64MiB/compute128MiB，栈1MiB；
  图片会话 surface 预算按 `min(128MiB,max(32MiB,4×inputRGBA))` 计算，累计上限128MiB，bridge 操作16384次；脚本捕获 bridge 上限异常后也不能冒充成功。
- **准入与释放**：原生最多32个保留任务、合计384MiB input/最大result transport预留，先准入再复制像素，
  预留保留到 TSFN finalization，限制主线程来不及接收时的结果堆积。
  ArkTS最多32个 active/queued 图片请求，合计128MiB encoded-input + 128MiB decoded-input RGBA预留；
  RGBA检查在 PixelMap/buffer 分配之前。输入 ImageKit PixelMap/ImageSource 在派发 native 前释放；
  排队/解码/执行/编码/取消异常均归还预留与句柄。**这些不是整个进程峰值内存保证**。
- **RPC保护**：[worker_rpc_validation.h](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/cpp/worker_rpc_validation.h>)
  检查循环、深度64、节点65536、稀疏数组长度、binary上限、function/proxy/accessor/exotic；
  Host结果另有大小/深度/循环检查与有界Map/Set验证。
  源 compute 的直接结构化参数/结果支持循环/Map/Set，与限制更严格的 worker→host RPC 不是同一通道。
  取消按真实请求Trace处理，不中断其他Trace；审计不记录代码、参数、像素或敏感异常原文。
- [JsEngine.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/source/JsEngine.ets>)
  single-flight初始化/已成功bootstrap不重跑；加入实际源 compute 入口、克隆、RPC、真实native像素旋转/取消的启动契约。
  **契约已经打包，但本轮还没验收执行**。
  [ImageTransforms.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/network/ImageTransforms.ets>)
  检查所有阶段的取消，迟到编码不发布；带修改脚本的组件图片独立拥有请求，避免共享缓存消费者互相取消。

### 本地与构建证据

- **生产C/C++真实执行82断言PASS**：[native audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-native-host/audit.log>)、
  [result](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-native-host/result-utf8.log>)。
  内容含逐RGBA重排带余数/旋转/alpha、非法返回/边界/预算、JS heap、无限循环、微任务循环、运行中取消、
  异步/循环结构化复制、Host RPC Trace、4个独立引擎并发、RPC图防护。不是手机 NAPI/ABI 验收。
- 同轮重跑生产 Trace **37** 与解码器独立向量 **17** PASS：
  [trace audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/native-runtime-host/audit.log>)、
  [codec audit](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/native-http-codecs/audit.log>)。
- **25组本地回归PASS**：[final regression](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-final-regression-20261014.log>)。
  新增18项ArkTS生命周期/准入用例、7项worker**源码契约**，browser cookie更新为19项；其余原回归也重跑。
  ArkTS/SDK/文件系统mock与源码契约不能提升为设备线程、图片或真实站点通过。
- SDK实际编译与签名通过：[build3](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-build3-20261014.log>)、
  [最终build5](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-build5-20261014.log>)，build5显式进程exit0。
  build5补自适应surface/结果预留和5项生产预算断言，防止4个小图因每个固定预留128MiB而必然被拒绝；
  高并发大图仍可明确拒绝，未声称所有尺寸都能4路同时处理。
  build1的mid-edit编译错误、build2的SDK类型错误已修；build3文本成功但PowerShell wrapper exit1不作为最终退出码证据。
  有既存SDK lint/deprecated警告，也有新Cookie facade的classes-as-object警告，**不是零警告声明**。
- **HDC install -r 成功，exit0**：[覆盖安装证据](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-install4-20261014.log>)。
  未卸载或清用户数据；[签名包SHA256](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-signed4-sha256.txt>)
  为 `FC239E1A3B286703004B536B23ED19BBAC37B1878EAE2F24142DCC90428521E6`（设备已安装build4）。
- **最新build5安装未成功**：[install5](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-install5-20261014.log>)
  正文 `E001005 Device not found or connected`，后续 `hdc list targets` 为 `[Empty]`。
  HDC该失败仍返回exit0，**必须同时核对正文，不能用退出码0冒充安装成功**。
  最新 [signed HAP](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/build/default/outputs/default/entry-default-signed.hap>)
  SHA256为 `9CE9DA2BF276B7DE13FE8203C8D64F27DA8D4AD9E9E312A3BFBE85A8703D02E7`，
  [build5 hash](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-runtime-signed5-sha256.txt>)、
  [包内容审计](<C:/Users/<user>/Desktop/dev/Venera-HM/logs/isolated-package-audit-20261014.json>) 已核对当前native库和原版init字节。
  最后确认成功安装为build4；自适应小图预留修正在主机build5，**等待重连install -r，不卸载或清数据，不启动前台**。

### 环境恢复与当前设备边界

- 当前DevEco为6.0.1.251、SDK6.0.1.112/API21，CLI使用主机Node24而非SDK捆绑Node18。
  临时CLI1.3.5显式安装common平台依赖后恢复，正常auth/signature命令恢复当前用户材料；不手工导出密钥。
  旧root用户编译器路径失效，恢复官方SHA256校验的Zig0.13.0后更新本机指针。
  原生脚本修正Windows PowerShell把编译器stderr warning误当致命错误的问题；仍按原生exit code拒绝真实失败。
- 当前SDK声明缺 PATCH/新Cookie API。PATCH保持精确wire字符串，不降为GET；当前设备接受情况尚未实测。
  Cookie采用基于官方API23声明的显式typed facade和运行时method检查，保留新版完整属性路径；API21/22继续旧兼容，
  不因编译SDK较旧而永久禁用新版元数据。[BrowserLoginSession.ets](<C:/Users/<user>/Desktop/dev/Venera-HM/entry/src/main/ets/features/BrowserLoginSession.ets>)。
- 旧包一次 HDC `aa start` 已返回 successfully，**不能再笼统写当前一直锁屏**。
  但设备前台正被其他应用使用，用户本轮明确选择 **“先构建和覆盖安装，暂不占用前台”**。
  安装新包后**未主动启动/点击/冷启验收**。无关UI内容立即丢弃；没有操作其他应用或登录真实账号。
  历史38条仍是历史基线，本轮没有读回，也不能声称新包已保持该数量实测。

### 必须保留的功能差异与下一步

1. **不等价于原版持久compute池全局**：当前是4个持久线程/每任务新引擎，避免旧Promise上下文串线；
   原版4个持久isolate内的跨任务全局状态未复刻。嵌套compute明确拒绝；远程JS函数回调/proxy生命周期仍缺。
2. Host validation/conversion依赖可信host getter/iterator不在两次读取间变形；主QuickJS仍process-retained，
   旧 external callback/QjsBridge总生命周期还需专门收口，不能宣称所有主引擎句柄完全释放。
3. 修改脚本组件暂绕过共享缓存以保证取消所有权；原版持久池、完整缓存/流式进度与性能等价仍需继续。
   原生限制不包含ImageKit所有临时分配，也不是全应用OOM保证。
4. 用户允许专用设备时段后，先验收新包启动 compute/native Trace/native codec契约，再运行离线像素oracle和本机HTTP回归，
   验证真实ImageKit/SDK gzip-deflate-br/异步onResponse/取消/后台暂停、DB/Cookie冷迁移与真实源矩阵。
   不自动抢占前台、不绕过权限；真实登录/验证码由用户在设备自行输入。
5. 不等待真机时段继续本地阅读器完整设置/双页/音量/墨水屏、系统后台与归档下载、导入导出/原版备份、双向同步/漫画库、
   OAuth popup/infoItems、探索/动态分类/评论/网络收藏/追更/图片收藏及完整L1–L5。完整目标保持进行中。

## 2026-10-14 运行层：真实异步Trace上下文与HTTP编码证据（上一轮）

前一轮有代码/安装/回归进展，本轮继续修共用运行层。完整迁移远未完成；设备锁屏不阻止本地实现。

### 代码与原生证据

- **不是全局current登录变量**：本次给vendored QuickJS增加embedding-only
  `JS_GetAsyncContext/JS_SetAsyncContext`。每个job捕获入队上下文，每个Promise reaction捕获**注册continuation时**上下文；
  `then`/`await`恢复reaction自己的上下文，不偷用最后resolve者。嵌套PumpJobs、正常/异常路径恢复旧上下文，
  job/reaction销毁释放值，Promise GC marker包含上下文。应用只存字符串。
  该版本Promise BEFORE/AFTER hook只覆盖部分thenable行为，不能靠它假装完整await跟踪。
  原生改动说明：`entry/src/main/cpp/quickjs/VENERA_PATCHES.md`。
- `callJson/invokeFunction`接受Trace参数；跨界函数handle记住原Owner。
  NAPI sendMessage给ArkTS**覆盖写入**`__veneraTraceId`，不相信源自己伪造的属性。
  接收器同步/异步到达、响应、拒绝/异常有统一Trace；HTTP、源save/delete、UI/validator/onCancel、
  设置getter/callback、图片onResponse/recovery/modifyImage接入。
  Auth日志按Owner判断，后台并发请求不被错误标成“当前登录”；晚到auth-owned callback仍脱敏。
- **已实际运行生产C/C++源码**，非JS模型模拟：
  `tools/run_native_runtime_host_tests.ps1`使用临时目录中校验官方SHA256的Zig0.13.0编译生产QuickJS/Runtime/trace header。
  `logs/native-runtime-host/audit.log`与`result.log`**37断言PASS**：
  交错await、多次await、不同订阅者共享Promise、catch/finally、嵌套then、无Trace后台、Promise.all、
  reentrant job pumping恢复Owner、GC/未完成reaction。没有读用户应用数据。
  **这不是手机ABI/NAPI/最新App启动通过**。
- 提供native `decodeHttpBody`：gzip/x-gzip（多成员）、zlib/raw deflate、Brotli，明确输出大小上限，
  截断/CRC/尾部垃圾/超限拒绝，错误不返回部分字节。
  Brotli decoder固定**v1.2.0 commit `028fb5a23661f123017c060daa546b55cf4bde29`**，
  只取common/dec/include/LICENSE，全部Git blob SHA1与官方固定tree匹配，未执行上游脚本。
  MIT许可文本还随包保存在`rawfile/licenses/brotli-MIT.txt`，与上游LICENSE逐字节相同。
  SDK应用链接系统zlib；主机原生测试另用固定zlib1.3.1源码，不替换SDK。
  `tools/run_native_http_codec_tests.ps1`编译**生产解码header与同一Brotli源码**，
  用独立Node标准库生成向量；`logs/native-http-codecs/audit.log`**17用例PASS**（含deflate Adler32/截断/尾部拒绝）。

### 必须纠正此前HTTP假设

已抓取固定commit的OpenHarmony NetStack主源码，`http_exec.cpp`在非Windows设置
`CURLOPT_ACCEPT_ENCODING=""`，libcurl会自动解码body。源码/commit记录：
`logs/upstream/ohos_http_exec.cpp`、`logs/upstream/netstack-tree-sha.txt`。
因此先前“@ohos.net.http不透明解压”的注释/判断不能当事实，更不能仅凭Content-Encoding就二次解压。

现在HttpClient默认保留SDK自动处理后的字节，ContentDecoding显式记录SDK处理策略；
只有**已证明是raw transport**的显式` sdkHandlesContentEncoding=false`路径才调用native codec，不能猜测header。
此默认策略依据公开源码，但**当前设备SDK HTTP具体行为仍未实测**。
fixture新增`/encoding/gzip|deflate|br`合成JSON；ImagePipelineUsability明确对真实返回正文逐字符核对，
如某SDK编码不支持或返回异常，不归类为源规则缺陷。

### 本轮验证/安装

- 本地23组全PASS，`logs/runtime-trace-codec-regression-20261014.log`：
  rpc-trace6、content-policy6、auth-log4、account-page9、browser-cookie17、schema4、image-component5、
  page-life5、http9、chapter7、pipeline14、pixel13、cache12、download-sync21、deep12、account19、
  reader10、settings31、history/reader75、search13、HTML11、UI14、原HTML用例。
  加上上面的原生主机37/codec17；不是最新设备矩阵、登录或ArkUI验收。
- `logs/runtime-trace-codec-build8-20261014.log`签名构建PASS（build8只补打包MIT通知）；
  `logs/runtime-trace-codec-install8-20261014.log`HDC覆盖安装PASS，未卸载/清数据；
  `logs/runtime-trace-codec-signed8-sha256.txt`保存包哈希。
  最近HDC启动（build6）`logs/runtime-trace-codec-start6-20261014.log`仍是**10106102锁屏**。
- 试图在`/data/local/tmp`执行交叉编译独立测试程序时，系统明确返回**Permission denied**，
  `logs/native-runtime-device-result.log`。已清理本次唯一临时binary/log，不改SELinux/root权限、不绕过锁屏。
  改为本地主机执行生产源码，并给App启动加NAPI `native trace contracts OK`与native codec固定向量契约；
  后两项**尚未实际执行**。

### 继续，不缩小目标

1. 解锁后先抓新包启动：native trace await/concurrent/captured-handle契约、native codec向量、DB/Cookie冷迁移；
   再跑合成HTTP编码/账号/后台暂停probe，然后真实用户账号前/后/登出/冷启动与新包源矩阵。
2. 本地推进真正独立图片JS引擎/超时/CPU线程及compute、Web popup/OAuth/infoItems、
   阅读器双页/全部设置/音量键/墨水屏、后台/归档下载、导入导出/原备份兼容、双向同步/漫画库、
   探索/动态分类/排行、评论/网络收藏/追更/图片收藏及完整L1–L5；绝不把codec/native主机测试升格全迁移完成。

## 2026-10-14 账号路径迁移：Cookie/WebView、会话保存、冷启动结构（上一轮）

本轮实际继续实现代码；完整目标未缩为模拟登录或编译通过。设备仍锁屏（最新HDC启动返回10106102），不绕过锁屏、不关闭开发者模式、不操纵电脑GUI，继续本地工作。

### 本轮代码

- 对照固定上游`parser.dart`与`comic_source_page.dart`：账号密码、声明顺序Cookie字段/validate、WebView URL/title checkStatus、
  `_localStorage`保存、Cookie导入、onLoginSuccess、`account='ok'`标记均已接入。
  `SourceAccountPage`提供三种实际入口、失败保留草稿、成功清草稿返回；路由只带源key。
  重新登录只使用保存的密码元组，不把Web/Cookie的`ok`标记误当密码；注册网站仅用户点击时打开系统浏览器。
- `SourceWebLoginPage`使用独占incognito登录空间与注册前互斥，默认HTTP UA与Web UA一致，禁止file访问/混合内容及非HTTP(S)外跳。
  正常浏览器配置/HTTP jar不清空；取消、标题/导航变化、退出后的晚到结果不提交。
  自动Cookie/localStorage导出后再次调用源checkStatus，等待**异步**onLoginSuccess和数据落盘再确认。
  Credential值不会放进路由参数或开发审计。
- 浏览器Cookie完整属性导入：Path/Domain/hostOnly/Secure/HttpOnly/过期/SameSite，
  RDB事务失败恢复内存；取消或callback失败尝试恢复本次导入/暂存，后续网络更新不被旧receipt回滚。
  源callback本身产生的任意副作用不能通用撤销，仍是实际站点专项验收项。
- Cookie表**加列迁移**`same_site DEFAULT ''`，不删除原Cookie；初始化先完成迁移再读Cookie。
  此为本地/mock验证，未声称最新包已执行真实RDB冷启动升级。
- 修复源显式跨域Cookie设置：发布的e-hentai Cookie登录会一次传`.e-hentai.org`和`.exhentai.org`；
  不能用HTTP响应域名限制误拒绝可信源API。源显式Domain允许跨域/省略前导点，HTTP Set-Cookie与浏览器导入仍严格按来源校验。
  这不证明e-hentai已真实登录；其gzip/br等网络兼容仍需查。
- SourceDataStore新增本源写入失败epoch/排队屏障：源JS `saveData`即便API表面同步，
  password/Cookie/Web成功与logout都等待已排队操作，不忽略token的异步SQL失败。
  暂存回滚不覆盖脚本之后的新值；密码/Cookie/站点正文不写日志，账号操作期间源console原文也抑制。
  **原生RPC子请求与并发await上下文TraceID完整传播还待做**，不能用全局当前账号trace错绑其他源后台请求。
- 当前设备系统API参数实测**26**（`logs/device-sdk-api-20261014.txt`）。
  Cookie完整导出使用运行时API≥23的fetchAllCookies，工程target/compatible仍21。
  继续读取固定上游`routing/webview.dart`后确认：原版只复制name/value/domain，并不保留其他Cookie属性；
  **不能因为旧SDK没有完整属性接口，就人为禁用原版可用的网页登录。**
  API21/22现已新增header兼容路径：name/value导出，Domain/Path/Secure/HttpOnly用本地CookieManager及document.cookie观察，
  父域需parent+sibling都确认；过期/SameSite不能获取时按原版session兼容。
  快照/日志明确`cookieMetadataComplete=false`，不伪称完整元数据。
  API21/22原生行为、完整元数据与跨域仍需设备对照；不是缩小完整迁移目标。

### 当前证据（不要提升为真实登录）

- 本地21组全部通过：auth-log3、account-page9、browser-cookie17、cookie-schema4、image-component5、
  page-life5、http7、chapter7、pipeline14、pixel13、cache12、download-sync21、deep12、account19、
  reader10、settings31、history/reader75、search13、HTML生命周期11、UI14、原HTML用例。
  `logs/account-web-final-regression-20261014.log`及各模块日志。
- 最终签名构建：`logs/account-web-build8-20261014.log`；HDC `install -r`覆盖安装成功：
  `logs/account-web-install8-20261014.log`、`logs/account-web-signed8-sha256.txt`。
  最近HDC启动（build7）：`logs/account-web-start7-20261014.log`→**10106102锁屏**，没有证明崩溃。
  build8只补了旧SDK兼容后覆盖安装，没有重复尝试绕过锁屏。
  未卸载/清用户数据，历史38条仍只是上次已验证基线，本轮未读回。
- 真实ArkWeb Cookie对象的expiresDate格式、incognito生命周期/UA、Schema升级/冷启动、验证码/网页流程、
  Cookie输入与源onLoginSuccess **均未设备验收**。本轮没有使用任何真实账号。

### 解锁后的新包验收入口

保留之前本机PNG/后台下载probe，新增本机合成账号probe：

1. `node tools/image_http_fixture_server.js`仅监听127.0.0.1:29091；检查无用户同端口HDC任务后rport该端口。
2. 历史→离线验收→“打开本机合成账号验收（需CLI服务器）”。
   Cookie输入`synthetic`或网页登录手动点“确认合成账号”，检查原生浏览器HttpOnly/Expires/SameSite Cookie、
   localStorage、实际HTTP验证、真实RDB写入和强停冷启动读回。
3. 此源`__HM_AUTH_USABILITY__`只在诊断注册表，未写真实源DAO；owner标记和随机Cookie名限定清理。
   “清理本机合成账号验收”不删除其他localhost Cookie/真实源/历史/收藏。
   **合成站点通过也不算L4真实登录**，实际账号/验证码必须用户在设备自行输入，不发到聊天。
4. 真实站点前/后/登出/冷启动、失败/取消对照，以及本轮共同层修改后的源深矩阵都需重跑；
   不能拿早前PID21512的5/20链路取样当新包验收。

### 不等待锁屏的下一步

- 优先完成原生QuickJS异步Trace上下文与HTTP压缩兼容（源码已存在JS_SetPromiseHook；
  gzip/deflate可用SDK native zlib，br能力需核实），解决真实Cookie登录关键共用层，不把SDK/桥失败归源规则。
- API21/22 header兼容的原生核验与完整Cookie元数据、独立图片JS引擎/超时/后台像素工作、
  Web popup/OAuth/实际验证码与源账号infoItems继续补。
- 继续阅读器双页/完整设置/音量键/墨水屏、源归档与系统后台下载、导入导出/原版备份兼容、
  真正双向同步/漫画库、动态分类/探索分段、评论/网络收藏/追更/图片收藏及完整L1–L5；目标未完成。

## 2026-10-14 锁屏期间继续迁移：完整图片配置、后台暂停、分组与推荐（上一轮）

仍以原安卓项目完整功能为目标。本轮设备锁屏，继续本地实现，没有绕过锁屏、关闭开发者模式、操作电脑GUI或清用户数据。

### 已实现，但本轮设备验收仍待解锁

- **下载生命周期**：UIAbility `onBackground`暂停running/checking；`onForeground`只解除门禁，不自动开始。
  DownloadsPage hide/disappear停止timer并暂停，show只恢复UI刷新。校验期间暂停停止后续磁盘解码；
  网络/像素处理晚到不写页、不推进checkpoint，不把用户有意暂停显示成下载失败。
  不是系统后台下载队列，后台持续下载/通知/批量/归档仍未做。
- **完整图片请求配置**：`ImageConfigParser`统一初始与失败恢复配置；新增native `isFunction`区分真实QuickJS回调。
  GET/POST/PUT/DELETE/HEAD/OPTIONS/PATCH、字符串/JSON/二进制正文均保留。
  `ImagePipeline`执行HTTP→异步onResponse→modifyImage→实际PixelMap解码；
  onLoadFailed每次返回全新配置，最多5次恢复/6次请求，非法返回/回调抛错/取消不发裸GET。
  上游整数字节list按Uint8List.fromList模256转换；非函数回调按上游忽略。
- **缓存/资源**：简单GET继续按URL/headers/Cookie/脚本身份缓存；含正文、非GET或回调绕过普通缓存，
  以免不同闭包/POST正文错误共用URL缓存。动态PixelMap由组件拥有，在替换/退出/晚到/自然尺寸读取失败时释放；
  共享缓存PixelMap不被单个组件误释放。此策略不是上游所有缓存/流式进度行为的完整复刻。
- **HTTP桥**：字符串正文不再自动冒充JSON，SDK不传空extraData；二进制子视图精确复制，不发送整个backing buffer。
  请求方法不再把PATCH/OPTIONS/未知方法静默变GET；默认头部按大小写不敏感识别。
  **shonen_jump_plus旧SDK Parameter error原因尚未真机确定，不能仅凭本地mock称已修源站登录。**
- **章节分组/推荐**：详情按组展示/折叠/组内倒序，阅读器目录显示组头；
  ChapterNavigation保留canonical ID/序号，重复ID在展示中去重，不改变历史。
  详情已解析recommend现在渲染，按推荐自身sourceKey跳转；封面补thumbnail hook。
  双页拆分、音量键、墨水屏、全部手势/设置与长列表虚拟化仍缺。
- **页面竞态**：源管理reload、详情/收藏刷新按退出/版本丢弃晚到响应，退出后不跳转下载页。

### 验证与安装证据

- 本地17组全部通过：图片组件生命周期5、页面/Ability生命周期5、HTTP适配7、分组/推荐7、
  图片流水线14、像素13、缓存12、下载/同步21、深矩阵12、账号8、阅读器控制10、设置29、
  历史/阅读器75、搜索13、HTML生命周期11、UI桥14、原HTML用例。
  `logs/pipeline-chapters-final-regression-20261014.log`及对应逐链路日志。
  数据/网络/SDK为隔离mock，**不算本轮设备验收**。
- 最终签名构建`logs/pipeline-chapters-build7-20261014.log`成功；
  通过HDC `install -r`覆盖安装`entry-default-signed.hap`成功，未卸载或清数据：
  `logs/pipeline-chapters-install7-20261014.log`、`logs/pipeline-chapters-signed7-sha256.txt`。
  **最新包已安装，但未成功启动/验收**；最近实测历史38条属于上轮，不声称本轮已读回。
- 此前build3用DevEco run时安装成功，启动返回**10106102设备锁屏**。
  `logs/image-pipeline-deploy3-20261014.log`的`Smoke: FAIL_CRASH`只是CLI误归类，不能据此证明应用崩溃。
- 测试服务器最初19091落在Windows排除端口18998–19097，改为**29091**；
  没有修改系统端口排除或防火墙。测试仅监听127.0.0.1，已结束本次Node服务器/自有HDC日志采集，
  已移除本次`tcp:29091 tcp:29091 [Reverse]`，其他HDC服务未停。

### 解锁后再验证，不停止本地迁移

1. 不必重复安装，HDC启动最新包；先验证新增native回调类型判断、旧像素桥/设置/存储启动契约。
2. 专用合成HTTP测试（**无账号/历史/收藏上传**）：

   ```powershell
   node tools/image_http_fixture_server.js
   # 另一CLI窗口，先确认fport ls没有同端口用户任务：
   & 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t <device-id> rport tcp:29091 tcp:29091
   ```

   历史→离线验收→“运行本机图片HTTP回归（需CLI测试服务器）”。
   ImagePipelineUsability先确认fixture /health身份，再检查POST/空POST/子视图/异步onResponse→旋转/恢复/上限拒绝；
   主机`logs/image-http-fixture-server.log`复核`/always-fail`恰好6次，不能把mock替代此步骤。
3. 同一服务器下“准备下载后台暂停验收”→用手机实际Home退后台→回来→“复核并清理后台暂停验收”；
   /slow为20秒合成PNG，需确认UIAbility真实回调、paused/0页/不自动恢复，清理仅随机自有任务。
   如被系统杀进程，finish会拒绝猜测清理其他下载；按ledger/marker审计恢复，不能强清用户数据。
4. 分组/倒序/推荐/封面hook UI、晚到图片所有权、离线下载恢复重验；再跑**新包**深矩阵。
   上轮final7（5链路取样/20脚本）是历史证据，不用于本轮新HTTP实现背书。
5. 本地继续独立图片JS引擎/超时/后台像素计算、WebView/Cookie与真实登录、双页/完整设置、
   导入导出/源归档/系统后台下载、真正双向同步/文件库，以及完整L1–L5矩阵/其余原版功能。

## 2026-10-14 图片变换、下载检查点与账号生命周期（上一轮设备验证）

目标仍是原安卓项目完整迁移，不是基础框架或MVP完成；设备锁屏继续本地工作，CLI签名/构建/安装，不操纵电脑GUI。

### 已落地的真实功能

- `ImageScriptBridge.ets`实现原版`Image.empty/copyRange/copyAndRotate90/fillImageAt/fillImageRangeAt/width/height`同步协议。
  对照固定commit的`logs/upstream/image_processing.dart`，顺时针旋转与JM带余数分块重排不是“只看可解码”。
  独占变换会话、finally释放句柄、过期句柄拒绝、矩形/整数校验、RGBA surface总量128MiB上限。
  `ImageTransforms`真实ImageKit解码为RGBA、处理premultiplied alpha、执行脚本并无损PNG编码。
  **差异/限制**：脚本仍在共享QuickJS中的IIFE执行，不等价于上游独立Isolate；尚无脚本超时中断，CPU长脚本和大图峰值内存仍需优化。
- 阅读器、封面、下载、浅/深矩阵共用图片配置/变换；缓存身份SHA256覆盖URL/头部/Cookie/变换脚本。
  并发同身份请求合并；已有坏缓存只删当前项，新无效响应不写缓存，有效图片`.part→rename`。
  `method/data/onResponse/onLoadFailed`仍明确标应用缺口，不能忽略它们发裸GET。
- 前台下载队列有所有权marker、每章页数ledger、整数/schema检查、逐页实际PixelMap解码。
  继续前读盘复核完整检查点，缺失/腐坏页从首个坏页回退，不删除后续内容、不重复累计；
  旧版无每章页数记录不自动冒充completed。同漫画并发创建合并；页面异步初始化/退出不会遗留timer。
  仍不是系统后台队列，CBZ/EPUB/PDF/源归档/批量下载未做。
- 账号密码成功等待站点callback与`setAndWait`落盘；登出等待异步站点callback和`removeAndWait`。
  单源登录/登出互斥，删除失败恢复最后确认值；Web/Cookie-only不伪造password login。
  **真实登录未执行**，需要用户在设备自行选择源并输入账号/验证码，不发密码到聊天。
- 阅读器基础页按钮、zoom/pan、默认8秒自动/暂停、窗口亮度已实现。
  自动阅读临时保持亮屏，暂停/隐藏/退出恢复；不绕过锁屏/修改系统设置。
  双页拆分/音量键/分组章节树/墨水屏/完整设置仍缺。
- WebDAV仅阅读数据白名单备份/保守事务合并；真实RDB隔离重复合并和导出三表已设备通过，
  不导出source_data/Cookie/账号，密码只页面会话。真实服务器认证/PUT/GET、双向冲突、删除传播、漫画库/定时仍缺。

### 本地与设备证据

- 本地生产代码回归：像素13、缓存10、深矩阵12、下载/同步19、阅读器控制10、账号8、历史/阅读器75、
  设置29、搜索13、HTML生命周期11、UI桥14、原HTML用例全部通过。
  文件：`logs/migration-final-regression-20261014.log`以及对应测试日志，不能当设备/真实站点验收。
- 真机ImageKit+QuickJS像素oracle已通过：3×5非对称RGBA、分块带余数、裁剪/顺时针旋转/填充、
  越界拒绝后下一请求正常；`ImageTransformUsability PASS`。不是JM真实内容人工核对。
- 真机下载：本地2章×3页，完成复核、随机自有目录注入缺页、回退恢复、累计仍6页、
  completed读回、自动清理；同步隔离去重；`logs/transfer-device/`。历史基线**38条不变**，不要还原到旧轮36/29条。
- build4设备深矩阵20行已完成：5个`SAMPLE_CHAIN_OK`为hcomic/hitomi/nhentai/copy_manga/**jm**；
  13个`BLOCKED_SEARCH`，ykmh/zaimanhua为`FAIL`。ManHuaGui本轮BLOCKED_SEARCH，不套用历史结果。
  `logs/image-deep-matrix-build4-20261014.log`与`logs/image-deep-matrix-build4-rows-20261014.jsonl`。
  mixed仅0/1分段、分类动态未验、L1只metadata、全L0 partial、L4/L5未验；不能说5源完整可用。
- 构建6：`logs/image-account-reader-build6-20261014.log`签名成功；
  部署证据`logs/image-account-reader-deploy6-20261014.log`。构建/安装通过不提升上面验收分级。
- 阅读器构建6真机：原`galleryLeftToRight`模式未改，页›1→2、‹页2→1，double tap比例1→2→1，
  35%窗口亮度，自动8秒前进、暂停后10秒页码不变，暂停恢复亮屏/退出恢复窗口亮度的SDK调用完成。
  `logs/reader-controls-device/`含逐步树与放大图；`logs/image-reader-transfer-device-pid13931-20261014.log`含对应API审计。
  两次CLI探针修正只涉及验收脚本：页面异步加载需等进度文本；CLI简化树隐藏Swiper内Image，改用HDC原树但只留应用图片bounds；
  系统确认按钮的文字在不可点击子Text，点击包含它的唯一Button。最终确认清理本次样本，历史38条不变。
  **没有双指pinch、pan边界、RTL自动阅读或全部模式视觉验收；亮度/亮屏恢复目前是SDK调用完成日志，未另读回系统状态。**
- 共用解码验收再次收紧：浅/深矩阵现在要求`createPixelMap`而非只读取图片header，
  HttpClient与图片配置/缓存/变换透传同TraceID，URL/会话秘密不再写入新HTTP请求日志。
  构建7额外去掉浅自检误导性的`fully working`字样，改为取样链路且非全L0–L5。
  当前最终签名包/部署：`logs/image-account-reader-build7-20261014.log`、
  `logs/image-account-reader-deploy7-20261014.log`、`logs/final7-signed-hap-sha256.txt`。
  构建7最终实际PixelMap矩阵已完成（PID21512，设备时间02:16:54–02:21:29）：
  20行，5个SAMPLE_CHAIN_OK=hcomic/hitomi/nhentai/copy_manga/jm、13个BLOCKED_SEARCH、
  ykmh请求403/zaimanhua漫画不存在两项FAIL，均未作为规则缺陷豁免。
  `logs/image-deep-matrix-final7-20261014.log`、`logs/image-deep-matrix-final7-rows-20261014.jsonl`、
  `logs/image-matrix-device/final7-completed.json`。L0仍partial，mixed动态/完整L1/L4/L5未验。
  已验证并停止本线程HDC HiLog采集进程PID178736，没有停止其他HDC服务/进程。
  设备最后在离线验收矩阵结果页，当前应用PID21512；以下历史日志不得替代它。

### 下一步不等待锁屏

1. 下载补`UIAbility.onBackground`/页面hide暂停和生命周期回归，
   不能以当前返回页面的pause代码声称系统后台下载已完成；源页reload还需退出响应保护。
2. 图片method/data/onResponse/onLoadFailed；独立图片JS引擎/超时/后台像素工作，JM真实页内容人工核对。
   shonen_jump_plus的空字符串POST可能被SDK extraData校验拒绝，需本地/设备确定性复现后修复，不能当HTTP401。
3. 完整L1设置schema/init/filename、动态/随机分类、mixed全部分段、非搜索路由与L4/L5真实登录分级。
4. WebView/Cookie登录、站点账号前后/登出/冷启动对照；只在用户自己提供设备交互时做真实认证，不冒充模拟结果。
5. 阅读器双页/组章节/音量键/墨水屏；后台与归档下载；完整双向同步/文件库、导入导出、详情/收藏/追更其余功能。

## 2026-10-14 连续修复：源设置、HTML生命周期、搜索分页（最新）

实际代码已修改并通过CLI签名构建/覆盖安装，不是仅更新文档：

- **源设置**：固定上游v1.17.0（commit `7110c19c4f3e342cf33d358d6be9058d8abc2505`）对照；
  上游设置页validator是正则字符串，动态部分是settings/options getter。HM现在保存/回调后重新读getter，
  保留未提交草稿、原始false/0值和失效选项，处理读取乱序、页面退出、异常与忙碌状态。
  异步函数validator/options作为明确的兼容扩展，不能说上游v1.17.0本来要求支持。
- **保存可靠性**：SourceDataStore写入/删除有序执行，UI等待数据库完成才报“已保存”；
  写失败恢复最后已确认值，不回滚覆盖更新的请求；不记录用户设置内容。
- **设备设置验收**：隔离样本验证函数this/异步校验拒绝与通过、动态选项一→二、旧选项显示而不静默改值、
  布尔false选择与callback刷新。强停后输入42、开关true、原始false选项、callback_count=1均保留。
  已清理样本SQL/注册项/恢复标记；本轮设置验收的历史基线36条不变（不是旧轮的29条）。
- **HTML修复**：不再用“最多8项”淘汰未dispose的活跃文档；移除numeric/docN双别名；
  修复补充平面数字实体、属性实体、序列化转义和script/style原始文本。
  上游init.js未修改，新增启动契约验证12个活文档和Unicode后全部dispose。成熟HTML5库替换仍未做。
- **搜索**：新增页码/游标加载更多、去重、末页/重复游标停载、追加失败重试和旧请求隔离；
  切源/改关键词清空旧结果，详情路由按结果自身sourceKey，返回详情后保留原结果。
  搜索后收键盘，显示加载条数；实际设备H-Comic由10条→20条，切本地源后旧网格清空。
- **深度自检纠错**：cursorOnly标记让loadNext-only路径可被验收，首跳null/次跳游标且参数顺序正确，
  分页指纹比较完整结果而非前5项。深度矩阵仍未完整执行，不能当全L0–L3通过。
- **回归**：Node设置28项、搜索13项、HTML生命周期/Unicode/审计11项、UI桥14项、历史/阅读器75断言，
  原HTML用例通过。最终包设备UI自检（含auditFile读盘）、历史4组、收藏10项通过。
- **源矩阵**：共用层修改后22源浅链路已重跑；最终PID46996为4/22（含local/demo_api，实际20个JS源），
  不是完整深度通过率。PC抓取wn001.cfd页面可复放已发布wnacg规则得到24个字段完整结果，
  不能据此宣称设备wnacg通过；需要核对设备配置域名与实际响应，不应直接归咎选择器。
- **证据**：`logs/source-settings-device/`、`logs/search-device/`、`logs/ui-dialog-settings-search-final/`、
  `logs/settings-final-pid-46996.log`；最终构建`logs/settings-html-search-final-build-20261013.log`、
  部署`logs/final-deploy-20261014.log`。仅用CLI/HDC，没有操作电脑GUI、卸载或清用户数据。
- **工具链实测纠正**：本机product-info.json显示DevEco **26.0.0.851**，不是历史6.0.1；
  工程target/compatible保持HarmonyOS 6.0.1(21)，没有擅自升级应用基线。

## 2026-10-13 对话框崩溃修复已上板（最新）

- **本轮改的是应用代码**：全局无宿主builder已删除；`Index`用组件内`@Builder`注册闭包与`UIContext`，
  `UiBridge`用同一宿主的PromptAction开关窗口，解决`observeComponentCreation2 of undefined`崩溃。
- 加载框增加排队取消和异步打开期间取消处理；晚到的dialogId会关闭再释放队列，防止残留窗口和后续请求卡住。
  `onCancel`重复操作有保护，异常仍能关闭窗口；控制流由`tools/ui_bridge_cases.js`直接执行生产ETS覆盖。
- 上游`init.js`未修改。`UI.showDialog`原本返回void，自检改为等待按钮回调的完成信号，不再错误await返回值。
- **最终设备冷启动PID7940实测PASS**：空输入拒绝→输入42→默认乙/选择丙→异步按钮→
  排队加载取消→可见加载取消→无actions默认确定按钮→输入/选择取消返回null→越界默认索引丢弃→onCancel一次→无残留窗口。
- 开发日志现在同时写应用沙箱`filesDir/logs/app-dev-YYYY-MM-DD.log`和HiLog；
  对话框各层共用请求TraceID，包含到达、前置拒绝、渲染、校验、回调、关闭、响应和异常，不写用户输入内容。
  设备自检实际读回文件确认`auditFile=true`，不是仅声称落盘。
- 验证：最终签名构建`logs/ui-host-build5-20261013.log`、覆盖安装Smoke PASS；
  Node UI控制流14项、历史/阅读器75断言、HTML用例通过；最新设备历史4组与收藏10项通过。
  测试前历史29条，无卸载、无清空用户数据；隔离数据库用例自动清理，没有生成阅读样本。
- 证据：`logs/ui-dialog-device-final/`（24份逐步页面树+审计记录）、
  `logs/ui-host-final-app-evidence.log`（只保留最终PID，含UI结果与4+10回归）；
  复现：从历史页运行`tools/ui_dialog_device_cases.ps1 -CliPath <实际devecocli的cli.js路径>`。
- **边界**：未测验证码图片、真实站点登录、真实有副作用设置callback；未运行完整深度源矩阵，不等于全功能对齐。
  此前CLI记录中的UI崩溃已修复，不能继续当作当前阻塞。后续推进函数型设置validator/动态选项、HTML兼容及源矩阵。

## 2026-10-13 CLI 自动签名与新包上板（最新，覆盖此前签名阻塞）

- **不操作电脑 GUI**。技能 `references/ai-development-tools.md` 要求优先使用 DevEco CLI，以实际 `--help` 确认命令。
- 已通过 npm 获取 `@deveco/deveco-cli@1.3.5`，本机设置 `DEVECO_CLI_STUDIO_PATH=C:\Program Files\Huawei\DevEco Studio`。
- CLI 最初 `auth status` 为未登录，`signature generate` 提示先登录；
  `auth login --no-prompt` 成功后，**自动签名直接成功**，无需用户手工迁移材料或操作 IDE 签名页面。
- CLI 自动生成 p12、csr、证书及 profile，写回 `build-profile.json5`。生成的秘密字段不输出到报告。
- `build --product default --build-mode debug` 构建成功；
  `run --skip-build --module entry --device <device-id> --ability EntryAbility --product default`
  覆盖安装成功、Smoke PASS，**没有使用 `--uninstall`**。历史页面确认29条保留。
- 新包冷启动（PID38506，21:12:24）确认 `invokeFunction round-trip OK (sync, async, throw)`、
  `RSA-1024 PKCS1 decrypt vector OK`；AES/GBK/Cookie也通过。RSA只证明这一组1024位单块向量。
- **UI自检发现真实崩溃**：21:14:29，`TypeError: Cannot read property observeComponentCreation2 of undefined`，
  栈指向 `veneraUiDialogBuilder`（`UiDialog.ets:250`）、注册闭包（`:262`）。
  无组件宿主的全局builder调用需要修复，不能写UI通过；应用已重启、数据未清空。深度矩阵仍未运行。
- 证据：`logs/devecocli-signature-result-20261013.log`、`logs/devecocli-signed-build-20261013.log`、
  `logs/devecocli-deploy-20261013.log`、`logs/devecocli-history-post-install-20261013.log`、
  `logs/device-new-package-evidence-20261013.log`、`logs/ui-dialog-jscrash-detail-20261013.log`。
- 可重复CLI入口（已有签名不要用 `--force` 随意覆盖）：

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Program Files\Huawei\DevEco Studio'
npx --yes --package=@deveco/deveco-cli@1.3.5 devecocli auth status
# 仅未登录时执行：
npx --yes --package=@deveco/deveco-cli@1.3.5 devecocli auth login --no-prompt
npx --yes --package=@deveco/deveco-cli@1.3.5 devecocli signature generate --product default
npx --yes --package=@deveco/deveco-cli@1.3.5 devecocli build --product default --build-mode debug
npx --yes --package=@deveco/deveco-cli@1.3.5 devecocli run --skip-build --module entry --device <device-id> --ability EntryAbility --product default
```

## 2026-10-13 设备重新连接：旧安装版本回归（最新）

- 设备 `<device-id>` 已连接且可启动。**签名尚未恢复，因此没有安装工作区的新包**。
- 手机现有版本没有 UI 对话框自检/深度开关；RSA 与 `invokeFunction` 仍待新包上板。
- 实测启动离线桥/AES/GBK/Cookie通过；历史逻辑4组、收藏夹逻辑10项通过。测试前后历史29条，测试后仅默认收藏夹0条，无新增阅读样本。
- 旧版源自检本轮4/22（分母含local/demo_api，实际20个JS源），单词单页单章浅取样；不等于完整L0–L3验收。通过：hcomic、hitomi、nhentai、**ManHuaGui v1.2.1**。历史“ManHuaGui上游即坏”不得套用这个已安装版本。
- `shonen_jump_plus` 的 `code 401: Parameter error` 是SDK参数错误，不能写成HTTP401。
- 完整边界、日志与图片尺寸见 [DEVICE_ACCEPTANCE_2026-10-13.md](DEVICE_ACCEPTANCE_2026-10-13.md)。流式抓取已停止，未卸载或清空应用。

## 2026-10-13 换机 + RSA + 源验收取样深度（最新，优先读）

### 工程已搬到另一台机器（**环境段落需按此修正**）

- 当前路径 `<repo>`，用户是 **root**；本文档“一、环境”里所有 `C:\Users\<user>\...` 只适用于上一台机器。
- 本机 **没有** `C:\Users\<user>\.ohos`，也没有设备（`hdc list targets` → `[Empty]`），**无模拟器镜像**。
- 因此 `build-profile.json5` 的 `signingConfigs`（指向 `C:\Users\<user>\.ohos\config\*.p12`）已**整块注释**，`products[0].signingConfig` 也注释掉：否则 `hvigorw assembleHap` 在 `SignHap` 阶段报 `00303107 Invalid storeFile`。现在产出 `entry-default-unsigned.hap`。
  装机时按注释里的步骤在 DevEco 重新生成签名（需华为账号 + 设备 UDID），再把那行取消注释。
- 本机工具链可用：DevEco `C:\Program Files\Huawei\DevEco Studio`（JBR JDK 25 / 自带 node v24.14.1 / sdk `default`），构建命令不变。
- **上游源码不在本机**（`C:\Users\<user>\AppData\Local\Temp\vsrc` 不存在）。需要逐行对照时按仓库现下载：`venera-app/venera`（`lib/foundation/js_engine.dart` 是 `convert`/桥的语义基准）、`venera-app/venera-configs`（33 个源脚本，`_venera_.js` 是模板）。

### 本轮代码改动（**只过了编译与离线测试，全部未上板**）

1. **`convert` 补上 RSA 私钥解密**（`JsMessageHandler.rsa`）：base64 PKCS#8 → DER 直读 → `createAsyKeyGenerator('RSA1024'|…)` + `convertKeySync(null, der)` → `RSA<size>|PKCS1` 解密，按模长分块（对齐 upstream `_processInBlocks`）。
   - 模长从 DER 里取（PKCS#8 → OCTET STRING → PKCS#1 → `INTEGER n`，去掉 ASN.1 符号零字节），据此选 `RSA1024/2048/3072/4096/8192`。
   - `isEncode === true` 返回 `null`（upstream 只实现解密）；输入不是模长整数倍时返回 `null`（upstream 会抛异常→null），不做静默截断。
   - 与 upstream 的唯一差异：upstream 返回 `numBlocks*(k-11)` 且尾部留零，这里只返回拼接后的明文（调用方都是扫第一个 `{`/`[`）。
2. **新增 RSA 离线向量**：`tools/rsa_reference_vectors.js`（`--generate` 出向量，默认用 `node:crypto` 的 `privateDecrypt` 复核向量本身）。同一组常量写进 `JsEngine.verifyBridgeContracts`，设备启动时 hilog 会打 `RSA-1024 PKCS1 decrypt vector OK` 或 `RSA PKCS1 decrypt vector MISMATCH: …`。
3. **源自检按 SOURCE_ACCEPTANCE 加深取样**（`SourceSelfTest`）：
   - **L1 每次都打**（离线、便宜）：`<key> | L1 | v… | caps=… | settings=N | account=password|web|cookie|none`。`thumb` 位目前恒缺（`onThumbnailLoad` 未接入），这本身就是结论。
   - **L2/L3 深度取样由 `sourceSelfTestDeep` 控制（默认 false）**：探索**全部**页 + 第 2 页 + 原始 part 结构（`L2 explore[i] parts | 名称=条数`，空 part 标 `!`）、分类**全部** part 且每 part 取前 2 项、搜索 **2 关键词 × 2 页**（CJK/ASCII 各一，且校验第 2 页与第 1 页 id 指纹不同）、只提供 `loadNext` 的源走「null 游标 → 返回游标」两跳；章节取**首/中/末**，每章取**首/中/末三张**图并解码。
   - 开关：`历史 → 离线可用性验收 → 源自检深度取样`（`Settings.sourceSelfTestDeep`，下次启动生效）。
   - 默认（非 deep）行为与之前一致：单章 + 封面/首张/末张解码，避免每次启动几十次图片请求触发风控。

### 本轮验证状态（**别把它当功能验收**）

| 检查 | 结果 |
|---|---|
| `hvigorw assembleHap` | ✅ **BUILD SUCCESSFUL**（[日志](<../dist/acceptance-depth-build1.log>)），0 error；新增告警只有 3 条，都是 RSA 三处 `cryptoFramework` 调用的“可能抛异常”lint（与同文件 AES 处同类，已被 try/catch 兜住）；`SourceSelfTest.ets` 零告警 |
| 产物 | `entry/build/default/outputs/default/entry-default-unsigned.hap`（4.74 MB，**未签名**） |
| `node tools/rsa_reference_vectors.js` | ✅ PASS（128 字节块 → 明文与期望一致） |
| `node tools/aes_reference_vectors.js` | ✅ 与 `JsEngine` 内嵌四向量一致 |
| `node tools/html_engine_cases.js` | ✅ ALL PASS |
| `node tools/history_reader_cases.js` | ✅ PASS 75（本轮未改相关文件，作回归对照） |
| 设备 / 上板 | ❌ **无设备**：RSA 向量、L1/L2/L3 深度取样、UI 对话框、`invokeFunction` 全部**未上板**，不得声称通过 |

### 下一步（按顺序）

1. 接设备后先看 hilog：`bridge contracts OK` / `invokeFunction round-trip OK` / `RSA-1024 PKCS1 decrypt vector OK` / `AES-128 … vectors OK` / `GBK … OK`，再跑 `历史 → 离线可用性验收` 的 UI 对话框自检。
2. 打开 `sourceSelfTestDeep` 跑一次完整矩阵（会明显变慢、请求变多），按 SOURCE_ACCEPTANCE §9 的记录格式逐源归档。
3. 仍未做：`compute`、`onThumbnailLoad`、HTML 引擎选择器覆盖面（wnacg 仍失败）、详情页/阅读器余下功能（见 `FEATURE_PARITY.md`）。

## 2026-10-13 UI 对话框桥 + 源验收细则（最新，优先读）

- 新增**原生 `invokeFunction(handle, args)`**（`napi_init.cpp`）：脚本回传给应用的回调（`UI.showDialog` 的 action、`showInputDialog` 的 validator、`showLoading` 的 onCancel、动态设置/分类 loader）此前只是不透明句柄，ArkTS 无法调用；现在补齐 JS→ArkTS→JS 往返（同步值、Promise、异常三类）。
- 新增 `source/UiBridge.ets`（请求模型 + 串行队列，避免两个对话框重叠）+ `components/UiDialog.ets`（dialog/input/select/loading 四种渲染，含验证码图片显示）。`AppInit` 在 `JsEngine.init()` 后 `installUiDialog()`；`JsMessageHandler` 的 `UI.*` 五个分支已实现（含 upstream 的校验：validator 非函数忽略、initialIndex 越界丢弃、无 actions 时给「确定」）。
- 修复 ArkTS 类型：`CustomBuilder` 是函数类型，`wrapBuilder()` 返回的 `WrappedBuilder` 不能直接传；改为注册闭包。`JsEngine.callJson` 返回 `Object | null`，调用处必须按可空声明。
- **本地状态**：`hvigorw assembleHap` **BUILD SUCCESSFUL**（[日志](<../dist/ui-dialog-build4.log>)）。**设备已断开，UI 对话框与 `invokeFunction` 全部未上板验证**，不得声称通过。上板后先看 hilog 的 `invokeFunction round-trip OK (sync, async, throw)`，再在 `历史 → 离线验收 → 运行 UI 对话框自检（需手动操作）` 逐项点击。
- 新增 [SOURCE_ACCEPTANCE.md](<SOURCE_ACCEPTANCE.md>)：**逐源验收完整分级细则**（L0 离线契约 / L1 注册解析 / L2 静态元数据 / L3 全链路 / L4 交互 / L5 站点专项），含「测到多细」的硬性取样要求（search ≥2 关键词×≥2 页、explore 全部 part、category 全部 part 前 2 项、章节取首/末/中、每章取首/中/末三张且必须 ImageKit 解出真实尺寸）、A/B/C 三类归因与 C 类强证据要求、设备执行命令与记录格式。
- 现状（以最新日志为准）：L0 🟡（RSA 未实现、invokeFunction/UI 未上板）、L1 🟡、L2 🟡（取样深度不足）、L3 🟡（每章只测 1 章、无中段取样）、L4/L5 ❌。

## 2026-10-13 阅读器七种模式 + 目录

- 上游 `enum ReaderMode` 的**7 种模式全部实现**：三种翻页方向（右→左/左→右/上→下）+ 连续上→下 + 瀑布流 + 连续左→右 + 连续右→左。新增 `features/ReaderModes.ets`（纯逻辑：规范化/分类/轴/反转/索引映射/标签/循环），`ReaderPage` 按模式选 Swiper 或 List。
- **关键不变量**：反转只改显示顺序，不改存储页码；`toDisplayIndex/toActualIndex` 双向映射，`displayOrder` 不修改原数组。设备上六次切换模式底栏始终 `1 / 3`，右→左模式截图与页码一致。
- 新增**目录浮层**：列全部章节、标“阅读中”、点击跳转；顶栏标题与底栏「目录」都能打开。顶栏显示 `第 n/N 章 · 章节名`。
- 模式写入 `Settings.readerMode`，强制停止重进后仍保留（设备验证 `连续（右→左）`）。
- 证据：`node tools/history_reader_cases.js` → **PASS 75**（28 位置/时钟 + 17 模式 + 19 控制流 + 11 冷启动/渲染）；构建 [日志](<../dist/reader-modes-build2.log>)；设备截图 [右→左第1页](<../dist/history-usability/mode-rtl-p1.jpeg>)。测试后模式已改回原值 `翻页（右→左）`，离线样本已清理，历史恢复 28 条。
- 完整边界见 [USABILITY_READER.md](<USABILITY_READER.md>)。**未做**：手势（点击/长按/双击缩放/拖动/音量键）、双页拆分、亮度、自动阅读、墨水屏刷新、分组章节树、大章节列表虚拟化、异尺寸远程图片滚动锚点。
- ArkTS 注意：`List` 没有 `listDirection` 构造参数，必须用 `.listDirection(Axis.Horizontal)` 属性，否则编译报 `ListOptions` 未知属性。

## 2026-10-13 收藏夹迭代

- 修复三个**真实应用缺陷**（都不是源规则问题）：①取消收藏残留——`isFavorite()` 查任意夹但只删默认夹，导致命名夹/多夹时界面显示“未收藏”而记录仍在；②空收藏夹无法存在——`folders()` 由 `DISTINCT folder` 推导；③完全没有收藏夹管理 UI。
- 新增 `favorite_folders` 表（名称+顺序），升级时从既有 `favorites.folder` 播种，不删表不清空。`''` 为移植版默认收藏夹（上游强制命名夹，差异已记录在代码与文档）。
- `FavoritesDao` 按上游重写：文件夹 CRUD/顺序、add（重复返回 false）、move/copy（目标已存在则 no-op，插入用 `MIN-1`，对齐 Dart `minValue(target)-1`）、batchMove/batchCopy/batchDelete/reorder、foldersOf/isFavoriteIn；名称校验对齐 `validateFolderName`（空/超50字/双引号/重名拒绝）。
- 书架页：收藏夹条 + 新建/重命名/删除夹 + 前移/后移 + 多选（全选/取消/移动/复制/移除），破坏性操作均有确认。详情页“收藏”改为**按收藏夹加入/移出面板**，长按=`quickFavorite`（只加默认夹，已存在 no-op）。
- 设备证据（16:03–16:08）：`HM验收夹` 新建后强制停止重进仍在（空夹持久化）；删除夹确认后仅剩 `默认收藏夹（0）`；详情页面对离线样本 `加入`→`已收藏`、`移出`→`未收藏`；测试后收藏夹与收藏数恢复原状。设备隔离回归 **10 条 PASS**（多夹共存、单夹移除不影响其它夹、move no-op、copy、夹内排序、夹顺序、重命名保留归属、默认夹保护、删除夹清理）。构建 [日志](<../dist/fav-build1.log>)；阅读回归仍 49/49（[日志](<../dist/fav-history-cases.log>)）。
- 完整证据与未覆盖项见 [USABILITY_FAVORITES.md](<USABILITY_FAVORITES.md>)。**未做**：拖拽排序（现为前移/后移）、筛选、网络收藏夹、folder_sync 绑定、稍后读/追更夹/moveFavoriteAfterRead、JSON 导入、封面本地缓存、translated_tags；批量移动/复制的 UI 仅有逻辑回归覆盖，未做设备全流程点击。
- 工作区仍无 `.git`，不能声称通过 Git diff 检查。

## 2026-10-13 阅读历史/续读迭代

- 用户进一步要求：除确证源规则自身问题外，其余应用场景要与原版一致并通过可用性检测。**目前远未达成**，不要把缺功能或HM桥接错误算作源问题。
- 已新增 [HistoryPage](<../entry/src/main/ets/pages/HistoryPage.ets>)（顶栏历史入口、100条分页、详情/续读、确认删除、多选）与 [UsabilityPage](<../entry/src/main/ets/pages/UsabilityPage.ets>)（隔离逻辑回归和可清理本地样本）。
- 历史数据库原地加source_key/ep_id，不丢旧数据；原子UPSERT替代SELECT+REPLACE；精确源识别替代首页猜第一个源。旧记录用1-based章序号，新增记录用稳定章ID；失效/空/失败不覆盖原记录。
- 设备确认：已有28条历史保留；本地样本第2章第2页在分页和瀑布流都通过强制停止后恢复，真实PNG/底栏对应；上下章成功；删除确认取消成功；测试样本已清理、最终28条，阅读模式恢复“翻页”。
- 上板发现并修复：progressReady非State导致底栏长期“— / —”；瀑布流继承Cover导致图片裁切。最终图片见 [截图](<../dist/history-usability/waterfall-fixed.jpeg>)。
- [生产逻辑回归](<../tools/history_reader_cases.js>) Node49条通过（要求Node>=22.13，不等于ArkTS/设备测试）。设备数据库回归4组PASS。最终构建 [日志](<../dist/history-build4.log>)，最新signed HAP已安装。
- 完整可复现范围/未验收项见 [USABILITY_HISTORY.md](<USABILITY_HISTORY.md>)：分组章节、已读章集合更新、统计/元信息刷新、全部删除UI、大数据分页、远程异尺寸瀑布锚点尚未验收或实现；其他模块继续看功能清单。
- 工作区没有.git，git status/diff不能用；不能声称通过Git diff检查。设备snapshot_display使用JPEG，PNG在当前设备不生成文件。

## 2026-10-13 源运行时接续记录

- **不是照搬原项目后端，更未完成特性对齐**；模型/源/页面只迁移一部分，QuickJS NAPI 桥和 HTML 引擎自行实现。功能缺口见 [FEATURE_PARITY.md](FEATURE_PARITY.md)。
- 修复原生 `callJson` **单一全局 deferred**：多个 Promise 现在按独立编号结算；同时修复 Uint8Array 子视图忽略 offset/length。启动离线双并发反序完成及子视图测试在设备 hilog `bridge contracts OK`。
- 按原版 parser.dart 实现 **只提供 `search.loadNext` 的源**首次传 null 游标；设备离线 `ehentai loadNext-only search registered` PASS。登录成功按原版只看是否抛错，登出调用源 `account.logout`，源管理登录状态改读 SourceDataStore；**真实账号登录尚未验证**。
- 分类读取原版 `category.parts`/`name`/`target`，兼容旧字符串标签，CategoryView 使用 `target.attributes.category/param`；设备离线 `hcomic category 29 items with target attributes` PASS。动态分类、随机抽取和 search-target 跳转未完成。
- `init()` 改为注册后约 50ms 调用（设备记录 `jm init() completed` / `copy_manga init() completed`）；完整功能链路未因此验收。
- AES 已纠正 ECB/CBC `NoPadding` 及 CFB/OFB 分段反馈；设备对照 OpenSSL 的 **AES-128 ECB/CBC/CFB8/OFB128** 四个向量 PASS。其他密钥尺寸/反馈段长、RSA、真实 jm 功能仍待验。
- 设备 **不支持** `iconv_open("GBK","UTF-8")`，故生成打包了 21,791 对 Unicode→GBK 表；设备 `GBK encode Chinese vector OK: 中=d6d0`。其他字符需持续验证。重新生成：`python tools/generate_gbk_table.py`。
- 自检完整源数现在为 **22**（原 21 源遗漏 ehentai）；历史 3/21 的全链路 PASS 不是最新通过率。每次启动自动全链路；六关键词额外扫描改为**默认关闭**，仅 `sourceSelfTestKeywordSweep=true` 时开启，避免风控/长时间网络阻塞。
- 已新增 `pages/SourceSettingsPage.ets`：已安装脚本中的「源设置 ›」入口，静态 input/select/switch 显示与保存（用户值优先/默认值回退）；Komga 设置默认 URL 及非法 URL 校验已上板验证，**Picacg select/switch 与重启持久性尚未验收**，函数 validator/callback/动态选项未实现。用户输入 `invalid` 测试后已将 Komga 地址恢复为 `https://demo.komga.org`。
- 新增 `network/CookieJar.ets` + SQLite cookies 表：脚本 `Network.setCookies/getCookies/deleteCookies` 同步可见且同步落盘，HttpClient 显式注入 Cookie 并保留原始 Set-Cookie 数组。设备离线 PASS：host-only/Domain/Path/Secure/Max-Age、清内存重载 SQLite、QuickJS 同步调用。**真实站点登录、响应多 Set-Cookie 实际 SDK 形状及 Cookie 对网络请求的端到端效果仍待验**。域/路径/Secure 改为安全规则，和上游宽松匹配有意不字节等价；尚未接入完整公共后缀表。
- Picacg `SourceSettingsPage` 上板显示 base_url、Image quality=`original`、App channel=`3`、Favorite sort=`New to old`；**真实点击 Old to new→强制结束进程→重进显示仍为 Old to new**，然后恢复原 New to old 并再次重启确认。Happy `originalImage` switch false→true→重启仍 true，最终恢复 false 且再次重启确认。Happy `cacheTTL` 数值选项 2592000000（一月）→0（当次）→重启仍当次，最终恢复一月并重启确认。Komga 测试后地址已恢复 `https://demo.komga.org`。
- 源设置 `callback` 已有按钮文案和 async busy 状态；设备无副作用模拟源回调通过 `this` 绑定及 Promise 回程离线测试，**真实清缓存等有副作用动作未点击**；函数 validator 和动态选项仍不支持。
- 下次重点：设置 UI 余下分支、真实 Cookie HTTP 收发、compute、RSA、阅读器与书架功能；不要把构建成功或离线向量通过写成特性完全一致。
- （后续轮次已推进：收藏夹管理、历史页与续读见本文件顶部两条记录。）

---

## 一、环境

### 1.1 目标与工程

| 项 | 值 |
|---|---|
| 上游项目 | `CyrilPeng/Venera-Next` v1.17.0+228（Flutter，230 个 Dart 文件 / 67,420 行） |
| 移植目标 | 原生鸿蒙 ArkTS/ArkUI 重写 |
| 工程目录 | `<repo>` |
| bundle | `com.venerahm.reader`，Ability `EntryAbility` |
| 目标平台 | HarmonyOS `6.0.1(21)`，`runtimeOS: HarmonyOS` |

### 1.2 工具链

| 组件 | 路径 / 版本 |
|---|---|
| DevEco Studio | `C:\Program Files\Huawei\DevEco Studio`，`DS-243.24978.46.36.601251` |
| hvigor | `6.21.1`（`tools\hvigor\bin\hvigorw.bat`） |
| HarmonyOS SDK | 自带 `sdk\default`，`6.0.1.112 / API 21 / Release` |
| JBR | `jbr\bin\java.exe` |
| Node | 自带 `tools\node\node.exe` |
| ohpm | `tools\ohpm\bin\ohpm.bat` |
| hdc | `sdk\default\openharmony\toolchains\hdc.exe` |
| TypeScript（做类型检查用） | `D:\ohos-sdk\ets\ets\build-tools\ets-loader\node_modules\typescript`（4.9.5-r4） |

### 1.3 构建命令（每次都要设这三个环境变量）

```powershell
$deveco = "C:\Program Files\Huawei\DevEco Studio"
$env:JAVA_HOME = "$deveco\jbr"
$env:DEVECO_SDK_HOME = "$deveco\sdk"
$env:PATH = "$deveco\tools\hvigor\bin;$deveco\tools\ohpm\bin;$deveco\tools\node;$deveco\jbr\bin;$env:PATH"
cd <repo>
& "$deveco\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap
```

产物：`entry\build\default\outputs\default\entry-default-signed.hap`

### 1.4 签名（关键，否则装不上）

已配置自动签名，材料在 `C:\Users\<user>\.ohos\config\`（`.cer` / `.p12` / `.p7b`）。

`build-profile.json5` 必须**同时**有两处，缺一则只产出 unsigned：
- `app.signingConfigs[]`（DevEco 写入）
- `app.products[].signingConfig: "default"` ← **DevEco 不会自动加，必须手工补**

```bash
hdc install -r <signed.hap>          # 未签名会报 error: no signature file
```

### 1.5 设备

| 项 | 值 |
|---|---|
| 设备 ID | `<device-id>` |
| 前提 | **屏幕必须解锁**，否则 `aa start` 报 `10106102 The device screen is locked` |
| 启动 | `hdc shell "aa start -b com.venerahm.reader -a EntryAbility"` |
| 重启 App | `hdc shell "aa force-stop com.venerahm.reader"` 再 start（`aa start` 对已运行的应用只是切前台，不会重跑 init） |

### 1.6 自动化验证闭环（已建成）

```bash
pwsh -File tools\e2e.ps1 -Action run      # build + install + launch + 读界面文字
pwsh -File tools\e2e.ps1 -Action logs     # 拉本应用日志
pwsh -File tools\e2e.ps1 -Action ui       # 导出当前界面所有文字
pwsh -File tools\e2e.ps1 -Action tap -X 100 -Y 200
pwsh -File tools\e2e.ps1 -Action shot     # 截图到 dist/
```

**流式抓日志**（重要：`hilog -x` 是一次性 dump，跑 2 分钟以上的自检会被系统日志挤掉缓冲区）：

```powershell
$proc = Start-Process -FilePath $hdc -ArgumentList 'shell','hilog' `
        -RedirectStandardOutput "$env:TEMP\hl.log" -NoNewWindow -PassThru
# …启动 App、等待…
Stop-Process -Id $proc.Id -Force
Get-Content "$env:TEMP\hl.log" | Select-String 'SelfTestReport'
```

其他可用能力（均已验证）：
- `uitest dumpLayout -p /data/local/tmp/l.json` → 拉取界面树（含所有文字与坐标）
- `uitest uiInput click/swipe/keyEvent` → 模拟点击/滑动/按键
- `snapshot_display -f /data/local/tmp/shot.jpeg` → 截图

**不可用**：agent 侧 `plugin_manager` 工具在本 profile 被 `disabled: true`，无法自动装插件。
**沙箱文件不可读**：`/data/storage/el2/base/haps/entry/files/` 属应用私有，`hdc file recv` 报 permission denied —— 自检结果只能走 hilog。

---

## 二、架构（三层，务必分清哪层是"移植"哪层是"自建"）

| 层 | 上游对应物 | 说明 |
|---|---|---|
| **数据/存储/源契约/UI** | ✅ 有（`models.dart`/`favorites_manager.dart`/`source.dart`/`main_page.dart`…） | 部分迁移且仍有缺陷；本轮就在历史存储/源路由/ArkUI中修复多项，不得称基本无bug |
| **ArkTS ↔ QuickJS 桥** | ❌ 无（上游是 `flutter_qjs`，Dart FFI 直连、无序列化） | **自建，当前所有 bug 的重灾区** |
| **HTML/CSS 解析引擎** | ❌ 无（上游用成熟库 `package:html`） | **自建，第二重灾区** |

**结论**：HM独有缺陷可能出在任意层。必须用原版对照、确定性回归与真实设备UI分别定位，不能将存储或UI问题自动归因于桥或源规则。

### 2.1 原生模块（entry/src/main/cpp）

```
CMakeLists.txt          QuickJS 静态库 + libvenerajs.so（NAPI）
js_engine.h/.cpp        QuickJsRuntime：EvaluateRaw / JsonStringify / PumpJobs
napi_init.cpp           导出：quickjsVersion / evaluate / callJson /
                        setMessageHandler / setGlobalString
value_bridge.h          【已写未接入】JSValue ↔ napi_value 深互转（见待办 ①）
quickjs/                vendored quickjs-ng 0.17.0（19 文件 2.77 MB）
types/libvenerajs/      给 ArkTS 的 d.ts + oh-package.json5
```

**领域陷阱（务必记住）**：`napi_get_global()` 返回的是 **ArkTS 的全局对象**，不是 QuickJS 的。
给脚本用的全局（`sendMessage`、`appVersion`）必须用 `JS_GetGlobalObject(ctx)` 装进 **QuickJS** 全局。

**`PumpJobs()` 是关键**：ArkTS Promise 落定时必须 pump QuickJS job queue，否则脚本里的 `await` 永远不会恢复。

### 2.2 JS 侧（resources/rawfile）

| 文件 | 作用 |
|---|---|
| `init.js` | **上游原样，绝不修改**（38 KB，定义 Network/Convert/HTML/ComicSource/UI 等） |
| `sendmessage_shim.js` | 把 `__nativeSendMessage` 包装成 `sendMessage`；处理 `Map→对象`、字节标记 |
| `html_engine.js` | **手写的** HTML 解析 + CSS 选择器（待办 ② 要换成成熟库） |

加载顺序：`init.js` → `sendmessage_shim.js` → `html_engine.js`（后者再包一层 `sendMessage`，`html` 消息不落到原生）。

### 2.3 ArkTS 侧（entry/src/main/ets）

```
foundation/   AppContext(含 APP_VERSION=1.17.0) / Settings / AppInit / Log / Semver
model/        Comic / ComicDetails / ComicType(FNV-1a) / Res / RouteParams
network/      HttpClient(@ohos.net.http, 重试+超时+自解码) / ImageLoader(磁盘缓存+PixelMap)
storage/      Database(relationalStore) / FavoritesDao / HistoryDao / SourceDao
source/       ComicSource 契约 / JsEngine / JsMessageHandler(分派表) /
              JsComicSource+ComicSourceParser / SourceManager / SourceInstaller /
              SourceRepository / SourceDataStore / SourceSelfTest / JsRuntime
features/     HomeView / BookshelfView / ExploreView / CategoryView / SearchView / SettingsView
pages/        Index(4 Tab+顶栏) / ComicDetailsPage / ReaderPage /
              SourceManagerPage / SourceRepositoryPage / SearchPage / SettingsPage
components/   ComicWidgets(AsyncComicImage/ComicCell/状态视图) / LoginDialog
```

---

## 三、验证方法（判断"能不能用"的唯一标准）

App 启动时自动跑 **`SourceSelfTest`**：对每个可搜索源走完整链路并写 hilog（TAG `SelfTestReport`）：

```
explore → search → details → chapters → loadEp → 封面下载+解码 → 首页下载+解码 → 末页下载+解码
```

**PASS 的含义**（这是严格标准，别放宽）：
```
<key> | PASS | search->details->NN pages, cover+first+last decoded
```
即：搜索有结果、详情有标题、章节有图、**封面/首页/末页三张图都下载成功且用 ImageKit 解码出真实像素尺寸**。

只报"字节数 > 64"是不合格的判定 —— 错误页和截断文件也能超过 64 字节。

---

## 三·补、本轮进展（真值桥 + 忠实翻译，**未做设备回归的项已标注**）

### 已完成的代码改动（均已编译通过；**设备验证状态见下表**）

| # | 改动 | 位置 |
|---|---|---|
| 1 | `sendMessage` 桥彻底去 JSON：`JsToNapi`/`NapiToJs` 深互转，含 Map/Set/ArrayBuffer/Uint8Array/Date/BigInt/函数句柄 | `cpp/value_bridge.h`、`cpp/napi_init.cpp` |
| 2 | `sendmessage_shim.js` 从 108 行缩到 20 行：只做 `sendMessage → __nativeSendMessage` 绑定 | `resources/rawfile/sendmessage_shim.js` |
| 3 | `handleJson(string)` → `handleMessage(Object): Object \| null \| Promise<...>`；删 `taggedBytes`/`stringify`/`__bytes__` | `ets/source/JsMessageHandler.ets` |
| 4 | **`callJson` 不再走 `JSON.stringify`**，改为 `JsToNapi` 深转换，签名 `Promise<Object>` | `cpp/napi_init.cpp`、`ets/source/JsEngine.ets`、`cpp/types/libvenerajs/index.d.ts` |
| 5 | `JsComicSource` 11 处 `callJson` 调用点全部改为「值进值出」，删掉 `JSON.parse` | `ets/source/JsComicSource.ets` |
| 6 | 探索页 `type` 改为按**字符串**判定（`mixed`/`multiPartPage`/`singlePageWithMultiPart`/`multiPageComicList`） | `ets/source/JsComicSource.ets` |
| 7 | `NapiToJs` 支持 ArkTS `Map`/`Set`（否则嵌套 Map 回程变 `{}`） | `cpp/value_bridge.h` |

**第 4 条是本轮最大的一处根因**：`JSON.stringify(new Map())` === `{}`。
凡是用 `Map` 装章节表的源（manhuagui / hcomic / ykmh …）都会丢掉整个章节表，
表现为自检里莫名其妙的 `single chapter` + `FAIL pages`。**这不是修 bug，是补一个上游不存在的序列化层。**

### 设备验证（`venera_fix1.log`，21 源，keyword="a"）

| 源 | 修复前 | 修复后 |
|---|---|---|
| **hcomic** | `FAIL pages 该章节没有图片` | **PASS（38 页，封面/首页/末页全部解码）** |
| ManHuaGui | `single chapter` → `FAIL pages 404` | `13 chapter(s)` ✅（pages 另有一处未修，见下） |
| ykmh | `FAIL pages 章节ID不能为空` | `2 chapter(s)`、`50 image(s)` ✅（图片解码另有一处未修） |
| hitomi | `FAIL explore ArrayBuffer object expected` | 仍 FAIL（原因已定位，见下） |
| **通过数** | 2/21 | **3/21（hcomic 新通过）** |

### 本轮最后一批改动（已编译，设备回归结果如下）

1. `NapiToJs` 恢复 ArrayBuffer / Uint8Array 区分（`napi_is_arraybuffer` → 真 `ArrayBuffer`，
   `napi_is_typedarray` → `Uint8Array`）。上一版把两者都做成 `Uint8Array`，
   而 hitomi 要 `new DataView(resp.body)` → 抛 `ArrayBuffer object expected`。
   ✅ **已验证：hitomi explore 从 FAIL 变 `ok explore | 25 items`**（同一轮里 hitomi 拿到 236/685 页）。
2. `JsMessageHandler.http` 的 `bytes` 分支直接回传 `response.bytes`（`ArrayBuffer`）。
3. 探索页 `type` 按字符串判定（见上表第 6 条）。
4. **`flattenParts` 支持 `{板块名: [漫画]}` 形状**（upstream `parser.dart` 的
   `singlePageWithMultiPart` 就是遍历 `res.keys`）。comick / copy_manga 都是这种形状，
   之前只认 `[{title, comics}]` 数组，所以 `0 items`。
   ✅ **已验证：comick `0 → 102 items`、copy_manga `0 → 51 items`**。
5. **`convert` 补上 AES-ECB/CBC/CFB/OFB + GBK(gb18030)**（`JsMessageHandler.aes`）。
   关键语义：upstream 用 pointycastle 的 `processBlock` 循环做**裸块处理，不剥 padding**，
   所以解密输出里保留填充字节（`jm.convertData` 靠扫第一个 `{`/`[` 来绕开它）。
   ⚠️ 原先用 PKCS7 的说法是错的：它会额外补整块、解密会剥 padding。现已改为
   ECB/CBC `NoPadding`，CFB/OFB 用 AES-ECB 单块原语实现原版的分段反馈逻辑。
   设备已对照 `tools/aes_reference_vectors.js` 的 AES-128 ECB/CBC/CFB8/OFB128 四种向量通过；
   **AES-192/256 与其他反馈段长尚未上板验收，jm 全链路仍未验证。**
6. **自检新增「关键字扫描」**：`a / 1 / 魔法 / ab / love / 海贼` 各搜一次，
   区分「移植坏了」与「这个关键字本来就没结果」。
   实测：Komiic `a:0 / 魔法:100`、comick 只有 `love:50`、hcomic 全关键字 10 条。
   新增设置项 `sourceSelfTestOnly`（填源 key）可只跑单个源，调试时省时间。

### 已确认「上游源自身即坏」，不要再查

| 源 | 症状 | 证据 |
|---|---|---|
| ManHuaGui | `loadEp` 报 `not a function`（stack 指向 `ManHuaGui.js:1040:36`） | `getImgInfos` 定义在 `account` 对象里（`:450`），却在 `comic.loadEp`（`:1040`）用 `this.getImgInfos` 调用；运行时 `this` 是 `comic`，探针实测 `srcGetImgInfos=undefined`。**已从 jsdelivr 下载发布版逐行比对，字节一致，同样有此 bug** |

**教训**：源级失败先分清「我的桥/引擎」还是「源自己坏」。
`_venera_` 仓库的源是社区维护的，确实存在自身不一致。
判定方法：把发布版源下载下来逐行对比 + 在 JS 侧打印真实运行时形状。

### 设备回归（`venera_fix4.log`，21 源）

| 源 | 结果 |
|---|---|
| **hcomic** | **PASS**（38 页，封面/首页/末页全部解码） |
| **nhentai** | **PASS**（36 页） |
| **hitomi** | explore/search/details/pages 全通（236 页），仅 `cover` 因**网络抖动** `2300999` 未过 |
| ykmh | 探索/搜索/详情（2 章节）/50 页图 URL 全通；`page1/page50` 取回 24 KB **非图片** |
| ManHuaGui | 13 章节正确，`loadEp` 报 `not a function`（完整异常未取到，见下） |
| comick / copy_manga | 仍是 `0 items`——但**第 4 条改动是在这次回归之后才编译进去的**，待重测 |

### ⚠️ 回归自检前必须先确认设备网络

2026-10-12 16:2x 之后，设备上的 VPN（`com.follow.clash`）进入坏状态：
国际域名被解析到黑洞 IP 且 100% 丢包。

```
ping www.manhuagui.com → 2a03:2880:f111:83:face:b00c:0:25de（Facebook 段），100% packet loss
ping hitomi.la         → 31.13.69.245（Facebook 段），100% packet loss
ping www.baidu.com     → 正常（国内域名不受影响）
```

表现就是**几乎所有源都报 `网络请求失败: code 2300999: Internal error`**
（连上一轮 PASS 的 hcomic 也会失败）。**这不是代码问题**。

**下次跑自检前先做这个判断**：如果连 `hcomic` / `nhentai` 都 `2300999`，
先让用户重启或换节点，别去改代码。

```powershell
$hdc shell "ps -ef" | Select-String 'clash|vpn'      # VPN 是否在跑
$hdc shell "ping -c 2 nhentai.net"                   # 解析到 Facebook 段就是坏了
```

### 仍然失败且根因已定位的项

| 源 | 症状 | 根因 |
|---|---|---|
| ykmh | `FAIL explore/search \| 403`、`page1/page50 \| 24 KB but not decodable` | 站点反爬/防盗链，疑似 Referer 或 Cookie |
| Komiic | `FAIL search \| 0 results` | **非缺陷**：关键字 `a` 不适用，扫描显示 `1`→19、`魔法`→100 |
| comick | `FAIL search \| Invalid status code: 422` | 站点反爬（探索页 102 items 已通） |
| copy_manga | `FAIL search \| 0 results` | 待查（探索页 51 items 已通） |
| wnacg | `FAIL search \| cannot read property 'text' of undefined` | 手写 HTML 引擎能力不足（见待办 ②） |
| manwaba | `not a function` | 缺 API，需定位方法名 |
| happy / shonen_jump_plus / baozi / ikmmh | `2300999` / `401` / `403` | 受限 header 或站点反爬 |
| picacg / komga | `Not logged in` / `Setting not found` | 源规则要求用户配置/登录 → 需要 `UI()` 对话框（待办 ⑤） |
| ManHuaGui | `FAIL pages \| not a function` | **上游源自身即坏**，见上表 |
| jm | `cannot read property '0' of undefined` | AES 本轮已补，**未验证**；若仍失败则是 RSA/其他 |

### 新增的本地调试工具（**不依赖设备**，很值得用）

```bash
node tools/html_engine_cases.js                                  # HTML 引擎微测试（当前 ALL PASS）
node tools/html_engine_probe.js <file.html> <selector...>        # 用真页面查选择器
node tools/html_probe.js <file.html> <selector...>               # 同上，输出更简洁
```

`html_engine_cases.js` 把 manhuagui 的章节选择器链路做成了断言，改引擎后先跑它。

### 调试经验（本轮踩到，**下次直接用**）

1. **`init.js` 里的 `console.log` 只保留第一个参数**（`log: (content) => ...`）。
   想在 JS 里打多段信息必须先自己拼成一个字符串。
2. **hilog 会把含换行的长字符串按行拆开**，脚本里打多行代码会被打散，重建时按 `VeneraHM: ` 前缀切。
3. 自检卡住/中断多半是**设备息屏或应用被冻结**（`FreezeFreezeUnit`），
   `hdc shell "power-shell setmode 602"` 可保屏常亮；日志里看到 `onBackground` 就要警惕。
4. 要判断「脚本到底产出了什么」，最省事的办法是**在 ArkTS 里对同一个源再求值一次**
   并把结果拼成单行字符串打出来，而不是去猜桥的行为。

---

## 四、当前真实状态

### 4.1 已完成并验证

| 项 | 状态 |
|---|---|
| 源仓库目录解析 + `.js` 下载安装 | ✅ 可用（33 条目录全部通过校验） |
| QuickJS 原生模块（arm64-v8a） | ✅ 编译进 HAP，`libvenerajs.so` 1366 KB |
| `init.js` 在 QuickJS 中运行 | ✅ 自检 `hasSendMessage:true, hasComicSource:true` |
| 22 个源脚本解析注册 | ✅ 0 失败 |
| 一级导航（首页/收藏/探索/分类 + 顶栏搜索/设置） | ✅ |
| 登录功能（账号密码 + 登录/退出按钮） | 🟡 返回值判定已按原版修复、登出调用脚本、状态读 SourceDataStore；**真实账号登录未实测** |
| **全链路 PASS 的源** | **3 个：hcomic（38 页）、nhentai（244 页）、hitomi（685 页）** |
| 探索页可用的源 | 8 个：hcomic / Komiic / manga_dex / nhentai / comick(102) / copy_manga(51) / ManHuaGui / zaimanhua |
| ArkTS ↔ QuickJS 桥 | 🟡 值进值出、并发与子视图已设备离线验证；函数回调/循环对象等边界未完全对齐 |
| `convert` 加密 | 🟡 AES-128 四模式已通过设备向量、GBK 中文“中→d6d0”已上板；其余密钥尺寸/字符待验，**缺 RSA** |
| Cookie 与 HTTP | 🟡 同步 JS set/get/delete、SQLite 冷缓存重载与域/路径/安全过滤已上板离线 PASS；真实响应和登录未验收 |
| 前端功能对齐 | ❌ **远未完成** —— 详情页/阅读器/历史/图片收藏/追更/下载/WebDAV 全缺，见 `docs/FEATURE_PARITY.md` |

### 4.2 当前失败分类

本表过去混入多个**现已修复**、未经证实就标“我的”的历史猜测（例如 hcomic/ManHuaGui），
不应再作现状使用。现状以本文件上方“仍然失败”表和 `FEATURE_PARITY.md` 为准；
每轮设备源矩阵须区分“网络故障 / 源站返回 / 上游源脚本缺陷 / 移植实现缺口”。
**未观察到上游与 HM 同请求响应时，不可把 403/422 一概归因于源站。**

---

## 五、继续任务（按优先级）

### ① 接入真值搬运，替换 JSON 字符串桥 —— 🟡 **主链路已完成，边界仍需持续验收**

**为什么**：上游 `flutter_qjs` 是 Dart FFI 直连，`JSValue ↔ Dart 值` 原生互转、**零序列化**。
我用 JSON 字符串当交换格式 → `new Map()` 变 `{}`、ArrayBuffer 变 `{}`、字节要 base64 打标记、字符串被二次 stringify。
**这些 bug 上游根本不可能有。**

**结果**：`value_bridge.h` 已接入 `sendMessage` 与 `callJson` 两条路径，
shim 缩成 20 行，`handleMessage` 值进值出。
`hcomic` 因此从 `FAIL pages` 变成 **PASS**；`ManHuaGui` 从 `single chapter` 变成 `13 chapter(s)`。

**关键教训（务必记住）**：`callJson` 原来还在用 `JSON.stringify`，
而 **`JSON.stringify(new Map())` 就是 `{}`** —— 凡是章节表用 `Map` 装的源，
整个章节表都在这一步被抹掉，然后表现为 `single chapter` + `FAIL pages` 这种毫无线索的症状。
以后凡见「章节表莫名其妙为空」，先想序列化，别去想 HTML 选择器。

### ② 用成熟 JS 库替换手写 HTML 引擎

**为什么**：上游用 `package:html`（成熟库），我手写了 500 行 → 越界、`undefined`、选择器不准。

**做法**：
1. `npm i htmlparser2 css-select domhandler`（临时目录）
2. 用 esbuild 打成单文件 IIFE，挂到 `globalThis.__htmlLib`
3. 重写 `html_engine.js`：只保留 handle 模型与 21 个子动作的分发，
   底层换成 `parseDocument` / `selectAll` / `selectOne` / `getText` / `getAttributeValue`
4. **`init.js` 与对外 API 完全不动**（`HtmlDocument`/`HtmlElement`/`HtmlNode` 签名不变）

### ③ `parser.dart` 逐行对照翻译（纪律问题）

已因"按理解重写"而非"逐行对照"踩过的坑：
- 探索页 `type` 是**字符串**（`"mixed"` / `"multiPartPage"` / `"multiPageComicList"`），不是数字
- `multiPartPage` 调 `load()`（**无参**），不存在 `loadMultiPart()`
- 单章节源 `epId` 允许为空串（`chapterIds.length` 才是判据）
- 结果可能是 `{data:[...]}` 包裹，不一定是裸数组
- `search.load(keyword, options, page)` 的参数顺序

**要求**：改任何 `JsComicSource`/`ComicSourceParser` 逻辑前，先对照
`C:\Users\<user>\AppData\Local\Temp\vsrc\venera\lib\foundation\comic_source\parser.dart`。

### ④ 剩余功能对齐

见 `docs/FEATURE_PARITY.md`（原版功能逐项状态）。缺口最大的是：
详情页（缩略图/推荐/评论）、阅读器（5 种模式/双页/手势/亮度/自动阅读）、
历史页/图片收藏/追更、本地漫画导入导出、设置全量分区、WebDAV 同步。

---

## 六、已修复的坑（**别改回去**）

| 坑 | 症状 | 修法 |
|---|---|---|
| `napi_get_global` 装错领域 | 脚本看不到 `sendMessage` | 用 `JS_GetGlobalObject(ctx)` 装进 QuickJS 全局 |
| ArkTS Promise 落定不 pump | 脚本 `await` 永不恢复 | `SettleResolve`/`SettleReject` 里调 `Runtime()->PumpJobs()` |
| `APP_VERSION` 用应用自身版本 | 大量源报 `需要应用版本 1.x.0` | 报 **1.17.0**（对齐上游 Venera 版本，源用它做 `minAppVersion` 判据） |
| `callJson` 走 `JSON.stringify` | `new Map()` 章节表变 `{}`，表现为 `single chapter` + `FAIL pages` | 改走 `JsToNapi` 深转换（本轮） |
| 所有字节都做成 `Uint8Array` | hitomi `new DataView(resp.body)` 报 `ArrayBuffer object expected` | `napi_is_arraybuffer` → 真 `ArrayBuffer`；`napi_is_typedarray` → `Uint8Array`（本轮） |
| `explore[i].type` 折成数字再比较 | `mixed` 源走错分支，`0 items` | 按字符串判定，照抄 upstream 的 `switch`（本轮） |
| `NapiToJs` 不认 ArkTS `Map` | 嵌套 Map（分组章节表）回程变 `{}` | `ValueClassName` 判 `Map`/`Set` 后走迭代器（本轮） |
| `napi_get_value_string_utf8` 写 `length+1` 字节进 `length` 大小的 `std::string` | 堆越界 | 先 `resize(length+1)` 再 `resize(length)`（本轮） |
| `JS_GetTypedArrayBuffer` 无条件调用 | 非 typed array 上留 pending 异常，污染下一次求值 | 先用 `JS_GetTypedArrayType(value) >= 0` 判定（本轮） |
| `JS_IsArrayBuffer` 先于 typed array 判定 | Uint8Array 被当成 ArrayBuffer | 两者分开判定（本轮） |
| 同步分支返回已解析对象 | `unexpected token: 'object'` | 约定：`__nativeSendMessage` **始终返回 JSON 字符串**（接入 ① 后此约定取消） |
| `JSON.stringify(Map)` | 章节表变 `{}`，单章节源进不去正文 | shim 的 `encode` 把 Map/Set 转成对象/数组 |
| 阅读器用 `targetEp.length===0` 判有无章节 | 单章节源直接显示"重试" | 改判 `chapterIds.length` |
| `ComicCell` 用 `layoutWeight(1)` | 封面被压成长条 | 改 `aspectRatio(0.72)` |
| HTML 元素动作只读 `key` | 15 个元素级动作全返回 null | 文档 key 在 `message.doc`，元素索引在 `message.key` |
| `http` 无重试、超时 30s | nhentai `code 2300028 timeout` | 超时 60s + 一次退避重试 |
| 列表容器缺失时返回 `null` | `cannot read property 'map' of null` | 数组类动作返回 `[]` |

---

## 七、另外一件未完成的事：dsh-auto-continue 插件

位置：`C:\Users\<user>\Desktop\dev\dsh-auto-continue\`（`package.json` / `cordis.patch.yml` / `index.js` / `README.md`）

作用：`/continue` 开启后，每次 `turn/end` 自动 `Agent.followup("继续")`，带 `maxRounds` 上限（默认 200）防死循环。

**状态**：语法通过、API 取自 dsh 自带包源码；**未安装、未运行验证** —— 因为本 profile 的
`tool-plugin-manager` 是 `disabled: true`。安装需在 Web UI → 设置 → 插件 → 安装 bundle，
目标目录填上面那个绝对路径。

---

## 八、上游源码位置（需要对照时用）

```
C:\Users\<user>\AppData\Local\Temp\vsrc\
├── next\      Venera-Next（上游 Flutter 版，230 dart 文件）
├── venera\    venera-app/venera（parser.dart 语义基准）
└── configs\   venera-configs（33 个源脚本 + index.json）
```

设备上已安装的源脚本在应用沙箱 `files/sources/<key>.js`。
