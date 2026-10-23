# 阅读器模式与目录：可用性验收记录

## 2026-10-14 控制功能增量（不等于完整阅读器）

已新增canonical页按钮、double tap/pinch缩放与zoom pan、窗口亮度循环、默认8秒自动阅读/暂停。
自动阅读期间窗口保持亮屏，暂停/隐藏/退出恢复；放大/加载期间不翻页，最后一章末页停止。

构建6、设备PID13931的新增实测：

| 操作 | 证据与结论 |
|---|---|
| 页› / ‹页 | 新建随机2章×3页本地样本，1→2→1，原galleryLeftToRight模式未改 |
| 双击 | 真实UI手势触发比例1→2→1，放大图留存；父阅读器zoom锁定标志随之恢复 |
| 自动阅读 | 8秒前进，用户暂停后再等10秒，页码不变 |
| 窗口亮度 | 亮度入口→35% UI；退出后setWindowBrightness恢复调用完成，不修改系统亮度 |
| 亮屏 | 自动期间setWindowKeepScreenOn(true)完成，暂停后恢复旧值调用完成 |
| 隔离清理 | 只清理本次HM_OFFLINE_READER随机标记目录及历史，真实历史仍38条；不清用户数据 |

证据：`logs/reader-controls-device/`、
`logs/image-reader-transfer-device-pid13931-20261014.log`。
CLI简化树不显示Swiper内Image，验收脚本使用HDC原树定位应用图片，丢弃通知区原始树，仅保存图片bounds；
确认弹窗通过含“清理样本”的唯一可点击Button定位，不点击不可点击子Text。
脚本：`tools/reader_controls_device_cases.ps1 -CliPath <实际cli.js路径>`，从历史页开始。

**尚未验证**：双指pinch、pan边界/父列表冲突、RTL自动阅读、连续模式晚加载锚点、背景锁屏时间统计、
恢复后亮度/亮屏的独立系统状态读回。**尚未实现完整对齐**：双页拆分、组章节树、音量键、墨水屏、全部设置/手势。

## 结论与验收口径

本轮把上游 `enum ReaderMode` 的**七种模式**全部实现，并补上**章节列表浮层**。这仍只是阅读器模块的验收，不代表整个应用可用性通过。

## 上游对照

`lib/features/reader/reader_page.dart:950-982` 定义 7 个模式，`reader_mode_labels.dart` 给出显示名，`images.dart:493-496` 对右→左模式执行 `images = images.reversed.toList()`。本轮逐条对齐：

| 上游 key | 本工程 | 渲染方式 |
|---|---|---|
| `galleryRightToLeft` | ✅ | 横向 Swiper + 图片顺序反转 |
| `galleryLeftToRight` | ✅ | 横向 Swiper |
| `galleryTopToBottom` | ✅ | 纵向 Swiper |
| `continuousTopToBottom` | ✅ | 纵向 List，自然比例 |
| `waterfallTopToBottom` | ✅ | 纵向 List，自然比例（默认） |
| `continuousLeftToRight` | ✅ | 横向 List |
| `continuousRightToLeft` | ✅ | 横向 List + 顺序反转 |

关键不变量：**反转只影响显示顺序，不影响存储的页码**。`ReaderModes.toDisplayIndex/toActualIndex` 负责双向映射，`displayOrder` 不修改原数组。

## 本轮实现

- 新增 `features/ReaderModes.ets`：模式规范化（未知值回退 waterfall，同 `ReaderMode.fromKey`）、分类判定、轴方向、反转判定、索引映射、显示顺序、中文标签、模式循环。
- 阅读器顶栏显示模式名，点击按上游顺序循环切换并持久化到 `Settings.readerMode`；切换模式保持当前页，并让列表滚动到新的显示索引。
- 新增**目录浮层**：列出全部章节、标记“阅读中”、点击跳转；顶栏标题与底栏“目录”均可打开。
- 顶栏显示 `第 n/N 章 · 章节名`，底栏保留页码 `当前页 / 总页数`。

## 已验证证据

设备：`<device-id>`，HarmonyOS 6.0.1 / API21，记录时间 2026-10-13 16:38–16:41。构建 [日志](<../dist/reader-modes-build2.log>)。

| 用例 | 结果 | 证据/边界 |
|---|---|---|
| 生产逻辑回归 | PASS 75/75 | [日志](<../dist/reader-modes.log>)：28 位置/时钟 + **17 阅读模式** + 19 Reader 控制流 + 11 冷启动/渲染 |
| 七模式循环 | PASS（设备UI） | 逐次点击依次得到 右→左 / 左→右 / 上→下 / 连续上→下 / 瀑布流 / 连续左→右 / 连续右→左 |
| 切换模式保持页码 | PASS（设备UI） | 六次切换后底栏始终 `1 / 3`，与图片内容一致 |
| 右→左模式图片与页码一致 | PASS（设备UI） | [截图](<../dist/history-usability/mode-rtl-p1.jpeg>) 显示 `PAGE 1 / 3` 且底栏 `1 / 3` |
| 目录浮层 | PASS（设备UI） | 显示 `1 Chapter_1`、`2 Chapter_2`，当前章标 `阅读中` |
| 目录跳章 | PASS（设备UI） | 点 Chapter_1 → `第 1/2 章 · Chapter_1`，页码重置为 `1 / 3`，浮层关闭 |
| 模式跨重启持久化 | PASS（设备UI） | 切到 `连续（右→左）` → 强制停止 → 重进 → 仍为 `连续（右→左）`，章页不变 |
| 测试后恢复 | PASS（设备UI） | 模式已改回原值 `翻页（右→左）`；离线样本清理，历史恢复 28 条 |

逻辑回归覆盖的映射不变量（节选）：`toDisplayIndex('galleryRightToLeft',0,3)==2`、`toActualIndex(...,2,3)==0`、溢出先夹取再反转、空章节返回 0、`displayOrder` 不修改原数组、未知模式回退、模式循环首尾相接。

## 未覆盖 / 未实现，下一轮仍须继续

- **手势与交互**：点击/长按/双击缩放、拖动进度、音量键翻页、边缘翻页区均未实现。
- **双页拆分**（横屏/宽屏合并两页）未实现；上游 `images.dart` 的双页分支未移植。
- 亮度调节、自动阅读、墨水屏刷新未实现。
- 连续横/纵向模式与上游仍有细节差异：上游按视口计算页面尺寸、支持翻页动画与预加载窗口；HM 用 List + Contain，**未做异尺寸远程图片的滚动锚点验证**。
- 目录浮层未在**大章节列表**（数百章）上验证虚拟化与性能；分组章节树未实现。
- 阅读进度恢复仍未覆盖分组章节（`chapter_group`）与已读章节集合更新。
- 模式切换的列表滚动定位只在 3 页样本上验证；长章节列表的定位精度待验。

## 复现

```powershell
node tools/history_reader_cases.js   # 需 Node >= 22.13；应输出 PASS 75

# 设备：Venera HM → 历史 → 离线验收
# 1. 打开本地样本详情 → Chapter_2，确认顶栏 `第 2/2 章` 与模式名。
# 2. 反复点击顶栏模式名，逐一确认 7 个模式标签与底栏页码不变。
# 3. 点「目录」→ 选择 Chapter_1，确认章号、页码与浮层关闭。
# 4. 切到任意模式后强制停止并重进，确认模式仍保留。
# 5. 用「清理本页生成的样本」移除样本。
```
