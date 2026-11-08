# Plan 7 — Persistent Knowledge Library: Synthesized Laws, Algebras, Functions, Heuristics, and Relational Structure

This plan specifies the next evolutionary step for `lisploop` following the completion and audit of [plan7-recursion.md](plan7-recursion.md), extending [plan7.md](plan7.md) (especially Milestone 9) in strict alignment with [prompt4.md](prompt4.md) and [architecture.md](architecture.md).

---

## 1. Objective & Architectural Mandate

Up to now, the artifacts discovered by `lisploop`—recursive functions and higher-order combinators (`*function-definitions*`), guarded algebraic laws (`law-validation`), checked syntax rewriters (`rewrite-library`), inverse requirement propagators (`propagator-library`), deductive nogood/DIP schemas (`nogood-clause`), and condensed search-trace heuristics (`heuristic-model`)—have lived in separate per-call structs or isolated global tables that are manually wired and cleared between synthesis runs.

Our goal is to unify all learned knowledge and the relational structure linking it together into a single **Persistent Knowledge Library** (`knowledge-library` / `*knowledge-library*`) that serves as the de facto store of knowledge across synthesizer calls:

1. **One Flat Homoiconic Store with Relational Linkage ("Graph over a Graph"):**
   Following [prompt4.md](prompt4.md) (§5–7, *"all data / experience should be in one 'flat' store. A list. In lisp"*), all learned items live in a single append-ordered list of typed homoiconic `knowledge-entry` records, cross-linked by explicit relational edges (`:derived-from`, `:certified-by`, `:inverts`, `:rewrites`, `:abstracts`, `:retyped-from`, `:repairs`, `:describes`) and backed by $O(1)$ runtime indexes.
2. **Strictly VM-Executable Knowledge:**
   Every piece of knowledge in the library is a typed S-expression AST executed on the metered VM (`vm.lisp`):
   - **Functions & Combinators (`:function`):** Object-language AST bodies executed via zero-copy lexical frame dispatch and `:code-eval`.
   - **Guarded Laws & Algebras (`:law`):** Guarded equation ASTs `(if G (= lhs rhs) 't)` paired with compiled `:code-*` rule-transformer ASTs (`compile-rule-transformer`).
   - **Solvers & Propagators (`:solver`):** Solvability guard ASTs $G(k,c)$, witness ASTs $q(k,c)$, and compiled `:code-*` pattern-matcher ASTs (`compile-propagator-matcher`), generalized to invert both built-in primitives and learned library functions/conserved quantities.
   - **Behavioral Descriptors (`:descriptor`):** Compact VM-executable probe predicates and structural signatures that trigger/filter library entries in $O(1)$ VM evaluations rather than blind enumeration ([prompt4.md](prompt4.md) lines 201–219; [plan7.md](plan7.md) §4.9).
   - **Heuristics & Deductive Schemas (`:heuristic`, `:nogood-schema`, `:dip-feature`):** Search-trace priority predictor ASTs $\hat{\pi}(X_{\mathrm{trace}})$, generalized UIP conflict patterns `(= X0 ?0)`, and DIP context-repair feature ASTs `(length X0)`.
3. **Closed-Loop Generation & Execution Across Calls:**
   The synthesizer automatically **consumes** the active `knowledge-library` (expanding the grammar with learned functions, narrowing pulled-back frames with learned propagators, normalizing syntax with validated rewrites, pruning/repairing conflicts with UIP/DIP schemas, and routing agenda nodes with the learned priority predictor) and **updates/consolidates** the library as new functions, laws, solvers, and traces are acquired.

---

## 2. Three Foundational Design Pillars

### 2.1 Every Entry Captures Transform, Applicability, and Optional Residual

Every `knowledge-entry` in the store uniformly represents a unit of computational knowledge as a guarded, triggered transformation plus an optional irreducible residual $(\hat{\pi}, G, T, \varepsilon)$:

1. **Transform (`expression`):** What computation or relation the entry evinces (a function body, an oriented equation/rewrite, an inverse witness $q(k,c)$, a priority predictor $\hat{\pi}$, or a bare `:lookup`/`:member` relation).
2. **Applicability (`inputs`, `target`, `guard`, `trigger`):**
   - *Types (`inputs`, `target`, `domain`):* Static sort discipline.
   - *Logical Guard (`guard`):* Exact domain of validity $G(X)$ (e.g., divisor non-zero, fiber uniqueness condition, or hit-mask separator).
   - *Heuristic / Behavioral Trigger (`trigger`):* A cheap VM-executable descriptor predicate or probe signature that gates when the entry should be proposed during search without blind enumeration.
3. **Irreducible Residual (`residual` — First-Order & Second-Order Bare Tables/Relations):**
   - Real-world and intermediate synthesis tasks frequently leave irreducible facts—exception rows $\varepsilon$, empirical lookup tables, or bare relations that cannot (yet) be compressed into a shorter intensional rule.
   - Because `lisploop` has first-class `:lookup` (`(lookup X '((k1 v1) ...))`), `:member` (`(member (tuple ...) '(...))`), and `:code` types, **both first-order bare tables (over `:int`, `(:gf p)`, `(:seq ...)`) and second-order bare relations (over `(:code ...)` syntax/operators)** are ordinary VM-executable ASTs priced by the exact same bitstream codec (`description-size`).
   - Retaining bare tables/relations (`:relation` / `residual` slot) in the persistent library serves two roles:
     1. **Immediate VM execution:** Hybrid programs $(\hat{\pi}, \varepsilon)$ execute directly as `(if G_hit \hat{\pi}(X) (lookup X 'residual-table))` (or `( + \hat{\pi}(X) (lookup X 'delta-table))`).
     2. **Delayed structure discovery (cryogenic empirical buffer):** An exception table $\varepsilon_1$ from one task may be too small to pay the description-length header $S(L)$ of a new abstraction on its own. When later tasks deposit $\varepsilon_2, \varepsilon_3$, `consolidate-knowledge-library` runs joint quotienting (`infer-fibers`, `propose-observed-laws`, `discover-library-abstractions`) across accumulated residuals, condensing them into a new intensional law or function once $\sum_k S(\varepsilon_k) > S(L) + \sum_k S(\varepsilon_k \mid L)$.

### 2.2 Higher-Order Edges and the Induction of Theories (`:functor` / Meta-Laws)

Edges in `knowledge-library` are not merely passive provenance bookmarks—they are **second-order relational facts** (`(edge-kind source-id target-id ...)`), stored in the same flat homoiconic format. This enables three mechanisms for inducing new functions and generalizations ("theories"):

1. **Co-Induction of Linked Knowledge (Functorial Meta-Rules):**
   - Anti-unifying across *connected subgraphs* (edges + endpoints) discovers second-order rules (`:functor` entries).
   - *Example (Functorial Inversion):* When `:inc-all` (`(:map X0 '(+ X0 '1))`) is linked via `:inverts` to `:dec-all` (`(:map X0 '(- X0 '1))`) because `'(+ X0 '1)` $\leftrightarrow$ `'(- X0 '1)`, and `:double-all` is linked via `:inverts` to `:halve-all` under an evenness guard, anti-unifying the `:inverts` edge across `:map` instances induces the second-order functorial solver:
     $$\mathrm{invert}((\text{:map } xs\; f),\; y) \;\Longrightarrow\; (\text{:map } y\; f^{-1}) \quad \text{guarded by } (\text{:foldr } y\; \text{'t}\; (\lambda (e, \text{acc}) \to G_{f^{-1}}(e) \land \text{acc})).$$
     Any newly synthesized `:map` program immediately inherits an inverse propagator and solvability guard from the `:inverts` edge of its element function $f$ without running a new solver search.
2. **Theory Formation (Shared Algebraic / Relational Motifs):**
   - When multiple functions share a relational star of edges—for example, `:sum`, `:product`, and `:append` are each `:refactored-by` `:foldr` with a step operator $\oplus$ that has an `:identity` law and an `:associativity` law—quotienting across those stars forms a reusable **theory motif** (e.g. a Monoid / Fold-Homomorphism schema), licensing cross-representation rewrites such as `:foldr` $\leftrightarrow$ `:foldl` or $F(\mathrm{append}(a,b)) = F(a) \oplus F(b)$.
3. **Graph-Neighborhood Locality for Subgraph AU:**
   - Sharing relational edges defines a natural graph distance between library entries. Passing edge-neighborhood coordinates as the `:locality-key` to `discover-subexpression-abstractions` and `discover-library-abstractions` seeds pairwise anti-unification along structurally related entries (`schedule-occurrence-pairs` with the 3:1 canonical reserve) rather than $O(N^2)$ blind pairs.

### 2.3 Declarative Lisp Metaprogramming (`define-knowledge-kind`)

To keep library creation, indexing, consumption, consolidation, and serialization/deserialization compact, uniform, and extensible without sprawling `ecase` dispatch across files, all knowledge kinds are registered through a single declarative macro **`define-knowledge-kind`**:

```lisp
(define-knowledge-kind name
  (:validate (entry library) ...)
  (:install (entry library ledger) ...)     ; populate O(1) runtime indexes / VM hooks
  (:consume (entry context ledger) ...)     ; expose to grammar / propagators / expanders
  (:consolidate (entries library ledger) ...)) ; periodic AU / law / residual condensation
```

Because every `knowledge-entry` shares the same homoiconic struct layout (typed AST slots `expression`, `guard`, `trigger`, `residual`, `auxiliary-code` + canonical `edges` and `metadata`), **creation, S-expression / bitstream serialization (`ast->sexp` / `sexp->ast`), deserialization, graph indexing, and human-readable inspection (`explain-knowledge-library`) are written once generically** in ~80 lines of code. Adding a new knowledge kind (`:function`, `:law`, `:solver`, `:descriptor`, `:heuristic`, `:nogood-schema`, `:dip-feature`, `:relation`, `:functor`) is a 10–15 line declarative `(define-knowledge-kind ...)` specification.

---

## 3. Core Data Structures & Relational Graph

### 3.1 `knowledge-entry`

Every item in the persistent store is a `knowledge-entry`:

```lisp
(defstruct (knowledge-entry (:constructor %make-knowledge-entry))
  id              ; Canonical keyword ID (:FA, :FB, :LAW-0, :SOLVER-0, :REL-0, :FUNC-0, ...)
  kind            ; Registered via `define-knowledge-kind`:
                  ;   :function | :law | :solver | :descriptor | :heuristic
                  ;   | :nogood-schema | :dip-feature | :relation | :functor
  domain          ; :int | (:gf p) | :any
  inputs          ; Input schema ((0 . type0) ...)
  target          ; Output/target sort or type
  expression      ; Primary VM-executable S-expression AST (what transform it evinces)
  guard           ; Logical validity guard AST (default '(quote t))
  trigger         ; Optional VM-executable heuristic/descriptor trigger AST
  residual        ; Optional irreducible bare table / relation AST or correction packet
  auxiliary-code  ; Optional compiled :code-* VM program (matcher or rule-transformer AST)
  status          ; :validated | :certified | :tentative | :conjecture | :empirical
  certificate     ; Optional law-certificate, solver-certificate, or MDL compression summary
  (bits 0 :type fixnum)       ; Description length S(entry) in bits
  (gain 0 :type fixnum)       ; Net MDL bit savings \Delta S when admitted via abstraction/compression
  (work 0 :type fixnum)       ; Cumulative discovery/validation work charged
  edges           ; Alist of typed relational links ((:abstracts :copy :inc-all) (:certified-by :law-1 :law-2) ...)
  metadata)       ; Kind-specific plist (:total-p, :conditional-code-params, :oracle-table, :operator, :position, ...)
```

### 3.2 Relational Edge Vocabulary

Edges form a typed directed graph over `knowledge-entry` IDs and primitive operators:

| Edge Key | Source $\to$ Target | Meaning |
| :--- | :--- | :--- |
| `:abstracts` | `:function` (combinator) $\to$ `(:function ...)` | Higher-order AU combinator $L$ factors concrete functions $\{p_i\}$ with $\Delta S > 0$ |
| `:refactored-by` | `:function` $\to$ `:function` (combinator) | Concrete function body was rewritten to call combinator $L$ with a `:code` literal |
| `:normalized-by` | `:function` $\to$ `(:law ...)` | Corpus bodies were normalized by these validated rewrite laws prior to AU |
| `:rewrites` | `:law` $\to$ operator / `:function` | Oriented guarded law `(if G (= lhs rhs) 't)` rewrites `lhs` (headed by target) to `rhs` |
| `:inverts` | `:solver` / `:functor` $\to$ operator / `:function` | Solver $(G, q)$ (or second-order functor) inverts target at argument `:position` |
| `:certified-by` | `:solver` $\to$ `(:law :law)` | Links a solver to its witness-soundness law and fiber-uniqueness law |
| `:retyped-from` | `:law` $\to$ `:law` | Conjecture obtained by domain retyping (`retype-law`, e.g. `(:gf 5)` $\to$ `:int`) |
| `:describes` | `:descriptor` $\to$ `:function` / `:solver` | Compact VM-executable behavioral probe or invariant labeling the target entry |
| `:repairs` | `:dip-feature` $\to$ `:nogood-schema` | Context-binding feature expression that resolves the target UIP lift-conflict pattern |
| `:has-residual` | `:function` / `:heuristic` $\to$ `:relation` | Links an approximate rule $\hat{\pi}$ to its irreducible bare residual table/relation $\varepsilon$ |
| `:induces` | `:functor` $\to$ `(:solver \| :law \| :function ...)` | Second-order edge rule induced by anti-unifying across connected first-order motifs |
| `:condensed-from` | `:heuristic` \| `:function` $\to$ `(entry-id ...)` | Entry condensed from search traces or accumulated `:relation` residual tables |

### 3.3 `knowledge-library` Container

```lisp
(defstruct (knowledge-library (:constructor %make-knowledge-library))
  (version 0 :type fixnum)
  entries                 ; Flat chronological list of `knowledge-entry` structs (the authoritative store)
  ;; O(1) derived runtime indexes (maintained generically via `define-knowledge-kind` hooks):
  by-id                   ; Hash table: id -> knowledge-entry
  by-kind                 ; Hash table: kind -> list of knowledge-entry
  incoming-edges          ; Hash table: target-id -> list of (edge-key source-id ...)
  functions               ; Hash table: fn-name -> function-definition (synced with VM dispatch)
  function-names          ; Ordered list of registered function keywords (:fa, :fb, ...)
  rewrite-libraries       ; Hash table: domain -> prepared `rewrite-library`
  propagator-libraries    ; Hash table: domain -> prepared `propagator-library`
  descriptors             ; Hash table: target-id -> list of `:descriptor` entries
  priority-predictor      ; Most recent `:heuristic` entry (or nil)
  (next-counter 0 :type fixnum))
```

- **Global Default & Lexical Scoping:** `*knowledge-library*` holds the active default `knowledge-library`. Calling `with-knowledge-library` (or passing `:library` to synthesis/discovery entry points) binds `*knowledge-library*` and synchronizes `*function-definitions*`, `*registered-function-names*`, and `*function-library-version*` so the VM and codec operate seamlessly without breaking any existing API or test.

---

## 4. Phased Implementation Plan

### Phase 1: `define-knowledge-kind` Metaprogramming, Core Store, & Generic Persistence (`ast.lisp`, `codec.lisp`)

1. **Declarative Kind Registry (`define-knowledge-kind` in `ast.lisp`):**
   - Define the `define-knowledge-kind` macro and `*knowledge-kind-specs*` protocol table.
   - Write the **single generic lifecycle engine** (`register-knowledge-entry`, `remove-knowledge-entry`, `rebuild-knowledge-indexes`, `knowledge-entry->sexp`, `sexp->knowledge-entry`, `consume-knowledge-library`, `consolidate-knowledge-library`, `explain-knowledge-library`) that iterates over registered kind specs rather than hardcoding `ecase` dispatch.
2. **Unified Function & Relation Registry Bridge (`ast.lisp`):**
   - Connect `define-function`, `find-function-definition`, `clear-function-definitions`, and `next-function-name` to `*knowledge-library*`.
   - Register `:function` and `:relation` (first-order and second-order bare `:lookup` / `:member` tables and unfactored residual packets $\varepsilon$) via `define-knowledge-kind`.
   - Add `with-knowledge-library (library &body body)` to switch or isolate knowledge libraries cleanly without destructive global wipes.
3. **Generic Homoiconic S-Expression & Bitstream Persistence (`codec.lisp`):**
   - Implement `serialize-knowledge-library` / `deserialize-knowledge-library` and `save-knowledge-library` / `load-knowledge-library` using a uniform typed-AST S-expression walker (`ast->sexp` / `sexp->ast`) that handles all `knowledge-entry` AST slots (`expression`, `guard`, `trigger`, `residual`, `auxiliary-code`) generically for every registered kind.

### Phase 2: VM-Executable Algebras, Rewrites, Generalized Propagators, & Functorial Edges (`laws.lisp`, `frame.lisp`)

1. **Declarative `:law`, `:solver`, and `:functor` Kinds (`laws.lisp`):**
   - Register `:law`, `:solver`, and `:functor` via `define-knowledge-kind`.
   - Extend `as-propagator-library` and `as-rewrite-library` to accept a `knowledge-library` directly.
2. **Generalizing Propagators to Learned Functions & Conserved Quantities (`laws.lisp`, `frame.lisp`):**
   - Generalize `compile-propagator-matcher` and `solve-learned-equality` so a `:solver` entry can invert **any primitive or learned library function/relation** at argument `:position` when the remaining arguments are closed/known (preserving the 3:1 `:fallback` sibling guarantee when `unique-p` is `nil`).
3. **Second-Order Edge Generalization (`:functor` Induction in `laws.lisp` / `factor.lisp`):**
   - When multiple library functions refactored by the same higher-order combinator (e.g., `:inc-all` and `:double-all` calling `:map`) have `:inverts` edges whose element functions also have `:inverts` edges (`+1` $\leftrightarrow$ `-1`, `*2` $\leftrightarrow$ `/2`), induce a `:functor` entry that automatically synthesizes the inverse `:solver` and solvability guard for any new call to that combinator!

### Phase 3: VM-Executable Triggers/Descriptors, Residuals, & Deductive Memory (`factor.lisp`, `synthesize.lisp`)

1. **Behavioral Triggers / Descriptors (`:descriptor`):**
   - When a `:function` or `:solver` is installed, compute and attach its `trigger` / `:descriptor` AST (recording probe invariants such as empty-sequence image `(:fa '() ...)` and length preservation vs reduction `(= (length out) (length in))`).
   - In `library-decompositions`, evaluate `trigger` ASTs on the current `frame` in $O(|\Omega|)$ VM steps (`:descriptor-check`) to filter incompatible combinators before running `lift-frame` and `fold-constants`.
2. **Persistent Irreducible Residuals (`:relation` / `residual` Slot) & Delayed Condensation:**
   - Allow `condense-heuristic` and `start-heuristic-synthesis` to commit hybrid models $(\hat{\pi}, \varepsilon)$ whose exception residual $\varepsilon$ is retained as a linked `:relation` entry (`(:has-residual :rel-id)`).
   - During consolidation, when multiple `:relation` residuals accumulate over compatible schemas, run joint quotienting (`infer-fibers`, `propose-observed-laws`, `discover-library-abstractions`) to condense the bare tables into a new intensional rule once net MDL gain $\Delta S > 0$.
3. **Persistent UIP Nogood Schemas, DIP Features, & Priority Predictors (`:nogood-schema`, `:dip-feature`, `:heuristic`):**
   - Persist `(:repairs :nogood-schema-id)` edges linking DIP context-binding features (`(length X0)`) to UIP conflict patterns (`(= X0 ?0)`), and evaluate matching `:dip-feature` entries first in `propose-dip-context-bindings`.
   - Persist the search-trace priority predictor $\hat{\pi}(X_{\mathrm{trace}})$ as a `:heuristic` entry automatically consumed by `start-synthesis` / `start-heuristic-synthesis` / `start-recursive-synthesis`.

### Phase 4: Closed-Loop Consolidation & Continual Curriculum (`factor.lisp`, `synthesize.lisp`)

1. **`consolidate-knowledge-library` (Driven by `define-knowledge-kind` Consolidation Hooks):**
   - Runs each registered kind's `:consolidate` hook in dependency order under one shared work `ledger`:
     1. **`:law` & `:solver`:** Validates pending laws/retyped conjectures, compiles syntax-decreasing rewrites, and validates inverse propagators.
     2. **`:relation` (Residual Mining):** Attempts joint condensation across accumulated bare residual tables/relations when $\Delta S > 0$.
     3. **`:function` (Locality-Seeded Higher-Order AU):** Uses shared relational edges as the `:locality-key` to group and anti-unify `:function` bodies (normalized by the library's rewrite rules), registering new higher-order combinators (`:map`, `:foldr`, `:foldl`, ...), refactoring existing `:function` entries in place, and computing their `trigger` descriptors.
     4. **`:functor` (Second-Order Edge AU):** Generalizes across connected `(:refactored-by, :inverts, :rewrites)` edge stars to induce functorial solvers/laws.
     5. **`:nogood-schema`, `:dip-feature`, & `:heuristic`:** Extracts UIP $\leftarrow$ DIP repair links and condenses updated search-trace priority predictors.

---

## 5. Verification & Test Suite Plan (`tests/library.lisp` + `tests/run.lisp`)

We will add a dedicated test suite `tests/library.lisp` (aliased under `m9` and `library` in `tests/run.lisp`) exercising:

1. **Test 1 — `define-knowledge-kind` Metaprogramming & Generic Persistence Roundtrip:**
   - Verify that all registered knowledge kinds (`:function`, `:law`, `:solver`, `:descriptor`, `:heuristic`, `:nogood-schema`, `:dip-feature`, `:relation`, `:functor`) are created, indexed, inspected (`explain-knowledge-library`), serialized (`serialize-knowledge-library`), and deserialized (`deserialize-knowledge-library`) through the single generic protocol, preserving all AST metadata, totality flags, certificates, and relational edges.
2. **Test 2 — Bare Residual Tables / Second-Order Relations & Delayed Structure Discovery:**
   - Store irreducible first-order (`:lookup` / `:member`) and second-order (relations over `:code` syntax) `:relation` entries and hybrid $(\hat{\pi}, \varepsilon)$ programs in `*knowledge-library*`.
   - Verify immediate VM execution of hybrid $(\hat{\pi}, \varepsilon)$ entries, then deposit multiple task residuals $\varepsilon_1, \varepsilon_2, \varepsilon_3$ that are individually incompressible but jointly condense into a new intensional rule with positive MDL gain ($\Delta S > 0$) during `consolidate-knowledge-library`.
3. **Test 3 — Higher-Order Edges, Functorial Inversion, & Behavioral Triggers:**
   - Verify that `trigger` / `:descriptor` predicates filter incompatible library combinators in $O(|\Omega|)$ VM steps before `lift-frame`.
   - Verify that anti-unifying `:inverts` edges across `:map` instances induces a second-order `:functor` entry that automatically equips a newly synthesized `:map` function with its inverse `:solver` propagator and narrows pulled-back parent frames without a separate solver search.
4. **Test 4 — Cross-Call Continual Learning Curriculum (All Knowledge Types Working in Concert):**
   - Run a multi-call synthesis curriculum (`copy`, `inc-all`, `double-all`, `sum`, `length`, `product` $\to$ `consolidate-knowledge-library` $\to$ `add-len` $\to$ held-out transfer task) where laws, rewrites, higher-order combinators, descriptors, functorial solvers, DIP repair schemas, and search-trace priority predictors accumulate in `*knowledge-library*` and strictly reduce search work $W_{\mathrm{search}}$ on subsequent calls.

---

## 6. Module Impact Summary

- **No new kernel concepts outside the VM:** All knowledge representations (including bare relations, triggers, and functorial rules) use existing AST constructors (`var`, `lit`, `op`, `app`, `hole`) and execute through `evaluate` / `start-validated-evaluation` in `vm.lisp`.
- **Backward Compatibility:** All 147 existing tests continue to pass unchanged; `*function-definitions*` and `*registered-function-names*` remain synchronized with the active `*knowledge-library*`.
- **Files to Modify/Add:**
  - `ast.lisp`: `knowledge-entry`, `knowledge-library`, `*knowledge-library*`, `define-knowledge-kind`, generic lifecycle/indexing engine, `with-knowledge-library`, and registry synchronization.
  - `codec.lisp`: Generic `ast->sexp` / `sexp->ast` and `serialize-knowledge-library` / `deserialize-knowledge-library` / `save-knowledge-library` / `load-knowledge-library`.
  - `laws.lisp`: Declarative `:law`, `:solver`, `:functor` kind specs, `as-rewrite-library`, `as-propagator-library`, generalized function/relation inversion in `solve-learned-equality`, and functorial solver induction.
  - `factor.lisp` & `synthesize.lisp`: Declarative `:descriptor`, `:relation`, `:nogood-schema`, `:dip-feature`, `:heuristic` kind specs, `trigger` evaluation in `library-decompositions`, delayed residual condensation, and `consolidate-knowledge-library`.
  - `package.lisp`, `tests/run.lisp`, `tests/library.lisp`: Exports and comprehensive test suite.
