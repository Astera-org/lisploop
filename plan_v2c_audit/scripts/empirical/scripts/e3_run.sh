#!/bin/bash
# usage: e3_run.sh v1|v2 GRAMMAR MODE CPU_SECONDS [MAX_SYNTAX]   log -> logs/e3_<kernel>_<grammar>_<mode>.log
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
k=$1; shift
if [ "$k" = v1 ]; then root=$E/repo/; else root=$E/repo/v2/; fi
timeout 900 sbcl --dynamic-space-size ${HEAP_MB:-3000} --script $E/scripts/e3_growth.lisp $root "$@" > $E/logs/e3_${k}_$1_$2.log 2>&1
echo "PROCESS rc=$?" >> $E/logs/e3_${k}_$1_$2.log
