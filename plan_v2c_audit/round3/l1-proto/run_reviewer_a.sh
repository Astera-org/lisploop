#!/bin/bash
# The reviewer's EXP A (unmodified), to record whether it prints the review's 5.3x / 7.6x / 1.0x figures.
cd "$(dirname "$0")" || exit 1
mkdir -p logs
t0=$(date +%s)
timeout 1200 python3 run_reviewer_a.py > logs/reviewer_expA.log 2>&1
echo "exit $? ; $(( $(date +%s) - t0 )) s" >> logs/reviewer_expA.log
tail -1 logs/reviewer_expA.log
