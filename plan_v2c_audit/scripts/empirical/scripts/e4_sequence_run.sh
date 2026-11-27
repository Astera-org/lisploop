#!/bin/bash
# usage: e4_sequence_run.sh TAG BUDGET fix|nofix [regimes...]
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
tag=$1; shift
timeout ${TMO:-900} sbcl --dynamic-space-size ${HEAP_MB:-2500} --script $E/scripts/e4_sequence.lisp "$@" > $E/logs/e4_seq_$tag.log 2>&1; echo "PROCESS rc=$?" >> $E/logs/e4_seq_$tag.log
