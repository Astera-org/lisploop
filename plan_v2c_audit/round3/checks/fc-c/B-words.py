#!/usr/bin/env python3
"""List every occurrence, with context, of the watch-words in frozen-copy lines 221-346."""
import re
P = "/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md"
lines = open(P, encoding="utf-8").read().split("\n")
words = r"\b(stage|stages|node|nodes|class|classes|fold|folds|folding|foldr|foldl|witness|witnesses|quotient|quotients|signature|signatures|probe|probes|index|indexing|indices|property|properties|usage|retrieval|geometries)\b"
for n in range(221, 347):
    s = lines[n - 1]
    for m in re.finditer(words, s, flags=re.I):
        a = max(0, m.start() - 55)
        b = min(len(s), m.end() + 45)
        print(f"{n}: [{m.group(0)}] ...{s[a:b]}...")
