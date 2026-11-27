#!/usr/bin/env python3
"""
Devil's Advocate Probe Experiments:
  Exp A: TRUE RAM accounting (seen + bank, and dropping seen on pruned penultimate nodes)
         on (A1) G1 polynomials and (A2) tg-probe-style lifted position-space tasks
         (reverse, shift-seq, rotate-left, map-adjacent +, map-adjacent -)!
  Exp B: Is Gap 3 needed? Ablating vacuity guard, redundancy rule (none vs cheap 5-line
         pairwise NMI vs full joint conditional MI), and automatic cross-type scoring
         over an enumerated word pool on the 61-op library.
  Exp C: Is Gap 4 needed? Joint probing vs Rule-3 Isolate slices (f(., b0)) on G2 arithmetic.
  Exp D: Is Gap 5 needed? 100-task stream comparing 150-probe static vs 150-probe + 5-line
         online fallback feedback vs 1000-probe stratified vs merged-product + feedback.
"""

import math
import random
import time
from collections import defaultdict, Counter

import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library, build_abstract_domains, knuth_bounds, synthesize_oe

def H(counts):
    tot = sum(counts.values())
    if tot == 0: return 0.0
    return -sum((c/tot) * math.log2(c/tot) for c in counts.values() if c > 0)

def cond_H(pairs):
    b = defaultdict(Counter)
    for x, y in pairs: b[x][y] += 1
    tot = len(pairs)
    return sum((sum(c.values())/tot) * H(c) for c in b.values())

def lump_score(pairs):
    hy = H(Counter(y for _, y in pairs))
    if hy < 1e-9: return 0.0, 0.0, 0.0
    hc = cond_H(pairs)
    return 1.0 - hc/hy, hy - hc, hy

def pair_nmi(xs, ys):
    hx = H(Counter(xs))
    hy = H(Counter(ys))
    if hx < 1e-9 or hy < 1e-9: return 0.0
    mi = max(0.0, hy - cond_H(list(zip(xs, ys))))
    return mi / min(hx, hy)

def canon_part(vals):
    m = {}
    out = []
    for v in vals:
        if v not in m: m[v] = len(m)
        out.append(m[v])
    return tuple(out)


# ==============================================================================
# EXP A: TRUE MEMORY ACCOUNTING (SEEN + BANK) ON G1 AND LIFTED TG-PROBE TASKS
# ==============================================================================

def run_exp_a():
    print("=" * 88)
    print("EXP A1: TRUE RAM ACCOUNTING (TOTAL seen + bank) ON G1 POLYNOMIALS (SIZE 9, 11, 13)")
    print("=" * 88)
    rows = [(0, 1), (1, -1), (-1, 0), (2, 3), (-2, 1), (3, -2),
            (1, 2), (-3, 2), (4, -1), (2, -3), (-1, 4), (3, 1)]
    n = len(rows)
    inps = [('x', tuple(r[0] for r in rows)), ('y', tuple(r[1] for r in rows)),
            ('0', (0,)*n), ('1', (1,)*n)]
    ops_fn = {'+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b}

    def run_g1(tgt, max_ops, mode):
        """
        mode='plain': standard OE (stores seen + bank for s < max_ops)
        mode='hom_keep_seen': h_bwd prunes bank, still stores pruned columns in seen
        mode='hom_drop_penult_seen': h_bwd prunes bank AND never inserts pruned s==max_ops-1
              columns into seen (since s==max_ops never checks seen!)
        """
        hom_h = []
        if mode != 'plain':
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

        by = defaultdict(list)
        seen = set()
        seen_penult = set()  # only for surviving penultimate classes!
        cands = 0

        def can_reach(col, s):
            if not hom_h: return True
            rem = max_ops - s
            return all(hb[proj(col)] <= rem for proj, hb in hom_h)

        for nm, col in inps:
            seen.add(col)
            if can_reach(col, 0): by[0].append((nm, col))

        for s in range(1, max_ops + 1):
            is_final = (s == max_ops)
            is_penult = (s == max_ops - 1)
            def handle(term, out):
                nonlocal cands
                if out == tgt: return True
                if is_final: return False
                if mode == 'hom_drop_penult_seen' and is_penult:
                    # Check h_bwd BEFORE touching seen! Pruned classes consume ZERO bytes of RAM!
                    if not can_reach(out, s):
                        return False
                    if out not in seen and out not in seen_penult:
                        seen_penult.add(out)
                        by[s].append((term, out))
                    return False
                if out not in seen:
                    seen.add(out)
                    if can_reach(out, s):
                        by[s].append((term, out))
                return False

            for t1, c1 in by[s-1]:
                cands += 1
                if handle(('neg', t1), tuple(-v for v in c1)):
                    return cands, len(seen) + len(seen_penult), sum(len(v) for v in by.values())
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
                                return cands, len(seen) + len(seen_penult), sum(len(v) for v in by.values())
        return cands, len(seen) + len(seen_penult), sum(len(v) for v in by.values())

    print(f"{'Task':<34} | {'Plain seen / bank':>18} | {'KeepSeen seen / bank':>21} | {'DropPenSeen seen / bank':>24} | {'TRUE RAM Gain':>13}")
    print("-" * 124)
    for nm, fn, mo in [
        ("A4 (sz9): (x+y)*(x-y)+1",       lambda x,y: (x+y)*(x-y)+1, 4),
        ("A8 (sz11): (x+y)^2-xy+1",       lambda x,y: (x+y)*(x+y)-x*y+1, 5),
        ("A12 (sz13): 2(x^2+y^2)-xy",     lambda x,y: 2*(x*x+y*y)-x*y, 6),
    ]:
        tgt = tuple(fn(x, y) for x, y in rows)
        _, ps, pb = run_g1(tgt, mo, 'plain')
        _, ks, kb = run_g1(tgt, mo, 'hom_keep_seen')
        _, ds, db = run_g1(tgt, mo, 'hom_drop_penult_seen')
        print(f"{nm:<34} | {ps:>8} / {pb:<7} | {ks:>9} / {kb:<9} | {ds:>10} / {db:<11} | {ps/max(1,ds):>12.1f}x")

    # EXP A2: Lifted position-space arithmetic tasks (tg-probe style: §6.7 open question!)
    print("\n" + "=" * 88)
    print("EXP A2: DO QUOTIENTS SAVE RAM INSIDE LIFTED POSITION-SPACE TASKS (§6.7 OPEN QUESTION)?")
    print("=" * 88)
    # Build lifted position space S' for 6 random sequences (lengths 3..6 -> 27 lifted rows!)
    rng = random.Random(77)
    raw_seqs = [tuple(rng.randint(-5, 6) for _ in range(L)) for L in (4, 5, 3, 6, 4, 5)]
    # Task 1: map-adjacent (+): target[r, i] = xs[i] + xs[i+1], over S' (21 lifted rows)
    # Task 2: map-adjacent (-): target[r, i] = xs[i+1] - xs[i]
    # Task 3: reverse: target[r, i] = xs[len(xs) - 1 - i], over S' (27 lifted rows)
    # Task 4: rotate-left by k: target[r, i] = xs[(i + k) % len(xs)], k in (1,2,1,3,2,1)
    ks = (1, 2, 1, 3, 2, 1)

    def test_lifted_task(tname, make_rows_fn, max_ops):
        # Grammar matching tg-probe: +, -, *, mod, max, min, at (indexing into xs!)
        # Leaves on S': i, len_xs, k (if used), 0, 1, plus sequence ref xs
        r_i, r_len, r_k, r_xs, r_tgt = make_rows_fn()
        m = len(r_tgt)
        # Note: 'at' takes (xs, idx_col) -> int_col (fails if idx < 0 or idx >= len)
        def eval_at(idx_col):
            out = []
            for r in range(m):
                ix = idx_col[r]
                if ix < 0 or ix >= r_len[r]: return None
                out.append(r_xs[r][ix])
            return tuple(out)

        int_leaves = [('i', r_i), ('len', r_len), ('0', (0,)*m), ('1', (1,)*m)]
        if r_k is not None:
            int_leaves.append(('k', r_k))

        # Check (1) Plain mixed grammar {+, -, *, mod, max, min, at}
        #       (2) Verb-table 1-step pre-filter (mod2, mod3, sign learned on 1,000 probes)
        #       (3) Tentative G1+at ring pass? (No: at is NOT a ring op on its index! Only outer +,-,* are!)
        # Learn 1-step verb tables for {+, -, *, mod, max, min} on mod2, mod3, sign
        probe = list(range(-12, 13))
        doms = {
            'mod2': lambda v: v % 2,
            'mod3': lambda v: v % 3,
            'sign': lambda v: -1 if v < 0 else (1 if v > 0 else 0),
        }
        arith_bin = {
            '+': lambda a, b: a + b,
            '-': lambda a, b: a - b,
            '*': lambda a, b: a * b,
            'max': lambda a, b: max(a, b),
            'min': lambda a, b: min(a, b),
            'mod': lambda a, b: None if b <= 0 else a % b,
        }
        vtbl = {}
        for dn, dfn in doms.items():
            vtbl[dn] = {}
            for opn, fn in arith_bin.items():
                tr = defaultdict(set)
                for a in probe:
                    for b in probe:
                        o = fn(a, b)
                        if o is not None:
                            tr[(dfn(a), dfn(b))].add(dfn(o))
                vtbl[dn][opn] = tr

        # Run Plain vs Pre-filtered final layer (skipping binary eval if labels cannot match tgt on first 6 rows!)
        check_r = list(range(min(6, m)))
        tgt_abs = {dn: [dfn(r_tgt[r]) for r in check_r] for dn, dfn in doms.items()}

        def run_lift(use_prefilter):
            by = defaultdict(list)  # list of (term, col, abs_cache)
            seen = set()
            cands_eval = 0
            cands_skip = 0
            def mk_abs(col):
                return {dn: [dfn(col[r]) for r in check_r] for dn, dfn in doms.items()}
            for nm, col in int_leaves:
                if col == r_tgt: return nm, 0, 0, len(seen)
                if col not in seen:
                    seen.add(col); by[0].append((nm, col, mk_abs(col)))
            for s in range(1, max_ops + 1):
                is_final = (s == max_ops)
                # Unary 'at xs idx' (cost +1 op)
                for t1, c1, _ in by[s - 1]:
                    cands_eval += 1
                    out = eval_at(c1)
                    if out is None: continue
                    if out == r_tgt: return ('at', 'xs', t1), cands_eval, cands_skip, len(seen)
                    if not is_final and out not in seen:
                        seen.add(out); by[s].append((('at', 'xs', t1), out, mk_abs(out)))
                # Binary arithmetic ops
                for s1 in range(s):
                    s2 = s - 1 - s1
                    l1, l2 = by[s1], by[s2]
                    if not l1 or not l2: continue
                    for opn, fn in arith_bin.items():
                        comm = opn in ('+', '*', 'max', 'min')
                        if comm and s1 > s2: continue
                        for i1, (t1, c1, a1) in enumerate(l1):
                            st2 = i1 if (comm and s1 == s2) else 0
                            for i2 in range(st2, len(l2)):
                                t2, c2, a2 = l2[i2]
                                if is_final and use_prefilter:
                                    ok_lbl = True
                                    for dn in doms:
                                        tr = vtbl[dn][opn]
                                        l_a1, l_a2, l_tg = a1[dn], a2[dn], tgt_abs[dn]
                                        for idx_r in range(len(check_r)):
                                            outs = tr.get((l_a1[idx_r], l_a2[idx_r]))
                                            if outs is not None and l_tg[idx_r] not in outs:
                                                ok_lbl = False; break
                                        if not ok_lbl: break
                                    if not ok_lbl:
                                        cands_skip += 1
                                        continue
                                cands_eval += 1
                                out = []
                                ok = True
                                for r in range(m):
                                    v = fn(c1[r], c2[r])
                                    if v is None: ok = False; break
                                    out.append(v)
                                if not ok: continue
                                out_t = tuple(out)
                                if out_t == r_tgt:
                                    return (opn, t1, t2), cands_eval, cands_skip, len(seen)
                                if not is_final and out_t not in seen:
                                    seen.add(out_t); by[s].append(((opn, t1, t2), out_t, mk_abs(out_t)))
            return None, cands_eval, cands_skip, len(seen)

        r0, e0, _, ram0 = run_lift(False)
        r1, e1, sk1, ram1 = run_lift(True)
        print(f"  {tname:<24} | Plain eval={e0:>7} RAM={ram0:>5} | Prefilt eval={e1:>7} (skip={sk1:>6}) RAM={ram1:>5} | EvalGain={e0/max(1,e1):>5.1f}x RAMGain={ram0/max(1,ram1):>4.1f}x | found={r1}")

    def mk_map_adj(op_fn):
        ri, rl, rxs, rt = [], [], [], []
        for s in raw_seqs:
            for i in range(len(s) - 1):
                ri.append(i); rl.append(len(s)); rxs.append(s); rt.append(op_fn(s[i], s[i+1]))
        return tuple(ri), tuple(rl), None, rxs, tuple(rt)

    def mk_reverse():
        ri, rl, rxs, rt = [], [], [], []
        for s in raw_seqs:
            for i in range(len(s)):
                ri.append(i); rl.append(len(s)); rxs.append(s); rt.append(s[len(s)-1-i])
        return tuple(ri), tuple(rl), None, rxs, tuple(rt)

    def mk_rotate():
        ri, rl, rk, rxs, rt = [], [], [], [], []
        for s, k in zip(raw_seqs, ks):
            for i in range(len(s)):
                ri.append(i); rl.append(len(s)); rk.append(k); rxs.append(s); rt.append(s[(i+k)%len(s)])
        return tuple(ri), tuple(rl), tuple(rk), rxs, tuple(rt)

    test_lifted_task("map-adjacent (+) [4ops]", lambda: mk_map_adj(lambda a,b: a+b), 4)
    test_lifted_task("map-adjacent (-) [4ops]", lambda: mk_map_adj(lambda a,b: b-a), 4)
    test_lifted_task("reverse [3ops]",          mk_reverse, 3)
    test_lifted_task("rotate-left [3ops]",      mk_rotate, 3)


# ==============================================================================
# EXP B: IS GAP 3 ACTUALLY NEEDED? (ABLATING REDUNDANCY, VACUITY, CROSS-TYPE)
# ==============================================================================

def run_exp_b():
    print("\n" + "=" * 88)
    print("EXP B: IS GAP 3 NEEDED? (ABLATING VACUITY, REDUNDANCY, AND CROSS-TYPE SCORING)")
    print("=" * 88)
    ops = make_61_library()
    rng = random.Random(303)
    probe_seqs = [()] + [tuple(rng.randint(-5, 5) for _ in range(rng.randint(1, 7))) for _ in range(400)]
    # Add stratified buckets so real properties have clean support
    for L in range(1, 7):
        probe_seqs += [
            tuple(2*rng.randint(-3, 3) for _ in range(L)),
            tuple(rng.randint(0, 6) for _ in range(L)),
            tuple(sorted(rng.randint(-5, 5) for _ in range(L))),
            tuple(sorted((rng.randint(-5, 5) for _ in range(L)), reverse=True)),
        ]
    probe_seqs = list(dict.fromkeys(probe_seqs))

    # Realistic enumerated pool of 25 candidate sequence quotients:
    # 10 length variants + 2 vacuous constants + 8 real content words + 5 junk words!
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
    int_cands = {
        'int_sign': lambda x: -1 if x < 0 else (1 if x > 0 else 0),
        'int_mod2': lambda x: x % 2,
        'int_mod3': lambda x: x % 3,
    }

    u_seq_ops = [k for k, (at, rt, _) in ops.items() if at == ('seq',) and rt == 'seq']
    s2i_ops   = [k for k, (at, rt, _) in ops.items() if at == ('seq',) and rt == 'int']

    # Score every seq_cand across u_seq_ops
    base_vals = {nm: [fn(s) for s in probe_seqs] for nm, fn in seq_cands.items()}
    cand_stats = {}
    for nm, fn in seq_cands.items():
        lumps_naive = []
        lumps_guarded = []
        for opk in u_seq_ops:
            opfn = ops[opk][2]
            obs = []
            for s in probe_seqs:
                o = opfn(s)
                if o is not None: obs.append((fn(s), fn(o)))
            hy = H(Counter(y for _, y in obs))
            hc = cond_H(obs)
            # Naive bug: treat hc==0 as 1.0 even when hy==0!
            lumps_naive.append(1.0 if hc < 1e-9 else (1.0 - hc/hy))
            lumps_guarded.append((1.0 - hc/hy) if hy > 0.05 else 0.0)
        cand_stats[nm] = (sum(lumps_naive)/len(lumps_naive), sum(lumps_guarded)/len(lumps_guarded))

    # Mode 1: Naive (no vacuity guard, no redundancy)
    m1 = sorted(seq_cands.keys(), key=lambda k: -cand_stats[k][0])[:6]
    # Mode 2: Vacuity guard ONLY (no redundancy)
    m2 = sorted(seq_cands.keys(), key=lambda k: -cand_stats[k][1])[:6]
    # Mode 3: Vacuity guard + CHEAP 5-line pairwise NMI redundancy filter (NMI < 0.65!)
    m3 = []
    for k in sorted(seq_cands.keys(), key=lambda k: -cand_stats[k][1]):
        if cand_stats[k][1] < 0.1: continue
        if all(pair_nmi(base_vals[k], base_vals[prev]) < 0.65 for prev in m3):
            m3.append(k)
        if len(m3) == 6: break

    print(f"  [1] Naive (no vacuity, no redundancy)       -> {m1}")
    print(f"  [2] Vacuity guard ONLY (no redundancy)      -> {m2}")
    print(f"  [3] Vacuity + 5-line pairwise NMI < 0.65    -> {m3}")

    # Test cross-type automatic pairing on Seq -> Int ops (no hand pairing!)
    print("\n  Automatic cross-type pairing (best seq word -> int word per Seq->Int op, ZERO hand pairs):")
    for opk in s2i_ops:
        opfn = ops[opk][2]
        best_pair = (0.0, None, None)
        for snm in m3:
            sfn = seq_cands[snm]
            for inm, ifn in int_cands.items():
                obs = [(sfn(s), ifn(opfn(s))) for s in probe_seqs if opfn(s) is not None]
                lp, mi, hy = lump_score(obs)
                if lp * mi > best_pair[0]:
                    best_pair = (lp * mi, snm, inm, lp)
        print(f"    {opk:<11} -> best pair: ({best_pair[1]} -> {best_pair[2]}), lump={best_pair[3]:.2f}")

    # Measure ACTUAL 61-op synthesis speedup of Mode 2 (all-length!) vs Mode 3 (diverse via 5-line NMI!)
    # on 12 diverse 3-op tasks!
    xs_rows = ((3,-1,4,2), (-2,5,0,-3,1), (2,4,6), (1,-2,3,-4,5,0), (7,1), (0,-1,2,3))
    def eval_p(p, xs):
        if p == 'xs': return xs
        return ops[p[0]][2](*[eval_p(a, xs) for a in p[1:]])

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

    def eval_vocab_speedup(word_names, label):
        doms = {wn: (lambda v, ty, fn=seq_cands[wn]: fn(v) if ty=='seq' else (v%2)) for wn in word_names}
        # Build quick tables
        tbls = {}; univs = {}
        for dn, afn in doms.items():
            u = {'seq': set(afn(s,'seq') for s in probe_seqs), 'int': {0, 1}}
            dt = {}
            for ok, (at, rt, fn) in ops.items():
                tr = defaultdict(Counter)
                if len(at) == 1:
                    p0 = probe_seqs if at[0] == 'seq' else list(range(-12,13))
                    for x in p0:
                        o = fn(x)
                        if o is not None:
                            ao = afn(o, rt); tr[(afn(x, at[0]),)][ao] += 1; u[rt].add(ao)
                else:
                    p0 = probe_seqs[:40] if at[0]=='seq' else list(range(-6,7))
                    p1 = probe_seqs[:40] if at[1]=='seq' else list(range(-6,7))
                    for x in p0:
                        for y in p1:
                            o = fn(x, y)
                            if o is not None:
                                ao = afn(o, rt); tr[(afn(x,at[0]), afn(y,at[1]))][ao] += 1; u[rt].add(ao)
                dt[ok] = tr
            tbls[dn] = dt; univs[dn] = u
        tot_p, tot_a, ram_p, ram_a = 0, 0, 0, 0
        for prog in bench:
            tgt = tuple(eval_p(prog, x) for x in xs_rows)
            _, pc, pst, _, _, _, _ = synthesize_oe(ops, [('xs','seq',xs_rows)], 'seq', tgt, 3, budget=300000)
            _, ac, ast, _, _, _, _ = synthesize_oe(ops, [('xs','seq',xs_rows)], 'seq', tgt, 3,
                                                   domains=doms, tables=tbls, all_states=univs, use_abstract_pruning=True, budget=300000)
            tot_p += pc; tot_a += ac; ram_p += pst; ram_a += ast
        print(f"  {label:<44} | Total cands: {tot_a:>7} vs Plain {tot_p:>7} ({tot_p/max(1,tot_a):>4.2f}x) | RAM: {ram_a:>5} vs {ram_p:>5} ({ram_p/max(1,ram_a):>4.2f}x)")

    print("\n  Actual 61-op synthesis impact (8 sequence tasks):")
    eval_vocab_speedup(m2, "[2] No redundancy (6 length variants!)")
    eval_vocab_speedup(m3, "[3] 5-line pairwise NMI < 0.65 (diverse!)")


# ==============================================================================
# EXP C: IS GAP 4 NEEDED? (JOINT PROBES vs RULE-3 ISOLATE SLICES ON G2)
# ==============================================================================

def run_exp_c():
    print("\n" + "=" * 88)
    print("EXP C: IS GAP 4 NEEDED? (JOINT PROBES vs RULE-3 ISOLATE SLICES ON G2 ARITHMETIC)")
    print("=" * 88)
    vals = list(range(-12, 13))
    g2 = {
        '+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b,
        'max': lambda a, b: max(a, b), 'min': lambda a, b: min(a, b),
        'div': lambda a, b: None if b == 0 else a // b,
        'mod': lambda a, b: None if b == 0 else a % b,
    }
    doms = {'mod2': lambda v: v%2, 'mod3': lambda v: v%3, 'sign': lambda v: -1 if v<0 else (1 if v>0 else 0)}

    # Build verb tables from ONLY Rule-3 slices (fixing b in {-1, 0, 1, 2} and varying a)
    # vs Joint grid (a, b) in [-12..12]^2!
    def build_tbl(slice_only):
        tbl = {}
        for dn, dfn in doms.items():
            tbl[dn] = {}
            for opn, fn in g2.items():
                tr = defaultdict(set)
                bs = (-1, 0, 1, 2) if slice_only else vals
                for a in vals:
                    for b in bs:
                        o = fn(a, b)
                        if o is not None:
                            tr[(dfn(a), dfn(b))].add(dfn(o))
                tbl[dn][opn] = tr
        return tbl

    t_slice = build_tbl(True)
    t_joint = build_tbl(False)

    # Test on 200 random G2 binary transitions (a, b) in [-20..20]^2: how many real outputs get FALSELY REJECTED?
    rng = random.Random(404)
    false_rej_slice = Counter()
    false_rej_joint = Counter()
    for _ in range(500):
        a, b = rng.randint(-20, 20), rng.randint(-20, 20)
        for opn, fn in g2.items():
            o = fn(a, b)
            if o is None: continue
            for dn, dfn in doms.items():
                aa, ab, ao = dfn(a), dfn(b), dfn(o)
                s_outs = t_slice[dn][opn].get((aa, ab))
                if s_outs is not None and ao not in s_outs:
                    false_rej_slice[opn] += 1
                j_outs = t_joint[dn][opn].get((aa, ab))
                if j_outs is not None and ao not in j_outs:
                    false_rej_joint[opn] += 1
    print(f"  False rejections on 500 fresh (a,b) in [-20..20]^2 (out of 1500 op-domain checks each):")
    for opn in g2:
        print(f"    {opn:<4}: Rule-3 Slice tables -> {false_rej_slice[opn]:>3} false rejects | Joint grid tables -> {false_rej_joint[opn]:>3} false rejects")


# ==============================================================================
# EXP D: IS GAP 5 NEEDED? (100-TASK STREAM: STATIC PROBES vs ONLINE FEEDBACK)
# ==============================================================================

def run_exp_d():
    print("\n" + "=" * 88)
    print("EXP D: IS GAP 5 NEEDED? (100-TASK STREAM: STATIC PROBES vs 5-LINE FALLBACK FEEDBACK)")
    print("=" * 88)
    ops = make_61_library()
    u_seq = [k for k, (at, rt, _) in ops.items() if at == ('seq',) and rt == 'seq']

    # 6 quotients (separate) + 1 merged 3-quotient product (nonneg x parity x order)
    def q_len(v): return min(len(v), 6)
    def q_nonneg(v):
        if not v: return 'E'
        if all(x>0 for x in v): return 'P'
        if all(x>=0 for x in v): return 'N0'
        if all(x<0 for x in v): return 'NEG'
        return 'M'
    def q_parity(v):
        if not v: return 'E'
        if all(x%2==0 for x in v): return 'EV'
        if all(x%2!=0 for x in v): return 'OD'
        return 'M'
    def q_order(v):
        if len(v)<=1: return 'S01'
        if len(set(v))==1: return 'C'
        if all(v[i]<=v[i+1] for i in range(len(v)-1)): return 'ASC'
        if all(v[i]>=v[i+1] for i in range(len(v)-1)): return 'DSC'
        return 'U'
    def q_prod(v): return (q_nonneg(v), q_parity(v), q_order(v))

    sep_doms = {'len': q_len, 'nonneg': q_nonneg, 'parity': q_parity, 'order': q_order}
    mrg_doms = {'len': q_len, 'prod': q_prod}

    def gen_probes(n_probes, stratified, seed=11):
        rng = random.Random(seed)
        ps = [()]
        if stratified:
            for L in range(1, 7):
                for _ in range(max(2, n_probes // 90)):
                    s = tuple(rng.randint(-5, 5) for _ in range(L))
                    ps.extend([s, tuple(sorted(s)), tuple(sorted(s, reverse=True)),
                               tuple(abs(x) for x in s), tuple(2*x for x in s),
                               tuple(2*x+1 for x in s), (s[0],)*L, (s[0],s[0])+s[2:]])
        while len(ps) < n_probes:
            L = rng.randint(0, 7)
            ps.append(tuple(rng.randint(-6, 6) for _ in range(L)))
        return ps[:n_probes]

    def build_vt(doms, probes):
        vt = {dn: {opk: defaultdict(set) for opk in u_seq} for dn in doms}
        for dn, dfn in doms.items():
            for opk in u_seq:
                fn = ops[opk][2]
                for s in probes:
                    o = fn(s)
                    if o is not None:
                        vt[dn][opk][dfn(s)].add(dfn(o))
        return vt

    # Generate 200 random 3-op unary sequence tasks on 6 random rows (including occasional edge rows!)
    rng_t = random.Random(888)
    tasks = []
    for _ in range(200):
        chain = [rng_t.choice(u_seq) for _ in range(3)]
        rows = [tuple(rng_t.randint(-5, 5) for _ in range(rng_t.randint(1, 6))) for _ in range(6)]
        # Add 1 structured edge row per task (e.g. equal prefix or sorted or all-even) to stress rare outputs!
        edge_choice = rng_t.choice([(3,3,3,1), (2,4,6,8), (0,0,0), (5,4,3,2), (-2,-2,-1)])
        rows[0] = edge_choice
        # Verify valid chain
        ok = True
        cur = rows
        interm = [rows]
        for opk in chain:
            nxt = []
            for x in cur:
                v = ops[opk][2](x)
                if v is None: ok = False; break
                nxt.append(v)
            if not ok: break
            cur = nxt; interm.append(cur)
        if ok:
            tasks.append((chain, interm))

    def sim_stream(name, doms, probes, feedback):
        vt = build_vt(doms, probes)
        misses_first100 = 0
        misses_last100 = 0
        updates = 0
        for idx, (chain, interm) in enumerate(tasks):
            # Does vt reject the TRUE chain on any step/row/domain?
            missed = False
            for step, opk in enumerate(chain):
                in_rows, out_rows = interm[step], interm[step+1]
                for dn, dfn in doms.items():
                    for x, y in zip(in_rows, out_rows):
                        ax, ay = dfn(x), dfn(y)
                        outs = vt[dn][opk].get(ax)
                        if outs is not None and ay not in outs:
                            missed = True
            if missed:
                if idx < 100: misses_first100 += 1
                else: misses_last100 += 1
                if feedback:
                    # 5-line feedback: add fallback-solved intermediate transitions directly to vt!
                    for step, opk in enumerate(chain):
                        for dn, dfn in doms.items():
                            for x, y in zip(interm[step], interm[step+1]):
                                ax, ay = dfn(x), dfn(y)
                                if ay not in vt[dn][opk][ax]:
                                    vt[dn][opk][ax].add(ay)
                                    updates += 1
        print(f"  {name:<50} | Misses 1..100: {misses_first100:>2}/100 | Misses 101..200: {misses_last100:>2}/100 | Total: {misses_first100+misses_last100:>3}/200 (fb_upd={updates})")

    sim_stream("Separate (4 doms), 150 random probes, NO feedback",  sep_doms, gen_probes(150, False), False)
    sim_stream("Separate (4 doms), 150 random probes, +5-line FB",  sep_doms, gen_probes(150, False), True)
    sim_stream("Separate (4 doms), 1000 strat probes, NO feedback", sep_doms, gen_probes(1000, True), False)
    sim_stream("Merged (nonneg x par x ord), 2000 rand, NO FB",     mrg_doms, gen_probes(2000, False), False)
    sim_stream("Merged (nonneg x par x ord), 2000 rand, +5-line FB",mrg_doms, gen_probes(2000, False), True)
    sim_stream("Merged (nonneg x par x ord), 2000 strat, NO FB",    mrg_doms, gen_probes(2000, True), False)
    sim_stream("Merged (nonneg x par x ord), 2000 strat, +5-line FB",mrg_doms, gen_probes(2000, True), True)


if __name__ == '__main__':
    run_exp_a()
    run_exp_b()
    run_exp_c()
    run_exp_d()
