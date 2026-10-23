# 通用迁移增量：搜索筛选与分类排行榜

## 为什么不是“只剩绅士源”

这轮按用户要求继续补通用功能，而不是把网站失败当作剩余清单的全部。
主要未完项目仍有：聚合搜索/搜索历史/标签建议与翻译，网络收藏/绑定同步，评论，图片收藏与追更，
详情缩略图/分享/封面查看器，完整阅读器设置/手势/音量键，本地导入导出与漫画库，系统后台与归档下载，双向同步/冲突/定时任务等。
这些不因安装成功、一次源矩阵或本地回归而变成完成。

## 本轮新增1：搜索筛选真正进入界面与分页

对照固定原版提交 `7110c19c4f3e342cf33d358d6be9058d8abc2505`：
[源解析合同](<https://github.com/CyrilPeng/Venera-Next/blob/7110c19c4f3e342cf33d358d6be9058d8abc2505/lib/features/comic_source/parser.dart#L779-L835>)、
[搜索面板](<https://github.com/CyrilPeng/Venera-Next/blob/7110c19c4f3e342cf33d358d6be9058d8abc2505/lib/features/search/search_page.dart>)、
[结果页筛选](<https://github.com/CyrilPeng/Venera-Next/blob/7110c19c4f3e342cf33d358d6be9058d8abc2505/lib/features/search/search_result_page.dart>)。

此前只是请求层替没有界面的搜索填入默认选项，用户不能选择；每页会话都传空数组，改变选项也无法锁定到同一查询。
现在包括：

- [源筛选元数据适配器](<../entry/src/main/ets/source/JsSearchOptionsAdapter.ets>)按源读取 `search.optionList`，支持动态getter；首横线分key/label，标签中的后续横线和空key均保留。
- [模型](<../entry/src/main/ets/source/ComicSource.ets>)补齐 `select` / `multi-select` / `dropdown` 类型，保留声明默认值的JSON序列化；缺省多选为空数组，单选/下拉为首key。
- [筛选状态策略](<../entry/src/main/ets/features/SearchFilterPolicy.ets>)验证默认值/选项范围/位置顺序，多选保持JSON数组；无效声明不是静默忽略，而是可见错误和刷新。
- [搜索界面](<../entry/src/main/ets/features/SearchView.ets>)有展开/收起、单选/多选/下拉和重置；只改筛选不会每次立即发网络，点击搜索后生效。切源保留稳定sourceKey，不因列表重排换源，不把被移除的源静默替换为另一个。
- [搜索会话](<../entry/src/main/ets/features/SearchSession.ets>)复制提交时筛选快照；普通页和游标页都传相同快照，源回调或界面后续原地修改数组不能污染分页；切源/改条件/退出的晚到结果不覆盖当前查询。

未覆盖：聚合搜索、搜索历史/快捷词、标签建议/翻译、自动语言过滤、搜索源管理仍是独立未迁移项，不称整个搜索模块完成。

## 本轮新增2：源锁定排行榜

对照[原版排行适配](<https://github.com/CyrilPeng/Venera-Next/blob/7110c19c4f3e342cf33d358d6be9058d8abc2505/lib/features/comic_source/parser.dart#L707-L775>)和
[原版排行页](<https://github.com/CyrilPeng/Venera-Next/blob/7110c19c4f3e342cf33d358d6be9058d8abc2505/lib/features/discovery/ranking_page.dart>)。

- [分类落地页](<../entry/src/main/ets/features/CategoryView.ets>)保留 `enableRankingPage` 并提供真实“排行榜”入口。EH这类 `parts:[]` 但有排行的分类不再一概报空分类。
- [排行模型](<../entry/src/main/ets/source/RankingData.ets>)与[适配器](<../entry/src/main/ets/source/JsRankingAdapter.ets>)遵守 `categoryComics.ranking.options`、`load(option,page)` 与 `loadWithNext(option,next)`；有load时优先load，不猜测loadNext别名。
- [会话](<../entry/src/main/ets/features/RankingSession.ets>)和[页面](<../entry/src/main/ets/pages/RankingPage.ets>)从路由sourceKey锁定源；有排序选项、加载/错误/空列表、重试和分页，点漫画仍回到原源详情。
- 普通页尊重有限maxPage；游标首请求传null，后续透传不透明cursor，循环cursor/空页/纯重复结果结束。重试保留已提交结果/页码/游标；切榜后旧请求、异常、finally不能干扰当前状态。
- 缺失加载方法、未安装/已移除的源、空排行选项都显式失败，不换源或声称通过。

未覆盖：探索分区更多、override发现页、所有源的真实排行和账号权限，不能由这次离线回放推出可用。

## 验证与产物

- [搜索生产方法测试](<../tools/search_filters_cases.js>)：**12项**，默认值、多选JSON、空key、源元数据异常、两种分页快照、切源/退出竞态和可见重试。
- [搜索实际主机NAPI测试](<../tools/search_filters_napi_cases.js>)：**5项**，生产元数据适配器与完整未修改安装EH源的请求构建，**2次内存拦截请求，零真实网络**。
- [排行生产方法测试](<../tools/ranking_cases.js>)：**15项**。
- [排行实际主机NAPI测试](<../tools/ranking_napi_cases.js>)：**6项**，完整未修改WNACG/EH/Komiic源，生产parser→configure→factory→session，**16次内存拦截请求，零真实网络**。
- [全量回归](<../logs/search-ranking-regression-20261016.log>)：**40组JS套件 + Python报告/历史手机记录断言通过**。其中历史手机记录不是新功能手机实测。
- [真实SDK/API21构建日志](<../logs/discovery-search-ranking-build-20261016.log>)：退出0、签名HAP完成。
- [签名包](<../dist/search-ranking-20261016-signed.hap>) SHA256 `14E1E03B04BA9DD770319598BEA9B655BCCF370AF432F1B1489A2308EB98E3A5`；[产物审计](<../logs/search-ranking-artifact-20261016.json>)。

**本轮没有覆盖安装或占用手机，没有输入账号，也没有将本地/主机NAPI结果写成真机/站点通过。**
此前阅读器白屏/卡顿修复已安装并确认首屏，但JM长章节持续翻页和设备帧率仍需专项验收。

## 下一步

继续补探索分区/更多跳转、详情评论的只读链路与缩略图；再按依赖推进网络收藏/追更、导入后台下载和完整同步。
新搜索面板与排行榜的真机点验应在用户安排的窗口进行；真实源返回403/空数据时继续区分站点响应、源脚本和迁移适配，不直接豁免。
