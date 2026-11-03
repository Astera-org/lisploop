---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,calc,shapes.geometric,fit,backgrounds}
---

# `lisploop` — plan 6

## Overview: Aim, Design Principle, and Milestone Map

### Aim

`lisploop` is a self-contained Common Lisp kernel and experimental suite investigating how an automated mathematical and algorithmic discovery system can **observe, compress, reorient, factor, and accelerate its own search** under strict resource accounting. Starting from raw relational observations or partial input-output specifications over finite prime fields $\mathbb{F}_p$ and unbounded signed integers $\mathbb{Z}$, the system synthesizes executable programs, discovers empirical invariants and certified algebraic laws, synthesizes domain-validity guards, reorients forward operators into backward constraint propagators, lifts latent intermediate concepts without supervision, extracts reusable syntactic abstractions and piecewise domain views, and condenses search experience into compact heuristic predictors and library descriptors.

### Core Design Principle

Every capability across all nine milestones is governed by two structural invariants:

1. **Homoiconic S-expression uniformity**: All mathematical objects in the system—object-language programs, row requirement predicates $A_\omega(Y)$ and $B_\omega(Z)$, quoted syntax values of type `(:code inputs sort)`, anti-unification templates with holes `#:?0`, algebraic laws, and rewrite rules—are ordinary Lisp cons trees constructed from a pooled symbol table (`*typed-symbol-pool*`) with $O(1)$ precomputed prefix-free bit-size metadata stored in a weak `eq` hash table (`*node-meta*`).
2. **Two-resource accounting ($S$ vs. $W$) and four fundamental operations**: Every transformation in the system either optimizes **Description Length ($S$)** (compressing representation size via lossless factorization or exact laws) or optimizes **Computational Work ($W$)** (reducing expected runtime work $W_{\mathrm{run}}$ or search work $W_{\mathrm{search}}$ via lossy heuristic condensation or tentative propagation, while preserving completeness through a 1-in-4 canonical reserve and authoritative forward replay). All nine milestones reduce to compositions of four operations:
   - **Operation 1 — Observational Conservation Across Frame Rows**: Unary synthesis, cross-row empirical equivalence and action invariance, exhaustive law certification, and exact Boolean guard synthesis.
   - **Operation 2 — Factorization & Latent Fiber Inference ($S$ Compression)**: Right-inverses of `Apply` across syntax trees (`anti-unify`, subgraph correspondence), value tables (`quotient-values`, `partition-rows`), and pulled-back requirement fibers (`infer-fibers` via Hard-EM MDL partition search).
   - **Operation 3 — Causal Reorientation, Contravariant Pullback, Constant Folding & Dual-Grade Propagation**: Reorienting relational observations without re-simulation, pulling parent requirements $A_\omega(Y)$ back through decoders $Y = d(X, Z)$ via `fold-constants`, detecting conflicts via `frame-conflict-p`, and narrowing child requirements via certified ($\iff$) in-place replacement or tentative ($\Leftarrow$) 3:1 scheduled propagation.
   - **Operation 4 — Lossy Heuristic Condensation & Multi-Lane Search Control ($W$ Compression)**: Synthesizing compact heuristic programs $\hat{\pi}(X)$ via `condense-heuristic` that price residuals during training and drop the residual table at deployment to steer partition selection, search ordering, and library retrieval.

### Reading & Implementation Map

| Milestone | Core Question | Operations Used | Kernel Modules | Experiment Runner & Test Suite |
| :--- | :--- | :--- | :--- | :--- |
| **1. Search** | Can typed bottom-up search synthesize compact programs under strict preemption, reorientation, pullback, and view controls? | Op 1 (unary), Op 2 (aligned AU & views), Op 3 (pullback) | `ast.lisp`, `codec.lisp`, `vm.lisp`, `frame.lisp`, `enumerate.lisp` | `experiments.lisp` (`run-m1`), `tests/core.lisp`, `tests/codec.lisp` |
| **2. Equivalence** | Can observational bucketing discover action invariants and split accidental agreements as evidence grows? | Op 1 (cross-row equivalence & orbit invariance) | `vm.lisp`, `frame.lisp`, `enumerate.lisp` | `experiments.lisp` (`run-m2`), `tests/observations.lisp`, `tests/visualizer.lisp` |
| **3A. Guarded Laws** | Can partial equations and domain-validity guards be discovered jointly and certified on finite domains? | Op 1 (exhaustive validation & zero-residual guard synthesis) | `enumerate.lisp`, `laws.lisp` | `law-experiments.lisp`, `tests/laws.lisp`, `tests/guards.lisp` |
| **3B. Law Compression** | Can anti-unification compress a corpus of discovered laws into shared templates and typed constructors? | Op 2 (term-algebra AU over quoted `:code` packets) | `codec.lisp`, `factor.lisp`, `laws.lisp` | `law-experiments.lisp`, `tests/compression.lisp` |
| **3C. Symbolic VM** | Can checked rewrite rules be expressed as first-class `:code` programs and amortized across search? | Op 1 + Op 3 (symbolic pullback) + rule amortization | `ast.lisp`, `vm.lisp`, `laws.lisp` | `law-experiments.lisp`, `tests/symbolic.lisp`, `tests/amortization.lisp` |
| **4. Algebra** | Can forward operators be reoriented into backward solvers that propagate certified ($\iff$) or tentative ($\Leftarrow$) child constraints? | Op 1 (solver/guard laws) + Op 3 (dual-grade propagation) | `frame.lisp`, `laws.lisp` | `algebra-experiments.lisp` (`run-m4`), `tests/algebra.lisp`, `tests/propagation.lisp` |
| **5. Lifting** | Can latent intermediate concepts be lifted via supplied contexts and discovered unsupervised via Hard-EM fiber clustering? | Op 2 (`infer-fibers`) + Op 3 (pullback/propagation) + Op 4 (`condense-heuristic`) | `frame.lisp`, `factor.lisp`, `laws.lisp` | `lifting-experiments.lisp` (`run-m5`), `tests/lifting.lisp` |
| **6. Abstraction** | Can repeated subtrees at unaligned positions and law-normalized syntax be factored into reusable abstractions? | Op 2 (aligned AU & subgraph search) + Op 1 (validated rewrites) | `ast.lisp`, `factor.lisp`, `laws.lisp` | `abstraction-experiments.lisp` (`run-m6`), `tests/abstraction.lisp` |
| **7. Views & Locality** | Can Boolean regime splits be discovered autonomously and locality priors accelerate subexpression search? | Op 1 (guard buckets) + Op 2 (views) + Op 3 (`frame-conflict-p`) + Op 4 (locality) | `frame.lisp`, `factor.lisp` | `view-experiments.lisp` (`run-m7`), `tests/views.lisp` |
| **8. Recursion** | Can multi-step decomposition chain pullbacks, prune conflicts early, and condense search returns into heuristics? | Op 2 + Op 3 (`fold-constants`, `frame-conflict-p`) + Op 4 (`condense-heuristic`) | `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `laws.lisp` | `tests/propagation.lisp`, `frame.lisp`, `factor.lisp` |
| **9. Vocabulary** | Can learned functions be indexed by opaque symbols and retrieved via condensed symbolic descriptors? | Op 2 (library packaging) + Op 4 (descriptor condensation & retrieval) | `ast.lisp`, `enumerate.lisp`, `factor.lisp` | Library descriptor synthesis & 3:1 prioritized retrieval |

---

## 1. Shared Contract: Homoiconic Representation, Availability, Cost Accounting & Epistemic Grades

All nine milestones share a single representation, execution engine, cost ledger, and epistemic grading contract. No milestone may introduce a private evaluator, unpriced side channel, or unverified shortcut.

### 1.1 Ambient Numeric Domains, Semantic Types, and Schema $\Gamma$

Every synthesis, observation, or validation problem is governed by an explicit **Schema** $\Gamma$:
$$\Gamma = \bigl(D,\; X_0{:}\tau_0,\, \dots,\, X_{m-1}{:}\tau_{m-1} \to \tau\bigr)$$
constructed by `make-schema` in `ast.lisp` (`schema-domain`, `schema-inputs`, `schema-target`, `schema-lookup-p`).

1. **Ambient Numeric Domain $D$**: Either unbounded signed integers `:int` ($\mathbb{Z}$) or a prime finite field `(:gf p)` ($\mathbb{F}_p$ with $p$ verified prime at construction by `prime-modulus-p`; composite moduli such as `(gf 4)` raise an immediate error). All arithmetic inside $\mathbb{F}_p$ is reduced modulo $p$, with exact multiplicative inverse via extended GCD (`gf-invert`) and division by zero raising a metered `evaluation-error`. In `:int`, division `:/` is truncating toward zero (`truncate`), and any non-Boolean conditionals or out-of-bounds sequence operations raise `evaluation-error`.
2. **Semantic Types $\tau$ and Runtime Value Sets $\mathcal{V}_\tau$**:
   - **Scalars**: `:int` ($\mathcal{V}_{\texttt{:int}} = \mathbb{Z}$), `(:gf p)` ($\mathcal{V}_{\texttt{(:gf }p\texttt{)}} = \{0, \dots, p-1\}$), and `:bool` ($\mathcal{V}_{\texttt{:bool}} = \{\texttt{nil}, \texttt{t}\}$).
   - **Product Types**: `(:tuple tau_0 ... tau_{k-1})` represented at runtime as proper lists `(v_0 ... v_{k-1})` of length $k$.
   - **Sequence Types**: `(:seq elem-type)` represented at runtime as proper lists of homogeneous elements, indexed by non-negative `:int` positions via `:gather` or key-value tuple tables via `:lookup`.
   - **Quoted Syntax Types**: `(:code ((id_0 . tau_0) ...) sort)` whose runtime values $v \in \mathcal{V}_\tau$ are typed object-language ASTs wrapped as `(lit code-type expr)`. Quoted syntax values are inspected and constructed by structural `:code-*` operators (`:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`, `:code-subst`, `:code-total`) without ever invoking `eval` or `funcall`.
3. **Exhaustive Domain Grid $D^\Gamma$**: When every input type $\tau_r$ is finite (`(:gf p)`, `:bool`, or nested tuples thereof), the exhaustive input grid $D^\Gamma = \mathcal{V}_{\tau_0} \times \dots \times \mathcal{V}_{\tau_{m-1}}$ is enumerable (`enumerable-type-p`, `enumerate-domain-rows`), enabling complete finite-domain law validation.

### 1.2 Homoiconic S-Expression AST and $O(1)$ Metadata Cache

Programs, requirements, laws, and anti-unification patterns are represented directly as canonical S-expressions rather than parallel `defstruct` hierarchies:

- **Variables**: `(var id type)` produces an interned uninterned symbol `#:X0`, `#:X1`, ... from `*typed-symbol-pool*` whose `get` plist stores `:kind :var`, `:id id`, and `:type type`.
- **Holes**: `(hole id type :kind (:value | :fn))` produces `#:?0`, `#:?1`, ... from `*typed-symbol-pool*` with `:kind :hole` and `:hole-kind`.
- **Operators**: `(op kind sig &key arity)` produces a pooled operator symbol (e.g., `#:+`, `#:if`, `#:tuple`, `#:gather`, `#:lookup`, `#:code-match`) carrying `:kind :op`, `:op-kind`, `:type` (return type), `:arg-types`, and `:arity`.
- **Literals**: `(lit type value)` produces standard Lisp quote forms `'value` whose type and precomputed payload bit-size are cached in `*node-meta*`.
- **Applications**: `(app op arg_1 ... arg_k)` constructs the ordinary list `(op arg_1 ... arg_k)` after verifying exact operator arity and argument types (`CheckTypes`), immediately computing and caching its `node-meta` in `*node-meta*`.

Because `node-meta` (`node-meta-type`, `node-meta-body-bits`, `node-meta-op-count`, `node-meta-free-vars`) is synthesized bottom-up at `app`/`lit`/`var`/`hole` construction time:
$$\mathrm{body\text{-}bits}\bigl((f\; e_1 \dots e_k)\bigr) = \mathrm{operator\text{-}bits}(f) + \sum_{i=1}^k \mathrm{body\text{-}bits}(e_i)$$
querying the prefix-free body bit-length $S_{\mathrm{body}}(e)$ or type $\tau$ of any AST node is $O(1)$ with zero traversal allocation.

### 1.3 Observation Frame $\Omega$, Row $\omega$, and Strict Information Isolation

An **Observation Frame** $\Omega$ (`frame` in `frame.lisp`) combines a `schema` $\Gamma$ with a sequence of **Rows** $\omega \in \Omega$ (`row` in `frame.lisp`):
$$\omega = \bigl(\mathrm{key}(\omega),\; \mathbf{x}_\omega,\; A_\omega(Y)\bigr)$$
where:
- $\mathrm{key}(\omega)$ (`row-key`) is an explicit occurrence identifier (such as a sample index, sequence position, or transition probe tag),
- $\mathbf{x}_\omega = (x_{\omega,0}, \dots, x_{\omega,m-1}) \in \mathcal{V}_{\tau_0} \times \dots \times \mathcal{V}_{\tau_{m-1}}$ (`row-known`) is the tuple of bound input values available at runtime, and
- $A_\omega(Y)$ (`row-requirement`) is a closed Boolean-typed S-expression whose sole free symbolic variable is the target $Y = \texttt{(var 0 }\tau\texttt{)}$. Standard constructors are `singleton-requirement` (`(= Y 'y_w)`), `set-requirement` (`(member Y '(v_1 ... v_k))`), and arbitrary Boolean predicate expressions $A_\omega(Y)$.

In addition to per-row unary requirements $A_\omega(Y)$, a `frame` $\Omega$ optionally carries relational row linkages `frame-pairs` and `frame-anchors` over row keys $\mathrm{key}(\omega)$, which can either be supplied from transition trajectories (`transition-probes`) or **computed** from any partition, view split, or fiber clustering (`partition-pairs-and-anchors`, `fiber-pairs-and-anchors`, `with-frame-linkage`).

**Strict Information Isolation ("No Informational Loops")**:
1. **Separation of Frame, Oracle, and Provenance**: The `frame` $\Omega$ contains only what the learner is allowed to observe. Any planted generating program or test fixture metadata is stored in a separate `provenance` structure that is never passed to search, law discovery, or factorization procedures. If an interactive `oracle` is used, it may only evaluate candidate inputs $\mathbf{x}$ and charge `:simulation` work; its internal syntax is inaccessible.
2. **Copy-on-Create Boundary Isolation**: Constructing an `observation-scope` or `search-job` deep-copies `frame-rows` and `language-literals` (`copy-row-list`, `copy-value`) so subsequent mutation by a caller cannot leak information into an active job.
3. **Standalone Model Execution**: Every synthesized `model` (`program-model`, `lookup-model`, `quotient-model`, `partition-model`, `corpus-abstraction-model`) must serialize to a self-delimiting bit vector via `encode-model`, decode in a clean state via `decode-model`, and pass `verify-model` / `execute-model` after the originating `frame`, `oracle`, and `provenance` have been nilled out.

### 1.4 Single Resumable Evaluation Stepper and Single Return Channel

All expression evaluation—whether inside candidate synthesis, row requirement checking, observational bucketing, law validation, constant folding, or symbolic rewriting—executes through the single frame-stack state machine `evaluation` in `vm.lisp` (`start-evaluation`, `advance-evaluation`, `evaluate`):

1. **Debt-Draining Preemption (`evaluation-debt`)**: Every VM step checks both remaining budget (`<= budget 0`) and pending sub-step work debt (`> (evaluation-debt eval) 0`). When a heavy multi-word arithmetic operation (such as $2^{256} \times 2^{256}$) or a prepaid bounds check exceeds the current work quantum, its cost is registered in `evaluation-debt` and drained across subsequent `advance-evaluation` calls before the instruction's result is pushed to `evaluation-values` or its error is signaled.
2. **Exact `quantum = 1` vs. Batch Parity**: Because instruction continuations (`eval-frame`), operand stacks, and work ledgers are updated atomically as debt drains, interrupting and resuming any search, observation, validation, or propagation job with `quantum = 1` produces the exact same (`equalp`) continuation stack, work ledger, and discovered results as running with a large batch budget.
3. **Single Return Channel (`message`)**: Every search or validation driver returns a `message` struct (`message-status` $\in \{\texttt{:complete}, \texttt{:cutoff}, \texttt{:exhausted}, \texttt{:invalid}\}$, `message-best`, `message-proposals`, `message-work`, `message-cursor`, `message-diagnostics`). Any candidate whose evaluation or requirement check is interrupted by a budget cutoff remains unresolved in the job's continuation cursor and is never reported as verified or refuted.

### 1.5 Exact Cost Accounting ($S$, $W_{\mathrm{run}}$, $W_{\mathrm{search}}$) and Two-Level Objectives

#### Description Length $S$ (Encoding v7)
Every model $M$ is encoded into a prefix-free bit vector under **Encoding v7** (`*encoding-version* = 7`, `codec.lisp`):
$$S(M) = S_{\mathrm{header}}(\Gamma) + S_{\mathrm{body}}(M)$$
- **Header $S_{\mathrm{header}}(\Gamma)$**: Encodes the 3-bit version (`7`), 2-bit packet kind (`0` expression, `1` lookup table, `2` concatenation corpus, `3` AU template+substitutions), target type $\tau$, input variable schema $((id_0 . \tau_0) \dots)$, and lookup flag once per model. Variable IDs are mapped to 0-based positional indices within the packet so $S_{\mathrm{body}}(M)$ and enumeration order are invariant to raw symbol ID numbers.
- **Body $S_{\mathrm{body}}(M)$**: Uses 2-bit AST node tags (`0` variable, `1` literal, `2` application, `3` hole) and Elias-gamma self-delimiting integers (`positive-bits` for $n \ge 1$ using $2\lfloor\log_2 n\rfloor + 1$ bits; `signed-bits` via zigzag encoding).
- **Analytical Literal Inversion**: `literal-range` in `codec.lisp` inverts the zigzag Elias-gamma bit-size threshold in $O(1)$ time to determine the exact integer interval $[-2^{k-1}, 2^{k-1}-1]$ that fits within $b$ remaining bits during bounded bottom-up enumeration.

#### Computational Work $W$ (Tariff v8 & Simulator v5)
Every operation charges an explicit `work` ledger (`*tariff-version* = 8`, `*simulator-version* = 5`) partitioned into ten orthogonal buckets:
- `:enumeration` (1 unit per candidate AST node or literal range step),
- `:proposal-execution` (evaluating a candidate $e$ on row inputs $\mathbf{x}_\omega$),
- `:checker` (evaluating requirement $A_\omega(Y)$ on the proposed output),
- `:simulation` (querying an external oracle or generating forward execution tables),
- `:orientation` (reorienting recorded observations into new input/requirement projections),
- `:rewrite` (applying a checked symbolic rewrite rule),
- `:validation` (exhaustive domain evaluation for law or rewrite certification),
- `:compression` (anti-unification, quotient/partition view factoring, Hard-EM fiber search, and heuristic condensation),
- `:matching` (structural pattern matching in `:code-match` or propagator library matching), and
- `:discovery` (observational bucketing, invariant filtering, and guard search).

Individual VM instructions are priced by operand bit size (`value-bit-size`): scalar comparisons and field operations cost $1 + \text{operand bits}$, integer multiplication costs $2 + \mathrm{bits}(a) \cdot \mathrm{bits}(b)$, and `:gather`/`:lookup` prepay $1 + \mathrm{bits}(\text{index}) + \mathrm{bits}(\text{length})$ **before** checking bounds or allocating result copies.

#### Object-Level vs. Meta-Level Objectives
1. **Object-Level Model Objective $J(M)$**: Ranks candidate models $M$ for a fixed frame $\Omega$:
   $$J(M) = S(M) + S\bigl(\varepsilon(M, \Omega)\bigr) + \lambda_{\mathrm{run}}\, W_{\mathrm{run}}(M)$$
   - For **exact synthesis, law discovery, and lossless compression** (Operations 1–3), admissibility requires zero residual ($\varepsilon_\omega = 0$ on all $\omega \in \Omega$, so $S(\varepsilon(M, \Omega)) = 0$), reducing the objective to $J_{\mathrm{exact}}(M) = S(M) + \lambda_{\mathrm{run}}\, W_{\mathrm{run}}(M)$.
   - For **lossy heuristic condensation** (Operation 4, `condense-heuristic`), $S(\varepsilon(\hat{\pi}, F))$ prices every row $\omega_i$ where $\hat{\pi}(\mathbf{x}_{\omega_i}) \neq w_i$ at $\mathrm{positive\text{-}bit\text{-}size}(i + 1) + \mathrm{value\text{-}bit\text{-}size}(w_i, \tau)$ during selection, and **drops $\varepsilon$ at deployment** because the downstream consumer relies on a 1-in-4 canonical reserve and authoritative verification.
2. **Meta-Level Procedural Objective $J_{\mathrm{procedure}}(P)$**: Evaluates end-to-end discovery procedures $P$ (including search, rewrite preparation, propagation, lifting, and view discovery):
   $$J_{\mathrm{procedure}}(P) = J(M_P) + \lambda_{\mathrm{search}}\, W_{\mathrm{search}}(P)$$
   where $W_{\mathrm{search}}(P)$ is the `work-total` across all ten buckets accumulated to produce $M_P$.

### 1.6 Epistemic Grades and Certificates

Every discovered statement, guard, solver, or rewrite rule carries an explicit epistemic status (`law-proposal-status`):
- `:replayed-observations` — holds on a finite set of empirical or held-out trajectory rows.
- `:conjecture` — holds on all tested sample rows of an infinite domain (`:int`) or an incompletely enumerated finite domain (either due to sample scope or budget `:cutoff`).
- `:vacuous` — guard is false on every row of the tested scope ($\Omega_{\mathrm{support}} = \emptyset$).
- `:refuted` — at least one concrete counterexample row $\omega$ was found where the guard holds and the equation/postcondition fails or errors (`law-proposal-counterexample`).
- `:validated` — exhaustively verified across **all** rows of a finite enumerable domain grid $\Omega = D^\Gamma$ (`schema-enumerable-p` and `frame-covers-domain-p`) with at least one positive support row and zero errors/cutoffs. Only `:validated` laws receive an immutable `law-certificate` (`law-certificate-law-bits`, `law-certificate-domain`, `law-certificate-inputs`, `law-certificate-support-size`), and only `:validated` laws may authorize in-place ($\iff$) downward constraint replacement or unverified syntactic rewriting.

---

## 2. The Four-Operation Mathematical Framework

Every capability across Milestones 1–9 is an instance or composition of **four fundamental operations** over a unified mathematical vocabulary.

### Nomenclature & Kernel Mapping

| Symbol | Mathematical Object | Kernel Representation (`lisploop`) |
| :--- | :--- | :--- |
| $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$ | **Schema**: ambient numeric domain $D \in \{\texttt{:int}, \texttt{(:gf } p\texttt{)}\}$, typed formal input signature, and target type $\tau$ | `schema` (`make-schema` in `ast.lisp`: `schema-domain`, `schema-inputs`, `schema-target`) |
| $D^\Gamma = \mathcal{V}_{\tau_0} \times \dots \times \mathcal{V}_{\tau_{m-1}}$ | **Exhaustive Input Grid**: Cartesian product of the runtime value domains $\mathcal{V}_{\tau_r}$ of each input variable $X_r : \tau_r$ (finite and enumerable when every $\tau_r$ is finite, e.g., `(:gf p)`, `:bool`, or tuples thereof) | `enumerable-type-p`, `enumerate-domain-rows`, `frame-covers-domain-p` (`laws.lisp`) |
| $\tau,\; \mathcal{V}_\tau$ | **Semantic Type & Value Domain**: `:int`, `(:gf p)`, `:bool`, `(:tuple ...)`, `(:seq ...)`, or quoted syntax `(:code inputs sort)`. For `(:code ...)`, runtime values $v \in \mathcal{V}_\tau$ are typed object-language ASTs wrapped as `(lit code-type expr)` | Type forms and runtime values (`ast.lisp`, `vm.lisp`) |
| $X = (X_0, \dots, X_{m-1})$ | **Symbolic Input Variables**: formal variable symbols of types $(\tau_0, \dots, \tau_{m-1})$ appearing inside object-language expressions | Pooled symbols `(var id type)` $\to$ `#:X0, #:X1, ...` (`*typed-symbol-pool*` in `ast.lisp`) |
| $Y : \tau_P,\; Z : \tau_C$ | **Symbolic Target Variables**: formal target variable `(var 0 type)` inside a parent requirement predicate $A_\omega(Y)$ or child requirement predicate $B_\omega(Z)$ | `(var 0 target-type)` inside `row-requirement` (`frame.lisp`) |
| $\Omega = \{\omega_1, \dots, \omega_N\}$ | **Observation Frame**: finite indexed sequence of observation rows under schema $\Gamma$, optionally carrying relational must-agree `pairs` and must-vary `anchors` | `frame` (`make-frame`, `with-frame-linkage` in `frame.lisp`: `frame-schema`, `frame-rows`, `frame-pairs`, `frame-anchors`) |
| $\omega = (\mathrm{key}, \mathbf{x}_\omega, A_\omega)$ | **Observation Row**: row key/occurrence identifier, bound input vector $\mathbf{x}_\omega = (x_{\omega,0},\dots,x_{\omega,m-1}) \in \mathcal{V}_{\tau_0}\times\dots\times\mathcal{V}_{\tau_{m-1}}$, and requirement predicate $A_\omega(Y)$ | `row` (`make-row` in `frame.lisp`: `row-key`, `row-known`, `row-requirement`) |
| $(\omega_a, \omega_b) \in \mathrm{pairs}$ and $\omega_r \in \mathrm{anchors}$ | **Relational Row Linkages (Must-Agree `pairs` & Must-Vary `anchors`)**: `pairs` is a list of 2-element row-key links $(\omega_a, \omega_b)$ requiring an observable or latent quantity $e(X)$ to agree ($M(e, \omega_a) = M(e, \omega_b)$); `anchors` is a list of representative row keys $(\omega_{r_0}, \omega_{r_1}, \dots)$ across distinct orbits/regimes requiring $e(X)$ not to collapse to a single constant ($\exists \omega_{r_u}, \omega_{r_v} \in \mathrm{anchors},\; M(e, \omega_{r_u}) \neq M(e, \omega_{r_v})$) | `frame-pairs`, `frame-anchors`, `observation-scope` (`classify-observation-bucket` in `enumerate.lisp`); computed from transitions by `transition-probes`, from partitions/views by `partition-pairs-and-anchors` & `with-frame-linkage` (`frame.lisp`), and from Hard-EM fibers by `infer-fibers` & `fiber-pairs-and-anchors` (`factor.lisp`) |
| $A_\omega(Y),\; B_\omega(Z)$ | **Row Requirement Predicate**: closed Boolean expression with free target variable $Y$ (or $Z$) encoding `(= Y 'y_w)`, `(member Y '(...))`, or an arbitrary relational guard | Homoiconic S-expression in `row-requirement` (`singleton-requirement`, `set-requirement`) |
| $\mathrm{Fiber}(\omega) \subseteq \mathcal{V}_{\tau_C}$ | **Admissible Target Fiber of Row $\omega$**: set of candidate target values $\{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ satisfying row $\omega$'s requirement | Concrete value set in $\mathcal{V}_{\tau_C}$ (`row-allowed-values`, `infer-fibers` in `factor.lisp`) |
| $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ | **Latent Partition Block (Row Level Set)**: subset of rows assigned to latent regime index $k \in \{0,\dots,K-1\}$ with non-empty common fiber $\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset$ | Cluster indices and merged requirement $B_{c_k}(Z) = \bigwedge_{\omega \in \Omega_k} B_\omega(Z)$ (`infer-fibers`) |
| $\mathcal{L}(\Gamma)$ | **Typed Expression Grammar**: well-typed S-expressions over schema $\Gamma$ with cached prefix-free bit-size metadata | Pooled S-expressions with `*node-meta*` (`ast.lisp`, `codec.lisp`, `enumerate.lisp`) |
| $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega)$ | **Outcome Matrix**: evaluation of expression $e \in \mathcal{L}(\Gamma)$ on row $\omega$'s bound inputs $\mathbf{x}_\omega$, yielding $v \in \mathcal{V}_\tau$, error $\bot_{\mathrm{err}}$, or budget cutoff $\bot_{\mathrm{cutoff}}$ | Resumable VM stepper `evaluation` (`vm.lisp`) and `observation-job` (`enumerate.lisp`) |
| $S(M),\; W_{\mathrm{run}}(M),\; W_{\mathrm{search}}(P)$ | **Resource Metrics**: prefix-free description bits $S(M) = S_{\mathrm{header}}(\Gamma) + S_{\mathrm{body}}(M)$, runtime evaluation work $W_{\mathrm{run}}(M)$, and cumulative search/discovery work $W_{\mathrm{search}}(P)$ | `description-size`, `body-size` (`codec.lisp`); 10-bucket `work` ledger (`ast.lisp`) |

### Key Conceptual Distinctions

- **Symbolic variables (uppercase $X, Y, Z$) vs. bound runtime values (lowercase $\mathbf{x}_\omega, y_\omega, z_\omega$)**: Uppercase $X = (X_0, \dots, X_{m-1})$, $Y$, and $Z$ denote formal AST variable nodes (`(var id type)`). Lowercase $\mathbf{x}_\omega = (x_{\omega,0}, \dots, x_{\omega,m-1})$ denotes the concrete runtime value vector stored in `row-known` on row $\omega \in \Omega$, and lowercase $y_\omega, z_\omega \in \mathcal{V}_\tau$ denote concrete runtime target values. Substituting $X \gets \mathbf{x}_\omega$ into an expression $d(X, Z)$ replaces each input variable $X_r$ with the literal `'x_{\omega,r}`, leaving only $Z$ free.
- **Value-space fiber $\mathrm{Fiber}(\omega) \subseteq \mathcal{V}_{\tau_C}$ vs. row-space partition block $\Omega_k \subseteq \Omega$**: For a single row $\omega \in \Omega$, its **admissible fiber** $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ lives in the target value space $\mathcal{V}_{\tau_C}$. Conversely, a **partition block** (or level set) $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ is a subset of observation rows in $\Omega$. A block $\Omega_k$ is jointly realizable by a single latent concept value $c_k \in \mathcal{V}_{\tau_C}$ if and only if the intersection of its value-space fibers is non-empty:
  $$\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset \iff \exists c_k \in \mathcal{V}_{\tau_C}\;\forall \omega \in \Omega_k,\; B_\omega(c_k) = \mathrm{t}.$$
- **What `pairs` and `anchors` mean (between frames vs. within a frame, and how both are computed)**:
  - **Meaning**: Whereas $A_\omega(Y)$ constrains row $\omega$'s output unary-wise, `pairs` and `anchors` express **relational equivalence and separation constraints across rows of $\Omega$** without fixing concrete target values in advance. Specifically, `pairs` $= \{(\omega_a, \omega_b)\}$ are **intra-block must-agree links** requiring $M(e, \omega_a) = M(e, \omega_b)$ (checked by `classify-observation-bucket` to set `observation-bucket-invariant-p`), while `anchors` $= (\omega_{r_0}, \dots, \omega_{r_{K-1}})$ are **cross-block diversity representatives** requiring $e$ to take at least two distinct values across different blocks (setting `observation-bucket-informative-p` so trivial constants are excluded).
  - **Between frames vs. within a frame**: `pairs` and `anchors` naturally arise when reorienting or factoring one frame into another—for example, `transition-probes` reorients a transition frame $\Omega_{\mathrm{step}}: (a,b) \mapsto (a',b')$ into a 2$N$-row probe frame $\Omega_{\mathrm{probe}}$ whose `pairs` `((\omega :before) (\omega :after))` remember which rows came from the same step in $\Omega_{\mathrm{step}}$. Storing `:pairs` and `:anchors` on `frame` (`with-frame-linkage`) allows any newly proposed linkage (from a transition, a Boolean view guard, or Hard-EM fiber clustering) to produce a self-contained `frame` ready for `make-observation-scope`.
  - **Computing `pairs` and `anchors`**: Neither needs to be hand-supplied. Given any partition $\Omega = \bigsqcup_{k=0}^{K-1} \Omega_k$ (from `partition-rows`, a Milestone 7 guard split `evaluate-guard-partition`, or Milestone 5 `infer-fibers`), `partition-pairs-and-anchors` (`frame.lisp`) and `fiber-pairs-and-anchors` (`factor.lisp`) automatically compute:
    1. `pairs`: for each block $\Omega_k = (\omega_{k,0}, \omega_{k,1}, \dots, \omega_{k,m-1})$ with $m \ge 2$, the $m - 1$ adjacent chain links $\bigl((\omega_{k,0}, \omega_{k,1}), (\omega_{k,1}, \omega_{k,2}), \dots\bigr)$ enforcing constancy across the entire block $\Omega_k$ in $O(m)$ checks; and
    2. `anchors`: the leading representative $\omega_{k,0}$ of each multi-row block $\Omega_k$ (when $K \ge 2$), enforcing separation across blocks.
- **Ambient domain $D$ vs. exhaustive input grid $D^\Gamma$**: $D \in \{\texttt{:int}, \texttt{(:gf } p\texttt{)}\}$ is the ambient numeric sort of the schema, whereas $D^\Gamma = \mathcal{V}_{\tau_0} \times \dots \times \mathcal{V}_{\tau_{m-1}}$ is the Cartesian product of the input variable domains (which may mix scalars, Booleans, tuples, sequences, or `:code` syntax).
- **Object-level model objective $J(M)$ vs. meta-level procedural objective $J_{\mathrm{procedure}}(P)$**: Candidate synthesis and compression rank individual models $M$ by $J(M) = S(M) + S(\varepsilon(M, \Omega)) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$ (with $\varepsilon \equiv 0$ for exact models and priced residual $\varepsilon$ during lossy heuristic condensation). Search control, propagation, and rewrite amortization evaluate whole discovery procedures $P$ by $J_{\mathrm{procedure}}(P) = J(M_P) + \lambda_{\mathrm{search}} W_{\mathrm{search}}(P)$.

\begin{figure}[htbp]
\centering
\resizebox{\textwidth}{!}{%
\begin{tikzpicture}[
  >=Latex,
  every node/.style={font=\small\sffamily},
  data/.style={
    draw=black!75, thick, rounded corners=4pt, fill=gray!8,
    text width=4.6cm, minimum height=1.15cm, align=center, inner sep=5pt
  },
  op/.style={
    draw=blue!75!black, thick, rounded corners=3pt, fill=blue!6,
    text width=4.6cm, minimum height=1.25cm, align=center, inner sep=5pt
  },
  store/.style={
    draw=teal!75!black, thick, cylinder, shape border rotate=90, aspect=0.22,
    fill=teal!8, text width=4.3cm, minimum height=1.15cm, align=center, inner sep=4pt
  },
  flow/.style={->, thick, draw=black!80},
  feedback/.style={->, thick, dashed, draw=blue!75!black},
  lbl/.style={font=\scriptsize\sffamily, fill=white, inner sep=1.5pt, align=center}
]

  % Top center: Frame and Grammar
  \node[data] (frame) at (0, 0) {
    \textbf{Observation Frame $\Omega$ \& Schema $\Gamma$}\\
    {\scriptsize Rows $\omega = (\mathrm{key}, \mathbf{x}_\omega, A_\omega(Y))$,\\ Grammar $\mathcal{L}(\Gamma)$}
  };

  % Center: Resumable VM & Outcome Matrix
  \node[data, fill=yellow!12] (matrix) at (0, -3.2) {
    \textbf{Resumable VM \& Outcome Matrix $M(e, \omega)$}\\
    {\scriptsize $\mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$\\ (\texttt{vm.lisp})}
  };

  % Operation 1: Left
  \node[op] (op1) at (-7, -3.2) {
    \textbf{Op 1: Observational Conservation}\\
    {\scriptsize Unary synthesis, cross-row buckets,}\\
    {\scriptsize action invariants, guards $G(X)$ \& laws}
  };

  % Operation 3: Right
  \node[op] (op3) at (7, -3.2) {
    \textbf{Op 3: Pullback \& Propagation}\\
    {\scriptsize $B_\omega(Z) = \mathrm{Fold}(A_\omega(d(\mathbf{x}_\omega, Z)))$}\\
    {\scriptsize Conflict check; $\iff$ in-place / $\Leftarrow$ 3:1}
  };

  % Stores below Op 1 and Op 3
  \node[store] (laws) at (-7, -7.3) {
    \textbf{Certified Laws \& Solvers}\\
    {\scriptsize \texttt{:validated} ($\Omega = D^\Gamma$)\\ vs.\ \texttt{:conjecture}}
  };

  \node[data] (fibers) at (7, -7.0) {
    \textbf{Child Frame $\Omega_C$ \& Fibers}\\
    {\scriptsize $\mathrm{Fiber}(\omega) = \{z \mid B_\omega(z) = \mathrm{t}\}$}
  };

  % Operation 2: Bottom Center-Left
  \node[op] (op2) at (-3.6, -11.0) {
    \textbf{Op 2: Factorization ($S$ Compression)}\\
    {\scriptsize Right-inverse of $\mathrm{Apply}(p, \theta_\omega) = t_\omega$:}\\
    {\scriptsize AU, Subgraphs, Views, Hard-EM \texttt{infer-fibers}}
  };

  % Operation 4: Bottom Center-Right
  \node[op] (op4) at (3.6, -11.0) {
    \textbf{Op 4: Heuristic Condensation ($W$ Control)}\\
    {\scriptsize $\min_{\hat{\pi}} S(\hat{\pi}) + S(\varepsilon) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(\hat{\pi})$}\\
    {\scriptsize Drops $\varepsilon$ at deployment; 1-in-4 canonical reserve}
  };

  % Primary Data Flows
  \draw[flow] (frame) -- node[lbl, right=2pt] {enumerate \& step} (matrix);
  \draw[flow] (matrix) -- node[lbl, above=2pt] {outcome\\vectors} (op1);
  \draw[flow] (frame.east) -| node[lbl, pos=0.3, above] {decoder $Y = d(X, Z)$} (op3.north);
  \draw[flow] (op1) -- node[lbl, right=2pt] {certify / solve} (laws);
  \draw[flow] (op3) -- node[lbl, right=2pt] {narrowed $B_\omega(Z)$} (fibers);

  % Cross-coupling between Op 1 / Laws and Op 3
  \draw[flow] (laws.north east) -- node[lbl, sloped, pos=0.3, above] {solver library \& guards} (op3.south west);

  % Flows into Op 2 (S Compression)
  \draw[flow] (laws.south) |- node[lbl, pos=0.3, left] {quoted \texttt{:code}\\laws \& ASTs} (op2.west);
  \draw[flow] (fibers.south) -- node[lbl, sloped, pos=0.4, above] {pulled-back $B_\omega(Z)$} (op2.north east);

  % Flow from Op 2 to Op 4
  \draw[flow] (op2) -- node[lbl, below=4pt] {latent\\labels $j_\omega$\\\& search\\traces} (op4);

  % Feedback loops back to Frame / Search / Pullback
  \draw[feedback] (op2.north) -- ++(0, 1.6) -| node[lbl, pos=0.25, above] {lifted templates $p$, views \& child frames} (matrix.south);
  \draw[feedback] (op4.east) -| (10.2, 1.6) -| node[lbl, pos=0.25, above] {selectors $\hat{\pi}(X)$, search priors \& descriptors (3:1)} (frame.north);

\end{tikzpicture}%
}
\caption{Data flow and feedback loops connecting the Observation Frame $\Omega$, the resumable VM outcome matrix $M(e, \omega)$, and Operations 1--4 across \texttt{lisploop}.}
\end{figure}

---

### 2.1 Operation 1: Observational Conservation Across Frame Rows

As the enumerator generates well-typed expressions $e \in \mathcal{L}(\Gamma)$ in canonical order of increasing description length $S(e)$, the resumable VM evaluates the **Outcome Matrix**:
$$M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}.$$
Four milestone capabilities are direct instances of conservation laws on $M(e, \omega)$:

1. **Per-Row Requirement Satisfaction (M1 Core Synthesis)**:
   A single expression $e$ is a valid program for frame $\Omega$ if and only if it satisfies the unary conservation predicate across all rows with zero residual ($\varepsilon_\omega = 0$):
   $$\forall \omega \in \Omega,\quad M(e, \omega) \notin \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\} \;\land\; \mathrm{Eval}\bigl(A_\omega(Y),\, [Y \gets M(e, \omega)]\bigr) = \mathrm{t}.$$
   Among all satisfying expressions, search (`search-job` in `enumerate.lisp`) selects $e$ minimizing $J_{\mathrm{exact}}(e) = S(e) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(e)$.

2. **Cross-Row Observational Equivalence & Action Invariance (M2)**:
   - **Empirical Equivalence (`observation-bucket`)**: Two expressions $e_1, e_2$ belong to the same observational equivalence class on $\Omega$ (`observed-agreement-p`) if and only if they are total on $\Omega$ and produce identical row vectors:
     $$e_1 \sim_\Omega e_2 \iff \forall \omega \in \Omega,\quad M(e_1, \omega) = M(e_2, \omega) \notin \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}.$$
     Note that erroring expressions ($M(e, \omega) = \bot_{\mathrm{err}}$) never enter an equivalence bucket and never count as agreeing (`tests/observations.lisp`).When the frame grows from $\Omega$ to $\Omega' \supset \Omega$, equivalence buckets refine monotonically by partitioning each bucket on the new columns $\Omega' \setminus \Omega$ while preserving the original scope's snapshot unchanged.
   - **Action Invariance (`observation-invariants`)**: Given a state transition or symmetry action $T$ represented by paired before/after rows $(\omega, T\omega)$ (`pairs`) and cross-orbit reference rows (`anchors`), an expression $e$ is an **informative invariant** if and only if it is conserved along every trajectory step while varying across distinct orbits:
     $$\bigl(\forall (\omega, T\omega) \in \mathrm{pairs},\; M(e, \omega) = M(e, T\omega)\bigr) \;\land\; \bigl(\exists (\omega_1, \omega_2) \in \mathrm{anchors},\; M(e, \omega_1) \neq M(e, \omega_2)\bigr).$$

3. **Exhaustive Finite-Domain Law Certification (M3A)**:
   When the frame covers the entire finite input grid $\Omega = D^\Gamma$ (`schema-enumerable-p` and `frame-covers-domain-p`), empirical equivalence $e_1 \sim_{D^\Gamma} e_2$ is promoted by `start-law-validation` / `resume-law-validation` (`laws.lisp`) from `:conjecture` to `:validated`, producing an immutable `law-certificate`. On infinite domains ($D = \texttt{:int}$) or proper subsets $\Omega \subsetneq D^\Gamma$, survival across $\Omega$ remains graded as `:conjecture`.

4. **Support Masks & Exact Guard Synthesis (M3A)**:
   When a candidate equation $e_1 = e_2$ (or a partial expression $e$ inside an observation job with `:retain-outcomes t`) succeeds on a non-empty proper subset of rows $\Omega_{\mathrm{ok}} \subsetneq \Omega$ and fails or errors (`:error`) on $\Omega \setminus \Omega_{\mathrm{ok}}$, `observed-support` and `support-frame` (`laws.lisp`) project the row outcomes onto a Boolean indicator frame $\Omega_{\mathrm{guard}}$ with target requirement:
   $$A^{\mathrm{guard}}_\omega(G) \equiv \bigl(G = \mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)\bigr).$$
   Running standard synthesis (Op 1.1) on $\Omega_{\mathrm{guard}}$ with **zero residual ($\varepsilon_\omega = 0$)** synthesizes the exact domain-validity guard $G(X)$ (`propose-guard-problems`, `start-guard-search`), yielding the guarded law $G(X) \implies e_1(X) = e_2(X)$ (`propose-guarded-laws`).

---

### 2.2 Operation 2: Factorization & Latent Fiber Inference ($S$ Compression)

Factorization reduces total description length $S$ by splitting a collection of witnessed objects $\{t_\omega\}_{\omega \in \Omega}$ into a **shared reusable structure $p$** (paid once in the model header/template) and **per-instance residuals $\{\theta_\omega\}_{\omega \in \Omega}$** such that a deterministic reconstruction operator `Apply` recovers each target exactly:
$$\mathrm{Apply}(p, \theta_\omega) = t_\omega \quad (\forall \omega \in \Omega), \qquad S(p) + \sum_{\omega \in \Omega} S(\theta_\omega) < \sum_{\omega \in \Omega} S(t_\omega).$$
Operation 2 instantiates `Apply` across three algebras:

1. **Term Algebra ($\mathrm{Apply} = \mathrm{Subst}$ — M1, M3B, M4, M6)**:
   - **Aligned Anti-Unification (`anti-unify` in `factor.lisp`)**: Given typed S-expressions $t_1, \dots, t_N$ (which may be object-language programs, quoted `:code` laws in M3B/M4, or data trees in M6), `anti-unify` computes the least general generalization (LGG) template $p$ containing typed value holes `(hole i type :kind :value)` (`#:?0, #:?1, ...`) and operator holes `(hole i sig :kind :fn)` (when applications share arity and argument/return signature `(arg-types . return-type)`), together with per-row substitution bindings $\theta_\omega$. Repeated subterms across all rows are bound to the **same hole ID** via a shared residual-signature table (`au-state`), enforcing structural equality constraints such as `(?op ?x ?x)` on `(+ '2 '2)` and `(* '3 '3)`. Calling `compile-au-constructor` lowers $p$ into a first-class typed lambda constructor so `au-substitutions-frame` reduces residual synthesis to standard child-frame search.
   - **Unaligned Subgraph Correspondence Search (`discover-subexpression-abstractions` in `factor.lisp` — M6)**: When a shared pattern $p$ occurs at **varying paths** $\pi_\omega$ inside larger trees $T_\omega = W_\omega\bigl[\pi_\omega \gets \mathrm{Subst}(p, \theta_\omega)\bigr]$, `collect-tree-occurrences` indexes all non-leaf subterms, seeds candidate patterns by anti-unifying pairs of compatible subtrees, and greedily extends occurrence sets across the remaining trees to maximize `occurrence-saved-bits` under the spliced pre-order packet codec (`corpus-abstraction-model`).

2. **Sequence & Table Algebra ($\mathrm{Apply} = \mathrm{Gather}$ or $\mathrm{Reassemble}$ — M1, M7)**:
   - **Quotient View (`quotient-values`, `restore-quotient`, `quotient-model`)**: Factors a value sequence $\{t_\omega\}_{\omega=0}^{N-1}$ into a deduplicated representative table $R = (r_0, \dots, r_{K-1})$ and an index sequence $j_\omega \in \{0, \dots, K-1\}$ such that $t_\omega = \mathrm{gather}(R, j_\omega)$.
   - **Partition View (`partition-rows`, `reassemble-partition`, `partition-model`)**: Factors an observation frame $\Omega$ into regime sub-frames $\Omega_0, \dots, \Omega_{K-1}$ while retaining explicit occurrence coordinates so `reassemble-partition` reconstructs the exact original ordered sequence with ties and multiplicity.

3. **Pulled-Back Requirement Algebra ($\mathrm{Apply} = \text{Hard-EM Fiber Intersection}$ — M5)**:
   When a parent requirement $A_\omega(Y)$ is pulled back through a decoder $Y = d(X, Z)$ to yield per-row child requirements $B_\omega(Z)$ on $\omega \in \Omega$, each row $\omega$ defines an **admissible fiber** in the child target space $\mathcal{V}_{\tau_C}$:
   $$\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}.$$
   Unsupervised concept lifting (`infer-fibers` in `factor.lisp`) seeks a partition of the row set $\Omega = \bigsqcup_{k=0}^{K-1} \Omega_k$ (via latent row labels $j_\omega \in \{0, \dots, K-1\}$) and a shared concept requirement $B_{c_k}(Z)$ for each block $\Omega_k$ such that:
   $$B_{c_k}(Z) \equiv \bigwedge_{\omega \in \Omega_k} B_\omega(Z) \neq \texttt{'nil} \iff \bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset.$$
   Because fiber intersection is non-associative with respect to greedy merging (for example, on the 4-row bridge-vs-leaf configuration $\mathrm{Fiber}(\omega_1)=\{1,2\}$, $\mathrm{Fiber}(\omega_2)=\{2,3\}$, $\mathrm{Fiber}(\omega_3)=\{1,4\}$, $\mathrm{Fiber}(\omega_4)=\{3,5\}$, greedily merging $\omega_1$ and $\omega_2$ on the bridge value $Z=2$ strands $\omega_3$ and $\omega_4$ into $K=3$ clusters, whereas the global optimum is $K=2$ with $\{\omega_1,\omega_3\} \mapsto Z=1$ and $\{\omega_2,\omega_4\} \mapsto Z=3$), `infer-fibers` executes a **host-bias-free MDL partition search**:
   - **Stage A (Same-Input Determinism & Conflict-Free Projection Search)**: `tighten-same-input-requirements` intersects requirements across rows sharing identical `row-known` $\mathbf{x}_\omega$, and—on multi-input frames with unrepeated full `row-known` tuples—evaluates candidate single-coordinate projections $X_r$ in the metered VM, adopting the minimum-bit conflict-free projection (`conjoin-requirements` $\neq \texttt{'nil}$).
   - **Stage B (Bounded Branch-and-Bound Lexicographic MDL Partitioning)**: After deduplicating satisfiable rows with identical requirements into unique groups $G_0, \dots, G_{U-1}$ (ordered with constrained groups before unconstrained `'t` groups, then by ascending requirement `body-size`), `infer-fibers` searches over compatible group partitions using `conjoin-requirements` to minimize cluster count $K$, breaking ties by minimum total description bits $\sum_{k=0}^{K-1} |\Omega_k|\, S_{\mathrm{body}}(B_{c_k})$ and minimum empirical label entropy (maximizing $\sum_k |\Omega_k|^2$).
   - **Stage C (Computed Intra-Fiber `pairs` & Cross-Fiber `anchors`)**: From the optimal partition $\Omega = \bigsqcup_{k=0}^{K-1} \Omega_k$, `infer-fibers` (and `fiber-pairs-and-anchors`) calls `partition-pairs-and-anchors` to attach the computed intra-fiber must-agree `pairs` and cross-fiber must-vary `anchors` directly onto the returned `refined-frame`.

---

### 2.3 Operation 3: Causal Reorientation, Contravariant Pullback, Closed-Subtree Constant Folding & Dual-Grade Propagation

Whereas forward evaluation pushes known inputs $\mathbf{x}_\omega$ forward through an expression $e$ to produce outputs, hierarchical synthesis and algebraic reasoning move **contravariantly** from parent requirements to child subproblems:

1. **Causal Reorientation (`orient-observations` in `frame.lisp`, `orient-arithmetic-requirements` in `laws.lisp` — M1, M2, M4)**:
   Given recorded relational observations $(v_{\omega,0}, \dots, v_{\omega,k-1})$ (stored in `observation-scope` or forward execution tables), reorientation selects any subset of coordinates as the new known input vector $\mathbf{x}'_\omega$ and projects the remaining coordinates into the new target requirement $A'_\omega(Y)$—charging `:orientation` work and **zero `:simulation` work**. When multiple recorded tuples share the same projected input $\mathbf{x}'_\omega$ (as in non-injective operations like $0 \cdot Z = 0$ or integer division), `orient-arithmetic-requirements` preserves the exact relational predicate $R_f(K, Z, C)$ rather than collapsing or dropping witnesses.

2. **Contravariant Pullback & Closed-Subtree Constant Folding (`pullback-frame` & `fold-constants` in `frame.lisp` — M1, M3C, M4, M5, M7, M8)**:
   Given a parent frame $\Omega_P$ with row requirements $A_\omega(Y)$ ($Y : \tau_P$) and a candidate outer decoder $Y = d(X, Z)$ where $Z : \tau_C$ is the unknown child variable, pulling $\Omega_P$ back along $d$ substitutes the row's known input values $X \gets \mathbf{x}_\omega$ into $A_\omega(d(X, Z))$ and simplifies the resulting predicate via `fold-constants`:
   $$B_\omega(Z) := \mathrm{FoldConstants}\Bigl(A_\omega\bigl(d(\mathbf{x}_\omega, Z)\bigr)\Bigr).$$
   Specifically, `fold-constants`:
   - Evaluates every closed ($Z$-free) subexpression once in the metered VM (charging `:orientation` work) and replaces it with its literal value `'v` (leaving any expression that raises a runtime error unfolded so error semantics are preserved);
   - Simplifies Boolean connectives `(if 't a b) -> a`, `(if 'nil a b) -> b`, `(if c 'nil 'nil) -> 'nil`, reflexivity `(= e e) -> 't`, distinct literals `(= 'u 'v) -> 'nil`, and set membership `(member 'v '(...))`;
   - Decomposes tuple equality by constructor injectivity:
     $$\bigl(\texttt{= (tuple } e_1 \dots e_m\texttt{) '}(v_1 \dots v_m)\bigr) \xrightarrow{\mathrm{FoldConstants}} \bigwedge_{i=1}^m (\texttt{= } e_i\;\texttt{'}v_i),$$
     and normalizes singleton memberships `(member Z '(v))` into `(= Z 'v)`.

3. **Immediate Structural & Cross-Row Conflict Detection (`frame-conflict-p` in `frame.lisp` — M5, M7, M8C)**:
   Immediately after `pullback-frame` and `fold-constants` (before any child candidate enumeration begins), `frame-conflict-p` inspects the pulled-back child frame $\Omega_C$:
   - **Row-Level Structural Conflict (`:unsatisfiable-row`)**: If any row $\omega \in \Omega_C$ folds to `B_\omega(Z) = 'nil` (for example, pulling `(= Y '(2 3))` back through the diagonal decoder $d(Z) = \texttt{(tuple } Z\; Z\texttt{)}$ folds via tuple injectivity to `(if (= Z '2) (= Z '3) 'nil)` $\to$ `'nil` when $Z$ is further constrained, or when a constant branch mismatches `'2 != '3`), the decoder $d$ is rejected in $O(1)$ work.
   - **Cross-Row Context/Partition Conflict (`:incompatible-rows`)**: Grouping rows by identical child input vector $\mathbf{x}_\omega$ (`row-known`), if two rows $\omega_1, \omega_2$ share the same child inputs $\mathbf{x}_{\omega_1} = \mathbf{x}_{\omega_2}$ (e.g., because a candidate view split or restricted child signature dropped a distinguishing coordinate $r$) and their requirements conjoin via `conjoin-requirements` to `'nil` ($\mathrm{Fiber}(\omega_1) \cap \mathrm{Fiber}(\omega_2) = \emptyset$), `frame-conflict-p` returns `(values t :incompatible-rows keys)` and prunes the invalid split or decomposition immediately.

4. **Dual-Grade Downward Algebraic Propagation (`propagate-arithmetic-child` & `propagation-search` in `laws.lisp` — M4, M5, M7, M8)**:
   When $B_\omega(Z)$ still contains an unsimplified operator application `(= (op K Z) 'c)` or `(= (op Z K) 'c)` (with known constant $K = k_\omega$ after `fold-constants`), the structural `:code-*` matcher (`compile-propagator-matcher`, `match-arithmetic-propagator`) matches the decoder against the learned `propagator-library`. Each `arithmetic-solver` in the library is synthesized by `discover-arithmetic-solver` and graded by `validate-arithmetic-solver` via two separate implications over $(K, C, Z)$:
   - **Witness Law ($\Leftarrow$)**: $G(K, C) \implies R_f\bigl(K,\, q(K, C),\, C\bigr)$ (does $z_\omega = q(k_\omega, c_\omega)$ satisfy the forward relation when guard $G(k_\omega, c_\omega)$ holds?).
   - **Uniqueness Law ($\implies$)**: $\bigl(G(K, C) \land R_f(K, Z, C)\bigr) \implies Z = q(K, C)$ (is $q(k_\omega, c_\omega)$ the **unique** solution in $\mathcal{V}_{\tau_C}$?).

   Downward propagation then acts according to the solver's epistemic grade:
   - **Grade 1 — Certified Equivalence ($\iff$, e.g., $\mathbb{F}_p$ addition, subtraction, and nonzero multiplication/division)**: Both the witness law ($\Leftarrow$) and uniqueness law ($\implies$) have status `:validated` across the full finite domain $D^\Gamma$. Whenever $G(k_\omega, c_\omega) = \mathrm{t}$ and $q(k_\omega, c_\omega) = v_\omega$ passes forward verification $B_\omega(v_\omega) = \mathrm{t}$, `propagate-arithmetic-child` replaces $B_\omega(Z)$ **in-place** in the primary child frame with the direct equality `(= Z 'v_w)` (`propagation-certified-p = t`, `propagation-fallback = nil`). On rows where $G(k_\omega, c_\omega) = \mathrm{nil}$ (such as $0 \cdot Z = 0$, where $\mathrm{Fiber}(\omega) = \mathbb{F}_p$, or $0 \cdot Z = 1$, where $\mathrm{Fiber}(\omega) = \emptyset$), $B_\omega(Z)$ is left untouched as an exact predicate.
   - **Grade 2 — Tentative Witness ($\Leftarrow$, e.g., $\mathbb{Z}$ arithmetic where sample validation yields `:conjecture`, or truncating integer division where uniqueness is `:refuted` because $Z / 2 = 1$ admits $\{2, 3\}$)**: When $G(k_\omega, c_\omega) = \mathrm{t}$ and the proposed value $v_\omega = q(k_\omega, c_\omega)$ passes row-level forward verification $B_\omega(v_\omega) = \mathrm{t}$, `propagate-arithmetic-child` places `(= Z 'v_w)` into the narrowed primary frame (`propagation-frame`) while **retaining the un-narrowed pulled-back frame** as `propagation-fallback`. `propagation-search` then interleaves **3 work quanta on `:primary` for every 1 quantum on `:fallback`** (`(= 3 (mod turn 4))`), and forward-verifies every candidate child expression found on `:primary` against `propagation-original` before accepting it. Thus, even when a tentative singleton choice on two coupled rows is mutually incompatible (e.g., row 1 has $Z / 2 = 1 \implies \text{witness } 2$ while row 2 with the same input has $Z / 3 = 1 \implies \text{witness } 3$, where only $Z = 3$ satisfies both), the 1-in-4 `:fallback` reserve still finds the valid shared child $Z = 3$.

---

### 2.4 Operation 4: Lossy Heuristic Condensation & Multi-Lane Search Control ($W$ Compression)

Operations 1–3 require lossless exactness ($\varepsilon_\omega = 0$) because an unverified error in an object-level program or law corrupts correctness. By contrast, **control heuristics**—which choose which partition branch to try, which occurrence pair or search continuation to expand next, or which library function to test first—cannot corrupt soundness provided every candidate solution is still checked by the authoritative verifier and a canonical reserve lane remains active.

`condense-heuristic` (`factor.lisp`) formulates heuristic learning as **lossy MDL table condensation**:
- Given a finite empirical table $F = \{(\mathbf{x}_{\omega_i}, w_i)\}_{i=0}^{N-1}$ mapping context features $\mathbf{x}_{\omega_i}$ (row inputs, subtree coordinates, or probe signatures) to target control labels or return estimates $w_i \in \mathcal{V}_\tau$, `condense-heuristic` enumerates compact candidate expressions $\hat{\pi} \in \mathcal{L}(\Gamma_{\mathrm{control}})$ and evaluates them against $F$.
- During training, each candidate $\hat{\pi}$ is scored by the full two-part code length plus runtime work:
  $$J_{\mathrm{heuristic}}(\hat{\pi}) = S(\hat{\pi}) + \underbrace{\sum_{i:\,\hat{\pi}(\mathbf{x}_{\omega_i}) \neq w_i} \Bigl(\mathrm{positive\text{-}bit\text{-}size}(i + 1) + \mathrm{value\text{-}bit\text{-}size}(w_i, \tau)\Bigr)}_{S(\varepsilon(\hat{\pi}, F))} + \lambda_{\mathrm{run}}\, W_{\mathrm{run}}(\hat{\pi}).$$
- **Dropping $\varepsilon$ at deployment**: Once the minimizing expression $\hat{\pi}^*$ is selected (improving over the uncondensed `lookup-model` baseline), the exception table $\varepsilon(\hat{\pi}^*, F)$ is **discarded**. At deployment, only the compact symbolic program $\hat{\pi}^*(X)$ is evaluated in the metered VM, paired with the **1-in-4 canonical reserve schedule** (`(= 3 (mod turn 4))`).

Operation 4 powers three control loops across the milestones:
1. **Intensional Partition Selectors (M5, M7)**: After `infer-fibers` (M5) or `discover-partition-views` (M7) assigns latent regime indices $j_\omega \in \{0, \dots, K-1\}$ to rows $\omega \in \Omega$, `condense-heuristic` compresses the extensional label table $(\mathbf{x}_\omega \mapsto j_\omega)$ into an intensional selector program $\hat{\pi}(X)$ deployed at runtime without carrying the per-row lookup table.
2. **Locality & Continuation Return Predictors (M7, M8D)**: In M7 (`schedule-occurrence-pairs`), subtree occurrence pairs are prioritized by structural distance (`compute-tree-locality-positions`) or an induced `:locality-key` expression with a 1-in-4 canonical reserve. In M8D, logged episode continuation returns $G_t = B_t - B_T - \lambda_{\mathrm{search}}(W_T - W_t)$ are condensed via `condense-heuristic` into a symbolic value predictor $\hat{\pi}(\text{features})$ that prioritizes search continuations 3:1 over canonical enumeration.
3. **Compositional Library Descriptors (M9)**: Given a library of opaque function symbols (`F_0, F_1, ...`) accumulated across M1–M8, `condense-heuristic` synthesizes compact symbolic probe descriptors that rank which library primitives to test first on a new partial I/O frame.

---

## 3. Architecture of the 7-Module Homoiconic Kernel & Concrete Worked Examples

The entire `lisploop` kernel is organized into **7 core Lisp modules** (plus `package.lisp` and `fixtures.lisp`), totaling ~4,600 lines of implementation code:

| Module | Responsibility | Key Exported Primitives |
| :--- | :--- | :--- |
| `ast.lisp` | Ambient domains (`:int`, `(:gf p)`), semantic types, schemas $\Gamma$, pooled symbols (`*typed-symbol-pool*`), homoiconic AST constructors, $O(1)$ `*node-meta*`, 10-bucket `work` ledger, `message` envelope, `model` structs | `gf`, `tuple-type`, `sequence-type`, `code-type`, `make-schema`, `var`, `lit`, `op`, `app`, `hole`, `make-work`, `charge!`, `make-message` |
| `codec.lisp` | Encoding v7 prefix-free bit-vector serializer/deserializer, analytical `literal-range` inversion, $O(1)$ `body-size` / `description-size`, model codecs (`:lookup`, `:quotient`, `:partition`, `:corpus-abstraction`, `:au`) | `encode-model`, `decode-model`, `body-size`, `description-size`, `header-size`, `literal-range`, `value-bit-size` |
| `vm.lisp` | Single resumable debt-draining frame-stack evaluator (`evaluation`) for all arithmetic, tuple/sequence, `:lookup`, `:gather`, and `:code-*` symbolic operators; prepared program validation | `start-evaluation`, `advance-evaluation`, `evaluate`, `evaluation-error`, `prepare-program`, `execute-model` |
| `frame.lisp` | Observation frames $\Omega$ and rows $\omega$, requirement constructors, `orient-observations`, `pullback-frame`, `fold-constants`, `conjoin-requirements`, `frame-conflict-p`, `verify-model`, `evaluate-candidate` | `make-row`, `make-frame`, `value-requirement`, `set-requirement`, `orient-observations`, `pullback-frame`, `fold-constants`, `frame-conflict-p`, `verify-model` |
| `enumerate.lisp` | Grammar specification (`language`), canonical size-bounded bottom-up synthesis (`search-job`), empirical equivalence bucketing (`observation-job`, `observation-bucket`), action invariants (`observation-invariants`), checked-rule search | `make-language`, `start-search`, `resume-search`, `make-observation-scope`, `start-observation-search`, `resume-observation-search`, `observation-invariants` |
| `factor.lisp` | Term anti-unification (`anti-unify`, `compile-au-constructor`), subgraph correspondence search (`discover-subexpression-abstractions`), quotient/partition views, Hard-EM fiber clustering (`infer-fibers`), heuristic condensation (`condense-heuristic`), autonomous view & locality discovery (`discover-partition-views`, `schedule-occurrence-pairs`) | `anti-unify`, `match-pattern`, `instantiate`, `quotient-values`, `partition-rows`, `infer-fibers`, `condense-heuristic`, `discover-subexpression-abstractions`, `discover-partition-views`, `schedule-occurrence-pairs` |
| `laws.lisp` | Exhaustive finite-domain law validation (`law-certificate`), support masks & guard synthesis (`propose-guarded-laws`), AU law-corpus compression (`propose-law-compressions`), amortized symbolic rewriting (`prepare-rewrite-library`), algebraic solver discovery & dual-grade propagation (`propagate-arithmetic-child`, `propagation-search`) | `start-law-validation`, `propose-guarded-laws`, `propose-law-compressions`, `prepare-rewrite-library`, `discover-arithmetic-solver`, `validate-arithmetic-solver`, `propagate-arithmetic-child`, `propagation-search` |

### 3.1 Concrete Example 1: Homoiconic S-Expressions and $O(1)$ Prefix-Free Sizing

In `ast.lisp`, an expression such as $X_0 + (X_1 + X_1)$ over $\mathbb{F}_5$ is constructed via:
```lisp
(let* ((f5 (gf 5))
       (x0 (var 0 f5))
       (x1 (var 1 f5))
       (plus (op :+ f5))
       (expr (app plus x0 (app plus x1 x1))))
  ...)
```
At runtime, `expr` is the ordinary cons tree `(#:+ #:X0 (#:+ #:X1 #:X1))`, which prints, pattern-matches, and quotes natively in Lisp. Simultaneously, `app` attaches a `node-meta` entry in `*node-meta*` recording `:type (:gf 5)`, `:body-bits 21`, `:op-count 2`, and `:free-vars (0 1)`. When `expr` is wrapped as a quoted syntax value `(lit (code-type inputs f5) expr)` for M3B law compression, M3C symbolic rewriting, or M4 propagator matching, the exact same cons tree is passed as a first-class value of type `(:code ...)` with zero serialization overhead.

### 3.2 Concrete Example 2: Pullback, `fold-constants`, `frame-conflict-p`, and $\iff$ vs. $\Leftarrow$ Propagation

Consider a parent row $\omega$ with bound inputs $\mathbf{x}_\omega = (a_\omega, b_\omega) = (2, 3)$ and target requirement $A_\omega(Y) \equiv (\texttt{= } Y\;\texttt{'1})$. Suppose the parent proposes the outer decoder $Y = d(X_0, X_1, Z) = (X_0 + X_0) + Z$.
1. **Pullback + Constant Folding (`pullback-frame`)**: Substituting $X_0 \gets \texttt{'2}$ into $A_\omega(d(X, Z))$ yields `(= (+ (+ '2 '2) Z) '1)`. Because `(+ '2 '2)` contains no occurrence of the child target $Z = \texttt{(var 0 ...)}$, `fold-constants` evaluates `(+ '2 '2)` once in the VM (producing `'4` in $\mathbb{F}_5$ or `'4` in $\mathbb{Z}$) and simplifies the row requirement to:
   $$B_\omega(Z) \equiv (\texttt{= (+ '4 } Z\texttt{) '1})$$
   so child search never re-evaluates `(+ '2 '2)` on any candidate for $Z$.
2. **Immediate Conflict Pruning (`frame-conflict-p`)**: If instead a candidate decoder were $d(Z) = \texttt{(tuple } Z\; Z\texttt{)}$ against parent requirement `(= Y '(2 3))`, `fold-constants` decomposes the tuple equality by injectivity into `(if (= Z '2) (= Z '3) 'nil)`. If another constraint or constant branch fixes $Z$, or if two rows with identical child inputs simplify to `(= Z '2)` and `(= Z '3)`, `frame-conflict-p` immediately flags `:unsatisfiable-row` or `:incompatible-rows` in $O(|\Omega|)$ time before child enumeration starts.
3. **Downward Propagation (`propagate-arithmetic-child`)**:
   - In $\mathbb{F}_5$, the addition solver $q(K, C) = C - K$ has both witness ($\Leftarrow$) and uniqueness ($\implies$) laws `:validated` on $\mathbb{F}_5^2$. `propagate-arithmetic-child` evaluates $q(4, 1) \equiv 2 \pmod 5$, verifies $4 + 2 \equiv 1 \pmod 5$, and replaces $B_\omega(Z)$ **in-place** with `(= Z '2)`.
   - In $\mathbb{Z}$, the solver $q(K, C) = C - K$ has status `:conjecture` (tested on $[-4, 4]^2$). `propagate-arithmetic-child` evaluates $q(4, 1) = -3$, forward-verifies $4 + (-3) = 1$, places `(= Z '-3)` in `propagation-frame` (`:primary`), and retains `(= (+ '4 Z) '1)` in `propagation-fallback` (`:fallback`) for 3:1 interleaved search in `propagation-search`.

### 3.3 Concrete Example 3: Two-Stage Unsupervised Concept Lifting via `infer-fibers` and `condense-heuristic`

In Milestone 5 (`lifting-experiments.lisp`), observations of $y_{r,t} = a_{j(r)} + \iota(t)$ over $\mathbb{F}_7$ with unknown regime offsets $a_0 = 1, a_1 = 3$ and occurrence coordinate $r \in \{0, \dots, 2\cdot\text{reps}-1\}$ are pulled back through the decoder $d((r, t), Z) = \iota(t) + Z$:
1. **Stage 1 (`infer-fibers`)**: On each row $\omega = (r, t)$, pulling back $A_\omega(Y) \equiv (\texttt{= } Y\;\texttt{'}y_{r,t})$ and applying `fold-constants` (or M4 certified $\mathbb{F}_7$ addition propagation) yields $B_\omega(Z) \equiv (\texttt{= } Z\;\texttt{'}a_{j(r)})$. `infer-fibers` groups identical-input rows via `tighten-same-input-requirements`, detects that projecting onto coordinate $X_0 = r$ is conflict-free whereas projecting onto $X_1 = t$ has cross-row fiber conflicts ($1 \neq 3$), and runs branch-and-bound MDL partition search to recover the exact $K = 2$ fiber clusters $B_{c_0}(Z) \equiv (\texttt{= } Z\;\texttt{'1})$ and $B_{c_1}(Z) \equiv (\texttt{= } Z\;\texttt{'3})$ along with per-row labels $j_\omega \in \{0, 1\}$.
2. **Stage 2 (`condense-heuristic` vs. `context-label-frame`)**: The discovered labels $j_\omega$ can be deployed either extensionally via a paid `lookup-model` on $r$ (`context-label-frame`) or intensionally by calling `condense-heuristic` to synthesize a compact selector expression $\hat{\pi}(r, t)$ (with 0 residual bits when $j(r)$ is a clean predicate on $r$).

### 3.4 Concrete Example 4: Debt-Draining VM Preemption and 3:1 Interleaved `propagation-search`

When a candidate expression performs an expensive operation—such as multiplying $2^{128} + i$ by itself on row $\omega$—`advance-evaluation` in `vm.lisp` computes the instruction tariff $2 + 129 \times 129 = 16{,}643$ work units and adds the excess over the remaining step budget to `evaluation-debt`. Subsequent calls with `quantum = 1` decrement `evaluation-debt` by 1 per quantum and charge `:proposal-execution` (or `:checker`) until the debt reaches 0, only then pushing the product onto `evaluation-values`. Consequently, `propagation-search` can cleanly interleave 3 quanta on the narrowed `:primary` child job with 1 quantum on the un-narrowed `:fallback` job without ever losing sub-instruction work accounting or continuation parity.

---

## 4. The Nine Milestones: Specifications, Harmonized Mechanics, and Concrete Tests

Each milestone below is specified in the unified vocabulary of Section 1 and Section 2, followed by the exact experiments in `*-experiments.lisp` and the concrete `deftest` assertions in `tests/*.lisp`.

---

### 4.1 Milestone 1: Core Typed Synthesis, Resumable Preemption, Reorientation, Pullback, Views & Aligned AU Controls

#### Research Question & Mathematical Formulation
Can a single size-bounded bottom-up enumerator (`search-job`) over a typed S-expression grammar $\mathcal{L}(\Gamma)$ synthesize compact programs $e$ satisfying $\forall \omega \in \Omega,\; A_\omega(M(e, \omega)) = \mathrm{t}$ (Operation 1.1) such that:
1. $J_{\mathrm{exact}}(e) = S(e) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(e)$ strictly beats both a packaged `lookup-model` table and a literal sequence packet on complete finite-field tables ($\mathbb{F}_5$) and generalizes to held-out $2^{256}$-scale inputs on unbounded integers ($\mathbb{Z}$);
2. Preemption and resumption at `quantum = 1` preserve exact continuation and work-ledger identity (`equalp`) with batch execution; and
3. Causal reorientation (`orient-observations`), contravariant pullback (`pullback-frame`), sequence factoring (`quotient-values`, `partition-rows`), and aligned anti-unification (`anti-unify`) operate on the exact same `frame` and AST representations without side-channel leakage?

#### Kernel Mechanics & Controls
- **Bottom-Up Size-Partitioned Enumeration (`enumerate.lisp`)**: `search-job` maintains a dynamic-programming `table` of synthesized expressions indexed by `(type . body-bits)`, a `cursor` tracking the current bit-size tier and operator production, and a resumable `active-eval` continuation (`candidate-eval`) for the expression currently being checked across `frame-rows`.
- **Positive & Negative Controls**:
  - *Cutoff vs. Exhaustion vs. Extension*: At bit bound $B = 50$ with small budget (`work-limit = 100`), search returns `:cutoff`; with sufficient budget at $B = 50$, search returns `:exhausted` with 0 solutions; extending the bound to $B = 61$ on the 25-row $\mathbb{F}_5$ table for $y = a + 2b$ (`gf5-fixture`) recovers `(+ X0 (+ X1 X1))` at $S = 59$ bits ($S_{\mathrm{header}} = 38$, $S_{\mathrm{body}} = 21$, $W_{\mathrm{run}} = 1{,}375$), beating the packaged `lookup-model` ($S = 315$ bits, $W_{\mathrm{run}} = 28{,}750$) and the raw literal sequence ($S = 103$ bits).
  - *Contradictory Same-Input Control*: A frame containing two rows with identical `row-known` `(1 1)` and conflicting requirements `(= Y '0)` and `(= Y '1)` must return `:exhausted` with 0 solutions and reject `lookup-model` construction.
  - *Supplied Pullback Control*: Pulling the 25-row $\mathbb{F}_5$ frame for $y = a + 2b$ back through the supplied outer decoder $d(X_0, Z) = X_0 + Z$ where the child schema exposes only $X_1$ (`b`) synthesizes the child program `(+ X1 X1)` and composes it into `(+ X0 (+ X1 X1))`.
  - *Integer Generalization Control*: On `integer-linear-fixture` ($y = a + 2b$ over $[-2, 2]^2 \subset \mathbb{Z}^2$, 25 rows) with unrestricted integer literals, search recovers `(+ X0 (+ X1 X1))` ($S = 44$ bits, $S_{\mathrm{header}} = 23$, $S_{\mathrm{body}} = 21$) and replays without error on 6 held-out signed starts around $\pm 2^{256}$ (`integer-held-out-starts`).

#### Concrete Experiments & Test Suite (`experiments.lisp` `run-m1`, `tests/core.lisp`, `tests/codec.lisp`)
- **Experiment Runner (`run-m1` in `experiments.lisp`)**: Executes the 7-row $\mathbb{F}_5$ and `:int` experimental matrix (`:cutoff-50`, `:exhausted-50`, `:extended-61` at $(\lambda_{\mathrm{run}}, \lambda_{\mathrm{search}}) = (0, 0)$ and $(1/100, 1/1000)$, `:contradiction`, `:pullback`, and `:int-linear-45` with $2^{256}$ held-out replay) plus `verify-m1-controls`.
- **Authoritative Tests in `tests/core.lisp` (14 `deftest`s)**:
  1. `domains-codec-and-runtime`: Verifies $\mathbb{F}_5$ modular arithmetic and multiplicative inverses (`gf-invert`), rejects composite modulus `(gf 4)`, rejects retired `:index` types, rejects reader macros (`#.`) and trailing tokens in `read-program-string`, verifies no host closures or `:fetch` ops exist, and checks that stepping $(2^{160})^2$ with small work budgets matches batch evaluation and charges more work than `2 * 3`.
  2. `integer-positions-and-bounds`: Tests `:gather` bounds checking on negative indices, exact length boundary, $2^{256}$ indices, and empty sequences; verifies `:lookup` feeding `:gather`; verifies `quantum = 1` vs. batch work parity on `quotient-model` execution (including prepaid bounds-check work before erroring on index 99).
  3. `isolated-reorientation-and-model-data`: Reorients a 5-row $\mathbb{F}_5$ ternary table $(a, b, c = a + 2b)$ to predict $b$ from $(a, c)$ via `orient-observations` with zero `:simulation` charges; verifies `lookup-model` roundtrips through `encode-model`/`decode-model` and executes after `frame` and `records` are nilled out; verifies undeclared variable `(var 99)` and contradictory/disallowed `lookup-model` tables raise errors; verifies overlapping `set-requirement` rows `'(1 2)` and `'(2 3)` on the same key select the shared witness `2`.
  4. `joint-pullback-and-composition`: Verifies `pullback-frame` on correlated tuple sets `'((0 0) (1 1))` over $\mathbb{F}_2^2$; checks that diagonal decoder `(tuple Z Z)` accepts $Z \in \{0, 1\}$ on `'((0 0) (1 1))` and rejects all $Z$ on anti-diagonal `'((0 1) (1 0))`; verifies `pullback-frame` matches an explicit fiber-set oracle across all 25 rows of $\mathbb{F}_5^2$ for $d(X_0, Z) = X_0 + Z$; verifies non-injective pullback $X_0 \cdot Z = y$ on $X_0 = 0$ accepts all 5 field elements when $y = 0$ and 0 elements when $y = 1$.
  5. `views-preserve-occurrences`: Tests `partition-rows`, `reassemble-partition`, and `partition-model` on a 6-row parity-split frame, and tests `quotient-values`, `restore-quotient`, and `quotient-model` on `'(8 2 8 2 9 8)`.
  6. `syntax-replay-matching-and-au`: Tests `instantiate`, `match-pattern`, and `anti-unify` on `(+ '2 '2)` and `(* '3 '3)` (recovering operator hole + single repeated value hole `(?op ?x ?x)`), on `(+ '2 '2)` and `(* '3 '4)` (breaking the repeated hole into 3 holes), and on cross-type `(= '1 '1)` in `:int` vs. `(:gf 5)` (collapsing to a single `:bool` root hole).
  7. `exhaustive-tiny-aligned-au-reference`: Exhaustively compares `anti-unify` against an independent flat reference `reference-flat-au` across all pairs of depth-1 binary expressions over $\mathbb{F}_2$ (`:+`, `:*`, vars `X0, X1`, literals `'0, '1`).
  8. `independent-complete-tiny-bound`: Compares `start-search` / `resume-search` against an independent brute-force enumerator `reference-one-application` over $\mathbb{F}_2$ ($y = a + b$), verifying identical candidate count (8) and bit sizes.
  9. `integer-payload-bounds-and-contradiction`: Verifies that synthesizing the negative literal `'-12` succeeds at exact bit bound `description-size` and fails 1 bit below, and checks contradictory integer row rejection.
  10. `resume-reaches-planted-program`: Runs the 25-row $\mathbb{F}_5$ $y = a + 2b$ search with `quantum = 1` (457 resumptions) and verifies `equalp` work ledgers and identical synthesized AST `(+ X0 (+ X1 X1))` against batch execution.
  11. `checker-interruption-is-unresolved`: Interrupts evaluation mid-checker (`budget = 1` vs. `budget = 2`) and verifies the candidate is neither accepted nor discarded until the checker finishes.
  12. `batched-search-preserves-continuations-and-costs`: Asserts step-by-step `equalp` identity of `(search-job-work, search-job-cursor, search-job-proposals, candidate-eval-state)` between `quantum = 1` and `quantum = 7` across 200 steps on $\mathbb{F}_5$.
  13. `batched-checker-debt-and-errors`: Tests heavy checker debt (`(= Y (* '2^128 '2^128))`) and mid-checker division-by-zero (`(/ '1 '0)`) at `quantum = 1` vs. batch, verifying exact `equalp` state and ledger parity.
  14. `unpaid-instruction-error-after-batched-work`: Verifies that an out-of-bounds `:gather` index of $2^{256}$ must drain its full 261-unit prepaid bounds-check debt before signaling `evaluation-error`, with exact `quantum = 1` vs. batch parity.
- **Authoritative Tests in `tests/codec.lisp` (5 `deftest`s)**:
  1. `codec-roundtrip-and-boundaries`: Tests Encoding v7 bit-vector roundtrips across scalars, tuples, sequences, lookups, and holes; verifies rejection of empty packets, wrong version tags, reserved node tags (`#b11` without hole context), trailing padding bits, truncated packets, and unbound variable indices.
  2. `codec-enumerator-complete-tiny-grammars`: Verifies 1-to-1 correspondence between all expressions enumerated by `search-job` and valid roundtripping bit packets over $\mathbb{F}_5$ and `:int`.
  3. `codec-literal-ranges-and-vocabulary`: Verifies analytical `literal-range` inversion against actual `body-size` across all integer literals in $[-511, 511]$ and bit bounds $0 \dots 24$.
  4. `structural-tariff-and-print-independence`: Verifies that binding `*print-base* = 16`, `*print-radix* = t`, and `*print-pretty* = t` has zero effect on `description-size`, `encode-model`, or VM execution tariffs.
  5. `schema-header-does-not-add-enumeration-work`: Proves that renaming input variable IDs from `(0, 1)` to `(1000, 2000)` changes `header-size` (paid once in the schema header) while leaving `body-size`, candidate enumeration order, and `:enumeration` work completely invariant.

---

### 4.2 Milestone 2: Observational Equivalence, Action Invariants & Scoped Replay

#### Research Question & Mathematical Formulation
Can the system group enumerated expressions $e \in \mathcal{L}(\Gamma)$ by their empirical outcome vectors $M(e, \omega)_{\omega \in \Omega}$ into observational equivalence classes (`observation-bucket`s, Operation 1.2) so that:
1. Under a state transition action $T : \mathcal{S} \to \mathcal{S}$ observed through trajectory step pairs $(\omega, T\omega)$ and cross-orbit anchors, `observation-invariants` isolates informative conservation laws ($M(e, \omega) = M(e, T\omega)$ on `pairs` and non-constant on `anchors`) without a supervised target column;
2. Discovered invariants replay on fresh held-out transition pairs (including $2^{256}$ cancellation starts in $\mathbb{Z}$) and reject nearby non-invariant transitions; and
3. Accidental empirical agreements (such as $X_0 = X_0^2$ on $\{0, 1\}$) split cleanly when discriminating inputs are added, while preserving the original scope's snapshot unchanged?

#### Kernel Mechanics & Controls
- **Scoped Observational Bucketing (`observation-scope`, `observation-job` in `enumerate.lisp`)**: `start-observation-search` / `resume-observation-search` enumerates well-typed expressions up to `size-limit` and evaluates each expression across all rows of `observation-scope`. Only expressions that complete on every row without `evaluation-error` or cutoff are inserted into `observation-bucket`s keyed by `(type . values)`. Every bucket retains **all** member syntax trees (`observation-bucket-expressions`) ordered by description size, selecting the shortest expression as the canonical representative (`observation-bucket-representative`) without deleting alternatives.
- **Transition Reorientation Without Simulation (`transition-probes` in `experiments.lisp`)**: Converts recorded orbit trajectories into `pairs` and `anchors` frames by charging `:orientation` work and zero `:simulation` work.

#### Concrete Experiments & Test Suite (`experiments.lisp` `run-m2`, `tests/observations.lisp`, `tests/visualizer.lisp`)
- **Experiment Runner (`run-m2` in `experiments.lisp`)**:
  - *$\mathbb{F}_5$ Transition Invariant (`gf5-transition-fixture`)*: $T(a, b) = (a + 1, b + 4) \pmod 5$ across 2 orbits of 5 steps (20 transition probes, 1 anchor pair). At body limit 21 bits, `observation-job` evaluates 70 expressions into 29 buckets; `observation-invariants` isolates the **single** informative invariant bucket containing `(+ X0 X1)` and `(+ X1 X0)` (50 bits total, 21 body bits). Held-out replay passes on 6 fresh $+4$ shift pairs and fails on the negative control shift $+3$.
  - *Integer Transition Invariant (`integer-transition-fixture`)*: $T(a, b) = (a + 1, b - 1)$ over $\mathbb{Z}$ across 3 orbits of 3 steps (18 probes, 2 anchor pairs). At body limit 21 bits, 50 expressions form 35 buckets and isolate the single informative invariant bucket `(+ X0 X1)` / `(+ X1 X0)` (35 bits total). Held-out replay passes on 6 fresh pairs including $(2^{256}, -2^{256}) \mapsto (2^{256}+1, -2^{256}-1)$ and fails on negative control shift $-2$.
  - *Accidental-Agreement Split Controls (`run-split`)*: On $\{0, 1\}$, `X0` and `(* X0 X0)` share a bucket (`agree-01 = T`); adding `2` in $\mathbb{F}_5$ or `{-1, 2, 2^256, 2^256+1}` in $\mathbb{Z}$ splits the bucket (`agree-ext = NIL`) while keeping both `X0` and `(* X0 X0)` inside the original `{0, 1}` bucket.
- **Authoritative Tests in `tests/observations.lisp` (12 `deftest`s) & `tests/visualizer.lisp`**:
  1. `observations-discover-informative-invariant`: Exhaustively compares `observation-job` over $\mathbb{F}_5$ against `reference-one-application` (verifying 70 records, 29 buckets, and 1 informative invariant bucket `(+ X0 X1)` / `(+ X1 X0)`), and verifies that a single-orbit scope (`anchors = nil`) reports 0 informative invariants because constants cannot be separated from orbit invariants without cross-orbit anchors.
  2. `invariants-fresh-data-and-negative-transition`: Verifies held-out replay on fresh $\mathbb{F}_5$ pairs and rejection of nearby shift $+3$ and non-invariant `(- X0 X1)`.
  3. `empirical-buckets-split-on-more-data`: Verifies that `X0` and `(* X0 X0)` agree on $\{0, 1\}$, split on $\{0, 1, 2\}$, and leave the `{0, 1}` scope snapshot unmodified.
  4. `integer-observed-invariant-discovery-and-held-out-replay`: Compares `:int` observation discovery against `integer-reference-value`, verifies $2^{256}$ cancellation replay, and checks single-orbit rejection.
  5. `integer-accidental-agreement-and-exact-large-values`: Verifies `:int` bucket splitting across $\{0, 1\} \to \{-1, 0, 1, 2, 2^{256}, 2^{256}+1\}$ with exact bignum discrimination (`2^256` vs `2^256 + 1`).
  6. `observation-scope-types-and-occurrences`: Verifies deep-copy isolation against caller mutation of `frame-rows`, preservation of duplicate coordinate keys, cross-scope `observed-agreement-p` error signaling, and distinct buckets for `'0` in $\mathbb{F}_5$, $\mathbb{F}_7$, and `:int`.
  7. `declared-literal-vocabulary`: Verifies defensive copying of `language-literals` and checks that restricting literals to `'(0)` excludes nonzero constant buckets while still finding `(+ X0 X1)`.
  8. `observation-cutoffs-errors-and-replay-bounds`: Verifies that failing `:lookup` expressions get status `:error`, never enter any bucket, and never satisfy `observed-agreement-p` (even with themselves); checks `:cutoff` handling in `replay-invariant`.
  9. `observation-batching-and-resumption`: Asserts step-by-step `equalp` parity of `observation-job` states, buckets, and work ledgers between `quantum = 1` and `quantum = 9` over $\mathbb{F}_5$.
  10. `observation-error-and-large-instruction-batching`: Asserts `quantum = 1` vs. `quantum = 11` parity on $2^{128}$ integer multiplications and out-of-bounds `:gather` errors inside `observation-job`.
  11. `integer-observation-discovery-budget-parity`: Verifies that running `run-m2`'s integer invariant discovery at `quantum = 1` produces `equalp` records, buckets, and work ledgers to batch execution.
  12. `transition-reorientation-reuses-recorded-data`: Verifies that `transition-probes` charges `:orientation` work and 0 `:simulation` work.
  13. `tests/visualizer.lisp`: Verifies read-only JSON export (`frame-data`, `job-data`, `write-json`) preserving correlated tuple sets, $2^{256}$ bignum strings, HTML `</script>` escaping, Encoding v7 / Tariff v8 metadata, error diagnostics, and quoted `:code` syntax without mutating job state or charging work.

---

### 4.3 Milestone 3: Guarded Laws (3A), AU Law-Corpus Compression (3B) & Checked Symbolic Rewriting (3C)

#### Research Question & Mathematical Formulation
1. **Milestone 3A (Guarded Law Discovery & Certification)**: Can cross-row equivalences $e_1 \sim_\Omega e_2$ and partial-domain equations be paired with synthesized zero-residual Boolean guards $G(X)$ (`propose-guarded-laws`, Operation 1.3–1.4) and exhaustively validated on $\Omega = D^\Gamma$ to issue `law-certificate`s, while grading sample-only survivals on $\mathbb{Z}$ or subsets of $\mathbb{F}_p$ as `:conjecture` and refuting invalid domain transfers (such as $X_0^5 = X_0$ on $\mathbb{F}_7$ or $\mathbb{Z}$, and $2 \cdot (X_0 / 2) = X_0$ on $\mathbb{Z}$)?
2. **Milestone 3B (AU Law-Corpus Compression)**: When discovered laws are represented as first-class quoted syntax values `(lit (:code inputs :bool) (if G (= lhs rhs) 't))`, can Operation 2 (`propose-law-compressions`) compress the law corpus via aligned anti-unification templates and lowered constructor lambdas (`compile-au-constructor`), achieving significant bit savings over literal concatenation and dictionary storage while reconstructing every law AST identically and re-validating every decoded law?
3. **Milestone 3C (Symbolic VM & Checked Rewriting Amortization)**: Can rewrite rules be executed as ordinary DSL programs over `(:code inputs sort)` values using `:code-*` VM primitives, learned via contravariant pullback (`pullback-frame`), and pre-validated once in `prepare-rewrite-library` so repeated search runs amortize validation cost while preserving total/error semantics (`provably-total-p`)?

#### Kernel Mechanics & Controls
- **Joint Equation & Guard Discovery (`laws.lisp`)**: Running `start-observation-search` with `:retain-outcomes t` records per-row `row-outcome` values and errors (`:error`). `propose-guard-problems` extracts partial equivalence pairs $(e_1, e_2)$ that agree on a non-empty proper support $\Omega_{\mathrm{ok}} \subsetneq \Omega$ and have at least one error or disagreement outside $\Omega_{\mathrm{ok}}$; `support-frame` builds the indicator target $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$, `start-guard-search` synthesizes $G(X)$ with $\varepsilon_\omega = 0$, and `propose-guarded-laws` validates $G(X) \implies e_1(X) = e_2(X)$.
- **Totality & Error Preservation in Guarded Rewriting (`apply-guarded-rewrite`, `provably-total-p`)**: A guarded law $G(\sigma) \implies \ell(\sigma) = r(\sigma)$ may rewrite a subterm $\ell(\sigma)$ to $r(\sigma)$ inside an enclosing `(if cond then else)` **only** when the enclosing branch condition syntactically matches $G(\sigma)$ and every subterm erased by replacing $\ell(\sigma)$ with $r(\sigma)$ satisfies `provably-total-p` (no unguarded `:/`, `:lookup`, or `:gather`). Thus unsound rewrites such as `(* '0 (/ '1 '0)) -> '0` or `(- (/ '1 '0) (/ '1 '0)) -> '0` are rejected.
- **Amortized Rewrite Library (`prepare-rewrite-library` in `laws.lisp`)**: Validates each candidate rewrite rule exhaustively across $D^\Gamma$ (charging `:validation` work), checks `provably-total-p`, and caches the compiled `prepared-rewrite` in `*prepared-rewrite-cache*` only after the full validation budget is paid.

#### Concrete Experiments & Test Suite (`law-experiments.lisp` `run-m3`, `tests/laws.lisp`, `tests/guards.lisp`, `tests/compression.lisp`, `tests/symbolic.lisp`, `tests/amortization.lisp`)
- **Experiment Runner (`run-m3` in `law-experiments.lisp`)**:
  - **3A**: Exhaustive law discovery on $\mathbb{F}_5$ and $\mathbb{F}_7$ (`discover-field-laws`) certifying `(+ X0 '0) = X0` and `(+ X0 X1) = (+ X1 X0)`; domain-transfer control $X_0^5 = X_0$ (`:validated` on $\mathbb{F}_5$, `:refuted` at $X_0 = 2$ on $\mathbb{F}_7$ and $\mathbb{Z}$); joint partial-domain equation and guard discovery (`discover-guarded-field-laws`) discovering `(if (= X0 '0) 'nil 't) => (/ X0 X0) = '1` (`:validated` on $\mathbb{F}_5$ and $\mathbb{F}_7$, `:conjecture` on $\mathbb{Z}$ sample and `:validated` on bounded integer window $[-4, 4]$) and simplifying `(if (= X0 '0) '0 (/ X0 X0))` to `(if (= X0 '0) '0 '1)`.
  - **3B**: Compresses the jointly discovered guarded law corpora on $\mathbb{F}_5$ (2,306 laws, 180,828 raw bits) and $\mathbb{F}_7$ (6,229 laws, 513,294 raw bits) via `propose-law-compressions` and `start-search` on `law-corpus-frame` across $\lambda_{\mathrm{run}} \in \{0, 1, 100\}$, comparing 4 lossless models (`:literal-sequence`, `:whole-law-dictionary`, `:global-au`, `:shape-grouped-au`). Shape-grouped AU achieves **33.9% bit reduction on $\mathbb{F}_5$** (`180,828 -> 119,532` bits) and **28.7% bit reduction on $\mathbb{F}_7$** (`513,294 -> 366,184` bits), while `compile-au-constructor` (`report-quoted-au-constructor`) lowers the global AU template `(if ?0 (= ?1 ?2) 't)` into a verified `:code` constructor expression.
  - **3C**: `report-symbolic-transformation-search` pulls `code-transform-fixture` (`?t + 0 -> ?t` when `code-total`) back through a `:code-*` outer decoder to an `:int` child selector frame, synthesizes child index `'0`, and replays the composed symbolic transformer; compares plain vs. checked-rule search on $y = a + 2b$ (`report-search-comparison`), demonstrating one-time validation amortization across cold vs. warm runs.
- **Authoritative Tests**:
  - **`tests/laws.lisp` (11 `deftest`s)**:
    1. `division-subtraction-and-lazy-conditionals`: Tests `:-`, `:/`, `:=`, and lazy `:if` in $\mathbb{F}_5$, $\mathbb{F}_7$, and `:int` (verifying `(if (= X0 '0) '0 (/ X0 X0))` does not evaluate `(/ '0 '0)` when `X0 = 0`, and that non-Boolean `:if` conditions error).
    2. `conditional-and-division-resumption`: Asserts `quantum = 1` vs. `quantum = 5` state and ledger `equalp` parity across `:if` and `:/` evaluations (including $2^{256} / 3$).
    3. `mixed-type-enumeration-and-predicate-frames`: Verifies synthesis of Boolean predicate `(= X0 '0)` on mixed `:bool`/`:gf` grammars and checks that type-restricted grammars do not enumerate dead boolean subtrees.
    4. `laws-discovered-and-independently-validated`: Discovers and certifies identity, commutativity, and guarded self-division laws on $\mathbb{F}_5$ and $\mathbb{F}_7$, and verifies $X_0^5 = X_0$ domain specificity.
    5. `law-scope-counterexamples-and-cutoffs`: Tests all epistemic statuses (`:validated`, `:conjecture`, `:vacuous`, `:refuted`, `:cutoff`), verifies refutation of $X_0 / X_0 = 1$ at $X_0 = 0$, and checks that tampering with a `law-certificate` is rejected by `apply-guarded-rewrite`.
    6. `guarded-rewrites-preserve-errors-and-terminate`: Verifies that `(if (= X0 '0) '0 (/ X0 X0))` rewrites to `(if (= X0 '0) '0 '1)` while unguarded `(/ X0 X0)` is untouched, and that `(* '0 (/ '1 '0)) -> '0` and `(- (/ '1 '0) (/ '1 '0)) -> '0` are blocked by `provably-total-p`.
    7. `equality-constrained-search-keeps-alternatives-and-costs`: Verifies that checked-rule canonicalization records `:rewrite` work without deleting non-canonical alternatives when their objective cost is lower.
    8. `partial-terms-and-boolean-guards`: Verifies that `(if (/ '1 '0) X0 X0)` is not rewritten to `X0` because the condition is not provably total.
    9. `exhaustive-rewrite-preservation-on-tiny-grammar`: Exhaustively verifies that every rewrite performed by the validated $\mathbb{F}_5$ rewrite library preserves evaluation semantics (including `:error` behavior) across all expressions up to 24 body bits.
    10. `truncating-division-does-not-transfer-field-identities`: Verifies that $X_0 \neq 0 \implies X_0 / X_0 = 1$ holds on `:int` while the field identity $2 \cdot (X_0 / 2) = X_0$ is `:refuted` at $X_0 = 3$ under truncating integer division.
    11. `nested-mixed-type-enumeration-reference`: Compares mixed `:bool`/`(:gf 5)` enumeration against an independent recursive reference grammar up to 30 body bits.
  - **`tests/guards.lisp` (7 `deftest`s)**:
    1. `joint-field-guard-discovery-and-support-reference`: Verifies `observed-support` against a host arithmetic oracle across all candidate pairs on $\mathbb{F}_5$ and $\mathbb{F}_7$.
    2. `retained-row-outcomes-and-exact-support`: Verifies `:retain-outcomes t` captures exact per-row values and `:error` markers (`(/ X0 X0)` errors at `0` and equals `1` on `{1,2,3,4}`).
    3. `outcome-retention-budget-parity`: Asserts `quantum = 1` vs. `quantum = 7` `equalp` parity with `:retain-outcomes t`.
    4. `guard-residual-frame-and-occurrence-isolation`: Verifies `support-frame` preserves duplicate occurrence keys and isolates row mutations.
    5. `guard-discovery-resume-validation-and-rewriting`: Verifies resumable `start-guard-search` / `resume-guard-search` at `quantum = 1` vs. batch and end-to-end rewrite certification.
    6. `learned-guard-on-samples-is-not-a-certificate`: Demonstrates that $X_0^4 = 1$ with guard $X_0 \neq 0$ learned on the sample subset $\{0, 1, 6\} \subset \mathbb{F}_7$ gets status `:conjecture` (no certificate) and is `:refuted` at $X_0 = 2$ on the full domain $\mathbb{F}_7$.
    7. `multi-input-guards-and-unequal-values`: Synthesizes two-variable guard `(= X1 '0) -> nil` for `(X0 * X1) / X1 = X0` over $\mathbb{F}_5^2$.
  - **`tests/compression.lisp` (7 `deftest`s)**:
    1. `concatenation-codec-values-and-cutoffs`: Tests packet kind `2` (concatenation corpus) and kind `3` (AU template + substitutions) roundtrips, corruption rejection, and `quantum = 1` vs. batch decompression parity.
    2. `core-search-listed-proposals-and-objective`: Verifies that `start-search` on `law-corpus-frame` with `:listed-proposals` ranks the 4 compression models by $J(M) = S(M) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$ and switches the winner from `:shape-grouped-au` at $\lambda_{\mathrm{run}} = 0$ to `:literal-sequence` at $\lambda_{\mathrm{run}} = 100$.
    3. `au-law-repeated-expression-and-operator-holes`: Verifies that anti-unifying quoted laws `(+ e1 e1) = e1` and `(* e2 e2) = e2` extracts both an operator hole `#:?0` and a single repeated subexpression hole `#:?1`.
    4. `au-law-corpus-occurrences-isolation-and-type-boundaries`: Verifies preservation of duplicate laws in a corpus, input mutation isolation, and rejection of cross-domain ($\mathbb{F}_5$ vs. $\mathbb{F}_7$) corpus mixing.
    5. `compression-checks-syntax-including-guards-not-boolean-outputs`: Proves that `law-corpus-frame` checks exact quoted AST syntax (so replacing a law with a distinct tautology fails verification) and that losslessly compressing an unvalidated false law (`X0 / X0 = 1` with guard `'t`) does not fabricate a `law-certificate`.
    6. `au-compression-cutoffs-objective-and-negative-gain`: Verifies negative compression gain reporting on tiny 2-law corpora where template overhead exceeds savings.
    7. `au-compression-of-jointly-discovered-field-laws`: Verifies positive compression and full re-validation on the jointly discovered $\mathbb{F}_5$ guarded law corpus.
  - **`tests/symbolic.lisp` (8 `deftest`s)** & **`tests/amortization.lisp` (5 `deftest`s)**:
    1. `quoted-syntax-types-codec-and-no-evaluation`: Verifies `(:code ...)` values roundtrip through Encoding v7 without evaluating quoted `(/ X0 '0)` and that no `:eval`/`:funcall` operators exist.
    2. `symbolic-inspection-construction-and-failure-boundaries`: Tests `:code-kind`, `:code-child`, `:code-operator`, and `:code-apply` (including arity/type mismatch errors).
    3. `symbolic-matching-substitution-and-quotation-scope`: Tests `:code-match`, `:code-bind`, and `:code-subst`—verifying repeated-hole equality enforcement, simultaneous non-recursive substitution (swapping `X0 -> X1` and `X1 -> X0` in `(+ X0 X1)` yields `(+ X1 X0)` without re-substituting), and opacity across nested quote boundaries.
    4. `symbolic-au-lowers-operator-and-repeated-holes`: Verifies `compile-au-constructor` lowers templates with both `:fn` and `:value` holes into executable `:code-apply` programs.
    5. `symbolic-grammar-enumerates-and-snapshots-typed-constants`: Verifies enumeration of `:code-*` programs and snapshot isolation.
    6. `symbolic-pullback-learns-a-checked-transformation`: Pulls `code-transform-fixture` back through a `:code-*` outer decoder to an `:int` child index frame, discovers `'0`, and validates the composed rewrite rule.
    7. `symbolic-vm-continuations-cover-copying-and-errors`: Asserts `quantum = 1` vs. `quantum = 4` `equalp` parity across `:code-match` and `:code-subst`.
    8. `checked-rule-transformer-is-an-isolated-dsl-program`: Verifies that a compiled rule transformer executes after nilling out source fixtures.
    9. `prepared-program-validation-boundaries-and-isolation`, `prepared-execution-keeps-input-checks-errors-and-cutoffs`, `rewrite-preparation-publication-reuse-and-scope`, `rewrite-cache-budget-parity-across-multiple-rules`, `checked-search-amortizes-once-with-fresh-job-isolation` (`tests/amortization.lisp`): Verify `prepare-program`, cache publication only after full `:validation` payment, `quantum = 1` vs. batch cache parity, and one-time validation amortization across multiple search runs.

---

### 4.4 Milestone 4: Algebraic Relation Reorientation, Guarded Solver Discovery & Dual-Grade Propagation

#### Research Question & Mathematical Formulation
Can the system observe forward binary operations $f(a, b) = c$ for $+, -, \times, /$ over $\mathbb{F}_5$, $\mathbb{F}_7$, and $\mathbb{Z}$, reorient those forward records into left-operand ($f(Z, K) = C$) and right-operand ($f(K, Z) = C$) relational frames without enumerating inverse values in the host (`orient-arithmetic-requirements`), synthesize guarded witness solvers $q(K, C)$ and validity guards $G(K, C)$ (`discover-arithmetic-solver`), grade both witness ($\Leftarrow$) and uniqueness ($\implies$) implications (`validate-arithmetic-solver`), and deploy the resulting 8-rule `propagator-library` inside `propagate-arithmetic-child` and `propagation-search` (Operation 3.4)?

#### Kernel Mechanics & Controls
- **Forward Relation & Definedness Guard Synthesis (`observe-arithmetic-relation`)**: Executes $f(a, b)$ across the forward grid ($\mathbb{F}_p^2$ or $[-4, 4]^2 \subset \mathbb{Z}^2$), recording values and division-by-zero errors, and synthesizes the forward definedness guard (`b != 0` for `:/`, `'t` for `:+`, `:-`, `:*`).
- **Relational Reorientation Without Host Inverse Enumeration (`orient-arithmetic-requirements`)**: Reorients the forward records into target $Z$ given $(K, C)$ by retaining the forward relational requirement $R_f(K, Z, C)$ (conjoined across colliding $(K, C)$ rows via `conjoin-requirements`). Thus non-injective rows such as $0 \cdot Z = 0$ keep the full relational predicate `(= (* '0 Z) '0)` (satisfied by all $Z$), contradictory rows $0 \cdot Z = 1$ keep an unsatisfiable conjunction, and multi-valued integer division rows such as $Z / 2 = 1$ keep `(= (/ Z '2) '1)` (satisfied by $Z \in \{2, 3\}$).
- **Solver & Guard Synthesis (`discover-arithmetic-solver`)**: Searches for a witness expression $q(K, C)$ satisfying the reoriented rows on their solvable support, then synthesizes the exact solvability guard $G(K, C)$ via zero-residual guard search on the witness's support indicator—discovering `K != 0` for field multiplication/division and the self-composed divisibility guard `(if (= K '0) 'nil (= (* K (/ C K)) C))` for integer multiplication $K \cdot Z = C$.
- **Weak Addition Bootstrap (`:body-bound 24`)**: When solving $K + Z = C$ or $Z + K = C$ using a restricted grammar containing **only `:+` and `:*`** (no `:-` or `:/`), search discovers the additive inverse $C + (p - 1) \cdot K$ in $\mathbb{F}_p$ (`4 * K` in $\mathbb{F}_5$, `6 * K` in $\mathbb{F}_7$) and $C + (-1) \cdot K$ in $\mathbb{Z}$.
- **Certified ($\iff$) vs. Tentative ($\Leftarrow$) Propagation**: See Section 2.3 (Operation 3.4).

#### Concrete Experiments & Test Suite (`algebra-experiments.lisp` `run-m4`, `tests/algebra.lisp`, `tests/propagation.lisp`)
- **Experiment Runner (`run-m4` in `algebra-experiments.lisp`)**:
  - Discovers and validates all 8 oriented solvers (`:+`, `:-`, `:*`, `:/` $\times$ `:left`, `:right`) in $\mathbb{F}_5$ (`:validated` $\iff$), $\mathbb{F}_7$ (`:validated` $\iff$), and $\mathbb{Z}$ on $[-4, 4]^2$ (witness `:conjecture` $\Leftarrow$, with `:/` uniqueness `:refuted` at counterexamples $Z / 2 = 1$ and $4 / Z = 1$).
  - Runs the weak `+`/`*` addition bootstrap across $\mathbb{F}_5$, $\mathbb{F}_7$, and $\mathbb{Z}$ (with $2^{256}$ held-out verification).
  - Evaluates the expensive-context integer control $y = a^2 + g(b)$ with $a_i = 2^{128} + i$ and $g(b) = b^2 + 1$: tentative propagation evaluates $a_i^2$ once during `fold-constants`/`propagate-arithmetic-child` and narrows $B_\omega(Z)$ to `(= Z 'v_w)`, reducing total work to the first verified child solution by **79.3%** (`2,193,913 -> 454,724` work units).
  - Applies aligned AU (`anti-unify`) across the 8 guarded solver statements in each domain, recovering the shared guarded implication skeleton `(if ?0 (= ?1 ?2) 't)`.
- **Authoritative Tests in `tests/algebra.lisp` (8 `deftest`s) & `tests/propagation.lisp` (8 `deftest`s)**:
  1. `all-arithmetic-orientations-match-independent-field-reference`: Verifies all 16 solvers across $\mathbb{F}_5$ and $\mathbb{F}_7$ against an independent Euclid-free reference oracle (`independent-arithmetic`).
  2. `original-addition-bootstrap-and-separate-oracle`: Verifies the `+`/`*`-only addition bootstrap on $\mathbb{F}_5$, $\mathbb{F}_7$, and $\mathbb{Z}$ (including held-out inputs at $\pm 2^{256}$).
  3. `zero-empty-and-multivalued-fibers-remain-predicates`: Verifies that $0 \cdot Z = 0$ (5 solutions in $\mathbb{F}_5$) and $0 \cdot Z = 1$ (0 solutions) remain un-narrowed predicate rows during certified propagation, and set/predicate parent requirements are preserved.
  4. `certified-propagators-preserve-entire-field-child-frames`: Exhaustively verifies that for every operator and orientation over $\mathbb{F}_5$ and $\mathbb{F}_7$, the propagated child frame has the exact same admissible fiber $\mathrm{Fiber}(\omega)$ on every row and the exact same set of satisfying child programs as the unpropagated pulled-back frame.
  5. `integer-witnesses-divisibility-and-division-counterexamples`: Verifies `:int` solver grades (`:conjecture` for witnesses, `:refuted` for division uniqueness on $Z / 2 = 1$ and $4 / Z = 1$) and tests the integer multiplication divisibility guard at $C = 2(2^{128}+1)$ vs. $2(2^{128}+1)+1$.
  6. `solver-certificates-and-bounds-do-not-overclaim`: Verifies that sample-grid $\mathbb{F}_5$ discovery without full domain coverage cannot issue a `law-certificate` or set `propagation-certified-p`.
  7. `repeated-grid-occurrences-and-incomplete-forward-evidence`: Verifies duplicate key preservation and incomplete-grid handling.
  8. `au-reconstructs-the-actual-guarded-solver-families`: Verifies lossless AU roundtrip of all 8 guarded solver statements.
  9. `propagator-dsl-matching-and-library-isolation` (`tests/propagation.lisp`): Verifies `:code-*` matcher compilation caching, rejection of `(+ Z Z)` (where neither operand is $Z$-free), and library mutation isolation.
  10. `integer-proposals-check-original-forward-requirements`: Verifies that invalid tentative witness proposals are rejected row-by-row by forward verification $B_\omega(v_\omega)$ and fall back to the original row requirement.
  11. `tentative-failure-and-success-both-preserve-integer-alternatives`: Constructs a coupled 2-row integer child problem (`Z / 2 = 1` and `Z / 3 = 1` on the same input) where tentative singleton propagation picks $Z = 2$ on row 1 and $Z = 3$ on row 2 (making `:primary` unsatisfiable), and verifies that `propagation-search` recovers the valid shared solution $Z = 3$ via its 1-in-4 `:fallback` reserve.
  12. `propagation-search-resumption-and-bound-extension`: Asserts `quantum = 1` vs. `quantum = 7` `equalp` parity of `propagation-search` across bound extensions.
  13. `verified-integer-propagation-amortizes-expensive-forward-context`: Verifies the 79.3% search work reduction on $a_i = 2^{128} + i$.
  14. `constant-folding-and-conflict-detection`: Unit-tests `fold-constants` (closed $2^{128}$ subtree folding, tuple equality decomposition, singleton `:member` normalization) and `frame-conflict-p` (`:unsatisfiable-row` on `(tuple Z Z) = '(2 3)` and `:incompatible-rows` on conflicting same-input rows).
  15. `hard-em-infer-fibers-and-cannot-links`: Unit-tests `infer-fibers` on 2-cluster set requirements `{1, 2}`, `{2, 3}`, `{4, 5}` and incompatible-row conflict detection.
  16. `condense-heuristic-with-priced-residual`: Unit-tests `condense-heuristic` on a noisy parity table (7 clean rows + 1 corrupted exception row), verifying that training prices the 1-row residual to select `(mod X0 2)` and drops the residual table at deployment.

---

### 4.5 Milestone 5: Intermediate Concept Lifting via Supplied Contexts & Unsupervised Hard-EM Fiber Inference

#### Research Question & Mathematical Formulation
When a family of observations $y_{r,t} = d\bigl((r, t),\, a_{j(r)}\bigr)$ depends on an unobserved intermediate concept $Z = a_{j(r)}$ indexed by a latent regime $j(r) \in \{0, \dots, K-1\}$ across occurrences $r$ and inner index $t$:
1. Can pulling the parent frame $\Omega_P$ back through $Y = d((r, t), Z)$ (`pullback-frame`) and projecting onto a supplied regime coordinate $j(r)$ lift the child synthesis problem to $Z = g(j)$ so that total description bits $S(\text{composed})$ beat `lookup-model` and raw literal sequences as repetitions grow?
2. When no regime labels $j(r)$ are supplied, can **unsupervised Hard-EM fiber inference** (`infer-fibers`, Operation 2.3) intersect the pulled-back value fibers $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ across rows, avoid greedy bridge merges via branch-and-bound MDL search, recover the latent regime partition $\Omega = \bigsqcup_{k=0}^{K-1} \Omega_k$, and deploy the discovered labels via either a paid `lookup-model` (`context-label-frame`) or an intensional selector $\hat{\pi}(X)$ synthesized by `condense-heuristic` (Operation 4.1)?

#### Kernel Mechanics & Controls
- **Four-Part Experimental Architecture (`lifting-experiments.lisp`)**:
  1. *Supplied Context Lifting & Repetition Scaling (`run-m5-supplied-lift-and-repetitions`)*: On `gf7-lifting-fixture` ($y_{r,t} = a_{j(r)} + \iota(t) \pmod 7$ with $a_0 = 1, a_1 = 3$, $t \in \{0, \dots, 6\}$, metered conversion `gf7-iota-conversion`), pulling back through $d((r,t), Z) = \iota(t) + Z$ and projecting onto supplied $j \in \{0, 1\}$ synthesizes the child predictor $a_j = 1 + 2j$ (`(+ '1 (+ X2 X2))`) and composes it with the outer decoder. Across $\mathrm{reps} \in \{1, 2, 4, 8\}$ (14 to 112 rows), the lifted program size stays constant at **105 bits** while `lookup-model` grows from 249 to 1,689 bits and whole-sequence literal storage grows from 69 to 370 bits.
  2. *Contradictory $t$-Only Control & Scope Enforcement (`run-m5-contradictory-t-only-control`)*: Dropping the occurrence coordinate $r$ so the child sees only $t$ causes `frame-conflict-p` to flag `:incompatible-rows` on keys `((:seq 0 0) (:seq 1 0))` (since $t = 0$ requires both $Z = 1$ and $Z = 3$), and bounded search returns 0 solutions. Attempting to apply the map $r \to j$ when the parent frame lacks $r$ raises an immediate scope error; encoding $r \to j$ as a paid `lookup-model` over parent coordinate $r$ (`context-label-frame`) restores solvability.
  3. *Unsupervised Hard-EM Discovery & Dual Deployment (`run-m5-hard-em-discovery-and-deployment`)*: Starting from the unlabelled $(r, t)$ parent frame, `infer-fibers` recovers the exact $K = 2$ latent fiber classes (`(= Z '1)` and `(= Z '3)`) both directly on the raw pulled-back predicates and after M4 certified $\mathbb{F}_7$ addition propagation (which also eliminates repeated $\iota(t)$ evaluations during child search), while attaching computed intra-fiber `pairs` and cross-fiber `anchors` (`fiber-pairs-and-anchors`, `partition-pairs-and-anchors`) onto the returned `refined-frame`. Deploys the discovered labels via **Path A** (paid `lookup-model` over $r$) and **Path B** (`condense-heuristic` synthesizing an intensional selector $\hat{\pi}(r, t)$ with 0 residual bits).
  4. *Integer Lifting with Tentative Propagation (`run-m5-integer-lifting-and-tentative-propagation`)*: On `integer-lifting-fixture` ($y_{r,t} = a_{j(r)} + t$ over $\mathbb{Z}$ with $a_0 = 1, a_1 = 3$), combines M4 tentative integer propagation (`:conjecture`, 28 forward-verified row suggestions) with `infer-fibers`, `context-label-frame`, `propagation-search`, and `condense-heuristic`, replaying on held-out $2^{256}$ inputs.

#### Concrete Experiments & Test Suite (`lifting-experiments.lisp` `run-m5`, `tests/lifting.lisp`)
- **Authoritative Tests in `tests/lifting.lisp` (9 `deftest`s)**:
  1. `hard-em-bridge-vs-leaf-disambiguation`: Tests the 4-row bridge-vs-leaf trap ($\mathrm{Fiber}(\omega_1)=\{1,2\}$, $\mathrm{Fiber}(\omega_2)=\{2,3\}$, $\mathrm{Fiber}(\omega_3)=\{1,4\}$, $\mathrm{Fiber}(\omega_4)=\{3,5\}$) across 5 row permutations in both $\mathbb{F}_7$ and `:int`—verifying that `infer-fibers` avoids the greedy $Z = 2$ bridge merge ($K = 3$) and finds the globally optimal $K = 2$ partition ($\{1\}$ and $\{3\}$) on every permutation.
  2. `hard-em-same-input-must-link-and-conjunct-propagation`: Verifies that `tighten-same-input-requirements` intersects width-3 set requirements (`{1,2,3} \cap {1,4,5} = {1}`) on rows sharing identical `row-known` before clustering, and propagates conjunct equalities across relational pulled-back requirements in both $\mathbb{F}_7$ and `:int`.
  3. `hard-em-unconstrained-rows-and-context-affinity-refinement`: Verifies that when rows have unconstrained `'t` or ambiguous `{1, 3}` fibers alongside a distinguishing context coordinate $X_0 = r$ and a conflicting coordinate $X_1 = t$ (in both $\mathbb{F}_7$ and `:int`), `tighten-same-input-requirements` identifies the conflict-free projection $X_0$ and `condense-heuristic` directly synthesizes the regime selector over the underconstrained requirements without host affinity tables.
  4. `hard-em-relational-member-filtering-and-cannot-links`: Verifies that `fold-constants` normalizes 1-element `:member` to `:=`, filters `:member` sets against `:=` conjuncts, and preserves `:incompatible-rows` cannot-links when same-input rows have disjoint fibers.
  5. `hard-em-multi-regime-and-higher-arity-fibers`: Verifies `infer-fibers` on non-singleton $K = 2$ intersection fibers (`{1, 2}` and `{4, 5}`) and 3-regime ($K = 3$) disambiguation (`{1}`, `{3}`, `{5}`) across $\mathbb{F}_7$ and `:int`.
  6. `m5-supplied-lift-and-repetition-compression`: Verifies `run-m5-supplied-lift-and-repetitions` across $\mathrm{reps} \in \{1, 2, 4, 8\}$.
  7. `m5-contradictory-t-only-and-context-restoration`: Verifies `:incompatible-rows` conflict detection on $t$-only projection, missing-coordinate scope rejection, and restoration via `context-label-frame`.
  8. `m5-unsupervised-hard-em-discovery-and-selector-deployment`: Verifies exact label agreement between raw and M4-propagated `infer-fibers`, positive work savings from M4 propagation, and verified replay of both Path A (`lookup-model`) and Path B (`condense-heuristic`).
  9. `m5-integer-lifting-and-tentative-propagation`: Verifies end-to-end integer lifting with tentative `:conjecture` propagation and $2^{256}$ held-out replay.

---

### 4.6 Milestone 6: Typed Anti-Unification, Subexpression Correspondence Search & Validated-Law Alternate Syntax

#### Research Question & Mathematical Formulation
Can Operation 2 in the term algebra be extended from root-aligned trees (`anti-unify`) to:
1. **Unaligned Subgraph Correspondence Search (`discover-subexpression-abstractions`)**: Given a corpus of trees $\{T_i\}_{i=0}^{N-1}$ where a shared template $p$ is embedded at **unknown, varying subtree paths** $\pi_i$ inside distinct outer wrappers $T_i = W_i\bigl[\pi_i \gets \mathrm{Subst}(p, \theta_i)\bigr]$ (and some trees may be unrelated distractions with $\pi_i = \texttt{:none}$), can the system discover $(p, \{\pi_i\}, \{\theta_i\})$ and encode the corpus via a spliced pre-order packet (`corpus-abstraction-model`) that beats literal storage, whole-tree dictionary storage, and root-aligned AU?
2. **Law-Normalized Syntactic Abstraction**: When equivalent subtrees are obscured by algebraic identity wrappers (such as $e + 0$ or $e \cdot 1$ in $\mathbb{F}_5$), can normalizing the corpus through a `:validated` rewrite library (`prepare-rewrite-library`) expose a strictly tighter anti-unification template $p$ and smaller description length $S$ than raw syntactic AU, while prohibiting uncertified `:int` sample conjectures from altering syntax?

#### Kernel Mechanics & Controls
- **Five-Stage Progression (`abstraction-experiments.lisp`)**:
  - *Stages 1–3 (`run-m6-aligned-stages-and-controls`)*:
    - Stage 1 (Known Pattern): Reconstructs trees from a supplied template $p$ via `instantiate` and via a lowered `:code` constructor (`compile-au-constructor`) on `au-substitutions-frame`.
    - Stage 2 (First-Order Matching): Extracts per-tree bindings $\theta_i$ against a supplied pattern $p$ via `match-pattern` (enforcing repeated-hole equality and operator-hole signature compatibility), and shows that when the extracted bindings $\theta_i$ still share common structure, running `anti-unify` tightens the loose pattern to the exact LGG.
    - Stage 3 (Aligned Anti-Unification): Compares `anti-unify` against an independent recursive oracle `m6-reference-aligned-au` up to hole renaming (`patterns-isomorphic-p`), verifying operator holes, repeated value holes, and cross-type fallback.
  - *Stage 4 (`run-m6-hidden-occurrence-subgraph-search`)*: On `planted-abstraction-fixture` (where the planted pattern `(+ (* ?0 ?0) ?1)` is embedded at paths `NIL`, `'(1)`, `'(0)`, and `'(1 0)` inside 4 different wrappers per repetition), `discover-subexpression-abstractions` indexes all non-leaf subterms via `collect-tree-occurrences`, seeds pairwise LGGs, greedily selects best-saving occurrences across all corpus trees (`occurrence-saved-bits`), and emits a `corpus-abstraction-model` verified by `verify-corpus-abstraction-replay` and `decode-tree-corpus`. Includes repetition scaling ($\mathrm{reps} \in \{1, 2, 4\}$), unrelated-tree distraction controls (`:include-unrelated-p t`, assigning path `:none` to unrelated trees), and 4 deterministic LCG randomized trials (`randomized-planted-abstraction-fixture`).
  - *Stage 5 (`run-m6-validated-law-alternate-syntax`)*: Over $\mathbb{F}_5$, validates $X_0 + 0 = X_0$ and $X_0 \cdot 1 = X_0$ via `start-law-validation`, compiles them via `prepare-rewrite-library`, and normalizes corpus trees where branches are disguised as `(+ (* a b) (+ (* a b) '0))` and `(+ (* (* c d) '1) (* c d))`. Raw syntactic AU requires **5 holes** (`(+ ?0 ?1)` at root or loose branch holes), whereas law-normalized AU recovers the tight **2-hole** repeated-branch template `(+ (* ?0 ?1) (* ?0 ?1))`, reducing total AU bits while preserving exact original spelling on the raw path and rejecting uncertified `:int` sample conjectures.

#### Concrete Experiments & Test Suite (`abstraction-experiments.lisp` `run-m6`, `tests/abstraction.lisp`)
- **Authoritative Tests in `tests/abstraction.lisp` (7 `deftest`s)**:
  1. `abstraction-stages-1-to-3-and-controls`: Verifies Stages 1–3 (`instantiate`, `compile-au-constructor`, `match-pattern`, `anti-unify` vs. `m6-reference-aligned-au`, repeated holes, operator holes, cross-type fallback, and loose-template tightening).
  2. `abstraction-subtree-path-and-occurrence-indexing`: Tests `subtree-at-path`, `replace-subtree-at-path`, and `collect-tree-occurrences` across valid and invalid paths.
  3. `abstraction-tree-corpus-packet-and-spliced-model`: Tests `make-tree-corpus`, `encode-tree-corpus`, `decode-tree-corpus`, and `verify-corpus-abstraction-replay` (including rejection of tampered outer wrappers or substitutions).
  4. `abstraction-hidden-occurrence-subgraph-search-and-compression`: Verifies Stage 4 hidden-path recovery (`NIL`, `'(1)`, `'(0)`, `'(1 0)`), isomorphic planted-pattern recovery, and bit-size compression beating `:literal-sequence`, `:whole-tree-dictionary`, and `:aligned-root-au` at $\mathrm{reps} \in \{2, 4\}$.
  5. `abstraction-unrelated-tree-controls-and-randomized-trials`: Verifies `:none` path assignment on unrelated trees, negative-gain fallback on 2-tree corpora, and exact pattern recovery across all 4 seeded randomized trials (`randomized-planted-abstraction-fixture`).
  6. `abstraction-validated-law-alternate-syntax`: Verifies Stage 5 hole reduction (`5 -> 2` holes) and bit savings after `:validated` $\mathbb{F}_5$ law normalization, and verifies that `:conjecture` integer laws are rejected by `prepare-rewrite-library`.
  7. `abstraction-experiment-runner`: Executes the full `run-m6` suite and verifies all summary invariants.

---

### 4.7 Milestone 7: Autonomous View Discovery, Partition Reassembly & Locality Scheduling

#### Research Question & Mathematical Formulation
1. **Autonomous Boolean View Discovery (`discover-partition-views` in `factor.lisp`)**: Given a parent frame $\Omega$ whose target values follow a piecewise regime split across unknown input regions, can the system enumerate candidate Boolean guards $G(X)$ over a guard grammar, deduplicate observationally equivalent and complement ($G$ vs. $\neg G$) splits via Operation 1 (`observation-bucket`s), prune conflicting splits in $O(|\Omega|)$ via Operation 3 (`frame-conflict-p`), synthesize per-branch child models (`:separate-parts` `(if G M_true M_false)` and `:shared-decoder` $d\bigl(X, \texttt{(if } G\; Z_{\mathrm{true}}\; Z_{\mathrm{false}}\texttt{)}\bigr)$ with optional M4 `solver` propagation), and select the view that minimizes $J(M) = S(M) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$?
2. **Physical Permutation Invariance & Ordered Reassembly (`shuffle-frame-rows`, `partition-rows`, `reassemble-partition`, `partition-model`)**: Does shuffling the physical storage order of rows in $\Omega$ while keeping their declared coordinates $\mathbf{x}_\omega$ and occurrence keys `row-key` leave synthesized models and reassembled sequences completely invariant, while rejecting target-value grouping when no runtime selector or paid lookup key is available?
3. **Locality-Prioritized Occurrence Scheduling (`compute-tree-locality-positions`, `schedule-occurrence-pairs` in `factor.lisp`)**: When searching for shared subexpression abstractions in large multi-branch trees (`locality-abstraction-fixture`), does prioritizing candidate occurrence pairs by structural tree distance (`:locality` schedule with a 1-in-4 canonical reserve `(= 3 (mod turn 4))` or an induced `:locality-key` expression) reduce discovery work compared to `:canonical` order when repeated subtrees are co-local (`:co-local`) or made co-local by an induced parity key (`:interleaved`), while the 1-in-4 canonical reserve prevents starvation when matching subtrees are placed at opposite ends (`:distant`)?

#### Kernel Mechanics & Controls
- **Guard Partition Enumeration, Computed Linkages & Complement Deduplication (`evaluate-guard-partition`, `discover-partition-views` in `factor.lisp`)**:
  - `evaluate-guard-partition` evaluates a Boolean guard $G(X)$ across all rows of $\Omega$ in the metered VM, splits $\Omega$ into projected `true-frame` and `false-frame`, records the occurrence-preserving `partition` via `partition-rows`, and computes a new `linked-frame` via `with-frame-linkage` / `partition-pairs-and-anchors` carrying intra-regime must-agree `frame-pairs` and cross-regime must-vary `frame-anchors`.
  - `discover-partition-views` runs `start-observation-search` / `resume-observation-search` over `guard-language` (`:bool` target) to collect total Boolean guard buckets on $\Omega$.
  - Filters out trivial splits (where `true-rows` or `false-rows` is empty) and canonicalizes complement symmetry `(G, ~G)` using canonical Boolean masks so each unordered 2-part split $\{\Omega_{\mathrm{true}}, \Omega_{\mathrm{false}}\}$ is evaluated at most once, choosing the shorter guard expression $S(G)$.
  - For each candidate split, checks `frame-conflict-p` on both parts (recording `:conflict` proposals when a branch has incompatible same-input rows), then runs child synthesis under `:separate-parts` and (when a shared outer decoder $d(X, Z)$ is supplied) `:shared-decoder` with `pullback-frame` and optional `propagate-arithmetic-child`, assembling `(if G child_true child_false)` and verifying the composed program in the metered VM.
- **Locality Distance & 3:1 Interleaved Schedule (`compute-tree-locality-positions`, `schedule-occurrence-pairs`)**:
  - Assigns each tree a structural position (raw tree index $0 \dots N-1$, or induced rank after evaluating a priced `:locality-key` expression in the metered VM, partitioning via `partition-rows`, and verifying inverse-permutation reconstruction via `reassemble-partition`).
  - Orders candidate cross-tree occurrence pairs by ascending tree distance $|p_a - p_b|$, path-depth alignment $||\pi_a| - |\pi_b||$, and spine depth $|\pi_a| + |\pi_b|$ in the locality lane, interleaving 3 locality pairs with 1 canonical pair (`(= 3 (mod turn 4))`).

#### Concrete Experiments & Test Suite (`view-experiments.lisp` `run-m7`, `tests/views.lisp`)
- **Experiment Runner (`run-m7` in `view-experiments.lisp`)**:
  - **Part 1 (`run-m7-supplied-and-discovered-views`)**: On 28 interleaved `:int` sequence rows ($y_{r,t} = a_{r \bmod 2} + t$ with $a_0 = 1, a_1 = 3$), verifies that non-separating guards `(= X0 '0)` and `(= X1 '0)` are pruned in $O(|\Omega|)$ by `frame-conflict-p`, and that both supplied and grammar-discovered parity guards `(= (- X0 (* (/ X0 '2) '2)) '0)` rank `:shared-decoder` ($S = 101$ bits, $W_{\mathrm{run}} = 3{,}106$) ahead of `:separate-parts` ($S = 110$ bits, $W_{\mathrm{run}} = 3{,}274$) and unfactored `:lookup` ($S = 528$ bits, $W_{\mathrm{run}} = 35{,}698$). On $\mathbb{F}_7$ two-regime sequences ($y_{r,t} = a_r + \iota(t)$), autonomous view search discovers `(= '0 X0)` and selects `:shared-decoder` ($S = 160$ bits) over `:lookup` ($S = 224$ bits) and `:separate-parts` ($S = 261$ bits).
  - **Part 2 (`run-m7-storage-shuffle-and-permutation-controls`)**: Verifies that permuting physical row storage via `shuffle-frame-rows` yields the identical model ($S = 101$ bits, $W_{\mathrm{run}} = 3{,}106$), that grouping an ordered value sequence with ties/multiplicity requires and prices the inverse permutation via `partition-model` ($S = 526$ bits), and that withholding $r$ leaves $0$ valid runtime views over $t$ alone.
  - **Part 3 (`run-m7-locality-scheduling-and-canonical-reserve`)**: On `locality-abstraction-fixture`, verifies that `:locality` recovers the co-local planted template at `(3, 4)` under `pair-budget = 6` ($\Delta S = +5$ bits) while `:canonical` misses it; that `:locality`'s 1-in-4 canonical reserve recovers the distant match at `(0, 5)` ($\Delta S = +5$ bits) while `:locality-only` misses it; and that supplying the priced parity key `(- X0 (* (/ X0 '2) '2))` induces adjacency across `(0, 2, 4)` at `pair-budget = 1` ($\Delta S = +116$ bits).
- **Authoritative Tests in `tests/views.lisp` (4 `deftest`s)**:
  1. `view-supplied-vs-discovered-and-three-way-comparison`: Verifies supplied vs. autonomous view discovery, $O(|\Omega|)$ conflict pruning on non-separating guards, and 3-way bit comparison (`:shared-decoder` < `:separate-parts` < `:lookup` in `:int`, and `:shared-decoder` < `:lookup` < `:separate-parts` in $\mathbb{F}_7$).
  2. `view-physical-shuffle-and-permutation-reconstruction`: Verifies `shuffle-frame-rows` invariance, `partition-model` inverse permutation reconstruction with ties, target-leakage rejection when $r$ is withheld, and computed `pairs`/`anchors` via `partition-pairs-and-anchors`, `with-frame-linkage`, and `fiber-pairs-and-anchors` feeding `make-observation-scope` / `observation-invariants`.
  3. `view-locality-scheduling-and-canonical-reserve`: Verifies `:co-local`, `:distant` (1-in-4 reserve vs. window-only), and `:interleaved` (priced `:locality-key`) subexpression discovery on `locality-abstraction-fixture`.
  4. `view-experiment-runner`: Runs the complete `run-m7` suite and verifies all invariants.

---

### 4.8 Milestone 8: Recursive Synthesis, Backtracking/DAG Memory, Conflict Explanations & Learned Search Preferences

#### Research Question & Mathematical Formulation
Can the kernel compose Operations 2, 3, and 4 into a multi-step recursive synthesis engine that:
1. **Milestone 8A (Recursive Multi-Step Reconstruction)**: Chains `pullback-frame` + `fold-constants` + `propagate-arithmetic-child` across multiple decomposition steps $Y = d_1(X, Z_1),\; Z_1 = d_2(X, Z_2),\; \dots$ (including partial-constraint propagation where degenerating rows leave $Z_2$ unconstrained `'t` while informative rows pin $Z_2$ down) and lifts shared solver structure across primes via `:code` anti-unification?
2. **Milestone 8B (Backtracking, Depth & DAG Memory)**: Suspends and resumes parent/child search continuations (`search-job`, `observation-job`, `propagation-search`) across backtracking branches while sharing verified child subproblem results, `*node-meta*`, and `*prepared-rewrite-cache*` without recomputing completed subproblems?
3. **Milestone 8C (Checked Conflict Explanations & Pruning)**: Prunes dead decomposition branches before child enumeration whenever `fold-constants` and `frame-conflict-p` detect a row-level structural contradiction (`:unsatisfiable-row`) or a cross-row input collision (`:incompatible-rows`)?
4. **Milestone 8D (Learned Search Preferences via Residual-Priced Heuristic Condensation)**: Condenses logged continuation returns $G_t = B_t - B_T - \lambda_{\mathrm{search}}(W_T - W_t)$ via `condense-heuristic` (Operation 4.2) into a compact symbolic priority predictor $\hat{\pi}$ that steers search 3:1 over the 1-in-4 canonical reserve?

#### Kernel Mechanics, Controls & Concrete Tests (`tests/propagation.lisp`, `frame.lisp`, `factor.lisp`)
- **8A — Multi-Step Recursive Chain ($y = a + 3b$ over $\mathbb{F}_7$ and Cross-Prime Coefficient Lifting)**:
  - *Step 1*: Pulling the 49-row $\mathbb{F}_7$ frame for $y = a + 3b$ back through $d_1(X_0, Z_1) = X_0 + Z_1$ and applying certified $\mathbb{F}_7$ addition propagation (`propagate-arithmetic-child`) produces the child frame $\Omega_{Z_1}$ with exact target values $z_{1,\omega} \equiv 3 b_\omega \pmod 7$.
  - *Step 2*: Pulling $\Omega_{Z_1}$ back through $d_2(X_1, Z_2) = X_1 \cdot Z_2$ and applying certified $\mathbb{F}_7$ multiplication propagation leaves the 7 rows with $b_\omega = 0$ as the unconstrained predicate `'t` ($\mathrm{Fiber}(\omega) = \mathbb{F}_7$, since $0 \cdot Z_2 = 0$) and narrows the 42 rows with $b_\omega \neq 0$ to `(= Z_2 '3)`.
  - *Step 3*: Child synthesis on $\Omega_{Z_2}$ (or `infer-fibers` intersecting the 42 singleton fibers with the 7 `'t` fibers) immediately synthesizes the constant `'3` ($S_{\mathrm{body}} = 7$ bits), assembling the full two-step program `(+ X0 (* X1 '3))` and verifying it on all 49 rows.
  - *Cross-Prime AU Lifting*: Anti-unifying the quoted `:code` additive-inverse solvers $C + 4K$ ($\mathbb{F}_5$), $C + 6K$ ($\mathbb{F}_7$), and $C + (-1)K$ ($\mathbb{Z}$) after type-erased or within-schema `:code` alignment isolates the single modulus-dependent coefficient hole `?coeff` inside `(+ C (* ?coeff K))`.
- **8B — Resumable Continuation & DAG Subproblem Reuse**:
  - Every `search-job`, `observation-job`, and `propagation-search` is a first-class resumable closure over its `(schema, language, frame, cursor, table, work)` state. When two parent decoders reduce to the same canonical child requirement signature $(B_\omega(Z))_{\omega \in \Omega}$, or when a suspended parent branch is resumed at a higher work budget, cached subproblem results and prepared rewrite rules (`*prepared-rewrite-cache*`) are reused without re-enumerating already-exhausted tiers.
- **8C — Checked Conflict Explanations (`fold-constants` & `frame-conflict-p` in `tests/propagation.lisp` & `tests/lifting.lisp`)**:
  - *Test 1 (`:unsatisfiable-row` in `constant-folding-and-conflict-detection`)*: Pulling `(= Y '(2 3))` back through diagonal decoder `(tuple Z Z)` decomposes via tuple injectivity in `fold-constants` into `(if (= Z '2) (= Z '3) 'nil)`. When combined with a concrete substitution or constant mismatch, `frame-conflict-p` returns `(values t :unsatisfiable-row (:bad))` in 0 child enumeration steps.
  - *Test 2 (`:incompatible-rows` in `constant-folding-and-conflict-detection`, `m5-contradictory-t-only-and-context-restoration`, and `discover-partition-views`)*: When two rows in the same partition branch or sharing identical child inputs $\mathbf{x}_\omega$ require `(= Z '2)` and `(= Z '3)`, `conjoin-requirements` folds their conjunction to `'nil` and `frame-conflict-p` returns `(values t :incompatible-rows (:k1 :k2))`, immediately pruning the invalid branch and recording a `:conflict` diagnostic.
- **8D — Residual-Priced Heuristic Condensation (`condense-heuristic` in `tests/propagation.lisp`)**:
  - Given logged episode features and continuation returns $G_t$, tabular shrinkage $\widehat{G}_k = \frac{\kappa G_{0,k} + \sum_{i:k_i=k} G_i}{\kappa + n_k}$ produces target scores that `condense-heuristic` compresses into a symbolic expression $\hat{\pi}$ by pricing residual mismatches during training and dropping the residual table at deployment (`condense-heuristic-with-priced-residual`), scheduling 3 heuristic quanta per 1 canonical reserve quantum (`(= 3 (mod turn 4))`).

---

### 4.9 Milestone 9: Self-Hosted Compositional Vocabulary & Library Retrieval

#### Research Question & Mathematical Formulation
Once the system has discovered and verified reusable functions $f_0, f_1, \dots, f_{L-1}$ across Milestones 1–8, can those functions be registered in the object language under **opaque symbol IDs** (`#:F0`, `#:F1`, ... carrying only their input-output type signature $(\tau_0, \dots, \tau_{m-1}) \to \tau$ and no human-chosen names) while the system synthesizes **compact symbolic descriptors and retrieval heuristics** $\hat{\pi}$ in its own DSL (`condense-heuristic`, Operation 4.3) to prioritize which library entries to test and compose on new partial I/O frames?

#### Kernel Mechanics, Controls & Concrete Verification
- **Opaque Library Registration (`ast.lisp`, `enumerate.lisp`)**:
  - Learned functions (such as shifts $s_c(x) = x + c$, scalings $m_c(x) = c \cdot x$, squares $q(x) = x^2$, and linear combinations $f(a, b) = a + 2b$) are wrapped as `prepared-program` entries (`prepare-program` in `vm.lisp`) and exposed in `language-operators` under opaque symbol tags `:f0, :f1, ...` whose encoding bit cost is determined solely by operator arity and table index.
- **Behavioral Probe Signature & Descriptor Condensation (`condense-heuristic`)**:
  - Each library entry $f_\ell$ is evaluated on a fixed canonical probe tuple $\mathbf{p} = (p_1, \dots, p_k)$ (e.g., $x \in \{0, 1, 2\}$), charging `:discovery` work to form a behavioral probe table mapping probe outputs $(f_\ell(p_1), \dots, f_\ell(p_k))$ and algebraic property bits (such as $f_\ell(0) = 0$, $f_\ell(1) - f_\ell(0) = f_\ell(2) - f_\ell(1)$) to library indices or structural parameter values $c$.
  - Calling `condense-heuristic` on the probe table synthesizes a compact symbolic descriptor $\hat{\pi}$ (for example, recovering the shift constant $c = f(0)$ for the family $s_c(x) = x + c$ or the slope $c = f(1) - f(0)$ for $m_c(x) = c \cdot x$) that predicts the relevant library primitive directly from a new task's probe observations.
- **3:1 Prioritized Retrieval with 1-in-4 Canonical Reserve**:
  - On a new synthesis frame $\Omega$ (including partial I/O frames where $f(0)$ is unobserved and must be inferred from differences or relational probes, and two-step compositions $f_{\ell_1}(f_{\ell_2}(x))$), the search driver schedules **3 quanta testing descriptor-ranked library candidates for every 1 quantum of canonical bottom-up enumeration** (`(= 3 (mod turn 4))`), charging all descriptor evaluation and candidate verification work to `W_search` and verifying every proposed composition on the full frame $\Omega$ plus held-out inputs.

---

## 5. Research Decisions, Required Experiment Trace & Literature Boundaries

### 5.1 Summary of Core Research Decisions

| Topic | Decision in `lisploop` |
| :--- | :--- |
| **AST & Data Representation** | Homoiconic pooled S-expressions (`#:X0`, `#:?0`, `#:+`, `'v`) with $O(1)$ weak-table metadata (`*node-meta*`); quoted syntax `(:code inputs sort)` wraps the exact same S-expressions as first-class values without `eval`. |
| **Evaluator & Preemption** | Single frame-stack stepper `evaluation` (`vm.lisp`) with `evaluation-debt` draining; guarantees exact `quantum = 1` vs. batch state, continuation, and work-ledger parity (`equalp`). |
| **Two-Level Objective** | Object-level $J(M) = S(M) + S(\varepsilon(M, \Omega)) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$ ($\varepsilon \equiv 0$ for exact models; priced residual during lossy heuristic condensation, dropped at deployment); meta-level $J_{\mathrm{procedure}}(P) = J(M_P) + \lambda_{\mathrm{search}} W_{\mathrm{search}}(P)$. |
| **Pullback & Simplification** | `pullback-frame` substitutes $X \gets \mathbf{x}_\omega$ into $A_\omega(d(X, Z))$ and runs `fold-constants` (closed-subtree evaluation, Boolean identities, tuple equality injectivity) followed by $O(|\Omega|)$ conflict detection via `frame-conflict-p`. |
| **Downward Propagation** | Dual-grade: `:validated` ($\iff$, witness $\Leftarrow$ + uniqueness $\implies$ on $D^\Gamma$) replaces $B_\omega(Z)$ **in-place**; `:conjecture` ($\Leftarrow$ on $\mathbb{Z}$ or non-unique fibers) schedules `:primary` vs. `:fallback` **3:1** in `propagation-search` with forward replay against `propagation-original`. |
| **Unsupervised Concept Lifting** | Two-stage: Stage 1 (`infer-fibers`) runs must-link/projection tightening + exact branch-and-bound MDL partition search over pulled-back fibers $\mathrm{Fiber}(\omega)$; Stage 2 deploys labels via `lookup-model` or `condense-heuristic`. |
| **Heuristic & Locality Control** | All learned control priors (locality schedules, search-return predictors, library descriptors) interleave **3 heuristic quanta with 1 canonical reserve quantum** (`(= 3 (mod turn 4))`) so completeness is never lost. |

### 5.2 Required Experiment Trace Standard

Every experiment runner (`run-m1` through `run-m6` and subsequent milestone drivers) emits a machine-checkable structured plist trace (`results.md`) recording:
1. **Schema & Scope**: Ambient domain $D$, input signature, target type $\tau$, row count $|\Omega|$, and bit/work limits.
2. **Synthesized / Discovered Artifacts**: Exact S-expression syntax, Encoding v7 total bits $S(M) = S_{\mathrm{header}} + S_{\mathrm{body}}$, runtime work $W_{\mathrm{run}}(M)$, and epistemic status (`:validated`, `:conjecture`, `:refuted`, `:replayed-observations`).
3. **Full 10-Bucket Work Breakdown**: `:enumeration`, `:proposal-execution`, `:checker`, `:simulation`, `:orientation`, `:rewrite`, `:validation`, `:compression`, `:matching`, `:discovery`, and `work-total`.
4. **Baseline & Control Comparisons**: Exact bit and work comparisons against `lookup-model`, literal sequences, unpropagated pullback, unnormalized AU, and negative controls (contradictory rows, wrong shifts, invalid domain transfers, and `quantum = 1` parity checks).

### 5.3 Literature & Reference Boundaries (`[R1]–[R11]`)

The mathematical mechanisms in `lisploop` connect to established literature under strict self-containment boundaries:
- **[R1] Minimum Description Length & Two-Part Codes** (Rissanen 1978; Grünwald 2007): Motivates $J(M) = S(M) + S(\varepsilon(M, \Omega))$ under prefix-free Encoding v7 (`codec.lisp`) and residual-priced heuristic condensation (`condense-heuristic`).
- **[R2] Levin Universal Search & Resource-Bounded Complexity** (Levin 1973; Schmidhuber 2004): Motivates combining program size $S(M)$, runtime work $W_{\mathrm{run}}(M)$, and search work $W_{\mathrm{search}}(P)$ with a guaranteed 1-in-4 canonical reserve.
- **[R3] Bottom-Up Observational Equivalence Synthesis** (Udupa et al. 2013 *TRANSIT*; Albarghouthi et al. 2013 *Escher*): Motivates `observation-bucket`s on outcome vectors $M(e, \omega)$, extended here with action-invariant filtering (`observation-invariants`), partial-outcome retention (`:retain-outcomes t`), and exact preemption parity.
- **[R4] Algebraic Specification & Equational Term Rewriting** (Baader & Nipkow 1998; Jackson 2006): Motivates exhaustive finite-domain certification (`law-certificate`), totality-checked guarded rewriting (`provably-total-p`), and rewrite preparation amortization (`prepare-rewrite-library`).
- **[R5] Contravariant Witness Functions & Top-Down Deductive Synthesis** (Polozov & Gulwani 2015 *FlashMeta*): Motivates pulling parent requirements $A_\omega(Y)$ back through decoders $Y = d(X, Z)$ (`pullback-frame`), generalized here so witness solvers are **learned and graded inside the system** (M4) rather than hand-coded per operator.
- **[R6] Constraint Propagation & Narrowing** (Apt 2003; Steele 1980): Motivates propagating relational constraints across operator networks, refined here into the dual-grade distinction between certified in-place equivalence ($\iff$) and tentative 3:1 witness propagation ($\Leftarrow$).
- **[R7] Predicate Invention, Relational Decomposition & Hard-EM Clustering** (Muggleton 1995; Kemp & Tenenbaum 2008): Motivates unsupervised intermediate concept lifting (`infer-fibers`) by intersecting pulled-back value fibers $\mathrm{Fiber}(\omega)$ under a lexicographic MDL partition objective.
- **[R8] Plotkin / Reynolds Anti-Unification & E-Graph Subtree Compression** (Plotkin 1970; Reynolds 1970; Bowers et al. 2023 *Stitch*; Cao et al. 2023 *babble*): Motivates `anti-unify` (extended with typed `:fn` operator holes and lowered constructor lambdas), unaligned subgraph correspondence search (`discover-subexpression-abstractions`), and law-normalized syntactic anti-unification.
- **[R9] Unification-Based Condition Synthesis** (Alur et al. 2015 *STUN*): Motivates synthesizing piecewise regime programs `(if G M_true M_false)` via guard enumeration, complement deduplication, and $O(|\Omega|)$ conflict pruning (`discover-partition-views`).
- **[R10] Conflict-Driven Clause Learning & Nogood Pruning** (Marques-Silva & Sakallah 1999; Feng et al. 2018 *Neo*): Motivates early structural and cross-row conflict detection (`fold-constants` + `frame-conflict-p`) prior to child search.
- **[R11] Library Learning & Wake-Sleep Program Induction** (Ellis et al. 2021 *DreamCoder*): Motivates self-hosted library growth and learned retrieval descriptors (M9), implemented here without neural networks by condensing probe tables into symbolic DSL heuristics via `condense-heuristic`.

---

## Appendix A: Architectural Evolution — What Changed from `plan4` and `plan5` to `plan6`

This appendix records the architectural diagnosis and stress-test that transformed `plan4` (the original 16-file specification) and `plan5` (its initial homoiconic refactor) into the self-contained 7-module architecture of `plan6`.

### A.1 What `plan5` Diagnosed Correctly in `plan4` (Retained in `plan6`)

`plan5` identified three major sources of architectural friction in `plan4`:
1. **Elimination of the Two-Level AST Schism**: In `plan4`, object-language programs were `defstruct` nodes while Milestone 3C quoted programs (`(:code ...)`) were nested data structures manipulated by custom `:code-*` instructions. `plan5` replaced both with **canonical homoiconic S-expressions** (`(+ X0 '1)`) backed by a pooled symbol table (`*typed-symbol-pool*`) and a weak `eq` metadata table (`*node-meta*`) caching type and prefix-free bit size in $O(1)$.
2. **Unification of Discovery Mechanisms**: `plan5` recognized that synthesis (M1), invariants (M2), laws and guards (M3A), AU compression (M3B/M6), algebraic inversion (M4), concept lifting (M5), and view discovery (M7) are not nine unrelated algorithms, but projections of a small set of operations over an observation matrix $M(e, \omega)$ and pulled-back requirement predicates $A_\omega(d(X, Z))$.
3. **Consolidation of the Codebase**: `plan5` collapsed `plan4`'s 16 fine-grained source files into a 7-module kernel (`ast.lisp`, `codec.lisp`, `vm.lisp`, `frame.lisp`, `enumerate.lisp`, `factor.lisp`, `laws.lisp`).

### A.2 Five Architectural Stress-Test Findings in `plan5` and Their Resolution in `plan6`

Stress-testing `plan5` against the authoritative kernel and test suite exposed five places where `plan5` over-simplified a mechanism in a way that would violate the cost model, the epistemic grading rules, or integer/multi-fiber soundness:

1. **Pullback Must Include Closed-Subtree Constant Folding (`fold-constants`), Not Pure Syntactic Substitution**:
   - *The flaw in `plan5`*: `plan5` defined pullback purely as syntactic substitution $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$, deferring all simplification to M3/M4 rewrite rules.
   - *Why that failed*: First, in Milestone 4's expensive-context control $y = a^2 + g(b)$ with $a = 2^{128} + i$, pure syntactic substitution leaves `(* 'a 'a)` unsimplified inside $B_\omega(Z)$, forcing the checker to recompute $a^2$ on every candidate child program $g(b)$ instead of amortizing the known context once during pullback. Second, in Milestone 8C, pulling `(= Y '(2 3))` back through the diagonal decoder $d(Z) = \texttt{(tuple } Z\; Z\texttt{)}$ produces `(= (tuple Z Z) '(2 3))`; without constructor-injectivity folding (`(and (= Z '2) (= Z '3)) -> 'nil`), the structural conflict is invisible until child enumeration wastes budget.
   - *Resolution in `plan6`*: `pullback-frame` in `frame.lisp` immediately runs `fold-constants` (evaluating closed $Z$-free subtrees once in the metered VM, decomposing tuple equalities by injectivity, and simplifying Boolean/membership identities) followed by `frame-conflict-p` (`:unsatisfiable-row` and `:incompatible-rows`).

2. **Certified In-Place Equivalence ($\iff$) vs. Tentative 3:1 Witness Propagation ($\Leftarrow$)**:
   - *The flaw in `plan5`*: `plan5` treated downward propagation uniformly as applying a verified M3 rewrite rule `(op K Z) = C -> Z = q(K, C)` to simplify $B_\omega(Z)$ in-place.
   - *Why that failed*: Over finite fields $\mathbb{F}_p$, an exhaustively `:validated` bijection (both witness $\Leftarrow$ and uniqueness $\implies$ certified on $D^\Gamma$) is a true logical equivalence ($\iff$) when its guard holds, so replacing $B_\omega(Z)$ **in-place** with `(= Z 'v_w)` is exact and loses zero solutions. Over $\mathbb{Z}$, however, (a) solvers validated on $[-4, 4]^2$ have status `:conjecture`, and (b) truncating integer division `Z / 2 = 1` has **multiple solutions** $Z \in \{2, 3\}$ (uniqueness is `:refuted`). Replacing `(= (/ Z '2) '1)` in-place with `(= Z '2)` destroys $Z = 3$ and causes coupled child problems (such as `Z / 2 = 1` and `Z / 3 = 1`) to fail (`tentative-failure-and-success-both-preserve-integer-alternatives` in `tests/propagation.lisp`).
   - *Resolution in `plan6`*: Operation 3.4 enforces **dual-grade propagation**: `:validated` ($\iff$) solvers narrow $B_\omega(Z)$ in-place, whereas `:conjecture` ($\Leftarrow$) solvers populate a narrowed `:primary` frame alongside an un-narrowed `:fallback` frame scheduled **3:1** in `propagation-search` with forward replay against `propagation-original`.

3. **Two-Stage Concept Lifting (`infer-fibers` + `condense-heuristic`) and Non-Greedy MDL Fiber Clustering**:
   - *The flaw in `plan5`*: `plan5` described M5 Hard-EM concept lifting as "just `quotient-values` applied to pulled-back requirement predicates," and suggested greedy pairwise intersection of compatible predicates.
   - *Why that failed*: Exact syntactic quotienting of $B_\omega(Z)$ only merges rows whose pulled-back predicates are already syntactically identical (failing whenever rows have overlapping set or relational requirements such as $\{1, 2\}$ and $\{2, 3\}$), while greedy pairwise intersection falls into the bridge-vs-leaf trap (`{1,2}, {2,3}, {1,4}, {3,5}` merging `{1,2}` and `{2,3}` to `{2}` and stranding `{1,4}` and `{3,5}` into $K = 3$ clusters instead of the optimal $K = 2$). Moreover, `quotient-values` produces an extensional index list $j_\omega$, whereas deploying a lifted concept on a multi-coordinate parent $(r, t)$ requires either a paid `lookup-model` over $r$ or an intensional selector expression $\hat{\pi}(r, t)$.
   - *Resolution in `plan6`*: `infer-fibers` (`factor.lisp`) performs Stage A same-input determinism and single-coordinate conflict-free projection search (`tighten-same-input-requirements`), Stage B bounded branch-and-bound lexicographic MDL partition search over deduplicated requirement groups, and Stage C computed intra-fiber `pairs` and cross-fiber `anchors` (`partition-pairs-and-anchors`, `fiber-pairs-and-anchors`), followed by Stage 2 deployment via `context-label-frame` or direct requirement synthesis in `condense-heuristic`.

4. **The Single Resumable Debt-Draining Stepper (`evaluation`) in `vm.lisp`**:
   - *The flaw in `plan5`*: `plan5` suggested a ~100-line recursive evaluator charging `work` on each call.
   - *Why that failed*: A host-stack recursive `eval` cannot suspend mid-expression or mid-instruction when a single bignum multiplication $(2^{128})^2$ or prepaid `:gather` bounds check exceeds a small step quantum (`quantum = 1`), breaking the core preemption parity tests (`batched-search-preserves-continuations-and-costs`, `batched-checker-debt-and-errors`, `unpaid-instruction-error-after-batched-work`).
   - *Resolution in `plan6`*: `vm.lisp` retains the single explicit frame-stack state machine `evaluation` with `evaluation-debt` draining, used uniformly across all 7 modules.

5. **Separating Exact Synthesis ($\varepsilon_\omega = 0$) from Residual-Priced Heuristic Condensation (Operation 4)**:
   - *The flaw in `plan5`*: `plan5` wrote a single global objective $J(M) = S(M) + S(\varepsilon(M, D)) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M) + \lambda_{\mathrm{search}} W_{\mathrm{search}}(M)$ without distinguishing where non-zero residuals $\varepsilon$ are permitted or how $W_{\mathrm{search}}$ is attributed.
   - *Resolution in `plan6`*: Section 1.5 and Section 2.4 separate the **object-level model objective** $J(M)$ from the **meta-level procedural objective** $J_{\mathrm{procedure}}(P)$, require $\varepsilon_\omega \equiv 0$ for valid synthesis, laws, and guards (Operations 1–3), and introduce `condense-heuristic` (Operation 4) which prices residuals during heuristic learning and drops $\varepsilon$ at deployment behind the 1-in-4 canonical reserve.

### A.3 Consolidation Mapping from `plan4`'s 16 Files to `plan6`'s 7-Module Kernel

| `plan6` Module | Consolidated `plan4` Files | Architectural Simplification |
| :--- | :--- | :--- |
| `ast.lisp` | `types.lisp`, `work.lisp`, `ast.lisp` (parts) | Unified pooled symbols (`*typed-symbol-pool*`), homoiconic cons ASTs, $O(1)$ `*node-meta*`, 10-bucket `work` ledger, `message` envelope, and `model` structs. |
| `codec.lisp` | `codec.lisp`, `compression.lisp` (packet codecs) | Single Encoding v7 bit-vector serializer/deserializer with $O(1)$ `body-size` lookup and analytical `literal-range` inversion across expressions, lookups, concatenations, and AU packets. |
| `vm.lisp` | `runtime.lisp`, `symbolic.lisp` (VM ops), `amortization.lisp` (prepared programs) | Single debt-draining `evaluation` stepper executing scalar/field arithmetic, tuples/sequences, `:lookup`, `:gather`, and `:code-*` symbolic inspection/matching/substitution. |
| `frame.lisp` | `frame.lisp`, `pullback.lisp` | Unified `frame` and `row` structures, `orient-observations`, `pullback-frame` with `fold-constants`, `conjoin-requirements`, `frame-conflict-p`, and standalone `verify-model`. |
| `enumerate.lisp` | `search.lisp`, `observations.lisp` | Shared bottom-up grammar table driving both unary synthesis (`search-job`) and cross-row equivalence/invariant discovery (`observation-job`, `observation-invariants`). |
| `factor.lisp` | `views.lisp`, `au.lisp`, `abstraction.lisp`, `lifting.lisp` | Unified factorization module housing `anti-unify`, `compile-au-constructor`, `discover-subexpression-abstractions`, `quotient-values`, `partition-rows`, `infer-fibers`, `condense-heuristic`, `discover-partition-views`, and `schedule-occurrence-pairs`. |
| `laws.lisp` | `laws.lisp`, `guards.lisp`, `algebra.lisp`, `propagation.lisp` | Unified equational and algebraic reasoning module housing `start-law-validation`, `propose-guarded-laws`, `propose-law-compressions`, `prepare-rewrite-library`, `discover-arithmetic-solver`, `validate-arithmetic-solver`, `propagate-arithmetic-child`, and `propagation-search`. |
