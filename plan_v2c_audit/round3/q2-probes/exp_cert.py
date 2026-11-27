"""Which verb tables could be certified rather than tested, and how much of the
candidate gain needs the uncertified ones?

1. TRUTH ESTIMATE U: union of the transitions seen by five probe rules at 30,000
   probes x 2 seeds, plus an exhaustive enumeration of a bounded domain (scope E3).
2. How many entries (input keys) of U are deterministic (one output label); how
   many (operator, quotient) tables are deterministic throughout.
3. Exhaustive small scopes E1, E2 as probe sets: which transitions of U they miss.
4. Length-regular operators: output length is a function of the input lengths
   (checked on every probe); for those, the three length quotients' tables follow
   from a function on lengths 0..N, a finite abstract domain.
5. Searches on S300 (and EDGE-R/EDGE-W if their plain caches exist) with:
   all of U; only deterministic entries; only fully deterministic tables; only the
   cheaply certifiable tier; nothing (types only); the exhaustive scopes as tables.

usage: python3 exp_cert.py [--procs 12] [--sets S300,EDGE-R,EDGE-W]
"""
import argparse
import time
from collections import defaultdict

from seqlib import L, I, OPNAMES, OPSIG, HAND6
from probegen import make_tables, gen_probes, PTables
from tabletools import trans_of, union_trans, tables_from_trans, all_lists, scope_probes
from tasksets import get_tasks
from harness import plain_cached, run_configs, summarize

QN = [q.name for q in HAND6]
LENQ = [QN.index(n) for n in ('caplen5', 'lenmod2', 'isempty')]


def scope(name):
    if name == 'E1':
        return scope_probes(all_lists(4, 1), [(all_lists(3, 1), all_lists(3, 1))],
                            range(-3, 4), all_lists(3, 1))
    if name == 'E2':
        return scope_probes(all_lists(5, 2), [(all_lists(3, 2), all_lists(3, 2))],
                            range(-6, 7), all_lists(4, 2))
    if name == 'E3':
        l1 = list(dict.fromkeys(all_lists(6, 2) + all_lists(10, 1)))
        return scope_probes(l1, [(all_lists(4, 2), all_lists(4, 2))], range(-12, 13),
                            all_lists(5, 2))
    raise ValueError(name)


def length_regular(probe_sets):
    """opname -> True if len(output) is a function of the lengths of the list
    arguments on every probe (list-valued operators only)."""
    reg = {}
    for name in OPNAMES:
        at, rt = OPSIG[name]
        if rt != L:
            continue
        f = defaultdict(set)
        for probes in probe_sets:
            argcols, res = probes[name]
            lens = [list(map(len, c)) for c, t in zip(argcols, at) if t == L]
            for key, r in zip(zip(*lens), res):
                f[key].add(len(r))
        reg[name] = all(len(s) == 1 for s in f.values())
    return reg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--procs', type=int, default=12)
    ap.add_argument('--sets', default='S300')
    a = ap.parse_args()
    t0 = time.time()
    sampled = []
    big = {}
    for rule in ('iid', 'push3', 'bank3', 'scalemix', 'hand'):
        for sd in (0, 1):
            pr = gen_probes(rule, 30000, sd, HAND6)
            if (rule, sd) in (('bank3', 0), ('push3', 0), ('iid', 0)):
                big[rule] = pr
            sampled.append(trans_of(PTables(HAND6, pr)))
    US = union_trans(sampled)
    print('# sampled union built, %.0f s' % (time.time() - t0), flush=True)
    sc = {}
    for nm in ('E1', 'E2', 'E3'):
        pr, sizes = scope(nm)
        sc[nm] = (trans_of(PTables(HAND6, pr)), sizes, pr if nm == 'E2' else None)
        print('# scope %s: probes per signature %s, %.0f s' % (nm, sizes, time.time() - t0),
              flush=True)
    U = union_trans([US, sc['E3'][0]])

    def npairs(t):
        return sum(len(s) for d in t.values() for s in d.values())

    def nent(t):
        return sum(len(d) for d in t.values())

    def missing(t, ref):
        """(key, label) pairs of ref whose key t HAS but whose label t lacks (defects),
        and pairs whose key t lacks altogether (harmless: unseen = anything)."""
        bad, unseen = [], 0
        for jn, d in ref.items():
            td = t.get(jn, {})
            for k, s in d.items():
                if k not in td:
                    unseen += len(s)
                else:
                    bad.extend((jn, k, x) for x in s - td[k])
        return bad, unseen

    print('\n1. Truth estimate U: %d entries (input keys), %d (key, output) pairs' % (nent(U), npairs(U)))
    b1, u1 = missing(US, sc['E3'][0])
    b2, u2 = missing(sc['E3'][0], US)
    print('   sampled union (10 tables x 30,000 probes) lacks %d pairs that scope E3 has '
          '(and %d on keys it never saw)' % (len(b1), u1))
    for jn, k, x in b1[:12]:
        print('      %s / %s  %s -> %s' % (jn[1], QN[jn[0]], k, x))
    print('   scope E3 lacks %d pairs that the sampled union has (and %d on keys outside the scope)'
          % (len(b2), u2))
    by = defaultdict(int)
    for jn, k, x in b2:
        by[(jn[1], QN[jn[0]])] += 1
    print('      by (operator, quotient): %s' % dict(sorted(by.items(), key=lambda z: -z[1])[:14]))

    print('\n2. Deterministic entries of U (one output label), by quotient')
    print('   %-8s %8s %8s %7s | %7s %10s %10s' %
          ('quotient', 'entries', 'determ.', 'share', 'tables', 'all-determ', 'trivial'))
    tot = [0, 0, 0, 0, 0]
    det_tables = set()
    trivial = set()
    for j, qn in enumerate(QN):
        e = d = tabs = dt = tv = 0
        for name in OPNAMES:
            t = U[(j, name)]
            e += len(t)
            nd = sum(1 for s in t.values() if len(s) == 1)
            d += nd
            tabs += 1
            if nd == len(t):
                dt += 1
                det_tables.add((j, name))
            outs = set().union(*t.values())
            if len(outs) == 1:
                tv += 1
                trivial.add((j, name))
        print('   %-8s %8d %8d %6.1f%% | %7d %10d %10d' % (qn, e, d, 100.0 * d / e, tabs, dt, tv))
        for i, v in enumerate((e, d, tabs, dt, tv)):
            tot[i] += v
    print('   %-8s %8d %8d %6.1f%% | %7d %10d %10d' %
          ('ALL', tot[0], tot[1], 100.0 * tot[1] / tot[0], tot[2], tot[3], tot[4]))
    print('   ("trivial" = the table has a single output label overall, e.g. a quotient that is '
          'constant on ints; it filters nothing)')
    nontriv_det = sum(1 for jn in det_tables if jn not in trivial)
    print('   fully deterministic and not trivial: %d of %d tables' % (nontriv_det, tot[2]))

    print('\n3. Exhaustive scopes used as probe sets, against U')
    print('   %-3s %-52s %8s %8s %12s %10s' %
          ('', 'probes per signature', 'entries', 'pairs', 'pairs lacked', 'tables hit'))
    for nm in ('E1', 'E2', 'E3'):
        t, sizes, _ = sc[nm]
        bad, unseen = missing(t, U)
        print('   %-3s %-52s %8d %8d %12d %10d' %
              (nm, sizes, nent(t), npairs(t), len(bad), len({jn for jn, k, x in bad})))
        by = defaultdict(int)
        for jn, k, x in bad:
            by[(jn[1], QN[jn[0]])] += 1
        if by:
            print('       lacked, by (operator, quotient): %s' %
                  dict(sorted(by.items(), key=lambda z: -z[1])[:10]))

    print('\n4. Length-regular operators (output length a function of input lengths on every probe '
          'of E2, iid, push3, bank3 at 30,000)')
    reg = length_regular([sc['E2'][2], big['iid'], big['push3'], big['bank3']])
    print('   list-valued operators: %d; length-regular: %d; not: %s' %
          (len(reg), sum(reg.values()), [n for n, v in reg.items() if not v]))
    cert = set(trivial)
    for j in LENQ:
        for name, v in reg.items():
            if v:
                cert.add((j, name))
    ce = sum(len(U[jn]) for jn in cert)
    cnt = sum(len(U[jn]) for jn in cert if jn not in trivial)
    print('   cheaply certifiable tier = trivial tables (%d) + length quotients on length-regular '
          'operators (%d): %d of %d tables, %d of %d entries (%d entries in non-trivial tables)' %
          (len(trivial), len(cert) - len(trivial), len(cert), tot[2], ce, tot[0], cnt))
    # are those certified tables deterministic?
    cd = sum(1 for jn in cert if jn not in trivial and jn in det_tables)
    print('   of the %d non-trivial certified tables, %d are deterministic throughout' %
          (len(cert) - len(trivial), cd))

    configs = {
        'U: all entries': tables_from_trans(HAND6, U),
        'U: deterministic entries only': tables_from_trans(HAND6, U, lambda j, n, k, s: len(s) == 1),
        'U: fully deterministic tables only': tables_from_trans(
            HAND6, U, lambda j, n, k, s: (j, n) in det_tables),
        'U: non-deterministic entries only': tables_from_trans(
            HAND6, U, lambda j, n, k, s: len(s) > 1),
        'U: certifiable tier only (length-regular)': tables_from_trans(
            HAND6, U, lambda j, n, k, s: (j, n) in cert),
        'U: all but the certifiable tier': tables_from_trans(
            HAND6, U, lambda j, n, k, s: (j, n) not in cert),
        'no entries (types only)': tables_from_trans(HAND6, U, lambda j, n, k, s: False),
        'scope E1 as the tables': tables_from_trans(HAND6, sc['E1'][0]),
        'scope E2 as the tables': tables_from_trans(HAND6, sc['E2'][0]),
        'scope E3 as the tables': tables_from_trans(HAND6, sc['E3'][0]),
    }
    print('\n5. Searches.  entries = input keys used for filtering; lost = answers lost; '
          'AUD = tasks with a reference-path defect; gain = candidates vs plain (order-averaged)')
    for setname in a.sets.split(','):
        tasks = get_tasks(setname)
        plain = plain_cached(setname, tasks, a.procs)
        res = run_configs(tasks, plain, configs, a.procs)
        print('\n   task set %s (%d tasks)' % (setname, len(tasks)))
        print('   %-44s %8s %5s %5s %8s %7s %8s' %
              ('tables', 'entries', 'lost', 'AUD', 'gain', 'store', 'storeJ1'))
        g = {}
        for c, tb in configs.items():
            s = summarize(c, tasks, plain, res)
            g[c] = s['gain']
            print('   %-44s %8d %5d %5d %7.2fx %6.2fx %7.2fx' %
                  (c, tb.n_entries(), s['miss'], s['aud'], s['gain'], s['store'], s['store_j1']))
        import math
        full, floor = g['U: all entries'], g['no entries (types only)']
        for c in ('U: deterministic entries only', 'U: fully deterministic tables only',
                  'U: certifiable tier only (length-regular)', 'U: non-deterministic entries only',
                  'U: all but the certifiable tier'):
            print('   share of the gain kept by "%s": %.0f%% of the factor, %.0f%% of the log-gain '
                  'above types-only' % (c, 100 * g[c] / full,
                                        100 * math.log(g[c] / floor) / math.log(full / floor)))
    print('\ntotal wall %.0f s' % (time.time() - t0))


if __name__ == '__main__':
    main()
