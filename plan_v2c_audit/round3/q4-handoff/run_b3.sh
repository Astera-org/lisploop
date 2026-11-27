#!/bin/bash
# B3: near-miss tasks (offset/scale, conditional) and what the proposals do on ordinary tasks.
cd "$(dirname "$0")"
python3 b3.py offscale --seed 21 --n 96 --procs 14 --out b3_os_s21.json > b3_run.log 2>&1
python3 b3.py offscale --seed 22 --n 96 --procs 14 --out b3_os_s22.json >> b3_run.log 2>&1
python3 b3.py ifsplit --seed 31 --n 60 --procs 14 --out b3_if_s31.json >> b3_run.log 2>&1
python3 b3.py ifsplit --seed 32 --n 60 --procs 14 --out b3_if_s32.json >> b3_run.log 2>&1
python3 b3.py spurious b12_s11.json --procs 14 --out b3_sp_s11.json >> b3_run.log 2>&1
python3 b3.py spurious b12_s12.json --procs 14 --out b3_sp_s12.json >> b3_run.log 2>&1
python3 b3.py report b3_os_s21.json b3_os_s22.json b3_if_s31.json b3_if_s32.json b3_sp_s11.json b3_sp_s12.json > b3_report.log 2>&1
echo done
