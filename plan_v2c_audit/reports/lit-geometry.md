# lit-geometry — calibrated literature review for the "geometry half" of a topology–geometry kernel

Researcher: `lit-geometry`. Date: 2026-11-24. Scope: topics 1–11 of the brief.
Target system: single-threaded CPU, Common Lisp, no DL framework, library of 10^1–10^3 entries,
truth in an exact engine, geometry only ranks / proposes / prices.

## 0. How to read this

**Verification legend.** Unmarked factual claims were checked online in this session (source URL given).
`[FROM-MEMORY]` = not verified online today; treat as a pointer, not a citation.
`[ESTIMATE]` = my own back-of-envelope number (cost, LOC), not from a paper.

**Maturity scale.** SHIPPED (in routine production/tool use) / PROVEN-RESEARCH (replicated by several
groups, known failure modes) / SINGLE-PAPER (one group or one system) / SPECULATIVE (framework or
aspiration; no working small-scale algorithm for the job in question).

**The three jobs.** R = rank/propose (heuristics, retrieval). P = price residuals (bits). L = compose language.

### Headline findings

1. **What demonstrably works at small scale without gradient descent** is almost entirely *derived*
   geometry: behavioural fingerprints with observational-equivalence pruning, cost-ordered enumeration,
   count-based priors (PCFG/bigram reweighting, naive Bayes, kNN, TF-IDF), random-walk proximity
   (personalised PageRank, successor representation), Weisfeiler–Leman hashes, closed-form linear algebra
   (Procrustes, ridge, small eigenproblems). Each has measured gains or shipped use.
2. **What needs gradient descent and a lot of data**: every method that *learns coordinates* — Poincaré,
   box, order and mixed-curvature embeddings; TransE/RotatE; sheaf neural networks; TEM; DisCoCat tensors;
   recognition networks; and all of the "flat is fine" transformer evidence.
3. **What is closer to hype than to engineering for this project**: learned sheaf Laplacians (a March 2026
   paper finds identity maps do about as well on the standard benchmarks), hyperbolic embeddings as a
   general upgrade (Euclidean matches them at ≥50 dimensions on the original benchmark), VSA as a
   compositional computer (noise compounds with depth; exact systems already do the job exactly),
   gauge/fibre-bundle networks, TDA, conceptual spaces as an algorithm.
4. **The "computation in superposition" claim in the previous plan is correct as a paraphrase, with one
   important sharpening**: the quadratic figure is for *neurons*; the *parameter* count needed is at least
   linear in the number of features computed, i.e. there is no compression of computation at all in
   parameters (§3).
5. **Nested vs flat is not a representability question.** Trees embed exactly in squared-Euclidean space
   with about one dimension per edge; LLMs encode hierarchy as orthogonal subspaces of a flat space; a
   library of ≤10^3 entries can afford one explicit dimension per feature. Hyperbolic geometry only buys
   compression at very low dimension, and pays in numeric precision (§1, §6, closing (b)).
6. **Residual pricing has one consistent answer**: price in the ambient space, or in a latent space *plus*
   the Jacobian/fibre correction, which is the same thing. Exact bijections transfer code lengths for free;
   quotients cost the fibre index. Adaptive geometry may be used inside a *prequential* code without any
   cheating (§8).
7. **The cited arXiv:2611.17309 is reachable** and is real, but it does not say what the owner's gloss says.
   It is about a tiny *learned pairwise energy* (not brute force) that solves Sudoku/Maze after
   milliseconds of training, and it explicitly warns that those benchmarks are too easy (§11).
8. **Four of the owner's wishes have no convincing precedent** at this scale: autonomous creation of
   coordinate spaces from few samples, geometric (as opposed to exact) collapse of spaces, vectors that
   stay meaningful while being "moved" through space creation/collapse, and words acting as geometric
   modifiers in a non-gradient system (closing (d)).

---

## 1. Geometry that respects hierarchy

**(i) What.** Embeddings whose geometry mirrors a partial order or tree: hyperbolic (Poincaré ball /
Lorentz) embeddings place tree nodes so that distance grows like tree distance; order embeddings and
entailment cones represent `x ≤ y` as cone containment; box embeddings represent it as box containment
with volume read as probability; product ("mixed-curvature") spaces combine spherical, Euclidean and
hyperbolic factors.

**(ii) Best small-scale evidence.**
- Nickel & Kiela 2017 (https://arxiv.org/abs/1705.08039) reported large gains over Euclidean on WordNet
  noun hypernymy at 5–200 dimensions; their best reconstruction MAP is cited as ≈0.87 at 200-d.
- **Reproduction failure of the headline comparison**: Bansal & Benton 2021
  (https://arxiv.org/abs/2109.07488) find Euclidean embeddings represent the same tree "at least as well"
  once given ≥50 dimensions (their reproduced Euclidean 50-d MAP is reported as 88.9, far above the
  original baseline). The hyperbolic advantage survives only at very low dimension.
- **A non-gradient construction exists**: Sala, De Sa, Gu, Ré 2018 (https://arxiv.org/abs/1804.03329)
  generalise Sarkar's 2011 combinatorial tree embedding; no optimisation step; WordNet MAP **0.989 in 2
  dimensions** — but the coordinates need roughly **500 bits of precision**, and the paper proves a
  precision–dimension trade-off for *any* hyperbolic embedding. They also give h-MDS (a closed-form
  hyperbolic MDS) for general metrics.
- Numerical fragility is documented, not anecdotal: Mishne et al., ICML 2023
  (https://proceedings.mlr.press/v202/mishne23a.html) analyse float64 limits of the Poincaré and Lorentz
  models (points cannot be represented beyond a modest radius; `[FROM-MEMORY]` ≈38 for the ball, ≈19 for
  Lorentz). Dhingra et al. 2018 (https://arxiv.org/abs/1806.04313) found no consistent downstream gain
  over Euclidean baselines for text.
- Box embeddings: Vilnis et al. 2018 (https://arxiv.org/abs/1805.06627); the "Gumbel box" fix exists
  because hard boxes have zero gradient when disjoint ("local identifiability",
  https://arxiv.org/abs/2010.04831). Order embeddings (Vendrov 2016), hyperbolic entailment cones (Ganea
  2018), mixed-curvature products (Gu et al. 2019): existence confirmed, details `[FROM-MEMORY]`.

**(iii) Data/compute; gradient?** All learned variants use (Riemannian) SGD over 10^4–10^6 order pairs.
The Sarkar/Sala construction and h-MDS need no gradient, but need the tree (or metric) as input and
arbitrary-precision arithmetic.

**(iv) Failure modes.** NaNs and boundary saturation; advantage disappears at moderate dimension; DAGs
with heavy multiple inheritance are not tree-like and distort; box/cone training has dead-gradient
regions; mixed-curvature needs a signature search. For Common Lisp specifically: rationals and bignums
are native, but arbitrary-precision `exp/log/acosh` are not, so the 500-bit construction is not free.

**(v) Maturity.** Learned hyperbolic/box/order embeddings: PROVEN-RESEARCH (with gradient, with caveats).
Combinatorial construction: PROVEN-RESEARCH but precision-bound. Mixed-curvature: PROVEN-RESEARCH with
small gains.

**(vi) Smallest useful version.** If the hierarchy is already an exact graph, *no embedding is needed*:
tree distance = `depth(u)+depth(v)−2·depth(lca)`; ancestor tests in O(1) via DFS pre/post-order interval
labels (a 1-D "box embedding" that is exact and trained by a traversal) `[FROM-MEMORY, textbook]`.
≈60 LOC, no dependencies `[ESTIMATE]`. Sarkar coordinates: ≈150 LOC plus a bigfloat library.

**(vii) Jobs.** R: yes, but the exact tree metric does the same job with zero risk. P: no. L: no.

**Calibrated take.** Hyperbolic space is a *compression* device for trees when dimension is scarce. With
≤10^3 entries dimension is not scarce and the tree is already in memory. Import nothing here.

---

## 2. Knowledge-graph embeddings (relations as geometric operations)

**(i) What.** Entities are vectors; each relation is an operation: TransE a translation (`h + r ≈ t`),
RotatE a rotation in complex planes, others bilinear forms. This is the cleanest formalisation of
"analogy = a vector in some space".

**(ii) Evidence.**
- Standard benchmarks have 10^4 entities and 10^5 training triples, and the best models reach
  hits@1 ≈ 25% on FB15k-237 (ComplEx 25.7, RotatE 23.8, TuckER 25.9).
- **A symbolic, gradient-free rule learner matches or beats them at the top of the ranking**: AnyBURL
  (https://arxiv.org/abs/2004.04412) samples paths, generalises them to Horn rules, runs on CPU for
  100–1000 s, and gets hits@1 27.3 (FB15k-237), 45.7 (WN18RR, best of all), 49.2 (YAGO3-10, second to
  ComplEx 50.5), with no hyper-parameter tuning.
- Ruffinelli et al., ICLR 2020 (https://iclr.cc/virtual/2020/poster/1952): once training is done
  carefully, differences between model geometries "shrink or reverse"; the oldest model (RESCAL) is
  competitive. The geometry of the relation operator matters less than the training recipe.

**(iii) Data/compute; gradient?** SGD with negative sampling; 10^5+ triples. Structure-only embeddings
degrade on low-degree entities (degree-binned WN18RR results in https://arxiv.org/abs/2206.12617).

**(iv) Failure modes.** TransE cannot fit 1-to-N / N-to-N relations (tails collapse) and pushes symmetric
relations toward `r≈0`; RotatE fixes symmetry/inversion/composition patterns but still struggles with
1-to-N and with transitivity (https://arxiv.org/abs/1902.10197, https://arxiv.org/abs/2110.14450).
Translations and 2-D rotations compose *commutatively*, so order-sensitive relation composition is not
representable `[FROM-MEMORY]`. Word-vector analogies, the popular face of "analogy as offset", are
fragile: Linzen 2016 (https://aclanthology.org/W16-2503/) shows the offset method can succeed merely
because the answer is the nearest neighbour of a query word; Rogers et al. 2017
(https://aclanthology.org/S17-1017/) argue it should not be used as a model of relations.

**(v) Maturity.** SHIPPED at web scale; **not** a small-data technique.

**(vi) Smallest version.** TransE with SGD ≈150 LOC `[ESTIMATE]`, but with 10^2–10^3 entities it has too
few triples per relation to beat rule mining.

**(vii) Jobs.** R: weak here. P: no. L: the "analogy term" is better served by *applying a verified map*
(the kernel's own transformers/functors are exact relation operators) than by a learned offset.

---

## 3. Vector-symbolic architectures, HRR, tensor products, sparse distributed memory

**(i) What.** Fixed-width random high-dimensional vectors with three operations: superposition (bundle),
binding (role⊗filler by XOR / circular convolution / permutation), and similarity; structures are built
recursively and queried by unbinding followed by a nearest-neighbour "clean-up". Tensor-product
representations (Smolensky) bind with the outer product, exactly but with growing dimension.

**(ii) What is actually known (stated precisely).**
- *Atoms*: the number of nearly-orthogonal atomic vectors in D dimensions is exponential in D
  (Johnson–Lindenstrauss).
- *Simultaneous storage*: the number of items reliably recoverable from one bundle is **linear** in D —
  about 0.5 bit per component, universal across VSA families (Frady, Kleyko, Sommer 2018,
  https://arxiv.org/abs/1707.01429). "Exponential" refers to the codebook, not to what one vector holds.
- *Computation in superposition* (Adler & Shavit, https://arxiv.org/abs/2409.15318, v3 Feb 2026):
  for a broad class of problems (permutations, pairwise logical operations), computing m′ features in
  superposition needs **Ω(√(m′ log m′)) neurons and Ω(m′ log m′) parameters**; pairwise AND is achievable
  with O(√m′ · log m′) neurons and O(m′ log² m′) parameters. Hence n neurons compute at most
  **O(n²/log n)** features, while merely *representing* m′ features needs only O(log m′) neurons. The
  abstract's own wording is an "exponential gap" between representing and computing.
  **So the previous plan's sentence is a fair paraphrase** — storage compresses exponentially,
  computation only quadratically — with two caveats: (a) "quadratically" is in neuron count; in
  *parameters* there is essentially no compression (≥ m′ log m′); (b) these are theorems about
  neural networks (with sparse feature activity `[FROM-MEMORY]` for the constructions), not about VSAs.
- Constructive results are weaker than the bound: Hänni, Mendel, Vaintrob, Chan 2024
  (https://arxiv.org/abs/2408.05451) get all pairwise ANDs of m features with Õ(m^{2/3}) neurons in one
  layer, and deep width-d networks emulating circuits of width Õ(d^{1.5}).
- *Nested structure*: the HDC/VSA survey (Kleyko et al., https://arxiv.org/abs/2111.06077) is explicit
  that bound vectors are dissimilar to their inputs, unbinding from a bundle returns a noisy vector so a
  clean-up memory is required at each level, exact recovery is guaranteed only for limited-size
  structures, plain superposition loses grouping (`(a+b)+(c+d) = (a+c)+(b+d)`), tensor products grow as
  D², D³, …, and factoring a k-way binding is a search exponential in k.
- Resonator networks (https://arxiv.org/abs/1906.11684, https://arxiv.org/abs/2007.03748) attack that
  factorisation: empirically the solvable problem size grows quadratically with D, about two orders of
  magnitude better than alternatives, **without convergence guarantees**.

**(iii) Data/compute; gradient?** None needed; codes are random. D ≈ 10^3–10^4.

**(iv) Failure modes.** Noise compounds with nesting depth; clean-up requires an item memory that is
itself an exact table; everything a VSA does approximately, an exact hash table / term graph does exactly.

**(v) Maturity.** Algebra and capacity theory: PROVEN-RESEARCH. Low-power classification: SHIPPED in a
niche. Deep compositional reasoning in superposition: SPECULATIVE.

**(vi) Smallest useful version.** Bipolar vectors, XOR/multiply binding, majority bundling, cosine
clean-up: ≈80 LOC, no dependencies `[ESTIMATE]`.

**(vii) Jobs.** R: only as a *similarity-preserving structural hash* (similar terms → similar vectors),
i.e. a random-feature approximation of a tree kernel. P: no. L: role–filler binding is a notation for
composition, not evidence that it works; no.

---

## 4. Spectral and diffusion geometry computed from the graph (no training)

**(i) What.** Distances and coordinates derived deterministically from a graph's random walk: Laplacian
eigenmaps / diffusion maps (eigenvectors of the normalised Laplacian), commute-time (resistance)
distance, the successor representation `M = (I − γP)^{-1}`, personalised PageRank (PPR), heat-kernel
signatures, and DeepWalk/node2vec. Weisfeiler–Leman (WL) colour refinement gives structural feature
vectors by iterated neighbourhood hashing.

**(ii) Evidence.**
- These are the same object seen several ways. The successor representation's eigenvectors coincide with
  the graph Laplacian's (Stachenfeld et al.; used for option discovery by Machado et al.,
  https://arxiv.org/abs/1710.11089). DeepWalk, LINE and node2vec with negative sampling are implicit
  factorisations of closed-form random-walk matrices, and factorising that matrix directly by SVD
  (NetMF, https://arxiv.org/abs/1710.02971) *beats* the SGD versions. So the gradient is not needed.
- PPR can be maintained **incrementally and locally** under edge insertions/deletions (Zhang, Lofgren,
  Goel 2016, https://arxiv.org/abs/1603.07796: restore an invariant at the touched vertices, then push).
  Caveat from later analysis (https://arxiv.org/abs/2404.16267): the amortised bound holds for a random
  source. Static local push costs O(1/(εα)) independent of graph size `[FROM-MEMORY]`.
- WL subtree features remain a strong baseline against GNNs on small graph datasets
  (https://arxiv.org/abs/2007.08663; standard message-passing GNNs are bounded by 1-WL,
  https://arxiv.org/abs/1810.02244).
- A 2026 NeurIPS paper builds a reusable RL feature basis directly from low-frequency Laplacian
  eigenvectors ("Grid Cells as Spectral Successor Features", https://neurips.cc/virtual/2026/163782;
  title/abstract only, not read).

**(iii) Cost at 10²–10⁵ nodes** `[ESTIMATE unless noted]`.

| Object | 10² | 10³ | 10⁴ | 10⁵ | Incremental? |
|---|---|---|---|---|---|
| Dense eigendecomposition (≈10·n³ flops) | instant | seconds (LAPACK); tens of seconds in plain Lisp | hours, 800 MB | infeasible | recompute |
| Sparse Lanczos, k≈32 | — | <1 s | seconds | minutes | restart; error accumulates |
| SR by linear solve / per-source power iteration | instant | seconds | per-source only | per-source only | tabular TD update per transition |
| PPR by local push | ms | ms | ms | ms | yes, local |
| WL refinement, h rounds, O(h·m) | µs–ms | ms | ms | <1 s | re-hash affected region |

**(iv) Failure modes.**
- **Commute time degenerates**: on large, well-connected graphs it converges to `1/d_u + 1/d_v` and
  carries no global structure (von Luxburg, Radl, Hein, JMLR 2014,
  https://jmlr.org/papers/v15/vonluxburg14a.html). On small sparse or tree-like graphs it is still
  informative (on a tree it equals path length `[FROM-MEMORY]`).
- **Eigenvector coordinates are unstable**: sign and within-eigenspace rotation are arbitrary, and small
  spectral gaps make individual eigenvectors swing under a one-edge change. Incremental eigen-updates
  accumulate error and need restart heuristics (TIMERS, https://arxiv.org/abs/1711.09541). Use
  basis-invariant quantities (diffusion/heat-kernel distances, PPR vectors), never raw coordinates, as
  persistent identifiers.
- WL cannot separate regular graphs / certain symmetric structures; hashing collisions are silent.

**(v) Maturity.** SHIPPED (PageRank, spectral clustering, WL kernels are standard-library material).

**(vi) Smallest useful version.** PPR push ≈80 LOC; WL hashing ≈60 LOC; Jacobi symmetric eigensolver
≈120 LOC (or LAPACK via an existing CL binding); none needs a DL framework `[ESTIMATE]`.

**(vii) Jobs.** R: yes — this is the literal implementation of "proximity flows along verified links".
P: a PPR vector is a normalised distribution computed by a rule both coder and decoder share, so
`−log₂ PPR(seed→entry)` is a legitimate code length for "which library entry next" at the cost of one
parameter (α). L: no.

---

## 5. Many local spaces glued by maps

Three questions per method: **(a)** decides when a new space is needed? **(b)** tests whether two spaces
are the same up to a transform? **(c)** transports vectors across a verified map?

| Method | What it is | (a) new space | (b) same-space test | (c) transport | Gradient? | Maturity for *this* use |
|---|---|---|---|---|---|---|
| LTSA; charting; global coordination of local linear models `[FROM-MEMORY]` | local PCA per neighbourhood, aligned by one eigenproblem | no (one chart per point; assumes a global chart exists) | no | no | no | PROVEN-RESEARCH for dense manifold samples; not applicable to a symbolic library |
| Mixtures of factor analysers | EM over local linear-Gaussian patches | only via model selection (BIC / variational Bayes / MDL) `[FROM-MEMORY]` | merge moves by the same criterion | no | no (EM) | PROVEN-RESEARCH; needs ≫ d samples per patch |
| Atlas learning (Pitelis et al., CVPR 2013, [pdf](https://openaccess.thecvf.com/content_cvpr_2013/papers/Pitelis_Learning_a_Manifold_2013_CVPR_paper.pdf)) | alternates chart parameters and discrete point-to-chart assignment | chart count by a penalised cost `[FROM-MEMORY]` | no | no | no | SINGLE-PAPER |
| Vector diffusion maps (Singer & Wu 2012, [pdf](https://web.math.princeton.edu/~amits/publications/VDMrevision_final.pdf)) | local PCA bases + orthogonal alignment `O_ij` on each edge → connection Laplacian | no | cycle consistency (holonomy) is measurable | **yes** — `O_ij` *is* discrete parallel transport, from an SVD | no | PROVEN-RESEARCH on dense point clouds (cryo-EM); needs samples from a manifold |
| Cellular sheaves / sheaf Laplacian (Hansen & Ghrist) | a vector space per node and edge with linear restriction maps; `L = δᵀδ`; kernel = globally consistent assignments | no | **yes, given the maps**: `dim ker L` and cycle inconsistency are exact linear algebra | yes, given the maps | no, if maps are given | theory PROVEN-RESEARCH; applications SPECULATIVE |
| Learned sheaves (Bodnar et al. 2022, https://arxiv.org/abs/2202.04579) | restriction maps learned end-to-end | no | no | learned | yes | **disputed**: "On the Necessity of Learnable Sheaf Laplacians" (Mar 2026, https://arxiv.org/abs/2603.05395) finds identity maps comparable on five heterophily benchmarks |
| Connection-Laplacian sheaf networks (Barbero et al. 2022, https://arxiv.org/abs/2206.08702) | maps *computed* by local PCA + Procrustes, not trained | no | no | yes | maps no; network yes | SINGLE-PAPER |
| Gauge-equivariant / fibre-bundle networks `[FROM-MEMORY]` | convolution independent of local frame choice on meshes | no | no | built in | yes | SPECULATIVE here |
| Thousand Brains / Monty (https://arxiv.org/abs/2507.04494, Jul 2025) | each module stores objects as point sets in an object-centric frame; recognises by accumulating evidence over (object, rotation, location) hypotheses; modules vote by transforming hypotheses through known sensor displacement | **not demonstrated**: new frames are created under supervision; unsupervised learning "beyond scope" | yes, but only for rigid 3-D pose | yes, rigid displacement | no (Hebbian-like) | SINGLE-PAPER; authors call it "nascent" |
| Tolman–Eichenbaum machine (https://pmc.ncbi.nlm.nih.gov/articles/PMC7707106) | factorises structure code from sensory code; actions act on the structure code | no | implicit | learned action matrices | yes (trained across many environments `[FROM-MEMORY]`); equivalent to a transformer with recurrent position codes (https://arxiv.org/abs/2112.04035) | PROVEN-RESEARCH as neuroscience; not a small-data tool |
| Conceptual spaces (Gärdenfors) | concepts as convex regions in low-D "quality" domains | no | no | no | n/a | SPECULATIVE: implementations are "ad hoc" (https://arxiv.org/abs/1707.05165); convexity itself is contested (https://arxiv.org/abs/1801.03929) |

**Monty numbers, because it is the only non-gradient "many reference frames" system with a quantitative
evaluation.** 77 YCB objects, 14 training rotations: 98.6% classification, 0° median rotation error on
learned poses; 88.1% / 6° with noise and novel rotations. After 8 views per object (≈600 samples) 88%
accuracy; after one view ≈50% versus ≈30% for a from-scratch ViT; continual learning without the
catastrophic forgetting of a pretrained ViT; ≈34,000× fewer training FLOPs than the from-scratch ViT.
Limits stated by the authors: 3-D object perception only, simulator, no compositional objects, no
unsupervised learning, inference cost linear in the number of stored models.

**Tools for (b) outside any of these frameworks.** Orthogonal Procrustes (closed-form SVD; needs point
correspondences), CCA / CKA `[FROM-MEMORY]`, and "relative representations" — re-describe each point by
its similarities to a shared anchor set, which is invariant to isometries and rescalings and enables
zero-shot stitching of independently trained spaces (Moschella et al., ICLR 2023,
https://arxiv.org/abs/2209.15430). All need paired or anchor samples and are statistically weak when the
number of pairs is not well above the dimension.

**Calibrated take.**
- (c) is solved whenever maps are given; in this project the maps are verified transformers, so transport
  = apply the map (exactly) and recompute local features.
- (b) has an exact answer in a symbolic kernel (a verified round trip `g∘f = id` on the data), which
  dominates any statistical test at small n. Geometry's legitimate role is to *propose* candidate pairs
  cheaply (matching fingerprints / anchor-relative profiles), after which the exact engine decides.
- (a) has exactly one principled non-gradient precedent: **model selection by description length** (add a
  component / abstraction when it pays for itself in bits). That is what the kernel's MDL already does.
  No small-scale algorithm creates a *coordinate* space on demand.
- The sheaf formalism is an accurate *vocabulary* for "spaces on nodes, verified maps on edges, global
  consistency = kernel of a Laplacian", and a ≈150-LOC linear-algebra check `[ESTIMATE]`; there is no
  evidence it improves search.

---

## 6. The "flat is fine" position

**(i) What.** The claim that one high-dimensional space, read through context-dependent attention,
already carries hierarchical, categorical and relational structure.

**(ii) Evidence (all from gradient-trained LLMs).**
- Hierarchy is linear-algebraic, not hyperbolic: in Gemma and LLaMA-3, over 900 WordNet concepts,
  categorical concepts form simplices, hierarchically related concepts lie in **orthogonal** subspaces,
  complex concepts are polytopes (Park, Choe, Jiang, Veitch, ICLR 2025 oral,
  https://arxiv.org/abs/2406.01506).
- Syntax trees are recoverable by a linear map under which **squared L2 distance equals tree distance**
  (Hewitt & Manning 2019, https://aclanthology.org/N19-1419/). Any tree embeds exactly this way with
  about one axis per edge `[FROM-MEMORY, textbook]`.
- A flat space contains low-dimensional *local* spaces: circular features for weekdays and months, used
  for modular arithmetic (Engels et al., ICLR 2025, https://arxiv.org/abs/2405.14860).
- **Context can reorganise the geometry to a graph given only in the prompt**: with enough random-walk
  context, representations abruptly rearrange to match grid/ring/hex connectivity, Dirichlet energy
  falls, and the layout matches the graph's spectral embedding; pretrained semantics are not fully
  overridden (Park et al., ICLR 2025, https://arxiv.org/abs/2501.00070). In other words the transformer
  computes in context roughly what §4 computes directly.
- Relations are only *sometimes* linear operators: of 47 relations tested, a single affine map on the
  subject representation decodes some well and others hardly at all (company→CEO under 6% faithfulness
  although the model knows the facts) (Hernandez et al., ICLR 2024, https://arxiv.org/abs/2308.09124).
- The cost side: §3's bounds — a shared flat space saves storage, not computation.

**(iii) What this implies for a small non-gradient system.** None of this is evidence that such geometry
can be *obtained* without ~10^9 tokens of training. What is cheaply available is flat geometry over a
**given** feature map:
- Random projection (JL) and SimHash/LSH: ≈50 LOC; pointless below ~10^4 items, where brute-force
  nearest neighbour takes microseconds–milliseconds `[ESTIMATE]`.
- Kernel methods (kernel ridge / GP, O(N³) at N ≤ 10³), with graph/tree/string kernels as the feature
  map: the classical small-data workhorse; closed form `[FROM-MEMORY]`.
- **Modern Hopfield / dense associative memory**: the update is `softmax(β·Xξ)`-weighted recall, proved
  equivalent to transformer attention, with one-step retrieval and capacity exponential in dimension
  (Ramsauer et al., https://arxiv.org/abs/2008.02217). Operationally: one-step attention = soft
  k-nearest-neighbour over stored fingerprints, one parameter β, ≈30 LOC.
- "Context-dependent projection" = a context-conditioned diagonal reweighting of features, which can be
  count-based (IDF, naive-Bayes log-odds). That is exactly what the shipped symbolic-search guides in §7
  do.

**(iv) Failure modes.** The feature map is the whole game; a flat space over poor features retrieves
poorly, and nothing here learns the features.

**(v) Maturity.** LLM geometry findings: PROVEN-RESEARCH. Soft-kNN / kernel retrieval: SHIPPED.

**(vii) Jobs.** R: yes. P: indirectly (as predictor in a prequential code, §8). L: no evidence at small scale.

---

## 7. Geometry for search guidance in program synthesis

**Measured gains, cheapest first.**

| Technique | Learned? | Evidence | Maturity |
|---|---|---|---|
| **Observational equivalence**: keep one program per output vector on the examples | no | the standard backbone of bottom-up synthesis (Udupa 2013; Albarghouthi 2013); breaks with context-dependent semantics, free variables, mutation | SHIPPED |
| **Cost-ordered (size) instead of height-ordered enumeration** | no | Probe paper, String suite: size-based 42 of 82 vs height-based 9 | SHIPPED |
| **Just-in-time PCFG reweighting from partial solutions** (Probe, https://arxiv.org/abs/2010.08663): `p(R) ∝ p_u(R)^(1−Fit)` | online, no training data | 91/140 vs 44 for its height-based baseline, 50 for the pre-trained EuPhony, 107 for CVC4 (whose solutions are 9× larger). **Against a competent size-based baseline the gain is modest overall (116 vs 93 of 210) and concentrated on large grammars (25 vs 9); none on circuits** | PROVEN-RESEARCH |
| **Hand-tuned operation weights + value/type filters** (TF-Coder, https://arxiv.org/abs/2003.09040) | no | 61/70 with no model; the two learned models add 2 tasks and 1.78× speed. The natural-language model that worked best is TF-IDF cosine, not a network | SHIPPED (Google tool) |
| **Distance on behaviour**: observational *similarity* clustering + distance-guided repair (Feser, Dillig, Solar-Lezama, OOPSLA 2023, [draft](https://www.cs.utexas.edu/~isil/metric-synthesis.pdf)); "oriented metrics" that drop symmetry (POPL 2026, https://arxiv.org/abs/2511.02491) | no; metric is expert-supplied | search-space reductions of 56–664× in the draft's domains; >10× over state of the art in string/bit-vector domains for orimetrics | PROVEN-RESEARCH (two groups) |
| **MCMC on a test-case cost, then exact verification** (STOKE, https://arxiv.org/abs/1211.0557) | no | beats `gcc -O3` on kernels (Montgomery multiply 1.6×, 16 lines shorter) | PROVEN-RESEARCH |
| **Naive Bayes / kNN over symbol features** for premise selection (MaSh, [pdf](https://www21.in.tum.de/~blanchet/mash.pdf)) | counts only | shipped in Isabelle's Sledgehammer (the source's default learner is naive Bayes + kNN combined); reported to outperform the older hand-written filter on large formalisations — exact figures not retrieved | SHIPPED |
| **Non-neural classifier on clause features** guiding a saturation prover (ENIGMA: linear model in https://arxiv.org/abs/1701.06532; stronger non-neural learners in https://arxiv.org/abs/1904.01677) | trained on past proof searches | the later version improves E on the Mizar library by 70%, single strategy; the original linear version reports "a large increase" on the AIM benchmark | PROVEN-RESEARCH |
| **Property signatures** (Odena & Sutton, https://arxiv.org/abs/2002.09030; BUSTLE, https://arxiv.org/abs/2007.14381) | 45 hand-written boolean properties + a small MLP trained on ≈200k self-generated examples, CPU hours | >2× programs in <1/10 time; BUSTLE 31/38 within 30 M candidates; beats RobustFill and DeepCoder-style premise selection; property signatures beat learned character embeddings | PROVEN-RESEARCH |
| **Neural attribute prediction** (DeepCoder, https://arxiv.org/abs/1611.01989) | yes | 1–3 orders of magnitude on a tiny DSL (e.g. 62× at 20% solved for sort-and-add, T=3) | PROVEN-RESEARCH |
| **Recognition model + library learning** (DreamCoder, https://arxiv.org/abs/2006.08381) | yes, on self-generated "dreams" | text editing 3.7% → 79.6% solved after learning; on LOGO and towers no ablation exceeds 60% while the full system nears 100%. **Compute: about a day on 20–100 CPUs per domain; "approximately a year of total CPU time" for the origami result** | PROVEN-RESEARCH |

**Reading the table.** The cheapest guidance with *large* measured gains is, in order: behavioural
equivalence classes; cost-ordered enumeration; an online or corpus-derived production prior; a
count-based relevance classifier from task features to primitives. Learned neural guidance adds on top
of those, and in the one clean comparison (TF-Coder) adds little. BUSTLE's finding that hand-free boolean
properties beat learned embeddings is the strongest single argument for *derived* geometry.

**Budget calibration.** DreamCoder's domain results used on the order of 10^3 CPU-hours each. A
single-threaded "hours" budget is 10^2–10^3× smaller. Its recognition model is sample-efficient in real
tasks only because its training data are fantasies sampled from the library — which costs that compute.

**Recent context.** ARC: the 2020 Kaggle top score was 20% and those solutions were brute-force program
search; 2024's winner reached 53.5% and 2025's 24% on ARC-AGI-2, both driven by test-time adaptation of
neural networks ("the year of the refinement loop") (https://arxiv.org/abs/2412.04604,
https://arxiv.org/abs/2601.10904). An MDL-only approach with no pretraining, CompressARC, reaches 20% on
ARC-AGI-1 evaluation with a 76K-parameter network — but by gradient descent at inference
(https://arxiv.org/abs/2512.06104). Lexicase selection (per-test-case behaviour vectors) repeatedly beat
tournament selection in genetic program synthesis, though a 2025 study finds the edge vanishes in
symbolic regression (https://arxiv.org/abs/2502.18093).

**(vi) Smallest useful version** `[ESTIMATE]`. Fingerprint hashing + equivalence classes ≈100 LOC
(probably present already); Probe-style reweighting ≈80 LOC; naive Bayes / kNN from property bits to
primitives ≈150 LOC; fingerprint distance for near-miss ranking ≈50 LOC. No dependencies.

**(vii) Jobs.** R: yes — this is the best-evidenced section of the review. P: a production prior is a
code, so guidance and pricing can share one distribution. L: TF-IDF/naive-Bayes from words to primitives
is the cheap bridge (see §9).

---

## 8. Geometry for residual pricing ("distance as description length")

**(i) What.** Information distance `max{K(x|y), K(y|x)}` and its computable proxy, normalised compression
distance (NCD); MDL two-part and prequential codes; edit scripts as codes; Gaussian / kernel-density
codes for real-valued residuals; pullback metrics.

**(ii) Evidence and failure.**
- NCD is only a metric for "normal" compressors and in practice violates idempotency: the error depends
  on object size relative to the compressor window (32 KB gzip, 450 KB bzip2); NCD drifts to 1 when the
  pair does not fit (Cebrián et al. 2005, summarised in https://arxiv.org/abs/1509.00689).
- "gzip + kNN beats BERT" (https://arxiv.org/abs/2212.09410) did not survive: a bag-of-words distance
  works equally well or better, and reported numbers were inflated by an evaluation bug
  (https://arxiv.org/abs/2307.15002). Compression distance is a decent, not a magical, similarity.
- MDL as an objective *does* carry real problem-solving weight (CompressARC above), with gradient.

**(iii) The principled way to price a residual in a newly induced latent space** `[textbook MDL;
FROM-MEMORY for attributions: Rissanen, Grünwald 2007, Dawid 1984, Hinton & van Camp 1993]`.

1. *Two-part code*: `L = L(decoder g) + L(z | prior, precision) + L(x | g(z))`. The decoder direction is
   what the receiver needs, so it must be paid; the encoder is free.
2. *The residual is priced in observable (ambient) units.* Pricing it in latent units is legitimate only
   with the change-of-variables term (`log|det J|` for continuous maps). A contraction makes latent
   residuals look small for nothing; that is the cheat.
3. *Discrete version of the same rule*: a verified **bijection** transfers code lengths exactly, so after
   an exact isomorphism has been established, pricing in the induced space is licensed with no
   correction. A **quotient** (many-to-one) map owes the fibre index, `log₂|fibre|` bits, or a code for
   the element within its fibre.
4. *Continuous values*: a density becomes a code only at a declared precision δ:
   `L = −log₂ p(x) − k·log₂ δ`; each real parameter costs about `½·log₂ n` bits. A Gaussian residual code
   is `n/2·log₂(2πe σ²) − n·log₂ δ`.
5. *Adaptive geometry without cheating — prequential coding*: code each item with a predictor that is a
   deterministic function of the items already coded. kNN, kernel density, PPR, a soft-attention lookup —
   any of them is admissible and costs zero parameter bits, because the decoder can rebuild the predictor.
   This is the clean interface by which geometry may "price".
6. Edit distance is a code length only if the edit costs are negative log-probabilities satisfying Kraft;
   unit-cost Levenshtein is not. Optimal-transport distances are useful for proposing, not for pricing.

**Information geometry in one paragraph.** A decoder `g: Z → X` induces on Z the pullback metric
`JᵀJ` (https://arxiv.org/abs/1710.11379); when the decoder outputs distributions, pulling back the
Fisher–Rao metric gives the information-geometric version
(https://proceedings.mlr.press/v151/arvanitidis22b.html), and natural gradient is steepest descent in
that metric `[FROM-MEMORY]`. The practical content for this project is exactly rule 2: distances in an
induced space mean something only after being pulled back to what is observed. This answers the owner's
parenthetical: there is no better option than pricing in the ambient space, but an induced space may
*inherit* that pricing through a verified map.

**A native alternative to NCD.** The kernel already owns a stronger compressor than gzip: its own program
prior. `d(x→y) = ` bits of the shortest found program mapping x to y under the current library is an
(upper bound on an) information distance, asymmetric by nature — which matches the POPL 2026 finding
that useful synthesis metrics are oriented. Vector distances are then cheap *predictors* of this
quantity, to be calibrated against it.

**(v) Maturity.** MDL two-part / prequential coding: SHIPPED (it is how compressors work). NCD:
PROVEN-RESEARCH with known pitfalls. Learned-metric pricing: no precedent that does not reduce to the rules above.

**(vi) Smallest version** `[ESTIMATE]`. Quantised Gaussian and prequential-kNN code-length functions:
≈100 LOC.

**(vii) Jobs.** P: yes. R: the same code lengths rank. L: no.

---

## 9. Compositional language semantics with geometry

**(i) What.** DisCoCat assigns each word a tensor whose order is dictated by its grammatical type and
composes by contraction; Baroni & Zamparelli make adjectives matrices acting on noun vectors; role–filler
schemes bind words to roles; language-guided library learning aligns words with program primitives.

**(ii) Evidence.**
- *Words as operators on vectors*: Baroni & Zamparelli 2010 (https://aclanthology.org/D10-1115/) fit one
  matrix per adjective by regression from corpus-observed adjective–noun vectors — closed form, but each
  adjective needs many observed phrases and a large corpus to supply the vectors. Results against simple
  addition/multiplication are mixed across tasks and papers.
- *DisCoCat*: published experiments are tiny — a 130-sentence two-topic classification and 105 noun
  phrases (https://arxiv.org/abs/2110.04236, https://arxiv.org/abs/2102.12846). No evidence of scaling.
- *Words as vector offsets*: fragile (§2).
- *Words as program fragments* — the approach with real small-data evidence. CCG semantic parsing maps
  each word to a typed lambda term and composes by application, learned from a few hundred sentences
  (Zettlemoyer & Collins 2005, [pdf](https://people.csail.mit.edu/lsz/papers/zc-uai05.pdf); from
  question–answer pairs only in Liang, Jordan, Klein 2011, https://aclanthology.org/P11-1060/; GeoQuery
  size and accuracies `[FROM-MEMORY]`: ≈600 training sentences, ≈80–90%).
- *Language-guided library learning*: LAPS (ICML 2021, https://arxiv.org/abs/2106.11053) couples
  DreamCoder with an IBM-Model-4 word↔primitive translation model. Held-out tasks solved, baseline →
  best LAPS: strings 33.4 → 54.6–57.0%; graphics (mean over seeds) 42.6 → 82.0%; scenes 73.9 → 95.9%.
  With **no language at test time**, the LAPS-learned library with example-only neural search still gives
  52.4 (strings), 91.0 (graphics, best run), 95.6 (scenes). With human rather than synthetic descriptions
  the best graphics run drops from 98.2 to 58.6. LILO (https://arxiv.org/abs/2310.19791)
  replaces the alignment model with an LLM: REGEX 43.9 → 77.1 (mean), LOGO 28.5 → 49.0, CLEVR ≈ ceiling;
  the authors equate one LLM round to ≈48 CPU-hours of enumerative search.

**(iii) Data/compute; gradient?** Regression or SGD for tensor models; EM counts for alignment models;
structured perceptron / log-linear for CCG. The alignment and lexicon learners are not deep learning.

**(iv) Failure modes.** Tensor order explodes with grammatical type; per-word operators need per-word
data; synthetic-language results overstate human-language performance (LAPS graphics, best run: 98 → 59).

**(v) Maturity.** Words-as-lambda-terms with a statistical lexicon: PROVEN-RESEARCH at 10²–10³ examples.
LAPS-style alignment inside library learning: PROVEN-RESEARCH (two systems). DisCoCat: SPECULATIVE at any
useful scale. Offsets: PROVEN-RESEARCH that they are unreliable.

**(vi) Smallest version** `[ESTIMATE]`. IBM-Model-1 word↔primitive alignment by EM ≈120 LOC; a typed
lexicon whose entries are library terms needs no new machinery beyond the kernel's own application.

**(vii) Jobs and the owner's three word types.**
- "like" (proximity) → restrict or re-rank retrieval by similarity: supported (§6, §7).
- "analogy" (a vector in some space) → supported only as *apply the same verified map*; the vector-offset
  reading is the weak one.
- "action" (make a space, operate between spaces) → supported as a lexicon entry that is an operator
  term; unsupported as a geometric act.

---

## 10. Topological data analysis; geometric deep learning

**TDA.** Persistent homology summarises the multi-scale connectivity of a *point cloud with a metric*
(components, loops, voids) as a stable diagram; Mapper produces a graph summary from a filter function
and a cover. Cost is cubic in the number of simplices in the worst case `[FROM-MEMORY]`. Mapper's output
"may vary dramatically with the choice of parameters" (https://arxiv.org/abs/1906.01507) and still lacks
standard quantitative evaluation (2025 review, https://arxiv.org/abs/2504.09042). For this project the
topology is *given* exactly by the kernel's graph, so there is nothing to infer from samples; the only
plausible use is a diagnostic (count the independent cycles in a derivation graph), which is ordinary
graph homology and needs no persistence. Maturity for this use: SPECULATIVE. Import nothing.

**Geometric deep learning.** Bronstein et al.'s blueprint derives architectures from a symmetry group and
a locality prior; on graphs this yields message passing, whose distinguishing power is capped by 1-WL
(https://arxiv.org/abs/1810.02244) `[blueprint details FROM-MEMORY]`. Two things transfer without any
network: the design rule "features should be invariant to relabelling and equivariant to the declared
symmetries", and the fact that WL hashing already attains the 1-WL ceiling for free. Everything else
needs gradient training. Maturity: SHIPPED as deep learning; as a non-gradient method it reduces to §4.

---

## 11. arXiv:2611.17309

**Reachable.** "Classical Energies Learn to Reason 1,000x Faster than Looped Models", Hoover, Blayney,
Whittington; submitted 12 Nov 2026, v2 19 Nov 2026 (https://arxiv.org/abs/2611.17309). I read the HTML
and searched its full text.

**What it is.** CRAM is a trainable version of the 1980s Hopfield–Tank energy: each cell holds a softmax
belief over C values; the energy is a mean-field free energy with an entropy term, learned **pairwise**
C×C cost matrices between cells, and per-cell input biases. Training is by **pseudolikelihood** on solved
puzzles: SGD with momentum on a per-cell local objective, weights starting at zero, never differentiating
through the solver. (So it is gradient-trained, but on a local objective that needs no inference.)
Inference is focused Gibbs-style descent with several chains, stopping when energy falls under a
threshold fitted on training solutions.

**Numbers.** Sudoku-Extreme 99.996%, Maze-Unique 100%, after 42 ms and 132 ms of training on one GPU;
looped baselines take 1–16 hours (HRM 54.6%, TRM 85.7% on Sudoku-Extreme). At matched accuracy ≥282×
fewer inference FLOPs. ≈98% with about 30 unique training puzzles (each augmented 99 times by digit
relabelling), versus roughly 700 for the best looped baseline. Parameters: 263K for Sudoku (≈7.7K nonzero
after training), **18 for Maze**. The learned weights recover the constraint graph (positive costs on
exactly the 810 same-row/column/box pairs) without being given it. Pseudolikelihood reaches 99% in
≈50 ms where full backprop-through-time reaches 48.8% after hours. Hand-set energies with one to three
distinct values solve every test puzzle.

**What it claims and does not claim.** The message is that these benchmarks are representable exactly by
a pairwise energy and therefore "not indicative of future performance on harder tasks"; the plain energy
"would struggle" on ARC-AGI where answers depend on computed quantities; a 29-parameter latent extension
reaches 99.9% on Maze-Hard, but learning such latents in general "remains open". It ties itself to
constraint acquisition and to prior work that learns pairwise costs and hands them to an exact solver.

**Relation to the owner's gloss.** The phrase "brute force" does not occur in the paper, and the method
is local energy descent, not exhaustive search. The transferable lessons are narrower and useful:
(1) when the hypothesis class matches the problem (pairwise constraints), a *local* fit that never
backpropagates through search suffices, from tens of examples; (2) an energy gives a stopping rule; (3) the learned object
is interpretable as constraints, which an exact engine can then verify. Independent corroboration that
the looped models' architecture was not the active ingredient: ARC Prize's analysis of HRM found a plain
transformer within ≈5 points and attributed most of the score to the outer refinement loop
(https://arcprize.org/blog/hrm-analysis).

---

# Closing

## (a) Candidate geometry engines for a small exact symbolic kernel

| | Flat global vector space (one learned embedding) | Per-space local coordinates glued by verified maps | Graph-derived (spectral / diffusion / WL) | Behavioural fingerprints (+ property signatures) |
|---|---|---|---|---|
| **Rank / propose** | strong *if trained*; no small-scale evidence untrained | no measured gain anywhere at small scale; Monty only for 3-D pose | good: PPR / SR retrieval, WL keys; shipped algorithms | **best evidence**: equivalence pruning, Probe, BUSTLE, MaSh, metric synthesis |
| **Price residuals** | only via a prequential predictor; otherwise must pay for the decoder | exact when the map is a verified bijection; quotient owes fibre bits | PPR gives a valid prior over library entries | native: residual = disagreement on probes, priced in ambient units |
| **Compose language** | LLM evidence only; offsets fragile | unproven (DisCoCat toy-scale) | none | indirect: words ↔ primitives by alignment counts |
| **Sample-efficiency** | poor (10^5+ examples typical) | unknown; local PCA needs ≫ d samples per patch | excellent (no samples; needs only the graph) | excellent (needs probe inputs, which the kernel generates) |
| **Needs gradient training** | yes | no if maps are given; yes if learned | no | no (counts or convex fits) |
| **Incremental under library change** | retrain / drift | local by construction | PPR local; eigenvectors unstable | local (new entry = new row) |
| **Implementation risk** | high (optimiser, drift, no ground truth) | high (no working precedent for creation/collapse) | low–medium (avoid raw eigenvector coordinates and commute time on dense graphs) | low |
| **Maturity** | SHIPPED at scale, unproven small | SPECULATIVE → SINGLE-PAPER | SHIPPED | SHIPPED / PROVEN-RESEARCH |

## (b) What the evidence says about "nested vs flat"

1. **Flat spaces represent nesting without difficulty when dimension is not scarce.** Trees are exactly
   squared-Euclidean; LLMs realise hierarchy as orthogonal subspaces and categories as simplices;
   Euclidean matches hyperbolic on WordNet from 50 dimensions up. Curved or nested geometry is a
   *compression* of that, valuable when one must pack 10^5 concepts into few dimensions — not this
   project's regime.
2. **A shared flat space saves storage, not computation.** Superposition bounds say computing m′ features
   costs about m′ parameters regardless. A small system has no storage pressure, so it has no reason to
   superpose: explicit sparse features (one dimension per property, primitive, WL colour, probe) are
   exact, interpretable and incremental.
3. **Flat spaces already contain local spaces.** Circular weekday features, orthogonal hierarchy
   subspaces and context-induced graph layouts are sub-manifolds selected by context. "Many local spaces"
   and "one flat space read through attention" are two descriptions of the same arrangement; the
   difference is whether the selection is an explicit index or a learned soft one.
4. **Explicit local spaces glued by maps work only where the maps or dense samples are given.** Here the
   maps are given — they are verified library transformers — so the atlas already exists as the typed
   graph. Nothing in the literature shows that giving each chart *learned coordinates* helps at this
   scale.
5. **The brain analogy cuts the same way.** The hippocampal models that fit data best are equivalent to
   transformers with recurrent position codes, and grid-like codes are Laplacian eigenvectors of the
   transition graph: flat activity, structure supplied by the graph and by context.

**Resolution supported by evidence:** keep nesting in the *topology* (the exact graph, which is already
recursively folded) and keep geometry flat, local to each node's native type, explicit, and recomputable.
"Context" is then a choice of seeds and feature weights (PPR personalisation, count-based reweighting),
not a learned projection. This is a reading both of the owner's positions are consistent with; the
evidence does not support building a nested geometry engine first.

## (c) The most conservative design from SHIPPED / PROVEN-RESEARCH parts only

1. **Truth and price**: exact verification; MDL in ambient units; code-length transfer across spaces only
   through verified bijections, with fibre bits for quotients; prequential coding wherever an adaptive
   predictor is used.
2. **Behavioural geometry**: output vectors on probe inputs → equivalence classes (hash) and a fingerprint
   distance for near-miss ranking and repair.
3. **Feature geometry**: boolean property signatures of values, tasks and entries (properties are
   themselves predicates the kernel can discover and add) → sparse vectors.
4. **Priors from counts**: production / bigram prior from the solved corpus; within-task reweighting from
   partial solutions; naive Bayes or kNN from task features to primitives.
5. **Graph proximity**: personalised PageRank by local push over the dependency / derivation graph, seeded
   by the current task; WL hashes as structural keys; a dense eigen-solve only as an offline diagnostic.
6. **Retrieval**: one-step softmax attention (soft kNN) over fingerprints, with count-based feature
   weights as the "context".
7. **Language**: a lexicon from words to library terms, scored by an IBM-Model-1-style alignment;
   composition is the kernel's own typed application.

Rough size: 800–1,200 lines of Common Lisp, no dependencies beyond an optional LAPACK binding `[ESTIMATE]`.

**What it gives up.** No learned continuous embeddings and therefore no generalisation beyond feature
overlap; no vector-offset analogy; no "moving" vectors (proximity is recomputed, not learned); no
per-space coordinate systems; no geometric trigger for creating or collapsing spaces (creation stays an
MDL decision, collapse stays an exact isomorphism check); heuristic quality capped by the property
vocabulary and by how well the dependency graph reflects usefulness. It also gives up the hope that
geometry will find structure the exact engine cannot verify — by construction it only reorders work.

## (d) Owner's wishes with no convincing precedent

1. **An engine that *makes* coordinate spaces when residuals require**, from tens of samples, without
   gradient descent. Closest precedents: MDL/BIC component addition in mixture models; library-learning
   compression. Monty's new reference frames are created under supervision in every reported result.
2. **Collapsing spaces on geometric evidence of sameness.** Procrustes/CCA/anchor methods need paired
   samples well in excess of the dimension. The reliable version is exact (verified round trip), which is
   topology, not geometry.
3. **Vectors that are moved by induced proximity and stay meaningful as spaces are created and merged.**
   Proximity *computation* along links is well precedented (PPR, successor representation, and
   "retrofitting"-style neighbour averaging `[FROM-MEMORY]`); persistent learned coordinates under a
   changing graph are not — eigen-coordinates are unstable and incremental updates drift.
4. **Language in which each word is a geometric modifier** (proximity term, offset vector, or
   space-creating action) in a small non-gradient system. Offsets are unreliable even at corpus scale;
   tensor semantics is toy-scale; what works is words as program fragments with statistical alignment.
5. **A hybrid nested geometry–topology engine that beats both flat embeddings and a pure symbolic graph.**
   No head-to-head evidence exists. The nearest candidates (sheaf networks, mixed-curvature spaces) show
   small or disputed gains even with gradient training and large data.
6. **Geometry that makes residual pricing fundamentally better than ambient pricing.** Theory forbids it:
   every consistent scheme reduces to ambient units plus a correction. Geometry can only supply a better
   predictive distribution.

---

## Appendix: items seen but not read

Surfaced in search results by title only; not used as evidence: "The Ball and the Box: Two Geometries of
Computation in Superposition" (arXiv 2610.11744); "Sheaf-MPNN: A Library for Sheaf Neural Networks as
Message Passing" (arXiv 2611.04670); "Hierarchical Pooling for Sheaf Neural Networks" (arXiv
2606.20932); "Learning the structure of Connection Graphs" (arXiv 2510.11245); "Variational Atlas
Autoencoders and Self-Supervised Chart Selection" (arXiv 2610.33577); "An Introduction to
Compression-Based Machine Learning" (arXiv 2609.21309); "A Three Axis Evaluation Framework for Mapper
Algorithms" (arXiv 2606.21688).

## Appendix: verification gaps worth knowing about

- DreamCoder's per-domain ablation percentages are in a figure, not text; only the text-editing numbers
  and the "≤60% vs ≈100%" statement were verified.
- BUSTLE's baseline solve counts are plotted, not tabulated; only "31 of 38" is exact.
- The metric-synthesis reduction factors come from the 2018 draft record, not the OOPSLA 2023 version.
- Nickel & Kiela's original table was not opened; the 0.87 figure is as quoted by Sala et al.
- Bansal & Benton is an arXiv preprint; I found no peer-reviewed venue listed.
- The Monty paper is from the system's own developers; no independent replication found.
- arXiv:2611.17309 post-dates my training data; everything about it comes from today's fetch.
