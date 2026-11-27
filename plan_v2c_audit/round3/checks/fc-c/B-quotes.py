#!/usr/bin/env python3
"""Search the repository documents for each quotation used in sections 2.4-2.9 of the frozen copy.
Reports exact matches (file:line) and, where there is none, the closest match after whitespace
normalisation. Read-only."""
import os, re, sys, glob

ROOT = "/home/tlh24/lisploop"
files = []
for pat in ["*.md", "deprecated/*.md", "plan7/*.md", "*.tex", "deprecated/*.txt", "*.txt"]:
    files += glob.glob(os.path.join(ROOT, pat))
files = sorted(set(files))

quotes = [
    "Topologically, computation may be seen as a projection,",
    "In which case the reverse process requires a lift",
    "up to (say) depth=2 (this is essential!)",
    "here we will **learn** the propagation rules",
    "on the search tree and execution graph itself",
    "the search process of the kernel itself produces data that bootstraps rules and complexity for further search",
    "which again is what the kernel itself is supposed to be doing!!",
    "one 'flat' store. A list. In lisp.",
    "not essential for this proposal, except",
    "a second parallel language of nine `:code-*` primitives",
    "Six hand-rolled state machines",
    "a measurement says it is needed",
    "is a few hundred lines, not a heavy import",
    "a measurement says it binds",
    "a universal graph-matching engine",
    "A general graph-isomorphism solver is unnecessary.",
    "Running a computation backwards is lifting: given f(x), supply the index.",
    "needs an order or a metric on D",
    "No column is designated as input or output.",
    "via the exchange of input and outputs",
    "A metric and a decoder shell are two views of one correction code.",
    "the unresolved information is the membership of each input in its valid subset",
    "can propose and never eliminates",
    "cheaper requirement checks, rather than fewer enumerated candidates",
    "only through verified maps",
    "how, though?",
    "This price is one step deep",
    "one step deep",
]

def norm(s):
    return re.sub(r"\s+", " ", s)

texts = {}
for f in files:
    try:
        texts[f] = open(f, encoding="utf-8", errors="replace").read()
    except Exception as e:
        print("cannot read", f, e)

for q in quotes:
    hits = []
    for f, t in texts.items():
        # exact, allowing line wraps
        nt = norm(t)
        if norm(q) in nt:
            # find line
            for i, line in enumerate(t.split("\n"), 1):
                if q[:25] in line or norm(q)[:25] in norm(line):
                    hits.append(f"{os.path.relpath(f, ROOT)}:{i}")
                    break
            else:
                hits.append(f"{os.path.relpath(f, ROOT)}:(wrapped)")
    print(("FOUND   " if hits else "MISSING ") + repr(q))
    for h in hits[:8]:
        print("      ", h)
