# verify-review — reproduction of the empirical claims in `plan_v2c_audit.md`

Agent `verify-review`. Everything below was run by me; nothing is copied from the review.
Working directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/verify-review/` (called `$W` below).
The repository was not touched: `git status --short` lists the same 21 untracked entries before and after, and no tracked file is modified.

Environment: SBCL 2.6.4.debian, `--dynamic-space-size 8GB`, every run under `timeout`, every run from a script with its log in `$W/logs/`. All randomness is seeded (the probe's own `sb-ext:seed-random-state`; mine in `r5-metric.lisp`). Counts are deterministic; timings vary by a few ms.

## 0. Verdicts

| # | Claim (review section) | Verdict | What I measured |
|:--|:--|:--|:--|
| R1a | copy, inc-all, dbl-all, positions: exact `tabulate`, 200/200, 3–8,607 candidates | **REPRODUCED** | 151 / 408 / 8,607 / 3 candidates; all 200/200 |
| R1b | scan and shift-seq exact, 200/200, 11,298 and 8,781 candidates | **PARTLY** | both exact with one guard, both 200/200; shift-seq 8,781 (exact match); scan **11,604**, not 11,298 |
| R1c | filter needs a unary boolean call; then `(select xs (call1b p x))`, 200/200, 1,383 candidates | **REPRODUCED** | without it `NIL` after 1,576,693 candidates; with it the same program, 200/200, 1,383 |
| R1d | sum-all, len-all, prd-all, last-or 200/200 via `fold`; unlifted scalar path overfits (20–23/200) | **PARTLY** | fold path 200/200 on all four. Unlifted path: sum-all 23/200, prd-all 20/200, but **len-all 200/200** (`(len xs)` is a leaf) and **last-or 200/200** (an exact one-guard split) |
| R1e | map-adjacent on its 8 spec rows: default returns a size-19 `if`-split impostor, 29/200; `*occam*` gives the exact size-10 term, 200/200, 64 ms, 616,232 candidates | **PARTLY** | impostor 29/200: yes. `*occam*`: exact, size 10, 200/200, 616,232 candidates, 60–64 ms: yes. The impostor is **27 nodes** by the probe's `tsize` (22 if `(len xs)` counts as one leaf), accepted after **level 8**, not "size 19 at level 7" |
| R1f | foldl on its 9 spec rows returns `(fold a (- acc x) xs)`, 81/200, because the spec only has `f = -` | **REPRODUCED** | `(fold a (lambda (acc x) (- acc x)) xs)`, 81/200. The stated reason ("size 3 beats `(call f acc x)` size 4") is not how the probe as it stands works: `f` is not a leaf of its step bank at all (see §1f) |
| R1g | seq-corr, best-shift, argmax-corr not solvable by the probe as it stands (table: `NIL`, 0/200) | **REPRODUCED** that none is solved; **detail wrong for two of three** | seq-corr `NIL`. argmax-corr returns impostors (31/200 and 43/200). best-shift returns an impostor (1/200) |
| R2 | a small monoidal pushforward solves `:spec/seq-corr` from 7 rows as `(fold-space (min (len xs) (len ys)) + 0 (* (at xs i) (at ys i)))`, 200/200; "8 lines" | **REPRODUCED** (the "8 lines" only for the operator itself) | same program, 200/200; 20,713 candidates / 8 ms with the shape granted; 3,050,322 / 0.7 s with the shape enumerated. It does **not** subsume the probe's `fold` path |
| R3a | `(and (not (= b 0)) (= (* (div c b) b) c))` exactly right on all 1,681 pairs | **REPRODUCED** | 0 false positives, 0 false negatives, floor and truncating division, against brute force |
| R3b | `div(a,b)=c` for `b` is non-injective on its image; only a section "unless guarded by \|a\| < c(c+1)" | **PARTLY** | non-injective: yes. The guard is sufficient for at-most-one but not exact: 48 (floor) / 78 (truncate) pairs with exactly one `b` fail it |
| R3c | the three positive rows of `:spec/solve-/-1` are exact multiples | **REPRODUCED** | 12 = 3·4, 15 = 5·3, −12 = −4·3; the row (15, 3) → 5 has two preimages {4, 5} |
| R4 (sums) | conditional Kraft sums 1.5 (`:bool`), 1.1875 (`(:gf 5)`, u = 3), 1.4059 (`:int`, u = 0, \|v\| ≤ 1000) | **REPRODUCED** | 3/2, 19/16, 92137/65536 = 1.4059; plain `value-bit-size` 0.9059 |
| R4 (does it matter) | "live" violation | **PARTLY** | In Stage A the 0-bit price is never summed per cell: only exception rows are charged, each with its row index and the count. The shortfall there is one bit per model. The one place that sums it densely, `induce-row-order`, has no caller outside `tests/` |
| R5i | 0 triangle violations on sample grids in `:int`, `(:gf 5)`, `(:seq :int)`, `:code` | **PARTLY** | 0 on `:int`, every `(:gf p)` tried, and small-value seq and code grids. **Violations exist** on `(:seq :int)` (up to 6 bits) and `:code` (up to 4 bits) once values are large |
| R5ii | integer distances symmetric; 0, 4, 5, 5, 8 … 17 bits at \|Δ\| = 0, 1, 2, 3, 4 … 1000 | **REPRODUCED** | exactly those values; symmetric for every Δ up to 10⁶ |
| R5iii | d(() → (1 2)) = 13 against 1; d(x0 → x0+1) = 15 against 3 | **REPRODUCED** | 13 and 1. 15 and 3 with a two-input code scope (14 and 2 with one input, 16 and 4 with three) |
| R6 | `anti-unify` maps `(+ x x)`, `(+ y y)` to one shared hole and `(+ x y)`, `(+ y x)` to two | **REPRODUCED** | `(+ ?0 ?0)` and `(+ ?0 ?1)` |
| R6' | review's second anti-unification point (class cells need a DFTA product) | **COULD NOT TEST** | a statement of theory; nothing in the tree implements class-valued instance cells |

## 1. R1 — the probe on the kernel's actual `:spec` rows

### Setup

- `tg-probe.lisp`: byte-identical copy (sha256 `0f4da503…`). `./run-baseline.sh` reruns its experiment D; the log equals the repository's `proto/logs/d.log` once timings are masked.
- `tg-probe-r1.lisp`: the copy with three modifications (§7), all for R1c.
- `r1-spec.lisp`: an added driver. It holds the spec rows, the hidden references, and calls the probe's own `solve-task`, `solve-scalar`, `solve-fold`, `timed` and `verify` with the budgets of the probe's `exp-d` (sequence outputs: max size 10, 30 M candidates; scalar outputs: size ≤ 9 and 3 M; fold: 3 M). It redefines nothing in the probe.
- Held-out is the probe's own `verify`: 200 examples, seed 999, sequences of length 0–12 with values −5..9. Integer inputs: `k` in 0..4 (positions), 0..3 (shift-seq, best-shift); `a`, `d` in −5..9. A function argument is drawn from `+ - *` and a predicate from `pos even neg`; `*` and `neg` occur in no spec row.

### How the references were defined, and checked

Each reference in `r1-spec.lisp` (lines 16–55) is a line-by-line transliteration of the library's `:EXPRESSION` in `v2/library/{sequences,scans,sequence-shift}.sexp`; the source expression is quoted in a comment above each. The six seed functions (copy, inc-all, dbl-all, sum-all, len-all, prd-all) are not library entries; their references are the functions their names and four rows denote.

Two machine checks (`./run-xref.sh`, log `logs/xref-kernel.log`):

1. My hand-copied rows equal the stored `:SPEC` entries of `v2/library/*.sexp`, in order and content, for all ten specs that are stored (positions, scan, shift-seq, filter, map-adjacent, foldl, last-or, seq-corr, best-shift, argmax-corr). The six seed specs exist only in `bootstrap/build-batteries.lisp:563-568` and were copied by eye.
2. I loaded the **v2 kernel** from a scratch copy, loaded the three batteries, and evaluated the library's own definition in the kernel VM on each of the 200 held-out inputs of every task: **0 mismatches** with my reference on all ten. The six seed functions were checked the same way as instances of the library's `:map` and `:foldr`: 0 mismatches.

Every reference also reproduces every one of its spec rows (asserted at load).

### Results (`./run-r1.sh`, `logs/r1.log`)

| Spec | rows (lifted) | path | candidates | ms | held-out | program found |
|:--|:--|:--|--:|--:|:--|:--|
| copy | 4 (6) | tabulate | 151 | 0 | 200/200 | `(at xs i)` |
| inc-all | 4 (6) | tabulate | 408 | 0 | 200/200 | `(+ 1 (at xs i))` |
| dbl-all | 4 (6) | tabulate | 8,607 | 0–4 | 200/200 | `(+ (at xs i) (at xs i))` |
| positions | 11 (10) | tabulate | 3 | 0 | 200/200 | `(+ i k)` |
| scan | 9 (9) | tabulate + 1 guard | **11,604** | 0–4 | 200/200 | `(if (= i 0) (call f a (at xs i)) (call f prev (at xs i)))` |
| shift-seq | 13 (27) | tabulate + 1 guard | 8,781 | 4 | 200/200 | `(if (< i (- (len xs) k)) (at xs (+ i k)) 0)` |
| filter, probe as it stands | 7 (9) | select | 1,576,693 | 224 | — | `NIL` |
| filter, with `call1b` | 7 (9) | select | 1,383 | 0 | 200/200 | `(select xs (lambda (j x) (call1b p x)))` |
| sum-all | 4 | unlifted scalar | 781 | 0 | **23/200** | a 23-node `if` over `(len xs)` |
| | | fold | 2 | 0 | 200/200 | `(fold 0 (lambda (acc x) (+ acc x)) xs)` |
| len-all | 4 | unlifted scalar | 0 | 0 | **200/200** | `(len xs)` |
| | | fold | 4 | 0 | 200/200 | `(fold 0 (lambda (acc x) (+ acc 1)) xs)` |
| prd-all | 4 | unlifted scalar | 6,405 | 0 | **20/200** | a 29-node `if` over `(len xs)` |
| | | fold | 34 | 0 | 200/200 | `(fold 1 (lambda (acc x) (* acc x)) xs)` |
| last-or | 7 | unlifted scalar | 1,832 | 0 | **200/200** | `(if (< 0 (len xs)) (at xs (- (len xs) 1)) d)` |
| | | fold | 0 | 0 | 200/200 | `(fold d (lambda (acc x) x) xs)` |
| map-adjacent, default | 8 (6) | tabulate + split | 55,288 | 8 | **29/200** | see §1e |
| map-adjacent, `*occam*` | 8 (6) | tabulate | 616,232 | 60–64 | 200/200 | `(call f (at xs (+ i 1)) (at xs i))` |
| foldl | 9 | unlifted scalar | 203,893 | 28 | 22/200 | a 33-node `if` |
| | | fold | 18 | 0 | **81/200** | `(fold a (lambda (acc x) (- acc x)) xs)` |
| seq-corr | 7 | unlifted scalar | 404,906 | 60 | — | `NIL` |
| | | fold | 43,337 | 36 | — | `NIL` (74,680 fold programs tried) |
| argmax-corr | 3 | unlifted scalar | 1,724 | 0 | 31/200 | `(if (= (len ys) (+ 1 1)) (- (len xs) (len ys)) (+ 1 1))` |
| | | fold | 2,609 | 4 | 43/200 | `(fold 0 (lambda (acc x) (+ acc (- 1 (mod 1 x)))) xs)` |
| best-shift | 9 (18) | `solve-task`, 2-tuple as a sequence | 8,297,753 | 3,000 | 1/200 | a 47-node nested `if` |

### Notes per sub-claim

**1b, scan.** 11,604, not 11,298. The count does not depend on the order of the inputs (six orders tried, `logs/r1-variants.log`). The cumulative counts at the level boundaries are 294, 350, 7,728, 11,604 (`logs/r1-variants2.log`), so 11,298 is not a boundary of this bank. I could not find a setting that gives 11,298. The qualitative result is as claimed.

**1c, filter.** Without the unary call the probe enumerates 1.58 M candidates and returns nothing. With it, the predicate is found at size 3. The held-out set includes the unseen predicate `neg` (71 of 200 examples); all correct.

**1d.** The review's "unlifted `solve-scalar` overfits 4-row specs (20–23/200)" holds for sum-all and prd-all. It does not hold for len-all, where the answer `(len xs)` is a granted leaf found by one hash probe, nor for last-or, where the unlifted path finds the exact program with one guard.

**1e, map-adjacent.** Default policy returns

`(if (= 1 (at xs 0)) (+ (len xs) (* i (call f (len xs) i))) (+ (len xs) (+ (len xs) (call f (len xs) 1))))`

- Held-out 29/200. The 29 are the 28 examples whose output is empty plus one coincidence; on non-empty outputs it is right 1 time in 172.
- Size: 27 by the probe's `tsize`; 22 if `(len xs)` is counted as one node, as the bank counts it. Not 19.
- Accepted after level 8 (4,444 classes, 55,189 candidates in the element bank), not level 7. The trace shows no split after levels 2–7.
- With `*occam*`: the exact size-10 term, 200/200, 616,232 candidates, 60–64 ms. All four numbers match the review.
- I tried max size 7, 8, 9, greedy nested splits, and candidate limits of 20 k, 22 k, 30 k, 50 k: impostors of 27, 35 or 36 nodes, never 19.

Extra, not asked: `*occam*` on all eight sequence-output specs (`./run-r1-occam.sh`). All eight are 200/200. The two specs that genuinely need a guard cost 7,257,787 (scan, 1.3 s) and 7,238,105 (shift-seq, 2.9 s) candidates, against 11,604 and 8,781 by default: 625× and 824×.

**1f, foldl.** The result reproduces: 81/200, of which 68/68 on `f = -`, 10/66 on `+`, 3/66 on `*`. The review's explanation needs a correction. In the probe as it stands, `solve-fold` builds its step bank over `acc`, `x`, 0, 1 only (`tg-probe.lisp:481-483`); `f` is not there, so `(call f acc x)` is never a candidate. I added a variant that offers `f` to the step bank (`solve-fold-f` in `r1-variants2.lisp`): `(- acc x)` is still returned first (81/200), and if it is skipped the next fit is `(fold a (lambda (acc x) (call f acc x)) xs)`, 200/200. So the review's sentence is right for a probe that has `f` in scope, which this one does not.

**1g.** None of the three is solved. Only seq-corr returns `NIL`. argmax-corr (three rows) and best-shift return programs that fit the rows and are wrong, which for the design is a worse outcome than `NIL`. The review's table shows `NIL`, 0/200 for all three.

**A caveat on every "200/200".** It holds for the held-out distribution above. shift-seq found on the spec rows scores 174/200 if `k` is drawn from −3..15: the spec has no negative `k`, the library returns `xs` unchanged there, and the found term reads out of range. positions, scan and last-or stay at 200/200 with their integer input drawn from much wider ranges (`logs/r1-variants2.log`).

## 2. R2 — monoidal pushforward

### What I added

In the probe copy `tg-probe-r2.lisp` (16 lines, of which 14 code):

- `*aggs*`, the five fixed fold algebras: `(+, 0)`, `(*, 1)`, `max`, `min` (no identity: an empty fibre gives `:err`), and `count` of true cells on boolean classes. 3 lines.
- `agg-step`, one step of a fold, with `:err` poisoning the fibre. 1 line.
- `reduce-pmap`, the pushforward: `collect` (`tg-probe.lisp:264`) with a fold algebra in place of `list`. 5 lines.
- one clause in the interpreter `ev` so that `(fold-space L agg (lambda (i) elem))` can be run on held-out examples. 5 lines.

In the added file `r2-reduce.lisp`:

- shape granted (30 lines): build the position space from a given shape term, enumerate classes on it by size, push each new class forward under each aggregate of its cell type, compare with the scalar target, return the first fit.
- shape enumerated (27 more lines): shapes are the classes of the probe's own shape bank up to size 3 (lengths, integer inputs, 0, 1 under `+ - max min`), non-negative and not constant; iterative deepening on shape size + element size.

So the operator and its table are 9 lines, which is what "8 lines" can mean. A version that searches and can be verified is 44 lines with the shape granted and 71 with the shape searched.

### Results (`./run-r2.sh`, `logs/r2.log`)

| Task (rows) | shape | candidates | ms | held-out | program |
|:--|:--|--:|--:|:--|:--|
| seq-corr (7 spec rows) | granted `(min (len xs) (len ys))` | 20,713 | 8 | 200/200 | `(fold-space (min (len xs) (len ys)) + (lambda (i) (* (at xs i) (at ys i))))` |
| | enumerated, 13 shapes | 3,050,322 | 708 | 200/200 | the same |
| sum-all (4) | granted / enumerated | 97 / 133 | 0 | 200/200 | `(fold-space (len xs) + (lambda (i) (at xs i)))` |
| len-all (4) | granted / enumerated | 0 / 36 | 0 | 200/200 | `(fold-space (len xs) + (lambda (i) 1))` |
| prd-all (4) | granted / enumerated | 97 / 133 | 0 | 200/200 | `(fold-space (len xs) * (lambda (i) (at xs i)))` |
| last-or (7) | granted / enumerated | 922,903 / 3,506,865 | 212 / 2,312 | — | `NIL` |
| probe's own "sum" (12 random rows) | granted / enumerated | 97 / 133 | 0 | 200/200 | as sum-all |
| probe's own "alternating sum" | granted / enumerated | 431,369 / 534,710 | 452 / 588 | — | `NIL` |
| probe's own "horner base 2" | granted / enumerated | 431,369 / 534,710 | 468 / 588 | — | `NIL` |
| foldl (9 spec rows) | granted `(len xs)` | 719,361 | 156 | — | `NIL` |
| | enumerated | 175,493 | 184 | 38/200 | `(fold-space a count (lambda (i) (not (< (* i i) (* (len xs) a)))))` |
| argmax-corr (3 spec rows) | enumerated | 1,926 | 4 | 49/200 | `(fold-space (len xs) max (lambda (i) (mod i (- (len xs) i))))` |

### Does it subsume the probe's `fold` generate-and-test?

No. It solves seq-corr, which the `fold` path cannot (that path folds one input sequence). The `fold` path solves last-or, alternating sum and Horner, which this cannot. On the kernel's four scalar specs it gets three of four; on the probe's own three fold tasks, one of three.

### What it cannot do, with the reason in each case

- **Horner (step 2·acc + x).** The result is Σ xᵢ·2^(n−1−i). No element term in this grammar computes that weight. This is the review's case: a non-associative step with no observed accumulator.
- **foldl with `f` given.** No fixed aggregate fits. On the spec rows (only `f = -`) the target is `a − Σ xᵢ`, which is a pushforward composed with one operator on the base space; my version tests the pushed-forward column against the target directly and does not compose. I did not test an algebra read from the row, `(e, ⊕) = (a, call f)`.
- **last-or.** It is a fold with an associative step (keep the right argument) whose identity is the input `d`. None of the five fixed aggregates has an identity taken from a base-space column.
- **alternating sum.** It is a pushforward of xᵢ·(−1)^i, but that element term needs about 17 nodes in this grammar (no literal 2, no `if`); the search stopped at 9. This is a budget limit, not a limit of the mechanism.
- **argmax-corr, best-shift.** They need a nested space (shifts × positions), an arg-max, and a tuple.

One more observation: with the shape enumerated, integer inputs are candidate shapes, and on foldl the search returns a program that uses the initial value `a` as a length. With three to nine rows the pushforward overfits as readily as the split does.

## 3. R3 — the divisibility guard

`./run-r3.sh`, `logs/r3.log`. No kernel code; the unmodified probe is loaded only for its `ev`.

**3a.** For every (b, c) in [−20, 20]² I counted the integers `a` in [−2000, 2000] with a·b = c. For b ≠ 0 every solution has |a| ≤ 20, so the window is complete; for b = c = 0 every `a` is a solution. 304 pairs have exactly one `a`, 1,376 have none, 1 has many.

| Division | false positives | false negatives | wrong witness where the guard holds |
|:--|--:|--:|--:|
| floor (the probe's `div`) | 0 | 0 | 0 |
| truncating (the kernel's `:/` on `:int`, `vm.lisp:219`) | 0 | 0 | 0 |

The uniqueness guard alone, `(not (= b 0))`, has 1,336 false positives, so the replay conjunct does all the work the review says it does.

One qualification. In the probe's own evaluator `and` is strict in `:err`. The term as written evaluates to `:t` on 304 pairs, `:f` on 1,336 and **`:err` on the 41 pairs with b = 0**. It is exact if `:err` is read as false or `and` short-circuits. The review says "totalized"; that is the step that totalizes it.

**3b.** `div(a, b) = c` solved for `b`, all (a, c) in [−20, 20]², `b` searched in [−3000, 3000] without 0.

- 10/4 = 10/5 = 2 under both divisions: non-injective, as claimed.
- Of the pairs on the image, 54.3 % (floor) and 60.0 % (truncate) have exactly one `b`.
- The review's guard |a| < c(c+1):

| | guard true: no b / one b / many b | guard false: no b / one b / many b |
|:--|:--|:--|
| floor | 1,223 / 200 / 0 | 1 / 48 / 209 |
| truncate | 1,241 / 182 / 0 | 7 / 78 / 173 |

It never admits a pair with several preimages, so it is a sound uniqueness guard. It is not exact: it rejects 48 (floor) or 78 (truncate) pairs that have exactly one `b` (for example a = 6, c = 2, b = 3), and it says nothing about existence, which again needs the replay.

**3c.** `:spec/solve-/-1`, `bootstrap/build-batteries.lisp:234-235`, inputs (a, c) → b:

| a | c | spec b | exact multiple | preimages (truncate) | preimages (floor) |
|--:|--:|:--|:--|:--|:--|
| 12 | 4 | 3 | yes | {3} | {3} |
| 15 | 3 | 5 | yes | {4, 5} | {4, 5} |
| −12 | 3 | −4 | yes | {−4} | {−4} |
| 0 | 4 | none | — | none | none |
| 12 | 0 | none | — | every \|b\| > 12 | every b > 12 |
| 0 | 0 | none | — | every b ≠ 0 | every b ≠ 0 |

All three positive rows are exact multiples, as claimed. The second already has two preimages, so even on its own rows the spec's answer is a choice.

## 4. R4 — the Kraft sums, and whether they matter

`./run-kernel.sh r4-kraft`, `logs/r4-kraft.log`. Root kernel loaded from the scratch copy `$W/kernel/`; all prices come from the kernel's `correction-bit-size`, `value-bit-size`, `positive-bit-size`, `body-size`, `condense-heuristic`, `relational-linkage-residual`, `induce-row-order`.

### 4.1 The sums

| Type, u | distances | Σᵥ 2^−d(u→v) | same, with only the v = u cell put back to its pre-override price |
|:--|:--|:--|:--|
| `:bool`, T (and NIL) | 0, 1 | 3/2 = 1.5000 | 1.0000 |
| `(:gf 5)`, u = 3 (same for every u) | 5, 5, 4, 0, 4; replacement 3 bits | 19/16 = 1.1875 | 0.6875 |
| `:int`, u = 0, \|v\| ≤ 1000 | 0, 4, 5, 5, 8, 8, 8, 8, 9 … | 1.4059 | 0.9059 |
| `:int`, plain `value-bit-size`, \|v\| ≤ 1000 | | 0.9059 | |
| `:int`, u = 0, \|v\| ≤ 100,000 | | 1.4424 (tends to 1.5) | |
| `(:gf 2)`, `(:gf 3)`, `(:gf 7)`, `(:gf 13)` | | 1.0625, 1.1250, 1.2500, 1.2734 | |

All three of the review's numbers reproduce, and for these types line 1581 is the only cause.

### 4.2 Where the per-cell prices are summed

Every call site of `correction` / `priced-correction` / `correction-bit-size` in the root kernel:

| Site | What is summed | Is "which rows are exact" paid for? |
|:--|:--|:--|
| `condense.lisp:105-108` `charge-row-witness`, from `:116`, `:240`, `:254`; total at `condense.lisp:129-133` | only rows that **fail** their check; each adds `positive-bit-size(row index + 1)` + the correction; a non-empty residual adds `positive-bit-size(1 + count)` | **Yes**, by listing exception rows by index |
| `enumerate.lisp:652-667` `relational-linkage-residual` | only **violated** must-agree pairs; each adds `positive-bit-size(pair index + 1)` + the correction | **Yes**, same scheme |
| `frame.lisp:1543-1552`, parts of a tuple or sequence | every part; an equal part costs **1 bit**, so the 0 of line 1581 never enters this sum | Yes |
| `proposals.lisp:728-739` `induce-row-order`, chain and star | a correction for **every** consecutive pair (chain) or every row (star); an equal step costs 0 | **No** |

I confirmed the first two by running the kernel. `condense-heuristic` on seven small integer frames produced 28 models; for every one, `residual-bits` equals Σ over listed exceptions of (index bits + correction bits) + count bits, and exact rows contribute nothing. Example: targets (0 0 0 0 7 0), program `'0`: one exception at row 4, 5 + 8 + 4 = 17 bits. `relational-linkage-residual` with four must-agree pairs charges 0, 8 and 15 bits for 0, 1 and 2 violated pairs, equal to the sum over violated pairs only. In these paths the two values handed to `correction` always differ, so the branch at line 1581 is not reached at top level.

### 4.3 A concrete example, or why none exists

**Stage A (the first two sites): no per-cell example exists.** The residual is a count, then for each exception a row index and a correction. Each part is a prefix code, so for any inexact model the total is a decodable code length (a wasteful one, since sorted indices are coded independently).

What is unpaid is **one bit per model**. An empty residual is charged 0 bits, where the count code would charge `positive-bit-size(1)` = 1. Smallest case: one row, predicted p. Target p costs 0 bits; target p + δ costs 1 + `value-bit-size(δ)` + 4. The Kraft sum over all targets is 1 + 0.0138 = 1.0138. Over N rows it is 1.016 (N = 2), 1.019 (4), 1.023 (8), 1.024 (16); charging one bit for "exact" brings each to about 0.52. So the review's "1 bit per column" is the whole of the Stage-A defect, and its second half ("charge ≥ 1 bit on equal cells") is not needed there.

**`induce-row-order`: an example exists.** Five Boolean rows keyed by an integer input x0 = 1..5. The chain price is `value-bit-size(first)` + Σ `correction-bit-size(prev, next)` + `body-size(x0)` = 1 + (number of flips) + 2. The column T T T T T is charged 3 bits in all. Over the 32 possible columns Σ 2^−bits = **1.2656** (the chain alone: 5.0625), so no uniquely decodable code has these lengths. For n rows the sum is 1.5^(n−1)/4: 0.5625, 0.8438, 1.2656, 1.8984, 4.2715 for n = 3, 4, 5, 6, 8. The function returns its `chain-bits` only when it induces a key; that happens on 2 of the 256 eight-row columns, and on both my recomputation equals the kernel's number.

A decision it changes: eight Boolean rows F F F F T T T T. The kernel induces the key, chain 4 bits against a baseline of 5 (the "star", which has the same defect). Coding the eight targets independently costs 8 bits; the chain with one bit on each equal step would cost 10 and the key would not be induced.

**But `induce-row-order` and `with-induced-row-order` have no caller** in the root kernel or in `v2/` outside `tests/topology.lisp`. So the violation is not "live" in the synthesis pipeline today. It becomes live if row-order induction is wired in. It would also carry over to the new design: `plan_v2c.md` §6.1–6.2 makes a residual a column priced row by row, and summing the kernel's `correction` over every row of a column is exactly the dense sum above.

### 4.4 A second defect the review does not mention

`frame.lisp:1572` prices a sequence correction as the **minimum** of the delta code and the replacement code, with no bit saying which was used. The replacement code is complete on `(:seq :int)`, and the delta is strictly cheaper on some targets (d((1 2) → (1 3)) = 7 against 13). So the conditional Kraft sum exceeds 1 even with the v = u cell left out: from u = (1 2), over sequences of length ≤ 3 with elements in −3..3, the excess over the replacement code is 0.0688, giving a lower bound of 1.0686 for the full sum. `code-edit` (`frame.lisp:1619`) and the competing metric decoders in `priced-correction` (`frame.lisp:1663-1667`) have the same shape. Each is worth at most one bit per cell per alternative.

## 5. R5 — triangle inequality, symmetry, asymmetry

`./run-kernel.sh r5-metric`, `logs/r5-metric.log`. d = `correction-bit-size`. Every ordered triple of each grid.

| Grid | values | triples | violations | worst |
|:--|--:|--:|--:|:--|
| `:int`, all of −60..60 | 121 | 1,771,561 | 0 | |
| `:int`, ± magnitudes at powers of two up to 2²⁰ | 57 | 185,193 | 0 | |
| `(:gf p)`, p = 2, 3, 5, 7, 13, 31, all residues | | 32,491 in all | 0 | |
| `(:tuple :int :int)` over {−100, −1, 0, 1, 2, 50} | 36 | 46,656 | 0 | |
| `(:seq :int)`, all of length ≤ 3 over {−1, 0, 1, 2} | 85 | 614,125 | 0 | |
| `(:seq :int)`, 150 random, length ≤ 5, elements −3..3 | 150 | 3,375,000 | 0 | |
| `(:seq :int)`, 150 random, length ≤ 5, elements −20..20 | 150 | 3,375,000 | **2** | 1 bit |
| `(:seq :int)`, 150 random, length ≤ 5, elements −100..100 | 150 | 3,375,000 | **3** | 1 bit |
| `(:seq :int)`, length ≤ 4 over {0, 5} and length ≤ 3 over {0, 7, −100} | 67 | 300,763 | **49** | 6 bits |
| `:code`, one input, depth ≤ 2 over {x0, 0, 1, 2} and 60 random depth-3 | 112 | 1,404,928 | 0 | |
| `:code`, two inputs, depth ≤ 2 over {x0, x1, 0, 1} and 60 random depth-3 | 94 | 830,584 | 0 | |
| `:code`, two inputs, literals {0, 1, 1000, −77}, 150 random depth-3 | 227 | 11,697,083 | **10** | 4 bits |

The review's "0 violations" holds on small-value grids, which is probably what it sampled. It is not true of the price in general. The clearest counterexample:

- u = (−100 −100), v = (−100), w = (−100 0 0)
- d(u→w) = 21, d(u→v) + d(v→w) = 6 + 9 = 15.

Dropping an element is nearly free and appending a small one is cheap, while rewriting −100 to 0 in place costs 15 bits; the direct price does not consider the two-step route. So on `(:seq :int)` and `:code` the kernel's price is not a quasi-metric; its shortest-path closure would be. The statement in the review that it "is a Lawvere quasi-metric" needs that qualification. On `:int`, `(:gf p)` and tuples of them I found no violation.

**Integers.** d(0→Δ) = 0, 4, 5, 5, 8, 8, 9, 10, 14, 17 at Δ = 0, 1, 2, 3, 4, 5, 8, 16, 100, 1000, and the same at −Δ. d(0→Δ) = d(0→−Δ) = d(Δ→0) for every Δ in 1..1,000,000. d(u→v) depends only on v − u (checked for u in −50..50, v − u in −200..200).

**Asymmetry.** `(:seq :int)`: d(() → (1 2)) = 13, d((1 2) → ()) = 1. `:code`: d(x0 → x0+1) and back are 14 and 2 with one integer input in scope, **15 and 3 with two**, 16 and 4 with three or four, 17 and 5 with five. The review does not state the scope; its numbers are the two-input ones.

## 6. R6 — anti-unification

`./run-kernel.sh r6-au`, `logs/r6-au.log`. Root kernel, `anti-unify` (`unify.lisp:36-73`), x = `(var 0 :int)`, y = `(var 1 :int)`, z = `(var 2 :int)`.

| Sources | Pattern returned | Distinct holes |
|:--|:--|--:|
| `(+ x x)`, `(+ y y)` | `(+ ?0 ?0)` | 1 |
| `(+ x y)`, `(+ y x)` | `(+ ?0 ?1)` | 2 |
| `(+ x x)`, `(+ y z)` | `(+ ?0 ?1)` | 2 |
| `(* (+ x 1) (+ x 1))`, `(* (+ y 1) (+ y 1))` | `(* (+ ?0 1) (+ ?0 1))` | 1 |
| `(+ x x)`, `(+ y y)`, `(+ z z)` | `(+ ?0 ?0)` | 1 |
| `(+ x x)`, `(* y y)`, default | `(?0 ?1 ?1)`, ?0 an operator hole | 2 |
| `(+ x x)`, `(* y y)`, `:operator-holes-p nil` | `?0` | 1 |
| `(+ x 3)`, `(+ y 3)` | `(+ ?0 3)` | 1 |

The mechanism is where the review says: `disagreement` at `unify.lisp:48-50` keys a hash table on the tuple of disagreeing subterms, so equal tuples share a hole. That is "two varying columns collide into one class on the instance space", so the review's first correction to `plan_v2c.md` §5.4 is right against the code.

Rows 6 and 7 bear on the second correction: positions are aligned only under a shared operator, or under an operator hole when signatures agree; otherwise the whole subterm becomes one hole. The rest of that correction (cells that hold classes need a product of tree automata) is theory and I did not test it. One fact from the probe is relevant: a `cls` keeps only one representative term (`tg-probe.lisp:37-42`), so in the probe as built a cell holding a class has exactly one decomposition, and the problem the review describes arises only in a store that keeps every member.

## 7. Every modification to the probe

Three files exist. `tg-probe.lisp` is unmodified. `tg-probe-r1.lisp` has MODs 1–3. `tg-probe-r2.lisp` has MODs 1–6. Full diffs: `logs/diff-probe-r1.patch` (7 lines added, 2 removed), `logs/diff-probe-r1-r2.patch` (16 added, 0 removed), `logs/diff-probe-r2.patch`.

Regression: `./run-regress.sh` runs the original experiment D with `tg-probe-r2.lisp`; its log equals the repository's `proto/logs/d.log` with timings masked. The modifications change nothing the original measured.

| MOD | File : line | What | Why |
|:--|:--|:--|:--|
| 1 | `tg-probe-r1.lisp:217-220` (in `*all-ops*`; line 217 loses two closing parentheses, 218–220 are new) | new operator `call1b`, `(:pred :int) → :bool`; a `:pred` cell is one of the names `pos`, `even`, `neg` | R1c. Not added to `*d-ops*`; the driver binds it for filter only. With no `:pred` leaf it generates no candidates |
| 2 | `tg-probe-r1.lisp:323` (in `gen-example`) | input kind `:pred`, drawn uniformly from `pos even neg` | held-out predicate inputs for filter |
| 3 | `tg-probe-r1.lisp:344-345` (in `input-cols`) | a `:pred` input becomes a leaf of type `:pred` instead of `:int` | so that `call`, which expects `:code`, is never applied to a predicate name |
| 4 | `tg-probe-r2.lisp:229-233` | `*aggs*` (five fold algebras) and `agg-step` | R2 |
| 5 | `tg-probe-r2.lisp:249-253` (in `ev`) | evaluator clause for `(fold-space L agg (lambda (i) elem))` | R2, to verify on held-out examples |
| 6 | `tg-probe-r2.lisp:281-286` | `reduce-pmap`, the pushforward | R2 |

Added files that call probe internals but redefine nothing:

| File | Content |
|:--|:--|
| `r1-spec.lisp` | references (16–55), spec rows (64–124), `check-refs`, `held-out` (the probe's `verify` inside `handler-case`), `report`, `run-seq`, `run-scalar`, `breakdown`, `r1` |
| `r1-variants.lisp` | `permuted` (input order), `bank-size`, a trace of `cover` by `sb-int:encapsulate` (removed again after use) |
| `r1-variants2.lisp` | level trace for scan; map-adjacent under other settings; wider held-out ranges; `solve-fold-f`, a copy of the probe's `solve-fold` with `f` offered to the step bank |
| `r1-occam.lisp` | `*occam*` on all sequence-output specs |
| `r2-reduce.lisp` | `reduce-bank`, `run-reduce`, `solve-reduce-granted`, `shape-classes`, `solve-reduce`, driver |
| `r3-guard.lisp` | brute-force checks; uses only the probe's `ev` |
| `xref-dump.lisp`, `xref-kernel.lisp` | reference cross-check against the v2 kernel |
| `r4-kraft.lisp`, `r5-metric.lisp`, `r6-au.lisp` | root kernel only; no probe |

Choices of mine that affect numbers: the held-out ranges listed in §1; in R2, shapes limited to size ≤ 3 and to non-constant columns, total size ≤ 10, element size ≤ 9 when the shape is granted; in R3, the search windows; in R5, the grids.

## 8. Commands

All from `$W`. `./run-all.sh` runs everything in order (about 6 minutes).

```
./run-baseline.sh          # unmodified probe, experiment D        -> logs/baseline-d.log
./run-regress.sh           # modified probe, experiment D, diffed   -> logs/regress-d-r2.log
./run-r1.sh                # R1                                    -> logs/r1.log
./run-r1-variants.sh       # input order; split level              -> logs/r1-variants.log
./run-r1-variants2.sh      # scan levels; settings; wide held-out  -> logs/r1-variants2.log
./run-r1-occam.sh          # *occam* on all sequence specs         -> logs/r1-occam.log
./run-xref.sh              # references against the v2 kernel       -> logs/xref-kernel.log
./run-r2.sh                # R2                                    -> logs/r2.log
./run-r3.sh                # R3                                    -> logs/r3.log
./run-kernel.sh r4-kraft   # R4                                    -> logs/r4-kraft.log
./run-kernel.sh r5-metric  # R5                                    -> logs/r5-metric.log
./run-kernel.sh r6-au      # R6                                    -> logs/r6-au.log
```

Each is `timeout N sbcl --dynamic-space-size 8GB --noinform --non-interactive --load … > logs/….log 2>&1`. The kernel scripts load `$W/kernel/load.lisp` (root kernel, copied by `rsync` without `.git`, `*.pdf`, `plan_v2c_audit/scripts`); `xref-kernel.lisp` loads `$W/kernel/v2/load.lisp`, because only `v2/` holds `library/*.sexp`. No bootstrap was run anywhere. The kernel logs begin with about 1,400 lines of SBCL style warnings from loading; the results are at the end.

## 9. What surprised me

1. **Two details of the review's table do not reproduce and I cannot find the setting that gives them**: scan at 11,298 candidates (I get 11,604 under every input order) and the map-adjacent impostor at "size 19, level 7" (27 nodes, level 8). The rest of that table matches to the candidate, including 616,232 and 64 ms, so the modified probe the reviewer ran was close to mine but not identical, or those two figures were mis-transcribed.
2. **The triangle inequality fails** for the kernel's price on sequences and on code once element values are large. The review reports zero violations and builds "Lawvere quasi-metric" on it.
3. **The Kraft violation is real per cell but is not where the review puts it.** Stage A pays for the positions of exceptions; what it omits is one bit per model. The dense sum is in `induce-row-order`, which nothing calls.
4. **A second Kraft defect**, the unpaid minimum at `frame.lisp:1572`, is independent of line 1581.
5. **The probe returns wrong programs rather than `NIL`** on argmax-corr and best-shift, and the pushforward I added does the same on foldl and argmax-corr. With three to nine rows every first-fit mechanism here overfits; `*occam*` fixed all eight sequence specs at 600–800× the cost on the two that need a guard.
6. **The foldl impostor is not a size contest in the probe as it stands**: the right step is outside its step bank.
7. **The guard of R3a evaluates to `:err`, not false, at b = 0** in the probe's own strict `and`.
8. **The kernel spec row (15, 3) → 5 has two preimages**, so the spec the review calls hand-chosen is ambiguous on its own rows.
9. **len-all and last-or are solved by the unlifted path**; the review groups them with the two that overfit.
10. **shift-seq's 200/200 depends on `k ≥ 0`** in the held-out set (174/200 otherwise).
