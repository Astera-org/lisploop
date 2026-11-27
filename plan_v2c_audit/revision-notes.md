# Revision notes for `plan_v2c.md`

`plan_v2c.md` states the current design. This file is the record of how it got there: what each revision changed, the answers to your margin notes, and what was taken from the outside review (`plan_v2c_audit.md`) and what was not. It was Appendices C and G of the plan until 26 November, and was moved here so that the plan itself reads as a plan.

Section numbers in Parts 2 and 3 are those of the plan at the time each part was written. The plan's sections 6 and 8 were renumbered on 26 November; Part 1 gives the mapping.

| Part | Date | Contents |
|:--|:--|:--|
| 1 | 26 November 2026 | The third revision: the outside review's unified treatment of heuristics, vocabulary and residuals, verified and integrated; a pass for clarity and length |
| 2 | 25 November 2026 | The second revision: your margin notes on the plan and on the review, answered; the ledger of what was taken from the review's first two sections (formerly Appendix G) |
| 3 | 24 November 2026 | Your margin notes on `plan_v2b.md`, and how each was used (formerly Appendix C) |

## Part 1. The revision of 26 November 2026

### 1.1 What was asked

You had worked with the outside reviewer on the stream of heuristics, vocabulary, and residuals, and the result was §2.5 and Appendices A and B of `plan_v2c_audit.md`. You asked that it be folded into the plan, with its claims verified first, and that the plan then be gone over for consistency, clarity, and concision. Part-way through you added: "Don't trade clarity for concision! You have a tendency toward telegraphic text already."

### 1.2 What changed in the plan

**Section 6 is reorganized around the review's idea.** Geometry is now presented as one question: what does one column cost, given others? The question is asked at two resolutions, of the values and of coarse labels of the values. It is answered by three computations: equality, counting over groups, and correction. The former §6.2 (pricing), §6.3 (guiding search), and §6.6 (language) are parts of that one picture instead of three mechanisms.

**Section 7.2 gains the order in which a search consults the store,** which is the review's four-stage handoff as corrected by measurement. Sections 7.4 to 7.6 are brought into line: what reflection reads, the rules for the kernel's own experiments, and the rules for memory.

**Section 8 states findings instead of a ledger.** The claim-by-claim comparison with the review is in this file. §8.7 holds every measurement about words, tables, near misses, and memory.

**Three appendices left the plan.** Two came to this file: the old Appendix C (your notes on `plan_v2b.md`) and the old Appendix G (your notes on the plan and on the review, and the ledger of the review's first two sections). The third, the old Appendix B (locations of ideas in the trail), was folded into §2.8, and at least four of its 24 rows are no longer anywhere in the plan.

**Sections 2, 4, 5, 7.1, 7.3, 9 and the appendices were revised for clarity** from a first-time reader's review (`reports/clarity-review.md`): 56 passages rewritten, internal names defined where they first appear, eight words that had two meanings given one each, and a table of terms added at the front. The parts written in this revision were then reviewed in the same way (`reports/clarity-review-new.md`), and the whole was checked against the logs by three independent readers (`reports/factcheck3-A.md`, `-B.md`, and `-C.md`). Those checks found three more words still used in two senses: "word", "Stage A", and "signature". Each now has one. A word is a quotient that the kernel keeps in its vocabulary, and the values it can take are its labels. The present kernel's own "Stage A" is called its first search phase. A task's set of properties is called its property set, and "signature" is kept for type signatures.

Section numbers changed as follows.

| Before 26 November | Now |
|:--|:--|
| §6.1 One definition | §6.1 One question |
| (new) | §6.2 Two resolutions, two outcomes |
| §6.2 Pricing residuals | §6.3 |
| §6.3 Guiding search; §6.6 Language | §6.4 Words and verb tables; §6.5 Where they come from; §6.7 Language with people, and precedent |
| §6.4 Spaces; §6.5 Values with geometry | §6.6 |
| §6.7 What remains open | §6.8 |
| §8.5 What the prototype changes | §8.8 |
| §8.6 The review's re-runs | §8.5 |
| §8.7 Search across spaces | §8.6 |
| §8.8 Words and verb tables | §8.7 |
| Appendix D, E, F | Appendix B, C, D |
| Appendix C, G | this file |
| Appendix B | §2.8 |

**Detail moved here from §4.5 of the plan.** The paper you cited in the margin, arXiv 2611.17309, fits its model in 42 ms for Sudoku and 132 ms for mazes. One hand-set value of its weights already solves every Sudoku puzzle, and three every maze. Its search moves run in Triton kernels with one GPU warp per chain, at a mean of 2.0 × 10⁹ FLOPs per Sudoku, on an H200. Part 2 has the full answer to your note on it.

### 1.3 The review's §2.5 and Appendix B, claim by claim

Each claim that has a script behind it was first run with the reviewer's own scripts. These print the numbers the review quotes, with one thing to note: for the three polynomial targets, one of the two scripts prints memory gains of 4.9×, 5.5×, and 6.0× under an earlier rule, and the other prints the 9.4×, 22.6×, and 22.9× that the review quotes. The claims of §2.5.1 and §2.5.2 and both examples of Appendix B.3 have no script. They are argued and not measured, so there was nothing of the reviewer's to run. The scripts were then read, to separate what was computed from what was built in. Then each claim was tested independently, in the form it would have to take inside the kernel. Reports: `verify-words.md`, `verify-probes.md`, `verify-memory.md`, `verify-handoff.md`, `verify-proto-labels.md`.

| The review's claim | Verdict | What the plan does | Where |
|:--|:--|:--|:--|
| §2.5.1: laws, inverses, computed residuals, exact congruences, and verb tables are one store primitive, a group-by that measures what one column leaves undetermined in another | holds for three of the five, and for one of those three only in its first step | Adopted as one *question* answered by three computations: equality, counting over groups, and correction. One 30-line counting routine gives exact facts about labels and verb tables with nothing added. For an inverse it supplies the first step, the dependency test; the guard and the term are small searches on top, of 9 and 18 further lines. A law is equality of columns, which is a different computation. A near miss is not a group-by: on a task's few rows the group-by returned zero for a near miss and for a far-off term whose values are all different, alike, in all of 2,000 trials. It does tell apart a column whose values repeat. A near miss is measured by correction | §6.1, §6.2, §8.7 |
| §2.5.1: tables are learned by an agenda between searches and only read during one | holds, with a cost | Adopted. A target with a label no table mentions occurred in none of 234 tasks. The failure that did occur is a transition missing from a table. At 2,000 random probes per operator it lost 3 of the 234 answers, and under the three-to-one reserve those three cut the saving summed over tasks from 12.1× to 6.6×. That is why the fallback stays | §7.2, §8.7 |
| §2.5.1: words must keep several labels; Boolean properties are not enough | holds in search | Adopted. Limiting words to 2, 4, 6, 8 labels gave 4.8×, 8.4×, 12.2×, 13.0×. The review's argument from the score does not hold in general: composite moduli coarsen to parity at a score of 1, and on sequences the best Boolean out-scores the many-label word | §6.5 |
| §2.5.2: a handoff in four stages: labels before and during enumeration, computed residuals at the horizon among the classes the labels let through, exact description length at acceptance | holds in outline; two parts corrected, one step added | Adopted as four steps. Labels do not look ahead: they ruled out 43–47% of classes one step from the answer and none further. The near-miss check ended up inside the tentative, label-filtered pass, on every candidate that pass evaluates, including those the labels then decline to keep. The review ran it only on the classes the filter keeps, and checking every evaluated candidate halved the candidates needed. The plain search is the fallback for wrong table entries. A filter applied strictly at the one size where the near miss sits does discard it: in the store prototype such a filter lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted. With a size bound raised round by round, in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test did not ask whether the guard was kept as well. The added step is that a held answer bounds the rest of the search | §6.2, §6.4, §7.2, §8.7 |
| Appendix B.3: a wrong first step is closer to the target (8) than the right one (12), so a distance to the target "is blind to multi-step plans" | true of its one row | Not used as evidence. On eight rows, by the review's own measure (the sum of absolute differences) the comparison reversed in 2 of 3 seeds; by the kernel's correction code the wrong step stayed the cheaper one in 2 of 3. Measured over the 179 tasks where it could be measured, the class on the path to the answer ranks well above chance one step out and a little above chance further out. So corrections are a weak guide far from the answer and not a misleading one | §6.2, §8.7 |
| §2.5.2: "residual bucket regularity" breaks ties among near misses | holds for one case | Adopted only as the exact test that a residual is a constant. As a ranking by labels it helped for constant offsets (56 of 64 against 22–29), moved the true parent down more often than up on ordinary tasks, and on conditionals only moved the right branch down | §6.3, §8.7 |
| §2.5.3: test reachability before a class enters the dedupe table; 9.4× to 22.9× less memory on ring polynomials | holds | Adopted, with the rule for an unknown answer size added: restart at each bound. The earlier reproduction already counted this way, so the plan's earlier figures stand. In the reviewer's script the answer's size is given | §7.6, §8.7 |
| §2.5.3: 2.1× less memory on the sequence library | partly | 2.4× in classes and 1.5× in bytes without a look-ahead. The reviewer's figure used a look-ahead, 41 of the 61 operators, and a given answer size | §7.6, §8.7 |
| §2.5.3: no memory saving on lifted tasks "whenever `at(xs, idx)` sits at or inside the term" | true only by construction of its test | Not adopted. The script filters only the final size, which is never stored, and gives `at` no table. With every size filtered and a table for `at`, stored classes fell 1.4× to 5.7× in Python. In the store prototype, once a firm size bound existed, a look-ahead cut the classes held on lifted tasks by ten times or more. The two instruments count plain search's classes differently, so the two figures are not comparable | `reports/verify-memory.md`; §7.6, §8.7 |
| §2.5.3: on lifted tasks, 5.3× to 7.6× fewer evaluations when arithmetic is outermost and none when `at` is | depends on operator order | Not adopted as stated. In the store prototype the same tasks gave 2.5× and 6.1×, and the "none" cases gave 17× and 22×; moving `at` in the operator list reverses them. A plain early comparison with the target does as well | §8.7 |
| §2.5.4 (1): "*Stratify by current words*" gives no misses in 200 tasks | its test does not show it | Adopted in a different form. The reviewer's probes were random lists plus transforms chosen by hand for the words under test, and gave no misses in 7 of 20 probe seeds. A rule with no hand knowledge, probes drawn as small programs produce them and spread over pairs of labels, lost none in 1,700 runs at 1,000 probes per operator or more. Its tables are still not sound: on streams of 4,000 tasks they met a wrong entry on about 5 tasks per 1,000 at 1,000 probes | §6.5, §7.5, §8.7 |
| §2.5.4 (2): grow the grammar of candidate words from the library | the mechanism does not reproduce | Not adopted as a source of gain: 13.0× with the library's operators in the grammar, 12.8× without, and 10.3× with the review's fold forms added. Choosing the words again as the library grows is kept | §6.5 |
| §2.5.4 (3): three small rules choose the vocabulary; they picked six named words worth 4.5× | the rules hold; the result was built in | The rules are adopted, and are close to what the earlier reproduction already did. The reported choice was among 24 hand-written candidates that contained the answers, and the six words are typed into the script that measures them. From an enumerated pool of 95,732 candidate words the rules give 13.0× with six words and 15.3× with ten, against 15.8× by hand. That is a procedure with no word listed by hand, run in Python on one library, with thresholds set by hand, and never together with the probe rule | §6.5, §8.7 |
| §2.5.4 (4): build two-argument tables from joint probes, not from slices | holds as a rule; its evidence is weaker than it looks | Adopted, on the argument and not on the measurement. The counts reproduce exactly: 287 and 422 false rejections out of 1,476 checks. The slices tested were a bad case, and most random slices reject nothing. At an equal budget, random joint probes rejected more than random slices did | §6.5, §7.5, §8.7 |
| Appendix B.2: online feedback and merged quotients are unnecessary | holds for merged words; holds for feedback on the tasks searched | Both left out of the first version. Merged words still lost answers at ten times the probes. Feedback removed nothing in the 1,700 runs once the probes were good. On streams of 4,000 tasks it cut the rate of wrong entries met three- to fourfold, so it is a cheap thing to add later | §6.5, §8.7 |
| Appendix B.1: the review's corrections to its own earlier figures | consistent with the plan | Nothing to do | |
| Appendix B.3: quotients as a generalization of Fourier characters and projective quotients | not tested | Not taken into the plan. It makes no claim the kernel acts on | |

### 1.4 What the verification found that the review did not ask

- **Probes should be what small programs produce.** The inputs an operator meets inside a program are other operators' outputs. At 1,000 probes per operator or more, this one change accounts for most of the difference between tables that lose answers and tables that do not (§6.5).
- **The Python gains have no plain control.** The plainest control compares each candidate of the last size with the target one row at a time and stops at the first mismatch, with no tables. No Python run has it. In the store prototype it cut candidates exactly as much as ordering by labels did, and took less time (§6.4, §8.7). Experiment X4 now has it as an arm.
- **A held answer bounds the rest of the search.** Under the size-order rule a split that fits is held while smaller programs are ruled out. Its size is a bound, and with a bound a look-ahead cut candidates 36× on seven guarded runs of the prototype (§7.2).
- **Labels save much memory in two situations.** The first is pure ring arithmetic with residues modulo small primes: stored classes were 8.5 to 26 times fewer at sizes 7 to 13, in Python. The second is the look-ahead once there is a firm bound on the size of the whole answer. In the store prototype the classes stored were 34 times fewer on the seven guarded runs, where a held answer gave the bound, and ten times fewer or more on three lifted tasks, where the answer's size was handed over. The two instruments count plain search's classes differently, so the figures are not comparable. That the first would move the memory wall out by two or three sizes is arithmetic on an extrapolation, not a measurement (§7.6, §8.7).
- **The difference from which an offset or a scale is read is often undefined.** It is taken element by element and needs two values of the same type and length. It was undefined for 41–43% of the classes on the path one step from an answer. The correction code itself is defined for any two values (§6.2).
- **The words the procedure chooses are not the hand-chosen ones.** They are mostly the length joined with a property of an early element, and on the one library tried they reach about four fifths of the hand list's gain (§6.5).
- **Averages flatter a tentative filter.** In one run of 234 tasks, with tables built from 2,000 random probes per operator, the filter lost 3 answers, two of them on larger tasks. The gain averaged per task was 16×. With the lost tasks retried by plain search, the saving summed over tasks was 12.7×. Under the three-to-one reserve it was 6.6×, against 12.1× under the same reserve had nothing been lost. So cost has to be summed over tasks with the fallback counted (§6.4, experiment X4).
- **Only the length tables, worth 3.6× of the 17×, follow from anything provable. About two fifths of the factor rests on entries that allow more than one output label, where a missed label cannot be told from an impossible one** (§6.5).

### 1.5 Clarity and length

Two independent readers went through the plan as first-time readers, one over the audit and proposal sections and one over the sections written in this revision (`reports/clarity-review.md`, `reports/clarity-review-new.md`). Both found the same thing: the main obstacle was vocabulary, not sentence length. About thirty internal names were used before they were defined, and eight ordinary words were used in two senses ("Stage", "node", "class", "fold", "witness", "quotient", "signature", "probe"). The fixes were definitions at first use, a table of terms at the front, one sense for each of those words, and full sentences where a string of noun phrases had stood. A further check then verified that the rewording had changed no fact. It found about forty places where it had, and those were corrected (`reports/factcheck3-C.md`). A last check compared the finished plan with the full record of the vocabulary measurements. It found no figure that differed. It found twenty-five places where a figure was attached to the wrong arrangement, a qualifier had been dropped, two sections disagreed, or a pointer led to something that had moved, and those were corrected as well (`reports/factcheck3-final.md`, `reports/apply-final.md`).

The plan was 38,300 words before this revision and is about 51,800 now. What went out: the three appendices that moved to this file, about 3,600 words, and the full record of the vocabulary measurements, which is now `measurements-words.md`. The plan keeps an account of about 3,500 words where that record has 7,000. What came in: about 9,000 words of definitions and fuller sentences from the two clarity passes, most of them in §2, which doubled, and in §5, §7 and §9; the table of terms; and the new material of §6, §7.2 and §8.7, which is longer than what it replaced because each figure now says what it was measured on and under which arrangement.

So this pass made the plan clearer and did not make it shorter. Shortening it further without compressing sentences means moving material out of it, and that is a choice about what the plan is for. The candidates, in order of size:

1. §2, the audit of the present kernel, is about 7,400 words. It could become a findings document in this folder, with the plan keeping §1.1, the diagnosis of §3, and the tables. That would save about 6,000 words.
2. §8.1 to §8.6, the prototype's results, are about 4,400 words. They could be reduced to their tables and conclusions, with the detail left to `reports/proto.md`, `reports/verify-review.md` and `reports/cross-space.md`. That would save about 2,500.
3. §4, the six perspectives, is about 2,300 words, and its conclusions are all carried into §5. It could move with §2.
4. Appendix A answers the points of your original prompt one by one, and §1.5 of the plan gives the same answers in short form. Dropping the appendix would save about 1,000.

Gaps that the clarity pass could not fill from any source are listed in the two gap logs, `reports/clarity-gaps-sec2.md` and `reports/clarity-gaps-sec4-9.md`. One concerns your own words: what "depth two" means, where your own use of the phrase does not confirm the outside review's reading of it.

### 1.6 A note on the reviewer's scripts

The plan's earlier text said the review's code was not in the repository. That is still so, but the scripts exist, in the review tool's own scratch folder, and they were read and run for this revision. Nine of this revision's own scripts import them from that folder, and cannot be rerun from the repository until it is copied in (Appendix D of the plan). The reviewer's scripts print what the review quotes. In at least five places a result is built into a script instead of computed: the six-word list, typed in and printed under the label of the selection rule; the pool of 24 hand-written candidates it is said to be chosen from; the "stratified" probes, of which about half are hand-chosen transforms; the answer's size, which is handed to the search in every memory experiment; and the lifted-task experiment, which gives `at` no table, filters only a size that is never stored, and enumerates `at` first.

## Part 2. The revision of 25 November 2026 (formerly Appendix G)

This part records the revision of 25 November. Its section numbers are those of the plan at that date. It answers the two questions in your request, then each note on `plan_v2c_annotated.pdf` and `plan_v2c_audit_annotated.pdf`, and says what was taken from the outside review, `plan_v2c_audit.md`, and what was not. The review was read as it stood at 17:20 on 25 November (323 lines). It grew twice while this revision was in progress, after your annotated copy: first by its second section, then by an appendix that restates that section in plain words and makes no new claim.

### G.0 The two questions in your request

**Computation within frames against search across them.** Accepted as you put it, and made a section (§5.9). Within a space everything is computed, in time linear in the cells touched; the one search there is for the term itself. Across spaces nearly everything is a search for a witness: a map, a substitution, a pattern, or a quotient. The witness is cheap to check and can be hard to find. Compression lives on that side, so the search is allowed, and it is budgeted differently: every attempt is tentative, capped, and recorded. A matching engine is included, as colour refinement with backtracking. Measured for this revision: refinement matches irregular data of 10,000 rows with no backtracking; regular structures without symmetry, and look-alikes that must be rejected, need it at once; and a crossing whose map is a small term costs almost nothing (§8.7). You asked that the hybrid kernel cheaply prioritize mixing between frames. The obvious way, overlap of signatures between problems, was measured and does not do it: it finds the form of a program and not its operators. What did work is in the next paragraph.

**Language.** Your sense that the representation behind it would unlock other expensive parts is supported, within limits that are now measured. The representation is the outside review's: a word is a label of a small quotient of values, and each operator carries a table of what it does to labels. A description is then a run of the program on labels, which is your October sentence made literal. On a hand-written library of 61 operators this cut candidates about 15 times and time 1.3 to 4 times, more at larger sizes, and worked for operators never used before, where prices from counts of past use failed (§8.8). The same object serves signatures, the choice of what to mix, guards, and part of the memory wall on arithmetic. In the one small test it did not serve reflection as an index, where plain replay did better. Over the sizes tried it behaved as a constant factor in candidates, and it loses a small share of answers, so it may order and filter tentatively but not eliminate. The vocabulary moves into Stage C, and X4 is rewritten to test it on the kernel's own library (§6.6).

### G.1 Notes on this document

Highlights without a note are listed only where they changed something.

| Where | Your note | Answer | Changed |
|:--|:--|:--|:--|
| §1.5, "A primitive may encode the shape of a container" | "does this mean a learned library primitive describes a datastructure .. ?" | Yes, in this sense. A container, on the store, is a recipe for a space: which rows a value unfolds into, the map back, and how to rebuild or reduce. The granted forms are that recipe for the one container the VM is born with. A learned container would be a library entry of the same shape: a pair of terms, unfold and build, that are inverse on the examples. A matrix is two nested position spaces; a tree is a position space with a parent endomap. So a data structure is a learnable entry, written in the store's own nouns. It is proposal, and not before Stage D. | §7.1 |
| §2.3, "It cannot buy more structure" | "so - it cannot go any deeper -- ??" | Correct. The job's tree is a root with one or two children, and it stops there. A child is expanded only when some generator proposes a decomposition for it, and none does. On the four stuck specs, raising `:max-depth` to 3 or 4 changed nothing. More budget lengthens the expressions enumerated at those nodes; it does not add nodes. | §2.3 |
| §2.3, the behaviour pruner | "is this a subset of the message idea / prototypes in the old code? What about UIP / DIP, which might be a special case of messages? Can part of the action of a behavior pruner be done by reflection?" | Yes to all three. The pruner's fact is "this column equals one already kept", which is a message in plan 4's sense: a claim with its evidence. A nogood is the same kind of fact about a requirement: a dependency test that failed. The UIP step generalizes such a fact; the DIP step looks for a column that separates the conflicting rows. On the store all three are facts about classes on one space, kept in one table. The pruner is also the cheapest reflection there is. What reflection could add is prediction: skipping the evaluation when a law or a count says the candidate will collide. | §7.4 |
| §2.8, "Quotient by laws before anti-unifying" | "duh" | Agreed. It is kept only as the measured form of the claim. | — |
| §4.5, "Trees embed exactly in squared-Euclidean space" | "is this true? The other doc mentions that superposition can only store quadratic items, not exponential.." | It is true, at one dimension per edge, which the draft did not say. Give each edge its own axis; a node's vector has the square root of an edge's weight on the axis of every edge between it and the root; the squared distance between two nodes is then exactly the length of the path between them. So it shows that nesting can be represented, and nothing about economy. On economy the other document and this one agree, and the draft was too terse: *storing* features in superposition is exponentially efficient, *computing* with them only quadratically. | §4.5 |
| §4.5, on arXiv 2611.17309 | "it took several years for it to become 'too easy'. also note that their move application is very clever, costing 700-900 flops per move, written in Triton + leveraging TB/sec cache. So a B200 can dispatch millions of moves in ms. I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else." | You are right and the draft was wrong to set the two against each other. On "too easy": agreed that it took years; the authors' remark is about what the benchmarks can show today. The paper's own text: search moves "run in Triton kernels with one GPU warp per chain", a move updates only the fields of the cells coupled to the one that changed, and a Sudoku costs a mean of 2.0 × 10⁹ FLOPs. A small, exactly representable energy makes the *learning* trivial; the *solving* is done by a very large number of very cheap moves. The figure of 700–900 FLOPs per move and the B200 are not in the paper's text, which reports an H200; they do not conflict with its per-puzzle total. | §4.5 |
| §4.6, "do not build reentrancy out of nested interpreters" | "No, def never run an iterpreter backwards; but why not build reentrancy out of nested interpreters?" | You can, provided the tower is collapsed before it runs. The warning was about paying for each level at run time: 6–178× per level until staged away, in the published measurements, and 4× from removing one level in this kernel's own closure compiler. Nested interpreters as the meaning of reentrancy are fine. As the way it executes, they need the scheduled lowering you already want. For most of what reentrancy is wanted for, the store needs no second interpreter: one evaluator whose terms can mention terms, spaces, and requirements. | §4.6 |
| §5.2, "a reference to a row of another space" | "yes finally" | — | — |
| §5.4, "different spellings give AU different alignments" | "???" | The sentence was unclear, and the quotation was an auditor's paraphrase. The source says that expressions which agree on the rows may "expose different alignments for the anti-unification mechanism", and that the enumerator "therefore retains their trees". The point: one class has many spellings, and which spelling is handed to anti-unification decides what pattern comes out. Keeping one representative per class can therefore hide a pattern that another spelling would have shown. | §5.4 |
| §6.3, "store's enumerator rather than listed by hand" | (highlight) | Measured in §8.7. Properties generated that way recognise a problem's form at three times chance, and do not pick its operators. | §6.3, §8.7 |
| §6.6 Language | "can nothing be adopted from the other plans and versions of this plan?" | Yes, and the section is rewritten around your October outline. It keeps the like and analogy rows of the mapping in `plan_v2b.md` §7.8, the `like`/`analogy`/`act` query forms named in `plan_v2.tex` without the vectors `plan_v2.md` gave those words, and plan 7's coupling of names to tariffs. The mechanism is the outside review's, after reproduction. | §6.6, §8.8 |
| §10, "We do not advocate such blank-slate learning as a route to AI." | "who is this from?" | The authors of DreamCoder (Ellis and colleagues), about their own run that rediscovered `fold` from first principles in about a year of CPU time. | §10 |

### G.2 Notes on the outside review

| Where | Your note | Answer | Changed |
|:--|:--|:--|:--|
| Its §1.3.1: classes merge "only after evaluating them on S", so transfer "across spaces still requires an explicit normalizer or probe evaluation" | "this is a fundamental limit for compression and needs to be allowed." | Taken as a requirement. §5.9 is new: computation within a space, search across spaces, the three ways to find a map, and what prioritizes the search. The draft's statement that nothing on the store needs graph matching is withdrawn. | §5.9, §7.6, §1.5 |
| Its §1.3.2: "Adding an 8-line monoidal pushforward" | (highlight) | Reproduced. The operator itself is nine lines; with the search around it, 44 to 71. It solves `seq-corr` from the kernel's seven spec rows, 200/200. It does not replace `fold`. | §7.2, §7.3, §8.5, §8.6 |

### G.3 What was taken from the outside review

Its empirical claims were reproduced before use, since none of its code is in the repository (§8.6, §8.8).

*From its first section.*

| The review's point | What was done | Where |
|:--|:--|:--|
| In standard terms the store is a tree automaton, or ground e-graph, indexed by spaces; `plan_v2b.md`'s attributed C-set is its core | adopted, as one sentence | §5.8 |
| What separates this plan from its siblings is extensional against intensional equality | adopted | §5.8, §5.9 |
| Rewriting across spaces is traded away | adopted, and after your note made a requirement | §5.9 |
| Collect under an aggregate unifies `tabulate` with reductions | adopted after reproduction. It does not replace `fold` | §7.2, §7.3, §8.6 |
| Shared holes are equal columns; the instance table is ragged; classes in cells need a product of automata | adopted on the review's argument and the literature; the last point was not run. The draft's sentence on classes in cells is corrected | §5.4 |
| An inverse's guard is the table's uniqueness test and a forward replay | adopted after reproduction | §7.2, §8.6 |
| Its guard for `a div b = c` solved for `b` | not adopted. It is sound but rejects 48 to 78 pairs that have exactly one answer | §8.6 |
| The prices are an oriented metric: symmetric and logarithmic on integers, asymmetric on sequences and code | adopted for the symmetry and the asymmetry. They are a metric in the strict sense only on integers, fields, and tuples | §6.1 |
| No violations of the triangle inequality | not adopted as stated: it holds on small values, and fails on sequences and code once values are large | §6.1, §8.6 |
| A live violation of the prefix-code bound, and one bit per column as the fix | adopted in corrected form. The sums are right; the violation is not live in the main pricing path | §6.2, §8.6, Appendix F |
| Name the pricing metric and the retrieval index apart | adopted | §6 |
| The prototype on the kernel's own spec rows | adopted after reproduction, with four corrections | §8.6 |
| A split must not be accepted ahead of a smaller unsplit term | adopted. It reverses the conclusion the draft drew from its own data | §7.2, §8.5, §8.6 |
| The prototype validates the store, not the general synthesizer | adopted and stated | §8.6 |
| The categorical vocabulary: a fibration over finite sets, an adjoint triple, an enriched metric | not adopted as this document's language. §5.8 records only the automaton and table identifications. An earlier audit said of `plan_v2.tex` that its vocabulary was heavier than its content, and your prompt objected to academic imports; the same caution applies | §5.8 |
| Description length as a shortest path through the store | not adopted. It was not checked, and with shared sub-terms choosing the cheapest derivation is itself NP-hard | — |

*From its second section.*

| The review's point | What was done | Where |
|:--|:--|:--|
| A word is a quotient of values; a verb is the operator's table over its labels, read off probe rows by one group-by; signatures and language are one mechanism (its first proposed change) | adopted after reproduction | §6.3, §6.6, §8.8 |
| The gain: 1.5× to 26.5× in candidates, with zero misses | adopted in corrected form: about 15× in candidates and 1.3× to 4× in time; 0.3% of answers lost at 1,000–3,000 random probes per operator, 11% at 100 | §6.6, §8.8 |
| The tables default "soundly" | not adopted. They are tested knowledge: they may order and filter tentatively, not eliminate | §5.5, §6.6 |
| Tables need no solved tasks, so new library entries are not starved; Naive Bayes over signatures is | adopted. The review's 6.5× for Naive Bayes depends on the order of the operator list, which is not known for its run; used as prices it is far worse than the review says | §6.3, §6.6, §8.8 |
| Ranking by surprise, as part of its headline method | not adopted: it added 3–5% | §8.8 |
| A merged product of quotients, to save memory | not adopted: 8 of 60 tasks lost at 2,000 probes per operator | §8.8 |
| Planning over the tables by shortest paths | not adopted: the bound on remaining steps rarely exceeds one or two, and one test before evaluation gives nearly all the gain | §6.6, §8.8 |
| Choosing quotients by lumpability | adopted as the first selection rule, with the four parts that had to be supplied by hand named | §6.6, §8.8 |
| The weakest guard by comparing bit masks | adopted. It is unique only when some guard in the pool has exactly the law's rows | §6.6, §8.8 |
| Residues modulo small primes, by column, against the memory wall | adopted for pure ring grammars, which is the limit the review itself states | §6.6, §8.4, §8.8 |
| Upgrade X4 to compare types, flat signatures with counts, and tables, including never-used entries (its second proposed change) | adopted, with the reproduction's accounting added: order-averaged baseline, every pass counted, wall time, and answers lost | §11.2 |
| A column of labels that hold on every row, to index the derivation space (its third) | not adopted for now. In an outline of its experiment, replay with no index found all 25 repeats and an index found 9 to 19, depending on its key. Replay's cost grows with the store, so the question stays open | §7.4, §8.8 |
| The literature on synthesis guided by abstract values | checked against the papers and added. The citations exist, and the figures quoted from them are exact. Two corrections: in the synthesizers cited the abstract meaning of each operator is written by hand, except in one that learns it from training problems and hand-supplied operator axioms; and Ruby is one system's implementation language, not a benchmark. One paper, from 1977, could not be fetched | §6.6, Appendix E |
| Its Appendix A, a walk through the second section in plain words | nothing further to adopt: it makes no new claim. Its "safety rule", that a case the probes missed can only loosen the pruning and never discard a real answer, is the claim that did not reproduce | §8.8 |

## Part 3. Your annotations on `plan_v2b.md` (formerly Appendix C)

The annotated PDF holds 28 annotation objects: 11 typed notes, 14 highlights, 3 ink strokes. `plan_v2.tex` listed seven notes, with wrong page numbers. The four typed notes it missed:

| Beside | Note |
|:--|:--|
| §9 risk 3: extraction is NP-hard; anytime search remains necessary | "Yes, I know." |
| §9 risk 7: a link between sheaf-style obstruction and clause learning | "what exactly does this mean?" |
| §9 risk 9: the kernel "chooses experiments" | "Yes!" |
| §8, the unit-exact ledger parity bullet ("work drift is tolerable") | "yes. and new (local) metrics may be admissible, even if they are not desireable." |

Highlights it missed include "Reuse has lost to matching cost in every small measured case on record", the passage on distributivity having no shape in the law filter, and "Lifting e-graphs". It also missed an ink bracket around the paragraph on a recognizer being a solver plus a decoder.

Read together, the notes accept the sober claims without comment and ask for mechanism or evidence wherever the text leans on literature: "how, though?", "what is the evidence for this? Or proof?", "Which successful engines?", "what exactly does this mean?". This plan was written to that standard: each proposal names its mechanism, and each number names its source.
