#!/bin/bash
# Regenerate every log behind the L1 report (about 75 min of CPU on a quiet machine).
cd "$(dirname "$0")" || exit 1
bash run_reviewer_a.sh                                   # reviewer's EXP A, unmodified  -> logs/reviewer_expA.log
python3 make_reviewer_a2_order.py && python3 reviewer_a2_order.py > logs/reviewer_a2_order.log
./run-regress.sh                                         # filter off == repo proto/logs/d.log
for e in e0 e1 e2 e3 e4 e5 e6 e7; do TMO=5400 ./run.sh $e; done
python3 tabulate.py logs/e1.log > logs/e1-table.txt
python3 tabulate.py logs/e5.log "(b)" > logs/e5b-table.txt
