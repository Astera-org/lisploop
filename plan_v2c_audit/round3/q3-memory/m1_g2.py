"""Does "test before inserting" change anything when the labels are UNSOUND?
G2 = G1 + floor div and mod (residues do not commute with them).  Targets are chosen as the
earlier q3_g2.py chose them: they need div or mod (plain G1 cannot reach them at the size
plain G2 finds them).  Labels are read off evaluated columns; a column whose label lies
outside the ring closure gets h = infinity.  Compared: (b) prune the bank only, (c) test first.

usage: python3 m1_g2.py [--n 120] [--seed 0]
"""
import argparse
import operator
import random

from q3lib import Domain, pick_rows, fdiv, fmod
from memlib import Labeller, one_pass, kept_map, OPS_G1, OPS_G2

ap = argparse.ArgumentParser()
ap.add_argument('--n', type=int, default=120)
ap.add_argument('--seed', type=int, default=0)
A = ap.parse_args()
rng = random.Random(A.seed)
xs = tuple(rng.randint(-9, 9) for _ in range(32))
ys = tuple(rng.randint(-9, 9) for _ in range(32))
leaves = [('x', xs), ('y', ys), ('0', tuple([0] * 32)), ('1', tuple([1] * 32))]
leaf_cols = [c for _, c in leaves]
DOM = [Domain(2, list(range(12)), leaf_cols), Domain(3, pick_rows(xs, ys, 3, 4), leaf_cols),
       Domain(5, pick_rows(xs, ys, 5, 3), leaf_cols)]
for d in DOM:
    d.forward([d.ids[d.alpha(c)] for c in leaf_cols])
BIN = {'+': operator.add, '-': operator.sub, '*': operator.mul, 'div': fdiv, 'mod': fmod}


def rand_term(size, ops):
    if size == 1:
        return rng.choice(['x', 'y', 'x', 'y', '0', '1'])
    if size == 2 or (size % 2 == 0 and rng.random() < 0.5) or (rng.random() < 0.1):
        return ('neg', rand_term(size - 1, ops))
    s1 = rng.randint(1, size - 2)
    return (rng.choice(ops), rand_term(s1, ops), rand_term(size - 1 - s1, ops))


def ev(t):
    if isinstance(t, str):
        return dict(leaves)[t]
    if t[0] == 'neg':
        a = ev(t[1])
        return None if a is None else tuple(-v for v in a)
    a, b = ev(t[1]), ev(t[2])
    if a is None or b is None or (t[0] in ('div', 'mod') and 0 in b):
        return None
    return tuple(map(BIN[t[0]], a, b))


n = inside = same = flips = lost_b = lost_c = unsound = 0
seen = set()
while n < A.n:
    t = rand_term(rng.choice([3, 5, 5, 7]), ['+', '-', '*', 'div', 'mod', 'div', 'mod'])
    col = ev(t)
    if col is None or len(set(col)) < 3 or col in seen:
        continue
    seen.add(col)
    pl = one_pass(leaves, col, 7, None, 'plain', OPS_G2, asgo=True)
    if not pl['hit']:
        continue
    ns = pl['hit_size']
    if one_pass(leaves, col, ns, None, 'plain', OPS_G1, asgo=True)['hit']:
        continue                       # reachable without div/mod at that size: not a G2 test
    n += 1
    ids = [d.ids.get(d.alpha(col)) for d in DOM]
    if None in ids:
        continue
    inside += 1
    lab = Labeller(DOM, [d.backward(i) for d, i in zip(DOM, ids)])
    rp = one_pass(leaves, col, ns, None, 'plain', OPS_G2, keep=True)
    rb = one_pass(leaves, col, ns, lab, 'bank', OPS_G2, keep=True)
    rc = one_pass(leaves, col, ns, lab, 'pre', OPS_G2, keep=True, check=True)
    kp, kc = kept_map(rp), kept_map(rc)
    expect = {c: s for c, s in kp.items() if s + lab.h(lab.key(c)) <= ns}
    same += kept_map(rb) == kc
    flips += rc['retest_flip']
    lost_b += not rb['hit']
    lost_c += not rc['hit']
    unsound += expect != kc
print('# G2 targets that need div or mod (true size 3-7): %d; with a target label known to the ring tables: %d'
      % (n, inside))
print('bank of (b) identical to bank of (c) (columns and sizes): %d of %d' % (same, inside))
print('a column cut at its first test and kept at a later test in the same pass: %d' % flips)
print('answers lost: (b) %d, (c) %d of %d' % (lost_b, lost_c, inside))
print('targets where pruning removed a class that itself passes the test (a needed argument was cut, '
      'i.e. the labels are unsound there): %d of %d' % (unsound, inside))
