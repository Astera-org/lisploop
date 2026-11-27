# Recount the reviewer's EXP C per pair (a pair is rejected if ANY quotient rejects it),
# with the same seed and tables as exp_devils_advocate.py run_exp_c().
import random
from collections import Counter, defaultdict
vals = list(range(-12, 13))
g2 = {
    '+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b,
    'max': lambda a, b: max(a, b), 'min': lambda a, b: min(a, b),
    'div': lambda a, b: None if b == 0 else a // b,
    'mod': lambda a, b: None if b == 0 else a % b,
}
doms = {'mod2': lambda v: v % 2, 'mod3': lambda v: v % 3,
        'sign': lambda v: -1 if v < 0 else (1 if v > 0 else 0)}
def build_tbl(slice_only):
    tbl = {}
    for dn, dfn in doms.items():
        tbl[dn] = {}
        for opn, fn in g2.items():
            tr = defaultdict(set)
            bs = (-1, 0, 1, 2) if slice_only else vals
            for a in vals:
                for b in bs:
                    o = fn(a, b)
                    if o is not None:
                        tr[(dfn(a), dfn(b))].add(dfn(o))
            tbl[dn][opn] = tr
    return tbl
t_slice = build_tbl(True)
rng = random.Random(404)
checks = Counter(); rej_checks = Counter(); pairs = Counter(); rej_pairs = Counter()
for _ in range(500):
    a, b = rng.randint(-20, 20), rng.randint(-20, 20)
    for opn, fn in g2.items():
        o = fn(a, b)
        if o is None:
            continue
        pairs[opn] += 1
        anyrej = False
        for dn, dfn in doms.items():
            checks[opn] += 1
            s = t_slice[dn][opn].get((dfn(a), dfn(b)))
            if s is not None and dfn(o) not in s:
                rej_checks[opn] += 1
                anyrej = True
        if anyrej:
            rej_pairs[opn] += 1
for opn in g2:
    print('%-4s checks rejected %3d of %4d | pairs with a defined result %3d, rejected by at least one quotient %3d'
          % (opn, rej_checks[opn], checks[opn], pairs[opn], rej_pairs[opn]))
