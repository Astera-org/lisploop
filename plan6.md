---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,fit,backgrounds,calc}
---

# lisploop --- plan 6

## One homoiconic kernel: conservation, factorization, pullback, and heuristic condensation

30 October 2026 (updated with live kernel nomenclature; see [architecture.md](architecture.md)). Refines and stress-tests [plan 5](plan5.md) against the full scope of [prompt.md](prompt.md), [plan 4](plan4.md), and the empirical findings in [results.md](results.md). The nine research pillars, strict cost accounting ($S$, $W_{\mathrm{run}}$, $W_{\mathrm{search}}$), resumable budgets, and information-isolation contracts remain authoritative. What changes is a streamlined, homoiconic 7-module Common Lisp architecture built around **four fundamental operations**, unifying **exact guards, runtime errors, latent fiber clustering, and approximate heuristics/names** under a single Minimum Description Length (MDL) and computational-work model.

---

## 1. Diagnosis and stress-test of `plan4` and `plan5`

The Milestone 1--4 implementation passes all 85 core tests (187,405 assertions) and reproduces every empirical figure in [results.md](results.md), validating that the research questions in [plan 4](plan4.md) are well-posed. Reviewing the original 16-file `plan4` scaffold (~2,600 LOC) alongside [plan 5](plan5.md) exposed both the accidental complexity of the `plan4` scaffold and five technical subtleties that shaped the live 7-module kernel ([architecture.md](architecture.md)).

### 1.1 What `plan5` diagnosed correctly

1. **Fighting Lisp's homoiconicity with verbose AST wrappers and redundant `:code-bind` traversals**:
   Instead of native S-expressions `(+ X0 (* '2 X1))`, `plan4`'s `syntax.lisp` wrapped every node in property lists repeating the type at every leaf (`(:app (:op :+ (:gf 5)) ((:var 0 (:gf 5)) (:lit (:gf 5) 2)))`). Furthermore, when `symbolic.lisp` and `laws.lisp` lowered rewrite rules and propagator matchers into 25-node interpreted `:code-*` programs:
   - Each of the $k$ `:code-bind` nodes re-ran full tree pattern matching (`match-code`) from scratch just to extract one variable binding.
   - Each `:code-less` node called `encode-model` twice from scratch, allocating two bit-vectors on every attempted match just to compare expression sizes.
   - Replacing tagged-list ASTs with pooled homoiconic symbols carrying $O(1)$ cached structural metadata (`*node-meta*` in `ast.lisp`) and adding single-entry match memoization (`*last-code-match*` in `vm.lisp`) plus cross-job validation caching (`*prepared-rewrite-cache*` in `laws.lisp`) eliminates that redundant host work while preserving exact VM tariff accounting.
2. **Ad-hoc state machines for budget preemption**:
   `evaluation`, `search-job`, `observation-job`, `law-validation`, `rewriting`, and `propagation-search` each need preemptive stepping where `quantum = 1` produces the exact same ledger totals and outcomes as batch execution. Centralizing instruction-cost prepayment in the VM stepper (`evaluation` in `vm.lisp`) guarantees uniform debt draining before execution.
3. **Separate subsystems for coupled mathematical operations**:
   Pullback (`frames.lisp`), equational simplification (`laws.lisp`), and algebraic propagation (`propagation.lisp`) were originally built as isolated engines, even though downward requirement propagation is simply closed-subtree constant folding (`fold-constants`) plus dual-grade solver rewriting (`propagate-arithmetic-child`) on the pulled-back child requirement predicate $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$.

### 1.2 Five stress-test refinements implemented in the kernel

Stress-testing [plan 5](plan5.md) against the full test suite and Milestones 5--9 revealed five places where the architecture needed explicit mathematical and data-structure support:

1. **Ambient numeric domain $D$ in the schema $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$**:
   Top-down expected-type propagation determines operand types for `+`, `-`, `*`, `/`, `if`, `tuple`, `gather` (whose index sequence is always `(:seq :int)`), and `code-child` (whose child index is `:int`). However, type-erasing predicates (`=`, `member`) return `:bool`, which does not specify the operand domain on closed terms. Because $\mathbb{F}_5$, $\mathbb{F}_7$, and $\mathbb{Z}$ never mix in a single unquoted runtime expression ([plan 4](plan4.md)), recording the **ambient numeric domain** $D \in \{\texttt{:int}, \texttt{(:gf } p\texttt{)}\}$ inside `schema` (`make-schema` in `ast.lisp`, inferred automatically from `inputs` and `target`) makes typing unambiguous across all frame rows $\omega \in \Omega$.
2. **Schema-parametric $O(1)$ bit-size caching (avoiding 64-bit `lex-rank` overflow)**:
   `plan5` proposed packing `(body-bits, lex-rank)` into a 64-bit fixnum on each AST node. However, in Encoding Version 7 (`codec.lisp`), each variable reference costs $2 + \lceil \log_2 \max(1, m) \rceil$ bits (which depends on the input arity $m = |\Gamma_{\mathrm{inputs}}|$), and expressions in M3/M4 reach 76--416 bits (overflowing 64 bits). Instead, each AST node caches schema-independent `(non-var-bits, var-count, syntax-work, total-p, free-vars)` in `*node-meta*` (`ast-meta` in `ast.lisp`). For *any* schema $\Gamma$ with $m$ inputs:
   $$\mathrm{body\text{-}size}(e, \Gamma) = \mathrm{non\text{-}var\text{-}bits}(e) + \mathrm{var\text{-}count}(e) \cdot \lceil \log_2 \max(1, m) \rceil$$
   is computed in $O(1)$ integer arithmetic, and `expression-less-p` compares $O(1)$ `description-size` first, only encoding bit-vectors when breaking exact bit-length ties.
3. **Orientation and epistemic grades in downward requirement propagation ($\iff$ vs. $\Leftarrow$)**:
   - *Orientation*: General rewrite rules (`(+ ?0 '0) -> ?0`) are oriented by strictly decreasing description size (`expression-less-p`). Algebraic solver rules for $R_f(K, Z, C)$ isolate the unknown symbolic child variable $Z$ as $Z = q(K, C)$ under guard $G(K, C)$; before constant folding, the witness expression $q(K, C)$ (such as `(+ C (* '4 K))` in $\mathbb{F}_5$) can be *larger* in bit size than $f(K, Z)$, so solver isolation is oriented by **eliminating $Z$ from the RHS** ($Z \notin \mathrm{free\text{-}vars}(q(K, C))$) and evaluating $G(k_\omega, c_\omega)$ and $v_\omega = q(k_\omega, c_\omega)$ on the row's known values.
   - *Epistemic grades*: Over finite fields $\mathbb{F}_p$, exhaustively `:validated` bidirectional laws ($\iff$, both witness and uniqueness certified) license **in-place replacement** of $B_\omega(Z)$ by the singleton requirement `(= Z 'v_w)`. Over `:int` (where laws are sample `:conjecture`s and truncating division `Z / 2 = 1` has a multi-element fiber $\mathrm{Fiber}(\omega) = \{2, 3\}$), a witness law is only a directional implication ($\Leftarrow$). It cannot overwrite $B_\omega(Z)$ in-place; instead, `propagate-arithmetic-child` forward-verifies $B_\omega(v_\omega) = \mathrm{t}$ and populates a narrowed `propagation-frame` scheduled 3:1 against the retained `propagation-fallback` frame.
   - *Unlocking latent values*: Reducing an opaque relational predicate $B_\omega(Z)$ to `(= Z 'v_w)` turns the symbolic child target $Z$ on row $\omega$ into an **explicitly witnessed target value $v_\omega \in \mathcal{V}_{\tau_C}$**, enabling `quotient-values` (M5/M7), `infer-fibers` rank-0 anchoring (M5/M7), and immediate conflict detection ($\texttt{(= Z '2)} \land \texttt{(= Z '3)} \xrightarrow{\text{fold}} \texttt{'nil}$ via `frame-conflict-p` in M8C).
4. **Uniform debt-draining stepper invariants (`evaluation` in `vm.lisp`)**:
   Every primitive instruction prepays its tariff into `evaluation-remaining-cost` *before* executing its payload, ensuring errors are never observed unpaid and `quantum = 1` stepping matches batch execution across all 85 tests.
5. **The 4th fundamental operation — Lossy heuristic condensation (`condense-heuristic`)**:
   Alongside lossless description-length ($S$) factorization, `factor.lisp` implements a first-class operation for **lossy MDL condensation**: pricing row mismatches $\varepsilon(\hat{\pi}, F)$ in bits during learning and discarding $\varepsilon$ at deployment to synthesize intensional partition selectors (M5/M7) and search-control heuristics (M8D/M9).

---

## 2. The four-operation mathematical framework

Across all nine pillars of [prompt.md](prompt.md) and [architecture.md](architecture.md), the synthesizer operates on one recursive data structure—a **Frame** $\Omega$ (`frame`) of **observation rows** $\omega \in \Omega$ (`row`) over a typed **Schema** $\Gamma$ (`schema`)—and performs **four fundamental operations**.

### Nomenclature, Kernel Mapping, and Conceptual Framing

To keep the distinction between **symbolic variables** (uppercase $X_i, Y, Z$) and **bound runtime values** (lowercase $\mathbf{x}_\omega, y_\omega, z_\omega, v_\omega$) completely unambiguous—and to show how the same `frame` mechanism supports recursive and meta-level synthesis when values are themselves quoted syntax trees—the table and framing notes below define every symbol used in Figure 1 and Sections 2.1--2.4.

| Symbol | Meaning in the Mathematical Framework | Live Kernel Representation ([`architecture.md`](architecture.md)) |
| :--- | :--- | :--- |
| $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$ | **Typing schema (context)**: specifies the ambient numeric domain $D$, the $m$ symbolic input variables $X_i$ with their types $\tau_i$, and the target output type $\tau$. | `schema` struct (`make-schema` in `ast.lisp`) with slots `domain`, `inputs`, `target`, `lookup-p`. |
| $D$ | **Ambient numeric domain**: either unbounded integers $\mathbb{Z}$ or a prime field $\mathbb{F}_p = \{0,\dots,p-1\}$. Disambiguates type-erasing operators (`=`, `member`) on closed terms. | `:int` or `(:gf p)` (`schema-domain`). When all inputs are finite (`:bool` or `(:gf p)`), $D^\Gamma = \mathcal{V}_{\tau_0} \times \dots \times \mathcal{V}_{\tau_{m-1}}$ denotes the exhaustive input grid. |
| $\tau,\; \tau_i,\; \mathcal{V}_\tau$ | **Semantic type** $\tau$ and its **value domain** $\mathcal{V}_\tau$. Crucially, $\tau$ may be a **base/container type** ($\mathbb{Z}, \mathbb{F}_p, \mathbb{B}$, tuple, sequence) *or* a **quoted code type** `(:code inputs sort)` whose elements $v \in \mathcal{V}_\tau$ are themselves typed ASTs. | `:int`, `(:gf p)`, `:bool`, `(:tuple ...)`, `(:seq ...)`, or `(:code inputs sort)` (`valid-type-p`, `value-p` in `ast.lisp`). |
| $X = (X_0, \dots, X_{m-1})$ and $Y, Z$ | **Symbolic variables (AST nodes)**: $X_i$ are the formal input variable symbols appearing inside candidate expressions $e(X)$; $Y : \tau_P$ and $Z : \tau_C$ denote the symbolic target variables inside parent and child requirement predicates $A_\omega(Y)$ and $B_\omega(Z)$. | Pooled uninterned variable symbols `#:X0`, `#:X1`, $\dots$ constructed via `(var id type)` in `ast.lisp` (a requirement predicate has a 1-variable schema where $Y$ or $Z$ is `(var 0 target-type)`). |
| $\Omega = (\omega_1, \dots, \omega_n)$ | **Frame (observation table)**: a finite ordered sequence of rows over schema $\Gamma$, optionally carrying action-linkage `pairs` and orbit-separation `anchors`. | `frame` struct (`make-frame` in `frame.lisp`) holding `frame-schema`, `frame-rows`, and optional `frame-pairs`, `frame-anchors`. |
| $\omega \in \Omega$ | **Observation row**: a single row in $\Omega$ pairing a concrete input vector $\mathbf{x}_\omega$ with a target requirement predicate $A_\omega(Y)$. Represents an I/O training example (M1), a state under an action (M2), a domain grid point in $D^\Gamma$ (M3/M4), or a quoted AST in a corpus (M3B/M6). | `row` struct (`make-row` in `frame.lisp`) with inspection label `row-key`, input value list `row-known`, and target predicate `row-requirement`. |
| $\mathbf{x}_\omega = (x_{\omega,0}, \dots, x_{\omega,m-1})$ | **Row input value vector**: the concrete tuple of bound runtime values $x_{\omega,i} \in \mathcal{V}_{\tau_i}$ stored on row $\omega$ (substituting $X_i \gets x_{\omega,i}$ during evaluation). | `row-known` list on `row` $\omega$. When $\tau_i$ is `:int` or `(:gf p)`, $x_{\omega,i}$ is a number; when $\tau_i$ is `(:code ...)`, $x_{\omega,i}$ is a quoted syntax tree. |
| $T\omega$ | **Action-linked row** (e.g., trajectory successor): a row linked to $\omega$ by an empirical action, symmetry transformation, or co-locality relation $(\omega, T\omega)$. Conserved quantities satisfy $M(e, \omega) = M(e, T\omega)$ across `pairs` while varying across orbit `anchors`. | Linked row-index pair $(\omega, T\omega)$ in `observation-scope-pairs` (inherited automatically from optional `frame-pairs`, or produced from transition records by `transition-probes`). |
| $\mathcal{L}(\Gamma)$ and $\mathcal{E} \subseteq \mathcal{L}(\Gamma)$ | **Typed expression language** $\mathcal{L}(\Gamma)$ of well-typed S-expressions $e(X)$ over $\Gamma$, and the **candidate stream** $\mathcal{E} \subseteq \mathcal{L}(\Gamma)$ evaluated during a search or observation run. | `language` struct (`make-language`) defines $\mathcal{L}(\Gamma)$; `enumerator` (`enumeration-step` in `enumerate.lisp`) or a replay list yields $e \in \mathcal{E}$ in non-decreasing bit length. |
| $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega)$ | **Outcome Matrix cell**: result of evaluating symbolic expression $e(X) \in \mathcal{E}$ on row $\omega$'s bound input values $\mathbf{x}_\omega$, taking values in $\mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$. | Computed by the metered VM stepper `evaluation` (`vm.lisp`) inside `search-job` or `observation-job` (`observation-outcome`). |
| $A_\omega(Y)$ and $B_\omega(Z)$ | **Parent vs. child row requirement predicates**: Boolean S-expressions over symbolic target variable $Y : \tau_P$ (parent) or $Z : \tau_C$ (child) that evaluate to $\mathrm{t}$ on value $v \in \mathcal{V}_\tau$ iff $v$ is admissible on row $\omega$ ($B_\omega = A_\omega$ when undecomposed). | `row-requirement` on `row` (`singleton-requirement` `(= X0 'v)`, `set-requirement` `(member X0 '(v1 v2))`, or any Boolean AST over `#:X0`). |
| $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ | **Target-value fiber of row $\omega$ (admissible set in $\mathcal{V}_{\tau_C}$)**: the set of concrete child/residual values $z \in \mathcal{V}_{\tau_C}$ satisfying row $\omega$'s symbolic requirement predicate $B_\omega(Z)$. May be a singleton $\{v_\omega\}$, a finite set, all of $\mathcal{V}_{\tau_C}$ (`'t`), or empty (`'nil`, a conflict). | Inspected via `extract-allowed-values` and intersected via `conjoin-requirements` (`frame.lisp`). |
| $t_\omega,\; p,\; \theta_\omega$ | **Factorization & residual value (Operation 2)**: $t_\omega \in \mathcal{V}_\tau$ is a concrete witnessed object on row $\omega$ (a quoted AST or base value $y_\omega$); $p$ is a shared template/table; $\theta_\omega \in \mathrm{Fiber}(\omega)$ is the **concrete per-row residual value** selected from row $\omega$'s fiber such that $\mathrm{Apply}(p, \theta_\omega) = t_\omega$ (when $\mathrm{Apply}$ is injective on $t_\omega$, $\mathrm{Fiber}(\omega) = \{\theta_\omega\}$ is a singleton). | `anti-unify` & `compile-au-constructor` (where $t_\omega$ is a `:code` AST and $\theta_\omega$ is the tuple of hole bindings), `quotient-values` (where $\theta_\omega = j_\omega$). |
| $\Omega_k \subseteq \Omega$ and $j_\omega \in \{0,\dots,K-1\}$ | **Row-space value fiber (level set in $\Omega$) & cluster index**: for a map from rows to values/classes, $\Omega_k = \{\omega \in \Omega \mid j_\omega = k\}$ is the subset of rows sharing representative value $R_k$ or compatible intersected fiber $\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset$, and $j_\omega$ is the discrete index recording which class $\Omega_k$ row $\omega$ belongs to. | `quotient-values` & `partition-rows` (`frame.lisp`), `infer-fibers` returning `fiber-class` structs with `fiber-class-rows` ($\Omega_k$) and `fiber-class-requirement` ($B_{c_k}(Z) = \bigwedge_{\omega \in \Omega_k} B_\omega(Z)$). |
| $d(X, Z),\; R_f,\; q,\; G,\; v_\omega$ | **Pullback & solver components (Operation 3)**: $Y = d(X, Z)$ is a candidate decoder AST over parent inputs $X$ and child variable $Z$; $R_f(K, Z, C)$ is the relational view of primitive $f(K, Z) = C$; $q(K, C)$ and $G(K, C)$ are a learned solver witness and guard; $v_\omega = \mathrm{fold}(q(k_\omega, c_\omega)) \in \mathrm{Fiber}(\omega)$ is the folded witness value on row $\omega$. | `pullback-frame`, `fold-constants`, `discover-arithmetic-solver`, `validate-arithmetic-solver`, `propagate-arithmetic-child`. |
| $\hat{\pi}(X)$ and $\varepsilon_\omega$ | **Heuristic predictor & residual (Operation 4)**: $\hat{\pi}(X)$ is a compact symbolic program predicting target values or fiber classes $j_\omega$ from row inputs $\mathbf{x}_\omega$; $\varepsilon_\omega$ is the training error residual on row $\omega$, priced in bits during learning and **dropped at deployment**. | `condense-heuristic` returning a `heuristic-model` (`heuristic-program`, `heuristic-residual`, `heuristic-score` in `factor.lisp`). |
| $S(\cdot),\; W_{\mathrm{syn}},\; W_{\mathrm{run}},\; W_{\mathrm{search}}$ | **Exact accounting metrics**: $S(\cdot)$ is prefix-free description length in bits (Encoding v7); $W_{\mathrm{syn}}, W_{\mathrm{run}}, W_{\mathrm{search}}$ are AST construction, runtime evaluation, and cumulative search work in tariff units (Tariff v8). | `description-size` (`header-size` + `body-size` in `codec.lisp`), `syntax-work`, `evaluation-work`, `ledger-total` (`vm.lisp`). |

> **Key Conceptual Distinctions (Avoiding Jargon Traps)**
>
> 1. **Symbolic Variables ($X, Y, Z$) vs. Row Values ($\mathbf{x}_\omega, y_\omega, z_\omega$), and How One `frame` Mechanism Supports Recursive & Meta-Level Synthesis**:
>    - In any single frame $\Omega$ over schema $\Gamma$, uppercase $X = (X_0, \dots, X_{m-1})$ and $Y, Z$ are **symbolic variable AST nodes** (`#:X0, #:X1, ...`) inside expressions $e(X)$ and requirement predicates $A_\omega(Y), B_\omega(Z)$, whereas lowercase $\mathbf{x}_\omega = (x_{\omega,0}, \dots, x_{\omega,m-1})$ (`row-known`) and $y_\omega, z_\omega, v_\omega$ are **concrete values** in $\mathcal{V}_{\tau_i}$ and $\mathcal{V}_\tau$ bound when evaluating on row $\omega$.
>    - **Recursive decomposition across parent/child frames (M1, M4, M5, M7, M8A)**: When a parent frame with target requirement $A_\omega(Y)$ is decomposed through a candidate decoder $Y = d(X, Z)$, substituting the row's known values $X \gets \mathbf{x}_\omega$ while keeping $Z$ symbolic turns $A_\omega(d(\mathbf{x}_\omega, Z))$ into a new symbolic predicate $B_\omega(Z)$ (`row-requirement`) on the child frame! `fold-constants` evaluates closed ($Z$-free) subtrees to literal values while leaving $Z$-dependent subtrees symbolic, so recursive synthesis simply constructs child `frame`s using the exact same representation.
>    - **Self-hosted / meta-level synthesis via `:code` values (M3B, M3C, M6, M8, M9)**: Because the type system includes quoted syntax types $\tau = \texttt{(:code } \Gamma'\ \sigma\texttt{)}$, an S-expression $e' \in \mathcal{L}(\Gamma')$ (containing its own inner symbolic variables $X'_0, X'_1, \dots$) is **also a first-class runtime value** $v \in \mathcal{V}_\tau$ (`(lit code-type expr)`). Thus the *exact same* `frame`, `search-job`, `observation-job`, `anti-unify`, and `condense-heuristic` machinery synthesizes object-level numeric functions when $\mathcal{V}_\tau = \mathbb{Z}$ or $\mathbb{F}_p$, and synthesizes/verifies symbolic rewrite transformers, anti-unification constructors, and propagator matchers when $\mathcal{V}_\tau = \mathcal{V}_{\texttt{(:code ...)}}$.
> 2. **Why "Right-Inverse of `Apply`" (Operation 2: Factorization) is different from "Pullback" (Operation 3: Predicate Precomposition)**:
>    - **Factorization (Operation 2) works on *concrete witnessed values* $\{t_\omega\}$**: We already have a concrete value $t_\omega \in \mathcal{V}_\tau$ at every row $\omega$ (e.g., a list of quoted law ASTs `(law_1 ... law_n)` in $\mathcal{V}_{\texttt{(:code ...)}}$ or a list of concrete output values `(y_1 ... y_n)` in $\mathbb{Z}$ or $\mathbb{F}_p$). Forward execution `Apply` combines a shared template $p$ and a row-specific argument $\theta_\omega$ to produce $t_\omega = \mathrm{Apply}(p, \theta_\omega)$. **Factorization** computes a *right-inverse* of `Apply`: it simultaneously splits the collection $\{t_\omega\}_{\omega \in \Omega}$ into a single shared pattern $p$ and per-row residuals $\{\theta_\omega\}_{\omega \in \Omega}$ such that $\mathrm{Apply}(p, \theta_\omega) = t_\omega$ holds identically.
>    - **Pullback (Operation 3) works contravariantly on *symbolic requirement predicates* $A_\omega(Y)$**: When decomposing a synthesis problem through a candidate decoder $Y = d(X, Z)$, we do *not* yet know the child values $z_\omega$, and the map $z \mapsto d(\mathbf{x}_\omega, z)$ is in general **not invertible** (for example, integer truncating division $d(\mathbf{x}_\omega, z) = z / 2$ is many-to-one, and $d(\mathbf{x}_\omega, z) = (z, z)$ is not surjective). We do not need $d^{-1}$ to form the child problem! Instead, because $A_\omega(Y) : \mathcal{V}_{\tau_P} \to \mathbb{B}$ is a Boolean predicate on $Y$, we **pull $A_\omega$ back along $d(\mathbf{x}_\omega, \cdot)$ by symbolic substitution (function precomposition)**:
>      $$B_\omega(Z) \;:=\; (A_\omega \circ d_{\mathbf{x}_\omega})(Z) \;=\; A_\omega\bigl(d(\mathbf{x}_\omega, Z)\bigr).$$
>      Only *after* forming the pulled-back predicate $B_\omega(Z)$ does the kernel simplify it via closed-subtree constant folding (`fold-constants`) and, when applicable, learned algebraic solvers (`propagate-arithmetic-child`).
> 3. **Two Dual Uses of "Fiber" (Target-Value Set $\mathrm{Fiber}(\omega) \subseteq \mathcal{V}_{\tau_C}$ vs. Row Level-Set $\Omega_k \subseteq \Omega$), and "Extensional" vs. "Intensional" Lifting**:
>    - **In value space ($\subseteq \mathcal{V}_{\tau_C}$)**: For a single row $\omega$, $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$ is the **set of admissible target values** satisfying predicate $B_\omega(Z)$, whereas $\theta_\omega$ (or $z_\omega, v_\omega$) is a **single concrete value chosen from $\mathrm{Fiber}(\omega)$**. When `Apply` or a certified solver is injective, $\mathrm{Fiber}(\omega) = \{\theta_\omega\}$ is a singleton (`(= Z 'v_w)`); when a decoder is many-to-one (e.g., `(= (/ Z '2) '1)`), $\mathrm{Fiber}(\omega) = \{2, 3\}$ has multiple candidate values and $\theta_\omega \in \{2, 3\}$ is the coordinate selected once disambiguated.
>    - **In row space ($\subseteq \Omega$)**: Viewing a column or expression as a map $\Omega \to \mathcal{V}_\tau$, the preimage of a value $R_k \in \mathcal{V}_\tau$ is the **level set of rows** $\Omega_k = \{\omega \in \Omega \mid y_\omega = R_k\}$. In `quotient-values`, $\Omega$ is partitioned into these exact value level-sets $\Omega_0, \dots, \Omega_{K-1}$ and each row's residual is its class index $\theta_\omega = j_\omega \in \{0, \dots, K-1\}$ such that $y_\omega = \mathrm{gather}(R, j_\omega)$. When rows only have predicates $B_\omega(Z)$ rather than single values, `infer-fibers` generalizes `quotient-values` by coupling both spaces: each `fiber-class` $c_k$ groups a cluster of rows $\Omega_k \subseteq \Omega$ (`fiber-class-rows`, indexed by $j_\omega = k$) whose target-value fibers have a non-empty intersection $\bigcap_{\omega \in \Omega_k} \mathrm{Fiber}(\omega) \neq \emptyset$, represented by the conjoined predicate $B_{c_k}(Z) = \bigwedge_{\omega \in \Omega_k} B_\omega(Z)$ (`fiber-class-requirement`).
>    - **Extensional labels ($j_\omega$) vs. Intensional selector ($\hat{\pi}(X)$)**: The cluster assignment $j_\omega \in \{0, \dots, K-1\}$ from `quotient-values` or `infer-fibers` is *extensional*—a finite lookup vector indexed by the training rows $\omega \in \Omega$ that cannot be evaluated on new inputs. Operation 4 (`condense-heuristic`) takes $j_\omega$ as target values and synthesizes a symbolic S-expression $\hat{\pi}(X)$ predicting $\hat{\pi}(\mathbf{x}_\omega) \approx j_\omega$. This program $\hat{\pi}(X)$ is *intensional*: it computes the class index from input values $\mathbf{x}_\omega$, generalizes to held-out rows, and drops noisy Stage-1 cluster assignments $\varepsilon_\omega$ at deployment.

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
        Schema $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$, \quad Frame Rows $\omega \in \Omega$ with values $\mathbf{x}_\omega$, \quad Candidates $e(X) \in \mathcal{E} \subseteq \mathcal{L}(\Gamma)$\\
        Outcome Matrix $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$, \quad $O(1)$ Cached Metadata $(\mathrm{bits}, W_{\mathrm{syn}}, \mathrm{total?}, \mathrm{vars})$
    };

    % Four Pillars below
    \node[box, text width=3.75cm, anchor=north] (cons) at (-6.15, -1.7) {
        \textbf{1. Observational Conservation}\\
        Level sets of $M(e, \omega)$ across $\omega \in \Omega$:\\[2pt]
        $\bullet$ \textbf{Synthesis (M1)}: $A_\omega(M(e, \omega)) = \mathrm{t}$\\
        $\bullet$ \textbf{Invariants (M2)}: $M(e, \omega) = M(e, T\omega)$\\
        $\bullet$ \textbf{Laws (M3)}: $e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega)$ on $D^\Gamma$\\
        $\bullet$ \textbf{Exact Guards (M3/4)}: compress\\
        \phantom{$\bullet$ }support mask $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$ to $\varepsilon_\omega \equiv 0$
    };

    \node[box, text width=3.75cm, anchor=north] (fact) at (-2.05, -1.7) {
        \textbf{2. Factorization \& Fiber EM}\\
        Right-inverse of $\mathrm{Apply}$ on $\{t_\omega\}$:\\
        $t_\omega = \mathrm{Apply}(p, \theta_\omega)$, keep $\theta_\omega$\\[2pt]
        $\bullet$ \textbf{Term AU (M3/6)}: $\mathrm{Subst}(p, \theta_\omega)$\\
        $\bullet$ \textbf{Seq quotient (M5/7)}: $\mathrm{gather}(R, j_\omega)$\\
        $\bullet$ \textbf{Hard-EM fibers (M5/7)}: cluster\\
        \phantom{$\bullet$ }compatible $B_\omega(Z)$ into classes $j_\omega$
    };

    \node[box, text width=3.75cm, anchor=north] (pull) at (2.05, -1.7) {
        \textbf{3. Pullback \& Propagation}\\
        Precompose $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$:\\[2pt]
        $\bullet$ \textbf{Fold closed subtrees} ($Z$-free)\\
        $\bullet$ \textbf{Certified $\iff$ (M4/8A)}: isolate\\
        \phantom{$\bullet$ }$Z$, replace $B_\omega(Z)$ with $(= Z\ \text{'}v_\omega)$\\
        $\bullet$ \textbf{Tentative $\Leftarrow$ (M4 $\mathbb{Z}$)}: verify\\
        \phantom{$\bullet$ }$B_\omega(v_\omega)$, spawn preferred lane
    };

    \node[box, text width=3.75cm, anchor=north] (heur) at (6.15, -1.7) {
        \textbf{4. Heuristic Condensation}\\
        Compress $W_{\mathrm{search}}, W_{\mathrm{run}}$:\\[2pt]
        $\bullet$ \textbf{Learn $\hat{\pi}(X)$} via MDL with priced\\
        \phantom{$\bullet$ }error residual $S(\hat{\pi}) + S(\varepsilon) + \lambda_{\mathrm{run}} W_{\mathrm{run}}$\\
        $\bullet$ \textbf{Deploy}: drop $\varepsilon_\omega$ for intensional\\
        \phantom{$\bullet$ }selectors (M5/7) \& Agenda (M8/9)\\
        $\bullet$ \textbf{Verify} on $B_\omega(Z)$ + $1/4$ reserve
    };

    % Arrows from kernel
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (cons.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (fact.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (pull.north);
    \draw[->, thick] (kernel.south) -- ++(0,-0.3) -| (heur.north);

    % Cross-links at bottom
    \draw[->, thick] (fact.south) -- ++(0,-0.45) -| node[pos=0.25, below, lbl] {Residuals $\theta_\omega, j_\omega$ form child frames} (cons.south);
    \draw[->, thick] (pull.south) -- ++(0,-0.9) -| node[pos=0.25, below, lbl] {Explicit targets $(= Z\ \text{'}v_\omega)$ \& trace costs feed MDL heuristic/selector synthesis} (heur.south);
\end{tikzpicture}
\caption{All nine milestones factor through four operations over one homoiconic S-expression kernel.}
\end{figure}
```

### 2.1 Operation 1: Observational conservation across frame rows

Let $\Omega = (\omega_1, \dots, \omega_n)$ be the rows of a `frame` over schema $\Gamma$ and let $\mathcal{E} \subseteq \mathcal{L}(\Gamma)$ be a stream of symbolic S-expressions $e(X)$ generated by `enumerator` (or supplied for replay). Evaluating each $e(X) \in \mathcal{E}$ on each row's input value vector $\mathbf{x}_\omega$ produces the **Outcome Matrix** $M(e, \omega) = \mathrm{Eval}(e, \mathbf{x}_\omega) \in \mathcal{V}_\tau \cup \{\bot_{\mathrm{err}}, \bot_{\mathrm{cutoff}}\}$. Every discovery task in Milestones 1--4 is a conservation query on $M$:

- **M1 (Function synthesis via unary row requirements, `search-job`)**: Each row $\omega \in \Omega$ carries a *unary* predicate $A_\omega(Y)$ (`row-requirement`) that judges a single output value $y_\omega = M(e, \omega)$ in isolation. `search-job` finds $e(X) \in \mathcal{E}$ such that $\forall \omega \in \Omega,\ A_\omega(M(e, \omega)) = \mathrm{t}$ (early-exiting the row loop on the first $\bot_{\mathrm{err}}$ or `nil`). For instance, learning an action $T$ itself in Milestone 2 sets $A_\omega(Y) := (Y = \mathbf{x}_{T\omega})$.
- **M2 (Behavioral equivalence & symmetries under an action, `observation-job`)**: By contrast, testing whether a candidate observable $e(X)$ is **conserved under an action $T$** ($M(e, \omega) = M(e, T\omega)$) is a *relational* property across linked rows $(\omega, T\omega) \in \texttt{pairs}$—the target value $y_\omega$ is not fixed in advance; we only require that $e$ take the *same* value before and after the action while taking at least two distinct values across orbit `anchors`. `observation-job` partitions $\mathcal{E}$ into `observation-bucket`s by complete non-error output value vectors $[M(e, \omega_1), \dots, M(e, \omega_n)]$ and `observation-invariants` selects buckets conserved across `observation-scope-pairs` (inherited automatically from optional `frame-pairs` or produced by `transition-probes`).
- **M3 (Finite-domain laws, `start-law-validation`)**: On the exhaustive finite input grid $\Omega = D^\Gamma$, verify $\forall \omega \in \Omega,\ \bigl(G(\mathbf{x}_\omega) \Rightarrow e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega)\bigr) = \mathrm{t}$ with positive active support ($\exists \omega,\ G(\mathbf{x}_\omega) = \mathrm{t}$).
- **M3/M4 (Support masks & exact guards, `observed-support` & `propose-guarded-laws`)**: Any partially valid expression or equation pair $(e_1, e_2)$ partitions $\Omega$ into its **positive support rows** $\Omega_{\mathrm{ok}} = \{\omega \in \Omega \mid e_1(\mathbf{x}_\omega) = e_2(\mathbf{x}_\omega) \in \mathcal{V}_\tau\}$ and **failure/error rows** $\Omega_{\mathrm{fail}} = \Omega \setminus \Omega_{\mathrm{ok}}$. Synthesizing an exact guard $G(X)$ on `support-frame` is simply synthesizing a Boolean predictor conserved on the indicator $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$ with zero residual error ($\varepsilon_\omega \equiv 0$).

### 2.2 Operation 2: Factorization and latent fiber inference ($S$ compression)

Whereas forward evaluation applies a shared operator or template $p$ to a row-specific argument $\theta_\omega$ to produce a concrete value $t_\omega = \mathrm{Apply}(p, \theta_\omega) \in \mathcal{V}_\tau$, lossless factorization computes a **right-inverse of `Apply`**: given a collection of concrete values $\{t_\omega\}_{\omega \in \Omega}$ (either base values or quoted `:code` ASTs), it factors them into a shared template $p$ and per-row residuals $\{\theta_\omega\}_{\omega \in \Omega}$ minimizing $S(p) + S(\{\theta_\omega\}) + \lambda_{\mathrm{run}} W_{\mathrm{run}}$:

1. **Term Algebra (M3B Law Corpus & M6 Anti-Unification, `anti-unify`)**: Each $t_\omega \in \mathcal{V}_{\texttt{(:code ...)}}$ is a quoted S-expression; $\mathrm{Apply}$ is syntactic hole substitution $\mathrm{Subst}(p, \theta_\omega)$ (`instantiate` / `:code-subst`). `anti-unify` computes the least general generalization (LGG) pattern $p$ (with typed holes `?0, ?1, ...`) and the per-row residual subtree tuples $\theta_\omega$.
2. **Sequence Algebra (M1/M5/M7 Quotients & Partitions, `quotient-values` & `partition-rows`)**: Each $t_\omega = y_\omega \in \mathcal{V}_\tau$ is a concrete value; $\mathrm{Apply}$ is indexed sequence lookup `(gather R j_w)`. `quotient-values` factors $\{y_\omega\}_{\omega \in \Omega}$ into a deduplicated sequence of unique representatives $R$ and integer index residuals $\theta_\omega = j_\omega \in \{0, \dots, |R|-1\}$.
3. **Latent Fiber & Partition Inference via Hard EM (`infer-fibers`, M5/M7)**:
   When every row's target requirement is already a concrete singleton `(= Z 'v_w)`, `quotient-values` groups identical values $v_\omega$ directly. However, when row requirements $B_\omega(Z)$ are **multi-valued or relational** (e.g., `(member Z '(2 3))`, `(= (/ Z '2) '1)`, or unconstrained `'t`), we do not have a single value $t_\omega$ on every row—instead, each row $\omega$ specifies an admissible **fiber** $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$. Crucially, once a parent requirement $A_\omega(Y)$ is pulled back through $Y = d(X, Z)$ to per-row child predicates $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$, cross-row compatibility is *already internalized* into the unary predicates $B_\omega(Z)$: two rows $\omega_i, \omega_j$ can share a latent coordinate $z$ iff $\mathrm{Fiber}(\omega_i) \cap \mathrm{Fiber}(\omega_j) \neq \emptyset$. To cluster $\Omega$ into $K$ latent classes $j_\omega \in \{0, \dots, K-1\}$ without an external witness oracle or explicit `frame-pairs`, `infer-fibers` performs **confidence-ordered Hard EM over row requirements**:
   - **Tightness ranking**: Rows are ordered by `fiber-tightness-rank` from most constrained to least constrained: rank 0 (singletons `(= Z 'c)`), rank 1 (finite sets `(member Z '(c1 ...))` by ascending cardinality), and rank 2 (general Boolean predicates).
   - **Cannot-link soundness filter**: Two symbolic requirements $B_A(Z), B_B(Z)$ cannot share a `fiber-class` if their conjunction `(conjoin-requirements B_A B_B target-type)` constant-folds to `'nil` ($\mathrm{Fiber}(A) \cap \mathrm{Fiber}(B) = \emptyset$).
   - **E-step (free coverage)**: If conjoining row $\omega$'s requirement $B_\omega(Z)$ with an existing class requirement $B_c(Z)$ leaves $B_c(Z)$ unchanged (`equal`), then $\mathrm{Fiber}(c) \subseteq \mathrm{Fiber}(\omega)$ is already satisfied for free ($\Delta S = 0$), and $\omega$ joins class $c$ immediately (committed tight fibers disambiguate wider-fiber rows).
   - **M-step (coverage-vote amortized merging / nucleation)**: Otherwise, each compatible class $c$ is scored by its marginal description-bit increase $\Delta S = \max\bigl(0,\, S(B_c \land B_\omega) - S(B_c)\bigr)$ divided by its compatibility **coverage votes** ($1 +$ the number of remaining unassigned rows compatible with $B_c \land B_\omega$). Row $\omega$ merges into the lowest-cost compatible class, or nucleates a new `fiber-class` if all existing classes are incompatible. Once `infer-fibers` assigns each row $\omega \in \Omega_k$ its narrowed requirement $B_{c_k}(Z)$, synthesizing a child coordinator $c(X)$ via `search-job` automatically enforces invariance across all rows within each fiber $\Omega_k$.

### 2.3 Operation 3: Causal reorientation, pullback, and dual-grade propagation

Recording forward evaluations $c = f(a, b)$ turns a directed primitive $f$ into a relational table governed by the definedness-and-equality predicate $R_f(a, b, c) \iff \mathrm{defined}_f(a, b) \land (f(a, b) = c)$. **Reorientation** (`orient-observations`, `orient-arithmetic-requirements`) selects which columns form the known row input values $\mathbf{x}_\omega$ and which column is the target $Y$ to explain.

When a parent frame with symbolic row requirements $A_\omega(Y)$ is decomposed through a candidate decoder expression $Y = d(X, Z)$ over symbolic parent inputs $X$ and a symbolic child variable $Z : \tau_C$, **pullback (`pullback-frame`)** substitutes the row's known input values $X \gets \mathbf{x}_\omega$ into $d(X, Z)$ and precomposes $A_\omega(Y)$ with $d(\mathbf{x}_\omega, Z)$, forming the symbolic child requirement S-expression:
$$B_\omega(Z) \;:=\; A_\omega\bigl(d(\mathbf{x}_\omega, Z)\bigr).$$
Because pullback is symbolic AST substitution followed by partial evaluation, it works for *any* decoder $d(X, Z)$—even when $z \mapsto d(\mathbf{x}_\omega, z)$ is many-to-one or non-surjective. Simplifying the pulled-back predicate $B_\omega(Z)$ then proceeds in two stages:

1. **Closed-subtree constant folding and conflict detection (`fold-constants` & `frame-conflict-p`)**:
   During `pullback-frame`, `fold-constants` simplifies $B_\omega(Z)$ bottom-up in the metered VM:
   - Any **closed subtree** with no free symbolic variable $Z$ (`(null (free-vars subtree))`, such as `(* 'a_w 'a_w)` in `(= (+ (* 'a_w 'a_w) Z) 'y_w)` when $a_\omega = 2^{128} + i$ is bound on row $\omega$) is evaluated **once** during pullback and replaced by its literal value `'K_w` (or propagates `:error` to fold an enclosing equality to `'nil`).
   - Tuple equalities `(= (tuple e_1 e_2) '(v_1 v_2))` decompose by injectivity into conjunctions, and finite-set `:member` requirements are intersected across conjunctions.
   - If any row's $B_\omega(Z)$ folds to `'nil` (`:unsatisfiable-row`), or if two rows with identical child input values $\mathbf{x}_\omega$ conjoin to `'nil` (`:incompatible-rows`), `frame-conflict-p` immediately refutes the decomposition.
2. **Variable isolation via learned arithmetic solvers ($\iff$ vs. $\Leftarrow$, `propagate-arithmetic-child`)**:
   In Milestone 4, `discover-arithmetic-solver` learns a symbolic inverse witness $q(K, C)$ and admissibility guard $G(K, C)$ for $R_f(K, Z, C)$, and `validate-arithmetic-solver` checks both directions:
   - **Certified Equivalence ($\iff$, exhaustive finite fields)**:
     When both the witness law $G(K, C) \Rightarrow R_f(K, q(K, C), C)$ ($\Leftarrow$) and the uniqueness law $\bigl(G(K, C) \land R_f(K, U, C)\bigr) \Rightarrow U = q(K, C)$ ($\implies$) are `:validated` over the entire finite domain, $R_f(k_\omega, Z, c_\omega)$ is logically equivalent to $Z = q(k_\omega, c_\omega)$ whenever $G(k_\omega, c_\omega) = \mathrm{t}$. `propagate-arithmetic-child` evaluates $G(k_\omega, c_\omega)$ and $v_\omega = q(k_\omega, c_\omega)$ and replaces $B_\omega(Z)$ **in-place** with the singleton requirement `(= Z 'v_w)`, shrinking the child verification frame directly.
   - **Tentative Witness ($\Leftarrow$, integers or multi-valued fibers)**:
     Over `:int` (where laws are sample `:conjecture`s and truncating division `Z / 2 = 1` has a multi-valued fiber $\{2, 3\}$), a witness rule $G(K, C) \Rightarrow R_f(K, q(K, C), C)$ is only a directional implication ($\Leftarrow$) and cannot soundly overwrite $B_\omega(Z)$ in-place. Instead, `propagate-arithmetic-child` computes $v_\omega = q(k_\omega, c_\omega)$, **forward-verifies** $B_\omega(v_\omega) = \mathrm{t}$ using the original pulled-back requirement, and populates a narrowed `propagation-frame` (`(= Z 'v_w)`) while retaining the original pullback frame as `propagation-fallback`.

### 2.4 Operation 4: Heuristic condensation and multi-lane agenda control ($W$ compression)

How do runtime errors ($\bot_{\mathrm{err}}$), exact guards ($G(X)$), and approximate heuristics, intensional partition selectors (M5/M7), search policies (M8D), or compositional function names (M9) fit into a single cost and execution model?

Consider any symbolic predictor $\hat{\pi}(X)$ evaluated across the row input values $\mathbf{x}_\omega$ ($\omega \in \Omega$) of a frame $F$:

1. **Pricing errors in computation ($W_{\mathrm{run}}$)**:
   Every VM primitive in `vm.lisp` prepays its full structural and bit-width tariff (`evaluation-remaining-cost`) *before* executing, even when it errors (e.g., `1/0` pays the division tariff before returning $\bot_{\mathrm{err}}$). In contrast, a lazy conditional `(if G(X) (/ X0 X0) '0)` evaluates only `G(X)` when $G(\mathbf{x}_\omega) = \mathrm{nil}$, avoiding both the error and the runtime cost of `(/ X0 X0)`.
2. **Exact guards as zero-residual compression of the support mask ($S$ vs. $W$)**:
   Let $\mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega) \in \{\mathrm{t}, \mathrm{nil}\}$ be the indicator of rows where a partial law or solver succeeds. Storing the indicator extensionally as a literal exception mask costs $\sim |\Omega|$ bits; synthesizing an **exact guard** $G(X)$ such that $G(\mathbf{x}_\omega) = \mathbf{1}_{\Omega_{\mathrm{ok}}}(\omega)$ on every row replaces the literal mask with a compact Boolean expression of description size $S(G)$ and execution cost $W_{\mathrm{run}}(G)$ whose residual error is identically zero ($\varepsilon_\omega \equiv 0$).
3. **Intensional selectors, heuristics, policies, and names as lossy MDL condensations (`condense-heuristic`, discarding $\varepsilon_\omega$ at deployment)**:
   When condensing a frame $F$ with ambiguous or noisy row requirements $B_\omega(Z)$—for example, learning an intensional partition selector $\hat{\pi}(\mathbf{x}_\omega) \approx j_\omega$ after `infer-fibers` (M5/M7), a search-return predictor (M8D), or a symbolic library descriptor (M9)—`condense-heuristic` uses the **exact same synthesizer and two-part MDL objective**:
   $$\min_{\hat{\pi} \in \mathcal{E}} \Bigl[\, S(\hat{\pi}) \;+\; S\bigl(\varepsilon(\hat{\pi}, F)\bigr) \;+\; \lambda_{\mathrm{run}}\, W_{\mathrm{run}}(\hat{\pi}) \,\Bigr].$$
   - **During discovery**, `condense-heuristic` first refines $F$ via `infer-fibers` and then prices every row $\omega_i$ where $\hat{\pi}(\mathbf{x}_{\omega_i})$ fails to satisfy the refined requirement $B_{\omega_i}(Z)$ (or errors) by charging the exact bit length of encoding the missed row index $i$ and a satisfying witness value $w_i \in \mathrm{Fiber}(\omega_i)$:
     $$\Delta S_{\mathrm{miss}}(i) = \mathrm{positive\text{-}bit\text{-}size}(i + 1) + \mathrm{value\text{-}bit\text{-}size}(w_i, \tau).$$
     Pricing $S(\varepsilon(\hat{\pi}, F)) = \sum_{i \in \mathrm{missed}} \Delta S_{\mathrm{miss}}(i)$ alongside $S(\hat{\pi}) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(\hat{\pi})$ prevents both trivial underfitting (high residual cost $S(\varepsilon)$) and brittle lookup-table memorization (high program cost $S(\hat{\pi})$).
   - **At deployment**, the kernel **discards the residual table $\varepsilon(\hat{\pi}, F)$** and deploys the bare symbolic S-expression $\hat{\pi}(X)$ (`heuristic-program`):
     - For **intensional lifting/partitioning (M5/M7)**, replacing the extensional cluster value vector $(j_{\omega_1}, \dots, j_{\omega_n})$ by the intensional expression $\hat{\pi}(X)$ generalizes to unseen input values $\mathbf{x}$ and drops noisy Stage-1 cluster assignments.
     - For **multi-lane search control (`propagation-search`, M4/M7/M8D/M9)**, the narrowed frame or heuristic priority is scheduled in the `:primary` lane while a fixed **1-in-4 canonical reserve** (`(= 3 (mod turn 4))`) advances the unguided `:fallback` lane.
   - **Why discarding $\varepsilon_\omega$ is always sound and self-pricing**: Every candidate program discovered by a heuristic or tentative lane is replayed against the authoritative original frame requirement (`:verification` on `propagation-original`) before acceptance. If an approximate selector or tentative integer witness misfires, it cannot corrupt soundness—it simply pays the verification work in $W_{\mathrm{search}}$ while the 1-in-4 canonical reserve guarantees completeness.

| Control knowledge type | Residual $\varepsilon_\omega$ on $\Omega$ | Certified on domain? | Permitted effect in live kernel ([`architecture.md`](architecture.md)) |
|---|---|---|---|
| **Checked conflict (`frame-conflict-p`, M8C)** | $\mathrm{Fiber}(\omega) = \emptyset$ ($B_\omega(Z) \xrightarrow{\text{fold}} \texttt{'nil}$) | Yes (exact fold to `'nil`) | Refute branch / merge immediately (`:unsatisfiable-row` or `:incompatible-rows`) |
| **Certified equivalence ($\iff$, M3/M4 GF($p$))** | $\varepsilon_\omega \equiv 0$ under guard $G(X)$ | Yes (`:validated` on $D^\Gamma$) | Rewrite expression (`start-rewriting`) or replace child requirement $B_\omega(Z)$ **in-place** (`propagate-arithmetic-child`) |
| **Tentative witness ($\Leftarrow$, M4 $\mathbb{Z}$)** | $\varepsilon_\omega = 0$ on forward-verified rows | No (`:conjecture` / multi-valued fiber) | Forward-check $B_\omega(v_\omega) = \mathrm{t}$; schedule `propagation-frame` 3:1 against `propagation-fallback` (`propagation-search`) |
| **Hard-EM fiber / selector lift (M5, M7)** | Stage-1 residual $\varepsilon_\omega$ dropped by $\hat{\pi}(X)$ | Verified on parent $A_\omega(Y)$ | Cluster compatible $B_\omega(Z)$ into classes $j_\omega$ (`infer-fibers`), then condense intensional selector $\hat{\pi}(X)$ (`condense-heuristic`) |
| **Heuristic policy / Locality / Name (M7, M8D, M9)** | $\varepsilon_\omega \neq 0$ (priced in training, **dropped** at deployment) | No (`heuristic-model`) | Order multi-lane priority queue; replay all candidates against original frame with $1/4$ canonical reserve |

---

## 3. Seven consolidations that streamline the 16-file scaffold into the 7-module kernel

By leaning into homoiconic S-expressions, pooled typed symbols with $O(1)$ metadata, pure S-expression row requirements, and unified multi-lane scheduling, the live kernel ([architecture.md](architecture.md)) consolidates the 16-file `plan4` scaffold into 7 focused modules:

1. **Homoiconic S-expressions with $O(1)$ metadata and cached `:code-*` validation (`ast.lisp`, `vm.lisp`, `laws.lisp`)**:
   Programs are native S-expressions `(#:+ #:X0 (#:* '2 #:X1))` backed by `*typed-symbol-pool*` and weak pointer-keyed metadata `*node-meta*`. Both direct host S-expression matching/substitution (`match-pattern`, `instantiate`) and metered `:code-*` meta-programs (`compile-rule-transformer`, `compile-propagator-matcher`, `compile-au-constructor`, `validated-program`) are supported; single-entry `:code-match` / `:code-bind` memoization (`*last-code-match*` in `vm.lisp`) and cross-job static validation caching (`*prepared-rewrite-cache*` in `laws.lisp`) eliminate redundant AST traversals while keeping 100% tariff parity with [results.md](results.md).
2. **Unified AST & corpus factorization (`factor.lisp` replacing `au.lisp` + `law-compression.lisp`)**:
   Typed anti-unification (`anti-unify`) factors any collection of concrete terms $\{t_\omega\}_{\omega \in \Omega}$ into a shared LGG template $p$ (with value or `:fn` holes `?0, ?1, ...`) and per-row substitution tuples $\theta_\omega$, supporting both lowered `:code-subst` constructors (`compile-au-constructor`) and corpus packet compression (`make-law-corpus`, `propose-law-compressions`).
3. **Streamlined solver & guard synthesis (`laws.lisp` replacing separate `guards.lisp` + `algebra.lisp` + `propagation.lisp`)**:
   Partial-domain equation support (`observed-support`, `propose-guard-problems`, `propose-guarded-laws`) and arithmetic relation reorientation (`observe-arithmetic-relation`, `orient-arithmetic-requirements`, `discover-arithmetic-solver`, `validate-arithmetic-solver`) share the same `support-frame` Boolean synthesis and exhaustive/sampled `law-validation` pipeline.
4. **Co-located enumeration, synthesis, and observation bucketing (`enumerate.lisp` replacing `grammar.lisp` + `search.lisp` + `observations.lisp` + `propagation-search.lisp`)**:
   The exact-bit bottom-up `enumerator` feeds both early-exit synthesis (`search-job` testing $A_\omega(M(e, \omega)) = \mathrm{t}$) and full-table empirical bucketing (`observation-job` over `observation-scope` computing equivalence classes, trajectory invariants across $(\omega, T\omega)$, and retained row outcomes for guard discovery).
5. **Pullback with automatic closed-subtree folding and dual-grade propagation (`frame.lisp`, `vm.lisp`, `laws.lisp`)**:
   `pullback-frame` substitutes $Y \gets d(\mathbf{x}_\omega, Z)$ into $A_\omega(Y)$ and immediately applies `fold-constants` to simplify $Z$-free subtrees and detect row/cross-row conflicts (`frame-conflict-p`); `propagate-arithmetic-child` applies certified $\iff$ solvers in-place on $B_\omega(Z)$ and applies tentative $\Leftarrow$ integer witnesses to populate a forward-verified `propagation-frame` scheduled by `propagation-search`.
6. **Pure S-expression `row-requirement` predicates (`frame.lisp` replacing wrapper-heavy `frames.lisp`)**:
   Every row $\omega \in \Omega$ stores its target constraint natively as a Boolean S-expression `row-requirement` ($A_\omega(Y)$ or $B_\omega(Z)$ in symbolic variable `#:X0`): `singleton-requirement` `(= X0 'v)`, `set-requirement` `(member X0 '(v1 v2))`, or a general relational predicate. `extract-allowed-values` inspects explicit value sets directly in $O(1)$ without executing a checker.
7. **Unified lossy MDL condensation and multi-lane scheduling (`condense-heuristic` in `factor.lisp`, `propagation-search` in `enumerate.lisp`)**:
   Intensional partition selectors (M5/M7), search-control heuristics (M8D), and library descriptors (M9) are all synthesized via `condense-heuristic` (pricing missed rows $\varepsilon(\hat{\pi}, F)$ during training and dropping $\varepsilon$ at deployment) and scheduled with a 1-in-4 canonical reserve.

---

## 4. Concrete worked examples in the `plan6` kernel

### Example 1: Homoiconic S-expressions, schema $\Gamma$, and $O(1)$ schema-parametric sizing (`ast.lisp`)

A `schema` $\Gamma = (D,\, X_0{:}\tau_0,\dots,X_{m-1}{:}\tau_{m-1} \to \tau)$ packages `(domain inputs target lookup-p)`:

```lisp
(defstruct (schema (:constructor %make-schema))
  (domain :int)   ; ambient numeric domain D: :int or (:gf p)
  inputs          ; ordered alist ((0 . (:gf 5)) (1 . (:gf 5))) for X0, X1
  (target :int)   ; target type \tau: (:gf 5), :bool, (:tuple ...), (:seq ...), (:code ...)
  (lookup-p nil))
```

Expressions $e(X) \in \mathcal{L}(\Gamma)$ are native S-expressions whose pooled operator/variable symbols and cons cells map in `*node-meta*` to `ast-meta` structs:

| Surface S-expression $e(X)$ | Types under $\Gamma = (\mathbb{F}_5,\, (X_0, X_1) \to \mathbb{F}_5)$ | Cached $O(1)$ `ast-meta` fields |
|---|---|---|
| `(+ X0 (* '2 X1))` | `+`, `*`, `X0`, `X1`, `'2` all `(:gf 5)` | `non-var-bits = 19`, `var-count = 2`, `syntax-work = 25`, `total-p = t`, `free-vars = (0 1)` |
| `(if (= X0 '0) '0 (/ X0 X1))` | `=` compares `(:gf 5)`; `if` returns `(:gf 5)` | `non-var-bits = 33`, `var-count = 3`, `syntax-work = 36`, `total-p = nil`, `free-vars = (0 1)` |
| `(gather '(1 3) '(0 1 0))` | `'(1 3)` is `(:seq (:gf 5))`; `'(0 1 0)` is `(:seq :int)` | `non-var-bits = 64`, `var-count = 0`, `syntax-work = 29`, `total-p = nil`, `free-vars = ()` |

Because `non-var-bits` and `var-count` are cached at AST construction time, `body-size` for any schema $\Gamma$ with $m = |\Gamma_{\mathrm{inputs}}|$ is a single $O(1)$ formula:

```lisp
(defun body-size (expression inputs)
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (meta (ensure-ast-meta expression)))
    (expression-type expression norm-inputs)
    (+ (ast-meta-non-var-bits meta)
       (* (ast-meta-var-count meta)
          (integer-length (max 0 (1- (length norm-inputs))))))))
```

### Example 2: Pullback, closed-subtree folding, conflict detection, and dual-grade propagation (Milestones 4, 8A, and 8C)

Suppose a parent frame $\Omega$ over $\Gamma_P = (D,\, (X_0{:}\tau_0, X_1{:}\tau_1) \to \tau_P)$ with symbolic parent row requirements $A_\omega(Y)$ is pulled back through a candidate decoder $Y = d(X_0, X_1, Z)$ to a child frame over $\Gamma_C = (D,\, (X_1{:}\tau_1) \to \tau_C)$:

1. **Closed-subtree constant folding during `pullback-frame` (M4 expensive-context control)**:
   Suppose the decoder is `(+ (* X0 X0) Z)` with row value $x_{\omega,0} = 2^{128} + i$ and parent singleton requirement $A_\omega(Y) \equiv \texttt{(= Y 'y\_w)}$.
   Substituting $X_0 \gets \text{'}x_{\omega,0}$ into $A_\omega(d(x_{\omega,0}, x_{\omega,1}, Z))$ and calling `fold-constants` recognizes that `(* 'x_{w,0} 'x_{w,0})` has no free symbolic variable $Z$ (`(null (free-vars subtree))`), evaluates it **once** during pullback to literal value $K_\omega = x_{\omega,0}^2$, and produces the simplified symbolic child requirement:
   $$B_\omega(Z) \equiv \texttt{(= (+ '} K_\omega\ \texttt{Z) '} y_\omega\texttt{)}.$$
2. **Certified field propagation ($\iff$, `(:gf 5)`)**:
   Applying the certified (`:validated`) additive solver for $R_+(K, Z, C)$ rewrites $B_\omega(Z)$ **in-place** via `propagate-arithmetic-child` to the singleton requirement `(= Z 'v_w)` where $v_\omega \equiv y_\omega - K_\omega \pmod{5}$.
   On a nested linear decoder $Y = X_0 + X_1 \cdot Z$ (Milestone 8A), two chained steps of pullback + solver propagation reduce `(= (+ '1 (* '2 Z)) '0)` $\to$ `(= (* '2 Z) '4)` $\to$ `(= Z '2)`.
3. **Tentative integer propagation ($\Leftarrow$, `:int`)**:
   Consider two rows $\omega_1, \omega_2$ sharing identical child input value $\mathbf{x}_{\omega_1} = \mathbf{x}_{\omega_2} = (0)$ with pulled-back requirements $B_{\omega_1}(Z) \equiv \texttt{(= (/ Z '2) '1)}$ ($\mathrm{Fiber}(\omega_1) = \{2, 3\}$) and $B_{\omega_2}(Z) \equiv \texttt{(= (/ Z '3) '1)}$ ($\mathrm{Fiber}(\omega_2) = \{3, 4, 5\}$).
   The integer division witness $q(K, C) = K \cdot C$ proposes value $v_{\omega_1} = 2$ on $\omega_1$ and $v_{\omega_2} = 3$ on $\omega_2$. Both pass individual forward verification $B_{\omega_1}(2) = \mathrm{t}$ and $B_{\omega_2}(3) = \mathrm{t}$.
   Because the integer solver is only a tentative witness ($\Leftarrow$), `propagate-arithmetic-child` retains the original pullback frame $B_{\omega_1}, B_{\omega_2}$ as `propagation-fallback` and places the narrowed singleton requirements $B_{\omega_1}^{\mathrm{pref}}(Z) \equiv \texttt{(= Z '2)}$, $B_{\omega_2}^{\mathrm{pref}}(Z) \equiv \texttt{(= Z '3)}$ in `propagation-frame`.
4. **Immediate conflict detection (`frame-conflict-p`, Milestone 8C)**:
   In the narrowed frame above (or in an invalid Milestone 7 partition), rows $\omega_1$ and $\omega_2$ have identical known child input value $\mathbf{x}_\omega = (0)$ but incompatible singleton requirements `(= Z '2)` and `(= Z '3)`. Calling `conjoin-requirements` folds their conjunction to `'nil`, so `frame-conflict-p` flags `:incompatible-rows` in $O(|\Omega|)$ time; meanwhile, the `propagation-fallback` lane finds the true shared value $z = 3 \in \mathrm{Fiber}(\omega_1) \cap \mathrm{Fiber}(\omega_2)$.
   Similarly, pulling back $A_\omega(Y) \equiv \texttt{(= Y '(2 3))}$ through diagonal tuple decoder $d(Z) = \texttt{(tuple Z Z)}$ decomposes by tuple injectivity inside `fold-constants` into `(if (= Z '2) (= Z '3) 'nil)` $\xrightarrow{\text{fold}} \texttt{'nil}$, immediately flagging `:unsatisfiable-row`.

### Example 3: Two-stage topological lifting — Extensional Hard-EM fiber clustering to intensional selector condensation (Milestones 5 & 7)

When decomposing $Y = d(X, Z)$ where the child value $z_\omega$ depends on a latent regime or context class $j_\omega \in \{0, \dots, K-1\}$, enumerating candidate selector expressions top-down and running child synthesis for each candidate is combinatorially prohibitive. Instead, the kernel separates **Stage 1 (extensional fiber clustering via `infer-fibers`)** from **Stage 2 (intensional selector synthesis via `condense-heuristic`)**:

1. **Pullback to row fibers (Operation 3, `pullback-frame`)**:
   Pulling back $A_\omega(Y)$ through $d(\mathbf{x}_\omega, Z)$ yields per-row symbolic requirement predicates $B_\omega(Z)$ defining $\mathrm{Fiber}(\omega) = \{z \in \mathcal{V}_{\tau_C} \mid B_\omega(z) = \mathrm{t}\}$. Some rows simplify to rank-0 singletons (`(= Z '1)`, `(= Z '3)`), while others remain rank-1 finite sets (`(member Z '(1 2))`) or rank-2 relational predicates (`(= (/ Z '2) '1)`).
2. **Stage 1 — Extensional Hard EM over fiber compatibility (Operation 2, `infer-fibers`)**:
   `infer-fibers` processes rows $\omega \in \Omega$ in ascending order of `fiber-tightness-rank`, clustering $\Omega$ into $K$ `fiber-class`es $c_0, \dots, c_{K-1}$ with narrowed class requirement $B_{c_j}(Z) = \bigwedge_{\omega \in c_j} B_\omega(Z)$:
   - **Cannot-links**: Any merge where `(conjoin-requirements B_c B_w target-type)` folds to `'nil` ($\mathrm{Fiber}(c) \cap \mathrm{Fiber}(\omega) = \emptyset$) is vetoed.
   - **Confidence-ordered E-step / M-step**: Tight rank-0 singletons are processed first, founding clean classes $c_0: \texttt{(= Z '1)}$ and $c_1: \texttt{(= Z '3)}$. When an ambiguous rank-1 row $\omega$ with `(member Z '(1 2))` arrives, the **E-step** sees that $B_{c_0} \land B_\omega = B_{c_0}$ ($\mathrm{Fiber}(c_0) = \{1\} \subseteq \{1, 2\}$), assigning $\omega \to c_0$ ($j_\omega = 0$) at zero marginal bit cost ($\Delta S = 0$) without nucleating a spurious class for $z = 2$.
3. **Stage 2 — Intensional selector synthesis (Operation 4, `condense-heuristic`)**:
   Once Stage 1 assigns an extensional class value $j_\omega \in \{0, \dots, K-1\}$ (or refined fiber requirement) to each row $\omega$, `condense-heuristic` synthesizes an intensional expression $\hat{\pi}(X)$ over the symbolic input variables $X$ minimizing $S(\hat{\pi}) + S(\varepsilon(\hat{\pi}, F)) + \lambda_{\mathrm{run}} W_{\mathrm{run}}(\hat{\pi})$, drops the training residual $\varepsilon$ at deployment, and verifies the resulting composite model against the authoritative parent frame $\Omega$.

### Example 4: Uniform debt-draining stepper (`vm.lisp`) and Multi-Lane scheduler (`enumerate.lisp`)

Every resumable computation in `vm.lisp` prepays its structural tariff before executing through `evaluation` (`start-evaluation`, `advance-evaluation`, `start-program-validation`, `start-validated-evaluation`, `advance-accounted-evaluation`):

```lisp
(defstruct evaluation
  (status :unknown)
  value
  (work 0)
  (remaining-cost 0)
  tasks
  context
  lookup-fn)

(defun advance-evaluation (evaluation budget)
  (loop while (and (eq :unknown (evaluation-status evaluation))
                   (plusp budget))
        do (cond
             ((plusp (evaluation-remaining-cost evaluation))
              (let ((paid (min budget (evaluation-remaining-cost evaluation))))
                (decf budget paid)
                (decf (evaluation-remaining-cost evaluation) paid)
                (incf (evaluation-work evaluation) paid)))
             ((null (evaluation-tasks evaluation))
              (setf (evaluation-status evaluation) :value))
             (t (step-evaluation-task evaluation))))
  evaluation)
```

Multi-lane scheduling (`propagation-search` in `enumerate.lisp`) coordinates tentative/heuristic lanes with a guaranteed canonical fallback:

- Every 4th quantum (`(= 3 (mod turn 4))`) is reserved for the canonical `:fallback` lane (weight $1/4$); the remaining 3 quanta advance the `:primary` heuristic/narrowed lane (or `:verification`).
- Any candidate discovered on a narrowed `:primary` frame is replayed against the original parent/pullback frame (`propagation-original`) before entering `results`.

---

## 5. Module architecture of the live 7-module kernel

| Module | Consolidates (`plan4` files) | Responsibilities & Key Exports ([`architecture.md`](architecture.md)) |
|---|---|---|
| **`1. ast.lisp`** | `syntax.lisp`, `symbolic.lisp` (types) | Schema $\Gamma = (D, \text{inputs}, \tau)$ (`make-schema`), pooled homoiconic S-expressions (`lit`, `var`, `op`, `app`, `hole`), weak $O(1)$ metadata table `*node-meta*` (`non-var-bits`, `var-count`, `syntax-work`, `total-p`, `free-vars`), `body-size`, `instantiate`. |
| **`2. codec.lisp`** | `codec.lisp` | Prefix-free binary serializer (`encode-model`, `decode-model`, `+encoding-version+ = 7`), $O(1)$ `header-size` and `description-size`, canonical ordering `expression-less-p`. |
| **`3. vm.lisp`** | `sim.lisp` | Structural tariff (`+tariff-version+ = 8`, `value-work`, `syntax-work`), debt-draining `evaluation` stepper (`start-evaluation`, `advance-evaluation`, `validated-program`), `*last-code-match*` memoization, and closed-subtree constant folder (`fold-constants`). |
| **`4. frame.lisp`** | `frames.lisp`, `guards.lisp` (frames) | `frame` ($\Omega$) and `row` ($\omega$) with input values $\mathbf{x}_\omega$ (`row-known`) and Boolean S-expression `row-requirement` ($A_\omega(Y), B_\omega(Z)$), `conjoin-requirements`, `frame-conflict-p`, `orient-observations`, `pullback-frame` (with automatic `fold-constants`), `support-frame`, `quotient-values`, `partition-rows`. |
| **`5. enumerate.lisp`** | `grammar.lisp`, `search.lisp`, `observations.lisp`, `propagation-search.lisp` | Exact-bit bottom-up `enumerator` over $\mathcal{L}(\Gamma)$, synthesis `search-job`, equivalence-bucketing `observation-job` ($M(e, \omega)$, `observation-invariants`), and multi-lane `propagation-search` (1-in-4 canonical reserve). |
| **`6. factor.lisp`** | `au.lisp`, `law-compression.lisp` | First-order `match-pattern`, typed `anti-unify` ($t_\omega = \mathrm{Subst}(p, \theta_\omega)$) & `compile-au-constructor`, confidence-ordered Hard-EM fiber clustering (`infer-fibers`), lossy MDL heuristic condensation (`condense-heuristic`), and M3B `law-corpus` compression. |
| **`7. laws.lisp`** | `laws.lisp`, `guards.lisp`, `algebra.lisp`, `propagation.lisp` | Equational & guarded law discovery (`propose-observed-laws`, `propose-guarded-laws`), exhaustive $D^\Gamma$ & sampled `law-validation`, cached symbolic rewriting (`prepare-rewrite-library`, `start-rewriting`), M4 solver discovery (`discover-arithmetic-solver`), and dual-grade $\iff$/$\Leftarrow$ propagation (`propagate-arithmetic-child`). |

---

## 6. How all nine milestones map onto the four operations

| Milestone | Execution in the 7-Module Kernel ([`architecture.md`](architecture.md)) |
|---|---|
| **1. Core Synthesis** | **Op 1 + Op 2 + Op 3**: `search-job` tests $A_\omega(M(e, \omega)) = \mathrm{t}$ across $\omega \in \Omega$; `pullback-frame` + `compose-model` decompose through $Y = d(X, Z)$; `partition-rows`, `quotient-values`, and `anti-unify` factor views, values, and ASTs. |
| **2. Observational Equivalence** | **Op 1**: `observation-job` evaluates $\mathcal{E} \times \Omega$, partitions total output value vectors into `observation-bucket`s, and extracts `observation-invariants` conserved across transition pairs $(\omega, T\omega)$ while varying across `anchors`. |
| **3. Guarded Laws & Rewriting** | **Op 1 + Op 2**: M3A extracts partial support masks (`observed-support`) and synthesizes exact guards $G(X)$ on `support-frame` (`propose-guarded-laws`), validated over $D^\Gamma$ (`start-law-validation`). M3B compresses quoted `:code` law corpora via `anti-unify` + `quotient-values` (`propose-law-compressions`). M3C amortizes validated `:code-*` rewrite rules across `search-job`s (`prepare-rewrite-library`). |
| **4. Algebraic Reorientation & Propagation** | **Op 1 + Op 3 + Op 4**: `observe-arithmetic-relation` & `orient-arithmetic-requirements` reorient $R_f(K, Z, C)$; `discover-arithmetic-solver` learns witness $q(K, C)$ and guard $G(K, C)$; `propagate-arithmetic-child` rewrites $B_\omega(Z)$ in-place when certified ($\iff$, $\mathbb{F}_p$) or schedules narrowed `propagation-frame` 3:1 against `propagation-fallback` in `propagation-search` when tentative ($\Leftarrow$, $\mathbb{Z}$). |
| **5. Intermediate Concept Lifting** | **Op 3 + Op 2 + Op 4**: `pullback-frame` forms $B_\omega(Z) := A_\omega(d(\mathbf{x}_\omega, Z))$; withholding a needed context variable causes `frame-conflict-p` to detect `:incompatible-rows`; `infer-fibers` clusters compatible row fibers $\mathrm{Fiber}(\omega)$ into latent classes $j_\omega$, and `condense-heuristic` synthesizes an intensional selector $\hat{\pi}(X)$ with $\hat{\pi}(\mathbf{x}_\omega) \approx j_\omega$. |
| **6. Typed Anti-Unification & Macros** | **Op 2**: `anti-unify` computes the typed LGG pattern $p$ and per-row residuals $\theta_\omega$ on quoted `:code` terms $t_\omega$ (including repeated-hole diagonal constraints and function-sorted operator holes), lowered into reusable `:code-subst` constructors by `compile-au-constructor`. |
| **7. Autonomous View Discovery & Locality** | **Op 2 + Op 4**: Stage 1 (`infer-fibers` / `quotient-values`) clusters compatible row requirements $B_\omega(Z)$ into extensional class values $j_\omega \in \{0, \dots, K-1\}$; Stage 2 (`condense-heuristic`) synthesizes an intensional regime selector $\hat{\pi}(X)$ (reassembled by `partition-model` / `:gather`). |
| **8. Recursive Synthesis & Search Control** | **8A (Op 3)**: Chained `pullback-frame` + `fold-constants` + `propagate-arithmetic-child` across nested decoders. **8B**: Shared `*node-meta*` & `*prepared-rewrite-cache*`. **8C (Op 3)**: Tuple injectivity and same-input conjunction fold impossible child requirements to `'nil` (`frame-conflict-p`). **8D (Op 4)**: `condense-heuristic` learns a residual-priced heuristic $\hat{\pi}(X)$ (dropping $\varepsilon$ at deployment) to prioritize lanes in `propagation-search`. |
| **9. Self-Hosted Vocabulary & Policy** | **Op 2 + Op 4**: Promoted macros and policies run as metered `:code-*` programs or `heuristic-model`s over `:code` and base frames, ranked on new frames $\Omega$ by condensed symbolic descriptors $\hat{\pi}(X)$ while retaining the 1-in-4 canonical reserve. |
