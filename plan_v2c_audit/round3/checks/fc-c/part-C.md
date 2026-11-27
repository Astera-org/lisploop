# Fact-check, round 3, scope C, slice: sections 4 and 5 (frozen-copy lines 348 to 625)

Line numbers are those of `v3-for-check.md`. The eighteen section files `sections/04.*.md` and `sections/05.*.md` were confirmed to be contained verbatim in the frozen copy. Scripts are in `round3/fc-c/` (`C-diff.sh`, `C-terms.sh`, `C-annots.py`; `C-pdf/` holds decompressed copies of the three annotated PDFs, made so that the owner's notes could be read at the source).

## A note on paths, not a finding

While this check was running, at about 19:01 on 26 November, someone outside the check moved the root kernel files of `/home/tlh24/lisploop` (all root `*.lisp`, `bootstrap/`, `deprecated/`, `experiments/`, `milestones/`, `plan7/`, `tests/`, and several older documents) into a new directory `v1/`. Nothing in this check wrote to the repository. The content of the files is unchanged, so no citation below is reported as broken on that account: a path such as `unify.lisp:103` or `deprecated/plan3.md` is read at `v1/<same path>` in the working tree, or at the path as written in commit `31d5ae7`. The parent may wish to decide whether the plan's front matter should say which of the two its paths refer to.

## Findings, most serious first

**1. FACTUAL ERROR. A code reference that does not do what the sentence says, and an attribution that plan 3 does not make in those words. Added by the rewording; no gap-log entry covers it.**

Line 553: "The kernel does this on frames (§2.1; `frame.lisp:544`, `unify.lisp:103`), and plan 3 already described lift as a pullback of this kind (`deprecated/plan3.md` §3)."

What the sources say. `frame.lisp:544` is `pullback-frame`, whose docstring begins "B(z)=A(d(c,z))", so that reference is right. `unify.lisp:103` is `compile-au-constructor`, whose docstring is "A DSL program maps quoted hole fillings to the instantiated quoted expression." It builds a decoder from an anti-unification pattern. It does not pull a requirement back, and it does not act on a frame (`laws-library.md:214` describes it the same way). The two references come from one row of the former Appendix B (`sections.preclarity/AB.0.md:13`), which carried two separate ideas: "Lift as predicate pullback, B(z) ⇔ A(d(c, z))", which goes with `frame.lisp:544`, and "Pattern instantiation is the decoder", which goes with `unify.lisp:103`. The rewording attached both references to the first idea. Second, plan 3 never uses the word "lift" (a search of `deprecated/plan3.md` finds none). Its §3 (L122 to L148) defines the requirement on a child as B_i(z) ⇔ A_i(d(c_i, z)). It is the document auditor who calls that a definition of lift (`docs-origins.md:603`, "lift is defined here as pulling a *requirement* back along a decoder").

Replacement: "The kernel does this on frames, in `pullback-frame` (§2.1; `frame.lisp:544`). Plan 3 already defined the requirement on a child problem by a pullback of this kind, B(z) ⇔ A(d(c, z)) (`deprecated/plan3.md` §3), and the document auditor reads that definition as the first statement of lift (docs-origins report)."

If the second reference is wanted, it belongs in §5.4, with the instance space: "The kernel already compiles an anti-unification pattern into the decoder that rebuilds each instance from its hole fillings (`compile-au-constructor`, `unify.lisp:103`)."

**2. INCONSISTENCY. A pointer into the rewritten §6 that does not land, on a sentence that the rest of the document now argues against.**

Line 362: "Treat the choice of a small grammar for each problem as the main control problem (§6.4)."

What the frozen copy now says. §6.4 (lines 698 to 737) is about words and verb tables. It never discusses choosing a small grammar for a problem. The text that this pointer used to reach was the old §6.3, "The control problem with the most leverage is choosing what to mix into each problem ... Choosing a small grammar is its commonest form (§4.1)" (`git show HEAD:plan_v2c.md`, line 612), and that text is gone. What replaced it says the opposite: line 619, "What did save work avoids choosing a subset at all"; §8.6 (lines 1153 to 1162), where a grammar restricted by the nearest problems cost 0.95 to 1.09 of the full cost, summed over tasks, and only an oracle's choice gave a factor of 12; and experiment X4 (line 1404), none of whose five arms selects a subset. The gap log flagged this pointer as needing a check once §6 settled (`clarity-gaps-sec4-9.md:59`), and it was left as it was.

Replacement: "Treat what a search tries first, when many library entries are in scope, as the main control problem. Choosing a small grammar for each problem would be worth about a factor of 12 if the choice were right, and the one way of choosing that was measured saved nothing (§8.6). The plan therefore orders and filters candidates with verb tables, and does not choose a subset (§6.4)."

**3. INCONSISTENCY. A sentence added by the rewording asserts a mechanism that the design, six lines earlier, says it avoids.**

Line 625: "There the kernel has to select which library entries go into each problem's grammar."

Source. The pre-clarity text said only "as context selection". The clarity review's suggested rewrite (item A45) expanded it into this sentence. Line 619 of the same section says "What did save work avoids choosing a subset at all", the table at line 597 prices that selection as "exponential in the library", and §11.3 gives Stage C "the vocabulary of §6.4 and §6.5 (words chosen by score, verb tables, name prices)" and no step that selects entries.

Replacement for that sentence and the one after it: "There, many library entries are in scope at once, and the outcome depends on which of them a search tries first. The plan does not select a subset of the library for each problem, because the one measurement of that saved nothing (§8.6). It orders and filters candidates by the quotients and verb tables of §6.4, which are first used in Stage C, and analogies between operator tables are found there as terms (experiment X9, §11.2)."

**4. INCONSISTENCY. A leftover of the old "retrieval index".**

Line 621: "The order of attack is fixed by cost: refute with invariants; propose with the index; try a key term; refine; and only then backtrack."

What the frozen copy now says. No index is defined anywhere in §5 or §6. The only indexes left in the document are the ones that lost: line 917, "an index of past problems found 19 at best ... The ones tried did not earn their place", and line 1268. §1.5 (line 101) was already updated to say "run only on the pairs that cheaper signals propose (§5.9)". This sentence was not.

Replacement: "The order of attack is fixed by cost. First refute with invariants. Then propose pairs with the cheap signals listed above, labels first. Then try a key term, then refine, and only then backtrack."

**5. OVER-STATEMENT. The paragraph on arXiv 2611.17309 was strengthened in the rewording, and it now says that a claim holds which no source in the audit checks.**

Line 400, three sentences:
(a) "The paper you cited in the margin, arXiv 2611.17309, supports this."
(b) "Your note on the paper said that "it took several years for it to become 'too easy'", and that "I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else.""
(c) "Both halves of your note hold, and the second is the one that matters here: the bits of the answer come from fast evaluation, not from the model."

What the sources say. The two quotations in (b) are verbatim; I read the note in `plan_v2c_annotated.pdf` itself. (a) The pre-clarity text said "bears on this". "Supports this" comes from the clarity review's suggested wording (item C2) and from no source. The two literature auditors who read the paper concluded otherwise: "The result is about a *tiny hypothesis space matched exactly to the problem* plus a *local training objective*, not about fast evaluation of a large search space" (`lit-search.md:574`); "it does not say what the owner's gloss says" (`lit-geometry.md:46`); "What transfers to symbolic program/law search. Plainly: little" (`lit-search-appendix-sci.md:496`). The plan may side with the owner's reading, but it should not present the paper as support without saying that its own auditors read it differently. (c) Before the rewording, "both halves" followed a description of the paper's cheap moves, and had no stated referent. The rewording made the first half the claim that the benchmarks took "several years" to become too easy. No report measures or cites that. The revision notes only say "agreed that it took years". The middle of the note, which the plan does not quote, is the part the paper's text fails to bear out: "700-900 flops per move" and "a B200" are not in the paper, which reports an H200 (`revision-notes.md:117`; `factcheck2-A.md:203`).

Replacement for the three sentences: "The paper you cited in the margin, arXiv 2611.17309, bears on this. Its model is small and represents the rules of the puzzle exactly, and its answers come from a very large number of very cheap moves. Its authors add that these benchmarks are too easy, and that learning latent quantities "remains an important open research direction". Your note on the paper said that "I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else." For this paper that holds: a model with one hand-set weight already solves every puzzle, so the bits of the answer come from the search and not from the model. The two literature auditors drew a narrower lesson, that the paper's hypothesis space is tiny and matched to the puzzle and that little of it carries over to program search (lit-search report, §9.3). Either reading argues for an exact store with cheap evaluation, and not for a learned embedding. Your note also said that "it took several years for it to become 'too easy'"; the audit has no source on that, and the authors' remark is about what the benchmarks can show today."

**6. OVER-STATEMENT. "Fitted to" four enumerators, and then "agrees with" the same four.**

Line 358: "The search-literature auditor fitted a model to four published enumerators, and the model agrees with their measured sizes to within a node or two."

What the source says. The model's three parameters were set from anchors drawn from many systems (`lit-search-appendix-enum.md:385` to `:392`: evaluation rate from Bustle, Massalin and STOKE; candidates per class from Probe, ESR, QuickSpec and TRANSIT; branching from the growth table). It was then *checked* against outcomes: "Checks against A.2: ... EUSolver's 9–12 and Probe's 6.5–7.9 ... TRANSIT's 15 and Probe's failure at 19 ... TF-Coder's plain-enumeration ceiling ... Agreement is within about ±2 nodes" (`lit-search.md:641`). The gap-log entry A31 supplied "agrees with their measured sizes" from that line and kept the older word "fitted". As the sentence now reads, the model agrees with the data it was fitted to, which would be no evidence at all, and is not what was done.

Replacement: "The search-literature auditor built a model of enumeration from growth figures in the published systems, and then checked it against the program sizes that four published enumerators reached (EUSolver, Probe, TRANSIT and TF-Coder). It agrees with them to within about two nodes."

**7. MISSING CAVEAT. The sentence added for "depth two" asserts the link that the gap log marked UNFILLED.**

Line 531: "Experiments to depth two are your requirement from October (§2.8)."

What the source says. The October text is "do the same for all the other elementary operators in the toolbox, including negation, up to (say) depth=2 (this is essential!)" (`deprecated/plan.md` L86 to L88). That is about running operators composed two deep. The gap log says in so many words that this "does not confirm the review's reading (functions among the inputs)" and that no definition was written (`clarity-gaps-sec4-9.md:50`). But the new sentence stands directly after the heading "Depth-two experiments are spaces whose cells hold terms" and before "A space whose rows range over `(f, g, xs)`", so it tells the owner that this construction is the October requirement. The nearer support is the current prompt: "Algebra emerges from running parallel and depth >= 2 experiments on the simulator, showing that expressions themselves can be abstracted over in the same way" (`plan_v2_prompt.md:2`).

Replacement: "In October you asked for experiments on operators composed "up to (say) depth=2" (§2.8), and your current prompt says that "depth >= 2 experiments" show "that expressions themselves can be abstracted over in the same way". This plan reads the second as experiments whose inputs include functions. That reading is the plan's own."

**8. MISSING CAVEAT. Counts are listed as a cheap signal with no word of what was measured about counts.**

Line 617: "The fourth is a count of which pairings paid off before."

What the frozen copy now says. §8.8 item 8 (line 1281): "Counts become a correction to the tables." §10 risk 4 (line 1346): "Counts over tens of solved problems carry no signal." §6.4 (line 719): counts used as prices "sent 5 of 8 such tasks past the search's cap". A count of pairings was never measured. Of the four signals, only the first was measured as a way to propose pairs (§8.6), and line 619 reports that it found form and not operators.

Replacement: "The fourth is a count of which pairings paid off before. That one has not been measured, and the counts that were measured, of operators' past use, said nothing about an entry not yet used (§8.7), so a count can only adjust what the other three propose."

**9. INCONSISTENCY, minor. "Retrieval" is the old term, and retrieval is the use that the measurements did not support.**

Line 402: "A flat space is the right shape for *retrieval and ranking*, and the wrong place for truth."

What the frozen copy now says. The next sentence was updated to "a layer over the exact store that ranks and filters". Retrieval of similar problems by flat properties found the form of a program and not its operators (§8.6), and an index of past problems found 9 to 19 of 25 repeats where plain replay found all 25 (line 1268).

Replacement: "A flat space is the right shape for *ranking and filtering*, and the wrong place for truth."

**10. OVER-STATEMENT, minor, older than this round. "Each extra level" is not what the report's figure measures.**

Line 408: "Each extra level of interpretation costs a factor of 6–178, until that level is compiled away by staging **[L]**."

What the source says. "staging gives 7–87× on ground functions, 6–178× through nested interpreters, 2–49× with a sketch" (`lit-discrete.md:243`), and "Measured benefit in a search setting: 6–178× through nested relational interpreters" (`:436`). The figure is the speed-up that staging gave on the benchmarks that run through nested interpreters. Neither line says that each level costs that much.

Replacement: "In the same paper's measurements, staging made the benchmarks that run through nested interpreters 6 to 178 times faster **[L]**."

**11. OVER-STATEMENT, minor. "One research group only" covers two different things in the source.**

Line 376: "Binders and conditional equalities inside e-graphs have been done by one research group only **[L]**."

What the source says. "Slotted e-graphs (binders) | SINGLE-PAPER | PLDI 2025 + one 2026 preprint" and "Colored e-graphs (conditional equalities) | SINGLE-PAPER | One group, two papers" (`lit-discrete.md:48`, `:49`; also `:541`, `:542`). "One group" is said of conditional equalities only, and the sentence as written can be read as one group having done both.

Replacement: "Binders inside e-graphs rest on one paper and one preprint, and conditional equalities inside e-graphs are the work of one research group **[L]**."

**12. INCONSISTENCY, minor, older than this round. "Its one impostor".**

Line 545: "The prototype does not do it, and returned its one impostor as an answer (§8.1)."

What the frozen copy says. §8.1 reports the one miss in 135 default runs (line 1037) and a second impostor under the larger grammar (line 1039). §8.5 reports impostors returned on the kernel's spec rows for `map-adjacent`, `foldl`, `best-shift`, `argmax-corr`, and two reductions without lifting (lines 1112 to 1116).

Replacement: "The prototype does not do it. In its 135 default runs on its own rows it returned one impostor as an answer (§8.1), and on the kernel's much shorter spec rows it returned several (§8.5)."

**13. COSMETIC. The pointer to the revision notes promises details that the notes do not all carry.**

Line 400: "The details of the paper, and the full answer to your note, are in `plan_v2c_audit/revision-notes.md`."

The cut (clarity review, C2) removed five details from §4.5. The draft `revision-notes.md:117` carries the Triton kernels and the 2.0 × 10⁹ FLOPs. It does not carry "fitting it takes milliseconds" or "one hand-set value already solves every Sudoku puzzle, and three every maze". Those two facts are now nowhere in the plan or the notes. They are in `lit-geometry.md:551` to `:559` and `lit-search.md:571`. If finding 5's replacement is used, the hand-set weight returns to the text. Otherwise add one sentence to the notes: "The paper fits its model in 42 ms and 132 ms, and a hand-set energy with one distinct weight solves every Sudoku test puzzle, and one with three solves every maze."

**14. COSMETIC. Two phrases in quotation marks have no source.**

Line 608: "It is the "graph walker": a colour that flows along verified links." Line 609: "This is the "graph isomorphism engine"."

Neither phrase is in any repository document (`factcheck2-A.md:214`, and the gap log's UNFILLED entry A45). The owner's prompt has "an efficient graph isomorphism test" and "proximity flows along verified topological links" (`plan_v2_prompt.md:10`, `:7`). If the phrases are from the owner's unfiled request they should be attributed. If not, the marks should go.

Replacement for 608: "It is a walk over the graph: a colour that flows along verified links, as in your phrase "proximity flows along verified topological links"." Replacement for 609: "This is the isomorphism test that your prompt said might be needed."

**15. COSMETIC. The caption's rule for bold does not fit two rows.**

Line 416: "Bold marks the cells that the proposal of §5 takes up: for each operation, the perspective that the paragraph after the table names as supplying it."

The bold cells do match the paragraph, cell for cell, as the gap log says. But the row "Substitution, composition" has no bold cell, the last row ("Mature at the scale needed") is not an operation, and for "Closeness" the measure the plan itself calls bedrock is the per-column codes of §6.1, which is the relational cell and is not bold.

Replacement: "Bold marks, in each row, the perspective that the paragraph after the table names as the plan's source for it. The first row has none, because every perspective supplies substitution."

**16. COSMETIC, older than this round. "Three short routines".**

Line 521: "The prototype implements it as three short routines, 22 lines, and uses them only for lifts over output and input positions."

`proto.md:51` lists four functions in those 22 lines, "`explode`, `pull`, `collect`, `elt-col`", and `proto/tg-probe.lisp:255` to `:268` has the four definitions.

Replacement: "The prototype implements it as three short routines and one helper, 22 lines in all, and uses them only for lifts over output and input positions."

**17. COSMETIC. One of the three results under a single [L] was not checked online.**

Line 396: "Three results show it **[L]**. First, a tree can be embedded exactly in a flat space."

`lit-geometry.md:320` to `:322`: the measured result (Hewitt and Manning) was verified, and "Any tree embeds exactly this way with about one axis per edge" is tagged `[FROM-MEMORY, textbook]`. The construction in the plan's next sentence proves the claim, so nothing is wrong, but Appendix C's list of what was not checked online leaves it out. Either tag the first result **[L, from memory]** or add it to that list.

**18. COSMETIC. The outline does not call the matching problem by that name; it says the other thing is a matching problem.**

Line 615: "It calls the matching problem "the quotienting-AU problem" (AU is anti-unification) and describes it as "structure & type-aware & locality-seeded"."

`prompt4.md:170`: "This makes the quotienting-AU problem that of a structure & type-aware & locality-seeded subgraph isomorphism problem." The quoted pieces are verbatim. The outline names the problem of quotienting and anti-unifying, and says that it is a matching problem.

Replacement: "It says that "the quotienting-AU problem" (AU is anti-unification) is a subgraph matching problem that is "structure & type-aware & locality-seeded"."

## Changes against the pre-clarity version

"Review" items are those of `clarity-review.md`. "Gap" entries are those of `clarity-gaps-sec4-9.md`.

| File | Change | Kind | Supported by |
|:--|:--|:--|:--|
| 04.1 | "8, 10, 10, 10 of 16 over three decades" became "only two more of the sixteen specs" | numbers dropped | Review B5. The figures remain in §2.3. Supported. |
| 04.1 | "the search tree stayed at two nodes" became "stayed a root with one or two children" | claim changed | Review A5, and `empirical.md:293-297` (2 or 3 nodes). Supported; it corrects the older wording. |
| 04.1 | "4.5 decades, so five to nine nodes" became "4.5 tenfold steps, so it adds between five and nine nodes to the largest program reached" | reworded | Review A31. Supported. |
| 04.1 | added "agrees with their measured sizes" | claim added | Gap A31 (`lit-search.md:641`). Supported, but "fitted" was kept: finding 6. |
| 04.1 | added "which is about 7,700 CPU-hours" | number added | Gap A48 (`lit-discrete.md:32`; 5 × 24 × 64 = 7,680). Supported. |
| 04.1 | "every record" became "the kernel's records, which are its trace, the syntax it retains, and its list of sub-problems" | definition added | Gap A32 (`search-engine.md:1053-1054`). Supported. |
| 04.1 | pointer "(§6.4)" kept | pointer | UNSUPPORTED: finding 2. |
| 04.2 | the parenthesis on what the auditor checked became **[L, from memory]** and **[L, abstract only]** | tags added | Review B4; `lit-discrete.md:187`, `:189`. Supported. |
| 04.2 | added "(§2.8)" | pointer added | Review B1. Lands (line 306). |
| 04.3 | added "that is, until no law adds a new equality" | definition added | Review A56. Supported. |
| 04.3 | "are single-group research" became "have been done by one research group only" | claim reworded | Gap A56. Partly supported: finding 11. |
| 04.3 | "which the auditor verified from abstracts" became **[L, abstract only]** | tag added | Review B4; `lit-discrete.md:29`. Supported. |
| 04.4 | two quotations dropped ("No column is designated as input or output"; "via the exchange of input and outputs") in favour of "(§2.8)" | quotations dropped | Review B1. Both remain at line 300. Supported. |
| 04.5 | the three results separated; superposition defined | reworded | Review A33. Supported. |
| 04.5 | "verified against the paper" dropped; **[L]** kept | tag text dropped | Review B4. Supported. |
| 04.5 | "n neurons compute at most about n² features" dropped | number dropped | Review A33 and B11. Appendix C keeps the bound. Supported. |
| 04.5 | "a broad class of problems" became "a broad category of problems" | reworded | Review A12 (keeps "class" for the store's term). Supported. |
| 04.5 | dropped: "small pairwise energy"; "fitting it takes milliseconds"; "one hand-set value already solves every Sudoku puzzle, and three every maze"; the Triton kernels; "2.0 × 10⁹ FLOPs per Sudoku"; "scheduled lowering" | numbers and claims dropped | Review C2. Supported as a cut, but two of the facts are in no other place: finding 13. |
| 04.5 | "bears on this" became "supports this" | claim strengthened | Review C2's suggested text; no source. UNSUPPORTED: finding 5. |
| 04.5 | two quotations of the owner's note added | quotations added | Gap A34. Verbatim against the annotated PDF. Supported as quotations; what the plan then says of them is finding 5. |
| 04.5 | pointer to `plan_v2c_audit/revision-notes.md` added | pointer added | Gap A34. The draft exists and has the row (line 117). |
| 04.5 | Take: "feature vectors as an index over the exact store (§6.4)" became "features, which here are the labels of §6.2, as a layer over the exact store that ranks and filters (§6.4, §6.6)" | claim and pointers changed | Review A55. Lands. "Retrieval" left behind: finding 9. |
| 04.6 | **[L, abstract only]** added for FlashMeta's deployment | tag added | Gap B4; `lit-discrete.md:31`. Supported. |
| 04.6 | "its authors" became "The relational interpreters of miniKanren ... the authors of a 2025 paper on them" | attribution added | Gap A35 (`lit-discrete.md:238-241`). Supported. |
| 04.6 | "pullback is 37 sound lines" became "already sound, and small" | number dropped | Review B12. Stays in §2.1 and §9. Supported. |
| 04.6 | "(§5.4, measured in §8)" became "(§5.3, §5.4; measured in §8)" | pointer added | Review A37. Lands. |
| 04.6 | owner's phrase on reentrancy quoted; the tower sentence expanded | quotation added | Gap A35. Verbatim (`plan_v2_prompt.md:5`). Supported. |
| 04.7 | heading changed; caption added | definitions added | Gap A36 (`lit-discrete.md:543` for "(2026)"). Supported; finding 15 on the rule for bold. |
| 05.1 | "As §4.2 observed" | pointer added | Review B13. Lands. |
| 05.3 | "This plan calls the check the *dependency test*"; gloss of `tabulate` with "(§7.1)" | definitions added | Review A37. Both match the Terms table and line 827. Supported. |
| 05.4 | "n is the number of rows"; definition of `select` | definitions added | Gap A38. `proto/tg-probe.lisp:239`; `proto.md:94`. Supported. |
| 05.4 | "`plan_v2b.md` (its §7.3) listed six moves on its store" | attribution added | Gap A38 (`docs-v2tex.md:617`; `plan_v2b.md:469`; the note itself in `plan_v2b_annotated.pdf`). Supported. |
| 05.4 | plain-words definition of anti-unification | definition added | Gap A56 (`lit-discrete.md:342`). Supported. |
| 05.4 | "a single paper the auditor could read only in summary" became **[L, summary only]** | tag added | Review B4; `lit-discrete.md:380`. Supported. |
| 05.4 | "same signature" became "same type signature" | reworded | Gap A24; `anti-unify` compares `operator-type` (`unify.lisp:36-58` at HEAD). Supported. |
| 05.4 | "took one pattern from five holes to two" became "gave a pattern with fewer holes (§2.8)" | numbers dropped | Review B1. Line 305 keeps 5 and 2. Supported. |
| 05.4 | "the last of the four stages in which this plan is to be built (§11.3)" | gloss added | Review A1. Lands. |
| 05.4 | "Experiments to depth two are your requirement from October (§2.8)" | claim added | Gap A38 is UNFILLED. Finding 7. |
| 05.5 | the Tested grade written out; "which §6.2 calls verb tables ... (§6.4)" | reworded, pointers | Review A39 and A55. Both land (lines 660, 724). |
| 05.5 | "of §2.3, in which a program fits the spec's rows and is wrong"; definition of probe space | location and definition added | Gap A9. Matches line 192, line 932 and the Terms table. Supported. |
| 05.5 | quotation "the unresolved information is the membership of each input in its valid subset" dropped for "(§2.8)" | quotation dropped | Review B1. Line 303 keeps it. Supported. |
| 05.6 | "in 37 lines" dropped | number dropped | Review B12. Supported. |
| 05.6 | added "(§2.1; `frame.lisp:544`, `unify.lisp:103`), and plan 3 already described lift as a pullback of this kind (`deprecated/plan3.md` §3)" | references and claim added | From the former Appendix B row (review B1 and C1). No gap-log entry. UNSUPPORTED in part: finding 1. |
| 05.8 | "The same review" became "The outside review also" | attribution fixed | Gap A40 (`plan_v2c_audit.md:31`). Supported. |
| 05.8 | "keeps laws by use" became "keeps a law only when something reads it"; "Experiment X1 (§11.2), which runs law discovery on the new store" | reworded, gloss | Review A40. Matches lines 1278 and 1401. Supported. |
| 05.9 | definition of *witness* | definition added | Review A8. Supported. |
| 05.9 | "the outside review calls this "probe evaluation"" | attribution added | Gap A56 (`plan_v2c_audit.md:39`). Supported. |
| 05.9 | "a signature that flows" became "a colour that flows" | reworded | Review A8 (one sense per word). Supported. |
| 05.9 | "In the version measured it is 65 lines on top of 36 for refinement" dropped from the backtracking bullet | numbers dropped | Review B11. Line 623 keeps both; they match `cross-space/xs-m3.lisp` lines 37-72 and 73-137. Supported. |
| 05.9 | "Symmetric structures matched against their own copy needed choices, and none had to be undone." dropped | claim dropped | Review B11. Line 1186 keeps it. Supported. |
| 05.9 | "Plan 2 recorded this in October" became "the finding that plan 2 recorded in October holds (§2.8)" | pointer added | Review B1. Lands (line 306); plan 2 was committed on 19 October. Supported. |
| 05.9 | the aligner paragraph split; *selective* defined; "the `gather` rule (§7.2)" | definition, pointer | Gap A43. Lands (lines 855, 865). Supported. |
| 05.9 | "the quotienting-AU problem" quoted | quotation added | Gap A41. Verbatim (`prompt4.md:170`). Finding 18 on the verb. |
| 05.9 | "(`plan7/plan7-library.md` §2.2.3)" | reference added | No gap-log entry. Checked: item 3 of §2.2, lines 56-57; never built (`docs-plan7-arch.md:200`, `:454`). Supported. |
| 05.9 | four signals numbered; "These first two are the two resolutions of §6.2, coarse and full" | claim made explicit | Gap A42. Matches lines 655 to 660. Supported; finding 8 on the fourth. |
| 05.9 | "The compromise" became "How the two kinds of work are budgeted"; "(X9)" became "(experiment X9, §11.2)" | reworded | Review A45, A40. Lands. |
| 05.9 | "a product of two automata and quadratic in the corpus; this is deferred to Stage D" became "which §5.4 prices and defers to Stage D (§11.3)" | claim replaced by pointer | Review B11. Lines 527 and 529 carry it. Supported. |
| 05.9 | "accepts an abstraction only when it shortens the total description" | gloss added | Gap A44. `abstraction.lisp:385-386` at HEAD: "only when it strictly improves description length above MIN-GAIN", default 0. Supported. |
| 05.9 | stages paragraph: "as context selection" became "There the kernel has to select which library entries go into each problem's grammar" | claim added | Review A45. UNSUPPORTED by the new §6: finding 3. The other additions there (four stages, "the store core", "adds requirements with holes and spaces with maps") match §11.3. |

Files 04.0, 05.0, 05.2 and 05.7 changed in wording only, or not at all.

## Cross-references checked

| Pointer | Line | What the sentence promises | Lands? |
|:--|--:|:--|:--|
| §2.3 (twice) | 356 | budgets were milliseconds; budget alone does not help | yes |
| §6.4 | 362 | the choice of a small grammar for each problem | **no** (finding 2) |
| §2.8 | 368 | matching is conjunctive-query matching | yes, line 306 |
| §2.4 | 376 | 385 times the work with 80 laws | yes, line 229 (182,000 against 70.2 million; `laws-library.md:239-241`) |
| §5.5 | 380 | a law says a class is real beyond its rows | yes |
| §2.8 | 386 | relations before directions | yes, line 300 |
| §6.2; §6.4, §6.6 | 402 | labels; a flat layer that ranks and filters | yes (lines 653, 716 to 720, 792). Line 792 says "the labels of §6.4" where lines 102 and 402 say §6.2; labels are defined in §6.2. |
| §2.1 | 408 | pullback is sound and small | yes |
| §5.3, §5.4, §8 | 410 | dependency test; reorientation; measured | yes (lines 482, 514, 1043 onward) |
| §7.1 | 412 | one evaluator whose terms mention terms, spaces and requirements | yes, line 839, though §7.1 says it as "the store's own operations are ordinary programs" |
| §4.1, §5 | 416, 429 | budget-only column; the proposal | yes |
| §4.2 | 437, 467 | N copies of one graph; factorization | yes |
| §5.5 | 463 | evidence grade | yes |
| §7.1 | 494 | `tabulate` builds a sequence from a length and a function of position | yes, line 827, same words |
| §2.3, §8.1 | 496 | 2.8 × 10⁹; a quarter of a second; five seconds; twelve examples against eight | yes (line 190; lines 1017, 1027; `proto.md:74`, `:397`) |
| §8.1 | 500 | `select` is how the prototype writes `filter` | yes, line 1024 |
| §8.5 | 525 | `anti-unify` gives one shared hole | yes, line 1135 |
| §5.9, §11.3, §2.8 | 529 | search across spaces; Stage D; quotienting by laws | yes (Stage D: "abstraction over classes"; line 305) |
| §2.8, §10 | 531 | the October requirement; no precedent | lands; finding 7 on what is claimed |
| §2.4 | 535 | nothing learned prunes on the integers | yes, line 228 |
| §6.2, §6.4 | 540 | verb tables defined; tested grade | yes |
| §9 | 543 | evidence record, tentative and fallback, root verification carried over | yes (lines 1298, 1307, 1311) |
| §2.3, §8.1 | 545 | the `foldl` impostor; the prototype's impostor | yes; finding 12 |
| §2.8 | 547 | a guard is what a law leaves unresolved | yes, line 303 |
| §2.1; §9 | 553 | pullback on frames; the same soundness tests | yes; code reference wrong (finding 1) |
| §7.2 | 555 | what each construct does to a requirement | yes, table at 847 to 861 |
| §2.9 | 557 | neither earlier plan made lifting a requirement an operation | yes, line 324 |
| §7.4 | 563 | the derivation space and its columns | yes, line 913 |
| lit-search report, section B | 567 | the recommended recipe | yes (`lit-search.md:662`) |
| §5.9; §8.8; §2.4; X1 (§11.2) | 569, 571 | the hard part; laws kept by use; rewriting cost; X1 | yes (lines 1278, 229, 1401) |
| §8 | 579 | the first two measured on a prototype | yes (§8.1, §8.2) |
| §6.2 | 596 | quotient of values | yes, line 653 |
| §5.6, §7.2 | 603 | requirement with a hole; the one move | yes |
| §8.6 | 607, 609 | `max` to `min` under negation; when backtracking was needed | yes (lines 1172, 1182 to 1186) |
| §2.8 | 611 | plan 2's finding on tree-shaped patterns | yes |
| §7.2 (twice) | 613 | mapping output positions to input positions; the `gather` rule | yes (lines 855, 865) |
| `prompt4.md` L170–175 | 615 | three quotations | verbatim |
| `plan7/plan7-library.md` §2.2.3 | 615 | graph distance between library entries seeds anti-unification | yes (item 3 of §2.2, lines 56 to 57) |
| §6.2, §6.1 | 617 | labels; the cost of one column given another | yes |
| §8.6, §8.7, §6.4 | 619 | form at three times chance and no saving; tables tested before evaluation | yes (0.48 and 0.54 against 0.15; 0.77 to 0.83 against 0.73) |
| §8.6; §9; X9 (§11.2) | 621 | 257,214 backtracks on 30 rows; three to one; X9 | yes (`cross-space/logs/m3.log:40`; line 1307; line 1409) |
| §5.4; §11.3; §9 | 623 | prices and defers anti-unification over classes; Stage D; abstraction code carried over | yes (lines 527 to 529, 1418, 1302) |
| §11.3; §6.4; X9 (§11.2) | 625 | four stages; quotients and tables first used in Stage C; analogies as terms | yes; finding 3 on the added sentence |

## Stale terms, and words used in a second sense, in lines 348 to 625

Old vocabulary still present: "the index" (line 621, finding 4); "retrieval" (line 402, finding 9); "a count of which pairings paid off before" (line 617, finding 8); "the choice of a small grammar" and "select which library entries" (lines 362 and 625, findings 2 and 3). "Property signatures", "usage counts", "signature space" and "four geometries" do not occur in the slice.

Outside the slice, noticed in passing: line 1353 (§10, risk 11) still says "the retrieval measurement of §8.6"; line 1496 (Appendix C) gives "context selection" as a role; line 1133 (§8.5) says "Stage A does not price cell by cell", meaning the kernel's first search phase, with no gloss.

Second senses:

- **Stage.** Lines 529, 623 and 625 all mean the plan's stages A to D. "Staging" at lines 408 and 412 is a different word for compiling a level of interpretation away, and line 412 defines it.
- **Node.** A node of a program's syntax tree (lines 356 to 360, 494, 547). A vertex of a hypergraph whose nodes are values (line 366). A node of an embedded tree (line 396). A place in the execution graph (line 437). A term in the shared term graph (line 461). A class, in "Classes are nodes" (line 467). Lines 461 and 467 are six lines apart and name the vertices of two different graphs.
- **Class.** The store's term everywhere in §5. In §4.3 (lines 376 to 380) it is an e-graph's equivalence class, and line 378 says how the two differ.
- **Fold.** The sequence primitive (line 508) and the combinator DreamCoder rediscovered (line 358) are one sense. "Folded and recursively nested" (line 531) is the owner's word in another sense, inside a quotation.
- **Witness.** "Witness functions of FlashMeta" (line 408) are hand-written partial inverses. In §5.9 (lines 587 to 603) a witness is a map, substitution or pattern that relates two spaces, defined at line 587. Neither is the kernel's "witness", the answer term of §2.5. The document therefore has three senses, and the slice has two.
- **Quotient.** Merging rows, or merging terms into a class (lines 511, 523, 529). A term from values to labels (line 596, glossed "of values (§6.2)"; line 625, "The quotients and tables of §6.4", not glossed). The Terms table at the front defines only the second. Line 615 has the owner's "quotienting-AU".
- **Signature.** Only "type signature" (line 526).
- **Probe.** "Probe space" (line 545, defined there). "Probe evaluation" (line 591) is the outside review's phrase for evaluating on another space, and is attributed.
- **Index.** A position in a sequence ("index set", "index argument", "the indices increase": lines 421, 509, 613). A look-up structure ("index on output", line 422; "a separate index", line 521). The retrieval index (line 621, stale).

## Checked and found correct

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
- The gap log's UNFILLED entries for this slice. "Scheduled lowering" and the hand-set value are gone from the text. The simpler length term is not named. No owner is named for "graph walker". The one that leaks is "depth two" (finding 7).

## Could not check

- The text of arXiv 2611.17309. The reports give "an important open research direction" (`lit-search-appendix-sci.md:492`) and "remains open" (`lit-geometry.md:559`). The fuller quotation at line 400, with "remains", was verified in the previous round against a saved copy of the paper (`factcheck2-A.md:203`) that is no longer in the scratchpad.
- "So the split you describe is exact" (line 599), and the two phrases of finding 14. They may come from the owner's earlier request, which is not in a file.
- The papers behind the literature figures. I checked the plan against the auditors' reports, not against the papers. Finding 10 rests on the report's wording.
- **[L, from memory]** for the smallest-grammar problem at line 594: no report line was found for it, and the tag already says so.
- Checks made after the move of 19:01, against git HEAD or `v1/` and not against the root path: the body of `anti-unify` (`git show HEAD:unify.lisp`, lines 36 to 68), for "same type signature" at line 526; the search of plan 3 for the word "lift" (`git show HEAD:deprecated/plan3.md`), for finding 1; and plan 2's statement on acyclic patterns (`v1/deprecated/plan2.md:241`, `:615`), for the pointer at line 611. Every other read of a moved file (`frame.lisp:544`, `unify.lisp:103`, `deprecated/plan.md` L80 to L92, `deprecated/plan3.md` §3, `deprecated/results.md`, `plan7/plan7-library.md`, `plan8.md:306`, `abstraction.lisp:380-386`, `evidence.lisp`) was made before the move, at the root path. No check failed because a file had moved.
