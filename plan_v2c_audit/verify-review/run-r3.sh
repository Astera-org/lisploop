#!/bin/sh
cd "$(dirname "$0")" || exit 1
timeout 600 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe.lisp --load r3-guard.lisp --eval "(tg::r3)" > logs/r3.log 2>&1
echo "exit $? -> logs/r3.log"
