#!/bin/sh
cd "$(dirname "$0")" || exit 1
timeout 900 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r1.lisp --load r1-spec.lisp --load r1-variants.lisp --eval "(tg::variants)" > logs/r1-variants.log 2>&1
echo "exit $? -> logs/r1-variants.log"
