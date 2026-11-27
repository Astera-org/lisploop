"""Task sets for Q2 (deterministic given seeds)."""
import random

from seqlib import (L, I, OPNAMES, OPSIG, parse, term_ops, term_size, term_leaves, term_str,
                    term_type, eval_term, make_inputs, random_term, nondegenerate, subterms)

HELD_OUT = ('map_adj_sub', 'dbl_all')

REVIEW_TASKS = [
    ('T1', 'sum(map_adj_sub(sort(xs)))'),
    ('T3', 'sum(zip_mul(xs, shift1(xs)))'),
    ('T4', 'sum(filter_pos(zip_sub(xs, ys)))'),
    ('T5', 'len(filter_even(map_adj_add(xs)))'),
    ('T6', 'running_sum(reverse(inc_all(xs)))'),
    ('T8', 'dbl_all(sort(abs_all(xs)))'),
    ('T9', 'sort(dbl_all(filter_pos(map_adj_add(xs))))'),
    ('T10', 'dbl_all(sort(abs_all(map_adj_sub(xs))))'),
]


def _rename(t):
    """If a term uses only ys, call it xs."""
    if 'xs' in term_leaves(t):
        return t

    def r(u):
        if isinstance(u, str):
            return 'xs'
        return (u[0],) + tuple(r(a) for a in u[1:])
    return r(t)


def instantiate(name, term, seed, rows=8):
    """Random example rows for a term; retries seeds until the task is non-degenerate."""
    names = sorted(set(term_leaves(term)))
    for k in range(200):
        rng = random.Random(seed * 1000 + k)
        env = make_inputs(rng, names, rows=rows)
        if nondegenerate(term, env):
            return dict(name=name, term=term, env=env, target=eval_term(term, env),
                        ttype=term_type(term), size=term_size(term), ops=term_ops(term),
                        cold=[o for o in term_ops(term) if o in HELD_OUT])
    return None


def gen_tasks(n, seed, opnames, n_ops_choices=(3, 4), max_size=5, require=None, prefix='G',
              exclude=(), rows=8, p_ys=0.3):
    """n random non-degenerate pipeline tasks.  `require`: an operator that must occur."""
    rng = random.Random(seed)
    out = []
    seen = set(exclude)
    tries = 0
    while len(out) < n and tries < 200000:
        tries += 1
        t = random_term(rng, rng.choice(n_ops_choices), opnames, max_size=max_size, p_ys=p_ys)
        if t is None:
            continue
        t = _rename(t)
        if require is not None and require not in term_ops(t):
            continue
        s = term_str(t)
        if s in seen:
            continue
        task = instantiate('%s%d' % (prefix, len(out) + 1), t, rng.randrange(10 ** 6), rows=rows)
        if task is None:
            continue
        seen.add(s)
        out.append(task)
    return out


def review_tasks(seed=1):
    return [instantiate(n, parse(s), seed + k) for k, (n, s) in enumerate(REVIEW_TASKS)]


def training_tasks(n=80, seed=100):
    ops = [o for o in OPNAMES if o not in HELD_OUT]
    return gen_tasks(n, seed, ops, prefix='TR')


def my_tasks(seed=200, exclude=()):
    """A dozen more: 8 from the full library (whatever comes), 2 forced to contain
    map_adj_sub and 2 forced to contain dbl_all (cold-start operators)."""
    out = gen_tasks(8, seed, OPNAMES, prefix='M', exclude=exclude)
    ex = set(exclude) | {term_str(t['term']) for t in out}
    a = gen_tasks(2, seed + 1, OPNAMES, require='map_adj_sub', prefix='Ma', exclude=ex)
    ex |= {term_str(t['term']) for t in a}
    b = gen_tasks(2, seed + 2, OPNAMES, require='dbl_all', prefix='Md', exclude=ex)
    return out + a + b
