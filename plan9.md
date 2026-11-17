# `lisploop` — Plan 9: Closing Heuristic Induction, Homoiconic Conditional Propagators, and Geometric-Topological Unification

> **Status:** Architectural audit and implementation specification (v1.0 — post-Plan-8 audit & refactor), 17 November 2026.
> Audited against the authoritative Common Lisp kernel on branch `charlie` at commit `019736f` (25 pure-kernel modules in `load.lisp`, `15,157` LOC + 6 milestone modules in `milestones/load.lisp`, `1,585` LOC; `182` kernel tests / `418,400` checks and `40` milestone tests / `186,771` checks passing), cross-referencing `plan8.md` (§5, §6.5–§6.7, Appendices A–C), `prompt4.md`, `architecture2.md`, `plan7/plan7.md`, `plan7/plan7-recursion.md`, `plan7/plan7-higher-order.md`, `plan7/plan7-library.md`, `plan7/plan7-m9-policy.md`, and `tests/README.md`.

---

## 1. Ground-Truth Baseline & Architectural Diagnosis (`019736f`)

### 1.1 What the Plan 8 Audit (`1bfb69d`) Settled vs. Remaining `main` Gaps

Commit `1bfb69d` delivered and audited several foundational mechanisms from `plan8.md`:

- **Metric pullback & subterm sharing:** `pulled-back-metric` and `metric-invariant-under-decoder-p` (`frame.lisp:448-526`) pull a parent `frame-metric` through invariant or pure-child decoders, and `share-repeated-subterms` (`frame.lisp:708-831`) factors repeated compound subterms behind `:code-eval`, solving Probe 5 (`tests/structural.lisp:210-234`) at default `:heuristic-budget 2000` in `264,353` work (`253` bits).
- **Coupled product joins & tuple set factoring:** Bounded coupled-slot pooling (`product-join-coupled`, `*max-coupled-slot-candidates* = 4`, `*max-coupled-combinations* = 256` in `synthesize.lisp:585-680`) and Cartesian tuple membership folding (`fold-member-tuple` in `requirements.lisp:308-322`) decompose multi-slot products without dropping cross-slot invariants.
- **Evidence grades & template generalization:** `:sampled` vs. `:exhaustive` attestation (`evidence.lisp:51-72`), evidence-gated `:unique-p` (`propagator-tested-p` in `laws.lisp:604-610, 787-793`), sampled integer solver replay (`lift-field-solvers` in `consolidate.lisp:513-652`), and `:decoder-template` anti-unification (`generalize-decoder-templates` in `proposals.lisp:1175-1236`) are operational.
- **Initial homoiconic repairs:** `simplify-symbolic-expr` (`laws.lisp:727-744`) normalizes via `fold-constants` plus library rewrite laws, `projection-row-keys` (`proposals.lisp:821-835`) enumerates compound input accessors in the VM, and `probe-values-for-type` centralizes probe values.

At the same time, `plan8.md:323` records five capabilities still absent relative to `main` (`67c015c`, `11,906` LOC vs. `charlie`'s `15,157` LOC):

1. Co-induced `(:*` $\leftrightarrow$ `:/)` multiplicative/affine metric decoder.
2. Conserved-sum / moment-difference heuristic solvers.
3. Stage B pullback for `:code-edit` residuals (`code-edit` at `frame.lisp:1520-1561` prices Stage A edits only; no Stage B decoder pulls back `:code` targets).
4. Bidirectional / rotating `:shift-seq` (current `install-sequence-shift-metric` at `bootstrap-inverters.lisp:296-345` supports forward zero-padded advances only, and sits in the pure kernel despite having zero kernel callers).
5. Explicit `:metric` keyword plumbing on top-level search and synthesis entry points (`start-synthesis`, `start-heuristic-synthesis`, `synthesize-recursive-function`).

### 1.2 Five Latent Source Bugs Identified in the Current Kernel

Auditing the Lisp source directly at `019736f` exposes five concrete bugs that silently degrade deduction, priority routing, metric condensation, and library consolidation:

1. **UIP Nogood Pattern Bypass & Unsound Positional Schema Matching (`nogoods.lisp:244-251, 314-341, 384-385`):**
   - `anti-unify-nogood-clauses` constructs `uip` via `(copy-nogood-clause first-ng)` (`L244`) without clearing `nogood-clause-bindings`. In `check-parent-nogoods` (`L384`), `(or (nogood-clause-bindings entry) (clause-expr-matches-known-p ...))` short-circuits to `T` whenever `first-ng` carried concrete bindings, skipping `clause-expr-matches-known-p` on the generalized `:uip-clause` hole pattern.
   - `check-library-nogood-schemas` (`L314-341`) zips `(first (row-known row))` positionally against `(first allowed)` (`(= (length seq-in) (length (first allowed)))`), assuming index $i$ of input maps to index $i$ of output—unsound on permuting combinators (`reverse`, `sort`) and blind to multi-input lifts.
2. **Disconnected M8D Return Calculation & Feature/Baseline Mismatch (`consolidate.lisp:5-89` vs. `synthesize.lisp:408-465`):**
   - `synthesis-episode-returns` (`consolidate.lisp:5-18`) computes realized M8D search returns $G_t = B_t - B_T - \lambda_{\mathrm{search}}(W_T - W_t)$, **but has zero callers anywhere in the codebase**.
   - Instead, `make-search-trace-frame` (`consolidate.lisp:20-56`) regresses a hardcoded 4-feature host formula `(+ f0 (* 2 f1) (floor search-work 64) (if solved-p 0 10))`, while `priority-predictor-function` (`synthesize.lisp:432-451`) passes 6 features and `node-priority` (`synthesize.lisp:458`) *overwrites* the exact full-path MDL price rather than predicting a bounded residual around it (forcing `tests/theories.lisp:175` to pass `:condense-heuristic-p nil`).
3. **Repeated VM Re-Typechecking, AST Allocation, & Triple Evaluation in `metric-delta` (`vm.lisp:416-526`, `laws.lisp:1201-1213`, `condense.lisp:218-236`):**
   - Whenever an entry calls a defined library `:function` (such as `:argmax-corr`), `compile-ast-fn` (`vm.lisp:416`) returns `nil` and `eval-entry-slot` (`vm.lisp:524`) falls back to raw `(evaluate ast inputs args :ledger ledger)`—re-running static `expression-type` validation and re-charging `value-work` on *every* `(candidate, row)` pair instead of caching a pre-validated `validated-program` inside `entry-executable`.
   - `metric-delta` (`laws.lisp:1209`) then allocates a fresh closed AST `(app operator (lit type predicted) (lit delta-type delta))` (inserting transient conses into `*node-meta*`) and invokes un-prepared `evaluate` even when `:witness` has current checked evidence.
   - Finally, `condense.lisp:218-236` discards `best-packet` from `select-closest-witness`, forcing `metric-residual-decompositions` (`decompose.lisp:46-52`) and `prepare-synthesis-node` to re-run the solver a 2nd and 3rd time. This accounts for the $30\times$ manual `:heuristic-budget 60000` override in `tests/metrics.lisp:214, 442`.
4. **Residual `:relation` Consolidation Failures (`relations.lisp:112-180`):**
   - `table-rows` / `find-compressing-expr` (`L112-126`) passes `:member` set payloads into `singleton-requirement`, crashing whenever a multi-valued relation has $\ge 4$ rows.
   - Line `156` checks `(null (knowledge-entry-expression entry))`, skipping 100% of synthesis-committed hybrid `:relation` entries because `commit-synthesis-job` (`consolidate.lisp:301`) populates `:parametric (heuristic-program h-model)` into `knowledge-entry-expression`.
   - Pass 2 (`L177`) checks `(< (* (length remaining) (body-size best inputs)) ...)` because it pastes duplicate AST copies into each relation rather than extracting one shared `:function` and calling it.
5. **Missing `:code-subst` Lineage Edges & Two-Pass Consolidation Ordering (`abstraction.lisp:515-520`, `consolidate.lisp:214, 946-964`):**
   - `combinator-call-code-args` (`abstraction.lisp:515-520`) recognizes `(lit (:code ...) ...)` arguments when recording `:refactored-by`/`:abstracts` edges in `define-function`, but misses `(app (:code-subst ...) ...)` closures—breaking downstream theory/functor transfer for parameterized lifts.
   - `commit-synthesis-job` (`consolidate.lisp:214`) defaults `:register-templates-p nil`, so `consolidate-knowledge-library` (`L947`) never records observed decompositions for `generalize-decoder-templates`.
   - `consolidate-knowledge-library` (`L956-963`) executes per-kind `:consolidate` hooks *before* `retype-knowledge-laws` and `lift-field-solvers`, requiring two calls to reach fixed-point (`tests/invariants.lisp:424-428`).

### 1.3 Unwired Seams & Why the Kernel LOC Gate Was Missed

As `plan8.md:287` observed, meeting the kernel simplification target requires retiring duplicated host mechanisms rather than micro-trimming lines:

- **Conditional propagators are split across rigid host builders:** All `346` lines of `bootstrap-inverters.lisp` plus `induce-solvers-from-transformers` (`templates.lisp:247-272`, which ignores source operator identity and drops source guards) hand-construct ASTs for special cases (`(= (f (f X0)) X0)`, unary `:map`, binary `(op elem param)`), while general search-based `(guard, witness)` solver discovery was left outside the kernel in `milestones/algebra-discovery.lisp:259-371`.
- **Target residuals have parallel Stage B paths:** `make-additive-residual-decoder` (`decompose.lisp:13-25`) hardcodes `+` alongside `metric-residual-decompositions` (`decompose.lisp:45`), while `filter-map-decompositions` (`proposals.lisp:148-298`, `150` LOC) hand-recognizes `(:map (:filter xs pred) mapper)` outside general combinator lifting.
- **Induced geometry and compositional addressing are built but disconnected from synthesis:**
  - `induce-row-order` and `with-induced-row-order` (`proposals.lisp:853-964`) have **zero callers** outside `tests/topology.lisp`; `:persistence` edges are ignored in Stage A's `relational-linkage-residual` (`enumerate.lisp:591-602`); and `generated-space-distance` (`milestones/corpus.lisp:455-462`) treats distinct scalar `:int` `:locality-key` values as unrelated partition classes (`2 + rank-dist`) instead of 1D metric coordinates $|k_a - k_b|$.
  - `frame-addressed-entries` (`descriptors.lisp:691-712`) and `find-knowledge-entries-by-address` (`knowledge.lisp:258-262`) have **zero callers** in `proposals.lisp`; `synthesize-io-descriptor-specs` (`descriptors.lisp:329-518`) is ~190 lines of 1D-sequence host templates; and `consolidate-policy-descriptors` (`consolidate.lisp:329-366`) nudges weights $\pm 1$ without ever synthesizing contrastive separators between colliding entries.

---

## 2. Unifying Around the Two Mathematical Motifs

Almost every operation in `lisploop` is an instance of one of two mathematical structures. Making those two structures explicit in code allows us to delete bespoke host recognizers while broadening generality.

### 2.1 Motif I: Topological Projection, Pullback/Lift, and Fiber Calculus

Every structural transformation in synthesis acts on the **input-requirement bundle** $\mathcal{E} \to \Omega$ whose base points $\omega \in \Omega$ carry known inputs $x_\omega \in \mathcal{X}$ and target requirement fibers $A_\omega(Y) \subseteq \mathcal{Y}$:

1. **Projection ($\pi: \Omega \to \mathcal{V}$):** Quotienting or forgetting coordinates—`project-frame-rows` (`frame.lisp:620-645`), `orient-available` (`frame.lisp:1664-1698`), and Stage A behavioral equivalence bucketing (`observation-bucket` in `enumerate.lisp:545-580`).
2. **Pullback & 1-to-Many Lift ($d^*: A_\omega(Y) \mapsto B_{\omega,c}(Z)$):** Pulling parent requirements back along an outer decoder $Y = d(X, Z)$ (`pullback-frame`, `product-slot-frame`, `lift-frame` in `frame.lisp:886-1242`). When $d$ invokes higher-order code $Z$ at call sites $c \in \{0, \dots, m_\omega - 1\}$ on row $\omega$, `probe-frame-coordinates` (`frame.lisp:1028-1104`) materializes the **evaluation cover** $\widetilde{\Omega} = \{(\omega, c)\}$ purely by metered VM probe execution.
3. **Fiber Narrowing (Conditional Propagators):** Intersecting pulled-back fibers $B_{\omega,c}(Z)$ with guarded inverse preimages $G(K, c) \Rightarrow Z \in W(K, c)$ (`propagate-requirements` in `laws.lisp:680-723`, `solve-equality-symbolically` in `laws.lisp:746-806`).
4. **Fiber Separation / Sectioning:** Whenever a projection or lift aliases two points $(\omega_1, c_1), (\omega_2, c_2)$ onto identical child inputs $\pi(\omega_1, c_1) = \pi(\omega_2, c_2)$ with incompatible target fibers $B_{\omega_1,c_1} \wedge B_{\omega_2,c_2} = \bot$, synthesis either records a deductive nogood or adjoins a **section coordinate** $\kappa(X)$ with $\kappa(\omega_1, c_1) \neq \kappa(\omega_2, c_2)$ to separate the colliding fibers.

#### Architectural Simplifications from Motif I

- **Unifying the Three Fiber-Separation Paths (`proposals.lisp:661-720`, `nogoods.lisp:282-346, 406-512`, `synthesize.lisp:476-484`):**
  Currently, first-order `dependency-expander`, higher-order `propose-dip-context-bindings` (DIP), and `check-library-nogood-schemas` duplicate collision detection and separator enumeration:
  - Replace index-aligned sequence zipping in `check-library-nogood-schemas` (`nogoods.lisp:314-341`) with `probe-frame-coordinates`, making persisted `:nogood-schema` checks sound on permuting/filtering/multi-input combinators and fixing the `anti-unify-nogood-clauses` `bindings` copy bug (`nogoods.lisp:244` $\to$ `(setf (nogood-clause-bindings uip) nil)`).
  - Unify separator candidate generation across `dependency-expander` and DIP around **(a)** library `:dip-feature` entries, **(b)** Stage A's already-evaluated `heuristic-buckets` on the parent frame, and **(c)** bounded enumerator features when Stage A buckets do not separate the conflict.
  - Drop the `(decomposition-lift-p proposal)` gate in `node-dip-repairs` (`synthesize.lisp:479`) so first-order projections `(:dependency f(X))` that hit `:incompatible-rows` conflicts are repaired by DIP (`(f(X), \kappa(X))`) identically to higher-order combinator lifts.
- **Retiring `filter-map-decompositions` (`proposals.lisp:148-298`, `-150` LOC):**
  `filter-map-decompositions` is a procedural hostcomprehension recognizer for `(:map (:filter xs pred) mapper)`. With partial/reentrant lifts properly scheduled (§4.3) and `:decoder-template` anti-unification wired (`:register-templates-p t`), `(:map (:filter xs pred) mapper)` arises as an ordinary two-step lift—first `:map` or `:filter` via partial/nested combinator proposals—and consolidates into a first-class `:decoder-template` entry in `*knowledge-library*`.

---

### 2.2 Motif II: Observed & Generated Geometries, Co-Induced Metrics, and Embeddings

Heuristic induction, heuristic-guided search, and heuristic-based language creation all instantiate **metric-chart and embedding induction** across three coupled discrete spaces:

| Space | Points | Observed Geometry | Generated / Library Geometry | Plan 9 Unification |
| :--- | :--- | :--- | :--- | :--- |
| **1. Target Space $(\mathcal{Y}, d_{\mathcal{L}})$** | Output values / ASTs $y \in \tau$ | Replacement bits `value-bit-size` & structural `:tuple-delta` / `:seq-delta` | Co-induced charts $(d, q)$ via `:metric-decoder` + pulled-back `frame-metric` | Single cached chart protocol covering `(+, -)`, `(*, /)`, rotating `:shift-seq`, `:code-subst` AU edits, and bipartite set matching |
| **2. Row / Corpus Space $(\Omega, d_{\Omega})$** | Frame rows $\omega \in \Omega$ or AST occurrences $o \in \mathcal{C}$ | Target variation $\sum_{(u,v)} d_{\mathcal{L}}(y_u, y_v)$ along `:persistence` chains | Coordinate embedding $k: \mathcal{X} \to \mathbb{Z}^d$ stored as `:locality-key` | $\mathbb{Z}^d$ tuple & scalar $L_1$ distance; live `with-induced-row-order` from Stage A buckets; soft `:persistence` residual pricing |
| **3. Concept / Library Space $(\mathcal{F}, d_{\mathcal{F}})$** | Library `:function`s, `:decoder-template`s, `:solver`s | Behavioral I/O traces on probes & job confusion outcomes | Symbolic coordinate map $\phi: \mathcal{F} \to \{0,1,*\}^K$ of `:descriptor` concepts in `compositional-index` | Homoiconic `:descriptor` seeds, contrastive separator synthesis across confusion classes, & progressive Tier $1 \to 2 \to 3$ variable-compute address decoding |

#### 1. Unifying Target Charts $(\mathcal{Y}, d_{\mathcal{L}})$
Every local coordinate chart on $\mathcal{Y}$ is a pair $(d: \tau \times \tau_\delta \to \tau,\; q: \tau \times \tau \rightharpoonup \tau_\delta)$ linked by `(:metric-decoder d q tag-bits)`:

- **Stage A (`priced-correction`):** Evaluates active charts $(d, q)$ on $(\hat{y}, y)$, scoring $\mathrm{tag}(d) + S_{\tau_\delta}(\delta)$ where $\delta = q(\hat{y}, y)$ and $d(\hat{y}, \delta) = y$, and **stores the winning chart packet `(:chart decoder-id delta)` directly in `heuristic-residual`**.
- **Stage B (`metric-residual-decompositions`):** Reads the winning chart(s) directly from `heuristic-residual` without re-evaluating `program` or `q`, proposing $Y = d(\hat{\pi}(X), Z)$ with $q$ attached as child propagator—and lifting scalar charts componentwise across homogeneous/heterogeneous `:tuple` targets automatically.
- **Consequences:**
  1. Retires bespoke `make-additive-residual-decoder` and the `(not (eq :+ ...))` exclusion in `decompose.lisp:13-67`: `(:+` $\leftrightarrow$ `:-)` is simply the built-in default 0-tag chart on `:int` and `(:gf p)`.
  2. Restores the `(:*` $\leftrightarrow$ `:/)` exact-factor chart (guarded by `(and (not (= pred 0)) (= (mod target pred) 0))`, plus affine remainder composition via standard Stage B depth 2).
  3. Closes **Stage B pullback for `:code-edit` (`plan8.md` §5.5, `L303`)**: when `code-edit` (`frame.lisp:1520-1561`) anti-unifies predicted `:code` literal $\hat{c}$ against target $c$ into pattern $p(?_0 \dots ?_{k-1})$ with fillings $(\delta_0, \dots, \delta_{k-1})$, Stage B emits the exact `:code-subst` / Constructor-AU product pullback $Y = \text{code-subst}(p, \text{tuple}(Z_0, \dots, Z_{k-1}))$ so child slots synthesize the varying sub-ASTs!
  4. Threads `:metric` cleanly onto `start-synthesis`, `start-heuristic-synthesis`, and `synthesize-recursive-function`.

#### 2. Wiring Row & Corpus Embeddings ($\Omega \to \mathbb{Z}^d$)

- **Multi-dimensional `:locality-key` embeddings (`proposals.lisp:771-776`, `milestones/corpus.lisp:447-507`):** Allow `:locality-key` entries to target either `:int` or flat integer tuples `(:tuple :int ...)` ($\mathbb{Z}^d$).
- **Fixing `generated-space-distance` (`milestones/corpus.lisp:455-462`) & multi-input keys (`L478`):** When a `:locality-key` produces scalar integers $k_a, k_b \in \mathbb{Z}$, measure $L_1$ coordinate distance $|k_a - k_b|$ (matching the tuple branch $\sum_i |k_{a,i} - k_{b,i}|$) rather than treating distinct integers as unrelated partition classes, and evaluate multi-input `:locality-key` expressions when subterm occurrences supply matching arity.
- **Zero-overhead `with-induced-row-order` in synthesis & soft `:persistence` pricing:** Invoke `with-induced-row-order` at the end of root Stage A condensation, passing `(heuristic-buckets h-model)` so candidate keys $k(X)$ are harvested at zero extra enumeration cost. In `relational-linkage-residual` (`enumerate.lisp:591-602`), keep `:persistence` edges zero-penalty on exact row hits (`plan8.md` §6.4.15) while adding a small variation tie-breaker $\lfloor d_{\mathcal{L}}(\hat{y}_u, \hat{y}_v) / 4 \rfloor$ on *non-exact* Stage A candidates so smooth approximations along the induced chain outrank jagged ones.

#### 3. Contrastive Descriptors & Variable-Compute Compositional Language (`prompt4.md` §9, `plan8.md` Appendix C.3–C.4)

- **Homoiconic seed `:descriptor`s (`descriptors.lisp`):** Express reusable I/O concepts (`len-eq`, `len-le`, `empty->empty`, `preserves-head`, `monotone-int`, tuple-projection preservation) as declarative `:descriptor` specifications in `*knowledge-library*`, retiring ~150 lines of 1D-sequence-only procedural AST builders in `synthesize-io-descriptor-specs` (`descriptors.lisp:329-518`).
- **Contrastive Separator Synthesis (`synthesize-contrastive-descriptors` in `consolidate.lisp`):**
  During `consolidate-knowledge-library`, form **confusion classes** of active `:function` and `:decoder-template` entries that either (a) collide on coarse compositional address tokens or (b) competed on a `synthesis-job` (one won while a sibling lifted and failed/conflicted). For each confusion pair $(f_1, f_2)$:
  1. Generate probe inputs $X$ via `probe-values-for-type`, computing $(X, f_1(X))$ and $(X, f_2(X))$ in the VM.
  2. Build a binary classification `frame` over `(X, Y) -> :bool` requiring `T` on $(X, f_1(X))$ and `NIL` on $(X, f_2(X))$ whenever $f_1(X) \neq f_2(X)$.
  3. Run a bounded `start-search` (`work-limit = 15000`, `bound = header + 28`) to synthesize a minimal Boolean separator $D(X, Y)$ (e.g., adjacent order `(<= (at Y 0) (at Y 1))` separating `sort` from `reverse`, or endpoint preservation `(= (at Y 0) (at X (- (length X) 1)))`).
  4. Validate $D(X, f_1(X))$ on finite/sampled probe domains (attesting `:sampled` or `:exhaustive` `:necessary` evidence as appropriate), register $D$ as a Tier-3 `:descriptor` with `:describes` edge to $f_1$, and re-index `compositional-index`.
- **Progressive Variable-Compute Address Decoding (`frame-addressed-entries` in `descriptors.lisp:658-713` $\to$ `library-decompositions` in `proposals.lisp:300-395`):**

  Replace the flat `(max-tier 2)` scan with staged variable-compute decoding:
  1. **Tier 1 ($O(1)$ type, arity, & boundary checks):** Filter `compositional-index` to compatible entries; if $\le k_{\mathrm{unambig}}$ (default `2`) entries survive, return immediately without running VM sequence loops.
  2. **Tier 2 (behavioral I/O descriptors):** Evaluate Tier-2 descriptors *only* `:describing` the surviving set; prune `:necessary` violations and rank survivors.
  3. **Tier 3 (contrastive separators & algebraic invariants):** Executed *only* on remaining ties/confusion classes where $\ge 2$ candidates score within `4` policy bits of the leader.

---

## 3. Homoiconic Conditional Propagators: Everything Searchable in `*knowledge-library*`

Conditional propagators are the primary bridge between syntax and fiber narrowing. Per architectural principle, **every propagator whose guard and witness can be discovered by search or derived from library laws belongs in `*knowledge-library*`, not in host Lisp**.

### 3.1 Kernel-Native Search for Conditional Solvers (`induce-conditional-solvers` in `laws.lisp`)

Promote and generalize solver discovery into the pure kernel as `induce-conditional-solvers(operator-or-fn &key positions library work-limit ledger)`:

1. **Empirical Fiber Construction:** For an operator or `:function` $f(X_0, \dots, X_{n-1}) \to \tau_Y$ and unknown index set $P \subset \{0, \dots, n-1\}$ (with known indices $K = \{0,\dots,n-1\} \setminus P$), evaluate $f$ on probe assignments from `probe-values-for-type`, grouping tuples by context $c = (X_K, y)$ into empirical fibers $F(c) = \{X_P \mid f(X_K, X_P) = y\}$.
2. **Witness Synthesis ($W(c)$):**
   - Build a `frame` mapping known context $c = (X_K, Y)$ to requirement `(member Z F(c))` over all non-empty fibers $F(c) \neq \emptyset$.
   - Run `start-heuristic-synthesis` / `condense-heuristic` to synthesize a minimal witness expression $W(X_K, Y)$ (supporting conditional witnesses `(if G_branch W_1 W_2)` as well as multi-witness finite-fiber list expressions when $|F(c)| > 1$ is bounded and uniform, e.g., `(cons Y (cons (- 0 Y) ()))` for `abs`).
   - Note how this automatically solves parameterized sequence functions like `(scale-seq xs p) = ys` at *both* position `0` (`xs = map(ys, / p)`) and position `1` (`p`, synthesizing a witness over non-zero elements instead of `bootstrap-inverters.lisp:78`'s fragile hardcoded `(at xs 0)`!).
3. **Necessary & Sufficient Guard Synthesis ($G(c)$):**
   - Partition evaluated probe contexts plus boundary counterfactuals $(X_K, y')$ into **replay-valid** contexts ($f(X_K, W(X_K, y')) = y'$) vs. **invalid** contexts ($F(c) = \emptyset$ or $f(X_K, W(X_K, y')) \neq y'$).
   - Synthesize minimal Boolean guard $G(X_K, Y) : \text{bool}$ via `start-search` / `find-sound-exception-guard` (discovering `(= (mod Y X0) 0)` and `(not (= X0 0))` for integer scaling, `(<= 0 Y)` for squares/abs, `(= (length X0) (length Y))` for pointwise sequence ops, etc.).
4. **Verification & Registration:** Certify exhaustively via `certify-solver-entry` on finite types or via `sampled-solver-validations` (`consolidate.lisp:513-558`, extended from `:int`/`:bool` to sequences and tuples via `probe-values-for-type`) on infinite types, registering the resulting `:solver` in `library`.

### 3.2 Law-to-Solver Extraction, Learned `:functor` AU, & Retiring `bootstrap-inverters.lisp`

We retire `bootstrap-inverters.lisp` (`346` LOC removed from `load.lisp` and `Makefile`) and `induce-solvers-from-transformers` (`templates.lisp:247-272`, which dropped source guards and operator checks), replacing them with three concise, domain-general mechanisms in `laws.lisp` and `templates.lisp`:

1. **General Law-to-Solver Extraction (`induce-law-solvers` in `laws.lisp`, ~35 LOC):**
   For any tested `:law` entry (`usable-motif-law-p` or guarded `:validated`/`:sampled` equation) of shape:
   $$G(\vec{v}) \implies (\mathrm{op}\; A_0 \dots A_{\mathrm{pos}} \dots A_{m-1}) = v_t$$
   where $v_t \in \vec{v}$ is a bare variable, each $A_j$ ($j \neq \mathrm{pos}$) is a variable $v_{k_j}$ disjoint from $v_t$ (so $\vec{k} = (v_{k_j})_{j \neq \mathrm{pos}}$ together with target $v_t$ determine all free variables of $A_{\mathrm{pos}}$ and $G$), register a `:solver` for `op` at `pos` with witness $W = A_{\mathrm{pos}}$ and guard $G$, inheriting the law's `:exhaustive` or `:sampled` witness evidence!
   - Subsumes `induce-involution-solvers` (`(= (f (f X0)) X0)`), mutual inverses `(= (enc (dec Y)) Y)`, group actions `(= (shift-seq (shift-seq XS K) (- 0 K)) XS)`, and right-cancellation laws `(= (+ (- Y K) K) Y)` in one unified rule.
2. **Learned `:functor` Anti-Unification (`laws.lisp`, ~55 LOC, fulfilling `plan7/plan7-library.md` §3.4):**
   Keep `:functor` as a first-class `define-knowledge-kind` (`:priority 40`, preserving all 9+ knowledge kinds in `tests/library.lisp` and `tests/invariants.lisp`), but replace the hardcoded Lisp builders of `bootstrap-inverters.lisp:28-249` with **edge-star anti-unification**:
   - When $\ge 2$ functions $f_1, f_2$ refactored through a higher-order combinator $C$ (`(:refactored-by C)` edges, now recorded for `:code-subst` closures too by fixing `abstraction.lisp:515-520`) possess `:solver` entries whose witnesses call $C$ over inverted step codes (or when $C$'s recursion body is length-preserving elementwise application and element `:solver`s exist), store the generalized `:code-match`/`:code-bind`/`:code-subst` transfer rule as the `:functor` entry's homoiconic AST—carrying elementwise target guards soundly via `all-elements` rather than silently dropping them (`bootstrap-inverters.lisp:70`)!
   - Expose `induce-functorial-solvers` as a thin wrapper invoking `(induce-law-solvers library)` + `:functor` consolidation + `(induce-conditional-solvers ...)` on newly refactored functions, keeping existing test call sites (`tests/library.lisp`, `tests/higher-order.lisp`, `tests/audit.lisp`) compatible.
3. **Relocating `install-sequence-shift-metric` to Test Fixtures (`tests/support.lisp` / `tests/metrics.lisp`):**
   Move `install-sequence-shift-metric` out of `load.lisp` into the test suite, upgraded to support **bidirectional / rotating integer shifts** ($k \in [-L, L]$) once static totality (§5.1) removes the dummy forward `(tail xs)` restriction.

### 3.3 Expressive Conditional Requirement Propagation (`laws.lisp` & `synthesize.lisp`)

1. **Finite-Set Preimages, Multi-Witness Complete Fibers, & Monotone Inequalities (`laws.lisp:582-723`):**
   - **Set propagation:** Generalize `extract-equality-target` to also match finite set memberships `(member term '(c_1 ... c_m))` ($1 \le m \le 8$). When a rule solves `(= term 'c_i)` for every $c_i$ (or refutes infeasible $c_i$ under a certified-necessary guard), rewrite the conjunct to the union `(member unknown '(w_1 ... w_r))`.
   - **Multi-witness complete fibers (`:fiber-set-p t`):** Allow a `:solver` returning `(:seq tau)` with metadata `:fiber-set-p t` to return the finite list of *all* inverse witnesses $W(K, c) = (w_1, \dots, w_r)$ for non-injective operators (`abs`, `sq`, truncating `/`, modular square roots). Certifying fiber completeness (`f(K, z) = c <=> member z W(K, c)`) lets `propagate-requirements` rewrite `(= (abs Z) '5)` $\to$ `(member Z '(5 -5))` **without** marking propagation ambiguous or spawning a `:fallback-p` clone!
   - **Monotone inequality propagation:** When a unary/binary `:solver` carries `:exhaustive` or `:sampled` monotonicity evidence (`:increasing` or `:decreasing`), propagate strict/non-strict bounds `(< (op 'k Z) 'c)` $\to$ `(< Z 'w)` (or flipped for `:decreasing`).
2. **Row-Assumption-Aware Propagation:**
   - Feed sibling conjuncts of `(row-requirement row)` into `propagate-requirements` and subsequent `fold-constants`: e.g., `(and (< '0 Z) (= (* Z Z) '9))` narrows via the complete fiber `(member Z '(-3 3))` and immediately folds against `(< '0 Z)` to `(= Z '3)` with zero fallback!
3. **Indexed Evidence-Ranked Dispatch, Solver-Aware Folding, & Deferred Fallbacks:**
   - Index `propagator-library` rules by `(operator-name . positions)` and sort each bucket by evidence grade: `(certified + complete) > certified > (sampled + complete) > sampled > conjecture`, eliminating greedy registration-order dependence (`laws.lisp:667-678`).
   - Pass an optional predicate `:preserve-operator-p` into `frame-conflict-p` / `fold-constants` so calls matching an active `:solver` are narrowed in **one** pass rather than running propagation twice around `callable-rules-library` (`synthesize.lisp:527-542`).
   - Queue ambiguous/tentative `:fallback-p t` clones onto `synthesis-node-deferred-proposals` (`synthesize.lisp:736-746`) instead of eagerly inserting them into `synthesis-job-nodes`, preventing speculative fallbacks from stealing 25% of reserve turns while the primary narrowed node is still actively improving.
4. **Intermediate Simplification & Boundary-Guarded Symbolic Orientation (`laws.lisp:746-911`):**
   - Call `simplify-symbolic-expr` on `expression` before each unwinding step in `solve-equality-symbolically` (so algebraic cancellations expose buried occurrences of `target-id`).
   - Wire `orient-conserved-quantity` into invariant/relational synthesis, and when symbolic unwinding produces `(values sym-expr guards certified-p)` where `guards` hold on $\ge 1$ row(s) but fail on boundary rows (e.g., division by `X0 = 0`), propose a guarded conditional decomposition `(if guard sym-expr Z_boundary)` so the child frame only has to solve the boundary fiber!

---

## 4. Closing Heuristic Induction, Search Control, & Consolidation Loops

### 4.1 VM `entry-executable` `validated-program` Cache & Fast `metric-delta`

1. **Pre-Validated AST Execution (`vm.lisp:473-526`):**
   Add `expr-program`, `guard-program`, and `aux-program` (`validated-program` structs from `prepare-program` in `vm.lisp:247-272`) to `entry-executable`. When `compile-ast-fn` returns `nil` (e.g., recursive or `:function`-calling entries like `:argmax-corr`), `eval-entry-slot` calls `evaluate-prepared` on the cached `validated-program`, bypassing repeated `expression-type` traversals and input `value-work` tariffs on every call while preserving exact VM step metering.
2. **Zero-Allocation `metric-delta` & Cached Residual Packets (`laws.lisp:1185-1218`, `condense.lisp:218-236`, `decompose.lisp:30-67`):**
   - Each tuple in `metric-decoders` carries a pre-prepared 2-variable `validated-program` for `(app operator (var 0 type) (var 1 delta-type))`.
   - When `(knowledge-evidence-current-p entry :witness)` holds, `metric-delta` skips forward replay altogether; when the solver is sampled/conjectured, it replays via `evaluate-prepared` on `(list predicted delta)` with **zero AST allocation** and zero `*node-meta*` growth.
   - `condense-heuristic` preserves `best-packet` per missed row inside `heuristic-residual`, so `metric-residual-decompositions` reads which metric decoder won on each row in $O(1)$ without re-running `eval-expr-value` or `metric-delta`.

### 4.2 Information-Gain / Bucket-Yield Adaptive `stage-a-budget`

`stage-a-budget` (`synthesize.lisp:363-380`) currently multiplies `base` (`2000`) by $2 \cdot \max(1, \text{arity}-1)^2$ unconditionally inside `lifted-p` branches and by `1` outside them—burning $8\times$ budgets on dead lifted combinators (Probe 4 regression `80k -> 113k`) while starving 3-input root/projection frames.

- **Design:** Replace the static multiplier cliff with an **adaptive yield-gated Stage A budget** inside `node-stage-a-model` / `condense-heuristic`:
  - Run Stage A in quanta of `base` (`2000` work), up to ceiling $B_{\max}(\text{arity}) = \text{base} \cdot \min(16, (1 + \max(0, \text{arity}-1))^2)$ on *both* lifted and multi-input frames.
  - After each quantum, continue to the next quantum **if and only if** the just-completed quantum either (a) strictly improved `best-score` ($S(p) + S(\varepsilon)$) or (b) increased behavioral feature diversity (`(length (heuristic-buckets job))` grew by $\ge \eta_{\min}$ non-constant buckets while grammar enumeration is still in low-size variable-combination tiers).
  - Stop immediately on exact hit (`stop-on-exact-p`) or zero yield. Dead lifts abort after 1 quantum (`2000` work); genuine 3-input conditional transitions (`plan8.md` Appendix A Probe 3 & Probe 5) scale smoothly until bilinear variable combinations are condensed.

### 4.3 Monotone Full-Path-Price Branch Closing & Online Marginal $J_{\mathrm{procedure}}$ Stopping

To close `plan8.md` §5.4 and Appendix C.1 (`synthesize.lisp:856-1180`):

1. **Incumbent Bound Pruning:** Whenever `synthesis-job-best` updates to verified score $J^* = J_{\mathrm{exact}}(M_{\mathrm{best}})$, tighten `synthesis-node-bound` on all open nodes and immediately close (`:phase :done`, `:expansion :done`) any node whose minimal composed root size (`full-path-minimal-bits`, substituting a minimal variable/literal at `child-id`) is $\ge J^*$.
2. **Monotone Full-Path-Price Branch Closing (with 1-Step Representation Grace):**
   Track `parent-full-price` $B(p)$ on each non-structural Stage B / library child $c$:
   - Allow at most **one** non-improving representation shift (`grace-used-p = t` when $B(c) > B(p)$) so a decoder that pays upfront header bits to expose a clean inner invariant can expand once.
   - If a grandchild $g$ under a `grace-used-p` branch still satisfies $B(g) \ge \min(B(p), B(c))$, mark $g$'s expansion `:done` and park its priority behind active improving lanes.
3. **Bounded Eager Fan-Out & Responsive Deferred Promotion:**
   - Default `*max-eager-proposals-per-node*` (`synthesize.lisp:983`) to `4` (keeping product-slot groups atomic).
   - Upgrade `promote-next-deferred-proposal` (`synthesize.lisp:856-863, 951`) so a node promotes its next deferred proposal whenever all of its *own* eager children have either closed (`:done`) or been prepared with `node-price` worse than the parent's Stage A baseline—ending the starvation of `:library-partial` and `:learned-template` proposals (`proposals.lisp:1093, 1319`).
4. **Online Marginal $J_{\mathrm{procedure}}$ Stopping (`resume-synthesis`):**
   Add `:stopping-policy` (`nil`, `:first`, or `:marginal-j` with `:search-weight`) to `resume-synthesis`: once at least one verified root solution $M_{\mathrm{best}}$ exists, halt online if an additional work window $\Delta W$ passes with $\Delta W \cdot \lambda_{\mathrm{search}} > B(M_{\mathrm{best}}) - B_{\mathrm{lower}}$, where $B_{\mathrm{lower}}$ is the best open lower bound across active lanes.

### 4.4 True M8D Residual Priority Predictor $\hat{\Delta}$ Around Analytical MDL

Fix `consolidate.lisp:5-89` and `synthesize.lisp:408-465`:

1. **Unified 6-Feature Trace Schema:** Standardize `node-trace-features` (`synthesize.lisp:408`) on the 6-integer tuple:
   `(full-program-bits residual-bits depth constrained-rows policy-score coupled-count)`.
2. **Return-Grounded Residual Targets:** In `make-search-trace-frame`, call `synthesis-episode-returns` on each job's trace (mapping node IDs to realized cost-to-go improvements) so each explored node's target is the **clipped integer residual** $\Delta^*(n) = \mathrm{clamp}(J_{\text{realized}}(n) - B_{\mathrm{MDL}}(n), -32, +64)$, where $B_{\mathrm{MDL}}(n)$ is the analytical `node-priority` formula (`synthesize.lisp:460-464`).
3. **Additive Residual Deployment:** In `node-priority`, evaluate $B_{\mathrm{MDL}}(n) + \mathrm{clamp}(\hat{\Delta}(f_n), -32, +64)$ instead of replacing $B_{\mathrm{MDL}}(n)$ outright. A zero predictor `0` reproduces exact analytical MDL; learned predictors adjust for empirical residual over/under-optimism without ever inverting asymptotic MDL scaling. Re-enable `:condense-heuristic-p t` in `tests/theories.lisp:175`.

### 4.5 Single-Pass Consolidation Fixed-Point, `:relation` Pooling, & Levin Amortization

1. **Single-Pass Consolidation Order (`consolidate.lisp:946-975`):**
   - Default `:register-templates-p t` in `commit-synthesis-job` (`consolidate.lisp:214`) so `remember-successful-decompositions` feeds `:decoder-template` generalization automatically.
   - Reorder `consolidate-knowledge-library` stages into topological dependency order:
     1. Ingest jobs, law validations, and observation laws.
     2. Retype laws across `retype-domains` (`retype-knowledge-laws`) and lift cross-field solvers (`lift-field-solvers`) *first*, so newly lifted integer laws and solvers are visible to theory hooks.
     3. Run `:consolidate` hooks (`:relation`, `:law`, `:motif`, `:functor`, `:decoder-template`) to fixed point (at most 2 internal micro-passes when a hook adds entries of an earlier kind).
     4. Synthesize contrastive `:descriptor`s, update policy descriptor weights, condense M8D residual `:heuristic`, and run utility amortization.
2. **Fixing `consolidate-residual-relations` (`relations.lisp:105-185`):**
   - Build per-row `member-requirement`s when a relation table stores multi-value sets instead of assuming `singleton-requirement`.
   - Include hybrid relations (`(and (knowledge-entry-residual entry) ...)` even when `knowledge-entry-expression` holds a non-exact Stage A `:parametric` base!), pricing candidate compression against `(knowledge-entry-bits entry)`.
   - In Pass 2 (multi-relation pooling across $\ge 2$ relations sharing `(domain, inputs, target)`), define **one** shared helper `:function` $g$ when `(+ (header-size inputs target) (body-size best inputs) (* k call-bits)) < sum_bits`, refactoring each relation to call $g$ and recording `:abstracts` / `:refactored-by` edges.
3. **Scale-Free Levin Search Tariff (`amortize-library-entries` in `consolidate.lisp:422-475`):**
   - Replace linear `(ceiling (* search-weight work))` (or support `:cost-model :levin` as the default) with the scale-free Levin charge $\lceil \log_2(1 + W_{\mathrm{failed}}) \rceil$ per failed lift (`plan8.md:274`), and extend amortization to `:decoder-template` entries and uncertified conjectured `:solver`s (attributing `:propagator-dispatch` + `:propagation-witness` + rejected witness replay work per solver entry).

---

## 5. Open Frontiers (`plan8.md` §5.1–§5.5 & Appendices B–C)

### 5.1 Static Totality Extensions (`ast.lisp`) & Homoiconic `(:fix-seq fuel init step)`

#### A. Generalizing `analyze-function-body-totality` (`ast.lisp:704-851`, Appendix C.2)
Replace Boolean `non-empty-vars` + single `decreasing-param-id` with a lightweight **structural rank environment** $\Gamma$ mapping each parameter $X_i$ to its proven branch lower bound (`(:seq-len>= k)` for sequences, `(:int>= b)` / `(:int-neq 0)` for integers):

1. **Multi-step sequence descent (`(tail^d X_i)`):** Propagate `(:seq-len>= 1)` into the false branch of `(= X_i ())` / `(< (length X_i) 1)`, and `(:seq-len>= (1+ k))` into the false branch of `(= (tail^k X_i) ())` or `(< (length X_i) '(k+1))`. Accept any self-call argument `(tail^d X_i)` ($1 \le d \le k$), certifying `pairwise`, `evens`/`odds`, and 2-step sliding recursions.
2. **Multi-parameter sum & lexicographic descent (`merge`):** Collect all recursive call vectors $\vec{a}^{(s)} = (\Delta_1^{(s)}, \dots, \Delta_m^{(s)})$ across self-call sites $s$, where $\Delta_i^{(s)} \in \{-\text{strict}, 0, +\text{unknown}\}$. Certify totality whenever there exists a non-empty parameter subset $S$ (sum measure $\sum_{i \in S} |X_i|$: every call site has $\Delta_i \le 0$ for all $i \in S$ and $\Delta_j < 0$ for at least one $j \in S$) or a parameter permutation (lexicographic measure)—certifying `merge(xs, ys)` and mutual countdowns immediately.
3. **Bounded `:int` descent (`range`, `shift-seq`, binary halving):** Under branch guard `(< 'b X_i)` (or `(and (<= '0 X_i) (not (= X_i '0)))`), certify `(- X_i 'c)` ($c \ge 1$, when $X_i - c \ge b - 1$) and positive integer halving `(/ X_i 'd)` ($d \ge 2$, under `(< '0 X_i)`) as strictly decreasing on the non-negative measure $\max(0, X_i - b)$.

#### B. Homoiconic `(:fix-seq fuel init step)` as a Library `:function` (Appendix B.3)
Rather than expanding `+operator-names+` in `ast.lisp`, define `:fix-seq` as a standard library `:function`:
```lisp
;; fuel : (:seq alpha), init : sigma, step : (:code ((0 . sigma)) sigma) -> sigma
(define-function :fix-seq (list (cons 0 seq-alpha) (cons 1 sigma) (cons 2 step-type)) sigma
  (lambda (self)
    (let* ((fuel (var 0 seq-alpha)) (state (var 1 sigma)) (step (var 2 step-type))
           (next-fn (lit (code-type (list (cons 0 seq-alpha) (cons 1 sigma) (cons 2 step-type)
                                          (cons 3 sigma))
                                    sigma)
                         (term `(if (= ,(var 3 sigma) ,(var 1 sigma))
                                    ,(var 1 sigma)
                                    (,self (tail ,(var 0 seq-alpha)) ,(var 3 sigma) ,(var 2 step-type)))
                               sigma))))
      (term `(if (= ,fuel ())
                 ,state
                 (code-eval ,next-fn ,fuel ,state ,step (code-eval ,step ,state)))
            sigma))))
```
**Two Specific Design Points to Test During Implementation:**

1. *Totality through `:code-eval` `let`-sharing:* Verify `analyze-function-body-totality` tracks `(tail fuel)` across an inline `:code-eval` of a quoted literal `next-fn` (or allow inlining closed `:code-eval` beta-redexes during totality checking so `next` is evaluated once at runtime while `self` sees `(tail fuel)` under `(= fuel ()) = nil`).
2. *Two-parameter polymorphic retyping & stationary equilibrium law:* Extend `retype-function-definition` (`proposals.lisp:24-110`) from 1 sequence element type to independent `(alpha, sigma)` type variables (so `:fix-seq` defined once over `(:seq :int)` and `:int` retypes to `fuel : (:seq (:tuple :int :int))` and `state : (:seq :int)`). Pair `:fix-seq` with a library `:law` / lift hook encoding the **stationary fixed-point condition**: on any row where `y != init` and convergence occurs within `< |fuel|` steps, `(code-eval step 'y) = 'y` holds as a `coupled = 0` Stage B constraint (retaining the full un-narrowed trajectory fallback if `|fuel|` exhausts early).

### 5.2 Minimum-$d_{\mathcal{L}}$ Bipartite Set Matching & Canonical `sort-by` Bootstrapping (Appendix B.1–B.2)

1. **Metered Hungarian / Shortest-Augmenting-Path Assignment (`frame.lisp`):**
   - Provide a reusable pure-kernel matcher `minimum-bipartite-correspondence(pred-seq target-seq elem-type &key metric decoders order-free-p ledger)` bounded by `*max-bipartite-set-size*` (`12`, falling back to positional `:seq-delta` above the bound so long streams remain $O(N)$).
   - Edge weights $C_{i,j}$ use `priced-correction(pred[i], target[j], elem-type)` (charging `ledger`), with insertion/deletion slack nodes weighted by `value-bit-size` + 2 tag bits.
   - **Order-free `:metric` mode:** Returns pure multiset edit cost $\sum_{(i,j)\in\pi^*} C_{i,j}$ (`0` bits on any permutation of the target set).
   - **Lossless `:bipartite-seq-delta` chart mode:** Adds permutation code length $\lceil \log_2(|\text{target}|! + 1) \rceil$ and emits portable `(:bipartite-seq-delta perm element-deltas)` handled by `apply-correction-packet` (`frame.lisp:1453-1489`), gated strictly below `(value-bit-size target seq-type)` so Galois soundness holds unconditionally.
2. **Closing the `:locality-key` Co-Induction Loop:**
   When a Stage A model achieves `0` element-edit bits under bipartite matching (differing from `target` only by permutation $\pi^*$), `induce-element-order-key` runs `induce-row-order` on the elementwise frame $e_j \mapsto j$, synthesizing the monotone tuple projection $\kappa(e)$ (e.g., `(at e 0)`) and proposing `(sort-by base-expr kappa)` in Stage B while registering $\kappa$ as a `:locality-key`!

### 5.3 Pure-Kernel Active Disambiguating Query Selection (`plan8.md` §5.3)

Add `propose-disambiguating-query(candidates-or-job &key inputs domain-guard (work-limit 20000) ledger)` in `explain.lisp` / `proposals.lisp`:

- Given $\ge 2$ distinct verified/surviving candidate expressions $\{e_1, \dots, e_k\}$ over `inputs` (or an underdetermined fiber), construct a **dual query-synthesis `frame`**:
  - **Target:** A single tuple value $x^* \in \text{tuple}(\tau_0, \dots, \tau_{n-1})$ (or scalar $\tau_0$ when unary) on a 1-row inputless frame.
  - **Requirement:** `(and domain-guard (not (= e_1(X) e_2(X))))` (and for $k > 2$, Stage A maximization of distinct output count $|\{e_1(x^*), \dots, e_k(x^*)\}|$).
- Solve using the kernel's own `start-search` / `condense-heuristic`, metered on `ledger`—producing minimal, valid disambiguating oracle inputs with zero external SMT machinery.

### 5.4 Coupled Intermediate Fibers & Latent State / Accumulator Abduction (`plan8.md` §5.1)

1. **Observation-Regime Contract (`:open-loop` vs. `:prequential`):**
   Annotate sequential schemas/lifts explicitly via `schema-availability-order` (`frame.lisp:1625-1698`): in `:open-loop` (`:scan`, `:scan-proj0`, `reverse-acc`), step $t$ sees only action $a_t$ and the recurrent state $s_t$ emitted by step $t-1$; in `:prequential` autoregressive prediction, step $t$ sees observed $y_{t-1}$ at a strictly earlier availability rank.
2. **Bounded Trajectory Fiber Narrowing (`lift-frame` in `frame.lisp:1150-1242` + `fibers.lisp`):**
   When `lift-frame` produces multi-step `coupled-requirements` (as in `plan8.md` Appendix A Probe 6: `(:scan-proj0 actions '(0 0) step)` where `(at s_1 0) = y_0` is observed, `(at s_1 1)` is unobserved, and `(= (at (code-eval step s_1 a_1) 0) y_1)` couples step $t=0$ and $t=1$):
   - Seed a decoupled partial child frame from the anchored $t=0$ rows plus any stationary/boundary rows.
   - Enumerate/condense candidate transitions `step` on the anchored sub-frame, and validate/score candidates on the coupled multi-step rows via forward VM trajectory rollout (`coupled-trajectory-admissible-p`, analogous to `coupled-combination-admissible-p` in `synthesize.lisp:613-632`), combined with backward conditional propagator narrowing (`propagate-requirements`) from $y_t$ through candidate `step` skeletons to restrict latent coordinates $s_{t,\text{lat}}$.
3. **Latent State Product-Extension Proposal (`:latent-scan` / accumulator abduction):**
   When lifting a stateful combinator (`:scan` or `:fold`) over observed type $\tau$ fails with an unrepairable fiber collision—specifically, two call coordinates $(\omega_1, t_1), (\omega_2, t_2)$ share identical $(s_{\text{obs}}, a)$ inputs yet require incompatible next outputs $y'$, and no input projection $\kappa(X)$ separates them because the varying quantity is dynamic—propose a **latent-register lift** expanding state $\tau \to \text{(:tuple }\tau\text{ :int)}$ (or `(:tuple tau (:seq elem))` for sequence accumulators like `reverse-acc`) initialized at a synthesized literal (`0` or `()`) and projected via `(at state 0)` at output! This reduces hidden-state abduction directly to coupled product-slot synthesis (`synthesize.lisp:634-680`) + trajectory rollout screening.

---

## 6. Candidate Phase Breakdown (`P9.1` – `P9.5`), Verification Gates, & LOC Budget

*(Note: Phases below group tightly coupled changes into self-contained, independently testable increments; execution sequence to be finalized after plan review.)*

| Phase | Core Deliverables | Primary Modules Touched | Key Semantic Verification Gates |
| :--- | :--- | :--- | :--- |
| **`P9.1` Substrate, Totality, VM Cache & Homoiconic Propagators** | Fix 5 latent bugs (§1.2, except M8D in `P9.2`); `entry-executable` `validated-program` cache & zero-alloc `metric-delta` + cached chart packet; unified target `:metric-decoder` (`(+, -)`, `(*, /)`, `:code-edit` Stage B pullback, `:metric` kwarg); `induce-conditional-solvers`, `induce-law-solvers`, learned `:functor` AU, set/complete-fiber/assumption propagation, solver-aware single fold, deferred fallbacks; unified fiber-separation (`probe-frame-coordinates` + DIP on projections); retire `bootstrap-inverters.lisp` & `filter-map-decompositions`; generalize `analyze-function-body-totality` | `vm.lisp`, `ast.lisp`, `frame.lisp`, `laws.lisp`, `templates.lisp`, `condense.lisp`, `decompose.lisp`, `nogoods.lisp`, `proposals.lisp`, `synthesize.lisp`, `relations.lisp`, `abstraction.lisp`, `load.lisp`, *(retire `bootstrap-inverters.lisp`)* | `tests/metrics.lisp` passes at default `:heuristic-budget 2000` (dropping `60000`); `tests/higher-order.lisp` Filter-Map, involution, & functor suites pass with `bootstrap-inverters.lisp` & `filter-map-decompositions` gone; new tests for `merge`/`pairwise`/`range` totality, complete-fiber `abs`/`sq` propagation without fallback, `:code-edit` Stage B pullback, and search-discovered `:solver`s |
| **`P9.2` Heuristic Control, M8D & Consolidation Closure** | Yield-gated adaptive `stage-a-budget`; incumbent lower-bound pruning, 1-grace monotone full-path branch closing, `*max-eager-proposals-per-node* = 4` + responsive deferred waking, `:stopping-policy :marginal-j`; 6-feature return-grounded M8D residual predictor $\hat{\Delta}$; `:register-templates-p t` default, 1-pass consolidation order, Levin $\log_2 W$ amortization across functions/templates/solvers | `synthesize.lisp`, `condense.lisp`, `consolidate.lisp` | `plan8.md` Appendix A Probe 3 (asymmetric conditional tuple scan) solves $< 350\text{k}$ work; Probe 4 $< 85\text{k}$; 1-call `consolidate-knowledge-library` idempotence (`tests/invariants.lisp`); `:condense-heuristic-p t` enabled & beneficial on `tests/theories.lisp` |
| **`P9.3` Co-Induced Embeddings & Language Creation** | $\mathbb{Z}^d$ tuple & scalar $L_1$ `:locality-key` embeddings; multi-input `generated-space-distance`; Stage-A-bucketed `with-induced-row-order` wired at root + soft Stage A `:persistence` tie-breaker; homoiconic seed `:descriptor`s; `synthesize-contrastive-descriptors` across confusion classes; progressive Tier $1 \to 2 \to 3$ `frame-addressed-entries` routing in `library-decompositions` | `proposals.lisp`, `enumerate.lisp`, `descriptors.lisp`, `consolidate.lisp`, `milestones/corpus.lisp` | Automatic synthesis of contrastive separator between `reverse` and `sort` during consolidation; $>50\%$ reduction in `library-decompositions` orientation + false-lift work on 8+ combinator libraries; row-permutation invariance preserved |
| **`P9.4` `(:fix-seq)`, Set Matching & Active Queries** | Library `:fix-seq` + 2-param `retype-function-definition` + stationary `(= (code-eval step Y) Y)` lift law; metered Hungarian bipartite set metric & `:bipartite-seq-delta` chart + `sort-by` `:locality-key` bootstrapping; pure-kernel `propose-disambiguating-query`; moment-difference heuristic solvers | `proposals.lisp`, `frame.lisp`, `laws.lisp`, `explain.lisp` | Graph reachability / transitive closure over shuffled `(:seq (:tuple :int :int))` edge lists solved via `:fix-seq` + bipartite matching; canonical `sort-by` induced from matched fibers; minimal oracle query disambiguation |
| **`P9.5` Coupled & Latent Fibers** | Explicit `:open-loop` vs. `:prequential` availability contract; anchored $t=0$ seeding + VM trajectory rollout screening + backward propagator narrowing on multi-step `coupled-requirements`; latent-register product lift `tau -> (:tuple tau tau_L)` on unrepairable dynamic state collisions | `frame.lisp`, `fibers.lisp`, `proposals.lisp`, `synthesize.lisp` | `plan8.md` Appendix A Probe 6 (`:scan-proj0` with hidden 2nd register) and `reverse-acc` / stateful transducer synthesis solved through general kernel decomposition |

### Non-Negotiable Kernel Invariants Preserved Across All Phases
1. **Pure-Kernel Isolation (`tests/run.lisp:61-71`):** `load.lisp` has zero dependencies on `milestones/` or test fixtures.
2. **Deterministic Unit-Step Preemption (`check-anytime-resumption`, `tests/support.lisp`):** Every host preparation, propagation, bipartite assignment, and Stage A quantum stages work onto private ledgers and publishes only via `stage-work` / `pay-debt` (`1`-unit vs. `97`-unit parity).
3. **Zero-False-Pruning Galois Soundness (`tests/invariants.lisp`):** Every metric chart (`:bipartite-seq-delta`, `:code-edit`, `(*, /)`) gates bit price against raw replacement and verifies replay; tentative/sampled propagators and stationary `:fix-seq` hypotheses preserve deferred un-narrowed fallbacks; branch closing prunes *hard* only against verified root upper bounds $J^*(M_{\mathrm{best}})$ and parks (rather than deletes) speculative non-monotone branches under the 3:1 reserve.
4. **Representation & Permutation Invariance (`tests/invariants.lisp`):** Row-order induction canonicalizes via `canonical-row-order`; all input projections and multi-parameter retypings key on `(id . type)` alists rather than contiguous `0..n-1` indices.
5. **Single-Pass Consolidation & Serialization Fixed Point (`tests/invariants.lisp:400-465`):** One call to `consolidate-knowledge-library` reaches semantic fixed point and round-trips losslessly through `serialize-knowledge-library` / `deserialize-knowledge-library`.

### Expected Pure-Kernel LOC Balance (`load.lisp`)

| Change Group | Retired / Consolidated | Added | Net LOC |
| :--- | :---: | :---: | :---: |
| Retire `bootstrap-inverters.lisp` (`-346`), `induce-solvers-from-transformers` (`-26`), `filter-map-decompositions` (`-150`), & `make-additive-residual-decoder` (`-20`); add `induce-conditional-solvers`, `induce-law-solvers`, learned `:functor` AU, & richer propagation | `-542` | `+215` | **`-327`** |
| Unify fiber separation (`dependency-expander` + DIP + `check-library-nogood-schemas` via `probe-frame-coordinates`) | `-195` | `+75` | **`-120`** |
| Replace procedural 1D `synthesize-io-descriptor-specs` with homoiconic library `:descriptor`s + contrastive separator synthesis + progressive Tier $1 \to 3$ decoding | `-205` | `+125` | **`-80`** |
| VM `validated-program` cache, static totality generalization, adaptive `stage-a-budget`, branch closing, M8D residual fix, `:relation` & consolidation fixes | `-95` | `+160` | **`+65`** |
| `(:fix-seq)` support, bipartite set matching, `propose-disambiguating-query`, & coupled/latent fiber abduction (`P9.4`–`P9.5`) | `-15` | `+315` | **`+300`** |
| **Total Across `P9.1`–`P9.5`** | **`-1,052`** | **`+890`** | **`-162` net (`-462` net across `P9.1`–`P9.3`)** |
