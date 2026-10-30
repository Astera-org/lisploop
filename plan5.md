---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,fit,backgrounds,calc}
---

# lisploop --- plan 5

## One homoiconic kernel: observational conservation, factorization, and causal pullback

29 October 2026. Synthesizes the architectural and mathematical lessons from implementing Milestones 1--4 of [plan 4](plan4.md) (documented in [results.md](results.md)). The nine research pillars, strict cost accounting ($S$, $W_{\rm run}$, $W_{\rm search}$), resumable budgets, and information-isolation contracts of `plan4.md` remain unchanged. What changes is the **internal representation and conceptual factorization**: replacing six parallel state machines, verbose non-homoiconic AST wrappers, and a duplicate symbolic sub-language with a small, genuinely homoiconic Common Lisp kernel built around three mathematical operations.

## 1. Diagnosis: accidental complexity in the Milestone 1--4 scaffold

The implementation of Milestones 1--4 passes 77 test suites and 185,011 checks, proving that the research questions in `plan4.md` are well-posed and testable. However, inspecting the 16 source files (~2,600 lines of Common Lisp) and the empirical cost ledgers in `results.md` reveals three sources of accidental complexity.

### 1.1 Fighting Lisp's homoiconicity with verbose tagged ASTs and a second sub-language

Instead of representing expressions as native S-expressions `(+ a (* 2 b))` typed against a lexical schema, `syntax.lisp` wraps every node in property-list tags that repeat the domain type at every leaf and operator:

```lisp
(:app (:op :+ (:gf 5)) ((:var 0 (:gf 5)) (:lit (:gf 5) 2)))
```

When Milestone 3 needed to manipulate expressions as data (`symbolic.lisp`), instead of using Lisp's native quotation `'expr` and treating syntax trees as ordinary sequences/tuples, the scaffold introduced a **second parallel language** of nine `:code-*` primitives (`:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`, `:code-subst`, `:code-total`, `:code-less`) and a parameterized type `(:code inputs sort)` that embeds an entire variable schema inside every AST node's type tag.

This caused a severe, self-inflicted performance penalty in Milestone 3 (`results.md`, "Cost of using checked equations in a second search"):

- `compile-rule-transformer` in `laws.lisp` lowers a rewrite rule `lhs = rhs` into an interpreted `:code-*` AST.
- To bind $k$ pattern variables, it emits a `:code-match` node followed by $k$ separate `:code-bind` nodes. In `execute-symbolic-primitive`, **every `:code-bind` call re-runs `match-code` from scratch** on the entire tree just to extract one variable.
- Next, `:code-less` calls `encode-model` to serialize **both** candidate expressions into fresh bit-vectors from scratch on every attempted match just to compare their sizes.
- Consequently, applying the single rule `a+0=a` across 649 candidates saved 7,732 evaluation units but spent **545,921 work units** inside rewriting (and 2,126,539 units before preparation caching). The overhead was not an intrinsic property of equational rewriting; it was the tax of simulating pattern matching through stateless AST opcodes.

### 1.2 Six hand-rolled state machines for budget preemption

To support `quantum = 1` interruption tests, the codebase implements **six separate manual state-machine structs** with ad-hoc `:phase`, `:tasks`, and `:debt` fields:

1. `evaluation` (`sim.lisp`: `:validate-program`, `:validate`, `:eval`, `:branch`, `:apply`)
2. `search-job` (`search.lisp`: 11 phases from `:proposal-setup` to `:check`)
3. `observation-job` (`observations.lisp`: 7 phases from `:setup` to `:index`)
4. `law-validation` (`laws.lisp`: 4 phases from `:setup` to `:equation`)
5. `rewriting` (`laws.lisp`: 6 task tags from `:setup` to `:try`)
6. `propagation-search` (`propagation-search.lisp`: multi-lane scheduler)

Yet `search-job`, `observation-job`, and `law-validation` execute the exact same computational pattern: *iterate over a stream of candidate expressions $\times$ a stream of occurrence rows, evaluate each cell under a work budget, and aggregate outcomes*. Duplicating this loop across 700+ lines of manual phase-switching obscures the core algorithms.

### 1.3 Parallel subsystems for what are mathematically identical operations

In the current codebase:

- **Requirement checking** has two representations (`finite-allowed` vs. `predicate-allowed` in `frames.lisp`).
- **Pullback** (`pullback-frame` in `frames.lisp`), **rewrite normalization** (`laws.lisp`), and **algebraic propagation** (`propagation.lisp` + `propagation-search.lisp`) are three separate engines, each with its own matcher, preparation cache, and execution loop.
- **Anti-unification** (`au.lisp`), **symbolic constructor lowering** (`symbolic.lisp`), **quotient reconstruction** (`frames.lisp`), and **law corpus compression** (`law-compression.lisp`) are implemented as four separate mechanisms.

## 2. The unifying mathematical framework

Across all nine pillars of `plan4.md`, the synthesizer operates on a single structure—a **Frame of Occurrences** $\omega \in \Omega$ over a typed variable context $\Gamma$—and performs **three fundamental operations**:

```{=latex}
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
    >=Latex,
    box/.style={draw, rounded corners=3pt, align=left, font=\footnotesize, inner sep=6pt, fill=white},
    hdr/.style={draw, rounded corners=3pt, align=center, font=\small, inner sep=7pt, fill=gray!10},
    lbl/.style={font=\scriptsize\itshape, align=center}
]
    % Top: Frame & Evaluator (16.0cm wide)
    \node[hdr, text width=16.0cm] (kernel) at (0, 0) {
        \textbf{Homoiconic Frame \& Metered Evaluator Kernel}\\
        Context $\Gamma = (x_1:\tau_1,\dots,x_m:\tau_m)$, \quad Occurrences $\omega \in \Omega$, \quad S-Expressions $e \in \mathcal{L}(\Gamma)$\\
        Outcome Matrix $M(e, \omega) = \mathrm{Eval}(e, \omega) \in \mathrm{Val} \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$
    };

    % Three Pillars below (anchored by north at y = -1.75)
    \node[box, text width=4.9cm, anchor=north] (cons) at (-5.65, -1.75) {
        \textbf{1. Observational Conservation}\\
        Level sets of $M(e, \omega)$ across $\Omega$:\\[2pt]
        $\bullet$ \textbf{Synthesis (M1)}: $R_\omega(e(\omega)) \equiv \mathrm{true}$\\
        $\bullet$ \textbf{Invariants (M2)}: $e(\omega) = e(T\omega)$\\
        $\bullet$ \textbf{Laws (M3)}: $e_1 = e_2$ on $\Omega = D^\Gamma$\\
        $\bullet$ \textbf{Guards (M3/4)}: indicator $G(\omega)$\\
        \phantom{$\bullet$ }of support fiber $\Omega_{\mathrm{true}}(e_1 = e_2)$
    };

    \node[box, text width=4.9cm, anchor=north] (fact) at (0, -1.75) {
        \textbf{2. Factorization (Inverse Apply)}\\
        Decompose $\{t_\omega\}_{\omega\in\Omega}$ into shared $p$\\
        and residual $\theta_\omega$: $t_\omega = \mathrm{Apply}(p, \theta_\omega)$\\[2pt]
        $\bullet$ \textbf{Term algebra (M6 AU)}: $\beta$-expansion\\
        $\bullet$ \textbf{Seq algebra (M5/7)}: $\mathrm{gather}(R, i_\omega)$\\
        $\bullet$ \textbf{Value algebra (M5/8)}: $d(x_\omega, z_\omega)$\\
        \vphantom{$\bullet$ of support}
    };

    \node[box, text width=4.9cm, anchor=north] (pull) at (5.65, -1.75) {
        \textbf{3. Causal Reorientation \& Pullback}\\
        Embed directed $f(a,b)=c$ into $\Gamma_f$:\\[2pt]
        $\bullet$ \textbf{Reorient (M4)}: project $(a,c) \mapsto b$\\
        $\bullet$ \textbf{Pullback (M1/5/8)}: $B_\omega(z) = A_\omega(d(x_\omega, z))$\\
        $\bullet$ \textbf{Propagate (M4)}: rewrite checker\\
        \phantom{$\bullet$ }$B_\omega(z)$ via certified law + fold
    };

    % Arrows from kernel
    \draw[->, thick] (kernel.south) -- ++(0,-0.35) -| (cons.north);
    \draw[->, thick] (kernel.south) -- (fact.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.35) -| (pull.north);

    % Cross-links at bottom
    \draw[->, thick] (fact.south) -- ++(0,-0.45) -| node[pos=0.25, below, lbl] {Residuals $\theta_\omega, z_\omega$ become child frames} ([xshift=0.8cm]cons.south);
    \draw[->, thick] ([xshift=-0.8cm]cons.south) -- ++(0,-0.95) -| node[pos=0.25, below, lbl] {Certified equivalences $G \Rightarrow (R \Leftrightarrow z=q)$ rewrite pulled-back checkers} (pull.south);
\end{tikzpicture}
\caption{All nine milestones factor through three operations over a single homoiconic frame and evaluator kernel.}
\end{figure}
```

### 2.1 Operation 1: Observational conservation over fibers

Let $\Omega$ be a set of occurrences (observed input-output rows, trajectory pairs, or exhaustive domain assignments) and $\mathcal{E}$ be an enumerated stream of typed S-expressions. Evaluating $\mathcal{E} \times \Omega$ yields an **Outcome Matrix** $M(e, \omega) \in \text{Value} \cup \{\bot_{\text{err}}\}$.

Every discovery milestone in the first half of the plan is a **conservation query** on $M$:

| Milestone | Fiber / Partition of $\Omega$ | Conserved Expression |
|---|---|---|
| **M1. Function synthesis** | Trivial single fiber $\Omega$ | $\forall \omega \in \Omega:\ R_\omega(e(\omega)) = \text{true}$ |
| **M2. Behavioral equivalence** | Pointwise across $\Omega$ | $e_1 \equiv_\Omega e_2 \iff \forall \omega \in \Omega:\ M(e_1,\omega) = M(e_2,\omega) \neq \bot_{\text{err}}$ |
| **M2. Trajectory invariants** | Transition orbits $\omega \sim T(\omega)$ | $h$ constant within each $\sim$-class ($h(\omega) = h(T\omega)$), non-constant across anchor classes |
| **M3. Universal finite-domain laws** | Complete product grid $\Omega = D^\Gamma$ | $\forall \omega \in D^\Gamma:\ (e_1(\omega) = e_2(\omega)) = \text{true}$ |
| **M3/M4. Guard discovery** | Level sets $\Omega = \Omega_{\text{true}} \sqcup \Omega_{\text{false}}$ of predicate $P(\omega)$ | Synthesize Boolean $G(\omega)$ conserved on the indicator of $\Omega_{\text{true}}$, so $(G \Rightarrow P) \equiv \text{true}$ on $\Omega$ |

Because all five are queries over the same outcome matrix $M(e, \omega)$, **there is only one evaluation engine**. A synthesis search is simply an observation job filtered by a row requirement predicate $R_\omega$ with early row-rejection when $\Omega_{\text{false}}$ is entered.

### 2.2 Operation 2: Factorization as the dual of application (AU, Lifting, Quotients)

Forward computation applies an invariant operator $p$ to an occurrence-specific argument $\theta_\omega$:

$$t_\omega = \text{Apply}(p, \theta_\omega).$$

Compression and abstraction ask for the **right-inverse (dual) of $\text{Apply}$**: given a family of observed objects $\{t_\omega\}_{\omega \in \Omega}$, factor it into a **conserved structure** $p$ (shared across all $\omega \in \Omega$) and a **fiber residual** $\theta_\omega$ (varying with $\omega$), subject to minimizing total description length $S(p) + S(\{\theta_\omega\}) + \lambda W$:

1. **In the Free Term Algebra (M6 Anti-Unification & M3 Law Compression)**:
    - Objects $t_\omega$ are quoted S-expressions.
    - $\text{Apply}$ is syntactic substitution ($\beta$-reduction): $\text{Subst}(p, \theta_\omega) = t_\omega$.
    - Anti-unification computes the least general generalizer $p = \text{LGG}(\{t_\omega\})$—which in homoiconic Lisp is literally a $\lambda$-template `(lambda (?v0 ... ?vk) body)`—together with the residual tuple of subtrees $\theta_\omega$ for each $\omega$.
2. **In the Sequence Algebra (M5/M7 Quotients & Partitions)**:
    - Objects $t_\omega$ are values in an ordered sequence.
    - $\text{Apply}$ is indexed lookup `(gather representatives residual-indices)`.
    - `quotient-values` factors $\{t_\omega\}$ into the conserved list of unique representatives $R$ and the integer index residual $\theta_\omega \in \{0, \dots, |R|-1\}$.
3. **In the Value Algebra (M5 Lifting & M8 Recursive Synthesis)**:
    - Objects $t_\omega = y_\omega$ are target values in a parent frame.
    - $\text{Apply}$ is evaluation of a decoder expression $d(x_\omega, z_\omega)$.
    - Lifting factors $y_\omega$ through $d$, turning the unknown fiber coordinate $z_\omega$ into the target of a child synthesis frame.

Because Lisp is homoiconic, all three factorizations produce ordinary S-expressions in the same language, priced by the same binary codec and executed by the same VM.

### 2.3 Operation 3: Causal reorientation, pullback, and propagation as predicate rewriting

Why does causal direction matter?

- A simulator primitive $f: A \times B \to C$ is **causally directed**: given $(a, b)$, forward execution deterministically computes $c = f(a, b)$ (or errors), whereas the inverse fiber $f_a^{-1}(c) = \{b \mid f(a, b) = c\}$ may be empty (e.g., $0 \cdot b = 1$), multivalued (e.g., $0 \cdot b = 0$, or truncating integer division $b / 2 = 1 \implies b \in \{2, 3\}$), or computationally expensive to invert.
- Once forward execution on a grid records tuples $(a, b, c) \in \Gamma_f$, the causal asymmetry is converted into a **relational table** governed by the conserved forward law:
  $$R_f(a, b, c) \iff \text{defined}_f(a, b) \land (f(a, b) = c).$$
- **Reorientation** (`orient-observations`) simply changes which columns of $\Gamma_f$ are declared inputs (the base of the fibration, say $(a, c)$) and which column is the unknown target $z = b$, governed by the requirement predicate $R_f(a, z, c)$.

Now consider what happens when a parent problem with requirement $A_\omega(y)$ is decomposed through a decoder $y = d(x_\omega, z)$:

1. **Pullback (`pullback-frame`)** substitutes $d(x_\omega, z)$ for $y$ in $A_\omega(y)$, producing the child requirement predicate:
   $$B_\omega(z) \equiv A_\omega(d(x_\omega, z)).$$
   Note that $B_\omega(z)$ is an ordinary Boolean S-expression with one free variable `z` (for example, `(= (* 2 z) 1)`).
2. **Algebraic Solver Discovery (M4)** discovers a witness expression $q(k, c)$ and a guard $G(k, c)$, and validates two ordinary Milestone 3 laws:
    - **Witness law**: `(if G(k,c) R(k,z=q(k,c),c) true)`
    - **Uniqueness (fiber-equivalence) law**: `(if G(k,c) (= R(k,z,c) (= z q(k,c))) true)`
3. **Propagation IS Guarded Law Rewriting + Constant Folding on $B_\omega(z)$**:
   In the current codebase, `propagation.lisp` and `propagation-search.lisp` build a separate 234-line subsystem (`propagator-library`, `compile-propagator-matcher`, `propagate-arithmetic-child`) to inspect the decoder AST, match the operator, evaluate the guard, evaluate the witness, and replace `predicate-allowed` with `finite-allowed`.
   **Under the unified framework, `propagation.lisp` disappears into `laws.lisp`:**
    - A certified uniqueness law is a guarded rewrite rule on Boolean expressions:
      $$R(k, z, c) \xrightarrow{\text{when } G(k, c)} (z = q(k, c)).$$
    - Normalizing the child row's checker AST $B_\omega(z)$ with this rewrite rule and **folding closed constant subexpressions** (expressions with no free variable `z`) automatically evaluates $G(k_\omega, c_\omega)$:
        - If $G(k_\omega, c_\omega)$ evaluates to `true`, $R(k_\omega, z, c_\omega)$ rewrites to `(= z q(k_w, c_w))`, and constant folding reduces `q(k_w, c_w)` to a literal constant $v_\omega$, leaving the singleton checker `(= z v_w)`!
        - If $G(k_\omega, c_\omega)$ evaluates to `false` (e.g., $0 \cdot z = 0$), the guarded rewrite does not fire, and the checker AST remains `(= (* 0 z) 0)`!

## 3. Concrete worked examples: `plan4` scaffold vs. `plan5` kernel

### Example 1: Homoiconic S-expressions and lexical schemas

In `plan4`, every AST node carries explicit tags and duplicate type descriptors. In `plan5`, expressions are native S-expressions interpreted relative to a schema $\Gamma$:

| Concept | `plan4` representation (`syntax.lisp` / `symbolic.lisp`) | `plan5` homoiconic representation |
|---|---|---|
| Schema $\Gamma$ | `((0 . (:gf 5)) (1 . (:gf 5)))` | `((a (:gf 5)) (b (:gf 5)))` |
| Arithmetic AST | `(:app (:op :+ (:gf 5)) ((:var 0 (:gf 5)) (:app (:op :* (:gf 5)) ((:lit (:gf 5) 2) (:var 1 (:gf 5))))))` | `(+ a (* 2 b))` |
| Quoted syntax | `(:lit (:code ((0 . :int)) :int) (:app (:op :+ :int) ((:var 0 :int) (:lit :int 0))))` | `'(:code ((x :int)) :int (+ x 0))` or `'(+ x 0)` under type `(:code ((x :int)) :int)` |
| Pattern / Template | `(:app (:hole 0 (:fn (:int :int) :int)) ((:hole 1 :int) (:hole 1 :int)))` | `(?op ?x ?x)` (where `?`-prefixed symbols are pattern variables in a pattern schema) |
| Row requirement | `#S(ALLOWED :TYPE (:gf 5) :VALUES (0) :EXPRESSION (:app (:op := (:gf 5)) ...))` | Boolean S-expression `(= z 0)` or `(member z '(2 3))` in context `((z (:gf 5)))` |

**Why this matters:**

- **Zero-copy homoiconicity**: A quoted expression inside a literal `(quote (+ x 0))` *is* the exact S-expression `(+ x 0)` that the evaluator, anti-unifier, and codec operate on.
- **One substitution function**: `instantiate`, `compose-model`, `pullback-frame`, and `:code-subst` collapse into a single 12-line S-expression substitution function `subst-expr(expr, bindings, schema)`.
- **Identical binary packet sizes**: `codec.lisp` walks `(op arg1 arg2)` with expected type $\tau$ from $\Gamma$ and emits the exact same prefix bits (`00` var, `01` lit, `10` app + 4-bit opcode) as Version 7.

### Example 2: Guarded rewriting without the `:code-*` compilation tax

Consider normalizing the GF(5) candidate expression `(+ (+ a 0) b)` under the validated law `(+ ?x 0) = ?x` (with guard `true`), and normalizing `(if (= x 0) 0 (/ x x))` under `(if (not (= ?x 0)) (= (/ ?x ?x) 1) true)`.

**How `plan4` (`laws.lisp` + `symbolic.lisp`) does it:**

1. `compile-rule-transformer` compiles the law into a 25-node DSL program using `:code-match`, `:code-bind`, `:code-subst`, `:code-total`, and `:code-less`.
2. At every AST node of the candidate, the VM runs this DSL program:
    - `:code-match` walks the pattern and source.
    - `:code-bind` walks the pattern and source **again** for each variable (`?x`).
    - `:code-subst` constructs the replacement and substituted guard.
    - `:code-less` calls `encode-model` on both the source and replacement, allocating bit vectors and running the full schema+body serializer to compare lengths.

**How `plan5` does it directly on S-expressions:**

1. Every constructed S-expression caches a lightweight 64-bit canonical rank `(cons body-bits lex-rank)` computed incrementally in $O(1)$ time when the node is built by `app`:
   $$\text{bits}(\text{op}(e_1, \dots, e_k)) = \text{overhead}(\text{op}) + \sum_{i=1}^k \text{bits}(e_i).$$
   Comparing two expressions with `expr-less-p` is a **single integer comparison** instead of two full bit-vector encodings!
2. A validated rule is a struct `(rule pattern replacement guard schema certificate)`.
3. Applying a rule at an S-expression node `expr` under active branch assumptions `A`:

```lisp
(defun apply-rule (rule expr assumptions ledger)
  (multiple-value-bind (theta matched-p)
      (match-expr (rule-pattern rule) expr (rule-schema rule) ledger)
    (when (and matched-p
               (every #'provably-total-p (mapcar #'cdr theta))
               (let ((g (subst-expr (rule-guard rule) theta)))
                 (or (equal g t) (member g assumptions :test #'equal))))
      (let ((repl (subst-expr (rule-replacement rule) theta)))
        (when (expr-less-p repl expr)
          repl)))))
```

- `match-expr` runs **once**, returning the binding alist `theta = ((?x . (+ a 0)))`.
- `provably-total-p`, `subst-expr`, and `expr-less-p` run directly on the S-expression with the same structural tariff charges, eliminating the $4\times$ redundant `:code-bind` traversals and the bit-encoder allocation inside `:code-less`.

### Example 3: Pullback and propagation as checker-AST rewriting (Milestones 4 & 8A)

Consider the Milestone 4 reuse problem over GF(5):

- Parent inputs: $\Gamma_P = (\texttt{a}: \text{GF}(5),\ \texttt{b}: \text{GF}(5))$, target $\texttt{y}: \text{GF}(5)$.
- True underlying function: $y = a \cdot (b + 1) \pmod 5$.
- Supplied parent decoder: $d(a, b, z) = (\texttt{* a z})$, where child $z = g(b)$ sees only $\Gamma_C = (\texttt{b}: \text{GF}(5))$.

Take two parent rows with the **same** child input $b = 1$:

- **Row $\omega_1$**: `a = 2, b = 1`, observed target `y = 4` (since $2 \cdot (1+1) = 4$). Parent checker $A_{\omega_1}(y)$ is `(= y 4)`.
- **Row $\omega_2$**: `a = 0, b = 1`, observed target `y = 0` (since $0 \cdot (1+1) = 0$). Parent checker $A_{\omega_2}(y)$ is `(= y 0)`.

**Step 1: Pullback (`pullback-frame`) is pure substitution.**
Substitute $y \gets (\texttt{* a z})$ and each row's known `a` into $A_\omega(y)$:

- Child row $\omega_1$ (`b = 1`): checker $B_{\omega_1}(z)$ is `(= (* 2 z) 4)`.
- Child row $\omega_2$ (`b = 1`): checker $B_{\omega_2}(z)$ is `(= (* 0 z) 0)`.

**Step 2: Certified solver from Milestone 4 is an ordinary guarded law.**
In Milestone 4, forward observation of `(* k z) = c` over GF(5) discovered witness `(/ c k)` under guard `(not (= k 0))` (written `(if (= k 0) nil t)`), and certified the uniqueness law:

$$\text{Law}_{\times}: \quad \texttt{(if (not (= ?k 0)) (= (= (* ?k ?z) ?c) (= ?z (/ ?c ?k))) t)}$$

**Step 3: Propagation is normalizing $B_\omega(z)$ with $\text{Law}_{\times}$ + constant folding.**
We normalize each child row's checker AST $B_\omega(z)$ using the rewrite library containing $\text{Law}_{\times}$, plus partial evaluation (evaluating any subexpression with no free variables):

- **On Row $\omega_1$**:
  $$\texttt{(= (* 2 z) 4)}$$
  Matches `(= (* ?k ?z) ?c)` with `?k = 2, ?z = z, ?c = 4`.
  Substitute into guard: `(not (= 2 0))` $\xrightarrow{\text{fold}}$ `t` (guard discharged!).
  Substitute into replacement: `(= z (/ 4 2))` $\xrightarrow{\text{fold}}$ `(= z 2)`.
  So $B_{\omega_1}(z)$ simplifies to `(= z 2)`!
- **On Row $\omega_2$**:
  $$\texttt{(= (* 0 z) 0)}$$
  Matches `(= (* ?k ?z) ?c)` with `?k = 0, ?z = z, ?c = 0`.
  Substitute into guard: `(not (= 0 0))` $\xrightarrow{\text{fold}}$ `nil` (guard fails!).
  The rewrite does not fire. $B_{\omega_2}(z)$ remains `(= (* 0 z) 0)` (which folds to `(= 0 0) -> t`, accepting any $z \in \{0,1,2,3,4\}$).

Look at what this achieves:

1. Both rows at `b = 1` are consistent ($z = 2$ satisfies `(= z 2)` and `(= (* 0 z) 0)`).
2. We do **not** need `finite-allowed` vs. `predicate-allowed` as separate types: `(= z 2)` is a singleton predicate, `(member z '(2 3))` is a finite-set predicate, and `(= (* 0 z) 0)` is an unsimplified relational predicate.
3. Multi-step propagation (Milestone 8A: $y = a + b \cdot k$, pulling back through $+$ then $\times$) works **automatically** by simply normalizing the nested checker AST `(= (+ a (* b z)) y)` with $\{\text{Law}_+, \text{Law}_\times\}$:
   $$\begin{aligned}
   \texttt{(= (+ 1 (* 2 z)) 0)} &\xrightarrow{\text{Law}_+} \texttt{(= (* 2 z) (- 0 1))} \xrightarrow{\text{fold}} \texttt{(= (* 2 z) 4)} \\
   &\xrightarrow{\text{Law}_\times} \texttt{(= z (/ 4 2))} \xrightarrow{\text{fold}} \texttt{(= z 2)}.
   \end{aligned}$$
   In `plan4`, `propagate-arithmetic-child` could only handle a single outer operator because `compile-propagator-matcher` was hardcoded to match one depth-1 application. Treating propagation as guarded law rewriting + constant folding handles arbitrary nested decoders for free!

### Example 4: Anti-unification and law compression as inverse $\beta$-reduction (Milestones 3 & 6)

Suppose Milestone 3 discovers a family of guarded laws over GF(5), such as:

- $t_1 = \texttt{(if t (= (+ a 0) a) t)}$
- $t_2 = \texttt{(if t (= (* a 1) a) t)}$
- $t_3 = \texttt{(if (not (= a 0)) (= (/ a a) 1) t)}$

In `plan4`, `law-compression.lisp` (193 lines) and `symbolic.lisp` (145 lines) implement two different mechanisms: one slices serialized bit-vectors into `:fixed` bit-fragments assembled by `concat(gather(...))`, and the other compiles `:hole` trees into `:code-apply` ASTs.

In `plan5`, anti-unification (`anti-unify`) is simply **factoring a sequence of terms $\{t_\omega\}$ into a $\lambda$-template and a residual sequence of argument tuples**:

1. Aligning $\{t_1, t_2, t_3\}$ yields the LGG pattern:
   $$p = \texttt{(if ?g (= ?lhs ?rhs) t)}$$
   with residual tuple sequence $\Theta = [(\texttt{t}, \texttt{(+ a 0)}, \texttt{a}),\ (\texttt{t}, \texttt{(* a 1)}, \texttt{a}),\ (\texttt{(not (= a 0))}, \texttt{(/ a a)}, \texttt{1})]$.
2. Each column of $\Theta$ can itself be factored by `quotient-values` (dictionary of unique subtrees + integer index sequence) or recursively anti-unified (Milestone 8).
3. Reconstructing the $i$-th law is simply applying the template $p$ to the $i$-th residual tuple $\theta_i$:
   $$\hat{t}_i = \text{Subst}(p, \theta_i).$$

### Example 5: One metered stepper instead of six state machines

Every resumable job in `lisploop` (evaluation, synthesis search, observation, law validation, rewriting, and multi-lane scheduling) is a **metered state transition system** driven by a single protocol:

```lisp
(defstruct job
  id
  (status :unknown) ; :unknown | :complete | :cutoff | :error
  (ledger (make-ledger))
  (debt 0)          ; unpaid tariff units for the current atomic step
  step-fn           ; (lambda (job budget) ...) advancing when debt = 0
  state             ; job-specific state struct
  results
  messages)

(defun advance-job (job work-limit &key quantum)
  "Uniform budget loop for ALL jobs: pay pending debt first, then step."
  (loop while (and (eq :unknown (job-status job))
                   (< (ledger-total (job-ledger job)) work-limit))
        for remaining = (- work-limit (ledger-total (job-ledger job)))
        for budget = (if quantum (min quantum remaining) remaining) do
          (if (plusp (job-debt job))
              (let ((paid (min budget (job-debt job))))
                (decf (job-debt job) paid)
                (charge (job-ledger job) :work paid))
              (funcall (job-step-fn job) job budget)))
  job)
```

Furthermore, because every job is an instance of `job`, **recursive child synthesis (Milestone 8A/8B)** and **multi-lane scheduling (Milestone 4 integer fallback / Milestone 7 locality)** require no new state-machine structs: a parent job or scheduler simply holds a priority queue / ring of child `job` objects and calls `(advance-job child quantum)`!

## 4. Architecture of the unified kernel

The 16 source files (~2,600 LOC) of the Milestone 1--4 codebase consolidate into **7 orthogonal modules** (~900 LOC total):

| Module | Replaces | Core abstractions & responsibilities |
|---|---|---|
| `1. ast.lisp` | `syntax.lisp`, `symbolic.lisp` (part) | Homoiconic S-expressions, types (`:int`, `:bool`, `(:gf p)`, `(:tuple ...)`, `(:seq ...)`, `(:code schema sort)`), lexical schemas $\Gamma$, incremental size/rank metadata, `subst-expr`, `provably-total-p`. |
| `2. codec.lisp` | `codec.lisp` | Exact prefix-coded binary serialization (`encode-model`, `decode-model`, `description-size`, `body-size`). Bit-compatible with Version 7 packets. |
| `3. vm.lisp` | `sim.lisp` | Structural tariff (`value-work`, `syntax-work`), uniform `job` / `advance-job` preemption engine, metered S-expression evaluator, and partial evaluator (`fold-constants`). |
| `4. frame.lisp` | `frames.lisp`, `guards.lisp` | `Frame(schema, rows)` where each `Row(key, known, requirement)` carries a Boolean S-expression `requirement(z)`. Includes `orient-observations`, `pullback-frame` (substitution into `requirement`), `support-frame` (indicator frame from partial outcomes), and `quotient-values` / `partition-rows`. |
| `5. enumerate.lisp` | `grammar.lisp`, `search.lisp`, `observations.lisp` | Canonical size-partitioned S-expression enumerator (`make-language`, `enumeration-step`) and the **Unified Matrix Evaluator** over $(\mathcal{E} \times \Omega)$ supporting both synthesis mode (early row-rejection on `requirement`) and observation mode (full outcome matrix + equivalence/invariance buckets). |
| `6. factor.lisp` | `au.lisp`, `law-compression.lisp`, `symbolic.lisp` (part) | Pattern matching (`match-expr`), aligned typed anti-unification (`anti-unify`), template instantiation, and corpus compression via template + quotient residuals. |
| `7. laws.lisp` | `laws.lisp`, `algebra.lisp`, `propagation.lisp`, `propagation-search.lisp` | Law records `(if guard (= lhs rhs) t)`, exhaustive finite-domain & sampled validation, fast S-expression normalizer (`rewrite-expr`), forward-to-inverse relation builder, and **propagation via checker-AST rewriting + constant folding**. |

## 5. How Milestones 5--9 plug directly into this kernel

Because the kernel is built around **Conservation**, **Factorization**, and **Pullback/Rewriting**, the remaining milestones in `plan4.md` require **no new evaluation engines or AST sub-languages**:

1. **Milestone 5 (Lifting)**:
    - A supplied lift is just a `pullback-frame` where the parent frame has coordinates $(r, t)$, the decoder is $d((r, t), z) = \iota(t) + z$, and the child binding is $j = \pi(r)$.
    - When $r$ is withheld ($\pi$ depends only on $t$), the pulled-back checker predicates $B_{(r,t)}(z)$ for rows with identical $t$ but different $r$ simplify via $\text{Law}_+$ to contradictory requirements `(= z 1)` and `(= z 3)` on the same child input $t$—immediately exposing the missing fiber coordinate!
2. **Milestone 6 (Abstraction / Subtree Occurrence Search)**:
    - Whole-tree AU is already `factor.lisp`.
    - Hidden-occurrence abstraction simply enumerates sub-expression paths $t_\omega = C_\omega[s_\omega]$ (separating outer wrapper $C_\omega$ from inner occurrence $s_\omega$), anti-unifies $\{s_\omega\}$, and prices the wrapper + template + substitutions using `codec.lisp`.
3. **Milestone 7 (Partitioning & Locality)**:
    - A view/partition selector is a small expression $k(\omega)$ whose level sets partition $\Omega = \bigsqcup_j \Omega_j$.
    - Each part $\Omega_j$ is an ordinary `Frame` solved by a child `job`, reassembled by `gather`.
    - Locality scheduling simply orders the candidate pairs / frames in the `job` scheduler queue while reserving 1-in-4 quanta for canonical enumeration.
4. **Milestone 8 (Recursion, Backtracking, Conflict Explanations, and Learned Preferences)**:
    - **8A (Recursive reconstruction)**: As shown in Example 3, nested decoders $y = a + b \cdot k$ are handled by chaining `pullback-frame` (or normalizing the pulled-back predicate through $\{\text{Law}_+, \text{Law}_\times\}$).
    - **8B (Backtracking & memory)**: All search branches are uniform `job` instances in a DAG keyed by canonical `(frame-hash, language-hash, bound)`.
    - **8C (Returning explanations / conflicts)**: Look at the two required conflicts in `plan4.md` (Section 8C):
        1. `pair(z, z)` cannot reconstruct `pair(2, 3)`: Under pullback + constant folding, the checker predicate becomes `(= (tuple z z) (tuple 2 3))`, which rewrites via tuple injectivity to `(and (= z 2) (= z 3))` $\to$ `nil`! An unsatisfiable row requirement (`nil`) immediately refutes the parent decomposition.
        2. Two rows in the same partition part requiring `(= z 2)` and `(= z 3)` on identical child input: Conjoining single-input requirements for identical known inputs immediately yields `nil`!
    - **8D & 9 (Search preferences & Vocabulary)**: The scheduler selects which `job` in the active DAG to advance for the next work quantum using a shrunk return table $\widehat{G}_k$ or a tiny synthesized descriptor expression evaluated in the same VM.

## 6. Verification & migration checklist before rewriting

To ensure zero regression in scientific rigor when moving from the `plan4` scaffold to the `plan5` kernel:

1. **Bit-exact description sizes ($S$)**: Retain the exact Version 7 prefix code in `codec.lisp` so every arithmetic, tuple, sequence, and quoted expression has the identical bit length as in `results.md`.
2. **Deterministic structural tariff ($W_{\rm run}, W_{\rm search}$)**: Retain `value-work`, `syntax-work`, and arithmetic bit-width charges; eliminate only the artificial overhead of compiling rewrite/propagator rules into interpreted `:code-bind` / `:code-less` ASTs.
3. **Unit-vs-batch continuation parity**: Test every `job` with `quantum = 1` vs. unbatched `work-limit` to guarantee exact resumption parity.
4. **Side-by-side Milestone 1--4 reproduction**: Run `make test m1 m2 m3 m4` on the simplified kernel and compare discovered formulas, certificates, and work ledgers directly against `results.md`.
