# verify-probes: how verb-table probes are chosen, and what is lost

Work directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/q2-probes/` (all scripts and logs below are there).

Terms: a **loss** is a task the table-filtered search does not find at the size plain search finds it (the same search and definition as verify-quotients `q2_sound.py`). A **defect** is a "seen input, unseen output" transition on the reference program's own path. **Gain** is the candidate count against plain search, averaged over operator orders.

## 1. Bottom line

The review's 0/200 is a defect audit, not a search. It came from one seed, with probes that were half hand-made transforms matched to the quotients under test. Over 20 probe seeds, the same probes average 1.9 misses, and changing only the task seed gives 2 to 9 misses, never 0.

An automatic rule does better than the hand transforms at every budget, and it lost no answer from 1,000 probes per operator on all three task sets. That rule takes program-shaped probes (operator arguments as random small programs produce them on one row) and spreads them evenly across the occupied buckets of pairs of quotients. Stratifying i.i.d. random lists alone is not enough, because some buckets are unreachable.

Online feedback removes nothing once the probes are good. Merged products still lose answers at 10,000 probes. Slices must not feed label-keyed tables. Only about 60% of the gain survives if only deterministic entries filter.

## 2. Verdict table

| Claim | Verdict | Mine vs review |
|:--|:--|:--|
| P1: ≥1,000 probes "stratified across occupied buckets plus edge cases" give 0/200 misses with no feedback; 150 random give 110/200, and 55/200 with feedback | **Numbers REPRODUCED, the claim is TRUE BY CONSTRUCTION and does not survive seed variation.** In EXP D the "stratified" probes are 529 hand transforms plus 471 random lists, with no buckets at all, and a "miss" is a reference-path audit (your reading is correct). | 110/55/0 exactly (`run_reviewer.log`). Same probes, 20 probe seeds: 1.9 mean, range 0–7, zero in 7/20. 10 task seeds: 2–9, never 0. Literal bucket stratification with no hand list: 0.6 at 1,000 (zero in 9/20) and 0 at 3,000 (20/20). Equal-budget random at 1,000: 13.8. |
| P1 as a kernel mechanism | **PARTLY.** Stratifying by current words helps, but only on top of a program-shaped source. | bank2+strat2: 0 lost from 1,000 probes on 300 + 200 + 200 tasks; defect-free on 4,000-task streams in only 4/10 seeds at 3,000 |
| P2: feedback is unnecessary | **REPRODUCED for good probes, measured.** It still helps weak tables. | best rule at ≥1,000: 0 losses with or without feedback; 300 probes: 5 → 4 |
| P3: merged products still lose with stratified probes | **REPRODUCED** | merged3 with the best rule: 68 / 27 / 10 of 600 lost at 1k / 3k / 10k probes (review: 50/200 at 2k) |
| P4: dependency scores and slice false rejections | **REPRODUCED exactly.** The size of the effect depends on the slice set chosen. | div 0.04 vs 1.00; mod 0.53 vs 1.00; false rejections 55/50/287/422 vs joint 0 |

## 3. What changes for the plan

**1. Probe rule (P1).** All rows use the six hand quotients and 61 operators of verify-quotients, with the same search. The losses columns sum 3 table seeds on S300 (900 searches) and 2 seeds on each edge set (400 searches each). The defects column is per 1,000 tasks of a 4,000-task stream, as the mean over 10 table seeds (`exp_audit.log`).

| Rule (probes per operator) | Lost, S300: 300 / 1k / 3k | Lost, EDGE-R | Lost, EDGE-W | Defects /1,000 tasks at 1k / 3k |
|:--|:--|:--|:--|:--|
| (i) i.i.d. | 17 / 5 / 1 | 11 / 1 / 1 | 10 / 6 / 3 | 44.8 / 21.3 |
| (ii) strat2: literal, pairs of buckets | 4 / 1 / 0 | 7 / 2 / 0 | 6 / 3 / 2 | 16.3 / 4.7 |
| (iii) push2: random input through 0–2 operators | 7 / 2 / 0 | 8 / 1 / 0 | 7 / 2 / 0 | 17.7 / 4.4 |
| (iii′) bank2: both arguments from random ≤2-operator terms on one row | 10 / 2 / 0 | 9 / 0 / 0 | 3 / 0 / 0 | 10.5 / 0.85 |
| (iii″) oelog3: the enumeration's own stored classes, size ≤3 | 4 / 0 / 0 | 7 / 1 / 0 | 3 / 0 / 0 | 9.8 / 1.4 |
| **(iv) bank2+strat2** | **3 / 0 / 0** | **3 / 0 / 0** | **0 / 0 / 0** | **5.0 / 0.55** |
| (v) reviewer's hand transforms | 7 / 2 / 0 | 7 / 1 / 0 | 6 / 2 / 1 | 26.3 / 8.3 |

- **Gain does not move.** It is 16.9–17.1× on S300 and 17.6–18.0× on EDGE-R, for every rule from 300 probes up. Table size converges to 1,736 keys and about 2,590 (key, output) pairs for every rule (`exp_audit.log`).
- **Seen-input, unseen-output defects are almost all of it.** Defects on the reference path (the AUD column of the logs) outnumber losses about 10 to 1, as in verify-quotients. Only 5 lost searches in all logs had a clean reference path; they were lost through a shorter equivalent program.
- **Why the program-shaped source works.** The remaining i.i.d. defects are the transforms a program produces and random lists do not:
  - `dedup_adj` under `caplen5`, which needs runs of equal elements;
  - `take3` of a constant prefix;
  - `zip_sub` of two equal lists, which needs correlated arguments. Only bank2 and oelog3 supply correlated arguments.
- **Unreached buckets.** Stratifying i.i.d. candidates never reaches 3 of the 140 bucket pairs (all-zero lists of length ≥4, constant lists of length ≥5), even with 200,000 candidates. Every program-shaped source reaches all 140 from 2,000 candidates (`buckets.log`). An unreached bucket gets no table entry, so it means "anything", which is safe.
- **First stratifier version, rejected.** It sampled uniformly among distinct values and made things worse as probes grew (push2+strat1d: 34 → 13 defects/1,000 at 1k → 10k, against 18 → 1 unstratified; `exp_audit_v1.log`). The reason is that it discards the source's frequencies: `take_n` rarely sees n in 1..5. The current rule keeps each bucket's own frequencies.
- **Cost.** bank2+strat2 at 1,000 probes takes 17.6 s to build, against 1.1 s for i.i.d. (one process on a loaded machine, `time_tables.log`), because it evaluates 20× more candidates.
- **No rule reaches zero defects reliably on long streams.** bank2+strat2 at 3,000 probes was defect-free on the 4,000-task stream in 4 of 10 seeds. Zero losses on 700 tasks is not soundness.

**2. Feedback (P2)** (`exp_feedback_p1.log`, `exp_feedback_p23.log`).

- **Real searches, replayed over 700 tasks, 2 seeds.** bank2+strat2 lost 0 at 1,000 and 3,000 probes, so feedback had nothing to remove. At 300 probes, losses went 5 → 4 with fallback-only feedback and 5 → 2 when every solved task is fed back. For i.i.d. at 1,000 probes: 10 → 9 and 10 → 4.
- **Audit stream.** Feedback cuts bank2+strat2 at 3,000 from about 0.55 to about 0.13 defects per 1,000 tasks after the first 1,000 tasks. That is 1.3 table updates per 4,000 tasks.
- **Cheapest guard.** "Unseen unless probed ≥10 times" removed nothing under the best rule, which already had 0 losses, and cut its gain from 17.0× to 13.8×: stratified probes leave many keys thinly probed. Under i.i.d. at 300 probes it took losses from 9 to 5. guard(30,1) took them to 0 at 12.5×. Verdict: keep the fallback as the guarantee. Feedback is a cheap optional extra; the guard does not pay with good probes.

**3. Merged products (P3)** (`exp_merged.log`, merged3 = sign × parity × order, 38 labels, 2 seeds, 600 searches).

| Probe rule | 1,000 | 3,000 | 10,000 | Gain |
|:--|:--|:--|:--|:--|
| i.i.d. | 100 | 42 | 18 | 21.8–25.1× |
| bank2+strat2 | 68 | 27 | 10 | 21.4–22.2× |
| hand | 84 | 34 | 10 | 21.4–24.0× |
| bank2+strat2, guard ≥10 probes | 38 | 7 | 6 | 11.6–14.7× |

The merged product buys about 22× against 17×, and still loses 1.7% of answers at 10,000 probes. verify-quotients needed 300,000 i.i.d. probes to reach zero. Leaving merged products out is supported.

**4. Slices (P4)** (`p4_slices.log`).

- **Reproduced.** The dependency scores match on three grids. The false-rejection counts match at the reviewer's seed; the exact expectation is 56.5 / 56.5 / 287.9 / 430.1 per 500 pairs.
- **The count depends on the slice set.** {−1, 0, 1, 2} is a worst case. Over 200 random 4-value slice sets, the median is 0 for every operator: zero in 114/200 sets for `div` and 125/200 for `mod`.
- **Joint probing is not always zero either.** At the same budget (100 random pairs instead of the 625-pair grid), `div` and `mod` have a median of 14.6 false rejections.
- **The principle holds.** A label-keyed table must be built from probes of the joint distribution.
- **The sound use of slices** is a table keyed on (label of a, value of b), built from joint probes. It is sound when `a` is probed over [−40, 40]: 0 of 1,384 entries are wrong. It is 9.4× larger than the label-keyed table (1,384 against 148 keys for b ∈ [−12, 12]), and it is narrower in only 42 entries, all at b ∈ {±1, ±2}.
- **The review's example needs no slices.** "x mod 2k is determined by x mod 2" is already deterministic in the joint parity table: key (a even, b even) gives {even}, key (a odd, b even) gives {odd}.
- **Where it pays, it is just a finer quotient.** In the 61-operator library, `take_n` keyed on clamp(n, 0, 5) turns 6 entries (1 deterministic) into 36 entries, all deterministic. That is a finer int quotient learned jointly, not a slice.

**5. Certification** (`exp_cert.log`).

- **Truth estimate.** U is the union of 10 tables × 30,000 probes plus an exhaustive enumeration E3. It has 1,736 keys.
- **71.5% of entries are deterministic** (1,242 of 1,736). By quotient: sign 62%, parity 70%, order 46%, caplen5 92%, lenmod2 71%, isempty 81%.
- **Tables.** 194 of the 366 (operator, quotient) tables are deterministic throughout, but 62 of those are trivial (one output label, so they filter nothing).
- **Filtering with only the deterministic entries of U** keeps 10.2× of 17.0× in gain: 60% of the factor, 78% of the log-gain above types-only (1.58×). Using only the fully deterministic tables keeps 3.25×.
- **Provably certifiable tier.** 35 of the 41 list-valued operators are length-regular (output length a function of input lengths). On those, the three length quotients give 104 tables, 68 of them deterministic. This tier alone gives 3.6×.
- **Exhaustive small scope.** E3 enumerates every list of length ≤6 over [−2, 2] and every list of length ≤10 over [−1, 1]: 107k unary probes and 610k list-pair probes, about 90 s. Used as the tables, it lost 0 answers at 16.9×. It contains every transition the 300,000 sampled probes found on its keys. E1 and E2, which are smaller scopes, lose 35 and 25 answers.
- **What this means for the design.** Exhaustion of a small scope is the cheapest route to near-complete tables, but it is a small-scope assumption, not a certificate, except on the length tier. About 40% of the factor rests on non-deterministic entries whose completeness is only tested, so it needs the fallback.

## 4. Supplied by hand

**The reviewer's.**
- **EXP D probes:** sorted, sorted-descending, abs, 2x, 2x+1, constant and equal-prefix transforms, matched to the `order`, `parity` and `sign` quotients. Dropping only the constant and equal-prefix transforms gives 14.6 misses.
- **EXP D tasks:** five edge rows that those transforms produce.
- **Feedback rule:** it also creates entries for unseen keys (48 rather than 55 without that).
- **Unequal budgets:** 150 against 1,000 probes.
- **Denominator:** 196 tasks kept, divided by 200.
- **EXP C:** the slice set {−1, 0, 1, 2} and a 625-pair joint grid against 100 slice probes.

**Mine.**
- The six quotients and the base value ranges.
- The 20× candidate factor, and bank depth 2.
- The EDGE-W templates (`tasksets.py`), written after the rules were fixed.
- No rule names an edge case.

## 5. Commands (in the work directory; the machine was shared and loaded)

| Table / number | Command | Log | Runtime |
|:--|:--|:--|:--|
| Reviewer EXP C, D; CHECK 3 | `python3 run_reviewer.py`; `python3 ../reviewer/verify_guard_fourier_slices.py` | `run_reviewer.log`, `reviewer_check3.log` | 2 s |
| EXP D varied | `python3 revD_vary.py` | `revD_vary.log` | 8.5 min |
| P1 searches, S300 (i, iii, v, first stratifier) | `python3 exp_main.py --taskset S300 --rules old-iid,iid,strat1,strat2,push1,push2,push3,push2+strat1,push2+strat2,hand,scalemix --M 100,300,1000,3000 --seeds 0,1,2 --procs 12 --tag main` (run with `probegen_v1.py`; equivalences in `check_v1_names.log`) | `exp_main_S300.log` | 51 min |
| P1 searches, new rules, edge sets | `bash run_v2.sh` | `exp_main_S300_v2.log`, `exp_main_EDGE-R.log`, `exp_main_EDGE-W.log` | 25 min |
| Defect streams | `python3 exp_audit.py --M 100,300,1000,3000 --seeds 10 --procs 5` | `exp_audit.log` (`exp_audit_v1.log`: first stratifier, includes 10k) | 14 min |
| Bucket reach; table cost | `python3 buckets.py`; `python3 time_tables.py 300 1000` | `buckets.log`, `time_tables.log` | 5 min |
| P2 | `python3 exp_feedback.py --parts 1 --procs 3`; `--parts 2,3 --best bank2+strat2 --procs 12 --p2rules iid,strat2,push2,bank2,oelog3,bank2+strat2,hand` | `exp_feedback_p1.log`, `exp_feedback_p23.log` | 3 + 18 min |
| P3 | `python3 exp_merged.py --rules iid,bank2+strat2,hand --M 1000,3000,10000 --seeds 0,1 --quots merged3 --guards 10 --sets S300 --procs 8` | `exp_merged.log` | 16 min |
| P4 | `python3 p4_slices.py` | `p4_slices.log` | 32 s |
| Certification | `python3 exp_cert.py --procs 6 --sets S300` | `exp_cert.log` | 21 min |

## 6. Not done / could not check

- **No proof of completeness.** "Certified" here means complete against a 300,000-probe union plus exhaustion of E3, not proven, except for the length-regular tier, whose length-regularity was itself checked on probes and not proven.
- **Automatic quotients not tested.** Quotients chosen automatically (verify-quotients §2.8) were not combined with the new probe rules.
- **Merged product only partly tested.** It was run on S300 only, and not with the merged product plus the three length quotients.
- **Small loss counts.** The searches total 700 tasks, so loss counts of 0–3 do not separate the better rules. The 4,000-task defect streams do.
- **Feedback replay assumption.** It assumes a task found by the static tables stays found after feedback. That holds because no feedback update added a label new to its domain (`domgrew` = 0 in `exp_feedback_p23.log`).
