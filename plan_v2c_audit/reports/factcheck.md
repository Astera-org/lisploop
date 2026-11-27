# Fact-check of `plan_v2c.md`

Checked against: the fifteen reports in `plan_v2c_audit/reports/` (and the four `lit-search-appendix-*` files where needed), the prototype source and all nine logs in `plan_v2c_audit/proto/`, the root kernel and `v2/` code, the owner's prompts (`plan_v2_prompt.md`, `deprecated/prompt.md`, `prompt4.md`, `batteries-and-reflection.md`), and the trail documents the plan quotes (`deprecated/plan*.md`, `deprecated/results.md`, `plan7/*.md`, `plan8.md`, `plan9-audit.md`). Nothing under `/home/tlh24/lisploop` was edited.

Severity: **A** factually wrong; **B** unsupported or over-stated; **C** imprecise or missing caveat; **D** cosmetic. Counts: A 10, B 19 (B5 is the general finding; B6–B10 are its instances), C 33, D 15.

Plan line numbers are those of `grep -n` on `plan_v2c.md`.

---

## A. Factually wrong

**A1. The prototype did not cover "the four" stuck functions.**
- Plan §1.4: "They include the four the existing kernel does not find at a thousand times its budget." §8.1: "These include the four functions the existing kernel does not find without a hand-written schema at a thousand times its budget (§2.3)."
- Source: §2.3's own four are `map-adjacent`, `scan`, `shift-seq`, `best-shift` (empirical.md §0 item 2 and §4.1; docs-v2tex.md §7 item 1). The prototype's task list (`proto/tg-probe.lisp:279-303`) has no `best-shift`, and no `seq-corr`, `argmax-corr` or function-argument `foldl`. proto.md §0 names its four as "map-adjacent, positions, scan, shift-seq". In the regime of §2.3 the kernel solves `positions` at 3.6× the budget (empirical.md §4.1); it fails only in the whitelist regime (bootstrap-reflection.md §4.2, search-engine.md §2.5), where five functions fail, `best-shift` among them.
- Correction: "three of the four (`map-adjacent`, `scan`, `shift-seq`); `best-shift`, the largest (259 body bits), was not attempted."

**A2. An AI-written plan sentence is presented as the owner's words.**
- Plan §4.4: "Your own October formulation was 'No column is designated as input or output'."
- Source: `deprecated/plan2.md:835`, agent-written text outside the embedded owner outline (L33–190). docs-origins.md §5(c) item c1 tags it **[AI]**. The plan's own §2.8 and Appendix B attribute the same sentence to plan 2. The owner's phrase, quoted in that same plan-2 paragraph, is "exchange of input and outputs".
- Correction: "Plan 2 put it as …" or quote the owner's own phrase.

**A3. "Sampled evidence can propose and never eliminates" is from Plan 8, not Plan 9.**
- Plan §2.8 ("(plan 9)"), §5.5 ("Plan 9 recorded that …"), Appendix B (location `plan9.md`).
- Source: `plan8.md:306` (§6.7). docs-plan8-9.md §5 item 6 cites it as "(plan8 §6.7)". The phrase does not occur in `plan9.md` or `plan9-audit.md`.

**A4. "66th of 2,661" is from Plan 1, not Plan 2.**
- Plan §2.8 ("(plan 2)"), §6.2 ("In plan 2's measurement"), Appendix B (location `deprecated/plan2.md`).
- Source: `deprecated/plan.md:579` (plan 1). docs-origins.md §3 and item e8 both say "plan1 L579". It is also a result of a Python scratch script that was never committed (docs-origins.md §0 fact 1: "They are unverifiable"), which the plan says of one other nugget but not of this one.

**A5. "A guard is the residual of a law" is not a remark in the trail.**
- Plan §5.5: "The trail's remark that 'a guard is the residual of a law' …". Also §2.8 ("(results, October)") and Appendix B (`deprecated/results.md` L730).
- Source: the phrase is the auditor's gloss in docs-plan6-results.md line 447 ("*Why now:* a guard is the residual of a law"). `deprecated/results.md:730-733` says "the unresolved information is the membership of each input in its valid subset. That information is represented by a normal frame". `grep` finds the phrase in no trail document.
- Correction: drop the quotation marks and attribute the reading to this audit.

**A6. The time and cost given for the inverse of `*` are not in the log.**
- Plan §1.4: "`*` with its guard `b ≠ 0` in 0.22 s". §8.2 table: "141,652 (0.22 s)".
- Source: `proto/logs/c.log`: 268 ms and 236 ms (padded run), 236 and 240 ms (unpadded). proto.md §5 gives 268 / 236. proto.md §5 also notes "the 141,652 candidates are the cost of also finding the size-8 section; the guard has size 4 and the inverse size 3".
- Correction: "0.24–0.27 s; the candidate count includes the search for a size-8 section, not only the guard and inverse." (§8 opens with "every number below is copied from a log there".)

**A7. The map-adjacent element term is not five nodes.**
- Plan §5.3: "a five-node term solves it".
- Source: `(+ (at xs i) (at xs (+ i 1)))` is nine nodes (four operators, five leaves) under the prototype's own `tsize` (`tg-probe.lisp:154`); proto.md §0 calls the function-argument version "a size-10 term". Correction: "a nine-node term".

**A8. The memory figure for "an hour" mixes the one-hour and ten-hour extrapolations.**
- Plan §8.4: "The sizes an hour could reach by time alone would need 0.2–2.4 TB."
- Source: `proto/logs/a.log`: one hour needs 210.7 / 207.0 / 256.7 GB; ten hours 2,437 / 1,237 / 1,694 GB. proto.md §0 says "the sizes that 1 h or 10 h … would reach need 0.2 to 2.4 TB".
- Correction: "0.21–0.26 TB for one hour; 1.2–2.4 TB for ten."

**A9. The kernel's `positions` is not a selective function.**
- Plan §7.3 case 2: "Selective functions (`filter`, `positions`): a `where` over input positions".
- Source: the kernel spec is `positions(xs, k) = (k, k+1, …)` (`bootstrap/build-batteries.lisp:659-667`: "The index list of a sequence, counted from a start"). proto.md §3: "the spec is an offset index list, not 'positions of a value'". In `d.log` it is the position-wise `(tabulate (len xs) (lambda (i prev) (+ i k)))`, 3 candidates. The plan's §8.1 table lists only "positions of a value", which is the prototype author's own task, and omits the "positions (spec)" row.
- Correction: move `positions` to case 1; say that "positions of a value" is not a kernel function.

**A10. "11–118×" is not the pruner's figure, and it is not the largest effect measured.**
- Plan §1.1 item 4: "A working behaviour pruner … switched on, it cuts work 11–118×". §2.3: "pruning cut work 11× to 118× … This is the largest measured effect in the audit." §11.1 repeats it.
- Source: docs-v2tex.md §2 row 5 and §6.2 table: pruning alone gives 5.8×, 16.9×, 78.9× ("6–79×"); 11–118× is pruning plus column evaluation. The same report adds "a 5-element field saturates its behaviours quickly, so these ratios flatter pruning". search-engine.md §10.2 measured 11–31× for pruning alone and 26–77× with the columnar flag on other workloads. empirical.md §3.1 measured 1/470 of the work at 48 bits on integers, which is larger than 118×.
- Correction: "6–79× for pruning alone and 11–118× with column evaluation, on a GF(5) benchmark that flatters it; 470× on one integer grammar."

---

## B. Unsupported or over-stated

**B1. Extrapolations are presented as measurements.**
- Plan §1.4 under "Limits, also measured": "A single deep search exhausts 24 GB in one to eight minutes, and ten hours reaches one node further than one hour." §7.6: "the prototype exhausts 24 GB within one to eight minutes of one deep search". §8.5 item 5: "the prototype puts numbers on it".
- Source: `a.log` prints these under "extrapolation"; `proto/run.sh` gives SBCL a 10 GB heap; proto.md §4 says "By extrapolation" and lists six assumptions as "all optimistic unless noted". What was measured: a 90 s run per grammar with a 6-million-class cap, and two size-minimal runs that died at 10 GB (`docc-15M-heap-exhausted.log`, `docc-30M-heap-exhausted.log`). Only the §8.4 table row carries "(extrapolated)".
- Correction: say "extrapolated from a 90-second run" in §1.4, §7.6 and §8.5.

**B2. The low-risk claim for the first two stages contradicts the plan's own body.**
- Plan §1: "with little research risk in the first two stages … the plan keeps them off the first two stages". §1.7: "built only from shipped parts". §11.3: "nothing in it is new science: its parts are the shipped ones."
- Source: Stage A contains X2 (inverses from tables). §5.8 item 2 says of that mechanism "no precedent found" and calls it "this plan's own"; §10 lists "Learning inverse rules" under no convincing precedent, "*Depended on*"; lit-discrete.md §11.4 item 1 and lit-search.md §C item 5 say the same. X2's gate includes "the two composite cases in risk 2", and §1.6 lists "Learned inverses beyond one operator" as research. Stage B rests on §5.8 item 1 (also "this plan's own"), and §11.3 itself places research risk in X3, which is the gate of Stage B.
- Correction: state that Stage A contains one mechanism without precedent (measured only on the prototype) and that Stage B's central mechanism is the plan's own.

**B3. The list of no-precedent items the plan depends on is incomplete.**
- Plan §10: "The plan depends on the first two; the others are deferred or avoided by design."
- Source: lit-discrete.md §11.4 closes "Items 1, 2 and 8 are where the project would be doing research". Item 8 is "Deriving algebra from depth-two interventions on a program simulator … not something I found". The plan proposes exactly this (§5.4 third remark, X6, Stage D) and never flags it; that remark carries no [P] tag. Also unflagged: item 4, conditional equalities with learned guards in a merged store (§5.5 guarded laws), and lit-search.md §C item 7 (guards beyond size 4). The last bullet of the plan's own list, "A unified topology–geometry kernel. Nothing attempts it", is the plan's title, so it is neither deferred nor avoided.

**B4. "About 3,500 lines … independent of the frame representation, and import largely as they are" is not what the reports say.**
- Plan §9 opening, and §1.7.
- Source: core-repr.md §7 says of the codec "Import the *mechanism*" and of the evaluator "Import the *design* … `execute-primitive` is a 22-branch `case` to re-derive". laws-library.md §8 says the observation engine "Depends on the enumerator and row-job base". search-engine.md §9.1 says "Clean apart from the frame-row assumptions" and, of the scheduler, "The formula is hard-coded; the shape is reusable". In code: `propagate-requirements (frame source ledger)` (`laws.lisp:736`); `message-frame` builds a frame (`messages.lisp:60-73`); `milestones/algebra-discovery.lisp` works through `support-frame`; `enumerate.lisp` refers to frames 41 times. Those rows are about 1,400 of the table's 3,450 lines. search-engine.md's own tally of clean code in its 7,101 lines is about 1,450, including 301 marked "import the idea, not the file". The plan's §7.1 also changes the evaluator's unit of evaluation.
- Correction: split the table into "imports as code" (ledger, evidence, unify, persistence, abstraction, certification) and "imports as design, bound to frames today".

**B5. Sections 5–7 state the proposal in the indicative with almost no [P] tags.**
- Plan header: "Every claim that carries weight is tagged". Tag count in the body: [P] five times, none in §5 (lines 365–501 have no tag of any kind).
- B6–B10 are the instances that matter.

**B6. "A guarded law needs no extra machinery" (§5.5).**
- Source: the prototype's law experiment was unconditional only (proto.md §6). lit-search.md bottom line 3 and §B row 10: searched guards work to size ≤ 4, and "Implication structure between conditions is mandatory to avoid drowning (Chompy without it: no termination in hours)". lit-discrete.md §11.4 item 4 lists conditional equalities with learned guards in a merged store as having no mature precedent. The plan's own §7.6 prices it at g × c × n.

**B7. "the store knows it at the moment it happens" (§5.5, the `foldl` check).**
- Source: not implemented in the prototype; the seed-9 miss was returned as an answer, not reported as underdetermined (proto.md §3.3). By §5.2 a class stores "that column once, its smallest term", and by §5.5 enumeration "can keep one and build only from it", so the rival programs that fit the task rows are never built or kept. The check needs retained members and a second evaluation.

**B8. "anti-unification is automatically taken modulo every equivalence the store has observed" (§5.4), at cost "their total size" (§7.6).**
- Source: no anti-unification in the prototype. lit-discrete.md finding 6: beyond first-order "everything … costs"; over classes it is "inherently quadratic in the size of the corpus". With one representative per class this is normalise-then-anti-unify, which the kernel already does (laws-library.md §3, "pre-normalisation"). docs-plan6-results.md §3 item 1 records why spellings were kept: "different spellings give AU different alignments".

**B9. "On this store they are literally one routine with different maps" (§5.4; §1.3 "one routine").**
- Source: the prototype has three routines (`explode`, `pull`, `collect`) used for lifts over output and input positions only. Its split used a separate "per-call index of boolean classes … (a restriction of base in all but name)" (proto.md §7 item 5). Anti-unification, recursion as a call space, projection and the derivation space were not built.

**B10. "'Lift of a requirement' is then an operation a synthesized program can perform, which neither earlier plan achieved" (§5.6); "It is the same 37 lines, with the same soundness tests".**
- Source: this plan has not achieved it either. The prototype's goals are host predicates on a class (proto.md §2). `pullback-frame` takes and returns frames (`frame.lisp:544-580`), and the plan's own §9 lists pullback under "rewrite the code".

**B11. "one 12-operator grammar and no skeleton" (§1.4, §8.1); "`filter` … are then terms to be found, and §8 finds them" (§7.1).**
- Source: the procedure hard-codes the program forms `(tabulate L (lambda (i prev) …))`, `select`, `where`, a single-guard `if`, `fold` / `foldr`, plus routing among them (proto.md §7 items 1–9, 12). It uses a second "Shape grammar `+ - max min` over lengths" (proto.md §3) and given leaves `(len xs)`, 0, 1 and the `prev` lag column. `select` is filter (`tg-probe.lisp:239`), so what was found for "filter x > k" is the predicate `(< k x)`. Higher-order `map` and `filter` were not tasks. `select` is also absent from §7.1's six primitives.
- Related: docs-v2tex.md §3.1 (Pass 2) records the rejection of a "`:filter`-specific … subsequence propagator" because it "Hard-codes one library function". The prototype's `align` (`tg-probe.lisp:436-440`) is a subsequence aligner for the same job, and the plan's Appendix D omits that row.

**B12. The §5.3 comparison is between different tasks.**
- Plan: "The existing kernel does not find this function in 2.8 × 10⁹ work … A prototype of this store finds it in about a quarter of a second."
- Source: the kernel's `map-adjacent` takes a function argument (leaf `(cons (code-eval X2 X1 X0) X3)`, bootstrap-reflection.md §3.2). The 244 ms figure is the fixed-`+` task. The matching prototype task took 8,458,580 candidates and 5.0 s, was perfect on 7 of 8 further example sets, and returned an impostor under the 15-operator grammar (`d.log`, `dseeds.log`). It ran on 12 examples with 31 lifted rows, not the spec's 8 examples with 6 output elements (proto.md §8 "Not tested").

**B13. "Cases 1–4 cover every function in the current library" (§7.3).**
- Source: untested for `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`, `map`, `foldr`, `filter`, `scan-pair`. `best-shift` (a search over shifts of a correlation of two sequences) plausibly needs two lifts, which §8.5 item 1 says were not tested. See also A9.

**B14. "These are the witnesses and guards the kernel's milestone code finds from hand-written spec rows" (§8.2).**
- Source: laws-library.md §1.3. The milestone path works from a full grid, not spec rows; the hand-written spec rows belong to the `consolidate.lisp` path. The results differ: the milestone code finds the divisor-unknown solver for `/` with its guard (prototype: "not found"); its dividend-unknown guard is `k ≠ 0` (prototype: `b = ±1`); on integers its `*` guard includes divisibility (prototype: `(not (= b 0))` only, because every row of a product table is divisible).

**B15. Two pieces of evidence in §6.3 drop caveats that change their meaning.**
- "45 hand-written properties of this kind beat learned embeddings": lit-geometry.md §7 table: "45 hand-written boolean properties + a small MLP trained on ≈200k self-generated examples". Both arms fed a trained network; the plan's signatures are to be used with "none … trained by gradient descent".
- "gains for distance-on-behaviour synthesis are 56–664×": the same table says "metric is expert-supplied", and the appendix says the factors "come from the 2018 draft record, not the OOPSLA 2023 version".
- The count precedent (Probe) reweights within one task from partial solutions; the plan's counts are across tasks.

**B16. Ruler's result is attached to a mechanism the plan does not adopt.**
- Plan Appendix E: "Pruning the term space with laws already found (Ruler) | 350 s with it; unfinished at 24 h without | building only from class representatives". §1.3: the review's recipe "is nearly this parts list". §4.3: classes need "no rules".
- Source: lit-search.md bottom line 2: "The decisive mechanism is using laws already found to shrink the term space before testing anything … Observational-equivalence dedupe and typing come next." Recipe rows 3 (class representatives) and 5 (prune with laws) are separate. The plan drops row 5 (§8.5 item 4: "Classes do the pruning").

**B17. "'interestingness' as a criterion was AM's undoing [L]" (§7.5).**
- Source: no report says this. lit-search.md §4.6 quotes Lenat and Brown: "AM's ultimate limitation apparently was due to its inability to discover new, powerful, domain-specific heuristics", and success came from "the density of worthwhile math concepts as represented in Lisp". The word appears once, describing what AM's heuristics scored.

**B18. Enumeration reach is a model estimate, stated as what published systems reach.**
- Plan §4.1: "published bottom-up enumerators with dedupe reach about 17 nodes in an hour over 10 primitives, 10 nodes over 30, and 7 over 100 [L, estimate anchored on six published systems]"; "Multiplying the budget by 3,600 is worth seven."
- Source: lit-search.md §A.3 is headed "ESTIMATE; not a published result". It assumes 10⁶ evaluations per second; at 10⁵ "subtract 2.1, 1.3 and 0.85 nodes". Ranges are 13–22, 8–13, 6–8. It is checked against four systems (EUSolver, Probe, TRANSIT, TF-Coder); I could not find "six". §A.4 gives 7.5, 4.6 and 3.0 nodes for 3,600×; "seven" is the 10-primitive case only.

**B19. Appendix E: "All figures were checked online by the literature auditors unless marked."**
- Source: nothing in the table is marked, and the reports tag several of its entries otherwise: OpenCog's start date "[FM]" and its overview paper checked "in its abstract" (lit-discrete.md §3.1); the e-graph / version-space / tree-automaton identity "[V-abs]" (finding 2); FlashMeta "[V-abs]"; the enumeration reach "ESTIMATE"; the anti-unification-as-product reading "[V-abs; the paper itself could not be fetched]" (lit-discrete.md §6.6). The same holds for one [L] claim outside the table: "Trees embed exactly" is "[FROM-MEMORY, textbook]" (lit-geometry.md §6).

---

## C. Imprecise or missing caveat

1. §2.3: "An hour reaches 53–63 body bits" and "An hour would need roughly 180–240 GB" are extrapolations (empirical.md §8: "Everything said about 1 h and 10 h is extrapolation … over 12–23 bits of horizon"). Not labelled.
2. §2.3, §7.4: "158 places: 52 … 51 … 30 … 30 … 6" sums to 169. search-engine.md §4: "a row with two classes is counted under both".
3. §2.3 table row 5: "every internal bound, depth, and stage budget raised 100×". The bound went 130 → 300; the run was a cutoff at 1.5 × 10⁹, not an exhaustion (search-engine.md §2.5).
4. §2.3, §7.1: "evaluating candidates is about 3% of the time". In flat exact search it is 52% (empirical.md §6a); the 3% holds because "Most candidates in these lanes are not of the target type or are rejected on the first row".
5. §2.4, Appendix A: "Distributivity is missing only because of the script". The host filter also has no two-operator shape (`consolidate.lisp:709-735`), and the battery's budget is 85× too small (laws-library.md §1.2).
6. §2.5, §7.6: the lifting result omits that four rows of the same table became 1.7–3× dearer (bootstrap-reflection.md §6.2; its summary says three). The "6.6×" comes from a separate experiment with dummy-bodied stand-in functions (§6.3 there).
7. §2.5, X6: "`:map` and `:foldr` are found". `:foldr`'s gain is 0 bits after naming and it is not accepted with two seeds per signature; both names come from the script (bootstrap-reflection.md §6.4, §2.3).
8. §2.6: "One older loop is wired in". search-engine.md finding 8: "not on any production path"; `consolidate-knowledge-library` is called only from tests.
9. §2.8: "From the 14–19 October prompts". Two of the four quotes ("learn the propagation rules", "search tree and execution graph itself") first appear in the prompt of 20–26 October (`deprecated/prompt.md:15`, `:52`; docs-origins.md A6, A22).
10. §2.8: Plan 5 diagnosed "a second `:code-*` language, six state machines, parallel engines". This is a paraphrase in quotation marks (plan5: "a **second parallel language** of nine `:code-*` primitives"; "Six hand-rolled state machines").
11. §2.8, Appendix B: plan-1 and plan-2 numbers come from uncommitted Python scripts (docs-origins.md §0 fact 1). Only one nugget says so.
12. §2.9: "`plan_v2.md` has ten unverified novelties on its critical path". docs-v2b.md: "6 (A) + 10 (X)".
13. §2.9 against §9: the keep list includes Stage 1 code (difference facts, definedness guards, behaviour pruning) that §9 leaves ("beyond the three pieces above"). docs-v2tex.md §6.2 lists seven salvageable Stage 1 pieces.
14. §4.2, Appendix E: "about 17 years" is from memory; the overview-paper claim was checked against the abstract only (lit-discrete.md §3.1).
15. §4.3: "e-graphs, version-space algebras, and finite tree automata are one data structure". lit-discrete.md finding 2: "[V-abs] … a research-level unification, not a shipped product".
16. §4.3: the kernel's 385× is offered as evidence on e-graphs. It measures VM-interpreted rewrite rules used as a cache key (laws-library.md finding 6).
17. §1.5, §5.4, Appendix A: anti-unification "is a product, not a quotient" is used to qualify the owner's wording. lit-discrete.md §6.6: SINGLE-PAPER, "[V-abs; the paper itself could not be fetched]", and the owner's phrase "is best kept as intuition".
18. §4.5: "a hand-set energy with one weight already solves every puzzle". One value for Sudoku-Extreme, three for Maze-Unique (lit-search.md §9.3). Adler–Shavit holds "for a broad class of problems".
19. §6.5: the margin note is read as endorsing local geometric metrics. docs-v2b.md §7: "Its placement is ambiguous. Two readings".
20. §6.6: LAPS sits on DreamCoder with neural search; with human rather than synthetic descriptions "the best graphics run drops from 98.2 to 58.6" (lit-geometry.md §9).
21. §6.3 item 4: random-walk proximity is the same family as Appendix D's rejected "spectral embedding", rejected for weight at a library of a few hundred. docs-v2tex.md §2 row 25 classes Naive Bayes triggers as an academic import at this library size.
22. Appendix E: λ² is "replicated" (lit-search.md §3.2 tags it SINGLE-PAPER; lit-discrete.md tags the family PROVEN-RESEARCH). "Equality saturation | shipped in one compiler": Cranelift is an acyclic e-graph with eager rewrites (lit-discrete.md maturity table).
23. §1.4, §8.1: the text says fifteen tasks; the table has fourteen rows. "between 3 and 703,183" uses the omitted row.
24. §8.1: nested splits overfit on "2 of 8" and "5 of 8". Seed 1 also fails (106/200 and 117/200 in `d.log`): 3 of 9 and 6 of 9.
25. §8.4, §1.4: "Ten hours buys one more node than one hour". For `{+ − * neg}` with dedupe the table says 18 → 20. The by-time rows rest on ratios that "were still rising" (proto.md §4 assumption 2).
26. §8.4: "about ten times the kernel's (§2.3), on four to five times as many rows". §2.3 gives no candidate rate. empirical.md §2 has 118–248 thousand per second (8–17×); search-engine.md §2.1 infers about 21,000 (about 100×).
27. §10: "roughly the parts list of §5". lit-search.md §C item 11 lists "rewrite systems or e-graphs, decision trees", which §5 does not contain.
28. §1.6: "A closed loop in which discoveries become the next round's primitives. No convincing precedent exists". lit-discrete.md §11.4 item 2 is narrower (laws, solvers and abstractions on the *same* store); the abstraction loop exists and "roughly doubles solve rates … then plateaus" (lit-search.md bottom line 7).
29. §5.8 item 2: "no precedent found". lit-search.md §B row 13: inverses "as laws `g(f x) = x`" (QuickSpec) and structural inversion from a table of primitive inverses are PROVEN-RESEARCH; only learned witness functions have none.
30. Header: "The code auditors were told not to read the earlier v2 plans". The README names three of the five; bootstrap-reflection.md §8 compares itself with `plan_v2.tex`.
31. §9 line ranges against counts: `enumerate.lisp:131-214` is 84 lines, given as 148 (search-engine.md: `59-214`); `enumerate.lisp:704-877` is 174 lines, given as ~315 (laws-library.md: `563-877`; search-engine.md counts that engine at ~215).
32. Appendix F harness note: the two "defects" are one defect seen twice (stub left defined, hence the commit error; empirical.md §4.7). The corrected "16, 10, 11, 9" needs a second correction, a clean library per spec (bootstrap-reflection.md §4.2). The plan keeps 8 as the baseline in §2.3 and X3.
33. §6.1: integers "roughly twice the logarithm" (Elias-δ), sequences "an edit script" (core-repr.md §5: aligned "by position only", as §2.7 says).

---

## D. Cosmetic

1. §2.2: "`anti-unify` … and five callers". Six kernel call sites (`abstraction.lisp:106`, `nogoods.lisp:238`, `proposals.lisp:497`, `:1075`, `frame.lisp:1596`, `consolidate.lisp:656`), plus `milestones/corpus.lisp`.
2. Owner quotes silently altered: "is a form of quotienting" adds "is"; "budged" and "hypotheticalyl" corrected; "host Lisp" capitalised; "desirable" in §6.5 against "desireable" in Appendix C.
3. §7.1: "smuggling `map-indexed` into host Lisp" is a paraphrase in quotation marks (docs-v2tex.md: "Smuggled `map-indexed`/`foldl` into host Lisp via higher-order opcodes").
4. §4.1: "Note what that table says". There is no table.
5. Appendix A: "Blocked by eight concrete things" lists six.
6. Appendix F: "about 150,000 words". The fifteen reports are about 174,000 words; 218,000 with the four appendices.
7. Appendix B: "59 pairs became 106" is located in `plan8.md`; it is `plan9-audit.md:331`.
8. Appendix C: the recognizer paragraph is an ink bracket, not a highlight.
9. §2.8: "the reports list eleven or twelve each". docs-plan6-results.md lists ten.
10. §2.3, §7.3: "The kernel's one recursion skeleton". There is also the lockstep form (`decompose.lisp:416-513`).
11. §5.3: length term `(- (length xs) 1)`; the prototype found `(- (len xs) (min (len xs) 1))`.
12. §1.1 item 3: "five orders of magnitude" is tied to 0.4 s; an hour over 0.4 s is four.
13. Appendix A: `target-sensitive-p` has one kernel caller, `orient-conserved-quantity`, which has none.
14. §10: "per both literature reviews". There are three.
15. §8.4: "Largest size fully enumerated" for the two richer grammars is size 9 counted hash-only, which proto.md §4 calls approximate.

---

## Where the reports disagree, and which the plan followed

| Quantity | Reports | Plan |
|:--|:--|:--|
| Synthesis-job throughput | empirical 5.2–6.9 M work/s; search-engine 6.1–8.7 M; bootstrap-reflection 4.5–7 M | empirical |
| 350,000 work in seconds | empirical 0.06–0.07; search-engine 0.04; bootstrap-reflection 0.05–0.08 | empirical |
| Kernel candidates per second | empirical 118–248 thousand (measured); search-engine about 21,000 (inferred) | empirical, unstated |
| Nodes in the stuck search tree | search-engine 2; empirical and bootstrap-reflection 2–3 | both, in different sections |
| Schema-assisted `map-adjacent` size | search-engine 260 bits; empirical 262 | search-engine |
| `positions` without schemas | empirical: solved at 3.6× (full grammar); search-engine, bootstrap-reflection: unsolved at 1,000–2,000× (whitelist) | both, in separate table rows |
| Observation engine line count | laws-library 315 (`563-877`); search-engine ~215 | laws-library, with a third line range |
| Pruning gain | docs-v2tex 6–79× alone, 11–118× with columns; search-engine 11–31× and 26–77×; empirical 470× | docs-v2tex's combined figure |
| ×1000 on all 16 specs | docs-v2tex ran it (12 / 10); empirical ran five specs singly | consistent |
| Undefined exports in `v2/package.lisp` | docs-v2tex ten; core-repr eleven | "about ten" |

---

## Checked and found correct

**Section 8 against the logs.** Every row of the §8.1 table (candidates, times, held-out scores, terms) against `d.log`; 134 of 135 against `dseeds.log`; size-minimal 35–1,100× against `docc.log`; the fold counts 21 / 51 / 157; the 12-operator and 15-operator grammars; the 1.8-million maximum; all §8.2 rows except the `*` time; the boundary artefact (`c.log`, both runs); 60–150× from goal inversion; all §8.3 figures (3,282 / 105 / 59 / 8,889 / ×2.8; false laws 0, 1, 23, 199); all §8.4 table cells against `a.log`; 874 / 206 / 22 lines.

**Section 2 numbers.** Throughput, 350,000 budget, 0.4 s bootstrap, the four-row budget ladder, 2.83 × 10⁹ and 8,085×, ×1.38–1.50 per bit, 18–23 bits, 53–63 and 132–259 bits, 430 bytes, 11 GB, 109,012 work, 99.0–99.8%, 315,388 / 767, 70 against 47 bits, 187 / 14 equations, 182 k / 741 k / 70.2 M and 385×, the §2.5 provenance table, 19%, 8 atoms, 9 of 10, 20 of 21, 2.4×, 3 of 8 at 25–42 thousand, the predictor's 40 of 42 labels and +0.02%, 2,332 work, 4–60 ms, 7.5·n², 430,941, the operator prices, 3,334 against 2,000, 44 s, 900 → 4,600 → 17,647, 1,393 lines, 64 runs, 21 of 40.

**Code citations (24 checked, all land).** `frame.lisp:7-10`, `:14-24`, `:221-222`, `:508-518`, `:544-580`, `:1214-1256`, `:1533`; `synthesize.lisp:290-320`, `:447-457`, `:636-642`; `consolidate.lisp:709-735`, `:1209`; `decompose.lisp:341-382`; `vm.lisp:384`; `enumerate.lisp:426-441`; `laws.lisp:215-228`, `:1250-1327`; `evidence.lisp:62-73`; `unify.lisp:36-73`; `v2/ast.lisp:1096` and `:673`; `v2/package.lisp:66-69`; the `recursion-schemas.lisp` header; `body-size` docstring; file lengths of `codec`, `evidence`, `persistence`, `messages`, `abstraction`; the 17,647 total.

**Owner quotations.** The quotations from `plan_v2_prompt.md` in Appendix A and §§2, 5, 6 match the file apart from the edits in D2. The October and batteries quotations match their files (dating: C9). The margin notes the plan quotes match docs-v2b.md §7. The plan-7 quotations match at the cited lines (L437, L641, m9 L5, recursion L65-67, L97).

**Literature.** Matches the reports: AC saturation 2ⁿ − 1; Cranelift 1.13 and 0.1%; 6–178×; "impractical for most applications"; λ² 0.43 s; 7,700 CPU-hours; Myth 0.07 → 128 s; QuickSpec 398 / 33 / 42 min; Ruler 350 s; Chompy 26 min; PIE 87 of 101; 65%; Probe 91 / 44; LAPS 42.6 → 82.0; PRODIGY 4–6%; one reuse in 20,000; Adler–Shavit bounds; the four pricing rules; the CRAM description; the two quoted cautions; the declared verification gaps.

**Appendix D.** All sixteen rows and reasons match docs-v2tex.md §3.1 (one rejected mechanism with a counterpart in the plan is not listed: B11).

**Appendices C and F.** The annotation counts (28 / 11 / 14 / 3), the four missed notes, the five missing documents, the `architecture2.md` drift, the `v2` construction failure and the evidence soft spots match docs-v2b.md, docs-plan7-arch.md, docs-plan8-9.md, docs-v2tex.md, core-repr.md and laws-library.md.
