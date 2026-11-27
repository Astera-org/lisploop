"""P4: joint probes vs fixed-argument ("isolate") slices for two-argument operators.
Own code; nothing imported from the reviewer.

  A. dependency scores on parity: joint vs slice b = 1..4 (review: div 0.04 / 1.00 at
     b=1; mod 0.53 / 1.00 at b=2,4), on three grids.
  B. false rejections of label-keyed tables built from slices b in {-1,0,1,2} against
     the joint grid (review: 55 +, 50 -, 287 div, 422 mod of 500 fresh pairs; 0 joint):
     same seed as the reviewer, 20 other seeds, the exact expectation over the whole
     41x41 test grid, per quotient; then OTHER slice sets (200 random 4-subsets) and a
     joint table at the SAME budget (100 random pairs).
  C. the sharper question: a table keyed on (label of a, VALUE of b).  Is it sound,
     what does it add over the joint label-keyed table, what does it cost.

usage: python3 p4_slices.py > p4_slices.log
"""
import math
import random
from collections import Counter, defaultdict

OPS = {
    '+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b,
    'max': max, 'min': min,
    'div': lambda a, b: None if b == 0 else a // b,
    'mod': lambda a, b: None if b == 0 else a % b,
}
QS = {'mod2': lambda v: v % 2, 'mod3': lambda v: v % 3,
      'sign': lambda v: (v > 0) - (v < 0)}


def H(c):
    n = sum(c.values())
    return -sum(v / n * math.log2(v / n) for v in c.values() if v) if n else 0.0


def dep(pairs):
    """dependency score 1 - H(out | key) / H(out) of a list of (key, out)."""
    hy = H(Counter(y for _, y in pairs))
    if hy < 1e-12:
        return float('nan')
    by = defaultdict(Counter)
    for k, y in pairs:
        by[k][y] += 1
    hc = sum(sum(c.values()) / len(pairs) * H(c) for c in by.values())
    return 1 - hc / hy


def table(op, q, pairs):
    t = defaultdict(set)
    for a, b in pairs:
        o = op(a, b)
        if o is not None:
            t[(q(a), q(b))].add(q(o))
    return t


def false_rej(tabs, tests):
    """per operator: number of (pair, quotient) checks whose key is in the table
    and whose true output label is not."""
    out = Counter()
    per_q = Counter()
    for opn, op in OPS.items():
        for a, b in tests:
            o = op(a, b)
            if o is None:
                continue
            for qn, q in QS.items():
                s = tabs[(opn, qn)].get((q(a), q(b)))
                if s is not None and q(o) not in s:
                    out[opn] += 1
                    per_q[(opn, qn)] += 1
    return out, per_q


def build(pairs):
    return {(opn, qn): table(op, q, pairs) for opn, op in OPS.items() for qn, q in QS.items()}


def main():
    print('A. dependency score on parity (x mod 2): joint key (a%2, b%2) vs slice key (a%2) at fixed b')
    for G in (12, 20, 30):
        vals = range(-G, G + 1)
        print('  grid [-%d, %d]^2' % (G, G))
        for opn in ('+', '*', 'div', 'mod'):
            op = OPS[opn]
            j = dep([((a % 2, b % 2), op(a, b) % 2) for a in vals for b in vals
                     if op(a, b) is not None])
            sl = []
            for b0 in (1, 2, 3, 4, -1, 5, 6):
                s = dep([((a % 2,), op(a, b0) % 2) for a in vals])
                sl.append('b=%d:%s' % (b0, 'const' if s != s else '%.2f' % s))
            print('    %-4s joint %.2f | slices %s' % (opn, j, ' '.join(sl)))
    print('  joint parity table of mod on [-12,12]^2 (key -> output labels): %s' %
          {k: sorted(v) for k, v in sorted(table(OPS['mod'], QS['mod2'],
                                                 [(a, b) for a in range(-12, 13)
                                                  for b in range(-12, 13)]).items())})
    print('  joint parity table of div: %s' %
          {k: sorted(v) for k, v in sorted(table(OPS['div'], QS['mod2'],
                                                 [(a, b) for a in range(-12, 13)
                                                  for b in range(-12, 13)]).items())})

    vals = list(range(-12, 13))
    grid = [(a, b) for a in vals for b in vals]
    t_joint = build(grid)
    t_slice = build([(a, b) for a in vals for b in (-1, 0, 1, 2)])
    print('\nB. false rejections, label-keyed tables from slices b in {-1,0,1,2} (a in [-12,12]) '
          'vs the joint 25x25 grid; test pairs in [-20,20]^2; 3 quotients, so <= 1500 checks per 500 pairs')
    rng = random.Random(404)                      # the reviewer's seed and draw order
    tests = [(rng.randint(-20, 20), rng.randint(-20, 20)) for _ in range(500)]
    fs, fq = false_rej(t_slice, tests)
    fj, _ = false_rej(t_joint, tests)
    full = [(a, b) for a in range(-20, 21) for b in range(-20, 21)]
    es, eq = false_rej(t_slice, full)
    ej, _ = false_rej(t_joint, full)
    seeds = []
    for sd in range(20):
        r = random.Random(1000 + sd)
        tt = [(r.randint(-20, 20), r.randint(-20, 20)) for _ in range(500)]
        seeds.append(false_rej(t_slice, tt)[0])
    print('  %-4s %14s %12s %22s %22s   %s' % ('op', 'slice seed404', 'joint 404', 'slice 20 seeds min..max',
                                                'exact per 500 (slice/joint)', 'slice by quotient (seed 404)'))
    for opn in OPS:
        xs = [s[opn] for s in seeds]
        print('  %-4s %14d %12d %14d..%-6d %14.1f / %-5.1f   %s' %
              (opn, fs[opn], fj[opn], min(xs), max(xs), es[opn] * 500 / len(full),
               ej[opn] * 500 / len(full),
               {qn: fq[(opn, qn)] for qn in QS}))

    print('\n  other slice sets: 200 random 4-subsets of b in [-12,12]; false rejections per 500 '
          'test pairs (exact over the 41x41 grid): median [min..max]; and share of subsets with zero')
    r = random.Random(77)
    by = defaultdict(list)
    for _ in range(200):
        bs = r.sample(vals, 4)
        t = build([(a, b) for a in vals for b in bs])
        f, _ = false_rej(t, full)
        for opn in OPS:
            by[opn].append(f[opn] * 500 / len(full))
    for opn in OPS:
        xs = sorted(by[opn])
        print('    %-4s median %6.1f [%5.1f..%6.1f]  zero in %3d/200' %
              (opn, xs[len(xs) // 2], xs[0], xs[-1], sum(1 for x in xs if x == 0)))
    print('\n  joint probing at the SAME budget as the 4 slices (100 random pairs in [-12,12]^2), '
          '200 seeds: false rejections per 500 (exact): median [min..max], share with zero')
    by = defaultdict(list)
    for sd in range(200):
        r = random.Random(5000 + sd)
        t = build([(r.choice(vals), r.choice(vals)) for _ in range(100)])
        f, _ = false_rej(t, full)
        for opn in OPS:
            by[opn].append(f[opn] * 500 / len(full))
    for opn in OPS:
        xs = sorted(by[opn])
        print('    %-4s median %6.1f [%5.1f..%6.1f]  zero in %3d/200' %
              (opn, xs[len(xs) // 2], xs[0], xs[-1], sum(1 for x in xs if x == 0)))

    print('\nC. table keyed on (label of a, VALUE of b), b in [-12,12], a probed on [-A, A]')
    print('  truth = all a in [-200,200].  joint = key (label a, label b) on the 25x25 grid.')
    print('  narrower = value-keyed entries with strictly fewer output labels than the joint entry '
          'for the same (label a, label b); det = entries with one output label;')
    print('  unsound(A) = value-keyed entries, probed with a in [-A,A], that miss a true output label')
    wide = range(-200, 201)
    print('  %-4s %-5s | %7s %5s | %7s %5s %8s | %-28s | %10s %10s' %
          ('op', 'quot', 'joint', 'det', 'value', 'det', 'narrower', 'b values where narrower',
           'unsound12', 'unsound40'))
    tot = Counter()
    for opn, op in OPS.items():
        for qn, q in QS.items():
            tj = t_joint[(opn, qn)]
            truth = defaultdict(set)
            for b in vals:
                for a in wide:
                    o = op(a, b)
                    if o is not None:
                        truth[(q(a), b)].add(q(o))
            narrower = [k for k, s in truth.items() if len(s) < len(tj[(k[0], q(k[1]))])]
            nb = sorted({k[1] for k in narrower})
            uns = {}
            for A in (12, 40):
                tv = defaultdict(set)
                for b in vals:
                    for a in range(-A, A + 1):
                        o = op(a, b)
                        if o is not None:
                            tv[(q(a), b)].add(q(o))
                uns[A] = sum(1 for k, s in truth.items() if k in tv and not s <= tv[k])
            dj = sum(1 for s in tj.values() if len(s) == 1)
            dv = sum(1 for s in truth.values() if len(s) == 1)
            tot.update(joint=len(tj), jdet=dj, value=len(truth), vdet=dv, narrower=len(narrower),
                       u12=uns[12], u40=uns[40])
            print('  %-4s %-5s | %7d %5d | %7d %5d %8d | %-28s | %10d %10d' %
                  (opn, qn, len(tj), dj, len(truth), dv, len(narrower),
                   str(nb)[:28], uns[12], uns[40]))
    print('  TOTAL      | %7d %5d | %7d %5d %8d | %-28s | %10d %10d' %
          (tot['joint'], tot['jdet'], tot['value'], tot['vdet'], tot['narrower'], '',
           tot['u12'], tot['u40']))
    print('\n  the review\'s example "x mod 2k is determined by x mod 2": joint parity key (a%2, b%2=0) '
          'of mod is already deterministic (see A); the value-keyed table adds nothing there.')

    # one operator of the 61-operator library where the VALUE of an int argument matters
    print('\n  take_n(n, xs) under caplen5 = min(len, 5) (the int side of that quotient is trivial):')
    r = random.Random(3)
    lj = defaultdict(set)
    lv = defaultdict(set)
    for _ in range(20000):
        n = r.randint(-3, 9)
        xs = tuple(r.randint(-9, 9) for _ in range(r.randint(0, 9)))
        out = xs[:n] if n > 0 else ()
        lj[(0, min(len(xs), 5))].add(min(len(out), 5))
        lv[(max(0, min(n, 5)), min(len(xs), 5))].add(min(len(out), 5))
    print('    label-keyed: %d entries, %d deterministic, %.2f output labels per entry' %
          (len(lj), sum(1 for s in lj.values() if len(s) == 1),
           sum(map(len, lj.values())) / len(lj)))
    print('    keyed on (clamp(n,0,5), caplen5 xs): %d entries, %d deterministic' %
          (len(lv), sum(1 for s in lv.values() if len(s) == 1)))


if __name__ == '__main__':
    main()
