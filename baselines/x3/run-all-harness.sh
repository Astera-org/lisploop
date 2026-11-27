#!/bin/bash
# Every harness run behind the report, in order.
#   run-all-harness.sh              the runs up to a hundred times the budget, about three minutes
#   run-all-harness.sh with-x1000   also the thousand-fold run of the gate's regime: four more minutes,
#                                   about 9 GB of memory at its peak
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W" || exit 1
# default budget (350,000 work per spec), all four regimes, each library mode
bash run-harness.sh as-written 1
bash run-harness.sh repaired 1
bash run-harness.sh clean 1
bash run-harness.sh curriculum 1
# ten times the budget, all four regimes
bash run-harness.sh as-written 10 all 8192 1200
bash run-harness.sh clean 10 all 8192 1200
bash run-harness.sh curriculum 10 all 8192 1200
# a hundred times the budget, the gate's regime only
bash run-harness.sh as-written 100 active-grammar-no-schemas 12288 1800
bash run-harness.sh clean 100 active-grammar-no-schemas 12288 1800
bash run-harness.sh curriculum 100 active-grammar-no-schemas 12288 1800
# a thousand times the budget, the gate's regime, the harness as written, all sixteen specs in one run
if [ "$1" = "with-x1000" ]; then
  bash run-harness.sh as-written 1000 active-grammar-no-schemas 12288 2400
fi
bash run-tabulate.sh
