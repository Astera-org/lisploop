"""M1 on polynomials: where the memory is, and what "test before inserting" buys.

Grammar G1 = {+, -, *, neg} over leaves x, y, 0, 1; 32 rows; size = number of nodes.
Labels: residues mod 2 on 12 rows, mod 3 on 4 rows, mod 5 on 3 rows (as the earlier q3_poly.py).

For each target:
  (a) plain, (b) prune the bank only, (c) test before inserting [label read off the evaluated
  column], (c') the same with the label predicted before evaluation;
  first with the size GIVEN (one pass at the true size), then with the size UNKNOWN:
     policy R: the bound is deepened from the tables' own lower bound, every pass restarts,
               memory = peak over passes, evaluations = sum over passes;
     policy K: the bank is kept across bounds, a cut class leaves a record (hash, size, budget,
               candidate) and is re-evaluated when the bound reaches its budget.
Entries are counted separately for the dedupe table (`seen`) and the bank.  Bytes: Python =
sum of sys.getsizeof over every distinct object reachable from the two containers; "model" =
entries x the live bytes per entry measured in SBCL on the prototype's structures (m2_bytes.log).

usage: python3 m1_poly.py [--seed 0] [--nrand 200] [--procs 12] [--ng2 60]
"""
import argparse
import math
import multiprocessing as mp
import operator
import random
import time
import tracemalloc

from q3lib import Domain, pick_rows, fdiv, fmod
from memlib import (Labeller, one_pass, deepen, incremental, kept_map, deep_size, OPS_G1, OPS_G2)

B_FULL, B_COL, B_HASH, B_REC = 448.7, 331.7, 27.5, 91.7      # m2_bytes.log

ap = argparse.ArgumentParser()
ap.add_argument('--rows', type=int, default=32)
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--nrand', type=int, default=200)
ap.add_argument('--ng2', type=int, default=60)
ap.add_argument('--procs', type=int, default=12)
ap.add_argument('--maxsize', type=int, default=13)
A = ap.parse_args()

rng = random.Random(A.seed)
xs = tuple(rng.randint(-9, 9) for _ in range(A.rows))
ys = tuple(rng.randint(-9, 9) for _ in range(A.rows))
leaves = [('x', xs), ('y', ys), ('0', tuple([0] * A.rows)), ('1', tuple([1] * A.rows))]
leaf_cols = [c for _, c in leaves]
DOM = [Domain(2, list(range(12)), leaf_cols), Domain(3, pick_rows(xs, ys, 3, 4), leaf_cols),
       Domain(5, pick_rows(xs, ys, 5, 3), leaf_cols)]
for d in DOM:
    d.forward([d.ids[d.alpha(c)] for c in leaf_cols])

SIX = [
    ('A2', '(x+x)*(y+1)', lambda x, y: (x + x) * (y + 1)),
    ('A3', 'x*y + x - y', lambda x, y: x * y + x - y),
    ('A4', '(x+y)*(x-y) + 1', lambda x, y: (x + y) * (x - y) + 1),
    ('A8', '(x+y)^2 - x*y + 1', lambda x, y: (x + y) ** 2 - x * y + 1),
    ('A11', '(x*y + x + 1)*(y - x)', lambda x, y: (x * y + x + 1) * (y - x)),
    ('A12', '2*(x^2 + y^2) - x*y', lambda x, y: 2 * (x * x + y * y) - x * y),
]


def gm(v):
    v = [x for x in v if x > 0]
    return math.exp(sum(math.log(x) for x in v) / len(v)) if v else float('nan')


def model(seen_n, bank_n):
    """Model bytes: a banked class is a full class; a column in `seen` only is column + table entry."""
    return bank_n * B_FULL + (seen_n - bank_n) * B_COL


def run_target(job):
    name, target, cap, trace = job
    t0 = time.perf_counter()
    pl = one_pass(leaves, target, cap, None, 'plain', asgo=True, keep=True)
    if not pl['hit']:
        return None
    ns = pl['hit_size']
    plain_sizes = kept_map(pl)
    out = dict(name=name, ns=ns, plain_hit_eval=pl['hit_at'], plain_at_hit=pl['seen_n'],
               plain_below=pl['seen_below'], plain_at_hit_bytes=deep_size([pl['seen'], pl['levels']]))
    del pl
    ids = [d.ids[d.alpha(target)] for d in DOM]
    hs = [d.backward(i) for d, i in zip(DOM, ids)]
    nmin = max(d.g[i] for d, i in zip(DOM, ids))
    lab = Labeller(DOM, hs)
    out['nmin'] = nmin
    # ---------------- size given
    K = {}
    for mode in ('plain', 'bank', 'pre', 'pred'):
        r = one_pass(leaves, target, ns, lab if mode != 'plain' else None, mode, keep=True, check=True)
        K[mode] = kept_map(r)
        out['g_' + mode] = dict(found=r['hit'] and r['hit_size'] == ns, seen=r['seen_n'],
                                bank=r['bank_n'], evaluated=r['evaluated'], hit_at=r['hit_at'],
                                bytes=deep_size([r['seen'], r['levels']]), flips=r['retest_flip'],
                                model=model(r['seen_n'], r['bank_n']))
        if mode == 'bank':
            # the columns (b) keeps in `seen` only: how many of them have s + h = ns + 1, i.e.
            # would be needed again if the bound were raised by one
            cut = [c for c in r['seen'] if c not in K[mode]]
            out['cut_b'] = len(cut)
        del r
    expect = {c: s for c, s in K['plain'].items() if s + lab.h(lab.key(c)) <= ns}
    out['chk_bank_eq_pre'] = K['bank'] == K['pre']
    out['chk_pred_eq_pre'] = K['pred'] == K['pre']
    out['chk_sizes_as_plain'] = all(plain_sizes.get(c) == s for c, s in K['pre'].items())
    out['chk_closed'] = expect == K['pre']       # nothing that passes the test is lost through a cut parent
    # ---------------- tracemalloc cross-check (python allocations still live after the pass)
    if trace:
        for mode in ('plain', 'bank', 'pre'):
            tracemalloc.start()
            r = one_pass(leaves, target, ns, lab if mode != 'plain' else None, mode, keep=True)
            cur, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            out['g_' + mode]['traced'] = cur
            del r
    # ---------------- size unknown, policy R (restart per bound)
    for mode in ('bank', 'pre', 'pred'):
        d = deepen(leaves, target, nmin, cap, lab, mode)
        out['r_' + mode] = dict(found=d['found'] and d['N'] == ns, N=d['N'], evaluated=d['evaluated'],
                                last_eval=d['last_evaluated'], peak_seen=d['peak_seen'],
                                peak_bank=d['peak_bank'], peak_bytes=d['peak_bytes'],
                                npass=len(d['passes']),
                                model=model(d['peak_seen'], d['peak_bank']),
                                peak_in_last=(d['peak_seen'] == d['last']['seen_n']))
    d = deepen(leaves, target, 1, cap, None, 'plain')
    out['r_plain'] = dict(evaluated=d['evaluated'], peak_seen=d['peak_seen'], peak_bytes=d['peak_bytes'],
                          found=d['found'] and d['N'] == ns)
    # ---------------- size unknown, policy K (keep the bank, cut records)
    k = incremental(leaves, target, nmin, cap, lab)
    out['k'] = dict(found=k['found'] and k['N'] == ns, N=k['N'], evaluated=k['evaluated'],
                    reeval=k['reeval'], replaced=k['replaced'], peak_kept=k['peak_kept'],
                    peak_cut=k['peak_cut'], bytes_kept=k['bytes_kept'], bytes_cut=k['bytes_cut'],
                    sizes_ok=all(plain_sizes.get(c, s) == s for c, s in k['kept'].items()),
                    superset=all(c in k['kept'] for c in K['pre']),
                    model=k['peak_kept'] * B_FULL + k['peak_cut'] * B_REC)
    # policy K with a cut-set that has no sizes (the review's one-pass argument carried across bounds)
    kn = incremental(leaves, target, nmin, cap, lab, naive=True)
    out['kn'] = dict(found=kn['found'] and kn['N'] == ns, N=kn['N'],
                     sizes_ok=all(plain_sizes.get(c, s) == s for c, s in kn['kept'].items()),
                     wrong=sum(1 for c, s in kn['kept'].items() if plain_sizes.get(c, s) != s))
    out['wall'] = time.perf_counter() - t0
    return out


def rand_term(r, size, ops):
    if size == 1:
        return r.choice(['x', 'y', 'x', 'y', '0', '1'])
    if size == 2 or (size % 2 == 0 and r.random() < 0.5) or (r.random() < 0.1):
        return ('neg', rand_term(r, size - 1, ops))
    s1 = r.randint(1, size - 2)
    return (r.choice(ops), rand_term(r, s1, ops), rand_term(r, size - 1 - s1, ops))


BIN = {'+': operator.add, '-': operator.sub, '*': operator.mul, 'div': fdiv, 'mod': fmod}


def ev(t):
    if isinstance(t, str):
        return dict(leaves)[t]
    if t[0] == 'neg':
        a = ev(t[1])
        return None if a is None else tuple(-v for v in a)
    a, b = ev(t[1]), ev(t[2])
    if a is None or b is None:
        return None
    if t[0] in ('div', 'mod') and 0 in b:
        return None
    return tuple(map(BIN[t[0]], a, b))


def g2_job(target):
    """(b) vs (c) with tables that are NOT sound (div and mod in the grammar; labels read off
    evaluated columns).  The equivalence of (b) and (c) must not depend on soundness."""
    pl = one_pass(leaves, target, 7, None, 'plain', OPS_G2, asgo=True)
    if not pl['hit']:
        return None
    ns = pl['hit_size']
    ids = [d.ids.get(d.alpha(target)) for d in DOM]
    if None in ids:
        return dict(ns=ns, outside=True)
    hs = [d.backward(i) for d, i in zip(DOM, ids)]
    lab = Labeller(DOM, hs)
    rp = one_pass(leaves, target, ns, None, 'plain', OPS_G2, keep=True)
    rb = one_pass(leaves, target, ns, lab, 'bank', OPS_G2, keep=True)
    rc = one_pass(leaves, target, ns, lab, 'pre', OPS_G2, keep=True, check=True)
    kp, kc = kept_map(rp), kept_map(rc)
    expect = {c: s for c, s in kp.items() if s + lab.h(lab.key(c)) <= ns}
    return dict(ns=ns, outside=False, same=kept_map(rb) == kc, found_b=rb['hit'],
                found_c=rc['hit'], flips=rc['retest_flip'], seen_b=rb['seen_n'], seen_c=rc['seen_n'],
                plain=pl['seen_below'], closed=expect == kc,
                sizes=all(kp.get(c) == s for c, s in kc.items()))


def table_given(rows):
    print('%-5s %2s | %-15s | %-22s | %-15s | %9s %9s | %8s %8s %8s | %6s %6s' %
          ('', 'sz', '(a) plain', '(b) bank only', '(c) test first', 'gain (b)', 'gain (c)',
           'KB (a)', 'KB (b)', 'KB (c)', 'x (b)', 'x (c)'))
    print('%-5s %2s | %7s %7s | %7s %7s %6s | %7s %7s | %9s %9s | %8s %8s %8s | %6s %6s' %
          ('', '', 'seen', 'bank', 'seen', 'bank', 'sum', 'seen', 'bank', 'seen', 'seen',
           'python', 'python', 'python', 'bytes', 'bytes'))
    for o in rows:
        a, b, c = o['g_plain'], o['g_bank'], o['g_pre']
        print('%-5s %2d | %7d %7d | %7d %7d %6d | %7d %7d | %8.1fx %8.1fx | %8.1f %8.1f %8.1f | %5.1fx %5.1fx' %
              (o['name'], o['ns'], a['seen'], a['bank'], b['seen'], b['bank'], b['seen'] + b['bank'],
               c['seen'], c['bank'], a['seen'] / b['seen'], a['seen'] / max(1, c['seen']),
               a['bytes'] / 1e3, b['bytes'] / 1e3, c['bytes'] / 1e3,
               a['bytes'] / b['bytes'], a['bytes'] / c['bytes']))


def main():
    t0 = time.time()
    print('# M1 polynomials: %d rows, x,y in [-9,9], seed %d; domains F_2 x12 rows (%d states), '
          'F_3 x4 (%d), F_5 x3 (%d)' % (A.rows, A.seed, DOM[0].n, DOM[1].n, DOM[2].n))
    jobs = [(n, tuple(f(x, y) for x, y in zip(xs, ys)), A.maxsize, True) for n, _, f in SIX]
    with mp.get_context('fork').Pool(min(A.procs, 6)) as pool:
        six = pool.map(run_target, jobs, chunksize=1)
    print('\n== Table 1. Six targets, size GIVEN (one pass at the true size; the last size is not stored) ==')
    table_given(six)
    print('\n   model bytes (SBCL: stored class %.0f B, column in the dedupe table only %.0f B):' % (B_FULL, B_COL))
    for o in six:
        a, b, c = o['g_plain'], o['g_bank'], o['g_pre']
        print('   %-5s (a) %9.1f KB  (b) %9.1f KB  (c) %8.1f KB   gain (b) %4.1fx  (c) %5.1fx   | '
              'tracemalloc live KB: (a) %8.1f (b) %8.1f (c) %7.1f  -> (b) %4.1fx (c) %5.1fx' %
              (o['name'], a['model'] / 1e3, b['model'] / 1e3, c['model'] / 1e3, a['model'] / b['model'],
               a['model'] / c['model'], a['traced'] / 1e3, b['traced'] / 1e3, c['traced'] / 1e3,
               a['traced'] / b['traced'], a['traced'] / c['traced']))
    print('\n   evaluations in that one pass: ' + '; '.join(
        '%s plain %d, (b) %d, (c) %d, (c\') %d' % (o['name'], o['g_plain']['evaluated'], o['g_bank']['evaluated'],
                                                  o['g_pre']['evaluated'], o['g_pred']['evaluated']) for o in six))
    print('\n== Table 2. Six targets, size UNKNOWN ==')
    print('%-5s %2s %4s | %-17s | %-33s | %-33s | %-45s' %
          ('', 'sz', 'Nmin', 'plain', 'R + (b) bank only', 'R + (c) test first',
           'K: keep bank + cut records (labels after eval.)'))
    print('%-5s %2s %4s | %8s %8s | %7s %7s %8s %7s | %7s %7s %8s %7s | %7s %7s %8s %7s %5s' %
          ('', '', '', 'below', 'at hit', 'seen', 'bank', 'evals', 'x last', 'seen', 'bank', 'evals',
           'x last', 'kept', 'records', 'evals', 're-ev', 'repl'))
    for o in six:
        b, c, k = o['r_bank'], o['r_pre'], o['k']
        print('%-5s %2d %4d | %8d %8d | %7d %7d %8d %6.2fx | %7d %7d %8d %6.2fx | %7d %7d %8d %7d %5d' %
              (o['name'], o['ns'], o['nmin'], o['plain_below'], o['plain_at_hit'], b['peak_seen'],
               b['peak_bank'], b['evaluated'], b['evaluated'] / max(1, o['g_bank']['hit_at']),
               c['peak_seen'], c['peak_bank'], c['evaluated'], c['evaluated'] / max(1, o['g_pre']['hit_at']),
               k['peak_kept'], k['peak_cut'], k['evaluated'], k['reeval'], k['replaced']))
    print('\n   the same in bytes, and as gains over plain (plain = classes below the hit size):')
    print('%-5s | %10s %10s | %10s %7s | %10s %7s | %10s %7s || python KB: %8s %8s %8s %8s' %
          ('', 'plain KB', '(at hit)', 'R+(b) KB', 'gain', 'R+(c) KB', 'gain', 'K KB', 'gain',
           'plain', 'R+(b)', 'R+(c)', 'K'))
    for o in six:
        b, c, k = o['r_bank'], o['r_pre'], o['k']
        pm = o['plain_below'] * B_FULL
        print('%-5s | %10.1f %10.1f | %10.1f %6.1fx | %10.1f %6.1fx | %10.1f %6.1fx || %19.1f %8.1f %8.1f %8.1f' %
              (o['name'], pm / 1e3, o['plain_at_hit'] * B_FULL / 1e3, b['model'] / 1e3, pm / b['model'],
               c['model'] / 1e3, pm / c['model'], k['model'] / 1e3, pm / k['model'],
               o['g_plain']['bytes'] / 1e3, b['peak_bytes'] / 1e3, c['peak_bytes'] / 1e3,
               (k['bytes_kept'] + k['bytes_cut']) / 1e3))
    print('\n   evaluations until the hit: ' + '; '.join(
        '%s plain %d (restarting plain %d), R+(c) %d, R+(c\') %d, K %d' %
        (o['name'], o['plain_hit_eval'], o['r_plain']['evaluated'], o['r_pre']['evaluated'],
         o['r_pred']['evaluated'], o['k']['evaluated']) for o in six))
    print('   peak over passes is reached in the last pass: %s' %
          all(o['r_' + m]['peak_in_last'] for o in six for m in ('bank', 'pre', 'pred')))

    # ------------------------------------------------------------ random targets
    r2 = random.Random(A.seed + 1000)
    seen = set()
    jobs = []
    tries = 0
    while len(jobs) < A.nrand and tries < 100000:
        tries += 1
        t = rand_term(r2, r2.choice([7, 9, 9, 11, 11]), ['+', '-', '*'])
        col = ev(t)
        if col is None or len(set(col)) < 3 or col in seen:
            continue
        seen.add(col)
        jobs.append(('R%d' % len(jobs), col, 11, False))
    with mp.get_context('fork').Pool(A.procs) as pool:
        rnd = [o for o in pool.map(run_target, jobs, chunksize=1) if o is not None]
    allr = six + rnd
    print('\n== Table 3. %d random polynomial targets (written with 7-11 nodes; plain cap 11), by true size ==' % len(rnd))
    print('%4s %4s | %-31s | %-31s | %-23s | %-24s' %
          ('size', 'n', 'size given: gain in entries', 'size unknown, R: gain', 'K: gain', 'evaluations x last pass'))
    print('%4s %4s | %9s %9s %9s | %9s %9s %9s | %9s %11s | %7s %7s %7s' %
          ('', '', '(b) seen', '(c) seen', '(c) bytes', '(b) model', '(c) model', '(c) py', 'model', 'rec/kept',
           'R (c)', "R (c')", 'K'))
    for sz in sorted({o['ns'] for o in rnd}):
        g = [o for o in rnd if o['ns'] == sz]
        print('%4d %4d | %8.2fx %8.2fx %8.2fx | %8.2fx %8.2fx %8.2fx | %8.2fx %11.1f | %6.2fx %6.2fx %6.2fx' %
              (sz, len(g),
               gm([o['g_plain']['seen'] / max(1, o['g_bank']['seen']) for o in g]),
               gm([o['g_plain']['seen'] / max(1, o['g_pre']['seen']) for o in g]),
               gm([o['g_plain']['bytes'] / max(1, o['g_pre']['bytes']) for o in g]),
               gm([o['plain_below'] * B_FULL / max(1, o['r_bank']['model']) for o in g]),
               gm([o['plain_below'] * B_FULL / max(1, o['r_pre']['model']) for o in g]),
               gm([o['g_plain']['bytes'] / max(1, o['r_pre']['peak_bytes']) for o in g]),
               gm([o['plain_below'] * B_FULL / max(1, o['k']['model']) for o in g]),
               sum(o['k']['peak_cut'] for o in g) / max(1, sum(o['k']['peak_kept'] for o in g)),
               gm([o['r_pre']['evaluated'] / max(1, o['g_pre']['hit_at']) for o in g]),
               gm([o['r_pred']['evaluated'] / max(1, o['g_pred']['hit_at']) for o in g]),
               gm([o['k']['evaluated'] / max(1, o['g_pre']['hit_at']) for o in g])))
    big = [o for o in rnd if o['ns'] >= 7]
    print('   targets of true size >= 7 (%d): entries gain (b) %.2fx [%.2f..%.2f], (c) %.1fx [%.1f..%.1f]' %
          (len(big), gm([o['g_plain']['seen'] / max(1, o['g_bank']['seen']) for o in big]),
           min(o['g_plain']['seen'] / max(1, o['g_bank']['seen']) for o in big),
           max(o['g_plain']['seen'] / max(1, o['g_bank']['seen']) for o in big),
           gm([o['g_plain']['seen'] / max(1, o['g_pre']['seen']) for o in big]),
           min(o['g_plain']['seen'] / max(1, o['g_pre']['seen']) for o in big),
           max(o['g_plain']['seen'] / max(1, o['g_pre']['seen']) for o in big)))

    print('\n== Checks over all %d targets (six + random) ==' % len(allr))
    n = len(allr)
    print('   found at the plain size: size given (b) %d (c) %d (c\') %d; R (b) %d (c) %d (c\') %d; K %d   of %d' %
          (sum(o['g_bank']['found'] for o in allr), sum(o['g_pre']['found'] for o in allr),
           sum(o['g_pred']['found'] for o in allr), sum(o['r_bank']['found'] for o in allr),
           sum(o['r_pre']['found'] for o in allr), sum(o['r_pred']['found'] for o in allr),
           sum(o['k']['found'] for o in allr), n))
    print('   bank of (b) identical to bank of (c), columns and sizes: %d of %d' %
          (sum(o['chk_bank_eq_pre'] for o in allr), n))
    print("   bank of (c') identical to bank of (c): %d of %d" % (sum(o['chk_pred_eq_pre'] for o in allr), n))
    print('   every kept class has the size plain search gives it: %d of %d' %
          (sum(o['chk_sizes_as_plain'] for o in allr), n))
    print('   kept set = exactly the plain classes with size + h <= N (no class lost through a cut '
          'argument): %d of %d' % (sum(o['chk_closed'] for o in allr), n))
    print('   policy K with a cut-set that carries no sizes: found at the plain size %d of %d (found later or not '
          'at all: %s); targets with a kept class at a wrong size: %d' %
          (sum(o['kn']['found'] for o in allr), n,
           [(o['name'], o['ns'], o['kn']['N']) for o in allr if not o['kn']['found']][:8],
           sum(1 for o in allr if not o['kn']['sizes_ok'])))
    print('   a column cut at its first test in a pass and kept at a later test in the same pass: (c) %d, (c\') %d times' %
          (sum(o['g_pre']['flips'] for o in allr), sum(o['g_pred']['flips'] for o in allr)))
    print('   len(seen) == len(bank) under (c): %d of %d' %
          (sum(o['g_pre']['seen'] == o['g_pre']['bank'] for o in allr), n))
    print('   policy K: kept sizes equal plain sizes %d of %d; kept is a superset of the one-pass bank %d of %d; '
          'records replaced by a SMALLER derivation found in a later pass: %d (in %d targets)' %
          (sum(o['k']['sizes_ok'] for o in allr), n, sum(o['k']['superset'] for o in allr), n,
           sum(o['k']['replaced'] for o in allr), sum(1 for o in allr if o['k']['replaced'])))
    print('   policy R peak is in the last pass: %d of %d' %
          (sum(all(o['r_' + m]['peak_in_last'] for m in ('bank', 'pre', 'pred')) for o in allr), n))

    # ------------------------------------------------------------ unsound tables
    r3 = random.Random(A.seed + 2000)
    seen = set()
    cols = []
    tries = 0
    while len(cols) < A.ng2 and tries < 100000:
        tries += 1
        t = rand_term(r3, r3.choice([5, 5, 7, 7]), ['+', '-', '*', 'div', 'mod', 'div', 'mod'])
        col = ev(t)
        if col is None or len(set(col)) < 3 or col in seen or 'div' not in str(t) and 'mod' not in str(t):
            continue
        seen.add(col)
        cols.append(col)
    with mp.get_context('fork').Pool(A.procs) as pool:
        g2 = [o for o in pool.map(g2_job, cols, chunksize=1) if o is not None]
    ins = [o for o in g2 if not o['outside']]
    print('\n== Unsound labels (div and mod added; residues do not commute with them): %d random targets, '
          '%d with a label the tables know ==' % (len(g2), len(ins)))
    print('   bank of (b) identical to bank of (c): %d of %d; a column cut at its first test and kept at a later '
          'one: %d times; answers lost by (b) %d, by (c) %d' %
          (sum(o['same'] for o in ins), len(ins), sum(o['flips'] for o in ins),
           sum(not o['found_b'] for o in ins), sum(not o['found_c'] for o in ins)))
    print('   (the labels really are unsound here: the kept set differs from "plain classes with size + h <= N" '
          'on %d of %d targets; a kept class has a size other than its plain size on %d)' %
          (sum(not o['closed'] for o in ins), len(ins), sum(not o['sizes'] for o in ins)))
    print('\ntotal %.1f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
