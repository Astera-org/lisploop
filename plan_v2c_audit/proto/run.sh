#!/bin/sh
# usage: ./run.sh d|dseeds|docc|a|c|b [logname]
# Runs one experiment of tg-probe.lisp; all output goes to logs/<logname>.log
cd "$(dirname "$0")" || exit 1
mkdir -p logs
log="logs/${2:-$1}.log"
sbcl --dynamic-space-size 10GB --noinform --non-interactive \
     --load tg-probe.lisp --eval "(tg::main :$1)" > "$log" 2>&1
echo "exit $? -> $log"
