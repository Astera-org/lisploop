# verify-quotients: rebuilding the experiments of `plan_v2c_audit.md` §2.3

Everything below was rebuilt from the review's prose; none of its code existed. Python 3.14, standard
library only, all seeds fixed. Scripts and logs are in
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/verify-quotients/`.
Nothing under `/home/tlh24/lisploop` was touched.

## 0. Bottom line

The core idea survives: pushing operators forward along small quotients, by one group-by on a probe table,
prunes a 61-operator bottom-up search by about 15× in candidates (3–60× per task), works as well for operators
never seen in a solution, and costs 180 ms to learn. Four things in the review do not survive as stated.

1. **"Zero misses" is a property of the task sample, not of the method.** The default "unseen abstract input
   → anything" does not cover a *seen* input with an *unseen* output. On 300 random tasks with i.i.d. probes the
   loss rate is 11% at 100 probes per operator, 0.3% at 1,000–3,000, and reaches 0 only at 10,000. For the
   merged product quotient the review recommends, it is 8% at 3,000 probes and 1.3% at 30,000.
2. **The soft ranking adds 3–5%**, not a separate effect. Almost all of the gain is the hard filter applied
   *before* a candidate is evaluated, mostly at the last size level.
3. **The backward bound alone is nearly vacuous.** Discarding classes after evaluation gives 1.5×. The gain
   does not grow with pipeline length (about 10–15× at every size from 3 to 6).
4. **The headline candidate ratio overstates the saving.** The filter does about 7 table look-ups per surviving
   candidate; end-to-end wall time improves 2× at size 5 and 4× at size 6, not 15×.

## 1. Verdict table

| # | Claim (review §2.3) | Verdict | Reproduced how far |
|:--|:--|:--|:--|
| Q2a | Tables prune a 61-op search, gains 1.5–26.5× | **REPRODUCED** | Direction, task ordering (Spearman 0.69 on the review's 8) and rough magnitude; mine are larger: geometric mean 14–17×, range 2.7–60× (one 613×) |
| Q2b | Works for operators never seen in a solution | **REPRODUCED** | Cold tasks 11–12× vs warm 16–26× in library order; order-averaged, cold 14–21× vs warm 15–26× |
| Q2c | Zero misses | **PARTLY** | 0/20, 0/20, 0/60, 0/40 on my task sets at 2,000 probes; 1/300 at 1,000–3,000 i.i.d. probes; 34/300 at 100 |
| Q2d | Flat Naive Bayes 6.5× worse than plain on a cold task | **PARTLY** | Direction yes; magnitude depends on seed and on how the order is used: T8 is 0.84× in one seed, 7.6× worse in the other; under cost-weighted use T8 is 144× worse and most cold tasks exceed the 3M cap |
| Q2e | Soft ranking by surprise contributes | **NOT REPRODUCED** | +3–5% on totals; within the last level it helps on some tasks and hurts on others |
| Q2f | 161 ms to learn 6 quotients × 61 operators | **REPRODUCED** | 180 ms at 2,000 probes per operator (150 ms of it is the group-by) |
| Q2g | Merged product quotient cuts stored classes 4–9× | **PARTLY** | 5.2× stored, 24× candidates, but 8 of 60 tasks lost at 2,000 probes |
| Q1a | Integer lumpability values and ordering | **REPRODUCED** | To three decimals, once "ring" is read as six operators, not four |
| Q1b | Sequence lumpability | **PARTLY** | Capped length is rank 1 of 5,475 (0.877 vs 0.857); the other three named values differ by 0.1 and rank 48–311 |
| Q4 | 26–127 valid guards collapse to one weakest guard | **REPRODUCED** | Same three terms, 47–151 valid guards, 0.48 ms; but 7 and 3 maximal guards on two of my three extra laws |
| Q3a | Column homomorphism: candidates 1.5–32×, stored 8–23× | **REPRODUCED** | Ordering and magnitude: stored 8.5–26×; candidates 2.9–19× with the review's design, 12–136× with mine |
| Q3b | Per-row quotients give only 1.0–1.2× | **PARTLY** | Much weaker than columns, but 1.6–5.6× candidates and 1.2–1.7× stored |
| Q3c | With div and mod the pruning is unsound | **REPRODUCED** | 117 of 120 random div/mod targets lost; concrete misses in §5 |
| Q5 | 11/20 reuse hits, 2.2–2.3× fewer candidates | **PARTLY (outline only)** | 7–11 hits of 20; 1.2–1.3× fewer candidates; the invariant index is beaten by index-free replay |

## 2. Q2: pushed-forward tables on a 61-operator library

### 2.1 Setup

**Library (61 operators, all total; `head`, `last`, `min_el`, `max_el` of the empty list are 0).**

- list→list (31): `inc_all dbl_all abs_all neg_all dec_all sq_all half_all`, `map_adj_add map_adj_sub
  map_adj_mul map_adj_min map_adj_max`, `filter_pos filter_neg filter_even filter_odd`, `sort sort_desc
  reverse shift1 tail init take2 take3 drop2`, `running_sum running_max running_min dedup_adj evens_idx
  odds_idx`
- list×list→list (6): `zip_add zip_sub zip_mul zip_min zip_max concat`
- list→int (9): `sum len head last min_el max_el count_pos count_even count_distinct`
- int→int (6): `inc dec dbl neg abs sq`; int×int→int (5): `add sub mul min max`
- int×list→list (4): `cons add_k mul_k take_n`

`map_adj_sub` is `xs[i+1] - xs[i]`; `shift1` rotates left by one; zips truncate to the shorter list.

**Tasks.** The review's 8, plus 12 drawn by a seeded random typed-term generator (8 unconstrained, 2 forced to
contain `map_adj_sub`, 2 forced to contain `dbl_all`). Each has 8 rows; lists have length 2–7, elements in
[−9, 9]. Leaves are the list inputs the reference uses. Degenerate tasks are rejected (fewer than 3 distinct
outputs, or an operator that is a no-op on these rows).

**Size** is the number of nodes. A **candidate** is one evaluation of an operator on argument classes over all
rows. **Stored classes** are those kept below the last size level (the review's RAM figures behave the same way:
1,561 for four different tasks).

**(i) Plain.** Bottom-up by size with observational-equivalence dedupe. Operator order within a level is the
library listing order. Because that order is arbitrary and visibly drives the result, every count is also given
as the mean over random operator orders (`plain_rnd`).

**(ii) Naive Bayes.** 23 Boolean all-row properties of (input, output), one Bernoulli Naive Bayes per operator,
Laplace 1, trained on 80 generated tasks with `map_adj_sub` and `dbl_all` excluded. The generating term counts
as the solution. Two complete uses:

- **U1**: operators are tried in posterior order within each size level. Complete because it is only an order.
- **U2**: Probe-style costs, `cost = max(1, round(−log2 q))` with `q` the normalised posterior, leaf cost 1,
  enumeration by total cost. Complete because every cost is finite. Capped at 3 million candidates.

**(iii) Abstract tables.** Six hand-listed quotients (see §2.8 for automatic ones):

| Quotient | On a list | On an int |
|:--|:--|:--|
| sign | (any < 0, any > 0) | sign |
| parity | (any even, any odd) | x mod 2 |
| order | (non-decreasing, non-increasing) | trivial |
| caplen5 | min(length, 5) | trivial |
| lenmod2 | length mod 2 | trivial |
| isempty | length = 0 | x = 0 |

Each operator is evaluated on 2,000 probes (lists of length 0–8, elements in [−9, 9]; ints in [−20, 20]) and
grouped per quotient into `abstract args → Counter(abstract result)`. An unseen argument tuple means "anything".
A class's abstract value is its per-row vector, per quotient. Per quotient and row, a Dijkstra pass gives the
least number of further nodes to reach the target's abstract value, where a binary step costs 1 plus the
smallest possible sibling (1 for a list, 2 for an int); the bound is the maximum over quotients and rows.
Size is unknown, so the search deepens the bound N = 1, 2, … and **every pass is counted**. A class of size s is
kept if s + bound ≤ N. A candidate is skipped *before evaluation* if every result the tables allow needs more
than N − s further nodes.

**(iv)** The same, with operators of the last level ordered by the least surprise
Σ_quotients mean_rows −log2 P(target's abstract value | operator, abstract arguments).

### 2.2 Main result

Command: `python3 q2_main.py --tag main` (68 s). `*` marks a task containing a held-out operator.

| Task | N* | plain lib | plain rnd | NB-U1 | NB-U2 | (iii) | (iv) | gain lib | gain rnd | stored plain → (iii) | found |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|:--|
| T1* `sum(map_adj_sub(sort(xs)))` | 4 | 22,356 | 15,100 | 10,484 | 20,701 | 1,403 | 1,403 | 15.9× | 10.8× | 884 → 666 | yes |
| T3 `sum(zip_mul(xs, shift1(xs)))` | 5 | 429,504 | 296,870 | 103,400 | 22,996 | 16,611 | 16,613 | 25.9× | 17.9× | 16,153 → 6,343 | yes |
| T4 `sum(filter_pos(zip_sub(xs, ys)))` | 5 | 942,517 | 645,287 | 155,445 | 925,930 | 55,156 | 57,578 | 16.4× | 11.2× | 34,065 → 23,674 | yes |
| T5 `len(filter_even(map_adj_add(xs)))` | 3 | 1,233 | 683 | 173 | 661 | 95 | 55 | 22.4× | 12.4× | 41 → 41 | yes |
| T6 `running_sum(reverse(inc_all(xs)))` | 4 | 18,831 | 15,313 | 6,147 | 8,217 | 330 | 314 | 60.0× | 48.8× | 919 → 153 | yes |
| T8* `dbl_all(sort(abs_all(xs)))` | 4 | 2,450 | 10,797 | 2,058 | 352,317 | 324 | 324 | 7.6× | 33.3× | 918 → 170 | yes |
| T9* `sort(dbl_all(filter_pos(map_adj_add(xs))))` | 5 | 47,956 | 148,017 | 30,721 | >3.0M | 12,070 | 12,070 | 4.0× | 12.3× | 14,936 → 5,828 | yes |
| T10* `dbl_all(sort(abs_all(map_adj_sub(xs))))` | 5 | 49,675 | 195,559 | 42,240 | >3.1M | 8,000 | 8,000 | 6.2× | 24.4× | 16,317 → 3,935 | yes |
| M1 `sq_all(reverse(shift1(xs)))` | 4 | 5,192 | 10,671 | 1,802 | 96 | 355 | 313 | 16.6× | 34.1× | 909 → 152 | yes |
| M2 `map_adj_mul(map_adj_add(tail(neg_all(xs))))` | 4 | 7,772 | 11,070 | 2,252 | 268,308 | 741 | 744 | 10.4× | 14.9× | 929 → 414 | yes |
| M3 `count_pos(map_adj_mul(dec_all(evens_idx(xs))))` | 4 | 26,317 | 15,068 | 1,574 | 15,082 | 1,664 | 1,387 | 19.0× | 10.9× | 887 → 785 | yes |
| M4 `dec(dbl(min_el(xs)))` | 4 | 26,013 | 10,684 | 3,034 | 917 | 858 | 795 | 32.7× | 13.4× | 928 → 351 | yes |
| M5 `take2(dec_all(filter_neg(drop2(xs))))` | 5 | 92,918 | 215,226 | 249,266 | 223,664 | 17,181 | 17,180 | 5.4× | 12.5× | 17,130 → 9,392 | yes |
| M6 `count_pos(running_min(tail(take3(xs))))` | 5 | 519,298 | 206,476 | 40,545 | 2,033 | 27,867 | 25,873 | 20.1× | 8.0× | 16,632 → 10,649 | yes |
| M7 `filter_odd(sort(map_adj_mul(xs)))` | 4 | 11,951 | 10,608 | 3,686 | 35,165 | 722 | 722 | 16.6× | 14.7× | 887 → 457 | yes |
| M8 `dec_all(dec_all(filter_pos(xs)))` | 4 | 4,238 | 16,129 | 6,317 | 35,824 | 561 | 561 | 7.6× | 28.7× | 931 → 335 | yes |
| Ma1* `map_adj_sub(running_min(zip_max(xs, ys)))` | 5 | 297,754 | 655,216 | 1,209,459 | >3.1M | 15,903 | 16,235 | 18.3× | 40.4× | 34,490 → 7,924 | yes |
| Ma2* `map_adj_sub(inc_all(map_adj_max(reverse(xs))))` | 4 | 7,249 | 16,035 | 30,427 | >3.1M | 648 | 679 | 10.7× | 23.6× | 938 → 354 | yes |
| Md1* `running_sum(filter_pos(half_all(dbl_all(xs))))` | 3 | 835 | 683 | 426 | 114 | 23 | 22 | 38.0× | 31.0× | 41 → 17 | yes |
| Md2* `sort_desc(dec_all(map_adj_mul(dbl_all(xs))))` | 5 | 90,563 | 211,545 | 211,791 | >3.0M | 8,269 | 8,268 | 11.0× | 25.6× | 16,749 → 4,127 | yes |

N* is the size at which plain finds the behaviour; several tasks have a shorter equivalent than the reference.
"gain lib" is plain lib / (iv); "gain rnd" is plain rnd / (iv).

Geometric means over the 20 tasks, with the second task seed (`--taskseed 1`) in brackets:

| Ratio to plain | all 20 | cold (8 [11]) | warm (12 [9]) |
|:--|--:|--:|--:|
| (iii), library order | 13.9× [16.7×] | 11.2× [11.7×] | 16.1× [25.9×] |
| (iv) soft operator order | 14.6× [17.2×] | 11.2× [12.1×] | 17.5× [26.5×] |
| (iii), both order-averaged | 17.5× [18.5×] | 21.4× [14.2×] | 15.3× [25.5×] |
| discard after evaluation only | 1.52× [1.54×] | 1.33× [1.15×] | 1.67× [2.22×] |
| NB-U1, library-order plain | 2.06× [2.14×] | 0.83× [2.29×] | 3.77× [1.98×] |
| NB-U1, order-averaged plain | 2.65× [2.52×] | 1.72× [3.12×] | 3.53× [1.93×] |
| table-derived order, no pruning (order-averaged plain) | 6.06× [5.74×] | 5.39× [5.26×] | 6.54× [6.37×] |
| stored classes, (iii) | 2.53× [2.79×] | 3.10× [2.33×] | 2.21× [3.48×] |
| stored classes, (iii) + one-step look-ahead | 9.09× [7.17×] | 10.4× [6.00×] | 8.30× [8.91×] |

The one-step look-ahead additionally drops a size N−1 class that no unary operator can take to the target.

**Against the review's own rows.** The review reports 9.4×, 26.5×, 12.8×, 15.7×, 6.6×, 1.8×, 3.5×, 1.5× for
T1–T10; I get 15.9×, 25.9×, 16.4×, 22.4×, 60.0×, 7.6×, 4.0×, 6.2×. The ordering largely agrees (Spearman 0.69); T6 is
the outlier, 60× for me against 6.6×. Mine are higher throughout. Two of the review's cells cannot be total
evaluation counts: T3 lists 85 candidates with 812 classes stored, and T5 lists 164 with 1,383. Creating a
stored class costs at least one evaluation, so those counts must exclude the lower levels. Counted that way
(last level only), my gains would be far larger than the review's, not smaller.

### 2.3 Naive Bayes and cold start

The held-out operators are ranked 52–58 of 61 by Naive Bayes on every task, as the review says.
"Seed 0" is the main run; "seed 1" is `--taskseed 1`.

| Task (cold operator at the root) | plain lib | plain rnd | NB-U1 | vs lib | vs rnd | NB-U2 |
|:--|--:|--:|--:|--:|--:|--:|
| T8, seed 0 | 2,450 | 10,797 | 2,058 | 0.84× | 0.19× | 352,317 (144× worse) |
| T8, seed 1 | 2,459 | 10,940 | 18,658 | **7.6× worse** | 1.7× worse | 368,883 (150× worse) |
| T10, seed 0 | 49,675 | 195,559 | 42,240 | 0.85× | 0.22× | >3.07M |
| Ma1, seed 0 | 297,754 | 655,216 | 1,209,459 | 4.1× worse | 1.8× worse | >3.08M |
| Ma2, seed 0 | 7,249 | 16,035 | 30,427 | 4.2× worse | 1.9× worse | >3.05M |
| Md2, seed 1 | 50,438 | 190,559 | 183,139 | 3.6× worse | 0.96× | >3.03M |

- The review's "6.5× worse on T8" reproduces as 7.6× in one seed and as a small *win* in the other. In seed 0
  the equivalent program `sort(dbl_all(abs_all(xs)))` is rooted at `sort`, which Naive Bayes ranks second.
- The 6.5× is measured against a lucky baseline: `dbl_all` is second in the library listing, so plain finds T8
  after 2,450 candidates where a random order needs 10,800. Against order-averaged plain, within-level Naive
  Bayes is never more than 1.9× worse here, because an order can cost at most one level.
- Under cost-weighted use the damage is much larger than the review states: 5 of 8 cold tasks (6 of 11 in the
  second seed) exceed the 3 million cap, which is at least 10–420× more than plain.
- With 80 training tasks for 61 operators, three warm operators (`zip_add`, `mul`, `max`) also had zero counts.

### 2.4 Where the gain comes from

`python3 q2_sweep.py` (60 tasks: the 20 above plus 40 more random ones; 71 s). Candidate gain is order-averaged.

| Configuration | misses | candidates | [min, max] | stored | stored + look-ahead | wall |
|:--|--:|--:|:--|--:|--:|--:|
| types only (a constant quotient) | 0 | 1.66× | [1.0, 3.2] | 1.14× | 1.14× | 1.6× |
| 1 quotient: sign | 0 | 5.96× | [3.0, 20] | 1.33× | 1.80× | 2.3× |
| 1: parity | 0 | 6.37× | [3.2, 19] | 1.52× | 2.09× | 2.6× |
| 1: order | 0 | 3.87× | [1.5, 11] | 1.29× | 1.32× | 1.7× |
| 1: caplen5 | 0 | 5.34× | [2.5, 21] | 1.88× | 1.88× | 3.7× |
| 1: lenmod2 | 0 | 2.78× | [1.9, 4.6] | 1.14× | 1.14× | 2.2× |
| 1: isempty | 0 | 2.78× | [1.4, 5.8] | 1.58× | 1.59× | 2.6× |
| 3: sign + parity + order | 0 | 11.3× | [3.7, 22] | 1.78× | 6.17× | 1.9× |
| 3: caplen5 + lenmod2 + isempty | 0 | 6.06× | [2.6, 22] | 2.07× | 2.09× | 3.5× |
| 3: sign + order + caplen5 | 0 | 12.6× | [3.3, 47] | 2.19× | 4.36× | 2.5× |
| **6: all** | **0** | **15.7×** | [3.8, 50] | 2.32× | 8.37× | 2.1× |
| 1 merged: sign × parity × order (38 states) | **8** | 23.9× | [4.1, 88] | 5.16× | 9.47× | 2.4× |
| merged + 3 length quotients | **8** | 28.2× | [4.1, 140] | 5.40× | 10.4× | 2.2× |
| product of all six (162 states) | **11** | 27.5× | [4.7, 112] | 6.01× | 9.91× | 1.7× |
| 6: all, abstract value on 1 row of 8 | 0 | 5.87× | [1.8, 19] | 1.59× | 1.88× | 4.4× |
| 6: all, 2 rows | 0 | 9.51× | [2.1, 34] | 1.80× | 3.34× | 5.2× |
| 6: all, 4 rows | 0 | 12.2× | [2.2, 46] | 2.00× | 5.38× | 3.9× |
| 6: all, 200 probes | **2** | 15.9× | [3.9, 52] | 2.39× | 8.35× | 2.1× |
| 6: all, 20,000 probes | 0 | 15.7× | [3.9, 50] | 2.32× | 8.37× | 2.1× |
| 6: all, enriched pool, 2,000 | 0 | 15.7× | [3.8, 50] | 2.32× | 8.37× | 2.1× |

- **Number of quotients:** 1 gives 2.8–6.4×, 3 gives 6–13×, 6 gives 15.7×. Types alone give 1.7×.
- **The abstract value is a per-row vector.** With one row the six quotients give 5.9×; with eight, 15.7×. The
  method is in effect a 48-coordinate signature match predicted from tables.
- **The pre-evaluation filter is the method.** Discarding only after evaluation gives 1.5× (§2.2). The backward
  bound rarely exceeds 1–2, because a binary operator with an unconstrained sibling connects almost any abstract
  value to any other.
- **Soft ranking** changes the total by 3–5%. Within the last level it moved the hit from 220th to 2,642nd on T4
  and from 9th to 341st on Ma1, and from 303rd to 26th on M3.
- **The table-derived operator order with no pruning** gives 6× over order-averaged plain, against 2.6× for
  Naive Bayes, and holds on cold tasks (5.4×). That part of the review's claim is sound and cheap.

### 2.5 Pipeline length

`python3 q2_length.py` (40 single-input chains, 10 per length; 27 s). No misses.

| Size found | tasks | plain (order-avg.) | candidate gain | stored | stored + look-ahead | wall |
|--:|--:|--:|--:|--:|--:|--:|
| 3 | 13 | 625 | 14.4× | 1.7× | 4.7× | n/a |
| 4 | 14 | 12,107 | 11.1× | 1.7× | 5.7× | 1.3× |
| 5 | 6 | 240,147 | 11.6× | 1.8× | 7.3× | 2.0× |
| 6 | 5 | 3,250,313 | 15.6× | 2.7× | 8.9× | 4.2× |

The candidate gain is flat with length: the filter removes roughly one level of branching and no more. Only the
wall-time gain grows. Wall times compare complete last levels on both sides.

### 2.6 Soundness

`python3 q2_sound.py --tasks 300` (350 s on 12 processes). A miss is a task not found at the size plain finds it.
"Audit" counts tasks whose reference program uses a transition absent from the tables.

| Tables | probes | pairs seen once | **misses / 300** | audit | candidate gain |
|:--|--:|--:|--:|--:|--:|
| 6 factored, i.i.d. | 100 | 248 | **34 (11.3%)** | 134 | 17.6× |
| | 300 | 139 | 4 (1.3%) | 48 | 16.9× |
| | 1,000 | 63 | 1 (0.3%) | 13 | 17.0× |
| | 3,000 | 37 | 1 (0.3%) | 10 | 17.0× |
| | 10,000 | 22 | 0 | 1 | 17.0× |
| | 30,000 | 1 | 0 | 1 | 17.0× |
| 6 factored, enriched | 100 | 237 | 23 (7.7%) | 86 | 18.0× |
| | 300 | 98 | 5 (1.7%) | 35 | 16.8× |
| | 1,000 and up | 57 → 0 | 0 | 3 → 0 | 17.0× |
| 6 factored, i.i.d., guarded | 3,000 | 0 | 1 (0.3%) | 9 | 16.9× |
| merged sign × parity × order, i.i.d. | 3,000 | 3,063 | **24 (8.0%)** | 95 | 23.4× |
| | 30,000 | 5,659 | 4 (1.3%) | 21 | 21.4× |
| | 300,000 | 6,145 | 0 | 2 | 21.2× |
| merged, guarded | 3,000 | 0 | 1 (0.3%) | 8 | 7.6× |
| | 30,000 | 0 | 0 | 2 | 12.8× |
| merged + 3 length, enriched | 3,000 | 3,722 | 15 (5.0%) | 67 | 27.7× |
| | 30,000 | 6,880 | 1 (0.3%) | 10 | 27.9× |

**Cause.** Of the 115 (configuration, task) misses, 113 coincide with the same defect on the reference path: an
abstract argument tuple the probes *did* see, with an abstract result they did not. The review's default covers only unseen tuples.
Examples:

- `take3` under `order`: a non-increasing list whose first three elements are equal becomes constant. Seen 0
  times in 3,000 probes; loses `take3(sort_desc(abs_all(shift1(xs))))`.
- `zip_mul` under `sign`: two lists with only negatives and zeros, zeros aligned, give all zeros. This transition
  is on the reference path of the review's own T3 in my main run; the search survived it because the bad
  prediction still left a route to the target.
- `head` under `sign`: a list of negatives and zeros whose head is zero.

The remaining two have a clean reference path. In both, plain finds the behaviour through a shorter equivalent
program (size 4 against a reference of size 5), and the pruned search fails at that smaller size.

The "guard" is my addition, not the review's: treat a tuple as unseen unless probed at least 30 times with every
recorded result seen more than once. It removes most misses at a cost in gain for sparse tables.

A second hole exists and was not hit: the bound assumes every abstract value a sibling can take was seen in some
probe. That holds for the six small quotients and not for products.

### 2.7 Cost

`python3 q2_tables_cost.py`. Milliseconds, best of 5, 61 operators.

| Quotients | probes | operator evaluation | quotients + group-by | total | entries |
|:--|--:|--:|--:|--:|--:|
| 6 hand-listed | 200 | 2.7 | 15.3 | 18.2 | 1,671 |
| | 2,000 | 27.9 | 149.8 | **180.2** | 1,736 |
| | 20,000 | 317.7 | 1,487.8 | 1,830.3 | 1,736 |
| merged + 3 length | 2,000 | 28.1 | 163.9 | 194.4 | 4,634 |
| | 20,000 | 318.3 | 1,641.5 | 1,983.9 | 7,374 |

Per-task backward distance tables take 0.8 ms. The review's 161 ms and 275 ms correspond to about 2,000 probes
per operator, which is the regime where the merged quotient loses 8% of tasks.

Search-time work, summed over the 20 main tasks: plain 2.60 million evaluations; (iv) 0.17 million evaluations
plus 1.25 million table look-ups. Wall time is 2.0× better (geometric mean, complete levels).

### 2.8 Quotients chosen automatically

`python3 q2_auto.py` (64 s). `autoquot.py` enumerates 3,233 list partitions of the form
`q(r(g(xs)))` (g: identity or one of 31 list→list operators; r: one of 9 reductions; q: an integer term of up to
3 nodes over `+ * mod < = abs sgn min`), scores each by mean lumpability over the 37 list-valued operators, and
walks down the ranking skipping any candidate whose normalised mutual information with an accepted one is 0.5 or
more. Each is paired with the int quotient it best predicts through the reductions.

Selected, in order: `min(len(map_adj_add xs), 5)`, `min(sum(abs_all xs), 4)`, `len(xs) mod 2`,
`sgn(head(init xs))`, `count_pos(abs_all xs) mod 5`, `sgn(max_el(inc_all xs))`.

| Quotients | misses / 60 | candidate gain | stored | stored + look-ahead |
|:--|--:|--:|--:|--:|
| hand-listed 6 | 0 | 15.8× | 2.32× | 8.37× |
| automatic top 1 | 0 | 5.7× | 1.83× | 1.93× |
| automatic top 3 | 0 | 7.2× | 2.03× | 2.33× |
| automatic top 6 | 0 | 10.7× | 2.03× | 2.84× |
| automatic top 10 | 0 | 12.0× | 2.03× | 3.85× |

So the method does not depend on the hand list: automatic selection keeps about two thirds of the gain. The
hand list is still better, and the difference is the sign, parity and order patterns, which the enumerated pool
cannot express.

## 3. Q1: lumpability

### 3.1 Integers

`python3 q1_int.py --size 7` (1.5 s). Grid x, y ∈ [−10, 10], floor division, division by zero skipped. Pool:
47,906 terms → 6,762 distinct functions → **1,109 distinct partitions** with 2–6 blocks. `(3x+1) mod 4` and
`x mod 4` are one candidate by construction.

| Quotient | pool term | {+,−,*,neg} | six ops | all eight | rank by 4 / 6 / 8 | review |
|:--|:--|--:|--:|--:|:--|:--|
| mod 5 | `(mod x 5)` | 1.000 | **0.888** | 0.714 | 4 / 2 / 30 | 0.888 |
| mod 4 | `(mod x 4)` | 1.000 | **0.876** | 0.717 | 3 / 3 / 29 | 0.876 |
| mod 3 | `(mod x 3)` | 1.000 | **0.861** | 0.696 | 2 / 6 / 43 | 0.860 |
| parity | `(mod x 2)` | 1.000 | **0.833** | 0.699 | 1 / 13 / 41 | 0.833 |
| sign | `(sgn x)` | 0.747 | **0.832** | **0.772** | 59 / 14 / **1** | 0.830, 0.772 |
| mod 6 | `(mod x (+ 1 5))` | 1.000 | 0.895 | 0.751 | 5 / 1 / 3 | not named |
| x = 1 | `(= x 1)` | 0.117 | 0.302 | 0.243 | 737 / 690 / 702 | 0.30–0.48 |
| \|x\| < 2 | `(= x (sgn x))` | 0.427 | 0.480 | 0.407 | 330 / 399 / 380 | 0.30–0.48 |
| even or negative | `(mod (+ x (abs x)) 4)` | 0.219 | 0.356 | 0.286 | 572 / 598 / 622 | 0.30–0.48 |

The review's "ring lumpability" is the mean over **six** operators, {+, −, *, neg, max, min}. Over the four ring
operators every `mod k` scores exactly 1.000 and they tie. With that reading the numbers match to three decimals,
which also means the review's experiment was real and used this grid.

Top 15 over all eight operators: `(sgn x)` 0.772, `(+ (sgn x) (< 5 x))` 0.751, `(mod x 6)` 0.751,
`(+ (sgn x) (< 4 x))`, `(+ (sgn x) (< 3 x))`, `(+ (sgn x) (< 2 x))`, `(< x 0)` 0.745, `(+ (sgn x) (= x 1))`,
`(+ (sgn x) (sgn (+ x 5)))`, `(* (sgn x) (mod x 3))` 0.737, then four more sign refinements and
`(+ (sgn x) (= x 2))` 0.728. Top 15 over the six: mod 6, mod 5, mod 4, then `(+ (sgn (abs x)) (mod x 5))`
0.873, `(mod x (+ 5 (= x 5)))` 0.864, mod 3, and further one-point perturbations of mod 5 and mod 4, with parity
13th and sign 14th. Full lists are in `q1_int_size7.log`.

Two cautions. In the four- and six-operator rankings most of ranks 4–15 are **perturbed copies** of the winners
(a congruence with one value split off), scoring within 0.02–0.09 of the clean quotient; a top-k cut returns the
same idea many times unless term size or a diversity rule breaks ties. And "sign is highest overall" holds for floor division on this grid; with
truncating division sign is 4th (0.733), and on a [−20, 20] grid it is 2nd.

### 3.2 Sequences

`python3 q1_seq.py` (88 s). 15 operators: `reverse sort inc_all dbl_all neg_all abs_all running_sum tail take3
map_adj_add map_adj_sub filter_pos filter_even zip_add concat`; 1,500 probes each; lists of length 0–8. Pool as
in §2.8 with q up to 4 nodes: 161,568 raw candidates → **5,475 partitions**.

| Quotient | mine | exact ops | rank / 5,475 | review |
|:--|--:|--:|--:|:--|
| capped length `(min (len xs) 5)` | **0.877** | 10 / 15 | **1** | 0.857, 9/15 |
| length mod 2 | 0.707 | 8 / 15 | 136 | 0.817, 10/15 |
| is-empty | 0.786 | 10 / 15 | 48 | 0.673 |
| all-even | 0.590 | 6 / 15 | 311 | 0.688 |
| all-nonnegative | 0.527 | 4 / 15 | 615 | not named |
| head = 2 | 0.313 | 2 / 15 | 3,393 | 0.24–0.49 |
| sum > 5 | 0.418 | 2 / 15 | 1,694 | 0.24–0.49 |
| max < 3 (my distractor) | 0.603 | 4 / 15 | 271 | — |

Top 15 (with `min` in the grammar): `(min (len xs) 5)` 0.877, `(min (len (map_adj_add xs)) 5)` 0.868,
`(min (len xs) 4)` 0.867, `(min (len (drop2 xs)) 5)` 0.865, `(min (len (map_adj_add xs)) 4)` 0.859,
`(len (take3 xs))` 0.853, then nine more caps and residues of the length of `xs` or of a shortened copy of it.
**All fifteen are the length.**

- Capped length is found and ranked first, as claimed. It needs `min` in the candidate grammar, which the
  integer grammar I was given lacks; without it the winner is `(len (take3 xs))`, a cap at 3.
- Of the top 100, 39 are the length and the rest are count-of-distinct-values and small-magnitude predicates
  (`(< (count_distinct xs) 2)`, `(< (sum (abs_all xs)) 3)`). No parity or sortedness quotient appears. The first
  sign-like one, `(sgn (max_el xs))`, is 78th without `min` and outside the top 100 with it. All-even is 311th,
  and my distractor "max < 3" outranks it (`q1_seq_top100.log`).
- The 2-bit sign, parity and order patterns used in Q2 are not expressible in the enumerated pool at all. Scored
  directly they get 0.745, 0.799 and 0.699.
- **The averaging convention decides the outcome.** When α(f(x)) is constant I score 0. Scoring it as "exactly
  predictable" (1) puts fifteen vacuous predicates such as `(< (len (evens_idx xs)) 5)` at the top with 0.933.

## 4. Q4: weakest guard by bitset maximality

`python3 q4_guards.py` (6 s). 32 rows, a, b ∈ [−6, 6]. Pool: 22 arithmetic terms of up to 3 nodes over a, b, 0, 1
with + − *; 1,936 guards with <, <=, =, != → **302 distinct non-trivial masks** (the review has 439).

| Law | agrees on | valid guards | maximal | weakest guard(s) | guards sharing the mask |
|:--|--:|--:|--:|:--|--:|
| `max(a,b) = a` | 20/32 | 49 | **1** | `(<= b a)` | 16 |
| `div(a*b, b) = a` | 31/32 | 151 | **1** | `(!= b 0)` | 40 |
| `abs(a+b) = abs(a)+abs(b)` | 16/32 | 47 | **1** | `(<= 0 (* a b))` | 3 |
| `max(a,0) = a` | 23/32 | 60 | **1** | `(<= 0 a)` | 25 |
| `div(a,b)*b = a` | 17/32 | 22 | **7** | `(= (* a a) (* b b))`, `(= (* a b) (- 0 a))`, `(= a (* a b))`, `(= 1 (* b b))`, … | 1–4 |
| `mod(a,b) = a` | 11/32 | 10 | **3** | `(< (* a a) (* a b))`, `(<= (* a a) (- 0 a))`, `(< (* a a) b)` | 1–5 |

Bitset time for all six laws: **0.48 ms**. The review's three laws reproduce exactly, terms included.

The uniqueness is close to a tautology: one maximal guard exists exactly when some guard in the pool has the
law's agreement mask. Over 20 random row sets of 32 rows that held 20/20 times for the first four laws, 0/20 for
divisibility (0–8 maximal guards) and 4/20 for the `mod` law (1–4). With 16 rows, 5 of 20 row sets had no row
with b = 0, so the `div` law needed no guard at all, and the shortest term for the `abs` law was the expected one
in only 10 of 20.

## 5. Q3: column homomorphisms

`python3 q3_poly.py` (15 s). 32 rows, x, y ∈ [−9, 9]; leaves x, y, 0, 1; + and * enumerated up to commutativity.
Domains: F_2 on 12 rows (16 states), F_3 on 4 rows (81 states), F_5 on 3 rows (125 states), the F_3 and F_5 rows
chosen with distinct residue pairs. Closure, tables and forward DP take 65–143 ms once; the backward DP 13–24 ms
per target. The DP's lower bound sets the first size tried; every deepening pass is counted.

| Target | size | plain cands (stored) | filter at every level | cand gain | filter at last level only (1 pass) | cand gain | stored | **stored gain** |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| A2 `(x+x)*(y+1)` | 7 | 2,047 (127) | 15 | 136× | 108 | 19.0× | 8 | **15.9×** |
| A3 `x*y + x - y` | 7 | 860 (127) | 20 | 43× | 149 | 5.8× | 15 | **8.5×** |
| A4 `(x+y)*(x-y) + 1` | 9 | 6,101 (595) | 487 | 12.5× | 2,090 | 2.9× | 62 | **9.6×** |
| A8 `(x+y)^2 - x*y + 1` | 11 | 35,601 (3,147) | 695 | 51× | 8,388 | 4.2× | 119 | **26.4×** |
| A11 `(x*y + x + 1)*(y - x)` | 11 | 68,023 (3,147) | 2,206 | 31× | 16,938 | 4.0× | 333 | **9.5×** |
| A12 `2*(x^2 + y^2) - x*y` | 13 | 439,253 (17,609) | 13,812 | 32× | 97,005 | 4.5× | 1,229 | **14.3×** |

The review reports stored gains of 19.8, 8.2, 9.4, 22.6, 10.2, 22.9 and candidate gains of 32.2, 4.6, 2.8, 3.2,
1.5, 7.4. Its plain counts (1,898; 492; 4,192; 24,912; 61,840; 403,822) are close to mine, so this experiment
was evidently run much as I ran it. Its design filters before evaluation on the last level only; that column of
mine matches its candidate gains. Filtering at every level, which the exact homomorphism allows, is 3–10× better
again. A11 is found at size 11, not 13. A second row seed gives stored gains of 8.3–24.8×.

**Wall time** (A12, best of 3): plain 625 ms; pruned 800 ms when every pair of abstract buckets is tested;
436 ms with the last-level join. That is 1.43× faster (1.53× with the second row seed; the review: 1.7×). The
crossover is at size 11 (A8 1.1×, A11 1.4×); at sizes 7–9 the per-target DP makes the pruned search 4–8× slower.
Absolute times moved by up to 1.6× between runs of the same script (one run gave 387, 503 and 277 ms); the
ratios did not.

**Per-row negative.** The same primes applied to 19 single rows give candidate gains of 1.6–5.6× and stored
gains of 1.2–1.7×. The review says 1.0–1.2×. Columns are far better, as it claims; per-row is less useless than
it claims.

**Exactness and the G2 boundary.** `python3 q3_g2.py --n1 200 --n2 120` (10 s).

- G1: 200 random polynomial targets, **200 found at the plain size, 0 misses**.
- G2 (G1 plus floor `div` and `mod`), 120 random targets of true size 3–7 that need `div` or `mod`: the ring
  automaton **loses 117 (98%)**. For 104 the target's abstract value is not a state of the automaton at all.
  For 13 it is, and the search still fails at the true size.
- Concrete misses: `(div (neg x) (neg (+ 1 1)))`, true size 5, is unreachable for the automaton.
  `(- x (mod y (+ 1 1)))`, true size 7, has DP bound 7 and is not found at 7. `(mod x (+ 1 (* y y)))`, true
  size 7, DP bound 5, is not found at 7. The six printed examples are all found when the bound is relaxed by 2.
- lump(mod 2; div) = 0.05 and lump(mod 3; div) = 0.06, exactly the review's figures; sign is 1.00 on *, max, min
  and 0.69 on div (§3.1).

## 6. Q5: reuse, in outline only

`python3 q5_reuse.py` (6 s). Reproduced in outline; not a faithful rebuild.

**Synonyms.** Jaccard overlap of table supports recovers the families, with higher values than the review's:
`map_adj_sub` ≈ `map_adj_mul` 0.79, `map_adj_add` 0.78, `tail` 0.76, `init` 0.76, `map_adj_min` 0.72;
`filter_pos` ≈ `filter_neg` 0.89, `filter_odd` 0.82, `filter_even` 0.82; `zip_add` ≈ `zip_sub` 0.84, `zip_max`
0.82, `zip_min` 0.82, `zip_mul` 0.76, `concat` 0.17; `sum` ≈ `last` 0.90, `head` 0.90, `min_el` 0.86. Against
seven hand-listed families, 69% of top-1 same-type neighbours are family members.

**Reuse.** Streams of 20 three-operator tasks: 9 base, 5 repeats on fresh inputs, 6 siblings (one operator swapped
within a hand-listed family). Five streams, pooled:

| Method | hits / 100 | candidates vs abstract search alone |
|:--|--:|--:|
| B: replay every earlier solution first, no index | 25 (all 25 repeats) | 1.31× fewer |
| C: replay only solutions with the same all-row signature | 19 | 1.22× |
| D: C plus one-operator synonym variants | 26 | 1.30× |
| E: B plus synonym variants of all earlier solutions | 41 (25 repeats + 16 of 30 siblings) | 1.17× |

- Hit counts of 7–11 per stream of 20 match the review's 11 of 20.
- The 2.2× does not reproduce. 11 free tasks out of 20 equal-cost tasks is 20/9 = 2.22 by arithmetic; with real,
  unequal costs and the Q2 search already cheap, the saving is 1.2–1.3×.
- The index is not what produces the hits. Replaying everything costs at most 60 candidates here and gets every
  repeat; the all-row signature changed on fresh inputs for 6 of 25 repeats.

## 7. Choices the review left open

| Open point | Chosen | Second choice shown |
|:--|:--|:--|
| Operator list | 61, listed in §2.1 | — |
| `shift1`, `map_adj_sub` direction | rotate left; `xs[i+1] − xs[i]` | — |
| Partial operators | totalised to 0 | — |
| Task rows | 8; lengths 2–7; values ±9 | second task seed |
| Size, candidate, stored classes | nodes; one operator evaluation; classes below the last level | — |
| Plain's operator order | library order | mean over random orders |
| Unknown target size | deepen the bound, all passes counted | last pass alone (`abs1`, about 7% less) |
| Rows in the abstract value | per-row vector over all 8 | 1, 2, 4 rows |
| Combining quotients and rows | maximum of independent bounds | merged products |
| Sibling of a binary step | any abstract value, least size by type | — |
| Probes | 2,000 i.i.d. per operator | 100–300,000; enriched pool |
| Naive Bayes use | within-level order | cost-weighted; prior-only for unseen operators |
| Naive Bayes training labels | the generating term | — |
| Soft ranking | per operator, least surprise | per candidate bucket |
| Lumpability average | arithmetic mean, constant output = 0 | pooled entropies; constant output = 1 |
| Integer grid, division | [−10, 10]², floor | [−20, 20]²; truncating |
| Sequence candidate grammar | q ∘ reduction ∘ optional operator | with and without `min` |
| Guard pool | terms ≤ 3 nodes, 4 comparators | 16 / 32 / 64 rows, 20 row sets |
| Q3 rows per prime | first rows with distinct residue pairs | second seed |

## 8. What was supplied by hand

This is the list to check before integrating the idea.

- **The six quotients.** Three of them (the 2-bit sign, parity and order patterns) cannot be produced by the pool
  I enumerated, and their expressible analogues rank 300–600 by lumpability. Automatic selection keeps 10.7× of
  15.8×.
- **The pairing across types.** Sign on lists is paired with sign on ints, parity with parity. That pairing is
  what makes `sum`, `head` and `len` informative, and I wrote it by hand. `autoquot.py` picks it by
  cross-lumpability, and that is my construction, not the review's.
- **The candidate grammar for sequence quotients**, including `min`, and the redundancy rule in the automatic
  selection. Without a redundancy rule the top 15 are all the length.
- **The probe distribution.** Lengths 0–8 put empty and one-element lists in the probes; those are where
  filters and adjacent maps behave differently. Fewer or narrower probes turn directly into lost tasks.
- **The Naive Bayes feature list** (23 properties) is hand-written, as in the literature.
- **The convention that a constant abstract output scores 0.** The opposite convention ranks vacuous predicates
  first.
- **Q3's rows** were chosen to have distinct residues, which gives the full 81 and 125 states.
- **Q5's operator families** are hand-listed; they define what counts as a sibling.

Other things that surprised me:

- The review's Q1 and Q3 numbers reproduce closely enough that those experiments clearly existed. Its Q2 table
  does not hang together (candidate counts below stored-class counts; 4-operator tasks cheaper than 3-operator
  ones), so I could match its direction and range, not its rows.
- The gain is almost independent of pipeline length and strongly dependent on the number of example rows.
- The table-derived operator order, with no pruning at all, beats Naive Bayes by 2× and is immune to cold start.
  That is the cheapest part of the proposal and the best supported.

## 9. Commands and files

All run from the scripts directory; logs have the same stem as the script.

| Experiment | Command | Time |
|:--|:--|--:|
| Q2 main | `python3 q2_main.py --tag main` → `q2_main.log`, `q2_main.json` | 68 s |
| Q2 second seed | `python3 q2_main.py --tag seed2 --taskseed 1` → `q2_main_seed2.log` | 102 s |
| Q2 quotients, rows, probes | `python3 q2_sweep.py --procs 12` → `q2_sweep.log` | 71 s |
| Q2 length | `python3 q2_length.py --per 10 --procs 6` → `q2_length.log` | 27 s |
| Q2 soundness | `python3 q2_sound.py --tasks 300 --procs 12` → `q2_sound.log` | 350 s |
| Q2 table cost | `python3 q2_tables_cost.py` → `q2_tables_cost.log` | 20 s |
| Q2 automatic quotients | `python3 q2_auto.py --procs 10` → `q2_auto.log` | 64 s |
| Q1 integers | `python3 q1_int.py --size 7` (also `--size 5`, `--trunc`, `--G 20`) → `q1_int_*.log` | 1.5 s |
| Q1 sequences | `python3 q1_seq.py` (also `--top 100` → `q1_seq_top100.log`) → `q1_seq.log` | 88 s |
| Q4 | `python3 q4_guards.py` → `q4_guards.log` | 6 s |
| Q3 | `python3 q3_poly.py` (also `--seed 1 --skip-perrow`) → `q3_poly.log`, `q3_poly_seed1.log` | 15 s |
| Q3 exactness / G2 | `python3 -u q3_g2.py --n1 200 --n2 120` → `q3_g2.log` | 10 s |
| Q5 | `python3 -u q5_reuse.py` → `q5_reuse.log` | 6 s |

Shared modules: `seqlib.py` (operators, quotients, tables), `q2search.py` (plain, pruned, Naive Bayes,
cost-weighted search), `q2tasks.py`, `q2common.py`, `q3lib.py`, `autoquot.py`.

Not done: the review's 44-state Merge-and-Shrink with a shrink step (I used the plain product), CEGAR
refinement, and a faithful Q5. Wall times are single runs on a shared machine and moved by up to 1.6× between
runs; the ratios were stable.
