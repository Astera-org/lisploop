#!/bin/bash
# Retained memory of each configuration, one fresh SBCL process per measurement.
# The last number of each configuration is how many identical jobs are held at once.
W="$(cd "$(dirname "$0")" && pwd)"
export X1_V1="${X1_V1:-$W/v1}"
export X1_OUT="$W"
LOG="$W/x1-memory.log"
: > "$LOG"
run() {
  X1_CFG="$1" timeout 600 sbcl --dynamic-space-size 8192 --non-interactive --no-userinit --no-sysinit \
    --load "$W/x1-memory.lisp" 2>&1 | grep '^MEM ' >> "$LOG"
}
# The four shipped jobs, 200 copies each, and once more with 50 copies to show the spread.
run '("obs1" 1 (:+ :*) (0 1) 20 20000 200)'
run '("obs2" 2 (:+ :*) nil 24 40000 200)'
run '("obs3+" 3 (:+) nil 44 80000 200)'
run '("obs3*" 3 (:*) nil 44 80000 200)'
run '("obs1" 1 (:+ :*) (0 1) 20 20000 50)'
run '("obs2" 2 (:+ :*) nil 24 40000 50)'
run '("obs3+" 3 (:+) nil 44 80000 50)'
run '("obs3*" 3 (:*) nil 44 80000 50)'
# The two cut-off jobs at their bit bound, run to exhaustion; and at the smaller natural bounds.
run '("obs3+" 3 (:+) nil 24 1000000000000 200)'
run '("obs3+" 3 (:+) nil 34 1000000000000 20)'
run '("obs3+" 3 (:+) nil 44 1000000000000 4)'
run '("obs3*" 3 (:*) nil 44 1000000000000 4)'
# The distributivity grammar; 34 bits also with one copy to show the spread of the method.
run '("dist" 3 (:+ :*) nil 24 1000000000000 50)'
run '("dist" 3 (:+ :*) nil 34 1000000000000 4)'
run '("dist" 3 (:+ :*) nil 34 1000000000000 1)'
run '("dist" 3 (:+ :*) nil 44 1000000000000 1)'
cat "$LOG"
