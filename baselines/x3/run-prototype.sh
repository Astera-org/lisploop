#!/bin/bash
# Re-run the audit's prototype on the kernel's spec rows (plan_v2c.md 8.5) in the writable copy vr/run,
# with the audit's own drivers, and compare each log with the audit's stored log (timings masked).
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W/vr/run" || exit 1
mask() { sed -E 's/ms +[0-9-]+/ms N/g' "$1"; }
{
  for name in r1 r1-occam r2; do
    sh "./run-$name.sh"
    cp "logs/$name.log" "$W/logs/vr-$name.log"
    if diff -q <(mask "logs/$name.log") <(mask "../orig/logs/$name.log") > /dev/null; then
      echo "$name.log: identical to the audit's stored log once timings are masked"
    else
      echo "$name.log: DIFFERS from the audit's stored log"
    fi
  done
} > "$W/logs/prototype-rerun.txt" 2>&1
cat "$W/logs/prototype-rerun.txt"
