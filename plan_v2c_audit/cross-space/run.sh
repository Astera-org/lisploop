#!/bin/sh
# usage: ./run.sh m1|m2|m3 [lisp-expression] [logname]
# Loads the UNMODIFIED tg-probe.lisp, then xs-<name>.lisp, and evaluates the
# expression (default: (tg::<name>)).  Output goes to logs/<logname>.log.
# 8 GB heap, hard timeout (default 3600 s; override with TMO=seconds).
cd "$(dirname "$0")" || exit 1
mkdir -p logs
expr="${2:-(tg::$1)}"
log="logs/${3:-$1}.log"
timeout "${TMO:-3600}" sbcl --dynamic-space-size 8GB --control-stack-size 200MB \
     --noinform --non-interactive \
     --load tg-probe.lisp --load "xs-$1.lisp" --eval "$expr" > "$log" 2>&1
echo "exit $? -> $log"
