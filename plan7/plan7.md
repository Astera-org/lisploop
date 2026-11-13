---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,calc,shapes.geometric,fit,backgrounds}
---

# `lisploop` — plan 7

## Overview: Aim, Design Principle, and Milestone Map

### Aim

`lisploop` is motivated by & tests the hypothesis: **there are many levels of conservation, some of which are generated from different views of the same data and meta-data, especially different forms of causality. When conserved information or views are destroyed, hidden, or aliased, a fixed set of algorithms for inferring them suffices - and can bootstrap inferring algorithms, heuristics, languages, search policies, and search messages/constraints that can infer or find them**.

It is implemented as a self-contained Common Lisp kernel and experimental suite over finite prime fields $\mathbb{F}_p$ and unbounded signed integers $\mathbb{Z}$. 
The system investigates how automated mathematical and algorithmic discovery arises from three interacting components
(below, [M1](#sec-m1)–[M9](#sec-m9) refer to the milestones summarized in the [Reading & Implementation Map](#sec-reading-map) and defined in [Section 4](#sec-milestones); concrete representations and mathematical nomenclature are defined in [Section 1](#sec-shared-contract) and [Section 2](#sec-nomenclature)):

1. **Symmetry (Conservation Under Action and Across Observations)**: Discovery begins by detecting what remains invariant when inputs, states, or syntax are transformed. At the empirical data level, a synthesized program $e(X)$ conserves a target input-output relation $A_\omega(Y)$ across observation rows $\omega \in \Omega$ ([M1](#sec-m1)), while an action invariant $h(X)$ is conserved along the trajectory steps of a state transition $T$ (`pairs`) yet varies across distinct orbits (`anchors`, [M2](#sec-m2)) and hence remains informative. At the operator and meta-data level, guarded algebraic laws $G(X) \implies e_1(X) = e_2(X)$ can be certified across a supported finite domain grid $D^\Gamma$ ([M3A](#sec-m3)), and shared syntactic skeletons $p$ can be found across corpora of laws and subexpressions ([M3B](#sec-m3), [M6](#sec-m6)); `retype-law` retypes scalar and tuple laws across prime fields and `:int`, while automatic cross-prime solver-family alignment prior to anti-unification remains proposed [M8](#sec-m8) work.
2. **Algebra (Converting Conserved Expressions into Generative Models, Descriptions, and Backward Solvers)**: A conserved relation $R(X, Y)$ or invariant $h(s) = h(Ts)$ is initially a passive test—it checks whether a given tuple is valid, but does not by itself generate solutions. Algebra turns passive conservation into **active generation and backward constraint propagation**: reorienting which coordinates of a recorded relation serve as known inputs vs. unknown targets (`orient-observations`, `orient-arithmetic-requirements`), synthesizing explicit witness functions $q(K, C)$ and solvability guards $G(K, C)$ that invert forward operators ([M4](#sec-m4)), and pulling parent requirements $A_\omega(Y)$ backward through outer decoders $Y = d(X, Z)$ to generate child synthesis problems, with explicit simplification and propagation (`pullback-frame`, `fold-constants`, `propagate-requirements`).
3. **Interacting Views of Data & Meta-Data, and Inferring Hidden or Aliased Information**: Because object-language programs, row requirement predicates $A_\omega(Y)$, the equations and guards of algebraic laws, and anti-unification templates are all homoiconic S-expressions, the system can project both runtime data and symbolic meta-data through interchangeable views: deduplicated lookup tables (quotient views), syntactic templates with holes ([M3B](#sec-m3), [M6](#sec-m6)), synthesized input-feature projections (`start-dependency-search`), and **piecewise regimes**—subsets of observations $\Omega_k \subseteq \Omega$ that follow different local rules or parameters when a single uniform formula does not fit all rows. Specifically, a regime split may be either an **observable Boolean regime split** ([M7](#sec-m7)), where a synthesized guard predicate $G(X)$ partitions the input space into `(if G branch_1 branch_2)` (e.g., even vs. odd episodes), or a **latent regime parameter** $a_{j(r)}$ ([M5](#sec-m5)), where an unobserved intermediate value $Z = a_{j(r)}$ (such as a hidden per-episode offset $a_0 = 1$ vs. $a_1 = 3$ inside $y_{r,t} = \iota(t) + a_{j(r)}$) switches across occurrence groups $r$ without any explicit regime label $j(r)$ in the data. Whenever a projection or many-to-one operator **aliases** distinct states onto the same observable value or hides an unlabelled coordinate—such as $0 \cdot Z = 0$, truncating integer division $Z / 2 = 1 \implies \{2, 3\}$, latent regime parameters $a_{j(r)}$ in [M5](#sec-m5), or shared subexpressions buried at varying tree paths in [M6](#sec-m6)—the kernel explores candidate hidden structures via conservative requirement folding (`fold-constants`), bounded fiber partition proposals (`infer-fibers`), explicit dependency/selector synthesis (`start-dependency-search`), structural conflict pruning (`frame-conflict-p`), and subgraph correspondence search (`discover-subexpression-abstractions`).

### Core Design Principle

The research program seeks reductions in description length $S$, execution work $W_{\mathrm{run}}$, and discovery work $W_{\mathrm{search}}$, while allowing intermediate expansions that make later compression possible. Individual proposals need not improve any of these quantities.

The implementation uses four operations: observational conservation; factorization and bounded fiber proposals; causal reorientation, pullback, simplification, and propagation; and heuristic condensation with explicit search orchestration. Programs, requirements, and quoted syntax are S-expressions. Frames, laws, certificates, and continuations are Lisp structs around them, not object-language programs.

For tentative propagation and recursive decomposition, completed candidates are replayed against the original specification. Their schedulers reserve every fourth quantum for an active original search lane. This is a guarantee of scheduled progress within configured bounds, not an unrestricted completeness or wall-clock guarantee. Locality scheduling has a separate reserve measured in occurrence-pair selections. Learned heuristic scheduling remains an M8 research target.

### Reading & Implementation Map {#sec-reading-map}

This plan distinguishes **implemented mechanisms and tests** from **proposed extensions**. The Lisp is authoritative; [architecture.md](architecture.md) documents current APIs. Standalone experiment runners have been removed: fixtures and experimental controls now live in `tests/`. Historical numbers remain in [deprecated/results.md](deprecated/results.md) and [deprecated/results-history.md](deprecated/results-history.md), with their original accounting versions.

| Milestone | Question and current boundary | Main source | Current evidence |
| :--- | :--- | :--- | :--- |
| [1. Search](#sec-m1) | Typed bounded synthesis, pullback, reconstruction, and preemption | `ast.lisp`, `codec.lisp`, `vm.lisp`, `frame.lisp`, `enumerate.lisp` | `tests/core.lisp`, `tests/codec.lisp` |
| [2. Equivalence](#sec-m2) | Empirical buckets and informative action invariants | `frame.lisp`, `enumerate.lisp` | `tests/observations.lisp` |
| [3. Laws and syntax](#sec-m3) | Guarded laws, exact corpus reconstruction, checked symbolic rewrites | `laws.lisp`, `factor.lisp`, `vm.lisp` | Law, guard, compression, symbolic, and amortization suites |
| [4. Algebra](#sec-m4) | Learned witnesses and guards; certified versus tentative propagation | `laws.lisp`, `enumerate.lisp` | `tests/algebra.lisp`, `tests/propagation.lisp` |
| [5. Lifting](#sec-m5) | Supplied lifting, bounded fiber proposals, explicit dependencies | `factor.lisp`, `synthesize.lisp` | `tests/lifting.lisp`, `tests/refactor.lisp` |
| [6. Abstraction](#sec-m6) | Typed AU and bounded subexpression correspondence search | `factor.lisp`, `laws.lisp` | `tests/abstraction.lisp` |
| [7. Views and locality](#sec-m7) | Boolean views, Stage A residual/linkage metrics, and supplied locality schedules; pluggable DSL metrics and learned locality keys remain open | `frame.lisp`, `enumerate.lisp`, `factor.lisp` | `tests/views.lisp`, `tests/refactor.lisp` |
| [8. Recursion](#sec-m8) | Supplied & Stage B residual decompositions (`heuristic-decompositions`, `start-heuristic-synthesis`), child folding/solver propagation, nogood sibling pruning, child DAG reuse, and `:policy :heuristic` agenda routing | `synthesize.lisp`, `requirements.lisp`, `frame.lisp`, `factor.lisp` | `tests/refactor.lisp`, `tests/propagation.lisp` |
| [9. Vocabulary](#sec-m9) | Proposed learned function registry and descriptor-guided retrieval | Existing syntax and condensation are prerequisites | No end-to-end M9 implementation |

## 1. Shared Contract: Representation, Availability, Costs, and Evidence {#sec-shared-contract}

### 1.1 Domains, types, and schemas

A schema $\Gamma=(D,X_0{:}\tau_0,\ldots,X_{m-1}{:}\tau_{m-1}\to\tau)$ is constructed with `make-schema`; its slots are `domain`, `inputs`, `target`, and `lookup-p`. The ambient arithmetic domain is `:int` or `(:gf p)`. `gf` rejects composite moduli; integer division truncates toward zero and field division uses `field-reciprocal`.

Values may also be Booleans, tuples, sequences, or quoted syntax of type `(:code inputs sort)`. Homogeneous tuples and sequences support bounds-checked `:at`; sequences also support gathering, concatenation, and table lookup. An input schema and the predicate checker have separate variable scopes.

Finite tuples over `(:gf p)` and `:bool` are valid runtime and law types (`law-type-p`, `finite-type-p`): the **exhaustive law validator** supports scalar field, Boolean, and nested finite-tuple inputs and equation results. `finite-type-cardinality` and `law-assignment` recursively enumerate those finite product grids via mixed-radix unranking (e.g. radix depends on the field of the tuple), while unbounded types (such as `:int`, tuples containing `:int`, or sequences) require explicit `:samples`.

### 1.2 Homoiconic syntax and metadata

`var` and `hole` return pooled symbols. `lit` produces a typed quote list, and `app` produces an ordinary operator-headed list. A function hole has sort `(:fn argument-types return-type)`; `hole` has no `:kind` keyword. Laws contain equation and guard ASTs inside a `law` struct.

`*typed-symbol-pool*` gives symbols stable identity. `*node-meta*` is a weak `eq` cache for node kind, type, non-variable bits, variable count, syntax work, conservative totality, and free variables. Copies may require metadata reconstruction.

After scope/type validation, the body-size formula for $m$ inputs is

$$
S_{\mathrm{body}}(e)=
\mathrm{nonvarbits}(e)+\mathrm{varcount}(e)\,
\mathrm{integer\text{-}length}(\max(0,m-1)).
$$

The metadata lookup can be constant time; `body-size` and `description-size` themselves recursively validate expressions. AST construction, copying, quotation, and serialization are not free.

The 26 fixed operators comprise sixteen object primitives (`:+`, `:*`, `:=`, `:tuple`, `:member`, `:lookup`, `:gather`, `:-`, `:/`, `:if`, `:concat`, `:at`, `:cons`, `:tail`, `:length`, `:<`) and ten symbolic primitives (`:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`, `:code-subst`, `:code-total`, `:code-less`, `:code-eval`), supplemented by dynamically defined homoiconic functions (`:fa`, `:fb`, ...), as detailed in [architecture.md](architecture.md) and [plan7-recursion.md](plan7-recursion.md). Quoted code is first-class syntax data that can be inspected, transformed, partially specialized with runtime values via `:code-subst`, and explicitly run under the VM budget via `:code-eval`; there is no arbitrary host `eval` or host-call escape hatch.

### 1.3 Frames and strict input availability

A `frame` contains a `schema`, a list of `rows`, and optional cross-row `pairs` and `anchors`. Each row $\omega = (\mathrm{key}_\omega, \mathbf{x}_\omega, A_\omega(Y))$ has three fields:

- **`row-key` ($\mathrm{key}_\omega$):** A unique row ID used by the harness to keep repeated inputs distinct and to reference rows in `pairs` and `anchors`. Candidate programs cannot read `row-key`; any table or quotient lookup must compute its key or index from `row-known`.
- **`row-known` ($\mathbf{x}_\omega$):** The input values passed to the candidate program, in `schema-inputs` order.
- **`row-requirement` ($A_\omega(Y)$):** A Boolean AST over `(var 0 target-type)` that checks the candidate's output $Y$. When `pullback-frame` bakes parent observations into $A_\omega(Y)$ as literal constants while passing only a subset of inputs to the child, those constants are visible only to the checker, not to the child program.

`singleton-requirement` and `set-requirement` build equality (`=`) and membership (`:member`) checks. `extract-allowed-values` extracts explicit target values from these (and from complete tuple-coordinate constraints), returning `:unknown` for general predicates, which the VM evaluates directly rather than reducing to a value list.

`lookup-model`, `quotient-model`, `partition-model`, and `corpus-abstraction-model` return ordinary ASTs (with no wrapper struct); `lookup-model` requires `schema-lookup-p` and explicit, non-conflicting target values for each input tuple. Search entry points (`start-search`, `make-observation-scope`, `start-synthesis`) deep-copy their inputs via `snapshot-frame` so later caller edits cannot alter an active run.

Finally, `pairs` (must-agree row links) and `anchors` (must-vary representatives) are ignored by exact synthesis (`start-search`); they only classify `observation-bucket` results (`invariant-p`, `informative-p`) and add pair-drift and anchor-collision bit penalties (`relational-linkage-residual`) during observation and heuristic search (`start-heuristic-search`, `condense-heuristic`).

### 1.4 One VM, several return contracts

All expression evaluation runs through the step-by-step `evaluation` state machine in `vm.lisp` (`start-evaluation`, `advance-evaluation`, `evaluate`). At any point an `evaluation` has status `:unknown` (still running or paused on budget), `:value` (finished), or `:error` (runtime failure); higher-level drivers report a paused run as `:cutoff`. To avoid re-checking syntax on every row, `start-program-validation` type-checks an expression once into a `validated-program`, which `start-validated-evaluation` reuses across inputs.

Search and synthesis drivers report events via a three-field `message` struct (`call-id`, `claim`, `evidence` in `enumerate.lisp`), where `evidence` is a producer-specific payload (a `candidate`, a diagnostic plist, or recursive node metadata) while live continuation cursors stay on the job struct itself. Law validation (`laws.lisp`) uses its own `law-validation` state and `law-certificate` structs.

Work budgets come in two forms:
- **Resumable jobs** (`resume-search`, `resume-synthesis`, etc.) take an **absolute cumulative** work limit and preserve their state so they can be resumed later.
- **Synchronous helpers** (`fold-constants`, `infer-fibers`, view helpers) take a **per-call** budget via `with-work-limit` and return `:cutoff` if exhausted, without saving a resumable cursor.

Host-side setup steps (such as child-node pullback and folding in `prepare-synthesis-node`) run atomically in Lisp, record their tariff in a `debt` counter, and drain that debt against the budget before publishing their results. Thus work limits enforce deterministic accounting parity, not OS-level thread preemption.

### 1.5 Description, execution, and discovery costs

Current versions are `+encoding-version+ = 7` in `codec.lisp`, and `+tariff-version+ = 10`, `+simulator-version+ = 6` in `vm.lisp`.

Encoding v7 uses Elias delta positive integers, zigzag signed integers, typed headers, two-bit AST tags, and extended four-bit opcodes. The header includes input IDs as well as types; body references use input positions. Thus body cost can be invariant to renaming while header cost changes. `encode-model` and `decode-model` serialize ordinary expressions, including constructing lookup/partition/corpus expressions.

Work uses structural visits and operand widths, independently of compressed size. Small-field arithmetic ($p\le257$) has unit primitive cost; integer multiplication/division cost the product of operand widths, and addition/subtraction the maximum width. Larger fields add a modular penalty. VM validation, data traversal, and checking contribute separate work.

The implemented exact candidate objective is

$$
J_{\mathrm{exact}}(M)=S(M)+\lambda_{\mathrm{run}}W_{\mathrm{run}}(M).
$$

`candidate-score` implements it for exact search (`start-search`) and recursive root selection (`start-synthesis`). `propagation-search` ranks accepted candidates by description bits (`candidate-size`) alone. Heuristic search adds the exception and relational residual cost in Operation 4, breaking score ties by smaller program bits. View APIs rank **description bits first and runtime second**, with no `run-weight` argument.

The research procedure criterion is

$$
J_{\mathrm{procedure}}(P)=J(M_P)+\lambda_{\mathrm{search}}W_{\mathrm{search}}(P).
$$

Discovery work is reported separately from exact candidate selection. This criterion is not yet an automatically learned controller objective. Reusable-policy acquisition and amortization must be reported explicitly in future experiments.

### 1.6 Epistemic grades

`law-validation-status` distinguishes `:unknown`, `:refuted`, `:vacuous`, `:conjecture`, and `:validated`. A completed exhaustive supported finite-domain check with active guard support yields `:validated`; explicit samples yield at most `:conjecture`, even when they enumerate a complete finite grid. An unfinished check remains unresolved.

A `law-certificate` stores `snapshot`, `evidence`, `assignments`, `active`, and `work`. Consumers compare snapshots and versions. Empirical observation scopes carry `:replayed-observations`; they are not law certificates.

A bounded partition proposal, a detected conflict, and a cutoff are different claims. In particular, an expression not simplifying to false is not a satisfiability proof, and exhausting a work budget is not a proof that no solution exists.

## 2. The Four-Operation Mathematical Framework

### Nomenclature & Kernel Mapping {#sec-nomenclature}

Uppercase $X,Y,Z$ denote symbolic variables; lowercase $\mathbf{x}_\omega,y_\omega,z_\omega$ denote concrete values.

| Symbol | Meaning | Representation |
| :--- | :--- | :--- |
| $\Gamma,D,\tau$ | Schema, ambient arithmetic domain, semantic type | `schema` and type S-expressions |
| $\Omega,\omega$ | Frame and occurrence row | `frame`, `row` |
| $A_\omega(Y),B_\omega(Z)$ | Parent and child requirements | Boolean ASTs over target variable 0 |
| $M(e,\omega)$ | Candidate outcome on a row | VM evaluation / retained observation outcome |
| $\mathrm{Fiber}(\omega)$ | Accepted values $\{z:B_\omega(z)=\mathrm{true}\}$ | Predicate, sometimes an explicit finite set |
| $\Omega_k,j_\omega$ | A proposed row block and its index | Partition, fiber classes, label list |
| $p,\theta_\omega$ | Shared reconstruction template and instance substitutions | AU pattern/substitutions or table/index residual |
| $d(X,Z)$ | Forward decoder of a child value | Typed AST with a fresh child variable |
| $q(K,C),G(K,C)$ | Solver witness and applicability guard | Synthesized ASTs and validation records |
| $\hat\pi,\varepsilon$ | Heuristic expression and training exceptions | `heuristic-model` |

### Key conceptual distinctions

**Unary requirements versus cross-row conservation.** A row requirement $A_\omega(Y)$ tests a single row's output in isolation. By contrast, `pairs` require two rows to produce the *same* output ($M(e,\omega_a)=M(e,\omega_b)$) without fixing what that value is, and `anchors` require at least two representative rows to produce *different* outputs so a constant function cannot trivially pass. Passing per-row requirements does not imply pair invariance, and finding an invariant observable does not pin down a unique target function.

**Pullback versus inversion.** Both move a parent constraint backward through an outer decoder $Y=d(\mathbf{x}_\omega,Z)$, but in different ways. **Pullback** (`pullback-frame`) substitutes the decoder expression directly into the parent check to form $B_\omega(Z)=A_\omega(d(\mathbf{x}_\omega,Z))$. This requires no inverse function and preserves the entire set of valid $Z$ values—whether empty, unique, or multi-valued (such as integer division $Z/2=1 \implies Z\in\{2,3\}$)—though child search still has to run $d$ to test each candidate. **Inversion** (a learned witness solver $z=q(k,c)$ in `laws.lisp`) directly computes *one* solution value $z_\omega$, turning the child check into a direct target `(= Z 'z_w)`. When $d$ is many-to-one, picking a single witness drops the other valid solutions unless uniqueness is also certified (`validate-arithmetic-solver`).

**Factorization versus a partition hypothesis.** Factoring concrete values or syntax (`quotient-values`, `anti-unify`) immediately produces a shared template $p$ and per-row arguments $\theta_\omega$ whose exact reconstruction $\mathrm{Apply}(p,\theta_\omega)=t_\omega$ is verified on the spot. By contrast, when `infer-fibers` merges pulled-back row predicates $B_\omega(Z)$ into a block $\Omega_k$, it only checks that their conjunction $\bigwedge_{\omega\in\Omega_k} B_\omega(Z)$ does not simplify to `nil`. That grouping is only a **partition hypothesis** (`:feasibility :unresolved`); it becomes a verified factorization only after downstream search finds a concrete witness for each block, synthesizes a selector over runtime inputs, and checks the reconstructed parent model.

**Value fibers versus row blocks.** A **value fiber** $\mathrm{Fiber}(\omega)=\{z:B_\omega(z)=\mathrm{true}\}$ is the set of allowed target values for a *single* row $\omega$. A **row block** $\Omega_k\subseteq\Omega$ is a set of *rows* grouped together to share one latent value $c_k$, which is possible if and only if their value fibers overlap:

$$
\exists c_k\;\forall\omega\in\Omega_k,\ B_\omega(c_k)=\mathrm{true}.
$$

Because `fold-constants` is conservative and budgeted, a block conjunction not folding to `nil` only means no contradiction was found—not that a shared witness $c_k$ is guaranteed to exist.

**Extensional versus intensional descriptions.** Training-time helpers like `quotient-values` and `partition-rows` produce **extensional** descriptions: a list of block representatives plus an explicit array of row indices or permutations recording which block each row came from. Because a deployed program is not given the physical row index $\omega$ at runtime, turning a partition into an **intensional** runtime program requires either synthesizing a selector expression over the row's actual inputs (`row-known`) or paying the bit cost to embed an explicit lookup/gather table (`lookup-model`, `quotient-model`, `partition-model`).

**Reconstruction residuals versus heuristic errors.** The word "residual" refers to two different roles in Operations 2 and 4. In **lossless factorization** (Operation 2), the residual $\theta_\omega$ (an AU hole substitution or quotient index) is *part of the program* required to reconstruct every row exactly. In **heuristic condensation** (Operation 4, `start-heuristic-search`), the exception residual $\varepsilon$ is a list of correction packets for rows (or pairs/anchors) where the approximate program $\hat\pi(X)$ missed. The search pays the bit cost $S(\varepsilon)$ during training to trade off program size against accuracy (and keeps $\varepsilon$ in `heuristic-model` for inspection or Stage B refinement), but deploying `heuristic-program` alone omits $\varepsilon$.

**Generated linkage.** When a partition or fiber clustering groups rows into blocks (`partition-pairs-and-anchors`), each block with $\ge 2$ rows generates a chain of must-agree `pairs` linking its rows, plus one representative `anchor` key (retained only when at least two multi-row blocks exist). For `classify-observation-bucket` to mark an observable `informative-p`, it must agree on all `pairs` and differ across at least one pair of `anchors` (it need not take distinct values on *every* block). Both `observation-bucket` and `start-heuristic-search` also score pair drift and anchor collisions in bits via `relational-linkage-residual`. One-to-one row transforms (`pullback-frame`, `project-frame-rows`, `context-label-frame`, `shuffle-frame-rows`, `propagate-requirements`) preserve `pairs` and `anchors` (and `infer-fibers` keeps existing linkage or installs its inferred block linkage), whereas row-subsetting transforms (`evaluate-guard-partition` branch subframes, `%synthesize-supplied-partition-view` shared-decoder parent frames, and `covered-frame`) drop them.

**Decoder scope.** An outer decoder $d(X,Z)$ is not restricted to a single primitive inverse: it can be any well-typed AST over the parent inputs $X$ and a fresh child variable $Z$ (including a tuple-valued $Z$ when a decoder combines multiple child outputs), while `bindings` specify which parent expressions $e_r(X)$ compute the child's runtime inputs. When a child solution $e_C$ is found, `compose-model` substitutes `bindings` into $e_C$ and $e_C$ into $d(X,Z)$ by plain AST inlining—so any binding referenced multiple times pays for its syntax and runtime evaluation at each occurrence (there is no implicit `let`-sharing or automatic outer-decoder enumeration).

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
    {\scriptsize AU, Subgraphs, Views, \texttt{infer-fibers}}
  };

  % Operation 4: Bottom Center-Right
  \node[op] (op4) at (3.6, -11.0) {
    \textbf{Op 4: Heuristics \& Orchestration ($W$ Control)}\\
    {\scriptsize $\min_{\hat{\pi}} S(\hat{\pi}) + S(\varepsilon) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(\hat{\pi})$}\\
    {\scriptsize Dependency \& recursive synthesis (3:1)}
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
  \draw[flow] (op2) -- node[lbl, below=4pt] {latent\\labels $j_\omega$} (op4);

  % Feedback loops back to Frame / Search / Pullback
  \draw[feedback] (op2.north) -- ++(0, 1.6) -| node[lbl, pos=0.25, above] {lifted templates $p$, views \& child frames} (matrix.south);
  \draw[feedback] (op4.east) -| (10.2, 1.6) -| node[lbl, pos=0.25, above] {selectors $\hat{\pi}(X)$, dependencies \& decompositions (3:1)} (frame.north);

\end{tikzpicture}%
}
\caption{Data flow and feedback loops connecting the Observation Frame $\Omega$, the resumable VM outcome matrix $M(e, \omega)$, and Operations 1--4 across \texttt{lisploop}.}
\end{figure}

### 2.1 Operation 1: Observational Conservation Across Frame Rows

Exact synthesis accepts an expression only if each candidate evaluation and each corresponding requirement check returns a value and the latter value is `t`:

$$
\forall\omega\in\Omega,\qquad A_\omega(M(e,\omega))=\mathrm{true}.
$$

`start-search` / `resume-search` implement bounded bottom-up enumeration or checking a declared expression list. `search-job-results` retains every accepted candidate. Optional checked rewriting can reuse witnessed rejections without discarding original syntax alternatives or their costs.

Observation search instead groups complete typed output vectors:

$$
e_1\sim_\Omega e_2
\iff
\forall\omega,\ M(e_1,\omega)=M(e_2,\omega)
\quad\text{with no errors or unfinished evaluations}.
$$

The equivalence is scoped to that snapshot. New evidence may distinguish old agreements, but requires a new observation scope/job; there is no automatic incremental bucket-refinement API.

For action invariance,

$$
\forall(a,b)\in\mathrm{pairs},\ M(e,a)=M(e,b)
$$

must hold, and informative invariants additionally vary across anchors. This excludes constants from `observation-invariants`, not from all synthesis APIs.

Law discovery proposes equations from observations, then validates them separately. Support masks for partial equations become Boolean `support-frame` targets. `start-guard-search` returns an ordinary search job resumed with `resume-search`. Guards must reproduce the observed support exactly; universal applicability requires a separate supported exhaustive law check.

### 2.2 Operation 2: Factorization and Latent Fiber Proposals

For witnessed objects, seek a shared representation $p$ and residuals $\theta_\omega$ with

$$
\mathrm{Apply}(p,\theta_\omega)=t_\omega.
$$

Compression is an objective, not a guarantee: template, selector, occurrence, and reconstruction overhead can make a factorization larger than its baseline.

**Term algebra.** `anti-unify` constructs a typed least general generalization within a common scope, memoizing repeated disagreements. Value and function-sorted holes are ordinary `hole` symbols. `compile-au-constructor` lowers the pattern into the symbolic DSL; `au-substitutions-frame` exposes substitutions as another synthesis problem. `retype-law` (backed by `retype-expr`, `retype-type`, and `retype-value` in `laws.lisp`) explicitly retypes laws and expressions across `(:gf p)` and `:int` (including nested tuples and sequences, reducing integers modulo $p$ while preserving `:int` index literals), whereas `anti-unify` itself does not erase types across schemas or primes automatically.

**Unaligned syntax.** `collect-tree-occurrences` records subtree paths and contexts. `discover-subexpression-abstractions` seeds patterns from compatible occurrence pairs, extends them with bounded/greedy correspondence choices, and builds reconstructing corpus expressions. Optional checked normalization supplies an alternate syntax corpus; original syntax remains a distinct reconstruction target.

**Sequences and tables.** `quotient-values` returns representatives and complete occurrence indexes. `partition-rows` stores original positions, and `reassemble-partition` checks restoration. `quotient-model` constructs `:gather` or `:at`; `partition-model` includes inverse permutation data. Multiplicity and order are retained.

**Requirement fibers (`infer-fibers`).** When pullback or reorientation leaves rows with multi-valued or relational predicates $B_\omega(Z)$, `(infer-fibers frame &optional ledger budget branch-limit)` searches for a partition of the rows into a small number of blocks $\Omega_k$ such that all rows in a block can share a single latent value $c_k$:

1. **Same-input tightening (`tighten-same-input-requirements`):** First, each row requirement is folded, and rows that have the exact same complete `row-known` input tuple have their requirements conjoined (since any deterministic function must output the same value on identical full inputs). Rows that simplify to `nil` are isolated as explicit conflict rows; the remaining identical requirements are grouped together and ordered with constrained predicates before unconstrained `'t` rows.
2. **Bounded branch-and-bound partition search:** Rather than making a single greedy pass—which can get trapped by merge order even though set intersection is associative (for example, on fibers $\{1,2\}$, $\{2,3\}$, $\{1,4\}$, and $\{3,5\}$, greedily merging $\{1,2\}\cap\{2,3\}=\{2\}$ strands $\{1,4\}$ and $\{3,5\}$ in three blocks instead of finding the two-block split $\{1,2\}\cap\{1,4\}=\{1\}$ and $\{2,3\}\cap\{3,5\}=\{3\}$)—`infer-fibers` runs a depth-first search (capped by `budget` and `branch-limit`, default `2048`) that tries merging each group into an existing compatible block or starting a new block. Candidate partitions are ranked by a three-level lexicographic proxy (not Hard EM, global MDL, or Shannon entropy):
   1. Fewest blocks $K$.
   2. Fewest total requirement body bits $\sum_k |\Omega_k|\,S_{\mathrm{body}}(B_{c_k})$ across rows.
   3. Largest block-size concentration $\sum_k |\Omega_k|^2$ as a tie-breaker.
3. **Return contract and unresolved feasibility:** `infer-fibers` returns `(values classes labels refined-frame partition status)`. Hitting `branch-limit` still returns the best partition found so far (`:search-status :cutoff`), whereas exhausting the total work `budget` returns `nil` proposal values and a `:cutoff` message. Because `fold-constants` is conservative, a block conjunction not folding to `nil` does not prove a shared witness $c_k$ exists, so `status` always marks `:feasibility :unresolved` until downstream synthesis finds a concrete witness and selector. The returned `refined-frame` replaces each row's requirement with its block conjunction and preserves existing `pairs`/`anchors` (or installs the block linkage from `partition-pairs-and-anchors`).

**Competing fiber hypotheses and inter-frame comparison.** Multiple frames often cover the **same underlying rows** $\omega\in\Omega$ while disagreeing on their fibers or on what generates them:

- **Unclustered vs. fiber-tightened frames (`start-selector-search`):** Pre-clustering fibers can hurt when an outlier singleton pulls an ambiguous row away from a simple global rule (for example, if row 0 allows $\{0,4\}$, rows $1..2$ follow $y=x_0$, and row 3 is an outlier $\{4\}$, `infer-fibers` merges row 0 with row 3 into $Z=4$, breaking $y=x_0$ on row 0). Thus the `refined-frame` from `infer-fibers` never overwrites the original frame; it competes as a parallel branch alongside direct search on the unclustered requirements.
- **Competing input projections (`dependency-proposals`, `start-dependency-search`):** Projecting `row-known` onto different feature expressions (`project-frame-rows`) changes which rows collide as "same-input" tuples during tightening, yielding different fiber intersections on the same dataset.
- **Competing outer decoders (`heuristic-decompositions`, `discover-partition-views`, tentative vs. fallback propagation):** Pulling $\Omega$ back through different decoders $d_1(X,Z)$ vs. $d_2(X,Z)$ (such as an additive displacement $Y=\hat\pi(X)+Z$ vs. a conditional patch $(\texttt{if } G(X)\;\hat\pi(X)\;Z)$ where covered rows fold to $B_\omega(Z)=\texttt{'t}$) produces child frames over the same rows whose fibers live in incommensurable target spaces.

Because local child metrics are not comparable across different decoders or projections (a child frame with many `'t` rows looks trivial locally while hiding outer-decoder cost), **inter-frame comparison always goes through root reconstruction**:

- **During search (`node-priority` in `synthesize.lisp`):** Under `:policy :heuristic`, each child frame is condensed into a Stage A heuristic $\hat\pi_i$, composed through all ancestor decoders back to the root input space, and ranked by **full-path price**: composed root program bits + child residual bits ($S(M_{\mathrm{root}}(\hat\pi_i)) + S(\varepsilon_i) + \lambda_{\mathrm{run}}W_{\mathrm{run}}$).
- **At completion (`synthesis-verification-step`, `price-view-combinations`):** Every child candidate is composed into a root expression and verified against the **original root requirements** $A_\omega(Y)$.
- **Cross-branch sharing and pruning:** Within a `synthesis-job`, two branches that produce the exact same child `(frame, language)` (`child-scope-signature`) share a single child search (`synthesis-job-scope-cache`, `:subproblem-reused`) while still pricing their own parent reconstructions. Conversely, if a pure dependency projection fails because a subset of rows $(k_1,\dots,k_m)$ has incompatible fibers, `(parent-id k_1 ... k_m)` is recorded in `synthesis-job-nogoods` to immediately prune any sibling projection that aliases those same rows. Outside of nogood pruning and exact scope caching, sibling frames that disagree on how to cluster ambiguous fibers do not vote or merge across branches—they compete as independent lanes judged at the root.

### 2.3 Operation 3: Reorientation, Pullback, Conservative Simplification, and Propagation

#### 2.3.1 Causal reorientation

`orient-observations` chooses known and target columns from recorded tuples, without simulation. It preserves every occurrence. Projecting away an input can create conflicting requirements; the function does not turn those conflicts into existential target sets automatically.

`orient-arithmetic-requirements` uses a recorded forward relation and a chosen unknown operand to build the corresponding forward predicate. Multiple or absent solutions remain expressed by that predicate.

#### 2.3.2 Pullback and composition

For parent inputs $X$, child target $Z$, decoder $d$, and bindings $e_0(X),\ldots,e_r(X)$,

$$
B_\omega(Z)=A_\omega(d(\mathbf{x}_\omega,Z)),\qquad
\mathbf{x}^{C}_\omega=(e_0(\mathbf{x}_\omega),\ldots,e_r(\mathbf{x}_\omega)).
$$

`pullback-frame` substitutes the closed parent observations, remaps the child target to variable 0, evaluates bindings, and preserves the parent frame's `pairs` and `anchors` linkage across the 1-to-1 row mapping (as do `project-frame-rows`, `context-label-frame`, and `propagate-requirements`). It returns the raw predicate and does not invoke a solver or fold it.

A child solution reconstructs as

$$
M_{\mathrm{parent}}(X)=d(X,e_C(e_0(X),\ldots,e_r(X))).
$$

This is ordinary AST substitution. Root verification remains necessary, especially when child requirements came from tentative narrowing.

#### 2.3.3 Conservative folding and checked conflicts

`fold-constants` in `requirements.lisp` evaluates closed subtrees under one local budget. It retains expressions on errors or unfinished evaluation. Totality checks gate reductions that would erase or reorder potentially partial computations. Finite-set intersection, equality substitution, and tuple reconstruction are supported; literal-table inversion is not.

`frame-conflict-p` folds each row and conjunctions on identical inputs, returning `(values conflict folded-frame)`: the primary value is either a `frame-conflict` with kind `:unsatisfiable-row` or `:incompatible-rows`, or `nil`, and the second value is a fresh `frame` carrying the folded row predicates when no conflict is found. It neither mutates the input frame in place nor proves all remaining predicates satisfiable. `prepare-synthesis-node` installs `folded-frame` (and narrows it via `propagate-requirements` when a propagator library or solver is present) so child searches and nested pullbacks receive simplified predicates.

#### 2.3.4 Dual-grade propagation and 3:1 scheduling {#sec-3-to-1-scheduling}

A `propagator-library` (`prepare-propagator-library`) registers learned inverse rules (`arithmetic-propagator`), each keyed by `(domain, operator, position)` and carrying a solvability guard $G(k,c)$ and witness expression $q(k,c)$. `validate-arithmetic-solver` checks both **witness soundness** ($G(k,c)\implies f(k,q(k,c))=c$) and **fiber uniqueness** ($G(k,c)\implies [f(k,z)=c \iff z=q(k,c)]$). Rules exhaustively validated on a finite domain are marked `certified-p`; rules whose uniqueness law is validated or holds on samples are marked `unique-p`.

During child preparation, after `pullback-frame` (and `fold-constants` when pre-folded) exposes row predicates over the child target, `propagate-requirements` scans each row's top-level `AND` conjuncts (never under negation). Whenever a conjunct matches `(= (op K T) 'c)` or a singleton `(member (op K T) '(c))` with one closed operand $K$ (either already a literal `'k` or a closed parent subtree evaluated once to `'k`) and one open term `T` (the child variable, a tuple slot `(at Z 'i)`, or a nested call), `solve-learned-equality` selects the matching `(op, position)` rule, evaluates $G(k,c)$ and $q(k,c)$ in the VM (forward-checking $f(k,w)=c$ if not `certified-p`), rewrites the conjunct to `(= T 'w)`, and loops until nested operators unwind; a subsequent fold then reassembles tuple slots.

When every applied rule has `unique-p = t`, narrowing is an exact replacement. If any applied rule lacks uniqueness (`unique-p = nil`, e.g., integer division $Z/2=1\implies\{2,3\}$ where $q$ picks only $Z=2$), `prepare-synthesis-node` spawns a `:fallback` sibling that keeps the un-narrowed pullback frame. In standalone `start-propagation-search` (`enumerate.lisp`), every fourth quantum is similarly reserved for the original fallback frame (just as recursive synthesis reserves every fourth quantum for the root, and `:locality` reserves every fourth pair selection), ensuring an uncertified shortcut cannot permanently block a valid solution.

### 2.4 Operation 4: Heuristic Condensation, Dependencies, and Search Control

`start-heuristic-search` / `resume-heuristic-search` in `synthesize.lisp` interleave observation, requirement checking, correction extraction, and ranking under one cumulative ledger. `condense-heuristic` in `factor.lisp` is the synchronous convenience wrapper returning a best completed model and status.

The search scores the original requirements, without silently tightening them or selecting a single witness before checking. When `check-requirement` returns `t` on row $i$ (or when the row requirement is unconstrained `(lit :bool t)`), the row incurs zero unary residual bits (even if `extract-allowed-values` returns `:unknown`). When a prediction $\hat{y}_i$ fails row $i$'s requirement $A_{\omega_i}$ (or errors), `extract-allowed-values` extracts explicit witnesses $\mathrm{Allowed}(A_{\omega_i})$ (including requirements inverted into explicit witnesses by M4's learned `propagate-requirements` solver during child preparation; if no explicit witness list is available, the candidate is rejected on that row). Otherwise, the miss is priced by the **Correction Encoder / Pricer** (`correction-packet`, `apply-correction-packet`, `correction-bit-size`, `select-closest-witness` in `frame.lisp`):

$$
S_{\mathrm{corr}}(\hat{y}_i, A_{\omega_i}, \tau)=
\min_{w\in\mathrm{Allowed}(A_{\omega_i})}
S_{\mathrm{corr}}(\hat{y}_i, w, \tau),
$$

minimizing correction bit length across all explicit witnesses in $\mathrm{Allowed}(A_{\omega_i})$ (so set-valued requirements are invariant to witness list ordering), with total unary row cost including the 1-based physical row-index prefix $L_+(i+1)$:

$$
S_{\mathrm{rows}}(\varepsilon)=\sum_{i\in I_{\mathrm{miss}}}
\Bigl[L_+(i+1)+S_{\mathrm{corr}}(\hat{y}_i, A_{\omega_i}, \tau)\Bigr].
$$

Specifically:

- **Integers (`:int`):** encodes the signed difference $\delta = w - \hat{y}_i$ with bit cost $L_{\mathrm{int}}(\delta) = L_+(\mathrm{signed\text{-}code}(\delta))$.
- **Prime fields (`(:gf p)`):** encodes the centered modular Lee displacement $\delta = \mathrm{centered\text{-}mod}(w - \hat{y}_i, p) \in [-\lfloor p/2\rfloor, \lceil p/2\rceil - 1]$ with bit cost $L_{\mathrm{int}}(\delta)$, rather than a flat $\lceil\log_2 p\rceil$ constant.
- **Tuples (`(:tuple ...)`):** encodes a componentwise correction packet where unchanged coordinates ($\hat{y}_{i,j} = w_j$) pay 1 bit (`L_int(0) = 1`) and changed coordinates pay $S_{\mathrm{corr}}(\hat{y}_{i,j}, w_j, \tau_j)$.
- **Other domains (`:bool`, `:seq`, `:code`) or single-value evaluation errors:** fall back to replacement bit cost $L_\tau(w)$.

When the frame also carries relational linkage (`frame-pairs` and/or `frame-anchors`), `relational-linkage-residual` in `enumerate.lisp` extends pair invariance and anchor diversity from Boolean Delta/Heaviside indicators to bit metrics over the post-row-correction values $\tilde{y}$ (where row $i$ uses its selected witness $w_i$ if row $i$ had a unary correction, and $\hat{y}_i$ otherwise):

1. **Intra-fiber / transition pair drift:** each linked pair $(\omega_a,\omega_b)\in\mathrm{pairs}$ with $\tilde{y}_a \ne \tilde{y}_b$ pays index cost $\max(L_+(i_a+1),L_+(i_b+1))$ plus $S_{\mathrm{corr}}(\tilde{y}_a, \tilde{y}_b, \tau)$ (or $L_\tau(\tilde{y}_b)$ / $L_\tau(\tilde{y}_a)$ when one endpoint errored, and $1+\mathrm{type\text{-}bit\text{-}size}(\tau)$ when both errored and neither endpoint was already overridden by a unary row residual).
2. **Cross-fiber anchor collision (anti-collapse):** each anchor $\omega_{r_m}\in\mathrm{anchors}$ whose output collides with an earlier anchor ($\tilde{y}_{r_m}=\tilde{y}_{r_j}$ for $j<m$) or errors pays $L_+(i+1)+\mathrm{minimum\text{-}disambiguation\text{-}bit\text{-}size}(\tau)$ across each row $i$ in its pair-connected component $G(\omega_{r_m})$ that was not already overridden by a unary row residual, preventing constant collapse from scoring zero residual bits on relational frames.

For total residual entries $\mathcal{R}$ (unary entries `(row-key . witness)` plus relational entries `((:pair a b) . packet)` and `((:anchor k) . :disambiguate)`),

$$
S(\varepsilon)=
\begin{cases}
0,&\mathcal{R}=\varnothing,\\
L_+(|\mathcal{R}|+1)+S_{\mathrm{rows}}(\varepsilon)+S_{\mathrm{pairs}}(\varepsilon)+S_{\mathrm{anchors}}(\varepsilon),
&\mathcal{R}\ne\varnothing,
\end{cases}
$$

and the heuristic objective is

$$
J_{\mathrm{heuristic}}(h)=S(h)+S(\varepsilon)+
\lambda_{\mathrm{run}}W_{\mathrm{run}}(h).
$$

> **Design Note (Stage A Extensional Pricer vs. Stage B Intensional Synthesis & Pluggable Metrics):**
> The residual cost $S(\varepsilon)$ above serves as **Stage A** of a two-stage correction architecture: it prices *extensional* literal correction packets (differences, Lee displacements, componentwise tuple deltas, and relational pair/anchor corrections) in $O(|\Omega|)$ time to rank candidate branches before committing recursive synthesis budget (**Stage B**, where structured residuals are synthesized into intensional sub-programs via pullback). In general, Stage A may need to accept **pluggable DSL metric primitives** (or problem-supplied metric programs, since some problems specify their evaluation metric explicitly) rather than relying solely on the built-in type-directed difference codec. We defer the pluggable DSL metric hook for now, as it is likely to be unified with general search reentrancy (see [prompt4.md](prompt4.md) §8.b).
>
> Stage A runs at every node on that node's own pulled-back frame. A decoder that changes representation (for instance mapping to an angle) therefore has its residual priced in the new space, using witnesses that the learned library exposes by inverting the decoder; where no learned rule applies, a missed symbolic row leaves the candidate unpriced rather than being priced by a host-coded inverse. The routing priority adds the candidate composed to the root to the child's residual bits, so branches in different spaces compete in one currency. This price is one step deep: an expensive intermediate residual may condense after further expansion, which is why expansion is recursive and the price only orders work rather than pruning it.

A `heuristic-model` retains program, residual, exactness flag, program/residual bits, runtime, and score. Deployment of `heuristic-program` alone omits corrections. `heuristic-exact-p` means no unary or relational residual exceptions ($\mathcal{R}=\varnothing$).

Dependency search is explicit:

- `dependency-proposals` creates empty-input and individual-coordinate decompositions by default, or uses supplied feature expressions.
- `start-selector-search` optionally adds fiber and dependency proposals alongside direct root search.
- `start-dependency-search` first enumerates feature expressions, selects observational representatives, then starts direct and feature-conditioned synthesis. It does not implicitly call `infer-fibers` or heuristic condensation.

Learning a policy from continuation traces, generating locality keys, and deploying descriptors to prioritize library entries remain research extensions. The current controller does not consume `heuristic-model` priorities.

### 2.5 Non-Monotonic Pathways, Distributed Costing, and Search Policy {#sec-mountain-passes}

A useful decomposition may initially increase syntax or discovery work: it can introduce a feature basis, branch selector, reconstruction shell, or symbolic residual problem. Local immediate compression is therefore not required.

The recursive controller retains all accepted child candidates in `search-job-results`, reconstructs them through the entire ancestor chain, and prices verified root expressions. Child-local optima cannot hide a better complete reconstruction. View synthesis similarly considers assembled branch combinations, using its bits-first objective.

Work is charged as preparation, enumeration, execution, checking, and reconstruction proceed. Search costs and final runtime are not interchangeable. Inlining can duplicate an expensive feature, so staged synthesis does not by itself establish runtime reuse.

Current node selection is deterministic: root reserve, pending verification priority, then round-robin children. Search-policy learning is an M8D objective. The research aim is to learn useful paths through temporary expansions; the existing scheduler does not prove those paths optimal.

## 3. Architecture of the Nine-Module Kernel and Worked Examples

`load.lisp` loads `package.lisp`, then the following modules. The package exports APIs; it does not define their implementations or the version constants.

| Order | Module | Responsibility |
| :--- | :--- | :--- |
| 1 | `ast.lisp` | Types, symbols, expressions, metadata, structural bit/work helpers |
| 2 | `codec.lisp` | Expression packets, sizing, encoded ordering |
| 3 | `vm.lisp` | Ledger, work limits, evaluator, static program validation |
| 4 | `requirements.lisp` | Conservative folding and conjunction analysis |
| 5 | `frame.lisp` | Frames, requirement constructors, conflicts, pullback/composition, partitions and linkage |
| 6 | `enumerate.lisp` | Enumeration, exact/observation search, messages, propagation-search adapter |
| 7 | `factor.lisp` | AU, fiber proposals, corpus models, heuristic wrapper, views and locality |
| 8 | `laws.lisp` | Laws, guards, rewrite libraries, arithmetic solvers and propagation |
| 9 | `synthesize.lisp` | Resumable heuristic, recursive, selector, and dependency search |

`tests/support.lisp` and suite-local fixtures are test infrastructure, not kernel modules. `benchmark.lisp` is a separate consumer. Rewrite program caches belong to individual `rewrite-library` objects; they do not provide global DAG reuse.

### 3.1 Typed syntax and packet sizing

After loading `load.lisp` and entering package `lisploop`:

```lisp
(let* ((field (gf 5))
       (inputs (list (cons 0 field) (cons 1 field)))
       (x0 (var 0 field))
       (x1 (var 1 field))
       (expression (app (op :+ field) x0
                        (app (op :+ field) x1 x1))))
  (values (body-size expression inputs)
          (description-size expression inputs)
          (length (encode-model expression inputs))))
```

The body has 21 bits; the last two values agree. This example uses cached structural metadata after validation. Quoting the expression as a syntax literal adds the actual literal/type/encoding costs.

### 3.2 Pullback, explicit simplification, and partiality

For $A(Y)\equiv(Y=1)$, $X_0=2$, and $d(X_0,Z)=(X_0+X_0)+Z$, `pullback-frame` yields the raw requirement

$$
(=\, (+\, (+\, '2\, '2)\, Z)\, '1).
$$

An explicit `fold-constants` call can reduce the closed addition to `'4`. The returned folded AST must be installed or otherwise used to avoid future recomputation; `frame-conflict-p` alone does not update the original requirement.

The diagonal decoder $(\mathrm{tuple}\ Z\ Z)$ cannot satisfy target $(2,3)$. Conservative tuple/equality folding detects the contradiction. Partial division or indexing errors, including under negation or conditionals, retain their error behavior rather than becoming false.

A solver for $Z/2=1$ over integers may propose $Z=2$, but $Z=3$ is also a witness. The tentative adapter retains both possibilities through the original fallback.

### 3.3 Latent offsets and explicit dependencies

The lifting suites use observations of the form $y_{r,t}=\iota(t)+a_{j(r)}$, or $t+a_{j(r)}$ over integers. A supplied offset decoder and learned arithmetic propagation expose requirements on the latent offset. Fiber proposals can group compatible rows; context frames then expose labels or representatives as selector targets.

A $t$-only dependency can be contradictory while an occurrence/context coordinate permits prediction. A paid lookup and a synthesized selector are distinct choices. The suite explicitly composes and verifies the chosen selector; `infer-fibers` does not automatically deploy one.

### 3.4 Work debt and recursive reconstruction

Multiplying two integers of width 129 has primitive arithmetic tariff $129^2=16641$, in addition to validation/evaluation overhead. The VM drains that instruction debt before executing it. The tests compare one-unit resumes with uninterrupted execution, including error paths.

The concrete nested fixture `recursive-control` in `tests/refactor.lisp` uses rows $x\mapsto x+3$, an outer decoder $x+Z$, an inner decoder $1+Z$, and a conflicting empty-context alternative. The controller preserves the branches across cutoffs, reports the conflict, and reconstructs candidates through the complete ancestor chain.

The parent-pricing control uses an expensive context binding whose child variable is locally shorter than a literal. After inlining, the literal is the smaller parent. Retaining all accepted child candidates allows the controller to choose it.

## 4. The Nine Milestones: Implemented Experiments and Remaining Work {#sec-milestones}

The following sections identify current evidence without treating historical traces or planned examples as current executable runners. Run `make test` for all core suites; `tests/run.lisp` accepts suite names and milestone aliases `m1` through `m7`.

### 4.1 Milestone 1: Core Typed Synthesis, Pullback, Views, and AU {#sec-m1}

**Question.** Can bounded search synthesize compact typed programs, preserve occurrence information, and resume exactly under work limits?

**Implemented.** `make-language` specifies operators, a literal vocabulary (`:all` by default), and additional typed constants. The default arithmetic grammar contains addition and multiplication. Enumeration covers body-size tiers; exact search checks every row and ranks accepted candidates by bits plus optional runtime weight. Supplied proposal lists use the same checking path.

Reorientation, joint tuple-valued pullback, composition, quotient/partition reconstruction, and aligned AU are available as separate operations. Lookup tables require explicit permission and available keys.

**Evidence.** `tests/core.lisp` and `tests/codec.lisp` cover independent tiny-grammar enumeration, packet roundtrips and malformed inputs, integer payload bounds, reconstruction, repeated occurrences, partial checker interruption, and batch/unit parity. Particularly relevant tests include `joint-pullback-and-composition`, `views-preserve-occurrences`, `exhaustive-tiny-aligned-au-reference`, and `at-operator-tuple-projections-and-quotient-pullback`.

### 4.2 Milestone 2: Observational Equivalence and Informative Invariants {#sec-m2}

**Question.** Can execution identify conserved observables without confusing sampled agreement with a universal law?

**Implemented.** `transition-probes` reorients recorded transitions into paired before/after inputs without rerunning the transition. Observation jobs group complete output vectors and classify invariance and anchor diversity. Scope identity, types, versions, and input snapshots bound the evidence.

**Evidence.** `tests/observations.lisp` covers field and integer invariants, held-out replay, negative transitions, accidental agreements split by fresh evidence, storage-shuffle controls, outcome retention, errors, and resumption.

**Boundary.** In addition to Boolean `invariant-p` and `informative-p` flags, `observation-bucket` records metric `pair-bits`, `anchor-bits`, and `residual-bits` via `relational-linkage-residual`. Exact search (`start-search`) remains governed strictly by row requirements.

### 4.3 Milestone 3: Guarded Laws, Law Compression, and Symbolic VM {#sec-m3}

**3A — Laws and guards.** Observed equations and their support masks are proposed from execution. Boolean guard synthesis reproduces a support mask, and separate validation determines whether the guarded equation holds on a supported complete finite domain or only on samples. Tests cover zero divisors, lazy conditionals, non-transfer of field identities to integers, and guard scope.

**3B — Lossless law-corpus compression.** `make-law-corpus` packages actual equation and guard syntax. `propose-law-compressions` constructs alternatives using literals, repetition, and AU templates. The decoded corpus must preserve syntax, guards, and occurrences, not merely evaluate to the same Boolean results. Negative compression gain is allowed and tested.

**3C — Symbolic programs and checked rewriting.** Quoted expressions are inspected, matched, constructed, and substituted with `:code-*` programs. Rule transformers and propagator matchers use the same metered VM and validated-program boundary. Rewriting preserves relevant definedness and has a decreasing encoded syntax order; original alternatives remain available during search. `retype-law` translates scalar and tuple laws across prime fields and `:int`.

**Evidence.** `tests/laws.lisp`, `tests/guards.lisp`, `tests/compression.lisp`, `tests/symbolic.lisp`, and `tests/amortization.lisp` cover discovery, finite certificates, tuple-domain law validation/retyping/rewriting, exact reconstruction, symbolic pullback, typed constructors, scoped preparation caches, and amortization. `symbolic-pullback-learns-a-checked-transformation` uses syntax construction/equality, not a nonexistent `:code-eval` primitive.

### 4.4 Milestone 4: Algebraic Reorientation and Dual-Grade Propagation {#sec-m4}

**Question.** Can forward arithmetic evidence support learned inverse witnesses and guards, while preserving empty and multi-valued fibers?

**Implemented.** Arithmetic relation observation and reorientation expose either operand as the unknown. Witness and guard discovery use ordinary search. `validate-arithmetic-solver` checks both witness correctness and whole-fiber uniqueness. `prepare-propagator-library`, `as-propagator-library`, and `propagate-requirements` apply learned guards and witnesses inside pulled-back row requirements.

Certified field rules can replace applicable fibers equivalently. Tentative integer rules require forward verification and retain the original alternative whenever narrowing occurs. Guard-false, failed, or unsupported rows remain original predicates.

**Evidence.** `tests/algebra.lisp` exercises both operands of all four arithmetic operators in field/integer controls, independent references, incomplete evidence, solver certificates, and AU of actual same-scope solver families. `tests/propagation.lisp` covers wrong witnesses, division's multiple solutions, coupled requirements, fallback fairness, resumption, and amortization of expensive known contexts.

**Boundary.** Learned M4 solvers reach recursive synthesis and view orchestration through `propagate-requirements` (via the job-level `:library` of `start-synthesis`, per-branch `decomposition-solver`, or the `:solver` argument to view synthesis).

### 4.5 Milestone 5: Lifting, Fiber Proposals, and Dependency Selection {#sec-m5}

**Question.** Can compatible latent requirements and observable context produce useful intermediate concepts and selectors?

**Implemented.** Supplied outer decoders expose latent targets. `infer-fibers` proposes bounded partitions; `context-label-frame` projects labels through declared context bindings. Exact selectors, paid lookups, or lossy condensation can be composed explicitly and checked at the parent. Direct search competes with optional fiber and dependency proposals.

**Evidence.** `tests/lifting.lisp` covers repeated offsets, missing context, incompatible same-input requirements, empty and multi-valued fibers, bridge-versus-leaf partition choices, supplied and inferred lifting, and field/integer propagation. Historical `hard-em-...` test names refer to the current bounded partition implementation.

`tests/refactor.lisp` checks that full-input determinism does not silently become coordinate selection, that direct selectors can outperform a fiber proposal, and that feature expressions can be synthesized before selector search. Heuristic tests verify original-requirement acceptance and explicit outlier corrections.

**Boundary.** Non-refuted partitions are hypotheses; no global latent-identification or minimum-description guarantee follows.

### 4.6 Milestone 6: Abstraction at Aligned and Unaligned Positions {#sec-m6}

**Question.** Can repeated syntax be factored into reusable typed templates even when occurrences have different surrounding contexts?

**Implemented.** Aligned AU preserves repeated holes and can abstract compatible operators. Subtree occurrence records provide paths and contexts. Bounded pair-seeded search constructs templates, selects occurrences, and produces exact corpus reconstruction programs with residual syntax.

Validated rewriting can expose alternate syntax for abstraction. Compression of that normalized corpus is distinguished from reconstruction of the original corpus.

**Evidence.** `tests/abstraction.lisp` covers aligned controls, path indexing, spliced corpus packets, hidden occurrences, repetition-dependent compression, unrelated trees, randomized trials, and validated alternate syntax. `tests/symbolic.lisp` verifies lowering templates to DSL constructors.

**Boundary.** Correspondence discovery is bounded and greedy in parts. Learned abstractions are not automatically registered as callable new DSL primitives.

### 4.7 Milestone 7: Views, Reassembly, and Locality {#sec-m7}

**Question.** Can observable partitions and locality priors improve decomposition and abstraction search? The revised [prompt4.md](prompt4.md) additionally asks for learned ordering and meaningful approximate residuals; that broader goal is not yet implemented.

**Boolean views.** `evaluate-guard-partition` evaluates a supplied guard, produces true/false subframes, and returns a linked parent frame as its fifth value on a successful nontrivial split. `discover-partition-views` enumerates guards and deduplicates observationally equivalent/complement splits. It tries separate branch models and a supplied shared decoder independently.

Child candidates are reconstructed at the parent. `price-view-combinations` ranks assembled candidates by bits, then runtime. `discover-partition-views` includes a verified lookup baseline when `schema-lookup-p` permits it and the frame provides compatible explicit witnesses. The supplied-view helper does not add that baseline. Supplied-view and discovery wrappers share one additional-work budget and return a final status message; they are synchronous.

**Locality.** Without a key, tree indexes supply positions. A supplied `:locality-key` can produce equivalence classes or integer-list coordinates. `generated-space-distance` (an internal helper in `factor.lisp`) uses Manhattan distance for unequal, equal-length integer lists; equal keys and distinct scalar keys follow the coarse-class/rank rules in the source. A scalar key is not interpreted as an ordinary numeric distance.

Pair ordering (`schedule-occurrence-pairs`) prioritizes cross-tree pairs (`pair-cross-tree-p`) ahead of same-tree pairs before sorting by `pair-tree-dist`, `pair-rank-dist`, `pair-path-dist`, and `pair-depth-sum`. `:locality` retains every fourth selection for canonical order (`(= 3 (mod turn 4))`). `:locality-only` serves as a hard-cutoff negative control: it omits the 1-in-4 reserve, filters candidate pairs strictly to cross-tree pairs with `(<= (pair-tree-dist p) 1)`, and disables Step 2b multi-tree LGG relaxation (which is also skipped whenever `pair-budget` is non-nil). Step 3 of `discover-subexpression-abstractions` constructs and prices full packet models only for `:aligned-root` plus at most the top 8 `:subexpression` selections ranked by `abstraction-structural-score`. A host-function key is supported but its body is not VM-metered; DSL-key evaluation is metered. Neither key synthesis nor a complete policy-description objective is implemented here.

**Evidence.** `tests/views.lisp` covers supplied versus discovered views, separate/shared/lookup comparisons, ordered reassembly and physical-shuffle controls, computed linkage, co-local and distant planted occurrences, supplied parity and 2D keys, and preservation of tentative fallback alternatives. `tests/refactor.lisp` adds total-budget and shared-decoder-versus-conflicting-separate-branch controls.

**Remaining scope.** Stage A extensional correction pricing (`correction-packet`, `correction-bit-size`, `select-closest-witness`, and `relational-linkage-residual`) now prices ordered differences on `:int` and `(:gf p)`, componentwise tuples, set-valued fibers, and metric `frame-pairs`/`frame-anchors` linkage, while preserving `pairs` and `anchors` across 1-to-1 frame transforms. Pluggable DSL metric primitives (or problem-supplied metrics, likely tied to reentrancy per `prompt4.md` §8.b) and autonomous locality-key synthesis remain open extensions.

### 4.8 Milestone 8: Recursive Synthesis and Learned Search Preferences {#sec-m8}

**8A — Multi-step reconstruction and Stage A $\to$ Stage B residual pullback.** `start-synthesis` accepts explicit decomposition trees and preserves direct root search. Each child candidate is composed through every ancestor and verified on the original root. Intermediate expansion is permitted; the direct root bound does not cap a completed reconstruction obtained through separately bounded children.

The `decomposition` slots are `name`, `decoder`, `child-id`, `child-type`, `bindings`, `language`, `bound`, `children`, `fiber-p`, `solver`, and `fallback-p`. `prepare-synthesis-node` pulls every child back, folds it (`frame-conflict-p`), narrows it with the job library plus any branch `solver` (`propagate-requirements`), and folds again; the folded frame is installed on the child node. An ambiguous narrowing spawns a `:fallback` sibling that skips propagation. The library is part of the search, not of a particular proposal: any decoder whose pulled-back requirements expose a learned operator is inverted without being declared.

`heuristic-decompositions` and `start-heuristic-synthesis` bridge Stage A heuristic condensation to Stage B recursive synthesis by converting a non-exact `heuristic-model` $(\hat{\pi}, \varepsilon \ne \varnothing)$ into two complementary child `decomposition` proposals:

- **Additive / displacement residual decoder (`:heuristic-additive`):** when $\hat{\pi}(X)$ is total across the frame (`heuristic-total-p`) over `:int`, `(:gf p)`, or tuples thereof, constructs outer decoder $d(X, Z) = \hat{\pi}(X) + Z$ (with optional learned M4 `:solver`), exposing the displacement $Z = Y - \hat{\pi}(X)$ as the child target.
- **Conditional exception-patching decoder (`:heuristic-conditional`, anytime decision-list refinement):** converts the row hit/miss mask of $\hat{\pi}$ into a Boolean `support-frame`, groups guards observationally, and keeps the most covering sound hit or miss guard $G(X)$ (an exact separator covers every hit), then pulls $\Omega$ back through $d(X, Z) = (\texttt{if } G(X)\; \hat{\pi}(X)\; Z)$ (or $(\texttt{if } G_{\mathrm{miss}}(X)\; Z\; \hat{\pi}(X))$ when $G_{\mathrm{miss}}$ selects misses) so covered rows fold via `fold-constants` to `(lit :bool t)` (0 residual bits) and child synthesis focuses strictly on the uncovered exception rows.

**Recursive expansion.** Branch points are not confined to the root. `start-synthesis` accepts `:expand`, a function `(job node frame language heuristic-model ledger)` returning decompositions, and `:max-depth` (an integer, or nil for no limit). Expansion is lazy: once a node shallower than `max-depth` (root included) is prepared, expanding it becomes an agenda action alongside searching it. The branches are staged in a private ledger and published once that debt is paid. Conflicted nodes, scope-cache followers (whose canonical node expands the same frame), and nodes whose Stage A model is already exact are never expanded. `heuristic-expander` builds an expander from `heuristic-decompositions`, fed by the node's own Stage A model. A representation change therefore re-prices its residual in the child's space, and that residual can be condensed and branched again: an additive residual becomes a further displacement, and a conditional exception branch becomes the next entry of a decision list $(\texttt{if } G_1\; \hat{\pi}_1\; (\texttt{if } G_2\; \hat{\pi}_2\; Z))$. `start-heuristic-synthesis` is `start-synthesis` with `:policy :heuristic`, this expander, `:max-depth 2` by default, and optional selector proposals.

**Full-path pricing and anytime search.** Every node's price is its Stage A program composed through every ancestor's decoder and priced at the root, plus its own residual bits (plus weighted run work): the description length of a complete path, with the deepest residual standing in for whatever its subtree may still condense it to. Search and expansion actions are ranked by the same price over the whole tree, not per level; ties go to expansion, the cheaper lookahead, and every fourth child selection is round-robin over all actions. The root and any unprepared node are prepared before ranking, since an unpriced node cannot compete. Because the agenda is flat over all nodes, a parent need not inherit its children's prices: each child competes directly with its full-path price. With `:max-depth nil` the search is anytime: it deepens wherever full-path prices are lowest for as long as the budget lasts, `resume-synthesis` keeps the best verified candidate after every call, and incremental resumption reproduces an uninterrupted run. In `tests/refactor.lisp`, $y = x_0 + x_1 + x_2 + 1$ needs three nested residual spaces: it is not found at `:max-depth 2`, and is found without a limit with prices falling along the path, while a decoy sibling with a large residual is expanded only after the promising chain. In `tests/refactor.lisp`, $y = x_0 + x_1 + 1$ under an operator-free grammar has no solution at depth 1 and is reconstructed as $x_0 + (x_1 + 1)$ at depth 2: Stage A condenses $x_0$ at the root, $x_1$ in the first residual space, and $1$ in the second.

**8B — Continuations, explicit dependencies, and child-frame DAG reuse.** Node preparation, search, composition debt, and root verification are preserved across cumulative-budget resumes. `dependency-proposals`, `start-selector-search`, and `start-dependency-search` expose different ways to propose contexts. `finish-synthesis-preparation` indexes child problems by `child-scope-signature`; when an equivalent child `(frame, language)` has already been prepared (`synthesis-job-reused-subproblems`), the follower node attaches to the canonical child search (emitting `:subproblem-reused`) while still reconstructing and pricing every discovered child candidate through its own parent decoder and bindings.

**8C — Checked conflicts and sibling nogood pruning.** A false row or incompatible identical-input requirements stops a child before enumeration (`frame-conflict-p`). When a pure dependency projection (`decoder = (var child-id child-type)`) fails with `:incompatible-rows` on keys $(k_1, \dots, k_m)$, `(parent-id k_1 ... k_m)` is recorded as a reusable induced anchor nogood in `synthesis-job-nogoods`. Any subsequent sibling projection under the same parent whose bindings alias $(k_1, \dots, k_m)$ to the same non-error context tuple is immediately pruned with `:reused-nogood t` without pulling back or folding the full frame.

**8D — Condensation, heuristic agenda routing, and episode returns.** Resumable heuristic search (`start-heuristic-search`, `resume-heuristic-search`, `condense-heuristic`) prices unary and relational residuals via the Stage A correction encoder (`correction-packet`, `apply-correction-packet`, `correction-bit-size`, `select-closest-witness`, `relational-linkage-residual`), supporting ordered difference bits on `:int` and `(:gf p)`, componentwise tuples, order-independent witness selection on sets, and standalone or paired anti-collapse anchors. Under `:policy :heuristic` (or a supplied `priority-predictor`, a host function of the node, frame, language, and Stage A model), `prepare-synthesis-node` scores each child branch with a bounded Stage A heuristic lookahead probe (pricing the reconstructed root candidate plus child residual bits), immediately promotes any `heuristic-exact-p` child hit to root verification, and routes 3 of every 4 child selections to the lowest-priority child while reserving every 4th child selection for round-robin exploration. `synthesis-episode-returns` computes the realized return

$$
G_t=B_t-B_T-\lambda_{\mathrm{search}}(W_T-W_t)
$$

for every scheduling step recorded in `synthesis-job-trace`.

**Current tests.** `tests/refactor.lisp` includes twenty-two tests, covering partial-expression folding, snapshots, heuristic and recursive budget parity, nested `x+3` reconstruction, direct selectors versus fibers, parent-level candidate pricing, synthesized sum features, view budgets, synthesized inverse-grid witnesses, partition uncertainty, shared-decoder independence, correction encoding across ordered domains/tuples/sets, frame-linkage preservation with metric anti-collapse, standalone anchors with `apply-correction-packet` roundtrips and component deduplication, pulled-back child-frame folding and learned M4 solver propagation with heuristic scoring, Stage A $\to$ Stage B additive and conditional residual synthesis, heuristic agenda routing with unit-step parity and episode returns, conflict nogood sibling pruning with child-frame DAG reuse, requirement-level learned propagation (nested operators, tuple coordinates, ambiguous division), recursive heuristic expansion through two residual spaces, and anytime best-first expansion through three with incremental-resumption parity.

**Remaining open extensions:**

1. Enumerate arbitrary outer decoder shells autonomously under a declared grammar and budget. The additive and conditional shells are the two built-in expanders; others plug into `:expand`.
2. Support pluggable DSL metric primitives (or problem-supplied metric programs, unified with general search reentrancy per [prompt4.md](prompt4.md) §8.b). A metric and a decoder shell are two views of one correction code: the shell reconstructs a value from a residual, and the metric prices that residual before it is synthesized.
3. Decide when to stop expanding from evidence rather than a budget or `max-depth`, e.g. when a child's full-path price does not improve on its parent's. Currently such a branch is only deprioritised, never closed.

### 4.9 Milestone 9: Vocabulary and Library Retrieval {#sec-m9}

**Proposed question.** Can learned functions be exposed through opaque names and retrieved using compact symbolic descriptions of their behavior?

The current syntax VM, packet codec, AU constructors, and heuristic condensation are prerequisites. The operator vocabulary is fixed: no opaque `:f0` registry, callable learned-function installation, learned descriptor retrieval lane, or automatic library eviction exists.

A future experiment could acquire functions, pay for their definitions and execution, build behavioral probe frames, synthesize descriptors, and compare descriptor-guided retrieval with canonical search. Registration, description costs, scope validation, and amortization would need explicit implementation. This section is a research specification, not a report of completed M9 verification.

## 5. Research Decisions, Experiment Traces, and Literature Boundaries

### 5.1 Decisions and implementation limits

| Topic | Current contract |
| :--- | :--- |
| Representation | Ordinary typed ASTs; host structs for frames, jobs, and evidence |
| Correctness | Original row checks for exact proposals; explicit finite law certificates |
| Availability | Only declared inputs reach the candidate; keys and target-derived labels are not free context |
| Simplification | Explicit conservative folding; errors and unfinished evaluation remain distinct from false |
| Fiber inference | Bounded lexicographic proposal search with unresolved feasibility |
| Heuristics | Original-row acceptance plus Stage A correction-packet pricing (`:int` / `(:gf p)` differences, componentwise tuples, min-bit set witnesses, metric `pairs`/`anchors`) and Stage B additive/conditional residual pullback (`heuristic-decompositions`, `start-heuristic-synthesis`); pluggable DSL metrics deferred to reentrancy |
| Recursion | Supplied decompositions plus lazy, best-first per-node `:expand` actions to `:max-depth` or, with nil, anytime (`heuristic-expander`), child folding & job-level learned propagation (`propagate-requirements`), root reconstruction, cumulative budgets |
| Scheduling | Deterministic 1-in-4 root reserve + verification + round-robin (`:round-robin`) or full-path Stage A / host-function priority-predictor routing over search and expansion actions (`:heuristic`) with episode return tracking (`synthesis-episode-returns`) |
| Reuse | Library-local rewrite caches; within-job child-frame DAG scope sharing (`synthesis-job-reused-subproblems`) and induced anchor nogood sibling pruning (`synthesis-job-nogoods`) |
| Pricing | Complete ASTs pay inlining costs; view selection differs from weighted exact-search selection |

### 5.2 Verification and trace standard

Current test commands are:

```bash
make test
sbcl --script tests/run.lisp m1 m2
sbcl --script tests/run.lisp m3 m4
sbcl --script tests/run.lisp m5 m6 m7 refactor
```

The `m1` alias selects `core`; `m2` selects `observations` and `codec`; `m3` selects the law/guard/compression/symbolic/amortization suites; `m4` selects algebra and propagation. Later aliases select lifting, abstraction, and views. There is no `m8` alias; use `refactor` and the relevant supporting suites.

Tests print assertions and a pass summary. They do not emit the former standalone experiment-runner trace format. `benchmark.lisp` prints bounded search/dispatch measurements; Makefile benchmark targets write logs and source fingerprints. Historical reports must retain their recorded versions.

Future experiment traces should record:

1. Schema, input availability, frame/scope identity, grammar, supplied proposals, and bounds.
2. Exact artifacts, program bits, runtime work, discovery work, and evidence grade.
3. `ledger-counts` and `ledger-total`, including preparation, failed proposals, and verification.
4. Baselines and negative controls appropriate to the claim.
5. Encoding/tariff/simulator versions, source revision, cutoff state, and any acquisition/amortization assumptions.

This is a reporting requirement for new experiments, not a claim that every current API or test already emits all fields.

### 5.3 Literature and reference boundaries (`[R1]`–`[R11]`)

These references motivate the research directions. They do not establish that the corresponding full algorithms or guarantees have been implemented here.

- **[R1] MDL and two-part codes** (Rissanen 1978; Grünwald 2007): description-length objectives. The model packet is executable/serializable; the present heuristic exception cost is a narrower proxy.
- **[R2] Universal search and resource-bounded complexity** (Levin 1973; Schmidhuber 2004): explicit separation of description and computation. The implemented reserve schedule is not a proof of universal-search optimality.
- **[R3] Observational-equivalence synthesis** (Udupa et al. 2013, *TRANSIT*; Albarghouthi et al. 2013, *Escher*): execution-based grouping. Lisploop's buckets remain empirical and scoped.
- **[R4] Algebraic specification and rewriting** (Baader & Nipkow 1998; Jackson 2006): law validation and checked rewriting with definedness constraints.
- **[R5] Deductive synthesis** (Polozov & Gulwani 2015, *FlashMeta*): backward requirements. Lisploop separately synthesizes and grades arithmetic witnesses.
- **[R6] Constraint propagation** (Apt 2003; Steele 1980): propagation across computations. Certified equivalence and tentative witness proposals have distinct implementation paths.
- **[R7] Predicate invention and latent structure** (Muggleton 1995; Kemp & Tenenbaum 2008): concept lifting. The actual fiber routine is bounded partition search, not Hard EM.
- **[R8] Anti-unification and library compression** (Plotkin 1970; Reynolds 1970; Bowers et al. 2023, *Stitch*; Cao et al. 2023, *babble*): shared syntax and abstractions. This kernel uses typed AU and bounded occurrence proposals, not e-graphs or a general learned-function registry.
- **[R9] Condition synthesis** (Alur et al. 2015, *STUN*): piecewise programs. Current views use Boolean guard enumeration and explicit parent reconstruction.
- **[R10] Conflict-driven learning** (Marques-Silva & Sakallah 1999; Feng et al. 2018, *Neo*): motivation for M8 conflict reuse. Current conflicts are local checked diagnostics, not learned clauses.
- **[R11] Library learning** (Ellis et al. 2021, *DreamCoder*): motivation for M9. Descriptor learning and library retrieval remain proposed.

## Appendix A: Architectural Evolution and Audit Corrections

The earlier plans introduced the homoiconic representation, the four-operation organization, exact versus tentative propagation, and the distinction between model and discovery costs. [plan6.md](plan6.md) is the preceding research plan; [plan6-refactor.md](plan6-refactor.md) records implementation changes after its audit.

The post-audit implementation added `requirements.lisp` and `synthesize.lisp`, bringing the kernel to nine implementation modules. The split is not complete thematic relocation: requirement constructors remain in `frame.lisp`, and the heuristic wrapper and view orchestration remain in `factor.lisp`.

The following corrections supersede older implementation claims:

1. **Pullback and folding are separate.** Raw predicate substitution lives in `pullback-frame`. `frame-conflict-p` returns `(values conflict folded-frame)` without mutating its input frame in place, and `prepare-synthesis-node` installs `folded-frame` (after job-level `propagate-requirements` narrowing) on child synthesis nodes.
2. **Partial-expression behavior is preserved.** Closed evaluation errors or cutoffs are not rewritten into false, and table inversion is not a built-in simplification.
3. **Dependency selection is explicit.** Same-input tightening uses the complete input tuple. Feature/projection hypotheses compete through reconstruction, with incompatible row pairs recorded as reusable sibling nogoods (`synthesis-job-nogoods`).
4. **Partition feasibility is unresolved.** The bounded proxy can propose a non-refuted block without proving that it has a witness. The fifth return value reports proposal/search status.
5. **Recursive candidates are priced at the root.** Accepted children are retained; nested reconstruction may temporarily expand and may exceed the direct root grammar bound.
6. **Return contracts remain producer-specific.** `message` has three fields; resumable state stays in its job. Synchronous helper cutoff is not a resumable continuation.
7. **Caches are scoped.** Rewrite preparation is library-local; `synthesis-job` caches equivalent child `(frame, language)` scopes within a synthesis job (`synthesis-job-reused-subproblems`) while still reconstructing and pricing each parent branch.
8. **Models are ordinary expressions.** Lookup, quotient, partition, and corpus constructors have no separate model-wrapper or packet-kind layer.
9. **Experiments moved into tests.** Removed runner names, historical numerical traces, and obsolete helper APIs are not current reproduction instructions.
10. **M7–M9 status.** Stage A extensional correction pricing (`correction-packet`, `apply-correction-packet`, `correction-bit-size`, `select-closest-witness`, `relational-linkage-residual`), Stage B additive and conditional residual pullback (`heuristic-decompositions`, `start-heuristic-synthesis`) applied recursively per node (`:expand`, `heuristic-expander`), requirement-level learned propagation (`propagate-requirements`), `:policy :heuristic` agenda routing (`synthesis-episode-returns`), nogood sibling pruning, and child-frame DAG reuse are implemented. Pluggable DSL metric primitives (unified with general search reentrancy), autonomous locality-key synthesis, and M9 vocabulary retrieval remain open research goals.
