#!/usr/bin/env python3
"""Apply the findings of reports/factcheck3-final.md to the section files and to the full record.
Every patch is an exact-match replacement; a patch that does not match the expected number of times is
reported and not applied. A log is written to reports/apply-final.md.
usage: fixfinal2.py [dry]"""
import glob, os, sys
R = '/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/'
dry = len(sys.argv) > 1 and sys.argv[1] == 'dry'
files = {p: open(p).read() for p in sorted(glob.glob(R + 'sections/*.md'))}
REC = R + 'measurements-words.md'
rec = {REC: open(REC).read()}
log, fails = [], 0

def patch(finding, old, new, store=files, count=1, note=''):
    global fails
    n = sum(t.count(old) for t in store.values())
    where = [os.path.basename(p) for p, t in store.items() if old in t]
    if n != count:
        fails += 1
        log.append(f"- finding {finding}: NOT APPLIED, expected {count} match(es) and found {n}: `{old[:70]}`")
        return
    for p in store:
        if old in store[p]:
            store[p] = store[p].replace(old, new)
    log.append(f"- finding {finding}: applied in {', '.join(where)}{'; ' + note if note else ''}")

S, M = files, rec

# ---------------------------------------------------------------- finding 1: the guard qualifier
patch(1, "With a size bound that is raised round by round the loss did not occur: in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. §7.2 uses the second arrangement.",
      "With a size bound that is raised round by round, the branches were not lost: in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test asked only whether the two branches were kept. It did not ask whether the guard was kept as well, or whether the conditional was then put together. §7.2 uses the second arrangement.")
patch(1, "With rounds of increasing bound the loss did not occur, because both branches of the conditional are evaluated and kept one or two rounds later. The third limit of §6.4 gives both measurements **[M]**. So the check lives inside the tentative pass, and the rounds are what let a near miss through.",
      "With rounds of increasing bound, in Python, both branches of the conditional were evaluated and kept one or two rounds later. That test did not ask whether the guard was kept as well. The third limit of §6.4 gives both measurements **[M]**. So the check lives inside the tentative pass, and the rounds are what should let a near miss through. Whether they do so inside the kernel, with the guard included, is not known (§10, risk 14).")
patch(1, "Rounds of increasing bound let the near miss through in Python (§8.7). Whether they do so inside the kernel is not known, and that is risk 14 of §10.",
      "With rounds of increasing bound, in Python, both branches of every conditional built for the test were kept (§8.7). Whether the guard was kept as well was not asked. Whether the rounds let the whole near miss through inside the kernel is not known, and that is risk 14 of §10.")
patch(1, "With a size bound raised round by round, no: Python kept both branches of all 120 |",
      "With a size bound raised round by round, the branches were not hidden: Python kept both branches of all 120. Whether the guard is kept as well was not asked |")
patch(1, "kept both branches of all 120 conditionals built for the test in Python (§8.7). Which of the two the kernel's tentative pass resembles is not known",
      "kept both branches of all 120 conditionals built for the test in Python; that test did not ask whether the guard was kept (§8.7). Which of the two the kernel's tentative pass resembles is not known",
      note='risk 14 of §10, which the report did not list but which states the same result')

# ---------------------------------------------------------------- findings 1 and 10: the two prototype bullets of §8.7
patch('1, 10', "- *A filter applied strictly at one size destroys guard splits, and rounds of increasing bound did not.* A near miss fails the labels on exactly the rows it gets wrong. In the prototype a filter applied at the one size where the near miss sits lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted. In Python, with a size bound raised round by round, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. Whether the rounds do the same inside the kernel is not known (§10, risk 14).",
      "- *A filter applied strictly at one size destroys guard splits, and with rounds of increasing bound the branches were kept.* A near miss fails the labels on exactly the rows it gets wrong. In the prototype a filter that skips candidates was applied at the one size where the near miss sits. That size was handed to it, and the search stopped there. It lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted. In Python, with a size bound raised round by round, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test asked whether both branches were kept. It did not ask whether the guard was kept, or whether the conditional was then put together. Whether the rounds save the whole conditional inside the kernel is not known (§10, risk 14).")
patch(10, "The prototype keeps one bank across sizes and does not restart, so it cannot skip, only reorder. Reordering cut candidates 2.73× over its 15 tasks.",
      "When the size of the answer is not handed over, the prototype cannot skip. It keeps one bank across sizes and does not restart, so a candidate skipped at one size would be missing at the next, and the labels can only reorder the candidates of a size. Reordering cut candidates 2.73× over its 15 tasks.")

# ---------------------------------------------------------------- finding 2: the arrangement of 2.4 to 3.0 times
patch(2, "On tasks built to contain such a step, this proposal evaluated 2.4 to 3.0 times fewer candidates than the label filter alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate **[M]**.",
      "On tasks built to contain such a step, the check was first run as the outside review arranged it, only on the classes that the label filter keeps. In that arrangement the search evaluated 2.4 to 3.0 times fewer candidates than the label-filtered search alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate **[M]**. Run on every candidate that is evaluated, which is the arrangement of this step, the check halved the candidates again, as the paragraph after this list reports.")
patch(2, "Where a near miss exists, yes: 2.4 to 3.0 times fewer candidates than the label filter alone, on tasks built to contain a constant offset or scale. On ordinary tasks it added little |",
      "Where a near miss exists, yes. On tasks built to contain a constant offset or scale, a check run only on the classes the label filter keeps evaluated 2.4 to 3.0 times fewer candidates than the label filter alone, and a check run on every evaluated candidate halved the candidates again. On ordinary tasks it added little |")

# ---------------------------------------------------------------- finding 3: one step from the answer
patch(3, "| *one step from the answer*, *true parent* | A class is one step from the answer when one more operator applied to it gives the target. The true parent is the class of that kind from which the answer is in fact built (§6.2). |",
      "| *one step from the answer*, *true parent* | The true parent is the class from which the answer is in fact built by one more operator. A class is one step from the answer when it has the true parent's size, whether or not any operator takes it to the target (§6.2). |")
OLD3 = "Call a class *one step from the answer* when applying one more operator to it gives the target, and call the class of that kind from which the answer is in fact built the *true parent*."
NEW3 = "Call the class from which the answer is in fact built by one more operator the *true parent*, and call every class of the true parent's size a class *one step from the answer*, whether or not any operator takes it to the target."
patch(3, OLD3, NEW3)
patch(3, OLD3, NEW3, store=M, note='the same definition in the record')
patch(3, "- *Labels act on the last step.* Among the classes one step from the answer, the tables rule out 43–47%. Among classes two or more steps away, they rule out none.",
      "- *Labels act on the last step.* A class one step from the answer is any class of the true parent's size (§6.2). Among these classes the tables rule out 43–47%. Among classes two or more steps away, they rule out none.")

# ---------------------------------------------------------------- finding 4: what the tables rule out below the bound
patch(4, "For smaller candidates the tables tried so far ruled out nothing (§6.2), so in practice the test acts on the last step of each round.",
      "For a candidate one size below the bound, the question is whether one more operator can take its result to the target's labels, and the tables tried so far ruled out 43–47% of the classes of that size. For smaller candidates they ruled out nothing (§6.2). So in practice the test acts on the last step of each round and on the size just below it. Applying it throughout the enumeration gave twice the gain of applying it at the final size alone (§8.7).")

# ---------------------------------------------------------------- finding 5: either pass
patch(5, "Each candidate that either pass evaluates is compared with the target.",
      "Each candidate that the tentative pass evaluates is compared with the target.")

# ---------------------------------------------------------------- findings 6 and 7: the pointer to the full record
patch('6, 7', "This section gives the main results. The full record, with every figure quoted elsewhere in this plan, the arrangement each was measured in, and the script behind it, is `plan_v2c_audit/measurements-words.md`.",
      "This section gives the main results. The full record is `plan_v2c_audit/measurements-words.md`. It gives the figures quoted elsewhere in this plan and the arrangement each was measured in. So where another section cites §8.7 for a figure that is not given below, the figure is in that record. The commands and logs behind each figure are in the reports that Appendix D lists for §8.7.",
      note='one sentence in §8.7 makes the citations of finding 7 good, instead of a change to each of them')
patch(6, "| `verify-proto-labels.md` | the label filter and the look-ahead inside the store prototype (§8.7) | `round3/l1-proto/` |",
      "| `verify-proto-labels.md` | the label filter and the look-ahead inside the store prototype (§8.7) | `round3/l1-proto/` |\n| `measurements-words.md`, which is in `plan_v2c_audit/` and not in `reports/` | the full record of the measurements that §8.7 gives in short | the folders of the six reports above |")
patch(7, "with the library in its listing order the first row is 13.9× and 16.7×. Five qualifications apply.",
      "with the library in its listing order the first row is 13.9× and 16.7×. So the gain of the six hand-listed words runs from 13.9× to 18.5× with the set of tasks and the order of the operators, and the rest of this plan gives it as 14× to 18×. Five qualifications apply.",
      note='the range is now stated in §8.7 itself')
patch(7, "Without this step the first six words are all versions of the length.",
      "Without this step, in an earlier and smaller pool of candidate words, the fifteen best-scoring words were all versions of the length.")
patch(7, "Most of the words with many labels are two-part words.",
      "The six words chosen were all two-part words, and with single terms only the gain was 10.4×.")
patch(7, "The review first proposed to add to the tables whatever a fallback search discovers, and then dropped the idea.",
      "The review first proposed to add to the tables whatever a fallback search discovers, and then dropped the idea (its Appendix B.2).")
patch(7, "With the filter on, the ordering of step 1 adds only a few percent.",
      "With the filter on, the ordering of step 1 changed the totals by only 3 to 5 percent.")
patch(7, "and one figure of §8.7 comes from one of those: that the review's result of no misses held for 7 of 20 probe seeds.",
      "and one figure of the full record behind §8.7 comes from one of those: that the review's result of no misses held for 7 of 20 probe seeds.")
# the three items the record lacked
patch(7, "One answer of 60 was lost. A second probe seed gave 14.3× with six words.",
      "One answer of 60 was lost. A second probe seed gave 14.3× with six words. The six words chosen were all two-part words, and with single terms only the gain was 10.4×, with no answer lost. Without the step that skips repetition, in the earlier and smaller pool of `verify-quotients.md`, the fifteen best-scoring words were all versions of the length.",
      store=M, note='two items added to the record')
patch(7, "- *Feeding back the transitions of tasks solved by the fallback* removed nothing in the 1,700 runs once the probes were good, because nothing was lost there.",
      "- *Feeding back the transitions of tasks solved by the fallback* is an idea the review first proposed and then dropped (its Appendix B.2). It removed nothing in the 1,700 runs once the probes were good, because nothing was lost there.",
      store=M, note='one item added to the record')

# ---------------------------------------------------------------- finding 8: the rule for two-argument operators
patch(8, "Three further rules, each measured:",
      "Three further rules follow. The second and the third rest on measurements. The first was measured as well, but the measurement did not decide the matter, and the rule is adopted on the argument given with it.")
patch(8, "A table keyed on labels is a claim about every value that carries the label, and holding one argument fixed samples only a few of them.",
      "A table keyed on labels is a claim about every value that carries the label, and holding one argument fixed samples only a few of them. The review's evidence for the rule was that tables built from slices, in which one argument is held at a few fixed values, made 287 false rejections for `div` and 422 for `mod`. That depended on the slices it chose. Most random choices of slice rejected nothing, and at an equal budget random probes of both arguments rejected more true results than random slices did.")

# ---------------------------------------------------------------- finding 9: which setting is built
patch(9, "It is the version to build, with the setting still to be decided.",
      "It is the version to build, at the middle setting for now, because that is the setting that lost no answer. The setting remains a knob, to be tried again when the procedure is run in the kernel.")
patch(9, "The middle setting of that second version is the one §6.5 proposes to build.",
      "The middle setting of that second version is the one §6.5 proposes to build for now, because it is the setting that lost no answer.", store=M)

# ---------------------------------------------------------------- finding 11: the memory figures and their arrangements
patch(11, "The second is the look-ahead of §7.2, once a held answer gives a firm bound: in the store prototype it cut the classes held by ten times or more on lifted tasks.",
      "The second is the look-ahead of §7.2, once there is a firm bound on the size of the whole answer. In the store prototype it cut the classes stored 34 times on the seven guarded runs, where a held answer gave the bound, and ten times or more on three lifted tasks, where the answer's size was handed over.")
patch(11, "One further saving needs no labels and was computed but not run.",
      "Most of the saving of the one-step look-ahead needs no labels. It comes from a rule that was computed but not run, and that by calculation would save 5.8 times in bytes on its own, with labels then adding 1.3 to 2.5 times.")
patch(11, "and ten times fewer classes held or more with the look-ahead once a held answer gives a firm bound. Little elsewhere |",
      "and 34× fewer classes stored with the look-ahead on the seven guarded runs, where a held answer gives a firm bound. Little elsewhere |")

# ---------------------------------------------------------------- finding 12: one headline gain
patch(12, "cut the candidates a search evaluates about 15 times and its time 1.3 to 4 times",
      "cut the candidates a search evaluates 14 to 18 times, depending on the set of tasks, and its time 1.3 to 4 times")
patch(12, "This pass evaluated about 16 times fewer candidates than plain search **[M]**; the figure varies with the set of tasks (§6.4).",
      "This pass evaluated 14 to 18 times fewer candidates than plain search, depending on the set of tasks **[M]** (§6.4).")

# ---------------------------------------------------------------- finding 13: what halved the summed saving
patch(13, "In the one run that measured the cost of the fallback, counting it halved the saving summed over tasks (§6.4).",
      "In the one run that measured it, three lost answers out of 234 halved the saving summed over tasks under this reserve, from 12.1× to 6.6× (§6.4).")
patch(13, "A lost task costs a whole plain search. In the one run where this was measured, 3 of 234 answers were lost, two of them on larger tasks, and under the reserve that halved the saving summed over tasks (§6.4)",
      "A lost task costs a whole plain search, and four times that under the reserve. In the one run where this was measured, 3 of 234 answers were lost, two of them on larger tasks, and under the reserve that halved the saving summed over tasks, from 12.1× to 6.6× (§6.4)")

# ---------------------------------------------------------------- finding 14: in which stage counts exist
patch(14, "Replay is built in Stage C; the memo and the counts are built in Stage D.",
      "Replay is built in Stage C, and so are the counts of operators in accepted solutions, which the price of a name and arm 4 of X4 need. The memo and the counts of moves, which are read from the derivation space, are built in Stage D.")
patch(14, "Counts of which operators and moves appeared in accepted solutions are read from this record, and they adjust the order that the verb tables give (§6.4).",
      "Counts of which operators appeared in accepted solutions are kept with the library from Stage C, and counts of moves are read from this record. Both adjust the order that the verb tables give (§6.4).")

# ---------------------------------------------------------------- finding 15: what X9 contains
patch(15, "Its cost and its yield are rows of the derivation space, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust (experiment X9, §11.2).",
      "Experiment X9 tests this arrangement (§11.2). Once the derivation space exists, in Stage D, the cost and the yield of each attempt are rows of it, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust **[P]**.")

# ---------------------------------------------------------------- finding 16: pairs of labels
patch(16, "4. *Probe with what programs produce, spread over the words.* The rows on which an operator is tested are the outputs of small random programs over the library, spread evenly over the labels that occur (§6.5).",
      "4. *Probe with what programs produce, spread over pairs of labels.* The rows on which an operator is tested are the outputs of small random programs over the library, spread evenly over the pairs of labels that occur (§6.5).")

# ---------------------------------------------------------------- finding 17: true parents, not tasks
patch(17, "In a quarter of the tasks the labels left the true parent tied with other classes",
      "For a quarter of the true parents the labels left the true parent tied with other classes")

# ---------------------------------------------------------------- finding 18: the qualifier on (sgn x)
patch(18, "`(sgn x)` ranks first of 1,109 candidate words, and an arbitrary predicate such as `(= x 1)` ranks 702nd.",
      "`(sgn x)` ranks first of 1,109 candidate words on a grid of −10 to 10 with floor division, and an arbitrary predicate such as `(= x 1)` ranks 702nd. The first place depends on those choices: with truncating division `(sgn x)` ranks 4th, and on a grid of −20 to 20 it ranks 2nd.")

# ---------------------------------------------------------------- finding 19
patch(19, "No run had the plain early-comparison control", "No Python run had the plain early-comparison control")

# ---------------------------------------------------------------- finding 21: tags
patch(21, "The filter above is one step of this.",
      "The filter above is one step of this, and that one step is all that was measured. Passing a requirement back through several operators is proposal **[P]**.")
patch(21, "because published guard search stops at guards of about four nodes.",
      "because published guard search stops at guards of about four nodes **[L]** (§5.5).")
patch(21, "Spent on breadth, re-validation, and ablation, hours can compound, as the audit measured: three of eight held-out tasks became solvable,",
      "That hours spent on breadth, re-validation, and ablation will compound is proposal **[P]**. The audit measured one instance of the effect it relies on: three of eight held-out tasks became solvable,")
patch(21, "are too. They are. The pruner's fact", "are too. On this store they would be, and that is proposal **[P]**. The pruner's fact")
patch(21, "It shows that the plumbing works.", "It shows that the plumbing works **[C]** (§2.6).")
patch(21, "But nothing reads that frame except a test and an offline experiment **[C]**.",
      "But nothing reads that frame except a test and an offline experiment, `yield-gate` (§7.4) **[C]**.")

# ---------------------------------------------------------------- finding 22: bare pipes inside table cells
patch(22, "costs log₂|fiber| bits per row", "costs log₂\\|fiber\\| bits per row")
patch(22, "A symmetry refund of −log₂|Sym| bits", "A symmetry refund of −log₂\\|Sym\\| bits")

# ---------------------------------------------------------------- finding 23: sentences about how the document changed
patch(23, "Counts now only adjust the order that the tables give (§6.4).", "Counts only adjust the order that the tables give (§6.4).")
patch(23, "shown so far only in the prototype, though now on the kernel's own spec rows as well (§8.5)",
      "shown so far only in the prototype, on its own rows and on the kernel's spec rows (§8.5)")
patch(23, "are not part of X3's gate as it is now written.", "are not part of X3's gate.")
patch(23, "Since then, for four laws, the weakest valid guard has been picked out of a pool of candidate guards, in Python (§8.7).",
      "In Python, for four laws, the weakest valid guard was picked out of a pool of candidate guards (§8.7).")

# ---------------------------------------------------------------- finding 24
patch(24, "The retrieval measurement of §8.6 is not repeated on the kernel's tasks in any experiment of §11.",
      "The comparison of problems by their property sets in §8.6 is not repeated on the kernel's tasks in any experiment of §11.")

# ---------------------------------------------------------------- finding 25: Appendix D and Appendix B
patch(25, "`factcheck3-A.md`, `factcheck3-B.md`, `factcheck3-C.md` | independent checks",
      "`factcheck3-A.md`, `factcheck3-B.md`, `factcheck3-C.md`, `factcheck3-final.md` | independent checks")
patch(25, "see §7.2 for the argument and the caution", "see §7.2 for the argument")

# ---------------------------------------------------------------- section D of the report: a defined term used in a second sense
patch('D', "The outside review proposed this as a handoff in four stages, from labels to corrections to the exact code.",
      "The outside review proposed this as a handoff in four parts: verb tables consulted before enumeration, verb tables consulted during it, corrections on the classes that survive, and acceptance by the exact code.",
      note='"stages" is kept for Stages A to D')
patch('D', "become the next round's primitives on the same store", "become primitives for the next turn of the loop, on the same store", count=2,
      note='"round" is kept for the rounds of a search')
patch('D', "polynomial; a group-by per round", "polynomial; one group-by for each step of the refinement")
patch('D', "drawn from a small bank of terms", "drawn from a small pool of terms", note='"bank" is kept for the bank of classes')
patch('D', "with a richer bank of maps", "with a richer pool of maps")
patch('D', "pruning the term space with laws already found", "pruning the set of all terms with laws already found", note='"space" is kept for a space of rows')
patch('D', "Pruning the term space with laws already found (Ruler)", "Pruning the set of all terms with laws already found (Ruler)")
patch('D', "*Score each candidate word by the dependency test.*", "*Score each candidate word by a graded form of the dependency test.*")
patch('D', "a human label is aligned to a word by co-occurrence counts", "a name that a person supplies is aligned to a word by co-occurrence counts",
      note='"label" is kept for the values of a word')
patch('D', "the gain depends on the grammar and the rows", "what dedupe saves depends on the grammar and the rows", note='"gain" is kept for the ratio of candidates')
patch('D', "`:map` re-emerges with a positive gain, as it does now", "`:map` re-emerges with a positive saving in description length, as it does now")
patch('D', "and the classes held 34×, and changed no answer", "and the classes stored 34×, and changed no answer", note='"held" is kept for a held answer')
patch('D', "With the answer's size given, the classes held fell from", "With the answer's size given, the classes stored fell from")
patch('D', "36× fewer candidates and 34× fewer classes held, with no answer changed", "36× fewer candidates and 34× fewer classes stored, with no answer changed")
patch('D', "the classes held", "the classes stored", store=M, count=rec[REC].count("the classes held"), note='the record, every occurrence')

out = ["# Applying the final check (`factcheck3-final.md`) to plan v2c", "",
       "One line for each patch, by the number of the finding in `factcheck3-final.md`. Findings 20 and the clean list of section F asked for no change. "
       "Of the terms in section D, those that are ordinary uses of a common word (candidate, residual, correction, split, fallback, quotient as a verb) were left as they are. "
       "Finding 24's other point, the word \"signature\" in the comparison with type systems, was left as intended.", ""] + log
if not dry:
    for p, t in files.items():
        open(p, 'w').write(t)
    open(REC, 'w').write(rec[REC])
    open(R + 'reports/apply-final.md', 'w').write('\n'.join(out) + '\n')
print('\n'.join(l for l in log if 'NOT APPLIED' in l))
print(f"{len(log)} patches, {fails} not applied{' (dry run, nothing written)' if dry else ''}")
