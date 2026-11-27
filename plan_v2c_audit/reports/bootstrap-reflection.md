# bootstrap-reflection: how the library comes into being, and what reflection exists

Auditor: `bootstrap-reflection`. Scope: `bootstrap/*`, `v2/bootstrap/*`, `v2/library/*.sexp`,
`batteries-and-reflection.md`, `messages.lisp`, `explain.lisp`, `persistence.lisp`,
`tests/{batteries,messages,library}.lisp`, `v2/experiments/stage0-audit.lisp`, `v2/STAGE0_RESULTS.md`,
and the `consolidate.lisp` / `abstraction.lisp` / `descriptors.lisp` / `decompose.lisp` functions the
bootstrap calls.

Tags: **VERIFIED** = I read the code at the cited lines or ran it; **INFERRED** = a conclusion drawn
from verified facts but not itself executed.

Line numbers are for `v2/` unless a path says otherwise. `bootstrap/` is byte-identical between root
and `v2/` (`diff -q`), as are `messages.lisp`, `explain.lisp`, `persistence.lisp` and the three test
files. The repository was not touched; everything ran in a scratch copy. All scripts and raw outputs
are in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/bootstrap-reflection/`
(index in section 11).

Timing caveat: the machine was shared with the other auditors, so wall times vary by up to 2x
between runs. Work-unit counts are deterministic and reproduce exactly.

---

## 0. Findings in one page

1. **The whole cold bootstrap is 2.28 million work units and takes 0.3 to 1.1 s** of search (2.3 to
   6 s wall including loading the kernel from source). It regenerates `v2/library/*.sexp`
   byte-for-byte, from both the root and the `v2` kernel. The per-spec budget is 350,000 work units,
   which is about 0.08 s of CPU. One hour of search would be roughly 16 to 25 billion work units,
   i.e. about 10,000 times the entire library. (section 1)

2. **By bits, 59% of the library is hand-authored AST** (5,254 of 8,884 bits; 18 of 61 entries), and
   a further 6% is stamped by single-purpose host templates. 13% was found by search with an
   author-chosen operator whitelist, 13% by search steered by a hand-written recursion skeleton, 6%
   derived by generic mechanical transformation, and **2.5% (8 arithmetic solver witnesses of 3
   atoms each) by search with a generic grammar**. (section 2)

3. **Within the searched entries, the part the search actually had to find is tiny.** Across the 19
   synthesis jobs of the bootstrap, the answers total 2,401 body bits, of which 460 bits (19%) were
   found in a leaf search; the rest is decoder skeleton. The largest expression enumerated anywhere
   in the bootstrap is `(at (best-shift X0 X1 0) 1)`: 8 atoms, 53 bits. In 16 of 19 jobs the leaf is
   1 to 6 atoms and came straight out of Stage A with under 30 units of enumeration. (section 3.4)

4. **The 16 synthesized function names and bodies reproduce an earlier hand-written answer key.**
   `library/{arithmetic,scans,sequence-shift,sequences}.lisp` (207 lines, commit `849013a`) defined
   the same 21 entries by hand; they were deleted in `b3af2e6` and replaced by 1,304 lines of
   `bootstrap/` that make the kernel re-derive them. 20 of the 21 come out equivalent, down to the
   literal `'((0))` in `:shift-seq`, which the spec supplies as a constant. (section 3.5)

5. **More budget does not recover what the recursion schemas supply.** Without
   `recursion-schemas.lisp`, `:map-adjacent`, `:positions`, `:scan`, `:shift-seq` and `:best-shift`
   are still not found at 350,000,000 work units (1,000x the bootstrap budget, about a minute
   each); the search graph stays at 2 or 3 nodes and 93% or more of the work is flat enumeration in
   one or two nodes. `:scan` exhausts its bounded space at 321.8M. Raising depth and description bound does
   not change this. This partly contradicts the "budgets were just too small" hypothesis: here the
   limit is the proposal set, not time. (section 4.2)

6. **But in one place more budget does substitute for author help.** The author split the
   three-variable law search into `{+}`-only and `{*}`-only grammars. With the combined grammar at
   the bootstrap's 80,000 units associativity is not found; at 800,000 units (0.15 s) it is.
   (section 2.3)

7. **Three specs depend on "trace-complete" examples**, rows that are the execution trace of the
   intended program including its intermediate accumulator states. With whitelist and schemas kept
   and only the rows replaced by ordinary input/output pairs, `:foldl`, `:scan` and `:best-shift`
   are not found at 35M work. (section 3.3)

8. **Reflection as built is a 128-line read-only projection with zero kernel readers.**
   `messages.lisp` turns three of a job's ten-plus message kinds into integer/boolean rows. Only a
   test file and an offline experiment script read them. Step 3 of `batteries-and-reflection.md`
   (reified trace frames, `:conserved` / `:regime-hit` / `:disambiguate` messages, L0 to L3 scoped
   absorption, `*reflective-depth*`) has no code at all. (section 5)

9. **An older reflective loop does exist and is wired into search**: search traces are condensed into
   a priority-predictor program that `node-priority` adds to analytic MDL. Run on the kernel's own
   16-spec curriculum it learns the constant `0` and changes total work by +0.02%, because 40 of its
   42 training labels saturate at the clamp and the jobs have 1 to 5 nodes each. In all 19 bootstrap
   synthesis jobs: 0 nogoods, 0 reused subproblems. (section 5.4)

10. **The library does make later synthesis reach further, by a large factor, but the bootstrap does
    not use the mechanism that does it.** On 8 held-out tasks, enabling library lifting proposals
    solved 3 tasks in 25k to 42k work that the kernel alone does not solve at 35M (over 800x), and
    made a fourth 3.2x cheaper; three others got 1.7 to 3x more expensive. Offering library
    functions as plain grammar operators, which is how the bootstrap offers them, never helped and
    in one case cost 6.6x. `synthesize-spec-entry` leaves lifting proposals off for its recursive
    jobs, which are 15 of the 16. (section 6)

11. **Sound and worth keeping**: `:spec` replay on load, refusal of wrong specs and wrong types,
    re-certification instead of trusting stored certificates, the persistence fixed point,
    deterministic metered work, the evidence grades, and `discover-library-abstractions`. `:map` and
    `:foldr` are the one result that survives removing both the whitelist and the schemas.
    (section 7)

---

## 1. Running it (question 6)

**VERIFIED** by `run-bootstrap.sh` and `instrumented-bootstrap.lisp`.

| Run | Bootstrap proper | Wall incl. kernel load | Total work | Output vs committed `v2/library/*.sexp` |
| :-- | --: | --: | --: | :-- |
| `v2`, `sbcl --script bootstrap/build-batteries.lisp` | 0.44 s | 3.16 s | 2,276,265 | all 8 files byte-identical (`cmp`) |
| root, same command | 1.07 s (contended), 0.32 s on rerun | 5.98 s, 2.32 s on rerun | 2,276,298 | all 8 files byte-identical |

Plainly: **the cold bootstrap of the whole library takes well under a second of search.** Throughput
is about 4.5 to 7 million work units per second, so the default per-spec budget of 350,000
(`consolidate.lisp:1249`) is about 0.05 to 0.08 s and the seed budget of 80,000
(`bootstrap/build-batteries.lisp:562`) about 0.015 s.

Work by battery (one ledger each; sequences and descriptors share one):

| Battery | Work | Largest category |
| :-- | --: | :-- |
| algebra | 9,105 | law proposal |
| arithmetic | 672,221 | synthesis 480,000 = 8 x 60,000: each witness search runs to its full limit with no early stop (`consolidate.lisp:1497`), although the answers are 15-bit expressions |
| constructors | 91,927 | guard search 73,401 |
| functors | 33,739 | simulation only: replaying hand-built transformers |
| sequences + descriptors | 679,011 | synthesis 652,294 |
| scans | 265,434 | synthesis 263,277 |
| sequence-shift | 524,828 | synthesis 471,035 |

Shape of the 19 jobs that go through `resume-synthesis`: 1 to 5 nodes each (1, 2, 3, 4, 5 nodes: 1,
5, 7, 5, 1 jobs), 181 messages in total, **0 nogoods and 0 reused subproblems in every job**. In 16
of the 19, `:preparation` (Stage A condensation) is the largest work category, at 42% to 70% of the
job; the exceptions are the two constructor guard jobs and `:argmax-corr`.

The Stage 0 ablation (`make -C v2 stage0` equivalent) runs all 64 synthesis attempts in 5.6 s wall.

There is no test that regenerates the batteries. `batteries-and-reflection.md:103` promises "a
dedicated bootstrap test" that "the kernel still regenerates equivalent `.sexp` batteries from scratch
within bounded work"; `grep -n "build-batteries\|bootstrap/" tests/` returns nothing. **VERIFIED.**
The regeneration does hold when run by hand.

Root has no `library/` directory in git (only `v2/library/` is tracked), while root
`*battery-directory*` is `library/` next to `consolidate.lisp` (root `consolidate.lisp:1662`) and
`tests/batteries.lisp:32-34` expects all eight names. So root `make test` needs `make bootstrap`
first. **INFERRED**, not run.

---

## 2. Provenance of every library entry (question 1)

### 2.1 Classes

- **A**: found by kernel search over a generic default grammar, no per-spec grammar help.
- **B**: found by kernel search, using only the kernel's own proposal machinery, over an operator
  whitelist or micro-grammar the spec author chose.
- **C**: found by search in which a hand-written skeleton from `recursion-schemas.lisp` is on the
  winning path.
- **D**: derived by a generic mechanical transformation of other entries (anti-unification, template
  retyping).
- **D-host**: stamped by a single-purpose host template. The entry's expression is written out in
  kernel source; the kernel decides only whether it applies. I split this from D because calling it
  "derived by the kernel" would overstate it and calling it E would misplace where it was authored.
- **E**: hand-authored AST or host-spliced value in `build-batteries.lisp`.

### 2.2 Totals

The eight files hold 92 entries: 61 operational and 31 `:spec`. **VERIFIED** by parsing the packets
(`list-entries.lisp`). Bits are the `:bits` field each entry records. Every entry records `:gain 0`.

| Class | Entries | Share | Bits | Share |
| :-- | --: | --: | --: | --: |
| A generic search | 8 | 13.1% | 225 | 2.5% |
| B whitelisted search | 16 | 26.2% | 1,200 | 13.5% |
| C schema-steered search | 7 | 11.5% | 1,153 | 13.0% |
| D generic derivation | 3 | 4.9% | 511 | 5.8% |
| D-host template stamp | 9 | 14.8% | 541 | 6.1% |
| E hand-authored | 18 | 29.5% | 5,254 | 59.1% |
| **Total** | **61** | | **8,884** | |

By kind: 15 laws, 13 solvers, 13 functions, 10 transformers, 8 descriptors, 1 decoder template, 1
motif. Of the 14 knowledge kinds the kernel defines, the library uses 8. The four that record
something learned from search (`:nogood-schema`, `:dip-feature`, `:heuristic`, `:relation`) do not
appear, because `save-clean-battery` keeps only the IDs the script lists and drops "auto
side-effects" (`build-batteries.lisp:81-87`). **VERIFIED.**

### 2.3 The table

`work` is the entry's recorded `:work` field. For synthesized functions it is the job's total work;
for the others it is a run or validation cost, not a discovery cost.

**algebra.sexp** (12 laws, 442 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:int/cancel-+-0`, `-+-1`, `---0`, `---1` | 36 each | 25 | E | written as terms and attested `:trusted-axiom`, `build-batteries.lisp:106-117` |
| `:int/id-+-right`, `id-+-left` | 25 each | 370 | B | observation search over GF(3), one variable, operators `{+,*}`, literals `(0 1)`, `:127-131`, `:147` |
| `:int/id-*-right`, `id-*-left` | 28 each | 370 | B | same |
| `:int/comm-+`, `:int/comm-*` | 36 each | 2,880 / 2,936 | B | two variables, `{+,*}`, `:132-136`, `:148` |
| `:int/assoc-+` | 60 | 25,834 | B | three variables, operator list `{+}` only, `:137-141`, `:149` |
| `:int/assoc-*` | 60 | 26,740 | B | three variables, operator list `{*}` only, `:142-146`, `:150` |

After the search, a host shape filter decides what is kept and what it is called: only laws for which
`law-operator-fact` returns commutative, associative or identity survive (`:155`, `:166`;
`consolidate.lisp:709-735`), and the ID comes from a host `ecase` (`:168-171`). The survivors are
retyped to `:int` and checked on six sample values (`:160-165`).

I measured the filter (`law-filter.lisp`, **VERIFIED**): the four searches propose 66 + 50 + 35 + 36 =
187 laws; 14 pass the shape filter; they collapse to the 8 named entries. The other 173 are
discarded. No distributive law, zero law or inverse is ever registered.

I also measured the grammar split. With three variables and both operators together at the
bootstrap's 80,000 units, only commutativity is found. At 800,000 units both associativity laws
appear. So here a 10x budget in the undivided grammar recovers what the hand-split supplied.

**arithmetic.sexp** (8 solvers, 225 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:solve-+-0`, `+-1`, `---0`, `---1` | 15 each | 13 | A | spec has no `:operators` (`build-batteries.lisp:191-214`), so the witness language is the default `{+,-,*,/}` with literals `(0 1)` (`consolidate.lisp:1420-1430`); plain `start-search` (`:1496-1499`) |
| `:solve-*-0`, `*-1`, `/-0` | 39 each | 31 | A | same, plus a guard from `synthesize-boolean-separator` over `:none` rows (`:215-232`) |
| `:solve-/-1` | 48 | 37 | A | same (`:233-238`) |

Caveats on calling this A. Each witness is one operator application, three atoms. The `:unique-p` /
`:finite-unique-p` flags are declared by the author in spec metadata. Uniqueness of the four
`+`/`-` solvers is attested `:trusted-axiom` by `induce-law-solvers` (`consolidate.lisp:1686-1701`)
from the four hand-written cancellation axioms, which is why `build-arithmetic-battery` loads
`algebra.sexp` first (`build-batteries.lisp:185-187`). The guards that came out are equivalent to the
earlier hand-written ones (`(if (= k 0) nil t)`), not the sharper divisibility guard
`batteries-and-reflection.md:89` promised.

**constructors.sexp** (3 solvers + 3 laws, 382 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:solve-cons-0` | 82 | 47 | B | `:operators (at tail)`, `:guard-operators (tail =)`, 3 positive + 4 `:none` rows, `:262-278` |
| `:solve-cons-1` | 79 | 45 | B | `:operators (at tail)`, `:guard-operators (at = =)`, `:279-295` |
| `:solve-cons-01` | 73 | 49 | B | `:operators (tuple at tail)`, `:296-308` |
| `:cons/head`, `:cons/tail`, `:cons/non-empty` | 52, 49, 47 | ~500 | E | both sides written by hand, checked on 4 sample rows, `:311-321` |

**functors.sexp** (10 transformers, 4,917 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:functor/map-inverse-0`, `-1` | 448, 445 | 0 | E | AST built in host Lisp, `:376-392` |
| `:functor/map-guard-0`, `-1` | 783, 780 | 0 | E | `:394-419` |
| `:functor/map-witness-0`, `-1` | 557, 554 | 0 | E | `:421-433` |
| `:functor/unary-map-witness` | 187 | 0 | E | `:435-447` |
| `:functor/pointwise-seq-witness` | 476 | 0 | E | `:449-473` |
| `:functor/pointwise-param-guard` | 498 | 0 | E | `:502-523` |
| `:functor/pointwise-param-witness` | 189 | 50,000 | B | `learn-knowledge-transformer` over a language of 2 operators (`code-subst` at one exact type, `tuple`) and 2 hand-built constants (`head0`, `head1`), from 1 example row, `:475-494`. The answer is `(code-subst X0 (tuple head0 head1))`; the search chose the order of two constants. |

These ten are not free-standing knowledge. Kernel source calls them by fixed ID:
`functor-transformer-library` looks up `:functor/map-guard-0` (`consolidate.lisp:1949`) and
`induce-functorial-solvers` runs `:functor/map-guard-N`, `map-inverse-N`, `map-witness-N`,
`unary-map-witness`, `pointwise-seq-witness`, `pointwise-param-witness`, `pointwise-param-guard` by
name (`consolidate.lisp:2050-2104`). They are 292 lines of deleted host code
(`bootstrap-inverters.lisp`, removed in `b3af2e6`) re-expressed as about 150 lines of host-built AST.
**VERIFIED.** The `reg-tr` helper does attach and replay a one-row spec for each
(`build-batteries.lisp:354-370`), so they are checked, but not found.

**sequences.sexp** (6 functions, 1 solver, 1 template, 1 motif, 1,181 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:map` | 127 | 64 | D | anti-unification of `:copy`, `:inc-all`, `:dbl-all`, `:569-584`; `abstraction.lisp:380-464` |
| `:foldr` | 133 | 70 | D | anti-unification of `:sum-all`, `:len-all`, `:prd-all`, same lines |
| `:foldl` | 133 | 81,333 | C | winning path `:state-fold-inductive`; whitelist `:622` |
| `:filter` | 192 | 75,546 | B | winning path two `:heuristic-conditional` (kernel's own); whitelist `:637-638` |
| `:map-adjacent` | 213 | 109,012 | C | winning path `:lookahead-inductive`; whitelist `:654-655` |
| `:positions` | 88 | 46,196 | C | winning path `:counter-inductive`; whitelist `:669-671` |
| `:solve-at-1` | 193 | 100 | E | host supplies the index list as a third input (`:684-688`), searches a 2-operator language with `:library-functions '(:filter)` (`:689-692`), then splices `(positions xs 0)` for that input (`:697-699`) and sets the solver flags by hand (`:700-704`). The searched leaf is `(= X2 (at X1 X0))`, 38 of the witness's 175 body bits. |
| `:comprehension/filter-map` | 41 | 0 | E | expression, trigger and metadata including `:policy-score -18` written by hand, `:711-734` |
| `:foldr=foldl/monoid` | 61 | 0 | D-host | `induce-fold-motifs` builds exactly this equation when two fold-shaped functions agree on probes (`consolidate.lisp:905-915`); the script hand-defines the instances `:sum-m`, `:prod-m` and hand-adds their `:refactored-by` edges, `:745-753` |

The six seeds (`:copy`, `:inc-all`, `:dbl-all`, `:sum-all`, `:len-all`, `:prd-all`) are class B and are
not saved. `:map` and `:foldr` get their names from the script (`:577`, `:581`).

**descriptors.sexp** (8 descriptors, 480 bits)

All eight are D-host: `:desc/scalar-reduction` 3, `:desc/subset-elements` 231, `:desc/len-le` 66,
`:desc/len-dec-1` 61, `:desc/len-eq` 49, `:desc/outer-shape-2d` 3, `:desc/empty->empty` 18,
`:desc/pointwise-map` 49. They are side effects of `define-function` harvested at
`build-batteries.lisp:758-763`. Their IDs and expressions are written in `descriptors.lisp:463-497`
and `:545-580`. The "observation search" there is run with an operator list and a `:body-bound` sized
to the prototype (`descriptors.lisp:436-440`, `:449-453`) and is used only to test whether the
hand-written prototype holds. `:desc/outer-shape-2d` exists only because the script retypes `:map`
to 2D for the purpose (`:759`). **VERIFIED.**

**scans.sexp** (2 functions, 462 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:scan` | 211 | 263,277 | C | winning path `:state-scan-inductive`; whitelist `:799-800` |
| `:scan-pair` | 251 | 138 | D | `instantiate-entry-template` of `:scan` at author-given types, `:805-811` |

**sequence-shift.sexp** (5 functions, 1 solver, 795 bits)

| Entry | Bits | Work | Class | Evidence |
| :-- | --: | --: | :-- | :-- |
| `:shift-seq` | 130 | 99,009 | C | winning path `:countdown-inductive`; whitelist `:844-845`; constant `'((0))` supplied at `:847` |
| `:seq-corr` | 160 | 87,499 | B | winning path `:heuristic-additive` + `:lockstep-inductive` (kernel's own, `decompose.lisp:416`); whitelist `:858-859` |
| `:best-shift` | 255 | 196,019 | C | winning path `:heuristic-conditional` + `:counter-inductive`; whitelist includes `:seq-corr`, `:872-873` |
| `:argmax-corr` | 53 | 36,063 | B | non-recursive; whitelist is 2 operators `(best-shift at)` and literals `(0 1)`, `:886-887` |
| `:last-or` | 123 | 32,013 | C | winning path `:lookahead-inductive`; also solvable without (section 4.2) |
| `:solve-shift-seq-by-correlation` | 74 | 37 | B | witness language is the single operator `:argmax-corr`, `:920` |

Winning paths are **VERIFIED** by instrumenting `resume-synthesis` and walking the winning node's
ancestors (`instrumented-bootstrap.lisp`, output `instr-v2.out`).

`:last-or` is in the library only to serve the solver's guard: it appears in the spec's
`:guard-operators` (`:925-927`), which is the operator set of the earlier hand-written guard. The
guard that was actually induced is the replay `(= (shift-seq X0 (argmax-corr X0 X1)) X1)`
(`consolidate.lisp:1519-1525`), which does not call it. So `:last-or` is unused by any entry.
**VERIFIED** from the packet. The hand-written guard was a cheap structural test whose stated purpose
was to avoid running the correlation; the induced one runs the correlation and the shift. **INFERRED**
that this is costlier at use.

---

## 3. The information budget (question 2)

### 3.1 What a `:spec` contains

A `:spec` entry (`consolidate.lisp:1112-1137`) holds: the input and target types; the example rows
(in `:residual`); a `:specifies` edge naming the entry to produce; and metadata: `:target-kind`,
`:operators` (the whitelist), `:literals`, `:constants`, and for solvers `:inverts`, `:position`,
`:guard-operators`, `:unique-p`, `:finite-unique-p`, `:metric-p`, `:certified-p`.
`synthesize-spec-entry` turns it into a job with description bound 130, budget 350,000, Stage A
budget 15,000 and `:max-depth 2` (`consolidate.lisp:1248-1282`). In the bootstrap every call also
passes the recursion-schema expander (`build-batteries.lisp:13-15`).

### 3.2 Per function spec

Computed by `spec-budget.lisp` and `leaf-bits.lisp` on the committed library. **VERIFIED.** "Example
bits" prices each row's values with the kernel's own value codec. "Leaf" is the expression the
winning node's own search or Stage A produced; everything else in the answer is decoder skeleton.

| Function | Rows | Example bits | Whitelist | Distractors | Answer bits / atoms | Leaf bits / atoms | Leaf |
| :-- | --: | --: | :-- | :-- | --: | --: | :-- |
| `:copy` (seed) | 4 | | `cons tail at = if + *` | `+ *` | 89 / 13 | 17 / 3 | `(cons X0 X1)` |
| `:inc-all` (seed) | 4 | | same, literal `1` | `*` | 100 / 16 | 29 / 6 | `(cons (+ X0 1) X1)` |
| `:dbl-all` (seed) | 4 | | same, literal `2` | `*`, literal `2` | 116 / 18 | 26 / 5 | `(cons (+ X0 X0) X1)` |
| `:sum-all` (seed) | 4 | | `tail at = if + *`, literal `0` | `*` | 85 / 14 | 12 / 3 | `(+ X0 X1)` |
| `:len-all` (seed) | 4 | | same, literals `0 1` | `* at` | 69 / 12 | 15 / 4 | `(+ X1 1)` |
| `:prd-all` (seed) | 4 | | same, literal `1` | `+` | 88 / 14 | 12 / 3 | `(* X0 X1)` |
| `:foldl` | 9 | 407 | `tail at = if code-eval` | none | 133 / 16 | 48 / 4 | `(code-eval X2 X1 X0)` |
| `:filter` | 7 | 359 | `cons tail at = if code-eval` | none | 192 / 25 | 4 / 1 | `X3` |
| `:map-adjacent` | 8 | 319 | same | none | 213 / 27 | 63 / 6 | `(cons (code-eval X2 X1 X0) X3)` |
| `:positions` | 11 | 291 | `cons tail at = if +`, literals `0 1` | `at`, literal `0` | 88 / 14 | 19 / 3 | `(cons X1 X2)` |
| `:scan` | 9 | 403 | `cons tail at = if code-eval` | none | 211 / 24 | 48 / 4 | `(code-eval X2 X1 X0)` |
| `:shift-seq` | 13 | 511 | `concat cons cons tail = < - if`, literals `0 1`, constants `()` and `((0))` | `cons` at `:int` | 130 / 22 | 30 / 5 | `(concat (cons X0 '((0))))` |
| `:seq-corr` | 7 | 234 | `+ * tail at = if`, literal `0` | none | 160 / 27 | 4 / 1 | `X2` |
| `:best-shift` | 9 | 405 | `seq-corr tuple at tail = < + if`, literals `0 1` | none | 255 / 33 | 5 / 1 | `X2` |
| `:argmax-corr` | 3 | 157 | `best-shift at`, literals `0 1` | none | 53 / 8 | 53 / 8 | `(at (best-shift X0 X1 0) 1)` |
| `:last-or` | 7 | 238 | `tail at = if` | none | 123 / 18 | 4 / 1 | `X3` |

Reading it:

- **Distractors.** Among the 10 saved function specs, the whitelist is the answer's operator set
  exactly in 9 by operator name (8 if `cons` at a second type counts). The six seeds share two
  grammars and so carry 1 or 2 distractor operators each; their literal lists are per task and
  exact except `:dbl-all`.
- **Types.** Everything is over `:int`, `(:seq :int)`, `(:tuple :int :int)` and `:code` over those.
  The algebra search is over GF(3).
- **Totals for the 10 saved function specs.** 3,324 bits of examples in; 1,558 bits of answer out;
  278 of those bits found at a leaf.
- **Totals for all 31 persisted specs.** 157 rows and 7,263 example bits, against 5,745 bits for the
  31 entries they specify (2,954 of which are five hand-built transformers).
- **Whitelist selection** costs the author little to state, about 7 to 17 bits per spec as a subset
  of the 16 to 20 operator generic grammar for that signature, but it removes the per-node branching
  the search cannot afford. Evidence: `:argmax-corr`, the only answer found by plain enumeration, is
  found in 22,229 enumeration units with its 2-operator whitelist and is not found at 3.5M with the
  generic grammar (section 4.2).
- **By text.** 949 lines of `build-batteries.lisp` plus 355 of `recursion-schemas.lisp` produce 61
  entries. The hand-written battery files they replaced defined 21 of the same entries in 207 lines.

### 3.3 Example design: trace-complete rows

The recursive search answers a candidate's self-calls from an oracle table built from the spec rows
(`decompose.lisp:781-785`), so a recursive call is only "known" if its arguments are themselves a
row. For plain structural recursion that means suffix-closed lists: `()`, `(3)`, `(1 3)`, `(4 1 3)`.
For state-threading recursions it means the rows must be the call trace of the intended program,
intermediate states included. The script says so for `:positions`: "Every recursive call the
definition makes on these rows is itself a row" (`build-batteries.lisp:659-661`). Examples:

- `:spec/foldl` (`:612-620`): `((1 2 3) 12) -> 6`, `((2 3) 11) -> 6`, `((3) 9) -> 6`, `(() 6) -> 6`.
  The second argument steps 12, 11, 9, 6: the accumulator of a left fold with `a - b`.
- `:spec/scan` (`:789-797`): `((2 -1 3) 1)`, `((-1 3) 3)`, `((3) 2)`, `(() 5)`.
- `:spec/best-shift` (`:868-870`): `((3 4 1) ys 0)`, `((4 1) ys 1)`, `((1) ys 2)`, `(() ys 3)`.

To write these rows the author must already know the algorithm.

I measured how much they matter (`trace-ablation.lisp`, `trace-ablation-foldl.lisp`, **VERIFIED**):
whitelist, literals, constants and recursion schemas kept; only the rows replaced by the same number
of ordinary input/output pairs whose intermediate states are not rows.

| Spec | Trace-complete rows | Black-box rows, 350k | Black-box rows, 35M |
| :-- | :-- | :-- | :-- |
| `:foldl` (step `2a-b` so order matters) | sound, 87,563 | not found | not found; space exhausted at 4.85M |
| `:scan` | sound, 263,277 | not found | not found |
| `:best-shift` | sound, 196,019 | not found | not found |
| `:positions` | sound, 46,196 | sound, 86,789 | |
| `:shift-seq` | sound, 99,009 | sound, 100,739 | |

A related effect on a held-out task: `last` with rows that are not suffix-closed is not found by the
kernel alone at 35M; with suffix-closed rows it is found at 129,622 (section 6).

### 3.4 What the search searched

From the Leaf columns above, plus the three non-function jobs (two constructor guards and the
`:solve-at-1` witness): over the 19 jobs, 2,401 answer body bits, 460 leaf bits. In 16 of the 19 the
leaf came from Stage A, and the node's own enumeration spent between 0 and 29 work units. The three
that needed real enumeration: a constructor guard (1,485 units), `:scan`'s step (5,954) and
`:argmax-corr` (22,229). The skeleton around the leaf comes from one of two places:

- the kernel's built-in splits: the inductive split `(if (= xs ()) base Z(head, self(tail)))`
  (`decompose.lisp:384-414`), its lockstep form (`:416`), and Stage B additive / conditional
  residuals. These are generic across tasks but are themselves fixed host skeletons;
- the five curriculum skeletons in `recursion-schemas.lisp` (section 4).

So "kernel search" in the bootstrap means: pick a base case, pick one of a handful of fixed
recursion shapes, and find a 1 to 8 atom expression for the hole. **VERIFIED** (`leaf-bits.lisp`).

### 3.5 The answer key

`git show 849013a:library/{arithmetic,scans,sequence-shift,sequences}.lisp` are hand-written battery
sources, 207 lines, defining 8 arithmetic solvers, `:map`, `:foldr`, `:foldl`, `:filter`,
`:map-adjacent`, `:scan`, `:scan-pair`, `:shift-seq`, `:seq-corr`, `:best-shift`, `:argmax-corr`,
`:last-or` and `:solve-shift-seq-by-correlation`. Commit `b3af2e6` ("step 2 of batteries
+reflectivity done") deleted them together with `batteries.lisp` (232 lines) and
`bootstrap-inverters.lisp` (292 lines), in a change of +4,086 / -1,651 lines across the kernel;
`42ffb1b` added `build-batteries.lisp` (896 lines). In that commit the recursion skeletons lived
inside the kernel: `79e6966` / `708cb3b` then moved 324 lines out of `decompose.lisp` into
`bootstrap/recursion-schemas.lisp`. **VERIFIED** (`git show --stat`).

Comparing bodies: the bootstrapped entries are the hand-written ones up to argument order in 20 of
21 cases, including `:best-shift`'s embedded lambda `(if (< here (at best 0)) best (tuple here
place))` and `:shift-seq`'s `(concat (cons (shift-seq (tail xs) (- k 1)) '((0))))`. The exception is
the guard of `:solve-shift-seq-by-correlation` (section 2.3). `:filter`'s base case is `xs` rather
than `()`.

So the bootstrap as built is a re-derivation of a known target under specs tuned until the target
came out. The comments "Synthesize ... de novo from pure `:spec`s!" (`build-batteries.lisp:608`) and
"Synthesize the 6 first-order recursive list functions de novo and discover `:map` & `:foldr`!"
(`:549`) are accurate for the second and an over-claim for the first.

### 3.6 Curriculum order

The order is the literal sequence of calls at `build-batteries.lisp:939-947` and, inside each
builder, the order of statements. No kernel component chooses what to learn next. The dependencies
the order encodes:

- arithmetic after algebra (loads `algebra.sexp` for the axioms, `:185-187`);
- seeds, then anti-unification, then `:foldl`, `:filter`, `:map-adjacent`, `:positions`, then
  `:solve-at-1` (needs `:filter` and `:positions`), then the template (needs `:map`, `:filter`), then
  the motif (reloads `algebra.sexp`, needs `:foldr`, `:foldl`), then the descriptor harvest;
- `:shift-seq`, `:seq-corr`, then `:best-shift` (whitelists `:seq-corr`), then `:argmax-corr`
  (whitelists `:best-shift`), `:last-or`, then the solver (whitelists `:argmax-corr`).

Every use of an earlier library function by a later synthesized one is put there by the author as a
whitelisted operator. None of `:foldl`, `:filter`, `:map-adjacent`, `:positions`, `:scan`,
`:shift-seq`, `:seq-corr`, `:last-or` calls `:map` or `:foldr`; each is written by direct recursion.
The bootstrap never calls `consolidate-knowledge-library`; it calls the individual stages by hand in
a chosen order. **VERIFIED** (`grep` in `bootstrap/`).

---

## 4. `recursion-schemas.lisp` (question 3)

### 4.1 What it encodes

Its own header is accurate: "Recursion schemas the battery curriculum is given, not ones the kernel
finds" and "Each is the shape of one battery function ... written by hand"
(`recursion-schemas.lisp:2`, `:8-9`). It is an `:expand` function
(`recursion-schema-expander`, `:332-355`) that, for a recursive job at a node whose frame has an
empty-sequence row, proposes up to five program skeletons with one hole:

| Skeleton | Lines | Shape | Written for |
| :-- | :-- | :-- | :-- |
| lookahead | 79-137 | `(if (= xs ()) base0 (if (= (tail xs) ()) base1 Z))`; the hole sees `(at xs 0)`, `(at (tail xs) 0)` and `self(tail xs)` | `:map-adjacent`, `:last-or` |
| state fold | 161-176 | `(if (= xs ()) s (self (tail xs) Z ...))` | `:foldl` |
| state scan | 177-194 | `(if (= xs ()) () (cons Z (self (tail xs) Z ...)))` | `:scan` |
| countdown | 195-256 | `(if (= xs ()) base (if (< 0 k) Z base'))` with `self(tail xs, k-1)` in scope | `:shift-seq` |
| counter | 257-330 | `(if (= xs ()) base Z)` with `self(tail xs, k+1)` in scope | `:positions`, `:best-shift` |

Each carries task-shaped detail beyond the shape:

- the lookahead skeleton admits equal base cases only when the language holds a two-argument
  `:code-eval` over the element type (`:103-113`), which is `:map-adjacent`'s signature;
- the countdown skeleton removes `<` and `-` from the hole's language (`:238-241`);
- the counter skeleton puts into scope every call of a defined all-sequence function on the inputs
  (`:265-281`), which is `(seq-corr xs ys)` for `:best-shift`, and the tuple projections of the
  recursive result (`:282-288`);
- `candidate-inductive-bases` (`:16-42`) proposes base cases including tuples of defaults and
  inputs, which is `:best-shift`'s `(tuple 0 index)`;
- fixed policy scores +4, +4, +3, -4, -2.

### 4.2 Which entries need it

My runs start each spec from a clean library with its curriculum prerequisites loaded from the
battery (`budget-scaling.lisp`). **VERIFIED.** Whitelist kept, schemas off:

| Spec | 350k | 3.5M | 35M | 350M | Nodes at the end |
| :-- | :-- | :-- | :-- | :-- | --: |
| `:foldl` | impostor at 120,163 (passes all rows, wrong on `2a-b`) | same | | | 3 |
| `:filter` | sound, 74,878 | | | | 3 |
| `:map-adjacent` | no | no | no | no | 2 |
| `:positions` | no | no | no | no | 2 |
| `:scan` | no | no | no | no, space exhausted at 321,768,109 | 2 |
| `:shift-seq` | no | no | no | no | 3 |
| `:seq-corr` | sound, 86,899 | | | | 4 |
| `:best-shift` | no | no | no | no | 2 |
| `:argmax-corr` | sound, 94,140 | | | | 5 |
| `:last-or` | sound, 49,757 | | | | 4 |

Rerunning the five failures at 35M with `:max-depth 4`, and again with the description bound raised
by 80 bits as well, changes nothing: still 2 or 3 nodes, still not found. In the failing jobs
93% to 96% of the work is `:child-search`, flat enumeration in the root and one conditional child;
for `:map-adjacent` the root alone takes 3.34M of 3.5M.

So six entries need the schemas (five do not appear at any budget tried; `:foldl` comes out wrong),
`:last-or` uses one but does not need it, and `:scan-pair` inherits `:scan`'s.

Check of `v2/STAGE0_RESULTS.md` section E0b-2 against the code and a rerun:

- The table reproduces (5.6 s). Small differences in a few work numbers (for example `:argmax-corr`
  99,180 against the document's 98,921) suggest the code moved slightly after the document.
- **`:argmax-corr` "FAIL (51,825)" without schemas is a harness artifact.** In that sequential regime
  `:best-shift` has already failed and is left defined as an oracle-only stub, so the guard
  `(not (defined-function-p :best-shift))` at `stage0-audit.lisp:199` is false and the real
  `:best-shift` is not loaded. `:argmax-corr` is a non-recursive job, for which the expander returns
  nothing anyway (`recursion-schemas.lisp:338-340`). With `:best-shift` present it solves at 94,140
  without schemas.
- **The "Active Grammar" columns conflate two things.** `active-library-spec-operators`
  (`consolidate.lisp:1213-1246`) adds every active library function, and in the audit's sequential
  regime that includes all earlier specs' results. With only `:map` and `:foldr` loaded, `:seq-corr`
  under the active grammar is sound at 100,091 and `:best-shift` (active + schemas) at 200,581; the
  document lists both as TIMEOUT. Section 6.3 measures the effect directly.
- With those two corrections my held-out-sound counts are 16/16, 10/16, 11/16 and 9/16 for the four
  regimes, against the document's 16/16, 9/16, 9/16 and 8/16. The conclusion stands; the document
  slightly overstates the damage.
- "TIMEOUT (350,000)" in that table means "not found in about 0.08 s". The document does not test
  larger budgets. I did, and for these five it makes no difference.

One more data point on plain enumeration, **VERIFIED** (`budget-argmax-active.out`).
`:argmax-corr` is the only bootstrap answer found by enumeration alone: 8 atoms, 53 bits, 22,229
enumeration units with its 2-operator whitelist. With the generic grammar instead (about 16
primitives plus the 4 loaded library functions) the 53-bit answer is not found at 350k, 3.5M or 35M.
Given 350M, the job stops at 57,664,468 work with a **280-bit impostor** built on `:foldr` that fits
the spec's 3 rows and fails the held-out case. So fourteen-odd extra operators cost more than a
2,500x increase in work on an 8-atom target, and a 3-row spec then accepts the first thing that
fits.

---

## 5. Reflection as built (question 4)

### 5.1 What is recorded

A job pushes a `message` struct of `call-id`, `claim`, `evidence` (`enumerate.lisp:237`) through
`synthesis-message` (`synthesize.lisp:115-132`), which adds parent ID, proposal name, description
limit and job work so far. Claims sent by the synthesis controller: `:prepared` (`:925`),
`:expanded` (`:1108`), `:child-candidate` (`:756`), `:candidate` and `:rejected` (`:1273-1275`),
`:conflict` (`:843`), `:subproblem-reused` (`:857`), `:cegar-refinement` (`:1217`),
`:bounded-exhaustion` / `:cutoff` (`:1309`, `:1341`), plus noted events, of which there is one call
site: `:stage-a` from `condense-heuristic` (`condense.lisp:42`), carrying the history of buckets and
models found and the work at which each was found.

Granularity: one message per node event and per Stage A search. Not recorded as messages: individual
enumerated candidates, individual evaluations, and the scheduler's lane choices, which go to a
separate `synthesis-job-trace` list (`synthesize.lisp:1062-1070`) that `messages.lisp:8-9` says it
does not read. A bootstrap job produces 6 to 21 messages.

### 5.2 Who reads it

`messages.lisp` (128 lines) defines five readers, `:node`, `:stage-a`, `:stage-a-bucket`,
`:stage-a-model`, `:verified` (`:88-128`), covering three claims (`:prepared`, `:stage-a`,
`:candidate`) and projecting only `:int` and `:bool` columns; `message-rows` (`:43-58`); and
`message-frame` (`:60-81`), which makes an ordinary frame from rows.

Readers of those functions outside `messages.lisp`: `tests/messages.lisp` and
`experiments/yield-gate.lisp`. **No kernel module calls `message-rows`, `message-frame` or
`define-message-reader`.** **VERIFIED** by `grep` over `v2/*.lisp`, `v2/milestones`, `v2/bootstrap`.

The kernel's own uses of `synthesis-job-messages` are three lookups of which node owns a verified
candidate (`consolidate.lisp:37-40`, `:362-371`; `proposals.lisp:1597-1600`).

`explain.lisp` (145 lines) builds plists and prints text for a job, a node or the library. It has no
kernel caller; six test call sites check that a report string is non-empty. It is a channel to a
human or an agent, not to the kernel. **VERIFIED.**

### 5.3 `batteries-and-reflection.md`: promised against built

| Promise | Lines | Status |
| :-- | :-- | :-- |
| Heterogeneous tuple projection in `:at` | 52-57 | Built; `tests/messages.lisp:149-213` |
| `:necessity` obligation on solvers | 59-67 | Built for finite types only (`consolidate.lisp:1546`); all three `:cons` solvers and all eight integer solvers record `:necessary-p nil` |
| `instantiate-entry-template` across kinds; batteries as plain `.sexp` | 69-71 | Built (`templates.lisp:421`); `batteries.lisp` retired |
| Rank-environment totality | 73-74 | Built; `tests/batteries.lisp:472` |
| `algebra.sexp`: field solvers certified on GF(5)/GF(7), lifted, with divisibility guards "sharper than hand-written" | 89 | Not as described. `algebra.sexp` holds 12 laws and no solvers. Integer solvers come from 3 to 6 integer rows; their guards equal the hand-written ones. `lift-field-solvers` exists (`consolidate.lisp:603`) and the bootstrap does not call it |
| `constructors.sexp` with `:necessity` and a `length` law, subsuming host `:cons` folds | 84, 90 | Partly. No `:necessity`, no `length` law. `STAGE0_RESULTS.md:58-62` shows the host folds are still needed for lifting |
| `functors.sexp`: "synthesized `:transformer` ASTs", retiring `bootstrap-inverters.lisp` | 83, 91 | The file was retired; 9 of 10 transformers are hand-built and called by ID from kernel source. The proof-of-concept figure "52,751 work (157 body-bits)" refers to a probe script outside the repository; I could not check it |
| `descriptors.sexp`: descriptors "discovered by observational/contrastive synthesis" | 92 | Host prototypes dumped to a file (section 2.3) |
| `metrics.sexp` with shift, product and moment metric decoders | 93 | Absent. One shift metric, in `sequence-shift.sexp` |
| `:spec` kind with replay | 97-101 | Built. Edge is `:specifies`, not `:verifies` |
| Specs replay automatically when an entry is instantiated at a new type; `propose-disambiguating-query` | 102, 145 | Not built. Replay happens only at default types (`consolidate.lisp:1930`); `tests/batteries.lisp:183-186` asserts that a wrong spec loads at another type. `propose-disambiguating-query` has no definition in `v2/` |
| A bootstrap regeneration test | 103 | Absent |
| Roadmap step 0, item 3: predictor adds a clamped residual instead of overwriting MDL | 37, 185 | Built (`synthesize.lisp:498-516`; `tests/audit.lisp:791`). I did not check the other five items |
| **Step 3**: `reify-search-frame`, branch and candidate trace frames, upward `:conserved` / `:regime-hit` / `:disambiguate` messages, job-wide feature pool, L0 to L3 scope lattice, `*reflective-depth*`, `(:reflect . scope)` agenda action, capped reflective quanta | 124-178, 190-191 | **Absent.** `grep` for `reify-search-frame`, `reflective-depth`, `:conserved`, `:regime-hit`, `(:reflect`, `:redundant` over `v2/*.lisp` returns nothing. What exists of step 3 is `note-event`, the five readers and `message-frame` |

Measured: the only measurement of reflection in the repository is `experiments/yield-gate.lisp`. I
ran it (3.6 s). It reads the Stage A rows of two jobs, labels each quantum "needed" or not in host
Lisp from the winning path (`yield-gate.lisp:110-127`), asks the kernel's conflict check whether
"needed" is a function of what a gate could read (it is not: conflict on every column set tried),
and has observation search propose gate expressions. The best sound one, `(< quantum buckets)`, would
have stopped 38,064 of 153,518 Stage A work units on those two jobs. The script states its own
limits (`:8-10`): the result is a suggestion from two searches and nothing is applied. It also shows
node 0 running Stage A twice in both jobs (2,120 then 10,000 work, no model either time).

### 5.4 Where a search decision depends on recorded history

**Within a job** (all host-coded, none learned):

- subproblem deduplication by frozen scope signature (`synthesize.lisp:885-904`, `:848-862`);
- UIP / DIP nogoods (`nogoods.lisp`), consulted at preparation (`nogoods.lisp:432-433`);
- node priority from the node's own Stage A model (`synthesize.lisp:498-516`).

In the 19 bootstrap jobs none of the first two fired: 0 nogoods, 0 reuses.

**Across jobs**, through the knowledge library:

- `:nogood-schema` and `:dip-feature` entries committed by `commit-synthesis-job`
  (`consolidate.lisp:297-330`) and checked by later jobs (`nogoods.lisp:310-324`);
- descriptor profiles that prune library candidates;
- **a learned priority predictor.** `make-search-trace-frame` (`consolidate.lisp:20-93`) turns the
  explored nodes of finished jobs into a frame of six integer features (program bits, residual bits,
  depth, constrained rows, policy score, coupled count) against a clamped residual;
  `condense-search-heuristic` (`:95-129`) induces a program over `{+,*,-}`; it is stored as a
  `:heuristic` entry (`:237-245`) and `node-priority` adds its output, clamped to [-24, 48], to the
  analytic MDL (`synthesize.lisp:515`). `consolidate-knowledge-library` does this whenever it is
  given jobs (`consolidate.lisp:1039-1048`). The predictor is read only when the job is given a
  knowledge library by name and runs the heuristic policy (`synthesize.lisp:183-186`).

This last is a real instance of what the owner asks for: a search policy term that is a VM program
learned from the kernel's own search records. Tests show it can be learned and deployed and that the
held-out task still solves (`tests/recursion.lisp:2206-2252`, `:2378-2410`). No test compares work
with and without it.

I ran it on the kernel's own curriculum (`predictor-loop.lisp`, **VERIFIED**): the 16 function
specs, in order, in one library. 57 nodes in total, 161 messages, 38,016 scheduler trace entries,
1,253,942 work. The trace frame has 42 rows; **40 of the 42 labels are 48, the clamp maximum**. The
condensed predictor is the literal `0` (58 program bits, 819 residual bits, 10,042 work to learn).
Rerunning the curriculum with it: 1,254,150 work, ratio 1.000.

Why the labels saturate: the label is `min(b+48, (winning score or b+24) + subtree_work/64) - b`
(`consolidate.lisp:76-79`), so any node whose subtree spent more than about 3,000 work units is
clamped to 48. Every node in these jobs did. **VERIFIED** from the frame; the arithmetic is read from
the code.

**Across sessions**: only through `save-knowledge-library`. `tests/library.lisp:348-450` serializes a
library holding a nogood schema, a DIP feature and a predictor, restores it, and checks a nogood is
reused. The committed batteries hold none of these kinds, and nothing writes messages or traces to
disk (`with-open-file` occurs only in `persistence.lisp:114`, `:124`, `consolidate.lisp:1735` and the
benchmark). **VERIFIED.**

---

## 6. What the library buys (question 5)

### 6.1 Evidence already in the tests

`tests/library.lisp:348-450` (L4) is a real compounding loop: synthesize `inc` and `add3` cold, call
`consolidate-knowledge-library` (which anti-unifies them into `:map`, builds descriptors, a functor,
an inverted solver and a predictor), serialize, deserialize, and synthesize warm. The test asserts
only `<`. I printed the numbers (`l4-numbers.lisp`, **VERIFIED**):

| Task | Cold work | Warm work | Change | Cold size | Warm size | Warm path |
| :-- | --: | --: | --: | --: | --: | :-- |
| `inc` | 18,090 | 15,948 | -12% | 122 bits | 54 bits | `:library` (map) |
| `shift4` | 20,076 | 16,687 | -17% | 126 | 58 | `:library` (map) |
| `add-len` | 40,155 | 37,823 | -6% | 161 | 161 | DIP repair, 1 reused nogood |

Consolidation cost 42,717 work; the three warm runs save 7,863 between them. The learned predictor in
that run is the single feature `X1` (residual bits). So the loop works end to end and its measured
margin at this scale is 6% to 17% of work and about 2.2x of description size.

`STAGE0_RESULTS.md:58` gives one more: a `:map` lift solved in 7,139 work against about 33,000 for
the same function by recursion. I reproduced the 7,139.

### 6.2 A held-out experiment

`library-value.lisp`, **VERIFIED**. Eight tasks that are not in the curriculum, all `(:seq :int)` to
`(:seq :int)` or `:int`. The same primitive grammar (`cons tail at = if + * - <`, literals `0 1 2`)
in every regime; bound 130, depth 2, as in the bootstrap. Regimes: kernel alone; kernel plus
recursion schemas; all eight batteries loaded with the six combinators added as plain operators;
batteries loaded with library lifting proposals on (`:library-proposals-p t`). Work to the first
verified candidate, budget 35M:

| Task | Kernel alone | + schemas | Library as operators | Library, lifting proposals | Found via |
| :-- | --: | --: | --: | --: | :-- |
| `add2-all` | 115,271 | 117,288 | 147,488 | **35,787** | `:map` |
| `run-sum` (prefix sums) | no at 35M | no | no | **38,130** | `:scan` |
| `diffs` (adjacent differences) | no at 35M | no | no | **42,237** | `:map-adjacent` |
| `last` (rows not suffix-closed) | no at 35M | no | no | **25,463** | `:foldl` |
| `last` (suffix-closed rows) | 129,622 | 76,617 | 131,679 | **28,698** | `:foldl` |
| `sum-sq` | **78,282** | 81,873 | 79,186 | 169,292 | `:foldr` |
| `count-pos` | **139,035** | 142,460 | 140,697 | 236,977 | `:foldr` |
| `sq-pos` (filter then map) | **105,860** | 107,643 | 123,222 | 245,168 | recursion; library unused |
| `pos-only` | **81,392** | 83,368 | 83,434 | 240,245 | `:filter` |

- **Reach.** Three tasks the kernel alone does not solve at 35M are solved in 25k to 42k with lifting
  proposals: a factor over 800. These are the cases whose direct recursion needs a shape the kernel
  does not propose (threaded state, two-step lookahead) or examples it does not have.
- **Examples.** Lifting removes the need for trace-complete rows: `last` with rows that are not
  suffix-closed is unreachable for the recursive search and trivial through `:foldl`.
- **Cost.** Where direct recursion is found anyway, lifting proposals make it 1.7x to 3x more
  expensive, because the proposals compete for the budget. A non-recursive job with lifting
  (`start-heuristic-synthesis`) is cheaper on `sum-sq` (45,839) and dearer on `count-pos` (982,829).
- **Size.** Library answers are 45 to 85 bits against 123 to 199.
- `sq-pos` shows the `:comprehension/filter-map` template not firing in a recursive job. The
  non-recursive job finds a 100-bit answer at 923,132 that is worth noting: `:foldr` retyped by the
  kernel to a sequence-valued state, `(foldr xs () (if (< 0 x) (cons (* x x) acc) acc))`, a filter
  and a map in one fold.
- `pos-only` through `:filter` returns `x >= 0` where recursion returned `x > 0`. My training rows
  contain no zero, so both fit; my held-out row has one. This is my spec's ambiguity, not a kernel
  fault, and I do not count it against the library.
- **Library as plain operators never used a library function** and never solved what the kernel
  alone did not.

The last point matters because it is how the bootstrap consumes its own library.
`synthesize-spec-entry` calls `start-recursive-synthesis` without `:library`
(`consolidate.lisp:1275-1279`), and that function's default is
`(library-proposals-p (not (null library)))` (`decompose.lisp:770`; root `decompose.lisp:704`). So
**lifting proposals are off for the 15 recursive function jobs of the bootstrap.** The one
non-recursive job, `:argmax-corr`, goes through `start-heuristic-synthesis`, whose expander defaults
them on (`proposals.lisp:1035`), but its answer came from root enumeration. The one bootstrap job
whose winning path is `:library` is the `:solve-at-1` witness, where the author passed
`:library-functions '(:filter)` explicitly. **VERIFIED** from the instrumented winning paths.

### 6.3 Library growth as a flat grammar

`grammar-growth.lisp`, **VERIFIED**. The same spec under the "active grammar", as functions are added
to the loaded library:

| Spec | Empty | `:map`, `:foldr` | sequences battery | + scans + six first-order seed stand-ins |
| :-- | --: | --: | --: | --: |
| `:seq-corr` | 100,058 | 100,091 | 100,091 | 664,209 |
| `:filter` | 118,580 | 118,681 | 118,814 | 119,209 |
| `:last-or` | 160,394 | 160,462 | 160,679 | 161,050 |

Mostly neutral, and 6.6x worse for `:seq-corr` once functions whose type fits the hole are in the
grammar. The seed stand-ins have dummy bodies, so this measures type-compatible operators in the
grammar, not those particular functions. **INFERRED** that this is what turns `:seq-corr` into a
TIMEOUT in the Stage 0 table.

### 6.4 Do entries sit unused?

Inside the library: `:best-shift` calls `:seq-corr`; `:argmax-corr` calls `:best-shift`; the shift
solver calls `:argmax-corr` and `:shift-seq`; `:solve-at-1` calls `:filter` and `:positions`; the
template calls `:map` and `:filter`; the motif names `:foldr` and `:foldl`. Not called by any entry:
`:map-adjacent`, `:scan`, `:scan-pair`, `:last-or`. Recorded `:gain` is 0 for all 61 entries, so the
library itself holds no evidence of amortization. `:foldr`'s MDL gain from the seeds is 0 bits after
naming (`:map`'s is 94), and with two seeds per signature instead of three `:foldr` is not accepted
at all (`au-robust.lisp`, **VERIFIED**).

Use by the test suite and kernel: batteries are loaded in six test files (`load-battery` occurs 37
times in `tests/batteries.lisp`), the transformers are called by kernel source, and in `v2` (Stage 1
work in progress) `proposals.lisp:275-380` hard-codes the covers `(map (positions xs 0) W)` and
`(filter (positions xs 0) W)` by library entry name. The root kernel does not have those lines.

Summary for this question: the mechanism compounds, strongly on tasks that need a recursion shape
the kernel lacks. The bootstrapped library as produced does not demonstrate it, because its own
construction never lifts through an earlier entry.

---

## 7. What is sound and worth keeping (question 7)

Each of these is **VERIFIED** by a test I read, and where noted by a run.

- **Spec replay on load.** `load-battery` replays every attached `:spec` on the VM at default types
  (`consolidate.lisp:1930-1936`); for a solver it also runs the witness forward through the operator
  (`:1199-1206`). `tests/batteries.lisp:28-64`.
- **Refusal.** A packet whose spec row is wrong does not load; a corrupted return type fails
  deserialization; an entry is not loaded without the functions it calls
  (`tests/batteries.lisp:122-207`; dependency check `consolidate.lisp:1894-1908`).
- **Certificates are recomputed, never trusted.** A solver over finite types is re-certified on load
  and at each type instantiation; a packet that over-claims uniqueness has the claim withdrawn
  (`tests/batteries.lisp:208-226`; `consolidate.lisp:1801-1816`; `templates.lisp:421-426`).
- **Evidence grades are honest.** Integer solvers load as `:conjecture`, narrow with a fallback kept,
  and record `:trusted-axiom` where an axiom is the only ground (`tests/batteries.lisp:65-110`). In
  the library, 8 entries carry a `:trusted-axiom` certificate (the 4 axioms and the 4 solvers whose
  uniqueness rests on them), 12 a `:sampled` one, and nothing over an infinite type claims more.
- **Persistence fixed point.** Serialize, deserialize, serialize gives equal entries
  (`tests/batteries.lisp:57-64`), with signatures declared before bodies so forward and mutual
  references load (`persistence.lisp:86-95`). `*read-eval*` is bound to nil when reading a battery
  (`consolidate.lisp:1737`).
- **Deterministic, metered regeneration.** Five bootstrap runs across the two kernels gave
  byte-identical packets, and per-job work was identical between repeated runs of one kernel (the
  two kernels differ by 33 work units in one battery). Stepping a job one unit at a time or in a batch gives the same
  messages (`tests/messages.lisp:81-119`).
- **Type parameters.** One packet stated at `?a = :int` instantiates at GF(5) with renamed self-calls
  (`tests/batteries.lisp:112-120`).
- **`discover-library-abstractions`.** Generic, MDL-gated, and the one bootstrap result that survives
  ablation: with the full generic grammar and no schemas, all six seeds still solve (393,075 work
  against 165,602) and the same `:map` and `:foldr` bodies come out (`au-robust.lisp`).
- **Library lifting through `:code` holes** (`library-decompositions`, `proposals.lisp:153`): the
  mechanism behind every gain in section 6.2.
- **`message-frame`**: 22 lines that make a table of kernel-typed values into an ordinary frame. As
  far as it goes it is the right primitive; it has no producer inside the kernel and no consumer.
- **The Stage 0 audit harness** (`stage0-audit.lisp`): the ablation switches
  `*use-active-library-grammar*`, `*enable-host-cons-folds*`, `*enable-host-descriptor-synthesis*`
  and the held-out impostor checks are the right kind of instrument. Its two flaws are in section
  4.2.

Weaker than they look:

- Specs do not replay at non-default types (`consolidate.lisp:1930`; asserted as behavior at
  `tests/batteries.lisp:183-186`).
- A spec with one row, as six of the transformer specs and `:spec/scan-pair` have, verifies very
  little. `:spec/foldl` admits three different wrong programs once any help is removed
  (`STAGE0_RESULTS.md:102-119`; reproduced).

---

## 8. Comparison with `plan_v2.tex` lines 264-290

Read only after my counts were fixed.

| Their claim | Mine | Verdict |
| :-- | :-- | :-- |
| 8,884 AST bits in the eight packets | 8,884 | Agree exactly |
| "52 operational entries"; the 61 of `plan_v2b` "includ[es] 9 `:functor` markers" | 61 operational entries; no entry of kind `:functor` in any packet. Kinds: 15 law, 13 solver, 13 function, 10 transformer, 8 descriptor, 1 template, 1 motif | **Disagree.** The denominator is 61 |
| Their four buckets, 2 + 21 + 10 + 19 = 52 | Their own list for the fourth bucket (9 transformers, 4 axioms, 3 cons laws, the template, 8 descriptors, `:solve-at-1`) has 26 members, not 19 | **Internally inconsistent** |
| "Only 2 of 52 ... arise from unassisted synthesis plus library anti-unification": `:map`, `:foldr` | `:map` and `:foldr` are the result most robust to removing help, which I confirmed. But their seeds do use curated grammars and exact literal lists in the bootstrap as written, and the 8 arithmetic solver witnesses use no per-spec grammar at all | Agree in spirit; I would say 3 entries by generic derivation and 8 by generic search, 11 of 61, 8.3% of bits |
| "Prosthetic synthesis via `recursion-schemas.lisp` (21/52)" | 7 entries have a schema on the winning path, 6 need one, 1 more inherits. The 11 solvers induced by `induce-conditional-solver` use `start-search` with no expander | **Disagree on the count**; 21 appears to lump in whitelisted solver induction |
| Without schemas, `:positions`, `:scan`, `:map-adjacent`, `:shift-seq`, `:best-shift` fail at 20M | Fail at 350M | Agree, and stronger |
| Without schemas `:foldl` and `:last-or` "return wrong functions" | `:foldl` yes. `:last-or` is sound without schemas on the audit's own held-out case (49,757), as `STAGE0_RESULTS.md:98` also says | **Disagree on `:last-or`**, at least for that held-out case |
| "9/11 function specs supply exclusively the answer's operators" | 9 of 10 by operator name | Roughly agree |
| "Whitelisted micro-grammar laws (10/52)"; 1,753 valid laws over GF(3)^3 with `+` | 8 laws from four micro-grammars; at the bootstrap's own budgets the four searches propose 187 laws and the shape filter keeps 14 | Disagree on 10; their 1,753 is presumably at a larger budget, not checked |
| Hand-authored: 57% of bits (5,061) | 5,061 = transformers + axioms + cons laws + template. Adding `:solve-at-1` gives 5,254 (59.1%); adding host-stamped descriptors and motif, 5,795 (65.2%) | Agree; mine is slightly higher by classification |
| 9/10 transformers, 4,728 bits, `:work 0` | Same | Agree |
| Defect 8: Stage A runs twice on node 0 | Reproduced by `yield-gate.lisp` | Agree |
| Defect 10: `messages.lisp` projects only scalar `:int` / `:bool` columns with zero kernel readers | Same. `message-frame` itself can carry tuple and code columns (`tests/messages.lisp:196-213`); the five readers do not | Agree |

---

## 9. Where the evidence goes against the owner's hypotheses

- **"Budgets were tiny" is true and is not the main obstacle for recursion.** The budgets are tiny
  by any measure (section 1). But five of the six schema-dependent functions are not found at 1,000x
  the budget, and one job exhausts its space. The missing thing is a general proposal for a self-call
  with synthesized arguments, which is what the header of `recursion-schemas.lisp:10-12` says. For
  law discovery, by contrast, 10x budget did replace an author's grammar split.
- **"Underwhelmed with the quantity of information ... abstracted to the library"** is supported: 2.5%
  of bits from generic search, 59% hand-authored, all `:gain 0`.
- **The library is not inert.** Lifting through library combinators gives over 800x reach on three
  held-out tasks, and removes the need for trace-complete examples. The bootstrap does not use it.
- **Reflection is not entirely absent.** A trace-to-policy loop exists and is wired into
  `node-priority`. It is ineffective on the curriculum for two concrete reasons: saturated labels and
  search graphs of 1 to 5 nodes. With graphs that small there is nothing for a learned policy to
  reorder, whatever the representation. That is a property of how little search the bootstrap does,
  not only of the reflection code.
- **"Nothing very interesting was findable ... with rigid enumeration"** is supported directly: the
  largest enumerated expression in the bootstrap is 8 atoms, and in failing jobs 93% or more of work is
  flat enumeration in one or two nodes while the graph does not grow.

---

## 10. Not determined

- The proof-of-concept claim in `batteries-and-reflection.md:83` (a functorial inverter synthesized
  in 52,751 work): its probe script is outside the repository.
- Whether budgets well beyond 350M (hours) would find the five schema-dependent functions. `:scan`'s
  space is exhausted, so not for `:scan` at these bounds; for the other four the trend (graph fixed
  at 2 to 3 nodes, all work in flat enumeration of 130 to 255 bit targets) makes it unlikely, but I
  ran at most about a minute each.
- Five of the six "step 0" bug fixes in `batteries-and-reflection.md:35-40`.
- Whether root `make test` passes from a clean checkout without `make bootstrap` (section 1).
- `plan_v2.tex`'s figure of 1,753 laws over GF(3)^3.
- The seed stand-ins in section 6.3 are dummies; I did not rerun with the real seed bodies.

### Housekeeping: a stray `library/` in the real repository

`git status` in `/home/tlh24/lisploop` now shows an untracked `library/` that was not there at the
start of the session. Its eight files were written between 20:10:50 and 20:10:51 local time and are
byte-identical to `v2/library/*.sexp`. **I did not create it**: every bootstrap I ran printed output
paths under my scratch tree (`boot-v2.out`, `boot-root.out`), and my instrumented runs write to
`out-library/` and `out-library2/` in my scratch directory. The one-second span of the timestamps
matches a root-kernel bootstrap run from the real root, so another process ran
`bootstrap/build-batteries.lisp` (or evaluated its forms with the repository path as load truename)
there. I left it untouched. Two consequences: the repository is no longer in its starting state, and
root `tests/batteries.lisp` will now find its batteries, which hides the "root needs `make
bootstrap` first" condition noted in section 1.

---

## 11. Scripts and outputs

All under
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/bootstrap-reflection/`.
`tree/` is the scratch copy of the repository.

| Script | Output | What it shows |
| :-- | :-- | :-- |
| `run-bootstrap.sh` | `boot-v2.out`, `boot-root.out` | cold bootstrap, wall time, byte comparison |
| `instrumented-bootstrap.lisp` | `instr-v2.out`, `instr-root.out` | per-battery work, per-job nodes / messages / nogoods / winning path |
| `list-entries.lisp`, `pretty-entries.lisp` | `entries.txt`, `pretty.txt` | every entry: kind, bits, work, status, expression |
| `leaf-bits.lisp` | (stdout) | answer bits against leaf bits per job |
| `spec-budget.lisp` | (stdout) | rows, example bits, whitelist, distractors per spec |
| `law-filter.lisp` | (stdout) | laws proposed against laws kept; combined-grammar budget test |
| `run-stage0.sh` | `stage0.out` | reproduction of the Stage 0 audit |
| `budget-scaling.lisp` | `budget-3.5M.out`, `budget-350M-wl-off.out`, `budget-35M-deep.out`, `budget-argmax-active.out` | ablations at 350k to 350M, depth and bound variants |
| `trace-ablation.lisp`, `trace-ablation-foldl.lisp` | `trace-ablation.out` | trace-complete rows against black-box rows |
| `au-robust.lisp` | (stdout) | `:map` / `:foldr` without whitelist or schemas; seed-count sensitivity |
| `library-value.lisp`, `library-value-b.lisp` | `library-value-350k.out`, `library-value-35M.out` | held-out tasks with and without the library |
| `grammar-growth.lisp` | (stdout) | cost as the flat grammar grows |
| `predictor-loop.lisp` | (stdout) | learned priority predictor on the curriculum |
| `l4-numbers.lisp` | (stdout) | cold and warm numbers of the L4 test |
| (repo script, run in scratch) | `yield-gate.out` | the yield-gate experiment |
