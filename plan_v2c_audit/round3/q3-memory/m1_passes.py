"""Per-bound detail of policy R + (c) on two targets: how the bank grows from one bound to the
next (classes cut at bound N that are kept at bound N+1), and what each pass costs."""
import random

from q3lib import Domain, pick_rows
from memlib import Labeller, one_pass, kept_map

rng = random.Random(0)
xs = tuple(rng.randint(-9, 9) for _ in range(32))
ys = tuple(rng.randint(-9, 9) for _ in range(32))
leaves = [('x', xs), ('y', ys), ('0', tuple([0] * 32)), ('1', tuple([1] * 32))]
leaf_cols = [c for _, c in leaves]
DOM = [Domain(2, list(range(12)), leaf_cols), Domain(3, pick_rows(xs, ys, 3, 4), leaf_cols),
       Domain(5, pick_rows(xs, ys, 5, 3), leaf_cols)]
for d in DOM:
    d.forward([d.ids[d.alpha(c)] for c in leaf_cols])

for name, fn, ns in [('A8', lambda x, y: (x + y) ** 2 - x * y + 1, 11),
                     ('A12', lambda x, y: 2 * (x * x + y * y) - x * y, 13)]:
    target = tuple(fn(x, y) for x, y in zip(xs, ys))
    ids = [d.ids[d.alpha(target)] for d in DOM]
    hs = [d.backward(i) for d, i in zip(DOM, ids)]
    nmin = max(d.g[i] for d, i in zip(DOM, ids))
    lab = Labeller(DOM, hs)
    prev = {}
    print('%s (true size %d, tables\' lower bound %d)' % (name, ns, nmin))
    print('   %3s %10s %8s %22s %26s' % ('N', 'evaluated', 'bank', 'new since last bound',
                                         'of them cut at last bound'))
    for N in range(nmin, ns + 1):
        r = one_pass(leaves, target, N, lab, 'pre', keep=True)
        k = kept_map(r)
        new = [c for c in k if c not in prev]
        # a class is "cut at the last bound" if it was derivable there (size < N-1) but failed the test
        was_cut = [c for c in new if k[c] < N - 1]
        print('   %3d %10d %8d %22d %26d   hit=%s' % (N, r['evaluated'], len(k), len(new), len(was_cut), r['hit']))
        assert all(prev[c] == k[c] for c in prev if c in k) and all(c in k for c in prev)
        prev = k
    # classes per size: plain against the last pass of (c)
    rp = one_pass(leaves, target, ns, None, 'plain', keep=True)
    print('   classes per size 1..%d, plain: %s' % (ns - 1, [len(rp['levels'][s]) for s in range(1, ns)]))
    print('   classes per size 1..%d, (c)  : %s' % (ns - 1, [len(r['levels'][s]) for s in range(1, ns)]))
    top = len(rp['levels'][ns - 1])
    print('   plain with the top stored size (%d) as hashes: %d full classes instead of %d (%.2fx)' %
          (ns - 1, rp['seen_n'] - top, rp['seen_n'], rp['seen_n'] / (rp['seen_n'] - top)))
