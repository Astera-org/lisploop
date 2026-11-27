#!/bin/sh
# EXP-A runner: enumerator growth and redundancy. Writes only into the scratch directory.
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine
cd "$D" || exit 1
timeout 600 sbcl --dynamic-space-size 4096 --script "$D/exp-a.lisp" > "$D/exp-a.out" 2>&1
echo "exit=$?" >> "$D/exp-a.out"
tail -n 120 "$D/exp-a.out"
