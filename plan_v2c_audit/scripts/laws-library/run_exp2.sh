#!/bin/bash
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library
cd "$S"
( time timeout 1700 sbcl --dynamic-space-size 6000 --script "$S/exp_solvers.lisp" ) > "$S/exp_solvers.log" 2>&1
tail -30 "$S/exp_solvers.log"
