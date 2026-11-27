#!/usr/bin/env python3
# Compare numbers, evidence tags, code spans and quotations between pre-clarity and current section files.
import re, sys
from collections import Counter
base = '/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/'
def toks(s):
    out = Counter()
    for m in re.finditer(r'\*\*\[[A-Z][^\]]*\]\*\*', s): out['TAG ' + m.group(0)] += 1
    for m in re.finditer(r'`[^`]+`', s): out['CODE ' + m.group(0)] += 1
    for m in re.finditer(r'[“"]([^"”]{3,})["”]', s): out['QUOTE ' + m.group(1)] += 1
    s2 = re.sub(r'`[^`]+`', ' ', s)
    for m in re.finditer(r'[×~≈]?\d[\d,\.]*(?:[–-]\d[\d,\.]*)?(?:\s?×\s?10[⁰¹²³⁴⁵⁶⁷⁸⁹]+)?[×%]?', s2):
        t = m.group(0).rstrip('.,')
        out['NUM ' + t] += 1
    for m in re.finditer(r'§\d+(?:\.\d+)?', s): out['REF ' + m.group(0)] += 1
    return out
for f in sys.argv[1:]:
    a = toks(open(base + 'sections.preclarity/' + f + '.md').read())
    b = toks(open(base + 'sections/' + f + '.md').read())
    print('=====', f)
    for k in sorted(set(a) | set(b)):
        if a[k] != b[k]:
            print(f'  {a[k]:>2} -> {b[k]:>2}  {k}')
