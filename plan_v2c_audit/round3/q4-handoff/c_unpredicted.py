"""Experiment C: tables are learned offline and only READ by the solver.  How often does
a task need something no table predicts, and what does the fallback cost?

  python3 c_unpredicted.py b12_s11.json b12_s12.json > c_unpredicted.log

For every ordinary task of b12.py and several probe budgets:
  unseen     a label of the target (some row, some quotient) that no probe value of that type ever had
  no_writer  a label of the target that no operator's table lists as an output
  path_miss  some step of the reference program maps input labels the probes SAW to an output
             label they never saw for them (q2search.ref_audit): the tables call it impossible
  lost       the label-filtered search does not find the answer at the size plain search does
Cost of a loss under the kernel's reserve rule (three parts tentative to one part fallback,
plan_v2c.md L565): the plain fallback finds the answer after its own cost P, by which time
the tentative side has spent 3P; a task the filter solves at cost F costs F * 4/3.
"""
import json
import sys
import time
from collections import Counter
from multiprocessing import Pool

from hlib import (L, I, OPSIG, BASE61, BASE61_SET, AbsCtx, tables_for, gmean, mean, median, eval_term,
                  expected_random_order, term_str)
import q2search
import q2tasks
import random

CONFIGS = [(100, 'iid', 0), (300, 'iid', 0), (1000, 'iid', 0), (2000, 'iid', 0), (2000, 'iid', 1),
           (2000, 'enriched', 0)]


def work(job):
    task, nstar, plain_cost = job
    env, Y, ty, term = task['env'], task['target'], task['ttype'], task['term']
    out = dict(name=task['name'], nstar=nstar, plain=plain_cost, cfg={})
    rng = random.Random(1)
    for (M, kind, seed) in CONFIGS:
        tb = tables_for(BASE61, M, kind, seed)
        unseen = no_writer = 0
        for j, q in enumerate(tb.q):
            written = set()
            for name in BASE61:
                if OPSIG[name][1] == ty:
                    for c in tb.tab[j][name].values():
                        written.update(c)
            for y in Y:
                lab = q.f[ty](y)
                if lab not in tb.dom[j][ty]:
                    unseen += 1
                if lab not in written:
                    no_writer += 1
        aud = q2search.ref_audit(term, env, tb)
        pr = q2search.pruned_search(env, Y, ty, tb, nstar, opnames=BASE61_SET)
        last = pr['last']
        cost = pr['cum_before'] + last['below'] + (
            expected_random_order(last['fin_n'], last['fin_hit'], rng, 200) if pr['found'] else sum(last['fin_n']))
        out['cfg']['%d/%s/%d' % (M, kind, seed)] = dict(unseen=unseen, no_writer=no_writer, path_miss=len(aud),
                                                        miss_ops=sorted({a[0] + ':' + a[1] for a in aud}),
                                                        found=pr['found'], cost=cost)
    return out


def main():
    jobs = []
    for fn in sys.argv[1:]:
        J = json.load(open(fn))
        tasks = q2tasks.gen_tasks(J['args']['n'], J['args']['seed'], list(BASE61), n_ops_choices=(3, 4),
                                  max_size=5, prefix='G')
        info = {t['name']: t for t in J['tasks'] if not t.get('skip')}
        jobs += [(t, info[t['name']]['nstar'], info[t['name']]['plain_cost']) for t in tasks if t['name'] in info]
    t0 = time.perf_counter()
    with Pool(14) as p:
        res = p.map(work, jobs, chunksize=1)
    print('C. %d ordinary tasks (%s); six quotients; wall %.0f s' % (len(res), ' + '.join(sys.argv[1:]),
                                                                    time.perf_counter() - t0))
    print('%-18s %7s %9s %9s %6s | %12s %14s %16s %16s' % (
        'probes/kind/seed', 'unseen', 'no writer', 'path miss', 'lost', 'gain if found',
        'sum-cost gain', 'with 3:1 reserve', 'reserve, no loss'))
    P = sum(r['plain'] for r in res)
    for (M, kind, seed) in CONFIGS:
        k = '%d/%s/%d' % (M, kind, seed)
        C = [r['cfg'][k] for r in res]
        lost = [r for r in res if not r['cfg'][k]['found']]
        ok = [r for r in res if r['cfg'][k]['found']]
        # every pass counted; a lost task falls back to plain
        tot_oracle = sum(r['cfg'][k]['cost'] for r in ok) + sum(r['cfg'][k]['cost'] + r['plain'] for r in lost)
        tot_reserve = sum(r['cfg'][k]['cost'] * 4 / 3 for r in ok) + sum(4 * r['plain'] for r in lost)
        tot_reserve0 = sum(r['cfg'][k]['cost'] * 4 / 3 for r in ok) + sum(r['plain'] / 16 * 4 / 3 for r in lost)
        print('%-18s %7d %9d %9d %6d | %11.1fx %13.1fx %15.1fx %15.1fx' % (
            k, sum(1 for c in C if c['unseen']), sum(1 for c in C if c['no_writer']),
            sum(1 for c in C if c['path_miss']), len(lost),
            gmean([r['plain'] / r['cfg'][k]['cost'] for r in ok]), P / tot_oracle, P / tot_reserve,
            P / tot_reserve0))
    k = '2000/iid/0'
    print('\nlost tasks at 2,000 probes: ' + '; '.join('%s (plain cost %d, misses %s)' % (
        r['name'], r['plain'], r['cfg'][k]['miss_ops']) for r in res if not r['cfg'][k]['found']))
    pm = [r for r in res if r['cfg'][k]['path_miss']]
    print('path misses at 2,000 probes: %d tasks; of these the search still found an answer in %d '
          '(another program, or the miss is on a step the filter did not test)' % (
              len(pm), sum(1 for r in pm if r['cfg'][k]['found'])))
    print('columns: "sum-cost gain" = total plain candidates / total candidates when a lost task is retried '
          'plain after the filtered passes;')
    print('         "with 3:1 reserve" = the same under the reserve rule (found: 4/3 of the filtered cost; '
          'lost: 4x the plain cost);')
    print('         "reserve, no loss" = what the reserve would cost if no task were lost (lost tasks priced '
          'as typical filtered ones).')


if __name__ == '__main__':
    main()
