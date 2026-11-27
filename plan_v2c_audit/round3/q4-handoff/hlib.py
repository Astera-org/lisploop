"""Shared helpers for experiments B1-B4 and C (claim U2).  Standard library only.

Reuses the 61-operator library, quotients, tables and searches of verify-quotients
(seqlib.py, q2search.py, q2tasks.py: copied here unchanged).
"""
import math
import random
import time
from collections import Counter, defaultdict

import seqlib
from seqlib import (L, I, OPS, OPNAMES, OPSIG, OPFN, OPIDX, HAND6, Q_SIGN, Q_PARITY, Q_ORDER,
                    Q_ISEMPTY, eval_term, term_size, term_str, term_type, term_ops, subterms,
                    build_tables, make_inputs, MINSIZE)

BASE61 = tuple(OPNAMES)
BASE61_SET = frozenset(BASE61)


# ------------------------------------------------------------------ oracle constant operators
# Used ONLY as the favourable baseline in B3: "the grammar happens to contain the needed
# constant offset / scale as a unary operator".  They are appended after the 61 base
# operators, so every table and search restricted to BASE61 is unchanged.
def _register(name, at, rt, fn):
    OPS.append((name, at, rt, fn))
    OPNAMES.append(name)
    OPIDX[name] = len(OPS) - 1
    OPFN[name] = fn
    OPSIG[name] = (at, rt)


ORACLE = {}
for _c in (-3, -2, 2, 3):
    _nm = 'add' + ('m%d' % -_c if _c < 0 else str(_c))
    _register(_nm + '_all', (L,), L, (lambda c: lambda xs: tuple([x + c for x in xs]))(_c))
    _register(_nm, (I,), I, (lambda c: lambda x: x + c)(_c))
    ORACLE[('add', _c, L)] = _nm + '_all'
    ORACLE[('add', _c, I)] = _nm
for _c in (-2, 3):
    _nm = 'mul' + ('m%d' % -_c if _c < 0 else str(_c))
    _register(_nm + '_all', (L,), L, (lambda c: lambda xs: tuple([x * c for x in xs]))(_c))
    _register(_nm, (I,), I, (lambda c: lambda x: x * c)(_c))
    ORACLE[('mul', _c, L)] = _nm + '_all'
    ORACLE[('mul', _c, I)] = _nm

import q2search                                           # noqa: E402  (after registration)
from q2search import AbsCtx, INF, expected_random_order   # noqa: E402

_TABLE_CACHE = {}


def tables_for(opnames=BASE61, M=2000, kind='iid', seed=0):
    key = (tuple(opnames), M, kind, seed)
    if key not in _TABLE_CACHE:
        _TABLE_CACHE[key] = build_tables(HAND6, M=M, kind=kind, seed=seed, opnames=list(opnames))
    return _TABLE_CACHE[key]


# ------------------------------------------------------------------ the kernel's correction code
# codec.lisp emit-positive (Elias delta) on ast.lisp signed-code; frame.lisp `correction`.
# One change, following rule 5 of plan_v2c.md section 6.2: an exact value costs 1 bit, not 0.
_PB = {}


def pos_bits(v):
    b = _PB.get(v)
    if b is None:
        w = v.bit_length()
        lw = w.bit_length()
        b = _PB[v] = 2 * lw + w - 2
    return b


def int_bits(d):
    """0 -> 1 bit; +-1 -> 4; 2, 3 -> 5; 4 -> 8; 1000 -> 17."""
    return pos_bits(2 * d + 1 if d >= 0 else -2 * d)


def seq_bits(xs):
    return pos_bits(1 + len(xs)) + sum(map(int_bits, xs))


def corr_bits(p, t):
    """Bits to write target value t when prediction p is known.
    int given int : int_bits(t - p)
    list given list: 1 bit if equal; else min(plain code of t,
                      [1 if same length else 1 + int_bits(length change)]
                      + per shared position [1 if equal else 1 + int_bits(difference)]
                      + plain code of each element of t beyond the length of p)
    different types: plain code of t."""
    if p == t:
        return 1
    if isinstance(t, int):
        return int_bits(t - p) if isinstance(p, int) else int_bits(t)
    if isinstance(p, int):
        return seq_bits(t)
    ld = len(t) - len(p)
    b = 1 if ld == 0 else 1 + int_bits(ld)
    for a, c in zip(p, t):
        b += 1 if a == c else 1 + int_bits(c - a)
    if ld > 0:
        for c in t[len(p):]:
            b += int_bits(c)
    return min(seq_bits(t), b)


def col_dl(u, y):
    """Description-length distance of target column y from candidate column u (sum over rows)."""
    return sum(map(corr_bits, u, y))


def col_l1(u, y):
    """L1 distance, or None where it is not defined (different types, or a row whose
    list lengths differ)."""
    tot = 0
    for p, t in zip(u, y):
        if isinstance(t, int):
            if not isinstance(p, int):
                return None
            tot += abs(t - p)
        else:
            if isinstance(p, int) or len(p) != len(t):
                return None
            for a, c in zip(p, t):
                tot += abs(c - a)
    return tot


def col_residual(u, y):
    """Element-wise y - u per row, or None where undefined."""
    out = []
    for p, t in zip(u, y):
        if isinstance(t, int):
            if not isinstance(p, int):
                return None
            out.append(t - p)
        else:
            if isinstance(p, int) or len(p) != len(t):
                return None
            out.append(tuple([c - a for a, c in zip(p, t)]))
    return tuple(out)


_VQ = {L: (Q_SIGN.f[L], Q_PARITY.f[L], Q_ORDER.f[L]),
       I: (Q_SIGN.f[I], Q_PARITY.f[I], Q_ISEMPTY.f[I])}


def regularity(R, ty):
    """'Residual bucket regularity': the number (0..3) of value quotients whose label of
    the residual is the same on every row.  Lists: sign pattern, parity pattern, order.
    Ints: sign, parity, is-zero."""
    if R is None:
        return 0
    return sum(1 for q in _VQ[ty] if len(set(map(q, R))) == 1)


def const_offset(u, y):
    """c if y = u + c element-wise on every row and position (c != 0), else None."""
    c = None
    for p, t in zip(u, y):
        if isinstance(t, int):
            if not isinstance(p, int):
                return None
            d = t - p
            if c is None:
                c = d
            elif d != c:
                return None
        else:
            if isinstance(p, int) or len(p) != len(t):
                return None
            for a, b in zip(p, t):
                d = b - a
                if c is None:
                    c = d
                elif d != c:
                    return None
    return c if c else None


def const_scale(u, y):
    """c if y = c * u element-wise on every row and position (c not 0 or 1), else None."""
    c = None
    for p, t in zip(u, y):
        if isinstance(t, int):
            if not isinstance(p, int):
                return None
            pairs = ((p, t),)
        else:
            if isinstance(p, int) or len(p) != len(t):
                return None
            pairs = zip(p, t)
        for a, b in pairs:
            if a == 0:
                if b != 0:
                    return None
                continue
            if b % a:
                return None
            d = b // a
            if c is None:
                c = d
            elif d != c:
                return None
    return c if c not in (None, 0, 1) else None


def residual_proposal(u, y):
    """The stage-3 proposal for a near miss: ('add', c) or ('mul', c) or None."""
    c = const_offset(u, y)
    if c is not None:
        return ('add', c)
    c = const_scale(u, y)
    if c is not None:
        return ('mul', c)
    return None


# ------------------------------------------------------------------ the bank (plain search)
class Bank:
    """Bottom-up enumeration by size with behaviour dedupe, keeping for every class its
    column, type, size and one representative (operator, argument class ids)."""

    def __init__(self, env, opnames=BASE61_SET):
        self.ops = [o for o in OPS if o[0] in opnames]
        self.cols, self.ty, self.size, self.rep = [], [], [], []
        self.idx = {}
        self.lev = {L: defaultdict(list), I: defaultdict(list)}
        self.ncand = {1: len(env)}
        self.evaluated = len(env)
        for name, col in env.items():
            if col not in self.idx:
                self._add(col, L, 1, name)

    def _add(self, col, ty, size, rep):
        i = len(self.cols)
        self.idx[col] = i
        self.cols.append(col)
        self.ty.append(ty)
        self.size.append(size)
        self.rep.append(rep)
        self.lev[ty][size].append(i)
        return i

    def level(self, s, target=None, store=True, hook=None):
        """Evaluate every candidate of size s.  Returns per-operator counts and first-hit
        positions, the list of hitting candidates (opname, id1, id2), and, if `hook`
        returned true on a newly stored class, the number of candidates evaluated so far."""
        cols, idx, lev = self.cols, self.idx, self.lev
        ns, hs, hits = [], [], []
        total = 0
        for (name, at, rt, fn) in self.ops:
            n = 0
            hit = -1
            if len(at) == 1:
                for i in lev[at[0]].get(s - 1, ()):
                    col = tuple(map(fn, cols[i]))
                    if col == target:
                        if hit < 0:
                            hit = n
                        hits.append((name, i, None))
                    n += 1
                    if store and col not in idx:
                        j = self._add(col, rt, s, (name, i))
                        if hook is not None and hook(col, rt, j):
                            self.evaluated += total + n
                            return dict(hook_at=self.evaluated, hook_id=j)
            else:
                for s1 in range(1, s - 1):
                    A = lev[at[0]].get(s1)
                    B = lev[at[1]].get(s - 1 - s1)
                    if not A or not B:
                        continue
                    for i1 in A:
                        c1 = cols[i1]
                        for i2 in B:
                            col = tuple(map(fn, c1, cols[i2]))
                            if col == target:
                                if hit < 0:
                                    hit = n
                                hits.append((name, i1, i2))
                            n += 1
                            if store and col not in idx:
                                j = self._add(col, rt, s, (name, i1, i2))
                                if hook is not None and hook(col, rt, j):
                                    self.evaluated += total + n
                                    return dict(hook_at=self.evaluated, hook_id=j)
            ns.append(n)
            hs.append(hit)
            total += n
        self.ncand[s] = total
        self.evaluated += total
        return dict(n=ns, hit=hs, hits=hits, total=total, hook_at=None)

    def term(self, i):
        r = self.rep[i]
        if isinstance(r, str):
            return r
        return (r[0],) + tuple(self.term(a) for a in r[1:])


def run_plain(env, target, size_ref, opnames=BASE61_SET):
    """Plain search: levels 2.. until the first level with a hit (at most size_ref).
    Returns (bank, n_star, final) where the bank holds every class of size < n_star and
    `final` is the result of the last level."""
    bank = Bank(env, opnames)
    if target in bank.idx:
        return bank, 1, None
    s = 1
    while s < size_ref:
        s += 1
        r = bank.level(s, target, store=s < size_ref)
        if r['hits']:
            return bank, s, r
    return bank, None, None


def pct_rank(pool, x):
    """Mid-rank percentile of x in pool (which contains x): 0 = best (smallest), 1 = worst;
    0.5 is the expectation for a class drawn at random."""
    n = len(pool)
    if n < 2:
        return None
    better = sum(1 for v in pool if v < x)
    tied = sum(1 for v in pool if v == x)
    return (better + (tied - 1) / 2) / (n - 1)


def gmean(xs):
    xs = [x for x in xs if x is not None and x > 0]
    return math.exp(sum(map(math.log, xs)) / len(xs)) if xs else float('nan')


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else float('nan')


def median(xs):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return float('nan')
    m = len(xs) // 2
    return xs[m] if len(xs) % 2 else (xs[m - 1] + xs[m]) / 2


def boot_ci(xs, seed=0, B=2000):
    """95% bootstrap interval of the mean."""
    xs = [x for x in xs if x is not None]
    if len(xs) < 2:
        return (float('nan'), float('nan'))
    rng = random.Random(seed)
    n = len(xs)
    ms = sorted(sum(rng.choice(xs) for _ in range(n)) / n for _ in range(B))
    return ms[int(0.025 * B)], ms[int(0.975 * B)]


# ------------------------------------------------------------------ label-filtered pass with a hook
def pruned_pass_hook(inputs, target, N, ctx, opnames, hook=None, hook_all=False, stop_after=None):
    """q2search.pruned_pass (same filter, same counting) plus a hook.
    hook(col, type) is called on every newly STORED class (hook_all=False), or on every
    EVALUATED candidate before the label test (hook_all=True).  When it returns true the
    pass stops and reports the number of candidates evaluated so far.
    stop_after: do not enumerate size levels above this one."""
    ops = [o for o in OPS if o[0] in opnames]
    nq = ctx.nq
    lev = {L: defaultdict(lambda: q2search._Lev(nq)), I: defaultdict(lambda: q2search._Lev(nq))}
    seen = set()
    evaluated = 0
    ah, aids_tab = ctx.ah, ctx.aids
    hit = False
    for name, col in inputs.items():
        evaluated += 1
        if col == target:
            hit = True
        if hook_all and hook(col, L):
            return dict(fired=evaluated, hit=hit, evaluated=evaluated)
        if col in seen:
            continue
        a = ctx.abstract(col, L)
        if 1 + ah[a] > N:
            continue
        seen.add(col)
        lev[L][1].add(col, a, aids_tab[a])
        if hook is not None and not hook_all and hook(col, L):
            return dict(fired=evaluated, hit=hit, evaluated=evaluated)
    fin_n, fin_hit = [], []
    for s in range(2, N + 1):
        if stop_after is not None and s > stop_after:
            break
        rem = N - s
        final = s == N
        for t_ in (L, I):
            for k_ in list(lev[t_].keys()):
                lev[t_][k_].freeze()
        for (name, at, rt, fn) in ops:
            n = 0
            h1 = -1
            out = lev[rt][s]
            if len(at) == 1:
                K = lev[at[0]].get(s - 1)
                if K is None or not K.cols:
                    if final:
                        fin_n.append(0)
                        fin_hit.append(-1)
                    continue
                idxs, _ = q2search._unary_idxs(ctx, K, name, rem)
                cols = K.cols
                for i in idxs:
                    col = tuple(map(fn, cols[i]))
                    evaluated += 1
                    if col == target:
                        hit = True
                        if h1 < 0:
                            h1 = n
                    n += 1
                    if hook_all and hook(col, rt):
                        return dict(fired=evaluated, hit=hit, evaluated=evaluated)
                    if final or col in seen:
                        continue
                    a = ctx.abstract(col, rt)
                    if s + ah[a] > N:
                        continue
                    seen.add(col)
                    out.add(col, a, aids_tab[a])
                    if hook is not None and not hook_all and hook(col, rt):
                        return dict(fired=evaluated, hit=hit, evaluated=evaluated)
            else:
                for s1 in range(1, s - 1):
                    A = lev[at[0]].get(s1)
                    B = lev[at[1]].get(s - 1 - s1)
                    if A is None or B is None or not A.cols or not B.cols:
                        continue
                    acols, bcols = A.cols, B.cols
                    for aid1, g1 in A.groups.items():
                        ids1 = aids_tab[aid1]
                        for aid2, g2 in B.groups.items():
                            ids2 = aids_tab[aid2]
                            ok = True
                            for j in range(nq):
                                b = ctx.bq[j].get((name, ids1[j], ids2[j]))
                                if b is None:
                                    b = ctx.bound_q(j, name, ids1[j], ids2[j])
                                if b > rem:
                                    ok = False
                                    break
                            if not ok:
                                continue
                            for i1 in g1:
                                c1 = acols[i1]
                                for i2 in g2:
                                    col = tuple(map(fn, c1, bcols[i2]))
                                    evaluated += 1
                                    if col == target:
                                        hit = True
                                        if h1 < 0:
                                            h1 = n
                                    n += 1
                                    if hook_all and hook(col, rt):
                                        return dict(fired=evaluated, hit=hit, evaluated=evaluated)
                                    if final or col in seen:
                                        continue
                                    a = ctx.abstract(col, rt)
                                    if s + ah[a] > N:
                                        continue
                                    seen.add(col)
                                    out.add(col, a, aids_tab[a])
                                    if hook is not None and not hook_all and hook(col, rt):
                                        return dict(fired=evaluated, hit=hit, evaluated=evaluated)
            if final:
                fin_n.append(n)
                fin_hit.append(h1)
        if hit and not final:
            break
    return dict(fired=None, hit=hit, evaluated=evaluated, fin_n=fin_n, fin_hit=fin_hit,
                stored=len(seen))
