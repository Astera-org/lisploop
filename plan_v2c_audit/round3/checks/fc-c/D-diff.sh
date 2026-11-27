#!/bin/bash
R=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3
for f in 07.1 07.3 09.0 AA.0 AD.0 AE.0; do
  echo "=================== $f"
  git diff --no-index --word-diff=plain -U0 $R/sections.preclarity/$f.md $R/sections/$f.md
done
