import json, math
SRC = '/home/tlh24/lisploop/plan_v2c_audit/verify-quotients/'
res = json.load(open(SRC + 'q2_length.json'))
c = '6 quotients, iid M=2000'
def fit(xs, ys):
    n = len(xs); mx = sum(xs)/n; my = sum(ys)/n
    sxx = sum((x-mx)**2 for x in xs); sxy = sum((x-mx)*(y-my) for x, y in zip(xs, ys))
    b = sxy/sxx; a = my - b*mx
    rss = sum((y - a - b*x)**2 for x, y in zip(xs, ys)); se = math.sqrt(rss/(n-2)/sxx)
    return b, se, n
for lab, f in (('cand gain, order-averaged', lambda r: r['plain_rand']/r['cfg'][c]['abs_rand']),
               ('cand gain, library order', lambda r: r['plain_lib']/r['cfg'][c]['abs_opsoft']),
               ('stored-class gain', lambda r: r['plain_store']/max(1, r['cfg'][c]['store'])),
               ('stored gain + look-ahead', lambda r: r['plain_store']/max(1, r['cfg'][c]['store_j1'])),
               ('wall gain (plain wall > 10 ms)', None)):
    if f is None:
        rs = [r for r in res if r['plain_wall'] > 0.01 and r['found_size'] >= 3]
        f2 = lambda r: r['plain_wall']/r['cfg'][c]['wall']
    else:
        rs = [r for r in res if r['found_size'] >= 3]; f2 = f
    xs = [r['found_size'] for r in rs]; ys = [math.log(f2(r)) for r in rs]
    b, se, n = fit(xs, ys)
    print('%-32s n=%d  factor per extra node: x%.2f  (95%% interval x%.2f .. x%.2f)' % (lab, n, math.exp(b), math.exp(b-2*se), math.exp(b+2*se)))
# per-size ranges
for s in (3,4,5,6):
    rs = [r for r in res if r['found_size']==s]
    g = sorted(r['plain_rand']/r['cfg'][c]['abs_rand'] for r in rs)
    w = sorted(r['plain_wall']/r['cfg'][c]['wall'] for r in rs)
    print('N*=%d n=%d cand gain min %.1f max %.1f | wall ratio min %.2f max %.2f | plain wall max %.4fs' % (s, len(rs), g[0], g[-1], w[0], w[-1], max(r['plain_wall'] for r in rs)))
# plain growth per level
import statistics
