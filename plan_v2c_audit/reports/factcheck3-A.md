# Fact-check 3-A: §1.3, §1.4, §1.6, §1.7, §5.9 (one paragraph), §6, §7.2, §7.4–§7.6

Checked document: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md`. Line numbers are lines of that file.

Sources are named relative to `/home/tlh24/lisploop/plan_v2c_audit/`: reports are in `reports/`, this round's scripts and logs in `round3/`. Two small scripts of mine are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-a/` (`b3_checks.py`, and `vq/run_fc.sh`, which re-runs three helper scripts of the earlier fact-check on copies). I wrote nothing under `/home/tlh24/lisploop`. Someone else moved files there while I worked; see the note before the list of correct claims.

Most of the numbers are copied correctly. The serious findings are of another kind: a figure is attached to an arrangement or a condition other than the one that was measured, or a limit found in one instrument is stated as general when the other instrument shows the opposite.

## Findings, most serious first

### 1. FACTUAL ERROR. §7.2 step 3: both gains quoted for the near-miss check were measured in arrangements that step 3 does not describe, and the arrangement it does describe measured worse.

- Line 878: "On tasks built to contain such a step this was worth 2.4× to 3.0× beyond what labels gave **[M]**."
- Line 881: "The review placed this check after the label filter, on the candidates the filter lets through. It has to see every candidate, for the reason given in step 2, and run that way it also cost half as much **[M]**."

Step 3 puts the check in the plain pass, which runs only after the tentative label pass has found nothing (line 877; risk 14 at line 1356 and X4 at line 1404 say the same). The experiment had six arms (`round3/q4-handoff/b3.py` lines 11–18; results in `b3_report.log`, two task sets of 96):

| Arm | What it is | Candidates, geometric mean |
|:--|:--|--:|
| B | label-filtered search, the constant available as an operator | 2,870 / 2,228 |
| C | plain search with the check on every stored class | 1,853 / 1,117 |
| D | label-filtered search, check on the classes the filter keeps (the review's order) | 1,155 / 720 |
| D2 | label-filtered search, check on every candidate that pass evaluates, before the label test | 559 / 366 |
| E | as B, with the check on the classes the filter keeps | 1,207 / 749 |

"2.4× to 3.0×" is B / E (2.38×, 2.98×): the check added inside a label-filtered search, on the classes the filter keeps, which is the review's placement. "Half as much" is D / D2 (2.07×, 1.97×): both arms are label-filtered passes. Step 3's own arrangement is arm C. The log gives C / D = 1.60× and 1.55× ("gain review order vs residual only"), so the plain pass with the check took 1.6 times more candidates than the review's arrangement, and by my recomputation from the JSON files 3.3 and 3.1 times more than D2 (`fc-a/b3_checks.py`). That is before counting the tentative pass, which in step 3 has to run and fail first.

Two further caveats apply to the same sentences. The gains count candidates only. The log counts each check separately and says a check costs about one evaluation; with each check counted as one candidate, B / E is 1.57× and 2.00× (my recomputation; the same method reproduces the log's own 19.15× and 23.25× for A / C). And the proposal was tried only for a constant offset and a constant scale (`verify-handoff.md` §6), not for a residual that "falls in some other class with a small term".

Replacement for line 878: "On tasks built to contain such a step, the check was worth 2.4× to 3.0× in candidates beyond what labels gave, and 1.6× to 2.0× when each check is counted as one candidate **[M]**. That was measured with the check running inside the label-filtered search, and only for a constant offset and a constant scale."

Replacement for line 881: "The review placed this check after the label filter, on the classes the filter keeps. Inside the label-filtered pass, checking every candidate that pass evaluates, before the label test, cost half as much as checking only the classes it keeps **[M]**. The arrangement of this step, a plain pass with the check and no labels, was also measured on those tasks. It took 1.6 times more candidates than the review's arrangement and about 3 times more than the best one, before counting the tentative pass that has to fail first."

Where the check should then run is the author's decision. As written, step 3 claims for one arrangement the figures of two others.

### 2. FACTUAL ERROR. §6.2 and §6.8: the correction code is not undefined between values of different shape. What was undefined is the element-wise difference.

- Line 668: "What measures a near miss is the correction code of §6.1, applied row by row, and it needs the two values to have the same shape: it was undefined for 41–43% of the classes one step from an answer, because the types or the lengths differed."
- Line 810: "…and a correction is undefined between values of different shape (§6.2)."
- (Line 1236 in §8.7, outside my scope, says the same.)

The 41% and 43% are the column "L1 undefined for the on-path class" in `b12_report.log` (42 of 102; 43 of 99). In the experiment's code the correction code is `corr_bits` (`hlib.py` lines 83–104). It is defined for every pair: lists of different length pay a code for the change of length, and values of different type pay the plain code of the target. The functions that return "undefined" are `col_l1` and `col_residual` (lines 112–141), the element-by-element difference from which an offset or a scale is read. The kernel agrees: `frame.lisp:1563-1578` prices a sequence against a prediction of another length, and §6.1 itself says the sequence code includes "a change of length". The report words it correctly: "That difference is undefined for 41–43% of true parents one step out" (`verify-handoff.md` lines 82–84).

Replacement for line 668, second half: "What measures a near miss is the correction code of §6.1, applied row by row. That code is defined for any two values, because it can pay for a change of length or fall back to the plain code of the target. What is often not defined is the element-by-element difference from which an offset or a scale is read. It needs two values of the same type and the same length, and it was undefined for 41–43% of the classes on the path one step from an answer."

Replacement for line 810: "On sequences and code the present prices break the triangle inequality for large values (§6.1), and the element-wise residual from which proposals are read is undefined between values of different type or length (§6.2)."

### 3. OVER-STATEMENT, with a mis-attached number. "It cannot find an answer that needs a guard" rests on the prototype's strict filter, and the Python experiment of the same round shows the opposite.

- Line 94: "…they cannot find an answer that needs a guard…"
- Line 726: "A strict filter therefore discards the candidates from which a conditional would have been built: in the store prototype it lost the guard split in 7 of 9 guarded runs."
- Line 875: "And it cannot find an answer that needs a guard, because the near miss a guard is built on fails the labels on the very rows it gets wrong."

Three things are wrong.

First, the number. In `round3/l1-proto/logs/e3.log` the strict filter ("strict@L q3") lost the split in 9 of 9 runs. Seven of nine is the result when candidates with a Boolean result are exempted from the filter ("guards exempt"). `verify-proto-labels.md` item 6 says so in two separate bullets.

Second, the condition. The strict filter was applied at a level handed over by an oracle, "the level after which plain finds its split", and the search stopped there (log lines 25–28). That is not the tentative pass of step 2, whose bound is deepened step by step.

Third, the Python measurement. `b3_report.log`, on 120 tasks built as conditionals, has the line "review order (label-filtered passes until both branches are stored …): 60 of 60 tasks reach it within pass 6, both branches stored in 60; candidates geo-mean 1345, against 1333 for the plain bank to size 3 (1.0x more)", and the same for the second set (1321 against 1329). With a deepening bound the label filter kept both branches of every planted conditional, one or two passes later, at no extra cost. (The test asked whether the two branches were stored. It did not ask whether the guard was.) The plan does not report this. One of the nine prototype runs, also, lost a split that was itself an impostor (`map-adjacent` on the spec rows, 29/200), so its loss was no harm.

Replacement for line 726: "*A strict filter loses near misses.* A candidate that is right on most rows and wrong on a few fails the labels on the rows it gets wrong. In the store prototype, a filter applied strictly at the level where the split would have been found lost the guard split in all 9 guarded runs, and in 7 of 9 when Boolean guards were exempted from it. With a bound that is deepened step by step the loss did not occur: in Python, both branches of all 120 planted conditionals were stored within one or two further passes, at no extra cost."

Replacement for the last sentence of line 875: "The second limit concerns answers that need a guard. A filter applied strictly at one level lost them in the prototype. A filter with a deepening bound kept the branches they are built from in Python. Which of the two the kernel's tentative pass resembles is not yet measured, so the plain pass stays behind it."

Replacement in line 94: "…a strict label filter loses answers that need a guard…"

### 4. FACTUAL ERROR and INCONSISTENCY. The "one routine" claim is overstated for inverses in §6.2, and §7.5 contradicts §6.2.

- Line 666: "For inverses, for exact facts about labels, and for verb tables the claim holds exactly. … Given an operator's table it reproduces the inverse of `*` with its guard `b ≠ 0` as §8.2 found it. Given labels it returns the verb table. Nothing else is needed."
- Line 943: "The first three and the verb tables are literally one routine with different columns passed in (§6.2)."
- Line 664: "That was tested by writing the one routine and running it on each case (§8.7) **[M]**."

`round3/q4-handoff/u1_residual.log` ends with a table of what each case needed beyond the 30-line routine: congruence 0 lines; verb table 0 lines; inverse 9 lines for "guard from a pool" plus 18 for "witness search", with the note "the routine returns the table (b,c)->a, i.e. the specification; the term is a search"; law 2 lines plus 15 for an enumerator. For `*` the routine itself returns "determined on 92.3%". The guard `(not (= b 0))` was chosen from a pool of 13 guards supplied by hand, and `(div c b)` was found "after 17 candidates" by a separate search (`verify-handoff.md` §4 lists the pool and the grammar as supplied by hand). So "nothing else is needed" is true for labels and false for inverses.

Line 943's "first three" are Laws, Inverses and Definedness (lines 934–936). Line 667 of the same document says a law "is a different test". Definedness was not part of the experiment at all.

The pointer at line 664 does not land. §8.7 (lines 1188–1270) contains no account of this test; the only other mention is the file list in Appendix D (line 1539).

Replacement for line 666: "For exact facts about labels and for verb tables the claim holds exactly. One routine of 30 lines groups rows by some columns, looks at another column within each group, and returns the table. Given labels it returns the verb table, and nothing else is needed. For inverses it supplies the first step only. Given the table of `*` it reports that an argument is determined on 92.3% of the rows, as §8.2 found. The guard `b ≠ 0` was then picked from a pool of thirteen candidate guards, and the term `(div c b)` was found by a small search. Those two steps took 9 and 18 further lines."

Replacement for line 943: "The dependency test behind an inverse and the verb tables are one routine with different columns passed in (§6.2). Laws come from a different test, the hashing of columns into classes. A guard for definedness, like the guard and the term of an inverse, is a small search on top."

For line 664, either add the test to §8.7 or point to `verify-handoff.md` part A.

### 5. FACTUAL ERROR. §6.4: the "12×" and the "6.6×" are mislabelled, and "among the dearest" rests on three tasks.

Line 728: "*Averages flatter it.* The tasks a filter loses are among the dearest to solve again. In one run the per-task average gain was 16×. The saving summed over all tasks was 12×, and with the fallback for the lost tasks counted it was 6.6×."

`round3/q4-handoff/c_unpredicted.log`, row "2000/iid/0", has four figures and defines them: "gain if found" 16.3×; "sum-cost gain" 12.7×, where "a lost task is retried plain after the filtered passes"; "with 3:1 reserve" 6.6×, where a found task costs 4/3 of its filtered cost and a lost one four times its plain cost; and "reserve, no loss" 12.1×, "what the reserve would cost if no task were lost". The plan's "12×" is the last of these, which the report gives as 12.1×. It is a counterfactual, not the saving summed over the tasks. The saving summed over the tasks with the fallback counted as a plain retry is 12.7×. The 6.6× holds only under the three-to-one reserve.

The first sentence generalizes from the three tasks lost in that run. Their plain costs were 16,015, 311,507 and 318,721 candidates (same log); the geometric mean over all tasks was about 44,000 and 41,000 (`b12_report.log`, B4(b)). Two are tasks of size 5, as about half of all the tasks are, and one is cheaper than the typical task. The run used 2,000 random probes, not the probe rule of §6.5.

Replacement: "*Averages flatter it.* In one run with random probes the per-task average gain was 16×, and three of 234 answers were lost. Two of the three were among the larger tasks. With those three retried by plain search, the saving summed over all tasks was 12.7×. Under the kernel's three-to-one reserve, where a lost task costs four times its plain search, it was 6.6×, against 12.1× under the same reserve had nothing been lost."

The same phrase recurs at line 894 ("because the tasks a tentative pass loses are among the dearest") and should read "because a lost task costs a whole plain search, and in the one run that measured it the summed saving fell by half".

### 6. MISSING CAVEAT. The Python gains have no plain control, and in the prototype the plain control matched the labels.

- Lines 716–720 (§6.4, "What it buys in search"), line 873 ("Ordering alone gave 6× **[M]**") and line 875 ("This pass gave about 16× **[M]**").
- Line 806: "Every search measurement so far is on a library of whole-sequence operators written for the experiment (§8.7)."

In the store prototype a control with no labels, comparing each candidate with the target row by row and stopping at the first mismatch, cut candidates exactly as much as ordering by labels did and was faster: 2.73× in both, 2.01× against 1.68× in time (`round3/l1-proto/logs/e1.log` lines 112–114; `verify-proto-labels.md` §1 and item 2). No such arm exists in the Python search, where a candidate is always a full evaluation over all eight rows (`verify-quotients.md` §2.1), and where applying labels only at the last size gave 7.8× and 8.0× (`b12_report.log`). So whether the 14 to 18 times would survive that control is not measured. §8.7 and risk 9 mention the prototype finding. The sections in my scope that state the gains do not.

Line 806 is also wrong as written, because the prototype run is a search measurement on element-level arithmetic.

Sentence to add after line 720: "None of these runs has the plainest control, which is to compare each candidate of the last size with the target one row at a time and stop at the first mismatch, with no tables. In the store prototype that control cut candidates exactly as much as ordering by labels did, and took less time (§8.7). Whether it would match the gains above is not measured."

Replacement for line 806: "Whether verb tables pay on the kernel's own library. The search measurements so far are on a library of whole-sequence operators written for the experiment, and on the prototype's twelve element-level operators, where labels gained nothing over a plain comparison with the target except as a look-ahead (§8.7). Experiment X4 (§11.2) is the test."

### 7. INCONSISTENCY. "Labels save memory only on ring arithmetic" contradicts the prototype result that step 4 of §7.2 quotes.

- Line 94: "…and they save memory only on ring arithmetic."
- Line 734: "…it is the one case where labels cut memory by an order of magnitude **[M]**."
- Line 994: "*Expect a large saving only where the labels are exact.*"
- Line 992: "Whenever a search has a target and a size bound, a class that cannot reach the target within the bound is not stored…"

`round3/l1-proto/logs/e5.log`, part (b): on the two runs whose answer has a function call at its root, the classes held were 5,235,775 with types alone and 106,389 with labels (49 times fewer), and 468,420 against 27,983 (17 times fewer). Part (a), with no oracle and a restart at each bound ("la-deepen q3"), holds 270 classes against 25,639 for `reverse` and 34,919 against 2,306,369 for `map-adjacent` with a function argument. `verify-proto-labels.md` item 4 summarizes "36× to 95× fewer". None of this is ring arithmetic. The two instruments count the plain search differently: the Python figures count plain's classes below the answer's size (`verify-memory.md` line 36), and the prototype counts what plain holds at the hit. That explains most of the gap, and the text should say so.

Line 992 also needs a limit. The same look-ahead, run with the level of the branches as its bound, lost the guard split in all nine guarded runs, and in seven of nine with guards exempted (`e3.log`, "look-ahead@L q3 + split"). The rule is safe only when the bound is the size of the whole answer, as in step 4.

Replacement for line 734: "On `+ − * neg`, reduction modulo a small prime is exact. In the Python experiments it is the one case where labels cut stored classes by an order of magnitude **[M]**. In the store prototype, once a size bound existed, a look-ahead on labels also cut the classes held by ten times or more on some lifted tasks (§8.7). The two instruments count the plain search's classes differently, so the figures are not comparable."

Replacement in line 94: "…and in the Python experiments they saved much memory only on ring arithmetic."

Sentence to add to line 992: "The bound must be the size of the whole answer sought. With the level of a conditional's branches as the bound, the test discarded the branches and the split was lost."

### 8. OVER-STATEMENT. "The kernel can choose its vocabulary" is a Python procedure on one library, its two halves were never run together, and three qualifications from the report are missing.

- Line 94: "The kernel can choose the vocabulary itself, to within a fifth of the gain of one listed by hand, and can choose the rows the tables are built from better than hand-picked ones."
- Line 750: "**the kernel can choose a vocabulary nearly as good as a hand-made one.**"
- Line 748 (step 4), line 754, line 755.

The numbers are right (13.0× against 15.78× is 82%). What is missing:

a. Nothing ran in the kernel. This is a Python procedure on the 61-operator library, 60 tasks, with the grammar's extra primitives, the size bounds, the cap of eight labels, the repetition threshold and the number of words all set by hand (`verify-words.md` §4). A second probe seed gave 14.3×.

b. The word rule and the probe rule were never combined. The vocabulary was chosen and tested with tables from 2,000 random probes (`verify-words.md` lines 4–5). The probe rule was tested only with the six hand-listed quotients, and is spread over their labels (`verify-probes.md` §6: "Quotients chosen automatically … were not combined with the new probe rules").

c. "Within a fifth" fails for two of the variants run. With the threshold at 0.8 the gain was 11.5× (27% short). With the library's operators and the fold forms that the review's prescription 2 names (`all`, `fold`) both in the grammar, it was 10.3× (35% short; `summary.log`, "lib_fold|pairs|K=6"). Line 754 reports 13.0× and 12.8× and omits the 10.3×.

d. Line 755's "the version to build" lost no answer at one threshold only. At thresholds 0.5 and 0.8 the same version gave 12.3× with one answer lost and 10.6× with three lost (`summary.log`, "compcap" rows).

e. Step 4 says the pairing is done "so that the labels of `sum`, `head`, and `len` mean something". The integer word it chose was `(sgn (abs v))`, "is the value zero", for five of the six words (`sel_main.log` lines 9–14; `verify-words.md` item 4). The other pairing objective gave 15.4× and lost a second answer.

Replacement for line 94: "A procedure that the kernel could run chose a vocabulary to within a fifth of the gain of one listed by hand, and another chose the rows the tables are built from better than the review's hand-picked ones. Both were run in Python, on one library, and not yet together."

Replacement for line 750, bold sentence: "**a procedure with no word listed by hand chose a vocabulary nearly as good as a hand-made one, on this library.**"

Sentence to add to line 754: "With the fold forms the review named also in the grammar, the gain fell to 10.3×, so a richer grammar of candidates can do worse."

Replacement for line 755, last sentence: "Applying the repetition test to the two halves of a pair as well gave 13.9× and lost no answer at the default threshold, and 12.3× and 10.6× with one and three answers lost at the other two. It is the version to build, with the threshold still to be settled."

Sentence to add to step 4 (line 748): "In the run measured, the integer word chosen was 'is the value zero' for five of the six words, so this step is the weakest of the four."

### 9. MISSING CAVEAT. §7.6 rule 3: "two or three sizes" is arithmetic on an extrapolation, under a heading tagged [M].

Line 994: "…these rules cut stored classes 8.5 to 26 times, which moves the memory wall of §8.4 out by two or three sizes for such searches."

`verify-memory.md` line 80: "Projection to the §8.4 wall (arithmetic, not measured). Classes grow ×3.0 per size on G1, so a 10–25× cut in stored classes moves the 24 GB wall by about 2–3 sizes." The cut was measured at sizes 7 to 13 with two variables and the leaves x, y, 0, 1. The wall of §8.4 is itself an extrapolation, at size 16, for a grammar with three variables and the leaves x, y, z, 0, 1, 2.

In the same paragraph, line 993's "between 1.0 and 2.1 times" is a range of per-size geometric means, not of single searches. The 2.08× is the mean over three targets of size 10, and the means rise with size: 1.00× up to size 4, 1.19× at 7, 1.49× at 9 (`m1_poly.log`, Table 3). The largest single figure is not in the log.

Replacement for line 994: "…these rules cut stored classes 8.5 to 26 times at sizes 7 to 13. If the cut holds at larger sizes and with a third variable, which was not measured, then with classes growing ×3.0 per unit of size it would move the extrapolated memory wall of §8.4 out by two or three sizes."

Replacement in line 993: "…and the restarts cost, on average at each size, between 1.0 and 2.1 times the evaluations of that pass, more at larger sizes."

### 10. OVER-STATEMENT. §5.9: "Two measurements say which signals work" covers one of the four signals, and the second measurement is not a signal for choosing pairs.

Line 619: "Two measurements say which signals work. … It is the amortization your outline describes, and §6.4 builds on it."

Line 617 lists four signals for choosing which pairs to try: agreement of labels, the cost of one column given another, colour histograms, and counts of pairings that paid before. §8.6 measured the first, in the form of shared Boolean properties, and found it works for form and not for operators. The other three were never measured as a way to propose pairs. The second measurement of the paragraph, the verb tables, is a different mechanism on a different instrument: Python and the 61-operator library, where the signature experiment was the Lisp prototype on thirty sequence tasks.

The last sentence claims more than was shown. In `prompt4.md` L170–175 the search to be amortized is the matching problem of "quotienting-AU". What was measured is a constant factor in the enumeration of terms for one problem. No matching or anti-unification search has been run with a vocabulary.

Replacement for the first sentence: "One of the four signals has been measured, and so has one alternative to choosing pairs at all."

Replacement for the last two sentences: "That table is found once per operator and read in every later search. It is amortization of the kind your outline describes, shown so far for the enumeration of terms and not yet for matching or anti-unification. The other three signals have not been measured as a way to propose pairs. §6.4 builds on the tables."

### 11. OVER-STATEMENT. §7.4: an identity stated as fact with nothing behind it.

Line 922: "The search for a separating column is the search for a word (§6.5) on a task's own rows."

The kernel's DIP step looks for a context expression "that takes different values on every conflicting row pair" among variables and one-step applications (`search-engine.md` §8, "DIP repair"). The word search of §6.5 scores small terms into at most eight labels by how well the labels of each operator's inputs predict the labels of its output on probe rows. The two have different candidates, different scores and different rows. No report tests one as the other. The sentence is new in this round.

Replacement: "The search for a separating column resembles the search for a word (§6.5): both look for a small term whose values tell rows apart. Whether the vocabulary could supply the separating columns is not tested **[P]**."

### 12. INCONSISTENCY. §7.2 step 4 says "seven guarded tasks"; they are seven runs of five functions.

Line 883: "In the store prototype, on the seven guarded tasks, this cut candidates 36× and stored classes 34× and changed no answer **[M]**. … Types alone did all of it on five of the seven tasks, and labels were needed on the other two."

`e5.log` part (b) lists the runs: `shift-seq`, `running-sum`, `scan` with an initial value, `scan` with step 2·acc − x, and `scan` with a function argument, all on the prototype's rows, then `scan` and `shift-seq` again on the kernel's spec rows. `verify-proto-labels.md` says "7 guarded runs", and so does §8.7 at line 1251. The two runs that needed labels are one function, `scan` with a function argument, on its two row sets. The figures are right: 63,756,814 to 1,768,247 candidates (36.06×), 14,360,391 to 423,797 classes (33.89×), programs changed 0. One plain run stopped at its cap of 15 million candidates, so its ratio is a lower bound. On the heading's generality: this is one prototype, three quotients and element-level arithmetic, and the report notes that the look-ahead was not run under first-fit acceptance (§7).

Replacement: "In the store prototype, on seven guarded runs (five functions, two of them run again on the kernel's spec rows), this cut candidates 36× and stored classes 34× and changed no answer **[M]**. It recovers part of what the size-order rule costs (§8.5). Types alone did all of it on five of the seven runs. Labels were needed on the other two, which are the same function, `scan` with a function argument, on two sets of rows."

### 13. MISSING CAVEAT. §7.5 rule 4 and §6.5: "lost no answer", and "nothing left to correct", leave out the long streams.

- Line 950: "At 1,000 such rows per operator the tables lost no answer in the measurements of §8.7."
- Line 768: "With good probes there was nothing left for it to correct."

The count is right: rule (iv), `bank2+strat2`, at 1,000 probes lost 0 of 900 + 400 + 400 searches (`exp_main_S300_v2.log`, `exp_main_EDGE-R.log`, `exp_main_EDGE-W.log`). But on streams of 4,000 tasks the same tables met a wrong entry on about 5 tasks per 1,000 at 1,000 probes and 0.55 at 3,000, and at 3,000 probes only 4 of 10 seeds were free of them (`exp_audit.log`; `verify-probes.md` line 48: "Zero losses on 700 tasks is not soundness"). On those streams feedback did have something to correct. After the first 1,000 tasks it cut the rate from about 5.0 to about 1.7 per 1,000 tasks at 1,000 probes, and from about 0.55 to about 0.13 at 3,000 (`exp_feedback_p1.log`, rows `bank2+strat2`). The report's verdict is "a cheap optional extra", not "nothing". "The measurements of §8.7" is also too wide, since other measurements in §8.7 lost answers with other probes.

Replacement for line 950: "At 1,000 such rows per operator the tables lost no answer in 1,700 searches over 700 tasks (§8.7). On longer streams of tasks they still met a wrong entry on about five tasks in a thousand, so the fallback stays."

Replacement for line 768, last sentence: "With good probes no answer was lost in the 700 tasks searched, so there was nothing for it to correct there. On streams of 4,000 tasks it cut the rate of wrong entries met three- to fourfold. It is left out of the first version and is a cheap thing to add later."

### 14. FACTUAL ERROR, small. §7.4: an index found 20 of the 25 repeats, not 19 at best.

Line 917: "…replay found all 25 at no more than 57 candidates per task, and an index of past problems found 19 at best (§8.7) **[M]**."

`verify-quotients/q5_reuse.log`, "over 5 random streams": method C, the index alone, found 3, 5, 4, 2 and 5 repeats, which is 19. Method D, the same index with one-operator synonym variants of what it retrieves, found 3, 5, 5, 2 and 5, which is 20, and six sibling tasks besides, for 26 hits against replay's 25. In candidates D saved 1.30× against replay's 1.31×, so the conclusion stands. The 25 and the 57 (three candidates for each of at most 19 stored solutions) are right.

Replacement: "…and an index of past problems found 19, or 20 when synonym variants of the retrieved solutions were tried as well (§8.7) **[M]**."

### 15. OVER-STATEMENT. §6.2: "nearly always all different" is 54–56% in the log.

Line 668: "On a task's few rows the values of a candidate are nearly always all different, so grouping by them "determines" any target whatever, and the count says nothing."

`b12_report.log`: "share of ALL bank classes for which 'Y is a function of U' holds on the 8 rows (zero residual): 53.8%" and 55.5%; `verify-handoff.md` gives 81% at four rows. The conclusion holds for a different reason, which `u1_residual.log` shows: the test passes equally for the near miss and for an unrelated column.

Replacement: "On a task's few rows, grouping by a candidate's values "determines" the target for more than half of all the classes in a bank (54–56% on eight rows, 81% on four), and it does so for an unrelated column as readily as for a near miss. So the count says nothing about nearness."

### 16. MISSING CAVEAT. §6.2: "never the right one" is true of the class test; the filter did lose answers in the same run.

Line 672: "The labels ruled out nearly half of the classes one step from the answer, never the right one, and none of the classes further away."

0 of 410 classes on the path were ruled out (`b12_report.log`, 212 + 198). In the same two runs the label-filtered search lost 1 of 119 and 2 of 115 answers, because the tables called the last step itself impossible ("the reference's own last step is rejected in 1 of 91 tasks", "2 of 88"). The 43–47% was also measured with the answer's size taken from plain search (`verify-handoff.md` §4).

Replacement: "The labels ruled out nearly half of the classes one step from the answer and none of the classes further away. They never ruled out a class on the path to the answer, though in 3 of the 234 tasks a wrong table entry ruled out the last step itself."

### 17. INCONSISTENCY in terms.

a. *word*. The table of terms (line 35) says "The labels are the words of the kernel's vocabulary (§6.2)", and line 706 agrees. §6.5 uses "word" for the quotient: "A word whose label is the same for every output" (line 746), "Limiting a word to 2, 4, 6, or 8 labels" (line 753), "a word with k labels" (line 732), "six words" for six quotients (line 750). §6.2, which the table points to, never uses the word "word". Replacement for the table entry: "A quotient of values is a small term that takes a value to one of a few labels, such as its sign. A quotient with its labels is one word of the kernel's vocabulary (§6.2, §6.4)." Line 706 would then read "the quotient is the word, and its labels are the word's values".

b. *tested*. Line 724: "That is knowledge carried across spaces without being re-checked there (§5.9), which is the definition of the tested grade (§5.5)." The table of terms and §5.5 define *tested* as true on this space and also on fresh spaces. Carrying knowledge across spaces without checking is not that definition. Replacement: "That is knowledge carried across spaces without being re-checked there (§5.9). It is of the tested grade (§5.5): it has held on the probe rows, it is not proved, and so it may be used only where a mistake costs time or a missed answer."

c. *the review*. In §6 and §7 "the review" means the outside review, except at line 779 ("the one principled, gradient-free criterion the review found") and line 954 ("the review found no system that learns termination guards"), where it is the literature review. Replace both with "the literature review".

### 18. Smaller over-statements and dropped caveats.

a. Line 725: "…and was the same for programs of 3 to 6 nodes." The log has 14.4×, 11.1×, 11.6× and 15.6× (`verify-quotients.md` §2.5), and the previous version said the data "cannot exclude a drift of 15% per node either way". Replacement: "…and was between 11× and 16× for programs of 3 to 6 nodes, with no trend."

b. Line 807: "A merged, finer quotient showed a gain that rose with program size, and lost answers." Re-running the earlier helper `sweep_by_size.py` on a copy gives 12.2×, 23.2× and 30.0× at sizes 3, 4 and 5 against plain search averaged over operator orders, and 22.4×, 23.9× and 23.7× with the operators in listing order, with five tasks at size 3 and the lost tasks left out. Replacement: "A merged, finer quotient showed a gain that rose with program size against one of the two baselines and was flat against the other, and it lost answers."

c. Line 696: "…and misleads about as often as it helps elsewhere (§8.7)." On the ordinary tasks it moved the true parent up in 47 cases and down in 62. On the tasks built as conditionals it moved the right branch down in 79 of 240 cases and up in none (`b3_report.log`). Replacement: "…that helps for exactly one case, a constant offset. On ordinary tasks it misled a little more often than it helped, and on conditionals it only misled (§8.7)."

d. Line 719: "Counts of past use do not: used as prices they sent 5 of 8 such tasks past the search's cap." Used only as an order, counts still gave 1.7× and 3.1× on those tasks (`verify-quotients.md` §2.2, "NB-U1, order-averaged plain", cold column). The previous version said so. Add: "Used only to order, counts still gave 1.7× and 3.1× on those tasks."

e. Line 754: "So re-choosing the vocabulary as the library grows is cheap insurance, not a source of compounding." True at six words (12.0×, 11.5×, 13.0×). At ten words the gain rose from 13.5× to 15.3× between the first and second stage (`summary.log`). Add: "At ten words the gain did rise, from 13.5× to 15.3×, between the first two stages."

f. Line 710: "(§8.6 tested 350 candidate maps between operator tables in 1.3 ms, and 29 held)". Of the 29, 17 carry an operator to itself, and the 12 between two different operators are all between `max` and `min` (line 1172; the previous version said "12 of them between two different operators"). Restore that clause.

### 19. INCONSISTENCY, small. §6.8's last bullet against §11.

Line 811: "§11 puts that ablation ahead of building anything in this section beyond the per-column codes."

Stage C (line 1417) contains the vocabulary, the verb tables and the tentative pass, and ends when X4 passes. X4's gate reads "or §6.4 and §6.5 are not built further" (line 1404). The ablation needs a first build. Replacement: "§11 makes that ablation, X4, the gate for building any of this beyond a first version."

### 20. COSMETIC.

a. Line 871 says the order "changes two things that the measurements of §8.7 forced", and line 741 says "Two of the review's reasons for them do not" hold. Neither place says which two. I count at least three changes in §7.2: where the near-miss check runs, a split being held and not accepted, and step 4. Name them where they are announced.

b. Line 745: "…or a pair of two such terms." Pair components were limited to four nodes, a pair to nine (`pool_main.log`: "818 components (<= 4 nodes)"). Replacement: "…or a pair of two such terms of up to four nodes each."

c. Line 746: "For each operator…". Words on lists were scored on the 37 operators that take lists to a list (`wordlib.py` docstring; `sel_main.log` line 250). Replacement: "For each operator that takes lists to a list…".

d. Line 763 quotes the review as "stratify by current words". The review has "*Stratify by current words*", capitalized (`plan_v2c_audit.md` §2.5.4 item 1), and its rule adds "plus boundary/constant/equal-prefix edge cases", which the plan's rule deliberately leaves out. Either match the capital or drop the quotation marks.

e. Line 90: "On the 4 to 13 rows of the kernel's own specs". The thirteen that are solved have 4 to 13 rows. The sixteen have 3 to 13: `argmax-corr` has three (`v2/library/sequence-shift.sexp` lines 221–228; `verify-review.md` §1 table). Line 1103 has the same slip.

f. Line 996: "…so they can be held as hashes and their columns dropped." This works only if each one-argument operator is applied to the class when it is made, before the column is dropped (`verify-memory.md` line 76). Add that clause.

## A change in the repository during this check, not made by me

Between about 19:03 and 19:08 local time on 26 November, while I was reading logs, the working tree of `/home/tlh24/lisploop` changed. The root kernel (every root `.lisp` file, `tests/`, `milestones/`, `bootstrap/`, `plan7/`, `figures/`, `experiments/`, `deprecated/`, `library/`, and the plan 8 and plan 9 documents) now sits in a new untracked directory `v1/`, the root `Makefile` is modified, and `git status` shows 96 tracked files as deleted. `HEAD` is still `31d5ae7`. I ran only read-only commands there and moved nothing. `plan_v2c_audit/`, `v2/`, `prompt4.md` and `plan_v2_prompt.md` are where they were.

Two consequences. The kernel paths I cite were read at the root before the move and are now under `v1/` with the same line numbers (I confirmed `v1/frame.lisp` line 1563); the plan 7 quotation is now at `v1/plan7/plan7-recursion.md`. And if the move is kept, every root-level path in the plan needs the prefix, for example `bootstrap/recursion-schemas.lisp` (line 899) and `plan7/plan7-library.md` (line 615), with many more in §2, §9 and the appendices, and the phrase "root kernel" in the front matter (line 3) needs rewording. The sections in my scope cite no moved path directly.

## Checked and found correct

- §6.1: the worked example (a difference of one costs 4 bits; 16 bits; 29 bits against a prediction of zero, from 9 + 8 + 8 + 4), against `verify-review.md` §5 and the code in `hlib.py`; integer costs 0, 4, 5, 5, 8 and 17; the asymmetry and triangle statements; the description of the correction rules against `frame.lisp:1533-1581`; the plan 7 quotation.
- §6.2: 43% and 47% ruled out one step away; 0 of 410; 0.0% further out; ties in 25% and 26% of tasks; 46% and 54% against 39% and 33% by chance; the 30-line routine; `x + 1` given `x`; 18 of 18 verb tables identical.
- §6.3: rules 1 to 5 are word for word those of the previous version, apart from the renumbered pointer in rule 5; "66th of 2,661"; 56 of 64, 4 and 3 of 32, 47 up and 62 down.
- §6.4: 1.7× against 15.7× on the same 60 tasks; 14 to 18 times; 1.3 to 4 times in wall time; 5 of 8; 6× against 2.6×; "1,700 runs over 700 tasks" (900 + 400 + 400 searches on 300 + 200 + 200 tasks) with 0 lost, and 12 lost with random probes (5 + 1 + 6); the 16× and the 6.6× as numbers; 22 of 32 against 9.4 by chance (re-run); 350, 1.3 ms and 29; every quotation from `prompt4.md` L174–203 and from `plan7/plan7-recursion.md` L67; the three word types from `plan_v2_prompt.md`.
- §6.5: the four steps against `wordpool.py`, `wordlib.py` and `wordsel.py`; 13.00×, 15.30×, 15.78× and 13.85×; ranks 4,401 and 3,866 of 95,732; 4.75×, 8.38×, 12.17× and 13.00×; 12.78× without the library; 26, 45 and 61 operators, 12.02×, and two of six words carried over at each step (read off the word lists in the logs); 11.51× and 14.83×; 21 CPU-minutes (`run_pool_main.out`: user 20m52s); nine of ten words containing the length; the probe rule against rule (iv) in `probegen.py`; 0, 12 and 5 lost; the review's Appendix B.2 item 5 ("earlier Gap 5 … dropped"); 17× to 22× and 10 of 600 lost at 10,000 probes; 71.5%, 10.2× of 17.0×, and 3.6×.
- §6.6: both margin notes are quoted exactly.
- §6.7: every figure against `lit-abstraction.md` and `lit-geometry.md`; the text is that of the previous version apart from one dropped clause.
- §7.2: the running example; 6.06× and 5.74×; 15.64× and 16.89×; 2 of 64 (0 + 1 + 0 + 1 of 18 + 22 + 10 + 14); 36.06× and 33.89×; five of seven runs; 0 of 234.
- §7.4: 25 of 25; 57 as three candidates for each of 19 stored solutions; the description of UIP and DIP and "only two narrow forms are kept between jobs" against `search-engine.md` §8; the inventory of 158 (the four classes sum to 163 because a row with two classes is counted twice).
- §7.5: the AM quotations against `lit-search.md` and `lit-discrete.md`.
- §7.6: 8.5× to 26.4×; 1.54× in bytes; 94.4% (561,342 of 594,488); about 7 look-ups (7.39, re-run); records outnumbering kept classes on all six targets; the peak in the last pass on 206 of 206.
- §1.4, §1.6, §1.7: 874 lines; thirteen of sixteen and the three changes; 25 candidates and 60–150×; 3,500, 2,200, 1,300 and 750 against §9; Stage C against §11.3; 2.5%.
- §5.9 paragraph: three times chance (0.48 and 0.54 against 0.15); no more saving than the control (0.77–0.83 against 0.73).

## Could not check

- "Without this step the first six words are all versions of the length" (line 747), for the pool of 95,732. The scored pool file `pool_main.pkl` was not copied and no log has a selection without the repetition test. The claim is supported for an earlier pool (`verify-quotients.md` §3.2: all of the top fifteen) and by the review's own run.
- Literature figures in §6.7 and §7.4 were checked against the audit's reports, not against the papers.
- The largest restart cost of any single search (line 993). The logs give means per size only.
- The CPU time of the other pool runs, and wall times anywhere; only the main pool's `time` output is kept.
- Whether an early-exit comparison would match the label gains in Python (finding 6). No such arm was run, and I did not run one.
- A slip in a report, not in the plan: `verify-handoff.md` line 10 gives the integer code as 2·⌊log2 w⌋ + w − 1. Its own code and its stated values (4 bits at ±1, 17 at 1000) correspond to 2·⌊log2 w⌋ + w.
