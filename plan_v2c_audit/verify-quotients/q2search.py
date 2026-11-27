"""Search engines for Q2: plain bottom-up OE, abstract-table pruned OE, Naive Bayes.

Size of a term = number of nodes (operators + leaves).  Level s holds the
classes whose smallest term has size s.  A CANDIDATE is one concrete evaluation
of an operator on argument classes over all example rows.
"""
import math
import random
import time
from collections import Counter, defaultdict

from seqlib import L, I, OPS, OPNAMES, OPSIG, OPFN, OPIDX

INF = 99


# =================================================================== plain OE
def plain_search(inputs, target, size_ref, opnames=None):
    """Bottom-up enumeration by size with observational-equivalence dedupe.
    Enumerates COMPLETE levels; the level containing the first hit is the final
    level and is not stored.  Returns per-level per-operator statistics from
    which 'candidates until found' under any operator order can be computed."""
    ops = [o for o in OPS if opnames is None or o[0] in opnames]
    lev = {L: defaultdict(list), I: defaultdict(list)}
    seen = set()
    levels = []           # per level: dict(total=, n=[per op], hit=[per op first-hit idx or -1], stored=)
    t0 = time.perf_counter()
    # level 1
    n1 = 0
    hit1 = -1
    for name, col in inputs.items():
        if col == target and hit1 < 0:
            hit1 = n1
        n1 += 1
        if col not in seen:
            seen.add(col)
            lev[L][1].append(col)
    levels.append(dict(size=1, total=n1, n=None, hit=None, stored=len(lev[L][1]), anyhit=hit1 >= 0))
    found = 1 if hit1 >= 0 else None
    s = 1
    while found is None and s < size_ref:
        s += 1
        store = s < size_ref
        ns, hs = [], []
        stored = 0
        for (name, at, rt, fn) in ops:
            n = 0
            hit = -1
            out = lev[rt][s]
            if len(at) == 1:
                for c in lev[at[0]][s - 1]:
                    col = tuple(map(fn, c))
                    if col == target and hit < 0:
                        hit = n
                    n += 1
                    if store and col not in seen:
                        seen.add(col)
                        out.append(col)
                        stored += 1
            else:
                for s1 in range(1, s - 1):
                    A = lev[at[0]][s1]
                    B = lev[at[1]][s - 1 - s1]
                    if not A or not B:
                        continue
                    for c1 in A:
                        for c2 in B:
                            col = tuple(map(fn, c1, c2))
                            if col == target and hit < 0:
                                hit = n
                            n += 1
                            if store and col not in seen:
                                seen.add(col)
                                out.append(col)
                                stored += 1
            ns.append(n)
            hs.append(hit)
        anyhit = any(h >= 0 for h in hs)
        levels.append(dict(size=s, total=sum(ns), n=ns, hit=hs, stored=stored, anyhit=anyhit))
        if anyhit:
            found = s
    res = dict(found_size=found, levels=levels, opnames=[o[0] for o in ops],
               wall_s=time.perf_counter() - t0)
    if found is not None:
        res['below'] = sum(l['total'] for l in levels[:found - 1])
        res['store_below'] = sum(l['stored'] for l in levels[:found - 1])
        res['final_total'] = levels[found - 1]['total']
    return res


def count_under_order(n, hit, order):
    """Candidates evaluated in a level until the first hit, if operators are tried
    in `order` (a list of operator indices) and arguments in canonical order."""
    c = 0
    for oi in order:
        if hit[oi] >= 0:
            return c + hit[oi] + 1
        c += n[oi]
    return None


def expected_random_order(n, hit, rng, trials=2000):
    idx = [i for i in range(len(n)) if n[i] > 0]
    tot = 0
    for _ in range(trials):
        rng.shuffle(idx)
        tot += count_under_order(n, hit, idx)
    return tot / trials


# =================================================================== abstract context
class AbsCtx:
    """Per-task view of the pushed-forward tables: distances to the target's
    abstract value, memoised bounds and surprises."""

    def __init__(self, tables, target, ttype, absrows=None):
        self.tb = tables
        self.nq = len(tables.q)
        self.ttype = ttype
        self.R = absrows or len(target)     # abstract columns use the first R rows only
        self.tvec = []
        self.dmap = []                 # per quotient: {t: {(type, a): dist}}
        for j, q in enumerate(tables.q):
            tv = tuple(map(q.f[ttype], target[:self.R]))
            self.tvec.append(tv)
            self.dmap.append({t: tables.dist_to(j, ttype, t) for t in set(tv)})
        self.vid = [dict() for _ in range(self.nq)]      # (type, vec) -> id
        self.vecs = [[] for _ in range(self.nq)]         # id -> vec
        self.hq = [[] for _ in range(self.nq)]           # id -> h
        self.aid = {}                                    # (type, ids) -> aid
        self.aids = []                                   # aid -> ids
        self.ah = []                                     # aid -> h (max over quotients)
        self.stepmin = [dict() for _ in range(self.nq)]
        self.bq = [dict() for _ in range(self.nq)]       # (oi, id1, id2) -> bound
        self.sq = [dict() for _ in range(self.nq)]       # (oi, id1, id2) -> surprise bits
        self.ball = {}
        self.qf = [(q.f[L], q.f[I]) for q in tables.q]

    def abstract(self, col, ty):
        """Intern the abstract column of a concrete column; returns aid."""
        ids = []
        k = 0 if ty == L else 1
        if self.R < len(col):
            col = col[:self.R]
        for j in range(self.nq):
            vec = tuple(map(self.qf[j][k], col))
            key = (ty, vec)
            vid = self.vid[j]
            i = vid.get(key)
            if i is None:
                i = len(vid)
                vid[key] = i
                self.vecs[j].append(vec)
                dm = self.dmap[j]
                dom = self.tb.dom[j][ty]
                h = 0
                for a, t in zip(vec, self.tvec[j]):
                    d = dm[t].get((ty, a))
                    if d is None:
                        # abstract value known to the tables but with no path -> unreachable;
                        # abstract value never seen in any probe -> no information (0)
                        d = INF if a in dom else 0
                    if d > h:
                        h = d
                self.hq[j].append(h)
            ids.append(i)
        ids = tuple(ids)
        key = (ty, ids)
        a = self.aid.get(key)
        if a is None:
            a = len(self.aids)
            self.aid[key] = a
            self.aids.append(ids)
            self.ah.append(max(self.hq[j][ids[j]] for j in range(self.nq)) if self.nq else 0)
        return a

    def _stepmin(self, j, name, key, t):
        k = (name, key, t)
        sm = self.stepmin[j]
        b = sm.get(k)
        if b is None:
            rt = OPSIG[name][1]
            d = self.dmap[j][t]
            c = self.tb.tab[j][name].get(key)
            if c is None:      # TOP: anything of the result type
                if rt == self.ttype:
                    b = 0
                else:
                    dom = self.tb.dom[j][rt]
                    b = min((d.get((rt, v), INF) for v in dom), default=0)
            else:
                b = min(d.get((rt, v), INF) for v in c)
            sm[k] = b
        return b

    def bound_q(self, j, name, i1, i2):
        """Lower bound (ops still needed AFTER applying `name`) for quotient j."""
        k = (name, i1, i2)
        b = self.bq[j].get(k)
        if b is None:
            v1 = self.vecs[j][i1]
            tv = self.tvec[j]
            b = 0
            if i2 is None:
                for a, t in zip(v1, tv):
                    x = self._stepmin(j, name, (a,), t)
                    if x > b:
                        b = x
            else:
                v2 = self.vecs[j][i2]
                for a, a2, t in zip(v1, v2, tv):
                    x = self._stepmin(j, name, (a, a2), t)
                    if x > b:
                        b = x
            self.bq[j][k] = b
        return b

    def bound(self, name, a1, a2=None):
        k = (name, a1, a2)
        b = self.ball.get(k)
        if b is None:
            ids1 = self.aids[a1]
            ids2 = self.aids[a2] if a2 is not None else None
            b = 0
            for j in range(self.nq):
                x = self.bound_q(j, name, ids1[j], ids2[j] if ids2 is not None else None)
                if x > b:
                    b = x
            if len(self.ball) < 3_000_000:
                self.ball[k] = b
        return b

    def surprise(self, name, a1, a2=None):
        """Sum over quotients of the row-mean of -log2 P(target abstract | op, abstract args)."""
        ids1 = self.aids[a1]
        ids2 = self.aids[a2] if a2 is not None else None
        tot = 0.0
        rt = OPSIG[name][1]
        for j in range(self.nq):
            k = (name, ids1[j], ids2[j] if ids2 is not None else None)
            s = self.sq[j].get(k)
            if s is None:
                v1 = self.vecs[j][ids1[j]]
                v2 = self.vecs[j][ids2[j]] if ids2 is not None else None
                tv = self.tvec[j]
                tab = self.tb.tab[j][name]
                s = 0.0
                for r, t in enumerate(tv):
                    key = (v1[r],) if v2 is None else (v1[r], v2[r])
                    c = tab.get(key)
                    if c is None:
                        s += math.log2(max(1, len(self.tb.dom[j][rt])))
                    else:
                        p = c.get(t, 0)
                        s += 20.0 if p == 0 else -math.log2(p / sum(c.values()))
                s /= len(tv)
                self.sq[j][k] = s
            tot += s
        return tot


# =================================================================== pruned pass
class _Lev:
    """Stored classes of one (type, size): concrete columns, abstract-column ids,
    and per quotient the list of abstract row-vector ids."""
    __slots__ = ('cols', 'aids', 'vids', 'groups', 'vset')

    def __init__(self, nq):
        self.cols = []
        self.aids = []
        self.vids = [[] for _ in range(nq)]
        self.groups = {}
        self.vset = None

    def add(self, col, aid, ids):
        i = len(self.cols)
        self.cols.append(col)
        self.aids.append(aid)
        for j, v in enumerate(ids):
            self.vids[j].append(v)
        g = self.groups.get(aid)
        if g is None:
            self.groups[aid] = [i]
        else:
            g.append(i)

    def freeze(self):
        if self.vset is None:
            self.vset = [set(v) for v in self.vids]


def _unary_idxs(ctx, K, name, rem):
    """Indices of the classes in K on which unary operator `name` may still reach
    the target within `rem` further nodes, by a per-quotient semi-join on the
    abstract row-vector ids.  Returns (indices, number of table lookups)."""
    idxs = None
    checks = 0
    for j in range(ctx.nq):
        vs = K.vset[j]
        bq = ctx.bq[j]
        pj = set()
        for v in vs:
            b = bq.get((name, v, None))
            if b is None:
                b = ctx.bound_q(j, name, v, None)
            if b <= rem:
                pj.add(v)
        checks += len(vs)
        if len(pj) == len(vs):
            continue
        if not pj:
            return (), checks
        vj = K.vids[j]
        if idxs is None:
            idxs = [i for i, v in enumerate(vj) if v in pj]
        else:
            idxs = [i for i in idxs if vj[i] in pj]
        if not idxs:
            return (), checks
    if idxs is None:
        idxs = range(len(K.cols))
    return idxs, checks


def pruned_pass(inputs, target, N, ctx, prefilter=True, opnames=None, want_buckets=True):
    """One bottom-up pass with size bound N.
    * a class of size s whose abstract column needs at least h more nodes to
      reach the target's abstract column is kept only if s + h <= N;
    * with prefilter, a candidate of size s is not evaluated if every abstract
      result the tables allow for it needs more than N - s further nodes.
    The last level (size N) is only compared with the target, never stored."""
    ops = [o for o in OPS if opnames is None or o[0] in opnames]
    nq = ctx.nq
    lev = {L: defaultdict(lambda: _Lev(nq)), I: defaultdict(lambda: _Lev(nq))}
    seen = set()
    considered = evaluated = discarded = dup = checks = nabs = 0
    t0 = time.perf_counter()
    ah, aids_tab = ctx.ah, ctx.aids
    hit_level = None
    for name, col in inputs.items():        # level 1
        considered += 1
        evaluated += 1
        if col == target:
            hit_level = 1
        if col in seen:
            continue
        a = ctx.abstract(col, L)
        nabs += 1
        if 1 + ah[a] > N:
            discarded += 1
            continue
        seen.add(col)
        lev[L][1].add(col, a, aids_tab[a])
    below = evaluated
    stored_below = len(seen)
    stored_upto_nm2 = len(seen) if N >= 3 else 0
    fin_n, fin_hit = [], []
    buckets = {}
    used = {L: set(), I: set()}
    used_all = {L: False, I: False}
    for s in range(2, N + 1):
        rem = N - s
        final = s == N
        for t_ in (L, I):
            for k_ in list(lev[t_].keys()):
                lev[t_][k_].freeze()
        for (name, at, rt, fn) in ops:
            n = 0
            hit = -1
            out = lev[rt][s]
            if len(at) == 1:
                K = lev[at[0]].get(s - 1)
                if K is None or not K.cols:
                    if final:
                        fin_n.append(0)
                        fin_hit.append(-1)
                    continue
                considered += len(K.cols)
                if prefilter:
                    idxs, ck = _unary_idxs(ctx, K, name, rem)
                    checks += ck
                else:
                    idxs = range(len(K.cols))
                cols = K.cols
                if final:
                    if isinstance(idxs, range):
                        used_all[at[0]] = True
                    else:
                        used[at[0]].update(idxs)
                    kaids = K.aids
                    for i in idxs:
                        col = tuple(map(fn, cols[i]))
                        if want_buckets:
                            key = (name, kaids[i], None)
                            bk = buckets.get(key)
                            if bk is None:
                                bk = buckets[key] = [0, -1]
                            if col == target:
                                if hit < 0:
                                    hit = n
                                if bk[1] < 0:
                                    bk[1] = bk[0]
                            bk[0] += 1
                        elif col == target and hit < 0:
                            hit = n
                        n += 1
                    evaluated += n
                else:
                    for i in idxs:
                        col = tuple(map(fn, cols[i]))
                        evaluated += 1
                        if col == target and hit_level is None:
                            hit_level = s
                        if col in seen:
                            dup += 1
                            continue
                        a = ctx.abstract(col, rt)
                        nabs += 1
                        if s + ah[a] > N:
                            discarded += 1
                            continue
                        seen.add(col)
                        out.add(col, a, aids_tab[a])
            else:
                for s1 in range(1, s - 1):
                    A = lev[at[0]].get(s1)
                    B = lev[at[1]].get(s - 1 - s1)
                    if A is None or B is None or not A.cols or not B.cols:
                        continue
                    considered += len(A.cols) * len(B.cols)
                    acols, bcols = A.cols, B.cols
                    for aid1, g1 in A.groups.items():
                        ids1 = aids_tab[aid1]
                        for aid2, g2 in B.groups.items():
                            if prefilter:
                                checks += 1
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
                            if final and want_buckets:
                                key = (name, aid1, aid2)
                                bk = buckets.get(key)
                                if bk is None:
                                    bk = buckets[key] = [0, -1]
                            for i1 in g1:
                                c1 = acols[i1]
                                for i2 in g2:
                                    col = tuple(map(fn, c1, bcols[i2]))
                                    evaluated += 1
                                    if final:
                                        if col == target:
                                            if hit < 0:
                                                hit = n
                                            if want_buckets and bk[1] < 0:
                                                bk[1] = bk[0]
                                        if want_buckets:
                                            bk[0] += 1
                                        n += 1
                                        continue
                                    if col == target and hit_level is None:
                                        hit_level = s
                                    if col in seen:
                                        dup += 1
                                        continue
                                    a = ctx.abstract(col, rt)
                                    nabs += 1
                                    if s + ah[a] > N:
                                        discarded += 1
                                        continue
                                    seen.add(col)
                                    out.add(col, a, aids_tab[a])
            if final:
                fin_n.append(n)
                fin_hit.append(hit)
        if not final:
            below = evaluated
            stored_below = len(seen)
            if s <= N - 2:
                stored_upto_nm2 = len(seen)
    if N >= 2 and any(h >= 0 for h in fin_hit) and hit_level is None:
        hit_level = N
    # classes of size N-1 that at least one unary operator can still take to the target
    j1 = 0
    if N >= 2:
        for t_ in (L, I):
            K = lev[t_].get(N - 1)
            if K is not None:
                j1 += len(K.cols) if used_all[t_] else len(used[t_])
    return dict(N=N, considered=considered, evaluated=evaluated, discarded=discarded, dup=dup,
                checks=checks, nabs=nabs, below=below, store_below=stored_below,
                store_joint1=stored_upto_nm2 + j1 if N >= 3 else stored_below,
                fin_n=fin_n, fin_hit=fin_hit,
                buckets=buckets if want_buckets else None, hit_level=hit_level,
                wall_s=time.perf_counter() - t0, opnames=[o[0] for o in ops])


def soft_counts(pp, ctx):
    """From the final level of a pruned pass: candidates until the first hit under
    (a) library operator order, (b) operators ordered by min bucket surprise,
    (c) buckets ordered by surprise.  Also the operator order (b), extended to
    all operators (those with no admissible candidate go last, in library order)."""
    n, hit, names = pp['fin_n'], pp['fin_hit'], pp['opnames']
    lib = count_under_order(n, hit, range(len(n)))
    bks = pp['buckets']
    sur = {}
    opmin = {}
    for k in bks:
        s = ctx.surprise(*k)
        sur[k] = s
        if s < opmin.get(k[0], 1e9):
            opmin[k[0]] = s
    order = sorted(range(len(n)), key=lambda i: (opmin.get(names[i], 1e9), i))
    op_soft = count_under_order(n, hit, order)
    keys = sorted(bks, key=lambda k: sur[k])     # stable: ties keep canonical order
    c = 0
    bucket_soft = None
    for k in keys:
        if bks[k][1] >= 0:
            bucket_soft = c + bks[k][1] + 1
            break
        c += bks[k][0]
    return dict(lib=lib, op_soft=op_soft, bucket_soft=bucket_soft, order=order, opmin=opmin,
                n_buckets=len(bks))


def pruned_search(inputs, target, ttype, tables, n_star, prefilter=True, opnames=None,
                  absrows=None):
    """Iterative deepening on the size bound N = 1..n_star, each pass a restart.
    cum_before = candidates evaluated in the passes before the last one."""
    ctx = AbsCtx(tables, target, ttype, absrows)
    cum_before = 0
    cum_checks = 0
    passes = []
    t0 = time.perf_counter()
    for N in range(1, n_star + 1):
        pp = pruned_pass(inputs, target, N, ctx, prefilter=prefilter, opnames=opnames,
                         want_buckets=(N == n_star))
        passes.append((N, pp['evaluated'], pp['considered']))
        cum_checks += pp['checks']
        if pp['hit_level'] is not None or N == n_star:
            break
        cum_before += pp['evaluated']
    found = pp['hit_level'] is not None
    return dict(found=found, found_N=pp['N'] if found else None, cum_before=cum_before,
                cum_checks=cum_checks, passes=passes, last=pp,
                wall_s=time.perf_counter() - t0, ctx=ctx)


def ref_audit(term, env, tables):
    """Check every operator application of the reference program against the
    tables: a MISS is an abstract argument tuple that the probes saw, with an
    abstract result they never saw for it (TOP entries cannot miss)."""
    from seqlib import subterms, eval_term
    misses = []
    for (u, d) in subterms(term):
        if isinstance(u, str):
            continue
        name = u[0]
        at, rt = OPSIG[name]
        args = [eval_term(a, env) for a in u[1:]]
        res = eval_term(u, env)
        for j, q in enumerate(tables.q):
            tab = tables.tab[j][name]
            for r in range(len(res)):
                key = tuple(q.f[at[i]](args[i][r]) for i in range(len(at)))
                c = tab.get(key)
                if c is None:
                    continue
                ar = q.f[rt](res[r])
                if ar not in c:
                    misses.append((name, q.name, key, ar, r))
    return misses


# =================================================================== Naive Bayes on flat signatures
def signature(env, out, ty):
    """Boolean properties of (inputs, output) at the task boundary; each is a
    statement about ALL rows unless it says 'some'."""
    xs = env['xs']
    ys = env.get('ys')
    f = []
    isL = ty == L
    f.append(isL)
    if isL:
        ox = list(zip(out, xs))
        f.append(all(len(o) == len(x) for o, x in ox))
        f.append(all(len(o) < len(x) for o, x in ox))
        f.append(all(len(o) <= len(x) for o, x in ox))
        f.append(all(len(o) == len(x) - 1 for o, x in ox))
        f.append(all(tuple(sorted(o)) == o for o in out))
        f.append(all(tuple(sorted(o, reverse=True)) == o for o in out))
        f.append(all(all(v >= 0 for v in o) for o in out))
        f.append(all(all(v % 2 == 0 for v in o) for o in out))
        f.append(all(not (Counter(o) - Counter(x)) for o, x in ox))
        f.append(all(sorted(o) == sorted(x) for o, x in ox))
        f.append(all(o[:1] == x[:1] for o, x in ox))
        f.append(all(o[-1:] == x[-1:] for o, x in ox))
        f.append(any(len(o) == 0 for o in out))
        f.append(any(len(o) > len(x) for o, x in ox))
        f += [False] * 6
    else:
        f += [False] * 14
        ox = list(zip(out, xs))
        f.append(all(o >= 0 for o in out))
        f.append(all(o % 2 == 0 for o in out))
        f.append(all(o in x for o, x in ox))
        f.append(all(0 <= o <= len(x) for o, x in ox))
        f.append(all(abs(o) <= max(map(abs, x), default=0) for o, x in ox))
        f.append(all(o == len(x) for o, x in ox))
    f.append(ys is not None)
    f.append(bool(isL and ys is not None and
                  all(len(o) == min(len(x), len(y)) for o, x, y in zip(out, xs, ys))))
    return tuple(f)


SIG_NAMES = ['out_is_list', 'len=len(xs)', 'len<len(xs)', 'len<=len(xs)', 'len=len(xs)-1',
             'out_sorted_asc', 'out_sorted_desc', 'out_all_nonneg', 'out_all_even',
             'out_submultiset_xs', 'out_perm_xs', 'head_same', 'last_same', 'some_out_empty',
             'some_out_longer', 'int_nonneg', 'int_even', 'int_in_xs', 'int_in_0..len',
             'int_abs<=max|xs|', 'int=len(xs)', 'two_inputs', 'len=min(len xs,len ys)']


class NaiveBayes:
    """One Bernoulli Naive Bayes per operator: P(op in solution | signature),
    Laplace smoothing 1.  `backoff_unseen`: an operator with zero training count
    is scored by its prior alone (second choice)."""

    def __init__(self, train, opnames=None, backoff_unseen=False):
        self.opnames = opnames or OPNAMES
        self.n = len(train)
        self.K = len(train[0][0])
        self.cnt = Counter()
        self.fc = defaultdict(lambda: [0] * self.K)
        self.ftot = [0] * self.K
        for sig, ops in train:
            for k, b in enumerate(sig):
                if b:
                    self.ftot[k] += 1
            for o in set(ops):
                self.cnt[o] += 1
                for k, b in enumerate(sig):
                    if b:
                        self.fc[o][k] += 1
        self.backoff_unseen = backoff_unseen

    def logodds(self, name, sig):
        nf = self.cnt[name]
        nn = self.n - nf
        lo = math.log((nf + 1) / (nn + 1))
        if self.backoff_unseen and nf == 0:
            return lo
        fc = self.fc[name]
        for k, b in enumerate(sig):
            p1 = (fc[k] + 1) / (nf + 2)
            p0 = (self.ftot[k] - fc[k] + 1) / (nn + 2)
            lo += math.log(p1 / p0) if b else math.log((1 - p1) / (1 - p0))
        return lo

    def posterior(self, sig):
        out = {}
        for name in self.opnames:
            lo = self.logodds(name, sig)
            out[name] = 1 / (1 + math.exp(-lo)) if lo > -700 else 0.0
        return out

    def order(self, sig):
        p = self.posterior(sig)
        return sorted(range(len(self.opnames)), key=lambda i: (-p[self.opnames[i]], i))


# =================================================================== cost-weighted (Probe-style) OE
def weighted_search(inputs, target, cost, order=None, cap=3_000_000, max_cost=200):
    """Bottom-up enumeration by total COST (leaf = 1, operator = cost[name] >= 1)
    with OE dedupe; stops at the first hit.  Complete: every cost is finite.
    Returns candidates evaluated until the hit (or None if cap reached)."""
    ops = list(OPS) if order is None else [OPS[i] for i in order]
    lev = {L: defaultdict(list), I: defaultdict(list)}
    seen = set()
    n = 0
    t0 = time.perf_counter()
    for name, col in inputs.items():
        n += 1
        if col == target:
            return dict(cands=n, cost=1, stored=len(seen), wall_s=time.perf_counter() - t0)
        if col not in seen:
            seen.add(col)
            lev[L][1].append(col)
    for C in range(2, max_cost + 1):
        for (name, at, rt, fn) in ops:
            rem = C - cost[name]
            if rem < 1:
                continue
            new = []
            if len(at) == 1:
                for c in lev[at[0]].get(rem, ()):
                    col = tuple(map(fn, c))
                    n += 1
                    if col == target:
                        return dict(cands=n, cost=C, stored=len(seen), wall_s=time.perf_counter() - t0)
                    if col not in seen:
                        seen.add(col)
                        new.append(col)
            else:
                for c1cost in range(1, rem):
                    A = lev[at[0]].get(c1cost)
                    B = lev[at[1]].get(rem - c1cost)
                    if not A or not B:
                        continue
                    for c1 in A:
                        for c2 in B:
                            col = tuple(map(fn, c1, c2))
                            n += 1
                            if col == target:
                                return dict(cands=n, cost=C, stored=len(seen),
                                            wall_s=time.perf_counter() - t0)
                            if col not in seen:
                                seen.add(col)
                                new.append(col)
            # classes of cost C created by this operator become visible only at higher cost
            lev[rt][C].extend(new)
            if n > cap:
                return dict(cands=None, cost=C, stored=len(seen), wall_s=time.perf_counter() - t0,
                            capped=n)
    return dict(cands=None, cost=max_cost, stored=len(seen), wall_s=time.perf_counter() - t0, capped=n)


def nb_costs(post, opnames=None):
    """Probe-style integer costs: cost = max(1, round(-log2 q)) with q the
    posterior normalised over operators."""
    opnames = opnames or OPNAMES
    z = sum(post[n] for n in opnames)
    return {n: max(1, round(-math.log2(max(post[n] / z, 1e-12)))) for n in opnames}
