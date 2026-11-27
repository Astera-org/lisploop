# cross-space — how well do cheap, store-derived signals prioritize a search across spaces?

Agent `cross-space`. Three measurements added to a copy of the store prototype (`tg-probe.lisp`, unmodified). Nothing under `/home/tlh24/lisploop` was created, changed or run. Everything is seeded; candidate counts are deterministic, timings vary by a few percent. Every number below is copied from a log in `cross-space/logs/`.

The question behind all three: inside one space, evaluating and hashing is polynomial; relating two spaces means *finding* a correspondence, which is a search, while *checking* a proposed one is cheap. How far do signals the store produces for almost nothing (classes that are true on a task's rows, law flags of an operator's table, colours from group-by) go in ordering that search?

## 0. Bottom line

- **M1. Signatures are almost free and they do find the same program form. They do not find the operators, and that is where the search cost is.**
  - Cost: 648 candidates (0.27 M cells) for the size-3 pool and 33,624 candidates (14 M cells) for the size-5 pool, for all 30 tasks at once. Solving the 30 tasks with the full grammar takes 10.1 M candidates.
  - Form: the nearest neighbour has the same program form for 48% of tasks (size-3 pool) and 54% (size-5 pool), against 15% by chance and 32% from input/output types alone. The first same-form task sits at mean rank 3.5 and 3.1, against 6.0 by chance.
  - Operators: the three nearest neighbours' operators contain every operator the task needs for 57% of tasks, against 49% for three random tasks.
  - Search: a grammar restricted to those operators gives a held-out-correct program in 67% (size 3) and 66% (size 5) of attempts. Three random tasks give 58%. A control that uses no signature at all (the four most frequent operators in the rest of the pool) gives 69%.
  - Honest total cost, "restricted attempt, then the full grammar if it fails": 1.09× and 0.95× the full grammar summed over tasks, 1.34× and 1.36× when the one task that is 79% of the total is left out, and 0.83× and 0.77× as a geometric mean per task (random: 1.86×). With the attempt cut off at 100,000 candidates: 0.79× and 0.72× without the largest task, 0.72× and 0.68× geometric mean. The signature-free control does better under that cap (0.61×, 0.60×).
  - Ceiling: restricting each task to its own operators costs 0.017× in total and 0.085× per task. So operator choice is worth 12× to 60×, and this signature captures almost none of it.
- **M2. Checking an analogy between two operators is cheap enough that pre-filters hardly matter.** All 350 triples (14 maps × 25 operator pairs) are tested in 1.3 ms; 29 non-trivial homomorphisms are found; none is false on 1,000 fresh rows. 96% of the 316 failing triples are rejected by the first row read. Comparing commutative / idempotent / associative flags of the two operators skips 35% of the failing triples, and it is not sound: with a richer bank of maps it skips a true one. Three rows are enough to accept no false triple with this bank; a richer bank needs 16.
- **M3. Colour refinement from group-by and re-index finds the row correspondence without search wherever rows differ locally, and backtracking appears exactly where they do not.**
  - Sparse random graphs: 99.8% to 100% of nodes get a unique colour in 3 or 4 rounds; n = 10,000 takes 0.16 s.
  - Trees, sparser graphs, a grid, a cycle: individual choices are needed (up to 1,586 of them) but none is ever undone. The cost is one whole-column pass per choice, so trees go from 48 ms at n = 1,000 to 5.4 s at n = 10,000.
  - Backtracking: about n/2 on random 3-regular graphs; n on two cycles against one (rejected, in time growing as n³); and 48 → 594 → 10,716 → 257,214 on 12 → 30 nodes when a non-isomorphic pair is made of interchangeable parts.
- **Across the three:** rejection is cheap everywhere (one row, one round). The cheap signals order the search well when the objects are generic, and say nothing when they are regular: scans that all satisfy "same length", operators that are all commutative and associative, nodes that all have degree 3. Proving that *no* correspondence exists is the expensive direction.

## 1. Files, commands, environment

Directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/cross-space/`

| file | lines | content |
|:--|--:|:--|
| `tg-probe.lisp` | 874 | the prototype, byte-identical to `plan_v2c_audit/proto/tg-probe.lisp` (`cmp` passes); no change was needed |
| `xs-m1.lisp` | 662 | M1: my 12 pool tasks and the 4 I dropped (see 2.1), one solver entry point, signatures, retrieval, restricted grammars, controls |
| `xs-m2.lisp` | 221 | M2: map bank, homomorphism test by re-index, pre-filters, sequence maps |
| `xs-m3.lisp` | 238 | M3: graph as two spaces, refinement, individualization with backtracking, generators |
| `run.sh` | 13 | driver |
| `logs/m1.log`, `logs/m2.log`, `logs/m3.log` | 1,592 / 165 / 40 | all results |
| `logs/dev/` | | four development logs, kept as evidence for section 2.1 (dropped tasks) and section 6 (shared seeds); not otherwise used |

Commands, run from that directory:

```
./run.sh m1     # 272 s   -> logs/m1.log
./run.sh m2     #   2 s   -> logs/m2.log
./run.sh m3     #  45 s   -> logs/m3.log
```

`run.sh` is `timeout ${TMO:-3600} sbcl --dynamic-space-size 8GB --control-stack-size 200MB --noinform --non-interactive --load tg-probe.lisp --load xs-<name>.lisp --eval "(tg::<name>)" > logs/<name>.log 2>&1`.

Environment: SBCL 2.6.4.debian, 16 threads available, one used, 31 GB RAM. The prototype's clock has 4 ms resolution; M2 and M3 use `sb-ext:get-time-of-day` (1 µs).

Units, as in the prototype report: a **candidate** is one operator applied down one column; **cells** = candidates × rows.

## 2. M1 — do store-generated signatures prioritize inter-task mixing?

### 2.1 Task pool

30 tasks: the prototype's 15 sequence tasks, its 3 fold tasks, and 12 of mine. "Form" is read off the program the standard procedure emits with the full 12-operator grammar: `tab` = `tabulate` without guard or `prev`; `tabg` = `tabulate` with an `if`; `rec` = body uses `prev`; `sel`, `where`, `fold`. All 30 are solved 200/200 with the full grammar on all five example sets, with the same form each time. Counts by form: tab 8, tabg 4, rec 5, sel 4, where 4, fold 5.

The table is replicate 1. "P3 size" and "P5 size" are signature sizes (section 2.2); "mean" is over the five replicates.

| # | task | from | reference function | form found | operators in the body | full-grammar candidates | P3 size | P5 size | P3 mean | P5 mean |
|--:|:--|:--|:--|:--|:--|--:|--:|--:|--:|--:|
| 0 | reverse | proto | reverse of `xs` | tab | `(at - +)` | 86,452 | 8 | 147 | 9.6 | 89.0 |
| 1 | shift-seq (spec) | proto | `out[i] = xs[i+k]`, 0 past the end; k in 0..3 | tabg | `(< - at +)` | 9,169 | 4 | 95 | 4.2 | 78.8 |
| 2 | rotate-left k | proto | `out[i] = xs[(i+k) mod n]`; k in 0..3 | tab | `(at mod +)` | 218,927 | 4 | 66 | 5.6 | 70.4 |
| 3 | map-adjacent + | proto | `out[i] = xs[i+1] + xs[i]` | tab | `(at +)` | 276,712 | 7 | 214 | 6.4 | 145.6 |
| 4 | map-adjacent - | proto | `out[i] = xs[i+1] - xs[i]` | tab | `(- + at)` | 685,732 | 5 | 77 | 6.6 | 93.8 |
| 5 | running-sum | proto | `out[i] = xs[0]+..+xs[i]` | rec | `(< + at)` | 4,775 | 4 | 55 | 4.0 | 82.4 |
| 6 | scan + init a (spec) | proto | `out[i] = a + xs[0]+..+xs[i]`; a in -5..9 | rec | `(< + at)` | 9,161 | 1 | 36 | 5.0 | 97.0 |
| 7 | scan 2*acc-x init a | proto | `acc <- 2*acc - x` from `a`, trace; a in -3..3 | rec | `(< + - at)` | 286,780 | 3 | 29 | 6.0 | 71.2 |
| 8 | positions (spec) | proto | `out[i] = k + i`; k in 0..4 | tab | `(+)` | 3 | 19 | 311 | 12.4 | 191.6 |
| 9 | positions-of v | proto | indices j with `xs[j] = v` (v mostly drawn from xs) | where | `(=)` | 8,172 | 14 | 104 | 13.0 | 126.0 |
| 10 | filter x>k | proto | elements `> k`; k in -3..7 | sel | `(<)` | 7,226 | 12 | 279 | 13.0 | 280.8 |
| 11 | take k | proto | first `min(k, n)` elements; k in 0..8 | tab | `(at)` | 267 | 3 | 77 | 4.4 | 122.0 |
| 12 | zip-add | proto | `out[i] = xs[i] + zs[i]`, length `min` | tab | `(+ at)` | 28,243 | 2 | 58 | 19.6 | 340.4 |
| 13 | map-adjacent f (spec) | proto | `out[i] = f(xs[i+1], xs[i])`; f one of + - * per example | tab | `(call + at)` | 7,927,021 | 8 | 123 | 5.4 | 70.2 |
| 14 | scan f init a (spec) | proto | `acc <- f(acc, x)` from `a`, trace | rec | `(< call at)` | 14,018 | 1 | 57 | 1.4 | 35.0 |
| 15 | shift-right k | mine | `out[i] = 0` if `i < k` else `xs[i-k]`; k in 0..3 | tabg | `(not < at -)` | 8,878 | 16 | 228 | 5.8 | 103.6 |
| 16 | prepend k | mine | `(k . xs)`; k in -5..9 | tabg | `(< at -)` | 9,771 | 5 | 93 | 10.8 | 160.6 |
| 17 | append k | mine | `xs ++ (k)`; k in -5..9 | tabg | `(< at)` | 298 | 4 | 53 | 4.8 | 82.8 |
| 18 | running-max | mine | `out[i] = max(xs[0..i])` | rec | `(< max at)` | 4,767 | 11 | 166 | 8.2 | 110.6 |
| 19 | remove v | mine | `xs` without the elements equal to `v` | sel | `(not =)` | 8,401 | 11 | 140 | 6.8 | 140.0 |
| 20 | keep positive | mine | elements `> 0` | sel | `(<)` | 957 | 9 | 254 | 10.0 | 244.4 |
| 21 | keep even x | mine | even elements | sel | `(= mod +)` | 91,604 | 1 | 58 | 4.0 | 75.0 |
| 22 | positions x>k | mine | indices j with `xs[j] > k`; k in -3..7 | where | `(<)` | 7,930 | 14 | 277 | 12.2 | 228.6 |
| 23 | positions of negatives | mine | indices j with `xs[j] < 0` | where | `(<)` | 1,365 | 19 | 293 | 15.2 | 219.6 |
| 24 | positions of even x | mine | indices j with `xs[j]` even | where | `(= mod +)` | 92,260 | 8 | 158 | 13.2 | 167.8 |
| 25 | sum | proto | sum of `xs` | fold | `(+)` | 53,541 | 2 | 16 | 3.2 | 23.6 |
| 26 | alternating sum | proto | `x0 - x1 + x2 - ...` | fold | `(-)` | 58,685 | 5 | 17 | 1.2 | 7.6 |
| 27 | horner base 2 | proto | fold `acc <- 2*acc + x` from 0 | fold | `(+)` | 69,995 | 2 | 11 | 1.0 | 7.4 |
| 28 | product | mine | product of `xs` | fold | `(*)` | 54,407 | 1 | 3 | 0.8 | 3.8 |
| 29 | sum of squares | mine | sum of `x*x` | fold | `(+ *)` | 65,738 | 2 | 39 | 3.8 | 39.4 |

Sequences have length 0 to 7 with values −5..9, 12 examples per task (the prototype's settings).

The pool was built so that form and operators are not the same thing: `filter x>k` / `positions x>k`, `remove v` / `positions-of v` and `keep even x` / `positions of even x` are pairs with the same predicate and different forms.

**Four tasks I tried and dropped**, because the standard procedure with the *full* grammar returns impostors for them (`logs/m1.log`, "tasks tried and EXCLUDED"; five example sets each, seeds 1 to 5):

| task | full grammar: correct | mean candidates | only `at` + intended operators: correct | mean candidates |
|:--|:--|--:|:--|--:|
| keep a<x<b | 4/5 | 578,965 | 4/5 | 17,158 |
| keep x<=k | 5/5 here; impostor `(< x k)`, 140/200, on the first replicate set I drew (seed 1021, `logs/dev/m1-dev2.log`) | 7,874 | 5/5 | 7,612 |
| max with floor k | 0/5 | 756,589 | 5/5 | 696 |
| max with floor 0 | 3/5 | 60,907 | 5/5 | 212 |

The last two are worth a note in their own right: the scalar route's last-resort nested split invents a case analysis (for example 32/200 held-out), and restricting the grammar to `{at, max}` turns 0/5 into 5/5 at a thousandth of the cost. A restricted grammar is also a regularizer.

### 2.2 (a) Signature

**Construction.** One shared space: 64 generic probe rows, then the 12 example rows of every task (424 rows). Generic leaves are columns on it:

- per sequence input k: `(len sK) (sum sK) (min sK) (max sK)`; per integer input: `nK`;
- for a sequence output: `(len out) (first out) (last out) (sum out) (min out) (max out)`; for an integer output: `outv`;
- constants `0`, `1`.

That is 18 leaves for this pool (two sequence inputs, one integer input). A leaf a task does not have is `:err` on that task's rows; `min`, `max`, `first`, `last` of an empty sequence are `:err`. On the probe rows every leaf is computed from independent random sequences and integers.

The prototype's enumerator then builds every Boolean class. A class on this shared space is a **property**. It **holds** for a task when its column, restricted to that task's 12 rows, has no false cell and is true on at least 6. The task's **signature** is the set of properties that hold. Nothing is written per task.

Canonical naming comes from the store itself: two terms are the same property exactly when they are one class on the shared space, that is, equal on the 64 probe rows and on every task's rows. The probe rows are what makes this a cross-task identity; the reviewer's "explicit probe evaluation" is here 64 extra rows in the one bank. Classes with no false cell on the probe rows are tautologies of the leaves (such as `(< (min s1) (+ (max s1) 1))`) and are dropped.

Two pools:

- **P3**, the literal reading of the spec: operators `=` and `<` only, so every property has size 3.
- **P5**: `+` and `−` allowed under the comparison, size ≤ 5. This adds properties such as `(= 1 (- (len out) (len s1)))` and `(= (sum s1) (- (last out) n1))`.

| pool (replicate 1) | candidates | cells | ms | Boolean classes | tautologies dropped | pool | hold for ≥ 1 task |
|:--|--:|--:|--:|--:|--:|--:|--:|
| P3 | 648 | 274,752 | 4 | 454 | 8 | 446 | 74 |
| P5 | 33,624 | 14,256,576 | 132 | 7,492 | 27 | 7,465 | 840 |

Over the five replicates the pool is 443 to 446 (P3) and 7,388 to 7,465 (P5); the number holding for at least one task is 74 to 87 and 840 to 1,131.

**Signature sizes** are in the table of 2.1. Replicate 1: P3 from 1 to 19, mean 6.8, and 8 of the 30 tasks have at most 2 properties; P5 from 3 to 311, mean 118. Sizes move a lot between example sets (zip-add: 2 properties in replicate 1, 19.6 on average), because most properties are inequalities that 12 rows satisfy by accident.

Examples (replicate 1, P3, complete signatures):

```
rotate-left k    (= (len s1) (len out)) (= (sum s1) (sum out)) (= (min s1) (min out)) (= (max s1) (max out))
scan + init a    (= (len s1) (len out))
prepend k        (= n1 (first out)) (< 0 (max s1)) (< 0 (len out)) (< (len s1) (len out)) (< (min out) (max s1))
running-sum      (= (len s1) (len out)) (= (sum s1) (last out)) (< 0 (len s1)) (< 0 (len out))
sum              (= (sum s1) outv) (< 0 (len s1))
product          (< 0 (len s1))
```

### 2.3 (b) Leave-one-out retrieval

Each task is given its own example seed (`1000·s + i` for replicate s and task i). Five replicates; the table is their mean. Similarity is Jaccard. Ties are given their expected value under a random tie-break.

| signature | nearest neighbour has the same form | chance | mean rank of first same-form task | chance | nearest neighbour shares ≥ half of the operators | chance | mean rank of first such task | chance |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| P3 | 0.482 | 0.152 | 3.53 | 6.00 | 0.599 | 0.425 | 2.60 | 3.57 |
| P5 | 0.543 | 0.152 | 3.06 | 6.00 | 0.607 | 0.425 | 2.40 | 3.57 |
| P3 + first/last of the inputs | 0.494 | 0.152 | 3.54 | 6.00 | 0.588 | 0.425 | 2.60 | 3.57 |
| P3 without input-only properties | 0.507 | 0.152 | 3.57 | 6.00 | 0.573 | 0.425 | 2.82 | 3.57 |
| P5 without input-only properties | 0.537 | 0.152 | 3.25 | 6.00 | 0.643 | 0.425 | 2.43 | 3.57 |
| P5, equalities only | 0.469 | 0.152 | 3.58 | 6.00 | 0.579 | 0.425 | 2.87 | 3.57 |
| types only (which leaves exist) | 0.318 | 0.152 | 3.91 | 6.00 | 0.471 | 0.425 | 2.56 | 3.57 |
| P3 from 48 other examples per task | 0.464 | 0.152 | 3.61 | 6.00 | 0.544 | 0.425 | 3.06 | 3.57 |
| P5 from 48 other examples per task | 0.673 | 0.152 | 2.53 | 6.00 | 0.671 | 0.425 | 2.39 | 3.57 |

Per replicate, nearest-neighbour same-form: P3 0.62, 0.42, 0.43, 0.45, 0.50; P5 0.53, 0.57, 0.54, 0.53, 0.54.

"Shares at least half of the operators" compares operator sets of the lambda bodies with `at` left out (it is always kept). Its chance rate is high, 0.425, because many solutions use one or two operators.

By form of the held-out task (nearest neighbour has the same form, pooled over replicates):

| form | n | P3 | P5 | types only | chance |
|:--|--:|--:|--:|--:|--:|
| tab | 8 | 0.41 | 0.38 | 0.27 | 0.24 |
| tabg | 4 | 0.40 | 0.30 | 0.23 | 0.10 |
| rec | 5 | 0.44 | 0.40 | 0.14 | 0.14 |
| sel | 4 | 0.35 | 0.55 | 0.09 | 0.10 |
| where | 4 | 0.97 | 0.85 | 0.09 | 0.10 |
| fold | 5 | 0.42 | 0.90 | 1.00 | 0.14 |

**Operator coverage**, the number that matters for (c): do the k nearest neighbours' operators contain every operator of the task's own solution?

| k | P3 | P5 | types only | k random tasks | mean grammar size (P3) |
|--:|--:|--:|--:|--:|--:|
| 1 | 0.31 | 0.31 | 0.20 | 0.22 | 2.9 |
| 2 | 0.46 | 0.45 | 0.33 | 0.38 | 4.1 |
| 3 | 0.57 | 0.57 | 0.43 | 0.49 | 5.0 |
| 5 | 0.69 | 0.70 | 0.53 | 0.62 | 6.1 |
| 8 | 0.74 | 0.84 | 0.80 | 0.72 | 7.3 |

The gain over random is 7 to 9 points for k from 1 to 5.

Reading:

- The form signal is real: three times chance, and half again above what types give.
- `where` is recognized almost always, because index lists share `(= (first out) (min out))` and `(= (last out) (max out))`: the output is sorted.
- More rows help P5 (0.54 → 0.67 with 48 rows) and not P3. P5's weakness is accidental inequalities, which rows remove. P3's is too few properties, which rows do not add.
- The operator signal is weak at every k.

### 2.4 (c) Does it save search?

For each held-out task: grammar = `at` plus every operator in the lambda bodies of its 3 nearest neighbours' solutions (guard comparisons are in those bodies, so they are kept). Then the prototype's standard procedure. Size limit 10, budget 12 M candidates.

"Correct" means 200/200 on the prototype's held-out examples. **Fair cost** = candidates of the restricted attempt, plus the full grammar's candidates whenever the attempt is not correct.

**Per task, replicate 1, P3.** "random" is 5 draws of 3 other tasks. "oracle" is the task's own operators plus `at`.

| task | full | NN3 result | NN3 cand | fair cost | ratio | random: correct | random: fair (mean) | ratio | oracle cand | NN3 grammar |
|:--|--:|:--|--:|--:|--:|:--|--:|--:|--:|:--|
| reverse | 86,452 | fail | 270,899 | 357,351 | 4.13 | 2/5 | 117,734 | 1.36 | 5,903 | `(mod < max call + at)` |
| shift-seq (spec) | 9,169 | ok | 1,816 | 1,816 | 0.20 | 4/5 | 7,431 | 0.81 | 1,816 | `(- call < + at)` |
| rotate-left k | 218,927 | IMPOSTOR | 158,656 | 377,583 | 1.73 | 1/5 | 439,431 | 2.01 | 14,493 | `(- call < + at)` |
| map-adjacent + | 276,712 | ok | 3,170 | 3,170 | 0.01 | 5/5 | 51,142 | 0.18 | 2,339 | `(< call at +)` |
| map-adjacent - | 685,732 | ok | 44,479 | 44,479 | 0.07 | 1/5 | 591,955 | 0.86 | 38,208 | `(- at + not = <)` |
| running-sum | 4,775 | ok | 731 | 731 | 0.15 | 4/5 | 46,565 | 9.75 | 349 | `(call < + at *)` |
| scan + init a (spec) | 9,161 | ok | 1,816 | 1,816 | 0.20 | 5/5 | 1,459 | 0.16 | 578 | `(call - < + at)` |
| scan 2*acc-x init a | 286,780 | fail | 423,601 | 710,381 | 2.48 | 0/5 | 583,485 | 2.04 | 18,117 | `(call < at = mod +)` |
| positions (spec) | 3 | ok | 3 | 3 | 1.00 | 5/5 | 34 | 11.27 | 3 | `(max at + <)` |
| positions-of v | 8,172 | ok | 8,028 | 8,028 | 0.98 | 3/5 | 302,700 | 37.04 | 7,956 | `(at = mod + <)` |
| filter x>k | 7,226 | ok | 7,046 | 7,046 | 0.97 | 5/5 | 7,060 | 0.98 | 6,974 | `(+ < max at)` |
| take k | 267 | ok | 123 | 123 | 0.46 | 5/5 | 123 | 0.46 | 51 | `(not at - < +)` |
| zip-add | 28,243 | ok | 1,952 | 1,952 | 0.07 | 5/5 | 6,467 | 0.23 | 1,564 | `(call + at not =)` |
| map-adjacent f (spec) | 7,927,021 | fail | 227,624 | 8,154,645 | 1.03 | 0/5 | 8,101,229 | 1.02 | 42,118 | `(- < max at +)` |
| scan f init a (spec) | 14,018 | fail | 156,991 | 171,009 | 12.20 | 0/5 | 203,913 | 14.55 | 658 | `(- < + at)` |
| shift-right k | 8,878 | ok | 2,452 | 2,452 | 0.28 | 4/5 | 67,740 | 7.63 | 887 | `(not = < - at +)` |
| prepend k | 9,771 | fail | 17,267 | 27,038 | 2.77 | 4/5 | 277,164 | 28.37 | 857 | `(call + at <)` |
| append k | 298 | ok | 118 | 118 | 0.40 | 5/5 | 147 | 0.49 | 46 | `(< - + at)` |
| running-max | 4,767 | fail | 44,096 | 48,863 | 10.25 | 0/5 | 256,329 | 53.77 | 244 | `(- call + at)` |
| remove v | 8,401 | fail | 146,937 | 155,338 | 18.49 | 0/5 | 735,575 | 87.56 | 8,149 | `(not < - + at)` |
| keep positive | 957 | ok | 857 | 857 | 0.90 | 5/5 | 847 | 0.89 | 782 | `(< max at - +)` |
| keep even x | 91,604 | fail | 57,248 | 148,852 | 1.62 | 0/5 | 153,769 | 1.68 | 8,116 | `(< + at -)` |
| positions x>k | 7,930 | ok | 7,822 | 7,822 | 0.99 | 5/5 | 7,750 | 0.98 | 7,678 | `(= mod + not < at -)` |
| positions of negatives | 1,365 | ok | 1,265 | 1,265 | 0.93 | 3/5 | 35,596 | 26.08 | 1,190 | `(at < mod + =)` |
| positions of even x | 92,260 | fail | 1,453 | 93,713 | 1.02 | 1/5 | 163,524 | 1.77 | 8,140 | `(at = <)` |
| sum | 53,541 | ok | 2,574 | 2,574 | 0.05 | 5/5 | 6,160 | 0.12 | 457 | `(* + at <)` |
| alternating sum | 58,685 | ok | 16,861 | 16,861 | 0.29 | 4/5 | 17,457 | 0.30 | 1,057 | `(not < at - = mod +)` |
| horner base 2 | 69,995 | ok | 20,693 | 20,693 | 0.30 | 4/5 | 16,323 | 0.23 | 459 | `(= mod < + - at)` |
| product | 54,407 | fail | 1,210 | 55,617 | 1.02 | 0/5 | 70,348 | 1.29 | 206 | `(+ at <)` |
| sum of squares | 65,738 | fail | 4,074 | 69,812 | 1.06 | 0/5 | 69,068 | 1.05 | 1,710 | `(< call at - =)` |

Replicate 1 totals: full 10,091,255; NN3 fair 10,492,008 (1.04×); random 12,338,528 (1.22×); oracle 181,105 (0.018×). NN3 correct 18/30, one impostor, 11 without a program. On the 18 it solved, NN3 cost 121,806 candidates against 1,231,109 for the full grammar (0.10×). The same tables for P5, for types only, for the control, and for replicates 2 to 5 are in `logs/m1.log`.

**Aggregate, mean over five replicates** (30 tasks each; 150 restricted attempts per row, 750 for random):

| restriction from | correct | impostor | no program | total, no cap | total without the largest task | geo-mean per task | tasks cheaper than full (of 30) | total without largest, 100k cap | geo-mean, 100k cap |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| P3, 3 nearest | 0.673 | 0.027 | 0.300 | 1.094 | 1.336 | 0.829 | 18.0 | 0.790 | 0.722 |
| P5, 3 nearest | 0.660 | 0.027 | 0.313 | 0.946 | 1.363 | 0.768 | 18.0 | 0.719 | 0.682 |
| types only, 3 nearest | 0.493 | 0.013 | 0.493 | 0.981 | 0.882 | 0.668 | 13.0 | 0.882 | 0.668 |
| control: 4 most frequent operators of the other tasks | 0.693 | 0.060 | 0.247 | 1.196 | 1.893 | 0.729 | 19.4 | 0.613 | 0.602 |
| 3 random other tasks | 0.576 | 0.036 | 0.388 | 1.204 | 1.888 | 1.861 | 13.4 | 1.058 | 1.350 |
| oracle: own operators | 1.000 | 0 | 0 | 0.017 | 0.064 | 0.085 | 29.0 | 0.064 | 0.085 |

All cost columns are ratios to the full grammar. Correct attempts per replicate, of 30: P3 18, 21, 20, 22, 20; P5 21, 20, 19, 19, 20; control 20, 21, 21, 21, 21; random 85, 88, 88, 85, 86 of 150.

What the numbers say:

1. **The restriction is right two times in three, and that is barely above random and equal to a control that never looks at the task.** The control's grammar is `{at + < − =}` for almost every task.
2. **Without a cap, falling back costs more than restricting saves.** A miss costs the whole failed enumeration (up to 1.5 M candidates for a task whose full-grammar cost is 14,000) and then the full run.
3. **One task decides the totals.** `map-adjacent f` is 79% of the full-grammar candidates. Its `call` operator comes only from `scan f`, and the generic leaves contain nothing about a function-valued input, so it is missed in nearly every attempt. The "without the largest task" and geometric-mean columns are the ones to read.
4. **With the attempt cut at 100,000 candidates** the signature restriction saves 21% to 28% of the total and 28% to 32% per task. The control saves 39% and 40%.
5. **The ceiling is far away.** Own operators: 6% of the cost without the largest task, 8.5% per task.
6. **Missing an operator is not always a miss, and can be worse than one.** `prepend k` without `−` is still solved 200/200 in three replicates, by a longer program, for 517,887 to 521,887 candidates against about 9,670 (54×). `shift-right k` in replicate 3: 978,864 against 9,171 (107×). Summed over replicates, the attempts that succeeded cost 0.56× the full grammar for P3 and 0.17× for P5.
7. **Restricted grammars return wrong programs that fit the 12 examples**: 4 of 150 attempts for P3, 4 for P5, 9 for the control, 27 of 750 for random. Example: `rotate-left k` without `mod` gives `(if (< i (- (len xs) k)) (at xs (+ i k)) (at xs (+ i (- k (len xs)))))`, 181/200. A system with no held-out rows would accept these. The fair cost above assumes they are detected.

Operators missing from the P3 grammars, summed over the five replicates: `−` 15, `+` 13, `mod` 12, `call` 9, `*` 8, `not` 8, `=` 7, `max` 5, `<` 3.

The cap figures are computed after the fact from the uncapped runs: an attempt that had not finished by the cap is charged the cap and counted as returning nothing.

### 2.5 Added: does the form help choose the route?

The form is what the signature does retrieve, so I measured the one place the standard procedure uses it: it tries `tabulate` (or a scalar term) first and `select` / `where` / `fold` second. With the full grammar, replicate 1:

| policy | total candidates | ratio | tasks sent to the second route first | route choice right (of 30) |
|:--|--:|--:|--:|--:|
| standard order | 10,091,255 | 1.000 | 0 | 17 |
| always the second route first | 9,754,323 | 0.967 | 30 | 13 |
| oracle (own form) | 9,754,328 | 0.967 | 13 | 30 |
| nearest neighbour's form, P3 | 9,828,003 | 0.974 | 13 | 26 |
| nearest neighbour's form, P5 | 9,763,604 | 0.968 | 16 | 23 |
| nearest neighbour's form, types only | 9,786,144 | 0.970 | 16 | 17 |
| form of a random other task (expected) | 9,951,835 | 0.986 | | |

Means over five replicates: 0.966 (always second first), 0.966 (oracle), 0.979 (P3), 0.970 (P5), 0.969 (types), 0.985 (random).

The second route costs nothing when it does not apply: the subsequence alignment fails at once and a fold search is at most a few hundred programs. So "always try it first" equals the oracle and no signature is needed. What the standard order wastes is 336,927 candidates, 3.3% of the total. About 302,000 of that is the scalar search on the five fold tasks, 53,000 to 70,000 candidates each and 99.9% of those tasks' cost. One by-product: with the second route first, `take k` comes out as `(select xs (lambda (j x) (< j k)))`, 200/200.

### 2.6 (d) Where the signature was uninformative or misleading

The generic leaves see a sequence only through its length, ends, sum, minimum and maximum, so anything that happens *between* positions is invisible. All of the following are from replicate 1, P3. Every recurrence shows only "same length": the whole signature of `scan + init a` and of `scan f init a` is `(= (len s1) (len out))`, which `shift-seq`, `shift-right`, `rotate-left`, `reverse`, `running-sum` and `positions` satisfy too. Folds show almost nothing, and what they show is about the sample: `product` has the single property `(< 0 (len s1))`, which says that its 12 examples happened to contain no empty list, and `sum of squares` has Jaccard 0 to every other task; types alone retrieve folds perfectly (1.00) while P3 gets 0.42, so here the richer signature is worse than its own type bit. It is actively misleading for `running-max`, whose nearest neighbour is `reverse` (0.46): both satisfy `(= (len s1) (len out))` and `(= (max s1) (max out))` and four accidents such as `(< 1 (max s1))`, so the restricted grammar lacks `max` and `<`, and with P5 an impostor came back (94/200). `keep even x` lands next to `horner base 2`, a fold, through one shared accident, `(< (min s1) (len s1))`, while its true analogue `positions of even x` shares nothing with it, because one returns values and the other indices. Parity is not expressible with `+ − = <` over aggregates, which is why `mod` is the third most often missing operator; `call` is missing because a function-valued input is not a leaf at all. And the signature is noisy: `zip-add` has 2 properties in one example set and 19.6 on average, and `remove v` ends up nearest to `shift-right k` (0.35) on inequalities such as `(< (min out) (len s1))` alone.

## 3. M2 — analogy as a verified map between two operators' tables

### 3.1 Integer operators

Maps f: the classes of a bank over one variable, grammar `{neg + *}`, leaves `x 0 1 2`, sizes ≤ 4, on the space x = −36..36. That is 93 candidates, 23 classes, 14 of them non-constant. Grid: a, b in −6..6, 169 rows. `f(a)` is a re-index of f's column along the map "row → row a + 36 of the f space" (the prototype's `pull`); the test `f(op1(a,b)) = op2(f(a), f(b))` is three re-indexes per (f, op1), then one column operation and one column comparison per triple.

| | |
|:--|--:|
| triples tested (14 maps × 5 × 5 operators) | 350 |
| hold on the grid | 34 |
| of which trivial (identity map, op1 = op2) | 5 |
| listed | 29 |
| false on 1,000 fresh rows, values to ±1000 | 0 |
| time: map bank / all 350 tests (mean of 20 passes) | 0.09 ms / 1.32 ms |

Found:

| f | op1 → op2 |
|:--|:--|
| `(neg x)` | + → +, − → −, max → min, min → max |
| `(+ x x)` | + → +, − → −, max → max, min → min |
| `(neg (+ x x))` | + → +, − → −, max → min, min → max |
| `(+ x 1)`, `(+ x 2)`, `(+ x (neg 1))`, `(+ x (neg 2))` | max → max, min → min |
| `(neg (+ x 1))`, `(neg (+ x 2))`, `(+ 1 (neg x))`, `(+ 2 (neg x))` | max → min, min → max |
| `(* x x)` | * → * |

These are the linear maps for + and −, the increasing maps for max and min, the decreasing maps exchanging max and min, and squaring for *.

**Pre-filters**, over the 316 failing triples and the 29 true ones:

| filter | tests it needs | failing triples skipped | true triples wrongly skipped |
|:--|--:|--:|--:|
| F1, operators only: op1 has one of commutative / idempotent / associative that op2 lacks | 15 | 112 (35%) | 0 |
| F2, per (f, op1): a law of op2 pulled back, `f(op1(a,b)) = f(op1(b,a))` if op2 is commutative, `f(op1(a,a)) = f(a)` if idempotent | 140 | 108 (34%) | 0 |
| F3, per (f, op2): a law of op1 must hold for op2 on the image of f | 140 | 112 (35%) | 0 |
| F2 or F3 | 280 | 220 (70%) | 0 |
| reading rows until the first counterexample | 0 | — | — |

Flags measured from the tables (commutative, idempotent, associative): `+` yes/no/yes, `−` no/no/no, `*` yes/no/yes, `max` and `min` yes/yes/yes.

Early exit, in a seeded random row order: the first counterexample comes after 1.05 rows on average (median 1, maximum 3). 96% of failing triples are rejected by the first row, 99% by the second. Cells read fall from 59,150 to 6,078, and 5,746 of those are the 34 true triples, which must read all 169 rows.

How few rows are safe: accepting on the first k rows gives 14 false triples at k = 1, 2 at k = 2, and none from k = 3.

So the answer to "what cheap pre-filter": **none is worth having at this scale.** The flag comparison removes a third of the failures and the test it saves is one row. Its real use would be to discard whole operator *pairs* (8 of 25 here) before any map is enumerated, and for that it is not sound in general, as the next run shows. F2 and F3 are sound (they are consequences of the homomorphism equation) and remove 70%, but they need as many column tests as there are (f, operator) pairs, which only pays when there are many operators per map.

**Added: a richer bank** (`{neg + * max min}`, size ≤ 5: 625 candidates, 98 non-constant maps, 2,450 triples, 9.4 ms). 180 non-trivial triples hold; none is false on the fresh rows. F1 skips 783 of 2,265 failures and **one true triple**: `(max 0 (min x 1))` is a homomorphism from `min` to `*` (a 0/1-valued step turns minimum into product), although `min` is idempotent and `*` is not. A map whose image is small can land where the target operator satisfies laws it lacks in general. F2 or F3 skip 1,534 (68%) and no true one. Early exit: mean 1.26 rows, maximum 16; and here 16 rows are needed before no false triple is accepted (3 false at 12 rows). The same grammar as the spec at size ≤ 6 (58 maps, 1,450 triples, 5.3 ms) gives 90 triples, 0 false.

### 3.2 Sequence-to-integer maps against append

f in {len, sum, max, min, first, last}; `f(append(xs, ys)) = op2(f(xs), f(ys))` for op2 in {+, max, min}; 64 rows of random non-empty sequences (lengths 1 to 6, values −5..9).

| | |
|:--|--:|
| triples tested | 18 |
| found | 4: len → +, sum → +, max → max, min → min |
| false on 1,000 fresh rows (values to ±1000, lengths 1 to 12) | 0 |
| time, including the fresh-row check | 1.09 ms |

Flags: `append` is associative only, and `+`, `max`, `min` are all associative, so F1 skips nothing. F2 (12 tests: is `f(xs++ys) = f(ys++xs)`, is `f(xs++xs) = f(xs)`) skips 10 of the 14 failures and no true triple: `first` and `last` are not symmetric, `len` and `sum` are not idempotent. The four it cannot skip are max/+, max/min, min/+, min/max. Early exit: 2.14 rows on average, at most 11.

## 4. M3 — a row correspondence when no key identifies rows

A graph is a node space and an edge space with two map columns. H is G with the rows of both spaces permuted by seeded random permutations. One refinement round is two `pull`s (each edge row reads the colour of its source, and of its target), two `collect`s (each node gathers the colours along its out-edges, and its in-edges), a sort of each gathered list, and one group-by that maps (own colour, out-colours, in-colours) to a dense id. G and H are refined in the same round with one shared group-by table, so equal keys get equal colours in both. Refinement stops when no class splits, and fails as soon as the two colour histograms differ. Then: take the smallest class with at least two nodes, pair its first G node with each H node of that colour in turn, refine, backtrack on failure. When all colours are unique the bijection is read off the colours and verified by re-indexing G's two edge columns through it and comparing the edge rows with H's as multisets. Every "isomorphic" below passed that verification.

| case | n | m | result | colour classes after 1st refinement | nodes with a unique colour | rounds, 1st refinement | individualizations | backtracks | rounds, total | ms |
|:--|--:|--:|:--|--:|--:|--:|--:|--:|--:|--:|
| sparse random, m=3n (out-deg 3) | 100 | 300 | isomorphic | 100 | 100 | 3 | 0 | 0 | 3 | 0.2 |
| sparse random, m=3n (out-deg 3) | 1,000 | 3,000 | isomorphic | 999 | 998 | 4 | 1 | 0 | 5 | 3.1 |
| sparse random, m=3n (out-deg 3) | 10,000 | 30,000 | isomorphic | 9,978 | 9,977 | 4 | 22 | 0 | 26 | 158.7 |
| sparse random, m=1.5n (deg in+out 3) | 100 | 150 | isomorphic | 96 | 95 | 4 | 4 | 0 | 8 | 0.4 |
| sparse random, m=1.5n (deg in+out 3) | 1,000 | 1,500 | isomorphic | 941 | 934 | 5 | 59 | 0 | 64 | 21.3 |
| sparse random, m=1.5n (deg in+out 3) | 10,000 | 15,000 | isomorphic | 9,372 | 9,300 | 6 | 593 | 0 | 633 | 2,381.9 |
| random recursive tree | 100 | 99 | isomorphic | 84 | 73 | 7 | 14 | 0 | 23 | 0.8 |
| random recursive tree | 1,000 | 999 | isomorphic | 801 | 638 | 8 | 171 | 0 | 207 | 48.1 |
| random recursive tree | 10,000 | 9,999 | isomorphic | 8,085 | 6,547 | 9 | 1,586 | 0 | 1,914 | 5,413.5 |
| grid 30x30, arcs both ways | 900 | 3,480 | isomorphic | 120 | 0 | 15 | 2 | 0 | 116 | 56.5 |
| grid 30x30, arcs right/down only | 900 | 1,740 | isomorphic | 465 | 30 | 16 | 1 | 0 | 73 | 18.9 |
| one directed cycle | 200 | 200 | isomorphic | 1 | 0 | 1 | 1 | 0 | 101 | 4.6 |
| one cycle, arcs both ways | 200 | 400 | isomorphic | 1 | 0 | 1 | 2 | 0 | 200 | 11.6 |
| 2 cycles of 25 vs 1 cycle of 50 | 50 | 50 | not-isomorphic | 1 | 0 | 1 | 50 | 50 | 651 | 7.0 |
| 2 cycles of 50 vs 1 cycle of 100 | 100 | 100 | not-isomorphic | 1 | 0 | 1 | 100 | 100 | 2,501 | 45.7 |
| 2 cycles of 100 vs 1 cycle of 200 | 200 | 200 | not-isomorphic | 1 | 0 | 1 | 200 | 200 | 10,001 | 345.6 |
| 2 cycles of 200 vs 1 cycle of 400 | 400 | 400 | not-isomorphic | 1 | 0 | 1 | 400 | 400 | 40,001 | 2,661.4 |
| same, arcs both ways (n=200) | 200 | 400 | not-isomorphic | 1 | 0 | 1 | 200 | 200 | 10,001 | 519.2 |
| 3-regular random (3 permutations) | 100 | 300 | 5/5 isomorphic | 1 | 0 | 1 | 54.6 | 53.6 | 102.8 | 4.6 |
| 3-regular random (3 permutations) | 300 | 900 | 5/5 isomorphic | 1 | 0 | 1 | 111.4 | 110.4 | 221.0 | 25.1 |
| 3-regular random (3 permutations) | 1,000 | 3,000 | 5/5 isomorphic | 1 | 0 | 1 | 606.2 | 605.2 | 1,509.6 | 526.0 |
| 3-regular random (3 permutations) | 3,000 | 9,000 | 5/5 isomorphic | 1 | 0 | 1 | 1,835.8 | 1,834.8 | 4,481.2 | 4,550.1 |
| isomorphic: C3+C3+C6 (regular, mixed) | 12 | 12 | isomorphic | 1 | 0 | 1 | 7 | 4 | 16 | 0.1 |
| isomorphic: 2 x C6 | 12 | 12 | isomorphic | 1 | 0 | 1 | 2 | 0 | 8 | 0.0 |
| isomorphic: 3 x C6 | 18 | 18 | isomorphic | 1 | 0 | 1 | 3 | 0 | 12 | 0.1 |
| isomorphic: 4 x C6 | 24 | 24 | isomorphic | 1 | 0 | 1 | 4 | 0 | 16 | 0.1 |
| isomorphic: 5 x C6 | 30 | 30 | isomorphic | 1 | 0 | 1 | 5 | 0 | 20 | 0.2 |
| NON-iso: 2 x C6 vs 1 x C6 + 2 x C3 | 12 | 12 | not-isomorphic | 1 | 0 | 1 | 48 | 48 | 109 | 0.4 |
| NON-iso: 3 x C6 vs 2 x C6 + 2 x C3 | 18 | 18 | not-isomorphic | 1 | 0 | 1 | 594 | 594 | 1,357 | 5.3 |
| NON-iso: 4 x C6 vs 3 x C6 + 2 x C3 | 24 | 24 | not-isomorphic | 1 | 0 | 1 | 10,716 | 10,716 | 24,493 | 127.6 |
| NON-iso: 5 x C6 vs 4 x C6 + 2 x C3 | 30 | 30 | not-isomorphic | 1 | 0 | 1 | 257,214 | 257,214 | 587,917 | 3,591.9 |

The 3-regular rows are means over 5 graphs each; backtracks per graph were (16, 98, 79, 23, 52), (176, 19, 3, 290, 64), (545, 492, 385, 808, 796), (45, 2202, 2481, 2426, 2020).

**Solved by refinement alone.** Sparse random graphs with 3 out-edges per node: every node unique after 3 rounds at n = 100, and 998 of 1,000 and 9,977 of 10,000 after 4. The 2 and 23 remaining nodes are interchangeable twins (the map found differs from the hidden one on 2 and on 22 nodes, and still verifies), so the 1 and 22 choices are never wrong.

**Choices but no backtracking.** With half as many edges, 5% to 7% of nodes stay non-unique; in random trees, 27% to 36%; the grid needs 1 or 2 choices; a cycle needs 1 (directed) or 2. In all of these every choice was right, 0 backtracks: what refinement leaves undecided is symmetry. A cycle needs n/2 rounds for one choice, because a colour spreads one edge per round.

**The cost there is passes, not search.** Each choice triggers at least one refinement round, and a round built from whole-column operations touches every row whatever changed. Trees: 0.8 ms, 48 ms, 5.4 s for n = 100, 1,000, 10,000, a factor of 100 per factor of 10. A worklist refinement would avoid this, but it is not a group-by over a column.

**Where backtracking grows.**

- *Regular graphs with no symmetry* (random 3-regular): one colour, and the right partner of the first node is one among n. About n/2 wrong pairings are tried (53.6, 110.4, 605.2, 1,834.8); each is rejected in two to two and a half rounds. Time grows with n²: 4.6 ms at n = 100 to 4.6 s at n = 3,000.
- *Non-isomorphic regular pairs*: two cycles against one. All n pairings fail, each after about n/4 rounds: 50, 100, 200, 400 backtracks, 651 to 40,001 rounds, 7 ms to 2.7 s, a factor of 6.5 to 7.7 per doubling of n.
- *Non-isomorphic pairs made of interchangeable parts*: k hexagons against k−1 hexagons and two triangles. 48, 594, 10,716, 257,214 backtracks at 12, 18, 24, 30 nodes, 3.6 s for the last. The counts follow B(k) = 6(k−1)(B(k−1)+1) + 6 exactly: every way of matching hexagons is tried before the mismatch is reached, because nothing records that the hexagons are interchangeable. The isomorphic counterpart (k hexagons against a copy) takes k choices and no backtrack.
- A small isomorphic pair where a choice can be wrong (two triangles and a hexagon, all nodes one colour): 7 choices, 4 backtracks.

So this engine is cheap on "find the correspondence when there is one and the rows are distinguishable", and expensive on "show there is none" and on regular structure. Pruning by discovered automorphisms, which is what makes practical tools fast on the hexagon case, is not expressible as group-by and re-index; I did not build it.

## 5. Choices the spec did not fix

**M1**

1. Pool: 30 tasks; which 12 to add and which 4 to drop (2.1).
2. Each task gets its own example seed, and there are five replicates. With the prototype's single seed, tasks with the same input spec receive *the same inputs* (section 6).
3. "Program form" is read from the emitted program, not from my intent. They agree for all 30.
4. Leaf set: exactly the spec's list; an integer output becomes the leaf `outv`; an `:elt` input counts as an integer; a function-valued input has no leaf. First/last of the inputs are a variant only.
5. One shared space with 64 probe rows (seed 77); properties are classes on it; tautologies on the probe rows are dropped.
6. "Holds" = no false cell on the task's rows and true on at least half. The half is needed because `:err` cells exist (empty outputs).
7. P3 is the literal spec; P5 is my reading of "up to a small size". Both are reported everywhere.
8. Jaccard of two empty signatures is 0. Ties: expected value in (b); in (c), a fixed seeded priority (seed 4242).
9. A solution's operators are those of the lambda body (not of the shape term), restricted to the 12-operator grammar; `if` is not one of them. For "shares at least half", `at` is left out, and a task whose solution has no other operator counts every task as sharing.
10. Budget 12 M candidates instead of the prototype's 30 M, to stay inside an 8 GB heap. No pool task needs more than 8.5 M.
11. Integer-output tasks: the prototype's scalar search (size ≤ 9, 3 M), then its fold search, as in its experiment D.
12. "Correct" = 200/200 on the prototype's held-out generator. Impostors are counted separately and charged the fallback.
13. Random baseline: seeds `9000 + 10·i + d`, the same draws for every signature variant.
14. Caps are evaluated after the fact (2.4).
15. Added and not asked for: the types-only baseline, the pool-frequency control, the oracle, the coverage-by-k table, the 48-row variant, the route-order experiment.

**M2**

16. Grid −6..6; the map space is −36..36 so that every `op1(a,b)` has a row. Fresh rows: seed 4242.
17. "Trivial" = the identity map with op1 = op2; those 5 are counted but not listed.
18. Law flags are computed on the same grid values (associativity on all 13³ triples).
19. Sequence rows: 64, lengths 1 to 6, seed 11; fresh lengths 1 to 12.
20. The two extra banks, and filters F2 and F3, are additions.

**M3**

21. Directed simple graphs. "Average degree 3" is ambiguous for a directed graph, so both m = 3n and m = 1.5n were run.
22. Trees are random recursive trees with edges child → parent. The grid and the cycle were run with arcs both ways and one way.
23. Class to split: the smallest with at least two nodes, lowest colour on ties; its first G node against the H nodes in row order.
24. A backtrack = one individualization undone. "Rounds" counts every refinement round, including the one that confirms stability.
25. Both graphs are refined together; stability is "the number of classes did not change".
26. The 3-regular graphs, the mixed-cycle pair and the hexagon series are additions.

## 6. What surprised me

1. **The prototype's example generator correlates tasks.** With one seed for all tasks, every task with input spec `((xs :seq))` gets the same 12 lists. Accidental properties of that one sample then act as a hidden "same input spec" label: P5 nearest-neighbour same-form is 0.83 on the prototype's own example sets and 0.54 with independent seeds (`logs/m1.log`, "replicate 0"). The first number would have been the headline had I not looked at which properties were doing the work.
2. **A control with no signature matches the signature on operators.** I expected nearest neighbours to beat "the four commonest operators" clearly. They do not (67% against 69% correct).
3. **A restricted grammar that still succeeds can cost 50 to 100 times the full grammar**, by finding a longer program around the missing operator.
4. **Route choice needs no prediction**: the second route is free to try first.
5. **Types retrieve folds better than the signature does**, because accidental input-only properties drown the one informative bit.
6. **The flag pre-filter is unsound, and the store found the counterexample itself** (`min → *` through a 0/1 step).
7. **The hexagon series matched a hand recurrence to the last digit** (257,214), which is a useful check on the backtracking code and a clear picture of what missing automorphism pruning costs.
8. **Individualization without any backtracking is already quadratic** when every refinement is a whole-column pass.

## 7. Limits of these measurements

- 30 tasks in 6 forms, 12 of them mine, with deliberate same-predicate pairs across forms. Retrieval rates depend on that composition; the comparison with chance, with types and with the control is the part that should transfer.
- One signature design. A signature that looked at position-level structure (the lifted spaces the prototype already builds) was not tried; section 2.6 says why that is where the missing information is.
- (c) restricts operators only. It does not reuse neighbours' sub-terms, sizes or shapes.
- The interleaved policy (run restricted and full grammars size by size) was not built; the cap column is a stand-in.
- M2 covers 5 integer operators and 6 sequence functions. M3 has no automorphism pruning and no incremental refinement.
- Nothing was skipped from the three specifications. The per-task tables of (c) for P5, the two baselines and replicates 2 to 5 are in the log, not in this report.
