#!/bin/sh
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine
cd "$D" || exit 1
timeout 400 sbcl --dynamic-space-size 3072 --script "$D/exp-c.lisp" > "$D/exp-c.out" 2>&1
echo "exit=$?" >> "$D/exp-c.out"
cat "$D/exp-c.out"
