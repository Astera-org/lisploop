"""Fact-check helper (exploratory, NOT part of the audited record): rerun the Q5 stream with the index
key swapped from the 23 hand-written Boolean properties (q2search.signature) to all-row quotient labels
(what the review's third change describes).  Copy of q5_reuse.py's run_stream with a pluggable key."""
import random
from seqlib import (L, I, OPNAMES, OPSIG, HAND6, build_tables, term_str, term_ops, eval_term,
                    make_inputs, nondegenerate, random_term)
from q2search import plain_search, pruned_search, soft_counts, signature

tb = build_tables(HAND6, M=2000, kind='iid', seed=0)
FAM = [['map_adj_add', 'map_adj_sub', 'map_adj_mul', 'map_adj_min', 'map_adj_max'],
       ['filter_pos', 'filter_neg', 'filter_even', 'filter_odd'],
       ['inc_all', 'dec_all', 'dbl_all', 'neg_all', 'abs_all', 'sq_all', 'half_all'],
       ['sum', 'head', 'last', 'min_el', 'max_el'],
       ['sort', 'sort_desc', 'reverse'],
       ['running_sum', 'running_max', 'running_min'],
       ['zip_add', 'zip_sub', 'zip_mul', 'zip_min', 'zip_max']]
famof = {o: i for i, f in enumerate(FAM) for o in f}

def subst(t, pos, new):
    if pos == 0:
        return (new,) + t[1:]
    return (t[0], subst(t[1], pos - 1, new))

def sig_flat(env, target, ty):
    return signature(env, target, ty)

def sig_labels(env, target, ty):
    """all-row quotient labels: per quotient, the label of xs and of the output if constant over rows, else None"""
    out = [ty]
    for q in HAND6:
        a = {q.f[L](x) for x in env['xs']}
        b = {q.f[ty](y) for y in target}
        out.append((next(iter(a)) if len(a) == 1 else None, next(iter(b)) if len(b) == 1 else None))
    return tuple(out)

def sig_labels_out(env, target, ty):
    """same, output labels only"""
    out = [ty]
    for q in HAND6:
        b = {q.f[ty](y) for y in target}
        out.append(next(iter(b)) if len(b) == 1 else None)
    return tuple(out)

def run_stream(seed, keyfn):
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
    tail = stream[9:]
    rng.shuffle(tail)
    stream = stream[:9] + tail
    solved = []
    rep_hits_B = rep_hits_C = 0
    maxB = 0
    for k, (kind, t, parent) in enumerate(stream):
        env = None
        for tries in range(100):
            env = make_inputs(random.Random(seed * 7919 + k * 101 + tries), ['xs'])
            if nondegenerate(t, env):
                break
        target = eval_term(t, env)
        ty = OPSIG[t[0]][1]
        sig = keyfn(env, target, ty)
        def try_programs(progs):
            c = 0
            for p in progs:
                c += len(term_ops(p))
                if OPSIG[p[0]][1] == ty and eval_term(p, env) == target:
                    return c, True
            return c, False
        cb, hb = try_programs([p for _, p in solved])
        cc, hc = try_programs([p for s, p in solved if s == sig])
        maxB = max(maxB, cb)
        if kind == 'repeat':
            rep_hits_B += hb
            rep_hits_C += hc
        solved.append((sig, t))
    return rep_hits_B, rep_hits_C, maxB

for nm, fn in (('23 hand-written Boolean properties (as run)', sig_flat),
               ('all-row quotient labels, input+output', sig_labels),
               ('all-row quotient labels, output only', sig_labels_out)):
    tb_, tc_, mx = 0, 0, 0
    per = []
    for s in range(5):
        b, c, m = run_stream(100 + s, fn)
        tb_ += b; tc_ += c; mx = max(mx, m); per.append(c)
    print('%-46s repeats found: replay-all %d/25, index %d/25 %s; max replay cost per task %d candidates' % (nm, tb_, tc_, per, mx))
