#!/bin/bash
# run-baseline.sh -- reproduce the X1 baseline from a fresh copy of the v1 kernel.
#
#   bash run-baseline.sh              full run: copy, Lisp run, checksums, Python check, memory
#   X1_SKIP_MEMORY=1 bash run-baseline.sh    the same without the memory measurements
#   REPO=/path/to/lisploop bash run-baseline.sh    take v1/ from another checkout
#
# Nothing is written outside this directory. The repository is only read (cp -r).
# Outputs: x1-equations.txt (the 187), x1-equations-by-job.txt, x1-equations-distinct.txt,
# x1-equations-typed.sexp, x1-classes.txt, x1-observed-*.txt, x1-exhausted-*.txt, x1-bound*.txt,
# x1-dist*.txt,
# and the logs x1-baseline.log, x1-check.log, x1-memory.log.
set -u
W="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$W/../.." && pwd)}"
COPY="$W/v1"
trap 'rm -rf "$COPY"' EXIT

[ -d "$REPO/v1" ] || { echo "no kernel at $REPO/v1"; exit 2; }

echo "== 1. fresh copy of $REPO/v1 -> $COPY"
if [ -d "$COPY" ]; then rm -rf "$COPY"; fi
cp -r "$REPO/v1" "$COPY"

echo "== 2. the Lisp run (x1-baseline.lisp), log in x1-baseline.log"
export X1_V1="$COPY"
export X1_OUT="$W"
( time timeout 1800 sbcl --dynamic-space-size 8192 --non-interactive --no-userinit --no-sysinit \
    --load "$W/x1-baseline.lisp" ) > "$W/x1-baseline.log" 2>&1
grep '^real' "$W/x1-baseline.log" | sed 's/^/whole Lisp process, wall clock: /'
grep -q '^===== done =====' "$W/x1-baseline.log" || { echo "the Lisp run did not finish"; exit 1; }

echo "== 3. data files against the recorded baseline (x1-SHA256SUMS)"
if [ -f "$W/x1-SHA256SUMS" ]; then
  ( cd "$W" && sha256sum -c --quiet x1-SHA256SUMS ) && echo "all data files identical to the recorded baseline"
else
  ( cd "$W" && sha256sum x1-*.txt x1-*.sexp > x1-SHA256SUMS ) && echo "no recorded checksums; wrote x1-SHA256SUMS"
fi

echo "== 4. independent re-implementation (x1-check.py), log in x1-check.log"
python3 "$W/x1-check.py" "$W" > "$W/x1-check.log" 2>&1
grep -c '^PASS' "$W/x1-check.log" | sed 's/^/checks passed: /'
grep '^FAIL' "$W/x1-check.log"
tail -1 "$W/x1-check.log"

if [ -z "${X1_SKIP_MEMORY:-}" ]; then
  echo "== 5. retained memory, one process per configuration (x1-memory.lisp), log in x1-memory.log"
  bash "$W/run-memory.sh" > /dev/null
  cut -d' ' -f1-9,11-13 "$W/x1-memory.log"
fi

echo "== 6. the numbers"
echo "-- the four jobs as the bootstrap runs them (equations, work, classes):"
sed -n '/^===== A\. /,/^===== A2\. /p' "$W/x1-baseline.log" \
  | grep -E '^\[obs|claim=|records=|ledger-by|^   +\(:|cells:|pass-law|^TOTAL'
echo "-- wall time:"
sed -n '/^===== A2\. /,/^===== B\. /p' "$W/x1-baseline.log" | grep -E 'wall-us'
echo "-- the same grammars run to the end of their bit bounds:"
sed -n '/^===== B\. /,/^===== C\. /p' "$W/x1-baseline.log" | grep -E '^\[obs|claim=|records='
echo "-- distributivity grammar (3 variables, + and *):"
sed -n '/^===== E\. /,/^===== F\. /p' "$W/x1-baseline.log" \
  | grep -E '^\[dist|claim=|records=|cells:|lhs-observed|equation proposed'
echo "-- equations file: $(wc -l < "$W/x1-equations.txt") lines in $W/x1-equations.txt"
