"""Deterministic checks: complete source traversal != reading chain != all-stage pass."""
import importlib.util
import json
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('report', ROOT / 'tools/source_matrix_report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)
assert report.classify(['TypeError: not a function'])[0] == 'UNDETERMINED'
assert report.classify(['SyntaxError: unexpected token: undefined'])[0] == 'UNDETERMINED'
assert report.classify(['record 4012 failed'])[0] == 'UNDETERMINED'
assert report.classify(['SDK code 401 Parameter error'])[0] == 'TRANSPORT_OR_SDK_ERROR_OBSERVED'
assert report.classify(['HTTP 403'])[0] == 'HTTP_FAILURE_OBSERVED'
assert report.classify(['TypeError: network is undefined'])[0] == 'UNDETERMINED'
row = dict(l1='METADATA_OK', explore='SAMPLED_PAGES', category='FAIL', search='TWO_KEYWORDS_SAMPLED_ONE_PASSED', l3='SAMPLE_CHAIN_OK')
assert report.chain_ok(row)
assert not report.stage_ok(row)
with tempfile.TemporaryDirectory(prefix='venera-source-report-') as temp:
    src = pathlib.Path(temp) / 'run.jsonl'
    out = pathlib.Path(temp) / 'report.md'
    records = [dict(source='matrix', stage='BEGIN', note='installed=2'),
               dict(source='a', stage='ROW', note=json.dumps(dict(key='a', **row))),
               dict(source='b', stage='ROW', note=json.dumps(dict(key='b', **row))),
               dict(source='matrix', stage='END', note='rows=2')]
    src.write_text('\n'.join(json.dumps(record) for record in records), encoding='utf-8')
    result = report.main(src, out, 'test')
    assert result['complete'] and result['reading_chains'] == 2 and result['all_public_stages_sampled'] == 0
    records.pop()
    src.write_text('\n'.join(json.dumps(record) for record in records), encoding='utf-8')
    assert not report.main(src, out, 'incomplete')['complete']
print('PASS 10 source report evidence-boundary contracts; no site/device action')
