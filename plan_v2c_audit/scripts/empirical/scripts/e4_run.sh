#!/bin/bash
# usage: e4_run.sh TAG TARGET MAX_BUDGET [BOUND_ADD] [MAX_DEPTH] [HEUR_BUDGET] [WALL_S] ; log -> logs/e4_TAG_TARGET.log
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
tag=$1; shift; target=$1
wall=${6:-1200}
s=$(date +%s.%N)
timeout $((wall + 120)) sbcl --dynamic-space-size ${HEAP_MB:-4096} --script $E/scripts/e4_rescue.lisp "$@" > $E/logs/e4_${tag}_${target}.log 2>&1; rc=$?
e=$(date +%s.%N); echo "PROCESS rc=$rc total_wall_s=$(echo "$e - $s" | bc)" >> $E/logs/e4_${tag}_${target}.log
