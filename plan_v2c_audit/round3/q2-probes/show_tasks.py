"""Print a few tasks of each edge-stressed set (sanity check of tasksets.py)."""
import time

from seqlib import term_str
from tasksets import get_tasks

for name in ('EDGE-R', 'EDGE-W'):
    t0 = time.time()
    ts = get_tasks(name)
    print('%s: %d tasks in %.1f s; sizes %s; two-input tasks %d' %
          (name, len(ts), time.time() - t0,
           {s: sum(1 for t in ts if t['size'] == s) for s in range(3, 7)},
           sum(1 for t in ts if len(t['env']) == 2)))
    for t in ts[:6]:
        print('   %-48s row0: %s -> %s' %
              (term_str(t['term']), {k: v[0] for k, v in t['env'].items()}, t['target'][0]))
