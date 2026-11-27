"""Build and score a pool of word candidates for one grammar configuration.

usage: python3 wordpool.py CONFIG [--procs 15]
writes pool_CONFIG.pkl and pool_CONFIG.log

Steps (all timed):
  1. enumerate single terms of <= S nodes on the probe pool (wordlib.enum_list_words),
     dedupe by the partition induced on the pool;
  2. evaluate each surviving term on the full value table (pool + every operator's
     outputs) and compute, per list-only operator, H(out) and H(out | in);
  3. pairs: (pair a b) for every two single words of <= PAIRCOMP nodes whose joint
     label set has <= CARD labels on the pool and on the full table; dedupe by partition;
     score likewise;
  4. the same enumeration for words on ints (terms over v), scored on the int operators.
"""
import argparse
import multiprocessing as mp
import pickle
import sys
import time
from array import array
from collections import Counter

import wordlib as W
from wordlib import (L, I, OPS, OPFN, OPSIG, LIB_LL, LIB_LLL, LIB_IL, LIB_LI, LIB_II, LIB_III,
                     LISTONLY, FN, FOLDS, Probes, tstr, tsize, compile_term, canon_any, lump_hh, Hc)

OPNAMES = [o[0] for o in OPS]
INT_OPS = LIB_II + LIB_III
GRANTED_LIST = ['len', 'head', 'last']                   # stand-ins for the kernel's `length` and `at`
STAGE1 = INT_OPS + LIB_IL + ['len', 'head', 'last', 'sum',
                             'reverse', 'tail', 'init', 'take2', 'take3', 'drop2', 'concat']
STAGE2 = STAGE1 + ['inc_all', 'dbl_all', 'abs_all', 'neg_all', 'dec_all', 'sq_all', 'half_all',
                   'zip_add', 'zip_sub', 'zip_mul', 'zip_min', 'zip_max', 'min_el', 'max_el',
                   'sort', 'sort_desc', 'shift1', 'evens_idx', 'odds_idx']
assert len(STAGE1) == 26 and len(STAGE2) == 45 and set(STAGE2) < set(OPNAMES)

CONFIGS = {
    # name: seed, allowed library operators in the GRAMMAR, fold forms, pair component size
    'main': dict(seed=0, allowed=OPNAMES, fold=False, paircomp=4),
    'seed1': dict(seed=1, allowed=OPNAMES, fold=False, paircomp=4),
    'nolib': dict(seed=0, allowed=INT_OPS + GRANTED_LIST, fold=False, paircomp=4),
    'nolib_fold': dict(seed=0, allowed=INT_OPS + GRANTED_LIST, fold=True, paircomp=5),
    # pair components: other words <= 3 nodes, fold forms <= 5 nodes (with <= 4 / <= 5 the pool has
    # 744k pair partitions, too many to score in the time available)
    'lib_fold': dict(seed=0, allowed=OPNAMES, fold=True, paircomp=3, foldcomp=5),
    'stage1': dict(seed=0, allowed=STAGE1, fold=False, paircomp=4),
    'stage2': dict(seed=0, allowed=STAGE2, fold=False, paircomp=4),
}
S_FULL = 5
CARD = 8
P = 800

PR = None            # Probes (global, inherited by forked workers)
COMP = None          # pair components: list of (full-table label int, pool label int)
_LCACHE = {}
LCACHE_MAX = 24


def lcol(t):
    """list-typed term -> its column over the full value table (cached, FIFO)."""
    if t == 'xs':
        return PR.vals
    c = _LCACHE.get(t)
    if c is not None:
        return c
    op = t[0]
    fn = OPFN[op]
    if len(t) == 2:
        c = list(map(fn, lcol(t[1])))
    else:
        a1, a2 = t[1], t[2]
        if op in LIB_IL:
            if isinstance(a1, int):
                c = [fn(a1, v) for v in lcol(a2)]
            else:
                c = list(map(fn, icol(a1), lcol(a2)))
        else:
            c = list(map(fn, lcol(a1), lcol(a2)))
    if len(_LCACHE) >= LCACHE_MAX:
        _LCACHE.pop(next(iter(_LCACHE)))
    _LCACHE[t] = c
    return c


def icol(t):
    op = t[0]
    if op == 'pair':
        return list(zip(icol(t[1]), icol(t[2])))
    if op in FOLDS:
        ff = W._fold_fn(op, compile_term(t[1]))
        return list(map(ff, lcol(t[2])))
    fn = FN[op]
    if op in LIB_LI:
        return list(map(fn, lcol(t[1])))
    if len(t) == 2:
        return list(map(fn, icol(t[1])))
    a1, a2 = t[1], t[2]
    if isinstance(a2, int):
        return [fn(x, a2) for x in icol(a1)]
    if isinstance(a1, int):
        return [fn(a1, y) for y in icol(a2)]
    return list(map(fn, icol(a1), icol(a2)))


def lsub_key(t):
    """sort key: the list subterms of t from innermost outwards (cache locality)."""
    out = []

    def walk(u):
        if isinstance(u, (str, int)):
            return
        for a in u[1:]:
            walk(a)
        if u[0] in LIB_LL or u[0] in LIB_LLL or u[0] in LIB_IL:
            out.append(tstr(u))
    walk(t)
    return tuple(out)


def score_single(args):
    k, t, want_lab = args
    lab, nl = canon_any(icol(t))
    if lab is None or nl > CARD:
        return (k, nl, None, None)
    hh = lump_hh(lab, nl, PR.getters, PR.P)
    return (k, nl, hh.tobytes(), lab if want_lab else None)


def _canon_joint(ja, jb, n):
    """joint labels of two byte-label columns given as ints (labels < 8) -> (bytes, nlab)."""
    j = ((ja << 3) + jb).to_bytes(n, 'little')
    codes = list(dict.fromkeys(j))
    if len(codes) > CARD:
        return None, len(codes)
    tab = bytearray(256)
    for i, c in enumerate(codes):
        tab[c] = i
    return j.translate(bytes(tab)), len(codes)


def score_pairs(chunk):
    out = []
    NV, Pn = PR.NV, PR.P
    for (i, j) in chunk:
        lab, nl = _canon_joint(COMP[i][0], COMP[j][0], NV)
        if lab is None:
            continue
        out.append((i, j, nl, lump_hh(lab, nl, PR.getters, Pn).tobytes()))
    return out


def int_hh(lab, pr):
    res = array('f')
    for n in INT_OPS:
        Ii, Jj, Kk = pr.irows[n]
        m = len(Ii)
        o = [lab[k] for k in Kk]
        ho = Hc(Counter(o), m)
        if ho < 1e-12:
            res.extend((0.0, 0.0))
            continue
        a = [lab[k] for k in Ii] if Jj is None else list(zip([lab[k] for k in Ii], [lab[k] for k in Jj]))
        res.extend((ho, max(0.0, Hc(Counter(zip(a, o)), m) - Hc(Counter(a), m))))
    return res


def main():
    global PR, COMP
    ap = argparse.ArgumentParser()
    ap.add_argument('config')
    ap.add_argument('--procs', type=int, default=15)
    a = ap.parse_args()
    cfg = CONFIGS[a.config]
    logf = open('pool_%s.log' % a.config, 'w')

    def log(*x):
        s = ' '.join(str(v) for v in x)
        print(s)
        logf.write(s + '\n')
        logf.flush()
    T = {}
    t0 = time.time()
    PR = Probes(seed=cfg['seed'], P=P)
    allowed = set(cfg['allowed'])
    log('# config %s: probe seed %d, %d probes per operator, value table %d lists; grammar uses %d library operators%s'
        % (a.config, cfg['seed'], P, PR.NV, len(allowed), ' + fold forms' if cfg['fold'] else ''))
    st = {}
    words = W.enum_list_words(PR.pool, allowed, S=S_FULL, card=CARD, fold=cfg['fold'], log=log, stats=st)
    T['enumerate_s'] = time.time() - t0
    log('single terms <= %d nodes: %d generated, %d word partitions (2..%d labels on the pool); %.1f s'
        % (S_FULL, sum(st['raw'].values()), len(words), CARD, T['enumerate_s']))
    # ---------------- singles: full-table labels and scores
    t1 = time.time()
    items = sorted(words.items(), key=lambda kv: lsub_key(kv[1][1]))
    pc = cfg['paircomp']
    fc = cfg.get('foldcomp', pc)

    def is_comp(s, t):
        return s <= pc or (s <= fc and t[0] in FOLDS)
    jobs = [(k, t, is_comp(s, t)) for k, (key, (s, t)) in enumerate(items)]
    cands = []
    comps = []
    ndrop = 0
    with mp.get_context('fork').Pool(a.procs) as pool:
        for (k, nl, hhb, lab) in pool.imap(score_single, jobs, chunksize=64):
            key, (s, t) = items[k]
            if hhb is None:
                ndrop += 1
                continue
            hh = array('f')
            hh.frombytes(hhb)
            c = dict(term=t, size=s, card=len(set(key)), cardf=nl, key=key, hh=hh, pair=False)
            cands.append(c)
            if lab is not None:
                comps.append((c, lab))
    T['score_singles_s'] = time.time() - t1
    log('singles scored: %d kept, %d dropped (more than %d labels on the full table); %.1f s wall on %d processes'
        % (len(cands), ndrop, CARD, T['score_singles_s'], a.procs))
    # ---------------- pairs
    t2 = time.time()
    comps.sort(key=lambda cl: (cl[0]['size'], tstr(cl[0]['term'])))
    COMP = [(int.from_bytes(lab, 'little'), int.from_bytes(c['key'], 'little')) for (c, lab) in comps]
    seen = set(words.keys())
    pairs = {}
    npair = 0
    nP = PR.P
    for i in range(len(comps)):
        ci = comps[i][0]
        pi = COMP[i][1]
        for j in range(i + 1, len(comps)):
            cj = comps[j][0]
            npair += 1
            key, nl = _canon_joint(pi, COMP[j][1], nP)
            if key is None or nl <= max(ci['card'], cj['card']):
                continue            # too many labels, or one component already determines the other
            if key in seen:
                continue
            sz = 1 + ci['size'] + cj['size']
            old = pairs.get(key)
            if old is None or old[0] > sz:
                pairs[key] = (sz, i, j, nl)
    T['pair_enum_s'] = time.time() - t2
    log('pairs: %d components (<= %d nodes%s), %d pairs tried, %d new partitions with <= %d labels; %.1f s'
        % (len(comps), pc, ', fold forms <= %d' % fc if fc != pc else '', npair, len(pairs), CARD,
           T['pair_enum_s']))
    t3 = time.time()
    plist = [(i, j) for (sz, i, j, nl) in pairs.values()]
    pinfo = {(i, j): (key, sz, nl) for key, (sz, i, j, nl) in pairs.items()}
    chunks = [plist[k:k + 400] for k in range(0, len(plist), 400)]
    nkept = 0
    with mp.get_context('fork').Pool(a.procs) as pool:
        for res in pool.imap(score_pairs, chunks):
            for (i, j, nl, hhb) in res:
                key, sz, nlp = pinfo[(i, j)]
                hh = array('f')
                hh.frombytes(hhb)
                cands.append(dict(term=('pair', comps[i][0]['term'], comps[j][0]['term']), size=sz,
                                  card=nlp, cardf=nl, key=key, hh=hh, pair=True))
                nkept += 1
    T['score_pairs_s'] = time.time() - t3
    log('pairs scored: %d kept (<= %d labels on the full table); %.1f s wall on %d processes'
        % (nkept, CARD, T['score_pairs_s'], a.procs))
    # ---------------- int side
    t4 = time.time()
    iw = W.enum_int_words(PR.E, allowed, S=S_FULL, card=CARD)
    icands = []
    for key, (s, t) in iw.items():
        icands.append(dict(term=t, size=s, card=len(set(key)), key=key, hh=int_hh(key, PR), pair=False))
    base = sorted([c for c in icands if c['size'] <= 4], key=lambda c: (c['size'], tstr(c['term'])))
    seen_i = set(iw.keys())
    nE = len(PR.E)
    for i in range(len(base)):
        for j in range(i + 1, len(base)):
            key, nl = _canon_joint(int.from_bytes(base[i]['key'], 'little'),
                                   int.from_bytes(base[j]['key'], 'little'), nE)
            if key is None or nl <= max(base[i]['card'], base[j]['card']) or key in seen_i:
                continue
            seen_i.add(key)
            icands.append(dict(term=('pair', base[i]['term'], base[j]['term']),
                               size=1 + base[i]['size'] + base[j]['size'], card=nl, key=key,
                               hh=int_hh(key, PR), pair=True))
    T['int_side_s'] = time.time() - t4
    log('int words: %d single (<= %d nodes) + %d pairs; %.1f s'
        % (len(iw), S_FULL, len(icands) - len(iw), T['int_side_s']))
    T['total_wall_s'] = time.time() - t0
    log('total %.1f s wall; times: %s' % (T['total_wall_s'], {k: round(v, 1) for k, v in T.items()}))
    pickle.dump(dict(config=a.config, cfg=cfg, cands=cands, icands=icands, times=T, enum_stats=st,
                     n_singles=len(words), n_pairs=nkept),
                open('pool_%s.pkl' % a.config, 'wb'), protocol=4)
    log('wrote pool_%s.pkl: %d list candidates, %d int candidates' % (a.config, len(cands), len(icands)))


if __name__ == '__main__':
    main()
