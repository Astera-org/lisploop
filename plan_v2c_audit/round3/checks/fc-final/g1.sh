#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
echo "=== leftover terms ==="
grep -n -i -o -E '.{60}(signature|retrieval|four geometr|geometries|can choose|could choose|kernel chooses).{60}' "$D"
echo "=== revision talk ==="
grep -n -i -o -E '.{50}(first draft|this revision|in revision|earlier version|previous version|earlier draft|was added|added in|now says|no longer|previously said|TODO|TBD|XXX|\?\?\?|FIXME|placeholder).{50}' "$D"
echo "=== pass words ==="
grep -n -o -E '.{50}\b(pass|passes)\b.{50}' "$D" | sed -n '1,200p'
