#!/bin/bash
# Copy the verify-quotients code this study reuses (read-only source) into the work directory.
set -e
W=/home/tlh24/lisploop/plan_v2c_audit/round3/q2-probes
SRC=/home/tlh24/lisploop/plan_v2c_audit/verify-quotients
for f in seqlib.py q2search.py q2tasks.py q2common.py; do
  cp "$SRC/$f" "$W/$f"
done
ls -la "$W"
