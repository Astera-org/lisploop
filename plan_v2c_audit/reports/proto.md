# proto — measurement probe for a factored (base × column × class) store

Agent `proto`. Standalone SBCL instrument; it does not load or modify anything under `/home/tlh24/lisploop`.
Everything is seeded; counts are deterministic and timings vary by a few percent between runs. Every number below is copied from a log in `proto/logs/`.

## 0. Bottom line

- **Lift as change of base works on these tasks.** One generic procedure and one 12-operator grammar solved all 15 sequence tasks, each verified 200/200 on held-out examples with longer sequences. That includes my versions of the four tasks the kernel times out on (map-adjacent, positions, scan, shift-seq), among them the two `:spec` signatures that take a function argument `f`.
- **Across 9 example sets, 134 of 135 runs are 200/200.** The one miss (map-adjacent with `f`, seed 9) is an example set with no information about argument order: its only examples with the non-commutative operator have a single element.
- **Cost.** Between 3 and 703,183 candidate columns and under 0.5 s for the first-order tasks. Map-adjacent with a function argument (a size-10 term) took 8.5 M candidates and 5 s.
- **Guard splits are the weak point.** Nested splits overfit: tried at every level they give impostors (rotate-left 2 of 8 sets, map-adjacent-`f` 5 of 8). As a last resort at budget end they gave one more (map-adjacent-`f` under the 15-operator grammar). Accepting a one-guard split only after every smaller single term is excluded changed no outcome but cost 35 to 1,100 times more candidates.
- **Scalar folds are outside pure base change.** Sum, alternating sum and Horner fail without an added `fold` form whose step is found by generate-and-test over a class bank (cheap here: at most 157 fold programs tried).
- **Memory, not time, is the wall for exhaustive enumeration.** Throughput is about 2 M candidates/s (60 to 65 M cells/s), 452 bytes per stored class at 32 rows. By extrapolation, 24 GB is used up after roughly 4 minutes (G1, size 16), 8 minutes (G2, size 11) or 1 minute (G3, size 10), and the sizes that 1 h or 10 h of time alone would reach need 0.2 to 2.4 TB.
- **Dedupe helps polynomials much more than the richer grammars.** It cuts growth per unit of size from ×9.3 to ×3.3 for {+ − * neg}, but only from ×13.6 to ×7.3 once div, mod, max, min are in (30 to 40 % of candidates are still new classes).
- **Inverses from functional dependencies come out as predicted,** once the grid boundary is padded: `+` gives `(- c b)`, `*` gives guard `(not (= b 0))` with `(div c b)`. `max` is not "nothing": it has a guarded partial inverse, `(< b c)` with `a = c`.
- **Laws from collisions are sound but do not converge to a small basis.** Commutativity, associativity, the identities, x·0, double negation and distributivity are all derivable by size 7, with 0 false laws at 8 or more probe rows. But the kept set grows about ×2.8 per size (105 at size 7, 8,889 at size 12, 27,394 when the 60 s ended inside size 13) and pruning then dominates run time.

## 1. Files, commands, environment

Directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/proto/`

| file | content |
|---|---|
| `tg-probe.lisp` | the whole instrument (one file, 874 lines) |
| `run.sh` | driver: `sbcl --dynamic-space-size 10GB --noinform --non-interactive --load tg-probe.lisp --eval "(tg::main :X)" > logs/X.log 2>&1` |
| `check-seed9.sh` | prints the training examples of the one failing example set |
| `logs/d.log`, `dseeds.log`, `docc.log`, `a.log`, `c.log`, `b.log`, `check-seed9.log` | all results |
| `logs/docc-30M-heap-exhausted.log`, `logs/docc-15M-heap-exhausted.log` | two crashed runs of the size-minimal variant, kept as evidence (section 8) |

Commands (run from that directory), with approximate wall time:

```
./run.sh d        # experiment D: main table, folds, 4 variants          ~1 min
./run.sh dseeds   # D on 8 other example sets, 3 policies                ~5 min
./run.sh docc     # D with size-minimal split acceptance, seeds 1..9     ~7 min
./run.sh a        # experiment A: growth and throughput                  ~2.5 min
./run.sh c        # experiment C: inverses, pad 0 and pad 3              ~5 s
./run.sh b        # experiment B: laws, plus sensitivity runs            ~70 s
./check-seed9.sh  # the seed-9 examples of map-adjacent f                ~1 s
```

Environment: SBCL 2.6.4.debian, Intel i9-11900H, 31 GB RAM, single thread, other jobs running on the machine (load 0.5 to 1.5). The timer has 4 ms resolution.

Source line counts by section (874 lines; the 500 to 800 target is exceeded):

| section | lines |
|---|---|
| header | 17 |
| 1 core store (base, column, class, bank, enumeration, goals, operator table) | 206 |
| 2 interpreter for terms and emitted programs | 29 |
| 3 change of base (`explode`, `pull`, `collect`, `elt-col`) | 22 |
| 4 experiment D (tasks, examples, split, lift, fold, tables) | 279 |
| 5 experiment A | 119 |
| 6 experiment C | 62 |
| 7 experiment B | 116 |
| 8 main | 24 |

Units. A **candidate** is one operator applied column-wise to a tuple of existing classes (one new column). **Cells** = candidates × rows. These are not the kernel's "work units"; the 350,000-work timeouts cannot be compared with candidate counts directly.

## 2. The store, as built

- `base`: `n` rows, optional `parent` and `pmap` (row → parent row).
- column: simple-vector of cells. A cell is an integer, `:t`, `:f`, a list of integers, `:err`, or (added) an operator name for a function-valued input.
- `cls`: id, column, type, size, representative term (the first, hence smallest, term that produced the column).
- `bank`: one per base. A table from a 36-bit content hash of the column to `(column . class)` pairs, confirmed by cell-wise equality; classes indexed by (type, size); one vector of all classes in creation order.
- Enumeration by size: for size s, each operator over every type-correct tuple of classes whose sizes sum to s−1. All-`:err` columns are dropped. Hooks `on-new` and `on-coll`. Counters for candidates, cells, collisions.
- Goals are predicates on a class: exact column, masked column, per-row allowed set.
- Change of base is 15 lines: `explode` (rows → (row, index) pairs), `pull` (a parent column read through `pmap`), `collect` (the reverse).

A consistency check runs inside experiment A. The number of candidates of size s is a pure function of the class counts of smaller sizes; predicted and enumerated counts are asserted equal at every completed size.

## 3. Experiment D — lift by change of base

Setup: 12 examples per task, sequences of length 0 to 7 with values −5..9, seed 1. One grammar for every task: `+ - * mod max min at = < and not call`. Shape grammar `+ - max min` over lengths, integer inputs, 0, 1. Size limit 10, budget 30 M candidates. Held-out: 200 fresh examples, lengths 0 to 12.

Semantics. `shift-seq`, `positions`, `scan`, `map-adjacent` mirror the `:spec` rows: shift left by k with zero fill; `positions(xs,k) = (k, k+1, …)` (the spec is an offset index list, not "positions of a value"); left scan with init, output excludes init; `map-adjacent` gives `f(xs[i+1], xs[i])`. `rotate-left`, `positions-of v`, `filter`, `take`, `zip-add` and `scan 2·acc−x` are my own definitions. The examples are my own random rows, not the `:spec` rows.

### 3.1 Main table (`logs/d.log`, first table)

`T L e` abbreviates `(tabulate L (lambda (i prev) e))`.

| task | ok | candidates | cells | ms | held-out | emitted program |
|---|---|---|---|---|---|---|
| reverse | yes | 86,434 | 4.4 M | 56 | 200/200 | `T (len xs) (at xs (- (len xs) (+ i 1)))` |
| shift-seq (spec) | yes | 9,175 | 0.37 M | 4 | 200/200 | `T (len xs) (if (< i (- (len xs) k)) (at xs (+ i k)) 0)` |
| rotate-left k | yes | 217,920 | 8.7 M | 108 | 200/200 | `T (len xs) (at xs (mod (+ i k) (len xs)))` |
| map-adjacent + | yes | 291,481 | 11.7 M | 244 | 200/200 | `T (- (len xs) (min (len xs) 1)) (+ (at xs i) (at xs (+ i 1)))` |
| map-adjacent − | yes | 703,183 | 28.1 M | 436 | 200/200 | `T (- (len xs) (min (len xs) 1)) (- (at xs (+ i 1)) (at xs i))` |
| running-sum | yes | 4,771 | 0.24 M | 4 | 200/200 | `T (len xs) (if (< 0 i) (+ prev (at xs i)) (at xs i))` |
| scan + init a (spec) | yes | 9,369 | 0.37 M | 8 | 200/200 | `T (len xs) (if (< 0 i) (+ prev (at xs i)) (+ a (at xs i)))` |
| scan 2·acc−x init a | yes | 304,540 | 13.1 M | 204 | 200/200 | `T (len xs) (if (< 0 i) (+ prev (- prev (at xs i))) (+ a (- a (at xs i))))` |
| positions (spec) | yes | 3 | 123 | 0 | 200/200 | `T (len xs) (+ i k)` |
| positions-of v | yes | 8,332 | 0.11 M | 0 | 200/200 | `(where xs (lambda (j x) (= x v)))` |
| filter x>k | yes | 7,002 | 0.09 M | 0 | 200/200 | `(select xs (lambda (j x) (< k x)))` |
| take k | yes | 267 | 8,629 | 0 | 200/200 | `T (min (len xs) k) (at xs i)` |
| zip-add | yes | 30,265 | 0.97 M | 20 | 200/200 | `T (min (len xs) (len zs)) (+ (at xs i) (at zs i))` |
| map-adjacent f (spec signature) | yes | 8,458,580 | 262 M | 5,036 | 200/200 | `T (- (len xs) (min (len xs) 1)) (call f (at xs (+ i 1)) (at xs i))` |
| scan f init a (spec signature) | yes | 14,186 | 0.50 M | 16 | 200/200 | `T (len xs) (if (< 0 i) (call f prev (at xs i)) (call f a (at xs i)))` |

Notes:

- Candidates include the shape bank. Lifted bases had 31 to 51 rows. The split step also scans classes (up to 53 M further cell comparisons, logged per task as "split-scan cells").
- Argument order came out right for subtraction and for `call f`.
- The five split tasks (shift-seq and the four scans) used one guard each. In each, the chosen term was also the single best-matching class, so the stated rule "take the term matching the most rows" was sufficient here.
- For filter and positions-of the shape step fails ("no shape term"), which is what routes them to the input-index lift.

### 3.2 Variants on the same examples (candidates; held-out shown where not 200/200)

| task | 12-op grammar | 15-op grammar (adds neg, div, if), budget 12 M | 12-op + goal inversion | 15-op + goal inversion | 12-op, size-minimal splits, budget 15 M |
|---|---|---|---|---|---|
| reverse | 86,434 | 197,071 | 86,434 | 197,071 | 86,434 |
| shift-seq | 9,175 | 12,753 | 9,175 | 12,753 | 9,834,897 |
| rotate-left | 217,920 | 506,796 | 217,920 | 506,796 | 217,920 |
| map-adjacent + | 291,481 | 1,037,437 | 4,791 | 6,489 | 291,481 |
| map-adjacent − | 703,183 | 1,761,194 | 4,791 | 6,489 | 703,183 |
| running-sum | 4,771 | 6,574 | 4,771 | 6,574 | 3,171,095 |
| scan + init | 9,369 | 12,980 | 9,369 | 12,980 | 10,579,588 |
| scan 2·acc−x | 304,540 | 528,675 | 304,540 | 528,675 | 10,675,341 |
| positions (spec) | 3 | 9 | 0 | 6 | 3 |
| positions-of v | 8,332 | 8,373 | 8,332 | 8,373 | 8,332 |
| filter | 7,002 | 7,043 | 7,002 | 7,043 | 7,002 |
| take | 267 | 386 | 267 | 386 | 267 |
| zip-add | 30,265 | 69,933 | 350 | 397 | 30,265 |
| map-adjacent f | 8,458,580 | 12,000,100, **impostor 117/200** | 8,458,580 | 12,000,100, **impostor 117/200** | 8,458,580 |
| scan f init | 14,186 | 49,010 | 14,186 | 49,010 | 15,000,001 (budget) |

- **Goal inversion** is an optional mechanism I added (section 7, item 13). It takes the total inverses that experiment C derives for `+` and `−` and turns "find y" into "find y − k for some existing class k", answered by one hash probe per class. It cut map-adjacent ± from 0.3 to 1.8 M candidates down to about 5 to 6 thousand, and zip-add from 30 to 70 thousand down to about 400. It does nothing for terms whose root is `at`, `call` or a split. With it, map-adjacent − comes out as `(+ (at xs (+ i 1)) (- 0 (at xs i)))` (the `+` inverse is tried first); still 200/200.
- **Size-minimal splits** (last column; `logs/docc.log`): a one-guard split is only held, and enumeration continues until every single term smaller than it is excluded. All programs are identical to the first column. The five split tasks cost 3 to 15 M candidates (2 to 8 s) instead of 5 to 305 thousand.
- **The failure:** map-adjacent with a function argument under the 15-operator grammar. Its answer has size 10; completing sizes 9 and 10 in that grammar exceeds the 12 M budget I allowed for memory safety. At budget end the last-resort nested split returned a three-way case analysis (one first-order map-adjacent per operator) behind guards that only happened to separate the operators on the 31 lifted rows. The grammar has no equality test on function values, so no honest guard exists.

### 3.3 Robustness over example sets (seeds 2..9; `logs/dseeds.log`, `logs/docc.log`)

"Perfect" = 200/200 held-out. All 8 sets were "solved" on the training rows for every task and policy.

| task | default: perfect, median candidates | nested splits at every level: perfect | size-minimal splits: perfect, median candidates | default + goal inversion: perfect, median candidates |
|---|---|---|---|---|
| reverse | 8/8, 86,420 | 8/8 | 8/8, 86,420 | 8/8, 86,420 |
| shift-seq (spec) | 8/8, 9,074 | 8/8 | 8/8, 9,874,555 | 8/8, 9,074 |
| rotate-left k | 8/8, 214,446 | **6/8** | 8/8, 214,446 | 8/8, 214,446 |
| map-adjacent + | 8/8, 284,661 | 8/8 | 8/8, 284,661 | 8/8, 4,787 |
| map-adjacent − | 8/8, 699,206 | 8/8 | 8/8, 699,206 | 8/8, 4,785 |
| running-sum | 8/8, 4,775 | 8/8 | 8/8, 3,086,153 | 8/8, 4,775 |
| scan + init a (spec) | 8/8, 9,268 | 8/8 | 8/8, 11,454,291 | 8/8, 9,268 |
| scan 2·acc−x init a | 8/8, 297,628 | 8/8 | 8/8, 10,244,793 | 8/8, 297,628 |
| positions (spec) | 8/8, 3 | 8/8 | 8/8, 3 | 8/8, 0 |
| positions-of v | 8/8, 8,332 | 8/8 | 8/8, 8,332 | 8/8, 8,332 |
| filter x>k | 8/8, 8,058 | 8/8 | 8/8, 8,058 | 8/8, 8,058 |
| take k | 8/8, 267 | 8/8 | 8/8, 267 | 8/8, 267 |
| zip-add | 8/8, 30,050 | 8/8 | 8/8, 30,050 | 8/8, 350 |
| map-adjacent f (spec) | **7/8**, 7,954,565 | **3/8** | **7/8**, 7,954,565 | **7/8**, 7,954,565 |
| scan f init a (spec) | 8/8, 14,192 | 8/8 | 8/8, 15,000,001 | 8/8, 14,192 |

- **The one default-policy miss** is map-adjacent `f` on seed 9. `logs/check-seed9.log` shows why: the set has `f = -` only on two one-element sequences, so it holds no output element computed by a non-commutative operator. The default policy returned `(if (= i (call f i 1)) (* …) (+ …))` (135/200). The size-minimal policy returned the single term `(call f (at xs i) (at xs (+ i 1)))`, with the arguments swapped (136/200). Neither is refutable from those 12 examples. This is the same lesson as the kernel's `foldl` impostors: examples for a function argument must include a non-commutative operator on a sequence of at least two elements.
- **Nested splits at every size level** produce impostors: rotate-left on seeds 3 and 6 (and seed 1, 106/200), map-adjacent `f` on seeds 2, 3, 5, 6, 9 (and seed 1, 117/200). Each is a case analysis with guards that fit the training rows by accident.
- **Size-minimal acceptance** changed no outcome on these sets (the seed-9 miss stays a miss, with a different wrong program) and cost 35 to 1,100 times more candidates on the split tasks.

### 3.4 Negatives: scalar-output folds (`logs/d.log`)

| task | base change only, sizes ≤ 9 | with the added fold form |
|---|---|---|
| sum | FAIL after 68,220 candidates | `(fold 0 (lambda (acc x) (+ acc x)) xs)`, 200/200; 21 fold programs tried, 1,348 step applications |
| alternating sum x0−x1+x2−… | FAIL after 68,220 | `(foldr 0 (lambda (acc x) (- x acc)) xs)`, 200/200; 51 tried, 1,514 step applications |
| Horner base 2 | FAIL after 68,220 | `(fold 0 (lambda (acc x) (+ acc (+ acc x))) xs)`, 200/200; 157 tried, 2,028 step applications |

Why base change cannot do it: the output is one value per example, so there is no output index to explode over, and the accumulator values are never observed. A scan is solvable precisely because its outputs are the accumulator trace (the `prev` column). For a fold, the step function cannot be posed as a column goal. What I added is generate-and-test: enumerate step classes over leaves `acc x 0 1` (deduped on a 7×7 probe grid) and run each through `fold` and `foldr`, with each init in {0, 1, integer inputs}, on all examples. Alternating sum needed the right fold; a left fold has no step function for it.

## 4. Experiment A — growth and throughput (`logs/a.log`)

32 rows of integers in −9..9 (the first three rows are made of 0, 1, −1), leaves x y z 0 1 2. Time limit 90 s per grammar. When storing the next size would exceed 6 M classes, that size is run hash-only (new columns counted by hash, not stored) and is the last.

G1 = {+ − * neg}; G2 = G1 ∪ {div mod max min}; G3 = G2 ∪ {= < and not if}.

Candidates evaluated and new classes per size (`h` = counted hash-only; bracketed = exact count of the first size not completed, computed from class counts):

| size | G1 cand | G1 new | G2 cand | G2 new | G3 cand | G3 new |
|---|---|---|---|---|---|---|
| 2 | 6 | 5 | 6 | 5 | 6 | 5 |
| 3 | 113 | 38 | 257 | 98 | 329 | 136 |
| 4 | 218 | 20 | 518 | 158 | 676 | 203 |
| 5 | 1,463 | 290 | 8,565 | 3,388 | 11,012 | 4,024 |
| 6 | 2,150 | 104 | 23,520 | 7,761 | 31,276 | 9,827 |
| 7 | 15,476 | 2,738 | 370,641 | 148,300 | 481,731 | 168,492 |
| 8 | 19,742 | 640 | 1,254,160 | 430,951 | 1,745,426 | 520,788 |
| 9 | 169,648 | 27,119 | 18,254,505 | 7,059,376 h | 24,056,722 | 7,758,129 h |
| 10 | 190,811 | 4,233 | [71,782,608] | | [101,780,503] | |
| 11 | 1,888,761 | 283,740 | | | | |
| 12 | 1,905,138 | 30,048 | | | | |
| 13 | 21,428,178 | 3,103,781 | | | | |
| 14 | 19,739,225 | 224,807 | | | | |
| 15 | [248,139,395]; 122 M done when the 90 s ended | | | | | |

| | G1 | G2 | G3 |
|---|---|---|---|
| last complete size | 14 | 9 | 9 |
| candidates through that size | 45.4 M | 19.9 M | 26.3 M |
| classes through that size | 3.68 M | 7.65 M | 8.46 M |
| syntactic terms through that size (no dedupe, by counting) | 5.7 × 10^11 | 3.4 × 10^8 | 4.5 × 10^8 |
| seconds to complete it | 25 | 9.8 | 12.8 |
| candidates / s | 1.86 M | 2.03 M | 2.05 M |
| cells / s | 59.6 M | 64.9 M | 65.6 M |
| live bytes per stored class | 458 | 452 | 452 |
| growth per unit size: candidates | ×3.31 | ×7.29 | ×7.35 |
| growth per unit size: classes | ×3.01 | ×7.17 | ×7.03 |
| growth per unit size: syntactic terms | ×9.25 | ×13.61 | ×13.72 |
| new classes per candidate, last sizes | 0.145 odd, 0.011 even | 0.34 to 0.40 | 0.30 to 0.35 |

- Growth factors are the fourth root of the product of the two latest two-step ratios. (Sizes alternate in parity because binary operators change size by 2.) The two-step candidate ratios were still rising: G1 11.1, 10.0, 11.3, 10.4 for sizes 11..14; G2 45.4, 43.3, 53.3, 49.3 for sizes 6..9.
- The class cap stopped stored enumeration before the 90 s limit in G2 and G3 (after about 10 and 13 s). G1 used the full 90 s.
- Hash-only counts are approximate: they rely on the 36-bit hash without the equality check. During development, changing the hash function moved the G2 size-9 count by about 0.1 %.

### Extrapolation: largest size fully enumerable

| time budget | G1 dedupe | G1 none | G2 dedupe | G2 none | G3 dedupe | G3 none |
|---|---|---|---|---|---|---|
| 1 min | 14 | 10 | 10 | 8 | 9 (10 is borderline) | 8 |
| 1 hour | 18 | 11 | 12 | 10 | 12 | 10 |
| 10 hours | 20 | 12 | 13 | 11 | 13 | 11 |

RAM those dedupe sizes would need, with the top size hash-only:

| time budget | G1 | G2 | G3 |
|---|---|---|---|
| 1 min | 1.6 GB | 4.1 GB | 0.6 GB |
| 1 hour | 211 GB | 207 GB | 257 GB |
| 10 hours | 2,437 GB | 1,238 GB | 1,694 GB |

Memory-limited at 24 GB (top size hash-only): G1 size 16 after 267 s; G2 size 11 after 488 s; G3 size 10 after 62 s.

Assumptions, all optimistic unless noted:

1. Throughput stays at the measured rate. It will not once the bank stops fitting in cache or RAM.
2. Beyond the last complete size, candidates follow the latest per-parity two-step ratio, and the new-class fraction stays at its last measured value. The ratios were still rising (toward the syntactic rate), so true growth is somewhat faster than modelled.
3. The first incomplete size uses the exact candidate count, which is computable from class counts without evaluation.
4. "None" (no dedupe) counts raw syntactic terms, computed by recurrence without evaluation, at the same per-candidate rate. That is generous to the no-dedupe case, which would also have to recompute or store sub-term columns.
5. Memory: 452 to 458 bytes per stored class at 32 rows (after a full GC), 25 to 36 bytes per hash-only class. "Top size hash-only" is the mode actually implemented: the last size is counted and could be goal-tested, but its columns are not kept.
6. 32 probe rows. Fewer rows shrink a class but merge more terms falsely (in B, 6 rows already gives a false law).

Reading. With dedupe, time alone would give sizes 14 / 18 / 20 (G1) and about 10 / 12 / 13 (G2, G3) at 1 min / 1 h / 10 h; without dedupe, 10 / 11 / 12 and 8 / 10 / 11. But every with-dedupe size past the first few minutes needs hundreds of GB. On this machine the memory-limited sizes are 16 (G1), 11 (G2) and 10 (G3), all reached within 1 to 8 minutes. As it stands, this enumerator cannot spend hours of search.

## 5. Experiment C — inverses and guards from functional dependencies (`logs/c.log`)

Table of c = op(a, b) on a, b ∈ −6..6, `:err` rows dropped. "FD %" is the share of rows whose group (other argument, c) contains a single value of the inverted argument. Leaves: the other argument, c, 0, 1. Grammar G2 when the dependency is total, G3 otherwise. Budget 300,000 candidates. Bracketed numbers are term sizes. This is the padded run (explained below).

| op | inverted arg | FD % | guard | inverse | section (any preimage) | candidates | ms |
|---|---|---|---|---|---|---|---|
| + | a | 100 | – | `(- c b)` [3] | – | 25 | 0 |
| + | b | 100 | – | `(- c a)` [3] | – | 25 | 0 |
| − | a | 100 | – | `(+ b c)` [3] | – | 6 | 0 |
| − | b | 100 | – | `(- a c)` [3] | – | 22 | 0 |
| * | a | 92.3 | `(not (= b 0))` [4] | `(div c b)` [3] | `(div c (if (= b 0) 1 b))` [8] | 141,652 | 268 |
| * | b | 92.3 | `(not (= a 0))` [4] | `(div c a)` [3] | `(div c (if (= a 0) 1 a))` [8] | 141,652 | 236 |
| neg | a | 100 | – | `(neg c)` [2] | – | 1 | 0 |
| div | a | 16.7 | `(= b (div 1 b))` [5], i.e. b = ±1 | `(* b c)` [3] | `(* b c)` [3] | 2,516 | 4 |
| div | b | 24.4 | not found | not found | not found | 300,001 | 484 |
| mod | a | 0 | – | – | `c` [1] | 0 | 0 |
| mod | b | 23.1 | not found | not found | not found | 300,001 | 480 |
| max | a | 46.2 | `(< b c)` [3] | `c` [1] | `c` [1] | 137 | 0 |
| max | b | 46.2 | `(< a c)` [3] | `c` [1] | `c` [1] | 137 | 0 |

- For `*`, the 141,652 candidates are the cost of also finding the size-8 section; the guard has size 4 and the inverse size 3.
- **Grid boundary artifact.** Without padding (first table in the log), `max` shows FD 46.7 % and `div a` 21.8 %, and no guard is found for either. The extra rows are ones like (b = −6, c = −6), where a is "unique" only because the grid stops at −6. Forming the groups over a range 3 wider for the inverted argument removes them and the guards appear. `+ − * neg` are unaffected.
- **`max` is not "nothing".** Where c > b the dependency holds and a = c. That is a correct guarded partial inverse.
- `div b` and `mod b` have a dependency on about a quarter of the rows, but the mask is irregular and no guard of size ≤ 8 expresses it.
- The "section" column is an addition: a term that returns some valid preimage on every row (the per-row allowed-set goal). It exists where no inverse does (`mod`: a = c; `div`: a = b·c).

## 6. Experiment B — laws from collisions (`logs/b.log`)

Grammar {+ * neg}, leaves x y z 0 1, the same 32 probe rows. Term order: size, then lexicographic with x<y<z<0<1 and +<*<neg (the order in which the enumerator creates classes).

| size | candidates (cum.) | collisions (cum.) | classes | kept laws | seconds (cum.) |
|---|---|---|---|---|---|
| 3 | 59 | 39 | 25 | 8 | 0.00 |
| 5 | 535 | 418 | 122 | 31 | 0.00 |
| 7 | 3,943 | 3,282 | 666 | 105 | 0.00 |
| 9 | 28,317 | 24,153 | 4,169 | 481 | 0.04 |
| 10 | 82,211 | 68,147 | 14,069 | 1,124 | 0.17 |
| 11 | 209,993 | 181,175 | 28,823 | 3,163 | 0.96 |
| 12 | 633,335 | 530,216 | 103,124 | 8,889 | 6.79 |
| 13 (unfinished) | 1,569,792 | 1,355,618 | 214,178 | 27,394 | 60.04 |

At size 7: 3,282 raw collisions, 105 kept laws, 0.01 s. The 60 s limit ended inside size 13, so that row is partial.

Size at which each named law is first derivable (both sides rewrite to one normal form under the kept laws); `*` = also kept literally:

| law | size | | law | size |
|---|---|---|---|---|
| commutativity + | 3 * | | identity x·1 | 3 * |
| commutativity * | 3 * | | zero x·0 | 3 * |
| associativity + | 5 | | double negation | 3 * |
| associativity * | 5 | | distributivity | 7 * |
| identity x+0 | 3 * | | | |

Associativity is never kept literally. What is kept at size 5 is `(+ y (+ x z)) = (+ x (+ y z))`; the larger side of `(+ (+ x y) z) = (+ x (+ y z))` was already rewritable by commutativity to an earlier term, so the rule discards that equation.

First 40 kept laws (larger side = smaller side; `[n]` = size being enumerated):

```
 1 [2] (neg 0) = 0                          21 [5] (+ (neg x) (neg x)) = (neg (+ x x))
 2 [3] (+ x 0) = x                          22 [5] (+ (neg x) (neg y)) = (neg (+ x y))
 3 [3] (+ y x) = (+ x y)                    23 [5] (* x (+ x 1)) = (+ x (* x x))
 4 [3] (+ 0 1) = 1                          24 [5] (* x (+ y 1)) = (+ x (* x y))
 5 [3] (* x 0) = 0                          25 [5] (* y (+ x x)) = (* x (+ y y))
 6 [3] (* x 1) = x                          26 [5] (* y (* x x)) = (* x (* x y))
 7 [3] (* y x) = (* x y)                    27 [5] (* y (* x y)) = (* x (* y y))
 8 [3] (neg (neg x)) = x                    28 [5] (* y (* x z)) = (* x (* y z))
 9 [4] (+ x (neg x)) = 0                    29 [5] (* 0 (+ x y)) = 0
10 [4] (+ 0 (neg x)) = (neg x)              30 [5] (* 1 (+ x y)) = (+ x y)
11 [4] (* x (neg 1)) = (neg x)              31 [5] (neg (+ x (neg y))) = (+ y (neg x))
12 [4] (* y (neg x)) = (* x (neg y))        32 [6] (+ x (+ y (neg x))) = y
13 [4] (neg (* x x)) = (* x (neg x))        33 [6] (+ x (neg (+ x x))) = (neg x)
14 [4] (neg (* x y)) = (* x (neg y))        34 [6] (+ x (neg (+ x y))) = (neg y)
15 [5] (+ y (+ x x)) = (+ x (+ x y))        35 [6] (+ y (neg (+ x y))) = (neg x)
16 [5] (+ y (+ x y)) = (+ x (+ y y))        36 [6] (+ 0 (+ 1 (neg x))) = (+ 1 (neg x))
17 [5] (+ y (+ x z)) = (+ x (+ y z))        37 [6] (* x (+ x (neg 1))) = (+ (neg x) (* x x))
18 [5] (+ 0 (+ 1 1)) = (+ 1 1)              38 [6] (* x (+ y (neg 1))) = (+ (neg x) (* x y))
19 [5] (+ 0 (* x x)) = (* x x)              39 [6] (* x (+ 1 (neg x))) = (+ x (* x (neg x)))
20 [5] (+ 0 (* x y)) = (* x y)              40 [6] (* x (+ 1 (neg y))) = (+ x (* x (neg y)))
```

Soundness on 1000 fresh rows in −1000..1000: **0 false of 105** at size 7, and 0 false of 27,394 in the 60 s run.

Sensitivity (all at size ≤ 7):

| variation | kept laws | after inter-reduction | false on fresh rows |
|---|---|---|---|
| 32 rows, order x y z 0 1 | 105 | 59 | 0 |
| 32 rows, order 0 1 x y z | 133 | 43 | 0 |
| 12 rows | 105 | 59 | 0 |
| 8 rows | 105 | 59 | 0 |
| 6 rows | 106 | 60 | 1 |
| 4 rows | 124 | 81 | 23 |
| 3 rows | 280 | 263 | 199 |

What the kept set shows:

- The prune as specified is one-step and online. It keeps special cases found before the general law (laws 15 and 16 before 17) and instances the ordered rules cannot reach (`(+ 0 (* x y)) = (* x y)`, because commutativity may not move `0` behind a larger term). A post-pass that drops laws derivable from the others takes 105 down to 59, still far from the roughly 10 ring axioms.
- The kept set grows about ×2.8 per size and is roughly 8 to 16 % of the classes. The linear scan over kept rules then dominates run time: size 12 took about 5.8 s, of which enumeration at the measured rate is about 0.2 s; size 13 was unfinished after 53 s.
- The count depends on the arbitrary leaf order (105 against 133 before the post-pass).

## 7. Every mechanism added beyond the stated hypothesis

The hypothesis names base, column, class, guard as boolean column, inverse from a table, and lift as change of base. To get the results above I also needed the following. Items marked (given) were in the task statement; the rest are mine.

**In the lift procedure (D)**

1. (given) A lag column `prev = ys[i−1]`. It turns `tabulate` into a recurrence: the interpreter threads the previous output. Training uses the observed previous output; running uses the program's own.
2. (given) Leaves `(len xs)` per sequence and constants 0, 1; shape synthesis as a separate first step.
3. Iterative deepening on term size, with a split attempt after every size level. The first level at which a single term or a one-guard split fits is accepted. This is first-fit, not size-minimal: a split of total size 12 is accepted without excluding single terms of sizes 6 to 11. The size-minimal alternative is the `docc` variant.
4. Split choice restricted to classes whose match-mask has a guard class, then most rows first, two candidates tried. On these tasks the unrestricted "most rows" choice was the same class every time.
5. A per-call index of boolean classes by their column restricted to the rows still unexplained (needed for nested splits; a restriction of base in all but name).
6. Nested (two-guard) splits only when the size or candidate budget is exhausted.
7. Routing: if no shape term exists, switch to the input-index lift; try `select` (subsequence alignment), then `where` (index list).
8. `if` is lazy in the untaken branch; every other operator is strict in `:err`.
9. A `:code` cell type and a `call` operator for function-valued inputs. Function values come from the fixed set {+, −, *}, and there is no equality test on them.
10. The size limit (10) and candidate budgets (30 M; 12 M for the large grammar; 15 M for the size-minimal variant) are my choices, set by memory.
11. A full garbage collection between tasks (without it the size-minimal runs exhaust the 10 GB heap).

**Outside base change**

12. The `fold` / `foldr` form with generate-and-test over step classes, a 7×7 probe grid for deduping step functions, and the init set {0, 1, integer inputs} (section 3.4).
13. Optional goal inversion: residual lookup through the total inverses derived by experiment C (off in the main table).

**In A, C, B**

14. A hash-only mode for the last size in A, and the exact prediction of candidate counts from class counts.
15. In C: padding the inverted argument's range (without it `max` and `div` fail); a much wider range to list all preimages; the "section" goal.
16. In B: both rewrite directions of each law, each used only when the result is earlier in the term order and introduces no new variable; the named-law test by normal-form comparison; the inter-reduction post-pass; the leaf-order choice.

## 8. What worked, what did not, surprises

Worked:

- Lift by change of base, including shape, split and the input-index variant, with one grammar. The hard part of each task became a term of size 3 to 10 over index columns.
- Guard discovery as a hash probe: the match mask of a partial term is looked up directly among boolean classes.
- Inverses and guards from tables, and feeding those inverses back into the search (item 13).
- Observational-equivalence dedupe as the source of laws: no false law at 8 or more rows.

Did not work, or only with caveats:

- Nested splits overfit (sections 3.2, 3.3). A guard split needs an acceptance test stronger than "fits the rows"; the size-minimal test changed no outcome here and costs 35 to 1,100 times more.
- A function argument is only as well determined as its examples (seed 9).
- Scalar folds need a mechanism that is not base change (item 12).
- Exhaustive enumeration cannot use a long time budget: RAM runs out in minutes (section 4). The same wall showed up in D: two runs of the size-minimal variant died of heap exhaustion at 10 GB before item 11 was added.
- The specified law prune does not give a small basis, and its cost overtakes enumeration by size 12.
- Finite-table dependencies have boundary artifacts (item 15).

Surprises:

- How little dedupe buys once div, mod, max, min are present: 30 to 40 % of candidates are new classes, against 14 % (odd sizes) and 1 to 2 % (even sizes) for polynomials.
- The candidate count of a size is exactly predictable from class counts, so the cost of the next level is known before running it.
- Associativity never appears as a kept law; the rule set keeps a rearrangement law instead and then leaks instances at larger sizes.
- `max` has a clean guarded inverse; I expected none.
- SBCL 2.6.4 crashed compiling `(reduce #'+ (cdr e) :key #'tsize)` inside the self-recursive `tsize`; I rewrote it as a loop.

Not tested:

- The kernel's own `:spec` rows. They are few and short (map-adjacent: 8 examples, 6 output elements in total), which would leave the lifted problem badly under-determined. My example sets give 31 to 51 lifted rows.
- Fewer than 12 examples, negative shift amounts, nested sequences, outputs that are neither index-aligned nor a subsequence (sort, dedupe, concat), tasks needing two lifts.
- A fair cost comparison with the kernel: the units differ, and so do the grammars and row sets.
