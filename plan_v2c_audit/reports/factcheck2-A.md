# Fact-check of the revised plan, part A

Checked: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/v2c/dry.md` (line numbers below are `dry.md` lines), the `+` lines of `rev2.diff`, in sections 1–5, 5.9, 6 intro–6.3, 7, 8.1, 8.5–8.7, 10, 11, Appendix A, Appendix F, G.1, G.2 and the "From its first section" table.

Verdict: the numbers are copied correctly almost everywhere. The errors are in wording that generalizes past the data (backtracking, "no work saved"), in two causal claims, in one coding-theory rule, and in a few attributions.

Source abbreviations, all under `/home/tlh24/lisploop/`:
- VR = `plan_v2c_audit/reports/verify-review.md`; VR logs = `plan_v2c_audit/verify-review/logs/`
- XS = `plan_v2c_audit/reports/cross-space.md`; XS logs = `plan_v2c_audit/cross-space/logs/`
- VQ = `plan_v2c_audit/reports/verify-quotients.md`
- REVIEW = `plan_v2c_audit.md` (as it stands now: 323 lines, modified 17:20 on 25 November)

Reports and logs agree with each other wherever I compared them; I found no report-versus-log discrepancy.

## Findings, most serious first

### 1. FACTUAL ERROR — when backtracking is needed (lines 551, 860, 67, 1067, 1265)

- L551: "It is about a hundred lines on top of refinement, exponential in the worst case, and needed only for highly symmetric structures (§8.7)."
- L860: "exponential in the worst case; needed only for symmetric structures (§8.7)"
- L67: "Matching rows with no key needs no search on irregular data and backtracking on regular or symmetric structures."
- L1067: "Irregular structure is matched by refinement, with no search. Regular structure needs backtracking in proportion to its size."
- L1265: "Not on irregular data; at once on regular or symmetric structures"

Source (XS:389–400; XS logs `m3.log`): the data run the other way on symmetry.
- Symmetric structures matched against their own copy needed choices and **zero** backtracks: one cycle (1 choice), the 30 × 30 grid (2), five hexagons against five hexagons (5). XS:391: "what refinement leaves undecided is symmetry", "every choice was right, 0 backtracks".
- Backtracking occurred on "Regular graphs with no symmetry (random 3-regular)" (XS:397, about n/2 backtracks), on non-isomorphic pairs that must be rejected, and on one mixed isomorphic pair (two triangles and a hexagon: 4 backtracks).
- "Irregular … with no search" also overstates. The random tree row in the document's own table has 6,547 of 10,000 matched by refinement alone and 1,586 choices in 5.4 s. Only "no backtracking" is supported.

Proposed, L551: "It is about a hundred lines on top of refinement and exponential in the worst case. In §8.7 it was needed for regular structures that have no symmetry, and to reject look-alikes that are not isomorphic; symmetric structures matched against their own copy needed choices but no backtracking."
Proposed, L67 and L1265: "Matching rows with no key needed no backtracking on irregular data or on symmetric structures (only choices, up to 1,586 on a 10,000-node tree). It needed backtracking on regular structures without symmetry and to reject non-isomorphic look-alikes."
Proposed, L1067: "Irregular structure is matched by refinement plus choices that are never undone. A regular structure with no symmetry needs backtracking in proportion to its size."
L860: same change as L551.

### 2. FACTUAL ERROR (causal) — why the aggregate does not replace `fold` (lines 1001, 794)

- L1001: "It does not replace `fold`: `last-or`, an alternating sum, and a Horner evaluation need state carried from one element to the next."
- L794: "A fold with sequential state (`foldl` with an arbitrary step, an alternating sum, a Horner evaluation) is not."

Source (VR:149–152) gives three different reasons, and only one is sequential state:
- alternating sum: "It is a pushforward of xᵢ·(−1)^i, but that element term needs about 17 nodes in this grammar … the search stopped at 9. This is a budget limit, not a limit of the mechanism."
- `last-or`: "a fold with an associative step (keep the right argument) whose identity is the input `d`. None of the five fixed aggregates has an identity taken from a base-space column."
- Horner: "No element term in this grammar computes that weight"; this is the review's case.

Proposed, L1001: "It does not replace `fold`: it returned nothing on `last-or`, an alternating sum, and a Horner evaluation, for three different reasons. `last-or` is an associative aggregate whose identity is an input, which none of the five fixed aggregates has. The alternating sum is a sum of xᵢ·(−1)^i whose element term, about 17 nodes, lay beyond the size-9 search: a budget limit. Horner needs a weight that no element term in the grammar computes."
Proposed, L794: drop "an alternating sum" from the list, or write "(`foldl` with an arbitrary step, a Horner evaluation)".

### 3. FACTUAL ERROR — pricing rule 5 (line 596)

L596: "Either one bit per column says whether the column is exact, or every cell's code includes the zero. The kernel escapes this in its main pricing path only because it lists exception rows with their indices."

- The review's fix is both parts together, not either (REVIEW:89: one bit per column, and "inside a non-exact column, code every cell with a true prefix distribution … charging ≥ 1 bit on equal cells").
- The first alternative alone does not repair a column priced row by row. My arithmetic, not a source: for n Boolean cells with a flag bit and exact cells still free, the lengths sum to 1.5ⁿ/2, above 1 for n ≥ 2.
- "Escapes" is too strong. VR:232 and VR logs `r4-kraft.log`:1639–1643: Stage A still under-pays one bit per model (Kraft sum 1.014 to 1.024). §8.6 (L1013) says so; §6.2 does not.

Proposed: "In a column priced row by row, every cell's code must include the zero, so an exact cell costs at least one bit; one more bit per column can then say that the whole column is exact. The kernel avoids the per-cell violation in its main pricing path only because it lists exception rows with their indices; what it leaves unpaid there is one bit per model."

### 4. FACTUAL ERROR — Appendix F pricing defects (line 1467)

L1467: "Two pricing defects, found while checking the outside review. … Neither is live in Stage A's main pricing path."

- The first defect (`frame.lisp:1581`) was reported by the review itself (REVIEW:79), not found while checking it. Only the second (`frame.lisp:1572`) was.
- "Neither is live" is unsupported for the second. VR:242 says nothing about where line 1572 is reached. By code reading (not run): Stage A prices each exception row through `closest-row-witness` (`condense.lisp:95`, called at `:116` and `:238`) → `select-closest-witness` (`frame.lisp:1719`) → `priced-correction` (`1645`) → `correction` (`1533`), whose `:seq` branch takes the minimum at line 1572. So it is reached whenever an exception row has a sequence target.
- The cited lines themselves are right: 1581 is the zero for an equal prediction, 1572 is the unpaid `min`, and `proposals.lisp:728-739` is the chain price in `induce-row-order`, which only `with-induced-row-order` and tests call.

Proposed: "Two pricing defects. The outside review reported the first, and the second was found while checking it. … The first is not reached in Stage A's main pricing path, which under-pays one bit per model instead; it is live in `induce-row-order`, which only tests call. The second sits in the sequence branch of `correction`, which Stage A calls for every exception row; how often it bites there was not measured."

### 5. FACTUAL ERROR — what is persisted (line 812)

L812: "Today these live in three structures (observation buckets, clause lists tied to node ids, `:dip-feature` entries), and only one narrow form is persisted."

Source (`plan_v2c_audit/reports/search-engine.md`:895–903, 917–919): two kinds are persisted. "`:nogood-schema` and `:dip-feature` are library kinds and are committed by `commit-synthesis-job` by default"; used separators "are committed as `:dip-feature` entries … and tried first in later jobs".

Proposed: "… and only two narrow forms are persisted: nogood schemas, which apply to one map-shaped decoder, and the separating features."

### 6. FACTUAL ERROR (attribution) — "Your earlier objection" (line 1530)

L1530: "recorded in one sentence, not adopted as this document's language. Your earlier objection to vocabulary heavier than content stands | §5.8"

- The only source I found for the phrase is an auditor, not the owner: `plan_v2c_audit/reports/docs-v2tex.md`:865, "**The vocabulary is heavier than the content.**" Nothing like it is in either annotation file, `prompt4.md`, `plan_v2_prompt.md`, or Appendix C. If the owner said it in a message I cannot see, keep it.
- The cross-reference is also loose: the §5.8 sentence (L509) records the tree automaton, the ground e-graph and the attributed C-set. It mentions none of the three terms in this row (fibration, adjoint triple, enriched metric).

Proposed: "not adopted as this document's language; §5.8 records only the automaton and C-set identifications. An earlier audit said of `plan_v2.tex` that its vocabulary was heavier than its content, and the same caution applies."

### 7. FACTUAL ERROR (cross-reference) — G.2 "Changed" column (line 1506)

L1506 lists "§5.4, §7.2, §7.3, §8.6" as changed by the pushforward note. §5.4 did not change on this point: `plan_v2c.md`:436 already read "as a sequence or through an aggregate", and `rev2.diff` has no hunk there. The §5.4 hunks are all about anti-unification.

Proposed: "§7.2, §7.3, §8.5, §8.6".

### 8. FACTUAL ERROR — "Every recurrence" (line 1049)

L1049: "Every recurrence shows the single property "output as long as input"."

Source (XS:59–90, column "P3 size", and XS:141; first example set, smaller pool): true of two of the five recurrences. `scan + init a` and `scan f init a` have 1 property; `scan 2*acc-x` has 3, `running-sum` 4 (including `(= (sum s1) (last out))`), `running-max` 11. The report's own sentence at XS:286 is loose in the same way.

Proposed: "Two of the five recurrences show only the single property "output as long as input", which five tasks that are not recurrences also satisfy."

### 9. OVER-STATEMENT — "no work was saved" (lines 67, 561, 1263)

- L67: "…and do not find the operators a problem needs, so they saved no work."
- L561: "no work was saved (§8.7)"
- L1263: "For its operators, no; no work saved"

Source (XS:243–248; XS logs `m1.log`:1581–1586): "saves nothing" holds only for the uncapped total summed over tasks (1.09 and 0.95), which one task dominates. Per task the signature restriction costs 0.77–0.83 of the full grammar, and 0.68–0.72 with the cap. The real finding is that a task-blind control does as well or better (0.73 and 0.60). §8.7 itself (L1038–1043) reports this correctly.

Proposed: "…so they saved no more work than a control that ignores the task."

### 10. OVER-STATEMENT — "time 2 to 4 times" (lines 68, 1266)

- L68: "that cut candidates about 15 times and time 2 to 4 times"
- L1266: "about 15× in candidates, 2× to 4× in time"

Source (VQ:226–228, 294): wall time improved 1.3× at size 4 (14 tasks), 2.0× at size 5 (6 tasks), 4.2× at size 6 (5 tasks); 2.0× as a geometric mean on the main 20 tasks. The document's own §8.8 gives "1.3×, 2.0×, and 4.2×", so §1.4 and §11.1 disagree with it.

Proposed: "and time about 2 times overall (1.3× at size 4, 4× at size 6)".

### 11. MISSING CAVEAT — "Three need a change" (lines 66, 1262)

- L66: "Three need a change: `map-adjacent` …, `seq-corr` …, and `filter` …"
- L1262: "three of them only after a change"

Source (VR:64–69; VR logs `r1.log`): `sum-all` and `prd-all` reach 200/200 only on the `fold` route. The unlifted route returns impostors for them (23/200 and 20/200), and the route order used in the §8.7 runs tries it first. So five of the thirteen depend on something other than the standard procedure. The §8.6 table (L991) has this; the two summaries do not.

Proposed addition: "Two more, `sum-all` and `prd-all`, are right only when the `fold` route is taken ahead of the unlifted one, which returns impostors."

### 12. MISSING CAVEAT — triangle inequality (lines 1011, 583, 1523)

- L1011: "No violations of the triangle inequality | **no** | … On sequences, 49 violations in 300,763 triples …"
- L583: "on sequences and code the present prices break the triangle inequality on some triples"
- L1523: "The prices are an oriented metric: … | adopted"

Source (VR:26, 250–263; VR logs `r5-metric.log`): the report's verdict is PARTLY. The review's zero holds on small-value grids. The 49 come from one grid built to provoke them; three random sequence grids of 3,375,000 triples each gave 0, 2 and 3. Violations appear "once values are large". VR:268 also says the price "is not a quasi-metric" on sequences and code, which contradicts "adopted" at L1523.

Proposed, L1011: "partly | none on integers, fields, tuples, or small-value sequence and code grids. With large element values they appear: 0, 2 and 3 in three random grids of 3.4 million triples, and 49 of 300,763 in a grid built to show them …"
Proposed, L583: add "once element values or literals are large".
Proposed, L1523: "adopted for the symmetry and asymmetry; 'metric' holds only on integers, fields and tuples".

### 13. MISSING CAVEAT — "Reproduced" labels differ from the report's verdicts (lines 989, 992)

L989 (`scan`, `shift-seq`) and L992 (`map-adjacent`) say "yes". VR:14 and VR:17 say PARTLY for both: the `scan` count and the impostor's size and level do not reproduce. The Note column carries the detail, so this is a label only. Proposed: "yes, one count differs" in both rows.

### 14. OVER-STATEMENT — what the first draft said (line 471, line 1520)

L471: "The first draft said that classes in the cells would give anti-unification modulo the store's equivalences for free. That was wrong."

Source (`plan_v2c.md`:459): the draft said the result "is taken modulo the equivalences the store has observed **[P]**" and then gave "Two cautions", the first being that the cost "is quadratic in the size of the corpus". It did not say "for free". Related: VR:30 marks the review's class-cell point COULD NOT TEST, so L1520's "adopted" rests on the review and the literature report, not on a run.

Proposed: "The first draft said that classes in the cells would give anti-unification modulo the store's equivalences, and noted only the cost. It missed that a class has many spellings."

### 15. OVER-STATEMENT — the signature experiment's set-up (line 1022)

L1022: "…over generic leaves (lengths, first and last elements, sums, minima and maxima of inputs and output, integer inputs, 0 and 1). A task's signature is the set of those properties true on every example. Nothing was written by hand."

Source (XS:109–117, XS:96–103):
- First and last elements are leaves of the output only; for inputs they were a variant. This also affects L1049, "its length, its ends, and three aggregates".
- The 18 leaves and the operator sets were chosen by hand; XS:117 says "Nothing is written per task".
- A property "holds" when it has no false cell and is true on at least 6 of the 12 rows.
- Four candidate tasks were dropped because the full grammar returned impostors on them, so the pool is one the full grammar solves 30 of 30.

Proposed: "…(lengths, sums, minima and maxima of inputs and output, the output's first and last elements, integer inputs, 0 and 1). … Nothing was written per task. Four further tasks were tried and dropped because the full grammar returned impostors on them."

### 16. OVER-STATEMENT — unsourced line counts (lines 551, 565)

L551 "about a hundred lines on top of refinement"; L565 "Refinement and backtracking, about 150 lines."

No source states these. In the measured engine (`plan_v2c_audit/cross-space/xs-m3.lisp`), refinement is lines 37–72 (36 lines) and choice, verification and backtracking are lines 73–137 (65 lines). Proposed: "about 65 lines on top of 36 for refinement in the prototype", or mark both as estimates.

### 17. COSMETIC — smaller points, one line each

- L3: "Appendix G lists every change." It does not list §2.9, §7.5, §8.1, the new risks 11–13, X9, or the Appendix A and F edits. Proposed: "Appendix G lists the changes of substance."
- L852: "about 7 look-ups in the reproduction". VQ:22 says "about 7 table look-ups per surviving candidate". Add "per surviving candidate".
- L51: "Within a space everything is computed, in time linear in the cells touched." L527 and L864 except the search for the term itself, which is exponential. Add "apart from enumerating terms". Likewise L843, "Across spaces every operation is a search for a witness", contradicts L533, where carrying an equality to another space needs no search.
- Staging disagrees in three places. L567 puts "analogy between tables" in Stage D; X9 (L1280), a Stage C gate, requires that "analogies between operator tables are found as terms". L1288 gives Stage C "by term and by refinement", while X9 builds "colour refinement with backtracking". L567 says the tables of §6.6 "are built" in Stage C; §6.6's staging paragraph has Stage A building them.
- L469: "kept every expression's tree for this reason". `deprecated/results.md`:560–562 gives three reasons (may differ elsewhere, different costs, different alignments). Proposed: "partly for this reason".
- L468: "Where operators diverge … the whole sub-term is the cell." The kernel's `anti-unify` keeps positions aligned under an operator hole when signatures agree (VR:285, `(?0 ?1 ?1)`). Worth one clause.
- L1051: "risk 4 and risk 12". Risk 4 is about counts, which §8.8 measured. The risk that cites this measurement is risk 11 (L1229). Proposed: "risk 11 and risk 12".
- L1493, L1494: the two notes are quoted in part without a mark. The first omits "it took several years for it to become 'too easy'. also note that their move application is very clever, costing 700-900 flops per move, written in Triton + leveraging TB/sec cache. So a B200 can dispatch millions of moves in ms."; the second omits "No, def never run an iterpreter backwards; but". The "too easy" remark gets no answer. Add ellipses.
- L1490: the "3%" row changed nothing, against L1483, "listed only where they changed something".
- L152: "raising `:max-depth` to 3 or 4 changed nothing". True of the four stuck specs (`plan_v2c_audit/reports/empirical.md`:358–364). In the same table `argmax-corr` went to 49 and 64 nodes and returned an impostor. Add "on the four stuck specs".
- L1527: "with two counts corrected". Four things were corrected: the `scan` count, the impostor's size, "overfits two, not four", and impostors where the review shows `NIL`.
- L1528: "It reverses the draft's reading of its own data." The draft's reading of its own data still holds (L999 says so); the new rows reverse the conclusion.
- L557: the outline's hedge is dropped. `prompt4.md`:175 reads "Hypothetically through the development of a vocabulary / short descriptive language." Proposed: "and the means, hypothetically, is …".
- L995: "impostors scoring at most 49/200". The 49 is the aggregate variant (VR:141). The prototype as it stands scores 31 and 43 on `argmax-corr` and 1 on `best-shift`.
- L1053: "saved less than reading one row". XS:332 says the test it saves "is one row" (mean 1.05 rows).

### 18. MISSING CAVEAT — unchanged sentences the revision has made stale

Outside the diff, but each now contradicts added text:
- L69: "folds to a scalar need a `fold` form, since lifting alone cannot express them" (against L794 and L911).
- L74: "Taking instances modulo classes is meant to make it robust to equivalent syntax; that is untested (§5.4)" (against L471, "That was wrong").
- L799: "It did not test `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or` …" (§8.6 ran all five).
- L1219, risk 1, and L1291, "shown so far on the prototype's rows" (§8.6 now covers the kernel's rows).

## Checked and found correct

- §8.6 spec table: every candidate count, held-out score and timing, against VR and `r1.log`, `r1-occam.log`, `r1-variants2.log`, `r2.log` (151, 408, 8,607, 3; 11,604; 8,781; 174/200; 1,383; 1.58 M; 23/200, 20/200; 29/200; 616,232; 27 nodes; 81/200; 20,713; 3.05 M; 625×, 824×).
- "23 lines in six marked places", "nine lines", "44–71": the patches in VR logs and VR:112–124.
- 13 of 16 specs, "4 to 13 rows", and its agreement across §1.4, §8.6 and §11.1.
- §8.6 price table: integer distances, 13/1 and 15/3, Kraft sums 1.5, 1.1875, 1.4059, 1,681 pairs, 48 and 78, the anti-unification holes (`r3.log`, `r4-kraft.log`, `r5-metric.log`, `r6-au.log`).
- §8.7: all three tables and the prose figures (0.48, 0.54, 0.32, 0.15; 0.67, 0.66, 0.49, 0.58, 0.69; 648 against 10.1 M; fair-cost table; 0.95–1.09; factor of 12; 2.7% and 6%; 350, 1.3 ms, 29, 96%; every row of the refinement table), against XS, `m1.log`, `m2.log`, `m3.log`.
- Figures cited from §8.8 in my sections: 61 operators, about 15×, 0.3% at 1,000 probes, 0.3% to 11%, 2.6×, 52nd to 58th of 61, 25 and 19 and "at most 60" (VQ).
- All quotations from `annots/cram.txt`: "run in Triton kernels with one GPU warp per chain", "remains an important open research direction", one and three hand-set values, 2.02e9 FLOPs per Sudoku, 42 ms and 132 ms fits, H200; no B200 and no 700–900 FLOPs figure in the text.
- `prompt4.md` L170–175: the three quotations are verbatim. "October outline" is right: the lines were in the owner's prompt by 19 October (git history) and still stand.
- Every owner note quoted in G.1 and G.2 is verbatim, apart from the two truncations above, and attached to the right passage; all 11 typed notes appear.
- Statements of the form "the review says" for REVIEW §1.3: tree automaton, C-set as the core of `plan_v2b.md`, extensional against intensional, the trade, two layers, "validates the store", the split rule, both parts of the inverse guard.
- `deprecated/results.md`:561–562 quotations; plan 7's seeding by graph distance and "never built"; plan 4's message as claim with evidence; plan 2 on acyclic patterns (October); DreamCoder attribution; 6–178× and the closure compiler's 4×; `plan_v2.tex`:759 for the replay guard; 31–51 lifted rows.
- Kernel references `frame.lisp:1581`, `frame.lisp:1572`, `proposals.lisp:728-739`.
- All section cross-references added in the diff resolve, except those in findings 6, 7 and 17.
- Appendix F's four new reports all exist in `plan_v2c_audit/reports/`; `lit-abstraction.md` appeared at 17:31, during this check.

## Could not check

- The owner's revision request. Not available to me, so I could not verify "as you say" (L75, L1323), "the split you describe" (L541), or the quoted phrases "graph walker" (L550) and "graph isomorphism engine" (L551). Neither phrase occurs in any repository document.
- "Its modified code was not kept" (L984). Only this document and the audit README say so.
- L1493: "they are consistent with its per-puzzle total". The paper gives no moves per puzzle. 2.0 × 10⁹ FLOPs at 800 per move implies about 2.5 million moves, which is near four chains of one 524,288-move schedule, so it is plausible but not stated.
- L536: "choosing which subsets to generalize, for the best total compression, is NP-hard". No report states it. The neighbouring hardness claims are in `lit-discrete.md`:125 and :473 and plan 2.
- The review as read "at 16:05 … (244 lines)" (L1473, the other checker's section). The file now has 323 lines and was modified at 17:20; it has gained an Appendix A that this document does not mention. I checked against the current file. Its §1.3 matches every statement made about it.
- G.0 is the other checker's, but it repeats two findings above: "refinement alone matches irregular data of 10,000 rows with no search" (finding 1) and "time 2 to 4 times" (finding 10).
