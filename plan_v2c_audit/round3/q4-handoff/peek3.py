"""Small look-ups into the b3 offset/scale JSON files."""
import json
import sys
from collections import Counter

from hlib import gmean

for fn in sys.argv[1:]:
    J = json.load(open(fn))
    T = J['tasks']
    print(fn)
    print('  arm B (labels, constant operator in grammar) lost the answer in %d of %d' % (
        sum(1 for t in T if not t['B_found']), len(T)))
    print('  A / D2 = %.1fx;  A / E = %.1fx;  B / D2 = %.2fx;  A / D = %.1fx' % (
        gmean([t['A'] / t['D2'] for t in T]), gmean([t['A'] / t['E'] for t in T]),
        gmean([t['B'] / t['D2'] for t in T]), gmean([t['A'] / t['D'] for t in T])))
    print('  arm C fired at bank level relative to the planted near miss size: %s' % dict(Counter(
        t['C_level'] - (t['size'] - 1) for t in T)))
    print('  planted constants: %s' % dict(Counter((t['fam'], t['c']) for t in T)))
    for h in (0, 1):
        Q = [t for t in T if t['hU'] == h]
        if Q:
            print('  near misses with label bound %d (n=%d): D / D2 = %.2fx,  C / D = %.2fx' % (
                h, len(Q), gmean([t['D'] / t['D2'] for t in Q]), gmean([t['C'] / t['D'] for t in Q])))
