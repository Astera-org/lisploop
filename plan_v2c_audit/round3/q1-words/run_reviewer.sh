#!/bin/bash
# Run the reviewer's three scripts in place; logs go to this work directory.
W=/home/tlh24/lisploop/plan_v2c_audit/round3/q1-words
R=/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer
cd "$R" || exit 1
export PYTHONDONTWRITEBYTECODE=1
( time python3 verify_guard_fourier_slices.py ) > "$W/rev_guard_fourier.log" 2>&1
( time python3 verify_ram_and_nmi.py ) > "$W/rev_ram_and_nmi.log" 2>&1
( time python3 exp_devils_advocate.py ) > "$W/rev_devils_advocate.log" 2>&1
echo done
