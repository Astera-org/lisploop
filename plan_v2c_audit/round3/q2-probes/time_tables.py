"""Cost of building the six-quotient tables under each probe rule (one process).

usage: python3 time_tables.py [M ...]
"""
import sys
import time

from seqlib import HAND6
from probegen import make_tables

RULES = ['iid', 'strat1', 'strat2', 'push2', 'bank2', 'bank3', 'push2+strat1', 'bank2+strat1',
         'bank2+strat2', 'hand', 'scalemix']
Ms = [int(x) for x in sys.argv[1:]] or [1000]
print('%-14s %7s %8s %8s %7s %7s' % ('rule', 'M', 'seconds', 'entries', 'pairs', 'det'))
for M in Ms:
    for r in RULES:
        info = {}
        t0 = time.perf_counter()
        tb = make_tables(r, M, 0, HAND6, info=info)
        dt = time.perf_counter() - t0
        print('%-14s %7d %8.2f %8d %7d %7d  %s' %
              (r, M, dt, tb.n_entries(), tb.n_pairs(), tb.n_det(), info.get('buckets', '')))
