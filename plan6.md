---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,fit,backgrounds,calc}
---

# lisploop --- plan 6

## One homoiconic kernel: conservation, factorization, pullback, and heuristic condensation

30 October 2026. Refines and stress-tests [plan 5](plan5.md) against the full scope of [prompt.md](prompt.md), [plan 4](plan4.md), and the empirical findings in [results.md](results.md). The nine research pillars, strict cost accounting ($S$, $W_{\rm run}$, $W_{\rm search}$), resumable budgets, and information-isolation contracts remain authoritative. What changes is a streamlined, genuinely homoiconic Common Lisp architecture built around **four fundamental operations**, unifying **exact guards, runtime errors, and approximate heuristics/names** under a single Minimum Description Length (MDL) and computational-work model while cutting seven redundant mechanisms (~1,500+ lines of scaffold code) from the Milestone 1--4 implementation.

---

## 1. Diagnosis and stress-test of `plan4` and `plan5`

The Milestone 1--4 implementation passes 82 tests and 187,382 checks ([results.md](results.md)), validating that the research questions in [plan 4](plan4.md) are well-posed. However, reviewing the 16 source files (~2,600 LOC) alongside [plan 5](plan5.md) exposes both the accidental complexity of the `plan4` scaffold and five subtle technical traps in `plan5` that must be resolved before coding.

### 1.1 What `plan5` diagnosed correctly

1. **Fighting Lisp's homoiconicity with verbose AST wrappers and a second `:code-*` sub-language**:
   Instead of native S-expressions `(+ a (* 2 b))`, `syntax.lisp` wraps every node in property lists repeating the type at every leaf (`(:app (:op :+ (:gf 5)) ((:var 0 (:gf 5)) (:lit (:gf 5) 2)))`). To manipulate syntax as data in Milestone 3, `symbolic.lisp` and `laws.lisp` lowered every rewrite rule and propagator matcher into a 25-node interpreted `:code-*` program where:
   - Each of the $k$ `:code-bind` nodes re-ran full tree pattern matching (`match-code`) from scratch just to extract one variable.
   - Each `:code-less` node called `encode-model` twice from scratch, allocating two bit-vectors on every attempted match just to compare expression sizes.
   - Consequently, applying a single rule (`a+0=a`) across 649 candidates in M3 saved 7,732 evaluation units but spent **545,921 work units** inside rewriting (and 2,126,539 before preparation caching).
2. **Six duplicate state machines for budget preemption**:
   `evaluation`, `search-job`, `observation-job`, `law-validation`, `rewriting`, and `propagation-search` each hand-roll ad-hoc `:phase` and `:debt` loops for the same resumable stepping pattern.
3. **Separate subsystems for identical mathematics**:
   Pullback (`frames.lisp`), equational rewriting (`laws.lisp`), and algebraic propagation (`propagation.lisp`) were built as separate engines, even though algebraic propagation is simply guarded rewriting + constant folding on the pulled-back requirement predicate $B_\omega(z) \equiv A_\omega(d(x_\omega, z))$.

### 1.2 Five stress-test corrections to `plan5`

Stress-testing [plan 5](plan5.md) against the existing test suite and Milestones 5--9 reveals five places where `plan5` must be tightened:

1. **Bidirectional type inference requires an ambient numeric `domain` in the schema $\Gamma$**:
   In `plan5`, expressions are bare S-expressions `(+ a (* 2 b))` typed by an outer schema $\Gamma$. Top-down expected-type propagation (bidirectional typing) determines operand types for `+`, `-`, `*`, `/`, `if`, `tuple`, `gather` (whose second argument is always `(:seq :int)`), and `code-child` (whose index is always `:int`). However, type-erasing operators (`=`, `member`) return `:bool`, which does not specify the operand type on closed ground terms like `(= 0 0)`. Because GF(5) and GF(7) never mix in a single unquoted runtime expression ([plan 4](plan4.md)), declaring the single **ambient numeric `domain`** (`:int` or `(:gf p)`) inside $\Gamma = (\text{domain}, \text{inputs}, \text{target})$ makes bidirectional type inference 100% unambiguous on pure, untagged S-expressions.
2. **Schema-parametric $O(1)$ bit-size caching (and avoiding 64-bit `lex-rank` overflow)**:
   `plan5` proposed caching a 64-bit `(cons body-bits lex-rank)` on each AST node. However, in Version 7 packets (`codec.lisp`), a variable reference costs $2 + \lceil \log_2 \max(1, |\Gamma_{\text{inputs}}|) \rceil$ bits, which depends on the number of inputs in $\Gamma$, and expressions in M3/M4 reach 76--416 bits (overflowing a 64-bit integer rank). Instead, interned AST nodes cache schema-independent `(non-var-bits, var-count, syntax-work, total-p, free-vars)` at construction time. Then for *any* schema $\Gamma$:
   $$\mathrm{body\text{-}size}(e, \Gamma) = \mathrm{non\text{-}var\text{-}bits}(e) + \mathrm{var\text{-}count}(e) \cdot \lceil \log_2 \max(1, |\Gamma_{\text{inputs}}|) \rceil$$
   is computed in $O(1)$ integer arithmetic, and `expr-less-p` compares `body-size` in $O(1)$ before breaking ties by fast structural comparison without allocating bit-vectors.
3. **Orientation and epistemic grades in checker-AST propagation ($\iff$ vs. $\Leftarrow$)**:
   - *Orientation*: General simplification rules (`(+ ?x 0) -> ?x`) are oriented by decreasing bit size (`expr-less-p`). Algebraic solve rules (`(= (+ ?k ?z) ?c) -> (= ?z (- ?c ?k))`) isolate the target variable `z`; before constant folding, the RHS `(+ ?c (* 4 ?k))` can be *larger* in bit size than the LHS! Solve rules must therefore be oriented by **reducing the depth/occurrences of the unknown variable `z` on the LHS** (with $z \notin \mathrm{free\text{-}vars}(\text{RHS})$) followed immediately by constant-folding the `z`-free guard $G(k_\omega, c_\omega)$ and witness $q(k_\omega, c_\omega)$.
   - *Epistemic grades*: Over finite fields, exhaustively validated uniqueness laws ($\iff$) license **in-place replacement** of $B_\omega(z)$ by `(= z v_w)`. Over integers (where laws are sample conjectures and truncating division `z/2 = 1` has a multi-valued fiber $\{2, 3\}$), a witness law is only a directional implication ($\Leftarrow$). It cannot overwrite $B_\omega(z)$ in-place; instead, it forward-verifies $B_\omega(v_\omega) = \mathrm{t}$ and populates a **heuristic preferred frame** scheduled 3:1 against the retained fallback frame $B_\omega(z)$.
   - *Unlocking latent values*: Reducing an opaque predicate $B_\omega(z)$ to `(= z v_w)` turns the latent variable $z_\omega$ into an **explicitly observed target value $v_\omega$**, which is what enables value bucketing (M2), `quotient-values` (M5/M7), and immediate partition conflict detection ($\texttt{(= z 2)} \land \texttt{(= z 3)} \to \mathrm{nil}$ in M8C).
4. **Uniform `job` stepper invariants**:
   To preserve exact ledger categories and `quantum = 1` vs. batch continuation parity across all 82 tests, `job` stores `(debt, debt-category)`, and every `step-fn` either incurs atomic debt via `(incur-debt job category amount)` or delegates to a child `job`.
5. **The missing 4th operation — Computational compression via heuristics, guards, and names**:
   `plan5` covered lossless description-length ($S$) factorization, but left out a first-class mathematical operation for **lossy/heuristic condensation** (where residuals are priced during learning and discarded at deployment) to compress search and execution work ($W_{\rm search}, W_{\rm run}$).

---

## 2. The four-operation mathematical framework

Across all nine pillars of [prompt.md](prompt.md) and [plan 4](plan4.md), the synthesizer operates on a single structure—a **Frame of Occurrences** $\omega \in \Omega$ over a typed context $\Gamma = (\text{domain}, \text{inputs}, \text{target})$—and performs **four fundamental operations**:

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
        \textbf{Homoiconic S-Expression, Frame \& Metered Stepper Kernel}\\
        Context $\Gamma = (\mathrm{domain}, x_1:\tau_1,\dots,x_m:\tau_m \to \tau)$, \quad Occurrences $\omega \in \Omega$, \quad S-Expressions $e \in \mathcal{L}(\Gamma)$\\
        Outcome Matrix $M(e, \omega) = \mathrm{Eval}(e, \omega) \in \mathrm{Val} \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$, \quad $O(1)$ Cached Metadata $(\mathrm{bits}, W_{\mathrm{syn}}, \mathrm{total?}, \mathrm{vars})$
    };

    % Four Pillars below
    \node[box, text width=3.75cm, anchor=north] (cons) at (-6.15, -1.7) {
        \textbf{1. Observational Conservation}\\
        Level sets of $M(e, \omega)$ on $\Omega$:\\[2pt]
        $\bullet$ \textbf{Synthesis (M1)}: $B_\omega(e(\omega)) = \mathrm{t}$\\
        $\bullet$ \textbf{Invariants (M2)}: $e(\omega) = e(T\omega)$\\
        $\bullet$ \textbf{Laws (M3)}: $e_1 = e_2$ on $D^\Gamma$\\
        $\bullet$ \textbf{Exact Guards (M3/4)}: compress\\
        \phantom{$\bullet$ }support mask $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$ to $\varepsilon = 0$
    };

    \node[box, text width=3.75cm, anchor=north] (fact) at (-2.05, -1.7) {
        \textbf{2. Factorization \& Fiber EM}\\
        Right-inverse of $\mathrm{Apply}$:\\
        $t_\omega = \mathrm{Apply}(p, \theta_\omega)$, keep $\theta_\omega$\\[2pt]
        $\bullet$ \textbf{Term AU (M3/6)}: $\mathrm{Subst}(p, \theta_\omega)$\\
        $\bullet$ \textbf{Seq quotient (M5/7)}: $\mathrm{gather}(R, j_\omega)$\\
        $\bullet$ \textbf{Hard-EM fibers (M5/7)}: infer\\
        \phantom{$\bullet$ }latent class $j_\omega$ on $B_\omega(z)$
    };

    \node[box, text width=3.75cm, anchor=north] (pull) at (2.05, -1.7) {
        \textbf{3. Pullback \& Rewrite}\\
        Pull back $B_\omega(z) = A_\omega(d(x_\omega, z))$:\\[2pt]
        $\bullet$ \textbf{Fold closed subtrees} ($z$-free)\\
        $\bullet$ \textbf{Certified $\iff$ (M4/8A)}: isolate\\
        \phantom{$\bullet$ }$z$, replace $B_\omega(z)$ with $(= z\ v_\omega)$\\
        $\bullet$ \textbf{Witness $\Leftarrow$ (M4 $\mathbb{Z}$)}: verify\\
        \phantom{$\bullet$ }$B_\omega(v_\omega)$, spawn preferred lane
    };

    \node[box, text width=3.75cm, anchor=north] (heur) at (6.15, -1.7) {
        \textbf{4. Heuristic Condensation}\\
        Compress $W_{\mathrm{search}}, W_{\mathrm{run}}$:\\[2pt]
        $\bullet$ \textbf{Learn $\hat{\pi}$} via MDL with priced\\
        \phantom{$\bullet$ }error residual $S(\hat{\pi}) + S(\varepsilon) + \lambda W$\\
        $\bullet$ \textbf{Deploy}: drop $\varepsilon$ for intensional\\
        \phantom{$\bullet$ }selectors (M5/7) \& Agenda (M8/9)\\
        $\bullet$ \textbf{Verify} on $B_\omega$ + $1/4$ reserve
    };

    % Arrows from kernel
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (cons.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (fact.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (pull.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (heur.north);

    % Cross-links at bottom
    \draw[->, thick] (fact.south) -- ++(0,-0.45) -| node[pos=0.25, below, lbl] {Residuals $\theta_\omega, z_\omega$ form child frames} (cons.south);
    \draw[->, thick] (pull.south) -- ++(0,-0.9) -| node[pos=0.25, below, lbl] {Explicit targets $(= z\ v_\omega)$ \& trace costs feed MDL heuristic/policy synthesis} (heur.south);
\end{tikzpicture}
\caption{All nine milestones factor through four operations over one homoiconic S-expression kernel.}
\end{figure}
```

### 2.1 Operation 1: Observational conservation over fibers

Let $\Omega$ be a set of occurrences and $\mathcal{E}$ be a stream of candidate S-expressions. Evaluating $\mathcal{E} \times \Omega$ produces the **Outcome Matrix** $M(e, \omega) \in \text{Val} \cup \{\bot_{\text{err}}, \bot_{\text{cutoff}}\}$. Every discovery task in Milestones 1--4 is a conservation query on $M$:

- **M1 (Function synthesis)**: Single fiber $\Omega$; find $e$ such that $\forall \omega \in \Omega,\ B_\omega(M(e, \omega)) = \mathrm{t}$ (early-exiting the row loop on the first $\bot_{\text{err}}$ or `nil`).
- **M2 (Behavioral equivalence & trajectory invariants)**: Partition $\mathcal{E}$ by complete non-error output vectors $[M(e, \omega_1), \dots, M(e, \omega_n)]$; for trajectory pairs $\omega \sim T(\omega)$, require $M(h, \omega) = M(h, T\omega)$ within orbits and variation across anchor starts.
- **M3 (Finite-domain laws)**: On the exhaustive grid $\Omega = D^\Gamma$, check $\forall \omega \in \Omega,\ (G(\omega) \Rightarrow e_1(\omega) = e_2(\omega)) = \mathrm{t}$.
- **M3/M4 (Support masks & exact guards)**: Any partially successful expression or equation $e$ partitions $\Omega$ into its **valid fiber** $\Omega_{\text{ok}}(e) = \{\omega \mid M(e, \omega) = \mathrm{t}\}$ and **failure/error fiber** $\Omega_{\text{fail}}(e) = \{\omega \mid M(e, \omega) \in \{\mathrm{nil}, \bot_{\text{err}}\}\}$. Synthesizing an exact guard $G(\omega)$ is simply synthesizing a Boolean predictor conserved on the indicator $\mathbf{1}_{\Omega_{\text{ok}}(e)}(\omega)$.

### 2.2 Operation 2: Factorization and latent fiber inference ($S$ compression)

Forward execution applies a shared operator $p$ to an occurrence-specific argument $\theta_\omega$: $t_\omega = \mathrm{Apply}(p, \theta_\omega)$. Lossless compression factors $\{t_\omega\}_{\omega \in \Omega}$ into a conserved template/program $p$ and a fiber residual $\{\theta_\omega\}_{\omega \in \Omega}$ minimizing $S(p) + S(\{\theta_\omega\}) + \lambda_{\rm run} W_{\rm run}$:

1. **Term Algebra (M3 Law Corpus & M6 Anti-Unification)**: $t_\omega$ are quoted S-expressions; $\mathrm{Apply}$ is syntactic substitution $\mathrm{Subst}(p, \theta_\omega)$; `anti-unify` computes the LGG pattern $p$ and residual subtree tuples $\theta_\omega$.
2. **Sequence Algebra (M5/M7 Quotients & Partitions)**: $t_\omega$ are concrete values; $\mathrm{Apply}$ is `(gather representatives residual-indices)`; `quotient-values` factors $\{t_\omega\}$ into unique representatives $R$ and integer index residuals $j_\omega \in \{0, \dots, |R|-1\}$.
3. **Value Algebra (M5 Lifting & M8A Recursive Synthesis)**: $t_\omega = y_\omega$ are parent target values; $\mathrm{Apply}$ is a decoder expression $d(x_\omega, z_\omega)$; lifting turns the unknown fiber coordinate $z_\omega$ into a child synthesis target governed by pulled-back requirement $B_\omega(z) \equiv A_\omega(d(x_\omega, z))$.
4. **Latent Fiber & Partition Inference via Hard EM (`infer-fibers`, M5/M7)**:
   When $B_\omega(z)$ is already reduced to an exact singleton `(= z v_w)` on every row, `quotient-values` groups identical $v_\omega$ directly. However, when pulled-back fibers $B_\omega(z)$ are **multi-valued or relational** (e.g., `(member z '(2 3))`, `(= (/ z 2) 1)`, or unconstrained `t`), or when occurrences must be grouped into latent classes $j_\omega \in \{0, \dots, K-1\}$ before a selector expression is known, `infer-fibers` performs **extensional Hard EM on the partition lattice**:
   - **Cannot-link soundness filter**: Two rows/classes $A, B$ cannot merge if their conjoined fiber requirement folds to `nil` ($B_A(z) \land B_B(z) \xrightarrow{\text{fold}} \mathrm{nil}$) or induces a same-input conflict on the child frame.
   - **Confidence-ordered E-step / M-step**: Order occurrences from most constrained (singletons `(= z v)` first, then small finite sets, then general predicates) to least constrained:
     - **E-step**: If an existing class $c$'s narrowed fiber/witness already satisfies $B_\omega(z)$, assign $\omega \to c$ for free (committed high-confidence classes disambiguate wider-fiber rows).
     - **M-step**: Otherwise, commit the sound merge (`attach` to an existing class, `consolidate` two classes, or `nucleate` a new class) that minimizes marginal description-length cost $\Delta S$ amortized over **coverage votes** (how many remaining rows' $B_{\omega'}(z)$ are compatible with the narrowed class fiber $B_c(z) \land B_\omega(z)$).

### 2.3 Operation 3: Causal reorientation, pullback, and dual-grade checker rewriting

Recording forward executions $c = f(a, b)$ converts a causally directed primitive into a relational table governed by the definedness-and-equality predicate $R_f(a, b, c) \iff \mathrm{defined}_f(a, b) \land (f(a, b) = c)$. Reorientation (`orient-observations`) selects which columns are known inputs and which is the unknown target $z$.

When a parent frame with row requirements $A_\omega(y)$ is decomposed through a decoder $y = d(x_\omega, z)$, **pullback (`pullback-frame`)** substitutes $d(x_\omega, z)$ for $y$ and substitutes the row's known inputs $x_\omega$, producing the child requirement S-expression $B_\omega(z) \equiv A_\omega(d(x_\omega, z))$.

Simplifying $B_\omega(z)$ proceeds in two steps using the same rewrite engine as Milestone 3:

1. **Eager constant folding of closed subtrees (`fold-constants`)**:
   During `pullback-frame`, any subexpression of $B_\omega(z)$ with no free variable `z` (for example, `(* a a)` in `(= (+ (* a a) z) y)` when $a = 2^{128} + i$ is known on row $\omega$) is evaluated once per row and replaced by its literal value (or $\bot_{\text{err}} \to \mathrm{nil}$ if it errors).
2. **Variable isolation via learned solve rules ($\iff$ vs. $\Leftarrow$)**:
   Milestone 4 learns a witness $q(k, c)$ and guard $G(k, c)$ for $R_f(k, z, c)$:
   - **Certified Equivalence ($\iff$, exhaustive finite fields)**:
     When $\forall k, c, z:\ G(k, c) \Rightarrow (R_f(k, z, c) \iff z = q(k, c))$ is certified, matching $R_f(k_\omega, u(z), c_\omega)$ inside $B_\omega(z)$ (where $z \notin \mathrm{free\text{-}vars}(k_\omega, c_\omega)$) evaluates $G(k_\omega, c_\omega)$ by constant folding. If `t`, it rewrites $R_f(k_\omega, u(z), c_\omega) \to \texttt{(= } u(z)\ v_\omega\texttt{)}$ where $v_\omega = \mathrm{fold}(q(k_\omega, c_\omega))$ **in-place**, strictly reducing the depth of `z` (handling nested decoders $y = a + b \cdot k$ in M8A automatically by induction on depth!).
   - **Conjectured or Multi-Valued Witness ($\Leftarrow$, integers)**:
     When only $G(k, c) \Rightarrow R_f(k, q(k, c), c)$ holds as a sample conjecture (or when $R_f$ has multiple solutions, as in integer truncating division `z / 2 = 1` where $z \in \{2, 3\}$), the rewrite is **not** equivalence-preserving. The kernel folds $v_\omega = q(k_\omega, c_\omega)$, **forward-verifies** $B_\omega(v_\omega) = \mathrm{t}$ using the original checker, and emits `(= z v_w)` into a **heuristic preferred frame** while retaining the original $B_\omega(z)$ in the **fallback frame**.

### 2.4 Operation 4: Heuristic condensation and agenda ordering ($W$ compression)

How do runtime errors ($\bot_{\text{err}}$), exact guards ($G$), and approximate heuristics, search policies (M8D), or compositional function names (M9) fit into a single cost and execution model?

Consider any candidate expression, rewrite rule, or heuristic predictor $\hat{g}(\omega)$ evaluated across $\Omega$:

1. **Pricing errors in computation ($W$)**:
   Every VM primitive prepays its full structural and bit-width cost *before* executing, even when it errors (e.g., `1/0` pays the division tariff before returning $\bot_{\text{err}}$). In contrast, a lazy conditional `(if G(x) (/ x x) 0)` evaluates only `G(x)` when `G(x)` is `nil`, avoiding both the error and the execution cost of `(/ x x)`.
2. **Exact guards as zero-residual compression of the error/failure mask ($S$ vs. $W$)**:
   Let $\varepsilon_\omega = \mathbf{1}_{\Omega_{\text{ok}}(\hat{g})}(\omega) \in \{\mathrm{t}, \mathrm{nil}\}$ be the indicator of rows where $\hat{g}(\omega)$ does not error and satisfies the target relation.
   - Storing $\varepsilon_\omega$ as a literal exception mask costs $S(\varepsilon) \sim |\Omega|$ bits.
   - Synthesizing an **exact guard** $G(\omega) \equiv \varepsilon_\omega$ replaces the literal mask with a Boolean program of size $S(G)$ and execution cost $W_{\rm run}(G)$, reducing the residual classification error to **zero**.
3. **Intensional selectors, heuristics, policies, and names as lossy MDL condensations (discarding $\varepsilon_\omega$ at deployment)**:
   When learning an intensional context/partition selector $\hat{\pi}(x_\omega) \approx j_\omega$ from Hard-EM inferred classes (M5/M7), a search heuristic $\hat{\pi}(\phi(\omega))$ (M8D), or a compositional function descriptor/name (M9) from execution traces $\{y_\omega\}$, we use the **exact same synthesizer and MDL objective**:
   $$\min_{\hat{\pi}} \Big[ S(\hat{\pi}) + S(\{\varepsilon_\omega\}) + \lambda_{\rm run} W_{\rm run}(\hat{\pi}) \Big], \qquad y_\omega = d(\hat{\pi}(\phi(\omega)), \varepsilon_\omega).$$
   - **During discovery**, pricing the residual error $S(\{\varepsilon_\omega\})$ alongside $S(\hat{\pi}) + \lambda_{\rm run} W_{\rm run}(\hat{\pi})$ forces $\hat{\pi}$ to be a compact, fast, bounded-computation predictor of the target or inferred class $j_\omega$.
   - **At deployment**, we **discard the residual $\varepsilon_\omega$**:
     - For **intensional lifting/partitioning (M5/M7)**, replacing the extensional class labels $j_\omega$ by $\hat{\pi}(x_\omega)$ both generalizes to unobserved occurrences and drops noisy Stage-1 class assignments before checking against $B_\omega(z)$.
     - For **search control and retrieval (M7 locality, M8D, M9)**, $\hat{\pi}$ orders/prioritizes the **Agenda** of pending search jobs, decompositions, or library entries.
   - **Why discarding $\varepsilon_\omega$ is always safe and self-pricing**: Every candidate proposed by a prioritized or partitioned lane is still checked against the authoritative Frame requirement $B_\omega(z)$, and a fixed **1-in-4 canonical reserve** advances the unguided stream. If an approximate selector, heuristic, or unguarded integer witness produces a false positive or a runtime error $\bot_{\text{err}}$ on a held-out row, it simply pays the wasted verification cost in $W_{\rm search}$ and is rejected by $B_\omega(z)$.

| Control knowledge type | Residual $\varepsilon_\omega$ on scope | Certified on domain? | Permitted effect in kernel |
|---|---|---|---|
| **Checked conflict (M8C)** | $\Omega_{\text{ok}} = \emptyset$ ($\varepsilon \equiv \mathrm{nil}$) | Yes (exact fold to `nil`) | Prune branch immediately (`priority = 0`) |
| **Certified equivalence law ($\iff$, M3/M4 GF($p$))** | $\varepsilon \equiv 0$ under guard $G$ | Yes (exhaustive $D^\Gamma$) | Rewrite expression or checker $B_\omega(z)$ **in-place** |
| **Verified witness conjecture ($\Leftarrow$, M4 $\mathbb{Z}$)** | $\varepsilon = 0$ on training grid | No (sample conjecture / multi-valued fiber) | Forward-check $B_\omega(v_\omega) = \mathrm{t}$; schedule preferred frame 3:1 over fallback frame |
| **Hard-EM fiber / selector lift (M5, M7)** | $\varepsilon$ from Stage-1 EM dropped by $\hat{\pi}(x_\omega)$ | Verified on $B_\omega(z)$ | Consolidate compatible fibers $B_\omega(z)$ into classes $j_\omega$, then synthesize intensional selector $\hat{\pi}(x_\omega)$ |
| **Heuristic policy / Locality / Name (M7, M8D, M9)** | $\varepsilon \neq 0$ (priced during learning, **dropped** at deployment) | No (lossy condensation) | Order Agenda priority queue; validate all candidates against $B_\omega(z)$ with $1/4$ canonical reserve |

---

## 3. Seven removals that streamline the kernel without losing generality

By leaning fully into homoiconic S-expressions, bidirectional typing, checker-AST rewriting, and the unified Agenda, we remove seven ceremonial subsystems from `plan4` and the current 16-file codebase:

1. **Remove `:code-*` rule/matcher compilation and static-validation caches** (`compile-rule-transformer`, `compile-propagator-matcher`, `validated-program`, `rewrite-library-program-cache`, and `tests/amortization.lisp` --- **~450 LOC removed**):
   In a homoiconic kernel, a law `(if G (= lhs rhs) t)` is already a native S-expression. Pattern matching (`match-expr`), substitution (`subst-expr`), totality (`provably-total-p`), and size comparison (`expr-less-p`) execute directly as metered operations on S-expressions without compiling rules into a second 25-node `:code-bind` AST. Quoted code `(:code schema sort)` remains a first-class value for M3/M6/M8A/M9 symbolic synthesis, with $O(1)$ cached `:code-total` / `:code-less` and single-pass match binding.
2. **Remove bit-slicing law-corpus compression** (`law-compression.lisp` and `:concat` --- **~200 LOC removed**):
   A law corpus is a sequence of quoted S-expressions `'(law_1 ... law_N)`. Anti-unification factors the corpus at the AST level into a template $p$ and substitution tuples $[\theta_1, \dots, \theta_N]$ compressed by `quotient-values` (`gather`) and priced directly by `codec.lisp`, without converting ASTs into `:bool` bit-lists inside the VM.
3. **Remove the bespoke 3-stage solver-guard pipeline in `algebra.lisp`** (`learn-solver-guard` --- **~80 LOC removed**):
   In `plan4`, M4 needed three separate Boolean searches and a synthetic 3-column feature frame `(k, c, f(k, q(k,c)))` only because the guard grammar excluded the forward check `(= f(k, q(k,c)) c)`. Including the forward residual check (or arithmetic operators) in the guard language reduces M4 solver-guard discovery to the **exact same 1-step `support-frame` guard search** used in M3.
4. **Merge `observation-scope` / `observation-job` into `frame` / `matrix-job`** (`observations.lisp` vs. `search.lisp` --- **~220 LOC removed**):
   A single `Frame(schema, rows, pairs, anchors)` and a single `matrix-job` handle both synthesis (early row-rejection when $B_\omega(e(\omega))$ fails) and observation (full row evaluation, output-vector equivalence bucketing, and per-row outcome retention for guard discovery).
5. **Merge `propagation.lisp` and `propagation-search.lisp` into `laws.lisp` + the Agenda** (**~235 LOC removed**):
   `pullback-frame` folds closed subtrees automatically; `propagate-frame` applies certified $\iff$ solve rules in-place on $B_\omega(z)$ and applies conjectured $\Leftarrow$ witness rules to spawn a forward-verified preferred frame scheduled by the general Agenda.
6. **Remove the separate `allowed` wrapper struct** (`finite-allowed` vs. `predicate-allowed` in `frames.lisp` --- **~40 LOC removed**):
   Every row requirement is a Boolean S-expression $B_\omega(z)$ in variable `z`: `(= z v)` for a singleton, `(member z '(v1 v2))` for a finite set, or `(= (+ 1 (* 2 z)) 0)` for a general relation. A 3-line helper `extract-allowed-values(expr)` extracts explicit values when needed by `lookup-model`, `transition-probes`, or conflict checking.
7. **Unify Milestones 8D (Search Preferences) and 9 (Vocabulary) under Operation 4**:
   Both branch-selection policies (8D) and library descriptors/names (M9) are scoring expressions $\hat{\pi}$ learned via MDL with priced residuals and deployed by dropping residuals to rank entries in the Agenda (backed by the 1-in-4 canonical reserve).

---

## 4. Concrete worked examples in the `plan6` kernel

### Example 1: Pure S-expressions, bidirectional typing, and $O(1)$ schema-parametric sizing

A schema $\Gamma$ specifies `(domain inputs target)`:

```lisp
(defstruct schema
  (domain :int)   ; ambient numeric domain: :int or (:gf p)
  inputs          ; ordered alist: ((a . (:gf 5)) (b . (:gf 5)))
  target          ; result type: (:gf 5), :bool, (:tuple ...), (:seq ...), (:code ...)
  (lookup-p nil))
```

Expressions are native S-expressions interned via a lightweight constructor that caches structural metadata in a hash-table (or struct wrapper with native S-expression printing):

| Surface S-expression | Inferred types under $\Gamma = (\text{GF}(5), (a, b) \to \text{GF}(5))$ | Cached $O(1)$ node metadata |
|---|---|---|
| `(+ a (* 2 b))` | `+`, `*`, `a`, `b`, `2` all `:gf 5` | `non-var-bits = 19`, `var-count = 2`, `syntax-work = 25`, `total-p = t`, `free-vars = (a b)` |
| `(if (= a 0) 0 (/ a b))` | `=` compares `:gf 5`; `if` returns `:gf 5` | `non-var-bits = 33`, `var-count = 3`, `syntax-work = 36`, `total-p = nil`, `free-vars = (a b)` |
| `(gather '(1 3) '(0 1 0))` | `' (1 3)` is `(:seq (:gf 5))`; `'(0 1 0)` is `(:seq :int)` | `non-var-bits = 64`, `var-count = 0`, `syntax-work = 29`, `total-p = nil`, `free-vars = ()` |

Because `non-var-bits` and `var-count` are cached at construction time, `body-size` for any schema $\Gamma$ with $m = |\Gamma_{\text{inputs}}|$ is a single $O(1)$ arithmetic formula:

```lisp
(defun body-size (expr schema)
  (+ (expr-non-var-bits expr)
     (* (expr-var-count expr) (integer-length (max 0 (1- (length (schema-inputs schema))))))))
```

### Example 2: Dual-grade checker-AST rewriting (Milestones 4, 8A, and 8C)

Suppose a parent frame over $\Gamma_P = (\text{domain}, (a, b) \to y)$ is pulled back through a decoder $d(a, b, z)$ to a child frame over $\Gamma_C = (\text{domain}, (b) \to z)$:

1. **Eager constant folding during `pullback-frame` (M4 expensive-context control)**:
   Parent decoder is `(+ (* a a) z)` with $a = 2^{128} + i$ and observed output $y_\omega$.
   Substituting $a \gets 2^{128} + i$ into `(= (+ (* a a) z) y_w)` and calling `fold-constants` notices that `(* (2^128 + i) (2^128 + i))` has no free variable `z`, evaluates it **once** during pullback to literal $K_\omega = (2^{128}+i)^2$, and produces:
   $$B_\omega(z) \equiv \texttt{(= (+ } K_\omega\ \texttt{z) } y_\omega\texttt{)}.$$
2. **Certified field propagation ($\iff$, GF(5))**:
   Applying the certified uniqueness law $\text{Law}_+:\ \texttt{(= (+ ?k ?z) ?c)} \to \texttt{(= ?z (- ?c ?k))}$ rewrites $B_\omega(z)$ in-place to `(= z (- y_w K_w))` $\xrightarrow{\text{fold}}$ `(= z v_w)`.
   On a nested decoder $y = a + b \cdot z$ (Milestone 8A), two steps of isolation + constant folding reduce `(= (+ 1 (* 2 z)) 0)` $\to$ `(= (* 2 z) 4)` $\to$ `(= z 2)` automatically.
3. **Conjectured / multi-valued integer propagation ($\Leftarrow$, `:int`)**:
   On `z / 2 = 1` and `z / 3 = 1` for the same child input $b = 0$:
   The numerator witness $q(k, c) = k \cdot c$ proposes $v_1 = 2$ for row 1 and $v_2 = 3$ for row 2. Both pass individual forward verification $B_1(2) = \mathrm{t}$ and $B_2(3) = \mathrm{t}$.
   Because the law is only a witness conjecture ($\Leftarrow$), the kernel keeps the original frame $B_1(z) \equiv \texttt{(= (/ z 2) 1)}$, $B_2(z) \equiv \texttt{(= (/ z 3) 1)}$ as the fallback lane, and places the singleton frame $B_1^{\text{pref}}(z) \equiv \texttt{(= z 2)}$, $B_2^{\text{pref}}(z) \equiv \texttt{(= z 3)}$ in the preferred lane.
4. **Immediate conflict detection (Milestone 8C)**:
   In the preferred lane above (or in an invalid Milestone 7 partition), two rows with identical child input $b = 0$ have singleton checkers `(= z 2)` and `(= z 3)`. Conjoining requirements for identical known inputs folds `(= 2 3)` $\to$ `nil`! The preferred lane is **immediately refuted in $O(1)$** without enumerating a single candidate program, handing 100% of remaining quanta to the fallback lane (which finds the shared solution $z = 3$!).
   Similarly, pulling back `(= y '(2 3))` through decoder `(tuple z z)` yields `(= (tuple z z) '(2 3))` $\to$ `(and (= z 2) (= z 3))` $\to$ `nil`, immediately refuting the decoder `(tuple z z)`.

### Example 3: Two-stage topological lifting — Hard-EM fiber inference to intensional selector synthesis (Milestones 5 & 7)

When decomposing $y_\omega = d(x_\omega, z_\omega)$ where $z_\omega$ depends on a hidden or unaligned context class $j_\omega \in \{0, \dots, K-1\}$, enumerating candidate selector programs $k(x_\omega)$ top-down and running child synthesis for every candidate selector is combinatorially expensive. Instead, `plan6` separates **Stage 1 (extensional fiber/partition inference)** from **Stage 2 (intensional selector synthesis)**:

1. **Pullback to fiber predicates (Operation 3)**:
   Pulling back $A_\omega(y)$ through $d(x_\omega, z)$ yields per-occurrence fiber requirements $B_\omega(z)$. Some rows simplify via $\iff$ laws to singletons (`(= z 1)`, `(= z 3)`), while others remain multi-valued or relational (e.g., `(member z '(1 2))`, `(= (/ z 2) 1)`, or `t`).
2. **Stage 1 — Extensional Hard EM over fiber compatibility (`infer-fibers`, Operation 2)**:
   `infer-fibers` clusters $\Omega$ into $K$ extensional classes $\Omega = \bigsqcup_{j=0}^{K-1} \Omega_j$ with class fiber $B^{(j)}(z) = \bigwedge_{\omega \in \Omega_j} B_\omega(z)$:
   - **Cannot-links**: Any merge where $B_A(z) \land B_B(z) \xrightarrow{\text{fold}} \mathrm{nil}$ (for example, merging a row requiring `(= z 1)` with one requiring `(= z 3)` on the same child input) is immediately vetoed.
   - **Confidence-ordered E-step / M-step**: Singletons and tight fibers are processed first, founding clean classes $c_0: \texttt{(= z 1)}$ and $c_1: \texttt{(= z 3)}$. When an ambiguous row $\omega$ with `(member z '(1 2))` arrives, the **E-step** sees that $c_0$ ($z=1$) already satisfies $B_\omega(z)$ for free, resolving the hidden variable $j_\omega = 0$ without nucleating a spurious class for $z=2$.
3. **Stage 2 — Intensional selector synthesis (`condense-heuristic`, Operation 4)**:
   Once Stage 1 assigns an extensional class index $j_\omega \in \{0, \dots, K-1\}$ to each row, $j_\omega$ becomes an **explicit integer target column** over available inputs $x_\omega = (r_\omega, t_\omega)$. Standard synthesis under Operation 4 learns a compact selector $\hat{\pi}(x_\omega) \approx j_\omega$ minimizing $S(\hat{\pi}) + S(\{\varepsilon_\omega\}) + \lambda_{\rm run} W_{\rm run}(\hat{\pi})$, drops any Stage-1 noise residuals $\varepsilon_\omega$ at deployment, and verifies the resulting lifted program $d(x_\omega, g(\hat{\pi}(x_\omega)))$ against the authoritative parent frame.

### Example 4: One metered `job` stepper and Multi-Lane `agenda`

Every resumable computation is driven by a single `job` struct that preserves exact ledger categories and `quantum = 1` vs. batch parity:

```lisp
(defstruct job
  id
  (status :unknown)       ; :unknown | :complete | :bounded-exhaustion | :cutoff | :refuted | :error
  (ledger (make-ledger))
  (debt 0)                ; unpaid tariff units for the current atomic step
  (debt-category :work)   ; exact ledger category for pending debt
  step-fn                 ; (lambda (job budget quantum)) — only called when debt = 0
  state                   ; job-specific state struct
  results
  messages)

(defun incur-debt (job category amount)
  (setf (job-debt job) amount
        (job-debt-category job) category))

(defun advance-job (job work-limit &key quantum)
  "Pay pending debt first; only invoke step-fn when debt = 0."
  (loop while (and (eq :unknown (job-status job))
                   (< (ledger-total (job-ledger job)) work-limit))
        for remaining = (- work-limit (ledger-total (job-ledger job)))
        for budget = (if quantum (min quantum remaining) remaining) do
          (if (plusp (job-debt job))
              (let ((paid (min budget (job-debt job))))
                (decf (job-debt job) paid)
                (charge (job-ledger job) (job-debt-category job) paid))
              (funcall (job-step-fn job) job budget quantum)))
  job)
```

Multi-lane scheduling (M4 integer propagation, M7 locality, M8 recursive DAG search, M8D learned policies, and M9 vocabulary retrieval) is a single `agenda` state running inside a `job`:

- An `agenda` holds a list of **lanes** `(lane job weight priority verifier-frame)`.
- Every 4th quantum is reserved for the **canonical lane** (weight $1/4$); the remaining 3 quanta advance the highest-priority active heuristic lane.
- Any candidate emitted by a heuristic lane with a `verifier-frame` is replayed against `verifier-frame` before acceptance.

---

## 5. Module architecture of the `plan6` kernel (~850 LOC total)

| Module | Replaces (`plan4` files) | Responsibilities |
|---|---|---|
| **`1. ast.lisp`** | `syntax.lisp`, `symbolic.lisp` (part) | Homoiconic S-expressions, bidirectional type checker over $\Gamma = (\text{domain}, \text{inputs}, \text{target})$, interned $O(1)$ metadata (`non-var-bits`, `var-count`, `syntax-work`, `total-p`, `free-vars`), `subst-expr`, `expr-less-p`. |
| **`2. codec.lisp`** | `codec.lisp` | Exact prefix-coded binary serializer (`encode-model`, `decode-model`, $O(1)$ `description-size` and `body-size`). |
| **`3. vm.lisp`** | `sim.lisp` | Structural tariff (`value-work`, `syntax-work`), uniform `job` / `advance-job` stepper, metered S-expression evaluator, and closed-subtree partial evaluator (`fold-constants`). |
| **`4. frame.lisp`** | `frames.lisp`, `guards.lisp` | `Frame(schema, rows, pairs, anchors)` with Boolean S-expression requirements $B_\omega(z)$, `orient-observations`, `pullback-frame` (with automatic `fold-constants` and M8C conflict detection), `support-frame`, `quotient-values`, and `partition-rows`. |
| **`5. enumerate.lisp`** | `grammar.lisp`, `search.lisp`, `observations.lisp`, `propagation-search.lisp` | Size-partitioned S-expression enumerator, **Unified Matrix Evaluator** $M(e, \omega)$ (synthesis + observation buckets + outcome retention), and the **Multi-Lane Agenda** (with 1-in-4 canonical reserve and heuristic ordering $\hat{\pi}$). |
| **`6. factor.lisp`** | `au.lisp`, `law-compression.lisp`, `symbolic.lisp` (part) | Typed first-order matching (`match-expr`), aligned & subtree anti-unification (`anti-unify`), Hard-EM latent fiber/partition inference (`infer-fibers`), AST-level corpus compression via templates + `gather` quotients, and lossy heuristic condensation (MDL scoring with residual drop at deployment). |
| **`7. laws.lisp`** | `laws.lisp`, `algebra.lisp`, `propagation.lisp` | Law records `(if G (= lhs rhs) t)`, exhaustive finite-domain & sampled validation, fast S-expression normalizer (`rewrite-expr`), 1-step guard/solver discovery, and **dual-grade checker-AST propagation** ($\iff$ in-place rewrite vs. $\Leftarrow$ forward-verified agenda lane). |

---

## 6. How all nine milestones execute on this kernel

| Milestone | Execution in the `plan6` kernel |
|---|---|
| **1. Search** | `matrix-job` in synthesis mode over `Frame`; interruption/resumption via `advance-job`; pullback control via `pullback-frame` + `compose-model`. |
| **2. Learned equivalence** | `matrix-job` in observation mode over `Frame` with `pairs` and `anchors`; equivalence bucketing on complete rows. |
| **3. Laws** | Span equalities from M2 buckets; partial-outcome support masks $\to$ `support-frame` Boolean synthesis for guards $G$; exhaustive $D^\Gamma$ validation; AST-level AU corpus compression; fast S-expression `rewrite-expr`. |
| **4. Algebra** | Forward grid execution $\to$ definedness guard $\to$ reoriented relational frame $R_f(k, z, c)$. Witness selection by MDL coverage prior; 1-step `support-frame` solver guard (with $f(k, q(k,c))$ in language); dual-grade $\iff$/$\Leftarrow$ checker-AST propagation. |
| **5. Lifting** | `pullback-frame` with context projection $\pi(r, t)$; withholding $r$ folds pulled-back singleton checkers on identical $t$ to `nil` (exposing missing fiber context); `quotient-values` / `infer-fibers` recover the latent fiber assignment $j_\omega$. |
| **6. Abstraction** | `match-expr`, `anti-unify`, and subtree path decomposition $t_\omega = C_\omega[s_\omega]$ in `factor.lisp`, priced directly by `codec.lisp`. |
| **7. Partitioning & locality** | Two-stage view discovery: Stage 1 (`infer-fibers` / `quotient-values`) clusters compatible row fibers $B_\omega(z)$ into extensional classes $j_\omega$; Stage 2 synthesizes intensional selector $\hat{\pi}(x_\omega) \approx j_\omega$ via Operation 4 (reassembled by `gather`). Locality prioritizes candidate pairs in the `agenda` with a $1/4$ canonical reserve. |
| **8. Recursion** | **8A**: Multi-step pullback + checker-AST rewriting across nested decoders. **8B**: DAG of `job` instances scheduled by `agenda`. **8C**: Tuple injectivity and same-input singleton conjunction fold impossible child checkers to `nil`. **8D**: Synthesize search-return predictor $\hat{\pi}$ via Operation 4 (MDL with residual dropped at deployment) to order the `agenda`. |
| **9. Vocabulary & language** | Library definitions receive opaque IDs and short symbolic descriptors $\hat{\pi}$ learned via Operation 4 on behavioral probes; given a new Frame query, descriptors rank library entries in the `agenda` before canonical enumeration. |
