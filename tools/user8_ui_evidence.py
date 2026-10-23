"""Assert recorded real-device UI observations (not a substitute for current live UI).
Only reads Venera-scoped JSON snapshots produced after PID/focus verification.
"""
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / 'logs/user8-ui'
EVIDENCE = []


def nodes(name):
    path = BASE / name
    data = path.read_bytes()
    tree = json.loads(data.decode('utf-8'))
    found = []
    def walk(node):
        found.append(node)
        for child in node.get('children', []):
            walk(child)
    for node in tree if isinstance(tree, list) else [tree]:
        walk(node)
    EVIDENCE.append({'file': str(path.relative_to(ROOT)).replace('\\', '/'), 'sha256': hashlib.sha256(data).hexdigest()})
    return found


def has(name, text, kind=None):
    return any(node.get('text') == text and (kind is None or node.get('type') == kind) for node in nodes(name))


checks = {}
checks['explore_initial_jm'] = has('1792045464915-a4b9-layout.out', '禁漫天堂', 'Select')
checks['category_retains_jm'] = has('1792045492989-e7c9-layout.out', '禁漫天堂', 'Select')
checks['category_changed_komiic'] = has('1792045557687-a787-layout.out', 'Komiic', 'Select')
checks['explore_follows_komiic'] = has('1792045567883-89e3-layout.out', 'Komiic', 'Select')
checks['detail_tag_routes_results'] = has('1792045814379-9b18-layout.out', '标签:魔法') and has('1792045814379-9b18-layout.out', '已到末页')
checks['category_real_loading'] = has('1792047085110-e2f5-layout.out', '正在加载分类/标签…')
checks['category_error_and_retry'] = has('1792047180722-3ca7-layout.out', '分类/标签列表加载失败，请重试') and has('1792047180722-3ca7-layout.out', '重试', 'Button')
checks['retry_stays_visible_on_failure'] = has('1792046676298-abb6-layout.out', '分类/标签列表加载失败，请重试')
checks['right_single_tap_1_to_2'] = has('1792046029073-6965-layout.out', '1 / 54') and has('1792046092178-c2ec-layout.out', '2 / 54')
checks['left_single_tap_2_to_1'] = has('1792046101661-7efe-layout.out', '1 / 54')
checks['center_no_turn'] = has('1792046143274-fd26-layout.out', '1 / 54')
checks['title_clipboard_os_paste_roundtrip'] = has('1792046892217-9d1c-layout.out', '魔法少女丹德莉恩', 'TextInput')
checks['longpress_tag_stays_detail'] = has('1792045939166-1d85-layout.out', '标签:魔法') and has('1792045939166-1d85-layout.out', '继续阅读')
checks['reader_details_same_comic'] = has('1792046153586-a1d2-layout.out', '魔法少女丹德莉恩') and has('1792046153586-a1d2-layout.out', '作者')
checks['home_continue_opens_reader'] = has('1792046285405-15ea-layout.out', '详情') and has('1792046285405-15ea-layout.out', '1 / 54')
checks['continue_reader_to_details'] = has('1792046315785-88c0-layout.out', '魔法少女丹德莉恩') and has('1792046315785-88c0-layout.out', '作者')
checks['details_back_home_not_reader_loop'] = has('1792046326125-e40f-layout.out', 'Venera HM') and has('1792046326125-e40f-layout.out', '首页')
settings = nodes('1792045412185-844f-layout.out')
checks['demo_settings_removed_visible'] = not any('演示' in node.get('text', '') for node in settings)
checks['wnacg_search24_current_ua_build'] = has('1792050889833-69f1-layout.out', '已加载 24 条')
checks['wnacg_search48_current_ua_build'] = has('1792050938010-134d-layout.out', '已加载 48 条')
checks['wnacg_reader121_current_ua_build'] = has('1792051021521-5241-layout.out', '1 / 121') and has('1792051044127-0496-layout.out', '2 / 121')
assert all(checks.values()), {name: ok for name, ok in checks.items() if not ok}
unique = {record['file']: record for record in EVIDENCE}
report = {'device': '<device-id>', 'checks': checks, 'files': list(unique.values()),
          'scope': 'Actual Venera UI snapshots; interaction tests on previous installed signed build, WNACG on current original-UA reviewed package; not all gestures/modes or wire-pixel verification.',
          'not_claimed': ['all reader modes/multitouch tested', 'all sources fully usable', 'L4/L5 real accounts', 'all chapters/images fetched', 'unchanged user history count']}
out = ROOT / 'logs/user8-ui/verified-ui-evidence-20261015.json'
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'PASS {len(checks)} actual recorded device-UI assertions; {len(unique)} exact file hashes; no new device actions')
