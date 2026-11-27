"""exp_main_S300.log and exp_audit_v1.log were produced with probegen_v1.py, whose
rules strat1, strat2, push2+strat1, push2+strat2 are called strat1d, strat2d,
push2+strat1d, push2+strat2d in the current probegen.py.  Check that the two give
identical tables (all rules whose definition did not change, and the renamed ones)."""
import importlib

from seqlib import HAND6

v1 = importlib.import_module('probegen_v1')
v2 = importlib.import_module('probegen')
PAIRS = [('iid', 'iid'), ('push2', 'push2'), ('hand', 'hand'), ('scalemix', 'scalemix'),
         ('strat1', 'strat1d'), ('strat2', 'strat2d'), ('push2+strat1', 'push2+strat1d'),
         ('push2+strat2', 'push2+strat2d')]
for M in (100, 1000):
    for sd in (0, 1):
        for a, b in PAIRS:
            t1 = v1.make_tables(a, M, sd, HAND6)
            t2 = v2.make_tables(b, M, sd, HAND6)
            same = t1.tab == t2.tab
            print('M=%-5d seed %d  v1 %-13s == current %-14s : %s' % (M, sd, a, b, same))
