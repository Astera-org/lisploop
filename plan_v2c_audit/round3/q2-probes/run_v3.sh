#!/bin/bash
# third wave, after run_v2.sh: merged products (P3), then feedback replay and guards (P2)
cd "$(dirname "$0")"
until grep -q "^real" exp_main_EDGE-W.log 2>/dev/null; do sleep 20; done
( time python3 exp_merged.py --rules iid,bank2+strat2,hand --M 1000,3000,10000 --seeds 0,1 --quots merged3 --guards 10 --sets S300 --procs 12 ) > exp_merged.log 2>&1
( time python3 exp_feedback.py --parts 2,3 --best bank2+strat2 --procs 12 --p2rules iid,strat2,push2,bank2,oelog3,bank2+strat2,hand ) > exp_feedback_p23.log 2>&1
