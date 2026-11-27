"""Q2 with quotients chosen AUTOMATICALLY by lumpability (autoquot.py) instead of
the six hand-listed ones: same 60 tasks as q2_sweep.py, same search.

usage: python3 q2_auto.py [--procs 12]
"""
import argparse
import json
import math
import multiprocessing as mp
import time

from seqlib import OPNAMES, HAND6, build_tables, term_str
from q2common import compare
from q2tasks import review_tasks, training_tasks, my_tasks, gen_tasks
import autoquot

CONFIGS = {}
TASKS = []


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def job(ti):
    return compare(TASKS[ti], CONFIGS, 777 + ti, trials=300)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--procs', type=int, default=12)
    a = ap.parse_args()
    t0 = time.time()
    qs, info = autoquot.select(K=10, verbose=True)
    print('selection took %.1f s\n' % (time.time() - t0))
    CONFIGS['hand-listed 6'] = (build_tables(HAND6, M=2000, kind='iid', seed=0), None)
    CONFIGS['hand-listed 6, M=20000'] = (build_tables(HAND6, M=20000, kind='iid', seed=0), None)
    for K in (1, 3, 6, 10):
        CONFIGS['auto top-%d' % K] = (build_tables(qs[:K], M=2000, kind='iid', seed=0), None)
    CONFIGS['auto top-6, M=20000'] = (build_tables(qs[:6], M=20000, kind='iid', seed=0), None)
    CONFIGS['auto top-10, M=20000'] = (build_tables(qs[:10], M=20000, kind='iid', seed=0), None)
    for name, (tb, _) in CONFIGS.items():
        print('%-26s states per quotient %s, table entries %d' % (name, tb.n_states(), tb.n_entries()))
    train = training_tasks(80, 100)
    rev = review_tasks(1)
    ex = {term_str(t['term']) for t in train} | {term_str(t['term']) for t in rev}
    mine = my_tasks(200, exclude=ex)
    ex |= {term_str(t['term']) for t in mine}
    TASKS.extend(rev + mine + gen_tasks(40, 300, OPNAMES, prefix='X', exclude=ex))
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, range(len(TASKS)), chunksize=1)
    print('\n%d tasks; total %.1f s' % (len(TASKS), time.time() - t0))
    print('\n%-26s %4s %4s %9s %9s %7s %7s %7s %9s' %
          ('configuration', 'miss', 'aud', 'cand_lib', 'cand_rnd', 'min', 'max', 'store', 'store_j1'))
    for cname in CONFIGS:
        rs = [(r, r['cfg'][cname]) for r in res]
        ok = [(r, c) for r, c in rs if c['found']]
        gr = [r['plain_rand'] / c['abs_rand'] for r, c in ok]
        print('%-26s %4d %4d %8.2fx %8.2fx %7.1f %7.1f %6.2fx %8.2fx' %
              (cname, len(rs) - len(ok), sum(1 for r, c in rs if c['audit']),
               gmean([r['plain_lib'] / c['abs_opsoft'] for r, c in ok]), gmean(gr), min(gr), max(gr),
               gmean([r['plain_store'] / max(1, c['store']) for r, c in ok]),
               gmean([r['plain_store'] / max(1, c['store_j1']) for r, c in ok])))
    for cname in CONFIGS:
        bad = [(r['name'], r['term'], r['cfg'][cname]['audit_first'][:1]) for r in res
               if not r['cfg'][cname]['found']]
        if bad:
            print('MISSES under %s: %s' % (cname, bad))
    json.dump(res, open('q2_auto.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
