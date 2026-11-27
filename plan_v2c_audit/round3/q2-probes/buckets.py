"""How many buckets does rejection sampling reach?

Buckets of lists under the six quotients: single (quotient, label) and pairs
(two quotients, two labels).  'exist' = reached by an exhaustive enumeration of
all lists of length <= 6 over [-2,2] plus length <= 10 over [-1,1].
For each candidate source and candidate count C: buckets reached, and the
buckets that exist but were not reached.

usage: python3 buckets.py > buckets.log
"""
import random

from seqlib import L, HAND6
from probegen import tuple_sampler
from tabletools import all_lists

QN = [q.name for q in HAND6]
FS = [q.f[L] for q in HAND6]


def buckets(vals):
    one, two = set(), set()
    for v in vals:
        labs = [f(v) for f in FS]
        for j in range(6):
            one.add((j, labs[j]))
            for k in range(j + 1, 6):
                two.add((j, k, labs[j], labs[k]))
    return one, two


def main():
    ex = list(dict.fromkeys(all_lists(6, 2) + all_lists(10, 1)))
    e1, e2 = buckets(ex)
    print('exist (exhaustive scope, %d lists): %d single buckets, %d pair buckets' %
          (len(ex), len(e1), len(e2)))
    print('%-9s %8s | %6s %6s | %s' % ('source', 'C', 'single', 'pairs', 'pair buckets that exist but were not reached'))
    for src in ('iid', 'push2', 'bank2', 'oelog3', 'scalemix'):
        draw = tuple_sampler(src)
        for C in (2000, 20000, 200000):
            rng = random.Random(5)
            vals = [draw(rng, (L,))[0] for _ in range(C)]
            b1, b2 = buckets(vals)
            miss = sorted(e2 - b2)
            txt = ', '.join('%s=%s&%s=%s' % (QN[j], a, QN[k], b) for j, k, a, b in miss[:6])
            print('%-9s %8d | %6d %6d | %d: %s%s' %
                  (src, C, len(b1), len(b2), len(miss), txt, ' ...' if len(miss) > 6 else ''))
            extra = b2 - e2
            if extra:
                print('%-9s %8s   (reaches %d pair buckets outside the exhaustive scope)' %
                      ('', '', len(extra)))


if __name__ == '__main__':
    main()
