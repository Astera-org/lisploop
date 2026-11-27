#!/bin/bash
# second wave of searches: new stratifier and program-shaped probes on S300, then the two edge-stressed sets
cd "$(dirname "$0")"
( time python3 exp_main.py --taskset S300 --rules strat1,strat2,bank2,oelog3,bank2+strat1,bank2+strat2 --M 100,300,1000,3000 --seeds 0,1,2 --procs 12 --tag v2 ) > exp_main_S300_v2.log 2>&1
for S in EDGE-R EDGE-W; do
  ( time python3 exp_main.py --taskset $S --rules iid,strat2,push2,bank2,oelog3,bank2+strat2,hand --M 300,1000,3000 --seeds 0,1 --procs 12 --tag edge ) > exp_main_${S}.log 2>&1
done
