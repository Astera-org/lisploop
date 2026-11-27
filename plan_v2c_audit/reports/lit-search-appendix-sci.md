# Literature notes: (A) law discovery by controlled experiment / symbolic regression, (B) brute force with fast evaluation

Compiled 2026-11-24. Purpose: calibrated review (maturity, measured scale, failure evidence) for an LLM-free,
single-threaded, enumerative program-induction kernel with a deterministic simulator as oracle.

## Conventions

- **VERIFIED** = I fetched the source during this session and read the passage. URL plus a short quote or table reference is given.
- **FROM-MEMORY** = not verified online in this session (source paywalled, blocked, or search budget exhausted). Treat as a lead, not a fact.
- **MY-ARITHMETIC** = a number I derived from verified numbers; the derivation is shown.
- **ESTIMATE** = my own judgement (e.g. lines of code); no source.
- Maturity tags: SHIPPED / PROVEN-RESEARCH (several independent implementations) / SINGLE-PAPER (includes single-group lines of work) / SPECULATIVE.
- The web-search budget for the session ran out part-way through. After that only direct fetches of known URLs were possible, which is why items 1 (ABACUS, COPER, IDS detail) and 6 (GNU superopt, Denali) have FROM-MEMORY parts.

---

## Cross-cutting summary

### What transfers to a simulator-oracle setting

1. **BACON's experiment design** (vary one independent term, hold the rest; once a law is found at a level, do not re-vary that term). Transfers verbatim. Noise handling, BACON's admitted weak point, is moot for a deterministic simulator: constancy becomes exact equality.
2. **FAHRENHEIT's scope search**: after a law is found, search for the boundary of the region where it holds, then look for laws *on the boundaries* ("boundaries of boundaries"). This is the closest published match to "guards are regions where a law does not hold".
3. **AI Feynman's decomposition tests**. The paper says the neural net exists only because "we need to be able to evaluate f at points ... of our choosing where we typically have no data". With an oracle, translational/scaling/product/sum symmetry, additive and multiplicative separability, and set-two-variables-equal are direct queries with exact equality instead of 7x/10x-NN-error thresholds.
4. **Null space of a monomial library evaluated on sampled states** (Sharma et al. 2013 for program loops; SID 2023 for ODEs; Kaiser et al. 2018 with SINDy). Exact over rationals, complete within the chosen span, no training.
5. **Semantic (value-vector) deduplication**: Paresy's "language cache" of characteristic bit-vectors; ESR's duplicate removal. Enumerate semantics, not syntax.
6. **Two-stage testing** (Massalin 1987, STOKE 2013): a few hand-chosen discriminating test vectors reject almost all candidates; the expensive check runs only on survivors.
7. **Meet-in-the-middle hash join** (Ramanujan Machine): enumerate left and right sides separately at low precision, hash, re-verify hits at high precision. O(M+N) instead of O(MN).
8. **A columnar interpreter beats per-candidate compilation** (DynamicExpressions.jl README: 607 ns interpreted vs 117,000 ns for naive `eval` of the same expression over 100 rows).

### What does not transfer, or transfers only weakly

- Dimensional analysis (AI Feynman, COPER) needs units. A type system could play that role, but nobody in this slice shows it.
- AI Feynman 2.0's gradient-based modularity tests need derivatives; finite differences on an oracle are an approximation, not a verbatim transfer.
- Everything neural: AI Poincaré, Noether Networks, ConservNet, CRAM's learned energy.
- AI Descartes / AI Hilbert need a complete, consistent axiom set supplied by a human.

### The honest speed arithmetic (detail in item 8)

- ESR authors' own statement: "even greatly enhanced computational resources could not extend the maximum complexity by ≳ 1".
- Measured effective branching factors are small after deduplication (about 2.2 per cost unit for Paresy regexes, about 3.1 per node for ESR unique functions), so 1000x buys about 6-9 units, not 1-2. Before deduplication it is 2.8-4.5.
- In the one study that measured both on the same task (sorting kernels, n=3), heuristics and cuts gave about 580x; parallel CPU gave 3.3x; GPU gave 1.2x.

---

# (A) Law discovery

## 1. BACON.1-BACON.5, FAHRENHEIT, ABACUS, IDS, COPER

### BACON

**(i) What it does.** Production-system programs (Langley, Bradshaw, Simon, later Zytkow) that take independent and dependent terms from the user, run factorial-style experiments, and define new "theoretical terms" (products, ratios, slopes, intercepts) until some term is constant. Higher levels of description summarise lower ones.

**(ii) Heuristics and scale. VERIFIED** from the BACON.5 paper, https://ijcai.org/proceedings/1981/0026.pdf

- Five heuristics: "noting constancies; finding linear relations; detecting monotonic trends; postulating intrinsic properties; and reasoning by analogy".
- Trend rule: "If a monotonic increasing relation is found between two terms and the signs of their values are the same, then the ratio of those terms is defined"; decreasing gives a product.
- Experiment design: "it starts to run experiments by varying one of the terms and holding all others constant". BACON.5 then skips re-varying a term once the law at that level is known: "This method requires significantly less data than the complete factorial design technique used in earlier versions".
- Constancy test: mean times "a user-modifiable fraction (say 0.05)" gives an interval, with an allowed number of exceptions.
- Kepler trace: d and p rise together, so d/p; then d²/p; then d³/p² constant.
- Laws reported for BACON.5: Snell's law, conservation of momentum, Black's specific heat law, Joule's law; plus "the ideal gas law, Coulomb's law, Kepler's third law, Ohm's law, Archimedes' law of displacement, and Galileo's pendulum law and law of constant acceleration".
- Law class: "product and power laws, linear relations, and complex combinations of these forms". Largest law shown has about 4 variables (pV/nT; Snell with intrinsic properties).
- Compute: not stated in the paper. FROM-MEMORY: seconds to minutes on a 1980 machine.
- FROM-MEMORY: BACON.1 = constancy/trend rules on two variables; BACON.3 = levels of description; BACON.4 = intrinsic properties and common divisors (chemistry); BACON.5 = symmetry/analogy for conservation laws. Only the BACON.5 list above is verified.

**(iii) Failure modes and critiques. VERIFIED.**

- Authors' own admission (same paper): "it cannot adequately deal with noise; it cannot handle irrelevant variables; and the class of laws it considers is overly constrained".
- Pre-selected variables, authors' own words: "the program was only presented with terms relevant to the final law" and "we carefully avoided giving BACON.5 an extra term" that would have allowed cosine/tangent-like ratios in the Snell task.
- Control structure: "BACON.5 can consider only a single hypothesis at a time".
- External critique: Chalmers, French, Hofstadter 1991, https://consc.net/papers/highlevel.pdf : "BACON, in short, works only in a world of hand-picked, prestructured data"; "inadvertently guilty of 20-20 hindsight". They also note that students given the same table made the same "discoveries" within an hour.

**(iv) Maturity.** PROVEN-RESEARCH at toy scale (five versions by one group; the trend heuristics are widely re-implemented as teaching examples, FROM-MEMORY). Never shipped. No evidence of a discovery not known in advance.

**(v) Smallest sound version.** Constancy test, linear fit, monotone-trend term definition, one-variable-at-a-time experiment loop with recursion over levels. ESTIMATE 200-400 lines of Lisp. Intrinsic properties add maybe 100-200.

**(vi) Transfer.** The experiment design and the "define a term, test constancy" loop transfer directly, and exact arithmetic removes the noise problem. What does not transfer: the term generator is greedy (one hypothesis at a time) and restricted to products/ratios/linear forms. For program laws the term language must be the kernel's own enumeration; BACON's contribution is then only the *experiment schedule* (which variables to hold fixed), not the hypothesis space.

### FAHRENHEIT (Zytkow)

**(i)** BACON extended to find several regularities in one data set, the *scope* of each, and regularities among special points (maxima, minima, discontinuities, boundaries), with a real electrochemistry rig in the loop.

**(ii) VERIFIED**, Zytkow, Zhu, Hussam, AAAI-90, https://cdn.aaai.org/AAAI/1990/AAAI90-133.pdf

- "FAHRENHEIT searches for the scope of the laws it has discovered, it can find several regularities in data, change the order in which it varies independent variables, and detect irrelevant variables."
- "FAHRENHEIT has been able to find boundaries of regularities, regularities on boundaries and boundaries of boundaries."
- "the same recursive mechanism for generalization to new variables applies to all types of special points".
- Scale: one experiment located "60 maxima" and "nine regularities, including six constancies"; experiments of "several hour duration" (rig time, not CPU).
- Per-concept error estimates, unlike "a single error parameter for the whole system in BACON and ABACUS".
- Confirmed by Langley's 2024 retrospective, http://www.isle.org/~langley/papers/discovery.aaai24.pdf : the system used data "to identify maxima and minima that it incorporated into higher-level equations".

**(iii)** Authors' limitations section: the step from repeatability analysis to regularity finding "requires our intervention"; a procedural change "has not been automated and must be done manually". Law class is still BACON's. One domain demonstrated.

**(iv)** SINGLE-PAPER (single group, several papers 1987-1990). The earlier paper "Combining many searches in the FAHRENHEIT discovery system" (1987) was not retrievable; FROM-MEMORY for its content.

**(v)** On top of a BACON core: for each found law, bisect each independent variable for the edge of validity; treat edge location as a new dependent term and recurse. ESTIMATE 150-300 extra lines.

**(vi)** Direct match to the owner's picture. "Law holds here, find where it stops, then find the law governing the stopping point" is a guard-synthesis procedure that needs only an oracle. In a discrete deterministic simulator the boundary search is exact bisection or exhaustive scan rather than curve analysis. Not shown anywhere: scaling beyond a couple of independent variables, or boundaries that are not axis-aligned.

### ABACUS (Falkenhainer & Michalski, Machine Learning 1:367-401, 1986)

Citation VERIFIED via the reference list of the Zytkow paper above; content **FROM-MEMORY** (Springer copy requires cookies; the GMU archive PDFs I opened were other reports).

- FROM-MEMORY: ABACUS searches for several equations, each fitting a subset of the data, then hands the subsets to the AQ rule learner to induce a symbolic precondition per equation ("if substance = X and T < c then law 1"). Uses dimensional-unit compatibility to prune term formation.
- FROM-MEMORY critique: clustering by "which equation fits" depends on a tolerance; one global error parameter (this part VERIFIED by Zytkow's remark quoted above).
- Maturity: SINGLE-PAPER (one follow-up, ABACUS.2, FROM-MEMORY).
- Transfer: "label each sample point by which candidate law it satisfies, then learn a classifier over the inputs" is the generic recipe for guards. With exact arithmetic the labelling is unambiguous, which removes ABACUS's main fragility.

### IDS (Nordhausen & Langley)

**VERIFIED** only at summary level, Langley 2024 (URL above): IDS "created a taxonomy from observed qualitative states of an environment, induced qualitative laws about temporal relations among these states, and found numeric relations both within and between the states"; it "rediscovered ... contextualized versions of Black's heat law and conservation of momentum".

- Relevance: numeric laws are attached to qualitative states, so the state *is* the guard. Mechanism details FROM-MEMORY.
- Maturity: SINGLE-PAPER.

### COPER (Kokar 1986)

**FROM-MEMORY** entirely (not retrievable). Uses dimensional analysis (Buckingham pi) to decide whether the set of arguments is complete and to constrain the functional form. Transfer is weak without units.

### What these say about finding where a law holds

Three distinct published mechanisms: (a) FAHRENHEIT: boundary search per variable after the law is found, recursion on the boundary (verified); (b) ABACUS: partition data by which equation fits, then learn a symbolic description of each part (from memory); (c) IDS: discover qualitative states first, then laws inside each state (verified at summary level). None reports scale beyond a handful of variables, and none was independently replicated.

---

## 2. Schmidt & Lipson 2009, "Distilling free-form natural laws from experimental data"

**(i)** Genetic-programming symbolic regression over time-series from physical rigs (oscillator, pendulum, double pendulum, air track). Fitness asks whether a candidate f(x, y, ...) predicts the ratios of derivatives between pairs of variables. The commercial descendant was Eureqa.

**(ii) VERIFIED**, copy of Science 324:81 at https://faculty.washington.edu/morgansn/pmwiki/uploads/Site/schmidt-science2009.pdf

- Compute: "In a 32-core implementation, the time required ranged from a few minutes for the harmonic oscillator to 30 hours for the double pendulum."
- Bootstrapping from simpler systems: "from 30 to 40 hours of computation to 7 to 8 hours".
- Noise cost: simulated noiseless data "took ~1/10th of the computational effort to analyze".
- Scaling: time "depends exponentially on the complexity of the law expression itself and roughly quadratically on the system dimensionality".
- Building blocks: "algebraic operators {+, -, ÷, ×}, analytical functions (for example, sine and cosine), constants, and state variables".
- Partial-derivative-pair criterion: compare data ∆x/∆y with (df/dy)/(df/dx) from the candidate; purpose is to reject trivial invariants.
- So the headline double-pendulum result cost roughly 960-1280 core-hours (32 x 30-40 h). MY-ARITHMETIC.

**(iii) VERIFIED critique**, Hillar & Sommer, https://arxiv.org/abs/1210.7273

- "The proposed fitness function [4, Equation S8] is flat for general systems."
- The fitness "is either encoding a consequence of Hamilton's equations of motion ... or Newton's 2nd law for a force arising from a potential".
- "a major claim that '[w]ithout any prior knowledge about physics ... the algorithm discovered Hamiltonians, Lagrangians and other laws' appears to be false."
- They also note the comment was submitted to Science and rejected, so it is an unrefereed preprint.
- From the paper itself: the user chooses which variables to supply (positions only, or positions and velocities), and that choice determines which law type appears.

**(iv)** SHIPPED as Eureqa (commercial; FROM-MEMORY that it was later absorbed into DataRobot). The specific invariant-finding fitness is SINGLE-PAPER with a standing published objection.

**(v)** Derivative-ratio fitness plus any expression search. ESTIMATE 200 lines on top of an existing enumerator.

**(vi)** The useful idea is the *non-triviality test*: an invariant must predict how one variable responds to another. With a simulator this is measured by perturbation rather than estimated from noisy time series. The Hillar-Sommer point generalises: check that a "prior-free" fitness is not identically satisfied or secretly domain-specific.

---

## 3. AI Feynman, AI Feynman 2.0, and independent re-evaluation

**(i)** Recursive problem reduction: dimensional analysis, polynomial fit, brute-force string enumeration, then neural-net-assisted tests for symmetry and separability that split the problem into smaller ones. Version 2.0 adds gradient-based detection of general graph modularity and Pareto-optimal output.

**(ii) VERIFIED**, https://arxiv.org/abs/1905.11481

- Brute force: reverse Polish strings by increasing length; "there are s^n strings of length n using an alphabet of s symbols". Three symbol subsets tried in turn.
- Limit of brute force: a 15-symbol RPN string "would require about 2 years for the brute force method"; another "about 100 times the age of our universe".
- Budget: "a maximum of 2 hours of CPU time per mystery"; later symbol sets add an hour each. In 2.0: "we allow the brute force code to run for only a minute for each iteration".
- Results: abstract, "it discovers all of them, while previous publicly available software cracks only 71"; bonus set "from 15% to 90%". Without dimensional analysis "it now solves 93%". On a third-party set, "66.7% of the equations while Eureqa discovered 48.9%".
- Data: most equations found by polyfit/brute force "using only 10 data points"; NN-dependent ones need "between 10² and 10⁶".
- The exact tests (Algorithms 1 and 2 and Sec. II.F):
  - Translational symmetry: f(x1, x2, ...) = f(x1 + a, x2 + a, ...) with a = 1, threshold 7x NN validation error. Then replace the pair by x2 - x1. Same test for sum, product, ratio.
  - Multiplicative separability: ∆sep = f(x1,x2) - f(x1,c2)·f(c1,x2)/f(c1,c2), c_i = column means, threshold 10x NN error.
  - Additive separability: f(x) = f(x1-part) + f(x2-part) - f(all means).
  - "Setting variables equal": solve with two inputs tied, divide out.
- AI Feynman 2.0, https://arxiv.org/abs/2006.10782 : "solves 73 of 100 baseline problems ... with r = -1" (10% noise) and is "typically 1-3 orders of magnitude more robust".

**(iii) Failure evidence. VERIFIED.**

- SRBench (La Cava et al. 2021), https://arxiv.org/abs/2107.14351 : 130 ground-truth problems, 14 SR methods, budget "1M evaluations or 8 hours" on one core, noise 0/0.001/0.01/0.1.
  - "AIFeynman identifies exact solutions 53% of the time, nearly twice as often as the next closest method (GP-GOMEA, 27%)."
  - "at noise levels above 0.01, four other methods recover exact solutions more often: DSR, gplearn, AFP_FE, and AFP."
  - "AIFeynman may be brittle in application to real-world and/or noisy data".
  - Operon, best on black-box data, "struggles to recover solutions to these problems".
  - So the authors' own 100% became 53% under an independent protocol with no units supplied and a fixed budget. Per-method percentages other than 53 and 27 are in a figure only; I could not extract them.
- Later secondary figure: DGSR paper, https://arxiv.org/abs/2401.00282 , cites "AI Feynman at 52.65%" as the best SRBench baseline.
- ERBench (Kahlmeyer et al., June 2026), https://arxiv.org/abs/2606.09276 , Table 3: exact recovery PySR 0.29 ± 0.04, DSR 0.0, E2E 0.0, Operon 0.0, gplearn 0.05. "PySR excels on equations with low complexity (1-3 operators) ... dropping to near zero" as operators increase. Different benchmark from SRBench; do not merge the numbers.
- Same paper, Table 1: enumerative UDFS recovers 1.0 on 40 Feynman equations at every sample size; PySR 0.965-1.0.
- The paper's own failures: NN missed separability because of "large dynamic range induced by the fifth power".

**(iv)** PROVEN-RESEARCH (open source, independently benchmarked). Brittle under noise by independent measurement.

**(v)** With an oracle the NN disappears. The symmetry/separability tests plus recursion are ESTIMATE 100-200 lines; the RPN brute force another 100-150.

**(vi)** See the transfer list at the top. Verbatim: translational, scaling, product, sum symmetry; additive and multiplicative separability; set-variables-equal. With exact arithmetic the thresholds become equality on a handful of random points. Approximate only: 2.0's gradient tests. Not applicable: dimensional analysis. Caveat: these tests detect structure over a field (shifts, ratios); for program laws the analogous tests are invariance under argument permutation, argument tying, or independence from an argument, which the paper does not cover.

---

## 4. PySR / SymbolicRegression.jl and Exhaustive Symbolic Regression

### PySR (Cranmer 2023)

**(i)** Multi-population ("island") evolutionary search over expression trees with tournament selection, age-regularised replacement, simulated annealing on mutation acceptance, BFGS constant optimisation, and a complexity-frequency penalty. Julia back end, Python front end.

**(ii) VERIFIED**, https://arxiv.org/abs/2305.01582

- Evaluation is the bottleneck: "the expression evaluation code, which remains the bottleneck in PySR"; operators "fused together into single compiled operators ... up to a depth of two operators".
- Benchmark budget: "8 cores ... search for up to 1 hour" on EmpiricalBench (9 equations, 5 trials each).
- Authors' caveat: "genetic algorithms are very inefficient" in number of evaluations; and "we are the authors of PySR, we are therefore more likely to be running in a stable environment".
- Evaluation speed is not given in the paper. VERIFIED from the DynamicExpressions.jl README, https://github.com/SymbolicML/DynamicExpressions.jl : x1*cos(x2-3.2) over 100 rows takes 607 ns interpreted, 629 ns hard-coded, 526 ns hand-SIMD, and 117,000 ns via naive `eval`. MY-ARITHMETIC: about 1.6 M evaluations/s of a 6-node tree on 100 rows on one core, about 1 ns per node-row.

**(iii)** ERBench 2026 (above): 29% exact recovery, near zero beyond a few operators. ESR paper: PySR "is able to obtain the true Pareto front up to and including complexity 6, but achieves little improvement beyond that", with "practically identical results if we run PySR for 5 or 10 hours". Stochastic: no guarantee of coverage.

**(iv)** SHIPPED (open source, maintained, widely used).

**(v)** Not a small system. The transferable part is the evaluator design: enum-tagged tree, columnar buffers, fused kernels. ESTIMATE 300-500 lines for a comparable interpreter.

**(vi)** Evaluator design transfers; the evolutionary search is orthogonal to an enumerative kernel. The 607 ns vs 117,000 ns comparison is direct evidence against compiling each candidate.

### Exhaustive Symbolic Regression (Bartlett, Desmond, Ferreira)

**(i)** Generate every expression tree up to a complexity bound from a fixed operator set, remove duplicates symbolically, fit parameters of each unique function, rank by minimum description length.

**(ii) VERIFIED**, https://arxiv.org/abs/2211.11461

- Operator set: "{x, a, inv, +, -, ×, ÷, pow}" (8 symbols, one variable, a = parameter). Maximum complexity 10.
- Counts: naive n^k "approximately 168 million"; "only 5.2 million of these are valid trees, and 134,234 of these are unique"; parameters optimised for 119,861.
- Compute: generation and dedup "took 46 minutes at complexity 10 when run with 196 cores"; a full run "~150 CPU hours", "33 CPU hours" with precomputed functions.
- Scaling: "the time required at complexity c scales approximately as (1.5k)^c if one uses k basis functions".
- Limits: "it cannot reach complexities ≳10 for reasonable operator basis sets. Hence, we only consider univariate applications"; "SymPy fails to find duplicates in many situations".
- Follow-up, priors: https://arxiv.org/abs/2304.06333 . A Katz back-off n-gram language model over operator sequences, trained on "a compilation of 161 scientific equations" (100 Feynman + 20 bonus + 41 others), used as a prior on function structure. Code name `katz`.
- Follow-up, review (Desmond, July 2025): https://arxiv.org/abs/2507.13033 . "A typical limit is complexity 10, for which a full ESR run takes ~200 CPU-hours (the scaling with complexity is exponential, so even greatly enhanced computational resources could not extend the maximum complexity by ≳ 1)". Planned ESR 2.0 (Julia rewrite, better simplification, multiple variables): "This will raise the complexity cap from 10 to ~13." Planned, not reported as done.

**(iii)** Univariate only; complexity ≤ 10; imperfect dedup; exhaustive only relative to a hand-chosen operator set.

**(iv)** SINGLE-PAPER in the sense of one group (several papers, public code). UDFS (Kahlmeyer et al. 2024) is an independent enumerative system; I verified only its ERBench Table 1 numbers.

**(v)** Tree enumeration by node count plus canonicalisation. ESTIMATE 300-600 lines without the fitting stage. With a deterministic oracle and no free constants, fingerprinting by value vector replaces SymPy.

**(vi)** Strongest transfer in section A: exhaustive enumeration with a guarantee, description-length ranking, and a language-model prior learned from a corpus of known laws without any neural network (n-gram back-off). The measured counts give real branching factors (item 8).

---

## 5. Theory-plus-data systems, conservation-law discovery, Ramanujan Machine

### AI Descartes (Cornelio et al.)

**VERIFIED**, https://arxiv.org/abs/2109.01634

- Method: MINLP-based symbolic regression proposes formulas; KeYmaera X tries to derive each from background axioms or reports a reasoning-based distance.
- Scale: three case studies (Kepler's third law, relativistic time dilation, Langmuir adsorption). Operators: subsets of {+, -, ×, ÷, (one symbol lost in text extraction, presumably √), log, exp}. Langmuir SR run: "20 minutes on 45 cores".
- Failure, authors' words: for time dilation "we did not recover this formula from data".
- Assumes the background theory is "complete ... and consistent".
- Maturity: SINGLE-PAPER (one group). Transfer: weak. It needs axioms; the simulator already is the ground truth.

### AI Hilbert (Cory-Wright et al.)

**VERIFIED**, https://arxiv.org/abs/2308.09474

- Restricts laws and axioms to polynomial equalities/inequalities and searches for Positivstellensatz certificates by sum-of-squares / semidefinite and mixed-integer optimisation. Claims polynomial time "when the degree of the polynomial certificates we search over is bounded".
- Demonstrated on Kepler's third law, Hagen-Poiseuille, radiated gravitational wave power, time dilation.
- Maturity: SINGLE-PAPER. Transfer: the idea that a polynomial law is a linear-algebra object once the monomial basis is fixed. Needs an SDP solver, which is outside a small Lisp kernel.

### Neural conservation-law discovery

- AI Poincaré, https://arxiv.org/abs/2011.04698 : trajectories only, dynamics unknown; neural manifold-dimension estimate. VERIFIED abstract-level.
- AI Poincaré 2.0, https://arxiv.org/abs/2203.12610 : from known differential equations; conserved quantities "parametrized as neural networks", independence test described as "a nonlinear generalization of singular value decomposition". VERIFIED.
- Noether Networks, https://arxiv.org/abs/2112.03321 : meta-learned conservation loss inside a neural predictor. VERIFIED abstract-level.
- ConservNet, https://arxiv.org/abs/2102.04008 : "a neural network trained with a novel ... noise-variance loss". VERIFIED abstract-level.
- All require training; all excluded by the owner's constraints. Maturity: each SINGLE-PAPER.

### The exact, non-neural version: null space of a candidate library

- **SID** (Liu, Sturm, Bharadwaj, Silva, Tegmark 2023), https://arxiv.org/abs/2305.19525 . VERIFIED.
  - Setting: "differential equations and basis functions are both known".
  - Method: H(x) = Σ θ_k b_k(x); require ∇H·f = 0 at sample points; this "is a linear equation of θ"; "we apply singular value decomposition"; the number of vanishing singular values is the number of conserved quantities. "The linear structure obviously gives completeness (in the space spanned by basis functions)".
  - Result: "SID discovers 14 and 3 conserved quantities, respectively, where only 12 and 2 were previously known to domain experts."
  - Example scale: polynomials to 3rd order, K = 19 basis terms, 4 conserved quantities.
  - Limitation, authors' words: "humans need to input basis functions".
- **Kaiser, Kutz, Brunton 2018**, https://arxiv.org/abs/1811.00961 . VERIFIED: conserved quantities are Koopman eigenfunctions with zero eigenvalue, identified from data with a SINDy-style "dictionary of candidate functions"; demonstrated on the 3-D rigid body (energy and angular momentum).
- **Sharma, Gupta, Hariharan, Aiken, Liang, Nori, ESOP 2013**, https://theory.stanford.edu/~aiken/publications/papers/esop13.pdf . VERIFIED. This is the program-side version.
  - Data matrix A: one row per logged program state, one column per monomial up to degree d. Candidate invariants: "B := Basis(NullSpace(A))". Then an SMT check; counterexamples add rows. "Iterating between the two phases leads to a sound algorithm."
  - "our first guess is an actual invariant" on most benchmarks.
- Maturity of the null-space idea: PROVEN-RESEARCH (three independent groups, two domains).
- Smallest sound version: monomial generator, exact rational Gaussian elimination, re-test on fresh samples. ESTIMATE 150-250 lines. Cost grows as C(n+d, d) columns.
- Transfer: verbatim. Rows are simulator states (or input/output tuples), columns are candidate terms from the kernel's own enumeration, null-space vectors are linear laws among terms. Over rationals it is exact, so no SVD threshold. It finds only laws *linear in the chosen terms*; the term library is the whole inductive bias.

### Ramanujan Machine

**VERIFIED**, https://arxiv.org/abs/1907.00205

- MITM-RF: enumerate the continued-fraction side to "low precision (10 digits)", store in a hash table, enumerate the other side, re-evaluate matches at higher precision. Complexity "O(M + N)" time, "O(N)" space, versus "O(MN)" naive.
- False-positive argument: for "an enumeration space of 10⁹ and result accuracy of more than 50 digits", chance match "smaller than 10⁻⁴⁰"; conjectures tested "for up to 2000 digits".
- Second algorithm: gradient descent ("Descent&Repel"), described as proof of concept.
- Authors: "the MITM-RF method is not trivially scalable".
- Compute (cores, hours): not stated in the passages I read. NOT VERIFIED.
- FROM-MEMORY: published in Nature 2021; several "new" formulas were later shown to follow from known continued-fraction results.
- Maturity: PROVEN-RESEARCH for the MITM/hash technique (old idea), SINGLE-PAPER for the system.
- Transfer: two-sided enumeration with a hash join on value fingerprints, then escalation of test strength on hits. For a deterministic simulator "higher precision" means "more test inputs".

---

# (B) Brute force with fast evaluation

## 6. Superoptimisers, optimal Boolean chains, sorting networks

### Massalin 1987

**VERIFIED**, https://www.cse.iitm.ac.in/~krishna/courses/2022/odd-cs6013/MassalinCANews87.pdf

- Exhaustive enumeration of instruction sequences by increasing length from a chosen opcode subset.
- Boolean test (exact, minterm comparison): "tested about 40 programs per second, and this allowed programs of up to 3 instructions".
- Probabilistic test (run on test vectors): "superoptimizer can test 50000 programs per second and the exhaustive search approach becomes practical".
- Test vectors are "chosen (manually) to maximize the probability that a random program will fail on the first or second test".
- Reach: "programs 12 instructions long in several hours running time on a 16MHz 68020"; abstract says "about 13 machine instructions".
- Soundness: "superoptimizer runs without the boolean check, and the author has yet to find an incorrect program", i.e. unverified output, inspected by hand.
- Limits: "the exhaustive search still grows exponentially"; pointers unsolved; register-register operations only.
- Size: "about 300 lines of 68020 assembly code".
- STOKE's later description: Massalin had "to restrict the set of enumerable opcodes to between 10 and 15".
- Maturity: PROVEN-RESEARCH (re-implemented many times). Smallest version: the 300 lines above.

### GNU superoptimizer (Granlund & Kenner, PLDI 1992)

- VERIFIED only through Souper's related work: "the GNU superoptimizer was an unsound, enumeration-based tool that was used to improve GCC's code generation by deriving ways to turn code with control flow into straight-line code."
- Throughput and maximum length: **FROM-MEMORY / NOT VERIFIED** (paper URL returned 404).
- Maturity: SHIPPED in effect (its output went into GCC machine descriptions).

### STOKE (Schkufza, Sharma, Aiken, ASPLOS 2013)

**VERIFIED**, https://theory.stanford.edu/~aiken/publications/papers/asplos13.pdf

- MCMC over x86-64 loop-free code; cost = test-case distance plus performance term; symbolic validator only on promising candidates.
- Validator throughput: "the number is well below 100" per second.
- Test-case emulator: "just under 500,000" test-case evaluations per second.
- With early termination, proposals "at peak exceeds 50,000" per second.
- Budget: "40 dual-core 1.8 GHz AMD Opterons", "30 minutes" each for synthesis and optimisation.
- Failures: "STOKE is unable to synthesize a rewrite for three of the Hacker's Delight Benchmarks"; loop-free code only; 64-bit multiply/divide treated as uninterpreted.
- Maturity: PROVEN-RESEARCH (open source; several follow-up papers by the group; used as a baseline by others).
- Point for this review: the test-case fast path is what makes the method exist at all. At under 100 validations/s, MCMC "would almost certainly drive that number well below a useful threshold".

### Souper (Sasnauskas et al. 2017)

**VERIFIED**, https://arxiv.org/abs/1711.04422

- Synthesises LLVM-IR peephole right-hand sides with SMT-based CEGIS; 51 instructions in its IR.
- Result: Clang binary "about 3 MB (4.4%) smaller", "though it is also about 2% slower"; compilation "5× to 25× slower" on first run.
- Synthesis reach: Hacker's Delight "P1-P17 and P19 out of P1-P25"; "Our CEGIS implementation does not scale as well as Gulwani et al.'s".
- Maturity: SHIPPED as an offline tool (open source); not a default compiler pass.

### Denali (Joshi, Nelson, Randall, PLDI 2002)

- VERIFIED only through STOKE's description: Denali and equality saturation "gain scalability by only considering programs that are known to be equal to the input program", but "rely heavily on expert knowledge" in the form of axioms.
- E-graph plus SAT mechanics and results: **FROM-MEMORY / NOT VERIFIED**.
- Maturity: SINGLE-PAPER as a system; the E-graph idea itself is PROVEN-RESEARCH via later equality-saturation work (FROM-MEMORY).

### Bansal & Aiken

VERIFIED via STOKE: exhaustive enumeration with canonicalisation up to register renaming scales to "input code sequences of at most length 6 and produce code sequences of at most length 3".

### Optimal Boolean chains (Knuth, TAOCP 4A §7.1.2)

- VERIFIED via secondary sources only: https://msoeken.github.io/papers/2017_ismvl.pdf : "Knuth has computed the combinational complexity of all 4- and 5-input Boolean functions"; NPN reduction to "222 and 616,126 functions instead of 65,536 and 4,294,967,296"; hardest cases are "11-step chains for their 6 corresponding NPN classes and the 12-step chain for its single" class.
- https://cp4space.hatsya.com/2019/05/28/five-input-boolean-circuits/ : same counts; canonisation by iterating over 3840 transformations.
- Knuth's own text and compute time: NOT VERIFIED.
- Technique: each function is a 32-bit truth table; gates are single word operations; search is over semantics with symmetry canonicalisation.
- Maturity: PROVEN-RESEARCH (reproduced by exact-synthesis groups).
- Transfer: for any finite input domain, a candidate's whole behaviour is one bit-vector; combining two candidates is one machine operation; equality of behaviour is integer equality.

### Sorting networks and sorting kernels

- Codish et al. 2014, https://arxiv.org/abs/1405.5754 . VERIFIED: 25 comparators optimal for 9 inputs. Symmetry reduction "from approx. 2.2 × 10³⁷ to approx. 3.3 × 10²¹", then SAT "in less than 12 hours"; cluster of "144 Intel E8400 cores"; pure generate-and-prune took "just over one week" plus "five additional days". Without parallelism "approx. 9 years of computation on a single core".
- Harder 2020, https://arxiv.org/abs/2012.04400 . VERIFIED: 35 comparators for 11 channels, 39 for 12, by dynamic programming with a certificate checked by an Isabelle/HOL-verified program. Compute not extracted.
- Ullrich & Hack, CGO 2025 (Distinguished Paper), https://compilers.cs.uni-saarland.de/papers/ullrich_sorting_kernels.pdf . VERIFIED.
  - Enumerative A* over assembly sorting kernels, tested on all n! permutations.
  - Times: "Enum, best 97 ms / 2443 ms / 11 min" for n = 3/4/5 versus "AlphaDev-RL 6 min / 30 min / ≈1050 min".
  - Ablation for n = 3: plain Dijkstra single core 56 s; parallel 17 s; GPU 46 s; A* with dedup and no heuristic 219 s; plus permutation-count heuristic 1713 ms; all heuristics plus cut 97 ms.
  - States enumerated: "7·10³, 7·10⁴, and 6·10⁶" for n = 3, 4, 5 out of program spaces of about 10^19.9, 10^40, 10^71.2.
  - Exhaustive lower bound: no correct kernel of length 19 for n = 4.
  - "classical synthesis approaches fail to scale beyond arrays of length 3" (SMT, CP, ILP, planners, Stoke).
  - Maturity: SINGLE-PAPER, peer-reviewed.

---

## 7. GPU / bit-parallel exhaustive enumerative synthesis

### Paresy (Valizadeh & Berger, PLDI 2023)

**VERIFIED**, https://arxiv.org/abs/2305.18575

- Task: minimal-cost regular expression consistent with positive and negative strings.
- Representation trick: every candidate language is a bit-vector ("characteristic sequence") over the *infix closure* of the examples, so concatenation and star can be computed from sub-results. All bit-vectors live in one write-once contiguous matrix, the "language cache", ordered by cost. Only semantically unique bit-vectors are cached.
- Throughput (Table 1, 24 hardest cases): average 19,127,861,447 REs checked in 4.12 s on an A100 versus 4465 s on CPU; "Speed-up 1077x". MY-ARITHMETIC: about 4.6 × 10⁹ REs/s on GPU, about 4.3 × 10⁶ REs/s on CPU.
- Against prior tool: "AlphaRegex is always slower than the CPU version of Paresy, in an extreme case by more than three orders of magnitude". So the representation alone, on CPU, is worth up to 1000x.
- Limit: "the number of regular languages increases exponentially with increasing cost, makes available memory the scalability limit"; solves tasks in seconds "provided they fit in memory". One benchmark ran out of memory where AlphaRegex succeeded.
- Problem sizes are small: 8-14 positive and 7-14 negative strings, binary alphabet in the main comparison.
- Measured growth (appendix table, one specification): REs checked versus cost of the minimal solution: cost 8 → 2,073; 12 → 116,912; 14 → 794,598; 18 → 18,698,767; 22 → 319,649,322; 28 → 26,774,099,142.
- Maturity: SINGLE-PAPER (one group; open source).

### LTL learning on GPUs (Valizadeh, Fijalkow, Berger, CAV 2024)

**VERIFIED**, https://arxiv.org/abs/2402.12373

- Same enumerate-semantics design for LTL over finite traces. New pieces: "branch-free LTL semantics that has O(log n) time complexity" by shift-and-or doubling ("exponential propagation"); divide-and-conquer on the specification; "relaxed uniqueness checks" (hash the characteristic matrix to 126 bits, allow false positives).
- Claims: "handles traces at least 2048 times more numerous, and on average at least 46 times faster than existing state-of-the-art learners".
- Price: minimality is given up. "While uniqueness improves scalability, it just delays the inevitable: there are simply too many unique CMs."
- Authors on the 46x figure: "the existing benchmarks are too easy, and the timing measurements are dominated by GPU startup latency".
- Unexplained "phase transition" when hash bits are masked: from minimal formulas to out-of-memory "with almost no intermediate stages".
- Enumerator instance limited to 64 traces of length ≤ 64.
- Maturity: SINGLE-PAPER (same group).

### Follow-up: "GPU accelerated program synthesis: Enumerate semantics, not syntax!" (Berger, Fijalkow, Valizadeh, arXiv April 2025)

**VERIFIED**, https://arxiv.org/abs/2504.18943 . A 10-page position/overview article, no new benchmark.

- Scale-by-brute-force claim: "we embrace the exponential nature of enumeration, and exploit its simplicity in order to make all cases extremely fast on GPUs"; "bottom-up program synthesis is embarrassingly parallel".
- Their own hedge: "Yet another possibility is that our success with GPU acceleration of program synthesis was a lucky fluke! After all, our synthesis is at the least expressive part of the Chomsky-Schützenberger hierarchy".
- On SAT: "the community consensus seems to be that 'GPUs are hopeless'".
- I found no 2025-2026 paper extending this to SyGuS or general program synthesis. Search budget ran out before a second query, so absence is weakly established.

### Transfer for a single-threaded CPU kernel

The GPU is not the transferable part. What transfers: (1) a behaviour fingerprint that is closed under the language's constructors (infix closure for concatenation; suffix-contiguity for temporal operators), so a parent's fingerprint is computed from children's fingerprints in a few word operations; (2) a write-once cost-ordered cache; (3) uniqueness as the only pruning rule. Paresy's CPU version already beat the prior top-down tool by up to three orders of magnitude. The hard requirement is that such a closed fingerprint domain exists; for general programs with unbounded data it may not.

---

## 8. Does a 100-1000x faster evaluator change what is findable?

### Explicit statements of the log_b argument. VERIFIED.

- Desmond 2025 (ESR review): "the scaling with complexity is exponential, so even greatly enhanced computational resources could not extend the maximum complexity by ≳ 1".
- ESR 2022: "the time required at complexity c scales approximately as (1.5k)^c".
- AI Feynman: "there are s^n strings of length n using an alphabet of s symbols".
- Massalin: "Even with the probabilistic test, the exhaustive search still grows exponentially with the number of instructions".
- Paresy: memory, not time, becomes the limit because unique languages grow exponentially with cost.
- Schmidt & Lipson: time "depends exponentially on the complexity of the law expression".

### Measured effective branching factors. MY-ARITHMETIC on verified counts.

| Source | Quantity | b per unit | Extra units from 1000x |
|---|---|---|---|
| ESR, run time, k = 8 operators | (1.5k)^c | 12 | 2.8 |
| ESR, naive strings | 8^k | 8 | 3.3 |
| ESR, valid trees, 5.2 M up to c = 10 | geometric fit | about 4.6 | 4.5 |
| ESR, unique functions, 134,234 up to c = 10 | geometric fit | about 3.1 | 6.1 |
| Paresy, REs checked (built from deduplicated sub-languages), cost 8 → 28 | (26.77e9 / 2073)^(1/20) | about 2.27 | 8.4 |
| Paresy, cost 22 → 28 | (83.8)^(1/6) | about 2.09 | 9.4 |

- Geometric fits assume N(c) ∝ b^c and cumulative total = N(10)·b/(b-1). They are rough.
- Reading: deduplication roughly halves log b. At ESR's depth that was worth more than a 1000x evaluator: the paper's own figure is 168 M naive candidates reduced to 134,234 unique, "a factor of 1250 smaller".
- ESR's planned move from complexity 10 to about 13 comes from a rewrite of simplification and dedup plus a faster language, not from more hardware.

### Counter-evidence: cases where the constant factor changed the outcome qualitatively. VERIFIED.

- Massalin: 40 → 50,000 programs/s (1250x) coincided with reach going from 3 to 12 instructions. Confounded: tree pruning was added, the opcode table is 10-15 entries, and "reasonable time" became "several hours". If attributed to speed alone it implies b ≈ 2.2 (MY-ARITHMETIC: 1250^(1/9)).
- STOKE: validator below 100/s versus about 500,000 test-case evaluations/s. MCMC needs millions of proposals in 30 minutes; at validator speed the method does not function. This is a threshold effect, not extra depth.
- Paresy: 1000x on GPU turned roughly 1-hour CPU problems into 4-second ones; by the table above that is about 8-9 cost units at the frontier, on a base of about 19-28. A real but bounded gain.
- AutoML-Zero, https://arxiv.org/abs/2003.03384 : "even a trivial task can be as rare as 1 in 10¹²"; search runs at "10,000 models/second/cpu core"; functional-equivalence caching "results in a 4x speedup". MY-ARITHMETIC: one random hit at that density needs 10⁸ core-seconds, about 3 core-years. So raw speed alone was not enough even there; evolution plus 10k cores was.

### Evidence that structure beats throughput. VERIFIED.

- Sorting kernels, n = 3 (Ullrich & Hack): single core 56 s → parallel 17 s (3.3x) → GPU 46 s (1.2x) → heuristics and cuts 97 ms (about 580x). For n = 5, 11 minutes on a laptop versus about 1050 minutes for the RL system on TPUs.
- Codish et al.: symmetry reduction removed a factor of about 10¹⁶ (2.2 × 10³⁷ → 3.3 × 10²¹).
- AI Feynman: brute force alone would take "longer than the age of our universe"; decomposition makes pieces small enough.
- ESR: 168 M naive → 134,234 unique, "a factor of 1250 smaller".
- PySR: evaluator is fast, yet exact recovery falls to near zero beyond a few operators (ERBench 2026).

### Bottom line for a Lisp kernel

- A 1000x evaluator buys roughly 3-4.5 AST nodes without semantic dedup and roughly 6-9 with it. Both figures come from small, low-arity grammars (8 symbols; regex constructors). A richer operator set lowers them.
- Memory for the dedup table becomes the binding limit before time does (Paresy).
- Threshold effects are real: methods that need 10⁶-10¹⁰ candidate tests are simply unavailable at 10²/s. So speed determines *which algorithms are usable*, more than how deep any one of them reaches.
- No source in this slice measures b for a typed functional program grammar with recursion. That number is the one the owner needs and it is not in the literature I read.

---

## 9. arXiv:2611.17309, "Classical Energies Learn to Reason 1,000× Faster than Looped Models"

Hoover, Blayney, Whittington (Prefrontal, London). v1 12 Nov 2026, v2 19 Nov 2026. Read in full from https://arxiv.org/html/2611.17309v2 . Unreviewed preprint, twelve days old at time of writing.

**Summary (about 250 words).**

CRAM ("Compact Reasoning Associative Memory") is a trainable version of the Hopfield-Tank energy. Each answer cell holds a categorical belief; the energy is a sum of pairwise cost matrices K_ij between cells' candidate values, per-cell biases, and an entropy term. Training fits the costs from solved puzzles with a pseudolikelihood objective plus L1, by SGD from zero, with no backpropagation through a solver. Inference clamps the clues, starts several independent chains from random fills, and does noisy single-cell descent ("focused Gibbs search") until a board's energy falls below a threshold fitted from training solutions.

Reported numbers: 99.996% of Sudoku-Extreme (412,786 test puzzles) and 100% of Maze-Unique (1,000 mazes), after 42 ms and 132 ms of training on one H200 GPU from 1,000 training rows; "at least 1,000×" faster training than seven looped baselines (HRM, TRM, GRAM, EqR, FRM, TRMP, EBR; 1.2-23.2 h) and 282× to 128,000× fewer inference FLOPs. Nonzero parameters: 7.7K (Sudoku), 18 (Maze). It reaches 98% from 30 unique puzzles versus 700 for EBR. N-Queens and graph colouring are also covered.

Why it works, per the paper: these puzzles "belong to a category of logic puzzles that CRAM's pairwise energy can represent exactly". The learned weights are the rules: "positive equal-digit costs on exactly the 810 cell pairs that share a row, column or box"; the 18 maze costs implement dead-end filling. A hand-set energy with one unique weight (Sudoku) or three (Maze) solves every test puzzle, with "up to 19×" fewer FLOPs than the learned one.

Caution: "A high score on these benchmarks therefore only shows that a model has learned a few pairwise rules between answer cells". It "does not indicate that a model can scale to harder tasks such as ARC-AGI-1", where answers depend on quantities that must be computed.

**Details worth knowing.**

- Table 2 prints 100.00 ± 0.00 for Sudoku; the abstract's 99.996% is the unrounded figure.
- Table 1 lists the priors supplied: digit-relabelling augmentation for Sudoku; locality and translation invariance for Maze (a 3×3 shared window). "In no task is the energy told the rules of a puzzle", but these priors are substantial.
- Timing asymmetry, disclosed: CRAM times are warm (median of seven fits after a first), baseline times are one cold fit.
- "CRAM never returns a wrong answer, it only 'misses'": the stopping test had no false positives, while baselines' halting rules stop on wrong boards on 0.05-3.54% of puzzles.
- Full BPTT on the same energy "fails to solve more than 48.8% after 5 h". The objective, not the model, carries the speedup.
- Maze-Hard needs a latent extension (Appendix F); learning latents in general is called "an important open research direction".
- Comparison excludes methods that "pass learned costs to an external exact solver".

**What transfers to symbolic program/law search. Plainly: little, and none of it is the learning.**

- The paper's own explanation is that the hypothesis space is tiny (pairwise costs between answer cells) and the constraints are local. Program and law search does not have that shape; the paper says so for ARC.
- Non-learned analogue, cited by the paper as prior art: "constraint acquisition". Enumerate candidate pairwise constraints, keep those never violated by any solved example (a version-space filter), then solve by constraint propagation or min-conflicts local search. That needs no gradient and no GPU. The paper's hand-set energies are exactly this endpoint and they outperform the learned ones. System names for constraint acquisition are FROM-MEMORY and omitted.
- Transferable habits rather than methods: (1) before crediting a search method, test whether a hand-written or exhaustively enumerated minimal hypothesis already solves the benchmark; (2) use a violation count ("energy") with a threshold calibrated on known-good examples as a stop test that cannot accept a wrong answer; (3) local, per-constraint scoring is far cheaper than scoring through a whole solver trajectory.
- ESTIMATE: fitting 7.7K pairwise parameters by pseudolikelihood would run on a CPU in seconds. The paper reports only H200 timings, so this is my inference, and it is still parameter fitting, which the owner's constraints exclude.
- Maturity: SINGLE-PAPER, preprint. The underlying Hopfield-Tank energy and pairwise MRF learning are old and PROVEN-RESEARCH.

---

## Could not verify

- Langley & Zytkow 1989 survey (DTIC ADA201850): HTTP 403. FAHRENHEIT's 1987 paper: not found.
- ABACUS mechanism and results; COPER entirely; IDS mechanism beyond Langley's 2024 one-paragraph summary.
- BACON.1-BACON.4 version-by-version differences (only BACON.5's paper was read).
- "Scientific Discovery" (1987 book): not online; nothing here is quoted from it.
- GNU superopt throughput and sequence lengths; Denali's mechanics and results.
- Knuth's own text for the 5-variable chain computation, and its run time (two secondary sources agree on 616,126 classes and a maximum of 12 steps).
- Per-method SRBench exact-solution percentages other than AIFeynman 53% and GP-GOMEA 27% (figure only). PySR was not in SRBench 2021; SRBench 2.0 (arXiv 2505.03977) results for exact recovery were not extracted.
- PySR whole-search throughput (only the evaluator micro-benchmark from the README).
- Ramanujan Machine compute budget; later critique of novelty.
- Harder's compute for the 11/12-channel bounds.
- Eureqa's corporate history.
- Whether any 2025-2026 work extends bit-parallel GPU enumeration to SyGuS or general program synthesis (one search only).
- UDFS (Kahlmeyer et al., IJCAI 2024) primary paper: only its numbers as reported in ERBench Table 1.
