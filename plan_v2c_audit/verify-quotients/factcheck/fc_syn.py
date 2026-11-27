"""Fact-check helper: break down the 69% synonym-recovery figure (copy of the logic in q5_reuse.py part (a))."""
from seqlib import OPNAMES, OPSIG, HAND6, build_tables
tb = build_tables(HAND6, M=2000, kind='iid', seed=0)
supp = {}
for name in OPNAMES:
    s = set()
    for j in range(len(tb.q)):
        for key, c in tb.tab[j][name].items():
            for v in c:
                s.add((j, key, v))
    supp[name] = s
def jacc(a, b):
    return len(supp[a] & supp[b]) / len(supp[a] | supp[b])
def neighbours(name, k=None, same_type=True):
    out = [(jacc(name, o), o) for o in OPNAMES if o != name and (not same_type or OPSIG[o] == OPSIG[name])]
    out.sort(reverse=True)
    return out[:k] if k else out
FAM = [['map_adj_add', 'map_adj_sub', 'map_adj_mul', 'map_adj_min', 'map_adj_max'],
       ['filter_pos', 'filter_neg', 'filter_even', 'filter_odd'],
       ['inc_all', 'dec_all', 'dbl_all', 'neg_all', 'abs_all', 'sq_all', 'half_all'],
       ['sum', 'head', 'last', 'min_el', 'max_el'],
       ['sort', 'sort_desc', 'reverse'],
       ['running_sum', 'running_max', 'running_min'],
       ['zip_add', 'zip_sub', 'zip_mul', 'zip_min', 'zip_max']]
famof = {o: i for i, f in enumerate(FAM) for o in f}
print('operators in library', len(OPNAMES), 'in a family', len(famof))
tot = hit = 0; chance = 0.0; hit_any = 0
for f in FAM:
    h = 0; ch = 0.0; ha = 0
    for o in f:
        same = [x for x in OPNAMES if x != o and OPSIG[x] == OPSIG[o]]
        nb = neighbours(o, 1)[0][1]
        nb_any = neighbours(o, 1, same_type=False)[0][1]
        h += famof.get(nb) == famof[o]
        ha += famof.get(nb_any) == famof[o]
        ch += (len([x for x in same if famof.get(x) == famof[o]])) / len(same)
    print('%-12s size %d  top-1 same-type in family: %d  (chance %.2f)  top-1 any-type in family: %d' % (f[0], len(f), h, ch, ha))
    tot += len(f); hit += h; chance += ch; hit_any += ha
print('total %d of %d = %.0f%%; expected by chance %.1f of %d = %.0f%%; without same-type restriction %d of %d' % (hit, tot, 100*hit/tot, chance, tot, 100*chance/tot, hit_any, tot))
