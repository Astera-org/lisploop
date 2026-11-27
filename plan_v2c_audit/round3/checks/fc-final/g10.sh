#!/bin/bash
D=/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md
g(){ grep -n -o -E ".{0,160}($1).{0,160}" "$D" | head -${2:-8}; echo; }
echo "## yield-gate"; g 'yield-gate|offline experiment'
echo "## about 15 / 16 / 17 gains"; g 'about 1[5-8] times|1[4-8]× to 1[4-8]×|about a sixth|a fifth' 12
echo "## human label / labels supplied"; g 'human label|labels supplied|labeled' 6
echo "## classes held / held"; g 'classes held|class(es)? (is|are) held' 10
echo "## next round"; g "next round|round's" 6
echo "## bank of"; g 'bank of (terms|maps)|richer bank' 4
echo "## term space"; g 'term space' 4
echo "## positive gain / gain depends"; g 'positive gain|the gain depends|measured gain' 4
echo "## Since then / now"; g 'Since then|though now|Counts now|as it is now written' 6
echo "## applies a correction"; g 'applies a correction|applies a change' 4
echo "## either pass / both passes"; g 'either pass|both passes|every pass' 4
echo "## spread evenly over the labels"; g 'spread[^.]{0,40}over the (labels|words)' 6
