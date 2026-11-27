"""Experiment A (claim U1): ONE routine, five regimes.

residual(space, A_columns, B_column, qA, qB) groups the rows of `space` by the
projected A values and reports how well they determine the projected B value.

Run:  python3 u1_residual.py > u1_residual.log
Standard library only; fixed seeds.
"""
import inspect
import math
import random
from collections import Counter, defaultdict

from seqlib import (L, I, OPFN, OPSIG, Q_PARITY, Q_SIGN, Q_CAPLEN, make_pools, eval_probes, Tables)


# ============================================================ the shared routine
def residual(space, A, B, qA=None, qB=None):
    """space: list of rows (dict: column name -> value).  A: list of column names.
    B: a column name.  qA: one projection per A column (None = identity).  qB: projection
    of B (None = identity).

    Returns a dict:
      H_cond   empirical conditional entropy H(qB(B) | qA(A)), bits per row
      H_out    empirical entropy H(qB(B)), bits per row
      score    dependency score 1 - H_cond/H_out (0 when H_out = 0)
      undet    number of rows that lie in a group with more than one B label
      n, groups, labels   rows, distinct A keys, distinct B labels
      table    {A key: B label} when every group is determined, else None
      counts   {A key: Counter(B label)}   (the verb table, when q is a quotient)
      dl_bits  description length of the B labels given the A keys, in bits, under an
               ADAPTIVE COUNT CODE: rows are coded in order; a row's label is coded with
               probability (c + 1/2) / (m + K/2), c = times this label was already seen
               under this A key, m = rows already seen under this key, K = number of
               distinct B labels on the space (Krichevsky-Trofimov estimator).  A decoder
               that knows the A keys and K can rebuild the counts, so it is a valid code.
      dl_free  the same code with no A key at all (what B costs unconditioned)."""
    qA = qA or [None] * len(A)
    keys, labs = [], []
    for row in space:
        keys.append(tuple(row[a] if q is None else q(row[a]) for a, q in zip(A, qA)))
        labs.append(row[B] if qB is None else qB(row[B]))
    n = len(space)
    counts = defaultdict(Counter)
    for k, b in zip(keys, labs):
        counts[k][b] += 1
    K = len(set(labs))

    def H(c):
        m = sum(c.values())
        return -sum(v / m * math.log2(v / m) for v in c.values())
    H_cond = sum(sum(c.values()) / n * H(c) for c in counts.values())
    H_out = H(Counter(labs))
    undet = sum(sum(c.values()) for c in counts.values() if len(c) > 1)

    def adaptive(keyseq):
        seen = defaultdict(Counter)
        bits = 0.0
        for k, b in zip(keyseq, labs):
            c = seen[k]
            bits -= math.log2((c[b] + 0.5) / (sum(c.values()) + K / 2))
            c[b] += 1
        return bits
    H_cond, H_out = abs(H_cond), abs(H_out)
    return dict(H_cond=H_cond, H_out=H_out, score=(1 - H_cond / H_out) if H_out > 0 else 0.0,
                undet=undet, n=n, groups=len(counts), labels=K,
                table={k: next(iter(c)) for k, c in counts.items()} if undet == 0 else None,
                counts=dict(counts), dl_bits=adaptive(keys), dl_free=adaptive([()] * n))


def show(tag, r, extra=''):
    print('  %-46s H_cond=%.3f H_out=%.3f score=%.3f undet=%d/%d groups=%d labels=%d '
          'dl=%.1f (free %.1f) %s' % (tag, r['H_cond'], r['H_out'], r['score'], r['undet'], r['n'],
                                      r['groups'], r['labels'], r['dl_bits'], r['dl_free'], extra))


# ============================================================ what each regime needs BEYOND the routine
# (each helper is counted in lines at the end)

def extra_law_is_identity(r):
    """A law is an EQUALITY of columns: the table must be the identity."""
    return r['table'] is not None and all(k == (v,) for k, v in r['table'].items())


def extra_law_enumerate(leaves, ops, max_size, rows):
    """The term space: every term to a size bound with its column (the enumerator the
    store already has).  Returns rows {term, col} for the group-by on the term space."""
    by = defaultdict(list)
    for name, col in leaves:
        by[1].append((name, col))
    for s in range(2, max_size + 1):
        for (op, ar, fn) in ops:
            if ar == 1:
                for (t, c) in by[s - 1]:
                    by[s].append(('(%s %s)' % (op, t), tuple(map(fn, c))))
            else:
                for s1 in range(1, s - 1):
                    for (t1, c1) in by[s1]:
                        for (t2, c2) in by[s - 1 - s1]:
                            by[s].append(('(%s %s %s)' % (op, t1, t2), tuple(map(fn, c1, c2))))
    return [dict(term=t, col=c, size=s) for s in sorted(by) for (t, c) in by[s]]


def extra_inverse_guard(space, det_mask, guard_pool):
    """The weakest guard in a pool that is true only on determined rows (a mask test)."""
    valid = []
    for name, fn in guard_pool:
        g = [bool(fn(row)) for row in space]
        if any(g) and all(d for d, gi in zip(det_mask, g) if gi):
            valid.append((name, g))
    weakest = [(n, g) for (n, g) in valid
               if not any(g2 != g and all(b or not a for a, b in zip(g, g2)) for (_, g2) in valid)]
    return valid, weakest


def extra_inverse_witness(space, target, mask, leaves, ops):
    """Search for a term over the given leaves that equals `target` on the masked rows."""
    tried = 0
    cands = [(n, [row[n] for row in space]) for n in leaves]
    for (t, c) in cands:
        tried += 1
        if all(a == b for a, b, m in zip(c, target, mask) if m):
            return t, tried
    for (op, fn) in ops:
        for (t1, c1) in cands:
            for (t2, c2) in cands:
                tried += 1
                try:
                    col = [fn(a, b) if m else None for a, b, m in zip(c1, c2, mask)]
                except ZeroDivisionError:
                    continue
                if all(a == b for a, b, m in zip(col, target, mask) if m):
                    return '(%s %s %s)' % (op, t1, t2), tried
    return None, tried


def extra_residual_difference(y, u):
    """Type-specific 'Y minus U'.  int: y - u.  list: element-wise when the lengths
    agree, else None (undefined: the kernel then prices a change of length)."""
    if isinstance(y, int) and isinstance(u, int):
        return y - u
    if isinstance(y, tuple) and isinstance(u, tuple) and len(y) == len(u):
        return tuple(a - b for a, b in zip(y, u))
    return None


def extra_residual_to_positions(space, col):
    """Change of space: one row per (row, position) of a list column."""
    return [dict(row=i, pos=j, v=v) for i, row in enumerate(space) if row[col] is not None
            for j, v in enumerate(row[col])]


def kernel_int_bits(d):
    """The kernel's integer correction code (codec.lisp emit-positive on ast.lisp
    signed-code): Elias-delta of 2d+1 (d >= 0) or -2d (d < 0).  0 -> 1 bit, +-1 -> 4,
    2..3 -> 5, 4 -> 8, 1000 -> 17 (plan_v2c.md L585 quotes 0,4,5,5,8 and 17; it prices an
    exact cell at 0, which rule 5 of plan section 6.2 says must be at least 1)."""
    v = 2 * d + 1 if d >= 0 else -2 * d
    w = v.bit_length()
    lw = w.bit_length()
    return (lw - 1) + lw + (w - 1)


def extra_residual_guard(space, agree, guard_pool):
    """A guard for the rows where U and Y disagree: g true exactly on the agreeing rows,
    or exactly on the disagreeing ones."""
    out = []
    for name, fn in guard_pool:
        g = [bool(fn(row)) for row in space]
        if g == agree:
            out.append('(if %s U ?else)' % name)
        elif g == [not a for a in agree]:
            out.append('(if %s ?else U)' % name)
    return out


def loc(fn):
    src = inspect.getsource(fn).split('\n')
    body, in_doc = 0, False
    for ln in src[1:]:
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        if s.startswith('"""'):
            if not (s.count('"""') == 2):
                in_doc = not in_doc
            continue
        if in_doc:
            if s.endswith('"""'):
                in_doc = False
            continue
        body += 1
    return body + 1


def main():
    rng = random.Random(0)
    print('=' * 100)
    print('A.  ONE ROUTINE: residual(space, A_columns, B_column, qA, qB)   (%d lines)' % loc(residual))
    print('=' * 100)

    # ------------------------------------------------------------ (1) law
    print('\n(1) LAW (q = identity, residual 0)')
    S = [dict(x=a, y=b, z=c) for a, b, c in zip(rng.sample(range(-9, 10), 8), rng.sample(range(-9, 10), 8),
                                                 rng.sample(range(-9, 10), 8))]
    for row in S:
        row['x*(y+z)'] = row['x'] * (row['y'] + row['z'])
        row['x*y+x*z'] = row['x'] * row['y'] + row['x'] * row['z']
        row['x+1'] = row['x'] + 1
        row['x*x'] = row['x'] * row['x']
    r = residual(S, ['x*(y+z)'], 'x*y+x*z')
    show('B = x*y+x*z  given A = x*(y+z)', r, 'identity table: %s' % extra_law_is_identity(r))
    r = residual(S, ['x'], 'x+1')
    show('B = x+1      given A = x', r, 'identity table: %s  <- zero residual, NOT a law'
         % extra_law_is_identity(r))
    r = residual(S, ['x'], 'x*x')
    show('B = x*x      given A = x', r, 'identity table: %s  <- zero residual, NOT a law'
         % extra_law_is_identity(r))
    r = residual(S, ['y'], 'x*x')
    show('B = x*x      given A = y (unrelated)', r, '<- zero residual: the 8 y values are distinct')
    print('  (dl = %.1f bits against %.1f unconditioned: with one row per key the "table" is as long as the '
          'column; zero conditional entropy is not compression)' % (r['dl_bits'], r['dl_free']))
    # the form the store actually uses: one group-by on the TERM space, key = the whole column
    P = [dict(x=rng.randint(-9, 9), y=rng.randint(-9, 9), z=rng.randint(-9, 9)) for _ in range(8)]
    leaves = [(n, tuple(row[n] for row in P)) for n in 'xyz'] + [('0', (0,) * 8), ('1', (1,) * 8)]
    ops = [('+', 2, lambda a, b: a + b), ('*', 2, lambda a, b: a * b), ('neg', 1, lambda a: -a)]
    T = extra_law_enumerate(leaves, ops, 5, P)
    r = residual(T, ['col'], 'term')
    classes = [c for c in r['counts'].values() if len(c) > 1]
    print('  term space {+ * neg} over x y z 0 1 to size 5: %d terms, %d distinct columns' % (r['n'], r['groups']))
    show('B = term name given A = its column', r)
    print('  -> %d classes with more than one term (%d terms in them): these are the laws; '
          'here a law is a POSITIVE residual (a collision), e.g.' % (len(classes), r['undet']))
    ex = sorted(classes, key=lambda c: (len(c), sorted(c)))
    for c in [e for e in ex if any('y' in t and 'x' in t for t in e)][:3]:
        print('       ' + '  =  '.join(sorted(c, key=len)[:3]))

    # ------------------------------------------------------------ (2) inverse
    print('\n(2) INVERSE (q = identity, A = (b, c), B = a; residual 0 on a sub-space)')
    G = [dict(a=a, b=b) for a in range(-6, 7) for b in range(-6, 7)]
    gpool = [('(= b 0)', lambda r: r['b'] == 0), ('(not (= b 0))', lambda r: r['b'] != 0),
             ('(< b 0)', lambda r: r['b'] < 0), ('(< 0 b)', lambda r: r['b'] > 0),
             ('(= c 0)', lambda r: r['c'] == 0), ('(not (= c 0))', lambda r: r['c'] != 0),
             ('(< c 0)', lambda r: r['c'] < 0), ('(< 0 c)', lambda r: r['c'] > 0),
             ('(= b c)', lambda r: r['b'] == r['c']), ('(not (= b c))', lambda r: r['b'] != r['c']),
             ('(< b c)', lambda r: r['b'] < r['c']), ('(< c b)', lambda r: r['c'] < r['b']),
             ('(= b 1)', lambda r: r['b'] == 1)]
    wops = [('+', lambda a, b: a + b), ('-', lambda a, b: a - b), ('*', lambda a, b: a * b),
            ('div', lambda a, b: a // b)]
    for opname, fn in [('+', lambda a, b: a + b), ('*', lambda a, b: a * b), ('max', max)]:
        for row in G:
            row['c'] = fn(row['a'], row['b'])
        r = residual(G, ['b', 'c'], 'a')
        det = [len(r['counts'][(row['b'], row['c'])]) == 1 for row in G]
        show('c = (%s a b):  B = a given A = (b, c)' % opname, r,
             'determined on %.1f%%' % (100 * sum(det) / len(G)))
        if opname == 'max':
            # the boundary artifact reported in plan 8.2: widen the range of a when grouping
            Gw = [dict(a=a, b=b, c=max(a, b)) for a in range(-12, 13) for b in range(-6, 7)]
            rw = residual(Gw, ['b', 'c'], 'a')
            detw = [len(rw['counts'][(row['b'], row['c'])]) == 1 for row in G]
            print('      with a widened to -12..12 when grouping: determined on %.1f%% of the same 169 rows '
                  '(plan 8.2: 46.2%%); the difference is a false dependency at the grid boundary'
                  % (100 * sum(detw) / len(G)))
            det = detw
        if all(det):
            w, tried = extra_inverse_witness(G, [row['a'] for row in G], det, ['b', 'c'], wops)
            print('      total; witness search over {+ - * div} on b, c: %s after %d candidates' % (w, tried))
        else:
            valid, weakest = extra_inverse_guard(G, det, gpool)
            print('      guard: %d of %d pool guards valid; weakest: %s' % (len(valid), len(gpool),
                                                                         [n for n, _ in weakest]))
            if weakest:
                gm = weakest[0][1]
                w, tried = extra_inverse_witness(G, [row['a'] for row in G], gm, ['b', 'c'], wops)
                print('      witness on the guarded rows: %s after %d candidates' % (w, tried))
    print('  plan_v2c.md 8.2 reports for *: dependency on 92.3%, guard (not (= b 0)), inverse (div c b).')

    # ------------------------------------------------------------ (3) computed residual
    print('\n(3) COMPUTED RESIDUAL (q = identity, A = candidate U, B = target Y)')
    def mk(rg):
        rows = [dict(x=rg.randint(-9, 9), y=rg.randint(-9, 9)) for _ in range(8)]
        for row in rows:
            row['Y'] = 2 * row['x'] * row['x'] + 1
            row['U'] = 2 * row['x'] * row['x']
            row['W'] = 2 * row['y'] * row['y']
            row['V'] = row['y'] + row['x'] * 100
            row['R_U'] = extra_residual_difference(row['Y'], row['U'])
            row['R_W'] = extra_residual_difference(row['Y'], row['W'])
        return rows
    R = mk(random.Random(5))
    print('  Y = 2*x*x + 1;  near miss U = 2*x*x;  unrelated W = 2*y*y;  V = y + 100*x (a far-off term);  8 rows')
    show('as the review states it: B = Y given A = U', residual(R, ['U'], 'Y'))
    show('                         B = Y given A = W', residual(R, ['W'], 'Y'))
    show('                         B = Y given A = V', residual(R, ['V'], 'Y'),
         '<- kernel code L(Y|V) = %d bits' % sum(kernel_int_bits(row['Y'] - row['V']) for row in R))
    mc = random.Random(7)
    z = Counter()
    for _ in range(2000):
        Rm = mk(mc)
        for k in 'UWV':
            z[k] += residual(Rm, [k], 'Y')['undet'] == 0
    print('  over 2,000 random 8-row spaces (x, y in -9..9) the identity group-by reports ZERO residual for '
          'U in %.0f%%, for W in %.0f%%, for V in %.0f%%' % (z['U'] / 20, z['W'] / 20, z['V'] / 20))
    print('  -> with q = identity, "Y is a function of U" holds for any candidate whose values are distinct on the')
    print('     rows; it does not measure nearness.  (On the 61-operator library: see b12_report.log, B1.)')
    print('  after the type-specific difference R = Y - U (an operation OUTSIDE the routine):')
    r = residual(R, [], 'R_U')
    show('B = Y - U, no A columns', r, 'table %s -> propose (+ U %d)' % (r['table'], r['table'][()]))
    show('B = Y - W, no A columns', residual(R, [], 'R_W'))
    print('  kernel integer code, row by row:  L(Y|U) = %d bits,  L(Y|W) = %d bits,  L(Y) alone = %d bits'
          % (sum(kernel_int_bits(row['R_U']) for row in R), sum(kernel_int_bits(row['R_W']) for row in R),
             sum(kernel_int_bits(row['Y']) for row in R)))
    # conditional: Y = (if (< x 0) 0 (* x x)), U = x*x
    C = [dict(x=x) for x in (-7, -4, -2, -1, 0, 3, 5, 8)]
    for row in C:
        row['Y'] = 0 if row['x'] < 0 else row['x'] * row['x']
        row['U'] = row['x'] * row['x']
        row['agree'] = row['Y'] == row['U']
    cpool = [('(< x 0)', lambda r: r['x'] < 0), ('(< 0 x)', lambda r: r['x'] > 0),
             ('(= x 0)', lambda r: r['x'] == 0), ('(even x)', lambda r: r['x'] % 2 == 0),
             ('(< x 1)', lambda r: r['x'] < 1), ('(< 1 x)', lambda r: r['x'] > 1)]
    print('  Y = (if (< x 0) 0 (* x x));  near miss U = x*x;  rows agree: %s' % [int(r_['agree']) for r_ in C])
    show('B = Y given A = U (identity)', residual(C, ['U'], 'Y'), '<- 0: says nothing of the split')
    for name, fn in cpool:
        for row in C:
            row['g'] = bool(fn(row))
        r = residual(C, ['g'], 'agree')
        if r['undet'] == 0:
            show('B = agreement mask given A = %s' % name, r, '<- determined: a guard')
    print('  proposals:', extra_residual_guard(C, [row['agree'] for row in C], cpool))
    # sequences: the difference needs a second space
    Q = [dict(xs=tuple(rng.randint(-9, 9) for _ in range(rng.randint(2, 6)))) for _ in range(8)]
    for row in Q:
        row['U'] = tuple(sorted(row['xs']))
        row['Y'] = tuple(v + 3 for v in row['U'])
        row['R'] = extra_residual_difference(row['Y'], row['U'])
        row['Yt'] = row['U'][1:]
        row['Rt'] = extra_residual_difference(row['Yt'], row['U'])
    print('  sequences: Y = add_k(3, sort(xs)), U = sort(xs), list lengths %s' % [len(r_['xs']) for r_ in Q])
    show('B = Y - U (a list per row), no A, row space', residual(Q, [], 'R'),
         '<- not constant: the lengths differ')
    show('B = element of Y - U, no A, POSITION space', residual(extra_residual_to_positions(Q, 'R'), [], 'v'),
         '<- constant 3: propose add_k(3, U)')
    print('  Y = tail(sort(xs)), U = sort(xs): element-wise Y - U is %s (undefined: the lengths differ)'
          % Q[0]['Rt'])

    # ------------------------------------------------------------ (4) exact congruence
    print('\n(4) EXACT CONGRUENCE (q a quotient, residual 0)')
    m5 = lambda v: v % 5
    G2 = [dict(a=a, b=b) for a in range(-12, 13) for b in range(-12, 13)]
    for opname, fn in [('+', lambda a, b: a + b), ('-', lambda a, b: a - b), ('*', lambda a, b: a * b),
                       ('div', lambda a, b: a // b if b else 0), ('max', max)]:
        for row in G2:
            row['c'] = fn(row['a'], row['b'])
        r = residual(G2, ['a', 'b'], 'c', [m5, m5], m5)
        show('c = (%s a b), q = mod 5 on a, b and c' % opname, r,
             ('table of %d entries, e.g. (3,4)->%s' % (len(r['table']), r['table'][(3, 4)]))
             if r['table'] else 'not a congruence')

    # ------------------------------------------------------------ (5) soft verb table
    print('\n(5) SOFT VERB TABLE (q a quotient, residual positive)')
    prng = random.Random(0)
    pools = make_pools(prng, 2000, 'iid')
    probes = eval_probes(prng, pools, 2000)
    tb = Tables([Q_PARITY, Q_SIGN, Q_CAPLEN], pools, probes)
    lab = {0: 'E', 1: 'EV', 2: 'OD', 3: 'M'}
    for op in ('dbl_all', 'inc_all', 'filter_pos', 'sort', 'map_adj_add', 'take3'):
        for j, q in enumerate([Q_PARITY, Q_SIGN, Q_CAPLEN]):
            idx, res = probes[op]
            V = [dict(x=pools[L][k], fx=v) for (k,), v in zip(idx, res)]
            r = residual(V, ['x'], 'fx', [q.f[L]], q.f[L])
            same = {k: dict(c) for k, c in r['counts'].items()} == {k: dict(c) for k, c in tb.tab[j][op].items()}
            show('%-11s q = %-7s' % (op, q.name), r, 'same table as seqlib.Tables: %s' % same)
            if op == 'filter_pos' and q is Q_PARITY:
                for k in sorted(r['counts']):
                    print('        %-3s -> %s' % (lab[k[0]], {lab[v]: n for v, n in sorted(r['counts'][k].items())}))

    # ------------------------------------------------------------ what is shared, what is not
    print('\n' + '=' * 100)
    print('LINES OF CODE: the shared routine and what each regime needs beyond it')
    print('=' * 100)
    rows = [('shared routine residual()', loc(residual), 'all five regimes call it unchanged'),
            ('(1) law: identity-table test', loc(extra_law_is_identity),
             'zero residual is "B is a function of A"; a law also needs the table to be the identity'),
            ('(1) law: term enumerator', loc(extra_law_enumerate),
             'the group-by runs on the TERM space (key = whole column), not on the row space'),
            ('(2) inverse: guard from a pool', loc(extra_inverse_guard),
             'plus the guard pool itself (enumerated Boolean terms) and the grid design (padding)'),
            ('(2) inverse: witness search', loc(extra_inverse_witness),
             'the routine returns the table (b,c)->a, i.e. the specification; the term is a search'),
            ('(3) residual: Y minus U', loc(extra_residual_difference),
             'type-specific; undefined when list lengths differ'),
            ('(3) residual: to the position space', loc(extra_residual_to_positions),
             'a constant offset on lists of varying length is constant only per position'),
            ('(3) residual: integer code', loc(kernel_int_bits),
             'L(R) is a code length on values, not an entropy of a group-by'),
            ('(3) residual: guard for the disagreeing rows', loc(extra_residual_guard),
             'plus the guard pool; then a separate problem for ?else'),
            ('(4) congruence', 0, 'nothing; choosing q is a separate search (verify-quotients: 19 s)'),
            ('(5) soft verb table', 0, 'nothing; probe design (count, edge cases) is outside the routine')]
    for name, n, note in rows:
        print('  %-44s %3d lines   %s' % (name, n, note))


if __name__ == '__main__':
    main()
