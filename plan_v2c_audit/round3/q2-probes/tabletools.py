"""Helpers: tables as plain transition dictionaries, unions, filters, exhaustive scopes."""
import itertools
from collections import Counter

from seqlib import L, I, OPNAMES, OPSIG, OPFN
from probegen import PTables


def trans_of(tb):
    """{(j, opname): {key: set(output labels)}}"""
    return {(j, name): {k: set(c) for k, c in d.items()}
            for j, tab in enumerate(tb.tab) for name, d in tab.items()}


def union_trans(ts):
    out = {}
    for t in ts:
        for jn, d in t.items():
            o = out.setdefault(jn, {})
            for k, s in d.items():
                o.setdefault(k, set()).update(s)
    return out


def tables_from_trans(quotients, tr, keep=None):
    """A PTables object from a transition dictionary (every count = 1).
    keep(j, name, key, labels) -> bool selects the entries used for filtering;
    dropped entries are unseen (= anything)."""
    tb = PTables.__new__(PTables)
    tb.q = quotients
    tb.opnames = OPNAMES
    tb.tab = []
    tb.dom = []
    for j in range(len(quotients)):
        dom = {L: set(), I: set()}
        tab = {}
        for name in OPNAMES:
            at, rt = OPSIG[name]
            d = tr.get((j, name), {})
            for k, s in d.items():
                dom[rt].update(s)
                for t, a in zip(at, k):
                    dom[t].add(a)
            tab[name] = {k: Counter(dict.fromkeys(s, 1)) for k, s in d.items()
                         if keep is None or keep(j, name, k, s)}
        tb.tab.append(tab)
        tb.dom.append(dom)
    tb._succ = [None] * len(quotients)
    return tb


def all_lists(n, k):
    """Every list of length <= n with elements in [-k, k]."""
    vals = range(-k, k + 1)
    out = []
    for m in range(n + 1):
        out.extend(itertools.product(vals, repeat=m))
    return out


def scope_probes(lists1, pairs_ll, ints, lists_il):
    """Probes for an exhaustive scope: unary list operators on lists1, list x list
    operators on every pair in pairs_ll (a list of (A, B) list-sets, all A x B pairs),
    int operators on ints (all pairs), int x list operators on ints x lists_il."""
    cols = {(L,): (list(lists1),), (I,): (list(ints),)}
    a, b = [], []
    for A, B in pairs_ll:
        for x in A:
            a.extend([x] * len(B))
            b.extend(B)
    cols[(L, L)] = (a, b)
    cols[(I, I)] = ([x for x in ints for _ in ints], [y for _ in ints for y in ints])
    cols[(I, L)] = ([n for n in ints for _ in lists_il], [x for _ in ints for x in lists_il])
    probes = {}
    for name in OPNAMES:
        at, rt = OPSIG[name]
        c = cols[at]
        probes[name] = (c, list(map(OPFN[name], *c)))
    return probes, {''.join(sg): len(c[0]) for sg, c in cols.items()}
