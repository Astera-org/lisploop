# Final check of plan v2c (v5-for-check.md) against the full record of the word measurements

"The document" is `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md`, and line numbers without a file name are its lines. "The record" is `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/measurements-words.md`. The scripts used for this check are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-final/`. Nothing under `/home/tlh24/lisploop` was changed and nothing was built.

Every figure in §8.7 itself agrees with the record. I found no figure in the listed sections that differs numerically from the record. The findings are of four other kinds: a figure attached to the wrong arrangement, a qualifier that the record carries and the document dropped, sections that disagree with each other, and citations of "(§8.7)" for things the shortened §8.7 no longer holds. I found no contradiction between the record and the parts of the underlying reports I consulted (`verify-words.md` in full, and the relevant parts of `verify-handoff.md`, `verify-probes.md` and `verify-quotients.md`).

The findings are numbered from most to least serious.

## A. Findings that change what a claim says

**1. INCONSISTENT (qualifier dropped). The document says in five places that rounds of increasing bound saved the conditional. The record says the test asked only whether the two branches were kept.**

- Line 1424 (§11.1): "With a size bound raised round by round, no: Python kept both branches of all 120".
- Line 1311 (§8.8, item 9): "Rounds of increasing bound let the near miss through in Python (§8.7)."
- Line 908 (§7.2): "With rounds of increasing bound the loss did not occur, because both branches of the conditional are evaluated and kept one or two rounds later."
- Line 746 (§6.4) and line 1279 (§8.7): "both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost."

The record, line 86, adds: "That test asked whether both branches were kept. It did not ask whether the guard was." This qualifier is nowhere in the document (a search for "whether the guard" finds nothing). It matters, because the same paragraph shows that in the prototype the guard had to be exempted by hand to survive, and that even then 7 of 9 conditionals were lost. The row of §11.1 answers "no" to "Does a label filter hide answers that need a conditional?", which the measurement does not support in that form.

Replacements:

- Line 1279: "In Python, with a size bound raised round by round, both branches of all 120 conditionals built for the test were kept one or two rounds after plain search would first hold them, at no extra cost. That test asked whether both branches were kept. It did not ask whether the guard was kept, or whether the conditional was then put together."
- Line 1424, second cell: "Applied strictly at one size, yes: the store prototype lost all 9 conditionals, and 7 of the 9 with Boolean candidates exempted. With a size bound raised round by round, the branches were not hidden: Python kept both branches of all 120. Whether the guard is kept as well was not asked."
- Line 1311: "With rounds of increasing bound, in Python, both branches of every conditional built for the test were kept (§8.7). Whether the guard was kept was not asked."
- Line 908: "With rounds of increasing bound, in Python, both branches of the conditional were evaluated and kept one or two rounds later. The test did not ask whether the guard was kept as well."
- Line 746: add after "at no extra cost": "The test did not ask whether the guard was kept."

**2. WRONG FIGURE (attached to the wrong arrangement). The 2.4× to 3.0× of the offset and scale proposal is quoted in §7.2 for the arrangement of step 3, and in §11.1 for no arrangement. In the record it belongs to the review's arrangement.**

- Line 905 (§7.2, step 3, which is headed "Every candidate that is evaluated is checked as a near miss"): "On tasks built to contain such a step, this proposal evaluated 2.4 to 3.0 times fewer candidates than the label filter alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate **[M]**."
- Line 1423 (§11.1): "Where a near miss exists, yes: 2.4 to 3.0 times fewer candidates than the label filter alone, on tasks built to contain a constant offset or scale."

The record, line 76, gives these figures for the check run "Inside the label-filtered search, on the classes the filter keeps. This is the review's arrangement." The arrangement of §7.2 is the next one (record, line 77), which halved the candidates again. §8.7 (line 1273) states this correctly; lines 905 and 1423 do not.

Replacements:

- Line 905: "On tasks built to contain such a step, the check was first run as the outside review arranged it, only on the classes the label filter keeps. In that arrangement it evaluated 2.4 to 3.0 times fewer candidates than the label-filtered search alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate **[M]**. Run on every candidate that is evaluated, which is the arrangement of this step, it halved the candidates again, as the paragraph after this list reports."
- Line 1423, second cell: "Where a near miss exists, yes. On tasks built to contain a constant offset or scale, a check run only on the classes the label filter keeps evaluated 2.4 to 3.0 times fewer candidates than the label filter alone, and a check run on every evaluated candidate halved the candidates again. On ordinary tasks it added little."

**3. TERM and INCONSISTENT. "One step from the answer" is defined one way and used another, and under the definition the headline result contradicts the sentence after it.**

- Line 44 (Terms): "A class is one step from the answer when one more operator applied to it gives the target."
- Line 688 (§6.2): "Call a class *one step from the answer* when applying one more operator to it gives the target ... Among the classes one step from the answer, the labels ruled out nearly half. ... They never ruled out a class on the path to the answer".
- Line 1266 (§8.7) and line 1422 (§11.1) use the phrase the same way, without a definition.

As defined, every class one step from the answer leads to the target, so "the labels ruled out nearly half" of them would mean that the tables are wrong about half of the classes that lead to the answer. What was measured is different: the share of all classes of the true parent's size. The record says so at line 66: "Where a figure compares the true parent with other classes one step from the answer, the other classes are all the classes of the true parent's size." `verify-handoff.md` (line 43) has "rules out 43% / 47% of classes one step out". The document dropped the sentence that makes the phrase mean this.

Replacements:

- Line 44: "A class is one step from the answer when it has the size of the answer less one operator. The true parent is the one class of that size from which the answer is in fact built (§6.2)."
- Line 688: "Call the class from which the answer is in fact built by one more operator the *true parent*, and call every class of the true parent's size a class *one step from the answer*, whether or not any operator takes it to the target."
- Line 1266: insert after the first sentence of the bullet: "A class one step from the answer is any class of the size of the true parent."

**4. INCONSISTENT. §7.2 says the tables rule out nothing below the bound. §6.2 and §8.7 say they rule out 43–47% of the classes one size below it, and that applying them throughout doubles the gain.**

- Line 898 (§7.2, step 2): "For smaller candidates the tables tried so far ruled out nothing (§6.2), so in practice the test acts on the last step of each round."
- Line 688 (§6.2): "Among the classes one step from the answer, the labels ruled out nearly half. Among classes two or more steps away, they ruled out none."
- Line 1266 (§8.7): "Applying the tables throughout enumeration still doubles the gain over applying them only at the final size, 15.6× and 16.9× against 7.8× and 8.0×." The record (line 68) gives the likely cause: the tables "also skip, before they are evaluated, the candidates one size below the answer that cannot reach the target's labels in one more step".

A class one step from the answer is a "smaller candidate" in the sense of line 898, so the pointer to §6.2 does not support the sentence.

Replacement for line 898: "For a class one size below the bound, the question is whether one more operator can take it to the target's labels, and the tables tried so far ruled out 43–47% of such classes. For classes smaller than that they ruled out nothing (§6.2). So in practice the test acts on the last step of each round and on the size just below it, and applying it throughout the enumeration gave twice the gain of applying it at the final size alone (§8.7)."

**5. INCONSISTENT. Where the near-miss check runs.** Seven places say it runs inside the tentative pass (line 93 in §1.3, line 908 in §7.2, line 1273 in §8.7, line 1311 in §8.8, line 1385 in §10, line 1441 in §11.2, line 1456 in §11.3). One sentence says otherwise.

- Line 904 (§7.2, step 3): "Each candidate that either pass evaluates is compared with the target."

"Either pass" makes the fallback a pass and puts the check in it too. The Terms table (line 34, line 50) defines the fallback as the plain search, which "uses no guidance". Four paragraphs later, line 908 concludes "So the check lives inside the tentative pass".

Replacement for line 904: "Each candidate that the tentative pass evaluates is compared with the target."

**6. POINTER. The sentence in §8.7 that names the full record promises three things the record does not deliver, and the file is not yet at the path given.**

- Line 1217: "The full record, with every figure quoted elsewhere in this plan, the arrangement each was measured in, and the script behind it, is `plan_v2c_audit/measurements-words.md`."

(a) The record names no script for any figure. Its line 3 says: "The reports named in Appendix D of the plan hold the commands and logs for every figure." (b) Not every figure quoted elsewhere is in it; finding 7 lists the exceptions. (c) At the time of this check `/home/tlh24/lisploop/plan_v2c_audit/` holds no `measurements-words.md`. It also holds no `revision-notes.md`, which lines 3, 7 and 1552 cite, and `plan_v2c_audit/reports/` holds none of the `apply-*.md` logs of line 1585. All of these exist only in the scratchpad `round3/` folder and must be copied before the document is delivered. (d) Appendix D (lines 1554–1585) does not list the record at all.

Replacement for line 1217: "The full record is `plan_v2c_audit/measurements-words.md`. It gives the figures quoted elsewhere in this plan and the arrangement each was measured in. The commands and logs behind each figure are in the reports that Appendix D lists for §8.7."

Row to add to the table of Appendix D: "| `measurements-words.md`, which is in `plan_v2c_audit/` and not in `reports/` | the full record of the measurements that §8.7 gives in short | the folders of the six reports above |"

**7. POINTER. Sentences that cite §8.7, or stand under a citation of §8.7, for something the shortened §8.7 no longer contains.** Each is in the record unless the last column says otherwise.

| Line | Section | What is cited | In §8.7 now? | In the record? |
|--:|:--|:--|:--|:--|
| 736, 1420 | §6.4, §11.1 | "the gain is 14× to 18×, depending on the set of tasks" | no; §8.7 has 17.5×, 18.5×, 13.9×, 16.7× and never states the range | yes, line 7 |
| 737 | §6.4 | "Used only to order the operators within each size, counts still gave 1.7× and 3.1× on those tasks" | no | yes, line 36 |
| 768 | §6.5 ("The figures are in §8.7") | "Without this step the first six words are all versions of the length." | no | **no.** `verify-quotients.md` line 515 has "Without a redundancy rule the top 15 are all the length", for the earlier pool |
| 769 | §6.5 | "is the value zero" for five of the six list words | no | yes, line 97 |
| 774 | §6.5 | "Most of the words with many labels are two-part words." | no | **no**; the table in §3a of `verify-words.md` is consistent with it |
| 775 | §6.5 | with ten words the gain rose "from 13.5× to 15.3×" | no | yes, line 98 |
| 776 | §6.5 | 13.9× with none lost, and 12.3× and 10.6× with one and three lost | no | yes, line 94 |
| 788 | §6.5 | the rule for two-argument operators, under "each measured" | no; the slice measurement is gone from §8.7 | yes, line 58 (see finding 8) |
| 789 | §6.5 | "The review first proposed to add to the tables whatever a fallback search discovers, and then dropped the idea." | no | **no**; the outside review says it at `plan_v2c_audit.md` line 435 |
| 828 | §6.8 | the merged word's gain "rose with program size against one of the two baselines and was flat against the other" | no | yes, line 57 |
| 902 | §7.2 | "With the filter on, the ordering of step 1 adds only a few percent." | no | yes, line 27 (3% to 5%) |
| 910 | §7.2, "(§8.7)" | the seven runs are "five functions, two of them run a second time on the kernel's spec rows"; labels were needed on "`scan` with a function argument"; with the branches' size as the bound "the look-ahead discarded the branches" | no; §8.7 has only "seven guarded runs" and "five of the seven" | yes, line 88 |
| 944 | §7.4 | "at most 19 stored solutions" | no | yes, line 111 |
| 1020 | §7.6, under "the measurements of §8.7 **[M]**" | "those records outnumbered the classes kept" | no | yes, line 104 |
| 1021 | §7.6, "(§8.7)" | "4.3 times with a one-step look-ahead"; "The two instruments count plain search's classes differently" | no | yes, lines 105 and 107 |
| 1023 | §7.6 | "94% of stored classes are of that size" | no | yes, line 105 |
| 1600 | Appendix D | "One figure of §8.7 comes from one of them: that the review's result of no misses held for 7 of 20 probe seeds." | no | yes, line 40 |

The simplest repair that keeps §8.7 short is to change the citation in each of these sentences from "(§8.7)" to "(the full record of §8.7)", and to add the three items marked **no** to the record. For line 1600 the replacement is: "One figure of the full record behind §8.7 comes from one of them: that the review's result of no misses held for 7 of 20 probe seeds." For line 768, the record and the sentence should both say what was measured: "Without this step, in the earlier and smaller pool, the fifteen best-scoring words were all versions of the length."

**8. INCONSISTENT. §6.5 says a rule was measured; the record says the measurement did not decide it.**

- Line 786: "Three further rules, each measured:" and line 788: "*A table for a two-argument operator is built from probes that vary both arguments together.*"

Record, line 58: "So the measurement does not decide the matter, and the rule is adopted on an argument." The measurement also went against the rule at an equal budget: "random probes of both arguments together rejected more than random slices did: a median of 14.6 per 500 pairs against 0."

Replacements:

- Line 786: "Three further rules. The second and the third rest on measurements. The first was measured as well, but the measurement did not decide the matter, and the rule is adopted on the argument given with it."
- Line 788, to be added at the end: "The review's evidence for this rule was that tables built from slices made 287 and 422 false rejections for `div` and `mod`. That depended on the slices it chose. Most random choices of slice reject nothing, and at an equal budget random probes of both arguments rejected more true results than random slices did."

**9. INCONSISTENT between the document and the record. Which setting is to be built.**

- Line 776 (§6.5): "It is the version to build, with the setting still to be decided."
- Record, line 94: "The middle setting of that second version is the one §6.5 proposes to build."

One of the two has to change. If §6.5 is right, the record's sentence should read: "§6.5 proposes to build that second version and leaves the setting open." If the record is right, line 776 should read: "It is the version to build, at the middle setting, which is the one that lost no answer."

**10. INCONSISTENT inside §8.7, made by the shortening. Two adjacent bullets say the prototype's filter lost conditionals by skipping, and that it cannot skip.**

- Line 1279: "In the prototype a filter applied at the one size where the near miss sits lost the conditional in all 9 runs".
- Line 1280: "The prototype keeps one bank across sizes and does not restart, so it cannot skip, only reorder."

The record reconciles them (line 86: "That size was handed to it, and the search stopped there"; line 87: "a candidate skipped at one size would be missing if that size turned out not to be the last").

Replacements:

- Line 1279: "In the prototype a filter that skips was applied at the one size where the near miss sits. That size was handed to it, and the search stopped there. It lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted."
- Line 1280: "When the size of the answer is not handed over, the prototype cannot skip. It keeps one bank across sizes and does not restart, so a candidate skipped at one size would be missing at the next, and the labels can only reorder the candidates of a size."

## B. Smaller disagreements

**11. WRONG FIGURE (arrangement). The memory saving "on lifted tasks" was measured with the answer's size handed over, and not with a held answer.**

- Line 1021 (§7.6): "The second is the look-ahead of §7.2, once a held answer gives a firm bound: in the store prototype it cut the classes held by ten times or more on lifted tasks."
- Line 1426 (§11.1): "ten times fewer classes held or more with the look-ahead once a held answer gives a firm bound".

Record, line 107: "With the answer's size handed over, the classes held fell from 25,639 to 270 on `reverse` ...". The saving with a held answer is the 34× of the seven guarded runs (record, line 88). §8.7 line 1281 keeps the two apart.

Replacements:

- Line 1021: "The second is the look-ahead of §7.2, once there is a firm bound on the size of the whole answer. In the store prototype it cut the classes held 34 times on the seven guarded runs, where a held answer gave the bound, and ten times or more on three lifted tasks, where the answer's size was handed over."
- Line 1426: "... and 34× fewer classes held with the look-ahead on the seven guarded runs, where a held answer gives a firm bound. Little elsewhere".

In the same paragraph, line 1021 gives "4.3 times with a one-step look-ahead" as a saving from labels, and line 1023 then presents the rule of holding the largest size as hashes as "One further saving". The record (line 105) says the two overlap: "Most of that further saving does not need labels ... that rule alone would save 5.8× in bytes, and labels would then add 1.3× to 2.5×." Replacement for the first sentence of line 1023: "Most of the saving of the one-step look-ahead needs no labels. It comes from a rule that was computed but not run, and that by calculation would save 5.8 times in bytes on its own."

**12. INCONSISTENT. The headline gain is given as four different numbers.**

- Line 106 (§1.4): "cut the candidates a search evaluates about 15 times".
- Line 902 (§7.2): "This pass evaluated about 16 times fewer candidates than plain search **[M]**".
- Lines 736 and 1420 (§6.4, §11.1): "14× to 18×".
- Line 1254 (§8.7): "The gain is the same under every rule, 17×".

All are within the record's range (line 7: 13.9× to 18.5×, "which the rest of this document gives as 14× to 18×"), but a reader meets four different headline numbers for one result, and the record gives the range and not "about 15".

Replacements: line 106, "cut the candidates a search evaluates 14 to 18 times, depending on the set of tasks, and its time 1.3 to 4 times"; line 902, "This pass evaluated 14 to 18 times fewer candidates than plain search, depending on the set of tasks **[M]** (§6.4)."

**13. INCONSISTENT. What halved the summed saving, and what a lost task costs.**

- Line 921 (§7.2): "In the one run that measured the cost of the fallback, counting it halved the saving summed over tasks (§6.4)."
- Line 748 (§6.4): 12.7× with plain retries, 6.6× under the reserve, "against 12.1× under the same reserve had nothing been lost".
- Line 1384 (§10, risk 13): "A lost task costs a whole plain search." and "under the reserve that halved the saving".

By §6.4 the reserve with nothing lost still gives 12.1×, so counting the fallback is not what halved the saving. The three lost answers did. And §6.4 says a lost task costs four times its plain search under the reserve, where risk 13 says one.

Replacements: line 921, "In the one run that measured it, three lost answers out of 234 halved the saving summed over tasks under this reserve, from 12.1× to 6.6× (§6.4)."; line 1384, "A lost task costs a whole plain search, and four times that under the reserve."

**14. INCONSISTENT. In which stage counts exist.**

- Line 1446 (X7): "Replay is built in Stage C; the memo and the counts are built in Stage D."
- Line 945 (§7.4): "Counts of which operators and moves appeared in accepted solutions are read from this record", that is, from the derivation space, which line 1457 puts in Stage D.
- Against these: line 1456 puts "the order and price of names" in Stage C, line 858 (§7.1) builds the price from "its share of uses in accepted solutions", and line 1439 makes "Counts of past use" arm 4 of X4, which ends Stage C.

Replacements: line 1446, "Replay is built in Stage C, and so are the counts of operators in accepted solutions, which the price of a name and arm 4 of X4 need. The memo and the counts of moves, which are read from the derivation space, are built in Stage D."; line 945, first sentence, "Counts of which operators appeared in accepted solutions are kept with the library from Stage C, and counts of moves are read from this record. Both adjust the order that the verb tables give (§6.4)."

**15. POINTER. §5.9 cites X9 for something X9 does not contain.**

- Line 633: "Its cost and its yield are rows of the derivation space, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust (experiment X9, §11.2)."

X9 (line 1448) says only "each attempt on its own budget account", and its gate is about the selective specs and analogies. X9 also belongs to Stage C, and the derivation space is built in Stage D (line 1457).

Replacement: "Each attempt runs on its own budget account (experiment X9, §11.2). Once the derivation space exists, in Stage D, the cost and the yield of each attempt are rows of it, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust **[P]**."

**16. INCONSISTENT. The probe rule is stated over labels in §7.5 and over pairs of labels everywhere else.**

- Line 977 (§7.5, rule 4): "*Probe with what programs produce, spread over the words.* The rows on which an operator is tested are the outputs of small random programs over the library, spread evenly over the labels that occur (§6.5)."
- Line 782 (§6.5): "Then spread the probes evenly over the pairs of labels that occur." The record (line 42) defines the measured rule over pairs of words. Spreading over single labels is the review's rule, not the one measured.

Replacement: "*Probe with what programs produce, spread over pairs of labels.* The rows on which an operator is tested are the outputs of small random programs over the library, spread evenly over the pairs of labels that occur (§6.5)."

**17. INCONSISTENT. "Tasks" against "true parents".**

- Line 690 (§6.2): "In a quarter of the tasks the labels left the true parent tied with other classes".
- Line 1269 (§8.7): "for a quarter of the true parents"; record, line 71: "26 of 102 and 26 of 99", where the two task sets have 119 and 115 tasks.

Replacement for line 690: "For a quarter of the true parents the labels left the true parent tied with other classes, and in about half of those ties the correction ranked the true parent first, where chance would give a little over a third."

**18. INCONSISTENT (qualifier dropped in §8.7). The first place of `(sgn x)` depends on the grid and on the kind of division.**

- Line 1285: "Once `div`, `mod`, `max`, and `min` are counted, `(sgn x)` ranks first of 1,109 candidate words, and an arbitrary predicate such as `(= x 1)` ranks 702nd."
- Record, line 92: "on a grid of −10 to 10 with floor division ... The first place depends on those choices: with truncating division `(sgn x)` ranks 4th, and on a grid of −20 to 20 it ranks 2nd."

Replacement: "Once `div`, `mod`, `max`, and `min` are counted, `(sgn x)` ranks first of 1,109 candidate words on a grid of −10 to 10 with floor division, and an arbitrary predicate such as `(= x 1)` ranks 702nd. The first place depends on those choices: with truncating division `(sgn x)` ranks 4th, and on a grid of −20 to 20 it ranks 2nd."

**19. INCONSISTENT (wording). "No run" against "no Python run".**

- Line 1420 (§11.1): "No run had the plain early-comparison control".
- Line 1236 (§8.7): "No Python run has it. In the store prototype that control cut candidates exactly as much as ordering by labels did". Line 1425, five rows below line 1420, reports the prototype's run of that control.

Replacement: "No Python run had the plain early-comparison control".

## C. Evidence tags (item 6)

**20. TAG.** Every **[M]** in §6 and §7 (lines 680, 688, 734, 742, 754, 755, 762, 896, 902, 905, 906, 908 twice, 910, 914, 944 twice, 1017) traces to the record or to §8. The one weak case is line 902, whose second sentence ("adds only a few percent") rests on a figure that is only in the record (finding 7).

**21. TAG. Proposals without [P] that read as measured or as fact.**

- Line 753 (§6.4, purpose 2): "A verb table lets a requirement pass backward through *any* operator, coarsely: the labels of the argument must be among those the table takes to the labels required of the result. The filter above is one step of this." Only the one step was measured. Replacement for the last sentence: "The filter above is one step of this, and the one step is all that was measured; passing a requirement back through several operators is proposal **[P]**."
- Line 752 (§6.4, purpose 1): "published guard search stops at guards of about four nodes" has no tag. §5.5 (line 559) carries **[L]** for the same statement. Replacement: add "**[L]** (§5.5)" after "four nodes".
- Line 1025 (§7.6): "Spent on breadth, re-validation, and ablation, hours can compound, as the audit measured: three of eight held-out tasks became solvable". The audit measured that the library made three of eight tasks solvable when used for lifting (§2.5, line 271). It did not measure hours compounding. Replacement: "That hours spent on breadth, re-validation, and ablation will compound is proposal **[P]**. The audit measured one instance of the effect it relies on: three of eight held-out tasks became solvable, in under 50,000 work, once the library was used for lifting, though three or four others became dearer (§2.5)."
- Line 949 (§7.4): "They are." answers the owner's question as a fact, and the sentence "On the store they are all facts about classes on a space, kept in one table and shared across sub-problems and jobs" is untagged; the only **[P]** in the paragraph is on its last sentence. Replacement for "They are.": "On this store they would be, and that is proposal **[P]**."
- Line 953 (§7.4): "It shows that the plumbing works." is a claim about the present kernel with no tag and no pointer. §2.6 (line 275) mentions "an offline experiment" but does not name `yield-gate` or say what it showed. Replacement: "It shows that the plumbing works **[C]** (§2.6)", and name `yield-gate` at line 275.
- In "The order of names, and their price" (line 758) the **[P]** is present and covers the right sentence. Purposes 3, 4 and 5 of line 754–756 are tagged correctly.

## D. Terms (item 4)

One place where each term is used in another sense. Terms not listed here were used consistently wherever I looked.

| Term (line of definition) | Used differently at | The other sense |
|:--|:--|:--|
| *one step from the answer* (44) | 688, 1266, 1422 | any class of the true parent's size (finding 3) |
| *quotient* (40) | 523: "Quotient \| merge rows (projection), or merge terms (a class)" | merging rows or terms, not a term on values; line 667 acknowledges it |
| *label* (40) | 819: "a human label is aligned to a word by co-occurrence counts"; 1544 | a name supplied by a person |
| *word* (40) | 720: "Your three word types", of which only 'like' is a word in the defined sense | the owner's wider sense; an 'action' is a verb table and an 'analogy' is a map |
| *verb table* (41) | 953: "A table from problem labels to the move that succeeded is a verb table for moves" | a table for a move, not for an operator and a word |
| *label filter* (42) | 1280: "it cannot skip, only reorder" | a filter that reorders (finding 10) |
| *candidate* (33) | 682: "a pool of thirteen candidate guards"; 890: "a candidate answer is replayed forward" | any proposed thing; only "candidate word" is reserved by the Terms table |
| *bank* (32) | 1199: "unary maps f drawn from a small bank of terms ... a richer bank of maps" | a pool of maps to try |
| *gain* (35) | 1445: "`:map` re-emerges with a positive gain"; 1123: "the gain depends on the grammar and the rows" | a saving in description length; the saving from dedupe |
| *dependency test* (37) | 767: "Score each candidate word by the dependency test ... the share of the uncertainty ... that the labels of the inputs remove" | a graded score, not a yes-or-no check |
| *residual* (38) | 457: "The per-row values of its leaves are the labeled residual." | the owner's phrase for what varies between contexts |
| *correction* (39) | 815: "an invertible `decode` operator that applies a correction" | the change itself, not its cost in bits |
| *split* (45) | 866: "Split the requirement the way that construct splits it."; 975: "*Split ambiguities.*" | dividing a requirement; telling two programs apart |
| *held* (47) | 1281: "the classes held 34×"; 1425, 1426 | classes kept in memory |
| *look-ahead* (48) | 1021: "a one-step look-ahead, which also drops a class of the largest stored size" | a variant that needs no firm bound on the whole answer; it is defined in place |
| *tentative pass*, *round* (50) | 904: "either pass" (finding 5); 119 and 1390: "the next round's primitives"; 1002: "a group-by per round" | the fallback as a pass; a turn of the learning loop; a step of colour refinement |
| *fallback* (50) | 856: "`(try e fallback)`" | an expression of the object language |
| *space* (30) | 583: "pruning the term space with laws already found"; 114: "A flat space buys storage economy" | the set of all terms; an embedding space |
| *Stages A to D* (54) | 892: "a handoff in four stages, from labels to corrections to the exact code" | the review's four-stage handoff, which the caveat in the Terms table does not mention; the sentence also names three things for four stages |

## E. Leftovers (item 5)

**22. LEFTOVER. Two table rows have the wrong number of cells, because of a bare `|` inside a cell.** Line 521 (§5.4): "costs log₂|fiber| bits per row" gives the row six cells under a header of four. Line 1507 (Appendix B): "A symmetry refund of −log₂|Sym| bits" gives the row four cells under a header of two. Both are also in the present `plan_v2c.md` (its lines 453 and 1394). Replacement: write `log₂\|fiber\|` and `−log₂\|Sym\|` in those two rows. Every other table row has the right number of cells.

**23. LEFTOVER. Sentences that speak of how the document or the work changed.**

- Line 1310 (§8.8, item 8): "Counts now only adjust the order that the tables give (§6.4)." Replacement: "Counts only adjust the order that the tables give (§6.4)."
- Line 1459 (§11.3): "shown so far only in the prototype, though now on the kernel's own spec rows as well (§8.5)". Replacement: "shown so far only in the prototype, on its own rows and on the kernel's spec rows (§8.5)".
- Line 1304 (§8.8, item 2): "are not part of X3's gate as it is now written". Replacement: "are not part of X3's gate".
- Line 559 (§5.5): "The prototype tested unconditional laws only. Since then, for four laws, the weakest valid guard has been picked out". Replacement: "The prototype tested unconditional laws only. In Python, for four laws, the weakest valid guard was picked out of a pool of candidate guards (§8.7)."
- Line 3 and line 7 speak of revisions, but they are the front matter that points to `revision-notes.md`, and I take them as intended.

**24. LEFTOVER. Words the brief asked about.** "Four geometries", "retrieval index" and "the kernel can choose" occur nowhere. "Signature" survives at line 91 ("That table is a type signature the kernel has learned for the operator") and three times at line 732 ("a refined signature that the kernel has inferred"; "the signatures are inferred from samples"). Both are the type-system comparison and may be intended. If the word is to go, line 91 can read: "That table is a small type system the kernel has learned for the operator." The other occurrences (lines 191, 243, 270, 538, 1328, and the published name "Property signatures" at line 1538) mean an ordinary type signature. "Retrieval" survives at line 1382 (risk 11): "The retrieval measurement of §8.6", a name §8.6 does not use. Replacement: "The comparison of problems by their property sets in §8.6 is not repeated on the kernel's tasks in any experiment of §11."

**25. LEFTOVER. Appendix D.** Line 1580 lists the independent checks and does not list this one (`factcheck3-final.md`); line 1585 lists `apply-*.md`, which are not yet in `plan_v2c_audit/reports/` (finding 6). Appendix B, line 1518, sends the reader to "§7.2 for the argument and the caution"; §7.2 (line 888) gives the argument, and the nearest thing to a caution is its last sentence, that the aligner "should be built as" a search for a map.

No placeholder was found. Every sentence that announces a number of things gives that number (five limits and five purposes in §6.4, four steps and four observations in §6.5, four uses in §7.4, four rules in §7.5, three rules in §7.6, five qualifications and three smaller results in §8.7, six arms in X4, three working rules in §11.3), with the one exception noted for line 892 in the table of terms. Every heading in the listed sections has under it what it names.

## F. Clean

- **Numbers (item 1).** Apart from findings 2, 11 and 12, every figure I checked in §1.3, §1.4, §1.6, §5.9, §6.1 to §6.8, §7.2, §7.4 to §7.6, §8.7, §8.8, §10 and §11.1 to §11.3 that concerns words, labels, verb tables, near misses, probes, the vocabulary or memory is in the record with the same value, the same task set and the same instrument. That includes the whole of the two tables of §8.7, the 234-task run (16×, 12.7×, 6.6×, 12.1×), the probe figures (0 in 1,700 runs over 700 tasks, 12, 5, about 5 per 1,000), the vocabulary figures (13.0×, 15.3×, 15.8×), the memory figures (8.5× to 26×, 1.5×, 1.0 to 2.1), the 41–43%, the 43–47%, and the counts of the one routine (30, 9 and 18 lines, 92.3%).
- **The example of §6.1** (line 659: 16 bits and 29 bits) agrees with the integer code of §8.5 (line 1157) and with the formula in `verify-handoff.md` (line 9).
- **Never together.** That the vocabulary procedure and the probe rule were not run together is said the same way in all seven places (lines 106, 771, 1283, 1299, 1312, 1383, 1421), and X4 (line 1443) is named as the first joint run.
- **Memory.** "Two situations" is said consistently at lines 747, 1021, 1122, 1308, 1378 and 1426, and "two or three sizes" (line 1021) is stated as arithmetic on a condition that "was not measured".
- **Labels and corrections.** "Nearly half", "none further out", "never a class on the path", and "3 of the 234" agree at lines 688, 1266 and 1422.
- **Pass and round.** Apart from line 904, "pass" and "round" are used as the Terms table defines them, including "every round of every pass" at line 1443.
- **Other pointers.** The pointers I followed out of the listed sections to §2.3, §2.4, §2.5, §2.6, §2.7, §2.8, §4.1, §4.5, §4.6, §5.2 to §5.6, §5.8, §7.1, §7.3, §8.1 to §8.6, §9, and to Appendices B and D say what the pointing sentence promises, apart from findings 6, 7 and 15. In particular "the third limit of §6.4" (line 908), "rule 4 of §7.5" (lines 1309 and 1443), "§8.8, item 2" (line 1434), "risk 14 of §10" (lines 1279 and 1311), "§5.9, first consequence" (line 1448) and "two paragraphs below" (line 684) are all right.
