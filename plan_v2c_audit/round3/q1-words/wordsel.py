"""Selection of a vocabulary from a scored pool (pool_CONFIG.pkl), by the review's three rules:
  (a) vacuity guard: an operator contributes 0 when H(output label) <= vac (default 0.05 bits);
  (b) greedy walk down the ranking by mean dependency score; skip a candidate whose
      normalised mutual information (by the smaller entropy, on the probe pool) with an
      already chosen word is >= nmi_cap (default 0.65);
  (c) each chosen list word is paired with the int word that it best predicts through
      the library's list->int reductions: every (list word, int word) pair is scored
      directly, mean over those operators of 1 - H(b(r(x)) | a(x)) / H(b(r(x))).
No word, pairing or threshold other than the arguments is supplied.
"""
import pickle
import time
from collections import Counter

from wordlib import (LISTONLY, LIB_LI, Probes, tstr, tsize, compile_term, scores_from_hh, nmi, Hc,
                     canon_any, lump_hh)

_POOLS = {}


def load_pool(config):
    if config not in _POOLS:
        d = pickle.load(open('pool_%s.pkl' % config, 'rb'))
        d['probes'] = Probes(seed=d['cfg']['seed'], P=800)
        _POOLS[config] = d
    return _POOLS[config]


def rank(pool, vac=0.05, ops=None, card=8, max_single=5, pairs=True, max_pair=9, need=None):
    """Eligible list candidates, best first.  ops: operator names to average over."""
    opidx = [k for k, n in enumerate(LISTONLY) if ops is None or n in ops]
    out = []
    for c in pool['cands']:
        if c['card'] > card or c['cardf'] > card:
            continue
        if c['pair']:
            if not pairs or c['size'] > max_pair:
                continue
        elif c['size'] > max_single:
            continue
        if need is not None and not need(c):
            continue
        s = scores_from_hh(c['hh'], vac, opidx)
        out.append((s, c))
    out.sort(key=lambda sc: (-sc[0], sc[1]['size'], tstr(sc[1]['term'])))
    return out


def _hk(c, P):
    """(entropy of the pool labels, the labels as one big int) -- cached on the candidate."""
    x = c.get('_hk')
    if x is None:
        x = c['_hk'] = (Hc(Counter(c['key']), P), int.from_bytes(c['key'], 'little'))
    return x


def nmi_fast(c1, c2, P):
    """normalised mutual information (by the smaller entropy) of two candidates' pool labels
    (labels < 8, so the joint label of each probe fits one byte)."""
    h1, i1 = _hk(c1, P)
    h2, i2 = _hk(c2, P)
    if h1 < 1e-12 or h2 < 1e-12:
        return 0.0
    hj = Hc(Counter(((i1 << 3) + i2).to_bytes(P, 'little')), P)
    return max(0.0, h1 + h2 - hj) / min(h1, h2)


def greedy(ranked, K, nmi_cap, P=800, comps=None):
    """comps (NOT one of the review's rules; a remedy tried in this audit): a dict
    term -> single candidate.  When given, a pair is also skipped if either of its two
    components is redundant (NMI >= cap) with a chosen word or with a component of one."""
    chosen = []
    parts = []            # chosen words and, with comps, their components
    walked = 0
    for (s, c) in ranked:
        if len(chosen) >= K or s <= 0:
            break
        walked += 1
        if any(nmi_fast(c, x[1], P) >= nmi_cap for x in chosen):
            continue
        mine = []
        if comps is not None and c['pair']:
            mine = [comps[c['term'][1]], comps[c['term'][2]]]
            if any(nmi_fast(m, x, P) >= nmi_cap for m in mine for x in parts):
                continue
        if comps is not None and any(nmi_fast(c, x, P) >= nmi_cap for x in parts):
            continue
        chosen.append((s, c, walked))
        parts.append(c)
        parts.extend(mine)
    return chosen, walked


def pair_int(pool, alpha_key, vac=0.05, card=8, reds=None, need=None, objective='lump'):
    """Rule (c): the int word best predicted from list word alpha through the reductions.
    objective 'lump': mean dependency score over the list->int operators;
    objective 'lumpmi': mean of (dependency score x mutual information in bits), which is
    what the reviewer's script maximises (exp_devils_advocate.py line 456)."""
    pr = pool['probes']
    reds = [r for r in LIB_LI if reds is None or r in reds]
    memo = pool.setdefault('_pair_memo', {})
    mk = (alpha_key, vac, card, tuple(reds), objective, need is None)
    if mk in memo:
        return memo[mk]
    res = _pair_int(pool, alpha_key, vac, card, reds, need, objective)
    memo[mk] = res
    return res


def _pair_int(pool, alpha_key, vac, card, reds, need, objective):
    pr = pool['probes']
    EI = pr.EI
    cache = pool.setdefault('_beta_cols', {})
    best = (0.0, None)
    P = pr.P
    ha = Hc(Counter(alpha_key), P)
    ia = int.from_bytes(alpha_key, 'little') << 3
    for b in pool['icands']:
        if b['card'] > card:
            continue
        if need is not None and not need(b):
            continue
        cols = cache.get(id(b))
        if cols is None:
            bk = b['key']
            cols = {}
            for r in LIB_LI:
                o = bytes([bk[EI[v]] for v in pr.red[r]])
                cols[r] = (Hc(Counter(o), P), int.from_bytes(o, 'little'))
            cache[id(b)] = cols
        tot = 0.0
        for r in reds:
            ho, io = cols[r]
            if ho <= vac:
                continue
            hc = max(0.0, Hc(Counter((ia + io).to_bytes(P, 'little')), P) - ha)
            if objective == 'lump':
                tot += 1.0 - hc / ho
            else:
                tot += (1.0 - hc / ho) * (ho - hc)
        x = tot / len(reds)
        if x > best[0] + 1e-12 or (best[1] is not None and abs(x - best[0]) <= 1e-12 and
                                   (b['size'], tstr(b['term'])) < (best[1]['size'], tstr(best[1]['term']))):
            best = (x, b)
    return best


def select(config, K=6, nmi_cap=0.65, card=8, vac=0.05, ops=None, reds=None, max_single=5, pairs=True,
           max_pair=9, need=None, log=None, icard=None, objective='lump', compcap=False):
    """Returns a list of dicts: list term, int term (or None), scores."""
    pool = load_pool(config)
    comps = None
    if compcap:
        comps = pool.get('_comps')
        if comps is None:
            comps = pool['_comps'] = {c['term']: c for c in pool['cands'] if not c['pair']}
    t0 = time.perf_counter()
    rmemo = pool.setdefault('_rank_memo', {})
    rk = (vac, None if ops is None else tuple(ops), card, max_single, pairs, max_pair)
    if need is None and rk in rmemo:
        ranked = rmemo[rk]
    else:
        ranked = rank(pool, vac=vac, ops=ops, card=card, max_single=max_single, pairs=pairs,
                      max_pair=max_pair, need=need)
        if need is None:
            rmemo[rk] = ranked
    t1 = time.perf_counter()
    chosen, walked = greedy(ranked, K, nmi_cap, comps=comps)
    t2 = time.perf_counter()
    out = []
    for (s, c, w) in chosen:
        x, b = pair_int(pool, c['key'], vac=vac, card=icard or card, reds=reds, objective=objective)
        out.append(dict(lterm=c['term'], iterm=b['term'] if b is not None else None, score=s, cross=x,
                        size=c['size'], card=c['cardf'], rank=w, key=c['key']))
    t3 = time.perf_counter()
    info = dict(n_eligible=len(ranked), walked=walked, rank_s=t1 - t0, greedy_s=t2 - t1, pairing_s=t3 - t2)
    if log:
        log('  %s K=%d nmi<%.2f card<=%d vac=%.2g%s%s%s%s: %d eligible candidates, walked %d; '
            'rank %.1f s, greedy %.1f s, pairing %.1f s'
            % (config, K, nmi_cap, card, vac, '' if pairs else ' no-pairs',
               '' if max_single == 5 else ' singles<=%d' % max_single,
               ' component-cap' if compcap else '', '' if objective == 'lump' else ' pairing=' + objective,
               len(ranked), walked, t1 - t0, t2 - t1, t3 - t2))
        for k, w in enumerate(out):
            log('    %2d. %.3f  rank %-6d card %d  %-62s | int: %-24s (cross %.2f)'
                % (k + 1, w['score'], w['rank'], w['card'], tstr(w['lterm']),
                   tstr(w['iterm']) if w['iterm'] is not None else 'trivial', w['cross']))
    return out, info


# ------------------------------------------------------------------ Boolean coarsening (C1 extension)
def best_boolean(fL, pr, vac=0.05, objective='score'):
    """Among all splits of the labels of fL into two groups, the best one.
    objective 'score': highest mean dependency score (the selection criterion itself);
    objective 'info':  highest (mean dependency score) x (entropy of the split on the probe pool),
                       i.e. prefers a split that is both closed and informative.
    Returns (labels in group 1, score of the split, score of fL itself, number of labels)."""
    raw = [fL(v) for v in pr.vals]
    lab, nl = canon_any(raw)
    labels = list(dict.fromkeys(raw))          # label of canonical id i
    opidx = range(len(LISTONLY))
    full = scores_from_hh(lump_hh(lab, nl, pr.getters, pr.P), vac, opidx)
    best = (-1.0, None)
    for mask in range(1, 1 << (nl - 1)):       # label 0 always in group 0
        tab = bytearray(256)
        for i in range(1, nl):
            if mask >> (i - 1) & 1:
                tab[i] = 1
        b = lab.translate(bytes(tab))
        s = scores_from_hh(lump_hh(b, 2, pr.getters, pr.P), vac, opidx)
        if objective == 'score':
            obj = s
        else:
            obj = s * Hc(Counter(pr.pget(b)), pr.P)
        if obj > best[0]:
            best = (obj, mask, s)
    grp = tuple(labels[i] for i in range(1, nl) if best[1] >> (i - 1) & 1)
    return grp, best[2], full, nl


def vocab_repr(words):
    return [[repr(w['lterm']), repr(w['iterm'])] for w in words]
