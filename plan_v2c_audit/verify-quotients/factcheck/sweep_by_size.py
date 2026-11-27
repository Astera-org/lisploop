import json, math, sys
SRC = '/home/tlh24/lisploop/plan_v2c_audit/verify-quotients/'
d = json.load(open(SRC + 'q2_sweep.json'))
print(type(d), (list(d.keys()) if isinstance(d, dict) else len(d)))
res = d['res'] if isinstance(d, dict) and 'res' in d else d
r0 = res[0]
print({k: (v if not isinstance(v, (dict, list)) else type(v).__name__) for k, v in r0.items()})
cn = list(r0['cfg'].keys())
print(cn)
print(r0['cfg'][cn[0]])
def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')
sizes = sorted({r['found_size'] for r in res})
print('sizes', sizes, {s: sum(1 for r in res if r['found_size'] == s) for s in sizes})
print('%-36s' % 'config (cand_rnd gain by N*)', ' '.join('N*=%d(n)' % s for s in sizes))
for c in cn:
    row = []
    for s in sizes:
        ok = [r for r in res if r['found_size'] == s and r['cfg'][c]['found']]
        row.append('%6.1fx(%d)' % (gmean([r['plain_rand'] / r['cfg'][c]['abs_rand'] for r in ok]), len(ok)))
    print('%-36s' % c[:36], ' '.join(row))
print()
print('lib-order gain (plain_lib/abs_opsoft) by N*')
for c in cn:
    row = []
    for s in sizes:
        ok = [r for r in res if r['found_size'] == s and r['cfg'][c]['found']]
        row.append('%6.1fx(%d)' % (gmean([r['plain_lib'] / r['cfg'][c]['abs_opsoft'] for r in ok]), len(ok)))
    print('%-36s' % c[:36], ' '.join(row))
