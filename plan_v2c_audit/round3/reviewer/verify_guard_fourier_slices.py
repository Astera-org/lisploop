#!/usr/bin/env python3
"""
Quick empirical verification of three mathematical points from user questions:
  1. Boolean guard (x mod 3 == 0) vs 3-valued quotient (x mod 3) lumpability on {+, -, *, neg}.
  2. Greedy conditional-MI / MDL feature selection: does I(g(f(x)); g(x) | W(x)) automatically
     reject redundant guards (e.g. x < 1 after x < 0, x = 0) while keeping orthogonal words?
  3. Curried / inputs-held-constant isolation slices f(a, b_0) vs joint binary f(a, b):
     verifying when holding b fixed reveals true partial conservation vs false binary lumpability!
"""

import math
from collections import defaultdict, Counter

def H(counts):
    tot = sum(counts.values())
    if tot == 0: return 0.0
    return -sum((c/tot) * math.log2(c/tot) for c in counts.values() if c > 0)

def cond_H(xy_pairs):
    buckets = defaultdict(Counter)
    for x, y in xy_pairs:
        buckets[x][y] += 1
    tot = len(xy_pairs)
    return sum((sum(c.values())/tot) * H(c) for c in buckets.values())

def mi_and_lump(xy_pairs):
    h_y = H(Counter(y for _, y in xy_pairs))
    h_y_x = cond_H(xy_pairs)
    mi = max(0.0, h_y - h_y_x)
    lump = (mi / h_y) if h_y > 1e-9 else 0.0
    return mi, h_y_x, h_y, lump

vals = list(range(-12, 13))
pairs = [(a, b) for a in vals for b in vals]
ops = {
    '+':   lambda a, b: a + b,
    '-':   lambda a, b: a - b,
    '*':   lambda a, b: a * b,
    'max': lambda a, b: max(a, b),
    'div': lambda a, b: None if b == 0 else a // b,
    'mod': lambda a, b: None if b == 0 else a % b,
}

print("=" * 80)
print("CHECK 1: BOOLEAN MASK (x mod 3 == 0) vs 3-VALUED QUOTIENT (x mod 3)")
print("=" * 80)
for name, fn in [
    ('x mod 3 (3-valued)',        lambda x: x % 3),
    ('x mod 3 == 0 (Boolean)',    lambda x: (x % 3) == 0),
    ('x mod 5 (5-valued)',        lambda x: x % 5),
    ('x mod 5 == 0 (Boolean)',    lambda x: (x % 5) == 0),
    ('sign (-/0/+, 3-valued)',    lambda x: -1 if x < 0 else (1 if x > 0 else 0)),
    ('x < 0 (Boolean)',           lambda x: x < 0),
    ('x == 0 (Boolean)',          lambda x: x == 0),
    ('x mod 2 (Boolean)',         lambda x: x % 2),
]:
    row = []
    for oname in ('+', '-', '*', 'max'):
        op = ops[oname]
        obs = [((fn(a), fn(b)), fn(op(a, b))) for a, b in pairs]
        mi, hc, hy, lp = mi_and_lump(obs)
        row.append(f"{oname}:L={lp:.2f}(MI={mi:.2f},Hc={hc:.2f})")
    print(f"  {name:<24} | " + "  ".join(row))

print("\n" + "=" * 80)
print("CHECK 2: GREEDY CONDITIONAL MI SELECTION (REDUNDANCY REJECTION)")
print("=" * 80)
cands = {
    'x mod 2':   lambda x: x % 2,
    'x mod 3':   lambda x: x % 3,
    'x < 0':     lambda x: x < 0,
    'x == 0':    lambda x: x == 0,
    'x > 0':     lambda x: x > 0,
    'x < 1':     lambda x: x < 1,     # redundant once {x<0, x==0} chosen!
    'x < 2':     lambda x: x < 2,     # near-redundant with x<0!
    'x < -1':    lambda x: x < -1,    # near-redundant with x<0!
    'x == 5':    lambda x: x == 5,    # junk!
    'abs(x)<2':  lambda x: abs(x) < 2,
}
ring_ops = ['+', '-', '*', 'max']
selected = []

for step in range(5):
    best = None
    scores = []
    for cname, cfn in cands.items():
        if cname in selected: continue
        # Marginal predictive MI of cfn given already selected W:
        # I(g(f(a,b)) ; (g(a),g(b)) | W(a), W(b)) = H(g(f) | W(a),W(b)) - H(g(f) | W(a),W(b), g(a),g(b))
        # Also penalize residual conditional entropy H(g(f) | g(a), g(b)) (want lumpable features!)
        tot_cmi = 0.0
        tot_hc = 0.0
        tot_hy = 0.0
        for oname in ring_ops:
            op = ops[oname]
            obs_w = []
            obs_wg = []
            obs_g = []
            for a, b in pairs:
                wa = tuple(cands[w](a) for w in selected)
                wb = tuple(cands[w](b) for w in selected)
                ga, gb = cfn(a), cfn(b)
                go = cfn(op(a, b))
                obs_w.append(((wa, wb), go))
                obs_wg.append(((wa, wb, ga, gb), go))
                obs_g.append(((ga, gb), go))
            h_given_w = cond_H(obs_w)
            h_given_wg = cond_H(obs_wg)
            cmi = max(0.0, h_given_w - h_given_wg)
            _, hc_g, hy_g, _ = mi_and_lump(obs_g)
            tot_cmi += cmi
            tot_hc += hc_g
            tot_hy += hy_g
        avg_cmi = tot_cmi / len(ring_ops)
        avg_lump = 1.0 - (tot_hc / max(1e-9, tot_hy))
        # Normalized marginal gain: marginal MI * lumpability (rewards orthogonal + closed!)
        score = avg_cmi * avg_lump
        scores.append((score, avg_cmi, avg_lump, cname))
    scores.sort(reverse=True)
    top = scores[0]
    selected.append(top[3])
    runner = ", ".join(f"{nm}:{sc:.3f}(cMI={cm:.2f},L={lp:.2f})" for sc, cm, lp, nm in scores[:5])
    print(f"  Step {step+1} picked '{top[3]:<8}' | top5: {runner}")

print("\n" + "=" * 80)
print("CHECK 3: INPUTS-HELD-CONSTANT ISOLATION SLICES f(a, b_0) vs JOINT f(a, b)")
print("=" * 80)
for oname in ('+', '*', 'div', 'mod'):
    op = ops[oname]
    # Joint mod 2 lumpability
    j_obs = [((a % 2, b % 2), op(a, b) % 2) for a, b in pairs if op(a, b) is not None]
    _, _, _, j_lump = mi_and_lump(j_obs)
    slice_lumps = []
    for b0 in (1, 2, 3, 4):
        s_obs = [((a % 2,), op(a, b0) % 2) for a in vals if op(a, b0) is not None]
        _, _, _, sl = mi_and_lump(s_obs)
        slice_lumps.append(f"b={b0}:{sl:.2f}")
    print(f"  {oname:<4} on mod2 | Joint Lump={j_lump:.2f} | Curried slices: " + ", ".join(slice_lumps))
