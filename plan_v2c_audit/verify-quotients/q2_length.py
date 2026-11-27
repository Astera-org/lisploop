"""Q2: gain of abstract-table pruning as a function of pipeline length (2..5 operators).

For each length, --per random tasks over the 61-operator library (single input
xs, so that size-6 searches stay within the time budget), 8 example rows.
Tables: the six hand-listed quotients, 2000 i.i.d. probes per operator, and the
same with 20000 enriched probes.

usage: python3 q2_length.py [--per 10] [--procs 6]
"""
import argparse
import json
import math
import multiprocessing as mp
import time

from seqlib import OPNAMES, HAND6, build_tables
from q2common import compare
from q2tasks import gen_tasks

CONFIGS = {}
TASKS = []


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def job(ti):
    return compare(TASKS[ti], CONFIGS, 9000 + ti, trials=200)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--per', type=int, default=10)
    ap.add_argument('--procs', type=int, default=6)
    a = ap.parse_args()
    t0 = time.time()
    CONFIGS['6 quotients, iid M=2000'] = (build_tables(HAND6, M=2000, kind='iid', seed=0), None)
    CONFIGS['6 quotients, enriched M=20000'] = (build_tables(HAND6, M=20000, kind='enriched', seed=0), None)
    for n_ops in (2, 3, 4, 5):
        TASKS.extend(gen_tasks(a.per, 500 + n_ops, OPNAMES, n_ops_choices=(n_ops,), max_size=n_ops + 1,
                               prefix='L%d_' % n_ops, p_ys=0.0))
    print('# Q2 length sweep: %d tasks (unary chains over xs), %d processes' % (len(TASKS), a.procs))
    # longest tasks first so the pool balances
    order = sorted(range(len(TASKS)), key=lambda i: -TASKS[i]['size'])
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, order, chunksize=1)
    print('search time %.1f s' % (time.time() - t0))
    for cname in CONFIGS:
        print('\n== %s ==' % cname)
        print('%-7s %-58s %2s %10s %10s %9s %9s %8s %8s %8s %7s %7s %5s' %
              ('task', 'reference', 'N*', 'plain_lib', 'plain_rnd', 'abs_lib', 'abs_rnd', 'gain_rnd',
               'store', 'abs_st', 'st_j1', 'wall', 'found'))
        for r in sorted(res, key=lambda r: (r['n_ops'], r['name'])):
            c = r['cfg'][cname]
            if c['found']:
                print('%-7s %-58s %2d %10d %10.0f %9d %9.0f %7.1fx %8d %8d %7d %6.1fx %5s' %
                      (r['name'], r['term'][:58], r['found_size'], r['plain_lib'], r['plain_rand'],
                       c['abs_lib'], c['abs_rand'], r['plain_rand'] / c['abs_rand'], r['plain_store'],
                       c['store'], c['store_j1'], r['plain_wall'] / max(c['wall'], 1e-4), 'yes'))
            else:
                print('%-7s %-58s %2d %10d %10.0f %9s %9s %8s %8d %8d %7d %7s %5s' %
                      (r['name'], r['term'][:58], r['found_size'], r['plain_lib'], r['plain_rand'], '-', '-',
                       '-', r['plain_store'], c['store'], c['store_j1'], '-', 'MISS'))
        print('\n   by number of operators in the reference (geometric means over found tasks):')
        print('   %5s %5s %5s %12s %10s %10s %10s %10s %10s' %
              ('n_ops', 'tasks', 'miss', 'plain_rnd', 'gain_lib', 'gain_rnd', 'store', 'store_j1', 'wall'))
        for key, lab in (('n_ops', 'n_ops'), ('found_size', 'N*')):
            for k in sorted({r[key] for r in res}):
                rs = [r for r in res if r[key] == k]
                ok = [r for r in rs if r['cfg'][cname]['found']]
                if not ok:
                    continue
                print('   %s=%d %5d %5d %12.0f %9.1fx %9.1fx %9.1fx %9.1fx %9.1fx' %
                      (lab, k, len(rs), len(rs) - len(ok), gmean([r['plain_rand'] for r in ok]),
                       gmean([r['plain_lib'] / r['cfg'][cname]['abs_opsoft'] for r in ok]),
                       gmean([r['plain_rand'] / r['cfg'][cname]['abs_rand'] for r in ok]),
                       gmean([r['plain_store'] / max(1, r['cfg'][cname]['store']) for r in ok]),
                       gmean([r['plain_store'] / max(1, r['cfg'][cname]['store_j1']) for r in ok]),
                       gmean([r['plain_wall'] / r['cfg'][cname]['wall'] for r in ok
                              if r['plain_wall'] > 0.01])))
    json.dump(res, open('q2_length.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
