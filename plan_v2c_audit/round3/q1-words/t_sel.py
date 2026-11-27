"""Smoke test of selection on a pool.  usage: python3 t_sel.py CONFIG [K]"""
import sys

from wordsel import *

cfg = sys.argv[1]
K = int(sys.argv[2]) if len(sys.argv) > 2 else 10
pool = load_pool(cfg)
print(cfg, len(pool['cands']), 'list candidates;', len(pool['icands']), 'int candidates')
ranked = rank(pool)
print('top 25 by mean dependency score (vacuity guard 0.05):')
for (s, c) in ranked[:25]:
    print('   %.3f  size %d card %d  %s' % (s, c['size'], c['cardf'], tstr(c['term'])))
for cap in (0.5, 0.65, 0.8):
    select(cfg, K=K, nmi_cap=cap, log=print)
select(cfg, K=K, pairs=False, log=print)
select(cfg, K=K, card=2, log=print)
select(cfg, K=K, card=4, log=print)
