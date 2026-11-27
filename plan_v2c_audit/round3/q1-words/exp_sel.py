"""Select vocabularies from the scored pools under every variation, and write them out for
wsearch.py.   usage: python3 exp_sel.py main|more
  main: pool_main (+ pool_nolib, pool_nolib_fold)   -> sel_main.log, vocabs_main.json
  more: pool_seed1, pool_lib_fold, pool_stage1/2     -> sel_more.log, vocabs_more.json
"""
import json
import sys
import time
from collections import Counter

from seqlib import HAND6, L, I
from wordlib import (LISTONLY, LIB_LI, Hc, tstr, compile_term, canon_bytes, canon_any, lump_hh,
                     scores_from_hh)
import wordsel as WS
from wordpool import STAGE1, STAGE2

suite = sys.argv[1]
logf = open('sel_%s.log' % suite, 'w')


def log(*x):
    s = ' '.join(str(v) for v in x)
    print(s)
    logf.write(s + '\n')
    logf.flush()


VOC = {}
INFO = {}


def add(name, config, **kw):
    words, info = WS.select(config, log=log, **kw)
    VOC[name] = WS.vocab_repr(words)
    INFO[name] = (words, info)
    return words


def hand_analysis(config, vocs, max_pair=9):
    """Where do the six hand-listed list words sit in the pool, and how much of each does a
    selected vocabulary capture?"""
    pool = WS.load_pool(config)
    pr = pool['probes']
    P = pr.P
    ranked = WS.rank(pool, max_pair=max_pair)
    scores = [s for (s, c) in ranked]
    log('\n== the hand-listed list words against the %s pool (%d candidates, pairs <= %d nodes) ==' % (config, len(ranked), max_pair))
    log('   score = mean dependency score over the 37 list-only operators, vacuity guard 0.05;')
    log('   rank = 1 + number of pool candidates with a higher score;')
    log('   nearest = pool candidate maximising I(hand; cand) / max(H(hand), H(cand)) on the probe pool')
    hk = {}
    for q in HAND6:
        f = q.f[L]
        raw = [f(v) for v in pr.vals]
        lab, nl = canon_any(raw)
        s = scores_from_hh(lump_hh(lab, nl, pr.getters, pr.P), 0.05, range(len(LISTONLY)))
        rk = 1 + sum(1 for x in scores if x > s)
        key = canon_bytes([f(v) for v in pr.pool])
        hh = Hc(Counter(key), P)
        ik = int.from_bytes(key, 'little')
        hk[q.name] = (key, hh, ik)
        exact = None
        best = (-1, None, None)
        for r, (sc, c) in enumerate(ranked):
            if c['key'] == key:
                exact = (r + 1, sc, c)
            h2, i2 = WS._hk(c, P)
            mi = hh + h2 - Hc(Counter(((ik << 3) + i2).to_bytes(P, 'little')), P)
            x = mi / max(hh, h2)
            if x > best[0] + 1e-9:
                best = (x, r + 1, (sc, c))
        log('   %-8s score %.3f, would rank %5d | same partition in pool: %s | nearest (%.2f): rank %d, %.3f, %s'
            % (q.name, s, rk,
               'rank %d, %s' % (exact[0], tstr(exact[2]['term'])) if exact else 'none',
               best[0], best[1], best[2][0], tstr(best[2][1]['term'])))
    log('\n   share of each hand word\'s label information carried by the single best word of a vocabulary')
    log('   (I(hand; word) / H(hand) on the probe pool; 1.00 = that word determines the hand word):')
    log('   %-44s %s' % ('vocabulary', '  '.join('%-8s' % q.name for q in HAND6)))
    for name in vocs:
        words = INFO[name][0]
        cells = []
        for q in HAND6:
            key, hh, ik = hk[q.name]
            b = 0.0
            for w in words:
                wk = w['key']
                h2 = Hc(Counter(wk), P)
                mi = hh + h2 - Hc(Counter(zip(key, wk)), P)
                b = max(b, mi / hh)
            cells.append('%-8.2f' % b)
        log('   %-44s %s' % (name, '  '.join(cells)))


CONTENT = [   # plain-word content properties, written as terms of each grammar, to locate them in a pool
    ('any negative', [('sgn', ('count_pos', ('neg_all', 'xs'))), ('any', ('<', 'x', 0), 'xs')]),
    ('any positive', [('sgn', ('count_pos', 'xs')), ('any', ('<', 0, 'x'), 'xs')]),
    ('any even', [('sgn', ('count_even', 'xs')), ('any', ('=', 0, ('mod', 'x', 2)), 'xs')]),
    ('any odd', [('sgn', ('count_even', ('inc_all', 'xs'))), ('any', ('mod', 'x', 2), 'xs')]),
    ('all non-negative', [('<', ('min_el', 'xs'), 0), ('all', ('<', -1, 'x'), 'xs')]),
    ('sign of min', [('sgn', ('min_el', 'xs'))]),
    ('signs present (hand sign)', [('pair', ('sgn', ('count_pos', 'xs')), ('sgn', ('count_pos', ('neg_all', 'xs')))),
                                   ('pair', ('any', ('<', 'x', 0), 'xs'), ('any', ('<', 0, 'x'), 'xs'))]),
    ('parities present (hand parity)', [('pair', ('sgn', ('count_even', 'xs')), ('sgn', ('count_even', ('inc_all', 'xs')))),
                                        ('pair', ('any', ('mod', 'x', 2), 'xs'), ('all', ('mod', 'x', 2), 'xs'))]),
    ('some ascent', [('sgn', ('count_pos', ('map_adj_sub', 'xs')))]),
    ('some descent', [('sgn', ('count_pos', ('neg_all', ('map_adj_sub', 'xs'))))]),
    ('sorted ascending', [('=', 0, ('count_pos', ('neg_all', ('map_adj_sub', 'xs'))))]),
]


def content_ranks(config, max_pair=11):
    pool = WS.load_pool(config)
    pr = pool['probes']
    ranked = WS.rank(pool, max_pair=max_pair)
    pos = {c['key']: (r + 1, s, c) for r, (s, c) in enumerate(ranked)}
    log('\n== where plain-word content properties sit in the %s pool (%d candidates, pairs <= %d nodes) =='
        % (config, len(ranked), max_pair))
    for name, terms in CONTENT:
        out = []
        for t in terms:
            try:
                f = compile_term(t)
                key = canon_bytes([f(v) for v in pr.pool])
            except KeyError:
                continue
            hit = pos.get(key)
            if hit is not None:
                out.append('rank %d (score %.3f) as %s' % (hit[0], hit[1], tstr(hit[2]['term'])))
        log('   %-32s %s' % (name, '; '.join(dict.fromkeys(out)) if out else 'not in the pool'))


def boolean_version(name, config, words, both=True):
    """C1 extension: every multi-valued word replaced by its best single Boolean (the split of
    its labels into two groups with the highest mean dependency score).  Two variants: the int
    side kept as it was, or re-paired by rule (c) among Boolean int words."""
    pool = WS.load_pool(config)
    pr = pool['probes']
    keep, repair = [], []
    log('  Boolean version of %s:' % name)
    for w in words:
        if w['card'] <= 2:
            keep.append([repr(w['lterm']), repr(w['iterm'])])
            repair.append([repr(w['lterm']), repr(w['iterm'])])
            continue
        fL = compile_term(w['lterm'])
        grp, sb, sf, nl = WS.best_boolean(fL, pr)
        bt = ('in', w['lterm'], grp)
        fb = compile_term(bt)
        key = canon_bytes([fb(v) for v in pr.pool])
        x, b = WS.pair_int(pool, key, card=2)
        log('     %.3f (%d labels) -> %.3f  %s   | int kept: %s | int re-paired (Boolean): %s (cross %.2f)'
            % (sf, nl, sb, tstr(bt), tstr(w['iterm']) if w['iterm'] is not None else 'trivial',
               tstr(b['term']) if b is not None else 'trivial', x))
        keep.append([repr(bt), repr(w['iterm'])])
        repair.append([repr(bt), repr(b['term'] if b is not None else None)])
    VOC[name + '|bool-list'] = keep
    if both:
        VOC[name + '|bool-both'] = repair


t0 = time.time()
if suite == 'main':
    log('== main pool: every variation of the selection rule ==')
    for K in (1, 3, 6, 10):
        add('main|pairs|K=%d' % K, 'main', K=K)
    for K in (1, 3, 6, 10):
        add('main|nopairs|K=%d' % K, 'main', K=K, pairs=False)
    for cap in (0.5, 0.8):
        add('main|pairs|K=6|nmi=%.2f' % cap, 'main', K=6, nmi_cap=cap)
        add('main|nopairs|K=6|nmi=%.2f' % cap, 'main', K=6, nmi_cap=cap, pairs=False)
    for card in (2, 4, 6):
        add('main|pairs|K=6|card=%d' % card, 'main', K=6, card=card)
    add('main|nopairs|K=6|card=4', 'main', K=6, card=4, pairs=False)
    add('main|pairs|K=6|vac=0', 'main', K=6, vac=1e-12)
    add('main|nopairs|K=6|vac=0', 'main', K=6, vac=1e-12, pairs=False)
    add('main|pairs|K=6|pair=lumpmi', 'main', K=6, objective='lumpmi')
    add('main|nopairs|K=6|pair=lumpmi', 'main', K=6, pairs=False, objective='lumpmi')
    add('main|nopairs|K=10|pair=lumpmi', 'main', K=10, pairs=False, objective='lumpmi')
    add('main|singles<=3|K=6', 'main', K=6, pairs=False, max_single=3)
    add('main|singles<=4|K=6', 'main', K=6, pairs=False, max_single=4)
    add('main|singles<=4+pairs<=7|K=6', 'main', K=6, max_single=4, max_pair=7)
    add('main|pairs<=7|K=6', 'main', K=6, max_pair=7)
    log('\n== grammar without the library\'s list operators (len, head, last only) ==')
    for cfg in ('nolib', 'nolib_fold'):
        add('%s|pairs|K=6' % cfg, cfg, K=6)
        add('%s|nopairs|K=6' % cfg, cfg, K=6, pairs=False)
    add('nolib_fold|pairs|K=10', 'nolib_fold', K=10)
    log('\n== C1 extension: multi-valued words replaced by their best single Boolean ==')
    boolean_version('main|pairs|K=6', 'main', INFO['main|pairs|K=6'][0])
    boolean_version('main|nopairs|K=6', 'main', INFO['main|nopairs|K=6'][0])
    boolean_version('main|nopairs|K=10', 'main', INFO['main|nopairs|K=10'][0], both=False)
    # the hand list, one word at a time and all at once
    pr = WS.load_pool('main')['probes']
    log('  Boolean version of the hand list (int side kept):')
    hb = {}
    for q in HAND6:
        grp, sb, sf, nl = WS.best_boolean(q.f[L], pr)
        hb[q.name] = grp
        log('     %-8s %.3f (%d labels) -> %.3f as Boolean, labels %s vs the rest' % (q.name, sf, nl, sb, grp))
    multi = ['sign', 'parity', 'order', 'caplen5']
    VOC['@hand6'] = []
    VOC['@auto6'] = []
    VOC['@auto10'] = []
    VOC['@types'] = []
    VOC['hand6|all four multi-valued -> Boolean'] = [
        ['@handbool:' + q.name, repr(hb[q.name])] if q.name in multi else ['@hand:' + q.name, 'None']
        for q in HAND6]
    for m in multi:
        VOC['hand6|%s -> Boolean' % m] = [
            ['@handbool:' + q.name, repr(hb[q.name])] if q.name == m else ['@hand:' + q.name, 'None']
            for q in HAND6]
    hand_analysis('main', ['main|pairs|K=1', 'main|pairs|K=3', 'main|pairs|K=6', 'main|pairs|K=10',
                           'main|nopairs|K=1', 'main|nopairs|K=3', 'main|nopairs|K=6', 'main|nopairs|K=10',
                           'main|pairs|K=6|nmi=0.50', 'main|pairs|K=6|nmi=0.80',
                           'main|nopairs|K=6|nmi=0.50', 'main|nopairs|K=6|nmi=0.80',
                           'main|pairs|K=6|card=2', 'main|pairs|K=6|card=4'])
    for cfg in ('nolib', 'nolib_fold'):
        hand_analysis(cfg, ['%s|pairs|K=6' % cfg, '%s|nopairs|K=6' % cfg])
elif suite == 'extra':
    log('== a remedy not in the review: the NMI cap also applied to the two components of a pair ==')
    for K in (3, 6, 10):
        add('main|pairs|K=%d|compcap' % K, 'main', K=K, compcap=True)
    for cap in (0.5, 0.8):
        add('main|pairs|K=6|nmi=%.2f|compcap' % cap, 'main', K=6, nmi_cap=cap, compcap=True)
    add('main|pairs|K=6|card=4|compcap', 'main', K=6, card=4, compcap=True)
    add('nolib_fold|pairs|K=6|compcap', 'nolib_fold', K=6, compcap=True)
    add('nolib|pairs|K=6|compcap', 'nolib', K=6, compcap=True)
    log('\n== fold-form pools with pairs up to 11 nodes (two 5-node fold forms) ==')
    add('nolib_fold|pairs<=11|K=6', 'nolib_fold', K=6, max_pair=11)
    add('nolib_fold|pairs<=11|K=10', 'nolib_fold', K=10, max_pair=11)
    add('nolib_fold|pairs<=11|K=6|compcap', 'nolib_fold', K=6, max_pair=11, compcap=True)
    boolean_version('main|pairs|K=6|compcap', 'main', INFO['main|pairs|K=6|compcap'][0], both=False)
    log('\n== C1 extension, second definition of "best Boolean": the split maximising score x entropy ==')
    pool = WS.load_pool('main')
    pr = pool['probes']
    for vname in ('main|nopairs|K=6', 'main|pairs|K=6'):
        words = json.load(open('selected_main.json'))[vname]
        spec = json.load(open('vocabs_main.json'))[vname]
        out = []
        log('  %s:' % vname)
        for (lr, ir), w in zip(spec, words):
            import ast
            lt = ast.literal_eval(lr)
            if w['card'] <= 2:
                out.append([lr, ir])
                continue
            grp, sb, sf, nl = WS.best_boolean(compile_term(lt), pr, objective='info')
            bt = ('in', lt, grp)
            log('     %.3f (%d labels) -> %.3f  %s' % (sf, nl, sb, tstr(bt)))
            out.append([repr(bt), ir])
        VOC[vname + '|bool-info'] = out
    hb = {}
    for q in HAND6:
        grp, sb, sf, nl = WS.best_boolean(q.f[L], pr, objective='info')
        hb[q.name] = grp
        log('     hand %-8s %.3f (%d labels) -> %.3f as Boolean (info), labels %s vs the rest' % (q.name, sf, nl, sb, grp))
    multi = ['sign', 'parity', 'order', 'caplen5']
    VOC['hand6|all four multi-valued -> Boolean (info)'] = [
        ['@handbool:' + q.name, repr(hb[q.name])] if q.name in multi else ['@hand:' + q.name, 'None']
        for q in HAND6]
    hand_analysis('main', ['main|pairs|K=3|compcap', 'main|pairs|K=6|compcap', 'main|pairs|K=10|compcap'])
    hand_analysis('nolib_fold', ['nolib_fold|pairs|K=6|compcap', 'nolib_fold|pairs<=11|K=6',
                                 'nolib_fold|pairs<=11|K=10', 'nolib_fold|pairs<=11|K=6|compcap'], max_pair=11)
    for cfg in ('main', 'nolib', 'nolib_fold'):
        content_ranks(cfg)
else:
    log('== second probe seed ==')
    for K in (1, 3, 6, 10):
        add('seed1|pairs|K=%d' % K, 'seed1', K=K)
    for K in (6, 10):
        add('seed1|nopairs|K=%d' % K, 'seed1', K=K, pairs=False)
    log('\n== library operators + fold forms (any / all / count over an element term) ==')
    for K in (6, 10):
        add('lib_fold|pairs|K=%d' % K, 'lib_fold', K=K)
        add('lib_fold|nopairs|K=%d' % K, 'lib_fold', K=K, pairs=False)
        add('lib_fold|pairs<=11|K=%d' % K, 'lib_fold', K=K, max_pair=11)
    add('lib_fold|pairs<=11|K=6|compcap', 'lib_fold', K=6, max_pair=11, compcap=True)
    add('seed1|pairs|K=6|compcap', 'seed1', K=6, compcap=True)
    log('\n== the library grows: stage 1 (26 operators), stage 2 (45), stage 3 = main (61) ==')
    for (cfg, ops) in (('stage1', STAGE1), ('stage2', STAGE2)):
        for K in (6, 10):
            add('%s|pairs|K=%d' % (cfg, K), cfg, K=K, ops=ops, reds=ops)
            add('%s|nopairs|K=%d' % (cfg, K), cfg, K=K, ops=ops, reds=ops, pairs=False)
    hand_analysis('seed1', ['seed1|pairs|K=6', 'seed1|nopairs|K=6'])
    hand_analysis('lib_fold', ['lib_fold|pairs|K=6', 'lib_fold|nopairs|K=6', 'lib_fold|pairs|K=10',
                               'lib_fold|nopairs|K=10', 'lib_fold|pairs<=11|K=6', 'lib_fold|pairs<=11|K=10',
                               'lib_fold|pairs<=11|K=6|compcap'], max_pair=11)
    for cfg in ('seed1', 'lib_fold', 'stage1', 'stage2'):
        content_ranks(cfg)
log('\nselection timings (seconds; rank = scoring already done, just averaging and sorting):')
for name, (words, info) in INFO.items():
    log('   %-40s eligible %6d walked %6d rank %.1f greedy %.1f pairing %.1f'
        % (name, info['n_eligible'], info['walked'], info['rank_s'], info['greedy_s'], info['pairing_s']))
json.dump(VOC, open('vocabs_%s.json' % suite, 'w'), indent=1)
json.dump({n: [dict(lterm=tstr(w['lterm']), iterm=tstr(w['iterm']) if w['iterm'] is not None else None,
                    score=w['score'], cross=w['cross'], size=w['size'], card=w['card'], rank=w['rank'])
               for w in ws] for n, (ws, info) in INFO.items()},
          open('selected_%s.json' % suite, 'w'), indent=1)
log('wrote vocabs_%s.json (%d vocabularies); %.0f s' % (suite, len(VOC), time.time() - t0))
