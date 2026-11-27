"""Q5 (outline reproduction): (a) verb-class synonyms from Jaccard overlap of the
pushed-forward tables; (b) cross-task reuse on 20 sequential 3-operator tasks
with disjoint inputs.

(b) task stream: 9 base programs (random 3-operator unary chains), 5 REPEATS of
earlier programs on fresh inputs, 6 SIBLINGS (an earlier program with one
operator replaced by another member of a HAND-listed family -- so that a
sibling hit tests whether the Jaccard synonyms recover the hand families).
Methods, all falling back to the Q2 abstract-table search (cost counted):
   A  abstract-table search alone
   B  replay every previously solved program first (no index)
   C  replay only programs stored under the same all-row Boolean signature
   D  C, then one-operator synonym variants (top-4 Jaccard neighbours of the
      same type) of the programs in the bucket
   E  B, then one-operator synonym variants of ALL previous programs
A replayed program costs one candidate per operator application.

usage: python3 q5_reuse.py [--seed 0]
"""
import argparse
import random

from seqlib import (L, I, OPS, OPNAMES, OPSIG, OPFN, HAND6, build_tables, term_str, term_ops,
                    eval_term, make_inputs, nondegenerate, random_term)
from q2search import plain_search, pruned_search, soft_counts, signature

ap = argparse.ArgumentParser()
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--seeds', type=int, default=5)
A = ap.parse_args()

tb = build_tables(HAND6, M=2000, kind='iid', seed=0)

# ------------------------------------------------------------ (a) synonyms
supp = {}
for name in OPNAMES:
    s = set()
    for j in range(len(tb.q)):
        for key, c in tb.tab[j][name].items():
            for v in c:
                s.add((j, key, v))
    supp[name] = s


def jacc(a, b):
    return len(supp[a] & supp[b]) / len(supp[a] | supp[b])


def neighbours(name, k=None, same_type=True):
    out = [(jacc(name, o), o) for o in OPNAMES if o != name and (not same_type or OPSIG[o] == OPSIG[name])]
    out.sort(reverse=True)
    return out[:k] if k else out


print('# Q5 (a): operator neighbours by Jaccard overlap of table supports (6 quotients, 2000 probes)')
REVIEW = {'map_adj_sub': 'map_adj_mul .61, map_adj_add .61, map_adj_min .53, map_adj_max .53',
          'filter_pos': 'filter_neg .57, filter_odd .45, filter_even .41',
          'zip_add': 'zip_sub .74, zip_max .69, zip_min .68, zip_mul .66 (concat .07)',
          'sum': 'head .61, last .51, min_el .47, max_el .43'}
for name in ('map_adj_sub', 'filter_pos', 'zip_add', 'sum', 'sort', 'inc_all', 'dbl_all'):
    nb = neighbours(name, 6)
    print('  %-12s ~ %s' % (name, ', '.join('%s %.2f' % (o, j) for j, o in nb)))
    if name in REVIEW:
        print('  %-12s   review: %s' % ('', REVIEW[name]))
print('  zip_add vs concat: %.2f' % jacc('zip_add', 'concat'))

FAM = [['map_adj_add', 'map_adj_sub', 'map_adj_mul', 'map_adj_min', 'map_adj_max'],
       ['filter_pos', 'filter_neg', 'filter_even', 'filter_odd'],
       ['inc_all', 'dec_all', 'dbl_all', 'neg_all', 'abs_all', 'sq_all', 'half_all'],
       ['sum', 'head', 'last', 'min_el', 'max_el'],
       ['sort', 'sort_desc', 'reverse'],
       ['running_sum', 'running_max', 'running_min'],
       ['zip_add', 'zip_sub', 'zip_mul', 'zip_min', 'zip_max']]
famof = {o: i for i, f in enumerate(FAM) for o in f}
print('\n  recovery of the hand-listed families by the top-k same-type neighbours:')
for k in (1, 2, 4):
    tot = hit = 0
    for f in FAM:
        for o in f:
            nb = [x for _, x in neighbours(o, k)]
            want = min(k, len(f) - 1)
            hit += sum(1 for x in nb if famof.get(x) == famof[o])
            tot += want
    print('     top-%d: %d of %d neighbour slots are family members (%.0f%%)' % (k, hit, tot, 100.0 * hit / tot))


# ------------------------------------------------------------ (b) reuse
def subst(t, pos, new):
    """Replace the operator at depth `pos` of a unary chain."""
    if pos == 0:
        return (new,) + t[1:]
    return (t[0], subst(t[1], pos - 1, new))


def run_stream(seed, verbose):
    rng = random.Random(seed)
    unary = [n for n in OPNAMES if len(OPSIG[n][0]) == 1]
    base = []
    while len(base) < 9:
        t = random_term(rng, 3, unary, p_ys=0.0, max_size=4)
        if t is None or term_str(t) in [term_str(b) for b in base]:
            continue
        if not any(o in famof for o in term_ops(t)):
            continue
        base.append(t)
    stream = [('base', t, None) for t in base]
    for t in rng.sample(base, 5):
        stream.append(('repeat', t, t))
    sib = 0
    while sib < 6:
        t = rng.choice(base)
        pos = [i for i, o in enumerate(term_ops(t)) if o in famof]
        i = rng.choice(pos)
        old = term_ops(t)[i]
        new = rng.choice([o for o in FAM[famof[old]] if o != old])
        t2 = subst(t, i, new)
        if term_str(t2) in [term_str(s[1]) for s in stream]:
            continue
        stream.append(('sibling', t2, t))
        sib += 1
    # originals first, then repeats and siblings in random order
    tail = stream[9:]
    rng.shuffle(tail)
    stream = stream[:9] + tail
    solved = []            # (signature, program)
    cost = {m: 0 for m in 'ABCDE'}
    hits = {m: {'repeat': 0, 'sibling': 0, 'base': 0} for m in 'BCDE'}
    sigstable = 0
    for k, (kind, t, parent) in enumerate(stream):
        env = None
        for tries in range(100):
            env = make_inputs(random.Random(seed * 7919 + k * 101 + tries), ['xs'])
            if nondegenerate(t, env):
                break
        target = eval_term(t, env)
        ty = OPSIG[t[0]][1]
        ps = plain_search(env, target, 4)
        pr = pruned_search(env, target, ty, tb, ps['found_size'])
        sc = soft_counts(pr['last'], pr['ctx'])
        a = pr['cum_before'] + pr['last']['below'] + sc['op_soft']
        sig = signature(env, target, ty)
        if kind == 'repeat':
            sigstable += any(s == sig and term_str(p) == term_str(t) for s, p in solved)

        def try_programs(progs):
            c = 0
            for p in progs:
                c += len(term_ops(p))
                if OPSIG[p[0]][1] == ty and eval_term(p, env) == target:
                    return c, True
            return c, False

        def variants(progs):
            out = []
            seen = set()
            for p in progs:
                ops = term_ops(p)
                for i, o in enumerate(ops):
                    for _, n in neighbours(o, 4):
                        v = subst(p, i, n)
                        s = term_str(v)
                        if s not in seen:
                            seen.add(s)
                            out.append(v)
            return out
        allp = [p for _, p in solved]
        bucket = [p for s, p in solved if s == sig]
        cb, hb = try_programs(allp)
        cc, hc = try_programs(bucket)
        cd, hd = (cc, hc)
        if not hd:
            x, hd = try_programs(variants(bucket))
            cd += x
        ce, he = (cb, hb)
        if not he:
            x, he = try_programs(variants(allp))
            ce += x
        cost['A'] += a
        for m, c, h in (('B', cb, hb), ('C', cc, hc), ('D', cd, hd), ('E', ce, he)):
            cost[m] += c + (0 if h else a)
            if h:
                hits[m][kind] += 1
        if verbose:
            print('   %2d %-8s %-44s abs %6d | B %s%4d  C %s%4d  D %s%4d  E %s%4d' %
                  (k + 1, kind, term_str(t), a, '+' if hb else ' ', cb, '+' if hc else ' ', cc,
                   '+' if hd else ' ', cd, '+' if he else ' ', ce))
        solved.append((sig, t))
    return cost, hits, sigstable


print('\n# Q5 (b): 20 sequential 3-operator tasks, disjoint inputs (seed %d); + marks a hit, numbers are'
      ' replay candidates' % A.seed)
cost, hits, st = run_stream(A.seed, True)
print('\n   totals (candidates):', cost)
print('   hits:', hits, ' repeats whose signature matched the original: %d of 5' % st)
print('\n   over %d random streams:' % A.seeds)
print('   %5s %9s | %-22s %-22s %-22s %-22s | sig-stable repeats' % ('seed', 'A', 'B', 'C', 'D', 'E'))
tot = {m: 0 for m in 'ABCDE'}
th = {m: 0 for m in 'BCDE'}
for s in range(A.seeds):
    cost, hits, st = run_stream(100 + s, False)
    for m in cost:
        tot[m] += cost[m]
    cells = []
    for m in 'BCDE':
        h = hits[m]['repeat'] + hits[m]['sibling'] + hits[m]['base']
        th[m] += h
        cells.append('%4.2fx %2d hits (%dr %ds)' % (cost['A'] / cost[m], h, hits[m]['repeat'], hits[m]['sibling']))
    print('   %5d %9d | %-22s %-22s %-22s %-22s | %d/5' % (100 + s, cost['A'], *cells, st))
print('   pooled gain over A:  ' + '  '.join('%s %.2fx (%d/%d hits)' % (m, tot['A'] / tot[m], th[m], 20 * A.seeds)
                                           for m in 'BCDE'))
print('   (11 hits out of 20 equal-cost tasks would by itself give 20/9 = 2.22x)')
