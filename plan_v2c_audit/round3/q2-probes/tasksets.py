"""Task sets for the probe study (deterministic given seeds).

S300   : the 300 random 3-4 operator tasks of verify-quotients q2_sound.py
         (gen_tasks(300, 900)).
S300b  : a second draw of 300 (seed 901).
EDGE-R : 200 random tasks built like the reviewer's EXP D: row 0 of every input
         is replaced by one of the reviewer's five structured rows.
EDGE-W : 200 random tasks whose row 0 is a structured row from a WIDER family of
         templates (below), written by me after the probe rules were fixed; it
         tests whether a zero is specific to the reviewer's five rows.
"""
import random

from seqlib import (OPNAMES, term_ops, term_size, term_leaves, term_str, term_type, eval_term,
                    make_inputs, random_term, nondegenerate)
from q2tasks import gen_tasks, _rename, HELD_OUT

REVIEWER_ROWS = [(3, 3, 3, 1), (2, 4, 6, 8), (0, 0, 0), (5, 4, 3, 2), (-2, -2, -1)]


def reviewer_row(rng):
    return rng.choice(REVIEWER_ROWS)


def wide_row(rng):
    """One structured list of length 2..7 from ten templates."""
    n = rng.randint(2, 7)
    k = rng.randrange(10)
    c = rng.randint(-9, 9)
    if k == 0:                                   # constant
        return (c,) * n
    if k == 1:                                   # plateau, then non-increasing
        p = rng.randint(2, max(2, n - 1))
        rest = sorted((rng.randint(-9, c) for _ in range(n - p)), reverse=True)
        return (c,) * p + tuple(rest)
    if k == 2:                                   # plateau, then non-decreasing
        p = rng.randint(2, max(2, n - 1))
        rest = sorted(rng.randint(c, 9) for _ in range(n - p))
        return (c,) * p + tuple(rest)
    if k == 3:                                   # zeros with one non-zero element
        i = rng.randrange(n)
        v = rng.choice([x for x in range(-9, 10) if x])
        return tuple(v if j == i else 0 for j in range(n))
    if k == 4:                                   # no positive element, some zeros
        return tuple(rng.choice([0, 0, -rng.randint(1, 9)]) for _ in range(n))
    if k == 5:                                   # arithmetic progression
        d = rng.choice([-3, -2, -1, 1, 2, 3])
        a = rng.randint(-4, 4)
        return tuple(a + d * j for j in range(n))
    if k == 6:                                   # all even, one sign
        s = rng.choice([-1, 1])
        return tuple(s * 2 * rng.randint(0, 4) for _ in range(n))
    if k == 7:                                   # all odd, one sign
        s = rng.choice([-1, 1])
        return tuple(s * (2 * rng.randint(0, 4) + 1) for _ in range(n))
    if k == 8:                                   # two values alternating
        b = rng.randint(-9, 9)
        return tuple(c if j % 2 == 0 else b for j in range(n))
    return tuple(rng.choice([c, c, rng.randint(-9, 9)]) for _ in range(n))   # mostly one value


def instantiate_edge(name, term, seed, rowgen, rows=8):
    names = sorted(set(term_leaves(term)))
    for k in range(200):
        rng = random.Random(seed * 1000 + k)
        env = make_inputs(rng, names, rows=rows)
        env = {n: (rowgen(rng),) + col[1:] for n, col in env.items()}
        if nondegenerate(term, env):
            return dict(name=name, term=term, env=env, target=eval_term(term, env),
                        ttype=term_type(term), size=term_size(term), ops=term_ops(term),
                        cold=[o for o in term_ops(term) if o in HELD_OUT])
    return None


def gen_edge_tasks(n, seed, rowgen, prefix, n_ops_choices=(3, 4), max_size=5, rows=8, p_ys=0.3):
    rng = random.Random(seed)
    out = []
    seen = set()
    tries = 0
    while len(out) < n and tries < 200000:
        tries += 1
        t = random_term(rng, rng.choice(n_ops_choices), OPNAMES, max_size=max_size, p_ys=p_ys)
        if t is None:
            continue
        t = _rename(t)
        s = term_str(t)
        if s in seen:
            continue
        task = instantiate_edge('%s%d' % (prefix, len(out) + 1), t, rng.randrange(10 ** 6),
                                rowgen, rows=rows)
        if task is None:
            continue
        seen.add(s)
        out.append(task)
    return out


def get_tasks(name, n=None):
    if name == 'S300':
        return gen_tasks(n or 300, 900, OPNAMES, prefix='S')
    if name == 'S300b':
        return gen_tasks(n or 300, 901, OPNAMES, prefix='Sb')
    if name == 'EDGE-R':
        return gen_edge_tasks(n or 200, 910, reviewer_row, 'ER')
    if name == 'EDGE-W':
        return gen_edge_tasks(n or 200, 920, wide_row, 'EW')
    if name.startswith('RAND'):          # RAND<seed>: big random stream for audits
        return gen_tasks(n or 3000, int(name[4:]), OPNAMES, prefix='R')
    if name.startswith('EDGER'):
        return gen_edge_tasks(n or 1000, int(name[5:]), reviewer_row, 'ER')
    if name.startswith('EDGEW'):
        return gen_edge_tasks(n or 1000, int(name[5:]), wide_row, 'EW')
    raise ValueError(name)
