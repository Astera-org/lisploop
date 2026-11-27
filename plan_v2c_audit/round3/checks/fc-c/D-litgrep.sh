#!/bin/bash
cd /home/tlh24/lisploop/plan_v2c_audit/reports
g() { echo "=== $1"; grep -n -i -E "$1" lit-search.md lit-discrete.md lit-geometry.md lit-abstraction.md lit-search-appendix-*.md | cut -c1-${2:-330} | head -${3:-8}; }
g "398 laws|398"
g "42 min|size 8"
g "350 s|24 h"
g "26 min|14 operators|size 4|size ≤ 4"
g "87 of 101|65%"
g "1\.13|0\.1%"
g ">60%|60% time|more than 60"
g "91 of 140|91/140| 44 "
g "45 hand|45 properties|hand-written properties"
g "6–178|178"
g "17 years|~17|2008"
g "50 dimensions|rule miner|AnyBURL"
g "n²/log|n\^2/log|O\(log m\)|log m"
g "42\.6|82\.0|98\.2|58\.6"
g "519|456|409"
g "8\.3|9\.2|2\.1×|3\.1×"
g "three of six|3 of 6|merge-and-shrink"
g "EURISKO|Eurisko" 500 6
