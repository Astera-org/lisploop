#!/bin/sh
cd "$(dirname "$0")" || exit 1
timeout 1200 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r1.lisp --load r1-spec.lisp --load r1-occam.lisp --eval "(tg::r1-occam)" > logs/r1-occam.log 2>&1
echo "exit $? -> logs/r1-occam.log"
