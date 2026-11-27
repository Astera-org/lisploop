# Fact-check, round 3, scope C, part D: §7.1, §7.3, §9, Appendices A, B, C

Line numbers are those of `round3/v3-for-check.md`. Report paths are under `/home/tlh24/lisploop/plan_v2c_audit/reports/`.

## Read this first: the repository changed under the check

At about 19:01 PST on 26 November, while this check was running, the working tree of `/home/tlh24/lisploop` was reorganized by someone outside the check. Every root kernel file (`*.lisp`), and `bootstrap/`, `deprecated/`, `plan7/`, `tests/`, `milestones/`, `experiments/`, `plan8.md`, `plan9.md`, `plan9-audit.md`, `plan-exec.md`, `architecture.md`, `architecture2.md` and `batteries-and-reflection.md`, now sit under a new untracked directory `v1/`, and `git status` shows 92 tracked files as deleted at the root. I did not do this; every command I ran was read-only. I compared six of the moved files with `git show HEAD:<path>` and they are byte-identical, so the content is unchanged and no finding below depends on the move: no citation is reported as broken, and no line count as missing, because of it. This is an observation for the author, not a finding. The plan's file-and-line references (`frame.lisp:544-580`, `vm.lisp:384`, `bootstrap/recursion-schemas.lisp`, `plan7/plan7-recursion.md` L97, `tests/theories.lisp`, and so on) are written as root paths. If the move is kept, the front matter (line 3) could carry one sentence, for example: "File paths are those of commit `15e64c6`; the root kernel and the older plans have since been moved under `v1/`, so `frame.lisp` is now `v1/frame.lisp`."

## Findings, most serious first

**1. INCONSISTENCY (a stale design statement that the new §6.4 and §8.7 contradict).**
Line 837: "**5. Price names by use.** An operator's name costs −log₂ of its share of uses in accepted solutions (§6.4), under a prefix code as now."
The section it cites now says the opposite. Line 737 (§6.4): "Prices from counts of past use are the form that failed on new operators. So a name's price comes first from its tables, and from counts only as a correction that cannot price a name out **[P]**." Line 1210 (§8.7): "Used as prices in the manner of the published grammar-reweighting method, it sent 5 of the 8 tasks that need one past a cap of three million candidates." Line 719 says the same. The sentence at line 837 was not touched by the clarity pass (it is identical in `sections.preclarity/07.1.md`), so the rewrite of §6 left it behind.
Replacement: "**5. Price names from tables, with counts only as a correction.** An operator's place in the enumeration, and so its price, is read first from how well its verb tables fit the labels of the problem at hand. Its share of uses in accepted solutions enters only as a correction that cannot price a name out (§6.4). Counts alone were measured as prices and failed: they sent 5 of the 8 tasks that needed a never-used operator past the search's cap (§8.7). The code stays a prefix code, as now."

**2. INCONSISTENCY (§7.1 and §7.3 against §8.5).**
Line 909: "The higher-order `map`, `foldr` and `filter` were not tested." Line 829: "§8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter`. It did not attempt the higher-order `map` and `filter` themselves."
Line 1111 (§8.5) reports the kernel's `filter` spec as run and solved: "`filter` | 200/200 at 1,383 candidates, once a one-argument Boolean call is in the grammar". The kernel's `filter` is the higher-order one: its spec takes the predicate as an argument (`bootstrap/build-batteries.lisp:628`, `:spec/filter (list (cons 0 seq-t) (cons 1 pred-t)) seq-t`). `verify-review.md:63` gives the program found, `(select xs (lambda (j x) (call1b p x)))`, and `verify-review.md:86` says the held-out set included a predicate never seen in the rows. `verify-review.md:301` gives the limit that should be stated: the predicate is one of three named functions (`pos`, `even`, `neg`), not arbitrary code. §8.1 and §8.5 also found `scan` and `map-adjacent` with a function argument (lines 1027, 1028, 1110), so "first-order instances of ... `scan`" at line 829 understates as well.
Replacement for line 909: "The kernel's `filter` spec, which takes its predicate as an argument, was solved on its own rows once the grammar could call a one-argument Boolean function; the predicate was one of three named functions, not arbitrary code (§8.5). The higher-order `map` and `foldr` were not tested."
Replacement for the last two sentences of line 829: "§8 finds the terms for `reverse`, `shift`, `zip`, for first-order instances of `map`, `scan`, and `filter`, and for `scan`, `map-adjacent` and the kernel's `filter` with a function passed in as an argument (§8.1, §8.5). It did not attempt `map` or `foldr` with a function argument."

**3. FACTUAL ERROR (a definition that is not what the source says; added by the clarity pass).**
Line 1299: "It handles operators with any number of arguments and respects types. A pair of differing sub-terms that recurs gets one shared hole, and an operator itself can become a hole (§5.4)"
The pre-clarity cell was "n-ary, typed, shared holes, operator holes", copied from `core-repr.md:620`. "n-ary" there means that any number of terms are generalized at once, not that operators may have any number of arguments. `unify.lisp:36`: `(defun anti-unify (sources ...)` takes a list of sources; its docstring (`unify.lisp:37`) says "Equal disagreement tuples reuse the same hole", where a tuple has one sub-term from each source. `laws-library.md:207-208`: "n-ary, typed, syntactic, first-order least general generalisation" and "the table from a tuple of disagreeing subterms to its hole". The gap log cites `lit-discrete.md:342`, which describes the two-term case ("Given two terms ... the same pair of differing subterms"); that is where "pair" came from. The operator hole also has a condition that the cell drops: `unify.lisp:40-41`, "Applications whose operators differ but share a signature are aligned under an operator hole".
Replacement: "It generalizes any number of terms at once and respects types. Where the terms differ, the differing sub-terms, one from each term, are replaced by a hole, and the same combination of differing sub-terms gets the same hole wherever it recurs. An operator itself can become a hole when the operators have the same type signature (§5.4)"

**4. FACTUAL ERROR (file-and-line reference; present before the clarity pass).**
Line 1310: "| Requirement propagation, with replay and fallback | `laws.lisp:736` onward | 338 | re-seat |"
The 338 lines are `laws.lisp:447-784` (`laws-library.md:350`: "`propagate-requirements` with witness replay, necessity refutation, set-valued witnesses, fallback | `laws.lisp:447-784` | 338"). Line 736 is only where the entry function `propagate-requirements` starts; it ends at line 786, so "736 onward" covers 51 lines of the 338.
Replacement for the "Where" cell: "`laws.lisp:447-784`"

**5. OVER-STATEMENT (the word "only" was added by the clarity pass and is not in the source).**
Line 899: "They differ only in the arguments passed to the recursive call, which their author chose by hand."
`search-engine.md:1064-1067` says the five schemas and the kernel's own template are "the same act (bind the recursive call's value as a new input of the child) with a different hand-chosen argument tuple". It does not say that is the only difference, and its own table (`search-engine.md:733-737`) shows others: `:lookahead-inductive` has a second base case, `:state-scan-inductive` wraps the call in `cons`, `:countdown-inductive` adds a test on a counter. The file's header says the same (`bootstrap/recursion-schemas.lisp:6-8`: "a second base case, a state threaded through the recursive call, and an integer counted down or up beside the sequence").
Replacement: "They differ in the arguments passed to the recursive call, which their author chose by hand, and in the base cases and the fixed code that the author wrote around the call."

**6. OVER-STATEMENT (a design statement with no source, presented in a "Finding" cell).**
Line 1452: "Within a space, neither: rooted, ordered, shared terms are compared by hash, and laws up to renaming by brute force over at most five variables."
The only other place this appears is the cost table of §7.6 (line 973), which is proposal. I found no measurement and no code behind "at most five variables": no report mentions it (grep of all reports for "renam", "five variables", "5 variables"), the prototype has no such routine (`proto/tg-probe.lisp`), and the law experiment of §8.3 used three variables. Appendix A is not covered by the front matter's rule that §5 to §7 are **[P]**, so here it reads as something the audit found.
Replacement: "Within a space, neither. Rooted, ordered, shared terms are compared by hash. This plan proposes to compare laws up to renaming of their variables by trying every renaming, which is affordable only while laws have few variables; that has not been built or measured **[P]**."

**7. MISSING CAVEAT (created by a cut that clarity-review B2 allowed).**
Line 1452, same cell. Before the clarity pass the cell went on: "Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run on what the index proposes. The e-graph's store is useful; its saturation is not." B2 asked for the cell to keep only its first sentence. What is left answers "we'd need an efficient graph isomorphism test ..., or e-graphs" with "neither", which is the opposite of what the plan says at line 101 ("Across spaces a matching engine is needed, as you say") and in §5.9. A reader who uses Appendix A as the index of answers gets the wrong one.
Replacement, to follow the sentence in finding 6: "Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run only on the pairs that cheaper signals propose (§5.9). An e-graph's store is worth having, and its saturation is not (§4.3)."

**8. MISSING CAVEAT (Appendix B says nothing is re-imported; one rejected item has a close relative in §5.9, and the table is a selection).**
Line 1459: "This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2)." Line 1475: "| A spectral embedding and a `like`/`analogy`/`act` query language | interpreter weight at a library of a few hundred |"
(a) The removal that line 1475 summarizes had three parts. `docs-v2tex.md:296`: "Closed-form 32-dimensional Laplacian/SVD, 2-hop WL hashes, the `(:like/:analogy/:act)` query DSL | "Eigensolver or interpreter bloat" at |L| ≤ 500"; `plan_v2.tex:401` has the same three. The row drops "2-hop WL hashes". WL (Weisfeiler–Leman) hashing is colour refinement, which this plan uses at line 608 to match rows and at line 617 as a signal ("the colour histograms of two spaces"), with a measurement in §8.6. The use differs (an exact match that is then verified, against a similarity hash), and it is measured, but the appendix is where the owner will look for exactly this and it is silent. The three word types 'like', 'action', 'analogy' of line 706-708 are the owner's own (prompt line 8), not a query language, so they are not a re-import; one clause saying so would help for the same reason.
(b) The table has 17 rows. `docs-v2tex.md:259-301` records about 35 removals across the three passes (for example tree automata from Burst, PIE bi-abduction, unboxed integer columns, experimentation as an object-language primitive). The front matter (line 17) says "Appendix B lists what their own audit passes rejected", which reads as complete.
Replacement for line 1459: "This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2). One further item has a relative here. The pass that removed the spectral embedding also removed graph hashes made by colour refinement; this plan uses colour refinement to match rows across spaces (§5.9), where every match is then checked exactly, and that use was measured (§8.6). The table lists the rejections that bear on this plan; the full record of about 35 is in the `docs-v2tex.md` report, part 3.1. The reasons given for each rejection are those recorded in the revisions of `plan_v2.tex`."
Replacement for the first cell of line 1475: "A spectral embedding, graph hashes by colour refinement, and a `like`/`analogy`/`act` query language"

**9. MISSING CAVEAT (a literature claim with no tag, no pointer, and a source that was checked from abstracts only).**
Line 1437: "The method has long precedent for numeric laws and for program slicing."
The gap log (`clarity-gaps-sec2.md:94`) marks this UNFILLED: "has no counterpart in the body or Appendix E that I could find". It is supported, in a report the worker did not search: `lit-discrete.md:34`, "'Hold all but a few inputs constant and see what changes' is an established discovery method for numeric laws (BACON 1977–81; control-variable symbolic regression 2023; AI Feynman 2020) and for program dependence (dynamic slicing, delta debugging, causal program dependence analysis 2025) [V-abs]". So the claim is sourced, the source was verified from abstracts only, and none of the four sections in the "See" cell states it.
Replacement: "The method has precedent for numeric laws, from BACON (1977 to 1981) onward, and for finding what a program's output depends on, as in dynamic slicing; the literature auditor checked these against abstracts only (lit-discrete report, finding 7) **[L, abstract only]**."

**10. OVER-STATEMENT (two details of the new description of requirement simplification are not what the code does; added by the clarity pass).**
Line 1318: "a rule that drops or reorders a sub-term applies only when that sub-term is provably total. Each rule is held to one of two contracts: the simplified requirement is equivalent to the original, or it is merely necessary for it."
(a) `requirements.lisp:136-139` (`unfoldable-parts-p`): "True when a fold rule may drop or reorder every expression in PARTS: each is provably total or, under the :necessary CONTRACT, built from holes, total constructors, `:code-eval` and structurally terminating functions without unguarded partial primitives." So "only when ... provably total" holds under one contract and is relaxed under the other. (b) The contract belongs to a call of the simplifier, not to a rule: `requirements.lisp:529`, `(defun fold-constants (expression &key ledger (budget 10000) (contract :equivalent) max-fibers)`, and the same rules run under either contract.
Replacement: "a rule that drops or reorders a sub-term applies only when that sub-term is provably total or, under the weaker of the two contracts below, when it is built only from parts that cannot fail (`requirements.lisp:136-149`). Each call of the simplifier names one of two contracts: the simplified requirement must be equivalent to the original, or it need only be necessary for it."

**11. MISSING CAVEAT (the new definition of the fact-and-measure scheme leaves out half of the criterion, and the line count covers only part of what is described; added by the clarity pass).**
Line 1319: "The first is the fact-and-measure scheme, about 50 lines. A branch is judged under the facts that its condition establishes, and a recursive definition is total when the arguments of every self-call decrease on measures of its parameters: a sequence shortened by `tail`, an integer bounded below that is reduced by a literal, or an integer bounded above that is increased."
`core-repr.md:304-306`: "A definition is total if every step is total under path facts **and** its self-calls descend lexicographically on per-parameter measures". The code agrees (`ast.lisp:1023-1027`, docstring of `analyze-function-body-totality`; `ast.lisp:1007-1013`, docstring of `self-calls-descend-p`: "Some measure must fall at one call at least and rise at none ... That is a lexicographic order"). So decreasing self-calls are necessary and not sufficient, and not every self-call has to decrease. On the count: `core-repr.md:619` gives "the fact/measure scheme (`self-call-changes`, `self-calls-descend-p`, 50 LOC)"; those two functions are `ast.lisp:971-1022`, 52 lines. The branch facts described in the first half of the sentence are a different function, `condition-facts` (`ast.lisp:764-831`, 68 lines), which the 50 does not include.
Replacement: "The first is the fact-and-measure scheme. A branch is judged under the facts that its condition establishes (`condition-facts`, 68 lines). A recursive definition is total when every step of its body is total under those facts and its self-calls descend in a lexicographic order on measures of its parameters: a sequence shortened by `tail`, an integer bounded below that is reduced by a literal, or an integer bounded above that is increased. The test on self-calls is about 50 lines (`self-call-changes`, `self-calls-descend-p`)."
Line 907 ("The kernel's termination check, about 50 lines that can be carried over") is consistent with the 50-line figure and needs no change.

**12. MISSING CAVEAT ("as code" for the largest row of the table; present before the clarity pass).**
Line 1302: "| Description-length-gated abstraction | `abstraction.lisp` | 580 | as code | it is what finds `:map` |", with line 1293: ""As code" means the file can be lifted nearly unchanged."
The auditor's verdict on that file is narrower. `laws-library.md:355`: "Works on the 6-function corpus; cover heuristics are list-specific." `laws-library.md:216`: the cover's "atomic units" are "hand-listed list-recursion idioms: a bound variable, `(tail X)`, `(at X c)`, a self-call", and the pattern keeps "recursive control spines". The plan replaces tail recursion with `tabulate`, `fold` and `scan` (§7.1), so those parts will not carry over unchanged. The row is 580 of the 1,287 lines marked "as code".
Replacement for the "Why" cell: "it is what finds `:map`. Its acceptance test, by total description length, carries over. Its heuristics for which sub-terms to share are written for recursion on lists and will need rewriting for the new sequence primitives"

**13. INCONSISTENCY (a count with no referent; the gap log marks it UNFILLED and the plan still asserts it).**
Line 1335: "On tariffs: nothing here preserves the present prices in bits or in work, and three of those prices are artifacts (§2.7)."
§2.7 (lines 271-279) names two: line 277, the name bits that are "an accident of its position in the list of primitives", and line 278, the work price list that "charges quadratic cost for operations that are not quadratic in the host", illustrated by two examples. No third is identifiable (`clarity-gaps-sec4-9.md:54` reached the same conclusion; `core-repr.md:89` and `:56-58` are the two sources).
Replacement: "On tariffs: nothing here preserves the present prices in bits or in work, and two of them are artifacts: the name bits, which follow an operator's position in the list of primitives, and the work price list, which charges quadratic cost for operations that are not quadratic in the host (§2.7)."

**14. INCONSISTENCY (terms in Appendix C that the rest of the document does not use, or uses differently).**
(a) Line 1499: "| Property signatures (BUSTLE) | one lineage | ... | property sets (§8.6) |". §8.6 never says "property set". It calls the thing a "signature" throughout (lines 1141, 1143, 1151, 1157, 1162), and line 1281 says "Words replace signatures and counts". The pointer lands on the right measurement; the name does not match. Replacement for the cell: "the sets of properties compared between whole problems, which §8.6 calls signatures and which did not find the operators a problem needs".
(b) Line 1498: "| Grammar reweighting during search (Probe) | one lineage | ... | counts |". After the rewrite, counts failed as prices (line 1210) and survive only as a correction (line 737). Replacement for the cell: "counts of past use, which failed as prices on never-used operators (§8.7) and are kept only as a correction to the tables (§6.4)".
(c) Line 1496: "§7.3 case 5; context selection". "Context selection" occurs nowhere else in the document. Replacement: "§7.3 case 5; the choice of which library entries go into a problem's grammar (§4.1, §5.9)".
(d) "One lineage" (lines 1498, 1499, 1505) is not defined; line 1483 defines only "Shipped" and "Replicated". The gap log left it undefined because the obvious definition is wrong for Probe: `lit-search.md:218` grades Probe "PROVEN-RESEARCH (re-implemented by Bee Search authors; baseline for Simba, DryadSynth)" and `lit-search.md:362` "SINGLE-PAPER, re-implemented once"; `lit-geometry.md:373` grades property signatures "PROVEN-RESEARCH". Replacement for the Probe grade: "one system, re-implemented once by another group". Replacement for the BUSTLE and LAPS grades: "one research group and its follow-up systems". If "one lineage" is kept, add to line 1483: ""One lineage" means one research group and the systems that follow from its work."

**15. COSMETIC (a quotation that is not verbatim from its primary source).**
Line 829: "because they "Smuggled `map-indexed`/`foldl` into host Lisp via higher-order opcodes""
The quotation is taken from the audit report (`docs-v2tex.md:293`), not from the document it attributes. The revision itself (`git show dbd3347:plan_v2.tex`, line 113) reads: "\texttt{v2.2} smuggled \texttt{map-indexed}/\texttt{foldl} into host Lisp via higher-order \texttt{:tabulate}/\allowbreak\texttt{:loop} opcodes and a \texttt{:filter}-specific propagator". So the capital S is the report's, and "`:tabulate`/`:loop`" was dropped without a mark.
Replacement: "An earlier audit pass removed `:tabulate` and `:loop`, saying that the version before it had "smuggled `map-indexed`/`foldl` into host Lisp via higher-order `:tabulate`/`:loop` opcodes", and the next pass put them back."

**16. COSMETIC (Appendix A gives one cause where §6.3 gives three; wording added by the clarity pass from review item A51).**
Line 1444: "The clunkiness comes from having eight representations of one thing (§2.7)."
Line 690-694 (§6.3): "ambient pricing is not what made residuals clunky. Three implementation facts did (§2.7)", and lists the eight representations, a metric that cannot depend on the row, and program bits sized at the root added to residual bits sized in a child space.
Replacement: "The clunkiness comes from three facts of the implementation, of which the first is that one thing has eight representations (§2.7, §6.3)."

**17. COSMETIC (three small points in the §9 totals and table).**
(a) Line 1309: the "Lines" cell "215–315" is now unexplained, because the sentence that explained it ("where two auditors counted the same code differently, both figures are given") was cut under review item C7. Replacement for the cell: "215 by one auditor's count and 315 by another's". (b) The same row lists `laws.lisp:215-228`, 14 lines that the row above it (`laws.lisp`, 228 lines, which is `laws.lisp:1-228`) already counts. (c) Line 1289 ends "The kernel proper is 17,647 lines", right after "About 3,500 lines are worth carrying over". About 370 of the 3,500 are milestone code (line 1313), which the 17,647 does not include (17,647 is the root `*.lisp` total of 17,818 less `load.lisp` and `benchmark.lisp`). Line 116 has it right ("of the present kernel and its milestone code"). Replacement for the last sentence of line 1289: "The kernel proper is 17,647 lines; about 370 of the lines to carry over are milestone code outside that count."

**18. COSMETIC (three cells of Appendix C).**
(a) Line 1508: "perfect heuristics in polynomial time in three of six benchmark domains". `lit-abstraction.md:12` quotes the paper: "in three of the six classical planning benchmarks that have polynomial-time optimal solution algorithms". Replacement: "perfect heuristics in polynomial time in three of the six benchmark domains that have polynomial-time optimal algorithms". (b) Line 1509 names EURISKO alone. The analysis it paraphrases is of both systems (`lit-discrete.md:563`: "AM and EURISKO: by the author's own analysis ..."), and the specific point about short Lisp programs is about AM, which is how line 952 attributes it. Replacement for the first cell: "Reflection that compounds (AM, EURISKO)". (c) Line 1463: "computation in superposition does not compress". Line 398 and line 1504 say it compresses quadratically, as does the recorded reason (`docs-v2tex.md:263`: "quadratically, not exponentially, efficient"). Replacement: "computation in superposition is only quadratically efficient".

**19. COSMETIC (§7.3, last paragraph; both present before the clarity pass).**
(a) Line 909: "Published recursion synthesizers need examples that are closed under the recursive call ... Otherwise they need angelic execution". The two definitions that the clarity pass added are correct (`lit-search.md:241`, Myth's trace-complete examples; `lit-search-appendix-enum.md:203`, Burst: "assume recursive calls can return anything ("angelic"), synthesise, then check"). The either-or is not exhaustive in the report's own table: `lit-search.md:244` (SMyth, "no trace-completeness", by live bidirectional evaluation) and `:248` (SyRup, joint search of traces and programs). Replacement for "Otherwise they need angelic execution, which ...": "The published ways around that requirement are angelic execution, which assumes that a recursive call can return anything, synthesizes, and then checks, and two single-paper techniques that push examples through partly written programs or search for the missing traces **[L]**." (b) Same line: "On the kernel's spec rows it was run on `foldl`, `seq-corr`, `best-shift`, `argmax-corr` and `last-or`". §8.5 ran all sixteen specs (line 1118). Replacement: "On the kernel's spec rows it was run on all sixteen specs, among them `foldl`, `seq-corr`, `best-shift`, `argmax-corr` and `last-or`, which are the ones that bear on case 4, and not all of these were solved (§8.5 gives the outcome of each)."

**20. COSMETIC (Appendix A, row on policies).**
Line 1445: "The one learned policy is a clamped regression on six integers."
It is not a regression in the usual sense. `core-repr.md:522`: "an `:int` AST run in the VM on six integers"; `consolidate.lisp:21-25`: the kernel's own `condense-heuristic` induces a program from a frame of six integer inputs whose labels are clamped to [−24, 48]. §2.6 (line 265) describes it correctly and does not mention the six integers.
Replacement: "The one learned policy is a small program, induced by the kernel's own search from six integers that describe a sub-problem, whose output is a clamped correction to that sub-problem's priority."

## Changes against the pre-clarity version

"Supported" names the clarity-review item or gap-log entry. Nothing in this slice lost a number or an evidence tag except where a row says so.

| Section | What changed | Kind | Supported by | Verdict |
|:--|:--|:--|:--|:--|
| §7.1 l.817 | Opening sentence split into four properties; "its code is re-derived for the new opcodes (§9)" added | added claim, pointer | A46; §9 table row "Metered, resumable evaluator ... as design" | supported |
| §7.1 l.827 | Glosses for `length`, `at`, `fold`, `scan`; heading reworded | added definitions | A47 | supported (they define proposed primitives and agree with the §7.2 table) |
| §7.1 l.831 | "Stage D, the last of the four stages ... (§11.3)" | added pointer | A1 | supported |
| §7.1 l.833 | λ² and DreamCoder named; **[L]** moved to the first sentence; "(§4.1)" added | added names, tag moved | A48; gap log A48 (`lit-discrete.md:32`) | supported; 0.43 s and 7,700 CPU-hours unchanged and correct |
| §7.3 l.899 | "which the bootstrap supplies (`bootstrap/recursion-schemas.lisp`)"; "bind the value of the recursive call as a new input of the child problem"; "They differ only in the arguments ..." | added claims, file reference | A49; gap log A49 (`search-engine.md:1064-1067`, `:729-739`) | supported except the word "only" (finding 5) |
| §7.3 l.902 | Keep-column defined | added definition | A49 | supported (agrees with line 1010) |
| §7.3 l.907 | Two ranking tests spelled out; "about 50 portable lines" became "about 50 lines that can be carried over" | reworded | A49; UNFILLED for "land on a known row", wording kept | supported; the unfilled reading is not asserted |
| §7.3 l.909 | Definitions of "closed under the recursive call" and "angelic execution"; "not all of these were solved (§8.5 gives the outcome of each)"; "Cases 1–4 are different" | added definitions and claim | A49; gap log A49 (`lit-search.md:240-241`, `lit-search-appendix-enum.md:203`) | supported; "every" was not written, as the log says |
| §9 l.1289 | Dropped: "Line counts are the auditors', from the root tree; where two auditors counted the same code differently, both figures are given." | dropped sentence | C7 (optional) | supported; leaves "215–315" unexplained (finding 17a) |
| §9 l.1299 | "n-ary, typed, shared holes, operator holes" expanded; "(§5.4)" added | changed claim | A50; gap log A50 | NOT supported as written (finding 3) |
| §9 l.1300 | "fixed-point save and load" became "Saving, loading and saving again gives equal entries" | reworded | A50; gap log (`bootstrap-reflection.md:785-786`) | supported; "entries", not "file", matches the source |
| §9 l.1305 | Codec cell expanded: encoder as a counter; decoder rejects non-canonical codes; "you have said that the present prices need not be kept" | added claims | A50; gap log (`core-repr.md:614`, `:74`; prompt line 15) | supported; `codec.lisp:10` and `:205` confirm |
| §9 l.1318 | "Definedness-preserving folding" renamed and explained; note that "folding" is not the primitive `fold` | added definition | A7; gap log A7 (`core-repr.md:562-564`, `:312-313`) | supported in substance; two details wrong (finding 10) |
| §9 l.1319 | Fact-and-measure scheme and least-fixed-point discipline defined; `knowledge.lisp:514-545` added | added definitions, file reference | A50; gap log A50 (`core-repr.md:297-308`, `:619`, `:289-290`) | least-fixed-point sentence correct (`knowledge.lisp:514-518`); fact-and-measure sentence incomplete (finding 11) |
| §9 l.1322-1325 | "From v2" bullet became three sub-bullets; lift against split, the replay guard and "each row of the root problem is priced exactly once" moved in from §2.9; definitions of difference facts, `gather`, `evolve` added | moved and added | B3; A30; gap log (`docs-v2tex.md:86`, `:83`, `:87`, `:841`, `:748-756`) | supported; every item of the old §2.9 list is present |
| §2.9 → §9 | Lost in the move: the parenthesis "(all cheap, all grounded in something measured here)" and the bullet "the list of mechanisms those audits rejected, in Appendix D, which this plan does not re-import" | dropped | B10 for the bullet; nothing for the parenthesis | acceptable: the parenthesis was the docs-v2tex auditor's own judgement (`docs-v2tex.md:824`), not a measurement |
| §9 l.1327 | "fold soundness under both contracts" became "soundness of requirement simplification under both contracts" | reworded | A7 | supported |
| §9 l.1333 | "the Stage 1 additions" became "v2's Stage 1 additions" | reworded | A1 | supported |
| §9 l.1335 | "three of them are artifacts" reworded, count kept | unchanged claim | A50, UNFILLED | not supported (finding 13) |
| App. A l.1435 | Cut: the two sentences after "As intuition, yes." | dropped | B2 | supported; §5.4 carries them |
| App. A l.1437 | "See" cell gained §5.3 and §6.1 | added pointers | A51, C8 | supported; both land |
| App. A l.1438 | "Depth one exists and works; a script limits it." rewritten | reworded | A51 | supported by line 225 |
| App. A l.1440 | "A row is a tuple is an n-ary edge" split | reworded | A51 | supported |
| App. A l.1442 | List of six blockers cut, "listed in §2.2" | dropped | A51, C8 | supported; §2.2 lines 164-171 list eight |
| App. A l.1444 | Residual answer rewritten | reworded, added "(§2.7)", "(§6.3)" | A51; gap log `clarity-gaps-sec2.md:93` | supported by line 690; narrows three causes to one (finding 16) |
| App. A l.1446 | Cut: "A flat space buys storage, not computation, and this library has no storage pressure. Use one flat signature space as an index." | dropped | B2 | supported; also removes a stale term |
| App. A l.1449 | Cut: "Three gaps: the fault is an unstructured string; search discards it; no opcode observes it. Timeouts have no precedent."; `plan7/plan7-recursion.md` L97 added to "See" | dropped, added reference | B2; gap log `clarity-gaps-sec2.md:87` | supported; the line number is right |
| App. A l.1452 | Cut: the across-spaces and e-graph sentences | dropped | B2 | allowed by B2, but changes the answer (finding 7) |
| App. A l.1453 | Cut: the three reasons distributivity was missed, now "when asked directly" | dropped | B2 | supported; line 227 carries them, including "85 times" |
| App. A l.1454 | "See" cell gained §9 | added pointer | B3 | supported in part (see the table below) |
| App. B l.1457 | Re-lettered D to B | relabel | brief | correct |
| App. B l.1459 | Cut: "Two further proposals are close relatives of rejected items ...: random-walk proximity and count-based triggers (§6.4)." | dropped | A53 | supported; neither phrase occurs in the frozen copy. See finding 8 for a relative that is still there |
| App. B l.1474 | "Host probes" became "Hand-written recognizers in host code" | reworded | A9; gap log (`docs-v2tex.md:295`) | supported |
| App. B end | Cut: "What survived every pass unchanged is short: columnar tables, a behaviour table, a single record for all knowledge, the Stage 0 fixes, and the audit of the kernel." | dropped | B3 | supported; note that "a single record for all knowledge" and "the audit of the kernel" as survivors (`docs-v2tex.md:321-324`) are now stated nowhere |
| App. C l.1481 | Re-lettered E to C | relabel | brief | correct |
| App. C l.1483 | Verification gaps moved up from below the table | moved | A54, B4 | supported (`lit-search.md:737`, `:442`, `:485`) |
| App. C | Cut: "The three rows on abstract values were added in the revision and checked against the papers' text (`lit-abstraction.md`); a 1977 paper by Knuth that the outside review also cites could not be fetched." | dropped | C4 | supported; the caveat survives in the draft `revision-notes.md` line 173, whose "See" cell still says "§6.6, Appendix E" and should say "§6.7, Appendix C" |
| App. C l.1496 | Myth cell expanded: "raised one task from 0.07 s to 128 s" | reworded | A54; gap log (`lit-search-appendix-enum.md:160`) | supported: `list_compress` 0.073 s to 128.3 s |
| App. C l.1499 | Role "signatures" became "property sets (§8.6)" | changed | A55 | pointer right, term not the one §8.6 uses (finding 14a) |
| App. C l.1505 | Role now "(§6.7)" | changed pointer | A54, A55 | lands (line 798) |
| App. C l.1506, 1507 | "(§6.5)" added; "(§6.4)" became "(§6.5)" | changed pointers | A55 | both land (lines 741-771) |
| App. C l.1509 | EURISKO cell expanded | reworded | A54; gap log (`lit-discrete.md:563`) | supported; see finding 18b |

## Appendix A, row by row

Quotations were compared character for character with `/home/tlh24/lisploop/plan_v2_prompt.md`. All 22 are verbatim apart from marked ellipses. Two harmless conventions: inner double quotes are written as single quotes at line 1453, and the bold and the exclamation mark of the prompt's "**lift has to be a synthesizer primitive just like substitution is!**" are covered by the ellipsis at line 1441. Outside the appendix, line 839 puts "lift is a synthesizer primitive" in quotation marks; the owner wrote "lift has to be a synthesizer primitive".

| Line | Quote verbatim | Finding correct | "See" cells land |
|:--|:--|:--|:--|
| 1434 frame | yes | yes | §2.1 yes for one unknown per row and relations among unknowns; "a position, or anything about expressions" is said at line 55 and in §2.2, not in §2.1 |
| 1435 anti-unification | yes | yes | §5.4 yes (line 523) |
| 1436 expression as pattern | yes | yes | §5.1 yes |
| 1437 topology by experiment | yes | `target-sensitive-p` fact correct (`laws.lisp:892`, `:948`; the tests also call it directly at `tests/topology.lisp:42-44`, so "only caller" means only caller in the kernel). Precedent sentence: finding 9 | §2.4 yes (line 234); §5.3 yes (line 482); §6.1 yes (line 647); §7.5 yes (line 949) |
| 1438 depth ≥ 2 | yes | yes (`laws-library.md:134`: "nothing iterates the observation engine over expression-valued inputs") | §2.4 yes; §5.4 yes (line 531); §10 yes (line 1361) |
| 1439 conditional | yes | yes | §2.4 yes (line 232); §5.5 yes (line 547) |
| 1440 tuple | yes | yes | §4.2 yes; §5.2 yes (line 467) |
| 1441 lift in host | yes | yes (`core-repr.md:381-394`) | §2.2 yes, with one gap: the §2.2 table has no row for tuples |
| 1442 reentrancy | yes | yes | §2.2 yes (lines 162-171, eight items); `search-engine.md` §6.2 exists at line 773 |
| 1443 guards | yes | yes (`search-engine.md:690`: 158 rows, 30 D) | §2.3 yes (line 219) |
| 1444 residuals | yes | yes for the two exceptions (line 690, rules 1 and 2); see finding 16 | §2.7 yes; §6.3 yes |
| 1445 policies | yes | constant 0 correct; "regression" loose (finding 20) | §2.6 yes for the predictor; "six integers" is not in §2.6 |
| 1446 flat | yes | yes | §4.5 yes (line 396); §6.6 yes (line 792) |
| 1447 incidental complexity | yes | yes | §2.2 yes (line 173); §2.4 yes (line 230); §2.7 yes (line 273) |
| 1448 underwhelmed | yes | yes | §2.5 yes |
| 1449 totality | yes | first half yes (`core-repr.md:40`). Second half is plan 7's sentence (`plan7/plan7-recursion.md:97`, "only gates algebraic erasure, substitution, and constructor splitting"); by the code totality also gates frame metrics and metric decoders (`core-repr.md:311-313`), which are not rewrites and not execution | §7.1 yes (items 2 and 4); §7.5 yes (line 954); the plan 7 line is right |
| 1450 agents search | yes | yes | §2.4 yes (line 233); §2.5 yes (line 254) |
| 1451 budget | yes | yes | §2.3 yes (line 181) |
| 1452 graph isomorphism | yes | findings 6 and 7 | §4.3 yes; §5.9 yes; §7.6 yes for the renaming row (line 973), which is itself unsourced |
| 1453 not findable | yes | yes | §2.4 yes (line 227); §2.5 yes (line 251) |
| 1454 data structures OK | yes | yes by the reports (`docs-v2b.md:73`, `:187`; `docs-v2tex.md:119`, `:321`) | weak: §2.9 names "index columns, one behaviour table" for one plan's Stage 0 only, and neither §2.9 nor §9 says that a shared term graph is common to both earlier plans |
| 1455 geometry not closed | yes | yes | §6.8 exists ("What remains open") |

## Cross-references checked (§7.1, §7.3, §9, Appendices B and C)

| Line | Pointer | Lands |
|:--|:--|:--|
| 817 | (§9) | yes: line 1304, "as design" |
| 821 | (§2.3) for 3% | yes: line 215 |
| 823 | (§7.5) guards and totality from faults | yes: lines 936, 954 |
| 823 | `vm.lisp:384`, `enumerate.lisp:426-441` | yes: the `setf` that turns the condition into a string starts at 384 (`princ-to-string` is on 385); `consume-search-outcome` is exactly 426-441 |
| 829 | "§8 finds the terms ..." | partly (finding 2) |
| 831 | (§11.3) | yes |
| 833 | (§4.1) | yes: line 358 |
| 837 | (§6.4) | no: §6.4 says the opposite (finding 1) |
| 839 | (§7.4) | yes |
| 827, 839 | "six" primitives against the §7.2 table and line 103 | consistent: `gather` is stated to be derived; the aggregates of line 858 and `try` of line 835 are extra forms that §7.1 does not count; line 103 names three of the six and leaves out `scan` |
| 899 | (§2.3) | yes: line 196 (which says the lockstep form "walks two sequences"; the code handles two or more, `search-engine.md:717`) |
| 904 | (§8.5) | yes: line 1122 |
| 905 | (§8 measures this) | yes: line 1038 |
| 909 | (§8.1), (§8.5) | yes |
| 1299 | (§5.4) | yes: lines 525-526 |
| 1304, 1318 | §7.1 | yes |
| 1321 | "the `decode` construct" | yes: line 861 |
| 1325 | (§7.2) replay guard | yes: line 867 |
| 1325 | (Appendix B) symmetry refund | yes: line 1468 |
| 1333 | (§2.9) "mined, not continued" | yes for the reasons (line 317); §2.9 no longer has a list and points back to §9 |
| 1335 | (§2.7) | two artifacts there, not three (finding 13) |
| 1459, 1478 | (§7.1) | yes: line 829 |
| 1459, 1479 | (§7.2) "the argument and the caution" | yes: line 865 |
| 1489 | §7.5 laws | yes: line 934 |
| 1490 | (§5.8) | yes: line 571 |
| 1496 | §7.3 case 5 | yes; "context selection" has no anchor (finding 14c) |
| 1499 | (§8.6) | yes; term mismatch (finding 14a) |
| 1505 | (§6.7) | yes: line 798 |
| 1506 | §6.4, (§6.5) | yes: lines 724, 759 |
| 1507 | (§6.5) | yes: line 743; §6.7 line 800 names Atlas |
| 1508 | (§8.7) | yes: line 1227 |

## Words used in a second sense, in this slice

- "Witness": line 1500 uses it for FlashMeta's per-operator inverse functions. The front matter and §5.9 use it for an object that relates two spaces, and §2.5, line 1060 and X2 (line 1402) use it for the kernel's answer term.
- "Node": line 1476, "on every enumerated node", means every enumerated expression. Elsewhere a node is a node of a syntax tree (line 1496) or, before the clarity pass, a sub-problem.
- "Signature": line 1499, "Property signatures", is the literature's name for a set of Boolean properties. §2.5, §5.4 and §6.4 use "type signature".
- "Fold": handled. Line 1318 now says the kernel's "folding" is not the primitive `fold`.
- "Stage": every use in this slice is qualified ("Stage 0 of the v2 plans", "v2's Stage 1", "Stage D ... (§11.3)").
- "Probe", "quotient", "index", "class": no second sense in this slice. "Host probes" is gone from Appendix B.

## Noticed outside this slice

- Line 621 (§5.9): "propose with the index". The index was removed from §6. 
- Line 1133 (§8.5): "Stage A does not price cell by cell" uses the kernel's "Stage A" with no qualifier, against line 42.
- Line 1353 (§10): "the retrieval measurement of §8.6".
- Lines 1141-1162 (§8.6) call sets of properties "signatures" throughout; line 664 calls the same thing "property signatures" as a mechanism of earlier plans.
- Line 1541 lists `factcheck3-*.md` as existing reports.

## Checked and found correct

- §7.1: the four properties of the VM (`core-repr.md:38-41`; `vm.lisp:370-386`), the fault as a string that exact search discards (`core-repr.md:345-355`), the pruner's treatment of unresolved cells (`search-engine.md:1038`), the removal and return of `:tabulate` and `:loop` (`docs-v2tex.md:293`, `:309`), 0.43 s and 7,700 CPU-hours (`lit-discrete.md:32`; `lit-search-appendix-enum.md:169`; `lit-search-appendix-lib.md:115`).
- §7.3: five schemas supplied by the bootstrap (`search-engine.md:729-737`; `bootstrap/build-batteries.lisp:15`), the lockstep variant, the 50-line termination check (`ast.lisp:971-1022`), the definitions of closed examples and angelic execution, the list of what was run.
- §9 totals: the "as code" rows sum to 1,287 and the "as design" rows to 877, together 2,164 ("roughly 2,200"); the "re-seat" rows sum to 1,186 to 1,286 ("roughly 1,300"); the whole is 3,350 to 3,450 ("about 3,500"); the five re-implement items sum to about 730 to 760 ("about 750"); 17,647 is the root `*.lisp` total less `load.lisp` and `benchmark.lisp`; "about 4,800 of 7,101" is `search-engine.md` §9.2 plus §9.3 (1,900 + 2,900), of which 965 lines are the curriculum file and tooling. Line 116 agrees with all of these.
- §9 table: every line range and count against the code at HEAD and against `core-repr.md:612-624`, `search-engine.md:935-947`, `laws-library.md:343-359`, except the two in findings 4 and 17; the "as code / as design / re-seat" assignments follow those reports and the earlier fact-check (`factcheck.md:78-81`), except finding 12.
- §9 lists: pullback 37 lines; `requirements.lisp:129-540`; `ast.lisp:696-1101`; `knowledge.lisp:514-545`; `vm.lisp:402-551`; `laws.lisp:1250-1327`; the six Stage 0 fixes (`docs-v2tex.md:673`); the four salvageable Stage 1 pieces (`docs-v2tex.md:748-752`, which lists seven; the plan takes the first four); the three design ideas; the 3:1 reserve (`synthesize.lisp:968-970`, `:992-997`; `search-engine.md:232-235`); the quotation from `bootstrap/recursion-schemas.lisp:8-9`, verbatim with a marked ellipsis; the owner's waiver of the present prices (prompt line 15).
- Appendix B: all 17 rows and reasons against `docs-v2tex.md:259-301`. No symmetry refund, spectral embedding, trained router, difference-bound matrix or permutation search is used anywhere in the frozen copy; the difference facts kept in §9 are the fact list that replaced the matrix.
- Appendix C: 398 laws, 33 functions, size 7, 42 minutes, size 8 out of memory (`lit-search.md:55`); 350 s against 24 h (`:108`); conditions to size 4 and 26 minutes for 14 operators (`:67`, `:120`); 87 of 101 and 65% (`:414`, `:423`); 1.13 and 0.1% (`lit-discrete.md:135-137`); more than 60% (`lit-discrete.md:416`); 15–30 nodes, 0.07 s to 128 s; 7,700 CPU-hours; 91 of 140 against 44, and 84 for the stronger baseline (`lit-search.md:218`); 45 properties (`lit-geometry.md:373`); 6–178× (`lit-discrete.md:242`); about 17 years, with the start date from memory (`lit-discrete.md:36`, `:189`); 50 dimensions and the rule miner (`lit-geometry.md:597`, `:120`); O(n²/log n) and O(log m) (`lit-geometry.md:166-167`); 42.6% to 82.0% (`lit-geometry.md:489`); 519 of 544 against 456 and 409, and the conditional problems (`lit-abstraction.md:9`); 8.3×, 9.2×, 2.1×, 3.1× (`lit-abstraction.md:8`); the three declared gaps (`lit-search.md:737`).
- Gap-log entries confirmed against their cited lines: A48; A49 (three entries); A7; A50 persistence, codec, least fixed point; A30 with B3 (all three entries); A9 for Appendix B; A54 (three entries); `clarity-gaps-sec2.md` lines 87 and 93. UNFILLED entries: "land on a known row" and "every" are not asserted; "one lineage" is not defined but is still used (finding 14d); "three prices" is still asserted (finding 13); the "long precedent" sentence is still asserted and turns out to have a source (finding 9).

## Could not check

- Whether "about 35 removals" in finding 8 is the exact count: I counted rows of three tables in `docs-v2tex.md` by eye and did not read the `plan_v2.tex` revisions themselves, apart from `dbd3347` line 113 and the current line 401.
- The literature figures were checked against the audit reports, not against the papers.
- `revision-notes.md` exists only as a draft in the scratchpad; I checked one line of it (173) and no more.
- Checks made after the move of 19:01, against `git show HEAD:<path>` or `v1/<path>` instead of the root path: the line ranges of the solver schema and the metric decoder (`laws.lisp:1059-1244`, `:1250-1327`), of the ledger and the closure compiler (`vm.lisp:10-54`, `:402-551`), the predictor in `consolidate.lisp:1-60` (finding 20), and `bootstrap/build-batteries.lisp:15` and `:628` (the schema expander, and the `filter` spec of finding 2). One search, for callers of `recursion-schema-expander`, first failed because `bootstrap/` had gone, and was redone against `v1/`. Everything else, including the `wc` line counts behind the §9 totals (17,818 lines in the root `*.lisp` files, all present), was read at the root paths before the move.
