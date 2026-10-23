# 本轮功能（图标 / 分享 / 下载并发 / 缓存体系）2026-10-17

> 用户提出 5 项需求，其中「包名」按用户选择**保持不变**。全部改动**只在本地验证**，未安装。

## 1. 图标：改用原安卓项目图标

来源：用户给出的上游仓库 `https://github.com/venera-app/venera`（默认分支 master）。

- 取 `assets/app_icon.png`（1024×1024，V 标志 + 蓝底）作为前景层与启动图标
- 背景层用上游自适应图标 `ic_launcher_background` 的纯色 `(33,67,243)`
- 写入 `AppScope/resources/base/media` 与 `entry/src/main/resources/base/media` 两处
- 原文件备份在 `logs/icon-source/original/`

`layered_image.json` 结构未变；新增静态守卫断言两层都是真实 1024 图片、不是占位文件。

## 2. 包名

保持 `com.venerahm.reader`。改包名会变成新应用、旧数据不迁移，用户选择不改。

## 3. 下载：进度条 + 多任务 + 多线程

- **进度条**：`DownloadsPage` 每行渲染真实 `Progress({value,total:100,type:ProgressType.Linear})`，
  文案 `已保存 X 页 · 第 c/n 章 · p%`；总页数未知时显式显示"总页数未知"，百分比按已完成章节 + 本章进度估算，**不编造总页数**。
- **多任务**：`MAX_CONCURRENT_TASKS = 3`，第 4 个任务排队等待空位（不报错），界面显示"排队中（等待并行空位）"；新增"全部继续"。
- **多线程**：`PAGE_WORKERS = 3`，一章内最多 3 页并行抓取。

**安全不变量（关键）**：持久化检查点始终是**连续已校验前缀**。批次完成后按索引顺序逐页提交，
遇到第一个未验证的页就停止并抛出；代际变化时**先中断再提交**。因此乱序完成不会跳页，晚到结果不会写盘。

后台租约仍只有一个：其余并发任务走前台路径，退后台时暂停并显示原因（不谎称有后台许可）。

## 4. 分享：分享原网站地址

核对上游原版：`share()` 分享 `title + comic.url`，无 url 时只有标题——与旧实现一致。
真正的问题是**多数源不返回 url**（wnacg / Komiic / manwaba 都不返回）。

现改为三级回退，始终指向原网站：

1. 源返回的漫画页 URL
2. 漫画 id 本身是绝对链接时（EH 这类）直接用
3. 源自己的站点域名（`linkHandler.domains[0]`）

不安全候选（`javascript:`、含账号密码、带 token 查询串）仍拒绝；标题仍做控制字符清洗。

## 5+6. 缓存：封面/详情/正文持久化 + 1GB 上限 + 设置页

新增 [CacheStore](<../entry/src/main/ets/foundation/CacheStore.ets>)：字节记账、LRU 淘汰、可配置上限（**默认 1 GiB**）、
索引原子写入（`.part` → rename）、索引损坏/缺失时按目录列表重建（索引只提供新近度，不决定大小，所以陈旧索引不会多算字节）。

- 键名安全的沿用 `<key>.img`（旧封面文件升级后仍命中），其余转义为可逆的 `x<hex>.img`
- 单项超过上限时**拒绝该单项**，不清空其他缓存
- [ImageLoader](<../entry/src/main/ets/network/ImageLoader.ets>) 只替换磁盘读写，`ImageLease`、内存表、并发池、共享合并语义不变；写缓存失败不再让图片失败
- [CacheSettingsPage](<../entry/src/main/ets/pages/CacheSettingsPage.ets>)：占用条、条目数、256MB/512MB/1GB/2GB/4GB（1GB 标注默认）、清除缓存（确认框明确**不删下载与阅读历史**）
- 设置页新增"存储 → 缓存管理 ›"

**详情/正文缓存**接在源层（`JsComicSource`），缓存的是**源返回的原始 JSON**——
因为解析后的模型含 `Map`，`JSON.stringify` 会静默丢字段。详情页先用缓存秒开，**仍会请求网络刷新**；
刷新失败时保留缓存内容并明确提示，而不是变成错误页。

## 本地验证

- **50 套 + 2 项负向对照**全部通过（`.\tools\run_local_search_download_regression.ps1`）
- 新增：`download_progress_cases.js` 8、`cache_store_cases.js` 17、`cache_settings_cases.js` 11、`details_cache_cases.js` 5
- **关键证据**：`details_cache_cases.js` 用**真实源适配器**模拟两次启动（全新内存、同一缓存目录）——
  第二次 `loadCachedComicInfo` 命中且**脚本调用次数为 0**；缓存命中后 `loadComicInfo` 仍恰好调用一次（不会永久陈旧）。
- 缓存代理另有"两次启动封面零网络"用例（`fetches` 保持 1）
- 真实 SDK/API21 编译退出 0（`logs/round-icons-downloads-cache-build1.log`），且已确认产物对应最新源码

## 未验证 / 已知限制

- **未安装、未实机**：进度条渲染、多任务并发在真机的内存/CPU、三路并行解码、设置页交互均未上机。
- 缓存**没有 TTL**：详情以"先缓存后刷新"方式避免陈旧，但离线时看到的是上次缓存内容。
- Cookie 是图片身份的一部分（有意不弱化）：源若轮换会话 Cookie，同一封面会重新下载一次。
- 图片与 JSON 共用一个上限（沿用 `cacheDir/images` 以兼容升级），未分类型预算。
- 索引写入对 put/touch 防抖 1.2 秒；进程被杀可能丢失最近的新近度（大小仍按目录重建）。
- 正文页列表只做写穿缓存，下载与阅读仍信任实时列表，避免陈旧列表让检查点误判失效。
