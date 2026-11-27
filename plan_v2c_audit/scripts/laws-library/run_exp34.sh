#!/bin/bash
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library
cd "$S"
echo "=== exp_rewrite"; ( time timeout 900 sbcl --dynamic-space-size 6000 --script "$S/exp_rewrite.lisp" ) > "$S/exp_rewrite.log" 2>&1; tail -25 "$S/exp_rewrite.log" | cut -c1-600
echo "=== exp_bootstrap"; ( time timeout 1500 sbcl --dynamic-space-size 6000 --script "$S/exp_bootstrap.lisp" ) > "$S/exp_bootstrap.log" 2>&1; grep "##\|!!\|Saved\|real\|rror" "$S/exp_bootstrap.log" | cut -c1-300
