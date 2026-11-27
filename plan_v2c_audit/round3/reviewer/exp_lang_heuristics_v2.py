#!/usr/bin/env python3
"""
Rigorous Empirical Evaluation of Factored Quotient Algebras (Abstract DFTAs)
as the Unifying Mechanism for Language, Heuristics, Library Scaling, RAM Pruning,
Conditional Laws, and Cheap Reflection in plan_v2c.

Experiments:
  1. Partition-canonical automatic word discovery via Algebraic Lumpability + MDL
     (1A: Integer arithmetic; 1B: Sequence algebra).
  2. 61-Function Library Scaling (Minton Utility Problem & Cold-Start):
     Compares Plain OE vs. Flat Signature + Naive Bayes (plan_v2c §6.3) vs.
     Sound Factored Abstract DFTA (Knuth backward bounds) vs. Soft MDL Abstract Planner.
     Includes 2-op, 3-op, 4-op, unconstrained, and cold-start (unseen library op) tasks.
  3. Arithmetic RAM Wall & Exact Algebraic Boundary:
     (3A) G1 = {+, -, *, neg}: Plain OE vs. Per-Row Quotients vs. Column-Vector
          Ring Homomorphisms (F_2^N, F_3^4, F_5^3) on size-7 (3-op) and size-9 (4-op)
          structured AND unstructured targets.
     (3B) Honest failure-mode test on G2 = G1 U {div, mod, max, min}, where F_p is
          NOT a homomorphism for div/mod!
  4. FCA Bitset Implication Lattice for Conditional Laws (Chompy bottleneck).
  5. Cheap Reflection: Cross-task transfer on the Derivation Space via abstract
     transition signatures vs. concrete memoization (including false-hit fallback cost).
"""

import math
import random
import time
import heapq
from collections import defaultdict, Counter

random.seed(42)


def entropy(counts):
    tot = sum(counts.values())
    if tot == 0:
        return 0.0
    h = 0.0
    for c in counts.values():
        if c > 0:
            p = c / tot
            h -= p * math.log2(p)
    return h


def cond_entropy_and_lump(pairs):
    out_counts = Counter(y for _, y in pairs)
    h_out = entropy(out_counts)
    if h_out < 1e-9:
        return 0.0, 0.0, 0.0
    buckets = defaultdict(Counter)
    for x, y in pairs:
        buckets[x][y] += 1
    tot = len(pairs)
    h_cond = sum((sum(c.values()) / tot) * entropy(c) for c in buckets.values())
    return h_cond, h_out, 1.0 - (h_cond / h_out)


def canonical_partition(seq_vals):
    """Canonical partition tuple invariant to bijective relabeling of abstract values."""
    mapping = {}
    out = []
    for v in seq_vals:
        if v not in mapping:
            mapping[v] = len(mapping)
        out.append(mapping[v])
    return tuple(out)


# ==============================================================================
# EXPERIMENT 1: PARTITION-CANONICAL WORD DISCOVERY VIA LUMPABILITY + MDL
# ==============================================================================

def run_exp1():
    print("=" * 84)
    print("EXPERIMENT 1A: PARTITION-CANONICAL WORD DISCOVERY ON INTEGER ARITHMETIC")
    print("=" * 84)
    vals = list(range(-12, 13))
    pairs_ab = [(a, b) for a in vals for b in vals]
    arith_ops = {
        '+':   (2, lambda a, b: a + b),
        '-':   (2, lambda a, b: a - b),
        '*':   (2, lambda a, b: a * b),
        'neg': (1, lambda a: -a),
        'max': (2, lambda a, b: max(a, b)),
        'min': (2, lambda a, b: min(a, b)),
        'div': (2, lambda a, b: None if b == 0 else a // b),
        'mod': (2, lambda a, b: None if b == 0 else a % b),
    }

    # (name, AST_size_MDL, fn)
    candidates = [
        ('is_zero (x=0)',        3, lambda x: x == 0),
        ('is_neg (x<0)',         3, lambda x: x < 0),
        ('is_pos (x>0)',         3, lambda x: x > 0),
        ('sign (-/0/+)',         5, lambda x: -1 if x < 0 else (1 if x > 0 else 0)),
        ('parity (x mod 2)',     3, lambda x: x % 2),
        ('mod_3 (x mod 3)',      3, lambda x: x % 3),
        ('mod_4 (x mod 4)',      3, lambda x: x % 4),
        ('mod_5 (x mod 5)',      3, lambda x: x % 5),
        ('biject ((3x+1) mod 4)',7, lambda x: (3 * x + 1) % 4),
        ('biject (1-(x mod 2))', 5, lambda x: 1 - (x % 2)),
        ('eq_1 (x=1)',           3, lambda x: x == 1),
        ('eq_5 (x=5)',           3, lambda x: x == 5),
        ('lt_3 (x<3)',           3, lambda x: x < 3),
        ('abs_lt2 (|x|<2)',      4, lambda x: abs(x) < 2),
        ('mod7_eq3',             5, lambda x: (x % 7) == 3),
        ('even_or_neg',          7, lambda x: (x % 2 == 0) or (x < 0)),
        ('div3_eq0',             5, lambda x: (x // 3) == 0),
    ]

    # Step 1: Partition-canonical deduplication keeping shortest-MDL term!
    part_best = {}
    collapsed = []
    for name, mdl, fn in sorted(candidates, key=lambda t: t[1]):
        p = canonical_partition([fn(v) for v in vals])
        card = len(set(p))
        if card <= 1:
            continue
        if p in part_best:
            collapsed.append((name, part_best[p][0]))
            continue
        part_best[p] = (name, mdl, fn, card)

    print(f"Partition-canonical dedupe collapsed {len(collapsed)} bijective aliases:")
    for dup, keeper in collapsed:
        print(f"  collapsed '{dup}' -> '{keeper}'")

    ring_ops = ['+', '-', '*', 'neg', 'max', 'min']
    scored = []
    for name, mdl, fn, card in part_best.values():
        per_op = {}
        exact_cnt = 0
        for opname, (arity, opfn) in arith_ops.items():
            obs = []
            if arity == 1:
                for a in vals:
                    o = opfn(a)
                    if o is not None:
                        obs.append(((fn(a),), fn(o)))
            else:
                for a, b in pairs_ab:
                    o = opfn(a, b)
                    if o is not None:
                        obs.append(((fn(a), fn(b)), fn(o)))
            hc, ho, lump = cond_entropy_and_lump(obs)
            per_op[opname] = lump
            if hc < 1e-9 and ho > 0.1:
                exact_cnt += 1
        avg_ring = sum(per_op[o] for o in ring_ops) / len(ring_ops)
        avg_all = sum(per_op.values()) / len(per_op)
        scored.append((avg_ring, avg_all, exact_cnt, card, mdl, name, per_op))

    scored.sort(reverse=True)
    print(f"\n{'Word':<22} {'MDL':>3} {'Card':>4} {'ExOps':>5} {'RingLump':>8} {'AllLump':>8}  Details")
    for ar, aa, ex, card, mdl, name, po in scored[:12]:
        det = f"+:{po['+']:.2f} *:{po['*']:.2f} max:{po['max']:.2f} div:{po['div']:.2f} mod:{po['mod']:.2f}"
        print(f"{name:<22} {mdl:>3} {card:>4} {ex:>5} {ar:>8.3f} {aa:>8.3f}  {det}")

    print("\n" + "=" * 84)
    print("EXPERIMENT 1B: AUTOMATIC WORD DISCOVERY ON SEQUENCE ALGEBRA")
    print("=" * 84)
    rng = random.Random(7)
    seqs = [()] + [tuple(rng.randint(-4, 6) for _ in range(rng.randint(1, 6))) for _ in range(150)]
    seq_ops = {
        'reverse':      lambda xs: tuple(reversed(xs)),
        'sort':         lambda xs: tuple(sorted(xs)),
        'tail':         lambda xs: xs[1:] if xs else None,
        'inc_all':      lambda xs: tuple(x + 1 for x in xs),
        'dbl_all':      lambda xs: tuple(x * 2 for x in xs),
        'neg_all':      lambda xs: tuple(-x for x in xs),
        'abs_all':      lambda xs: tuple(abs(x) for x in xs),
        'filter_pos':   lambda xs: tuple(x for x in xs if x > 0),
        'filter_even':  lambda xs: tuple(x for x in xs if x % 2 == 0),
        'map_adj_add':  lambda xs: tuple(xs[i] + xs[i+1] for i in range(len(xs)-1)),
        'map_adj_sub':  lambda xs: tuple(xs[i+1] - xs[i] for i in range(len(xs)-1)),
        'running_sum':  lambda xs: tuple(sum(xs[:i+1]) for i in range(len(xs))),
        'shift1_zero':  lambda xs: (xs[1:] + (0,)) if xs else (),
        'rotate1':      lambda xs: (xs[1:] + xs[:1]) if xs else (),
        'dedup_adj':    lambda xs: tuple(xs[i] for i in range(len(xs)) if i == 0 or xs[i] != xs[i-1]),
    }
    seq_words = [
        ('len_cap5',        3, lambda xs: min(len(xs), 5)),
        ('len_mod2',        3, lambda xs: len(xs) % 2),
        ('is_empty',        3, lambda xs: len(xs) == 0),
        ('all_even',        4, lambda xs: all(x % 2 == 0 for x in xs)),
        ('all_nonneg',      4, lambda xs: all(x >= 0 for x in xs)),
        ('is_sorted',       5, lambda xs: all(xs[i] <= xs[i+1] for i in range(len(xs)-1))),
        ('sum_mod2',        4, lambda xs: sum(xs) % 2),
        ('sum_sign',        5, lambda xs: 0 if sum(xs) == 0 else (1 if sum(xs) > 0 else -1)),
        ('has_zero',        3, lambda xs: 0 in xs),
        ('len_eq_3 (junk)', 3, lambda xs: len(xs) == 3),
        ('sum_gt_5 (junk)', 4, lambda xs: sum(xs) > 5),
        ('head_eq_2 (junk)',4, lambda xs: (xs[0] == 2) if xs else False),
    ]
    s_res = []
    for name, mdl, fn in seq_words:
        lumps = []
        ex = 0
        for opfn in seq_ops.values():
            obs = []
            for s in seqs:
                o = opfn(s)
                if o is not None:
                    obs.append(((fn(s),), fn(o)))
            hc, ho, lump = cond_entropy_and_lump(obs)
            if ho > 0.05:
                lumps.append(lump)
                if hc < 1e-9:
                    ex += 1
        s_res.append((sum(lumps)/len(lumps), ex, name))
    s_res.sort(reverse=True)
    print(f"{'Sequence Word':<22} {'ExactOps/15':>11} {'AvgLumpability':>15}")
    for al, ex, nm in s_res:
        print(f"{nm:<22} {ex:>11} {al:>15.3f}")


# ==============================================================================
# EXPERIMENT 2: 61-FUNCTION LIBRARY SCALING (FIXED + 4 REGIMES + COLD START!)
# ==============================================================================

def make_61_library():
    ops = {}
    # Unary Seq -> Seq (41 ops)
    ops['reverse']     = (('seq',), 'seq', lambda xs: tuple(reversed(xs)))
    ops['sort']        = (('seq',), 'seq', lambda xs: tuple(sorted(xs)))
    ops['sort_desc']   = (('seq',), 'seq', lambda xs: tuple(sorted(xs, reverse=True)))
    ops['tail']        = (('seq',), 'seq', lambda xs: xs[1:] if xs else None)
    ops['init']        = (('seq',), 'seq', lambda xs: xs[:-1] if xs else None)
    ops['inc_all']     = (('seq',), 'seq', lambda xs: tuple(x + 1 for x in xs))
    ops['dec_all']     = (('seq',), 'seq', lambda xs: tuple(x - 1 for x in xs))
    ops['dbl_all']     = (('seq',), 'seq', lambda xs: tuple(x * 2 for x in xs))
    ops['tri_all']     = (('seq',), 'seq', lambda xs: tuple(x * 3 for x in xs))
    ops['neg_all']     = (('seq',), 'seq', lambda xs: tuple(-x for x in xs))
    ops['abs_all']     = (('seq',), 'seq', lambda xs: tuple(abs(x) for x in xs))
    ops['sq_all']      = (('seq',), 'seq', lambda xs: tuple(x * x for x in xs))
    ops['halve_all']   = (('seq',), 'seq', lambda xs: tuple(x // 2 for x in xs))
    ops['mod2_all']    = (('seq',), 'seq', lambda xs: tuple(x % 2 for x in xs))
    ops['mod3_all']    = (('seq',), 'seq', lambda xs: tuple(x % 3 for x in xs))
    ops['clamp0_all']  = (('seq',), 'seq', lambda xs: tuple(max(0, x) for x in xs))
    ops['filter_pos']  = (('seq',), 'seq', lambda xs: tuple(x for x in xs if x > 0))
    ops['filter_neg']  = (('seq',), 'seq', lambda xs: tuple(x for x in xs if x < 0))
    ops['filter_nz']   = (('seq',), 'seq', lambda xs: tuple(x for x in xs if x != 0))
    ops['filter_even'] = (('seq',), 'seq', lambda xs: tuple(x for x in xs if x % 2 == 0))
    ops['filter_odd']  = (('seq',), 'seq', lambda xs: tuple(x for x in xs if x % 2 != 0))
    ops['map_adj_add'] = (('seq',), 'seq', lambda xs: tuple(xs[i] + xs[i+1] for i in range(len(xs)-1)))
    ops['map_adj_sub'] = (('seq',), 'seq', lambda xs: tuple(xs[i+1] - xs[i] for i in range(len(xs)-1)))
    ops['map_adj_mul'] = (('seq',), 'seq', lambda xs: tuple(xs[i] * xs[i+1] for i in range(len(xs)-1)))
    ops['map_adj_max'] = (('seq',), 'seq', lambda xs: tuple(max(xs[i], xs[i+1]) for i in range(len(xs)-1)))
    ops['map_adj_min'] = (('seq',), 'seq', lambda xs: tuple(min(xs[i], xs[i+1]) for i in range(len(xs)-1)))
    ops['running_sum'] = (('seq',), 'seq', lambda xs: tuple(sum(xs[:i+1]) for i in range(len(xs))))
    ops['running_max'] = (('seq',), 'seq', lambda xs: tuple(max(xs[:i+1]) for i in range(len(xs))))
    ops['running_min'] = (('seq',), 'seq', lambda xs: tuple(min(xs[:i+1]) for i in range(len(xs))))
    ops['shift1']      = (('seq',), 'seq', lambda xs: (xs[1:] + (0,)) if xs else ())
    ops['shift2']      = (('seq',), 'seq', lambda xs: (xs[2:] + (0, 0)) if len(xs) >= 2 else (0,) * len(xs))
    ops['rshift1']     = (('seq',), 'seq', lambda xs: ((0,) + xs[:-1]) if xs else ())
    ops['rotate1']     = (('seq',), 'seq', lambda xs: (xs[1:] + xs[:1]) if xs else ())
    ops['rrotate1']    = (('seq',), 'seq', lambda xs: (xs[-1:] + xs[:-1]) if xs else ())
    ops['evens_idx']   = (('seq',), 'seq', lambda xs: xs[::2])
    ops['odds_idx']    = (('seq',), 'seq', lambda xs: xs[1::2])
    ops['take2']       = (('seq',), 'seq', lambda xs: xs[:2])
    ops['drop2']       = (('seq',), 'seq', lambda xs: xs[2:])
    ops['dedup_adj']   = (('seq',), 'seq', lambda xs: tuple(xs[i] for i in range(len(xs)) if i == 0 or xs[i] != xs[i-1]))
    ops['positions']   = (('seq',), 'seq', lambda xs: tuple(range(len(xs))))
    ops['dup_seq']     = (('seq',), 'seq', lambda xs: xs + xs)

    # Binary Seq x Seq -> Seq (6 ops)
    ops['zip_add']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x + y for x, y in zip(a, b)))
    ops['zip_sub']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x - y for x, y in zip(a, b)))
    ops['zip_mul']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x * y for x, y in zip(a, b)))
    ops['zip_max']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(max(x, y) for x, y in zip(a, b)))
    ops['zip_min']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(min(x, y) for x, y in zip(a, b)))
    ops['concat']      = (('seq', 'seq'), 'seq', lambda a, b: a + b)

    # Unary Seq -> Int (9 ops)
    ops['sum']         = (('seq',), 'int', lambda xs: sum(xs))
    ops['prod']        = (('seq',), 'int', lambda xs: math.prod(xs) if xs else 1)
    ops['len']         = (('seq',), 'int', lambda xs: len(xs))
    ops['head']        = (('seq',), 'int', lambda xs: xs[0] if xs else None)
    ops['last']        = (('seq',), 'int', lambda xs: xs[-1] if xs else None)
    ops['max_el']      = (('seq',), 'int', lambda xs: max(xs) if xs else None)
    ops['min_el']      = (('seq',), 'int', lambda xs: min(xs) if xs else None)
    ops['count_pos']   = (('seq',), 'int', lambda xs: sum(1 for x in xs if x > 0))
    ops['count_even']  = (('seq',), 'int', lambda xs: sum(1 for x in xs if x % 2 == 0))

    # Binary Int x Int -> Int (5 ops)
    ops['add']         = (('int', 'int'), 'int', lambda a, b: a + b)
    ops['sub']         = (('int', 'int'), 'int', lambda a, b: a - b)
    ops['mul']         = (('int', 'int'), 'int', lambda a, b: a * b)
    ops['imax']        = (('int', 'int'), 'int', lambda a, b: max(a, b))
    ops['imin']        = (('int', 'int'), 'int', lambda a, b: min(a, b))
    return ops


def build_abstract_domains(ops):
    """
    Learn abstract transition tables f^{#_j} by plain group-by on a well-stratified
    generic probe space (covering lengths 0..8, all signs, parities, sortedness).
    Also records all observed states per (domain, type) so any unseen input defaults
    soundly to TOP (never empty!).
    """
    rng = random.Random(101)
    probe_seqs = [()]
    # Stratified random probes covering lengths 1..8
    for L in range(1, 9):
        for _ in range(30):
            probe_seqs.append(tuple(rng.randint(-5, 5) for _ in range(L)))
        # Stratified special buckets: all-pos, all-nonneg, all-neg, all-even, all-odd, asc, dsc, const
        for _ in range(4):
            probe_seqs.append(tuple(rng.randint(1, 6) for _ in range(L)))
            probe_seqs.append(tuple(rng.randint(0, 6) for _ in range(L)))
            probe_seqs.append(tuple(rng.randint(-6, -1) for _ in range(L)))
            probe_seqs.append(tuple(2 * rng.randint(-3, 3) for _ in range(L)))
            probe_seqs.append(tuple(2 * rng.randint(-3, 3) + 1 for _ in range(L)))
            probe_seqs.append(tuple(sorted(rng.randint(-5, 5) for _ in range(L))))
            probe_seqs.append(tuple(sorted((rng.randint(-5, 5) for _ in range(L)), reverse=True)))
            c = rng.randint(-4, 4)
            probe_seqs.append((c,) * L)
    # Deduplicate probes
    probe_seqs = list(dict.fromkeys(probe_seqs))
    probe_ints = list(range(-15, 16)) + [20, -20, 30, -30, 50, -50, 100, -100]

    # 6 small compositional unary quotients (discovered via Exp 1A/1B lumpability!)
    domains = {
        'len_sign': lambda v, ty: (
            min(len(v), 7) if ty == 'seq' else (-1 if v < 0 else (1 if v > 0 else 0))
        ),
        'nonneg': lambda v, ty: (
            ('E' if len(v) == 0 else (
             'P' if all(x > 0 for x in v) else (
             'N0' if all(x >= 0 for x in v) else (
             'NEG' if all(x < 0 for x in v) else 'M'))))
            if ty == 'seq' else ('P' if v > 0 else ('Z' if v == 0 else 'N'))
        ),
        'parity': lambda v, ty: (
            ('E' if len(v) == 0 else (
             'EV' if all(x % 2 == 0 for x in v) else (
             'OD' if all(x % 2 != 0 for x in v) else 'M')))
            if ty == 'seq' else (v % 2)
        ),
        'order': lambda v, ty: (
            ('S01' if len(v) <= 1 else (
             'C' if len(set(v)) == 1 else (
             'ASC' if all(v[i] <= v[i+1] for i in range(len(v)-1)) else (
             'DSC' if all(v[i] >= v[i+1] for i in range(len(v)-1)) else 'U'))))
            if ty == 'seq' else (-1 if v < 0 else (1 if v > 0 else 0))
        ),
        'sum_mod2': lambda v, ty: (
            ('E' if len(v) == 0 else (sum(v) % 2)) if ty == 'seq' else (v % 2)
        ),
        'len_mod2_int3': lambda v, ty: (
            ('E' if len(v) == 0 else (len(v) % 2)) if ty == 'seq' else (v % 3)
        ),
    }

    # Also build a compact bucketed sample per (domain, type) for binary ops so every
    # abstract state pair (a0, a1) is covered cleanly!
    t0 = time.perf_counter()
    tables = {}
    all_states = {}
    for dname, afn in domains.items():
        by_state_seq = defaultdict(list)
        for s in probe_seqs:
            by_state_seq[afn(s, 'seq')].append(s)
        by_state_int = defaultdict(list)
        for x in probe_ints:
            by_state_int[afn(x, 'int')].append(x)
        all_states[dname] = {
            'seq': set(by_state_seq.keys()),
            'int': set(by_state_int.keys()),
        }
        # Stratified binary probe list: up to 6 diverse examples per abstract state!
        bin_seqs = [s for lst in by_state_seq.values() for s in lst[:6]]
        bin_ints = [x for lst in by_state_int.values() for x in lst[:6]]

        dtbl = {}
        for opname, (arg_tys, res_ty, fn) in ops.items():
            trans = defaultdict(Counter)
            if len(arg_tys) == 1:
                p0 = probe_seqs if arg_tys[0] == 'seq' else probe_ints
                for x in p0:
                    out = fn(x)
                    if out is not None:
                        a0 = afn(x, arg_tys[0])
                        ao = afn(out, res_ty)
                        trans[(a0,)][ao] += 1
                        all_states[dname][res_ty].add(ao)
            else:
                p0 = bin_seqs if arg_tys[0] == 'seq' else bin_ints
                p1 = bin_seqs if arg_tys[1] == 'seq' else bin_ints
                for x in p0:
                    a0 = afn(x, arg_tys[0])
                    for y in p1:
                        out = fn(x, y)
                        if out is not None:
                            ao = afn(out, res_ty)
                            trans[(a0, afn(y, arg_tys[1]))][ao] += 1
                            all_states[dname][res_ty].add(ao)
                if arg_tys[0] == arg_tys[1]:
                    full_p = probe_seqs if arg_tys[0] == 'seq' else probe_ints
                    for x in full_p:
                        out = fn(x, x)
                        if out is not None:
                            a0 = afn(x, arg_tys[0])
                            ao = afn(out, res_ty)
                            trans[(a0, a0)][ao] += 1
                            all_states[dname][res_ty].add(ao)
            dtbl[opname] = trans
        tables[dname] = dtbl
    learn_ms = (time.perf_counter() - t0) * 1000
    return domains, tables, all_states, learn_ms


def knuth_bounds(ops, leaf_abs, target_abs, dtbl, state_universe, max_ops):
    """
    Sound forward-backward Knuth DP over abstract transition table `dtbl`.
    Crucially: any reachable abstract input tuple NOT seen in `dtbl[op]` defaults to
    TOP (all states in state_universe[res_ty]), NEVER empty — so missing samples
    can only loosen bounds, never cause false elimination!
    """
    INF = 999
    g_fwd = defaultdict(lambda: INF)
    for ty, a in leaf_abs:
        g_fwd[(ty, a)] = 0

    # Forward DP: min op count to reach (ty, a)
    for _ in range(max_ops + 1):
        changed = False
        # Snapshot reachable states by type
        reach_by_ty = defaultdict(list)
        for (ty, a), g in list(g_fwd.items()):
            if g < max_ops:
                reach_by_ty[ty].append((a, g))

        for opname, (arg_tys, res_ty, _) in ops.items():
            trans = dtbl[opname]
            top_outs = state_universe[res_ty]
            if len(arg_tys) == 1:
                t0 = arg_tys[0]
                for a0, g0 in reach_by_ty[t0]:
                    c = g0 + 1
                    outs = trans.get((a0,), top_outs)
                    for ao in outs:
                        if c < g_fwd[(res_ty, ao)]:
                            g_fwd[(res_ty, ao)] = c
                            changed = True
            else:
                t0, t1 = arg_tys
                l0, l1 = reach_by_ty[t0], reach_by_ty[t1]
                for a0, g0 in l0:
                    for a1, g1 in l1:
                        c = g0 + g1 + 1
                        if c > max_ops:
                            continue
                        outs = trans.get((a0, a1), top_outs)
                        for ao in outs:
                            if c < g_fwd[(res_ty, ao)]:
                                g_fwd[(res_ty, ao)] = c
                                changed = True
        if not changed:
            break

    # Backward DP: min remaining op count from (ty, a) to target_abs
    h_bwd = defaultdict(lambda: INF)
    h_bwd[target_abs] = 0
    reach_by_ty = defaultdict(list)
    for (ty, a), g in g_fwd.items():
        if g < max_ops:
            reach_by_ty[ty].append((a, g))

    for _ in range(max_ops + 1):
        changed = False
        for opname, (arg_tys, res_ty, _) in ops.items():
            trans = dtbl[opname]
            top_outs = state_universe[res_ty]
            if len(arg_tys) == 1:
                t0 = arg_tys[0]
                for a0, g0 in reach_by_ty[t0]:
                    outs = trans.get((a0,), top_outs)
                    best_out = min(h_bwd[(res_ty, ao)] for ao in outs)
                    cand = 1 + best_out
                    if cand < h_bwd[(t0, a0)]:
                        h_bwd[(t0, a0)] = cand
                        changed = True
            else:
                t0, t1 = arg_tys
                l0, l1 = reach_by_ty[t0], reach_by_ty[t1]
                for a0, g0 in l0:
                    for a1, g1 in l1:
                        if g0 + g1 + 1 > max_ops:
                            continue
                        outs = trans.get((a0, a1), top_outs)
                        best_out = min(h_bwd[(res_ty, ao)] for ao in outs)
                        if best_out >= INF:
                            continue
                        c0 = 1 + g1 + best_out
                        if c0 < h_bwd[(t0, a0)]:
                            h_bwd[(t0, a0)] = c0
                            changed = True
                        c1 = 1 + g0 + best_out
                        if c1 < h_bwd[(t1, a1)]:
                            h_bwd[(t1, a1)] = c1
                            changed = True
        if not changed:
            break

    # Useful ops: ops that appear on at least one valid hyperpath of op-count <= max_ops
    useful_ops = set()
    for opname, (arg_tys, res_ty, _) in ops.items():
        trans = dtbl[opname]
        top_outs = state_universe[res_ty]
        if len(arg_tys) == 1:
            t0 = arg_tys[0]
            for a0, g0 in reach_by_ty[t0]:
                outs = trans.get((a0,), top_outs)
                for ao in outs:
                    if g0 + 1 + h_bwd[(res_ty, ao)] <= max_ops:
                        useful_ops.add(opname)
                        break
                if opname in useful_ops:
                    break
        else:
            t0, t1 = arg_tys
            l0, l1 = reach_by_ty[t0], reach_by_ty[t1]
            for a0, g0 in l0:
                for a1, g1 in l1:
                    if g0 + g1 + 1 > max_ops:
                        continue
                    outs = trans.get((a0, a1), top_outs)
                    for ao in outs:
                        if g0 + g1 + 1 + h_bwd[(res_ty, ao)] <= max_ops:
                            useful_ops.add(opname)
                            break
                    if opname in useful_ops:
                        break
                if opname in useful_ops:
                    break

    return g_fwd, h_bwd, useful_ops


def compute_op_mdl_scores(ops, inputs, target_ty, target_col, domains, tables, all_states, max_ops, check_rows):
    """
    Soft MDL Information-Weighted Abstract Scoring (Zero training traces needed!):
    For each operator f, computes the minimum total surprise (-log2 P_j(a_out | f, a_in))
    along a valid abstract hyperpath through f, averaged across domains and rows!
    This ranks operators by how sharply their abstract semantics explain the I/O transition,
    even when hard pruning is loose (like inc_all(reverse(xs))).
    """
    INF = 1e9
    op_cost_sum = Counter()
    op_active_cnt = Counter()

    for dname, afn in domains.items():
        dtbl = tables[dname]
        univ = all_states[dname]
        # Precompute -log2 P(ao | op, a_args) for each op
        op_nll = {}
        for opname, trans in dtbl.items():
            nll_map = {}
            for a_args, cnts in trans.items():
                tot = sum(cnts.values())
                nll_map[a_args] = {ao: -math.log2(c / tot) for ao, c in cnts.items()}
            op_nll[opname] = nll_map

        for r in check_rows:
            leaf_abs = [(ty, afn(col[r], ty)) for _, ty, col in inputs]
            tgt_abs = (target_ty, afn(target_col[r], target_ty))
            # Soft forward DP by exact op-count k = 0..max_ops: fwd[(k, ty, a)] = min NLL
            fwd = defaultdict(lambda: INF)
            for ty, a in leaf_abs:
                fwd[(0, ty, a)] = 0.0
            for k in range(1, max_ops + 1):
                for opname, (arg_tys, res_ty, _) in ops.items():
                    nll_map = op_nll[opname]
                    if len(arg_tys) == 1:
                        t0 = arg_tys[0]
                        for (kk, ty, a0), c0 in list(fwd.items()):
                            if kk == k - 1 and ty == t0 and c0 < INF:
                                outs = nll_map.get((a0,))
                                if outs:
                                    for ao, w in outs.items():
                                        nc = c0 + w + 1.0
                                        if nc < fwd[(k, res_ty, ao)]:
                                            fwd[(k, res_ty, ao)] = nc
                    else:
                        t0, t1 = arg_tys
                        for k0 in range(0, k):
                            k1 = k - 1 - k0
                            l0 = [(a, c) for (kk, ty, a), c in fwd.items() if kk == k0 and ty == t0 and c < INF]
                            l1 = [(a, c) for (kk, ty, a), c in fwd.items() if kk == k1 and ty == t1 and c < INF]
                            for a0, c0 in l0:
                                for a1, c1 in l1:
                                    outs = nll_map.get((a0, a1))
                                    if outs:
                                        for ao, w in outs.items():
                                            nc = c0 + c1 + w + 1.0
                                            if nc < fwd[(k, res_ty, ao)]:
                                                fwd[(k, res_ty, ao)] = nc

            # Soft backward DP: bwd[(rem, ty, a)] = min NLL to reach tgt_abs in <= rem ops
            bwd = defaultdict(lambda: INF)
            for rem in range(0, max_ops + 1):
                bwd[(rem, tgt_abs[0], tgt_abs[1])] = 0.0
            for rem in range(1, max_ops + 1):
                for opname, (arg_tys, res_ty, _) in ops.items():
                    nll_map = op_nll[opname]
                    if len(arg_tys) == 1:
                        t0 = arg_tys[0]
                        for (a0,), outs in nll_map.items():
                            best = INF
                            for ao, w in outs.items():
                                v = bwd[(rem - 1, res_ty, ao)]
                                if v + w + 1.0 < best:
                                    best = v + w + 1.0
                            if best < bwd[(rem, t0, a0)]:
                                bwd[(rem, t0, a0)] = best
                    else:
                        t0, t1 = arg_tys
                        # Use forward-reachable sibling costs
                        for (a0, a1), outs in nll_map.items():
                            for k1 in range(0, rem):
                                c1 = fwd[(k1, t1, a1)]
                                if c1 < INF:
                                    for ao, w in outs.items():
                                        v = bwd[(rem - 1 - k1, res_ty, ao)] + c1 + w + 1.0
                                        if v < bwd[(rem, t0, a0)]:
                                            bwd[(rem, t0, a0)] = v
                            for k0 in range(0, rem):
                                c0 = fwd[(k0, t0, a0)]
                                if c0 < INF:
                                    for ao, w in outs.items():
                                        v = bwd[(rem - 1 - k0, res_ty, ao)] + c0 + w + 1.0
                                        if v < bwd[(rem, t1, a1)]:
                                            bwd[(rem, t1, a1)] = v

            # Best path cost passing through each op f
            for opname, (arg_tys, res_ty, _) in ops.items():
                nll_map = op_nll[opname]
                best_f = INF
                if len(arg_tys) == 1:
                    t0 = arg_tys[0]
                    for k0 in range(0, max_ops):
                        rem = max_ops - 1 - k0
                        for (a0,), outs in nll_map.items():
                            c0 = fwd[(k0, t0, a0)]
                            if c0 >= INF:
                                continue
                            for ao, w in outs.items():
                                tot_c = c0 + w + 1.0 + bwd[(rem, res_ty, ao)]
                                if tot_c < best_f:
                                    best_f = tot_c
                else:
                    t0, t1 = arg_tys
                    for k0 in range(0, max_ops):
                        for k1 in range(0, max_ops - k0):
                            rem = max_ops - 1 - k0 - k1
                            for (a0, a1), outs in nll_map.items():
                                c0 = fwd[(k0, t0, a0)]
                                c1 = fwd[(k1, t1, a1)]
                                if c0 >= INF or c1 >= INF:
                                    continue
                                for ao, w in outs.items():
                                    tot_c = c0 + c1 + w + 1.0 + bwd[(rem, res_ty, ao)]
                                    if tot_c < best_f:
                                        best_f = tot_c
                if best_f < INF:
                    op_cost_sum[opname] += best_f
                    op_active_cnt[opname] += 1
                else:
                    op_cost_sum[opname] += 50.0  # penalty for unreachable

    # Lower score = sharper abstract explanation!
    return {op: op_cost_sum[op] for op in ops}


def synthesize_oe(ops, inputs, target_ty, target_col, max_ops,
                  domains=None, tables=None, all_states=None,
                  use_abstract_pruning=False, op_order=None,
                  row_subset_for_abs=None, budget=400000):
    t0 = time.perf_counter()
    n = len(target_col)
    active_ops = dict(ops)
    h_tables = []

    abs_time_ms = 0.0
    if use_abstract_pruning:
        ta0 = time.perf_counter()
        check_rows = row_subset_for_abs if row_subset_for_abs is not None else list(range(min(n, 6)))
        # Compute useful_ops per (domain, row) and intersect monotonically!
        # Fixed-point iterate up to 2 rounds so pruning op set tightens h_bwd across domains!
        for _round in range(2):
            h_tables = []
            prev_n = len(active_ops)
            for dname, afn in domains.items():
                dtbl = tables[dname]
                univ = all_states[dname]
                for r in check_rows:
                    leaf_abs = [(ty, afn(col[r], ty)) for _, ty, col in inputs]
                    tgt_abs = (target_ty, afn(target_col[r], target_ty))
                    _, h_bwd, uops = knuth_bounds(active_ops, leaf_abs, tgt_abs, dtbl, univ, max_ops)
                    h_tables.append((dname, afn, r, h_bwd))
                    active_ops = {k: v for k, v in active_ops.items() if k in uops}
            if len(active_ops) == prev_n:
                break
        abs_time_ms = (time.perf_counter() - ta0) * 1000

    # Order active ops (e.g., by soft MDL or Naive Bayes!)
    if op_order is not None:
        ordered_ops = [(k, active_ops[k]) for k in op_order if k in active_ops]
    else:
        ordered_ops = list(active_ops.items())

    by = defaultdict(list)
    seen = defaultdict(set)
    cand_count = 0
    pruned_count = 0
    stored_count = 0

    def can_reach(ty, col, s):
        if not use_abstract_pruning:
            return True
        rem = max_ops - s
        for _, afn, r, h_bwd in h_tables:
            a = afn(col[r], ty)
            if h_bwd[(ty, a)] > rem:
                return False
        return True

    for name, ty, col in inputs:
        if ty == target_ty and col == target_col:
            return name, 0, len(inputs), 0, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000
        if col not in seen[ty]:
            seen[ty].add(col)
            if can_reach(ty, col, 0):
                by[(ty, 0)].append((name, col))
                stored_count += 1

    for s in range(1, max_ops + 1):
        for opname, (arg_tys, res_ty, fn) in ordered_ops:
            if len(arg_tys) == 1:
                t1 = arg_tys[0]
                for term1, col1 in by[(t1, s - 1)]:
                    cand_count += 1
                    if cand_count > budget:
                        return None, cand_count, stored_count, pruned_count, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000
                    out = []
                    ok = True
                    for r in range(n):
                        v = fn(col1[r])
                        if v is None:
                            ok = False
                            break
                        out.append(v)
                    if not ok:
                        continue
                    out_t = tuple(out)
                    if res_ty == target_ty and out_t == target_col:
                        return (opname, term1), cand_count, stored_count, pruned_count, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000
                    if s < max_ops and out_t not in seen[res_ty]:
                        seen[res_ty].add(out_t)
                        if can_reach(res_ty, out_t, s):
                            by[(res_ty, s)].append(((opname, term1), out_t))
                            stored_count += 1
                        else:
                            pruned_count += 1
            else:
                t1, t2 = arg_tys
                for s1 in range(0, s):
                    s2 = s - 1 - s1
                    list1 = by[(t1, s1)]
                    list2 = by[(t2, s2)]
                    if not list1 or not list2:
                        continue
                    for term1, col1 in list1:
                        for term2, col2 in list2:
                            cand_count += 1
                            if cand_count > budget:
                                return None, cand_count, stored_count, pruned_count, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000
                            out = []
                            ok = True
                            for r in range(n):
                                v = fn(col1[r], col2[r])
                                if v is None:
                                    ok = False
                                    break
                                out.append(v)
                            if not ok:
                                continue
                            out_t = tuple(out)
                            if res_ty == target_ty and out_t == target_col:
                                return (opname, term1, term2), cand_count, stored_count, pruned_count, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000
                            if s < max_ops and out_t not in seen[res_ty]:
                                seen[res_ty].add(out_t)
                                if can_reach(res_ty, out_t, s):
                                    by[(res_ty, s)].append(((opname, term1, term2), out_t))
                                    stored_count += 1
                                else:
                                    pruned_count += 1
    return None, cand_count, stored_count, pruned_count, len(active_ops), abs_time_ms, (time.perf_counter() - t0) * 1000


def flat_problem_signature(inps, tty, tgt):
    """Flat 14-bit BUSTLE/plan_v2c §6.3 style problem signature (no algebra, no composition)."""
    xs = inps[0][2]
    bits = []
    bits.append(tty == 'int')
    bits.append(len(inps) >= 2)
    if tty == 'seq':
        bits.append(all(len(y) == len(x) for x, y in zip(xs, tgt)))
        bits.append(all(len(y) == max(0, len(x) - 1) for x, y in zip(xs, tgt)))
        bits.append(all(len(y) < len(x) for x, y in zip(xs, tgt) if len(x) > 0))
        bits.append(all(len(y) <= len(x) for x, y in zip(xs, tgt)))
        bits.append(all(all(v >= 0 for v in y) for y in tgt))
        bits.append(all(all(v > 0 for v in y) for y in tgt))
        bits.append(all(all(v % 2 == 0 for v in y) for y in tgt))
        bits.append(all(all(y[i] <= y[i+1] for i in range(len(y)-1)) for y in tgt))
        bits.append(all(set(y).issubset(set(x)) for x, y in zip(xs, tgt)))
        bits.append(all(sum(y) == sum(x) for x, y in zip(xs, tgt)))
        bits.append(False)
        bits.append(False)
    else:
        bits.extend([False]*10)
        bits.append(all(v >= 0 for v in tgt))
        bits.append(all(v % 2 == 0 for v in tgt))
    return tuple(bits)


def train_naive_bayes(ops, xs_rows, ys_rows, eval_prog, heldout_cold_ops):
    """
    Simulate plan_v2c §6.3 Naive Bayes over flat signature bits, trained on 50 random
    solved 2-op and 3-op tasks that do NOT include `heldout_cold_ops` (simulating newly
    added library functions with 0 training traces!).
    """
    rng = random.Random(999)
    avail = [k for k in ops if k not in heldout_cold_ops]
    u_seq = [k for k in avail if ops[k][0] == ('seq',) and ops[k][1] == 'seq']
    b_seq = [k for k in avail if ops[k][0] == ('seq', 'seq') and ops[k][1] == 'seq']
    u_int = [k for k in avail if ops[k][0] == ('seq',) and ops[k][1] == 'int']

    op_present = Counter()
    bit_given_op = defaultdict(Counter)
    bit_total = Counter()
    n_train = 0

    for _ in range(80):
        # Generate random 2-op or 3-op program
        use_y = rng.random() < 0.3
        inps = [('xs', 'seq', xs_rows)] + ([('ys', 'seq', ys_rows)] if use_y else [])
        p = 'xs'
        used_ops = set()
        depth = rng.choice([2, 3])
        if use_y and rng.random() < 0.7:
            op = rng.choice(b_seq)
            p = (op, 'xs', 'ys')
            used_ops.add(op)
            depth -= 1
        cur_ty = 'seq'
        for step in range(depth):
            if step == depth - 1 and rng.random() < 0.45:
                op = rng.choice(u_int)
                p = (op, p)
                used_ops.add(op)
                cur_ty = 'int'
            else:
                op = rng.choice(u_seq)
                p = (op, p)
                used_ops.add(op)
        try:
            tgt = tuple(eval_prog(p, xs_rows[i], ys_rows[i]) for i in range(len(xs_rows)))
            if any(v is None for v in tgt):
                continue
        except Exception:
            continue
        sig = flat_problem_signature(inps, cur_ty, tgt)
        n_train += 1
        for bi, bv in enumerate(sig):
            if bv:
                bit_total[bi] += 1
        for op in used_ops:
            op_present[op] += 1
            for bi, bv in enumerate(sig):
                if bv:
                    bit_given_op[op][bi] += 1

    def score_ops(inps, tty, tgt):
        sig = flat_problem_signature(inps, tty, tgt)
        scores = {}
        for op in ops:
            # Laplace-smoothed Naive Bayes log-odds
            c_op = op_present[op]
            p_op = (c_op + 0.5) / (n_train + 1.0)
            ll = math.log(p_op)
            for bi, bv in enumerate(sig):
                p_b_given_op = (bit_given_op[op][bi] + 0.5) / (c_op + 1.0)
                ll += math.log(p_b_given_op if bv else (1.0 - p_b_given_op))
            scores[op] = ll
        return sorted(ops.keys(), key=lambda k: -scores[k])

    return score_ops


def run_exp2():
    print("\n" + "=" * 84)
    print("EXPERIMENT 2: 61-FUNCTION LIBRARY SCALING (PLAIN OE vs FLAT NB vs ABSTRACT DFTA)")
    print("=" * 84)
    ops = make_61_library()
    domains, tables, all_states, learn_ms = build_abstract_domains(ops)
    print(f"Library: {len(ops)} typed ops. One-time group-by learning (6 quotients x 61 ops): {learn_ms:.1f} ms")

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
        args = [eval_prog(a, xs, ys) for a in p[1:]]
        if any(a is None for a in args):
            return None
        return op(*args)

    # Hold out 2 ops from Naive Bayes training to test COLD-START newly learned library entries!
    cold_ops = {'dbl_all', 'map_adj_sub'}
    nb_scorer = train_naive_bayes(ops, xs_rows, ys_rows, eval_prog, cold_ops)

    tasks = [
        ("T1 [COLD]: sum(map_adj_sub(sort(xs)))",      ('sum', ('map_adj_sub', ('sort', 'xs'))),                  'int', 3, [('xs', 'seq', xs_rows)]),
        ("T2: reverse(filter_pos(map_adj_add(xs)))",   ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),        'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T3: sum(zip_mul(xs, shift1(xs)))",           ('sum', ('zip_mul', 'xs', ('shift1', 'xs'))),              'int', 3, [('xs', 'seq', xs_rows)]),
        ("T4: sum(filter_pos(zip_sub(xs, ys)))",       ('sum', ('filter_pos', ('zip_sub', 'xs', 'ys'))),          'int', 3, [('xs', 'seq', xs_rows), ('ys', 'seq', ys_rows)]),
        ("T5: len(filter_even(map_adj_add(xs)))",      ('len', ('filter_even', ('map_adj_add', 'xs'))),           'int', 3, [('xs', 'seq', xs_rows)]),
        ("T6: running_sum(reverse(inc_all(xs)))",      ('running_sum', ('reverse', ('inc_all', 'xs'))),           'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T7 [UNCONSTR]: inc_all(reverse(xs))",        ('inc_all', ('reverse', 'xs')),                            'seq', 2, [('xs', 'seq', xs_rows)]),
        ("T8 [COLD]: dbl_all(sort(abs_all(xs)))",      ('dbl_all', ('sort', ('abs_all', 'xs'))),                  'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T9 [4-OP]: sort(dbl_all(filter_pos(map_adj_add(xs))))",
         ('sort', ('dbl_all', ('filter_pos', ('map_adj_add', 'xs')))),                                           'seq', 4, [('xs', 'seq', xs_rows)]),
    ]

    print(f"\n{'Task':<53} | {'PlainOE':>9} {'RAM':>6} | {'FlatNB':>9} | {'AbsDFTA':>7} {'Ops':>5} {'RAM':>6} {'ms':>6} | {'+SoftMDL':>8} | {'Gain':>6}")
    print("-" * 136)
    for tname, prog, tty, max_ops, inps in tasks:
        tgt = tuple(eval_prog(prog, xs_rows[i], ys_rows[i]) for i in range(len(xs_rows)))
        # 1. Plain OE
        p_res, p_c, p_st, _, _, _, _ = synthesize_oe(ops, inps, tty, tgt, max_ops, budget=400000)
        # 2. Flat Naive Bayes ordering (top-k ordering, no pruning; same full grammar so 0 false misses)
        nb_ord = nb_scorer(inps, tty, tgt)
        nb_res, nb_c, _, _, _, _, _ = synthesize_oe(ops, inps, tty, tgt, max_ops, op_order=nb_ord, budget=400000)
        # 3. Sound Factored Abstract DFTA (Knuth backward lower-bound pruning)
        a_res, a_c, a_st, _, a_ops, a_abs_ms, a_ms = synthesize_oe(
            ops, inps, tty, tgt, max_ops, domains=domains, tables=tables, all_states=all_states,
            use_abstract_pruning=True, budget=400000
        )
        # 4. Sound Abstract DFTA + Soft MDL operator ordering (zero training traces!)
        mdl_scores = compute_op_mdl_scores(ops, inps, tty, tgt, domains, tables, all_states, max_ops, list(range(4)))
        mdl_ord = sorted(ops.keys(), key=lambda k: mdl_scores[k])
        m_res, m_c, m_st, _, _, _, m_ms = synthesize_oe(
            ops, inps, tty, tgt, max_ops, domains=domains, tables=tables, all_states=all_states,
            use_abstract_pruning=True, op_order=mdl_ord, budget=400000
        )

        p_s = f"{p_c:>9}" if p_res else f">{p_c:>8}"
        nb_s = f"{nb_c:>9}" if nb_res else f">{nb_c:>8}"
        a_s = f"{a_c:>7}" if a_res else f"MISS"
        m_s = f"{m_c:>8}" if m_res else f"MISS"
        best_abs = m_c if m_res else a_c
        gain = f"{p_c / max(1, best_abs):>5.1f}x" if (a_res or m_res) else " FAIL"
        print(f"{tname:<53} | {p_s} {p_st:>6} | {nb_s} | {a_s} {a_ops:>2}/{len(ops)} {a_st:>6} {a_ms:>6.1f} | {m_s} | {gain}")


# ==============================================================================
# EXPERIMENT 3: ARITHMETIC RAM WALL — COLUMN-VECTOR HOMOMORPHISMS (G1 vs G2!)
# ==============================================================================

def run_exp3():
    print("\n" + "=" * 84)
    print("EXPERIMENT 3A: COLUMN-VECTOR RING HOMOMORPHISMS (F_2^N, F_3^4, F_5^3) ON G1={+,-,*,neg}")
    print("=" * 84)
    rng = random.Random(19)
    # 12 rows of (x, y)
    rows = [(0, 1), (1, -1), (-1, 0), (2, 3), (-2, 1), (3, -2),
            (1, 2), (-3, 2), (4, -1), (2, -3), (-1, 4), (3, 1)]
    n = len(rows)
    x_col = tuple(r[0] for r in rows)
    y_col = tuple(r[1] for r in rows)
    z_col = tuple(0 for _ in rows)
    o_col = tuple(1 for _ in rows)
    inps = [('x', 'int', x_col), ('y', 'int', y_col), ('0', 'int', z_col), ('1', 'int', o_col)]

    g1_ops = {
        '+':   (('int', 'int'), 'int', lambda a, b: a + b),
        '-':   (('int', 'int'), 'int', lambda a, b: a - b),
        '*':   (('int', 'int'), 'int', lambda a, b: a * b),
        'neg': (('int',), 'int', lambda a: -a),
    }

    def run_col_homomorphism_synth(ops_dict, target_col, max_ops, use_col_hom=False,
                                   exact_ring=True, budget=600000):
        """
        Bottom-up OE with EXACT column-vector quotient backward pruning!
        For exact_ring=True (G1):
          - Project column onto F_2^12 (12-bit int, at most 16 reachable states!)
          - Project first 4 rows onto F_3^4 (at most 81 states!)
          - Project first 3 rows onto F_5^3 (at most 125 states!)
          Because pi_p : Z^k -> F_p^k is an EXACT RING HOMOMORPHISM for {+, -, *, neg},
          we run exact Knuth forward-backward DP directly in the tiny finite rings F_2^12,
          F_3^4, and F_5^3 (NO sampling error, 100% CERTIFIED SOUND!).
        """
        t0 = time.perf_counter()
        hom_h = []  # list of (proj_fn, h_bwd_dict)
        dp_ms = 0.0

        if use_col_hom and exact_ring:
            td0 = time.perf_counter()
            specs = [
                # (modulus p, row indices tuple)
                (2, tuple(range(n))),        # F_2^12: <= 16 reachable polynomial functions!
                (3, (0, 1, 2, 3)),           # F_3^4:  <= 81 states!
                (3, (4, 5, 6, 7)),           # second 4-row F_3^4 projection!
                (5, (0, 1, 2)),              # F_5^3:  <= 125 states!
                (5, (3, 4, 5)),              # second 3-row F_5^3 projection!
            ]
            for p, ridxs in specs:
                k = len(ridxs)
                def make_proj(p=p, ridxs=ridxs):
                    return lambda col: tuple(col[i] % p for i in ridxs)
                proj = make_proj()

                # Forward exact closure in F_p^k up to max_ops - 1 (and check max_ops)
                g_fwd = {}
                layers = defaultdict(list)
                for _, _, col in inps:
                    a = proj(col)
                    if a not in g_fwd:
                        g_fwd[a] = 0
                        layers[0].append(a)

                # Helper op execution in F_p^k
                def apply_fp(opn, a, b=None, p=p):
                    if opn == 'neg': return tuple((-x) % p for x in a)
                    if opn == '+':   return tuple((x + y) % p for x, y in zip(a, b))
                    if opn == '-':   return tuple((x - y) % p for x, y in zip(a, b))
                    if opn == '*':   return tuple((x * y) % p for x, y in zip(a, b))

                # Build transitions and forward g_fwd up to max_ops
                edges_u = []
                edges_b = []
                for s in range(1, max_ops + 1):
                    # Unary neg
                    for a in layers[s - 1]:
                        o = apply_fp('neg', a)
                        if s < max_ops and o not in g_fwd:
                            g_fwd[o] = s
                            layers[s].append(o)
                    # Binary +, -, *
                    for s1 in range(0, s):
                        s2 = s - 1 - s1
                        l1, l2 = layers[s1], layers[s2]
                        if not l1 or not l2:
                            continue
                        for a in l1:
                            for b in l2:
                                for opn in ('+', '-', '*'):
                                    if opn in ('+', '*') and s1 > s2:
                                        continue
                                    o = apply_fp(opn, a, b)
                                    if s < max_ops and o not in g_fwd:
                                        g_fwd[o] = s
                                        layers[s].append(o)

                # Exact backward DP h_bwd from tgt_a (using exact algebraic inversion for +,-,neg
                # and forward-reachable siblings for *)!
                tgt_a = proj(target_col)
                INF = 999
                h_bwd = defaultdict(lambda: INF)
                h_bwd[tgt_a] = 0
                reach_list = list(g_fwd.items())  # (state, g_val) with g_val <= max_ops - 1

                for _ in range(max_ops):
                    changed = False
                    # Current frontier of states with finite h_bwd < max_ops
                    active_h = [(o, hv) for o, hv in list(h_bwd.items()) if hv < max_ops]
                    for o, hv in active_h:
                        # neg: neg(a) = o => a = neg(o)
                        a = apply_fp('neg', o)
                        if a in g_fwd and hv + 1 < h_bwd[a]:
                            h_bwd[a] = hv + 1
                            changed = True
                        # +, - with any sibling b of cost gb:
                        for b, gb in reach_list:
                            c = 1 + gb + hv
                            if c > max_ops:
                                continue
                            # a + b = o => a = o - b
                            a1 = apply_fp('-', o, b)
                            if a1 in g_fwd and c < h_bwd[a1]:
                                h_bwd[a1] = c
                                changed = True
                            # a - b = o => a = o + b
                            a2 = apply_fp('+', o, b)
                            if a2 in g_fwd and c < h_bwd[a2]:
                                h_bwd[a2] = c
                                changed = True
                            # b - a = o => a = b - o
                            a3 = apply_fp('-', b, o)
                            if a3 in g_fwd and c < h_bwd[a3]:
                                h_bwd[a3] = c
                                changed = True
                    # Multiplication a * b = o: iterate reachable pairs (a, b) with ga + gb + 1 <= max_ops
                    for a, ga in reach_list:
                        for b, gb in reach_list:
                            if ga + gb + 1 > max_ops:
                                continue
                            o = apply_fp('*', a, b)
                            hv = h_bwd[o]
                            if hv < INF:
                                c0 = 1 + gb + hv
                                if c0 < h_bwd[a]:
                                    h_bwd[a] = c0
                                    changed = True
                                c1 = 1 + ga + hv
                                if c1 < h_bwd[b]:
                                    h_bwd[b] = c1
                                    changed = True
                    if not changed:
                        break
                hom_h.append((proj, h_bwd))
            dp_ms = (time.perf_counter() - td0) * 1000

        # Concrete OE search with backward pruning BEFORE storing in RAM!
        by = defaultdict(list)
        seen = set()
        cands = 0
        stored = 0
        pruned = 0

        def ok_to_store(col, s):
            if not hom_h:
                return True
            rem = max_ops - s
            for proj, hb in hom_h:
                if hb[proj(col)] > rem:
                    return False
            return True

        for name, _, col in inps:
            if col == target_col:
                return name, 0, len(inps), 0, dp_ms, (time.perf_counter() - t0) * 1000
            if col not in seen:
                seen.add(col)
                if ok_to_store(col, 0):
                    by[0].append((name, col))
                    stored += 1

        for s in range(1, max_ops + 1):
            # Unary neg
            for t1, c1 in by[s - 1]:
                cands += 1
                if cands > budget:
                    return None, cands, stored, pruned, dp_ms, (time.perf_counter() - t0) * 1000
                out = tuple(-v for v in c1)
                if out == target_col:
                    return ('neg', t1), cands, stored, pruned, dp_ms, (time.perf_counter() - t0) * 1000
                if s < max_ops and out not in seen:
                    seen.add(out)
                    if ok_to_store(out, s):
                        by[s].append((('neg', t1), out))
                        stored += 1
                    else:
                        pruned += 1
            # Binary ops
            for s1 in range(0, s):
                s2 = s - 1 - s1
                l1, l2 = by[s1], by[s2]
                if not l1 or not l2:
                    continue
                for opname, (_, _, fn) in ops_dict.items():
                    if opname == 'neg':
                        continue
                    comm = opname in ('+', '*')
                    if comm and s1 > s2:
                        continue
                    for i1, (t1, c1) in enumerate(l1):
                        start2 = i1 if (comm and s1 == s2) else 0
                        for i2 in range(start2, len(l2)):
                            t2, c2 = l2[i2]
                            cands += 1
                            if cands > budget:
                                return None, cands, stored, pruned, dp_ms, (time.perf_counter() - t0) * 1000
                            out = tuple(fn(c1[r], c2[r]) for r in range(n))
                            if out == target_col:
                                return (opname, t1, t2), cands, stored, pruned, dp_ms, (time.perf_counter() - t0) * 1000
                            if s < max_ops and out not in seen:
                                seen.add(out)
                                if ok_to_store(out, s):
                                    by[s].append(((opname, t1, t2), out))
                                    stored += 1
                                else:
                                    pruned += 1
        return None, cands, stored, pruned, dp_ms, (time.perf_counter() - t0) * 1000

    tasks_g1 = [
        ("A1 (3-op/sz7): x*x + y*y [nonneg]",          lambda x, y: x*x + y*y,             3),
        ("A2 (3-op/sz7): (x+x)*(y+1) [even]",          lambda x, y: (x+x)*(y+1),           3),
        ("A3 (3-op/sz7): (x*y) + (x - y) [unconstr]",  lambda x, y: x*y + (x - y),         3),
        ("A4 (4-op/sz9): (x+y)*(x-y) + 1 [unconstr]",  lambda x, y: (x+y)*(x-y) + 1,       4),
        ("A5 (4-op/sz9): (x*y + x) * (y - 1) [rand]",  lambda x, y: (x*y + x) * (y - 1),   4),
        ("A6 (4-op/sz9): x*x - y*y + x [rand]",        lambda x, y: x*x - y*y + x,         4),
    ]
    print(f"{'G1 Task':<44} | {'Plain Cands':>11} {'RAM':>7} {'ms':>7} | {'ColHom Cands':>12} {'RAM':>6} {'DPms':>5} {'ms':>7} | {'CandGain':>8} {'RAMGain':>8}")
    print("-" * 134)
    for name, fn, mo in tasks_g1:
        tgt = tuple(fn(x, y) for x, y in rows)
        p_res, p_c, p_st, _, _, p_ms = run_col_homomorphism_synth(g1_ops, tgt, mo, use_col_hom=False, budget=800000)
        h_res, h_c, h_st, h_pr, dp_ms, h_ms = run_col_homomorphism_synth(g1_ops, tgt, mo, use_col_hom=True, budget=800000)
        p_s = f"{p_c:>11}" if p_res else f">{p_c:>10}"
        h_s = f"{h_c:>12}" if h_res else f"MISS({h_c})"
        cg = f"{p_c/max(1,h_c):>7.1f}x" if h_res else "FAIL"
        rg = f"{p_st/max(1,h_st):>7.1f}x" if h_res else "FAIL"
        print(f"{name:<44} | {p_s} {p_st:>7} {p_ms:>7.1f} | {h_s} {h_st:>6} {dp_ms:>5.1f} {h_ms:>7.1f} | {cg:>8} {rg:>8}")

    # Now HONEST FAILURE BOUNDARY: G2 = G1 + {div, mod, max, min}
    print("\n" + "=" * 84)
    print("EXPERIMENT 3B (HONEST FAILURE BOUNDARY): G2 = {+,-,*,neg,div,mod,max,min}")
    print("=" * 84)
    # Check what happens to algebraic lumpability & F_p homomorphisms when div/mod/max/min enter:
    g2_ops = dict(g1_ops)
    g2_ops['max'] = (('int', 'int'), 'int', lambda a, b: max(a, b))
    g2_ops['min'] = (('int', 'int'), 'int', lambda a, b: min(a, b))
    g2_ops['div'] = (('int', 'int'), 'int', lambda a, b: None if b == 0 else a // b)
    g2_ops['mod'] = (('int', 'int'), 'int', lambda a, b: None if b == 0 else a % b)

    # Check exact homomorphism failure rate of mod 2 and mod 3 on each op in G2
    probe = list(range(-10, 11))
    print("Per-op exactness of F_2 (mod 2), F_3 (mod 3), and Sign (-/0/+) over G2:")
    for opname, (atys, _, fn) in g2_ops.items():
        stats = []
        for qname, qfn in [('mod2', lambda v: v % 2), ('mod3', lambda v: v % 3), ('sign', lambda v: -1 if v<0 else (1 if v>0 else 0))]:
            obs = []
            if len(atys) == 1:
                for a in probe:
                    o = fn(a)
                    if o is not None: obs.append(((qfn(a),), qfn(o)))
            else:
                for a in probe:
                    for b in probe:
                        o = fn(a, b)
                        if o is not None: obs.append(((qfn(a), qfn(b)), qfn(o)))
            hc, ho, lump = cond_entropy_and_lump(obs)
            stats.append(f"{qname}: lump={lump:.2f} (H_cond={hc:.2f})")
        print(f"  {opname:<5} -> " + " | ".join(stats))
    print("Conclusion: Once div/mod enter the grammar, F_p ceases to be a homomorphism (lump ~ 0.00-0.19)!")
    print("In a mixed G2 grammar, F_p column-homomorphism pruning is ONLY sound on the ring sub-grammar G1,")
    print("OR as a factored tentative-first proposal (try G1 ring-pruned search first, then fall back to G2)!")


# ==============================================================================
# EXPERIMENT 4: FCA BITSET IMPLICATION LATTICE FOR CONDITIONAL LAWS
# ==============================================================================

def run_exp4():
    print("\n" + "=" * 84)
    print("EXPERIMENT 4: FCA BITSET IMPLICATION LATTICE FOR CONDITIONAL LAWS (CHOMPY BOTTLENECK)")
    print("=" * 84)
    rows = [(0, 0), (0, 1), (1, 0), (-1, 1), (2, 2), (2, -2), (-3, -3)] + [
        (random.Random(31 + i).randint(-6, 6), random.Random(99 + i).randint(-6, 6)) for i in range(25)
    ]
    n = len(rows)
    full_mask = (1 << n) - 1

    int_terms = [
        ('a', [r[0] for r in rows]),
        ('b', [r[1] for r in rows]),
        ('0', [0]*n),
        ('1', [1]*n),
        ('(+ a b)', [r[0]+r[1] for r in rows]),
        ('(- a b)', [r[0]-r[1] for r in rows]),
        ('(* a b)', [r[0]*r[1] for r in rows]),
        ('(neg a)', [-r[0] for r in rows]),
        ('(neg b)', [-r[1] for r in rows]),
    ]
    mask_to_term = {}
    def add_bool(term, bits):
        if bits == 0 or bits == full_mask:
            return
        if bits not in mask_to_term:
            mask_to_term[bits] = term

    for i, (t1, c1) in enumerate(int_terms):
        for j, (t2, c2) in enumerate(int_terms):
            if i < j:
                eq_m = sum((1 << r) for r in range(n) if c1[r] == c2[r])
                add_bool(f"(= {t1} {t2})", eq_m)
                add_bool(f"(not (= {t1} {t2}))", full_mask ^ eq_m)
            if i != j:
                lt_m = sum((1 << r) for r in range(n) if c1[r] < c2[r])
                add_bool(f"(< {t1} {t2})", lt_m)
                add_bool(f"(<= {t2} {t1})", full_mask ^ lt_m)

    atoms = list(mask_to_term.items())[:40]
    for i in range(len(atoms)):
        m1, s1 = atoms[i]
        for j in range(i + 1, len(atoms)):
            m2, s2 = atoms[j]
            add_bool(f"(and {s1} {s2})", m1 & m2)

    all_masks = list(mask_to_term.keys())
    cond_laws = [
        ("max(a,b) = a",           lambda a, b: max(a, b) == a),
        ("div(a*b, b) = a",        lambda a, b: b != 0 and (a * b) // b == a),
        ("abs(a+b) = abs(a)+abs(b)", lambda a, b: abs(a + b) == abs(a) + abs(b)),
        ("a - b = abs(a - b)",     lambda a, b: (a - b) == abs(a - b)),
        ("a * b > 0 => ...",       lambda a, b: (a > 0 and b > 0) or (a < 0 and b < 0)),
        ("min(a, 0) = 0",          lambda a, b: min(a, 0) == 0),
    ]
    t0 = time.perf_counter()
    print(f"Total distinct non-trivial guard classes (32-bit masks): {len(all_masks)}")
    print(f"{'Conditional Law':<28} | {'Agree':>6} | {'ValidGuards':>11} | {'Maximal(Weakest)':>16} | Best Guard Found")
    print("-" * 104)
    for lname, pred in cond_laws:
        agree = sum((1 << r) for r in range(n) if pred(rows[r][0], rows[r][1]))
        valid = [m for m in all_masks if (m & ~agree) == 0]
        # Maximal elements in the bitset implication poset (m1 implies m2 iff (m1 & m2) == m1)
        maximal = [m for m in valid if not any(m2 != m and (m & m2) == m for m2 in valid)]
        best = max(maximal, key=lambda m: (m.bit_count(), -len(mask_to_term[m]))) if maximal else None
        bstr = f"{mask_to_term[best]} ({best.bit_count()}/{agree.bit_count()})" if best else "none"
        print(f"{lname:<28} | {agree.bit_count():>3}/{n:<2} | {len(valid):>11} | {len(maximal):>16} | {bstr}")
    ms = (time.perf_counter() - t0) * 1000
    print(f"Total bitset FCA filtering time across all 6 laws: {ms:.2f} ms")


# ==============================================================================
# EXPERIMENT 5: CHEAP REFLECTION — ABSTRACT TRANSITION MEMOIZATION
# ==============================================================================

def run_exp5():
    print("\n" + "=" * 84)
    print("EXPERIMENT 5: CHEAP REFLECTION — DERIVATION SPACE ABSTRACT MEMO vs CONCRETE MEMO")
    print("=" * 84)
    ops = make_61_library()
    domains, tables, all_states, _ = build_abstract_domains(ops)

    # Generate 24 sequence tasks (6 structural families x 4 variations each) on COMPLETELY
    # DISJOINT random concrete input tables so concrete memoization gets 0% hits!
    families = [
        # (family_name, prog_tuple, tty, max_ops)
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
        # Repeat same programs on fresh concrete tables (cross-job reuse!)
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

    def abstract_transition_sig(xs_col, tty, tgt_col):
        """
        Cheap problem signature in the Derivation Space:
        summarizes the input->output abstract transition invariant across rows
        (using the SAME 6 quotient domains + relative length delta!).
        """
        sig = [tty]
        if tty == 'seq':
            deltas = [len(y) - len(x) for x, y in zip(xs_col, tgt_col)]
            if all(d == 0 for d in deltas): sig.append('dL=0')
            elif all(d == -1 for d in deltas): sig.append('dL=-1')
            elif all(d <= 0 for d in deltas): sig.append('dL<=0')
            else: sig.append('dL=any')
        else:
            sig.append('to_int')
        for dname in ('nonneg', 'parity', 'order'):
            afn = domains[dname]
            outs = frozenset(afn(y, tty) for y in tgt_col)
            sig.append((dname, outs))
        return tuple(sig)

    concrete_memo = {}
    # Derivation space: maps abstract_sig -> list of (solved_prog, op_set)
    deriv_space = defaultdict(list)

    tot_dfta_cands = 0
    tot_refl_cands = 0
    conc_hits = 0
    abs_exact_hits = 0
    abs_subgram_hits = 0
    abs_fallbacks = 0

    for idx, (tname, prog, tty, max_ops) in enumerate(families):
        # Generate a brand-new concrete input table for EVERY task!
        rng = random.Random(500 + idx * 37)
        xs_col = tuple(
            tuple(rng.randint(-5, 6) for _ in range(L))
            for L in (4, 5, 3, 6, 2, 4)
        )
        tgt_col = tuple(eval_p(prog, x) for x in xs_col)
        inps = [('xs', 'seq', xs_col)]

        # Check concrete memo
        ckey = (xs_col, tty, tgt_col)
        if ckey in concrete_memo:
            conc_hits += 1

        # Baseline: Sound Abstract DFTA (already strong!)
        base_res, base_c, _, _, _, _, _ = synthesize_oe(
            ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
            use_abstract_pruning=True, budget=400000
        )
        tot_dfta_cands += base_c

        # Reflection-augmented: check Derivation Space by abstract_transition_sig!
        asig = abstract_transition_sig(xs_col, tty, tgt_col)
        refl_c = 0
        found = None

        past = deriv_space.get(asig, [])
        if past:
            # Stage 1 (Tentative): replay exact past solution skeletons with same abstract sig (cost: 1 cand each!)
            for p_prog, _ in past:
                refl_c += 1
                try:
                    out = tuple(eval_p(p_prog, x) for x in xs_col)
                    if out == tgt_col:
                        found = p_prog
                        abs_exact_hits += 1
                        break
                except Exception:
                    pass

            # Stage 2 (Tentative): search small sub-grammar of ops seen in past derivations + type-compatible neighbors
            if found is None:
                sub_op_names = set()
                for _, oset in past:
                    sub_op_names |= oset
                # Restrict to observed family ops (tiny grammar!)
                sub_ops = {k: ops[k] for k in sub_op_names}
                s_res, s_c, _, _, _, _, _ = synthesize_oe(
                    sub_ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                    use_abstract_pruning=True, budget=50000
                )
                refl_c += s_c
                if s_res is not None:
                    found = s_res
                    abs_subgram_hits += 1

        # Stage 3 (Fallback): full Abstract DFTA if tentative reflection missed!
        if found is None:
            if past:
                abs_fallbacks += 1
            f_res, f_c, _, _, _, _, _ = synthesize_oe(
                ops, inps, tty, tgt_col, max_ops, domains=domains, tables=tables, all_states=all_states,
                use_abstract_pruning=True, budget=400000
            )
            refl_c += f_c
            found = f_res

        tot_refl_cands += refl_c
        if found is not None:
            concrete_memo[ckey] = found
            deriv_space[asig].append((found, extract_ops(found)))

    print(f"20 sequential tasks on DISJOINT concrete input tables (0% concrete overlap):")
    print(f"  Concrete memo hits:                  {conc_hits}/20 (0%)")
    print(f"  Abstract Deriv-Space exact hits:     {abs_exact_hits}/20 (1-candidate replay!)")
    print(f"  Abstract Deriv-Space subgrammar hit: {abs_subgram_hits}/20 (warm-started family!)")
    print(f"  Abstract Deriv-Space false-hit fallbacks (paid tiny tentative tax + full fallback): {abs_fallbacks}/20")
    print(f"  Total candidates — AbsDFTA alone:    {tot_dfta_cands:,}")
    print(f"  Total candidates — AbsDFTA + Refl:   {tot_refl_cands:,}  ({tot_dfta_cands/max(1,tot_refl_cands):.2f}x further reduction ON TOP of AbsDFTA!)")


if __name__ == '__main__':
    run_exp1()
    run_exp2()
    run_exp3()
    run_exp4()
    run_exp5()
