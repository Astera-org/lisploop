# Fact-check 3-B: front matter, §8.0, §8.4–§8.8, §10, §11, Appendix D; and `revision-notes.md` Part 1

Checked: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md` (line numbers are of that frozen copy) and `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/revision-notes.md`, Part 1.
My scripts are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-b/` (`slices_per_pair.py`, `wc_sections.py`, and a copy of the verify-quotients scripts under `vq/` used for one rerun). Nothing under `/home/tlh24/lisploop` was created, edited or deleted by me.

## Notice: the repository's working tree changed while this check was running

At about 19:01 on 26 November (the brief was written at 18:47) the root kernel was moved. `git status` now shows 92 tracked files deleted from the repository root (every root `*.lisp`, `tests/`, `deprecated/`, `milestones/`, `plan7/`, `experiments/`, `bootstrap/`, `plan8.md`, `plan9.md`, `plan9-audit.md`, `architecture.md`, `architecture2.md`, `batteries-and-reflection.md`, `plan-exec.md`) and a new untracked directory `/home/tlh24/lisploop/v1/` that holds them. `v1/frame.lisp` is byte-identical to `HEAD:frame.lisp`. The root `Makefile` (19:03) and `measure_complexity.sh` (19:10) were then edited as well, so someone is reorganizing the repository as this is written. I did not do this and did not touch it. It matters for the plan in three ways. Every file-and-line reference written relative to the root (for example `frame.lisp:1581`, `bootstrap/recursion-schemas.lisp`, `tests/theories.lisp`, `deprecated/plan2.md`, `plan7/plan7.md`) now resolves under `v1/` in the working tree, though it is still right for commit `15e64c6`. The brief's own source path `/home/tlh24/lisploop/*.lisp` no longer exists. And the housekeeping bullets of Appendix D that speak of "the root kernel" (lines 1548–1556) describe a layout the working tree no longer has. If the move is the owner's, the front matter (line 3) should say that paths are those of commit `15e64c6` and that the kernel now sits in `v1/`.

---

## A. Findings on the plan (`v3-for-check.md`), most serious first

### 1. FACTUAL ERROR. The slice counts are out of 1,476 checks, not out of 500 results

- Line 1228: "Tables built from slices that hold one argument at a few fixed values rejected 287 of 500 true results for `div` and 422 for `mod`, with the slices the review chose."
- Source: the reviewer's `exp_devils_advocate.py` lines 556–573 adds one to the counter for every (pair, quotient) that is falsely rejected, under three quotients, and prints "False rejections on 500 fresh (a,b) … (out of 1500 op-domain checks each)" (`round3/q2-probes/run_reviewer.log`). `round3/q2-probes/p4_slices.log` gives the split by quotient: `div` 92 + 145 + 50 = 287, `mod` 92 + 145 + 185 = 422. The review itself (Appendix B.2 item 4) says "caused … 287 (`div`), and 422 (`mod`) false rejections", with no "of 500". Recounted with the reviewer's seed (`fc-b/slices_per_pair.py`): 492 of the 500 pairs have a non-zero divisor, so there are 1,476 checks; 228 of the 492 true results for `div` and 293 for `mod` are rejected by at least one quotient.
- Replacement: "Tables built from slices that hold one argument at a few fixed values made 287 false rejections for `div` and 422 for `mod`, out of 1,476 checks (492 fresh pairs with a non-zero divisor, each checked under three quotients), with the slices the review chose. Counted by pair, 228 of the 492 true results for `div` and 293 for `mod` were rejected by at least one quotient."

### 2. FACTUAL ERROR and INCONSISTENCY. It is the residual that is undefined, not the correction

- Line 1236: "*A correction is often not defined.* It needs two values of the same shape. For 41–43% of the classes one step from the answer, the types or the lengths differ."
- Source: `round3/q4-handoff/b12_report.log`, column "L1 undefined for the on-path class": 42 of 102 (41%) and 43 of 99 (43%) one step out, 74% and 74% two steps out, 90% and 82% three steps out. `b12.py` line 8 defines L1 as "sum of |differences| (defined only for equal types and equal list lengths)". The correction code (DL in the logs) is defined in every one of those cases: the same table gives a DL percentile for all 102 and 99 classes, and "DL percentile … n=26 of 26 defined". `verify-handoff.md` line 82–84 says the same: "A computed residual … is §6.1's correction code applied to a type-specific difference. That difference is undefined for 41–43% of true parents". The kernel's code prices a change of length (`v1/frame.lisp:1566-1578`, `len-delta`), and the plan's own §8.5 table (line 1131) quotes a correction between sequences of different lengths: "13 bits from `()` to `(1 2)` and 1 bit back". The term table (line 34) defines a correction as "the bits the kernel's codec charges to turn a predicted value into the true one", which is never undefined.
- The same mistake is at line 668 (§6.2, "it needs the two values to have the same shape: it was undefined for 41–43% of the classes one step from an answer") and line 810 (§6.8, "a correction is undefined between values of different shape"). Those lines are outside my scope and need the same change.
- Also: the 41–43% is of the *on-path* classes one step out (the true parents), not of all classes one step from the answer.
- Replacement: "*A residual is often not defined.* An element-wise difference between a class and the target needs two values of the same type and the same length. For 41–43% of the on-path classes one step from the answer they differ, and for 74–90% of those two or three steps away. The correction code is defined in all of these cases, because it prices a change of length; it says nothing only when the types differ, which was so for about one on-path class in ten."

### 3. OVER-STATEMENT. "It cannot find an answer that needs a guard" rests on a strict filter at a size handed over by an oracle, and a log of this round shows the opposite on the Python library

- Line 1282 (§8.8, point 9): "It is tested knowledge, it acts on the last step, and it cannot find an answer that needs a guard (§8.7)."
- Line 1356 (risk 14): "The tentative label pass hides answers that need a guard. In the prototype a strict filter lost the guard split in 7 of 9 guarded runs (§8.7)".
- The same sentence is at line 94 (§1.4) and line 875 (§7.2, step 2), outside my scope.
- Source for the prototype: `round3/l1-proto/logs/e3.log`. Every "LOST" there is in a mode called `strict@L`, defined in the log's header as "at size level L (the level after which plain finds its split: an ORACLE) only label-feasible candidates are evaluated". So the evidence is a filter applied at the final size with no slack.
- Source against the general claim: `round3/q4-handoff/b3_report.log`, in both blocks headed "CONDITIONAL near-miss tasks: 60": "review order (label-filtered passes until both branches are stored, pass {4: 19, 5: 41}): 60 of 60 tasks reach it within pass 6, both branches stored in 60; candidates geo-mean 1345, against 1333 for the plain bank to size 3 (1.0x more)" and the same for seed 32 ("60 of 60 … both branches stored in 60"). The code is `b3.py` lines 366–380. Under the filter as §8.7 itself defines it (line 1192: a candidate is skipped when its tables say it cannot give the target's labels "within the size that remains", with the bound deepened), a near miss of size s is kept as soon as the bound reaches s plus its label distance, which was 1 or 2. So on 120 planted conditionals the label-filtered passes stored both branches in every task, one or two passes later and at no extra cost. `verify-handoff.md` does not report this line of its own log.
- What stands: a filter applied strictly at the last size discards near misses; and running the near-miss check on every evaluated candidate cost half as much (`b3_report.log`, D / D2 = 2.07× and 1.97×, on the offset and scale tasks).
- Replacement for line 1282: "**The label filter is one tentative pass, not the search.** It is tested knowledge, and it acts on the last step. Applied strictly at the final size it discards the near miss that a guard is built from: in the store prototype, with the final size handed over, such a filter lost the guard split in all 9 guarded runs, and in 7 of 9 when Boolean-valued candidates were exempted (§8.7). On the Python library, where the bound is deepened and a class is kept while its labels can still reach the target's, both branches of a planted conditional were still stored in all 120 tasks, one or two passes later. Near-miss proposals are placed in the plain pass behind the filter (§7.2) because there they see every candidate and cost half as much."
- Replacement for the first cell of risk 14: "A label filter applied at the final size hides answers that need a guard. In the prototype such a filter, given the final size, lost the guard split in all 9 guarded runs, and in 7 of 9 with Boolean-valued candidates exempted. On the Python library, with a deepened bound, the branches of a planted conditional survived the filter in all 120 tasks (§8.7). Which of the two the kernel's tentative pass resembles is not known."

### 4. FACTUAL ERROR. The strict filter lost the split in 9 of 9 runs; 7 of 9 is the variant that exempts Boolean results

- Line 1249: "A near miss fails the labels on exactly the rows it gets wrong, so a filter that skips every candidate whose labels do not match skips the near miss too. The split was lost in 7 of 9 guarded runs."
- Line 1394 (§11.1): "As a strict filter it lost the guard split in 7 of 9 guarded runs."
- Line 1356 (risk 14) repeats it.
- Source: `round3/l1-proto/logs/e3.log`. The row `strict@L q3`, which is the filter the sentence describes, reads "LOST (no program)" on all nine tasks. The row `strict@L q3, guards exempt` is lost on seven; it survives on `shift-seq (spec)` and `spec shift-seq`. `verify-proto-labels.md` §3 item 6 says so in full: "the split was lost in 9 of 9 guarded tasks … With Boolean guards exempted it was still lost in 7 of 9." One of the nine is `spec map-adjacent`, whose split is the 29/200 impostor of §8.5, so eight right answers were at stake, not nine. All of these runs are at a size handed over by an oracle.
- Replacement for line 1249: "A near miss fails the labels on exactly the rows it gets wrong, so a filter that skips every candidate whose labels do not match skips the near miss too. With the final size handed to the filter, the split was lost in all 9 guarded runs. With Boolean-valued candidates exempted, so that the guard itself survives, it was still lost in 7 of 9. One of the nine splits was the 29/200 impostor of §8.5, so eight right answers were at stake."
- Replacement for line 1394: "As a strict filter at a final size that was handed to it, it lost the guard split in all 9 guarded runs, and in 7 of 9 when Boolean-valued candidates were exempted."

### 5. INCONSISTENCY. §11.1 gives the zero-loss result to the wrong row of the §8.7 table

- Line 1392: "Probes drawn as small programs produce them lost no answer in 1,700 runs at 1,000 probes per operator, where random probes lost 12."
- Source: the plan's own table, line 1220, row "as small programs produce them": 2 lost of 900 at 1,000 probes (`exp_main_S300_v2.log`, `bank2 1000 | 2`). The rule that lost none is the next row, line 1221, "as small programs produce them, then spread evenly over pairs of labels" (`bank2+strat2`: 0 + 0 + 0). The 12 for random probes is right (5 + 1 + 6).
- Replacement: "Probes drawn as small programs produce them, and then spread evenly over pairs of labels, lost no answer in 1,700 runs at 1,000 probes per operator, where random probes lost 12."

### 6. INCONSISTENCY. "Two fifths … tested and nothing more" contradicts the sentence before it and §6.5

- Line 1230: "Only the tables for length follow from anything that can be proved cheaply, and those alone give 3.6×. So roughly two fifths of the gain rests on entries that are tested and nothing more."
- Source: `round3/q2-probes/exp_cert.log`, part 5. Deterministic entries only: 10.16× of 16.96× ("60% of the factor"). Certifiable tier only: 3.60× ("21% of the factor"). "Deterministic" means one output label in the truth estimate U, which is itself the union of ten tables of 30,000 probes and an exhaustive enumeration of short lists; it is a sample. Line 771 (§6.5) says this correctly: "'exactly one label in every probe' is still a sample … So the tables are tested knowledge throughout". Under the term table (line 38) nothing but the length tier is certified. So the two fifths is the share that rests on entries allowing more than one output label, and the share that rests on tested knowledge is everything above 3.6×.
- Replacement: "About 71% of table entries allow exactly one output label, as judged against the union of ten tables of 30,000 probes each and an exhaustive enumeration of short lists. Filtering with those entries alone keeps a gain of 10.2× of the 17.0×. Only the tables for length follow from anything that can be proved cheaply, and those alone give 3.6×. So everything beyond 3.6× rests on entries that are tested and nothing more, and about two fifths of the factor rests on entries that allow more than one output label, where a label the probes missed cannot be told from one that cannot occur."

### 7. OVER-STATEMENT. "Every empirical claim it makes was reproduced"

- Line 5: "Every empirical claim it makes was reproduced independently before it was used here, and several were corrected (§8.5 to §8.7)."
- Line 1190: "Each of those was rebuilt independently before it was used here".
- Source. "Reproduced" is not what the verdict tables say. NOT REPRODUCED: the contribution of soft ranking (`verify-quotients.md` Q2e); the lifted-space "1.0× RAM whenever `at` …" (`verify-memory.md`); the word-bootstrap mechanism (`verify-words.md` C3); regime 3 of the one primitive and "tables see multi-step structure" (`verify-handoff.md` U1, U2); "nothing when `at` is outermost" (`verify-proto-labels.md`). TRUE BY CONSTRUCTION: the six selected words, the 0/200 misses, `len(seen) == len(bank)`, the undirected 1.0×. "Every … it makes" also fails: the reuse experiment was "Reproduced in outline; not a faithful rebuild" (`verify-quotients.md` §6, and "Not done: … a faithful Q5"); the review's merge-and-shrink with a shrink step and its CEGAR refinement were not built; R6′ in `verify-review.md` is "COULD NOT TEST"; and for §2.5.1, §2.5.2 and both examples of Appendix B.3 "No script in the reviewer's directory computes" them (`verify-handoff.md` §2), so there was no experiment of the review's to reproduce, only the claim to test.
- On the question asked of me: I found no empirical claim of the review's §2.5 or Appendix B that the plan *uses as a result* and that no report tested. The plan's numbers in §8.7 are its own measurements. The two places where the plan leans on something only partly tested are (a) the reuse result of line 1268, which rests on the outline rebuild and on an exploratory rerun with a script and no log (I reran it, see the correct-claims list), and (b) Appendix B.1 item 1 of the review, its corrected stored-class figures 51 / 51 / 2,269, which no report recomputed and which the plan does not use.
- Replacement for line 5: "Every empirical claim of the review that this plan uses was re-tested independently before it was used here. Some reproduced, several were corrected, several did not hold or held only because of how the review's own test was built, and its experiment on reuse was rebuilt only in outline (§8.5 to §8.7; `plan_v2c_audit/revision-notes.md` gives the verdict on each)."
- Replacement for the clause at line 1190: "Each of those was rebuilt independently before it was used here, except the experiment on reuse across tasks, which was rebuilt only in outline, and several questions the review did not ask were measured as well **[M]**."

### 8. OVER-STATEMENT. The reason given for "doubles the gain" is not what the measurement shows

- Line 1234: "Applying them throughout enumeration still doubles the gain over applying them only at the final size, 15.6× and 16.9× against 7.8× and 8.0×, because every pass of the deepening has a last step."
- Source: the numbers are right (`b12_report.log`, B4 (b)). The cause is not in `verify-handoff.md`, and the harness does not support it. In `b12.py` lines 255–262 and 493–516, plain search is one bank built once, with no deepening, and "labels LATE" is that plain bank below the answer's size plus a filtered last level. Its cost is dominated by the levels below the answer (for answers of size 5: 35,448 candidates below, 625,171 at the last level before filtering). "Labels EARLY" pays extra passes and is still cheaper, because it also skips, before evaluation, the candidates one size below the answer whose labels cannot reach the target's in one step. That is the 43–47% of the same bullet.
- Replacement: "Applying them throughout enumeration still doubles the gain over applying them only at the final size, 15.6× and 16.9× against 7.8× and 8.0×. The cause was not isolated. The likely one is that during enumeration the tables also skip, before they are evaluated, the candidates one size below the answer that cannot reach the target's labels in one more step, and that level is the largest of those below the last."

### 9. MISSING CAVEAT. The percentiles are means; one step out the correction is a strong signal, not a weak one

- Line 1235: "*Corrections are weakly informative at every distance.* … The class on the path to the answer stands at the 20th to 23rd percentile one step out, and at the 29th to 39th further out, where the 50th is chance."
- Line 1393 (§11.1): "Corrections were weakly informative everywhere."
- Source: `b12_report.log`, B1. One step out the mean percentile is 20.5 and 23.0, but the median is 1.9 in both sets and the on-path class is in the best tenth in 68% and 66% of cases; it is in the worse half in 18 of 102 and 23 of 99 (`peek.log`). Two and three steps out the means are 32.2, 39.0, 28.9, 32.7 and the medians 23.4, 40.8, 27.6, 33.3. The report's own bottom line is narrower than the plan's: "weakly informative several steps out". The cut that lost answers lost 31 of 119 in one set and 37 of 115 in the other; the plan gives only the first.
- Replacement for line 1235: "*Corrections carry a signal at every distance: strong next to the answer, weak further out.* Rank every class of one size by the cost of the target given that class. One step from the answer the class on the path is in the best tenth in two cases of three (its median is about the 2nd percentile), and in the worse half in about one case of five, so its mean is the 20th to 23rd percentile. Two and three steps out its mean is the 29th to 39th percentile and its median the 23rd to 41st, where the 50th is chance. That is too weak to cut on: keeping only the better half at each size lost 31 of 119 answers in one task set and 37 of 115 in the other."
- Replacement for the sentence at line 1393: "Corrections were a strong signal one step from the answer and a weak one further out, and too weak anywhere to cut on."

### 10. INCONSISTENCY. The term table says the labels are the words; §8.7 and §11 use "word" for the quotient

- Line 35: "A quotient of values is a small term that takes a value to one of a few labels, such as its sign. The labels are the words of the kernel's vocabulary (§6.2)."
- Usage: line 1256 "13.0× with six words and 15.3× with ten"; line 1258 "*Several labels per word matter in search.* Allowing at most 2, 4, 6, or 8 labels per word"; line 1257 "Nine of the ten have the length in them"; line 1259 "two of the six words carried over"; line 1392 "Words chosen by score"; line 1417 "words chosen by score". In all of these a word *has* several labels, so a word is a quotient. (Line 706 in §6.4, "its labels are the words", agrees with the term table and disagrees with §6.5 and §8.7.)
- Replacement for line 35: "A quotient of values is a small term that takes a value to one of a few labels, such as its sign. A quotient that the kernel keeps in its vocabulary is called a word, and its labels are the values the word can take (§6.2)." Line 706 then needs the matching change.

### 11. INCONSISTENCY. Two different times for building tables from random probes

- Line 1224: "Building the tables takes 17.6 s under the rule in bold against 1.1 s at random."
- Line 1260: "Learning the tables for a chosen vocabulary takes 0.2 s with random probes."
- Source: `round3/q2-probes/time_tables.log`: 17.57 s and 1.11 s, both at 1,000 probes per operator, one run each, "one process on a loaded machine" (`verify-probes.md` line 47). `verify-quotients/q2_tables_cost.log`: 180.2 ms at 2,000 random probes, best of five, for the six hand-listed quotients (not "a chosen vocabulary"). The two figures for the same job differ twelvefold per probe, and the reader meets both within forty lines.
- Replacement for line 1224: "At 1,000 probes per operator, building the tables took 17.6 s under the rule in bold against 1.1 s at random, in one run each on a loaded machine; the ratio, about sixteen, is the figure to keep."
- Replacement for line 1260: "Learning the tables for the six hand-listed quotients took 0.2 s at 2,000 random probes per operator in the earlier timing (best of five runs), and about sixteen times the random figure under the probe rule adopted above."

### 12. MISSING CAVEAT. The 17× and 22× from reordering depend on where `at` sits in the operator list

- Line 1250: "Reordering cut candidates 17× and 22× on `reverse` and `rotate`, and 2.5× and 6× on `map-adjacent`."
- Source: `round3/l1-proto/logs/e7.log` and `verify-proto-labels.md` §3 item 3: over six operator orders the gain on `reverse` ran from 1.04× to 22.8× and on `map-adjacent +` from 2.25× to 23.8×; with `at` first in the list, `reverse` and `rotate` gave 1.04× and 1.14×. On the five guarded tasks the reordering gave 1.00× (`e1-table.txt`). The sentence's conclusion (a plainer test does as well) is right; the four numbers are properties of one operator order.
- Replacement: "With the prototype's own operator order, reordering cut candidates 17× and 22× on `reverse` and `rotate`, 2.5× and 6× on `map-adjacent`, and nothing on the guarded tasks. Those figures are set by the order of the operator list: over six orders the cut on `reverse` ran from 1.04× to 23×."

### 13. MISSING CAVEAT. "22× in place of 17×" compares one merged quotient, used alone, with all six

- Line 1227: "*Merging three quotients into one* gave 22× in place of 17× and still lost 10 of 600 answers at 10,000 probes."
- Source: `round3/q2-probes/exp_merged.py` lines 4–5 and 21: the run used `merged3` = "one quotient: sign x parity x order", without the three length quotients (`verify-probes.md` §6: "not with the merged product plus the three length quotients"). The like-for-like figures in `verify-quotients.md` §2.4 are 23.9× merged against 11.3× for the same three kept separate, and 28.2× for merged-plus-length against 15.7× for the six. The loss count is right (`exp_merged.log`, `bank2+strat2 10000 none | 10`).
- Replacement: "*Merging sign, parity, and order into one quotient of 38 labels,* used on its own, gave 22× where the six separate quotients give 17×, and still lost 10 of 600 answers at 10,000 probes. It is left out."

### 14. INCONSISTENCY. The X4 gate charges a one-off cost of minutes against searches of seconds, and sits above the measured time gains

- Line 1404: "Count the fair cost: every pass of the search, the fallback whenever the filtered pass misses, the look-ups, and the time to choose the words and build the tables. … *Gate:* at least 3× lower total wall time on held-out tasks".
- What the text says elsewhere: choosing a vocabulary took "about 21 CPU-minutes" (line 1260, line 967); building tables under the adopted rule took 17.6 s (line 1224); wall time improved "1.3×, 2.0×, and 4.2× at program sizes 4, 5, and 6" (line 1207); in the store prototype labels gained nothing in time over a plain comparison (line 1250). X4 runs on "X3's tasks", the 16-spec ladder, whose searches the plan measures in milliseconds to seconds. Read literally, a total that includes 21 CPU-minutes of word choice cannot be 3× lower than unguided searches that take seconds, whatever the tables are worth. And without the one-off cost, the only measured time gain above 3× is at size 6.
- Nothing in X4 is already done, and nothing is strictly impossible. The gate needs to say over what the one-off cost is spread.
- Replacement for the two sentences: "Count the fair cost of each search: every pass, the fallback whenever the filtered pass misses, and the look-ups. Report the one-off cost of choosing the words and building the tables separately, with the number of tasks after which it is repaid. … *Gate:* at least 3× lower total search wall time on held-out tasks, including those that need a never-used entry, with no answer lost after the fallback, and a one-off cost that is repaid within the task set; or §6.4 and §6.5 are not built further."

### 15. INCONSISTENCY. Two risks point at experiments that no longer do what the risk says

- Line 1353 (risk 11): "the retrieval measurement of §8.6, repeated on the kernel's tasks (X4)". X4 as rewritten (line 1404) has five arms, none of which is retrieval by shared properties; the earlier arm "flat signatures with counts" is gone.
- Line 1356 (risk 14): "X3 and X4 count answers that only the fallback finds". X3 (line 1403) has no tentative pass and no fallback and counts no such thing; only X4 does.
- Replacement for risk 11's second cell: "the retrieval measurement of §8.6, repeated on the kernel's tasks as a sixth arm of X4; a budget account for every attempt (X9)", and add that arm to X4, or else: "a budget account for every attempt (X9); the retrieval measurement of §8.6 is not repeated".
- Replacement for risk 14's second cell: "near-miss proposals run in the plain pass, on every candidate evaluated (§7.2); X4 counts the answers that only the fallback finds".

### 16. FACTUAL ERROR (small). The kernel's specs have 3 to 13 rows, not 4 to 13

- Line 1103: "The outside review ran it instead on the kernel's `:spec` rows, which are far fewer: 4 to 13 rows per spec."
- Source: `verify-review.md` results table (line 78): `argmax-corr | 3`; `verify-review/r1-spec.lisp` line 122: ":spec/argmax-corr, build-batteries.lisp:881-884 (3 rows)". The previous version said "4 to 13" of the thirteen specs that were solved, which is true of those; the new sentence says it of all sixteen. Line 90 (§1.4, outside my scope) has the same phrase.
- Replacement: "The outside review ran it instead on the kernel's `:spec` rows, which are far fewer: 3 to 13 rows per spec."

### 17. INCONSISTENCY. "Stage A" in §8.5 means the present kernel's phase, and the text does not say so; and code lengths do not "sum to 1.5"

- Line 1133: "the code lengths sum to 1.5 for Booleans, 1.19 for GF(5), and 1.41 for integers, where a prefix code allows at most 1. Stage A does not price cell by cell, and leaves one bit per model unpaid instead."
- Source: the term table, line 42, promises that "the text says which is meant"; here it does not, and a reader takes it for Stage A of this plan. Appendix D (line 1556) words the same fact correctly: "the main pricing path of the kernel's first search phase". The quantity that is 1.5 is the Kraft sum, the sum of 2 to the minus length over all values (`verify-review.md` R4: "conditional Kraft sums 1.5 …"), not a sum of code lengths.
- Replacement: "broken wherever cells are priced one by one, because an exact cell costs 0 bits: summing 2 to the power of minus the code length over all values gives 1.5 for Booleans, 1.19 for GF(5), and 1.41 for integers, where a prefix code allows at most 1. The present kernel's first search phase (which its code calls "Stage A") does not price cell by cell, and leaves one bit per model unpaid instead."

### 18. INCONSISTENCY. "Each with a gate fixed in advance" is not true of X8

- Line 43: "*X1 to X9* | The experiments of §11.2, each with a gate fixed in advance."
- Line 1399: "Each experiment has a gate fixed in advance."
- Line 1408: "**X8. Self-description.** … *Gate:* none; this is exploratory."
- Replacement for line 43: "The experiments of §11.2. Each has a gate fixed in advance, except X8, which is exploratory." Replacement for line 1399: "Each experiment except X8 has a gate fixed in advance."

### 19. MISSING CAVEAT. "Worth two or three sizes" carries a small-scale gain to the memory wall by arithmetic

- Line 1095: "With classes growing ×3.0 per unit of size, that is worth two or three sizes (§7.6)."
- Source: `verify-memory.md` line 80 labels this "Projection to the §8.4 wall (arithmetic, not measured)". The 8.5× to 26× was measured in Python with two variables, at sizes 7 to 13, where plain search holds at most 17,609 classes; the wall of the table above is at size 16 with three variables in the Lisp prototype, about three thousand times as many classes. The arithmetic itself is right (the logarithm of 8.5 to base 3 is 1.9, of 26 is 3.0).
- Replacement: "If the same ratio held at the wall, which was not measured, then with classes growing ×3.0 per unit of size it would be worth two or three sizes (§7.6)."

### 20. MISSING CAVEAT. Two results of this round that would qualify the bullets on feedback and on slices

- Line 1226: "*Feeding back the transitions of tasks solved by the fallback* removed nothing once the probes were good, because nothing was lost. It is left out." Source: true of the 700-task searches (`exp_feedback_p23.log`). On the 4,000-task stream, where the same paragraph has just said the tables are "still not sound", feedback cut the rate of wrong entries met from about 0.55 to about 0.13 per 1,000 tasks after the first thousand (`exp_feedback_p1.log`, `bank2+strat2 3000`; `verify-probes.md` line 53, which calls feedback "a cheap optional extra"). Add: "On a stream of 4,000 tasks it did cut the rate at which wrong entries were met, from about 0.55 to about 0.13 per 1,000 tasks, so it remains a cheap option."
- Line 1228: "Those slices were a bad case, and most random choices of slice reject nothing. The rule stands for a plainer reason". Source: `p4_slices.log`: at the same budget of 100 probes, random *joint* pairs gave a median of 14.6 false rejections per 500 pairs for `div` and for `mod`, where random slice sets gave a median of 0; the review's comparison set a 625-pair joint grid against 100 slice probes (`verify-probes.md` §4, "Unequal budgets"). Add: "At an equal budget of 100 probes, joint probes at random rejected more than random slices did (a median of 14.6 per 500 pairs against 0), so the measurement does not decide the matter; the rule is adopted on the argument that follows." (Line 765, outside my scope, calls this rule "measured".)

### 21. OVER-STATEMENT. "Among the dearest" rests on three lost tasks, one of which was cheaper than average

- Line 1355 (risk 13): "The tasks they lose are among the dearest to solve again".
- Source: `round3/q4-handoff/c_unpredicted.log`: at 2,000 probes the lost tasks cost plain search 16,015, 311,507 and 318,721 candidates. The geometric mean plain cost of those task sets is 44,187 and 40,702 (`b12_report.log`). Two of three are dear; one is below the mean.
- Replacement: "In the one run where this was looked at, two of the three tasks lost were among the dearest to solve again, which is enough to halve the saving summed over tasks".

### 22. MISSING CAVEAT. Sample sizes behind three sentences of "Where labels act"

- Line 1232: "That was measured on 234 tasks of three and four operators." The on-path figures of the four bullets (0 of 410, the percentiles, the ties) come from 179 of the 234: the 55 tasks where plain search found a shorter program than the reference are excluded (`b12_report.log` headers: "on-path classes (… 91 tasks)" and "(… 88 tasks)"; `verify-handoff.md` §6). Replacement: "That was measured on 234 tasks of three and four operators; the figures about the class on the path to the answer use the 179 of them in which plain search found the reference program and not a shorter one."
- Line 1237: "*Next to the answer each breaks some of the other's ties.* … Inside those ties the correction ranks it first in 46–54% of cases, against 33–39% by chance." Source: 12 of 26 and 14 of 26 (`b12_report.log`, B2). With 26 cases per set, 46% against 39% is no evidence on its own. And only one direction was measured: the correction breaking the labels' ties. Replacement: "*Next to the answer the correction breaks some of the labels' ties.* With six quotients the labels leave the true parent tied with other classes for a quarter of the true parents. Inside those ties the correction ranks it first in 12 and 14 of 26 cases in the two task sets, where chance would give about 10 and 9."
- Line 1241: "30× to 35× against plain search". Counting each residual check as one candidate, the same logs give 19× and 23× (`b3_report.log`, "counting each residual check as one candidate"). Add the clause "or 19× to 23× if each check is counted as a candidate".

### 23. X3: what the gate asks, set against the rest of the text

- Line 1403: "*Gate:* at least 14 of 16 held-out-sound (today 8–10); … `foldl` either solved or reported as underdetermined".
- Nothing in X3 is already done, and nothing is said to be impossible. Two things should be stated, because the text elsewhere bears on them. First, the prototype reaches 13 of 16, and the three it misses are `foldl`, whose rows "do not determine the function argument" (line 1114), and `best-shift` and `argmax-corr`, of which line 909 says "`best-shift` plausibly needs two lifts, and two lifts were not tested". So 14 can be reached only by solving one of the two correlation specs, or by counting a correct report of "underdetermined" for `foldl` as a pass; the gate does not say which. Second, "the bounded look-ahead of §7.2" needed labels on two of its seven runs (line 1251), and labels enter in Stage C, after X3 (line 1417); in Stage B it can only be the types-only form. Likewise the near-miss proposals that build a guard split are listed under Stage C, while two of X3's specs need a guard.
- Replacement for the gate's first clauses: "*Gate:* at least 14 of 16 held-out-sound (today 8–10), where a spec that is correctly reported as underdetermined by its rows counts as sound; nothing returned that fits the rows and fails held-out; no guard split accepted that fails the size-order rule of §8.8. Also measure what the size-order rule costs with and without the bounded look-ahead of §7.2, in its types-only form, since labels arrive in Stage C."

### 24. Appendix D. The kept scripts that rerun the reviewer's experiments depend on a folder that is not in the repository

- Line 1513: "The scripts and logs behind each measurement are in the folder named beside it." Line 11: "**[M]** | measured during this audit; the script is kept".
- Source: nine scripts under `plan_v2c_audit/round3/` read the reviewer's code from a hard-coded path in this session's scratch folder, `/tmp/claude-1000/…/scratchpad/round3/reviewer`: `q2-probes/revD_vary.py`, `q2-probes/run_reviewer.py`, `q1-words/rev_expb_vary.py`, `q1-words/run_reviewer.sh`, `q3-memory/r0_expA.py`, `q3-memory/r0_run_reviewer.sh`, `q3-memory/r0_count.py`, `l1-proto/run_reviewer_a.py`, and `l1-proto/make_reviewer_a2_order.py`. That folder was not copied into `plan_v2c_audit/` and a reboot can clear it. The figure "held for 7 of 20 seeds" (line 1214) is produced by `revD_vary.py` and cannot be rerun from the repository as it stands. The five round-3 reports also give the scratch folder, not `plan_v2c_audit/round3/…`, as their work directory (line 3 of each).
- Every report and folder that Appendix D names exists, except `factcheck3-*.md`, which are being written, and `plan_v2c_audit/revision-notes.md`, which is still in the scratch folder. Each scope description fits its report. Four files in `reports/` are not listed: `clarity-gaps-sec2.md`, `clarity-gaps-sec4-9.md`, `glossary-sec2.md`, `glossary-sec4-9.md`; the two gap logs are the record of what the clarity pass could not source and are worth a row.
- Replacement for the sentence at line 1513: "The scripts and logs behind each measurement are in the folder named beside it. The reviewer's own scripts, which several of the round-3 scripts import, are copied in `round3/reviewer/`." (That requires copying the folder and replacing the hard-coded path in the nine scripts.)

### 25. COSMETIC

- Line 1214: "So five ways of choosing probes were compared with nothing written by hand about which cases matter". The fifth row of the table is the review's hand-chosen transforms. Replacement: "So four ways of choosing probes that use nothing written by hand about which cases matter were compared with each other and with the review's hand-chosen transforms". (The report compared seven rules; the two left out of the table, `push2` and `oelog3`, change no conclusion.)
- Line 1214: the word "stratifying" is in quotation marks; the review's words are "*Stratify by current words*" and "stratified evenly across occupied quotient buckets" (review, line 295). Quote one of those.
- Line 1214: "held for 7 of 20 seeds". These are probe seeds; over 10 task seeds it was never zero (`revD_vary.log` part 5: 2 to 9 misses). Replacement: "held for 7 of 20 probe seeds, and for none of 10 other task seeds".
- Line 1216, column heading "Wrong table entries met per 1,000 tasks". The log counts tasks whose reference program meets at least one wrong entry (`exp_audit.py`: "tasks with a reference-path defect, per 1,000 tasks"), on the random stream of 4,000 tasks, mean of ten seeds. Replacement: "Tasks whose reference program meets a wrong table entry, per 1,000 tasks of a random stream, at 1,000 / 3,000 probes".
- Line 1190: "Everything in this section except the last experiment is standard-library Python on a library of operators written by hand for the purpose." The Lisp experiment is not the last in the section, and the integer scores, the ring polynomials and the guards are not on that library. Replacement: "Everything in this section is standard-library Python, except the experiment headed 'In the store prototype', which is Lisp. The search experiments use a library of operators written by hand for the purpose."
- Line 1243: "It does nothing for a scale (3 or 4 of 32)". The correction alone put the scale near miss first in 0 of 32, and regularity moved its median rank from about 140 to about 15 (`b3_report.log`). Replacement: "It does little for a scale: first in 3 or 4 of 32 tasks, against none by the correction's size alone".
- Line 1251: "On the seven guarded runs". These are a different set from the nine of line 1249 (they leave out `spec map-adjacent` and `spec last-or`). Say "On seven guarded runs". The plain arm of one of the seven stopped at its budget of 15 million candidates (`e5.log`, `scan f init a (spec) plain 15000001`), so the 36× is a lower bound for that run.
- Line 1255: "`(sgn x)` ranks first of 1,109 candidates". With truncating division it is 4th, and on a grid of −20 to 20 it is 2nd (`verify-quotients.md` §3.1). Add "on this grid, with floor division".
- Line 1122: the previous version's sentence "With the shape searched rather than given, the aggregate path also returns impostors on `foldl` and `argmax-corr`" was dropped. It is a limit of the mechanism this paragraph recommends and should stay.
- Line 1368 against line 754: §10 says the plan depends on "a vocabulary that a system chooses for itself and that goes on improving its own search"; §6.5 says re-choosing the vocabulary is "cheap insurance, not a source of compounding". Say in §10 that what Stage C depends on is the self-chosen vocabulary passing X4, and that its going on improving is hoped for and not depended on.

---

## B. Findings on `revision-notes.md`, Part 1

### B1. FACTUAL ERROR. The word accounting of §1.5 has two false statements and does not add up

- Line 82: "Stating findings instead of a ledger in §8 removed about 1,400." and "The new material of §6 and §7 is about the length of what it replaced."
- Source: word counts by section of `git show HEAD:plan_v2c.md` and of the frozen copy (`fc-b/wc_sections.py`). Section 8 went from 6,734 to 7,728 words: it is about 1,000 longer. Restating old §8.6 as §8.5 saved 137; §8.7 grew from 2,145 to 2,957 and §8.8 from 247 to 468. Sections 7.2 and 7.4 to 7.6 went from 2,491 to 4,126 words (7.2 alone from 839 to 1,843). Section 6 went from 5,349 to 5,656. The note's own items sum to 38,300 − 3,600 − 1,400 + 3,800 + 650 = 37,750, against "about 43,000". The other figures are right or close: 38,320 before, 43,082 now, 3,639 for the three appendices, 628 for the front matter, about 4,500 added to §2, §4, §5, §7.1, §7.3 and §9 (about 4,000 if the 549 words of old Appendix B that went into §2.8 are set aside), §2 at 6,632 and §8.1–§8.4 at 2,046.
- Replacement for the paragraph: "The plan was 38,300 words before this revision and is now about 43,100. Moving three appendices out removed about 3,600. The table of terms added about 630. The clarity pass added about 4,000 to sections 2, 4, 5, 7.1, 7.3 and 9, nearly all of it definitions of terms that had been used without one. Section 8 is about 1,000 words longer than before, not shorter: restating §8.5 as findings saved about 140, and the new measurements took §8.7 from 2,150 to 2,960 words. The rewritten parts of §7 (7.2 and 7.4 to 7.6) grew from about 2,500 to about 4,100 words, and §6 from about 5,350 to about 5,650. Sections 10 and 11 grew by about 400 together. So the plan is longer for two reasons: the first-time reader's review found the main obstacle to be undefined internal vocabulary, and the new measurements and the order of a search needed room."

### B2. OVER-STATEMENT. Not every claim had a script, and one script prints different numbers

- Line 50: "Each claim was first run with the reviewer's own scripts, which print the numbers the review quotes in every case."
- Source: `verify-handoff.md` §2: "No script in the reviewer's directory computes the five-regime table, either example in Appendix B.3, or any stage-3 quantity … there was nothing of the reviewer's to re-run." So rows 1, 2, 4, 5 and 6 of the table had no script. And `round3/q3-memory/r0_expA.log` shows the reviewer's `exp_devils_advocate.py` EXP A1 printing "TRUE RAM Gain" of 4.9×, 5.5× and 6.0× for the three targets for which the review quotes 9.4×, 22.6× and 22.9×; the quoted figures come from the other script, `verify_ram_and_nmi.py` (`r0_verify_ram.log`). `verify-proto-labels.md` §7 notes this.
- Replacement: "Each claim that has a script behind it was first run with the reviewer's own scripts. These print the numbers the review quotes, with one thing to note: for the three polynomial targets, one of the two scripts prints memory gains of 4.9×, 5.5× and 6.0× under an earlier rule, and the other prints the 9.4×, 22.6× and 22.9× that the review quotes. The claims of §2.5.1 and §2.5.2 and both examples of Appendix B.3 have no script. They are argued and not measured, so there was nothing of the reviewer's to run."

### B3. MISSING CAVEAT. Row 2 names the failure that did not occur and leaves out the one that did

- Line 55: verdict "holds"; "The one failure it invites, a target with a label no table mentions, occurred in none of 234 tasks".
- Source: `verify-handoff.md` verdict "REPRODUCED, with a cost … A transition missing from a table: 3 of 234 answers lost at 2,000 probes", and §3 item 7: "the risk is a missing transition, not an unseen label". The review's wording of the claim is "**Online solver (`§7.2`):** Reads those precomputed tables via $O(1)$ lookups."
- Replacement for the verdict and third cell: "holds, with a cost | Adopted. A target with a label no table mentions occurred in none of 234 tasks. The failure that did occur is a transition missing from a table: at 2,000 random probes per operator it lost 3 of 234 answers, and those three cut the saving summed over tasks from about 12× to 6.6×. That is why the fallback stays."

### B4. MISSING CAVEAT. "Reversed in 2 of 3 seeds" is by the review's L1 measure; by the kernel's correction code it reversed in 1 of 3

- Line 58: claim "so corrections mislead far from the answer"; "On eight rows the comparison reversed in 2 of 3 seeds."
- Source: `round3/q4-handoff/b3_example.log`. By L1 the right step is closer in seeds 1 and 2 (218 against 224, 191 against 250) and the wrong step in seed 3 (240 against 213). By the correction code, which is what the row's word "corrections" means in the plan, the wrong step is cheaper on the review's row (26 against 27 bits) and in seeds 1 and 3 (279 against 290, 304 against 316), and the right step only in seed 2 (265 against 274). The review's own words are that a ruler `|y − U|` "is blind to multi-step plans", with L1 = 8 against 12.
- Replacement for the third cell: "Not used as evidence. On eight rows, by the review's own measure (the sum of absolute differences) the comparison reversed in 2 of 3 seeds; by the kernel's correction code the wrong step stayed the cheaper one in 2 of 3. Measured over the 179 tasks where it could be measured, the class on the path to the answer ranks well above chance one step out and a little above chance further out, so corrections are a weak guide far from the answer and not a misleading one."

### B5. FACTUAL ERROR (small). Row 1: the column the log calls "unrelated" was told apart; it was the far-off term that was not

- Line 54: "on a task's few rows the group-by returned zero for a near miss and for an unrelated column alike, in all of 2,000 trials".
- Source: `round3/q4-handoff/u1_residual.log` line 35: "the identity group-by reports ZERO residual for U in 100%, for W in 4%, for V in 100%", where U is the near miss, W = `2*y*y` is labelled "unrelated", and V = `y + 100*x` is "a far-off term".
- Replacement: "on a task's few rows the group-by returned zero for a near miss and for a far-off term whose values are all different, alike, in all of 2,000 trials; it does tell apart a column whose values repeat".

### B6. INCONSISTENCY. Rows 9 and 10 point to §8.7 for results that §8.7 does not contain

- Line 62: "With every size filtered and a table for `at`, stored classes fell 1.4× to 5.7× | §8.7". Line 63: "moving `at` in the operator list reverses them … | §8.7".
- Source: §8.7 of the frozen plan (lines 1262–1266 and 1250) has neither the lifted-position memory figures nor the dependence on operator order; a search of the whole file for "5.7×" and for "operator order" finds neither. The figures themselves are right (`verify-memory.md` Table 2; `verify-proto-labels.md` §2).
- Either add the two results to §8.7 (finding 12 above gives a sentence for the second) or change both "Where" cells to "`reports/verify-memory.md`" and "`reports/verify-proto-labels.md`".

### B7. FACTUAL ERROR. Row 4 repeats "7 of 9"

- Line 57: "a strict label filter lost the guard split in 7 of 9 guarded runs in the store prototype".
- Source and replacement as in finding 4: "a strict label filter, given the final size, lost the guard split in all 9 guarded runs in the store prototype, and in 7 of 9 with Boolean-valued candidates exempted". Finding 3 also applies to the sentence before it: on the Python library the label-filtered passes kept both branches of a planted conditional in 120 of 120 tasks, so "must see every candidate" rests on the prototype's strict filter and on the halved cost, not on a loss measured in Python.

### B8. INCONSISTENCY. "Two fifths … tested and nothing more"

- Line 78: "**About two fifths of the tables' gain rests on entries that are tested and nothing more** (§6.5)."
- Source: as in finding 6; §6.5 itself (plan line 771) says the tables are "tested knowledge throughout".
- Replacement: "**Only the length tables, worth 3.6× of the 17×, follow from anything provable. About two fifths of the factor rests on entries that allow more than one output label, where a missed label cannot be told from an impossible one** (§6.5)."

### B9. INCONSISTENCY. Old Appendix B did not come to this file

- Line 27: "**Three appendices left the plan** for this file: … and the old Appendix B (locations of ideas in the trail, which §2.8 now carries in line)." Line 46: "| Appendix B, C, G | this file |".
- Source: this file holds old Appendix G (Part 2) and old Appendix C (Part 3) and no table of locations; its line 3 says "It was Appendices C and G of the plan". The 24 rows of old Appendix B went into §2.8, and at least four of them are no longer anywhere in the plan (the `plan7-m9-policy.md` and `plan9-audit.md` rows, the intervention-style generator, and "59 pairs became 106").
- Replacement for line 27: "**Three appendices left the plan.** Two came to this file: the old Appendix C (your notes on `plan_v2b.md`) and the old Appendix G (your notes on the plan and on the review, and the ledger of the review's first two sections). The third, the old Appendix B (locations of ideas in the trail), was folded into §2.8, and four of its 24 rows were dropped." Replacement for line 46: "| Appendix C, G | this file |" and a new row "| Appendix B | §2.8 |".

### B10. INCONSISTENCY. §1.6 counts three built-in results; the table above it names more

- Line 94: "They are honest about what they print. In three places a result is built into the script instead of computed".
- Source: the three statements are each right. `verify_ram_and_nmi.py` line 237 passes the typed list `['len_cap6','all_even','all_nonneg','is_sorted','max_le_2','has_zero']` under the printed label "[3] 5-line pairwise NMI < 0.65 (diverse!)". `exp_devils_advocate.py` lines 611–623 builds the "stratified" probes from random lists and seven hand transforms (529 of the 1,000 probes, `revD_vary.log`). The answer size is the third element of every target tuple (`verify_ram_and_nmi.py` 116–123; `exp_devils_advocate.py` 185–188, 347–350). But rows 9 and 10 of the notes' own table add two more ("true only by construction of its test": no table for `at` and a filter on a size that is never stored; and an outcome set by the place of `at` in the operator list), and `verify-words.md` adds the 24-candidate pool that already contains the answers. And a script that prints a typed-in list under the label of a selection rule is not "honest about what it prints".
- Replacement: "They print what the review quotes. In at least five places a result is built into a script instead of computed: the six-word list, typed in and printed under the label of the selection rule; the pool of 24 hand-written candidates it is said to be chosen from; the "stratified" probes, of which about half are hand-chosen transforms; the answer's size, which is handed to the search in every memory experiment; and the lifted-task experiment, which gives `at` no table, filters only a size that is never stored, and enumerates `at` first."

### B11. MISSING CAVEAT. Smaller points in Part 1

- Line 64: "lost none in 1,700 runs". At 300 probes per operator the same rule lost 6. Add "at 1,000 probes per operator or more".
- Line 62: the quotation "whenever `at` sits at or inside the term" is not the review's text, which reads "whenever `at(xs, idx)` sits at or inside the term" (review, line 290). Line 64: the review's phrase is "*Stratify by current words*".
- Line 29: "eight words that had two meanings given one each". At least three still carry two: "Stage A" (plan line 1133, finding 17), "word" (finding 10), and "signature" (a task's set of properties at lines 1141 and 1281; an operator's type signature at lines 79 and 714).
- Line 90: "Gaps the clarity pass could not fill from any source, and left as they were:" lists three. The gap logs list about ten (`clarity-gaps-sec4-9.md`, "UNFILLED": A34 twice, A37, A38, A45, A49 twice, A50, A54; `clarity-gaps-sec2.md`: A14, A51). One of the unlisted ones concerns your own words: what "depth two" means, where "the owner's own use … does not confirm the review's reading" (A38). Say "the three largest are", and point to the two gap logs.
- Line 74: "This one change accounts for most of the difference". True at 1,000 and 3,000 probes (12 lost at random, 2 with program-shaped probes alone, 6 with spreading alone). At 300 probes spreading alone did better (17 against 22). Add "at 1,000 probes per operator or more".
- Line 58: "Measured over 234 tasks": the on-path figures use 179 of them (finding 22).

---

## C. Claims checked and found correct

- §8.7 "What the tables buy": all six rows, the listing-order figures 13.9× and 16.7×, seven look-ups, 1.3× / 2.0× / 4.2×, 14.4× / 11.1× / 11.6× / 15.6×, 2.8–6.4×, 6.1–12.6×, 15.7×, 5.9×, and 5 of 8 past the cap: all match `verify-quotients.md` §2.2–§2.5. "51st to 58th of 61" matches `q2_main.log` and `q2_main_seed2.log` (the report's "52–58" is the looser figure; one rank of 51 is in the second log).
- 34 / 4 / 1 / 1 / 0 lost of 300, and the `take3` example: `verify-quotients.md` §2.6.
- The probe table, every cell: S300 from `exp_main_S300.log` (random, hand) and `exp_main_S300_v2.log` (the other three); the 800-run column is the sum of `exp_main_EDGE-R.log` and `exp_main_EDGE-W.log` (200 tasks × 2 seeds each, one structured row per task, `tasksets.py`); the last column from `exp_audit.log`. 900 = 300 × 3 and 800 = 2 × 200 × 2 are right.
- "7 of 20 seeds" (`revD_vary.log`, part 2, `hand n=1000 … zero in 7/20`); gain 16.9–17.1× on S300 and 17.6–18.0× on EDGE-R under every rule; 17.57 s and 1.11 s (`time_tables.log`); "4 of 10 seeds" (`exp_audit.log`).
- Feedback removes nothing at 1,000 and 3,000 probes; merged quotient 21.4–22.2× and 10 of 600; slices 287 and 422 as raw counts, and "most random slices reject nothing" (zero in 114 and 125 of 200 sets).
- 71.5%, 10.16× of 16.96×, 3.60× (`exp_cert.log`).
- 43.3% and 47.4%; 0 of 410 (212 + 198); 15.64× and 16.89× against 7.79× and 8.01×; 31 of 119; 41% and 43%; ties 26 of 102 and 26 of 99; 46% and 54% against 39% and 33% (`b12_report.log`).
- 192 tasks; 2.38× and 2.98×; 29.8× and 35.4×; none lost; 70 of 234 and 64 right; ceiling 1.12× and 1.11×; 82 of 120; 64 fitting splits and 2 right; 56 of 64 against 29 and 22; 4 and 3 of 32; up 47 and down 62; D / D2 = 2.07× and 1.97× (`b3_report.log`, `b12_report.log`).
- Store prototype: 17.30×, 22.29×, 2.52×, 6.09× and the plain comparison giving the same cut in less time (`e1-table.txt`); 36.06× candidates, 17.08× time, 14.36 million to 0.42 million classes = 34×, no answer changed, types alone equal on five of seven (`e5.log`); parity alone 3.396 million against 3.379 million (`verify-proto-labels.md`).
- Vocabulary: 1,109 and 702nd; 95,732 (`pool_main.log`); 13.00×, 15.30×, 15.78×, 13.85× with none lost, one of 60 lost (`summary.log`); nine of ten words contain the length (`sel_main.log`); ranks 4,401 and 3,866 and "sorted" not expressible (`sel_extra.log`); 4.75× / 8.38× / 12.17× / 13.00×; 12.78× without the library; 26 / 45 / 61 operators with two of six words carried over at each step (I compared the three lists in `sel_more.log` and `sel_main.log`) and 12.02×; 20 min 52 s of CPU (`run_pool_main.out`); 180 ms.
- Memory: 8.5× to 26.4× on six targets; 9.7× over 111 random targets of size 7 or more (`m1_poly.log` line 59); 200 of 200 found; 117 of 120 lost; 1.2× to 2.6×; restarts 1.0 to 2.1; 2.39× / 7.10× entries and 1.54× / 4.34× bytes (`m3_extra.log`).
- "Two smaller results": 47 to 151 valid guards on four laws, seven maximal guards for the divisibility law (`verify-quotients.md` §4); 25 of 25 repeats, at most 57 candidates, an index finding 9, 14 or 19. The last three have a script and no log; I reran a copy (`fc-b/vq/fc_reuse_labels.py`) and got exactly 25/25, 57, and 19 / 9 / 14.
- §8.4, reworded sentence: 8.5 to 26, two variables, sizes 7 to 13, first grammar of the three, "each class that is kept still holds its whole column", and the arithmetic of two or three sizes.
- §8.5 against the previous §8.6 and `verify-review.md`: every figure in both tables is unchanged and right; "Thirteen of the sixteen" is supported by the table as now written (4 + 2 + 1 + 4 + 1 + 1); "625 and 824 times" matches `r1-occam` and `e5.log`. Changes of meaning are only those in findings 16, 17 and the dropped sentence in finding 25. The review's sentence "The prototype validates the *store*, not the *general synthesizer*" is quoted fairly (review, line 114).
- §8.6: unchanged from the previous §8.7 except two sentences, both right.
- §8.8: points 1, 2, 4, 5, 6, 7, 8 and 10 each agree with the section they cite; point 3's "most of its cost" follows from the 625× and 824×. Point 9 is finding 3.
- §10: risks 4, 7, 9, 12 and the first sentence of 13 agree with §8.7; the vocabulary bullet agrees with §8.7 and §6.7; the quotations "less gameable", "does not lead to many useful lemmas", "has a one-operator answer" and the DreamCoder sentence are in the reports as quoted.
- §11.1: the five new rows, except the two sentences in findings 4 and 5 and the one in finding 9. §11.3: the stage table agrees with §11.2 and §1.7.
- Front matter: the counts of auditors match Appendix D (5 + 6 + 3 + 1); the three commits exist; Appendix B names the two exceptions the front matter promises; every term in the table except "word" (finding 10), "Stages A to D" (finding 17) and "X1 to X9" (finding 18) is used in my sections as defined.
- Appendix D: `v1/frame.lisp:1581` returns 0 bits for an exact cell and `:1572` takes a minimum of two codes, as the last bullet says.
- `revision-notes.md` Part 1: the quotation of your instruction; the section mapping table; rows 3, 6, 7, 8, 12, 13, 14, 15, 16 and 17 of the claim table against their reports and against the review's wording; 56 rewritten passages (items A1 to A56 of `clarity-review.md`); the three statements of §1.6 taken singly; the before and after totals and the figure for the appendices in §1.5.

## D. What I could not check, and why

- `factcheck3-*.md` and `plan_v2c_audit/revision-notes.md` do not exist at the paths Appendix D gives; the first are being written and the second is still in the scratch folder.
- I reran nothing but the two small scripts named above. Every other number was compared with a log, not regenerated.
- Carried-over figures of §8.7 were checked against `verify-quotients.md` and, for the Naive Bayes ranks and the reuse streams, against its logs; I did not reopen `q2_sweep.log`, `q2_length.log`, `q2_sound.log` or `q4_guards.log`.
- The pool files (`pool_*.pkl`) were not copied, so 95,732 rests on the log line and the ranks on `sel_extra.log`.
- Your latest request is not in a file; I compared the quotation in the notes with the wording given in the brief.
- "Three of the code auditors … were told not to read the earlier v2 plans" (line 5) has no source I could find.
- The housekeeping bullets of Appendix D that were carried over from the previous version (lines 1548–1555) were not rechecked, apart from the two `frame.lisp` lines.
- Whether review Appendix B.1's corrected figures (51 / 51 / 2,269) are right: no report recomputed them and the plan does not use them.
- Sections 6 and 7 are outside my scope. I read them to follow pointers, and where a sentence there repeats a finding above I have given its line number (lines 94, 668, 706, 765, 810, 875) and nothing more.
