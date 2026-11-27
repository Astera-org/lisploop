"""M2(1): undirected enumeration (law discovery) has no target, so the backward bound h is 0
for every class and the test s + h <= N never fails.  This script asks the remaining
question: does anything TARGET-FREE survive?  The obvious candidate is a coarser dedupe key:
keep one class per distinct LABEL instead of one per distinct column.

G1 = {+, -, *, neg} over x, y, 0, 1; 32 rows; every size up to S is enumerated and stored.
For each key:
   stored    classes kept (each still holds its full column: children are computed from it)
   coverage  share of plain's classes (distinct columns of size <= S) that the coarse search
             ever produces as a candidate
   laws      candidates whose column equals the column of the class they land in (true
             equations on the 32 rows), as a share of plain's
   false     candidates that land in a class with a DIFFERENT column (a "law" that is only a
             congruence of labels)

usage: python3 m5_undirected.py [--S 11] [--seed 0]
"""
import argparse
import operator
import random
import time
from collections import defaultdict

from q3lib import pick_rows

ap = argparse.ArgumentParser()
ap.add_argument('--S', type=int, default=11)
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--rows', type=int, default=32)
A = ap.parse_args()
rng = random.Random(A.seed)
xs = tuple(rng.randint(-9, 9) for _ in range(A.rows))
ys = tuple(rng.randint(-9, 9) for _ in range(A.rows))
leaves = [xs, ys, tuple([0] * A.rows), tuple([1] * A.rows)]
OPS = [(operator.add, True), (operator.sub, False), (operator.mul, True)]
r3 = pick_rows(xs, ys, 3, 4)
r5 = pick_rows(xs, ys, 5, 3)
sgn = lambda v: (v > 0) - (v < 0)

KEYS = [
    ('column (plain)', lambda c: c),
    ('first 16 rows', lambda c: c[:16]),
    ('first 8 rows', lambda c: c[:8]),
    ('parity, mod 3, sign on 32 rows', lambda c: (tuple(v & 1 for v in c), tuple(v % 3 for v in c),
                                                   tuple(map(sgn, c)))),
    ('mod 2, 3, 5 on 32 rows', lambda c: (tuple(v & 1 for v in c), tuple(v % 3 for v in c),
                                          tuple(v % 5 for v in c))),
    ('mod 2 x12, mod 3 x4, mod 5 x3 rows', lambda c: (tuple(c[r] & 1 for r in range(12)),
                                                       tuple(c[r] % 3 for r in r3),
                                                       tuple(c[r] % 5 for r in r5))),
    ('parity on 32 rows', lambda c: tuple(v & 1 for v in c)),
]


def enumerate_all(keyfn, S):
    rep = {}                       # key -> column of the kept class
    levels = defaultdict(list)
    produced = set()               # every distinct column ever evaluated (measurement only)
    evaluated = true_laws = false_laws = 0

    def file(col, s):
        nonlocal true_laws, false_laws
        produced.add(col)
        k = keyfn(col)
        old = rep.get(k)
        if old is None:
            rep[k] = col
            levels[s].append(col)
        elif old == col:
            true_laws += 1
        else:
            false_laws += 1

    for c in leaves:
        evaluated += 1
        file(c, 1)
    for s in range(2, S + 1):
        for c in levels[s - 1]:
            evaluated += 1
            file(tuple(map(operator.neg, c)), s)
        for s1 in range(1, s - 1):
            s2 = s - 1 - s1
            L1, L2 = levels[s1], levels[s2]
            for fn, comm in OPS:
                if comm and s1 > s2:
                    continue
                same = comm and s1 == s2
                for i1, c1 in enumerate(L1):
                    for i2 in range(i1 if same else 0, len(L2)):
                        evaluated += 1
                        file(tuple(map(fn, c1, L2[i2])), s)
    return dict(stored=len(rep), evaluated=evaluated, true_laws=true_laws, false_laws=false_laws,
                produced=produced, classes=set(rep.values()))


t0 = time.time()
print('# M2(1) undirected enumeration on G1, %d rows, every size up to %d stored; seed %d' % (A.rows, A.S, A.seed))
base = None
print('%-36s %8s %7s %10s %9s %10s %9s %9s' %
      ('dedupe key', 'stored', 'gain', 'evaluated', 'coverage', 'true laws', 'share', 'false'))
for name, kf in KEYS:
    r = enumerate_all(kf, A.S)
    if base is None:
        base = r
    cov = len(base['classes'] & r['produced']) / len(base['classes'])
    print('%-36s %8d %6.1fx %10d %8.1f%% %10d %8.1f%% %9d' %
          (name, r['stored'], base['stored'] / r['stored'], r['evaluated'], 100 * cov, r['true_laws'],
           100.0 * r['true_laws'] / max(1, base['true_laws']), r['false_laws']))
print('total %.1f s' % (time.time() - t0))
