#!/bin/bash
# Tables for REPORT.md from results/*.sexp.  No kernel is loaded.
W="$(cd "$(dirname "$0")" && pwd)"
timeout 300 sbcl --noinform --non-interactive --load "$W/tabulate.lisp" > "$W/logs/tables.txt" 2>&1
echo "exit $? -> logs/tables.txt"
