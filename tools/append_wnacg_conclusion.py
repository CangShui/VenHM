import pathlib
p=pathlib.Path('docs/SOURCE_MATRIX_2026-10-15_newbuild.md')
t=p.read_text(encoding='utf-8')
extra = """## 决定性归因：绅士漫画 wnacg（本轮实测）

手机在**无 Cookie、公开路径**下对当前默认域名抓到 3 份 **HTTP 200** 响应
（30994 / 42559 / 42833 字符；本机同 URL 为 403，说明网络出口不同）。
用**独立解析器（lxml/libxml2，非本工程引擎）**对手机同一份字节解析：

| 选择器 | 独立解析器命中 |
|---|---|
| `p.result > b` | **0** |
| `div.grid div.gallary_wrap > ul.cc > li` | **0** |
| `div.title_sort` / `div.bodywrap` | 0 |
| `a[href]` | 58 |

页面确实是真实的绅士漫画搜索结果页（可见“搜索結果 … 同人誌 4623 中文 11426”），
但站点已**不再使用 `gallary_wrap`/`class="cc"` 这套结果列表标记**。
因此结论是：

- **不是本工程 HTML 引擎解析错误**（独立解析器结果一致为 0）。
- **是源脚本选择器相对站点当前标记已过期**（`wnacg.js` 1.0.6 期望旧结构）；
  脚本第 491 行又对空结果直接取 `p.result > b[0].text`，于是抛
  `cannot read property 'text' of undefined`。
- 修复方式应是**更新该源脚本/等待源仓库更新**，不是改应用桥或解析器；
  应用侧可做的是给出可读错误而不是裸 TypeError。

## 与上一轮构建的对比（同一套矩阵）

| | 上一轮包 | 本轮修正包 |
|---|---|---|
| 取样链路通过 | 5 | **7**（新增 manga_dex、copy_manga） |
| 分类阶段 | 仅静态标签 | 多数源出现 `PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE`（**真实发起**分类请求） |
| ehentai | `not a function` + `JSON.parse(undefined)`（A 类迁移缺口） | 不再出现；现为 0 结果（需登录/换词），归 UNDETERMINED |
| 到达图片解码 | 少 | Komiic 到 chapter3 page21/21 解码 1000x1333；comick 到 chapter30 page97（图片403）；manwaba 到 chapter23 page29 |

说明：本轮修的迁移缺口（游标探索、搜索默认选项、分类真实请求、逐阶段隔离）**产生了可测量的真实改善**。

"""
t=t.replace('## 归因含义', extra+'## 归因含义')
p.write_text(t,encoding='utf-8')
print('DECISIVE_SECTION_ADDED')
