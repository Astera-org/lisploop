#!/bin/bash
# Run the in-scope kernel test modules (none of these write files) for root and v2.
for root in /home/tlh24/lisploop /home/tlh24/lisploop/v2; do
  echo "######## $root"
  ( cd /tmp && time sbcl --script $root/tests/run.lisp core codec invariants structural topology metrics lifting closures totality symbolic 2>&1 | grep -v "^; \|STYLE-WARNING\|^;\|^$" | tail -25 )
done
