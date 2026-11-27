"""Merge vocabulary files for one search run, dropping names already measured.
usage: python3 merge_vocabs.py OUT.json IN1.json IN2.json ... [--skip search_X.json ...]"""
import json
import sys

args = sys.argv[1:]
out = args[0]
skip = set()
ins = []
mode = 'in'
for a in args[1:]:
    if a == '--skip':
        mode = 'skip'
        continue
    if mode == 'skip':
        skip |= set(json.load(open(a)))
    else:
        ins.append(a)
voc = {}
for fn in ins:
    for k, v in json.load(open(fn)).items():
        if k not in skip and k not in voc:
            voc[k] = v
json.dump(voc, open(out, 'w'), indent=1)
print('%d vocabularies -> %s' % (len(voc), out))
for k in voc:
    print('   ', k)
