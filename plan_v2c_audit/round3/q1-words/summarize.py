"""Collect the search results (search_*.json) into one table: candidate gain (order-averaged,
the 15.7x convention), stored-class gain, answers lost; plus the per-task comparison against the
hand list.   usage: python3 summarize.py search_main.json [search_more.json ...] > summary.log"""
import json
import math
import sys

rows = {}
for fn in sys.argv[1:]:
    for k, v in json.load(open(fn)).items():
        rows[k] = v
hand = rows.get('@hand6')
print('%-62s %2s %5s %9s %6s %6s %7s %8s %s' % ('vocabulary', 'K', 'lost', 'cand_rnd', 'min', 'max', 'store',
                                                 'store_j1', 'tasks better/worse than hand (x1.25)'))
for k, v in rows.items():
    bw = ''
    if hand is not None:
        b = w = 0
        for t, g in v['per_task'].items():
            h = hand['per_task'].get(t)
            if g is None or h is None:
                continue
            if g > 1.25 * h:
                b += 1
            elif g < h / 1.25:
                w += 1
        bw = '%d / %d' % (b, w)
    print('%-62s %2d %5d %8.2fx %6.1f %6.1f %6.2fx %7.2fx %s' % (k[:62], v['K'], v['miss'], v['cand_rnd'], v['mn'],
                                                               v['mx'], v['store'], v['store_j1'], bw))
