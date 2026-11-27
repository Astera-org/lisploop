#!/bin/bash
# The harness runs were made twice (before and after a progress line was added to x3-harness.lisp).
# Compare the two sets of tables with the CPU timings masked.  The second set also holds the x1000 run,
# which is removed before comparing: its block in Table 2 and its line in Table 1.
W="$(cd "$(dirname "$0")" && pwd)"
clean() {
  sed -E 's/cpu +[0-9.]+ s/cpu N s/' "$1" \
    | awk '/^-- as-written-x1000/{skip=1} /^TABLE 3/{skip=0} !skip' \
    | grep -v "x1000" | grep -v "^$"
}
if diff <(clean "$W/logs/tables-before-rerun.txt") <(clean "$W/logs/tables.txt") > "$W/logs/compare-rerun.diff"; then
  echo "second run identical to the first (work, outcomes, programs, grammars), timings aside"
else
  echo "runs differ: see logs/compare-rerun.diff"; head -20 "$W/logs/compare-rerun.diff"
fi | tee "$W/logs/compare-rerun.txt"
bash "$W/finish.sh"
