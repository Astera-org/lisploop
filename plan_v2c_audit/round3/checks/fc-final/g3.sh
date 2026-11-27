#!/bin/bash
R=/home/tlh24/lisploop/plan_v2c_audit/reports
S=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/reports
ls -la $R | head -80
echo ---
ls /home/tlh24/lisploop/plan_v2c_audit/ | head -60
echo --- diff of report copies
for f in verify-words verify-probes verify-memory verify-handoff verify-proto-labels; do cmp $R/$f.md $S/$f.md && echo same $f; done
