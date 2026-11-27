"""Audit-only comparison of probe rules on long task streams (no search).

For each (rule, M, seed) build the six-quotient tables and count, over a long
stream of tasks, how many have a DEFECT on the reference program's own path
(an input-label key the probes saw, with an output label they did not).  This
is the reviewer's EXP D measure; it is cheap, so it can use thousands of tasks
and ten seeds and separates rules that the 300-task searches cannot.

usage: python3 exp_audit.py [--rules ..] [--M 100,300,1000,3000,10000] [--seeds 10]
                            [--procs 12] [--nrand 4000] [--nedge 1500]
"""
import argparse
import multiprocessing as mp
import pickle
import os
import time
from collections import Counter

from seqlib import HAND6
from probegen import make_tables
from tasksets import get_tasks
from harness import ref_transitions, defects, CACHE

RULES = ['iid', 'strat1', 'strat2', 'push1', 'push2', 'push3', 'bank2', 'bank3', 'oelog3', 'oelog4',
         'push2+strat1', 'push2+strat2', 'bank2+strat1', 'bank2+strat2', 'hand', 'scalemix']
STREAMS = {}      # name -> list of transition sets


def job(arg):
    rule, M, sd = arg
    tb = make_tables(rule, M, sd, HAND6)
    out = {}
    for sname, trs in STREAMS.items():
        n = 0
        cnt = Counter()
        for tr in trs:
            d = defects(tr, tb)
            if d:
                n += 1
                cnt.update(d)
        out[sname] = (n, cnt)
    return arg, out, tb.n_entries(), tb.n_pairs()


def load_stream(name, n):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, 'trans_%s_%d.pkl' % (name, n))
    if os.path.exists(path):
        return pickle.load(open(path, 'rb'))
    tasks = get_tasks(name, n)
    trs = [ref_transitions(t['term'], t['env'], HAND6) for t in tasks]
    pickle.dump(trs, open(path, 'wb'))
    return trs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rules', default=','.join(RULES))
    ap.add_argument('--M', default='100,300,1000,3000,10000')
    ap.add_argument('--seeds', type=int, default=10)
    ap.add_argument('--procs', type=int, default=12)
    ap.add_argument('--nrand', type=int, default=4000)
    ap.add_argument('--nedge', type=int, default=1500)
    a = ap.parse_args()
    t0 = time.time()
    STREAMS['RAND7000'] = load_stream('RAND7000', a.nrand)
    STREAMS['EDGER7100'] = load_stream('EDGER7100', a.nedge)
    STREAMS['EDGEW7200'] = load_stream('EDGEW7200', a.nedge)
    print('# streams: %s; built in %.0f s' % ({k: len(v) for k, v in STREAMS.items()},
                                              time.time() - t0), flush=True)
    rules = a.rules.split(',')
    Ms = [int(x) for x in a.M.split(',')]
    jobs = [(r, M, sd) for r in rules for M in Ms for sd in range(a.seeds)]
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, jobs, chunksize=1)
    R = {arg: (out, e, p) for arg, out, e, p in res}
    qn = [q.name for q in HAND6]
    for sname, trs in STREAMS.items():
        n = len(trs)
        print('\n== stream %s (%d tasks): tasks with a reference-path defect, per 1,000 tasks; '
              'mean over %d table seeds [min..max] ==' % (sname, n, a.seeds))
        print('%-14s' % 'rule' + ''.join('%22s' % ('M=%d' % M) for M in Ms))
        for r in rules:
            line = '%-14s' % r
            for M in Ms:
                xs = [1000.0 * R[(r, M, sd)][0][sname][0] / n for sd in range(a.seeds)]
                line += '%10.2f [%4.1f..%5.1f]' % (sum(xs) / len(xs), min(xs), max(xs))
            print(line)
        print('-- seeds (of %d) with ZERO defective tasks' % a.seeds)
        for r in rules:
            print('%-14s' % r + ''.join(
                '%22d' % sum(1 for sd in range(a.seeds) if R[(r, M, sd)][0][sname][0] == 0)
                for M in Ms))
    print('\n== table size: input keys (entries) / (key, output) pairs, mean over seeds ==')
    print('%-14s' % 'rule' + ''.join('%22s' % ('M=%d' % M) for M in Ms))
    for r in rules:
        line = '%-14s' % r
        for M in Ms:
            e = sum(R[(r, M, sd)][1] for sd in range(a.seeds)) / a.seeds
            p = sum(R[(r, M, sd)][2] for sd in range(a.seeds)) / a.seeds
            line += '%22s' % ('%.0f / %.0f' % (e, p))
        print(line)
    print('\n== the commonest remaining defects (operator, quotient, input key -> missing output: '
          'tasks hit, summed over seeds and the three streams) ==')
    for r in rules:
        for M in Ms:
            if M not in (1000, 3000, 10000):
                continue
            cnt = Counter()
            for sd in range(a.seeds):
                for sname in STREAMS:
                    cnt.update(R[(r, M, sd)][0][sname][1])
            top = ', '.join('%s/%s %s->%s: %d' % (n_, qn[j], k, ar, c)
                            for (n_, j, k, ar), c in cnt.most_common(6))
            print('  %-14s M=%-6d distinct %3d | %s' % (r, M, len(cnt), top))
    print('\ntotal wall %.0f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
