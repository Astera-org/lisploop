# docs-v2tex — risk audit of `plan_v2.tex` (v2.1 → v2.4), `v2/STAGE0_RESULTS.md`, and the Stage 1 WIP

Auditor: `docs-v2tex`. Repository treated read-only; every run below was made in scratch copies
(`.../scratchpad/docs-v2tex/copy_stage0` = `git archive 397499a v2`, `.../copy_head` = `v2/` at HEAD,
which is byte-identical to `a4e19fa` for `v2/`).

Tags: **VERIFIED** (I checked it against code or re-ran it), **WRONG**, **UNCHECKED**, **AS-CLAIMED** (literature),
**PROJECTION** (a number that is a forecast, not a measurement). "MINE" marks a measurement I made that the plan does not contain.

Line references `plan_v2.tex:N` are to the working-tree file (v2.4, 922 lines). Older versions are cited by commit:
v2.1 = `4043a8e`, v2.2 = `faf8909`, v2.3 = `dbd3347`/`551f106`, v2.4 = `a4e19fa`.

---

## 0. Headline findings

1. **Four major versions in four hours.** `git log --follow -- plan_v2.tex`: v2.1 at 18:16 and 18:22, v2.2 at 19:48,
   v2.3 at 20:58 and 21:12, v2.4 at 22:18, all on 2026-11-21. Each "audit pass" found fatal flaws in a predecessor
   that had been presented in the same confident register. The document's PDF author field is
   "Antigravity Synthesis Audit and Architecture Specification" (`plan_v2.tex:53`): plan and audits are by the same
   agent toolchain. The three passes are self-audits, not independent review.
2. **Roughly half of the critical path is academic import or novel invention.** Of 40 mechanisms the Stage 1–2 gates
   depend on, I classify 6 as working here (K), 13 as standard (S), 7 as academic import (A) and 14 as speculative or
   invented in the plan itself (X). Every Stage 1 gate (E1–E5) depends on at least one A/X item; E5 depends on four (§2).
3. **The Stage 1 WIP is not working in the sense that matters.** MINE:
   - `v2` kernel tests: 228 tests, 938,281 checks pass (6.5 s); milestones 40 tests, 186,771 checks pass. These are
     exactly the Stage 0 counts. The WIP added +1,393/−167 lines and **zero tests** (`git diff --stat 397499a a4e19fa -- v2/`
     touches no file under `v2/tests/`).
   - `(app (op :tabulate :int) n F)` with `F` a code *variable* or a partial body **crashes at AST construction**:
     `tabulate-code-total-under-p` (`v2/ast.lisp:1096`) builds `(var -1 :int)`, which violates the assertion in
     `pooled-leaf` (`v2/ast.lisp:673`). `gather-indices-in-bounds-p` does the same with `(var -2 :int)`
     (`v2/ast.lisp:1144`). That is the exact shape every synthesis proposal for `:tabulate` constructs
     (`v2/proposals.lisp:309`), so the flagship opcode cannot be used for synthesis.
   - Ten symbols for E3 (`mini-egraph`, `egraph-*`, `ac-canonicalize-expr`, `minimize-laws-with-egraph`,
     `certify-law-by-pit`, `certify-law-by-induction`, `totalize-forward-replay`) are exported in
     `v2/package.lisp:66–69` and **defined nowhere**. `op-props` is one unused slot (`v2/knowledge.lisp:119`).
   - The E2 machinery (behaviour pruning, bottom-up column evaluation, effective horizon) is behind three flags that
     **no caller sets** (`grep` over `v2/` finds no `:columnar-p t`, `:prune-behaviors-p t`, `:effective-horizon-p t`).
   - Re-running the Stage 0 survival audit on the WIP gives **the identical solved/unsolved pattern on all 64 runs**
     (work drifts by under 0.3%). The WIP fixes none of the six timeouts Stage 0 named as its target
     (`v2/STAGE0_RESULTS.md:127`).
   - Complexity moved the wrong way against the plan's own ratchet: pure-kernel `cccc` cognitive 6,515 (v1) → 6,658
     (Stage 0) → **7,431** (WIP); LOC of the 25 modules 17,647 → 17,879 → **19,105**.
4. **Two cheap experiments, which the plan never ran, are more informative than the plan.** MINE:
   - *Behaviour pruning works and is already coded.* Turning the dormant flags on by hand, on the kernel's own
     benchmark: `quartic 77` work 29,382,492 → 248,113 (118×), candidates 106,057 → 670, same 77-bit answer;
     `quadratic 70` 2,687,984 → 97,846 (27×); `linear 61` 182,181 → 17,168 (11×). Column evaluation alone cuts
     tariff 2.6–3.2× but is *slower in wall-clock* (0.65 s → 1.02 s on `quartic 77`) because cells are boxed lists.
   - *Budget alone saturates quickly.* The Stage 0 audit runs all 64 syntheses in 2 s at its 350k cap (about 60 ms
     of search per spec). Raising the cap 10× lifts no-prosthetics survival from 9/16 to 11/16 (8 → 10 held-out
     sound). Raising it a further 10× (35M per spec) changes **nothing**. At 1000× (350M per spec, about a minute
     each) one more spec "solves", as an impostor: held-out-sound survival stays at 10/16 (§7).
5. **The geometry dialog ends in a deferral, not an answer.** Across versions the geometric layer went
   VSA bus → SGD attention router → closed-form SVD → nothing but a Naive Bayes feature index and an empty `address`
   slot "for Stage 3 once |L| ≫ 500" (the library has 52–61 entries). Spaces are still made, but only as tables of
   rows. No surviving mechanism collapses two spaces on evidence of symmetry or moves proximity along verified
   links (§4).
6. **What is solid** is small and mostly not from the literature: the Stage 0 fixes and audit harness, behaviour
   pruning, the totalized forward-replay guard (I verified the 12/33/57-bit claims), difference facts for index
   bounds, polynomial identity testing for ring laws, the gather pullback into preimage fibres, and the trap list
   in §3.

---

## 1. The v2.4 design in plain language

The plan says the kernel becomes "one Intro/Elim-symmetric prepaid VM and one monotone Columnar / Open-DAG Store
(~1,100 LOC clean core) driven by one external Anytime Controller" (`plan_v2.tex:615`). Stripped of vocabulary, it
proposes the following. LOC figures are the plan's (`plan_v2.tex:126–136`, Table 1), all PROJECTIONS.

| # | Plan's name | What it is | Job | Claimed LOC |
|---|---|---|---|---|
| 1 | `cstore` | One container for everything persistent and task-scoped. Never given a struct; only `cstore.op-props` and an "inverted table" are named (`:621`, `:624`, `:729`). | Stops state being private to a job (margin M2). | in 460 |
| 2 | `cbase`, "columnar base" (`:623`, `:687–693`) | A table of N rows ("sites") numbered 0..N−1. Columns are arrays, one per evaluated expression. "Structure maps" are integer arrays sending each row to a row of another table, −1 meaning undefined. | Replaces `frame` rows. A lift is a new table plus a map back to its parent. Holds the column cache, behaviour table and summary. | in 460 |
| 3 | "Slot-canonical open-DAG handle `ref = (cid, slot-map)`" (`:448`, `:624`, `:698–708`) | Expressions hash-consed as skeletons whose variable positions are numbered 0..k−1. A reference is (skeleton id, tuple of the actual variables). "Injective" means no variable appears twice in the tuple; if two slots get the same variable a new skeleton is interned. Packed into one fixnum for ≤5 variables with ids <64. | Share one node across scopes, so renumbering `X0→X1` on lift is cheap. O(1) description size from two cached integers. | in 460 |
| 4 | "Law-activated smart-constructor flags" (`:624`, `op-props`) | A per-operator flag set {`:assoc`, `:comm`, `(:id e)`, `(:cancel inv)`}, empty at start. When a law about an operator is certified the flag is set and the DAG constructor then flattens, sorts, drops units and cancels. | Collapse syntactic duplicates (12 spellings of `x0+x1+x2` to one) without hard-coding algebra. | in 460 |
| 5 | `behav-table` (`:625`, `:692`) | Per table: hash from (type, vector of outcomes on that table's rows) to the first expression with that behaviour. Timeouts excluded. Never shared across tables. | Enumerate one expression per behaviour instead of ~38. | in 460 |
| 6 | `ctx` (`:626`, `:711–715`) | (table id, bit-mask of active rows, list of difference facts). | A guard region: the rows where a branch applies, plus what is known there. | in 460 |
| 7 | `mini-egraph` (`:626`, `:718–721`) | Union-find, node table and parent lists, "<180 LOC", one instance per consolidation batch. | Throw away laws derivable from others; host for 1-step induction. | in 460 |
| 8 | `grule` (`:626`, `:724–731`) | One record for all knowledge: guard or trigger, typed ports with directional witnesses, evidence grades per obligation, Naive Bayes weights, optional address, net utility. Indexed by (head operator, child head operators). | Replace the 14 `define-knowledge-kind` silos. | in 460 |
| 9 | "Covers" and "Σ ⊣ Δ ⊣ Π + d\*" (`:512–516`, `:530–535`) | Names for four operations: Δ = re-index a column along a row map (lift); Σ = merge or quotient along the map; Π = require all rows in a fibre to agree; d\* = substitute the decoder into the requirement (the v1 pullback `B(Z)=A(d(X,Z))`). Five "cover geometries": container positions, guard regions, quotients, unordered collections, value residuals. | Vocabulary unifying index frames, guards, quotients and residual charts. | 150 |
| 10 | "Partition-of-unity selector", "top-8 witness mass", "first-appearance partition code" (`:413–417`, `:470–478`) | Three pricing rules. Price each root row once, by one selected patch. Score a candidate against a set of acceptable witnesses by the 8 nearest. Number latent class labels by order of first appearance. | Replace the sheaf residual and bits-back refund that Pass 1 struck down. | 45 |
| 11 | "Symmetric VM instruction set" (`:632–655`, Table 3) | Ten new opcodes: `:iota` (0..n−1), `:tabulate` (map over indices), `:where` (positions of a value), `:evolve` (scan with state), `:code-arity`, `:code-var`/`-var-id`, `:code-quote`/`-value`, `:code-anti-unify`. | Make index lift, state lift and anti-unification VM primitives rather than host code. | in 165 |
| 12 | "Generic memoized `:necessary` unfold" (`:659`) | Two fold rules: `(if C nil nil) → nil` when only necessity is required; memoize unfolding of `(= call literal)`. | Lift `:filter` and other branching recursions without 2^n case splits. | ~35 of 165 |
| 13 | "Parameter-varying recursion + DIP state promotion + CEGAR" (`:660`) | Propose self-calls with extra argument holes; widen state to a tuple when fibres are inconsistent; replay candidates on root rows and add counterexamples. | Delete `bootstrap/recursion-schemas.lisp` (355 LOC). | ~55 + ~40 |
| 14 | "Difference facts" `(:diff u v k)` (`:552–556`) | A short list of facts "u − v ≤ k" attached to the totality analysis. | Prove `0 ≤ i < length(xs)` for variable indices. | ~35 |
| 15 | "O(\|w\|) totalized forward-replay guards" (`:559`) | Wrap a solver's replay in the definedness guard of its witness: `(if (= k 0) nil (= (* (/ c k) k) c))`. | Derive conditional-solver guards with no search. | in 140 |
| 16 | PIT and 1-step induction (`:586–587`) | Certify `{+,−,×}` identities over ℤ by agreement on a small grid; prove sequence laws by one induction step in the mini e-graph. | Retire `:trusted-axiom`; certify `:int`/`:seq` laws. | 25 + 80 |
| 17 | "Bottom-up single-op column eval", "effective horizon c̃(op) ≤ 8", "two-phase lazy prep", "outcome hash-join" (`:371`, `:755–763`) | Evaluate only the root operator over cached child columns. Order enumeration with operator headers capped at 8 bits. Defer Stage A until a node is popped. Join two candidate pools by hashing outcomes. | Repair five measured budget cliffs. | in 140 |
| 18 | "Sparse millibit Naive Bayes", "O(N) summaries" (`:668–669`) | For each rule and feature an integer weight 1024·log2(P(win\|f)/P(win)), in an inverted index. Features are column summaries (`empty-p`, `const-p`, `monotone-sign`, `distinct-ratio`, parity), type constructors, probe hashes. | Decide which library rule or recognizer to try. The whole of v2.4's "geometry". | in 140, summaries ~25 |
| 19 | "4-bucket attribution", `(:probe …)`, `SearchTrace` (`:568`, `:596–608`) | Classify each rule's effect on a job as inert, generator of a losing subtree, pruner of a dead branch, or on the winning path; replay only for the last two. A metered experiment primitive in the meta grammar. Search events as a table with code-valued columns. | Reflection and utility accounting. | in 140 |
| 20 | Four-tier lowering (`:368–373`) | Step VM, closure tree, column closures, `cl:compile` at ≥50k evaluations. | Keep homoiconicity while approaching hardware speed. | — |
| 21 | Two-regime compute contract (`:770–773`) | Cold bootstrap may use 10^7–5×10^8 work per spec; warm tests ≤500k. Stage A budget scales with the job. | Stop curing 50 ms timeouts with whitelists. | policy |

Sum of the six subsystem estimates: 460 + 150 + 45 + 165 + 140 + 140 = 1,100.

Two observations for the synthesis:

- **There is no single small data structure.** The store is five structs plus `cstore`, `SearchTrace`, `op-props`, an
  inverted index, per-table behaviour tables, column caches and memo tables. The operations the owner wants uniform
  are spread over three layers: VM opcodes (evaluate), host fold rules in `requirements.lisp` (pull a requirement
  back through a lift), and host proposal generators (decide to lift). Only the first layer is "a synthesizer
  primitive".
- **"Hypergraph" is vocabulary.** The actual store is a rooted, hash-consed term DAG plus row tables. General
  hypergraph matching is explicitly avoided because it is NP-complete (`plan_v2.tex:314`, `:430`).

---

## 2. Risk classification

Classes: **K** working in this kernel and measured; **S** standard technique with mature implementations elsewhere;
**A** academic import with limited evidence at this scale or needing substantial adaptation; **X** speculative, novel,
or invented within the plan. "Critical path" = needed to pass the Stage 1 gates E1–E5 or the Stage 2 gate
(`plan_v2.tex:790–800`).

| # | Mechanism | Class | Justification | Gate |
|---|---|---|---|---|
| 1 | Columnar `cbase` tables | S | Arrays of columns are standard. Benefit here is unmeasured; my column-eval run shows the WIP's boxed version is slower in wall-clock. | E2, E6 |
| 2 | Hash-consed expression DAG | S | Standard. v1 pools leaves and caches metadata but stores trees. | E6 |
| 3 | Injective `(cid, slot-map)` handles, 61-bit packing | **X** | Invented in Pass 1 after rejecting Slotted and Zucker's thinning. No implementation anywhere. Canonical form modulo renaming *and* AC is not delivered: `f(a,b)+f(b,c)` and its renaming `f(x2,x0)+f(x0,x1)` sort to different skeletons when children are ordered by ambient variable ids (my analysis; the general problem is graph-isomorphism hard). Sound, but sharing silently fails. | E6 |
| 4 | Law-activated canonicalization flags | **X** | Novel. Flipping a flag changes normal forms, so every interned ref, behaviour key, memo and column cache must be re-canonicalized. Not addressed. Also unclear which representative's bits are charged. | E3 |
| 5 | `behav-table` (observational equivalence) | S, K-partial | Standard in bottom-up enumeration. Ratio 38:1 at 30 body bits measured in `plan_v2b.md:193`. MINE: 6–79× less work on the benchmark with the WIP pruning flag on, 11–118× with column evaluation as well. Changes "bounded exhaustion" into "exhaustion modulo behaviour on these rows". | E2 |
| 6 | `ctx` = row mask + facts | S | Guards as row subsets already exist. | E1 |
| 7 | `grule` unifying 14 knowledge kinds | **X** | Design conjecture. The 14 kinds have different operational semantics today (`plan_v2.tex:236`). | E6 |
| 8 | Two-level discrimination index for rules | S | Discrimination trees. Unmeasured here. | E3 |
| 9 | Batch mini e-graph for law minimization | **A** | Ruler does this with e-matching and bounded saturation. Congruence closure alone cannot derive an instance of a law from its schema, so "<180 LOC" and "O(α(N)) per candidate" are optimistic. | E3 |
| 10 | `:iota`, `:where` | S, K-smoke | Two lines each (`v2/vm.lisp:262–263`). MINE: evaluate correctly, codec round-trips. | E1 |
| 11 | `:tabulate`, `:evolve` as VM primitives | S as language features; **X** as synthesis lever | VM continuations work (MINE: `tabulate 4 j*j → (0 1 4 9)`, `evolve` gives running sums, pause and resume works). The AST layer crashes on unknown or partial bodies. The claim that they remove six timeouts (`v2/STAGE0_RESULTS.md:127`) is a prediction; MINE: zero change. | E1 |
| 12 | `:code-*` duals, `:code-anti-unify` | S/K wrappers; **X** as reflective lever | Thin wrappers. `:code-anti-unify` calls the host `anti-unify` (`v2/unify.lisp:75`) and errors unless the caller pre-declares a variable slot for each hole. MINE: smoke tests pass. Nothing uses them. | E1 |
| 13 | Gather pullback to preimage fibres | K | v1 has tuple slicing; `fold-equal-gather` (`v2/requirements.lisp:402`) works: MINE `(= (gather '(5 6 5) Z) '(5 6))` folds to `|Z|=2 ∧ Z[0]∈{0,2} ∧ Z[1]=1`. | E1 |
| 14 | Memoized `:necessary` unfold | K-partial | The `(if C nil nil)` rule is tested in Stage 0. The memo (`v2/requirements.lisp:276`) is untested. "40 DAG visits", "≤(\|xs\|+1)(\|ys\|+1) states" have no artifact. | E1 |
| 15 | Parameter-varying self-calls + DIP state promotion | **X** | The replacement for `recursion-schemas.lisp`. Stage 0 shows what removing schemas costs. No measurement that ~55 generic lines recover it. | E5 |
| 16 | CEGAR replay "instead of Burst" | **A** | Burst's guarantees come from its automata. A 40-line replay loop is a different algorithm with the same name on it. | E5 |
| 17 | Partition-of-unity cover pricing | S once de-jargonized | "Each row is priced by the branch its guard selects." | E6 |
| 18 | Top-8 witness log-sum-exp | **X** | The plan's own. v1 already takes the closest witness (`condense.lisp:232–240`). Binary search applies only to ordered scalars. Low value. | E6 |
| 19 | First-appearance partition code | S, K | Restricted-growth strings. `quotient-values` (`frame.lisp:1443`) already returns first-occurrence representatives. | E6 |
| 20 | Synthesized sort keys for unordered covers | **X** | No mechanism for finding the key. | E6 |
| 21 | Quotient or orbit covers along invariants | **X** | No mechanism for finding the invariant. `orient-conserved-quantity` has zero callers (`plan_v2.tex:284`). | E6 |
| 22 | Multi-stage residual peeling with MDL stop | **X** | Matching pursuit is standard for continuous signals. For program synthesis it needs recognizers that are themselves to be bootstrapped. In v1 residuals are "wiped on lift" (`plan_v2.tex:340`). | E6 |
| 23 | O(N) column summaries | S | Trivial. | E6 |
| 24 | Recognizers as *synthesized* library rules (correlation, differences, periodicity) | **X** | Central to worked trace 2 (`plan_v2.tex:737`). Today the one recognizer is hand-written and has no trigger (`:290`). `seq-corr`, `best-shift`, `argmax-corr` are among the specs that fail without whitelists. | E6 |
| 25 | Sparse millibit Naive Bayes trigger | **A** | Standard in premise selection with thousands of facts. Here \|L\| < 100 and tens of tasks; v1's priority predictor "collapsed to X0 on 11 examples" (v2.1, `4043a8e:plan_v2.tex:424`). | E6 |
| 26 | Certified range laws feeding totality (`mod` range, length preservation) | **X** | Needs the induction rule. The hooks `*mod-range-certified-p*`, `*certified-length-preserving-ops*` exist and are never set (`v2/ast.lisp:772–775`). | E1 |
| 27 | Difference facts | S, K-partial | Zone-style constraints without closure (two-step transitivity only: sound, incomplete). Implemented; old totality tests pass; MINE: `(at x0 (+ x1 x2))` is proved total under both guards and not without. | E1 |
| 28 | Totalized forward-replay guard | K (micro-claim), S | MINE: replay 33 body bits, guarded 57, witness 12; `provably-total-p` nil then T; exact divisibility on the −3..3 grid. Not wired into `consolidate.lisp:1473`. | E3 |
| 29 | PIT over ℤ[x] for `{+,−,×}` | S | Correct (a polynomial of degree ≤ d_r in each variable vanishing on a grid of d_r+1 points per variable is zero). Not implemented. | E3 |
| 30 | 1-step structural induction in the mini e-graph | **A** | TheSy-style, restricted. Needs rewriting with certified laws, which #9 does not yet supply. | E3 |
| 31 | Bottom-up single-op column evaluation | S | Standard. MINE: tariff 2.6–3.2× lower, wall-clock worse in the WIP representation. | E2 |
| 32 | Effective horizon c̃(op) ≤ 8 | **X** | Heuristic. Enumeration is no longer in description-length order: the WIP disables the invariant `size = scoped-bits` when the flag is on (`v2/enumerate.lisp:91`), so "first found is shortest" is lost, and so is "kept behaviour representative is shortest". | E2 |
| 33 | Two-phase lazy node preparation | S | Lazy expansion. Not implemented. | E2 |
| 34 | Behaviour-indexed coupled pools + outcome hash-join | **A/X** | A hash join needs a join key. For a general decoder `d(z1,z2)=y` that means inverting one argument. The key is never specified. | E5 |
| 35 | Bitset AC-3 on small value domains | S | Standard. | E5 |
| 36 | Stitch-style DAG anti-unification with "AC multiset diffing" and identity unrolling, to induce `functors.sexp` | **A + X** | Stitch is real and substantial. The AC and identity extensions are new. Nine of ten transformers are hand-written today (`plan_v2.tex:272`). | E5 |
| 37 | `SearchTrace` with code-valued columns | **X** | v1's `messages.lisp` has zero kernel readers; ablating reflective entries moves work by 0 (`plan_v2.tex:100`, `:285`). | E4 |
| 38 | `(:probe …)`: input slicing, disambiguating queries | **A** | Distinguishing inputs are standard (QuickSpec). The plan never says who answers the query when the data is a fixed set of rows. | E4 |
| 39 | 4-bucket attribution | **X** | Invented in Pass 1 to repair v2.1's O(1) ablation. Needs per-rule causal bookkeeping that does not exist. | E4 |
| 40 | Two-regime budgets, Stage A scaling | S (policy) | Consistent with DreamCoder-scale budgets. MINE: budget alone saturates (§7). | E1, E5 |

Not on the critical path, deferred by the plan: Tier 2 `cl:compile`; the Stage 3 spectral or `address` layer.

**Count.** K or K-partial 6 (#10, 12, 13, 14, 27, 28, counting wrappers as K); S 13; A 7 (#9, 16, 25, 30, 34, 36, 38);
X 14 (#3, 4, 7, 11, 15, 18, 20, 21, 22, 24, 26, 32, 37, 39). **A + X = 21 of 40.**

Per gate: E1 needs #11, #26 (X). E2 needs #32 (X). E3 needs #4 (X), #9, #30 (A). E4 needs #37, #39 (X), #38 (A).
E5 needs #15 (X), #16, #34, #36 (A). Stage 2 needs #3, #7, #18, #20, #21, #22, #24 (X), #25 (A).

### 2.1 Quantitative claims that are projections, not measurements

| Claim | Where | Status |
|---|---|---|
| "43×–110× less work" for bottom-up evaluation | `:115`, `:371`, `:757` | PROJECTION. 828,242 and 7,524 appear only in `plan_v2.tex` (no script, no results file). The ratio compares VM tariff units with a count of primitive operations. MINE on the WIP code: 2.6–3.2× tariff, wall-clock regression. |
| "233 classes vs 3,044 trees at 24 bits" | `:738`, `:761` | UNCHECKED, no artifact. (The 38:1 figure at 30 bits is from `plan_v2b.md:193`.) |
| "<2 µs lookup (~300 integer ops)" for Naive Bayes | `:107`, `:401` | PROJECTION. Also beside the point: the question is whether it has signal. |
| "~1,050 / ~1,100 LOC clean core"; 460/150/45/165/140/140 | `:81`, `:126–136`, `:349`, `:615`, `:800` | PROJECTION, and internally inconsistent (1,050 three times, 1,100 twice). Trajectory across versions: ~10,000 → 2,200 → 1,250 → 1,050 → 1,100 for the same promised function. |
| "diff facts ~35 LOC" | `:111`, `:552` | WRONG against the WIP: `v2/ast.lisp` +407/−74. About 190 lines are difference-fact code proper (`:835–957` plus the `condition-facts` and `known-*` changes) and about 130 more are totality cases built on it. |
| "2-rule fix ~35 LOC", "symmetric VM + unfold + recursion ~165 LOC" | `:132`, `:659` | PROJECTION, already exceeded. Memo and factoring are about 60 lines (claimed 35). With the opcode fold rules (`requirements.lisp` +171 in all), `vm.lisp` +95 and `proposals.lisp` +198, the "~165 LOC" subsystem stands at about 450 lines before any recursion work. |
| PIT ~25, induction ~80, mini-egraph <180, AU ~90, CEGAR ~40, recursion ~55, summaries ~25 | `:459`, `:492`, `:586–587`, `:660`, `:668` | PROJECTION. The one data point available (the WIP) shows overruns of roughly 3–6×. |
| "match probes from ~840 units to 1–2 units" | `:379` | PROJECTION. |
| "Primarily an implementation artifact (85%) plus a small-task fixed-cost threshold (15%)" | `:379` | Invented precision. No measurement separates the two. |
| "depth-1 `:code-eval` visited in ~60 candidates" | `:738`, `:755` | PROJECTION. |
| "1,753 → ≤4 laws" | `:626`, `:739`, `:794` | PROJECTION (a gate). v2.1 said "to 9 laws" (`4043a8e:913`). `plan_v2b.md:170` says "all consequences of two". |
| "40 DAG visits on length 4 … 39 visits" ("Measured in SBCL") | `:659` | UNCHECKED, no artifact. |
| "non-shift miss cost from 3,637 work to <15 units" | `:668` | PROJECTION. |
| "cut 128-bit integer search from 2,193,972 to 454,323 (−79.3%)" | `:379` | Digits WRONG: `deprecated/results.md:1444` has 2,193,913 → 454,724 (79.3% is right). The same table shows *full bounded search got more expensive* with propagation (2,973,192 → 3,522,367), which the plan omits. |
| "`cl:compile` takes 0.5–3.0 ms" | `:367` | UNCHECKED here. |
| `W_A = max(2000, min(250000, ⌊W_job/64⌋))`; 10^7–5×10^8 work per spec; "≥10×–100× amortization" | `:772–773` | Design constants and targets. |
| "cccc 7,376 → <2,200; LOC 17,818 → ~5,500; max function 311 → ≤35" | `:803` | Targets. Observed so far: 7,376 → 7,519 → 8,292. |
| ">95% of candidate nodes sit outside `:if`" | `:550` | UNCHECKED. |
| CompressARC "~4% on algorithmic ARC-AGI-2", "20 min GPU per puzzle" | `:493` | AS-CLAIMED. |

Table 4's column is headed "Verified v2.3 Repair & Cost" (`plan_v2.tex:753`). None of the five repairs was implemented
when that was written, and the WIP later implemented two of them behind flags that are off.

### 2.2 Kernel facts I spot-checked

VERIFIED: 25 modules total 17,647 lines (17,656 with `load.lisp`); the per-module LOC in Table `tab:cccc`; 14
knowledge kinds; `*max-coupled-slot-candidates*` = 4 at `synthesize.lisp:636`; `*max-eager-proposals-per-node*` = nil
at `:1042`; `(provably-total-p replay)` at `consolidate.lisp:1473`; `law-operator-fact` at `consolidate.lisp:709`;
`retype-knowledge-laws` call at `:1022`; `:/` is `truncate` on `:int` at `vm.lisp:219`; variable-length opcode code
at `codec.lisp:18–21`; `expression-closure` at `vm.lisp:439`; `plan-exec.md:15,20` give 4.0× and 7.5×;
`plan9-audit.md:501` gives no result at 57 bits within 60,000,000 work; `plan_v2b.md:192` gives the 70% preparation
share; five of the seven margin notes (M1–M5) are in `plan_v2b_annotated.pdf` verbatim. Of 40 file:line citations I
tested, 31 land within three lines; the rest are near misses that match `v2/` line numbers or neighbouring
definitions (`frame.lisp:1033` is at 1019, `synthesize.lisp:876` at 847, `laws.lisp:1184` is `make-knowledge-solver`,
not `arithmetic-propagator`, which is at 451–471; `vm.lisp:186` is not `:code-less`, which is at 148 and 176).

UNCHECKED or unverifiable: `plan_v2_annotated.pdf` (cited at `plan_v2.tex:448`) is not in the working tree or in git
history; the cited bootstrap time is at `plan_v2b.md:864`, not `:221`.

### 2.3 Every citation the plan leans on

All AS-CLAIMED unless noted. "2026" entries post-date anything I can check from memory.

- **Stores, fibrations, e-graphs** (`plan_v2.tex:814–857`): Patterson, Lynch & Fairbanks 2022 (ACSets,
  arXiv:2106.04703); Brown, Patterson, Hanks & Fairbanks 2022/2023 (arXiv:2111.03784); Spivak 2012 (arXiv:1009.1166)
  and Poly (arXiv:2005.01894); Melliès & Zeilberger POPL 2015; Zhang et al. egglog PLDI 2023; Wang, Willsey & Suciu
  Free Join SIGMOD 2023; Singher & Itzhaky Colored E-Graphs (arXiv:2305.19203) and Easter Egg FMCAD 2024; Schneider
  et al. Slotted E-Graphs PLDI 2025; **Zucker, "Lifting E-Graphs: A Function Isn't a Constant", EGRAPHS 2026,
  arXiv:2606.22734**; Bonchi et al. JACM 2022; Tiurin et al. "Equivalence Hypergraphs", LICS 2025
  (arXiv:2406.15882; venue unconfirmed); **Rosin, Ullrich & Hack, "Associativity and Commutativity in Equality
  Saturation", EGRAPHS 2026, arXiv:2610.01198** (an October arXiv number for a workshop normally held in June:
  worth checking); Goharshady, Lam & Parreaux OOPSLA 2024; Kœhler et al. POPL 2024; Nandi et al. Ruler OOPSLA 2021;
  **Cheung, Nandi & Lerner, CHOMPY, FMCAD 2026**; Ellis et al. DreamCoder PLDI 2021; Cao et al. babble POPL 2023;
  Bowers et al. Stitch POPL 2023; Koppel et al. ECTA ICFP 2022; Smallbone et al. QuickSpec 2, JFP 2017.
- **Containers, loops, proofs** (`:864–880`): Abbott, Altenkirch & Ghani 2005; Gibbons ESOP 2017; Paszke et al. Dex
  ICFP 2021; Gibbons 1996 (third homomorphism theorem); Farzan & Nicolet Parsynt PLDI 2017; Nandi et al. Szalinski
  PLDI 2020; Massey 1969; Miltner et al. Burst POPL 2022; Singher & Itzhaky TheSy CAV 2021.
- **Propagators, sheaves, information** (`:887–897`): Radul & Sussman 2009; Miné 2001; Perera et al. ICFP 2012;
  Robinson 2020 (arXiv:1805.08927 per v2.1); Abramsky & Brandenburger 2011; Hansen & Ghrist 2019; Bodnar et al. 2022;
  **Caralt et al. 2026 (arXiv:2603.05395 per v2.1)**; Ó Conghaile MFCS 2022; Bennett et al. 1998; Vereshchagin &
  Vitányi 2004; Hoogeboom et al. 2019; Townsend, Bird & Barber ICLR 2019; Balasubramanian 1997; Myung et al. PNAS 2000.
- **Superposition, brain scaffolds, lowering, reflection** (`:904–920`): Adler & Shavit 2024 (arXiv:2409.15318);
  Ren et al. ICLR 2020; Frady et al. 2020; Peng et al. 2024; Park et al. ICLR 2025; Feng & Steinhardt ICLR 2024;
  Whittington et al. Cell 2020 (TEM); George et al. 2021 (CSCG); Raju et al. 2024; Chandra et al. Nature 2025
  (Vector-HaSH); **Hoover, Blayney & Whittington, CRAM, arXiv:2611.17309v1** (supplied by the owner in margin M7);
  Liao & Gu CompressARC (arXiv:2512.06104); Kühlwein et al. MaSh ITP 2013; Blaauwbroek et al. Graph2Tac ICML 2024;
  Smith 1984; des Rivières & Smith 1984; Maes 1987; Amin & Rompf POPL 2018; Lenat & Brown 1984; Goertzel et al. 2023.
- Cited in earlier versions and dropped: Padhi et al. 2016 (PIE); Grand et al. LILO ICLR 2024; Plate 1995; Kanerva 2009.

Patterns worth knowing:

- **Citations were used first as building blocks and then as cautionary tales.** Parsynt is "imported" in v2.1
  (`4043a8e:113`, `:825`) and "misapplied … requires a known source loop" one version later (`plan_v2.tex:113`).
  Colored e-graphs, Zucker's thinning, Robinson's consistency radius, Ó Conghaile's cohomology and bits-back all
  follow the same arc.
- **Over-reading.** v2.2 says Park et al. "proved that what in-context attention actually computes on a graph is
  Dirichlet energy minimization — whose exact global optimum is given in closed form by Laplacian / SVD
  eigenvectors" (`faf8909:401`). As I recall that paper it is an empirical finding with an energy-minimization
  interpretation. Treat "proved" as the plan's word.
- Five 2026 items carry weight in the argument (Zucker, Rosin et al., Cheung et al., Caralt et al., Hoover et al.).
  Three of them are workshop or same-year papers.

---

## 3. What each audit pass removed

### 3.1 The trap list

**v2.0 (`plan_v2.md`) → v2.1.** Reasons from `4043a8e:plan_v2.tex:105–115`, `:408–418`, `:463`.

| Removed | Stated reason |
|---|---|
| D = 256 VSA ambient bus as the geometric substrate, with binding as "creating a space" and key unification as "collapsing two spaces" (`plan_v2.md:297–330`) | Computing in superposition is quadratically, not exponentially, efficient (Adler & Shavit); unbinding noise √(K/D) (Frady); disjunction needs Θ(N) dimensions (Ren); one attention layer cannot compose (Peng). Demoted to a 1-hop hash pre-filter in v2.1, gone in v2.2. |
| Vector cellular sheaves with learned restriction matrices | Learned restriction maps rarely beat the identity (Caralt et al. 2026, plus `plan_v2b` §6.8). |
| Heuristic Jacobian scale `J_scale` in the child metric (`plan_v2.md:326`) | Discrete bijections carry no Jacobian term. |
| Pointer-struct `hyperstore` | Columnar arrays instead. |

**v2.1 → v2.2 (Pass 1, "mathematical soundness").** Reasons from `plan_v2.tex:105–115`, Table 1, and `faf8909:105–136`.

| Removed | Stated reason |
|---|---|
| The "5-extension e-graph": egglog/Free Join + Zucker thinning union-find + Colored e-graphs + Chompy + AC multiset rebuilding + babble (~10,000 LOC) | "Five research extensions never combined in any published system" (`faf8909:105`). The plan's own combination was unsound: a subset mask plus left-to-right slot order equates `x0−x1` with `x1−x0`. 32-variable overflow. Kapur critical pairs times 2^k composite colours. |
| Robinson consistency radius as residual price | Restriction variance reversed; sup is not additive; summing over cover morphisms double-counts rows in ≥3 patches. |
| Čech cohomology (Ó Conghaile) as the source of nogoods | ℤ-linearization lets signed combinations cancel when no discrete solution exists, and emits no Boolean clause. |
| Bits-back symmetry refund, −log2\|Sym\| | Violates Kraft when the child is a deterministic program (description length goes to −155 bits in the plan's own counterexample, `plan_v2.tex:470`); counting \|Sym\| is #P-hard. |
| Colored branch forking on `:if` | 2^{\|xs\|} worlds on `:filter`. |
| Parsynt accumulator synthesis | Needs the source loop, which I/O synthesis does not have. |
| Burst/ECTA tree automata | >3,000 LOC. |
| Cross-multiplying PIT through `:/` | `:/` truncates on `:int`: ⌊5/2⌋·2 ≠ 5. |
| Full TheSy induction; external PIE bi-abduction | Unbounded lemma search; unnecessary machinery. |
| int8 SGD d = 64 attention/bilinear router | >10^4 weights on 100 entries overfits; ~1,000 LOC of autodiff in Lisp. |
| CRAM-style energy relaxation | Needs training on thousands of puzzles. |
| `cl:compile` at 10^3 evaluations | Compile costs 0.5–3 ms against 2.1 µs per closure call. |
| Unboxed fixnum columns for `:int` | Bignum overflow. |
| O(1) ablation by assumption toggle | Would archive every working nogood: a rule that kills a dead branch is never on the winning path. |
| Experimentation as an object-language primitive | Moved to the meta grammar. |

**v2.2 → v2.3 (Pass 2, "purity, budgets, simplicity").** Reasons from `plan_v2.tex:105–115`, `:401`, `:550`, Table 4.

| Removed | Stated reason |
|---|---|
| AC, identity and cancellation hard-coded in the DAG constructor for `:+`, `:*` | "Smuggles `algebra.sexp` into host Lisp." |
| `:tabulate` and `:loop` opcodes | "Smuggled `map-indexed`/`foldl` into host Lisp via higher-order opcodes" (`dbd3347:113`). **Reversed in v2.4.** |
| `:filter`-specific O(\|X\|·\|Y\|) subsequence propagator | Hard-codes one library function. |
| Host probes: normalized cross-correlation, autocorrelation, finite differences, Berlekamp–Massey/Hankel rank | Domain solvers in core structs, against `prompt4.md:206`. To be "bootstrapped library recognizers" instead. |
| Closed-form 32-dimensional Laplacian/SVD, 2-hop WL hashes, the `(:like/:analogy/:act)` query DSL | "Eigensolver or interpreter bloat" at \|L\| ≤ 500. Deferred to an "optional Stage-3 affordance". |
| 12×12 DBM matrix per context, with host transfer rules for `mod`, `tabulate`, positivity | 144 words on every enumerated node; "10–30× overkill". |
| Bitset AC-3 plus "discrete Hard-EM" on coupled cells | O(D²) = 10^6 evaluations at D = 1,000. Hard-EM silently dropped. |
| Unbounded witness-set sum | Stalls Stage A as O(C·\|R\|·\|S\|). |
| O(n!) permutation search for unordered covers | Explodes past n = 8. |
| Pareto size lists; ephemeral e-graph per subgoal | Two integers suffice once slot maps are injective; "1,753× rebuilds". |
| Top-down Stage A evaluation; exact-bits horizon; eager preparation; 4-candidate pool cap | The five "budget cliffs". |
| (Added in `551f106`) | The two-regime wake–sleep budget contract. |

**v2.3 → v2.4 (Pass 3, "VM symmetry").**

| Removed | Stated reason |
|---|---|
| Pass 2's own freeze of the VM at 27 opcodes | "Over-corrected": elimination was primitive while introduction, lift and generalization were "trapped in host Lisp", which "violates the core reentrancy goal" (`plan_v2.tex:457`). Ten opcodes added, including `:tabulate` again and `:loop` again as `:evolve`. |

### 3.2 Instability

What changed at least once between v2.1 and v2.4: the equivalence store (global multi-extension e-graph → ephemeral
mini e-graph → batch mini e-graph); the binder representation (thinning mask → slot map → injective slot map); AC
handling (e-graph multisets → hard-coded constructor → law-activated flags); totality (DBM in context → 12×12 DBM →
fact list); residual pricing (consistency radius plus bits-back → partition of unity plus full witness sum → top-8);
geometry (VSA → SGD router → SVD → Naive Bayes only); loop lifting (Parsynt → `:loop` → self-calls only → `:evolve`
plus self-calls); `:filter` (colour forking → host propagator → generic unfold); VM opcodes (add → freeze → add
more); experimentation (object level → meta level); attribution (O(1) → 4-bucket); lowering (3 tiers → 4).

What survived all four versions essentially unchanged: columnar tables as the layout; one `grule` record for all
knowledge; the Σ/Δ/Π + d\* vocabulary; Naive Bayes log-odds as the cold-start trigger; PIT; the behaviour table; the
five cover geometries and four residual rules as *text*; Stage 0; and the empirical audit of the kernel
(`plan_v2.tex:229–290`), which is the most reliable part of the document.

Two further signals:

- **Small numbers move between versions without explanation.** Law minimization "1,753 → 9" (v2.1) becomes "≤ 4".
  "7 live bugs" becomes "ten defects". The ratchet targets tighten (<2,400 → <2,200; ~6,000 → ~5,500 LOC) while
  the design changes underneath. Worked trace 2 detects the residual by "lag-2 autocorrelation" in v2.1–2.2 and by a
  "parity summary" in v2.3–2.4, with the same 94 → 28 → 0 bits.
- **The document was not re-read after Pass 3.** The v2.4 file refers to `v2.3` 64 times and to `v2.4` 11 times, and most mechanism descriptions still begin "Kernel v2.3 …".
  The owner's commit message for v2.2 already reads "Still quite complicated, though; not sure if it can be
  directly implemented."

---

## 4. The geometry dialog

The questions below are the owner's, verbatim from the embedded prompt (`plan_v2.tex:153–211`) and margin notes
(`:213–226`). That prompt is the earlier comparative one, not `plan_v2_prompt.md`.

### Q2 — VSA vs local transformers vs brain scaffolds

> "Are you certain that VSA is the right role? What about a small local-context BERT style transformer? The alternate
> proposal `plan_v2b` mentions keeping everything flat … with some wrinkles that definitely need to be gone through."
> "Compare VSA with the suggestions in v2b section 6.6. I've heard of the Tolman-Eichenbaum machine, but have not read
> up; could be hype-y." "Having looked at it, it seems to be a form of gradient-trained system with a (semi-fixed?)
> lifting through hippocampally-defined structure."

Positions, by version:

- **v2.0** (`plan_v2.md:297–330`): one flat 256-dimensional space. Binding by a key *is* making a space ("transports
  x into a fresh quasi-orthogonal subspace … without allocating a new neuron"). Unifying two keys *is* collapsing
  two spaces. `like` = bundling, `analogy` = binding difference, `action` = context operator. This is the only
  version that answers the owner's make/collapse/move question directly.
- **v2.1** (`4043a8e:401–444`): "No — pure VSA is not sufficient." Two regimes: below 100 library entries, exact
  probes plus Naive Bayes log-odds; above, a trained d = 64 quantized bilinear/attention router minimizing "graph
  Dirichlet + MDL-distance loss". VSA kept only for 1-hop hashes.
- **v2.2** (`faf8909:401`, `:643–650`): the router is "unnecessary risk". Replace it with the top 32 eigenvectors of
  `S = α·A_verified + (1−α)·W̃W̃ᵀ` (verified links plus Naive Bayes weights), by 20 orthogonal-iteration steps, and a
  three-combinator query language. This is the only version in which *verified topological links shape a geometry*.
- **v2.3–v2.4** (`plan_v2.tex:395–401`, `:664–670`): SVD and query language are "bloat" below 500 rules. Keep sparse
  Naive Bayes plus "verified topological dependency edges (`:inverts`, `:refactored-by`, `:induced-by`)", which are
  named once and given no mechanism. An `address` slot stays `nil`.

Argument and evidence. Against flat vectors carrying nested structure: the four cited bounds (AS-CLAIMED). On TEM:
agreement with the owner that it is BPTT over a fixed action set and unsuitable when new combinators are invented.
From Vector-HaSH and CSCG: "factorizing an exact discrete algebraic scaffold from flat content associations", and
clone-splitting of aliased states as an analogue of the kernel's DIP state splitting. For deferral:
`prompt4.md:206–207`, "We don't need this self-organization yet … but affordances should be made for its later
addition" (VERIFIED as quoted).

Open. (i) Whether a flat space with context beats made spaces is argued from lower bounds, never tested. (ii) The
warm-regime mechanism was replaced twice and then removed. (iii) The deferral rests on a sentence from an older
prompt; the current prompt says the opposite: "We *must* start with some bedrock of 'these things are close'".
(iv) The Naive Bayes features (five column summaries, type constructors, probe hashes) are a bag of flags, not a
space. (v) The small local transformer the owner asked about gets one paragraph in v2.1 and none later.

### M3 — "what is the evidence for this? Or proof?"

On `plan_v2b`'s "Computing in superposition compresses only quadratically where storage compresses exponentially".
Answer (`plan_v2.tex:397`): Adler & Shavit, arXiv:2409.15318, by Kolmogorov counting over families of pairwise
Boolean functions: m′ sparse features can be *stored* in O(log m′) dimensions (Johnson–Lindenstrauss) but
*computing* m′ pairwise features needs width Ω(√(m′ log m′)) and Ω(m′ log m′) parameters, so n neurons compute at
most O(n²/log n) features. AS-CLAIMED; the statement matches my recollection of the paper. Limit: it is a bound on
one class of circuits computing pairwise ANDs. It says flat vectors should not *be* the computation. It does not
say geometry cannot rank or address.

### M5 — "yes. obviously."

On "Every successful system … keeps truth in an exact engine and lets geometry only rank or propose". The plan adopts
it as an invariant: "Geometry only ranks, triggers, and prices Stage A" (`plan_v2.tex:493`). This is the one
geometric principle stable across every version and endorsed by the owner. Keep it.

### M7 — the flat alternative may simply win

> "Yes, also - brute-force search works whenever the size of the search space is small enough and the speed of each
> evaluation is short enough. This is how recent work in energy-based models were able to solve hard combinatorial
> problems. See, for example, https://arxiv.org/abs/2611.17309v1 A good reason for the homoiconic, scheduled lowering
> / compiling formulation."

(Spelling normalized here; the original reads "energy-based omdels" and "homiconic".)

Answer (`plan_v2.tex:367–373`): accept the principle; answer the "fast evaluation" half with the four-tier lowering
schedule; reject CRAM itself (needs training on thousands of grids). The "small search space" half is answered
implicitly by behaviour pruning. MINE: on this kernel the space half is worth far more than the speed half
(pruning 79×, column evaluation 2.6×, on `quartic 77`).

### Q3 — sheaf theory

> "As I'm reading the plans, I'm belatedly realizing that there is mathematics at the intersection of topology and
> geometry -- sheaf theory (another area of mathematics that I barely understans [sic]). `plan_v2b` references sheaves; is
> this consistent and compatible with your `plan_v2`?"

- **v2.1** (`4043a8e:452–476`): "Yes — sheaf theory is the *exact* mathematical bridge." Stalks are candidate sets
  with the MDL correction as pseudometric; restriction maps are verified decoders; consistency radius zero = global
  section = verified program; positive radius = residual bits; nonzero infimum = cohomological obstruction = nogood.
- **v2.2–v2.4** (`plan_v2.tex:408–419`): "Conceptually yes … but v2.3 strips away both learned sheaf matrices and
  flawed cohomological machinery." Two traps: the radius is a sup and the summed variant double-counts overlaps;
  integer cohomology neither decides discrete problems nor emits clauses. What remains: price each root row once
  through a selector κ (Eq. 1); require exact agreement on overlaps `(logand mask-j mask-k)`; detect gluing failure
  by fibrewise meet, fact contradiction or joins; emit ordinary 1-UIP nogoods (`nogoods.lisp:218`, VERIFIED present).

Assessment. The retreat is correct and the reasons are sound as stated. After it, "sheaf" contributes vocabulary
only: a cover is a set of row masks, a section is a program per mask, gluing is agreement on shared rows, and
obstruction is an ordinary conflict clause. Nothing in v2.4 needs sheaf theory to be stated or implemented.
Open: whether any local-to-global structure beyond "agree on shared rows" earns its keep. The plan gives no example
that needs more.

### Q6 — conditional description length and pricing of made spaces

> "Likewise, section 6.5 is an possibly deep perspective, and might well be useful in intermediate-space induction.
> Or it, like everything else, might be a tool of bounded utility."

- **v2.1** (`4043a8e:542–557`): "Both halves of your intuition are right." Three "exact, parameter-free accounting
  identities": bijective charts cost nothing extra; surjections cost log2 of the fibre size; under-determined latents
  get a bits-back refund of log2|Sym|.
- **v2.2–v2.4** (`plan_v2.tex:467–479`): the refund is a "critical Kraft-inequality violation". Counterexample: 20
  rows with Y = X, decoder `⌊z/2^10⌋` (20 bits), program `g(x)=1024x` (25 bits), 2^10 witnesses per row, refund 200
  bits, net −155. Replacement: (1) deterministic child: exactly `bits(d)+bits(g)`; (2) explicit witness sets: mass
  of the 8 nearest witnesses (Eq. 2); (3) unlabeled partitions: first-appearance labels.

Assessment. Rule 1 is right and is the important one: an under-determined intermediate space is paid for by the
cheapest program that lands in the fibres, with no refund. Rule 3 is standard and already in the kernel. Rule 2 is
a small refinement of v1's closest-witness score. The bounded-utility half of the answer, stated clearly only in
v2.1 (`4043a8e:557`), is the durable insight: conditional description length is the *objective* and cannot be the
*heuristic*, because estimating it is the synthesis problem, and before a connecting program exists the distance
between `2x+1000` and `2x+1001` is infinite.

Open, and it is the owner's question in the current prompt ("I'm not sure if there are better options for
bootstrapping generated and intermediate spaces other than pricing in the original or ambient spaces"): v2.4 offers
no alternative to pricing in the ambient space. Rule (c) of Q9a and Eq. 1 both price at the root. The one attempt
at intrinsic pricing of a made space (the symmetry refund) was the thing struck down.

### Q9 / Q9a — covers, charts, multi-stage residuals

> "v2b sec 7.4: worry that we're focusing too much on the indexing (since that has concrete examples at the beginning
> of the prompt), and not fiber (or sheaf, cover, chart..) computation, which is more general." "Not enough
> consideration of residuals in this plan."

Answer (`plan_v2.tex:529–542`, nearly unchanged since v2.1). Five cover types "uniformly over `cbase`": (1) container
coordinates (sequences, tuples, grids, AST positions); (2) disjoint and overlapping guard regions; (3) quotients
along conserved invariants; (4) unordered collections via synthesized sort keys; (5) value-space residual charts
`Y = d(X, Ŷ, Δ)`. Residual calculus, four rules: (a) an explicit chart witness (signed difference, quotient and
remainder, exception mask); (b) accept a stage only if total bits strictly fall, with leftovers as a sparse lookup;
(c) weight residuals by 1/|fibre| per root row; (d) re-run library triggers on the residual column.

Evidence: one worked example, `y_t = 2x_{t−2} + (−1)^t + 3`, "MDL from 94 to 28 bits … to 0" (`plan_v2.tex:737`).
It is a narrative, not a run. Its first step requires a "bootstrapped shift-correlation metric grule" that does not
exist.

Assessment. Rule (c) is grounded in `plan9-audit.md` §4 and is worth keeping. Rule (b) is a sound stopping rule.
Types (1), (2) and (5) extend things the kernel has. Types (3) and (4) are names: nothing says how an invariant or a
sort key is found, and `orient-conserved-quantity` and `induce-row-order` have no callers today
(`plan_v2.tex:284`). "Uniformly over cbase" is asserted, not shown: each type needs its own proposal source.
Deferred: nothing explicitly, but only type (1) reached the WIP.

### Q13 — information geometry of the library

> "v2b, sec 9: 'A uniform store is not uniformly learnable. Each level needs a schema designed so that small changes
> are meaningful, and that design is not done here' -- well, this is the point of the whole experiment! Small changes
> meaningful ≃ information geometry of the library or language. Right?"

Answer: "Yes." (`plan_v2.tex:575–576`; v2.1 at `4043a8e:709–728` is longer and more excited.) The prefix code is the
coordinate chart; a one-operator edit is a small step; behaviour change on the rows is the movement. Quotienting
duplicates removes directions where syntax moves and behaviour does not (38:1 → 1:1). Abstraction pulls 40-bit
concepts into 5-bit one-edit neighbours. Totality prunes crash directions. v2.1 defines a "local algorithmic Fisher
sensitivity" I_L(p) = expected non-crashing, novel behavioural displacement over one-edit neighbours. In v2.4 that
survives only as a sidenote: "an offline curriculum diagnostic (never computed inside inner search)". Caveat kept
from `plan_v2b`: the initial `SearchTrace` schema must have meaningful code and delta columns, not opaque ids.

Assessment. As analogy it is fair and agrees with the owner. As mechanism it is empty: the Fisher-volume reading of
MDL (Balasubramanian; Myung et al.) concerns smooth parametric families, and nothing here is computed from it.
The one usable piece is the diagnostic I_L(p), which is cheap to measure and would turn "small changes meaningful"
into a number tracked across library growth. The plan defers it. Open: no experiment tests whether library growth
actually increases one-edit behavioural density.

### M1 — "how, though?"

On "keep the topology nested and exact, keep the geometry flat and local to each space, and compare across spaces
only through verified maps". Answer (`plan_v2.tex:432–435`): (i) nested decoders are exact integer ids in the DAG;
(ii) on one table and type, two columns have distance Σ_rows bits(u[s], v[s]); (iii) candidates in different spaces
are never compared directly, but pushed forward through the decoder or pulled back through a verified witness into
a shared space first.

Assessment. This is a correct description of what v1 already does (Stage A residual in the node's representation;
requirement pullback). It answers "how" for *pricing a candidate against a target*. It does not answer how proximity
between two *problems*, two *rules* or two *spaces* is represented or moves, which is what a heuristic or a
language needs.

### Pillar III as it stands (`plan_v2.tex:664–670`)

Two items. (1) Host summaries of a column in O(N): `empty-p`, `const-p`, `monotone-sign`, `distinct-ratio`, sum and
length parity. Domain recognizers must be synthesized library rules "gated behind a cheap O(1) millibit log-odds
threshold". (2) The Naive Bayes inverted index; everything spectral or compositional behind `address`, for Stage 3.

### What geometric objects survive, and what they do

| Object | Does | New relative to v1? |
|---|---|---|
| Per-table column distance in bits | Stage A residual | No |
| Push or pull through a verified decoder before comparing | Cross-space pricing | No |
| One price per root row; 1/\|fibre\| weighting | Stops lifts inflating residuals | Partly (audit fix) |
| Top-8 witness mass | Scores a candidate against a witness set | Minor refinement |
| First-appearance labels | Removes k! relabelings | No |
| Residual columns with MDL stop | Peels layered structure | Proposed, not built |
| Column summaries + Naive Bayes weights | Triggers rules | Proposed, not built |
| `:inverts` / `:refactored-by` / `:induced-by` edges | Unspecified | Named only |
| `address` slot | Nothing (`nil`) | Placeholder |

**Is there anything that would let the system "make spaces where needed, collapse them when symmetry-finding shows
they are the same, and move vectors along verified links"?**

- *Make*: yes, topologically. A lift, a guard split or a residual column makes a new table or column. That is a
  set of rows with a map to its parent, with the bit metric inherited from the type.
- *Collapse*: no. The behaviour table "never merges across bases" by design (`plan_v2.tex:625`). Law-activated
  flags merge *expressions*, not spaces. Quotient covers presuppose the invariant.
- *Move*: only one candidate column at a time through one decoder, for pricing. Nothing propagates similarity
  along verified links. v2.0 (key unification) and v2.2 (`A_verified` in the spectral matrix) each had a mechanism;
  both were removed.

So the geometry case is open, as the owner says. The plan's contribution is negative knowledge: which imports fail
and why (VSA as computation, learned sheaf maps, cohomological nogoods, symmetry refunds, an SGD router at this
scale), plus two invariants (truth exact and geometry only ranks; price in bits with Kraft discipline).

---

## 5. The rest of the Q&A

**Q1 / Q1a — homoiconic + deferred lowering.** "Is this compatible with the dual {homoiconic and deferred-lowering to
machine code} current design? … only lower to compiled executable code when needed & warranted."
Answer (`plan_v2.tex:365–373`): yes, without relaxing homoiconicity. Four tiers: step VM for 1–4 evaluations; closure
tree above that; column closures for Stage A sweeps; `cl:compile` at ≥50,000 site evaluations or for committed
rules. Bignum-safe.
*Assessment:* tiers 0–1 are measured (`plan-exec.md`: 4.0× and 7.5×, VERIFIED). Tier 1.5 is the column evaluator;
MINE: lower tariff, slower wall-clock as written. Tier 2 is deferred. Sound in principle, with the caveat that the
tariff and the clock now disagree.

**Q1b — "Reuse has lost to matching cost in every small measured case on record … is this a matter of scale or
implementation?"**
Answer (`:379`): "85% implementation, 15% fixed cost". M3 paid 545,921 matching units to save 7,732, because rules
were scanned linearly and `:code-less` serialized both terms. M4 propagation lost on a toy field but cut a 128-bit
integer search by 79.3%. Remedy: index rules by (head, child heads) and cache sizes.
*Assessment:* both data points exist (`deprecated/results.md:1048–1058`, `:1440–1447`), with wrong digits and with
the worse full-search figure omitted. The 85/15 split is not a measurement. The honest answer is "both": reuse paid
only where the avoided computation was expensive. The remedy is standard and untested here.

**Q1c — let.** "Also, somewhat glad we did not factor in the let binding, since the current structure is more
compatible with graph / hypergraph structuring .. or doe [sic] let binding have a simple interpretation in the g/hg
interpretation?"
Answer (`:385`): omitting `let` was right. In a hash-consed DAG a shared subterm is wire fan-out. Price a shared node
once plus a back-reference; optimal DAG extraction is hard, so budget it. Hoisting above `:if` is valid only if the
shared term is total or demanded on both branches.
*Assessment:* standard and correct, including the call-by-value condition. It changes the codec's prices (trees
today), which the owner now permits.

**Q4 / Q12 — attributed C-sets; "The hypergraph is the semantics (?!?)".**
Answer (`:428–430`): a C-set over the schema {class, application node, port} is isomorphic to a directed port
hypergraph, so the mathematics is a hypergraph and the memory layout is arrays. Plain C-sets are insufficient:
homomorphism matching is NP-complete, there is no congruence or AC normalization, and they cover row migration but
not predicate pullback.
*Assessment:* the isomorphism is true and trivial. It resolves the wording and sidesteps the question, which was
whether an n-way graph is the right *operational* structure. v2.4's operative structure is a rooted term DAG plus
tables. Also a reversal: v2.1 said one "must layer egglog's union-find + seminaive rebuild" on the tables
(`4043a8e:498`); v2.2 onward has no e-graph in the store.

**Q5a — colored, slotted, lifting e-graphs.**
Answer (`:446–450`): adopt none. Slotted needs permutation-group stabilizers in union-find. Thinning masks with slot
order are unsound in the plan's own combination and overflow at 32 columns. Colored spawns 2^k composite colours and
has no meet across branches. Chompy needs an SMT solver. Use slot-map handles, row masks plus fact lists, and one
small e-graph for derivability.
*Assessment:* declining the stack is prudent. The unsoundness was of v2.1's combination, not of the papers. The
replacement (risk item 3) is unbuilt and has its own hole. For the synthesis: nothing from the e-graph family is
needed on the critical path except, possibly, a small derivability check.

**Q5b — third homomorphism theorem, Farzan & Nicolet, Szalinski, index-function induction.**
Answer (`:455–460`): Gibbons' theorem marks the boundary between reductions that split by index and sequential
state. Parsynt is inapplicable. Take Szalinski's speculative identity unrolling for anti-unification, and replace its
affine index solver with MDL synthesis over gather preimage fibres. Replace Burst by a replay loop. Complete the VM
symmetrically. The footnote at `:290` gives a five-tier taxonomy: T0 index lenses, T1 stencils, T2 selective
subsequences, T3 observed scans, T4 hidden state.
*Assessment:* the taxonomy is useful and independent of the design. The gather fibre pullback is real (§6). T4 is
unsolved in practice: `foldl` is an impostor and `scan` times out, at every budget I tried.

**Q7 — the sceptic.** "Skeptic's view in v2b sec 6.8 cuts deep and meaningfully. How would you respond to these
examples?"
Answer (`:487–494`): map each warning to an invariant. EURISKO: typed schemas, simulator verification, compression
raising mutation density. OpenCog: exact grades, no fuzzy truth, no unrestricted subgraph matching. Monotone store,
non-monotone control outside it. Stitch over babble. Truth exact, geometry ranks. CompressARC shows flat neural MDL
builds no cross-task library.
*Assessment:* the weakest answer. It restates design intent. The sceptic's best evidence is in this document's own
audit: 2 of 52 library entries arise unassisted, ablating reflective entries moves work by 0, and without
prosthetics half the bootstrap specs fail. "Compression raises mutation density" is the hypothesis under test, not a
rebuttal. The definition of monotone engines (Datalog, egglog, CDCL, propagators) is correct and worth keeping.

**Q8 — six store moves.** "v2b sec 7.3 - I agree with all of these. Yet: apply, substitute and match, and
project are all flavors of the same, as are lift and spit [sic]. Price stays the same & hasn't need a revision. This
formulation is different than the hypergraph forulation, but want to make sure I'm not missing critical
distinctions in those 6 categories."
Answer (`:502–521`): three families. Pushforward: Apply, Substitute/Match, Aggregate. Pullback: Reindex/Lift and
Split. Metric: Price. Distinctions to keep: Apply evaluates values while Substitute rewrites syntax; Aggregate is
two different things, existential merge (Σ) and universal meet (Π); Lift demands *one* program for all fibre rows
while Split allows a *different* program per region and pays for the guard; Merge is a quotient, not a split.
*Assessment:* a fair taxonomy that confirms the owner's grouping. The Lift/Split and Σ/Π distinctions are
concrete and useful. The adjunction itself does no work: no algorithm in the plan uses it. And classifying the moves
does not make them uniform operations available to the synthesizer.

**Q10 — "the lattice form of the host's totality facts".**
Answer (`:550–559`): agree with a lattice, but unary intervals cannot relate `i` to `length(xs)`; a DBM per node is
overkill; use a short list of difference facts. Host totality covers only the partial primitives' own domains;
operator range facts enter as certified library laws. Solver guards come from wrapping the replay in the witness's
definedness guard.
*Assessment:* the best-founded answer in the document. The interval objection is correct. Difference facts exist in
the WIP and pass the existing totality tests. I verified the divisibility micro-claims. Caveats: only two-step
transitivity; the "learned range" hooks are never set; the LOC estimate is off by about 5×; guards for *unknown*
partiality still fall back to separator search, so "learn totality by tolerating crashes" is only partly served.

**Q11 — 3-Lisp.**
Answer (`:568`): three rules. Do not reify live continuations in inner loops; stage reflection at explicit meta
boundaries. Raw stacks have low mutation density; use declarative trace schemas. Reflective policy must never forge
evidence. So: a `SearchTrace` table with code-valued columns, with hooks limited to proposal scoring inside the 3:1
reserve and to consolidation.
*Assessment:* conservative and reasonable, and it matches the owner's highlight in the annotated PDF ("finegrained
procedural access to interpreter state was hard to use"). It defines reflection as a mineable log. Nothing is built,
and the existing log has no readers.

**Q14 — a second proof rule.** "what would a second proof rule be, then? Obviously we do have algebra!"
Answer (`:584–588`): rule 2, PIT for `{+,−,×}` over ℤ on a grid of ∏(d_r+1) ≤ 4,096 points; rule 3, one-step
structural induction in the mini e-graph for `map id`, map fusion, `length∘map`. `foldr = foldl` stays sampled
unless its shift lemma exists.
*Assessment:* PIT is correct, cheap, and removes the four trusted axioms; adopt. The induction rule depends on a
rewriting engine that is not there. Guarded laws (for example `x/x = 1` when `x ≠ 0`) are not covered by either.

**Q15 — experimentation and attribution.** "E4: attribution by ablation: I really like this! Experimentatino [sic] is
very much not a native part of the kernel, and v2b does well to highlight & propose a remedy. Yet is it properly
integrated into the homoiconic kernel?"
Answer (`:596–608`): a metered `(:probe target intervention budget)`, in the *meta* grammar only. Three uses: input
slicing by intervention; active disambiguating queries; 4-bucket attribution. v2.1's O(1) ablation was a bug.
*Assessment:* the answer to the owner's question changed between versions, from "object-language primitive"
(`4043a8e:115`) to "meta only". Disambiguating queries are motivated by a measured failure (three `foldl`
impostors), but with fixed rows there is nobody to answer the query; the practical remedy is in the spec (vary the
code argument). The 4-bucket protocol is intricate and unvalidated.

---

## 6. Stage 0 and Stage 1 as built

### 6.1 Stage 0 (`v2/STAGE0_RESULTS.md`, commit `397499a`)

What it established, and what I re-ran:

- **Six soundness fixes with six regression tests** (`STAGE0_RESULTS.md:27–44`, `v2/tests/stage0.lisp`): default
  samples for retyped laws; `:unresolved`/`:cutoff` treated as unknown in row satisfaction; certified laws passed
  into node search; per-row fuel and sandboxed child bindings; distinct keys for coupled fallback rows; branch-safe
  `:filter` lifting. VERIFIED: 228 tests, 938,281 checks pass on the Stage 0 copy (5.8 s). `v2/tests` is the root
  `tests` plus `stage0.lisp`; no existing test was edited.
- **Ledger effect is negligible** (`:19`): every benchmark category bit-identical except H1/H2.
- **Complexity** (`:15–17`): pure-kernel cognitive 6,515 → 6,658. VERIFIED with `cccc`.
- **E0b-1a** (`:56–62`): with host `:cons` folds off, `:map` still solves (7,139 → 9,896 work). Constructor inverses
  in the library do narrow, but only as conjectures, and `lift-frame` never calls `propagate-requirements`.
- **E0b-1b** (`:68–75`): preloaded descriptors reproduce every pruning decision of the 141-complexity host function.
  A latent certificate gap on `:filter` was found.
- **E0b-2** (`:81–100`): 16 bootstrap function specs × {whitelist, full grammar} × {schemas on, off}, with held-out
  checks. Solved / held-out sound: 16/16; 10/9; 10/9; 9/8. VERIFIED: I reproduced every cell.
- **Three `foldl` impostors** (`:102–119`): every row of the spec uses the same code argument `(- A B)`, so
  right-to-left folds and a hard-coded `:-` satisfy it and are as short or shorter.

To keep in any plan: the six fixes; the E0b harness as the standing honesty metric (held-out-sound survival with no
whitelist and no schemas, currently 8/16); the finding that host content can be gated and measured; the rule that
higher-order specs must vary their code arguments.

One caution. The harness caps each spec at 350,000 work, which is about 60 ms. Stage 0's "TIMEOUT" therefore means
"not within 60 ms", and the document's implication (`:125–127`) that representation is the cause was never
separated from budget. §7 does that.

### 6.2 Stage 1 WIP (`a4e19fa`, `git diff 397499a a4e19fa -- v2/`: 13 files, +1,393/−167)

| Piece | Where | State (MINE unless noted) |
|---|---|---|
| Ten opcodes in the primitive table | `v2/ast.lisp:146–155` | Present; table has 37 entries. |
| Opcode index remap | `v2/ast.lisp:283–300` | A hack with literals 27, 8, 35: old primitives keep 0–26, the first eight library functions keep 27–34, new primitives start at 35. Preserves old bit prices; makes new primitives dearer than library functions. Contradicts "opcode numbering is a non-constraint". |
| `:iota`, `:where` | `v2/vm.lisp:262–263` | Work. `iota 4 → (0 1 2 3)`; `where 3 (1 3 2 3) → (1 3)`. |
| `:tabulate`, `:evolve` | `v2/vm.lisp:358–382`, `:400–426` | Work in the VM as resumable continuations for total literal bodies. The body's environment is only the index (and state), so outer values must be spliced in through `:code-subst`. Declined by closures (`v2/vm.lisp:603`). |
| Totality for `:tabulate`, `:gather` | `v2/ast.lisp:1093`, `:1129` | **Crash** for any body that is a code variable or not already total: `(var -1 :int)` and `(var -2 :int)` fail the non-negative-id assertion. Also special-cases one syntactic shape, `(code-subst 'lit (tuple 'X0 …))`. |
| `:code-arity`, `-var`, `-var-id`, `-quote`, `-value` | `v2/vm.lisp:180–200` | Work; quote/value round-trips. |
| `:code-anti-unify` | `v2/vm.lisp:201`, `v2/unify.lisp:75` | Works: `(+ x0 1)`, `(+ x0 2)` → `(+ x0 x1)`. Errors if the output scope lacks a slot per hole. A wrapper over the host function, prepaid at base + w1·w2. |
| Difference facts | `v2/ast.lisp:835–950`, `condition-facts` | Work on smoke tests; old totality tests pass. Two-step transitivity. Ad hoc cases for `(- A B)` and `mod`. |
| Learned-range hooks | `v2/ast.lisp:772–775` | Declared, read, never set. |
| Definedness guard | `v2/decompose.lisp:515–570`, used at `:695` | Works: `(/ x0 x1)` → `(not (= x1 0))`; `(at x0 (+ x1 x2))` → both bounds. Tried before separator search. |
| Fold rules for iota/tabulate/gather/evolve | `v2/requirements.lisp:367–460` | `fold-equal-gather` and `fold-equal-evolve` work. Everything touching `:tabulate` with a code variable is unreachable because construction crashes. |
| Memoized unfold, common-conjunct factoring | `v2/requirements.lisp:215–290`, `:704` | Present; exercised only incidentally by old tests. |
| Fixed-length sequence slots in `extract-allowed-values` | `v2/frame.lisp:126–215` | Present; product capped at 64. |
| Effective horizon, behaviour pruning, column evaluation | `v2/enumerate.lisp:59–124`, `:282–384`, `:658–715`, `:1094–1118` | Present behind flags no caller sets. With flags on by hand: correct answers, large savings (below). Cells are boxed `(status value error work)` lists and caches are `equal` hash tables keyed on whole expressions. |
| Container-cover proposals | `v2/proposals.lisp:248–440` | A 195-line host generator. Names `:positions`, `:map`, `:filter`; tries length deltas {0,1,2,3}; carries policy scores −14, −12, −13, −11, +2. This is the 22nd hand-written proposal generator, written under a plan whose Pass 2 was about not doing this. The `:tabulate` branches need `:tabulate` in the language, which nothing supplies. |
| `:pit`, `:ind1` accepted as checked evidence | `v2/evidence.lisp:66,71` | Widening of the trust set with no producer. |
| E3 exports | `v2/package.lisp:66–69` | Undefined symbols. |
| `op-props` | `v2/knowledge.lisp:119` | Unused slot. |

E2 flags enabled by hand (`scratchpad/docs-v2tex/e2flags.lisp`, GF(5), 25 rows, operators `+ *`; same best model in
every row):

| Benchmark | Flags | Work | Candidates kept | Wall |
|---|---|---|---|---|
| linear 61 | none | 182,181 | 649 | — |
| | prune | 31,457 | 91 | — |
| | column | 56,796 | 649 | — |
| | both | 17,168 | 91 | — |
| quadratic 70 | none | 2,687,984 | 9,889 | 0.08 s |
| | prune | 158,647 | 358 | 0.02 s |
| | column | 958,397 | 9,889 | 0.11 s |
| | both | 97,846 | 358 | 0.02 s |
| quartic 77 | none | 29,382,492 | 106,057 | 0.65 s |
| | prune | 372,602 | 670 | 0.03 s |
| | column | 11,097,838 | 106,057 | 1.02 s |
| | both | 248,113 | 670 | 0.03 s |

The effective-horizon flag changes nothing here (no large headers in this grammar). Caveats: a 5-element field
saturates its behaviours quickly, so these ratios flatter pruning; `plan_v2b` measured 38:1 over integers at 30
body bits. Successes drop from 10 to 1 because equal-behaviour alternatives are no longer returned.

Is the WIP tested? No new tests. Does it change outcomes? MINE: the E0b-2 audit on the WIP copy gives the same 64
solved/unsolved results as Stage 0.

Timeline. Stage 0 landed at 20:36. v2.3, which said "zero new VM opcodes", was committed at 20:58 and 21:12. The WIP
with ten new opcodes and the v2.4 text that justifies them were committed together at 22:17.

**Salvageable independently of the v2.4 design:**

1. Behaviour pruning and column evaluation in `enumerate.lisp`, after tests, an unboxed column representation, and
   a decision on what "exhaustion" then means.
2. `definedness-guard-for-expr`, and the same idea at `consolidate.lisp:1473`.
3. Difference facts, after removing the negative-id variables and the shape-specific cases.
4. `fold-equal-gather` (index frames as slicing) and `fold-equal-evolve`.
5. `:iota`, `:where`, and the VM continuations for `:tabulate` and `:evolve`.
6. The `:code-*` duals and the anti-unify wrapper, if a consumer appears.
7. The fixed-length sequence case in `extract-allowed-values`.

**Not salvageable as written:** `container-cover-decompositions`; the opcode index remap; the evidence-grade
widening; the dangling exports.

---

## 7. Experiments the plan proposed

From `plan_v2.tex:776–804`.

| ID | Content | Gate | State |
|---|---|---|---|
| E0a | Six soundness and sandbox fixes | Tests pass | Done, verified |
| E0b | Gate host fold rules and descriptor synthesis; strip whitelists and schemas | Measure survival | Done, verified, extended below |
| E1 | Symmetric VM, container covers, memoized unfold, difference facts, range laws | Six index tasks of `plan_v2b` §3.2 plus `reverse`, `rotate`, `:solve-at-1` under 500k each; round-trip tests for every intro/elim pair | Partly coded; gate untested; crash on `:tabulate` |
| E2 | Behaviour table, column evaluation, effective horizon, lazy preparation | ≥10× fewer candidates at 30 body bits; preparation <25%; >3× on `quartic 77` | Coded behind flags. MINE: with flags forced on, `quartic 77` is about 20× faster in wall-clock with 158× fewer candidates on the flat benchmark search. The 30-body-bit and preparation-share gates were not measured, and nothing in hierarchical synthesis uses the flags |
| E3 | Law-activated AC, batch e-graph, replay guards, PIT, induction | 1,753 → ≤4 laws; 57-bit guard in <10k work; zero trusted axioms | Not started (exports only) |
| E4 | Meta `(:probe)`, code columns in the trace, 4-bucket attribution | Eliminates the three impostor classes; archives zero-utility entries without losing nogoods | Not started |
| E5 | Parameter-varying recursion, coupled hash-join, wake–sleep bootstrap, induce `functors.sexp` by anti-unification | All 8 batteries cold with no whitelist, `recursion-schemas.lisp` deleted, 0 hand-built ASTs, warm suite <15 s | Not started |
| E6–E8 | Build the clean-core store and Naive Bayes geometry beside the kernel | ≤1,100 LOC; passes M1–M4, E1–E5 and `tests/metrics.lisp` at the default Stage A budget | Not started |
| Stage 3 | Migrate module by module | Complexity and LOC fall at every commit | Not started; trend is upward |

**Cheap and decisive whatever the design:**

1. **Budget sweep of E0b-2.** Zero new code: the harness takes `:budget`. MINE, on the Stage 0 copy, description
   bound unchanged at 130 bits (`scratchpad/docs-v2tex/e0b_3p5M.log`, `e0b_35M.log`):

   | Regime | 350k | 3.5M | 35M | 350M |
   |---|---|---|---|---|
   | whitelist + schemas | 16 / 16 | 16 / 16 | 16 / 16 | not run |
   | whitelist, no schemas | 10 / 9 | 10 / 9 | 10 / 9 | not run |
   | full grammar + schemas | 10 / 9 | 12 / 10 | 12 / 10 | not run |
   | full grammar, no schemas | 9 / 8 | 11 / 10 | 11 / 10 | 12 / 10 |

   (solved / held-out sound, of 16; work units per spec.) At 10×: `positions` solves at 1,251,494 work and
   `seq-corr` at about 665,000; `scan` "solves" as an impostor in one regime. At 100×: no change. At 1000×
   (`e0b_350M_r4.log`, 278 s wall for the regime): `argmax-corr` "solves" at 35,667,327 work and is an
   **impostor**; `map-adjacent`, `scan`, `shift-seq` and `best-shift` each consume the full 350M and fail; `foldl`
   is an impostor at every budget. Held-out-sound survival without prosthetics is therefore 8, 10, 10, 10 across
   three orders of magnitude of budget. Throughput was 5.2–5.9M work per second, so one hour is roughly 2×10^10
   work and the largest run here is about one minute per spec, not hours.
   Reading: with v1's control structure, more top-level budget saturates between 1M and 4M work, and past that it
   buys impostors. The binding constraints are inside (Stage A frozen at 2,000 units, the fixed 130-bit bound,
   the proposal sources) and in the specs (under-determination), which agrees with the plan's "five cliffs"
   diagnosis and contradicts any hope that hours alone will do it. I did not vary the bound or the inner budgets,
   so this does not show that a restructured search would also saturate.
2. **Fix the higher-order specs** (vary the code argument over non-commuting functions) and re-run the harness.
3. **Turn the pruning flags on in Stage A and node search** and re-run E0b-2 and the Plan 8 probes. The code exists.
   This is the cheapest test of whether enumeration modulo behaviour moves any of the five stuck specs.
4. **Scale the Stage A budget with the job** (one constant) and re-run. Tests cliff 2 in isolation.
5. **Wire the totalized replay guard at `consolidate.lisp:1473`** and re-run the plan-9 divisibility case. The
   micro-claims are verified; the end-to-end claim (<10k work) is one edit away from a measurement.
6. **PIT on the four `:trusted-axiom` laws.** About 50 lines; a yes/no outcome.
7. **Measure one-edit behavioural density** I_L(p) before and after loading the library. Turns Q13 into a number.
8. **Law minimization on GF(3)^3**: count how many of the 1,753 laws survive derivability from the first k. Needs
   instantiation, not just congruence, so it is the least cheap of these.

Experiments that are *not* decisive regardless of design: E6–E8 (they test the store, not an assumption) and E4's
attribution protocol (it tests its own bookkeeping).

---

## 8. What survives, and why the document disappoints

### 8.1 Ideas worth carrying forward

Cheap, grounded in something measured here, and responsive to the owner's lens:

1. **The kernel audit** (`plan_v2.tex:229–290`): ten live defects, six host barriers to index frames, the
   provenance of the 52 library entries (2 unassisted, 21 via schemas, 10 from whitelisted micro-grammars, 19
   hand-coded). I verified its LOC and structural claims.
2. **Stage 0**: the fixes, the harness, and the survival number as the metric to move.
3. **Enumeration modulo behaviour**, with column evaluation as a secondary gain. The largest measured effect in
   scope, and the direct answer to margin M7.
4. **Index lift as preimage fibres of `gather`**: `(= (gather C Z) Y)` splits into `|Z| = |Y|` and
   `Z[j] ∈ {i | C[i] = Y[j]}`. This is the owner's "tuple slicing" intuition made operational, and it works in the
   WIP. `:where` is exactly the fibre as a value.
5. **Lift versus Split** (one program over all fibre rows, versus a guard and a program per region) and **Σ versus
   Π** inside "aggregate". Small, sharp distinctions for a uniform operation set.
6. **The T0–T4 ladder** as a curriculum and a diagnostic of where search fails (T4 today).
7. **Totality**: difference facts for variable indices; definedness guards derived from primitive preconditions;
   the totalized replay guard; host knowledge limited to primitive domains.
8. **PIT** as the second proof rule.
9. **Pricing discipline**: pay `bits(d) + bits(g)` with no symmetry refund; price each root row once; weight by
   1/|fibre|; first-appearance labels; stop residual peeling when bits stop falling.
10. **Invariants**: truth exact and geometry only ranks (M5); monotone store, non-monotone control outside;
    reflection staged at meta boundaries; policies never forge evidence.
11. **Two compute regimes**, plus the calibration that today's caps are about 60 ms per spec, and my result that
    raising only the outer cap saturates.
12. **Complexity scores as a gate** (M6), used honestly: they are rising.
13. **The trap list** of §3.1.

### 8.2 Why the owner finds it unsatisfying

- **It is unstable.** Four designs in four hours, each announcing the last one's soundness bugs. The VM opcode
  question was answered add, freeze, add. The geometry was answered four different ways. Nothing in the process
  suggests v2.4 is a fixed point; the owner's reaction to v2.2 was already "not sure if it can be directly
  implemented".
- **Its confidence is uncorrelated with evidence.** "100% Kraft-sound", "Verified v2.3 repair", "achieves full
  self-bootstrapping coverage at minimal complexity (~1,050 LOC core) with zero smuggled host algebra"
  (`plan_v2.tex:349`) describe a kernel that did not exist. The numbers that carry the argument (43×–110×,
  233 vs 3,044, 1,100 LOC) have no artifact. Where I could measure, the direction was sometimes right and the
  magnitude was not.
- **It is built from citations.** Sixty-five citation keys, five from 2026, several from workshops. In v2.1 they are
  components; by v2.2 half are warnings. The design that remains after the warnings is mostly the plan's own
  invention (slot-map handles, law-activated flags, top-8 mass, 4-bucket attribution, effective horizon), which
  is neither verified nor imported from anything that works.
- **The vocabulary is heavier than the content.** "Σ_u ⊣ Δ_u ⊣ Π_u", "partition-of-unity selector", "Naperian fiber
  lift", "stateful coalgebraic dual", "Čech obstruction" stand for group-by, re-index, all-agree, the branch a guard
  selects, map over indices, scan, and a conflict clause. The translation in §1 fits in a table.
- **There is no single small data structure.** The owner asked for one n-way graph on which substitution, lift,
  projection, fibre, anti-unification, partition, conservation, reorientation and residuals are uniform and
  re-entrant. The plan has five structs and half a dozen side tables, and its operations live in three places (VM,
  host fold rules, host proposal generators). "Lift as a synthesizer primitive" was met by adding opcodes for
  *evaluating* lifts; the inverse and the decision to lift remain host Lisp. Reorientation is a field in `grule`.
  Anti-unification over execution graphs, and algebra from depth-two experiments, each get one sentence.
- **The geometry is deferred**, on the authority of an older prompt, when the current prompt asks for it from the
  beginning.
- **The implementation contradicts the plan.** A plan about removing host proposal generators and hard-coded policy
  produced a new 195-line generator with five hard-coded scores. A plan with a falling-complexity ratchet produced
  +12% cognitive complexity. A plan claiming ~1,100 LOC for everything produced +1,226 LOC for part of two of
  five experiments, with no tests, dead flags, undefined exports and a crash on the main new opcode.
- **It answers a different question.** The document is a point-by-point reply to fifteen comparative questions about
  another plan, not a self-contained design. "Hours of search" appears as one paragraph added in an 11-line commit (`551f106`).
  The kernel doing the discovering, rather than agents, is measured (2 of 52) and then planned around with more
  agent-written host code.
- **It is hard to read.** 137 kB of dense LaTeX with bidirectional link badges, 64 stale version labels, and
  quantities repeated in abstract, thesis, tables, answers and pillars with small inconsistencies.

### 8.3 Cautions for `plan_v2c.md`

- Do not re-import anything in §3.1 without a new argument.
- Treat every LOC and speed-up figure in `plan_v2.tex` as unverified unless it appears in §2.2 or §6.
- The Stage 1 WIP in `v2/` should be mined for the seven pieces in §6.2, not continued.
- Any new design should name, for each of the owner's operations, where it lives (data structure, VM, synthesizer)
  and what small experiment on the existing kernel would show it earns its place.
- The cheapest informative work is in §7 items 1–6, and none of it needs a new store.

---

## Appendix A. Scratch artifacts

All under `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/docs-v2tex/`:

- `plan_<commit>.tex`: the six revisions of the plan.
- `stage1.diff`: `git diff 397499a a4e19fa -- v2/`.
- `test_head_kernel.log`, `test_head_milestones.log`, `test_stage0_kernel.log`: test runs.
- `smoke.lisp`, `smoke2.lisp`, `smoke3.lisp`, `smoke4.lisp`: opcode, totality, crash backtrace, divisibility guard.
- `e2flags.lisp`, `e2flags_q.lisp`: behaviour pruning and column evaluation with flags forced on.
- `stage0_audit_stage0.log`, `stage0_audit_head.log`: E0b audit on both copies.
- `copy_stage0/v2/experiments/stage0-budget.lisp`, `stage0-budget1.lisp`: budget-parameterized E0b-2
  (`E0B_BUDGET`, `E0B_REGIME`); `e0b_3p5M.log`, `e0b_35M.log`, `e0b_350M_r4.log`.

## Appendix B. Note on the working tree

An untracked `library/` directory (eight `.sexp` files) appeared in the repository root at 20:10:50–51 on
2026-11-24. It was not there in the session's opening `git status`. I did not create it: all my SBCL runs were in
the scratch copies, and none was running at that time (my kernel-test run ended at about 20:09:46 and the next
SBCL process started after 20:10:57). The one-second write pattern looks like a root `make bootstrap` by another
process. I left it untouched. `git status` now shows `?? library/` beside `GEMINI.md` and `notebook.zim`.
