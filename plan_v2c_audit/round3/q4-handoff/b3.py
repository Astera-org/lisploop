"""Experiment B3 (claim U2, stage 3 as a mechanism): tasks WITH a near miss.

  python3 b3.py offscale --seed 21 --n 96 --out b3_os_s21.json
        answer = U + c or c * U for a pipeline U of 2-3 library operators (element-wise on lists)
  python3 b3.py ifsplit  --seed 31 --n 60 --out b3_if_s31.json
        answer = (if g U V), U and V pipelines of 2 operators, g a guard on a reduction of xs
  python3 b3.py spurious b12_s11.json --out b3_sp_s11.json
        the ordinary tasks of b12.py: do the residual proposals fire, and are the splits they find real?
  python3 b3.py report b3_os_s21.json b3_if_s31.json b3_sp_s11.json ...

Search arms for offset / scale tasks (candidates = operator evaluations over all rows):
  A  plain search; the needed constant operator is IN the grammar (62 operators)   [favourable baseline]
  B  label-filtered search, same 62-operator grammar and its tables                 [labels only]
  C  plain search over the 61 operators + residual check on every stored class      [residual only]
  D  label-filtered search over the 61 operators + residual check on every class that
     SURVIVES the filter (the review's stage 2 -> stage 3 order)
  D2 as D, but the residual check sees every evaluated candidate (before the label test)
  E  as B (62 operators) + residual check on every surviving class
A residual check is one pass over the rows (about the cost of one evaluation); it is counted separately.
"""
import argparse
import json
import math
import random
import sys
import time
from collections import Counter, defaultdict
from multiprocessing import Pool

from hlib import (L, I, OPS, OPSIG, OPFN, BASE61, BASE61_SET, ORACLE, AbsCtx, Bank, run_plain, tables_for,
                  col_dl, col_l1, col_residual, regularity, const_offset, const_scale, residual_proposal,
                  pct_rank, gmean, mean, median, boot_ci, expected_random_order, eval_term, subterms,
                  term_str, term_ops, term_size, term_type, pruned_pass_hook, make_inputs, INF)
import q2search
import q2tasks
from seqlib import random_term, nondegenerate, parse

PREDS = [('pos', lambda v: v > 0), ('neg', lambda v: v < 0), ('even', lambda v: v % 2 == 0),
         ('zero', lambda v: v == 0)]
PREDF = dict(PREDS)
CMPS = [('lt', lambda a, b: a < b), ('eq', lambda a, b: a == b)]
CMPF = dict(CMPS)


# =================================================================== offset / scale
def gen_offscale(n, seed):
    rng = random.Random(seed)
    out, seen, tries = [], set(), 0
    keys = sorted(k for k in ORACLE if k[2] == L)
    while len(out) < n and tries < 100000:
        tries += 1
        fam, c, _ = keys[len(out) % len(keys)]
        u = random_term(rng, rng.choice((2, 3)), list(BASE61), max_size=4, p_ys=0.3)
        if u is None:
            continue
        u = q2tasks._rename(u)
        term = (ORACLE[(fam, c, term_type(u))], u)
        s = term_str(term)
        if s in seen:
            continue
        task = q2tasks.instantiate('N%d' % (len(out) + 1), term, rng.randrange(10 ** 6))
        if task is None:
            continue
        # U must be a real near miss: not constant, not the target
        seen.add(s)
        task.update(fam=fam, c=c, oracle=term[0], uterm=u)
        out.append(task)
    return out


def rank_block(bank, pool, i, target):
    """Ranks (1 = best) of class i in pool under several orders."""
    dl = {j: col_dl(bank.cols[j], target) for j in pool}
    l1 = {j: col_l1(bank.cols[j], target) for j in pool}
    reg, simple = {}, {}
    for j in pool:
        Rc = col_residual(bank.cols[j], target)
        reg[j] = regularity(Rc, bank.ty[j])
        simple[j] = Rc is not None and (residual_proposal(bank.cols[j], target) is not None or Rc in bank.idx)

    def rk(key):
        k = key(i)
        return 1 + sum(1 for j in pool if key(j) < k), sum(1 for j in pool if key(j) == k) - 1
    out = dict(pool=len(pool), reg=reg[i], frac_reg3=sum(1 for j in pool if reg[j] == 3) / len(pool),
               n_simple=sum(simple.values()), simple=simple[i], l1_def=l1[i] is not None)
    out['rank_dl'], out['ties_dl'] = rk(lambda j: dl[j])
    out['rank_l1'], _ = rk(lambda j: (l1[j] is None, l1[j] or 0))
    out['rank_reg_dl'], _ = rk(lambda j: (-reg[j], dl[j]))
    out['rank_reg3_dl'], _ = rk(lambda j: (reg[j] != 3, dl[j]))
    out['rank_simple_dl'], _ = rk(lambda j: (not simple[j], dl[j]))
    return out


def work_offscale(task):
    t0 = time.perf_counter()
    env, Y, ty, term = task['env'], task['target'], task['ttype'], task['term']
    ns = task['size']
    ucol = eval_term(task['uterm'], env)
    ops62 = BASE61_SET | {task['oracle']}
    rng = random.Random(1)
    out = dict(name=task['name'], term=term_str(term), fam=task['fam'], c=task['c'], ttype=ty, size=ns,
               inputs=len(env))
    # A: plain, constant operator in the grammar
    ps = q2search.plain_search(env, Y, ns, opnames=ops62)
    nsA = ps['found_size']
    lv = ps['levels'][nsA - 1]
    out['nsA'] = nsA
    out['A'] = ps['below'] + expected_random_order(lv['n'], lv['hit'], rng, 200)
    # B: labels, same grammar
    T62 = tables_for(tuple(BASE61) + (task['oracle'],), 2000, 'iid', 0)
    pr = q2search.pruned_search(env, Y, ty, T62, nsA, opnames=ops62)
    last = pr['last']
    out['B_found'] = pr['found']
    out['B'] = pr['cum_before'] + last['below'] + (
        expected_random_order(last['fin_n'], last['fin_hit'], rng, 200) if pr['found'] else sum(last['fin_n']))
    # the residual hook
    state = dict(checks=0, fired=None)

    def hook(col, t, j=None):
        if t != ty:
            return False
        state['checks'] += 1
        p = residual_proposal(col, Y)
        if p is not None:
            state['fired'] = (p, col == ucol)
            return True
        return False
    # C: plain 61 + residual on every stored class
    bank = Bank(env, BASE61_SET)
    fired = None
    for i in range(len(bank.cols)):
        if hook(bank.cols[i], bank.ty[i]):
            fired = bank.evaluated
    s = 1
    while fired is None and s < ns:
        s += 1
        r = bank.level(s, Y, store=True, hook=hook)
        fired = r['hook_at']
    out['C'] = fired
    out['C_checks'] = state['checks']
    out['C_fired'] = state['fired']
    out['C_level'] = s
    # D, D2: labels over the 61 operators (no constant operator), residual on survivors / on everything
    T61 = tables_for(BASE61, 2000, 'iid', 0)
    ctx61 = AbsCtx(T61, Y, ty)
    out['hU'] = ctx61.ah[ctx61.abstract(ucol, ty)]
    for arm, hall in (('D', False), ('D2', True)):
        state.update(checks=0, fired=None)
        cum = 0
        res = None
        for N in range(1, ns + 2):
            r = pruned_pass_hook(env, Y, N, ctx61, BASE61_SET, hook=hook, hook_all=hall, stop_after=ns - 1)
            if r['fired'] is not None:
                res = cum + r['fired']
                out[arm + '_pass'] = N
                break
            cum += r['evaluated']
        out[arm] = res
        out[arm + '_spent'] = cum
        out[arm + '_checks'] = state['checks']
    # E: labels with the constant operator in the grammar + residual on survivors
    ctx62 = AbsCtx(T62, Y, ty)
    state.update(checks=0, fired=None)
    cum = 0
    res = None
    for N in range(1, nsA + 1):
        r = pruned_pass_hook(env, Y, N, ctx62, ops62, hook=hook)
        if r['fired'] is not None:
            res = cum + r['fired']
            out['E_how'] = 'residual'
            break
        if r['hit']:
            fn = r.get('fin_n') or []
            res = cum + r['evaluated'] - sum(fn) + (expected_random_order(fn, r['fin_hit'], rng, 200)
                                                    if fn and any(h >= 0 for h in r['fin_hit']) else sum(fn))
            out['E_how'] = 'search'
            break
        cum += r['evaluated']
    out['E'] = res
    out['E_checks'] = state['checks']
    # ranking of the near miss among the classes of its level and type (complete plain bank)
    full = Bank(env, BASE61_SET)
    for s in range(2, ns):
        full.level(s, Y, store=True)
    i = full.idx.get(ucol)
    if i is not None:
        pool = full.lev[full.ty[i]][full.size[i]]
        out['rank'] = rank_block(full, pool, i, Y)
        out['rank']['level'] = full.size[i]
    out['t'] = time.perf_counter() - t0
    return out


# =================================================================== conditionals
def guard_bank(bank, R, max_int_level=3):
    """Smallest guard term per distinct non-constant row mask.  Guards: pos / neg / even /
    zero of an int class of size <= max_int_level; lt / eq of two int classes of size 2."""
    FULL = (1 << R) - 1
    G = {}
    n = 0
    for s in range(2, max_int_level + 1):
        for i in bank.lev[I].get(s, []):
            col = bank.cols[i]
            for pn, pf in PREDS:
                n += 1
                m = sum(1 << r for r, v in enumerate(col) if pf(v))
                if m in (0, FULL):
                    continue
                if m not in G or G[m][0] > s + 1:
                    G[m] = (s + 1, (pn, i))
    i2 = bank.lev[I].get(2, [])
    for a in i2:
        for b in i2:
            if a == b:
                continue
            for cn, cf in CMPS:
                n += 1
                m = sum(1 << r for r, (x, y) in enumerate(zip(bank.cols[a], bank.cols[b])) if cf(x, y))
                if m in (0, FULL):
                    continue
                if m not in G or G[m][0] > 5:
                    G[m] = (5, (cn, a, b))
    return G, n


def eval_guard(gt, bank, env):
    if gt[0] in PREDF:
        return [PREDF[gt[0]](v) for v in eval_term(bank.term(gt[1]), env)]
    return [CMPF[gt[0]](a, b) for a, b in zip(eval_term(bank.term(gt[1]), env), eval_term(bank.term(gt[2]), env))]


def guard_str(gt, bank):
    return '%s(%s)' % (gt[0], ', '.join(term_str(bank.term(i)) for i in gt[1:]))


def split_search(bank, ids, target, G):
    """The stage-3 split proposal: for each class its agreement mask with the target
    (rows where it is already right); a guard g, a class right on the rows of g and a
    class right on the other rows make (if g U V).  Returns the smallest fitting split,
    all splits of that size, the number of fitting triples, and the classes examined."""
    R = len(target)
    FULL = (1 << R) - 1
    bym = defaultdict(list)
    for i in ids:
        col = bank.cols[i]
        m = 0
        for r in range(R):
            if col[r] == target[r]:
                m |= 1 << r
        if m and m != FULL:
            bym[m].append(i)
    nfit = 0
    sols = []
    for g, (gs, gt) in G.items():
        ng = FULL & ~g
        us = [i for m, lst in bym.items() if m & g == g for i in lst]
        if not us:
            continue
        vs = [i for m, lst in bym.items() if m & ng == ng for i in lst]
        if not vs:
            continue
        nfit += len(us) * len(vs)
        for u in us:
            for v in vs:
                sols.append((1 + gs + bank.size[u] + bank.size[v], gs, u, v, g))
    if not sols:
        return None, [], 0, sum(len(v) for v in bym.values())
    sols.sort()
    best = sols[0]
    return best, [s for s in sols if s[0] == best[0]][:300], nfit, sum(len(v) for v in bym.values())


def eval_split(sol, bank, G, env):
    _, _, u, v, g = sol
    gc = eval_guard(G[g][1], bank, env)
    uc = eval_term(bank.term(u), env)
    vc = eval_term(bank.term(v), env)
    return tuple(a if c else b for c, a, b in zip(gc, uc, vc))


def gen_if(n, seed):
    rng = random.Random(seed)
    out, tries = [], 0
    while len(out) < n and tries < 200000:
        tries += 1
        ty = rng.choice((L, L, I))
        u = random_term(rng, 2, list(BASE61), want=ty, p_ys=0.0, max_size=3)
        v = random_term(rng, 2, list(BASE61), want=ty, p_ys=0.0, max_size=3)
        if u is None or v is None or u == v:
            continue
        gi = rng.choice([o[0] for o in OPS if o[0] in BASE61_SET and o[1] == (L,) and o[2] == I])
        pn = rng.choice([p[0] for p in PREDS])
        env = make_inputs(random.Random(rng.randrange(10 ** 6)), ['xs'], rows=8)
        uc, vc = eval_term(u, env), eval_term(v, env)
        gc = [PREDF[pn](x) for x in eval_term((gi, 'xs'), env)]
        if not 2 <= sum(gc) <= 6:
            continue
        if any(a == b for a, b in zip(uc, vc)) or len(set(uc)) < 3 or len(set(vc)) < 3:
            continue
        if not (nondegenerate(u, env) and nondegenerate(v, env)):
            continue
        y = tuple(a if c else b for c, a, b in zip(gc, uc, vc))
        env2 = make_inputs(random.Random(rng.randrange(10 ** 6)), ['xs'], rows=64)
        g2 = [PREDF[pn](x) for x in eval_term((gi, 'xs'), env2)]
        y2 = tuple(a if c else b for c, a, b in zip(g2, eval_term(u, env2), eval_term(v, env2)))
        out.append(dict(name='IF%d' % (len(out) + 1), u=u, v=v, guard=(pn, gi), env=env, target=y, ttype=ty,
                        env2=env2, target2=y2, gmask=sum(1 << r for r, c in enumerate(gc) if c)))
    return out


def label_rowmask(ctx, col, ty, ttype):
    """Rows on which all six labels of the class equal those of the target."""
    if ty != ttype:
        return 0
    a = ctx.abstract(col, ty)
    ids = ctx.aids[a]
    m = (1 << len(col)) - 1
    for j in range(ctx.nq):
        for r, (x, t) in enumerate(zip(ctx.vecs[j][ids[j]], ctx.tvec[j])):
            if x != t:
                m &= ~(1 << r)
    return m


def count_cover(masks, FULL):
    """Number of ordered pairs of masks whose union is all rows."""
    c = Counter(masks)
    return sum(a * b for m1, a in c.items() for m2, b in c.items() if m1 | m2 == FULL)


def work_if(task):
    t0 = time.perf_counter()
    env, Y, ty = task['env'], task['target'], task['ttype']
    R = len(Y)
    FULL = (1 << R) - 1
    out = dict(name=task['name'], ttype=ty, u=term_str(task['u']), v=term_str(task['v']),
               guard='%s(%s(xs))' % task['guard'])
    bank = Bank(env, BASE61_SET)
    found = None
    first = None
    spent = len(env)
    for s in (2, 3, 4):
        r = bank.level(s, Y, store=True)
        spent += r['total']
        if r['hits'] or Y in bank.idx:
            out['plain_solved_at'] = s
        G, ng = guard_bank(bank, R)
        ids = [i for i in range(len(bank.cols)) if bank.ty[i] == ty]
        best, mins, nfit, nmask = split_search(bank, ids, Y, G)
        if best is not None and first is None:
            gens = [eval_split(sol, bank, G, task['env2']) == task['target2'] for sol in mins]
            first = dict(level=s, total_size=best[0], n_fit=nfit, n_min=len(mins), min_generalize=sum(gens),
                         first_generalizes=gens[0], candidates=spent, classes_examined=len(ids),
                         guard_terms=ng, guard_masks=len(G), nonzero_masks=nmask,
                         split='(if %s %s %s)' % (guard_str(G[best[4]][1], bank), term_str(bank.term(best[2])),
                                                 term_str(bank.term(best[3]))))
        if s == 3:
            # the planted program, and what enumeration of `if` as an operator would face
            uc, vc = eval_term(task['u'], env), eval_term(task['v'], env)
            iu, iv = bank.idx.get(uc), bank.idx.get(vc)
            out['planted_in_bank'] = iu is not None and iv is not None and task['gmask'] in G
            T61 = tables_for(BASE61, 2000, 'iid', 0)
            ctx = AbsCtx(T61, Y, ty)
            out['hU'] = ctx.ah[ctx.abstract(uc, ty)]
            out['hV'] = ctx.ah[ctx.abstract(vc, ty)]
            # the review's order: stage 3 sees only the classes that survive the stage-2 label filter.
            # Cost of the deepening passes until BOTH planted branches are stored (guards not required).
            need = 3 + max(1, out['hU'], out['hV'])
            if need <= 6:
                got = set()

                def hk(col, t, _uc=uc, _vc=vc):
                    if col == _uc or col == _vc:
                        got.add(col)
                    return False
                cum = 0
                for N in range(1, need + 1):
                    rr = pruned_pass_hook(env, Y, N, AbsCtx(T61, Y, ty), BASE61_SET, hook=hk,
                                          stop_after=3 if N == need else None)
                    cum += rr['evaluated']
                out['stage2_cost'] = cum
                out['stage2_pass'] = need
                out['stage2_both'] = len(got) == 2
            nT = len(ids)
            lm = [label_rowmask(ctx, bank.cols[i], ty, ty) for i in ids]
            am = [sum(1 << r for r in range(R) if bank.cols[i][r] == Y[r]) for i in ids]
            out['if_triples'] = len(G) * nT * nT
            out['if_label_pairs'] = count_cover(lm, FULL)
            out['if_triples_label'] = len(G) * out['if_label_pairs']
            out['if_exact_pairs'] = count_cover(am, FULL)
            out['n_classes'] = nT
            out['n_guards'] = len(G)
            if iu is not None:
                pool = bank.lev[ty][bank.size[iu]]
                out['rankU'] = rank_block(bank, pool, iu, Y)
            if iv is not None:
                pool = bank.lev[ty][bank.size[iv]]
                out['rankV'] = rank_block(bank, pool, iv, Y)
            if first is not None:
                break
    out['first'] = first
    out['t'] = time.perf_counter() - t0
    return out


# =================================================================== ordinary tasks: do proposals fire?
def work_spurious(job):
    spec, seed, n = job
    t0 = time.perf_counter()
    task, info = spec
    nstar = info['nstar']
    env, Y, ty, term = task['env'], task['target'], task['ttype'], task['term']
    R = len(Y)
    out = dict(name=task['name'], term=term_str(term), ttype=ty, nstar=nstar, root=term[0],
               plain_cost=info['plain_cost'], lab_cost=info['lab_cost'], lab_found=info['lab_found'])
    state = dict(checks=0, fired=None)

    def hook(col, t, j=None):
        if t != ty:
            return False
        state['checks'] += 1
        p = residual_proposal(col, Y)
        if p is not None:
            state['fired'] = p
            state['j'] = j
            return True
        return False
    rng = random.Random(seed * 7919 + n)
    names = sorted(env)
    env2 = make_inputs(rng, names, rows=64)
    y2 = eval_term(term, env2)
    bank = Bank(env, BASE61_SET)
    fired = None
    s = 1
    while fired is None and s < nstar - 1:
        s += 1
        r = bank.level(s, Y, store=True, hook=hook)
        fired = r['hook_at']
    out['os_fired'] = fired
    out['os_level'] = s if fired is not None else None
    out['os_prop'] = state['fired']
    out['os_checks'] = state['checks']
    if fired is not None:
        fam, c = state['fired']
        u2 = eval_term(bank.term(state['j']), env2)
        f = (lambda v: v + c) if fam == 'add' else (lambda v: v * c)
        p2 = tuple(f(v) if isinstance(v, int) else tuple(map(f, v)) for v in u2)
        out['os_generalizes'] = p2 == y2
        out['os_size'] = bank.size[state['j']] + 2
    # splits from the complete bank below n*
    bank = Bank(env, BASE61_SET)
    for s in range(2, nstar):
        bank.level(s, Y, store=True)
    out['below'] = sum(bank.ncand.values())
    G, ng = guard_bank(bank, R)
    ids = [i for i in range(len(bank.cols)) if bank.ty[i] == ty]
    best, mins, nfit, nmask = split_search(bank, ids, Y, G)
    out['classes'] = len(ids)
    out['guards'] = len(G)
    out['nonzero_masks'] = nmask
    if best is not None:
        gens = [eval_split(sol, bank, G, env2) == y2 for sol in mins]
        out['split'] = dict(total_size=best[0], n_fit=nfit, n_min=len(mins), min_generalize=sum(gens),
                            first_generalizes=gens[0],
                            split='(if %s %s %s)' % (guard_str(G[best[4]][1], bank), term_str(bank.term(best[2])),
                                                    term_str(bank.term(best[3]))))
    else:
        out['split'] = None
    out['t'] = time.perf_counter() - t0
    return out


# =================================================================== driver and report
def cmd_offscale(a):
    tasks = gen_offscale(a.n, a.seed)
    t0 = time.perf_counter()
    with Pool(a.procs) as p:
        res = p.map(work_offscale, tasks, chunksize=1)
    json.dump(dict(kind='offscale', args=vars(a), wall=time.perf_counter() - t0, tasks=res), open(a.out, 'w'))
    print('wrote %s (%d tasks, %.0f s)' % (a.out, len(res), time.perf_counter() - t0))


def cmd_ifsplit(a):
    tasks = gen_if(a.n, a.seed)
    t0 = time.perf_counter()
    with Pool(a.procs) as p:
        res = p.map(work_if, tasks, chunksize=1)
    json.dump(dict(kind='if', args=vars(a), wall=time.perf_counter() - t0, tasks=res), open(a.out, 'w'))
    print('wrote %s (%d tasks, %.0f s)' % (a.out, len(res), time.perf_counter() - t0))


def cmd_spurious(a):
    J = json.load(open(a.src))
    seed, n = J['args']['seed'], J['args']['n']
    tasks = q2tasks.gen_tasks(n, seed, list(BASE61), n_ops_choices=(3, 4), max_size=5, prefix='G')
    ns = {t['name']: t for t in J['tasks'] if not t.get('skip')}
    jobs = [((t, ns[t['name']]), seed, k) for k, t in enumerate(tasks) if t['name'] in ns]
    t0 = time.perf_counter()
    with Pool(a.procs) as p:
        res = p.map(work_spurious, jobs, chunksize=1)
    json.dump(dict(kind='spurious', args=vars(a), wall=time.perf_counter() - t0, tasks=res), open(a.out, 'w'))
    print('wrote %s (%d tasks, %.0f s)' % (a.out, len(res), time.perf_counter() - t0))


def g(v):
    return gmean(v)


def rep_offscale(J):
    T = J['tasks']
    print('=' * 110)
    print('OFFSET / SCALE near-miss tasks: %d (seed %s); answer sizes %s; target types %s; wall %.0f s' % (
        len(T), J['args']['seed'], dict(Counter(t['nsA'] for t in T)), dict(Counter(t['ttype'] for t in T)),
        J['wall']))
    for fam in ('add', 'mul', 'all'):
        Q = [t for t in T if fam == 'all' or t['fam'] == fam]
        print('  family %-4s n=%d' % (fam, len(Q)))
        rows = [('A  plain, constant op in grammar (62 ops)', 'A', None),
                ('B  labels, constant op in grammar', 'B', None),
                ('C  plain 61 ops + residual check on stored classes', 'C', 'C_checks'),
                ('D  labels 61 ops + residual check on SURVIVING classes', 'D', 'D_checks'),
                ('D2 labels 61 ops + residual check on every evaluated', 'D2', 'D2_checks'),
                ('E  labels 62 ops + residual check on surviving classes', 'E', 'E_checks')]
        for nm, k, ck in rows:
            v = [t[k] for t in Q]
            ok = [x for x in v if x is not None]
            line = '    %-58s geo-mean %9.0f  median %9.0f  not found %2d of %d' % (
                nm, g(ok), median(ok), len(v) - len(ok), len(v))
            if ck:
                line += '   residual checks (median) %6.0f' % median([t[ck] for t in Q if t[k] is not None])
            print(line)

        def ratio(k1, k2):
            v = [t[k1] / t[k2] for t in Q if t[k1] is not None and t[k2] is not None]
            return g(v), len(v)
        for nm, k1, k2 in (('residual on plain search:            A / C ', 'A', 'C'),
                           ('labels alone:                        A / B ', 'A', 'B'),
                           ('residual on top of labels:           B / E ', 'B', 'E'),
                           ('review order vs residual only:       C / D ', 'C', 'D'),
                           ('residual sees everything vs survivors: D / D2', 'D', 'D2')):
            r, n = ratio(k1, k2)
            print('      gain %-48s %7.2fx  (n=%d)' % (nm, r, n))
        if fam == 'all':
            v = [dict(t, both=t['C'] + t['C_checks']) for t in Q]
            print('      counting each residual check as one candidate: A / (C + checks) = %.2fx' % g(
                [t['A'] / t['both'] for t in v]))
    print('  label bound h of the near miss U to the target (61-operator tables): %s' % dict(
        sorted(Counter('inf' if t['hU'] >= INF else t['hU'] for t in T).items(), key=str)))
    print('  arm D fired in pass (0 = never; U has size n*-1): %s' % dict(sorted(Counter(
        (t.get('D_pass', 0) - (t['size'] - 1)) if t['D'] is not None else 'never' for t in T).items(), key=str)))
    print('  arm C: the class that fired was the planted U in %d of %d (else an equivalent or smaller near miss)' % (
        sum(1 for t in T if t['C_fired'] and t['C_fired'][1]), len(T)))
    print('  arm E ended by: %s' % dict(Counter(t.get('E_how') for t in T)))
    print('  RANK of the near miss U among the classes of its size and type (complete plain bank):')
    for fam in ('add', 'mul'):
        Q = [t['rank'] for t in T if t['fam'] == fam and 'rank' in t]
        print('    family %s (n=%d, pool median %d classes; all three residual labels constant for U in %d; '
              'pool share all-constant %.2f%%)' % (fam, len(Q), median([q['pool'] for q in Q]),
                                                   sum(q['reg'] == 3 for q in Q),
                                                   100 * mean([q['frac_reg3'] for q in Q])))
        for nm, k in (('L1 (undefined last)', 'rank_l1'), ('DL alone', 'rank_dl'),
                      ('regularity count, then DL', 'rank_reg_dl'), ('all-regular first, then DL', 'rank_reg3_dl'),
                      ('R constant / scale / bank class first, then DL', 'rank_simple_dl')):
            v = [q[k] for q in Q]
            print('      %-48s rank 1 in %3d of %d   median rank %5.1f   mean rank %7.1f   worst %d' % (
                nm, sum(1 for x in v if x == 1), len(v), median(v), mean(v), max(v)))
        mv = [(q['rank_dl'], q['rank_reg_dl']) for q in Q]
        print('      regularity moved U up in %d, down in %d, nowhere in %d' % (
            sum(1 for a_, b_ in mv if b_ < a_), sum(1 for a_, b_ in mv if b_ > a_),
            sum(1 for a_, b_ in mv if b_ == a_)))


def rep_if(J):
    T = J['tasks']
    print('=' * 110)
    print('CONDITIONAL near-miss tasks: %d (seed %s): answer (if g U V), |U| = |V| = 3 nodes, g = pred(reduction(xs)); '
          'planted size 10; wall %.0f s' % (len(T), J['args']['seed'], J['wall']))
    print('  target types %s;  plain search finds the target as an unconditional program of size <= 4 in %d' % (
        dict(Counter(t['ttype'] for t in T)), sum(1 for t in T if 'plain_solved_at' in t)))
    F = [t for t in T if t['first']]
    print('  split proposal (agreement masks + guard bank) found a fitting split in %d of %d; at bank level %s' % (
        len(F), len(T), dict(Counter(t['first']['level'] for t in F))))
    print('    planted U, V and guard all present in the bank at level 3: %d of %d' % (
        sum(t.get('planted_in_bank', False) for t in T), len(T)))
    print('    cost: candidates evaluated in the bank, median %d;  classes examined (one mask each), median %d;  '
          'guard terms evaluated, median %d' % (median([t['first']['candidates'] for t in F]),
                                                median([t['first']['classes_examined'] for t in F]),
                                                median([t['first']['guard_terms'] for t in F])))
    print('    the first (smallest) split is right on 64 fresh rows in %d of %d;  total size median %d (planted 10)' % (
        sum(t['first']['first_generalizes'] for t in F), len(F), median([t['first']['total_size'] for t in F])))
    print('    fitting triples per task: median %d;  of the smallest-size ones, share right on fresh rows: %.0f%%' % (
        median([t['first']['n_fit'] for t in F]),
        100 * sum(t['first']['min_generalize'] for t in F) / sum(t['first']['n_min'] for t in F)))
    for ty in (L, I):
        Q = [t for t in F if t['ttype'] == ty]
        if Q:
            print('      target type %s: first split right on fresh rows %d of %d;  found at level 2 (before the '
                  'planted branches exist) in %d' % (ty, sum(t['first']['first_generalizes'] for t in Q), len(Q),
                                                     sum(1 for t in Q if t['first']['level'] == 2)))
    print('  WITHOUT the proposal: (if g U V) enumerated as an operator, from the same classes (sizes <= 3) and guards')
    print('    triples: geo-mean %.3g;  after the row-wise label test (labels of Y = labels of U or of V on every '
          'row): %.3g (%.0fx fewer);' % (g([t['if_triples'] for t in T]), g([max(1, t['if_triples_label']) for t in T]),
                                         g([t['if_triples'] / max(1, t['if_triples_label']) for t in T])))
    print('    pairs (U, V): all %.3g;  label test keeps %.3g;  exact agreement masks keep %.3g' % (
        g([t['n_classes'] ** 2 for t in T]), g([max(1, t['if_label_pairs']) for t in T]),
        g([max(1, t['if_exact_pairs']) for t in T])))
    print('    (a size-ordered enumeration reaches size 10 only after every smaller size; see b12_report.log for '
          'the measured size of levels 4 and 5)')
    print('  stage 2 before stage 3: label bound h of the planted branches to the target (61-operator tables)')
    hs = Counter()
    for t in T:
        for k in ('hU', 'hV'):
            if k in t:
                hs['inf' if t[k] >= INF else t[k]] += 1
    print('    %s   (a branch of size 3 survives the label filter of pass N only if 3 + h <= N)' % dict(
        sorted(hs.items(), key=str)))
    S2 = [t for t in T if 'stage2_cost' in t]
    print('    review order (label-filtered passes until both branches are stored, pass %s): %d of %d tasks reach '
          'it within pass 6, both branches stored in %d;' % (
              dict(Counter(t['stage2_pass'] for t in S2)), len(S2), len(T), sum(t['stage2_both'] for t in S2)))
    print('      candidates geo-mean %.0f, against %.0f for the plain bank to size 3 (%.1fx more)' % (
        g([t['stage2_cost'] for t in S2]), g([t['first']['candidates'] for t in S2 if t['first']]),
        g([t['stage2_cost'] / t['first']['candidates'] for t in S2 if t['first']])))
    print('  RANK of the planted branches among classes of their size and type:')
    Q = [t[k] for t in T for k in ('rankU', 'rankV') if k in t]
    for nm, k in (('L1 (undefined last)', 'rank_l1'), ('DL alone', 'rank_dl'),
                  ('regularity count, then DL', 'rank_reg_dl'), ('all-regular first, then DL', 'rank_reg3_dl')):
        v = [q[k] for q in Q]
        print('      %-40s rank 1 in %3d of %d   median rank %5.1f   mean rank %6.1f  (pool median %d)' % (
            nm, sum(1 for x in v if x == 1), len(v), median(v), mean(v), median([q['pool'] for q in Q])))
    mv = [(q['rank_dl'], q['rank_reg_dl']) for q in Q]
    print('      regularity moved a branch up in %d, down in %d, nowhere in %d' % (
        sum(1 for a_, b_ in mv if b_ < a_), sum(1 for a_, b_ in mv if b_ > a_), sum(1 for a_, b_ in mv if b_ == a_)))


def rep_spurious(J):
    T = J['tasks']
    print('=' * 110)
    print('ORDINARY tasks (%s, %d tasks, no near miss planted): what the stage-3 proposals do there; wall %.0f s' % (
        J['args']['src'], len(T), J['wall']))
    F = [t for t in T if t['os_fired'] is not None]
    print('  offset / scale proposal fired on a class smaller than the answer in %d of %d tasks (roots: %s)' % (
        len(F), len(T), dict(Counter(t['root'] for t in F).most_common(6))))
    print('    residual checks per task (one per stored class of the target type): median %d' % median(
        [t['os_checks'] for t in T]))
    print('    the fired program (U plus or times the constant) is right on 64 fresh rows in %d of %d;  its size '
          'minus n*: %s' % (sum(1 for t in F if t.get('os_generalizes')), len(F),
                            dict(sorted(Counter(t['os_size'] - t['nstar'] for t in F).items()))))
    if F:
        print('    on those %d tasks: candidates until the proposal fires, geo-mean %.0f;  plain search %.0f '
              '(%.1fx);  label-filtered search %.0f (%.2fx)' % (
                  len(F), g([t['os_fired'] for t in F]), g([t['plain_cost'] for t in F]),
                  g([t['plain_cost'] / t['os_fired'] for t in F]), g([t['lab_cost'] for t in F]),
                  g([t['lab_cost'] / t['os_fired'] for t in F])))
        print('    over all %d tasks, plain search with the proposal against plain search without: %.2fx '
              '(checks not counted), %.2fx (each check counted as a candidate)' % (
                  len(T), g([t['plain_cost'] / (t['os_fired'] or t['plain_cost']) for t in T]),
                  g([t['plain_cost'] / ((t['os_fired'] + t['os_checks']) if t['os_fired'] is not None
                                        else t['plain_cost'] + t['os_checks']) for t in T])))
    S = [t for t in T if t['split']]
    print('  a fitting split (if g U V) exists among the classes below n* in %d of %d tasks' % (len(S), len(T)))
    for ty in (L, I):
        Q = [t for t in T if t['ttype'] == ty]
        Sq = [t for t in Q if t['split']]
        if not Q:
            continue
        print('    target type %s: %d of %d tasks have one;  the smallest is right on 64 fresh rows in %d of %d;  '
              'its size minus n*: median %s, min %s' % (
                  ty, len(Sq), len(Q), sum(t['split']['first_generalizes'] for t in Sq), len(Sq),
                  median([t['split']['total_size'] - t['nstar'] for t in Sq]) if Sq else '-',
                  min([t['split']['total_size'] - t['nstar'] for t in Sq]) if Sq else '-'))
        if Sq:
            print('      fitting triples per task: median %d, max %d;  smallest-size splits right on fresh rows: '
                  '%d of %d' % (median([t['split']['n_fit'] for t in Sq]), max(t['split']['n_fit'] for t in Sq),
                               sum(t['split']['min_generalize'] for t in Sq), sum(t['split']['n_min'] for t in Sq)))


def cmd_report(a):
    for fn in a.files:
        J = json.load(open(fn))
        {'offscale': rep_offscale, 'if': rep_if, 'spurious': rep_spurious}[J['kind']](J)
        print()


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd')
    for nm in ('offscale', 'ifsplit'):
        r = sub.add_parser(nm)
        r.add_argument('--seed', type=int, default=21)
        r.add_argument('--n', type=int, default=96)
        r.add_argument('--procs', type=int, default=14)
        r.add_argument('--out', required=True)
    r = sub.add_parser('spurious')
    r.add_argument('src')
    r.add_argument('--procs', type=int, default=14)
    r.add_argument('--out', required=True)
    r = sub.add_parser('report')
    r.add_argument('files', nargs='+')
    a = ap.parse_args()
    dict(offscale=cmd_offscale, ifsplit=cmd_ifsplit, spurious=cmd_spurious, report=cmd_report)[a.cmd](a)
