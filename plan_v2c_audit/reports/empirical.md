# `empirical` — measured numbers on whether larger budgets rescue the existing engine

Auditor: `empirical`. Tree audited: `/home/tlh24/lisploop` at `15e64c6` (branch `reflective`), copied with
`rsync -a --exclude .git --exclude '*.pdf'` to
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/repo/`.
Nothing was written into `/home/tlh24/lisploop`. SBCL 2.6.4.debian, single-threaded kernel.

All paths below are relative to
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/`
(`scripts/` = what was run, `logs/` = raw output). Times are CPU seconds of the SBCL process unless
"wall" is stated. The machine was shared with other auditors (load average 8–13 during the first
20 minutes, about 1.5 afterwards), so rates measured early are 30–45 % lower than rates measured late;
both are given where they differ. Work counts, tree counts and behaviour counts are deterministic.

---

## 0. Answer

**Claim tested:** "the budget for search was very limited … we should tolerate hours of search … provided
the search algorithm is not fundamentally big-O too expensive."

1. **The budgets were tiny in wall-clock terms — true, and by more than the documents suggest.**
   The 350,000-work cap of `STAGE0_RESULTS.md` is **0.06–0.07 CPU seconds**. The whole E0b-2 audit
   (64 synthesis attempts) costs **1.5 CPU seconds**. The cold bootstrap of 8 batteries / 31 specs reports
   0.39–0.44 s. The repository's largest standard benchmark (`quartic 77`) is 0.43 s. One algebra-solver
   discovery is 0.05–0.14 s.
2. **Raising the budget does not rescue the existing engine.** For the seven specs that time out at 350k
   under "active grammar, no schemas":

   | budget | sound solutions gained | what happened |
   |---|---|---|
   | ×10 (3.5M work, 0.7 s) | 2 of 7: `positions` at 1,250,219 work, `seq-corr` at 663,714 work | budget-limited, by factors 3.6 and 1.9 |
   | ×100 (35M, 6–8 s) | 0 more | — |
   | ×102 | `argmax-corr` returns a 279-bit program that passes its 3 spec rows and **fails held-out** | impostor |
   | ×1000 (350M, 57–71 s, 2.6–3.5 GB live) | 0 more; `map-adjacent`, `scan`, `shift-seq`, `best-shift` still `:cutoff` | — |
   | ×1430 (500M, `shift-seq` only, 73 s, 4.75 GB live) | 0 more | still `:cutoff`; the run to ×2000 (700M) **exhausted an 11 GB heap** before reaching it |

   `foldl` returns the same impostor at every budget (the search stops at the first spec-consistent program).
3. **Why, in order of what binds first:**
   - **Structure (not a numeric cap).** After the first ~350k work the job is 2–3 flat bottom-up
     enumerations and stays that way: node count 2–3, `expandable 0`, `deferred 0` at every rung from 350k to
     500M. None of those lanes has a grammar that contains the known solution: the root lane has no self-call
     operator; the one child lane that is given recursion receives it as a fixed input,
     `(SELF (tail X0) <other args unchanged>)`, and loses `:tail :at :if :=`; a conditional child without
     that lift keeps the full language but has no recursion at all. `scan`, `shift-seq`, `best-shift` need a self-call with a changed argument;
     `map-adjacent` needs `(at (tail X0) 0)` next to the recursive result. Raising `:max-depth` 2→4,
     `:heuristic-budget` ×10 and the bit bound +100 changed nothing (§4.4).
   - **Exponent.** In those lanes work grows **×1.38–1.50 per body bit** (×25–57 per 10 bits). A 1000×
     budget moved each lane's completed horizon by 18–23 bits. Extrapolated, 1 hour reaches 53–63 body bits and
     10 hours 59–70; the reference solutions are 132–259 body bits.
   - **Memory.** The enumerator keeps every tree: 7.8–10.4 live bytes per work unit (≈430 bytes per tree) in
     a synthesis job, and SBCL's copying collector needs about twice the live size. A 5 GB heap died between
     200M and 350M work (≈40–65 s of search); an 11 GB heap died between 500M and 700M (≈75–100 s). One hour
     at the measured rate is ≈1.9–2.5 × 10^10 work ≈ 180–240 GB live. On this 31 GB machine the engine
     cannot run for more than a few minutes, whatever the exponent.
   - **Internal numeric caps** exist and were found (§4.5, §5) but none of them is what stops these specs.
4. **Behaviour dedupe changes the exponent, not the verdict.** On the real 26–30-operator grammars,
   99.0–99.8 % of enumerated trees duplicate an earlier behaviour on the spec rows (e.g. `map-adjacent`:
   315,388 trees, 767 behaviours). v2's unused `:prune-behaviors-p` flag lowers growth from ×1.36–1.43 to
   ×1.18–1.27 per bit: the same ~13M work reaches 56 bits instead of 40 (`shift-seq`), 70 instead of 47
   (`map-adjacent`). Extrapolated to one hour that is 86–112 bits instead of 65–75 — still short of
   132–259. As implemented it also keeps ~1 KB per *tried* candidate, so it hits the same memory wall.
5. **Two of the seven "TIMEOUT" cells in the STAGE0 table are harness artifacts** (§4.7): after `seq-corr`
   fails, `best-shift`'s grammar silently lacks `:seq-corr`; after `best-shift` fails, `argmax-corr`'s
   grammar lacks both.

Not verified here: that no *other* program for the four unsolved specs exists inside the lanes' grammars.
The inexpressibility statement is about the known (battery) solutions and rests on the printed node languages
and bindings (`logs/e4_nodes_*.log`) and on the header of `bootstrap/recursion-schemas.lisp`, which says the
same thing.

---

## 1. E1 — Baseline

Scripts: `scripts/e1_baseline.sh`, `scripts/e1b_root_kernel_after_bootstrap.sh`, `scripts/e1c_retime.sh`,
`scripts/e4_0_stage0_reproduce.sh`. Logs: `logs/e1_*.log`, `logs/e1b_*.log`, `logs/e1c_*.log`,
`logs/e4_0_stage0_reproduce.log`.

| run | command (in the copy) | result | suite's own time | process wall |
|---|---|---|---|---|
| root kernel, fresh copy | `sbcl --script tests/run.lisp kernel` | **FAILED, rc=1**, at test 71 `M5-FINITE-FIELD-LIFTING-AND-CERTIFIED-PROPAGATION`: `No battery packet :ARITHMETIC at …/library/arithmetic.sexp` | — | 10.1 s |
| root kernel, after root bootstrap | same | 222 tests, 938,737 checks passed | 5.52 s (6.20 s under load) | 7.84 s |
| root milestones | `sbcl --script tests/run.lisp milestones` | 40 tests, 186,771 checks passed | 13.05 s (22.37 s under load) | 15.26 s |
| v2 kernel | `cd v2; sbcl --script tests/run.lisp kernel` | 228 tests, 938,281 checks passed | 5.67 s (15.78 s under load) | 8.25 s |
| v2 milestones | `cd v2; sbcl --script tests/run.lisp milestones` | 40 tests, 186,771 checks passed | 12.73 s (21.36 s under load) | 15.10 s |
| root cold bootstrap | `sbcl --script bootstrap/build-batteries.lisp` | 8 batteries, 61 entries, 31 specs | "Bootstrap complete in 0.44 s" | 2.99 s |
| v2 cold bootstrap | `cd v2; sbcl --script bootstrap/build-batteries.lisp` | 8 batteries, 61 entries, 31 specs | "Bootstrap complete in 0.39 s" | 3.13 s |
| v2 `stage0-audit.lisp`, unmodified | `cd v2; sbcl --dynamic-space-size 4096 --script experiments/stage0-audit.lisp` | E0b-2 table reproduced: 16/16, 10/16 (9 sound), 10/16 (9), 9/16 (8) | — | 5.34 s |

Findings.
- **The root tree has no `library/` directory** (`ls /home/tlh24/lisploop/library` fails; `git ls-files library`
  is empty; only `v2/library/*.sexp` is tracked). The root kernel suite therefore fails on a fresh checkout
  until `make bootstrap` is run; the root `Makefile`'s `test` target does not depend on `bootstrap`.
- **The live tree changed while I was working, and not through my scripts.** When I copied it (20:08) the
  root had no `library/`. At the end of my run `git status` in `/home/tlh24/lisploop` shows `?? library/`:
  eight `.sexp` files timestamped 20:10:50–20:10:51. My root bootstrap ran at 20:09:34 and its log
  (`logs/e1_root_bootstrap.log`) shows every save path inside the scratch copy; no script or log of mine
  references the real tree. Some other process ran a root bootstrap there (I saw a foreign
  `sbcl --script bootstrap/build-batteries.lisp` in the process list at 20:10). The files are identical in
  content to what the bootstrap generates. The "fails on a fresh checkout" finding describes the tree as
  committed at `15e64c6`.
- Both bootstraps regenerate all 8 `.sexp` files **byte-identical** to the committed `v2/library/*.sexp`.
- About 2.5 s of every process is loading and compiling the kernel sources; the synthesis itself is the
  0.39–0.44 s figure.
- Six work figures in my reproduction differ slightly from `STAGE0_RESULTS.md` §E0b-2 (pass/fail identical):
  `best-shift` W+S 199,199 (doc 199,252); `argmax-corr` W+S 99,180 (98,921); `argmax-corr` W-noS 51,952
  (51,825); `positions` AG+S 92,569 (92,605); `last-or` AG+S 152,465 (152,471); `last-or` AG-noS 162,170
  (162,173).
- In the same log, the recursive `inc-all` probe inside `measure-cons-fold-gate` is unsolved at its 80,000
  cap in all three regimes (`:REC-SOLVED NIL :REC-WORK 80000`); the document's E0b-1a table has no column for it.

---

## 2. E2 — Throughput: work units, candidates, seconds

Scripts: `scripts/e2_e6_run.sh`, `scripts/e2_e6_large.sh` (the repository's own `benchmark.lisp`, run alone),
plus the rates printed by `scripts/e3_growth.lisp`, `scripts/e4_rescue.lisp`, `scripts/e5b_algebra_raised_cap.lisp`.
Logs: `logs/e2_*.log`.

| regime | workload | work | CPU s | work/s | candidates | cand./s | work per cand. |
|---|---|---|---|---|---|---|---|
| flat exact search (`benchmark.lisp`, GF(5) {+,*}, 2 inputs, 25 rows) | `linear 61` | 182,181 | 0.0035 | 52M | 649 | 186k | 281 |
| | `quadratic 70` | 2,687,984 | 0.041 | 65M | 9,889 | 240k | 272 |
| | `quartic 77` (Makefile's "large run") | 29,382,492 | 0.428 | 68.6M | 106,057 | 248k | 277 |
| | `quartic 82` | 210,375,007 | 3.516 (GC 19 %) | 59.8M | 643,657 | 183k | 327 |
| | `quartic 86` | 1,048,334,639 | 20.62 (GC 31 %) | 50.9M | 3,249,673 | 158k | 323 |
| | `quartic 90` | 1,136,000,000 | 22.82 | — | 3,566,145 | — | **`:HEAP-CUTOFF`** (benchmark's own 768 MiB cap), bound 90 not completed |
| flat exact search, `:int` {+,−,*}, 2 inputs, 10 rows (E3 g2) | to 48 body bits | 1,427,679,951 | 42.96 | 33.2M | 8,619,010 | 201k | 166 |
| Stage-A-style observation search (every candidate on every row), same grammar | to 45 body bits | 916,342,146 | 24.62 (loaded) | 37.2M | 1,076,776 | 43.7k | 851 |
| v2 pruned search (`:prune-behaviors-p t :columnar-p t`), same grammar | to 66 body bits | 143,350,129 | 12.31 | 11.6M | 2,188,372 tried, 269,682 kept | 178k tried | 66 per tried |
| recursion synthesis job (`resume-synthesis`), `map-adjacent`, active grammar | to 350M work | 350,000,000 | 66.79 (loaded; GC 16 %) | 5.24M | 7,911,026 trees | 118k | 44 |
| same, `shift-seq`, quiet machine | to 500M work | 500,000,000 | 72.64 (GC 16 %) | 6.88M | 12,290,484 trees | 169k | 41 |
| algebra vocabulary observation, GF(7), 98 rows (E5) | body-bound 32 | 922,544,511 | 33.66 | 27.4M | 100,461 | 3.0k | 9,183 |

The synthesis job does 5–10× fewer work units per second than flat search. Its loop advances a search one
work unit per iteration (`(search-step search 1)`), and the profile in §6 puts 3 % of its time in candidate
evaluation. Per candidate the two regimes are similar (120–250k candidates/s).

**Exchange rates** (single thread, this machine):

| | work units | candidates |
|---|---|---|
| the 350k cap | 350,000 = 0.06–0.07 s | ≈ 8,000 |
| 1 hour, synthesis job (5.2–6.9M work/s) | 1.9–2.5 × 10^10 | 4.2–6.1 × 10^8 |
| 10 hours, synthesis job | 1.9–2.5 × 10^11 | 4.2–6.1 × 10^9 |
| 1 hour, flat exact search (33–60M work/s) | 1.2–2.2 × 10^11 | 5.7–7.2 × 10^8 |
| 10 hours, flat exact search | 1.2–2.2 × 10^12 | 5.7–7.2 × 10^9 |

These assume the rate holds. It does not hold for long, because of memory:

| regime | live heap measured | per unit | one hour would need |
|---|---|---|---|
| synthesis job, `map-adjacent`, 350M work | 3,219 MiB | 9.6 bytes/work, 427 bytes/tree | ≈ 170–240 GB |
| synthesis job, `scan` / `shift-seq` / `best-shift`, 350M | 3,460 / 3,366 / 2,597 MiB | 10.4 / 10.1 / 7.8 bytes/work | same order |
| flat search, `quartic 86` | +588 MiB | 190 bytes/tree | ≈ 110–140 GB |
| flat search, g2 to 48 bits | 1,651 MiB | 201 bytes/tree | same order |
| v2 pruned search, g2 to 66 bits | 2,129 MiB | 973 bytes per *tried* candidate (column cache holds every tried expression: 2,188,372 entries for 269,682 kept) | ≈ 600 GB |

Observed failures: `map-adjacent` with a 5,000 MB heap: `Heap exhausted, game over` between the 200M and
350M rungs (`logs/e4_x3000_map-adjacent.log`); with 7,000 MB it completes 350M. `shift-seq` with an
11,000 MB heap: heap exhausted between the 500M and 700M rungs (`logs/e4_x2000_shift-seq.log`).

---

## 3. E3 — Growth of the enumerator, with and without behaviour dedupe

Scripts: `scripts/e3_growth.lisp` (+ `e3_run.sh`, `e3_big.sh`) for plain integer grammars;
`scripts/e3b_real_grammar.lisp` (+ `e3b_run.sh`) for the real active-library grammars of three E4 specs.
Logs: `logs/e3_*.log`, `logs/e3b_*.log`.

Method. One flat `start-search` over a frame whose target no candidate satisfies, advanced one body-size at
a time. "Trees" = expressions the enumerator built and kept (all types). "Behaviours" = distinct output
vectors over all rows. The kernel does not expose a behaviour count for an exact search, so in `exact` mode
the script hashes the output vector of every new tree itself (plain `evaluate`, off the ledger, not timed).
Cross-checks: the count equals the kernel's own `observation-job-buckets` count in `observe` mode (1,578 /
2,311 / 2,619 at 39 / 42 / 45 bits) and equals the retained set of v2's `prune` mode at every size compared.
Root (v1) and v2 give identical trees and work in `exact` mode (`logs/e3_v1_g2_exact.log`); v1 has no
pruning flag.

### 3.1 g2: {+, −, *}, 2 `:int` variables, literals (0 1), 10 rows

Bit costs: variable 3, literal 0 = 3, literal 1 = 6, operator overhead 6; one more binary operator with a
3-bit leaf is +9 bits.

| body bits (≈ binary ops) | trees, exact | behaviours | work, exact | kept / tried, pruned | work, pruned |
|---|---|---|---|---|---|
| 12 (1) | 31 | 14 | 2,875 | 14 / 31 | 1,202 |
| 21 (2) | 538 | 67 | 58,167 | 67 / 232 | 8,727 |
| 30 (3) | 12,139 | 316 | 1,539,347 | 316 / 1,594 | 62,707 |
| 39 (4) | 311,191 | 1,578 | 45,495,779 | 1,578 / 9,901 | 439,792 |
| 48 (5) | 8,619,010 | 8,414 | 1,427,679,951 (43 s) | 8,414 / 59,545 | 3,039,877 |
| 57 (6) | — | — | — | 46,810 / 359,353 | 20,868,469 |
| 66 (7) | — | — | — | 269,682 / 2,188,372 | 143,350,129 (12.3 s) |

| growth | per +9 bits (one operator) | per bit |
|---|---|---|
| trees, exact | ×17, ×23, ×26, ×28 | ×1.45 |
| work, exact | ×20, ×26, ×30, ×31 | ×1.47 |
| behaviours | ×4.8, ×4.7, ×5.0, ×5.3 | ×1.20 |
| work, pruned | ×7.0, ×6.9, ×6.9, ×6.9 | ×1.24 |

At 48 bits, 99.9 % of the 8.6M trees are behavioural duplicates; pruned search does the same horizon in
1/470 of the work.

### 3.2 g3: {+, −, *, /, mod, <, =, if}, 3 `:int` variables, literals (0 1 2), 10 rows

Bit costs: variable 4, literal 0 = 3, literals 1, 2 = 6; overheads + − * / if = 6, `=` 9, `mod` and `<` 14.

| body bits | trees, exact | behaviours | work, exact | kept / tried, pruned | work, pruned |
|---|---|---|---|---|---|
| 21 | 297 | 79 | 30,418 | 79 / 273 | 8,331 |
| 30 | 15,083 | 1,108 | 1,802,705 | 1,108 / 4,874 | 165,861 |
| 39 | 828,137 | 18,194 | 114,142,507 | 18,194 / 82,799 | 3,276,316 |
| 42 | 2,810,517 | 27,261 | 398,197,901 (13.8 s) | 27,261 / 130,619 | 5,182,627 |
| 44 | — | — | — | 98,144 / 374,602 | 17,674,262 |

Growth per bit: trees ×1.56, exact work ×1.58, behaviours ×1.36, pruned work ×1.37–1.39.

### 3.3 The real grammars (root lane of three E4 specs, library as the audit has it)

| spec grammar | mode | body bits reached | trees | behaviours on the spec rows | work | CPU s |
|---|---|---|---|---|---|---|
| `shift-seq`: 26 operators, 2 inputs, 13 rows | exact | 40 | 343,796 | 1,433 | 13,046,714 | 0.58 |
| | pruned | 56 | 294,840 tried | 30,043 | 13,456,777 | 2.34 |
| `map-adjacent`: 28 operators, 2 inputs, 8 rows | exact | 47 | 315,388 | 767 | 15,295,479 | 0.69 |
| | pruned | 70 | 209,737 tried | 30,413 | 13,144,238 | 3.52 |
| `best-shift`: 30 operators, 3 inputs, 9 rows | exact | 41 | 339,751 | 3,491 | 19,741,256 | 0.82 |
| | pruned | 52 | 154,005 tried | 30,852 | 6,552,699 | 1.22 |

| growth per bit | trees, exact | work, exact | behaviours | work, pruned |
|---|---|---|---|---|
| `shift-seq` (30→40; pruned 46→56) | ×1.42 | ×1.42 | ×1.19 | ×1.22 |
| `map-adjacent` (40→47; pruned 60→70) | ×1.37 | ×1.36 | ×1.17 | ×1.18 |
| `best-shift` (35→41; pruned 45→52) | ×1.42 | ×1.43 | ×1.25 | ×1.27 |

### 3.4 What one hour reaches (extrapolation)

Assumptions: the fitted per-bit factor stays constant, the measured work/s stays constant, memory is not a
limit. The third is false for the existing code (§2), so these are upper bounds.

| grammar | 1 h, exact | 10 h, exact | 1 h, deduped | 10 h, deduped | size of the known solution |
|---|---|---|---|---|---|
| g2 | 57–60 bits (6 binary ops; 7 ops needs ≈13 h) | 63 | ≈ 92 (≈10 ops) | ≈ 103 | — |
| g3 | ≈ 56 | ≈ 61 | ≈ 66 | ≈ 73 | — |
| `shift-seq` root grammar | ≈ 65 | ≈ 71 | ≈ 93 | ≈ 105 | 132 body bits |
| `map-adjacent` root grammar | ≈ 75 | ≈ 82 | ≈ 112 | ≈ 126 | 214 |
| `best-shift` root grammar | ≈ 65 | ≈ 71 | ≈ 86 | ≈ 95 | 259 |

Rule of thumb from these fits: **exact enumeration gains 5.7–7.5 bits per 10× of work; deduped enumeration
gains 9.7–14 bits per 10×.** A variable costs 3–5 bits and an application 6 bits or more plus its operands,
so each 10× buys roughly one more AST node without dedupe and roughly two with it.

Caveat on the dedupe figures: behaviours are distinguished only on the 8–13 spec rows, so observational
merging also merges programs that differ off those rows (the same mechanism that produces the impostors in §4).

---

## 4. E4 — Budget-rescue test

Harness: `scripts/e4_rescue.lisp` (driver `scripts/e4_run.sh`). For a target spec it replays every earlier
spec with the audit's own call (`synthesize-spec-entry`, 350k cap, `*use-active-library-grammar* t`, no
expanders), so the library is what the audit's regime had on reaching the target; then it builds the
target's job exactly as `synthesize-spec-entry` does (active-library grammar, bound 130+24 = 154 bits,
`:max-depth 2`, `:heuristic-budget 15000`), keeps the job, and resumes it through cumulative caps. Because
`resume-synthesis` is cumulative, one run to the largest cap answers every smaller cap. At each rung it logs
the claim of `resume-synthesis` (`:cutoff` / `:bounded-exhaustion` / `:candidate`), CPU, GC, live heap after
a forced full GC (excluded from the timings), and for every searching node its completed body bits, tree
count and work. Sanity: at 350k every target reproduces the audit (`:cutoff` at 350,000; `last-or` solved at
~162k; `foldl` impostor).

Whole-sequence variant: `scripts/e4_sequence.lisp` = the audit's own `measure-bootstrap-distractor-audit`
with the per-spec cap as a parameter (it reproduces the audit's four totals at 350k).

### 4.1 Per-spec result, "active grammar, no schemas" (`logs/e4_x100_*.log`, `logs/e4_x1000_*.log`)

| spec | 350k (×1) | ×10 | ×100 | ×1000 (350M) | program / held-out |
|---|---|---|---|---|---|
| `positions` | cutoff | **solved at 1,250,219 work, 0.42 s** | | | `(if (= X0 ()) X0 (cons X1 (inc-all (positions (tail X0) X1))))`, 120 bits; spec verified; held-out PASS |
| `seq-corr` | cutoff | **solved at 663,714 work, 0.14 s** | | | `(if (= X0 ()) 0 (if (= X1 ()) 0 (+ (seq-corr (tail X0) (tail X1)) (* (at X0 0) (at X1 0)))))`, 191 bits; held-out PASS |
| `map-adjacent` | cutoff | cutoff | cutoff | cutoff, 66.8 s, 3,219 MiB live | none |
| `scan` | cutoff | cutoff | cutoff | cutoff, 69.1 s, 3,460 MiB | none |
| `shift-seq` | cutoff | cutoff | cutoff | cutoff, 71.4 s (49.2 s quiet), 3,366 MiB | none |
| `best-shift` | cutoff | cutoff | cutoff (35.0M) | cutoff, 57.4 s, 2,597 MiB | none |
| `argmax-corr` | cutoff | cutoff | cutoff (35.0M) | **"solved" at 35,656,508 work, 7.65 s** | 279-bit `(foldr X0 2 (code-subst '(if (= 2 (- V0 1)) (/ (len-all V2) 2) 0) (tuple 'V0 'V1 X1)))`; passes its 3 spec rows; **held-out FAIL** |
| `foldl` | impostor at 208,573 | same | same | same | `(if (= () X0) X1 (- (foldl (tail X0) X1 X2) (at X0 0)))`; held-out FAIL |

Every unsolved rung reported `:cutoff`, never `:bounded-exhaustion`: the larger budget was consumed, not
refused.

### 4.2 Where the budget went

For the four unsolved recursive specs the node census is identical at every rung from 350k to 350M:
`:NODES 3 :PHASES (:SEARCH 3)` (`map-adjacent`, `shift-seq`) or `:NODES 2 :PHASES (:SEARCH 2)` (`scan`,
`best-shift`), `:DEFERRED 0 :EXPANDABLE 0`. The job is the root's exact search plus one or two
`:heuristic-conditional` children, each a flat enumeration, sharing the work in fixed proportions
(root 24 %, first child 64–73 %, second child 9 %).

Completed body bits per lane at 350k / 3.5M / 35M / 350M total work, and the fitted growth
(`scripts/e4_fit.py`, `logs/e4_fit.txt`):

| spec, lane | operators / inputs | body-bit cap (bound − header) | completed body bits | trees at 350M | work growth per bit |
|---|---|---|---|---|---|
| `map-adjacent` root | 28 / 2 | 106 | 28 / 38 / 44 / 51 | 1,613,528 | ×1.384 |
| `map-adjacent` child 1 | 20 / 4 | 87 | 31 / 38 / 44 / 50 | 5,449,265 | ×1.453 |
| `map-adjacent` child 2 | 20 / 4 | 87 | 24 / 33 / 39 / 45 | 848,233 | ×1.441 |
| `scan` root | 29 / 3 | 98 | 27 / 34 / 40 / 46 | 2,183,894 | ×1.465 |
| `scan` child 1 | 20 / 5 | 79 | 31 / 37 / 44 / 49 | 6,943,338 | ×1.464 |
| `shift-seq` root | 26 / 2 | 125 | 26 / 32 / 38 / 44 | 2,206,873 | ×1.495 |
| `shift-seq` child 1 | 26 / 2 | 125 | 26 / 35 / 41 / 47 | 5,501,071 | ×1.492 |
| `shift-seq` child 2 | 19 / 4 | 106 | 21 / 31 / 36 / 42 | 883,264 | ×1.443 |
| `best-shift` root | 30 / 3 | 107 | 25 / 32 / 38 / 44 | 1,498,204 | ×1.469 |
| `best-shift` child 1 | 20 / 5 | 81 | 25 / 34 / 40 / 46 | 2,865,959 | ×1.479 |

- A 1000× budget advanced each lane by 18–23 bits.
- Extrapolated at the fitted factors and each lane's share: 1 hour → 53–63 completed body bits; 10 hours →
  59–70. Exhausting a lane's own bound would take 2 × 10^13 to 1 × 10^22 work per lane.
- Sizes of the known solutions (the programs the whitelist+schemas regime finds, measured with
  `description-size`): `map-adjacent` 262 bits (214 body), `scan` 269 (213), `shift-seq` 161 (132),
  `best-shift` 306 (259). All exceed the 154-bit node bound, so no single lane could return them even after
  exhausting its bound.

### 4.3 Why no lane can contain the known solutions

`scripts/e4_nodes.lisp` prints each node's proposal, bindings, inputs and language
(`logs/e4_nodes_{map-adjacent,scan,shift-seq,best-shift}.log`). For `map-adjacent`:

```
NODE 0  language ops=(+ - * / MOD < = IF IF = CONS TAIL LENGTH CONCAT AT = IF CODE-EVAL COPY INC-ALL DBL-ALL
                      SUM-ALL LEN-ALL PRD-ALL MAP FOLDR FOLDL FILTER)          ; no MAP-ADJACENT
NODE 1  decoder=(IF (= X0 ()) () X2)
        bindings=((0 . X0) (1 . X1) (2 AT X0 0) (3 MAP-ADJACENT (TAIL X0) X1))
        language ops=(+ - * / MOD < CONS LENGTH CONCAT CODE-EVAL COPY INC-ALL … FILTER)   ; no TAIL, AT, IF, =
NODE 2  decoder=(IF (= X0 (CONS X2 X3)) X3 X4)   same inputs, same language
```

- The root lane never has the function being defined among its operators (`start-recursive-synthesis`
  removes it; `active-library-spec-operators` excludes it), so it cannot emit any recursive program.
- A child lane's only access to recursion is the bound input `(SELF (tail X0) X1 …)`, every other argument
  passed unchanged; the lane that receives it has lost `:tail :at :if :=`. A conditional child that does not
  receive it (`shift-seq` node 1, decoder `(if (= X1 0) X0 X2)`) keeps the root's full language and, like the
  root, has no self-call.
- `scan` needs `(scan (tail X0) (code-eval X2 X1 (at X0 0)) X2)`; `shift-seq` needs
  `(shift-seq (tail X0) (- X1 1))`; `best-shift` needs `(best-shift (tail X0) X1 (+ X2 1))`: a changed
  argument in the self-call. `map-adjacent` needs `(at (tail X0) 0)` together with the recursive result.
- `bootstrap/recursion-schemas.lisp` states this itself: the schemas are "the shape of one battery function
  (`:map-adjacent` and `:last-or`, `:foldl`, `:scan`, `:shift-seq`, `:best-shift`), written by hand …
  Retiring one means giving the kernel a general way to propose its recursion (a self call whose arguments
  are synthesized)".

The two specs that *are* rescued by ×2–×4 are exactly those whose solution fits the built-in template
(`positions` via the library's `inc-all`, `seq-corr` via the lockstep form).

### 4.4 Raising the internal constants (35M work each; `scripts/e4_caps.sh`, `logs/e4_cap*_*.log`)

| change | `map-adjacent` | `scan` | `shift-seq` | `best-shift` | `argmax-corr` |
|---|---|---|---|---|---|
| `:max-depth` 2 → 3 | cutoff, 3 nodes | cutoff, 2 | cutoff, 3 | cutoff, 2 | impostor at 34,811,421; 49 nodes |
| `:max-depth` 2 → 4 | cutoff, 3 | cutoff, 2 | cutoff, 3 | cutoff, 2 | impostor at 33,614,182; 64 nodes |
| `:heuristic-budget` 15,000 → 150,000 | cutoff, 3 | cutoff, 2 | cutoff, 3 | cutoff, 2 | cutoff, 34 nodes |
| bit bound 154 → 254 | cutoff, 3 | cutoff, 2 | cutoff, 3 | cutoff, 2 | cutoff, 34 nodes |
| all three together | cutoff, 4 | cutoff, 2 | cutoff, 3 | cutoff, 2 | impostor at 33,614,182; 64 nodes |

The tree does not grow when it is allowed to be deeper: no further proposals are generated.

### 4.5 The other three regimes and the whole sequence (`scripts/e4_regimes.sh`, `scripts/e4_sequence_run.sh`)

Whole 16-spec sequence, per-spec cap raised (solved / held-out sound of 16):

| regime | ×1 (350k) | ×10 | ×100 | total CPU, all four regimes |
|---|---|---|---|---|
| whitelist + schemas | 16 / 16 | 16 / 16 | 16 / 16 | ×1: 1.5 s; ×10: 10.5 s; ×100: 77.6 s |
| whitelist, no schemas | 10 / 9 | 10 / 9 | 10 / 9 | |
| active grammar + schemas | 10 / 9 | 12 / 10 | 12 / 10 | |
| active grammar, no schemas | 9 / 8 | 11 / 10 | 11 / 10 | |

- Whitelist, no schemas, at ×100: `map-adjacent`, `positions`, `scan`, `shift-seq`, `best-shift` all still
  `:cutoff`. A 7–10 operator grammar does not help when the recursion shape is missing.
- Active grammar + schemas at ×10: `seq-corr` solved at ~665k (sound); `scan` "solved" at 405,758 with a
  401-bit program that hard-codes a quoted step function — **held-out FAIL**. `map-adjacent`, `shift-seq`,
  `best-shift`, `argmax-corr` still cutoff at ×100.
- So more budget, in every regime, either changes nothing or adds one sound solution and one impostor.

### 4.6 One minutes-scale run (`scripts/e4_x2000_shiftseq.sh`, `logs/e4_x2000_shift-seq.log`)

`shift-seq` (smallest known solution), 11,000 MB heap, quiet machine:

| total work | claim | CPU s | live MiB | completed body bits, root / child 1 / child 2 |
|---|---|---|---|---|
| 350M (×1000) | `:cutoff` | 49.2 | 3,366 | 44 / 47 / 42 |
| 500M (×1430) | `:cutoff` | 72.6 | 4,750 | 45 / 47 / 43 |
| 700M (×2000) | **not reached: `Heap exhausted during garbage collection`** | — | — | — |

The process died 157 s after launch (wall, including load and prefix replay). An 11 GB heap therefore
holds less than ~100 s of this search.

### 4.7 Harness artifacts in the STAGE0 E0b-2 table

`stage0-audit.lisp` loads a prerequisite battery function only when `(not (defined-function-p …))`. A failed
recursive synthesis leaves its oracle stub defined, so the prerequisite is then *not* loaded, and — having no
knowledge entry — it is absent from every later active grammar. Printed grammars
(`logs/e4_seq_x1_nofix_dbg.log` vs `logs/e4_seq_x1_fix_dbg.log`):

| at spec | audit as written | with prerequisites loaded when the library has no entry |
|---|---|---|
| `best-shift` (active grammar) | no `:seq-corr` | `:seq-corr` present |
| `argmax-corr` (active grammar) | no `:seq-corr`, no `:best-shift` | both present, but no tuple accessor |

Consequences:
- `best-shift` and `argmax-corr` "TIMEOUT" in the active-grammar columns are cascades from `seq-corr`'s
  timeout, which itself is a 1.9× budget shortfall.
- Whitelist-no-schemas `argmax-corr` "FAIL (51,825)" is not a search failure: the search finds the correct
  84-bit `(at (best-shift X0 X1 0) 1)` at 51,952 work and then `commit-synthesis-job` raises
  `Unknown knowledge-entry :BEST-SHIFT` (`logs/e4_wlns_argmax-corr.log`). With the prerequisite loaded it is
  solved soundly in 99,198 work (that regime becomes 11 / 10).
- With the prerequisite loaded, active-grammar `argmax-corr` is still unsolved at ×100:
  `active-library-spec-operators` adds tuple operators only for tuple types in the spec's own signature, so
  `(at <tuple> 1)` is not in the grammar. With the fix, `best-shift` has `:seq-corr` and is still unsolved at
  ×100 (it needs the `(+ X2 1)` self-call).

---

## 5. E5 — Algebra discovery

Scripts: `scripts/e5_run.sh`, `scripts/e5_algebra.lisp`, `scripts/e5b_algebra_raised_cap.lisp`,
`scripts/e5b_algebra_raised_cap_int.lisp`. Logs: `logs/e5_*.log`, `logs/e5b_*.log`.

Milestone test module (`sbcl --script tests/run.lisp algebra`): 8 tests, 27,871 checks; 3.61 s (root),
3.92 s (v2).

**What is discovered at default settings** (`discover-arithmetic-solver`, `:body-bound 16`, operators
+ − * /): for each of the four operators and each argument position, a **one-operator** inverse plus a
guard.

| domain | solvers found | work per solver | CPU per solver | total |
|---|---|---|---|---|
| GF(5), 50 rows | 8 | 645,521–703,758 | 0.05–0.08 s | 5,515,907 work, 0.47 s |
| GF(7), 98 rows | 8 | 2,120,865–2,262,427 | 0.12–0.14 s | 17,819,925 work, 1.03 s |
| `:int`, 162 rows | 8 | 653,520–705,821 | 0.08–0.14 s | 5,512,035 work, 0.92 s |

Witnesses: solve `+` → `(- X1 X0)`; `−` → `(+ X0 X1)` or `(- X0 X1)`; `*` → `(/ X1 X0)` guarded by `X0 ≠ 0`
(on `:int` also `(= X1 (* (/ X1 X0) X0))`); `/` → `(* X0 X1)` or `(/ X0 X1)` with guards. Each discovery
enumerates 89 (`:int`) to 333 (GF(7)) expressions falling into 23–49 behaviour buckets.

**Raising the term-size bound** (solve `k − x = c`; work includes the vocabulary observation):

| `:body-bound` | GF(7) work | expressions / behaviours | CPU s | `:int` work | expressions / behaviours | CPU s |
|---|---|---|---|---|---|---|
| 12 | 145,753 | 25 / 17 | 0.06 | 314,870 | 41 / 15 | 0.11 |
| 16 (default) | 2,262,422 | 333 / 49 | 0.13 | 697,685 | 89 / 23 | 0.10 |
| 22 | 4,104,441 | 589 / 86 | 0.19 | 8,910,206 | 969 / 70 | 0.54 |
| 24 | 25,322,450 | 3,277 / 237 | 0.94 | 25,879,209 | 2,697 / 102 | 1.30 |
| 26 | **default: assertion "Observation cutoff"**; raised cap: 106,122,552 | 12,685 / 261 | 3.60 | 25,879,377 | 2,697 / 102 | 1.34 |
| 28 | 208,002,969 | 23,661 / 261 | 7.41 | 37,729,529 | 3,849 / 114 | 1.83 |
| 30 | 252,324,120 | 28,781 / 430 | 9.11 | **default: assertion**; raised cap: 329,234,643 | 30,025 / 329 | 19.95 |
| 32 | 922,544,511 | 100,461 / 1,197 | 33.66 | 329,234,859 | 30,025 / 329 | 22.29 |
| 34 | **heap exhausted (4 GB)** | | | not run | | |

- **Internal cap found:** `discover-arithmetic-solver` defaults `:work-limit` to `+completion-work+`
  = 100,000,000 (`laws.lisp:440`), and `finish-observations` *asserts* on cutoff. At the default this stops
  GF(7) at body-bound 26 and `:int` at 30. I raised it by passing `:work-limit 20000000000` from the script
  (no source change).
- Scaling: default 16 → 24 bits (one- to two-operator terms) costs ×11 (GF(7)) and ×37 (`:int`); 24 → 32 costs
  ×36 (GF(7)); 24 → 30 costs ×12.7 (`:int`). Roughly ×35 per added operator, the same exponent as E3.
- The witness is `(- X0 X1)` at every bound: the question asked has a one-operator answer, so the extra
  work buys nothing. At bound 32, 100,461 expressions fall into 1,197 behaviours.
- One notch on the operator set (`:mod` added, `:int`): work +0.002 % at bound 16, +7.6 % at 20, +0.6 % at
  24 — `:mod` carries a 14-bit overhead, so terms containing it barely fit these bounds.

---

## 6. E6 — Where the time goes

Scripts: `scripts/e2_e6_large.sh` (benchmark's own `profile` mode, `sb-sprof :cpu`, 2 ms),
`scripts/e6_profile_synthesis.lisp`. Logs: `logs/e6_*.log`. The Makefile's `benchmark-profile` workload
(`quadratic 70`) finishes in 0.044 s and yields 11 samples, so the profiles below use larger runs.
Percentages are of profiler samples ("Total" column = inclusive).

**(a) Flat exact search, `quartic 86`** (first 4.0 s of a 20.6 s run; 2,000 samples, the benchmark's
`:max-samples`):

| share (inclusive) | what |
|---|---|
| 52 % | `settled-evaluation`: running candidates on rows, including tariff accounting (`validation-work` 10 %, `primitive-cost` 8 %, `execute-primitive` 6 %, evaluation closures 16–18 %) |
| 22 % | `ensure-ast-meta` → `gethash/weak` under `call-with-recursive-system-lock`: per-node AST metadata kept in a weak hash table, one locked lookup each |
| 10 % | `compute-app-meta` (building metadata for new applications) |
| 31 % of CPU over the whole run | GC (6.40 s of 20.62 s; 19 % at `quartic 82`, 4 % at `quartic 77`) |

**(b) Synthesis job, `map-adjacent` to 35M work** (1,168 samples):

| share (inclusive) | what |
|---|---|
| 93 % | `resume-synthesis` (self 11.8 %) |
| 69 % | `synthesis-node-step` (self 8.5 %) |
| 41 % | `row-job-step` |
| 20 % | `enumeration-step`, of which `app` 16 %, `ensure-ast-meta` 11.5 %, `compute-app-meta` 10.6 % |
| 10 % | `charge` (ledger) |
| 9 % | `activate-job-oracle` (called on every node step) + `find-function-definition` 2.7 % |
| 5.5 % | `%assoc` |
| 5 % | `select-synthesis-lane`; 4 % `synthesis-finished-p` (re-evaluated every loop iteration) |
| **3 %** | `advance-accounted-evaluation` / `advance-evaluation` — actually running candidates |
| 9 % of CPU at 35M, 16–21 % at 350M | GC |

In the synthesis job candidate evaluation is about 3 % of the time; the rest is the one-work-unit-at-a-time
scheduling loop, ledger charging, and AST construction and metadata lookup. Most candidates in these lanes
are not of the target type or are rejected on the first row, so there is little evaluation to do.

---

## 7. Internal caps and constants encountered

| constant | where | effect observed | raised? |
|---|---|---|---|
| per-spec budget 350,000 | `synthesize-spec-entry :budget`, audit | = 0.06–0.07 s CPU | yes, to 350M (five specs) and 500M (one) |
| description bound 130 (+24 active grammar) | `synthesize-spec-entry :bound` | smaller than all four unsolved reference programs (161–306 bits) | +100: no change |
| `:max-depth 2` | `synthesize-spec-entry` | tree is 2–3 nodes | 3, 4: no change |
| `:heuristic-budget 15000` | `synthesize-spec-entry` | — | ×10: no change |
| self-call template `(SELF (tail X0) others-unchanged)`; child language without `:tail :at :if :=`; no self operator in the root lane | proposal generation | makes the four unsolved specs inexpressible | not a constant |
| tuple operators only for signature types | `active-library-spec-operators` | `argmax-corr` inexpressible in the active grammar | not changed |
| prerequisite test `defined-function-p` | `stage0-audit.lisp` | cascade failures (§4.7) | fixed in `scripts/e4_sequence.lisp` (`fix` mode) |
| `+completion-work+` = 100,000,000 | `laws.lisp:440`, default of `discover-arithmetic-solver` | assertion at body-bound 26 / 30 | passed 2 × 10^10 as argument |
| `+benchmark-heap-cap+` = 768 MiB | `benchmark.lisp` | `quartic 90` stops at 22.8 s | not changed |
| SBCL heap | `--dynamic-space-size` | 5 GB dies before 350M work; 7 GB completes it; 11 GB dies before 700M; 4 GB dies at algebra bound 34 | 2–11 GB used |
| `BENCHMARK_SECONDS ?= 300` | Makefiles | never approached: largest standard run 0.43 s | — |

No source file of the copy was edited. Every raised value was passed as an argument from a script in
`scripts/`; the prerequisite fix lives in a copy of the audit function inside `scripts/e4_sequence.lisp`.
The copy's `library/*.sexp` (root, newly created) and `v2/library/*.sexp` (rewritten, byte-identical) were
produced by the bootstrap runs of E1.

---

## 8. Skipped, and limits of these measurements

- **No run longer than ~75 s of search** (500M work). Longer runs are blocked by memory, not by time:
  ≈10 live bytes per work unit, about twice that during collection. Everything said about 1 h and 10 h is extrapolation from fitted per-bit
  factors over 12–23 bits of horizon.
- ×1000 was run per spec for the five specs unsolved at ×100, not as a whole 16-spec sequence.
- Beyond ×1000 only `shift-seq` was tried (×1430 reached, ×2000 not).
- v2's `:prune-behaviors-p` was measured in flat searches only (E3, E3b). I did not wire it into the
  synthesis job's node searches, so there is no E4 number with dedupe on.
- E5 covers the M4 arithmetic-solver discovery only (`milestones/algebra-discovery.lisp`); law discovery,
  propagation and the other milestone drivers were not timed separately.
- The GF(7) algebra scaling stops at body-bound 32 (heap), `:int` at 32 (my list ended there).
- First-pass E1 timings and the `e4_x1000` / `e3 … observe` rates were taken under load average 8–13.

## 9. Scripts (all in `scripts/`) and their logs (in `logs/`)

| script | purpose | logs |
|---|---|---|
| `e1_baseline.sh`, `e1b_root_kernel_after_bootstrap.sh`, `e1c_retime.sh` | suites and bootstraps, two timing passes | `e1_*.log`, `e1b_*.log`, `e1c_*.log` |
| `e4_0_stage0_reproduce.sh` | unmodified `stage0-audit.lisp` | `e4_0_stage0_reproduce.log` |
| `e2_e6_run.sh`, `e2_e6_large.sh` | `benchmark.lisp` workloads, meter, profile | `e2_*.log`, `e6_benchmark_profile_*.log` |
| `e3_growth.lisp`, `e3_run.sh`, `e3_big.sh` | growth on g2 / g3, modes exact / prune / observe, v1 and v2 | `e3_*.log` |
| `e3b_real_grammar.lisp`, `e3b_run.sh` | growth on the real grammars of `shift-seq`, `map-adjacent`, `best-shift` | `e3b_*.log` |
| `e4_rescue.lisp`, `e4_run.sh` | budget ladder for one spec; args: target, max budget, bound-add, max-depth, heuristic-budget, wall cap, regime | `e4_smoke*`, `e4_x100_*`, `e4_x3000_*` (5 GB heap; one heap exhaustion, two killed by me to free RAM), `e4_x1000_*`, `e4_x2000_*` |
| `e4_x1000_sequential.sh`, `e4_x2000_shiftseq.sh` | the 350M and 700M runs, one process at a time | `e4_x1000_driver.log` |
| `e4_fit.py` | per-lane growth fit from the rung lines | `e4_fit.txt` |
| `e4_nodes.lisp` | prints every node's proposal, bindings, inputs, language | `e4_nodes_*.log` |
| `e4_caps.sh` | internal-constant variations at 35M | `e4_capd3_*`, `e4_capd4_*`, `e4_caph10_*`, `e4_capb100_*`, `e4_capall_*` |
| `e4_regimes.sh` | the audit's other three regimes at 35M | `e4_ags_*`, `e4_wlns_*`, `e4_wls_*` |
| `e4_sequence.lisp`, `e4_sequence_run.sh` | whole 16-spec audit at ×1 / ×10 / ×100, with and without the prerequisite fix | `e4_seq_*.log` |
| `e5_run.sh`, `e5_algebra.lisp`, `e5b_algebra_raised_cap.lisp`, `e5b_algebra_raised_cap_int.lisp` | algebra timing and scaling | `e5_*.log`, `e5b_*.log` |
| `e6_profile_synthesis.lisp` | `sb-sprof` profile of a synthesis job (generated from `e4_rescue.lisp`) | `e6_profile_synthesis_map-adjacent.log` |

Total wall-clock spent on experiments: about 40 minutes.
