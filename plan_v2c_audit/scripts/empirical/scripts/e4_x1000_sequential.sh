#!/bin/bash
# E4: 1000x cap (350M work) for the 5 specs that still fail at 100x; ONE process at a time
# (each needs ~3.5 GB live heap at 350M work), 7 GB heap, waits for >= 9 GB MemAvailable.
E=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical
cd $E
for t in map-adjacent scan shift-seq best-shift argmax-corr; do
  for i in $(seq 1 60); do
    avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    [ "$avail" -ge 9000 ] && break; sleep 10
  done
  echo "$(date +%T) start $t MemAvailable=${avail}MiB" >> logs/e4_x1000_driver.log
  HEAP_MB=7000 ./scripts/e4_run.sh x1000 $t 350000000 0 2 15000 600
done
echo done >> logs/e4_x1000_driver.log
