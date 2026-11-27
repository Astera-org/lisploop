# Log: applying `factcheck3-C.md` to the section files of scope C

Input: `round3/sections/`. Output: `round3/sections-fc-c/` (35 files, same names). Changed: 27 files. Copied unchanged: `02.0.md`, `04.0.md`, `04.2.md`, `04.4.md`, `05.0.md`, `05.1.md`, `05.2.md`, `05.7.md`. Every change was made by three scripts in `round3/sections-fc-c/work/` (`patch_02.py`, `patch_04_05.py`, `patch_07_09_app.py`), which read `sections/` and write `sections-fc-c/`, so they can be run again. Each old string had to occur exactly once or the script stops. Nothing under `/home/tlh24/lisploop` was written.

"Checker's text" below means the replacement sentence the report gives. Where I departed from it, the line says how and why.

## Findings 1 to 9 (factual errors; each source opened again)

1. Applied, `02.3.md`. Source re-read: `v2/consolidate.lisp:1213-1246` and `:1264-1271`. The new definition names the primitives exactly (`cons`, `tail`, `length`, `concat`, `at` for a sequence type; `tuple`, `at` for a tuple type; `code-eval` for a code type), because the checker's phrase "the sequence primitives" would have included `gather`, which the grammar leaves out. "signature" written as "type signature" (decision 11).
2. Applied, `02.3.md`. Source re-read: `empirical.md:250-252`. The text now says that a tenfold of work buys 6–7 bits, that a variable costs 3–5 bits and an operator application 6 bits or more besides its operands, and then draws the bold conclusion.
3. Applied, `07.1.md` and `07.3.md`. Sources re-read: `v1/bootstrap/build-batteries.lisp:628` (the `filter` spec takes a predicate), `verify-review.md:15`, `:39`, `:54-80`, and §8.5 as it now stands. §7.1 now says that §8 finds `scan`, `map-adjacent` and `filter` with the function or predicate as an argument, and that only the higher-order `map` and `foldr` were not attempted. §7.3 now says the prototype was run on all sixteen specs and thirteen were solved in some configuration, which is §8.5's own sentence. The checker's sentence on named function arguments was kept and extended to predicates (`verify-review.md:39`).
4. Applied, `05.6.md`. Sources re-read: `v1/frame.lisp:544` (`pullback-frame`), `v1/unify.lisp:103` (`compile-au-constructor`, which builds a decoder from a pattern), `v1/deprecated/plan3.md` §3 (no use of the word "lift"), `docs-origins.md:603`. Departure: the checker wrote that the auditor reads plan 3's definition "as the first statement of lift"; the report says only "lift is defined here", so the text says "as a definition of lift". The formula is also given in words. The reference `unify.lisp:103` is dropped from the plan; the checker's optional sentence for §5.4 was not added (it would be a new sentence about a nugget that the plan does not use).
5. Applied, `02.8.md`. Source re-read: the four lists have 11, 10, 15 and 12 items (`docs-origins.md:474-547`, `docs-plan6-results.md:362` on, `docs-plan7-arch.md:363-379`, `docs-plan8-9.md:495-508`).
6. Applied, `02.8.md`. Source re-read: `docs-origins.md:534-539`; `pairs`, `anchors`, `edges` relate rows of one frame.
7. Applied, `09.0.md`. Source re-read: `v1/unify.lisp:36-43` (a list of sources; "Equal disagreement tuples reuse the same hole"; operator holes need a shared signature).
8. Applied, `09.0.md`. Source re-read: `laws-library.md:350` and `v1/laws.lisp` (the 338 lines are 447-784; `propagate-requirements` starts at 736).
9. Applied, `02.1.md`. Source re-read: `v1/requirements.lisp:245-256` (ten rules over five constructors). The sentence was split into three. The same looseness in the table of `02.2.md` ("one simplification rule per constructor") was changed to "hand-written simplification rules, each for one constructor" (`core-repr.md:390` lists six such rules over five constructors).

## Findings 10 to 20 (inconsistencies)

10. Applied, `07.1.md`, NOT with the checker's text, which conflicts with §6.4 as it now stands. Item 5 keeps its heading "Price names by use" and now says what §6.4 "The order of names, and their price" says: the price of a name is −log₂ of its share of uses, under a prefix code, and is used only at acceptance (§7.2); the order in which operators are tried comes from the verb tables, and counts may only adjust it within a limit (§6.4); letting counts set the order failed on 5 of 8 tasks (§8.7). "Adjust", not "correction" (decision 11).
11. Applied, `04.1.md`, in the form the task asked for: the main control problem is which library entries are tried on a problem; choosing a small grammar would be worth a factor of 12 if right, and the one measured way of choosing saved no more work than a control that ignores the task (§8.6); the plan does not choose a subset, each operator carries a verb table and each candidate is tested against the target's labels (§6.4). "Verb table" is defined in the sentence. Departure: the checker's "saved nothing" holds only for the cost summed over tasks (0.95 to 1.09), while the per-task figure in §8.6 is 0.77 to 0.83 against the control's 0.73, so the text uses the comparison with the control, which §5.9 already states.
12. Applied, `05.9.md`. "The kernel has to select which library entries go into each problem's grammar" is gone. The paragraph now says that the outcome depends on which entries a search tries, that the plan does not select a subset, because the one measured way of selecting saved no more work than a control (§8.6), and that each candidate is tested against the target's labels through the operators' tables (§6.4). Departure: the checker's "quotients and verb tables" is written as "the tables of what each operator does to labels", to avoid "quotient" in the vocabulary sense (decision 1).
13. Applied, `05.9.md`: "propose with the index" is now "propose pairs with the cheap signals above, labels first", in four sentences.
14. Applied, `03.0.md`. From the sources: 1 to 5 sub-problems in the bootstrap's 19 jobs (`bootstrap-reflection.md:121-122`, as §2.6 says), and two or three on the specs that stay unsolved (`empirical.md:293-297`, as §2.3 says). The same unqualified statement in `04.1.md` ("the tree of sub-problems stayed a root with one or two children") was given the qualifier "on the four specs that stay unsolved".
15. Applied, `09.0.md`: "two of them are artifacts", and both are named (the name bits; the work price list). No source gives a third.
16. Applied, `AE.0.md`. (a) BUSTLE role: "the property sets compared between whole problems, which did not find the operators a problem needs (§8.6)". "Property sets" kept, per decision 11, although §8.6 still says "signature" (see "for others"). (b) Probe role: counts of past use failed when they set the order of search (§8.7) and are kept as the price of a name and as a limited adjustment to the order (§6.4). This follows §6.4 and decision 11 ("adjustment"), not the checker's "kept only as a correction". (c) Myth role: "§7.3 case 5; the control problem of which library entries are tried on a problem (§4.1, §5.9)", because the plan no longer selects a grammar. (d) "One lineage": the Probe grade is changed to "one system, re-implemented once by another group" (`lit-search.md:218`, `:362`). For the two rows that keep the term, a definition was added to the first paragraph: one original system together with the systems that build directly on it. That is true of both rows by the reports (property signatures, then BUSTLE, `lit-geometry.md:373`; LAPS, then LILO, `lit-geometry.md:487-503`). The checker's "one research group" was not used, because no report says it of either.
17. Applied in `02.3.md`, NOT with the checker's text. The checker's "The library holds 31 specs. The sixteen used in this section are the ones that specify functions" is wrong by the checker's own finding 37: 13 of the 31 saved specs specify functions, and the specs of the six seed functions are not saved. The text now says that a spec is one entry the bootstrap asks the kernel to produce, that this section uses the specs of the sixteen functions the kernel synthesizes, and that there are specs for solvers and other kinds of entry (§2.5). The Terms table entry is outside my files (see "for others").
18. Not applied, as instructed: it concerns §6.4, which has been fixed. `05.5.md` keeps its sentence on verb tables.
19. Applied, `04.5.md`: "ranking and filtering".
20. Applied, `05.5.md`, checker's text.

## Findings 21 to 33 (over-statements)

21. Applied, `04.5.md`. "Bears on this" is restored, and both quotations of your note are kept. The paragraph no longer says "both halves of your note hold". It says that the second part of the note holds for this paper, gives the hand-set energy as the reason (`lit-search.md:571`), reports that the two literature auditors drew a narrower lesson (lit-search report, §9.3), and says the audit has no source on "several years". Departures from the checker's text: "one hand-set weight already solves every puzzle" is written exactly (one distinct weight value for Sudoku, three for mazes); and "Either reading argues for an exact store" was not used, because the auditors' reading does not argue for one. The sentence "That argues for an exact store with cheap evaluation, and not for a learned embedding" stays attached to your reading, where it was.
22. Applied, `02.3.md`: the qualifier "On the four specs that stay unsolved" leads the claim, and `argmax-corr` (34, then 49 and 64 sub-problems, an impostor) is reported at the end of the bullet (`empirical.md:356-362`). Also applied to `04.1.md` (see 14). §1.1 is outside my files.
23. Applied, `02.4.md`: heading and count now speak of conversions between kinds of entry; the two generic conversions are named, with a pointer to the laws-library report §2.2. "Fold signature" became "type signature, that of a fold" (decision 11).
24. Applied, `02.5.md`, checker's text. The **[M]** tag is back on the 6.6× figure.
25. Applied, `02.2.md`. The unsourced gloss is removed. Departure: the checker's "The search audit took this to mean that ..." is also an inference, so the text says only what the report lists as existing today (search-engine report, §6.1) and then the eight blockers (§6.2). The short quotation of your phrase is kept; the full sentence is quoted in §4.6.
26. Applied, `04.1.md`, checker's text.
27. Applied, `AA.0.md`, checker's text, with **[P]**. "At most five variables" is gone from Appendix A; it remains in the cost table of §7.6 (see "for others").
28. Applied, `07.3.md`, checker's text.
29. Applied, `02.3.md`, checker's text (source re-read: `v1/plan8.md:296`).
30. Applied, `09.0.md`, checker's text.
31. Applied, `02.9.md`, as two sentences.
32. Applied, `04.6.md`. "Staging" is now defined in that sentence, where it first appears, and the later sentence refers back to it. The same over-statement in the table of `AE.0.md` ("each interpretive level costs 6–178×") was changed to match.
33. Applied, `04.3.md`, checker's text. The grade "single group" in the table of `AE.0.md` was changed to match.

## Findings 34 to 45 (missing caveats)

34. Applied, `02.3.md` (source re-read: `v2/experiments/stage0-audit.lisp:59-84`, one case per spec).
35. Applied, `02.3.md`: the sentence before the table says all four tests were flat searches and that soundness inside a synthesis job was not determined; the cell is "Integer arithmetic problems over `+` and `*`, on six rows".
36. Applied, `AA.0.md`: the row again says that across spaces a matching engine is needed, and that an e-graph's store is worth having and its saturation is not.
37. Applied, `02.5.md`. "Operational" is restored and glossed. The counts were re-derived from `scripts/bootstrap-reflection/entries.txt` (61 = 15 laws, 13 solvers, 13 functions, 10 transformers, 8 descriptors, 1 template, 1 motif; 31 specs, of which 10 are the saved synthesized functions). The paragraph was reordered so that "ten of the 16 are saved, and their specs are ten of the 31" is said once.
38. Applied, `05.4.md`, checker's text (both quotations checked in `v1/deprecated/plan.md` L84-90 and `plan_v2_prompt.md:2`).
39. Applied, `AD.0.md`. Departures: the count of the full record is "about thirty rows", not "about 35" (the three tables of `docs-v2tex.md` §3.1 have 31 removal rows); one sentence was added saying that the three word types of §6.4 are yours and are not the rejected query language, which the finding asked for.
40. Applied, `09.0.md`. A sentence says what "lexicographic" means here, from the docstring of `self-calls-descend-p`. Line ranges re-checked: `condition-facts` is `ast.lisp:764-831`, 68 lines.
41. Applied, `09.0.md`, checker's text in the "Why" cell. The "How" cell still says "as code", as the checker left it.
42. Applied, `02.8.md`, checker's text.
43. Applied, `05.9.md`, in two sentences.
44. Applied, `05.3.md`. "Split" is spelled out as a split by a guard, and the size-order rule is given in §8.5's own terms.
45. Applied, `AA.0.md`, checker's text, with **[L, abstract only]**.

## Findings 46 to 71 (cosmetic)

46. Applied, `02.3.md`.
47. Applied, `02.3.md`.
48. Applied, `02.3.md` ("offered to every synthesis job of the bootstrap").
49. Applied, `02.1.md`: `frame.lisp:1194-1271`.
50. Applied, `02.3.md`, both cells.
51. Applied, `02.7.md` (source re-read: `v1/synthesize.lisp:447-457`).
52. Applied, `02.4.md`. "Answer term" is not used there, because §2.5 defines it later; the sentence says "the expression that the solver computes for the unknown".
53. Applied, `02.6.md`, as two sentences.
54. Applied, `02.4.md`; and "only caller in the kernel" in the matching row of `AA.0.md`.
55. Applied, `02.4.md`.
56. Applied, `02.9.md`.
57. Applied, `02.8.md` ("Normalize by laws before anti-unifying"), and the back-reference in `05.4.md` ("normalizing expressions by known laws").
58. Applied, `AA.0.md`: the "See" cell is now "§9; the `docs-v2b.md` and `docs-v2tex.md` reports", which is where the statement is supported.
59. Applied in part, `04.5.md`: the hand-set energy is back in the text through finding 21. The fit times (42 ms and 132 ms) belong in the revision notes (see "for others").
60. Applied, `05.9.md`: both invented quotations are gone; your own phrase is quoted for the first.
61. Applied, `04.7.md`. The reason the first row has no bold cell is given as "substitution is not special to any one perspective", because the Flat-vectors cell of that row says "weak". One sentence says the last row is not an operation.
62. Applied, `05.4.md`.
63. Applied, `04.5.md`: the first of the three results is tagged **[L, from memory]**.
64. Applied, `05.9.md`, with the outline's own words "subgraph isomorphism problem".
65. Applied, `07.1.md` (quotation checked with `git show dbd3347:plan_v2.tex`, line 113).
66. Applied, `AA.0.md`.
67. Applied, `09.0.md`: (a) the cell reads "215 by one auditor's count and 315 by another's"; (b) the "Where" cell notes that the 14 lines of `laws.lisp` are also counted in the finite-field row; (c) the sentence on the 370 lines of milestone code.
68. Applied: (a) and (b) in `AE.0.md`, (c) in `AD.0.md`.
69. Applied, `07.3.md`. The two single-paper techniques are described from the report's table (`lit-search.md:244`, `:248`).
70. Applied, `AA.0.md`, with "adjustment" for "correction" (decision 11); "See" cell gains the core-repr report, §5, since §2.6 does not mention the six integers.
71. Applied, `07.1.md`.

## Decisions of the brief applied where no finding asked for it

- Decision 12: "the root kernel (v1, as distinct from the copy in `v2/`)" is "the v1 kernel, which is the original kernel and is distinct from the copy in `v2/`" in `02.2.md` and `02.3.md`. No path was rewritten.
- Decision 11: "a class of rows" is "a group of rows" (`02.2.md`); "adds a correction" is "adds an adjustment" (`02.6.md`); "every synthesizer the review checked" is "that the literature review checked" (`05.8.md`); "every enumerated node" is "every enumerated expression" (`AD.0.md`).
- Decision 1: "choosing quotients of values" is "choosing words, which are quotients of values", and "merged quotients" is "merged words" (`AE.0.md`).

## Changes taken from the report's tables, not from a numbered finding

- `05.5.md`: after "The prototype tested unconditional laws only", one sentence points to the four laws whose weakest guard was found in Python (§8.7). The report's note under its table of stale sentences asks for this pointer.
- `07.1.md`: "lift is a synthesizer primitive" in quotation marks was not your wording; the sentence now quotes "lift has to be a synthesizer primitive" (the report's note on Appendix A).
- `AA.0.md`, first row: "See" is "§2.1, §2.2" (the last clause of the finding is said in §2.2).
- `AA.0.md`, totality row: "totality gates only rewrites" became "Totality never gates execution. It gates certain rewrites, and also frame metrics and metric decoders", with the core-repr report §2.4 added to "See" (`core-repr.md:311-313`).
- `AE.0.md`: the role of the λ² row gains "(§7.2)".

Not changed, although the cross-reference table marks them "lands in part": the pointer from §4.6 to §7.1 for an evaluator whose terms mention requirements; the pointer from §5.9 to X9 for measuring the share of an hour spent across spaces; the pointer from §2.9 to Appendix D for the failing opcode (the claim itself is supported by `docs-v2tex.md:29-32`). Words in a second sense that were left: "node" for a vertex of a graph in §4.2, §4.5 and §5.2, where the sentence is about a graph; FlashMeta's "witness functions", which is the published name.

## For others (outside my files)

- Finding 72, `11.1.md`: "3 of 8 unreachable tasks solved" should read as the checker gives it (of 8 held-out tasks, the 3 the kernel alone could not reach were solved).
- Finding 73, `10.0.md`, risk 11: X4 has no retrieval arm; use the checker's replacement.
- Finding 74, `08.5.md`: "Stage A does not price cell by cell" needs "The kernel's first search phase (which its code calls Stage A)".
- Finding 75: Terms table, X1 to X9 (X8 has no gate); `01.1.md`, "the search tree has two or three nodes at every budget" (should be qualified as §2.3 and §4.1 now are); `08.2.md` and `11.2.md`, "witness" for a solver's answer term; `07.4.md`, the mapping of the 158 decisions leaves out the 6 accounting rules.
- Finding 17: the Terms table entry for *spec* (`00-front.md`) still says "One function the bootstrap asks the kernel to synthesize". §2.3 now says "one entry that the bootstrap asks the kernel to produce".
- Finding 34: the Terms table says "*Held-out* scores count fresh inputs"; in §2.3 the harness has one hand-written input per spec.
- Finding 59: `revision-notes.md` should carry "The paper fits its model in 42 ms and 132 ms". Its line 173 still says "§6.6, Appendix E" where the numbering is now §6.7 and Appendix C. §4.5 now says the audit has no source on "several years"; the notes say "agreed that it took years".
- Finding 27: the cost table of `07.6.md` still has "brute force over at most 5 variables", which has no measurement or code behind it. Appendix A now says "few variables" and "not built or measured".
- Decision 11: `08.6.md` still calls sets of properties "signatures"; Appendix C now points to it for "property sets".
- Decision 1: the Terms table still says "The labels are the words of the kernel's vocabulary".
- Decision 12: the front matter still says "root kernel unchanged since `df33ed1`".

## My own check after writing

Script: `round3/sections-fc-c/work/check_tokens.py`. For each file it compares, as multisets, every number, number word, quotation, evidence tag, code span and section pointer of the input with the output. Everything that is in the input and absent from the output:

| File | Lost | Explained by |
|:--|:--|:--|
| `02.1.md` | `frame.lisp:1214-1256` | finding 49 (now `1194-1271`) |
| `02.8.md` | "twelve" | finding 5 (ten to fifteen) |
| `04.7.md` | "§5" in the caption | finding 61 (caption rewritten; the paragraph after the table still names §5) |
| `05.4.md` | "two" in "Experiments to depth two" | finding 38 (the heading keeps "Depth-two") |
| `05.6.md` | `unify.lisp:103` | finding 4 |
| `05.9.md` | "graph walker", "graph isomorphism engine" | finding 60 |
| `07.1.md` | "Smuggled ... via higher-order opcodes" | finding 65 (replaced by the verbatim text) |
| `07.1.md` | "lift is a synthesizer primitive" | replaced by your wording (see the tables section above) |
| `07.3.md` | `seq-corr`, `best-shift`, `argmax-corr`, `last-or` | finding 3 (the list of five specs is replaced by "all sixteen"; `best-shift` is still named in the last sentence) |
| `09.0.md` | `laws.lisp:736` | finding 8 |
| `09.0.md` | "three" prices | finding 15 |
| `AA.0.md` | "§2.9" | finding 58 |
| `AA.0.md` | "five" variables | finding 27 |

No evidence tag was lost. Tags added: **[M]** (`02.5.md`, finding 24), **[L, from memory]** (`04.5.md`, finding 63), **[L, abstract only]** (`AA.0.md`, finding 45), **[P]** (`AA.0.md`, finding 27). Two tags moved within their paragraph: **[C]** in `02.1.md` (finding 9) and **[L]** in `07.3.md` (finding 69).

Losses that the script cannot see, because they are words and not tokens, and the finding behind each: "one or two children" in §3 (14); "long precedent" (45); "regression" (70); "context selection", "counts", "single group", and "one lineage" on the Probe row (16, 33); "stand-in functions" (24); "that the search can use", "that only hold example rows" (37); "supports this", "Both halves of your note hold" (21); "fitted a model" (26); "retrieval" (19); "its one impostor" (20); "only" in §7.3 (28); "one for each constructor" (9); "every operator the kernel has" (1).

Every number added to the text was traced to its source: 264,353 and 16,000 (`plan8.md:296`); 35 million, 34, 49, 64 (`empirical.md:33`, `:356-362`); 12 (§8.6); 64 ms (§8.5); 135 (§8.1); 5 of 8 (§6.4, §8.7); 68, 136-149, 447-784, 1194-1271, 14, 370 (code and `laws-library.md:350`, report line 67); 1977 to 1981 (`lit-discrete.md:34`); 21 specs (31 less 10).

The scope grew from 111,900 to 124,127 bytes. Every file has the same number of lines as before, and every table row has the same number of cells. Nearly all of the growth is replacement text from the report; the largest part is the definitions paragraph and the Structure bullet of §2.3.
