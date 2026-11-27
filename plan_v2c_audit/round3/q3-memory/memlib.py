"""memlib: bottom-up polynomial search with explicit memory accounting.

Extends q3lib (the earlier reproduction): same grammar (leaves x, y, 0, 1; + - * binary, neg
unary; + and * up to commutativity; size = number of nodes), same abstract domains
(residues mod p of a column on a few rows) and the same forward/backward tables.

Memory lives in two containers:
   seen : the dedupe table (a set of columns)
   bank : the per-size lists of classes that later sizes are built from
MODES of one pass with size bound N (the last size N is compared with the target, never stored):
   plain : no test.
   bank  : (b) every new column goes into `seen`; only columns that pass s + h <= N go into the bank.
   pre   : (c) the test is made BEFORE inserting into `seen` (label read off the evaluated column).
   pred  : (c') as (c), but the label is PREDICTED from the argument labels before the candidate
           is evaluated (possible because residues commute with + - * neg), so a failing
           candidate is not even evaluated.  This is what q3lib.search does.
"""
import operator
import sys
from collections import defaultdict

from q3lib import INFTY, fdiv, fmod

OPS_G1 = [('+', operator.add, True, 'add'), ('-', operator.sub, False, 'sub'),
          ('*', operator.mul, True, 'mul')]
OPS_G2 = OPS_G1 + [('div', fdiv, False, None), ('mod', fmod, False, None)]


def deep_size(roots):
    """Sum of sys.getsizeof over every distinct object reachable from `roots` through
    tuples, lists, sets, frozensets and dicts (each object counted once, by id)."""
    seen = set()
    tot = 0
    stack = list(roots)
    gs = sys.getsizeof
    while stack:
        o = stack.pop()
        i = id(o)
        if i in seen:
            continue
        seen.add(i)
        tot += gs(o)
        t = type(o)
        if t is tuple or t is list or t is set or t is frozenset:
            stack.extend(o)
        elif t is dict:
            stack.extend(o.keys())
            stack.extend(o.values())
    return tot


class Labeller:
    """Label of a column = tuple of abstract-state ids, one per domain; h = max over domains."""

    def __init__(self, doms, hs):
        self.doms = doms
        self.hs = hs
        self.nd = len(doms)

    def key(self, col):
        k = []
        for d in self.doms:
            i = d.ids.get(d.alpha(col))
            if i is None:
                return None          # outside the ring closure (only with div/mod)
            k.append(i)
        return tuple(k)

    def h(self, key):
        if key is None:
            return INFTY
        m = 0
        for d in range(self.nd):
            v = self.hs[d][key[d]]
            if v > m:
                m = v
        return m


def one_pass(leaves, target, N, lab=None, mode='plain', ops=OPS_G1, keep=False, asgo=False,
             check=False):
    """One bottom-up pass.

    asgo=False: the size bound N is binding: size N is only compared with the target.
    asgo=True (plain only): the size is not known; every size is stored as it is enumerated
          and the pass stops at the first hit (N is then just a cap).
    Returns counts.  seen_n / bank_n are the peaks (both only ever grow within a pass).
    kept (if keep): {column: size} of the bank, cutcols: columns in `seen` but not in the bank."""
    assert mode in ('plain', 'bank', 'pre', 'pred')
    assert mode == 'plain' or lab is not None
    levels = defaultdict(list)          # size -> [(column, key)]
    seen = set()
    nbank = 0
    evaluated = 0
    hit = None
    hit_size = None
    seen_below = 0                      # len(seen) when the hit level started
    retest_flip = 0                     # a column tested twice in one pass with different outcomes
    first_test = {} if check else None  # column -> outcome of its first test (proof check)
    prune = mode != 'plain'
    tkey = lab.key(target) if prune else None
    tabs = None
    if mode == 'pred':
        D = lab.doms
        nd = lab.nd
        tabs = {'add': [d.add for d in D], 'sub': [d.sub for d in D], 'mul': [d.mul for d in D]}
        negt = [d.neg for d in D]

    def consider(col, s, key):
        """File an evaluated candidate of a stored size s.  key: its label if already known."""
        nonlocal nbank, retest_flip
        if mode == 'plain':
            if col not in seen:
                seen.add(col)
                levels[s].append((col, None))
                nbank += 1
            return
        if mode == 'bank':
            if col in seen:
                return
            seen.add(col)
            key = lab.key(col)
            if s + lab.h(key) <= N:
                levels[s].append((col, key))
                nbank += 1
            return
        # pre / pred: test first, insert only what is kept
        if key is None:
            key = lab.key(col)
        ok = s + lab.h(key) <= N
        if first_test is not None:
            # the harmful case would be: cut at its first test, kept at a later one
            ft = first_test.get(col)
            if ft is None:
                first_test[col] = ok
            elif ok and not ft:
                retest_flip += 1
        if not ok:
            return
        if col not in seen:
            seen.add(col)
            levels[s].append((col, key))
            nbank += 1

    def result():
        r = dict(hit=hit is not None, hit_at=hit, hit_size=hit_size, evaluated=evaluated,
                 seen_n=len(seen), bank_n=nbank, seen_below=seen_below, retest_flip=retest_flip)
        if keep:
            r['seen'] = seen
            r['levels'] = levels
        else:
            r['bytes'] = deep_size([seen, levels])
        return r

    for s in range(1, N + 1):
        final = (s == N) and not asgo
        rem = N - s
        seen_below = len(seen)
        if s == 1:
            for _, col in leaves:
                evaluated += 1
                if col == target and hit is None:
                    hit, hit_size = evaluated, 1
                    if asgo:
                        return result()
                if not final:
                    consider(col, 1, None)
        else:
            # ---- neg
            for (c, k) in levels[s - 1]:
                nk = None
                if mode == 'pred':
                    nk = tuple(negt[d][k[d]] for d in range(nd))
                    if lab.h(nk) > rem:
                        continue
                col = tuple(map(operator.neg, c))
                evaluated += 1
                if col == target and hit is None:
                    hit, hit_size = evaluated, s
                    if asgo:
                        return result()
                if not final:
                    consider(col, s, nk)
            # ---- binary
            for s1 in range(1, s - 1):
                s2 = s - 1 - s1
                L1 = levels[s1]
                L2 = levels[s2]
                if not L1 or not L2:
                    continue
                for (oname, fn, comm, tname) in ops:
                    if comm and s1 > s2:
                        continue
                    same = comm and s1 == s2
                    partial = tname is None
                    tb = tabs[tname] if (mode == 'pred' and tname) else None
                    for i1, (c1, k1) in enumerate(L1):
                        for i2 in range(i1 if same else 0, len(L2)):
                            c2, k2 = L2[i2]
                            nk = None
                            if tb is not None:
                                nk = tuple(tb[d][k1[d]][k2[d]] for d in range(nd))
                                if lab.h(nk) > rem:
                                    continue
                            if partial and 0 in c2:
                                continue
                            col = tuple(map(fn, c1, c2))
                            evaluated += 1
                            if col == target and hit is None:
                                hit, hit_size = evaluated, s
                                if asgo:
                                    return result()
                            if not final:
                                consider(col, s, nk)
        if hit is not None and not final:
            return result()            # found below the bound
    return result()


def kept_map(r):
    """{column: size} of the bank of a pass run with keep=True."""
    kept = {}
    for s, lv in r['levels'].items():
        for col, _ in lv:
            kept[col] = s
    return kept


def deepen(leaves, target, n0, nmax, lab, mode, ops=OPS_G1):
    """Policy R: the size is unknown; the bound N goes n0, n0+1, ...; every pass restarts from
    nothing.  Peak memory is the maximum over passes; evaluations are summed over passes."""
    tot = 0
    peak_seen = peak_bank = peak_sum = peak_bytes = 0
    passes = []
    last = None
    for N in range(n0, nmax + 1):
        r = one_pass(leaves, target, N, lab, mode, ops)
        passes.append((N, r['evaluated'], r['seen_n'], r['bank_n']))
        peak_seen = max(peak_seen, r['seen_n'])
        peak_bank = max(peak_bank, r['bank_n'])
        peak_sum = max(peak_sum, r['seen_n'] + r['bank_n'])
        peak_bytes = max(peak_bytes, r['bytes'])
        last = r
        if r['hit']:
            tot += r['hit_at']
            break
        tot += r['evaluated']
    return dict(found=last['hit'], N=N, hit_size=last['hit_size'], evaluated=tot,
                last_evaluated=last['evaluated'], peak_seen=peak_seen, peak_bank=peak_bank,
                peak_sum=peak_sum, peak_bytes=peak_bytes, passes=passes, last=last)


def incremental(leaves, target, n0, nmax, lab, ops=OPS_G1, naive=False):
    """Policy K: the size is unknown; the bank is KEPT from one bound to the next.

    A column that fails the test at bound N is not stored; a CUT RECORD is kept for it instead:
        hash(column) -> (size, f = size + h, the candidate that produced it)
    with no column.  When the bound reaches f the candidate is re-evaluated and the class
    stored.  Sizes below the bound are processed incrementally (only candidates with at least
    one argument that is new in this pass); the top size N of each pass is only compared with
    the target and is evaluated again, in full, when it becomes a stored size in the next pass.
    Labels are read off evaluated columns (the general case: no prediction before evaluation).

    Across passes sizes are NOT visited in increasing order, so a record must carry its size
    and be replaced when a smaller derivation of the same column turns up (`replaced`).
    naive=True drops that: the first record for a column stands (a cut-set with no sizes)."""
    levels = defaultdict(list)          # size -> [column]
    seen = {}                           # kept column -> size
    cut = {}                            # hash(column) -> (size, f, cand)
    byF = defaultdict(list)             # f -> [hash]
    st = dict(evaluated=0, reeval=0, replaced=0, promoted=0, peak_kept=0, peak_cut=0,
              peak_cut_alone=0)
    full_done = 0
    N = n0

    def file(col, s, cand):
        if col in seen:
            return
        f = s + lab.h(lab.key(col))
        hh = hash(col)
        if f <= N:
            seen[col] = s
            levels[s].append(col)
            cut.pop(hh, None)
        else:
            r = cut.get(hh)
            if r is not None and naive:
                return                  # naive: "already seen as cut", whatever its size was
            if r is None or s < r[0]:
                if r is not None:
                    st['replaced'] += 1
                cut[hh] = (s, f, cand)
                byF[f].append(hh)

    def evalc(cand):
        if cand[0] == 'leaf':
            return cand[1]
        if cand[0] == 'neg':
            return tuple(map(operator.neg, cand[1]))
        return tuple(map(cand[0], cand[1], cand[2]))

    def finish(found, s):
        st['peak_kept'] = max(st['peak_kept'], len(seen))
        st['peak_cut'] = max(st['peak_cut'], len(cut))
        # bytes of the cut records WITHOUT the argument columns they point to (those are kept
        # classes and are counted in bytes_kept): dict + key int + record tuple + candidate tuple
        gs = sys.getsizeof
        bc = gs(cut) + sum(gs(v) for v in byF.values()) + gs(byF)
        for hh, r in cut.items():
            bc += gs(hh) + gs(r) + gs(r[2])
        st.update(found=found, N=N, hit_size=s, kept=dict(seen), n_cut=len(cut),
                  bytes_kept=deep_size([seen, levels]), bytes_cut=bc)
        return st

    for N in range(n0, nmax + 1):
        old = {s: len(levels[s]) for s in range(1, N + 1)}
        prom = defaultdict(list)
        for hh in byF.pop(N, ()):
            r = cut.get(hh)
            if r is not None and r[1] == N:
                prom[r[0]].append(hh)
        for s in range(1, N + 1):
            top = s == N
            incr = s <= full_done
            # 1. promote the records whose budget has now been reached
            for hh in prom.get(s, ()):
                r = cut.get(hh)
                if r is None or r[0] != s or r[1] != N:
                    continue
                col = evalc(r[2])
                st['evaluated'] += 1
                st['reeval'] += 1
                del cut[hh]
                if col not in seen:
                    seen[col] = s
                    levels[s].append(col)
                    st['promoted'] += 1
            # 2. candidates of size s
            if s == 1:
                if not incr:
                    for _, col in leaves:
                        st['evaluated'] += 1
                        if col == target:
                            return finish(True, s)
                        if not top:
                            file(col, 1, ('leaf', col))
                continue
            L = levels[s - 1]
            for i in range(old[s - 1] if incr else 0, len(L)):
                c = L[i]
                col = tuple(map(operator.neg, c))
                st['evaluated'] += 1
                if col == target:
                    return finish(True, s)
                if not top:
                    file(col, s, ('neg', c))
            for s1 in range(1, s - 1):
                s2 = s - 1 - s1
                L1 = levels[s1]
                L2 = levels[s2]
                if not L1 or not L2:
                    continue
                o1, o2 = (old[s1], old[s2]) if incr else (0, 0)
                for (oname, fn, comm, tname) in ops:
                    if comm and s1 > s2:
                        continue
                    same = comm and s1 == s2
                    if same:
                        pairs = ((i1, i2) for i2 in range(o1 if incr else 0, len(L1))
                                 for i1 in range(0, i2 + 1))
                    elif incr:
                        pairs = ((i1, i2) for i1 in range(len(L1))
                                 for i2 in range(o2 if i1 < o1 else 0, len(L2)))
                    else:
                        pairs = ((i1, i2) for i1 in range(len(L1)) for i2 in range(len(L2)))
                    for i1, i2 in pairs:
                        c1 = L1[i1]
                        c2 = L2[i2]
                        col = tuple(map(fn, c1, c2))
                        st['evaluated'] += 1
                        if col == target:
                            return finish(True, s)
                        if not top:
                            file(col, s, (fn, c1, c2))
            st['peak_kept'] = max(st['peak_kept'], len(seen))
            st['peak_cut'] = max(st['peak_cut'], len(cut))
        full_done = max(full_done, N - 1)
    return finish(False, None)
