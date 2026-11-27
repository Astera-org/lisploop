#!/bin/bash
# The larger-budget rungs of run-all-harness.sh, on their own (they take the longest).
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W" || exit 1
bash run-harness.sh as-written 10 all 8192 1200
bash run-harness.sh clean 10 all 8192 1200
bash run-harness.sh curriculum 10 all 8192 1200
bash run-harness.sh as-written 100 active-grammar-no-schemas 12288 1800
bash run-harness.sh clean 100 active-grammar-no-schemas 12288 1800
bash run-harness.sh curriculum 100 active-grammar-no-schemas 12288 1800
echo ladder-done
