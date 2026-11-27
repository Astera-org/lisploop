"""Small read-outs from m3_lib61.json: cost of restarting at each bound on the library, the
spread of the per-task gains, and the comparison with the earlier sweep's stored counts."""
import json
import math

res = json.load(open('m3_lib61.json'))
old = json.load(open('/home/tlh24/lisploop/plan_v2c_audit/verify-quotients/q2_sweep.json'))['res']


def gm(v):
    return math.exp(sum(math.log(x) for x in v) / len(v))


for c in ('D-c', 'F-c', 'FL-c'):
    k = '2000|' + c
    tot = sum(r['cfg'][k]['evaluated'] for r in res)
    last = sum(r['cfg'][k]['last_evaluated'] for r in res)
    g = [r['plain_below'] / max(1, r['cfg'][k]['seen']) for r in res]
    gb = [r['plain_bytes'] / max(1, r['cfg'][k]['bytes']) for r in res]
    print('%-5s evaluations: all passes %d, last pass %d (restart costs %.2fx); entry gain gmean %.2fx '
          '[%.2f..%.2f]; python byte gain gmean %.2fx [%.2f..%.2f]; on sums %.2fx entries, %.2fx bytes' %
          (c, tot, last, tot / last, gm(g), min(g), max(g), gm(gb), min(gb), max(gb),
           sum(r['plain_below'] for r in res) / sum(r['cfg'][k]['seen'] for r in res),
           sum(r['plain_bytes'] for r in res) / sum(r['cfg'][k]['bytes'] for r in res)))
for c in ('D-b', 'F-b', 'FL-b'):
    k = '2000|' + c
    print('%-5s on sums: dedupe-table entries %.2fx fewer than plain, bank %.2fx, python bytes %.2fx' %
          (c, sum(r['plain_below'] for r in res) / sum(r['cfg'][k]['seen'] for r in res),
           sum(r['plain_below'] for r in res) / sum(r['cfg'][k]['bank'] for r in res),
           sum(r['plain_bytes'] for r in res) / sum(r['cfg'][k]['bytes'] for r in res)))
same_store = sum(1 for r, o in zip(res, old) if r['cfg']['2000|F-c']['seen'] == o['cfg']['6: all']['store'])
same_j1 = sum(1 for r, o in zip(res, old) if r['cfg']['2000|FL-c']['seen'] == o['cfg']['6: all']['store_j1'])
same_plain = sum(1 for r, o in zip(res, old) if r['plain_below'] == o['plain_store'])
print('against the earlier sweep (q2_sweep.json, "6: all"), per task: plain stored equal on %d of 60; '
      'F-c dedupe table == earlier `store` on %d; FL-c dedupe table == earlier `store_j1` on %d' %
      (same_plain, same_store, same_j1))
print('plain: classes held at the hit if every size is stored as enumerated / classes below the hit size: '
      '%.1fx on sums' % (sum(r['plain_at_hit'] for r in res) / sum(r['plain_below'] for r in res)))
