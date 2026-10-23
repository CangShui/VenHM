# 设备接回后的现有版本回归

> **最终更新**：对话框builder崩溃与加载取消竞态已经修复并覆盖安装。
> 最终冷启动设备UI自检PASS（含日志读回`auditFile=true`），历史4组/收藏10项回归PASS。
> 证据为`logs/ui-dialog-device-final/`与`logs/ui-host-final-app-evidence.log`，详见HANDOVER置顶修复记录。
> 后面的旧包快照和21:14崩溃均为历史，不是当前阻塞。

> **后续更新**：21:10–21:14已通过DevEco CLI登录、自动签名、构建并覆盖安装新包。
> 签名阻塞解除，历史29条保留，RSA1024参考向量与invokeFunction三种回程通过。
> UI自检触发builder上下文崩溃，仍未通过；证据见HANDOVER置顶CLI记录。
> 下文保留20:30–20:33旧安装版本快照，不代表当前部署状态。

## 结论与边界

2026-10-13（Asia/Shanghai），设备 `<device-id>` 已连接且解锁，现有应用能够冷启动。
**本次没有安装工作区的新包**：本机未找到签名材料，工程仍配置为 unsigned。
手机的验收页面缺少「运行 UI 对话框自检」和「源自检深度取样」入口，启动日志也没有
`invokeFunction round-trip OK` 或 RSA 向量。因此以下结果只对应手机上现有版本，不证明新代码可用。

## 证据

- 完整流式日志：`../logs/device-cold-start-20261013.log`。
- 本次冷启动 PID 10402 的应用日志：`../logs/device-existing-app-evidence-20261013.log`。
- 同一 PID 的源矩阵：`../logs/device-existing-source-matrix-20261013.log`。
- 验收页面树：`../dist/history-usability/device-usability-baseline.json`。
- 历史回归页面树：`../dist/history-usability/device-history-regression-final.json`。
- 收藏回归页面树：`../dist/history-usability/device-favorites-regression-final.json`。
- 测试后数据页面树：`../dist/history-usability/device-history-after-regression.json`、
  `../dist/history-usability/device-favorites-after-regression.json`。

原始流式日志包含历史缓冲记录；本报告使用 PID 10402、20:30:39 开始的冷启动轮次，不混入 PID 9617。

## 已执行的设备回归

| 项目 | 实际结果 |
|---|---|
| QuickJS 并发 Promise / TypedArray 子视图 | 启动日志通过 |
| 设置模拟异步 callback | 启动日志通过 |
| Cookie 范围/路径/Secure/过期/持久化及 JS set/get/delete | 启动离线用例通过；不是实际登录验收 |
| AES-128 ECB/CBC/CFB8/OFB128 | 启动参考向量通过 |
| GBK `中 → d6d0` | 启动参考向量通过 |
| 历史数据库及位置逻辑 | 4 组通过，20:31:55 |
| 收藏夹数据库逻辑 | 10 项通过，20:32:01；后两项从日志确认 |
| 测试清理 | 历史前后均 29 条；测试后仅默认收藏夹（0），首页本地漫画为 0；没有生成阅读样本 |

未卸载应用、未清空应用数据、未使用真实账号、未修改源设置。
这些是数据库逻辑回归，不等于批量操作 UI、跨重启续读和七模式的完整验收。

## 旧版自检结果：4/22

搜索词 `a`，时间 20:30:39–20:33:04。分母 22 包含 `local`、`demo_api` 两个内置源，
本轮实际注册的 JS 源为 20 个；不得称「22 个脚本全部可用」。
旧版仅测 1 词、1 页、1 章、封面/首张/末张，**未满足完整 L0–L3 标准**。

| 源 | 抽样页数 | 封面尺寸 | 首张尺寸 | 末张尺寸 |
|---|---:|---|---|---|
| hcomic | 28 | 500×719 | 1200×1725 | 1280×1800 |
| hitomi | 245 | 640×480 | 1600×1200 | 1032×1215 |
| nhentai | 40 | 500×706 | 1280×1807 | 1280×1807 |
| ManHuaGui v1.2.1 | 20（126 章中只取首章） | 132×176 | 900×1275 | 777×1200 |

**ManHuaGui 本轮通过**：文档中的历史「上游即坏」不能用于豁免这个已安装版本。
本轮未重新下载并逐字节比较脚本，不推断历史缺陷是如何修好的。

其余终止阶段：

| 源 | 现象（待定位，不作上游豁免） |
|---|---|
| local / demo_api | 无本地样本 / 未配置 API |
| komga / picacg | 缺 default_username / 未登录 |
| Komiic / copy_manga / manwaba / ikmmh / jm | `a` 搜索 0 结果 |
| ehentai | `unexpected token: 'undefined'`；优先调查解析/桥/源返回值 |
| manga_dex | Network response was not ok |
| comick / baozi | 422 / 403 |
| happy | 网络 2300999 |
| shonen_jump_plus | **SDK 参数错误 code 401: Parameter error，不是已证明的 HTTP 401** |
| ykmh | 详情 HTTP 500 |
| zaimanhua | 详情提示不存在或已删除 |
| wnacg | `cannot read property 'text' of undefined`，HTML/规则对照待做 |

## 继续前需要的操作

在本机 DevEco 为工程恢复自动签名（华为账号、当前设备 UDID），或迁移旧机器的对应签名材料。
确认 `products[].signingConfig` 与真实 `signingConfigs` 对应后构建 signed HAP，
**覆盖安装，不卸载**，保留现有 29 条历史。
若新签名与既有安装不一致而覆盖失败，先解决签名一致性，不能用卸载绕过。

接着再验证 `invokeFunction`、RSA、UI 五分支及深度矩阵。当前这些新能力仍待上板。
