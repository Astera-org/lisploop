#!/usr/bin/env python3
"""Run ONLY EXP A of the reviewer's exp_devils_advocate.py (A1: G1 RAM; A2: lifted tg-probe-style tasks),
unmodified, by importing it from the scratch copy.  Output -> logs/reviewer_expA.log (see run_reviewer_a.sh)."""
import sys
sys.path.insert(0, '/home/tlh24/lisploop/plan_v2c_audit/round3/reviewer')
import exp_devils_advocate as r
r.run_exp_a()
