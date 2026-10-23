# 仅本地验证：统一选源、同页聚合、下载重启9800005

## 执行范围

用户最新明确要求“不要急着装到手机，先在本地测试”。本记录对应这条要求之后的步骤：
**没有覆盖安装、启动、点击手机或真实源请求**。只运行本地生产代码夹具、现有主机NAPI夹具和真实SDK编译。
此前已安装包不变，以下新包仅在本地归档。

## 一、搜索/探索/分类：同一个用户选源

- [搜索页](<../entry/src/main/ets/features/SearchView.ets>)和探索/分类共同依赖[SelectedSource](<../entry/src/main/ets/features/SelectedSource.ets>)。
- 三处真实源选项来自同一份全部安装源列表，使用稳定sourceKey而非独立下标。
- 搜索选中B→探索/分类跟随B；探索/分类选中A→搜索跟随A。这一行为在三个**实际生产View方法**一起运行的回归中验证，不只是检查代码字符串。
- 某源不支持搜索时保留用户的同一选源并提示能力不足，不把全局源改成另一个源；源已移除同样明确提示，不静默切换。
- 重复进入搜索页先退订旧监听，避免多次筛选加载；切源时旧单源请求、旧聚合收尾和旧筛选元数据均不能覆盖当前状态。

## 二、聚合搜索：只在同一搜索页的下拉框

- “聚合搜索（全部源）”位于搜索源下拉框首项；没有独立聚合按钮/页面/路由。
- 聚合只是搜索模式，不是虚构的漫画源，因此进入聚合不会把探索/分类的真实源替换成“全部源”；选回一个真实源后，三处继续服务这个源。
- 修复了旧代码选择聚合不更新选中index0、再选回同一个真实源因提前返回而仍留在聚合项的问题。
- [聚合会话](<../entry/src/main/ets/features/AggregatedSearchSession.ets>)不再有三源请求上限：8个带未完成Promise的源在回归中全部启动，各自结果/失败独立，且各自使用自己的默认筛选。
- 请求全部发起不等于把所有图片同时挂载：[分区数据源](<../entry/src/main/ets/features/AggregatedSearchList.ets>)使用不可变快照和局部变化通知，搜索页LazyForEach只按需构建可视分区。源A完成不会重建源B已显示的图片。
- “更多”透传已提交关键词与入口源，不使用尚未执行的输入框草稿。界面通知抛错不会被误算成源错误或导致聚合Promise不结算。

## 三、下载重启：纠正9800005的过强归因

此前“9800005通常就是旧任务残留，全部停止再重试”**没有设备证据，现已撤回**。
9800005只表示连续任务校验失败，可来自`isModeSupported`或原生启动，不直接证明旧任务残留。

本地核对到的具体请求问题：旧请求`backgroundTaskModes=[DATA_TRANSFER]`却给`backgroundTaskSubmodes=[]`。
[公开API21映射](<https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-backgroundtasks-kit/js-apis-resourceschedule-backgroundTaskManager.md#backgroundtasksubmode21>)将DATA_TRANSFER映射到LIVE_VIEW_NOTIFICATION，而不是NORMAL_NOTIFICATION。
[公开参数校验实现](<https://github.com/openharmony/resourceschedule_background_task_mgr/blob/master/interfaces/kits/napi/src/bg_continuous_task_napi_module.cpp>)会拒绝空数组、长度不一致和不匹配子模式。
**这是公开合同/实现和当前SDK声明的依据，不冒充手机厂商二进制的源码证明。**

[后台协调器](<../entry/src/main/ets/features/BackgroundDownloadCoordinator.ets>)已改为：
- DATA_TRANSFER配LIVE_VIEW子模式；分阶段记录`is-mode-supported`/`native-start`及原始错误码，不记录请求、账号或堆栈正文。
- 删除无证据的`startWithRecovery`盲重试和无ID的“停止本应用全部后台任务”。只有已知、确属于当前租约的精确ID才能停止。
- 用户取消与原生启动并发时，原生稍后接受的ID不会丢失，会等待该次启动结算后按精确ID停止一次；其他任务ID的取消/挂起通知不影响当前任务。
- 系统仍拒绝后台许可时，[队列](<../entry/src/main/ets/features/DownloadQueue.ets>)可以完成用户明确启动的前台下载，保留具体后台拒绝码；退后台则暂停，不谎称有后台许可，不自动恢复。
- 暂停/继续/重启/删除保留代际与旧runner退出检查；已保存页和无关目录、历史、收藏不会被控制操作误删。

**尚不能宣称9800005在手机上消失、后台授权成功或长时间后台下载通过。**这需要用户之后安排实机测试。

## 四、测试完整性：防止未完成Promise的假通过

发现旧下载测试把HTTP桩设成永不结算，再await下载；Node可能在没有活跃句柄时以0退出，后续用例根本没运行。
已用可结算gate替代，新增逐例看门狗、beforeExit完整性检查和最终完成计数。

- [搜索回归](<../tools/search_filters_cases.js>)：**25项完整运行**，包括三View双向共享、同源从聚合返回、不可搜索/移除源、跨模式/新旧查询/元数据竞态、所有源同时启动、独立默认值、局部渲染与已提交关键词。
- [后台/队列回归](<../tools/background_download_cases.js>)：**27项完整运行**，包括9800005分别从两个阶段抛出、重复用户重试不盲停、不碰其他nativeID、晚到接受、任务控制、文件安全及前后台降级。
- [负向看门狗验证](<../tools/local_watchdog_cases.js>)：**2项**，只在内存把测试替换为永不结算，确认子进程确定退出1并报告WATCHDOG/缺少最终标记，不能以exit0冒充通过。
- [完整本地执行器](<../tools/run_local_search_download_regression.ps1>)：每套独立进程/超时/真实退出码/完成摘要；**46套（45 JS+1 Python）通过**。
- [逐套汇总](<../logs/local-search-download-20261017/summary.json>)和同目录stdout/stderr保存完整输出；不含新的手机证据。

执行器曾误把通过用例名称中的“failure”当失败，已改为只匹配行首失败记录，同时保留所有退出码/计数检查，并重新完整执行通过。不是修改预期绕过生产失败。

## 五、构建与未安装产物

- [本地SDK最终构建](<../logs/local-search-download-build-final-20261017.log>)真实退出0，签名HAP生成；已检查当前生产源码没有比产物更新。
- [最终仅本地归档HAP](<../dist/local-search-download-20261017-r2-signed.hap>)，SHA256 `FD73DAE918B40A3F8CCC2645517EFF95111DCE7124E69C31623D8E653D88C6E8`。
- [产物审计](<../logs/local-search-download-artifact-20261017.json>)状态`LOCAL_ONLY_NOT_INSTALLED`。

等待用户安排之后再做手机安装/界面与系统后台授权验证；本轮先停在本地，不将SDK编译或夹具成功当作手机修复通过。
