#!/bin/sh
# R2: probe copy with MODs 1-6 (tg-probe-r2.lisp) + r1-spec.lisp (rows, references) + r2-reduce.lisp
cd "$(dirname "$0")" || exit 1
timeout 1800 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r2.lisp --load r1-spec.lisp --load r2-reduce.lisp --eval "(tg::r2)" > logs/r2.log 2>&1
echo "exit $? -> logs/r2.log"
