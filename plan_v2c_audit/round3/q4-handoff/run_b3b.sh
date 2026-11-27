#!/bin/bash
# Re-run the conditional family (adds the "review order" cost) and rebuild the B3 report.
cd "$(dirname "$0")"
python3 b3.py ifsplit --seed 31 --n 60 --procs 14 --out b3_if_s31.json > b3_run_if.log 2>&1
python3 b3.py ifsplit --seed 32 --n 60 --procs 14 --out b3_if_s32.json >> b3_run_if.log 2>&1
python3 b3.py report b3_os_s21.json b3_os_s22.json b3_if_s31.json b3_if_s32.json b3_sp_s11.json b3_sp_s12.json > b3_report.log 2>&1
echo done
