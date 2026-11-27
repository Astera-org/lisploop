#!/bin/bash
# E5: (1) time the algebra milestone test module alone (root + v2); (2) the scaling script (v2).
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
for k in root v2; do
  if [ $k = root ]; then d=$E/repo; else d=$E/repo/v2; fi
  ( cd $d; s=$(date +%s.%N); timeout 600 sbcl --script tests/run.lisp algebra > $E/logs/e5_test_algebra_$k.log 2>&1; rc=$?; e=$(date +%s.%N); echo "PROCESS rc=$rc wall_s=$(echo "$e - $s" | bc)" >> $E/logs/e5_test_algebra_$k.log )
done
timeout 900 sbcl --dynamic-space-size 3000 --script $E/scripts/e5_algebra.lisp $E/repo/v2/ ${1:-30} > $E/logs/e5_algebra_v2.log 2>&1; echo "PROCESS rc=$?" >> $E/logs/e5_algebra_v2.log
