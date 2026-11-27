"""Probe-generation rules for verb tables, at an equal budget of M operator
evaluations per operator (stdlib only; reuses seqlib from verify-quotients).

Every rule returns `probes`: opname -> (argcols, results), where argcols is a
tuple of lists (one list of M values per argument position).  Operators with
the same argument types share their probe arguments (one probe space per
signature), as in verify-quotients.

BASE distribution (identical to verify-quotients' 'iid' pool):
  lists of length 0..8 with elements uniform in [-9, 9]; ints uniform in [-20, 20].

Rules.  Nothing in (i)-(iv), (vi), (vii) names an edge case.
  iid        (i)   M base values per type; unary operators see the pool, binary
                   operators see M random pairs from the pools.
  strat1     (ii)  "stratified by current words", literal.  Per signature draw
                   C = 20*M candidate argument tuples from the base distribution
                   (independent arguments); put each in the bucket (quotient j,
                   labels of its arguments under j) = one KEY of one verb table;
                   give every OCCUPIED bucket an equal share of the M probes
                   (round-robin over buckets, distinct tuples; a bucket that runs
                   out drops out and its share goes to the others).  A bucket no
                   candidate reaches stays empty: the table then has no entry for
                   it (= "anything", never wrong).  This is rejection sampling
                   with a reservoir per bucket.
  strat2     (ii') the same with buckets = occupied PAIRS of keys across two
                   quotients (j < k, labels under j, labels under k).
  pushD      (iii) a probe value is a base value pushed through d randomly chosen
                   library operators, d uniform in 0..D (D = 1, 2, 3).  Operator
                   chosen uniformly among those returning the needed type; one
                   argument position (chosen at random) carries the rest of the
                   chain, the others are base values.  Uses only the library's
                   signature list.  Binary operators: M random pairs of pool values
                   (arguments independent).
  bankD      (iii') "program-shaped" probes: draw a fresh row (xs, ys base lists);
                   each argument is the value on that row of a random typed term
                   with d operators over the leaves xs, ys (d uniform in 0..D; an
                   int argument needs d >= 1).  The two arguments of a binary
                   operator are evaluated on the SAME row, so they can be
                   correlated (zip_sub(inc_all xs, xs)), as they are inside a search.
  oelogS     (iii'') the enumeration's own evaluations: enumerate every class of
                   size <= S over two list inputs on 2 random rows (plain search
                   with behaviour dedupe), and take as an argument tuple stored
                   classes of the right types read on the same row.  This is what a
                   kernel gets for free: a group-by over (a sample of) the operator
                   applications a search has already performed.
  X+strat1 / X+strat2 (iv)  candidates drawn by rule X (pushD or bankD), then
                   stratified as in (ii).
  hand       (v)   the reviewer's hand-made transforms (exp_devils_advocate.py
                   gen_probes, stratified=True) in my value ranges: for each
                   length 1..8, random s plus sorted(s), sorted desc, abs, 2x,
                   2x+1, constant (s0,)*L, equal-prefix (s0,s0)+s[2:]; about half
                   the pool, the rest base values.  Ints: base.
  scalemix   (vi)  MY ADDITION, not in the review: base lengths, but the element
                   range is drawn per list (r uniform in 1..9, elements uniform in
                   [-r, r]); ints: r uniform in 1..20.  One generic knob ("probe at
                   several scales"); makes ties and zeros common.
  strat1d, strat2d, X+strat1d, X+strat2d : the FIRST version of the stratifier
                   (per-argument reservoirs of DISTINCT values, sampled uniformly);
                   kept because exp_audit_v1.log / exp_main_S300.log used it under
                   the names strat1, strat2, push2+strat1, push2+strat2.  Sampling
                   uniformly among distinct values throws away the natural
                   frequencies of the source and is worse (see report).
  old-iid, old-enriched : exactly the pools of verify-quotients build_tables.
"""
import random
from collections import Counter, defaultdict

from seqlib import L, I, OPNAMES, OPSIG, OPFN, Tables, rand_list, random_term, eval_term

CAND_FACTOR = 20          # candidate tuples per signature = CAND_FACTOR * M (stratified rules)

BY_RET = defaultdict(list)
for _n in OPNAMES:
    BY_RET[OPSIG[_n][1]].append(_n)


# ------------------------------------------------------------------ value samplers
def base_val(rng, ty):
    if ty == L:
        return rand_list(rng, 0, 8, 9)
    return rng.randint(-20, 20)


def chain_val(rng, ty, depth):
    """A base value pushed through exactly `depth` library operators."""
    if depth == 0:
        return base_val(rng, ty)
    name = rng.choice(BY_RET[ty])
    at = OPSIG[name][0]
    k = rng.randrange(len(at))
    args = [chain_val(rng, at[i], depth - 1 if i == k else 0) for i in range(len(at))]
    return OPFN[name](*args)


def scalemix_val(rng, ty):
    if ty == L:
        r = rng.randint(1, 9)
        return tuple(rng.randint(-r, r) for _ in range(rng.randint(0, 8)))
    r = rng.randint(1, 20)
    return rng.randint(-r, r)


def bank_val(rng, ty, D, env):
    """Value on the one-row environment env of a random term with 0..D operators."""
    d = rng.randint(0, D)
    if ty == I and d == 0:
        d = 1
    while True:
        t = random_term(rng, d, OPNAMES, want=ty)
        if t is not None:
            return eval_term(t, env)[0]


def oe_bank(rng, maxsize, rows=2):
    """The classes plain search itself stores: every term of size <= maxsize over two
    list inputs on `rows` random rows, one representative per distinct column."""
    lev = {L: defaultdict(list), I: defaultdict(list)}
    seen = set()
    for _ in range(2):
        col = tuple(base_val(rng, L) for _ in range(rows))
        if col not in seen:
            seen.add(col)
            lev[L][1].append(col)
    for s in range(2, maxsize + 1):
        for name in OPNAMES:
            at, rt = OPSIG[name]
            fn = OPFN[name]
            out = lev[rt][s]
            if len(at) == 1:
                for c in lev[at[0]][s - 1]:
                    col = tuple(map(fn, c))
                    if col not in seen:
                        seen.add(col)
                        out.append(col)
            else:
                for s1 in range(1, s - 1):
                    for c1 in lev[at[0]][s1]:
                        for c2 in lev[at[1]][s - 1 - s1]:
                            col = tuple(map(fn, c1, c2))
                            if col not in seen:
                                seen.add(col)
                                out.append(col)
    return {t: [c for s in sorted(lev[t]) for c in lev[t][s]] for t in (L, I)}


def oelog_sampler(maxsize, rows=2):
    """Argument tuples as the enumeration meets them: pick stored classes of the
    right types from one bank and read them on the same row.  A bank is reused
    for a few draws, then a fresh one (fresh input rows) is enumerated."""
    reuse = 8 * 4 ** (maxsize - 3)
    state = {'bank': None, 'left': 0}

    def draw(rng, sig):
        if state['left'] == 0:
            state['bank'] = oe_bank(rng, maxsize, rows)
            state['left'] = reuse
        state['left'] -= 1
        b = state['bank']
        r = rng.randrange(rows)
        return tuple(rng.choice(b[t])[r] for t in sig)
    return draw


def tuple_sampler(src):
    """draw(rng, sig) -> one argument tuple for an operator with argument types sig."""
    if src.startswith('oelog'):
        return oelog_sampler(int(src[5:]))
    if src in ('iid', 'strat1', 'strat2', 'strat1d', 'strat2d'):
        return lambda rng, sig: tuple(base_val(rng, t) for t in sig)
    if src.startswith('push'):
        D = int(src[4:])
        return lambda rng, sig: tuple(chain_val(rng, t, rng.randint(0, D)) for t in sig)
    if src == 'scalemix':
        return lambda rng, sig: tuple(scalemix_val(rng, t) for t in sig)
    if src.startswith('bank'):
        D = int(src[4:])

        def draw(rng, sig):
            env = {'xs': (base_val(rng, L),), 'ys': (base_val(rng, L),)}
            return tuple(bank_val(rng, t, D, env) for t in sig)
        return draw
    raise ValueError(src)


def hand_list_pool(rng, M):
    ps = [()]
    reps = max(1, M // 128)
    for n in range(1, 9):
        for _ in range(reps):
            s = tuple(rng.randint(-9, 9) for _ in range(n))
            ps.extend([s, tuple(sorted(s)), tuple(sorted(s, reverse=True)),
                       tuple(abs(x) for x in s), tuple(2 * x for x in s),
                       tuple(2 * x + 1 for x in s), (s[0],) * n, (s[0], s[0]) + s[2:]])
    while len(ps) < M:
        ps.append(rand_list(rng, 0, 8, 9))
    return ps[:M]


# ------------------------------------------------------------------ stratification (final)
def bucketize(cands, quotients, sig, mode):
    """bucket -> list of candidate tuples (with multiplicity, in draw order).
    mode 1: bucket = (j, key_j);  mode 2: bucket = (j, k, key_j, key_k), j < k,
    where key_j = the labels of the arguments under quotient j (a verb-table key)."""
    res = defaultdict(list)
    nq = len(quotients)
    if nq < 2:
        mode = 1          # pairs of quotients need two; a single (product) quotient uses its own keys
    fs = [[q.f[t] for t in sig] for q in quotients]
    for c in cands:
        keys = [tuple(f(v) for f, v in zip(fj, c)) for fj in fs]
        if mode == 1:
            for j in range(nq):
                res[(j, keys[j])].append(c)
        else:
            for j in range(nq):
                for k in range(j + 1, nq):
                    res[(j, k, keys[j], keys[k])].append(c)
    return res


def stratified_pool(rng, resv, M):
    """M items, every occupied bucket an equal share, distinct items first."""
    strata = sorted(resv, key=repr)
    rng.shuffle(strata)
    lst = {}
    for s in strata:
        x = list(resv[s])
        rng.shuffle(x)
        lst[s] = x
    pos = dict.fromkeys(strata, 0)
    used = set()
    chosen = []
    active = strata
    while len(chosen) < M and active:
        nxt = []
        for s in active:
            if len(chosen) >= M:
                break
            x, p = lst[s], pos[s]
            while p < len(x) and x[p] in used:
                p += 1
            if p < len(x):
                used.add(x[p])
                chosen.append(x[p])
                p += 1
                nxt.append(s)
            pos[s] = p
        active = nxt
    k = 0
    n0 = len(chosen)
    while len(chosen) < M:           # fewer distinct candidates than M (ints): repeat
        chosen.append(chosen[k % n0])
        k += 1
    return chosen


# ------------------------------------------------------------------ stratification (first version)
def reservoirs_d(cands, quotients, ty, mode):
    res = defaultdict(dict)
    nq = len(quotients)
    fs = [q.f[ty] for q in quotients]
    for v in cands:
        labs = [f(v) for f in fs]
        if mode == 1:
            for j in range(nq):
                res[(j, labs[j])][v] = None
        else:
            for j in range(nq):
                for k in range(j + 1, nq):
                    res[(j, k, labs[j], labs[k])][v] = None
    return {s: list(d) for s, d in res.items()}


reservoirs = reservoirs_d       # name used by revD_vary.py


def joint_key_pairs(rng, resv0, resv1, M, nq):
    keys = []
    for j in range(nq):
        a0 = [s for s in resv0 if s[0] == j]
        a1 = [s for s in resv1 if s[0] == j]
        keys += [(s0, s1) for s0 in a0 for s1 in a1]
    keys.sort(key=repr)
    rng.shuffle(keys)
    xs, ys = [], []
    i = 0
    while len(xs) < M:
        s0, s1 = keys[i % len(keys)]
        xs.append(rng.choice(resv0[s0]))
        ys.append(rng.choice(resv1[s1]))
        i += 1
    return xs, ys


def indep_bucket_vals(rng, resv, M):
    strata = sorted(resv, key=repr)
    return [rng.choice(resv[rng.choice(strata)]) for _ in range(M)]


# ------------------------------------------------------------------ rules
def gen_probes(rule, M, seed, quotients, opnames=None, info=None):
    """Return probes: opname -> ((argcol, ...), results)."""
    opnames = opnames or OPNAMES
    if rule in ('old-iid', 'old-enriched'):
        from seqlib import make_pools, eval_probes
        rng = random.Random(seed)
        pools = make_pools(rng, M, rule[4:], opnames)
        pr = eval_probes(rng, pools, M, opnames)
        probes = {}
        for name in opnames:
            at, rt = OPSIG[name]
            idx, res = pr[name]
            if len(at) == 1:
                probes[name] = ((pools[at[0]],), res)
            else:
                probes[name] = (([pools[at[0]][a] for a, b in idx],
                                 [pools[at[1]][b] for a, b in idx]), res)
        return probes
    rng = random.Random(seed * 7919 + 13)
    parts = rule.split('+')
    src = parts[0]
    smode = parts[-1] if parts[-1].startswith('strat') else None
    sigs = sorted({OPSIG[n][0] for n in opnames})
    cols = {}                     # signature -> tuple of argument columns
    if src == 'hand':
        pool = {L: hand_list_pool(rng, M), I: [base_val(rng, I) for _ in range(M)]}
        draw = None
    else:
        draw = tuple_sampler(src)
    if smode is None:
        if src.startswith('bank') or src.startswith('oelog'):
            for sg in sigs:
                c = [draw(rng, sg) for _ in range(M)]
                cols[sg] = tuple(list(x) for x in zip(*c))
        else:
            if src != 'hand':
                pool = {t: [draw(rng, (t,))[0] for _ in range(M)] for t in (L, I)}
            for sg in sigs:
                if len(sg) == 1:
                    cols[sg] = (pool[sg[0]],)
                else:
                    p0, p1 = pool[sg[0]], pool[sg[1]]
                    cols[sg] = ([p0[rng.randrange(M)] for _ in range(M)],
                                [p1[rng.randrange(M)] for _ in range(M)])
    elif smode in ('strat1', 'strat2'):
        mode = int(smode[5])
        C = CAND_FACTOR * M
        nb = {}
        for sg in sigs:
            cands = [draw(rng, sg) for _ in range(C)]
            resv = bucketize(cands, quotients, sg, mode)
            nb[sg] = len(resv)
            chosen = stratified_pool(rng, resv, M)
            cols[sg] = tuple(list(x) for x in zip(*chosen))
        if info is not None:
            info['buckets'] = {''.join(sg): n for sg, n in nb.items()}
    elif smode in ('strat1d', 'strat2d'):
        mode = int(smode[5])
        C = CAND_FACTOR * M
        cands = {t: [draw(rng, (t,))[0] for _ in range(C)] for t in (L, I)}
        resv = {t: reservoirs_d(cands[t], quotients, t, mode) for t in (L, I)}
        pool = {t: stratified_pool(rng, resv[t], M) for t in (L, I)}
        if info is not None:
            info['buckets'] = {t: len(resv[t]) for t in (L, I)}
        for sg in sigs:
            if len(sg) == 1:
                cols[sg] = (pool[sg[0]],)
            elif mode == 1:
                cols[sg] = joint_key_pairs(rng, resv[sg[0]], resv[sg[1]], M, len(quotients))
            else:
                cols[sg] = (indep_bucket_vals(rng, resv[sg[0]], M),
                            indep_bucket_vals(rng, resv[sg[1]], M))
    else:
        raise ValueError(rule)
    probes = {}
    for name in opnames:
        at, rt = OPSIG[name]
        c = cols[at]
        probes[name] = (c, list(map(OPFN[name], *c)))
    return probes


# ------------------------------------------------------------------ tables
class PTables(Tables):
    """Tables built from per-operator probe lists (same fields as seqlib.Tables)."""

    def __init__(self, quotients, probes, opnames=None):
        self.q = quotients
        self.opnames = opnames or OPNAMES
        self.tab = []
        self.dom = []
        for q in quotients:
            cache = {}
            dom = {L: set(), I: set()}
            tab = {}
            for name in self.opnames:
                at, rt = OPSIG[name]
                argcols, res = probes[name]
                ares = list(map(q.f[rt], res))
                dom[rt].update(ares)
                labs = []
                for i, col in enumerate(argcols):
                    lb = cache.get(id(col))
                    if lb is None:
                        lb = cache[id(col)] = list(map(q.f[at[i]], col))
                        dom[at[i]].update(lb)
                    labs.append(lb)
                t = defaultdict(Counter)
                for key, r in zip(zip(*labs), ares):
                    t[key][r] += 1
                tab[name] = dict(t)
            self.tab.append(tab)
            self.dom.append(dom)
        self._succ = [None] * len(quotients)

    # --- derived tables -------------------------------------------------
    def _copy_with(self, keep):
        import copy
        t = copy.copy(self)
        t.tab = [{name: {k: c for k, c in d.items() if keep(c)} for name, d in tab.items()}
                 for tab in self.tab]
        t.dom = self.dom
        t._succ = [None] * len(self.q)
        return t

    def min_count(self, k):
        """Cheapest guard: an input key counts as unseen unless probed >= k times."""
        return self._copy_with(lambda c: sum(c.values()) >= k)

    def guard(self, k, s):
        """verify-quotients' guard: probed >= k times AND every output seen > s times."""
        return self._copy_with(lambda c: sum(c.values()) >= k and min(c.values()) > s)

    def deterministic_only(self):
        """Keep only the entries with exactly one output label."""
        return self._copy_with(lambda c: len(c) == 1)

    def clone(self):
        import copy
        t = copy.copy(self)
        t.tab = [{name: {k: Counter(c) for k, c in d.items()} for name, d in tab.items()}
                 for tab in self.tab]
        t.dom = [{ty: set(s) for ty, s in dom.items()} for dom in self.dom]
        t._succ = [None] * len(self.q)
        return t

    def add_transition(self, j, name, key, ar, create=False):
        """Online feedback: record one more (key -> output label).  With
        create=False an unseen key stays unseen (it was never wrong)."""
        d = self.tab[j][name]
        c = d.get(key)
        if c is None:
            if not create:
                return False
            c = d[key] = Counter()
        if ar in c:
            return False
        c[ar] += 1
        dm = self.dom[j][OPSIG[name][1]]
        grew = ar not in dm
        dm.add(ar)
        self._succ[j] = None
        self.dom_grew = getattr(self, 'dom_grew', 0) + grew
        return True

    def n_pairs(self):
        return sum(len(c) for tab in self.tab for d in tab.values() for c in d.values())

    def n_det(self):
        return sum(1 for tab in self.tab for d in tab.values() for c in d.values() if len(c) == 1)

    def n_single(self):
        return sum(1 for tab in self.tab for d in tab.values() for c in d.values()
                   for v in c.values() if v == 1)


def make_tables(rule, M, seed, quotients, opnames=None, info=None):
    return PTables(quotients, gen_probes(rule, M, seed, quotients, opnames, info), opnames)
