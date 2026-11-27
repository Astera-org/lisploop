#!/bin/bash
# E4 internal-cap variations at 100x budget (35M work): one constant raised at a time.
#   d3 / d4 : :max-depth 2 -> 3 / 4        h10 : :heuristic-budget 15000 -> 150000
#   b100    : description bound 154 -> 254 bits    all : max-depth 4, heuristic-budget 150000, bound +100
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E
run_var() { # tag bound-add max-depth heur
  for t in map-adjacent scan shift-seq best-shift argmax-corr; do HEAP_MB=1500 ./scripts/e4_run.sh $1 $t 35000000 $2 $3 $4 120 & done; wait
}
run_var capd3 0 3 15000
run_var capd4 0 4 15000
run_var caph10 0 2 150000
run_var capb100 100 2 15000
run_var capall 100 4 150000
