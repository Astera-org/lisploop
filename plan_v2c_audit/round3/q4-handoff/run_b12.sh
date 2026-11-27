#!/bin/bash
# B1, B2, B4 on two task sets of 120 ordinary tasks (3 and 4 operators).
cd "$(dirname "$0")"
python3 b12.py run --seed 11 --n 120 --procs 7 --out b12_s11.json > b12_run_s11.log 2>&1 &
python3 b12.py run --seed 12 --n 120 --procs 7 --out b12_s12.json > b12_run_s12.log 2>&1 &
wait
python3 b12.py report b12_s11.json b12_s12.json > b12_report.log 2>&1
echo done
