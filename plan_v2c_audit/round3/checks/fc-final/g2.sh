#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
awk 'NR>=132 && NR<=592' "$D" | grep -n -o -E '[^.]{0,220}(§6\.[0-9]|§7\.[2456]|§8\.[5678]|Appendix [A-D]|§6\b|§7\b|§8\b|§10|§11)[^.]{0,120}' | awk -F: '{printf "%d:", $1+131; $1=""; print}'
