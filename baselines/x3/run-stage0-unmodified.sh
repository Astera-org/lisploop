#!/bin/sh
# The Stage 0 harness exactly as committed (v2/experiments/stage0-audit.lisp), run in the copy.
# Same command as `make stage0` in v2/Makefile:24-25.
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W/kernel/v2" || exit 1
( time timeout 600 sbcl --dynamic-space-size 4096 --script experiments/stage0-audit.lisp ) \
  > "$W/logs/stage0-unmodified.log" 2>&1
echo "exit $? -> logs/stage0-unmodified.log"
