#!/bin/sh
# Everything, in order.  ~6 minutes.
cd "$(dirname "$0")" || exit 1
./run-baseline.sh; ./run-regress.sh
./run-r1.sh; ./run-r1-variants.sh; ./run-r1-variants2.sh; ./run-xref.sh
./run-r2.sh; ./run-r3.sh
./run-kernel.sh r4-kraft; ./run-kernel.sh r5-metric; ./run-kernel.sh r6-au
./run-r1-occam.sh
