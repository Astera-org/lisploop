# Plan 7 -- Milestone 9: Partial Fiber Expansions, Compositional Names, and Computed Policy Heuristics

> [!IMPORTANT]
> **Governing Principle (`prompt4.md` Alignment)**
> You do not need to run an entire calculation---or unroll an entire recursive or multi-dimensional structure---to estimate whether a hypothesis holds. A meta-function with $b$ bits of freedom is constrained by $O(b)$ scalar fiber observations. Conversely, an operator, decoder, rewrite, or solver in the knowledge library should not be addressed solely by an opaque symbol (`:fa`, `:DECODER-TEMPLATE-0`), but also by a **secondary compositional address** formed from the **overlapping set of cheap, substance-specialized heuristic descriptors** that trigger and weight its execution.

---

## 0. Executive Summary & Architectural Diagnosis

Auditing the 16-module Common Lisp kernel after the higher-order (`H1`--`H4`) and modularization (`R1`--`R11`) refactors reveals two tightly coupled bottlenecks that M9 resolves together:

1. **Higher-Order Lifting Unfolds Everything Upfront (`frame.lisp`, `requirements.lisp`, `synthesize.lisp`)**:
   * [`lift-frame`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L562-L663) currently runs [`pullback-frame`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L244-L280) and [`fold-constants`](file:///home/tlh24/sandbox/team/tlh/lisploop/requirements.lisp#L276-L315) across **every element of every parent row** before [`select-active-fiber-rows`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L515-L560) truncates the result to `*max-active-lifted-rows*`.
   * Worse, in [`fold-constants`](file:///home/tlh24/sandbox/team/tlh/lisploop/requirements.lisp#L302-L311), if the unfolding budget (`remaining`) hits `0` on element $k$ of a large sequence or grid, `(if (zerop remaining) rebuilt res)` **reverts the entire outer `:cons` equality chain back to `rebuilt`**, yielding 0 scalar fibers and collapsing to `:status :coupled`.
   * In [`prepare-synthesis-node`](file:///home/tlh24/sandbox/team/tlh/lisploop/synthesize.lisp#L1200-L1269), `lift-frame` executes **before** Stage A (`node-stage-a-model`), forcing every proposed higher-order combinator or template to pay full unfolding work before the agenda can even score whether the branch is plausible.

2. **Library Names & Triggers Are Opaque and Unweighted (`factor.lisp`, `proposals.lisp`, `synthesize.lisp`)**:
   * Library entries carry arbitrary sequential names (`:fa`, `:fb`, `:DECODER-TEMPLATE-0`) and at most a single boolean `knowledge-entry-trigger` produced by [`compute-function-descriptor`](file:///home/tlh24/sandbox/team/tlh/lisploop/factor.lisp#L2278-L2324).
   * [`library-function-descriptor-compatible-p`](file:///home/tlh24/sandbox/team/tlh/lisploop/proposals.lisp#L110-L139) only consults descriptors attested as `:necessary` (as a hard boolean gate) and ignores `:empirical` descriptors altogether.
   * When `:register-templates-p t` is enabled (`R8` in [audit-review.txt](file:///home/tlh24/sandbox/team/tlh/lisploop/audit-review.txt)), every stored `:decoder-template` is unconditionally proposed and fully prepared (`pullback-frame` + `lift-frame` + Stage A), causing warm discovery work on `inc-list` to jump from `19,147` to `48,573`.
   * Meanwhile, the M8D search-trace predictor ([`node-trace-features`](file:///home/tlh24/sandbox/team/tlh/lisploop/synthesize.lisp#L1109-L1119)) sees only 4 scalar integers `(prog-bits, res-bits, depth, constrained-rows)`---completely blind to frame types, shapes, shape deltas, sampled contents, and operator identity (and suffers from a 4-vs-6 input arity mismatch against [tests/library.lisp](file:///home/tlh24/sandbox/team/tlh/lisploop/tests/library.lisp#L123-L148)).

### Design Decisions
1. **Compositional Name as Secondary Address**: Primary `knowledge-entry-id` values (`:fa`, `:map`, `:DECODER-TEMPLATE-0`, etc.) remain unchanged for full backward compatibility. Each entry's compositional descriptor name (e.g., `:COMB/SEQ->SEQ/LEN-EQ/EMPTY->EMPTY/POINTWISE`) is exposed as a **secondary address** (`knowledge-entry-compositional-name`, indexed in `knowledge-library-compositional-index` and queryable via `find-knowledge-entries-by-address`).
2. **Deferred Proposal Records (Lazy Execution Until Budget Permits)**: Candidate proposals are scored cheaply via overlapping policy descriptors *before* pullback/lifting. Proposals outside the immediate top-$B$ expansion batch are retained as lightweight `deferred-proposal` records on the agenda/node without executing `pullback-frame`, `lift-frame`, or Stage A until the search budget and agenda priority reach them.

---

## Part I (`M9.1`): True Partial & Budget-Calibrated Fiber Expansions

### 1.1 Partial Head-Prefix Unfolding in `requirements.lisp`

**Problem**: In [`fold-constants`](file:///home/tlh24/sandbox/team/tlh/lisploop/requirements.lisp#L302-L311), splitting `(= (cons h tail) '(v0 v1 ...))` under `:contract :necessary` builds `(and (= h 'v0) (= tail '(v1 ...)))`, recurses on both branches, and then checks `(if (zerop remaining) rebuilt res)`. When `remaining` reaches `0` deep inside `tail`, the entire conjunction is discarded and replaced with the unsplit `rebuilt` term.

**Design**:
1. Add `:max-fibers` (default `nil` under `:equivalent`, integer $k$ under partial lifting) to [`fold-constants`](file:///home/tlh24/sandbox/team/tlh/lisploop/requirements.lisp#L276-L315).
2. Track `fibers-emitted` alongside `remaining` budget when unfolding recursive sequence/grid equalities under `:contract :necessary`:
   * When splitting `(= (cons h tail) (lit (:seq tau) (v0 . vs)))`:
     * Always fold the head fiber `(= h 'v0)` first with a bounded per-fiber budget slice so `remaining` cannot be exhausted mid-head by the tail.
     * Increment `fibers-emitted` whenever `h` resolves into a concrete scalar/row constraint.
     * If `(or (zerop remaining) (and max-fibers (>= fibers-emitted max-fibers)))`:
       * **Do not revert `h`!**
       * Under `:contract :necessary`, retain the folded head conjunct `h-folded` (returning `(lit :bool t)` for the dropped tail conjunct `(= tail 'vs)`), and record `(= tail 'vs)` in a `deferred-conjuncts` list returned as the third value of `fold-constants`.
3. For nested 2D/tensor structures (`(:seq (:seq :int))`, e.g. outer products, matrix contractions, stencils), bound the outer and inner fiber counts so a $64 \times 64$ grid unfolds only a $2 \times 2 = 4$ fiber corner/patch in $O(k)$ work.

### 1.2 Coordinate-Targeted Pullback Probes & Contiguous Window Selection

Many higher-order hypotheses (index shifts $i \pm s$, discrete derivatives $\Delta X_i = X_{i+1} - X_i$, transposes $A_{j,i}$, outer products $u_i v_j$, contractions $\sum_k A_{i,k} B_{k,j}$) have a meta-function specified by a tiny number of bits.

**Design**:
* Introduce `probe-frame-coordinates (frame decoder &key probe-coords ledger)` in [frame.lisp](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp):
  * Projects parent sequence/grid requirements at selected coordinates (e.g., `((0) (1))` for 1D or `((0 0) (0 1) (1 0) (1 1))` for 2D) into necessary coordinate obligations `(= (at Y i) 'v_i)`.
* Upgrade [`select-active-fiber-rows`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L515-L560) to implement the **3:1 locality-to-canonical contiguous window** policy:
  * **Current bug**: Pass 2 selects `(first group)` (index $0$) and `(car (last group))` (index $L-1$), destroying adjacency `(j, j+1)` whenever $L > 2$.
  * **Fix**:
    1. Pass 1: Any unsatisfiable row (immediate refutation).
    2. Pass 2 (Co-local contiguous window, $\lceil \frac{3}{4} K \rceil$ slots): For each parent row, select **adjacent pairs** starting from the left boundary `(fiber 0, fiber 1)` (followed by `fiber 2` and right boundary `fiber L-1` as slots permit). This guarantees that first differences $\Delta_j = f(j+1) - f(j)$ and local stencils are preserved inside the active sample.
    3. Pass 3 (Canonical diversity, $\lfloor \frac{1}{4} K \rfloor$ slots): Distinct interior input values `k0` not covered by the boundary window.

### 1.3 Evidence-Calibrated Anytime Fiber Schedule $k(t)$

* When `lift-frame` is called during node preparation, pass `:max-unfold-fibers` calibrated to `max-active-rows` (so each parent row unfolds only enough fibers to populate the active window plus a small reserve, e.g., $\max(2, \lceil K / R \rceil + 1)$ fibers per parent row), saving the unexpanded tail equalities in `reserve-rows`.
* When a branch solves its active fibers or reaches root ratification (`verify-model-against-frame`), if any reserve/tail obligations fail, `expand-lifted-reserve-fibers` unfolds the next batch ($2\times$ fibers) from the deferred continuations.

---

## Part II (`M9.2`): Substance-Specialized Meta-Heuristics & Sequence-Aware Stage A

### 2.1 Smooth Sequence Residual Pricing in `frame.lisp`

**Problem**: [`correction-bit-size`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L980-L1002) treats `:seq` as atomic (`((:seq :code) (value-bit-size target type))`). If a candidate program predicts `'(2 4 6 8)` for target `'(2 4 6 9)`, it pays the full replacement cost of `'(2 4 6 9)` instead of 1 element delta.

**Design**:
Update [`correction-packet`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L946-L961), [`apply-correction-packet`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L963-L978), and [`correction-bit-size`](file:///home/tlh24/sandbox/team/tlh/lisploop/frame.lisp#L980-L1002) for `(:seq elem-type)`:
* When `predicted` and `target` are both lists:
  * Price the length displacement $\Delta L = \text{len}(\text{target}) - \text{len}(\text{predicted})$ in `(if (zerop dL) 1 (1+ (value-bit-size dL :int)))` bits.
  * Over the shared prefix $m = \min(\text{len}(\text{predicted}), \text{len}(\text{target}))$: sum `(if (equal p_i t_i) 1 (1+ (correction-bit-size p_i t_i elem-type t)))`.
  * Over any missing suffix of `target` (when $\Delta L > 0$): sum `(value-bit-size t_i elem-type)`.
  * Cap at `(value-bit-size target type)`.
* Keep `correction-packet` / `apply-correction-packet` round-trip exact (`(equal (apply-correction-packet pred (correction-packet pred target type t) type t) target)`).

### 2.2 Substance-Specialized Fast Guards (Meta-Heuristics)

Before unfolding a candidate operator or template on a frame $\Omega$, substance-specialized meta-heuristics test necessary or strongly indicative invariants in $O(1)$ to $O(k_0)$ work:
* **1D Pointwise Maps**: $\forall r,\; \text{len}(Y_r) = \text{len}(X_{r,0}) \land (X_{r,0}=() \Rightarrow Y_r=())$.
* **Filters / Subsequences**: $\forall r,\; 0 \le \text{len}(Y_r) \le \text{len}(X_{r,0}) \land \text{subset}(Y_r[0..k_0], X_{r,0})$.
* **Discrete Derivatives / Stencils**: $\forall r,\; \text{len}(Y_r) = \max(0, \text{len}(X_{r,0}) - 1)$ + adjacent-index dependency probe.
* **Outer Products / 2D Lifts**: $\text{rank}(Y) = 2,\; \text{shape}(Y_r) = (\text{len}(X_{r,0}), \text{len}(X_{r,1}))$, plus $2\times 2$ minor probes ($Y_{00}Y_{11} = Y_{01}Y_{10}$ for multiplicative outer product; $Y_{00}+Y_{11} = Y_{01}+Y_{10}$ for additive outer table).
* **Contractions / Reductions**: $\text{rank}(Y) < \text{rank}(X)$, empty-list identity (`0` for additive, `1` for multiplicative).
* **Permutations / Reversals**: $\text{len}(Y_r) = \text{len}(X_r) \land \sum Y_{r,i} = \sum X_{r,i}$.

---

## Part III (`M9.3`): Meaningful Compositional Names & Secondary Addressing Space

### 3.1 `descriptor-clause` and Compositional Profiles

Every knowledge entry $e$ (`:function`, `:decoder-template`, `:law`, `:solver`, `:transformer`) receives a **Compositional Descriptor Profile** stored in `(getf (knowledge-entry-metadata entry) :descriptor-profile)` and a secondary compositional address stored in `(getf (knowledge-entry-metadata entry) :compositional-name)` (accessible via `knowledge-entry-compositional-name` and indexed in `knowledge-library-compositional-index`):

```lisp
(defstruct descriptor-clause
  id              ; keyword naming the shared :descriptor entry, e.g. :DESC/LEN-EQ
  facet           ; :type | :shape-delta | :boundary | :sampled-content | :algebraic
  tier            ; 0 (type/shape O(1)), 1 (row-shape/boundary O(R)), 2 (k-fiber probe O(k)), 3 (relational)
  status          ; :necessary (hard guard when false) | :empirical (soft log-odds weight)
  weight-bits     ; positive integer MDL bonus (in bits) when satisfied, penalty when violated
  work-cost)      ; expected VM steps to evaluate on a sample
```

### 3.2 Five Compositional Facets
1. **Facet 1 --- `:type` (Tier 0)**: Input/output type constructors and higher-order `:code` hole arities (`SEQ->SEQ`, `CODE+SEQ->SEQ`, `SEQ2->GRID`, `SEQ->INT`, `INT->INT`).
2. **Facet 2 --- `:shape-delta` (Tier 1)**: VM-executable boolean descriptors over input/output lengths and inner grid dimensions (`:DESC/LEN-EQ`, `:DESC/LEN-LE`, `:DESC/LEN-DEC-1`, `:DESC/OUTER-SHAPE-2D`, `:DESC/SCALAR-REDUCTION`).
3. **Facet 3 --- `:boundary` (Tier 1)**: Base-case behavior on empty sequences or zero scalars (`:DESC/EMPTY->EMPTY`, `:DESC/EMPTY->ZERO`, `:DESC/EMPTY->ONE`, `:DESC/ZERO->ZERO`).
4. **Facet 4 --- `:sampled-content` (Tier 2)**: Sampled fiber properties evaluated on up to $k_0$ elements (`:DESC/SUBSET-ELEMENTS`, `:DESC/CONSTANT-STEP-DELTA`, `:DESC/RANK1-2X2-MULT-MINOR`, `:DESC/RANK1-2X2-ADD-MINOR`, `:DESC/ADJACENT-DIFF-DEP`, `:DESC/SUM-INVARIANT`).
5. **Facet 5 --- `:algebraic` (Tier 3)**: Relational neighborhood tags (`:DESC/INVOLUTION`, `:DESC/COMMUTATIVE`, `:DESC/ASSOCIATIVE`, `:DESC/FUNCTORIAL-MAP`).

---

## Part IV (`M9.4`): Overlapping Policy Heuristics & Deferred Proposal Execution

### 4.1 Frame-Cached Descriptor Evaluation & Overlapping Policy Scoring

For any frame $\Omega$, `evaluate-frame-descriptors (frame library &key sample-size ledger)` evaluates active Tier 1--2 `:descriptor` entries once on a $k_0$-row/fiber sample and caches the truth status (`:all-true`, `:some-false`, `:indeterminate`).

For any candidate entry $e$ with descriptor clauses $\{(d_i, \text{status}_i, w_{e,i})\}$:
$$\Delta J_{\text{policy}}(e \mid \Omega) = \sum_{i} \begin{cases}
+\infty \text{ (prune)} & \text{if } \text{status}_i = \text{:necessary} \land d_i(\Omega) = \text{:some-false} \\
-w_{e,i} \text{ (bit bonus)} & \text{if } d_i(\Omega) = \text{:all-true} \\
+\lceil w_{e,i}/2 \rceil \text{ (bit penalty)} & \text{if } \text{status}_i = \text{:empirical} \land d_i(\Omega) = \text{:some-false} \\
0 & \text{if } d_i(\Omega) = \text{:indeterminate}
\end{cases}$$

### 4.2 Deferred Proposal Queue (Keeping Proposals Without Executing Until Budget Permits)

In [`expand-synthesis-node`](file:///home/tlh24/sandbox/team/tlh/lisploop/synthesize.lisp#L2481-L2530):
1. All proposals from [`propose-decompositions`](file:///home/tlh24/sandbox/team/tlh/lisploop/synthesize.lisp#L2366-L2432) are first scored cheaply using their decoder syntax cost + `policy-adjustment` $\Delta J_{\text{policy}}(e \mid \Omega)$ **without** running `prepare-synthesis-node` (`pullback-frame` / `lift-frame` / Stage A).
2. Proposals that fail a `:necessary` descriptor ($\Delta J_{\text{policy}} = +\infty$) are rejected immediately.
3. Among surviving proposals, only the top `*max-eager-proposals-per-node*` (e.g., `2` or `3`) are prepared immediately in this step; the remaining proposals are stored in `(node-deferred-proposals node)` sorted by policy priority.
4. Whenever the node is revisited on the agenda (as budget permits), it materializes (`prepare-synthesis-node`) the next batch of deferred proposals before falling back to heavier structural enumerations!

### 4.3 Arity-Safe Priority Predictor & Discriminative Descriptor Consolidation
* Fix `:heuristic` validation and `evaluate-priority-predictor-expr` to handle both 4-input (`node-trace-features`) and 6-input (`tests/library.lisp`) feature vectors safely.
* Add `consolidate-policy-descriptors` to update empirical descriptor weights $w_{e,i}$ from positive/negative synthesis traces and synthesize new discriminative `:descriptor` guards when two operators share a type signature.
