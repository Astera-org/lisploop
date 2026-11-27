#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
sed -n '374p;414p;422p;424p;428,441p' "$D"
echo ====
sed -n '132,134p;189p;329p' "$D" | cut -c1-900
