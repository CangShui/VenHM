# Venera HM

[VeneraNext](https://github.com/CyrilPeng/Venera-Next) 的**原生鸿蒙（ArkTS/ArkUI）移植**工程。

- 上游：`venera_next` v1.17.0+228（Flutter 3.41.4）
- 本工程：HarmonyOS `6.0.1(21)`，`runtimeOS: HarmonyOS`，bundle `com.venerahm.reader`
- 语言/UI：ArkTS + ArkUI（声明式），原生 NAPI C++ 承载 QuickJS 漫画源运行时
- 迁移计划与进度：[docs/MIGRATION_PLAN.md](docs/MIGRATION_PLAN.md) · [migration_status.yaml](migration_status.yaml)

## 能力概览

| 模块 | 说明 |
|---|---|
| 漫画源 | QuickJS 原生运行时（NAPI）+ `sendMessage` 桥；支持 JS 源安装、校验、失败回退 |
| 搜索/探索 | 源选择、关键字搜索、聚合搜索（无固定源数量上限）、分类与排行、筛选与标签路由 |
| 详情 | 封面/作者/标签/简介、章节列表、评论、分享、图片与网络收藏 |
| 阅读器 | 7 种模式（翻页/连续/瀑布、横竖、RTL）、双页拆分、点击分区、自动阅读、亮度、音量键、阅读统计 |
| 阅读交互 | 整阅读窗口九宫格；进入正文菜单隐藏，中心唤出，菜单外点仅关闭不翻页（参考 Legado-E 默认行为，UI 为自有） |
| 下载 | 前台/后台下载队列、并发与进度、断点续传校验、后台任务租约 |
| 缓存 | 持久化图片缓存、容量上限与 LRU、统计与清理（不影响下载/历史） |
| 数据 | 收藏/历史/阅读统计/追更、WebDAV 阅读数据备份入口 |
| 界面 | 统一浅灰画布、白色圆角分组卡片、固定方框原生矢量图标、悬浮底部导航 |

尚未完成与已知限制见 [docs/FEATURE_PARITY.md](docs/FEATURE_PARITY.md) 与 [docs/HANDOVER.md](docs/HANDOVER.md)。
文档中的设备实测记录、构建哈希与逐步验证过程保留在 `docs/` 中，其中设备标识与本机路径已做脱敏。

## 工程结构

```
entry/src/main/
├── ets/
│   ├── entryability/            # UIAbility 入口
│   ├── model/                   # 领域模型
│   ├── foundation/              # Log / AppContext / Settings / 缓存与阅读设置
│   ├── network/                 # HttpClient / CookieJar / 图片管线与变换
│   ├── storage/                 # relationalStore + 各 DAO
│   ├── source/                  # ComicSource 契约 / JS 源运行时与适配器 / 源管理
│   ├── features/                # 各业务视图与会话、下载队列、阅读策略
│   ├── components/              # 通用组件（图片、UI Kit、阅读窗口与点击分区）
│   └── pages/                   # 各页面（书架/搜索/详情/阅读器等）
├── cpp/                         # NAPI：QuickJS 运行时、HTTP 解码、图片桥
└── resources/                   # 图标（SVG）、配色、rawfile JS 库
```

## 构建

需要 **DevEco Studio 6.0.1** 与 HarmonyOS SDK 6.0.1(21)（DevEco 自带 `sdk/default`）。

```powershell
$deveco = "C:\Program Files\Huawei\DevEco Studio"
$env:JAVA_HOME = "$deveco\jbr"
$env:DEVECO_SDK_HOME = "$deveco\sdk"
$env:PATH = "$deveco\tools\node;$deveco\tools\ohpm\bin;$deveco\tools\hvigor\bin;$deveco\jbr\bin;$env:PATH"
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

### 签名说明（重要）

仓库中的 [build-profile.json5](build-profile.json5) **不包含任何签名材料**，因此默认构建产物是 *unsigned* HAP。
需要安装到设备时，请在 DevEco Studio 中通过 `File → Project Structure → Signing Configs`
用自己的华为账号自动生成签名（材料只保留在本机），再次构建即得到 `entry-default-signed.hap`。

**不要把证书、profile 或密码提交到仓库。** `.gitignore` 已屏蔽密钥库与签名文件，
[`tools/secret_scan.ps1`](tools/secret_scan.ps1) 可在提交前检查凭据、签名材料、带凭据 URL 与硬件标识。

## 本地测试

```powershell
# 全量本地回归（无设备、无安装、无真实站点）
.\tools\run_local_search_download_regression.ps1
# 阅读交互专项
.\tools\run_legado_reader_local.ps1
# 提交前隐私扫描
.\tools\secret_scan.ps1
```

这些用例执行生产方法的纯逻辑/受控假件，覆盖源解析、图片管线、下载队列、缓存、阅读交互与路由；
它们**不能替代**真机渲染、系统行为与真实站点可用性验证。

## 发布产物

签名 HAP 通过 [Releases](../../releases) 发布，不进入版本库。
安装需要本机 `hdc`，并且 HAP 的签名证书需与设备信任配置匹配。

## 许可证

上游 VeneraNext 为 GPL-3.0，本移植工程沿用同一许可，见 [LICENSE](LICENSE)。
内嵌的 QuickJS、Brotli 等第三方组件保留各自的许可证文本（`entry/src/main/cpp/*/LICENSE`、`entry/src/main/resources/rawfile/licenses/`）。
