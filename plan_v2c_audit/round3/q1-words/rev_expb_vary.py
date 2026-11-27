"""Perturbing the reviewer's EXP B (exp_devils_advocate.py lines 357-444), NOT an independent test:
the same 25 hand-written candidate lambdas (copied verbatim), the same operators
(make_61_library, unary seq->seq), the same scoring and the same greedy rule; what varies is
what the reviewer fixed: the probe seed, the 24 hand-added "stratified" probes (all-even,
all-non-negative, sorted, reverse-sorted lists), and the NMI threshold.

usage: python3 rev_expb_vary.py > rev_expb_vary.log
"""
import math
import random
import sys
from collections import Counter, defaultdict

sys.dont_write_bytecode = True
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library


def H(counts):
    tot = sum(counts.values())
    return -sum((c / tot) * math.log2(c / tot) for c in counts.values() if c > 0) if tot else 0.0


def cond_H(pairs):
    b = defaultdict(Counter)
    for x, y in pairs:
        b[x][y] += 1
    tot = len(pairs)
    return sum((sum(c.values()) / tot) * H(c) for c in b.values())


def pair_nmi(xs, ys):
    hx, hy = H(Counter(xs)), H(Counter(ys))
    if hx < 1e-9 or hy < 1e-9:
        return 0.0
    return max(0.0, hy - cond_H(list(zip(xs, ys)))) / min(hx, hy)


# the reviewer's pool, verbatim (exp_devils_advocate.py lines 376-401)
seq_cands = {
    'const_0 (VACUOUS)':   lambda s: 0,
    'len>=0 (VACUOUS)':    lambda s: len(s) >= 0,
    'len_cap6':            lambda s: min(len(s), 6),
    'len_cap5':            lambda s: min(len(s), 5),
    'len_cap4':            lambda s: min(len(s), 4),
    'len_cap3':            lambda s: min(len(s), 3),
    'len_mod2':            lambda s: len(s) % 2,
    'len_mod3':            lambda s: len(s) % 3,
    'len>0 (is_nonempty)': lambda s: len(s) > 0,
    'len>1':               lambda s: len(s) > 1,
    'len>2':               lambda s: len(s) > 2,
    'len>3':               lambda s: len(s) > 3,
    'all_nonneg':          lambda s: 'E' if not s else ('P' if all(x>0 for x in s) else ('N0' if all(x>=0 for x in s) else ('NEG' if all(x<0 for x in s) else 'M'))),
    'all_even':            lambda s: 'E' if not s else ('EV' if all(x%2==0 for x in s) else ('OD' if all(x%2!=0 for x in s) else 'M')),
    'is_sorted':           lambda s: 'S01' if len(s)<=1 else ('C' if len(set(s))==1 else ('ASC' if all(s[i]<=s[i+1] for i in range(len(s)-1)) else ('DSC' if all(s[i]>=s[i+1] for i in range(len(s)-1)) else 'U'))),
    'sum_mod2':            lambda s: 'E' if not s else (sum(s) % 2),
    'sum_sign':            lambda s: 0 if sum(s)==0 else (1 if sum(s)>0 else -1),
    'has_zero':            lambda s: 0 in s,
    'min_ge_0':            lambda s: (min(s) >= 0) if s else True,
    'max_le_2 (junk)':     lambda s: (max(s) <= 2) if s else True,
    'head_eq_1 (junk)':    lambda s: (s[0] == 1) if s else False,
    'head_even (junk)':    lambda s: (s[0] % 2 == 0) if s else None,
    'sum_gt_5 (junk)':     lambda s: sum(s) > 5,
    'len_eq_3 (junk)':     lambda s: len(s) == 3,
}
ops = make_61_library()
u_seq_ops = [k for k, (at, rt, _) in ops.items() if at == ('seq',) and rt == 'seq']
print('pool: %d hand-written lambdas; scored on %d unary seq->seq operators' % (len(seq_cands), len(u_seq_ops)))
print('cardinalities of the "content" words on the reviewer\'s probes: all_nonneg 5 labels (E/P/N0/NEG/M), '
      'all_even 4 (E/EV/OD/M), is_sorted 5 (S01/C/ASC/DSC/U)')


def run(seed, stratified, cap, n=400, vmax=5, floor=0.1):
    rng = random.Random(seed)
    probe_seqs = [()] + [tuple(rng.randint(-vmax, vmax) for _ in range(rng.randint(1, 7))) for _ in range(n)]
    if stratified:
        for Ln in range(1, 7):
            probe_seqs += [
                tuple(2 * rng.randint(-3, 3) for _ in range(Ln)),
                tuple(rng.randint(0, 6) for _ in range(Ln)),
                tuple(sorted(rng.randint(-5, 5) for _ in range(Ln))),
                tuple(sorted((rng.randint(-5, 5) for _ in range(Ln)), reverse=True)),
            ]
    probe_seqs = list(dict.fromkeys(probe_seqs))
    base = {nm: [fn(s) for s in probe_seqs] for nm, fn in seq_cands.items()}
    st = {}
    for nm, fn in seq_cands.items():
        g = []
        for opk in u_seq_ops:
            opfn = ops[opk][2]
            obs = []
            for s in probe_seqs:
                o = opfn(s)
                if o is not None:
                    obs.append((fn(s), fn(o)))
            hy = H(Counter(y for _, y in obs))
            hc = cond_H(obs)
            g.append((1.0 - hc / hy) if hy > 0.05 else 0.0)
        st[nm] = sum(g) / len(g)
    m3 = []
    for k in sorted(seq_cands, key=lambda k: -st[k]):
        if st[k] < floor:
            continue
        if all(pair_nmi(base[k], base[p]) < cap for p in m3):
            m3.append(k)
        if len(m3) == 6:
            break
    return m3, st


m3, st = run(303, True, 0.65)
print('\nreviewer\'s setting (seed 303, stratified probes, NMI < 0.65):')
print('   selected:', m3)
print('   scores of all 24, best first (the script comment says 25; the dict has 24):')
for k in sorted(st, key=lambda k: -st[k]):
    print('      %.3f  %s%s' % (st[k], k, '   <- selected' if k in m3 else ''))

print('\nvarying what the reviewer fixed (selected six, in order):')
for (seed, strat, cap) in [(303, True, 0.5), (303, True, 0.8), (303, False, 0.65),
                           (1, True, 0.65), (2, True, 0.65), (3, True, 0.65), (4, True, 0.65),
                           (1, False, 0.65), (2, False, 0.65), (3, False, 0.65), (4, False, 0.65),
                           (1, False, 0.5), (1, False, 0.8)]:
    m, _ = run(seed, strat, cap)
    print('   seed %3d  stratified probes %-5s  NMI < %.2f : %s' % (seed, strat, cap, m))

print('\nhow often each candidate is selected over seeds 1..20 (NMI < 0.65):')
for strat in (True, False):
    cnt = Counter()
    for seed in range(1, 21):
        m, _ = run(seed, strat, 0.65)
        cnt.update(m)
    print('   stratified probes %-5s: %s' % (strat, ', '.join('%s %d' % kv for kv in cnt.most_common())))
