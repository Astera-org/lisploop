#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
g(){ grep -n -o -E ".{0,200}($1).{0,200}" "$D" | head -${2:-8}; echo; }
echo "## 50,000"; g '50,000|dearer'
echo "## four things / most of the library"; g 'trace-shaped|trace-complete' 6
echo "## 66th"; g '66th|2,661'
echo "## ten yes-or-no / descriptors"; g 'ten yes-or-no|descriptors\.lisp|fixed menu' 6
echo "## commutativity appears at once"; g 'appears at once|shared-input' 4
echo "## three named functions"; g 'three named' 4
echo "## 1.5 flat layer"; g 'flat layer' 6
echo "## fifteen / 12-operator"; g 'twelve element-level|12-operator' 6
echo "## in the kernel can"; g 'could run|can run' 8
