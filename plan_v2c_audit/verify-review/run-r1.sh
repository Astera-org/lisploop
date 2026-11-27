#!/bin/sh
# R1: modified probe (tg-probe-r1.lisp, 3 marked mods) + driver r1-spec.lisp on the kernel's :spec rows
cd "$(dirname "$0")" || exit 1
timeout 900 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r1.lisp --load r1-spec.lisp --eval "(tg::r1)" > logs/r1.log 2>&1
echo "exit $? -> logs/r1.log"
