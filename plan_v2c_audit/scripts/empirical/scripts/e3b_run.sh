#!/bin/bash
# usage: e3b_run.sh TARGET MODE CPU_S MAX_SYNTAX
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
timeout 900 sbcl --dynamic-space-size ${HEAP_MB:-3000} --script $E/scripts/e3b_real_grammar.lisp "$@" > $E/logs/e3b_$1_$2.log 2>&1; echo "PROCESS rc=$?" >> $E/logs/e3b_$1_$2.log
