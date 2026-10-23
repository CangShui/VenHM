"""Offline independent lxml/XPath HOME expectations. No JS helper/source algorithms imported."""
import hashlib, json, pathlib, re
from urllib.parse import urljoin, urlsplit
from lxml import html, etree
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BASE = 'https://wnacg.com'
def cls(name):
    return 'contains(concat(" ",normalize-space(@class)," ")," '+name+' ")'
def norm(node):
    return ' '.join(node.text_content().split())
def one(node, query):
    values=node.xpath(query)
    assert values, query
    return values[0]
def card(li, mobile):
    a=one(li,'.//a['+cls('ImgA')+']' if mobile else './/div['+cls('pic_box')+']/a')
    image=one(a,'./img')
    title=one(li,'.//a['+cls('txtA')+']') if mobile and li.xpath('.//a['+cls('txtA')+']') else one(a,'./span') if mobile else one(li,'.//div['+cls('info')+']/div['+cls('title')+']/a')
    info=one(li,'.//span['+cls('info')+']' if mobile else './/div['+cls('info')+']/div['+cls('info_col')+']')
    return dict(id=re.search(r'-aid-(\d+)\.html',a.get('href')).group(1),title=norm(title),cover=urljoin(BASE+'/',image.get('data-original') or image.get('data-src') or image.get('src')),description=' '.join(info.text_content().strip().replace('\n','').replace('\t','').split()))
rows=[]
for folder,mobile in [('phone-upstream-ua',False),('phone',True)]:
    path=HERE/folder/'phone-0.html'; data=path.read_bytes(); text=data.decode('utf-8'); doc=html.fromstring(text,parser=html.HTMLParser(encoding='utf-8',huge_tree=True))
    sections=[]
    if mobile:
        for box in doc.xpath('//div['+cls('imgBox')+']'):
            heading=one(box,'./div['+cls('Sub_H2')+']')
            name=norm(one(heading,'./span['+cls('Title')+']'))
            href=one(heading,'./a[@href]').get('href')
            cards=[card(li,True) for li in box.xpath('.//ul['+cls('col_3_2')+']/li')]
            sections.append(dict(title=name,comics=cards,viewMore='category:'+name+'@'+href))
    else:
        heads=doc.xpath('//div['+cls('title_sort')+']'); bodies=doc.xpath('//div['+cls('bodywrap')+']')
        assert len(heads)==len(bodies)==6
        for heading,body in zip(heads,bodies):
            name=re.sub(r'\s+','',one(heading,'./div['+cls('title_h2')+']').text_content())
            href=one(heading,'./div['+cls('r')+']/a').get('href')
            # libxml2 is not an HTML5 treebuilder: missing </div> nests later li.
            # Ownership by nearest gallery UL avoids counting subsequent sections.
            owner=one(body,'.//div['+cls('gallary_wrap')+']/ul['+cls('cc')+']')
            cards=[card(li,False) for li in owner.xpath('.//li') if li.xpath('ancestor::ul[1]')[0] is owner]
            sections.append(dict(title=name,comics=cards,viewMore='category:'+name+'@'+href))
    selectors={'div.title_sort':'//div['+cls('title_sort')+']','div.bodywrap':'//div['+cls('bodywrap')+']','div.title_h2':'//div['+cls('title_h2')+']','div.gallary_wrap > ul.cc > li':'//div['+cls('gallary_wrap')+']/ul['+cls('cc')+']/li','div.imgBox':'//div['+cls('imgBox')+']','div.Sub_H2':'//div['+cls('Sub_H2')+']','ul.col_3_2 > li':'//ul['+cls('col_3_2')+']/li'}
    homeLinks=doc.xpath('//a[@href="/"]')
    rows.append(dict(file=str(path.relative_to(ROOT)).replace('\\','/'),sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),utf16Units=len(text.encode('utf-16-le'))//2,proof=json.loads(path.with_suffix('.proof.json').read_text(encoding='utf-8')),title=norm(one(doc,'//title')),selectors={s:len(doc.xpath(q)) for s,q in selectors.items()},sections=sections,rootHomeLinks=len(homeLinks),metaRefresh=doc.xpath('//meta[translate(@http-equiv,"REFSH","refsh")="refresh"]/@content'),duplicateClassTags=re.findall(r'<div\s+class="(?:title_sort|bodywrap)"\s+class="cc"\s*>',text)))
assert [len(s['comics']) for s in rows[0]['sections']]==[6,12,12,12,12,12]
assert [s['title'] for s in rows[0]['sections']]==['最新更新','同人誌CG畫集','單行漫畫','雜誌短篇','韓國漫畫','Cosplay寫真']
searches=[]
for i in [1,2]:
    path=HERE/'phone-upstream-ua'/f'phone-{i}.html'; data=path.read_bytes(); doc=html.fromstring(data.decode('utf-8'))
    nodes=doc.xpath('//div['+cls('grid')+']//div['+cls('gallary_wrap')+']/ul['+cls('cc')+']/li')
    cards=[card(li,False) for li in nodes]
    total=one(doc,'//p['+cls('result')+']/b').text_content()
    searches.append(dict(file=str(path.relative_to(ROOT)).replace('\\','/'),sha256=hashlib.sha256(data).hexdigest(),comics=cards,maxPage=(int(total.replace(',',''))+23)//24))
    assert len(cards)==24
output=dict(scope='Offline exported UTF-8 response text, not original wire bytes. XPath lxml independent of helper and production JS.',lxmlVersion=list(etree.LXML_VERSION),files=rows,searches=searches,urlContract=dict(publicBase=BASE,defaultPath=urlsplit(BASE).path or '/',root=urljoin(BASE,'/'),relative=urljoin(BASE+'/','albums.html')))
(HERE/'home_oracle.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
browser_fixtures=[dict(file=r['file'],sha256=r['sha256'],text=(ROOT/r['file']).read_text(encoding='utf-8'),selectors=list(r['selectors']),expected=[dict(title=s['title'],count=len(s['comics']),ids=[c['id'] for c in s['comics']]) for s in r['sections']] if 'phone-upstream-ua' in r['file'] else []) for r in rows]
template=(HERE/'home_browser_test.js').read_text(encoding='utf-8')
(HERE/'home_browser_generated.js').write_text(template.replace('__HOME_FIXTURES__',json.dumps(browser_fixtures,ensure_ascii=False)),encoding='utf-8')
print(json.dumps([{k:r[k] for k in ['file','sha256','title','selectors']}|{'sections':[{'title':s['title'],'count':len(s['comics']),'ids':[c['id'] for c in s['comics']]} for s in r['sections']]} for r in rows],ensure_ascii=False,indent=2))
