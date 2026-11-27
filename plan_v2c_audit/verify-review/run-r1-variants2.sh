#!/bin/sh
cd "$(dirname "$0")" || exit 1
timeout 900 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r1.lisp --load r1-spec.lisp --load r1-variants.lisp --load r1-variants2.lisp --eval "(tg::variants2)" > logs/r1-variants2.log 2>&1
echo "exit $? -> logs/r1-variants2.log"
