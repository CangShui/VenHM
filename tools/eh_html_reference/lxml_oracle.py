"""Independent OFFLINE libxml2/lxml tree/count oracle; NOT HTML5 implicit tbody oracle.
No HTTP, no credential reads, no DOM content/attributes printed.
"""
import json
from pathlib import Path
from lxml import html
HERE=Path(__file__).resolve().parent
spec=json.loads((HERE/'probe_spec.json').read_text(encoding='utf-8'))
fixtures=json.loads((HERE/'oracle_input.json').read_text(encoding='utf-8'))

def css_to_xpath(css):
    # Only the exact source grammar under test: tag/id/classes, child,
    # descendant and comma group. Independent XPath evaluator, no JS engine.
    import re
    branches=[]
    for group in css.split(','):
        tokens=re.findall(r'[^\s>]+|>',group.strip())
        expr='';axis='//'
        for token in tokens:
            if token=='>':
                axis='/'
                continue
            tag=re.match(r'^[A-Za-z][A-Za-z0-9_-]*|^\*',token)
            name=tag.group() if tag else '*'
            step=name
            for marker,value in re.findall(r'([.#])([A-Za-z0-9_-]+)',token):
                step += "[@id='"+value+"']" if marker=='#' else "[contains(concat(' ',normalize-space(@class),' '),' "+value+" ')]"
            expr+=axis+step
            axis='//'
        branches.append(expr)
    return ' | '.join(branches)

rows=[]
for fixture in fixtures:
    tree=html.fromstring(fixture['html'])
    counts={q:len(tree.xpath(css_to_xpath(q))) for q in fixture['counts']}
    diff={q:{'production':fixture['counts'][q],'lxml':n} for q,n in counts.items() if n!=fixture['counts'][q]}
    rows.append({'name':fixture['name'],'countQueries':len(counts),'countDifferences':diff,'counts':counts})
    print(f"LXML {fixture['name']}: queries={len(counts)} countDifferences={len(diff)}")
result={'oracle':'lxml.html/libxml2; independent XPath, NOT HTML5 table tree construction','fixtures':len(rows),'rows':rows}
(HERE/'lxml_results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
if any(r['countDifferences'] for r in rows):
    raise SystemExit('LXML_COUNT_MISMATCH inspect private structural-only output')
print(f'LXML_OFFLINE_PASS fixtures={len(rows)}; implicit tbody NOT modeled/claimed')
