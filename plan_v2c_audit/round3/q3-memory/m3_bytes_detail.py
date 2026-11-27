"""Why the BYTE gain on the 61-operator library is smaller than the ENTRY gain.

For the review's eight tasks (2,000-probe tables): Python bytes per stored class in plain search,
split by the type of the column (a list per row, or an integer per row), and in the filtered
search (F-c), split into the columns themselves and the label bookkeeping kept beside them.
Also: Python bytes of one hash-only entry (an integer in a set)."""
import random

from seqlib import L, I, HAND6, build_tables
from q2search import AbsCtx
from q2tasks import review_tasks
from mem61 import plain_pass, pass61
from memlib import deep_size

tb = build_tables(HAND6, M=2000, kind='iid', seed=0)
tot = dict(pl_L=0, pl_I=0, n_L=0, n_I=0, fc_cols=0, fc_all=0, fc_n=0, fcL=0, fcI=0)
for task in review_tasks(1):
    env, target, ttype = task['env'], task['target'], task['ttype']
    pa = plain_pass(env, target, task['size'], asgo=True)
    ns = pa['hit_size']
    pg = plain_pass(env, target, ns)
    for t_ in (L, I):
        cols = [c for lv in pg['lev'][t_].values() for c in lv]
        tot['pl_' + t_] += deep_size([cols])
        tot['n_' + t_] += len(cols)
    ctx = AbsCtx(tb, target, ttype)
    # the last pass of F-c, keeping its structures: re-run pass61's logic through a thin copy
    r = pass61(env, target, ns, ctx, True, 'c', False)
    tot['fc_all'] += r['bytes']
    tot['fc_n'] += r['seen_n']
print('plain, eight tasks: %d list-valued classes at %.0f bytes each; %d integer-valued classes at %.0f bytes each'
      % (tot['n_L'], tot['pl_L'] / max(1, tot['n_L']), tot['n_I'], tot['pl_I'] / max(1, tot['n_I'])))
print('F-c (test before insert), eight tasks: %d classes at %.0f bytes each, labels included' %
      (tot['fc_n'], tot['fc_all'] / max(1, tot['fc_n'])))
rng = random.Random(0)
s = set(rng.getrandbits(62) for _ in range(500000))
print('hash-only entry (an integer in a Python set): %.1f bytes' % (deep_size([s]) / len(s)))
