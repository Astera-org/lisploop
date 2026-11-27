#!/bin/bash
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/bootstrap-reflection
cd $S/tree/v2
TIMEFORMAT='stage0 wall=%R s'
time sbcl --dynamic-space-size 4096 --script experiments/stage0-audit.lisp > $S/stage0.out 2>&1
echo "exit=$?"
