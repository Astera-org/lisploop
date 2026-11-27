#!/bin/bash
# usage: run-harness.sh MODE MULT [REGIMES] [HEAP_MB] [TIMEOUT_S]
#   MODE     as-written | repaired | clean | curriculum
#   MULT     budget multiplier on 350,000 work per spec (1, 10, 100, ...)
#   REGIMES  all (default) or a comma list, e.g. active-grammar-no-schemas
# Writes logs/harness-MODE-xMULT[-REGIMES].log and results/MODE-xMULT[-REGIMES].sexp
W="$(cd "$(dirname "$0")" && pwd)"
MODE="$1"; MULT="$2"; REG="${3:-all}"; HEAP="${4:-4096}"; TMO="${5:-900}"
TAG="$MODE-x$MULT"; [ "$REG" = "all" ] || TAG="$TAG-$REG"
mkdir -p "$W/results" "$W/logs"
export X3_V2_ROOT="$W/kernel/v2/" X3_WORK="$W/" X3_MODE="$MODE" X3_MULT="$MULT" X3_REGIMES="$REG"
export X3_OUT="$W/results/$TAG.sexp"
( time timeout "$TMO" sbcl --dynamic-space-size "$HEAP" --noinform --non-interactive \
    --load "$W/x3-harness.lisp" ) > "$W/logs/harness-$TAG.log" 2>&1
echo "exit $? -> logs/harness-$TAG.log"
