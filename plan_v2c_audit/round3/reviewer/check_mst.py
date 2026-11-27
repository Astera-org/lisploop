#!/usr/bin/env python3
import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
from exp_lang_heuristics_v2 import make_61_library, build_abstract_domains, compute_op_mdl_scores, synthesize_oe

ops = make_61_library()
domains, tables, all_states, _ = build_abstract_domains(ops)
xs_rows = ((3,-1,4,2), (-2,5,0,-3,1), (2,4,6), (1,-2,3,-4,5,0), (7,1), (0,-1,2,3))
ys_rows = ((1,2,-1,3), (4,-1,2,0,-2), (0,2,4), (-1,2,-3,4,-5,1), (2,5), (3,1,0,-2))
def eval_p(p, xs, ys):
    if p == 'xs': return xs
    if p == 'ys': return ys
    return ops[p[0]][2](*[eval_p(a, xs, ys) for a in p[1:]])

tasks = [
    ("T1", ('sum', ('map_adj_sub', ('sort', 'xs'))), 'int', 3, [('xs','seq',xs_rows)]),
    ("T3", ('sum', ('zip_mul', 'xs', ('shift1', 'xs'))), 'int', 3, [('xs','seq',xs_rows)]),
    ("T4", ('sum', ('filter_pos', ('zip_sub', 'xs', 'ys'))), 'int', 3, [('xs','seq',xs_rows), ('ys','seq',ys_rows)]),
    ("T5", ('len', ('filter_even', ('map_adj_add', 'xs'))), 'int', 3, [('xs','seq',xs_rows)]),
    ("T6", ('running_sum', ('reverse', ('inc_all', 'xs'))), 'seq', 3, [('xs','seq',xs_rows)]),
    ("T8", ('dbl_all', ('sort', ('abs_all', 'xs'))), 'seq', 3, [('xs','seq',xs_rows)]),
    ("T9", ('sort', ('dbl_all', ('filter_pos', ('map_adj_add', 'xs')))), 'seq', 4, [('xs','seq',xs_rows)]),
]
for tag, prog, tty, mo, inps in tasks:
    tgt = tuple(eval_p(prog, xs_rows[i], ys_rows[i]) for i in range(len(xs_rows)))
    sc = compute_op_mdl_scores(ops, inps, tty, tgt, domains, tables, all_states, mo, list(range(4)))
    ord_ops = sorted(ops.keys(), key=lambda k: sc[k])
    _, m_c, m_st, _, _, _, _ = synthesize_oe(ops, inps, tty, tgt, mo, domains=domains, tables=tables, all_states=all_states, use_abstract_pruning=True, op_order=ord_ops, budget=400000)
    print(f"{tag}: m_c={m_c}, m_st={m_st}")
