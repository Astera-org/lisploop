"""The reviewer's EXP D (exp_devils_advocate.py run_exp_d), ported so its fixed
choices can be varied.  Only the reviewer's operator library is imported; the
quotients, probe generator, task generator and the "miss" test are re-typed from
the reviewer's code and behave identically at the reviewer's settings (first
block of the log reproduces 110 / 55 / 0 / 50 / 43).

In this experiment a "miss" is NOT a failed search: it is a task whose
reference chain uses a (seen input label -> unseen output label) transition.

usage: python3 revD_vary.py > revD_vary.log
"""
import random
import sys
from collections import defaultdict

REV = '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer'
sys.path.insert(0, REV)
from exp_lang_heuristics_v2 import make_61_library   # noqa: E402

from probegen import reservoirs, stratified_pool      # noqa: E402  (my bucket stratifier)

OPS = make_61_library()
U_SEQ = [k for k, (at, rt, _) in OPS.items() if at == ('seq',) and rt == 'seq']


def q_len(v): return min(len(v), 6)


def q_nonneg(v):
    if not v: return 'E'
    if all(x > 0 for x in v): return 'P'
    if all(x >= 0 for x in v): return 'N0'
    if all(x < 0 for x in v): return 'NEG'
    return 'M'


def q_parity(v):
    if not v: return 'E'
    if all(x % 2 == 0 for x in v): return 'EV'
    if all(x % 2 != 0 for x in v): return 'OD'
    return 'M'


def q_order(v):
    if len(v) <= 1: return 'S01'
    if len(set(v)) == 1: return 'C'
    if all(v[i] <= v[i + 1] for i in range(len(v) - 1)): return 'ASC'
    if all(v[i] >= v[i + 1] for i in range(len(v) - 1)): return 'DSC'
    return 'U'


def q_prod(v): return (q_nonneg(v), q_parity(v), q_order(v))


SEP = {'len': q_len, 'nonneg': q_nonneg, 'parity': q_parity, 'order': q_order}
MRG = {'len': q_len, 'prod': q_prod}
TRANSFORMS = ['raw', 'sorted', 'sorted_desc', 'abs', 'dbl', 'dbl+1', 'constant', 'equal_prefix']
REVIEWER_ROWS = [(3, 3, 3, 1), (2, 4, 6, 8), (0, 0, 0), (5, 4, 3, 2), (-2, -2, -1)]
# a second hand list of structured rows, written without looking at the transforms' outputs
OTHER_ROWS = [(4, 4, 4, 4, 2), (1, 1, 0, 0), (0, 0, 5), (-1, -3, -3), (2, 2, 2, 2, 2, 2),
              (0, -2, -4), (1, 3, 5, 7), (-5, 0, 0), (0, 1, 0, 1), (-1, -1, -1, -1, -1)]


class _Q:
    def __init__(self, fn):
        self.f = {'L': fn}


def gen_probes(n, kind, seed=11, drop=()):
    rng = random.Random(seed)
    ps = [()]
    if kind == 'hand':
        for Ln in range(1, 7):
            for _ in range(max(2, n // 90)):
                s = tuple(rng.randint(-5, 5) for _ in range(Ln))
                allt = [s, tuple(sorted(s)), tuple(sorted(s, reverse=True)),
                        tuple(abs(x) for x in s), tuple(2 * x for x in s),
                        tuple(2 * x + 1 for x in s), (s[0],) * Ln, (s[0], s[0]) + s[2:]]
                ps.extend(v for nm, v in zip(TRANSFORMS, allt) if nm not in drop)
    if kind == 'bucket':          # literal stratification by the four quotients' buckets
        cands = [tuple(rng.randint(-6, 6) for _ in range(rng.randint(0, 7))) for _ in range(20 * n)]
        resv = reservoirs(cands, [_Q(f) for f in SEP.values()], 'L', 1)
        return stratified_pool(rng, resv, n)
    while len(ps) < n:
        ps.append(tuple(rng.randint(-6, 6) for _ in range(rng.randint(0, 7))))
    return ps[:n]


def build_vt(doms, probes):
    vt = {dn: {opk: defaultdict(set) for opk in U_SEQ} for dn in doms}
    labs = {dn: [dfn(s) for s in probes] for dn, dfn in doms.items()}
    for opk in U_SEQ:
        fn = OPS[opk][2]
        outs = [fn(s) for s in probes]
        for dn, dfn in doms.items():
            t = vt[dn][opk]
            for a, o in zip(labs[dn], outs):
                if o is not None:
                    t[a].add(dfn(o))
    return vt


def gen_tasks(seed=888, edge_rows=REVIEWER_ROWS, n=200):
    rng = random.Random(seed)
    tasks = []
    for _ in range(n):
        chain = [rng.choice(U_SEQ) for _ in range(3)]
        rows = [tuple(rng.randint(-5, 5) for _ in range(rng.randint(1, 6))) for _ in range(6)]
        if edge_rows:
            rows[0] = rng.choice(edge_rows)
        ok = True
        cur = rows
        interm = [rows]
        for opk in chain:
            nxt = []
            for x in cur:
                v = OPS[opk][2](x)
                if v is None:
                    ok = False
                    break
                nxt.append(v)
            if not ok:
                break
            cur = nxt
            interm.append(cur)
        if ok:
            tasks.append((chain, interm))
    return tasks


def stream(doms, probes, tasks, feedback=False, create=True):
    vt = build_vt(doms, probes)
    miss = 0
    for chain, interm in tasks:
        bad = False
        for step, opk in enumerate(chain):
            for dn, dfn in doms.items():
                for x, y in zip(interm[step], interm[step + 1]):
                    outs = vt[dn][opk].get(dfn(x))
                    if outs is not None and dfn(y) not in outs:
                        bad = True
        if bad:
            miss += 1
            if feedback:
                for step, opk in enumerate(chain):
                    for dn, dfn in doms.items():
                        for x, y in zip(interm[step], interm[step + 1]):
                            ax = dfn(x)
                            if create or ax in vt[dn][opk]:
                                vt[dn][opk][ax].add(dfn(y))
    return miss


def main():
    T = gen_tasks()
    print('tasks kept: %d of 200 attempts (the reviewer divides by 200)' % len(T))
    print('\n1. the reviewer\'s settings (review: 110, 55, 0, 50, 43)')
    print('   separate 4, 150 random, no feedback : %3d' % stream(SEP, gen_probes(150, 'random'), T))
    print('   separate 4, 150 random, feedback    : %3d' % stream(SEP, gen_probes(150, 'random'), T, True))
    print('   separate 4, 1000 "stratified"       : %3d' % stream(SEP, gen_probes(1000, 'hand'), T))
    print('   merged, 2000 "stratified"           : %3d' % stream(MRG, gen_probes(2000, 'hand'), T))
    print('   merged, 2000 "stratified", feedback : %3d' % stream(MRG, gen_probes(2000, 'hand'), T, True))
    hp = gen_probes(1000, 'hand')
    print('   of the 1000 "stratified" probes, hand-transformed: %d; plain random: %d' %
          (1 + 6 * max(2, 1000 // 90) * 8, 1000 - 1 - 6 * max(2, 1000 // 90) * 8))

    print('\n2. probe seed varied (20 seeds), separate 4 quotients, no feedback: misses of %d, '
          'mean [min..max], seeds with zero (20 seeds up to n=3000, 6 at 10000)' % len(T))
    for kind in ('random', 'bucket', 'hand'):
        for n in (150, 300, 1000, 3000, 10000):
            ns = 20 if n <= 3000 else 6
            xs = [stream(SEP, gen_probes(n, kind, seed=sd), T) for sd in range(ns)]
            print('   %-7s n=%-6d %6.1f [%3d..%3d]  zero in %2d/%d' %
                  (kind, n, sum(xs) / ns, min(xs), max(xs), sum(1 for x in xs if x == 0), ns))

    print('\n3. 1000 "stratified" probes with one hand transform left out (20 probe seeds): mean misses')
    for d in TRANSFORMS[1:]:
        xs = [stream(SEP, gen_probes(1000, 'hand', seed=sd, drop=(d,)), T) for sd in range(20)]
        print('   without %-13s %6.1f [%3d..%3d]' % (d, sum(xs) / 20, min(xs), max(xs)))
    xs = [stream(SEP, gen_probes(1000, 'hand', seed=sd, drop=('constant', 'equal_prefix')), T)
          for sd in range(20)]
    print('   without constant and equal_prefix %6.1f [%3d..%3d]' % (sum(xs) / 20, min(xs), max(xs)))

    print('\n4. the structured row changed (1000 probes, 20 probe seeds): mean misses [min..max]')
    for nm, rows in (('reviewer\'s five rows', REVIEWER_ROWS), ('ten other structured rows', OTHER_ROWS),
                     ('no structured row', None)):
        Tx = gen_tasks(edge_rows=rows)
        for kind in ('random', 'bucket', 'hand'):
            xs = [stream(SEP, gen_probes(1000, kind, seed=sd), Tx) for sd in range(20)]
            print('   %-26s %-7s %6.1f [%3d..%3d] of %d' %
                  (nm, kind, sum(xs) / 20, min(xs), max(xs), len(Tx)))

    print('\n5. task seed varied (10 seeds), reviewer\'s rows, probe seed 11: misses')
    for kind, n in (('random', 150), ('hand', 1000), ('bucket', 1000)):
        xs = [stream(SEP, gen_probes(n, kind), gen_tasks(seed=900 + k)) for k in range(10)]
        print('   %-7s n=%-5d %s' % (kind, n, xs))

    print('\n6. merged product (len + nonneg x parity x order): mean misses [min..max]')
    for kind in ('random', 'hand'):
        for n in (2000, 10000, 50000):
            ns = 20 if n <= 2000 else (6 if n <= 10000 else 3)
            xs = [stream(MRG, gen_probes(n, kind, seed=sd), T) for sd in range(ns)]
            print('   %-7s n=%-6d %6.1f [%3d..%3d] (%d seeds)' % (kind, n, sum(xs) / ns, min(xs), max(xs), ns))

    print('\n7. the feedback rule: the reviewer\'s code also CREATES an entry for an unseen input label '
          '(one output only); variant that leaves unseen labels unseen')
    for n in (150,):
        p = gen_probes(n, 'random')
        print('   150 random: no feedback %d; feedback as coded %d; feedback without creating entries %d'
              % (stream(SEP, p, T), stream(SEP, p, T, True, True), stream(SEP, p, T, True, False)))


if __name__ == '__main__':
    main()
