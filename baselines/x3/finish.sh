#!/bin/bash
# Record the repository's state at the end and compare with the state recorded by setup.sh.
W="$(cd "$(dirname "$0")" && pwd)"
SRC="${REPO:-$(cd "$W/../.." && pwd)}"
( cd "$SRC" && git rev-parse HEAD && git status --short ) > "$W/logs/repo-state-after.txt" 2>&1
if cmp -s "$W/logs/repo-state-before.txt" "$W/logs/repo-state-after.txt"; then
  echo "repository state unchanged (HEAD and git status identical before and after)"
else
  echo "REPOSITORY STATE CHANGED"; diff "$W/logs/repo-state-before.txt" "$W/logs/repo-state-after.txt"
fi | tee "$W/logs/repo-state-compare.txt"
