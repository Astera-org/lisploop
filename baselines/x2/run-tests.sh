#!/bin/bash
# Run the v1 milestone test suites that exercise solver and guard discovery, in the private copy.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/logs"
for group in algebra guards propagation topology; do
  ( time timeout 900 sbcl --dynamic-space-size 4096 --script "$HERE/v1/tests/run.lisp" "$group" ) > "$HERE/logs/test-$group.log" 2>&1
  echo "== $group: exit $?"
  tail -6 "$HERE/logs/test-$group.log" | grep -v '^$'
done
