#!/bin/sh
# Regression: the probe copy with the L1 hooks, filter OFF, must reproduce the repo's experiment D log
# (plan_v2c_audit/proto/logs/d.log) exactly, timings aside.
cd "$(dirname "$0")" || exit 1
mkdir -p logs
timeout 900 sbcl --dynamic-space-size 10GB --noinform --non-interactive \
     --load tg-probe-l1.lisp --load labels.lisp --eval "(tg::main :d)" > logs/regress-d-l1.log 2>&1
echo "exit $? -> logs/regress-d-l1.log"
mask() { sed -E 's/ +[0-9]+ +([0-9]+\/200|-) /  MS \1 /; s/ ms [0-9]+/ ms MS/' "$1"; }
mask /home/tlh24/lisploop/plan_v2c_audit/proto/logs/d.log > logs/_d_repo.masked
grep -v "^;\|^$\|STYLE-WARNING\|undefined" logs/regress-d-l1.log | mask /dev/stdin > logs/_d_l1.masked
grep -v "^$" logs/_d_repo.masked > logs/_d_repo.masked2
if diff -q logs/_d_repo.masked2 logs/_d_l1.masked >/dev/null; then echo "REGRESSION OK: L1 probe with filter off == repo d.log (timings masked)"; else echo "REGRESSION DIFFERS"; diff logs/_d_repo.masked2 logs/_d_l1.masked | head -20; fi
