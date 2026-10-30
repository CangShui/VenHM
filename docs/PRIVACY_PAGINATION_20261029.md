# 2026-10-29：八项需求修正与精简（VenHM 1.0.3）

## 交付状态

源码已完成集成，**61套本地回归及负向对照通过，真实SDK签名编译退出0**。
用户随后明确要求安装，已核对在线实体机和归档包SHA256并成功覆盖安装，[安装证据](<../logs/venhm-103-privacy-pagination-install-20261029.log>)明确`install bundle successfully`，退出0。**未卸载、未清数据、未启动、未截图、未点击、未推送或发布Release**。旧模块数据迁移将在用户首次打开新版时运行；功能手感/真实站点/真机帧率不作已验收宣称。

[新签名包](<../dist/venhm-1.0.3-privacy-pagination-20261029-signed.hap>)：8,069,832字节，
SHA256 `622DA2D3574EAFFC3DAE1BD233A5F8C10C1BA71C4FF789296B64243D2ED0CF25`。
[产物审计](<../logs/privacy-pagination-20261029/artifact.json>)，包名保持`com.venerahm.reader`。

## 1. 自动翻页：每页停留0.1–10秒滑块

[ReaderPage](<../entry/src/main/ets/pages/ReaderPage.ets>)的中部速度菜单改为滑块，左侧0.1s、右侧10s、步长0.1秒，显示当前小数秒。
拖动只改草稿，点击开始/应用后生效；取消不写偏好、不启动自动阅读。提供停止按钮。

真实定时器使用`Math.round(seconds * 1000)`，即100–10000ms，**不只是改文案**。连续/瀑布/横向模式也按这一间隔前进一屏，去掉旧100ms平滑滚动分支。
菜单、加载、布局、滚动与缩放门禁仍保留；图片未就绪会等待，不保证在解码/渲染来不及的硬件上强行做到每100ms一帧。
速度为当前阅读会话选择，不会隐式改全局或设备层。设置页对应滑块支持0.1小数；旧20/30/60秒偏好读取时收敛为10秒，不因旧值使整层配置加载失败。

上一版还存在作用域误述：`setActive`会依据当前启用层写到全局/设备，**不保证当前漫画**。现在模式菜单明确调用`ReaderSettings.set('comic', comicId, sourceKey, 'readerMode', ...)`，写独立`readerModeOverride`，不启用整套漫画偏好、不影响其他漫画或源。

[13项速度/作用域/隐私测试](<../tools/reader_speed_privacy_cases.js>)执行真实ReaderPage、ReaderSettings、HistoryDao、Log方法，验证100ms/10000ms、草稿取消、十进制冷加载、仅当前源+漫画、失败回滚、恢复位置保存失败可重试及迟到失败不覆盖新成功。

## 2. 探索 / 搜索 / tag结果分页

不是全部都能归咎源规则。确认并修正的前端缺口：

- 总页数0代表未知，却被当作只有第一页。
- 探索与标签结果缺少原生Grid滚到底回调。
- 重复数据页被误当最终页，或追加失败后无法稳妥重试。

[SearchView](<../entry/src/main/ets/features/SearchView.ets>)、[SearchSession](<../entry/src/main/ets/features/SearchSession.ets>)、[ExploreView](<../entry/src/main/ets/features/ExploreView.ets>)、[CategoryComicsPage](<../entry/src/main/ets/pages/CategoryComicsPage.ets>)现在有受控`onReachEnd`及明确“更多/重试”后备入口。
只有明确正数页数、真正空尾页或结束/重复游标才停止；短页本身不代表结束。按源+漫画ID去重，重复非空页暂停自动加载但允许手动继续，不伪造EOF；追加失败保留既有列表和页码，重试同页。
切源/切分区/改筛选/刷新/离开会作废旧请求的结果，不能把晚到结果混进新列表。源回调本身未提供中止句柄时属于逻辑取消，不宣称实际网络必定已取消。

**源规则边界：**某些探索区确实声明为单页预览：现有manwaba预览页大小6，ykmh首页部分区块主动截10/15项；它们不是完整搜索结果，不能假定有无限页。
当前六份样本不声明`mixed`；通用mixed探索适配器既存的`load(0)`/maxPage丢失限制没有在这次泛化修复，不能说所有第三方自定义混合区块都已完整分页。正常搜索/分类/tag及多页探索49项生产方法回归已通过；真实远端返回仍待实测。

[49项分页用例](<../tools/pagination_refresh_cases.js>)覆盖页1/2/3、未知页数、数值/不透明游标、重试、重复页、刷新/切源/切分区/筛选/生命周期竞态，固定计数、看门狗与提前退出guard。

## 3 / 5 / 7. 完整移除阅读统计、WebDAV、图片收藏

不是隐藏按钮：三类页面/路由、业务类、DAO、启动注册和设置/书架/长按入口均移除，删除8个专属运行时源文件。
保留普通漫画收藏、网络收藏、追更、图片查看器、下载、本地漫画和继续阅读。

- 阅读计时器、统计会话ID、时长累计字段与SQL、统计表写入已删除。
- 继续阅读只保存恢复位置所需ID/源/章节/页码/封面等，以及原历史列表排序时间；不累计阅读时长/次数，不做独立行为画像。
- [Log](<../entry/src/main/ets/foundation/Log.ets>)的audit/info/debug不再输出或落盘，停止逐页行为诊断文件；升级仅清原应用自有`app-dev-YYYY-MM-DD.log`普通文件，未知文件/链接不触碰。错误警告仅系统HiLog，不写新的应用日志文件。
- [Database](<../entry/src/main/ets/storage/Database.ets>)升级删除仅五个精确旧功能表，不重建/删除history。新历史schema没有时长列；旧SQLite支持时删除旧列，否则只把旧时长值归零。
- [AppInit](<../entry/src/main/ets/foundation/AppInit.ets>)移除旧`webdavEndpoint`偏好。旧用户名/密码仅在页面会话中，不曾持久化，没有额外凭据迁移。
- 旧图片副本只清精确独占目录`filesDir/picture_favorites`内原命名规则的小写UUID.image直接普通文件；不递归，不跟随链接，不删目录或任何下载/local/cache数据。

**清理边界：**无法确定所有权的未知名称、子目录、链接或不安全目录保守保留；不支持DROP COLUMN的系统保留旧空列但值清零。逻辑删除/普通unlink不等同取证级物理擦除。

[11项退役/隐私迁移](<../tools/retired_modules_cases.js>)使用生产迁移+内存SQLite/假Harmony Rdb，验证精确表白名单、保留历史及普通数据、fallback、幂等、失败可重试、目录/链接安全及运行时无退役入口。

## 4. 哪些源有设置与登录能力

范围是本机现有**六份公开规则样本**的实际生产解析结果，不是当前手机安装列表或全网络源总清单。
[能力证据](<../logs/pagination-source-capabilities.json>)通过真实ComicSourceParser/SourceSettings读取静态声明，阻止网络和初始化定时器，不调用登录/验证钩子、不读取真实账户Cookie。

| 源规则 | 源设置 | 登录声明 |
|---|---|---|
| wnacg | 4项：刷新域名、启动刷新开关、域名选择、域名输入 | 用户名/密码 |
| ehentai | 3项：域名、两个事件开关 | WebView + Cookie字段验证 |
| Komiic | 无 | 用户名/密码 |
| manwaba | 无 | 未声明 |
| shonen_jump_plus | 无 | 未声明 |
| ykmh | 无 | 未声明 |

共2个设置源/7字段、3个登录能力源。**真实登录成功验证为0，不能把声明存在说成账号登录已实测可用。**其他用户自行导入源以其脚本声明为准。

## 6. 首页本地漫画恒为1 / 删除后不刷新 / 无法横滑

确认旧实现至少有三类问题：初次reload与通知reload各有一条直接赋值路径，旧请求可覆盖删后新列表；Tab子组件不可靠地收到页面show；本地集合按任意目录计数，空占位/已标记诊断目录也被算进去。

[LocalSource](<../entry/src/main/ets/source/LocalSource.ets>)仅将实际含普通图片文件的目录纳入列表，排除精确自有标记的旧诊断样本；没有删除真实漫画或无标记同名目录。
[HomeView](<../entry/src/main/ets/features/HomeView.ets>)统一版本化本地加载，变更通知、真实[Index](<../entry/src/main/ets/pages/Index.ets>)路由返回/Tab可见性都可刷新；Home/Bookshelf每次await之后先检查生命周期/版本，隐藏时不继续启动DB或封面扫描，旧finally不能清掉新加载状态。
本地栏改横向Scroll，显示全部条目，不再slice前6本。删除/完成仍由实际Queue通知，两View同步重扫。

[45项本地库用例](<../tools/local_library_refresh_cases.js>)覆盖2→1→0、空/metadata目录、精确诊断所有权、8/9漫画不截断、删除通知、旧scan/旧init/旧finally、隐藏工作抑制、host返回和Queue实际完成/delete信号。
这不代表已经读取或核验手机上那个“1”的具体目录，本轮没有连接/操作实体机。

## 8. 下载同时阅读的卡顿

确认的热路径：下载每张图在字节流水线和保存阶段重复完整解码；最多3任务×3页共9路；检查点逐页同步重写全部ledger；逐事件Log同步开写关文件；隐藏首页也会响应每次进度更新并重载。

已做：

1. [ImagePipeline](<../entry/src/main/ets/network/ImagePipeline.ets>)仍实际解码验证，但请求64×64验证图；[DownloadQueue](<../entry/src/main/ets/features/DownloadQueue.ets>)不重复完整解码，磁盘恢复也采用受限解码。
2. [ReaderWorkload](<../entry/src/main/ets/features/ReaderWorkload.ets>)按可见阅读器owner幂等管理。阅读中每任务下一批1页，离开恢复3页；任务并发上限仍3，正在执行批次安全结算。
3. 只对连续已验证成功前缀按批写检查点；部分失败不会跨过坏页。崩溃可能留下未记账但有效的尾文件，恢复会重验已记录前缀并重新下载尾部，不制造虚假进度。
4. 关闭逐页日志磁盘I/O；隐藏首页/书架不做无效DB/封面列表工作。

[8项下载性能/安全用例](<../tools/performance_download_cases.js>)的受控生产方法测量：
- 12页下载：12次64×64解码请求（旧源码是24次完整解码调用）。
- 完成后重检：12次受限解码，0次HTTP。
- 12页单章：4次批前缀检查点，含生命周期共10次ledger写；旧源码约18次。
- 3个任务最大并行页请求：非阅读9、阅读3，退出后下一批恢复。

**不宣称真机FPS、原生codec实际内存占用或所有机型不卡顿已测得改善。**图片变换、网络、原生源码运行时等仍可能有耗时；本轮给的是明确减少的解码/并发/同步I/O证据。

## 验证与交付边界

[61套最终汇总](<../logs/privacy-pagination-final-20261029/summary.json>)，
[SDK最终构建](<../logs/privacy-pagination-20261029/sdk-build-final2.log>)。

旧混合download/sync套件以`--downloads-only`保留下载安全测试；只删除与退役功能专属期待，普通收藏、历史位置、失败路由、源/图片/下载取消与负向控制仍通过。旧历史证据不重录成新“通过”。
本机带密码的签名配置保持本地未提交；没有使用此前聊天PAT，也没有替用户发布仓库版本。
