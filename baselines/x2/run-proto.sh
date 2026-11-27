#!/bin/bash
# Re-run, in a private copy, the two prototype runs that gate X2 refers to:
#   experiment C of plan_v2c_audit/proto/tg-probe.lisp (inverses and guards from an operator's table), and
#   R3 of plan_v2c_audit/verify-review/r3-guard.lisp (the divisibility guard checked by brute force).
# Then compare with the logs kept in the repository (timing columns removed for C).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$HERE/../.." && pwd)}"
AUDIT="$REPO/plan_v2c_audit"
mkdir -p "$HERE/proto-copy" "$HERE/logs"
cp "$AUDIT/proto/tg-probe.lisp" "$AUDIT/verify-review/r3-guard.lisp" "$HERE/proto-copy/"
cd "$HERE/proto-copy"
timeout 600 sbcl --dynamic-space-size 4GB --noinform --non-interactive \
     --load tg-probe.lisp --eval "(tg::main :c)" > "$HERE/logs/proto-c.log" 2>&1
echo "experiment C: exit $?"
timeout 600 sbcl --dynamic-space-size 4GB --noinform --non-interactive \
     --load tg-probe.lisp --load r3-guard.lisp --eval "(tg::r3)" > "$HERE/logs/proto-r3.log" 2>&1
echo "R3: exit $?"
timeout 600 sbcl --dynamic-space-size 4GB --noinform --non-interactive \
     --load tg-probe.lisp --load "$HERE/proto-table-check.lisp" --eval "(tg::table-check)" > "$HERE/logs/proto-table-check.log" 2>&1
echo "table check: exit $?"
grep -v "^;\|^$" "$HERE/logs/proto-table-check.log"
# The last column of C is milliseconds; drop it before comparing.
strip_ms() { sed -E 's/[[:space:]]+[0-9]+[[:space:]]*$//' "$1"; }
if diff <(strip_ms "$AUDIT/proto/logs/c.log") <(strip_ms "$HERE/logs/proto-c.log") > "$HERE/logs/proto-c.diff"; then
  echo "experiment C: identical to plan_v2c_audit/proto/logs/c.log (timing column ignored)"
else
  echo "experiment C: DIFFERS from the repository log, see logs/proto-c.diff"
fi
if diff "$AUDIT/verify-review/logs/r3.log" "$HERE/logs/proto-r3.log" > "$HERE/logs/proto-r3.diff"; then
  echo "R3: identical to plan_v2c_audit/verify-review/logs/r3.log"
else
  echo "R3: DIFFERS from the repository log, see logs/proto-r3.diff"
fi
