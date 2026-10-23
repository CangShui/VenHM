# VeneraNext → HarmonyOS（ArkTS/ArkUI）迁移计划

> Planner Agent 交付物。上游源码：`CyrilPeng/Venera-Next` v1.17.0+228（Flutter 3.41.4，`lib/` 230 个 Dart 文件 / 67,420 物理行）。
> 目标工程：`<repo>`（HarmonyOS 6.0.1(21)，`runtimeOS: HarmonyOS`，bundle `com.venerahm.reader`）。
> 路线：**原生 ArkTS/ArkUI 重写**（非 Flutter 鸿蒙化）。本轮范围：**可运行骨架 + 最小闭环**。

---

## 1. 迁移顺序与阶段划分

Analyzer 给出的模块清单（23 个模块）按依赖关系重排为 9 个阶段。阶段 0 是硬前置，其余按"数据层 → 业务逻辑 → UI"推进。

| 阶段 | 内容 | 上游规模 | 本轮状态 |
|---|---|---|---|
| **0** | **QuickJS NAPI 原生模块**（`flutter_qjs` 替代）+ `assets/init.js` 兼容性 | 7 文件 / 3,171 行 | ❌ 未开始（P0 阻塞项，契约已固定） |
| 1 | 基础类型与平台层：`Res`/`ComicType`/`Comic`/`ComicDetails`/`ComicChapters`、`AppContext`、`Settings`、`Log`、文件系统 | 18 文件 / ~2,900 行 | ✅ 完成 |
| 2 | 存储层：`relationalStore` 封装 + 收藏/历史 DAO | 11 文件（SQLite 同步→异步重构） | ✅ 完成（收藏/历史/源表） |
| 3 | 网络层：HTTP 客户端、Cookie、图片下载与缓存 | 9 文件 / 2,130 行 | 🟡 部分（HTTP + 图片缓存；Cookie/缓存/Cloudflare/代理未做） |
| 4 | 漫画源领域：`ComicSource` 契约、注册表、源管理 | 23 文件 / 7,673 行 | 🟡 部分（契约 + 注册表 + 2 个内置源；JS 源解析未做） |
| 5 | 最小闭环 UI：书架 → 搜索 → 详情 → 章节 → 阅读器 | 14 文件 / 9,146 行 | ✅ 完成（精简版） |
| 6 | 阅读器增强：7 种阅读模式、双页拆分、自动阅读、亮度、墨水屏 | 20 文件 / 7,725 行 | ❌ 未开始（仅分页 + 瀑布流） |
| 7 | 设置/历史/图片收藏/追更/探索分类 | 43 文件 / ~13,000 行 | ❌ 未开始 |
| 8 | 下载 + 导入导出（CBZ/EPUB/PDF） | 21 文件 / 7,081 行 | ❌ 未开始（依赖 7z/PDF 决策） |
| 9 | WebDAV 同步 + WebDAV 漫画库 + deep link + WebView 登录 | 15 文件 / ~5,500 行 | ❌ 未开始 |

---

## 2. 阶段 0：QuickJS NAPI 模块（最高优先级）

没有它，**所有 `.js` 漫画源都无法运行**（上游 9 个文件直接依赖 `flutter_qjs`）。契约已在 `entry/src/main/ets/source/JsRuntime.ets` 中逐字固定，实现时不得改动 `assets/init.js`（已原样复制到 `entry/src/main/resources/rawfile/init.js`）。

要点：
- QuickJS 源码以 CMake 目标编译为 `arm64-v8a` / `x86_64` 原生库，经 NAPI 暴露。
- 注入两个全局：`sendMessage(message)` 与 `appVersion`。
- 22 个 `method` 分派 + `html` 的 21 个子动作 + `convert` 的 13 种类型 + `UI` 的 7 个子动作，参数名必须与 Dart 版逐字一致。
- **同步/异步混合返回**：`load_data`/`isLogged`/`getLocale`/`getPlatform`/`html.*`/`convert`/`random`/`uuid`/`cookie.get` 同步返回 `napi_value`；`http`/`delay`/`getClipboard`/`compute`/`UI.*` 返回 `napi_create_promise`。
- 需要 JS 函数句柄（等价 Dart `JSInvokable`）：`UI.showDialog` 的 `actions[].callback`、`showLoading.onCancel`、`showInputDialog.validator`、动态分类 `loader`、`settings` 里的函数值。ArkTS 无 Finalizer → 用 `napi_create_reference` + 显式 `dispose()`，在源卸载时统一释放。
- `ArrayBuffer` ↔ 原生字节数组零拷贝。
- 验收基准：上游 `test/foundation/js_engine_test.dart`、`js_pool_test.dart`、`test/features/comic_source/source_parser_test.dart`，以及 `doc/examples/minimal_source.js` 端到端。

## 3. 阶段 0.5：HTML/CSS 选择器（第二阻塞项）

上游用 `package:html` 的 CSS 选择器支撑全部网页抓取类源。OHOS 无等价物。**推荐方案**：在 QuickJS 内运行纯 JS 的 HTML/CSS 库，保持 `HtmlDocument`/`HtmlElement`/`HtmlNode` 对外 API 不变，只替换内部实现——这样 `init.js` 中这三个类的签名无需改动。次选是手写解析器（工作量极大）。

---

## 4. 关键设计决策（已落地）

| 决策 | 原因 |
|---|---|
| `Comic` 声明为 **interface**，`ComicItem`/`FavoriteItem` 显式 `implements` | ArkTS 无结构化类型；上游 `Comic` 是具体类却被 `FavoriteItem`/`History`/`LocalComic` 当作接口实现 |
| `ComicType` 用 **FNV-1a 32 位**哈希替代 Dart `String.hashCode` | Dart 的哈希不可跨语言复现；该值入库，必须稳定。**与 Flutter 版数据库不二进制兼容**，故不做数据迁移 |
| 收藏改为**单表 + `folder` 列** | 上游每文件夹动态建表；`relationalStore` 下不可行 |
| 收藏表额外存 `source_key` 文本 | 上游只存 `ComicType` 哈希，反查源需要 resolver；直接存 key 更简单可靠 |
| 全部存储调用 **async/await** | `relationalStore` 只有异步 API，而上游是同步调用；管理器层采用"内存态 + 异步落盘" |
| 内置 `LocalSource` + `DemoApiSource` | QuickJS 未接入前保证"书架→搜索→详情→章节→阅读器"闭环可跑；`DemoApiSource` 沿用上游 `doc/examples/minimal_source.js` 的 JSON 契约 |
| UI 组件只用**基本类型**做 `@Prop`，尺寸由父容器包裹 | 规避 ArkTS/ArkUI 对接口类型 `@Prop` 与自定义组件通用属性的限制 |
| `Log` 统一封装 `hilog` | 对齐上游 `Log.addLog` 的单点出口 |

## 5. 无法直接移植的 Flutter 机制（后续阶段替换）

| Flutter | ArkTS/OHOS |
|---|---|
| `Overlay` / `PopupRoute` / `showDialog` | `Stack` + `@Builder` + `CustomDialogController` + `bindSheet` |
| `Sliver*` / `sliver_tools` | `List`/`Grid`/`WaterFlow` + `ListItemGroup` |
| `CustomPainter` / `CustomClipper` | `Canvas` + `CanvasRenderingContext2D` |
| `WidgetsBindingObserver` | `UIAbility.onForeground/onBackground` |
| `MethodChannel`/`EventChannel` | ArkTS 原生模块 + `@ohos.events.emitter` |
| `dart:isolate`（14 文件） | `@ohos.taskpool` |
| `extension` on String（`.tl`/`.tlParams`） | 独立函数；`translations` 需优先移植 |
| `mixin` / `ChangeNotifier` / `Listenable` | `implements` + 组合；`@Observed`/`@ObjectLink` 或自建事件总线 |
| `photo_view`（缩放查看器） | `Image` + `PinchGesture`/`PanGesture` + `matrix4` 自研 |
| `scrollable_positioned_list` | `List` + `Scroller.scrollToIndex` |

## 6. 原生依赖风险（OHOS 无现成实现）

| 依赖 | 能力 | 替代方案 | 风险 |
|---|---|---|---|
| `flutter_qjs` | 内嵌 QuickJS | 自建 NAPI 模块 | **致命** |
| `rhttp` | HTTP/2、代理、DNS 覆盖、TLS 细粒度 | `@ohos.net.http` / `rcp`；DNS 覆盖无公开 API | 高 |
| `flutter_inappwebview` | 登录/Cloudflare WebView | `@ohos.web.webview` | 高 |
| `flutter_7zip` | 7z 解压 | `@ohos.zlib` 仅 zip/gzip → 降级不支持 7z | 高 |
| `flutter_saf` | Android SAF | `@ohos.file.picker` + `fileAccess` | 高 |
| `pdfrx` | PDF 渲染（PDFium） | 无 → 降级只做导出 | 中高 |
| `webdav_client` | WebDAV | 自建 PROPFIND/认证 | 中高 |
| `desktop_webview_window` / `window_manager` / `dynamic_color` | 桌面窗口、动态取色 | 直接删除 | 低 |

## 7. 验证状态

| 检查项 | 结果 |
|---|---|
| 非 UI 层类型检查（TS 4.9.5，SDK 桩） | ✅ 21/21 文件 0 错误 |
| **hvigor 编译 + HAP 打包** | ✅ **BUILD SUCCESSFUL**（12s，0 error / 109 warning） |
| 产物 | `entry-default-unsigned.hap` 642.4 KB；`ets/modules.abc` 368.4 KB（vm `ark13.0.1.0`） |
| 上游 `init.js` 打包 | ✅ `resources/rawfile/init.js` 38.2 KB |
| 安装 / 上板 | ❌ 未执行：HAP 未签名（HarmonyOS 调试签名需绑定设备 UDID），且本机无设备、无模拟器系统镜像 |
| 遗留 warning | 91 条"可能抛异常"lint + 18 条废弃 API（`@ohos.router`、`promptAction.showToast`） |

工具链：DevEco Studio `DS-243.24978.46.36.601251` + hvigor `6.21.1` + 自带 HarmonyOS SDK `6.0.1.112 / API 21 (Release)`，与本工程 `targetSdkVersion 6.0.1(21)` 完全匹配。

## 8. 下一步

1. **上板运行**：本机无设备、无模拟器系统镜像。接上鸿蒙手机（开启 USB 调试）后：
   - DevEco → `File → Project Structure → Signing Configs → Automatically generate signature`（登录华为账号，profile 绑定设备 UDID）
   - `hvigorw --no-daemon assembleHap` 产出 `entry-default-signed.hap`
   - `hdc install -r <hap>` 然后 `hdc shell aa start -b com.venerahm.reader -a EntryAbility`
   - 或无设备时用 DevEco 内置 **Previewer** 预览 ArkUI 界面
2. **阶段 0**：QuickJS NAPI 模块 POC（含 `convert`/`html`/`http` 三条链路），完成后接入 `JsComicSource`，届时可直接加载 `venera-configs` 的 `.js` 源。
3. **阶段 6**：阅读器补齐 7 种模式与双页拆分。
4. **技术债**：`@ohos.router` → `Navigation`/`NavPathStack`，`promptAction.showToast` → `promptAction.openToast`（消除 18 条废弃警告）。
