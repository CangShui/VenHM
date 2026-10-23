# 通用功能迁移：搜索/探索、详情、收藏追更、阅读器、后台下载

用户明确要求补下列功能，本轮按模块实现并接通真实源接口、存储、入口与生命周期。
所有验证为**本地生产方法/实际主机桥/真实SDK编译**；本轮**未安装、未占用手机、未输入账号、未访问真实站点**。

## 1. 聚合搜索、单源绑定选源、搜索历史、探索分区与“更多”

- **聚合搜索**：[会话](<../entry/src/main/ets/features/AggregatedSearchSession.ets>)按源分组各自第一页，
  **全局最多3个进行中请求**，其余排队；切换关键词/来源或退出会作废旧结果并结算未启动的排队任务，不会继续打网络。
  每个源独立显示加载/空/失败并可单独重试；结果按源隔离，源返回不匹配身份会被拒绝。
  [页面](<../entry/src/main/ets/pages/AggregatedSearchPage.ets>)用 `LazyForEach` + `cachedCount(1)` 只构建可视源分区，
  “更多”跳转到该源**锁定的完整分页**（沿用既有 `CategoryComicsPage` 搜索分页）。
- **统一选源**：探索与分类继续共用 `SelectedSource` 稳定键；“聚合”入口只把当前可搜索源作为参数传入，不改变全局选源。
- **搜索历史**：[DAO](<../entry/src/main/ets/storage/SearchHistoryDao.ets>)独立表、去重、按时间排序、上限100条，
  写入/删除/清空均参数化且串行；仅在用户提交搜索时写入，绝不进入网络或审计日志。
  [搜索界面](<../entry/src/main/ets/features/SearchView.ets>)提供历史列表与清空/删除，失败不阻塞搜索。
- **探索分区与“更多”**：探索已有分区页签、真实游标/分页与失败重试；本轮未新增“更多”跳转 UI，
  **该子项仍属未完成**，不并入本轮通过项。

## 2. 详情缩略图、评论、分享、封面查看器

- [详情能力](<../entry/src/main/ets/source/DetailsCapabilities.ets>)按原版固定提交声明
  `loadThumbnails/loadComments/loadChapterComments/sendComment/sendChapterComment/likeComment/voteComment`，
  未声明的能力保持不存在。
- [适配器](<../entry/src/main/ets/source/JsDetailsAdapter.ets>)保留 `next` 首请求 null、章节评论、回复、
  点赞/投票的**原版位置参数顺序**；只有明确用户动作才会触发写操作，失败不自动重试或重新登录。
- [媒体会话](<../entry/src/main/ets/features/DetailsMedia.ets>)/[评论会话](<../entry/src/main/ets/features/DetailsComments.ets>)
  负责分页、游标、去重与陈旧响应隔离；缩略图支持 EH 的 `@x/y` 雪碧裁剪，只读变换不修改共享 PixelMap。
- [封面查看器](<../entry/src/main/ets/pages/ImageViewerPage.ets>)支持真实捏合/拖动/双击与上一张/下一张，
  只取当前图，不整章预下载。[评论页](<../entry/src/main/ets/pages/CommentsPage.ets>)为纯文本可选，
  回复/点赞/投票仅在源声明且用户确认时调用。
- 分享使用系统分享（`@kit.ShareKit`）提交文本/链接，平台选择器未做真机验收。

## 3. 网络收藏、图片收藏、追更

- [网络收藏适配器](<../entry/src/main/ets/source/JsFavoritesAdapter.ets>)按原版调用
  `loadComics(page,folder)`、`loadNext(next,folder)`（首请求 null）、`loadFolders(comicId)`、`addOrDelFavorite(...)`；
  未登录时显式失败且不发起请求。
  **已确认的实际脚本差异**：安装版绅士源声明了第4个 `favoriteId` 参数，而原版解析器只传3个，
  会导致删除 URL 出现 `undefined`。适配器改为读取函数声明长度：3参数源保持原样，4参数源在缺少收藏ID时**拒绝删除**，
  有ID时传入；夹具已断言请求中不出现 `undefined`。
- [图片收藏](<../entry/src/main/ets/features/PictureFavorites.ets>)只在阅读器明确动作时保存已处理图片字节，
  文件名使用本地随机UUID，写入前检查冲突、失败清理自身文件，且不记录原始URL/头部。
  管理页支持定位回原漫画与原页、确认后删除。
- [追更](<../entry/src/main/ets/features/FollowUpdates.ets>)为手动、只读检查：有界并发、逐漫画失败保留、
  首次检查建立基线避免误报更新、记录已读标记；不声称定时后台任务。
- 入口：书架新增三个按钮，设置页也新增对应入口，均已注册路由。

## 4. 阅读器设置、音量键、统计、手势

- [音量键](<../entry/src/main/ets/features/ReaderVolumeKeys.ets>)使用 API21 公开的
  `@ohos.multimodalInput.inputConsumer` 前台按键消费（`VOLUME_UP/DOWN`），仅在阅读器可见且用户启用时注册，
  隐藏/退出立即释放；不轮询全局音量、不改系统音量。
- [手势策略](<../entry/src/main/ets/features/ReaderGesturePolicy.ets>)集中左右点击区、长按动作与缩放判定。
- **连续模式自动阅读改为真实滚动**（`autoScrollStyle/speed/distance`，到底才翻页/换章），不再是每次跳一整页。
- [阅读统计](<../entry/src/main/ets/storage/ReadingStatsDao.ets>)/[页面](<../entry/src/main/ets/pages/StatisticsPage.ets>)
  用增量基线+按天分段+去重页表统计时长/页数，避免重复累计。
- 设置项按“已支持/平台不支持”明确分类；不支持的（墨水屏硬件、自动布局检测、滚轮倍率、状态栏等）**显式列出而非假装可调**。

## 5. 后台下载与任务控制

- [后台协调器](<../entry/src/main/ets/features/BackgroundDownloadCoordinator.ets>)使用 API21
  `ContinuousTaskRequest` + `MODE_DATA_TRANSFER` + 系统常驻通知 + WantAgent；`isModeSupported()` 或系统拒绝/挂起时
  **明确失败并暂停**，不伪造后台能力，也不用音频保活。
- 队列加入**代际(epoch)+在飞Promise归属**：暂停立即使旧runner失效；重启/删除先取消并等待旧runner退出再动文件；
  删除只处理严格命名的自有 `DL_*` 目录与自有 `.part`，删除前校验根路径与符号链接。
- 通知点击只打开下载列表，**绝不自动恢复任务**；`onDestroy` 停止原生服务。

## 验证与产物

- [全量回归](<../logs/broad-features-regression2-20261016.log>)：**45组JS套件 + Python报告/历史手机记录断言全部通过**。
  新增/更新套件：`details_cases`(14)、`details_napi_cases`(6，完整未修改WN/EH/Komiic源+13次内存拦截请求)、
  `collections_cases`(9)、`collections_napi_cases`(5)、`background_download_cases`(21)、`search_filters_cases`(12)、
  `search_filters_napi_cases`(5)、`ranking_cases`(15)、`ranking_napi_cases`(6)。
- [真实SDK/API21构建](<../logs/broad-features-compile3-20261016.log>)：退出0，签名HAP完成。
- [签名包](<../dist/broad-features-20261016-signed.hap>) SHA256
  `7F8CE9659F9C56AF06A80A516DF69087B7EE086DBCCF0264E99D474B7812FB9E`；
  [产物审计](<../logs/broad-features-artifact-20261016.json>)。

## 明确未完成 / 未验证

- 本轮**未安装到手机**：以上功能全部未做真机点验，也未访问真实站点或真实账号。
- 分享的系统选择器、后台任务在真实系统的授权/挂起行为、音量键真实按键、统计与后台下载的跨进程重启，
  都需要真机确认，不能由本地夹具代替。
- 探索“更多”跳转 UI、聚合搜索的源管理界面、评论富文本渲染、封面导出/保存仍未做。
- 图片收藏的长期容量管理与去重策略、追更的定时检查仍是待办。
- 此前 JM 后续页加载与卡顿只完成本地修复并安装过一版；**长章节与真实帧率仍待专项验收**。
