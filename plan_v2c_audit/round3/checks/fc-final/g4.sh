#!/bin/bash
R=/home/tlh24/lisploop/plan_v2c_audit/reports
echo "=== one step from the answer / parent-size in verify-handoff ==="
grep -n -i -E 'one step|parent|43|47|sibling|same size|of that size|ruled out|rule out' $R/verify-handoff.md | head -60
echo "=== versions of the length ==="
grep -n -i -E 'versions of|all .*length|first six|without (the )?(repetition|redundan)|redundan' $R/verify-words.md | head -30
echo "=== dropped / repair in verify-probes ==="
grep -n -i -E 'dropped|withdr|retract|repair|feed' $R/verify-probes.md | head -30
echo "=== two-part with many labels ==="
grep -n -i -E 'two-part|pair word|product' $R/verify-words.md | head -30
