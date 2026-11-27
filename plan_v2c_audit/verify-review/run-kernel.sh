#!/bin/sh
# usage: ./run-kernel.sh r4-kraft|r5-metric|r6-au   -- loads the ROOT kernel from the scratch copy kernel/
cd "$(dirname "$0")" || exit 1
timeout 1500 sbcl --dynamic-space-size 8GB --noinform --non-interactive --load "$1.lisp" > "logs/$1.log" 2>&1
echo "exit $? -> logs/$1.log"
