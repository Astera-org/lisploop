# Parent part: cross-references, stale statements, second senses

## Findings, most serious first

**1. FACTUAL ERROR. Two sentences say that the higher-order `filter` was not attempted, and §8.5 of the same document reports that it was run and solved.**

Line 829 (§7.1): "§8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter`. It did not attempt the higher-order `map` and `filter` themselves."

Line 909 (§7.3): "On the kernel's spec rows it was run on `foldl`, `seq-corr`, `best-shift`, `argmax-corr` and `last-or`, and not all of these were solved (§8.5 gives the outcome of each). The higher-order `map`, `foldr` and `filter` were not tested."

What the sources say. The kernel's `filter` spec takes the predicate as an argument: `bootstrap/build-batteries.lisp:628` declares `:spec/filter (list (cons 0 seq-t) (cons 1 pred-t)) seq-t`. The prototype was run on that spec's rows and found `(select xs (lambda (j x) (call1b p x)))`, 200/200, at 1,383 candidates, and the held-out set included a predicate that occurs in no spec row (`verify-review.md:15`, `:63`, `:86`). The frozen copy reports this at line 1111 ("`filter` | 200/200 at 1,383 candidates, once a one-argument Boolean call is in the grammar"). §8 also has `scan` and `map-adjacent` with a function argument (lines 1027, 1028, 1110, 1113), so "first-order instances of ... `scan`" understates as well. `map` and `foldr` are not among the sixteen specs (the kernel derives them by anti-unification), so "not tested" is right for those two. Second, the prototype was run on all sixteen specs' rows (`verify-review.md:54-80`), not on the five that line 909 lists. The sentence comes from the version before §8.5 existed, which said that the prototype of §8.1 "did not test `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`, or the higher-order `map`, `foldr`, and `filter`; §8.6 has since run the first five" (`sections.orig/07.3.md:13`). Each rewording since has carried the list forward without re-reading §8.5.

Replacement for line 829: "§8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter` (§8.1). It also finds `scan`, `map-adjacent` and `filter` when the function or the predicate is an argument (§8.1, §8.5). It did not attempt the higher-order `map` or `foldr`."

Replacement for the two sentences of line 909: "On the kernel's spec rows it was run on all sixteen specs, and thirteen were solved in some configuration (§8.5 gives the outcome of each). Those sixteen include `filter` with its predicate as an argument, which was solved once a one-argument Boolean call was in the grammar, and `foldl` with its step as an argument, which returned an impostor. In these runs a function argument is one of three named functions, not arbitrary code. The higher-order `map` and `foldr` are not among the sixteen and were not tested."

The limit in the last-but-one sentence is from `verify-review.md:39` and `:301`: a function argument is drawn from `+ - *`, and a predicate from `pos`, `even`, `neg`.

**2. INCONSISTENCY. §7.1 still proposes the pricing of names that the rewritten §6.4 says failed.**

Line 837 (§7.1): "**5. Price names by use.** An operator's name costs −log₂ of its share of uses in accepted solutions (§6.4), under a prefix code as now."

What the frozen copy now says. §6.4, line 737: "Prices from counts of past use are the form that failed on new operators. So a name's price comes first from its tables, and from counts only as a correction that cannot price a name out **[P]**." Line 719: counts of past use "used as prices ... sent 5 of 8 such tasks past the search's cap". §8.8 item 8 (line 1281): "Counts become a correction to the tables." Risk 4 (line 1346): "tables first, counts only as a correction (§6.4)". The pointer used to reach the old §6.3, where counts "set the price of an operator's name" (`git show HEAD:plan_v2c.md`, line 618). It was renumbered to §6.4 and the sentence was not re-read against the new text.

Replacement: "**5. Price names by fit, then by use.** An operator's place in the enumeration, and so the price of its name, is read first from how well its verb tables fit the labels of the problem at hand. Counts of its uses in accepted solutions only correct that price, and may never price a name out (§6.4). The code stays a prefix code, as now."

**3. MISSING CAVEAT. The comparison in §5.3 stops at §8.1, and §8.5 has since run the case that the sentence says was not run.**

Line 496: "It finds the function-argument version in about five seconds, on twelve of its own examples rather than the spec's eight, and not robustly (§8.1)."

What the frozen copy now says. Line 1113: on the spec's own eight examples the prototype returns "an impostor built from a guard split, 29/200, under first-fit acceptance; the right program, 200/200, when splits are accepted in size order", at 616,232 candidates and 64 ms (`verify-review.md:72-73`).

Replacement: "It finds the function-argument version in about five seconds, on twelve of its own examples, and not robustly (§8.1). On the spec's own eight examples it returns an impostor when the first split that fits is accepted, and the right program in 64 ms when splits are accepted in size order (§8.5)."

**4. INCONSISTENCY, minor. "Tested" is defined two ways.**

Line 540 (§5.5): "**Tested**: the two terms also have the same column on several fresh spaces that include boundary values. ... The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are knowledge of this grade (§6.4)."

What the frozen copy says elsewhere. §6.4, line 724: "A verb table is learned on a probe space and read on a task's space. That is knowledge carried across spaces without being re-checked there (§5.9), which is the definition of the tested grade (§5.5)." §5.5 defines the grade by a positive check on fresh spaces. §6.4 defines it by the absence of a check on the space where the knowledge is used, and a verb table is read off one probe space, with no second space involved. The Terms table (line 38) follows §5.5.

Replacement for the last sentence of the bullet: "The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are used as knowledge of this grade (§6.4): they are true of the probe rows they were read from, and they are used on task rows where they have not been checked."

**5. COSMETIC. "A soundness gap the audit flagged" was inferred from the code and not shown.**

Line 825 (§7.1): "Pending cells also close a soundness gap the audit flagged in v2's dormant pruner, which treats two unresolved cells as equal."

What the source says. `search-engine.md:1038-1041`: "Caveat (INFERRED): the behaviour key treats two expressions that are both `:unresolved` on a row as equal there (`v2/enumerate.lisp:373-382`), which in recursive jobs with oracle tables could merge programs that differ off the table". The same report lists as not determined "Whether the dormant v2 pruning stays sound inside the full tree" (`search-engine.md:1078-1079`).

Replacement: "Pending cells also close a possible soundness gap in v2's dormant pruner. The search audit found, by reading the code and without a failing run, that the pruner treats two unresolved cells as equal."

**6. INCONSISTENCY outside the scope (§10). Risk 11 points to a measurement that X4 no longer contains.**

Line 1353: "the retrieval measurement of §8.6, repeated on the kernel's tasks (X4); a budget account for every attempt (X9)"

X4 (line 1404) compares five arms: no guidance, types only, counts of past use, verb tables used to order, and verb tables used to filter. None retrieves similar problems.

Replacement: "the guidance ablation on the kernel's tasks (X4), which counts what each form of guidance costs when it is wrong; a budget account for every attempt (X9)"

**7. INCONSISTENCY outside the scope (§8.5). The kernel's "Stage A" is used with no gloss.**

Line 1133: "Stage A does not price cell by cell, and leaves one bit per model unpaid instead."

The Terms table (line 42) says of the three kinds of stage that "the text says which is meant". Here it does not, and Stage A of this plan is the store core. Line 1556 says the same thing correctly ("the kernel's first search phase").

Replacement: "The kernel's first search phase (which its code calls Stage A) does not price cell by cell, and leaves one bit per model unpaid instead."

**8. INCONSISTENCY outside the scope (Terms table, §1.1, §8.2, §11.2). Four smaller leftovers.**

Line 43: "*X1 to X9* | The experiments of §11.2, each with a gate fixed in advance." X8 (line 1408) reads "*Gate:* none; this is exploratory." Replacement: "The experiments of §11.2. Each but the exploratory X8 has a gate fixed in advance."

Line 57: "(the search tree has two or three nodes at every budget), exponential second (each tenfold of work buys about one AST node)". "Node" has two senses in one sentence, and §2.3 was reworded to avoid exactly this. Replacement: "(on the specs that stay unsolved, the tree of sub-problems is a root with one or two children at every budget), exponential second (each tenfold of work buys about one AST node)".

Lines 1060 and 1402: "these are the witnesses the kernel reaches by two other routes: its milestone code, on a full grid with a supplied witness language", and "no witness language beyond the operators in scope. *Gate:* the same witnesses and guards the milestone code finds". Here "witness" is the kernel's word for a solver's answer term (glossed once, at line 251), while §5.9 and §7.6 use "witness" for a map, substitution or pattern that relates two spaces. Replacement for line 1060: "these are the answer terms that the kernel reaches by two other routes: its milestone code, on a full grid with a supplied language of answer terms". Replacement for line 1402: "no language of answer terms beyond the operators in scope. *Gate:* the same answer terms and guards the milestone code finds".

Line 928: "Of the 158 hard-coded decisions, the 30 dedupe and memo guards become the class table and the problem memo; the 30 ordering rules become tables and counts; the 52 caps become budget accounts that defer rather than drop; the 51 pieces of domain knowledge become library entries or are deleted." §2.3 (line 219) has a fifth category, 6 accounting rules, which this mapping leaves out. Replacement: add "; the 6 accounting rules stay, as the ledger's own rules".
