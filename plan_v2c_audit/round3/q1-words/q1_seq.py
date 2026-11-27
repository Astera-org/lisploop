"""Q1 (sequences): lumpability ranking of an ENUMERATED pool of list quotients.

Pool: alpha(xs) = q(r(g(xs))) with
   g in {identity} + the 31 unary list->list operators of the 61-operator library,
   r in the 9 list->int reductions of the library,
   q = every unary integer term up to --qsize nodes over leaves v, 0..5 and
       operators + * mod < = abs sgn  (plus `min` when --with-min: needed to
       express a capped length; reported separately because it is a grammar choice).
Deduplicated by the partition induced on all probe values; 2..--blocks blocks.

Lumpability is measured on 15 operators (13 unary, 2 binary) over random lists
(length 0..8, elements in [-9, 9]), --P probes per operator, plug-in entropies.

usage: python3 q1_seq.py [--P 1500] [--qsize 4] [--with-min] [--seed 0]
"""
import argparse
import math
import random
import time
from collections import Counter

from seqlib import L, I, OPS, OPFN, OPSIG, rand_list

ap = argparse.ArgumentParser()
ap.add_argument('--P', type=int, default=1500)
ap.add_argument('--qsize', type=int, default=4)
ap.add_argument('--blocks', type=int, default=6)
ap.add_argument('--with-min', action='store_true')
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--top', type=int, default=15)
ap.add_argument('--maxlen', type=int, default=8)
A = ap.parse_args()
rng = random.Random(A.seed)

SEQ15 = ['reverse', 'sort', 'inc_all', 'dbl_all', 'neg_all', 'abs_all', 'running_sum', 'tail',
         'take3', 'map_adj_add', 'map_adj_sub', 'filter_pos', 'filter_even', 'zip_add', 'concat']

# ------------------------------------------------------------------ probes
pool = [rand_list(rng, 0, A.maxlen, 9) for _ in range(A.P)]
vid = {}
vals = []


def idx(v):
    i = vid.get(v)
    if i is None:
        i = vid[v] = len(vals)
        vals.append(v)
    return i


PROBE = {}
for name in SEQ15:
    at, rt = OPSIG[name]
    fn = OPFN[name]
    rows = []
    if len(at) == 1:
        for v in pool:
            rows.append((idx(v), None, idx(fn(v))))
    else:
        for _ in range(A.P):
            a, b = rng.choice(pool), rng.choice(pool)
            rows.append((idx(a), idx(b), idx(fn(a, b))))
    PROBE[name] = rows
NV = len(vals)


def H(counter, n):
    return -sum(c / n * math.log2(c / n) for c in counter.values())


def lump_parts(lab, name):
    rows = PROBE[name]
    n = len(rows)
    joint, inp, out = Counter(), Counter(), Counter()
    for (i, j, k) in rows:
        a = (lab[i], lab[j] if j is not None else -1)
        o = lab[k]
        joint[(a, o)] += 1
        inp[a] += 1
        out[o] += 1
    ho = H(out, n)
    hc = max(0.0, H(joint, n) - H(inp, n))
    return hc, ho


def canon(v):
    m = {}
    out = []
    for x in v:
        k = m.get(x)
        if k is None:
            k = m[x] = len(m)
        out.append(k)
    return tuple(out)


# ------------------------------------------------------------------ integer q-terms
def sgn(v):
    return (v > 0) - (v < 0)


def q_terms(maxsize, with_min):
    """(size, text, python function) for every q term, as closures over v."""
    lv = {1: [('v', lambda v: v)] + [(str(c), (lambda c: lambda v: c)(c)) for c in range(6)]}
    for s in range(2, maxsize + 1):
        cur = []
        for (t, f) in lv.get(s - 1, []):
            cur.append(('(abs %s)' % t, (lambda f: lambda v: abs(f(v)))(f)))
            cur.append(('(sgn %s)' % t, (lambda f: lambda v: sgn(f(v)))(f)))
        for s1 in range(1, s - 1):
            for (t1, f1) in lv.get(s1, []):
                for (t2, f2) in lv.get(s - 1 - s1, []):
                    mk = lambda op, f1=f1, f2=f2: (lambda v: op(f1(v), f2(v)))
                    cur.append(('(+ %s %s)' % (t1, t2), mk(lambda a, b: a + b)))
                    cur.append(('(* %s %s)' % (t1, t2), mk(lambda a, b: a * b)))
                    cur.append(('(mod %s %s)' % (t1, t2), mk(lambda a, b: a % b if b else None)))
                    cur.append(('(< %s %s)' % (t1, t2), mk(lambda a, b: int(a < b))))
                    cur.append(('(= %s %s)' % (t1, t2), mk(lambda a, b: None if a is None or b is None else int(a == b))))
                    if with_min:
                        cur.append(('(min %s %s)' % (t1, t2), mk(min)))
        lv[s] = cur
    out = []
    for s in sorted(lv):
        for (t, f) in lv[s]:
            if 'v' in t:
                out.append((s, t, f))
    return out


def safe(f, d):
    try:
        return f(d)
    except TypeError:        # a None from mod-by-zero flowed into arithmetic
        return None


def build_pool(with_min):
    Q = q_terms(A.qsize, with_min)
    G = [('', None)] + [(n, OPFN[n]) for (n, at, rt, fn) in OPS if at == (L,) and rt == L]
    R = [(n, OPFN[n]) for (n, at, rt, fn) in OPS if at == (L,) and rt == I]
    parts = {}
    n_raw = 0
    for gname, g in G:
        gv = vals if g is None else [g(v) for v in vals]
        for rname, r in R:
            u = [r(v) for v in gv]
            D = sorted(set(u))
            base = '(%s (%s xs))' % (rname, gname) if gname else '(%s xs)' % rname
            seen_local = set()
            for (qs, qt, qf) in Q:
                n_raw += 1
                m = {}
                ok = True
                for d in D:
                    x = safe(qf, d)
                    if x is None:
                        ok = False
                        break
                    m[d] = x
                if not ok:
                    continue
                nb = len(set(m.values()))
                if nb < 2 or nb > A.blocks:
                    continue
                key = canon([m[d] for d in D])
                if key in seen_local:
                    continue
                seen_local.add(key)
                lab = canon([m[x] for x in u])
                size = qs + 1 + (1 if gname else 0)        # nodes: q-term (v replaced) + r + g
                term = qt.replace('v', base)
                old = parts.get(lab)
                if old is None or old[0] > size:
                    parts[lab] = (size, term, nb)
    return parts, n_raw, len(Q), len(G), len(R)


def score(parts):
    rows = []
    for lab, (size, term, nb) in parts.items():
        hc, ho, lv = {}, {}, {}
        for name in SEQ15:
            c, o = lump_parts(lab, name)
            hc[name], ho[name] = c, o
            lv[name] = 0.0 if o < 1e-12 else 1.0 - c / o
        so = sum(ho.values())
        rows.append(dict(term=term, size=size, nb=nb, lab=lab, l=lv,
                         mean=sum(lv.values()) / len(SEQ15),
                         # second choice: constant output counts as exact (1.0)
                         mean1=sum((1.0 if ho[n] < 1e-12 else lv[n]) for n in SEQ15) / len(SEQ15),
                         # third choice: pooled entropies
                         pooled=0.0 if so < 1e-12 else 1.0 - sum(hc.values()) / so,
                         exact=sum(1 for n in SEQ15 if ho[n] > 1e-12 and hc[n] < 1e-12),
                         const=sum(1 for n in SEQ15 if ho[n] < 1e-12),
                         minblock=min(Counter(lab[i] for i in range(A.P)).values()) / A.P))
    return rows


NAMED = [
    ('len_cap5', lambda xs: min(len(xs), 5)), ('len_mod2', lambda xs: len(xs) % 2),
    ('all_even', lambda xs: all(x % 2 == 0 for x in xs)), ('is_empty', lambda xs: not xs),
    ('all_nonneg', lambda xs: all(x >= 0 for x in xs)),
    ('sign pattern (any<0, any>0)', lambda xs: (any(x < 0 for x in xs), any(x > 0 for x in xs))),
    ('parity pattern', lambda xs: (any(x % 2 for x in xs), any(x % 2 == 0 for x in xs))),
    ('order (asc, desc)', lambda xs: (all(a <= b for a, b in zip(xs, xs[1:])),
                                      all(a >= b for a, b in zip(xs, xs[1:])))),
    ('len_cap3', lambda xs: min(len(xs), 3)), ('len_mod3', lambda xs: len(xs) % 3),
    ('JUNK head_eq_2', lambda xs: bool(xs) and xs[0] == 2),
    ('JUNK sum_gt_5', lambda xs: sum(xs) > 5),
    ('JUNK last_even', lambda xs: bool(xs) and xs[-1] % 2 == 0),
    ('JUNK max_lt_3', lambda xs: max(xs, default=0) < 3),
]


def report(with_min):
    t0 = time.perf_counter()
    parts, n_raw, nq, ng, nr = build_pool(with_min)
    t1 = time.perf_counter()
    rows = score(parts)
    t2 = time.perf_counter()
    print('\n' + '#' * 100)
    print('# pool %s `min` in the q-grammar: %d q-terms x %d g x %d r = %d raw candidates -> '
          '%d distinct partitions with 2..%d blocks' %
          ('WITH' if with_min else 'WITHOUT', nq, ng, nr, n_raw, len(rows), A.blocks))
    print('# enumeration %.1f s, lumpability %.1f s; %d distinct probe values' % (t1 - t0, t2 - t1, NV))
    ranks = {}
    for key, title in (('mean', 'mean Lump over 15 ops (constant output = 0)'),
                       ('pooled', 'pooled entropies 1 - sum H(out|in) / sum H(out)'),
                       ('mean1', 'mean Lump over 15 ops, constant output counted as exact (=1)')):
        rs = sorted(rows, key=lambda r: (-r[key], r['size'], r['term']))
        ranks[key] = {r['term']: i + 1 for i, r in enumerate(rs)}
        print('\n== top %d by %s ==' % (A.top, title))
        print('%4s %-52s %2s %2s %6s %6s %6s %5s %5s %7s' %
              ('rank', 'term', 'sz', 'nb', 'mean', 'pooled', 'mean1', 'exact', 'const', 'minblk'))
        for i, r in enumerate(rs[:A.top]):
            print('%4d %-52s %2d %2d %6.3f %6.3f %6.3f %5d %5d %7.4f' %
                  (i + 1, r['term'][:52], r['size'], r['nb'], r['mean'], r['pooled'], r['mean1'],
                   r['exact'], r['const'], r['minblock']))
    bylab = {r['lab']: r for r in rows}
    print('\n== named quotients and distractors (score computed directly; rank if the partition is in the pool) ==')
    print('%-28s %6s %6s %6s %5s %5s | rank/%d by mean, pooled, mean1 | pool term' %
          ('name', 'mean', 'pooled', 'mean1', 'exact', 'const', len(rows)))
    for name, fn in NAMED:
        lab = canon([fn(v) for v in vals])
        sc = score({lab: (0, name, max(lab) + 1)})[0]
        r = bylab.get(lab)
        rk = ('%5d %5d %5d' % tuple(ranks[k][r['term']] for k in ('mean', 'pooled', 'mean1'))
              if r else '   not in pool   ')
        print('%-28s %6.3f %6.3f %6.3f %5d %5d | %s | %s' %
              (name, sc['mean'], sc['pooled'], sc['mean1'], sc['exact'], sc['const'], rk,
               r['term'] if r else '-'))
    print('per-operator Lump of the named quotients:')
    print('%-28s %s' % ('', ' '.join('%7s' % n[:7] for n in SEQ15)))
    for name, fn in NAMED:
        lab = canon([fn(v) for v in vals])
        sc = score({lab: (0, name, max(lab) + 1)})[0]
        print('%-28s %s' % (name, ' '.join('%7.2f' % sc['l'][n] for n in SEQ15)))
    v = sorted(r['mean'] for r in rows)
    q = lambda p: v[int(p * (len(v) - 1))]
    print('score distribution (mean): min %.3f q25 %.3f median %.3f q75 %.3f q90 %.3f q99 %.3f max %.3f'
          % (v[0], q(.25), q(.5), q(.75), q(.9), q(.99), v[-1]))
    return rows


print('# Q1 sequences: P=%d probes/op, lists len 0..%d, elements [-9,9], q-terms up to %d nodes, seed %d'
      % (A.P, A.maxlen, A.qsize, A.seed))
print('# 15 operators:', SEQ15)
report(False)
report(True)
