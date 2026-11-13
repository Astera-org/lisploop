# `lisploop` — Plan 8: Geometric & Topological Unification (SMOCE), Product & Sharing Completeness, and Kernel Simplification

> **Status:** Architectural audit and implementation plan (v3 — refocused on domain-general kernel primitives and simplification), 13 November 2026.
> Audited against the authoritative Common Lisp kernel at commit `b6e289e` (24 kernel modules in `load.lisp`, `12,433` LOC + 5 milestone modules in `milestones/`, `1,401` LOC), cross-referencing `prompt4.md`, `architecture2.md`, `plan7.md`, `plan7-recursion.md`, `plan7-library.md`, `plan7-higher-order.md`, `plan7-m9-policy.md`, and `plan8-2.md`.
> Empirical measurements in §1.3 and Appendix A are accompanied by self-contained reproduction code verified against commit `b6e289e`.

---

## 1. Executive Synthesis: Unifying Structure, Computation, and Space Induction

This plan addresses three foundational questions about the `lisploop` kernel:
1. How syntactic anti-unification (AU) and library refactoring relate mathematically to top-down/bottom-up (TD+BU) computational synthesis, and what should—and should not—be unified.
2. How heuristic condensation, conservation, and `frame` scaffolding generalize into **target geometry** (pluggable/co-induced transformation metrics) and **index topology** (induced orderings, typed cross-row edges, and ontology-free availability preorders).
3. Which missing general primitives unlock structured product spaces, subexpression sharing, and relational dependency folding while **reducing** incidental kernel complexity—and which harder problems (such as unobserved latent state abduction) should be cleanly separated and deferred.

### 1.1 Where `plan8-2.md`'s Restrictive Calibration Holds

1. **Unify the data model and agenda; keep the inner matching and search engines distinct (`plan8-2.md` §4.3).**
   Syntactic AU (`anti-unify` in `unify.lisp:36`) is linear-time ($O(|t|)$) and deterministic because free-algebra constructors (`:cons`, `:tuple`, AST application nodes) are **injective**; all search on the AU side lives in **correspondence** (which functions, rows, or subtrees to align). Computational synthesis (`enumerate.lisp`, `condense.lisp`, `synthesize.lisp`) operates over **many-to-one** primitives (`:+`, `:*`, `:at`, `:fold`), where row alignment is fixed upfront and search lives in **conserved computation**. Replacing AU with enumeration would forfeit $O(|t|)$ determinism; collapsing synthesis into unstratified E-graph saturation would blow up VM budgets. They meet as **complementary operators emitting `decomposition`s and `frame`s onto one full-path MDL agenda**.
2. **Keep the two senses of "fiber" and "table vs. graph" distinct (`plan8-2.md` §3.2–3.3).**
   - *Preimage / value fiber (`plan7.md` §2):* $\mathrm{Fiber}(\omega) = \{z \mid B_\omega(z) = \mathrm{true}\}$, arising when a non-injective operator aliases inputs. Because constructors are injective, AU yields **point substitutions**, not multi-valued preimage fibers.
   - *Occurrence / bundle fiber (`select-active-fiber-rows` in `frame.lisp:529`):* The $k$ child occurrences $(\omega, c)$ unfolded from a parent object $\omega$ under a 1-to-many cover (`lift-frame` or `collect-tree-occurrences`).
   - *Star-table vs. graph:* Root-aligned `anti-unify` is isomorphic to `observation-bucket` over root-to-leaf path selectors. True graph topology enters only with **unaligned correspondence** (`discover-subexpression-abstractions` in `milestones/corpus.lisp:583`) and **cross-row linkage** (`pairs`, `anchors`, `frame-edges`).
3. **Verified kernel baselines (`b6e289e`).**
   - Exact search (`search-step` in `enumerate.lisp:455`) currently **ignores `pairs` and `anchors`**; only `observation-job` and Stage A (`condense.lisp`) read them.
   - Functorial inverters in `bootstrap-inverters.lisp:6` are host-coded structural recognizers, not learned `:transformer` rules.
   - `evaluate-frame-descriptors` does not exist in `descriptors.lisp`; `find-knowledge-entries-by-address` (`knowledge.lisp:253`) and `probe-frame-coordinates` (`frame.lisp:598`) have **zero callers** in the synthesis loop.

### 1.2 Core Architectural Lacunae Exposed by Audit & Thought Experiments

Using algebra, recursive sequence synthesis, AST refactoring, and stateful transition streams as diagnostic lenses exposes five **domain-general** lacunae in the current kernel:

1. **Product Decomposition, Guard Reuse, & Subexpression Sharing (`#4`):**
   - `compose-model` (`frame.lisp:399-404`) always substitutes child `bindings` inline, inflating $S(M)$ and $W_{\mathrm{run}}(M)$ multiplicatively whenever a derived binding is referenced $\ge 2$ times. Homoiconic `:code-eval` over a `:code` literal provides exact `let`-sharing with **zero new VM opcodes** (§3.3).
   - While `make-additive-residual-decoder` (`decompose.lisp:13`) expands `+` slot-wise on `:tuple`s, `decomposition` (`synthesize.lisp:8`) has only a single `child-id`: non-trivial product targets (`:tuple`s and multi-hole Constructor-AU skeletons $p(?0 \dots ?m)$) either remain monolithic or blow past default `max-depth = 2` (`decompose.lisp:419`) if chained sequentially, and accessing `(at X 0)` on a pair costs **`30` body-bits**.
   - In Stage B Path B2, `find-sound-exception-guard` (`decompose.lisp:81`) defaults to `guard-bound = 20` body-bits (`decompose.lisp:305`) and re-enumerates `:bool` ASTs syntactically from scratch in `observed-predicates` (`decompose.lisp:68`), **discarding `(heuristic-buckets h-model)`** (`condense.lisp:240`), which already holds evaluated feature vectors up to 18 bits. Pairing existing Stage A buckets via `=`/`<` finds 27–32 bit relational guards with **zero extra VM evaluations**.
2. **Host-Coded `correction` vs. Co-Induced `(decoder, :solver)` DSL Metrics (`#1` & `#5`):**
   `correction` (`frame.lisp:1003-1086`) hardcodes one fixed metric per type (`:bool` and `:code` pay full replacement; `:seq-delta` pays elementwise prefix mismatches on shifted sequences). Pairing a binary library decoder $d(\hat{Y}, \delta) \to Y$ with a certified or tentative `:solver` $q(\hat{Y}, Y) \to \delta$ **co-induces** both a Stage A residual metric and its matching Stage B pullback $Y = d(\hat{\pi}(X), Z)$ (§3.1).
3. **Static Row Topology & Ontology-Free Dependency Folding (`#2`):**
   `frame` currently treats `pairs` and `anchors` as static, unchecked hints and has no general representation for **availability order** (which columns/ports precede others) or **induced locality** (sorting rows by a synthesized key $k(X)$ to minimize output variation). Furthermore, `decomposition-bindings` (`frame.lisp:392`) evaluate strictly on a single row: cross-element context must enter via **composable higher-order combinator lifts (`lift-frame`)**, never by smuggling neighbor rows into non-composable `bindings` (§3.4).
4. **Numeric vs. Symbolic Reorientation:**
   Operation 3's reorientation helpers (`conserved-quantity-frame` in `frame.lisp:793` + `propagate-requirements` in `laws.lisp:781`) solve equations **numerically per row** (`solve-learned-equality`, `laws.lisp:761`). On a frame whose target rows are already singletons, numeric conservation-inversion merely reproduces the starting frame (`tests/recursion.lisp:559-640`), while degenerate invariants like `(- Y Y) = 0` collapse to `'t`. Useful reorientation on singleton targets requires **target-sensitivity filtering + symbolic solver unwinding (`solve-equality-symbolically`)** over ASTs (§3.3).
5. **Fixed Stage A Fast-Path Budgets & Boundary of Decoupled `lift-frame`:**
   - Adding a single irrelevant scalar input to a lifted `:scan` task increases work $7.5\times$–$26\times$ (`21,023` $\to$ `158,433` / `547,872`, identically at bounds `90` and `110`) because fixed `heuristic-budget` cuts off Stage A just before `exact-heuristic-program` (`synthesize.lisp:479`), triggering ~14 Stage B/sibling expansions; scaling Stage A budget with input arity restores the fast path (`62,942` / `73,335` work).
   - Conversely, when a lifted combinator threads **unobserved or non-injectively projected intermediate state** (whether an unknown recursion accumulator or a hidden world variable), `lift-frame` leaves `t >= 1` rows in `coupled-requirements` (`:unresolved`). Solving coupled/latent intermediate fibers requires joint hypothesis-and-trajectory alternation rather than single-pass lifting—cleanly separated into §5.1 for future investigation.

### 1.3 Verified Empirical Diagnostic Summary at Commit `b6e289e`

| Diagnostic Probe (Runnable in Appendix A) | What It Tests | Result on `b6e289e` | Architectural Takeaway |
| :--- | :--- | :--- | :--- |
| **1. Scalar `:scan` (`s' = s + a`)** | Library fold/scan lifting | **Solved** in `21,023` work | Temporal/sequential framing works via ordinary library `lift-frame` |
| **2. Same + 1 Irrelevant Input** | Arity scaling (`bounds 90 & 110`) | `158,433` (`+/*`) / `547,872` (`+/-/=`) work (identical at 90 & 110) | Bound has no effect; Stage A misses fast path under fixed `heuristic-budget` |
| **3. Same + `:heuristic-budget 30000`** | Arity-scaled Stage A budget | **`62,942` / `73,335` work** | Stage A budget must scale with `(length inputs)` (`P8.2`) |
| **4. Symmetric Tuple `:scan-tup`** | `make-additive-residual-decoder` | **Solved today** in `80,212` work | Additive Path B1 splits `+` per slot when tuple residual `Z` is tiny |
| **5. Conditional Tuple (`207` body-bits)** | Asymmetric per-slot guard (`(at s 0)` = `30` bits) | **Fails** at `800k` & `4M` work (`coupled = 0`) | Needs parallel `product-decomposition`, tuple projection, & bucket-pair guards (`P8.1`) |
| **6. Stage A `heuristic-buckets` Pairing** | `(= b_i b_j)` over Stage A buckets | Finds 27-bit guard `(= X0 (- X1 X2))` in **`30,000` work + `231` checks** | Reusing `heuristic-buckets` (`condense.lisp:240`) eliminates $>500\text{k}$ syntactic guard search (`P8.1`) |
| **7. Partially Observed Tuple (`:scan-proj0`)** | Unobserved intermediate slot | Steps $t \ge 1$ `:coupled` (`:unresolved`) | Marks the exact boundary of decoupled `lift-frame` (deferred in §5.1) |

---

## 2. Intersection Map & Kernel Simplification (~950–1,300 LOC Removable)

### 2.1 Where Search Lives Across Mechanisms

| Mechanism | Ambient Space | Shared Part $p$ | Per-Instance $\theta_\omega$ | Where Search Lives |
| :--- | :--- | :--- | :--- | :--- |
| **Aligned AU** (`unify.lisp:36`) | `:code` ASTs (root-aligned) | LGG pattern $p(?0 \dots ?k)$ | Point substitutions $\sigma_\omega$ | **None** ($O(\|t\|)$ closed form); `abstraction.lisp` searches *corpus subsets* |
| **Unaligned Subtree AU** (`milestones/corpus.lisp:583`) | `:code` ASTs (arbitrary paths) | Shared subterm template | Path occurrences + arguments | **Correspondence search** (3:1 `:locality`-scheduled occurrence pairs) |
| **Library AU** (`abstraction.lisp:98, 181`) | Recursive `:function` ASTs | Higher-order combinator (`:code-eval`) | Closed `:code` literals + FO args | **Subset search** + `shared-subterm-cover` continuation factoring |
| **Exact / Stage A Synthesis** (`enumerate.lisp`, `condense.lisp`) | Runtime values $\mathcal{V}_\tau$ | Program $e(X)$ or chart $\hat{\pi}(X)$ | Given `row-known` (+ delta packet $\varepsilon_\omega$) | **Computation search** (size-tiered grammar enumeration over fixed rows) |
| **TD Pullback / Product / Lift** (`frame.lisp`, `fibers.lisp`, `decompose.lisp`) | Requirement predicates $A_\omega(Y)$ | Outer decoder $d(X, Z_0 \dots Z_{m-1})$ | Child fibers $B_{\omega,j}(Z_j)$ | **Decoder & partition search** (vertical target change + horizontal splits) |

### 2.2 Streamlining & Deduplication Targets (`P8.4`)

At `b6e289e`, the kernel (`12,433` LOC) + `milestones/` (`1,401` LOC) totals `13,834` LOC. The four core phases of Plan 8 add **~`550–650` LOC** of general capability while retiring **~`950–1,300` LOC** of legacy indirection, leaving the codebase **smaller and flatter**:

1. **Collapse Dual Pre-M7 Structs in `laws.lisp` onto `knowledge.lisp` (~350–450 LOC saved):**
   Store laws and solvers directly as `knowledge-entry` payloads, retiring standalone `law`, `rewrite-rule`, `rewrite-library`, `certified-solver`, and `solver-library` structs (`laws.lisp:5-60`) and their synchronization wrappers.
2. **Declarative Meta-AST Rules in `bootstrap-inverters.lisp` & `descriptors.lisp` (~250–350 LOC saved):**
   Replace hand-nested host `app`/`lit` `:code-match`/`:code-bind` AST builders with `term` templates and `learn-knowledge-transformer` (`transformers.lisp:246`) `(source, target)` pairs.
3. **Single Parameterized `Cover + Orient` Constructor in `frame.lisp` & `milestones/corpus.lisp` Absorption (~350–500 LOC saved):**
   Factor the 10 manual row/schema-copying constructors (`pullback-frame`, `restrict-frame`, `orient-observations`, `conserved-quantity-frame`, `context-label-frame`, `lift-frame`, `au-substitutions-frame`, `make-search-trace-frame`, etc.) through one parameterized builder over `frame-edges`, and unify `nogood-clause` / `:uip-clause` (`nogoods.lisp:5, 214`).

---

## 3. The Unified Five-Stage Cycle (SMOCE) & Core Primitives

Both AU/library refactoring and TD+BU synthesis instantiate **one five-stage fibered factorization cycle** over `frame`s:

| Stage | Operation | On Constructors / Syntax (`:code`, `:tuple`, `:cons`) | On Computation & Relational Frames |
| :--- | :--- | :--- | :--- |
| **1. Cover** | Unfold occurrences or induce row order (3:1 window + reserve) | `collect-tree-occurrences`; parallel `:tuple` coordinate slots | `lift-frame` on library combinators; `sort-by(k(X))` variation chains |
| **2. Correspond** | Align occurrences (via `:locality-key`) & match constructors in $O(\|t\|)$ | Root walk; 3:1 `:locality` pairing; `match-pattern`, `fold-equal-tuple` | Row key alignment; `infer-fibers` Helly blocks; `dependency-proposals` |
| **3. Orient** | Select `known -> target` under availability $\tau(p) < \tau(q)$ & unwind `:solver`s | Orient `(= lhs rhs)` by `expression-less-p`; symbolic solver unwinding | Forward evaluation; backward `propagate-requirements` (+ tentative `:solver`s); symmetric $C(X,Y)=c_0 \xrightarrow{\text{symbolic}} Y=g(X)$ |
| **4. Conserve** | Minimize $S(p) + S_{\mathrm{rows}}^{d_{\mathcal{L}}}(\varepsilon) + S_{\mathrm{edges}}^{d_{\mathcal{L}}}(\varepsilon) + \lambda W_{\mathrm{run}}$ | Closed-form LGG `anti-unify` + `shared-subterm-cover`; `provably-total-p` | Tiered search + Stage A under `:metric` / $d_{\mathcal{L}}$; Stage A bucket-pair guards; edge-checked `search-step` |
| **5. Extract** | Emit single or parallel `product-decomposition` with `:code-eval` `let`-sharing | `abstraction-parameters`; multi-hole Constructor-AU `p(?0..?m)`; `:uip-clause` | Co-induced $d(\hat{\pi}(X), Z)$ pullback; parallel product join; `:code-eval` `let`-frames |

```mermaid
flowchart LR
    F["Frame Omega (Rows + frame-edges + Availability Preorder + Metric d_L)"] --> C1["1. Cover: Lift / Parallel Slot Cover / sort-by(k(X))"]
    C1 --> C2["2. Correspond: Locality Align + Match Constructors O(|t|)"]
    C2 --> C3["3. Orient & Unwind: Availability tau(p)<tau(q) + Symbolic/Heuristic Solvers"]
    C3 --> C4["4. Conserve: Closed-Form LGG or Stage A/Bucket-Pair Search under d_L"]
    C4 --> C5["5. Extract: Co-Induced Pullback + Parallel Product Join + let-Sharing"]
    C5 -->|"Child subproblem(s) or CEGAR refinement"| F
```

### 3.1 Target Geometry: Pluggable & Co-Induced `(decoder, :solver)` Metrics *(Priority #1 & #5)*

Heuristic condensation is **coordinate-chart induction**: Stage A finds $\hat{\pi}(X)$ placing targets near $0$ displacement under a transformation action, and Stage B pulls targets back along that action.
1. **Explicit `:metric` AST Hook:** `frame`, `start-heuristic-search`, `condense-heuristic`, and `start-synthesis` accept an optional total `:code` AST `M : (tau, tau) -> :int` (`0` iff equal, metered on `ledger` in `select-closest-witness` at `frame.lisp:1088` and `relational-linkage-residual` at `enumerate.lisp:543`).
2. **Co-Induced `(decoder, :solver)` Pairs:** Register knowledge edges `(:metric-decoder d q tag-bits)` pairing any binary decoder $d : (\tau, \tau_\delta) \to \tau$ with a `provably-total-p` `:solver` $q : (\tau, \tau) \to \tau_\delta$ (certified or tentative `#5`: `:+` $\leftrightarrow$ `:-`, `:shift-seq` $\leftrightarrow$ `:argmax-corr`, `:code-subst` $\leftrightarrow$ `anti-unify`, or conserved-sum / moment-difference estimators guarded by `witness-replays-p` and 3:1 `propagation-fallback` in `laws.lisp:821-824`).
   - *Stage A:* `correction` evaluates the top-$k$ ($k \le 4$) type-matching `(d, q)` pairs, scoring $S_{\mathrm{tag}}(d) + \text{value-bit-size}(\delta, \tau_\delta)$ whenever $d(\hat{y}, q(\hat{y}, y)) = y$ (capped by default `correction-bit-size`).
   - *Stage B:* `make-metric-residual-decoder` proposes $Y = d(\hat{\pi}(X), Z)$ (`Z : tau_delta`) for the winning `d`, generalizing Path B1 (`decompose.lisp:13`) from `+` to shifts, scalings, and `:code` template edits.

### 3.2 Product Completeness, `let`-Sharing, & Bucket-Pair Guards *(Priority #4)*

1. **Homoiconic `let`-Sharing in `compose-model` (`frame.lisp:399`, #4):**
   Count free-variable uses of each binding `(id_r . b_r)` across `(instantiate decoder (list (cons child-id child-model)) :var)`. Whenever sharing multi-use bindings strictly improves `candidate-score` ($S(M) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$) over inline substitution, emit `(:code-eval (lit (:code ...) body) b_0 ... b_{r-1})`. Uses existing `vm.lisp` metering, `O(1)` `provably-total-p` (`ast.lisp:826`), and `call-unfolding` (`requirements.lisp:347`) with **zero new primitives**.
2. **Parallel Multi-Hole `product-decomposition` & Tuple Projection (`synthesize.lisp`, `proposals.lisp`):**
   - Expose scalar/component bindings `(at X_i '0) ... (at X_i '(k-1))` for small `:tuple` inputs ($k \le 6$), avoiding repeated 30-bit `:at` trees.
   - Add an AND-join `product-slots` mode on `synthesis-node` for any injective constructor skeleton (`(tuple ?0 ... ?{k-1})` or Constructor-AU LGG $p(?0 \dots ?m)$ from promoted `au-substitutions-frame`) whose per-row requirements factor into independent per-hole conjuncts. All holes solve **in parallel at constant depth `d + 1`** (without decrementing computational `max-depth` on pure constructor unpacking) and reassemble as soon as each hole verifies a child candidate.
3. **Stage-A Feature-Bucket Guard Discovery (`decompose.lisp:81`):**
   Before running `observed-predicates`, `find-sound-exception-guard` pairs already-computed Stage A feature buckets in `(heuristic-buckets h-model)` (`condense.lisp:240`) with `=` and `<` up to 32 body-bits, finding relational exception guards across arithmetic, sequence, and tuple tasks with zero redundant VM evaluations.

### 3.3 Symbolic Equation Unwinding (`solve-equality-symbolically`)

To make Operation 3's conservation-reorientation productive on singleton-target frames (avoiding circular numeric round-tripping and degenerate `(- Y Y) = 0` invariants):
1. **Target-Sensitivity Check:** Accept joint invariant $C(\mathbf{x}, Y) = c_0$ only when `Y` occurs free in $C$ and perturbing $y_\omega \mapsto y'_\omega$ changes $C(\mathbf{x}_\omega, y)$ on $\ge 1$ row.
2. **Symbolic Unwinding:** Apply certified `:solver` witness ASTs **symbolically** to `(= C(X, Y) 'c_0)` (checking solver domain guards across `row-known`) to emit closed-form candidate $Y = g(X)$ directly (e.g., `(= (- (+ Y X0) X1) '0) => (- X1 X0)`), or simplified non-identity requirement `(= h(Y) g(X))`. Reserve numeric `conserved-quantity-frame` strictly for unoriented relational tables where $Y$ is not yet the target.

### 3.4 Relational `frame-edges`, `sort-by` Space Induction *(Priority #2)*, & Availability Preorders

1. **Checked `frame-edges` vs. Single-Row `bindings`:**
   - Replace untyped `pairs`/`anchors` on `frame` (`frame.lisp:12`) with typed `frame-edges` (`:equal`, `:distinct`, `:persistence`, `:recurrence`), enforced for hard edges in `search-step` (`enumerate.lisp:455`), priced for soft `:persistence` in `relational-linkage-residual` (`enumerate.lisp:543`), and included in `child-scope-signature` (`synthesize.lisp:199`) and `nogood-clause` (`nogoods.lisp:5`).
   - **`decomposition-bindings` (`frame.lisp:392`) remain strictly single-row** so `compose-model` always produces a self-contained AST. Cross-element input context (`x_{i-1}, x_i`, sliding windows, accumulators) enters **exclusively** through composable higher-order combinator lifts (`lift-frame` on `:foldr`, `:scan`, `:map-adj`, etc.).
2. **Synthesized `sort-by(k(X))` Topology & `:locality-key` Induction (#2):**
   On frames without pre-existing chain edges, sort row indices along each `:<`-comparable feature bucket $k(X)$ in Stage A's `(heuristic-buckets h-model)` (`O(|B|)` passes, zero VM runs). When induced chain variation $\sum_{(u,v) \in E_k} d_{\mathcal{L}}(y_u, y_v) + \text{description-size}(k)$ beats the unpermuted baseline, attach $E_k$ as `:persistence` `frame-edges` (plus extremal `:distinct` anchors) and register $k(X)$ as a reusable `:locality-key` for 3:1 unaligned correspondence.
3. **Ontology-Free Availability Preorder (`schema`):**
   Instead of baking domain roles (`:state`, `:action`, `:next-state`) into `schema` (`ast.lisp:30`), optional column metadata carries only an **availability index** $\tau(p)$ in a preorder $(\mathcal{T}, \le)$: predicting a target at $\tau_{\mathrm{target}}$ may read only inputs with $\tau(p) < \tau_{\mathrm{target}}$ (and never `row-key`). Symmetric invariant search temporarily drops `<` to find $C(W) = c_0$, then symbolically unwinds for the maximal-$\tau$ port.

### 3.5 Continual-Learning Consolidation Hygiene *(#6)*

Extend `consolidate-knowledge-library` (`consolidate.lisp:363`) with:
1. **Second-Order Theory Motifs (`plan7-library.md` §2.2):** Quotient connected `(:refactored-by :foldr)` + `:associative` + `:identity` `:law` edge stars into reusable **Monoid / Fold-Homomorphism** motifs licensing `:foldr <-> :foldl` / `:scan` rewrites on new instances.
2. **Cross-Prime `(:gf p)` Solver AU:** Domain-erased `anti-unify` across finite-field `:solver` witnesses to lift parametric `:int` solver conjectures.
3. **Net-Utility Cold-Archive Demotion (`plan7.md` §4.9):** Track $\mathrm{NetUtility}(e) = \sum \Delta S_{\mathrm{saved}}(e) - \lambda_{\mathrm{search}} \sum W_{\mathrm{dispatch + failed\text{-}lift}}(e)$ from `ledger`, demoting non-amortizing entries without live `:depends-on` callers to `:active-p nil` cold archive after $K$ epochs.

---

## 4. Streamlined Four-Phase Implementation Roadmap (`P8.1` – `P8.4`)

| Phase | Scope & Files | Verification Gate (with Held-Out & Negative Controls) |
| :--- | :--- | :--- |
| **`P8.1` Product Decomposition, `let`-Sharing (#4), & Bucket-Pair Guards** | `frame.lisp` (`compose-model` `:code-eval` sharing), `synthesize.lisp` (`product-slots` constant-depth AND-join), `proposals.lisp` (`:tuple` projections + promoted Constructor-AU `au-substitutions-frame` + `:decoder-template` AU), `decompose.lisp` (`heuristic-buckets` `=`/`<` guard pairing up to 32 bits). | Multi-use bindings emit smaller `:code-eval` ASTs that unfold in `requirements.lisp:347`; Constructor-AU & asymmetric conditional `:tuple` tasks (incl. Appendix A Probe 5) solve and generalize on held-out inputs. |
| **`P8.2` Co-Induced DSL Metrics (#1), Heuristic `:solver`s (#5), & Arity-Scaled M9 Policy** | `frame.lisp` (`frame-metric` + `(:metric-decoder d q)` in `correction`), `condense.lisp`, `decompose.lisp` (`make-metric-residual-decoder`), `bootstrap-inverters.lisp` (`:argmax-corr` & moment `:solver`s + 3:1 `propagation-fallback`), `synthesize.lisp` (**arity-scaled `node-stage-a-model` budget** + `*max-eager-proposals-per-node*`), `descriptors.lisp` (`evaluate-frame-descriptors` + address lookup). | Shifted sequences & `:code` ASTs price smoothly via `(:shift-seq, :argmax-corr)` and `(:code-subst, anti-unify)` and pull back in Stage B; Probe 2 irrelevant-input `:scan` drops under `80,000` work; fallback preserves completeness on ambiguous correlations. |
| **`P8.3` Checked `frame-edges`, `sort-by` Space Induction (#2), Preorders, & Symbolic Unwinding** | `ast.lisp` (`schema` availability preorder $\tau$), `frame.lisp` (`frame-edges`), `enumerate.lisp` (hard edge checks in `search-step`), `synthesize.lisp` (`child-scope-signature`), `proposals.lisp` (`sort-by` bucket variation pass $\to$ `:persistence` edges + `:locality-key`), `laws.lisp` (`solve-equality-symbolically` + target-sensitivity filter). | Hard `frame-edges` prune invalid exact candidates; shuffled functional/dynamical tables recover latent ordering key $k(X)$ (while random-noise negative controls induce no edges); `solve-equality-symbolically` derives `reverse` index map directly from `I + j - (n-1) = 0`. |
| **`P8.4` Theory Motifs, Library Amortization/Eviction, & Kernel Cleanup (#6)** | `consolidate.lisp`, `laws.lisp`, `bootstrap-inverters.lisp`, `descriptors.lisp`, `frame.lisp`, `nogoods.lisp` (absorbing `milestones/corpus.lisp`): Monoid motif stars, cross-prime `(:gf p)` solver AU, net-utility cold-archive demotion, and ~950–1,300 LOC deduplication (§2.2). | Net kernel + milestone LOC decreases vs. `b6e289e` with 100% existing test suite green; Monoid motif transfers `:foldr <-> :foldl`; `GF(5)/GF(7)` solvers lift to `:int`; planted decoy entries demote to `:active-p nil`. |

---

## 5. Deferred Frontiers & Future Investigation

The following open problems are cleanly separated from Core Plan 8 so the kernel stays general, minimal, and domain-agnostic:

1. **Coupled Intermediate Fibers & Latent Accumulator / State Abduction:**
   When `lift-frame` unfolds a recursive helper or sequence combinator whose intermediate accumulator is unobserved (`coupled-requirements` in `frame.lisp:684`, Appendix A Probe 7), single-pass lifting cannot decouple steps $t \ge 1$. A general resolution—applicable equally to synthesizing hidden recursion accumulators (`reverse-acc`), loop invariants, and non-Markovian dynamical systems—must address four coupled requirements documented during audit:
   - *Explicit Prediction / Calling Contracts:* Distinguishing **open-loop rollout** (valid only for endogenous memory determined by observed inputs) from **prequential filtering** (required for exogenous per-episode parameters, where filter updates read newly arrived observations under $\tau(o_{t+1}) < \tau(o_{t+2})$ and price latent channel bit-capacity $C_{\mathrm{cap}}(\tau_L)$).
   - *Latent-Hole Decoder Proposal:* Proposing $F(\dots, Z)$ via iterated Stage A on residual row subsets (regime multiplexers) or per-instance Stage A + AU shells rather than clustering input-confounded raw residuals.
   - *Joint $(L, U)$ Alternation:* Resolving soft-persistence ties across unprobed corridors via alternating Viterbi/constraint-propagation over finite fibers and Stage A/B synthesis of transition laws, validated on held-out horizons and Markovian negative controls.
2. **Unaligned Set/Graph Correspondence & Fuel-Bounded Fixed-Point Combinators:**
   Extending `:locality-key` canonical ordering with minimum-$d_{\mathcal{L}}$ bipartite set matching across `(:seq (:tuple ...))` elements and structurally fueled `(:fix-seq fuel init step)` closure for variable-degree graph traversal.
3. **Active Intervention & Disambiguating Query Selection *(Item 3 — `prompt4.md` §3b)*:**
   Selecting inputs or online actions whose predicted outcomes maximally split surviving candidate programs or narrow ambiguous preimage fibers under $d_{\mathcal{L}}$.
4. **Branch-Closing Controllers, Static Totality Extensions, & Discriminative Descriptors *(Item 7)*:**
   Monotone full-path-price branch closing and marginal $J_{\mathrm{procedure}}$ stopping (`plan7.md` §1.5, §4.8); bounded `:int` descent, `(tail (tail X_i))`, and non-lockstep `merge` totality in `analyze-function-body-totality` (`ast.lisp:700`, `plan7-recursion.md` §2.3); discriminative separator `:descriptor` synthesis (`plan7-m9-policy.md` §4.3) and variable-compute compositional address decoding (`prompt4.md` §9).
5. **Stage-A-Seeded Decoder-Shell AU & Firewall-Typed Object-Language Views (`plan8-2.md` §4.2, §6.5):**
   General 1-edit residual shell anti-unification and reifying `frame` views as object-language values behind a static capability firewall barring candidate access to `row-key`.

---

## Appendix A. Self-Contained Reproducible Diagnostic Probes at Commit `b6e289e`

Run directly via `sbcl --script` from repository root at commit `b6e289e`:

```lisp
(load "load.lisp")
(in-package :lisploop)
(clear-knowledge-library)

(let* ((tup (tuple-type :int :int))
       (seq-int (sequence-type :int))
       (seq-tup (sequence-type tup))
       (step-int (code-type '((0 . :int) (1 . :int)) :int))
       (step-tup (code-type (list (cons 0 tup) (cons 1 :int)) tup)))
  (define-function :scan (list (cons 0 seq-int) (cons 1 :int) (cons 2 step-int)) seq-int
    (lambda (self)
      (let* ((actions (var 0 seq-int)) (state (var 1 :int)) (step (var 2 step-int))
             (next (term `(code-eval ,step ,state (at ,actions 0)))))
        (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) seq-int))))
  (define-function :scan-tup (list (cons 0 seq-int) (cons 1 tup) (cons 2 step-tup)) seq-tup
    (lambda (self)
      (let* ((actions (var 0 seq-int)) (state (var 1 tup)) (step (var 2 step-tup))
             (next (term `(code-eval ,step ,state (at ,actions 0)))))
        (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) seq-tup))))
  (define-function :scan-proj0 (list (cons 0 seq-int) (cons 1 tup) (cons 2 step-tup)) seq-int
    (lambda (self)
      (let* ((actions (var 0 seq-int)) (state (var 1 tup)) (step (var 2 step-tup))
             (next (term `(code-eval ,step ,state (at ,actions 0)))))
        (term `(if (= ,actions ()) () (cons (at ,next 0) (,self (tail ,actions) ,next ,step))) seq-int))))

  ;; 1. Exact AST bit-size diagnostic on conditional product rules
  (let* ((s (var 0 tup)) (a (var 1 :int))
         (s0 (term `(at ,s 0))) (s1 (term `(at ,s 1)))
         (cond-tup (term `(tuple (+ ,s0 ,a) (if (= (+ ,s0 ,a) ,s1) (+ ,s1 ,a) ,s1))))
         (proj-in '((0 . :int) (1 . :int) (2 . :int)))
         (ps0 (var 0 :int)) (ps1 (var 1 :int)) (pa (var 2 :int))
         (g-proj (term `(= (+ ,ps0 ,pa) ,ps1)))
         (b-proj (term `(if (= (+ ,ps0 ,pa) ,ps1) (+ ,ps1 ,pa) ,ps1))))
    (format t "[Bits] (at s 0)=~D, monolithic-tuple=~D, proj-guard=~D (default-g-bound=20), proj-branch=~D~%"
            (body-size s0 (list (cons 0 tup) (cons 1 :int)))
            (body-size cond-tup (list (cons 0 tup) (cons 1 :int)))
            (body-size g-proj proj-in) (body-size b-proj proj-in)))

  ;; 2. Symmetric tuple scan: solved today via make-additive-residual-decoder
  (let* ((in-tup (list (cons 0 seq-int) (cons 1 tup)))
         (f-sym (make-frame (make-schema :inputs in-tup :target seq-tup)
                            (list (make-row :key 0 :known '((1 2) (0 10))
                                            :requirement (singleton-requirement seq-tup '((1 11) (3 13))))
                                  (make-row :key 1 :known '((-1 3) (5 2))
                                            :requirement (singleton-requirement seq-tup '((4 1) (7 4)))))))
         (lang-tup (make-language :int in-tup
                                  :operators (list (op :+ :int) (op :- :int) (op :tuple tup) (op :at tup) (op :scan-tup))
                                  :literals '(0 1)))
         (j-sym (start-heuristic-synthesis f-sym lang-tup 160 :library-proposals-p t :library-functions '(:scan-tup))))
    (resume-synthesis j-sym 400000 :stop-on-first t)
    (format t "[Symmetric Tuple Scan] solved=~S work=~D~%"
            (not (null (synthesis-job-best j-sym))) (ledger-total (synthesis-job-ledger j-sym))))

  ;; 3. Asymmetric conditional tuple scan: lifts with coupled=0, fails synthesis at 800k
  (let* ((in-tup (list (cons 0 seq-int) (cons 1 tup)))
         (f-cond (make-frame (make-schema :inputs in-tup :target seq-tup)
                             (list (make-row :key 0 :known '((1 1) (0 2))
                                             :requirement (singleton-requirement seq-tup '((1 2) (2 3))))
                                   (make-row :key 1 :known '((1 1) (0 3))
                                             :requirement (singleton-requirement seq-tup '((1 3) (2 3))))
                                   (make-row :key 2 :known '((-1 -1) (4 2))
                                             :requirement (singleton-requirement seq-tup '((3 2) (2 1)))))))
         (lang-cond (make-language :int in-tup
                                   :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int)
                                                    (op :tuple tup) (op :at tup) (op :scan-tup))
                                   :literals '(0 1))))
    (multiple-value-bind (l-cond c-cond)
        (lift-frame f-cond (app (op :scan-tup) (var 0 seq-int) (var 1 tup) (var 2 step-tup)) 2 step-tup nil)
      (let ((j-cond (start-heuristic-synthesis f-cond lang-cond 260 :library-proposals-p t :library-functions '(:scan-tup))))
        (resume-synthesis j-cond 800000 :stop-on-first t)
        (format t "[Conditional Tuple Scan] lift-rows=~D coupled=~D solved@800k=~S work=~D~%"
                (length (frame-rows l-cond)) (length c-cond)
                (not (null (synthesis-job-best j-cond))) (ledger-total (synthesis-job-ledger j-cond))))))

  ;; 4. Stage A heuristic-buckets pair-guard discovery on projected 3-input frame
  (let* ((proj-in '((0 . :int) (1 . :int) (2 . :int)))
         (rows (loop for (s0 s1 a) in '((0 2 1) (1 2 1) (2 3 1) (3 4 -1) (2 4 -1) (5 2 -1) (3 2 -1))
                     for i from 0
                     collect (make-row :key i :known (list s0 s1 a)
                                       :requirement (singleton-requirement :int (if (= (+ s0 a) s1) (+ s1 a) s1)))))
         (f-proj (make-frame (make-schema :inputs proj-in :target :int) rows))
         (lang-proj (make-language :int proj-in :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int)) :literals '(0 1)))
         (led (make-ledger))
         (hm (condense-heuristic f-proj lang-proj :work-limit 30000 :ledger led))
         (mask (heuristic-hit-mask f-proj hm))
         (ib (remove-if-not (lambda (b) (eq :int (ast-type (car b)))) (heuristic-buckets hm)))
         (exact-g (loop for ((e1 . v1) . rest) on ib
                        thereis (loop for (e2 . v2) in rest
                                      when (equal (mapcar #'equal v1 v2) (mapcar #'not mask))
                                        return (term `(= ,e1 ,e2))))))
    (format t "[Stage-A Bucket-Pair Guard] stage-a-work=~D buckets=~D exact-guard=~S~%"
            (ledger-total led) (length ib) exact-g))

  ;; 5. Arity scaling diagnostic: bound invariance vs. Stage A heuristic-budget
  (let* ((in-3 (list (cons 0 seq-int) (cons 1 :int) (cons 2 :int)))
         (f-irr (make-frame (make-schema :inputs in-3 :target seq-int)
                            (list (make-row :key 0 :known '((1 1) 0 7) :requirement (singleton-requirement seq-int '(1 2)))
                                  (make-row :key 1 :known '((2 -1 3) 1 9) :requirement (singleton-requirement seq-int '(3 2 5)))
                                  (make-row :key 2 :known '((-2 4) 5 3) :requirement (singleton-requirement seq-int '(3 7))))))
         (lang-3 (make-language :int in-3 :operators (list (op :+ :int) (op :* :int) (op :scan)) :literals '(0 1))))
    (dolist (cfg '((90 nil) (110 nil) (90 30000)))
      (destructuring-bind (bnd hb) cfg
        (let ((j (apply #'start-heuristic-synthesis f-irr lang-3 bnd
                        :library-proposals-p t :library-functions '(:scan)
                        (when hb (list :heuristic-budget hb)))))
          (resume-synthesis j 1000000 :stop-on-first t)
          (format t "[Arity Scaling] bound=~D h-budget=~S => work=~D~%"
                  bnd hb (ledger-total (synthesis-job-ledger j)))))))

  ;; 6. Partially observed accumulator boundary: steps t >= 1 remain coupled
  (let ((f-proj0 (make-frame (make-schema :inputs (list (cons 0 seq-int) (cons 1 tup)) :target seq-int)
                             (list (make-row :key 0 :known '((1 1) (0 0))
                                             :requirement (singleton-requirement seq-int '(1 2)))))))
    (multiple-value-bind (l2 c2)
        (lift-frame f-proj0 (app (op :scan-proj0) (var 0 seq-int) (var 1 tup) (var 2 step-tup)) 2 step-tup nil)
      (format t "[Partial Accumulator Boundary] rows=~D coupled=~D~%" (length (frame-rows l2)) (length c2)))))
```
