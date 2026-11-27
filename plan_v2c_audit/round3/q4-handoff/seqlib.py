"""Shared library for the Q2 / Q1-seq / Q5 experiments (stdlib only).

Values: lists are tuples of ints ('L'), scalars are ints ('I').
A COLUMN is a tuple with one value per example row.
All operators are TOTAL (head/last/min_el/max_el of the empty list = 0).
"""
import heapq
import math
import operator
import random
import time
from collections import Counter, defaultdict

L, I = 'L', 'I'
MINSIZE = {L: 1, I: 2}     # smallest term of each type (task inputs are lists)


def _adj(fn):
    def g(xs):
        return tuple(map(fn, xs, xs[1:]))
    return g


def _zip(fn):
    def g(xs, ys):
        return tuple(map(fn, xs, ys))
    return g


def _running(fn):
    def g(xs):
        out = []
        acc = None
        for x in xs:
            acc = x if acc is None else fn(acc, x)
            out.append(acc)
        return tuple(out)
    return g


def _dedup_adj(xs):
    out = []
    for x in xs:
        if not out or out[-1] != x:
            out.append(x)
    return tuple(out)


_sub_rev = lambda a, b: b - a      # map_adj_sub: xs[i+1] - xs[i]

# (name, argtypes, rettype, fn).  Order = "library order"; the first operators
# follow the order in which the review lists them.
OPS = [
    # element-wise maps  L -> L
    ('inc_all', (L,), L, lambda xs: tuple([x + 1 for x in xs])),
    ('dbl_all', (L,), L, lambda xs: tuple([x + x for x in xs])),
    ('abs_all', (L,), L, lambda xs: tuple(map(abs, xs))),
    ('neg_all', (L,), L, lambda xs: tuple(map(operator.neg, xs))),
    ('dec_all', (L,), L, lambda xs: tuple([x - 1 for x in xs])),
    ('sq_all', (L,), L, lambda xs: tuple([x * x for x in xs])),
    ('half_all', (L,), L, lambda xs: tuple([x // 2 for x in xs])),
    # adjacent maps  L -> L   (length n -> n-1)
    ('map_adj_add', (L,), L, _adj(operator.add)),
    ('map_adj_sub', (L,), L, _adj(_sub_rev)),
    ('map_adj_mul', (L,), L, _adj(operator.mul)),
    ('map_adj_min', (L,), L, _adj(min)),
    ('map_adj_max', (L,), L, _adj(max)),
    # zips  L x L -> L   (truncate to the shorter)
    ('zip_add', (L, L), L, _zip(operator.add)),
    ('zip_sub', (L, L), L, _zip(operator.sub)),
    ('zip_mul', (L, L), L, _zip(operator.mul)),
    ('zip_min', (L, L), L, _zip(min)),
    ('zip_max', (L, L), L, _zip(max)),
    # filters  L -> L
    ('filter_pos', (L,), L, lambda xs: tuple([x for x in xs if x > 0])),
    ('filter_neg', (L,), L, lambda xs: tuple([x for x in xs if x < 0])),
    ('filter_even', (L,), L, lambda xs: tuple([x for x in xs if not x & 1])),
    ('filter_odd', (L,), L, lambda xs: tuple([x for x in xs if x & 1])),
    # structural  L -> L
    ('sort', (L,), L, lambda xs: tuple(sorted(xs))),
    ('sort_desc', (L,), L, lambda xs: tuple(sorted(xs, reverse=True))),
    ('reverse', (L,), L, lambda xs: xs[::-1]),
    ('shift1', (L,), L, lambda xs: xs[1:] + xs[:1]),       # rotate left by one
    ('tail', (L,), L, lambda xs: xs[1:]),
    ('init', (L,), L, lambda xs: xs[:-1]),
    ('take2', (L,), L, lambda xs: xs[:2]),
    ('take3', (L,), L, lambda xs: xs[:3]),
    ('drop2', (L,), L, lambda xs: xs[2:]),
    ('concat', (L, L), L, operator.add),
    ('running_sum', (L,), L, _running(operator.add)),
    ('running_max', (L,), L, _running(max)),
    ('running_min', (L,), L, _running(min)),
    ('dedup_adj', (L,), L, _dedup_adj),
    ('evens_idx', (L,), L, lambda xs: xs[0::2]),
    ('odds_idx', (L,), L, lambda xs: xs[1::2]),
    # reductions  L -> I
    ('sum', (L,), I, sum),
    ('len', (L,), I, len),
    ('head', (L,), I, lambda xs: xs[0] if xs else 0),
    ('last', (L,), I, lambda xs: xs[-1] if xs else 0),
    ('min_el', (L,), I, lambda xs: min(xs) if xs else 0),
    ('max_el', (L,), I, lambda xs: max(xs) if xs else 0),
    ('count_pos', (L,), I, lambda xs: sum(1 for x in xs if x > 0)),
    ('count_even', (L,), I, lambda xs: sum(1 for x in xs if not x & 1)),
    ('count_distinct', (L,), I, lambda xs: len(set(xs))),
    # scalar  I -> I
    ('inc', (I,), I, lambda x: x + 1),
    ('dec', (I,), I, lambda x: x - 1),
    ('dbl', (I,), I, lambda x: x + x),
    ('neg', (I,), I, operator.neg),
    ('abs', (I,), I, abs),
    ('sq', (I,), I, lambda x: x * x),
    # scalar  I x I -> I
    ('add', (I, I), I, operator.add),
    ('sub', (I, I), I, operator.sub),
    ('mul', (I, I), I, operator.mul),
    ('min', (I, I), I, min),
    ('max', (I, I), I, max),
    # mixed  I x L -> L
    ('cons', (I, L), L, lambda n, xs: (n,) + xs),
    ('add_k', (I, L), L, lambda n, xs: tuple([n + x for x in xs])),
    ('mul_k', (I, L), L, lambda n, xs: tuple([n * x for x in xs])),
    ('take_n', (I, L), L, lambda n, xs: xs[:n] if n > 0 else ()),
]
OPNAMES = [o[0] for o in OPS]
OPIDX = {o[0]: i for i, o in enumerate(OPS)}
OPFN = {o[0]: o[3] for o in OPS}
OPSIG = {o[0]: (o[1], o[2]) for o in OPS}
assert len(OPS) == 61 and len(set(OPNAMES)) == 61


# ----------------------------------------------------------------- terms
def term_ops(t):
    if isinstance(t, str):
        return []
    out = [t[0]]
    for a in t[1:]:
        out += term_ops(a)
    return out


def term_size(t):
    if isinstance(t, str):
        return 1
    return 1 + sum(term_size(a) for a in t[1:])


def term_leaves(t):
    if isinstance(t, str):
        return [t]
    out = []
    for a in t[1:]:
        out += term_leaves(a)
    return out


def term_str(t):
    if isinstance(t, str):
        return t
    return t[0] + '(' + ', '.join(term_str(a) for a in t[1:]) + ')'


def term_type(t):
    if isinstance(t, str):
        return L
    return OPSIG[t[0]][1]


def eval_term(t, env):
    """env: name -> column (tuple over rows). Returns a column."""
    if isinstance(t, str):
        return env[t]
    fn = OPFN[t[0]]
    args = [eval_term(a, env) for a in t[1:]]
    return tuple(map(fn, *args))


def subterms(t, depth=0, out=None):
    """All subterm occurrences as (term, depth below root)."""
    if out is None:
        out = []
    out.append((t, depth))
    if not isinstance(t, str):
        for a in t[1:]:
            subterms(a, depth + 1, out)
    return out


def parse(s):
    """Parse 'sum(map_adj_sub(sort(xs)))' into nested tuples."""
    s = s.replace(' ', '')
    pos = 0

    def p():
        nonlocal pos
        j = pos
        while j < len(s) and (s[j].isalnum() or s[j] == '_'):
            j += 1
        name = s[pos:j]
        pos = j
        if pos < len(s) and s[pos] == '(':
            pos += 1
            args = [p()]
            while s[pos] == ',':
                pos += 1
                args.append(p())
            assert s[pos] == ')'
            pos += 1
            return (name,) + tuple(args)
        return name
    t = p()
    assert pos == len(s), s
    return t


# ----------------------------------------------------------------- inputs
def rand_list(rng, lo_len, hi_len, vmax):
    return tuple(rng.randint(-vmax, vmax) for _ in range(rng.randint(lo_len, hi_len)))


def make_inputs(rng, names, rows=8, lo_len=2, hi_len=7, vmax=9):
    return {n: tuple(rand_list(rng, lo_len, hi_len, vmax) for _ in range(rows)) for n in names}


# ----------------------------------------------------------------- random typed terms
def random_term(rng, n_ops, opnames, want=None, p_ys=0.3, max_size=None):
    """Uniform-ish random typed term with exactly n_ops operators.
    Leaves are list inputs xs / ys.  Returns None on failure."""
    by_ret = defaultdict(list)
    for n in opnames:
        by_ret[OPSIG[n][1]].append(n)

    def gen(ty, n):
        if n == 0:
            if ty != L:
                return None
            return 'ys' if rng.random() < p_ys else 'xs'
        cands = by_ret[ty][:]
        rng.shuffle(cands)
        for name in cands:
            at = OPSIG[name][0]
            if len(at) == 1:
                sub = gen(at[0], n - 1)
                if sub is not None:
                    return (name, sub)
            else:
                rest = n - 1
                # an I argument needs at least one op
                lo0 = 1 if at[0] == I else 0
                lo1 = 1 if at[1] == I else 0
                if rest < lo0 + lo1:
                    continue
                k = rng.randint(lo0, rest - lo1)
                a = gen(at[0], k)
                b = gen(at[1], rest - k)
                if a is not None and b is not None:
                    return (name, a, b)
        return None

    for _ in range(200):
        ty = want or rng.choice([L, L, I])
        t = gen(ty, n_ops)
        if t is None:
            continue
        if max_size is not None and term_size(t) > max_size:
            continue
        return t
    return None


def nondegenerate(t, env):
    """Reject tasks whose output is constant over rows, or equals the column of
    an input or of a proper subterm (an operator that is a no-op on these rows)."""
    col = eval_term(t, env)
    if len(set(col)) < 3:
        return False
    for (u, d) in subterms(t):
        if d == 0:
            continue
        if eval_term(u, env) == col:
            return False
    # every proper subterm must itself be non-constant, and each op must change its argument
    for (u, d) in subterms(t):
        if isinstance(u, str):
            continue
        cu = eval_term(u, env)
        if len(set(cu)) < 2:
            return False
        for a in u[1:]:
            if eval_term(a, env) == cu:
                return False
    return True


# ----------------------------------------------------------------- quotients
class Quotient:
    """A 'word': a pair of small maps, one per value type, into a small finite set."""

    def __init__(self, name, fL, fI):
        self.name = name
        self.f = {L: fL, I: fI}


def _sgn(x):
    return (x > 0) - (x < 0)


def _q_sign_L(xs):
    neg = pos = 0
    for x in xs:
        if x < 0:
            neg = 1
        elif x > 0:
            pos = 2
    return neg + pos


def _q_par_L(xs):
    r = 0
    for x in xs:
        r |= 2 if x & 1 else 1
        if r == 3:
            break
    return r


def _q_order_L(xs):
    asc = desc = True
    for a, b in zip(xs, xs[1:]):
        if a > b:
            asc = False
        elif a < b:
            desc = False
    return asc + 2 * desc


_triv = lambda x: 0

Q_SIGN = Quotient('sign', _q_sign_L, _sgn)                     # L: (any<0, any>0)   I: sgn
Q_PARITY = Quotient('parity', _q_par_L, lambda x: x & 1)        # L: (any even, any odd)  I: x mod 2
Q_ORDER = Quotient('order', _q_order_L, _triv)                  # L: (non-decr, non-incr)  I: trivial
Q_CAPLEN = Quotient('caplen5', lambda xs: min(len(xs), 5), _triv)
Q_LENMOD2 = Quotient('lenmod2', lambda xs: len(xs) & 1, _triv)
Q_ISEMPTY = Quotient('isempty', lambda xs: not xs, lambda x: x == 0)
HAND6 = [Q_SIGN, Q_PARITY, Q_ORDER, Q_CAPLEN, Q_LENMOD2, Q_ISEMPTY]
QBYNAME = {q.name: q for q in HAND6}


def product_quotient(name, qs):
    fl = [q.f[L] for q in qs]
    fi = [q.f[I] for q in qs]
    return Quotient(name, lambda xs: tuple(f(xs) for f in fl), lambda x: tuple(f(x) for f in fi))


# ----------------------------------------------------------------- probe pools and tables
def make_pools(rng, M, kind='iid', opnames=None, max_len=8, vmax=9):
    """Probe values per type.
    'iid'      : lists of length 0..max_len with elements uniform in [-vmax, vmax];
                 ints uniform in [-20, 20].
    'enriched' : half as above; the other half are those values pushed through one
                 random library operator (so sorted / all-even / non-negative /
                 empty lists are well represented)."""
    opnames = opnames or OPNAMES
    pl = [rand_list(rng, 0, max_len, vmax) for _ in range(M)]
    pi = [rng.randint(-20, 20) for _ in range(M)]
    if kind == 'enriched':
        l2l = [n for n in opnames if OPSIG[n] == ((L,), L)]
        l2i = [n for n in opnames if OPSIG[n] == ((L,), I)]
        for k in range(M // 2, M):
            pl[k] = OPFN[rng.choice(l2l)](pl[k])
            pi[k] = OPFN[rng.choice(l2i)](rand_list(rng, 0, max_len, vmax))
    elif kind != 'iid':
        raise ValueError(kind)
    return {L: pl, I: pi}


def eval_probes(rng, pools, M, opnames=None):
    """The 'probe table' of each operator: argument index tuples and results."""
    opnames = opnames or OPNAMES
    out = {}
    for name in opnames:
        at, rt = OPSIG[name]
        fn = OPFN[name]
        if len(at) == 1:
            pool = pools[at[0]]
            idx = [(k,) for k in range(min(M, len(pool)))]
            res = [fn(pool[k]) for (k,) in idx]
        else:
            p0, p1 = pools[at[0]], pools[at[1]]
            idx = [(rng.randrange(len(p0)), rng.randrange(len(p1))) for _ in range(M)]
            res = [fn(p0[a], p1[b]) for (a, b) in idx]
        out[name] = (idx, res)
    return out


class Tables:
    """Pushed-forward operator tables for a list of quotients.

    tab[j][opname][abstract-arg-tuple] = Counter(abstract result)
    dom[j][type] = set of abstract values of that type seen anywhere."""

    def __init__(self, quotients, pools, probes, opnames=None):
        self.q = quotients
        self.opnames = opnames or OPNAMES
        self.tab = []
        self.dom = []
        for q in quotients:
            aL = list(map(q.f[L], pools[L]))
            aI = list(map(q.f[I], pools[I]))
            apool = {L: aL, I: aI}
            dom = {L: set(aL), I: set(aI)}
            tab = {}
            for name in self.opnames:
                at, rt = OPSIG[name]
                idx, res = probes[name]
                ares = list(map(q.f[rt], res))
                dom[rt].update(ares)
                t = defaultdict(Counter)
                if len(at) == 1:
                    a0 = apool[at[0]]
                    for (k,), r in zip(idx, ares):
                        t[(a0[k],)][r] += 1
                else:
                    a0, a1 = apool[at[0]], apool[at[1]]
                    for (k0, k1), r in zip(idx, ares):
                        t[(a0[k0], a1[k1])][r] += 1
                tab[name] = dict(t)
            self.tab.append(tab)
            self.dom.append(dom)
        self._succ = [None] * len(quotients)

    def succ(self, j):
        """One-step abstract successor relation for quotient j, as a dict
        (type, a) -> {(type, a'): size cost}.  The value is taken as ANY one
        argument of ANY operator, the other argument (if any) ranging over the
        whole abstract domain; an abstract argument tuple never seen in the
        probes gives TOP (every abstract value of the result type).
        Size cost of a step = 1 for the operator + the smallest possible size
        of the sibling argument (a list leaf = 1; an int needs >= 2 nodes,
        because task inputs are lists)."""
        if self._succ[j] is not None:
            return self._succ[j]
        dom, tab = self.dom[j], self.tab[j]
        succ = defaultdict(dict)

        def add(src, res, cost):
            d = succ[src]
            for r in res:
                if d.get(r, 99) > cost:
                    d[r] = cost
        for name in self.opnames:
            at, rt = OPSIG[name]
            t = tab[name]
            top = [(rt, v) for v in dom[rt]]
            if len(at) == 1:
                for a in dom[at[0]]:
                    c = t.get((a,))
                    add((at[0], a), top if c is None else [(rt, v) for v in c], 1)
            else:
                for a in dom[at[0]]:
                    for b in dom[at[1]]:
                        c = t.get((a, b))
                        res = top if c is None else [(rt, v) for v in c]
                        add((at[0], a), res, 1 + MINSIZE[at[1]])
                        add((at[1], b), res, 1 + MINSIZE[at[0]])
        self._succ[j] = succ
        return succ

    def dist_to(self, j, ty, t):
        """Backward Dijkstra: (type, a) -> least number of extra term nodes with
        which a value of abstract value a can be turned into one of abstract
        value (ty, t).  Admissible if the tables are complete on the transitions used."""
        succ = self.succ(j)
        pred = defaultdict(list)
        for a, ss in succ.items():
            for s, c in ss.items():
                pred[s].append((a, c))
        d = {(ty, t): 0}
        heap = [(0, 0, (ty, t))]
        k = 0
        while heap:
            ds, _, s = heapq.heappop(heap)
            if ds > d.get(s, 99):
                continue
            for a, c in pred[s]:
                nd = ds + c
                if nd < d.get(a, 99):
                    d[a] = nd
                    k += 1
                    heapq.heappush(heap, (nd, k, a))
        return d

    def guarded(self, kmin=30, smin=1):
        """A more cautious copy: an abstract argument tuple is treated as unseen
        (TOP) unless the probes hit it at least kmin times AND every abstract
        result recorded for it was seen more than smin times (a result seen only
        once or twice is evidence that other results are still missing)."""
        import copy
        t = copy.copy(self)
        t.tab = []
        for tab in self.tab:
            nt = {}
            for name, d in tab.items():
                nt[name] = {k: c for k, c in d.items()
                            if sum(c.values()) >= kmin and min(c.values()) > smin}
            t.tab.append(nt)
        t._succ = [None] * len(self.q)
        return t

    def n_entries(self):
        return sum(len(t) for tab in self.tab for t in tab.values())

    def n_states(self):
        return [sum(len(d) for d in dom.values()) for dom in self.dom]


def build_tables(quotients, M=2000, kind='iid', seed=0, opnames=None, timing=None):
    rng = random.Random(seed)
    t0 = time.perf_counter()
    pools = make_pools(rng, M, kind, opnames)
    t1 = time.perf_counter()
    probes = eval_probes(rng, pools, M, opnames)
    t2 = time.perf_counter()
    tb = Tables(quotients, pools, probes, opnames)
    t3 = time.perf_counter()
    if timing is not None:
        timing.update(pool_s=t1 - t0, probe_eval_s=t2 - t1, groupby_s=t3 - t2)
    return tb
