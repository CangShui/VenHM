"""Generate evidence-bounded source observations, not regex-based blame.
Usage: python source_matrix_report.py run.jsonl report.md label [evidence.json]
"""
import collections
import json
import pathlib
import re
import sys


def load(path):
    rows = {}
    stages = collections.defaultdict(list)
    malformed = 0
    for line in pathlib.Path(path).read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except (ValueError, TypeError):
            malformed += 1
            continue
        source = record.get('source', '')
        stages[source].append((record.get('stage', ''), record.get('note', '')))
        if record.get('stage') == 'ROW':
            try:
                rows[source] = json.loads(record['note'])
            except (ValueError, TypeError, KeyError):
                malformed += 1
    return rows, stages, malformed


def classify(notes):
    """Describe observations; error wording alone cannot assign responsibility."""
    text = ' | '.join(notes).lower()
    if 'image_config_unsupported' in text:
        return 'APPLICATION_CAPABILITY_GAP', '明确未实现的图片配置；迁移层必须继续补'
    if re.search(r'not logged in|need login|login expired|未登录', text):
        return 'LOGIN_REQUIRED_OBSERVED', '源报告需要登录；未输入真实账号，不能验证登录后路径'
    if re.search(r'setting not found|requires configuration|需要配置', text):
        return 'CONFIGURATION_REQUIRED_OBSERVED', '观察到配置缺失；还需区分用户未配置与默认值迁移缺失'
    if re.search(r'(?:http|status(?: code)?|状态码)[\s:=]+[45]\d\d\b', text):
        return 'HTTP_FAILURE_OBSERVED', '观察到HTTP失败；不能排除请求适配/头部差异，不能直接归责站点'
    if re.search(r'\bcode\s+\d+|timeout|timed out|网络请求失败|network response', text):
        return 'TRANSPORT_OR_SDK_ERROR_OBSERVED', 'SDK/传输错误；SDK code401不等于HTTP401，原因待证据定位'
    if 'different=false' in text:
        return 'PAGINATION_COMPARISON_REQUIRED', '需先核对maxPage/next结束契约，不能因重复第二页就判分页迁移错误'
    return 'UNDETERMINED', '异常文本不足以区分源规则、响应模板与迁移实现，需要同输入对照'


def chain_ok(row):
    return row.get('l3') in ('SAMPLE_CHAIN_OK', 'SAMPLE_CHAIN_OK_SEARCH_NOT_PASSED')


def stage_ok(row, observations=None):
    if observations:
        for stage, note in observations:
            if stage.endswith(('_FAIL', '_ERROR')) or stage == 'ERROR':
                return False
            if stage == 'L2_SEARCH' and not re.match(r'^[^:]*:p1=\d+', note):
                # Older installed matrices called one successful keyword a pass
                # even when the other request threw. Preserve those failures.
                return False
    explore = row.get('explore', '')
    category = row.get('category', '')
    search = row.get('search', '')
    return (row.get('l1') == 'METADATA_OK' and
            (explore == 'NOT_APPLICABLE' or explore.startswith('SAMPLED_')) and
            (category == 'NOT_APPLICABLE' or category.startswith('PARTS_AND_REAL_TARGETS_SAMPLED_OK')) and
            search.startswith('TWO_KEYWORDS') and row.get('l3') == 'SAMPLE_CHAIN_OK')


def safe(value):
    text = str(value).replace('|', '/').replace('\n', ' ').replace('\r', ' ')
    text = re.sub(r'https?://\S+', '[URL]', text)
    return text[:300]


def link(path, output):
    file = pathlib.Path(path)
    if not file.is_absolute():
        file = pathlib.Path.cwd() / file
    try:
        target = pathlib.Path(__import__('os').path.relpath(file, pathlib.Path(output).resolve().parent)).as_posix()
    except ValueError:
        target = file.as_uri()
    return f'[{pathlib.Path(path).name}](<{target}>)'


def main(src, out, label='', evidence_path=None):
    rows, stages, malformed = load(src)
    overrides = json.loads(pathlib.Path(evidence_path).read_text(encoding='utf-8')) if evidence_path else {}
    end_notes = [note for stage, note in stages.get('matrix', []) if stage == 'END']
    begin = next((note for stage, note in stages.get('matrix', []) if stage == 'BEGIN'), '')
    match = re.search(r'installed=(\d+)', begin)
    expected = int(match.group(1)) if match else None
    complete = bool(end_notes) and malformed == 0 and (expected is None or len(rows) == expected)
    chains = [key for key, row in rows.items() if chain_ok(row)]
    sampled_all = [key for key, row in rows.items() if stage_ok(row, stages[key])]
    lines = [f'# 逐源矩阵观察报告：{label}', '',
             f'原始设备证据：{link(src, out)}。这里只执行公开只读取样，不登录、不发布、不变更网络收藏。', '',
             '## 完整性与判定边界', '',
             f'- 已输出源行：**{len(rows)} / {expected if expected is not None else "未知"}**；END标记：**{"有" if end_notes else "无"}**；坏JSON行：**{malformed}**。',
             f'- 本轮遍历完整性：**{"完整遍历已列源" if complete else "未完成/证据不完整，不得作为全源完成"}**。',
             f'- 详情/章节/取样图片链路成功：**{len(chains)}**（允许来自探索/分类候选；不等于搜索通过）。',
             f'- 已观测L1/探索/实际分类目标/搜索/阅读链路取样均无失败：**{len(sampled_all)}**。',
             '- **L0仍为部分契约，L4/L5真实账号和站点专项未测。无一行可因此升格为全部功能PASS。**',
             '- 旧“链路通过7个”忽略了nhentai/ykmh分类失败，也忽略Komiic的独立阅读链路；现将阶段分开展示。',
             '- 只有错误关键词不是定责证据；HTTP403可能涉及我们的UA/请求适配，不能作为源坏或上游豁免。', '',
             '## 全部源逐阶段观察', '',
             '| 源 | L1 | 探索 | 分类（实际请求） | 搜索 | 阅读链路 | 观察分类/待定位 |',
             '|---|---|---|---|---|---|---|']
    for key, row in rows.items():
        notes = [n for stage, n in stages[key] if stage not in ('L1', 'ROW', 'CLASSIFY')]
        observed, why = classify(notes)
        override = overrides.get(key, {})
        extra = override.get('finding', '')
        lines.append('| ' + ' | '.join([f'`{safe(key)}`', safe(row.get('l1')), safe(row.get('explore')),
            safe(row.get('category')), safe(row.get('search')), safe(row.get('l3')),
            safe(observed + '；' + (extra or why))]) + ' |')
    missing = [key for key in stages if key != 'matrix' and key not in rows]
    if missing:
        lines += ['', '仅有阶段日志、无最终ROW（可能只是额外公开探针）：' + '、'.join(f'`{safe(key)}`' for key in missing)]
    lines += ['', '## 失败点与可复现定位', '']
    for key, row in rows.items():
        notes = [(stage, note) for stage, note in stages[key] if stage not in ('L1', 'ROW', 'CLASSIFY')]
        failures = [(stage, note) for stage, note in notes if re.search(r'FAIL|ERROR', stage) or
                    re.search(r'error|failed|false|not logged|not found|invalid|not a function|undefined is not callable|失败|异常', note, re.I)]
        if not failures and stage_ok(row):
            continue
        lines += [f'### `{safe(key)}`', '']
        if key in overrides:
            entry = overrides[key]
            lines += [entry.get('finding', ''), '', '**证据适用范围：** ' + entry.get('limit', ''), '']
            for file in entry.get('files', []):
                lines.append('- 对照证据：' + link(file, out))
        if failures:
            for stage, note in failures[:6]:
                lines.append(f'- `{safe(stage)}`：{safe(note)}')
        else:
            lines.append('- 见上表阶段状态；不能以最后一条成功图片解码覆盖前面的失败。')
        lines.append('')
    lines += ['## 内建本地源（与20个远程脚本分列）', '',
              '- SourceManager另注册LocalSource；不在SourceDao安装脚本表中，因此不出现在上述20个ROW。',
              '- 本地导入/目录持久化/本地图片阅读不由远程矩阵覆盖；当前签名包未重新逐项验收，状态NOT_TESTED_CURRENT_PACKAGE。',
              '- 设置页21个源=20个安装脚本+1个内建本地源；不能把本地源静默算通过，也不能把它当第21个联网源。', '',
              '## 下一步与尚未验证', '',
              '- 未完成阶段继续独立复测；源内配置/真实账号需要用户设备操作，不在本报告伪造登录后结果。',
              '- 页面选源、tag导航、loading/error、剪贴板、左右单击与正文到详情需另附当前签名包真机UI证据。',
              '- 同源跨网络时点结果变化不是修复因果证明；“5变7”不能直接全部归功于迁移修复。',
              '- 证据受原始响应、UA、域名、时间、源码版本和取样范围约束；后续更新应保留旧报告，不能改写历史原始记录。']
    pathlib.Path(out).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'REPORT rows={len(rows)} expected={expected} complete={complete} reading_chains={len(chains)} all_public_stages_sampled={len(sampled_all)}')
    return {'rows':len(rows),'expected':expected,'complete':complete,'reading_chains':len(chains),'all_public_stages_sampled':len(sampled_all)}


if __name__ == '__main__':
    main(*sys.argv[1:])
