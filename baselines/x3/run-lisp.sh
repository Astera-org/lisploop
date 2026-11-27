#!/bin/bash
# usage: run-lisp.sh SCRIPT.lisp LOGNAME [HEAP_MB] -- run one of the base-x3 kernel-side scripts in the copy.
W="$(cd "$(dirname "$0")" && pwd)"
export X3_V2_ROOT="$W/kernel/v2/" X3_WORK="$W/"
( time timeout 900 sbcl --dynamic-space-size "${3:-4096}" --noinform --non-interactive --load "$W/$1" ) \
  > "$W/logs/$2.log" 2>&1
echo "exit $? -> logs/$2.log"
