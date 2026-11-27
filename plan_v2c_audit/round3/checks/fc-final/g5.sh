#!/bin/bash
R=/home/tlh24/lisploop/plan_v2c_audit/reports
echo "=== length variants in verify-quotients ==="
grep -n -i -E 'length' $R/verify-quotients.md | grep -i -E 'six|all|top|first|variant|redundan|greedy' | head -20
echo "=== review dropped feedback: outside review text ==="
grep -n -i -E 'feedback|feed back|online' /home/tlh24/lisploop/plan_v2c_audit.md | head -20
echo "=== verify-probes P2/P1 rows ==="
sed -n '17,30p' $R/verify-probes.md
