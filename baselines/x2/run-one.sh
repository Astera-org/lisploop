#!/bin/bash
# Run one of the x2-*.lisp scripts in this directory against the private copy; log to logs/NAME.log.
# usage: bash run-one.sh x2-dump   (no extension)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="$1"
mkdir -p "$HERE/logs"
cd "$HERE"
( time timeout "${2:-900}" sbcl --dynamic-space-size 4096 --noinform --non-interactive \
     --load "$HERE/$NAME.lisp" ) > "$HERE/logs/$NAME.log" 2>&1
echo "exit $? -> logs/$NAME.log"
tail -${3:-12} "$HERE/logs/$NAME.log"
