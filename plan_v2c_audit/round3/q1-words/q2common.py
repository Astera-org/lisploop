"""Shared per-task comparison used by q2_sound.py and q2_length.py."""
import random

from seqlib import term_str
from q2search import (plain_search, count_under_order, expected_random_order, pruned_search,
                      soft_counts, ref_audit)


def compare(task, configs, seed, trials=300):
    """plain OE once, then abstract-table search under every configuration
    (name -> (tables, absrows))."""
    rng = random.Random(seed)
    env, target, ttype = task['env'], task['target'], task['ttype']
    ps = plain_search(env, target, task['size'])
    ns = ps['found_size']
    lv = ps['levels'][ns - 1]
    out = dict(name=task['name'], term=term_str(task['term']), n_ops=len(task['ops']),
               size=task['size'], found_size=ns, inputs=len(env),
               plain_lib=ps['below'] + count_under_order(lv['n'], lv['hit'], range(len(lv['n']))),
               plain_rand=ps['below'] + expected_random_order(lv['n'], lv['hit'], rng, trials),
               plain_full=ps['below'] + ps['final_total'],
               plain_store=ps['store_below'], plain_wall=ps['wall_s'], cfg={})
    for cname, (tb, absrows) in configs.items():
        pr = pruned_search(env, target, ttype, tb, ns, absrows=absrows)
        last = pr['last']
        aud = ref_audit(task['term'], env, tb)
        r = dict(found=pr['found'], store=last['store_below'], store_j1=last['store_joint1'],
                 checks=pr['cum_checks'], wall=pr['wall_s'], audit=len(aud),
                 audit_first=[str(x) for x in aud[:3]])
        if pr['found']:
            sc = soft_counts(last, pr['ctx'])
            base = pr['cum_before'] + last['below']
            r['abs_lib'] = base + sc['lib']
            r['abs_opsoft'] = base + sc['op_soft']
            r['abs_rand'] = base + expected_random_order(last['fin_n'], last['fin_hit'], rng, trials)
            r['fin_n'] = sum(last['fin_n'])
        out['cfg'][cname] = r
    return out
