"""M2(2): do label tables save memory inside a lifted position space?

A lifted position space is emulated as the reviewer does it: one row per (sequence, position).
Leaves i, len, 0, 1 (and k where the task has one); binary + - * mod max min on integers
(a candidate undefined on any row -- mod by b <= 0 -- is dropped); unary `at`: at(idx) = xs[idx]
(dropped if out of range on any row).  Size = number of nodes; `at` is one node.

Quotients (per row): parity, mod 3, sign; optionally the fault guard of `at` as a fourth word,
inrange = (0 <= v < len).  Every operator INCLUDING `at` gets a verb table by one group-by over
probes.  Two tables for `at`:
   A : keyed on the label of the index only;
   S : keyed on (label of the SEQUENCE, label of the index), the sequence label being the set of
       labels its elements take (so "all even", "all non-negative" are sequence labels).

Searches (target size unknown; bound deepened N = 1, 2, ...):
   plain : bottom-up with behaviour dedupe.
   LL    : filter before evaluation on the LAST size only (the reviewer's EXP A2 design).  Nothing
           below the last size is filtered, so the bank is plain's by construction; lower sizes
           are enumerated once and kept across bounds.
   EL    : every size: (1) a candidate is skipped before evaluation if no label its tables allow
           can reach the target's labels in the nodes that remain; (2) an evaluated class of size
           s is stored only if s + h <= N (tested before it enters the dedupe table); (3) a class
           of size N-1 is stored only if `at` (the only unary operator) may take it to the target.
           Restart per bound; all passes counted; memory = peak over passes.
h = max over quotients and rows of the least number of further nodes from the class's label to
the target's label on that row (binary step = 2 nodes, `at` = 1), by Dijkstra on the tables.

usage: python3 m4_lifted.py [--seed 1] [--nseq 6] [--tasks all] [--guard]
"""
import argparse
import heapq
import operator
import random
import time
from collections import defaultdict

INF = 99


def _mod(a, b):
    return a % b


BIN = [('+', operator.add, True), ('-', operator.sub, False), ('*', operator.mul, True),
       ('mod', _mod, False), ('max', max, True), ('min', min, True)]

Q_BASE = [('parity', lambda v, n: v & 1), ('mod3', lambda v, n: v % 3),
          ('sign', lambda v, n: (v > 0) - (v < 0))]
Q_GUARD = ('inrange', lambda v, n: 0 <= v < n)


# ----------------------------------------------------------------- verb tables from probes
def learn_tables(quots, seed=0, grid=12, nat=4000):
    """One group-by per (operator, quotient).  Binary operators: a, b on [-grid, grid]^2 for each
    len in 1..7 (len matters only to the guard word).  `at`: nat random (sequence, index) probes,
    index in [-3, len+2]; an undefined result contributes no output label."""
    rng = random.Random(seed)
    T = []
    for qn, qf in quots:
        tq = {}
        for on, fn, _ in BIN:
            t = defaultdict(set)
            for n in range(1, 8):
                for a in range(-grid, grid + 1):
                    la = qf(a, n)
                    for b in range(-grid, grid + 1):
                        if on == 'mod' and b <= 0:
                            t[(la, qf(b, n))]            # seen, no output: undefined
                            continue
                        t[(la, qf(b, n))].add(qf(fn(a, b), n))
            tq[on] = dict(t)
        T.append(tq)
    atA = [defaultdict(set) for _ in quots]
    atS = [defaultdict(set) for _ in quots]
    for _ in range(nat):
        n = rng.randint(1, 7)
        kind = rng.random()
        if kind < 0.6:
            xs = [rng.randint(-5, 6) for _ in range(n)]
        elif kind < 0.8:                       # so that uniform sequences are well represented
            xs = [abs(rng.randint(-5, 6)) for _ in range(n)]
        else:
            xs = [2 * rng.randint(-3, 3) + rng.choice((0, 0, 1)) * 0 for _ in range(n)]
        for idx in range(-3, n + 3):
            for j, (qn, qf) in enumerate(quots):
                li = qf(idx, n)
                sl = tuple(sorted(set(qf(v, n) for v in xs)))
                atA[j][(li,)]
                atS[j][(sl, li)]
                if 0 <= idx < n:
                    o = qf(xs[idx], n)
                    atA[j][(li,)].add(o)
                    atS[j][(sl, li)].add(o)
    labels = []
    for j, (qn, qf) in enumerate(quots):
        ls = set()
        for t in T[j].values():
            for k, v in t.items():
                ls.update(k)
                ls.update(v)
        labels.append(sorted(ls))
    return dict(bin=T, atA=[dict(t) for t in atA], atS=[dict(t) for t in atS], labels=labels)


# ----------------------------------------------------------------- tasks
def make_rows(seed, nseq, lo=3, hi=6):
    rng = random.Random(seed)
    seqs = [tuple(rng.randint(-5, 6) for _ in range(rng.randint(lo, hi))) for _ in range(nseq)]
    ks = [rng.randint(1, len(s) - 1) for s in seqs]
    return seqs, ks


TASKDEF = [
    # name, description, adjacent-rows-only, uses k, target(xs, i, k), where the arithmetic is
    ('madd', 'xs[i] + xs[i+1]', True, False, lambda s, i, k: s[i] + s[i + 1], 'both'),
    ('msub', 'xs[i+1] - xs[i]', True, False, lambda s, i, k: s[i + 1] - s[i], 'both'),
    ('reverse', 'xs[len-1-i]', False, False, lambda s, i, k: s[len(s) - 1 - i], 'below'),
    ('rotl', 'xs[(i+k) mod len]', False, True, lambda s, i, k: s[(i + k) % len(s)], 'below'),
    ('scale', 'xs[i] * (i+1)', False, False, lambda s, i, k: s[i] * (i + 1), 'above'),
    ('stride', 'xs[(i+i) mod len]', False, False, lambda s, i, k: s[(i + i) % len(s)], 'below'),
    ('dlast', 'xs[i] - xs[len-1]', False, False, lambda s, i, k: s[i] - s[len(s) - 1], 'both'),
    ('revplus', 'xs[len-1-i] + i', False, False, lambda s, i, k: s[len(s) - 1 - i] + i, 'both'),
    # controls with NO `at` in the answer: is it `at` that stops the labels, or the bound itself?
    ('ctl1', '(i+1) * (len-i)', False, False, lambda s, i, k: (i + 1) * (len(s) - i), 'none'),
    ('ctl2', 'i*i - len*len', False, False, lambda s, i, k: i * i - len(s) * len(s), 'none'),
]


class Task:
    def __init__(self, tdef, seqs, ks, quots, tabs, at_table):
        name, desc, adj, usek, fn, where = tdef
        self.name, self.desc, self.where = name, desc, where
        xs, ii, ln, kk, tg = [], [], [], [], []
        for s, k in zip(seqs, ks):
            for i in range(len(s) - (1 if adj else 0)):
                xs.append(s)
                ii.append(i)
                ln.append(len(s))
                kk.append(k)
                tg.append(fn(s, i, k))
        self.xs, self.len = xs, tuple(ln)
        self.m = len(tg)
        self.target = tuple(tg)
        self.leaves = [('i', tuple(ii)), ('len', tuple(ln)), ('0', (0,) * self.m), ('1', (1,) * self.m)]
        if usek:
            self.leaves.append(('k', tuple(kk)))
        self.quots = quots
        self.nq = len(quots)
        self.tabs = tabs
        self.at_table = at_table
        self.rows = range(self.m)
        # per quotient and row: the context of `at` (the sequence's label, table S) and the target's label
        self.tl = [tuple(qf(v, n) for v, n in zip(self.target, ln)) for qn, qf in quots]
        self.sl = [tuple(tuple(sorted(set(qf(v, len(s)) for v in s))) for s in xs) for qn, qf in quots]
        self.cid = []            # per quotient: per row an id of (sequence label, target label)
        self.cidkeys = []
        for j in range(self.nq):
            ids = {}
            row = []
            for r in range(self.m):
                key = (self.sl[j][r] if at_table == 'S' else None, self.tl[j][r])
                if key not in ids:
                    ids[key] = len(ids)
                row.append(ids[key])
            self.cid.append(tuple(row))
            self.cidkeys.append({v: k for k, v in ids.items()})
        self.dist = [dict() for _ in range(self.nq)]         # (cid) -> {label: nodes still needed}
        self.memo_b = [defaultdict(dict) for _ in range(self.nq)]   # op -> {(a, b, cid): bound}
        self.memo_a = [dict() for _ in range(self.nq)]

    def labs(self, col):
        ln = self.len
        return tuple(tuple(map(qf, col, ln)) for qn, qf in self.quots)

    def at_outs(self, j, sl, a):
        if self.at_table == 'S':
            o = self.tabs['atS'][j].get((sl, a))
        else:
            o = self.tabs['atA'][j].get((a,))
        return self.tabs['labels'][j] if o is None else o

    def d(self, j, cid):
        """Backward Dijkstra on single-row labels of quotient j, towards the target label of
        the rows with this cid; `at` edges use those rows' sequence label."""
        dd = self.dist[j].get(cid)
        if dd is not None:
            return dd
        sl, t = self.cidkeys[j][cid]
        labels = self.tabs['labels'][j]
        pred = defaultdict(list)
        for a in labels:
            for o in self.at_outs(j, sl, a):
                pred[o].append((a, 1))
            for on, fn, _ in BIN:
                tb = self.tabs['bin'][j][on]
                for b in labels:
                    for o in tb.get((a, b), labels):
                        pred[o].append((a, 2))
                    for o in tb.get((b, a), labels):
                        pred[o].append((a, 2))
        dd = {t: 0}
        heap = [(0, 0, t)]
        n = 0
        while heap:
            ds, _, s = heapq.heappop(heap)
            if ds > dd.get(s, INF):
                continue
            for a, c in pred[s]:
                if ds + c < dd.get(a, INF):
                    dd[a] = ds + c
                    n += 1
                    heapq.heappush(heap, (ds + c, n, a))
        self.dist[j][cid] = dd
        return dd

    def h(self, labs):
        m = 0
        for j in range(self.nq):
            cj = self.cid[j]
            lj = labs[j]
            for r in self.rows:
                v = self.d(j, cj[r]).get(lj[r], INF)
                if v > m:
                    m = v
        return m

    def ok_bin(self, on, la, lb, rem):
        """May on(a, b) still reach the target's labels within rem further nodes, on every row?"""
        for j in range(self.nq):
            A, B, C = la[j], lb[j], self.cid[j]
            memo = self.memo_b[j][on]
            tb = self.tabs['bin'][j][on]
            for r in self.rows:
                key = (A[r], B[r], C[r])
                v = memo.get(key)
                if v is None:
                    outs = tb.get((A[r], B[r]))
                    if outs is None:
                        outs = self.tabs['labels'][j]
                    dd = self.d(j, C[r])
                    v = min((dd.get(o, INF) for o in outs), default=INF)
                    memo[key] = v
                if v > rem:
                    return False
        return True

    def ok_at(self, la, rem):
        for j in range(self.nq):
            A, C = la[j], self.cid[j]
            memo = self.memo_a[j]
            for r in self.rows:
                key = (A[r], C[r])
                v = memo.get(key)
                if v is None:
                    dd = self.d(j, C[r])
                    v = min((dd.get(o, INF) for o in self.at_outs(j, self.sl[j][r], A[r])), default=INF)
                    memo[key] = v
                if v > rem:
                    return False
        return True

    def eval_at(self, idx):
        out = []
        for r in self.rows:
            ix = idx[r]
            if ix < 0 or ix >= self.len[r]:
                return None
            out.append(self.xs[r][ix])
        return tuple(out)


def lpass(T, N, mode, asgo=False):
    """One pass.  mode: 'plain', 'LL' (filter the last size only), 'EL' (every size).
    Returns counts; per_level[s] = classes stored at size s; last = candidates evaluated at
    the last size (until the hit, if any)."""
    levels = defaultdict(list)          # size -> [(col, labs)]
    seen = set()
    evaluated = 0
    last = 0
    skipped = 0
    cut_h = cut_la = 0
    target = T.target
    use = mode != 'plain'

    def res(hit, s):
        return dict(hit=hit, hit_size=s, evaluated=evaluated, last=last, seen_n=len(seen),
                    per_level={k: len(v) for k, v in levels.items()}, skipped=skipped,
                    cut_h=cut_h, cut_la=cut_la)

    def file(col, s):
        nonlocal cut_h, cut_la
        if col in seen:
            return
        labs = T.labs(col) if use else None
        if mode == 'EL':
            if s + T.h(labs) > N:
                cut_h += 1
                return
            if s == N - 1 and not T.ok_at(labs, 0):
                cut_la += 1
                return
        seen.add(col)
        levels[s].append((col, labs))

    for s in range(1, N + 1):
        final = (s == N) and not asgo
        rem = N - s
        filt = (mode == 'EL') or (mode == 'LL' and final)
        if s == 1:
            for nm, col in T.leaves:
                evaluated += 1
                last += final
                if col == target:
                    return res(True, 1)
                if not final:
                    file(col, 1)
            continue
        for (c, lb) in levels[s - 1]:
            if filt and not T.ok_at(lb, rem):
                skipped += 1
                continue
            evaluated += 1
            last += final
            col = T.eval_at(c)
            if col is None:
                continue
            if col == target:
                return res(True, s)
            if not final:
                file(col, s)
        for s1 in range(1, s - 1):
            s2 = s - 1 - s1
            L1, L2 = levels[s1], levels[s2]
            if not L1 or not L2:
                continue
            for (on, fn, comm) in BIN:
                if comm and s1 > s2:
                    continue
                same = comm and s1 == s2
                ismod = on == 'mod'
                for i1, (c1, l1) in enumerate(L1):
                    for i2 in range(i1 if same else 0, len(L2)):
                        c2, l2 = L2[i2]
                        if filt and not T.ok_bin(on, l1, l2, rem):
                            skipped += 1
                            continue
                        evaluated += 1
                        last += final
                        if ismod and min(c2) <= 0:
                            continue
                        col = tuple(map(fn, c1, c2))
                        if col == target:
                            return res(True, s)
                        if not final:
                            file(col, s)
    return res(False, None)


def run_task(T, cap):
    pl = lpass(T, cap, 'plain', asgo=True)
    if not pl['hit']:
        return None
    ns = pl['hit_size']
    below = sum(v for k, v in pl['per_level'].items() if k < ns)
    out = dict(name=T.name, desc=T.desc, where=T.where, rows=T.m, ns=ns, plain_eval=pl['evaluated'],
               plain_below=below, plain_at_hit=pl['seen_n'],
               plain_top=pl['per_level'].get(ns - 1, 0), plain_levels=pl['per_level'])
    # plain evaluations of the sizes below ns (each enumerated once)
    pg = lpass(T, ns, 'plain')
    below_eval = pg['evaluated'] - pg['last']
    # LL, size given (the reviewer's setting): one pass at ns
    ll = lpass(T, ns, 'LL')
    out['ll_given'] = dict(found=ll['hit'], evaluated=ll['evaluated'], stored=ll['seen_n'])
    # LL, size unknown: lower sizes enumerated once and kept; the filtered last size tried at each bound
    tot = below_eval
    found = False
    for N in range(1, ns + 1):
        r = lpass(T, N, 'LL')
        tot += r['last']
        if r['hit']:
            found = r['hit_size'] == ns
            break
    out['ll'] = dict(found=found, evaluated=tot, stored=ll['seen_n'])
    # EL, size unknown, restart per bound
    tot = 0
    peak = 0
    r = None
    for N in range(1, ns + 1):
        r = lpass(T, N, 'EL')
        tot += r['evaluated']
        peak = max(peak, r['seen_n'])
        if r['hit']:
            break
    top = r['per_level'].get(ns - 1, 0)
    out['el'] = dict(found=r['hit'] and r['hit_size'] == ns, evaluated=tot, stored=peak,
                     last_pass=r['evaluated'], levels=r['per_level'], cut_h=r['cut_h'],
                     cut_la=r['cut_la'], top=top)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--nseq', type=int, default=6)
    ap.add_argument('--tasks', default='all')
    ap.add_argument('--cap', type=int, default=8)
    A = ap.parse_args()
    t0 = time.time()
    seqs, ks = make_rows(A.seed, A.nseq)
    print('# M2(2) lifted position space; seed %d; %d sequences %s; k = %s' % (A.seed, len(seqs), seqs, ks))
    defs = [t for t in TASKDEF if A.tasks == 'all' or t[0] in A.tasks.split(',')]
    variants = [('A', Q_BASE, 'A', 'parity, mod 3, sign; `at` keyed on the index label'),
                ('S', Q_BASE, 'S', 'the same; `at` keyed on (sequence label, index label)'),
                ('SG', Q_BASE + [Q_GUARD], 'S', 'S plus the guard word inrange = (0 <= v < len)')]
    tabs = {}
    for vn, quots, att, _ in variants:
        key = len(quots)
        if key not in tabs:
            tabs[key] = learn_tables(quots, seed=0)
    for vn, quots, att, desc in variants:
        tb = tabs[len(quots)]
        print('\n== variant %s: %s ==' % (vn, desc))
        if vn == 'A':
            for j, (qn, _) in enumerate(quots):
                print('   `at` table A under %-7s: %s' % (qn, {k[0]: sorted(v) for k, v in sorted(tb['atA'][j].items())}))
        if vn == 'S':
            for j, (qn, _) in enumerate(quots):
                n_all = sum(1 for k, v in tb['atS'][j].items() if set(v) == set(tb['labels'][j]))
                print('   `at` table S under %-7s: %d (sequence label, index label) entries, %d of them allow every label'
                      % (qn, len(tb['atS'][j]), n_all))
        print('%-8s %-20s %-5s %4s %2s | %9s %7s %7s | %9s %9s %6s | %9s %6s | %9s %7s %6s %6s | %s' %
              ('task', 'target', 'arith', 'rows', 'N*', 'plain ev', 'stored', 'top', 'LL given', 'LL unkn.',
               'stored', 'EL evals', 'gain', 'EL stored', 'gain', 'cut h', 'cut la', 'lost'))
        for td in defs:
            T = Task(td, seqs, ks, quots, tb, att)
            o = run_task(T, A.cap)
            if o is None:
                print('%-8s not found by plain within size %d' % (td[0], A.cap))
                continue
            ll, lg, el = o['ll'], o['ll_given'], o['el']
            lost = [n for n, f in (('LL', ll['found']), ('LLg', lg['found']), ('EL', el['found'])) if not f]
            print('%-8s %-20s %-5s %4d %2d | %9d %7d %7d | %9d %9d %6d | %9d %5.1fx | %9d %6.2fx %6d %6d | %s' %
                  (o['name'], o['desc'], o['where'], o['rows'], o['ns'], o['plain_eval'], o['plain_below'],
                   o['plain_top'], lg['evaluated'], ll['evaluated'], ll['stored'], el['evaluated'],
                   o['plain_eval'] / el['evaluated'], el['stored'], o['plain_below'] / max(1, el['stored']),
                   el['cut_h'], el['cut_la'], ','.join(lost) or 'none'))
            low = sum(o['plain_levels'].get(s, 0) - el['levels'].get(s, 0) for s in range(1, o['ns'] - 1))
            print('%-8s   stored per size: plain %s | EL %s | gains: LL given %.1fx, LL unknown %.1fx evaluations; '
                  'plain with size N*-1 as hashes: %d full classes (%.1fx); EL cut %d classes below size N*-1' %
                  ('', [o['plain_levels'].get(s, 0) for s in range(1, o['ns'])],
                   [el['levels'].get(s, 0) for s in range(1, o['ns'])],
                   o['plain_eval'] / lg['evaluated'], o['plain_eval'] / ll['evaluated'],
                   o['plain_below'] - o['plain_top'], o['plain_below'] / max(1, o['plain_below'] - o['plain_top']),
                   low))
            SUMMARY.append((vn, o['name'], o['where'], o['ns'], o['plain_eval'], o['plain_below'], o['plain_top'],
                            lg['evaluated'], ll['evaluated'], el['evaluated'], el['stored'], low, len(lost)))
    print('\n== summary (seed %d): gains over plain; "stored" counts classes below N*; EL = every size ==' % A.seed)
    print('%-8s %-5s %2s | %8s %8s | %-26s | %-26s | %-26s | %10s | %s' %
          ('task', 'arith', 'N*', 'LL evals', 'LL store', 'EL-A evals / stored', 'EL-S evals / stored',
           'EL-SG evals / stored', 'hash-top', 'cut below N*-1 (A,S,SG); lost'))
    names = [t[0] for t in defs]
    by = {(v, n): row for (v, n, *row) in SUMMARY}
    for n in names:
        if ('A', n) not in by:
            continue
        a, s, g = by[('A', n)], by[('S', n)], by[('SG', n)]
        where, ns, pev, pst, ptop = a[0], a[1], a[2], a[3], a[4]
        cell = lambda r: '%5.1fx / %5.2fx (%d)' % (pev / r[7], pst / max(1, r[8]), r[8])
        print('%-8s %-5s %2d | %7.1fx %7.2fx | %-26s | %-26s | %-26s | %9.2fx | %d,%d,%d; %d' %
              (n, where, ns, pev / s[6], 1.0, cell(a), cell(s), cell(g), pst / max(1, pst - ptop),
               a[9], s[9], g[9], a[10] + s[10] + g[10]))
    print('\ntotal %.1f s' % (time.time() - t0))


SUMMARY = []

if __name__ == '__main__':
    main()
