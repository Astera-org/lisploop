#!/bin/bash
# list occurrences of the watched words in frozen-copy lines 348-625, with a short context
F=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md
for w in "$@"; do
  echo "=== $w"
  awk 'NR>=348 && NR<=625' "$F" | grep -n -o -i ".\{45\}$w.\{40\}" | awk -F: '{printf "%d: %s\n", $1+347, substr($0, index($0,":")+1)}'
done
