#!/bin/bash
# E3 one more notch (memory-heavy, run one at a time): g2 exact to 48 body bits; g2 prune to 66; g3 exact to 42.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E
cp logs/e3_v2_g2_exact.log logs/e3_v2_g2_exact_to45.log; cp logs/e3_v2_g2_prune.log logs/e3_v2_g2_prune_to63.log; cp logs/e3_v2_g3_exact.log logs/e3_v2_g3_exact_to39.log
HEAP_MB=5000 ./scripts/e3_run.sh v2 g2 exact 200 1100000
HEAP_MB=5000 ./scripts/e3_run.sh v2 g2 prune 200 90000
HEAP_MB=5000 ./scripts/e3_run.sh v2 g3 exact 200 2500000
