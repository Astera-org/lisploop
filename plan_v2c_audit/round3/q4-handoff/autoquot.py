"""Automatic selection of quotients by lumpability, with nothing hand-picked.

List candidates: alpha(xs) = q(r(g(xs))) -- g in {identity} + the 31 unary
list->list library operators, r in the 9 list->int reductions, q an integer term
of at most `qsize` nodes over v, 0..5 with + * mod < = abs sgn min.
Int candidates: beta(v) = q(v).
Score = mean over the library's operators of the same type of
Lump = 1 - H(alpha(f(x)) | alpha(args)) / H(alpha(f(x)))   (0 when H(alpha(f)) = 0).
Selection (fixed rule, not tuned): walk down the ranking; skip a candidate whose
smallest block holds < 1% of the probe values, or whose normalised mutual
information with an already selected quotient is >= 0.5; stop at K.
Each selected list quotient is paired with the int quotient (from the 8 best
diverse int candidates, or the trivial one) that it best predicts through the
library's list->int reductions.
"""
import math
import random
from collections import Counter

from seqlib import L, I, OPS, OPFN, OPSIG, Quotient, rand_list


def _sgn(v):
    return (v > 0) - (v < 0)


def q_terms(maxsize, with_min=True):
    lv = {1: [('v', lambda v: v)] + [(str(c), (lambda c: lambda v: c)(c)) for c in range(6)]}
    for s in range(2, maxsize + 1):
        cur = []
        for (t, f) in lv.get(s - 1, []):
            cur.append(('(abs %s)' % t, (lambda f: lambda v: abs(f(v)))(f)))
            cur.append(('(sgn %s)' % t, (lambda f: lambda v: _sgn(f(v)))(f)))
        for s1 in range(1, s - 1):
            for (t1, f1) in lv.get(s1, []):
                for (t2, f2) in lv.get(s - 1 - s1, []):
                    mk = lambda op, f1=f1, f2=f2: (lambda v: op(f1(v), f2(v)))
                    cur.append(('(+ %s %s)' % (t1, t2), mk(lambda a, b: a + b)))
                    cur.append(('(* %s %s)' % (t1, t2), mk(lambda a, b: a * b)))
                    cur.append(('(mod %s %s)' % (t1, t2), mk(lambda a, b: a % b)))
                    cur.append(('(< %s %s)' % (t1, t2), mk(lambda a, b: int(a < b))))
                    cur.append(('(= %s %s)' % (t1, t2), mk(lambda a, b: int(a == b))))
                    if with_min:
                        cur.append(('(min %s %s)' % (t1, t2), mk(min)))
        lv[s] = cur
    return [(s, t, f) for s in sorted(lv) for (t, f) in lv[s] if 'v' in t]


def _safe(f):
    def g(v):
        try:
            return f(v)
        except ZeroDivisionError:
            return -999
    return g


def canon(v):
    m = {}
    out = []
    for x in v:
        k = m.get(x)
        if k is None:
            k = m[x] = len(m)
        out.append(k)
    return tuple(out)


def H(counter, n):
    return -sum(c / n * math.log2(c / n) for c in counter.values())


def lump(lab, rows):
    """rows = (I, J or None, K) index lists; returns Lump, with 0 for constant output."""
    Ii, Jj, Kk = rows
    n = len(Ii)
    g = lab.__getitem__
    out = list(map(g, Kk))
    co = Counter(out)
    ho = H(co, n)
    if ho < 1e-12:
        return 0.0
    if Jj is None:
        a = list(map(g, Ii))
    else:
        a = list(zip(map(g, Ii), map(g, Jj)))
    hc = H(Counter(zip(a, out)), n) - H(Counter(a), n)
    return 1.0 - max(0.0, hc) / ho


def nmi(a, b):
    n = len(a)
    ha, hb = H(Counter(a), n), H(Counter(b), n)
    if min(ha, hb) < 1e-12:
        return 1.0
    return (ha + hb - H(Counter(zip(a, b)), n)) / min(ha, hb)


def select(K=6, seed=0, P=800, qsize=3, blocks=6, verbose=True, log=print):
    rng = random.Random(seed)
    # ------------------------------------------------ list side
    pool = [rand_list(rng, 0, 8, 9) for _ in range(P)]
    vid, vals = {}, []

    def idx(v):
        i = vid.get(v)
        if i is None:
            i = vid[v] = len(vals)
            vals.append(v)
        return i
    pidx = [idx(v) for v in pool]          # the pool WITH multiplicity, as indices
    lops = [(n, at, fn) for (n, at, rt, fn) in OPS if rt == L and all(t == L for t in at)]
    rows = {}
    for (n, at, fn) in lops:
        if len(at) == 1:
            rows[n] = ([idx(v) for v in pool], None, [idx(fn(v)) for v in pool])
        else:
            pa = [rng.choice(pool) for _ in range(P)]
            pb = [rng.choice(pool) for _ in range(P)]
            rows[n] = ([idx(a) for a in pa], [idx(b) for b in pb], [idx(fn(a, b)) for a, b in zip(pa, pb)])
    Q = [(s, t, _safe(f)) for (s, t, f) in q_terms(qsize)]
    G = [('', None)] + [(n, OPFN[n]) for (n, at, rt, fn) in OPS if at == (L,) and rt == L]
    R = [(n, OPFN[n]) for (n, at, rt, fn) in OPS if at == (L,) and rt == I]
    parts = {}
    for gname, g in G:
        gv = vals if g is None else [g(v) for v in vals]
        for rname, r in R:
            u = [r(v) for v in gv]
            Dv = sorted(set(u))
            base = '(%s (%s xs))' % (rname, gname) if gname else '(%s xs)' % rname
            local = set()
            for (qs, qt, qf) in Q:
                m = {d: qf(d) for d in Dv}
                nb = len(set(m.values()))
                if nb < 2 or nb > blocks:
                    continue
                key = canon([m[d] for d in Dv])
                if key in local:
                    continue
                local.add(key)
                lab = canon([m[x] for x in u])
                size = qs + 1 + (1 if gname else 0)
                old = parts.get(lab)
                if old is None or old[0] > size:
                    parts[lab] = (size, qt.replace('v', base), (g, r, qf))
    cands = []
    npool = len(pool)
    for lab, (size, term, fns) in parts.items():
        sc = sum(lump(lab, rows[n]) for (n, at, fn) in lops) / len(lops)
        plab = [lab[i] for i in pidx]
        cnt = Counter(plab)
        cands.append((sc, size, term, plab, fns, min(cnt.values()) / npool if len(cnt) > 1 else 0.0))
    cands.sort(key=lambda c: (-c[0], c[1], c[2]))
    chosen = []
    skipped = []
    for c in cands:
        if len(chosen) >= K:
            break
        if c[5] < 0.01:
            skipped.append((c[2], c[0], 'small block'))
            continue
        red = [x[2] for x in chosen if nmi(c[3], x[3]) >= 0.5]
        if red:
            skipped.append((c[2], c[0], 'redundant with ' + red[0]))
            continue
        chosen.append(c)
    # ------------------------------------------------ int side
    E = list(range(-150, 151))
    EI = {v: i for i, v in enumerate(E)}
    grid = range(-12, 13)
    iops = [(n, at, fn) for (n, at, rt, fn) in OPS if rt == I and all(t == I for t in at)]
    irows = {}
    for (n, at, fn) in iops:
        if len(at) == 1:
            xs_ = [x for x in grid if -150 <= fn(x) <= 150]
            irows[n] = ([EI[x] for x in xs_], None, [EI[fn(x)] for x in xs_])
        else:
            pr = [(x, y) for x in grid for y in grid]
            irows[n] = ([EI[x] for x, y in pr], [EI[y] for x, y in pr], [EI[fn(x, y)] for x, y in pr])
    iparts = {}
    for (qs, qt, qf) in Q:
        vals_q = [qf(v) for v in E]
        lab = canon(vals_q)
        nb = max(lab) + 1
        if nb < 2 or nb > blocks:
            continue
        if lab not in iparts or iparts[lab][0] > qs:
            iparts[lab] = (qs, qt, qf)
    icands = []
    for lab, (qs, qt, qf) in iparts.items():
        sc = sum(lump(lab, irows[n]) for (n, at, fn) in iops) / len(iops)
        g0 = [lab[EI[x]] for x in grid]
        icands.append((sc, qs, qt, lab, qf, min(Counter(g0).values()) / len(g0) if len(set(g0)) > 1 else 0.0))
    icands.sort(key=lambda c: (-c[0], c[1], c[2]))
    ichosen = []
    for c in icands:
        if len(ichosen) >= 8:
            break
        if c[5] < 0.01:
            continue
        gi = [EI[x] for x in grid]
        if any(nmi([c[3][i] for i in gi], [x[3][i] for i in gi]) >= 0.5 for x in ichosen):
            continue
        ichosen.append(c)
    # ------------------------------------------------ pairing through the reductions
    out = []
    info = []
    for (sc, size, term, lab, (g, r, qf), mb) in chosen:
        best = (0.2, None)
        for (isc, iqs, iqt, ilab, iqf, imb) in ichosen:
            tot = 0.0
            for rname, rf in R:
                a = lab
                o = [iqf(rf(v)) for v in pool]
                ho = H(Counter(o), npool)
                if ho > 1e-12:
                    tot += 1.0 - max(0.0, H(Counter(zip(a, o)), npool) - H(Counter(a), npool)) / ho
            x = tot / len(R)
            if x > best[0]:
                best = (x, (iqt, iqf))
        fL = (lambda g, r, qf: (lambda xs: qf(r(xs if g is None else g(xs)))))(g, r, qf)
        if best[1] is None:
            fI, iname = (lambda v: 0), 'trivial'
        else:
            fI, iname = best[1][1], best[1][0]
        out.append(Quotient('%s | int: %s' % (term, iname), fL, fI))
        info.append((term, sc, iname, best[0]))
    if verbose:
        log('automatic selection: %d list partitions scored on %d list operators (%d probes each); '
            '%d int partitions on %d int operators' % (len(cands), len(lops), P, len(icands), len(iops)))
        log('top 12 list candidates by mean lumpability:')
        for c in cands[:12]:
            log('     %.3f  %-46s size %d  smallest block %.3f' % (c[0], c[2], c[1], c[5]))
        log('top int candidates kept for pairing: ' + ', '.join('%s (%.3f)' % (c[2], c[0]) for c in ichosen))
        log('selected (K=%d):' % K)
        for (term, sc, iname, x) in info:
            log('     %.3f  %-46s paired with int quotient %s (cross-lumpability %.2f)' % (sc, term, iname, x))
        log('skipped above the last selected: %d candidates (%d redundant, %d small-block); first few: %s' %
            (len(skipped), sum(1 for s in skipped if s[2].startswith('red')),
             sum(1 for s in skipped if s[2] == 'small block'), skipped[:6]))
    return out, info


if __name__ == '__main__':
    select(6)
