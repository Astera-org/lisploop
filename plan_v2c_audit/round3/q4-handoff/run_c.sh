#!/bin/bash
# C (tables only read, never invented online) and a robustness run of B1/B2/B4 with 4 rows per task.
cd "$(dirname "$0")"
python3 c_unpredicted.py b12_s11.json b12_s12.json > c_unpredicted.log 2>&1
python3 b12.py run --seed 11 --n 120 --rows 4 --procs 14 --out b12_s11_rows4.json > b12_run_rows4.log 2>&1
python3 b12.py report b12_s11_rows4.json > b12_report_rows4.log 2>&1
echo done
