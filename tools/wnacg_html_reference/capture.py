"""Public, credential-free installed-rule URLs only; no auth/CAPTCHA retries."""
import json, hashlib, datetime, pathlib, urllib.request, urllib.error
out = pathlib.Path(__file__).resolve().parent
urls = {
    'default-home': 'https://wnacg.com',
    'default-search-a': 'https://wnacg.com/search/?q=a&f=_all&s=create_time_DESC&syn=yes&p=1',
    'default-search-cjk': 'https://wnacg.com/search/?q=%E9%AD%94%E6%B3%95&f=_all&s=create_time_DESC&syn=yes&p=1',
    'domains': 'https://wn01.link/',
}
records = []
for label, url in urls.items():
    record = {'label':label, 'requested':url, 'timestampUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'proofSource':'Installed wnacg.js default domain0 and public endpoint templates', 'privateHeaders':False}
    try:
        try:
            response = urllib.request.urlopen(url, timeout=20)
        except urllib.error.HTTPError as e:
            response = e
        with response:
            data = response.read(4 * 1024 * 1024)
            record.update(status=response.code, finalUrl=response.geturl(), contentType=response.headers.get('Content-Type'), byteCount=len(data), sha256=hashlib.sha256(data).hexdigest())
            file = out / (label + '.html')
            file.write_bytes(data)
            record['captureFile'] = str(file.relative_to(out.parent.parent)).replace('\\','/')
            record['blockedHttp'] = response.code in (401,403,429)
    except Exception as e:
        record['transportError'] = str(e)
    records.append(record)
    print(json.dumps(record, ensure_ascii=False), flush=True)
(out / 'capture-proof.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')

# Independent libxml2 parser: XPath is explicit translation of exact rule CSS.
from lxml import html
selectors = {
    'div.title_sort': '//div[contains(concat(" ",normalize-space(@class)," ")," title_sort ")]',
    'div.bodywrap': '//div[contains(concat(" ",normalize-space(@class)," ")," bodywrap ")]',
    'p.result > b': '//p[contains(concat(" ",normalize-space(@class)," ")," result ")]/b',
    'div.grid div.gallary_wrap > ul.cc > li': '//div[contains(concat(" ",normalize-space(@class)," ")," grid ")]//div[contains(concat(" ",normalize-space(@class)," ")," gallary_wrap ")]/ul[contains(concat(" ",normalize-space(@class)," ")," cc ")]/li',
    'a[href]': '//a[@href]',
}
files = [out.parent.parent/'logs/upstream/wnacg-search-page.html', out.parent.parent/'logs/upstream/wnacg-domain-page.html'] + [out/(label+'.html') for label in urls if (out/(label+'.html')).exists()]
results = []
for file in files:
    data = file.read_bytes()
    tree = html.fromstring(data.decode('utf-8', errors='replace'))
    row = {'file':str(file.relative_to(out.parent.parent)).replace('\\','/'), 'sha256':hashlib.sha256(data).hexdigest(), 'parser':'lxml.html/libxml2 independent XPath', 'selectors':{}}
    for css, xpath in selectors.items():
        nodes = tree.xpath(xpath)
        row['selectors'][css] = {'count':len(nodes)}
        if css == 'p.result > b': row['selectors'][css]['texts'] = [n.text_content().strip() for n in nodes]
        if css == 'a[href]' and 'domain' in file.name: row['selectors'][css]['hrefs'] = [n.get('href') for n in nodes]
    results.append(row)
(out/'lxml-reference.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print('Independent lxml results written.', flush=True)
