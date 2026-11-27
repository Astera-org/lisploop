"""Q2 main comparison: plain OE vs flat-signature Naive Bayes vs abstract tables
(hard pruning) vs abstract tables + soft ranking, on the review's 8 tasks + 12 more.

usage: python3 q2_main.py [--kind iid|enriched] [--M 2000] [--seed 0] [--tag main]
"""
import argparse
import json
import math
import random
import statistics
import sys
import time

from seqlib import (L, I, OPS, OPNAMES, OPSIG, HAND6, build_tables, term_str, term_ops)
from q2search import (plain_search, count_under_order, expected_random_order, pruned_search,
                      soft_counts, ref_audit, signature, NaiveBayes, weighted_search, nb_costs)
from q2tasks import review_tasks, training_tasks, my_tasks, HELD_OUT


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def run_task(task, tb, nb, nb_backoff, rng, do_weighted=True, do_post=True):
    env, target, ttype = task['env'], task['target'], task['ttype']
    r = dict(name=task['name'], term=term_str(task['term']), size=task['size'],
             n_ops=len(task['ops']), cold=task['cold'], inputs=sorted(env))
    # ---------------- (i) plain
    ps = plain_search(env, target, task['size'])
    ns = ps['found_size']
    lv = ps['levels'][ns - 1]
    n, hit = lv['n'], lv['hit']
    lib_order = list(range(len(n)))
    r['found_size'] = ns
    r['plain_lib'] = ps['below'] + count_under_order(n, hit, lib_order)
    r['plain_rand'] = ps['below'] + expected_random_order(n, hit, rng)
    r['plain_full'] = ps['below'] + ps['final_total']
    r['plain_store'] = ps['store_below']
    r['plain_wall'] = ps['wall_s']
    r['hit_ops'] = [OPNAMES[i] for i in lib_order if hit[i] >= 0]
    # ---------------- (ii) flat signature + Naive Bayes
    sig = signature(env, target, ttype)
    order = nb.order(sig)
    r['nb_u1'] = ps['below'] + count_under_order(n, hit, order)
    rank = {OPNAMES[i]: k + 1 for k, i in enumerate(order)}
    r['nb_rank_refops'] = {o: rank[o] for o in task['ops']}
    r['nb_rank_hit'] = min(rank[o] for o in r['hit_ops'])
    order_b = nb_backoff.order(sig)
    r['nb_u1_backoff'] = ps['below'] + count_under_order(n, hit, order_b)
    if do_weighted:
        post = nb.posterior(sig)
        cost = nb_costs(post)
        ws = weighted_search(env, target, cost, order=order)
        r['nb_u2'] = ws['cands']
        r['nb_u2_capped'] = ws.get('capped')
        r['nb_u2_cost'] = ws['cost']
        r['nb_u2_opcost'] = {o: cost[o] for o in task['ops']}
        r['nb_u2_store'] = ws['stored']
        post_b = nb_backoff.posterior(sig)
        ws = weighted_search(env, target, nb_costs(post_b), order=order_b)
        r['nb_u2_backoff'] = ws['cands']
    # ---------------- (iii)/(iv) abstract tables
    pr = pruned_search(env, target, ttype, tb, ns)
    last = pr['last']
    r['abs_found'] = pr['found']
    r['abs_wall'] = pr['wall_s']
    r['abs_checks'] = pr['cum_checks']
    r['abs_store'] = last['store_below']
    r['abs_store_j1'] = last['store_joint1']
    r['abs_cum_before'] = pr['cum_before']
    r['abs_below'] = last['below']
    r['abs_final_total'] = sum(last['fin_n'])
    r['audit'] = [(a, b, str(c), str(d), e) for (a, b, c, d, e) in ref_audit(task['term'], env, tb)]
    if pr['found']:
        sc = soft_counts(last, pr['ctx'])
        base = pr['cum_before'] + last['below']
        r['abs_final_lib'] = sc['lib']
        r['abs_final_opsoft'] = sc['op_soft']
        r['abs_final_bucketsoft'] = sc['bucket_soft']
        r['abs_lib'] = base + sc['lib']                         # (iii) cumulative, library order
        r['abs_one'] = last['below'] + sc['lib']                # (iii) single pass, oracle size
        r['abs_rand'] = base + expected_random_order(last['fin_n'], last['fin_hit'], rng)
        r['abs_opsoft'] = base + sc['op_soft']                  # (iv-a)
        r['abs_bucketsoft'] = base + sc['bucket_soft']          # (iv-b)
        # soft operator order WITHOUT pruning, applied to plain's final level (ordering only)
        r['softorder_plain'] = ps['below'] + count_under_order(n, hit, sc['order'])
    if do_post:
        pq = pruned_search(env, target, ttype, tb, ns, prefilter=False)
        r['post_found'] = pq['found']
        if pq['found']:
            sq = soft_counts(pq['last'], pq['ctx'])
            r['post_lib'] = pq['cum_before'] + pq['last']['below'] + sq['lib']
            r['post_store'] = pq['last']['store_below']
    return r


def fmt(x):
    if x is None:
        return '-'
    if isinstance(x, float):
        return '%.0f' % x
    return str(x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kind', default='iid')
    ap.add_argument('--M', type=int, default=2000)
    ap.add_argument('--seed', type=int, default=0)
    ap.add_argument('--tag', default='main')
    ap.add_argument('--taskseed', type=int, default=0, help='offset added to every task seed')
    a = ap.parse_args()
    rng = random.Random(12345)
    print('# Q2 main  kind=%s M=%d seed=%d taskseed=%d' % (a.kind, a.M, a.seed, a.taskseed))
    print('library: %d operators' % len(OPS))
    for (name, at, rt, fn) in OPS:
        print('   %-15s %s -> %s' % (name, ' x '.join(at), rt))
    # ---- tables
    reps = []
    for k in range(5):
        tm = {}
        tb = build_tables(HAND6, M=a.M, kind=a.kind, seed=a.seed, timing=tm)
        reps.append(tm)
    best = {k: min(t[k] for t in reps) for k in reps[0]}
    print('\ntables: %d quotients x %d operators, M=%d probes/operator (%s pool)' %
          (len(HAND6), len(OPS), a.M, a.kind))
    print('   quotients:', [q.name for q in HAND6])
    print('   abstract states per quotient (L+I):', tb.n_states(), ' table entries:', tb.n_entries())
    print('   build time, best of 5: probe pool %.1f ms, operator evaluation on probes %.1f ms, '
          'alpha + group-by %.1f ms' % (1e3 * best['pool_s'], 1e3 * best['probe_eval_s'],
                                        1e3 * best['groupby_s']))
    # ---- tasks
    ts = a.taskseed * 1000
    train = training_tasks(80, 100 + ts)
    rev = review_tasks(1 + ts)
    mine = my_tasks(200 + ts, exclude={term_str(t['term']) for t in train} |
                    {term_str(t['term']) for t in rev})
    tests = rev + mine
    print('\ntraining tasks for Naive Bayes: %d (operators held out: %s)' % (len(train), HELD_OUT))
    from collections import Counter
    cnt = Counter(o for t in train for o in set(t['ops']))
    print('   operators with zero training count:', [o for o in OPNAMES if cnt[o] == 0])
    print('   operator training counts:', dict(cnt.most_common()))
    tr = [(signature(t['env'], t['target'], t['ttype']), t['ops']) for t in train]
    nb = NaiveBayes(tr)
    nbb = NaiveBayes(tr, backoff_unseen=True)
    print('\ntest tasks:')
    for t in tests:
        print('   %-4s size %d  %s%s' % (t['name'], t['size'], term_str(t['term']),
                                         '   [COLD: %s]' % ','.join(t['cold']) if t['cold'] else ''))
    # ---- sanity: uniform-cost weighted search == plain (library order)
    t = tests[0]
    ws = weighted_search(t['env'], t['target'], {n: 1 for n in OPNAMES})
    res = []
    t0 = time.time()
    for t in tests:
        r = run_task(t, tb, nb, nbb, rng)
        res.append(r)
    print('\nsanity: unit-cost weighted search on %s = %s candidates; plain (library order) = %s'
          % (tests[0]['name'], ws['cands'], res[0]['plain_lib']))
    print('total search time %.1f s' % (time.time() - t0))

    # ---- table 1: candidates
    print('\n== Table A. Candidates evaluated until the reference behaviour is found ==')
    print('plain_lib = plain OE, library operator order; plain_rnd = mean over random operator orders;')
    print('NB-U1 = Naive Bayes order within each size level; NB-U2 = Naive Bayes costs (Probe-style);')
    print('abs = tables + hard pruning, iterative deepening, ALL passes counted (library order in last level);')
    print('abs1 = last pass only (size known); +op = soft operator order; +bkt = soft candidate order')
    hdr = ('task', 'sz', 'N*', 'plain_lib', 'plain_rnd', 'NB-U1', 'NB-U2', 'post', 'abs', 'abs1',
           '+op', '+bkt', 'gain_lib', 'gain_rnd', 'found')
    print(' '.join('%9s' % h for h in hdr))
    for r in res:
        gl = r['plain_lib'] / r['abs_opsoft'] if r['abs_found'] else None
        gr = r['plain_rand'] / r['abs_opsoft'] if r['abs_found'] else None
        row = (r['name'] + ('*' if r['cold'] else ''), r['size'], r['found_size'], r['plain_lib'],
               fmt(r['plain_rand']), r['nb_u1'],
               fmt(r.get('nb_u2')) if r.get('nb_u2') else '>%s' % r.get('nb_u2_capped'),
               fmt(r.get('post_lib')), fmt(r.get('abs_lib')), fmt(r.get('abs_one')),
               fmt(r.get('abs_opsoft')), fmt(r.get('abs_bucketsoft')),
               '%.1fx' % gl if gl else '-', '%.1fx' % gr if gr else '-',
               'yes' if r['abs_found'] else 'MISS')
        print(' '.join('%9s' % str(x) for x in row))
    print('(* = contains a held-out operator)')

    print('\n== Table B. Last size level only (where operator order matters) ==')
    hdr = ('task', 'level_n', 'plain_lib', 'plain_rnd', 'NB-U1', 'softord', 'abs_n', 'abs_lib',
           'abs+op', 'abs+bkt', 'NBrank')
    print(' '.join('%9s' % h for h in hdr))
    for r in res:
        row = (r['name'] + ('*' if r['cold'] else ''), r['plain_full'],
               r['plain_lib'], fmt(r['plain_rand']), r['nb_u1'], fmt(r.get('softorder_plain')),
               r['abs_final_total'], fmt(r.get('abs_final_lib')), fmt(r.get('abs_final_opsoft')),
               fmt(r.get('abs_final_bucketsoft')), r['nb_rank_hit'])
        print(' '.join('%9s' % str(x) for x in row))
    print('level_n = plain candidates through the complete last level; plain_lib/plain_rnd/NB-U1/softord are')
    print('totals for plain OE under four operator orders (softord = the table-derived soft order, no pruning);')
    print('abs_n = candidates admitted by the tables in the last level; abs_lib/abs+op/abs+bkt = position of')
    print('the hit among them under library / soft-operator / soft-candidate order; NBrank = NB rank (of 61) of')
    print('the best-ranked operator that produces the target at the last level.')

    print('\n== Table C. Classes stored below the last level, table look-ups, wall time ==')
    hdr = ('task', 'plain', 'post', 'abs', 'abs_j1', 'ratio', 'ratio_j1', 'lookups', 'plain_s',
           'abs_s')
    print(' '.join('%9s' % h for h in hdr))
    for r in res:
        row = (r['name'] + ('*' if r['cold'] else ''), r['plain_store'], fmt(r.get('post_store')),
               r['abs_store'], r['abs_store_j1'],
               '%.1fx' % (r['plain_store'] / max(1, r['abs_store'])),
               '%.1fx' % (r['plain_store'] / max(1, r['abs_store_j1'])), r['abs_checks'],
               '%.2f' % r['plain_wall'], '%.2f' % r['abs_wall'])
        print(' '.join('%9s' % str(x) for x in row))
    print('abs_j1 = additionally dropping size N-1 classes that no unary operator can take to the target;')
    print('plain_s is a COMPLETE last level, abs_s all passes with a complete last level (not time-to-hit).')

    print('\n== Naive Bayes detail ==')
    for r in res:
        print('   %-5s NB ranks of reference ops %s ; U2 op costs %s total cost %s ; U1 backoff %s ; U2 backoff %s'
              % (r['name'], r['nb_rank_refops'], r.get('nb_u2_opcost'), r.get('nb_u2_cost'),
                 r['nb_u1_backoff'], r.get('nb_u2_backoff')))

    print('\n== Soundness ==')
    nm = sum(1 for r in res if not r['abs_found'])
    print('tasks where (iii)/(iv) did not find the target at the size plain OE found it: %d of %d' %
          (nm, len(res)))
    for r in res:
        if r['audit'] or not r['abs_found']:
            print('   %-5s found=%s  table misses on the reference path: %s' %
                  (r['name'], r['abs_found'], r['audit']))

    def summarize(label, sel):
        rs = [r for r in res if sel(r) and r['abs_found']]
        if not rs:
            return

        def g(k1, k2):
            v = [r[k1] / r[k2] for r in rs if r.get(k1) and r.get(k2)]
            return '%.2fx [%.2f..%.2f] n=%d' % (gmean(v), min(v), max(v), len(v))
        print('\n-- %s (%d tasks): geometric-mean gain [min..max]' % (label, len(rs)))
        print('   plain_lib / abs (iii)            ', g('plain_lib', 'abs_lib'))
        print('   plain_lib / abs+op (iv-a)        ', g('plain_lib', 'abs_opsoft'))
        print('   plain_lib / abs+bkt (iv-b)       ', g('plain_lib', 'abs_bucketsoft'))
        print('   plain_rnd / abs_rnd (order-free) ', g('plain_rand', 'abs_rand'))
        print('   plain_rnd / abs+op               ', g('plain_rand', 'abs_opsoft'))
        print('   plain_lib / post-only            ', g('plain_lib', 'post_lib'))
        print('   plain_lib / NB-U1                ', g('plain_lib', 'nb_u1'))
        print('   plain_rnd / NB-U1                ', g('plain_rand', 'nb_u1'))
        print('   plain_lib / NB-U2 (uncapped only)', g('plain_lib', 'nb_u2'))
        print('   plain_rnd / softorder (no prune) ', g('plain_rand', 'softorder_plain'))
        print('   store: plain / abs               ', g('plain_store', 'abs_store'))
        print('   store: plain / abs_j1            ', g('plain_store', 'abs_store_j1'))
        print('   NB-U2 capped (no answer within cap):', sum(1 for r in rs if not r.get('nb_u2')))
    summarize('all tasks', lambda r: True)
    summarize('cold-start tasks (contain a held-out operator)', lambda r: r['cold'])
    summarize('warm tasks', lambda r: not r['cold'])
    summarize('cold operator at the root', lambda r: r['cold'] and r['term'].split('(')[0] in HELD_OUT)
    json.dump(res, open('q2_%s.json' % a.tag, 'w'), indent=1)


if __name__ == '__main__':
    main()
