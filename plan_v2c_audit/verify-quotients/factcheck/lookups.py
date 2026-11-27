import json
SRC = '/home/tlh24/lisploop/plan_v2c_audit/verify-quotients/'
res = json.load(open(SRC + 'q2_main.json'))
to_hit = sum(r['abs_opsoft'] for r in res)
full = sum(r['abs_cum_before'] + r['abs_below'] + r['abs_final_total'] for r in res)
ck = sum(r['abs_checks'] for r in res)
print('evaluations to hit %d; evaluations with complete last level %d; look-ups (complete levels) %d' % (to_hit, full, ck))
print('look-ups per evaluation: to-hit %.2f, like-for-like %.2f' % (ck / to_hit, ck / full))
print('plain to hit %d; plain complete levels %d' % (sum(r['plain_lib'] for r in res), sum(r['plain_full'] for r in res)))
