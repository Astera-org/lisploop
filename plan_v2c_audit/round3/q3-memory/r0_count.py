"""What the reviewer's verify_ram_and_nmi.py PART 2 actually searches: count the operators."""
import sys
from collections import Counter
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library

ops = make_61_library()
sig = Counter((v[0], v[1]) for v in ops.values())
u_seq = [k for k, v in ops.items() if v[0] == ('seq',) and v[1] == 'seq']
print('library size', len(ops))
print('signatures', dict(sig))
print('operators PART 2 searches over (unary seq -> seq only):', len(u_seq))
print(u_seq)
