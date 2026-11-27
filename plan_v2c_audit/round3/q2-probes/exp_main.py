"""Decisive experiment: probe-generation rules at equal budgets, real searches.

For every (rule, M, seed): build the six-quotient verb tables from M probes per
operator, then run the table-filtered search on every task of the set and
count the answers lost.

usage: python3 exp_main.py --taskset S300 [--rules a,b,..] [--M 100,300,1000,3000]
                           [--seeds 0,1] [--procs 14] [--tag main]
"""
import argparse
import json
import time

from seqlib import HAND6
from probegen import make_tables
from tasksets import get_tasks
from harness import plain_cached, run_configs, summarize

RULES = ['iid', 'strat1', 'strat2', 'push1', 'push2', 'push3', 'bank2', 'bank3',
         'push2+strat1', 'push2+strat2', 'bank2+strat1', 'bank2+strat2', 'hand', 'scalemix']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--taskset', default='S300')
    ap.add_argument('--ntasks', type=int, default=None)
    ap.add_argument('--rules', default=','.join(RULES))
    ap.add_argument('--M', default='100,300,1000,3000')
    ap.add_argument('--seeds', default='0,1')
    ap.add_argument('--procs', type=int, default=14)
    ap.add_argument('--tag', default='main')
    a = ap.parse_args()
    rules = a.rules.split(',')
    Ms = [int(x) for x in a.M.split(',')]
    seeds = [int(x) for x in a.seeds.split(',')]
    t0 = time.time()
    tasks = get_tasks(a.taskset, a.ntasks)
    plain = plain_cached(a.taskset, tasks, a.procs)
    t1 = time.time()
    configs, meta = {}, {}
    for rule in rules:
        for M in Ms:
            for sd in seeds:
                info = {}
                tb = make_tables(rule, M, sd, HAND6, info=info)
                cname = '%s|%d|%d' % (rule, M, sd)
                configs[cname] = tb
                meta[cname] = dict(entries=tb.n_entries(), pairs=tb.n_pairs(), det=tb.n_det(),
                                   single=tb.n_single(), info=info)
    t2 = time.time()
    print('# %s: %d tasks (found sizes %s); %d configurations; plain %.0f s, tables %.0f s' %
          (a.taskset, len(tasks),
           {s: sum(1 for p in plain if p['found_size'] == s) for s in range(2, 7)},
           len(configs), t1 - t0, t2 - t1), flush=True)
    res = run_configs(tasks, plain, configs, a.procs)
    print('# search %.0f s' % (time.time() - t2))
    summ = {c: summarize(c, tasks, plain, res) for c in configs}
    print('\nPer seed.  lost = answers lost / %d; AUD = tasks whose reference path has a defect;'
          ' ndef = distinct defect transitions; gain = candidates, order-averaged, vs plain;'
          ' entries = input keys in all tables; pairs = (key, output label) pairs\n' % len(tasks))
    print('%-14s %6s %4s | %4s %5s %4s %4s | %7s %6s %7s | %7s %6s %6s' %
          ('rule', 'M', 'seed', 'lost', 'lost%', 'AUD', 'ndef', 'gain', 'store', 'storeJ1',
           'entries', 'pairs', 'cnt=1'))
    for c in configs:
        rule, M, sd = c.split('|')
        s, m = summ[c], meta[c]
        print('%-14s %6s %4s | %4d %4.1f%% %4d %4d | %6.2fx %5.2fx %6.2fx | %7d %6d %6d' %
              (rule, M, sd, s['miss'], 100.0 * s['miss'] / s['n'], s['aud'], s['ndefect'],
               s['gain'], s['store'], s['store_j1'], m['entries'], m['pairs'], m['single']))
    print('\nSummed over seeds %s (lost and AUD are totals over %d task-searches)\n' %
          (seeds, len(tasks) * len(seeds)))
    print('%-14s %6s | %5s %6s %5s | %7s | %8s %7s' %
          ('rule', 'M', 'lost', 'lost%', 'AUD', 'gain', 'entries', 'pairs'))
    for rule in rules:
        for M in Ms:
            cs = ['%s|%d|%d' % (rule, M, sd) for sd in seeds]
            lost = sum(summ[c]['miss'] for c in cs)
            aud = sum(summ[c]['aud'] for c in cs)
            n = sum(summ[c]['n'] for c in cs)
            g = sum(summ[c]['gain'] for c in cs) / len(cs)
            e = sum(meta[c]['entries'] for c in cs) / len(cs)
            p = sum(meta[c]['pairs'] for c in cs) / len(cs)
            print('%-14s %6d | %5d %5.2f%% %5d | %6.2fx | %8.0f %7.0f' %
                  (rule, M, lost, 100.0 * lost / n, aud, g, e, p))
        print()
    print('Lost tasks and their defects (first 3), per configuration with a loss:')
    qn = [q.name for q in HAND6]
    for c in configs:
        for t, r in zip(tasks, res):
            if not r[c]['found']:
                d = [(n, qn[j], k, ar) for (n, j, k, ar) in r[c]['defects'][:3]]
                print('  %-22s %-6s %-50s %s' % (c, t['name'], term_str_(t), d))
    for c in configs:
        if summ[c]['lost_clean']:
            print('  NOTE %s: lost with a clean reference path: %s' % (c, summ[c]['lost_clean']))
    if any(m['info'] for m in meta.values()):
        print('\nOccupied buckets for the stratified rules, per signature:')
        for c, m in meta.items():
            if m['info']:
                print('  %-22s buckets %s' % (c, m['info']['buckets']))
    json.dump(dict(summary=summ, meta=meta,
                   res=[{c: dict(found=r[c]['found'], abs_rand=r[c].get('abs_rand'),
                                 defects=[str(x) for x in r[c]['defects']]) for c in configs}
                        for r in res]),
              open('exp_main_%s_%s.json' % (a.taskset, a.tag), 'w'))
    print('\ntotal wall %.0f s' % (time.time() - t0))


def term_str_(t):
    from seqlib import term_str
    return term_str(t['term'])


if __name__ == '__main__':
    main()
