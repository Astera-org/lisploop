#!/usr/bin/env python3
"""
Empirical validation of Compositional Abstract Semantics (Quotient Algebras / Abstract DFTA)
as the unified substrate for Language + Heuristics + Library Scaling + Reflection.

Experiments:
  1. Automatic Word Discovery via Algebraic Lumpability (Conditional Entropy) on:
     (1a) Integer arithmetic {+, -, *, neg, div, mod, max, min}
     (1b) Sequence library (20+ sequence/scalar ops)
  2. Library Scaling (Utility Problem): 60-function library, multi-step synthesis tasks.
     Compares:
       - Plain bottom-up OE enumeration (plan_v2c baseline)
       - Flat signature + Naive Bayes operator reweighting (plan_v2c §6.3)
       - Factored Abstract DFTA + Knuth backward lower-bound pruning (sound)
       - Information-weighted Abstract DFTA (soft MDL path) + CEGAR
     Measures candidates evaluated, PEAK classes in RAM, and wall time.
  3. Arithmetic RAM Wall & Honest Failure-Mode Check:
     Tests factored quotients (parity, mod-3, sign, bounded-range) on G1/G2 arithmetic
     targets — both structured targets (always even / non-negative) AND unstructured targets!
  4. Cheap Reflection & Conditional-Law Implication Pruning (FCA bitset DAG).
"""

import math
import random
import time
import heapq
from collections import defaultdict, Counter

random.seed(42)

# ==============================================================================
# EXPERIMENT 1A: AUTOMATIC WORD DISCOVERY ON INTEGER ARITHMETIC
# ==============================================================================

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

def cond_entropy_and_nmi(pairs):
    """Given list of (abstract_input_tuple, abstract_output), compute H(out | in), H(out), and NMI."""
    out_counts = Counter(y for _, y in pairs)
    h_out = entropy(out_counts)
    if h_out < 1e-9:
        return 0.0, 0.0, 0.0
    buckets = defaultdict(Counter)
    for x, y in pairs:
        buckets[x][y] += 1
    tot = len(pairs)
    h_cond = 0.0
    for cnts in buckets.values():
        w = sum(cnts.values()) / tot
        h_cond += w * entropy(cnts)
    lumpability = 1.0 - (h_cond / h_out)  # 1.0 = exact algebraic congruence!
    return h_cond, h_out, lumpability

def run_exp1a():
    print("=" * 78)
    print("EXPERIMENT 1A: AUTOMATIC WORD DISCOVERY ON INTEGER ARITHMETIC")
    print("=" * 78)
    # Probe space: pairs (a, b) in [-12..12]^2
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

    # Candidate unary "words" (as if enumerated up to size ~4-5 over {=, <, mod, div, neg, 0,1,2,3,4,5,7})
    # Include genuine algebraic properties AND realistic distractors/junk predicates!
    candidate_words = {
        'is_zero (x=0)':          lambda x: x == 0,
        'is_neg (x<0)':           lambda x: x < 0,
        'is_pos (x>0)':           lambda x: x > 0,
        'sign (-/0/+)':           lambda x: -1 if x < 0 else (1 if x > 0 else 0),
        'parity (x mod 2)':       lambda x: x % 2,
        'mod_3 (x mod 3)':        lambda x: x % 3,
        'mod_4 (x mod 4)':        lambda x: x % 4,
        'mod_5 (x mod 5)':        lambda x: x % 5,
        'eq_1 (x=1)':             lambda x: x == 1,
        'eq_5 (x=5)':             lambda x: x == 5,
        'lt_3 (x<3)':             lambda x: x < 3,
        'lt_neg2 (x<-2)':         lambda x: x < -2,
        'in_[-2,2]':              lambda x: -2 <= x <= 2,
        'div3_eq0 (x//3=0)':      lambda x: (x // 3) == 0,
        'sq_mod3 (x*x mod 3)':    lambda x: (x * x) % 3,
        'sq_mod5 (x*x mod 5)':    lambda x: (x * x) % 5,
        'mod7_eq3':               lambda x: (x % 7) == 3,
        'hash_junk ((3x+1)%4)':   lambda x: (3 * x + 1) % 4,
        'even_or_neg':            lambda x: (x % 2 == 0) or (x < 0),
        'abs_lt2 (|x|<2)':        lambda x: abs(x) < 2,
        'is_small (|x|<=5)':      lambda x: abs(x) <= 5,
    }

    # Score each word by lumpability across ring ops {+,-,*,neg,max,min} and full ops (+ div, mod)
    ring_ops = ['+', '-', '*', 'neg', 'max', 'min']
    results = []
    for wname, wfn in candidate_words.items():
        # Filter trivial or near-identity words: check cardinality & base entropy
        base_vals = [wfn(v) for v in vals]
        card = len(set(base_vals))
        h_base = entropy(Counter(base_vals))
        if card <= 1 or h_base < 0.15:
            continue
        per_op = {}
        exact_cnt = 0
        for opname, (arity, fn) in arith_ops.items():
            obs = []
            if arity == 1:
                for a in vals:
                    out = fn(a)
                    if out is not None:
                        obs.append(((wfn(a),), wfn(out)))
            else:
                for a, b in pairs_ab:
                    out = fn(a, b)
                    if out is not None:
                        obs.append(((wfn(a), wfn(b)), wfn(out)))
            hc, ho, lump = cond_entropy_and_nmi(obs)
            per_op[opname] = lump
            if hc < 1e-9 and ho > 0.1:
                exact_cnt += 1
        avg_ring = sum(per_op[o] for o in ring_ops) / len(ring_ops)
        avg_all = sum(per_op.values()) / len(per_op)
        # MDL-penalized score: prefer compact vocabularies (small card) with high lumpability
        results.append((avg_ring, avg_all, exact_cnt, card, h_base, wname, per_op))

    results.sort(reverse=True)
    print(f"{'Word':<24} {'Card':>4} {'ExactOps':>8} {'RingLump':>8} {'AllLump':>8}  Per-op lumpability (+, -, *, max, div, mod)")
    for avg_ring, avg_all, exact_cnt, card, h_base, wname, po in results[:14]:
        detail = f"+:{po['+']:.2f} -:{po['-']:.2f} *:{po['*']:.2f} max:{po['max']:.2f} div:{po['div']:.2f} mod:{po['mod']:.2f}"
        print(f"{wname:<24} {card:>4} {exact_cnt:>8} {avg_ring:>8.3f} {avg_all:>8.3f}  {detail}")

# ==============================================================================
# EXPERIMENT 1B: AUTOMATIC WORD DISCOVERY ON SEQUENCE ALGEBRA
# ==============================================================================

def run_exp1b():
    print("\n" + "=" * 78)
    print("EXPERIMENT 1B: AUTOMATIC WORD DISCOVERY ON SEQUENCE OPERATORS")
    print("=" * 78)
    rng = random.Random(7)
    seqs = [[]] + [[rng.randint(-4, 6) for _ in range(rng.randint(1, 6))] for _ in range(120)]

    seq_ops = {
        'reverse':      lambda xs: list(reversed(xs)),
        'sort':         lambda xs: sorted(xs),
        'tail':         lambda xs: xs[1:] if xs else None,
        'inc_all':      lambda xs: [x + 1 for x in xs],
        'dbl_all':      lambda xs: [x * 2 for x in xs],
        'neg_all':      lambda xs: [-x for x in xs],
        'abs_all':      lambda xs: [abs(x) for x in xs],
        'filter_pos':   lambda xs: [x for x in xs if x > 0],
        'filter_even':  lambda xs: [x for x in xs if x % 2 == 0],
        'map_adj_add':  lambda xs: [xs[i] + xs[i+1] for i in range(len(xs)-1)],
        'map_adj_sub':  lambda xs: [xs[i+1] - xs[i] for i in range(len(xs)-1)],
        'running_sum':  lambda xs: [sum(xs[:i+1]) for i in range(len(xs))],
        'shift1_zero':  lambda xs: (xs[1:] + [0]) if xs else [],
        'rotate1':      lambda xs: (xs[1:] + xs[:1]) if xs else [],
        'dedup_adj':    lambda xs: [xs[i] for i in range(len(xs)) if i == 0 or xs[i] != xs[i-1]],
    }

    # Candidate sequence properties (coarse finite words, cardinality <= 7)
    seq_words = {
        'is_empty (len=0)':      lambda xs: len(xs) == 0,
        'len_cap5 (min(len,5))': lambda xs: min(len(xs), 5),
        'len_mod2 (len%2)':      lambda xs: len(xs) % 2,
        'all_nonneg':            lambda xs: all(x >= 0 for x in xs),
        'all_even':              lambda xs: all(x % 2 == 0 for x in xs),
        'is_sorted':             lambda xs: all(xs[i] <= xs[i+1] for i in range(len(xs)-1)),
        'sum_mod2':              lambda xs: sum(xs) % 2,
        'sum_sign (-/0/+)':      lambda xs: 0 if sum(xs) == 0 else (1 if sum(xs) > 0 else -1),
        'has_zero':              lambda xs: 0 in xs,
        'head_even (junk/part)': lambda xs: (xs[0] % 2 == 0) if xs else None,
        'len_eq_3 (junk)':       lambda xs: len(xs) == 3,
        'head_eq_2 (junk)':      lambda xs: (xs[0] == 2) if xs else False,
        'sum_gt_5 (junk)':       lambda xs: sum(xs) > 5,
    }

    res = []
    for wname, wfn in seq_words.items():
        lumps = []
        exact_ops = 0
        for opname, fn in seq_ops.items():
            obs = []
            for s in seqs:
                out = fn(s)
                if out is not None:
                    obs.append(((wfn(s),), wfn(out)))
            hc, ho, lump = cond_entropy_and_nmi(obs)
            if ho > 0.05:
                lumps.append(lump)
                if hc < 1e-9:
                    exact_ops += 1
        avg_lump = sum(lumps) / len(lumps) if lumps else 0.0
        res.append((avg_lump, exact_ops, wname))
    res.sort(reverse=True)
    print(f"{'Sequence Word':<24} {'ExactOps/15':>11} {'AvgLumpability':>15}")
    for avg_lump, ex, wn in res:
        print(f"{wn:<24} {ex:>11} {avg_lump:>15.3f}")

# ==============================================================================
# EXPERIMENT 2: 60-FUNCTION LIBRARY SCALING (PLAIN OE vs FLAT NB vs ABSTRACT DFTA)
# ==============================================================================

def make_60_library():
    """60 realistic typed sequence/scalar library functions (15 core + 45 plausible helpers/distractors)."""
    ops = {}
    # Unary Seq -> Seq
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

    # Binary Seq x Seq -> Seq
    ops['zip_add']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x + y for x, y in zip(a, b)))
    ops['zip_sub']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x - y for x, y in zip(a, b)))
    ops['zip_mul']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(x * y for x, y in zip(a, b)))
    ops['zip_max']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(max(x, y) for x, y in zip(a, b)))
    ops['zip_min']     = (('seq', 'seq'), 'seq', lambda a, b: tuple(min(x, y) for x, y in zip(a, b)))
    ops['concat']      = (('seq', 'seq'), 'seq', lambda a, b: a + b)

    # Unary Seq -> Int
    ops['sum']         = (('seq',), 'int', lambda xs: sum(xs))
    ops['prod']        = (('seq',), 'int', lambda xs: math.prod(xs) if xs else 1)
    ops['len']         = (('seq',), 'int', lambda xs: len(xs))
    ops['head']        = (('seq',), 'int', lambda xs: xs[0] if xs else None)
    ops['last']        = (('seq',), 'int', lambda xs: xs[-1] if xs else None)
    ops['max_el']      = (('seq',), 'int', lambda xs: max(xs) if xs else None)
    ops['min_el']      = (('seq',), 'int', lambda xs: min(xs) if xs else None)
    ops['count_pos']   = (('seq',), 'int', lambda xs: sum(1 for x in xs if x > 0))
    ops['count_even']  = (('seq',), 'int', lambda xs: sum(1 for x in xs if x % 2 == 0))

    # Binary Int x Int -> Int
    ops['add']         = (('int', 'int'), 'int', lambda a, b: a + b)
    ops['sub']         = (('int', 'int'), 'int', lambda a, b: a - b)
    ops['mul']         = (('int', 'int'), 'int', lambda a, b: a * b)
    ops['imax']        = (('int', 'int'), 'int', lambda a, b: max(a, b))
    ops['imin']        = (('int', 'int'), 'int', lambda a, b: min(a, b))
    return ops

# Factored abstract domains (each tiny, automatically populated from forward probe tables!)
# Crucially: each abstraction maps a CONCRETE COLUMN (vector over the task rows) or per-row value
# into a tiny finite abstract value!
# Even cleaner: pointwise per-row abstract value alpha_j(val), lifted to a tuple across K=3 probe rows
# OR relational abstract property! Let's use per-value small finite abstractions (size 2..6 each),
# so each operator's abstract table f^{#_j} is LEARNED ONCE (independent of any task!) from probe values!

def make_learned_abstract_domains(ops):
    """
    Learn f^{#_j} for every operator in the 60-op library ONCE on a fixed generic probe space
    using plain group-by over the operator's forward table!
    Each domain j is a small finite quotient alpha_j: Val -> A_j (per type).
    """
    rng = random.Random(101)
    probe_seqs = [()] + [tuple(rng.randint(-4, 5) for _ in range(rng.randint(1, 5))) for _ in range(180)]
    # Add structured probes (all-even, all-pos, sorted, zeros) so rare abstract buckets are well-sampled!
    probe_seqs += [
        (0,), (0, 0), (1, 2, 3), (2, 4, 6), (-3, -1), (5, 3, 1), (0, 2, 4, 6),
        (1, 1, 1), (-2, 0, 2), (1, 3, 5, 7), (2, 2), (4, 2, 0), (1, 2, 3, 4, 5),
        (-4, -2, 0), (3, 3, 3, 3), (-1, -2, -3), (2, 6, 4), (0, 1, 0, 1)
    ]
    probe_ints = list(range(-12, 13)) + [20, -20, 30, -30, 100]

    # Define 6 small compositional quotients (each discovered in Exp 1A/1B!)
    # Every domain handles BOTH 'seq' and 'int' (returning a small finite tag)
    domains = {
        # Domain 1: Length (capped at 7) for seq, and sign for int
        'len_sign': (
            lambda v, ty: min(len(v), 7) if ty == 'seq' else (-1 if v < 0 else (1 if v > 0 else 0))
        ),
        # Domain 2: Non-negativity (all >= 0 for seq, >= 0 for int) + emptiness
        'nonneg': (
            lambda v, ty: ('E' if len(v) == 0 else ('P' if all(x > 0 for x in v) else ('N0' if all(x >= 0 for x in v) else ('NEG' if all(x < 0 for x in v) else 'M'))))
            if ty == 'seq' else ('P' if v > 0 else ('Z' if v == 0 else 'N'))
        ),
        # Domain 3: Parity (all even / all odd / empty / mixed for seq; mod 2 for int)
        'parity': (
            lambda v, ty: ('E' if len(v) == 0 else ('EV' if all(x % 2 == 0 for x in v) else ('OD' if all(x % 2 != 0 for x in v) else 'M')))
            if ty == 'seq' else (v % 2)
        ),
        # Domain 4: Sortedness (ascending / descending / const / unsorted for seq; sign for int)
        'order': (
            lambda v, ty: (
                'S01' if len(v) <= 1 else (
                'C' if len(set(v)) == 1 else (
                'ASC' if all(v[i] <= v[i+1] for i in range(len(v)-1)) else (
                'DSC' if all(v[i] >= v[i+1] for i in range(len(v)-1)) else 'U')))
            ) if ty == 'seq' else (-1 if v < 0 else (1 if v > 0 else 0))
        ),
        # Domain 5: Sum parity (sum(xs)%2 + empty flag; mod 2 for int)
        'sum_mod2': (
            lambda v, ty: ('E' if len(v) == 0 else sum(v) % 2) if ty == 'seq' else (v % 2)
        ),
        # Domain 6: Exact length mod 2 + non-empty for seq; mod 3 for int
        'len_mod2_int3': (
            lambda v, ty: ('E' if len(v) == 0 else len(v) % 2) if ty == 'seq' else (v % 3)
        ),
    }

    # For each domain d and each op f, learn transition table: (a_args) -> set of observed a_out (and counts!)
    tables = {}
    t0 = time.perf_counter()
    for dname, afn in domains.items():
        dtbl = {}
        for opname, (arg_tys, res_ty, fn) in ops.items():
            trans = defaultdict(Counter)
            if len(arg_tys) == 1:
                p0 = probe_seqs if arg_tys[0] == 'seq' else probe_ints
                for x in p0:
                    out = fn(x)
                    if out is not None:
                        trans[(afn(x, arg_tys[0]),)][afn(out, res_ty)] += 1
            else:
                p0 = probe_seqs if arg_tys[0] == 'seq' else probe_ints
                p1 = probe_seqs if arg_tys[1] == 'seq' else probe_ints
                # Sample pairs systematically (including diagonal a==b!)
                step0 = max(1, len(p0) // 45)
                step1 = max(1, len(p1) // 45)
                sub0 = p0[::step0]
                sub1 = p1[::step1]
                for x in sub0:
                    for y in sub1:
                        out = fn(x, y)
                        if out is not None:
                            trans[(afn(x, arg_tys[0]), afn(y, arg_tys[1]))][afn(out, res_ty)] += 1
                # Also diagonal x == y
                if arg_tys[0] == arg_tys[1]:
                    for x in p0:
                        out = fn(x, x)
                        if out is not None:
                            trans[(afn(x, arg_tys[0]), afn(x, arg_tys[1]))][afn(out, res_ty)] += 1
            dtbl[opname] = trans
        tables[dname] = dtbl
    learn_ms = (time.perf_counter() - t0) * 1000
    return domains, tables, learn_ms

def knuth_backward_bounds(ops, leaf_abs, target_abs, dtbl, max_ops):
    """
    Given abstract domain table dtbl[op][a_args] -> Counter(a_out),
    compute:
      1. Forward min op-count g_fwd[(ty, a)] to reach abstract state (ty, a) from leaves (cost 0).
      2. Backward min remaining op-count h_bwd[(ty, a)] needed to reach target_abs from (ty, a)
         (using forward-reachable sibling states for binary ops!).
    Note: each op application adds +1 to op-count (AST internal node count).
    For a concrete expression of op-count s with abstract state a,
    any completion of total op-count <= max_ops requires s + h_bwd[a] <= max_ops!
    """
    INF = 999
    # Step 1: Forward DP by op-count 0..max_ops
    g_fwd = defaultdict(lambda: INF)
    for ty, a in leaf_abs:
        g_fwd[(ty, a)] = 0

    changed = True
    while changed:
        changed = False
        for opname, (arg_tys, res_ty, _) in ops.items():
            trans = dtbl[opname]
            if len(arg_tys) == 1:
                t0 = arg_tys[0]
                for (a0,), outs in trans.items():
                    c = g_fwd[(t0, a0)] + 1
                    if c <= max_ops:
                        for ao in outs:
                            if c < g_fwd[(res_ty, ao)]:
                                g_fwd[(res_ty, ao)] = c
                                changed = True
            else:
                t0, t1 = arg_tys
                for (a0, a1), outs in trans.items():
                    c = g_fwd[(t0, a0)] + g_fwd[(t1, a1)] + 1
                    if c <= max_ops:
                        for ao in outs:
                            if c < g_fwd[(res_ty, ao)]:
                                g_fwd[(res_ty, ao)] = c
                                changed = True

    # Step 2: Backward DP from target_abs: h_bwd[state] = min extra ops to turn state into target_abs
    h_bwd = defaultdict(lambda: INF)
    h_bwd[target_abs] = 0
    changed = True
    while changed:
        changed = False
        for opname, (arg_tys, res_ty, _) in ops.items():
            trans = dtbl[opname]
            if len(arg_tys) == 1:
                t0 = arg_tys[0]
                for (a0,), outs in trans.items():
                    if g_fwd[(t0, a0)] >= INF:
                        continue
                    best_out = min(h_bwd[(res_ty, ao)] for ao in outs)
                    cand = 1 + best_out
                    if cand < h_bwd[(t0, a0)]:
                        h_bwd[(t0, a0)] = cand
                        changed = True
            else:
                t0, t1 = arg_tys
                for (a0, a1), outs in trans.items():
                    g0, g1 = g_fwd[(t0, a0)], g_fwd[(t1, a1)]
                    if g0 >= INF or g1 >= INF:
                        continue
                    best_out = min(h_bwd[(res_ty, ao)] for ao in outs)
                    if best_out >= INF:
                        continue
                    # If we hold a0, we still need to pay g1 for the other arg + 1 for op + best_out
                    c0 = 1 + g1 + best_out
                    if c0 < h_bwd[(t0, a0)]:
                        h_bwd[(t0, a0)] = c0
                        changed = True
                    c1 = 1 + g0 + best_out
                    if c1 < h_bwd[(t1, a1)]:
                        h_bwd[(t1, a1)] = c1
                        changed = True

    # Also compute which operators can even appear on ANY valid abstract hyperpath <= max_ops!
    useful_ops = set()
    for opname, (arg_tys, res_ty, _) in ops.items():
        trans = dtbl[opname]
        if len(arg_tys) == 1:
            t0 = arg_tys[0]
            for (a0,), outs in trans.items():
                g0 = g_fwd[(t0, a0)]
                if g0 < INF:
                    for ao in outs:
                        if g0 + 1 + h_bwd[(res_ty, ao)] <= max_ops:
                            useful_ops.add(opname)
                            break
        else:
            t0, t1 = arg_tys
            for (a0, a1), outs in trans.items():
                g0, g1 = g_fwd[(t0, a0)], g_fwd[(t1, a1)]
                if g0 + g1 + 1 <= max_ops:
                    for ao in outs:
                        if g0 + g1 + 1 + h_bwd[(res_ty, ao)] <= max_ops:
                            useful_ops.add(opname)
                            break
    return g_fwd, h_bwd, useful_ops

def synthesize_oe(ops, inputs, target_ty, target_col, max_ops,
                  domains=None, tables=None, use_abstract_pruning=False,
                  row_subset_for_abs=None, budget=300000):
    """
    Bottom-up OE enumerator over the 60-op library.
    If use_abstract_pruning=True, computes factored backward lower bounds across ALL rows
    and ALL 6 abstract domains:
      1. Intersects useful_ops across all (domain, row) to prune useless library functions upfront!
      2. Prunes any intermediate concrete class C at op-count s if for ANY (domain, row):
         s + h_bwd[d, r](alpha_d(C[r])) > max_ops! (Drops C before storing in RAM!)
    """
    t0 = time.perf_counter()
    n = len(target_col)
    active_ops = dict(ops)
    h_tables = []  # list of (dname, afn, row_idx, h_bwd)

    abs_time_ms = 0.0
    if use_abstract_pruning:
        ta0 = time.perf_counter()
        # Use up to 4 diverse rows (e.g. non-empty, different lengths) for fast per-row abstract checks
        check_rows = row_subset_for_abs if row_subset_for_abs is not None else list(range(min(n, 4)))
        for dname, afn in domains.items():
            dtbl = tables[dname]
            for r in check_rows:
                leaf_abs = [(ty, afn(col[r], ty)) for _, ty, col in inputs]
                tgt_abs = (target_ty, afn(target_col[r], target_ty))
                _, h_bwd, uops = knuth_backward_bounds(active_ops, leaf_abs, tgt_abs, dtbl, max_ops)
                h_tables.append((dname, afn, r, h_bwd))
                active_ops = {k: v for k, v in active_ops.items() if k in uops}
        abs_time_ms = (time.perf_counter() - ta0) * 1000

    # Bank: by[(ty, s)] = list of (term, col), seen[ty] = set of cols
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

    # Enumerate by op-count s = 1 .. max_ops
    for s in range(1, max_ops + 1):
        for opname, (arg_tys, res_ty, fn) in active_ops.items():
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

def run_exp2():
    print("\n" + "=" * 78)
    print("EXPERIMENT 2: 61-FUNCTION LIBRARY SCALING (PLAIN OE vs ABSTRACT DFTA)")
    print("=" * 78)
    ops = make_60_library()
    print(f"Library size: {len(ops)} typed functions")
    domains, tables, learn_ms = make_learned_abstract_domains(ops)
    print(f"One-time abstract table learning (6 quotients x {len(ops)} ops via group-by): {learn_ms:.1f} ms")

    # Fixed realistic task examples (6 rows, including diverse lengths & signs)
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
        return op(*args)

    # Mix of 2-op and 3-op tasks, INCLUDING an intentionally hard / ambiguous task (Task 7)!
    tasks = [
        ("T1: sum(map_adj_sub(sort(xs)))",           ('sum', ('map_adj_sub', ('sort', 'xs'))),             'int', 3, [('xs', 'seq', xs_rows)]),
        ("T2: reverse(filter_pos(map_adj_add(xs)))", ('reverse', ('filter_pos', ('map_adj_add', 'xs'))),   'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T3: sum(zip_mul(xs, shift1(xs)))",         ('sum', ('zip_mul', 'xs', ('shift1', 'xs'))),         'int', 3, [('xs', 'seq', xs_rows)]),
        ("T4: sum(filter_pos(zip_sub(xs, ys)))",     ('sum', ('filter_pos', ('zip_sub', 'xs', 'ys'))),     'int', 3, [('xs', 'seq', xs_rows), ('ys', 'seq', ys_rows)]),
        ("T5: len(filter_even(map_adj_add(xs)))",    ('len', ('filter_even', ('map_adj_add', 'xs'))),      'int', 3, [('xs', 'seq', xs_rows)]),
        ("T6: running_sum(reverse(inc_all(xs)))",    ('running_sum', ('reverse', ('inc_all', 'xs'))),      'seq', 3, [('xs', 'seq', xs_rows)]),
        ("T7 [HARD/UNCONSTR]: inc_all(reverse(xs))", ('inc_all', ('reverse', 'xs')),                       'seq', 2, [('xs', 'seq', xs_rows)]),
        ("T8 [HARD/3-op]: dbl_all(sort(abs_all(xs)))",('dbl_all', ('sort', ('abs_all', 'xs'))),            'seq', 3, [('xs', 'seq', xs_rows)]),
    ]

    print(f"\n{'Task':<44} | {'PlainOE Cands':>13} {'RAM':>6} {'ms':>6} | {'AbsDFTA Ops':>11} {'Cands':>8} {'RAM':>6} {'ms':>6} | {'Speedup':>7}")
    print("-" * 124)
    for tname, prog, tty, max_ops, inps in tasks:
        tgt = tuple(eval_prog(prog, xs_rows[i], ys_rows[i]) for i in range(len(xs_rows)))
        p_res, p_c, p_st, _, _, _, p_ms = synthesize_oe(ops, inps, tty, tgt, max_ops, use_abstract_pruning=False, budget=500000)
        a_res, a_c, a_st, a_pr, a_ops, a_abs_ms, a_ms = synthesize_oe(
            ops, inps, tty, tgt, max_ops, domains=domains, tables=tables, use_abstract_pruning=True, budget=500000
        )
        p_tag = f"{p_c:>11}" if p_res else f">{p_c:>10}"
        a_tag = f"{a_c:>8}" if a_res else f"MISS({a_c})"
        sp = f"{p_c / max(1, a_c):>6.1f}x" if a_res else "  FAIL"
        print(f"{tname:<44} | {p_tag:>13} {p_st:>6} {p_ms:>6.1f} | {a_ops:>4}/{len(ops):<6} {a_tag:>8} {a_st:>6} {a_ms:>6.1f} | {sp:>7}")
        if a_res is None:
            print(f"    [!] Abstract pruning missed solution! (Sampled probe table missed a transition -> shows why tentative/fallback matters!)")
        elif a_res != prog:
            print(f"    Note: found equivalent shorter/alt program: {a_res}")

# ==============================================================================
# EXPERIMENT 3: ARITHMETIC RAM WALL — WHERE ABSTRACT PRUNING BITES vs WHERE IT DOESN'T
# ==============================================================================

def run_exp3():
    print("\n" + "=" * 78)
    print("EXPERIMENT 3: ARITHMETIC ENUMERATION (G1) — STRUCTURED vs UNSTRUCTURED TARGETS")
    print("=" * 78)
    # G1 = {+, -, *, neg} over leaves x, y, 0, 1 on 12 rows
    rng = random.Random(19)
    rows = [(0, 1), (1, -1), (-1, 0)] + [(rng.randint(-8, 8), rng.randint(-8, 8)) for _ in range(9)]
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

    # Exact algebraic quotients (congruences!) for integers: mod 2, mod 3, mod 5, and sign
    # Note: mod 2, mod 3, mod 5 are EXACT ring homomorphisms (100% sound, zero false negatives!)
    int_domains = {
        'mod2': lambda v, ty: v % 2,
        'mod3': lambda v, ty: v % 3,
        'mod5': lambda v, ty: v % 5,
        'sign': lambda v, ty: -1 if v < 0 else (1 if v > 0 else 0),
    }
    # Build exact abstract tables for mod2, mod3, mod5, and sound sign table!
    int_tables = {}
    for dname, afn in int_domains.items():
        dtbl = {}
        probe = list(range(-10, 11))
        for opname, (atys, rty, fn) in g1_ops.items():
            trans = defaultdict(Counter)
            if len(atys) == 1:
                for a in probe:
                    trans[(afn(a, 'int'),)][afn(fn(a), 'int')] += 1
            else:
                for a in probe:
                    for b in probe:
                        trans[(afn(a, 'int'), afn(b, 'int'))][afn(fn(a, b), 'int')] += 1
            dtbl[opname] = trans
        int_tables[dname] = dtbl

    # Test targets of op-count 3 (AST size 7):
    # (a) structured: x*x + y*y (always >= 0), 2*(x*y + x) (always even), (x - y)*(x + y)
    # (b) unstructured: x*y + x - y, 2*x - y + 1 (random parity, random sign!)
    arith_tasks = [
        ("A1: (x*x) + (y*y) [nonneg]",     lambda x, y: x*x + y*y,         3),
        ("A2: (x+x) * (y+1) [even]",       lambda x, y: (x+x) * (y+1),     3),
        ("A3: (x*y) + (x+x) [mixed]",      lambda x, y: x*y + (x+x),       3),
        ("A4: ((x+x) - y) + 1 [unconstr]", lambda x, y: (x+x) - y + 1,     3),
    ]

    print(f"{'Arithmetic Task (3 ops / size 7)':<34} | {'PlainOE Cands':>13} {'RAM':>6} | {'AbsDFTA Cands':>13} {'RAM':>6} {'Pruned':>7} | {'Cands Ratio':>11} {'RAM Ratio':>9}")
    print("-" * 116)
    for name, fn, max_ops in arith_tasks:
        tgt = tuple(fn(x, y) for x, y in rows)
        p_res, p_c, p_st, _, _, _, _ = synthesize_oe(g1_ops, inps, 'int', tgt, max_ops, use_abstract_pruning=False, budget=400000)
        # Note: use rows 0..5 for mod2/mod3/mod5/sign backward pruning
        a_res, a_c, a_st, a_pr, _, _, _ = synthesize_oe(
            g1_ops, inps, 'int', tgt, max_ops, domains=int_domains, tables=int_tables,
            use_abstract_pruning=True, row_subset_for_abs=list(range(6)), budget=400000
        )
        print(f"{name:<34} | {p_c:>13} {p_st:>6} | {a_c:>13} {a_st:>6} {a_pr:>7} | {p_c/max(1,a_c):>10.1f}x {p_st/max(1,a_st):>8.1f}x  found={a_res}")

# ==============================================================================
# EXPERIMENT 4: CHEAP IMPLICATION LATTICE (FCA BITSET DAG) FOR CONDITIONAL LAWS
# ==============================================================================

def run_exp4():
    print("\n" + "=" * 78)
    print("EXPERIMENT 4: FCA BITSET IMPLICATION LATTICE ON CANDIDATE GUARDS (CHOMPY BOTTLENECK)")
    print("=" * 78)
    # 32 rows of (a, b) integers; enumerate small Boolean predicates to size 4
    rng = random.Random(31)
    rows = [(0, 0), (0, 1), (1, 0), (-1, 1), (2, 2), (2, -2), (-3, -3)] + [
        (rng.randint(-6, 6), rng.randint(-6, 6)) for _ in range(25)
    ]
    n = len(rows)
    full_mask = (1 << n) - 1

    # Enumerate int terms up to size 3, bool preds up to size 4, deduplicated by bitmask!
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
    # Build atomic Boolean masks (=, <) + negations + conjunctions (size <= 4)
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

    # Add pairwise conjunctions of atomic preds (capped at first 40 atoms to mimic size-4 guards)
    atoms = list(mask_to_term.items())[:40]
    for i in range(len(atoms)):
        m1, s1 = atoms[i]
        for j in range(i + 1, len(atoms)):
            m2, s2 = atoms[j]
            add_bool(f"(and {s1} {s2})", m1 & m2)

    all_masks = list(mask_to_term.keys())
    # Test conditional law discovery: e.g. max(a, b) = a (true on a >= b), and (a*b)//b = a (true on b != 0)
    targets = {
        'max(a,b) = a':        sum((1 << r) for r in range(n) if max(rows[r][0], rows[r][1]) == rows[r][0]),
        'div(a*b, b) = a':     sum((1 << r) for r in range(n) if rows[r][1] != 0 and (rows[r][0]*rows[r][1]) // rows[r][1] == rows[r][0]),
        'abs(a+b) = abs(a)+abs(b)': sum((1 << r) for r in range(n) if abs(rows[r][0]+rows[r][1]) == abs(rows[r][0])+abs(rows[r][1])),
    }
    print(f"Distinct non-trivial Boolean guard classes (bitmasks over {n} rows): {len(all_masks)}")
    for law_name, agree_mask in targets.items():
        # Every guard m with (m & ~agree_mask) == 0 is a valid conditional guard!
        valid = [m for m in all_masks if (m & ~agree_mask) == 0]
        # Maximal (weakest!) guards in the bitset implication poset: no other valid m2 strictly contains m!
        maximal = [m for m in valid if not any(m2 != m and (m & m2) == m for m2 in valid)]
        print(f"  Law [{law_name:<25}]: {len(valid):>4} valid guards -> {len(maximal)} maximal (weakest) via bitset implication:")
        for m in maximal[:3]:
            print(f"      {mask_to_term[m]}  (covers {m.bit_count()}/{agree_mask.bit_count()} agreeing rows)")

if __name__ == '__main__':
    run_exp1a()
    run_exp1b()
    run_exp2()
    run_exp3()
    run_exp4()
