"""Small look-ups into the b12 JSON files (lost tasks, exact label-reachability fractions)."""
import json
import sys

for fn in sys.argv[1:]:
    J = json.load(open(fn))
    T = [t for t in J['tasks'] if not t.get('skip')]
    print(fn)
    for t in T:
        if not t['lab_found']:
            print('  lost by labels early: %s  %s  n*=%d plain=%d root_adm=%s' % (
                t['name'], t['term'], t['nstar'], t['plain_cost'], t.get('root_adm')))
    for d in (1, 2, 3):
        P = [p for t in T if not t['short'] for p in t['path'] if not p.get('missing') and p['depth'] == d]
        if P:
            print('  steps out %d: label reachability rules out %.4f%% of classes on average (max %.2f%%); '
                  'n=%d' % (d, 100 * sum(1 - p['frac_reach'] for p in P) / len(P),
                            100 * max(1 - p['frac_reach'] for p in P), len(P)))
    skipped = [t for t in J['tasks'] if t.get('skip')]
    print('  skipped (answer of size < 3): %s' % [(t['name'], t['term'], t['nstar']) for t in skipped])
    # share of d=1 on-path classes whose DL is within the best k classes of the level
    P = [dict(p, root=t['root']) for t in T if not t['short'] for p in t['path']
         if not p.get('missing') and p['depth'] == 1]
    print('  true parents: DL rank within level and type: rank 1 in %d of %d; within best 10 in %d' % (
        sum(1 for p in P if p['rank_dl_same'] == 1), len(P), sum(1 for p in P if p['rank_dl_same'] <= 10)))
    from collections import Counter
    rs = [p for p in P if p['rsimple']]
    print('  true parents whose residual Y - U is a constant or is itself a bank class (decode by look-up): '
          '%d of %d; roots %s' % (len(rs), len(P), dict(Counter(p['root'] for p in rs).most_common(8))))
    for d in (1, 2, 3):
        Q = [p for t in T if not t['short'] for p in t['path'] if not p.get('missing') and p['depth'] == d]
        v = [p['pct_dl_all'] for p in Q if p['pct_dl_all'] is not None]
        print('  steps out %d: on-path class in the WORSE half of its level by DL in %d of %d; in the best half '
              'in %d; exactly at the tie midpoint in %d' % (d, sum(1 for x in v if x > 0.5), len(v),
                                                           sum(1 for x in v if x < 0.5), sum(1 for x in v if x == 0.5)))
