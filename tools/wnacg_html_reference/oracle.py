"""Offline independent libxml2 reference for the two concrete port regressions."""
import json, pathlib
from lxml import html, etree
out = pathlib.Path(__file__).resolve().parent
parent=html.fromstring('<div id="p">before<!--note--><a href="/x">link</a>after<b>end</b></div>')
node_types=[]
element_names=[]
texts=[]
if parent.text: node_types.append('text');element_names.append(None);texts.append(parent.text)
for n in parent:
    comment=isinstance(n,etree._Comment)
    node_types.append('comment' if comment else 'element')
    element_names.append(None if comment else n.tag)
    texts.append(n.text if comment else None)
    if n.tail:node_types.append('text');element_names.append(None);texts.append(n.tail)
children=[n for n in parent if not isinstance(n,etree._Comment)]
next_element=children[0].getnext()
while isinstance(next_element,etree._Comment):next_element=next_element.getnext()
node_result={'nodeTypes':node_types,'elementNames':element_names,'childNames':[n.tag for n in children], 'dotHref':children[0].get('href'), 'bracketHref':children[0].get('href'), 'nextName':next_element.tag, 'texts':texts}
child_tree=html.fromstring('<p class="result"><span><b>nested</b></span><b>direct</b></p>')
child_result=[n.text_content() for n in child_tree.xpath('./b')]
sibling_tree=html.fromstring('<main><div id="p">parent<span>nested</span></div>text<!--comment--><span>adjacent</span><i>gap</i><span>later</span></main>')
sibling_result={'adjacent':[n.text_content() for n in sibling_tree.xpath('./div[@id="p"]/following-sibling::*[1][self::span]')], 'general':[n.text_content() for n in sibling_tree.xpath('./div[@id="p"]/following-sibling::span')]}
result={'parser':'independent lxml.html/libxml2, no production JS reuse','cases':{'node_toElement contract':node_result, 'spaced child combinator must exclude nested descendant':child_result, 'spaced adjacent and general combinators':sibling_result}}
(out/'microcase-oracle.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
