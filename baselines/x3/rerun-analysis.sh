#!/bin/bash
# x3-common.lisp was changed once after analyze-rows.lisp and show-boot.lisp had first been run (the scratch
# package now uses CL).  Re-run both with the final prelude, then the scripts that depend on them, and
# confirm that the data files come out the same.
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W" || exit 1
cp x3-row-analysis.sexp logs/x3-row-analysis.before.sexp
cp x3-specs.lisp logs/x3-specs.before.lisp
cp x3-prerequisites.lisp logs/x3-prerequisites.before.lisp
bash run-lisp.sh show-boot.lisp show-boot
bash run-lisp.sh analyze-rows.lisp analyze-rows
bash run-lisp.sh dump-specs.lisp dump-specs
bash run-lisp.sh dump-prereqs.lisp dump-prereqs
bash run-lisp.sh probe-primitives.lisp probe-primitives
bash run-check-plain.sh > /dev/null
{
  for pair in "x3-row-analysis.sexp logs/x3-row-analysis.before.sexp" \
              "x3-specs.lisp logs/x3-specs.before.lisp" \
              "x3-prerequisites.lisp logs/x3-prerequisites.before.lisp"; do
    set -- $pair
    if cmp -s "$1" "$2"; then echo "$1: unchanged by the re-run"; else echo "$1: CHANGED by the re-run"; fi
  done
  grep "total:" logs/check-plain-read.log
} | tee logs/rerun-analysis.txt
