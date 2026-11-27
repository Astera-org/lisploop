"""Q2 sweeps: how the gain of abstract-table pruning changes with
  (a) the set / number of quotients (1, 3, 6, merged products),
  (b) the number of example rows the abstract column uses,
  (c) the probe pool (i.i.d. vs enriched) and its size.
60 tasks: the 20 of q2_main.py + 40 more random 3-4 operator tasks.

usage: python3 q2_sweep.py [--procs 12] [--extra 40]
"""
import argparse
import json
import math
import multiprocessing as mp
import random
import time

from seqlib import (L, I, OPNAMES, HAND6, QBYNAME, Quotient, product_quotient, build_tables,
                    term_str)
from q2search import (plain_search, count_under_order, expected_random_order, pruned_search,
                      soft_counts, ref_audit)
from q2tasks import review_tasks, training_tasks, my_tasks, gen_tasks

CONFIGS = {}        # name -> (tables, absrows)
TASKS = []


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def job(ti):
    task = TASKS[ti]
    rng = random.Random(777 + ti)
    env, target, ttype = task['env'], task['target'], task['ttype']
    ps = plain_search(env, target, task['size'])
    ns = ps['found_size']
    lv = ps['levels'][ns - 1]
    out = dict(name=task['name'], term=term_str(task['term']), n_ops=len(task['ops']),
               size=task['size'], found_size=ns,
               plain_lib=ps['below'] + count_under_order(lv['n'], lv['hit'], range(len(lv['n']))),
               plain_rand=ps['below'] + expected_random_order(lv['n'], lv['hit'], rng, 500),
               plain_store=ps['store_below'], plain_wall=ps['wall_s'], cfg={})
    for cname, (tb, absrows) in CONFIGS.items():
        pr = pruned_search(env, target, ttype, tb, ns, absrows=absrows)
        last = pr['last']
        r = dict(found=pr['found'], store=last['store_below'], store_j1=last['store_joint1'],
                 checks=pr['cum_checks'], wall=pr['wall_s'],
                 audit=len(ref_audit(task['term'], env, tb)))
        if pr['found']:
            sc = soft_counts(last, pr['ctx'])
            base = pr['cum_before'] + last['below']
            r['abs_lib'] = base + sc['lib']
            r['abs_opsoft'] = base + sc['op_soft']
            r['abs_rand'] = base + expected_random_order(last['fin_n'], last['fin_hit'], rng, 500)
            r['fin_n'] = sum(last['fin_n'])
        out['cfg'][cname] = r
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--procs', type=int, default=12)
    ap.add_argument('--extra', type=int, default=40)
    a = ap.parse_args()
    t0 = time.time()
    Q = QBYNAME
    m3 = product_quotient('sign*parity*order', [Q['sign'], Q['parity'], Q['order']])
    m6 = product_quotient('all6-product', HAND6)
    qsets = [
        # a constant quotient: the tables then carry only the operators' TYPES
        ('0: types only', [Quotient('type', lambda xs: 0, lambda x: 0)]),
        ('1: sign', [Q['sign']]), ('1: parity', [Q['parity']]), ('1: order', [Q['order']]),
        ('1: caplen5', [Q['caplen5']]), ('1: lenmod2', [Q['lenmod2']]), ('1: isempty', [Q['isempty']]),
        ('3: sign+parity+order', [Q['sign'], Q['parity'], Q['order']]),
        ('3: caplen5+lenmod2+isempty', [Q['caplen5'], Q['lenmod2'], Q['isempty']]),
        ('3: sign+order+caplen5', [Q['sign'], Q['order'], Q['caplen5']]),
        ('6: all', HAND6),
        ('1 merged: sign*parity*order', [m3]),
        ('4: merged3 + 3 length', [m3, Q['caplen5'], Q['lenmod2'], Q['isempty']]),
        ('1 merged: product of all 6', [m6]),
    ]
    states = {}
    for name, qs in qsets:
        tb = build_tables(qs, M=2000, kind='iid', seed=0)
        CONFIGS[name] = (tb, None)
        states[name] = (tb.n_states(), tb.n_entries())
    tb6 = CONFIGS['6: all'][0]
    for r in (1, 2, 4):
        CONFIGS['6: all, abstract rows=%d' % r] = (tb6, r)
    for kind, M in (('iid', 200), ('iid', 20000), ('enriched', 200), ('enriched', 2000),
                    ('enriched', 20000)):
        tb = build_tables(HAND6, M=M, kind=kind, seed=0)
        name = '6: all, %s M=%d' % (kind, M)
        CONFIGS[name] = (tb, None)
        states[name] = (tb.n_states(), tb.n_entries())
    train = training_tasks(80, 100)
    rev = review_tasks(1)
    ex = {term_str(t['term']) for t in train} | {term_str(t['term']) for t in rev}
    mine = my_tasks(200, exclude=ex)
    ex |= {term_str(t['term']) for t in mine}
    extra = gen_tasks(a.extra, 300, OPNAMES, prefix='X', exclude=ex)
    TASKS.extend(rev + mine + extra)
    print('# Q2 sweep: %d tasks, %d configurations, %d processes; setup %.1f s' %
          (len(TASKS), len(CONFIGS), a.procs, time.time() - t0))
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, range(len(TASKS)), chunksize=1)
    print('search time %.1f s' % (time.time() - t0))
    print('tasks by found size:', {s: sum(1 for r in res if r['found_size'] == s) for s in range(2, 7)})
    hdr = ('configuration', 'states', 'entries', 'miss', 'aud', 'cand_lib', 'cand_rnd', '[min', 'max]',
           'store', 'store_j1', 'lookups/ev', 'wall')
    print('\n%-34s %-22s %7s %4s %4s %8s %8s %6s %6s %6s %8s %10s %6s' % hdr)
    summary = {}
    for cname in CONFIGS:
        rs = [(r, r['cfg'][cname]) for r in res]
        ok = [(r, c) for r, c in rs if c['found']]
        gl = [r['plain_lib'] / c['abs_opsoft'] for r, c in ok]
        gr = [r['plain_rand'] / c['abs_rand'] for r, c in ok]
        st = [r['plain_store'] / max(1, c['store']) for r, c in ok]
        sj = [r['plain_store'] / max(1, c['store_j1']) for r, c in ok]
        lk = sum(c['checks'] for r, c in ok) / max(1, sum(c['abs_lib'] for r, c in ok))
        wl = gmean([r['plain_wall'] / c['wall'] for r, c in ok if c['wall'] > 0 and r['plain_wall'] > 0.01])
        s = states.get(cname, ('', ''))
        miss = len(rs) - len(ok)
        aud = sum(1 for r, c in rs if c['audit'])
        summary[cname] = dict(miss=miss, audit_tasks=aud, cand_lib=gmean(gl), cand_rnd=gmean(gr),
                              mn=min(gr), mx=max(gr), store=gmean(st), store_j1=gmean(sj))
        print('%-34s %-22s %7s %4d %4d %7.2fx %7.2fx %6.1f %6.1f %5.2fx %7.2fx %10.2f %5.2fx' %
              (cname, str(s[0]), s[1], miss, aud, gmean(gl), gmean(gr), min(gr), max(gr), gmean(st),
               gmean(sj), lk, wl))
    print('''
columns: states = abstract values per quotient (list + int); entries = table rows;
miss = tasks NOT found at the size plain OE finds them (soundness failures);
aud = tasks whose reference program uses a transition missing from the tables;
cand_lib = geometric mean of plain(library order) / abs+soft-op, all passes counted;
cand_rnd = geometric mean of plain / abs, both averaged over random operator orders, with [min, max];
store, store_j1 = geometric mean ratio of classes stored below the last level;
lookups/ev = table look-ups per candidate evaluated; wall = geometric mean wall-time ratio
(complete last level on both sides, tasks with plain wall > 10 ms).''')
    for cname in CONFIGS:
        bad = [(r['name'], r['term']) for r in res if not r['cfg'][cname]['found']]
        if bad:
            print('MISSES under %-34s: %s' % (cname, bad))
    json.dump(dict(summary=summary, res=res), open('q2_sweep.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
