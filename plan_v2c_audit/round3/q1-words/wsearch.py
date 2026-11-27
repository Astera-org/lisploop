"""What is a vocabulary worth in search?  Same search (q2search.py), same 60 tasks and same
accounting as verify-quotients/q2_auto.py and q2_sweep.py: order-averaged plain baseline,
every deepening pass counted, verb tables from 2,000 i.i.d. probes per operator (seed 0).

usage: python3 wsearch.py VOCABS.json TAG [--procs 14] [--tabseed 0] [--M 2000]
VOCABS.json: {name: [[list-term repr, int-term repr or "None"], ...]}; a name starting with
'@' is a built-in control ('@hand6', '@types').
writes search_TAG.log and search_TAG.json
"""
import argparse
import ast
import json
import math
import multiprocessing as mp
import time

from seqlib import OPNAMES, HAND6, QBYNAME, Quotient, build_tables, term_str
from q2common import compare
from q2tasks import review_tasks, training_tasks, my_tasks, gen_tasks
from wordlib import compile_term, tstr

CONFIGS = {}
TASKS = []


def gmean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else float('nan')


def job(ti):
    return compare(TASKS[ti], CONFIGS, 777 + ti, trials=300)


# The reviewer's hand-written words (verify_ram_and_nmi.py lines 139-151, verbatim), so that its
# two six-word vocabularies can be measured in this search.  Not used by any selection here.
REV_WORDS = {
    'len_cap6':   lambda s: min(len(s), 6),
    'len_cap5':   lambda s: min(len(s), 5),
    'len_cap4':   lambda s: min(len(s), 4),
    'len_mod3':   lambda s: len(s) % 3,
    'len_cap3':   lambda s: min(len(s), 3),
    'len_mod2':   lambda s: len(s) % 2,
    'all_even':   lambda s: 'E' if not s else ('EV' if all(x%2==0 for x in s) else ('OD' if all(x%2!=0 for x in s) else 'M')),
    'all_nonneg': lambda s: 'E' if not s else ('P' if all(x>0 for x in s) else ('N0' if all(x>=0 for x in s) else ('NEG' if all(x<0 for x in s) else 'M'))),
    'is_sorted':  lambda s: 'S01' if len(s)<=1 else ('C' if len(set(s))==1 else ('ASC' if all(s[i]<=s[i+1] for i in range(len(s)-1)) else ('DSC' if all(s[i]>=s[i+1] for i in range(len(s)-1)) else 'U'))),
    'max_le_2':   lambda s: (max(s) <= 2) if s else True,
    'has_zero':   lambda s: 0 in s,
}


def quotients(spec):
    qs = []
    for (lr, ir) in spec:
        if lr.startswith('@rev:'):                      # a reviewer word; int side given as a term or None
            it = ast.literal_eval(ir)
            qs.append(Quotient('reviewer %s | int: %s' % (lr[5:], tstr(it) if it is not None else 'trivial'),
                               REV_WORDS[lr[5:]], compile_term(it) if it is not None else (lambda v: 0)))
            continue
        if lr.startswith('@hand:'):                     # a hand-listed quotient, unchanged
            qs.append(QBYNAME[lr[6:]])
            continue
        if lr.startswith('@handbool:'):                 # its list side collapsed to one Boolean
            q = QBYNAME[lr[10:]]
            S = frozenset(ast.literal_eval(ir))
            qs.append(Quotient('%s in %s' % (q.name, sorted(S)),
                               (lambda f, S: (lambda xs: 1 if f(xs) in S else 0))(q.f['L'], S), q.f['I']))
            continue
        lt = ast.literal_eval(lr)
        it = ast.literal_eval(ir)
        fL = compile_term(lt)
        fI = compile_term(it) if it is not None else (lambda v: 0)
        qs.append(Quotient('%s | int: %s' % (tstr(lt), tstr(it) if it is not None else 'trivial'), fL, fI))
    return qs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('vocabs')
    ap.add_argument('tag')
    ap.add_argument('--procs', type=int, default=14)
    ap.add_argument('--tabseed', type=int, default=0)
    ap.add_argument('--M', type=int, default=2000)
    a = ap.parse_args()
    t0 = time.time()
    logf = open('search_%s.log' % a.tag, 'w')

    def log(*x):
        s = ' '.join(str(v) for v in x)
        print(s)
        logf.write(s + '\n')
        logf.flush()
    specs = json.load(open(a.vocabs))
    auto = None
    for name, spec in specs.items():
        if name == '@hand6':
            qs = HAND6
        elif name == '@types':
            qs = [Quotient('type', lambda xs: 0, lambda x: 0)]
        elif name.startswith('@auto'):                  # the earlier automatic selection (autoquot.py)
            if auto is None:
                import autoquot
                auto = autoquot.select(K=10, verbose=False)[0]
            qs = auto[:int(name[5:])]
        else:
            qs = quotients(spec)
        CONFIGS[name] = (build_tables(qs, M=a.M, kind='iid', seed=a.tabseed), None)
    train = training_tasks(80, 100)
    rev = review_tasks(1)
    ex = {term_str(t['term']) for t in train} | {term_str(t['term']) for t in rev}
    mine = my_tasks(200, exclude=ex)
    ex |= {term_str(t['term']) for t in mine}
    TASKS.extend(rev + mine + gen_tasks(40, 300, OPNAMES, prefix='X', exclude=ex))
    log('# %d tasks, %d vocabularies, tables from %d probes per operator (seed %d); setup %.1f s'
        % (len(TASKS), len(CONFIGS), a.M, a.tabseed, time.time() - t0))
    with mp.get_context('fork').Pool(a.procs) as pool:
        res = pool.map(job, range(len(TASKS)), chunksize=1)
    log('search wall %.1f s' % (time.time() - t0))
    log('\n%-58s %2s %7s %4s %4s %9s %9s %6s %6s %7s %9s' %
        ('vocabulary', 'K', 'entries', 'miss', 'aud', 'cand_lib', 'cand_rnd', 'min', 'max', 'store', 'store_j1'))
    summary = {}
    for cname in CONFIGS:
        tb = CONFIGS[cname][0]
        rs = [(r, r['cfg'][cname]) for r in res]
        ok = [(r, c) for r, c in rs if c['found']]
        gr = [r['plain_rand'] / c['abs_rand'] for r, c in ok]
        s = dict(K=len(tb.q), entries=tb.n_entries(), miss=len(rs) - len(ok),
                 aud=sum(1 for r, c in rs if c['audit']),
                 cand_lib=gmean([r['plain_lib'] / c['abs_opsoft'] for r, c in ok]), cand_rnd=gmean(gr),
                 mn=min(gr), mx=max(gr),
                 store=gmean([r['plain_store'] / max(1, c['store']) for r, c in ok]),
                 store_j1=gmean([r['plain_store'] / max(1, c['store_j1']) for r, c in ok]),
                 checks_per_eval=sum(c['checks'] for r, c in ok) / max(1, sum(c['abs_lib'] for r, c in ok)),
                 missed=[r['name'] + ' ' + r['term'] for r, c in rs if not c['found']],
                 per_task={r['name']: (r['plain_rand'] / c['abs_rand'] if c['found'] else None) for r, c in rs})
        summary[cname] = s
        log('%-58s %2d %7d %4d %4d %8.2fx %8.2fx %6.1f %6.1f %6.2fx %8.2fx' %
            (cname[:58], s['K'], s['entries'], s['miss'], s['aud'], s['cand_lib'], s['cand_rnd'], s['mn'],
             s['mx'], s['store'], s['store_j1']))
    log('''
columns: K = words; entries = verb-table rows; miss = tasks NOT found at the size plain search
finds them (answers lost); aud = tasks whose reference program uses a transition absent from the
tables; cand_lib = geometric mean of plain (library order) / filtered (soft operator order);
cand_rnd = geometric mean of plain / filtered, both averaged over random operator orders, all
deepening passes counted (the figure quoted as 15.7x for the hand list); store = ratio of classes
stored below the last level; store_j1 = the same with a one-step look-ahead.''')
    for cname, s in summary.items():
        if s['missed']:
            log('LOST under %s: %s' % (cname, s['missed']))
    for name in CONFIGS:
        log('\n%s:' % name)
        for q in CONFIGS[name][0].q:
            log('     ' + q.name)
    json.dump(summary, open('search_%s.json' % a.tag, 'w'), indent=1)


if __name__ == '__main__':
    main()
