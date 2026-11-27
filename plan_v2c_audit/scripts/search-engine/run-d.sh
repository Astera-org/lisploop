#!/bin/sh
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine
cd "$D" || exit 1
timeout 500 sbcl --dynamic-space-size 6144 --script "$D/exp-d.lisp" > "$D/exp-d.out" 2>&1
echo "exit=$?" >> "$D/exp-d.out"
cut -c1-420 "$D/exp-d.out"
