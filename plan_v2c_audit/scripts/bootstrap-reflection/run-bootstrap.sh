#!/bin/bash
# Cold bootstrap in the scratch copy: v2 (library emptied first) and root (no library dir).
set -u
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/bootstrap-reflection
T=$S/tree
REF=/home/tlh24/lisploop/v2/library
cd $T/v2
rm -f library/*.sexp
echo "=== v2 cold bootstrap ==="
TIMEFORMAT='wall=%R s user=%U s sys=%S s'
time sbcl --script bootstrap/build-batteries.lisp > $S/boot-v2.out 2>&1
echo "exit=$?"; cat $S/boot-v2.out
echo "=== diff vs committed v2/library ==="
for f in $REF/*.sexp; do b=$(basename $f); if cmp -s $f library/$b; then echo "IDENTICAL $b"; else echo "DIFFERENT $b ($(diff $f library/$b | grep -c '^[<>]') lines)"; fi; done
cd $T
echo "=== root cold bootstrap ==="
rm -rf library
time sbcl --script bootstrap/build-batteries.lisp > $S/boot-root.out 2>&1
echo "exit=$?"; cat $S/boot-root.out
echo "=== diff root-built vs committed v2/library ==="
for f in $REF/*.sexp; do b=$(basename $f); if cmp -s $f library/$b; then echo "IDENTICAL $b"; else echo "DIFFERENT $b ($(diff $f library/$b | grep -c '^[<>]') lines)"; fi; done
