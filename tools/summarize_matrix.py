import json,sys,pathlib,collections
p=pathlib.Path(sys.argv[1])
rows={};stages=collections.defaultdict(list)
for line in p.read_text(encoding='utf-8').splitlines():
    line=line.strip()
    if not line: continue
    try: rec=json.loads(line)
    except Exception: continue
    src=rec.get('source','');stage=rec.get('stage','');note=rec.get('note','')
    stages[src].append((stage,note))
    if stage=='ROW':
        try: rows[src]=json.loads(note)
        except Exception: pass
print(f"file={p.name} sources_with_rows={len(rows)}")
order=[s for s in stages if s!='matrix']
for src in order:
    r=rows.get(src)
    if r:
        print(f"{r.get('key'):22s} exp={r.get('explore','?'):52s} cat={r.get('category','?'):52s} search={r.get('search','?'):34s} L3={r.get('l3','?'):34s} {r.get('classification','?')}")
    else:
        last=[n for s,n in stages[src] if s not in ('L1',)][-1:] or ['']
        print(f"{src:22s} NO_ROW last={last[0][:80]}")
print('END_MARKER', 'YES' if any(s=='END' for s,_ in stages.get('matrix',[])) else 'NO')
