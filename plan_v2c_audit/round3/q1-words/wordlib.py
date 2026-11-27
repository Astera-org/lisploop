"""Word discovery with nothing listed by hand (C3).

A WORD on lists is a small term  xs -> label  whose value set on the probes has
2..CARD labels.  Terms are enumerated bottom-up by node count over a typed
grammar, with behaviour dedupe on the probe pool, exactly as a bottom-up
enumerator with observational equivalence would do it:

  list terms  L ::= xs | g(L) | z(L, L) | k(I, L)          g, z, k: the library's own
                                                           list->list, list x list->list,
                                                           int x list->list operators
  int terms   I ::= c | r(L) | u(I) | b(I, I)              c in 0..5
                    | (any e L) | (all e L) | (count e L)  only with fold=True
              r: the library's own list->int reductions
              u: the library's own int->int operators + granted `sgn`
              b: the library's own int x int->int operators + granted `mod < =`
              e: an int term of <= 3 nodes over the element x (truthy when != 0)
  word        W ::= I  (2..CARD labels on the probes)
                    | (pair W W)                           granted tuple constructor

Sizes are node counts; (pair a b) costs 1 + |a| + |b|; (any e L) costs 1 + |e| + |L|.
Candidates are deduplicated by the partition they induce on the probe pool and
the smallest term is kept.

Scoring (dependency score, "lumpability"), per library operator f whose
arguments and result are all lists:
    1 - H(w(f(x)) | w(x)) / H(w(f(x)))     and 0 when H(w(f(x))) <= vac  (vacuity guard)
A word's score is the mean over those operators.
"""
import math
import operator
import random
import time
from array import array
from collections import Counter

from seqlib import L, I, OPS, OPFN, OPSIG, rand_list

CONSTS = (0, 1, 2, 3, 4, 5)


def _sgn(v):
    return (v > 0) - (v < 0)


def _mod(a, b):
    return a % b if b else 0


def _lt(a, b):
    return 1 if a < b else 0


def _eq(a, b):
    return 1 if a == b else 0


GRANT_U = {'sgn': _sgn}
GRANT_B = {'mod': _mod, '<': _lt, '=': _eq}
FN = dict(OPFN)
FN.update(GRANT_U)
FN.update(GRANT_B)
FOLDS = ('any', 'all', 'count')

LIB_LL = [n for (n, at, rt, fn) in OPS if at == (L,) and rt == L]          # 31
LIB_LLL = [n for (n, at, rt, fn) in OPS if at == (L, L) and rt == L]       # 6
LIB_IL = [n for (n, at, rt, fn) in OPS if at == (I, L) and rt == L]        # 4
LIB_LI = [n for (n, at, rt, fn) in OPS if at == (L,) and rt == I]          # 9
LIB_II = [n for (n, at, rt, fn) in OPS if at == (I,) and rt == I]          # 6
LIB_III = [n for (n, at, rt, fn) in OPS if at == (I, I) and rt == I]       # 5
LISTONLY = LIB_LL + LIB_LLL                                                 # 37 scoring operators
ALL_LIST_OPS = LIB_LL + LIB_LLL + LIB_IL + LIB_LI


# ------------------------------------------------------------------ terms
def tstr(t):
    if isinstance(t, (str, int)):
        return str(t)
    if t[0] == 'in':            # Boolean coarsening: is the label of t[1] one of t[2]?
        return '(in %s {%s})' % (tstr(t[1]), ' '.join(str(x).replace(' ', '') for x in t[2]))
    return '(' + ' '.join([t[0]] + [tstr(a) for a in t[1:]]) + ')'


def tsize(t):
    if isinstance(t, (str, int)):
        return 1
    if t[0] == 'in':
        return 1 + tsize(t[1]) + len(t[2])
    return 1 + sum(tsize(a) for a in t[1:])


def tops(t, out=None):
    if out is None:
        out = set()
    if not isinstance(t, (str, int)):
        out.add(t[0])
        for a in t[1:]:
            tops(a, out)
    return out


def _fold_fn(kind, e):
    if kind == 'any':
        def f(xs):
            for x in xs:
                if e(x):
                    return 1
            return 0
    elif kind == 'all':
        def f(xs):
            for x in xs:
                if not e(x):
                    return 0
            return 1
    else:
        def f(xs):
            n = 0
            for x in xs:
                if e(x):
                    n += 1
            return n
    return f


def compile_term(t):
    """term -> python function of one value (the list xs, the int v, or the element x)."""
    if isinstance(t, str):
        return lambda z: z
    if isinstance(t, int):
        return lambda z, c=t: c
    op = t[0]
    if op == 'pair':
        f1, f2 = compile_term(t[1]), compile_term(t[2])
        return lambda z: (f1(z), f2(z))
    if op == 'in':
        f1 = compile_term(t[1])
        S = frozenset(t[2])
        return lambda z: 1 if f1(z) in S else 0
    if op in FOLDS:
        e = compile_term(t[1])
        ff = _fold_fn(op, e)
        if isinstance(t[2], str):
            return ff
        l = compile_term(t[2])
        return lambda z: ff(l(z))
    fn = FN[op]
    if len(t) == 2:
        if isinstance(t[1], str):
            return fn
        a = compile_term(t[1])
        return lambda z: fn(a(z))
    a1, a2 = t[1], t[2]
    if isinstance(a2, int):
        if isinstance(a1, str):
            return lambda z, c=a2: fn(z, c)
        f1 = compile_term(a1)
        return lambda z, c=a2: fn(f1(z), c)
    if isinstance(a1, int):
        if isinstance(a2, str):
            return lambda z, c=a1: fn(c, z)
        f2 = compile_term(a2)
        return lambda z, c=a1: fn(c, f2(z))
    f1, f2 = compile_term(a1), compile_term(a2)
    return lambda z: fn(f1(z), f2(z))


def canon_bytes(col):
    m = {}
    return bytes([m.setdefault(x, len(m)) for x in col])


def canon_any(col):
    """canonical labels as bytes if <= 255 labels, else None."""
    m = {}
    out = [m.setdefault(x, len(m)) for x in col]
    if len(m) > 255:
        return None, len(m)
    return bytes(out), len(m)


# ------------------------------------------------------------------ element terms (fold forms)
def element_terms():
    """int terms of <= 3 nodes over the element x, one per truthiness pattern on [-100, 100]."""
    dom = list(range(-100, 101))
    out = []
    seen = set()

    def add(t):
        f = compile_term(t)
        key = bytes([1 if f(x) else 0 for x in dom])
        if key in seen or len(set(key)) < 2:
            return
        seen.add(key)
        out.append((tsize(t), t))
    add('x')
    for u in LIB_II + list(GRANT_U):
        add((u, 'x'))
    for b in LIB_III + list(GRANT_B):
        for c in CONSTS:
            add((b, 'x', c))
            add((b, c, 'x'))
    return out


# ------------------------------------------------------------------ enumeration on the pool
def enum_list_words(pool, allowed, S=5, card=8, fold=False, log=None, stats=None):
    """All int-valued terms of <= S nodes over xs (see module docstring), evaluated on
    the pool only.  Returns {partition key (bytes over the pool): (size, term)} for the
    terms with 2..card labels, smallest term per partition.
    `allowed`: the library operator names that may appear."""
    P = len(pool)
    t0 = time.perf_counter()
    gL = [n for n in LIB_LL if n in allowed]
    zL = [n for n in LIB_LLL if n in allowed]
    kL = [n for n in LIB_IL if n in allowed]
    rI = [n for n in LIB_LI if n in allowed]
    uI = [n for n in LIB_II if n in allowed] + list(GRANT_U)
    bI = [n for n in LIB_III if n in allowed] + list(GRANT_B)
    ets = element_terms() if fold else []
    xs_col = tuple(pool)
    Lt = {1: [('xs', xs_col)]}
    seenL = {hash(xs_col)}
    It = {}
    seenI = set()
    words = {}
    nraw = Counter()
    nword = Counter()

    def rec_int(t, s, col):
        nraw[s] += 1
        if s < S:
            if col in seenI:
                return
            seenI.add(col)
        nl = len(set(col))
        if nl < 2:
            return
        if s < S:
            It.setdefault(s, []).append((t, col))
        if nl <= card:
            key = canon_bytes(col)
            if key not in words:
                words[key] = (s, t)
                nword[s] += 1

    def gen_L(s):
        """list terms of exactly s nodes (not stored, not deduplicated against other sizes
        beyond the hash set)."""
        for (t, col) in Lt.get(s - 1, ()):
            for g in gL:
                fn = OPFN[g]
                c2 = tuple(map(fn, col))
                h = hash(c2)
                if h in seenL:
                    continue
                seenL.add(h)
                yield ((g, t), c2)
        for a in range(1, s - 1):
            b = s - 1 - a
            for (t1, c1) in Lt.get(a, ()):
                for (t2, c2) in Lt.get(b, ()):
                    for z in zL:
                        fn = OPFN[z]
                        c3 = tuple(map(fn, c1, c2))
                        h = hash(c3)
                        if h in seenL:
                            continue
                        seenL.add(h)
                        yield ((z, t1, t2), c3)
            if a == 1:
                iargs = [(c, None) for c in CONSTS]
            else:
                iargs = It.get(a, ())
            for (ti, ci) in iargs:
                for (t2, c2) in Lt.get(b, ()):
                    for k in kL:
                        fn = OPFN[k]
                        if ci is None:
                            c3 = tuple([fn(ti, v) for v in c2])
                        else:
                            c3 = tuple(map(fn, ci, c2))
                        h = hash(c3)
                        if h in seenL:
                            continue
                        seenL.add(h)
                        yield ((k, ti, t2), c3)

    nL = Counter({1: 1})
    for s in range(2, S + 1):
        # ---- list terms of size s are stored only while something can still consume them
        if s <= S - 2:
            Lt[s] = list(gen_L(s))
            nL[s] = len(Lt[s])
        # ---- int terms of size s: reductions of list terms of size s-1 (streamed at the top size)
        src = Lt[s - 1] if (s - 1) in Lt else gen_L(s - 1)
        for (t, col) in src:
            if (s - 1) not in Lt:
                nL[s - 1] += 1
            for r in rI:
                rec_int((r, t), s, tuple(map(OPFN[r], col)))
        # fold forms (F e L): size 1 + |e| + |L| = s
        if fold:
            for (es, e) in ets:
                ls = s - 1 - es
                if ls < 1:
                    continue
                ef = compile_term(e)
                for (t, col) in Lt.get(ls, ()):
                    for kind in FOLDS:
                        ff = _fold_fn(kind, ef)
                        rec_int((kind, e, t), s, tuple(map(ff, col)))
        # unary int operators
        for (t, col) in list(It.get(s - 1, ())):
            for u in uI:
                rec_int((u, t), s, tuple(map(FN[u], col)))
        # binary int operators
        for a in range(1, s - 1):
            b = s - 1 - a
            A = [(c, None) for c in CONSTS] if a == 1 else It.get(a, ())
            B = [(c, None) for c in CONSTS] if b == 1 else It.get(b, ())
            for (t1, c1) in list(A):
                for (t2, c2) in list(B):
                    if c1 is None and c2 is None:
                        continue
                    for bo in bI:
                        fn = FN[bo]
                        if c1 is None:
                            col = tuple([fn(t1, y) for y in c2])
                        elif c2 is None:
                            col = tuple([fn(x, t2) for x in c1])
                        else:
                            col = tuple(map(fn, c1, c2))
                        rec_int((bo, t1, t2), s, col)
        if log:
            log('    size %d: %7d int terms generated, %6d new word partitions, %6d distinct list terms of size %d; %.1f s'
                % (s, nraw[s], nword[s], nL[s - 1], s - 1, time.perf_counter() - t0))
    if stats is not None:
        stats.update(raw=dict(nraw), words=dict(nword), lists=dict(nL), secs=time.perf_counter() - t0)
    return words


def enum_int_words(dom, allowed, S=5, card=8, stats=None):
    """Same enumerator for words on an int v, evaluated on the value list `dom`."""
    uI = [n for n in LIB_II if n in allowed] + list(GRANT_U)
    bI = [n for n in LIB_III if n in allowed] + list(GRANT_B)
    It = {1: [('v', tuple(dom))]}
    seenI = {tuple(dom)}
    words = {}
    n = len(dom)

    def rec(t, s, col):
        if col in seenI:
            return
        seenI.add(col)
        nl = len(set(col))
        if nl < 2:
            return
        It.setdefault(s, []).append((t, col))
        if nl <= card:
            key = canon_bytes(col)
            if key not in words:
                words[key] = (s, t)
    for s in range(2, S + 1):
        for (t, col) in list(It.get(s - 1, ())):
            for u in uI:
                rec((u, t), s, tuple(map(FN[u], col)))
        for a in range(1, s - 1):
            b = s - 1 - a
            A = [(c, None) for c in CONSTS] + list(It.get(a, ())) if a == 1 else It.get(a, ())
            B = [(c, None) for c in CONSTS] + list(It.get(b, ())) if b == 1 else It.get(b, ())
            for (t1, c1) in list(A):
                for (t2, c2) in list(B):
                    if c1 is None and c2 is None:
                        continue
                    for bo in bI:
                        fn = FN[bo]
                        if c1 is None:
                            col = tuple([fn(t1, y) for y in c2])
                        elif c2 is None:
                            col = tuple([fn(x, t2) for x in c1])
                        else:
                            col = tuple(map(fn, c1, c2))
                        rec((bo, t1, t2), s, col)
    if stats is not None:
        stats.update(classes=sum(len(v) for v in It.values()))
    return words


# ------------------------------------------------------------------ probes
class Probes:
    """Probe pool, value table and operator rows (as index lists into the value table)."""

    def __init__(self, seed=0, P=800, max_len=8, vmax=9):
        rng = random.Random(seed)
        self.seed, self.P = seed, P
        self.pool = [rand_list(rng, 0, max_len, vmax) for _ in range(P)]
        self.vid = {}
        self.vals = []
        idx = self.idx
        self.pidx = [idx(v) for v in self.pool]
        self.rows = {}            # list-only operators: (I, J or None, K)
        for n in LISTONLY:
            at, rt = OPSIG[n]
            fn = OPFN[n]
            if len(at) == 1:
                self.rows[n] = (self.pidx, None, [idx(fn(v)) for v in self.pool])
            else:
                pa = [rng.choice(self.pool) for _ in range(P)]
                pb = [rng.choice(self.pool) for _ in range(P)]
                self.rows[n] = ([idx(a) for a in pa], [idx(b) for b in pb],
                                [idx(fn(a, b)) for a, b in zip(pa, pb)])
        self.red = {n: [OPFN[n](v) for v in self.pool] for n in LIB_LI}   # reductions on the pool
        self.NV = len(self.vals)
        self.getters = {}
        for n, (Ii, Jj, Kk) in self.rows.items():
            self.getters[n] = (operator.itemgetter(*Ii),
                               operator.itemgetter(*Jj) if Jj is not None else None,
                               operator.itemgetter(*Kk))
        self.pget = operator.itemgetter(*self.pidx)
        # int side
        self.E = list(range(-150, 151))
        self.EI = {v: i for i, v in enumerate(self.E)}
        grid = range(-12, 13)
        self.grid = list(grid)
        self.irows = {}
        EI = self.EI
        for n in LIB_II + LIB_III:
            fn = OPFN[n]
            if OPSIG[n][0] == (I,):
                xs_ = [x for x in grid if -150 <= fn(x) <= 150]
                self.irows[n] = ([EI[x] for x in xs_], None, [EI[fn(x)] for x in xs_])
            else:
                pr = [(x, y) for x in grid for y in grid]
                self.irows[n] = ([EI[x] for x, y in pr], [EI[y] for x, y in pr],
                                 [EI[fn(x, y)] for x, y in pr])

    def idx(self, v):
        i = self.vid.get(v)
        if i is None:
            i = self.vid[v] = len(self.vals)
            self.vals.append(v)
        return i


def Hc(counter, n):
    return -sum(c / n * math.log2(c / n) for c in counter.values())


def lump_hh(lab, nlab, getters, P):
    """(H(out), H(out | in)) for every list-only operator; lab = bytes over the value table."""
    res = array('f')
    for n in LISTONLY:
        gI, gJ, gK = getters[n]
        o = bytes(gK(lab))
        ho = Hc(Counter(o), P)
        if ho < 1e-12:
            res.append(0.0)
            res.append(0.0)
            continue
        a = bytes(gI(lab))
        if nlab <= 8:
            if gJ is None:
                ca = Counter(a)
                j = ((int.from_bytes(a, 'little') << 3) + int.from_bytes(o, 'little')).to_bytes(P, 'little')
                cj = Counter(j)
            else:
                b = bytes(gJ(lab))
                ab = ((int.from_bytes(a, 'little') << 3) + int.from_bytes(b, 'little')).to_bytes(P, 'little')
                ca = Counter(ab)
                cj = Counter(zip(ab, o))
        else:
            if gJ is None:
                ca = Counter(a)
                cj = Counter(zip(a, o))
            else:
                ab = list(zip(a, gJ(lab)))
                ca = Counter(ab)
                cj = Counter(zip(ab, o))
        res.append(ho)
        res.append(max(0.0, Hc(cj, P) - Hc(ca, P)))
    return res


def scores_from_hh(hh, vac, opidx):
    """mean dependency score over the operators with indices opidx (into LISTONLY)."""
    tot = 0.0
    for k in opidx:
        ho = hh[2 * k]
        if ho > vac:
            tot += 1.0 - hh[2 * k + 1] / ho
    return tot / len(opidx)


def lump_generic(a_in, out, n, vac):
    """dependency score for arbitrary label sequences (a_in: sequence of hashables)."""
    ho = Hc(Counter(out), n)
    if ho <= vac:
        return 0.0
    hc = Hc(Counter(zip(a_in, out)), n) - Hc(Counter(a_in), n)
    return 1.0 - max(0.0, hc) / ho


def nmi(a, b, n):
    """normalised mutual information of two label sequences (bytes), by min entropy."""
    ha, hb = Hc(Counter(a), n), Hc(Counter(b), n)
    if ha < 1e-12 or hb < 1e-12:
        return 0.0
    return max(0.0, ha + hb - Hc(Counter(zip(a, b)), n)) / min(ha, hb)
