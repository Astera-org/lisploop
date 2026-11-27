#!/bin/bash
# The two data files, read and replayed with no kernel loaded.
W="$(cd "$(dirname "$0")" && pwd)"
( time timeout 300 sbcl --noinform --non-interactive --load "$W/check-plain-read.lisp" ) \
  > "$W/logs/check-plain-read.log" 2>&1
echo "exit $? -> logs/check-plain-read.log"
grep -v "^;" "$W/logs/check-plain-read.log" | grep -v "^$"
