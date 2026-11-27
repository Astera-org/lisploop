# `lisploop` — Plan 9: Closing Heuristic Induction, Homoiconic Conditional Propagators, and Geometric-Topological Unification

> **Status:** Architectural audit and implementation specification (v2.0 — revised incorporating empirical findings from `plan9-audit.md`), 17 November 2026.
> Grounded in the Common Lisp kernel on branch `charlie` at commit `019736f` (25 pure-kernel modules in `load.lisp`, `15,157` LOC + 6 milestone modules in `milestones/load.lisp`, `1,585` LOC; `182` kernel tests / `418,400` checks and `40` milestone tests / `186,771` checks passing), cross-referencing `plan9-audit.md`, `plan8.md` (§5, §6.4–§6.7, Appendices A–C), `prompt4.md`, `architecture2.md`, `plan7/plan7.md`, `plan7/plan7-recursion.md`, `plan7/plan7-higher-order.md`, `plan7/plan7-library.md`, `plan7/plan7-m9-policy.md`, and `tests/README.md`.

---

## 1. Verified Baseline, Existing Defects, & Empirical Audit Calibration (`019736f`)

### 1.1 Settled Plan 8 Baseline & Measured Probe Figures

Commit `1bfb69d` delivered and audited the core Plan 8 mechanisms:

- **Metric pullback & subterm sharing:** `pulled-back-metric` and `metric-invariant-under-decoder-p` (`frame.lisp:448-526`) pull a parent `frame-metric` through invariant or pure-child decoders, and `share-repeated-subterms` (`frame.lisp:708-831`) shares repeated compound subterms via `:code-eval`.
- **Coupled product joins & tuple set factoring:** Bounded coupled-slot pooling (`product-join-coupled`, `*max-coupled-slot-candidates* = 4`, `*max-coupled-combinations* = 256` in `synthesize.lisp:585-680`) and `fold-member-tuple` (`requirements.lisp:308-322`) split Cartesian tuple sets while screening cross-slot conjuncts.
- **Evidence grades & template generalization:** `:sampled` vs. `:exhaustive` attestation (`evidence.lisp:51-72`), evidence-gated `:unique-p` (`propagator-tested-p` in `laws.lisp:604-610, 787-793`), sampled integer solver replay (`lift-field-solvers` in `consolidate.lisp:513-652`), and non-lift `:decoder-template` anti-unification (`generalize-decoder-templates` in `proposals.lisp:1175-1236`) are live.
- **Homoiconic cleanups:** `simplify-symbolic-expr` (`laws.lisp:727-744`) normalizes via `fold-constants` plus library rewrite laws, `projection-row-keys` (`proposals.lisp:821-835`) enumerates compound input accessors in the VM, and `probe-values-for-type` (`descriptors.lisp:254-259`) centralizes scalar probe constants.

**Measured Pure-Kernel Baselines at `019736f` (`plan9-audit.md` §3 & Appendices B–C):**

- Irrelevant-input `:scan` (`plan8.md` §1.3 Probe 2 / Appendix A #5): **`34,067`** work at default budget.
- Symmetric tuple `:scan-tup` (`plan8.md` §1.3 Probe 4 / Appendix A #2): **`112,979`** work at default budget.
- Asymmetric conditional tuple `:scan-tup` (`plan8.md` §1.3 Probe 5 / Appendix A #3): **`264,353`** work at default budget (`253` bits).
- Partially observed `:scan-proj0` (`plan8.md` §1.3 Probe 7 / Appendix A #6): lifts with `rows = 3`, `coupled = 2` (unsolved; steps $t \ge 1$ remain coupled).
- Shifted-sequence metric task (`tests/metrics.lisp:214`, `plan9-audit.md` Appendix B): Stage A requires `12,377` work (`10,662` of which is VM `:heuristic-metric` execution of `:argmax-corr` + replay at `3,334` units per `metric-delta`); solves end-to-end at `:heuristic-budget 16000` in **`100,050`** work (`205,914` at `60000`).

**Capabilities Still Absent Relative to `main` (`plan8.md:323` & `plan8.md` §6.2):**

1. Co-induced `(:*` $\leftrightarrow$ `:/)` multiplicative metric decoder.
2. Conserved-sum / moment-difference heuristic solvers.
3. Bidirectional / rotating `:shift-seq` (`install-sequence-shift-metric` at `bootstrap-inverters.lisp:296-345` is forward-only and has zero kernel callers).
4. Certified transfer laws (`plan8.md:323`).
5. `:metric` keyword plumbing on top-level synthesis entry points (`start-synthesis`, `start-heuristic-synthesis`, `start-recursive-synthesis`).
6. Stage B pullback for `:code-edit` residuals (`plan8.md` §6.2; `code-edit` at `frame.lisp:1520-1561` is currently Stage A pricing only).

### 1.2 Confirmed Kernel Defects at `019736f` (`plan9-audit.md` §5 & §9)

1. **Totality Fixpoint Stale-Flag Soundness Bug (`knowledge.lisp:492-517`) & Undefined-Callee Totality (`ast.lisp:712-713`):**
   - `recompute-registered-functions-totality` (`knowledge.lisp:492`) iterates starting from existing `function-definition-total-p` and `conditional-code-params` flags instead of resetting non-oracle definitions to `(values nil nil)` first. Defining `g` total, defining `f` as `(g n)`, and redefining `g` as `(f n)` leaves both marked `total-p = T` so `(provably-total-p (f n))` returns `T` on a diverging mutual loop.
   - In `operator-step-total-p` (`ast.lisp:713`), `(or (null def) ...)` treats a call to a registered-but-undefined function name as total; it must require `def` to be present and proven total.
2. **Unsound Positional Zip in `check-library-nogood-schemas` (`nogoods.lisp:314-341`):**
   - `commit-synthesis-job` persists `:nogood-schema` entries for any lifted combinator (`consolidate.lisp:251-254`), and `check-library-nogood-schemas` then assumes call $i$ reads `seq-in[i]` and produces `out[i]`, which can falsely refute valid lifts of permuting decoders. Gating the positional zip on `function-body-length-preserving-p` (`abstraction.lisp:247`) restores soundness with zero extra VM work. *(Note: `nogoods.lisp:244` retaining `first-ng`'s `bindings` on `:uip-clause` is intentional and sound—Case 2 of `check-parent-nogoods` at `L380-392` re-derives `first-ng`'s conflict when sibling bindings agree, whereas clearing `bindings` breaks parent-scope binding equalities in `clause-expr-matches-known-p`.)*
3. **Member-Table Crash & Un-Memoized Incompressible Fits in `:relation` Consolidation (`relations.lisp:107-163`):**
   - `table-rows` (`relations.lisp:114`) destructures `(key value)` pairs and crashes on `:member` set relations (which store bare key lists). `first-order-table-p` must require `:functional` mapping tables.
   - Failed compression searches on incompressible tables are never memoized, re-spending `100,000` work on every subsequent `consolidate-knowledge-library` call. Recording `:fit-attempted-snapshot` against `(knowledge-statement-snapshot entry)` eliminates repeat work.
   - Note that `relations.lisp:156` (`(null (knowledge-entry-expression entry))`) deliberately skips hybrid `(base + residual)` relations because `condense` replaces the entire table (`relations.lisp:140-150`); fitting missed rows alone would overwrite `base` on rows `base` already got right (`plan9-audit.md` §4.7). Condensing hybrid relations requires synthesizing a guarded patch `(if guard patch base)` over *all* known rows (§4.4).
4. **Two-Call Consolidation Dependency Cycle (`consolidate.lisp:956-963`):**
   - Today `:consolidate` hooks run once before `retype-knowledge-laws` and `lift-field-solvers`: lifting `GF(5)`/`GF(7)` solvers to `:int` requires a *second* `consolidate-knowledge-library` call before `:functor` sees the lifted `:int` solvers, whereas moving `retype` and `lift` unconditionally before hooks leaves `:motif`-emitted laws un-retyped until a second call (`plan9-audit.md` §4.7). Putting hooks (`:function` 10, `:relation` 25, `:decoder-template` 40, `:functor` 40, `:motif` 45), `retype-knowledge-laws`, and `lift-field-solvers` inside a bounded convergence loop fixes both in a single call.
5. **Lift Templates Excluded from Generalization (`proposals.lisp:1191`):**
   - `generalize-decoder-templates` filters on `(not (getf meta :lift-p))`, skipping every template remembered from a higher-order library-lift win. *(Meanwhile, `:register-templates-p nil` in `commit-synthesis-job` at `consolidate.lisp:214` must remain default until learned-template retrieval is descriptor-gated so `unamortized-library-entries-are-archived` at `tests/theories.lisp:210-211` and warm budgets in `plan7/plan7-m9-policy.md:21` do not regress.)*
6. **Disconnected M8D Return Target & MDL Overwrite (`consolidate.lisp:5-56`, `synthesize.lisp:458`):**
   - `synthesis-episode-returns` (`consolidate.lisp:5-18`) is never called by kernel consolidation; `make-search-trace-frame` regresses a synthetic formula `f0 + 2*f1 + work/64 + (solved ? 0 : 10)` and `node-priority` (`synthesize.lisp:458`) *replaces* the analytical full-path MDL price with that raw prediction instead of adding a bounded learned residual around MDL.

### 1.3 Confirmed Unwired Seams & Empirical Guardrails from `plan9-audit.md`

Five kernel mechanisms are built and tested in isolation but not yet wired into synthesis or consolidation:

1. `induce-row-order` and `with-induced-row-order` (`proposals.lisp:853-964`, called only in `tests/topology.lisp`).
2. `frame-addressed-entries` (`descriptors.lisp:691-712`) and `find-knowledge-entries-by-address` (`knowledge.lisp:264-270`).
3. `orient-conserved-quantity` (`laws.lisp:850-911`).
4. `install-sequence-shift-metric` (`bootstrap-inverters.lisp:296-345`).
5. Contrastive `:descriptor` synthesis (`consolidate-policy-descriptors` at `consolidate.lisp:329-366` only nudges existing clause weights $\pm 1$).

At the same time, replay experiments in `plan9-audit.md` (§4 & Appendices A–C) establish **four concrete design guardrails** that v2.0 strictly respects:

- **Guardrail 1 (No per-quantum bucket/score Stage A cutoff):** Replaying Stage A in `2,000`-work quanta shows that the winning node on conditional tuple scan has bucket counts `4 5 5 5 8 8 11 13`—stalling across intermediate bit-tiers at `q3`–`q4` before reaching bilinear combinations at `q8`—while dead arity-3 lifts steadily add buckets through `q7`, and metric-heavy tasks yield `0` models in `q1` (`3,334` work per candidate). Keep `stage-a-budget` (`synthesize.lisp:363-380`, including the recursive-child $2\times$ and lifted-only `(max 1 (1- arity))^2` multipliers from `plan8.md` §6.4.7) intact.
- **Guardrail 2 (Keep narrowing fallbacks on the active reserve, not `deferred-proposals`):** Pushing `add-fallback-sibling` (`synthesize.lisp:736-746`) onto `synthesis-node-deferred-proposals` reverses `plan8.md` §6.7, places narrowing rescues behind up to 256 partial/template fallbacks, and breaks `an-ambiguous-narrowing-is-rescued-by-its-fallback`. Keep narrowing fallbacks as active siblings reached by the 1-in-$4|A|$ rotated reserve (`synthesize.lisp:934-937`).
- **Guardrail 3 (Keep host `+` subtraction fast-pathed):** Serving integer `+` through VM `metric-delta` would charge VM solver + replay steps on every missed row of every integer task and violate `(null (metric-decoders :int))` on a clean library (`tests/metrics.lisp:168`). Keep `correction`'s host subtraction (`frame.lisp:1494`) and `make-additive-residual-decoder` (`decompose.lisp:13-25`, tested in `tests/refactor.lisp:545`) as the zero-VM-work baseline, using `:metric-decoder` strictly for library-installed non-additive charts.
- **Guardrail 4 (Build & benchmark learned replacements *before* retiring host builders):** Today, removing `filter-map-decompositions` breaks H2 filter-map (`proposals.lisp:389`), and anti-unifying unary witnesses alone yields `(map Y ?code)` rather than the `:code-match`/`:code-bind`/`:code-subst` meta-program in `build-functorial-map-inverter`. Build and measure the homoiconic replacements alongside existing code first, and execute retirements in a separate gated step (`P9.3b`).

---

## 2. Unifying Around the Two Mathematical Motifs

### 2.1 Motif I: Topological Projection, Pullback/Lift, and Fiber Calculus

Every structural step in `lisploop` acts on the **input-requirement bundle** $\mathcal{E} \to \Omega$:

1. **Projection ($\pi: \Omega \to \mathcal{V}$):** Quotienting coordinates (`project-frame-rows` at `frame.lisp:1287`, `orient-available` at `frame.lisp:1302`) or partitioning rows into behavioral equivalence classes (`observation-bucket` at `enumerate.lisp:594`).
2. **Pullback & 1-to-Many Lift ($d^*: A_\omega(Y) \mapsto B_{\omega,c}(Z)$):** Pulling parent requirements through $Y = d(X, Z)$ (`pullback-frame`, `product-slot-frame`, `lift-frame` in `frame.lisp:528-1208`). Note that `lift-frame` constructs the full call-site cover by requirement folding, whereas `probe-frame-coordinates` (`frame.lisp:1045-1105`) folds only targeted output coordinates (default `(0)` and `(1)`) for lightweight partial-lift checks.
3. **Fiber Narrowing (Conditional Propagators):** Intersecting pulled-back requirements $B_{\omega,c}(Z)$ with guarded inverse preimages (`propagate-requirements` in `laws.lisp:680-723`, `solve-equality-symbolically` in `laws.lisp:746-806`).
4. **Fiber Separation / Sectioning:** When $\pi(\omega_1) = \pi(\omega_2)$ (or lifted call sites) collide on child inputs with incompatible requirements $B_1 \wedge B_2 = \bot$, either recording a deductive `nogood-clause` (`nogoods.lisp`) or adjoining a separating context coordinate $\kappa(X)$ (`dip-repaired-decompositions` at `nogoods.lisp:505-545`, `dependency-expander` at `proposals.lisp:474-529`).

#### Concrete Motif-I Improvements

1. **Complete DIP Repair on Pure First-Order Projections (`synthesize.lisp:479`, `nogoods.lisp:181`):**
   `dip-repaired-decompositions` (`nogoods.lisp:514-515`) already accepts `(pure-projection-decomposition-p proposal)`, but `node-dip-repairs` (`synthesize.lisp:479`) and `collect-frame-nogood-clauses` (`nogoods.lisp:181`) both gate on `(decomposition-lift-p proposal)`. Admitting `pure-projection-decomposition-p` at **both** sites ensures all colliding input buckets on a failed projection `(:dependency f(X))` are collected at once so `propose-dip-context-bindings` synthesizes a single separator $\kappa(X)$ resolving all collisions simultaneously (essential since `:dip-repair` nodes are not repaired a second time, `nogoods.lisp:512-513`). Where the parent node already condensed non-empty Stage A `heuristic-buckets`, test those buckets as zero-cost candidate separators before enumerating fresh grammar terms.
2. **General Comprehension / Subsequence Lifting (Prerequisite to Retiring `filter-map-decompositions`):**
   `library-decompositions` (`proposals.lisp:300-395`) currently lifts a combinator `(C X_seq Z_code)` only when `X_seq` is a parent variable/FO-expression, missing `[f(x) for x in xs if p(x)]` unless `filter-map-decompositions` (`proposals.lisp:219-298`) runs. To express list comprehensions through general lifting:
   - Extend `generalize-decoder-templates` (`proposals.lisp:1175-1236`) to support `:lift-p t` outer/inner combinator compositions once observed, **and**
   - Add a general **two-combinator pipeline lift** for contracting sequence frames (`|Y| <= |X|` with `|Y| < |X|` on some row): when the library contains a length-preserving mapper $M$ (`function-body-length-preserving-p`) and a contracting selector $F$ (`:DESC/LEN-LE` + `:DESC/SUBSET-ELEMENTS`), propose the nested product/sequential composition $M(F(X, Z_{\mathrm{pred}}), Z_{\mathrm{map}})$ gated by monotone subsequence alignment on `probe-frame-coordinates` (`(0)` and `(1)`). Once verified to solve H2 filter-map (`tests/higher-order.lisp:193`) within existing budgets, `filter-map-decompositions` can be retired in `P9.3b`.

---

### 2.2 Motif II: Observed & Generated Geometries, Co-Induced Metrics, and Embeddings

| Space | Points | Observed Geometry | Generated / Library Geometry | Plan 9 Refinements |
| :--- | :--- | :--- | :--- | :--- |
| **1. Target Space $(\mathcal{Y}, d_{\mathcal{L}})$** | Values / ASTs $y \in \tau$ | Host `+` delta & structural `:tuple-delta` / `:seq-delta` / `code-edit` | Library `(:metric-decoder d q tag-bits)` + pulled-back `frame-metric` | Parallel `heuristic-packets` cache, `(vm-versions)` prepared execution, `:metric` kwarg, safe `(*, /)`, moment solvers, unified `:code-edit` pullback |
| **2. Row / Corpus Space $(\Omega, d_\Omega)$** | Rows $\omega \in \Omega$ or AST occurrences | Chain variation $\sum_{(u,v)} d_{\mathcal{L}}(y_u, y_v)$ vs. independent & star baselines | `:locality-key` embeddings $k: \mathcal{X} \to \mathbb{Z}^d$ | Lexicographic $\mathbb{Z}^d$ tuple keys; `:int`-filtered bucket union; consolidation-time registration; `:partition` vs. `:coordinate` corpus distance |
| **3. Concept / Library Space $(\mathcal{F}, d_{\mathcal{F}})$** | Active `:function`s & `:decoder-template`s | Probe I/O traces & job lift outcomes | `:descriptor` AST profiles & `compositional-index` | Error-safe descriptor verdicts; mandatory `:necessary` pruning before progressive empirical tiers; memoized contrastive separators for liftable competitors |

#### 1. Target Space $(\mathcal{Y}, d_{\mathcal{L}})$: Prepared Execution, Packet Reuse, & Missing Charts

- **Version-Safe Prepared Execution in `entry-executable` (`vm.lisp:73-85, 473-526`):**
  Cache `(validated-program . vm-versions-snapshot)` slots on `entry-executable` constructed via `start-program-validation` (`vm.lisp:76`) and refreshed whenever `(vm-versions)` (`vm.lisp:73`) changes. When `compile-ast-fn` returns `nil` (as on recursive or `:function`-calling entries like `:argmax-corr`), `eval-entry-slot` runs `start-validated-evaluation` (`vm.lisp:81`), skipping repeated `expression-type` static checks while preserving input `value-work` validation (`tests/amortization.lisp`) and exact VM step metering.
- **Zero-Allocation `metric-delta` & Parallel `heuristic-packets` Slot (`laws.lisp:1201-1213`, `condense.lisp:218-245`):**
  - Keep `heuristic-residual` strictly in its `(row-key . witness)` format (preserving `consolidate.lisp:292`, `decompose.lisp:78-84`, and all existing tests), and add a parallel **`heuristic-packets`** alist `((row-key . packet) ...)` on `heuristic-model` populated whenever `(null (frame-metric frame))`.
  - In `metric-delta`, skip forward replay when `(knowledge-evidence-current-p entry :witness)` holds; otherwise replay through a cached `(vm-versions)`-checked `validated-program` for `(app operator (var 0 type) (var 1 delta-type))` with zero fresh AST allocation. `metric-residual-decompositions` (`decompose.lisp:30-67`) consults `heuristic-packets` directly in Stage B instead of re-evaluating the solver.
- **Closing the Six `main` / `plan8.md` §6.2 Gaps:**
  1. **`:metric` keyword:** Accept `:metric` on `start-synthesis`, `start-heuristic-synthesis`, and `start-recursive-synthesis` (`decompose.lisp:559`), attaching it to the root frame via `derive-frame`.
  2. **Safe `(:*` $\leftrightarrow$ `:/)` metric decoder:** An integer multiplicative solver `(/ target pred)` has guard `(if (= pred 0) nil (= (* (/ target pred) pred) target))`. Because an unconditional Stage B pullback `Y = (* base(X) Z)` conflicts on any row where `base(X)` does not divide `Y` (`(= (* 'p Z) 'y)` is unsatisfiable), `metric-residual-decompositions` proposes an unconditional partial chart $d(\hat{\pi}(X), Z)$ **only when every constrained row** has either $\hat{\pi}(x_\omega) = y_\omega$ (assuming $d$ has a right-identity delta, e.g., `1` for `*`) or a replay-valid `metric-delta`; when a chart covers a proper non-empty subset of missed rows (`>= 2` rows), emit a **conditional chart proposal** `(if G(X) d(base(X), Z_hit) Z_miss)` using Path B2's guard finder!
  3. **Conserved-sum / moment-difference heuristic solvers (`plan8.md:323`):** Provide library-definable moment estimators for aggregate/sequence targets—specifically first-moment delta `(- (sum-seq target) (sum-seq pred))` paired with decoders such as head-adjustment `(cons (+ (at xs 0) delta) (tail xs))` or uniform-offset `(when (= (mod delta (length xs)) 0) ...)`—as conjectured `:metric-decoder` entries verified by forward replay.
  4. **Bidirectional / rotating `:shift-seq`:** Relocate `install-sequence-shift-metric` from `bootstrap-inverters.lisp:296-345` to `tests/support.lisp`, extending `:shift-seq` and `:best-shift` (enabled by §5.1 integer descent/ascent totality) to positive and negative shifts $k \in [-|xs|, |xs|]$ (both zero-padded shift and cyclic rotation variants). In `tests/metrics.lisp:214, 442`, tighten the `:heuristic-budget` override from `60000` to the measured `16000` (or test an explicit `:metric-witness-budget` cap separate from `:observation` budget).
  5. **Certified transfer laws (`plan8.md:323`):** When a `:motif` or domain isomorphism rests on `:exhaustive` or `:derived` premise laws over a finite type (or proved structural induction), attest the transferred law `:derived` (`evidence.lisp:54`) rather than `:sampled` so `as-rewrite-library` and `solve-equality-symbolically` can apply it without fallback.
  6. **Cross-Row Unified `:code-edit` Stage B Pullback (`plan8.md` §6.2):** Row-by-row `code-edit` (`frame.lisp:1520-1561`) against a non-constant $\hat{\pi}(X)$ can yield different edit paths on each row. Stage B `:code-edit` pullback therefore computes the **joint anti-unifier** of `{target_w}` (or checks that all rows' `(:code-edit paths fillings)` share a non-empty intersection of structural paths in $\hat{\pi}(X_\omega)$), emitting `:code-subst` over the shared hole tuple only when a single typed template covers every constrained row.

#### 2. Row & Corpus Embeddings ($\Omega \to \mathbb{Z}^d$)

- **Tuple `:locality-key` Support (`proposals.lisp:771-964`):** Allow `:locality-key` entries to target `:int` or flat integer tuples `(:tuple :int ...)`, ordering rows in `induce-row-order` by lexicographic `<` across tuple components (breaking ties via `canonical-row-order`).
- **Type-Safe Bucket Reuse in `induce-row-order`:** Because `heuristic-buckets` holds target-typed expressions (`enumerate.lisp:789-796`) and passing a non-nil `:buckets` currently suppresses `projection-row-keys` (`proposals.lisp:908`), change `induce-row-order` to **union** any `:int` / `(:tuple :int ...)` buckets passed in `:buckets` with `(projection-row-keys frame ledger)` whenever compound inputs are present.
- **No Mid-Search Frame Reordering or Library Mutation:** Calling `with-induced-row-order` inside node preparation would reorder `frame-rows` (invalidating positional bucket indices), add a hard `:distinct` endpoint edge, and mutate `*knowledge-library*` mid-search. Instead, keep row-order induction **pure during search** (recording discovered candidate keys on `synthesis-job` metadata without mutating `frame-rows` or `*knowledge-library*`), and register winning `:locality-key` entries strictly inside `consolidate-knowledge-library`. Leave `relational-linkage-residual` (`enumerate.lisp:597`) free of `:persistence` cliff penalties (`plan8.md` §6.4.15).
- **Explicit `:partition` vs. `:coordinate` Mode in `generated-space-distance` (`milestones/corpus.lisp:455-462`):** Scalar `:locality-key`s in existing corpus tests represent discrete class labels (e.g., parity), where `2 + rank-dist` keeps the locality window focused on `59` same-class pairs (`plan9-audit.md` §8.6). Preserve discrete class distance as default (`:metric-mode :partition`) and apply $L_1$ coordinate distance $|k_a - k_b|$ when a scalar `:locality-key` carries metadata `:metric-mode :coordinate` (matching $\mathbb{Z}^d$ tuple keys). Keep single-occurrence arity validation (`milestones/corpus.lisp:478`) as tested.

#### 3. Descriptors, Mandatory `:necessary` Pruning, & Contrastive Synthesis (`descriptors.lisp`, `consolidate.lisp`)

- **Error-Safe Descriptor Verdicts (`descriptors.lisp:200-252`):** Fix `evaluate-descriptor-entry-on-frame` so rows on which a descriptor's expression errors count against `:satisfied` (yielding `:neutral` unless all concrete pairs evaluate cleanly to `T`), preventing partial/out-of-bounds descriptors from spuriously scoring `:satisfied`. Preserve all 10 existing `:descriptor` concepts (`tests/library.lisp`).
- **Mandatory Tier-1 `:necessary` Pruning + Progressive Empirical Tiers (`proposals.lisp:345-365`, `descriptors.lisp:658-785`):**
  Never skip `:necessary` descriptors via an early survivor-count cutoff (on contracting frames, Tier-1 `:necessary` pruning refutes `:map` in `197` work!). Structure candidate scoring in `library-decompositions` in three strict stages:
  1. **Stage 1 (Exact signature + `:necessary` pruning):** Filter by `:type` compatibility and evaluate all current `:necessary`-attested `:descriptor` entries on the candidate set, hard-pruning any unary-FO `:function` returning `:violated`.
  2. **Stage 2 (Tier-2 empirical I/O descriptors):** When $\ge 2$ un-pruned entries survive, evaluate Tier-2 empirical `:descriptor`s `:describing` only the surviving IDs.
  3. **Stage 3 (Tier-3 contrastive separators):** Evaluated only when $\ge 2$ surviving entries remain within `8` policy-delta bits of the top scorer.
- **Memoized Contrastive Separator Synthesis for Liftable Competitors (`consolidate.lisp`):**
  - Record attempted liftable entries (`:library`, `:learned-template`) explicitly on `synthesis-job` (distinguishing genuine failed lift searches from scope-reuse followers, fixing `consolidate.lisp:362-366`).
  - For confusion pairs $(f_1, f_2)$ of **liftable higher-order combinators or `:decoder-template`s** (applied to shared probe step codes over rich unsorted/signed probe sequences `'(() (3) (5 1 -2) (-1 2 5) (4 4 1))`, not `probe-sequences-for-type`'s ascending-only lists), build a binary `(X, Y) -> :bool` frame and run `start-search` + `resume-search` (`bound = header + 72`, `work-limit = 20000`) using valid kernel operators (`:=`, `:<`, `:+`, `:-`, `:if`, `:at`, `:length`, `:cons`, `:tail`).
  - Record tested pairs `(id1 . id2)` (keyed by statement snapshots) on `knowledge-library` so repeated calls to `consolidate-knowledge-library` never re-run failed separator searches (preserving 1-call fixed-point). Contrastive descriptors attach via `:describes` edges at `:tier 3` without altering the 5-slot compositional address symbol.

---

## 3. Homoiconic Conditional Propagators in `*knowledge-library*`

### 3.1 Kernel-Native Conditional Solver Discovery (`induce-conditional-solvers` in `laws.lisp`)

Add `induce-conditional-solvers(operator-or-fn &key positions library (work-limit 40000) ledger)` to `laws.lisp`:

1. **Rich Solver Probe Grid (`solver-probe-values-for-type`):** Unlike `probe-values-for-type` (`descriptors.lisp:254-259`, which returns only `(0 1)` on `:int` and `nil` on sequences/tuples—where `(* X0 Z) = Y` degenerates to witness `Y` and guard `t`), `solver-probe-values-for-type` supplies `(-3 -2 -1 0 1 2 3)` on `:int`, full elements up to $|D| \le 13$ on `(:gf p)`, small cartesian tuples, and diverse sequences `'(() (0) (2) (-2 3) (0 4 -2) (1 2 3))`.
2. **Fiber Frame & Witness Synthesis:** Evaluate forward calls $f(X) = y$ across bounded probe grids, grouping by known context $c = (X_K, y)$ into empirical fibers $F(c) = \{X_P \mid f(X_K, X_P) = y\}$. Construct a child `frame` with `set-requirement` (`frame.lisp:152`) over non-empty fibers $F(c)$ and synthesize a typed witness $W(X_K, Y) : \tau_P$ via `start-heuristic-synthesis` + `resume-synthesis`.
3. **Replay-Exact Guard Synthesis:** Partition probe contexts plus counterfactual targets $(X_K, y')$ into contexts where $f(X_K, W(X_K, y')) = y'$ holds vs. fails/errors, and run `start-search` + `resume-search` (`bound = header + 56`) for a Boolean guard $G(X_K, Y)$ in the kernel's native `:if`/`=`/`<`/`/`/`*` grammar (e.g., `(if (= X0 0) nil (= (* (/ Y X0) X0) Y))` for integer division).
4. **Evidence Attestation:** Run `certify-solver-entry` on finite domains ($\le 65,536$ assignments $\to$ `:exhaustive` current evidence) and `sampled-solver-validations` (`consolidate.lisp:513-558`, extended to sequences and tuples via `solver-probe-values-for-type` $\to$ `:sampled` evidence, which retains `propagation-fallback` on `:int` and sequences) on infinite domains.

### 3.2 Law-to-Solver Extraction (`induce-law-solvers`) & Staged Retirement of `bootstrap-inverters.lisp`

1. **Exact Preconditions & Bijectivity Rules for `induce-law-solvers` (`laws.lisp`):**
   Given an active tested `:law` (`knowledge-evidence-tested-p law :equivalence`) with guard $G(\vec{v})$ and equation `(= (op A_0 ... A_{m-1}) v_t)` (or symmetric orientation):
   - **Preconditions:** (a) Target $v_t$ is a variable in $\vec{v}$; (b) for inverted position $\mathrm{pos}$, every other argument $A_j$ ($j \neq \mathrm{pos}$) is a **distinct** variable $v_{k_j} \notin \{v_t\}$; and (c) $\mathrm{FV}(A_{\mathrm{pos}}) \cup \mathrm{FV}(G) \subseteq \{v_t\} \cup \{v_{k_j}\}_{j \neq \mathrm{pos}}$. *(Laws whose context positions hold compound expressions like `(- 0 K)` are handled only if rewrite/solver inversion first re-parameterizes `K' = (- 0 K)`.)*
   - **Evidence Attestation (`evidence.lisp:44-49`):** Certificates bind to their own entry's snapshot and cannot be copied; instead, attest the induced `:solver` with method **`:derived`** when `(knowledge-evidence-current-p law :equivalence)` holds (recording `(:induced-by law-id)`), or `:sampled` when the law's evidence is sampled.
   - **Uniqueness Preservation:** A single left-inverse law $f(W(y)) = y$ proves surjectivity (`:witness`), not injectivity (`:uniqueness`). However:
     - When `op` is unary, $G = \text{'t}$, and $A_0 = (\text{op } v_t)$ (an unguarded involution $f(f(x)) = x$), $f(z) = y \implies f(f(z)) = f(y) \implies z = f(y)$ algebraically guarantees injectivity! Thus `induce-law-solvers` attests `:derived` `:uniqueness` as well as `:witness` on certified unguarded involutions—matching `induce-involution-solvers` (`bootstrap-inverters.lisp:147`) with zero extra fallback.
     - More generally, when a dual left-cancellation law `G' => (= (W_op ... (op ... z ...)) z)` is also certified in `library`, attest `:derived` `:uniqueness` too.
2. **Keeping `:transformer` Live & Measuring Before Retiring `bootstrap-inverters.lisp`:**
   - Retain `induce-solvers-from-transformers` (`templates.lisp:247-272`, tightened to verify source operator match and instantiate source guards) so `:transformer` keeps its consumer.
   - Relocate `install-sequence-shift-metric` (`bootstrap-inverters.lisp:296-345`) immediately to `tests/support.lisp`.
   - Keep `bootstrap-inverters.lisp`'s functorial/pointwise builders (`L6-293`) in `P9.3a` while benchmarking `induce-conditional-solvers` + `induce-law-solvers` on all H4 and L2–L4 tasks; retire the remaining host builders in `P9.3b` once every `tests/library.lisp`, `tests/higher-order.lisp`, and `tests/audit.lisp` assertion passes at comparable budgets.

### 3.3 Sound Set Propagation, Solver-Aware Folding, & Symbolic Unwinding (`laws.lisp`)

1. **Single-Unknown Finite-Set Propagation Respecting Evidence Grades (`laws.lisp:582-723`):**
   - Extend `extract-equality-target` / `solve-learned-equality` to handle `(member term '(c_1 ... c_m))` for **single-unknown** applications (`(= 1 (length open))`) and $1 \le m \le 8$ (capping the resulting union at $\le 8$ elements at every unwinding depth so set size cannot blow up exponentially, and avoiding multi-unknown tuple unions which do not factor into a conjunction).
   - For each $c_i$, run the matching `:solver`: if all $m$ targets solve via rules with **current** `:witness` and `:uniqueness` evidence (`propagator-evidence` returning `(values t t)`, e.g., certified solvers over `(:gf p)` or `:bool`), rewrite to `(member unknown '(w_1 ... w_r))` with no fallback. On `:int` or sequences—where uniqueness/witness evidence is `:sampled` or conjectured—rewrite in `propagation-frame` while **always preserving `propagation-fallback`** (`laws.lisp:720-722`, Invariant 3).
   - *(Note: We drop list-valued `:fiber-set-p` witnesses on `:solver`, which violate `validate-solver-shape` at `laws.lisp:1049-1052` and break downstream consumers, and omit sign-dependent inequality propagation.)*
2. **Solver-Aware Single-Pass Folding & Typed Rule Indexing:**
   - Index `propagator-library` rules by `(list (arithmetic-propagator-operator rule) (solver-positions (arithmetic-propagator-position rule)))` (using the **full typed operator AST**, `laws.lisp:669`), sorted within each bucket by evidence grade `(certified+unique > certified > sampled+unique > sampled > conjecture)`. *(Note: indexing changes `:propagator-dispatch` work counts slightly relative to full linear scans; record before/after work deltas explicitly.)*
   - If `callable-rules-library` is unified into single-pass folding via `:preserve-operator-p`, match both the full operator and open argument positions—and whenever `solve-learned-equality` fails to rewrite a preserved call, **immediately run ordinary call unfolding** on it so conflict detection and witness extraction are never lost.
3. **Fallback-Safe Intermediate Simplification & Guarded `orient-conserved-quantity` (`laws.lisp:746-911`):**
   - In `solve-equality-symbolically`, attempt `simplify-symbolic-expr` on `expression` before unwinding each level, **but retain the unsimplified `expression` as fallback** whenever simplification duplicates `target-id` into $>1$ argument positions (`plan9-audit.md` §8.5).
   - Wire `orient-conserved-quantity` into relational/invariant synthesis; when symbolic unwinding yields `(values sym-expr guards certified-p)` whose `guards` hold on a non-empty proper subset of constrained rows, propose the guarded Stage B branch `(if guard sym-expr Z_boundary)` alongside the numeric `conserved-quantity-frame` fallback.

---

## 4. Search Control, Subtree-Grounded M8D Residuals, & Consolidation

### 4.1 Follower-Safe Pruning, Soft Priority Parking, & Anytime-Safe Stopping (`synthesize.lisp`)

1. **Follower-Safe Incumbent Filtering (`synthesize.lisp:681-704, 819-826`):**
   Never tighten a canonical node's `synthesis-node-bound` in-place via its own outer decoder overhead when followers share its `search-job` (`follow-canonical-node` at `synthesize.lisp:780-795`), as a follower with a cheaper outer path needs larger child candidates. Instead:
   - Filter composed root models at `enqueue-node-candidate` (`synthesize.lisp:681`) against the current verified incumbent score `J* = (candidate-score (synthesis-job-best job) run-weight)` before paying root verification work, and
   - Close a node (`:phase :done`) only when `(full-path-minimal-bits node)` exceeds `J*` for `node` **and every follower** in `(synthesis-node-followers node)`.
2. **Soft Priority Parking (Preserving Invariant 3 & `max-depth`):**
   Compare *per-parent-row normalized* analytical MDL (`full-path-program-bits + normalized-residual-bits`, excluding `node-policy-score`, coupled-requirement penalties, learned $\hat{\Delta}$, and multi-call row-count inflation on lifted frames). Rather than marking `expansion :done` irreversibly, add a soft priority penalty (`+16` bits) to branches that worsen normalized analytical MDL twice in a row—parking them behind improving branches while keeping them reachable on the 1-in-4 reserve.
3. **Structural-Node-Aware Deferred Promotion (`synthesize.lisp:856-863, 983`):**
   When `*max-eager-proposals-per-node*` is bounded (e.g., `4`), exclude `structural-node-p` children (whose `node-price` is `(min own parent)`, `synthesize.lisp:889-896`) when testing whether a parent's eager non-structural proposals have all closed or scored worse than the parent's baseline. Add a dedicated multi-combinator library starvation test verifying that deferred proposals wake promptly.
4. **Anytime-Safe Marginal Stopping (`resume-synthesis`, `synthesize.lisp:1148-1180`):**
   Record `work-at-last-improvement` on `synthesis-job` whenever `synthesis-job-best` improves. Under optional `:marginal-search-weight` $\lambda_{\mathrm{search}}$, halt once `(synthesis-job-best job)` exists and `(* lambda-search (- (ledger-total ledger) work-at-last-improvement))` exceeds `(candidate-score best)` minus the analytical lower bound of open enumeration frontiers. Because `work-at-last-improvement` lives on `synthesis-job` rather than a local `resume-synthesis` call window, 1-unit vs. 97-unit `check-anytime-resumption` parity holds identically.

### 4.2 Subtree-Grounded M8D Residual Priority Predictor (`consolidate.lisp:5-89`, `synthesize.lisp:408-465`)

1. **Well-Defined Per-Node Realized Cost (`make-search-trace-frame`):**
   For each prepared node $n$ with Stage A model $h_n$ in a completed `synthesis-job`:
   - Let $J_{\mathrm{win}}(n)$ be the minimum verified root `candidate-score` among verified candidates whose ancestor path passes through $n$ (or `nil` if $n$'s subtree produced no verified root candidate), and let $W_{\mathrm{sub}}(n)$ be total search + preparation work expended in $n$'s subtree.
   - Define realized node outcome $J_{\mathrm{real}}(n) = \min\big(B_{\mathrm{MDL}}(n) + 48,\; (J_{\mathrm{win}}(n) \text{ or } (B_{\mathrm{MDL}}(n) + 24)) + \lfloor W_{\mathrm{sub}}(n) / \text{work-scale} \rfloor\big)$, and set the regression target to the **signed residual** $\Delta^*(n) = \mathrm{clamp}(J_{\mathrm{real}}(n) - B_{\mathrm{MDL}}(n), -24, +48)$ over the 6-feature vector `(full-program-bits residual-bits depth constrained-rows policy-score coupled-count)`.
2. **Additive Deployment Around Analytical MDL (`node-priority`):**
   In `node-priority` (`synthesize.lisp:453-465`), compute analytical $B_{\mathrm{MDL}}(n)$ first and add `(clamp predicted-delta -24 48)` when a predictor is active. An uninformative predictor (`0`) leaves exact MDL ordering untouched.

### 4.3 One-Call Consolidation Convergence & Total-Batch Levin Amortization (`consolidate.lisp`)

1. **Bounded Convergence Loop (`consolidate.lisp:956-963`):**
   Inside `consolidate-knowledge-library`, run a bounded loop (up to `3` passes, stopping early as soon as a pass adds zero entries and zero new edges):
   - Execute `:consolidate` hooks in priority order (`:function` 10, `:relation` 25, `:decoder-template` 40, `:functor` 40, `:motif` 45).
   - Run `retype-knowledge-laws` across `retype-domains`.
   - Run `lift-field-solvers`.
   This resolves both `lift-field-solvers -> :functor` and `:motif -> retype-knowledge-laws` in **one** `consolidate-knowledge-library` call.
2. **Hybrid `:relation` Patch Condensation (`relations.lisp`):**
   Keep Pass 1 & Pass 2 on pure `:functional` tables (gated against `:member` tables and memoized on failure per §1.2.3, keeping Pass 2's tested copy-cost gate `tests/audit.lisp:369-382`). For hybrid `:relation` entries carrying both `base = knowledge-entry-expression` and `residual` (`consolidate.lisp:290-304`), only replace `(base + residual)` when a synthesized guarded expression `(if G(X) patch(X) base(X))` matches **both** all residual points *and* probe evaluations of `base` off the residual keys at strictly lower total bit size than `(knowledge-entry-bits entry)`.
3. **Total-Batch Logarithmic Search Tariff (`amortize-library-entries`, `consolidate.lisp:422-475`):**
   Taking $\log_2$ *per lift* overcharges many cheap failed lifts ($100 \times 100$ work $\to 700$ bits vs. linear `10`, `plan9-audit.md` §4.7). Support optional `:cost-model :levin` on lifted `:function`s using **one logarithm over the entry's total failed search work in the batch plus the per-proposal count**:
   $$\text{debt}(\text{entry}) = N_{\text{failed-proposals}} + \lceil \log_2(1 + W_{\text{failed-search}}) \rceil$$
   preserving nonzero debt when a lift conflicts before starting search (`tests/theories.lisp:187`) while preventing a single $10^6$-work exploration from permanently bankrupting a useful combinator (`21` bits instead of `977`).

---

## 5. Open Frontiers (`plan8.md` §5.1–§5.5 & Appendices B–C)

### 5.1 Static Totality Generalization (`ast.lisp:721-868`) & Homoiconic `(:fix-seq fuel init step)`

#### A. Sound Rank-Environment Totality Analyzer (`ast.lisp:700-868`)
First apply §1.2.1's soundness fixes (`recompute-registered-functions-totality` reset + `ast.lisp:713` non-nil `def` check). Then generalize `non-empty-vars` into a rank environment $\Gamma$ tracking proven parameter bounds:

1. **Multi-step sequence guards & element access (`(:seq-len>= k)`):**
   - Starting from $\Gamma(X_i) = 0$: if $\Gamma(X_i) \ge k$, then `(= (tail^k X_i) ())` is itself total to evaluate (`(tail^k X_i)` requires length $\ge k$), and its **false branch** establishes $\Gamma'(X_i) = \max(\Gamma(X_i), k + 1)$. Likewise `(< 'm (length X_i))` ($m \ge 0$) establishes $\Gamma'(X_i) = \max(\Gamma(X_i), m + 1)$ in its true branch.
   - **Step & access definedness:** Under $\Gamma(X_i) \ge L$, `(tail^d X_i)` is total for $1 \le d \le L$, and `(at (tail^j X_i) 'r)` is total whenever $r \ge 0, j \ge 0,$ and $r + j < L$ (so `pairwise` accessing `(at X 0)` and `(at (tail X) 0)` and recursing on `(tail (tail X))` under nested `(= X ())` and `(= (tail X) ())` guards is certified total!).
2. **Per-Slot Sum & Lexicographic Termination Measures (`merge`):**
   - At every recursive self-call `(self a_0 ... a_{m-1})`, compare `a_p` **strictly against parameter $X_p$ of the same slot $p$** (never matching `(tail ys)` in `xs`'s slot!): record $\Delta_p = -1$ if $a_p = (\text{tail}^d\; X_p)$ with $1 \le d \le \Gamma(X_p)$, $\Delta_p = 0$ if $a_p = X_p$, and $\Delta_p = +\infty$ otherwise.
   - Certify termination when there exists a non-empty subset $S \subseteq \{0,\dots,m-1\}$ such that at every self-call site, $\forall p \in S: \Delta_p \le 0$ and $\exists q \in S: \Delta_q = -1$ (sum measure $\sum_{p \in S} |X_p|$, certifying `merge(xs, ys)`), or a lexicographic order on $S$.
3. **Bounded Integer Descent & Ascent:**
   - **Descent:** If a single constant integer lower bound $b$ guards all recursive sites for integer parameter $X_p$ via `(< 'b X_p)` in $\Gamma$, then `(- X_p 'c)` for any literal $c \ge 1$ strictly decreases $\max(0, X_p - b)$. For integer halving `(/ X_p 'd)` ($d \ge 2$), require $b \ge 0$ (`(< '0 X_p)`), since negative integers stick at `0` under truncating division (`plan9-audit.md` §8.7). Never license descent from `(not (= X_p 0))` alone.
   - **Ascent (for negative shifts counting up to `0`):** Under a uniform upper bound `(< X_p 'b)` in $\Gamma$, `(+ X_p 'c)` ($c \ge 1$) strictly decreases $\max(0, b - X_p)$.
4. **Closed `:code-eval` Beta-Redex Inlining in Analyzer:**
   When `walk` encounters `(code-eval (lit (:code ...) body) arg_0 ... arg_{r-1})` where every `arg_j` walks cleanly under $\Gamma$, check `body` with each parameter mapped to `arg_j` (preserving outer $\Gamma$ bounds on parameters passed through as `(var id)`).

#### B. Homoiconic `(:fix-seq fuel init step)` & Two-Variable Instantiation (`proposals.lisp`, `templates.lisp`)

- With closed `:code-eval` beta-inlining in `analyze-function-body-totality`, the 3-parameter library `:function` `:fix-seq` (`fuel : (:seq alpha)`, `init : sigma`, `step : (:code ((0 . sigma)) sigma) -> sigma`) evaluates `(code-eval step state)` **once** per round and is certified conditionally total on parameter `2` (`step`) automatically.
- **Instantiation in `candidate-library-definitions` (`proposals.lisp:40-62`):** `retype-function-definition` (`templates.lisp:183-215`) already unifies independent template type variables (`in-elem` and `return-element-type`), so `(retype-function-definition :fix-seq '(:tuple :int :int) :return-element-type '(:seq :int))` already works; update `candidate-library-definitions` (`proposals.lisp:60-62`) so when `(= in-elem orig-elem)` holds on fuel while `(/= out-elem orig-out)`, `(retype in-elem out-elem)` is still invoked!
- **Two Separate Lifting Facts (`plan8.md` Appendix B.3 & `plan9-audit.md` §8.7):**
  1. *Certified zero-step inequality:* On any row with concrete `init` and singleton target `y != init`, `(if (= (code-eval step 'init) 'init) nil t)` holds unconditionally.
  2. *Conjectured stationary equilibrium (with fallback):* Because early convergence ($k < |\text{fuel}|$) cannot be proven from `(fuel, init, y)` alone, `(= (code-eval step 'y) 'y)` is proposed strictly as an **unverified conjectured narrowing** that retains the un-narrowed trajectory fallback.

### 5.2 Opt-In Bipartite Set Correspondence & Provably-Total `sort-by` (Appendix B.1–B.2)

1. **Strict Gating (`frame.lisp`):** Never run $O(N^2)$ elementwise corrections on ordinary ordered sequence tasks! Bipartite Hungarian assignment (`*max-bipartite-set-size* = 12`, metered on `ledger`) runs **only** when either:
   - The caller supplies an order-invariant set `frame-metric` (using `minimum-bipartite-correspondence` inside a library `:function` or metric AST; note `frame.lisp:1598` clamps non-equal misses to $\ge 1$ bit unless `(equal predicted target)` or set canonicalization precedes comparison), or
   - An explicit `:bipartite-seq-delta` `:metric-decoder` is installed in `*knowledge-library*` for tuple sequences `(:seq (:tuple ...))`—where any non-identity permutation pays $\ge 1$ tag + permutation bits (`0` bits iff `predicted` equals `target` in exact order, preserving `correction` invariants and gating strictly below replacement `value-bit-size`).
2. **Total `sort-by` Combinator & Consolidation-Time Key Harvesting:**
   Define `:insert-by` and `:sort-by` (`xs : (:seq alpha)`, `key : (:code ((0 . alpha)) :int) -> (:seq alpha)`) as standard library `:function`s (provably conditionally total on `key` via structural `(tail xs)` descent). Group matched element pairs per parent row when testing whether a monotone tuple projection `(at elem j)` orders target elements ascendingly, proposing `(:sort-by base key)` in Stage B without mutating `*knowledge-library*` during search.

### 5.3 Exact-Search Active Disambiguating Query Selection (`plan8.md` §5.3)

Add `propose-disambiguating-query(candidates &key inputs domain-guard (bound-slack 32) (work-limit 20000) ledger)` in `explain.lisp`:

- Because `(if (= e_1(X) e_2(X)) nil t)` is a non-membership relational predicate (`extract-allowed-values` returns `:unknown`, so Stage A witness condensation does not apply), construct a 1-row inputless `frame` whose target is `(:tuple tau_0 ... tau_{n-1})` (or scalar `tau_0` when unary) and solve via **exact `start-search` + `resume-search`**.
- When $|C| > 2$ candidates survive, run exact search to split the first pair $(e_1, e_2)$, evaluate all $e \in C$ on the discovered input $x^*$, and if desired prefer among the first $r \le 4$ enumerated splitting inputs the one maximizing distinct output count $|\{e(x^*) : e \in C\}|$.

### 5.4 Coupled Intermediate Fibers & Latent Trajectory Abduction (`plan8.md` §5.1)

`plan9-audit.md` §8.10 pinpoints why coupled/latent state synthesis cannot simply reuse `product-join`:

1. **Observation Regime Belongs to the Combinator Decoder:** `schema-availability-order` ranks whole input columns against the target. Whether step $t$ sees autonomous recurrent state $s_t$ (`:open-loop`, `:scan` / `:scan-proj0`) vs. observed prior output $y_{t-1}$ (`:prequential`, zipped window combinator) is encoded by **which higher-order combinator decoder** lifts the sequence.
2. **Partial Tuple-Projection Folding at $t = 0$ (`requirements.lisp`):** In Appendix A Probe 6 (`(:scan-proj0 actions '(0 0) step)`), row $t = 0$ has requirement `(= (at (code-eval step '(0 0) '1) 0) '1)`, whose `extract-allowed-values` is `:unknown` because component `1` of the returned tuple is unconstrained. Add a fold rule recognizing `(= (at Z 'j) 'v)` on a `:tuple`-typed target `Z`: under `product-slot-frame`, slot `0` receives the exact singleton requirement `(= Z_0 '1)` (`coupled = 0` at $t = 0$!), while slot `1` (`Z_1`, the latent accumulator update) remains coupled through $t \ge 1$.
3. **Trajectory-Screened Latent Synthesis (Dedicated Trajectory Join, Not `product-join`):**
   Because slot `1` has no decoupled $t = 0$ constraint, naive `product-join` would fill `*max-coupled-slot-candidates*` (`4`) with tiny constant expressions (`0`, `1`, `s_0`, `a`) and miss the true accumulator update. Instead, pair each candidate observed-slot expression `e_0` (solved from the decoupled $t = 0$ projection rows!) with bounded tiered enumeration of `e_1` screened directly by **multi-step VM rollout** of `(tuple e_0 e_1)` across the parent sequence rows (`trajectory-admissible-p`, metered on `ledger`). For flat `:scan` tasks that fail with dynamic state collisions (identical `(s_obs, a)` mapping to distinct `y'`), propose lifting `:scan-proj0` over `(:tuple tau :int)` initialized at `(tuple init 0)`.

---

## 6. Decoupled, Independently Testable Increments (`P9.1` – `P9.6`)

*(Execution order to be selected after review; each increment is small, self-contained, and anchored to measured `019736f` baselines.)*

| Increment | Scope | Files Touched | Concrete Verification Gate |
| :--- | :--- | :--- | :--- |
| **`P9.1` Zero-Drift Soundness & Consolidation Fixes** | 1. Reset non-oracle totality flags in `recompute-registered-functions-totality` + reject `(null def)` at `ast.lisp:713`.<br/>2. Gate `check-library-nogood-schemas` zip on `function-body-length-preserving-p`.<br/>3. Gate `:relation` condensation to `:functional` tables + memoize failed fits on statement snapshot.<br/>4. Put hooks + `retype-knowledge-laws` + `lift-field-solvers` in bounded convergence loop in `consolidate-knowledge-library`.<br/>5. Add `(vm-versions)`-keyed `validated-program` cache in `entry-executable`, zero-alloc `metric-delta` replay, & parallel `heuristic-packets` field on `heuristic-model`. | `knowledge.lisp`, `ast.lisp`, `nogoods.lisp`, `relations.lisp`, `consolidate.lisp`, `vm.lisp`, `laws.lisp`, `condense.lisp`, `decompose.lisp` | All `182` kernel + `40` milestone tests pass; Probe 2 (`34,067`), Probe 4 (`112,979`), and Probe 5 (`264,353`) Stage A/search trajectories unchanged (packet cache saves Stage B/prep work on metric tasks); new unit tests for mutual-redefinition non-totality, permuting-combinator nogood soundness, member-table safety, fit memoization, and 1-call consolidation fixed-point on **both** `lift -> :functor` and `:motif -> retype` fixtures. |
| **`P9.2` Static Totality & Missing `main` Capabilities** | 1. Rank-environment `analyze-function-body-totality` (`(:seq-len>= k)` with $1 \le d \le k+1$ & `(at (tail^j X) 'r)` for $r+j < L$; per-slot sum/lexicographic `merge`; integer descent/ascent/halving; closed `:code-eval` redex beta-inlining).<br/>2. `:metric` kwarg on `start-synthesis` / `start-heuristic-synthesis` / `start-recursive-synthesis`; move `install-sequence-shift-metric` to `tests/support.lisp` with bidirectional shifts & tighten `tests/metrics.lisp` `60000 -> 16000`; add all-row/guarded `(:*` $\leftrightarrow$ `:/)` decoder, moment-difference solvers, certified transfer laws, & cross-row unified `:code-edit` pullback. | `ast.lisp`, `synthesize.lisp`, `decompose.lisp`, `frame.lisp`, `consolidate.lisp`, `bootstrap-inverters.lisp`, `tests/support.lisp`, `tests/metrics.lisp` | New totality unit tests (`pairwise`, `evens`, `merge`, positive/negative `shift-seq`, integer halving, negative-halving rejection); partial `(*, /)` task solves without child conflict; `:code-edit` Stage B pullback solves parametric AST macro task; `tests/metrics.lisp` passes at `:heuristic-budget 16000` (`~100k` work). |
| **`P9.3a` Homoiconic Propagators & Comprehension Lift (Parallel Build)** | 1. `solver-probe-values-for-type` + `induce-conditional-solvers` + `induce-law-solvers` (`:derived` attestation, distinct context vars, bijective involution `:unique-p`); tighten `induce-solvers-from-transformers`.<br/>2. Single-unknown finite-set propagation ($m \le 8$, fallback preserved on `:int`), full-operator-keyed dispatch index, unsimplified fallback in `solve-equality-symbolically`, guarded `orient-conserved-quantity`.<br/>3. Complete DIP on pure projections (`synthesize.lisp:479` + `nogoods.lisp:181`); generalize `:lift-p` templates + 2-combinator `map(filter(...))` lift. | `laws.lisp`, `templates.lisp`, `synthesize.lisp`, `nogoods.lisp`, `proposals.lisp` | Learned `induce-conditional-solvers` & `induce-law-solvers` independently discover guarded `scale-seq`, `offset-seq`, arithmetic, and bijective involution solvers; 2-combinator pipeline lift solves H2 filter-map (`tests/higher-order.lisp:193`) with `filter-map-decompositions` disabled in an isolated test; before/after dispatch work logged. |
| **`P9.3b` Gated Retirement Step** | Retire `filter-map-decompositions` (`proposals.lisp:219-298`, `-80` to `-150` LOC) and the superseded builders of `bootstrap-inverters.lisp` (`-250` to `-346` LOC) **only** for every case verified green by `P9.3a`. | `proposals.lisp`, `bootstrap-inverters.lisp`, `load.lisp`, `Makefile`, `package.lisp` | Full `182` kernel + `40` milestone suite green at default budgets with zero regressions. |
| **`P9.4` Search Control, Subtree M8D, Levin Tariff, & Contrastive Descriptors** | 1. Follower-safe incumbent filtering, normalized soft MDL parking, structural-exempt deferred waking, `work-at-last-improvement` marginal stopping.<br/>2. Subtree-grounded M8D residual predictor $\hat{\Delta}$ around analytical MDL; total-batch Levin tariff (`N_prop + log2(1 + W_failed)`).<br/>3. Error-safe descriptor verdicts, mandatory `:necessary` pruning before progressive Tier 2/3 empirical scoring, memoized contrastive separator synthesis for liftable combinators, consolidation-time $\mathbb{Z}^d$ `:locality-key` harvesting & `:coordinate` mode. | `synthesize.lisp`, `consolidate.lisp`, `descriptors.lisp`, `proposals.lisp`, `milestones/corpus.lisp` | Multi-combinator starvation benchmark solved via deferred waking; 1-unit vs. 97-unit resumption parity under marginal stopping; learned M8D residual improves or matches baseline work across multi-job curriculum; contrastive separator synthesized & memoized (1-call fixed-point preserved). |
| **`P9.5` `(:fix-seq)`, Opt-In Set Matching, Active Queries, & Latent Trajectories** | 1. Library `:fix-seq` + 2-type `candidate-library-definitions` fix + conjectured stationary `(= (code-eval step 'y) 'y)` narrowing.<br/>2. Opt-in tuple-sequence bipartite correspondence + provably-total `:sort-by`.<br/>3. Exact-search `propose-disambiguating-query`.<br/>4. Tuple-slot `(= (at Z 'j) 'v)` folding at $t=0$ + trajectory-screened latent-slot enumeration for `:scan-proj0` & `reverse-acc`. | `proposals.lisp`, `frame.lisp`, `requirements.lisp`, `explain.lisp`, `synthesize.lisp` | Graph reachability over shuffled edge lists `(:seq (:tuple :int :int))` via `:fix-seq` + opt-in set metric; exact query disambiguation on multi-candidate tasks; Appendix A Probe 6 (`:scan-proj0` with unobserved 2nd tuple slot) & `reverse-acc` solved end-to-end. |

---

## 7. Non-Negotiable Kernel Invariants

1. **Pure-Kernel Isolation (`tests/run.lisp:61-71`):** `load.lisp` never depends on `milestones/` or test fixtures (`install-sequence-shift-metric` moves to `tests/support.lisp`).
2. **Deterministic Unit-Step Preemption (`check-anytime-resumption`):** Every host preparation, propagation, bipartite match, and marginal-stopping check depends solely on metered ledgers and persistent `synthesis-job` fields (`1`-unit vs. `97`-unit parity).
3. **Zero-False-Pruning Galois Soundness (`tests/invariants.lisp`):** Sampled/conjectured solvers and stationary `:fix-seq` hypotheses always preserve active reserve `propagation-fallback`s (`plan8.md` §6.7); canonical search bounds cover the loosest follower; partial metric decoders (`(*, /)`, `:code-edit`) either cover all constrained rows or split conditionally; speculative non-improving branches are priority-parked, never irreversibly killed.
4. **Permutation & Alpha-Renaming Invariance (`tests/invariants.lisp`):** `frame-rows` order and `*knowledge-library*` are never mutated mid-search; multi-type combinator retyping and tuple projections key on `(id . type)` alists.
5. **Single-Pass Consolidation & Serialization Idempotence (`tests/invariants.lisp:400-465`):** The bounded hook/retype/lift convergence loop plus snapshot-keyed failure memos (for incompressible `:relation` tables and contrastive `:descriptor` pairs) guarantee semantic fixed-point in a single `consolidate-knowledge-library` call.
