"""Shared harness: cached plain search, table-filtered search under many table
configurations, reference-path audit, summaries.

A LOSS (miss) = the table-filtered search does not find the target at the size
at which plain search finds it (same definition as verify-quotients q2_sound.py).
A DEFECT = on the reference program's own path, an input-label key the probes
DID see with an output label they did not ("seen input, unseen output").
"""
import math
import multiprocessing as mp
import os
import pickle
import random
import time

from seqlib import OPSIG, subterms, eval_term, term_str
from q2search import plain_search, expected_random_order, pruned_search

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache')

_TASKS = []
_PLAIN = []
_CONFIGS = {}


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


# ------------------------------------------------------------------ plain search (cached)
def _plain_job(ti):
    task = _TASKS[ti]
    rng = random.Random(4242 + ti)
    ps = plain_search(task['env'], task['target'], task['size'])
    ns = ps['found_size']
    lv = ps['levels'][ns - 1]
    return dict(found_size=ns,
                plain_rand=ps['below'] + expected_random_order(lv['n'], lv['hit'], rng, 200),
                plain_full=ps['below'] + ps['final_total'], plain_store=ps['store_below'],
                wall=ps['wall_s'])


def plain_cached(setname, tasks, procs=14):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, 'plain_%s_%d.pkl' % (setname, len(tasks)))
    if os.path.exists(path):
        with open(path, 'rb') as f:
            names, res = pickle.load(f)
        if names == [term_str(t['term']) for t in tasks]:
            return res
    _TASKS[:] = tasks
    with mp.get_context('fork').Pool(procs) as pool:
        res = pool.map(_plain_job, range(len(tasks)), chunksize=1)
    with open(path, 'wb') as f:
        pickle.dump(([term_str(t['term']) for t in tasks], res), f)
    return res


# ------------------------------------------------------------------ reference path
def ref_transitions(term, env, quotients):
    """All (opname, quotient index, input-label key, output label) used by the
    reference program on its rows."""
    out = set()
    for (u, d) in subterms(term):
        if isinstance(u, str):
            continue
        name = u[0]
        at, rt = OPSIG[name]
        args = [eval_term(a, env) for a in u[1:]]
        res = eval_term(u, env)
        for j, q in enumerate(quotients):
            fa = [q.f[t] for t in at]
            fr = q.f[rt]
            for r in range(len(res)):
                key = tuple(fa[i](args[i][r]) for i in range(len(at)))
                out.add((name, j, key, fr(res[r])))
    return out


def defects(trans, tables):
    """The reference transitions the tables wrongly exclude."""
    bad = []
    for (name, j, key, ar) in trans:
        c = tables.tab[j][name].get(key)
        if c is not None and ar not in c:
            bad.append((name, j, key, ar))
    return bad


# ------------------------------------------------------------------ filtered search
def search_one(task, pl, tb, seed, trials=200):
    rng = random.Random(seed)
    ns = pl['found_size']
    pr = pruned_search(task['env'], task['target'], task['ttype'], tb, ns)
    last = pr['last']
    r = dict(found=pr['found'], store=last['store_below'], store_j1=last['store_joint1'])
    if pr['found']:
        r['abs_rand'] = (pr['cum_before'] + last['below'] +
                         expected_random_order(last['fin_n'], last['fin_hit'], rng, trials))
    return r


def _cfg_job(ti):
    task, pl = _TASKS[ti], _PLAIN[ti]
    out = {}
    tcache = {}
    for cname, tb in _CONFIGS.items():
        r = search_one(task, pl, tb, 4242 + ti)
        qk = id(tb.q)
        tr = tcache.get(qk)
        if tr is None:
            tr = tcache[qk] = ref_transitions(task['term'], task['env'], tb.q)
        r['defects'] = defects(tr, tb)
        out[cname] = r
    return out


def run_configs(tasks, plain, configs, procs=14):
    """configs: name -> tables.  Returns a list (per task) of name -> result."""
    _TASKS[:] = tasks
    _PLAIN[:] = plain
    _CONFIGS.clear()
    _CONFIGS.update(configs)
    with mp.get_context('fork').Pool(procs) as pool:
        return pool.map(_cfg_job, range(len(tasks)), chunksize=1)


def summarize(cname, tasks, plain, res):
    rs = [(pl, r[cname]) for pl, r in zip(plain, res)]
    ok = [(pl, c) for pl, c in rs if c['found']]
    lost = [t['name'] for t, r in zip(tasks, res) if not r[cname]['found']]
    aud = sum(1 for pl, c in rs if c['defects'])
    dset = set()
    for pl, c in rs:
        dset.update(c['defects'])
    lost_clean = [t['name'] for t, r in zip(tasks, res)
                  if not r[cname]['found'] and not r[cname]['defects']]
    return dict(n=len(rs), miss=len(rs) - len(ok), lost=lost, aud=aud, ndefect=len(dset),
                lost_clean=lost_clean,
                gain=gmean([pl['plain_rand'] / c['abs_rand'] for pl, c in ok]),
                store=gmean([pl['plain_store'] / max(1, c['store']) for pl, c in ok]),
                store_j1=gmean([pl['plain_store'] / max(1, c['store_j1']) for pl, c in ok]))
