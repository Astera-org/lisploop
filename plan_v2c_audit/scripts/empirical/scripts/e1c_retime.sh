#!/bin/bash
# E1c: second timing pass of the four suites (first pass ran under load average ~11).
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
uptime > $E/logs/e1c_summary.log
for k in root v2; do for s in kernel milestones; do
  if [ $k = root ]; then d=$E/repo; else d=$E/repo/v2; fi
  ( cd $d; t0=$(date +%s.%N); timeout 600 sbcl --script tests/run.lisp $s > $E/logs/e1c_${k}_$s.log 2>&1; rc=$?; t1=$(date +%s.%N)
    echo "E1c ${k}_$s rc=$rc wall_s=$(echo "$t1 - $t0" | bc) :: $(tail -1 $E/logs/e1c_${k}_$s.log)" >> $E/logs/e1c_summary.log )
done; done
