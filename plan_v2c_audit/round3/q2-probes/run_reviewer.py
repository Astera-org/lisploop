"""Step 1: run the reviewer's own EXP C and EXP D (exp_devils_advocate.py) unchanged,
without the slow EXP A/B, and record what they print.

usage: python3 run_reviewer.py > run_reviewer.log
"""
import sys

REV = '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer'
sys.path.insert(0, REV)
import exp_devils_advocate as E   # noqa: E402  (main is guarded; importing runs nothing)

E.run_exp_c()
E.run_exp_d()
