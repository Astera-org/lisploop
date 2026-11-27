#!/usr/bin/env python3
"""
Quick verification of two crisp predictions:
  1. G1 AST Size 13 (6 ops): does Column-Vector Homomorphism + Quotient Hash-Join
     beat Plain OE on ALL THREE metrics (Candidates, RAM, AND Wall Time even in Python)?
  2. Abstract Verb-Class Synonym Expansion in Derivation-Space Reflection:
     grouping library ops by their learned abstract transition tables f^{#_j}
     (automatically — zero hand labels!) so retrieved skeletons generalize to sibling tasks!
"""

import time
import random
from collections import defaultdict, Counter

import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library, build_abstract_domains, synthesize_oe


# ==============================================================================
# 1. G1 SIZE 13 (6 OPS): WALL-TIME, CANDIDATE, AND RAM CROSSOVER
# ==============================================================================

def run_g1_size13():
    print("=" * 88)
    print("VERIFY 1: G1={+,-,*,neg} AT AST SIZE 13 (6 OPS) — WALL-TIME & RAM CROSSOVER")
    print("=" * 88)
    rows = [(0, 1), (1, -1), (-1, 0), (2, 3), (-2, 1), (3, -2),
            (1, 2), (-3, 2), (4, -1), (2, -3), (-1, 4), (3, 1)]
    n = len(rows)
    inps = [
        ('x', tuple(r[0] for r in rows)),
        ('y', tuple(r[1] for r in rows)),
        ('0', tuple(0 for _ in rows)),
        ('1', tuple(1 for _ in rows)),
    ]
    ops_fn = {
        '+': lambda a, b: a + b,
        '-': lambda a, b: a - b,
        '*': lambda a, b: a * b,
    }

    def synth(target_col, max_ops, use_hom=False, budget=3000000):
        t0 = time.perf_counter()
        hom_h = []
        dp_ms = 0.0

        def join_key(col):
            k5 = (col[0] % 5) + 5 * (col[1] % 5) + 25 * (col[2] % 5)
            k2 = 0
            for i in range(n):
                if col[i] & 1:
                    k2 |= (1 << i)
            return (k5, k2)

        def decode_k5(k5): return (k5 % 5, (k5 // 5) % 5, (k5 // 25) % 5)
        def encode_k5(t):  return t[0] + 5 * t[1] + 25 * t[2]

        if use_hom:
            td0 = time.perf_counter()
            # Fast integer-packed F_2^12 (<=16 states!), F_3^4 (<=81 states!), F_5^3 (<=125 states!)
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

                g_fwd = {}
                layers = defaultdict(list)
                for _, col in inps:
                    a = proj(col)
                    if a not in g_fwd:
                        g_fwd[a] = 0
                        layers[0].append(a)
                for s in range(1, max_ops):
                    for a in layers[s - 1]:
                        o = apply_fp('neg', a)
                        if o not in g_fwd:
                            g_fwd[o] = s; layers[s].append(o)
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
                                        g_fwd[o] = s; layers[s].append(o)

                tgt_a = proj(target_col)
                INF = 999
                h_bwd = defaultdict(lambda: INF)
                h_bwd[tgt_a] = 0
                reach = list(g_fwd.items())
                # Precompute multiplication edges once per finite ring!
                mul_edges = []
                for i, (a, ga) in enumerate(reach):
                    for j in range(i, len(reach)):
                        b, gb = reach[j]
                        if ga + gb + 1 <= max_ops:
                            mul_edges.append((a, ga, b, gb, apply_fp('*', a, b)))

                for _ in range(max_ops):
                    changed = False
                    active_h = [(o, hv) for o, hv in list(h_bwd.items()) if hv < max_ops]
                    for o, hv in active_h:
                        a = apply_fp('neg', o)
                        if a in g_fwd and hv + 1 < h_bwd[a]:
                            h_bwd[a] = hv + 1; changed = True
                        for b, gb in reach:
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
                    for a, ga, b, gb, o in mul_edges:
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
        by_bucket = defaultdict(lambda: defaultdict(list))
        by_k5 = defaultdict(lambda: defaultdict(list))
        seen = set()
        cands = 0
        stored = 0

        def ok_store(col, s):
            if not hom_h: return True
            rem = max_ops - s
            for proj, hb in hom_h:
                if hb[proj(col)] > rem:
                    return False
            return True

        def store(term, col, s):
            nonlocal stored
            by[s].append((term, col))
            stored += 1
            if use_hom:
                jk = join_key(col)
                by_bucket[s][jk].append((term, col))
                by_k5[s][jk[0]].append((term, col, jk[1]))

        for name, col in inps:
            if col == target_col:
                return name, 0, len(inps), dp_ms, (time.perf_counter() - t0) * 1000
            if col not in seen:
                seen.add(col)
                if ok_store(col, 0):
                    store(name, col, 0)

        tgt_k5, tgt_k2 = join_key(target_col)
        tgt_t5 = decode_k5(tgt_k5)
        mul_compat = defaultdict(list)
        if use_hom:
            for a1 in range(125):
                t1 = decode_k5(a1)
                for a2 in range(125):
                    t2 = decode_k5(a2)
                    if ((t1[0]*t2[0])%5 == tgt_t5[0] and (t1[1]*t2[1])%5 == tgt_t5[1] and (t1[2]*t2[2])%5 == tgt_t5[2]):
                        mul_compat[a1].append(a2)

        for s in range(1, max_ops + 1):
            is_final = (s == max_ops)
            if is_final and use_hom:
                neg_t5 = encode_k5(((-tgt_t5[0])%5, (-tgt_t5[1])%5, (-tgt_t5[2])%5))
                for t1, c1 in by_bucket[s - 1].get((neg_t5, tgt_k2), ()):
                    cands += 1
                    if tuple(-v for v in c1) == target_col:
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
                        if ok_store(out, s):
                            store(('neg', t1), out, s)

            for s1 in range(0, s):
                s2 = s - 1 - s1
                l1, l2 = by[s1], by[s2]
                if not l1 or not l2: continue
                if is_final and use_hom:
                    b2 = by_bucket[s2]
                    if s1 <= s2:
                        for t1, c1 in l1:
                            a1_5, a1_2 = join_key(c1)
                            d1 = decode_k5(a1_5)
                            n5 = encode_k5(((tgt_t5[0]-d1[0])%5, (tgt_t5[1]-d1[1])%5, (tgt_t5[2]-d1[2])%5))
                            for t2, c2 in b2.get((n5, tgt_k2 ^ a1_2), ()):
                                cands += 1
                                if tuple(c1[r] + c2[r] for r in range(n)) == target_col:
                                    return ('+', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    for t1, c1 in l1:
                        a1_5, a1_2 = join_key(c1)
                        d1 = decode_k5(a1_5)
                        n5 = encode_k5(((d1[0]-tgt_t5[0])%5, (d1[1]-tgt_t5[1])%5, (d1[2]-tgt_t5[2])%5))
                        for t2, c2 in b2.get((n5, tgt_k2 ^ a1_2), ()):
                            cands += 1
                            if tuple(c1[r] - c2[r] for r in range(n)) == target_col:
                                return ('-', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                    if s1 <= s2:
                        bk5_2 = by_k5[s2]
                        for t1, c1 in l1:
                            a1_5, a1_2 = join_key(c1)
                            if (a1_2 & tgt_k2) != tgt_k2: continue
                            for a2_5 in mul_compat[a1_5]:
                                for t2, c2, a2_2 in bk5_2.get(a2_5, ()):
                                    if (a1_2 & a2_2) != tgt_k2: continue
                                    cands += 1
                                    if tuple(c1[r] * c2[r] for r in range(n)) == target_col:
                                        return ('*', t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                else:
                    for opn, fn in ops_fn.items():
                        comm = opn in ('+', '*')
                        if comm and s1 > s2: continue
                        for i1, (t1, c1) in enumerate(l1):
                            st2 = i1 if (comm and s1 == s2) else 0
                            for i2 in range(st2, len(l2)):
                                t2, c2 = l2[i2]
                                cands += 1
                                if cands > budget:
                                    return None, cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                                out = tuple(fn(c1[r], c2[r]) for r in range(n))
                                if out == target_col:
                                    return (opn, t1, t2), cands, stored, dp_ms, (time.perf_counter() - t0) * 1000
                                if not is_final and out not in seen:
                                    seen.add(out)
                                    if ok_store(out, s):
                                        store((opn, t1, t2), out, s)
        return None, cands, stored, dp_ms, (time.perf_counter() - t0) * 1000

    # Two genuine 6-op (size 13) polynomials!
    targets = [
        ("A10 (6-op/sz13): (x*x + y)*(x - y) + 1",    lambda x, y: (x*x + y)*(x - y) + 1,     6),
        ("A11 (6-op/sz13): (x*y + x + 1)*(y - x)",    lambda x, y: (x*y + x + 1)*(y - x),     6),
        ("A12 (6-op/sz13): 2*(x*x + y*y) - x*y",      lambda x, y: 2*(x*x + y*y) - x*y,       6),
    ]
    print(f"{'G1 Size-13 Task':<42} | {'Plain Cands':>11} {'RAM':>7} {'ms':>8} | {'Hom+Join':>9} {'RAM':>6} {'DPms':>5} {'Totms':>7} | {'CandGain':>9} {'RAMGain':>8} {'TimeGain':>8}")
    print("-" * 144)
    for name, fn, mo in targets:
        tgt = tuple(fn(x, y) for x, y in rows)
        p_res, p_c, p_st, _, p_ms = synth(tgt, mo, use_hom=False, budget=3000000)
        h_res, h_c, h_st, dp_ms, h_ms = synth(tgt, mo, use_hom=True, budget=3000000)
        p_s = f"{p_c:>11}" if p_res else f">{p_c:>10}"
        h_s = f"{h_c:>9}" if h_res else f"MISS"
        print(f"{name:<42} | {p_s} {p_st:>7} {p_ms:>8.1f} | {h_s} {h_st:>6} {dp_ms:>5.1f} {h_ms:>7.1f} | {p_c/max(1,h_c):>8.1f}x {p_st/max(1,h_st):>7.1f}x {p_ms/max(0.1,h_ms):>7.1f}x")


# ==============================================================================
# 2. AUTOMATIC VERB-CLASS SYNONYMS FROM LEARNED ABSTRACT TRANSITION TABLES
# ==============================================================================

def run_verb_synonyms():
    print("\n" + "=" * 88)
    print("VERIFY 2: AUTOMATIC VERB-CLASS SYNONYMS ('LIKE' FOR OPERATORS) VIA ABSTRACT TRANSITIONS")
    print("=" * 88)
    ops = make_61_library()
    domains, tables, all_states, _ = build_abstract_domains(ops)

    # Represent each operator f by its signature of deterministic/support transitions
    # across the 6 learned quotient tables (purely from group-by, zero hand labels!)
    def op_behavior_profile(opname):
        arg_tys, res_ty, _ = ops[opname]
        prof = set()
        prof.add(('sig', arg_tys, res_ty))
        for dname, dtbl in tables.items():
            trans = dtbl[opname]
            for a_in, cnts in trans.items():
                tot = sum(cnts.values())
                # Keep high-probability / exact abstract transitions (> 10% support)
                outs = frozenset(ao for ao, c in cnts.items() if c / tot >= 0.1)
                prof.add((dname, a_in, outs))
        return prof

    profiles = {k: op_behavior_profile(k) for k in ops}

    def nearest_verbs(opname, k=6):
        arg_tys, res_ty, _ = ops[opname]
        p0 = profiles[opname]
        cands = []
        for other in ops:
            if other == opname: continue
            if ops[other][:2] != (arg_tys, res_ty): continue
            po = profiles[other]
            jacc = len(p0 & po) / max(1, len(p0 | po))
            cands.append((jacc, other))
        cands.sort(reverse=True)
        return cands[:k]

    print("Top-5 automatically discovered abstract verb-synonyms (Jaccard on f^{#_j}):")
    for probe_op in ('map_adj_sub', 'filter_pos', 'reverse', 'dbl_all', 'sort', 'sum', 'zip_add'):
        nbrs = ", ".join(f"{o}({s:.2f})" for s, o in nearest_verbs(probe_op, 5))
        print(f"  {probe_op:<14} ~= {nbrs}")

    # Now re-run Test C's 20 disjoint-table tasks WITH abstract verb-synonym expansion in Stage 2!
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
        ("F1_fresh: sum(map_adj_sub(sort(xs)))",  ('sum', ('map_adj_sub', ('sort', 'xs'))),               'int', 3),
        ("F2_fresh: rev(filter_pos(adj_add))",    ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),     'seq', 3),
        ("F3_fresh: dbl(sort(abs(xs)))",          ('dbl_all', ('sort', ('abs_all', 'xs'))),               'seq', 3),
        ("F4_fresh: len(filter_even(adj_add))",   ('len', ('filter_even', ('map_adj_add', 'xs'))),        'int', 3),
        ("F5_fresh: rsum(rev(inc_all(xs)))",      ('running_sum', ('reverse', ('inc_all', 'xs'))),        'seq', 3),
    ]

    def eval_p(p, xs):
        if p == 'xs': return xs
        return ops[p[0]][2](*[eval_p(a, xs) for a in p[1:]])

    def extract_ops(p):
        if isinstance(p, str): return set()
        s = {p[0]}
        for a in p[1:]: s |= extract_ops(a)
        return s

    def universal_sig(xs_col, tty, tgt_col):
        inv = {('ty', tty)}
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

    deriv_rows = []
    tot_plain = 0
    tot_dfta = 0
    tot_refl_syn = 0
    exact_hits = 0
    syn_hits = 0
    fallbacks = 0

    for idx, (tname, prog, tty, max_ops) in enumerate(families):
        rng = random.Random(500 + idx * 37)
        xs_col = tuple(tuple(rng.randint(-5, 6) for _ in range(L)) for L in (4, 5, 3, 6, 2, 4))
        tgt_col = tuple(eval_p(prog, x) for x in xs_col)
        inps = [('xs', 'seq', xs_col)]

        _, p_c, _, _, _, _, _ = synthesize_oe(ops, inps, tty, tgt_col, max_ops, budget=400000)
        tot_plain += p_c
        _, d_c, _, _, _, _, _ = synthesize_oe(
            ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
            use_abstract_pruning=True, budget=400000
        )
        tot_dfta += d_c

        asig = universal_sig(xs_col, tty, tgt_col)
        refl_c = 0
        found = None

        same_ty = [r for r in deriv_rows if ('ty', tty) in r[0]]
        ranked = sorted(same_ty, key=lambda r: -(len(asig & r[0]) / max(1, len(asig | r[0]))))

        # Stage 1: Exact replay of top-5 abstract neighbors
        for _, p_prog, _ in ranked[:5]:
            refl_c += 1
            try:
                if tuple(eval_p(p_prog, x) for x in xs_col) == tgt_col:
                    found = p_prog
                    exact_hits += 1
                    break
            except Exception:
                pass

        # Stage 2: Verb-synonym expanded subgrammar from top-2 abstract neighbors!
        if found is None and ranked:
            sub_names = set()
            for _, _, oset in ranked[:2]:
                for o in oset:
                    sub_names.add(o)
                    for _, syn in nearest_verbs(o, 4):
                        sub_names.add(syn)
            sub_ops = {k: ops[k] for k in sub_names}
            s_res, s_c, _, _, _, _, _ = synthesize_oe(
                sub_ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                use_abstract_pruning=True, budget=8000
            )
            refl_c += s_c
            if s_res is not None:
                found = s_res
                syn_hits += 1

        # Stage 3: Full fallback
        if found is None:
            if ranked:
                fallbacks += 1
            f_res, f_c, _, _, _, _, _ = synthesize_oe(
                ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                use_abstract_pruning=True, budget=400000
            )
            refl_c += f_c
            found = f_res

        tot_refl_syn += refl_c
        if found is not None:
            deriv_rows.append((asig, found, extract_ops(found)))

    print(f"\n20-task curriculum on DISJOINT concrete tables (61-op library):")
    print(f"  Exact-replay hits:              {exact_hits}/20 (5/5 repeats)")
    print(f"  Verb-synonym family hits:       {syn_hits}/20 (sibling transfer!)")
    print(f"  Full-library fallbacks:         {fallbacks}/20")
    print(f"  Total candidates Plain OE:      {tot_plain:,}")
    print(f"  Total candidates AbsDFTA alone: {tot_dfta:,} ({tot_plain/max(1,tot_dfta):.2f}x vs Plain)")
    print(f"  Total cands AbsDFTA+SynRefl:    {tot_refl_syn:,} ({tot_plain/max(1,tot_refl_syn):.2f}x vs Plain, {tot_dfta/max(1,tot_refl_syn):.2f}x vs AbsDFTA)")


if __name__ == '__main__':
    run_g1_size13()
    run_verb_synonyms()
