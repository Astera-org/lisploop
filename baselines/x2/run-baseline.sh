#!/bin/bash
# Reproduce the X2 baseline from a fresh copy of the v1 kernel. About two minutes.
#   bash run-baseline.sh
# Nothing under /home/tlh24/lisploop is written. Everything lands in this directory:
#   v1/                    the private copy the runs use (deleted and re-made each time)
#   x2-solvers.txt         one block per solver and domain (24 blocks)
#   x2-solvers.sexp        the same, machine-readable
#   x2-match-table.tsv     the table a new engine is compared with
#   x2-candidates.txt      every answer term the milestone code enumerates
#   logs/*.log             the log of every step
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
trap 'rm -rf "$HERE/v1" "$HERE/proto-copy"' EXIT
cd "$HERE"
mkdir -p logs

echo "== 1. fresh copy of v1"
bash "$HERE/copy-v1.sh"

echo "== 2. the milestone test suites (algebra is the one that asserts the eight solvers)"
bash "$HERE/run-tests.sh"

echo "== 3. the eight solvers on GF(5), GF(7) and the integers: answer terms, guards, grades, work"
bash "$HERE/run-one.sh" x2-dump 900 3

python3 "$HERE/work-ranges.py" > "$HERE/logs/work-ranges.log" 2>&1
cat "$HERE/logs/work-ranges.log"

echo "== 4. wall time without instrumentation"
bash "$HERE/run-one.sh" x2-time 900 2

echo "== 5. primitive semantics, and what each guard means by brute force"
bash "$HERE/run-one.sh" x2-semantics 900 1

echo "== 6. which results depend on the grid, the query rows, the literals, the bound, the operators, the field"
bash "$HERE/run-one.sh" x2-variants 1500 1

echo "== 7. the composite cases a*x + b = c and x + x = c"
bash "$HERE/run-one.sh" x2-composite 900 1

echo "== 8. the enumerated answer language, and the guard language against its bound"
bash "$HERE/run-one.sh" x2-extras 900 1

echo "== 9. what-if: flooring instead of truncating integer division"
bash "$HERE/run-one.sh" x2-floor 900 1

echo "== 10. would a conditional answer term win the milestone code's selection, were it in the language?"
bash "$HERE/run-one.sh" x2-section 900 1

echo "== 11. the prototype's experiment C and the review's R3, re-run and compared with the repository logs"
bash "$HERE/run-proto.sh"

echo "== 12. is this run the recorded baseline?"
if [ -f "$HERE/x2-SHA256SUMS" ]; then
  ( cd "$HERE" && sha256sum -c --quiet x2-SHA256SUMS ) && echo "all data files identical to the recorded baseline"
else
  ( cd "$HERE" && sha256sum x2-solvers.sexp x2-match-table.tsv > x2-SHA256SUMS ) && echo "no recorded checksums; wrote x2-SHA256SUMS"
fi
