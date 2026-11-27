# Fact-check, round 3, scope C: sections 2, 3, 4, 5.1 to 5.9, 7.1, 7.3, 9 and Appendices A, B, C

Checked: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md`. Every line number below is a line number of that frozen copy. Report paths are under `/home/tlh24/lisploop/plan_v2c_audit/reports/` unless given in full, logs are under `/home/tlh24/lisploop/plan_v2c_audit/scripts/` and the folders beside it, and code paths are those of the repository at commit `31d5ae7`.

How the check was made. The scope was cut into four slices (§2 intro to §2.3; §2.4 to §3; §4 and §5; §7.1, §7.3, §9 and the appendices), and each slice was checked by a separate checker that opened every source cited in the two gap logs, compared each current section file with its pre-clarity version, and opened the code for every new definition. A fifth pass read the whole frozen copy once for cross-references, stale statements and words used in two senses. I then opened the sources again for the leading findings of each slice (the full grammar, the size of an AST node, the higher-order `filter`, `unify.lisp:103`, the counts of recurring problems, the drift of the derivation record, the anti-unification cell, `laws.lisp:736`, and the "at most five variables" claim) and they held. Nothing was executed: no Lisp was loaded and no experiment was repeated. Scripts and the four slice reports are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-c/`.

## The repository changed during the check

At 19:01:41 on 26 November, while this check was running, the working tree of `/home/tlh24/lisploop` was reorganized by someone else. Every root kernel file (`*.lisp`), the directories `bootstrap/`, `deprecated/`, `experiments/`, `milestones/`, `plan7/` and `tests/`, and the documents `architecture.md`, `architecture2.md`, `batteries-and-reflection.md`, `plan8.md`, `plan9.md`, `plan9-audit.md` and `plan-exec.md` now sit under a new untracked directory `/home/tlh24/lisploop/v1/`, with a copy of the `Makefile`. `git status` showed 92 tracked files as deleted at the root and `?? v1/`. The reorganization was still going on when this report was written: by 19:12 the four files of `figures/` had moved as well (96 deletions), and the root `Makefile` (19:03) and `measure_complexity.sh` (19:10) had been edited. That pattern reads as a deliberate restructuring by the owner or by another session. This check did not do it. Every command the five checkers ran in the repository was a read; I searched the four checkers' scripts and transcripts for a move command and found none; and I restored nothing. The moved files keep their old modification times, and six of them were compared with `git show HEAD:<path>` and are identical, so no finding below depends on the move. Reads made after 19:01 used `v1/<path>` or git HEAD.

The consequence for the plan is this. Every file-and-line reference to the root kernel or to the older plans (`frame.lisp:544-580`, `laws.lisp:892-929`, `bootstrap/recursion-schemas.lisp`, `deprecated/plan2.md`, `plan7/plan7.md` L437, `plan8.md` §6.7, `tests/topology.lisp`, and the whole "Where" column of the table in §9) now names a path that does not exist in the working tree. If the move is kept, the front matter (line 3) needs one sentence, for example: "File paths are those of commit `15e64c6`. The root kernel and the older plans have since been moved under `v1/`, so `frame.lisp` is now `v1/frame.lisp`." The brief's own pointer to the kernel's code (`/home/tlh24/lisploop/*.lisp`) is stale for the same reason.

## Summary

There are 75 findings: 9 FACTUAL ERROR, 11 INCONSISTENCY, 13 OVER-STATEMENT, 12 MISSING CAVEAT, 26 COSMETIC, and 4 on sentences outside the scope that were noticed in passing.

The rewording was not neutral. About forty of the findings were introduced or made more definite by the clarity pass, most of them where a worker took a suggested sentence from the clarity review, which was written without opening the sources, or expanded a compressed phrase into a definition. About ten more are sentences that the rewriting of §6 and §8 left stale. The rest were in the text before this round. No number, quotation or file-and-line reference was lost in §2 or §3; what was lost there is the reach of one **[M]** tag and one word, "operational" (findings 24 and 37). Every cut in §4, §5, §9 and the appendices is covered by an item of the clarity review, and three of those cuts lost a fact that is now nowhere else, or changed a meaning (findings 36, 59 and 67).

The findings that matter most:

- **Two new definitions in §2.3 are wrong** (findings 1, 2). The "full grammar" is not "every operator the kernel has"; it leaves out `gather`, `member`, `lookup` and the code primitives, and for that reason one of the sixteen specs cannot be expressed in it. And "an AST node is 6–7 bits" turns the gain per tenfold of work into the size of a node.
- **§7.1 and §7.3 say the higher-order `filter` was not attempted, and §8.5 reports it solved** (finding 3).
- **§7.1 still prices names by counts of use, which the new §6.4 says failed** (finding 10). §4.1 still points to §6.4 for "the choice of a small grammar", which the new §6 does not contain and §5.9 argues against (findings 11, 12). §5.9 still says "propose with the index" (finding 13).
- **A code reference in §5.6 does not do what the sentence says** (finding 4): `unify.lisp:103` builds a decoder from an anti-unification pattern and is not a pullback on frames.
- **Two reworded sentences of §2.8 are not what the sources say** (findings 5, 6): the reports list 10, 11, 12 and 15 recurring problems, not "ten to twelve each"; and `pairs`, `anchors` and `edges` are not a record of which sub-problem came from which.
- **Two cells of the table in §9 are wrong** (findings 7, 8): "n-ary" means any number of terms, not operators of any arity; and the 338 lines are `laws.lisp:447-784`, not "`laws.lisp:736` onward".
- **Four statements were widened by the rewording** (findings 22, 23, 24, 28): "at every budget tried, this tree is a root with one or two children"; "every step that turns a discovered law into something the search can use"; "it made search 6.6× more expensive"; "they differ only in the arguments".
- **§4.5 now says the cited paper "supports" the argument**, where the earlier text said "bears on", and both literature auditors read the paper otherwise (finding 21).
- **A cut in Appendix A changed an answer** (finding 36): the row on graph isomorphism now reads "neither", and the half that said a matching engine is needed across spaces is gone.
- **Three facts that the gap logs marked UNFILLED are still asserted** (findings 15, 16, 38): "three of those prices are artifacts", the undefined grade "one lineage", and the October origin of "depth two". A fourth, the "long precedent" sentence of Appendix A, turns out to have a source that the worker did not search (finding 45).

Every quotation of the owner in the scope is verbatim, including all 22 in Appendix A and the three margin notes that were read in the annotated PDFs. Apart from the four that the findings name (the count of recurring problems, the 6–7 bits, the three artifact prices and the range of the 338 lines), every number that was kept agrees with its report, and with its log where a log exists. The eight blockers of reentrancy match the search audit one for one. The four senses of "lift" and the three of "fiber" match the report and the code. The definitions of work unit, lane, body bit, the kernel's first search phase, "used for lifting", atom, message, nogood, law star, fold motif, `select`, the least-fixed-point discipline, "angelic execution" and "closed under the recursive call" are right. The gloss on "closed arithmetic frames" is right and draws a contrast that the other rows of its table do not satisfy (finding 35). The definition of the fact-and-measure scheme is incomplete (finding 40), and the framing of the four occasions on which graph machinery was declined is the worker's reading of a list of six statements (finding 42).

## Findings

The findings are grouped by severity, and within a group the more serious come first. Each gives the exact sentence with its line number, what the source says, and a replacement.

### FACTUAL ERROR

**1. FACTUAL ERROR. The definition of "full grammar" is wrong, and the error bears on the budget table.**

Line 179: "The *full grammar* is every operator the kernel has, including the library functions defined so far, with no whitelist."

What the source says. The grammar that the audit builds when it ignores the whitelist is constructed by `active-library-spec-operators` (`v2/consolidate.lisp:1213-1246`). It contains `+ - * / mod < =` over the spec's domain, `if`, and then, only for each type that appears in the spec's own signature, `=` and `if` at that type, the sequence primitives `cons tail length concat at`, the tuple primitives `tuple` and `at`, and `code-eval`; and finally every active `:function` entry of the library. It also adds the literals 0, 1, 2 and raises the bit bound from 130 to 154 (`v2/consolidate.lisp:1264-1271`; `empirical.md:262-265`). It does not contain `gather`, `member`, `lookup`, or the code-reflection primitives. The printed grammar for `map-adjacent` has 28 operators (`empirical.md:329-330`), against 27 primitives plus the library. The omission is not harmless: the empirical report says that `argmax-corr` cannot be expressed in this grammar because tuple operators are added only for tuple types in the spec's own signature (`empirical.md:416-418`, `empirical.md:519`). The gap log (`clarity-gaps-sec2.md:14`) cites `empirical.md:262-265` and `:329-330`, and neither says "every operator the kernel has".

Replacement: "The *full grammar* is the grammar that the audit builds when it ignores the whitelist. It contains the arithmetic and comparison primitives, `if`, the sequence, tuple and code primitives for each type that appears in the spec's own signature, and every library function defined so far. It is not every operator the kernel has: it leaves out `gather`, `member`, `lookup` and the primitives that inspect code, and it adds tuple operators only when the spec's signature contains a tuple type. For that reason one of the sixteen specs, `argmax-corr`, cannot be expressed in it."

**2. FACTUAL ERROR. The rewording turned "6–7 bits per tenfold of work" into "an AST node is 6–7 bits".**

Line 197: "One node of a program's syntax tree, an *AST node*, is 6–7 bits. So **each tenfold increase in work buys about one more AST node**."

What the source says. `empirical.md:250-252`: "exact enumeration gains 5.7–7.5 bits per 10× of work; deduped enumeration gains 9.7–14 bits per 10×. A variable costs 3–5 bits and an application 6 bits or more plus its operands, so each 10× buys roughly one more AST node without dedupe and roughly two with it." The 6–7 bits is the gain per tenfold of work (a factor of 1.38–1.50 per bit gives 5.7 to 7.2 bits per factor of ten). The size of a node is given separately, and it is 3–5 bits for a variable and 6 bits or more for an operator (the same report lists operator overheads of 6, 9 and 14 bits at `empirical.md:183-184` and `:208`). The pre-clarity text was "**Each tenfold increase in work buys about one more AST node** (6–7 bits)", in which the parenthesis could be read either way. The rewrite, which follows clarity-review item A6 (written without opening the sources), fixed the wrong reading and made it the premise of the bold sentence. The gap log has no entry for it.

Replacement: "At a factor of 1.38–1.50 per bit, each tenfold increase in work buys 6–7 more bits. One node of a program's syntax tree, an *AST node*, costs 3–5 bits when it is a variable and 6 bits or more when it is an operator. So **each tenfold increase in work buys about one more AST node**."

**3. FACTUAL ERROR. Two sentences say that the higher-order `filter` was not attempted, and §8.5 of the same document reports that it was run and solved.**

Line 829 (§7.1): "§8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter`. It did not attempt the higher-order `map` and `filter` themselves."

Line 909 (§7.3): "On the kernel's spec rows it was run on `foldl`, `seq-corr`, `best-shift`, `argmax-corr` and `last-or`, and not all of these were solved (§8.5 gives the outcome of each). The higher-order `map`, `foldr` and `filter` were not tested."

What the sources say. The kernel's `filter` spec takes the predicate as an argument: `bootstrap/build-batteries.lisp:628` declares `:spec/filter (list (cons 0 seq-t) (cons 1 pred-t)) seq-t`. The prototype was run on that spec's rows and found `(select xs (lambda (j x) (call1b p x)))`, 200/200, at 1,383 candidates, and the held-out set included a predicate that occurs in no spec row (`verify-review.md:15`, `:63`, `:86`). The frozen copy reports this at line 1111 ("`filter` | 200/200 at 1,383 candidates, once a one-argument Boolean call is in the grammar"). §8 also has `scan` and `map-adjacent` with a function argument (lines 1027, 1028, 1110, 1113), so "first-order instances of ... `scan`" understates as well. `map` and `foldr` are not among the sixteen specs (the kernel derives them by anti-unification), so "not tested" is right for those two. Second, the prototype was run on all sixteen specs' rows (`verify-review.md:54-80`), not on the five that line 909 lists. The sentence comes from the version before §8.5 existed, which said that the prototype of §8.1 "did not test `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`, or the higher-order `map`, `foldr`, and `filter`; §8.6 has since run the first five" (`sections.orig/07.3.md:13`). Each rewording since has carried the list forward without re-reading §8.5.

Replacement for line 829: "§8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter` (§8.1). It also finds `scan`, `map-adjacent` and `filter` when the function or the predicate is an argument (§8.1, §8.5). It did not attempt the higher-order `map` or `foldr`."

Replacement for the two sentences of line 909: "On the kernel's spec rows it was run on all sixteen specs, and thirteen were solved in some configuration (§8.5 gives the outcome of each). Those sixteen include `filter` with its predicate as an argument, which was solved once a one-argument Boolean call was in the grammar, and `foldl` with its step as an argument, which returned an impostor. In these runs a function argument is one of three named functions, not arbitrary code. The higher-order `map` and `foldr` are not among the sixteen and were not tested."

The limit in the last-but-one sentence is from `verify-review.md:39` and `:301`: a function argument is drawn from `+ - *`, and a predicate from `pos`, `even`, `neg`.

**4. FACTUAL ERROR. A code reference that does not do what the sentence says, and an attribution that plan 3 does not make in those words. Added by the rewording; no gap-log entry covers it.**

Line 553: "The kernel does this on frames (§2.1; `frame.lisp:544`, `unify.lisp:103`), and plan 3 already described lift as a pullback of this kind (`deprecated/plan3.md` §3)."

What the sources say. `frame.lisp:544` is `pullback-frame`, whose docstring begins "B(z)=A(d(c,z))", so that reference is right. `unify.lisp:103` is `compile-au-constructor`, whose docstring is "A DSL program maps quoted hole fillings to the instantiated quoted expression." It builds a decoder from an anti-unification pattern. It does not pull a requirement back, and it does not act on a frame (`laws-library.md:214` describes it the same way). The two references come from one row of the former Appendix B (`sections.preclarity/AB.0.md:13`), which carried two separate ideas: "Lift as predicate pullback, B(z) ⇔ A(d(c, z))", which goes with `frame.lisp:544`, and "Pattern instantiation is the decoder", which goes with `unify.lisp:103`. The rewording attached both references to the first idea. Second, plan 3 never uses the word "lift" (a search of `deprecated/plan3.md` finds none). Its §3 (L122 to L148) defines the requirement on a child as B_i(z) ⇔ A_i(d(c_i, z)). It is the document auditor who calls that a definition of lift (`docs-origins.md:603`, "lift is defined here as pulling a *requirement* back along a decoder").

Replacement: "The kernel does this on frames, in `pullback-frame` (§2.1; `frame.lisp:544`). Plan 3 already defined the requirement on a child problem by a pullback of this kind, B(z) ⇔ A(d(c, z)) (`deprecated/plan3.md` §3), and the document auditor reads that definition as the first statement of lift (docs-origins report)."

If the second reference is wanted, it belongs in §5.4, with the instance space: "The kernel already compiles an anti-unification pattern into the decoder that rebuilds each instance from its hole fillings (`compile-au-constructor`, `unify.lisp:103`)."

**5. FACTUAL ERROR. Line 287.**
Sentence: "Each of the document auditors' reports lists ten to twelve of them; these four matter most:"
Source: four of the six document auditors' reports have a list of recurring problems, and the counts are 11, 10, 15 and 12. `docs-origins.md:474-547` lists R1 to R11. `docs-plan6-results.md:362` onward lists 10. `docs-plan7-arch.md:363-379` lists 15 (items 1 to 15, ending with "Per-level machinery"). `docs-plan8-9.md:495-508` lists 12. The other two document reports, `docs-v2b.md` and `docs-v2tex.md`, which Appendix D also lists as document auditors' reports, have no such list. The gap log cites `docs-plan7-arch.md:363` as support, and that line is the heading of the list of 15. The pre-clarity wording ("the reports list ten to twelve each") had the same error; the rewording made it a statement about every report.
Replacement: "Four of the document auditors' reports (those on plans 1 to 9) each list between ten and fifteen such problems; these four matter most:"

**6. FACTUAL ERROR. Line 289.**
Sentence: "The record of which sub-problem came from which shows the drift. It was kept first on the frame, then in store entries, then off the frame, and then on the frame again as `pairs`, `anchors` and `edges`."
Source: `pairs`, `anchors` and `edges` do not record which sub-problem came from which. They relate rows of one frame: `frame.lisp:12-24` (the struct, with the comment "Typed relations between rows, each (kind key-a key-b) over row keys"), and `core-repr.md:147-150`. The plan itself says so in §2.1 (line 126: "`pairs` links two rows whose values should agree, and `anchors` lists rows whose values should differ ... `edges` are typed links between two rows"), and §3 (line 338) says the derivation graph "exists only as a search tree ... and as a list of messages". The sentence comes from `docs-origins.md:534-539` (R9, "Where does the derivation graph live?"), which uses "derivation graph" loosely: what plan 1 kept on the frame was "lineage", what plan 2 kept on store entries was `prov`, plans 3 and 4 kept call-ids on messages, and what came back on the frame was links between rows. The pre-clarity text said "The derivation graph moved ...", which was the report's own loose phrase; the rewording to "the record of which sub-problem came from which" turned it into a specific claim about the code that the code contradicts.
Replacement: "The record of what is linked to what shows the drift. Plan 1 kept lineage on the frame, plan 2 kept provenance in every store entry, and plans 3 and 4 kept it off the frame, in separate records and in the call-ids of messages. In the present kernel, links are on the frame again as `pairs`, `anchors` and `edges`, but these relate rows of one frame (§2.1); they do not record which sub-problem came from which."

**7. FACTUAL ERROR (a definition that is not what the source says; added by the clarity pass).**
Line 1299: "It handles operators with any number of arguments and respects types. A pair of differing sub-terms that recurs gets one shared hole, and an operator itself can become a hole (§5.4)"
The pre-clarity cell was "n-ary, typed, shared holes, operator holes", copied from `core-repr.md:620`. "n-ary" there means that any number of terms are generalized at once, not that operators may have any number of arguments. `unify.lisp:36`: `(defun anti-unify (sources ...)` takes a list of sources; its docstring (`unify.lisp:37`) says "Equal disagreement tuples reuse the same hole", where a tuple has one sub-term from each source. `laws-library.md:207-208`: "n-ary, typed, syntactic, first-order least general generalisation" and "the table from a tuple of disagreeing subterms to its hole". The gap log cites `lit-discrete.md:342`, which describes the two-term case ("Given two terms ... the same pair of differing subterms"); that is where "pair" came from. The operator hole also has a condition that the cell drops: `unify.lisp:40-41`, "Applications whose operators differ but share a signature are aligned under an operator hole".
Replacement: "It generalizes any number of terms at once and respects types. Where the terms differ, the differing sub-terms, one from each term, are replaced by a hole, and the same combination of differing sub-terms gets the same hole wherever it recurs. An operator itself can become a hole when the operators have the same type signature (§5.4)"

**8. FACTUAL ERROR (file-and-line reference; present before the clarity pass).**
Line 1310: "| Requirement propagation, with replay and fallback | `laws.lisp:736` onward | 338 | re-seat |"
The 338 lines are `laws.lisp:447-784` (`laws-library.md:350`: "`propagate-requirements` with witness replay, necessity refutation, set-valued witnesses, fallback | `laws.lisp:447-784` | 338"). Line 736 is only where the entry function `propagate-requirements` starts; it ends at line 786, so "736 onward" covers 51 lines of the 338.
Replacement for the "Where" cell: "`laws.lisp:447-784`"

**9. FACTUAL ERROR (small). "One for each constructor" is not what the ten rules are.**

Line 136: "To turn a pulled-back requirement into an explicit set of allowed values, the kernel uses ten hard-coded rules, one for each constructor; the learned *solver* entries, ..."

What the source says. `requirements.lisp:245-256` (`*fold-rules*`) holds ten rules, each for one pairing of an outer operator with an inner constructor: `at` on `tuple` and on `cons`; `tail` on `cons`; `length` on `cons`; `=` on `tuple`, `cons`, `if`, `code-apply` and `code-subst`; `member` on `tuple`. That is ten rules over five constructors (`tuple` has three, `cons` has four). `core-repr.md:30` says "ten hard-coded per-constructor fold rules". The pre-clarity text said "ten hard-coded constructor rules". The rewrite added "one for each".

Replacement: "To turn a pulled-back requirement into an explicit set of allowed values, the kernel uses ten hard-coded rules, each of which takes one operation off one constructor (for example, an equality with a literal off a `tuple`, or `at` off a `cons`); the learned *solver* entries, ..."

### INCONSISTENCY

**10. INCONSISTENCY (a stale design statement that the new §6.4 and §8.7 contradict).**
Line 837: "**5. Price names by use.** An operator's name costs −log₂ of its share of uses in accepted solutions (§6.4), under a prefix code as now."
The section it cites now says the opposite. Line 737 (§6.4): "Prices from counts of past use are the form that failed on new operators. So a name's price comes first from its tables, and from counts only as a correction that cannot price a name out **[P]**." Line 1210 (§8.7): "Used as prices in the manner of the published grammar-reweighting method, it sent 5 of the 8 tasks that need one past a cap of three million candidates." Line 719 says the same. The sentence at line 837 was not touched by the clarity pass (it is identical in `sections.preclarity/07.1.md`), so the rewrite of §6 left it behind.
Replacement: "**5. Price names from tables, with counts only as a correction.** An operator's place in the enumeration, and so its price, is read first from how well its verb tables fit the labels of the problem at hand. Its share of uses in accepted solutions enters only as a correction that cannot price a name out (§6.4). Counts alone were measured as prices and failed: they sent 5 of the 8 tasks that needed a never-used operator past the search's cap (§8.7). The code stays a prefix code, as now."

**11. INCONSISTENCY. A pointer into the rewritten §6 that does not land, on a sentence that the rest of the document now argues against.**

Line 362: "Treat the choice of a small grammar for each problem as the main control problem (§6.4)."

What the frozen copy now says. §6.4 (lines 698 to 737) is about words and verb tables. It never discusses choosing a small grammar for a problem. The text that this pointer used to reach was the old §6.3, "The control problem with the most leverage is choosing what to mix into each problem ... Choosing a small grammar is its commonest form (§4.1)" (`git show HEAD:plan_v2c.md`, line 612), and that text is gone. What replaced it says the opposite: line 619, "What did save work avoids choosing a subset at all"; §8.6 (lines 1153 to 1162), where a grammar restricted by the nearest problems cost 0.95 to 1.09 of the full cost, summed over tasks, and only an oracle's choice gave a factor of 12; and experiment X4 (line 1404), none of whose five arms selects a subset. The gap log flagged this pointer as needing a check once §6 settled (`clarity-gaps-sec4-9.md:59`), and it was left as it was.

Replacement: "Treat what a search tries first, when many library entries are in scope, as the main control problem. Choosing a small grammar for each problem would be worth about a factor of 12 if the choice were right, and the one way of choosing that was measured saved nothing (§8.6). The plan therefore orders and filters candidates with verb tables, and does not choose a subset (§6.4)."

**12. INCONSISTENCY. A sentence added by the rewording asserts a mechanism that the design, six lines earlier, says it avoids.**

Line 625: "There the kernel has to select which library entries go into each problem's grammar."

Source. The pre-clarity text said only "as context selection". The clarity review's suggested rewrite (item A45) expanded it into this sentence. Line 619 of the same section says "What did save work avoids choosing a subset at all", the table at line 597 prices that selection as "exponential in the library", and §11.3 gives Stage C "the vocabulary of §6.4 and §6.5 (words chosen by score, verb tables, name prices)" and no step that selects entries.

Replacement for that sentence and the one after it: "There, many library entries are in scope at once, and the outcome depends on which of them a search tries first. The plan does not select a subset of the library for each problem, because the one measurement of that saved nothing (§8.6). It orders and filters candidates by the quotients and verb tables of §6.4, which are first used in Stage C, and analogies between operator tables are found there as terms (experiment X9, §11.2)."

**13. INCONSISTENCY. A leftover of the old "retrieval index".**

Line 621: "The order of attack is fixed by cost: refute with invariants; propose with the index; try a key term; refine; and only then backtrack."

What the frozen copy now says. No index is defined anywhere in §5 or §6. The only indexes left in the document are the ones that lost: line 917, "an index of past problems found 19 at best ... The ones tried did not earn their place", and line 1268. §1.5 (line 101) was already updated to say "run only on the pairs that cheaper signals propose (§5.9)". This sentence was not.

Replacement: "The order of attack is fixed by cost. First refute with invariants. Then propose pairs with the cheap signals listed above, labels first. Then try a key term, then refine, and only then backtrack."

**14. INCONSISTENCY. Line 338 against line 265.**
Sentence (line 338): "It exists only as a search tree with a root and one or two children (§2.3), and as a list of messages that no decision reads (§2.6)."
Source: "a root with one or two children" is the finding for the four specs that stay unsolved in the runs without schemas (`empirical.md:293-297`: `:NODES 3` or `:NODES 2` at every rung; `search-engine.md:41`). It is not the shape of every job. The 19 synthesis jobs of the bootstrap have "1 to 5 nodes each (1, 2, 3, 4, 5 nodes: 1, 5, 7, 5, 1 jobs)" (`bootstrap-reflection.md:121-122`), and §2.6 of the plan says so two pages earlier (line 265: "the jobs, with one to five sub-problems each"). The pre-clarity text ("a two-node tree per job") was also inexact; the rewording replaced one inexact count by another and added "only".
Replacement: "It exists only as a small search tree for each job, with one to five sub-problems in the bootstrap's jobs and two or three on the specs that stay unsolved (§2.3, §2.6), and as a list of messages that no decision reads (§2.6)."

**15. INCONSISTENCY (a count with no referent; the gap log marks it UNFILLED and the plan still asserts it).**
Line 1335: "On tariffs: nothing here preserves the present prices in bits or in work, and three of those prices are artifacts (§2.7)."
§2.7 (lines 271-279) names two: line 277, the name bits that are "an accident of its position in the list of primitives", and line 278, the work price list that "charges quadratic cost for operations that are not quadratic in the host", illustrated by two examples. No third is identifiable (`clarity-gaps-sec4-9.md:54` reached the same conclusion; `core-repr.md:89` and `:56-58` are the two sources).
Replacement: "On tariffs: nothing here preserves the present prices in bits or in work, and two of them are artifacts: the name bits, which follow an operator's position in the list of primitives, and the work price list, which charges quadratic cost for operations that are not quadratic in the host (§2.7)."

**16. INCONSISTENCY (terms in Appendix C that the rest of the document does not use, or uses differently).**
(a) Line 1499: "| Property signatures (BUSTLE) | one lineage | ... | property sets (§8.6) |". §8.6 never says "property set". It calls the thing a "signature" throughout (lines 1141, 1143, 1151, 1157, 1162), and line 1281 says "Words replace signatures and counts". The pointer lands on the right measurement; the name does not match. Replacement for the cell: "the sets of properties compared between whole problems, which §8.6 calls signatures and which did not find the operators a problem needs".
(b) Line 1498: "| Grammar reweighting during search (Probe) | one lineage | ... | counts |". After the rewrite, counts failed as prices (line 1210) and survive only as a correction (line 737). Replacement for the cell: "counts of past use, which failed as prices on never-used operators (§8.7) and are kept only as a correction to the tables (§6.4)".
(c) Line 1496: "§7.3 case 5; context selection". "Context selection" occurs nowhere else in the document. Replacement: "§7.3 case 5; the choice of which library entries go into a problem's grammar (§4.1, §5.9)".
(d) "One lineage" (lines 1498, 1499, 1505) is not defined; line 1483 defines only "Shipped" and "Replicated". The gap log left it undefined because the obvious definition is wrong for Probe: `lit-search.md:218` grades Probe "PROVEN-RESEARCH (re-implemented by Bee Search authors; baseline for Simba, DryadSynth)" and `lit-search.md:362` "SINGLE-PAPER, re-implemented once"; `lit-geometry.md:373` grades property signatures "PROVEN-RESEARCH". Replacement for the Probe grade: "one system, re-implemented once by another group". Replacement for the BUSTLE and LAPS grades: "one research group and its follow-up systems". If "one lineage" is kept, add to line 1483: ""One lineage" means one research group and the systems that follow from its work."

**17. INCONSISTENCY (term). "Spec" is defined as a function, and the library's `:spec` entries are a wider set.**

Line 177 (and the Terms table, line 25): "A *spec* is one function that the bootstrap asks the kernel to synthesize, given as a few rows of inputs and outputs."

What the source says. A `:spec` entry "holds: the input and target types; the example rows ...; a `:specifies` edge naming the entry to produce", with metadata for solvers as well as functions (`bootstrap-reflection.md:313-321`). The library holds 31 of them (`bootstrap-reflection.md:157`), and they specify solvers, guards and transformers besides functions (`bootstrap-reflection.md:358-359`, `:401-402`, `:811`). §2.5 at line 238 speaks of "31 `:spec` entries" beside "the 16 specs of §2.3". The definition fits the sixteen of this section and does not fit the thirty-one.

Replacement: "A *spec* is one entry that the bootstrap asks the kernel to produce, given as a few rows of inputs and outputs. The library holds 31 specs. The sixteen used in this section are the ones that specify functions."

**18. INCONSISTENCY, minor. "Tested" is defined two ways.**

Line 540 (§5.5): "**Tested**: the two terms also have the same column on several fresh spaces that include boundary values. ... The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are knowledge of this grade (§6.4)."

What the frozen copy says elsewhere. §6.4, line 724: "A verb table is learned on a probe space and read on a task's space. That is knowledge carried across spaces without being re-checked there (§5.9), which is the definition of the tested grade (§5.5)." §5.5 defines the grade by a positive check on fresh spaces. §6.4 defines it by the absence of a check on the space where the knowledge is used, and a verb table is read off one probe space, with no second space involved. The Terms table (line 38) follows §5.5.

Replacement for the last sentence of the bullet: "The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are used as knowledge of this grade (§6.4): they are true of the probe rows they were read from, and they are used on task rows where they have not been checked."

**19. INCONSISTENCY, minor. "Retrieval" is the old term, and retrieval is the use that the measurements did not support.**

Line 402: "A flat space is the right shape for *retrieval and ranking*, and the wrong place for truth."

What the frozen copy now says. The next sentence was updated to "a layer over the exact store that ranks and filters". Retrieval of similar problems by flat properties found the form of a program and not its operators (§8.6), and an index of past problems found 9 to 19 of 25 repeats where plain replay found all 25 (line 1268).

Replacement: "A flat space is the right shape for *ranking and filtering*, and the wrong place for truth."

**20. INCONSISTENCY, minor, older than this round. "Its one impostor".**

Line 545: "The prototype does not do it, and returned its one impostor as an answer (§8.1)."

What the frozen copy says. §8.1 reports the one miss in 135 default runs (line 1037) and a second impostor under the larger grammar (line 1039). §8.5 reports impostors returned on the kernel's spec rows for `map-adjacent`, `foldl`, `best-shift`, `argmax-corr`, and two reductions without lifting (lines 1112 to 1116).

Replacement: "The prototype does not do it. In its 135 default runs on its own rows it returned one impostor as an answer (§8.1), and on the kernel's much shorter spec rows it returned several (§8.5)."

### OVER-STATEMENT

**21. OVER-STATEMENT. The paragraph on arXiv 2611.17309 was strengthened in the rewording, and it now says that a claim holds which no source in the audit checks.**

Line 400, three sentences:
(a) "The paper you cited in the margin, arXiv 2611.17309, supports this."
(b) "Your note on the paper said that "it took several years for it to become 'too easy'", and that "I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else.""
(c) "Both halves of your note hold, and the second is the one that matters here: the bits of the answer come from fast evaluation, not from the model."

What the sources say. The two quotations in (b) are verbatim; I read the note in `plan_v2c_annotated.pdf` itself. (a) The pre-clarity text said "bears on this". "Supports this" comes from the clarity review's suggested wording (item C2) and from no source. The two literature auditors who read the paper concluded otherwise: "The result is about a *tiny hypothesis space matched exactly to the problem* plus a *local training objective*, not about fast evaluation of a large search space" (`lit-search.md:574`); "it does not say what the owner's gloss says" (`lit-geometry.md:46`); "What transfers to symbolic program/law search. Plainly: little" (`lit-search-appendix-sci.md:496`). The plan may side with the owner's reading, but it should not present the paper as support without saying that its own auditors read it differently. (c) Before the rewording, "both halves" followed a description of the paper's cheap moves, and had no stated referent. The rewording made the first half the claim that the benchmarks took "several years" to become too easy. No report measures or cites that. The revision notes only say "agreed that it took years". The middle of the note, which the plan does not quote, is the part the paper's text fails to bear out: "700-900 flops per move" and "a B200" are not in the paper, which reports an H200 (`revision-notes.md:117`; `factcheck2-A.md:203`).

Replacement for the three sentences: "The paper you cited in the margin, arXiv 2611.17309, bears on this. Its model is small and represents the rules of the puzzle exactly, and its answers come from a very large number of very cheap moves. Its authors add that these benchmarks are too easy, and that learning latent quantities "remains an important open research direction". Your note on the paper said that "I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else." For this paper that holds: a model with one hand-set weight already solves every puzzle, so the bits of the answer come from the search and not from the model. The two literature auditors drew a narrower lesson, that the paper's hypothesis space is tiny and matched to the puzzle and that little of it carries over to program search (lit-search report, §9.3). Either reading argues for an exact store with cheap evaluation, and not for a learned embedding. Your note also said that "it took several years for it to become 'too easy'"; the audit has no source on that, and the authors' remark is about what the benchmarks can show today."

**22. OVER-STATEMENT. The tree is "a root with one or two children" only for the four specs that stay unsolved.**

Line 196: "At every budget tried, this tree is a root with one or two children." The same claim, unqualified, is in §1.1 at line 57 ("the search tree has two or three nodes at every budget").

What the source says. `empirical.md:293-297`: "For the four unsolved recursive specs the node census is identical at every rung from 350k to 350M", with 3 nodes for `map-adjacent` and `shift-seq` and 2 for `scan` and `best-shift`. For `argmax-corr`, which is one of the seven specs of the table's second row, the same report gives 34 sub-problems at 35 million work units, and 49 and 64 when `:max-depth` is raised to 3 and 4 (`empirical.md:356-362`; log `empirical/logs/e4_x100_argmax-corr.log`, ":NODES 34"). That tree did grow, and it returned an impostor. The pre-clarity sentence ("The search tree has two or three nodes at every budget") had the same gap; the rewrite made it more definite. The next sentences of the paragraph already speak of "these children" and of "the four specs that stay unsolved", so the qualifier only needs to move up.

Replacement: "On the four specs that stay unsolved, this tree is a root with one or two children at every budget tried. (The tree of a fifth spec, `argmax-corr`, did grow, to 34 sub-problems, and to 49 and 64 when it was allowed more depth. What it returned was an impostor.)"

**23. OVER-STATEMENT. Line 231.**
Sentence: "**Every step that turns a discovered law into something the search can use is a hand-written recognizer of particular shapes.** There are four such steps **[C]**."
Source: `laws-library.md:29` (its finding 8) says "Every cross-kind conversion that carries "algebra" is a hand-written shape recogniser", that is, every conversion from one kind of library entry to another. The same report's conversion table (`laws-library.md:186-194`) marks three conversions of a law as generic: "law → rewrite rule(s) → VM program | `laws.lisp:247-311` | generic", "law(field) → law(`:int`) | generic (type-template unification)", and "solver + certified laws → uniqueness | generic". The rewrite rule is exactly "something the search can use" (it is what `start-search :laws` takes, and what cost 385× in the bullet above). Also, the fourth step listed does not start from a discovered law; it starts from a solver. The pre-clarity heading ("Every conversion that carries algebra is a hand-written shape recognizer") matched the report; the rewording widened it.
Replacement: "**Every conversion from one kind of library entry to another that carries algebra is a hand-written recognizer of particular shapes.** There are four such conversions **[C]**. (Turning a law into a rewrite rule, and retyping a law from a finite field to the integers, are generic; the laws-library report, §2.2, lists every conversion.)"

**24. OVER-STATEMENT, and a tag that no longer covers its claim. Line 259.**
Sentence: "In a separate experiment, with stand-in functions whose bodies were dummies, it made search 6.6× more expensive."
Source: `bootstrap-reflection.md:733-744` (§6.3). Three specs were run. `:seq-corr` went from 100,058 to 664,209 work (6.6×). `:filter` went from 118,580 to 119,209 and `:last-or` from 160,394 to 161,050, which is no change. The report says "Mostly neutral, and 6.6x worse for `:seq-corr`", and its summary (line 84) says "in one case cost 6.6x". The reworded sentence reads as a general result. Separately, the pre-clarity paragraph ended in **[M]**, which covered this figure; the tag now sits after "The test was 8 held-out tasks", so the 6.6× figure is untagged.
Replacement: "In a separate experiment **[M]**, functions with dummy bodies were added to the grammar of three specs. Two of the three were unaffected, and the third, `seq-corr`, became 6.6× more expensive."

**25. OVER-STATEMENT. The gloss on reentrancy is attributed to you and has no source.**

Line 162: "*Reentrancy*, your "freely shifting abstraction level", would be the kernel applying its own search to its own programs and records."

What the source says. Your prompt (`plan_v2_prompt.md:5`): "Reentrancy I think means freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph - whether that's an execution graph, a literal graph described by the data, graph generated by an AST, or some combination of all these". The gloss "the kernel applying its own search to its own programs and records" comes from the clarity review's proposed rewrite (item A35), which was written without opening any source. The worker on §4 declined to use it for that reason (`clarity-gaps-sec4-9.md:12`: "was not used, because no source states it"), and §4.6 (line 412) quotes you instead. The worker on §2 used it, and the §2 gap log has no entry for it. The sentence was not in the pre-clarity §2.2. What the search audit does say, in the section the plan cites, is what exists today toward reentrancy: synthesis over code values, frames built from the search's own messages, and searches nested in searches (`search-engine.md:752-771`), and then "What concretely stops full reentrancy" (`search-engine.md:773`).

Replacement: "*Reentrancy* is, in your words, "freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph". The search audit took this to mean that the kernel's search can be applied to the kernel's own products: code, the tables built from its own messages, and searches nested inside searches (search-engine report, §6.1). It lists eight concrete things that block this (search-engine report, §6.2) **[C]**:"

**26. OVER-STATEMENT. "Fitted to" four enumerators, and then "agrees with" the same four.**

Line 358: "The search-literature auditor fitted a model to four published enumerators, and the model agrees with their measured sizes to within a node or two."

What the source says. The model's three parameters were set from anchors drawn from many systems (`lit-search-appendix-enum.md:385` to `:392`: evaluation rate from Bustle, Massalin and STOKE; candidates per class from Probe, ESR, QuickSpec and TRANSIT; branching from the growth table). It was then *checked* against outcomes: "Checks against A.2: ... EUSolver's 9–12 and Probe's 6.5–7.9 ... TRANSIT's 15 and Probe's failure at 19 ... TF-Coder's plain-enumeration ceiling ... Agreement is within about ±2 nodes" (`lit-search.md:641`). The gap-log entry A31 supplied "agrees with their measured sizes" from that line and kept the older word "fitted". As the sentence now reads, the model agrees with the data it was fitted to, which would be no evidence at all, and is not what was done.

Replacement: "The search-literature auditor built a model of enumeration from growth figures in the published systems, and then checked it against the program sizes that four published enumerators reached (EUSolver, Probe, TRANSIT and TF-Coder). It agrees with them to within about two nodes."

**27. OVER-STATEMENT (a design statement with no source, presented in a "Finding" cell).**
Line 1452: "Within a space, neither: rooted, ordered, shared terms are compared by hash, and laws up to renaming by brute force over at most five variables."
The only other place this appears is the cost table of §7.6 (line 973), which is proposal. I found no measurement and no code behind "at most five variables": no report mentions it (grep of all reports for "renam", "five variables", "5 variables"), the prototype has no such routine (`proto/tg-probe.lisp`), and the law experiment of §8.3 used three variables. Appendix A is not covered by the front matter's rule that §5 to §7 are **[P]**, so here it reads as something the audit found.
Replacement: "Within a space, neither. Rooted, ordered, shared terms are compared by hash. This plan proposes to compare laws up to renaming of their variables by trying every renaming, which is affordable only while laws have few variables; that has not been built or measured **[P]**."

**28. OVER-STATEMENT (the word "only" was added by the clarity pass and is not in the source).**
Line 899: "They differ only in the arguments passed to the recursive call, which their author chose by hand."
`search-engine.md:1064-1067` says the five schemas and the kernel's own template are "the same act (bind the recursive call's value as a new input of the child) with a different hand-chosen argument tuple". It does not say that is the only difference, and its own table (`search-engine.md:733-737`) shows others: `:lookahead-inductive` has a second base case, `:state-scan-inductive` wraps the call in `cons`, `:countdown-inductive` adds a test on a counter. The file's header says the same (`bootstrap/recursion-schemas.lisp:6-8`: "a second base case, a state threaded through the recursive call, and an integer counted down or up beside the sequence").
Replacement: "They differ in the arguments passed to the recursive call, which their author chose by hand, and in the base cases and the fixed code that the author wrote around the call."

**29. OVER-STATEMENT. "Raised as well" says that two budgets were raised; the source varies one.**

Line 217: "One test problem from Plan 8 is solved at the default budget. It is not solved at a budget of 1,000,000 work units when the budget of the kernel's first phase is raised as well **[D]**."

What the source says. `plan8.md:296`: "Probe 5 now solves at the default budget in `264,353` work; passing `:heuristic-budget 16000`, which §6.3 and §6.5 recommend, now leaves it unsolved at `1,000,000`." (Quoted the same way at `docs-plan8-9.md:497`.) "The default budget" there is the default budget of the first phase (`:heuristic-budget`, 2,000). The only thing that differs between the two runs is that phase's budget. Nothing says the job's own budget was at its default in the first run and raised in the second. The bold claim ("More budget is not even monotone") stands, but for the first phase's budget.

Replacement: "One test problem from Plan 8 is solved in 264,353 work units when the kernel's first phase has its default budget. When that phase is given a larger budget, 16,000 units, the same problem is still unsolved after 1,000,000 work units **[D]**."

**30. OVER-STATEMENT (two details of the new description of requirement simplification are not what the code does; added by the clarity pass).**
Line 1318: "a rule that drops or reorders a sub-term applies only when that sub-term is provably total. Each rule is held to one of two contracts: the simplified requirement is equivalent to the original, or it is merely necessary for it."
(a) `requirements.lisp:136-139` (`unfoldable-parts-p`): "True when a fold rule may drop or reorder every expression in PARTS: each is provably total or, under the :necessary CONTRACT, built from holes, total constructors, `:code-eval` and structurally terminating functions without unguarded partial primitives." So "only when ... provably total" holds under one contract and is relaxed under the other. (b) The contract belongs to a call of the simplifier, not to a rule: `requirements.lisp:529`, `(defun fold-constants (expression &key ledger (budget 10000) (contract :equivalent) max-fibers)`, and the same rules run under either contract.
Replacement: "a rule that drops or reorders a sub-term applies only when that sub-term is provably total or, under the weaker of the two contracts below, when it is built only from parts that cannot fail (`requirements.lisp:136-149`). Each call of the simplifier names one of two contracts: the simplified requirement must be equivalent to the original, or it need only be necessary for it."

**31. OVER-STATEMENT (mild). Line 315.**
Sentence: "`plan_v2.md` and `plan_v2.tex` rest largely on mechanisms taken from papers without verification and on inventions of their own (the `docs-v2b.md` and `docs-v2tex.md` reports)."
Source: for `plan_v2.md`, `docs-v2b.md:18` gives "6 (A) + 10 (X) on the critical path", and "its headline deliverables depend on all of them", so "largely" holds. For `plan_v2.tex`, `docs-v2tex.md:22` says "Roughly half of the critical path is academic import or novel invention", 21 of 40 mechanisms (`docs-v2tex.md:162`). Clarity-review item C3 allowed the figures to be cut, and its suggested text used "largely"; for `plan_v2.tex` that word is stronger than the report.
Replacement: "`plan_v2.md` rests largely on mechanisms taken from papers without verification and on inventions of its own, and about half of the mechanisms that the gates of `plan_v2.tex` depend on are of those two kinds (the `docs-v2b.md` and `docs-v2tex.md` reports)."

**32. OVER-STATEMENT, minor, older than this round. "Each extra level" is not what the report's figure measures.**

Line 408: "Each extra level of interpretation costs a factor of 6–178, until that level is compiled away by staging **[L]**."

What the source says. "staging gives 7–87× on ground functions, 6–178× through nested interpreters, 2–49× with a sketch" (`lit-discrete.md:243`), and "Measured benefit in a search setting: 6–178× through nested relational interpreters" (`:436`). The figure is the speed-up that staging gave on the benchmarks that run through nested interpreters. Neither line says that each level costs that much.

Replacement: "In the same paper's measurements, staging made the benchmarks that run through nested interpreters 6 to 178 times faster **[L]**."

**33. OVER-STATEMENT, minor. "One research group only" covers two different things in the source.**

Line 376: "Binders and conditional equalities inside e-graphs have been done by one research group only **[L]**."

What the source says. "Slotted e-graphs (binders) | SINGLE-PAPER | PLDI 2025 + one 2026 preprint" and "Colored e-graphs (conditional equalities) | SINGLE-PAPER | One group, two papers" (`lit-discrete.md:48`, `:49`; also `:541`, `:542`). "One group" is said of conditional equalities only, and the sentence as written can be read as one group having done both.

Replacement: "Binders inside e-graphs rest on one paper and one preprint, and conditional equalities inside e-graphs are the work of one research group **[L]**."

### MISSING CAVEAT

**34. MISSING CAVEAT. "Held-out-sound" in this section means one hand-written test case per spec.**

Line 179: "A solution is *held-out-sound* when it is also right on fresh inputs that were not among the spec's rows." (The Terms table, line 27, says "*Held-out* scores count fresh inputs.")

What the source says. The harness that produced "8, then 10, then 10, then 10, of 16" checks each solution on exactly one fresh input, written by hand for that spec: `v2/experiments/stage0-audit.lisp:59-84` (`held-out-test-cases`), copied into the empirical auditor's script (`empirical/scripts/e4_rescue.lisp:64-82`, checked by `held-out-ok` at `:94-103`). A reader who has seen "200/200 on held-out examples" in §1.4 will assume something similar here. With one case per spec, the counts of sound solutions in the first table are upper bounds.

Replacement: "A solution is *held-out-sound* when it is also right on a fresh input that was not among the spec's rows. In the kernel's own audit harness, which produced the counts below, that is one hand-written input for each spec, so a count of sound solutions here is an upper bound."

**35. MISSING CAVEAT. None of the four pruner tests ran inside a synthesis job, and the new label on row 2 suggests that the others did.**

Lines 204-213, in particular line 209: "Arithmetic problems over `+` and `*`, searched on their own rather than inside a synthesis job | Pruning cut work 11–31×." and line 211: "`map-adjacent` | The same work reached 70 bits instead of 47."

What the source says. The 11–31× figures are from two observation searches over a six-row integer problem with `+` and `*` (`search-engine.md:1027-1035`; log `search-engine/exp-d.out`, 141,501 / 12,555 and 1,412,531 / 45,249), so the gloss on "closed arithmetic frames" is right as far as it goes. But the other three rows were flat searches too. The finite-field row is the repository's flat benchmark (`docs-v2tex.md:720-733`). The integer-grammar row and the `map-adjacent` row are "One flat `start-search` over a frame whose target no candidate satisfies" on the root lane's grammar (`empirical.md:172`, `:220-229`). The empirical report says "v2's `:prune-behaviors-p` was measured in flat searches only (E3, E3b). I did not wire it into the synthesis job's node searches, so there is no E4 number with dedupe on" (`empirical.md:540-541`), and the search audit lists as not determined "Whether the dormant v2 pruning stays sound inside the full tree (recursive jobs, CEGAR, shared tables)" (`search-engine.md:1078-1079`). The pre-clarity text did not have the caveat either, but it also did not draw a contrast that only one row satisfies.

Replacement for the cell at line 209: "Integer arithmetic problems over `+` and `*`, on six rows". Replacement for the sentence at line 204 that introduces the table: "Three auditors switched them on by hand **[M]**. All four tests were flat searches. The pruner was not run inside a synthesis job, and whether it stays sound there was not determined."

**36. MISSING CAVEAT (created by a cut that clarity-review B2 allowed).**
Line 1452, same cell. Before the clarity pass the cell went on: "Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run on what the index proposes. The e-graph's store is useful; its saturation is not." B2 asked for the cell to keep only its first sentence. What is left answers "we'd need an efficient graph isomorphism test ..., or e-graphs" with "neither", which is the opposite of what the plan says at line 101 ("Across spaces a matching engine is needed, as you say") and in §5.9. A reader who uses Appendix A as the index of answers gets the wrong one.
Replacement, to follow the sentence in finding 27: "Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run only on the pairs that cheaper signals propose (§5.9). An e-graph's store is worth having, and its saturation is not (§4.3)."

**37. MISSING CAVEAT. Line 238.**
Sentence: "The bootstrap writes 61 library entries that the search can use, beside 31 `:spec` entries that only hold example rows. To make them it runs 19 synthesis jobs: one for each of the 16 functions it synthesizes, which are the 16 specs of §2.3, and three more that find two guards and one solver."
Source: the numbers are right (`bootstrap-reflection.md:158`, `:121`, `:401-402`, `:266-267`). Three phrases added in the rewording are not what the source says.
(a) "To make them it runs 19 synthesis jobs" reads as if the 19 jobs produce the 61 entries. The 19 are only the jobs that go through `resume-synthesis` (`bootstrap-reflection.md:121`). The eight arithmetic solvers, which are the whole "generic search" row of the table below, come from eight plain searches outside the 19 (`bootstrap-reflection.md:114`, `:210`: "plain `start-search`"), and the eight sampled laws come from four observation jobs (`laws-library.md:41-52`).
(b) "that the search can use" replaces the report's word "operational" (`bootstrap-reflection.md:158`). Ten of the 61 are transformers, which consolidation code calls by fixed id and no search uses (`bootstrap-reflection.md:243-248`; `laws-library.md:259`).
(c) "that only hold example rows": a `:spec` entry also holds the types, a `:specifies` edge, and metadata that includes the operator whitelist (`bootstrap-reflection.md:315-319`). The whitelist of §2.3 is stored there. And the 31 `:spec` entries are not all specs in the sense of the Terms table (line 25, "one function the bootstrap asks the kernel to synthesize"): by the `:specifies` edges in `scripts/bootstrap-reflection/entries.txt`, 13 specify functions (the ten synthesized functions that are saved, and `:map`, `:foldr` and `:scan-pair`), 12 specify solvers, and 6 specify transformers (see also `bootstrap-reflection.md:358-359`).
Replacement: "The bootstrap writes 61 operational library entries (laws, solvers, functions, transformers, descriptors, one template and one motif), beside 31 `:spec` entries. A `:spec` entry holds the example rows, the types and the operator whitelist for one entry to be produced; ten of the 31 are the specs of the synthesized functions that are saved, and the others are for derived functions, solvers and transformers. Among its searches, the bootstrap runs 19 synthesis jobs: one for each of the 16 functions it synthesizes, which are the 16 specs of §2.3, and three more that find two guards and one solver's answer term. The laws and the eight arithmetic solvers come from separate, plain searches."

**38. MISSING CAVEAT. The sentence added for "depth two" asserts the link that the gap log marked UNFILLED.**

Line 531: "Experiments to depth two are your requirement from October (§2.8)."

What the source says. The October text is "do the same for all the other elementary operators in the toolbox, including negation, up to (say) depth=2 (this is essential!)" (`deprecated/plan.md` L86 to L88). That is about running operators composed two deep. The gap log says in so many words that this "does not confirm the review's reading (functions among the inputs)" and that no definition was written (`clarity-gaps-sec4-9.md:50`). But the new sentence stands directly after the heading "Depth-two experiments are spaces whose cells hold terms" and before "A space whose rows range over `(f, g, xs)`", so it tells the owner that this construction is the October requirement. The nearer support is the current prompt: "Algebra emerges from running parallel and depth >= 2 experiments on the simulator, showing that expressions themselves can be abstracted over in the same way" (`plan_v2_prompt.md:2`).

Replacement: "In October you asked for experiments on operators composed "up to (say) depth=2" (§2.8), and your current prompt says that "depth >= 2 experiments" show "that expressions themselves can be abstracted over in the same way". This plan reads the second as experiments whose inputs include functions. That reading is the plan's own."

**39. MISSING CAVEAT (Appendix B says nothing is re-imported; one rejected item has a close relative in §5.9, and the table is a selection).**
Line 1459: "This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2)." Line 1475: "| A spectral embedding and a `like`/`analogy`/`act` query language | interpreter weight at a library of a few hundred |"
(a) The removal that line 1475 summarizes had three parts. `docs-v2tex.md:296`: "Closed-form 32-dimensional Laplacian/SVD, 2-hop WL hashes, the `(:like/:analogy/:act)` query DSL | "Eigensolver or interpreter bloat" at |L| ≤ 500"; `plan_v2.tex:401` has the same three. The row drops "2-hop WL hashes". WL (Weisfeiler–Leman) hashing is colour refinement, which this plan uses at line 608 to match rows and at line 617 as a signal ("the colour histograms of two spaces"), with a measurement in §8.6. The use differs (an exact match that is then verified, against a similarity hash), and it is measured, but the appendix is where the owner will look for exactly this and it is silent. The three word types 'like', 'action', 'analogy' of line 706-708 are the owner's own (prompt line 8), not a query language, so they are not a re-import; one clause saying so would help for the same reason.
(b) The table has 17 rows. `docs-v2tex.md:259-301` records about 35 removals across the three passes (for example tree automata from Burst, PIE bi-abduction, unboxed integer columns, experimentation as an object-language primitive). The front matter (line 17) says "Appendix B lists what their own audit passes rejected", which reads as complete.
Replacement for line 1459: "This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2). One further item has a relative here. The pass that removed the spectral embedding also removed graph hashes made by colour refinement; this plan uses colour refinement to match rows across spaces (§5.9), where every match is then checked exactly, and that use was measured (§8.6). The table lists the rejections that bear on this plan; the full record of about 35 is in the `docs-v2tex.md` report, part 3.1. The reasons given for each rejection are those recorded in the revisions of `plan_v2.tex`."
Replacement for the first cell of line 1475: "A spectral embedding, graph hashes by colour refinement, and a `like`/`analogy`/`act` query language"

**40. MISSING CAVEAT (the new definition of the fact-and-measure scheme leaves out half of the criterion, and the line count covers only part of what is described; added by the clarity pass).**
Line 1319: "The first is the fact-and-measure scheme, about 50 lines. A branch is judged under the facts that its condition establishes, and a recursive definition is total when the arguments of every self-call decrease on measures of its parameters: a sequence shortened by `tail`, an integer bounded below that is reduced by a literal, or an integer bounded above that is increased."
`core-repr.md:304-306`: "A definition is total if every step is total under path facts **and** its self-calls descend lexicographically on per-parameter measures". The code agrees (`ast.lisp:1023-1027`, docstring of `analyze-function-body-totality`; `ast.lisp:1007-1013`, docstring of `self-calls-descend-p`: "Some measure must fall at one call at least and rise at none ... That is a lexicographic order"). So decreasing self-calls are necessary and not sufficient, and not every self-call has to decrease. On the count: `core-repr.md:619` gives "the fact/measure scheme (`self-call-changes`, `self-calls-descend-p`, 50 LOC)"; those two functions are `ast.lisp:971-1022`, 52 lines. The branch facts described in the first half of the sentence are a different function, `condition-facts` (`ast.lisp:764-831`, 68 lines), which the 50 does not include.
Replacement: "The first is the fact-and-measure scheme. A branch is judged under the facts that its condition establishes (`condition-facts`, 68 lines). A recursive definition is total when every step of its body is total under those facts and its self-calls descend in a lexicographic order on measures of its parameters: a sequence shortened by `tail`, an integer bounded below that is reduced by a literal, or an integer bounded above that is increased. The test on self-calls is about 50 lines (`self-call-changes`, `self-calls-descend-p`)."
Line 907 ("The kernel's termination check, about 50 lines that can be carried over") is consistent with the 50-line figure and needs no change.

**41. MISSING CAVEAT ("as code" for the largest row of the table; present before the clarity pass).**
Line 1302: "| Description-length-gated abstraction | `abstraction.lisp` | 580 | as code | it is what finds `:map` |", with line 1293: ""As code" means the file can be lifted nearly unchanged."
The auditor's verdict on that file is narrower. `laws-library.md:355`: "Works on the 6-function corpus; cover heuristics are list-specific." `laws-library.md:216`: the cover's "atomic units" are "hand-listed list-recursion idioms: a bound variable, `(tail X)`, `(at X c)`, a self-call", and the pattern keeps "recursive control spines". The plan replaces tail recursion with `tabulate`, `fold` and `scan` (§7.1), so those parts will not carry over unchanged. The row is 580 of the 1,287 lines marked "as code".
Replacement for the "Why" cell: "it is what finds `:map`. Its acceptance test, by total description length, carries over. Its heuristics for which sub-terms to share are written for recursion on lists and will need rewriting for the new sequence primitives"

**42. MISSING CAVEAT. Line 294.**
Sentence: "Each of plans 1 to 4 put it off (docs-origins report, part (d)). ... Plan 3 said not to add e-graphs or "a universal graph-matching engine" at first, and plan 4 said that "A general graph-isomorphism solver is unnecessary.""
Source: all five quotations are verbatim (`deprecated/plan.md:241-244` and `:1023-1024`; `deprecated/plan2.md:640-641`; `deprecated/plan3.md:44`; `deprecated/plan4.md:408`). Two things are the worker's reading and not the report's. First, `docs-origins.md:809-824` lists six statements (two from plan 1, one from plan 2, three from plans 3 and 4) and then says "declined on grounds of minimalism four times"; it does not say which four, and it does not say "once in each plan". Reading it as one per plan is reasonable, and the gap log says it was a reading. Second, "put it off" fits plans 1 to 3, which deferred it ("only after a measurement says it is needed", "Do not initially add"). Plan 4 did not defer; it judged a general solver "unnecessary". The report also tags all six statements "[AI]": they were written by the AI authors of those plans, not by the owner.
Replacement: "Each of plans 1 to 4 declined it; the docs-origins report (part (d)) lists six such statements across the four plans, all of them written by the plans' AI authors. Plans 1 to 3 put it off. Plan 1 left out e-graphs until "a measurement says it is needed", although it judged that a minimal e-graph "is a few hundred lines, not a heavy import". Plan 2 kept its patterns small and acyclic until "a measurement says it binds". Plan 3 said not to add e-graphs or "a universal graph-matching engine" at first. Plan 4 went further and said that "A general graph-isomorphism solver is unnecessary.""

**43. MISSING CAVEAT. Counts are listed as a cheap signal with no word of what was measured about counts.**

Line 617: "The fourth is a count of which pairings paid off before."

What the frozen copy now says. §8.8 item 8 (line 1281): "Counts become a correction to the tables." §10 risk 4 (line 1346): "Counts over tens of solved problems carry no signal." §6.4 (line 719): counts used as prices "sent 5 of 8 such tasks past the search's cap". A count of pairings was never measured. Of the four signals, only the first was measured as a way to propose pairs (§8.6), and line 619 reports that it found form and not operators.

Replacement: "The fourth is a count of which pairings paid off before. That one has not been measured, and the counts that were measured, of operators' past use, said nothing about an entry not yet used (§8.7), so a count can only adjust what the other three propose."

**44. MISSING CAVEAT. The comparison in §5.3 stops at §8.1, and §8.5 has since run the case that the sentence says was not run.**

Line 496: "It finds the function-argument version in about five seconds, on twelve of its own examples rather than the spec's eight, and not robustly (§8.1)."

What the frozen copy now says. Line 1113: on the spec's own eight examples the prototype returns "an impostor built from a guard split, 29/200, under first-fit acceptance; the right program, 200/200, when splits are accepted in size order", at 616,232 candidates and 64 ms (`verify-review.md:72-73`).

Replacement: "It finds the function-argument version in about five seconds, on twelve of its own examples, and not robustly (§8.1). On the spec's own eight examples it returns an impostor when the first split that fits is accepted, and the right program in 64 ms when splits are accepted in size order (§8.5)."

**45. MISSING CAVEAT (a literature claim with no tag, no pointer, and a source that was checked from abstracts only).**
Line 1437: "The method has long precedent for numeric laws and for program slicing."
The gap log (`clarity-gaps-sec2.md:94`) marks this UNFILLED: "has no counterpart in the body or Appendix E that I could find". It is supported, in a report the worker did not search: `lit-discrete.md:34`, "'Hold all but a few inputs constant and see what changes' is an established discovery method for numeric laws (BACON 1977–81; control-variable symbolic regression 2023; AI Feynman 2020) and for program dependence (dynamic slicing, delta debugging, causal program dependence analysis 2025) [V-abs]". So the claim is sourced, the source was verified from abstracts only, and none of the four sections in the "See" cell states it.
Replacement: "The method has precedent for numeric laws, from BACON (1977 to 1981) onward, and for finding what a program's output depends on, as in dynamic slicing; the literature auditor checked these against abstracts only (lit-discrete report, its finding 7) **[L, abstract only]**."

### COSMETIC

**46. COSMETIC (precision). "Its own budget, separate from the job's" can be read as "not charged to the job".**

Line 177: "It has its own budget, separate from the job's."

What the source says. The first phase has a cap of its own (2,000 units by default, 15,000 in the bootstrap), which is "fixed at job creation and does not scale with the top-level budget" (`search-engine.md:60-61`, `:266`; `synthesize.lisp:373-390`). Its work is still charged to the job: it "runs synchronously on a private ledger and is then "paid off"" out of the job's work (`search-engine.md:118-121`).

Replacement: "It has a cap of its own, which is fixed when the job is created and does not grow when the job's budget is raised. The work it does is still charged to the job."

**47. COSMETIC (precision). Two phrases in the Structure paragraph come from the review's rewrite, not from the report.**

Line 196: "a fixed list of *proposal generators*: host functions that each suggest one way to decompose it. The main one is a skeleton for recursion."

What the source says. The search audit lists 18 generators in the kernel (`search-engine.md:703-723`). Several return many decompositions at once (one for each library function, one for each tuple component, up to two features). It calls the recursion skeleton "The kernel's only recursion skeleton" (`search-engine.md:340`), not the main generator. The pre-clarity text said "The kernel's main recursion skeleton".

Replacement: "a fixed list of *proposal generators*: host functions that each suggest one kind of decomposition for it. The one that matters for these specs is the kernel's skeleton for recursion."

**48. COSMETIC (precision). A schema is not "supplied for one function".**

Line 179: "A *schema* is a hand-written skeleton of a recursive program, supplied for one function."

What the source says. There are five schemas for seven functions: `:lookahead-inductive` serves `map-adjacent` and `last-or`, and `:counter-inductive` serves `positions` and `best-shift` (`search-engine.md:733-737`; `bootstrap/recursion-schemas.lisp:8-9`). All five are passed to every synthesis call of the bootstrap (`bootstrap-reflection.md:320-321`), and each fires when its shape applies.

Replacement: "A *schema* is a hand-written skeleton of a recursive program. The bootstrap has five. Each was written with one or two of its functions in mind, and all five are offered to every job."

**49. COSMETIC. The file-and-line reference now reads as the location of `lift-frame`, and it is the interior of that function.**

Line 133: "The nearest thing is the host function `lift-frame` (`frame.lisp:1214-1256`) **[C]**."

What the source says. `lift-frame` is defined at `frame.lisp:1194` and runs to line 1271 (`core-repr.md:385`: "`lift-frame` (frame.lisp:1194-1271, 78 LOC)"). Lines 1214-1256 are the part that expands the decoder. In the pre-clarity text the same reference stood at the end of the sentence, after "and discards it", where it read as the location of the expansion.

Replacement: "The nearest thing is the host function `lift-frame` (`frame.lisp:1194-1271`) **[C]**."

**50. COSMETIC. Two cells of the budget table can be misread.**

Line 189: "The same seven, with 100 and 1000 times the budget (350 million units, about a minute each, 2.6–3.5 GB of live memory)". The parenthesis describes the 1000× runs only. The 100× runs were 35 million units and 6–8 s (`empirical.md:33`, `:35`).

Line 187: the fourth figure of "8, then 10, then 10, then 10" was not measured on a run of all sixteen specs. The whole sequence was run at 1, 10 and 100 times the budget (`empirical.md:370-375`; logs `empirical/logs/e4_seq_x1_nofix.log`, `e4_seq_x10_nofix.log`, `e4_seq_x100_nofix.log`, which give 8, 10 and 10). At 1000 times, "×1000 was run per spec for the five specs unsolved at ×100, not as a whole 16-spec sequence" (`empirical.md:538`). The count of 10 follows, because none of the five gained a sound solution. Both cells were the same in the pre-clarity text.

Replacement for line 189: "The same seven, with 100 times the budget (35 million units), and the five still unsolved with 1000 times (350 million units, about a minute each, 2.6–3.5 GB of live memory)". Replacement for the right-hand cell of line 187: "The number of specs with a held-out-sound solution was 8, then 10, then 10, then 10, of 16. The last figure comes from running each of the five specs still unsolved at 100 times, one at a time."

**51. COSMETIC (precision). Line 276.**
Sentence: "A sub-problem's score is the sum of two numbers that are measured in different places."
Source: `synthesize.lisp:447-457` (`node-analytical-mdl`) adds five terms: program bits priced at the root, residual bits, half the policy score when the model is inexact, 16 bits for each coupled requirement, and a weight times the run work. `core-repr.md:493-498` lists the same five and an optional learned correction. The pre-clarity sentence ("Node scores add program bits ... to residual bits") did not say there were only two.
Replacement: "A sub-problem's score adds two numbers that are measured in different places, together with three smaller terms (half a policy score, 16 bits for each coupled requirement, and a charge for run work)."

**52. COSMETIC (precision). Line 230.**
Sentence: "A `:solver`, for example, is a law together with a choice of which of the law's variables is the unknown. The code builds that law in order to validate the solver."
Source: `laws-library.md:28`: "A `:solver` is literally the law `op(k, W(k,c)) = c` plus a chosen unknown port". The unknown is an argument position of the operator, not a variable of that law; in the law the code builds, the answer term stands in the unknown's place (`consolidate.lisp:556-563`: "The witness law says that, under GUARD, OPERATOR applied to WITNESS gives the target"; `milestones/algebra-discovery.lisp:34-39`, `solve-witness-law`, substitutes the witness for the unknown at a position of the operator).
Replacement: "A `:solver`, for example, is a law about an operator together with a choice of which argument of the operator is the unknown. The code builds that law, with the solver's answer term in the place of the unknown, in order to validate the solver."

**53. COSMETIC (precision). Line 267.**
Sentence: "One group of things learned from traces, the nogoods and the features learned with them to tell such rows apart, saves 2,332 work units on the task `add-len`, out of the 40,155 that the task takes without them."
Source: the ablation removed three things together: "the nogood schema, DIP feature and predictor" (`docs-v2b.md:20`; table at `docs-v2b.md:329-333`). The figures are right (37,823 against 40,155).
Replacement: "One group of things learned from traces, a nogood, the feature learned with it to tell such rows apart, and the learned predictor, saves 2,332 work units on the task `add-len`, out of the 40,155 that the task takes without them."

**54. COSMETIC (precision). Line 234.**
Sentence: "Its only caller is `orient-conserved-quantity` (`laws.lisp:948`), and that function is called only from the tests (`tests/topology.lisp`) **[C]**."
Source: confirmed by grep for the kernel: the one kernel call is at `laws.lisp:948`, and `orient-conserved-quantity` has no caller outside `tests/topology.lisp`. The tests also call `target-sensitive-p` directly (`tests/topology.lisp:42-44`, `:322`). "Up to four other values" is `*sensitivity-alternatives*` = 4 (`laws.lisp:889-890`). The heading "The kernel has one test of dependency" matches `factcheck.md:189`; note that `laws-library.md:133` counts experiments that hold all but one input fixed as "present in two small places", the second being the fiber analysis of `induce-conditional-solver` (`consolidate.lisp:1426-1442`), which lists preimages and is not a dependency test.
Replacement: "Its only caller in the kernel is `orient-conserved-quantity` (`laws.lisp:948`), and that function, like `target-sensitive-p` itself, is otherwise called only from the tests (`tests/topology.lisp`) **[C]**."

**55. COSMETIC (precision). Line 227.**
Sentence: "(The script builds the library as eight *batteries*, each a file of library entries; the algebra battery is the one that holds the laws.)"
Source: eight batteries is right (`empirical.md:87`). The algebra battery holds 12 of the library's 15 laws; the three `cons` laws are in the constructors battery (`bootstrap-reflection.md:182`, `:222-229`).
Replacement: "(The script builds the library as eight *batteries*, each a file of library entries; the algebra battery is the one that holds the laws of arithmetic.)"

**56. COSMETIC (precision). Line 315.**
Sentence: "of about 35 claims that it makes about the code, three were wrong."
Source: `docs-v2b.md:17`: "all held except one miscount (10 fold rules, not 9), one figure I could not reproduce (16,262), and one over-statement". One of the three was not reproduced, which is weaker than wrong. The pre-clarity text said "three errors".
Replacement: "of about 35 claims that it makes about the code, all held except three: one miscount, one figure that could not be reproduced, and one over-statement."

**57. COSMETIC. Words used in a second sense, lines 231, 258, 305.**
"Quotient by laws before anti-unifying" (line 305) uses "quotient" for normalizing expressions by laws. The Terms table (line 35) defines a quotient as a small term that takes a value to one of a few labels. "Fold signature" (line 231) and "type signature" (line 258) use "signature" for the argument and result types of a function; this is a plain use, and no sentence in lines 221 to 346 uses "property signature", "usage counts", "retrieval index" or "four geometries". "Witness" (line 251) is glossed as the code's name for the answer term, which keeps it apart from the witness of §5.9. "Spec" is used for the 16 function specs and for the 31 `:spec` entries (finding 37). "Stage" at lines 315 and 317 always says "of the v2 plans". No use of "node", "class" or "probe" occurs in the slice.
Replacement for line 305: "*Normalize by laws before anti-unifying* (results, `deprecated/results.md` and `deprecated/plan6.md`): anti-unification of expressions first normalized by known laws took a pattern from 5 holes to 2."

**58. COSMETIC. A pointer from Appendix A into the slice. Line 1454.**
Sentence: "Agreed. Columns, a behaviour table, and a shared term graph are common to both earlier plans and survive here. | §2.9, §9"
§2.9 (lines 315 to 328) mentions "index columns, one behaviour table" only as the content of `plan_v2b.md`'s Stage 0. It does not say that these, or a shared term graph, are common to both earlier plans. The pre-clarity §2.9 did not say it either, so the rewording did not cause this; the pointer promises more than §2.9 holds.
Replacement for the "See" cell, unless §9 is given the sentence: "§9".

**59. COSMETIC. The pointer to the revision notes promises details that the notes do not all carry.**

Line 400: "The details of the paper, and the full answer to your note, are in `plan_v2c_audit/revision-notes.md`."

The cut (clarity review, C2) removed five details from §4.5. The draft `revision-notes.md:117` carries the Triton kernels and the 2.0 × 10⁹ FLOPs. It does not carry "fitting it takes milliseconds" or "one hand-set value already solves every Sudoku puzzle, and three every maze". Those two facts are now nowhere in the plan or the notes. They are in `lit-geometry.md:551` to `:559` and `lit-search.md:571`. If finding 21's replacement is used, the hand-set weight returns to the text. Otherwise add one sentence to the notes: "The paper fits its model in 42 ms and 132 ms, and a hand-set energy with one distinct weight solves every Sudoku test puzzle, and one with three solves every maze."

**60. COSMETIC. Two phrases in quotation marks have no source.**

Line 608: "It is the "graph walker": a colour that flows along verified links." Line 609: "This is the "graph isomorphism engine"."

Neither phrase is in any repository document (`factcheck2-A.md:214`, and the gap log's UNFILLED entry A45). The owner's prompt has "an efficient graph isomorphism test" and "proximity flows along verified topological links" (`plan_v2_prompt.md:10`, `:7`). If the phrases are from the owner's unfiled request they should be attributed. If not, the marks should go.

Replacement for 608: "It is a walk over the graph: a colour that flows along verified links, as in your phrase "proximity flows along verified topological links"." Replacement for 609: "This is the isomorphism test that your prompt said might be needed."

**61. COSMETIC. The caption's rule for bold does not fit two rows.**

Line 416: "Bold marks the cells that the proposal of §5 takes up: for each operation, the perspective that the paragraph after the table names as supplying it."

The bold cells do match the paragraph, cell for cell, as the gap log says. But the row "Substitution, composition" has no bold cell, the last row ("Mature at the scale needed") is not an operation, and for "Closeness" the measure the plan itself calls bedrock is the per-column codes of §6.1, which is the relational cell and is not bold.

Replacement: "Bold marks, in each row, the perspective that the paragraph after the table names as the plan's source for it. The first row has none, because every perspective supplies substitution."

**62. COSMETIC, older than this round. "Three short routines".**

Line 521: "The prototype implements it as three short routines, 22 lines, and uses them only for lifts over output and input positions."

`proto.md:51` lists four functions in those 22 lines, "`explode`, `pull`, `collect`, `elt-col`", and `proto/tg-probe.lisp:255` to `:268` has the four definitions.

Replacement: "The prototype implements it as three short routines and one helper, 22 lines in all, and uses them only for lifts over output and input positions."

**63. COSMETIC. One of the three results under a single [L] was not checked online.**

Line 396: "Three results show it **[L]**. First, a tree can be embedded exactly in a flat space."

`lit-geometry.md:320` to `:322`: the measured result (Hewitt and Manning) was verified, and "Any tree embeds exactly this way with about one axis per edge" is tagged `[FROM-MEMORY, textbook]`. The construction in the plan's next sentence proves the claim, so nothing is wrong, but Appendix C's list of what was not checked online leaves it out. Either tag the first result **[L, from memory]** or add it to that list.

**64. COSMETIC. The outline does not call the matching problem by that name; it says the other thing is a matching problem.**

Line 615: "It calls the matching problem "the quotienting-AU problem" (AU is anti-unification) and describes it as "structure & type-aware & locality-seeded"."

`prompt4.md:170`: "This makes the quotienting-AU problem that of a structure & type-aware & locality-seeded subgraph isomorphism problem." The quoted pieces are verbatim. The outline names the problem of quotienting and anti-unifying, and says that it is a matching problem.

Replacement: "It says that "the quotienting-AU problem" (AU is anti-unification) is a subgraph matching problem that is "structure & type-aware & locality-seeded"."

**65. COSMETIC (a quotation that is not verbatim from its primary source).**
Line 829: "because they "Smuggled `map-indexed`/`foldl` into host Lisp via higher-order opcodes""
The quotation is taken from the audit report (`docs-v2tex.md:293`), not from the document it attributes. The revision itself (`git show dbd3347:plan_v2.tex`, line 113) reads: "\texttt{v2.2} smuggled \texttt{map-indexed}/\texttt{foldl} into host Lisp via higher-order \texttt{:tabulate}/\allowbreak\texttt{:loop} opcodes and a \texttt{:filter}-specific propagator". So the capital S is the report's, and "`:tabulate`/`:loop`" was dropped without a mark.
Replacement: "An earlier audit pass removed `:tabulate` and `:loop`, saying that the version before it had "smuggled `map-indexed`/`foldl` into host Lisp via higher-order `:tabulate`/`:loop` opcodes", and the next pass put them back."

**66. COSMETIC (Appendix A gives one cause where §6.3 gives three; wording added by the clarity pass from review item A51).**
Line 1444: "The clunkiness comes from having eight representations of one thing (§2.7)."
Line 690-694 (§6.3): "ambient pricing is not what made residuals clunky. Three implementation facts did (§2.7)", and lists the eight representations, a metric that cannot depend on the row, and program bits sized at the root added to residual bits sized in a child space.
Replacement: "The clunkiness comes from three facts of the implementation, of which the first is that one thing has eight representations (§2.7, §6.3)."

**67. COSMETIC (three small points in the §9 totals and table).**
(a) Line 1309: the "Lines" cell "215–315" is now unexplained, because the sentence that explained it ("where two auditors counted the same code differently, both figures are given") was cut under review item C7. Replacement for the cell: "215 by one auditor's count and 315 by another's". (b) The same row lists `laws.lisp:215-228`, 14 lines that the row above it (`laws.lisp`, 228 lines, which is `laws.lisp:1-228`) already counts. (c) Line 1289 ends "The kernel proper is 17,647 lines", right after "About 3,500 lines are worth carrying over". About 370 of the 3,500 are milestone code (line 1313), which the 17,647 does not include (17,647 is the root `*.lisp` total of 17,818 less `load.lisp` and `benchmark.lisp`). Line 116 has it right ("of the present kernel and its milestone code"). Replacement for the last sentence of line 1289: "The kernel proper is 17,647 lines; about 370 of the lines to carry over are milestone code outside that count."

**68. COSMETIC (three cells of Appendix C).**
(a) Line 1508: "perfect heuristics in polynomial time in three of six benchmark domains". `lit-abstraction.md:12` quotes the paper: "in three of the six classical planning benchmarks that have polynomial-time optimal solution algorithms". Replacement: "perfect heuristics in polynomial time in three of the six benchmark domains that have polynomial-time optimal algorithms". (b) Line 1509 names EURISKO alone. The analysis it paraphrases is of both systems (`lit-discrete.md:563`: "AM and EURISKO: by the author's own analysis ..."), and the specific point about short Lisp programs is about AM, which is how line 952 attributes it. Replacement for the first cell: "Reflection that compounds (AM, EURISKO)". (c) Line 1463: "computation in superposition does not compress". Line 398 and line 1504 say it compresses quadratically, as does the recorded reason (`docs-v2tex.md:263`: "quadratically, not exponentially, efficient"). Replacement: "computation in superposition is only quadratically efficient".

**69. COSMETIC (§7.3, last paragraph; present before the clarity pass).**
Line 909: "Published recursion synthesizers need examples that are closed under the recursive call ... Otherwise they need angelic execution". The two definitions that the clarity pass added are correct (`lit-search.md:241`, Myth's trace-complete examples; `lit-search-appendix-enum.md:203`, Burst: "assume recursive calls can return anything ("angelic"), synthesise, then check"). The either-or is not exhaustive in the report's own table: `lit-search.md:244` (SMyth, "no trace-completeness", by live bidirectional evaluation) and `:248` (SyRup, joint search of traces and programs). Replacement for "Otherwise they need angelic execution, which ...": "The published ways around that requirement are angelic execution, which assumes that a recursive call can return anything, synthesizes, and then checks, and two single-paper techniques that push examples through partly written programs or search for the missing traces **[L]**."

**70. COSMETIC (Appendix A, row on policies).**
Line 1445: "The one learned policy is a clamped regression on six integers."
It is not a regression in the usual sense. `core-repr.md:522`: "an `:int` AST run in the VM on six integers"; `consolidate.lisp:21-25`: the kernel's own `condense-heuristic` induces a program from a frame of six integer inputs whose labels are clamped to [−24, 48]. §2.6 (line 265) describes it correctly and does not mention the six integers.
Replacement: "The one learned policy is a small program, induced by the kernel's own search from six integers that describe a sub-problem, whose output is a clamped correction to that sub-problem's priority."

**71. COSMETIC. "A soundness gap the audit flagged" was inferred from the code and not shown.**

Line 825 (§7.1): "Pending cells also close a soundness gap the audit flagged in v2's dormant pruner, which treats two unresolved cells as equal."

What the source says. `search-engine.md:1038-1041`: "Caveat (INFERRED): the behaviour key treats two expressions that are both `:unresolved` on a row as equal there (`v2/enumerate.lisp:373-382`), which in recursive jobs with oracle tables could merge programs that differ off the table". The same report lists as not determined "Whether the dormant v2 pruning stays sound inside the full tree" (`search-engine.md:1078-1079`).

Replacement: "Pending cells also close a possible soundness gap in v2's dormant pruner. The search audit found, by reading the code and without a failing run, that the pruner treats two unresolved cells as equal."

### Outside the scope, noticed in passing

**72. INCONSISTENCY outside the slice, with §2.5. Line 1383 (§11.1).**
Sentence: "On some tasks, when used for lifting (3 of 8 unreachable tasks solved; 3 or 4 dearer); not when offered as plain operators"
Source: §2.5 (line 259) and `bootstrap-reflection.md:683-700`: there were 8 held-out tasks, 3 of which the kernel alone did not solve in 35 million units; lifting solved those 3. "3 of 8 unreachable tasks" reads as if 8 tasks were unreachable and 5 stayed so.
Replacement: "On some tasks, when used for lifting (of 8 held-out tasks, the 3 that the kernel alone could not reach were solved, one became cheaper, and 3 or 4 became dearer); not when offered as plain operators"

**73. INCONSISTENCY outside the scope (§10). Risk 11 points to a measurement that X4 no longer contains.**

Line 1353: "the retrieval measurement of §8.6, repeated on the kernel's tasks (X4); a budget account for every attempt (X9)"

X4 (line 1404) compares five arms: no guidance, types only, counts of past use, verb tables used to order, and verb tables used to filter. None retrieves similar problems.

Replacement: "the guidance ablation on the kernel's tasks (X4), which counts what each form of guidance costs when it is wrong; a budget account for every attempt (X9)"

**74. INCONSISTENCY outside the scope (§8.5). The kernel's "Stage A" is used with no gloss.**

Line 1133: "Stage A does not price cell by cell, and leaves one bit per model unpaid instead."

The Terms table (line 42) says of the three kinds of stage that "the text says which is meant". Here it does not, and Stage A of this plan is the store core. Line 1556 says the same thing correctly ("the kernel's first search phase").

Replacement: "The kernel's first search phase (which its code calls Stage A) does not price cell by cell, and leaves one bit per model unpaid instead."

**75. INCONSISTENCY outside the scope (Terms table, §1.1, §8.2, §11.2). Four smaller leftovers.**

Line 43: "*X1 to X9* | The experiments of §11.2, each with a gate fixed in advance." X8 (line 1408) reads "*Gate:* none; this is exploratory." Replacement: "The experiments of §11.2. Each but the exploratory X8 has a gate fixed in advance."

Line 57: "(the search tree has two or three nodes at every budget), exponential second (each tenfold of work buys about one AST node)". "Node" has two senses in one sentence, and §2.3 was reworded to avoid exactly this. Replacement: "(on the specs that stay unsolved, the tree of sub-problems is a root with one or two children at every budget), exponential second (each tenfold of work buys about one AST node)".

Lines 1060 and 1402: "these are the witnesses the kernel reaches by two other routes: its milestone code, on a full grid with a supplied witness language", and "no witness language beyond the operators in scope. *Gate:* the same witnesses and guards the milestone code finds". Here "witness" is the kernel's word for a solver's answer term (glossed once, at line 251), while §5.9 and §7.6 use "witness" for a map, substitution or pattern that relates two spaces. Replacement for line 1060: "these are the answer terms that the kernel reaches by two other routes: its milestone code, on a full grid with a supplied language of answer terms". Replacement for line 1402: "no language of answer terms beyond the operators in scope. *Gate:* the same answer terms and guards the milestone code finds".

Line 928: "Of the 158 hard-coded decisions, the 30 dedupe and memo guards become the class table and the problem memo; the 30 ordering rules become tables and counts; the 52 caps become budget accounts that defer rather than drop; the 51 pieces of domain knowledge become library entries or are deleted." §2.3 (line 219) has a fifth category, 6 accounting rules, which this mapping leaves out. Replacement: add "; the 6 accounting rules stay, as the ledger's own rules".

## The two gap logs, entry by entry

Every entry of `clarity-gaps-sec2.md` and `clarity-gaps-sec4-9.md` was opened at its cited lines. The entries below did not hold as written, or hold with a qualification. Every entry not listed here was confirmed: the sentence in the plan says what the cited source says.

| Gap log, entry | What the plan now says | Verdict |
|:--|:--|:--|
| sec2, A2 full grammar | "every operator the kernel has, including the library functions defined so far" | wrong; the cited lines do not say it (finding 1) |
| sec2, A6 (no entry was written) | "an *AST node* is 6–7 bits" | wrong; the figure is the gain per tenfold of work (finding 2) |
| sec2, A1 first search phase | "It has its own budget, separate from the job's" | right about the cap; the work is still charged to the job (finding 46) |
| sec2, A1 `02.3.md` line 30 | "when the budget of the kernel's first phase is raised as well" | only that one budget differs between the two runs (finding 29) |
| sec2, A2 spec | "one function that the bootstrap asks the kernel to synthesize" | fits the sixteen of §2.3 and not the 31 `:spec` entries of §2.5 (findings 17, 37) |
| sec2, A2 schema | "supplied for one function" | five schemas serve seven functions, and all five are offered to every job (finding 48) |
| sec2, A2 held-out-sound | "right on fresh inputs" | in the harness behind the 8, 10, 10, 10 it is one hand-written input per spec (finding 34) |
| sec2, A5 tree shape | "At every budget tried, this tree is a root with one or two children" | true of the four specs that stay unsolved; `argmax-corr` grew to 34 sub-problems (finding 22) |
| sec2, A11 closed arithmetic frames | "searched on their own rather than inside a synthesis job" | right, and equally true of the other three rows (finding 35) |
| sec2, C8 eight blockers | the opening gloss on reentrancy | the eight are right; the gloss has no source (finding 25) |
| sec2, A56 battery | "the algebra battery is the one that holds the laws" | it holds 12 of 15 (finding 55) |
| sec2, A23 | "Every step that turns a discovered law into something the search can use" | the definitions of star and fold motif are right; the heading was widened (finding 23) |
| sec2, A15 61, 19, 16 | the opening paragraph of §2.5 | the numbers are right; three phrases are not what the source says (finding 37) |
| sec2, A14 stand-in functions | "it made search 6.6× more expensive" | one spec of three (finding 24) |
| sec2, A14 "three or four" (PARTLY UNFILLED) | gives both counts and no reason | respected |
| sec2, A25 2,332 | "the nogoods and the features learned with them" | the ablation also removed the learned predictor (finding 53) |
| sec2, A19 node score | "the sum of two numbers" | five terms are added (finding 51) |
| sec2, A26 | "The record of which sub-problem came from which ... on the frame again as `pairs`, `anchors` and `edges`" | not what those three fields record (finding 6) |
| sec2, A56 "ten to twelve" | "Each of the document auditors' reports lists ten to twelve of them" | the four reports that have a list give 11, 10, 15 and 12 (finding 5) |
| sec2, A27 four occasions | "Each of plans 1 to 4 put it off" | quotations verbatim; the framing is a reading, and plan 4 did not defer (finding 42) |
| sec2, A29 "three errors" | "three were wrong" | one of the three could not be reproduced, which is weaker (finding 56) |
| sec2, A51 Appendix A line 8 (UNFILLED) | "The method has long precedent for numeric laws and for program slicing." | still asserted; it has a source the worker did not search, checked from abstracts only (finding 45) |
| sec4-9, A31 | "fitted a model to four published enumerators, and the model agrees with their measured sizes" | the model was built from other anchors and then checked against the four (finding 26) |
| sec4-9, A34 | the two quotations of the owner's note; the pointer to the revision notes | quotations verbatim; "supports this" and "both halves hold" have no source (finding 21); two cut facts are not in the notes (finding 59) |
| sec4-9, A34 "scheduled lowering", the hand-set value (UNFILLED) | removed | respected |
| sec4-9, A36 | the caption of the table in §4.7 | the bold cells match the paragraph; the stated rule does not fit two rows (finding 61) |
| sec4-9, A56 `04.3` | "have been done by one research group only" | true of conditional equalities; binders rest on one paper and one preprint (finding 33) |
| sec4-9, A37 the simpler length term (UNFILLED) | not named | respected |
| sec4-9, A38 "depth two" (UNFILLED) | "Experiments to depth two are your requirement from October (§2.8)." | the unfilled link is asserted by position (finding 38) |
| sec4-9, A41 | "It calls the matching problem "the quotienting-AU problem"" | quotations verbatim; the outline says that problem is a matching problem (finding 64) |
| sec4-9, A45 "graph walker", "graph isomorphism engine" (UNFILLED) | kept in quotation marks | still presented as quotations with no source (finding 60) |
| sec4-9, pointer note on `04.1` "(§6.4)" | kept | does not land (finding 11) |
| sec4-9, A49 `07.3` line 3 | "They differ only in the arguments passed to the recursive call" | "only" is not in the source (finding 28) |
| sec4-9, A49 "land on a known row", "every" (UNFILLED) | wording kept, "every" not written | respected |
| sec4-9, A7 | "applies only when that sub-term is provably total. Each rule is held to one of two contracts" | relaxed under one contract; the contract belongs to a call, not to a rule (finding 30) |
| sec4-9, A50 `09.0` line 15 | "operators with any number of arguments ... A pair of differing sub-terms" | wrong reading of "n-ary" (finding 7) |
| sec4-9, A50 fact-and-measure | "total when the arguments of every self-call decrease" | half of the criterion; the 50 lines cover the self-call test only (finding 40) |
| sec4-9, A50 `09.0` line 48 (UNFILLED) | "three of those prices are artifacts (§2.7)" | still asserted; §2.7 names two (finding 15) |
| sec4-9, A54 "one lineage" (UNFILLED) | used three times, not defined | still used; the obvious definition is wrong for Probe (finding 16) |
| sec4-9, A54 EURISKO | "by its author's own analysis ..." | the analysis is of AM and EURISKO, and the point about short programs is about AM (finding 68) |

## Changes against the pre-clarity version

Each table lists every number, quotation, evidence tag, file-and-line reference or claim that was dropped, changed or added in one slice, and says what supports the change. "A.." , "B.." and "C.." in the support columns are items of `clarity-review.md`; "gap log" is the entry of the same name in the two gap logs.

### §2 intro, §2.1, §2.2, §2.3

No number, quotation, evidence tag or file-and-line reference was dropped from any of the four files (`fc-c/A-tokdiff.py`). Everything below is a change or an addition.

| Section | Item | What changed | Supported by |
|:--|:--|:--|:--|
| 2 intro | pointer | "Appendix F" became "Appendix D" | re-lettering; Appendix D (line 1511) does list the audit reports |
| 2.1 | `pairs`, `anchors`, `edges` | one sentence each on what they record; the words "equal" and "distinct" | A4; gap log line 23; `core-repr.md:147-150`; `frame.lisp:20-24`; `enumerate.lisp:607-687`. Correct |
| 2.1 | pullback, decoder, lift | three definitions, the example `map`, pointer to §5.6 | A4; gap log lines 20-21; `frame.lisp:544-547` and `:1194-1201` (docstrings); `docs-origins.md:600-607`. Correct. §5.6 (line 553) says what the pointer promises |
| 2.1 | coupled constraints | "capped at 4 candidate models per slot and 256 combinations" became "keeps up to 4 candidate programs for each unknown and tries up to 256 combinations" | A4; gap log line 22; `synthesize.lisp:636-642`. Correct |
| 2.1 | terms not shared | Lisp shorthand unpacked; "which the kernel takes before it starts a resumable computation such as a search on it" added | A17; gap log line 24; `frame.lisp:96-98`; `enumerate.lisp:361`; `synthesize.lisp:177`; `core-repr.md:36-38`. Correct |
| 2.1 | `lift-frame` | sentence rewritten; reference `frame.lisp:1214-1256` and **[C]** moved next to the function name | A18. Wording correct; reference placement is finding 49 |
| 2.1 | ten rules | "ten hard-coded constructor rules" became "ten hard-coded rules, one for each constructor" | UNSUPPORTED. Finding 9 |
| 2.1 | solver | gloss "computes an unknown argument of an operator from its other arguments and its result" added | gap log line 32; `laws-library.md:150`, `:176`. Correct |
| 2.2 | host and object language | new paragraph | A3. No fact added |
| 2.2 | root kernel | "It describes the root kernel (v1, as distinct from the copy in `v2/`)" added | A56. Correct (`core-repr.md:386` and `:390` note what v2 adds) |
| 2.2 | `iota` | gloss "a primitive that produces the index list 0, 1, …" | A56; gap log line 29; `v2/vm.lisp:262`; `core-repr.md:746`. Correct |
| 2.2 | table, Fiber row | "one fold rule per constructor" became "one simplification rule per constructor" | A7. Supported as a renaming. (The row has the same looseness as finding 9: `tuple` has two preimage rules, `core-repr.md:390`.) |
| 2.2 | reentrancy | new paragraph, the list of eight, a second **[C]**, pointers to §2.3 and §2.6 | C8 and A51; gap log line 30. The eight are correct (see below). The opening gloss is UNSUPPORTED: finding 25 |
| 2.2 | "model" | "where the child's model is its candidate program" added | A16; gap log line 28. Correct for `compose-through` (`core-repr.md:401-406`) |
| 2.2 | four senses of "lift" | the four named, with functions | A16; gap log line 26. Each description matches the function's docstring (`frame.lisp:1194-1201`, `decompose.lisp:384-388`, `consolidate.lisp:603-606`, `consolidate.lisp:2081-2083` and `:1977`). The count of four rests on one cell of the report, `core-repr.md:387`, which names three "other things called lift" and says "four meanings of one word"; reading `lift-frame` as the fourth is the natural reading and the gap log says so |
| 2.2 | three senses of "fiber" | the three named | A16; gap log line 27; `core-repr.md:390` word for word. Correct |
| 2.3 | definitions | two new paragraphs: spec, work unit, recursion-synthesis job, flat search, first search phase, schema, whitelist, full grammar, held-out-sound, impostor, bit bound | A1, A2; gap log lines 5-18. Correct: work unit, recursion-synthesis job, flat search, first search phase (but see finding 46), whitelist, impostor, bit bound. Wrong: full grammar (finding 1). Caveat missing: held-out-sound (finding 34). Imprecise: spec (finding 17), schema (finding 48) |
| 2.3 | budget table | cells made into sentences; "350k" became "350,000 units"; "350M work" became "350 million units"; "bounded exhaustion" became "tried every program that its bounds allow"; "the depth and stage budgets" became "the depth limit of the search tree and the budgets of the kernel's internal search phases" | A2; gap log lines 17-18; `search-engine.md:328`, `:330`; logs `search-engine/exp-b-ma-noschemas-exhaust.out`, `exp-b-ma-allknobs.out`. Correct. Finding 50 concerns cells that did not change |
| 2.3 | Structure | "two or three nodes" became "a root with one or two children"; proposal generators defined; "the four stuck specs" became "the four specs that stay unsolved" | A5; gap log lines 33-34. The count is correct for those four; scope is finding 22; two phrases are finding 47 |
| 2.3 | Exponent | body bit and lane defined; "(6–7 bits)" became a statement about the size of an AST node; "are 132–259 bits" became "have bodies of 132–259 bits" | A6; gap log lines 35-37. Body bit, lane and "bodies" are correct (`empirical.md:302`, `:293-297`, `:318-320`). The AST-node sentence is UNSUPPORTED: finding 2 |
| 2.3 | the 260-bit answer | explanation added; `:lookahead-inductive`; "(search-engine report, §0)" | A10; gap log line 38; `search-engine.md:45-47`, `:325`; log `search-engine/exp-b-ma-schemas.out` (every sub-problem has "bound=130", "best-bits=260", the third sub-problem is ":LOOKAHEAD-INDUCTIVE"). Correct |
| 2.3 | "v1" | "the root kernel (v1, as distinct from the copy in `v2/`)"; "they give the same outputs on the spec's rows as a tree built earlier" added | A56; `empirical.md:57-59`. Correct |
| 2.3 | pruner | paragraph became a table; definitions of the pruner and the columnar evaluator; gloss on "closed arithmetic frames"; the reason a five-element field flatters pruning; "covered the same horizon" became "The same size bound was reached" | A11; gap log lines 39-43; `search-engine.md:1021`, `:1027-1035`; `docs-v2tex.md:738-739`; `empirical.md:203-204`. The figures and definitions are correct. The missing caveat is finding 35 |
| 2.3 | profile | list of four items unpacked; "weak hash table" became "hash table"; "which advances the search one work unit at a time" added | A13; gap log line 45; `empirical.md:504-506`, `:136-137`. Correct |
| 2.3 | non-monotone budget | "One Plan 8 probe solves at the default budget and fails at 1,000,000 with a larger Stage A budget" rewritten | A1, A9. "raised as well" is UNSUPPORTED: finding 29 |
| 2.3 | 158 decisions | "By class" became "five categories"; explanation of why the figures exceed 158; a definition of reflection with pointer to §7.4 | A12; gap log line 44; `search-engine.md:485-487`, `:690-691`. Correct. §7.4 (line 913) opens with the same definition |

### §2.4 to §2.9 and §3

| Section | Item dropped, changed or added | Supported by | Verdict |
|:--|:--|:--|:--|
| 2.4 | **[C]** moved from the end of the first paragraph to "it works" | A20 rewrite | supported |
| 2.4 | Added "The script defines four discovery jobs", "the field of the integers modulo 3", "All 187 are true on every input" | A20; `laws-library.md:41-52`, `:63`; `exp_algebra.log` (TOTAL proposed=187 kept-by-shape-filter=14) | supported |
| 2.4 | Added the parenthesis on eight batteries | gap log A56; `empirical.md:87` | supported; "holds the laws" inexact (finding 55) |
| 2.4 | "a law plus a chosen unknown port" changed to "which of the law's variables is the unknown" | A22 rewrite | inexact (finding 52) |
| 2.4 | Added "Entries are linked by typed edges, each from one entry to other entries or to function names" | gap log A22; `core-repr.md:189` | supported |
| 2.4 | Heading "Every conversion that carries algebra" changed to "Every step that turns a discovered law into something the search can use"; "four such steps" | A23 rewrite | UNSUPPORTED as widened (finding 23) |
| 2.4 | Added definitions of "star" and "fold motif", and of the fourth step | gap log A23; `consolidate.lisp:693-696`, `:799-831`, `:833-915`; `laws-library.md:194`, `:259` | supported; checked in the code |
| 2.4 | "VM errors are first-class outcomes" changed to "an error raised by the VM counts as an outcome like any value" | rewording only; `laws-library.md:125` | supported |
| 2.4 | Added the bullet on `target-sensitive-p`, with `laws.lisp:892-929`, `laws.lisp:948`, `tests/topology.lisp`, **[C]** | C8; gap log; code | supported (finding 54, cosmetic) |
| 2.5 | Added the opening paragraph: 61, 31, 19, 16, "two guards and one solver", ten saved, six seeds | A15; gap log; `bootstrap-reflection.md:158`, `:121`, `:266-267`, `:401-402` | numbers supported; three phrases not (finding 37) |
| 2.5 | Dropped "operational" (of the 61 entries) | none | UNSUPPORTED; replaced by "that the search can use" (finding 37) |
| 2.5 | Added "answer term ... (the kernel's code calls it a witness)" and the definition of an atom, with a literal counting two | A15; gap log; `scripts/bootstrap-reflection/leaf-bits.lisp:9-17`; check: `(at (best-shift X0 X1 0) 1)` gives 8 | supported |
| 2.5 | "found at a leaf" changed to "found by enumeration at a leaf of the search tree"; "(§2.1)" added | A15; `bootstrap-reflection.md:325-327` | supported |
| 2.5 | "In 9 of 10 function specs" changed to "For 9 of the 10 saved functions" | `bootstrap-reflection.md:350-351` | supported |
| 2.5 | "defined the same 21 entries" changed to "defined 21 of these entries"; "Before the bootstrap existed" added | A15; `bootstrap-reflection.md:417-431`, `:366` | supported |
| 2.5 | Added the gloss of anti-unification; "three that map a list and three that reduce one"; "the seeds come three to a signature"; "type signature" | A24, A56; `bootstrap-reflection.md:256-257`, `:753-755`; `abstraction.lisp:233`, `:413-420` | supported |
| 2.5 | "full generic grammar" changed to "full grammar" | defined in §2.3 | supported |
| 2.5 | Added the definition of "used for lifting", naming `:map`, `:scan`, `:foldl` | A14; gap log; `proposals.lisp:152-160` (docstring of `library-decompositions`); `bootstrap-reflection.md:683-700` | supported |
| 2.5 | Added "the table of the bootstrap-reflection report shows four, and its summary counts three" | A14; `factcheck.md:144`; table at `bootstrap-reflection.md:697-700` (four rows dearer: 2.2×, 1.7×, 2.3×, 3.0×) | supported; no reason is asserted for the difference, as the gap log's PARTLY UNFILLED entry requires |
| 2.5 | **[M]** moved from the end of the paragraph to "The test was 8 held-out tasks"; "cost 6.6×" changed to "it made search 6.6× more expensive"; "whose bodies were dummies" added | A14; `bootstrap-reflection.md:742-744` | dummy bodies supported; generalization and the lost tag are finding 24 |
| 2.6 | Added definitions of reflection, a message, and the trace | A25; `search-engine.md:105`, `:821-829` | supported |
| 2.6 | "clamped delta to node priority" changed to "a correction, clamped to a fixed range, to the priority of each sub-problem"; "with one to five sub-problems each" added | gap log; `search-engine.md:851-853`; `bootstrap-reflection.md:76` | supported |
| 2.6 | Added the paraphrase of the `plan_v2b.md` claim, the definition of a nogood, "out of the 40,155"; **[M]** moved to the first sentence | A25; `docs-v2b.md:20`, `:329-337`; `search-engine.md:874-883` | supported (finding 53, cosmetic) |
| 2.7 | Added the definition of a residual | A19; `docs-origins.md:626-628` | supported; agrees with the Terms table |
| 2.7 | Dropped the eight internal names of the residual representations; pointer to core-repr §1.4 added | A19 | supported; `core-repr.md:163-174` has all eight with file and line |
| 2.7 | Added the four cases of metric pullback | A19; `core-repr.md:501-505`; `frame.lisp:508-542` (docstring and four `cond` clauses) | supported; checked in the code |
| 2.7 | "Node scores add ..." changed to "is the sum of two numbers" | A19 rewrite | inexact (finding 51) |
| 2.7 | Added 'Plan 7 stated this rule and called the price "one step deep" (`plan7/plan7.md` L437); the code is `synthesize.lisp:447-457`' | A52, B1; `AB.0.md` row 21; `plan7/plan7.md:437` verbatim | supported |
| 2.7 | "default Stage A budget of 2,000" changed to "the default budget of the kernel's first phase is 2,000" | A1; `search-engine.md:57-58`, `:533` | supported |
| 2.7 | Added the gloss of the metric decoder | gap log; `core-repr.md:53-55` | supported (tag bits omitted, harmless) |
| 2.8 | "(the reports list ten to twelve each ...)" changed to "Each of the document auditors' reports lists ten to twelve of them" | A56 | UNSUPPORTED (finding 5) |
| 2.8 | Item 1 rewritten in sentences | A26; `docs-origins.md:474-483`, `:534-539` | first half supported; last two sentences are finding 6 |
| 2.8 | Dropped "because learned knowledge never reduced the number of candidates enumerated"; "for the reason given in §2.4" added | B7 | supported; §2.4 (line 229) gives the reason |
| 2.8 | Added the paragraph on the four occasions, with five quotations and "(docs-origins report, part (d))" | A27; `docs-origins.md:809-824`; quotations checked in `deprecated/plan.md`, `plan2.md`, `plan3.md`, `plan4.md` | quotations verbatim; framing is finding 42 |
| 2.8 | "(locations in Appendix B)" replaced by a location on each of the twelve nuggets | B1; `AB.0.md` | supported; all twelve locations match `AB.0.md`, and I opened plan 2 §1.1, §1.2, §1.8, §4.4 and L835; plan 1 L579; plan 5 §2.3; plan 7 L156, L379, L437, L641; results L730-733; plan 8 §6.7 (L306) |
| 2.8 | Added the counting identity in words; the three cases of a residual made exact; "D is the domain" | A28; `deprecated/plan2.md:343`, `:349-351`, `:361-373` | supported |
| 2.8 | Added the sentence on plan 5 (`deprecated/plan5.md` §2.3) | A52; `AB.0.md` row 15; `deprecated/plan5.md:157-164` | supported |
| 2.8 | Added the two laws that make a solver | A28; `plan7/plan7.md:379` | supported |
| 2.8 | Added the reason compression does not reveal a law | A28; `deprecated/plan2.md:997-1009` (2,447 bits more) | supported |
| 2.8 | "ranked 66th of 2,661 by magnitude" changed to "Among 2,661 candidate lifts, the correct one ranked 66th by the size of its residual" | gap log; `deprecated/plan.md:579` | supported |
| 2.8 | Dropped "True as stated" (plan 8 nugget) | B1 | supported |
| 2.8 | Added the closing sentence pointing to the `docs-*.md` reports; the nine unused rows of the old Appendix B and its "Code" column are gone from the plan | C1, B1 | supported; I found the nine ideas in `docs-plan6-results.md`, `docs-plan7-arch.md` and `docs-plan8-9.md` |
| 2.9 | Dropped "six academic imports and ten unverified novelties", "v2.1 to v2.4 in four hours", "21 of the 40 mechanisms", "headline numbers have no artifact" | C3 | supported as a cut; the replacement word "largely" is finding 31 |
| 2.9 | "has no imported risk" changed to "depends on nothing unverified" | C3; `docs-v2b.md:18` ("0 (A)/(X) in Stage 0") | supported |
| 2.9 | Dropped "`:tabulate`", "(`v2/ast.lisp:1096` against `:673`)", "Ten exported symbols are defined nowhere"; "(Appendix D)" added | B8 | supported; both facts are in Appendix D, lines 1551 and 1552 |
| 2.9 | Dropped "Complexity rose." | C3, A29 | supported |
| 2.9 | "The Stage 0 survival audit gives the identical result on all 64 runs" changed to "It also changes no outcome: v2's Stage 0 audit, which runs 64 syntheses, gives the same result on all 64 with the Stage 1 code as without it" | A29; `docs-v2tex.md:742-743` | supported |
| 2.9 | Dropped the list of seven things to keep, and "(all cheap, all grounded in something measured here)"; pointer to §9 added | B3, B10 | supported; six of the seven are in §9 (lines 1322 to 1325) and the seventh is Appendix B |
| 2.9 | "Both plans" changed to "`plan_v2.md` and `plan_v2b.md`"; the four gaps written as sentences | A29; `docs-v2b.md:410-415` | supported |
| 2.9 | The highlighted sentence shortened to "only through verified maps"; "Section 6" changed to "Section 6.6" | B9 | supported (see the pointer check below) |
| 3 | "a two-node tree per job and a write-only message list" changed to "only as a search tree with a root and one or two children (§2.3), and as a list of messages that no decision reads (§2.6)" | A5 | partly (finding 14) |

No evidence tag was dropped except the one in finding 24. No file-and-line reference was dropped without its fact moving to Appendix D.

### §4 and §5

"Review" items are those of `clarity-review.md`. "Gap" entries are those of `clarity-gaps-sec4-9.md`.

| File | Change | Kind | Supported by |
|:--|:--|:--|:--|
| 04.1 | "8, 10, 10, 10 of 16 over three decades" became "only two more of the sixteen specs" | numbers dropped | Review B5. The figures remain in §2.3. Supported. |
| 04.1 | "the search tree stayed at two nodes" became "stayed a root with one or two children" | claim changed | Review A5, and `empirical.md:293-297` (2 or 3 nodes). Supported; it corrects the older wording. |
| 04.1 | "4.5 decades, so five to nine nodes" became "4.5 tenfold steps, so it adds between five and nine nodes to the largest program reached" | reworded | Review A31. Supported. |
| 04.1 | added "agrees with their measured sizes" | claim added | Gap A31 (`lit-search.md:641`). Supported, but "fitted" was kept: finding 26. |
| 04.1 | added "which is about 7,700 CPU-hours" | number added | Gap A48 (`lit-discrete.md:32`; 5 × 24 × 64 = 7,680). Supported. |
| 04.1 | "every record" became "the kernel's records, which are its trace, the syntax it retains, and its list of sub-problems" | definition added | Gap A32 (`search-engine.md:1053-1054`). Supported. |
| 04.1 | pointer "(§6.4)" kept | pointer | UNSUPPORTED: finding 11. |
| 04.2 | the parenthesis on what the auditor checked became **[L, from memory]** and **[L, abstract only]** | tags added | Review B4; `lit-discrete.md:187`, `:189`. Supported. |
| 04.2 | added "(§2.8)" | pointer added | Review B1. Lands (line 306). |
| 04.3 | added "that is, until no law adds a new equality" | definition added | Review A56. Supported. |
| 04.3 | "are single-group research" became "have been done by one research group only" | claim reworded | Gap A56. Partly supported: finding 33. |
| 04.3 | "which the auditor verified from abstracts" became **[L, abstract only]** | tag added | Review B4; `lit-discrete.md:29`. Supported. |
| 04.4 | two quotations dropped ("No column is designated as input or output"; "via the exchange of input and outputs") in favour of "(§2.8)" | quotations dropped | Review B1. Both remain at line 300. Supported. |
| 04.5 | the three results separated; superposition defined | reworded | Review A33. Supported. |
| 04.5 | "verified against the paper" dropped; **[L]** kept | tag text dropped | Review B4. Supported. |
| 04.5 | "n neurons compute at most about n² features" dropped | number dropped | Review A33 and B11. Appendix C keeps the bound. Supported. |
| 04.5 | "a broad class of problems" became "a broad category of problems" | reworded | Review A12 (keeps "class" for the store's term). Supported. |
| 04.5 | dropped: "small pairwise energy"; "fitting it takes milliseconds"; "one hand-set value already solves every Sudoku puzzle, and three every maze"; the Triton kernels; "2.0 × 10⁹ FLOPs per Sudoku"; "scheduled lowering" | numbers and claims dropped | Review C2. Supported as a cut, but two of the facts are in no other place: finding 59. |
| 04.5 | "bears on this" became "supports this" | claim strengthened | Review C2's suggested text; no source. UNSUPPORTED: finding 21. |
| 04.5 | two quotations of the owner's note added | quotations added | Gap A34. Verbatim against the annotated PDF. Supported as quotations; what the plan then says of them is finding 21. |
| 04.5 | pointer to `plan_v2c_audit/revision-notes.md` added | pointer added | Gap A34. The draft exists and has the row (line 117). |
| 04.5 | Take: "feature vectors as an index over the exact store (§6.4)" became "features, which here are the labels of §6.2, as a layer over the exact store that ranks and filters (§6.4, §6.6)" | claim and pointers changed | Review A55. Lands. "Retrieval" left behind: finding 19. |
| 04.6 | **[L, abstract only]** added for FlashMeta's deployment | tag added | Gap B4; `lit-discrete.md:31`. Supported. |
| 04.6 | "its authors" became "The relational interpreters of miniKanren ... the authors of a 2025 paper on them" | attribution added | Gap A35 (`lit-discrete.md:238-241`). Supported. |
| 04.6 | "pullback is 37 sound lines" became "already sound, and small" | number dropped | Review B12. Stays in §2.1 and §9. Supported. |
| 04.6 | "(§5.4, measured in §8)" became "(§5.3, §5.4; measured in §8)" | pointer added | Review A37. Lands. |
| 04.6 | owner's phrase on reentrancy quoted; the tower sentence expanded | quotation added | Gap A35. Verbatim (`plan_v2_prompt.md:5`). Supported. |
| 04.7 | heading changed; caption added | definitions added | Gap A36 (`lit-discrete.md:543` for "(2026)"). Supported; finding 61 on the rule for bold. |
| 05.1 | "As §4.2 observed" | pointer added | Review B13. Lands. |
| 05.3 | "This plan calls the check the *dependency test*"; gloss of `tabulate` with "(§7.1)" | definitions added | Review A37. Both match the Terms table and line 827. Supported. |
| 05.4 | "n is the number of rows"; definition of `select` | definitions added | Gap A38. `proto/tg-probe.lisp:239`; `proto.md:94`. Supported. |
| 05.4 | "`plan_v2b.md` (its §7.3) listed six moves on its store" | attribution added | Gap A38 (`docs-v2tex.md:617`; `plan_v2b.md:469`; the note itself in `plan_v2b_annotated.pdf`). Supported. |
| 05.4 | plain-words definition of anti-unification | definition added | Gap A56 (`lit-discrete.md:342`). Supported. |
| 05.4 | "a single paper the auditor could read only in summary" became **[L, summary only]** | tag added | Review B4; `lit-discrete.md:380`. Supported. |
| 05.4 | "same signature" became "same type signature" | reworded | Gap A24; `anti-unify` compares `operator-type` (`unify.lisp:36-58` at HEAD). Supported. |
| 05.4 | "took one pattern from five holes to two" became "gave a pattern with fewer holes (§2.8)" | numbers dropped | Review B1. Line 305 keeps 5 and 2. Supported. |
| 05.4 | "the last of the four stages in which this plan is to be built (§11.3)" | gloss added | Review A1. Lands. |
| 05.4 | "Experiments to depth two are your requirement from October (§2.8)" | claim added | Gap A38 is UNFILLED. Finding 38. |
| 05.5 | the Tested grade written out; "which §6.2 calls verb tables ... (§6.4)" | reworded, pointers | Review A39 and A55. Both land (lines 660, 724). |
| 05.5 | "of §2.3, in which a program fits the spec's rows and is wrong"; definition of probe space | location and definition added | Gap A9. Matches line 192, line 932 and the Terms table. Supported. |
| 05.5 | quotation "the unresolved information is the membership of each input in its valid subset" dropped for "(§2.8)" | quotation dropped | Review B1. Line 303 keeps it. Supported. |
| 05.6 | "in 37 lines" dropped | number dropped | Review B12. Supported. |
| 05.6 | added "(§2.1; `frame.lisp:544`, `unify.lisp:103`), and plan 3 already described lift as a pullback of this kind (`deprecated/plan3.md` §3)" | references and claim added | From the former Appendix B row (review B1 and C1). No gap-log entry. UNSUPPORTED in part: finding 4. |
| 05.8 | "The same review" became "The outside review also" | attribution fixed | Gap A40 (`plan_v2c_audit.md:31`). Supported. |
| 05.8 | "keeps laws by use" became "keeps a law only when something reads it"; "Experiment X1 (§11.2), which runs law discovery on the new store" | reworded, gloss | Review A40. Matches lines 1278 and 1401. Supported. |
| 05.9 | definition of *witness* | definition added | Review A8. Supported. |
| 05.9 | "the outside review calls this "probe evaluation"" | attribution added | Gap A56 (`plan_v2c_audit.md:39`). Supported. |
| 05.9 | "a signature that flows" became "a colour that flows" | reworded | Review A8 (one sense per word). Supported. |
| 05.9 | "In the version measured it is 65 lines on top of 36 for refinement" dropped from the backtracking bullet | numbers dropped | Review B11. Line 623 keeps both; they match `cross-space/xs-m3.lisp` lines 37-72 and 73-137. Supported. |
| 05.9 | "Symmetric structures matched against their own copy needed choices, and none had to be undone." dropped | claim dropped | Review B11. Line 1186 keeps it. Supported. |
| 05.9 | "Plan 2 recorded this in October" became "the finding that plan 2 recorded in October holds (§2.8)" | pointer added | Review B1. Lands (line 306); plan 2 was committed on 19 October. Supported. |
| 05.9 | the aligner paragraph split; *selective* defined; "the `gather` rule (§7.2)" | definition, pointer | Gap A43. Lands (lines 855, 865). Supported. |
| 05.9 | "the quotienting-AU problem" quoted | quotation added | Gap A41. Verbatim (`prompt4.md:170`). Finding 64 on the verb. |
| 05.9 | "(`plan7/plan7-library.md` §2.2.3)" | reference added | No gap-log entry. Checked: item 3 of §2.2, lines 56-57; never built (`docs-plan7-arch.md:200`, `:454`). Supported. |
| 05.9 | four signals numbered; "These first two are the two resolutions of §6.2, coarse and full" | claim made explicit | Gap A42. Matches lines 655 to 660. Supported; finding 43 on the fourth. |
| 05.9 | "The compromise" became "How the two kinds of work are budgeted"; "(X9)" became "(experiment X9, §11.2)" | reworded | Review A45, A40. Lands. |
| 05.9 | "a product of two automata and quadratic in the corpus; this is deferred to Stage D" became "which §5.4 prices and defers to Stage D (§11.3)" | claim replaced by pointer | Review B11. Lines 527 and 529 carry it. Supported. |
| 05.9 | "accepts an abstraction only when it shortens the total description" | gloss added | Gap A44. `abstraction.lisp:385-386` at HEAD: "only when it strictly improves description length above MIN-GAIN", default 0. Supported. |
| 05.9 | stages paragraph: "as context selection" became "There the kernel has to select which library entries go into each problem's grammar" | claim added | Review A45. UNSUPPORTED by the new §6: finding 12. The other additions there (four stages, "the store core", "adds requirements with holes and spaces with maps") match §11.3. |

Files 04.0, 05.0, 05.2 and 05.7 changed in wording only, or not at all.

### §7.1, §7.3, §9 and Appendices A, B, C

"Supported" names the clarity-review item or gap-log entry. Nothing in this slice lost a number or an evidence tag except where a row says so.

| Section | What changed | Kind | Supported by | Verdict |
|:--|:--|:--|:--|:--|
| §7.1 l.817 | Opening sentence split into four properties; "its code is re-derived for the new opcodes (§9)" added | added claim, pointer | A46; §9 table row "Metered, resumable evaluator ... as design" | supported |
| §7.1 l.827 | Glosses for `length`, `at`, `fold`, `scan`; heading reworded | added definitions | A47 | supported (they define proposed primitives and agree with the §7.2 table) |
| §7.1 l.831 | "Stage D, the last of the four stages ... (§11.3)" | added pointer | A1 | supported |
| §7.1 l.833 | λ² and DreamCoder named; **[L]** moved to the first sentence; "(§4.1)" added | added names, tag moved | A48; gap log A48 (`lit-discrete.md:32`) | supported; 0.43 s and 7,700 CPU-hours unchanged and correct |
| §7.3 l.899 | "which the bootstrap supplies (`bootstrap/recursion-schemas.lisp`)"; "bind the value of the recursive call as a new input of the child problem"; "They differ only in the arguments ..." | added claims, file reference | A49; gap log A49 (`search-engine.md:1064-1067`, `:729-739`) | supported except the word "only" (finding 28) |
| §7.3 l.902 | Keep-column defined | added definition | A49 | supported (agrees with line 1010) |
| §7.3 l.907 | Two ranking tests spelled out; "about 50 portable lines" became "about 50 lines that can be carried over" | reworded | A49; UNFILLED for "land on a known row", wording kept | supported; the unfilled reading is not asserted |
| §7.3 l.909 | Definitions of "closed under the recursive call" and "angelic execution"; "not all of these were solved (§8.5 gives the outcome of each)"; "Cases 1–4 are different" | added definitions and claim | A49; gap log A49 (`lit-search.md:240-241`, `lit-search-appendix-enum.md:203`) | supported; "every" was not written, as the log says |
| §9 l.1289 | Dropped: "Line counts are the auditors', from the root tree; where two auditors counted the same code differently, both figures are given." | dropped sentence | C7 (optional) | supported; leaves "215–315" unexplained (finding 67a) |
| §9 l.1299 | "n-ary, typed, shared holes, operator holes" expanded; "(§5.4)" added | changed claim | A50; gap log A50 | NOT supported as written (finding 7) |
| §9 l.1300 | "fixed-point save and load" became "Saving, loading and saving again gives equal entries" | reworded | A50; gap log (`bootstrap-reflection.md:785-786`) | supported; "entries", not "file", matches the source |
| §9 l.1305 | Codec cell expanded: encoder as a counter; decoder rejects non-canonical codes; "you have said that the present prices need not be kept" | added claims | A50; gap log (`core-repr.md:614`, `:74`; prompt line 15) | supported; `codec.lisp:10` and `:205` confirm |
| §9 l.1318 | "Definedness-preserving folding" renamed and explained; note that "folding" is not the primitive `fold` | added definition | A7; gap log A7 (`core-repr.md:562-564`, `:312-313`) | supported in substance; two details wrong (finding 30) |
| §9 l.1319 | Fact-and-measure scheme and least-fixed-point discipline defined; `knowledge.lisp:514-545` added | added definitions, file reference | A50; gap log A50 (`core-repr.md:297-308`, `:619`, `:289-290`) | least-fixed-point sentence correct (`knowledge.lisp:514-518`); fact-and-measure sentence incomplete (finding 40) |
| §9 l.1322-1325 | "From v2" bullet became three sub-bullets; lift against split, the replay guard and "each row of the root problem is priced exactly once" moved in from §2.9; definitions of difference facts, `gather`, `evolve` added | moved and added | B3; A30; gap log (`docs-v2tex.md:86`, `:83`, `:87`, `:841`, `:748-756`) | supported; every item of the old §2.9 list is present |
| §2.9 → §9 | Lost in the move: the parenthesis "(all cheap, all grounded in something measured here)" and the bullet "the list of mechanisms those audits rejected, in Appendix D, which this plan does not re-import" | dropped | B10 for the bullet; nothing for the parenthesis | acceptable: the parenthesis was the docs-v2tex auditor's own judgement (`docs-v2tex.md:824`), not a measurement |
| §9 l.1327 | "fold soundness under both contracts" became "soundness of requirement simplification under both contracts" | reworded | A7 | supported |
| §9 l.1333 | "the Stage 1 additions" became "v2's Stage 1 additions" | reworded | A1 | supported |
| §9 l.1335 | "three of them are artifacts" reworded, count kept | unchanged claim | A50, UNFILLED | not supported (finding 15) |
| App. A l.1435 | Cut: the two sentences after "As intuition, yes." | dropped | B2 | supported; §5.4 carries them |
| App. A l.1437 | "See" cell gained §5.3 and §6.1 | added pointers | A51, C8 | supported; both land |
| App. A l.1438 | "Depth one exists and works; a script limits it." rewritten | reworded | A51 | supported by line 225 |
| App. A l.1440 | "A row is a tuple is an n-ary edge" split | reworded | A51 | supported |
| App. A l.1442 | List of six blockers cut, "listed in §2.2" | dropped | A51, C8 | supported; §2.2 lines 164-171 list eight |
| App. A l.1444 | Residual answer rewritten | reworded, added "(§2.7)", "(§6.3)" | A51; gap log `clarity-gaps-sec2.md:93` | supported by line 690; narrows three causes to one (finding 66) |
| App. A l.1446 | Cut: "A flat space buys storage, not computation, and this library has no storage pressure. Use one flat signature space as an index." | dropped | B2 | supported; also removes a stale term |
| App. A l.1449 | Cut: "Three gaps: the fault is an unstructured string; search discards it; no opcode observes it. Timeouts have no precedent."; `plan7/plan7-recursion.md` L97 added to "See" | dropped, added reference | B2; gap log `clarity-gaps-sec2.md:87` | supported; the line number is right |
| App. A l.1452 | Cut: the across-spaces and e-graph sentences | dropped | B2 | allowed by B2, but changes the answer (finding 36) |
| App. A l.1453 | Cut: the three reasons distributivity was missed, now "when asked directly" | dropped | B2 | supported; line 227 carries them, including "85 times" |
| App. A l.1454 | "See" cell gained §9 | added pointer | B3 | supported in part (see the table below) |
| App. B l.1457 | Re-lettered D to B | relabel | brief | correct |
| App. B l.1459 | Cut: "Two further proposals are close relatives of rejected items ...: random-walk proximity and count-based triggers (§6.4)." | dropped | A53 | supported; neither phrase occurs in the frozen copy. See finding 39 for a relative that is still there |
| App. B l.1474 | "Host probes" became "Hand-written recognizers in host code" | reworded | A9; gap log (`docs-v2tex.md:295`) | supported |
| App. B end | Cut: "What survived every pass unchanged is short: columnar tables, a behaviour table, a single record for all knowledge, the Stage 0 fixes, and the audit of the kernel." | dropped | B3 | supported; note that "a single record for all knowledge" and "the audit of the kernel" as survivors (`docs-v2tex.md:321-324`) are now stated nowhere |
| App. C l.1481 | Re-lettered E to C | relabel | brief | correct |
| App. C l.1483 | Verification gaps moved up from below the table | moved | A54, B4 | supported (`lit-search.md:737`, `:442`, `:485`) |
| App. C | Cut: "The three rows on abstract values were added in the revision and checked against the papers' text (`lit-abstraction.md`); a 1977 paper by Knuth that the outside review also cites could not be fetched." | dropped | C4 | supported; the caveat survives in the draft `revision-notes.md` line 173, whose "See" cell still says "§6.6, Appendix E" and should say "§6.7, Appendix C" |
| App. C l.1496 | Myth cell expanded: "raised one task from 0.07 s to 128 s" | reworded | A54; gap log (`lit-search-appendix-enum.md:160`) | supported: `list_compress` 0.073 s to 128.3 s |
| App. C l.1499 | Role "signatures" became "property sets (§8.6)" | changed | A55 | pointer right, term not the one §8.6 uses (finding 16a) |
| App. C l.1505 | Role now "(§6.7)" | changed pointer | A54, A55 | lands (line 798) |
| App. C l.1506, 1507 | "(§6.5)" added; "(§6.4)" became "(§6.5)" | changed pointers | A55 | both land (lines 741-771) |
| App. C l.1509 | EURISKO cell expanded | reworded | A54; gap log (`lit-discrete.md:563`) | supported; see finding 68b |

## Cross-references from the scope to §6, §7, §8, §10, §11 and the appendices

"Lands" means that the target, as it stands in the frozen copy, says what the pointing sentence promises. The pointers inside the scope (to §2, §3, §4, §5 and §9) were checked slice by slice as well, and all of them land except where a finding says otherwise.

| Line | Pointer | What the sentence promises | Target | Verdict |
|--:|:--|:--|:--|:--|
| 122 | Appendix D | the audit reports are listed there | L1511-1542 | lands |
| 177 | §11.3 | Stage A of this plan is defined there | L1411-1420 | lands |
| 219 | §7.4 | reflection: the kernel reads the record of its searches and makes these decisions | L913, L928 | lands (L928 maps four of the five categories and leaves out the 6 accounting rules: finding 75) |
| 317 | Appendix D | the main new opcode of v2's Stage 1 fails in the form its own proposals build | L1552 | lands in part: L1552 gives the failing form (`(tabulate n F)` with `F` a code variable) and does not say that this is the main new opcode or that the proposals build that form |
| 328 | Section 6.6 | the answer to "how, though?" on comparing spaces "only through verified maps" | L777-781 | lands |
| 362 | §6.4 | the choice of a small grammar for each problem, as the main control problem | L698-737 | DOES NOT LAND (finding 11) |
| 402 | §6.2 | labels are defined there | L653 | lands |
| 402 | §6.4, §6.6 | a flat layer over the exact store that ranks and filters | L716-720, L792 | lands (§6.6 calls them "the labels of §6.4"; §4.5 and §1.5 say "the labels of §6.2", where they are defined) |
| 410 | §8 | inverses from an operator's table are measured | §8.2, L1043-1066 | lands |
| 412 | §7.1 | a single evaluator whose terms may mention terms, spaces and requirements | L839 | lands in part: L839 says the store's operations are programs over sequences and that their records are data; it does not mention requirements |
| 494 | §7.1 | `tabulate` builds a sequence from a length and a function of position | L827 | lands |
| 496 | §8.1 | a quarter of a second; about five seconds; twelve examples; not robust | L1017, L1027, L1006, L1036-1039 | lands, but §8.5 now has the result on the spec's eight examples (finding 44) |
| 500 | §8.1 | `select` is how the prototype writes `filter` | L1024 | lands |
| 525 | §8.5 | the kernel's `anti-unify` gives one shared hole | L1135 | lands |
| 529, 623, 831 | Stage D, §11.3 | anti-unification over classes and learned containers are in the last stage | L1418 | lands for abstraction over classes; learned containers are not named in the Stage D row, and L831 says nothing depends on them |
| 531 | §10 | depth-two algebra has no precedent | L1362 | lands |
| 540 | §6.2, §6.4 | verb tables are named in §6.2 and are tested knowledge in §6.4 | L660, L724 | lands (finding 18 on the two definitions of "tested") |
| 545 | §8.1 | the prototype returned its one impostor as an answer | L1037 | lands on §8.1; §8.5 has more (finding 20) |
| 555, 603 | §7.2 | each construct splits the requirement; the one move | L845-861 | lands |
| 563 | §7.4 | the derivation space and its columns | L913 | lands |
| 571 | §8.8 | a law is kept only when something reads it | L1278 | lands |
| 571 | X1, §11.2 | X1 runs law discovery on the new store and measures what pruning by laws would add | L1401 | lands |
| 579 | §8 | the first two of the plan's own mechanisms are measured on a prototype | §8.1, §8.2 | lands |
| 596, 617 | §6.2, §6.1 | quotients and labels; the cost of one column given another; the two resolutions | L653-660, L637-639 | lands |
| 607 | §8.6 | negation carries `max` to `min` | L1172 | lands |
| 609 | §8.6 | backtracking was needed for regular structures without symmetry and to reject look-alikes | L1182-1186 | lands |
| 613 | §7.2 (twice) | selection maps output positions to input positions; the index sets of the `gather` row | L855, L865 | lands |
| 619 | §8.6 | same form at three times chance; operators not found; no more work saved than a control | L1145-1162 | lands |
| 619 | §8.7, §6.4 | each candidate is tested against the target's labels before evaluation | L1192, L716-720 | lands |
| 621 | §8.6 | a pair of 30-row structures took 257,214 backtracks | L1184 | lands |
| 621 | §9 | the reserve rule, three parts tentative to one part fallback | L1307 | lands |
| 621 | X9, §11.2 | the share of an hour spent across spaces can be measured and adjusted | L1409 | lands in part: X9 puts each attempt on its own budget account; it does not say that the share is measured or adjusted |
| 625 | §11.3, §6.4, X9 | the contents of Stages A to D | L1413-1418, L1409 | lands, except that Stage C does not "select which library entries go into each problem's grammar" (finding 12) |
| 823 | §7.5 | faults kept as data train guards and totality | L936, L954 | lands |
| 829 | §8 | which terms §8 found, and that the higher-order `filter` was not attempted | L1014-1028, L1111 | CONTRADICTED for `filter` (finding 3) |
| 833 | §4.1 | 7,700 CPU-hours | L358 | lands |
| 837 | §6.4 | a name is priced by its share of uses in accepted solutions | L737 | CONTRADICTED (finding 10) |
| 839 | §7.4 | the records of the store's operations | L913 | lands |
| 904 | §8.5 | collect under each aggregate in scope | L1122 | lands |
| 905 | §8 | step functions enumerated by class are measured | L1038 | lands |
| 909 | §8.1, §8.5 | what was run on which rows | L1027-1028, L1107-1116 | CONTRADICTED for `filter`, and the list of five specs is not the list that was run (finding 3) |
| 1304, 1318 | §7.1 | the unit of evaluation changes; `fold` is a sequence primitive | L821, L827 | lands |
| 1325 | §7.2 | the existence half of an inverse's guard needs no search | L867 | lands |
| 1325 | Appendix B | no refund of bits for symmetry | L1468 | lands |
| 1333 | §2.9 | the rest of v2's Stage 1 should be mined, not continued | L317-319 | lands for the reasons; §2.9 no longer has the list and points back to §9 |
| 1335 | §2.7 | three prices are artifacts | L277-278 | two are named (finding 15) |
| 1437 | §2.4, §5.3, §6.1, §7.5 | the dependency test; `target-sensitive-p`; holding all but a few constant | L234, L482, L647, L949 | lands; the "long precedent" sentence is in none of the four (finding 45) |
| 1438 | §2.4, §5.4, §10 | depth-one experiments exist; spaces whose cells hold terms; no precedent for the loop | L223-225, L531, L1361-1362 | lands |
| 1439 | §2.4, §5.5 | guards from agreement masks; a guarded law is a class on a sub-space | L232, L547 | lands |
| 1440 | §4.2, §5.2 | a row is a tuple and an n-ary edge; store the factorization | L370, L467 | lands |
| 1441, 1442 | §2.2 | the operation table; the eight blockers | L144-172 | lands (the table has no row for tuples; the statement about tuples is in the core-repr report) |
| 1443 | §2.3 | 30 of 158 decisions are dedupe or memo guards | L219 | lands |
| 1444 | §2.7, §6.3 | eight representations; the two exceptions to ambient pricing | L273, L690 | lands (finding 66: §6.3 gives three causes of the clunkiness, the row gives one) |
| 1445 | §2.6 | the one learned policy learned the constant 0 | L265 | lands; "on six integers" is not in §2.6 (finding 70) |
| 1446 | §4.5, §6.6 | flat versus nested is not a question of what can be represented | L396, L792 | lands |
| 1447 | §2.2, §2.4, §2.7 | one concept several times; fourteen kinds, one struct; eight residual forms | L173, L230, L273 | lands |
| 1448, 1450, 1453 | §2.4, §2.5 | 2.5%; nothing initiates discovery; the answer key; 8 atoms; distributivity | L242, L233, L254, L251, L227 | lands |
| 1449 | §7.1, §7.5 | a crash and a cutoff are data; totality gates only rewrites | L823, L835, L954 | lands in part: neither section says that totality gates only rewrites; that half rests on the plan 7 citation, which is right |
| 1451 | §2.3 | four to five orders of magnitude; not the binding constraint | L181-194 | lands |
| 1452 | §4.3, §5.9, §7.6 | terms compared by hash; laws up to renaming by brute force over at most five variables | L376-380, L585, L973 | lands; the row of §7.6 is itself a proposal with no source (finding 27), and the cut changed the answer (finding 36) |
| 1454 | §2.9, §9 | columns, a behaviour table and a shared term graph survive | L315, L1303, L1324 | lands in part: §2.9 names index columns and one behaviour table for one plan's Stage 0; neither section says a shared term graph is common to both plans (finding 58) |
| 1455 | §6.8 | the geometry question stays open | L804-811 | lands |
| 1459, 1478 | §7.1 | the argument for the lifting forms | L829-833 | lands |
| 1459, 1479 | §7.2 | the argument for subsequence alignment, and the caution | L865 | lands |
| 1489 | §7.5 | laws on the agenda | L934 | lands |
| 1490 | §5.8 | prunes by class, keeps laws by use | L571 | lands |
| 1496 | §7.3 case 5; "context selection" | recursion synthesis from examples; choosing the context | L907-909; none | the first half lands; "context selection" occurs nowhere else in the frozen copy (finding 16) |
| 1499 | §8.6 | property sets | L1141-1170 | lands; §8.6 calls them signatures (finding 16) |
| 1505 | §6.7 | labels supplied by people come last | L798 | lands |
| 1506 | §6.4, §6.5 | the filter; tables read off probe rows | L716-728, L759-763 | lands |
| 1507 | §6.5 | choosing quotients of values | L743-757 | lands (Atlas itself is discussed in §6.7, L800) |
| 1508 | §8.7 | merged quotients lost answers | L1227 | lands |

The file `plan_v2c_audit/revision-notes.md`, to which lines 3, 400 and 1513 point, does not exist in the repository yet. The draft in the scratchpad has the row on arXiv 2611.17309 (its line 117); finding 59 lists two facts that the row does not carry. Line 173 of the draft still says "§6.6, Appendix E" where the new numbering has §6.7 and Appendix C.

## Sentences that still speak in the old terms of §6, or that the new §6 and §8.7 contradict

The old terms were "property signatures", "usage counts", "a flat signature space as an index", "retrieval index" and "four geometries". Of these five phrases, one occurs in the scope: "Property signatures" at line 1499, as the literature's name for the technique of BUSTLE. Outside the scope, line 664 uses "property signatures and usage counts" on purpose, to name what earlier plans built. What is left of the old design is the following.

| Line | Sentence | What the new text says | Finding |
|--:|:--|:--|:--|
| 837 (§7.1) | "Price names by use. An operator's name costs −log₂ of its share of uses in accepted solutions (§6.4)" | L737: prices from counts failed on new operators; counts are only a correction | finding 10 |
| 362 (§4.1) | "Treat the choice of a small grammar for each problem as the main control problem (§6.4)." | §6.4 does not choose a grammar; L619: "What did save work avoids choosing a subset at all" | finding 11 |
| 625 (§5.9) | "There the kernel has to select which library entries go into each problem's grammar." | the same | finding 12 |
| 621 (§5.9) | "propose with the index" | no index is defined; the indexes that were tried "did not earn their place" (L917) | finding 13 |
| 617 (§5.9) | "The fourth is a count of which pairings paid off before." | counts of past use carried no signal for unused entries (L1210, L1346); a count of pairings was not measured | finding 43 |
| 402 (§4.5) | "A flat space is the right shape for *retrieval and ranking*" | retrieval by flat properties found form and not operators (§8.6), and an index of past problems lost to replay (L1268) | finding 19 |
| 540 (§5.5) | "**Tested**: the two terms also have the same column on several fresh spaces" | L724 defines the tested grade as knowledge carried to a space where it is not re-checked | finding 18 |
| 829, 909 (§7.1, §7.3) | the higher-order `filter` "not attempted", "not tested" | L1111: solved on the kernel's spec rows | finding 3 |
| 545 (§5.5) | "returned its one impostor as an answer (§8.1)" | §8.5 reports several on the kernel's spec rows | finding 20 |
| 496 (§5.3) | "on twelve of its own examples rather than the spec's eight" | L1113: run on the spec's eight | finding 44 |
| 1496, 1498, 1499 (Appendix C) | roles "context selection", "counts", "property sets (§8.6)" | no section selects a context; counts are a correction; §8.6 says "signatures" | finding 16 |
| 1353 (§10, outside the scope) | "the retrieval measurement of §8.6, repeated on the kernel's tasks (X4)" | X4 has no retrieval arm | finding 73 |

One sentence of §5.5 is not contradicted and is now incomplete: line 547 says "The prototype tested unconditional laws only", which is true of the prototype, while §8.7 (line 1268) has since found the weakest valid guard for four laws in Python. A pointer to §8.7 would help.

## Words used in a second sense

| Word | Sense given in the Terms table or at first use | Other senses found, with lines |
|:--|:--|:--|
| Stage | Stages A to D of this plan (L42) | The kernel's own "Stage A" phase: glossed at L177; used with no gloss at L1133 (§8.5), which the Terms table promises will not happen (finding 74). Stage 0 and Stage 1 of the v2 plans: always marked (L315, 317, 919, 1323, 1324, 1333). "A handoff in four stages" for the review's order of a search (L871), beside "One search, four steps". "Staging" as compiling a level of interpretation away (L408, L412; defined at L412). |
| node | one node of a program's syntax tree, the unit of program size (L197) | A node of the kernel's search tree (L57, in the same sentence as "AST node"; §2.3 itself now says "a root with one or two children": finding 75). A vertex of a graph or hypergraph (L366, L396, L437); a term in the shared term graph (L461) and, six lines later, a class ("Classes are nodes", L467), which are the vertices of two different graphs; the "node space" of §8.6. "Every enumerated node" in Appendix B (L1476) is an enumerated expression. |
| class | all the terms that denote one column on a space (L29) | "A class of rows whose requirements can be satisfied together", one of the three senses of fiber in the kernel (L173). The classes of an e-graph, which are merged by rules and not by behaviour (L372-380; L378 states the difference). |
| fold | the sequence primitive `fold` (L827) | "Folding", the kernel's simplification of requirements (L1318; glossed). The "fold motif", a law about `foldr` and `foldl` (L231; glossed). "Folded and recursively nested" in the owner's words (L531). "Tenfold" is used as a noun ("each tenfold of work", L57, L980; "4.5 tenfold steps", L356). |
| witness | a concrete object that shows how two things across spaces are related (L587) | The kernel's own word for a solver's answer term: glossed at L251, then used with no gloss at L1060 and L1402 (finding 75). FlashMeta's "witness functions", which are per-operator partial inverses (L408, L1500). |
| quotient | a small term that takes a value to one of a few labels (L35) | The owner's operation of merging rows or merging terms (L155, L305, L511, L523, L529, L615). §6.2 (L653) joins the two senses in one sentence; the Terms table gives only the first. L625 has "The quotients and tables of §6.4" with no gloss, in a section where the word has so far meant merging. |
| signature | no entry in the Terms table | A type signature (L79, L231, L258, L526, L714). A task's set of properties (§8.6, L1141-1166; L1281 "Words replace signatures"; "Property signatures" at L1499). L79 and L714 call a verb table a learned type signature, so in §8 the bare word names the thing that verb tables replaced. |
| probe | a probe space: rows the kernel makes up to test terms (L31) | "Probe evaluation", the outside review's term for evaluating both sides of an equality on another space (L591; attributed). Probe, a published system (L1498). `tg-probe.lisp`, the prototype's file (L1004). |
| index | no entry in the Terms table | A position in a sequence (L509, L613, L827, L855, L1324). The member of a fiber that a residual names (L298-299). "Re-index", moving a column along a map (L500 and after). "Index columns" of v2's Stage 0 (L315). A look-up structure (L422, "index on output"; L521, "a separate index"). "Indexed by the space" (L567). "An index of past problems", a retrieval structure (L917, L1268). "The index" with no antecedent (L621, finding 13). |
| spec | one function the bootstrap asks the kernel to synthesize (L25, L177) | The 31 `:spec` entries of the library, which also specify solvers and transformers (L238; findings 17 and 37). |
| tested | true on this space and also on fresh spaces (L38, L540) | Carried to a space where it has not been checked (L724; finding 18). |

## Appendix A, row by row

Quotations were compared character for character with `/home/tlh24/lisploop/plan_v2_prompt.md`. All 22 are verbatim apart from marked ellipses. Two harmless conventions: inner double quotes are written as single quotes at line 1453, and the bold and the exclamation mark of the prompt's "**lift has to be a synthesizer primitive just like substitution is!**" are covered by the ellipsis at line 1441. Outside the appendix, line 839 puts "lift is a synthesizer primitive" in quotation marks; the owner wrote "lift has to be a synthesizer primitive".

| Line | Quote verbatim | Finding correct | "See" cells land |
|:--|:--|:--|:--|
| 1434 frame | yes | yes | §2.1 yes for one unknown per row and relations among unknowns; "a position, or anything about expressions" is said at line 55 and in §2.2, not in §2.1 |
| 1435 anti-unification | yes | yes | §5.4 yes (line 523) |
| 1436 expression as pattern | yes | yes | §5.1 yes |
| 1437 topology by experiment | yes | `target-sensitive-p` fact correct (`laws.lisp:892`, `:948`; the tests also call it directly at `tests/topology.lisp:42-44`, so "only caller" means only caller in the kernel). Precedent sentence: finding 45 | §2.4 yes (line 234); §5.3 yes (line 482); §6.1 yes (line 647); §7.5 yes (line 949) |
| 1438 depth ≥ 2 | yes | yes (`laws-library.md:134`: "nothing iterates the observation engine over expression-valued inputs") | §2.4 yes; §5.4 yes (line 531); §10 yes (line 1361) |
| 1439 conditional | yes | yes | §2.4 yes (line 232); §5.5 yes (line 547) |
| 1440 tuple | yes | yes | §4.2 yes; §5.2 yes (line 467) |
| 1441 lift in host | yes | yes (`core-repr.md:381-394`) | §2.2 yes, with one gap: the §2.2 table has no row for tuples |
| 1442 reentrancy | yes | yes | §2.2 yes (lines 162-171, eight items); `search-engine.md` §6.2 exists at line 773 |
| 1443 guards | yes | yes (`search-engine.md:690`: 158 rows, 30 D) | §2.3 yes (line 219) |
| 1444 residuals | yes | yes for the two exceptions (line 690, rules 1 and 2); see finding 66 | §2.7 yes; §6.3 yes |
| 1445 policies | yes | constant 0 correct; "regression" loose (finding 70) | §2.6 yes for the predictor; "six integers" is not in §2.6 |
| 1446 flat | yes | yes | §4.5 yes (line 396); §6.6 yes (line 792) |
| 1447 incidental complexity | yes | yes | §2.2 yes (line 173); §2.4 yes (line 230); §2.7 yes (line 273) |
| 1448 underwhelmed | yes | yes | §2.5 yes |
| 1449 totality | yes | first half yes (`core-repr.md:40`). Second half is plan 7's sentence (`plan7/plan7-recursion.md:97`, "only gates algebraic erasure, substitution, and constructor splitting"); by the code totality also gates frame metrics and metric decoders (`core-repr.md:311-313`), which are not rewrites and not execution | §7.1 yes (items 2 and 4); §7.5 yes (line 954); the plan 7 line is right |
| 1450 agents search | yes | yes | §2.4 yes (line 233); §2.5 yes (line 254) |
| 1451 budget | yes | yes | §2.3 yes (line 181) |
| 1452 graph isomorphism | yes | findings 27 and 36 | §4.3 yes; §5.9 yes; §7.6 yes for the renaming row (line 973), which is itself unsourced |
| 1453 not findable | yes | yes | §2.4 yes (line 227); §2.5 yes (line 251) |
| 1454 data structures OK | yes | yes by the reports (`docs-v2b.md:73`, `:187`; `docs-v2tex.md:119`, `:321`) | weak: §2.9 names "index columns, one behaviour table" for one plan's Stage 0 only, and neither §2.9 nor §9 says that a shared term graph is common to both earlier plans |
| 1455 geometry not closed | yes | yes | §6.8 exists ("What remains open") |

## Checked and found correct

### §2 intro, §2.1, §2.2, §2.3

- The eight blockers of reentrancy (lines 164-171) against `search-engine.md:775-815`: each of the eight in the plan corresponds to one of the eight in the report, in the same order, with none merged, split or invented. Item 3's "create" stands for the report's "synthesise", and item 8's "tables" for the report's "message rows".
- Frame facts of §2.1: the row and its requirement over one unknown (`frame.lisp:7-10`, `:221-222`); `frame.lisp:14-24`; the 4 and 256 at `synthesize.lisp:636-642`; pullback at `frame.lisp:544-580` being 37 lines; the soundness test at `tests/invariants.lisp:120-236`; seven extractor functions and 27 call sites (`core-repr.md:413-415`, `:541`); 4–60 ms at 4,000 rows (`core-repr.md:593`, `:810`).
- The operation table of §2.2 against `core-repr.md:380-397`: 34 call sites of `instantiate` (counted in the code: 34), "nine further variants", "about 350 lines" (78 + about 270), `anti-unify` at 38 lines with six call sites (counted in the code: six), and every operator name in the middle column.
- The quotations "wholly in the host lisp" (`plan_v2_prompt.md:4`) and "very limited" (`plan_v2_prompt.md:10`) are verbatim. "freely shifting abstraction level" is verbatim (`plan_v2_prompt.md:5`).
- Throughput and budgets of §2.3: 5–7 million and 33–69 million units per second (`empirical.md:123-133`; `empirical/logs/e4_fit.txt` gives 4.90 to 6.10 million at 350 million units); 350,000 at `consolidate.lisp:1209`; 0.06–0.07 s (`empirical.md:23`); about 2 × 10¹⁰ per hour (`empirical.md:145`); 0.4 s and byte-identical (`empirical.md:87-88`, `:103`); 44 s (`docs-plan6-results.md:691`).
- The budget table: 8, 10, 10 from the sequence logs; `positions` and `seq-corr` (`empirical.md:32`); the four still cut off, 2.6–3.5 GB (`empirical.md:35`; `e4_fit.txt`: 3,219, 3,460, 3,366 and 2,597 MiB); 2.83 × 10⁹ and 8,085× (log: 2,829,937,699); 130 to 300 and 1.5 × 10⁹ (`search-engine.md:330`); the `foldl` impostor (`empirical.md:38`).
- Exponent and memory: 1.38–1.50 per body bit (`empirical.md:304-313`); 18–23 bits (recomputed from the table: 18 to 23); 53–63 bits in an hour (`empirical.md:316`); bodies of 132–259 bits (`empirical.md:319-320`); about 430 bytes per tree, 11 GB exhausted before 7 × 10⁸, 180–240 GB (`empirical.md:51-54`; log `empirical/logs/e4_x2000_shift-seq.log`).
- 109,012 work units and 260 bits under a bound of 130 (log `search-engine/exp-b-ma-schemas.out`).
- Duplicates: 99.0–99.8% (recomputed: 98.97%, 99.58%, 99.76%); 315,388 trees and 767 behaviours (log `empirical/logs/e3b_map-adjacent_exact.log`); ×1.37–1.42 and ×1.17–1.25 (`empirical.md:233-235`).
- Pruner figures: 6–79× and 11–118× (recomputed from `docs-v2tex.md:722-733`: 5.8, 16.9, 78.9 and 10.6, 27.5, 118.4); 11–31× (log `search-engine/exp-d.out`); 1/470 (1,427,679,951 / 3,039,877 = 469.6, logs `e3_v2_g2_exact.log` and `e3_v2_g2_prune.log`); 70 bits against 47 (logs `e3b_map-adjacent_prune.log` and `_exact.log`); about two nodes per tenfold with the pruner (`empirical.md:250-252`).
- Profile: 3% (log `e6_profile_synthesis_map-adjacent.log`: 3.0%); about half in flat search (log `e6_benchmark_profile_root_quartic_86.log`: 52.4%).
- The 158 decisions and 52 / 51 / 30 / 30 / 6 (`search-engine.md:690-691`); the recursion skeleton at `decompose.lisp:341-382` (read in the code); the lockstep form (`search-engine.md:717`).
- Definitions checked against the code as well as the reports and found right: work unit (`core-repr.md:239-249`, `:320-323`; `search-engine.md:113-121`); the kernel's first search phase (`condense.lisp:3`, `:117-144`; `synthesize.lisp:392-408`; the run-weight term that the plan leaves out is zero by default, `synthesize.lisp:156`); lane; body bit; the pruner; the columnar evaluator; snapshot; `pairs`, `anchors`, `edges`.
- Consistency with the Terms table (lines 19-43) and §1.1 (lines 55-60): host and object language, frame, work unit, impostor and "Stages A to D" agree with §2.1 to §2.3. §1.1 item 3 (0.06 s, 8 to 10 of 16, one AST node per tenfold) and item 4 (99%, 6× to 470×) agree with §2.3.
- Words used in a second sense inside lines 120-219: "class" at line 173 ("a class of rows whose requirements can be satisfied together"), which is the code's `fiber-class` and not a class in the plan's sense; "Quotient" at line 155, in the merging sense that §5.4 keeps. Outside the slice, §1.1 at line 57 still says "the search tree has two or three nodes", where the rest of the document now says "sub-problems". No use of "Stage", "fold", "witness", "signature", "probe" or "index" in a second sense was found in the slice.
- Old terms of §6 ("property signatures", "usage counts", "retrieval index", "four geometries"): none in lines 120-219.

### §2.4 to §2.9 and §3

- **§2.4 numbers.** About 550 lines (`laws-library.md:23`: 315 + 230); budgets 20,000 to 80,000; 187 proposed and 14 kept (`exp_algebra.log`); 85 times (6,831,983 / 80,000); under a second (0.080 s in the log); four hand-written axioms; 182,181 / 741,101 / 70,181,164 with 10 results each (`exp_rewrite.log`); 14 kinds and six with no entry (`laws-library.md:148-161`); about 30 edge types written and about 10 read (`laws-library.md:180`); 3 shapes and 1 shape (`laws-library.md:187-188`; `consolidate.lisp:709-735`).
- **§2.5 numbers.** The provenance table, row by row (`bootstrap-reflection.md:158-169`); 61 and 31 (`entries.txt`: 61 non-spec, 31 `:SPEC`); 19 jobs, 19%, 8 atoms, three atoms (`bootstrap-reflection.md:37-41`, `:210-218`, `:398-402`); 9 of 10 (`:350`); 21 and 20 of 21, commit `849013a` (`:43-47`, `:417-431`); 2.4× (393,075 / 165,602, `:796-797`); zero bits and not accepted with two seeds (`:753-755`); 8 tasks, 3 solved at 25,463 to 42,237 against 35 million, 3.2× (115,271 / 35,787), 1.7 to 3× (`:697-700`; `library-value-35M.out`).
- **§2.6 numbers.** 128 lines (`wc -l messages.lisp`); 16 specs, constant 0, +0.02% (1,254,150 / 1,253,942), 40 of 42 labels (`bootstrap-reflection.md:640-644`); 2,332 of 40,155 (`docs-v2b.md:329-337`).
- **§2.7.** Eight representations (`core-repr.md:163-174`); `frame.lisp:1533` is `correction`, which compares sequences position by position; name bits 4, 9, 12 (`core-repr.md:87-88`); 7.5·n² and 430,941 (`core-repr.md:56-58`); 3,334 against 2,000 (`plan9-audit.md:221`; `docs-plan8-9.md:13`; `search-engine.md:57-58`).
- **§2.8 quotations.** Every quotation was found character for character, allowing for line wraps, Markdown bold and LaTeX dollar signs in the sources: the six October and batteries quotations (`deprecated/prompt.md:15`, `:52`, `:79-80`; `deprecated/plan.md:88-89`; `batteries-and-reflection.md:11-12`); "one 'flat' store. A list. In lisp." (`prompt4.md:157-158`, two bullet lines joined); "not essential for this proposal, except ..." (`prompt4.md:62`); plan 5's two phrases (`deprecated/plan5.md:25`, `:34`); "via the exchange of input and outputs" (`prompt4.md:144`); and the rest as listed in the table above. The numbers 900, 4,600, 17,647, nine state structs, 2,661 and 66th, 5 holes to 2 all match their reports and the source documents.
- **§2.9.** About 35 claims and three exceptions; 1,393 lines and no tests (`docs-v2tex.md:27`); 64 syntheses; the four shared gaps; the margin note "how, though?" and the phrase "only through verified maps" (`plan_v2b.md:23`; `scripts/docs-v2b/annots_extracted.txt:5-9`).
- **Pointers.** "Section 6.6" (line 328) lands on "Making, collapsing and moving spaces" (lines 775 to 795), which opens with the same margin note and answers it in three bullets (a space is made by a move; two spaces collapse on a verified bijection; a column moves along a map and is compared in a shared space). "(Appendix D)" (line 317) lands on the bullet about `(tabulate n F)` at line 1552. §3's pointers to §2.2, §2.3 and §2.6 land. "(§2.5)" for the answer term (line 301), "(§2.1)" for lifting and for the decoder skeleton (lines 251, 259), "§2.4" for why reuse loses (line 291) and "§5.5" (line 309) all land.
- **Consistency with §1.1, §11.1 and Appendix A.** §1.1 items 5 and 6, the §11.1 rows citing §2.4, §2.5 and §2.6, and the Appendix A rows citing §2.4 to §2.7 agree with the slice, except findings 72 and 58.
- **The gap log's PARTLY UNFILLED entry** (why the summary counts three): the plan gives the two counts and asserts no reason.
- **The frozen copy** at lines 221 to 346 is identical to `sections/02.4.md` through `03.0.md`.

### §4 and §5

- Every quotation of the owner in the slice, character for character: "freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph" (412); the sentence on expressions and the labeled residual (445); "really it's a form of quotienting and trivial lifting under substitution" (523); "folded and recursively nested" (531); the three quotations from `prompt4.md:170`, `:174`, `:175` (615); "flavors of the same" (521); the two parts of the note on the paper (400) and "is a fundamental limit for compression and needs to be allowed" (583), the last three read in the annotated PDFs themselves.
- Quotations from the trail and the review: "expose different alignments for the anti-unification mechanism" (`deprecated/results.md:561-562`); "can propose and never eliminates" (`plan8.md:306`); "makes the relational interpreter approach impractical for most applications" (`lit-discrete.md:241`); "probe evaluation" and the intensional against extensional paragraph (`plan_v2c_audit.md:31`, `:39`); the tree automaton, ground e-graph and attributed C-set sentence (`plan_v2c_audit.md:20`, `:35`).
- §4.1 figures: 17, 10 and 7 nodes with ranges 13–22, 8–13 and 6–8; 10⁶ evaluations per second; ten nodes, seven and a half, and three (`lit-search.md:625-629`, `:645`); five days on 64 CPUs as about 7,700 CPU-hours and "about a thousandth"; 4.5 tenfold steps giving five to nine nodes; 10¹⁰–10¹¹ work units (`search-engine.md:1052`).
- §4.2 and §4.3 figures and tags: about 17 years, from memory; no benchmark, abstract only; 2ⁿ − 1 classes; 1.13 and 0.1% (`lit-discrete.md:28`, `:135`, `:189`, `:554`); 385 with 80 laws (`laws-library.md:27`, `:239-241`).
- §4.5: O(log m), Ω(√(m log m)) neurons and Ω(m log m) parameters, Adler and Shavit, theorems about neural networks (`lit-geometry.md:163-172`); orthogonal subspaces and the spectral embedding (`:316-328`); 10⁵ examples (`:587`).
- §4.6 and §4.7: FlashMeta abstract only; the 2025 paper; "(2026)" in the caption (`lit-discrete.md:31`, `:240`, `:543`); the bold cells match the closing paragraph.
- New definitions: saturation, superposition, staging, dependency test, `select`, anti-unification, probe space, witness, selective function. Each agrees with its source or with the code.
- §5.3: both tables recomputed by hand; the nine-node term; the length term; 2.8 × 10⁹; 244 ms; 5.0 s; twelve examples against eight; not robust (`proto.md:9`, `:87`, `:97`, `:124`, `:397`).
- §5.4, §5.5: 22 lines (`proto.md:51`); 73 lines (`evidence.lisp`); guards to about four nodes and implication pruning (`lit-search.md:11`, `:120`); the categorical paper read in summary only (`lit-discrete.md:380`).
- §5.8: the recipe and its decisive step (`lit-search.md:10`, `:662-675`); inverses as laws and as structural inversion (`:686`).
- §5.9: 257,214 backtracks on 30 rows (`cross-space/logs/m3.log:40`); 36 and 65 lines; three times chance; the control; three parts to one; plan 7's seeding and "never built".
- The gap log's UNFILLED entries for this slice. "Scheduled lowering" and the hand-set value are gone from the text. The simpler length term is not named. No owner is named for "graph walker". The one that leaks is "depth two" (finding 38).

### §7.1, §7.3, §9 and Appendices A, B, C

- §7.1: the four properties of the VM (`core-repr.md:38-41`; `vm.lisp:370-386`), the fault as a string that exact search discards (`core-repr.md:345-355`), the pruner's treatment of unresolved cells (`search-engine.md:1038`), the removal and return of `:tabulate` and `:loop` (`docs-v2tex.md:293`, `:309`), 0.43 s and 7,700 CPU-hours (`lit-discrete.md:32`; `lit-search-appendix-enum.md:169`; `lit-search-appendix-lib.md:115`).
- §7.3: five schemas supplied by the bootstrap (`search-engine.md:729-737`; `bootstrap/build-batteries.lisp:15`), the lockstep variant, the 50-line termination check (`ast.lisp:971-1022`), the definitions of closed examples and angelic execution, the list of what was run.
- §9 totals: the "as code" rows sum to 1,287 and the "as design" rows to 877, together 2,164 ("roughly 2,200"); the "re-seat" rows sum to 1,186 to 1,286 ("roughly 1,300"); the whole is 3,350 to 3,450 ("about 3,500"); the five re-implement items sum to about 730 to 760 ("about 750"); 17,647 is the root `*.lisp` total less `load.lisp` and `benchmark.lisp`; "about 4,800 of 7,101" is `search-engine.md` §9.2 plus §9.3 (1,900 + 2,900), of which 965 lines are the curriculum file and tooling. Line 116 agrees with all of these.
- §9 table: every line range and count against the code at HEAD and against `core-repr.md:612-624`, `search-engine.md:935-947`, `laws-library.md:343-359`, except the two in findings 8 and 67; the "as code / as design / re-seat" assignments follow those reports and the earlier fact-check (`factcheck.md:78-81`), except finding 41.
- §9 lists: pullback 37 lines; `requirements.lisp:129-540`; `ast.lisp:696-1101`; `knowledge.lisp:514-545`; `vm.lisp:402-551`; `laws.lisp:1250-1327`; the six Stage 0 fixes (`docs-v2tex.md:673`); the four salvageable Stage 1 pieces (`docs-v2tex.md:748-752`, which lists seven; the plan takes the first four); the three design ideas; the 3:1 reserve (`synthesize.lisp:968-970`, `:992-997`; `search-engine.md:232-235`); the quotation from `bootstrap/recursion-schemas.lisp:8-9`, verbatim with a marked ellipsis; the owner's waiver of the present prices (prompt line 15).
- Appendix B: all 17 rows and reasons against `docs-v2tex.md:259-301`. No symmetry refund, spectral embedding, trained router, difference-bound matrix or permutation search is used anywhere in the frozen copy; the difference facts kept in §9 are the fact list that replaced the matrix.
- Appendix C: 398 laws, 33 functions, size 7, 42 minutes, size 8 out of memory (`lit-search.md:55`); 350 s against 24 h (`:108`); conditions to size 4 and 26 minutes for 14 operators (`:67`, `:120`); 87 of 101 and 65% (`:414`, `:423`); 1.13 and 0.1% (`lit-discrete.md:135-137`); more than 60% (`lit-discrete.md:416`); 15–30 nodes, 0.07 s to 128 s; 7,700 CPU-hours; 91 of 140 against 44, and 84 for the stronger baseline (`lit-search.md:218`); 45 properties (`lit-geometry.md:373`); 6–178× (`lit-discrete.md:242`); about 17 years, with the start date from memory (`lit-discrete.md:36`, `:189`); 50 dimensions and the rule miner (`lit-geometry.md:597`, `:120`); O(n²/log n) and O(log m) (`lit-geometry.md:166-167`); 42.6% to 82.0% (`lit-geometry.md:489`); 519 of 544 against 456 and 409, and the conditional problems (`lit-abstraction.md:9`); 8.3×, 9.2×, 2.1×, 3.1× (`lit-abstraction.md:8`); the three declared gaps (`lit-search.md:737`).
- Gap-log entries confirmed against their cited lines: A48; A49 (three entries); A7; A50 persistence, codec, least fixed point; A30 with B3 (all three entries); A9 for Appendix B; A54 (three entries); `clarity-gaps-sec2.md` lines 87 and 93. UNFILLED entries: "land on a known row" and "every" are not asserted; "one lineage" is not defined but is still used (finding 16d); "three prices" is still asserted (finding 15); the "long precedent" sentence is still asserted and turns out to have a source (finding 45).

## What could not be checked, and why

### §2 intro, §2.1, §2.2, §2.3

- The 6–79× and 11–118× figures rest on the table in `docs-v2tex.md`. The script is kept (`scripts/docs-v2tex/e2flags.lisp`) and its output is not, so the figures were recomputed from the report's table and not from a log.
- "4–60 ms at 4,000 rows" rests on `core-repr.md`. The script is kept (`scripts/core-repr/probe10.lisp`) and its output is not.
- "Four auditors tested this independently and agree" (line 183) and "Three auditors switched them on by hand" (line 204): the rows of the two tables were traced to the empirical, search-engine and docs-v2tex reports. Which auditor is the fourth for the first table was not established.
- The count "four" for the senses of "lift" (line 173) cannot be confirmed beyond the one cell at `core-repr.md:387`. The report does not list the four.
- The two rates of the synthesis job disagree between reports (5–7 million in `empirical.md`, 6.1–8.7 million in `search-engine.md:246`), and so does the size of the schema-assisted answer (260 bits in `search-engine.md:45`, 262 in `empirical.md:319`). Both disagreements predate this round, and `factcheck.md` is said to tabulate the first; neither was re-run.
- Nothing was executed. No Lisp was loaded and no experiment was repeated.

### §2.4 to §2.9 and §3

- Numbers whose logs were not copied into `plan_v2c_audit/scripts/`: the predictor loop (40 of 42, +0.02%), `au-robust` (2.4×, zero bits), `grammar-growth` (6.6×), `leaf-bits` output (19%, atom counts), the warm-library ablation behind 2,332, and the core-repr probes (7.5·n², 430,941, name bits). The scripts are there; the outputs are not. These figures were checked against the reports only. I ran nothing, because the repository is read-only for this check.
- The numbers that the plan itself says came from uncommitted Python scratch scripts of plans 1 and 2 (66th of 2,661; the 2,447 bits) were checked against the plan documents only.
- 3,334 work units is tagged **[D]** and rests on `plan9-audit.md`; it was not re-measured by any auditor (`docs-v2b.md:113` marks it UNCHECKED).
- Whether "four times" in the docs-origins report means one occasion per plan (finding 42): the report does not say.
- Checks made after 19:01, when the root kernel files were moved to `/home/tlh24/lisploop/v1/`: only two. The line numbers of the function definitions cited above (`consolidate.lisp`, `proposals.lisp`, `frame.lisp`, `synthesize.lisp`, `laws.lisp`) were re-confirmed by grep against `v1/`, and `milestones/algebra-discovery.lisp:30-48` (used in finding 52) was read at `v1/milestones/algebra-discovery.lisp`. Every other read of a root file, including all of `deprecated/`, `plan7/`, `plan8.md`, `plan9-audit.md`, `tests/topology.lisp` and the kernel sources, was made at the root path before the move. No citation is reported as broken because of the move.

### §4 and §5

- The text of arXiv 2611.17309. The reports give "an important open research direction" (`lit-search-appendix-sci.md:492`) and "remains open" (`lit-geometry.md:559`). The fuller quotation at line 400, with "remains", was verified in the previous round against a saved copy of the paper (`factcheck2-A.md:203`) that is no longer in the scratchpad.
- "So the split you describe is exact" (line 599), and the two phrases of finding 60. They may come from the owner's earlier request, which is not in a file.
- The papers behind the literature figures. I checked the plan against the auditors' reports, not against the papers. Finding 32 rests on the report's wording.
- **[L, from memory]** for the smallest-grammar problem at line 594: no report line was found for it, and the tag already says so.
- Checks made after the move of 19:01, against git HEAD or `v1/` and not against the root path: the body of `anti-unify` (`git show HEAD:unify.lisp`, lines 36 to 68), for "same type signature" at line 526; the search of plan 3 for the word "lift" (`git show HEAD:deprecated/plan3.md`), for finding 4; and plan 2's statement on acyclic patterns (`v1/deprecated/plan2.md:241`, `:615`), for the pointer at line 611. Every other read of a moved file (`frame.lisp:544`, `unify.lisp:103`, `deprecated/plan.md` L80 to L92, `deprecated/plan3.md` §3, `deprecated/results.md`, `plan7/plan7-library.md`, `plan8.md:306`, `abstraction.lisp:380-386`, `evidence.lisp`) was made before the move, at the root path. No check failed because a file had moved.

### §7.1, §7.3, §9 and Appendices A, B, C

- Whether "about 35 removals" in finding 39 is the exact count: I counted rows of three tables in `docs-v2tex.md` by eye and did not read the `plan_v2.tex` revisions themselves, apart from `dbd3347` line 113 and the current line 401.
- The literature figures were checked against the audit reports, not against the papers.
- `revision-notes.md` exists only as a draft in the scratchpad; I checked one line of it (173) and no more.
- Checks made after the move of 19:01, against `git show HEAD:<path>` or `v1/<path>` instead of the root path: the line ranges of the solver schema and the metric decoder (`laws.lisp:1059-1244`, `:1250-1327`), of the ledger and the closure compiler (`vm.lisp:10-54`, `:402-551`), the predictor in `consolidate.lisp:1-60` (finding 70), and `bootstrap/build-batteries.lisp:15` and `:628` (the schema expander, and the `filter` spec of finding 3). One search, for callers of `recursion-schema-expander`, first failed because `bootstrap/` had gone, and was redone against `v1/`. Everything else, including the `wc` line counts behind the §9 totals (17,818 lines in the root `*.lisp` files, all present), was read at the root paths before the move.

### The whole scope

- Nothing was executed. No Lisp was loaded, no experiment was repeated, and no log was regenerated. A number is called correct when it agrees with its report and, where the log was copied, with the log.
- The literature figures were checked against the auditors' reports, not against the papers.
- The owner's latest request is not in a file. Three phrasings that may come from it could therefore not be traced: "So the split you describe is exact" (line 599), and the quoted "graph walker" and "graph isomorphism engine" (lines 608 and 609).
- `plan_v2c_audit/revision-notes.md` does not exist in the repository. Its draft in the scratchpad was read at two rows only (lines 117 and 173).
- Whether the move of the root kernel into `v1/` is finished, and whether it is meant to stay.
- The four slice checkers' reports were merged as they were written. I re-opened the sources for findings 1, 2, 3, 4, 5, 6, 7, 8 and 27, and not for the rest.

## Sections with no finding

§2 (introduction), §4 (introduction), §4.2, §4.4, §5 (introduction), §5.1, §5.2, §5.7 and §5.8 are clean.
