"""Q3 (second half): (a) on G1 the column-homomorphism pruning is exact -- check on
random G1 targets that it never loses the target; (b) on G2 = G1 + {div, mod}
(floor) the same pruning is unsound -- exhibit concrete misses.

For G2 the abstract machinery is the G1 one (ring tables and DPs); a div/mod
candidate has no abstract transformer, so its abstract value is read off its
concrete column after evaluation, and a value outside the ring closure has no
backward-table entry (it cannot reach the target as far as the automaton knows).
Each G2 target is classified:
   bound     the DP's lower bound N_min on the target's size EXCEEDS its true size
             (the 'admissible' bound is simply false);
   outside   the target's abstract value is not a state of the ring automaton at all;
   pruned    neither of the above, yet the pruned search fails at the true size;
   ok        found at the true size.

usage: python3 q3_g2.py [--n1 200] [--n2 200] [--seed 0]
"""
import argparse
import operator
import random
import time

from q3lib import Domain, search, pick_rows, fdiv, fmod

ap = argparse.ArgumentParser()
ap.add_argument('--n1', type=int, default=200)
ap.add_argument('--n2', type=int, default=200)
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--rows', type=int, default=32)
A = ap.parse_args()
rng = random.Random(A.seed)
xs = tuple(rng.randint(-9, 9) for _ in range(A.rows))
ys = tuple(rng.randint(-9, 9) for _ in range(A.rows))
leaves = [('x', xs), ('y', ys), ('0', tuple([0] * A.rows)), ('1', tuple([1] * A.rows))]
leaf_cols = [c for _, c in leaves]
DOM = [Domain(2, list(range(12)), leaf_cols), Domain(3, pick_rows(xs, ys, 3, 4), leaf_cols),
       Domain(5, pick_rows(xs, ys, 5, 3), leaf_cols)]
for d in DOM:
    d.forward([d.ids[d.alpha(c)] for c in leaf_cols])
print('# Q3 G1 exactness / G2 unsoundness; %d rows; states %s; largest g (least term size of an abstract '
      'state) per domain: %s' % (A.rows, [d.n for d in DOM], [max(d.g) for d in DOM]))

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
    if a is None or b is None:
        return None
    if t[0] in ('div', 'mod') and 0 in b:
        return None
    return tuple(map(BIN[t[0]], a, b))


def show(t):
    if isinstance(t, str):
        return t
    if t[0] == 'neg':
        return '(neg %s)' % show(t[1])
    return '(%s %s %s)' % (t[0], show(t[1]), show(t[2]))


def has(t, names):
    if isinstance(t, str):
        return False
    return t[0] in names or any(has(a, names) for a in t[1:])


def pruned_at(target, N, grammar):
    """Ring-automaton pruned search at size bound N."""
    ids = [d.ids.get(d.alpha(target)) for d in DOM]
    if None in ids:
        return None, 'outside'
    hs = [d.backward(i) for d, i in zip(DOM, ids)]
    r = search(leaves, target, N, DOM, hs, grammar=grammar)
    return r, None


# ------------------------------------------------------------------ (a) G1
t0 = time.time()
n = miss = 0
gains = []
seen = set()
while n < A.n1:
    t = rand_term(rng.choice([5, 7, 9, 9]), ['+', '-', '*'])
    col = ev(t)
    if col is None or len(set(col)) < 3 or col in seen:
        continue
    seen.add(col)
    pl = search(leaves, col, 9, None, None, stop_at_hit=True)
    ns = pl['hit_size']
    ids = [d.ids[d.alpha(col)] for d in DOM]
    nmin = max(d.g[i] for d, i in zip(DOM, ids))
    hs = [d.backward(i) for d, i in zip(DOM, ids)]
    cum = 0
    found = False
    for N in range(nmin, ns + 1):
        r = search(leaves, col, N, DOM, hs, join=True)
        if r['hit'] is not None:
            found = r['hit_size'] == ns
            cum += r['hit']
            break
        cum += r['evaluated']
    n += 1
    if not found or nmin > ns:
        miss += 1
        print('   G1 MISS:', show(t), 'true size', ns, 'N_min', nmin)
    else:
        gains.append((ns, pl['hit'] / cum, pl['stored_below'] / max(1, r['stored_below'])))
print('\n(a) G1: %d random polynomial targets (written with 5-9 nodes); found at the plain-OE size in %d; '
      'MISSES %d   [%.1f s]' % (n, n - miss, miss, time.time() - t0))
for sz in sorted({g[0] for g in gains}):
    gs = [g for g in gains if g[0] == sz]
    import math
    gm = lambda v: math.exp(sum(math.log(x) for x in v) / len(v))
    print('    true size %2d: %3d targets, candidate gain gmean %.1fx [%.1f..%.1f], stored-class gain gmean %.1fx'
          % (sz, len(gs), gm([g[1] for g in gs]), min(g[1] for g in gs), max(g[1] for g in gs),
             gm([g[2] for g in gs])))

# ------------------------------------------------------------------ (b) G2
t0 = time.time()
cats = {'bound': [], 'outside': [], 'pruned': [], 'ok': []}
n = 0
seen = set()
while n < A.n2:
    t = rand_term(rng.choice([3, 5, 5, 7]), ['+', '-', '*', 'div', 'mod', 'div', 'mod'])
    if not has(t, ('div', 'mod')):
        continue
    col = ev(t)
    if col is None or len(set(col)) < 3 or col in seen:
        continue
    seen.add(col)
    pl = search(leaves, col, 7, None, None, grammar='G2', stop_at_hit=True)
    if pl['hit'] is None:
        continue
    ns = pl['hit_size']
    # is the behaviour reachable without div/mod at the same size? then it is not a G2 test
    p1 = search(leaves, col, ns, None, None, grammar='G1', stop_at_hit=True)
    if p1['hit'] is not None:
        continue
    n += 1
    ids = [d.ids.get(d.alpha(col)) for d in DOM]
    if None in ids:
        cats['outside'].append((show(t), ns, None))
        continue
    nmin = max(d.g[i] for d, i in zip(DOM, ids))
    if nmin > ns:
        cats['bound'].append((show(t), ns, nmin))
        continue
    r, _ = pruned_at(col, ns, 'G2')
    if r['hit'] is None:
        r2, _ = pruned_at(col, ns + 2, 'G2')
        cats['pruned'].append((show(t), ns, nmin, r2['hit_size'] if r2['hit'] is not None else None))
    else:
        cats['ok'].append((show(t), ns, nmin))
print('\n(b) G2: %d random targets that need div or mod (true size 3-7 by plain G2 search)   [%.1f s]'
      % (n, time.time() - t0))
print('    bound   (DP lower bound > true size)           : %3d' % len(cats['bound']))
print('    outside (target not a state of the automaton)  : %3d' % len(cats['outside']))
print('    pruned  (search fails at the true size)        : %3d' % len(cats['pruned']))
print('    ok      (found at the true size)               : %3d' % len(cats['ok']))
print('    => the ring pruning loses %d of %d targets (%.0f%%)' %
      (n - len(cats['ok']), n, 100.0 * (n - len(cats['ok'])) / n))
for k in ('bound', 'outside', 'pruned', 'ok'):
    print('\n    examples, %s:' % k)
    for e in sorted(cats[k], key=lambda e: (e[1], len(e[0])))[:6]:
        if k == 'bound':
            print('       %-40s true size %d, DP "lower bound" %d' % e)
        elif k == 'outside':
            print('       %-40s true size %d' % e[:2])
        elif k == 'pruned':
            print('       %-40s true size %d, DP lower bound %d, found by the pruned search at size bound +2: %s'
                  % (e[0], e[1], e[2], e[3]))
        else:
            print('       %-40s true size %d, DP lower bound %d' % e)
