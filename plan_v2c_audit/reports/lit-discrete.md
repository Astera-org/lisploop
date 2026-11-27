# lit-discrete — the discrete ("what connects to what") side: data structures and rewriting

Calibrated literature review for the lisploop topology–geometry kernel analysis.
Author: research agent `lit-discrete`. Date: 2026-11-24.

## How to read this

Evidence tags on individual claims:

- **[V]** verified online in this session; a URL follows.
- **[V-abs]** verified only from an abstract, a search-engine summary, or a secondary summary of the source; the full text was not read.
- **[FM]** FROM-MEMORY: not verified online in this session. Treat as a lead, not a fact.
- **[EST]** my own engineering estimate (lines of Common Lisp, untested). No source.

Maturity tags, as requested:

- **SHIPPED** — load-bearing in widely used systems.
- **PROVEN-RESEARCH** — several independent working implementations.
- **SINGLE-PAPER** — one group or one paper (plus perhaps one follow-up).
- **SPECULATIVE** — proposed or demonstrated only anecdotally.

Each technique has the same six fields: *What*, *Evidence*, *Failure modes and costs*, *Maturity*, *Smallest sound version*, *Relevance to the owner's lens*.

---

## 0. The ten findings that matter most

1. **The cheap part of an e-graph is shipped; the expensive part is not pulling its weight where it shipped.** Hash-consing + union-find + congruence closure is O(n log n) and sits inside every SMT solver. Equality *saturation* is exponential under associativity–commutativity (AC): a sum of n variables saturates to exactly 2^n − 1 classes and 3^n − 2^(n+1) + n + 1 nodes [V]. In the one production compiler that adopted e-graphs (Cranelift), the author's 2026 retrospective measures the multi-representation feature at about 0.1% execution-time benefit; nearly all the gain came from hash-consed sea-of-nodes plus eager directed rewrites [V].
2. **E-graphs, version-space algebras and finite tree automata are the same data structure** (classes = states, nodes = transitions) [V-abs]. This is the strongest mature evidence that one store can serve equivalence-merging, pattern matching and solving. It is a research-level unification, not a shipped product.
3. **"Run the interpreter backwards" does not scale, by its inventors' own statement.** The 2025 PLDI paper by the miniKanren authors says the interpretive overhead "makes the relational interpreter approach impractical for most applications" [V]. Their staged version filling three holes in `fib` takes 1.8 s; unstaged exceeds 5 minutes [V].
4. **Inverse semantics as a per-operator table is shipped** (FlashMeta/PROSE witness functions, in Excel Flash Fill and other Microsoft products) [V-abs]. The inverses are hand-written by a DSL designer. *Learning* them has no mature precedent.
5. **Synthesis over lifting combinators is orders of magnitude cheaper than over raw recursion.** λ² (map/fold/filter templates with deduction through them) has a median of 0.43 s over 40+ benchmarks [V]. DreamCoder, starting from a Y combinator, needed "roughly five days on 64 CPUs" (about 7,700 CPU-hours) to rediscover fold and unfold [V-abs]. An hours-long single-threaded budget is roughly a thousandth of that.
6. **Anti-unification is cheap and shipped in its first-order form; everything beyond that costs.** Modulo an arbitrary equational theory the generalisation set is "usually infinite" [V-abs]. Over e-graphs (babble) it is "inherently quadratic in the size of the corpus" [V]. The top-down alternative (Stitch) handles 250-program corpora in 0.2–77 s [V] but has no equational reasoning and no higher-order abstractions.
7. **"Hold all but a few inputs constant and see what changes" is an established discovery method** for numeric laws (BACON 1977–81; control-variable symbolic regression 2023; AI Feynman 2020) and for program dependence (dynamic slicing, delta debugging, causal program dependence analysis 2025) [V-abs]. For *equational* laws the direct precedent is QuickSpec and Ruler: enumerate terms, group them by test fingerprints, prune by congruence closure / e-graph [V-abs].
8. **Graph isomorphism is not needed** if the store is rooted, ordered and hash-consed. It appears only for (a) deduplicating variable-bearing laws modulo renaming and AC — small enough to brute-force — and (b) frequent-subgraph mining, which tree mining (Stitch, babble) sidesteps.
9. **General typed-hypergraph stores have a poor record as the substrate of a learning system.** OpenCog's AtomSpace (since 2008 [FM for the date]) and its Hyperon/MeTTa rewrite have no quantitative benchmark in their own overview paper [V-abs]; the reference MeTTa interpreter is reported about 500× slower than a Prolog transpilation of the same language [V-abs, self-reported by the transpiler's authors]. Wolfram-model rewriting, double-pushout tools, attributed C-sets and interaction nets are used as representations or rewriting engines; I found none used successfully as the substrate of induction.
10. **Reflection paid off in practice only in cheap, measured forms**: memoisation, dependency tracking, partial evaluation of interpreters, bandit-style budget allocation, and learned guidance by a separate statistical model. Same-substrate symbolic self-improvement (Soar chunking, PRODIGY explanation-based learning, EURISKO) hit the *utility problem*: learned rules can make the system slower [V-abs].

---

## Maturity at a glance

| Technique | Tag | One-line calibration |
|---|---|---|
| Hash-consing, union-find, congruence closure | SHIPPED | O(n log n); core of SMT solvers and compiler value numbering |
| Equality saturation (egg, egglog) | PROVEN-RESEARCH | Many tools; runtime unpredictable; AC exponential |
| Acyclic e-graph, eager rewrites (Cranelift) | SHIPPED | Works; multi-representation adds ~0.1% |
| Slotted e-graphs (binders) | SINGLE-PAPER | PLDI 2025 + one 2026 preprint |
| Colored e-graphs (conditional equalities) | SINGLE-PAPER | One group, two papers; contextual reasoning still an open thrust |
| Relational e-matching / Datalog engines | SHIPPED (Datalog) / PROVEN-RESEARCH (e-matching) | Joins with worst-case-optimal bound |
| AtomSpace / Hyperon / MeTTa as induction substrate | SPECULATIVE | No quantitative results after ~17 years |
| Wolfram-model hypergraph rewriting | SPECULATIVE (for induction) | Exploration tool only |
| DPO/SPO graph rewriting tools (GrGen, GP 2, …) | PROVEN-RESEARCH | Real tools; never a learning substrate |
| Catlab / ACSets | PROVEN-RESEARCH | One ecosystem; an indexed in-memory relational store with a categorical spec |
| Interaction nets / optimal sharing (HVM) | SINGLE-PAPER-ish, experimental | Work in progress; synthesis claims unpublished |
| Inductive logic programming on relational facts | PROVEN-RESEARCH | The one mature "induction on a relational store"; small programs |
| miniKanren relational interpreters | PROVEN-RESEARCH | Toy scale; "impractical for most applications" |
| Propagator networks (general) | PROVEN-RESEARCH (small) | Constraint propagation itself is SHIPPED |
| Lenses / bidirectional transformations | PROVEN-RESEARCH | Laws useful as tests; limited expressiveness |
| FlashMeta witness functions + version spaces | SHIPPED | Hand-written inverses |
| Finite-tree-automata synthesis (Dace, Blaze, ECTA) | PROVEN-RESEARCH | 0.7 s average on 84 tasks; 90× over PROSE on matrices |
| Observational-equivalence pruning | PROVEN-RESEARCH (standard) | Breaks with side effects / context-dependent semantics |
| Provenance semirings | PROVEN-RESEARCH | Clean algebra; polynomial blow-up if tracked in full |
| Incremental / self-adjusting computation | SHIPPED (Salsa-style) | Demand-driven memo graph; core < 50 lines |
| Tracing JIT / partial evaluation | SHIPPED | Trace + guards + side exits |
| Control-variable experiment for law discovery | PROVEN-RESEARCH | BACON → CVGP/VSR → AI Feynman |
| First-order anti-unification | SHIPPED | Linear; unique result |
| Higher-order pattern anti-unification | PROVEN-RESEARCH | Linear; unique result |
| Anti-unification modulo theories | PROVEN-RESEARCH (AC) / research | Infinite or exponential result sets |
| babble (anti-unification over e-graphs) | SINGLE-PAPER (+1 preliminary follow-up) | Quadratic in corpus |
| Stitch (top-down abstraction) | PROVEN-RESEARCH | Seconds to minutes; first-order abstractions only |
| Rank / each operators (APL, J, K) | SHIPPED | Lift as an explicit language primitive since the 1960s |
| Second-order array combinators (Futhark) | SHIPPED (in a real compiler) | map/reduce/scan/scatter, no recursion |
| Recursion schemes as synthesis templates | PROVEN-RESEARCH | λ², paramorphism synthesis, DreamCoder |
| Reflective towers (3-Lisp, Brown, Black) | SINGLE-PAPER each | Elegant; no load-bearing use |
| Collapsing towers by staging | SINGLE-PAPER (+ follow-ups) | Shipped analogue: Truffle partial evaluation |
| Soar chunking, PRODIGY EBL | PROVEN-RESEARCH with a documented failure | Utility problem |
| EURISKO heuristics-as-data | SPECULATIVE | Anecdotal successes; self-critique by author |
| Rational metareasoning | PROVEN-RESEARCH (myopic forms) | Exact form intractable |
| nauty / Traces canonical labelling | SHIPPED | Fast in practice; exponential worst case |
| Weisfeiler–Leman hashing | SHIPPED as a filter | Not a canonical form; fails on regular graphs |
| gSpan frequent-subgraph mining | PROVEN-RESEARCH | For many small graphs (molecules) |
| String-diagram rewriting, categorical databases | PROVEN-RESEARCH | Vocabulary and correctness conditions; no speed |

---

## 1. Term graphs and sharing

### 1.1 Hash-consing (DAG terms) — SHIPPED

- **What.** Every node `(operator, child-ids…)` is looked up in a hash table before being created, so structurally equal terms are one object and equality is an identity comparison. A term with shared subterms is a directed acyclic graph (DAG).
- **Evidence.** Cranelift's mid-end keeps pure operators in a hash-consed "sea of nodes"; global value numbering falls out of interning [V] (https://www.cfallin.org/blog/2026/04/09/aegraph). SMT solvers, BDD packages and Lisp symbol tables all rely on it [FM].
- **Failure modes and costs.** Interned terms leak unless the table is weak or collected by generation [FM]. It gives identity only up to *syntax*: not up to renaming of bound variables and not up to AC unless terms are normalised before interning. Hashing modulo bound-variable renaming exists (O(n log² n), PLDI 2021; an O(n log n) follow-up) but is a specialised algorithm [V-abs] (https://arxiv.org/pdf/2105.02856).
- **Smallest sound version.** One `equal` hash table keyed on `(op . child-ids)`. About 50–100 lines [EST].
- **Relevance.** This is the baseline answer to "same structure = same node". Substitution becomes "rebuild the path through the interning table"; sharing is automatic.

### 1.2 Union-find — SHIPPED

- **What.** A forest of parent pointers representing a partition; `find` returns a class representative, `union` merges two classes.
- **Evidence.** "About 15 lines of code" for a minimal version [V-abs] (https://bernsteinbear.com/blog/whats-in-an-egraph/).
- **Failure modes and costs.** No un-merge: backtracking needs a trail or a persistent variant. Explaining *why* two things are equal needs a separate proof forest; a naive explanation routine "would strongly dominate" the O(n log n) run time [V-abs] (https://www.cs.upc.edu/~roberto/papers/IC06.pdf).
- **Smallest sound version.** 30 lines [EST].
- **Relevance.** This is the quotient operation. It is one-way; guards that hold only in a region cannot be expressed by a plain merge (see 2.4).

### 1.3 Congruence closure — SHIPPED

- **What.** Keep an equivalence relation closed under "equal children imply equal parents". Hash-consing + union-find + a repair step after each merge.
- **Evidence.** O(n log n) since Downey–Sethi–Tarjan and Nelson–Oppen (1980); a simpler formulation with proof production by Nieuwenhuis and Oliveras [V-abs] (https://www.cs.upc.edu/~oliveras/lpar03.pdf).
- **Failure modes and costs.** Ground equalities only: it never invents new terms. The classic graph formulations need "rather involved manipulations" to hit the bound [V-abs]. A brute-force sweep instead of parent pointers is simpler but egg found it "too slow on larger workloads" [V-abs] (https://philipzucker.com/a-simplified-egraph/).
- **Smallest sound version.** 150–300 lines with deferred rebuild [EST].
- **Relevance.** This is "equivalence-merging" as a uniform store operation. It is the whole of an e-graph apart from rule application.

---

## 2. E-graphs and equality saturation

### 2.1 Equality saturation (egg, egglog) — PROVEN-RESEARCH

- **What.** An e-graph is a congruence-closed store of e-classes (sets of equivalent terms) and e-nodes (operators over classes). Equality saturation applies rewrite rules non-destructively — each match *adds* an equality — until nothing changes or a budget expires, then *extracts* a cheapest term.
- **Evidence.** egg (POPL 2021) reports case studies with "up to 3000×" speed-ups over prior e-graph code [V-abs] (https://arxiv.org/abs/2004.03082). Herbie runs equality saturation over 325 hand-written rules [V-abs] (https://arxiv.org/pdf/2410.14025). Relational e-matching (POPL 2022) recasts pattern matching as conjunctive queries and is "orders of magnitude faster" than egg's matcher [V-abs] (https://arxiv.org/abs/2108.02290). egglog (PLDI 2023) merges Datalog and equality saturation [V-abs] (https://arxiv.org/pdf/2304.04332). There is an annual workshop (fifth edition in 2026) and a January 2026 Dagstuhl seminar [V] (https://www.dagstuhl.de/26022).
- **Failure modes and costs.**
  - *AC blow-up.* Exact counts for x1 + … + xn under associativity and commutativity: 2^n − 1 e-classes and 3^n − 2^(n+1) + n + 1 e-nodes [V] (Rosin, Ullrich, Hack, EGRAPHS 2026; https://compilers.cs.uni-saarland.de/papers/ullrich_egraphs2026-paper17.pdf). Their multiset fix still "requires an exponential amount of memory" in the worst case [V].
  - *Unpredictable run time.* "Their run-time performance is unpredictable"; time-outs and size limits make run time predictable but results unpredictable, and adding rules can block optimisations that previously fired [V] (https://uwplse.org/2025/06/16/egraph-complexity.html). Size after n iterations is bounded by roughly I·r^(n−1) for r rules [V, same source].
  - *Non-termination.* An associativity rule plus a multiply-by-zero rule fails to saturate within 8 iterations in a published example [V] (https://uwplse.org/2026/02/24/egglog-containers.html).
  - *Extraction.* Choosing the cheapest term when sharing counts is NP-hard and hard to approximate within any constant factor; exact methods use integer programming or treewidth-parameterised dynamic programming [V-abs] (https://arxiv.org/pdf/2408.17042).
  - *Binders and conditions.* See 2.3 and 2.4.
- **Smallest sound version.** Union-find + hash-cons + rebuild + naive top-down e-matching + bottom-up cost extraction. Teaching implementations exist ("micro-egg", June 2026, without extraction [V] https://pavpanchekha.com/blog/microegg.html; Zucker 2021 [V]). Neither states a line count. My estimate is 300–600 lines [EST]; a commonly repeated figure of "about 100 lines" for a toy version is [FM].
- **Relevance.** The owner named e-graphs as a possible big-O hazard. The hazard is saturation with algebraic rules, not the store.

### 2.2 Acyclic e-graph with eager rewriting (Cranelift) — SHIPPED

- **What.** A restricted e-graph: nodes are immutable once created, union nodes replace separate class objects, rewrites run eagerly as each node is created in a single pass, with no rebuild step and no fixpoint.
- **Evidence** (all [V], https://www.cfallin.org/blog/2026/04/09/aegraph):
  - about 2% faster generated code than the previous pass pipeline, at 7–8% more compile time;
  - average e-class size after rewriting: 1.13 e-nodes;
  - across about 4 million value nodes, eager choice was suboptimal twice;
  - going from hash-consed sea-of-nodes to a true multi-representation e-graph "nets us ~0.1% execution-time improvement, at ~0.005% compile-time cost";
  - the rule set deliberately excludes associativity and commutativity; recursive rewrites are bounded in depth and count;
  - author's verdict: the sea-of-nodes aspect "works great", multi-representation "may not (yet?) be pulling its weight".
- **Failure modes and costs.** Less powerful than a full e-graph; extraction ignores sharing; side effects and control flow stay outside the graph.
- **Smallest sound version.** Hash-consed nodes + union nodes + directed rules with depth bound + bottom-up cost table: 250–400 lines [EST].
- **Relevance.** This is the shipped evidence for "use the store, skip the saturation". It also shows that keeping many equivalent forms alive rarely pays when rules are simplifications.

### 2.3 Binders: slotted e-graphs and de Bruijn indices — SINGLE-PAPER

- **What.** Slotted e-graphs make variable names a parameter of the e-class, so terms differing only by (bound or free) variable names are represented once.
- **Evidence.** PLDI 2025; two case studies; solves "practically relevant problems that cannot be solved with e-graphs using de Bruijn indices" [V-abs] (https://pldi25.sigplan.org/details/pldi-2025-papers/77/). One 2026 preprint extends it [V-abs, title only] (https://arxiv.org/pdf/2609.03998).
- **Failure modes and costs.** Limitations not stated in the abstract; I could not verify overheads. De Bruijn encoding breaks sharing of open subterms and needs shifting rules that themselves inflate the graph [FM].
- **Smallest sound version.** None that is small. The low-risk alternative is to avoid binders in stored terms by using point-free combinators (section 7).
- **Relevance.** "Substitution under binders in a merged graph" has no mature precedent.

### 2.4 Conditional equalities: colored e-graphs, assumption nodes — SINGLE-PAPER

- **What.** A base ("black") congruence relation plus layered relations that hold only under an assumption ("color").
- **Evidence.** Singher and Itzhaky, 2023 preprint and FMCAD 2024: hundreds of assumptions, about 10× less memory than one e-graph per assumption [V-abs] (https://arxiv.org/pdf/2305.19203). The alternative — explicit ASSUME nodes — "significantly expand[s] the size of the e-graph" [V-abs] (https://arxiv.org/pdf/2507.11897). Contextual reasoning was one of four open thrusts at Dagstuhl 2026 [V].
- **Failure modes and costs.** One group; targets egg's non-relational matcher; relational version is "ongoing work" [V-abs].
- **Smallest sound version.** Do not merge conditionally. Store a guarded law as a row `(guard, lhs-class, rhs-class)` and consult it during matching; merge only what holds unconditionally. About 100 lines on top of the store [EST].
- **Relevance.** The owner's "guards = regions where a law does not hold" maps onto exactly the part of e-graph research that is not yet settled.

### 2.5 2025–2026 developments worth knowing

- Dagstuhl seminar 26022 "Program Optimization with E-Graphs", four thrusts: program representation, rewriting models, contextual reasoning, extraction [V].
- AC handled natively by multiset nodes (Rosin et al. 2026) and by egglog "containers" (multisets plus higher-order `map`/`fold` primitives): one example drops from 13,040 e-graph nodes to 927; stated limits are greedy factoring and weak composition of primitives [V] (https://uwplse.org/2026/02/24/egglog-containers.html).
- Oatlog, an ahead-of-time compiled egglog engine, faster below about 10^5 e-nodes, parity beyond 10^7 [V-abs].
- E-Stitch (EGRAPHS 2026): top-down library learning over an e-graph, "preliminary" [V] (section 6.5).
- "Semantic foundations of equality saturation" (ICDT 2025) formalises e-graphs as reachable deterministic tree automata and notes that theory lags practice [V-abs] (https://arxiv.org/pdf/2501.02413).

---

## 3. Typed graph and hypergraph stores, and rewriting

**Direct answer to "which have been the substrate of a learning/induction system?"**

| Store | Used for induction? | Outcome |
|---|---|---|
| Relational facts + rules (inductive logic programming) | Yes, for 30+ years | Works at small program sizes |
| E-graph (babble, Ruler, E-Stitch) | Yes, since 2021 | Library learning and rule inference at research scale |
| AtomSpace / MeTTa | Attempted since 2008 | No quantitative success found |
| Wolfram-model hypergraphs | No | Representation / exploration |
| DPO/SPO graph grammars, GP 2 | No | Representation / transformation |
| ACSets (Catlab) | No | Representation / modelling |
| Interaction nets (HVM) | Claimed (SupGen) | Unpublished; unverifiable |

### 3.1 OpenCog AtomSpace, Hyperon, MeTTa — SPECULATIVE as an induction substrate

- **What.** A typed "metagraph" store (links may contain links) with a pattern-matching query engine; MeTTa is a language whose programs are themselves atoms in the store, executed by match-and-rewrite. The stated aim is close to the owner's: one store for data, programs, inference rules and learning.
- **Evidence.** The 2023 Hyperon overview paper is a design and roadmap document with no quantitative benchmark in its abstract [V-abs] (https://arxiv.org/abs/2310.18318). On the older system, the project's own mailing list records that the evolutionary program learner (MOSES) lived outside the AtomSpace, which was "awkward"; that a port was expected to be slower; and that the pattern miner was "a crude tool" [V-abs] (https://www.mail-archive.com/opencog@googlegroups.com/msg00662.html). The maintainer wrote that versioning and provenance were built in "yet no one uses it" [V-abs].
- **Failure modes and costs.** The reference Rust MeTTa interpreter is reported "at least ~500× slower" on average than PeTTa, a MeTTa-to-Prolog transpiler; a Scheme compiler reports 200×+ [V-abs, both self-reported by the faster tools' authors] (https://swi-prolog.discourse.group/t/metta-language-transpiler-petta/9490). The new MORK kernel's speed-ups are stated as "potential" [V-abs]. General pattern queries are subgraph matching (NP-complete); the system bounds them by link types and incoming-set indexes [FM].
- **Honest assessment.** After roughly 17 years (start date [FM]) I found no independent, quantitative demonstration that a uniform hypergraph store *enabled* a learning result that special-purpose structures could not get more cheaply. The lesson is not that the idea is wrong; it is that uniformity of representation did not, by itself, produce capability, and it cost large constant factors.
- **Smallest sound version.** Not applicable; the useful core is "typed tuples with inverse indexes", which is section 3.6.
- **Relevance.** The closest prior attempt at the owner's vision, and the main cautionary tale.

### 3.2 Wolfram-model hypergraph rewriting — SPECULATIVE for induction

- **What.** Rules replace a sub-hypergraph by another; a "multiway" system tracks all possible rewrite orders.
- **Evidence.** The SetReplace package exists and describes itself as an active research project [V-abs]. I found no learning or synthesis result, and no published complexity analysis of its matcher (search came back empty) [V].
- **Failure modes and costs.** Matching is sub-hypergraph isomorphism; multiway growth is combinatorial [FM].
- **Relevance.** Shares the vocabulary ("everything is hypergraph rewriting") but offers no evidence about induction.

### 3.3 Algebraic graph rewriting (double-pushout DPO, single-pushout SPO) and GP 2 — PROVEN-RESEARCH

- **What.** A rule is a span L ← K → R. A match is a structure-preserving map from L into the host graph. Delete the image of L \ K, glue in R \ K. DPO refuses matches that would leave dangling edges; SPO deletes them.
- **Evidence.** Several independent tools: GrGen.NET (search-plan-driven matching; its authors claim an order of magnitude over other tools on a standard benchmark; still maintained) [V-abs] (https://en.wikipedia.org/wiki/GrGen); GROOVE, AGG, Henshin [V-abs]. GP 2 compiles *rooted* rules that match in constant time under mild conditions; a compiled two-colouring program on grids up to 100,000 nodes matched hand-written C [V-abs] (https://arxiv.org/pdf/2501.09144, https://eprints.whiterose.ac.uk/179084/).
- **Failure modes and costs.** Unrooted matching is NP-complete in the rule size; tools rely on heuristics [V-abs]. "Provably correct rewriting code generally performs poorly on large problems" [V-abs] (https://arxiv.org/pdf/2111.03784).
- **How practical systems bound matching.** (1) Rooted rules: start the match at a known node (GP 2). (2) Search plans: order pattern edges by selectivity (GrGen). (3) Types and indexes on edges. (4) Small, fixed pattern size, so cost is polynomial with a small exponent.
- **Smallest sound version.** SPO rewriting on a typed multigraph with rooted matching: 300–500 lines [EST].
- **Relevance.** A rooted, typed pattern is the form in which "patterns that control graph rewrites" is cheap.

### 3.4 Catlab and attributed C-sets (ACSets) — PROVEN-RESEARCH

- **What.** A schema (a small category: tables as objects, foreign keys as arrows, attributes as typed columns) and instances of it stored column-wise with automatic inverse indexes. Described by its authors as "a joint generalization of graphs and data frames".
- **Evidence.** Within about a factor of two of a fast native Julia graph library on the authors' own benchmark [V-abs] (https://arxiv.org/abs/2106.04703). AlgebraicRewriting.jl provides DPO, SPO and sesqui-pushout rewriting over any schema, with backtracking homomorphism search [V-abs].
- **Failure modes and costs.** One ecosystem, one language (Julia). Homomorphism search is still subgraph matching.
- **Smallest sound version.** Tables with integer foreign keys and an inverse index per key column: 200–300 lines [EST]. This is what an implementer would write anyway.
- **Relevance.** Closest existing design to "frames + graph in one store". The category theory is a specification; the implementation is indexed tables.

### 3.5 Interaction nets and optimal sharing (HVM, Bend) — experimental

- **What.** Graph reduction by local rules with explicit duplication nodes, aiming at Lévy-optimal sharing of work.
- **Evidence.** HVM3 is described as work in progress [V-abs]. The synthesis demo "SupGen" (January 2025) drew a request on the Lean forum for a paper before relying on it [V-abs] (https://leanprover-community.github.io/archive/stream/113488-general/topic/SupGen.html). The author's own notes mention quadratic slow-downs against GHC in some cases [V-abs].
- **Failure modes and costs.** The cost of optimal (parallel) β-reduction "is not bounded by any Kalmár-elementary recursive function" (Asperti and Mairson) [V-abs]. The efficient "abstract algorithm" is sound only for a typable subset.
- **Relevance.** Elegant sharing, no verified induction result. High risk for this owner.

### 3.6 Relational stores: Datalog, triples, and inductive logic programming — SHIPPED (engines) / PROVEN-RESEARCH (induction)

- **What.** Programs or data as relations (triples are the binary case); derived facts by Horn rules evaluated bottom-up to a fixpoint ("semi-naive": only join against facts new in the last round).
- **Evidence (as representation).** Soufflé compiles Datalog to C++ and runs whole-program points-to analysis (Doop) [V-abs] (https://github.com/plast-lab/doop). GitHub's CodeQL is a Datalog-derived query language over program facts [FM].
- **Evidence (as induction substrate).** Inductive logic programming learns rules from relational examples. Popper (2021) uses a generate–test–constrain loop over answer-set programming and Prolog, learns recursive programs and invents predicates [V-abs] (https://arxiv.org/pdf/2005.02259). Typical learned programs are a handful of short clauses [FM].
- **Failure modes and costs.** Rule matching is conjunctive-query evaluation. With a worst-case-optimal join the cost is bounded by the query's maximum output size (the "AGM bound") [V]. Performance "depends on ordering rule premises" [V-abs]. Richer value domains lose the termination guarantee [V-abs].
- **Smallest sound version.** Indexed relations + semi-naive evaluation of Horn rules: 300–500 lines [EST].
- **Relevance.** The most mature form of "what connects to what, queried and derived uniformly". An e-graph is this plus a union-find column (that is egglog's point).

---

## 4. Relational and bidirectional computation ("reorientation")

### 4.1 miniKanren and relational interpreters — PROVEN-RESEARCH at toy scale

- **What.** A small logic language (unification, fresh variables, interleaved disjunction). Write an interpreter as a relation `eval(expr, value)`, then query with `expr` unknown to synthesise programs.
- **Evidence.** Byrd et al., "A Unified Approach to Solving Seven Programming Problems" (ICFP 2017): quines, proof search, synthesis from examples, all from one relational interpreter [V-abs]. Ballantyne et al., "Multi-stage Relational Programming" (PLDI 2025), all [V] from the paper text (https://namin.seas.harvard.edu/pubs/pldi-staged-mk.pdf):
  - "presently, the performance penalty of interpretation makes the relational interpreter approach impractical for most applications";
  - staging gives 7–87× on ground functions, 6–178× through nested interpreters, 2–49× with a sketch;
  - `synth-fib-larger` (accumulators and three holes): unstaged > 5 minutes, staged 1.8 s;
  - synthesising a proof of a longer inference chain: unstaged > 5 minutes, staged 1.1 s;
  - one benchmark gets slower when the staged-on argument is unknown.
- **Failure modes and costs.** Search order is uninformed and carries no cost model. Each layer of interpretation multiplies cost. The hand-tuned interpreter of 2017 needed bespoke search heuristics (argument/body reordering, depth limits, branch weights) [V].
- **Smallest sound version.** microKanren is famously about 40 lines of Scheme [FM]; a relational evaluator for a tiny language adds about 200 lines [EST].
- **Relevance.** Gives "reorientation for free" in principle, and a measured warning: free reorientation through an interpreter is paid for in exponential search. Also a direct data point on reentrancy — every extra interpretive level costs 6–178× until staged away.

### 4.2 Propagator networks and constraint propagation — SHIPPED (constraint propagation) / PROVEN-RESEARCH (general model)

- **What.** Cells accumulate partial information about a value under a monotone merge; stateless propagators recompute neighbours when a cell gains information. A relation such as a + b = c is three propagators, one per direction.
- **Evidence.** Radul's 2009 MIT thesis describes "a prototype general-purpose propagation system" [V-abs] (https://dspace.mit.edu/handle/1721.1/49525). Arc-consistency propagation and unit propagation are the inner loops of production constraint and SAT solvers [FM].
- **Failure modes and costs.** Propagation alone is incomplete; it must be combined with search (guessing and retracting). Tracking which guesses each value depends on can blow up exponentially in the number of assumptions [FM]. Non-monotone operations break the model.
- **Smallest sound version.** Cells + merge + agenda: 150–250 lines [EST].
- **Relevance.** The cleanest mature precedent for "a law reoriented into a solver": the same edge, with a propagator per direction.

### 4.3 Lenses and bidirectional transformations — PROVEN-RESEARCH

- **What.** A pair `get : S → V`, `put : S × V → S` satisfying round-trip laws (GetPut: putting back what you got changes nothing; PutGet: you get what you put).
- **Evidence.** Boomerang; Optician synthesises bijective string lenses from two regular expressions plus examples [V-abs] (https://www.cs.princeton.edu/~dpw/papers/synthesizing-lenses-popl2018.pdf).
- **Failure modes and costs.** The laws restrict what can be written; "unconditional correctness … leads to reduced practicality" [V-abs].
- **Smallest sound version.** Five or six combinators: about 100 lines [EST].
- **Relevance.** A lens is a projection together with a rule for updating within the fibre. The laws are ready-made *tests* for a learned inverse.

### 4.4 FlashMeta / PROSE: witness functions and version-space algebras — SHIPPED

- **What.** For each DSL operator the designer writes a *witness function*: given a required output, it returns constraints on the operator's arguments (a partial inverse). Synthesis runs top-down, pushing examples through witness functions, and collects all consistent programs in a *version-space algebra* — a DAG with union nodes and operator-join nodes.
- **Evidence.** Deployed in Microsoft products (PowerShell, Azure log analytics, Cortana) [V-abs] (https://www.microsoft.com/en-us/research/publication/flashmeta-a-framework-for-inductive-program-synthesis/); Flash Fill in Excel [FM]. A version space can stand for 10^30 programs [V-abs]. Rewriting Flash Fill on the framework took about one month against nine originally [V-abs].
- **Failure modes and costs.** Witness functions capture "(a subset of) inverse semantics" and are written by hand [V-abs]. A domain-specific synthesiser used to cost 1–2 person-years [V-abs]. Intersecting version spaces over many examples is slow [V-abs]. Ranking matters as much as search.
- **Smallest sound version.** Union/join nodes + top-down deduction for about ten operators: 500–800 lines [EST].
- **Relevance.** The shipped form of "fibre/preimage as a first-class operation", with the inverses supplied by a human. The owner's ambition is to *learn* those inverses.

### 4.5 Finite-tree-automata synthesis (Dace, Blaze, ECTA) — PROVEN-RESEARCH

- **What.** States are (symbol, concrete-or-abstract value) pairs; transitions are operators. The automaton accepts exactly the programs consistent with the examples. Multiple examples are handled by automaton intersection (a product construction).
- **Evidence.** Dace: 84 forum benchmarks, 92% solved, 0.7 s average, outperforming PROSE's version-space learner [V-abs] (https://arxiv.org/pdf/1707.01469). Blaze (abstraction refinement): 90× over PROSE on matrix tasks [V-abs]. ECTA (adds equality constraints between subterms): 8× over Hoogle+ with a tenth of the code [V-abs] (https://arxiv.org/abs/2206.07828).
- **Unification result.** Version-space algebras are acyclic tree automata (Koppel 2021) and e-graphs are deterministic tree automata [V-abs] (https://arxiv.org/pdf/2107.12568; https://github.com/egraphs-good/egg/discussions/104). They differ only in what a state means: "equal under the rules" versus "same output on the examples".
- **Failure modes and costs.** State count grows with the number of distinct values reachable; abstraction is needed for large value domains.
- **Smallest sound version.** Bottom-up construction keyed by value vectors, plus top-down extraction: 300–500 lines [EST].
- **Relevance.** Evidence that the frame (rows of example values) and the term graph can be one structure: a class keyed by its value column.

### 4.6 Observational-equivalence pruning — PROVEN-RESEARCH (standard technique)

- **What.** During bottom-up enumeration, run each candidate on the example inputs; keep only the first candidate for each distinct output vector.
- **Evidence.** Called "the standard technique" in the enumerative-synthesis literature [V-abs] (https://arxiv.org/pdf/2511.02491).
- **Failure modes and costs.** Unsound when semantics depend on context or when programs mutate state [V-abs]. It is equivalence *on the examples*, not in general.
- **Smallest sound version.** A hash table from value vector to representative: under 100 lines [EST].
- **Relevance.** The cheapest merge criterion available, and one the existing frame structure already supports.

---

## 5. Execution traces and dependency graphs as first-class data

### 5.1 Provenance semirings — PROVEN-RESEARCH

- **What.** Annotate each base fact with a symbol; joins multiply annotations, unions add them. The resulting polynomial records how each derived fact was produced. Choosing a different semiring gives counting, Boolean reachability, probability, or minimum cost.
- **Evidence.** Green, Karvounarakis, Tannen (2007): bag semantics, incomplete and probabilistic databases and why-provenance are instances of one construction [V-abs] (https://www.cs.ucdavis.edu/~green/papers/pods07.pdf).
- **Failure modes and costs.** Full polynomials can be exponentially large; practical systems keep a cheaper semiring [FM].
- **Smallest sound version.** One extra column per derived row and two user-supplied operations: about 100 lines on a table engine [EST].
- **Relevance.** A principled way to make "what was computed from what" data. The min-plus semiring gives "cheapest derivation in bits", which is the MDL price [FM, standard].

### 5.2 Incremental / self-adjusting computation — SHIPPED

- **What.** Record, while evaluating, which memoised results read which inputs; on change, re-run only what is affected ("early cut-off" when a recomputed value is unchanged).
- **Evidence.** Salsa drives rust-analyzer and mirrors the Rust compiler's red–green query system [V-abs] (https://rustc-dev-guide.rust-lang.org/salsa.html). microAdapton fits "in under 50 lines" of Scheme [V-abs] (https://arxiv.org/pdf/1609.05337).
- **Failure modes and costs.** Classic Adapton was "sometimes slower than from-scratch computation"; stable *names* for nodes are needed for reuse [V-abs] (https://arxiv.org/pdf/1503.07792). Memo tables grow without bound unless collected.
- **Smallest sound version.** Demand-driven memo table with dependency edges and dirty flags: 200–300 lines [EST].
- **Relevance.** This *is* the execution graph as data, built as a by-product of evaluation. It directly serves the owner's first reflection use ("do not do the same calculation many times").

### 5.3 Tracing JITs and partial evaluation of interpreters — SHIPPED

- **What.** Record the operations actually executed along a hot path as a straight-line trace with *guards* (conditions that held), compile it, and fall back ("side exit") when a guard fails.
- **Evidence.** Truffle/Graal compiles interpreters by partial evaluation (the first Futamura projection) in production; a controlled comparison found meta-tracing and partial evaluation "reach roughly the same level of performance" [V-abs] (https://research.jku.at/en/publications/practical-partial-evaluation-for-high-performance-dynamic-languag/).
- **Relevance.** A shipped structure that is literally "residual expression + guard = region where it is valid".

### 5.4 Program synthesis from traces — PROVEN-RESEARCH

- **What.** Infer a program (including loops or recursion) from a record of its operations by deciding which trace steps are the same program point.
- **Evidence.** Biermann and colleagues in the 1970s; merging trace rows into states is a graph-colouring problem and the search "can take a long time" [V-abs]. Trace-guided synthesis of recursive functions (PLDI 2023) and synthesis from partial traces (PLDI 2025) [V-abs] (https://www.microsoft.com/en-us/research/publication/trace-guided-inductive-synthesis-of-recursive-functional-programs/; https://arxiv.org/pdf/2504.14480).
- **Relevance.** Direct precedent for "an expression is a common pattern in the execution graph". The hard step is always state identification.

### 5.5 Structure discovery by intervention — PROVEN-RESEARCH

The owner asked whether "hold all but a few inputs constant and see what changes" is treated as structure discovery. It is, in four literatures:

- **Scientific-law discovery.** BACON (Langley, 1977–81) used "controlled experiments" to find empirical laws [V-abs] (https://ijcai.org/proceedings/1977/77). Control-variable genetic programming (2023) holds "all independent variables except for one as constants", fits that slice, then frees variables one at a time; vertical symbolic regression extends it [V-abs] (https://www.cs.purdue.edu/homes/yexiang/publications/ecml23-cvgp.pdf; https://arxiv.org/pdf/2312.11955).
- **AI Feynman.** Queries a fitted surrogate to test translational, rotational and scaling symmetry and additive/multiplicative separability, then recurses on the simpler sub-problems; solved 100 of 100 textbook equations against 71 for prior software. Version 2.0 aims at "reverse-engineering the computational graph of a mystery function" [V-abs] (https://arxiv.org/pdf/1905.11481; https://arxiv.org/pdf/2006.10782).
- **Program dependence.** Dynamic slicing and delta debugging are standard tools [FM for "standard"]. Causal Program Dependence Analysis (2025) intervenes on a running program to estimate the *strength* of dependence between program elements [V-abs] (https://research.chalmers.se/en/publication/542881). Koppel and Jackson (2020) give a causal definition of dependence that reduces to dynamic slicing [V-abs].
- **Equational laws from tests.** QuickSpec tests a set of functions and reports the equations that hold; the 2017 version "finds much more complex laws, faster" than its predecessors [V-abs] (https://www.cse.chalmers.se/~jomoa/papers/quickspec-JFP.pdf). Its use of congruence closure for pruning is [FM]. Ruler does the same with e-graphs: 5.8× smaller rule sets, 25× faster than an SMT-based tool [V-abs] (https://arxiv.org/pdf/2108.10436).

- **Failure modes and costs.** Pairwise interaction tests are quadratic in the number of inputs; full separability testing is exponential in the worst case [FM]. Tests on noisy or surrogate data give false symmetries [FM]. Laws found by testing are conjectures until checked on fresh data.
- **Smallest sound version.** Finite-difference dependence test + additive/multiplicative separability test + fingerprint grouping of small terms: about 200–300 lines [EST].
- **Relevance.** Strong support for the owner's experimental reading of topology. What is *not* in this literature: feeding the discovered structure back as new primitives in a loop that keeps bootstrapping.

---

## 6. Anti-unification (AU)

### 6.1 First-order syntactic AU — SHIPPED

- **What.** Given two terms, the least general generalisation (lgg) keeps the common skeleton and puts a variable wherever they differ, reusing the same variable for the same pair of differing subterms. Plotkin and Reynolds, 1970.
- **Evidence.** Unique result; linear time on trees. Used in inductive logic programming and in Facebook's Getafix bug-fix learner, which is deployed in production [V for deployment; FM that its pattern learning is anti-unification] (https://arxiv.org/abs/1902.06111).
- **Failure modes and costs.** Purely syntactic: `a+b` against `b+a` generalises to `x+y`. Over-general results need a ranking.
- **Smallest sound version.** 40 lines with a table memoised on pairs [EST]. On hash-consed DAGs the pair table bounds work by the product of the two DAG sizes.
- **Relevance.** Already the right primitive; the question is only what it is taken *modulo*.

### 6.2 Higher-order pattern AU — PROVEN-RESEARCH

- **What.** AU for λ-terms restricted to "patterns" (variables applied only to distinct bound variables).
- **Evidence.** A least general pattern generalisation "always exists and is unique modulo α-equivalence" and is computed in linear time [V-abs] (https://link.springer.com/10.1007/s10817-016-9383-3). Outside the pattern fragment there is no unique lgg [V-abs].
- **Smallest sound version.** 300–500 lines [EST].
- **Relevance.** Needed only if abstractions must take function arguments *and* terms carry binders. Combinator form avoids it.

### 6.3 AU modulo equational theories (E-generalisation) — PROVEN-RESEARCH for AC; otherwise research

- **What.** Find generalisations where instances need only be *equal under a theory E*.
- **Evidence.** For arbitrary E the set of generalisations "is usually infinite"; Burghardt represents it finitely as a regular tree grammar, first as a Prolog prototype, later improved by "several orders of magnitude" [V-abs] (https://arxiv.org/pdf/1403.8118; https://arxiv.org/pdf/1709.00744). The 2023 IJCAI survey states there is "little emphasis … on developing a strong theoretical foundation" [V-abs] (https://arxiv.org/abs/2302.00277). AC generalisation is finitary but can return exponentially many incomparable results; idempotent and multi-unit theories behave worse [FM].
- **Failure modes and costs.** Result sets, not single results; cost is theory-specific.
- **Smallest sound version.** Normalise to an AC canonical form (flatten, sort), then run syntactic AU. Incomplete but linear. About 60 extra lines [EST].
- **Relevance.** "AU as quotienting" is real, but the general case is not something to import.

### 6.4 AU over e-graphs: babble — SINGLE-PAPER (+ one preliminary follow-up)

- **What.** Saturate a corpus e-graph under a user-supplied theory, anti-unify pairs of e-classes to propose abstractions, then extract the best library with beam search.
- **Evidence** [V] (https://ar5iv.labs.arxiv.org/html/2212.04596): four 2-D CAD corpora of 250 programs (19,009–42,936 AST nodes) compressed 4.6–10.9× in 40–110 s on one core; these were "out of reach for DreamCoder". Using the theory "adds relatively little run time".
- **Failure modes and costs.** The theory "must be provided by domain experts"; the AU step "is incomplete and misses some patterns"; beam search "sacrifices theoretical optimality" [V]. Per its successors, the AU is "inherently quadratic in the size of the corpus" [V] (E-Stitch abstract).
- **Relevance.** The only demonstrated "AU on a merged graph". Useful once a theory exists; it does not learn the theory.

### 6.5 Top-down corpus-guided abstraction: Stitch (and E-Stitch) — PROVEN-RESEARCH

- **What.** Search the space of abstraction *bodies* top-down, tracking the set of corpus locations each partial body still matches, and prune any branch whose upper bound on compression (sum of sizes at its match locations) is below the best found.
- **Evidence** [V] (https://ar5iv.labs.arxiv.org/html/2211.16605): eight corpora of 250 programs, 0.24–77 s, 11–684 MB; 3–4 orders of magnitude faster and 2 orders less memory than DreamCoder's compressor at comparable compression. Adopted as the compression module of LILO [V] (https://arxiv.org/html/2310.19791v4).
- **Failure modes and costs.** "Cannot learn higher-order abstractions"; equational rewrites "are not natively supported"; arity capped at 3 in the experiments [V]. E-Stitch (2026) runs the same search over an e-graph and reports beating babble on babble's benchmarks, but the evaluation is "preliminary" [V] (https://pldi26.sigplan.org/details/egraphs-2026-papers/7/).
- **Smallest sound version.** Match-location sets + expansion + bound: 500–800 lines [EST].
- **Relevance.** The lowest-risk abstraction engine at the stated budget.

### 6.6 The categorical reading — SINGLE-PAPER

- **What.** In the category whose arrows are substitutions, Kahl (2019) reports that the universal-arrow construction of categorical *products* coincides with anti-unification, while coequalisers and pushouts correspond to *unification* [V-abs; the paper itself could not be fetched] (https://ifip.hal.science/hal-02364568v1).
- **Consequence.** In that reading AU is a *limit* (a span from the generalisation to both instances), and the *quotient* (a colimit) is unification or class merging. The owner's phrase "AU is a form of quotienting" is best kept as intuition; operationally AU is a product-style walk over pairs. Babble's e-class AU is exactly a memoised product over class pairs [FM for the internal detail], the same construction as tree-automaton intersection.
- **Has anyone made it operational?** Not as a shipped mechanism that I could find. The product construction on tree automata is the operational content, and that is standard.

---

## 7. "Lift as a primitive"

### 7.1 Array languages: rank and each (APL, J, K) — SHIPPED

- **What.** Every function has a *rank* (the dimensionality of the cells it consumes); applying it to a bigger array maps it over the leading "frame" axes. `each` and the explicit rank operator make this lift a first-class, user-visible primitive.
- **Evidence.** In continuous use since the 1960s; formalised with static shape types in Remora [V-abs] (https://arxiv.org/pdf/1907.00509).
- **Failure modes and costs.** Implicit agreement rules are easy to misapply; static typing of shapes needs dependent types [V-abs].
- **Smallest sound version.** Frame/cell split + `each` + scalar extension: about 100 lines [EST].
- **Relevance.** Direct precedent for lift as a language primitive rather than a host-language loop.

### 7.2 Naperian functors — SINGLE-PAPER (conceptual)

- **What.** Gibbons (2017): rank polymorphism needs only containers that are traversable, applicative and *Naperian* — fixed shape, each element addressed by a position, so the container is equivalent to a function from positions [V-abs] (https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.pdf). Pairs, triples, block vectors and perfect trees qualify.
- **Relevance.** A precise version of "a tuple is an edge with coordinates": a tuple is a function from a finite index set, and lift is post-composition.

### 7.3 Second-order array combinators (Futhark) and fusion laws — SHIPPED in a compiler

- **What.** `map`, `reduce`, `scan` and `scatter` as the only parallel constructs, with sequential loops rather than recursion, plus algebraic fusion rules (e.g. map after map is one map).
- **Evidence.** The Futhark compiler "reliably fuses" compositions using these rules [V-abs] (https://www.futhark-lang.org/publications/pldi17.pdf). The underlying Bird–Meertens laws and GHC's fold/build fusion are [FM].
- **Relevance.** Shows that four or five combinators cover a large class of array programs, and that their *laws* are few and known.

### 7.4 List-homomorphism theorems — PROVEN-RESEARCH

- **What.** If a function can be computed both as a left fold and as a right fold, it is a homomorphism: a divide-and-conquer "join" exists (third homomorphism theorem, Gibbons 1996) [V-abs].
- **Evidence.** Parsynt synthesises the join for loops, lifting the loop state when none exists directly [V-abs] (https://www.cs.toronto.edu/~azadeh/resources/papers/pldi17.pdf).
- **Relevance.** A worked example of deriving an algebraic law (associative combine) *from* two execution orders — the owner's "algebra from parallel experiments".

### 7.5 Recursion schemes as synthesis templates — PROVEN-RESEARCH

- **Evidence that combinators beat raw recursion.**
  - λ² (PLDI 2015) [V] (https://www.cs.utexas.edu/~swarat/pubs/pldi15.pdf): hypotheses are drawn from map, mapt, filter, foldl, foldr, foldt and a list recursor; each has *deduction rules* that turn examples for the whole into examples for the argument function. Over 40 benchmarks: median 0.43 s, 88% under a minute; deduction gives 6× on average; without type-directed hypothesis generation more than 60% time out at 10 minutes.
  - Hong and Aiken (PLDI 2024): synthesising via paramorphisms (fold with access to the unprocessed tail) "is simpler and solves more … benchmarks" than prior recursive synthesisers [V-abs] (https://api.crossref.org/works/10.1145%2F3656381).
  - Myth needs "trace-complete" examples to synthesise explicit recursion, which later work calls burdensome [V-abs].
  - DreamCoder with only a Y combinator rediscovers fold, then unfold, at "roughly five days on 64 CPUs" [V-abs] (https://arxiv.org/pdf/2006.08381). The LILO paper describes DreamCoder's search as "requiring more than two CPU-months just to learn a single domain" [V] (https://arxiv.org/html/2310.19791v4).
- **Smallest set of lifting primitives** (my synthesis from the above): `map`/`zip-with` (pointwise lift), `fold` (catamorphism), `scan` (prefix fold), bounded `unfold`/`iterate` (anamorphism), `gather` (index by a vector of positions), `filter`/`partition` (guard). In scheme terms: cata, ana, para. About 150 lines for the primitives and 200–300 for deduction rules through them [EST].
- **Failure modes and costs.** Each combinator needs its own inverse rule; without types or an equivalent pruning the hypothesis space explodes (the λ² ablation).
- **Relevance.** The best-supported single recommendation in this review: make these combinators kernel primitives with inverse rules, and do not expect to discover them from raw recursion at an hours-scale budget.

---

## 8. Reentrancy and reflection towers

### 8.1 Reflective towers: 3-Lisp, Brown, Blond, Black — SINGLE-PAPER each

- **What.** Each interpreter is itself interpreted by the level above; programs can read and modify their interpreter.
- **Evidence.** Research prototypes; I found no load-bearing use [FM]. Amin and Rompf's Purple realises "a conceptually infinite tower" and cites these as its inspirations [V-abs].
- **Relevance.** Elegant, not shown to pay.

### 8.2 Collapsing towers by staging — SINGLE-PAPER with a shipped analogue

- **What.** A stage-polymorphic evaluator that can either run code or emit code; stacking such evaluators and specialising collapses any number of interpretive levels into one compiled program.
- **Evidence.** Amin and Rompf, POPL 2018 (Pink, Purple) [V-abs] (https://www.cs.purdue.edu/~rompf/papers/amin-popl18.pdf). Measured benefit in a search setting: 6–178× through nested relational interpreters [V]. Shipped analogue: Truffle's partial evaluation of interpreters [V-abs].
- **Failure modes and costs.** Requires binding-time annotations and "small refactorings"; no gain where the staged-on input is unknown [V].
- **Smallest sound version.** Quote/unquote with an explicit "now or later" flag on the evaluator: 200–400 lines [EST]; Common Lisp macros and `compile` cover much of this natively [FM].
- **Relevance.** What made reflection *pay* was removing the cost of levels, not adding levels.

### 8.3 Meta-level search control — mixed

- **Soar chunking and PRODIGY explanation-based learning.** Learned rules can cost more to match than they save: the "utility problem" (Minton 1988) and "expensive chunks" (Tambe 1991). With expensive chunks "no guarantees can be made about Soar's performance"; matching them is NP-hard in the worst case; the remedy was to restrict the expressiveness of what may be learned [V-abs] (https://cdn.aaai.org/AAAI/1996/AAAI96-114.pdf).
- **EURISKO.** Heuristics stored as data and mutated by other heuristics. Lenat and Brown (1984) attribute AM's power to its large stock of heuristics and to its *representation*, concluding that representation "plays a crucial and unique role"; AM's ultimate limit was its "inability to discover new, powerful, domain-specific heuristics" [V-abs] (https://aaai.org/papers/00236-aaai83-059-why-am-and-eurisko-appear-to-work/). A secondary summary records Lenat's concession that enough short Lisp programs will always include some an observer can read as interesting mathematics [V-abs]. The source was recovered and re-run in 2023–24 [V-abs].
- **Rational metareasoning (Russell and Wefald).** Choose the computation with the highest expected value net of cost. The exact policy is intractable; myopic approximations work in game-tree and Monte-Carlo tree search [V-abs] (https://arxiv.org/pdf/1711.06892).
- **What paid off in practice.** (1) Memoisation and dependency tracking. (2) Measured utility for every learned rule — keep it only if matching cost × frequency is below the saving. (3) Myopic budget allocation across strategies. (4) Guidance by a *separate* learned statistical model (DreamCoder's recognition network). **What was only elegant:** infinite towers; heuristics that rewrite heuristics without utility accounting.
- **Smallest sound version.** A table of (strategy, attempts, successes, cost) with a bandit rule: under 150 lines [EST].
- **Relevance.** The owner's two reflection uses split cleanly: "avoid repeated work" is shipped technology; "learn search policies in the same substrate" has a documented failure mode and needs utility accounting from day one.

---

## 9. Graph isomorphism, canonical forms, and subgraph mining

### 9.1 nauty / Traces — SHIPPED

- **What.** Canonical labelling by individualisation and refinement: refine a vertex colouring, pick a vertex to distinguish, recurse, prune using discovered automorphisms.
- **Evidence.** McKay and Piperno, "Practical graph isomorphism, II" (2014) [V-abs] (https://arxiv.org/pdf/1301.1493).
- **Failure modes and costs.** Exponential worst case; hard families are highly symmetric (strongly regular graphs, CFI constructions) [V-abs].
- **Relevance.** Available if literal graphs appear in the data; not needed for terms.

### 9.2 Weisfeiler–Leman hashing — SHIPPED as a filter

- **What.** Iteratively hash each vertex with the multiset of its neighbours' hashes.
- **Failure modes.** Colour refinement "always returns the monochromatic coloring" on regular graphs; the two-dimensional variant cannot separate strongly regular graphs with equal parameters [V-abs] (https://arxiv.org/pdf/2005.08887).
- **Relevance.** Good as a cheap pre-filter or bucket key; never a proof of identity.

### 9.3 When is canonical labelling actually needed?

- **Not needed** for rooted terms with ordered children: hash-consing is already a linear-time canonical form.
- **Easy** for ground terms modulo AC: flatten nested applications, sort children by node id [FM].
- **Easy** for closed terms modulo bound-variable renaming: de Bruijn indices, or hashing modulo α [V-abs].
- **Hard in general** for *patterns with variables* modulo AC and renaming: AC matching is NP-complete [V-abs], and deciding equality of such terms is as hard as graph isomorphism [FM, Basin 1994]. In practice laws have few variables, so trying all variable orderings (k! for k ≤ 5) is affordable [EST].
- **Hard** for unrooted patterns in a large execution graph — which is why rooted matching (3.3) matters.

### 9.4 Frequent-subgraph mining (gSpan) — PROVEN-RESEARCH

- **What.** Enumerate subgraphs by growing a canonical "minimum DFS code", counting support in a database of graphs.
- **Failure modes and costs.** Every exact method "needs to solve many subgraph isomorphism instances"; designed for many small, low-degree graphs such as molecules; does "not scale well" to large single graphs [V-abs] (https://arxiv.org/pdf/1409.1152).
- **Relevance.** For program corpora and execution traces, mine rooted trees or DAGs (Stitch, babble) and avoid general subgraph mining.

**Answer to the owner's hypothetical.** An efficient graph-isomorphism test is not a prerequisite. Hashing is enough wherever the structure is rooted and ordered, which covers terms, traces and frames.

---

## 10. Applied category theory in rewriting and data software

- **What exists.** Catlab/ACSets and AlgebraicRewriting.jl (3.4). DisCoPy: string diagrams in Python, with a hypergraph-based representation for symmetric monoidal categories and a rewriting method; its language-processing origin became a separate library [V-abs] (https://github.com/discopy/discopy). String-diagram rewrite theory (Bonchi, Gadducci, Kissinger, Sobociński, Zanasi): rewriting diagrams is DPO rewriting of hypergraphs with interfaces; a "convex" variant is sound and complete for symmetric monoidal structure; confluence is decidable in that setting [V-abs] (https://arxiv.org/pdf/2104.14686). Categorical Query Language (CQL): functorial data migration, "production-ready for single-node in-memory" workloads, commercialised by one company [V-abs] (https://categoricaldata.net/). ZX-calculus rewriting for quantum-circuit optimisation is the most load-bearing use of diagram rewriting I know of [FM].
- **Maturity.** PROVEN-RESEARCH; small user bases; no learning or induction results.
- **What it buys an implementer.**
  1. *A schema-generic definition of gluing and matching.* Pushout = "merge two structures along a shared part"; pullback = "join on a shared key". One implementation serves every schema.
  2. *Correctness conditions for rewrites.* The dangling and identification conditions say exactly when deleting a matched part leaves a well-formed structure.
  3. *Three canonical ways to move data between schemas* (functorial data migration): re-index along a schema map (projection), push forward by union (quotient), push forward by product (join). These line up with the owner's projection / quotient / lift.
- **What it does not buy.** Speed (matching is still subgraph matching; storage is still indexed tables), a learning algorithm, or a Common Lisp library.
- **Verdict.** Use it as vocabulary and as a source of property tests (universal properties make good oracles). Implement as typed multigraph tables with inverse indexes. Importing a category-theory layer would be an "academic import" of exactly the kind the owner rejected.

---

## 11. Closing: the smallest mature set for one uniform graph store

### 11.1 The set

An **e-graph viewed as a relational table, used without saturation, with example-value columns** — five shipped or proven mechanisms on one node table:

1. **Hash-consed node table**: `(op, child-class-ids…) → class-id`. SHIPPED.
2. **Union-find + congruence closure** over that table. SHIPPED. Rewrites applied eagerly and directionally with a depth bound (Cranelift style). AC handled at interning time by flatten-and-sort, never by rules.
3. **Relational view of the same table**: each operator is a relation with an index on every column, so a pattern is a conjunctive query and the output column's index is the inverse image. SHIPPED as Datalog; PROVEN-RESEARCH as e-matching.
4. **A value vector per class** (its values on the example rows — the existing "frame"). Classes with equal vectors are observationally equivalent; this is a finite tree automaton, hence also a version space. PROVEN-RESEARCH.
5. **A fixed set of lifting combinators** as node operators (`map`/`zip-with`, `fold`, `scan`, bounded `unfold`, `gather`, `filter`), each with an inverse rule. SHIPPED as language design; PROVEN-RESEARCH for synthesis.

Around it, three small services: pair-memoised **anti-unification** with a Stitch-style top-down search (PROVEN-RESEARCH); a **dependency/memo graph** recorded during evaluation (SHIPPED); **propagators** on classes for solving (constraint propagation SHIPPED).

Rough total for the store and services: 2,500–4,000 lines of Common Lisp [EST].

### 11.2 How each requested operation lands

| Operation | Mechanism on the store | Maturity | Cost |
|---|---|---|---|
| Substitution | Instantiate pattern variables, re-intern | SHIPPED | Linear in pattern size |
| Lift | A `map`/`zip-with` node over a container-valued class | SHIPPED (languages); PROVEN (synthesis) | Linear in container |
| Projection | Column projection / component-select node | SHIPPED | Constant |
| Fibre / preimage | Index lookup on the output column; per-operator inverse rule | SHIPPED with hand-written inverses | Index lookup; inverse-specific |
| Anti-unification | Memoised walk over class pairs | SHIPPED (syntactic) | Product of the two sizes, worst case |
| Equivalence-merging | Union-find + congruence repair | SHIPPED | O(n log n) |
| Guards | Selection on value columns; guarded-law rows | Selection SHIPPED; conditional *merging* is research | Linear scan or index |
| Solving | Top-down through inverse rules + bottom-up with value-vector merging; propagators | SHIPPED / PROVEN | Exponential in depth; pruned by merging |

### 11.3 Budget calibration for "hours, single-threaded"

- Corpus compression at Stitch/babble scale (hundreds of programs, tens of thousands of nodes): seconds to minutes. Comfortable.
- Combinator-level synthesis of small functions (λ² scale): sub-second to minutes. Comfortable.
- Law discovery by testing small terms (QuickSpec/Ruler scale): minutes [FM for typical run times].
- Rediscovering recursion schemes from raw recursion (DreamCoder scale): about 7,700 CPU-hours. Out of reach by roughly three orders of magnitude.
- Equality saturation with AC and distributivity beyond about 10–15 operands: out of reach at any budget (3^n).

### 11.4 Owner's wishes with NO mature precedent

1. **Learning the inverses.** Witness functions and combinator deduction rules are hand-written in every shipped system. Automatically learning inverse semantics and feeding them back has no mature precedent that I found.
2. **A closed bootstrapping loop** in which discovered laws, solvers and abstractions become primitives for the next round on the *same* store. Pieces exist separately (QuickSpec/Ruler for laws, Stitch/babble for abstractions, DreamCoder for the loop with a neural guide); nobody has shipped the union.
3. **Reentrancy as free movement between abstraction levels on one graph** (execution graph, data graph and syntax graph treated alike, with rules that rewrite rules). AtomSpace/MeTTa is the main attempt and has no quantitative success. The mature fragments are homoiconicity and staging.
4. **Conditional equalities with learned guards inside a merged store.** Colored e-graphs are one group's work; contextual reasoning is an open research thrust as of January 2026.
5. **Binders inside a merged store.** Slotted e-graphs date from 2025. The mature route is to avoid binders with combinators.
6. **Lift as a native operation of a graph *store*** (as opposed to a language). The first step — multiset containers with higher-order `map`/`fold` in egglog — is from February 2026 and lists its own limitations.
7. **Same-substrate learned search policy.** The precedents (Soar, PRODIGY, EURISKO) are the source of the utility-problem warnings. The mature version uses a separate statistical model or a bandit.
8. **Deriving algebra from depth-two interventions on a program simulator.** Control-variable experiments are proven for numeric laws; test-based law discovery is proven for equations over given functions; combining them to induce the *algebra of expression space itself* is not something I found.
9. **Anti-unification as a literal quotient.** The one categorical treatment makes it a product; the quotient is unification/merging. No operational system implements AU as a pushout.

Items 1, 2 and 8 are where the project would be doing research. Items 3–7 can be avoided or deferred by design choices that stay inside mature territory.

---

## 12. Negative results and cautionary tales

1. **Cranelift, 2026.** After three years in production, e-graph multi-representation contributes about 0.1%; average class size is 1.13. Keeping many equivalent forms rarely matters when rules are simplifications [V].
2. **AC saturation is 3^n.** Proven counts, not folklore [V].
3. **Equality-saturation run time is unpredictable**; resource limits make *results* unpredictable; adding rules can disable earlier optimisations [V].
4. **Extraction is NP-hard and inapproximable** when sharing counts [V-abs].
5. **Relational interpreters are "impractical for most applications"** in their authors' words; tiny tasks time out at five minutes unstaged [V].
6. **DreamCoder's compute.** Five days on 64 CPUs for one domain when recursion must be discovered; Stitch showed the compression step alone was 3–4 orders of magnitude too slow [V-abs, V].
7. **λ² without types:** more than 60% of benchmarks time out. Pruning by types (or an equivalent) was load-bearing, more so than deduction [V].
8. **Myth's trace-completeness requirement:** explicit recursion needed examples for every recursive call [V-abs].
9. **The utility problem** (Soar, PRODIGY): unconstrained rule learning made systems slower; the fix was to restrict what could be learned and to measure utility [V-abs].
10. **AM and EURISKO:** by the author's own analysis the apparent discoveries leaned on a representation in which short programs happened to denote interesting concepts; heuristic-generated heuristics were mostly useless [V-abs].
11. **OpenCog / Hyperon:** roughly 17 years of a uniform hypergraph store without a published quantitative learning result; the first MeTTa interpreter was hundreds of times slower than a Prolog transpilation [V-abs].
12. **Optimal reduction** has non-elementary worst-case cost; the practical interaction-net runtime admits quadratic slow-downs and its synthesis claims are unpublished [V-abs].
13. **babble:** needs a human-supplied theory, is incomplete, and is quadratic in corpus size [V].
14. **E-generalisation:** infinite generalisation sets for arbitrary theories; the survey authors note weak foundations [V-abs].
15. **Category-theoretic rewriting code** "generally performs poorly on large problems" when written for provable correctness [V-abs].
16. **Classic incremental computation** was sometimes slower than recomputing from scratch until node naming was fixed [V-abs].
17. **Observational equivalence** silently becomes unsound with side effects or context-dependent meaning [V-abs].

---

## 13. What I could not verify

- Kahl's paper text (blocked by bot protection); the product/pushout statement rests on a search summary.
- Slotted e-graphs' overheads and limitations (abstract only).
- Complexity of the Wolfram SetReplace matcher (no source found).
- Typical program sizes reachable by Popper and other inductive-logic-programming systems.
- Real-world, non-toy deployments of general propagator networks.
- The internal use of anti-unification in Getafix, and of congruence closure in QuickSpec (both from memory).
- Exact line counts of minimal e-graphs; all LOC figures are my estimates.
- Run-time figures behind babble's "1–2 orders of magnitude faster than DreamCoder" claim (in a figure not extractable as text).

---

## 14. Sources consulted (verified this session)

E-graphs
- Fallin, "The acyclic e-graph: Cranelift's mid-end optimizer", 2026-04-09 — https://www.cfallin.org/blog/2026/04/09/aegraph
- Rosin, Ullrich, Hack, "Associativity and Commutativity in Equality Saturation", EGRAPHS 2026 — https://compilers.cs.uni-saarland.de/papers/ullrich_egraphs2026-paper17.pdf ; https://arxiv.org/abs/2610.01198
- "Parameterized Complexity of Running an E-Graph", 2025-06-16 — https://uwplse.org/2025/06/16/egraph-complexity.html
- "Custom Data Structures in E-Graphs", 2026-02-24 — https://uwplse.org/2026/02/24/egglog-containers.html
- Panchekha, micro-egg guide, 2026-06-16 — https://pavpanchekha.com/blog/microegg.html
- Zucker, "A Simplified E-graph Implementation", 2021 — https://philipzucker.com/a-simplified-egraph/
- Bernstein, "What's in an e-graph?" — https://bernsteinbear.com/blog/whats-in-an-egraph/
- egg — https://arxiv.org/abs/2004.03082 ; Relational e-matching — https://arxiv.org/abs/2108.02290 ; egglog — https://arxiv.org/pdf/2304.04332
- Slotted e-graphs — https://pldi25.sigplan.org/details/pldi-2025-papers/77/ ; Colored e-graphs — https://arxiv.org/pdf/2305.19203 ; contextual — https://arxiv.org/pdf/2507.11897
- Extraction via treewidth — https://arxiv.org/pdf/2408.17042 ; e-boost — https://arxiv.org/pdf/2508.13020
- Dagstuhl 26022 — https://www.dagstuhl.de/26022 ; EGRAPHS 2026 — https://pldi26.sigplan.org/home/egraphs-2026
- Semantic foundations of equality saturation — https://arxiv.org/pdf/2501.02413
- Herbie rules count — https://arxiv.org/pdf/2410.14025

Library learning and anti-unification
- babble — https://ar5iv.labs.arxiv.org/html/2212.04596
- Stitch — https://ar5iv.labs.arxiv.org/html/2211.16605
- E-Stitch — https://pldi26.sigplan.org/details/egraphs-2026-papers/7/E-Stitch-Top-Down-Library-Learning-for-E-Graphs
- DreamCoder — https://arxiv.org/pdf/2006.08381 ; LILO — https://arxiv.org/html/2310.19791v4
- Cerna and Kutsia survey — https://arxiv.org/abs/2302.00277
- Higher-order pattern AU — https://link.springer.com/10.1007/s10817-016-9383-3
- Burghardt, E-generalisation — https://arxiv.org/pdf/1403.8118 ; https://arxiv.org/pdf/1709.00744
- Kahl — https://ifip.hal.science/hal-02364568v1 (not readable)
- Getafix — https://arxiv.org/abs/1902.06111

Graph stores and rewriting
- Hyperon overview — https://arxiv.org/abs/2310.18318 ; PeTTa thread — https://swi-prolog.discourse.group/t/metta-language-transpiler-petta/9490 ; MORK — https://github.com/trueagi-io/MORK
- OpenCog list on MOSES/AtomSpace — https://www.mail-archive.com/opencog@googlegroups.com/msg00662.html
- GP 2 — https://arxiv.org/pdf/2501.09144 ; https://eprints.whiterose.ac.uk/179084/
- GrGen — https://en.wikipedia.org/wiki/GrGen
- ACSets — https://arxiv.org/abs/2106.04703 ; Computational category-theoretic rewriting — https://arxiv.org/pdf/2111.03784
- SupGen thread — https://leanprover-community.github.io/archive/stream/113488-general/topic/SupGen.html
- Asperti, efficient reduction of lambda terms — https://arxiv.org/pdf/1701.04240
- Doop/Soufflé — https://github.com/plast-lab/doop ; Popper — https://arxiv.org/pdf/2005.02259
- String-diagram rewrite theory II — https://arxiv.org/pdf/2104.14686 ; DisCoPy — https://github.com/discopy/discopy ; CQL — https://categoricaldata.net/

Relational, bidirectional, synthesis
- Multi-stage relational programming (full text) — https://namin.seas.harvard.edu/pubs/pldi-staged-mk.pdf
- Radul thesis — https://dspace.mit.edu/handle/1721.1/49525
- FlashMeta — https://www.microsoft.com/en-us/research/publication/flashmeta-a-framework-for-inductive-program-synthesis/
- Dace — https://arxiv.org/pdf/1707.01469 ; Blaze — https://arxiv.org/pdf/1710.07740 ; ECTA — https://arxiv.org/abs/2206.07828
- VSAs are acyclic tree automata — https://arxiv.org/pdf/2107.12568 ; e-graphs as DFTAs — https://github.com/egraphs-good/egg/discussions/104
- Observational equivalence — https://arxiv.org/pdf/2511.02491
- λ² (full text) — https://www.cs.utexas.edu/~swarat/pubs/pldi15.pdf
- Paramorphism synthesis — https://api.crossref.org/works/10.1145%2F3656381
- Synthesizing lenses — https://www.cs.princeton.edu/~dpw/papers/synthesizing-lenses-popl2018.pdf
- Parsynt — https://www.cs.toronto.edu/~azadeh/resources/papers/pldi17.pdf
- Naperian functors — https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.pdf ; Remora — https://arxiv.org/pdf/1907.00509 ; Futhark — https://www.futhark-lang.org/publications/pldi17.pdf

Traces, dependence, discovery
- Provenance semirings — https://www.cs.ucdavis.edu/~green/papers/pods07.pdf
- miniAdapton — https://arxiv.org/pdf/1609.05337 ; Nominal Adapton — https://arxiv.org/pdf/1503.07792 ; Salsa — https://rustc-dev-guide.rust-lang.org/salsa.html
- Truffle partial evaluation — https://research.jku.at/en/publications/practical-partial-evaluation-for-high-performance-dynamic-languag/
- Trace-guided synthesis — https://www.microsoft.com/en-us/research/publication/trace-guided-inductive-synthesis-of-recursive-functional-programs/ ; partial traces — https://arxiv.org/pdf/2504.14480
- BACON — https://ijcai.org/proceedings/1977/77 ; CVGP — https://www.cs.purdue.edu/homes/yexiang/publications/ecml23-cvgp.pdf ; VSR — https://arxiv.org/pdf/2312.11955
- AI Feynman — https://arxiv.org/pdf/1905.11481 ; 2.0 — https://arxiv.org/pdf/2006.10782
- Causal program dependence analysis — https://research.chalmers.se/en/publication/542881
- QuickSpec — https://www.cse.chalmers.se/~jomoa/papers/quickspec-JFP.pdf ; Ruler — https://arxiv.org/pdf/2108.10436

Reflection and meta-level control
- Collapsing towers — https://www.cs.purdue.edu/~rompf/papers/amin-popl18.pdf
- Expensive chunks — https://cdn.aaai.org/AAAI/1996/AAAI96-114.pdf
- Why AM and EURISKO appear to work — https://aaai.org/papers/00236-aaai83-059-why-am-and-eurisko-appear-to-work/ ; https://en.wikipedia.org/wiki/Eurisko
- Learning to select computations — https://arxiv.org/pdf/1711.06892

Isomorphism and mining
- Practical graph isomorphism II — https://arxiv.org/pdf/1301.1493
- Weisfeiler–Leman limits — https://arxiv.org/pdf/2005.08887
- Hashing modulo α — https://arxiv.org/pdf/2105.02856
- Congruence closure — https://www.cs.upc.edu/~oliveras/lpar03.pdf ; https://www.cs.upc.edu/~roberto/papers/IC06.pdf
- Frequent-subgraph mining scalability — https://arxiv.org/pdf/1409.1152
