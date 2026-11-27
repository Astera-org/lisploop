#!/bin/bash
# E2/E6 larger flat-search runs with the repo's own benchmark.lisp (root kernel): the Makefile's "one large run"
# (quartic 77), then larger bounds, then a CPU profile of a multi-second run. Run ALONE.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E/repo
for b in 77 82 86 90; do
  timeout 200 sbcl --dynamic-space-size 2048 --script benchmark.lisp search quartic $b 40 batch > $E/logs/e2_bench_root_quartic_$b.log 2>&1
done
timeout 200 sbcl --dynamic-space-size 2048 --script benchmark.lisp search quartic 86 40 batch profile > $E/logs/e6_benchmark_profile_root_quartic_86.log 2>&1
