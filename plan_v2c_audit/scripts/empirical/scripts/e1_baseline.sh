#!/bin/bash
# E1 baseline: kernel + milestone suites and cold bootstrap, root and v2. Runs serially.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
R=$E/repo
L=$E/logs
run() { # name dir cmd...
  name=$1; dir=$2; shift 2
  ( cd $dir; s=$(date +%s.%N); timeout 900 "$@" > $L/e1_$name.log 2>&1; rc=$?; e=$(date +%s.%N);
    echo "E1 $name rc=$rc wall_s=$(echo "$e - $s" | bc)" ) | tee -a $L/e1_summary.log
}
: > $L/e1_summary.log
run root_kernel      $R    sbcl --script tests/run.lisp kernel
run root_milestones  $R    sbcl --script tests/run.lisp milestones
run v2_kernel        $R/v2 sbcl --script tests/run.lisp kernel
run v2_milestones    $R/v2 sbcl --script tests/run.lisp milestones
run root_bootstrap   $R    sbcl --script bootstrap/build-batteries.lisp
run v2_bootstrap     $R/v2 sbcl --script bootstrap/build-batteries.lisp
