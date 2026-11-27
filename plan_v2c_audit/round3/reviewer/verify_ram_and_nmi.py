#!/usr/bin/env python3
"""
Quick 3-second verification of two sharp points from Exp A1 & Exp B:
  1. Monotonicity RAM theorem: checking `can_reach(out, s)` BEFORE `seen` insertion at ALL
     layers `s` is 100% sound (since S - s' <= S - s < h_bwd for all s' >= s!) and makes
     TRUE total RAM (len(seen)) == len(bank) -> true 9.4x - 22.9x RAM savings on G1!
  2. Exp B with final-layer pre-filtering (plan_v2c §8.8's main mechanism):
     compare 6 length variants (no redundancy) vs 5-line pairwise NMI < 0.65 (diverse words)!
"""

import random
from collections import defaultdict, Counter
import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library

# --- PART 1: Verify Check-Before-Seen Monotonicity Theorem on G1 ---
rows = [(0, 1), (1, -1), (-1, 0), (2, 3), (-2, 1), (3, -2),
        (1, 2), (-3, 2), (4, -1), (2, -3), (-1, 4), (3, 1)]
n = len(rows)
inps = [('x', tuple(r[0] for r in rows)), ('y', tuple(r[1] for r in rows)),
        ('0', (0,)*n), ('1', (1,)*n)]
ops_fn = {'+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b}

def g1_check_before_seen(tgt, max_ops, use_hom):
    hom_h = []
    if use_hom:
        specs = [(2, tuple(range(n))), (3, (0,1,2,3)), (3, (4,5,6,7)), (5, (0,1,2)), (5, (3,4,5))]
        for p, ridxs in specs:
            proj = (lambda col, p=p, ridxs=ridxs: tuple(col[i] % p for i in ridxs))
            def ap(opn, a, b=None, p=p):
                if opn == 'neg': return tuple((-x)%p for x in a)
                if opn == '+':   return tuple((x+y)%p for x, y in zip(a, b))
                if opn == '-':   return tuple((x-y)%p for x, y in zip(a, b))
                if opn == '*':   return tuple((x*y)%p for x, y in zip(a, b))
            g_fwd = {}; layers = defaultdict(list)
            for _, col in inps:
                a = proj(col)
                if a not in g_fwd: g_fwd[a] = 0; layers[0].append(a)
            for s in range(1, max_ops):
                for a in layers[s-1]:
                    o = ap('neg', a)
                    if o not in g_fwd: g_fwd[o] = s; layers[s].append(o)
                for s1 in range(s):
                    s2 = s - 1 - s1
                    for a in layers[s1]:
                        for b in layers[s2]:
                            for opn in ('+', '-', '*'):
                                if opn in ('+', '*') and s1 > s2: continue
                                o = ap(opn, a, b)
                                if o not in g_fwd: g_fwd[o] = s; layers[s].append(o)
            tgt_a = proj(tgt); INF = 999
            h_bwd = defaultdict(lambda: INF); h_bwd[tgt_a] = 0
            reach = list(g_fwd.items())
            mul_e = [(a,ga,b,gb,ap('*',a,b)) for i,(a,ga) in enumerate(reach)
                     for j in range(i,len(reach)) for b,gb in [reach[j]] if ga+gb+1 <= max_ops]
            for _ in range(max_ops):
                ch = False
                for o, hv in [(o,hv) for o,hv in list(h_bwd.items()) if hv < max_ops]:
                    a = ap('neg', o)
                    if a in g_fwd and hv+1 < h_bwd[a]: h_bwd[a] = hv+1; ch = True
                    for b, gb in reach:
                        c = 1 + gb + hv
                        if c > max_ops: continue
                        for a_c in (ap('-',o,b), ap('+',o,b), ap('-',b,o)):
                            if a_c in g_fwd and c < h_bwd[a_c]: h_bwd[a_c] = c; ch = True
                for a,ga,b,gb,o in mul_e:
                    hv = h_bwd[o]
                    if hv < INF:
                        if 1+gb+hv < h_bwd[a]: h_bwd[a] = 1+gb+hv; ch = True
                        if 1+ga+hv < h_bwd[b]: h_bwd[b] = 1+ga+hv; ch = True
                if not ch: break
            hom_h.append((proj, h_bwd))

    by = defaultdict(list); seen = set(); cands = 0
    def can_reach(col, s):
        if not hom_h: return True
        rem = max_ops - s
        return all(hb[proj(col)] <= rem for proj, hb in hom_h)

    for nm, col in inps:
        if can_reach(col, 0) and col not in seen:
            seen.add(col); by[0].append((nm, col))

    for s in range(1, max_ops + 1):
        is_final = (s == max_ops)
        def handle(term, out):
            if out == tgt: return True
            if is_final: return False
            # MONOTONICITY THEOREM: check can_reach BEFORE seen! Never store pruned columns in seen!
            if not can_reach(out, s): return False
            if out not in seen:
                seen.add(out); by[s].append((term, out))
            return False

        for t1, c1 in by[s-1]:
            cands += 1
            if handle(('neg', t1), tuple(-v for v in c1)): return True, cands, len(seen), sum(len(v) for v in by.values())
        for s1 in range(s):
            s2 = s - 1 - s1
            l1, l2 = by[s1], by[s2]
            if not l1 or not l2: continue
            for opn, fn in ops_fn.items():
                comm = opn in ('+', '*')
                if comm and s1 > s2: continue
                for i1, (t1, c1) in enumerate(l1):
                    st2 = i1 if (comm and s1 == s2) else 0
                    for i2 in range(st2, len(l2)):
                        t2, c2 = l2[i2]
                        cands += 1
                        if handle((opn, t1, t2), tuple(fn(c1[r], c2[r]) for r in range(n))):
                            return True, cands, len(seen), sum(len(v) for v in by.values())
    return False, cands, len(seen), sum(len(v) for v in by.values())

print("VERIFY PART 1: CHECK-BEFORE-SEEN MONOTONICITY THEOREM ON G1 (TRUE RAM = len(seen) == len(bank)!)")
for nm, fn, mo in [
    ("A4 (sz9): (x+y)*(x-y)+1",   lambda x,y: (x+y)*(x-y)+1, 4),
    ("A8 (sz11): (x+y)^2-xy+1",   lambda x,y: (x+y)*(x+y)-x*y+1, 5),
    ("A12 (sz13): 2(x^2+y^2)-xy", lambda x,y: 2*(x*x+y*y)-x*y, 6),
]:
    tgt = tuple(fn(x, y) for x, y in rows)
    ok0, c0, s0, b0 = g1_check_before_seen(tgt, mo, False)
    ok1, c1, s1, b1 = g1_check_before_seen(tgt, mo, True)
    print(f"  {nm:<28} | Plain seen={s0:>5}, bank={b0:>5} | CheckBeforeSeen found={ok1} seen={s1:>4}, bank={b1:>4} | TRUE RAM Gain={s0/max(1,s1):>5.1f}x")

# --- PART 2: Exp B with FINAL-LAYER PRE-FILTERING (plan_v2c §8.8 mechanism) ---
print("\nVERIFY PART 2: EXP B REDUNDANCY ABLATION WITH FINAL-LAYER PRE-FILTERING (§8.8)")
ops = make_61_library()
u_seq = {k: v for k, v in ops.items() if v[0] == ('seq',) and v[1] == 'seq'}
rng = random.Random(303)
probes = [()]
for L in range(1, 7):
    for _ in range(12):
        s = tuple(rng.randint(-5, 5) for _ in range(L))
        probes.extend([s, tuple(sorted(s)), tuple(sorted(s, reverse=True)),
                       tuple(abs(x) for x in s), tuple(2*x for x in s), tuple(2*x+1 for x in s), (s[0],)*L])
probes = list(dict.fromkeys(probes))

word_fns = {
    'len_cap6':   lambda s: min(len(s), 6),
    'len_cap5':   lambda s: min(len(s), 5),
    'len_cap4':   lambda s: min(len(s), 4),
    'len_mod3':   lambda s: len(s) % 3,
    'len_cap3':   lambda s: min(len(s), 3),
    'len_mod2':   lambda s: len(s) % 2,
    'all_even':   lambda s: 'E' if not s else ('EV' if all(x%2==0 for x in s) else ('OD' if all(x%2!=0 for x in s) else 'M')),
    'all_nonneg': lambda s: 'E' if not s else ('P' if all(x>0 for x in s) else ('N0' if all(x>=0 for x in s) else ('NEG' if all(x<0 for x in s) else 'M'))),
    'is_sorted':  lambda s: 'S01' if len(s)<=1 else ('C' if len(set(s))==1 else ('ASC' if all(s[i]<=s[i+1] for i in range(len(s)-1)) else ('DSC' if all(s[i]>=s[i+1] for i in range(len(s)-1)) else 'U'))),
    'max_le_2':   lambda s: (max(s) <= 2) if s else True,
    'has_zero':   lambda s: 0 in s,
}

xs_rows = ((3,-1,4,2), (-2,5,0,-3,1), (2,4,6), (1,-2,3,-4,5,0), (7,1), (0,-1,2,3))
def eval_p(p, xs):
    if p == 'xs': return xs
    return u_seq[p[0]][2](eval_p(p[1], xs))

bench = [
    ('dbl_all', ('sort', ('abs_all', 'xs'))),
    ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),
    ('running_sum', ('reverse', ('inc_all', 'xs'))),
    ('sort', ('dbl_all', ('filter_pos', 'xs'))),
    ('sort_desc', ('abs_all', ('map_adj_sub', 'xs'))),
    ('dbl_all', ('filter_even', ('inc_all', 'xs'))),
    ('sort', ('filter_pos', ('inc_all', 'xs'))),
    ('abs_all', ('reverse', ('sort', 'xs'))),
]

def run_prefilt(wlist, label):
    # Learn verb tables for wlist
    vt = {w: {} for w in wlist}
    for w in wlist:
        wf = word_fns[w]
        for ok, (_, _, fn) in u_seq.items():
            tr = defaultdict(set)
            for s in probes:
                o = fn(s)
                if o is not None: tr[wf(s)].add(wf(o))
            vt[w][ok] = tr

    tot_eval = 0; tot_ram = 0; solved = 0
    for prog in bench:
        tgt = tuple(eval_p(prog, x) for x in xs_rows)
        tgt_l = {w: [word_fns[w](y) for y in tgt] for w in wlist}
        # 1-step pre-filter at s==3 (final layer) + 1-step backward check at s==2 (penultimate layer, check-before-seen!)
        # Build 1-step backward reachable set per (w, row): states that can hit tgt_l[w][r] in 1 op!
        bwd1 = {w: [set() for _ in range(len(xs_rows))] for w in wlist}
        for w in wlist:
            for r in range(len(xs_rows)):
                tg = tgt_l[w][r]
                for ok, tr in vt[w].items():
                    for ain, aouts in tr.items():
                        if tg in aouts: bwd1[w][r].add(ain)

        by = defaultdict(list); seen = set(); ev = 0; found = False
        seen.add(xs_rows); by[0].append(('xs', xs_rows, {w: [word_fns[w](x) for x in xs_rows] for w in wlist}))
        for s in (1, 2, 3):
            for ok, (_, _, fn) in u_seq.items():
                for t1, c1, a1 in by[s - 1]:
                    if s == 3 and wlist:
                        # Pre-filter BEFORE evaluating!
                        ok_l = True
                        for w in wlist:
                            tr = vt[w][ok]; la = a1[w]; lt = tgt_l[w]
                            for r in range(len(xs_rows)):
                                outs = tr.get(la[r])
                                if outs is not None and lt[r] not in outs:
                                    ok_l = False; break
                            if not ok_l: break
                        if not ok_l: continue
                    ev += 1
                    out = []
                    ok_v = True
                    for x in c1:
                        v = fn(x)
                        if v is None: ok_v = False; break
                        out.append(v)
                    if not ok_v: continue
                    out_t = tuple(out)
                    if out_t == tgt:
                        found = True; break
                    if s < 3:
                        lbl = {w: [word_fns[w](v) for v in out_t] for w in wlist}
                        if s == 2 and wlist:
                            # Check-before-seen 1-step lookahead at penultimate layer!
                            if any(lbl[w][r] not in bwd1[w][r] for w in wlist for r in range(len(xs_rows))):
                                continue
                        if out_t not in seen:
                            seen.add(out_t); by[s].append(((ok, t1), out_t, lbl))
                if found: break
            if found: break
        tot_eval += ev; tot_ram += len(seen); solved += int(found)
    print(f"  {label:<44} | solved={solved}/8 | Evals={tot_eval:>6} | TRUE RAM(seen)={tot_ram:>5}")

run_prefilt([], "[0] Plain OE (no words)")
run_prefilt(['len_cap6','len_cap5','len_cap4','len_mod3','len_cap3','len_mod2'], "[2] No redundancy (6 length variants!)")
run_prefilt(['len_cap6','all_even','all_nonneg','is_sorted','max_le_2','has_zero'], "[3] 5-line pairwise NMI < 0.65 (diverse!)")
