#!/bin/bash
# E1b: root kernel suite again, AFTER root bootstrap has produced library/*.sexp in the copy.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E/repo; s=$(date +%s.%N); timeout 900 sbcl --script tests/run.lisp kernel > $E/logs/e1b_root_kernel.log 2>&1; rc=$?; e=$(date +%s.%N)
echo "E1b root_kernel_after_bootstrap rc=$rc wall_s=$(echo "$e - $s" | bc)" | tee -a $E/logs/e1_summary.log
