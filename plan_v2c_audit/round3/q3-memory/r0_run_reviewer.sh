#!/bin/bash
# Step 0: run the reviewer's own scripts unmodified (EXP A of exp_devils_advocate.py, and all of
# verify_ram_and_nmi.py) and keep the logs.
W=/home/tlh24/lisploop/plan_v2c_audit/round3/q3-memory
R=/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer
cd $W
( time python3 r0_expA.py ) > r0_expA.log 2>&1
( time python3 $R/verify_ram_and_nmi.py ) > r0_verify_ram.log 2>&1
cat r0_expA.log
cat r0_verify_ram.log
