"""Q3: column homomorphisms Z^N -> F_p^k for polynomial search on G1 = {+,-,*,neg}.

Compares, on the review's six targets:
  plain    : bottom-up OE by size, 32 rows
  colhom   : the same, pruning with F_2^12, F_3^4, F_5^3 (iterative deepening on the
             size bound N starting at the DP's lower bound; every pass counted)
  per-row  : the review's reported negative: the same primes used one row at a time.

usage: python3 q3_poly.py [--rows 32] [--seed 0] [--maxsize 13] [--skip-perrow]
"""
import argparse
import random
import time

from q3lib import Domain, search, pick_rows, INFTY

ap = argparse.ArgumentParser()
ap.add_argument('--rows', type=int, default=32)
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--vmax', type=int, default=9)
ap.add_argument('--maxsize', type=int, default=13)
ap.add_argument('--skip-perrow', action='store_true')
ap.add_argument('--only', default='')
A = ap.parse_args()

rng = random.Random(A.seed)
xs = tuple(rng.randint(-A.vmax, A.vmax) for _ in range(A.rows))
ys = tuple(rng.randint(-A.vmax, A.vmax) for _ in range(A.rows))
leaves = [('x', xs), ('y', ys), ('0', tuple([0] * A.rows)), ('1', tuple([1] * A.rows))]
leaf_cols = [c for _, c in leaves]

TARGETS = [
    ('A2', '(x+x)*(y+1)', lambda x, y: (x + x) * (y + 1)),
    ('A3', 'x*y + x - y', lambda x, y: x * y + x - y),
    ('A4', '(x+y)*(x-y) + 1', lambda x, y: (x + y) * (x - y) + 1),
    ('A8', '(x+y)^2 - x*y + 1', lambda x, y: (x + y) ** 2 - x * y + 1),
    ('A11', '(x*y + x + 1)*(y - x)', lambda x, y: (x * y + x + 1) * (y - x)),
    ('A12', '2*(x^2 + y^2) - x*y', lambda x, y: 2 * (x * x + y * y) - x * y),
]
if A.only:
    TARGETS = [t for t in TARGETS if t[0] in A.only.split(',')]

t0 = time.perf_counter()
r2 = list(range(12))
r3 = pick_rows(xs, ys, 3, 4)
r5 = pick_rows(xs, ys, 5, 3)
DOM = [Domain(2, r2, leaf_cols), Domain(3, r3, leaf_cols), Domain(5, r5, leaf_cols)]
for d in DOM:
    d.forward([d.ids[d.alpha(c)] for c in leaf_cols])
t_dom = time.perf_counter() - t0
print('# Q3: G1 = {+,-,*,neg} over x, y, 0, 1; %d rows, x,y in [-%d,%d], seed %d' %
      (A.rows, A.vmax, A.vmax, A.seed))
print('abstract domains: F_2 on rows %s (%d states), F_3 on rows %s (%d states), F_5 on rows %s (%d states)'
      % (r2, DOM[0].n, r3, DOM[1].n, r5, DOM[2].n))
print('closure + operation tables + forward DP for the three domains: %.1f ms (once per row set)'
      % (1e3 * t_dom))

PR = []
if not A.skip_perrow:
    for p, rows in ((2, r2), (3, r3), (5, r5)):
        for r in rows:
            d = Domain(p, [r], leaf_cols)
            d.forward([d.ids[d.alpha(c)] for c in leaf_cols])
            PR.append(d)


def run_pruned(doms, target, nstar, label, join=False, last_only=False):
    tb = time.perf_counter()
    hs = [d.backward(d.ids[d.alpha(target)]) for d in doms]
    nmin = max(d.g[d.ids[d.alpha(target)]] for d in doms)
    t_dp = time.perf_counter() - tb
    cum = 0
    checks = 0
    wall = 0.0
    res = None
    for N in range(max(1, nmin), nstar + 1):
        r = search(leaves, target, N, doms, hs, join=join, last_only=last_only)
        wall += r['wall']
        checks += r['checks']
        if r['hit'] is not None:
            res = r
            break
        cum += r['evaluated']
    if res is None:
        return dict(found=False, nmin=nmin, cum=cum, t_dp=t_dp, wall=wall)
    return dict(found=True, N=N, nmin=nmin, cum_hit=cum + res['hit'], one_hit=res['hit'],
                cum_full=cum + res['evaluated'], store=res['stored_below'], checks=checks,
                t_dp=t_dp, wall=wall, last_wall=res['wall'], last_full=res['evaluated'],
                last_below=res['below'])


rows_out = []
for name, text, fn in TARGETS:
    target = tuple(fn(x, y) for x, y in zip(xs, ys))
    # plain: one pass to the first hit (levels are complete below the hit level)
    pl = None
    for N in range(1, A.maxsize + 1):
        pass
    pl = search(leaves, target, A.maxsize, None, None, stop_at_hit=True)
    if pl['hit'] is None:
        print('%s: plain OE did not find the target within size %d' % (name, A.maxsize))
        continue
    nstar = pl['hit_size']
    ch = run_pruned(DOM, target, nstar, 'colhom')
    cj = run_pruned(DOM, target, nstar, 'colhom+join', join=True)
    assert cj['found'] == ch['found'] and cj.get('store') == ch.get('store')
    lo = run_pruned(DOM, target, nstar, 'last-level filter only', join=True, last_only=True)
    # best-of-3 wall times (the searches are short)
    for _ in range(2):
        pl2 = search(leaves, target, A.maxsize, None, None, stop_at_hit=True)
        pl['wall'] = min(pl['wall'], pl2['wall'])
        c2 = run_pruned(DOM, target, nstar, 'colhom')
        ch['wall'] = min(ch['wall'], c2['wall'])
        c2 = run_pruned(DOM, target, nstar, 'colhom+join', join=True)
        cj['wall'] = min(cj['wall'], c2['wall'])
    line = dict(name=name, text=text, nstar=nstar, plain_hit=pl['hit'], plain_store=pl['stored_below'],
                plain_wall=pl['wall'], ch=ch, cj=cj, lo=lo)
    if PR:
        line['pr'] = run_pruned(PR, target, nstar, 'perrow')
    rows_out.append(line)
    print('%-4s %-24s size found %2d | plain: %9d cands, %7d stored, %.2fs | colhom: found=%s N_min=%d '
          'cum %d (last pass %d), stored %d, lookups %d, search %.2fs + DP %.3fs%s'
          % (name, text, nstar, pl['hit'], pl['stored_below'], pl['wall'], ch['found'], ch['nmin'],
             ch.get('cum_hit', -1), ch.get('one_hit', -1), ch.get('store', -1), ch.get('checks', -1),
             ch['wall'], ch['t_dp'],
             (' | per-row: cum %d, stored %d' % (line['pr'].get('cum_hit', -1), line['pr'].get('store', -1)))
             if PR else ''), flush=True)

print('\n== Table: candidates evaluated until the target is found, and classes stored below the last level ==')
print('%-4s %-24s %3s %10s %8s | %10s %10s %7s %9s %9s | %8s %8s %8s %8s %8s | %8s %8s' %
      ('', 'target', 'sz', 'plain', 'stored', 'colhom', '(1 pass)', 'stored', 'cand gain', 'RAM gain',
       'plain ms', 'scan ms', 'join ms', 'lookups', 'w/ join', 'per-row', 'RAM gain'))
for l in rows_out:
    ch = l['ch']
    pr = l.get('pr')
    cj = l['cj']
    print('%-4s %-24s %3d %10d %8d | %10d %10d %7d %8.1fx %8.1fx | %8.1f %8.1f %8.1f %8d %8d | %8s %8s' %
          (l['name'], l['text'], l['nstar'], l['plain_hit'], l['plain_store'], ch['cum_hit'],
           ch['one_hit'], ch['store'], l['plain_hit'] / ch['cum_hit'],
           l['plain_store'] / max(1, ch['store']), 1e3 * l['plain_wall'],
           1e3 * (ch['wall'] + ch['t_dp']), 1e3 * (cj['wall'] + cj['t_dp']), ch['checks'], cj['checks'],
           ('%.2fx' % (l['plain_hit'] / pr['cum_hit'])) if pr else '-',
           ('%.2fx' % (l['plain_store'] / max(1, pr['store']))) if pr else '-'))
print('\n== Variant: abstract filter BEFORE evaluation on the last level only (below it: evaluate, then discard) ==')
print('%-4s %-24s %10s | %10s %10s %7s %9s %9s' % ('', 'target', 'plain', 'cum', '(1 pass)', 'stored', 'cand gain', '(1 pass)'))
for l in rows_out:
    lo = l['lo']
    print('%-4s %-24s %10d | %10d %10d %7d %8.1fx %8.1fx' %
          (l['name'], l['text'], l['plain_hit'], lo['cum_hit'], lo['one_hit'], lo['store'],
           l['plain_hit'] / lo['cum_hit'], l['plain_hit'] / lo['one_hit']))
print()
print('colhom = all iterative-deepening passes from N_min to the size found; (1 pass) = last pass alone;')
print('scan ms / join ms = search (best of 3) + backward DP for this target, testing every pair of abstract')
print('buckets / using the last-level join; lookups = abstract bucket-pair tests; the one-off cost of the')
print('domains (closure, tables, forward DP) is NOT included; per-row = candidate gain with the same primes')
print('applied to single rows (%d one-row domains).' % len(PR))
