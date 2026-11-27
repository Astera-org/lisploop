# factcheck2-B: §6.6, §6.7, §8.8 and every restatement of them in `dry.md`

Checked against the logs, not only the report. Short names: `vq/` is `/home/tlh24/lisploop/plan_v2c_audit/verify-quotients/`; "the report" is `plan_v2c_audit/reports/verify-quotients.md`; "the review" is `plan_v2c_audit.md` L128-248. Line numbers `L…` without a file are `dry.md`.

Three kinds of evidence are used and are marked: **[log]** read from a log; **[json]** my recomputation from a saved `.json` beside the log; **[rerun]** a scratch copy of the scripts that I ran. My scripts are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/factcheck2/`. Nothing under `/home/tlh24/lisploop` was touched.

Summary: 23 findings. The tables of §8.8 are almost entirely right (one cell wrong, one column missing a caveat). The problems are in the prose that summarises them: one experiment is described as something it was not (reuse), one sentence has no experiment behind it ("in every setting"), and several attributions to the review are stronger than its text.

## Findings, most serious first

### 1. FACTUAL ERROR. The reuse "index by labels" was not an index by labels, and the test was an outline

- L702: "But indexing past problems by their labels did not pay. Replaying every stored solution, with no index, found all 25 repeated tasks at a cost of at most 60 candidates; the index found 19."
- L807: "On 25 repeated tasks with fresh inputs, replay found all 25 at a cost of at most 60 candidates; an index of past problems by their labels found 19 (§8.8)."
- L1158: "The index found 19, because a label that holds on every row of one input set need not hold on the next."
- L1548 (G.3) and L1479 (G.0, "It did not serve reflection as an index") repeat it.

Source. `vq/q5_reuse.py` L12 and L141: method C keys on `signature(env, target, ty)`. `vq/q2search.py` L584-627: that function is the 23 hand-written Boolean task-boundary properties of the Naive Bayes arm. No quotient label enters it. The review's third change (L246) is a column of "universal abstract invariant" labels, which was not built. The report says so: "Reproduced in outline; not a faithful rebuild" (L456) and "Not done: … a faithful Q5" (L556). The numbers themselves are right **[log]** `q5_reuse.log`: B 25/25 repeats, C 19/25. The "60" is a bound: replay costs 3 candidates per stored solution and at most 19 are stored, so the maximum is 57 per task **[rerun]**; it grows linearly with the store.

Direction check **[rerun, exploratory, `fc_reuse_labels.py`]**: with the key swapped to all-row labels of the six quotients, the index finds 9/25 (input and output labels) or 14/25 (output only). So the conclusion survives; the description and the figure do not match each other.

Replace L702 with: "But an index of past problems did not pay in the one small test. In five streams of 20 tasks, replaying every stored solution found all 25 repeated tasks at no more than 57 candidates per task; an index keyed on 23 hand-written all-row properties found 19. That test was an outline, the key was not quotient labels, and replay costs three candidates per stored solution, with at most 19 stored here. The third change the review proposes is not adopted for now (Appendix G)."
Replace the last sentence of L807 with: "On 25 repeated tasks with fresh inputs and at most 19 stored solutions, replay found all 25 at no more than 57 candidates per task; an index by 23 all-row properties found 19 (§8.8). Replay's cost grows with the store."

### 2. FACTUAL ERROR. "The hits reproduce (7 to 11 per stream)" is the count for a method with no index

- L1158: "the review reports 11 reuse hits and 2.2× fewer candidates from indexing past problems by labels that hold on every row. The hits reproduce (7 to 11 per stream)."

Source **[log]** `q5_reuse.log`, six streams (seed 0, then 100-104). Method E, replay of every earlier solution plus one-operator synonym variants of all of them, no index: 11, 10, 8, 9, 7, 7. Method D, the index plus synonym variants, which is the review's design: 4, 5, 6, 6, 4, 5. Method C, index alone: 4, 3, 5, 4, 2, 5.

Replace with: "With an index and synonym variants, as the review describes, hits were 4 to 6 per stream. Counts of 7 to 11 were reached only with no index, by replaying every earlier solution and then its one-operator synonym variants."

### 3. FACTUAL ERROR. "in every setting it was flat in the size of the program"

- L680: "The factor itself is not fixed: one quotient gave 3 to 6 times, three gave 6 to 13, six gave 16, and merging three into one product gave 24, with answers lost. But in every setting it was flat in the size of the program."

Source. `vq/q2_length.py` L39-40 runs two configurations, both the six quotients (2,000 i.i.d. and 20,000 enriched probes). One quotient, three quotients, and the merged product were never run against program size. Splitting the 60-task sweep by found size **[json, `sweep_by_size.py` on `q2_sweep.json`]**, sizes 3 / 4 / 5 with 5 / 25 / 29 tasks: sign 5.8 / 5.9 / 6.0; six quotients 10.9 / 17.2 / 16.0; merged product 12.2 / 23.2 / 30.0 on the tasks it did not lose. The merged setting is not flat.

Replace the last sentence with: "Only the six-quotient setting was run against program size."

### 4. OVER-STATEMENT. "It is a constant factor, not a change of exponent"

- L680: "*It is a constant factor, not a change of exponent.* The gain is the same, 11 to 16 times, for programs of 3, 4, 5, and 6 nodes."
- Also L68 ("it does not change the exponent"), L719 ("Nothing measured so far does"), L1479.

Source **[log]** `q2_length.log`: 14.4, 11.1, 11.6, 15.6 for 13, 14, 6, 5 tasks; 40 single-input chains; per-task gains run from 5.6 to 42.5, and from 7.2 to 42.5 within size 6 alone. Three things in the same log cut against the flat reading as stated:
- In listing order the gain falls with size: 19.0, 15.2, 10.8, 10.2.
- Wall-time gain rises with size: 1.3, 2.0, 4.2 at sizes 4, 5, 6.
- Stored-class gain rises: 1.7, 1.7, 1.8, 2.7 (4.7 to 8.9 with look-ahead).

A fit of log gain on size **[json, `length_slope.py`]** gives ×1.00 per node for order-averaged candidates, with a 95% interval of ×0.85 to ×1.17; ×1.78 per node for wall time. For L719, the residue experiment was never analysed by size, and `q3_g2.log` shows its candidate gain going 4.8, 7.2, 24, 20, 42, 30, 16 over true sizes 3 to 9.

Replace with: "*In candidates it behaved as a constant factor over the sizes tried.* The gain was 11 to 16 times for programs of 3 to 6 nodes, on 38 single-input chains with the six quotients; the data cannot exclude a drift of 15% per node either way. In wall time the gain was still rising at the largest size."

### 5. OVER-STATEMENT. Cold against warm mixes two baselines inside each range

- L672: "It works for operators that have never appeared in a solution: 11 to 21 times on tasks that need one, against 15 to 26 on the others."

Source **[log]** `q2_main.log`, `q2_main_seed2.log`. Listing order: cold 11.2, 11.7; warm 16.1, 25.9. Order-averaged: cold 21.4, 14.2; warm 15.3, 25.5. Each quoted range takes its low end from one baseline and its high end from the other. Under listing order the cold tasks gain less in both task sets. Only two operators were held out.

Replace with: "It works for the two operators held out of every solved task. With the baseline averaged over operator orders the gain is 21 and 14 times on tasks that need one (two task sets), against 15 and 26 on the others; in listing order it is 11 and 12 against 16 and 26."

L671 has the same mixing, harmlessly: "14 to 18" spans both baselines, and "between 3 and 60 times on all but one task" is true only in listing order (order-averaged, two tasks exceed 60: 125× and 308×).

### 6. MISSING CAVEAT and one wrong number. "Counts fail there"

- L673: "Counts fail there, as the review says. Naive Bayes over signature bits, which §6.3 proposed, ranked the never-used operators 52nd to 58th of 61. Used as prices, it sent 5 of 8 such tasks past a cap of three million candidates."
- L616: "it ranked operators it had never seen in a solution 52nd to 58th of 61."

Source **[log]**. Ranks are 53-58 in the first task set and 51-55 in the second (`q2_main_seed2.log`, Md1: `'dbl_all': 51`). The report's "52-58" (L160) is a mis-copy. As an ordering, Naive Bayes did not fail on those tasks in aggregate: 1.72× and 3.12× against the order-averaged baseline on cold tasks (0.83× and 2.29× in listing order), and in the second set it did better on cold tasks than on warm ones (3.12 against 1.93). The failure is in the price use. "5 of 8" is the first set; the second has 6 of 11, and 2 of its 9 other tasks also pass the cap.

Replace with: "As prices, counts fail there, as the review says. Naive Bayes over signature bits ranked the never-used operators 51st to 58th of 61, and used as prices it sent 5 of 8 such tasks past a cap of three million candidates (6 of 11 in the second task set). Used only as an order it still gave 1.7 and 3.1 times on those tasks."

### 7. FACTUAL ERROR (method). "found 29 analogies … that way"

- L665: "It is the dependency test of §7.6: is the label of the output a function of the labels of the inputs? §8.7 found 29 analogies between pairs of operators that way in 1.3 ms."

Source. `reports/cross-space.md` L292: the test was "three re-indexes per (f, op1), then one column operation and one column comparison per triple", for a given second operator. No dependency test was run. L296-301: 350 triples tested in 1.32 ms, 34 hold, 29 non-trivial. L305-312: 17 of the 29 carry an operator to itself (`+ → +` under negation and doubling, `max → max` under shifts, `* → *` under squaring); 12 relate two different operators, all `max`/`min`.

Replace with: "§8.7 tested 350 candidate maps between operator tables by comparing columns, in 1.3 ms; 29 held, 12 of them between two different operators."

### 8. OVER-STATEMENT. "rebuilt all five"; "zero misses … do not" reproduce

- L1071: "One auditor rebuilt all five from the review's prose".
- L1160: "Its "zero misses", its second gain from ranking, and its 2.2× for reuse do not."

Source. Report L556: the 44-state Merge-and-Shrink, CEGAR, and a faithful fifth experiment were not built. Report L31: zero misses did hold on every task set of 20 to 60 tasks at 2,000 probes, including the review's own eight; the losses are 1 of 300 at 1,000-3,000 probes and 34 of 300 at 100.

Replace L1071 with: "One auditor rebuilt four of them from the review's prose and the fifth in outline". Replace L1160 with: "Its zero misses holds on its own eight tasks and fails as a property of the method; it gives no separate figure for ranking, which added 3-5% here; its 2.2× for reuse does not reproduce."

### 9. OVER-STATEMENT (attribution). Ranking by surprise as "a second gain"

- L682: "which the review presents as a second gain"; L1117: "The review counts it as a second mechanism."; L1541: "Ranking by surprise as a second gain".

Source. Review L192 names "`+SoftMDL` operator ranking" as part of one arm; the results table (L194-203) has one column, "AbsDFTA + SoftMDL"; L163-168 calls support and surprise "two coupled views" of one table. It reports no separate gain. L1117 is fair. L682 and L1541 are not.

Replace L682 with: "which the review folds into its headline arm without a separate figure".

### 10. OVER-STATEMENT (attribution). The "lucky order" is the rebuild's order

- L1119: "it is measured against a listing order in which the needed operator happens to come second."
- L1540: "The review's 6.5× for Naive Bayes was against a lucky operator order".

Source. Report L484, L489: the operator list and its order were chosen by the auditor. `dbl_all` is second in that list. The review's order is not known.

Replace L1119's clause with: "in the rebuild, the baseline's listing order happens to put the needed operator second; the review's own order is not known."

### 11. FACTUAL ERROR (citation) and OVER-STATEMENT. What §6.6 keeps from the earlier plans

- L653: "keeps the word-to-object mapping of `plan_v2b.md` §7.8, the three query forms of `plan_v2.md` without their vectors".
- L705: "**The three query forms** of `plan_v2.md`"; L1498 repeats both.
- L657: "This is the review's proposal, restated in the store's nouns."

Source. `plan_v2.md` L316-320 has like, analogy, action as vector operations; the word "query" does not occur in it, and `act` appears only as a subscript. The forms are named in `plan_v2.tex` L107, L401, L669 as "`(:like/:analogy/:act)`" and a "3-combinator query interpreter". Neither file gives the argument shapes `like x`, `analogy a b c`. `plan_v2b.md` L594 maps action words to rewrites that "create a base, lift, or partition"; the table at L659-663 maps 'action' to a verb table instead, so one row of three is not kept. In the review (L178) the 'analogy' word is "The same abstract verb class / commutative square relating two `(input, output)` pairs"; the map between two operators' tables at L663 is this document's own, from §8.7. The plan 7 quotation (L693) is verbatim, `plan7/plan7-recursion.md` L67.

Replace L653's clause with: "keeps the like and analogy rows of the mapping in `plan_v2b.md` §7.8, the `like`/`analogy`/`act` query forms named in `plan_v2.tex`, without the vectors `plan_v2.md` gave those words". In L705 change `plan_v2.md` to `plan_v2.tex`. Replace L657 with: "The first two rows are the review's proposal, restated in the store's nouns; the third comes from §8.7."

### 12. OVER-STATEMENT. "for 69% of operators"

- L702: "for 69% of operators the nearest table belongs to the same hand-listed family **[M]**."

Source **[log]** `q5_reuse.log`: "22 of 32 neighbour slots". The denominator is the 32 operators placed in seven hand-listed families; 29 of the 61 are in none. Neighbours are restricted to the same type, so chance is 29% **[rerun, `fc_syn.py`]**: the zip and reduction families score 5/5 each where chance is 80% and 50%; the adjacent-map family scores 1/5 and the running family 0/3. The figure is also absent from §8.8.

Replace with: "of the 32 operators placed in a hand-listed family, 22 have a family member as nearest table among operators of their type, where chance gives 9 **[M]**."

### 13. MISSING CAVEAT. "one more group-by on them"

- L711: "Stage A already builds the probe tables, for laws and inverses; a verb table is one more group-by on them".
- L825: "one group-by over the same probe table."

Source. The tables were learned from 2,000 probes per operator, drawn to include empty and one-element lists (report L93, L516-517). At 100 probes 34 of 300 answers were lost **[log]** `q2_sound.log`. The law probe spaces in this document have 8 to 32 rows (L946, L953).

Add after L711's sentence: "The probe tables must be larger for this: 1,000 or more probes per operator against the 8 to 32 rows that laws need, and at 100 probes 11% of answers were lost."

### 14. MISSING CAVEAT. "time 2 to 4 times"

- L68: "cut candidates about 15 times and time 2 to 4 times"; L1266, L1479, L1538 the same.

Source **[log]** `q2_length.log`: 1.3× at size 4, 2.0× at 5, 4.2× at 6. At size 3 every task ran no faster (0.45 to 0.99, on runs under 4 ms). §8.8 L1116 gives the three figures; L681 and the four summaries drop the first.

Replace with: "and time 1.3 to 4 times, more at larger sizes".

### 15. OVER-STATEMENT and internal inconsistency. Items 2 and 3 of "What the vocabulary unlocks"

- L698: "The tables replace it with one look-up per candidate **[M]**."
- L699: "*A library that grows without slowing search.* A new entry gets its tables at once, and is neither favoured nor starved **[M]**."
- L852: "Test a candidate against the target's labels before evaluating it | about 7 look-ups in the reproduction".

Source. L681 says seven look-ups, not one. The seven is total look-ups divided by candidates that survive to evaluation **[log]** `q2_sweep.log` 7.08; the test is made per group of candidates sharing labels (`vq/q2search.py` L292-322), and the look-ups are counted over complete last levels while evaluations stop at the answer (like for like it is 6.5 **[json]**). No run varied the size of the library; 61 is the only size measured.

Replace L698's sentence with: "The tables replace it with a few look-ups per candidate **[M]**." Replace L699's heading with: "*A library whose new entries are not starved.*" and add "No run varied the size of the library." In L852 write "about 7 look-ups per candidate that survives".

### 16. FACTUAL ERROR (one cell) in the first table of §8.8

- L1081: "Naive Bayes over 23 hand-written properties, trained on 80 solved tasks, used to order | 2.7×, 2.5×".

Source **[json]** `q2_main.json`: 2.648. L616 and L674 say 2.6. Replace with "2.6×, 2.5×".

Same table, COSMETIC. L1084 "Both sides of each ratio are averaged over random orders" is not true of rows 4 and 5, where only the baseline is averaged and the method has its own order. The column head says "geometric mean of 20 tasks"; rows 2 and 3 are means over 8 and 11, and 12 and 9.

### 17. MISSING CAVEAT. The soundness sentences

- L679: "and none only from 10,000." True for i.i.d. probes. With probes enriched with edge cases, none were lost from 1,000 **[log]** `q2_sound.log`.
- L679: "Merging quotients into one product, which the review does to save memory, lost 8% at 3,000 probes." The rebuilt product is sign × parity × order, 38 labels, plain. The review's (L192, L207) is nonneg × parity × order, 44 states, with a shrink step, and its stated reason is that separate bounds miss interactions; the memory cut is the reported effect. Report L556 lists it as not built.
- L1231: "lost 0.3% to 11% of tasks depending on the number of probes" omits that the range reaches zero.
- L1114: "Of 115 losses across all the configurations tried, 113 have one cause". The count is right (25 configurations of the soundness run; the table above it shows 8, which sum to 68). The report says "coincide with", not "have one cause"; the other two were lost through a shorter equivalent program and were not traced.

Replace L679's clause with: "and none only from 10,000 random probes, or from 1,000 when the probes include edge cases". Replace the merge sentence with: "Merging three quotients into one product, a plain version of what the review does, lost 8% at 3,000 probes."

### 18. OVER-STATEMENT. The flat-description sentences

- L655: "They do not share its *operators* more often than a control that ignores the task, and no search work is saved."
- L716: "Whether store-generated signatures separate problems as well as hand-written ones. For a problem's form they do, at three times chance".
- L1230: "A vocabulary the kernel generates for itself carries no signal beyond types. Flat signatures did not, for operators (§8.7)".

Source. `reports/cross-space.md` L150-158: the nearest neighbour shares at least half the operators in 0.60 of cases against 0.425 by chance, so it does share operators above chance. The comparison with the control is on a different quantity: a grammar built from the three neighbours solves 67% and 66% of tasks against 69% for the control (L243-246). L243-245: by solve rate the signatures beat types-only (0.67 against 0.49); by fair cost types-only is cheaper (0.67 against 0.77-0.83). "No work saved" holds for the uncapped total (1.09, 0.95); the per-task geometric mean is 0.83 and 0.77. No hand-written signature set was run, so L716's "as well as hand-written ones … they do" has nothing behind it.

Replace L655's sentence with: "A grammar built from the neighbours' operators solves the task no more often than one built from the commonest operators without looking at the task (67% against 69%), and summed over tasks no search work is saved." Replace L716's answer with: "For a problem's form they do better than chance by three times; for its operators they do not (§8.7). No hand-written set was run beside them." In L1230 write "no signal beyond a control that ignores the task".

### 19. MISSING CAVEAT. The residue experiment

- L1153-1154, column "Wall time": "1.1× faster", "1.4× faster". These use the last-level join and exclude a one-off 65-143 ms per row set **[log]** `q3_poly.log`: "the one-off cost of the domains … is NOT included". With the scan variant both rows are slower (64 against 57 ms; 800 against 625 ms).
- L1156 and L701: "117 of 120 random targets were lost". The 120 were drawn to need `div` or `mod` **[log]** `q3_g2.log`.
- L968: "On the first grammar alone, storing classes by their residues modulo small primes cut stored classes 8.5 to 26 times". §8.4's first grammar has leaves x, y, z, 0, 1, 2; the experiment has x, y, 0, 1, sizes 7 to 13, at most 17,609 classes, in Python.

Add to the table caption: "Wall time excludes a one-off 65-143 ms and uses a join on the last level." In L1156 and L701 write "117 of 120 random targets that need `div` or `mod`". In L968 write "On that operator set with two variables, at sizes 7 to 13".

### 20. OVER-STATEMENT. "to three decimals"

- L684: "this reproduced the review to three decimals"; L1132: "reproduce to three decimals".

Source. The table at L1125-1129 shows two of five rows off in the third place: `(mod x 3)` 0.861 against 0.860, `(sgn x)` 0.832 against 0.830 **[log]** `q1_int_size7.log`. Replace with "to within 0.002".

### 21. COSMETIC. Quotation and wording

- L648: the owner's line is "Hypothetically through the development of a vocabulary / short descriptive language" (`prompt4.md` L175). "by" drops the hedge. Write: hypothetically "through the development of …".
- L1114: "The review's rule, "unseen means anything"" is in quotation marks and is not the review's wording. The review (L165) says an unobserved abstract input "defaults soundly to ⊤". Drop the marks.
- L669: "61 whole-sequence operators": 11 of the 61 are on integers alone.
- L675 "10.7 against 15.8" against L1093 "15.7×": two runs of the same configuration (15.76 in `q2_auto.log`, 15.69 in `q2_sweep.log`). Use one.
- L1132: "fifteen vacuous predicates take the top places": the log prints the top fifteen, all vacuous; there may be more. Write "the top fifteen places".
- L702, L807: "at a cost of at most 60 candidates" needs "per task", as L1158 has.

### 22. MISSING CAVEAT (minor). Two measured costs that §6.6 leaves out

- Stored classes fell only 2.3 to 2.8 times with verb tables (7 to 9 with a one-step look-ahead) **[log]** `q2_main.log`, `q2_sweep.log`. §8.4 says memory is the wall, and §6.6 gives only the candidate figure.
- Choosing the quotients automatically took 18.9 s **[log]** `q2_auto.log`, against 0.18 s to learn tables. L669 gives only the second, and X4 (L1275) does not list selection in its fair cost.

### 23. COSMETIC. Cross-references and consistency

- L567 (§5.9) says the tables "are built" in Stage C; L711 says Stage A builds them and Stage C uses them.
- L1543 cites §8.8 for "the bound on remaining steps rarely exceeds one or two"; that statement appears only in §6.6 (L682). The same is true of the 69% figure.
- L1473: "(244 lines)". The review file is now 323 lines, modified 17:20 on 25 November; an Appendix A (L250-323) was added. Nothing in it contradicts the attributions checked here.

## Checked and found correct

- Every other cell of the three tables under "Verb tables" (L1075-1112) against `q2_main.log`, `q2_main_seed2.log`, `q2_sweep.log`, `q2_auto.log`, `q2_sound.log`; the sums 2.60 M, 0.17 M, 1.25 M (L1116) **[json]**; 180 ms (`q2_tables_cost.log`); the library composition 31 / 6 / 9 / 11 / 4.
- "Quotients chosen automatically keep about two thirds" (10.65 / 15.76 = 0.68), and the four hand-supplied items at L686-689.
- "5 of 8 … past a cap of three million" for the first task set; T8 as 7.6× worse in one set and 0.84× in the other; rank correlation 0.69 (recomputed); "85 candidates and 812 classes" (review L197).
- The dependency-score table (L1123-1130) and the sequence figures: 1,109; 5,475; 0.877; ranks 48 to 311; the distractor; the constant-output convention; sign 4th with truncating division.
- The guard table (L1136-1143), 1,936 terms, 302 masks, 0.48 ms; "47 to 151" for four laws.
- The residue table's class counts; 8.5 to 26; 200 of 200; 1.2 to 1.7 for single rows.
- Reuse: 25 of 25, 19, the saving 1.2 to 1.3, and 20/9 = 2.22.
- All four `prompt4.md` quotations at L648-651 (L174, L175, L187, L191, L197, L201-203) and the cited range; the plan 7 quotation; the LAPS figures (`lit-geometry.md` L489-492).
- Attributions that hold: the review claims zero misses (L205, L235); its three proposed changes are what L667, L1275, and L702 say (review L244-246); 161 ms; 6.5× on T8; 1.5× to 26.5×; 8× to 23×; its own warning on `div` and `mod`; "soundly"; "lumpability"; "ring".
- "Nearly all of it is one test": supported by Table B of `q2_main.log` (for example 533 of 553,374 last-level candidates admitted on T3) against a 2.5× cut below the last level.
- Report against logs: every table of the report matches its log. One mis-copy, the rank range in finding 6.

## Could not check

- "the bound on how many steps remain rarely exceeds one or two" (L682): no log prints the distribution of the bound; it rests on the report's sentence (L211-213).
- "experiments whose code was not kept" (L669, L1071): no source in the repository says either way.
- "you wrote that the representation which yields language probably unlocks other expensive parts" (L646): the owner's request is not among the files given.
- Whether the review had 244 lines at 16:05 (L1473): the file has changed since.
- The four placeholders, and sections 5.9, 8.6, 8.7 beyond the sentences of §6.6 that summarise them, were out of scope.
