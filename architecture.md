---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,fit,backgrounds,calc}
---

# Lisploop Architecture Reference

This document is the definitive architectural specification of the **Lisploop** synthesis kernel as currently implemented in Common Lisp (SBCL). It describes the live 7-module homoiconic architecture, its mathematical foundations, its cost and epistemic contracts, how the code executes Milestones 1--4 and the core primitives of Milestones 5--9, and what remains to complete the experimental roadmap.

---

## 1. Purpose, Philosophy, and Lineage

### 1.1 The Core Premise (`prompt.md` & `prompt4.md`)

Lisploop is a clean-room experiment in **inductive program synthesis, algebraic law discovery, causal reorientation, and self-improving search** under strict information-theoretic and computational accounting. Its design is governed by nine foundational commitments introduced in [prompt.md](prompt.md) and [prompt4.md](prompt4.md):

1. **No Informational Loops**: If an external agent or test harness supplies a hint, target decomposition, or unverified rule, the experiment measures the hint rather than discovery. Every benchmark fixture is strictly separated from the synthesizer across an explicit data-only boundary (`row` / `frame`).
2. **Epistemic Honesty**: Every claim returned by the kernel carries an explicit epistemic grade (`:replayed-observations`, `:conjecture`, `:vacuous`, `:refuted`, `:validated`) together with the exact bit bound, work bound, domain scope, and (when validated) an auditable `law-certificate`. Empirical agreement on finite samples never silently upgrades into an algebraic certificate.
3. **Closed Accounting (Description Bits + Paid Runtime Work)**: Every model, law, rewrite rule, solver, and residual pays its exact prefix-free description length $S(\cdot)$ in bits (Encoding Version 7) and its exact runtime execution work $W(\cdot)$ in structural tariff units (Tariff Version 8, Simulator Version 5). Meta-level machinery (rewriters, anti-unification constructors, propagator matchers) runs inside the same metered virtual machine and must amortize its own validation and execution cost.
4. **Observational Conservation**: Semantics is grounded in the empirical outcome matrix $M(e, \omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cut}}(q)\}$ of evaluating expression $e$ on environment row $\omega$. Observational equivalence ($e_1 \equiv_\Omega e_2$), guarded equivalence ($g(\omega) = \mathrm{t} \implies e_1(\omega) = e_2(\omega)$), trajectory invariants, and algebraic laws are all projections of $M$.
5. **Reorientation & Pullback**: "Input" and "output" are not intrinsic properties of a relation; they are **orientations** chosen relative to what is currently observed. Selecting a subset of columns as known and a target column to explain creates a `frame`. Choosing a partial decomposition $d(x, z)$ pulls a parent frame back into a child frame over $z$ without consulting any hidden oracle.
6. **Factorization of Redundancy**: Shared structure across expressions, laws, or requirement fibers is factored by typed least general generalization (anti-unification), value quotienting, or latent fiber clustering---turning repeated sub-problems into reusable constructors or intermediate concepts.
7. **Dual-Grade Downward Propagation**: Discovered algebraic solvers propagate parent requirements downward to child frames in two distinct epistemic modes:
   - **Certified ($\iff$)**: Exhaustively validated bidirectional equivalences replace the child requirement in-place, shrinking the verification frame.
   - **Tentative ($\Leftarrow$)**: Uncertified or right-to-left integer witness rules propose a fast narrowed `propagation-frame` while retaining the original pullback frame as `propagation-fallback`. Every candidate synthesized on the narrowed frame must pass forward replay on the original frame before acceptance.
8. **Preemptive Resumability**: Evaluation, search, observation, law validation, and rewriting are implemented as resumable state machines driven by explicit work budgets. Running a job in tiny increments (`quantum = 1`) must yield the exact same state, ledger totals, and outcomes as running it in a single large batch.
9. **Lossy Heuristic Condensation**: While object-level verification is lossless (wrong programs are rejected), **search control** is lossy: when exact deductive propagation yields an intractable predicate or heterogeneous fibers, the synthesizer can condense a requirement frame into a compact, cheap heuristic program by pricing mismatched rows as an explicit description-length residual during training and dropping the residual at deployment.

### 1.2 Evolution Across `plan4` $\to$ `plan5` $\to$ `plan6`

The codebase evolved through three documented planning stages:

| Stage | Document | Architectural Contribution |
| :--- | :--- | :--- |
| **Plan 4** | [plan4.md](plan4.md), [results.md](results.md) | Established the frozen experimental contract (Encoding v7, Tariff v8, Simulator v5), the 4-milestone empirical progression (M1 Core Synthesis, M2 Observational Invariants, M3 Guarded Laws + AU Compression + Checked Symbolic DSL, M4 Arithmetic Reorientation + Dual-Grade Propagation), and verified every claim in [results.md](results.md). Implemented across 16 separate `.lisp` files using tagged-list ASTs `(:app (:op :+ :int) (:var 0 :int) ...)`. |
| **Plan 5** | [plan5.md](plan5.md) | Refactored the 16-file scaffold into a **7-module homoiconic kernel** where programs are native Lisp S-expressions `(#:+ #:X0 #:X1)` backed by a weak pointer-keyed metadata table (`*node-meta*`) and a pooled typed-symbol registry (`*typed-symbol-pool*`). Preserved exact bit-for-bit and work-unit parity with `plan4` and [results.md](results.md). |
| **Plan 6** | [plan6.md](plan6.md) | Synthesized the architecture around **four fundamental operations** (Observational Conservation, Factorization/Hard-EM Fiber Inference, Causal Reorientation/Pullback/Constant-Folding, and Lossy Heuristic Condensation), replaced `allowed` wrapper structs with pure S-expression row requirements (`row-requirement`), and added the core primitives needed for Milestones 5--9: closed-subtree constant folding (`fold-constants`), conflict detection (`frame-conflict-p`), confidence-ordered Hard-EM fiber clustering (`infer-fibers`), and residual-priced heuristic condensation (`condense-heuristic`). |

> **How the Live Kernel Relates to [plan6.md](plan6.md)**:
> The live 7-module kernel implements the homoiconic S-expression representation, pure S-expression `row-requirement`s, single `evaluation` VM stepper, and all four `plan6` operations (`fold-constants`, `frame-conflict-p`, `infer-fibers`, `condense-heuristic`). At the same time, it retains the load-bearing `:code-*` symbolic primitives (`compile-rule-transformer`, `compile-propagator-matcher`, `compile-au-constructor`, `validated-program`) and `law-corpus` bit-packet compressor so that Milestones 3B, 3C, and 4 continue to meter static validation (`:validation`), rule rewriting (`:rewriting`), and propagator matching inside the preemptive VM with 100% parity against [results.md](results.md).

---

## 2. The Four Fundamental Operations

At the heart of the kernel, every synthesis, law-discovery, decomposition, and propagation step is an instance of four interacting operations over the empirical outcome matrix:

```{=latex}
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
    >=Latex,
    box/.style={draw, rounded corners=3pt, align=left, font=\scriptsize, inner sep=5pt, fill=white},
    hdr/.style={draw, rounded corners=3pt, align=center, font=\small, inner sep=6pt, fill=gray!10},
    lbl/.style={font=\scriptsize\itshape, align=center}
]
    % Top: Homoiconic Kernel
    \node[hdr, text width=16.2cm] (kernel) at (0, 0) {
        \textbf{Homoiconic S-Expression, Frame \& Metered Evaluator Kernel}\\
        Schema $\Gamma = (D,\, x_1{:}\tau_1,\dots,x_m{:}\tau_m \to \tau)$, \quad Frame Rows $\omega \in \Omega$, \quad Candidate Stream $e \in \mathcal{E} \subseteq \mathcal{L}(\Gamma)$\\
        Outcome Matrix $M(e, \omega) = \mathrm{Eval}(e, x_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cut}}(q)\}$, \quad $O(1)$ Cached Metadata $(\mathrm{bits}, W_{\mathrm{syn}}, \mathrm{total?}, \mathrm{vars})$
    };

    % Four Operations below
    \node[box, text width=3.75cm, anchor=north] (op1) at (-6.15, -1.7) {
        \textbf{1. Observational Conservation}\\
        \texttt{enumerate.lisp}, \texttt{laws.lisp}\\[2pt]
        $\bullet$ \textbf{Buckets}: level sets of $M(e, \omega)$\\
        \phantom{$\bullet$ }(\texttt{observation-job})\\
        $\bullet$ \textbf{Invariants}: $M(e, \omega) = M(e, T\omega)$\\
        \phantom{$\bullet$ }(\texttt{observation-invariants})\\
        $\bullet$ \textbf{Guards}: support masks $S(e_1, e_2)$\\
        \phantom{$\bullet$ }(\texttt{propose-guarded-laws})
    };

    \node[box, text width=3.75cm, anchor=north] (op2) at (-2.05, -1.7) {
        \textbf{2. Factorization \& Fibers}\\
        \texttt{factor.lisp}, \texttt{frame.lisp}\\[2pt]
        $\bullet$ \textbf{Term AU}: $t_\omega = \mathrm{Subst}(p, \theta_\omega)$\\
        \phantom{$\bullet$ }(\texttt{anti-unify})\\
        $\bullet$ \textbf{Quotients}: $\mathrm{gather}(R, j_\omega)$\\
        \phantom{$\bullet$ }(\texttt{quotient-values}, \texttt{partition-rows})\\
        $\bullet$ \textbf{Hard-EM Fibers}: cluster $B_\omega(z)$\\
        \phantom{$\bullet$ }(\texttt{infer-fibers})
    };

    \node[box, text width=3.75cm, anchor=north] (op3) at (2.05, -1.7) {
        \textbf{3. Reorient, Pullback \& Propagate}\\
        \texttt{frame.lisp}, \texttt{vm.lisp}, \texttt{laws.lisp}\\[2pt]
        $\bullet$ \textbf{Reorient}: project $(k, c) \mapsto z$\\
        \phantom{$\bullet$ }(\texttt{orient-observations})\\
        $\bullet$ \textbf{Pullback \& Fold}: $A_\omega(d(x_\omega, z))$\\
        \phantom{$\bullet$ }(\texttt{pullback-frame}, \texttt{fold-constants})\\
        $\bullet$ \textbf{Propagate}: $\iff$ certified in-place\\
        \phantom{$\bullet$ }vs.\ $\Leftarrow$ tentative (\texttt{frame-conflict-p})
    };

    \node[box, text width=3.75cm, anchor=north] (op4) at (6.15, -1.7) {
        \textbf{4. Heuristic Condensation}\\
        \texttt{factor.lisp}, \texttt{enumerate.lisp}\\[2pt]
        $\bullet$ \textbf{MDL Condensation}: price misses\\
        \phantom{$\bullet$ }$S(\hat{\pi}) + S(\varepsilon) + \lambda_{\mathrm{run}} W_{\mathrm{run}}$, drop $\varepsilon$\\
        \phantom{$\bullet$ }at deployment (\texttt{condense-heuristic})\\
        $\bullet$ \textbf{Multi-Lane Reserve}: $3{:}1$ schedule\\
        \phantom{$\bullet$ }with forward replay (\texttt{propagation-search})
    };

    % Arrows from kernel
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (op1.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (op2.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (op3.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (op4.north);

    % Cross-links at bottom
    \draw[->, thick] (op2.south) -- ++(0,-0.45) -| node[pos=0.25, below, lbl] {Residuals $\theta_\omega, j_\omega$ form child frames} (op1.south);
    \draw[->, thick] (op3.south) -- ++(0,-0.9) -| node[pos=0.25, below, lbl] {Folded fibers $B_\omega(z)$ \& narrowed witnesses feed MDL condensation \& multi-lane search} (op4.south);
\end{tikzpicture}
\caption{The four fundamental operations of the Lisploop kernel interacting over the empirical outcome matrix $M(e, \omega)$.}
\end{figure}
```

### Operation 1: Observational Conservation

Given an expression family $\mathcal{E}$ and a finite observation set $\Omega$, evaluating $e \in \mathcal{E}$ on $\omega \in \Omega$ under quantum $q$ produces a cell $M(e, \omega)$ with three possible outcomes:

- `:value` --- total evaluation returning a domain-valid payload $v \in \mathcal{V}_\tau$,
- `:error` --- domain or operational error (e.g., division by zero, out-of-bounds `:gather`, missing `:lookup` key, or failed `:code-*` assertion),
- `:unknown` / `:cutoff` --- resource exhaustion when the evaluation debt exceeds the work budget.

From $M(e, \omega)$, the kernel extracts:

- **Empirical Equivalence Buckets** (`observation-bucket`): expressions with identical total output vectors across $\Omega$, ranked by canonical description length (`expression-less-p`).
- **Trajectory Invariants** (`observation-invariants`): buckets whose values remain constant across transition pairs $(\omega_{\mathrm{before}}, \omega_{\mathrm{after}})$ while varying across distinct anchor trajectories.
- **Partial-Domain Support & Guarded Laws** (`observed-support`, `propose-guard-problems`, `propose-guarded-laws`): when `:retain-outcomes t` is enabled on an `observation-job`, expressions that error on some rows or agree only on a subset of $\Omega$ induce Boolean support masks $S(e_1, e_2) \subseteq \Omega$. Grouping pairs by identical support masks synthesizes a single guard $g$ whose positive support matches $S(e_1, e_2)$, yielding guarded equations $g(\vec{x}) \implies e_1(\vec{x}) = e_2(\vec{x})$.

### Operation 2: Factorization & Latent Fiber Inference

Redundancy is factored across both syntax trees and requirement rows:

1. **Typed Anti-Unification (`anti-unify`)**: Computes the least general generalization (LGG) of a list of typed expressions under a shared input context. Disagreements become typed holes (`?0`, `?1`, $\dots$); repeated identical disagreement tuples map to the same hole ID (enforcing diagonal equality constraints), and compatible operator disagreements generalize to function-sorted `:hole`s.
2. **Value Quotienting & View Partitioning (`quotient-values`, `partition-rows`)**: Factors a sequence of values into unique first-occurrence `representatives` and an integer index `residual` reconstructed by `(:gather representatives residual)`, or partitions occurrence rows by discrete class labels with exact permutation reassembly (`partition-model`).
3. **Confidence-Ordered Hard-EM Fiber Inference (`infer-fibers`)**: When a frame contains rows with ambiguous finite-set or relational predicate requirements $B_\omega(z)$ over the target variable $z$, `infer-fibers` clusters rows into compatible latent fiber classes without an external witness oracle:
   - **Pre-simplification & Tightness Ranking**: Each row requirement $B_\omega(z)$ is simplified via `fold-constants` and ranked by `fiber-tightness-rank`: rank 0 (singleton `(= X0 'c)` or 1-element `:member`), rank 1 (finite set `(member X0 '(c1 ...))` ordered by ascending cardinality), and rank 2 (general Boolean predicate), breaking ties by `syntax-work`.
   - **Cannot-Link Soundness Filter**: Two requirements $B_1(z), B_2(z)$ cannot share a fiber class if `(conjoin-requirements B1 B2 target-type)` constant-folds to `'nil` (`unsatisfiable-requirement-p`).
   - **E-Step (Free Coverage)**: If conjoining a row's requirement with an existing `fiber-class-requirement` leaves the class requirement unchanged (`equal`), the row is already satisfied by the class fiber and joins at zero marginal bit cost ($\Delta S = 0$).
   - **M-Step (Coverage-Vote Amortized Merging / Nucleation)**: Otherwise, each compatible class is scored by its marginal description-bit increase $\Delta S = \max(0, S(B_{\mathrm{joint}}) - S(B_{\mathrm{class}}))$ divided by its compatibility coverage votes ($1 + \text{number of remaining unassigned rows whose requirements are compatible with } B_{\mathrm{joint}}$). If no existing class is compatible, a new `fiber-class` is nucleated.

### Operation 3: Causal Reorientation, Pullback, Closed-Subtree Constant Folding & Dual-Grade Propagation

1. **Reorientation (`orient-observations`, `orient-arithmetic-requirements`)**: Projects raw witnessed records `(key . values)` into a `frame` with chosen input columns (`schema-inputs`) and target column(s) (`schema-target`) without executing any simulation.
2. **Pullback (`pullback-frame`) & Closed-Subtree Constant Folding (`fold-constants`)**:
   - Given a parent `frame` with row requirements $A_\omega(y)$ and a decoder expression $d(x, z)$ over parent inputs $x$ and latent child variable $z$, `pullback-frame` substitutes the row's known constants $x_\omega$ and `(var 0 child-type)` into $d$, and substitutes the resulting closed decoder into $A_\omega(y)$ to form the child requirement $B_\omega(z) = A_\omega(d(x_\omega, z))$.
   - `fold-constants` simplifies open requirement S-expressions bottom-up: any **closed subtree** `(null (free-vars subtree))` is evaluated in the metered VM (`evaluate`), replacing the subtree with `(lit type value)` on `:value` or propagating `:error` cleanly (`(= err x)` $\to$ `'nil`). It also folds `:if` on literal conditions, propagates singleton equalities `(= x 'c)` into `:if` branches, intersects `:member` sets and predicates, and decomposes tuple equalities `(= (tuple a1 a2) '(v1 v2))` into conjunctions of element equalities.
3. **Conflict Detection (`frame-conflict-p`)**: Checks a frame for unsatisfiability in $O(|\Omega|)$:
   - **Row-level contradiction (`:unsatisfiable-row`)**: A single row's requirement folds to `'nil` (e.g., `(= (tuple z z) '(2 3))` decomposes into `(if (= z 2) (= z 3) nil)` and folds to `'nil`).
   - **Cross-row contradiction (`:incompatible-rows`)**: Two or more rows sharing identical `row-known` inputs have requirements whose conjunction via `conjoin-requirements` folds to `'nil`.
4. **Dual-Grade Downward Propagation (`propagate-arithmetic-child`)**: Matches a parent frame and decoder against a `propagator-library` of discovered arithmetic solvers:
   - **Certified ($\iff$, `certified-p = t`)**: Replaces the child row's requirement in-place with `(set-requirement domain (list witness-value))`, shrinking the child verification frame.
   - **Tentative ($\Leftarrow$, `certified-p = nil`)**: Evaluates the guard and witness on each row and **forward-verifies** `witness-value` against the original pulled-back requirement `row-requirement`. Rows that pass populate a narrowed `propagation-frame` while `propagation-fallback` retains the original pullback frame.

### Operation 4: Lossy Heuristic Condensation & Multi-Lane Search Control

1. **Residual-Priced Heuristic Condensation (`condense-heuristic`)**: Compresses a frame $F$ into a compact `heuristic-model` in two stages:
   - First, runs `infer-fibers` on $F$ to resolve ambiguous fibers into a `refined-frame`.
   - Second, runs `observation-job` with `:retain-outcomes t` over `language`, scoring each candidate program $p$ by the two-part MDL objective:
     $$J_{\mathrm{heuristic}}(p) = S(p) + S(\mathrm{residual}(p, F)) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(p)$$
     where every row $i$ that $p$ fails to satisfy pays its exact row-index and witness-value bit cost:
     $$\Delta S_{\mathrm{miss}}(i) = \mathrm{positive\text{-}bit\text{-}size}(i + 1) + \mathrm{value\text{-}bit\text{-}size}(w_i, \tau)$$
   - Returns the minimum-score `heuristic-model` whose deployed `(heuristic-program model)` is the bare S-expression $p^*$ with the training residual discarded.
2. **Multi-Lane Scheduler with 1-in-4 Canonical Reserve (`propagation-search`)**: Coordinates a tentative `:primary` search lane (over `propagation-frame`) and a canonical `:fallback` search lane (over `propagation-fallback`):
   - Every 4th quantum (`(= 3 (mod turn 4))`) is reserved for `:fallback`; the other 3 quanta advance `:primary` (or `:verification`).
   - Any candidate discovered by `:primary` is replayed against `:original` (`:verification` lane) before it can enter `propagation-search-results`, guaranteeing soundness and completeness even when tentative integer witnesses fail or miss multi-valued fibers.

---

## 3. Epistemic, Isolation, and Accounting Contracts

### 3.1 Strict Information Isolation

- **No Hidden Oracle Calls**: All benchmark generators in `fixtures.lisp` emit only plain `frame`s or `(key . values)` records. No oracle AST or closure ever crosses into the synthesizer.
- **Self-Hosted Meta-Programs**: When a meta-level artifact (an anti-unification constructor, a rewrite rule transformer, or a propagator matcher) is applied during search, it is lowered into an explicit symbolic DSL program (`:code-*` operators), statically validated once per `(versions, scope)` (`validated-program`), and executed inside the metered VM.

### 3.2 Cost Objective & Frozen Accounting Versions

The kernel enforces three frozen version constants exported from `package.lisp`:

- `+encoding-version+ = 7` (`codec.lisp`)
- `+tariff-version+ = 8` (`vm.lisp`)
- `+simulator-version+ = 5` (`vm.lisp`)

#### Object-Level Model Objective

For a candidate model $M$ evaluated against a frame $E$:
$$J(M) = S(M) + S(E \mid M) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(M)$$

- $S(M)$ is $\mathrm{description\text{-}size}(\mathit{expr}, \mathit{inputs})$ in bits under Encoding Version 7 ($\mathrm{header\text{-}size}(\mathit{inputs}, \mathit{target}) + \mathrm{body\text{-}size}(\mathit{expr}, \mathit{inputs})$).
- For lossless synthesis (`search-job`), $S(E \mid M) = 0$ because only models satisfying every row requirement are accepted; for lossy heuristic condensation (`condense-heuristic`), $S(E \mid M)$ is `heuristic-residual-bits`.

#### Meta-Level Procedure Objective

For reusable meta-programs (such as compiled rewrite rules):
$$J_{\mathrm{procedure}}(P) = S(P) + \lambda_{\mathrm{prep}} W_{\mathrm{validate}}(P) + \lambda_{\mathrm{run}} \sum_{\mathrm{uses}} \bigl(W_{\mathrm{apply}}(P) + \Delta W_{\mathrm{search}}(P)\bigr)$$
where static structural validation cost $W_{\mathrm{validate}}(P)$ is charged **once** per unique `(rule, inputs, versions)` key in `*prepared-rewrite-cache*` (`laws.lisp`) and amortized across all subsequent search jobs in that scope.

### 3.3 Epistemic Grades

Every search, validation, and propagation result carries an explicit claim or validation status:

| Claim / Status | Meaning |
| :--- | :--- |
| `:replayed-observations` | Empirical scope evidence grade: candidate satisfies all observed rows in the current frame or replays across held-out observations. Not a universal proof. |
| `:conjecture` | Law or solver holds on all tested sample rows (`:samples` scope) with positive support, or is an uncertified integer $\Leftarrow$ witness rule. Cannot be used for in-place rewrite or certified frame replacement. |
| `:vacuous` | Guarded law was tested across its domain/samples, never failed, but its guard was never satisfied (`active = 0`). Rejected from rewrite and solver libraries. |
| `:refuted` | Law failed on at least one input tuple (either LHS $\neq$ RHS or an unguarded evaluation error occurred). Records the exact `counterexample` input vector. |
| `:validated` | Exhaustively verified over the entire finite Cartesian product of its input domain (every input type must be `:bool` or $\texttt{(:gf } p\texttt{)}$), with `active > 0` and zero cutoff interruptions. Carries a `law-certificate`. |
| `:cutoff` | Budget (`work-limit`) was exhausted before completion; job state is preserved for exact resumption. |
| `:bounded-exhaustion` / `:replay-complete` | All candidates up to `description-limit` (or all listed replay expressions) have been evaluated. |

---

## 4. Module-by-Module Kernel Reference

The kernel is loaded in deterministic order by `load.lisp` and exports its public API from `:lisploop` in `package.lisp`.

```{=latex}
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
    >=Latex,
    mod/.style={draw, rounded corners=3pt, align=center, font=\scriptsize, inner sep=4.5pt, fill=white, text width=3.55cm, minimum height=1.35cm},
    pkg/.style={draw, rounded corners=3pt, align=center, font=\scriptsize, inner sep=4.5pt, fill=gray!10, text width=3.55cm, minimum height=1.35cm}
]
    \node[pkg] (m0) at (-6.0, 0) {\textbf{0. \texttt{package.lisp}}\\Public API Exports\\\& Frozen Constants};
    \node[mod] (m1) at (-2.0, 0) {\textbf{1. \texttt{ast.lisp}}\\Homoiconic S-Exprs\\\& $O(1)$ Weak Metadata};
    \node[mod] (m2) at (2.0, 0) {\textbf{2. \texttt{codec.lisp}}\\Prefix Codec v7\\\& Canonical Order};
    \node[mod] (m3) at (6.0, 0) {\textbf{3. \texttt{vm.lisp}}\\Tariff v8, Simulator v5,\\Evaluator \& \texttt{fold-constants}};

    \node[mod] (m4) at (-6.0, -2.0) {\textbf{4. \texttt{frame.lisp}}\\Frames, S-Expr Reqs,\\Pullbacks, Conflicts \& Views};
    \node[mod] (m5) at (-2.0, -2.0) {\textbf{5. \texttt{enumerate.lisp}}\\Exact-Bit Enumerator,\\Search, Buckets \& Lanes};
    \node[mod] (m6) at (2.0, -2.0) {\textbf{6. \texttt{factor.lisp}}\\Matching, AU, \texttt{infer-fibers},\\\texttt{condense-heuristic} \& Corpus};
    \node[mod] (m7) at (6.0, -2.0) {\textbf{7. \texttt{laws.lisp}}\\Laws, Guards, Rewriting,\\Solvers \& Propagation};

    \draw[->, thick] (m0) -- (m1);
    \draw[->, thick] (m1) -- (m2);
    \draw[->, thick] (m2) -- (m3);
    \draw[->, thick] (m3.south) -- ++(0,-0.32) -| (m4.north);
    \draw[->, thick] (m4) -- (m5);
    \draw[->, thick] (m5) -- (m6);
    \draw[->, thick] (m6) -- (m7);
\end{tikzpicture}
\caption{Deterministic load and dependency order of the 7-module homoiconic kernel (\texttt{load.lisp}).}
\end{figure}
```

---

### Module 1: `ast.lisp` --- Homoiconic Representation & $O(1)$ Metadata

#### Type System & Schemas

Supported semantic types (`valid-type-p` in `ast.lisp`):

- `:int` --- arbitrary-precision integers (unbounded),
- $\texttt{(:gf } p\texttt{)}$ --- prime field $\mathbb{F}_p$ with elements $\{0, \dots, p-1\}$ (`gf` rejects composite moduli),
- `:bool` --- Booleans $\{\texttt{nil}, \texttt{t}\}$,
- $\texttt{(:tuple } \tau_1 \dots \tau_k\texttt{)}$ --- fixed-length heterogeneous tuples (`tuple-type`),
- $\texttt{(:seq } \tau\texttt{)}$ --- homogeneous sequences (`sequence-type`),
- $\texttt{(:code } \mathit{inputs}\ \mathit{sort}\texttt{)}$ --- quoted object-language syntax trees or operators in an explicit free-variable scope (`code-type`).

A `schema` (`make-schema`) packages `(domain inputs target lookup-p)`, automatically inferring the ambient numeric `domain` (`:int` or $\texttt{(:gf } p\texttt{)}$) from `target` and `inputs` when not explicitly supplied.

#### Homoiconic S-Expression Representation

AST nodes are native Lisp S-expressions whose symbols are interned into `*typed-symbol-pool*` (`ast.lisp`) and annotated in a weak pointer-keyed hash table `*node-meta*` (`:test #'eq :weakness :key`):

| AST Node Kind | Native Lisp Representation | Constructor | Notes |
| :--- | :--- | :--- | :--- |
| **Variable** (`:var`) | Pooled uninterned symbol `#:X0`, `#:X1`, $\dots$ | `(var id type)` | Pooled by `(:var id type)` in `*typed-symbol-pool*`. |
| **Hole** (`:hole`) | Pooled uninterned symbol `#:?0`, `#:?1`, $\dots$ | `(hole id sort)` | Used in anti-unification patterns (both value and `:fn` sorts). |
| **Literal** (`:lit`) | 2-element list `(#:QUOTE value)` | `(lit type value)` | Head is a pooled symbol `#:QUOTE` typed by `(:quote type)`. Prints natively as `'value`. |
| **Operator** (`:op`) | Pooled uninterned symbol `#:+`, `#:IF`, $\dots$ | `(op name type)` | Pooled by `(:op name type)` with signature `(:fn arg-types ret-type)`. |
| **Application** (`:app`) | Cons cell `(op-sym arg1 arg2 ...)` | `(app operator &rest args)` | Head is an `:op` or function-sorted `:hole` symbol. |

#### $O(1)$ Cached Structural Metadata (`ast-meta`)

Every AST node maps in `*node-meta*` to an `ast-meta` struct caching:

- `kind` (`:var`, `:hole`, `:lit`, `:op`, `:app`), `id`, `type`, `value`,
- `non-var-bits` --- exact bit size of all non-variable nodes in the subtree,
- `var-count` --- total variable occurrences in the subtree,
- `syntax-work` --- exact structural construction tariff,
- `total-p` --- conservative structural totality (`t` when the subtree is guaranteed not to raise a runtime error),
- `free-vars` --- deduplicated list of free variable IDs in the subtree.

Because `non-var-bits` and `var-count` are precomputed on every node, `body-size`, `syntax-work`, `provably-total-p`, and `free-vars` are all $O(1)$ metadata reads:
$$\mathrm{body\text{-}size}(e, \Gamma) = \mathrm{non\text{-}var\text{-}bits}(e) + \mathrm{var\text{-}count}(e) \cdot \lceil \log_2 \max(1, |\Gamma_{\mathrm{inputs}}|) \rceil.$$
If an expression is copied via `copy-tree`, `ensure-ast-meta` automatically reconstructs and re-caches its `ast-meta` from the pooled head symbol (`#:QUOTE` or operator symbol).

#### Operator Vocabulary (`+operator-names+`)

Defined in `ast.lisp` with 20 operators:

- **Object-Level Primitives (11)**: `:+`, `:*`, `:=`, `:tuple`, `:member`, `:lookup`, `:gather`, `:-`, `:/`, `:if`, `:concat`.
- **Symbolic Code Primitives (9, `*symbolic-primitives*`)**: `:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`, `:code-subst`, `:code-total`, `:code-less`.

---

### Module 2: `codec.lisp` --- Binary Codec (Version 7) & Canonical Ordering

#### Prefix-Free Bit Encoding (`+encoding-version+ = 7`)

`codec.lisp` implements an exact self-delimiting bit-vector serializer (`encode-model` / `decode-model`) and an $O(1)$ packet size oracle (`description-size` = `header-size` + `body-size`):

- **Positive integers** (`emit-positive`, `positive-bit-size`): Elias-style prefix code using $2\lfloor\log_2 L\rfloor + 1 + (L - 1)$ bits where $L = \lfloor\log_2 n\rfloor + 1$.
- **Signed integers** (`signed-code`): Zigzag mapping $z(n) = 2n+1$ for $n \ge 0$ and $z(n) = -2n$ for $n < 0$.
- **Operator Tags**: 4-bit opcode index into `+operator-names+`, with index $\ge 15$ extended by $\mathrm{positive\text{-}bit\text{-}size}(\mathit{index} - 14)$.

#### Canonical Expression Ordering (`expression-less-p`)

`expression-less-p` compares two expressions by $O(1)$ `description-size` first, only encoding bit-vectors to break exact bit-length ties lexicographically.

---

### Module 3: `vm.lisp` --- Tariff (Version 8), Simulator (Version 5), Resumable Evaluator & Constant Folder

#### Structural Runtime Tariff (`+tariff-version+ = 8`)

Runtime work charges scale with structural size and operand bit-width (`integer-width`):

- **Arithmetic (`arithmetic-cost`)**: Unit cost ($1$) for prime fields with $p \le 257$; bit-width sensitive ($\max(w_a, w_b)$ for `:+`/`:-`, $w_a \cdot w_b$ for `:*`/`:div`, plus modular reduction penalty for large prime fields) on `:int` and large $\texttt{(:gf } p\texttt{)}$.
- **Data & Sequence Primitives (`primitive-cost`)**: $1 + \sum \mathrm{value\text{-}work}(\mathit{args})$ plus index-width checks for `:gather`.
- **Symbolic Primitives (`symbolic-primitive-cost`)**: Prepays traversal, pattern-matching ($w_{\mathrm{pattern}} \cdot w_{\mathrm{source}}$), substitution, or size-comparison costs. A single-entry memo cache `*last-code-match*` (`vm.lisp`) avoids re-running host `match-pattern` when `:code-bind` immediately follows `:code-match` on the same `(pattern, source, scope)`, while charging the exact tariff specification.

#### Preemptive Resumable Evaluator (`evaluation` & `validated-program`)

The `evaluation` struct (`start-evaluation`, `advance-evaluation`, `evaluate`, `start-program-validation`, `start-validated-evaluation`, and `advance-accounted-evaluation`) is the single debt-draining VM state machine used across the entire kernel:

- Every instruction sets `evaluation-remaining-cost` to its structural tariff before execution.
- `advance-evaluation` drains $\min(\mathit{budget}, \mathit{remaining\text{-}cost})$ first, only executing the task when $\mathit{remaining\text{-}cost} = 0$. Thus an error (`:error`) is never observed before its full instruction cost is paid, and `quantum = 1` stepping produces the exact same state and ledger as batch execution.

#### Closed-Subtree Constant Folding (`fold-constants`)

`fold-constants` simplifies open S-expressions bottom-up:

1. **Closed-Subtree Evaluation (`eval-closed-expr`)**: Whenever an application has `(null (free-vars expr))`, it is evaluated in the VM up to `budget`. If it returns `:value`, it is replaced by `(lit result-type value)`; if it returns `:error`, `fold-node` propagates the failure cleanly (e.g., an equality `(= err x)` folds to `'nil`).
2. **Conditional & Equality Simplification**:
   - `(:if 't yes no)` $\to$ `yes`; `(:if 'nil yes no)` $\to$ `no`.
   - When `cond` is a singleton equality `(= x 'v)` on a variable `x`, substitutes $\texttt{x} \mapsto \texttt{'v}$ into `yes` via `instantiate` and re-folds `yes`.
   - Conjunctions `(if a b 'nil)` intersect finite sets and singletons: if `a` is `(= x 'v)` or `(member x '(v1 ...))`, filters the values against `b` and reduces to `'nil` (when empty), `(= x 'v)` (when $1$ value remains), or `(member x filtered)` (when multiple values remain).
3. **Tuple Injectivity Decomposition**: Decomposes $\texttt{(= (tuple } a_1 \dots a_k\texttt{) '(} v_1 \dots v_k\texttt{))}$ into the conjunction $\texttt{(and (= } a_1\ \texttt{'} v_1\texttt{) } \dots \texttt{ (= } a_k\ \texttt{'} v_k\texttt{))}$ and re-folds, immediately reducing diagonal conflicts like `(= (tuple z z) '(2 3))` to `'nil`.

---

### Module 4: `frame.lisp` --- Frames, S-Expression Requirements, Pullbacks, Conflicts, Views & Quotients

#### Pure S-Expression Row Requirements (`row`, `frame`)

A `frame` consists of `(schema rows pairs anchors)`. Each `row` holds `(key known requirement)` where `row-requirement` is a Boolean S-expression over `(var 0 target-type)`:

- `singleton-requirement`: `(app (op := type) (var 0 type) (lit type value))` --- `(= X0 'v)`.
- `set-requirement`: `(app (op :member type) (var 0 type) (lit (sequence-type type) values))` --- `(member X0 '(v1 ...))`.
- General predicates: any Boolean AST over `(var 0 target-type)` (e.g., `(lit :bool t)` for unconstrained probe frames, or pulled-back relational predicates).
- `extract-allowed-values`: Inspects a requirement S-expression and returns `nil` for `'nil`, `(list v)` for `(= X0 'v)`, `'(v1 ...)` for `(member X0 '(v1 ...))`, or `:unknown` for general predicates.
- `check-requirement`: Evaluates a requirement S-expression on a candidate `value` in the VM.

#### Conjunction, Conflict Detection, Pullback, Views & Quotients

- `conjoin-requirements`: Conjoins two requirements over `(var 0 target-type)` via `(fold-constants (bool-and req1 req2) schema)`.
- `frame-conflict-p`: Returns a `frame-conflict` struct (`:kind :unsatisfiable-row` or `:incompatible-rows`) if any row requirement folds to `'nil` or if rows sharing identical `row-known` inputs conjoin to `'nil`.
- `orient-observations`, `transition-probes`, `lookup-model`.
- `pullback-frame` & `compose-model`: Pulls a parent frame back through $d(x, z)$, folds closed subtrees via `fold-constants`, and composes synthesized child programs into parent solutions.
- `support-frame`, `partition-rows`, `reassemble-partition`, `partition-model`.
- `quotient-values`, `restore-quotient`, `quotient-model`.

---

### Module 5: `enumerate.lisp` --- Size-Partitioned Enumerator, Search, Observations & Multi-Lane Propagation Search

- **Exact-Bit Bottom-Up Enumerator (`language`, `enumerator`, `enumeration-step`)**: Enumerates well-typed ASTs in strictly non-decreasing order of `body-size` bits, using `integer-literals-of-bit-size` to invert the Elias/zigzag bit-length formula analytically and sorting each bucket by `expression-less-p`.
- **Resumable Synthesis (`search-job`: `start-search`, `resume-search`)**: Evaluates enumerated or replayed candidates against a `frame` with optional normal-form rejection caching (`:library`) when a validated `rewrite-library` is supplied.
- **Resumable Observation Discovery (`observation-job`: `start-observation-search`, `resume-observation-search`)**: Evaluates $\mathcal{E} \times \Omega$, groups total evaluations into typed-value `observation-bucket`s, checks trajectory invariance (`pairs`) and variation (`anchors`), and optionally retains per-row outcomes (`:retain-outcomes t`) for guard and solver discovery.
- **Multi-Lane Propagation Search (`propagation-search`: `start-propagation-search`, `resume-propagation-search`)**: Schedules `:primary`, `:fallback` (1-in-4 reserve), and `:verification` (forward replay on `:original`).

---

### Module 6: `factor.lisp` --- Pattern Matching, Anti-Unification, `infer-fibers`, `condense-heuristic` & Corpus Compression

- `match-pattern`: First-order pattern matcher supporting value holes and operator holes with consistent repeated-hole bindings.
- `anti-unify` & `compile-au-constructor`: Typed LGG with memoized disagreement tuples and lowering to `:code-apply` / `:code-subst` DSL constructors.
- `infer-fibers`: Confidence-ordered Hard-EM latent fiber inference returning `(values classes labels refined-frame partition)`.
- `condense-heuristic`: Two-stage MDL lossy heuristic condensation returning a `heuristic-model` (`heuristic-program`, `heuristic-residual`, `heuristic-exact-p`, `heuristic-score`).
- `make-law-corpus`, `propose-law-compressions`, `decode-law-corpus`: Milestone 3B law corpus compressor.

---

### Module 7: `laws.lisp` --- Laws, Guard Discovery, Rewriting, Arithmetic Solvers & Propagation

- **Law Discovery & Validation**: `propose-observed-laws`, `start-law-validation`, `resume-law-validation`.
- **Partial-Domain Guard Discovery**: `observed-support`, `propose-guard-problems`, `start-guard-search`, `propose-guarded-laws`.
- **Checked Symbolic Rewriting**: `prepare-rewrite-library`, `compile-rule-transformer`, `start-rewriting`, `advance-rewriting`.
- **M4 Arithmetic Solver Discovery & Dual-Grade Propagation**: `observe-arithmetic-relation`, `orient-arithmetic-requirements`, `discover-arithmetic-solver`, `validate-arithmetic-solver`, `prepare-propagator-library`, `propagate-arithmetic-child`.

---

## 5. Supporting Infrastructure: Fixtures, Experiments, Tests & Visualizer

| File / Directory | Role in the Repository |
| :--- | :--- |
| `fixtures.lisp` | Data-only observation generators and independent replay helpers (`code-transform-fixture`, `gf5-fixture`, `gf5-transition-fixture`, `integer-transition-fixture`, `integer-linear-fixture`, `replay-model`). |
| `experiments.lisp` | Top-level CLI runner and executable driver for **Milestone 1** (`run-m1`) and **Milestone 2** (`run-m2`). Also loads `law-experiments.lisp` (`m3`) and `algebra-experiments.lisp` (`m4`). |
| `law-experiments.lisp` | Executable driver for **Milestone 3** (`run-m3`: 3A guarded modular division laws & rewrite speedup vs.\ uncertified integer non-transfer; 3B AU compression of discovered field laws; 3C checked symbolic DSL rule compilation and amortization crossover after 2 jobs). |
| `algebra-experiments.lisp` | Executable driver for **Milestone 4** (`run-m4`: all $(+, -, \times, /) \times (\mathrm{left}, \mathrm{right})$ orientations in $\mathbb{F}_5, \mathbb{F}_7, \mathbb{Z}$, AU solver-family reconstruction, certified field propagation, and tentative integer propagation with forward replay). |
| `benchmark.lisp` | Timing harness measuring real wall-clock and GC time across the M1--M3 workloads. |
| `tests/` | 11 core test suites loaded by `tests/run.lisp` (`core`, `observations`, `codec`, `laws`, `guards`, `compression`, `symbolic`, `amortization`, `algebra`, `propagation` --- 85 tests, 187,405 assertions) plus `tests/visualizer.lisp` --- 100% passing via `make test`. |
| `visualizer/` | Static HTML/JSON report exporter (`export.lisp`, `generate.lisp`) for Milestone 2 observation scopes. |

---

## 6. Implementation Status & Milestone Roadmap (Milestones 1--9)

| Milestone | Kernel Primitives & Verification | Status |
| :--- | :--- | :--- |
| **M1: Core Typed Synthesis, Pullback, Views, Quotients & Aligned AU** | Implemented across `ast.lisp`, `codec.lisp`, `vm.lisp`, `frame.lisp`, `enumerate.lisp`, `factor.lisp`. Driven by `experiments.lisp` (`m1`); tested in `tests/core.lisp` and `tests/codec.lisp`. | **Complete & Verified** (matches [results.md](results.md)) |
| **M2: Observational Equivalence, Trajectory Invariants & Replay** | Implemented via `observation-job` (`enumerate.lisp`) and `transition-probes` (`frame.lisp`). Driven by `experiments.lisp` (`m2`); tested in `tests/observations.lisp` and `tests/visualizer.lisp`. | **Complete & Verified** (matches [results.md](results.md)) |
| **M3: Guarded Laws (3A), AU Law Compression (3B) & Symbolic Rewriting (3C)** | Implemented in `laws.lisp` and `factor.lisp`. Driven by `law-experiments.lisp` (`m3`); tested in `tests/laws.lisp`, `tests/guards.lisp`, `tests/compression.lisp`, `tests/symbolic.lisp`, and `tests/amortization.lisp`. | **Complete & Verified** (matches [results.md](results.md)) |
| **M4: Arithmetic Reorientation, Solvers & Dual-Grade Propagation** | Implemented in `laws.lisp` and `propagation-search` (`enumerate.lisp`). Driven by `algebra-experiments.lisp` (`m4`); tested in `tests/algebra.lisp` and `tests/propagation.lisp`. | **Complete & Verified** (matches [results.md](results.md)) |
| **M5: Intermediate Concept Lifting via Hard-EM Latent Fibers** | `infer-fibers` (`factor.lisp`) and `pullback-frame` (`frame.lisp`) implemented and unit-tested in `tests/propagation.lisp`; **end-to-end M5 lifting experiment driver not yet written**. | **Kernel Complete / Experiment Pending** |
| **M6: Typed Anti-Unification & Reusable Macro Discovery** | `anti-unify` and `compile-au-constructor` (`factor.lisp`) implemented and tested in `tests/core.lisp` and `tests/symbolic.lisp`; **unaligned hidden-subtree occurrence search not yet wired**. | **Mostly Complete** |
| **M7: Autonomous View Discovery & Feature-Locality Projection** | `partition-rows` (`frame.lisp`), `infer-fibers`, and `condense-heuristic` (`factor.lisp`) implemented and tested in `tests/core.lisp` and `tests/propagation.lisp`; **autonomous regime-predicate search & input-subset locality loop not yet wired**. | **Kernel Primitives Complete / Search Loop Pending** |
| **M8A: Nested Decoder Composition (Multi-Step Pullback & Propagation)** | `fold-constants` (`vm.lisp`), `pullback-frame` (`frame.lisp`), and `propagate-arithmetic-child` (`laws.lisp`) implemented; **chained multi-step decoder rewrite loop over nested contexts not yet wired**. | **Pending Chained Driver** |
| **M8B: Shared Sub-Expression Memoization & DAG GC** | Weak `*node-meta*` table and `*prepared-rewrite-cache*` implemented; **observation-bucket DAG node sharing & GC across iterative rounds not yet wired**. | **Pending** |
| **M8C: Contradiction Detection & Backtracking under Shared Latent Variables** | `fold-constants` tuple decomposition (`vm.lisp`) and `frame-conflict-p` (`frame.lisp`) implemented and unit-tested in `tests/propagation.lisp`; **agenda lane pruning on conflict not yet wired**. | **Kernel Complete / Agenda Wiring Pending** |
| **M8D: Lossy Heuristic Search Control via Residual-Priced Condensation** | `condense-heuristic` (`factor.lisp`) and `start-propagation-search` (`enumerate.lisp`) implemented and unit-tested in `tests/propagation.lisp`; **end-to-end agenda-routing benchmark not yet wired**. | **Kernel Complete / Benchmark Pending** |
| **M9: Self-Hosted Policy & Vocabulary Amortization** | `:code-*` VM, `condense-heuristic`, and `compile-au-constructor` implemented; **multi-problem vocabulary/policy promotion loop with automatic eviction not yet wired**. | **Pending** |

---

## 7. Quick-Start Verification Commands

To run the full test suite (all 85 core tests + visualizer exporter checks):
```bash
make test
```

To reproduce the Milestone 1--4 empirical reports:
```bash
sbcl --script experiments.lisp m1
sbcl --script experiments.lisp m2
sbcl --script experiments.lisp m3
sbcl --script experiments.lisp m4
```
