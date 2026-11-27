#!/bin/bash
# E4: one "minutes-scale" run. shift-seq (smallest reference program, 161 bits) to 700M work (2000x), 11 GB heap.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E
for i in $(seq 1 30); do avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo); [ "$avail" -ge 13000 ] && break; sleep 10; done
HEAP_MB=11000 ./scripts/e4_run.sh x2000 shift-seq 700000000 0 2 15000 900
