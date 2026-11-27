#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
show(){ awk -v a=$1 -v b=$2 'NR>=a && NR<=b' "$D" | grep -n -o -E ".{0,160}($3).{0,200}" | awk -v a=$1 -F: '{printf "%d:", $1+a-1; $1=""; print}' | head -${4:-6}; echo; }
echo "## 2.3 158 decisions / accounting"; show 187 232 '158|accounting rules|dedupe (and|or) memo'
echo "## 2.3 buy structure / tenfold"; show 187 232 'tenfold|two or three sub-problems|buy'
echo "## 2.4 187 equations / initiates / definedness"; show 233 247 '187|initiates|defined|error'
echo "## 2.5 three of eight / four things"; show 248 272 'three of|eight|whitelist|50,000'
echo "## 2.6 constant / trace-derived"; show 273 280 'constant|transfer'
echo "## 2.7 eight / three facts / artifacts"; show 281 292 'eight|three|artifact|row'
echo "## 2.8 counting identity / tree-shaped / EBG / four times"; show 293 324 'fiber|tree-shaped|explanation|four times|declined'
echo "## 4.5 / 4.6"; show 404 425 'represent|tower|interpreters'
echo "## 4.1 7,700 / hundred primitives"; show 364 375 '7,700|hundred|factor of 12'
