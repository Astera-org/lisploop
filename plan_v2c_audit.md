# Mathematical Audit & Verification of `plan_v2c.md`

*Living section-by-section validation against the root kernel (`df33ed1`), `v2/` (`a4e19fa`), the planning trail (`deprecated/plan.md` through `plan9.md`), sibling v2 proposals (`plan_v2.md`, `plan_v2b.md`, `plan_v2.tex`), the standalone prototype (`plan_v2c_audit/proto/tg-probe.lisp`), and the program-synthesis / coding-theory literature.*

---

## Section 1.3 — The Proposal (Cross-Referenced with §§4–8)

Section 1.3 compresses four distinct claims into five paragraphs: (1) a factored store `(Space, Column, Term, Class)`, (2) a single change-of-space description for the kernel's operations, (3) "geometry is description length," and (4) a single hole-refinement synthesizer backed by a standalone prototype (`tg-probe.lisp`). Below is the mathematical verification of each claim, its exact limitations, and where the formulation can be made cleaner and smaller.

---

### 1.3.1 What Data Structure §1.3 Actually Defines — and Why `plan_v2*` Proposed Different Ones

#### Exact mathematical interpretation of `(Space, Column, Term, Class)`

Evaluating an expression $t$ (a rooted, ordered DAG $\mathcal{P}(t)$) across $N$ independent contexts $S$ yields an execution hypergraph isomorphic to the Cartesian product:
$$\mathcal{G}_{\mathrm{exec}}(t, S) \;\cong\; \mathcal{P}(t) \times S.$$
Materializing $\mathcal{G}_{\mathrm{exec}}$ directly as a uniform $n$-way hypergraph (e.g., OpenCog/AtomSpace, or v1's `pullback-frame` in `frame.lisp:544-580` substituting concrete row literals `'x_w` into $N$ separate AST copies) discards that product structure and requires NP-complete conjunctive-query homomorphism ($\theta$-subsumption) to rediscover it (`deprecated/plan2.md:608-622`).

Storing the factors (`plan_v2c.md:42-48`, `§5.2`) constructs an **indexed deterministic bottom-up finite tree automaton (DFTA) — equivalently, a ground semantic e-graph or version-space algebra — fibered over $\mathbf{FinSet}$**:

1. **Base category ($\mathrm{Space}, \mathrm{Map}$):** Objects are finite sets of rows $S = \{0, \dots, |S|-1\}$. A column of row indices $m \in \mathrm{Col}(S', \mathrm{Row}(S))$ is a morphism $m : S' \to S$ in $\mathbf{FinSet}$ (or $\mathbf{FinSet}_\bot$ when boundary rows map to $\bot$ / `:err`).
2. **Data presheaf ($\mathrm{Column}$):** For value/status universe $V$, $\mathrm{Col}(S) = V^S$ is a contravariant functor: any map $m : S' \to S$ induces pullback (re-indexing) $m^* : V^S \to V^{S'}$ defined by $(m^* c)[r'] = c[m[r']]$.
3. **Syntax and observational quotient ($\mathrm{Term}, \mathrm{Class}$):** $\mathrm{Term}$ is the global hash-consed initial term DAG. On each space $S$, the evaluation homomorphism $[\![ - ]\!]_S : \mathrm{Term} \to V^S$ quotients terms by observational equivalence:
   $$t_1 \sim_S t_2 \;\Longleftrightarrow\; [\![ t_1 ]\!]_S = [\![ t_2 ]\!]_S.$$
   Its image $\mathrm{Class}(S) = \mathrm{Im}([\![ - ]\!]_S)$ **is** an $n$-way directed hypergraph: vertices are equivalence classes $C \in \mathrm{Class}(S)$ (keyed in $O(|S|)$ by their value column) and $(k+1)$-ary hyperedges $(C_1, \dots, C_k) \xrightarrow{\mathrm{op}} C_{\mathrm{out}}$ are pointwise operator transitions (Koppel 2021; ICDT 2025 DFTA $\cong$ e-graph identity).

#### Why `plan_v2.md`, `plan_v2b.md`, and `plan_v2.tex` proposed "newer" structures

The sibling v2 plans attempted to embed **intensional** equational equivalence ($\forall x.\, t_1(x) = t_2(x)$), **variable binders**, and **conditional assumptions** directly inside the store's equivalence relation. `plan_v2c` restricts the store's merge relation to **extensional** equality on concrete spaces $S$:

| Plan | Proposed Store | Relation to `plan_v2c` — and What Failed |
| :--- | :--- | :--- |
| `plan_v2.md` | Slotted Port-Hypergraph (`egglog` + Slotted + Colored e-graphs + `babble`) + ATMS semilattices + 256-D VSA/Sheaf | Co-de Bruijn thinning masks paired with first-occurrence slot order unsoundly equated $x_0 - x_1 \equiv x_1 - x_0$ (`plan_v2.tex:105`); AC saturation creates $2^n - 1$ classes ($3^n$ nodes); Colored `:if` worlds branch as $2^{|xs|}$ on `:filter`; VSA cannot compress pairwise computation ($\Omega(m \log m)$ parameters, Adler & Shavit 2024). |
| `plan_v2b.md` | Columnar **Attributed $\mathsf{C}$-Set** (bases + foreign-key maps + columns) + 6 edge kinds + Colored contexts | An Attributed $\mathsf{C}$-Set (Patterson et al. 2022) **is already** the `(Space, Map, Column)` core of `plan_v2c`. `plan_v2b` appeared more complex only because it added 6 separate edge types, Colored contexts, and a placeholder-oracle lift that evaluates `:if` truthily on `:filter` (`plan_v2.tex:311`). |
| `plan_v2.tex` (`v2.4`) | `cbase` arrays + injective `slot-map` Open-DAG + *law-activated AC flags* (`op-props`) + batch `mini-egraph` | Converged most of the way to `plan_v2c` after cutting VSA, sheaves, and Colored e-graphs. Remaining flaw: mutating canonical DAG construction when `op-props` dynamically enables `:assoc`/`:comm` invalidates previously interned IDs/caches and still misses multi-operator laws such as distributivity. |

**Validated trade-off and limitation:** `plan_v2c` isolates the intersection that survived all prior v2 passes (ACSet columnar spaces/maps + hash-consed terms + DFTA value-vector classes) and drops in-store equality saturation ($O(3^n) \to O(|S|)$). What this trades away is **cross-space schematic rewriting**: $\mathrm{Class}(S)$ merges terms only after evaluating them on $S$, so transferring algebraic equivalences to un-evaluated syntax or across spaces still requires an explicit normalizer or probe evaluation (and naive collision law sets grow $\times 2.8$ per size without converging; `plan_v2c.md:807`).

---

### 1.3.2 Validating the Unified-Operations Claim (§1.3 para. 2 & §5.3–5.4)

> *"build a space, give it a map to a space you have, and move columns along the map."*

Categorically, a map $m : S' \to S$ induces an adjoint triple $\Sigma_m \dashv m^* \dashv \Pi_m$ (Spivak 2012). Pullback $m^*$ covers container unnesting ($S' = \{(r, i) \mid 0 \le i < n_r\}$), guard sub-spaces ($\iota : S_g \hookrightarrow S$ injective), column projection ($q : S \twoheadrightarrow S/\!\sim$ surjective), and lags or self-calls ($s : S \rightharpoonup S$ partial endomap).

Cross-checking every operation named in §1.3 against the kernel and `tg-probe.lisp` exposes **three places where the telegraphic summary masks a mathematical gap**, each of which admits a cleaner formulation:

1. **Unifying `tabulate` and scalar `fold` via parameterized pushforward $m_{(e,\oplus)}$ (`plan_v2c.md:64, 444, 771`):**
   - *The gap:* `plan_v2c` states *"folds to a scalar need a `fold` form, since lifting alone cannot express them,"* and `tg-probe.lisp:472-495` treats `fold` as an ad-hoc generate-and-test over a single raw input list — failing (`NIL`) on two-sequence reductions like `seq-corr` ($\sum_i xs_i ys_i$).
   - *Why it happened:* `tg-probe` restricted pushforward `collect` (`tg-probe.lisp:264`) to the free list monoid (`list`). If pushforward along an ordered fiber map $m : S' \to S$ is parameterized by a fold algebra $(e, \oplus)$, then `tabulate` is $((), \mathrm{snoc})$ while scalar/tuple aggregation is $(0, +)$, $(1, \times)$, $(-\infty, \max)$, etc.
   - *Empirical check:* Adding an 8-line monoidal pushforward `reduce-pmap` along $m : S' \to S$ over $S' = \{(r,i) \mid i < \min(|xs_r|, |ys_r|)\}$ immediately solved `:spec/seq-corr` from its 7 kernel `:spec` rows (`(fold-space (min (len xs) (len ys)) + 0 (* (at xs i) (at ys i)))`, **200/200** on held-out).
   - *True mathematical boundary:* What genuinely cannot be decoupled by space maps alone is **unobserved non-homomorphic sequential state** (`foldl` with an unknown non-associative step $f$ when intermediate accumulators are absent from $S$), because $acc_i$ is a latent wire across fibers rather than an independent fiber evaluation.

2. **Anti-unification as an "instance space" (`plan_v2c.md:49, 446, 459`):**
   - *Correction 1 (Variable sharing is `Class` on the instance space):* §5.4 writes *"Constant columns are the shared pattern. Varying columns are the parameters."* That omits repeated variables: Plotkin–Reynolds LGG maps `(+ x x)` and `(+ y y)` to `(+ ?0 ?0)` (not `(+ ?0 ?1)`) precisely because the two varying subterm columns `[x, y]` and `[x, y]` **collide into the same `Class` on the instance space** (`unify.lisp:48-50`; Kahl 2019 categorical product in the category of substitutions).
   - *Correction 2 (Ragged spines and class cells):* Tree positions only form a rectangular space *along the shared top-down constructor spine* (diverging operators have incompatible arities). Moreover, §5.4's proposal that cells of the instance space hold **classes** rather than syntax (`plan_v2c.md:459`) breaks the single-spine table: a class has *multiple* operator decompositions, so anti-unifying classes requires **DFTA product intersection** (`babble`, quadratic in corpus size and returning a set/DAG of generalizations), not constant-column detection.

3. **Inverses "read off an operator's own table" (`plan_v2c.md:49, 417-420, 795`):**
   - *The gap:* In §8.2 (`plan_v2c.md:795`), `tg-probe` misses the integer divisibility guard for `*`, and the plan concludes: *"every row of a product table is divisible, so the table alone cannot show it."*
   - *Clean mathematical resolution:* Inverting $c = f(a, b)$ for $a$ decomposes into two orthogonal fiber conditions (`plan7/plan7.md:379-383`):
     - **Uniqueness on the image** ($|F_{b,c}| \le 1$ given $(b, c) \in \mathrm{Im}(f)$): tested directly by `group-by` functional dependency on the forward table, yielding $G_{\mathrm{uniq}}(b, c) = (b \ne 0)$ and witness $w(b, c) = \lfloor c/b \rfloor$.
     - **Existence / image membership** ($|F_{b,c}| \ge 1$ on arbitrary $(b, c)$): requires **zero search**. Given $w(b, c)$, $(b, c) \in \mathrm{Im}(f)$ holds iff $w(b, c)$ is defined and $f(w(b, c), b) = c$ (`consolidate.lisp:1466-1479`; `plan_v2.tex:759`).
   - *Empirical check:* Conjoining `tg-probe`'s forward-table uniqueness guard with totalized forward replay, `(and (not (= b 0)) (= (* (div c b) b) c))`, gave **0 errors across all $1,681$ pairs in $[-20, 20]^2$**. Conversely, for `div(a, b) = c` solving for $b$, integer floor/truncating division is genuinely non-injective on its image ($\lfloor 10/4 \rfloor = \lfloor 10/5 \rfloor = 2$), so only a *section* exists unless guarded by $|a| < c(c+1)$ — showing that `:spec/solve-/-1` in `bootstrap/build-batteries.lisp:233-239` appeared unique only because its 3 positive rows were hand-chosen exact multiples.

---

### 1.3.3 Why "Geometry is Description Length" (§1.3 para. 3 & §6) Is Non-Intuitive — Validated Against `codec.lisp` and `frame.lisp`

Testing `correction-bit-size` (`frame.lisp:1533-1582`) and Elias-$\delta$ coding (`codec.lisp:39-44`) directly in SBCL explains why this slogan feels counter-intuitive and pinpoints one live coding-theory defect:

1. **It is a Lawvere quasi-metric (oriented metric), not a Euclidean or Riemannian space:**
   - **Directed triangle inequality holds:** Exhaustive checks across sample grids in `:int`, `(:gf 5)`, `(:seq :int)`, and `:code` found **0 violations** of $d(u \to w) \le d(u \to v) + d(v \to w)$.
   - **Concave & non-inner-product on `:int`:** In `codec.lisp:39-44`, positive integer $n$ takes $E_\delta(n) = w(n) + 2\ell(n) - 2$ bits ($w(n) = \lfloor\log_2 n\rfloor + 1$, $\ell(n) = \lfloor\log_2 w(n)\rfloor + 1$). Under `signed-code` ($0 \mapsto 1$, $k > 0 \mapsto 2k+1$, $-k \mapsto 2k$), $2k$ ends in bit $0$, so $w(2k) = w(2k+1)$ for every $k \ge 1$. Thus $d_{\mathrm{int}}(u, v) = E_\delta(\mathrm{sc}(v - u))$ is **provably symmetric and subadditive**, **but logarithmic/concave** ($0, 4, 5, 5, 8, \dots, 17$ bits at $|\Delta| = 0, 1, 2, 3, 4, \dots, 1000$). Unlike $L_2^2$, a concave logarithmic metric has no inner products, angles, or convex barycenters, and favors sparse exact hits ($L_0$-like) over spread-out small errors — matching Plan 1's finding that true lifts ranked 66th of 2,661 by raw residual magnitude.
   - **Strictly asymmetric on `:seq` and `:code`:** Measured in SBCL, $d(\texttt{()} \to \texttt{(1 2)}) = 13$ bits vs. $d(\texttt{(1 2)} \to \texttt{()}) = 1$ bit; $d(x_0 \to x_0 + 1) = 15$ bits vs. $d(x_0 + 1 \to x_0) = 3$ bits. Because projection destroys fiber bits ($H(X) = H(f(X)) + \mathbb{E}\log_2|\text{fiber}|$), erasing structure is cheap while lifting/synthesizing pays for the missing subterms. This is a Lawvere $[0,\infty]$-enriched metric, matching *Oriented Metrics for Bottom-Up Enumerative Synthesis* (Meyer & Tepe, POPL 2026).

2. **Live Kraft-inequality violation in `frame.lisp:1581` (Metric $d(u,u)=0$ vs. Prefix Code):**
   - To enforce the metric axiom $d(u \to u) = 0$, `frame.lisp:1581` overrides `(if (equal predicted target) 0 bits)` per cell while leaving non-zero deltas at their full prefix lengths.
   - Measured conditional Kraft sums $\sum_v 2^{-d(u \to v)}$ in SBCL therefore **exceed 1** (violating prefix-freeness):

     | Type | Conditional distances from $u$ | Measured $\sum_v 2^{-d(u \to v)}$ | Valid prefix code ($\le 1$)? |
     | :--- | :--- | :---: | :---: |
     | `:bool` ($u = \mathrm{T}$) | $d(\mathrm{T}\to\mathrm{T})=0,\; d(\mathrm{T}\to\mathrm{NIL})=1$ | **$1.5000$** | **No** |
     | `(:gf 5)` ($u = 3$) | $(5, 5, 4, 0, 4)$ bits (vs. $3$-bit replacement) | **$1.1875$** | **No** |
     | `:int` ($u = 0, |v|\le 1000$) | $0$ at $0$; $4, 4, 5, 5, 5, 5, 8\dots$ (plain `value-bit-size`: $0.9059$) | **$1.4059$** | **No** |

   - *Clean fix:* Pay **1 bit once per column** to distinguish an exact zero-residual column ($r \equiv 0$) from a non-exact residual column; inside a non-exact column, code every cell with a true prefix distribution ($\sum_v 2^{-L(v|u)} \le 1$, charging $\ge 1$ bit on equal cells just as tuple/sequence `parts` already does at `frame.lisp:1550`).

3. **Two distinct layers are conflated under "Geometry" in §1.3:**
   - **Exact Pricing Geometry (§6.1–6.2):** Total MDL $\sum_{\text{derived}} L(t_j) + \sum_{\text{free}} L(c_i \mid \mathrm{pa}(c_i))$ is shortest directed hyperpath length in the store.
   - **Heuristic Retrieval Index (§6.3):** Boolean property signatures, operator counts, and graph random walks (PPR) are *not* conditional description lengths between columns; they compensate for the ruggedness of program space (where a 1-bit literal edit `mod x 2` $\to$ `mod x 3` causes maximal behavioral distance). Naming these separately avoids forcing one word to mean both exact coding and feature similarity.

---

### 1.3.4 Double-Checking the Sufficiency Prototype (`tg-probe.lisp`)

`tg-probe.lisp` (874 LOC) was tested only on its author's 12 random examples per task (31–51 lifted rows), explicitly leaving the kernel's actual `:spec` rows in `bootstrap/build-batteries.lisp` untested (`plan_v2c_audit/reports/proto.md:397`). Running `tg-probe` directly on the **actual kernel `:spec` rows** (verified on 200 fresh held-out inputs up to length 12) produced a sharp split:

| Kernel `:spec` (`build-batteries.lisp`) | Spec / Lifted Rows | `tg-probe` Default | Held-Out | Verification Finding |
| :--- | :---: | :--- | :---: | :--- |
| `copy`, `inc-all`, `dbl-all`, `positions` | 4–11 (`6–10`) | Exact `tabulate` | **200/200** | Solved in 0–4 ms (`3`–`8,607` candidates). |
| `scan` (`:code` arg), `shift-seq` | 9 (`9`), 13 (`27`) | Exact `tabulate` + 1 guard | **200/200** | Solved in 4 ms (`11,298` and `8,781` candidates). |
| `filter` (with unary `:bool` call added) | 7 (`9`) | `(select xs (call1b p x))` | **200/200** | Proto only included binary `:int` `call`; solves in 0 ms (`1,383` cands) once unary `:bool` call is added. |
| `sum-all`, `len-all`, `prd-all`, `last-or` | 4–7 | Exact via `fold` | **200/200** | Unlifted `solve-scalar` overfits 4-row specs (`20–23/200`); `fold` gets `200/200`. |
| **`map-adjacent` (`:spec`, `:code` arg)** | **8 (`6`)** | **Size-19 `if`-split impostor** | **29/200** | **With `*occam* = t`: exact size-10 answer (`200/200`) in 64 ms (`616,232` cands).** |
| **`foldl` (`:spec`, `:code` arg)** | **9** | `(fold a (- acc x) xs)` | **81/200** | Spec only supplies `f = -`; `(- acc x)` (size 3) beats `(call f acc x)` (size 4). |
| **`seq-corr`, `best-shift`, `argmax-corr`** | **7, 9, 3** | **`NIL` (unsolvable)** | **0/200** | Lacks fiber-fold (`seq-corr` $\to$ **200/200** once added), tuples, and 2-lift composition. |

**Validated limits of the prototype test:**

1. **`plan_v2c.md:769` misjudged `*occam*` (size-consistent split acceptance):** On 31–51 random rows, greedy first-fit splits happened not to overfit at size 7. On `:spec/map-adjacent`'s actual 6 lifted rows, `solve-col` (`tg-probe.lisp:409`) greedily accepts a size-19 `if`-split impostor (`29/200`) at level 7 before reaching the unsplit size-10 solution; enabling `*occam* = t` solves it **200/200 in 64 ms**. Guard splits must never jump ahead of global MDL size ordering.
2. **The prototype validates the *store*, not the *general synthesizer* (§1.3 para. 4 / §7.2):** `solve-task` (`tg-probe.lisp:504-508`) is a fixed 1-level host waterfall (`or solve-tabulate solve-select`) with three pieces of host scaffolding wired in: lag column `prev = ys[i-1]` added to every `tabulate` (`:430`), greedy host subsequence alignment `align` (`:436`), and pre-built `(len xs)` leaves (`:339`). Multi-step hole refinement (`best-shift`), requirements with holes (§5.6), instance-space AU, and derivation space (§7.4) are unimplemented in `tg-probe`.
3. **Underdetermined higher-order specs (`foldl`) confirm §5.5's ambiguity check is required:** Whenever distinct classes on a wider probe space collapse to the same column on task space $S$, returning the smallest representative without probing or reporting ambiguity yields the same `(- acc x)` impostor seen in `v2/STAGE0_RESULTS.md`.

---

### 1.3.5 Four Elegance-Biased Refinements for §1.3

1. **Unify `tabulate` and `fold` as parameterized pushforward $m_{(e,\oplus)}$ along $m : S' \to S$:** Pullback $m^*$ moves context down; pushforward $m_{(e,\oplus)}$ aggregates fibers up (free sequence monoid for `tabulate`, binary step/monoid for `fold`, `seq-corr`, and `argmax`/`best-shift`), enabling nested lifts to compose without special cases.
2. **Keep `if` and hole refinements inside one global MDL queue:** Eliminate greedy post-level `cover` passes; rank unsplit terms and conditional splits in the same exact description-length order (with 1 exactness bit per column so conditional codes strictly satisfy Kraft's inequality).
3. **Factor inversion into Forward-Table Uniqueness + Zero-Search Forward-Replay Existence:** Let search find only witness $w$ and uniqueness guard $G_{\mathrm{uniq}}$ via `group-by` on the operator's forward table, and obtain image membership automatically from totalized replay $f(w, \dots) = c$.
4. **State the two geometries cleanly:** Reserve *"description length"* for the exact **MDL pricing quasi-metric** (two-part code on the store's DAG), and treat **flat signature vectors + counts** explicitly as a lightweight **retrieval/ranking index** over that exact store (upgraded to compositional quotient algebras in §2 below).

---

## Section 2 — Language, Heuristics, Signatures, and Cheap Reflection (Cross-Referenced with §§6.3, 6.6, 7.4, 8.4 & Appendix E)

`plan_v2c.md` explicitly elides the language arm (`§6.6`: *"builds almost nothing for it"*) and treats heuristics as a flat layer (`§6.3`: static Boolean property signatures feeding Naive Bayes counts). Both choices share a single cause — and reversing that perspective unlocks several bottlenecks elsewhere in the plan (library scaling / Minton's utility problem, cold-start library reuse, the arithmetic RAM wall in `§8.4`, conditional-law guard search in `§5.5`, and cross-job reflection in `§7.4`) **without adding new core store primitives**.

---

### 2.1 Diagnosis: What `plan_v2c`'s Literature Audit Missed — and the Thread Already in `prompt4.md`

In [plan_v2c.md](file:///home/tlh24/lisploop/plan_v2c.md) (`§6.3`, `§6.6`, `Appendix E`), the literature review surveyed only *flat* or neural feature approaches (BUSTLE property signatures $\to$ MLP, Probe within-task grammar reweighting, LAPS fragment alignment on a neural synthesizer). Under a flat feature view:

1. **Signatures cannot compose:** Evaluating predicates only at the task boundary `(input, output)` gives no algebraic way to chain properties across a multi-step pipeline such as `sum(filter_pos(map_adj_add(xs)))`.
2. **Flat counts fail cold-start on a growing library:** Naive Bayes needs solved training traces to score an operator; every newly discovered library function enters with zero counts and gets pushed to the back of the search queue (making library growth *hurt* search).
3. **Flat features yield no admissible lower bounds:** They can reorder candidates, never prune unreachable concrete classes before storing them in RAM (`§8.4`).

Yet the planning trail (`prompt4.md:197-203`) already stated the exact mathematical relation uniting language and heuristics:

> *"A language enables compositional description of the labeled computation, in a form that is shorter and cheaper than executing the function / rule / algorithm itself. Thus it is a form of heuristic."*  
> *"True compositional addressing requires variable compute when decoding the address."*

There is a rigorous, non-neural, shipped/replicated literature lineage implementing this principle that `Appendix E` omitted:

- **Abstract-interpretation-guided synthesis (Abstract Finite Tree Automata / AFTAs):** **Blaze** (Wang, Dillig, Singh, POPL 2018 — CEGAR over AFTAs), **Simba** (Yoon, Lee, Yi, PLDI 2023 — iterative forward–backward abstract interpretation in bottom-up SyGuS: 519/544 bitvector tasks vs. Duet 456 and Probe 409), **Absynthe** (Guria, Foster, Van Horn, PLDI 2023 — language-agnostic abstract synthesis scaling to Pandas and Ruby libraries), and **Atlas / Amurth** (Wang et al., CAV 2018; Kalita et al., OOPSLA 2022 — automatic synthesis of abstract domains and most-precise transformers).
- **Factored homomorphic planning abstractions & hypergraph shortest paths:** **Merge-and-Shrink** (Helmert, Haslum, Hoffmann, Nissim, JACM 2014) and **Knuth (1977)** (*A Generalization of Dijkstra's Algorithm* — exact minimum-cost derivation in weighted directed hypergraphs).
- **Algebraic congruence / lumpability & Formal Concept Analysis (FCA):** Quotient algebras / bisimulation / causal states (Crutchfield & Shalizi) and Galois implication lattices (Ganter & Wille).

---

### 2.2 The Unifying Object: Learned Factored Quotient Algebras (Abstract DFTAs) {#sec-2-2}

*(For a plain-English walkthrough of this section with a worked example and a math-to-English glossary, see [Appendix A](#appendix-a).)*

In the categorical formulation of §1.3, a flat signature is a family of small finite quotient maps $\alpha_j : V \to \mathcal{A}_j$ evaluated only at the problem's inputs and target. Turning that flat signature simultaneously into a **compositional language**, **admissible pruner**, **soft MDL planner**, **library index**, and **reflection key** requires one functorial move:

> **Push every library operator $f$ forward along $\alpha_j$ via `group-by` on $f$'s existing probe table.**

By abstract interpretation (Cousot & Cousot 1979), a Galois connection $\alpha_j : \mathcal{P}(V) \rightleftarrows \mathcal{A}_j : \gamma_j$ induces the best abstract transformer $f^{\sharp_j}(\vec{a}) = \alpha_j\bigl(f(\gamma_j(\vec{a}))\bigr)$. On `plan_v2c`'s store, **$f^{\sharp_j}$ is never hand-written**: `§7.5` already evaluates each operator $f$ on a standard probe space $S_{\mathrm{probe}}$ (for laws, inverses, and definedness). One `group-by` mapping $(\alpha_j(x_1), \dots, \alpha_j(x_k)) \mapsto \alpha_j(f(\vec{x}))$ produces an ordinary small table in the store carrying two coupled views:

1. **Empirical support relation** $f^{\sharp_j} : \mathcal{A}_j^k \to \mathcal{P}(\mathcal{A}_j)$: an AFTA transition table. Any reachable abstract input not observed during probing defaults to $\top$ (all abstract outputs of the result type), never $\emptyset$. *Soundness caveat (confirmed by `plan_v2c.md §8.8`):* defaulting unseen inputs to $\top$ does **not** cover a *seen* input bucket whose rare output label was absent from the probe sample (e.g., `take3` on a non-increasing list whose first 3 elements happen to be equal). Sampled verb tables are therefore strictly **tested knowledge** (`§5.5`): safe for operator ordering or for filtering a tentative first pass backed by fallback, never for certified elimination.
2. **Fiber-surprise / MDL weight**, extending `§6.2` rule 2 ($H(X) = H(f(X)) + \mathbb{E}\log_2|\text{fiber}|$) directly to the quotient algebra:
   $$w_j(f; \vec{a} \to a_{\mathrm{out}}) \;=\; L(f) - \log_2 P_j(a_{\mathrm{out}} \mid f, \vec{a}).$$
   Exact algebraic congruences ($P_j = 1$) incur **0 surprise bits**; loose or non-informative transitions pay real conditional entropy bits.

Every language, heuristic, and reflection construct reduces to an operation on this single table:

| Concept | Exact Definition in the Quotient Store |
| :--- | :--- |
| **Word (noun)** | An abstract quotient value $a \in \mathcal{A}_j$, where $\alpha_j$ is a small unary `Term` selected automatically by **algebraic lumpability** $\mathrm{Lump}(\alpha; f) = 1 - H(\alpha(f(\vec{x})) \mid \alpha(\vec{x})) / H(\alpha(f(\vec{x})))$ (deduplicated by canonical partition up to bijective relabeling and ranked by MDL size), seeded by VM fault guards (`x=0`, `len=0`) and refined by CEGAR splits. |
| **Verb (`'action'`)** | The pushed-forward transition table $f^{\sharp_j}$ (including space-building lifts). Populated in $O(|S_{\mathrm{probe}}|)$ the moment $f$ enters the library — **zero training traces needed**. |
| **Compositional decode** (`prompt4.md:197`) | Running **Knuth's (1977) shortest-hyperpath DP** on the tiny finite AFTA ($|\mathcal{A}_j| \approx 2\text{–}44$) to compute forward reachability $g_{\mathrm{fwd}}$, backward lower bounds $h_{\mathrm{bwd}}$ (pruning unreachable concrete classes before RAM insertion), and minimum-MDL abstract paths in milliseconds. |
| **`'like'` word** | On problems: shared universal (all-row) abstract invariants. On operators: Jaccard overlap of learned transition tables $f^{\sharp_j} \approx g^{\sharp_j}$ (automatic **verb-class synonyms**, zero hand labels). |
| **`'analogy'` word** | The same abstract verb class / commutative square relating two `(input, output)` pairs (not vector offsets). |

---

### 2.3 Empirical Validation (and Honest Failure Boundaries) {#sec-2-3}

Preliminary Python experiments (five suites covering word discovery, 61-function library scaling, arithmetic RAM walls on `G1`/`G2`, conditional-law guard posets, and cross-job reflection) test each claim and expose its exact algebraic boundaries.

#### 1. Automatic Word Discovery via Partition-Canonical Lumpability
- Deduplicating candidate unary predicates by their **canonical equivalence partition** (invariant to bijective relabeling) and keeping the shortest-MDL term immediately collapsed junk bijections (`(3x+1) mod 4` $\to$ `x mod 4`; `1 - (x mod 2)` $\to$ `x mod 2`).
- **Integer arithmetic (`{+, -, *, neg, max, min, div, mod}`):** Lumpability automatically surfaced exact algebraic quotients and sign — `mod_5` (`0.888` ring lumpability, 4 exact ops), `mod_4` (`0.876`), `mod_3` (`0.860`), `parity` (`0.833`), and `sign` (`0.830` ring, **highest overall `0.772`** across all 8 ops including `div` and `max`) — while arbitrary predicates (`eq_1`, `even_or_neg`, `abs_lt2`) fell to `0.30–0.48`.
- **Sequence algebra (15 ops):** Top automatically discovered quotients were `len_cap5` (`0.857`, 9/15 exact), `len_mod2` (`0.817`, 10/15 exact), `all_even` (`0.688`), and `is_empty` (`0.673`); distractors (`head_eq_2`, `sum_gt_5`) fell to `0.24–0.49`.

#### 2. 61-Function Library Scaling, Cold-Start Utility, and Merge-and-Shrink
One-time `group-by` learning of 6 quotients $\times$ 61 typed sequence/scalar ops took **161 ms** (zero training tasks). Plain bottom-up OE was compared against Flat Signature + Naive Bayes (`plan_v2c §6.3`, trained on 80 solved tasks *holding out* two cold-start ops, `map_adj_sub` and `dbl_all`), Sound Factored Abstract DFTA (`h_bwd`), `+SoftMDL` operator ranking (`w_j`, zero training traces), and a 44-state **Merge-and-Shrink** product quotient (`nonneg` $\times$ `parity` $\times$ `order`, learned in 275 ms):

| Task (61-op library) | Plain OE (RAM) | Flat NB | AbsDFTA + SoftMDL (RAM) | Merged-MS RAM | Best Gain |
| :--- | --: | --: | --: | --: | --: |
| `T1 [COLD]: sum(map_adj_sub(sort(xs)))` | 83,926 (1,561) | 7,864 | **8,963** (1,383) | — | **9.4$\times$** |
| `T3: sum(zip_mul(xs, shift1(xs)))` | 2,253 (1,401) | 618 | **85** (**51**) | — | **26.5$\times$** |
| `T4: sum(filter_pos(zip_sub(xs, ys)))` | 285,098 (4,057) | 51,097 | **22,270** (3,659) | — | **12.8$\times$** |
| `T5: len(filter_even(map_adj_add(xs)))` | 2,579 (1,546) | 381 | **164** (**51**) | — | **15.7$\times$** |
| `T6: running_sum(reverse(inc_all(xs)))` | 37,233 (1,561) | 33,371 | 23,482 (601)* | **174** (5,653 cands) | **6.6$\times$** (9.0$\times$ RAM) |
| `T8 [COLD]: dbl_all(sort(abs_all(xs)))` | 4,167 (1,561) | **27,067 (6.5$\times$ worse)** | **2,303** (601) | **253** (2,479 cands) | **1.8$\times$** (**11.8$\times$ vs NB**) |
| `T9 [4-op]: sort(dbl(filter_pos(adj_add)))` | 12,440 (8,563) | 3,248 | **3,524** (**2,269**) | **3,367** | **3.5$\times$** (3.8$\times$ RAM) |
| `T10 [4-op]: dbl(sort(abs(adj_sub)))` | 145,929 (48,489) | — | 112,656 (26,903)* | **11,480** | **1.5$\times$** (**4.2$\times$ RAM**) |

*(Erratum vs. earlier draft, caught by `plan_v2c.md §8.8`: the previous table mistakenly paired `+SoftMDL` candidate counts on `T3`/`T5`/`T9` with the unordered `AbsDFTA` RAM counts `812`/`1,383`/`6,048`; corrected above to exact matched `m_st` values. Starred `T6` unordered `AbsDFTA` was `16,755 (601)` and `T10` is unordered `AbsDFTA`.)*

- **Tested, not sound:** Zero misses occurred on these 8 tasks, but `plan_v2c.md §8.8`'s 300-task reproduction showed **11% lost answers** at 100 random probes, **0.3%** at 1,000–3,000 random probes (0 at 10,000 random or 1,000 edge-stratified probes), and **8% lost** for the merged 3-quotient product at 3,000 probes — almost entirely from *seen* input buckets producing an unsampled rare output bucket. Verb tables therefore belong strictly in tentative-first + fallback or pure ordering.
- **Cold-start contrast:** On `T8`, Flat NB degraded search **6.5$\times$ worse** than plain OE because `dbl_all` had zero training counts; `AbsDFTA+SoftMDL` beat Flat NB by **11.8$\times$** with zero solved traces.
- **Honest limitation (why Merge-and-Shrink & CEGAR are needed):** Independent 1-domain-at-a-time bounds miss *additive subgoal interactions* ($\max(1,1,1)=1 < 1+1+1=3$). Merging `(nonneg` $\times$ `parity` $\times$ `order)` cut peak RAM **4.2$\times$–9.0$\times$**. Even then, `filter_pos` survived pruning on `T8` because `len_sign` alone sees `len=4` without knowing the input contains negatives (on all-positive inputs `filter_pos` preserves length). Eliminating that slack requires either a coupled product state `(len, sign)` or **Blaze-style CEGAR refinement** on demand rather than a fixed static menu of quotients.

#### 3. Arithmetic RAM Wall (`§8.4`): Per-Row Failure vs. Column-Vector Homomorphisms (`G1` vs. `G2`)
- **Honest negative (per-row quotients):** Applying per-row `mod2`/`mod3`/`mod5`/`sign` to `G1 = {+, -, *, neg}` yielded only **1.0$\times$–1.2$\times$** pruning. On a *single* row, every residue in $\mathbb{Z}/p\mathbb{Z}$ is reachable in 1 step from $\{0, 1, x, y\}$, collapsing $h_{\mathrm{bwd}} \le 1$.
- **Column-vector breakthrough:** Lifting $\pi_p$ to the **column homomorphism** $\mathbb{Z}^N \to \mathbb{F}_p^k$ ($\mathbb{F}_2^{12}$ has at most $2^{2^2} = 16$ reachable 2-variable polynomial functions ever; $\mathbb{F}_3^4 \le 81$ states; $\mathbb{F}_5^3 \le 125$ states) is **100% certified exact** on `G1`. Pairing exact $h_{\mathrm{bwd}}$ RAM pruning with an **$O(1)$ quotient hash-join** on the final layer (`a2 = tgt - a1 mod 5`, `a2_2 = tgt_2 ^ a1_2`) dramatically compresses RAM even on unstructured random polynomials:

| `G1 = {+, -, *, neg}` Target | Plain OE cands (RAM, ms) | ColHom+Join cands (RAM, search / tot ms) | Cand Gain | **RAM Gain** |
| :--- | --: | --: | --: | --: |
| `A2 (sz7): (x+x)*(y+1)` | 1,898 (99, 1.5) | 59 (**5**, 0.2 / 12.7) | **32.2$\times$** | **19.8$\times$** |
| `A3 (sz7): x*y + x - y` [unconstr] | 492 (99, 0.4) | 108 (**12**, 0.2 / 9.9) | **4.6$\times$** | **8.2$\times$** |
| `A4 (sz9): (x+y)*(x-y) + 1` [unconstr] | 4,192 (490, 3.7) | 1,489 (**52**, 3.7 / 49.0) | **2.8$\times$** | **9.4$\times$** |
| `A8 (sz11): (x+y)^2 - x*y + 1` | 24,912 (2,713, 22.1) | 7,685 (**120**, 12.0 / 98.0) | **3.2$\times$** | **22.6$\times$** |
| `A11 (sz13): (x*y + x + 1)*(y - x)` | 61,840 (12,801, 61.6) | 42,368 (**1,255**, 59.1 / 207.2) | **1.5$\times$** | **10.2$\times$** |
| `A12 (sz13): 2*(x^2 + y^2) - x*y` | 403,822 (15,760, 357.8) | 54,686 (**687**, **70.6** / **209.9**) | **7.4$\times$** | **22.9$\times$** (**1.7$\times$ wall**) |

*(The finite-ring DP cost is $O(1)$ in concrete depth — bounded by $\le 125$ states, ~90–140 ms in Python and $<2\text{ ms}$ in compiled SBCL — so wall time already crosses over at size 13 and scales directly against `§8.4`'s 24 GB wall.)*

- **Honest hard boundary (`G2 = G1` $\cup$ `{div, mod, max, min}`):** Once integer `div` and `mod` enter the grammar, modular arithmetic is no longer a homomorphism (`lump(mod2; div) = 0.05`, `lump(mod3; div) = 0.06`). Consequently, $\mathbb{F}_p$ column pruning is **sound only on the ring sub-algebra `G1`** (usable as a cheap tentative-first ring pass under `plan_v2c`'s reserve scheduler, or inside pure-ring subproblems), while `sign` (`1.00` on `*, max, min`; `0.69` on `div`) and intervals survive only partially.

#### 4. Conditional Laws / Chompy Bottleneck via FCA Bitset Poset (`§5.5`)
In `plan_v2c`, every Boolean guard column is already a bitmask over rows. For a candidate conditional law with agreement mask $A$, a guard $g$ is valid iff $(g \mathbin{\&} \neg A) = 0$, and $g_1$ implies $g_2$ iff $(g_1 \mathbin{\&} g_2) = g_1$. Restricting to poset maximals below a single mask $A$ avoids full $\#\mathrm{P}$-hard Duquenne–Guigues closure:

- Across 439 distinct non-trivial guard classes (32 rows), bitset maximal-element filtering collapsed **26–127 valid guards $\to$ 1 unique weakest guard** on all 6 tested laws (`max(a,b)=a` $\to$ `(<= b a)`, `div(a*b,b)=a` $\to$ `b != 0`, `abs(a+b)=abs(a)+abs(b)` $\to$ `(<= 0 (* a b))`, etc.) in **0.40 ms total**.

#### 5. Cheap Reflection on the Derivation Space (`§7.4`)
On 20 sequential 3-op tasks over the 61-op library with **completely disjoint concrete input tables** (`0/20` concrete memo hits):

- **Automatic verb-class synonyms** (Jaccard overlap on learned $f^{\sharp_j}$, zero hand labels) recovered semantic families directly from probe tables: `map_adj_sub` $\approx$ `map_adj_mul (0.61), map_adj_add (0.61), map_adj_min (0.53), map_adj_max (0.53)`; `filter_pos` $\approx$ `filter_neg (0.57), filter_odd (0.45), filter_even (0.41)`; `zip_add` $\approx$ `zip_sub (0.74), zip_max (0.69), zip_min (0.68), zip_mul (0.66)` (`concat`: `0.07`); `sum` $\approx$ `head (0.61), last (0.51), min_el (0.47), max_el (0.43)`.
- Indexing the Derivation Space by **universal (all-row) abstract invariants** yielded **5/5** exact cross-job replays ($\le 5$ candidates each) plus **6/20** sibling-family transfers via verb-synonym expansion (**11/20 total hits**), reducing total candidates **2.16$\times$–2.34$\times$ on top of Abstract DFTA** (**2.57$\times$–2.78$\times$** vs. Plain OE, zero misses).
- **Honest engineering caveat:** Noisy per-row `frozenset` signatures missed repeats (`1/20`) until replaced with all-quantified universal invariants; and exact replay ($\le 5$ cands) + soft neighbor-first operator ordering (`245k` cands) slightly outperformed hard sub-grammar caps (`266k`) because misses paid no sub-grammar fallback tax.

---

### 2.4 Lean Integration Hooks for `plan_v2c.md` (Zero Bloat)

Stages A and B do **not** require building a full language subsystem upfront. Keeping the architecture open to all of §2.2–§2.3 requires only three small, zero-bloat adjustments when revising `plan_v2c.md`:

1. **Unify §6.3 (Signatures) and §6.6 (Language) via Quotient Algebras:** Define a *word* as a small unary quotient `Term` $\alpha_j : V \to \mathcal{A}_j$ (or column projection $V^k \to \mathcal{A}_j$) selected by partition-canonical MDL + lumpability (plus fault guards and CEGAR splits), and a *verb* as its pushed-forward `group-by` table $f^{\sharp_j}$ (support + empirical counts) on $f$'s existing `§7.5` probe space.
2. **Upgrade Gate X4 (`plan_v2c.md:944`):** On the 30+ distractor library benchmark (explicitly including held-out cold-start library functions), compare (i) types only, (ii) flat signatures + Naive Bayes, and (iii) pushed-forward quotient tables (`h_bwd` + soft MDL). This directly tests whether compositional abstract semantics clears the cold-start utility wall where flat counts fail.
3. **Add one column to the Derivation Space (`§7.4`):** Record each problem's **universal abstract invariant signature** alongside its concrete `(space, requirement, context)` key, enabling cheap cross-job replay ($\le 5$ candidates) and verb-synonym warm-starting across disjoint concrete spaces without altering the exact concrete memo contract. *(Note: `plan_v2c.md §7.4` / `§8.8` currently adopts plain replay first while libraries are small and defers indexing until replay cost grows.)*

---

### 2.5 Unified Design Spec & Prescriptions for `plan_v2c.md` {#sec-2-5}

*(For a plain-English walkthrough of both §2.2 and §2.5, see [Appendix A](#appendix-a). For the historical process, errata, and probe ablations that trimmed these rules down to what follows, see [Appendix B](#appendix-b).)*

This section condenses the reconciliation of quotients, residuals, memory accounting, and kernel experiments into one clean descriptive and prescriptive specification ready to fold into `plan_v2c.md` (`§§6.1–6.6, 7.2, 7.5, 8.4, 11.2`).

#### 2.5.1 One Unified Primitive and Two-Timescale Reentrancy
Bucketing, computed residuals, heuristics, and vocabulary all reduce to **one store primitive** — `group-by` conditional entropy / residual length $L(q(B) \mid q(A))$ on a `Space` $S$ — varying only in whether projection $q$ is the identity ($q = \mathrm{id}$) or a small-codomain quotient ($q \ne \mathrm{id}$):

| Regime | Projection $q$ | Residual $H(q(B) \mid q(A))$ | Store Artifact Produced |
| :--- | :---: | :---: | :--- |
| **Exact law / strict conservation** | $q = \mathrm{id}$ (or endomap $s^*c = c$) | $0$ | Class collision (`t1 = t2`), invariant (`§5.3`) |
| **Exact reorientation (inverse)** | $q = \mathrm{id}$, $A=(b,c), B=a$ | $0$ (on $S_g$) | Witness + uniqueness guard (`§5.3`, `§8.2`) |
| **Computed residual heuristic** | $q = \mathrm{id}$, $A=U, B=Y$ | $>0$ (small $L(R)$) | `(decode U ?R)` or `(if ?g U ?else)` (`§6.1–6.3`) |
| **Exact congruence / homomorphism** | $q \ne \mathrm{id}$ | $0$ | Exact verb table; certified $\mathbb{F}_p^k$ column pruning |
| **Soft conservation / verb table** | $q \ne \mathrm{id}$ | $0 < H_{\mathrm{cond}} \ll H_{\mathrm{out}}$ | Tested verb table (ordering + tentative filter) |

**Two-timescale reentrancy (no nested meta-search):** Keep reentrancy strictly in the **store representation** (`§4.6`), never inside the inner enumeration loop:

- **Offline agenda (`§7.5`):** Runs this single `group-by` / reorientation primitive over probe spaces and the Derivation Space to produce laws, inverses, words $q$, and verb tables $f^\sharp$.
- **Online solver (`§7.2`):** Reads those precomputed tables via $O(1)$ lookups.

*Mathematical scope:* Quotient algebras are finite-alphabet universal-algebraic / lumpable-automaton quotients (discrete Koopman observables) — strictly generalizing discrete Fourier characters on abelian rings (`x mod p`, $\mathbb{Z}^N \to \mathbb{F}_p^k$) and oriented projective quotients (`sign`: $\mathbb{Z}/\mathbb{R}_{>0}$) to non-group container algebras (`sort`, `filter`, `len`) whose overlapping partitions live in the equivalence lattice $\mathrm{Eq}(V)$ rather than an orthonormal vector basis ([Appendix B.3](#appendix-b)). Two-label quotients are identical to Boolean guards (`§5.5`), but word discovery **must retain small finite codomains (`Card <= 6–8`)** because collapsing multi-way congruences to `Bool` destroys additive closure (`x mod 3` drops from lumpability `1.00` to `0.55` as `(x mod 3 == 0)`; [Appendix B.2](#appendix-b)).

#### 2.5.2 Four-Stage Online Handoff: Quotient Heuristics, Computed Residuals, and Ambient MDL
Under `§6.2`'s counting identity $H(X) = H(f(X)) + \mathbb{E}\log_2|\text{fiber}|$, computed residuals restrict target $Y$ to a **local ambient metric ball** around a concrete prediction $U$ ($L(Y) \le L(t) + L_{\mathrm{ambient}}(Y \mid U)$), while quotient tables restrict $Y$ to a **non-local algebraic fiber** $\alpha^{-1}(a)$ ($L(Y) \le L_{\mathrm{abstract}}(a) + L(Y \mid \alpha(Y) = a)$). Because one sees global multi-step operator structure and the other sees local within-fiber proximity and per-row match masks ([Appendix B.3](#appendix-b)), **both stay necessary** and hand off cleanly across four consecutive stages of `§7.2`:

1. **Pre-enumeration (Quotient tables — global):** Replay stored solutions (`§7.4`), then use verb tables to order operators and install tentative label filters before concrete evaluation.
2. **During enumeration (Quotient tables — candidate & RAM gate):** Skip concrete evaluation when input labels cannot reach target labels (plus exact column-prime filtering on pure-ring `G1` subproblems), backed by `plan_v2c`'s 3:1 tentative/fallback reserve.
3. **At the bank / refinement horizon (Computed residuals — local):** Among surviving concrete classes $U$, use $L_{\mathrm{ambient}}(Y \mid U)$ together with **residual bucket regularity** $\alpha(R)$ (`plan_v2c.md:606`) to break within-bucket ties, spawn `(decode U ?R)`, and propose `(if ?g U ?else)` from exact disagreement masks `U != Y`.
4. **Acceptance (Exact ambient MDL — `§6.1–6.2`):** Verify concretely at the root and compare all candidates by one exact Kraft-valid two-part code $L(t) + L_{\mathrm{ambient}}(R)$ (with 1 exactness bit per column, §1.3.3).

#### 2.5.3 True Memory Mechanics and Prescriptive RAM Rule (`§8.4`, `§6.7`)
In bottom-up OE, RAM resides in **both** the layer bank `by[s]` **and** the dedupe hash table `seen`.

- **Prescriptive Monotonicity RAM Rule (1-line invariant):** Whenever backward reachability `can_reach(c, s)` ($s + h_{\mathrm{bwd}}(\alpha(c)) \le S$) is active, **check `can_reach(c, s)` before inserting `c` into `seen`**. *Proof:* Because $s$ increases monotonically, any later duplicate at $s' \ge s$ satisfies $S - s' \le S - s < h_{\mathrm{bwd}}(\alpha(c))$ and fails `can_reach` in $O(1)$ without consulting `seen`. This forces `len(seen) == len(bank)` at every layer, turning an apparent `1.5×` true RAM saving into **9.4×–22.9× true total RAM reduction** on `G1` polynomials (0 misses) and **2.1× true RAM** on the 61-op sequence library ([Appendix B.2](#appendix-b)).
- **Validated scope boundaries (where quotients do *not* save RAM):**
  1. **Undirected discovery / law search (`§8.4`):** **1.0× RAM** (no target $Y$ to prune toward; keep discovery runs broad and shallow per `§7.6`).
  2. **Lifted position-space tasks (`§6.7`):** **1.0× RAM** whenever `at(xs, idx)` sits at or inside the term (`at` breaks value-label propagation from index to element), though arithmetic-outermost lifts (`map-adjacent +`/`-`) still cut **CPU evaluations 5.3×–7.6×** via final-layer pre-filtering ([Appendix B.2](#appendix-b)).

#### 2.5.4 Four Prescriptions for `plan_v2c.md`'s Kernel-Experiment Pipeline (`§6.6`, `§7.5`, `§11.2`)
To make `plan_v2c.md`'s kernel-driven discovery of approximate conservation self-contained and consistent (with minimal code), add exactly four concrete rules — and **omit** both merged product quotients and online fallback feedback from the core (neither earned its complexity in ablations; [Appendix B.2](#appendix-b)):

1. **Add Rule 4 (*Stratify by current words*) to `§7.5` ("Choosing experiments"):** Populate verb-table probe spaces with $\ge 1,000$ probes per operator stratified evenly across occupied quotient buckets plus boundary/constant/equal-prefix edge cases. On separate quotients, this achieves `0/200` misses on edge-stressed tasks with zero online feedback.
2. **Bootstrap the word-candidate grammar from the growing library (`§7.5` / `X4`–`X5`):** Feed accepted library reductions/lifts (`min-el`, `max-el`, `sum`, `map-adjacent`, `all`/`fold`) back into the unary word enumerator (`Card <= 6–8`), re-running word discovery as the library grows; run `X4` with base reductions or 1-level `fold`/`all` element predicates in scope (resolving `plan_v2c.md:688`).
3. **Replace the three hand-supplied selection rules (`plan_v2c.md:686-690`) with 6 lines in `§7.5`:** (a) 1-line vacuity guard (`H_out > 0.05`), (b) 5-line pairwise NMI redundancy cap (`pair_nmi(q_new, q_old) < 0.65`, avoiding heavy joint conditional-MI), and (c) direct per-operator cross-type `group-by` scoring $(\alpha^{\tau_{\mathrm{in}}}, \alpha^{\tau_{\mathrm{out}}})$ instead of hand-pairing list and integer quotients.
4. **Separate joint probing from Rule 3 (*Isolate*) (0 lines of extra code):** Always build unconditional binary verb tables from **joint stratified probes** (`0` false rejects); reserve Rule-3 fixed-argument slices (`f(·, b0)`) strictly for curried/parameter-conditioned conservation (`(mod a 2k)`), since slice tables cause hundreds of false rejections on `+`, `-`, `div`, and `mod` ([Appendix B.2](#appendix-b)).

---

## Appendix A — Plain-English Walkthrough of §2.2 & §2.5 (with Math Links) {#appendix-a}

[Section 2.2](#sec-2-2) and [Section 2.5](#sec-2-5) are dense with abstract-interpretation, coding-theory, and algebra vocabulary. Underneath the terminology, the idea is very simple: **compress the programming language into a handful of tiny "bucket cheat sheets," plan in those miniature worlds before running concrete search, and hand off to exact concrete residuals at the finish line.**

---

### A.1 The Core Picture: Buckets and Cheat Sheets

Suppose the kernel is working with lists of integers. There are infinitely many concrete lists, so searching over them directly blows up. Instead, pick a tiny coarse summary — say, looking only at **parity**: is every number in the list even (`EV`), every number odd (`OD`), a mix of both (`M`), or is the list empty (`E`)?

That summary sorts *every list in the universe* into just **4 labeled buckets**.

Now take any function in the library — say `dbl_all` (multiply every element by 2), `inc_all` (add 1 to every element), or `filter_pos` (keep only positive numbers). Run it on the kernel's existing test inputs and simply record: **if I drop a list from bucket $X$ into function $f$, which bucket(s) can come out?**

- `dbl_all`: `M -> EV`, `OD -> EV`, `EV -> EV`, `E -> E` *(always lands in `EV` for any non-empty list)*.
- `inc_all`: `EV -> OD`, `OD -> EV`, `M -> M`, `E -> E` *(cleanly flips parity)*.
- `filter_pos`: `M -> {E, EV, OD, M}` *(unpredictable from parity alone — any bucket could come out)*.

That tiny "bucket-in $\to$ bucket(s)-out" cheat sheet **is** the whole construction of [§2.2](#sec-2-2):

- The **bucket sorter** (the small function that labels a concrete value with its bucket) is a **[quotient map](#sec-2-2)** $\alpha_j : V \to \mathcal{A}_j$.
- The **bucket labels** (`EV`, `OD`, `M`, `E`; or `sorted`, `non-negative`, `length-4`) are the **[words (nouns/adjectives)](#sec-2-2)** of the language.
- Each operator's **bucket-to-bucket cheat sheet** is its **[pushed-forward abstract transformer](#sec-2-2)** $f^{\sharp_j}$ — literally the **[verb meaning](#sec-2-2)** of operator $f$ in that coarse vocabulary.
- All the cheat sheets together form a miniature, 4-state toy copy of the language: a **[Quotient Algebra](#sec-2-2)** (equivalently, an **[Abstract Deterministic Finite Tree Automaton, or AFTA](#sec-2-2)**).

**Why this beats a "flat signature":** A flat signature (`plan_v2c §6.3`) only puts the problem's *input* and *target* into buckets and then tries to guess operators from past statistical counts. Because it has no cheat sheets for what operators *do* to buckets, it cannot reason across multi-step chains and knows nothing about a newly invented library function until it has seen many solved examples using it. Pushing operators forward into bucket cheat sheets turns static tags into an **executable miniature simulator** that works on a new library function the instant it is probed — with **zero** prior solved tasks.

---

### A.2 Walking Through the Five Mechanics on One Concrete Problem

Suppose the task gives input `xs = [3, -1, 4, 2]` and target `y = [2, 4, 6, 8]`, and the true 3-step answer hidden inside a 61-function library is `dbl_all(sort(abs_all(xs)))`.

1. **Finding good words automatically (*Algebraic Lumpability* + *Canonical Partitions*, [§2.2](#sec-2-2), [§2.3 #1](#sec-2-3)):**  
   How does the kernel discover that `x mod 2` (parity) or `sign` (`-/0/+`) is a useful bucket system, while `x == 5` or `(3x+1) mod 4` is junk?  
   *Test whether the buckets predict themselves after running the library.* If knowing the input bucket(s) tells you the output bucket with almost no guesswork left over, the buckets are **lumpable** (high $\mathrm{Lump}(\alpha; f) = 1 - H_{\mathrm{cond}}/H_{\mathrm{out}}$). For `parity`, knowing even/odd of `a` and `b` determines even/odd of `a + b`, `a - b`, and `a * b` with 100% certainty (an exact **algebraic congruence**). Knowing whether `a == 5` and `b == 5` tells you almost nothing about whether `a + b == 5`, so it scores near zero and is discarded.  
   And why **canonical partitions**? Because `(3x+1) mod 4` puts the *exact same integers* into the exact same 4 buckets as `x mod 4` — it merely scrambled the bucket labels. Deduplicating candidates by which elements they group together and keeping the shortest expression automatically throws away scrambled aliases.

2. **Learning verb cheat sheets for free (*Galois Connection*, *Support*, and *Fiber-Surprise MDL*, [§2.2](#sec-2-2)):**  
   Nobody hand-writes abstract rules. Because `plan_v2c §7.5` already evaluates every library function $f$ on probe inputs, the kernel labels every input and output row with its bucket and runs a single `group-by`. Each entry in the resulting table carries two numbers:
   - **What is possible (*support relation* $f^{\sharp_j}$):** the set of output buckets ever seen for that input bucket. *Safety rule (and honest limit):* if an input bucket combination was never encountered during probing, default to **$\top$ ("top / anything is possible")**, never $\emptyset$ ("impossible"). However, a *seen* input bucket can still miss a rare output bucket on finite probes (`plan_v2c.md §8.8` measured 0.3% lost answers at 1,000–3,000 random probes), so sampled verb tables are **tested knowledge** (`§5.5`) — safe for ordering or tentative-first filtering with a fallback, never hard elimination.
   - **How sharp the transition is (*fiber-surprise MDL weight* $w_j$):** $-\log_2 P_j(a_{\mathrm{out}} \mid f, \vec{a})$. Because `dbl_all(M)` outputs `EV` 100% of the time, it pays $-\log_2(1) = 0$ surprise bits. Because `filter_pos(M)` lands in `EV` only by luck (say 15% of the time), it pays $-\log_2(0.15) \approx 2.7$ surprise bits. Deterministic, law-like verbs automatically rank ahead of noisy "could happen by accident" verbs — extending `plan_v2c §6.2` rule 2 (fiber entropy) directly to abstract transitions.

3. **Cheap mental simulation before real search (*Knuth Shortest Hyperpath* `g_fwd` and `h_bwd`, [§2.2](#sec-2-2)):**  
   Before enumerating concrete programs, the kernel runs a miniature shortest-path pass — **Knuth (1977)**, which is Dijkstra's algorithm generalized to 2-argument functions (hyperedges) — on the tiny bucket road map:
   - **Forward pass (`g_fwd`):** starting from the input's bucket at cost 0, how few steps reach each bucket?
   - **Backward pass (`h_bwd`):** starting from the target's bucket (`non-negative, all-even, ascending`), what is the *minimum remaining number of steps* required to transform any intermediate bucket into the target?
   - **Pruning RAM before storing:** In our 3-step budget, suppose after 2 concrete steps the enumerator builds a candidate list `c` that is still unsorted and still contains odd numbers. Checking `c`'s bucket shows `h_bwd = 2` (it still needs at least 2 more steps). Since $2 + 2 = 4 > 3$, the kernel **drops `c` immediately without storing it in RAM**.
   - Running this tiny millisecond DP *is* what `prompt4.md:197` meant by **"variable compute when decoding a compositional address"**: instead of looking up a static label, the kernel spends a tiny burst of multi-step reasoning in the word-level world to narrow the concrete search.

4. **Combining multiple small vocabularies (*Factored* vs. *Merge-and-Shrink* & *CEGAR*, [§2.3 #2](#sec-2-3)):**  
   Tracking 6 tiny independent vocabularies (`length`, `sign`, `parity`, `sortedness`, ...) is fast to learn and stays well-sampled at 1,000 stratified probes. Merging several vocabularies into one 44-bucket product (**Merge-and-Shrink**) captures multi-property interactions, but creates too many rare bucket corners and loses answers (`plan_v2c.md §8.8`), so the design keeps separate small quotients.

5. **Free `'like'` and `'analogy'` words (*Verb Synonyms* and *Derivation-Space Reflection*, [§2.2](#sec-2-2), [§2.3 #5](#sec-2-3)):**  
   Once every library function has a bucket cheat sheet $f^{\sharp_j}$, two functions whose cheat sheets heavily overlap are automatically **synonyms** (`'like'` words for operators) — discovered with zero hand labels (`map_adj_add` and `map_adj_sub` have nearly identical length/parity/sign tables; so do `filter_pos` and `filter_even`). Similarly, an **analogy** is two problems bridged by the same verb cheat sheet (or a map carrying one operator's table onto another's).

---

### A.3 How Buckets, Residuals, Memory, and Experiments Fit Together (Plain-English Walkthrough of §2.5)

[Section 2.5](#sec-2-5) ties four ideas together that initially look like separate subsystems:

1. **One `group-by` game, two zoom levels ([§2.5.1](#sec-2-5)):**  
   Everything in the store asks the same question on a table: *"How well does column $A$ predict column $B$, and how many leftover bits remain?"*
   - Zoomed **all the way in** ($q = \mathrm{id}$, exact concrete values): 0 leftover bits gives an **exact law or inverse**; a few leftover bits gives a **computed residual** (like `y - U = 1`, proposing `(+ U 1)` or an `if`-split where `U != y`).
   - Zoomed **out to buckets** ($q \ne \mathrm{id}$, 2–8 labels): 0 leftover bits gives an **exact congruence** (`mod p` on `+ - *`); partial leftover bits gives a **soft verb table** (approximate conservation of information).
   - **Why reentrant policies don't loop infinitely:** The kernel does its *table-learning* offline in the agenda (`§7.5`, running `group-by` on probe tables) and its *solving* online (`§7.2`, doing instant table lookups) — never inventing new buckets mid-inner-loop.

2. **Buckets are a wide-angle map; residuals are a close-up ruler ([§2.5.2](#sec-2-5)):**  
   - Buckets look **multiple steps ahead before running code**, cutting down a 60-function library and rejecting dead ends. A close-up ruler (`|y - U|`) is blind to multi-step plans — on `dbl_all(sort(abs_all(xs)))`, the wrong move `running_max(xs)` is *closer* in raw error (`8`) than the right move `abs_all(xs)` (`12`)!
   - Conversely, once you are one step from the answer (say `y = 2*x*x + 1`), buckets put `2*x*x` and `2*y*y` in the *exact same* `all-even, non-negative` bucket and can't tell them apart. The close-up ruler spots `y - 2*x*x = 1` instantly, and exact ambient MDL stays the single final judge.

3. **Why checking reachability *before* the dedupe table unlocks real RAM savings ([§2.5.3](#sec-2-5)):**  
   Bottom-up search stores every expression in **two** places: the layer list `by[s]` (used to build bigger terms) and the dedupe hash table `seen` (used to skip duplicates). If you throw away a dead expression from `by[s]` *after* putting it into `seen`, `seen` still eats almost all the RAM! Because search depth only grows, a dead expression that can't reach the target at depth $s$ can *never* reach it at any deeper depth $s' \ge s$ either — so checking reachability **first** keeps dead expressions out of `seen` completely (turning a 1.5$\times$ memory saving into **9$\times$–23$\times$** on ring polynomials). Equally important: buckets save **no RAM** when there is no target (undirected law discovery) or when `at(xs, idx)` breaks value-label flow inside lifted loops.

4. **Four simple rules for the kernel's own experiments ([§2.5.4](#sec-2-5)):**
   - **Stratify probes using your current buckets:** use $\ge 1,000$ examples covering every bucket plus edge cases like empty/constant lists — enough to eliminate misses without extra feedback plumbing.
   - **Let newly learned library functions become new bucket sorters:** once `min-el` and `sum` enter the library, `all_nonneg` and `sum_mod2` become tiny 3–4 node words.
   - **Keep words non-trivial and diverse:** a 1-line non-constant check plus a 5-line pairwise overlap cap keeps 6 slots from all turning into length variants, and direct cross-type `group-by` handles `Seq -> Int`.
   - **Always probe binary ops on varying pairs:** fixing one argument to a constant like `b = 1` makes `div` look parity-preserving when it isn't.

---

### A.4 Math-to-Plain-English Rosetta Table (Linked to §2.2 & §2.5)

| Math Term / Symbol in [§2.2](#sec-2-2) & [§2.5](#sec-2-5) | Plain-English Meaning | What It Does in the Kernel |
| :--- | :--- | :--- |
| **Quotient map** $\alpha_j : V \to \mathcal{A}_j$ | A tiny **bucket sorter** (e.g., `x mod 2`, `sign`, `is_sorted`). | Collapses infinitely many concrete values into a few coarse "words." |
| **Galois connection** $\alpha_j : \mathcal{P}(V) \rightleftarrows \mathcal{A}_j : \gamma_j$ | Moving between **sets of concrete values** ($\mathcal{P}(V)$) and **bucket labels** ($\mathcal{A}_j$). | Formalizes what exact abstract reasoning guarantees vs. finite probe sampling. |
| **Best abstract transformer** $f^{\sharp_j}$ | Function $f$'s **bucket-in $\to$ bucket(s)-out cheat sheet**, learned by `group-by` on $f$'s probe table. | Gives every library entry an immediate compositional "verb meaning" with zero training traces. |
| **Top** ($\top$) vs. **Empty** ($\emptyset$) | **"Anything could happen"** vs. **"strictly impossible."** | Unprobed bucket inputs default to $\top$; paired with tentative-first + fallback, keeps sampled tables safe. |
| **Algebraic lumpability** $\mathrm{Lump}(\alpha; f)$ | **"Do input buckets predict output buckets?"** ($1 =$ exact prediction, $0 =$ useless). | Automatically discovers good words (`mod_p`, `sign`, `len`, `all_even`) and rejects noisy predicates. |
| **Algebraic congruence** | A bucket system where $f$'s cheat sheet is **100% deterministic** ($\mathrm{Lump} = 1$, zero branching). | Free exact laws (0 surprise bits); e.g., `mod p` on `{+, -, *, neg}`. |
| **Canonical partition** | Grouping values by **which ones land in the same bucket**, ignoring arbitrary bucket names. | Collapses disguised duplicates like `(3x+1) mod 4` onto the shortest term `x mod 4`. |
| **Fiber-surprise MDL weight** $w_j$ | Operator bit-length plus **how unlikely** the output bucket is ($-\log_2 P_j$). | Ranks sharp, purposeful operators ahead of noisy "could match by accident" ones. |
| **AFTA** (Abstract DFTA) | The **miniature road map** formed by all buckets and all verb cheat sheets together. | Lets the kernel test multi-step compatibility over dozens of states instead of millions. |
| **Knuth shortest hyperpath** (`g_fwd`, `h_bwd`) | **Dijkstra's algorithm for multi-input functions** on the miniature road map. | Computes minimum remaining steps to the target so dead concrete candidates are dropped before RAM. |
| **Column homomorphism** $\mathbb{Z}^N \to \mathbb{F}_p^k$ ([§2.3 #3](#sec-2-3)) | Applying `mod p` to **an entire column of rows at once** instead of one row at a time. | Keeps $\le 125$ finite-ring states while slashing true RAM up to **22.9$\times$** on `{+, -, *, neg}`. |
| **Monotonicity RAM rule** ([§2.5.3](#sec-2-5)) | Check reachability **before** inserting into the `seen` dedupe table. | Prevents pruned classes from bloating `seen`, turning `1.5×` RAM into `9.4×–22.9×`. |

---

## Appendix B — Audit Process, Errata, and Probe Ablation Ledger {#appendix-b}

This appendix records the historical process, independent-reproduction corrections, and probe ablations that condensed early proposals into the four lean prescriptions of [§2.5](#sec-2-5).

### B.1 Errata & Corrections From Independent Reproduction (`plan_v2c.md §8.8`)
1. **Table 2 RAM mismatch (fixed in [§2.3 #2](#sec-2-3)):** The initial draft paired `+SoftMDL` candidate counts on `T3`/`T5`/`T9` (`85`/`164`/`3,524`) with unordered `AbsDFTA` RAM counts (`812`/`1,383`/`6,048`); corrected to exact matched `m_st` values (`51`/`51`/`2,269`).
2. **Soundness downgrade for sampled verb tables (fixed in [§2.2](#sec-2-2), [§2.3 #2](#sec-2-3), [Appendix A.2](#appendix-a)):** Defaulting *unseen* input buckets to $\top$ does not cover *seen* input buckets that miss a rare output label on finite probes (`plan_v2c.md §8.8` measured 11% lost at 100 probes, 0.3% at 1,000–3,000 random probes, 0 at 1,000 edge-stratified probes, and 8% lost for a merged 3-quotient product at 3,000 probes). Verb tables are therefore strictly **tested knowledge** (`§5.5`).
3. **Derivation-space indexing deferred:** Plain replay of stored solutions outperformed signature indexing at $\le 20$ stored solutions (`plan_v2c.md §7.4, §8.8`), so indexing is deferred until library size makes plain replay expensive.

### B.2 Probe Ablations Behind §2.5 (Kept, Simplified, and Dropped Proposals)

Scripts: `verify_guard_fourier_slices.py`, `exp_devils_advocate.py`, `verify_ram_and_nmi.py`.

1. **True RAM accounting (`seen + bank`) and lifted `tg-probe` tasks (behind [§2.5.3](#sec-2-5)):**

   | Target / Task | Plain `seen / bank` | Prune `bank` only (`KeepSeen`) | Check before `seen` (`§2.5.3`) | True RAM / Eval Gain |
   | :--- | :---: | :---: | :---: | :--- |
   | `G1 A4 (sz9): (x+y)*(x-y)+1` | `490 / 490` | `407 / 52` (`1.2×`) | **`52 / 52`** | **9.4$\times$ true RAM** |
   | `G1 A8 (sz11): (x+y)^2-xy+1` | `2,713 / 2,713` | `1,876 / 120` (`1.4×`) | **`120 / 120`** | **22.6$\times$ true RAM** |
   | `G1 A12 (sz13): 2(x^2+y^2)-xy` | `15,760 / 15,760` | `10,719 / 687` (`1.5×`) | **`687 / 687`** | **22.9$\times$ true RAM** |
   | Lifted `map-adjacent (+)` / `(-)` [4 ops] | `59,970` / `85,362` evals (`2,247` RAM) | — | `11,218` / `11,287` evals (`2,247` RAM) | **5.3$\times$ / 7.6$\times$ evals**, **1.0$\times$ RAM** |
   | Lifted `reverse` / `rotate-left` [3 ops] | `898` / `2,383` evals (`213` / `572` RAM) | — | `898` / `2,383` evals (`213` / `572` RAM) | **1.0$\times$ evals, 1.0$\times$ RAM** (`at` outermost) |

2. **Why `Card <= 6–8` beats `Bool`-only guard synthesis (`CHECK 1`):** On `{+, -}` over $[-12, 12]^2$, `x mod 3` (3-valued) has lumpability **`1.00`** (`Hc = 0.00`), whereas Boolean `(x mod 3 == 0)` collapses to **`0.55`** (`Hc = 0.41`); `x mod 5` (`1.00`) collapses to **`0.28`** as `(x mod 5 == 0)`; `sign` (`1.00` on `*`) drops to **`0.80`** as `x < 0`.

3. **Why heavy joint conditional-MI was simplified to 5-line pairwise NMI (`CHECK 2`, `EXP B`, `VERIFY PART 2`):**
   - Naive lumpability picked vacuous constants (`const_0`, `len>=0`). Vacuity guard alone filled all 6 slots with length variants (`len_cap6..3`, `len_mod2..3`: `19,805` evals, `4,207` RAM on 8 tasks under `§8.8` pre-filtering).
   - Greedy joint conditional-MI worked cleanly (`x mod 3 -> x mod 2 -> x > 0`, driving redundant `x < 1`/`x < 0` to `cMI = 0.00`), **but** a much simpler **5-line pairwise NMI cap (`< 0.65`)** already picked `[len_cap6, all_even, all_nonneg, is_sorted, max_le_2, has_zero]` and cut evaluations to **`12,221`** (**4.5$\times$** vs. plain `55,531`, **2.1$\times$** true RAM `3,892` vs. `8,265`). Direct per-operator cross-type `group-by` auto-paired `min_el`/`count_even` (`lump = 1.00`), `len` (`0.79`), and `prod` (`0.58`) with zero hand pairing.

4. **Why joint probing must stay separate from Rule-3 *Isolate* slices (`CHECK 3`, `EXP C`):** On `mod 2`, `div` has joint lumpability **`0.04`** yet slice `b = 1` scores **`1.00`**; `mod` has joint **`0.53`** yet slices `b = 2, 4` score **`1.00`**. Across 500 fresh `(a, b)` pairs in `[-20, 20]^2`, Rule-3 slice tables (`b` $\in \{-1,0,1,2\}$) caused **55 (`+`), 50 (`-`), 287 (`div`), and 422 (`mod`) false rejections** vs. **0 false rejections** across all 7 ops from joint grid probing.

5. **Why online fallback feedback (earlier Gap 5) and merged product quotients were dropped (`EXP D`):** Over 200 edge-stressed 3-op sequence tasks (each including structured edge rows like `(3,3,3,1)`, `(0,0,0)`, `(5,4,3,2)`):
   - Separate 4 quotients, 150 random probes: `110/200` misses without feedback $\to$ `55/200` with 5-line feedback (`38/100` then `17/100`).
   - **Separate 4 quotients, 1,000 stratified probes (Prescription 1), ZERO feedback:** **`0/200` misses (`0/100` then `0/100`)** — making online feedback unnecessary in the core once probes are stratified.
   - Merged 3-quotient product (`nonneg` $\times$ `parity` $\times$ `order`), 2,000 stratified probes: `50/200` misses without feedback $\to$ `43/200` with feedback (confirming `plan_v2c.md`'s decision to omit merged products).

### B.3 Mathematical Positioning Notes (Fourier / Projective Analogy & Residual Complementarity)
- **Projective-space Boolean Fourier bases:** Exact lumpability *recovers* discrete Fourier / modular characters on abelian rings (`x mod p`, $\mathbb{Z}^N \to \mathbb{F}_p^k$), the oriented projective/radial quotient on scale-invariant ops (`sign`: $\mathbb{Z}/\mathbb{R}_{>0}$), and $\mathbb{Z}_2$-complementation on 2-block canonical partitions (`p` $\sim$ `not p`). However, general sequence/container ops (`sort`, `filter`, `reverse`, `max`, `len`) do not act on $\mathbb{Z}_2^n$ or a linear vector space; their quotients are non-orthogonal overlapping partitions in $\mathrm{Eq}(V)$ governed by conditional entropy rather than Walsh–Hadamard inner products.
- **Concrete proof of quotient/residual complementarity:** On `xs = [3, -1, 4, 2]`, `y = dbl_all(sort(abs_all(xs))) = [2, 4, 6, 8]`, wrong step `running_max(xs) = [3, 3, 4, 4]` has smaller ambient error ($L_1 = 8$) than true step 1 `abs_all(xs)` ($L_1 = 12$) even though `running_max` destroys `-1` and `2` irreversibly — showing why multi-step quotient filtering is needed before concrete search. Conversely, on `y = 2*x*x + 1` or `y = (if (< x 0) 0 (* x x))`, coarse parity/sign buckets equate `2*x*x` and `2*y*y` and cannot see per-row agreement masks — showing why computed ambient residuals remain indispensable at the bank horizon.
