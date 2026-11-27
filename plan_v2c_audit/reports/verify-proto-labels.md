# L1: quotient labels and verb tables inside the tg-probe store prototype

Work directory `W = /tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/l1-proto/`. The repository was not touched; `git status` is the same before and after.

## 1. Bottom line

The label filter can be attached where the task asks. Every bank in the prototype is built after its target column is known. But it cannot *skip* anything, because the search deepens one size at a time and never knows which size is the last. Used instead as an **order** inside each size level, it cut candidates 17× and 22× on reverse and rotate, 2.5× and 6× on map-adjacent ±, and nothing on the guarded tasks. It changed no answer in 120 runs, with 0 false rejects. Two cautions:

- The whole cut comes from finding the answer earlier inside its own level. A test with no labels at all, comparing each candidate with the target row by row, gives the identical cut faster.
- Used as a true filter on a level known to be last, it **destroys the guard split** in 7 of 9 guarded runs. A near-miss always fails the labels on exactly the rows it gets wrong.

Labels earn their keep only in the look-ahead ("decline to store"), and only once a size bound exists.

## 2. Verdict table

| Claim (review §2.5.3, App. B.2 item 1) | Verdict | Review | Prototype (this work) |
|:--|:--|:--|:--|
| The reviewer's script prints these numbers | REPRODUCED | 5.3×, 7.6×, 1.0×, 1.0× | 5.3×, 7.6×, 1.0×, 1.0× (`reviewer_expA.log`) |
| Labels cut evaluations 5.3–7.6× when arithmetic is outermost (map-adjacent + / −) | PARTLY | 5.3×, 7.6× | 2.52×, 6.09× in candidates; 1.39×, 2.52× in CPU time. Over seeds 2–9: 2.49×, 6.07×. A label-free exact test gives the same cut in less time (1.58×, 2.91×) |
| Nothing when `at` is outermost (reverse, rotate-left) | NOT REPRODUCED: an artifact of operator order | 1.0× | 17.3×, 22.3×. With `at` placed first in the operator list: 1.04×, 1.14×. The reviewer's own script with `at` placed after the binary operators: 9.7×, 12.5× |
| Labels never reduce stored classes (1.0× RAM) | TRUE BY CONSTRUCTION in the script; FALSE for the look-ahead | 1.0× | The script never stores the last layer in either arm. In the prototype, used as an order: classes up to the last completed level identical; classes held at the end 3.25× fewer, from cutting the answer's level short, which the label-free test also does. Look-ahead with a size bound: 36× to 95× fewer (§3, item 4) |
| Python result: 15× fewer candidates gave only 1.3–4× in time | REPRODUCED in kind | — | 15 tasks: 2.73× candidates, 1.68× CPU, 1.50× total work. Geometric means 3.09×, 1.36×, 1.04× |

## 3. What changes for the plan

1. **The filter can only be an order, unless a size bound is known.** The target is known per bank: `solve-tabulate` builds the element bank after computing `yseq`, and `solve-col` receives `y` (`proto/tg-probe.lisp:426-431`). But `solve-col` deepens by size (`:405-412`) and stores every class of a level for later levels (`try`, `:123-134`). So a candidate that is ruled out at size *s* is still needed if size *s* is not the last. My filter tests a level's candidates first, evaluates the label-feasible ones, then evaluates the rest unless the answer was found. The gain is bounded by one level: completed levels are untouched (column `cand<=dn` is identical in every mode, `e1.log`).

2. **On these tasks the target itself is a sharper and cheaper test than any quotient.** The comparison mode "probe" tests each candidate against the target row by row, stopping at the first mismatch: about 1 cell per candidate, no labels. Over 120 runs (seeds 2–9) it matches the label filter's candidate cut exactly (2.50×) and does better in time (1.88× against 1.61×) and in work (2.32× against 1.39×). The labels lose because each stored class must be labelled on every row, 3 quotients × n cells, which roughly doubles the per-class cost. On the five guarded tasks, where no level holds a single-class answer, the filter is pure overhead: 0.76–0.84× in CPU.

3. **The gain is set by operator order, not by which operator is outermost** (`e7.log`). Over six operator orders, reverse ranged from 1.04× to 22.8× and map-adjacent + from 2.25× to 23.8×. A label test on 30–50 lifted rows is close to an exact test (item 5). It removes almost exactly the candidates that plain search evaluates before the answer inside the answer's level, and that count depends only on the order. The review's "nothing when `at` is outermost" holds only when `at` is enumerated first, which is the case in its script.

4. **The look-ahead reduces stored classes, and labels matter there.**
   - *With the answer's size handed over (an oracle):* classes stored fell from 25,639 to 270 (reverse), from 123,369 to 3,393 (map-adjacent +) and from 2,306,369 to 34,919 (map-adjacent f). The order-only filter gave 1,470, 30,181 and 717,984.
   - *With no oracle, deepening the bound with a restart from the leaves each time:* the same classes, at 3,933 / 91,603 / 285,795 candidates against plain's 86,434 / 291,481 / 8,458,580.
   - *Under size-ordered split acceptance (`*occam*`, no oracle):* the held split supplies the bound. On 7 guarded runs: 36× fewer candidates, 17× less CPU, 34× fewer classes held (14.36M → 0.42M); programs changed 0, lost 0 (`e5.log`).
   - *Types alone or labels:* types alone (no quotients) give the whole gain on 5 of the 7 runs. Labels are needed on the two `call`-rooted ones: scan f, 13.4M → 0.48M candidates; spec scan, 3.6M → 0.26M.

5. **Many rows make the filter sharp, but 2–4 rows already suffice** (`e2.log`, parts c and d). In the answer's level, the share of table-tested candidates not ruled out:
   - map-adjacent +: 2.3% with 1 row, 0.044% with 2, 0.0016% with 4, 1 candidate (the answer) with all rows;
   - reverse: 3.7% with 1 row, 0.04% with all.

   Total candidates: 3.53M with 1 row, 3.39M with 4, 3.38M with all; look-ups per candidate rise from 1.13 to 1.53. Random integers do not give "every label combination", because `+ − *` determine parity and the residue mod 3 exactly. A single quotient does almost all of it: parity alone 3.396M, all three quotients 3.379M. The `at` variants change almost nothing (3.379M → 3.377M), because only the few `at`-rooted candidates before the answer depend on them.

6. **The label filter and the guard split interfere: the filter must exempt near-misses, and labels cannot tell which candidates those are** (`e3.log`).
   - With the last level handed over and only label-feasible candidates evaluated, the split was lost in 9 of 9 guarded tasks. The prototype's 5 guarded tasks, spec scan, spec shift-seq, spec last-or, and spec map-adjacent, where the lost split was a 29/200 impostor.
   - With Boolean guards exempted it was still lost in 7 of 9. Only shift-seq (both row sets) survives, because its near-miss `(at xs (+ i k))` has `at` at its root. With the pair quotient added, that one is lost too.
   - Every near-miss was "allowed on m/n rows", with m exactly the rows it matches. The tables reproduce its match mask, and so must rule it out.
   - Separately, the Boolean guard of shift-seq is created at the last level, so even a filter by result type alone loses it.
   - Goal inversion (the prototype's other computed residual) survived a strict filter on map-adjacent ± and zip-add (`e4.log`), but only because its partner `(at xs (+ i 1))` has `at` at its root, for which the table says "anything". Inversion also beats the filter outright: map-adjacent ± in 4,791 candidates against 115,673.

7. **Cost.** Look-ups per table-tested candidate: 1.2–4.6 (`lk/gat` column). Building the tables: 26 ms for 13 operators × 3 quotients, plus 37 ms for `at` with sequence labels and the pair table.

## 4. What I built (a design choice in each case)

- **Quotients:** parity, residue mod 3, sign; an undefined cell gets its own label in each. The pair quotient on (index, sequence) is where the index falls: below, inside or above the sequence, or undefined. It is the natural label of the position/length pair and predicts whether `at` is defined. Sequence variant: a sequence is labelled by the set of its elements' labels, which covers "all even" and "all non-negative".
- **Verb tables:** one group-by over joint probes of all arguments:
  - integers −12..12 plus the undefined cell;
  - 703 probe sequences: all sequences of length ≤ 3 over −2..3, 300 random ones, and 144 drawn from a single label class;
  - all `:code`, `:pred` and `:bool` values.

  Checked on a wider range (−40..40, values up to ±10⁴, 400 fresh sequences): 0 unsound entries. With a −3..3 grid, `mod` under mod 3 was unsound on 3,953 of 20,164 probes.
- **The filter:**
  - *Order mode:* `first`.
  - *Strict mode:* filters only at a level handed over by an oracle.
  - *Look-ahead:* below a bound B, an operator is not enumerated if its result type cannot reach the target in the size left. A class of size s is not stored when (a) B − s is too small for it to sit two operators below the root, and (b) no operator, with any partner, can take its labels to the target's on every checked row. A column equal to the target is never declined.
  - *Comparison modes:* `lfprobe` and `probe`; `audit` counts false rejects.
- **Code size:**
  - probe copy `tg-probe-l1.lisp`: +33 / −10 lines against `verify-review/tg-probe-r2.lisp`, 21 places marked `L1 MOD` (`logs/diff-probe-l1.patch`);
  - `labels.lisp`: 490 lines, new;
  - drivers `l1-run.lisp`: 502 lines.

  With the filter off the copy reproduces the repository's `proto/logs/d.log` exactly, timings masked (`run-regress.sh`: "REGRESSION OK").

## 5. Supplied by hand

- **Mine:**
  - the three quotients, the pair quotient and the sequence-set label;
  - the probe grid;
  - which rows are checked;
  - in strict mode, the last level (an oracle);
  - in `la-oracle`, the bound.
- **The reviewer's script:**
  - the answer size (`max_ops`), so the last layer is known;
  - `at` enumerated before every binary operator, which is the source of the "1.0×";
  - no storage of the last layer in either arm, which is the source of the "1.0× RAM";
  - labels checked on the first 6 rows only;
  - no table for `at`;
  - hand-chosen sequences of lengths 4, 5, 3, 6, 4, 5;
  - commutativity pruning, which the prototype does not have.

## 6. Commands (all in W; `run-all.sh` reruns everything)

| Table / claim | Command | Log | CPU or wall time |
|:--|:--|:--|:--|
| reviewer's EXP A | `bash run_reviewer_a.sh` | `logs/reviewer_expA.log` | 11 s |
| reviewer's A2 with `at` placed last | `python3 make_reviewer_a2_order.py && python3 reviewer_a2_order.py` | `logs/reviewer_a2_order.log` | 20 s |
| regression | `./run-regress.sh` | `logs/regress-d-l1.log` | 4 min |
| tables | `./run.sh e0` | `logs/e0.log` | 1 s |
| main comparison | `./run.sh e1`; `python3 tabulate.py logs/e1.log` | `logs/e1.log`, `logs/e1-table.txt` | 7 min |
| quotients, `at` variants, rows | `./run.sh e2` | `logs/e2.log` | 15 min |
| guard split | `./run.sh e3` | `logs/e3.log` | 45 s |
| inversion | `./run.sh e4` | `logs/e4.log` | 3 min |
| look-ahead | `./run.sh e5` | `logs/e5.log`, `logs/e5b-table.txt` | 25 min |
| seeds 2–9 | `./run.sh e6` | `logs/e6.log` | 20 min |
| operator orders | `./run.sh e7` | `logs/e7.log` | 2.5 min |

Times are process CPU time, fastest of 3 runs (1 run if over 3 s). The machine had a load average of about 35 from other jobs, so wall-clock times were not used; CPU times still carry perhaps ±10% noise.

## 7. Not done / could not check

- The kernel's own library was not used: only the prototype's 12-operator grammar, plus `call1b` on the spec rows.
- Folds, `fold-space` and the select path were not given a label filter beyond what E1 includes (positions-of, filter).
- The look-ahead was not run with the deepening bound on the guarded tasks under the default first-fit policy. There the guard split needs the near-miss, and E3 shows the look-ahead loses it.
- Out of scope, noticed: the reviewer's copied EXP A1 prints 4.9×, 5.5× and 6.0× "TRUE RAM gain", not the review's 9.4×, 22.6× and 22.9×.
- Process: two early helper files were written with inline heredocs before I re-read rule 3. Their contents are saved in W (`run.sh`, `run-regress.sh`).
