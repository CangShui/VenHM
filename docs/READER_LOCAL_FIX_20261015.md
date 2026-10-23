# JM 正文空白/无限加载 与 阅读器卡顿：本地根因与修复

用户报告：禁漫天堂正文前两页正常，往后翻出现“新页显示约一秒→变空白→一直加载、流量持续、后续全部加载不出”；
以及所有正文纵向滚动/横向翻页严重卡顿。本地优先修复，未安装到手机、未卸载或清数据。

## 根因（本地可复现，非站点问题）

1. **已解码图片在组件复用时被清空并重新请求**
   `AsyncComicImage.aboutToReuse` 先写 `url`（触发 `@Watch` → `load()`），随后又无条件 `load()` 一次；
   `load()` 每次都会把 `pixelMap` 置空、取消旧 trace 并重新走 HTTP/解扰/解码。
   JM 的解扰像素图没有可复用的共享缓存，于是“显示一秒后空白再加载”，并持续消耗流量。
   旧回归 `tools/image_component_lifecycle_cases.js` 当时就在这一路径上失败。

2. **翻页销毁并重建整章图片，且一次性创建全部图片**
   画廊用 `ForEach(this.displaySpreads)` 立即构建整章；外层 spread 与内层图片的 key 都包含 `zoomReset`，
   而 `updatePage/seekPage` 每翻一页都会 `resetZoom()`，导致所有图片节点被销毁重建。
   就绪状态也被 `resetZoom` 清空，预取的解码结果被丢弃。这正是翻页/滚动卡顿的主因。

3. **每次翻页同步写历史**
   每个 `updatePage/stepPage/seekPage` 都立即 `HistoryDao.save`（同步磁盘 IO 在 UI 回调内）。

## 修复

### 图片所有权：显式租约 + 有界并发 + 按身份共享（`network/ImageLoader.ets`）
- 新增 `ImageLease`：每次获取返回一个幂等租约，组件只 `lease.release()`，
  **永不直接释放 PixelMap**；缓存图由加载器持有，避免一个组件释放掉别人正在显示的图。
- `acquireRequest(config, trace, shouldContinue, thumbnail)`：纯 GET（含 `modifyImage` 解扰）按
  `url+headers+cookie+transform` 哈希**共享同一次下载/解扰/解码**，多个消费者各持独立租约。
- 生产者并发上限 4，其余排队；**最后一个消费者离开且尚未完成时取消传输**，快速滚动不再继续下载没人看的页。
- 非共享请求（POST/正文/`onResponse`/`onLoadFailed`）保持独立管道，不与他人共享取消状态。

### 组件身份与复用（`components/ComicWidgets.ets`）
- 请求身份 = `url/sourceKey/comicId/epId/thumbnail` 的长度前缀元组；五个输入都 `@Watch('reloadImage')`。
- `@Watch` 与 `aboutToReuse` 合并为一次去抖更新，**同身份复用不再清空或重新请求**；
  布局/缩放/就绪变化不进入身份。
- 解码成功即清除待取消 trace，避免“取消已完成的变换”；失败为终态，不进入重复请求循环。

### 懒加载与就绪代（`features/ReaderRenderSource.ets`、`pages/ReaderPage.ets`）
- 新增 `IDataSource` 实现 `ReaderRenderSource`；`List`/`Swiper` 改用 `LazyForEach` + `cachedCount(1)`，
  仅构建当前±1 组（最多配置的每屏 5 图时 ≤15 张），不再一次性建整章。
- key 只含 `scope:image:源序号` / `scope:spread:源成员`，**去掉 `zoomReset`**；
  同一 identity 记录对象跨翻页/旋转复用，只有换章或分组变化才 `onDataReloaded`。
- 就绪状态改用独立 `renderGeneration`（缩放仍用 `zoomReset`），预取的就绪不再被翻页清掉。

### 进度写入合并（`pages/ReaderPage.ets`）
- 翻页只调度，500ms 合并落盘；隐藏/退出/换章**强制同步 flush**，并剔除网络等待时长。

## 本地验证

- 针对性套件（全部通过）：
  `image_component_lifecycle_cases`（15 项，含同身份复用不重下、共享图不被单方释放、失败不重试循环）、
  `reader_performance_cases`（长章节按需窗口、稳定身份、进度合并）、
  `reader_spread_cases`（575 项）、`reader_controls_cases`、`reader_tap_policy_cases`、
  `history_reader_cases`（续读/换章/时长）、`image_cache_cases`、`image_pipeline_cases`、
  `image_transform_cases`、`isolated_arkts_cases`（共享租约契约）。
- 全量回归：**36 组 JS 套件 + 报告/真机证据契约全部通过**（`logs/reader-local-fix-regression-20261015.log`）。
- 签名构建通过：`COMPILE_EXIT=0`；`entry-default-signed.hap` SHA256
  `56060332E3CD290164D3F72A574F3A16885EA252F9AF6DED0423D79627DB776A`。

## 尚未验证（不冒充完成）

- 用户随后授权实机安装：已非破坏性覆盖安装，安装日志明确 `install bundle successfully`；2026-10-16已核对当前前台首页（标题/历史/搜索/设置可见）。包哈希与上文一致。真机流畅度与真实 JM 长章节后续页**仍未完成专项复测**，安装成功不等于这两项性能/加载缺陷已实机通过。
  安装证据：[覆盖安装日志](<../logs/reader-local-fix-install-20261015.log>)；首屏证据：[实际布局](<../logs/user8-ui/1792122269254-5373-layout.out>)。
  本地仅测量“按需构建的图片数量”和“每身份一次请求”等结构性指标，**不是设备帧率/内存实测**。
- 图片仍共用 24 项内存缓存与内存上限策略，未按可见性优先级驱逐；极端长章节的内存占用仍需真机观测。
- 未改动站点源脚本；未调整 JM 的解扰语义。
