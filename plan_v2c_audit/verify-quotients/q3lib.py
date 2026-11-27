"""Q3 engine: bottom-up polynomial search over integer columns, with optional
pruning by column homomorphisms Z^N -> F_p^k.

Grammar G1: leaves x, y, 0, 1; operators + - * (binary), neg (unary).
G2 adds floor div and mod (a candidate undefined on any row is dropped).
Size = number of nodes.  + and * are enumerated up to commutativity.

A DOMAIN is (p, rows): the abstract value of a column is its residues mod p on
those rows.  For G1 this is a ring homomorphism, so the abstract value of a
candidate is computed from its arguments' abstract values BEFORE it is evaluated.
Per domain, two dynamic programmes over the (finite) set of abstract states:
   g[a] = least size of any term whose abstract value is a          (forward)
   h[a] = least number of further nodes with which a term of abstract value a
          can become one of the target's abstract value (sibling arguments are
          charged their least size g)                                (backward)
A class of size s is kept only if s + max_domains h <= N.
"""
import operator
import time

INFTY = 10 ** 6


class Domain:
    def __init__(self, p, rows, leaf_cols):
        self.p = p
        self.rows = rows
        self.ids = {}
        self.states = []
        for c in leaf_cols:
            self.id_of(self.alpha(c))
        self.close()

    def alpha(self, col):
        p = self.p
        return tuple(col[r] % p for r in self.rows)

    def id_of(self, st):
        i = self.ids.get(st)
        if i is None:
            i = self.ids[st] = len(self.states)
            self.states.append(st)
        return i

    def close(self):
        """Close the state set under + - * neg and tabulate the operations."""
        p = self.p
        done = 0
        while done < len(self.states):
            n = len(self.states)
            for i in range(done, n):
                a = self.states[i]
                self.id_of(tuple((-u) % p for u in a))
                for j in range(n):
                    b = self.states[j]
                    self.id_of(tuple((u + v) % p for u, v in zip(a, b)))
                    self.id_of(tuple((u - v) % p for u, v in zip(a, b)))
                    self.id_of(tuple((v - u) % p for u, v in zip(a, b)))
                    self.id_of(tuple((u * v) % p for u, v in zip(a, b)))
            done = n
        n = len(self.states)
        S = self.states
        I = self.ids
        self.neg = [I[tuple((-u) % p for u in a)] for a in S]
        self.add = [[I[tuple((u + v) % p for u, v in zip(a, b))] for b in S] for a in S]
        self.sub = [[I[tuple((u - v) % p for u, v in zip(a, b))] for b in S] for a in S]
        self.mul = [[I[tuple((u * v) % p for u, v in zip(a, b))] for b in S] for a in S]
        self.n = n

    def forward(self, leaf_ids):
        """g[a]: least term size per abstract state (Knuth / Bellman-Ford)."""
        g = [INFTY] * self.n
        for i in leaf_ids:
            g[i] = 1
        changed = True
        while changed:
            changed = False
            for i in range(self.n):
                gi = g[i]
                if gi >= INFTY:
                    continue
                k = self.neg[i]
                if gi + 1 < g[k]:
                    g[k] = gi + 1
                    changed = True
                for j in range(self.n):
                    c = gi + g[j] + 1
                    if c >= INFTY:
                        continue
                    for tab in (self.add, self.sub, self.mul):
                        k = tab[i][j]
                        if c < g[k]:
                            g[k] = c
                            changed = True
        self.g = g
        return g

    def backward(self, t):
        """h[a]: least further nodes from abstract state a to abstract state t."""
        g = self.g
        h = [INFTY] * self.n
        h[t] = 0
        changed = True
        while changed:
            changed = False
            for i in range(self.n):
                best = h[i]
                c = 1 + h[self.neg[i]]
                if c < best:
                    best = c
                for j in range(self.n):
                    gj = g[j]
                    if gj >= INFTY:
                        continue
                    for tab in (self.add, self.sub, self.mul):
                        c = 1 + gj + h[tab[i][j]]
                        if c < best:
                            best = c
                        c = 1 + gj + h[tab[j][i]]
                        if c < best:
                            best = c
                if best < h[i]:
                    h[i] = best
                    changed = True
        return h


def fdiv(a, b):
    return a // b


def fmod(a, b):
    return a % b


def search(leaves, target, N, domains=None, hs=None, grammar='G1', store_final=False,
           stop_at_hit=False, max_cands=None, join=False, last_only=False):
    """One bottom-up pass up to size N.
    leaves: list of (name, column).  domains/hs: abstract domains and their backward
    tables (None = plain OE).  join: on the LAST level, instead of testing every
    pair of abstract buckets, look up the buckets that can combine to the target's
    abstract value (for +, -: one hash look-up per left bucket; for *: an index on
    the last domain).  last_only: below the last level a candidate is EVALUATED
    even if its abstract value cannot reach the target, and only then discarded
    (the abstract filter is applied before evaluation on the last level only).
    Returns counts; `hit` = candidates evaluated up to and including the first
    one equal to the target."""
    D = domains or []
    nd = len(D)
    prune = nd > 0
    ops = [('+', operator.add, True), ('-', operator.sub, False), ('*', operator.mul, True)]
    if grammar == 'G2':
        ops += [('div', fdiv, False), ('mod', fmod, False)]
    levels = {}            # size -> {key: [(serial, col)]}
    seen = set()
    serial = 0
    evaluated = 0
    checks = 0
    hit = None
    hit_size = None
    t0 = time.perf_counter()
    tkey = None
    if prune:
        tk = [D[d].ids.get(D[d].alpha(target)) for d in range(nd)]
        tkey = tuple(tk) if None not in tk else None
    if join and tkey is not None:
        # per domain: for each left state a1, the right states a2 with a1 * a2 = target
        msol = [[{a2 for a2 in range(D[d].n) if D[d].mul[a1][a2] == tkey[d]} for a1 in range(D[d].n)]
                for d in range(nd)]

    def hmax(key):
        m = 0
        for d in range(nd):
            v = hs[d][key[d]]
            if v > m:
                m = v
        return m

    def done():
        return dict(hit=hit, hit_size=hit_size, evaluated=evaluated, below=below,
                    stored_below=stored_below, checks=checks, wall=time.perf_counter() - t0)

    lv = levels.setdefault(1, {})
    for name, col in leaves:
        evaluated += 1
        if col == target and hit is None:
            hit, hit_size = evaluated, 1
        if col in seen:
            continue
        key = tuple(D[d].ids[D[d].alpha(col)] for d in range(nd))
        if prune and 1 + hmax(key) > N:
            continue
        seen.add(col)
        lv.setdefault(key, []).append((serial, col))
        serial += 1
    below = evaluated
    stored_below = len(seen)
    for s in range(2, N + 1):
        rem = N - s
        final = s == N
        cur = levels.setdefault(s, {})
        store = (not final) or store_final
        usejoin = join and final and tkey is not None
        # ---- neg
        for key, bucket in list(levels.get(s - 1, {}).items()):
            nkey = tuple(D[d].neg[key[d]] for d in range(nd))
            if prune:
                checks += 1
                if hmax(nkey) > rem:
                    if last_only and not final:
                        evaluated += len(bucket)
                    continue
            out = cur.setdefault(nkey, []) if store else None
            for (_, c) in bucket:
                col = tuple(map(operator.neg, c))
                evaluated += 1
                if col == target and hit is None:
                    hit, hit_size = evaluated, s
                    if stop_at_hit:
                        return done()
                if store and col not in seen:
                    seen.add(col)
                    out.append((serial, col))
                    serial += 1
        # ---- binary
        for s1 in range(1, s - 1):
            s2 = s - 1 - s1
            L1 = levels.get(s1)
            L2 = levels.get(s2)
            if not L1 or not L2:
                continue
            idx2 = None
            for (oname, fn, comm) in ops:
                if comm and s1 > s2:
                    continue
                same = comm and s1 == s2
                tabname = {'+': 'add', '-': 'sub', '*': 'mul'}.get(oname)
                tabs = [getattr(D[d], tabname) for d in range(nd)] if tabname else None
                partial = oname in ('div', 'mod')
                # ---------- which bucket pairs to evaluate
                if tabs is None or not prune:
                    pairs = ((k1, b1, k2, b2, None) for k1, b1 in L1.items() for k2, b2 in L2.items())
                    if tabs is not None:      # plain OE: single bucket, key ()
                        pairs = ((k1, b1, k2, b2, ()) for k1, b1 in L1.items() for k2, b2 in L2.items())
                elif usejoin and oname in ('+', '-'):
                    plist = []
                    sub = [D[d].sub for d in range(nd)]
                    for k1, b1 in L1.items():
                        checks += 1
                        if oname == '+':
                            k2 = tuple(sub[d][tkey[d]][k1[d]] for d in range(nd))
                        else:
                            k2 = tuple(sub[d][k1[d]][tkey[d]] for d in range(nd))
                        b2 = L2.get(k2)
                        if b2 is not None:
                            plist.append((k1, b1, k2, b2, tkey))
                    pairs = plist
                elif usejoin and oname == '*':
                    if idx2 is None:
                        idx2 = {}
                        for k2 in L2:
                            idx2.setdefault(k2[nd - 1], []).append(k2)
                    plist = []
                    for k1, b1 in L1.items():
                        for a in msol[nd - 1][k1[nd - 1]]:
                            for k2 in idx2.get(a, ()):
                                checks += 1
                                ok = True
                                for d in range(nd - 1):
                                    if k2[d] not in msol[d][k1[d]]:
                                        ok = False
                                        break
                                if ok:
                                    plist.append((k1, b1, k2, L2[k2], tkey))
                    pairs = plist
                else:
                    plist = []
                    for k1, b1 in L1.items():
                        for k2, b2 in L2.items():
                            nkey = tuple(tabs[d][k1[d]][k2[d]] for d in range(nd))
                            checks += 1
                            if hmax(nkey) > rem:
                                if last_only and not final:
                                    # evaluated, then discarded: count the evaluations
                                    if same:
                                        for (i1, _) in b1:
                                            for (i2, _) in b2:
                                                if i1 <= i2:
                                                    evaluated += 1
                                    else:
                                        evaluated += len(b1) * len(b2)
                                continue
                            plist.append((k1, b1, k2, b2, nkey))
                    pairs = plist
                # ---------- evaluate
                for (k1, b1, k2, b2, nkey) in pairs:
                    out = cur.setdefault(nkey, []) if (store and nkey is not None) else None
                    for (i1, c1) in b1:
                        for (i2, c2) in b2:
                            if same and i1 > i2:
                                continue
                            if partial and 0 in c2:
                                continue
                            col = tuple(map(fn, c1, c2))
                            evaluated += 1
                            if col == target and hit is None:
                                hit, hit_size = evaluated, s
                                if stop_at_hit:
                                    return done()
                            if store and col not in seen:
                                if nkey is None:
                                    # div / mod: no abstract transformer; read the abstract
                                    # value off the concrete column.  A value outside the
                                    # ring closure has no entry in the backward tables.
                                    kk = []
                                    ok = True
                                    for d in range(nd):
                                        i = D[d].ids.get(D[d].alpha(col))
                                        if i is None:
                                            ok = False
                                            break
                                        kk.append(i)
                                    if nd and (not ok or s + hmax(tuple(kk)) > N):
                                        continue
                                    seen.add(col)
                                    cur.setdefault(tuple(kk), []).append((serial, col))
                                else:
                                    seen.add(col)
                                    out.append((serial, col))
                                serial += 1
            if max_cands and evaluated > max_cands:
                r = done()
                r['capped'] = True
                return r
        if hit is not None and not final:
            return done()        # found below the bound
        if not final:
            below = evaluated
            stored_below = len(seen)
    return done()


def pick_rows(xs, ys, p, k):
    """First k rows with pairwise distinct (x mod p, y mod p)."""
    out = []
    seen = set()
    for r, (x, y) in enumerate(zip(xs, ys)):
        key = (x % p, y % p)
        if key not in seen:
            seen.add(key)
            out.append(r)
            if len(out) == k:
                break
    return out
