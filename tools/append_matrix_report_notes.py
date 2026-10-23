import pathlib,sys
p=pathlib.Path(sys.argv[1]);t=p.read_text(encoding='utf-8')
extra = """## 归因用的外部复核（本轮新增）

- **shonen_jump_plus**：其 `fetchBearerToken` 对 `/api/v1/user_account/access_token` 的响应**不检查状态码**就 `JSON.parse`。
  用标准主机客户端带同一组公开头部复现该请求，得到 **HTTP 403 + `text/html`**；
  因此 `unexpected token '<'` 的根因是**站点拦截**，不是迁移层桥缺陷（归因规则已按此修正）。
- **wnacg**：当前公开默认域名在本机独立测试返回 **HTTP 403**，同样不得判为源规则损坏；
  其脚本 `wnacg.js:491` 对空结果直接取 `[0].text` 是**源健壮性**问题，需在拿到同一响应后再定性。
- **ehentai**：`explore[].loadNext` 被迁移层硬调 `load`、搜索未传 `search.optionList` 默认值，
  已在源脚本+调用点确认，属于**迁移层缺口**（已修）。
- 结论：**“源脚本对错误响应不设防”与“站点拦截”必须分开记录**；`C_` 类不得当作豁免。

"""
t=t.replace('## 归因含义', extra+'## 归因含义')
p.write_text(t,encoding='utf-8')
print('EXTRA_SECTION_ADDED')
