"""The two worked examples of plan_v2c_audit.md Appendix B.3 / A.3, recomputed.

  python3 b3_example.py > b3_example.log
"""
import random

from hlib import (L, I, OPS, OPSIG, OPFN, BASE61, BASE61_SET, AbsCtx, Bank, tables_for, col_dl, col_l1,
                  pct_rank, int_bits, make_inputs)
import seqlib


def example1(rows, tag):
    env = {'xs': tuple(rows)}
    f = OPFN
    y = tuple(f['dbl_all'](f['sort'](f['abs_all'](x))) for x in rows)
    print('\n--- %s: %d row(s); y = dbl_all(sort(abs_all(xs)))' % (tag, len(rows)))
    if len(rows) == 1:
        print('    xs = %s   y = %s' % (rows[0], y[0]))
    bank = Bank(env, BASE61_SET)
    bank.level(2, y, store=True)
    bank.level(3, y, store=True)
    tb = tables_for(BASE61, 2000, 'iid', 0)
    ctx = AbsCtx(tb, y, L)
    right = tuple(map(f['abs_all'], rows))
    wrong = tuple(map(f['running_max'], rows))
    print('    L1(abs_all(xs), y) = %s   L1(running_max(xs), y) = %s   (review: 12 and 8 on its one row)' % (
        col_l1(right, y), col_l1(wrong, y)))
    print('    DL(y | abs_all(xs)) = %d bits   DL(y | running_max(xs)) = %d bits' % (col_dl(right, y), col_dl(wrong, y)))
    for s in (2,):
        pool = bank.lev[L][s]
        l1s = [col_l1(bank.cols[i], y) for i in pool]
        dls = [col_dl(bank.cols[i], y) for i in pool]
        dfd = [v for v in l1s if v is not None]
        print('    size-%d list classes: %d, L1 defined for %d' % (s, len(pool), len(dfd)))
        for nm, col in (('abs_all(xs)  [on the path]', right), ('running_max(xs) [off the path]', wrong)):
            i = bank.idx[col]
            a = ctx.abstract(col, L)
            h = ctx.ah[a]
            print('      %-30s L1 rank %2d of %d   DL rank %2d of %d   label bound h = %d  -> %s at n* = 4' % (
                nm, 1 + sum(1 for v in dfd if v < l1s[pool.index(i)]), len(dfd),
                1 + sum(1 for v in dls if v < dls[pool.index(i)]), len(pool), h,
                'KEPT by labels' if 2 + h <= 4 else 'ruled out by labels'))
        out = sum(1 for i in pool if 2 + ctx.ah[ctx.abstract(bank.cols[i], L)] > 4)
        print('      labels rule out %d of the %d size-2 list classes at n* = 4' % (out, len(pool)))
        best = sorted(pool, key=lambda i: (col_l1(bank.cols[i], y) is None, col_l1(bank.cols[i], y) or 0))[:5]
        print('      five closest by L1: ' + ', '.join('%s (%s)' % (seqlib.term_str(bank.term(i)),
                                                                   col_l1(bank.cols[i], y)) for i in best))
    # does any size-4 program pass through running_max(xs)?  (brute force over the bank representatives)
    un = [o for o in OPS if o[0] in BASE61_SET and o[1] == (L,) and o[2] == L]
    thru = 0
    for (n1, _, _, f1) in un:
        mid = tuple(map(f1, wrong))
        for (n2, _, _, f2) in un:
            if tuple(map(f2, mid)) == y:
                thru += 1
    print('      unary chains g(f(running_max(xs))) that equal y: %d  (so the labels keep a class that cannot '
          'be completed)' % thru if thru == 0 else '      chains through running_max(xs) reaching y: %d' % thru)


def example2():
    print('\n--- Example 2: target T = 2*x*x + 1; candidates A = 2*x*x (near miss) and B = 2*y*y')
    rng = random.Random(3)
    for tag, rows in (('8 random rows, x, y in -9..9', [(rng.randint(-9, 9), rng.randint(-9, 9)) for _ in range(8)]),
                      ('grid x, y in -4..4 (81 rows)', [(x, y) for x in range(-4, 5) for y in range(-4, 5)])):
        T = [2 * x * x + 1 for x, y in rows]
        A = [2 * x * x for x, y in rows]
        B = [2 * y * y for x, y in rows]
        print('    %s' % tag)
        qs = [('parity (x mod 2)', lambda v: v % 2), ('sign', lambda v: (v > 0) - (v < 0)),
              ('non-negative (2 labels)', lambda v: v >= 0), ('x mod 3', lambda v: v % 3),
              ('x mod 5', lambda v: v % 5)]
        for nm, q in qs:
            diff = sum(1 for a, b in zip(A, B) if q(a) != q(b))
            # after the one step "+ 1": do the labels of A+1 and B+1 match the target's?
            okA = all(q(a + 1) == q(t) for a, t in zip(A, T))
            okB = all(q(b + 1) == q(t) for b, t in zip(B, T))
            print('      %-24s rows where the labels of A and B differ: %2d of %d;   labels of (A+1) match T: %s;'
                  '  labels of (B+1) match T: %s' % (nm, diff, len(rows), okA, okB))
        ra = [t - a for t, a in zip(T, A)]
        rb = [t - b for t, b in zip(T, B)]
        print('      residual T - A: %s -> constant, %d bits row by row;   T - B: %d distinct values, %d bits' % (
            sorted(set(ra)), sum(map(int_bits, ra)), len(set(rb)), sum(map(int_bits, rb))))


if __name__ == '__main__':
    print('Example 1 (review B.3): is the wrong first step closer than the right one, and do labels fix it?')
    example1([(3, -1, 4, 2)], 'the review\'s single row')
    for seed in (1, 2, 3):
        rng = random.Random(seed)
        env = make_inputs(rng, ['xs'], rows=8)
        example1(list(env['xs']), '8 random rows, seed %d' % seed)
    example2()
