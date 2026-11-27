"""Q1 (integers): does lumpability surface meaningful quotients from an ENUMERATED pool?

Pool: every unary term over x up to --size nodes, leaves x and constants 0..5,
operators + * mod < = abs sgn  (< and = return 0/1).  Nothing is hand-picked.
Candidates are deduplicated by the PARTITION they induce on the evaluation set
E = [-100, 100] (every value an operator can produce on the probe grid), keeping
the first = smallest term; partitions with 1 block or more than --blocks blocks
are dropped.

Lump(alpha; f) = 1 - H(alpha(f(x,y)) | alpha(x), alpha(y)) / H(alpha(f(x,y)))
on the uniform probe grid x, y in [-G, G] (unary f: x in [-G, G]); plug-in
entropies; rows where f is undefined (division by zero) are skipped; if
H(alpha(f)) = 0 the value is 0 (the quotient says nothing about f's output).

usage: python3 q1_int.py [--size 7] [--G 10] [--blocks 6] [--trunc]
"""
import argparse
import math
import sys
import time
from collections import Counter

ap = argparse.ArgumentParser()
ap.add_argument('--size', type=int, default=7)
ap.add_argument('--G', type=int, default=10)
ap.add_argument('--blocks', type=int, default=6)
ap.add_argument('--trunc', action='store_true', help='truncating div/rem instead of floor div/mod')
ap.add_argument('--top', type=int, default=15)
A = ap.parse_args()

G = A.G
E = list(range(-G * G, G * G + 1))
EI = {v: i for i, v in enumerate(E)}


def fdiv(a, b):
    if A.trunc:
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b >= 0) else -q
    return a // b


def fmod(a, b):
    if A.trunc:
        return a - b * fdiv(a, b)
    return a % b


OPS8 = [('+', 2, lambda a, b: a + b), ('-', 2, lambda a, b: a - b), ('*', 2, lambda a, b: a * b),
        ('neg', 1, lambda a: -a), ('max', 2, max), ('min', 2, min),
        ('div', 2, lambda a, b: fdiv(a, b) if b else None),
        ('mod', 2, lambda a, b: fmod(a, b) if b else None)]
RING4 = ['+', '-', '*', 'neg']
SIX = ['+', '-', '*', 'neg', 'max', 'min']
ALL8 = [o[0] for o in OPS8]

# probe tables of the operators (indices into E)
GRID = range(-G, G + 1)
PROBE = {}
for name, ar, fn in OPS8:
    rows = []
    if ar == 1:
        for x in GRID:
            rows.append((EI[x], None, EI[fn(x)]))
    else:
        for x in GRID:
            for y in GRID:
                r = fn(x, y)
                if r is None:
                    continue
                rows.append((EI[x], EI[y], EI[r]))
    PROBE[name] = rows


def H(counter, n):
    return -sum(c / n * math.log2(c / n) for c in counter.values())


def lump(lab, name):
    """lab: tuple of block labels over E."""
    rows = PROBE[name]
    n = len(rows)
    joint = Counter()
    inp = Counter()
    out = Counter()
    for (i, j, k) in rows:
        a = (lab[i], lab[j] if j is not None else None)
        o = lab[k]
        joint[(a, o)] += 1
        inp[a] += 1
        out[o] += 1
    ho = H(out, n)
    if ho < 1e-12:
        return 0.0
    hcond = H(joint, n) - H(inp, n)
    return 1.0 - hcond / ho


def canon(vals):
    """Canonical partition label vector: blocks numbered by first occurrence."""
    m = {}
    out = []
    for v in vals:
        k = m.get(v)
        if k is None:
            k = m[v] = len(m)
        out.append(k)
    return tuple(out)


# ------------------------------------------------------------ enumerate the pool
def sgn(v):
    return (v > 0) - (v < 0)


t0 = time.perf_counter()
levels = {1: []}
seen = {}
n_terms = 0


def add(size, term, vals):
    global n_terms
    n_terms += 1
    if vals in seen:
        return
    seen[vals] = (size, term)
    levels.setdefault(size, []).append((term, vals))


add(1, 'x', tuple(E))
for c in range(6):
    add(1, str(c), tuple([c] * len(E)))
for s in range(2, A.size + 1):
    for (t, v) in levels.get(s - 1, []):
        add(s, '(abs %s)' % t, tuple(map(abs, v)))
        add(s, '(sgn %s)' % t, tuple(map(sgn, v)))
    for s1 in range(1, s - 1):
        s2 = s - 1 - s1
        for (t1, v1) in levels.get(s1, []):
            for (t2, v2) in levels.get(s2, []):
                add(s, '(+ %s %s)' % (t1, t2), tuple(map(lambda a, b: a + b, v1, v2)))
                add(s, '(* %s %s)' % (t1, t2), tuple(map(lambda a, b: a * b, v1, v2)))
                if 0 not in v2:
                    add(s, '(mod %s %s)' % (t1, t2), tuple(map(lambda a, b: a % b, v1, v2)))
                add(s, '(< %s %s)' % (t1, t2), tuple(map(lambda a, b: int(a < b), v1, v2)))
                add(s, '(= %s %s)' % (t1, t2), tuple(map(lambda a, b: int(a == b), v1, v2)))
t_enum = time.perf_counter() - t0

# partitions
parts = {}
order = sorted(seen.items(), key=lambda kv: kv[1][0])     # smallest term first (stable)
n_fun = len(seen)
for vals, (size, term) in order:
    lab = canon(vals)
    nb = max(lab) + 1
    if nb < 2 or nb > A.blocks:
        continue
    if lab not in parts:
        parts[lab] = (size, term, nb)
t1 = time.perf_counter()
rows = []
for lab, (size, term, nb) in parts.items():
    lv = {name: lump(lab, name) for name in ALL8}
    rows.append(dict(term=term, size=size, nb=nb, lab=lab, l=lv,
                     ring4=sum(lv[o] for o in RING4) / 4, six=sum(lv[o] for o in SIX) / 6,
                     all8=sum(lv[o] for o in ALL8) / 8,
                     exact=sum(1 for o in ALL8 if lv[o] > 1 - 1e-9)))
t_lump = time.perf_counter() - t1

print('# Q1 integers: size<=%d, grid [-%d,%d]^2, blocks<=%d, %s division' %
      (A.size, G, G, A.blocks, 'truncating' if A.trunc else 'floor'))
print('terms generated %d; distinct functions on E %d; distinct partitions with 2..%d blocks %d'
      % (n_terms, n_fun, A.blocks, len(rows)))
print('enumeration %.1f s; lumpability of all candidates x 8 operators %.1f s' % (t_enum, t_lump))


def show(key, title):
    rs = sorted(rows, key=lambda r: (-r[key], r['size'], r['term']))
    rank = {r['term']: i + 1 for i, r in enumerate(rs)}
    print('\n== top %d by mean lumpability over %s ==' % (A.top, title))
    print('%4s %-34s %2s %2s %6s %6s %6s | %s' % ('rank', 'term', 'sz', 'nb', 'ring4', 'six', 'all8',
                                                 ' '.join('%5s' % o for o in ALL8)))
    for i, r in enumerate(rs[:A.top]):
        print('%4d %-34s %2d %2d %6.3f %6.3f %6.3f | %s' %
              (i + 1, r['term'], r['size'], r['nb'], r['ring4'], r['six'], r['all8'],
               ' '.join('%5.2f' % r['l'][o] for o in ALL8)))
    # ties at the top
    top = rs[0][key]
    print('   candidates tied with rank 1 (within 1e-9): %d' %
          sum(1 for r in rs if abs(r[key] - top) < 1e-9))
    return rs, rank


rk = {}
rk['ring4'] = show('ring4', 'the ring operators {+,-,*,neg}')
rk['six'] = show('six', '{+,-,*,neg,max,min}  (all but div, mod)')
rk['all8'] = show('all8', 'all eight operators')

# ---------------------------------------------- where the named quotients and junk fall
named = [
    ('mod_5', lambda x: x % 5), ('mod_4', lambda x: x % 4), ('mod_3', lambda x: x % 3),
    ('parity', lambda x: x % 2), ('sign', sgn), ('mod_6', lambda x: x % 6),
    ('sign x parity', lambda x: (sgn(x), x % 2)),
    ('is_zero', lambda x: x == 0), ('nonneg', lambda x: x >= 0),
    ('JUNK eq_1', lambda x: x == 1), ('JUNK abs_lt2', lambda x: abs(x) < 2),
    ('JUNK even_or_neg', lambda x: x % 2 == 0 or x < 0), ('JUNK lt_3', lambda x: x < 3),
    ('JUNK eq_2_or_5', lambda x: x in (2, 5)),
]
bylab = {r['lab']: r for r in rows}
print('\n== named quotients and junk predicates ==')
print('%-18s %-30s %6s %6s %6s | rank/%d by ring4, six, all8 | exact ops | per-op' %
      ('name', 'pool term', 'ring4', 'six', 'all8', len(rows)))
for name, fn in named:
    lab = canon(tuple(fn(v) for v in E))
    r = bylab.get(lab)
    lv = {o: lump(lab, o) for o in ALL8}
    r4 = sum(lv[o] for o in RING4) / 4
    s6 = sum(lv[o] for o in SIX) / 6
    a8 = sum(lv[o] for o in ALL8) / 8
    ex = sum(1 for o in ALL8 if lv[o] > 1 - 1e-9)
    if r is not None:
        ranks = '%5d %5d %5d' % tuple(rk[k][1][r['term']] for k in ('ring4', 'six', 'all8'))
        term = r['term']
    else:
        ranks = '  (partition not in the enumerated pool)'
        term = '-'
    print('%-18s %-30s %6.3f %6.3f %6.3f | %s | %d | %s' %
          (name, term, r4, s6, a8, ranks, ex, ' '.join('%s=%.2f' % (o, lv[o]) for o in ALL8)))

# distribution of scores
for key in ('ring4', 'six', 'all8'):
    v = sorted(r[key] for r in rows)
    q = lambda p: v[int(p * (len(v) - 1))]
    print('score distribution %-5s: min %.3f  q25 %.3f  median %.3f  q75 %.3f  q90 %.3f  q99 %.3f  max %.3f'
          % (key, v[0], q(.25), q(.5), q(.75), q(.9), q(.99), v[-1]))
