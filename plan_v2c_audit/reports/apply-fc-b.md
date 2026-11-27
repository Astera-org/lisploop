# Log: applying `factcheck3-B.md` and `clarity-review-new.md` to the front matter, section 8, sections 10 and 11, Appendix D, and Part 1 of the revision notes

Input: `round3/sections/` and `round3/notes/10-part1.md`. Output: `round3/sections-fc-b/` (17 files). Changed: `00-front.md`, `08.0.md`, `08.2.md`, `08.4.md`, `08.5.md`, `08.6.md`, `08.7.md`, `08.8.md`, `10.0.md`, `11.1.md`, `11.2.md`, `11.3.md`, `AF.0.md`, and `notes-10-part1.md` (the new Part 1 of the notes). Copied unchanged: `08.1.md`, `08.3.md`, `11.0.md`. Helper scripts are in `round3/sections-fc-b/work/`. Nothing under `/home/tlh24/lisploop` was written.

"Checker's text" means the replacement sentence a report gives. Where I departed from it, the line says how and why. Paths of logs are under `/home/tlh24/lisploop/plan_v2c_audit/`.

## A. `factcheck3-B.md`, findings on the plan

1. Applied (8.7, bullet on two-argument operators), checker's text, with "words" for "quotients" (decision 1).
2. Applied (8.7), by decision 6 and in the words of the current 6.2: the correction code is defined for any two values; what is undefined for 41–43% of the classes on the path one step out is the element-by-element difference. Kept from the checker: 74–90% two or three steps out, and "about one true parent in ten" where the types differ. The lines the checker names in 6.2 and 6.8 are outside my scope and are already fixed there.
3. Applied (8.8 item 9; risk 14), but not with the checker's text. Its last sentence puts near-miss proposals "in the plain pass behind the filter"; decision 4 puts the check inside the tentative pass, on every candidate that pass evaluates, with the plain search as fallback. I followed the decision.
4. Applied (8.7 "In the store prototype"; 11.1; risk 14): 9 of 9, and 7 of 9 with Boolean-returning candidates exempted; one of the nine was the 29/200 impostor. The Python result (both branches of all 120 conditionals kept one or two rounds later, about 1,330 candidates with the filter or without) is added to the same bullet, with the caveat that the test asked about the branches and not the guard (`b3_report.log`; `factcheck3-A.md` finding 3).
5. Applied (11.1). The cell now says "probes chosen by the rule of §6.5", which is the rule in bold, so the wrong row can no longer be read into it.
6. Applied (8.7, now under the heading "What can be certified"), checker's text; "10.2× of the 17.0×" reworded as two gains (clarity A23).
7. Applied: checker's text in the front matter; checker's clause in the opening of 8.7.
8. Applied (8.7), checker's text; "level" written as "size".
9. Applied (8.7 and 11.1), checker's text. Note for the author: the current 6.2 still says "Corrections carried a little information at every distance", which is weaker than what the log shows one step out (median about the 2nd percentile).
10. Applied (front matter), by decision 1: a quotient kept in the vocabulary is a word; "sign" is the word and "negative", "zero", "positive" are its labels. The *verb table* row now says "one word".
11. Applied (8.7). The two timings are now stated once, together, in the "Cost" bullet with what differs between them; the probes paragraph gives only the ratio and points there.
12. Applied (8.7), checker's text.
13. Applied (8.7), checker's text, with "word".
14. Applied (X4), checker's text for the cost and the gate. The gate now also says which arm it is measured against (see clarity A40 d).
15. Applied. Risk 11: the checker's second option ("the retrieval measurement of §8.6 is not repeated"), because the first would add an arm to X4 that no decision asks for. Risk 14: X3 is no longer named; X4 counts the answers only the fallback finds.
16. Applied (8.5): "3 to 13 rows per spec".
17. Applied (8.5 table, prefix-code row), with the fuller rewrite of clarity A8.
18. Applied (table of terms; first sentence of 11.2).
19. Applied (8.4), together with clarity C4 and decision 8: the bullet keeps one sentence and the pointer, and no longer says "two or three sizes". The projection is in 7.6; 8.7 says it was not measured.
20. Applied (8.7, both bullets). Feedback: the rates on the 4,000-task streams are given at both probe counts (5.0 to 1.7 and 0.55 to 0.13 per 1,000 tasks, `exp_feedback_p1.log`), and by decision 10 it is "left out of the first version, and a cheap thing to add later". Slices: checker's sentence added; the rule is said to be adopted on the argument.
21. Applied (risk 13), by decision 7: no "among the dearest"; "3 of 234 answers were lost, two of them on larger tasks".
22. Applied (8.7), all three: the 179 tasks; the ties as 12 and 14 of 26 against about 10 and 9, with "only this direction was measured"; "19 to 23 times if each check is counted".
23. Applied (X3), checker's text; "the rule of §8.8" is now "the size-order rule (§8.8, item 2)" and "the bounded look-ahead of §7.2" is "the look-ahead of §7.2 (step 4), in its types-only form". Stage B in 11.3 now lists the size-order rule and the types-only look-ahead, since X3 measures them. Not resolved, because the checker gives no text and it is a design choice: two of X3's specs need a guard, and the near-miss check that proposes a split is in Stage C.
24. Applied as a statement of the gap, not as the checker's text. The checker's sentence says the reviewer's scripts "are copied in `round3/reviewer/`"; they are not, and the repository is read-only for me. Appendix D now says, in its first paragraph and in a new housekeeping item, that nine scripts read the reviewer's scripts from a scratch folder and cannot be rerun from the repository until that folder is copied in. I confirmed the nine with `grep` (the tenth hit is `round3/BRIEF.md`). Rows were added to the table for the gap logs, the glossaries, `clarity-review-new.md` and the `apply-*.md` logs; `factcheck3-*` is written out as A, B, C; the working notes `lit-search-appendix-*.md` are named in the `lit-search.md` row.
25. Cosmetic items, all applied: "four ways ... compared with each other and with the review's hand-chosen transforms"; the quotation is now "*Stratify by current words*"; "7 of 20 probe seeds, and for none of 10 other task seeds"; the heading of the last column of the probe table; the sentence on which experiment is Lisp; "It does little for a scale: first in 4 and 3 of the 32 scale tasks, against none"; "On seven guarded runs", with the lower bound for the run that stopped at 15 million candidates; `(sgn x)` first "on a grid of −10 to 10 with floor division", 4th with truncating division, 2nd on a grid of −20 to 20; the dropped sentence on `foldl` and `argmax-corr` restored in 8.5; in §10 the vocabulary item now says Stage C depends on a self-chosen vocabulary passing X4 and that its going on improving is hoped for and not depended on.

The move to `v1/` (the checker's opening notice): applied in the front matter as a new short paragraph, "Where the cited files are", with the wording given in my task. "root kernel" is gone from my files. Individual paths were not rewritten (decision 12).

## B. `factcheck3-B.md`, findings on Part 1 of the revision notes

- B1: not applied as text. Section 1.5 now has the line `LENGTH-PARAGRAPH-TO-UPDATE` in place of the length paragraph and of the list of where the plan could be shortened, as my task says. The checker's replacement paragraph is in `factcheck3-B.md`, finding B1; its figures will be out of date after this round.
- B2: applied, checker's text.
- B3: applied. By decision 7 the cell says "from 12.1× to 6.6× under the three-to-one reserve", not "from about 12×".
- B4: applied, checker's text; the claim cell now quotes the review's own words, "is blind to multi-step plans".
- B5: applied, checker's text.
- B6: applied. Row 9 cites `reports/verify-memory.md` for the 1.4× to 5.7×; row 10 can keep "§8.7", because 8.7 now has the dependence on operator order (finding 12).
- B7: applied, by decision 4 (see the row on the four-stage handoff).
- B8: applied, checker's text.
- B9: applied; "at least four of its 24 rows", which is what the checker found, where its replacement sentence says "four".
- B10: applied, checker's text; one sentence added on the nine scripts that import the reviewer's scripts.
- B11: applied, all six: "at 1,000 probes per operator or more" (two places); the two quotations; the sentence on words with two meanings now says the third-round checks found three more and what each now means; "the three largest are", with the two gap logs named and the "depth two" gap mentioned; "the 179 tasks".

Also changed in Part 1 to agree with decisions 3 to 10: section 6 described as one question, two resolutions, three computations; the first row of the claim table (one routine only for the counting cases, first step only for an inverse); the row on feedback and merged words; the row on slices; the rows on choosing words and probes (run in Python on one library, never together; tables not sound); four new items in 1.4 (no plain control; memory in two situations; the element-by-element difference; the summed-cost figures in full).

## C. `clarity-review-new.md`, items that concern my files

- A1: applied (table of terms).
- A2: applied. The nine rows are in, with the confirmed definitions of *look-ahead*, *one step from the answer* and *true parent*. *bank* and *agenda* have the confirmed definitions (this also answers A6 and B9). I added three things the review did not list: *label filter* (A9), *round* in the row for *tentative pass* (decision 2), and what a *work unit* pays for (the small item on L26).
- A8: applied to the cell in 8.5 (rule 5 of 6.3 is outside my scope).
- A9: applied. One name each: *label filter* (before a candidate is evaluated), *look-ahead* (before a class is stored; defined in the table of terms and in 8.7), "a filter applied strictly at one size" for the prototype's oracle filter, and *one-step look-ahead* defined where 8.7 uses it. "Label test" no longer occurs in my files.
- A34: applied. The configuration is the prototype's unlifted path, and the two specs are `sum-all` and `prd-all`; `len-all` and `last-or` are solved on it (`verify-review.md` §0 R1d, §1d). The eight sequence specs are named; the two with a guard are `scan` and `shift-seq` (`l1-proto/logs/e1-table.txt` part c: 7,257,787 / 11,604 and 7,238,105 / 8,781).
- A35: applied. The opening sentence; the heading and row labels of the first table (the two held-out operators are named; "training" belongs to the count-based method); the three column headings of the second table; a paragraph that defines a run, gives 900 = 300 tasks × 3 table seeds and 800 = 2 sets × 200 tasks × 2 table seeds, and says what the unusual rows are (`q2-probes/tasksets.py`); the sentence that adds up the 1,700 runs.
- A36: applied, with the corrected counts of finding 1.
- A37: applied. "Fired" is gone. The unit is candidates. The reason given is the mechanical one: a check that sees every candidate fires no later than one that waits for the filter, and a check that fires ends the search (`verify-handoff.md` §4). I did not use the review's "the proposal can do no better than that": on the tasks where it fires the log shows 1.59× and 1.45× over the label-filtered search, above the 1.1× ceiling for an ordering.
- A38: applied. The setting says the gain is not one number; "14× to 18×" is used in 11.1.
- A39: applied in 8.8 item 2 and in X3. The sentence that the three further tests "are not part of X3's gate as it is now written" is my reading and is for the author to confirm.
- A40 (a), (b), (c), (d), (e): applied. For (d) the gate is against arm 1, the no-guidance arm, and the comparison with the plain early-comparison arm is reported beside it. Whether the gate should be against that control instead is the author's decision.
- Small items: L26 (work unit), L1210 (the method is described and not named), L1234 (410 of what), L1243 (64 and 32), L1268 (seven what), L1354 ("that library"), L1386 (the four limits), L1401 (the bucket engine and the enumerator, both now "the v1 kernel's" with a clause each): applied.
- B5 (second half), B10, B11, B12, B13: applied in 8.7. B11's missing reason is the one in `verify-proto-labels.md` §3 item 1: the prototype builds its bank once and does not restart at each bound.
- B14: applied. All five results now have an entry in 8.7 (see D below).
- B16 (§10): applied. The column is headed "What the design does about it, and what would show it", and each cell is labelled *Design:* or *Test:* or both.
- B17: replay is in Stage C in 11.3, and X7 says where each part is built; the placement of the near-miss check agrees with decision 4 in 8.7, 8.8, §10 and X4; 8.7 says why the 4.3× on the sequence library is set aside (most of it needs no labels); "two more only through the `fold` route" is gone from 11.1; 8.7 says the seven runs are not the nine.
- C4: applied (8.4 one sentence and the pointer; 8.7 keeps the figures).
- C14: applied in form, not in length. Each cell of the last rows is one or two short sentences with its pointer, but the rows went from 453 to 539 words, because findings 4, 5, 9 and decisions 4, 8, 9 each add a qualification and two rows were split.
- C3, C15 (not in my list): partly taken, to avoid a sixth copy of the same figures. 8.8 item 9 now states the change and points to 8.7 and to risk 14; risk 14 keeps the figures in short form. C5 and C8 were not applied.
- A40 (f) to (j), A3 to A7, A10 to A33, the other small items, B1 to B4, B6 to B8, B15, C1, C2, C6, C7, C9 to C13, C16: outside my scope.

## D. Section 8.7 against sections 6 and 7 as they now stand

Read first: the current `06.1.md` to `06.5.md`, `06.8.md`, `07.2.md`, `07.4.md`, `07.5.md`, `07.6.md`, and the versions in `sections-cn/`.

- (a) The counting routine: new paragraph "One routine for the counting cases" (`q4-handoff/u1_residual.log`; `verify-handoff.md` part A).
- (b) and (d) The summed-cost figures and the target no table predicts: new paragraph "A target the tables do not predict, and what a lost answer costs" (`q4-handoff/c_unpredicted.log`; `verify-handoff.md` part C).
- (c) 22 of 32 operators: third of "Three smaller results" (`verify-quotients/q5_reuse.log`; `factcheck2-B.md` finding 12).
- (e) The merged word by program size: in the bullet on merging (`factcheck2-B.md` finding 3; `factcheck3-A.md` finding 18b).
- Also added because 6.3, 6.5, 7.2, 7.4 or 7.6 cite 8.7 for them or state them with **[M]**: regularity on conditionals (79 of 240 down, none up); the thresholds of the word procedure (14.8×, 13.0×, 11.5×; 12.3×, 13.9×, 10.6×); 10.3× with the fold forms; 13.5× to 15.3× with ten words; "is the value zero" for five of six list words; the ordering adding 3% to 5% with the filter on; counts giving 1.7× and 3.1× when used only to order; records outnumbering kept classes; the index finding 19, or 20 with variants; the look-ahead losing the branches when the bound is the size of the branches.
- The plain early-comparison control: stated after the first table, where the gains are first given; the prototype figures (2.73× in candidates for both, 2.01× against 1.68× in time) are in the second prototype finding.
- "Round" is used for each repetition at a new bound; "pass" only for the tentative pass.
- Memory: five findings, in the words of decision 8 and of 7.6. The prototype figures are given with the size handed over and with the bound raised round by round; the two instruments are said not to be comparable, and why.

Section 8.7 grew from 2,957 to about 6,800 words.

## E. The check of the numbers in 8.7

Every numeric token of the new `08.7.md` was listed (`work/nums.py`, output `work/nums87.out`) and traced. All were found. By paragraph:

- Setting, first table, qualifications: `verify-quotients.md` §2.1 to §2.5 (`q2_main.log`, `q2_main_seed2.log`, `q2_sweep.log`, `q2_length.log`).
- Counting routine: `q4-handoff/u1_residual.log` (30, 18, 25, 92.3%, 13, 17, and the line counts 9, 18, 2, 15, 6 + 3 + 5 + 9 = 23, 2,000); `b12_report.log` (53.8% and 55.5%); `b12_report_rows4.log` (81.3%, one task set).
- Probes: `verify-quotients.md` §2.6; `verify-probes.md` §3 with `exp_main_S300.log`, `exp_main_S300_v2.log`, `exp_main_EDGE-R.log`, `exp_main_EDGE-W.log`, `exp_audit.log`, `revD_vary.log`, `time_tables.log`, `exp_feedback_p1.log`, `exp_merged.log`, `p4_slices.log`, `exp_cert.log`; `tasksets.py` for the two sets with an unusual row.
- Lost answers and summed cost: `q4-handoff/c_unpredicted.log`; `b12_report.log` for the geometric means 44,187 and 40,702.
- Labels and corrections: `q4-handoff/b12_report.log`, `peek.log`.
- Near misses: `q4-handoff/b3_report.log`, `b12_report.log`.
- Store prototype: `l1-proto/logs/e1.log`, `e1-table.txt`, `e3.log`, `e5.log`, `e7.log`; `verify-proto-labels.md`.
- Vocabulary: `verify-words.md`, `q1-words/summary.log`, `sel_main.log`, `run_pool_main.out`; `verify-quotients.md` §3.1 and §2.7.
- Memory: `verify-memory.md`, `q3-memory/m1_poly.log`, `m3_extra.log`; `verify-quotients.md` §5; `l1-proto/logs/e5.log`.
- Smaller results: `verify-quotients.md` §4 and §6, `verify-quotients/q5_reuse.log`.

Six sets of figures are found in a report but not in a log kept in the repository. They rest on a checker's own run:

1. 1.6 to 2.0 times when each check is counted as a candidate: `factcheck3-A.md` finding 1 (its script is in the scratch folder `round3/fc-a/`).
2. 1,476 checks, 492 pairs, 228 and 293 pairs rejected: `factcheck3-B.md` finding 1 (script in `round3/fc-b/`).
3. The merged word by size, 12×, 23×, 30× and 22×, 24×, 24×, on 5, 22, and 24 tasks: `factcheck2-B.md` finding 3 and `factcheck3-A.md` finding 18b. The script `verify-quotients/factcheck/sweep_by_size.py` is in the repository; its output is only in `round3/fc-a/vq/sweep_by_size.out`.
4. The index finding 9 and 14 with its two other keys: `factcheck3-B.md`, list C (a rerun of `verify-quotients/factcheck/fc_reuse_labels.py`, which has no log).
5. Chance of 9 in 32, and the family scores 5 of 5 against 2.5 and 4, and 0 of 3: `factcheck2-B.md` finding 12 (`fc_syn.py`, output only in `round3/fc-a/vq/fc_syn.out`).
6. About 10 and 9 by chance inside the ties: `factcheck3-B.md` finding 22, from the 39% and 33% of `b12_report.log`.

None could not be found.

## F. Changes made under the decisions, outside any finding

- Decision 11: "answer terms" for "witnesses" in 8.2 and in X2; "property set" for "signature" throughout 8.6 and in 8.8 item 8; "the literature review" in risk 8; "adjust" for "a correction to the tables" in 8.8 item 8 and risk 4.
- Decision 1: "word" for "quotient" throughout 8.7.
- 8.0: one sentence saying that one experiment of 8.7 was run on a copy of the prototype.
- 8.5: one sentence naming the size-order rule where the table of terms and 7.2 point for it.
- Appendix D: the housekeeping list is headed as found at commit `15e64c6`, before the move; the item on the test suite and `library/` is in the past tense and says it was not rechecked after the move.

## G. For the author

- 6.2 says the group-by gives zero "for an unrelated column as readily as for a near miss". In the log the column called "unrelated" (`2*y*y`) gave zero in 4% of trials; the far-off term whose values are all different (`y + 100*x`) gave zero in 100%. 8.7 and the notes say "a far-off term whose values are all different".
- 6.2's "a little information at every distance" against finding 9 (see A.9).
- 6.4 item 3 calls ring arithmetic "the one case where labels cut stored classes by an order of magnitude" in Python; on the sequence library the one-step look-ahead gave 7.1× in classes. 8.7 says why that is not credited to labels.
- X4: the gate is against the no-guidance arm; the comparison with the plain early comparison is reported. Decide whether the control should be the bar.
- Risk 11: the retrieval measurement of §8.6 is now said not to be repeated. The other choice is a further arm in X4.
- X3 and Stage B: which stage builds the guard split for the two specs that need one.
- 8.8 item 2: whether the three further tests are in any gate.
- Appendix D is true only once these are copied into `plan_v2c_audit/`: `factcheck3-A.md`, `-B.md`, `-C.md`, `clarity-review-new.md`, the `apply-*.md` logs, `revision-notes.md`, and the reviewer's scripts with the path changed in the nine scripts that import them. The six sets of figures in E would also be better supported if the checkers' small outputs were copied.
- Notes 1.5: the placeholder line, and the word counts in it will have changed again. A trial build of the three appliers' outputs together is about 54,500 words.
- The title line of the plan keeps its em dash.
