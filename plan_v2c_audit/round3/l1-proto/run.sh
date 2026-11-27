#!/bin/sh
# usage: ./run.sh <experiment-function> [logname]      e.g.  ./run.sh e1
# Loads the probe copy with the L1 hooks, the label machinery, the spec rows and the drivers; output -> logs/<logname>.log
cd "$(dirname "$0")" || exit 1
mkdir -p logs
log="logs/${2:-$1}.log"
timeout "${TMO:-3000}" sbcl --dynamic-space-size 10GB --noinform --non-interactive \
     --load tg-probe-l1.lisp --load labels.lisp --load r1-spec.lisp --load l1-run.lisp \
     --eval "(tg::l1-main 'tg::$1)" > "$log" 2>&1
echo "exit $? -> $log"
