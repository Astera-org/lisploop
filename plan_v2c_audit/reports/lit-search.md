# Literature review: search, discovery, library learning, reflection

Researcher: `lit-search`. Date: 2026-11-24. Purpose: a calibrated account of what has been shown to work, at what compute, and what has not, for an LLM-free, single-threaded, enumerative kernel that is meant to bootstrap laws, guards, inverses, transformers and higher-order functors from a simulator.

**How to read the evidence tags.** A number with a URL was read in the source today, by me or by one of four sub-researchers I directed (their full notes are the appendices; Section E says which sources I read first-hand and which I spot-checked). FROM-MEMORY marks anything not verified online. ESTIMATE marks my own arithmetic. Maturity tags: SHIPPED (in a product or widely used tool), PROVEN-RESEARCH (several independent implementations), SINGLE-PAPER, SPECULATIVE. All lines-of-code figures are estimates.

## Bottom line

1. **Algebraic law discovery by testing is solved engineering, and it is cheap.** QuickSpec-family systems find the complete set of non-redundant equational laws up to term size 7–9 over 5–33 functions in seconds to 42 minutes on one thread. This part of the owner's vision does not need hours, and is not a research risk.
2. **The decisive mechanism is using laws already found to shrink the term space before testing anything.** Measured value: over 250× in time (Ruler: 350 s vs more than 24 h) and about 1000× in tests (QuickSpec). Observational-equivalence dedupe and typing come next. Search-order cleverness is a distant fourth.
3. **Conditional laws with searched guards work at small guard sizes only**: guards of size ≤ 4 (Speculate), or a supplied predicate vocabulary with implication pruning (Chompy, 26 minutes for a 14-operator grammar; without implication pruning it does not finish in hours).
4. **Guards from failures have a standard recipe** (run on stratified small inputs, find mixed-label buckets, synthesise one separating predicate, learn a small Boolean combination, attack it). It always needs a predicate grammar, a larger grammar measurably hurts, and timeouts are not facts. No one has learned termination guards from timeouts.
5. **Enumeration reach** (estimate anchored on verified points; one hour, with dedupe, at 10^6 candidate evaluations per second): about 17 AST nodes over ~10 primitives, 10 over ~30, 7 over ~100. A metered interpreter at 10^5 per second loses 1–2 nodes. Ten hours adds 2, 1.3 and 0.85 nodes respectively. Memory runs out before time does. Published timeouts are almost all between 1 minute and 2 hours per task, and the few long runs on record do not show hours finding qualitatively different things from minutes: DreamCoder's own baseline of 24 hours of pure enumeration per task (up to 400 million programs) lost in every domain to the learned system, which solved its tasks in a mean of 54 seconds.
6. **Recursive list functions of 15–30 nodes are found in under a second only when the component context is hand-minimised per task.** Five extra helper functions cost two to three orders of magnitude.
7. **Library learning without a neural network roughly doubles solve rates over plain enumeration and then plateaus.** The single existing from-scratch bootstrap to higher-order functors (DreamCoder's "origami" run, no neural net) took about 7,700 CPU-hours on 20 hand-chosen tasks, and its authors wrote "We do not advocate such blank-slate learning as a route to AI".
8. **Every measured bootstrap depended on a dense, graded task set supplied from outside.** No system invents its own curriculum and benefits.
9. **"Reflection" has no convincing precedent as a compounding mechanism.** Its direct ancestor, EURISKO, is the field's best-documented cautionary tale. What does work is fixed-form learning from *explainable* failures (clause learning, conflict counters), with strict utility accounting.
10. **Inverses** are found as laws when they are short compositions, and by skeleton-guided search for programs of 5–25 lines. Inverse semantics are hand-written in every synthesiser checked. No system has invented an autocorrelation-class recogniser from data without neural guidance or 10^12-scale evolution.
11. **A 1000× faster evaluator buys 2–5 nodes** at realistic grammar sizes, plus threshold effects that make some algorithms usable at all. Where pruning and hardware were measured on the same task, pruning won by two orders of magnitude.
12. **A simulator gives two cheap exponent-reducers that data-only systems lack**: AI Feynman's symmetry and separability tests as exact oracle experiments that decompose a target before enumeration, and null-space computation over term value vectors for linear and conserved relations.


## 1. Theory exploration: law discovery by testing

This is the closest precedent for "algebra from experiments on the simulator", and it is the most mature part of the whole picture. The systems below share one recipe; the differences are in how redundancy is pruned and how conditions are handled.

### 1.0 The common recipe (QuickSpec 2 formulation, verified against the JFP paper)

Source: Smallbone, Johansson, Claessen, Algehed, "Quick specifications for the busy programmer", JFP 2017, https://www.cse.chalmers.se/~jomoa/papers/quickspec-JFP.pdf

State is `(E, T)`: discovered equations `E` and a set `T` of *candidate terms* (one representative per observed equivalence class). Terms are enumerated in size order and each is "considered":

1. **Build only from representatives.** A new term is generated only if all its proper subterms are in `T`. On the pretty-printer signature this alone takes the terms of size ≤ 9 from about 10^6 to about 10^4.
2. **Prune before testing.** Normalise the new term `t` with `E` (QuickSpec 2 uses Knuth-Bendix completion to turn `E` into a rewrite system; QuickSpec 1 used congruence closure over ground instances). If `norm(t)` is already in `T`, discard `t` untested.
3. **Test terms, not equations.** Otherwise evaluate `t` on random inputs and walk a decision tree keyed on results. If it lands in an empty leaf, `t` becomes a new representative; "typically 10 or so" test cases suffice. If it lands on representative `u`, conjecture `t = u`, test it thoroughly (default 1000 cases), emit it, add it to `E`, and renormalise `T`.
4. **Schemas.** Enumerate term shapes with holes; test the one-variable instance first (`(x++x)++x = x++(x++x)`), and only if that law holds, instantiate the most general version. A multi-variable law can hold only if its one-variable instance holds.
5. Laws come out smallest-first, so every printed law is non-derivable from smaller ones (up to the pruner's power).

Consequences the paper states: runtime is proportional to the number of *explored terms*, not the n^2 candidate equations; testing effort is proportional to the number of *discovered laws*; "well over 99%" of true equations between enumerated terms are redundant; interleaving pruning with testing saves "a factor of 1000" in tests in common cases.

### 1.1 QuickSpec 1 (Claessen, Smallbone, Hughes, TAP 2010)

- (i) Enumerate all terms to a depth limit, partition by random testing, emit all equations between class members, then prune by congruence closure.
- (ii) Depth "usually 3 or 4"; universe "typically 1000 to 50.000 terms"; 5,000–50,000 raw equations before pruning; the depth optimisation cut one example from 7,395 terms to 449. Source: https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quickspec.pdf
- (iii) Runs out of memory on the JFP examples (12 GB on the pretty printer at depth 4); user must fix the number of variables per type; no polymorphism.
- (iv) PROVEN-RESEARCH (superseded). (v) ~1–2 kLOC Haskell (FROM-MEMORY). (vi) Shows what *not* to do: test-then-prune.

### 1.2 QuickSpec 2 (JFP 2017)

- (i) The recipe in 1.0.
- (ii) Measured, all verified in the paper:
  - Pretty printer (4 combinators plus background string/arithmetic functions), terms to size 9: 16 laws, about 25,500 tests, 6–7 s. QuickSpec 1 on the same: 110,000 terms, 75 million tests, 1,200 s and out of memory before finishing.
  - Functional geometry (7 combinators), size 7: 25 s, 18 laws, 68,000 tests. QuickSpec 1: abandoned after 2 hours.
  - Octonions, size 7: 3 s vs 15 minutes.
  - **Stress test, 33 list functions, size 7: about 42 minutes, 398 laws, over 50,000 terms, about 874,000 tests.** At size 8 it "starts to run out of memory and slows to a crawl" and hits the 2-hour timeout; with 26 functions size 8 completes within 2 hours with 586 laws.
- (iii) Failure modes stated: "It does, however, generate too many laws" on big signatures (uninteresting consequences of truncating `zip`, etc.); memory, not time, is the binding limit; laws are only tested, not proved; idempotent/AC operators need special handling; ordering by size sometimes prints a law that a later one generalises.
- **Conditional laws:** the user names the predicate. QuickSpec wraps it as a new type whose generator produces only satisfying values (`suchThat`), turning `p(xs,ys) ⟹ l = r` into an unconditional law over projections of that type. The authors say plainly why they do not search for conditions: the space is "several orders of magnitudes larger than for unconditional equations" and "pruning for conditional equations is much more difficult ... we would need full first-order logic reasoning".
- (iv) **SHIPPED** as a library (Hackage `quickspec`; used inside HipSpec, Hipster, and in 2024 inside Vampire's induction pipeline: QuickSpec lemmas raised proofs found by 130%, 183% with trained strategy schedules — Einarsdóttir et al., IJCAR 2024, https://www.cse.chalmers.se/~slrn/papers/LDSAI_IJCAR_2024.pdf). Note Hackage reports the 2.2.1 build failing as of Aug 2026.
- (v) Smallest sound version: size-ordered enumeration over representatives + value-vector decision tree + a normaliser. With ground congruence closure instead of completion: roughly 500–1,000 lines of Lisp. Completion (Twee) is the expensive part to write; an e-graph or plain "rewrite with oriented laws, smallest-first" is the cheap substitute.
- (vi) This is the engine the owner's "algebra emerges from experiments" needs; it already exists and its limits are measured.

### 1.3 Speculate (Braquehais & Runciman, Haskell 2017)

Source: https://eprints.whiterose.ac.uk/129495/1/speculate_v3.0_20170717_camera_ready.pdf

- (i) QuickSpec-style equations by enumerative (LeanCheck) testing, plus inequalities (`≤`) between class representatives, plus **conditional equations whose conditions are searched automatically**.
- (ii) Defaults: expressions to size 5, inequalities to size 4, conditions to size 4, 500 tests. Measured growth for the `(+), abs, 0, 1, id` example (their Table 4):

  | size limit | exprs (2 vars) | classes (2 vars) | exprs (3 vars) | classes (3 vars) |
  |---|---|---|---|---|
  | 3 | 44 | 12 | 60 | 18 |
  | 5 | 748 | 36 | 1,180 | 68 |
  | 7 | 16,492 | 114 | 30,285 | 287 |

  Raw expressions grow about 4.7× per unit of size; observationally distinct classes grow about 1.7–2× per unit.
  Runtimes (their Table 6, 2.2 GHz 4-core PC): `(+)`/`abs` size 5: 3 s; size 6 with 3 variables: 2 min 37 s (43 equations, 44 inequalities, 24 conditional equations). Regular expressions (slow evaluator; test count lowered from 500 to 200 as size grows): size 3: 1.5 min; size 4: 9 min; size 5: 17 min; size 6: 1 h 26 min; **size 7 with inequalities also to size 7: 2 days 22 h 30 min** (130 equations, 699 inequalities).
- **How conditions are found (the precise mechanism):** Boolean-typed class representatives are the candidate conditions. The already-discovered `≤` relation on Booleans is implication, giving a digraph of conditions ordered by strength. For each pair of representatives `e1, e2` from *different* classes, pick an unmarked condition `c`; test `c ⟹ e1 = e2`; if all tests pass, mark `c` and delete every strictly stronger condition; if any fails, delete `c` and every weaker condition. What remains are the weakest conditions. A conditional law is discarded if another one with an implied-weaker condition exists.
- (iii) "The algorithm is sound modulo testing"; cost is quadratic in the number of class representatives times the number of conditions, hence the smaller size limit for conditions; needs enough test values satisfying sparse conditions; the regex example shows the wall (one extra size unit: 1.5 hours to 3 days).
- (iv) SINGLE-PAPER tool, but the mechanism is a straightforward extension of a PROVEN recipe and Chompy (1.6) independently re-derives the same idea. (v) ~3 kLOC Haskell (FROM-MEMORY); the conditional part is ~200 lines over an existing explorer. (vi) Direct template for "guards = regions where the law holds", with honest cost numbers.

### 1.4 IsaCoSy, IsaScheme, HipSpec, Hipster (2010–2017)

- (i) IsaCoSy generates only irreducible terms via constraints and proves by induction; HipSpec/Hipster run QuickSpec, then try to prove conjectures by structural induction, feeding proved lemmas back.
- (ii) HipSpec uses QuickSpec at term depth "usually 3" with "usually 2-3" variables per type (verified, https://www.cse.chalmers.se/~jomoa/papers/hipspec-cade.pdf). QuickSpec 1 authors report their examples "take seconds to run, while comparable examples in [IsaCoSy's] setting take hours" (verified in the QuickSpec 1 PDF).
- (iii) HipSpec reports insertion-sort equations "not proved because they require conditional lemmas"; proof, not conjecturing, is the bottleneck.
- (iv) PROVEN-RESEARCH. (vi) Relevant only if the kernel wants proof rather than testing; conjecturing-by-testing is the cheap part.

### 1.5 TheSy (Singher & Itzhaky, CAV 2021) and CCLemma (Kurashige et al., ICFP 2024)

- (i) TheSy replaces concrete testing with *symbolic observational equivalence*: terms are run on small symbolic constructor inputs inside an e-graph; terms that merge for all symbolic inputs give conjectures, which a one-level structural induction prover then proves. CCLemma makes exploration goal-directed from a target proof.
- (ii) TheSy explores to term depth **k = 2** with two placeholders per type. On 85 TIP benchmarks (1 h timeout): median 5.28 s vs Hipster's 305 s, but total time roughly equal (51.6k s vs 47.1k s) because of a slow case-splitting tail. Proves 187 of 311 CVC4 induction benchmarks in 5 min each. Source: https://ar5iv.labs.arxiv.org/html/2009.04826 . CCLemma: 60 s limit; "none of the four tools are able to prove more than 30%" of its optimisation benchmark (https://par.nsf.gov/servlets/purl/10555783).
- (iii) TheSy authors: larger k "greatly affects the run-time, but does not lead to many useful lemmas"; equalities only; case splitting dominates cost.
- (iv) SINGLE-PAPER each (two related implementations). (vi) Evidence that depth 2 is where symbolic exploration lives, and that undirected deepening has rapidly diminishing returns.

### 1.6 Ruler, Enumo, Chompy: rule synthesis for e-graph optimisers (2021–2026)

**Ruler** (Nandi et al., OOPSLA 2021, https://arxiv.org/pdf/2108.10436):
- (i) Enumerate terms into an e-graph by number of connectives; tag each e-class with a characteristic vector ("cvec") of values on sample inputs; e-classes with equal cvecs are candidate rules; pick the best by a syntactic score, validate (model check / SMT / fuzz), then **run the accepted rules on the term e-graph itself** to collapse it before the next round.
- (ii) Single-threaded AMD 3900X, 3 variables (their Table 1):

  | domain | ops in grammar | connectives | time | rules |
  |---|---|---|---|---|
  | bool | 4 | 3 | 0.06 s | 28 |
  | bv4 | 9 | 2 / 3 | 0.14 s / 4.3 s | 49 / 272 |
  | bv32 (Z3-validated) | 9 | 2 / 3 | 13 s / 630 s | 46 / 188 |
  | rationals (`+ − × / abs neg`, fuzz-validated) | 6 | depth 2 | 18 s | 50 |

  Compared with CVC4's enumerator: 5.8× fewer rules, 25× faster (harmonic means), with ~equal proving power. **Ablation: without shrinking the term space with learned rules, the rational run "did not complete in 24 hours; with [it], it completed in 350 seconds".**
- (iii) Stops at 3 connectives; no conditional rules; complete enumeration only; with fuzzing as the validator one configuration produced unsound rules (e-graph "soundiness" crashes catch most).
- (iv) PROVEN-RESEARCH. Ruler, Enumo and Chompy share authors, but CVC4's `--sygus-rr-synth` and TASO (1.7) are independent implementations of the same enumerate, fingerprint, verify recipe; Isaria (ASPLOS 2024) builds a vectorising compiler on Ruler's output; the Herbie case study found Ruler's rules as good as the hand-written ones.

**Enumo** (Pal et al., OOPSLA 2023; extended version arXiv 2609.14527, Sept 2026):
- (i) A DSL in which a *human* programs the exploration: which sub-grammars to enumerate, to what size, which rules to assume.
- (ii) On Halide's grammar (boolean + arithmetic + comparison + min/max/select), verified in the extended paper: Ruler "was able to run for just one iteration (further iterations did not terminate)", giving 90 rules that derive 18 of 725 hand-written rules (2.5%). Exhaustive enumeration to size 5 derives 327 of 725. Exhaustive enumeration is "computationally infeasible" beyond 5 atoms on operator subsets and 4 atoms on the full operator set. A hand-written 141-line guided program reached 840 rules deriving 84.0–90.9% of the 725. "Fast-forwarding" found 4 trigonometric identities in about 3 minutes from hand-chosen seed rules.
- (iii) The reach beyond size 5 came from human-authored workloads (e.g. hand-picking the shape `(select a (min b c) (max d c))`), not from more compute.
- (iv) SINGLE-PAPER tool on a PROVEN recipe.

**Chompy** (Cheung, Nandi, Lerner, FMCAD 2026, https://repositum.tuwien.at/handle/20.500.12708/230508):
- (i) Conditional rule synthesis: enumerate a separate workload of *predicates* and evaluate them to Boolean vectors ("pvecs"); two terms are a conditional candidate under predicate `p` if their cvecs agree wherever `p`'s pvec is true; candidate implications between predicates are found by pvec matching (`∀i. a_i ⇒ b_i`), validated by SMT, and saturated ("implication propagation") so that a rule whose condition implies a more general rule's condition is pruned.
- (ii) Grammar of 14 operators (`+ - * / % min max < <= > >= == != &&`). Full run: **1,551.7 s, 1,579 rules**; derives 73.3% of Caviar's 45 and 57.1% of Halide's 84 hand-written conditional rules. Without implication propagation it did not terminate "even after running for several hours" (3,931 rules at the last log). Conditional synthesis is 96.9% of the runtime. An LLM-only baseline recovered 9.8% / 3.1%.
- (iii) Evaluated on derivability only, not downstream effect; conditions limited to the supplied predicate workload.
- (iv) SINGLE-PAPER (2026), but it is the third appearance, from three unrelated groups, of the same idea: find the weakest predicate whose true-set lies inside the set of inputs on which the two sides agree (Speculate 2017, Alive-Infer 2017, Chompy 2026).

- (v) Smallest sound version of the Ruler family: an e-graph (300–600 lines), cvec analysis, cvec grouping, rule selection, validation by exhaustive small-domain check. About 1.5–2.5 kLOC. Without an e-graph, QuickSpec's normaliser gives the same pruning effect.
- (vi) The owner asks whether e-graphs are affordable: measured, they are, at 2–3 connectives and ≤ ~15 operators. The pruning-by-learned-laws ablation (350 s vs > 24 h) is the single strongest piece of evidence in this section.

### 1.7 Other rule-discovery systems that shipped

- **Halide TRS synthesis** (Newcomb et al., OOPSLA 2020, https://inst.eecs.berkeley.edu/~cs294-260/sp24/papers/verifying-halide-trs.pdf). Workload-driven: harvest left-hand-side patterns from >100,000 expressions the simplifier is stuck on, CEGIS a smaller right-hand side with Z3, synthesise a predicate if needed. 4,127 rules synthesised. Ablation test: of 321 hand-written rules removed one at a time, the synthesiser re-found 186 (58%); 15 failures were predicate-synthesis failures, 10 timeouts. SHIPPED-adjacent (run by Halide developers).
- **TASO** (Jia et al., SOSP 2019). Enumerate all tensor-operator graphs up to 4 operators (about 66 million graphs), fingerprint by hashing outputs on random inputs, verify candidates against hand-written operator axioms; about 29,000 substitutions reduce to 743 after pruning (course-slide figures, https://www.cl.cam.ac.uk/~ey204/teaching/ACS/R244_2020_2021/presentation/S7/Samuil_TASO.pdf). SHIPPED. Hard cap: 4 operators.
- **Bansal & Aiken peephole superoptimiser** (ASPLOS 2006). Enumerates x86 sequences **only up to length 3**, fingerprints about 500,000 sequences/s on test vectors, canonicalises registers/constants (50–60× space reduction at length 3), stores results in a fingerprint-indexed database that is then reused as an optimiser (1.7–10× on small kernels). A working example of search results being banked and reused.
- **Equational Theories Project** (Tao et al., 2024–2025, https://arxiv.org/html/2512.07087v2). All 22,028,942 implications among the 4,694 magma laws with at most 4 operations were settled and Lean-checked. Brute force over every magma of size ≤ 4 (about 4.3×10^9 magmas, **165 CPU-hours**) refuted 61.9% of all implications, i.e. 96.3% of the false ones (size 3 alone did 13.3M of 13.6M); size 5 (about 3×10^17) was infeasible and random sampling there found almost nothing. Duality and transitive closure left only 10,657 positive implications needing a direct (ATP) proof. "Perhaps two dozen" refutations needed ad hoc human constructions; one took "several months". The cleanest modern statement of the pattern: *exhaustive search over tiny models plus closure handles the bulk; the tail needs invention and no amount of the same brute force reaches it.*

### 1.8 What this section establishes

1. Unconditional equational laws over 5–30 functions, up to term size 7–9, 3 variables: **seconds to an hour, single-threaded, shipped.** This is not a research risk.
2. The decisive mechanism is not the enumerator; it is **using the laws already found to shrink the term space before testing** (QuickSpec's normal-form check; Ruler's `run_rewrites`). Measured value: 100× to more than 250× in time, 1000× in tests.
3. One more unit of term size costs roughly 2–6× in Speculate's regex table at comparable settings, and 49× for the step that also turned on inequalities; QuickSpec at 33 functions runs out of memory between size 7 and 8. **Hours buy one or two more size units over minutes, no more.**
4. Conditional laws with *searched* guards work at condition size ≤ 4 over a small predicate vocabulary (Speculate), or with a supplied predicate workload (Chompy: 26 minutes for a 14-operator grammar). Implication structure between conditions is mandatory to avoid drowning (Chompy without it: no termination in hours).
5. Past size ~5 on a 15-operator grammar, published successes come from *workload guidance* (terms harvested from real expressions: Halide, Bansal-Aiken; or hand-written: Enumo), not from longer exhaustive runs.

## 2. Scientific-law discovery by controlled experiment

The owner's phrase "holding all but a few constant" is BACON's method verbatim. The lineage is old, the demonstrations are small, and the well-known systems all needed a neural interpolant or a genetic search *only because they had data rather than a simulator*. With an exact oracle most of their machinery becomes a set of direct queries.

### 2.1 BACON.1–BACON.5 (Langley, Simon, Bradshaw, Zytkow, 1978–1987)

- (i) Data-driven heuristics over a table of observations: vary one independent variable with the others held fixed; note constancies, linear relations and monotonic trends; when two terms rise together consider their ratio, when one rises as the other falls consider their product; treat the constants found at one level as dependent variables at the next level up. BACON.4 postulates intrinsic properties for nominal variables; BACON.5 adds symmetry/analogy reasoning and does not re-vary a term already explained.
- (ii) Verified from the IJCAI-81 BACON.5 paper (https://ijcai.org/proceedings/1981/0026.pdf): five heuristics, "noting constancies; finding linear relations; detecting monotonic trends; postulating intrinsic properties; and reasoning by analogy". The laws rediscovered (Kepler's third, ideal gas, Coulomb, Ohm, Snell, Black, momentum conservation) have at most about five variables and small integer exponents (list FROM-MEMORY).
- (iii) The authors' own limits: "it cannot adequately deal with noise; it cannot handle irrelevant variables; and the class of laws it considers is overly constrained", and "the program was only presented with terms relevant to the final law". External critique (Chalmers, French, Hofstadter, https://consc.net/papers/highlevel.pdf): it "works only in a world of hand-picked, prestructured data".
- (iv) PROVEN-RESEARCH as a method (several versions and descendants); never a general discovery engine.
- (v) A few hundred lines.
- (vi) What transfers: the *experimental schedule* (vary one, hold the rest, recurse level by level) and the rule of not re-varying solved terms. With an exact simulator the noise problem disappears. What does not transfer: the greedy ratio/product term generator; replace it with the Section 1 enumerator.

### 2.2 FAHRENHEIT (Zytkow, 1987–1990) and ABACUS (Falkenhainer & Michalski, 1986)

- FAHRENHEIT (https://cdn.aaai.org/AAAI/1990/AAAI90-133.pdf, verified): after finding a law it "searches for the scope of the laws it has discovered", and looks for "boundaries of regularities, regularities on boundaries and boundaries of boundaries". One domain, partly manual. SINGLE-PAPER lineage. This is the closest published statement of the owner's "guards are computed regions where the law does not hold, found experimentally".
- ABACUS: conditional laws with preconditions obtained by clustering the data into regions where different equations hold. Mechanism FROM-MEMORY; only the citation was verified.
- Relevance: the idea of scope search has a precedent; the scalable mechanism for it is in Sections 1.3, 1.6 and 6.

### 2.3 Schmidt & Lipson 2009 (Eureqa)

- (i) Genetic-programming symbolic regression over time-series data, scored by how well the candidate predicts ratios of partial derivatives between variable pairs, which is meant to exclude trivial invariants.
- (ii) Verified (https://faculty.washington.edu/morgansn/pmwiki/uploads/Site/schmidt-science2009.pdf): on a 32-core implementation, "a few minutes for the harmonic oscillator to 30 hours for the double pendulum"; seeding the double-pendulum run with terms found for simpler systems cut 30–40 h to 7–8 h. That seeding result is one of the few *measured* instances of earlier discoveries making later ones cheaper (about 5×).
- (iii) Hillar & Sommer (https://arxiv.org/abs/1210.7273, unrefereed): the stated fitness "is flat for general systems"; the version that works effectively encodes Hamilton's equations or Newton's second law.
- (iv) SHIPPED as a product (Eureqa); the conservation-law claim itself is contested.
- (vi) With a simulator one does not need derivative-ratio fitness; invariants can be tested directly along trajectories (2.6).

### 2.4 AI Feynman (Udrescu & Tegmark 2020; 2.0 in 2020)

- (i) Fit a neural network to the data so the unknown function can be queried anywhere; then apply a battery of tests (dimensional analysis, translational and scaling symmetry, additive and multiplicative separability, setting variables equal) that each split the problem into smaller ones; brute-force and polynomial-fit the leaves.
- (ii) Own benchmark: 100/100 Feynman equations vs Eureqa's 71; bonus set 90% vs 15% (https://arxiv.org/abs/1905.11481). Brute force is over reverse-Polish strings, "s^n strings of length n"; a 15-symbol string "would require about 2 years". Independent re-evaluation (SRBench, https://arxiv.org/abs/2107.14351; 1M evaluations or 8 h on one core): "AIFeynman identifies exact solutions 53% of the time", next best 27%; above noise 0.01 four methods beat it.
- (iii) Brittle to noise; the decomposition tests depend on the quality of the interpolant.
- (iv) PROVEN-RESEARCH (independently benchmarked).
- (vi) **The key transfer.** The paper says the network exists only because "we need to be able to evaluate f at points ... of our choosing where we typically have no data". A simulator *is* that evaluator. The symmetry and separability tests then become exact oracle experiments of depth 2: "is f(x+a, y+a) = f(x, y) for sampled a?", "does f(x1,y1)·f(x2,y2) = f(x1,y2)·f(x2,y1)?". Each passed test factors the search space instead of enumerating it. This is the only technique in this section that attacks the exponent rather than the constant.

### 2.5 PySR and Exhaustive Symbolic Regression

- **PySR / SymbolicRegression.jl** (Cranmer 2023, https://arxiv.org/abs/2305.01582). Multi-population evolutionary search with simplification and constant optimisation. Evaluation "remains the bottleneck"; a tree interpreter evaluates one expression over 100 rows in about 607 ns, the same as hand-written code and about 200× faster than naive `eval` (DynamicExpressions.jl README). Typical budget: 8 cores for 1 hour. A June 2026 benchmark (ERBench, https://arxiv.org/abs/2606.09276) reports exact recovery 0.29 for PySR, 0.0 for DSR and Operon, and that PySR is near-perfect at 1–3 operators and near zero beyond. SHIPPED.
- **Exhaustive Symbolic Regression** (Bartlett, Desmond, Ferreira, https://arxiv.org/abs/2211.11461). Enumerate every expression up to a complexity bound, deduplicate symbolically, fit constants, rank by description length. With 8 operators and one variable at complexity 10: 168 million naive strings → 5.2 million valid trees → 134,234 unique functions; 46 minutes on 196 cores for generation and deduplication, about 150 CPU-hours for a full run. Runtime scales "approximately as (1.5k)^c". The authors' 2025 review (https://arxiv.org/abs/2507.13033): "even greatly enhanced computational resources could not extend the maximum complexity by ≳ 1". PROVEN-RESEARCH (one group, several papers; MDL ranking is standard).
- (vi) ESR is the honest ceiling for "exhaustive, single variable, 8 operators": complexity 10. It also shows MDL ranking over an exhaustive set works as a selection principle, which is the owner's pricing idea.

### 2.6 Conservation laws without neural networks: the null-space method

- (i) Choose a library of candidate terms (monomials, or enumerated expressions). Evaluate them on many states along trajectories. Any vector in the null space of the (differences of the) resulting matrix is a conserved linear combination. Verify on fresh data or with a prover.
- (ii) SID (https://arxiv.org/abs/2305.19525): complete within the span of the library; found 14 and 3 conserved quantities where 12 and 2 were known. Sharma et al., ESOP 2013 (https://theory.stanford.edu/~aiken/publications/papers/esop13.pdf) is the program-side version: rows are program states, columns are monomials to degree d, candidates are "Basis(NullSpace(A))", then an SMT check. Kaiser, Kutz, Brunton (https://arxiv.org/abs/1811.00961) do the same with a SINDy dictionary.
- (iii) Finds only laws *linear in the chosen terms*; the library must contain the right terms; numerical rank decisions are fragile in floating point (exact rationals fix this).
- (iv) PROVEN-RESEARCH (three independent lines).
- (v) Gaussian elimination over rationals plus a term library: 100–200 lines.
- (vi) A one-shot linear-algebra step finds every invariant in the span of N terms at cost O(N^3), where enumeration of sums of k terms would cost N^k. For "conservation and symmetries" this is the cheapest sound tool available, and it composes with enumeration: enumerate terms, then solve for linear relations among their value vectors.

### 2.7 Others

- **AI Descartes** (Cornelio et al. 2023) and **AI Hilbert**: symbolic regression filtered or driven by a theorem prover over *supplied* background axioms. SINGLE-PAPER each. Not a from-scratch discovery method.
- **AI Poincaré** (Liu & Tegmark 2021) and neural conservation-law finders: need trained networks. Out of scope.
- **Ramanujan Machine** (https://arxiv.org/abs/1907.00205): enumerate left-hand and right-hand expression families separately, hash each to 10 digits, join on the hash, re-verify matches to as many as 2,000 digits. Cost O(M+N) instead of O(M·N). The authors call it "not trivially scalable". This is the same trick as cvec matching (Section 1.6), on numbers.
- **Active automata learning** (Angluin's L*, LearnLib; SHIPPED): exact models from membership and equivalence queries against a black box. Verified scale from the Radboud TLS benchmarks: learned Mealy machines of 7–11 states (https://automata.cs.ru.nl/BenchmarkTLS). Mature, but it learns finite-state structure, not algebra.

### 2.8 What transfers to a simulator-oracle setting

1. Vary-one-hold-rest scheduling, level by level (BACON), with exact equality.
2. Scope search after a law is found: locate the boundary, then look for laws on the boundary (FAHRENHEIT).
3. Symmetry and separability tests as direct depth-2 oracle queries that *decompose* the target (AI Feynman). No network required.
4. Null space of a term library over sampled states, in exact arithmetic (linear and conserved relations for free).
5. Meet-in-the-middle joins on fingerprints of the two sides of a candidate law.
6. Exhaustive enumeration ranked by description length (ESR) as the fallback, with the measured ceiling of about 10 nodes for 8 operators and one variable.

## 3. Enumerative program synthesis at scale

Three facts organise this section. First, the baseline that every later paper has to beat is plain size-ordered bottom-up enumeration with observational-equivalence (OE) pruning, and it is stronger than most papers' headlines suggest. Second, the published reach of recursion synthesisers rests on per-task hand-picked component sets. Third, published timeouts are almost all 1 minute to 2 hours; the long runs that exist (DreamCoder's 24-hour-per-task enumeration baseline, Speculate's three-day run, superoptimiser anecdotes) do not show that more hours find qualitatively more.

### 3.1 Bottom-up enumeration with observational equivalence

| System | What it adds | Grammar | Measured reach | Compute | Maturity |
|---|---|---|---|---|---|
| **TRANSIT** (PLDI 2013) https://www.cis.upenn.edu/~alur/Pldi13.pdf | The canonical algorithm: enumerate by size, keep one expression per value vector on the examples | ~20 typed functions over Int/Set/Bool | Size 15 in 2–13 min; expected size > 20 not found in 30 min; sizes ≤ 11 under 1 s. Pruned search explores "two to three orders of magnitude fewer expressions" above size 10; unpruned exceeds 3.5 GB there | 1 core | Algorithm PROVEN-RESEARCH (re-implemented in ESolver, EUSolver, Probe, Bustle, TF-Coder, Duet) |
| **EUSolver** (TACAS 2017) https://www.cis.upenn.edu/~alur/Tacas17.pdf | Enumerate terms correct on *subsets* of examples plus predicates, unify with a decision tree | SyGuS grammars (~28 productions for strings) | 787 of 852 PBE benchmarks where plain enumeration (ESolver) "solved 1". Re-measured by Duet: string solutions of size 9–12 take 16–46 min | 3600 s; 9 kLOC Python/C++ | PROVEN-RESEARCH |
| **Probe** (OOPSLA 2020) https://arxiv.org/abs/2010.08663 | Cost-ordered enumeration under a PCFG re-estimated during the search from partial solutions | Median 16–17 operations (string, bit-vector), 4 (circuit) | 10 min: Probe 91 of 140; size-based baseline 84; height-based 44. A size-10 solution needs a bank of 2,048 programs (1 s); a size-19 solution is not reached by size-based search in 20 min | Scala, laptop | PROVEN-RESEARCH (re-implemented by Bee Search authors; baseline for Simba, DryadSynth) |
| **Bustle** (ICLR 2021) https://arxiv.org/abs/2007.14381 | Small MLP on property signatures re-weights intermediate values | 22 string operations | CrossBeam's re-measurement of the *unguided* Java baseline: 74 of 127 at 3.4 s, 91 at 30 s. Bustle itself: 101 and 112 | Java; ~3×10^5–10^6 candidates/s (inferred) | PROVEN-RESEARCH; needs a trained model |
| **TF-Coder** (TOPLAS 2022) https://arxiv.org/abs/2003.09040 | Hand-set operation weights; type/shape/value filters | **134 operations, same set for every task** | 63 of 70 real tasks in 5 min, 17 s mean. Largest solution: 5 operations, 11 nodes, 65 s. Plain TRANSIT: 39 of 70. Filters eliminate 98.6% of candidates for one operation | Python | **SHIPPED** |
| **cvc4sy / cvc5** (CAV 2019) https://homepage.divms.uiowa.edu/~ajreynol/cav19b.pdf | "Fast" enumeration unique up to the solver's rewriter, inside an SMT solver | SyGuS | 1,789 of 2,428 at 1800 s; without rewriting-based dedupe 1,690 | 1 core | **SHIPPED** |
| **Duet** (POPL 2021) https://psl.hanyang.ac.kr/assets/pdf/popl21.pdf | Bottom-up component bank + top-down decomposition with *hand-written* inverse semantics | SyGuS | 1,443 of 1,536 at 1 h. Enumerated components: size 1–12, mean 4; "92% of problems ... size ≤ 7". For a size-18 string program, OE enumeration alone "cannot be found even within 6 hours"; Duet finds it in 0.03 s | 5 kLOC OCaml | SINGLE-PAPER, standard baseline |
| **Simba** (PLDI 2023) https://arxiv.org/abs/2304.10768 | Forward/backward abstract interpretation prunes partial programs | Bit-vectors | Size-19 Hacker's Delight solution in 10.8 s where Probe and Duet exceed 1 h; in the same 1-hour runs Probe's solved programs average size 6.5–7.9 | 10 kLOC OCaml + Z3 | SINGLE-PAPER |
| **Bee / Heap / Eco Search** (2022–2025) https://arxiv.org/abs/2412.17330 | Exact best-first order under a cost function | 27–1,383 rules | At most about 1.2× more tasks than each other; Python generation-only throughput 0.8–1.1×10^5 programs/s; peak memory 5.4 GB in 300 s. Authors: learned cost functions were "close to the uniform grammar" | 1 core, 300 s–120 min | SINGLE-PAPER each |
| **MPL, metaprogram search** (Rule et al., Nat. Commun. 2024) https://www.nature.com/articles/s41467-024-50966-x | Search over program *transformations* (metaprimitives) rather than programs | 100 list functions | Matches human learners at 500K search steps and keeps ≥ 84% at 5K, where plain enumeration needed over 1M and stayed at or below the human 25th percentile. "MPL's success depends on having specific metaprimitives"; recursion in 34.4% of runs | LLM-free | SINGLE-PAPER |

Notes that matter for calibration:

- **Probe's own numbers deflate its headline.** The "44" baseline in the abstract is height-based. Against size-based OE enumeration it is 48 vs 42 (string), 21 vs 20 (bit-vector), 22 vs 22 (circuit). The learning matters when the grammar is bloated: with all string benchmarks sharing one extended grammar, Probe solves 25, size-based 9, height-based 1. The paper says the baselines "need the benefit of approaching each task with a different, carefully chosen grammar". (Verified first-hand in the paper text.)
- **TF-Coder is the only shipped data point at ~100 primitives**, and its reach is 5 operations. Its 7 failures need 3, 5, 6, 9, 10, 10, 13 operations; raising the limit from 5 minutes to 1 hour recovered two of them (at 31 and 58 min) and "the remaining problems are simply too difficult ... within an hour".
- **Decomposition, not time, wins the long tail.** EUSolver's 787 vs ESolver's 1; Duet's 0.03 s vs > 6 h; cvc4sy's observation that enumerative strategies lead at short times "but then EUS solves more benchmarks in the end".
- Smallest sound version of the baseline: typed size-ordered enumeration plus a hash set of value vectors, 100–300 lines.

### 3.2 Recursive-function synthesis (top-down typed, and bottom-up with angelic recursion)

The benchmark set is essentially one suite of 43–65 textbook list/tree/nat functions, reused from paper to paper, with 120-second timeouts.

| System | Method | Reach | What is hand-supplied | Maturity |
|---|---|---|---|---|
| **Escher** (CAV 2013) | Bottom-up OE enumeration + goal graph for conditionals; recursive calls answered by an oracle | 22 tasks, all solved, max 10.7 s; **one fixed set of 22 components for all tasks**. With OE off: 3 tasks hit the 1 GB limit, `stutter` 0.55 s → 67 s | An oracle for recursive-call outputs | SINGLE-PAPER; ideas PROVEN |
| **Myth** (PLDI 2015) https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf | Type-and-example-directed refinement + size-ordered enumeration of eliminations | 43 tasks, solutions of 5–32 AST nodes, mostly < 0.2 s; one extended example of 75 nodes in 3.9 s with 31 examples | **Per-task minimal context** ("it cannot discover helper functions on its own, so we provide them"); trace-complete examples. Adding five generic functions: `list_compress` 0.073 s → 128 s, `list_pairwise_swap` 0.007 s → 10.2 s | PROVEN-RESEARCH |
| **λ²** (PLDI 2015) https://www.cs.utexas.edu/~swarat/pubs/pldi15.pdf | Hypotheses over map/fold/filter with per-combinator deduction rules | ~40 tasks, median 0.43 s, worst 552 s (10-min limit). Without types almost everything times out; without deduction 4 time out | The combinators, their deduction rules, per-task "extra primitives" | SINGLE-PAPER |
| **Synquid** (PLDI 2016) | Refinement-type-directed search with SMT | 64 tasks incl. red-black insertion (size 69); all but 7 under 5 s | Per-task components and exploration bounds; refinement-type specs; an SMT solver | PROVEN-RESEARCH; not evaluator-only |
| **SMyth** (ICFP 2020) | Myth + live bidirectional evaluation; no trace-completeness | 38 of 43 in 120 s | Minimal contexts | SINGLE-PAPER |
| **Burst** (POPL 2022) | Bottom-up with tree automata; assume recursive calls return anything, then check | 43 of 45 from examples; 91% from logical specs (Synquid 49%) | Termination order (loses `list-rev-tailcall`) | SINGLE-PAPER |
| **Trio** (POPL 2023 / JFP 2025) | Enumerate recursion-free blocks, generalise to recursion | 65 of 65 "solved" (57 intended), mean 1.5 s; largest size 87 | Minimal contexts | SINGLE-PAPER |
| **SyRup** (PLDI 2023) | Joint search of traces and programs; fewer examples | 43 tasks, 32 recursive | — | SINGLE-PAPER |
| **MagicHaskeller** (2005–2022) | Exhaustive typed generate-and-test with a memo table, equivalence by random testing | 11 of 16 of the first "99 Haskell problems"; 3 of 9 FlashFill examples; memo table of "tens of gigabytes"; "only easy problems could be solved" | A fixed component library | SHIPPED (niche) |
| **IGOR2** | Analytical: anti-unify example equations, search over a few refinement operators | 11 toy problems in 0.007–5.7 s | Example sets closed under the recursion | SINGLE-PAPER lineage (algorithm description FROM-MEMORY) |
| **FrAngel** (POPL 2019) | *Random* generation + fragment mining + angelic conditions | 94% of 120 Java tasks in 30 min, 47% in 10 s; median task size 11, max 22; ~100–3,600 components per task | Component classes named per task | SINGLE-PAPER |

The honest reading: recursive list functions of 15–30 AST nodes are found in under a second **when the component context contains only what the task needs** and recursion is restricted to structurally decreasing calls. Adding five irrelevant helpers costs two to three orders of magnitude. No system in this table discovers its own helper functions; the only one that did is DreamCoder (Section 4), at about a CPU-year.

### 3.3 Superoptimisers and exhaustive combinatorial search

See Section 9 for the speed analysis. Reach summary: Massalin, 12 instructions in "several hours" over a 10–15-opcode table at 50,000 programs/s; GNU superopt, about 5 instructions practical and 7 "took several weeks"; Bansal & Aiken, length 3 over full x86; Lens, ≤ 5 ARM instructions in an hour; Knuth, all 5-variable Boolean functions up to 12 gates; Codish et al., 9-input sorting networks at about 9 single-core years; icecuber's ARC solver, depth 3 of 142 image transformations everywhere and depth 4 for half the tasks in 9 hours on 16 GB.

## 4. Library learning and compression; the AM/EURISKO and Schmidhuber lineages

### 4.1 EC (Dechter, Malmaud, Adams, Tenenbaum, IJCAI 2013)

- (i) Enumerate typed combinator programs best-first to a fixed frontier size; compress the solutions that hit tasks by promoting reused subtrees to primitives; re-estimate production weights; repeat. No neural network.
- (ii) Verified (https://www.ijcai.org/Proceedings/13/Papers/196.pdf): 1,000 polynomial tasks from `I S B C 1 0 * +`; 15 iterations at frontier 10,000 reaches near 100% where the same budget without learning "only hits 27 of the 1000 tasks (3%)".
- (iii) The curriculum cliff, measured by the authors: restricting to quadratics with coefficients above 1, "performance drops to 0 because no task is hit in the initial frontier". "The algorithm can get stuck in plateaus after a rapid initial increase in performance, due to its circular nature". On Boolean functions "most of the trajectories get stuck in a local minimum around 50%".
- (iv) Loop PROVEN-RESEARCH (many re-implementations); this system SINGLE-PAPER. (v) 500–1,500 lines. (vi) The owner's kernel is an EC-family system; these are its documented failure modes.

### 4.2 EC² (Ellis et al., NeurIPS 2018): the ablation table that matters

Verified first-hand from the paper's Table 3 (https://papers.nips.cc/paper/2018/file/7aa685b3b1dc1d6780bf36f7340078c9-Paper.pdf), % of held-out tasks solved:

| Domain | Full (library + recognition net) | Library, no net | Subexpression-only library, no net | Neural synthesis baseline | Re-weight grammar only | Plain enumeration |
|---|---|---|---|---|---|---|
| List processing | 94 | 79 | 71 | 35 | 62 | 37 |
| Text editing | 74 | 43 | 30 | 33 | 0 | 4 |
| Symbolic regression | 84 | 75 | 62 | 38 | 38 | 37 |

Reading: library learning with refactoring, without any neural network, roughly doubles the solve rate over plain enumeration (37→79, 4→43, 37→75). Re-weighting the grammar alone helps in one domain of three and *hurts* in another. Without the recognition network the system hits "a lower 'plateau' after which it stops solving new tasks".

### 4.3 DreamCoder (Ellis et al., 2020/2021)

Source: main text plus supplement, https://www.cs.cornell.edu/~ellisk/documents/dreamcoder_with_supplement.pdf (compute passages verified first-hand).

- (i) Wake: recognition-network-guided typed enumeration on a minibatch of tasks. Abstraction sleep: refactor found programs with version spaces and add the routine that most improves a Bayesian/MDL objective. Dream sleep: retrain the network.
- (ii) Measured:
  - Standard domains: 100–256 hand-built tasks each, wake timeouts 2 min to 1 h, 20–96 CPUs, "around a day using moderate compute resources (20-100 CPUs)". The list domain *starts* with `fold`, `unfold`, `map`; it learns about 20 routines, at most four layers deep.
  - Enumeration-only baseline: "24 hours per task, generating and testing up to 400 million programs for each task" (about 4,600 programs/s).
  - Physics: 60 textbook laws from 15 primitives that already include `map`, `fold`, `zip`; 93% after 8 cycles of 4 h × 64 CPUs (≤ 2,048 CPU-hours).
  - **The from-scratch bootstrap ("origami")**: primitives `if = > + - 0 1 cons car cdr nil is-nil` plus the Y combinator; 20 hand-chosen introductory-programming tasks; 4-hour timeout on 64 CPUs. "With enough compute time (roughly five days on 64 CPUs), DreamCoder learns to solve all 20 problems", building `fold`, `unfold`, `map`, `zip`, `length`, `range`. "We did not use the recognition model for this experiment." The authors: "DreamCoder took approximately a year of total CPU time."
  - Compression cost: "on the order of 10^14 or more refactorings before finding a single new library component."
- (iii) Failure modes: per-domain ablation curves are figure-only, but the text says the neural net alone "is always at least as effective as library learning by itself". Compression does not scale: on larger corpora DreamCoder "was unable to discover even a single abstraction ... despite being given hours of runtime and 256GB of RAM" (Stitch paper). On ARC with a hand-built 77-primitive DSL it solved 18 of 400 public-eval tasks against 160 for icecuber's hand-written brute force (https://arxiv.org/abs/2402.03507), after 3.1 billion programs. Independent cost statements: "upwards of thousands of CPU hours" (LAPS), "more than two CPU-months just to learn a single domain" (LILO). Each domain is learned separately.
- The authors' own conclusion: "We do not advocate such blank-slate learning as a route to AI"; such approaches need "massive compute".
- (iv) Loop PROVEN-RESEARCH on curated 100–250-task domains (reused by LAPS, LILO, AbstractBeam, ARC work). The from-scratch bootstraps are SINGLE-PAPER; no independent reproduction found.
- (v) Typed enumerator (~500 lines) + compressor + weighted grammar. Stitch-style compression removes the main cost centre.
- (vi) **This is the single existing proof that an LLM-free, network-free enumerate-and-compress loop can climb from 1959-Lisp primitives to higher-order functors. It took about 7,700 CPU-hours for 20 tasks that a person selected.** At single-threaded scale that is ten months of wall clock.

### 4.4 Stitch, babble, LAPS, LILO

- **Stitch** (Bowers et al., POPL 2023, https://arxiv.org/abs/2211.16605). Corpus-guided top-down search over abstraction templates with an upper bound for pruning. "3-4 orders of magnitude faster and uses 2 orders of magnitude less memory" than DreamCoder's compressor; tens of milliseconds on DreamCoder's domains; recovers the origami functions with "<2% of its compute" on top of one rewriting step. Evaluated on compression only, not on downstream solve rate. **SHIPPED** as a tool (used inside LILO). Core ~1–2 kLOC (estimate).
- **babble** (Cao et al., POPL 2023). Anti-unification over e-classes after equality saturation with a domain theory; 10–100× faster than DreamCoder. Needs a hand-supplied equational theory per domain. Compression-only evaluation. SINGLE-PAPER. Relevance: if the kernel discovers its own laws (Section 1), babble's design is what consumes them for library learning.
- **LAPS** (ICML 2021) and **LILO** (ICLR 2024): language- and LLM-assisted variants. LILO's internal negative result is worth noting: adding Stitch abstractions to the LLM solver *hurt* (−30.6 points on one domain) until the abstractions were given names and documentation. SINGLE-PAPER each.

### 4.5 Evidence that learned libraries often are not reused

- LLM-based systems (https://arxiv.org/abs/2410.20274, verified): LEGO-Prover learned "over 20,000 lemmas", of which 1,233 reached the prover and "exactly one lemma is reused ... once". TroVE: "3 successful reuses in 3,201 test questions"; a no-reuse ablation matched it. A follow-up (EACL 2026, https://aclanthology.org/2026.eacl-long.163/) finds three such systems "fail to consistently outperform the simple baseline" at equal compute.
- LLM-free: AbstractBeam (https://arxiv.org/abs/2405.17514) gains 3–4 points on hand-written tasks and nothing on synthetic ones; unused abstractions "bloat the DSL". Leroy: Stitch on Python gives a compression ratio of 1.04×.
- The transferable lesson is methodological: credit a library only after checking (a) that entries are actually invoked later and (b) an equal-compute baseline without the library.

### 4.6 AM and EURISKO

- (i) AM: an agenda over frame-represented mathematical concepts driven by 243 hand-written heuristics that mutate small Lisp predicates and score interestingness. EURISKO: heuristics are themselves units, so heuristics can mutate heuristics.
- (ii) Verified from the EURISKO paper (https://users.cs.northwestern.edu/~mek802/papers/not-mine/Lenat_EURISKO.pdf): in the Traveller fleet domain "146 units were added, by hand" and it "spent 1300 CPU hours on a personal Lisp machine".
- (iii) Lenat & Brown, "Why AM and EURISKO appear to work" (https://cdn.aaai.org/AAAI/1983/AAAI83-059.pdf), in their own words:
  - What AM did: "syntactically mutating small Lisp programs".
  - Why it worked: "it is, in part, the density of worthwhile math concepts as represented in Lisp that is the crucial factor". Unary numbers were "critical to AM's discovering arithmetic".
  - Why it stopped: "AM's ultimate limitation apparently was due to its inability to discover new, powerful, domain-specific heuristics for the various new fields it uncovered." It went fast "for a while, until it moved into a less well balanced state".
  - Why heuristics-about-heuristics did not bootstrap: mutating a two-page heuristic "is doomed to almost always giving garbage"; "For five years, that effort achieved mediocre results", until humans redesigned the representation so that heuristics shrank "from 60 lines to 3".
  - Human share: Lenat "culled through the runs of EURISKO every 12 hours or so"; "the final crediting of the win should be about 60/40% Lenat/EURISKO".
  - Meaning: "we -- the human observers -- play another crucial role in attributing 'meaning' to a discovery in AM."
- Ritchie & Hanna (1984; abstract and secondary summary only): the published description did not match the program; heuristics were entangled with control code; such work "is unproductive from the point of view of building a stable base for further research".
- Haase's Cyrano re-implementation (abstracts only): after AM "no generation of automated super-mathematicians appeared"; the lesson drawn was that "a close coupling of representation syntax and semantics is necessary", plus a closure requirement (new concepts must be valid inputs to the concept-forming process).
- 2023–2024: the sources were recovered and EURISKO runs under Medley Interlisp, but no published discovery has been reproduced and the Traveller data is missing (https://github.com/white-flame/eurisko).
- (iv) SINGLE-PAPER; never reproduced. (v) The agenda loop is a few hundred lines; the 243 heuristics and 146 hand-added units are the system.
- (vi) This is the direct ancestor of "reflection: the search graph as data, policies learned instead of hard-coded". Its designers' post-mortem says the reflective layer did not compound and the object-level success came from a representation in which small syntactic steps were dense in meaning.

**HR** (Colton) and **Graffiti** (Fajtlowicz) are theory-formation systems that did produce published mathematics (Graffiti's conjectures led to about 80 papers; HR invented integer sequences, though "HR did only the easy part"). Both work in a fixed human-supplied vocabulary and hand conjectures to human mathematicians; neither feeds results back into the generator. PROVEN-RESEARCH as conjecture generators, not as bootstraps.

### 4.7 Levin search, OOPS, PowerPlay, Gödel machine

- **Adaptive Levin search** (Schmidhuber, Zhao, Wiering 1997): on one hand-ordered maze sequence, adapting instruction probabilities from past solutions cut total steps from 39.4×10^6 to about 1–1.8×10^6 (20–45×). Stated limits: no help on the first goal set; earlier goals do not necessarily help later ones.
- **OOPS** (2004, https://arxiv.org/abs/cs/0207097). Verified: 30 tasks of the `1^n 2^n` language solved in about 0.3 days, then a universal Towers-of-Hanoi solver in 2–3 more days on a 1.5 GHz PC; 93,994,568,009 program prefixes tested. Reuse sped the second search "by a factor of 1000 or so". The paper's own caveats: without the helper tasks it "was not able to solve instances involving more than 3 disks" in a week; "oops does not by itself invent an appropriate series of easier subtasks"; the Hanoi solver "does not call the 1^n 2^n solver as a subprogram" (the reuse is a probability shift toward recursion-defining instructions); the first family "did not at all profit from solutions to earlier solved tasks"; per-family instruction probabilities were hand-boosted. SINGLE-PAPER, one hop of transfer.
- **PowerPlay** (2011; experiments 2013): in 8 hours on a PC a small recurrent net "invented 67 novel action sequences" for a fovea over one image. No external task was solved. SINGLE-PAPER.
- **Gödel machine**: "no full implementation has been created". SPECULATIVE.

### 4.8 What makes a bootstrap compound, and where each one stalled

Conditions present wherever compounding was actually measured:

1. **A dense, graded task set supplied from outside.** EC's cliff to 0%; OOPS's helper tasks; DreamCoder's hand-built task sets. No surveyed system invents its own curriculum and benefits.
2. **Something that shrinks breadth as the library grows.** DreamCoder's own cost model is breadth^depth: a library reduces depth and increases breadth. Without a breadth-reducer (recognition net, or at least re-weighting) EC² plateaus lower.
3. **A representation where small edits stay meaningful** (Lenat & Brown).
4. **Affordable semantic compression.** Refactoring is what found `fold`, and is what cost a CPU-year. Stitch makes the syntactic part cheap; the semantic part (rewriting modulo laws) remains expensive.
5. **Utility accounting.** See Section 5.6: unmeasured additions slow the system down.
6. **A human in the loop**, usually under-reported (EURISKO 60/40).

Where each stalled: EC/DreamCoder at about four library layers, one domain at a time, with compute and compression blow-up; AM/EURISKO when it left the region where Lisp mutations were dense in meaning; OOPS after one transfer; HR/Graffiti never fed back; Gauthier & Urban's LLM-free OEIS loop (Section 8) saw new solutions per generation fall from 8,438 to 187, and compounds through a retrained policy with no library at all.

The owner's observation that "it's been the AI agents that are doing the majority of search" matches the published record: in every lineage, much of the discovery was carried by parts supplied from outside the kernel (primitives and representation, the task corpus, periodic culling).

## 5. Learning search policy without (or with minimal) neural networks

The owner wants pruning and strategy re-weighting learned from the search's own trace. The mature, measured instances of that idea exist, but they are narrower than "reflection": they are fixed-form statistics and fixed-form lemmas over a trace whose failures can be *explained*.

### 5.1 Ranked by measured effect, evidence quality and cost

| # | Mechanism | Measured effect | Cost | Maturity |
|---|---|---|---|---|
| 1 | **Observational equivalence + size-ordered bottom-up enumeration.** Not learned, but the baseline against which everything else must be measured | Size-based 84 of 140 vs height-based 44 (Probe, 10 min). Escher with OE off: three tasks run out of memory, others 20–120× slower | ~300 lines | PROVEN-RESEARCH, many implementations |
| 2 | **Type/shape/validity filters and hand-set operation weights** | TF-Coder: removing filters loses 19 tasks of 61, removing weights loses 10; the two learned models add 2 tasks. λ² without types: almost everything times out | Tens of lines per operator | SHIPPED |
| 3 | **Failure-explanation lemmas** (CDCL clause learning; conflict-driven synthesis; abstraction refinement) | SAT (Katebi, Sakallah, Marques-Silva 2011; 10,000 runs at 1000 s): full solver 9,068 solved; without clause learning 4,837; without VSIDS 6,932; without restarts 8,653. Neo: 4–5.5× average, 19.8× on hard tasks. Blaze: 16–115× over OE enumeration | High; needs per-component specifications or abstract semantics, hand-written in every verified system | SHIPPED in SAT; PROVEN-RESEARCH in synthesis |
| 4 | **Library learning without a network** | EC²: plain enumeration 37 / 4 / 37% → 79 / 43 / 75% | High; plateaus; needs a task corpus | PROVEN-RESEARCH |
| 5 | **Decayed conflict counters as branching order** (VSIDS; LRB as a bandit) | 6,932 → 9,068; LRB solves 1,279 vs VSIDS 1,179 of 1,975 | ~50 lines *given* a conflict analysis that names the participants | SHIPPED |
| 6 | **Just-in-time PCFG from partial solutions** (Probe) | 84 → 91 of 140 on curated grammars; 9 → 25 of 70 on a bloated grammar; slower on tiny grammars because of restarts | ~300 lines | SINGLE-PAPER, re-implemented once |
| 7 | **Cross-task grammar re-weighting alone** | EC²: +25 / −4 / +1 points. Euphony: 236 vs 87 of 405 over EUSolver at 1 h, yet 50 of 140 in Probe's comparison, below unguided size-based search | ~100 lines | Mixed sign across papers |
| 8 | Exact best-first enumerators (Heap, Bee, Eco Search) | At most about 1.2× more tasks | ~300 lines | PROVEN-RESEARCH |
| 9 | Restarts, Luby, portfolios (SATzilla) | Large only for randomised solvers on heavy-tailed instances; Luby's universal strategy costs a log factor. Useless for a deterministic enumerator that keeps no state across restarts | 10–100 lines | SHIPPED |
| 10 | Primitive-presence prediction (DeepCoder), property signatures, per-value re-weighting (Bustle) | 15–62× at 20% solved on length-3 programs; a re-implementation solves 63% at length 5 and 2% at length 14. All neural | Training pipeline | PROVEN-RESEARCH that the effect is modest and decays with length |
| 11 | Explicit rational metareasoning (value of computation) | No shipped use found beyond the bandit rule inside MCTS | — | SPECULATIVE as engineering |

Sources: Probe https://arxiv.org/abs/2010.08663 ; TF-Coder https://arxiv.org/abs/2003.09040 ; Katebi et al. https://ai.dmi.unibas.ch/_files/teaching/fs21/ai/material/ai32-katebi-et-al-sat2011.pdf ; LRB https://cs.uwaterloo.ca/~ppoupart/publications/sat/learning-rate-branching-heuristic-SAT.pdf ; Neo https://www.cs.utexas.edu/~isil/pldi18-neo.pdf ; Blaze https://arxiv.org/abs/1710.07740 ; Euphony https://www.cis.upenn.edu/~alur/PLDI18.pdf ; DeepCoder https://ar5iv.labs.arxiv.org/html/1611.01989 and PCCoder https://arxiv.org/abs/1809.04682 .

### 5.2 Probe's update rule

`p(R) ∝ p_uniform(R)^(1 − Fit(R))`, where `Fit(R)` is the largest fraction of examples satisfied by any selected partial solution that uses production `R`; costs are `−log p` rounded to integers; the search restarts after each update. No training data. (i)–(vi): it is cheap, it is robust to useless productions, and it is the only *within-task* statistical policy learner with a clean ablation. Its limit is that it needs partial credit (programs satisfying a subset of examples), which law discovery does not have.

### 5.3 SAT as the model of "reflective" search that works

VSIDS is exactly a decayed statistic over the search trace: bump the variables that appeared in recent conflicts. Clause learning is exactly "never repeat the same failure": analyse the conflict, derive the smallest cause, store it as a constraint. Both are shipped in every modern solver and the ablation above shows each is worth thousands of instances.

Two properties make them work, and both are absent in naive program enumeration:

1. **A failure has a finite, computable explanation.** A conflict names the handful of assignments responsible. A failed program candidate does not name the sub-term responsible unless the system has semantics for partial programs. Neo and Blaze get their 4–115× by having hand-written specifications or abstract transformers for every component; Atlas and Amurth (Section 7) learn such transformers but need logical semantics to learn from.
2. **Learned items are deleted when they do not pay.** Clause-database reduction is the shipped answer to the utility problem below.

### 5.4 Levin-style time allocation, iterative deepening

Budget doubling costs a small constant factor; Luby's universal restart strategy costs a logarithmic factor, O(ℓ log ℓ). Levin search allocates time in proportion to program probability; its demonstrated value is in Section 4.7 (20–45× on one maze sequence, one 1000× transfer in OOPS). These are safe and nearly free to implement; none has been shown to change what is reachable by more than the log factor they are designed to bound.

### 5.5 Rational metareasoning

Russell & Wefald's framework has no shipped explicit use that the sub-researcher could find; Hay et al. note that UCT "applies bandit algorithms to problems that are not bandit problems". Treat as SPECULATIVE.

### 5.6 The utility problem (the main cautionary result for learned control)

- **Minton, PRODIGY/EBL** (https://cdn.aaai.org/AAAI/1988/AAAI88-100.pdf; OCR, digits may carry error). Control rules learned from the planner's own trace. `Utility = (AvrSavings × ApplicFreq) − AvrMatchCost`; rules with negative measured utility are discarded. Rules kept: 19 of 328, 30 of 588, 37 of 946 learning episodes (4–6%). Learned rules cut nodes by about 13× while each node became about 3.9× more expensive. Without utility validation the system was "approximately sixty-five percent poorer"; without the estimate as well, "performance deteriorated so rapidly that the full test phase could not be completed". Macro-operators "in some cases ... resulted in overall performance degradation".
- **Soar chunking** (Tambe & Rosenbloom, https://ijcai.org/proceedings/1989/0117.pdf): five "expensive chunks" produced a 25× per-step slowdown; restricting the expressiveness of learned conditions gave 3–9× speedups.
- Mechanism that controls it, proven three times (PRODIGY, Soar, SAT clause deletion): measure each learned item's match cost and savings online, delete the losers, and bound the expressiveness of what can be learned.
- Maturity: PROVEN-RESEARCH. Cost: per-rule counters and deletion, ~100 lines.
- Relevance: any reflective pruning policy must ship with this accounting. The library-bloat findings in Section 4.5 are the same phenomenon thirty years later.

### 5.7 Answer to "which simple statistical mechanisms give large measured speedups?"

Large and reliable: OE pruning; type and validity filters; pruning the term space with already-discovered laws (Section 1: 100× to over 250×); failure lemmas *where failures can be explained*. Moderate and conditional: just-in-time re-weighting (large only when the grammar is bloated); library learning (2× solve rate, at high cost). Small or sign-unstable: cross-task re-weighting, better best-first orders, restarts. No learned, LLM-free, network-free mechanism in this literature changes the exponent; they change the base or the constant.

## 6. Learning preconditions, guards and totality from failures

There is a standard recipe, implemented independently at least five times. It works at small guard sizes, it always needs a predicate vocabulary, and nothing in it learns from non-termination beyond treating a timeout as a label.

### 6.1 Systems

| System | What it does | Measured | Failure modes | Maturity |
|---|---|---|---|---|
| **Daikon** (Ernst et al., 1999–) | Instantiate ~75 invariant templates over variables at program points; keep those never falsified on traces; "splitting" gives conditional invariants | Widely used. An independent study found about a third of inferred clauses incorrect or irrelevant (https://plse.cs.washington.edu/daikon/pubs/PolikarpovaCM2009-abstract.html) | Conjunctive templates only; quality tracks the test suite | **SHIPPED** |
| **Sankaranarayanan et al.** (ISSTA 2008) | Decision-tree learning over supplied predicates, with test generation per predicate truth assignment | ~1,000 tests per feasible assignment | Predicates supplied | SINGLE-PAPER; idea PROVEN |
| **PIE** (Padhi, Sharma, Millstein, PLDI 2016) https://web.cs.ucla.edu/~todd/research/pldi16.pdf | Start with *no* features. Bucket tests by feature vector; a bucket containing both good and bad tests is a conflict; enumerate the smallest new predicate that separates a bounded conflict group; then learn a small k-CNF | 87 of 101 correct preconditions for OCaml List/String/AVL functions from 6,400 tests with integers in [−4, 4] and lists up to length 5. Lazily synthesised features: at most 5 (mean 1.5) where eager enumeration needs up to 18,051 (mean 1,612). Conflict group of 16: 1.8 s and 66 MB; all conflicts at once: 11.7 s and 309 MB | 10 of 14 failures needed quantified features; small-scope sampling missed `Sys.max_string_length`; black-box output is only "likely" | **PROVEN-RESEARCH** (LoopInvGen won SyGuS-Comp 2018 Inv track; idea re-implemented in Alive-Infer and Proviso) |
| **ICE / ICE-DT** (Garg et al., CAV 2014, POPL 2016) | Learner receives positive, negative and *implication* examples so that learned invariants are inductive; decision trees over attribute templates | Standard in invariant synthesis | Needs a verifier as teacher; attribute templates (octagons) supplied | PROVEN-RESEARCH |
| **Gehr, Dimitrov, Vechev** (CAV 2015) https://files.sri.inf.ethz.ch/website/papers/cav15-learning.pdf | Black-box: sample argument tuples for a method pair, run both orders, label commute / not; find a small formula over a fixed fragment (equalities and orderings among arguments and results) by set cover. Samples are drawn per "logical type" (cell of the predicate partition) | 21 data types; 15,000 to 145,001 samples; formula search ≤ 710 ms; largest formula size 19. Stratified sampling stabilised at 15,000 samples where random needed 75,000. Stopping rule: same formula on two successive doublings | Fragment hand-fixed; no guarantee; an SVM learner overfitted and a stochastic search did not terminate at five or more variables | SINGLE-PAPER. **The closest precedent for "law holds when guard"** |
| **Alive-Infer** (Menendez & Nagarakatte, PLDI 2017) https://people.cs.rutgers.edu/~santosh.nagarakatte/papers/pldi2017-alive-infer.pdf | Preconditions for LLVM peephole rewrites from positive/negative constant valuations; PIE-style predicate enumeration + Boolean learner + SMT validation | Weakest precondition for 133 of 174 rules in 1000 s each; some precondition for 164; **weaker than the expert-written one in 73**. Plain enumerative search: 114, and it "times out for optimizations that have more than three predicates" | Domain predicates hand-written; labels come from SMT, so they are exact | SINGLE-PAPER |
| **Proviso** (Astorga et al., PLDI 2019) https://par.nsf.gov/servlets/purl/10129745 | Decision-tree learner with a concolic test generator as teacher; "safe and maximal modulo the test generator" | Truly safe and maximal in 73 of 105 and 105 of 121 cases; about 740 s per method | Depends on observer methods; with features not supplied, the PIE learner "takes much longer time and even diverges in some cases" | SINGLE-PAPER |
| **Spyro** (OOPSLA 2023) https://arxiv.org/abs/2301.11117 | Synthesise the *most precise sound* conjunction of properties within a user DSL | 41 of 45 problems; DSLs of 4,000 to 14.8 trillion properties | DSL designed per benchmark family; needs SMT or Sketch | SINGLE-PAPER |
| **Liquid Types** (PLDI 2008) | Refinement types inferred as conjunctions of user-supplied qualifier templates | — | Qualifiers are the hand-supplied part; conjunction only | PROVEN-RESEARCH (shipped as LiquidHaskell) |
| **Speculate / QuickSpec / Chompy** | Section 1: conditions enumerated to size 4 (Speculate), user-declared (QuickSpec), or from a predicate workload with implication pruning (Chompy) | See Section 1 | | |

One cross-cutting measurement: **a larger predicate grammar makes things worse.** On 180 invariant benchmarks, LoopInvGen degraded in 65% of benchmark/grammar pairs when the grammar grew (https://arxiv.org/abs/1905.07457). Interleaving grammars of increasing expressiveness recovered a mean 5× speedup.

### 6.2 Partiality in law discovery

Ruler's treatment is the practical precedent for "tolerating crashing": characteristic vectors "may have a null value in them to indicate failure to evaluate", and two vectors match "if their non-null values agree in every (and at least one) position". Division by zero then does not block `x/x = 1` from being proposed; the validator or a guard decides whether it is accepted. Escher does the same in synthesis with a single `err` value covering exception, type error and non-termination.

### 6.3 Non-termination

How synthesisers deal with divergent candidates (all verified in the sources):

- **Restrict the space:** Myth, SMyth, Burst and Escher allow recursive calls only on structurally smaller arguments. Deterministic, no timeouts. Cost: programs whose termination argument is not the built-in order are unreachable (Burst loses `list-rev-tailcall`).
- **Run and cut off:** DreamCoder (a very short per-example limit in the released code) and MagicHaskeller (0.02 s default; its author warns "setting timeout makes the library referentially untransparent"). Cost: results depend on machine speed, and slow-but-correct candidates are silently dropped.
- **None of these learns anything from the cut-off.** The timed-out candidate is discarded, not analysed for the input region that caused it.

Learning termination facts from data:

- **TpT** (Nori & Sharma, FSE 2013): fit a loop bound by regression over test traces, then validate with a verifier. Fitting takes about 0.001 s; validation up to 2,841.7 s.
- **DynamiTe** (OOPSLA 2020, https://arxiv.org/abs/2010.05747): guesses ranking functions and recurrent sets from bounded traces, then validates statically. It calls its own bounded-execution step "unsound"; a loop counting to 1000 run with bound 500 is "wrongly categorized as potentially non-terminating".
- **Conditional termination** (Cook et al., CAV 2008; Urban 2013): static, solver-based under-approximation of the terminating inputs.
- The sub-researcher found **no work that learns a guard for the terminating inputs from timeout-labelled samples alone** inside a synthesiser (weak negative: search budget ran out before 2023–2026 could be swept).

### 6.4 The standard recipe

1. **Total evaluator with three outcomes.** Catch every crash; count steps, not wall-clock time. Label each run good / crash / fuel-exhausted. Keep the three distinguishable.
2. **Sample a small scope, stratified.** Many inputs over small domains, stratified by predicate cell so that rare coincidences (equal arguments, empty lists) are populated; add boundary values deliberately.
3. **Start with few or no predicates** over inputs and cheap observers (length, sign, emptiness, equality and order between arguments).
4. **Find conflicts.** Hash samples on their predicate vector. A bucket with mixed labels proves the current predicates are insufficient.
5. **Resolve one conflict by synthesising one predicate.** Enumerate Boolean expressions by size until one separates a bounded conflict group (PIE used 16).
6. **Learn the Boolean combination with an Occam bias**: smallest k-CNF, greedy set cover over cells, or an entropy-split decision tree. Conjunction-only learners fail on commutativity-style guards, where "disjunctions abound".
7. **Attack the guard.** Search for a bad input it admits and a good input it rejects; add them; repeat until stable across a doubled sample.
8. If the guard must be inductive (hold across recursive calls), feed implication pairs as well (ICE).
9. **Fuel-exhausted runs:** re-run with geometrically larger fuel before treating them as bad; optionally fit an input-dependent step bound from the terminating runs and label by "exceeds bound × margin".
10. **Store the guard as a conjecture** with its sample and scope.

Smallest sound version: steps 1–7 on top of an existing enumerator and evaluator are an estimated 300–600 lines.

### 6.5 Known failure modes

- Overfitting to the sample (Daikon's one-third; Proviso's 70–87% truly safe-and-maximal even with a concolic teacher).
- The predicate grammar is the real input in every system, and enlarging it hurts.
- Small-scope sampling misses large thresholds.
- Rare cells need an engineered sampler.
- Timeout labels are not facts.
- Validation, where attempted, dominates cost by orders of magnitude.
- No guarantee without a verifier: results are "likely", or "modulo a test generator".

## 7. Inverse, solver and propagator discovery

### 7.1 Program inversion proper

| System | What it does | Measured | What is supplied / limits | Maturity |
|---|---|---|---|---|
| **Universal Resolving Algorithm** (Abramov & Glück, 2000–2002) | Inverse *interpretation*: given program and output, enumerate inputs by driving a process tree breadth-first. Produces answers, not an inverse program | Abstract only: "sound and complete, and computes each solution for which the given program terminates, in finite time" | A semi-decision procedure; cost is paid again for every query; originally for tail-recursive programs | PROVEN-RESEARCH as a concept (same as narrowing in Curry or miniKanren) |
| **Dijkstra/Gries inversion; Janus; Glück & Kawabe LRinv** | Structural: invert statement by statement when every primitive has a known inverse and nothing is discarded | ~10-line first-order programs | Per-primitive inverse table; fails on non-injective or value-discarding code | PROVEN-RESEARCH |
| **miniKanren relational interpreters** (Byrd et al., ICFP 2017) https://www.cs.tufts.edu/~nr/cs257/archive/william-byrd/kanren-solving-pearl.pdf | Run an evaluator written as a relation backwards | Quines and small programs; the authors: "can't synthesize complete recursive programs much larger than append" | Interleaving search can starve | PROVEN-RESEARCH |
| **PINS** (Srivastava et al., PLDI 2011) https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/pldi11-inverse-synthesis.pdf | Template for the inverse (forward program's control skeleton with holes, candidate expressions mined from the forward text); symbolic execution of paths through `P; P⁻¹` prunes instantiations | 14 programs of 5–25 lines (LZ77, Base64, arithmetic); 1.07 s to 1,810 s; search spaces of 2^3 to 2^37 reduced to 1–4 candidates | "It is still up to a human to identify the final template"; library axioms (LZW needed 15); "PINS does not guarantee their correctness" | SINGLE-PAPER |
| **GENIC** (Hu & D'Antoni, PLDI 2017) | Model the program as a symbolic transducer; invert transition by transition with a SyGuS call each; injectivity = disjoint images | 13 of 14 real string encoders/decoders (abstract only) | Finite-state, bounded-lookahead programs; injectivity undecidable in general | SINGLE-PAPER |
| **Synbit** (OOPSLA 2021) https://ar5iv.labs.arxiv.org/html/2108.13783 ; **Optician** (POPL 2018) | Synthesise the backward half of a bidirectional program from the forward half used as a sketch | Synbit 13 of 15 in ≤ 5.6 s; Optician 39 of 39 bijective string lenses under 5 s | Fails when the inverse needs a different recursion shape | SINGLE-PAPER each |

### 7.2 Inverse semantics inside synthesisers

- **Hand-written in every system checked.** FlashMeta/PROSE witness functions "can be written by a domain expert" (https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/oopsla15-pbe.pdf); Duet's inverse semantics are per-operator rules; λ²'s deduction rules are per-combinator and are worth about 6× in its ablation.
- **No paper was found that learns witness functions or inverse semantics automatically** (weak negative: search was cut short).
- **What has been learned is forward abstract transformers**, which are propagators in the owner's sense:
  - **Atlas** (CAV 2018, https://ar5iv.labs.arxiv.org/html/1804.04152): learns predicate templates and 30–59 abstract transformers in 10–23 s from 4 training problems, and the learned abstractions run 8.3–9.2× faster than hand-written ones. Requires the DSL's logical (SMT) semantics. SINGLE-PAPER.
  - **Amurth** (OOPSLA 2022, https://ar5iv.labs.arxiv.org/html/2105.00493): two counterexample loops (a concrete input whose output escapes the abstract output is a soundness counterexample; a strictly smaller sound abstract output is a precision counterexample). 57 transformers at 4 s to 1,984 s each; found four soundness bugs in hand-written transformers. Requires a per-domain DSL and sometimes a template; too rich a DSL caused timeouts. PROVEN-RESEARCH for forward transformers (Atlas, Amurth, Amurth2).
  - **Moito** (2024, abstract only): for monotone operators an interval semantics follows "for free from the concrete semantics". SINGLE-PAPER.
- **Constraint-propagator generation** (older, constraint-programming side): Apt & Monfroy (CP 1999, https://arxiv.org/abs/cs/9909010) derive propagation rules from the extensional table of a finite constraint; Abdennadher & Rigotti (TOCL 2004, https://ar5iv.labs.arxiv.org/html/cs/0409030) mine CHR propagation rules such as `append(X,Y,Z), Y=[] ⇒ X=Z` and `min(X,Y,Z) ⇒ X=Z ∨ Y=Z` by testing candidate left-hand sides against the constraint's definition, with the candidate atoms supplied by the user. The paper reports no rule counts or timings and says the raw output is highly redundant. PROVEN-RESEARCH (two independent lines), small scale.
- **Opera** (PLDI 2024): derives streaming algorithms from batch programs, 50 of 51 tasks, using supplied fold/map axioms and a computer-algebra system. Solver discovery in a loose sense; SINGLE-PAPER.

### 7.3 Recognisers discovered rather than supplied

- **AutoML-Zero** (https://arxiv.org/abs/2003.03384): evolution over 65 supplied numeric operations at 10,000 models/s/core on 10,000 workers for 5 days (order of 10^12–10^13 evaluations) rediscovers linear regression, gradient descent and normalised-gradient idioms. Acceptable linear regressors are about 1 in 10^7 random programs; harder targets "as rare as 1 in 10^12". SINGLE-PAPER at that scale.
- **OEIS Superseeker**: "115 or so" hand-coded transforms.
- **Gauthier & Urban** (Section 8): self-learned OEIS programs, with a small trained network.
- **No verified precedent** exists for a non-neural synthesiser that, from I/O data and primitives not already containing the idea, invents an analysis routine of the autocorrelation class. Autocorrelation itself is short (about 10 nodes) *if* `shift`, pointwise product, `sum` and `argmax` are primitives and the scoring gives partial credit. Whether those are present is a design decision, not a literature result.

### 7.4 Most reliable route to an inverse of a given `f`

1. **Find it as a law.** The Section 1 explorer discovers `g(f(x)) = x` whenever `g∘f` is within its size bound: QuickSpec finds `reverse (reverse xs) = xs` and, for octonions, `x⁻¹ * (x * y) = y` (verified in the JFP paper). This covers inverses that are short compositions of library functions.
2. **Structural inversion** when primitives carry inverses and nothing is discarded. Exact and search-free. The per-primitive inverse table is itself discoverable by route 1.
3. **Skeleton-guided enumerate-and-test.** Reuse `f`'s recursion skeleton as the template for `g`, mine vocabulary from `f`'s text, fill holes by enumeration, test `g(f(x)) = x` on samples (PINS, Synbit, Optician). Reach: 5–25-line programs.
4. **Per-case inversion with image guards** (GENIC). The image predicate of each case *is* the guard for where that branch of `g` applies; disjoint images = injectivity. For non-injective `f` the honest outputs are a right inverse (`f(g(y)) = y`) or a set-valued witness.
5. **Generic backwards execution** as an oracle for single small queries only.

Unconstrained enumeration of `g` with only the round-trip test has no published success beyond `append`-sized programs, and round-trip testing on samples cannot establish injectivity or totality.

## 8. LLM-free versus LLM-guided discovery, 2023–2026 (calibration only)

The kernel is LLM-free by design; this section only fixes what pure search has and has not achieved on shared benchmarks.

- **FunSearch** (Nature 2024, https://www.nature.com/articles/s41586-023-06924-6): evolutionary search in which an LLM mutates a program skeleton's priority function. About 10^6 LLM samples per run; "only four out of 140 experiments" found the size-512 cap set in dimension 8. **AlphaEvolve** (2025, https://arxiv.org/abs/2506.13131): the successor; "thousands of LLM samples suffice". Both are SINGLE-GROUP systems with real mathematical results. In both, the human supplies the program skeleton and the evaluator; the search fills in one function.
- **ARC-AGI-1, private set.** icecuber's 2020 brute-force search over a hand-built DSL: about 20%. Best DSL-search entry in 2024: 40%. Test-time-trained neural entries in 2024: 53.5–55.5% (https://arxiv.org/abs/2412.04604). On the public evaluation set with a comparable DSL: icecuber 160 of 400, GPT-4 32, DreamCoder 18 (https://arxiv.org/abs/2402.03507). icecuber's DSL took "a bit over a month of full time work" after hand-solving 200 tasks; its depth-2 search solves 129 of 419 public-evaluation tasks in 70 seconds on a laptop. The ARC Prize 2025 report (https://arxiv.org/abs/2601.10904) does not mention any pure DSL-search result on ARC-AGI-2.
- **Gauthier & Urban, OEIS program synthesis** (LLM-free, from random initialisation). 13 operators including `loop` and `compr`. Unguided generation 0 finds 993 solutions; a self-trained tree network on CPU reaches 27,987 sequences after 25 generations in "less than 100 CPU days" (https://arxiv.org/abs/2202.11908). With a small translation model trained from scratch each iteration: 3,771 → 78,118 over 190 iterations and about three GPU-months (https://arxiv.org/abs/2301.11479). New solutions per generation fell from 8,438 to 187 in the first system. Their attempt to add macro definitions (a library) was "so far inconclusive". This is the strongest LLM-free compounding curve found; **it compounds through a retrained policy network, not a library**, and it uses neural training.
- **Same-benchmark comparisons (2024).** HySynth (https://arxiv.org/abs/2405.15880): hybrid 58%, unguided search 40%, LLM alone 6% on 299 tasks. SyGuS, 609 benchmarks at 600 s (https://arxiv.org/abs/2403.03997): LLM only 49.8%, uniform A* enumerator 50.7%, cvc5 68.1%, LLM-guided enumerator 80.1%. Chompy (Section 1.6): enumeration recovered 73.3% and 57.1% of hand-written conditional rules where an LLM-only baseline recovered 9.8% and 3.1%.
- **Rule synthesis and lemma discovery remain enumeration-led.** Enumo's 2026 extended paper adds LLM operators as one more workload source; Lemmanaid (2025) has an LLM propose lemma *templates* that symbolic search fills; the IJCAR 2024 Vampire result uses plain QuickSpec.

Reading: on small formal DSLs with tight budgets, classical enumeration was equal to or better than 2023–2024 LLMs used alone, and hybrids won. Enumeration's results always came with a hand-built DSL. The sub-researcher reports that the arcprize.org leaderboard on 2026-11-24 shows frontier LLMs above 90% on ARC-AGI-1 and -2; that reading was not cross-checked and there is no 2026 same-benchmark DSL-search comparison.

## 9. Brute force with fast evaluation

### 9.1 Evidence

| Source | What was sped up | Result |
|---|---|---|
| **Massalin 1987** https://www.cse.iitm.ac.in/~krishna/courses/2022/odd-cs6013/MassalinCANews87.pdf | Exact Boolean equivalence test (40 programs/s) replaced by running a few test vectors (50,000 programs/s), plus tables of known-suboptimal sub-sequences | Reach went from 3 instructions to 12 "in several hours" on a 16 MHz 68020, over a 10–15-opcode table. A 1,250× faster test plus pruning bought 9 instructions. About 300 lines of assembly. Output unverified |
| **GNU superopt** (README) | — | About 5 instructions practical; the longest ever, 7, "took several weeks" |
| **Bansal & Aiken 2006** | Fingerprint on test vectors, 500,000 sequences/s; canonical register/constant naming (50–60× fewer sequences at length 3) | Exhaustive only to **length 3** over real x86, yet useful because results are banked in a lookup table |
| **STOKE 2013** https://theory.stanford.edu/~aiken/publications/papers/asplos13.pdf | Test-case emulator "just under 500,000" evaluations/s vs symbolic validator "well below 100" per second | MCMC search is only usable at emulator speed. Still fails three Hacker's Delight tasks because near-misses are indistinguishable by the cost function |
| **Lens 2016** | Bidirectional enumeration with refined equivalence classes | From 3 to at most 5 ARM instructions in an hour (11× search-time reduction) |
| **Paresy** (PLDI 2023) https://arxiv.org/abs/2305.18575 | Regex candidates represented as bit-vectors over the infix closure of the examples, stored in a write-once "language cache"; GPU | On average 19.1 billion regexes checked in 4.12 s on GPU vs 4,465 s on CPU (1,077×). The CPU version already beat the prior tool by up to three orders of magnitude. "Available memory" is "the scalability limit" |
| **LTL on GPUs** (CAV 2024) https://arxiv.org/abs/2402.12373 | Same idea for temporal formulas | "2048 times more numerous, and on average at least 46 times faster", giving up minimality. A 2025 follow-up hedges that part of this may be "a lucky fluke" of an inexpressive language |
| **Sorting kernels** (Ullrich & Hack, CGO 2025) https://compilers.cs.uni-saarland.de/papers/ullrich_sorting_kernels.pdf | Pruning heuristics and cuts vs hardware | n = 3: single core 56 s; parallel 17 s; GPU 46 s; **with heuristics and cuts 97 ms**. n = 5: 11 minutes on a laptop vs about 1,050 minutes for AlphaDev's reinforcement learner. Pruning ≈ 580×; hardware 1.2–3.3× |
| **Exhaustive Symbolic Regression** | More compute | Authors: could not extend maximum complexity "by ≳ 1" (Section 2.5) |
| **Equational Theories Project** | Exhaustive finite models | All magmas of size ≤ 4 in 165 CPU-hours settled 96.3% of false implications; size 5 (3×10^17) unreachable (Section 1.7) |
| **AutoML-Zero** | 10,000 models/s/core; functional-equivalence cache (4×) | Needed 10^12-scale evaluation counts on 10,000 workers |
| **Knuth; Codish et al.** | Bit-parallel truth tables; symmetry and subsumption | All 5-variable Boolean functions to 12 gates (class representatives gave "a thousand-fold speedup"); 9-input sorting networks at about 9 single-core years, with the search space cut from 3.7×10^15 to 5.6×10^4 at 10 comparators by symmetry and subsumption |
| **PySR's evaluator** | Tree interpreter over columns vs naive `eval` | 607 ns vs 117,000 ns per expression over 100 rows; equal to hand-written code |

### 9.2 The arithmetic

If the effective branching factor per AST node is `b`, a speedup of `S` buys `log_b(S)` extra nodes.

| Setting | b | Extra nodes from 1000× |
|---|---|---|
| ~100 primitives, raw (no dedupe) | ~78 | 1.6 |
| ~30 primitives, raw | ~24 | 2.2 |
| ESR runtime, 8 operators | ~12 | 2.8 |
| ~10 primitives, raw | ~9 | 3.1 |
| ~100 primitives with OE (icecuber) | 15–20 | 2.3–2.6 |
| ~30 primitives with OE (SyGuS string/bit-vector) | 4–10 | 3–5 |
| ~10 primitives with OE (Probe's small grammar; Speculate) | 2–3 | 6–10 |

(Raw ratios are my exact term counts for untyped grammars with 3/3/4, 6/8/14/2 and 15/30/50/5 leaves/unary/binary/ternary symbols; OE ratios are measured, Section A.)

Two honest conclusions:

1. **Speed alone buys 2–5 nodes at realistic grammar sizes.** It does not turn a 12-node search into a 30-node search. Memory for the dedupe table runs out before time does (TRANSIT 3.5 GB at size 10 unpruned; QuickSpec at size 8; Paresy; icecuber's 20× memory per depth).
2. **Speed has threshold effects that matter more than depth.** Several algorithms only *function* above a speed threshold: MCMC superoptimisation, test-vector fingerprinting, value-vector dedupe itself, exhaustive small-model refutation. And where pruning and hardware were measured on the same task, pruning won by two orders of magnitude.

What reliably multiplies with fast evaluation: columnar evaluation over a fixed input panel with memoised sub-term value vectors (each new term costs one operator application over the panel, not a full re-evaluation); a tree interpreter rather than per-candidate compilation; two-stage testing (a handful of discriminating inputs first, the full panel only for survivors); canonical naming of variables and constants.

### 9.3 arXiv:2611.17309, "Classical Energies Learn to Reason 1,000x Faster than Looped Models" (Hoover, Blayney, Whittington; submitted 12 Nov 2026, v2 19 Nov 2026)

Fetched and read (https://arxiv.org/abs/2611.17309).

- **What it is.** CRAM is a trainable version of the Hopfield–Tank energy: a pairwise graphical model over puzzle cells (a cost for each pair of cell values, plus input costs), trained by a local objective (pseudolikelihood) with no backpropagation through a solver. Inference is noisy single-cell descent on the energy (a focused Gibbs search with a few independent chains) with an energy threshold as the stopping rule.
- **Numbers.** 99.996% of Sudoku-Extreme and 100% of Maze-Unique test puzzles after 42 ms and 132 ms of training on one H200 GPU; at least 1,000× faster to train than looped baselines (which take 1.2–23 hours) and at least 282× fewer inference FLOPs. The Maze energy has 18 parameters; the Sudoku energy ends with about 7.7K nonzero parameters. Also evaluated on N-Queens and graph colouring.
- **Why it works, in the paper's words.** These puzzles "belong to a category of logic puzzles that CRAM's pairwise energy can represent exactly". The learned Sudoku weights are the rules: positive equal-digit costs "on exactly the 810 cell pairs that share a row, column or box". "A hand-set CRAM energy with one unique weight value solves every Sudoku-Extreme test puzzle, and one with three values solves every Maze-Unique test maze."
- **Its caution.** High accuracy on these benchmarks "does not indicate that a model can scale to harder tasks such as ARC-AGI-1, where the answer depends on quantities that the model must compute"; a high score "only shows that a model has learned a few pairwise rules between answer cells".
- **Caveats.** A two-week-old preprint; CRAM timings are warm and baseline timings cold (disclosed); structural priors (locality, translation invariance, digit symmetry) are supplied.
- **What transfers.** The result is about a *tiny hypothesis space matched exactly to the problem* plus a *local training objective*, not about fast evaluation of a large search space. The learning itself needs GPU training and is outside the owner's constraints. The non-learned analogue is classical: **constraint acquisition** (keep every candidate pairwise constraint never violated by solved examples; the paper itself cites that literature) followed by propagation or min-conflicts local search. That is a credible, cheap route to *propagators for finite-domain relational structure*, and it connects to the Apt–Monfroy and Abdennadher–Rigotti rule generators in Section 7.2. It does not transfer to program or law search, which lacks the pairwise-local shape. The methodological lesson does transfer: check that a trivial hand-written hypothesis does not already solve the benchmark before crediting a search method.

## A. What enumeration reaches: the quantitative table

### A.1 Measured growth: syntactic terms versus observationally distinct classes

| Source (grammar) | Counted | Numbers | Reduction |
|---|---|---|---|
| Speculate Table 4 (`+ abs id 0 1`, 2 variables) | expressions / classes up to size s | s=3: 44 / 12; s=5: 748 / 36; s=7: 16,492 / 114 | 145× at size 7. Terms grow ~4.7× per node, classes ~1.6–2× |
| Speculate, same with 3 variables | | s=7: 30,285 / 287 | 105× |
| Probe (4 leaves, `concat/2`, `replace/3`; 2 examples) | OE bank per size | 349 / 714 / 2,048 at sizes 8 / 9 / 10; height 1 goes "from 80 to 15" | 62–264× against my syntactic count for that grammar |
| QuickSpec (pretty printer, 3 variables) | terms of size ≤ 9 | "approximately 10^6" → 10^4 when built from representatives | 100× |
| QuickSpec (33 list functions) | terms explored to size 7 | "over 50 000" | (typed; geometric mean ~4.7× per node) |
| TRANSIT (~20 typed functions, 10 examples) | expressions explored | "two to three orders of magnitude fewer" above size 10 | 100–1000× |
| Duet Table 2 (SyGuS) | OE components up to size n | bit-vector: 464 → ~1,850 → 44,023 for n = 3, 4, 5; string: ~20 → ~75 → ~330 for n = 2, 3, 4 | — |
| ESR (8 operators, 1 variable, complexity ≤ 10) | trees | 168M strings → 5.2M valid → 134,234 unique | 39× (symbolic, not OE) |
| FrAngel (~100 typed Java components, no OE) | programs per size | 30K (size 5), 800K (6), > 10M (7) | none applied; 12–27× per node |
| icecuber (142 unary image transformations) | time per extra depth | ×15 (2→3), ×20 (3→4) | against ×142 raw |
| Codish (36 comparators) | networks modulo symmetry and subsumption | 55,991 at 10 comparators | against 3.7×10^15 |
| Raw untyped counts (my arithmetic) | terms per node, asymptotic | ~10 primitives: ×9; ~30: ×24; ~100: ×78 | — |

Effective branching per AST node after dedupe, inferred: **2–4 for ~10 primitives; 4–10 for ~30; 10–25 for ~100.** No source measures it for a typed recursive functional grammar, which is the number this project most needs and should measure on its own VM.

### A.2 Verified reach (what was actually exhausted or solved, in what time)

| Primitives | System | Reach | Time, hardware |
|---|---|---|---|
| ~5–6 | Speculate (`+`, `abs`, 3 variables) | all expressions to size 6, inequalities and conditions to size 5 | 2 min 37 s |
| ~6 | Probe size-based baseline | size 10 in 1 s; size 19 not in 20 min | laptop, Scala |
| 4–9 | Ruler (bool; bit-vectors) | 3 connectives per side | 0.06 s; 4.3 s (bv4); 630 s (bv32, SMT-validated) |
| 8, one variable | ESR | complexity 10 | ~150 CPU-hours incl. fitting |
| 10–15 opcodes | Massalin | 12 instructions | "several hours", 16 MHz, 50,000 programs/s |
| 15+ (count not stated) | Enumo on Halide's grammar | 5 atoms on operator subsets, 4 on the full set, "beyond which ... computationally infeasible" | not stated |
| 14 | Chompy (conditional rules) | 1,579 rules deriving 57–73% of hand-written ones | 26 min |
| ~17 | Probe at 1 h (Simba's re-run) | solved programs average size 6.5–7.9 | 1 h |
| ~20 typed | TRANSIT | size 15 in 2–13 min; size > 20 not in 30 min | 1 core |
| ~28 | EUSolver (Python) | string solutions of size 9–12 | 16–46 min |
| 33 typed | QuickSpec 2 | all terms to size 7, 398 laws; size 8 out of memory | 42 min; 2 h timeout |
| 26 typed | QuickSpec 2 | all terms to size 8, 586 laws | within 2 h |
| ~12 tensor operators (count FROM-MEMORY) | TASO | 4 operators (66M graphs) | not verified |
| 134 | TF-Coder | 5 operations / 11 nodes, with weights and 98.6% filtering; plain enumeration solves 39 of 70 | 65 s; 5 min limit |
| 142 unary | icecuber | depth 3 everywhere, depth 4 for half the tasks | 9 h, 16 GB, multi-threaded C++ |
| full x86 | Bansal & Aiken | length 3 | 500,000 sequences/s |
| magma laws, ≤ 4 operations | Equational Theories Project | every model of size ≤ 4 | 165 CPU-hours |

### A.3 Estimate table (ESTIMATE; not a published result)

Model (from the enumeration sub-report, arithmetic re-checked): evaluations needed to exhaust size `s` ≈ `r · b^s`, so `s ≈ ln(E·T/r) / ln b`, with `E` candidate evaluations per second, `r` ≈ 30 candidates evaluated per retained class, and `b` the post-dedupe branching per node. Cells are total AST nodes including leaves.

**With OE dedupe, E = 10^6/s** (a lean compiled enumerator with columnar evaluation):

| Primitives | b | 1 s | 1 min | 1 h | 10 h |
|---|---|---|---|---|---|
| ~10 | 3 (2.3–4) | 9.5 (7.5–12.5) | 13 (10.5–17) | 17 (13–22) | 19 (15–25) |
| ~30 | 6 (4–10) | 6 (4.5–7.5) | 8 (6–10.5) | 10 (8–13) | 12 (9–15) |
| ~100 | 15 (10–25) | 4 (3–4.5) | 5.5 (4.5–6) | 7 (6–8) | 8 (6.5–9) |

**With OE dedupe, E = 10^5/s** (a metered interpreter): subtract 2.1, 1.3 and 0.85 nodes from the three rows.

**Without dedupe, E = 10^6/s, untyped** (my exact counts; the floor):

| Primitives | 1 s | 1 min | 1 h | 10 h |
|---|---|---|---|---|
| ~10 | 7 | 9 | 11 | 12 |
| ~30 | 5 | 6 | 8 | 8 |
| ~100 | 3 | 4 | 5 | 6 |

Checks against A.2: ~30 primitives at about half an hour gives 9–10 in the model, against EUSolver's 9–12 and Probe's 6.5–7.9; ~10 primitives at 20 minutes gives about 16, against TRANSIT's 15 and Probe's failure at 19; ~100 primitives at one minute gives 5.5, against TF-Coder's plain-enumeration ceiling of about 3 operations (7 nodes). Agreement is within about ±2 nodes.

Three qualifications:

1. **Memory binds before time.** One hour at these rates retains about 10^8 classes, roughly 12 GB at 100 bytes each. On a 16 GB machine the 1-hour column is the practical ceiling unless value vectors are stored very compactly or the bank is partitioned.
2. **For laws the reach doubles.** A law relates two terms, so exhausting terms to size `s` finds laws of total size up to `2s`. QuickSpec's point: "exploring n² conjectures in O(n) time allows us to effectively find laws of double the size."
3. **QuickSpec runs at about 20 terms per second** (50,000 terms in 42 minutes, dominated by testing and completion). A lean kernel should exceed its size-7-over-33-functions point by two or three sizes on speed alone. The binding problem then becomes the number of laws printed (398 at size 7 was already "too many").

### A.4 What hours buy that seconds do not

By the model, 3,600× more time adds about 7.5, 4.6 and 3.0 nodes for ~10, ~30 and ~100 primitives; going from 1 hour to 10 hours adds 2.1, 1.3 and 0.85. Verified evidence points the same way:

- Unguided OE baseline on 127 string tasks: 74 solved at 3.4 s, 91 at 30 s (CrossBeam, Table 1).
- TF-Coder: 63 of 70 at 5 minutes; one hour adds 2; the other 5 are "simply too difficult".
- FrAngel: 47% at 10 s, 94% at 30 minutes.
- icecuber: depth 2 costs 15× less than depth 3 and solves "about 80% as many tasks"; depth 4 costs 20× more again.
- Speculate on regular expressions: size 5 in 17 min, size 6 in 1 h 26 min, size 7 (with inequalities also enabled) in 2 days 22 h.
- QuickSpec with 33 functions: size 7 in 42 min; size 8 not in 2 h.
- GNU superopt: 5 instructions routinely, 7 in "several weeks".
- Duet: a size-18 string program "cannot be found even within 6 hours" by OE enumeration and is found in 0.03 s by decomposition.
- ESR's authors: more compute would not extend maximum complexity "by ≳ 1".
- DreamCoder's enumeration baseline: "type-directed enumeration for 24 hours per task, generating and testing up to 400 million programs for each task". The paper reports that the full system "always solves the most held-out tasks" with a mean solve time of 54.1 s (per-domain baseline values are in figures only). This is the most direct published test of "just search for hours", and it lost to a learned library with about a minute of search.

Published timeouts are almost all between 1 minute and 2 hours per task; beyond that there are only the DreamCoder baseline above, Speculate's three-day run and the superoptimiser anecdotes. What moved the frontier in these papers was not time: OE (100–1000×), type and validity filtering (98.6% in TF-Coder), pruning with discovered laws (over 250× in Ruler), per-task curated grammars (Probe's baseline falls from 42 to 9 solved when grammars are merged; Myth 0.07 s → 128 s with five extra functions), and decomposition on examples or goals (EUSolver 787 vs 1; Duet).

**Direct answer to the owner's premise.** The evidence supports the premise that the budget was the critical oversight only in part. Supported: seconds-scale budgets sit three to seven nodes below what hours reach, and published law-discovery systems run for minutes to an hour, not seconds. Not supported: nothing in the record suggests that hours of the *same* rigid enumeration reach algebras, inverters and higher-order functors that minutes do not. The one from-scratch functor bootstrap took about 7,700 CPU-hours with a hand-chosen task set.

## B. The most reliable recipe, from SHIPPED and PROVEN-RESEARCH parts only

Target: discover algebraic laws, conditional laws with guards, inverses, and recursive list functions from a simulator, single-threaded, hours of compute, no neural training.

| # | Component | Source of confidence | Tag |
|---|---|---|---|
| 1 | **Total, fuel-metered evaluator** returning value / crash / fuel-exhausted, with step counts (not wall clock) | Escher's `err`; Ruler's null cvec entries; every synthesiser's timeout | PROVEN-RESEARCH |
| 2 | **Columnar evaluation over a fixed input panel**: each term carries its value vector; a new term costs one operator application over the panel | TRANSIT, Ruler cvecs, STOKE and Bansal–Aiken test vectors, PySR's evaluator | SHIPPED |
| 3 | **Size-ordered bottom-up enumeration, building only from class representatives**, typed, with a hash on value vectors | TRANSIT / EUSolver / Probe / TF-Coder / QuickSpec | SHIPPED |
| 4 | **Law discovery = collisions.** A new term whose vector equals a representative's is a conjecture; test it on a larger and partly exhaustive small-domain sample; print smallest-first | QuickSpec 2, Speculate, Ruler | SHIPPED |
| 5 | **Prune with the laws already found before evaluating anything**: orient each law large→small and normalise, or keep an e-graph and run the laws on it | QuickSpec's normal-form check (1000× fewer tests); Ruler's `run_rewrites` (350 s vs > 24 h) | SHIPPED / PROVEN-RESEARCH |
| 6 | **Schemas**: test the one-variable instance first, generalise only if it holds | QuickSpec 2 | SHIPPED |
| 7 | **Incremental signatures with background theories**: explore a few functions, bank the laws, add functions | QuickSpec's documented practice ("It is not sensible to run QuickSpec in such an undirected way") | SHIPPED |
| 8 | **Linear and conserved relations by null space** over the value vectors of enumerated terms, in exact arithmetic | Sharma et al. 2013; SID; Kaiser–Kutz–Brunton | PROVEN-RESEARCH |
| 9 | **Decomposition tests as oracle experiments** (symmetry, separability, argument-equal) to split a target before enumerating | AI Feynman's tests, applied with exact queries | PROVEN-RESEARCH (the tests); my adaptation to an oracle |
| 10 | **Conditional laws.** Candidate guards are Boolean-typed class representatives up to size ~4, each with a truth vector. Two terms are a conditional candidate under `p` when their vectors agree wherever `p` is true. Order guards by implication (truth-vector inclusion); keep only the weakest guard per law; drop a law whose guard implies a kept law's guard | Speculate; Chompy (26 min for 14 operators; no termination in hours without implication pruning); Alive-Infer | PROVEN-RESEARCH |
| 11 | **Guards the vocabulary cannot express.** Conflict-driven predicate synthesis: bucket samples by predicate vector, enumerate the smallest predicate separating a mixed bucket, learn a small k-CNF or decision tree, then attack the guard with new samples | PIE / LoopInvGen; Gehr et al.; Sankaranarayanan et al. | PROVEN-RESEARCH |
| 12 | **Totality guards**: the same learner with label "crash". For fuel exhaustion, re-run with geometrically larger fuel first, and record the guard as a conjecture | PIE for exceptions (PROVEN). The fuel part is engineering practice with no validated precedent | PROVEN-RESEARCH / unvalidated |
| 13 | **Inverses.** First as laws `g(f x) = x` from step 4. Then structural inversion from a table of primitive inverses. Then skeleton-guided enumeration reusing `f`'s recursion shape, tested by round trip, with per-case image guards | QuickSpec (laws); Dijkstra/Glück (structural); PINS, Synbit, GENIC (skeleton, per-case) | PROVEN-RESEARCH for the first two; SINGLE-PAPER each for the third |
| 14 | **Recursive list functions.** Enumerate arguments of recursion schemes (`fold`, `map`, `filter`, `unfold`) as higher-order components; or direct structural recursion with calls only on smaller arguments and recursive calls answered from the examples. Keep the component context minimal per task | λ², Myth, Escher, Burst, Trio; MagicHaskeller | PROVEN-RESEARCH |
| 15 | **Workload guidance.** Harvest candidate terms from task solutions and stuck expressions instead of exhausting the grammar | Halide TRS synthesis (4,127 rules), Bansal–Aiken, Enumo | SHIPPED-adjacent |
| 16 | **Divide and conquer on examples**: terms correct on subsets plus predicates, joined by a decision tree | EUSolver (787 vs 1) | PROVEN-RESEARCH |
| 17 | **Within-task re-weighting** from partial solutions when the grammar is large | Probe (9 → 25 of 70 on a bloated grammar) | SINGLE-PAPER, replicated once |
| 18 | **Library compression** by top-down corpus-guided abstraction search under an MDL objective, after each batch of solutions | Stitch (shipped tool); EC/DreamCoder loop | SHIPPED (compressor) / PROVEN-RESEARCH (loop) |
| 19 | **Utility accounting for everything learned**: per-item counters of uses, match cost and savings; delete what does not pay; audit that library entries are actually invoked | Minton; Soar; SAT clause deletion; the reuse audits of Section 4.5 | PROVEN-RESEARCH |

Expected single-threaded budgets if built this way, read off the measurements: unconditional laws over 20–30 typed primitives to term size 7–9, minutes to an hour; conditional laws with guards of size ≤ 4, tens of minutes per signature; a guard by conflict-driven synthesis, seconds; a recursive list function of 15–30 nodes from a minimal context, under a second, and from a 30-function context, minutes to never; library compression, milliseconds to seconds.

Where the hours should go, on this evidence: many small incremental explorations (step 7) rather than one large one; one or two extra size units on small sub-signatures; exhaustive small-domain validation of conjectures; attacking guards. Not: a single deep enumeration over the full primitive set.

One observation for the design discussion (my inference, not a literature claim). The only "geometric" object with measured value across this whole literature is the value vector on a fixed input panel: equality of vectors is observational equivalence; agreement on a subset is a conditional-law candidate whose guard is that subset; linear dependence among vectors is a conservation law; inclusion between Boolean vectors is implication. The only "topological" structure with measured value is the e-graph (regions of expression space connected by proved equalities). Both are PROVEN. Nothing surveyed uses a learned continuous embedding without neural training.

## C. Ambitions with no convincing precedent

1. **Reflection that compounds.** A synthesiser that takes its own search graph as data and learns pruning or strategy policies beyond fixed-form statistics. EURISKO is the direct attempt and its authors report five years of "mediocre results" and a 60/40 human share. PRODIGY and Soar learned control rules from traces and ran into the utility problem. SAT solvers succeed with fixed-form lemmas and counters, where failures have computable explanations. OOPS showed one hop of transfer. No LLM-free system has been shown to synthesise its own search policy and keep improving.
2. **Self-generated curriculum.** None. OOPS "does not by itself invent an appropriate series of easier subtasks"; DreamCoder calls it "a necessary next step"; PowerPlay's self-invented tasks have no external meaning. Every measured bootstrap depended on a dense, graded, externally supplied task set, and EC's performance "drops to 0" without one.
3. **Higher-order functors from first-order primitives in hours on one thread.** One precedent exists (DreamCoder's origami run): about 7,700 CPU-hours, 20 selected tasks, no independent reproduction found.
4. **Inverters and recognisers of the autocorrelation class invented from I/O data.** None without neural guidance or 10^12-scale evolution over primitives that already contain the idiom.
5. **Learned inverse semantics / witness functions.** None found. Forward abstract transformers have been learned (Atlas, Amurth), given formal semantics and a per-domain DSL.
6. **Termination guards learned from timeouts.** None found; the nearest tools call their own bounded-execution labels "unsound" and rely on a static validator.
7. **Conditional laws with unrestricted searched guards.** Demonstrated only at guard size ≤ 4 (Speculate) or over a supplied predicate workload (Chompy), and QuickSpec's authors declined to attempt it.
8. **Hours-long single-threaded enumeration producing qualitatively new discoveries.** No paper reports it; the measured return is one to two nodes per decade of time.
9. **Cross-domain accumulation in one library.** Not shown; DreamCoder learns each domain separately and poses the unified library as an open question.
10. **Libraries whose entries are verified to be reused.** Reuse audits are rare, and where done they are discouraging.
11. **A single topology–geometry kernel subsuming these.** Nothing in this literature attempts it. The components that work are separate and simple: value vectors, hash tables, rewrite systems or e-graphs, decision trees.

## D. Negative results and cautionary tales

- **AM/EURISKO** (Section 4.6). Success came from "the density of worthwhile math concepts as represented in Lisp"; the reflective layer did not bootstrap until humans redesigned the representation; the celebrated result was "about 60/40% Lenat/EURISKO"; nothing has been reproduced from the recovered sources. Ritchie & Hanna's methodological critique: the published account did not let others build on it.
- **DreamCoder's authors on their own from-scratch result**: "approximately a year of total CPU time", and "We do not advocate such blank-slate learning as a route to AI".
- **EC's curriculum cliff and plateaus**: zero performance without easy tasks; trajectories "stuck in a local minimum around 50%".
- **The utility problem**: PRODIGY kept 4–6% of what it learned and was 65% slower without utility validation; five Soar chunks caused a 25× slowdown. Macro-operators sometimes degraded performance.
- **Library learning that "doesn't"**: one reuse among 20,000 learned lemmas; no-reuse ablations matching the full system; 1.04× compression on real code.
- **Bigger grammars hurt**: LoopInvGen degrades in 65% of cases; Probe's baseline falls from 42 to 9; Myth slows by three orders of magnitude with five extra functions.
- **Learned guidance decays with program length**: a re-implementation of DeepCoder solves 63% at length 5 and 2% at length 14.
- **Deeper exploration does not mean better laws**: TheSy's authors say larger depth "greatly affects the run-time, but does not lead to many useful lemmas"; QuickSpec at 33 functions "does, however, generate too many laws".
- **Scale in rule synthesis came from human workloads** (Enumo), and the tail in the Equational Theories Project needed months of human construction for single implications.
- **Headline baselines are often weak**: Probe's 44 is height-based (size-based gets 84 of its 91); Euphony's gains vanish against size-based search; TF-Coder's learned models add 2 tasks, where removing hand-set weights loses 10 and removing filters loses 19.
- **Benchmark monoculture**: recursion synthesis is evaluated on the same 43–65 small functions with per-task contexts.
- **BACON** was "only presented with terms relevant to the final law". **Schmidt & Lipson's** invariant criterion is "flat for general systems" per Hillar & Sommer. **OOPS** needed author-chosen helper tasks and hand-boosted instruction probabilities. **PowerPlay** invented 67 fovea trajectories and solved no external task.
- **Daikon**: about a third of inferred clauses incorrect or irrelevant. **Timeouts** as non-termination evidence are unsound by the tools' own statements.
- **Constant-factor speed**: ESR could not gain more than one complexity unit; pruning beat hardware by two orders of magnitude on sorting kernels.
- **Trivially solvable benchmarks**: the CRAM paper's own point is that a hand-set energy with one weight solves every Sudoku-Extreme puzzle, so high scores there say little.

## E. Verification status and gaps

- **Read first-hand by me today** (PDF text or page): QuickSpec 1 and 2, Speculate, Ruler, Enumo (2026 extended version), Chompy, TheSy (ar5iv), CCLemma (partial), HipSpec (partial), Halide TRS synthesis, Bansal & Aiken, the Equational Theories Project paper (first 100K characters), the CRAM paper, Probe's evaluation section, DreamCoder's compute passages and origami setup, EC² Table 3, Lenat & Brown (partial).
- **Verified by sub-researchers** with URLs and quotes, not re-read by me except where noted: everything else marked with a URL. Their full notes are the appendices below. I spot-checked the Probe baseline numbers, the EC² table, the DreamCoder origami figures and the CRAM claims against the source text; all matched.
- **FROM-MEMORY items** are tagged in place. The main ones: the list of laws BACON rediscovered; ABACUS and COPER mechanisms; IGOR2's algorithm; Denali; IsaCoSy details; LOC estimates throughout (all are estimates); TASO's exact count of 28,744 substitutions (course slides say "~29,000" and 743 after pruning).
- **Coverage limits.** Three of four sub-researchers exhausted the shared web-search quota part-way and continued by direct fetch only. Consequently 2025–2026 coverage is incomplete and every "none found" in Sections 6 and 7 is a weak negative. Figure-only data (DreamCoder's per-domain ablations, most cactus plots) could not be extracted.
- **Not verified**: Ritchie & Hanna and Haase's Cyrano beyond abstracts; GENIC beyond its abstract; URA timings; Knuth's printed text (draft fascicle used); the current ARC leaderboard reading; whether any 2025–2026 work extends bit-parallel GPU enumeration to general synthesis.
- **A correction to the brief**: SyRup is PLDI 2023, not POPL 2023. DryadSynth (POPL 2024) uses an LLM for one of its techniques and is not LLM-free. FrAngel is random search, AutoML-Zero evolutionary, Souper solver-based.

## Appendices (full sub-researcher notes, per-system entries with URLs and quotes)

- Enumerative synthesis at scale: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/reports/lit-search-appendix-enum.md`
- Library learning, AM/EURISKO, Schmidhuber, LLM calibration: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/reports/lit-search-appendix-lib.md`
- Scientific-law discovery and fast evaluation: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/reports/lit-search-appendix-sci.md`
- Search policy, guards and totality, inverses: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/reports/lit-search-appendix-pol.md`

