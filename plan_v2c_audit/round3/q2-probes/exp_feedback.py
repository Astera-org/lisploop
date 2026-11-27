"""P2: is online feedback still worth having once the probes are good?
And the cheapest alternative guard (an input key counts as unseen unless probed
at least k times).

Part 1 (audit, long streams, 10 table seeds).  A stream of 4,000 random tasks.
  static   : tables never change; count tasks with a reference-path defect.
  feedback : whenever a task's solution uses a transition the tables exclude,
             that transition is added (the key must already exist; an unseen key
             stays unseen).  This is the reviewer's 5-line rule, applied whenever
             a solved program is checked against the tables.
  Reported per quarter of the stream, per 1,000 tasks.

Part 2 (real searches).  For the configurations already searched by exp_main.py
  (static result per task read from its json), replay the task stream in order:
  a task that the static tables lose is searched again with the tables as updated
  so far; if still lost, the fallback solves it and its transitions are added.
  (Adding transitions only loosens the filter, so a task the static tables find is
  still found; only the lost ones need a second search.)
  'fallback-only' adds transitions only after a loss; 'every solution' also adds
  the excluded transitions of tasks that were found.

Part 3 (real searches).  Guards on S300 and EDGE-R: min_count(k) for k = 5, 10, 30
  and verify-quotients' guard(30, 1).

usage: python3 exp_feedback.py --best bank2 [--procs 12] [--parts 1,2,3]
"""
import argparse
import glob
import json
import multiprocessing as mp
import time

from seqlib import HAND6
from probegen import make_tables
from tasksets import get_tasks
from harness import (plain_cached, run_configs, summarize, ref_transitions, defects, search_one)
from exp_audit import load_stream

STREAM = []


def audit_job(arg):
    rule, M, sd = arg
    tb = make_tables(rule, M, sd, HAND6)
    n = len(STREAM)
    q = n // 4
    stat = [0] * 4
    fb = [0] * 4
    tf = tb.clone()
    upd = 0
    for i, tr in enumerate(STREAM):
        k = min(3, i // q)
        if defects(tr, tb):
            stat[k] += 1
        d = defects(tr, tf)
        if d:
            fb[k] += 1
            for (name, j, key, ar) in d:
                upd += tf.add_transition(j, name, key, ar)
    return arg, [1000.0 * x / q for x in stat], [1000.0 * x / q for x in fb], upd


def part1(rules, Ms, seeds, procs):
    STREAM[:] = load_stream('RAND7000', 4000)
    jobs = [(r, M, sd) for r in rules for M in Ms for sd in range(seeds)]
    with mp.get_context('fork').Pool(procs) as pool:
        res = {arg: (s, f, u) for arg, s, f, u in pool.map(audit_job, jobs, chunksize=1)}
    print('\nPart 1.  4,000-task stream; tasks with a reference-path defect per 1,000, by quarter of '
          'the stream; mean over %d table seeds' % seeds)
    print('%-14s %6s | %-31s | %-31s | %7s' %
          ('rule', 'M', 'static   Q1    Q2    Q3    Q4', 'feedback Q1    Q2    Q3    Q4', 'updates'))
    for r in rules:
        for M in Ms:
            s = [sum(res[(r, M, sd)][0][k] for sd in range(seeds)) / seeds for k in range(4)]
            f = [sum(res[(r, M, sd)][1][k] for sd in range(seeds)) / seeds for k in range(4)]
            u = sum(res[(r, M, sd)][2] for sd in range(seeds)) / seeds
            print('%-14s %6d |      %s |      %s | %7.1f' %
                  (r, M, ' '.join('%5.1f' % x for x in s), ' '.join('%5.1f' % x for x in f), u))


def part2(sets, procs, rules):
    print('\nPart 2.  Real searches, stream replayed in order (task sets %s, one after another)' % sets)
    static = {}          # cname -> list of found flags over the concatenated stream
    tasks, plain = [], []
    for setname in sets:
        ts = get_tasks(setname)
        tasks += ts
        plain += plain_cached(setname, ts, procs)
        merged = {}
        for path in sorted(glob.glob('exp_main_%s_*.json' % setname)):
            J = json.load(open(path))
            for i, r in enumerate(J['res']):
                for c, v in r.items():
                    rule = c.split('|')[0]
                    if rule not in rules:
                        continue
                    if path.endswith('_main.json') and 'strat' in rule:
                        continue          # first run: strat* there = strat*d now
                    merged.setdefault(c, [None] * len(ts))[i] = v['found']
        for c, fl in merged.items():
            static.setdefault(c, []).append(fl)
    static = {c: sum(v, []) for c, v in static.items()
              if len(v) == len(sets) and all(x is not None for fl in v for x in fl)}
    trs = [ref_transitions(t['term'], t['env'], HAND6) for t in tasks]
    print('  %d tasks; %d configurations present in every set' % (len(tasks), len(static)))
    agg = {}
    for c in sorted(static):
        rule, M, sd = c.split('|')
        if rule.startswith('old'):
            continue
        fl = static[c]
        lost_static = [i for i, f in enumerate(fl) if not f]
        out = {}
        for mode in ('fallback-only', 'every solution'):
            tb = make_tables(rule, int(M), int(sd), HAND6).clone()
            still = 0
            for i in range(len(tasks)):
                if fl[i]:
                    if mode == 'every solution':
                        for (name, j, key, ar) in defects(trs[i], tb):
                            tb.add_transition(j, name, key, ar)
                    continue
                r = search_one(tasks[i], plain[i], tb, 4242 + i, trials=1)
                if not r['found']:
                    still += 1
                for (name, j, key, ar) in defects(trs[i], tb):
                    tb.add_transition(j, name, key, ar)
            out[mode] = still
            out[mode + ' grew'] = getattr(tb, 'dom_grew', 0)
        a = agg.setdefault((rule, int(M)), [0, 0, 0, 0, 0])
        a[0] += len(lost_static)
        a[1] += out['fallback-only']
        a[2] += out['every solution']
        a[3] += 1
        a[4] += out['fallback-only grew'] + out['every solution grew']
    print('  answers lost over the stream, summed over table seeds (task-searches = %d x seeds)' %
          len(tasks))
    print('  (assumes a task found by the static tables is still found after feedback: adding output '
          'labels only loosens the filter, unless a label new to the whole domain is added; '
          'such additions are counted in the last column and should be 0)')
    print('  %-14s %6s %6s | %8s %14s %15s %8s' %
          ('rule', 'M', 'seeds', 'static', 'fallback-only', 'every solution', 'domgrew'))
    for (rule, M), a in sorted(agg.items()):
        print('  %-14s %6d %6d | %8d %14d %15d %8d' % (rule, M, a[3], a[0], a[1], a[2], a[4]))


GUARDS = ('none', 'min_count(10)', 'min_count(30)', 'guard(30,1)')
GUARD_M = (300, 1000)


def part3(best, procs, sets):
    print('\nPart 3.  Guards (real searches).  min_count(k): an input key is unseen unless probed '
          '>= k times; guard(30,1): also every output seen more than once')
    configs = {}
    for rule in ('iid', best):
        for M in GUARD_M:
            for sd in (0, 1):
                tb = make_tables(rule, M, sd, HAND6)
                base = '%s|%d|%d' % (rule, M, sd)
                configs[base + '|none'] = tb
                for k in (10, 30):
                    configs[base + '|min_count(%d)' % k] = tb.min_count(k)
                configs[base + '|guard(30,1)'] = tb.guard(30, 1)
    for setname in sets:
        tasks = get_tasks(setname)
        plain = plain_cached(setname, tasks, procs)
        res = run_configs(tasks, plain, configs, procs)
        print('\n  task set %s (%d tasks), summed over 2 table seeds' % (setname, len(tasks)))
        print('  %-14s %6s %-14s | %8s %5s %5s %8s' %
              ('rule', 'M', 'guard', 'entries', 'lost', 'AUD', 'gain'))
        for rule in ('iid', best):
            for M in GUARD_M:
                for g in GUARDS:
                    cs = ['%s|%d|%d|%s' % (rule, M, sd, g) for sd in (0, 1)]
                    ss = [summarize(c, tasks, plain, res) for c in cs]
                    print('  %-14s %6d %-14s | %8.0f %5d %5d %7.2fx' %
                          (rule, M, g, sum(configs[c].n_entries() for c in cs) / 2,
                           sum(s['miss'] for s in ss), sum(s['aud'] for s in ss),
                           sum(s['gain'] for s in ss) / 2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--best', default='bank2')
    ap.add_argument('--procs', type=int, default=12)
    ap.add_argument('--parts', default='1,2,3')
    ap.add_argument('--sets', default='S300,EDGE-R,EDGE-W')
    ap.add_argument('--p2rules', default='iid,push2,bank2,oelog3,hand,scalemix,strat1,bank2+strat1')
    ap.add_argument('--p3sets', default='S300,EDGE-R')
    a = ap.parse_args()
    t0 = time.time()
    parts = a.parts.split(',')
    if '1' in parts:
        part1(['iid', 'strat2', 'bank2', 'oelog3', 'bank2+strat2', 'hand'],
              [100, 300, 1000, 3000], 10, a.procs)
    if '2' in parts:
        part2(a.sets.split(','), a.procs, a.p2rules.split(','))
    if '3' in parts:
        part3(a.best, a.procs, a.p3sets.split(','))
    print('\ntotal wall %.0f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
