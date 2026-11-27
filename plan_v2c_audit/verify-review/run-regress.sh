#!/bin/sh
# Regression: the probe copy with ALL my modifications (tg-probe-r2.lisp, MODs 1-6) must reproduce the
# original experiment D log of the repo (plan_v2c_audit/proto/logs/d.log) exactly, timings aside.
cd "$(dirname "$0")" || exit 1
timeout 900 sbcl --dynamic-space-size 8GB --noinform --non-interactive \
     --load tg-probe-r2.lisp --eval "(tg::main :d)" > logs/regress-d-r2.log 2>&1
echo "exit $? -> logs/regress-d-r2.log"
mask() { sed -E 's/ +[0-9]+ +([0-9]+\/200|-) /  MS \1 /; s/ ms [0-9]+/ ms MS/' "$1"; }
mask /home/tlh24/lisploop/plan_v2c_audit/proto/logs/d.log > logs/_d_repo.masked
mask logs/regress-d-r2.log > logs/_d_r2.masked
mask logs/baseline-d.log > logs/_d_base.masked
if diff -q logs/_d_repo.masked logs/_d_r2.masked >/dev/null; then echo "REGRESSION OK: modified probe == repo d.log (timings masked)"; else echo "REGRESSION DIFFERS"; diff logs/_d_repo.masked logs/_d_r2.masked | head; fi
if diff -q logs/_d_repo.masked logs/_d_base.masked >/dev/null; then echo "BASELINE OK: unmodified probe == repo d.log (timings masked)"; else echo "BASELINE DIFFERS"; fi
