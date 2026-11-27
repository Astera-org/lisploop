p = '/home/tlh24/lisploop/plan_v2c_audit/reports/verify-memory.md'
s = open(p).read()
s = s.replace('Coarser dedupe keys: Table 5', 'Coarser dedupe keys: Table 3')
s = s.replace('none found (Table 5)', 'none found (Table 3)')
s = s.replace('**Table 5 (undirected, G1, every class up to size 11).**', '**Table 3 (undirected, G1, every class up to size 11).**')
s = s.replace("The reviewer's figure was taken with a look-ahead, on 41 unary operators, with the size given",
              "The reviewer's figure was taken with a look-ahead, on 41 unary operators and 8 tasks, with the size given")
s = s.replace("**Python bytes understate the library gain.** A kept class carries its labels: 911 B per class against 666 B for a plain list class. Recomputing labels from the column would avoid that cost.",
              "**On the library the byte gain is smaller than the entry gain** because each kept class also stores its labels: 911 B per class against 666 B for a plain list class. Recomputing labels from the column would close most of that gap.")
open(p, 'w').write(s)
