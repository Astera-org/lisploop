#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
sed -n '521p;1507p' "$D"
echo "--- how v5.md / build handles it"
grep -n 'fiber|' /tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5.md | head -5
cmp /tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5.md "$D" && echo "v5.md identical to v5-for-check.md"
grep -n -i 'pipe\|\\\\|' /tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/buildpdf.sh | head
echo "--- same rows in current repo plan"
grep -n 'Lift as the reverse of projection\|symmetry refund' /home/tlh24/lisploop/plan_v2c.md | cut -c1-200
echo "--- conditionals: guard qualifier anywhere?"
grep -n -i 'whether the guard\|guard was kept\|guard itself' "$D" | cut -c1-220
echo "--- of the true parent.s size"
grep -n -i "parent's size\|same size as the true parent\|classes of that size" "$D" | cut -c1-220
