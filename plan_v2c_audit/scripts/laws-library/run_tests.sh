#!/bin/bash
# Runs read-only test modules of the root kernel; output goes to scratch.
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library
cd "$S"
for group in "laws" "theories" "abstraction" "symbolic" "guards" "algebra" "compression" "corpus" "propagation"; do
  echo "=== $group"
  ( time timeout 900 sbcl --dynamic-space-size 4096 --script /home/tlh24/lisploop/tests/run.lisp $group ) > "$S/test-$group.log" 2>&1
  tail -4 "$S/test-$group.log" | grep -v "^$"
done
