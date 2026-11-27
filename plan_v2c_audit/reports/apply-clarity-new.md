# Log: applying `clarity-review-new.md` to sections 1, 6, and 7.2, 7.4 to 7.6

Scope: `01.0.md` to `01.7.md`, `06.0.md` to `06.8.md`, `07.0.md`, `07.2.md`, `07.4.md`, `07.5.md`, `07.6.md`.
Output: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/sections-cn/` (22 files; the edit scripts are in its `work/` folder: `apply1.py` for sections 1 and 6, `apply2.py` for section 7).
Copied unchanged: `01.2.md`, `01.7.md`, `06.0.md`, `06.8.md`, `07.0.md`.
Words in the 22 files: 14,321 before, 15,359 after. Nearly every item that still applied asks for a definition or a fuller sentence, and most of the repetition in list C had already been removed by the rewrite of 6.1, 6.2, 6.4, 6.5 and 7.2.
No number was changed. Three sets of figures were removed from one place because the same figures stay in another (noted under C3, C10, C11). One figure was added from §8.7 (noted under B17).

## Section 0 of the review

- Two resolutions against two ways to compute: already fixed (6.1 has three computations; each cell of the table in 6.2 says "computed by"; 6.2 ends "one question, two resolutions, and three computations").
- "Word" in two senses: fixed in 1.3 (see A1); already fixed in 6.2 and 6.4.
- Tendency example and "exact" in the bottom-left cell: already fixed in 6.2.
- One move against four steps: already fixed by the bridging paragraph in 7.2; I added the names *leaf enumeration* and *refinement* there because the Control list uses them.
- The label test on a candidate that is not the last step; the two changes; the running example: already fixed in 7.2.
- Whether the four steps were run together: already fixed (7.2 says they were not, and names X4).

## List A

- A1: applied in `01.3.md` (a vocabulary is a set of words; "sign" is a word and "negative", "zero", "positive" are its labels). Already fixed in the table of 6.4. The row of the table of terms (front matter) is outside my scope and still says "The labels are the words".
- A2: outside my scope (front matter). Within my files I defined at first use: guard split (1.4), reserve and look-ahead (6.4), label filter (7.2), leaf enumeration and refinement (7.2). Gain, plain search, candidate, held, size-order rule, one step from the answer and true parent were already defined in 6.2, 6.4 and 7.2.
- A3: already fixed in 6.5 (four steps, "candidate word", "two-part word"). Applied the remaining two: "among the candidate words" in 6.5, and "candidate words" in the cost table of 7.6.
- A4: already fixed in all four places (6.4, 6.5, 7.2, 7.4).
- A5: applied (rule 4 of 6.3 and the sentence after the rules; "underived").
- A6: applied in the Control list of 7.2 (one agenda, which holds the open sub-problems of tasks and the problems the kernel poses to itself on probe spaces). I added one sentence to 7.5 and reworded the last sentence of 1.3's paragraph on the synthesizer so that the three places agree. The row for *agenda* in the table of terms (front matter, outside my scope) still says "between searches" only.
- A7: 6.6 and 7.5 already said "the literature review". I also wrote "the outside review" in 6.2 ("The outside review also argued"), 6.7 ("the outside review's citations"; `plan_v2c_audit.md` L149 is where Simba, Blaze and Atlas are cited) and 7.2 step 3.
- A8: applied to rule 5 of 6.3, with the review's rewrite in full. The cell in the table of 8.5 is outside my scope.
- A9: the look-ahead was already defined in step 4 of 7.2. I added the name *label filter* in step 2. Sections 8.7, 8.8, 10 and 11 are outside my scope.
- A10, A11, A12, A13: already fixed in 6.1 and 6.2.
- A14: already fixed in 6.2. Applied the last part: the bullet that uses "one step from an answer" now says the phrase is defined two paragraphs below.
- A15: applied (6.3). Appendix A makes the same statement and is outside my scope.
- A16: applied (6.3, the three bullets).
- A17, A18, A19, A20, A21, A22, A23: already fixed in 6.4 and 6.5.
- A24: applied (6.7): 42.6% to 82.0% is the share of held-out tasks solved, without and with the method, as means over seeds; 98.2% is the best single run with synthetic descriptions, which fell to 58.6% with descriptions written by people (`lit-geometry.md` L486 to 492).
- A25: already fixed for steps 1 to 3. Not applied for step 4: an example with a guard carried through step 4 would say what a search does on a task that was not run, so I did not write one.
- A26, A27, A28, A29: already fixed in 7.2.
- A30: applied, with C6. The paragraph keeps "Two further rules". The size-order rule is now one sentence that points to step 3, where it is stated with its reason; the rule on the guard of an inverse has the review's wording. The paragraph on the splitting laws was moved up to follow the table, and now begins "The laws in the middle column of the table".
- A31: applied. Refinements ranked by tables is marked **[P]**, with "No table of a construct has been built" and the fixed list keyed on types. "Section 11 of the search-engine report"; "features" are "the separating columns of §7.4, which the present kernel calls features". For the sentence on reporting cost summed over tasks I followed C8 instead of the A31 rewording (see C8).
- A32: applied (7.4). The index is described from `verify-quotients/q5_reuse.py` and `q2search.py`: a key computed from yes-or-no properties of the task's inputs and output. The numbers are the current ones (19, or 20 with variants), not the review's "between 9 and 19". `yield-gate` is described from the header of `v1/experiments/yield-gate.lisp` and from `bootstrap-reflection.md` L602 to 607.
- A33: applied (7.5). The gap the review marked for "Lifted forms" stays open: I found no source that says what is recorded about a lifted form, so the bullet is the question alone.
- A34, A35, A36, A37: outside my scope (8.5, 8.7).
- A38: not applied where it would change a number. `01.4.md` still says "about 15 times" and step 2 of 7.2 "about 16 times", against "14× to 18×, depending on the set of tasks" in 6.4. In 7.2 I added "the figure varies with the set of tasks (§6.4)". The three figures should be reconciled by the author.
- A39: applied in the one place in my scope: the `if` row of the table in 7.2 now reads "accepted only under the size-order rule (step 3 below)".
- A40 (a) to (e): outside my scope.
- A40 (f): applied (`01.0.md`), worded so that it does not say "counting and coding", since §6 now has three computations.
- A40 (g): applied (`01.1.md`); the wording matches §2.8.
- A40 (h): applied (`01.4.md`).
- A40 (i): applied (`01.5.md`).
- A40 (j): applied (`01.6.md`), with one change. The review's "showed no compounding" would contradict the corrected 6.5 ("at most a small source of compounding"; the gain rose from 13.5× to 15.3× with ten words). I wrote "showed little or none (§6.5)".

## The 22 small items

- L26 (work unit): outside my scope.
- L81: applied (`01.3.md`). The same sentence said "then the plain search with every near miss examined", which decision 4 contradicts; it now says the near-miss check is in the tentative pass and the plain search is the fallback.
- L95: applied (`01.4.md`).
- L100: applied (`01.5.md`).
- L664: applied (6.2): "behaviour distance" is glossed (the earlier plan's own definition is at `plan_v2c.md` L616), "property signatures" became "property sets" (decision 11), and §2.7 and §8.6 are cited.
- L678: applied (6.3): the identity in words, and *fiber* defined.
- L684: applied (6.3, rule 3): "latent" defined; "cluster labels" no longer uses the word "labels".
- L735: applied (6.4, item 4).
- L802: applied with B15.
- L850-851: applied (7.2 table: `k` is an argument that is already known).
- L915: applied with B16.
- L928: applied (7.4): the four figures overlap (§2.3), and the 6 accounting rules are not part of the mapping. I did not write that the accounting rules "stay as they are", because no source says so.
- L968: applied (7.6 table).
- L992: applied (7.6, rule 1: "when the types and the verb tables say that it cannot reach the target").
- L998: applied (7.6), as "Spent on breadth, re-validation, and ablation, hours can compound, as the audit measured", because the antecedent of "that way" is a page earlier.
- L1210, L1234, L1243, L1268, L1354, L1386, L1401: outside my scope.

## List B

- B1: already fixed in 6.1 and 6.2; 1.3 agrees with it.
- B2: already fixed (bridging paragraph), with the two names added.
- B3: already fixed (6.2, first bullet).
- B4: the sentence in 7.5 that cites §6.2 was already fixed. Applied the other half: "most of them are the question of §6.1".
- B5: already fixed in 6.4; see C2.
- B6: 6.4 separates the order of names from their price. Checked 7.2 ("Labels and corrections decide what is tried. They never decide what is accepted.") and 7.4 (counts "adjust the order that the verb tables give"): both agree. 7.1 is outside my scope and agrees.
- B7: already fixed in 6.4. §5.5 as it now stands says that verb tables are knowledge of the tested grade, so 6.4 agrees with it.
- B8: already fixed; step 4 keeps the sentence that the label part of the look-ahead is tentative.
- B9: applied in 7.2 (Control) and 7.6: one bank for each space and set of leaves; a search that prunes toward its target does so in a working copy. The row for *bank* in the table of terms (front matter, outside my scope) still says "in one search on one space".
- B10, B11, B13: outside my scope (8.7).
- B12: already fixed in 6.2.
- B14: 8.7 is outside my scope, so I cited the report by name where the number is stated: the one routine (6.2) and the summed-cost run (6.4) and "none of 234 tasks" (7.2) cite `verify-handoff.md`; the 22 of 32 operators (6.4) cites `verify-quotients.md`. The statement about a merged word in 6.8 carries no number and was left; its figures are in `factcheck3-A.md`, line 243.
- B15: applied (6.7).
- B16: applied for 7.4 (heading "Four uses of this record"; the counts come first in item 2), 6.4 ("The same words and tables serve five other purposes"), and 6.6 (a residual makes a new column, not a new space). §10 is outside my scope.
- B17, replay and the stages: applied (7.4: replay reads the library of stored solutions and is available from Stage C). X7 in 11.2 still lists replay under Stage D; outside my scope.
- B17, where the near-miss check runs: already fixed.
- B17, the memory figure: applied (7.6, rule 3). It now gives both figures of §8.7, 1.5 times and 4.3 times with a one-step look-ahead, and says what that look-ahead does (`verify-quotients.md` L149).
- B17, columns dropped then used: already fixed in 7.6.
- B17, which two specs: outside my scope. B17, the seven runs: already fixed in 7.2.

## List C

- C1: 6.5 had already been trimmed. I removed what still repeated inside the section: "about five tasks in a thousand" was said twice, and "95,732" twice. The remaining figures in 6.5 are each the evidence for one rule or one observation, and A23 asks for them in full, so they stay.
- C2: applied. 6.2 has the full statement; the bullet in 6.4 is now "It acts on the last step (§6.2)" with the one consequence for the gain; 7.2 points to 6.2.
- C3: applied in 7.2. The reason stays in step 3; the figures (9 runs, 7 of 9, 120 conditionals) are now only in the third limit of 6.4, which step 3 cites.
- C4: nothing more to cut in my files. Rules 1 and 2 of 7.6 are in list D; rule 3 is the corrected text of decision 8.
- C5: 7.2 keeps the mechanism and its headline figures; nothing cut. 8.8 is outside my scope.
- C6: applied (see A30).
- C7: applied in 7.5 (rule 4 no longer ends "so the fallback stays"). Left in 6.4, where the bullet no longer carries figures and states the consequence once, and in 7.2, where "the fallback covers it" answers the failure just described.
- C8: applied in 7.2. The reporting rule is no longer restated there; the bullet gives the measurement and points to X4. The review's A31 asked only for a clearer subject in the sentence that C8 removes.
- C9: applied (7.4, item 2 is one clause on counts and points to 6.4).
- C10: applied in part, because list D protects the four rules of 7.5. Rule 4 keeps its statement and its result in words; the figures are left to 6.5.
- C11: applied in 6.1 (the bit counts 0, 4, 5, 5, 8 and 17 are now only in the table of 8.5; the worked example and the properties in words stay). The optional cut to rule 5 was not taken, because the brief asks for the A8 rewrite.
- C12: not applied, by instruction. The precedent figures stay in 6.7.
- C13: 6.7 keeps the sentence on compounding, because B15's rewrite keeps it and it is the conclusion of the paragraph; it now points to §10. 1.6 keeps its bullet.
- C14, C15: outside my scope.
- C16: applied (7.5 no longer defines a probe space; §5.5 and the table of terms do).
- C17: no change, as the review says.

## List D

Nothing it names was cut or compressed. The changes inside passages it names are corrections of wording asked for elsewhere in the review: rules 3, 4 and 5 of 6.3; the first and second rows of the table in 7.2; two rows of the cost table in 7.6; rule 1 of 7.6; rule 4 of 7.5 (see C10); the paragraph "A search reads" in 7.2, which gained a report name.

## Other changes made under the brief's decisions

- Decision 1: "a word is a term on values" in 6.6; "for one word" in the cost table of 7.6.
- Decision 11: "the search tree has two or three sub-problems" in `01.1.md` item 3 (the phrase is in item 3, not item 4).
- Decision 13: 6.6 now cites the labels of §6.2, as 1.5 does.

## For the author

- The table of terms in the front matter still has the old senses of *word*, *bank* and *agenda*.
- "About 15 times" (1.4), "about 16 times" (7.2) and "14× to 18×" (6.4) are the same quantity (A38).
- §8.7 as it stands says an index found "9 to 19, depending on its key"; 7.4 says "19, or 20 when variants of the retrieved solutions were tried as well".
- X7 (§11.2) and Stage D (§11.3) list replay with the derivation space; 7.4 now says replay is available from Stage C.
- What is recorded about a lifted form (7.5) is not stated anywhere.
