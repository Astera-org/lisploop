"""mem61: the 61-operator sequence library (seqlib.py) searched with explicit memory accounting.

Reuses the earlier reproduction's tables and per-task context (seqlib.build_tables,
q2search.AbsCtx) and re-implements the pass so that the dedupe table (`seen`) and the bank are
counted separately and the order "test, then insert" can be switched.

One pass with size bound N (the last size is only compared with the target):
   prefilter : a candidate is skipped BEFORE evaluation if every label the tables allow for its
               result needs more than N - s further nodes (never touches `seen`);
   the post-evaluation test: a new column of size s is banked only if s + h(labels) <= N;
   lookahead : a new column of size N-1 is banked only if some unary operator may, by the
               tables, take it to the target's labels (size N-1 is used by unary operators only);
   seen_mode : 'b' = insert into `seen` first, then test (bank-only pruning)
               'c' = test first, insert only what is banked.
"""
import time
from collections import defaultdict

from seqlib import L, I, OPS, OPSIG
from q2search import AbsCtx, _Lev, _unary_idxs
from memlib import deep_size

UNARY = {L: [o[0] for o in OPS if o[1] == (L,)], I: [o[0] for o in OPS if o[1] == (I,)]}


def lev_roots(lev):
    out = []
    for t_ in (L, I):
        for K in lev[t_].values():
            out += [K.cols, K.aids, K.vids, K.groups]
    return out


def plain_pass(inputs, target, N, asgo=False):
    """Plain bottom-up search with behaviour dedupe.  asgo: size unknown, store every size as it
    is enumerated and stop at the first hit; otherwise size N is compared only."""
    lev = {L: defaultdict(list), I: defaultdict(list)}
    seen = set()
    evaluated = 0
    per_level = {}
    for s in range(1, N + 1):
        final = (s == N) and not asgo
        before = len(seen)
        if s == 1:
            for name, col in inputs.items():
                evaluated += 1
                if col == target:
                    return dict(hit=True, hit_size=1, evaluated=evaluated, seen_n=len(seen),
                                seen_below=before, per_level=per_level, seen=seen, lev=lev)
                if not final and col not in seen:
                    seen.add(col)
                    lev[L][1].append(col)
        else:
            for (name, at, rt, fn) in OPS:
                out = lev[rt][s]
                if len(at) == 1:
                    for c in lev[at[0]][s - 1]:
                        col = tuple(map(fn, c))
                        evaluated += 1
                        if col == target:
                            return dict(hit=True, hit_size=s, evaluated=evaluated, seen_n=len(seen),
                                        seen_below=before, per_level=per_level, seen=seen, lev=lev)
                        if not final and col not in seen:
                            seen.add(col)
                            out.append(col)
                else:
                    for s1 in range(1, s - 1):
                        A = lev[at[0]][s1]
                        B = lev[at[1]][s - 1 - s1]
                        if not A or not B:
                            continue
                        for c1 in A:
                            for c2 in B:
                                col = tuple(map(fn, c1, c2))
                                evaluated += 1
                                if col == target:
                                    return dict(hit=True, hit_size=s, evaluated=evaluated,
                                                seen_n=len(seen), seen_below=before,
                                                per_level=per_level, seen=seen, lev=lev)
                                if not final and col not in seen:
                                    seen.add(col)
                                    out.append(col)
        per_level[s] = len(seen) - before
    return dict(hit=False, hit_size=None, evaluated=evaluated, seen_n=len(seen), seen_below=len(seen),
                per_level=per_level, seen=seen, lev=lev)


def pass61(inputs, target, N, ctx, prefilter=True, seen_mode='c', lookahead=False):
    nq = ctx.nq
    lev = {L: defaultdict(lambda: _Lev(nq)), I: defaultdict(lambda: _Lev(nq))}
    seen = set()
    evaluated = 0
    nbank = 0
    per_level = defaultdict(int)
    ah, aids_tab = ctx.ah, ctx.aids
    la_cache = {}
    flips = 0
    first = {}

    def la_ok(a, ty):
        k = (a, ty)
        v = la_cache.get(k)
        if v is None:
            v = False
            for name in UNARY[ty]:
                if ctx.bound(name, a) <= 0:
                    v = True
                    break
            la_cache[k] = v
        return v

    def file(col, s, rt):
        nonlocal nbank, flips
        if col in seen:
            return
        if seen_mode == 'b':
            seen.add(col)
        a = ctx.abstract(col, rt)
        ok = s + ah[a] <= N and not (lookahead and s == N - 1 and not la_ok(a, rt))
        if seen_mode == 'c':
            f = first.get(col)
            if f is None:
                if not ok:
                    first[col] = False       # proof check only: a cut column must stay cut
            elif f != ok:
                flips += 1
        if not ok:
            return
        if seen_mode == 'c':
            seen.add(col)
        lev[rt][s].add(col, a, aids_tab[a])
        nbank += 1
        per_level[s] += 1

    def result(hit, s):
        return dict(hit=hit, hit_size=s, evaluated=evaluated, seen_n=len(seen), bank_n=nbank,
                    per_level=dict(per_level), flips=flips,
                    bytes=deep_size([seen] + lev_roots(lev)))

    for name, col in inputs.items():
        evaluated += 1
        if col == target:
            return result(True, 1)
        if N > 1:
            file(col, 1, L)
    for s in range(2, N + 1):
        rem = N - s
        final = s == N
        for t_ in (L, I):
            for k_ in list(lev[t_].keys()):
                lev[t_][k_].freeze()
        for (name, at, rt, fn) in OPS:
            if len(at) == 1:
                K = lev[at[0]].get(s - 1)
                if K is None or not K.cols:
                    continue
                idxs = _unary_idxs(ctx, K, name, rem)[0] if prefilter else range(len(K.cols))
                cols = K.cols
                for i in idxs:
                    col = tuple(map(fn, cols[i]))
                    evaluated += 1
                    if col == target:
                        return result(True, s)
                    if not final:
                        file(col, s, rt)
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
                            if prefilter:
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
                                        return result(True, s)
                                    if not final:
                                        file(col, s, rt)
    return result(False, None)


def deepen61(inputs, target, ttype, tables, cap, prefilter, seen_mode, lookahead, ctx=None):
    """Policy R: bound N = 1, 2, ..., cap; every pass restarts; all passes counted."""
    ctx = ctx or AbsCtx(tables, target, ttype)
    tot = 0
    flips = 0
    peak = dict(seen=0, bank=0, bytes=0, full_fused=0, hash_fused=0)
    t0 = time.perf_counter()
    r = None
    for N in range(1, cap + 1):
        r = pass61(inputs, target, N, ctx, prefilter, seen_mode, lookahead)
        tot += r['evaluated']
        flips += r['flips']
        peak['seen'] = max(peak['seen'], r['seen_n'])
        peak['bank'] = max(peak['bank'], r['bank_n'])
        peak['bytes'] = max(peak['bytes'], r['bytes'])
        # "fused top": sizes <= N-2 kept as columns, size N-1 as hashes only (mode c only)
        top = r['per_level'].get(N - 1, 0) if N >= 2 else 0
        if r['bank_n'] - top >= peak['full_fused']:
            peak['full_fused'] = r['bank_n'] - top
            peak['hash_fused'] = top
        if r['hit']:
            break
    return dict(found=r['hit'], N=N, hit_size=r['hit_size'], evaluated=tot, flips=flips,
                last_evaluated=r['evaluated'], wall=time.perf_counter() - t0, **peak)
