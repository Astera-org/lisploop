#!/bin/sh
# Cross-check of the R1 hidden references against the kernel's own library definitions.
cd "$(dirname "$0")" || exit 1
timeout 300 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r1.lisp --load r1-spec.lisp --load xref-dump.lisp > logs/xref-dump.log 2>&1
echo "dump exit $?"
timeout 900 sbcl --dynamic-space-size 8GB --noinform --non-interactive --load xref-kernel.lisp > logs/xref-kernel.log 2>&1
echo "kernel exit $? -> logs/xref-kernel.log"
