#!/bin/bash
# Build and score the word pools for the remaining grammar configurations (see wordpool.py CONFIGS).
cd /home/tlh24/lisploop/plan_v2c_audit/round3/q1-words || exit 1
for c in stage1 stage2 seed1 lib_fold; do
  ( time python3 wordpool.py $c --procs 14 ) > run_pool_$c.out 2>&1
done
echo done
