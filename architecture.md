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
4. **Observational Conservation**: Semantics is grounded in the empirical outcome matrix $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cut}}(q)\}$ of evaluating symbolic expression $e(X)$ on row $\omega$'s bound input values $\mathbf{x}_\omega$. Observational equivalence ($e_1 \equiv_\Omega e_2$), guarded equivalence ($G(\mathbf{x}_\omega) = \mathrm{t} \implies e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega)$), symmetries/invariants conserved under an action ($M(e, \omega) = M(e, T\omega)$), and algebraic laws are all projections of $M$.
5. **Reorientation & Pullback**: "Input" and "output" are not intrinsic properties of a relation; they are **orientations** chosen relative to what is currently observed. Selecting a subset of columns as known inputs $\mathbf{x}_\omega$ and a target column $Y$ to explain creates a `frame`. Choosing a partial decomposition $Y = d(X, Z)$ pulls a parent requirement $A_\omega(Y)$ back into a symbolic child requirement $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$ without consulting any hidden oracle.
6. **Factorization of Redundancy**: Shared structure across expressions, laws, or requirement fibers is factored by typed least general generalization (anti-unification), value quotienting, or latent fiber clustering---turning repeated sub-problems into reusable constructors or intermediate concepts.
7. **Dual-Grade Downward Propagation**: Discovered algebraic solvers propagate parent requirements downward to child frames in two distinct epistemic modes:
   - **Certified ($\iff$)**: Exhaustively validated bidirectional equivalences replace the child requirement $B_\omega(Z)$ in-place with `(= Z 'v_w)`, shrinking the verification frame.
   - **Tentative ($\Leftarrow$)**: Uncertified or right-to-left integer witness rules propose a fast narrowed `propagation-frame` while retaining the original pullback frame as `propagation-fallback`. Every candidate synthesized on the narrowed frame must pass forward replay on the original frame before acceptance.
8. **Preemptive Resumability**: Evaluation, search, observation, law validation, and rewriting are implemented as resumable state machines driven by explicit work budgets. Running a job in tiny increments (`quantum = 1`) must yield the exact same state, ledger totals, and outcomes as running it in a single large batch.
9. **Lossy Heuristic Condensation**: While object-level verification is lossless (wrong programs are rejected), **search control** is lossy: when exact deductive propagation yields an intractable predicate or heterogeneous fibers, the synthesizer can condense a requirement frame into a compact, cheap heuristic expression $\hat{\pi}(X)$ by pricing mismatched rows $\varepsilon_\omega$ as an explicit description-length residual during training and dropping the residual at deployment.

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

### Nomenclature & Kernel Mapping

Throughout this document and [plan6.md](plan6.md), **uppercase letters** ($X_i, Y, Z$) denote **symbolic variable AST nodes** (`#:X0`, `#:X1`, $\dots$) inside expressions and requirement predicates, whereas **lowercase letters** ($\mathbf{x}_\omega, y_\omega, z_\omega, v_\omega$) denote **concrete runtime values** in $\mathcal{V}_\tau$ bound when evaluating on a specific observation row $\omega \in \Omega$:

| Symbol | Mathematical Meaning | Live Kernel Representation |
| :--- | :--- | :--- |
| $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$ | **Typing schema**: ambient numeric domain $D$, symbolic input variables $X_i : \tau_i$, and target output type $\tau$. | `schema` struct (`make-schema` in `ast.lisp`) with slots `domain`, `inputs`, `target`, `lookup-p`. |
| $\tau,\; \mathcal{V}_\tau$ | **Semantic type** $\tau$ and its **value domain** $\mathcal{V}_\tau$ (including base types $\mathbb{Z}, \mathbb{F}_p, \mathbb{B}$, tuples, sequences, and quoted syntax `(:code inputs sort)`). | `:int`, `(:gf p)`, `:bool`, `(:tuple ...)`, `(:seq ...)`, `(:code inputs sort)` (`valid-type-p`, `value-p` in `ast.lisp`). |
| $X = (X_0, \dots, X_{m-1})$ and $Y, Z$ | **Symbolic variables**: $X_i$ are formal input variables in $e(X)$; $Y : \tau_P$ and $Z : \tau_C$ are the target variable (`(var 0 type)`) in parent/child requirements $A_\omega(Y), B_\omega(Z)$. | Pooled uninterned symbols `#:X0`, `#:X1`, $\dots$ constructed via `(var id type)`. |
| $\Omega = (\omega_1, \dots, \omega_n)$ and $\omega \in \Omega$ | **Frame** $\Omega$ and **observation row** $\omega$ pairing bound input vector $\mathbf{x}_\omega = (x_{\omega,0}, \dots, x_{\omega,m-1})$ with requirement $A_\omega(Y)$. | `frame` (`make-frame`) and `row` (`make-row` with `row-key`, `row-known`, `row-requirement` in `frame.lisp`). |
| $T\omega$ | **Action-linked row**: a row linked to $\omega$ by an empirical action, symmetry transformation, or co-locality relation $(\omega, T\omega)$ (with M2 trajectory steps as the dynamical special case). | Row-index pair $(\omega, T\omega)$ in `observation-scope-pairs` (inherited automatically from optional `frame-pairs`, or produced from transition records by `transition-probes`). |
| $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega)$ | **Outcome Matrix cell**: result of evaluating $e(X) \in \mathcal{E}$ on $\mathbf{x}_\omega$, in $\mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cut}}(q)\}$. | Computed by `evaluation` (`vm.lisp`) inside `search-job` or `observation-job`. |
| $A_\omega(Y),\; B_\omega(Z),\; \mathrm{Fiber}(\omega)$ | **Symbolic row requirements** and **target-value fiber** $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$. | `row-requirement` (`singleton-requirement`, `set-requirement`, or general Boolean AST), `extract-allowed-values`, `conjoin-requirements` (`frame.lisp`). |
| $t_\omega,\; p,\; \theta_\omega$ | **Factorization & residual value (Operation 2)**: $t_\omega \in \mathcal{V}_\tau$ is a witnessed object on row $\omega$; $p$ is a shared template/table; $\theta_\omega \in \mathrm{Fiber}(\omega)$ is the per-row residual value satisfying $\mathrm{Apply}(p, \theta_\omega) = t_\omega$. | `anti-unify` & `compile-au-constructor` (where $t_\omega$ is a `:code` AST and $\theta_\omega$ is the hole-binding tuple), `quotient-values` (where $\theta_\omega = j_\omega$). |
| $\Omega_k \subseteq \Omega$ and $j_\omega \in \{0,\dots,K-1\}$ | **Row-space value fiber (level set in $\Omega$) & cluster index**: $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ groups rows sharing representative $R_k$ or compatible intersected fiber $\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset$. | `quotient-values` & `partition-rows` (`frame.lisp`), `infer-fibers` returning `fiber-class` structs with `fiber-class-rows` ($\Omega_k$) and `fiber-class-requirement` ($B_{c_k}(Z) = \bigwedge_{\omega \in \Omega_k} B_\omega(Z)$). |
| $d(X, Z),\; q(K, C),\; G(K, C),\; v_\omega$ | **Decoder AST** $Y = d(X, Z)$, **learned solver witness/guard** $q, G$, and **folded witness value** $v_\omega \in \mathrm{Fiber}(\omega)$. | `pullback-frame`, `fold-constants`, `discover-arithmetic-solver`, `propagate-arithmetic-child`. |
| $\hat{\pi}(X)$ and $\varepsilon_\omega$ | **Condensed heuristic expression** $\hat{\pi}(X)$ and **training residual** $\varepsilon_\omega$ (priced in bits during learning, dropped at deployment). | `condense-heuristic` (`heuristic-model` in `factor.lisp`). |

> **Key Conceptual Distinctions**
>
> 1. **Unary Per-Row Requirements (`search-job`) vs. Cross-Row Action Conservation (`observation-scope`)**:
>    - In `search-job`, each row $\omega$ carries a *unary* predicate $A_\omega(Y)$ (`row-requirement`) that judges a single output value $y_\omega = M(e, \omega)$ in isolation (e.g., learning an action $T$ sets $A_\omega(Y) := (Y = \mathbf{x}_{T\omega})$).
>    - In `observation-scope` (`observation-job`), testing whether a candidate observable $e(X)$ is **conserved under an action $T$** ($M(e, \omega) = M(e, T\omega)$) is a *relational* query across linked rows $(\omega, T\omega) \in \texttt{pairs}$ where the target value $y_\omega$ is not known in advance (and must vary across orbit `anchors`).
> 2. **Right-Inverse of `Apply` (Operation 2: Factorization) vs. Pullback (Operation 3: Predicate Precomposition)**:
>    - **Factorization** operates on *concrete witnessed values* $\{t_\omega\}_{\omega \in \Omega}$, computing a right-inverse of forward execution `Apply` by splitting $\{t_\omega\}$ into a shared pattern/table $p$ and per-row residuals $\{\theta_\omega\}$ such that $\mathrm{Apply}(p, \theta_\omega) = t_\omega$.
>    - **Pullback** operates contravariantly on *symbolic requirement predicates* $A_\omega(Y)$ via function precomposition $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$ even when $z \mapsto d(\mathbf{x}_\omega, z)$ is many-to-one or non-surjective. Once pulled back, cross-row compatibility is internalized into the per-row predicates $B_\omega(Z)$.
> 3. **Two Dual Uses of "Fiber" ($\mathrm{Fiber}(\omega) \subseteq \mathcal{V}_{\tau_C}$ vs. $\Omega_k \subseteq \Omega$), and Extensional ($j_\omega$) vs. Intensional ($\hat{\pi}(X)$) Lifting**:
>    - In **value space**, $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ is the admissible target-value set of row $\omega$, while $\theta_\omega \in \mathrm{Fiber}(\omega)$ is a single concrete residual value chosen from it.
>    - In **row space**, $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ is a level set of rows sharing a representative value $R_k$ (`quotient-values`) or a non-empty intersected fiber $\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset$ (`infer-fibers`). The cluster index vector $(j_{\omega_1}, \dots, j_{\omega_n})$ is *extensional* (indexed by $\omega \in \Omega$), whereas Operation 4 (`condense-heuristic`) synthesizes an *intensional* symbolic selector $\hat{\pi}(X)$ predicting $\hat{\pi}(\mathbf{x}_\omega) \approx j_\omega$ on new inputs and dropping Stage-1 assignment noise $\varepsilon_\omega$ at deployment.

At the heart of the kernel, every synthesis, law-discovery, decomposition, and propagation step is an instance of four interacting operations over $M(e, \omega)$:

```{=latex}
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
    >=Latex,
    box/.style={draw, rounded corners=3pt, align=left, font=\scriptsize, inner sep=5pt, fill=white, minimum height=2.7cm},
    hdr/.style={draw, rounded corners=3pt, align=center, font=\small, inner sep=6pt, fill=gray!10},
    lbl/.style={font=\scriptsize\itshape, align=center}
]
    % Top: Homoiconic Kernel
    \node[hdr, text width=16.2cm] (kernel) at (0, 0) {
        \textbf{Homoiconic S-Expression, Frame \& Metered Evaluator Kernel}\\
        Schema $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$, \quad Frame Rows $\omega \in \Omega$ with values $\mathbf{x}_\omega$, \quad Candidates $e(X) \in \mathcal{E} \subseteq \mathcal{L}(\Gamma)$\\
        Outcome Matrix $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cut}}(q)\}$, \quad $O(1)$ Cached Metadata $(\mathrm{bits}, W_{\mathrm{syn}}, \mathrm{total?}, \mathrm{vars})$
    };

    % Four Operations below
    \node[box, text width=3.75cm, anchor=north] (op1) at (-6.15, -1.7) {
        \textbf{1. Observational Conservation}\\
        \texttt{enumerate.lisp}, \texttt{laws.lisp}\\[2pt]
        $\bullet$ \textbf{Synthesis}: $A_\omega(M(e, \omega)) = \mathrm{t}$\\
        $\bullet$ \textbf{Buckets}: level sets of $M(e, \omega)$\\
        $\bullet$ \textbf{Symmetries}: $M(e, \omega) = M(e, T\omega)$\\
        \phantom{$\bullet$ }(\texttt{observation-invariants})\\
        $\bullet$ \textbf{Guards}: support masks $\Omega_{\mathrm{ok}}$
    };

    \node[box, text width=3.75cm, anchor=north] (op2) at (-2.05, -1.7) {
        \textbf{2. Factorization \& Fibers}\\
        Right-inverse of $\mathrm{Apply}$:\\
        $t_\omega = \mathrm{Apply}(p, \theta_\omega)$, keep $\theta_\omega$\\[2pt]
        $\bullet$ \textbf{Term AU}: $\mathrm{Subst}(p, \theta_\omega)$\\
        \phantom{$\bullet$ }(\texttt{anti-unify})\\
        $\bullet$ \textbf{Quotients}: $\mathrm{gather}(R, j_\omega)$\\
        $\bullet$ \textbf{Hard-EM Fibers}: cluster $B_\omega(Z)$\\
        \phantom{$\bullet$ }(\texttt{infer-fibers})
    };

    \node[box, text width=3.75cm, anchor=north] (op3) at (2.05, -1.7) {
        \textbf{3. Reorient, Pullback \& Propagate}\\
        \texttt{frame.lisp}, \texttt{vm.lisp}, \texttt{laws.lisp}\\[2pt]
        $\bullet$ \textbf{Reorient}: project $(K, C) \mapsto Z$\\
        \phantom{$\bullet$ }(\texttt{orient-observations})\\
        $\bullet$ \textbf{Pullback \& Fold}: $A_\omega(d(\mathbf{x}_\omega, Z))$\\
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
    \draw[->, thick] (op3.south) -- ++(0,-0.9) -| node[pos=0.25, below, lbl] {Folded fibers $B_\omega(Z)$ \& narrowed witnesses feed MDL condensation \& multi-lane search} (op4.south);
\end{tikzpicture}
\caption{The four fundamental operations of the Lisploop kernel interacting over the empirical outcome matrix $M(e, \omega)$.}
\end{figure}
```

### Operation 1: Observational Conservation Across Frame Rows

Given a candidate stream $\mathcal{E} \subseteq \mathcal{L}(\Gamma)$ and a finite frame $\Omega = (\omega_1, \dots, \omega_n)$, evaluating $e(X) \in \mathcal{E}$ on row $\omega$'s input value vector $\mathbf{x}_\omega$ under quantum $q$ produces an Outcome Matrix cell $M(e, \omega)$ with three possible outcomes:

- `:value` --- total evaluation returning a domain-valid payload $v \in \mathcal{V}_\tau$,
- `:error` --- domain or operational error (e.g., division by zero, out-of-bounds `:gather`, missing `:lookup` key, or failed `:code-*` assertion),
- `:unknown` / `:cutoff` --- resource exhaustion when the evaluation debt exceeds the work budget.

Every discovery task in Milestones 1--4 is a conservation query over $M(e, \omega)$, distinguishing **unary per-row satisfaction** from **cross-row relational conservation**:

- **Function Synthesis via Unary Row Requirements (`search-job`, M1)**: Each row $\omega \in \Omega$ carries a *unary* Boolean predicate $A_\omega(Y)$ (`row-requirement`) that judges a single candidate output value $y_\omega = M(e, \omega)$ in isolation. `search-job` finds $e(X) \in \mathcal{E}$ such that $\forall \omega \in \Omega,\ A_\omega(M(e, \omega)) = \mathrm{t}$, early-exiting the row loop on the first `:error` or `nil`. For example, learning a state-transition action $T$ itself in Milestone 2 sets $A_\omega(Y) := (Y = \mathbf{x}_{T\omega})$.
- **Empirical Equivalence & Symmetries via Cross-Row Conservation (`observation-job`, `observation-invariants`, M2)**: By contrast, testing whether a candidate observable $e(X)$ is **conserved under an action $T$** ($M(e, \omega) = M(e, T\omega)$) is a *relational* property across linked rows $(\omega, T\omega) \in \texttt{pairs}$---the target value $y_\omega$ is not fixed in advance; we only require that $e$ take the *same* value before and after the action while taking at least two distinct values across orbit `anchors`. `observation-job` partitions $\mathcal{E}$ into `observation-bucket`s by complete non-error output vectors $[M(e, \omega_1), \dots, M(e, \omega_n)]$ (ranked by `expression-less-p`) and checks invariance across `observation-scope-pairs` (which automatically inherit optional `frame-pairs` and `frame-anchors` when present on a `frame`, or are constructed from transition records by `transition-probes`).
- **Exhaustive Finite-Domain Laws (`start-law-validation`, M3)**: On the exhaustive finite input grid $\Omega = D^\Gamma$, verifies $\forall \omega \in \Omega,\ \bigl(G(\mathbf{x}_\omega) \implies e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega)\bigr) = \mathrm{t}$ with positive active support ($\exists \omega,\ G(\mathbf{x}_\omega) = \mathrm{t}$).
- **Partial-Domain Support Masks & Exact Guards (`observed-support`, `propose-guard-problems`, `propose-guarded-laws`, M3/M4)**: When `:retain-outcomes t` is enabled on an `observation-job`, any partially valid expression or equation pair $(e_1, e_2)$ partitions $\Omega$ into its **positive support rows** $\Omega_{\mathrm{ok}} = \{\omega \in \Omega \mid e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega) \in \mathcal{V}_\tau\}$ and **failure/error rows** $\Omega_{\mathrm{fail}} = \Omega \setminus \Omega_{\mathrm{ok}}$. Synthesizing an exact guard $G(X)$ on `support-frame` is simply synthesizing a Boolean predictor via `search-job` conserved on the indicator $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$ with zero residual error ($\varepsilon_\omega \equiv 0$).

### Operation 2: Factorization & Latent Fiber Inference ($S$ Compression)

Whereas forward evaluation applies a shared operator or template $p$ to a row-specific argument $\theta_\omega$ to produce a concrete value $t_\omega = \mathrm{Apply}(p, \theta_\omega) \in \mathcal{V}_\tau$, lossless factorization computes a **right-inverse of `Apply`**: given a collection of concrete values $\{t_\omega\}_{\omega \in \Omega}$ (either base values or quoted `:code` ASTs), it factors them into a shared template $p$ and per-row residuals $\{\theta_\omega\}_{\omega \in \Omega}$ minimizing $S(p) + S(\{\theta_\omega\}) + \lambda_{\mathrm{run}} W_{\mathrm{run}}$:

1. **Term Algebra (`anti-unify`, M3B Law Corpus & M6 Anti-Unification)**: Each $t_\omega \in \mathcal{V}_{\texttt{(:code ...)}}$ is a quoted S-expression; $\mathrm{Apply}$ is syntactic hole substitution $\mathrm{Subst}(p, \theta_\omega)$ (`instantiate` / `:code-subst`). `anti-unify` computes the least general generalization (LGG) pattern $p$ (with typed holes `?0`, `?1`, $\dots$) and the per-row residual subtree tuples $\theta_\omega$. Repeated identical disagreement tuples map to the same hole ID (enforcing diagonal equality constraints), and compatible operator disagreements generalize to function-sorted `:hole`s.
2. **Sequence Algebra (`quotient-values` & `partition-rows`, M1/M5/M7 Quotients & Partitions)**: Each $t_\omega = y_\omega \in \mathcal{V}_\tau$ is a concrete value; $\mathrm{Apply}$ is indexed sequence lookup `(gather R j_w)`. `quotient-values` factors $\{y_\omega\}_{\omega \in \Omega}$ into a deduplicated sequence of unique representatives $R$ and integer index residuals $\theta_\omega = j_\omega \in \{0, \dots, |R|-1\}$, while `partition-rows` splits occurrence rows into level-set subframes $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ with exact permutation reassembly (`partition-model`).
3. **Latent Fiber & Partition Inference via Hard EM (`infer-fibers`, M5/M7)**:
   When every row's target requirement is already a concrete singleton `(= Z 'v_w)`, `quotient-values` groups identical values $v_\omega$ directly. However, when row requirements $B_\omega(Z)$ are **multi-valued or relational** (e.g., `(member Z '(2 3))`, `(= (/ Z '2) '1)`, or unconstrained `'t`), we do not have a single value $t_\omega$ on every row---instead, each row $\omega$ specifies an admissible **target-value fiber** $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$. Crucially, once a parent requirement $A_\omega(Y)$ has been pulled back through a decoder $Y = d(X, Z)$ to per-row child predicates $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$, cross-row compatibility is *already internalized* into the unary predicates $B_\omega(Z)$: two rows $\omega_i, \omega_j$ can share a latent coordinate $z$ iff $\mathrm{Fiber}(\omega_i) \cap \mathrm{Fiber}(\omega_j) \neq \emptyset$. To cluster $\Omega$ into $K$ latent classes $j_\omega \in \{0, \dots, K-1\}$ (with row level-sets $\Omega_k$ and narrowed class requirements $B_{c_k}(Z) = \bigwedge_{\omega \in \Omega_k} B_\omega(Z)$) without an external witness oracle or explicit `frame-pairs`, `infer-fibers` performs **confidence-ordered Hard EM over row requirements**:
   - **Pre-simplification & Tightness Ranking**: Each row requirement $B_\omega(Z)$ is simplified via `fold-constants` and ranked by `fiber-tightness-rank`: rank 0 (singleton `(= X0 'c)` or 1-element `:member`), rank 1 (finite set `(member X0 '(c1 ...))` ordered by ascending cardinality), and rank 2 (general Boolean predicate), breaking ties by `syntax-work`.
   - **Cannot-Link Soundness Filter**: Two symbolic requirements $B_A(Z), B_B(Z)$ cannot share a `fiber-class` if `(conjoin-requirements B_A B_B target-type)` constant-folds to `'nil` ($\mathrm{Fiber}(A) \cap \mathrm{Fiber}(B) = \emptyset$).
   - **E-Step (Free Coverage)**: If conjoining row $\omega$'s requirement $B_\omega(Z)$ with an existing `fiber-class-requirement` $B_c(Z)$ leaves $B_c(Z)$ unchanged (`equal`), then $\mathrm{Fiber}(c) \subseteq \mathrm{Fiber}(\omega)$ is already satisfied for free ($\Delta S = 0$), and $\omega$ joins class $c$ immediately (committed tight fibers disambiguate wider-fiber rows).
   - **M-Step (Coverage-Vote Amortized Merging / Nucleation)**: Otherwise, each compatible class $c$ is scored by its marginal description-bit increase $\Delta S = \max\bigl(0,\, S(B_c \land B_\omega) - S(B_c)\bigr)$ divided by its compatibility **coverage votes** ($1 + \text{number of remaining unassigned rows compatible with } B_c \land B_\omega$). Row $\omega$ merges into the lowest-cost compatible class, or nucleates a new `fiber-class` if all existing classes are incompatible. Once `infer-fibers` assigns each row $\omega \in \Omega_k$ its narrowed requirement $B_{c_k}(Z)$ (or class index $j_\omega = k$), synthesizing a child coordinator $c(X)$ via `search-job` automatically enforces invariance across all rows within each fiber $\Omega_k$.

### Operation 3: Causal Reorientation, Pullback, Closed-Subtree Constant Folding & Dual-Grade Propagation

1. **Reorientation (`orient-observations`, `orient-arithmetic-requirements`)**: Projects raw witnessed records `(key . values)` into a `frame` with chosen input columns $\mathbf{x}_\omega$ (`schema-inputs`) and target column(s) $Y$ (`schema-target`) without executing any simulation.
2. **Pullback (`pullback-frame`) & Closed-Subtree Constant Folding (`fold-constants`)**:
   - Given a parent `frame` with symbolic row requirements $A_\omega(Y)$ and a decoder expression $Y = d(X, Z)$ over symbolic parent inputs $X$ and latent child variable $Z$, `pullback-frame` substitutes the row's known input values $X \gets \mathbf{x}_\omega$ and `(var 0 child-type)` into $d$, and precomposes $A_\omega(Y)$ with the resulting decoder to form the symbolic child requirement $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$.
   - `fold-constants` simplifies open requirement S-expressions bottom-up: any **closed subtree** `(null (free-vars subtree))` is evaluated in the metered VM (`evaluate`), replacing the subtree with `(lit type value)` on `:value` or propagating `:error` cleanly (`(= err Z)` $\to$ `'nil`). It also folds `:if` on literal conditions, propagates singleton equalities `(= Z 'c)` into `:if` branches, intersects `:member` sets and predicates, and decomposes tuple equalities `(= (tuple e1 e2) '(v1 v2))` into conjunctions of element equalities.
3. **Conflict Detection (`frame-conflict-p`)**: Checks a frame for unsatisfiability in $O(|\Omega|)$:
   - **Row-level contradiction (`:unsatisfiable-row`)**: A single row's requirement $B_\omega(Z)$ folds to `'nil` (e.g., `(= (tuple Z Z) '(2 3))` decomposes into `(if (= Z '2) (= Z '3) 'nil)` and folds to `'nil`).
   - **Cross-row contradiction (`:incompatible-rows`)**: Two or more rows sharing identical `row-known` input values $\mathbf{x}_\omega$ have requirements whose conjunction via `conjoin-requirements` folds to `'nil`.
4. **Dual-Grade Downward Propagation (`propagate-arithmetic-child`)**: Matches a parent frame and decoder against a `propagator-library` of discovered arithmetic solvers $q(K, C)$ with guard $G(K, C)$:
   - **Certified ($\iff$, `certified-p = t`)**: Replaces the child row's requirement $B_\omega(Z)$ in-place with `(set-requirement domain (list witness-value))`, shrinking the child verification frame.
   - **Tentative ($\Leftarrow$, `certified-p = nil`)**: Evaluates the guard and witness $v_\omega = q(k_\omega, c_\omega)$ on each row and **forward-verifies** $B_\omega(v_\omega) = \mathrm{t}$ against the original pulled-back requirement `row-requirement`. Rows that pass populate a narrowed `propagation-frame` while `propagation-fallback` retains the original pullback frame.

### Operation 4: Lossy Heuristic Condensation & Multi-Lane Search Control

1. **Residual-Priced Heuristic Condensation (`condense-heuristic`)**: Compresses a frame $F$ into a compact `heuristic-model` in two stages:
   - First, runs `infer-fibers` on $F$ to resolve ambiguous fibers into a `refined-frame`.
   - Second, runs `observation-job` with `:retain-outcomes t` over `language`, scoring each candidate symbolic expression $\hat{\pi}(X)$ by the two-part MDL objective:
     $$J_{\mathrm{heuristic}}(\hat{\pi}) = S(\hat{\pi}) + S\bigl(\varepsilon(\hat{\pi}, F)\bigr) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(\hat{\pi})$$
     where every row $\omega_i$ where $\hat{\pi}(\mathbf{x}_{\omega_i})$ fails to satisfy $B_{\omega_i}(Z)$ pays its exact row-index and witness-value bit cost:
     $$\Delta S_{\mathrm{miss}}(i) = \mathrm{positive\text{-}bit\text{-}size}(i + 1) + \mathrm{value\text{-}bit\text{-}size}(w_i, \tau)$$
   - Returns the minimum-score `heuristic-model` whose deployed `(heuristic-program model)` is the bare symbolic S-expression $\hat{\pi}^*(X)$ with the training residual $\varepsilon$ discarded.
2. **Multi-Lane Scheduler with 1-in-4 Canonical Reserve (`propagation-search`)**: Coordinates a tentative `:primary` search lane (over `propagation-frame`) and a canonical `:fallback` search lane (over `propagation-fallback`):
   - Every 4th quantum (`(= 3 (mod turn 4))`) is reserved for `:fallback`; the other 3 quanta advance `:primary` (or `:verification`).
   - Any candidate discovered by `:primary` is replayed against `:original` (`:verification` lane) before it can enter `propagation-search-results`, guaranteeing soundness and completeness even when tentative integer witnesses fail or miss multi-valued fibers.

---

## 3. Epistemic, Isolation, and Accounting Contracts

### 3.1 Strict Information Isolation

- **No Hidden Oracle Calls**: All benchmark generators in `fixtures.lisp` emit only plain `frame`s or `(key . values)` records. No oracle AST or closure ever crosses into the synthesizer.
- **Self-Hosted Meta-Programs**: Because the type system includes quoted syntax types $\tau = \texttt{(:code } \Gamma'\ \sigma\texttt{)}$, quoted object-language ASTs are first-class runtime values $v \in \mathcal{V}_\tau$. When a meta-level artifact (an anti-unification constructor, a rewrite rule transformer, or a propagator matcher) is applied during search, it is lowered into an explicit symbolic DSL program (`:code-*` operators), statically validated once per `(versions, scope)` (`validated-program`), and executed inside the metered VM.

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

1. **Closed-Subtree Evaluation (`eval-closed-expr`)**: Whenever an application has `(null (free-vars expr))`, it is evaluated in the VM up to `budget`. If it returns `:value`, it is replaced by `(lit result-type value)`; if it returns `:error`, `fold-node` propagates the failure cleanly (e.g., an equality `(= err Z)` folds to `'nil`).
2. **Conditional & Equality Simplification**:
   - `(:if 't yes no)` $\to$ `yes`; `(:if 'nil yes no)` $\to$ `no`.
   - When `cond` is a singleton equality `(= Z 'v)` on a symbolic variable $Z$, substitutes $\texttt{Z} \mapsto \texttt{'v}$ into `yes` via `instantiate` and re-folds `yes`.
   - Conjunctions `(if a b 'nil)` intersect finite sets and singletons: if `a` is `(= Z 'v)` or `(member Z '(v1 ...))`, filters the values against `b` and reduces to `'nil` (when empty), `(= Z 'v)` (when $1$ value remains), or `(member Z filtered)` (when multiple values remain).
3. **Tuple Injectivity Decomposition**: Decomposes $\texttt{(= (tuple } e_1 \dots e_k\texttt{) '(} v_1 \dots v_k\texttt{))}$ into the conjunction $\texttt{(and (= } e_1\ \texttt{'} v_1\texttt{) } \dots \texttt{ (= } e_k\ \texttt{'} v_k\texttt{))}$ and re-folds, immediately reducing diagonal conflicts like `(= (tuple Z Z) '(2 3))` to `'nil`.

---

### Module 4: `frame.lisp` --- Frames, S-Expression Requirements, Pullbacks, Conflicts, Views & Quotients

#### Pure S-Expression Row Requirements (`row`, `frame`)

A `frame` consists of `(schema rows pairs anchors)` where `pairs` and `anchors` are optional action-linkage / orbit-separation metadata (defaulting to `nil`). Each `row` holds `(key known requirement)` where `row-known` is the input value vector $\mathbf{x}_\omega$ and `row-requirement` is a Boolean S-expression $A_\omega(Y)$ or $B_\omega(Z)$ over `(var 0 target-type)`:

- `singleton-requirement`: `(app (op := type) (var 0 type) (lit type value))` --- `(= X0 'v)`.
- `set-requirement`: `(app (op :member type) (var 0 type) (lit (sequence-type type) values))` --- `(member X0 '(v1 ...))`.
- General predicates: any Boolean AST over `(var 0 target-type)` (e.g., `(lit :bool t)` for unconstrained probe frames, or pulled-back relational predicates).
- `extract-allowed-values`: Inspects a requirement S-expression and returns `nil` for `'nil`, `(list v)` for `(= X0 'v)`, `'(v1 ...)` for `(member X0 '(v1 ...))`, or `:unknown` for general predicates.
- `check-requirement`: Evaluates a requirement S-expression on a candidate `value` in the VM.

#### Conjunction, Conflict Detection, Pullback, Views & Quotients

- `conjoin-requirements`: Conjoins two requirements over `(var 0 target-type)` via `(fold-constants (bool-and req1 req2) schema)`.
- `frame-conflict-p`: Returns a `frame-conflict` struct (`:kind :unsatisfiable-row` or `:incompatible-rows`) if any row requirement folds to `'nil` or if rows sharing identical `row-known` input values $\mathbf{x}_\omega$ conjoin to `'nil`.
- `orient-observations`, `transition-probes`, `lookup-model`: `transition-probes` converts a frame of recorded action transitions $\mathbf{x}_\omega \mapsto \mathbf{x}_{T\omega}$ into unconstrained `:before` / `:after` probe rows with `frame-pairs` wired for `observation-scope`.
- `pullback-frame` & `compose-model`: Pulls a parent frame back through $Y = d(X, Z)$ into $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$, folds closed subtrees via `fold-constants`, and composes synthesized child programs into parent solutions.
- `support-frame`, `partition-rows`, `reassemble-partition`, `partition-model`.
- `quotient-values`, `restore-quotient`, `quotient-model`.

---

### Module 5: `enumerate.lisp` --- Size-Partitioned Enumerator, Search, Observations & Multi-Lane Propagation Search

- **Exact-Bit Bottom-Up Enumerator (`language`, `enumerator`, `enumeration-step`)**: Enumerates well-typed ASTs $e(X) \in \mathcal{L}(\Gamma)$ in strictly non-decreasing order of `body-size` bits, using `integer-literals-of-bit-size` to invert the Elias/zigzag bit-length formula analytically and sorting each bucket by `expression-less-p`.
- **Resumable Synthesis (`search-job`: `start-search`, `resume-search`)**: Evaluates enumerated or replayed candidates against a `frame` with optional normal-form rejection caching (`:library`) when a validated `rewrite-library` is supplied.
- **Resumable Observation Discovery (`observation-scope`, `observation-job`: `make-observation-scope`, `start-observation-search`, `resume-observation-search`)**: Evaluates $\mathcal{E} \times \Omega$, groups total evaluations into typed-value `observation-bucket`s, checks conservation across `pairs` ($M(e, \omega) = M(e, T\omega)$, defaulting to `frame-pairs`) and variation across `anchors` (defaulting to `frame-anchors`), and optionally retains per-row outcomes (`:retain-outcomes t`) for guard and solver discovery.
- **Multi-Lane Propagation Search (`propagation-search`: `start-propagation-search`, `resume-propagation-search`)**: Schedules `:primary`, `:fallback` (1-in-4 reserve), and `:verification` (forward replay on `:original`).

---

### Module 6: `factor.lisp` --- Pattern Matching, Anti-Unification, `infer-fibers`, `condense-heuristic` & Corpus Compression

- `match-pattern`: First-order pattern matcher supporting value holes and operator holes with consistent repeated-hole bindings.
- `anti-unify` & `compile-au-constructor`: Typed LGG with memoized disagreement tuples and lowering to `:code-apply` / `:code-subst` DSL constructors.
- `infer-fibers`: Confidence-ordered Hard-EM latent fiber inference over row requirements $B_\omega(Z)$, returning `(values classes labels refined-frame partition)`.
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
| **M2: Observational Equivalence, Symmetries/Invariants & Replay** | Implemented via `observation-job` (`enumerate.lisp`) and `transition-probes` (`frame.lisp`). Driven by `experiments.lisp` (`m2`); tested in `tests/observations.lisp` and `tests/visualizer.lisp`. | **Complete & Verified** (matches [results.md](results.md)) |
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
