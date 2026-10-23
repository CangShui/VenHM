# Legado-E阅读交互参考与漫画适配（2026-10-23）

## 当前状态

**适配代码、本地54套回归及SDK编译完成；新包已成功覆盖安装。**
开始安装前两次HDC列表返回`[Empty]`，当时未盲目执行；用户随后明确确认重连授权，重新识别到设备`<device-id>`并核对新包哈希后完成覆盖安装。
[安装证据](<../logs/legado-reader-user-install-20261023.log>)明确`install bundle successfully`；`VERIFIED_OVERWRITE_PASS`且退出0。
保留应用数据，没有卸载、清数据、启动、截图或点击，功能测试由用户自行进行。

## 固定参考，不照搬UI

参考仓库：[Luoyacheng/legado-E](https://github.com/Luoyacheng/legado-E)，固定提交`8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c`。
已读默认配置、ReadView触摸分发、ReadMenu显隐/遮罩、活动布局、滚动委托与自动阅读联动；下载文件仅作证据，不嵌入应用。
独立实现交互策略，保留本项目底部浮层视觉，不搬运Android布局/资源/代码。

### 默认九宫格

| 阅读窗口位置 | 左 | 中 | 右 |
|---|---|---|---|
| 上 | 上一页 | 上一页 | 下一页 |
| 中 | 上一页 | 菜单 | 下一页 |
| 下 | 上一页 | 下一页 | 下一页 |

依据：[默认动作](https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/app/src/main/java/io/legado/app/help/config/AppConfig.kt#L38-L46)、[分区与点击派发](https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/app/src/main/java/io/legado/app/ui/book/read/page/ReadView.kt#L132-L146)。
边界按整个阅读窗口的0.33/0.66计算，不按单张图片重复、不按长图总高度、不跟随缩放后的图片边框。
上游右上区域存在与上中重叠的0.36起点，但分发优先级先判上中；目标用无重叠九宫格实现其有效默认行为。
RTL漫画镜像左右列，顶部中间仍上一页、底部中间仍下一页；“反转点击翻页”只反转翻页，不移动菜单。

### 菜单什么时候显示和隐藏

- **新进入正文时隐藏**，点正中格唤出。依据：[上游初始布局](https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/app/src/main/res/layout/activity_book_read.xml#L7-L44)。
- 打开时全屏独立遮罩接管正文区点击，**外点只关菜单，不翻页**；菜单操作区自己的按钮照常响应。依据：[背景与显隐](https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/app/src/main/java/io/legado/app/ui/book/read/ReadMenu.kt#L368-L404)。
- 菜单不因等待3秒/5秒自动消失；只有明确收起、外点、打开目录/设置/详情/自动阅读或退出等动作关闭。
- 上一章/下一章、亮度等留在菜单内的操作不强制关闭。
- 打开菜单/目录暂停自动阅读的实际动作但保留原运行意图，关闭后继续；原本没开自动阅读则不会因关菜单而启动。离开页面仍停止自动阅读。
- 图片未加载、出错或存在留白也可通过中心格访问菜单，不再依赖单张图片解码成功。
- 原有全屏画布与下方浮层是Stack兄弟节点，菜单不挤压/重建正文。

## 漫画适配与防误触

实现：[窗口分区与接触仲裁](<../entry/src/main/ets/components/ReaderClickZones.ets>)、[阅读页](<../entry/src/main/ets/pages/ReaderPage.ets>)、[图片双击通知](<../entry/src/main/ets/components/ComicWidgets.ets>)。

1. 窗口监听原始触摸但不拦截原生滑动/捏合识别；图片不再另派单击，避免一张图一套分区和重复动作。
2. 菜单显隐无需图片就绪，真正翻页仍受可见性、加载、缩放、滚动、完整可见图片组就绪等门禁保护。
3. 连续/瀑布长图一次移动一个可见窗口高度/宽度，不整张跳过；页级向前跨章去上一章最后图/末屏，按钮“上一章”仍保留原先到首图的语义。
4. 松手轻微抖动采用按下位置判区；拖动、多指、取消、长按不当单击。
5. 漫画保留原生双击缩放，窗口单击等待350ms仲裁；两击60vp内判定与原生相符，图片原生双击识别还明确取消父级候选。双击放大、缩回和关闭双击缩放时均不能顺带开菜单/翻页。
6. **真实ArkUI Up模型**：抬手时`touches`可能仍包含已抬起手指，按`changedTouches.id`排除释放触点后计数，不能假设Up时数组为空。也不能按每个touch.type筛选，因为部分版本把所有触点标为本次事件类型。
7. Down时固定加载/缩放代际；窗口变化、滚动、退出、重试、原生双击同时取消接触和排队动作，防晚到/旧坐标。
8. 菜单打开时音量翻页回调不在背后翻页；既有按键平台订阅与释放实现不改。

平台依据：[OpenHarmony 5.0.3触摸桥接](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-5.0.3-Release/frameworks/bridge/declarative_frontend/engine/functions/js_touch_function.cpp)、[原生触摸分发](https://github.com/openharmony/arkui_ace_engine/blob/OpenHarmony-5.0.3-Release/frameworks/core/components_ng/event/touch_event.cpp)、[TapGesture官方说明](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-tapgesture.md)。这是源码/接口契约证据，不是本机触摸实测。

### 明确不是照搬的部分

保留本项目自有UI、菜单160ms动画、Back先关菜单/目录、漫画双击/捏合、RTL、现有ReaderWindowChrome全屏入退恢复。
上游Back最终退出阅读而非总是先关菜单，上游菜单显示系统栏；不能把这些说成完全一致。当前保留目标应用原有全屏与返回规则。
上游支持自定义九格全部动作，当前仅采用其默认九格+现有翻页启用/方向反转，不宣称迁入所有自定义功能。

## 本地证据

```powershell
.\tools\run_legado_reader_local.ps1
```

- [54套完整汇总](<../logs/legado-reader-regression-20261023/summary.json>)全部通过，含原有负向对照。
- [43项阅读交互](<../logs/legado-interaction-20261023/reader-cases.json>)执行真实ReaderPage、ReaderClickZones、AsyncComicImage方法，覆盖原生Up含本指、多指同事件type、40vp偏移双击、菜单遮罩/初始隐藏/无空闲隐藏、加载留白、长图按屏、RTL/反转、跨章末屏、按住期间代际变化、重试、音量键与自动阅读。
- [范围守卫](<../logs/legado-interaction-20261023/scope-result.json>)：58个非交互阅读方法、18个共享图片方法、99个既有后端/配置文件保持；autoStep与syncVolumeKeys仅新增菜单可见性门禁并对其余原文精确校验。
- [最终SDK构建](<../logs/legado-interaction-20261023/sdk-build-final.log>)实际退出0。原有警告仍存在，不宣称零警告。
- 图片加载/缓存/源/模型/数据库/下载逻辑不改；为本次新交互使用独立范围守卫，不覆盖之前历史基线。

先前失败如实处理：旧上一屏测试错用右上“下一页”区且不在可向上滚动位置；旧图片单击入口已移除，旧回归改为窗口入口并保留来源/历史/RTL断言；跨上一章用例需存在上一章。另有原生Up计数与双击空间阈值的真实实现缺陷，已通过源码审查定位、修复并补平台模型测试，而非只修断言。

## 产物与已完成安装

[签名包](<../dist/reader-legado-interaction-20261023-signed.hap>)，8,214,155字节。
SHA256：`5122ED52F5C9815470D4BF273B50777D4D3DE3C43CC083DB1FE4B82BA2BC201A`。
[产物审计](<../logs/legado-interaction-20261023/artifact.json>)。

用户确认重新连接授权后，已核对设备和哈希，并且仅执行：

```powershell
.\tools\install_verified.ps1 -HapPath 'dist\reader-legado-interaction-20261023-signed.hap' -Device '<device-id>' -EvidenceName 'legado-reader-user-install-20261023'
```

安装前先校验哈希与设备在线；成功必须有HDC明确`install bundle successfully`，不能只看退出0。
**不卸载、不清数据、不启动、不截图、不点击。** 新版安装已有明确成功证据；当前仍无功能/触感实机验收结论。HDC先前未连接时没有宣称已部署，重连授权后才安装。
