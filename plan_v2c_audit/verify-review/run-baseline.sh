#!/bin/sh
# Baseline regression: unmodified tg-probe.lisp, experiment D, to compare with the repo's proto/logs/d.log
cd "$(dirname "$0")" || exit 1
timeout 600 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe.lisp --eval "(tg::main :d)" > logs/baseline-d.log 2>&1
echo "exit $? -> logs/baseline-d.log"
