"""C1: does collapsing a multi-valued quotient to a Boolean destroy closure?

Independent re-computation of the review's CHECK 1 (verify_guard_fourier_slices.py),
then three extensions:
  (a) every 2-block coarsening of each quotient, not only the one the review chose;
  (b) other grids;
  (c) the Boolean terms that a small grammar would offer for the same idea.

dependency score(q; f) = 1 - H(q(f(a,b)) | q(a), q(b)) / H(q(f(a,b)))   (0 when H = 0)

usage: python3 c1_bool.py > c1_bool.log
"""
import itertools
import math
from collections import Counter


def H(c, n):
    return -sum(v / n * math.log2(v / n) for v in c.values())


def score(q, f, grid):
    n = 0
    cin, cout, cj = Counter(), Counter(), Counter()
    for a in grid:
        for b in grid:
            i = (q(a), q(b))
            o = q(f(a, b))
            cin[i] += 1
            cout[o] += 1
            cj[(i, o)] += 1
            n += 1
    ho = H(cout, n)
    if ho < 1e-12:
        return 0.0, 0.0, 0.0
    hc = max(0.0, H(cj, n) - H(cin, n))
    return 1.0 - hc / ho, hc, ho


OPS = [('+', lambda a, b: a + b), ('-', lambda a, b: a - b), ('*', lambda a, b: a * b),
       ('max', max)]
sgn = lambda x: (x > 0) - (x < 0)
QUOT = [
    ('x mod 3', lambda x: x % 3, 3),
    ('x mod 3 == 0', lambda x: x % 3 == 0, 2),
    ('x mod 5', lambda x: x % 5, 5),
    ('x mod 5 == 0', lambda x: x % 5 == 0, 2),
    ('sgn x', sgn, 3),
    ('x < 0', lambda x: x < 0, 2),
    ('x == 0', lambda x: x == 0, 2),
    ('x mod 2', lambda x: x % 2, 2),
    ('x mod 4', lambda x: x % 4, 4),
    ('x mod 6', lambda x: x % 6, 6),
]

print('== 1. the review\'s CHECK 1, recomputed: score (and H(out|in) bits) per operator ==')
for G in (12, 10, 20):
    grid = range(-G, G + 1)
    print('\ngrid [-%d, %d]^2' % (G, G))
    print('  %-14s %5s | %s' % ('quotient', 'card', '   '.join('%-14s' % n for n, _ in OPS)))
    for name, q, card in QUOT:
        cells = []
        for on, f in OPS:
            s, hc, ho = score(q, f, grid)
            cells.append('%.2f (Hc %.2f)' % (s, hc))
        print('  %-14s %5d | %s' % (name, card, '   '.join('%-14s' % c for c in cells)))

print('\n== 2. every 2-block coarsening of each multi-valued quotient (grid [-12, 12]^2) ==')
print('   best Boolean = the split of the labels into two groups with the highest mean score')
grid = range(-12, 13)
for name, q, card in QUOT:
    if card < 3:
        continue
    labs = sorted(set(q(x) for x in range(-200, 201)))
    full = {on: score(q, f, grid)[0] for on, f in OPS}
    rows = []
    for k in range(1, len(labs) // 2 + 1):
        for sub in itertools.combinations(labs, k):
            if 2 * k == len(labs) and labs[0] not in sub:
                continue
            S = set(sub)
            qb = lambda x, S=S, q=q: q(x) in S
            sc = {on: score(qb, f, grid)[0] for on, f in OPS}
            rows.append((sub, sc))
    for ops_name, ops_set in (('{+,-}', ('+', '-')), ('{+,-,*}', ('+', '-', '*')),
                              ('{+,-,*,max}', ('+', '-', '*', 'max'))):
        m_full = sum(full[o] for o in ops_set) / len(ops_set)
        best = max(rows, key=lambda r: sum(r[1][o] for o in ops_set))
        m_best = sum(best[1][o] for o in ops_set) / len(ops_set)
        worst = min(rows, key=lambda r: sum(r[1][o] for o in ops_set))
        m_worst = sum(worst[1][o] for o in ops_set) / len(ops_set)
        print('  %-8s over %-12s full %.2f | best Boolean {%s} vs rest %.2f | worst {%s} %.2f | %d splits'
              % (name, ops_name, m_full, ','.join(map(str, best[0])), m_best,
                 ','.join(map(str, worst[0])), m_worst, len(rows)))
    print('           per operator, best split over {+,-,*,max}: ' +
          '  '.join('%s %.2f->%.2f' % (o, full[o], max(rows, key=lambda r: sum(r[1].values()))[1][o])
                    for o, _ in OPS))

print('\n== 3. which Booleans keep closure exactly (score 1.00) on which operators, grid [-12, 12]^2 ==')
BOOL = [('x mod 2 == 0', lambda x: x % 2 == 0), ('x mod 3 == 0', lambda x: x % 3 == 0),
        ('x mod 4 == 0', lambda x: x % 4 == 0), ('x mod 5 == 0', lambda x: x % 5 == 0),
        ('x < 0', lambda x: x < 0), ('x > 0', lambda x: x > 0), ('x == 0', lambda x: x == 0),
        ('x <= 0', lambda x: x <= 0), ('x == 1', lambda x: x == 1)]
print('  %-14s | %s' % ('Boolean', '   '.join('%-5s' % n for n, _ in OPS)))
for name, q in BOOL:
    print('  %-14s | %s' % (name, '   '.join('%.2f ' % score(q, f, grid)[0] for _, f in OPS)))
