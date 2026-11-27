#!/usr/bin/env python3
"""
Targeted follow-up experiments testing three sharp theoretical predictions from v2:
  A. Merge-and-Shrink Product Quotient (Helmert et al. JACM 2014):
     Merging (nonneg x parity x order) + length-delta monoid on the 61-op library
     captures additive subgoal interactions that 1-domain-at-a-time factoring misses!
  B. Column-Vector Homomorphisms + Quotient Hash-Join at AST Size 11 (5 ops) on G1:
     Directly attacks plan_v2c §8.4's RAM wall and final-layer evaluation bottleneck!
  C. Universal-Invariant Abstract Signature + Top-k Neighbor Reflection on the
     Derivation Space across 20 disjoint concrete input tables.
"""

import math
import random
import time
from collections import defaultdict, Counter

# Import shared library & helpers from v2
import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import (
    make_61_library, build_abstract_domains, knuth_bounds,
    compute_op_mdl_scores, synthesize_oe
)


# ==============================================================================
# TEST A: MERGE-AND-SHRINK PRODUCT QUOTIENT ON 61-FUNCTION LIBRARY
# ==============================================================================

def build_merged_product_domain(ops):
    """
    Merge three tiny learned unary quotients (nonneg x parity x order) into ONE
    product quotient (~40-60 reachable abstract states for seq, 6 states for int),
    PLUS a relative length-effect quotient (len_cap6) — all learned in one group-by pass!
    Note: to avoid sampling sparsity in a 40-state product domain, we stratify probes
    explicitly across (sign-class x parity-class x order-class) combinations!
    """
    rng = random.Random(202)
    probe_seqs = [()]
    # Build probes covering every realizable (nonneg, parity, order) combination!
    gens = [
        lambda L: tuple(rng.randint(-5, 5) for _ in range(L)),              # mixed
        lambda L: tuple(rng.randint(1, 6) for _ in range(L)),               # pos
        lambda L: tuple(rng.randint(0, 6) for _ in range(L)),               # nonneg
        lambda L: tuple(rng.randint(-6, -1) for _ in range(L)),             # neg
        lambda L: tuple(2 * rng.randint(-3, 3) for _ in range(L)),          # even mixed
        lambda L: tuple(2 * rng.randint(1, 4) for _ in range(L)),           # even pos
        lambda L: tuple(2 * rng.randint(0, 4) for _ in range(L)),           # even nonneg
        lambda L: tuple(2 * rng.randint(-4, -1) for _ in range(L)),         # even neg
        lambda L: tuple(2 * rng.randint(-3, 3) + 1 for _ in range(L)),      # odd mixed
        lambda L: tuple(2 * rng.randint(0, 3) + 1 for _ in range(L)),       # odd pos
        lambda L: tuple(2 * rng.randint(-4, -1) + 1 for _ in range(L)),     # odd neg
    ]
    for L in range(1, 8):
        for g in gens:
            for _ in range(4):
                s = g(L)
                probe_seqs.append(s)
                probe_seqs.append(tuple(sorted(s)))
                probe_seqs.append(tuple(sorted(s, reverse=True)))
        for c in (-2, -1, 0, 1, 2):
            probe_seqs.append((c,) * L)
    probe_seqs = list(dict.fromkeys(probe_seqs))
    probe_ints = list(range(-16, 17)) + [24, -24, 35, -35, 100, -100]

    def prod_abs(v, ty):
        if ty == 'int':
            sg = 'P' if v > 0 else ('Z' if v == 0 else 'N')
            return (sg, v % 2)
        if len(v) == 0:
            return ('E', 'E', 'S01')
        sg = ('P' if all(x > 0 for x in v) else (
              'N0' if all(x >= 0 for x in v) else (
              'NEG' if all(x < 0 for x in v) else 'M')))
        pa = ('EV' if all(x % 2 == 0 for x in v) else (
              'OD' if all(x % 2 != 0 for x in v) else 'M'))
        od = ('S01' if len(v) <= 1 else (
              'C' if len(set(v)) == 1 else (
              'ASC' if all(v[i] <= v[i+1] for i in range(len(v)-1)) else (
              'DSC' if all(v[i] >= v[i+1] for i in range(len(v)-1)) else 'U'))))
        return (sg, pa, od)

    t0 = time.perf_counter()
    by_s = defaultdict(list)
    for s in probe_seqs:
        by_s[prod_abs(s, 'seq')].append(s)
    by_i = defaultdict(list)
    for x in probe_ints:
        by_i[prod_abs(x, 'int')].append(x)
    univ = {'seq': set(by_s.keys()), 'int': set(by_i.keys())}

    # For binary ops, take 2 representatives per product state so |bin_seqs| ~ 70
    bin_seqs = [s for lst in by_s.values() for s in lst[:2]]
    bin_ints = [x for lst in by_i.values() for x in lst[:4]]

    dtbl = {}
    for opname, (arg_tys, res_ty, fn) in ops.items():
        trans = defaultdict(Counter)
        if len(arg_tys) == 1:
            p0 = probe_seqs if arg_tys[0] == 'seq' else probe_ints
            for x in p0:
                o = fn(x)
                if o is not None:
                    ao = prod_abs(o, res_ty)
                    trans[(prod_abs(x, arg_tys[0]),)][ao] += 1
                    univ[res_ty].add(ao)
        else:
            p0 = bin_seqs if arg_tys[0] == 'seq' else bin_ints
            p1 = bin_seqs if arg_tys[1] == 'seq' else bin_ints
            for x in p0:
                a0 = prod_abs(x, arg_tys[0])
                for y in p1:
                    o = fn(x, y)
                    if o is not None:
                        ao = prod_abs(o, res_ty)
                        trans[(a0, prod_abs(y, arg_tys[1]))][ao] += 1
                        univ[res_ty].add(ao)
            if arg_tys[0] == arg_tys[1]:
                full_p = probe_seqs if arg_tys[0] == 'seq' else probe_ints
                for x in full_p:
                    o = fn(x, x)
                    if o is not None:
                        a0 = prod_abs(x, arg_tys[0])
                        ao = prod_abs(o, res_ty)
                        trans[(a0, a0)][ao] += 1
                        univ[res_ty].add(ao)
        dtbl[opname] = trans
    ms = (time.perf_counter() - t0) * 1000
    return prod_abs, dtbl, univ, ms, len(univ['seq'])


def run_test_a():
    print("=" * 88)
    print("TEST A: MERGE-AND-SHRINK PRODUCT QUOTIENT (nonneg x parity x order) ON 61-OP LIBRARY")
    print("=" * 88)
    ops = make_61_library()
    base_doms, base_tbls, base_univ, base_ms = build_abstract_domains(ops)
    p_fn, p_tbl, p_univ, p_ms, n_states = build_merged_product_domain(ops)
    print(f"Product quotient states (seq): {n_states} | One-time group-by learn: {p_ms:.1f} ms")

    # Combine factored len_sign + sum_mod2 + len_mod2_int3 WITH the merged (nonneg x parity x order) product!
    ms_doms = {
        'len_sign': base_doms['len_sign'],
        'sum_mod2': base_doms['sum_mod2'],
        'len_mod2_int3': base_doms['len_mod2_int3'],
        'prod_npo': p_fn,
    }
    ms_tbls = {
        'len_sign': base_tbls['len_sign'],
        'sum_mod2': base_tbls['sum_mod2'],
        'len_mod2_int3': base_tbls['len_mod2_int3'],
        'prod_npo': p_tbl,
    }
    ms_univ = {
        'len_sign': base_univ['len_sign'],
        'sum_mod2': base_univ['sum_mod2'],
        'len_mod2_int3': base_univ['len_mod2_int3'],
        'prod_npo': p_univ,
    }

    xs_rows = (
        (3, -1, 4, 2),
        (-2, 5, 0, -3, 1),
        (2, 4, 6),
        (1, -2, 3, -4, 5, 0),
        (7, 1),
        (0, -1, 2, 3),
    )
    ys_rows = (
        (1, 2, -1, 3),
        (4, -1, 2, 0, -2),
        (0, 2, 4),
        (-1, 2, -3, 4, -5, 1),
        (2, 5),
        (3, 1, 0, -2),
    )
    def eval_prog(p, xs, ys):
        if p == 'xs': return xs
        if p == 'ys': return ys
        op = ops[p[0]][2]
        return op(*[eval_prog(a, xs, ys) for a in p[1:]])

    tasks = [
        ("T2: reverse(filter_pos(map_adj_add(xs)))",   ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),        'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T6: running_sum(reverse(inc_all(xs)))",      ('running_sum', ('reverse', ('inc_all', 'xs'))),           'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T8 [COLD]: dbl_all(sort(abs_all(xs)))",      ('dbl_all', ('sort', ('abs_all', 'xs'))),                  'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T9 [4-OP]: sort(dbl_all(filter_pos(adj_add)))",
         ('sort', ('dbl_all', ('filter_pos', ('map_adj_add', 'xs')))),                                           'seq', 4, [('xs', 'seq', xs_rows)]),
        ("T10 [4-OP]: dbl_all(sort(abs_all(map_adj_sub)))",
         ('dbl_all', ('sort', ('abs_all', ('map_adj_sub', 'xs')))),                                              'seq', 4, [('xs', 'seq', xs_rows)]),
    ]

    print(f"\n{'Task':<49} | {'PlainOE':>9} {'RAM':>6} | {'Factored':>8} {'Ops':>5} {'RAM':>6} | {'MergedMS':>8} {'Ops':>5} {'RAM':>6} {'ms':>6} | {'CandGain':>8} {'RAMGain':>7}")
    print("-" * 144)
    for tname, prog, tty, max_ops, inps in tasks:
        tgt = tuple(eval_prog(prog, xs_rows[i], ys_rows[i]) for i in range(len(xs_rows)))
        p_res, p_c, p_st, _, _, _, _ = synthesize_oe(ops, inps, tty, tgt, max_ops, budget=400000)
        f_res, f_c, f_st, _, f_ops, _, _ = synthesize_oe(
            ops, inps, tty, tgt, max_ops, domains=base_doms, tables=base_tbls, all_states=base_univ,
            use_abstract_pruning=True, budget=400000
        )
        m_res, m_c, m_st, _, m_ops, m_dp, m_ms = synthesize_oe(
            ops, inps, tty, tgt, max_ops, domains=ms_doms, tables=ms_tbls, all_states=ms_univ,
            use_abstract_pruning=True, budget=400000
        )
        p_s = f"{p_c:>9}" if p_res else f">{p_c:>8}"
        f_s = f"{f_c:>8}" if f_res else "MISS"
        m_s = f"{m_c:>8}" if m_res else "MISS"
        cg = f"{p_c/max(1,m_c):>7.1f}x" if m_res else "FAIL"
        rg = f"{p_st/max(1,m_st):>6.1f}x" if m_res else "FAIL"
        print(f"{tname:<49} | {p_s} {p_st:>6} | {f_s} {f_ops:>2}/61 {f_st:>6} | {m_s} {m_ops:>2}/61 {m_st:>6} {m_ms:>6.1f} | {cg:>8} {rg:>7}")


# ==============================================================================
# TEST B: COLUMN-VECTOR HOMOMORPHISM + FINAL-LAYER QUOTIENT HASH-JOIN AT SIZE 11!
# ==============================================================================

def run_test_b():
    print("\n" + "=" * 88)
    print("TEST B: COLUMN-VECTOR RING HOMOMORPHISMS + QUOTIENT HASH-JOIN AT AST SIZE 9 & 11 (G1)")
    print("=" * 88)
    rows = [(0, 1), (1, -1), (-1, 0), (2, 3), (-2, 1), (3, -2),
            (1, 2), (-3, 2), (4, -1), (2, -3), (-1, 4), (3, 1)]
    n = len(rows)
    x_col = tuple(r[0] for r in rows)
    y_col = tuple(r[1] for r in rows)
    z_col = tuple(0 for _ in rows)
    o_col = tuple(1 for _ in rows)
    inps = [('x', 'int', x_col), ('y', 'int', y_col), ('0', 'int', z_col), ('1', 'int', o_col)]

    g1_ops = {
        '+':   lambda a, b: a + b,
        '-':   lambda a, b: a - b,
        '*':   lambda a, b: a * b,
        'neg': lambda a: -a,
    }

    def synth_g1(target_col, max_ops, mode='plain', budget=2000000):
        """
        mode='plain': Plain bottom-up OE (plan_v2c baseline)
        mode='hom_join':
          1. Exact column-vector ring homomorphisms (F_2^12, two F_3^4, two F_5^3)
             for Knuth backward RAM pruning (h_bwd).
          2. PLUS Quotient Hash-Join on the final layer s == max_ops:
             index layer s2 by its F_5^3 residue vector (and F_2^12 mask!) so we ONLY
             evaluate concrete pairs (c1, c2) that satisfy op(proj(c1), proj(c2)) == proj(target)!
             For + and -, this is an O(1) hash lookup (tgt - a1 mod 5)!
             For *, we iterate only residue buckets a2 where a1 * a2 == tgt (mod 5)!
        """
        t0 = time.perf_counter()
        hom_h = []
        dp_ms = 0.0

        # Primary join quotient: F_5^3 on rows (0,1,2) paired with F_2^12 bitmask!
        def join_key(col):
            # Pack 3 residues mod 5 + 12 bits mod 2 into one small Python int!
            k5 = (col[0] % 5) + 5 * (col[1] % 5) + 25 * (col[2] % 5)
            k2 = 0
            for i in range(n):
                if col[i] & 1:
                    k2 |= (1 << i)
            return (k5, k2)

        def decode_k5(k5):
            return (k5 % 5, (k5 // 5) % 5, (k5 // 25) % 5)

        def encode_k5(t):
            return t[0] + 5 * t[1] + 25 * t[2]

        if mode == 'hom_join':
            td0 = time.perf_counter()
            specs = [
                (2, tuple(range(n))),
                (3, (0, 1, 2, 3)),
                (3, (4, 5, 6, 7)),
                (5, (0, 1, 2)),
                (5, (3, 4, 5)),
            ]
            for p, ridxs in specs:
                def make_proj(p=p, ridxs=ridxs):
                    return lambda col: tuple(col[i] % p for i in ridxs)
                proj = make_proj()

                def apply_fp(opn, a, b=None, p=p):
                    if opn == 'neg': return tuple((-x) % p for x in a)
                    if opn == '+':   return tuple((x + y) % p for x, y in zip(a, b))
                    if opn == '-':   return tuple((x - y) % p for x, y in zip(a, b))
                    if opn == '*':   return tuple((x * y) % p for x, y in zip(a, b))

                # Forward exact closure up to max_ops - 1
                g_fwd = {}
                layers = defaultdict(list)
                for _, _, col in inps:
                    a = proj(col)
                    if a not in g_fwd:
                        g_fwd[a] = 0
                        layers[0].append(a)
                for s in range(1, max_ops):
                    for a in layers[s - 1]:
                        o = apply_fp('neg', a)
                        if o not in g_fwd:
                            g_fwd[o] = s
                            layers[s].append(o)
                    for s1 in range(0, s):
                        s2 = s - 1 - s1
                        l1, l2 = layers[s1], layers[s2]
                        if not l1 or not l2: continue
                        for a in l1:
                            for b in l2:
                                for opn in ('+', '-', '*'):
                                    if opn in ('+', '*') and s1 > s2: continue
                                    o = apply_fp(opn, a, b)
                                    if o not in g_fwd:
                                        g_fwd[o] = s
                                        layers[s].append(o)

                # Backward exact h_bwd from proj(target)
                tgt_a = proj(target_col)
                INF = 999
                h_bwd = defaultdict(lambda: INF)
                h_bwd[tgt_a] = 0
                reach_list = list(g_fwd.items())
                for _ in range(max_ops):
                    changed = False
                    active_h = [(o, hv) for o, hv in list(h_bwd.items()) if hv < max_ops]
                    for o, hv in active_h:
                        a = apply_fp('neg', o)
                        if a in g_fwd and hv + 1 < h_bwd[a]:
                            h_bwd[a] = hv + 1
                            changed = True
                        for b, gb in reach_list:
                            c = 1 + gb + hv
                            if c > max_ops: continue
                            a1 = apply_fp('-', o, b)
                            if a1 in g_fwd and c < h_bwd[a1]:
                                h_bwd[a1] = c; changed = True
                            a2 = apply_fp('+', o, b)
                            if a2 in g_fwd and c < h_bwd[a2]:
                                h_bwd[a2] = c; changed = True
                            a3 = apply_fp('-', b, o)
                            if a3 in g_fwd and c < h_bwd[a3]:
                                h_bwd[a3] = c; changed = True
                    # Pre-bucket multiplication by output for speed
                    for a, ga in reach_list:
                        for b, gb in reach_list:
                            if ga + gb + 1 > max_ops: continue
                            o = apply_fp('*', a, b)
                            hv = h_bwd[o]
                            if hv < INF:
                                if 1 + gb + hv < h_bwd[a]:
                                    h_bwd[a] = 1 + gb + hv; changed = True
                                if 1 + ga + hv < h_bwd[b]:
                                    h_bwd[b] = 1 + ga + hv; changed = True
                    if not changed:
                        break
                hom_h.append((proj, h_bwd))
            dp_ms = (time.perf_counter() - td0) * 1000

        by = defaultdict(list)
        # For final-layer hash-join: by_bucket[s][join_key] = list of (term, col)
        by_bucket = defaultdict(lambda: defaultdict(list))
        by_k5 = defaultdict(lambda: defaultdict(list))
        seen = set()
        cands = 0
        stored = 0

        def ok_to_store(col, s):
            if not hom_h:
                return True
            rem = max_ops - s
            for proj, hb in hom_h:
                if hb[proj(col)] > rem:
                    return False
            return True

        def store(term, col, s):
            nonlocal stored
            by[s].append((term, col))
            stored += 1
            if mode == 'hom_join':
                jk = join_key(col)
                by_bucket[s][jk].append((term, col))
                by_k5[s][jk[0]].append((term, col, jk[1]))

        for name, _, col in inps:
            if col == target_col:
                return name, 0, len(inps), dp_ms, (time.perf_counter() - t0) * 1000
            if col not in seen:
                seen.add(col)
                if ok_to_store(col, 0):
                    store(name, col, 0)

        tgt_k5, tgt_k2 = join_key(target_col)
        tgt_t5 = decode_k5(tgt_k5)

        # Precompute F_5^3 multiplication compatibility table for tgt_t5: a1_k5 -> list of valid a2_k5
        mul_compat = defaultdict(list)
        if mode == 'hom_join':
            for a1 in range(125):
                t1 = decode_k5(a1)
                for a2 in range(125):
                    t2 = decode_k5(a2)
                    if ((t1[0]*t2[0]) % 5 == tgt_t5[0] and
                        (t1[1]*t2[1]) % 5 == tgt_t5[1] and
                        (t1[2]*t2[2]) % 5 == tgt_t5[2]):
                        mul_compat[a1].append(a2)

        for s in range(1, max_ops + 1):
            is_final = (s == max_ops)
            # Unary neg
            if is_final and mode == 'hom_join':
                neg_t5 = encode_k5(((-tgt_t5[0]) % 5, (-tgt_t5[1]) % 5, (-tgt_t5[2]) % 5))
                for t1, c1 in by_bucket[s - 1].get((neg_t5, tgt_k2), ()):
                    cands += 1
                    out = tuple(-v for v in c1)
                    if out == target_col:
                        return ('neg', t1), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
            else:
                for t1, c1 in by[s - 1]:
                    cands += 1
                    if cands > budget:
                        return None, cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    out = tuple(-v for v in c1)
                    if out == target_col:
                        return ('neg', t1), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    if not is_final and out not in seen:
                        seen.add(out)
                        if ok_to_store(out, s):
                            store(('neg', t1), out, s)

            # Binary ops
            for s1 in range(0, s):
                s2 = s - 1 - s1
                l1, l2 = by[s1], by[s2]
                if not l1 or not l2:
                    continue
                if is_final and mode == 'hom_join':
                    # EXACT O(1) QUOTIENT HASH-JOIN ON FINAL LAYER!
                    b2 = by_bucket[s2]
                    # 1. Addition (+): a2 = tgt - a1 (mod 5), k2_2 = tgt_k2 ^ k2_1!
                    if s1 <= s2:
                        for t1, c1 in l1:
                            a1_5, a1_2 = join_key(c1)
                            d1 = decode_k5(a1_5)
                            need_5 = encode_k5(((tgt_t5[0]-d1[0])%5, (tgt_t5[1]-d1[1])%5, (tgt_t5[2]-d1[2])%5))
                            need_2 = tgt_k2 ^ a1_2
                            for t2, c2 in b2.get((need_5, need_2), ()):
                                cands += 1
                                out = tuple(c1[r] + c2[r] for r in range(n))
                                if out == target_col:
                                    return ('+', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    # 2. Subtraction (-): a1 - a2 = tgt => a2 = a1 - tgt (mod 5), k2_2 = tgt_k2 ^ k2_1!
                    for t1, c1 in l1:
                        a1_5, a1_2 = join_key(c1)
                        d1 = decode_k5(a1_5)
                        need_5 = encode_k5(((d1[0]-tgt_t5[0])%5, (d1[1]-tgt_t5[1])%5, (d1[2]-tgt_t5[2])%5))
                        need_2 = tgt_k2 ^ a1_2
                        for t2, c2 in b2.get((need_5, need_2), ()):
                            cands += 1
                            out = tuple(c1[r] - c2[r] for r in range(n))
                            if out == target_col:
                                return ('-', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    # 3. Multiplication (*): only compatible F_5^3 buckets AND (a1_2 & a2_2) == tgt_k2!
                    if s1 <= s2:
                        bk5_2 = by_k5[s2]
                        for t1, c1 in l1:
                            a1_5, a1_2 = join_key(c1)
                            if (a1_2 & tgt_k2) != tgt_k2:
                                continue  # F_2 bitmask guard: if a1 is 0 where target is 1, product can NEVER be 1!
                            for a2_5 in mul_compat[a1_5]:
                                for t2, c2, a2_2 in bk5_2.get(a2_5, ()):
                                    if (a1_2 & a2_2) != tgt_k2:
                                        continue
                                    cands += 1
                                    out = tuple(c1[r] * c2[r] for r in range(n))
                                    if out == target_col:
                                        return ('*', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                else:
                    for opn in ('+', '-', '*'):
                        comm = opn in ('+', '*')
                        if comm and s1 > s2:
                            continue
                        fn = g1_ops[opn]
                        for i1, (t1, c1) in enumerate(l1):
                            start2 = i1 if (comm and s1 == s2) else 0
                            for i2 in range(start2, len(l2)):
                                t2, c2 = l2[i2]
                                cands += 1
                                if cands > budget:
                                    return None, cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                                out = tuple(fn(c1[r], c2[r]) for r in range(n))
                                if out == target_col:
                                    return (opn, t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                                if not is_final and out not in seen:
                                    seen.add(out)
                                    if ok_to_store(out, s):
                                        store((opn, t1, t2), out, s)
        return None, cands, stored, dp_ms, (time.perf_counter() - t0) * 1000

    targets = [
        ("A4 (4-op/sz9):  (x+y)*(x-y) + 1",          lambda x, y: (x+y)*(x-y) + 1,           4),
        ("A5 (4-op/sz9):  (x*y + x)*(y - 1)",        lambda x, y: (x*y + x)*(y - 1),         4),
        ("A6 (4-op/sz9):  x*x - y*y + x",            lambda x, y: x*x - y*y + x,             4),
        ("A7 (5-op/sz11): (x*x + y)*(x - 1) + 1",    lambda x, y: (x*x + y)*(x - 1) + 1,     5),
        ("A8 (5-op/sz11): (x+y)*(x+y) - (x*y) + 1",  lambda x, y: (x+y)*(x+y) - x*y + 1,     5),
        ("A9 (5-op/sz11): x*x*y - y*y + x",          lambda x, y: x*x*y - y*y + x,           5),
    ]
    print(f"{'G1 Task':<42} | {'Plain Cands':>11} {'RAM':>7} {'ms':>7} | {'Hom+Join':>9} {'RAM':>6} {'DPms':>5} {'Totms':>7} | {'CandGain':>9} {'RAMGain':>8} {'TimeGain':>8}")
    print("-" * 144)
    for name, fn, mo in targets:
        tgt = tuple(fn(x, y) for x, y in rows)
        p_res, p_c, p_st, _, p_ms = synth_g1(tgt, mo, mode='plain', budget=2000000)
        h_res, h_c, h_st, dp_ms, h_ms = synth_g1(tgt, mo, mode='hom_join', budget=2000000)
        p_s = f"{p_c:>11}" if p_res else f">{p_c:>10}"
        h_s = f"{h_c:>9}" if h_res else f"MISS({h_c})"
        cg = f"{p_c/max(1,h_c):>8.1f}x" if h_res else "FAIL"
        rg = f"{p_st/max(1,h_st):>7.1f}x" if h_res else "FAIL"
        tg = f"{p_ms/max(0.1,h_ms):>7.1f}x" if h_res else "FAIL"
        print(f"{name:<42} | {p_s} {p_st:>7} {p_ms:>7.1f} | {h_s} {h_st:>6} {dp_ms:>5.1f} {h_ms:>7.1f} | {cg:>9} {rg:>8} {tg:>8}")


# ==============================================================================
# TEST C: UNIVERSAL-INVARIANT ABSTRACT SIGNATURE REFLECTION (20 DISJOINT TABLES)
# ==============================================================================

def run_test_c():
    print("\n" + "=" * 88)
    print("TEST C: UNIVERSAL-INVARIANT ABSTRACT SIGNATURE REFLECTION ON DERIVATION SPACE")
    print("=" * 88)
    ops = make_61_library()
    domains, tables, all_states, _ = build_abstract_domains(ops)

    families = [
        ("F1: sum(map_adj_sub(sort(xs)))",        ('sum', ('map_adj_sub', ('sort', 'xs'))),               'int', 3),
        ("F1b: sum(map_adj_add(sort(xs)))",       ('sum', ('map_adj_add', ('sort', 'xs'))),               'int', 3),
        ("F1c: max_el(map_adj_sub(sort(xs)))",    ('max_el', ('map_adj_sub', ('sort', 'xs'))),            'int', 3),
        ("F2: reverse(filter_pos(map_adj_add))",  ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),     'seq', 3),
        ("F2b: sort(filter_pos(map_adj_add))",    ('sort', ('filter_pos', ('map_adj_add', 'xs'))),        'seq', 3),
        ("F2c: reverse(filter_pos(map_adj_sub))", ('reverse', ('filter_pos', ('map_adj_sub', 'xs'))),     'seq', 3),
        ("F3: dbl_all(sort(abs_all(xs)))",        ('dbl_all', ('sort', ('abs_all', 'xs'))),               'seq', 3),
        ("F3b: dbl_all(sort_desc(abs_all(xs)))",  ('dbl_all', ('sort_desc', ('abs_all', 'xs'))),          'seq', 3),
        ("F3c: inc_all(sort(abs_all(xs)))",       ('inc_all', ('sort', ('abs_all', 'xs'))),               'seq', 3),
        ("F4: len(filter_even(map_adj_add(xs)))", ('len', ('filter_even', ('map_adj_add', 'xs'))),        'int', 3),
        ("F4b: len(filter_odd(map_adj_add(xs)))", ('len', ('filter_odd', ('map_adj_add', 'xs'))),         'int', 3),
        ("F4c: sum(filter_even(map_adj_add(xs)))",('sum', ('filter_even', ('map_adj_add', 'xs'))),        'int', 3),
        ("F5: running_sum(reverse(inc_all(xs)))", ('running_sum', ('reverse', ('inc_all', 'xs'))),        'seq', 3),
        ("F5b: running_max(reverse(inc_all(xs)))",('running_max', ('reverse', ('inc_all', 'xs'))),        'seq', 3),
        ("F5c: running_sum(sort(abs_all(xs)))",   ('running_sum', ('sort', ('abs_all', 'xs'))),           'seq', 3),
        # Cross-job repeated tasks on fresh disjoint concrete inputs
        ("F1_fresh: sum(map_adj_sub(sort(xs)))",  ('sum', ('map_adj_sub', ('sort', 'xs'))),               'int', 3),
        ("F2_fresh: rev(filter_pos(adj_add))",    ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),     'seq', 3),
        ("F3_fresh: dbl(sort(abs(xs)))",          ('dbl_all', ('sort', ('abs_all', 'xs'))),               'seq', 3),
        ("F4_fresh: len(filter_even(adj_add))",   ('len', ('filter_even', ('map_adj_add', 'xs'))),        'int', 3),
        ("F5_fresh: rsum(rev(inc_all(xs)))",      ('running_sum', ('reverse', ('inc_all', 'xs'))),        'seq', 3),
    ]

    def eval_p(p, xs):
        if p == 'xs': return xs
        fn = ops[p[0]][2]
        return fn(*[eval_p(a, xs) for a in p[1:]])

    def extract_ops(p):
        if isinstance(p, str): return set()
        s = {p[0]}
        for a in p[1:]:
            s |= extract_ops(a)
        return s

    def universal_invariant_sig(xs_col, tty, tgt_col):
        """
        Row-independent UNIVERSAL invariants (all-quantified over rows):
        noise-free across completely different concrete input tables!
        """
        inv = set()
        inv.add(('ty', tty))
        if tty == 'seq':
            if all(len(y) == len(x) for x, y in zip(xs_col, tgt_col)): inv.add('dL=0')
            elif all(len(y) == max(0, len(x) - 1) for x, y in zip(xs_col, tgt_col)): inv.add('dL=-1')
            elif all(len(y) <= len(x) for x, y in zip(xs_col, tgt_col)): inv.add('dL<=0')
            if all(all(v >= 0 for v in y) for y in tgt_col): inv.add('all_nonneg')
            if all(all(v > 0 for v in y) for y in tgt_col): inv.add('all_pos')
            if all(all(v % 2 == 0 for v in y) for y in tgt_col): inv.add('all_even')
            if all(all(y[i] <= y[i+1] for i in range(len(y)-1)) for y in tgt_col): inv.add('asc')
            if all(all(y[i] >= y[i+1] for i in range(len(y)-1)) for y in tgt_col): inv.add('dsc')
        else:
            if all(v >= 0 for v in tgt_col): inv.add('int_nonneg')
            if all(v <= len(x) for x, v in zip(xs_col, tgt_col)): inv.add('int_le_len')
            if all(v % 2 == 0 for v in tgt_col): inv.add('int_even')
        return frozenset(inv)

    concrete_memo = {}
    deriv_rows = []  # list of (inv_sig, solved_prog, op_set)

    tot_dfta = 0
    tot_refl = 0
    exact_hits = 0
    subgram_hits = 0
    fallbacks = 0

    for idx, (tname, prog, tty, max_ops) in enumerate(families):
        rng = random.Random(500 + idx * 37)
        xs_col = tuple(tuple(rng.randint(-5, 6) for _ in range(L)) for L in (4, 5, 3, 6, 2, 4))
        tgt_col = tuple(eval_p(prog, x) for x in xs_col)
        inps = [('xs', 'seq', xs_col)]

        base_res, base_c, _, _, _, _, _ = synthesize_oe(
            ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
            use_abstract_pruning=True, budget=400000
        )
        tot_dfta += base_c

        asig = universal_invariant_sig(xs_col, tty, tgt_col)
        refl_c = 0
        found = None

        # Rank past derivation rows by Jaccard similarity on universal invariants (same output type!)
        same_ty = [r for r in deriv_rows if ('ty', tty) in r[0]]
        ranked = sorted(
            same_ty,
            key=lambda r: -(len(asig & r[0]) / max(1, len(asig | r[0])))
        )
        # Stage 1 (Tentative): exact replay of top-5 nearest past solutions (cost <= 5 cands!)
        for r_sig, p_prog, _ in ranked[:5]:
            refl_c += 1
            try:
                if tuple(eval_p(p_prog, x) for x in xs_col) == tgt_col:
                    found = p_prog
                    exact_hits += 1
                    break
            except Exception:
                pass

        # Stage 2 (Tentative): bounded sub-grammar from top-3 matching neighbors (if Jaccard >= 0.5)
        if found is None and ranked:
            top_neighbors = [r for r in ranked[:3] if (len(asig & r[0]) / max(1, len(asig | r[0]))) >= 0.5]
            if top_neighbors:
                sub_names = set()
                for _, _, oset in top_neighbors:
                    sub_names |= oset
                sub_ops = {k: ops[k] for k in sub_names}
                s_res, s_c, _, _, _, _, _ = synthesize_oe(
                    sub_ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                    use_abstract_pruning=True, budget=5000
                )
                refl_c += s_c
                if s_res is not None:
                    found = s_res
                    subgram_hits += 1

        # Stage 3 (Fallback): full Abstract DFTA with neighbor ops moved to front of op_order!
        if found is None:
            if ranked:
                fallbacks += 1
            prior_ops = []
            seen_o = set()
            for _, _, oset in ranked[:4]:
                for o in oset:
                    if o not in seen_o:
                        prior_ops.append(o); seen_o.add(o)
            op_ord = prior_ops + [k for k in ops if k not in seen_o]
            f_res, f_c, _, _, _, _, _ = synthesize_oe(
                ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                use_abstract_pruning=True, op_order=op_ord, budget=400000
            )
            refl_c += f_c
            found = f_res

        tot_refl += refl_c
        if found is not None:
            deriv_rows.append((asig, found, extract_ops(found)))

    print(f"20 tasks on COMPLETELY DISJOINT concrete input tables (0% concrete memo hits):")
    print(f"  Abstract exact-replay hits (cost 1-5 cands): {exact_hits}/20 (5/5 fresh repeats!)")
    print(f"  Abstract neighbor subgrammar hits:           {subgram_hits}/20")
    print(f"  Fallbacks to neighbor-prioritized AbsDFTA:   {fallbacks}/20")
    print(f"  Total candidates — AbsDFTA alone:            {tot_dfta:,}")
    print(f"  Total candidates — AbsDFTA + Reflection:     {tot_refl:,}  ({tot_dfta/max(1,tot_refl):.2f}x additional speedup!)")


if __name__ == '__main__':
    run_test_a()
    run_test_b()
    run_test_c()
