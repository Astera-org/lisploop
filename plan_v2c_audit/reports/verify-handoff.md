# verify-handoff: the review's §2.5.1 ("one store primitive") and §2.5.2 ("four-stage handoff")

Work directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/q4-handoff/`.
Python 3.14, standard library only, fixed seeds. The library, quotients, tables and searches are the
verify-quotients code (`seqlib.py`, `q2search.py`, `q2tasks.py`), copied unchanged. Nothing under
`/home/tlh24/lisploop` was touched.

Terms used below. **DL** is the kernel's correction code (`codec.lisp` `emit-positive` on `ast.lisp`
`signed-code`, the per-type rules of `frame.lisp` `correction`). An integer difference d costs
2·⌊log2 w⌋+w−1 bits, where w is the bit length of 2d+1 (d ≥ 0) or −2d (d < 0): 4 bits at ±1, 5 at ±2, 8 at 4,
17 at 1000. An exact value costs 1 bit, not 0 (plan §6.2 rule 5). A list costs 1 bit when the lengths agree,
or 1 + the integer code of the length change when they differ; then per shared position 1 bit, plus the
difference when the elements differ; then the plain code of any added elements; capped at the list's own
code. **On-path class**: a proper subterm of the reference program. **True parent**: the argument of its root.
**Percentile**: 0 = closest to the target, 50 = what a random class gets.

## 1. Bottom line

One group-by routine (30 lines) does produce inverses with their uniqueness guard, exact congruences and soft
verb tables, with the same code and the same output. It does not produce laws or computed residuals without
steps that are not group-bys. Its "q = identity, small residual" regime cannot tell a near miss from an
unrelated column: the residual is zero for 54–56% of all bank classes. The complementarity claim is half right.
Label tables prune only one step from the target: 0.0% of classes are ruled out two or more steps out. Ambient
description length is weakly informative several steps out, not misleading. Residual proposals pay well on
tasks that have a near miss (2.4–3.0× on top of labels), but once labels are used they add at most 1.1× on
ordinary tasks.

## 2. Verdict table

No script in the reviewer's directory computes the five-regime table, either example in Appendix B.3, or any
stage-3 quantity. A grep for `residual`, `L1`, `ambient`, `decode` and `running_max` finds only operator
definitions. These claims are argued, not measured, so there was nothing of the reviewer's to re-run.
Paired numbers are the two task sets (seeds 11 and 12, 119 and 115 tasks of 3–4 operators, 8 rows each).

| Claim (review) | Verdict | Mine | Review |
|:--|:--|:--|:--|
| U1: one group-by gives all five regimes | PARTLY | Same code and output for regimes 2, 4 and 5. Regimes 1 and 3 need extra steps (below). | asserted |
| U1 regime 2: inverse and uniqueness guard read off the table | REPRODUCED | `*` determined on 92.3% of the grid; weakest guard `(not (= b 0))`; witness `(div c b)`. `max` 46.2% once the grid is widened. | plan §8.2: 92.3%, b ≠ 0, `(div c b)`; 46.2% |
| U1 regime 1: law = residual 0, q = id | PARTLY | `x+1` given `x`, and `x*x` given an unrelated `y`, also give residual 0, so a law needs an equality test. In the store a law is a collision: term given column has a *positive* residual (1,525 terms in 122 columns). | — |
| U1 regime 3: computed residual = L(Y∣U), q = id | NOT REPRODUCED | The identity group-by gives 0 both for the near miss and for `y+100x`, in 100% of 2,000 random spaces. "Y is a function of U" holds for 53.8% / 55.5% of all bank classes (81% at 4 rows). | — |
| U1 regimes 4 and 5: congruence, soft verb table | REPRODUCED | `mod 5` on `+ − *`: H_cond = 0 with a 25-entry table; `div` scores 0.08, `max` 0.66. 18 of 18 verb tables are identical to verify-quotients'. | — |
| U2: ambient distance misleads several steps out (B.3 example 1) | PARTLY; the example is one row | L1 of 12 against 8 reproduces on the review's single row. On 8 rows (3 seeds) `abs_all` ranks 1st, 1st and 2nd of 14 by L1. Across all tasks, the on-path class's mean DL percentile is 20.5 / 23.0 one step out, 32.2 / 39.0 two steps out, 28.9 / 32.7 three steps out (every 95% interval is below 50). It falls in the worse half in 18–23%, 34–42% and 23–27% of cases. | 8 < 12 |
| U2: tables see multi-step structure (stages 1–2) | NOT REPRODUCED | Label reachability rules out 43% / 47% of classes one step out, and **0.0%** two and three steps out. It never rules out the on-path class (0 of 410). | asserted |
| U2: labels are blind one step out (B.3 example 2) | PARTLY | Labels leave the true parent tied with other classes in 25% / 26% of tasks with six quotients, and 48% / 45% with sign and parity only. `mod 3` and `mod 5` do separate `2x²` from `2y²` (5/8 and 6/8 rows). | asserted, for parity and sign |
| U2: the residual separates where labels tie | PARTLY | Inside the tie group, DL ranks the true parent strictly first in 46% / 54% of cases, against 39% / 33% by chance. | asserted |
| Stage 3: `(decode U ?R)` proposal | REPRODUCED on near-miss tasks | 192 offset/scale tasks: 2.4× / 3.0× on top of labels; 30× / 35× against plain search, even when that search has the needed constant as an operator; no answer lost. | — |
| Stage 3: `(if ?g U ?else)` from the disagreeing rows | PARTLY | Planted conditionals: a fit is found in 120/120, and the first is right on 64 fresh rows in 82/120. Ordinary tasks: a fitting split exists in 64/234, and the smallest is right in 2. | — |
| "Residual bucket regularity" breaks ties | PARTLY | Puts the offset near miss first in 56/64 in both sets (DL alone: 29 and 22). Scale near misses: 4 and 3 of 32. It moved conditional branches down in 79/240 and up in 0; on ordinary tasks, up in 47 and down in 62. | asserted |
| The four-stage order | PARTLY | See the B4 table below. | asserted |
| Two timescales: tables are only read online | REPRODUCED, with a cost | A target label that no table has: 0 of 234 tasks at every probe count. A transition missing from a table: 3 of 234 answers lost at 2,000 probes. | asserted |

**B4, the order of the handoff** (whole search, every deepening pass counted, geometric mean over tasks):

| Arrangement | Gain over plain | Answers lost |
|:--|--:|--:|
| Labels during enumeration (stage 2) | 15.6× / 16.9× | 1 / 2 |
| Labels only at the last level ("labels late") | 7.8× / 8.0× | 1 / 2 |
| Residual (DL) order of the last level, no labels ("residual late") | 3.9× / 3.9× | 0 / 0 |
| Residual early as a cut: keep the best 50% / 25% by DL at every level | 3.2× / 12.2× (seed 11) | 31 / 68 of 119 |
| Best possible order of the last level, on top of stage 2 (ceiling for stage 3) | 1.12× / 1.11× more | — |
| Inside the label-filtered last level, candidates until the answer: random, DL, table surprise | 90, 9, 5 / 84, 9, 7 | — |
| Near-miss tasks: residual check on label survivors only (review), against every evaluated candidate | 2.07× / 1.97× more work | 0 |

With 4 rows per task the picture holds: on-path classes sit at the 20.0, 36.7 and 30.4 percentiles; labels
early give 11.9×, labels late 6.7×, residual late 3.7×; the stage-3 ceiling is 1.18×; labels tie the true
parent in 45% of tasks (six quotients) and 69% (two).

**C, a target the tables do not predict.** On the 234 ordinary tasks, no target ever carried a label that no
probe value had, or that no operator's table could output. That held at 100, 300, 1,000 and 2,000 probes per
operator, with i.i.d. and with enriched probes. The case that does occur is a step of the reference program
whose input labels the probes saw but whose output label they did not, so the table calls the step
impossible. Such steps occurred in 99, 29, 4 and 5 tasks at those probe counts, and the answer was lost in 26,
7, 2 and 3. A lost task falls back to plain search. Under the 3:1 reserve (three parts tentative, one part
fallback), the summed saving is 1.7×, 3.2×, 8.5× and 6.6×, against 12.1× if nothing were lost. Another probe
seed and the enriched probes lose 2 and 1 tasks, and give 8.5× and 8.6×.

## 3. What changes for the plan

1. **U1: state three regimes as measured, two as a way of speaking.** Inverses (uniqueness), congruences and
   verb tables are one routine with one output type. The routine reproduces §8.2's `*` row exactly. A law is a
   collision of columns on the term space, which is the store's existing mechanism; "zero residual" is too weak,
   because `x+1` given `x` passes. A computed residual is not a group-by. It is §6.1's correction code applied
   to a type-specific difference. That difference is undefined for 41–43% of true parents one step out
   (29–34% because list lengths differ, the rest because the types differ), and a constant offset on lists is
   constant only on the position space. Extra lines
   beyond the 30-line routine: law 2 (+15 for the enumerator); inverse 9 (guard) + 18 (witness search);
   residual 6 (difference) + 3 (positions) + 5 (code) + 9 (guard); congruence 0; verb table 0.
2. **Do not write that labels "look several steps ahead" on this library.** They rule out 0.0% of classes two
   or more steps out, and 43–47% one step out. That agrees with verify-quotients ("the bound rarely exceeds one
   or two"). Ambient DL keeps a weak signal several steps out: percentile 29–39 against 50 for chance.
3. **Keep the `(decode U c)` proposal as a cheap check, and run it on every evaluated candidate, not only on
   label survivors.** On near-miss tasks it gives 30–35× without the constant in the grammar, 2.4–3.0× on top of
   labels, and 2× more when it runs before the filter. On ordinary tasks it fired in 70 of 234 tasks, was right
   on fresh rows in 64 of 70, and gave 2.4–2.6× over plain search (2.1–2.25× counting each check as a candidate).
4. **Stage 3 as a ranking is nearly worthless after stage 2 on ordinary tasks.** The ceiling is 1.11–1.18×, and
   the tables' own surprise orders the last level better than DL does.
5. **Split proposals need §8.5's size-order rule.** On ordinary tasks, 97% of the smallest fitting splits are
   impostors, though all are at least 3 nodes larger than the answer.
6. **"Regularity" should be §6.2's form (R constant, or R a bank class)**, not "the labels of R are constant".
   The label form helps only constant offsets and hurts conditionals.
7. **Two timescales: the risk is a missing transition, not an unseen label.** At 2,000 probes the 3 lost tasks
   are among the most expensive (plain cost 16k, 312k, 319k). Under the 3:1 reserve they cut the summed saving
   from 12.1× to 6.6×, while the geometric mean stays at 16.3×. At 100 probes: 26 lost and 1.7×. X4 should
   report summed cost, not only geometric means.

## 4. Supplied by hand

- **Mine:**
  - the six quotients (verify-quotients' hand list);
  - the inverse guard pool (13 terms) and the witness grammar (`+ − * div` over `b`, `c`);
  - the split guard pool (4 predicates of integer classes, plus `<` and `=` of size-2 classes);
  - the proposal forms (offset, scale, `if`) and the difference operator;
  - the three value quotients used for "regularity";
  - the near-miss task families, which are built to contain a near miss, so the gain there holds by
    construction of the task set;
  - the oracle constant operators used in baseline A;
  - n* taken from plain search for B1, B2, B4(a) and the beam (every search arm otherwise deepens and counts
    every pass);
  - in B3, a fired proposal ends the search with no fresh-row check during the search; it was checked
    afterwards (64/70).
- **The reviewer's:**
  - the five-regime table and the four stages are asserted, with no code;
  - B.3 example 1 is one row, and on 8 rows the inequality reverses in 2 of 3 seeds;
  - in example 1, labels do not rule out `running_max(xs)` either (0 of 27–31 size-2 classes are ruled out);
  - example 2 depends on choosing parity and sign as the vocabulary.

## 5. Commands (run in the work directory)

| Result | Command | Log | Time |
|:--|:--|:--|--:|
| A (U1) | `python3 u1_residual.py` | `u1_residual.log` | 3 s |
| The B.3 examples | `python3 b3_example.py` | `b3_example.log` | 2 s |
| B1, B2, B4 | `bash run_b12.sh` | `b12_report.log` | 3.5 min |
| B3 | `bash run_b3.sh` (then `python3 peek3.py b3_os_s21.json b3_os_s22.json`) | `b3_report.log`, `peek3.log` | 3 min |
| C, and the 4-row run | `bash run_c.sh` | `c_unpredicted.log`, `b12_report_rows4.log` | 3.5 min |
| Look-ups (lost tasks, worse-half counts) | `python3 peek.py b12_s11.json b12_s12.json` | `peek.log` | 1 s |

`b12_report_rows4.log` says "on the 8 rows" in one line; that run has 4 rows.

## 6. Not done / could not check

- Python on a hand-written 61-operator library, not the kernel.
- Stage 1 (replay) and stage 4 (two-part-code acceptance) were not tested.
- Split guards are shallow, and the `else` branch came from the bank, not from a sub-search.
- Residual proposals were tried only for a constant offset, a constant scale and `if`.
- C stops at 2,000 probes; edge-stratified probes appear only as the "enriched" pool.
- The 55 tasks where plain search found a program shorter than the reference are excluded from the on-path
  statistics.
