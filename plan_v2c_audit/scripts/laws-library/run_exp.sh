#!/bin/bash
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library
cd "$S"
echo "=== v2 theories"; ( time timeout 600 sbcl --dynamic-space-size 4096 --script /home/tlh24/lisploop/v2/tests/run.lisp theories ) > "$S/test-v2-theories.log" 2>&1; tail -5 "$S/test-v2-theories.log"
echo "=== exp_algebra"; ( time timeout 1500 sbcl --dynamic-space-size 8192 --script "$S/exp_algebra.lisp" ) > "$S/exp_algebra.log" 2>&1; tail -5 "$S/exp_algebra.log"
