# `lisploop` --- Plan 7R: Loops, Recursion, Callable Functions, and Conserved-Quantity Inversion

> **Status**: Active implementation plan (`plan7-recursion.md`). R1, R2, R3, R4, and R5 completed and audited.
> Cross-checked against `plan7.md`, `prompt4.md`, `architecture.md`, `plan7-recursion2.md`, and the authoritative Lisp source (`package.lisp`, `ast.lisp`, `codec.lisp`, `vm.lisp`, `requirements.lisp`, `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `laws.lisp`, `synthesize.lisp`).

---

## 1. Diagnosis: Specific Omissions of Generality in the Current Kernel

The committed kernel already provides almost all of the foundational machinery required for recursive and higher-order synthesis:
- **Zero-copy homoiconic S-expressions (`ast.lisp`)**: A quoted expression inside a literal `'(+ X0 '1)` *is* the exact S-expression `(+ X0 '1)` with sort `(:code ((0 . :int)) :int)` that the evaluator, anti-unifier, and codec operate on (`deprecated/plan5.md` Sec. 3).
- **Canonical positional environments & runtime value lifting (`ast.lisp`, `vm.lisp`)**: Every expression uses canonical positional variables `X0, X1, ...` (`(var 0 t0)`, `(var 1 t1)`), and `:code-subst` specializes open `:code` templates by substituting either `:code` subtrees in the target scope or lifting runtime values directly into typed literal AST nodes `(lit tau value)` (homoiconic partial application / quasiquotation without lambda-calculus closures).
- **Extensible operator bit-coding (`codec.lisp`)**: `emit-operator-name` and `read-operator-name` already use a 4-bit opcode with Elias-delta extension for indices $\ge 15$.
- **Resumable continuation/task stack (`vm.lisp`)**: `evaluation` already executes via an explicit `tasks` stack and `stack` value list under 1-unit work budgets.
- **Four-operation synthesis engine (`requirements.lisp`, `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `laws.lisp`, `synthesize.lisp`)**: Symmetry/invariance bucketing (Op 1), syntactic/value quotienting & anti-unification (Op 2), pullback/reorientation & learned algebraic propagation (Op 3), and conditional/heuristic fiber condensation (Op 4).

Extending the system to invert looping and recursive programs (`copy`, `map`, `fold`, `sort`), learn higher-order library primitives (`map`, `fold`), and support reentrant search deductions requires correcting **four omissions of generality**:

1. **Inductive Sequence Constructors & Ordering (`ast.lisp`, `vm.lisp`, `requirements.lisp`)**:
   - `(:seq tau)` currently has `:at`, `:concat`, `:gather`, `:member`, `:lookup`, but lacks a scalar-to-sequence constructor (`:cons`), tail projection (`:tail`), sequence length (`:length`), and integer order (`:<`).
   - `fold-constants` in `requirements.lisp` splits tuple equalities `(= (tuple a b) '(v0 v1))` into coordinate equalities, but lacks the exact inductive analogue for sequences: splitting `(= (cons h t) '(v0 v1 ...))` into `(= h 'v0)` and `(= t '(v1 ...))` (and `'nil` against `'()`).
2. **Homoiconic Code Evaluation & Named Recursive Functions (`ast.lisp`, `codec.lisp`, `vm.lisp`)**:
   - The `:code-*` operator family can inspect, match, bind (`:code-bind`), and substitute (`:code-subst`) quoted S-expressions, but lacks `:code-eval` to execute a `(:code inputs sort)` expression on runtime arguments.
   - Operators are restricted to the fixed 21-element `+operator-names+` list. Named functions (with short de novo symbols `:fa`, `:fb`, ... in the language namespace, or supplied control names `:copy`, `:map`, `:fold`, `:insert`, `:sort`) cannot yet be bound in a `language` and invoked recursively or higher-order on the VM task stack.
3. **1-to-Many Call-Site Lifting & Conserved-Quantity Inversion (`requirements.lisp`, `frame.lisp`, `factor.lisp`, `synthesize.lisp`)**:
   - Current frame transforms are 1-to-1 (`pullback-frame`, `orient-observations`) or row subsets (guards/views). Pulling back through a recursive function or higher-order template (`map`, `fold`) unfolds multiple call occurrences per parent observation $(\omega, \text{path})$, requiring a **1-to-many lift** (`lift-frame`) and an `:unresolved` outcome when an oracle self-lookup misses an unobserved trace input.
   - To infer loops and index/value recurrences from outputs rather than only top-down shell guessing, the pipeline needs a stage that **observes conserved quantities** across lifted input/output/index fibers and **algebraically inverts** those conserved laws via M4 propagators into generative expressions.
4. **Top-Down Corpus Abstraction & Deductive Leaf Messages (`factor.lisp`, `synthesize.lisp`)**:
   - `anti-unify` abstracts mismatching subtrees into first-order variables, but when anti-unifying recursive programs (`map_inc` vs `map_double`, `fold_sum` vs `fold_prod`), mismatching subtrees depend on shared inner step terms (`(at X0 '0)`, `(:fa (tail X0))`). Factoring mismatches through their shared step subterms yields closed homoiconic `:code` parameters directly in canonical `(X0, X1, ...)` form (Stitch-style top-down abstraction).
   - Search leaf messages (`prompt4.md` Sec. 8.b) should act as **first-class S-expression deduction rules / learned clauses** (analogous to CDCL / UIP / DIP in SAT) rather than imperative host callbacks.

---

## 2. Detailed Plan

### Phase 1: Minimal Inductive Sequence & Ordering Primitives + Pullback Folding
**Files**: `ast.lisp`, `vm.lisp`, `requirements.lisp`, `package.lisp`

#### 1.1. Sequence & Ordering Primitives
- `:cons`: `(tau, (:seq tau)) -> (:seq tau)` --- prepends a scalar element to a sequence.
- `:tail`: `((:seq tau)) -> (:seq tau)` --- returns `(cdr seq)` when non-empty, and `:bottom` (evaluation error) on `'()`. *(Note: `head` is already `(at seq '0)` and `empty?` is already `(= seq '())`.)*
- `:length`: `((:seq tau)) -> :int` --- returns `(length seq)`.
- `:<`: `(:int, :int) -> :bool` --- strict integer ordering (restricted to `:int`, not `(:gf p)`).

#### 1.2. Sequence Equality Splitting & Guarded Call Unfolding in `fold-constants`
- **Sequence-equality splitting**: Mirroring `:tuple` splitting (`requirements.lisp:160-169`), extend `fold-constants` so:
  - `(= (cons H T) '(v0 v1 ...))` $\longrightarrow$ `(and (= H 'v0) (= T '(v1 ...)))`
  - `(= (cons H T) '())` $\longrightarrow$ `'nil`
- **Guarded call unfolding (`plan7-recursion2.md` K3)**:
  - When `fold-constants` encounters a call to a defined function or `(:code-eval 'body arg0 ...)` where arguments are literals or `provably-total-p`, unfold the body one step at a time while its control guards (`:if`) fold to literals, bounded by `fold-constants`'s existing single-traversal budget. Leave any unreduced call intact on budget cutoff.
  - With these two rules in `fold-constants`, pulling back a parent requirement through *any* recursive or library decoder automatically unrolls concrete recursion steps and splits output sequences into per-element/per-step requirements.

---

### Phase 2: Homoiconic Function Structure, De Novo Naming (M9), and Zero-Copy VM Stack Execution
**Files**: `ast.lisp`, `codec.lisp`, `vm.lisp`, `enumerate.lisp`

#### 2.1. Homoiconic Lisp Function Structure & Short De Novo Symbols
Rather than introducing a procedural/C-like declaration hierarchy or ML closure structs, defined functions mirror the homoiconic S-expression design of `lisploop`:

- **Definitions are named `:code` S-expressions**:
  - A defined function in a `language` (or local `letrec` binding) associates a symbol name with a homoiconic `expression` whose free variables `((0 . t0) ... (k-1 . tk-1))` are its positional parameters `X0, ..., X_{k-1}` and whose `expression-type` is its return type `ret`:
    $$\text{signature}(\texttt{:fa}) = \texttt{(:fn (}t_0 \dots t_{k-1}\texttt{) } \text{ret}\texttt{)}, \qquad \text{body}(\texttt{:fa}) \in \texttt{(:code ((0 . }t_0\texttt{) }\dots\texttt{) ret)}.$$
  - Self-recursion and mutual recursion are written directly as ordinary Lisp operator calls `(:fa (tail X0))` using the function's own symbol `:fa` (and canonicalized to a common self-symbol `:recur` only when comparing two distinct recursive functions during anti-unification).
- **Short De Novo Symbol Names (M9)**:
  - Newly synthesized or abstracted functions are assigned short de novo keyword symbols in the language namespace---e.g. `:fa`, `:fb`, `:fc`, ... (avoiding raw integers, which would collide visually and conceptually with positional variable indices and literals).
  - In Milestone 9, these de novo names serve as the vocabulary tokens whose usage probabilities and context affinities are coupled to the search policy and language tariffs.
- **Higher-Order Arguments via Existing `:code` + `:code-subst` + New `:code-eval`**:
  - Because `(:code inputs sort)` is already a first-class value type in `ast.lisp`, higher-order functions like `:map` and `:fold` simply take a `:code` parameter (e.g. `X1 : (:code ((0 . :int)) :int)`).
  - Calling that code parameter uses a single new symbolic/bridge primitive:
    - `:code-eval`: `((:code ((0 . t0) ... (m-1 . tm-1)) ret), t0, ..., tm-1) -> ret`
  - **Capturing outer variables without non-Lisp closure types** (see [Appendix A.2](#sec-appendix-capture) for a worked walkthrough): When a code argument to `:map` or `:fold` needs to capture an outer runtime variable (such as `k` in `map (+ X0 k) xs`), `:code-subst` accepts tuple bindings that are either `:code` expressions in the target scope (`'X0`) or runtime values of the corresponding input type (`k : :int`), lifting runtime values into typed literals `(lit tau k)` inside `'(+ X0 X1)` to produce the specialized `:code` value `'(+ X0 'k)`. `provably-total-code-arg-p` and `try-unfold-call` look through `(:code-eval (:code-subst 'template (tuple ...)) ...)` so requirement pullbacks unfold and propagate directly into captured runtime variables.
- **Compact Call-Site Encoding & $O(1)$ Call-Step Tariff (`ast.lisp`, `codec.lisp`, `vm.lisp`)**:
  - Because registered functions (`:fa`, `:fb`, ...) have fixed monomorphic signatures in `*function-definitions*`, call sites do not re-emit the `:code` type signature into the bitstream (`operator-bit-size`, `emit-operator`, `decode-model`); a call emits only the 2-bit `:app` tag and the operator opcode.
  - Invoking a defined function or `:code-eval` rebinds `evaluation-environment` to already-evaluated arguments on the VM stack and charges `1` unit for the call step in `primitive-cost` (plus `1` unit for `:restore-env`), while the body pays for all operations it executes—avoiding $O(N^2)$ sequence re-traversal tariffs on $O(N)$ structural recursions.
- **Structural Totality (`provably-total-p`), Transitive Fixed-Point (`recompute-registered-functions-totality`), & Cache Invalidation (`invalidate-app-meta`)** (see [Appendix A.1](#sec-appendix-totality)):
  - A recursive definition `:fa` is certified structurally total (`analyze-function-body-totality`, unified with `provably-total-p` and `expr-total-under-non-empty-p`) if every self-call to `:fa` occurs on the false branch of `(= Xi '())` and passes `(tail Xi)` at parameter position $i$ (or conditionally total on `conditional-code-params` when `:code-eval` is applied to a `:code` parameter).
  - Whenever a function definition is registered or redefined (`define-function`), `recompute-registered-functions-totality` runs a fixed-point pass across all `*registered-function-names*` and `invalidate-app-meta` evicts cached `:app` entries in `*node-meta*` so existing caller ASTs and transitive callees (e.g., `:fb` calling `:fa`) recompute totality consistently.
  - During active verification quanta inside `resume-synthesis`, `set-function-active-implementation` swaps `self-name` between `oracle-table` and candidate `body` without global cache eviction, and `resume-synthesis` finalizes the winning body via `define-function` (or restores `oracle-table` when no candidate is verified).
- **Constrained-Row `:unresolved` Filtering in Exact and Heuristic Search (`frame.lisp`, `enumerate.lisp`, `synthesize.lisp`)**:
  - Both `search-step` and `heuristic-search-step` skip `:unresolved` rows without charging false residual penalties and require `(>= resolved-rows (frame-min-resolved-rows frame))` — counting only **constrained** rows (`(not (unconstrained-requirement-p req))`) toward `resolved-rows` so dead `'t` base-case rows in pulled-back conditional branches cannot inflate `resolved-rows`.

#### 2.2. Zero-Copy Homoiconic Execution on the Resumable VM Stack
In `deprecated/plan5.md` (Sec. 3), **zero-copy homoiconicity** coupled with **canonical positional variables (`X0, X1, ...`)** means that a quoted expression `'(+ X0 '1)` or function body is already an immutable AST node over variable IDs `0, 1, ...`.

- Executing a call `(:fa a_0 ... a_{k-1})` or `(:code-eval code-val a_0 ... a_{k-1})` in `execute-instruction` (`vm.lisp`) requires **zero AST copying, zero alpha-renaming, and zero host-stack recursion**:
  1. Pop evaluated arguments $(v_0, \dots, v_{k-1})$ from `evaluation-stack`.
  2. Push `(:restore-env current-environment)` onto `evaluation-tasks`.
  3. Set `evaluation-environment` to the positional binding alist `((0 . v_0) ... (k-1 . v_{k-1}))`.
  4. Push `(:eval body-ast)` onto `evaluation-tasks`.
- **Properties**:
  - Stepping 1 unit at a time is bit-for-bit identical to batched execution (`step-evaluation` / `run-evaluation`).
  - Every recursive call and `:code-eval` charges the standard VM step budget; non-terminating recursion terminates cleanly with `:cutoff`.
  - When evaluating against a partial/oracle table (`Sec. 3.2`), hitting an unobserved table key returns `:unresolved` (joining `:value`, `:error`, and `:cutoff` in `vm.lisp`), so missing trace rows are treated as unrefuted rather than false.

#### 2.3. Known Soundness & Expressiveness Boundaries of Static Totality (Deferred Refinements)
Static totality (`provably-total-p` and `analyze-function-body-totality` in `ast.lisp`) **only gates algebraic erasure, substitution, and constructor splitting** in `fold-constants` (`unfoldable-seq-part-p`) and `laws.lisp`; it does **not** restrict what functions can be defined (`define-function`), enumerated, or executed in the VM (where the step budget handles arbitrary general recursion). While the current structural check suffices for Milestones R1--R6 (`copy`, `map`, `foldr`, `foldl`, `length`, `sum`, `product`, `insert`, `sort`), the following boundaries are noted for future refinement if encountered empirically:

1. **Multi-step structural descent (`(tail (tail Xi))`)**: Self-calls currently require a literal `(tail Xi)` argument rather than nested `tail` chains under corresponding non-empty guards (e.g., `pairwise`, `evens`/`odds`, or merge-sort splitting).
2. **Simultaneous / multi-sequence recursion (`merge`, `zip`)**: `decreasing-param-id` enforces a single fixed decreasing parameter index across all self-calls, which rejects functions like `merge(xs, ys)` that decrease `xs` in one branch (`(:merge (tail xs) ys)`) and `ys` in another (`(:merge xs (tail ys))`) while keeping total length $|xs| + |ys|$ strictly decreasing.
3. **Alternative emptiness guards & bounded integer recursion**: `empty-sequence-guard-var-id` only recognizes `(= Xi '())` / `(= '() Xi)` (not `(< '0 (length Xi))` or `(= (length Xi) '0)`), and `analyze-function-body-totality` does not yet track bounded `:int` measure decreases (such as `range` or `countdown` guarded by `(< X0 '1)`).

---

### Phase 3: Symmetry/Conservation Inference from Outputs & Direct Context Lifting
**Files**: `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `laws.lisp`, `synthesize.lisp`

To support both **bottom-up discovery of conserved quantities from outputs** and **top-down/inductive lifting of recursive calls**, synthesis uses two dual lifting paths:

![Phase 3: the two dual lifting paths (source: `figures/phase3-lifts.dot`).](figures/phase3-lifts.pdf){width=100%}

#### 3.1. Inferring Conserved Quantities from Outputs $\to$ Algebraic Inversion to Generative Model
When given input-output sequences $(x_\omega, y_\omega)$, we do not want to rely solely on guessing combinator shells; we want the system to **infer symmetry or conservation from the outputs and invert that conservation law into the generative model**:

1. **Stage 1 --- Fiber Inference over Output Elements / Index Addressing**:
   - Lift the output sequence $y_\omega$ into per-element observations $(\omega, j)$ with output index $j \in \{0, \dots, |y_\omega|-1\}$, length $n = (\text{length } x_\omega)$, and element target $y_{\omega, j} = (\text{at } y_\omega\ j)$.
   - When testing an array-indexing hypothesis $y_{\omega, j} = (\text{at } x_\omega\ I)$, `pullback-frame` + `fold-constants`'s existing 1D `:at` fiber inversion (`requirements.lisp:140-158`) automatically reduces `(= (at 'x_w I) 'y_wj)` to the exact fiber of matching source indices $I \in \{i \mid x_{\omega, i} = y_{\omega, j}\}$!
2. **Stage 2 --- Observing Conserved Quantities (`collect-observation-buckets` / `orient-observations`)**:
   - On the joint lifted frame containing $(x_\omega, j, n, I, y_{\omega, j})$ (or on a recursive transition frame containing head $H = (\text{at } x_\omega\ 0)$, tail result $Z = y(\text{tail}(x_\omega))$, and output $Y = y_\omega$), run Operation 1 (`collect-observation-buckets`) to find expressions $C(\dots)$ that are **conserved** across all rows (`constant-p` with value $c_0$, or invariant across `pairs`):
     - *Index conservation (`copy`)*: $C(I, j) = I - j = 0$ is conserved across all $(\omega, j)$.
     - *Index conservation (`reverse`)*: $C(I, j, n) = (I + j) - (n - 1) = 0$ is conserved across all $(\omega, j)$.
     - *Value conservation (`map_inc`)*: $C(x_{\omega, j}, y_{\omega, j}) = y_{\omega, j} - x_{\omega, j} = 1$ is conserved across all $(\omega, j)$.
     - *Step conservation (`fold_sum` / `length`)*: $C(H, Z, Y) = (Y - Z) - H = 0$ (for `sum`) or $Y - Z = 1$ (for `length`) is conserved across all non-empty step transitions.
     - *Permutation / Multiset & Monotonicity conservation (`sort`)*: `(length Y) - (length X) = 0`, `(member Y_j X) = t`, and adjacent-pair order `(< Y_{j+1} Y_j) = nil` are conserved across all outputs.
3. **Stage 3 --- Algebraic Inversion of the Conserved Quantity into the Generative Model**:
   - A conserved quantity $C(\mathbf{u}, T) = c_0$ (where $T$ is the unknown target $I$ or $Y$) is reoriented via `orient-observations` into the requirement `(= C(u, T) 'c_0)`.
   - Applying Operation 3 (`pullback-frame` + M4's learned witness solvers `propagate-requirements` in `laws.lisp`) algebraically inverts `(= C(u, T) 'c_0)` for $T$:
     - $(I + j) - (n - 1) = 0 \xrightarrow{\text{invert for } I} I = (n - 1) - j \implies y_{\omega, j} = \texttt{(at X (- (- (length X) '1) J))}$.
     - $Y_j - X_j = 1 \xrightarrow{\text{invert for } Y_j} Y_j = X_j + 1$.
     - $(Y - Z) - H = 0 \xrightarrow{\text{invert for } Y} Y = H + Z$.

#### 3.2. 1-to-Many `lift-frame`, Congruence Closure, and Oracle Self-Lift (`plan7-recursion2.md` K4, K5)
Complementing bottom-up conservation discovery, pulling back a parent frame $\Omega$ through a recursive definition or higher-order template $d(\mathbf{x}_\omega, F)$ uses a general **1-to-many frame lift** (`lift-frame`):

1. **Unfold & Split**: `pullback-frame` substitutes $d(\mathbf{x}_\omega, F)$ into $A_\omega(Y)$ and runs `fold-constants` (Phase 1.2). On concrete inputs $\mathbf{x}_\omega$, this unrolls the loop/recursion and splits sequence equalities into per-application constraints over terms $F(\mathbf{a})$.
2. **Congruence Closure Across Rows**: Collect all $F(\mathbf{a})$ occurrences via `collect-tree-occurrences`. Because $F$ is pure, a ground equation $F(0, 3) = 3$ from one row substitutes into nested terms $F(F(0, 3), 5) = 8$ in longer rows (union-find congruence closure over hash-consed ground application terms), resolving intermediate accumulators on prefix-closed fold data without any combinator-specific deduction rules.
3. **1-to-Many Child Frame Construction & Symmetry Refutation**:
   - Each distinct ground application $F(\mathbf{a})$ constrained by a conjunct becomes a child observation keyed by `(parent-key . path)` with known inputs $\mathbf{a}$.
   - Identical argument tuples $\mathbf{a}$ across occurrences are intersected by `tighten-same-input-requirements`.
   - **Symmetry test**: If two occurrences have identical lifted context $\mathbf{a}$ but incompatible requirements, `frame-conflict-p` immediately refutes the lift (e.g. refuting element-only `map` on `reverse`, which then lifts the index $j$ and outer sequence $x$ via `dependency-proposals`).
   - **Linkage**: For 1-to-many lifts, position along the unrolled call path provides a natural integer coordinate for `compute-tree-locality-positions`, and adjacent call sites generate shift/step `pairs`.
4. **Oracle Self-Lift for De Novo Recursive Definitions** (see [Appendix A.3](#sec-appendix-oracle-self-lift)):
   - To synthesize a new recursive function `:fa` directly on $\Omega$, the conditional shell splits out the base case (e.g. `(= X0 '())`), and on the non-empty branch evaluates self-calls `(:fa (tail X0))` against a partial oracle backed by $\Omega$'s own rows (`frame-oracle-table`, returning `:unresolved` on missing keys), followed by authoritative verification of the concrete recursive `:fa` body on the root frame in the VM (`activate-job-candidate-body`).
   - On `sort(X0)`, lifting $H = \texttt{(at X0 '0)}$ and $Z = \texttt{(:sort (tail X0))}$ on the non-empty branch produces the concrete child frame $\Omega_{\text{insert}}(H, Z) \to Y$. Splitting $\Omega_{\text{insert}}$ on `(= Z '())` and `(< H (at Z '0))` and pulling back `(cons (at Z '0) ?rest)` synthesizes `:insert` and `:sort`.
   - **R4 Implementation Notes (`ast.lisp`, `vm.lisp`, `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `synthesize.lisp`)**:
     - *Lazy `:unresolved` evaluation (`vm.lisp`, `ast.lisp`, `frame.lisp`)*: `advance-evaluation` allows `:unresolved` in `evaluation-values` at `:validate-inputs` time and signals `unresolved-evaluation` lazily in `:eval` only when a `:var` bound to `:unresolved` is actually evaluated. `evaluate-row-bindings` and `pullback-frame` preserve `:unresolved` on constrained child rows, substitute canonical type defaults on dead-branch (`'t`) rows (before `:unresolved`), and relax child row requirements to `(lit :bool t)` whenever a parent decoder depends on an `:unresolved` parent input. `tighten-same-input-requirements` skips rows containing `:unresolved`, and `lift-frame` emits `:coupled` `:unresolved` rows when fewer than 2 ground rows decouple on a coupled fold.
     - *Contextual & transitive totality (`ast.lisp`)*: `empty-sequence-guard-var-id` and `expr-total-under-non-empty-p` are wired into `compute-app-meta` and `analyze-function-body-totality` so recursive expressions guarded by `(= Xi '())` are certified `provably-total-p` once the underlying function definition is certified total, and `recompute-registered-functions-totality` propagates totality updates transitively across dependent functions.
     - *Oracle vs. concrete body switching & per-row cutoff (`enumerate.lisp`, `synthesize.lisp`)*: `activate-job-oracle` and `activate-job-candidate-body` use `set-function-active-implementation` during verification quanta to avoid global `*node-meta*` cache thrashing, with a per-row VM step budget (`row-budget` in `search-job`) deterministically rejecting circular or non-terminating candidates, and `resume-synthesis` finalizes the winning candidate via `define-function` or restores `oracle-table` on exit.
     - *Unified Stage A/B base-case & non-empty projection lifting (`factor.lisp`, `synthesize.lisp`)*: Rather than a separate recursive-split pass, `start-recursive-synthesis` simply defines `self-name` with `:oracle-table` and delegates to `start-heuristic-synthesis`. Stage A (`condense-heuristic`, retaining runner-up `heuristic-alternatives` and charging MDL witness bits on `:unresolved` rows) and Stage B (`heuristic-decompositions` / `find-sound-exception-guard`) discover both the base-case expression and the `(= Xi '())` guard directly; when `Path B2` in `heuristic-decompositions` discovers `(= Xi '())`, `lift-inductive-sequence-context` lifts the non-empty projections `(at Xi '0)` and `(:self ... (tail Xi) ...)` into the `else` child's `bindings`, and on multi-branch functions like `insert` the same `heuristic-expander` splits the child frame again on `(< (at X1 '0) X0)`.
     - *Explicit Debug Mode (`*synthesis-debug-mode*`, `explain-synthesis-node`, `explain-synthesis-job`)*: Passing `:debug-p t` (or binding `*synthesis-debug-mode*` to `t`) records structured causal provenance (`decomposition-provenance`, `synthesis-node-provenance`) on decompositions, nodes, and messages without affecting the non-debug fast path. `explain-synthesis-node` and `explain-synthesis-job` inspect and format the ancestor decoder chain, reconstructed partial AST with hole `?0`, lifted bindings, row status (`:constrained`, `:dead-unconstrained`, `:unresolved`), Stage A model, and `nogood-clause`s.

---

### Phase 4: Top-Down Homoiconic Library Learning (`map`, `fold` via Stitch-Style AU)
**Files**: `factor.lisp`, `ast.lisp`, `laws.lisp`, `package.lisp`

#### 4.1. Compatibility with Zero-Copy Positional Binding & Stitch-Style Top-Down Abstraction
In DreamCoder, abstracting lambda-calculus terms required expensive bottom-up version spaces because de Bruijn indices shifted under every lambda binder. In `lisploop`, **Phase 2.2's positional binding (`0, 1, ...`) makes higher-order anti-unification zero-copy and native**:
1. **Self-Reference Normalization (`rename-function-calls` in `ast.lisp`, `infer-self-operator-name` & `replace-operator-calls` in `factor.lisp`)**: When comparing recursive definitions `:fa`, `:fb`, ... of matching signature, `infer-self-operator-name` and `replace-operator-calls` normalize self-calls onto a shared temporary self-operator `:__au_self__` (and rewrite self-calls in the extracted combinator body to the new library combinator `(op target-name ...)`, appending any newly abstracted value or `:code` parameters).
2. **Common-Subterm Factoring into Positional `:code` Arguments (`shared-subterm-cover`, `abstract-over-subterms` in `factor.lisp`)**:
   - When `anti-unify-for-library` encounters a mismatch $(T_1, \dots, T_k)$ whose fillers reference bound parameters or self-calls (e.g. `copy`'s `(at X0 '0)`, `inc-all`'s `(+ (at X0 '0) '1)`, and `double-all`'s `(+ (at X0 '0) (at X0 '0))`, or `sum`'s `(+ (at X0 '0) (:fa (tail X0)))`, `length`'s `(+ (:fa (tail X0)) '1)`, and `product`'s `(* (at X0 '0) (:fa (tail X0)))`):
   - `shared-subterm-cover` extracts the maximal shared subterms $A_0, \dots, A_{m-1}$ covering all outer variable / self-call references.
   - `abstract-over-subterms` replaces each $A_j$ in every $T_i$ with canonical positional variable `(var j tau_j)` (`X0`, `X1`, ...) and packages the closed body as a typed `:code` literal.
   - Because `X0, X1, ...` are *already* the exact positional environment expected by `:code-eval` in Phase 2.2, each abstracted filler becomes a closed `:code` literal (`'X0`, `'(+ X0 '1)`, `'(+ X0 X0)` for `:map`; `'(+ X0 X1)`, `'(+ X1 '1)`, `'(* X0 X1)` for `:foldr`) with **zero variable shifting**, and the shared combinator template replaces the hole with `(:code-eval X_f A_0 ... A_{m-1})`!
3. **Stitch / e-Stitch Efficiency Roadmap**:
   - `discover-library-abstractions` (and `abstract-function-bodies`) operates top-down over the solved recursive corpus using `anti-unify-for-library`, accepting a new library definition (`:fa`, `:fb`, ... for `map`, `foldr`, `foldl`) only when it strictly reduces total description length $S(L) + \sum_i S(p_i \mid L) < \sum_i S(p_i)$.
   - Because `laws.lisp` already maintains certified equivalence rewrite rules, normalizing corpus expressions via `:rewrite-library` (`normalize-trees-with-library`) and guarded-equality normalization (`normalize-guarded-equalities`, rewriting `Xi -> 'c` inside the `then` branch of `(if (= Xi 'c) then else)`) plugs directly into top-down anti-unification without changing the representation.
4. **R5 Implementation Notes (`ast.lisp`, `factor.lisp`, `laws.lisp`, `package.lisp`, `tests/recursion.lisp`)** (see [Appendix A.4](#sec-appendix-r5-library) for worked AST and bit-accounting trace):
   - *Guarded-equality base-case canonicalization (`extract-var-literal-equality`, `normalize-guarded-equalities` in `factor.lisp`)*: De novo R4 synthesis produces `(if (= X0 '()) X0 ...)` for `inc-all` and `double-all` (`X0` is 6 bits vs `'()` at 9 bits) and `(if (= X0 '()) '() ...)` for `copy`. `normalize-guarded-equalities` substitutes `Xi -> 'c` inside the `then` branch of `(if (= Xi 'c) then else)` prior to anti-unification so all three map functions share the identical `'()` base case without opening a redundant base-case hole.
   - *Control-spine anti-unification (`anti-unify-for-library` in `factor.lisp`)*: Recurses into applications only along the shared recursive control spine (`:if` with non-hole guards, and constructors/tuples whose arguments contain recursive self-calls while at least one argument does not immediately mismatch into a bare hole). When an application directly wraps a recursive call alongside a diverging operand (as in `sum`'s `(+ (at X0 '0) (:self (tail X0)))` vs `length`'s `(+ (:self (tail X0)) '1)` vs `product`'s `(* (at X0 '0) (:self (tail X0)))`), `anti-unify-for-library` opens a single expression hole `?1` for the entire step expression rather than recursing into `:+` or introducing first-order operator holes.
   - *Order-independent subterm covers (`shared-subterm-cover` in `factor.lisp`)*: Canonicalizes extracted cover order via `stable-sort` so non-recursive parameter subterms (e.g. `(at X0 '0)`) precede recursive self-call subterms (e.g. `(:self (tail X0))`). This guarantees that `:foldr` step `:code` literals always bind `(X0 = (at X0 '0), X1 = (:self (tail X0)))` even when a function like `length` omits `(at X0 '0)` and appears first in the subset.
   - *First-order vs. higher-order hole classification (`abstract-function-bodies` in `factor.lisp`)*: For each hole in the LGG pattern:
     - If no filler references outer parameters or `:__au_self__` (e.g. base-case identity `'0`, `'0`, `'1` in `:foldr`), the hole becomes a **first-order value parameter** `(var param-id hole-sort)` (`X1 : :int`) and each refactored caller passes its concrete expression (`'0`, `'0`, `'1`).
     - If any filler references outer parameters or `:__au_self__`, `shared-subterm-cover` + `abstract-over-subterms` extracts the shared cover $A_0, \dots, A_{m-1}$, adds a **`:code` parameter** `(var param-id (:code ((0 . t0) ...) hole-sort))`, replaces the hole in the combinator body with `(:code-eval (var param-id ...) A_0 ... A_{m-1})`, and wraps each abstracted filler as a `:code` literal `(lit code-param-type ab-body)` at the refactored call site.
   - *Totality verification & exact MDL bit accounting (`finalize-library-abstraction` in `factor.lisp`)*: Requires every candidate combinator to contain at least one `:code` parameter and pass `analyze-function-body-totality` (`total-p` or non-empty `conditional-code-params`). Prices exact bit lengths via `description-size`:
     - `original-bits` $= \sum_i S(\text{body}_i, \text{inputs})$
     - `library-bits` $= S(\text{lib-body}, \text{lib-inputs})$
     - `refactored-call-bits` $= \sum_i S(\text{call}_i, \text{inputs})$
     - `gain` $= \text{original-bits} - (\text{library-bits} + \text{refactored-call-bits})$
     Also ensures candidate evaluation uses temporary function names (`call-with-temporary-function-names` with `:__lib_cand__`) and replaces operator calls (`replace-operator-calls`) before recomputing `ast-meta` so existing definitions in `*function-definitions*` are never clobbered during subset search.
   - *Signature-grouped subset search & rewrite integration (`discover-library-abstractions` in `factor.lisp`, `rewrite-scope-type-p` in `laws.lisp`)*: Normalizes corpus entries (`normalize-corpus-definition-entry`), optionally normalizes bodies once upfront with `:rewrite-library` (with `rewrite-scope-type-p` in `laws.lisp` permitting `:seq` inputs over the library's domain), explores both the full signature group and pair-seeded greedy subsets (isolating non-recursive or incompatible outliers), assigns fresh de novo names (`:fa`, `:fb`, ...), registers accepted combinators (`:gain > min-gain`), and returns `(values accepted-abstractions refactored-definitions all-candidates ledger)`.
   - *AST metadata preservation across function resets (`clear-function-definitions`, `rename-function-calls` in `ast.lisp`)*: `clear-function-definitions` clears `*typed-symbol-pool*` without deleting uninterned operator symbols from `*node-meta*`, and `rename-function-calls` falls back to `(operator-operand-type head)` when `to-name` is not currently bound in `*function-definitions*`, ensuring ASTs synthesized in earlier runs remain valid across function table resets.

---

### Phase 5: Deductive Leaf Messages & Policy-Decoupled Search (M8)
**Files**: `synthesize.lisp`, `requirements.lisp`, `laws.lisp`

#### 5.1. Composable Expander Proposals Without Baked-In Policy
- A `library-expander` proposes registered library definitions whose return type matches the current target as ordinary `decomposition`s; function-typed (`:code`) parameters become lifted child frames via `lift-frame` (Phase 3.2).
- Proposals are not ranked by hardcoded host rules (such as "equal lengths $\implies$ map"); they compete solely under the existing full-path Stage A description-length + work objective and the 3:1 interleaved reserve schedule.

#### 5.2. Leaf Messages as S-Expression Deduction Rules (CDCL / UIP / DIP Analogue)
Rather than adding an imperative host-code callback `:message-handler`, messages from search leaves (`prompt4.md` Sec. 8.b) are represented as **S-expression constraints and guarded deduction rules** processed by the existing requirement/law machinery:
- **Conflict Clauses (`nogood-clause` / `build-nogood-clause` in `synthesize.lisp`)**:
  - When a pulled-back or lifted frame conflicts on rows $(\omega_1, \omega_2)$ under context bindings $\pi(\mathbf{x})$, `build-nogood-clause` constructs a `nogood-clause` carrying the homoiconic S-expression fiber predicate `clause-expr` ($\bigwedge_j (= B_j\; 'v_j)$) recording the incompatible conjuncts.
  - Within the current problem, this clause prunes any sibling or descendant node whose assumptions entail the conflict (`check-parent-nogoods`).
- **Anti-Unification of Conflict Messages (UIP / DIP Generalization)**:
  - Across multiple leaf conflicts in a search tree, anti-unifying the conflict S-expressions via `anti-unify` extracts shared structural refutations (Unique Implication Points / partial conservation laws that must hold for any valid solution), and common subterms in dual implication points (DIP) introduce new intermediate variables (`dependency-proposals`).
- **Lossy Branch Condensations (Heuristics)**:
  - Quantitative leaf outcomes (work spent, residual bits) are recorded as ordinary rows in a search-trace frame, so `condense-heuristic` (`start-heuristic-search`) can induce an approximate priority predictor $\hat{\pi}$ (discarding $\varepsilon$ at deployment) using the exact same synthesis engine.

---

## 3. Milestones & Verification Matrix

Each milestone will be validated by a dedicated test suite in `tests/` (`tests/recursion.lisp`, wired into `tests/run.lisp`), comparing supplied controls against discovered artifacts:

| Milestone | Scope | Verification & Controls |
| :--- | :--- | :--- |
| **R1** | Phase 1.1 & Phase 2: `:cons`, `:tail`, `:length`, `:<`, `:code-eval`, named functions (`:fa`, `:fb`, ...) in `language`, zero-copy VM call stack, `:unresolved`, codec/tariff versions | 1-unit vs batch VM resume parity across deep recursion and `:code-eval`; infinite recursion `:cutoff` vs `:error`; codec roundtrip; `:code-bind` + `:code-eval` closure capture test |
| **R2** | Phase 1.2: Sequence-equality splitting `(= (cons h t) '(...))` and guarded call unfolding in `fold-constants` | Definedness preservation under lazy `:if`; budget cutoff leaves unreduced calls intact; generic pullback through supplied recursive decoders |
| **R3** | Phase 3.1 & 3.2: Conserved-quantity observation + M4 algebraic inversion; 1-to-many `lift-frame` + congruence closure | Bottom-up index/value conservation $\to$ generative inversion on `copy`, `reverse`, `map_inc`; 1-to-many lift on `map` (E1), symmetry conflict refutation on `reverse` (E1c), prefix-closed `fold` including `sumsq`, `horner10`, and `(+ acc (* acc x))` (E3) |
| **R4** | Phase 3.2 (Oracle Self-Lift): De novo recursive synthesis with `:unresolved` oracle + conditional base-case split | End-to-end synthesis of `copy`, `inc-all`, `double-all`, `sum`, `length`, `product`, and `insert` from I/O examples; negative control verifying root VM execution rejects oracle-only fits |
| **R5** | Phase 4: Homoiconic higher-order AU + positional `:code` argument extraction + DL library acceptance | Automatic discovery and registration of `:map` (`:fa`) and `:fold` (`:fb`) from the R4 solved corpus; refactoring savings verification |
| **R6** | Phase 5: Library expander + curriculum synthesis of `sort` (`insert` + `fold`/`sort`) + S-expression leaf nogood clauses | End-to-end synthesis of `sort` and held-out `map`/`fold` tasks using learned library primitives; search-work comparison with and without deductive leaf clauses |

---

## Appendix A: Provable Totality and Homoiconic Variable Capture

### A.1. What "Provably Total" Means (`provably-total-p` & `provably-total-code-arg-p`) {#sec-appendix-totality}

In `lisploop`, evaluating an expression in the VM (`vm.lisp`) can finish in four ways:
1. `:value` --- produces a valid value of the target type.
2. `:error` --- hits a partial-primitive failure (division by zero in `:/`, out-of-bounds index in `:at`/`:gather`, `:tail` on `'()`, missing `:lookup` key, etc.).
3. `:unresolved` --- queries a partial `:oracle-table` on an input not present in the table.
4. `:unknown` (`:cutoff`) --- exhausts the step budget (e.g., non-terminating recursion).

An expression is **total** if it is guaranteed to terminate with `:value` on *every* well-typed input assignment. Because exact totality is undecidable, `provably-total-p` (`ast.lisp`) is a **conservative static syntactic check** cached in the `total-p` slot of `ast-meta`:
- If `(provably-total-p expr)` is `t`, `expr` is guaranteed never to error or loop infinitely.
- If it is `nil`, `expr` *might* error or fail to terminate.

#### Why the synthesizer needs it: Definedness Preservation
Whenever `fold-constants` (`requirements.lisp`) simplifies a pulled-back requirement or `laws.lisp` rewrites an AST, it must preserve not just values, but also **error behavior (definedness)**. If a subexpression could error (such as `(/ '1 X0)` when `X0 = 0`), erasing or reordering it could turn an erroring program into a succeeding one. Specifically, `fold-constants` checks `provably-total-p` before:
- **Dropping subterms**: e.g., `(if cond A A) -> A` requires `(provably-total-p cond)`; `(at (tuple A B) '0) -> A` requires `(provably-total-p B)` because `:tuple` evaluates all its arguments; and `non-total-args-preserved-p` refuses to inline a call like `(:first-or-default '() (/ '1 X0))` if the taken branch `'0` drops the non-total argument `(/ '1 X0)`.
- **Substituting equalities & reordering conjunctions**: `extract-term-equality` only substitutes `(= term 'val)` when `(provably-total-p term)`, and `(if cond yes 'nil)` only intersects/reorders conjuncts when both `cond` and `yes` are `provably-total-p`.

#### How `provably-total-p` is computed (`compute-app-meta` in `ast.lisp`)
- **Always-total primitives**: `:var`, `:lit`, and total operators (`:+`, `:*`, `:-`, `:<`, `:=`, `:tuple`, `:cons`, `:length`, `:concat`, `:member`, `:code-kind`, `:code-total`, `:code-less`, `:code-apply`, `:code-match`, `:code-subst`) are total whenever all their arguments are total.
- **Conditionally-total primitives**:
  - `(/ a b)`: total iff `a` is total and `b` is a non-zero literal.
  - `(at seq i)`: total iff `seq` is total and `i` is a non-negative integer literal statically known to be in bounds (e.g., `< tuple-length`, `< literal-length`, or `'0` on `(:cons h t)`).
  - `(tail seq)`: total iff `seq` is a non-empty literal or a total `(:cons h t)`.
- **Recursive functions (`analyze-function-body-totality` in `ast.lisp`)**:
  - When `define-function` registers `:fa`, it walks the body tracking which sequence parameters `Xi` are guarded by the false branch of `(= Xi '())` (`non-empty-vars`). On that branch, `(at Xi '0)` and `(tail Xi)` are statically safe, and every recursive call `(:fa ...)` must pass `(tail Xi)` for a consistent decreasing parameter `Xi`.
- **Higher-order functions & `provably-total-code-arg-p` (`ast.lisp`)**:
  - A higher-order function like `:map` or `:fold` calls `(:code-eval f ...)` on a `:code` parameter `f`. Even if `:map`'s recursion over `xs` terminates, `(:map xs f)` is only total if the code passed for `f` is *also* total.
  - `analyze-function-body-totality` records which parameter indices of `:map` are passed to `:code-eval` in `function-definition-conditional-code-params` (e.g., `'(1)` for `:map`).
  - At a call site `(:map xs code-arg)` or `(:code-eval code-arg x)`, `provably-total-code-arg-p` checks whether `code-arg` is guaranteed to evaluate to a total AST:
    1. `code-arg` is a quoted `:code` literal `'(+ X0 '1)` whose inner AST satisfies `provably-total-p`, **or**
    2. `code-arg` is a `:code-subst` expression `(:code-subst 'template (tuple b0 ...))` where `'template` is a total literal AST and every binding `bi` is itself total.

---

### A.2. Capturing Outer Variables Without Non-Lisp Closure Types {#sec-appendix-capture}

#### The Problem: Positional Scope vs. Lexical Capture
In `lisploop`, all variables use canonical positional names `X0, X1, ...` (`(var 0 tau0)`, `(var 1 tau1)`), and a quoted code value has an explicit variable scope in its type: `(:code ((0 . :int)) :int)`.

Suppose we are inside an outer scope with two inputs---a sequence `X0 : (:seq :int)` and an integer `X1 : :int` (say `k = 5`)---and we want to use `:map` to compute "add `X1` to every element of `X0`":
- `:map` expects a second argument of type `(:code ((0 . :int)) :int)`---an S-expression whose **only** free variable is `X0` (which `:map` binds to the current list element when it runs `(:code-eval f elem)`).
- When `execute-instruction` (`vm.lisp`) runs `:code-eval`, it replaces `evaluation-environment` with `((0 . elem))`. The inner expression cannot reference the caller's `X1` directly (and `X0` inside `f` means the list element, not the outer sequence `X0`).
- In ML/Scheme, `(lambda (elem) (+ elem k))` solves this by allocating a **runtime closure object** `(code-ptr, env={k: 5})`. In `lisploop`, introducing an opaque closure struct would break homoiconicity: closures wouldn't be plain S-expressions, couldn't be inspected by `:code-*` operators, and couldn't be serialized as ordinary ASTs.

#### The Solution: Quasiquotation / Partial Specialization via `:code-subst`
In a homoiconic language, instead of bundling code with a hidden environment pointer, we **splice the runtime value of `X1` directly into the quoted AST as a literal** (just like Lisp backquote `` `(+ X0 ',X1) ``):

1. Start with a binary `:code` template literal that takes both the element (`X0`) and the parameter to capture (`X1`):
   - Template: `'(+ X0 X1)` of type `(:code ((0 . :int) (1 . :int)) :int)`.
2. Apply `:code-subst` (`ast.lisp`, `vm.lisp`) to that template and a 2-tuple of bindings `(tuple 'X0 X1)`:
   - Slot 0 is `'X0` of type `(:code ((0 . :int)) :int)` --- a `:code` expression in the target unary scope, meaning **"keep `X0` as the open parameter `X0` of the new unary function."**
   - Slot 1 is `X1` of type `:int` --- an **outer runtime value**, meaning **"take the runtime value of `X1` (e.g. `5`), wrap it into a literal AST node `(lit :int 5)` (`'5`), and substitute it for `X1` in the template."**
3. At runtime, when `X1 = 5`, evaluating:
   ```lisp
   (:code-subst '(+ X0 X1) (tuple 'X0 X1))
   ```
   returns the plain S-expression `:code` value:
   ```lisp
   '(+ X0 '5)
   ```
   of type `(:code ((0 . :int)) :int)`. `:map` then evaluates `(:code-eval '(+ X0 '5) elem)` on each element with zero closure objects.

#### Why `fold-constants` (`try-unfold-call`) looks through `:code-subst`
During backward synthesis (see test case 4 in `recursion-r2-pullback-through-recursive-decoders` in `tests/recursion.lisp`), suppose the outer decoder is:
```lisp
(:map X0 (:code-subst '(* X0 X1) (tuple 'X0 Z)))
```
where `Z` is an **unknown child target variable** `(var 0 :int)` we want to synthesize. Because `Z` is still symbolic (not a concrete runtime integer yet), `:code-subst` cannot reduce to a literal `:code` constant on its own.

So `try-unfold-call` (`requirements.lisp`) recognizes the pattern `(:code-eval (:code-subst 'template (tuple ...)) elem)` and symbolically substitutes `X0 -> elem` and `X1 -> Z` into `'(* X0 X1)`. Pulling back row `X0 = '(3 5) -> '(6 10)` through that decoder unfolds `:map` and `:code-subst` directly into:
```lisp
(and (= (* '3 Z) '6)
     (= (* '5 Z) '10))
```
which M4's `propagate-requirements` (`laws.lisp`) then immediately solves to `(= Z '2)`.

---

### A.3. What the "Oracle Self-Lift" Is --- Extensional Spec Lookup + Guard-Induced Projection {#sec-appendix-oracle-self-lift}

The "Oracle Self-Lift" in Phase 3.2 combines two mechanisms integrated directly into the standard Stage A/B heuristic synthesis pipeline:

1. **The Extensional Self-Oracle (`frame-oracle-table` + `:unresolved` + Root VM Verification)**:
   - Suppose we want to synthesize an unknown recursive function `:fa` from a frame $\Omega$ of input-output examples, e.g. `() -> 0`, `(2) -> 2`, `(3 2) -> 5`, `(1 4 2) -> 7`.
   - Before `:fa` has a synthesized body, we cannot execute `(:fa (tail X0))` intensionally. However, any valid implementation of `:fa` *must* agree with the specification $\Omega$ on every input present in $\Omega$.
   - During subproblem exploration, `frame-oracle-table` treats $\Omega$ itself as a partial lookup table for `:fa`:
     - On row `X0 = (3 2) -> 5`, `(tail X0) = (2)` is in $\Omega$, so `(:fa '(2))` returns `2`.
     - On row `X0 = (1 4 2) -> 7`, `(tail X0) = (4 2)` is *not* in $\Omega$ (trace-incomplete data), so `(:fa '(4 2))` returns `:unresolved` (unrefuted rather than false).
   - **Why this part is not cheating**: The oracle table is used *only* to form and score child subproblems. Whenever a candidate expression reaches root verification (`synthesis-verification-step`), `activate-job-candidate-body` discards the oracle table, binds `:fa` to the actual candidate AST body, and executes the full recursion from scratch in the VM on all rows of $\Omega$ (under a per-row step budget `row-budget`). Thus:
     - Trace-incomplete rows like `(1 4 2) -> 7` are verified by actually executing `(1 4 2) -> (4 2) -> (2) -> ()` in the VM.
     - Trivial oracle-only fits like `(:fa X0)` or `(if (= X0 '()) '0 (:fa X0))` (which match the oracle table 100% extensionally) loop infinitely when `:fa` is bound to the candidate body, hit the per-row VM cutoff, and are rejected.

2. **Guard-Induced Non-Empty Projection in `heuristic-decompositions` (`Path B2`) and How R5/R6 Internalize It**:
   - Neither the base-case expression nor the `(= Xi '())` split is hardcoded in a separate recursive pass: `start-recursive-synthesis` simply registers `self-name` with `:oracle-table` and delegates to `start-heuristic-synthesis`.
   - Standard Stage A (`condense-heuristic`) condenses the base-case model on the full frame (`'()`, `X0`, `'0`, `'1`, `(cons X0 X1)`), and standard Stage B (`find-sound-exception-guard` in `Path B2` of `heuristic-decompositions`) discovers the separating guard `(= Xi '())`.
   - When `Path B2` sees that the synthesized guard is `(= Xi '())` (`invert-p = nil`), `Xi` is statically guaranteed to be non-empty on the `else` branch (`child-var`), making the partial sequence destructors `(at Xi '0)` and `(tail Xi)` total on that branch. `Path B2` therefore lifts `H = (at Xi '0)` and `R = (:fa ... (tail Xi) ...)` into the child's `bindings`.
   - In the R1--R6 architecture, lifting `R = (:fa ... (tail Xi) ...)` on an emptiness guard serves as the **bootstrap** before a library exists:
     - In **R4**, it synthesizes the initial corpus of concrete recursive definitions (`copy`, `inc-all`, `double-all`, `sum`, `length`, `product`, `insert`, `sort`) through the standard `heuristic-expander`.
     - In **R5 (Phase 4)**, top-down homoiconic anti-unification (`anti-unify-for-library`) across those solved ASTs factors out the shared `(if (= X0 '()) ... (at X0 '0) ... (:fa (tail X0)))` skeleton into reusable higher-order library combinators (`:map`, `:foldr`).
     - In **R6 (Phase 5)**, once `:map` and `:foldr` are in the library, new recursive tasks pull back directly through those learned library combinators via `lift-frame` (R3).

---

### A.4. R5 Worked Trace: Discovering `:map` (`:fa`) and `:foldr` (`:fb`) from the R4 Corpus {#sec-appendix-r5-library}

Given the 6 de novo recursive definitions synthesized in R4, `discover-library-abstractions` groups them by signature `(inputs . return-type)` and runs `abstract-function-bodies`:

1. **Group 1 (`((0 . (:seq :int))) -> (:seq :int)`): `copy`, `inc-all`, `double-all` $\longrightarrow$ `:fa` (`:map`)**
   - **R4 Synthesized Bodies (`original-bits = 89 + 100 + 116 = 305` bits)**:
     - `copy` (`89` bits): `(if (= X0 '()) '() (cons (at X0 '0) (:fa (tail X0))))`
     - `inc-all` (`100` bits): `(if (= X0 '()) X0 (cons (+ (at X0 '0) '1) (:fa (tail X0))))`
     - `double-all` (`116` bits): `(if (= X0 '()) X0 (cons (+ (at X0 '0) (at X0 '0)) (:fa (tail X0))))`
   - **Normalization & Control-Spine Anti-Unification**:
     - `normalize-guarded-equalities` rewrites `X0 -> '()` inside the `then` branch of `(if (= X0 '()) X0 ...)`, aligning all three base cases to `'()`.
     - `anti-unify-for-library` produces LGG pattern `(if (= X0 '()) '() (cons ?0 (:__au_self__ (tail X0))))` with hole `?0 : :int` and fillers `((at X0 '0), (+ (at X0 '0) '1), (+ (at X0 '0) (at X0 '0)))`.
   - **Positional `:code` Extraction & Combinator Synthesis**:
     - `shared-subterm-cover` extracts the single shared subterm `A_0 = (at X0 '0)` (`:int`).
     - `abstract-over-subterms` replaces `(at X0 '0)` with `(var 0 :int)` (`X0`), yielding closed `:code` literals `'X0`, `'(+ X0 '1)`, and `'(+ X0 X0)` of type `(:code ((0 . :int)) :int)`.
     - Discovered combinator `:fa` (`library-bits = 127` bits, `conditional-code-params = '(1)`):
       - Inputs: `((0 . (:seq :int)) (1 . (:code ((0 . :int)) :int)))`, return type: `(:seq :int)`
       - Body: `(if (= X0 '()) '() (cons (code-eval X1 (at X0 '0)) (:fa (tail X0) X1)))`
     - Refactored corpus calls (`refactored-call-bits = 20 + 32 + 28 = 80` bits, all certified `provably-total-p`):
       - `copy`: `(:fa X0 'X0)` (`20` bits)
       - `inc-all`: `(:fa X0 '(+ X0 '1))` (`32` bits)
       - `double-all`: `(:fa X0 '(+ X0 X0))` (`28` bits)
     - **Total MDL Compression**: `305 -> 127 + 80 = 207` bits (`gain = +98` bits).

2. **Group 2 (`((0 . (:seq :int))) -> :int`): `sum`, `length`, `product` $\longrightarrow$ `:fb` (`:foldr`)**
   - **R4 Synthesized Bodies (`original-bits = 84 + 68 + 87 = 239` bits)**:
     - `sum` (`84` bits): `(if (= X0 '()) '0 (+ (at X0 '0) (:fa (tail X0))))`
     - `length` (`68` bits): `(if (= X0 '()) '0 (+ (:fa (tail X0)) '1))`
     - `product` (`87` bits): `(if (= X0 '()) '1 (* (at X0 '0) (:fa (tail X0))))`
   - **Control-Spine Anti-Unification & Hole Classification**:
     - `anti-unify-for-library` produces LGG pattern `(if (= X0 '()) ?0 ?1)` with two holes:
       - `?0 : :int` with closed fillers `('0, '0, '1)` $\longrightarrow$ first-order value parameter `X1 : :int`.
       - `?1 : :int` with fillers `((+ (at X0 '0) (:__au_self__ (tail X0))), (+ (:__au_self__ (tail X0)) '1), (* (at X0 '0) (:__au_self__ (tail X0))))`.
   - **Positional `:code` Extraction & Combinator Synthesis**:
     - `shared-subterm-cover` extracts the canonicalized 2-subterm cover `A_0 = (at X0 '0)`, `A_1 = (:__au_self__ (tail X0))`.
     - `abstract-over-subterms` replaces `A_0 -> X0` and `A_1 -> X1`, yielding closed binary `:code` literals `'(+ X0 X1)`, `'(+ X1 '1)`, and `'(* X0 X1)` of type `(:code ((0 . :int) (1 . :int)) :int)`.
     - Discovered combinator `:fb` (`library-bits = 133` bits, `conditional-code-params = '(2)`):
       - Inputs: `((0 . (:seq :int)) (1 . :int) (2 . (:code ((0 . :int) (1 . :int)) :int)))`, return type: `:int`
       - Body: `(if (= X0 '()) X1 (code-eval X2 (at X0 '0) (:fb (tail X0) X1 X2)))`
     - Refactored corpus calls (`refactored-call-bits = 33 + 36 + 36 = 105` bits, all certified `provably-total-p`):
       - `sum`: `(:fb X0 '0 '(+ X0 X1))` (`33` bits)
       - `length`: `(:fb X0 '0 '(+ X1 '1))` (`36` bits)
       - `product`: `(:fb X0 '1 '(* X0 X1))` (`36` bits)
     - **Total MDL Compression**: `239 -> 133 + 105 = 238` bits (`gain = +1` bit on 3 folds; `339 -> 133 + 151 = 284` bits, `gain = +55` bits when a 4th fold `sum-squares` is included; while a 2-fold pair has `gain = -16` bits and is rejected).
