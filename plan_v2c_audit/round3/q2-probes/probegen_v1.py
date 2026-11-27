"""Probe-generation rules for verb tables, at an equal budget of M operator
evaluations per operator (stdlib only; reuses seqlib from verify-quotients).

Every rule returns `probes`: opname -> (argcols, results), where argcols is a
tuple of lists (one list of M values per argument position).

BASE distribution (identical to verify-quotients' 'iid' pool):
  lists of length 0..8 with elements uniform in [-9, 9]; ints uniform in [-20, 20].

Rules (nothing in i-iv, vi names an edge case):
  iid        (i)   M base values per type; unary operators see the pool, binary
                   operators see M random pairs from the pools.
  strat1     (ii)  "stratified by current words", literal: draw C = 20*M base
                   candidates per type, put each in the bucket (quotient j, label a)
                   it falls in, and give every OCCUPIED bucket an equal share of the
                   M probes (round-robin over buckets, distinct values; a bucket
                   that runs out of distinct values drops out and its share goes to
                   the others).  A bucket no candidate reaches stays empty: the
                   table then has no entry for it (= "anything", never wrong).
                   Binary operators: every occupied KEY (quotient j, label of arg 1,
                   label of arg 2) gets an equal share; arguments are drawn from the
                   two buckets' reservoirs.
  strat2     (ii') the same with buckets = occupied PAIRS of labels across two
                   quotients (j < k, a_j, a_k).  Binary operators: each argument
                   drawn independently from a uniformly chosen pair-bucket.
  pushD      (iii) a probe value is a base value pushed through d randomly chosen
                   library operators, d uniform in 0..D (D = 1, 2, 3).  Operator
                   chosen uniformly among those returning the needed type; one
                   argument position (chosen at random) carries the rest of the
                   chain, the others are base values.  Uses only the library's
                   signature list.
  pushD+strat1 / pushD+strat2 (iv)  candidates drawn by pushD, then stratified.
  hand       (v)   the reviewer's hand-made transforms (exp_devils_advocate.py
                   gen_probes, stratified=True) in my value ranges: for each
                   length 1..8, random s plus sorted(s), sorted desc, abs, 2x,
                   2x+1, constant (s0,)*L, equal-prefix (s0,s0)+s[2:]; about half
                   the pool, the rest base values.  Ints: base.
  scalemix   (vi)  MY ADDITION, not in the review: base lengths, but the element
                   range is drawn per list (r uniform in 1..9, elements uniform in
                   [-r, r]); ints: r uniform in 1..20.  One generic knob ("probe at
                   several scales"); makes ties and zeros common.
"""
import random
from collections import Counter, defaultdict

from seqlib import L, I, OPNAMES, OPSIG, OPFN, Tables, rand_list

CAND_FACTOR = 20          # candidates per type = CAND_FACTOR * M for the stratified rules

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


def push_sampler(D):
    def f(rng, ty):
        return chain_val(rng, ty, rng.randint(0, D))
    return f


def scalemix_val(rng, ty):
    if ty == L:
        r = rng.randint(1, 9)
        return tuple(rng.randint(-r, r) for _ in range(rng.randint(0, 8)))
    r = rng.randint(1, 20)
    return rng.randint(-r, r)


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


# ------------------------------------------------------------------ stratification
def reservoirs(cands, quotients, ty, mode):
    """bucket -> list of distinct candidate values in it.
    mode 1: bucket = (j, label_j);  mode 2: bucket = (j, k, label_j, label_k), j < k."""
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


def stratified_pool(rng, resv, M):
    """M values, every occupied bucket an equal share, distinct values first."""
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


def joint_key_pairs(rng, resv0, resv1, M, nq):
    """M argument pairs for a binary signature: every occupied key (quotient j,
    label of arg 1, label of arg 2) gets an equal share."""
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
        # exactly the pools of verify-quotients build_tables(kind, seed): consistency check
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
    strat = 0
    if rule.endswith('+strat1') or rule == 'strat1':
        strat = 1
    elif rule.endswith('+strat2') or rule == 'strat2':
        strat = 2
    src = rule.split('+')[0]
    if src in ('iid', 'strat1', 'strat2'):
        sampler = base_val
    elif src.startswith('push'):
        sampler = push_sampler(int(src[4:]))
    elif src == 'scalemix':
        sampler = scalemix_val
    elif src == 'hand':
        sampler = None
    else:
        raise ValueError(rule)
    sigs = sorted({OPSIG[n][0] for n in opnames if len(OPSIG[n][0]) == 2})
    pairs = {}
    if strat == 0:
        if src == 'hand':
            pool = {L: hand_list_pool(rng, M), I: [base_val(rng, I) for _ in range(M)]}
        else:
            pool = {t: [sampler(rng, t) for _ in range(M)] for t in (L, I)}
        for sg in sigs:
            p0, p1 = pool[sg[0]], pool[sg[1]]
            pairs[sg] = ([p0[rng.randrange(M)] for _ in range(M)],
                         [p1[rng.randrange(M)] for _ in range(M)])
    else:
        C = CAND_FACTOR * M
        cands = {t: [sampler(rng, t) for _ in range(C)] for t in (L, I)}
        resv = {t: reservoirs(cands[t], quotients, t, strat) for t in (L, I)}
        pool = {t: stratified_pool(rng, resv[t], M) for t in (L, I)}
        if info is not None:
            info['buckets'] = {t: len(resv[t]) for t in (L, I)}
            info['min_bucket'] = {t: min(len(v) for v in resv[t].values()) for t in (L, I)}
        for sg in sigs:
            if strat == 1:
                pairs[sg] = joint_key_pairs(rng, resv[sg[0]], resv[sg[1]], M, len(quotients))
            else:
                pairs[sg] = (indep_bucket_vals(rng, resv[sg[0]], M),
                             indep_bucket_vals(rng, resv[sg[1]], M))
    probes = {}
    for name in opnames:
        at, rt = OPSIG[name]
        fn = OPFN[name]
        if len(at) == 1:
            col = pool[at[0]]
            probes[name] = ((col,), list(map(fn, col)))
        else:
            c0, c1 = pairs[at]
            probes[name] = ((c0, c1), list(map(fn, c0, c1)))
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
        self.dom[j][OPSIG[name][1]].add(ar)
        self._succ[j] = None
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
