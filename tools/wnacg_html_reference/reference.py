"""Offline same-byte lxml oracle for new public captures. No HTTP or user data."""
import argparse, hashlib, json, pathlib
from lxml import html
parser=argparse.ArgumentParser()
parser.add_argument('files',nargs='+')
parser.add_argument('--out',required=True)
parser.add_argument('--status',type=int,default=None,help='Status from parent public capture evidence; do not infer from DOM')
parser.add_argument('--proof',default=None,help='Evidence path/trace proving captured public status and no credentials')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
selectors={
 'div.title_sort':'//div[contains(concat(" ",normalize-space(@class)," ")," title_sort ")]',
 'div.bodywrap':'//div[contains(concat(" ",normalize-space(@class)," ")," bodywrap ")]',
 'p.result > b':'//p[contains(concat(" ",normalize-space(@class)," ")," result ")]/b',
 'div.grid div.gallary_wrap > ul.cc > li':'//div[contains(concat(" ",normalize-space(@class)," ")," grid ")]//div[contains(concat(" ",normalize-space(@class)," ")," gallary_wrap ")]/ul[contains(concat(" ",normalize-space(@class)," ")," cc ")]/li',
 'a[href]':'//a[@href]',
}
rows=[]
for name in args.files:
 file=pathlib.Path(name).resolve()
 data=file.read_bytes()
 tree=html.fromstring(data.decode('utf-8',errors='replace'))
 row={'file':str(file.relative_to(root)).replace('\\','/'),'sha256':hashlib.sha256(data).hexdigest(),'parser':'lxml.html/libxml2 independent XPath','capturedHttpStatus':args.status,'httpProof':args.proof,'selectors':{}}
 for css,xpath in selectors.items():
  nodes=tree.xpath(xpath)
  row['selectors'][css]={'count':len(nodes)}
  if css=='p.result > b':row['selectors'][css]['texts']=[n.text_content().strip() for n in nodes]
 rows.append(row)
pathlib.Path(args.out).write_text(json.dumps(rows,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(rows,indent=2,ensure_ascii=False))
