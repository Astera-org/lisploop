"""Experiments B1, B2, B4 (claim U2) on ordinary pipeline tasks of 3 and 4 operators.

  python3 b12.py run  --seed 11 --n 120 --out b12_s11.json   (per-task analysis, parallel)
  python3 b12.py report b12_s11.json [b12_s12.json ...]       (tables)

For each task: plain bottom-up search over the 61-operator library until the answer's
size n*; then every class of size < n* is scored against the target by
  L1          sum of |differences| (defined only for equal types and equal list lengths)
  DL          the kernel's correction code (hlib.corr_bits), summed over rows
  labels      the six hand-listed quotients of verify-quotients, tables from 2,000 probes
"""
import argparse
import json
import math
import sys
import time
from collections import Counter, defaultdict
from multiprocessing import Pool

from hlib import (L, I, OPS, OPSIG, BASE61, BASE61_SET, AbsCtx, Bank, run_plain, tables_for, col_dl,
                  col_l1, col_residual, regularity, const_offset, const_scale, pct_rank, gmean, mean,
                  median, boot_ci, expected_random_order, eval_term, subterms, term_str, term_ops)
import q2search
import q2tasks
import random

BEAMS = (0.5, 0.25, 0.1)


def final_cost(order, n, hitset):
    cum = 0
    for c in order:
        k = n[c]
        if k == 0:
            continue
        if c in hitset:
            return cum + (k + 1) / 2
        cum += k
    return None


def random_cost(ids, n, hitset):
    hs = [c for c in hitset if n[c] > 0]
    if not hs:
        return None
    non = sum(n[c] for c in ids if c not in hitset)
    return non / (len(hs) + 1) + sum((n[c] + 1) / 2 for c in hs) / len(hs)


def run_beam(env, target, nstar, k):
    """Residual ranking EARLY: at every size level below n*, keep only the best fraction k
    of the new classes of each type by DL to the target (ties in enumeration order)."""
    bank = Bank(env, BASE61_SET)
    below = len(env)
    for s in range(2, nstar):
        r = bank.level(s, target, store=True)
        below += r['total']
        for ty in (L, I):
            ids = bank.lev[ty].get(s)
            if not ids:
                continue
            keep = max(1, math.ceil(k * len(ids)))
            ids2 = sorted(ids, key=lambda i: (col_dl(bank.cols[i], target), i))[:keep]
            bank.lev[ty][s] = sorted(ids2)
    r = bank.level(nstar, target, store=False)
    solved = bool(r['hits'])
    cost = below + (expected_random_order(r['n'], r['hit'], random.Random(0), 200) if solved else r['total'])
    return solved, cost


def analyse(job):
    task, M, kind, tseed = job
    t0 = time.perf_counter()
    env, target, ttype, term = task['env'], task['target'], task['ttype'], task['term']
    tb = tables_for(BASE61, M, kind, tseed)
    bank, nstar, fin = run_plain(env, target, task['size'])
    out = dict(name=task['name'], term=term_str(term), n_ops=len(task['ops']), size=task['size'],
               nstar=nstar, ttype=ttype, inputs=len(env), root=term[0], root_arity=len(term) - 1)
    if nstar is None or nstar < 3:
        out['skip'] = True
        return out
    nC = next((i for i in range(len(bank.cols)) if bank.size[i] >= nstar), len(bank.cols))
    C = range(nC)
    ctx = AbsCtx(tb, target, ttype)
    nq, R = ctx.nq, len(target)
    dl, l1, aid, idf, reg, rsimple = [], [], [], [], [], []
    for i in C:
        col, ty = bank.cols[i], bank.ty[i]
        dl.append(col_dl(col, target))
        l1.append(col_l1(col, target))
        aid.append(ctx.abstract(col, ty))
        d = {}
        ok = True
        for p, t in zip(col, target):
            if d.setdefault(p, t) != t:
                ok = False
                break
        idf.append(ok)
        if ty == ttype:
            Rc = col_residual(col, target)
            reg.append(regularity(Rc, ty))
            rsimple.append(Rc is not None and (const_offset(col, target) is not None or Rc in bank.idx))
        else:
            reg.append(0)
            rsimple.append(False)
    ah = ctx.ah
    hamc = {}

    def ham(i):
        a = aid[i]
        v = hamc.get(a)
        if v is None:
            if bank.ty[i] != ttype:
                v = nq * R
            else:
                ids = ctx.aids[a]
                v = sum(1 for j in range(nq) for x, t in zip(ctx.vecs[j][ids[j]], ctx.tvec[j]) if x != t)
            hamc[a] = v
        return v
    # ---- final-level candidate counts per class (as first argument), with and without the label filter
    un = {L: [o[0] for o in bank.ops if o[1] == (L,)], I: [o[0] for o in bank.ops if o[1] == (I,)]}
    bi = {L: [(o[0], o[1][1]) for o in bank.ops if len(o[1]) == 2 and o[1][0] == L],
          I: [(o[0], o[1][1]) for o in bank.ops if len(o[1]) == 2 and o[1][0] == I]}
    groups = {}
    for ty in (L, I):
        for s, ids in bank.lev[ty].items():
            if s < nstar:
                groups[(ty, s)] = Counter(aid[i] for i in ids)
    memo = {}

    def cc(ty, s, a):
        key = (ty, s, a)
        v = memo.get(key)
        if v is None:
            n = nf = 0
            smin = 1e9
            if s == nstar - 1:
                for f in un[ty]:
                    n += 1
                    if ctx.bound(f, a) <= 0:
                        nf += 1
                        smin = min(smin, ctx.surprise(f, a))
            s2 = nstar - 1 - s
            if s2 >= 1:
                for f, t2 in bi[ty]:
                    g2 = groups.get((t2, s2))
                    if not g2:
                        continue
                    for a2, cnt in g2.items():
                        n += cnt
                        if ctx.bound(f, a, a2) <= 0:
                            nf += cnt
                            smin = min(smin, ctx.surprise(f, a, a2))
            v = memo[key] = (n, nf, smin)
        return v
    n0, nF, sur = [], [], []
    for i in C:
        n, nf, sm = cc(bank.ty[i], bank.size[i], aid[i])
        n0.append(n)
        nF.append(nf)
        sur.append(sm)
    assert sum(n0) == fin['total'], (sum(n0), fin['total'])
    H = {h[1] for h in fin['hits']}
    HF = {h[1] for h in fin['hits']
          if ctx.bound(h[0], aid[h[1]], aid[h[2]] if h[2] is not None else None) <= 0}
    ids = list(C)
    below = sum(bank.ncand[s] for s in range(1, nstar))
    costs = dict(below=below, final_total=fin['total'], final_filtered=sum(nF),
                 n_hit_classes=len(H), n_hit_classes_F=len(HF))
    costs['none_rand'] = random_cost(ids, n0, H)
    costs['none_dl'] = final_cost(sorted(ids, key=lambda i: (dl[i], i)), n0, H)
    costs['none_l1'] = final_cost(sorted(ids, key=lambda i: (l1[i] is None, l1[i] or 0, i)), n0, H)
    costs['none_ham'] = final_cost(sorted(ids, key=lambda i: (ham(i), i)), n0, H)
    costs['none_dlreg'] = final_cost(sorted(ids, key=lambda i: (-reg[i], dl[i], i)), n0, H)
    costs['lab_rand'] = random_cost(ids, nF, HF)
    costs['lab_dl'] = final_cost(sorted(ids, key=lambda i: (dl[i], i)), nF, HF)
    costs['lab_sur'] = final_cost(sorted(ids, key=lambda i: (sur[i], i)), nF, HF)
    costs['lab_ham'] = final_cost(sorted(ids, key=lambda i: (ham(i), i)), nF, HF)
    out['costs'] = costs
    # ---- per-level label statistics
    lv = {}
    for s in range(1, nstar):
        pool = bank.lev[L].get(s, []) + bank.lev[I].get(s, [])
        if pool:
            lv[s] = dict(n=len(pool), reach=sum(1 for i in pool if s + ah[aid[i]] <= nstar),
                         idf=sum(1 for i in pool if idf[i]),
                         elig=sum(1 for i in pool if n0[i] > 0), adm=sum(1 for i in pool if nF[i] > 0),
                         l1def=sum(1 for i in pool if l1[i] is not None))
    out['levels'] = lv
    # ---- the reference program's path
    out['short'] = nstar < task['size']
    path = []
    for (u, d) in subterms(term):
        if d == 0 or isinstance(u, str):
            continue
        cu = eval_term(u, env)
        i = bank.idx.get(cu)
        if i is None or i >= nC:
            path.append(dict(depth=d, missing=True))
            continue
        s, ty = bank.size[i], bank.ty[i]
        pool_same = bank.lev[ty][s]
        pool_all = bank.lev[L].get(s, []) + bank.lev[I].get(s, [])
        pl1 = [l1[j] for j in pool_same if l1[j] is not None]
        rec = dict(depth=d, level=s, ty=ty, same_type=ty == ttype, n_all=len(pool_all), n_same=len(pool_same),
                   pct_dl_all=pct_rank([dl[j] for j in pool_all], dl[i]),
                   pct_dl_same=pct_rank([dl[j] for j in pool_same], dl[i]),
                   l1_def=l1[i] is not None, frac_l1_def=len(pl1) / len(pool_same),
                   pct_l1=pct_rank(pl1, l1[i]) if l1[i] is not None else None,
                   pct_dl_shape=(pct_rank([dl[j] for j in pool_same if l1[j] is not None], dl[i])
                                 if l1[i] is not None else None),
                   pct_ham=pct_rank([ham(j) for j in pool_same], ham(i)),
                   reach=s + ah[aid[i]] <= nstar,
                   frac_reach=sum(1 for j in pool_all if s + ah[aid[j]] <= nstar) / len(pool_all),
                   idf=idf[i], frac_idf=sum(1 for j in pool_all if idf[j]) / len(pool_all))
        if d == 1:
            elig = [j for j in pool_all if n0[j] > 0]
            adm = [j for j in pool_all if nF[j] > 0]
            adm_same = [j for j in pool_same if nF[j] > 0]
            bucket = [j for j in pool_same if aid[j] == aid[i]]
            bl1 = [l1[j] for j in bucket if l1[j] is not None]
            k2 = ctx.aids[aid[i]][:2]
            bucket2 = [j for j in pool_same if ctx.aids[aid[j]][:2] == k2]
            rec.update(in_H=i in H, in_HF=i in HF, adm=nF[i] > 0,
                       frac_adm=len(adm) / max(1, len(elig)),
                       pct_dl_adm=pct_rank([dl[j] for j in adm_same], dl[i]) if nF[i] > 0 else None,
                       n_adm_same=len(adm_same),
                       bucket2=len(bucket2), pct_dl_bucket2=pct_rank([dl[j] for j in bucket2], dl[i]),
                       best_dl_bucket2=all(dl[j] > dl[i] for j in bucket2 if j != i),
                       bucket=len(bucket), bucket_hits=sum(1 for j in bucket if j in H),
                       pct_dl_bucket=pct_rank([dl[j] for j in bucket], dl[i]),
                       pct_l1_bucket=pct_rank(bl1, l1[i]) if l1[i] is not None else None,
                       best_dl_bucket=all(dl[j] > dl[i] for j in bucket if j != i),
                       rank_dl_bucket=1 + sum(1 for j in bucket if dl[j] < dl[i]),
                       ties_dl_bucket=sum(1 for j in bucket if dl[j] == dl[i]) - 1,
                       reg=reg[i], rsimple=rsimple[i],
                       frac_reg3=sum(1 for j in pool_same if reg[j] == 3) / len(pool_same),
                       pct_reg_dl=pct_rank([(-reg[j], dl[j]) for j in pool_same], (-reg[i], dl[i])),
                       pct_reg3_dl=pct_rank([(reg[j] != 3, dl[j]) for j in pool_same], (reg[i] != 3, dl[i])),
                       pct_rsimple_dl=pct_rank([(not rsimple[j], dl[j]) for j in pool_same],
                                               (not rsimple[i], dl[i])),
                       rank_dl_same=1 + sum(1 for j in pool_same if dl[j] < dl[i]),
                       rank_reg_dl=1 + sum(1 for j in pool_same if (-reg[j], dl[j]) < (-reg[i], dl[i])))
        path.append(rec)
    out['path'] = path
    # is the reference's own last step (root operator on its argument classes) passed by the label test?
    kids = [bank.idx.get(eval_term(k, env)) for k in term[1:]]
    if all(k is not None and k < nC for k in kids):
        out['root_adm'] = ctx.bound(term[0], aid[kids[0]], aid[kids[1]] if len(kids) > 1 else None) <= 0
    out['any_adm_hit'] = any(ctx.bound(h[0], aid[h[1]], aid[h[2]] if h[2] is not None else None) <= 0
                             for h in fin['hits'])
    out['t_plain'] = time.perf_counter() - t0
    # ---- labels EARLY, full accounting (every deepening pass), and residual EARLY (beam)
    rng = random.Random(1)
    lv_ = fin
    out['plain_cost'] = below + expected_random_order(lv_['n'], lv_['hit'], rng, 200)
    pr = q2search.pruned_search(env, target, ttype, tb, nstar, opnames=BASE61_SET)
    last = pr['last']
    out['lab_found'] = pr['found']
    out['lab_cost'] = (pr['cum_before'] + last['below'] +
                       (expected_random_order(last['fin_n'], last['fin_hit'], rng, 200) if pr['found']
                        else sum(last['fin_n'])))
    out['lab_before'] = pr['cum_before'] + last['below']
    out['lab_store'] = last['store_below']
    out['plain_store'] = nC
    out['beam'] = {}
    for k in BEAMS:
        solved, cost = run_beam(env, target, nstar, k)
        out['beam'][str(k)] = dict(solved=solved, cost=cost)
    out['t_all'] = time.perf_counter() - t0
    return out


def cmd_run(a):
    tasks = q2tasks.gen_tasks(a.n, a.seed, list(BASE61), n_ops_choices=(3, 4), max_size=5, prefix='G',
                              rows=a.rows)
    jobs = [(t, a.probes, a.kind, a.tseed) for t in tasks]
    t0 = time.perf_counter()
    with Pool(a.procs) as p:
        res = p.map(analyse, jobs, chunksize=1)
    json.dump(dict(args=vars(a), wall=time.perf_counter() - t0, tasks=res), open(a.out, 'w'))
    print('wrote %s: %d tasks in %.0f s' % (a.out, len(res), time.perf_counter() - t0))


def fmt(x, w=6, p=1):
    return ('%*.*f' % (w, p, x)) if x == x else ' ' * (w - 1) + '-'


def cmd_report(a):
    for fn in a.files:
        J = json.load(open(fn))
        T = [t for t in J['tasks'] if not t.get('skip')]
        print('=' * 110)
        print('%s: %d tasks (seed %s, %s rows, %s probes/op, %s); %d skipped; plain found a shorter program than '
              'the reference on %d' % (fn, len(T), J['args']['seed'], J['args'].get('rows', 8),
                                      J['args']['probes'], J['args']['kind'],
                                      len(J['tasks']) - len(T), sum(t['short'] for t in T)))
        print('   n* (answer size): %s;  operators: %s;  target type: %s;  wall %.0f s' % (
            dict(Counter(t['nstar'] for t in T)), dict(Counter(t['n_ops'] for t in T)),
            dict(Counter(t['ttype'] for t in T)), J['wall']))
        Tp = [t for t in T if not t['short']]
        P = [dict(p, task=t['name'], nstar=t['nstar'], root=t['root'], ttype=t['ttype'])
             for t in Tp for p in t['path'] if not p.get('missing')]
        print('   on-path classes (proper non-leaf subterms of the reference, %d tasks): %d; '
              'missing from the bank: %d' % (len(Tp), len(P),
                                              sum(1 for t in Tp for p in t['path'] if p.get('missing'))))

        # ------------------------------------------------------------ B1
        print('\nB1. Where the on-path class ranks among the bank classes of its own size level')
        print('    percentile: 0 = closest to the target, 100 = farthest, 50 = a class drawn at random')
        print('    %-10s %4s | %-31s | %-31s | %-25s | %s' % (
            'steps out', 'n', 'DL, pool = same level, any type', 'DL, pool = same level and type',
            'L1 (same type, defined)', 'L1 undefined for the on-path class'))
        print('    %-10s %4s | %6s %6s %6s %9s | %6s %6s %6s %9s | %6s %6s %5s %4s |' % (
            '', '', 'mean', 'median', '<=10%', '95% CI', 'mean', 'median', '<=10%', '95% CI', 'mean',
            'median', '<=10%', 'n'))
        for d in (1, 2, 3, 'all'):
            Q = [p for p in P if d == 'all' or p['depth'] == d]
            if not Q:
                continue
            row = '    %-10s %4d |' % (d, len(Q))
            for key in ('pct_dl_all', 'pct_dl_same'):
                v = [100 * p[key] for p in Q if p[key] is not None]
                lo, hi = boot_ci(v)
                row += ' %s %s %5.0f%% %4.0f-%-4.0f |' % (fmt(mean(v)), fmt(median(v)),
                                                        100 * mean([x <= 10 for x in v]), lo, hi)
            v = [100 * p['pct_l1'] for p in Q if p['pct_l1'] is not None]
            row += ' %s %s %4.0f%% %4d | %d of %d (%.0f%%)' % (
                fmt(mean(v)), fmt(median(v)), 100 * mean([x <= 10 for x in v]) if v else float('nan'), len(v),
                sum(1 for p in Q if not p['l1_def']), len(Q), 100 * mean([not p['l1_def'] for p in Q]))
            print(row)
        print('    the same on-path classes where L1 is defined, against only the classes of the same type AND the')
        print('    same list lengths as the target (a pool in which "similar size and shape" earns nothing):')
        for d in (1, 2, 3):
            Q = [p for p in P if p['depth'] == d and p.get('pct_dl_shape') is not None]
            if Q:
                v = [100 * p['pct_dl_shape'] for p in Q]
                w = [100 * p['pct_l1'] for p in Q if p['pct_l1'] is not None]
                lo, hi = boot_ci(v)
                print('       steps out %d  n=%3d   DL mean %s (95%% CI %.0f-%.0f) median %s   L1 mean %s median %s' % (
                    d, len(Q), fmt(mean(v)), lo, hi, fmt(median(v)), fmt(mean(w)), fmt(median(w))))
        print('    same, split by whether the on-path class has the type of the target (DL, same level and type):')
        for d in (1, 2, 3):
            for st in (True, False):
                v = [100 * p['pct_dl_same'] for p in P if p['depth'] == d and p['same_type'] == st
                     and p['pct_dl_same'] is not None]
                if v:
                    print('       steps out %d, %-14s n=%3d  mean %s  median %s' % (
                        d, 'same type' if st else 'other type', len(v), fmt(mean(v)), fmt(median(v))))
        print('    identity group-by (U1 regime 3 as the review states it): share of ALL bank classes for which')
        print('    "Y is a function of U" holds on the 8 rows (zero residual): %.1f%%;  on-path classes: %.1f%%' % (
            100 * sum(l['idf'] for t in T for l in t['levels'].values()) /
            sum(l['n'] for t in T for l in t['levels'].values()), 100 * mean([p['idf'] for p in P])))
        print('\n    Label reachability on the same classes (class kept iff size + label bound <= n*)')
        print('    %-10s %4s | %-22s | %-24s | %-30s' % ('steps out', 'n', 'bank classes ruled out',
                                                       'on-path class ruled out', 'DL rank needed to keep as many'))
        for d in (1, 2, 3):
            Q = [p for p in P if p['depth'] == d]
            if not Q:
                continue
            out_frac = [1 - p['frac_reach'] for p in Q]
            # how often would a DL cut-off that discards the same fraction lose the on-path class
            lost_dl = sum(1 for p in Q if p['pct_dl_all'] is not None and p['pct_dl_all'] > p['frac_reach'])
            print('    %-10s %4d | mean %5.1f%% med %5.1f%% | %3d of %3d (%4.1f%%)       | DL cut at the same '
                  'fraction loses %d (%.0f%%)' % (
                      d, len(Q), 100 * mean(out_frac), 100 * median(out_frac),
                      sum(1 for p in Q if not p['reach']), len(Q), 100 * mean([not p['reach'] for p in Q]),
                      lost_dl, 100 * lost_dl / len(Q)))
        Q = [p for p in P if p['depth'] == 1]
        ra = [t['root_adm'] for t in Tp if 'root_adm' in t]
        print('    one step out, the stronger test (some operator with this class as first argument may give the '
              'target labels):')
        print('       rules out mean %.1f%% of eligible classes;  the reference\'s own last step is rejected in '
              '%d of %d tasks;  every last step that hits is rejected in %d of %d' % (
                  100 * mean([1 - p['frac_adm'] for p in Q]), sum(1 for x in ra if not x), len(ra),
                  sum(1 for t in T if not t['any_adm_hit']), len(T)))
        lostdl = sum(1 for p in Q if p['pct_dl_all'] is not None and p['pct_dl_all'] > p['frac_adm'])
        print('       a DL cut-off keeping the same fraction would lose the true parent in %d of %d (%.0f%%)' % (
            lostdl, len(Q), 100 * lostdl / len(Q)))
        A = [p for p in Q if p['adm'] and p.get('pct_dl_adm') is not None]
        v = [100 * p['pct_dl_adm'] for p in A]
        lo, hi = boot_ci(v)
        print('       among the classes of its level and type that survive that test (median %s classes), the true '
              'parent\'s DL percentile: mean %s (95%% CI %.0f-%.0f), median %s, n=%d' % (
                  fmt(median([p['n_adm_same'] for p in A]), 1, 0), fmt(mean(v)), lo, hi, fmt(median(v)), len(v)))

        # ------------------------------------------------------------ B2
        print('\nB2. One step out: the true parent (argument of the reference root) against the classes of the')
        print('    same size and type that carry the SAME label vector on every row and quotient ("bucket")')
        Q = [p for p in P if p['depth'] == 1]
        multi = [p for p in Q if p['bucket'] > 1]
        print('    true parents: %d;  labels fail to separate (bucket > 1): %d (%.0f%%);  bucket size median %s, '
              'mean %s, max %d' % (len(Q), len(multi), 100 * len(multi) / len(Q),
                                   fmt(median([p['bucket'] for p in Q]), 1, 0),
                                   fmt(mean([p['bucket'] for p in Q]), 1, 1), max(p['bucket'] for p in Q)))
        print('    in those %d cases, rank of the true parent inside its bucket by distance to the target:' % len(multi))
        for key, nm in (('pct_dl_bucket', 'DL'), ('pct_l1_bucket', 'L1')):
            v = [100 * p[key] for p in multi if p[key] is not None]
            lo, hi = boot_ci(v)
            print('       %-3s percentile mean %s (95%% CI %.0f-%.0f), median %s, n=%d of %d defined' % (
                nm, fmt(mean(v)), lo, hi, fmt(median(v)), len(v), len(multi)))
        print('       DL strictly best in bucket: %d of %d (%.0f%%);  expected by chance %.0f%%' % (
            sum(p['best_dl_bucket'] for p in multi), len(multi), 100 * mean([p['best_dl_bucket'] for p in multi]),
            100 * mean([1 / p['bucket'] for p in multi])))
        print('       other bucket members that also reach the target in one step (alternative parents): '
              'mean %.2f' % mean([p['bucket_hits'] - 1 for p in multi]))
        m2 = [p for p in Q if p['bucket2'] > 1]
        v = [100 * p['pct_dl_bucket2'] for p in m2 if p['pct_dl_bucket2'] is not None]
        lo, hi = boot_ci(v)
        print('    with the review\'s two-word vocabulary only (sign and parity): bucket > 1 in %d of %d (%.0f%%), '
              'median bucket %s classes;' % (len(m2), len(Q), 100 * len(m2) / len(Q),
                                            fmt(median([p['bucket2'] for p in Q]), 1, 0)))
        print('       true parent\'s DL percentile inside it: mean %s (95%% CI %.0f-%.0f), median %s; strictly best '
              'in %d of %d (chance %.1f%%)' % (fmt(mean(v)), lo, hi, fmt(median(v)),
                                             sum(p['best_dl_bucket2'] for p in m2), len(m2),
                                             100 * mean([1 / p['bucket2'] for p in m2])))
        fam = {'offset/scale (inc dec dbl neg add_k mul_k ...)':
               {'inc_all', 'dec_all', 'dbl_all', 'neg_all', 'inc', 'dec', 'dbl', 'neg', 'add_k', 'mul_k',
                'half_all', 'abs_all', 'abs', 'sq_all', 'sq'},
               'reorder (sort sort_desc reverse shift1)': {'sort', 'sort_desc', 'reverse', 'shift1'},
               'shape-changing list->list (filter tail take ...)':
               {'filter_pos', 'filter_neg', 'filter_even', 'filter_odd', 'tail', 'init', 'take2', 'take3',
                'drop2', 'dedup_adj', 'evens_idx', 'odds_idx', 'map_adj_add', 'map_adj_sub', 'map_adj_mul',
                'map_adj_min', 'map_adj_max', 'take_n', 'cons', 'concat'},
               'running / zip (same length, new values)':
               {'running_sum', 'running_max', 'running_min', 'zip_add', 'zip_sub', 'zip_mul', 'zip_min',
                'zip_max'},
               'reduction list->int': {'sum', 'len', 'head', 'last', 'min_el', 'max_el', 'count_pos',
                                       'count_even', 'count_distinct'},
               'int x int': {'add', 'sub', 'mul', 'min', 'max'}}
        print('    by the kind of the root operator (all true parents; DL percentile within the same level and type,')
        print('    and inside the bucket where the bucket has more than one member):')
        print('       %-52s %4s %10s %10s %12s %10s' % ('root operator', 'n', 'level pct', 'bucket pct',
                                                        'best in bkt', 'L1 defined'))
        for nm, ops in fam.items():
            G = [p for p in Q if p['root'] in ops]
            if not G:
                continue
            Gm = [p for p in G if p['bucket'] > 1]
            print('       %-52s %4d %10s %10s %7d/%-4d %9.0f%%' % (
                nm, len(G), fmt(mean([100 * p['pct_dl_same'] for p in G if p['pct_dl_same'] is not None])),
                fmt(mean([100 * p['pct_dl_bucket'] for p in Gm if p['pct_dl_bucket'] is not None])),
                sum(p['best_dl_bucket'] for p in Gm), len(Gm), 100 * mean([p['l1_def'] for p in G])))
        print('    residual bucket regularity (labels of R = Y - U constant over rows), true parents, pool = same '
              'level and type:')
        print('       residual defined for the true parent: %d of %d;  all three value labels constant: %d;  '
              'share of the pool with all three constant: mean %.1f%%' % (
                  sum(p['l1_def'] for p in Q), len(Q), sum(p['reg'] == 3 for p in Q),
                  100 * mean([p['frac_reg3'] for p in Q])))
        for key, nm in (('pct_dl_same', 'DL alone'), ('pct_reg_dl', 'regularity count first, then DL'),
                        ('pct_reg3_dl', 'all-regular first, then DL'),
                        ('pct_rsimple_dl', 'plan 6.2: R constant or R a bank class first, then DL')):
            v = [100 * p[key] for p in Q if p[key] is not None]
            print('       %-55s mean pct %s  median %s  top-1%%: %3.0f%%' % (
                nm, fmt(mean(v)), fmt(median(v)), 100 * mean([x <= 1 for x in v])))
        mv = [(p['rank_dl_same'], p['rank_reg_dl']) for p in Q]
        print('       regularity moved the true parent up in %d, down in %d, left it in place in %d of %d' % (
            sum(1 for a_, b_ in mv if b_ < a_), sum(1 for a_, b_ in mv if b_ > a_),
            sum(1 for a_, b_ in mv if b_ == a_), len(mv)))
        up = [p for p in Q if p['rank_reg_dl'] < p['rank_dl_same']]
        dn = [p for p in Q if p['rank_reg_dl'] > p['rank_dl_same']]
        print('         moved up:   roots %s' % dict(Counter(p['root'] for p in up).most_common(8)))
        print('         moved down: roots %s' % dict(Counter(p['root'] for p in dn).most_common(8)))

        # ------------------------------------------------------------ B4
        print('\nB4. The order of the handoff')
        print('  (a) the FINAL size level only, on the complete plain bank: candidates evaluated until the first hit')
        print('      (classes expanded in the given order; geometric mean over tasks; "lost" = no hit survives)')
        keys = [('none_rand', 'no filter, random class order'), ('none_dl', 'no filter, DL order (residual late)'),
                ('none_l1', 'no filter, L1 order (undefined last)'),
                ('none_dlreg', 'no filter, regularity then DL'),
                ('none_ham', 'no filter, label-mismatch count order (labels late, as a ranking)'),
                ('lab_rand', 'label filter, random order (labels late, as a filter)'),
                ('lab_dl', 'label filter, then DL order (the review\'s stage 2 -> 3)'),
                ('lab_sur', 'label filter, then table-surprise order'),
                ('lab_ham', 'label filter, then label-mismatch order')]
        base = gmean([t['costs']['none_rand'] for t in T])
        for k, nm in keys:
            v = [t['costs'][k] for t in T]
            lost = sum(1 for x in v if x is None)
            g = gmean(v)
            better = sum(1 for t in T if t['costs'][k] is not None and
                         t['costs'][k] < t['costs']['lab_rand' if k.startswith('lab') else 'none_rand'])
            print('      %-68s %10.0f  gain %5.2fx  lost %d  beats random order on %d of %d' % (
                nm, g, base / g, lost, better, len(T)))
        print('      final level size: geometric mean %.0f candidates, %.0f after the label filter (%.1fx)' % (
            gmean([t['costs']['final_total'] for t in T]), gmean([t['costs']['final_filtered'] for t in T]),
            gmean([t['costs']['final_total'] / max(1, t['costs']['final_filtered']) for t in T])))
        print('      by answer size n*: ' + ';  '.join(
            'n*=%d: %d tasks, last level %.0f candidates, all levels below %.0f' % (
                n_, sum(1 for t in T if t['nstar'] == n_), gmean([t['costs']['final_total'] for t in T if t['nstar'] == n_]),
                gmean([t['costs']['below'] for t in T if t['nstar'] == n_])) for n_ in (3, 4, 5)))
        print('  (b) the WHOLE search, every pass counted (geometric mean of candidates; answers lost)')
        g0 = gmean([t['plain_cost'] for t in T])
        print('      %-58s %10.0f   1.00x   lost 0' % ('plain', g0))
        ok = [t for t in T if t['lab_found']]
        print('      %-58s %10.0f  %5.2fx   lost %d of %d' % (
            'labels EARLY (filter during enumeration)', gmean([t['lab_cost'] for t in ok]),
            gmean([t['plain_cost'] / t['lab_cost'] for t in ok]), len(T) - len(ok), len(T)))
        for k in BEAMS:
            ok = [t for t in T if t['beam'][str(k)]['solved']]
            print('      %-58s %10.0f  %5.2fx   lost %d of %d' % (
                'residual EARLY (keep best %d%% by DL at every level)' % (100 * k),
                gmean([t['beam'][str(k)]['cost'] for t in ok]),
                gmean([t['plain_cost'] / t['beam'][str(k)]['cost'] for t in ok]) if ok else float('nan'),
                len(T) - len(ok), len(T)))
        # stage 2 then 3 on the plain bank: below + filtered final in DL order
        v1 = gmean([t['costs']['below'] + t['costs']['none_dl'] for t in T])
        print('      %-58s %10.0f  %5.2fx   lost 0' % ('residual LATE only (plain below, DL order at the last level)',
                                                     v1, g0 / v1))
        okl = [t for t in T if t['costs']['lab_rand'] is not None]
        v4 = gmean([t['costs']['below'] + t['costs']['lab_rand'] for t in okl])
        print('      %-58s %10.0f  %5.2fx   lost %d of %d' % (
            'labels LATE only (plain below, label test at the last level)', v4,
            gmean([t['plain_cost'] / (t['costs']['below'] + t['costs']['lab_rand']) for t in okl]),
            len(T) - len(okl), len(T)))
        print('      ceilings: the best ANY ordering of the last level could do (answer first):')
        v2 = gmean([t['costs']['below'] + 1 for t in T])
        print('      %-58s %10.0f  %5.2fx' % ('  on plain search', v2, g0 / v2))
        ok = [t for t in T if t['lab_found']]
        v3 = gmean([t['lab_before'] + 1 for t in ok])
        print('      %-58s %10.0f  %5.2fx   (%.2fx on top of labels early)' % (
            '  on top of labels early', v3, gmean([t['plain_cost'] / (t['lab_before'] + 1) for t in ok]),
            gmean([t['lab_cost'] / (t['lab_before'] + 1) for t in ok])))
        print('      stored classes: plain %.0f, labels early %.0f (geometric means)' % (
            gmean([t['plain_store'] for t in T]), gmean([t['lab_store'] for t in T])))
        print()


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd')
    r = sub.add_parser('run')
    r.add_argument('--seed', type=int, default=11)
    r.add_argument('--n', type=int, default=120)
    r.add_argument('--probes', type=int, default=2000)
    r.add_argument('--kind', default='iid')
    r.add_argument('--tseed', type=int, default=0)
    r.add_argument('--procs', type=int, default=14)
    r.add_argument('--out', default='b12.json')
    r.add_argument('--rows', type=int, default=8)
    p = sub.add_parser('report')
    p.add_argument('files', nargs='+')
    a = ap.parse_args()
    if a.cmd == 'run':
        cmd_run(a)
    else:
        cmd_report(a)
