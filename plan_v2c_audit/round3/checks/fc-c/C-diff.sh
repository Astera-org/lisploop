#!/bin/bash
# word-diff of each section file in the slice against its pre-clarity version
R=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3
for f in "$@"; do
  echo "=================== $f"
  git diff --no-index --word-diff=plain -U0 "$R/sections.preclarity/$f" "$R/sections/$f" | tail -n +5
done
