#!/usr/bin/env python3
"""Merge the four slice reports and the parent's fragments into factcheck3-C.md."""
import re, sys, os
D = '/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-c/'
OUT = '/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/reports/factcheck3-C.md'

GROUPS = [
 ('FACTUAL ERROR', ['A1','A2','P1','C1','B1','B2','D3','D4','A3']),
 ('INCONSISTENCY', ['D1','C2','C3','C4','B5','D13','D14','A9','P4','C9','C12']),
 ('OVER-STATEMENT', ['C5','A4','B3','B4','A5','C6','D6','D5','A6','D10','B8','C10','C11']),
 ('MISSING CAVEAT', ['A7','A8','D7','B6','C7','D8','D11','D12','B7','C8','P3','D9']),
 ('COSMETIC', ['A10','A11','A12','A13','A14','B9','B10','B11','B12','B13','B14','B16','B17',
               'C13','C14','C15','C16','C17','C18','D15','D16','D17','D18','D19','D20','P5']),
 ('Outside the scope, noticed in passing', ['B15','P6','P7','P8']),
]
ALIAS = {'D2': 'P1', 'P2': 'D1'}   # duplicates that were merged

def sections(text):
    """split a part file on '## ' headings -> list of (heading, body)"""
    parts = re.split(r'(?m)^## (.+)$', text)
    out = []
    for i in range(1, len(parts), 2):
        out.append((parts[i].strip(), parts[i+1].strip('\n')))
    return out

def findings(body):
    parts = re.split(r'(?m)^\*\*(\d+)\. ', body)
    out = {}
    for i in range(1, len(parts), 2):
        out[int(parts[i])] = '**%s. ' % parts[i] + parts[i+1].rstrip() + '\n'
    return out

raw = {}
for L in 'ABCDP':
    raw[L] = open(D + 'part-%s.md' % L).read()

sec = {L: sections(raw[L]) for L in 'ABCDP'}
fnd = {}
for L in 'ABCDP':
    for h, b in sec[L]:
        if h.startswith('Findings'):
            for n, t in findings(b).items():
                fnd['%s%d' % (L, n)] = t

order = [k for _, ks in GROUPS for k in ks]
assert len(order) == len(set(order)), 'duplicate key'
missing = [k for k in fnd if k not in order and k not in ALIAS]
assert not missing, missing
absent = [k for k in order if k not in fnd]
assert not absent, absent
G = {k: i + 1 for i, k in enumerate(order)}
for a, b in ALIAS.items():
    G[a] = G[b]

PROTECT = [('(lit-discrete report, finding 7)', '(lit-discrete report, its f\x00inding 7)'),
           ('(finding 8) says', '(its f\x00inding 8) says')]
REF = re.compile(r'([Ff]indings?)(\s+)(\d+[a-d]?(?:(?:,\s*|\s+and\s+|\s+or\s+)\d+[a-d]?)*)')
def remap_local(text, L):
    for a, b in PROTECT:
        text = text.replace(a, b)
    def f(m):
        nums = re.sub(r'\d+', lambda d: str(G['%s%s' % (L, d.group(0))]), m.group(3))
        return m.group(1) + m.group(2) + nums
    text = REF.sub(f, text)
    return text.replace('f\x00inding', 'finding')
TAG = re.compile(r'\b([ABCDP])(\d+)\b')
REFT = re.compile(r'([Ff]indings?)(\s+)([ABCDP]\d+(?:(?:,\s*|\s+and\s+|\s+or\s+)[ABCDP]\d+)*)')
def remap_tags(text):
    def f(m):
        return m.group(1) + m.group(2) + TAG.sub(lambda t: str(G[t.group(1) + t.group(2)]), m.group(3))
    return REFT.sub(f, text)

# manual edits to merged duplicates
t = fnd['D19']
i = t.find(' (b) Same line:')
assert i > 0, 'D19 (b) not found'
t = t[:i].rstrip() + '\n'
t = t.replace('(§7.3, last paragraph; both present before the clarity pass)', '(§7.3, last paragraph; present before the clarity pass)')
t = t.replace('**\n(a) Line 909:', '**\nLine 909:')
fnd['D19'] = t

def get(L, prefix):
    for h, b in sec[L]:
        if h.startswith(prefix):
            return b
    raise KeyError((L, prefix))

out = []
out.append(remap_tags(open(D + 'frag-head.md').read()).rstrip() + '\n')
for title, ks in GROUPS:
    out.append('\n### %s\n' % title)
    for k in ks:
        L = k[0]
        t = remap_local(fnd[k], L)
        t = re.sub(r'^\*\*\d+\. ', '**%d. ' % G[k], t)
        out.append('\n' + t)

out.append('\n' + remap_tags(open(D + 'frag-gaps.md').read()).rstrip() + '\n')

out.append('\n## Changes against the pre-clarity version\n')
out.append('\nEach table lists every number, quotation, evidence tag, file-and-line reference or claim that was dropped, changed or added in one slice, and says what supports the change. "A.." , "B.." and "C.." in the support columns are items of `clarity-review.md`; "gap log" is the entry of the same name in the two gap logs.\n')
names = {'A': '§2 intro, §2.1, §2.2, §2.3', 'B': '§2.4 to §2.9 and §3', 'C': '§4 and §5', 'D': '§7.1, §7.3, §9 and Appendices A, B, C'}
for L in 'ABCD':
    out.append('\n### %s\n\n' % names[L])
    out.append(remap_local(get(L, 'Changes against'), L).strip() + '\n')

pt = re.sub(r'(?m)\| ([ABCDP]\d+) \|$', r'| finding \1 |', open(D + 'part-P-tables.md').read())
out.append('\n' + remap_tags(pt).rstrip() + '\n')

out.append('\n## Appendix A, row by row\n\n')
out.append(remap_local(get('D', 'Appendix A, row by row'), 'D').strip() + '\n')

out.append('\n## Checked and found correct\n')
for L in 'ABCD':
    out.append('\n### %s\n\n' % names[L])
    out.append(remap_local(get(L, 'Checked and found correct'), L).strip() + '\n')

out.append('\n## What could not be checked, and why\n')
cc = {'A': 'Not checked', 'B': 'What I could not check', 'C': 'Could not check', 'D': 'Could not check'}
for L in 'ABCD':
    out.append('\n### %s\n\n' % names[L])
    body = remap_local(get(L, cc[L]), L).strip()
    body = '\n'.join(l for l in body.split('\n') if 'were left to the fork' not in l)
    out.append(body + '\n')
out.append(remap_tags(open(D + 'frag-tail.md').read()))

text = ''.join(out)
open(OUT, 'w').write(text)
print('written', OUT, len(text), 'chars', text.count('\n'), 'lines')
for k in order:
    print(G[k], k, fnd[k][:90].replace('\n', ' '))
