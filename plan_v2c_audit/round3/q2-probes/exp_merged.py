"""P3: merged product quotients under automatic probe rules.

Quotient sets:
  merged3      one quotient: sign x parity x order            (as verify-quotients 2.6)
  merged3+len  that product + caplen5, lenmod2, isempty      (same information as the six)
  factored6    the six separate quotients (reference)

usage: python3 exp_merged.py [--rules iid,bank2,...] [--M 1000,3000,10000] [--seeds 0,1]
                             [--sets S300] [--procs 12] [--tag main]
"""
import argparse
import time

from seqlib import HAND6, QBYNAME, product_quotient
from probegen import make_tables
from tasksets import get_tasks
from harness import plain_cached, run_configs, summarize

M3 = product_quotient('sign*parity*order', [QBYNAME['sign'], QBYNAME['parity'], QBYNAME['order']])
QSETS = {
    'merged3': [M3],
    'merged3+len': [M3, QBYNAME['caplen5'], QBYNAME['lenmod2'], QBYNAME['isempty']],
    'factored6': HAND6,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rules', default='iid,bank2,bank2+strat1,hand')
    ap.add_argument('--M', default='1000,3000,10000')
    ap.add_argument('--seeds', default='0,1')
    ap.add_argument('--sets', default='S300')
    ap.add_argument('--quots', default='merged3,merged3+len,factored6')
    ap.add_argument('--guards', default='10')
    ap.add_argument('--procs', type=int, default=12)
    a = ap.parse_args()
    rules = a.rules.split(',')
    Ms = [int(x) for x in a.M.split(',')]
    seeds = [int(x) for x in a.seeds.split(',')]
    guards = [int(x) for x in a.guards.split(',') if x]
    t0 = time.time()
    configs, meta = {}, {}
    for qs in a.quots.split(','):
        for rule in rules:
            for M in Ms:
                for sd in seeds:
                    tb = make_tables(rule, M, sd, QSETS[qs])
                    c = '%s|%s|%d|%d|none' % (qs, rule, M, sd)
                    configs[c] = tb
                    for k in guards:
                        if qs != 'factored6':
                            configs['%s|%s|%d|%d|min_count(%d)' % (qs, rule, M, sd, k)] = tb.min_count(k)
    for c, tb in configs.items():
        meta[c] = (tb.n_entries(), tb.n_pairs(), tb.n_single(), tb.n_states())
    print('# %d configurations, tables %.0f s' % (len(configs), time.time() - t0), flush=True)
    for setname in a.sets.split(','):
        tasks = get_tasks(setname)
        plain = plain_cached(setname, tasks, a.procs)
        res = run_configs(tasks, plain, configs, a.procs)
        print('\n== task set %s (%d tasks); lost and AUD summed over table seeds %s ==' %
              (setname, len(tasks), seeds))
        print('%-12s %-13s %6s %-13s | %5s %6s %5s | %7s %6s | %8s %7s %7s %s' %
              ('quotients', 'rule', 'M', 'guard', 'lost', 'lost%', 'AUD', 'gain', 'store',
               'entries', 'pairs', 'cnt=1', 'labels'))
        for qs in a.quots.split(','):
            for rule in rules:
                for M in Ms:
                    for g in ['none'] + ['min_count(%d)' % k for k in guards]:
                        cs = ['%s|%s|%d|%d|%s' % (qs, rule, M, sd, g) for sd in seeds]
                        if cs[0] not in configs:
                            continue
                        ss = [summarize(c, tasks, plain, res) for c in cs]
                        lost = sum(s['miss'] for s in ss)
                        n = sum(s['n'] for s in ss)
                        print('%-12s %-13s %6d %-13s | %5d %5.2f%% %5d | %6.2fx %5.2fx | %8.0f %7.0f %7.0f %s'
                              % (qs, rule, M, g, lost, 100.0 * lost / n, sum(s['aud'] for s in ss),
                                 sum(s['gain'] for s in ss) / len(ss),
                                 sum(s['store'] for s in ss) / len(ss),
                                 sum(meta[c][0] for c in cs) / len(cs),
                                 sum(meta[c][1] for c in cs) / len(cs),
                                 sum(meta[c][2] for c in cs) / len(cs), meta[cs[0]][3]))
                print()
        for c in configs:
            s = summarize(c, tasks, plain, res)
            if s['lost_clean']:
                print('  NOTE %s: lost with a clean reference path: %s' % (c, s['lost_clean']))
    print('\ntotal wall %.0f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
