#!/bin/sh
# EXP-B runner. Usage: run-b.sh TAG SPEC BOUND MAX-DEPTH HB MAX-WORK WALL SCHEMAS [CONDENSE]
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine
TAG=$1; shift
cd "$D" || exit 1
WALL=$5
timeout $((WALL + 120)) sbcl --dynamic-space-size 6144 --script "$D/exp-b.lisp" "$@" > "$D/exp-b-$TAG.out" 2>&1
echo "exit=$?" >> "$D/exp-b-$TAG.out"
head -c 6000 "$D/exp-b-$TAG.out"
