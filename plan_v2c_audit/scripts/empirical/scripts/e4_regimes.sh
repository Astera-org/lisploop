#!/bin/bash
# E4 controls: the audit's other regimes at up to 100x the cap (35M work), for the specs that fail there at 350k.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E
for t in map-adjacent scan shift-seq seq-corr best-shift argmax-corr; do HEAP_MB=1500 ./scripts/e4_run.sh ags $t 35000000 0 2 15000 120 ags & done; wait
for t in map-adjacent positions scan shift-seq best-shift argmax-corr foldl; do HEAP_MB=1500 ./scripts/e4_run.sh wlns $t 35000000 0 2 15000 120 wlns & done; wait
# sanity: whitelist+schemas must reproduce the audit's 16/16 work figures for two specs
for t in map-adjacent scan; do HEAP_MB=1500 ./scripts/e4_run.sh wls $t 350000 0 2 15000 120 wls & done; wait
