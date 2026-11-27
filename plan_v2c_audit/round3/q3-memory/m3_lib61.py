"""M1 on the 61-operator library with sampled (unsound) verb tables.

The 60 tasks of the earlier q2_sweep.py (same seeds), six hand-listed quotients, tables from
2,000 i.i.d. probes per operator (and a 200-probe variant).  The target's size is unknown: the
bound is deepened N = 1, 2, ... with a restart per pass; evaluations are summed over all passes
and memory is the peak over all passes.  For each configuration: answers lost (not found at
the size plain search finds them), entries in the dedupe table and in the bank, Python bytes
(sum of sys.getsizeof over every distinct object reachable from the two containers).

  D   : no filter before evaluation; a class is discarded after evaluation if s + h > N
  F   : the earlier reproduction's method (iii): filter before evaluation + the same discard
  FL  : F + one-step look-ahead on size N-1 (kept only if some unary operator may reach the target)
  -b  : insert into the dedupe table, then test (bank-only pruning)
  -c  : test, then insert (the review's rule)

usage: python3 m3_lib61.py [--procs 12] [--probes 2000]
"""
import argparse
import json
import math
import multiprocessing as mp
import time

from seqlib import OPNAMES, HAND6, build_tables, term_str
from q2search import AbsCtx
from q2tasks import review_tasks, training_tasks, my_tasks, gen_tasks
from mem61 import plain_pass, deepen61, lev_roots
from memlib import deep_size

TASKS = []
TABLES = {}
CONF = [('D-b', False, 'b', False), ('D-c', False, 'c', False),
        ('F-b', True, 'b', False), ('F-c', True, 'c', False),
        ('FL-b', True, 'b', True), ('FL-c', True, 'c', True)]


def gm(v):
    v = [x for x in v if x and x > 0]
    return math.exp(sum(math.log(x) for x in v) / len(v)) if v else float('nan')


def job(ti):
    task = TASKS[ti]
    env, target, ttype = task['env'], task['target'], task['ttype']
    pa = plain_pass(env, target, task['size'], asgo=True)
    ns = pa['hit_size']
    out = dict(name=task['name'], term=term_str(task['term']), ns=ns, plain_eval=pa['evaluated'],
               plain_at_hit=pa['seen_n'], plain_below=pa['seen_below'],
               plain_at_hit_bytes=deep_size([pa['seen'], pa['lev']]))
    del pa
    pg = plain_pass(env, target, ns)                  # size given: sizes < ns stored
    assert pg['hit'] and pg['seen_n'] == out['plain_below']
    out['plain_bytes'] = deep_size([pg['seen'], pg['lev']])
    out['plain_top'] = pg['per_level'].get(ns - 1, 0)      # classes of size ns-1
    del pg
    out['cfg'] = {}
    for tname, tb in TABLES.items():
        ctx = AbsCtx(tb, target, ttype)
        for cname, pf, sm, la in CONF:
            d = deepen61(env, target, ttype, tb, ns, pf, sm, la, ctx=ctx)
            out['cfg'][tname + '|' + cname] = d
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--procs', type=int, default=12)
    a = ap.parse_args()
    t0 = time.time()
    TABLES['2000'] = build_tables(HAND6, M=2000, kind='iid', seed=0)
    TABLES['200'] = build_tables(HAND6, M=200, kind='iid', seed=0)
    train = training_tasks(80, 100)
    rev = review_tasks(1)
    ex = {term_str(t['term']) for t in train} | {term_str(t['term']) for t in rev}
    mine = my_tasks(200, exclude=ex)
    ex |= {term_str(t['term']) for t in mine}
    extra = gen_tasks(40, 300, OPNAMES, prefix='X', exclude=ex)
    TASKS.extend(rev + mine + extra)
    print('# M1 on the 61-operator library: %d tasks, 6 hand quotients; setup %.1f s' % (len(TASKS), time.time() - t0))
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, range(len(TASKS)), chunksize=1)
    print('search %.1f s; tasks by found size: %s' %
          (time.time() - t0, {s: sum(1 for r in res if r['ns'] == s) for s in range(2, 7)}))
    n = len(res)
    P = sum(r['plain_below'] for r in res)
    PB = sum(r['plain_bytes'] for r in res)
    print('\nplain search, summed over the %d tasks: evaluations %d; classes below the hit size %d '
          '(%.1f MB python); classes held at the moment of the hit if every size is stored as it is '
          'enumerated %d (%.1f MB)' %
          (n, sum(r['plain_eval'] for r in res), P, PB / 1e6, sum(r['plain_at_hit'] for r in res),
           sum(r['plain_at_hit_bytes'] for r in res) / 1e6))
    ptop = sum(r['plain_top'] for r in res)
    print('plain, of those %d classes: %d (%.0f%%) have size N*-1 and are used only by unary operators '
          'at the last size; held as hashes only they leave %d full classes: %.2fx fewer full classes '
          '(geometric mean %.2fx)' %
          (P, ptop, 100.0 * ptop / P, P - ptop, P / (P - ptop),
           gm([r['plain_below'] / max(1, r['plain_below'] - r['plain_top']) for r in res])))
    for tname in TABLES:
        print('\n== tables from %s i.i.d. probes per operator; size unknown, restart per bound, peak over passes ==' % tname)
        print('%-6s %5s | %9s %9s %9s | %10s %10s | %9s %9s | %10s %10s | %8s' %
              ('config', 'lost', 'seen', 'bank', 'sum', 'gain seen', '(gmean)', 'MB python', 'gain', 'evals',
               'gain', 'flips'))
        for cname, pf, sm, la in CONF:
            k = tname + '|' + cname
            ok = [r for r in res if r['cfg'][k]['found'] and r['cfg'][k]['N'] == r['ns']]
            lost = n - len(ok)
            se = sum(r['cfg'][k]['seen'] for r in res)
            ba = sum(r['cfg'][k]['bank'] for r in res)
            by = sum(r['cfg'][k]['bytes'] for r in res)
            evs = sum(r['cfg'][k]['evaluated'] for r in ok)
            pev = sum(r['plain_eval'] for r in ok)
            print('%-6s %5d | %9d %9d %9d | %9.2fx %9.2fx | %9.1f %8.2fx | %10d %9.2fx | %8d' %
                  (cname, lost, se, ba, se + ba, P / se,
                   gm([r['plain_below'] / max(1, r['cfg'][k]['seen']) for r in res]), by / 1e6,
                   gm([r['plain_bytes'] / max(1, r['cfg'][k]['bytes']) for r in res]),
                   evs, gm([r['plain_eval'] / r['cfg'][k]['evaluated'] for r in ok]),
                   sum(r['cfg'][k]['flips'] for r in res)))
        for cname in ('F-c', 'FL-c'):
            k = tname + '|' + cname
            ff = sum(r['cfg'][k]['full_fused'] for r in res)
            hf = sum(r['cfg'][k]['hash_fused'] for r in res)
            print('   %-5s with size N-1 held as hashes only: %d full classes + %d hashes; full classes vs '
                  'plain (all sizes below N* full) %.2fx, vs plain with its own top size as hashes %.2fx '
                  '(geometric means %.2fx, %.2fx)' %
                  (cname, ff, hf, P / max(1, ff), (P - ptop) / max(1, ff),
                   gm([r['plain_below'] / max(1, r['cfg'][k]['full_fused']) for r in res]),
                   gm([(r['plain_below'] - r['plain_top']) / max(1, r['cfg'][k]['full_fused']) for r in res])))
        lostn = {c: [r['name'] for r in res if not (r['cfg'][tname + '|' + c]['found'] and
                                                     r['cfg'][tname + '|' + c]['N'] == r['ns'])]
                 for c, *_ in CONF}
        print('   lost tasks: %s' % {c: v for c, v in lostn.items() if v})
        same = sum(1 for r in res if r['cfg'][tname + '|F-b']['bank'] == r['cfg'][tname + '|F-c']['bank'] and
                   r['cfg'][tname + '|D-b']['bank'] == r['cfg'][tname + '|D-c']['bank'] and
                   r['cfg'][tname + '|FL-b']['bank'] == r['cfg'][tname + '|FL-c']['bank'])
        print('   bank of -b equals bank of -c in size on %d of %d tasks; evaluations equal on %d' %
              (same, n, sum(1 for r in res if all(
                  r['cfg'][tname + '|' + x + '-b']['evaluated'] == r['cfg'][tname + '|' + x + '-c']['evaluated']
                  for x in ('D', 'F', 'FL')))))
    # per-task detail for the review's eight
    print('\n== the review\'s eight tasks, 2,000 probes: classes held (dedupe table / bank) ==')
    print('%-5s %2s | %8s | %-15s | %-15s | %-15s | %-15s | %-13s' %
          ('', 'N*', 'plain', 'D-b', 'D-c', 'F-b', 'F-c', 'FL-c'))
    for r in res[:8]:
        c = r['cfg']
        print('%-5s %2d | %8d | %7d/%-7d | %7d/%-7d | %7d/%-7d | %7d/%-7d | %6d/%-6d' %
              (r['name'], r['ns'], r['plain_below'],
               c['2000|D-b']['seen'], c['2000|D-b']['bank'], c['2000|D-c']['seen'], c['2000|D-c']['bank'],
               c['2000|F-b']['seen'], c['2000|F-b']['bank'], c['2000|F-c']['seen'], c['2000|F-c']['bank'],
               c['2000|FL-c']['seen'], c['2000|FL-c']['bank']))
    json.dump(res, open('m3_lib61.json', 'w'), indent=1)
    print('\ntotal %.1f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
