#!/bin/bash
# E2 (throughput, the Makefile's own benchmark workloads) and E6 (profiles). Run ALONE (timing-sensitive).
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
L=$E/logs
cap=${1:-60}
uptime > $L/e2_load_before.txt
for k in root v2; do
  if [ $k = root ]; then d=$E/repo; else d=$E/repo/v2; fi
  cd $d
  for spec in "linear 61" "quadratic 70"; do
    set -- $spec
    timeout $((cap+120)) sbcl --dynamic-space-size 2048 --script benchmark.lisp search $1 $2 $cap batch > $L/e2_bench_${k}_$1_$2.log 2>&1
  done
done
cd $E/repo; timeout 300 sbcl --dynamic-space-size 2048 --script benchmark.lisp meter > $L/e2_meter_root.log 2>&1
# E6a: the Makefile's benchmark-profile target, verbatim arguments but a shorter wall cap
cd $E/repo; timeout $((cap+120)) sbcl --dynamic-space-size 2048 --script benchmark.lisp search quadratic 70 $cap batch profile > $L/e6_benchmark_profile_root.log 2>&1
# E6b: profile of a recursion-synthesis job (map-adjacent, active grammar, no schemas, 35M work)
timeout 300 sbcl --dynamic-space-size 3000 --script $E/scripts/e6_profile_synthesis.lisp map-adjacent 35000000 > $L/e6_profile_synthesis_map-adjacent.log 2>&1
uptime > $L/e2_load_after.txt
