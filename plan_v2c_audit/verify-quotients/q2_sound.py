"""Q2 soundness study: how often does pruning by probe-learned tables LOSE the
reference behaviour, as a function of the number of probes per operator, the
probe pool, and the granularity of the quotient (factored vs merged product)?

A MISS = the abstract-table search does not find the target at the size at
which plain OE finds it.  AUD = the reference program itself uses an abstract
transition (seen argument tuple, unseen result) that is absent from the tables.
'guard(k,s)' = my addition: an argument tuple counts as unseen (TOP) unless it
was probed >= k times and every recorded result was seen > s times.

usage: python3 q2_sound.py [--tasks 300] [--procs 12]
"""
import argparse
import json
import math
import multiprocessing as mp
import time

from seqlib import OPNAMES, HAND6, QBYNAME, product_quotient, build_tables, term_str
from q2common import compare
from q2tasks import gen_tasks

CONFIGS = {}
TASKS = []


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def job(ti):
    return compare(TASKS[ti], CONFIGS, 4242 + ti, trials=200)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tasks', type=int, default=300)
    ap.add_argument('--procs', type=int, default=12)
    a = ap.parse_args()
    t0 = time.time()
    Q = QBYNAME
    m3 = product_quotient('sign*parity*order', [Q['sign'], Q['parity'], Q['order']])
    info = {}

    def add(name, tb):
        CONFIGS[name] = (tb, None)
        ones = sum(1 for tab in tb.tab for d in tab.values() for c in d.values()
                   for v in c.values() if v == 1)
        info[name] = (tb.n_entries(), ones)
    for kind in ('iid', 'enriched'):
        for M in (100, 300, 1000, 3000, 10000, 30000):
            add('factored 6, %s M=%d' % (kind, M), build_tables(HAND6, M=M, kind=kind, seed=0))
    for M in (300, 3000, 30000):
        tb = build_tables(HAND6, M=M, kind='iid', seed=0)
        add('factored 6, iid M=%d, guard(30,1)' % M, tb.guarded(30, 1))
    for M in (3000, 30000, 300000):
        tb = build_tables([m3], M=M, kind='iid', seed=0)
        add('merged sign*parity*order, iid M=%d' % M, tb)
        add('merged sign*parity*order, iid M=%d, guard(30,1)' % M, tb.guarded(30, 1))
    for M in (3000, 30000):
        tb = build_tables([m3, Q['caplen5'], Q['lenmod2'], Q['isempty']], M=M, kind='enriched', seed=0)
        add('merged3 + 3 length, enriched M=%d' % M, tb)
        add('merged3 + 3 length, enriched M=%d, guard(30,1)' % M, tb.guarded(30, 1))
    TASKS.extend(gen_tasks(a.tasks, 900, OPNAMES, prefix='S'))
    print('# Q2 soundness: %d random 3-4 operator tasks, %d configurations; setup %.1f s' %
          (len(TASKS), len(CONFIGS), time.time() - t0))
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, range(len(TASKS)), chunksize=1)
    print('search time %.1f s; tasks by found size: %s' %
          (time.time() - t0, {s: sum(1 for r in res if r['found_size'] == s) for s in range(2, 7)}))
    print('\n%-52s %7s %7s %5s %6s %5s %8s %7s %8s' %
          ('configuration', 'entries', 'count=1', 'MISS', 'miss%', 'AUD', 'cand_rnd', 'store', 'store_j1'))
    summary = {}
    for cname in CONFIGS:
        rs = [(r, r['cfg'][cname]) for r in res]
        ok = [(r, c) for r, c in rs if c['found']]
        miss = len(rs) - len(ok)
        aud = sum(1 for r, c in rs if c['audit'])
        gr = gmean([r['plain_rand'] / c['abs_rand'] for r, c in ok])
        st = gmean([r['plain_store'] / max(1, c['store']) for r, c in ok])
        sj = gmean([r['plain_store'] / max(1, c['store_j1']) for r, c in ok])
        summary[cname] = dict(entries=info[cname][0], singletons=info[cname][1], miss=miss, aud=aud,
                              cand_rnd=gr, store=st, store_j1=sj)
        print('%-52s %7d %7d %5d %5.1f%% %5d %7.2fx %6.2fx %7.2fx' %
              (cname, info[cname][0], info[cname][1], miss, 100.0 * miss / len(rs), aud, gr, st, sj))
    print('\nexamples of misses (configuration: task, reference, first missing transitions '
          '(operator, quotient, abstract args, abstract result, row)):')
    for cname in CONFIGS:
        bad = [r for r in res if not r['cfg'][cname]['found']][:3]
        for r in bad:
            print('  %-44s %-5s %-52s %s' % (cname, r['name'], r['term'], r['cfg'][cname]['audit_first']))
    # misses that are NOT explained by a missing transition on the reference path
    for cname in CONFIGS:
        odd = [r['name'] for r in res if not r['cfg'][cname]['found'] and not r['cfg'][cname]['audit']]
        if odd:
            print('  NOTE %s: misses with a clean reference path (lost via an equivalent shorter program): %s'
                  % (cname, odd))
    json.dump(dict(summary=summary, res=res), open('q2_sound.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
