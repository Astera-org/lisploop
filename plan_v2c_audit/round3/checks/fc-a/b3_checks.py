import json, math, sys
D = '/home/tlh24/lisploop/plan_v2c_audit/round3/q4-handoff/'
def gm(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs))
for f in ('b3_os_s21.json', 'b3_os_s22.json'):
    d = json.load(open(D + f))
    T = d['tasks'] if isinstance(d, dict) and 'tasks' in d else (d['res'] if isinstance(d, dict) and 'res' in d else d)
    if isinstance(T, dict):
        print(f, list(T.keys())[:10]); continue
    t0 = T[0]
    print(f, len(T), sorted(k for k in t0.keys()))
    for a, b in (('A', 'C'), ('B', 'E'), ('D', 'D2'), ('C', 'D'), ('C', 'D2'), ('B', 'C'), ('B', 'D2')):
        ok = [t for t in T if t.get(a) and t.get(b)]
        r = gm([t[a] / t[b] for t in ok])
        ck = b + '_checks'
        ak = a + '_checks'
        if all(ck in t for t in ok):
            r2 = gm([(t[a] + t.get(ak, 0)) / (t[b] + t[ck]) for t in ok])
        else:
            r2 = float('nan')
        print('  %s / %s = %.2fx (n=%d); with each check counted as one candidate on both sides: %.2fx' % (a, b, r, len(ok), r2))
