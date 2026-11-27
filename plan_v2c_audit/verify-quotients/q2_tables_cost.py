"""Q2: cost of building the pushed-forward tables (best of 5), and the per-task
cost of the backward distance tables.

usage: python3 q2_tables_cost.py
"""
import random
import time

from seqlib import HAND6, QBYNAME, OPS, product_quotient, build_tables, make_pools, eval_probes, Tables
from q2search import AbsCtx
from q2tasks import review_tasks

Q = QBYNAME
m3 = product_quotient('sign*parity*order', [Q['sign'], Q['parity'], Q['order']])
print('# table-building cost: %d operators; times in ms, best of 5' % len(OPS))
print('%-34s %-9s %7s %9s %9s %9s %9s %8s %8s' %
      ('quotients', 'pool', 'M', 'pool', 'op eval', 'group-by', 'total', 'entries', 'count=1'))
for qname, qs in (('6 hand-listed', HAND6), ('1 merged sign*parity*order', [m3]),
                  ('merged3 + caplen5/lenmod2/isempty', [m3, Q['caplen5'], Q['lenmod2'], Q['isempty']])):
    for kind in ('iid', 'enriched'):
        for M in (200, 500, 2000, 20000):
            best = None
            for rep in range(5):
                tm = {}
                tb = build_tables(qs, M=M, kind=kind, seed=0, timing=tm)
                if best is None or sum(tm.values()) < sum(best.values()):
                    best = tm
            ones = sum(1 for tab in tb.tab for d in tab.values() for c in d.values() for v in c.values() if v == 1)
            print('%-34s %-9s %7d %9.1f %9.1f %9.1f %9.1f %8d %8d' %
                  (qname, kind, M, 1e3 * best['pool_s'], 1e3 * best['probe_eval_s'], 1e3 * best['groupby_s'],
                   1e3 * sum(best.values()), tb.n_entries(), ones))
print('''
pool = drawing the probe values; op eval = evaluating the 61 operators on their probes (the "existing probe
table" the review assumes is already there); group-by = evaluating every quotient on arguments and results and
grouping; count=1 = (argument tuple, result) pairs seen exactly once (a sign that more are unseen).''')
tb = build_tables(HAND6, M=2000, kind='iid', seed=0)
ts = []
for t in review_tasks(1):
    t0 = time.perf_counter()
    tb._succ = [None] * len(tb.q)
    AbsCtx(tb, t['target'], t['ttype'])
    ts.append(time.perf_counter() - t0)
print('per-task backward distance tables (6 quotients, successor graph rebuilt each time): mean %.1f ms, max %.1f ms'
      % (1e3 * sum(ts) / len(ts), 1e3 * max(ts)))
