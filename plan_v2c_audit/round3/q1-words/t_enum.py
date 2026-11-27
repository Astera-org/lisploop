"""Smoke test: how big is the enumerated word pool, and how long does enumeration take?
usage: python3 t_enum.py [S] [fold]"""
import sys
import time
from collections import Counter

from wordlib import *

S = int(sys.argv[1]) if len(sys.argv) > 1 else 4
fold = len(sys.argv) > 2 and sys.argv[2] == 'fold'
pr = Probes(seed=0, P=800)
print('value table: %d distinct lists' % pr.NV)
allowed = set(n for (n, at, rt, fn) in OPS)
st = {}
t0 = time.time()
w = enum_list_words(pr.pool, allowed, S=S, card=8, fold=fold, log=print, stats=st)
print('S=%d fold=%s: %d word partitions in %.1f s' % (S, fold, len(w), time.time() - t0))
bysize = Counter(s for (s, t) in w.values())
print('by size:', sorted(bysize.items()))
bycard = Counter(len(set(k)) for k in w)
print('by card:', sorted(bycard.items()))
for s in sorted(bysize):
    ex = [tstr(t) for (ss, t) in w.values() if ss == s][:12]
    print(s, ex)
iw = enum_int_words(pr.E, allowed, S=5, card=8)
print('int words:', len(iw), sorted(Counter(s for (s, t) in iw.values()).items()))
print([tstr(t) for (s, t) in iw.values()][:60])
