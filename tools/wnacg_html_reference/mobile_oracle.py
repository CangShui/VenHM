"""Offline independent lxml audit of exact phone response-text captures. No network."""
import hashlib, json, pathlib, re
from lxml import html, etree
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=pathlib.Path(__file__).resolve().parent
source=(ROOT/'logs/user8-installed-scripts/wnacg.js').read_text(encoding='utf-8')
installed=list(dict.fromkeys(re.findall(r'querySelector(?:All)?\("([^"]+)"\)', source)))
modern=['div.imgBox','div.Sub_H2','div.Sub_H2 > span.Title','div.Sub_H2 > a[href]', 'ul.col_3_2 > li','ul#classify_container > li','a.ImgA','a.ImgA > img','a.ImgA > span','a.txtA','span.info','img[data-original]','img[data-src]','meta[http-equiv]','script','style']

def xpath(css):
    # Explicit small CSS->XPath subset: all literal installed selectors are in this subset.
    tokens=re.findall(r'[^\s>]+|>',css)
    result='.'; axis='//'
    for token in tokens:
        if token=='>': axis='/'; continue
        tag=re.match(r'^[\w-]+|^\*',token)
        part=tag.group() if tag else '*'
        suffix=token[len(tag.group()) if tag else 0:]
        attrs=re.findall(r'\[([\w-]+)\]',suffix)
        suffix=re.sub(r'\[[\w-]+\]','',suffix)
        for kind,name in re.findall(r'([.#])([\w-]+)',suffix):
            part+=f'[@id="{name}"]' if kind=='#' else f'[contains(concat(" ",normalize-space(@class)," ")," {name} ")]'
        for attr in attrs: part+=f'[@{attr}]'
        assert not re.sub(r'[.#][\w-]+','',suffix),css
        result+=axis+part; axis='//'
    return result

def records(nodes):
    result=[]
    for li in nodes:
        links=li.xpath(xpath('a.ImgA')); assert len(links)==1
        a=links[0]; imgs=a.xpath('./img'); assert len(imgs)==1
        titles=li.xpath(xpath('a.txtA')) or a.xpath('./span')
        assert len(titles)==1
        title=' '.join(titles[0].text_content().split())
        href=a.get('href'); ident=re.search(r'-aid-(\d+)\.html',href).group(1)
        image=imgs[0].get('data-original') or imgs[0].get('data-src') or imgs[0].get('src')
        info=li.xpath(xpath('span.info')); assert len(info)==1
        result.append({'id':ident,'title':title,'cover':'https:'+image if image.startswith('//') else image,'description':' '.join(info[0].text_content().split())})
    return result
rows=[]
for i in range(3):
    rel=f'tools/wnacg_html_reference/phone/phone-{i}.html'
    data=(ROOT/rel).read_bytes(); text=data.decode('utf-8',errors='strict')
    tree=html.fromstring(text)
    proofrel=f'tools/wnacg_html_reference/phone/phone-{i}.proof.json'
    proof=json.loads((ROOT/proofrel).read_text(encoding='utf-8'))
    counts={s:len(tree.xpath(xpath(s))) for s in installed+modern}
    cards=records(tree.xpath(xpath('ul.col_3_2 > li' if i==0 else 'ul#classify_container > li')))
    sections=[]
    if i==0:
        for box in tree.xpath(xpath('div.imgBox')):
            sections.append({'title':' '.join(box.xpath(xpath('div.Sub_H2 > span.Title'))[0].text_content().split()),'href':box.xpath(xpath('div.Sub_H2 > a[href]'))[0].get('href'),'comics':records(box.xpath(xpath('ul.col_3_2 > li')))})
    rows.append({'file':rel,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'unicodeCodepoints':len(text),'utf16Units':len(text.encode('utf-16-le'))//2,'utf8Strict':True,'replacementCharacters':text.count('\ufffd'),'metaCharset':tree.xpath('//meta[@http-equiv="Content-Type"]/@content'),'proofFile':proofrel,'proof':proof,'wireCharsetHeader':'NOT_CAPTURED','wireBytes':'NOT_CAPTURED: file is exported response text encoded as UTF-8','selectors':counts,'cards':cards,'sections':sections,'paginator':[{'text':' '.join(n.text_content().split()),'href':n.get('href')} for n in tree.xpath(xpath('div.f_left.paginator > a'))],'images':{'total':len(tree.xpath('//img')),'protocolRelative':len(tree.xpath('//img[starts-with(@src,"//")]')),'rootRelative':len(tree.xpath('//img[starts-with(@src,"/") and not(starts-with(@src,"//"))]')),'absolute':len(tree.xpath('//img[starts-with(@src,"https://") or starts-with(@src,"http://")]')),'dataOriginal':len(tree.xpath('//img[@data-original]')),'dataSrc':len(tree.xpath('//img[@data-src]'))},'structure':{'scripts':len(tree.xpath('//script')),'styles':len(tree.xpath('//style')),'literalDesktopClassesInMarkup':bool(re.search(r'class=["\'][^"\']*(?:title_sort|bodywrap|gallary_wrap)',text))}})
output={'scope':'offline exported response text, strict UTF-8, independent lxml.html/libxml2; not original HTTP entity bytes','lxmlVersion':list(etree.LXML_VERSION),'libxmlVersion':list(etree.LIBXML_VERSION),'installedSelectors':installed,'modernSelectors':modern,'files':rows}
(OUT/'mobile-oracle.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'installedSelectorCount':len(installed),'modernSelectorCount':len(modern),'files':[{'file':r['file'],'cards':len(r['cards']),'sections':len(r['sections']),'images':r['images'],'utf8Strict':r['utf8Strict'],'proofCharactersMatchUTF16':r['proof']['characters']==r['utf16Units']} for r in rows]},ensure_ascii=False,indent=2))
