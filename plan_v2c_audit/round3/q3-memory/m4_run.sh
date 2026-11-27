#!/bin/bash
# M2(2): lifted position space, eight tasks, three row seeds (run in parallel).
W=/home/tlh24/lisploop/plan_v2c_audit/round3/q3-memory
cd $W
for s in 1 2 3; do
  ( time python3 m4_lifted.py --seed $s ) > m4_lifted_seed$s.log 2>&1 &
done
wait
tail -3 m4_lifted_seed1.log m4_lifted_seed2.log m4_lifted_seed3.log
