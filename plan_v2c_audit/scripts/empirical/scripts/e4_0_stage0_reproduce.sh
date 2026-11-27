#!/bin/bash
# E4.0: reproduce v2 `make stage0` unmodified (350k cap) in the scratch copy; baseline for E4.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E/repo/v2; s=$(date +%s.%N)
timeout 2400 sbcl --dynamic-space-size 4096 --script experiments/stage0-audit.lisp > $E/logs/e4_0_stage0_reproduce.log 2>&1; rc=$?
e=$(date +%s.%N); echo "E4.0 stage0 rc=$rc wall_s=$(echo "$e - $s" | bc)" >> $E/logs/e4_0_stage0_reproduce.log
