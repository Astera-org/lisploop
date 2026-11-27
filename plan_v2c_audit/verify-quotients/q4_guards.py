"""Q4: weakest guard of a conditional law by bitset maximality.

Rows: --rows random integer pairs (a, b), each uniform in [-R, R].
Guard pool: (cmp T1 T2) for cmp in <, <=, =, != and T1, T2 arithmetic terms of
at most 3 nodes over leaves a, b, 0, 1 with + - *; deduplicated by MASK (one
bit per row), keeping the shortest term; the all-false and all-true masks are dropped.
For a law lhs = rhs: A = rows where both sides are defined and equal;
a guard g is VALID iff g & ~A == 0;  g1 implies g2 iff g1 & g2 == g1;
the WEAKEST guards are the valid guards that imply no other valid guard.

usage: python3 q4_guards.py [--rows 32] [--R 6] [--seed 0] [--seeds 20]
"""
import argparse
import random
import time

ap = argparse.ArgumentParser()
ap.add_argument('--rows', type=int, default=32)
ap.add_argument('--R', type=int, default=6)
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--seeds', type=int, default=20)
A = ap.parse_args()


def fdiv(a, b):
    return None if b == 0 else a // b


def fmod(a, b):
    return None if b == 0 else a % b


LAWS = [
    ('max(a,b) = a', lambda a, b: max(a, b), lambda a, b: a, 'a >= b'),
    ('div(a*b, b) = a', lambda a, b: fdiv(a * b, b), lambda a, b: a, 'b != 0'),
    ('abs(a+b) = abs(a)+abs(b)', lambda a, b: abs(a + b), lambda a, b: abs(a) + abs(b), 'a*b >= 0'),
    ('max(a,0) = a', lambda a, b: max(a, 0), lambda a, b: a, 'a >= 0'),
    ('div(a,b)*b = a', lambda a, b: None if b == 0 else (a // b) * b, lambda a, b: a,
     'b != 0 and b | a   (needs mod: not one comparison of + - * terms)'),
    ('mod(a,b) = a', lambda a, b: fmod(a, b), lambda a, b: a,
     '0 <= a < b or b < a <= 0   (a conjunction)'),
]


def arith_terms(rows):
    leaves = [('a', tuple(a for a, b in rows)), ('b', tuple(b for a, b in rows)),
              ('0', tuple(0 for _ in rows)), ('1', tuple(1 for _ in rows))]
    terms = [(1, t, c) for t, c in leaves]
    for (t1, c1) in leaves:
        for (t2, c2) in leaves:
            terms.append((3, '(+ %s %s)' % (t1, t2), tuple(x + y for x, y in zip(c1, c2))))
            terms.append((3, '(- %s %s)' % (t1, t2), tuple(x - y for x, y in zip(c1, c2))))
            terms.append((3, '(* %s %s)' % (t1, t2), tuple(x * y for x, y in zip(c1, c2))))
    seen = {}
    for sz, t, c in terms:           # dedupe arithmetic terms by column, smallest first
        if c not in seen:
            seen[c] = (sz, t)
    return [(sz, t, c) for c, (sz, t) in seen.items()]


def guard_pool(rows):
    n = len(rows)
    full = (1 << n) - 1
    T = arith_terms(rows)
    masks = {}          # mask -> (size, term)
    count = {}          # mask -> number of syntactic guards with that mask
    raw = 0
    for (s1, t1, c1) in T:
        for (s2, t2, c2) in T:
            for cmp, fn in (('<', lambda x, y: x < y), ('<=', lambda x, y: x <= y),
                            ('=', lambda x, y: x == y), ('!=', lambda x, y: x != y)):
                raw += 1
                m = 0
                for i in range(n):
                    if fn(c1[i], c2[i]):
                        m |= 1 << i
                if m == 0 or m == full:
                    continue
                count[m] = count.get(m, 0) + 1
                sz = 1 + s1 + s2
                if m not in masks or masks[m][0] > sz:
                    masks[m] = (sz, '(%s %s %s)' % (cmp, t1, t2))
    return masks, count, raw, len(T)


def agreement(rows, lhs, rhs):
    m = 0
    for i, (a, b) in enumerate(rows):
        l, r = lhs(a, b), rhs(a, b)
        if l is not None and r is not None and l == r:
            m |= 1 << i
    return m


def weakest(masklist, Amask):
    valid = [g for g in masklist if g & ~Amask == 0]
    maxi = []
    for g in valid:
        dominated = False
        for h in valid:
            if h != g and (g & h) == g:
                dominated = True
                break
        if not dominated:
            maxi.append(g)
    return valid, maxi


def run(seed, nrows, verbose):
    rng = random.Random(seed)
    rows = [(rng.randint(-A.R, A.R), rng.randint(-A.R, A.R)) for _ in range(nrows)]
    masks, count, raw, nT = guard_pool(rows)
    ml = list(masks)
    full = (1 << nrows) - 1
    if verbose:
        print('rows=%d  seed=%d  range [-%d,%d]; rows with b=0: %d, a=0: %d' %
              (nrows, seed, A.R, A.R, sum(1 for a, b in rows if b == 0), sum(1 for a, b in rows if a == 0)))
        print('arithmetic terms (distinct columns): %d; syntactic guards: %d; distinct non-trivial masks: %d'
              % (nT, raw, len(ml)))
    Am = [agreement(rows, lhs, rhs) for (_, lhs, rhs, _) in LAWS]
    # timing of the bitset work only (validity + maximality for all laws), best of 200
    best = 1e9
    for _ in range(200):
        t0 = time.perf_counter()
        for am in Am:
            weakest(ml, am)
        best = min(best, time.perf_counter() - t0)
    out = []
    for (name, lhs, rhs, truth), am in zip(LAWS, Am):
        valid, maxi = weakest(ml, am)
        exact = am in masks
        out.append((name, bin(am).count('1'), len(valid), len(maxi), exact,
                    [(masks[g][1], bin(g).count('1'), count[g]) for g in sorted(maxi, key=lambda g: -bin(g).count('1'))]))
        if verbose:
            print('\nlaw %-28s agrees on %2d/%d rows; true condition: %s' %
                  (name, bin(am).count('1'), nrows, truth))
            if am == full:
                print('   (law holds on every row: no guard needed; maximal PROPER guards listed)')
            print('   valid guards: %d   maximal (weakest): %d   a guard with mask == A exists: %s' %
                  (len(valid), len(maxi), exact))
            for g in sorted(maxi, key=lambda g: -bin(g).count('1')):
                print('      %-28s covers %2d rows; %d syntactic guards share this mask' %
                      (masks[g][1], bin(g).count('1'), count[g]))
    if verbose:
        print('\nbitset time for all %d laws (validity + pairwise maximality over %d masks): %.3f ms' %
              (len(LAWS), len(ml), best * 1e3))
    return len(ml), out, best


print('# Q4: weakest guards by bitset maximality')
run(A.seed, A.rows, True)

print('\n== stability over %d random row sets ==' % A.seeds)
for nrows in (16, 32, 64):
    stats = {name: [] for (name, _, _, _) in LAWS}
    nm = []
    tt = []
    for s in range(A.seeds):
        n, out, best = run(1000 + s, nrows, False)
        nm.append(n)
        tt.append(best)
        for (name, na, nv, nx, exact, terms) in out:
            stats[name].append((nv, nx, exact, terms[0][0] if terms else '-'))
    print('\nrows=%d: distinct masks %d..%d (mean %.0f); bitset time mean %.3f ms' %
          (nrows, min(nm), max(nm), sum(nm) / len(nm), 1e3 * sum(tt) / len(tt)))
    print('   %-28s %14s %22s %10s  most frequent top guard' %
          ('law', 'valid (range)', '#maximal: histogram', 'exact-mask'))
    for name in stats:
        v = stats[name]
        hist = {}
        for (nv, nx, ex, t) in v:
            hist[nx] = hist.get(nx, 0) + 1
        tops = {}
        for (nv, nx, ex, t) in v:
            tops[t] = tops.get(t, 0) + 1
        top = max(tops.items(), key=lambda kv: kv[1])
        print('   %-28s %6d..%-6d %22s %7d/%d  %s (%d/%d)' %
              (name, min(x[0] for x in v), max(x[0] for x in v), str(dict(sorted(hist.items()))),
               sum(1 for x in v if x[2]), len(v), top[0], top[1], len(v)))
