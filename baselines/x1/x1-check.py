#!/usr/bin/env python3
"""Independent re-implementation of the X1 baseline run, written from the baseline report's
description alone (its sections 1 and 4.1: configuration, order of terms, classes, tariff).

It shares no code with the v1 kernel. It enumerates terms in the order the report states,
groups them by their value vector on all assignments over GF(3), emits one equation per
non-representative member, and compares every file the Lisp run wrote. It also re-derives
the v1 ledger from the tariff stated in the report and compares it with the Lisp log.

Usage: python3 x1-check.py <directory holding the x1-*.txt files and x1-baseline.log>
"""
import re
import sys
from itertools import product

P = 3            # the field GF(3)
APP_BITS = 6     # 2 tag bits + 4 opcode bits
LIT_BITS = 4     # 2 tag bits + 2 value bits


def var_bits(nvars):
    return 2 + max(0, nvars - 1).bit_length()


def show(t):
    if t[0] == 'v':
        return 'x%d' % t[1]
    if t[0] == 'l':
        return str(t[1])
    return '(%s %s %s)' % (t[0], show(t[1]), show(t[2]))


def leaves(t):
    return 1 if t[0] in 'vl' else leaves(t[1]) + leaves(t[2])


def apps(t):
    return 0 if t[0] in 'vl' else 1 + apps(t[1]) + apps(t[2])


def nodes(t):
    return 1 if t[0] in 'vl' else 1 + nodes(t[1]) + nodes(t[2])


def int_width(k):
    return max(1, abs(k).bit_length())


def syntax_work(t):
    """ast.lisp: variable 1 + width(id) + type-work; literal 1 + type-work + value-work;
    application 1 + operator symbol (1 + type-work) + children. type-work((:gf 3)) = 3,
    value-work of a GF(3) value = 3."""
    if t[0] == 'v':
        return 1 + int_width(t[1]) + 3
    if t[0] == 'l':
        return 1 + 3 + 3
    return 1 + 4 + syntax_work(t[1]) + syntax_work(t[2])


def eval_work(t):
    """vm.lisp: one unit per :eval of a variable, 1 + value-work per :eval of a literal,
    one unit per :eval of an application plus one unit for its :apply."""
    if t[0] == 'v':
        return 1
    if t[0] == 'l':
        return 4
    return 2 + eval_work(t[1]) + eval_work(t[2])


def rows_of(nvars):
    """Row i assigns x_j = floor(i / 3^j) mod 3."""
    return [tuple((i // P ** j) % P for j in range(nvars)) for i in range(P ** nvars)]


def column(t, rows, cache):
    c = cache.get(t)
    if c is None:
        if t[0] == 'v':
            c = tuple(r[t[1]] for r in rows)
        elif t[0] == 'l':
            c = tuple(t[1] for _ in rows)
        else:
            a, b = column(t[1], rows, cache), column(t[2], rows, cache)
            c = tuple((x + y) % P for x, y in zip(a, b)) if t[0] == '+' else \
                tuple((x * y) % P for x, y in zip(a, b))
        cache[t] = c
    return c


def enumerate_terms(nvars, ops, lits, slack):
    """Yield ('step',) for every cursor step that offers nothing and ('term', t) for every
    step that offers a term, in the order of v1/enumerate.lisp:131-214, for body sizes
    1..slack. Ends after the :bound step of size = slack."""
    vb = var_bits(nvars)
    bucket = {}          # body size -> terms of that size, in the order built
    for size in range(1, slack + 1):
        # variables phase: one step per variable, then one step to leave the phase
        for i in range(nvars):
            if vb == size:
                t = ('v', i)
                bucket.setdefault(size, []).append(t)
                yield ('term', t)
            else:
                yield ('step',)
        yield ('step',)
        # literals phase
        for v in lits:
            if LIT_BITS == size:
                t = ('l', v)
                bucket.setdefault(size, []).append(t)
                yield ('term', t)
            else:
                yield ('step',)
        yield ('step',)
        # booleans phase: nothing to offer in these languages, one step to leave it
        yield ('step',)
        # applications phase
        for op in ops:
            total = size - APP_BITS
            if total < 2:
                yield ('step',)            # no composition: move to the next operator
                continue
            a = 1
            while a <= total - 1:
                b = total - a
                if a not in bucket or b not in bucket:
                    yield ('step',)        # a missing bucket: next composition
                    a += 1
                    continue
                left, right = list(bucket[a]), list(bucket[b])
                for x in left:
                    for y in right:        # the rightmost index moves fastest
                        t = (op, x, y)
                        bucket.setdefault(size, []).append(t)
                        yield ('term', t)
                a += 1
        yield ('step',)                    # no operator left: enter :finish
        yield ('step',)                    # :finish: the :bound event


def run(nvars, ops, lits, slack, limit=None):
    """Simulate the observation job. Returns a dict with the finished records, classes,
    equations and the ledger by category (cut at LIMIT when given)."""
    rows = rows_of(nvars)
    R = len(rows)
    per_row_inputs = sum(int_width(i) + 3 + 3 for i in range(nvars))
    charges = []                           # (category, amount) in the order charged
    records = []                           # (term, ledger total when finished)
    total = 0

    def charge(cat, amount):
        nonlocal total
        charges.append((cat, amount))
        total += amount

    charge('SETUP', R * (1 + 3 * nvars))
    built = 0
    for ev in enumerate_terms(nvars, ops, lits, slack):
        charge('ENUMERATION', 1)
        if ev[0] == 'term':
            t = ev[1]
            built += 1
            sw = syntax_work(t)
            charge('CONSTRUCTION', sw)
            ew = sw + per_row_inputs + eval_work(t)
            for _ in range(R):
                charge('SCHEDULING', 1)
                charge('EVALUATION', ew)
            charge('SCHEDULING', 1)
            charge('INDEXING', 1 + 3 * R)
            records.append((t, total))
    full_total = total
    ledger = {}
    spent = 0
    for cat, amount in charges:
        if limit is not None and spent + amount > limit:
            amount = limit - spent
        ledger[cat] = ledger.get(cat, 0) + amount
        spent += amount
        if limit is not None and spent >= limit:
            break
    if limit is not None:
        records = [r for r in records if r[1] <= limit]
    cache = {}
    classes = {}                           # value vector -> members in order
    order = []
    for t, _ in records:
        c = column(t, rows, cache)
        if c not in classes:
            classes[c] = []
            order.append(c)
        classes[c].append(t)
    equations = []
    for c in order:
        members = classes[c]
        for m in members[1:]:
            equations.append('(= %s %s)' % (show(m), show(members[0])))
    return dict(rows=R, records=records, order=order, classes=classes, equations=equations,
                ledger=ledger, work=spent, full_work=full_total, nvars=nvars)


def class_combination_count(nvars, ops, lits, slack):
    """How many distinct (operator, class, class) combinations a class-based evaluator would
    have to compute a column for at this bound: terms are built from class representatives
    only. Not a v1 number; an estimate of the least work a class engine needs."""
    rows = rows_of(nvars)
    vb = var_bits(nvars)
    bucket = {}
    seen = {}
    candidates = nonleaf = 0
    cache = {}
    for size in range(1, slack + 1):
        new = []
        if vb == size:
            new += [('v', i) for i in range(nvars)]
        if LIT_BITS == size:
            new += [('l', v) for v in lits]
        for t in new:
            candidates += 1
            c = column(t, rows, cache)
            if c not in seen:
                seen[c] = t
                bucket.setdefault(size, []).append(t)
        for op in ops:
            total = size - APP_BITS
            for a in range(1, total):
                b = total - a
                if a in bucket and b in bucket:
                    for x in list(bucket[a]):
                        for y in list(bucket[b]):
                            t = (op, x, y)
                            candidates += 1
                            nonleaf += 1
                            c = column(t, rows, cache)
                            if c not in seen:
                                seen[c] = t
                                bucket.setdefault(size, []).append(t)
    return candidates, nonleaf, len(seen), seen


def evaluation_breakdown(r):
    """Split the :evaluation category of a finished run into its parts, in ledger units:
    re-validation of the term's syntax, validation of the input declarations and values,
    :eval instructions, and :apply instructions (one per operator application per row)."""
    R, n = r['rows'], r['nvars']
    inputs = sum(int_width(i) + 3 + 3 for i in range(n))
    syn = sum(syntax_work(t) for t, _ in r['records']) * R
    inp = len(r['records']) * inputs * R
    app = sum(apps(t) for t, _ in r['records']) * R
    ev = sum(eval_work(t) for t, _ in r['records']) * R - app
    return dict(syntax_revalidation=syn, input_validation=inp, eval_instructions=ev, apply_instructions=app)


def parse_log(path):
    """Blocks of x1-baseline.log keyed by the name in square brackets (first occurrence)."""
    text = open(path).read()
    blocks = {}
    for m in re.finditer(r'^\[([^\]]+)\] field=.*?(?=^\[|^=====|^TOTAL)', text, re.S | re.M):
        name = m.group(1)
        if name in blocks:
            continue
        body = m.group(0)
        led = re.search(r'ledger-by-category=\(\((.*?)\)\)', body, re.S)
        ledger = {k: int(v) for k, v in re.findall(r':([A-Z-]+) \. (\d+)', led.group(1))}
        blocks[name] = dict(
            work=int(re.search(r' work=(\d+) wall', body).group(1)),
            records=int(re.search(r'records=(\d+)', body).group(1)),
            classes=int(re.search(r'classes=(\d+)', body).group(1)),
            equations=int(re.search(r'equations=(\d+)', body).group(1)),
            ledger=ledger)
    return blocks


def read_lines(path):
    return [l.rstrip('\n') for l in open(path) if not l.startswith('#')]


def class_lines(name, r):
    out = []
    for i, c in enumerate(r['order']):
        members = r['classes'][c]
        out.append('%s\t%d\t%d\t%s\t%s\t%s' % (name, i, len(members), ''.join(map(str, c)),
                                               show(members[0]), ' '.join(show(m) for m in members)))
    return out


def main(d):
    ok = True

    def check(label, cond, detail=''):
        nonlocal ok
        ok = ok and cond
        print('%s  %s %s' % ('PASS' if cond else 'FAIL', label, detail))

    log = parse_log(d + '/x1-baseline.log')
    shipped = [('obs1', 1, ['+', '*'], [0, 1], 20, 20000),
               ('obs2', 2, ['+', '*'], [], 24, 40000),
               ('obs3+', 3, ['+'], [], 44, 80000),
               ('obs3*', 3, ['*'], [], 44, 80000)]
    tag = {'obs1': 'obs1', 'obs2': 'obs2', 'obs3+': 'obs3plus', 'obs3*': 'obs3times'}
    by_job, all_eq, all_classes = [], [], []
    print('--- the four shipped jobs ---')
    for name, n, ops, lits, slack, limit in shipped:
        r = run(n, ops, lits, slack, limit)
        L = log[name]
        check('%s counts' % name,
              (len(r['records']), len(r['order']), len(r['equations'])) ==
              (L['records'], L['classes'], L['equations']),
              'records=%d classes=%d equations=%d' % (len(r['records']), len(r['order']), len(r['equations'])))
        check('%s ledger' % name, r['ledger'] == L['ledger'] and r['work'] == L['work'],
              'work=%d %s' % (r['work'], sorted(r['ledger'].items())))
        observed = [l.split('\t')[-1] for l in read_lines('%s/x1-observed-%s.txt' % (d, tag[name]))]
        check('%s observed terms, in order' % name, observed == [show(t) for t, _ in r['records']])
        by_job += ['%s\t%s' % (name, e) for e in r['equations']]
        all_eq += r['equations']
        all_classes += class_lines(name, r)
        k = len(r['records'])
        A = sum(apps(t) for t, _ in r['records'])
        if r['full_work'] <= limit:
            b = evaluation_breakdown(r)
            check('%s evaluation category splits as stated' % name, sum(b.values()) == r['ledger']['EVALUATION'],
                  str(sorted(b.items())))
        print('      cells: operator applications x rows = %d ; non-leaf trees x rows = %d' %
              (A * r['rows'], sum(1 for t, _ in r['records'] if t[0] not in 'vl') * r['rows']))
        if limit and r['full_work'] > limit:
            full = run(n, ops, lits, slack)
            w = [x[1] for x in full['records']]
            print('      cut off: record %d finished at work %d, record %d at %d' % (k, w[k - 1], k + 1, w[k]))
    check('x1-equations-by-job.txt (187 lines, same order)', by_job == read_lines(d + '/x1-equations-by-job.txt'),
          'lines=%d' % len(by_job))
    check('x1-equations.txt (sorted)', sorted(all_eq) == read_lines(d + '/x1-equations.txt'))
    check('x1-equations-distinct.txt', sorted(set(all_eq)) == read_lines(d + '/x1-equations-distinct.txt'),
          'distinct=%d' % len(set(all_eq)))
    check('x1-classes.txt', all_classes == read_lines(d + '/x1-classes.txt'), 'classes=%d' % len(all_classes))

    print('--- the same grammars and bit bounds, run to exhaustion ---')
    for name, n, ops, lits, slack, limit in shipped:
        r = run(n, ops, lits, slack)
        L = log[name + '-exhausted']
        check('%s exhausted counts and ledger' % name,
              (len(r['records']), len(r['order']), len(r['equations']), r['work'], r['ledger']) ==
              (L['records'], L['classes'], L['equations'], L['work'], L['ledger']),
              'records=%d classes=%d equations=%d work=%d' %
              (len(r['records']), len(r['order']), len(r['equations']), r['work']))
        check('%s exhausted equations' % name,
              sorted(r['equations']) == read_lines('%s/x1-exhausted-%s.equations.txt' % (d, tag[name])))
        check('%s exhausted classes' % name,
              class_lines(name + '-exhausted', r) == read_lines('%s/x1-exhausted-%s.classes.txt' % (d, tag[name])))

    print('--- the cut-off jobs against their natural bounds ---')
    for name, n, ops, lits, slack, limit in shipped[2:]:
        cut = set(run(n, ops, lits, slack, limit)['equations'])
        for s in (24, 34, 44):
            full = run(n, ops, lits, s)
            check('%s: the %d shipped equations are a subset of the %d at %d body bits (%d terms, %d classes)' %
                  (name, len(cut), len(full['equations']), s, len(full['records']), len(full['order'])),
                  cut <= set(full['equations']))
    print('--- equations a representatives-only engine would state (columns minus classes) ---')
    for name, n, ops, lits, slack, limit in shipped[:2]:
        cand, nonleaf, ncls, seen = class_combination_count(n, ops, lits, slack)
        print('      %s: %d columns - %d classes = %d equations, against %d from v1' %
              (name, cand, ncls, cand - ncls, len(run(n, ops, lits, slack)['equations'])))

    print('--- distributivity grammar: 3 variables, + and *, no literals ---')
    for slack in (24, 34):
        r = run(3, ['+', '*'], [], slack)
        L = log['dist%d' % slack]
        check('dist%d counts and ledger' % slack,
              (len(r['records']), len(r['order']), len(r['equations']), r['work'], r['ledger']) ==
              (L['records'], L['classes'], L['equations'], L['work'], L['ledger']),
              'records=%d classes=%d equations=%d work=%d' %
              (len(r['records']), len(r['order']), len(r['equations']), r['work']))
        check('dist%d equations' % slack,
              sorted(r['equations']) == read_lines('%s/x1-dist%d.equations.txt' % (d, slack)))
        check('dist%d classes' % slack,
              class_lines('dist%d' % slack, r) == read_lines('%s/x1-dist%d.classes.txt' % (d, slack)))
        b = evaluation_breakdown(r)
        check('dist%d evaluation category splits as stated' % slack, sum(b.values()) == r['ledger']['EVALUATION'],
              str(sorted(b.items())))
    r = run(3, ['+', '*'], [], 34)
    check('distributivity proposed at 34 bits',
          '(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))' in r['equations'])

    print('--- estimate, not a v1 number: columns a class-based evaluator must compute ---')
    print('    (terms built from class representatives only; one column per distinct')
    print('     (operator, class, class) combination; cells = non-leaf columns x rows)')
    for name, n, ops, lits, slack in [('obs1', 1, ['+', '*'], [0, 1], 20), ('obs2', 2, ['+', '*'], [], 24),
                                      ('obs3+', 3, ['+'], [], 24), ('obs3+', 3, ['+'], [], 34),
                                      ('obs3+', 3, ['+'], [], 44), ('obs3*', 3, ['*'], [], 24),
                                      ('obs3*', 3, ['*'], [], 34), ('obs3*', 3, ['*'], [], 44),
                                      ('dist', 3, ['+', '*'], [], 24), ('dist', 3, ['+', '*'], [], 34),
                                      ('dist', 3, ['+', '*'], [], 44)]:
        cand, nonleaf, ncls, seen = class_combination_count(n, ops, lits, slack)
        full = run(n, ops, lits, slack)
        check('%s slack=%d: a class engine finds the same classes and representatives' % (name, slack),
              [seen[c] for c in full['order']] == [full['classes'][c][0] for c in full['order']]
              and len(seen) == len(full['order']))
        R = full['rows']
        trees = len(full['records'])
        nl = sum(1 for t, _ in full['records'] if t[0] not in 'vl')
        A = sum(apps(t) for t, _ in full['records'])
        print('    %-6s slack=%2d rows=%2d  v1: trees=%6d classes=%5d work=%10d '
              'op-applications x rows=%8d non-leaf trees x rows=%8d | class engine: columns=%5d (non-leaf %5d) '
              'cells=%7d classes=%5d | ratios: work/cells=%7.1f op-apps/cells=%5.1f trees/cells=%5.1f' %
              (name, slack, R, trees, len(full['order']), full['work'], A * R, nl * R, cand, nonleaf,
               nonleaf * R, ncls, full['work'] / (nonleaf * R), A * R / (nonleaf * R), nl * R / (nonleaf * R)))
        assert ncls == len(full['order'])
    print('ALL CHECKS PASSED' if ok else 'SOME CHECKS FAILED')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
