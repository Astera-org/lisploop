# Literature fact-check: learned search policy, learned guards/totality, inverse discovery

Checked 2026-11-24. Audience: owner of an LLM-free, single-threaded, enumerative program-induction kernel.
Purpose: calibration (maturity, measured scale, failure evidence), not advocacy.

## How to read these notes

- **VERIFIED** — the number or quote was read this session in the cited source (PDF text via pdftotext, ar5iv HTML,
  or publisher/author page). Quotes are verbatim and short.
- **DERIVED** — arithmetic or a reading across verified numbers; the inference is mine.
- **SNIPPET** — seen only in a search-result summary or third-party record.
- **FROM-MEMORY** — not checked online this session. Treat as a pointer, not a fact.
- LOC figures under "smallest sound version" are engineering estimates, never sourced, unless a quote is given.
- Maturity tags: SHIPPED / PROVEN-RESEARCH (several independent implementations) / SINGLE-PAPER / SPECULATIVE.

## Limits of this check

- The session's web-search quota (shared) ran out about one third of the way through. After that only direct
  fetches of known URLs were possible. Consequences: (a) sweeps for 2023–2026 work are "none found", not "none
  exists"; (b) several classic papers behind paywalls (Springer, Elsevier, ACM) were read only through open
  precursors (Minton AAAI-88 for AIJ 1990; Tambe & Rosenbloom IJCAI-89 for MLJ 1990; Korf AAAI-82 for AIJ 1985).
- Two sources are OCR of scans (Minton AAAI-88, Korf AAAI-82); digits may carry OCR error.
- Parts 2 and 3 were compiled by parallel workers under the same rules and spot-read, not re-verified line by line.
- Scratch text extracts: `txt/` (Part 1), `txt2/` (Part 2), `txt3/` (Part 3) beside this file.

## Contents

- PART 1 — learning search policy with no / minimal neural nets (25 entries + ranked list)
- PART 2 — learning guards / preconditions / totality from failures (entries + the standard recipe)
- PART 3 — inverse / solver / propagator discovery (entries + conclusion)
- Consolidated list of what could not be verified

===================================================================================================

# PART 1 — Learning search policy with no / minimal neural nets

Conventions. "VERIFIED" = I read the number in the cited primary source during this session (PDF text
extracted with pdftotext, or ar5iv HTML). "FROM-MEMORY" = not checked online this session. "DERIVED" = my
arithmetic on verified numbers. LOC estimates under (v) are my own engineering estimates, never sourced.
Web-search quota ran out part-way through; items affected are flagged.

---------------------------------------------------------------------------------------------------

## 1.1 Probe — just-in-time PCFG learning (Barke, Peleg, Polikarpova, OOPSLA 2020)
Source: https://arxiv.org/abs/2010.08663 (PDF text extracted; ar5iv https://ar5iv.labs.arxiv.org/html/2010.08663)

(i) Bottom-up enumeration with observational-equivalence pruning, ordered by integer cost = rounded −log p of a
PCFG. The PCFG starts uniform and is re-estimated *during the same task* from "partial solutions" (programs
satisfying a subset of the examples); each update restarts the enumeration.

(ii) Update rule (Sec 5.3), VERIFIED: `p(R) = p_u(R)^(1−Fit) / Z`, where
`Fit = max_{P ∈ PSol, R ∈ tr(P)} |E ∩ E[P]| / |E|` — "the highest proportion of input-output examples that any
partial solution derived using this rule satisfies"; p_u uniform, Z normaliser. Costs: "cost(R) = ⌊rcost(R)⌉",
rcost = −log p (Sec 4). Partial solutions are filtered by a selection scheme; the chosen default is "First Cheapest": "selects a single
cheapest program (first enumerated) that satisfies a unique subset of examples". The update is not cumulative
counting: Fit is a max over selected partial solutions, exponentiating the *uniform* prior each time.

Benchmarks, VERIFIED: 140 SyGuS benchmarks (82 String, 27 BitVec, 31 Circuit), 10-minute timeout.
 - Headline: "Probe is able to solve a total of 91 problems within a timeout of ten minutes, compared to only 44
   problems for the baseline bottom-up synthesizer and 50 problems for EuPhony".
 - BUT the "44" baseline is HEIGHT-based enumeration. Against SIZE-based enumeration (Sec 6.2):
   String 48 vs 42 (height 9); BitVec 21 vs 20 (height 13); Circuit 22 vs 22 (height 22).
   DERIVED: Probe 91 vs size-based 84 of 140 — a gain of 7 problems (+8%).
 - Bloated grammar (70 String benchmarks with the union grammar, 48 string literals, 11 int literals):
   "Probe solves 25 benchmarks ... whereas height-based and size-based enumeration solved 1 ... and 9".
   Overall 210: "Probe solves 116, size-based solves 93 and height-based solves 45."
 - vs solvers (Sec 6.4): "Probe solves 91 within the 10-minute timeout, EuPhony solves 50, and CVC4 solves 107";
   String 48/23/75, BitVec 21/14/13, Circuit 22/13/19. CVC4 solutions "9 times larger than Probe solutions on
   average" (0.42 ite per example vs 0.01).
 - DERIVED and worth stating: plain size-based bottom-up + observational equivalence (84) beat offline-trained
   Euphony (50) on this set at 10 min. Baseline quality dominates the learned-guidance effect.

(iii) Failure modes (paper's own): Circuit domain — "the search is slowed down due to the restarting overhead"
because the grammar is tiny (4 operations median) and solutions use most productions; "trade-off between
restarting synthesis too often ... and restarting too infrequently"; rounding makes the probability ordering
only approximate; no condition abduction (so loses to CVC4 on String: 48 vs 75). My inference (not stated in
the paper): the signal is *partial credit over examples*, so it gives nothing on single-example or
all-or-nothing tasks.
Bee Search paper notes Probe's update interval d had to be tuned per algorithm (1..7).

(iv) Maturity: SINGLE-PAPER for the update rule; the *search skeleton* (cost-ordered bottom-up with OE) is
PROVEN-RESEARCH (re-implemented in Bee Search, Bustle, TF-Coder, HeapSearch lineage).

(v) Smallest sound version: integer-cost bottom-up bank indexed by cost; per-rule Fit table; recompute costs;
restart. ~200–400 LOC on top of an existing size-based enumerator (my estimate).

(vi) Relevance: the closest published match to "reflection with no NN, single thread"; expect large gains only
when the primitive set is bloated relative to what a task needs, small gains (+8%) on curated grammars.

---------------------------------------------------------------------------------------------------

## 1.2 E.C. (Dechter, Malmaud, Adams, Tenenbaum, IJCAI 2013)
Source: https://ijcai.org/proceedings/2013/0196.pdf (text extracted)

(i) Iterate: enumerate the N most probable expressions ("frontier") from a weighted combinator grammar over a
*set* of tasks; pick, per solved task, the solution maximising cross-task compressibility (fewest unique
subtrees); add shared subtrees as new productions and re-weight. No neural net.

(ii) VERIFIED: symbolic regression, 1000 tasks, 15 iterations, frontier 10 000: "the baseline run only hits 27 of
the 1000 tasks (3%), whereas our algorithm nears 100% for a frontier of 10000" (baseline = 150 000 expressions
from the initial grammar, the same total budget). Budgets are tiny by modern standards (1.5e5 expressions).

(iii) Failure modes, VERIFIED: Boolean-function experiment 2, frontier 2000, 10 runs: "several local minima that
the majority of the runs get stuck in with performance around 50%". Exact compression is exponential; they bound
candidate solutions per task to 2. Needs a task *distribution* with shared structure (the tasks were generated
from polynomials / circuits, i.e. a curriculum the authors constructed).

(iv) SINGLE-PAPER (superseded by EC²/DreamCoder, same group). (v) ~500 LOC (estimate): enumerator + subtree
counting + count-based reweighting. (vi) Relevance: evidence that pure count-based grammar re-estimation +
subtree abstraction bootstraps from 3% to ~100% — on a synthetic, self-similar task family.

---------------------------------------------------------------------------------------------------

## 1.3 EC² (Ellis, Morales, Sablé-Meyer, Solar-Lezama, Tenenbaum, NeurIPS 2018) — the no-NN ablations
Source: https://people.csail.mit.edu/asolar/papers/EllisMSST18.pdf Table 3 (text extracted)

(i) Explore/Compress/Compile: enumerate under (D, θ), compress frontiers into new DSL primitives, re-fit θ
("Once we have a DSL D we can update θ to arg max_θ L(D, θ, {F_x})"), train a recognition net. θ is one weight
per primitive (+ θ_var) — a unigram model.

(ii) Table 3, % held-out tasks solved, VERIFIED (columns: Ours / No NN / SE / NPS / PCFG / Enum):
 - List processing: 94 / 79 / 71 / 35 / 62 / 37
 - Text editing:    74 / 43 / 30 / 33 /  0 /  4
 - Symbolic regr.:  84 / 75 / 62 / 38 / 38 / 37
 where "PCFG ... lesions the recognition model and does not learn the DSL, but instead learns the parameters of
 the DSL (θ)", "No NN: lesions the recognition model", "Enum ... enumerates a frontier without any learning".
 Reading: θ-re-estimation alone = +25 points (lists), −4 (text), +1 (regression). Library learning without NN =
 +42 / +39 / +38 points over Enum. Library learning is the reliable no-NN lever; weight re-estimation alone is
 domain-dependent to the point of being useless in 2 of 3 domains.
 Text editing vs SyGuS: before learning 3.7%, after 74.1%, CVC4 82.4%.

(iii) Failure modes: without NN the system hits "a lower 'plateau' after which it stops solving new tasks".
Table extracted from a 2-column PDF; I re-assembled column order from the surrounding text — check the PDF
before quoting the symbolic-regression row.

(iv) PROVEN-RESEARCH for the wake/compress loop (EC, EC², DreamCoder, plus Stitch/LILO/babble re-implementations
of the compression half — FROM-MEMORY for those three). (v) unigram MAP re-estimation from frontier counts:
~100 LOC; fragment-grammar compression: thousands. (vi) Relevance: the cleanest published ablation separating
"re-weight" from "abstract" with no neural net.

---------------------------------------------------------------------------------------------------

## 1.4 DreamCoder (Ellis et al., arXiv 2006.08381; PLDI 2021)
Sources: https://arxiv.org/abs/2006.08381 (main text) and the version with supplement
https://www.cs.cornell.edu/~ellisk/documents/dreamcoder_with_supplement.pdf (text extracted; S-numbers below)

(i) Wake (enumerate, neurally guided) / abstraction sleep (refactor via version spaces, MDL) / dreaming sleep
(train recognition net on replays + fantasies).

(ii) The no-NN part, VERIFIED (S4.5.4): "We use an EM algorithm to estimate the continuous parameters of the
generative model, i.e. θ"; counts c(e, ρ) = "number of times that primitive e was used in program ρ"; the M-step
maximises a Jensen lower bound ("an instance of Generalized EM"). So the generative model is a *unigram* over
library entries, fit from expected usage counts in the per-task beams. The *bigram* is a parameterisation of the
recognition network's output (S4.6: "a kind of 'bigram' model over trees"), and the symmetry-breaking benefit is
reported only "when using both bigram parameterization and" the MAP training objective — i.e. it is a neural
result, not a count-based one. Enumeration is budget-deepening: programs "with description length between ∆ and
2∆, then 2∆ to 3∆, etc., until a timeout is reached" (S4.4).
 Numbers, VERIFIED: SyGuS text editing 3.7% → 79.6% (10 min/problem), 84.3% at "1 hour & 8 CPUs per problem",
 CVC4 82.4%; "no alternative model ever solves more than 60% of held-out tasks" in LOGO/towers "while DreamCoder
 learns to solve nearly 100%"; "93% of the laws" in the physics set after 8 cycles; typical runs on "20-100
 CPUs"; enumeration baseline "24 hours per task".
 The one experiment run WITHOUT the recognition model (S2.1.8, recursion from 1959-Lisp primitives + Y
 combinator): "We did not use the recognition model for this experiment"; "roughly five days on 64 CPUs" to solve
 "all 20 problems"; "DreamCoder took approximately a year of total CPU time". This is the closest published
 analogue of an LLM-free, NN-free library learner over a minimal Lisp, and its price is ~1 CPU-year for 20
 introductory tasks.
 Per-domain ablation percentages are only in Fig. 6 — NOT VERIFIED numerically.

(iii) Failure modes: compute; needs a task corpus with shared structure; the no-NN ablation plateaus (EC² Table 3
above); authors: "while learning from scratch may be possible in theory, such approaches suffer from a notorious
thirst for data ... or, if not data, then massive compute".

(iv) PROVEN-RESEARCH. (v) not small: tens of kLOC OCaml/Python (FROM-MEMORY). (vi) Relevance: the unigram EM
re-estimation is trivially portable (~100 LOC); its isolated measured benefit is the "PCFG" column of EC²
Table 3, i.e. unreliable; the measured cost of NN-free bootstrapping from Lisp primitives is a CPU-year.

---------------------------------------------------------------------------------------------------

## 1.5 Euphony (Lee, Heo, Alur, Naik, PLDI 2018)
Source: https://www.cis.upenn.edu/~alur/PLDI18.pdf (text extracted)

(i) Learns a probabilistic higher-order grammar (PHOG: production probabilities conditioned on AST context) from
solutions of previously solved problems (transfer learning via a feature map between grammars), then runs A*
top-down enumeration with the PHOG as cost, on top of EUSolver's divide-and-conquer.

(ii) VERIFIED (Table 3): 1,167 problems (762 training, 405 testing), timeout one hour: "Euphony is able to solve
236 out of 405 problems ... average and median times of 11m and 2m ... EUSolver is able to solve only 87 of the
problems, with average and median times of 29m and 26m." Overall row: 236 vs 87; 10m48s vs 29m20s average.
Size: "15,416 lines of Python code and 4,375 lines of C++".
Counter-evidence (Probe paper, same String test set, 10-min timeout): Euphony 50/140 vs Probe 91 vs CVC4 107 vs
plain size-based bottom-up 84 (DERIVED).

(iii) Failure modes: needs a corpus of solved problems in the same domain (762 training problems); training
set was "problems EUSolver could solve within 10 minutes", i.e. guidance learned on easy problems; authors note
training/test distribution shift and overfitting of richer models; top-down A* cannot use observational
equivalence the way bottom-up can (HeapSearch paper: "A* ... every new program has to be evaluated from scratch").

(iv) SINGLE-PAPER (PHOG idea from Bielik/Raychev/Vechev; one synthesis implementation). (v) n-gram-conditioned
production counts + A*: ~500 LOC core (estimate); authors' tool ~20 kLOC. (vi) Relevance: offline corpus
statistics give ~2.7× more problems solved over the *same* solver without them, yet lose to a better-engineered
unguided enumerator — implement the cheap enumerator first.

---------------------------------------------------------------------------------------------------

## 1.6 DeepCoder (Balog et al., ICLR 2017) and the shrinkage of its speedups
Sources: https://ar5iv.labs.arxiv.org/html/1611.01989 ; critique numbers https://arxiv.org/html/1809.04682 (PCCoder,
Zohar & Wolf NeurIPS 2018) ; https://www.cs.utexas.edu/~isil/pldi18-neo.pdf (Neo)

(i) A feed-forward net maps I/O examples to marginal probabilities that each of 34 DSL functions appears in the
target; search (DFS, "sort and add" enumeration, Sketch, λ²) tries functions in predicted order. NEURAL.

(ii) VERIFIED (DeepCoder tables; baseline = same search ordered by global prior frequency of functions):
 T=3 test (500 programs): speedup at 20/40/60% solved — DFS 15.2×/3.9×/2.9×; Enumeration 62.2×/54.6×/31.5×;
 λ² 80.4×/94.6×/6.2×. T=5 test (100 programs, net trained on T=4): DFS 6.8×/5.6×/2.6×; Enumeration 907×/>37×/>2×;
 λ² 9.6× at 20% only. Five examples per task with "relatively large integer values".
 Shrinkage, VERIFIED: PCCoder Table 2 (timeout 5,000 s, their DeepCoder re-implementation): DeepCoder solves
 63.0% at length 5, 11.2% at length 8, 7.0% at 10, 4.0% at 12, 2.0% at 14; "DeepCoder, meanwhile, fails to
 surpass the 5% mark for these lengths". PCCoder Table 1 (length 5, 10,000 s): original DeepCoder reaches 60%
 solved in 2654 s. Neo's re-implementation: "DeepCoder solves 32% of the benchmarks with an average running time
 of 205 seconds" (100 generated benchmarks with ≥5 components, 5-min limit).

(iii) Failure modes: the speedup is a ratio at a fixed fraction-solved and falls from ~15–60× (20% solved) to
~3× (60% solved) for DFS even in the paper's own table; a global presence/absence vector carries no positional
information so its value decays with program length; trained on synthetic programs (Shin et al., "Synthetic Datasets for Neural Program
Synthesis", https://arxiv.org/abs/1912.12345, abstract VERIFIED: synthetic generation "causes deep networks to
generalize poorly to certain data distributions" — shown on Karel/Calculator, not on DeepCoder itself); no public implementation (both PCCoder and Neo
re-implemented it; PCCoder's re-implementation was slower than the original: 67 s vs 24 s at 20%).

(iv) PROVEN-RESEARCH as an idea (many re-implementations); the headline factors are not robust.
(v) Non-neural analogue: per-task attribute → function co-occurrence table (naive Bayes); ~150 LOC (estimate).
(vi) Relevance: "predict which primitives are present" is the weakest form of guidance; do not budget for >3×
from it on programs longer than ~5 statements.

---------------------------------------------------------------------------------------------------

## 1.7 Property signatures (Odena & Sutton, ICLR 2020)
Source: https://ar5iv.labs.arxiv.org/html/2002.09030

(i) A "property" is a small boolean program over (input, output); a task's signature is the vector of
{all-true, all-false, mixed} over its examples. Properties are *generated*, not hand-written ("we generate many
random properties", then prune to those that discriminate). The signature feeds a feed-forward net for premise
selection (DeepCoder-style).

(ii) VERIFIED: 185 human-written test programs; 100,000 s per configuration, 3 seeds; baseline solved 28 on
average, with property signatures 73 (abstract: "emit twice as many programs in less than one-tenth of the
time"). Restricted DeepCoder comparison: 16.33 vs 3.33 (random baseline 3).

(iii) Failure modes: signature is an empirical under-approximation; neural consumer; narrow DeepCoder
comparison; day-long budgets.

(iv) PROVEN-RESEARCH for the featurisation (reused in Bustle, CrossBeam — the latter FROM-MEMORY).
(v) Signature computation is ~50 LOC given an evaluator; the consumer could be a lookup table / naive Bayes.
(vi) Relevance: this is the published precedent for *synthesised* features (properties enumerated from the same
language) — directly reusable as the feature grammar for Part 2 guards and for trace statistics.

---------------------------------------------------------------------------------------------------

## 1.8 TF-Coder (Shi, Bieber, Singh; arXiv 2003.09040, TOPLAS 2022)
Source: https://ar5iv.labs.arxiv.org/html/2003.09040

(i) Weighted bottom-up enumeration over TensorFlow ops with hand-assigned integer weights, aggressive
type/shape "operation filtering", and two small models (tensor-features NN; bag-of-words/TF-IDF or naive Bayes on
the task description) that multiply the weight of predicted ops by 0.75.

(ii) VERIFIED: "We manually assigned weights for each of TF-Coder's supported operations." 70 benchmarks, 5-min
limit: 63 solved (39 for the prior Transit algorithm). Ablation: "removing operation weights results in 10 fewer
solved tasks"; "removing operation filtering results in 19 fewer solved tasks"; "two-stage filtering strategy
eliminates 98.6% of all potential candidate programs". Models: without models 61/70, best combination 63/70;
faster on 41 of 61 tasks, slower on 11; 1.78× geometric-mean speedup, 1.59× total.

(iii) Failure modes: tasks needing ≥6 operations out of reach; 5 of 18 human-study examples gave false-positive
solutions (underspecified examples).

(iv) SHIPPED (public Colab tool, Google; usage analysis in the paper). (v) weights table + filters: a few hundred
LOC on a bottom-up enumerator. (vi) Relevance: in the one shipped system with a clean ablation, hand-set weights
(+10 tasks) and validity filters (+19) each outweigh the learned models (+2 tasks, 1.6×).

---------------------------------------------------------------------------------------------------

## 1.9 Bustle (Odena, Shi, Bieber, Singh, Sutton, Dai; ICLR 2021)
Source: https://ar5iv.labs.arxiv.org/html/2007.14381

(i) Bottom-up enumeration where a small MLP, fed property signatures of (inputs→output) and (intermediate
value→output), predicts whether each new value is a sub-expression of a solution; the prediction is binned to an
integer weight offset (0..5). NEURAL but tiny, CPU-only.

(ii) VERIFIED: 38 new benchmarks: Bustle solves 31 "within 30 million candidate expressions or 30 seconds";
model overhead "roughly 20% of the total time"; training data 200,000 examples from 1000 random searches,
"completing in a few hours on CPU". On 89 SyGuS tasks "the handwritten heuristics perform slightly better than
(heuristic-free) Bustle"; model+heuristics is best. DeepCoder-style premise selection "does not lead to more
tasks being solved overall compared to the no-model baseline". Exact per-configuration counts are only in
Fig. 3 — NOT VERIFIED numerically.

(iii) Failure modes: synthetic-training/real-task mismatch; learned model ≈ a handful of hand heuristics in
effect size; Bee Search shows Bustle's 0..5 clamp discards information.

(iv) PROVEN-RESEARCH (re-implemented by Ameen & Lelis; CrossBeam follow-up). (v) non-neural variant: logistic
regression / count table on signatures, ~300 LOC (estimate). (vi) Relevance: confirms that per-*value* reweighting
inside bottom-up search is feasible at 20% overhead, and that simple hand heuristics are a strong baseline.

---------------------------------------------------------------------------------------------------

## 1.10 HeapSearch (Fijalkow, Lagarde, Matricon, Ellis, Ohlmann, Potta; AAAI 2022)
Source: https://arxiv.org/pdf/2110.12485 (text extracted)

(i) Bottom-up enumeration of a PCFG in exact non-increasing probability order, each program once, using per
non-terminal heaps + successor pointers; also SQRT sampling (sample from √p renormalised, loss-optimal sampler).

(ii) VERIFIED: random PCFGs: "Heap Search generates 2.35 times more programs than A*". 137 DreamCoder-derived
tasks, 100 s timeout, 1M-program cap: Heap Search 97 solved, A* 85, Threshold 83. Table 1 programs/s: Heap Search
38,735; Threshold 25,381; DFS 20,281; SQRT 14,020; A* 6,071 — "Heap Search is 6 times faster than A*" (the ar5iv
rendering shows "66", a rendering artefact; the PDF says 6).

(iii) Failure modes: "memory hungry"; no observational-equivalence pruning (Bee Search paper's criticism);
optimality assumes the target is drawn from the PCFG.

(iv) PROVEN-RESEARCH (DeepSynth library; later "Eco Search"/constant-delay variants — FROM-MEMORY).
(v) ~300 LOC. (vi) Relevance: the right enumerator once you have any PCFG, learned or hand-set; a ≤2× effect over
threshold/iterative-deepening enumeration (97 vs 83 tasks), not an order of magnitude.

---------------------------------------------------------------------------------------------------

## 1.11 Bee Search (Ameen & Lelis, JAIR 2023)
Source: https://ar5iv.labs.arxiv.org/html/2310.04327

(i) Best-first bottom-up search over "cost tuples" so that programs are *generated* (not just evaluated) in
exact cost order with real-valued costs, keeping observational-equivalence pruning.

(ii) VERIFIED (120-minute budget per task): 205 SyGuS strings, small DSL: Bee(w_u) 184, Bee(w_Bustle) 182,
Bustle 180, Brute(w_Bustle) 143. Larger DSL: 132 / 123 / 117 / 95. 38 handcrafted (small DSL): Probe and
Bee(w_Probe) 29, Bustle 27. 27 bit-vector: Probe and Bee(w_Probe) 21 (small DSL); larger DSL Probe 13, Heap
Search 8. Non-neural cost w_Probe is one of the two best cost functions overall.

(iii) Failure modes: no gain when the cost function is coarse/uninformative (ties with Probe on small
bit-vector DSL); gains are a few % on small DSLs (184 vs 180).

(iv) SINGLE-PAPER (+ thesis). (v) ~400 LOC. (vi) Relevance: exact best-first ordering matters only for large
primitive sets; rounding to integer costs (Probe) is good enough otherwise.

---------------------------------------------------------------------------------------------------

## 1.12 VSIDS (Chaff — Moskewicz, Madigan, Zhao, Zhang, Malik, DAC 2001)
Source: http://web.stanford.edu/class/cs357/MMZZM01.pdf (text extracted)

(i) VERIFIED verbatim: "(1) Each variable in each polarity has a counter, initialized to 0. (2) When a clause is
added to the database, the counter associated with each literal in the clause is incremented. (3) The
(unassigned) variable and polarity with the highest counter is chosen at each decision. ... (5) Periodically,
all the counters are divided by a constant." I.e. an exponentially decayed count of participation in recent
failures — pure trace statistics.

(ii) Chaff overall: "one to two orders of magnitude performance improvement on difficult SAT benchmarks" vs
GRASP/SATO (whole solver: watched literals + VSIDS + restarts). Isolated effect of VSIDS: see 1.13
(9068 vs 6932 instances).

(iii) Failure modes: Katebi et al.: purely random branching (7325) beat the older static-count heuristic DLIS
(6932) — i.e. a *bad* statistic is worse than none; Biere & Fröhlich SAT 2015 (https://fmv.jku.at/papers/BiereFroehlich-SAT15.pdf, abstract,
VERIFIED): "...VMTF, ACIDS behave very similarly, if implemented carefully" — the exact decay scheme is
second-order; what matters is recency-weighted credit to conflict participants.

(iv) SHIPPED (every CDCL solver). (v) ~50 LOC (bump + decay + heap). (vi) Relevance: the canonical "decayed
conflict counter as branching policy"; needs a notion of *which choices participated in a failure* to credit.

---------------------------------------------------------------------------------------------------

## 1.13 Clause learning and the ablation study (Katebi, Sakallah, Marques-Silva, SAT 2011)
Source: https://ai.dmi.unibas.ch/_files/teaching/fs21/ai/material/ai32-katebi-et-al-sat2011.pdf Table 2 (extracted)

(i) CDCL: on a conflict derive a clause that is the negation of the responsible assignments, add it, and
backjump — "never repeat the same failure". Katebi et al. switch MiniSat features off one at a time.

(ii) VERIFIED Table 2: 10,000 runs (1000 instances × 10 shuffles), 1000 CPU-second limit. Instances solved:
full CDCL 9068; no restarts 8653; no two-watched-literals 8409; no VSIDS (DLIS instead) 6932; no clause
learning 4837. "CL > VSIDS > 2WL > RST." Luby restarts: 4533 SAT + 4535 UNSAT solved vs 4230 + 4423 without.
Random branching (rnd-freq=100) 7325 > DLIS 6932. Note the metric is instances-within-timeout, not a speedup
factor; "orders of magnitude" is a per-instance statement the table does not quantify.

(iii) Failure modes: families differ sharply (termrw: 446 solved without restarts vs 420 with); learned-clause
databases must be garbage-collected (activity/LBD deletion) or propagation cost swamps the benefit — the SAT
form of the utility problem (deletion policy numbers FROM-MEMORY).

(iv) SHIPPED. (v) 1-UIP learning + backjumping ≈ 300–600 LOC (MiniSat core is ~2 kLOC, FROM-MEMORY).
(vi) Relevance: the largest verified single effect of any reflective mechanism here (4837 → 9068), but it needs
a *sound explanation of failure* (resolution). The enumerative-synthesis analogue is Neo/Blaze (1.16–1.17),
which need hand-written component specs to produce the explanation.

---------------------------------------------------------------------------------------------------

## 1.14 Restarts, Luby's universal strategy, heavy tails; phase saving
Sources: https://cs.utexas.edu/~diz/Sub%20Websites/Research/optimal_speedup_of_las_vegas_algorithms.pdf ;
https://www.cs.cornell.edu/gomes/pdf/1998_gomes_aaai_iaai_boosting.pdf ;
https://www.cs.cornell.edu/gomes/pdf/2001_gomes_ai_portfolios.pdf (all text extracted)

(i) Luby, Sinclair, Zuckerman 1993: for a Las Vegas algorithm with unknown run-time distribution, the cutoff
sequence 1,1,2,1,1,2,4,… is universally near-optimal. Gomes/Selman/Kautz 1998: randomise tie-breaking and
restart to cut heavy tails.

(ii) VERIFIED: Luby abstract: "T(A, S_univ) = O(ℓ_A log(ℓ_A)) ... this is the best performance that can be
achieved, up to a constant factor, by any universal strategy" (ℓ_A = expected time of the optimal
distribution-aware strategy). Gomes et al. 1998 Table 1: logistics.d 108 min → 95 s mean; 3bit-adder-32
>24 h → 165 s; round-robin 14: 411 s → 250 s; block-world.d 30 min → 23 min. Abstract: "speedups of several
orders of magnitude for state-of-the-art complete search procedures". In a modern CDCL solver the marginal effect
is small: 9068 vs 8653 (Katebi, above).

(iii) Failure modes: restarts only help if (a) runs are randomised or state is carried over (learned clauses,
activities, saved phases) and (b) run time is heavy-tailed; with a deterministic enumerator and no carried state
a restart is pure waste (Probe's Circuit result is exactly this). Gains range from 1.3× to >500× across instances
in the same table.

Phase saving (Pipatsrisawat & Darwiche, SAT 2007): remember each variable's last polarity across backjumps —
FROM-MEMORY (search quota exhausted before I could open the paper; no numbers offered).

(iv) SHIPPED. (v) Luby sequence: 10 LOC. (vi) Relevance: Luby is the principled answer to "how long to run each
randomised strategy when you know nothing": cost ≤ log factor.

---------------------------------------------------------------------------------------------------

## 1.15 LRB — branching as a multi-armed bandit (Liang, Ganesh, Poupart, Czarnecki, SAT 2016)
Source: https://cs.uwaterloo.ca/~ppoupart/publications/sat/learning-rate-branching-heuristic-SAT.pdf (extracted)

(i) Reward for a variable = fraction of conflicts it participated in while assigned ("learning rate"); estimate
by exponential recency-weighted average (ERWA), plus "reason-side rate" and locality extensions. No NN.

(ii) VERIFIED: 1975 application + hard-combinatorial instances (SAT Competitions 2009–2014), 5000 s each,
MiniSat base: "LRB solves a total of 1279 instances, VSIDS solves a total of 1179 instances, and CHB solves a
total of 1235". ERWA alone 1212; +RSR 1251; +locality 1279. CryptoMiniSat+LRB "solves 59 more instances overall".
DERIVED: +8.5% instances over VSIDS. Context quote they give (Audemard & Simon): "improving a solver by solving
at least ten more instances ... is generally showing a critical new feature."

(iii) Failure modes: improvements are per-family (LRB improved CryptoMiniSat "on 6 of the 8 benchmarks");
later solvers switch between VSIDS and LRB by phase (MapleSAT family — FROM-MEMORY).

(iv) SHIPPED (MapleSAT lineage won SAT Competition tracks — FROM-MEMORY). (v) ~80 LOC over VSIDS.
(vi) Relevance: once a decayed failure counter exists, a principled bandit view buys single-digit percent.

---------------------------------------------------------------------------------------------------

## 1.16 Neo — conflict-driven learning in synthesis (Feng, Martins, Bastani, Dillig, PLDI 2018)
Source: https://www.cs.utexas.edu/~isil/pldi18-neo.pdf (text extracted)

(i) Partial programs are assignments; each component has a first-order *specification* (over-approximate
semantics); when SMT shows a partial program inconsistent with the examples, the unsat core is generalised into
a lemma ruling out every program that replaces a culprit component by one whose spec implies the same clauses
("equivalent modulo conflict").

(ii) VERIFIED. Data wrangling (50 benchmarks, 5-min limit): Neo 90% solved, mean 19 s; Morpheus 64%, 68 s.
Component ablation: baseline DFS 10%; + 2-gram statistical decider 20%; + deduction 70%; + learning 90%.
List domain (100 generated ≥5-component benchmarks): Neo 71%, 99 s; DeepCoder (re-impl.) 32%, 205 s; ablation
22% / 32% (NN decider) / 56% / 71%. Learning on vs off (Neo†): time-outs 10% vs 30% (wrangling), 29% vs 44%
(lists); "Neo is 2.7x faster than Neo† on 'easy' ... 5.7x on the medium ... 19.8x faster ... on 'hard'"; on the
25 benchmarks only Neo solved, 1-hour re-run: average speedup 5.5× / 4.0×, max 17.6× / 14.8×.

(iii) Failure modes / what is supplied: the per-component logical specs are hand-written ("we additionally wrote
first-order" specs for the DeepCoder DSL); needs an SMT solver; lemma store must be pruned; specs that are too
weak give no conflicts. DERIVED observation: the statistical decider alone gives +10 points in both domains;
deduction gives +50 / +24; learning +20 / +15.

(iv) PROVEN-RESEARCH (Neo → Trinity framework, Concord — FROM-MEMORY for the follow-ups). (v) Without SMT: an
abstract-interpretation check (e.g. length/shape/sign domains) + blocking set keyed on (hole, component
equivalence class): ~500 LOC (estimate). (vi) Relevance: the best-measured transplant of CDCL into synthesis;
~4–20× from learning, but only after deduction exists, and deduction needs specs (Part 3 problem).

---------------------------------------------------------------------------------------------------

## 1.17 Blaze — abstraction refinement (Wang, Dillig, Singh, POPL 2018)
Source: https://ar5iv.labs.arxiv.org/html/1710.07740 (evaluation section read)

(i) Build an abstract finite tree automaton from abstract semantics; when the chosen program is spurious,
construct a proof of incorrectness and refine the abstraction with new predicates so that it and many similar
programs disappear.

(ii) VERIFIED. Strings (108 SyGuS PBE): Blaze 90 solved, avg 0.49 s (median 0.14 s); FlashFill 87, 7.66 s;
ENUM-EQ (enumeration + observational equivalence) 54, 4.25 s; CFTA 56, 73.91 s; 363× over CFTA and 16× over
ENUM-EQ on commonly solved; refinement steps avg 74, median 17. Matrix (39): Blaze 39, 3.35 s; Prose 36,
113.13 s; ENUM-EQ 38, 147.88 s; CFTA 27; text factors 90× (Prose), 115× (ENUM-EQ), 262× (CFTA).

(iii) What is supplied: the domain expert must "specif[y] the abstract semantics of each DSL construct" and "a
suitable universe of predicates". Higher per-iteration overhead; bounded program size.

(iv) PROVEN-RESEARCH (Blaze, Atlas, Simba/Yoon et al. — latter FROM-MEMORY). (v) FTA + refinement ~1.5 kLOC
(estimate). (vi) Relevance: the strongest verified speedup over OE-enumeration in this list (16–115×), bought
entirely with hand-supplied abstract semantics; see Part 3 (Atlas) for learning them.

---------------------------------------------------------------------------------------------------

## 1.17b Failure-driven pruning in enumerative synthesis, generally (what is learned vs supplied)

Three verified tiers, in increasing cost and payoff:
 (a) Observational equivalence — "discarding programs that are observationally equivalent to some program that is
     already in the bank" (Probe §2). Learned per task from the examples, no specs needed. It is the 84-vs-44
     baseline of 1.1 and the ENUM-EQ row of 1.17. This is the only failure-memory that needs nothing supplied.
 (b) Type/shape/validity filters — TF-Coder: filters remove "98.6% of all potential candidate programs for a single
     operation"; λ² (Part 3, 3B.3): without type-aware generalisation "more than 60% of the benchmarks do not
     terminate", while hand-written deduction rules give "on average, 6 times faster". Supplied per operator.
 (c) Conflict lemmas / abstraction refinement — Neo 4–20×, Blaze 16–115× (above). Supplied: logical specs or
     abstract semantics per component. Atlas (Part 3, 3B.4) learns the abstract transformers but still needs
     the DSL's logical semantics and an interpolating SMT solver.
CEGIS itself (Solar-Lezama; counterexample inputs accumulated as tests) is FROM-MEMORY here; not re-checked.
I found no verified system that learns tier-(c) lemmas *purely from execution traces* with no supplied
semantics; the nearest are Probe (statistical, not a sound lemma) and Part 2's test-based guard learners.

---------------------------------------------------------------------------------------------------

## 1.18 SATzilla and algorithm portfolios
Sources: https://www.cs.ubc.ca/~hutter/papers/SATzilla.pdf (JAIR 2008, extracted) ;
https://www.cs.ubc.ca/~hutter/papers/cp07-satzilla.pdf ; https://www.cs.cornell.edu/gomes/pdf/2001_gomes_ai_portfolios.pdf

(i) Per-instance algorithm selection: compute cheap instance features, predict log-runtime of each solver with
ridge regression (after forward feature selection and pairwise products), run pre-solvers for a few seconds, then
the predicted-best solver; backup solver if features time out.

(ii) VERIFIED: "we use the same ridge regression method"; feature pool: "Nudelman et al. (2004a) introduced 84
features for SAT instances"; SATzilla07 models ended with "30, 30 and 27 features"; 2007 SAT Competition: "three
gold, one silver and one bronze medal". Gomes & Selman 2001: portfolios/restarts exploit heavy-tailed cost
distributions; a restart strategy "provably eliminates heavy-tailed" behaviour.

(iii) Failure modes: needs hundreds–thousands of training instances with runtimes for every component solver;
feature cost can exceed solve time (hence pre-solvers); selects among whole solvers, not inside one search.

(iv) SHIPPED (competition-winning; later banned/tracked separately — FROM-MEMORY). (v) ridge regression on ~30
features: ~100 LOC; the cost is the training data. (vi) Relevance: the proven non-neural recipe for "which
strategy for this task": linear model on cheap task features + a short universal pre-solve phase.

---------------------------------------------------------------------------------------------------

## 1.19 Levin search and OOPS (Schmidhuber 2002/2004)
Source: https://ar5iv.arxiv.org/html/cs/0207097

(i) Lsearch: in phase i (T doubling) run every program q for at most P(q)·T steps; total cost within a constant
factor 1/P(p) of the fastest solver p. OOPS adds reuse of frozen earlier solutions and self-modifying prefixes.

(ii) VERIFIED: Lsearch's cost is within a constant factor (depending on the prior probability P(p) of the fastest
solver p) of that solver's time; the constant "may be huge but does not depend on k"; "constants beyond 2^500
do not even make sense within this universe"; "in the real world constants do matter". Results: 1^k2^k
language task "roughly 0.3 days on a standard personal computer"; Towers of Hanoi up to 30 disks "within a few
additional days"; learned prefix speeds search by "a factor of 1000". Without the 1^n2^n pre-training task the
system solved Hanoi only up to 3 disks within a week. Initial bias: ~68–73 hand-chosen instructions with
hand-tuned probability boosts.

(iii) Failure modes (author's): "a badly chosen training sequence of intermediate tasks may cost more search
time than required for solving just the final task"; "does not by itself invent an appropriate series of easier
subtasks"; requires resettable environments.

(iv) SINGLE-PAPER/group for OOPS; Levin time-sharing itself is PROVEN-RESEARCH folklore (used as DreamCoder-style
"enumerate in probability order with doubling budget"). (v) ~100 LOC scheduler. (vi) Relevance: gives the
correct accounting (expected cost ∝ runtime / prior probability); it is an allocation rule, not a learner — all
measured gain came from the hand-ordered curriculum.

---------------------------------------------------------------------------------------------------

## 1.20 Iterative deepening / budget doubling cost
Source: https://en.wikipedia.org/wiki/Iterative_deepening_depth-first_search (secondary; Korf 1985 not opened —
search quota exhausted)

VERIFIED (secondary): total expansions Σ_{i=0..d} (d+1−i)·b^i ≤ b^d·(b/(b−1))²; for b=10, d=5 this is 123,456
vs 111,111, "about 11% more nodes"; at b=2 "about twice as long". Doubling a time budget instead of depth costs
≤2× (geometric sum; DERIVED). Luby's universal sequence costs a log factor (1.14).
Maturity SHIPPED. Relevance: re-enumeration from scratch after a policy update (Probe) costs a constant factor
only if each restart at least multiplies reach; with high branching the overhead is ≈ 1/(b−1).

---------------------------------------------------------------------------------------------------

## 1.21 Rational metareasoning (Russell & Wefald 1991) — shipped uses?
Sources: https://ar5iv.arxiv.org/html/1207.5879 (Hay, Russell, Tolpin, Shimony, UAI 2012);
https://aima.eecs.berkeley.edu/~russell/papers/mitecs-metareasoning.pdf (Russell's 1997 MITECS entry, text
extracted)

(i) Choose the computation with highest expected value of computation (VOC) net of its time cost; stop when no
computation has positive VOC.

(ii) VERIFIED (Russell 1997): "The simplest applications of rational metareasoning arise in the context of
anytime algorithms"; applications listed are heuristic search and game-playing (Russell & Wefald), logical
reasoning (Smith 1989), machine learning (Rivest & Sloan 1988) — all research systems. Two remarks directly on
"reflection": simulating object-level computations in order to choose among them "would seem counterproductive,
since simulating a computation ... is just a very slow way of doing the computation itself"; and "Compilation of
metareasoning into more efficient forms is perhaps the principal way in which an agent's computational
performance can improve over time" (he cites Soar's chunking — see 1.22 for what that cost).
VERIFIED (Hay et al. 2012): "UCT applies bandit algorithms to problems that are not bandit problems"; their
VOI-aware root policy reaches "the winning rate of 64% for 10000 samples per ply" against a UCT Pachi on 9×9 Go
(the opponent is "not the most powerful engine of Pachi"); "UCB1 is always considerably worse than the VOI-aware
sampling policies" on 25-arm selection; "At present we have no better proposal for internal nodes than to use
UCT there."

(iii) Candid status: I found NO evidence of a shipped system that computes Russell–Wefald VOC explicitly. UCT/
MCTS — the usual example — is a bandit heuristic that the metareasoning authors themselves call the wrong model.
Anytime-algorithm scheduling with performance profiles (Zilberstein & Russell 1996, cited in the entry as "a
widely applicable methodology") is the nearest to deployed practice; I did not verify any deployment. What
shipped instead are crude proxies: restarts, time-outs, portfolios with learned runtime models (SATzilla).

(iv) SPECULATIVE as an engineering method (PROVEN-RESEARCH as theory). (v) myopic VOC over K strategies with
Beta posteriors on per-unit-time success: ~100 LOC (estimate). (vi) Relevance: use it as accounting vocabulary
(value of a strategy = P(success per unit time)); the measured wins in practice come from much cruder statistics.

---------------------------------------------------------------------------------------------------

## 1.22 Soar chunking and "expensive chunks" (Tambe & Rosenbloom IJCAI 1989; Tambe, Newell, Rosenbloom MLJ 1990)
Source: https://ijcai.org/proceedings/1989/0117.pdf (text extracted; MLJ version paywalled)

(i) Chunking compiles the result of a subgoal into a production so the impasse never recurs. Problem: a learned
production can have a combinatorial match cost.

(ii) VERIFIED: over eight Soar tasks "Learning causes the number of actions required to drop by a factor of
between 5 and 14", yet "for the other four tasks (8-Puzzle, N-Queens, Grid and Magic-Square) the speedup in terms
of total match time is less than 1"; "the time per action for these four tasks increases by as much as a factor
of 25 (for the Magic-Square) ... only five chunks are acquired". Fix: restrict the representation to
"unique-attributes" so match cost is linear: "With the unique-attribute representation, all four tasks speed up,
by factors between 3 and 9", at the cost that "the chunks that are learned may be less general". The original
Laird/Rosenbloom/Newell 1986 chunking paper was NOT opened (FROM-MEMORY for anything about it).

(iii) Failure mode is the finding: fewer search steps ≠ less time; five rules were enough to cause a 25× per-step
slowdown.

(iv) SHIPPED in Soar (that chunking remains in current Soar releases is FROM-MEMORY). (v) n/a. (vi) Relevance: any learned
pruning rule whose *applicability test* is itself a search (pattern match with free variables, sub-enumeration)
can cost more than it saves; bound the match cost by construction.

---------------------------------------------------------------------------------------------------

## 1.23 Minton's utility problem (PRODIGY/EBL, AAAI-88; AIJ 1990)
Source: https://cdn.aaai.org/AAAI/1988/AAAI88-100.pdf (scanned; OCR text layer read — digits may carry OCR error)

(i) Explanation-based learning of search-control rules from the planner's own trace (successes, failures, goal
interactions); rules are compressed, then kept only if their measured utility is positive.

(ii) VERIFIED (OCR): "Utility = (AvrSavings x ApplicFreq) − AvrMatchCost"; "The rule is discarded if its utility
is determined to be negative."
 - Rules surviving: Blocks 328 examples analysed → 69 estimated useful → 19 found useful; STRIPS 588 → 130 → 30;
   Scheduling 946 → 243 → 37. DERIVED: 4–6% of learning episodes yield a kept rule.
 - STRIPS domain: nodes explored 3,992 (hand-coded rules) / 4,038 (learned) / 52,821 (none) — "approximately a
   factor of 13 fewer nodes"; time per node .274 s / .379 s / .098 s. DERIVED: 13× fewer nodes became ≈3.4×
   less time, because each node got ≈3.9× dearer.
 - Unsolved test problems within 80 CPU s (Blocks/STRIPS/Scheduling): hand-coded 0/4/1; learned 7/2/3; no rules
   19/49/32 (OCR; column assignment as printed).
 - Learned rules ran "approximately 50–100% worse ... than with the expert hand-coded rules".
 - Without empirical utility validation: "approximately sixty-five percent poorer"; without the utility estimate
   as well "performance deteriorated so rapidly that the full test phase could not be completed"; with
   compression stages 2–3 off "slightly worse than without learning".
 - Macro-operators: "In some cases, macro-operator learning resulted in overall performance degradation".
 - "the time spent learning was typically of the same order of magnitude as the time spent problem solving".

(iii) The mechanism that controlled it: (a) *measure* each rule's match cost and savings online and delete
negative-utility rules; (b) compress rule conditions to cut match cost; (c) (Soar's answer) restrict
expressiveness so match cost is bounded. All three are needed in Minton's ablation.

(iv) PROVEN-RESEARCH (PRODIGY, Soar, later planners; SAT clause-deletion is the shipped descendant).
(v) per-rule counters (tests, hits, time in test, time saved estimate) + deletion: ~100 LOC.
(vi) Relevance: mandatory instrumentation for any learned-pruning scheme: keep a rule only while
hits × saved-time > tests × test-time, measured, not assumed.

---------------------------------------------------------------------------------------------------

## 1.24 Korf's macro-operators (AAAI-82 precursor of AIJ 1985)
Source: https://cdn.aaai.org/AAAI/1982/AAAI82-039.pdf (scanned; OCR text). The 1985 AIJ paper itself was not
reachable (Columbia mirror blocked automated access).

(i) For serially decomposable puzzles, learn a table of macros indexed by (subgoal, current value) such that
applying one macro per subgoal solves any instance with no search.

(ii) VERIFIED (OCR): Rubik's cube: "entire table contains 238 macros. The lengths of the macros range from one
to sixteen primitive moves"; learning "runs under Unix on a VAX-11/780. The time required to completely fill the
macro table is about 15 minutes, and the memory required is about 200K words." Eight-puzzle table count
(35 macros) is FROM-MEMORY.

(iii) Failure modes: applies only when a fixed subgoal order makes the problem serially decomposable; solutions
are far from optimal; outside that class macros enlarge the branching factor (Minton above: "performance
degradation").

(iv) PROVEN-RESEARCH (macro learning recurs in planning, e.g. Macro-FF — FROM-MEMORY). (v) ~200 LOC for the
table-filling search. (vi) Relevance: library learning (macros) pays when it *removes* search levels; it costs
when it only adds branching — the same tension DreamCoder resolves with MDL.

---------------------------------------------------------------------------------------------------

## PART 1 CONCLUSION — ranked list (mechanism; measured effect; cost; evidence quality)

Ranking is by (size of verified effect) × (evidence quality) ÷ (implementation cost), for an LLM-free,
single-threaded enumerator. Effects are from the sources above; costs are my estimates.

1. Observational-equivalence pruning + size/cost-ordered bottom-up enumeration (the baseline everything else is
   measured against). Effect: size-based 84/140 vs height-based 44/140 at 10 min (Probe §6.2); on Blaze's string
   set ENUM-EQ 54/108. Cost: ~300 LOC. Evidence: PROVEN-RESEARCH, many implementations. *Not learned* — but it
   is the precondition; learned guidance measured against weaker baselines is inflated.
2. Validity/type/shape filters and hand-set operation weights. Effect: −19 and −10 tasks of 63 when removed
   (TF-Coder). Cost: tens of LOC per operator. Evidence: SHIPPED, one clean ablation. Hand-coded, i.e. the thing
   the owner wants to learn — but it is what demonstrably pays.
3. Failure-explanation learning (CDCL-style lemmas / abstraction refinement). Effect: SAT 4837 → 9068 instances
   (clause learning); Neo 4–5.5× average, up to ~20× on hard tasks; Blaze 16–115× over OE-enumeration. Cost: high,
   and it presupposes sound per-component abstract semantics (hand-written in every verified system).
   Evidence: SHIPPED in SAT; PROVEN-RESEARCH in synthesis.
4. Library learning without a neural net (compress solved programs into new primitives, re-weight). Effect:
   Enum 37/4/37% → No-NN EC² 79/43/75% (lists/text/regression); E.C. 3% → ~100% on a synthetic family. Cost:
   high (compression is the hard part), plateau without amortised guidance, needs a multi-task corpus.
   Evidence: PROVEN-RESEARCH.
5. Decayed failure/credit counters as branching order (VSIDS; LRB). Effect: 6932 → 9068 instances (VSIDS vs DLIS);
   LRB +8.5% over VSIDS. Cost: ~50 LOC *given* a conflict analysis that names the participants. Evidence: SHIPPED.
6. Within-task (just-in-time) PCFG re-weighting from partial solutions (Probe). Effect: 84 → 91 of 140 on curated
   grammars; 9 → 25 of 70 on a bloated grammar; slower on tiny grammars. Cost: ~300 LOC. Evidence: SINGLE-PAPER,
   re-implemented once (Bee Search) with the same qualitative result.
7. Cross-task grammar weight re-estimation alone (unigram/PHOG from solved tasks). Effect: +25 / −4 / +1 points
   (EC² "PCFG" column); Euphony 87 → 236 of 405 over EUSolver at 1 h, yet below unguided size-based enumeration
   in Probe's comparison. Cost: ~100 LOC. Evidence: mixed — two papers, contradictory sign.
8. Exact best-first enumerators for a given PCFG (HeapSearch, Bee Search). Effect: 83–85 → 97 of 137 tasks; 6×
   programs/s over A*; a few % over rounded costs on small DSLs. Cost: ~300 LOC. Evidence: PROVEN-RESEARCH.
9. Restarts / Luby / portfolios / per-instance selection. Effect: 8653 → 9068 inside CDCL; up to 10²–10³× on
   heavy-tailed instances with a randomised solver (Gomes et al.); worthless or harmful for a deterministic
   enumerator that carries no state across restarts. Cost: 10–100 LOC + training data for selection.
   Evidence: SHIPPED.
10. Per-task primitive-presence prediction (DeepCoder-style), property-signature premise selection, per-value
    reweighting (Bustle). Effect: 3–60× at low solve fractions on length-3–5 programs, decaying to 2% solved at
    length 14; Bustle ≈ hand heuristics; TF-Coder models +2 tasks, 1.6×. All neural in the literature.
    Evidence: PROVEN-RESEARCH that the effect is modest and baseline-sensitive.
11. Explicit rational metareasoning (VOC). No shipped use found; SPECULATIVE as engineering.

Standing caution (verified, 1.22–1.23): every learned control rule has a match cost. PRODIGY kept 4–6% of what
it learned and was 65% slower without utility validation; five Soar chunks produced a 25× per-step slowdown.
Budget for utility accounting from day one.


===================================================================================================

# PART 2 — Learning guards / preconditions and totality from failures

Fact-check date: 2026-11-24. Method: primary PDFs fetched and converted with `pdftotext`; numbers grepped from the text
(scratch text in `pol/txt2/`). Quotes are verbatim and under 25 words. Tags:

- **VERIFIED** = number/claim read in the primary source at the URL given.
- **ABSTRACT-ONLY** = only the publisher abstract was readable (full text paywalled).
- **FROM-MEMORY** = not checked online in this session.
- **ESTIMATE** = my own inference (all LOC figures are ESTIMATES; no source gives them).

Caveat on coverage: the session's web-search budget ran out part-way through. Everything below was reached by direct URL.
I could not run open-ended searches for 2023–2026 follow-ups, so every "none found" statement is weak evidence of absence.

---

## 2.1 Daikon (Ernst et al.) — template invariants over traces

Sources: Ernst et al., "The Daikon system for dynamic detection of likely invariants", SCP 69 (2007)
https://homes.cs.washington.edu/~mernst/pubs/daikon-tool-scp2007.pdf ;
Daikon manual https://plse.cs.washington.edu/daikon/download/doc/daikon/Enhancing-Daikon-output.html ;
Polikarpova, Ciupa, Meyer ISSTA 2009 abstract https://plse.cs.washington.edu/daikon/pubs/PolikarpovaCM2009-abstract.html

(i) What it does. Instruments a program, records variable values at procedure entry/exit, and checks a fixed grammar of
invariant templates against the trace; whatever is never falsified (and passes a statistical filter) is reported as a
"likely invariant". Positive examples only — there is no notion of a bad run.

(ii) Measured scale / effect (VERIFIED, SCP 2007).
- Template grammar: "Daikon checks for 75 different invariants" plus "derived variables (25 in all)".
- Scale: used on NASA CTAS, which "contains over 1 million lines of C and C++ code" — but "often requires focusing Daikon on a subset of the program".
- Naive generate-and-check "does not scale well"; "the optimizations reduce the number of invariants that need to be checked by 99%".

(iii) Failure modes.
- Unsound by construction: "there is a possibility of overfitting (overgeneralizing) by reporting properties that are true of the training runs but are not true in general" (SCP 2007 §3.4). Mitigation is a null-hypothesis confidence test, not a proof.
- Measured false-positive rate (VERIFIED, Polikarpova et al. ISSTA 2009 abstract; 25 classes, "more than 19500 inferred assertion clauses"): "Around a third of the generated assertions clauses are either incorrect or irrelevant"; and recall against human contracts is partial: "it only finds around 60% of those originally written by programmers".
- Disjunction is weak. Gehr et al. (CAV 2015 §8) tried Daikon for commutativity conditions: "they could only infer rather crude approximations to the target specification".
- Conditional invariants ("splitting") need the splitting predicate to come from somewhere: built-in splitters (which return statement ran; boolean result), a user-written `.spinfo` file, every boolean expression in the source (`CreateSpinfo`), or cluster analysis (`runcluster.pl`) (VERIFIED, Daikon manual). SCP 2007: "The predicates can be produced manually or automatically ... by static analysis of the program or by cluster analysis". Daikon does not synthesise a new predicate when the existing ones fail to separate.
- Nimmer & Ernst 2002 precision/recall figures against ESC/Java: FROM-MEMORY, not checked.

(iv) Maturity: **SHIPPED** (maintained tool, front ends for "C, C++, C#, Eiffel, F#, Java, Perl, and Visual Basic", https://plse.cs.washington.edu/daikon/). Current version number/date not verified.

(v) Smallest sound version. A list of ~10–20 unary/binary templates (x=c, x≤y, x=y+c, x∈{...}, len relations), instantiate over all variable pairs at one program point, delete on first falsifying sample, suppress implied ones. ESTIMATE 200–400 LOC of Lisp. "Sound" here only means "consistent with every sample seen".

(vi) Relevance: the cheapest baseline for learning facts from the kernel's own traces, but positive-only and conjunction-only — it does not learn a guard separating good from bad inputs, and a third of its output was wrong or irrelevant when measured.

---

## 2.2 PIE (Padhi, Sharma, Millstein PLDI 2016) and LoopInvGen

Sources: https://web.cs.ucla.edu/~todd/research/pldi16.pdf ; LoopInvGen tool paper https://arxiv.org/abs/1707.02029 ;
Padhi, Millstein, Nori, Sharma, "Overfitting in Synthesis: Theory and Practice", CAV 2019 https://arxiv.org/abs/1905.07457

(i) What it does. Black-box: run the function on many small inputs, label each test good/bad by the postcondition (e.g. "throws exception"). If two tests have the same feature vector but different labels, no Boolean function over the current features exists, so enumerate (with a cut-down Escher) the smallest new predicate that separates a small "conflict group"; once conflict-free, learn a small k-CNF formula over the features. LoopInvGen wraps this in a CEGIS loop with an SMT verifier to get provably sufficient loop invariants.

Exact mechanism (VERIFIED): "Let a conflict group be a set of tests that induce the same feature vector and that participate in a conflict". The feature learner searches by size for f with f true on all conflicting good tests and false on all conflicting bad tests (Fig. 5). Starts "with no initial features".

(ii) Measured effect (VERIFIED, PLDI 2016 §4).
- Black-box preconditions for OCaml `List`, `String`, `BatAvlTree`: "generates correct preconditions in 87 out of 101 cases". Budget per case: "at most one hour and use up to 8GB of memory". "Correct" = matches English documentation, judged by the authors.
- Sampling regime: "random integers in the range [−4, 4], lists of length at most 5, trees of height at most 5 and strings of length at most 12"; "found 6400 tests and conflict groups of maximum size 16 to provide good results".
- Lazy vs eager features (Table 2, 52 cases): eager enumeration needs min 13 / mean 1611.8 / max 18051 features; PIE selects min 1 / mean 1.5 / max 5.
- Conflict-group size matters: giving all conflicting tests at once costs "11.7 second and 309 MB, as compared to only 1.8 seconds and 66 MB" at size 16, and hits resource limits more often; size 2 over-specialises.
- LoopInvGen: "succeeds in inferring invariants for 43 out of 46 HOLA benchmarks"; "35 out of the 36 ICE benchmarks that require linear arithmetic"; 2 of 3 non-linear; 4 of 4 string benchmarks. Ablation with a pure program-synthesis learner instead of PIE: "succeeds for only 61 out of the 89 benchmarks", averaging "567 seconds and 1895 MB" versus "28 seconds and 128 MB".
- Later (VERIFIED, CAV 2019 paper): a tuned LoopInvGen was "the official winning solver" of the SyGuS-Comp 2018 Inv track; "LoopInvGen solves 115 benchmarks in a total of 2191 seconds whereas LoopInvGen+HE solves 117 benchmarks in 429 seconds".

(iii) Failure modes (VERIFIED).
- Feature grammar gap: of the 14 failures, "The majority (10 out of 14) require universally quantified features, which are not supported by our feature learner".
- Boundary sampling: "we do not infer that String.make(i,c) throws an exception if i is greater than Sys.max_string_length" — small-integer tests never reach the boundary.
- Sample cannot distinguish concepts: lists of primitives "cannot distinguish physical from structural equality" (`List.memq`).
- No control structure in features: the feature learner "does not attempt to infer control structures such as conditionals, loops, and recursion".
- Black-box output is only "likely"; the provably-sufficient variant needs an SMT verifier (two solvers "in parallel for two minutes"), and 3 HOLA failures "run out of memory during PIE's CNF learning phase".
- Grammar size causes overfitting, measured on LoopInvGen (CAV 2019, 180 benchmarks, six grammars, 30-minute timeout): "In 65 % of such pairs, we observe performance degradation with the more expressive grammar"; "adding nonlinear multiplication causes LoopInvGen to fail on 10 benchmarks that it can solve with a less-expressive grammar". The mitigation ("hybrid enumeration" = interleave grammars of increasing expressiveness) is a pure scheduling fix worth "a mean speedup of over 5×".
- Independent replication (Astorga et al. PLDI 2019 §6.2): with features not supplied, Proviso with the PIE learner "takes much longer time and even diverges in some cases".

(iv) Maturity: **PROVEN-RESEARCH**. Open-source tool that won a competition track; the conflict-then-new-predicate idea is re-implemented independently in Alive-Infer (2.8) and plugged into Proviso (2.6).

(v) Smallest sound version. Tests → feature matrix → hash on feature vector to find mixed-label buckets → size-ordered enumeration of boolean expressions over inputs until one splits the bucket → greedy k-CNF (k≤3) cover. ESTIMATE 300–600 LOC on top of an existing enumerator and evaluator; the enumerator is the kernel the owner already has.

(vi) Relevance: this is the closest published match to "run it, observe crashes, synthesise a predicate separating good from bad inputs" with no neural net and no hand-supplied predicates — and its failure list (quantified features, boundary values, grammar-size overfitting) is the list to plan around.

---

## 2.3 ICE learning (Garg, Löding, Madhusudan, Neider CAV 2014) and ICE-DT (POPL 2016)

Sources: https://madhu.cs.illinois.edu/CAV14ice.pdf ; https://madhu.cs.illinois.edu/popl16.pdf

(i) What it does. Reframes invariant learning so that the teacher returns three kinds of sample: positive, negative, and *implication* pairs (if s is in the invariant then s' must be). The learner must find a classifier consistent with all three. CAV 2014 uses a constraint solver over enumerated templates; POPL 2016 adapts ID3-style decision trees so that splits respect implications.

(ii) Measured effect (VERIFIED).
- CAV 2014 Table 1: about 34 small programs (my row count) from SV-COMP loops and the literature, most solved in under 1 s, worst 14.2 s; the tool "learns an adequate invariant for all programs in reasonable time".
- POPL 2016 Table 1 aggregate row: CPAchecker 41/58, randomized search 39/58, ICE-CS (constraint solver) 50/58, ICE-DT-entropy 58/58, ICE-DT-penalty 58/58; timeout 10 minutes. About 80% of programs needed implication counterexamples (text: "∼ 80% of programs").

(iii) Failure modes (VERIFIED).
- Predicate class is hand-supplied: attributes are "octagonal" (±x ± y ≤ c); for the three non-linear programs "we manually ask the learning algorithms ... to learn an invariant over attributes which include ... attributes over non-linear terms".
- Ignoring implications breaks learning: plain ± learning is "inherently non-robust"; naive decision trees with implications produce "large decision trees, and even diverges in the iterative setting".
- Positive/negative-only ML is fragile to the sample: the earlier ML approach "is very sensitive to the test harness used to obtain the set of safe/unsafe program configurations".
- Constraint-solver learner does not scale: ICE-CS "times out or runs out of memory on 6 programs".
- Needs a verifier (Boogie/Z3) as teacher; benchmarks are small intricate loops, not large programs.

(iv) Maturity: **PROVEN-RESEARCH** (two learners by the authors, compared against several independent tools; later Horn-clause variants are FROM-MEMORY).

(v) Smallest sound version. Decision-tree learner over a fixed attribute list, with a union-find or propagation pass that forces both ends of an implication pair onto the same side before a leaf is accepted. ESTIMATE 300–500 LOC excluding the teacher.

(vi) Relevance: when the guard must be *inductive* (true of a recursive call's argument whenever true of the caller's), ± labels are not enough; the kernel's reflective trace can supply implication pairs for free.

---

## 2.4 Sankaranarayanan, Chaudhuri, Ivančić, Gupta ISSTA 2008 — decision trees over predicates from test runs

Source: https://theory.stanford.edu/~srirams/papers/issta2008.pdf

(i) What it does. Given a procedure and a set of predicates over its inputs, enumerate feasible truth assignments to the predicates (SAT + theory solver), generate tests conforming to each, label each assignment safe or buggy by running under valgrind, then fit an ID3 decision tree whose Boolean formula is the likely precondition.

(ii) Measured effect (VERIFIED, §6 and Table 3). 30 C standard-library string functions: "Overall, our tool learns an exact precondition for 28 of the 30 instances". Per truth assignment "we ran ∼ 1000 different tests"; tree learning "≤ 1s"; valgrind "causes a factor of 50 slowdown in our testing".

(iii) Failure modes (VERIFIED).
- Missing predicate gives a safe-but-too-strong guard: for `strcat` it "generates a safe but impermissive precondition due to the missing predicate fwdBnds(p) − strLen(q) − strLen(p) > 0".
- Errors arise from "(a) incompleteness/unsoundness in the testing process, and (b) missing predicate".
- Predicate count explodes: "the number of predicates is large (100s of predicates and beyond)", so complete enumeration is replaced by sampling.
- Naive random strings rarely trigger the interesting cases; they needed a small character pool ("∼ 10" characters) to get coincidences.
- Proposed repair for missing predicates (§7): fit a separating hyperplane to good/bad integer inputs to *discover* a new linear predicate — the earliest instance I found of learning the feature rather than supplying it.

(iv) Maturity: **SINGLE-PAPER** tool; the tree-over-predicates idea itself is PROVEN-RESEARCH (reused in 2.3, 2.6).

(v) Smallest sound version. Fixed predicate list + truth table from tests + ID3. ESTIMATE 150–250 LOC.

(vi) Relevance: establishes the two-stage shape (predicates, then Boolean learner) and documents the main failure — the guard is only as good as the predicate set.

---

## 2.5 Seghir & Kroening, "Counterexample-Guided Precondition Inference" (ESOP 2013)

Source: Springer abstract page https://link.springer.com/chapter/10.1007/978-3-642-37036-6_25 — **ABSTRACT-ONLY** (full text paywalled; author PDF returned HTTP 403).

(i) What it does (from abstract). Extends CEGAR to precondition inference: keep over-approximations of the safe and unsafe input states and refine both with predicates from counterexamples until they are disjoint; the result is "necessary and sufficient for the validity of the assertion". Tool: P-Gen; evaluated on string- and array-manipulating programs.

(ii) Measured effect: **NOT VERIFIED** — no numbers visible on the page.

(iii) Failure modes: not verified from the paper. By construction it is white-box and needs a theorem prover and interpolation-style refinement; it is not a learn-from-runs method. (FROM-MEMORY: refinement may not terminate.)

(iv) Maturity: **SINGLE-PAPER**.

(v) Smallest sound version: not applicable without a symbolic engine; no estimate.

(vi) Relevance: the white-box contrast case — exact (necessary and sufficient) guards are obtainable, but only with symbolic execution the owner's kernel does not have.

---

## 2.6 Astorga, Madhusudan, Saha, Wang, Xie — "Learning stateful preconditions modulo a test generator" (PLDI 2019), tool Proviso

Source: https://par.nsf.gov/servlets/purl/10129745

(i) What it does. Active learning loop for C#: an ID3 decision-tree learner proposes a precondition over primitive parameters and *observer-method* values of the object state; a test generator (Pex, a white-box concolic tool) is asked to refute safety (a failing input the guard admits) and maximality (a passing input the guard rejects); iterate until neither is found. Guarantee is explicitly relative: "ideal" precondition "modulo" the test generator.

(ii) Measured effect (VERIFIED, §6).
- Commutativity conditions: "Out of the 105 commutativity cases, we find that Proviso can learn 73 (∼70%) truly safe and maximal preconditions"; "∼92% of the preconditions learned by Proviso for the commutativity cases are truly safe".
- Exception prevention: of 121 methods, "can learn 105 (∼87%) truly safe and maximal preconditions".
- Cost: "Proviso takes on average ∼740 seconds per method/method pair".
- Notable: it found `number < 1024` for a `toBinary` method ("the constant 1024 is discovered by Proviso") — but via Pex's constraint solving, not random sampling.

(iii) Failure modes (VERIFIED).
- Observer abstraction too weak: for stack `peek()`/`pop()` the needed property "turns out to be not expressible using the available observer methods and the learned precondition is false".
- Missing observer gives a guard that is "neither truly safe nor truly maximal" until `ContainsValueAt(x)` is added by hand.
- A test generator cannot certify positives: the teacher can label "vectors as positive, and later change its mind".
- Random testing is not a good enough teacher: effective with Pex "but not testing tools such as Randoop that generate random inputs".
- Feature learning from scratch is expensive: with PIE's learner and no features it "takes much longer time and even diverges in some cases".

(iv) Maturity: **SINGLE-PAPER** (built on a shipped test generator).

(v) Smallest sound version. Decision tree over (arguments, observer results) + a refutation search that enumerates inputs inside/outside the current guard. ESTIMATE 300–500 LOC; the hard part is the counterexample search, which in an enumerative kernel is exhaustive small-scope enumeration.

(vi) Relevance: the honest statement of what a test-based guard can claim ("safe and maximal modulo a test generator") and the measured gap between that and truth (70–87% truly ideal).

---

## 2.7 Gehr, Dimitrov, Vechev — "Learning Commutativity Specifications" (CAV 2015)

Source: https://files.sri.inf.ethz.ch/website/papers/cav15-learning.pdf

(i) What it does. Purely black-box: sample argument tuples for a method pair, execute both orders, label the tuple commute / not-commute using an abstract equality check, then find a small quantifier-free formula over a fixed fragment (equalities/orderings among arguments and return values) that excludes all negatives and covers as many positives as possible. Three ingredients: type-aware sampling (draw from each "logical type" = cell indistinguishable by the fragment), relevant-predicate discovery, and exhaustive-then-greedy weighted set cover. This is the closest precedent for learning the *condition* under which an algebraic law holds.

(ii) Measured effect (VERIFIED, §7, Fig. 4, "averaged over 8 runs").
- "inferring commutativity specifications for method pairs of 21 data types"; "Our tool inferred the best approximation in all cases".
- Method pairs per type: 3 to 120 (BitList 120, BitTextEditor 36, ArrayList 28).
- Samples drawn to stabilise: 15,000 (most) up to 145,001 (ArrayList) and 105,001 (UnionFind 5); "initial sample size to 5000".
- Time: sampling 35 ms – 2.4 s; formula search 0.06 ms – 710 ms. Largest formula size 19 (BitList), largest disjunct 9.
- Predicate discovery speeds formula search by 1.6× to 43.2× (column "P.d.").
- Type-aware vs random sampling: it "stabilized the inferred formula much earlier (15 000 vs. 75 000 examples)".
- Stopping rule: draw in doubling blocks; "if it produces the same outcome twice in a row, we declare the formula as stable".

(iii) Failure modes (VERIFIED unless tagged).
- The logical fragment is fixed by hand ("we assume a fixed logical fragment") and an abstract state-equality check must be supplied.
- Specifications are *state-independent* approximations; richer state-dependent conditions are out of scope.
- No soundness guarantee — Astorga et al. note these approaches "do not provide any guarantees".
- Competing learners failed on this task: the SVM-style approach was "prone to overfitting, as we observed in our experiments with it"; the stochastic-search approach — "We could not observe the approach terminating when inferring commutativity specifications over five or more variables".
- "Best approximation in all cases" is the authors' own judgement against known specifications; no independent replication found (weak: search budget exhausted).

(iv) Maturity: **SINGLE-PAPER**.

(v) Smallest sound version. Enumerate atoms (a=b, a<b over arguments and results); bucket samples by atom-valuation (the "logical type"); keep buckets that are purely positive; greedy cover of positive buckets by small conjunctions that hit no negative bucket. ESTIMATE 200–400 LOC.

(vi) Relevance: direct template for "law L holds when guard G" — millisecond-scale search once sampling is stratified by predicate cell; the price is a hand-fixed atom vocabulary.

---

## 2.8 Alive-Infer (Menendez & Nagarakatte, PLDI 2017)

Source: https://people.cs.rutgers.edu/~santosh.nagarakatte/papers/pldi2017-alive-infer.pdf

(i) What it does. For an LLVM peephole rewrite with symbolic constants, generate positive examples (constant valuations where the rewrite is valid, checked by SMT) and negative ones; enumerate predicates over the constants until examples are separated; learn a Boolean formula; then ask the SMT solver to validate and return counterexamples. Reports both a weakest precondition and "succinct partial preconditions".

(ii) Measured effect (VERIFIED, abstract/§1/§5.1; 1000-second timeout per optimisation).
- "Out of the 417 optimizations in the Alive suite, there are 174 optimizations that have a precondition."
- "generates the weakest precondition for 133 of them within 1000 seconds"; "either a partial or the weakest precondition for 164 out of the 174".
- "generates a weaker precondition than the precondition in the Alive suite for 73 optimizations".
- Souper patterns: "generalized a total of 71 optimizations"; preconditions for 54.
- Baseline enumerative "Alive-Search": weakest preconditions for 114 of 174; "times out for optimizations that have more than three predicates".
- Predicate-search effort varies by four orders of magnitude (some needed "as many as 104,000" candidate predicates).

(iii) Failure modes (VERIFIED). Of the 41 without a weakest precondition: 31 partial only; "For six optimizations, it was not able to learn sufficient predicates"; "In one case, the Boolean learner failed"; "in three cases Z3 returned unknown". Predicate grammar is domain-specific and hand-written (`isPowerOf2`, `isSignBit`, comparisons over constant expressions). Labels come from an SMT refinement check, not from running code — so the examples are exact, which a test-only setting does not get.

(iv) Maturity: **SINGLE-PAPER** with artifact; a real-world target (LLVM InstCombine), not shipped in LLVM (FROM-MEMORY).

(v) Smallest sound version. Same skeleton as PIE with an exact oracle for labels. ESTIMATE 300–500 LOC plus the oracle.

(vi) Relevance: evidence that guards for *rewrite rules* can be learned from ± examples at the scale of ~170 rules, and that the learned guards were weaker (more general) than expert-written ones in 73 cases.

---

## 2.9 Spyro (Park, D'Antoni, Reps, OOPSLA 2023) — "Synthesizing Specifications"

Source: https://arxiv.org/abs/2301.11117 (PDF text checked)

(i) What it does. Given a query over function symbols and a user-supplied DSL (grammar) of properties, synthesises a set of properties that are sound and *most precise* in the DSL ("best L-conjunction"), using positive examples (real behaviours) and negative examples (must be excluded) in a CEGIS loop with three primitives: Synthesize, CheckSoundness, CheckPrecision.

(ii) Measured effect (VERIFIED, §5).
- "We considered a total of 45 general specification-mining problems"; "synthesized properties for 41/45 benchmarks (45/45 if we consider the 4 benchmarks rewritten using a sketch semantics)".
- SMT back end: "6/10 benchmarks", "less than 6 minutes each", "timed out on the remaining 4"; Sketch back end: "35/35".
- "timeout threshold of 300 seconds for each call".
- DSL sizes: "between 4 thousand and 14.8 trillion properties"; "2-5 orders of magnitude faster than the baseline" (enumerate all sound properties) on large languages.

(iii) Failure modes (VERIFIED). The DSL is hand-designed per benchmark family: "For each set of similar benchmarks, we designed a DSL". Requires a solver (SMT or Sketch) for soundness/precision checks; Sketch gives bounded guarantees only. Timeouts in CheckPrecision mean "best" is not always certified.

(iv) Maturity: **SINGLE-PAPER** (follow-up work by the same group: FROM-MEMORY).

(v) Smallest sound version. Replace the solver with bounded exhaustive testing: enumerate DSL properties by size, keep those true on all sampled behaviours, discard any implied by a kept one. That loses the precision certificate. ESTIMATE 200–300 LOC.

(vi) Relevance: shows the right *objective* for a learned spec (sound and most-precise within a grammar), and that the grammar remains the human's contribution.

---

## 2.10 Speculate (Braquehais & Runciman, Haskell 2017) and QuickSpec's predicates

Sources: https://matela.com.br/speculate.pdf ; Smallbone, Johansson, Claessen, Algehed, "Quick Specifications for the Busy Programmer" (JFP 2017) https://smallbone.se/papers/quickspec2.pdf

(i) What it does. Speculate enumerates expressions by size from user-given functions and constants, partitions them into equivalence classes by testing, and reports equations; then, using only class *representatives*, it conjectures inequalities and conditional equations `c ==> e1 == e2`. Conditions are themselves enumerated Boolean-typed expressions; a digraph of conditions ordered by implication is pruned top-down to find the *weakest* condition under which each candidate equation survives testing.

(ii) Measured effect (VERIFIED).
- Defaults: "considers expressions up to size 5"; "considers conditions up to size 4"; "tests candidate laws for up to 500 value assignments".
- Growth (Table 4, 2 variables): 748 expressions/36 classes at size 5; 16492 expressions/114 classes at size 7.
- Times (Table 6): `(+)`/`abs` defaults 3 s, 4 conditional equations; insertion sort size 7 with conditions to size 6: 1 m 27 s, 12 conditional equations; digraphs size 6: 1 m 52 s, 34 conditional equations.
- vs QuickSpec 2 (Table 9): target law `isIn x t ==> isIn x (insert y t)` needs size 9 and 37 s in QuickSpec 2 vs size 5 and 1 s in Speculate.
- QuickSpec's restriction (Speculate §6): "QuickSpec can generate conditional equations, but only with conditions restricted to applications of a set of declared predicates".
- QuickSpec's own explanation (JFP §3.8): "the sheer number of possibilities of general conditional equations is several orders of magnitudes larger than for unconditional equations", and pruning them "would need full first-order logic reasoning".

(iii) Failure modes (VERIFIED).
- Blow-up: regular-expression example, size 7, 200 tests: "2d 22h 30m 10s" and 6 GB (Table 6).
- Naive pairwise comparison at size 7 would be "over a quarter of a billion pairs of expressions".
- Laws are tested conjectures only (500 or fewer assignments); the tests had to be *reduced* to 200 to make larger sizes feasible, which raises the false-law risk.
- Conditions limited to size 4 by default; a condition that holds on few random inputs is under-tested (QuickSpec addresses this with user generators: "allows the user to specify their own generators"). Sparse-condition bias in Speculate: ESTIMATE/inference, not a quoted finding.
- QuickSpec: "Coming up with the correct condition predicates is not always easy".

(iv) Maturity: **SHIPPED** as Haskell libraries (QuickSpec is PROVEN-RESEARCH with several versions; Speculate's conditional-law algorithm is SINGLE-PAPER evidence).

(v) Smallest sound version. Given equivalence classes already computed by an enumerator: for each pair of representatives that agree on *some* test inputs, enumerate Boolean representatives c up to size 4, keep c if (a) c holds on at least N inputs and (b) e1=e2 on all of them; keep only weakest c. ESTIMATE 150–300 LOC on top of an observational-equivalence enumerator.

(vi) Relevance: the only tool here that enumerates guards for conditional *laws* with no user-supplied predicates and no solver — and its numbers show the ceiling (conditions of size ~4–6, seconds to minutes, days at size 7).

---

## 2.11 Liquid Types (Rondon, Kawaguchi, Jhala PLDI 2008) — what is hand-supplied

Source: https://ranjitjhala.github.io/static/liquid_types.pdf

(i) What it does. Refinement-type inference by predicate abstraction: every unknown refinement is constrained to be a conjunction of instances of *logical qualifiers*; start from the conjunction of all qualifiers and iteratively weaken until all subtyping constraints (discharged by an SMT solver) hold.

(ii) Measured effect (VERIFIED). On the DML array-bounds benchmarks, DSOLVE "reduces the manual annotation required to prove safety from 31% of program text (or 17% by number of lines) to under 1%".

(iii) What is hand-supplied / failure modes (VERIFIED). "Our system takes as input a program and a set of logical qualifiers". A generic bounds-checking set suffices for most programs; otherwise "the programmer typically only needs to specify one or two extra qualifiers"; for the `bitv` library: "extra qualifiers (14 lines, 605 characters)", plus trusted assumptions and interface specifications. Refinements are conjunctions only (no learned disjunction); inference fails when "the set of qualifiers is insufficient" or subtyping is too conservative. Nothing is learned from runs.

(iv) Maturity: **PROVEN-RESEARCH**; descendants are shipped (LiquidHaskell — FROM-MEMORY).

(v) Smallest sound version. Houdini-style: candidate conjunction of all qualifier instances, drop any refuted. With testing instead of SMT this collapses to Daikon (2.1). ESTIMATE 150–300 LOC without the SMT side.

(vi) Relevance: static guards are available cheaply only when a human supplies the qualifier vocabulary — the same dependency as every data-driven method above.

---

## 2.12 How inductive synthesisers handle non-terminating candidates (structural recursion vs timeouts/fuel)

| System | Mechanism | Evidence | Status |
|---|---|---|---|
| Myth (Osera & Zdancewic PLDI 2015) https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf | Syntactic restriction. "A syntactic structural recursion check that enforces that recursive calls are only made on structurally decreasing arguments" plus a positivity restriction on data types. Reason given: "it is easy to generate trivial infinite loops such as fix f (x:t) : t = f x without the check". A 0.25 s timeout exists but bounds an enumeration round, not candidate evaluation. | VERIFIED |
| Escher (Albarghouthi, Gulwani, Kincaid CAV 2013) https://pages.cs.wisc.edu/~aws/papers/cav13a.pdf | Dynamic well-founded check. Values include `err`, denoting "a run-time exception, a type error, or a non-terminating computation"; the recursive call is redefined "so that an error is produced on arguments that are not decreasing, according to the well-founded relation". Crashes and divergence are one ordinary value in the output vector. | VERIFIED |
| SMYTH (Lubin, Collins, Omar, Chugh ICFP 2020) https://arxiv.org/abs/1911.00583 | Follows Myth: "we synthesize only structurally decreasing recursive functions, and we further require that the first argument to a recursive call be structurally decreasing". 38 of 43 Myth tasks; four "did not terminate within 120 seconds" (search time, not candidate divergence). | VERIFIED |
| Burst (Miltner et al. POPL 2022) https://www.cs.utexas.edu/~isil/burst.pdf | Well-founded order on values: "only permitting recursive calls on values that are strictly smaller than the input". Documented cost: "Burst fails on list-rev-tailcall due to our requirement for ensuring termination" — the accumulator call `([2],[1])` is not below `([1;2],[])` in the default order. 43 of 45 from I/O examples. | VERIFIED |
| DreamCoder (Ellis et al. 2021) https://arxiv.org/abs/2006.08381 ; code https://github.com/ellisk42/ec | General recursion via "primitive recursion (the Y combinator)" and a per-example wall-clock timeout. The paper text I could read does not describe candidate-level timeouts (the only hit is search "until timeout"). In the released code, `solvers/task.ml` has `?timeout:(timeout = 0.001)` wrapped in `run_for_interval`, and any other result or exception is `| _ -> false`, i.e. likelihood log 0; Python `Task.check` raises `EvaluationTimeout` and returns False. Units of 0.001 are not stated in that file (seconds: FROM-MEMORY). | VERIFIED in code; paper-level statement NOT FOUND |
| MagicHaskeller (Katayama) https://hackage.haskell.org/package/MagicHaskeller/docs/MagicHaskeller.html | Timeout by default: "time out is taken after 0.02 second since each invocation of evaluation by default"; it "also catches inevitable exceptions like stack space overflow"; and the author warns "setting timeout makes the library referentially untransparent". `forcibleTimeout` is "necessary for interrupting some infinite loops". (Its default library favours total recursion schemes: FROM-MEMORY.) | VERIFIED (docs) |

Summary of the split:
- **Restrict the space** (Myth, SMYTH, Burst, Escher): no divergence can occur, so no timeout is needed and evaluation is deterministic. Cost: programs whose termination argument is not the built-in order are unreachable (Burst's `list-rev-tailcall`; SMYTH's first-argument rule).
- **Run and cut off** (DreamCoder, MagicHaskeller): full recursion, with a short wall-clock limit whose expiry is scored as "wrong". Cost: the search result depends on machine speed (MagicHaskeller says so explicitly), and slow-but-correct candidates are silently discarded.
- None of the six *learns* anything from the cut-off: a timed-out candidate is dropped, not analysed for the input region that caused it.

Maturity of both mechanisms: **PROVEN-RESEARCH** (several independent implementations each).
Smallest sound version: step-counting evaluator with a fuel argument returning a distinguished ⊥ on exhaustion — ESTIMATE 30–80 LOC in an existing interpreter; structural-recursion check — ESTIMATE 50–150 LOC.
Relevance: fuel (step count), not wall-clock time, is the reproducible form of the timeout; and keeping ⊥ as a third label rather than folding it into "wrong" is what the guard learner in the recipe below needs.

---

## 2.13 Nori & Sharma, "Termination proofs from tests" (ESEC/FSE 2013), tool TpT

Source: https://microsoft.com/en-us/research/wp-content/uploads/2016/02/final-version.pdf

(i) What it does. Instrument each loop with a counter, run the test suite, and fit a loop bound (a linear or bounded-degree polynomial in the initial variable values) by constrained regression — literally one quadratic-program call. A safety checker then validates the bound; a failed check yields a counterexample that becomes a new test.

(ii) Measured effect (VERIFIED, Tables 1–3).
- Micro-benchmarks (Table 2): TpT 22 of 27; best prior tools 18 of 27 (hence "15% more benchmarks than any previously known technique"). By group: Oct 6/6, Driver 10/10, Poly 6/11.
- Data needed: "at most 300 randomly selected states ... were sufficient to obtain a sound bound for all our benchmarks"; inputs drawn from −N..N with N between 5 and 20.
- Cost is in validation, not learning: e.g. `fakemodem` (3.1K LOC) infer 0.001 s, validate 2841.7 s; drivers up to 6.5K LOC.
- Rounding of regression coefficients to integers "was performed only in four cases".

(iii) Failure modes (VERIFIED).
- 5 of 11 PolyRank benchmarks FAIL in the infer phase (bound not expressible in the template).
- Disjunctive bounds need input partitioning by predicates, done by hand-coded schemes ("for two benchmarks we performed predicate based splitting"); systematic clustering "is left for future work".
- A slow test is only suspicious: if a run exceeds "a user specified time-out then the loop is classified as 'potentially non-terminating' and the proof fails"; "TpT does not report a certificate of non-termination".
- Soundness comes entirely from the external safety checker.

(iv) Maturity: **SINGLE-PAPER**.

(v) Smallest sound version (unvalidated). Record (inputs, iteration count) pairs; least-squares fit over monomials of degree ≤2 with the constraint prediction ≥ observed; use the fitted bound as the fuel for that function. ESTIMATE 100–200 LOC including a small QP/LP or a max-of-linear fit. Unsound without a checker.

(vi) Relevance: a learned, input-dependent *fuel budget* is a better "is this a timeout?" test than a constant — exceeding the fitted bound by a margin is far stronger evidence of divergence than exceeding a fixed step limit.

---

## 2.14 DynamiTe (Le, Antonopoulos, Fathololumi, Koskinen, Nguyen, OOPSLA 2020)

Source: https://arxiv.org/abs/2010.05747 (PDF text checked)

(i) What it does. Dynamic analysis for both directions: learn ranking functions from terminating traces and *recurrent sets* (a predicate on states from which the loop never exits — i.e. a guard for non-termination) from traces that hit an iteration bound; validate each guess with a static prover; pass counterexamples from one direction to the other as new samples.

(ii) Measured effect (VERIFIED, with an internal inconsistency in the paper).
- Abstract: "we created new sets of 38 terminating and 39 non-terminating programs".
- Introduction: "termination-nla consists of 37 terminating programs and nontermination-nla consists of 38"; "rank functions (in 35 of 37 cases) and recurrent sets (in 33 of 38 cases)".
- §8: "In 34 of the 38 benchmarks, DynamiTe was able to guess ranking functions. The ranking functions derived from 8 of those 32 benchmarks can be validated." And: "Out of the 39 benchmarks, DynamiTe was able to generate a recurrence set for 34 programs."
- The three passages disagree (35/37 vs 34/38; 33/38 vs 34/39; "34" then "those 32"). Safe reading: roughly 34–35 guessed of 37–38, of which only 8 machine-validated; the rest were confirmed by hand ("we manually inspected them").
- For 28 of the non-termination cases "dynamic analysis was actually unnecessary" — the loop condition itself was the recurrent set.
- Linear programs: "DynamiTe is typically an order of magnitude slower" than Ultimate; "The timeout for each benchmark program is 400s".
- Independent measurement (Giacobbe et al. 2022, Table 1): DynamiTe 84 of 124 = 67.7%, lowest of four tools.

(iii) Failure modes (VERIFIED).
- Bounded execution as divergence evidence is unsound: "This transformation is unsound because (i) it does not account for loop body states beyond _bnd".
- Concrete mislabelling: `while(x<1000): x = x + 1` "is wrongly categorized as potentially non-terminating due to the predefined instrumented execution bound (e.g. 500)". Their fix is the counterexample exchange, which needs the static validator.
- Small-input bias: "we usually prefer to generate small random inputs and limit the number of them"; for bound `x < 10000` "the algorithm would require some inputs where x would be larger than or equal to 9500".
- "our non-termination proofs are restricted to only deterministic programs"; "it is not guaranteed that ProveT will terminate".
- Validation is the bottleneck: most learned ranking functions could not be checked by Ultimate/CPAchecker.

(iv) Maturity: **SINGLE-PAPER** (one independent re-run as a baseline).

(v) Smallest sound version (unvalidated). Label traces terminated / hit-fuel; run the guard learner of the recipe over the *initial states* of the two classes to get a candidate "diverges when G(x)"; test G by re-running hit-fuel inputs with 2×, 4×, 8× fuel. ESTIMATE 150–300 LOC given a guard learner.

(vi) Relevance: the nearest precedent for learning *where* a program fails to terminate from run data — and a documented demonstration that a fixed step bound mislabels terminating runs.

---

## 2.15 Urban — piecewise-defined (segmented) ranking functions (SAS 2013; FuncTion)

Source: https://caterinaurban.github.io/pdf/sas2013.pdf

(i) What it does. A static abstract domain (backward analysis) whose elements are piecewise-defined ranking functions: the pieces partition the state space (intervals), each piece carries an affine bound on remaining steps, and the *domain of definition* of the function is a sufficient precondition for termination.

(ii) Measured effect. Abstract (VERIFIED): the domain "automatically synthesizes piecewise-defined ranking functions and infers sufficient conditions for program termination"; a "research prototype static analyzer, for a small imperative language, that yielded interesting preliminary results". **No benchmark counts in this paper.** FuncTion's later competition results: FROM-MEMORY, not checked.

(iii) Failure modes (VERIFIED, §6). "the implemented domain has a limited expressiveness that translates into an imprecision of the analysis especially in the case of nested loops (and, in general, of programs with non-linear complexity)". Static, needs program text and widening; nothing is learned from runs.

(iv) Maturity: **SINGLE-PAPER** line from one group with a tool (PROVEN-RESEARCH status not established here).

(v) Smallest sound version: an interval × affine backward analyser — not small. ESTIMATE >1000 LOC. Not a candidate for a first implementation.

(vi) Relevance: shows the right *output shape* for a totality guard — a partial step-bound function whose domain is the guard — which a data-driven learner could aim to produce (2.13 + a guard for the domain).

---

## 2.16 Giacobbe, Kroening, Parsert — "Neural Termination Analysis" (ESEC/FSE 2022), tool νTerm — for contrast

Source: https://arxiv.org/abs/2102.03824 (PDF text checked)

(i) What it does. Train a very small neural network on sampled traces so that its output decreases along every observed transition, then verify with an SMT solver that it is a ranking function for all executions.

(ii) Measured effect (VERIFIED, Table 1 and §Experiments). 124 problems (72 term-crafted, 38 Aprove_09, 14 added by the authors). νTerm "proves termination for 97.2 out of 124 problems on average (100 in the best out of the five runs), which accounts for 78.4%"; AProVE 81.4%, Ultimate 77.4%, DynamiTe 67.7%. Configuration: "a neural network consisting of 7 neurons with 1000 sample traces with a maximum length of 1000"; "timeout of 60 seconds for each problem".

(iii) Failure modes (VERIFIED). Overfitting to traces when loops are short or branches rare ("may lead to overfitting of the networks to the sampled traces"); large constants: `while (x < 10000000) x++` "would require complete traces ... which take a long time to gather"; parity-dependent ranking functions are not expressible; benchmark selection excludes programs with more than two nested loops or function calls; its advantage is concentrated on the 14 author-written problems (92.9% vs 7.8–50% for others), while on term-crafted it is behind Ultimate (68.9% vs 84.5%).

(iv) Maturity: **SINGLE-PAPER**.

(v) Smallest sound version: not applicable (needs gradient training and an SMT verifier). A 7-neuron model is small enough that a non-neural template search (max of a few affine functions) is the obvious substitute — ESTIMATE, not tested by the paper.

(vi) Relevance: the "learning" needed for ranking functions is tiny (7 neurons, 1000 traces); the hard part is verification and trace coverage, not model capacity.

---

## 2.17 Conditional termination — Cook, Gulwani, Lev-Ami, Rybalchenko, Sagiv (CAV 2008), and learning a guard for the set of inputs on which a program terminates

Sources: Springer abstract https://link.springer.com/chapter/10.1007/978-3-540-70545-1_32 (**ABSTRACT-ONLY**);
Le, Qin, Chin PLDI 2015 abstract via https://api.semanticscholar.org/graph/v1/paper/DOI:10.1145/2737924.2737993 (**ABSTRACT-ONLY**)

(i) What it does. Cook et al. describe "synthesizing reasonable underapproximations to weakest preconditions for termination": guess a candidate ranking function, compute the condition under which it actually decreases and is bounded, and use that condition as a termination precondition (the guess-then-derive-condition detail is FROM-MEMORY; Urban's related-work section confirms the direction: "a method based on preconditions generating valid ranking functions").

(ii) Measured effect: **NOT VERIFIED** — abstract says only that it "provides experimental evidence".

(iii) Failure modes: static, symbolic (needs a constraint solver / quantifier elimination — FROM-MEMORY); under-approximates, so inputs outside the guard are *unknown*, not divergent.

(iv) Maturity: **PROVEN-RESEARCH** for static conditional termination as a topic (Cook 2008; Urban 2013; Le/Qin/Chin PLDI 2015, whose abstract says it derives "conditional termination and non-termination specifications" per method — all static). **For learning the terminating-input guard purely from run data: effectively SINGLE-PAPER (DynamiTe, and only for the non-termination side, with a static validator).**

(v) Smallest sound version: none that is sound without a prover. The unsound data-driven version is the recipe below with label "exhausted fuel".

(vi) Relevance: I found **no verified work that learns a termination guard from timeout-labelled samples alone inside a program synthesiser**. Closest: DynamiTe (2.14, recurrent sets from bounded traces + validator), TpT (2.13, loop bounds from tests + validator), PIE-style precondition inference (2.2) applied to an "exception" label, and Escher's `err` value (2.12). Weak negative: the search budget was exhausted before I could look for 2023–2026 work.

---

## 2.18 How reliable are timeouts as evidence of non-termination?

All VERIFIED quotes are repeated from the entries above.

- No tool that *proves* anything accepts a timeout as non-termination. TpT: exceeding the limit makes the loop "potentially non-terminating" and "the proof fails"; it "does not report a certificate of non-termination". DynamiTe calls its own bounded-execution transformation "unsound".
- Measured mislabelling exists even on one-line loops: DynamiTe's `while(x<1000): x = x + 1` with bound 500 is "wrongly categorized as potentially non-terminating". νTerm reports the dual problem — a terminating loop to 10,000,000 cannot be sampled to completion.
- Wall-clock limits make search irreproducible: MagicHaskeller — "setting timeout makes the library referentially untransparent".
- Synthesisers that use short limits (DreamCoder code: 0.001 per example; MagicHaskeller: 0.02 s) treat expiry as "candidate is wrong". That is safe for *rejecting candidates* (a false "diverges" only loses a slow program) but is not evidence about the input.
- I found **no measured false-positive rate** for "timeout ⇒ diverges" in the synthesis literature (NOT FOUND; weak, search budget exhausted).

Practical reading (inference, not a quoted result): a step-count budget is deterministic and therefore usable as a label; treat exhaustion as a third outcome; before calling an input "bad", re-run with geometrically larger fuel, or compare against a learned input-dependent bound (2.13). The label is still a conjecture.

---

## CONCLUSION — the standard recipe, and its known failure modes

### The recipe ("run it, observe crashes/timeouts, synthesise a predicate separating good from bad inputs")

This is the common skeleton of Sankaranarayanan 2008, PIE 2016, Gehr 2015, Alive-Infer 2017 and Proviso 2019. Steps 4–5 are PIE's contribution; step 2's stratification is Gehr's and Sankaranarayanan's; step 7 is Proviso's/Alive-Infer's; step 8 is ICE.

1. **Define the outcome label.** Run the candidate on input x inside a total evaluator: catch every crash, count steps. Label ∈ {good, crash, fuel-exhausted}. (Escher folds exception, type error and non-termination into one `err` value; keep them distinguishable if the guard should explain which.)
2. **Sample inputs from a small scope, stratified.** Many inputs over a small domain (PIE: integers in [−4,4], lists ≤5, 6400 tests). Stratify by predicate cell so that rare cells are populated (Gehr's type-aware sampling: 15,000 vs 75,000 samples to stabilise; Sankaranarayanan: ~1000 tests per feasible truth assignment). Add boundary values deliberately.
3. **Start with a small (possibly empty) predicate set** over the inputs and cheap observers (length, sign, emptiness, equality/order between arguments).
4. **Find conflicts.** Hash each sample on its feature vector; a bucket containing both good and bad samples proves no Boolean function over the current predicates can be the guard.
5. **Resolve a conflict by synthesising one new predicate.** Enumerate Boolean expressions by size until one is true on the bucket's good samples and false on its bad ones. Use a bounded conflict group (PIE: 16) — 2 over-specialises, "all" forces the enumerator to find the whole guard.
6. **Learn the Boolean combination with an Occam bias.** Smallest k-CNF (PIE), greedy weighted set cover over cells (Gehr), or an entropy-split decision tree (Sankaranarayanan, ICE-DT, Proviso).
7. **Attack the guard, then repeat.** Search specifically for (a) a bad input the guard admits and (b) a good input it rejects; add them and go to 4. Stop when the guard is stable across a doubled sample (Gehr: same result "twice in a row") or the refuter finds nothing (Proviso). With a verifier this is CEGIS and gives a sufficient precondition (LoopInvGen); without one the claim is "safe and maximal modulo the test generator".
8. **If the guard must be inductive** (hold on recursive calls / loop iterations), feed implication pairs (s ⇒ s′) to the learner, not only ± labels (ICE).
9. **For fuel-exhausted labels**, re-run with larger fuel before treating them as bad; optionally fit an input-dependent step bound from the terminating runs (TpT) and use "exceeds bound × margin" as the label.
10. **Record the guard as a conjecture** with its sample and scope, and re-test it when the sampler or grammar changes.

### Known failure modes (each tied to a measurement above)

- **Overfitting the sample.** Daikon: about a third of inferred clauses incorrect or irrelevant. ICE authors: ± ML learning "very sensitive to the test harness". Proviso: only 70% (commutativity) / 87% (exceptions) of guards truly safe and maximal even with a concolic teacher.
- **The predicate grammar is the real input.** Every system needs one: Daikon's 75 templates, ICE's octagons, Gehr's fixed fragment, Alive-Infer's domain predicates, Spyro's per-family DSL, Liquid Types' qualifiers, QuickSpec's declared predicates. A missing predicate gives a guard that is safe but too strong (`strcat`), or `false` (Proviso `peek`/`pop`), or failure (PIE: 10 of 14 failures needed quantified features).
- **A bigger grammar is not a fix.** LoopInvGen degraded in 65% of benchmark/grammar pairs when the grammar grew; Speculate needed days at expression size 7. Interleaving grammars of increasing size recovered a 5× mean speedup.
- **Boundary sampling.** Small-scope inputs miss large thresholds (PIE: `Sys.max_string_length`; νTerm: 10,000,000; DynamiTe: needs inputs ≥ 9500). Proviso found `number < 1024` only because Pex solves path constraints.
- **Rare cells.** Random sampling under-populates cells with coincidences (equal arguments, special terminators); both Sankaranarayanan and Gehr had to engineer the sampler.
- **Weak observers / state abstraction.** Guards over object state are limited to what observer functions expose (Proviso).
- **Disjunction.** Conjunctive template learners (Daikon, Liquid Types, Houdini-style) cannot express guards that are disjunctive; commutativity conditions are ("disjunctions abound").
- **Timeout labels are not facts.** A fixed bound mislabels terminating runs (DynamiTe's bound-500 example); wall-clock limits are machine-dependent (MagicHaskeller).
- **Cost concentrates in checking, not learning.** TpT: 0.001 s to infer vs up to 2841.7 s to validate; Proviso ~740 s per method; Alive-Infer 1000 s budgets; DynamiTe validated only 8 of ~34 guessed ranking functions.
- **No guarantee without a verifier.** Black-box results are "likely" (Daikon), "modulo a test generator" (Proviso), or carry no guarantee (Gehr, Sankaranarayanan, per Astorga et al.).

### What I could not verify (Part 2)

- Seghir & Kroening ESOP 2013: abstract only; no evaluation numbers.
- Cook et al. CAV 2008: abstract only; algorithm details and experiments are FROM-MEMORY.
- Urban/FuncTion: no benchmark numbers (the SAS 2013 paper gives none); competition results FROM-MEMORY.
- Daikon: current release/version; Nimmer & Ernst precision/recall figures.
- DreamCoder: no paper-level statement of per-candidate timeouts found; verified only in repository source; units of `0.001` not confirmed.
- DynamiTe: the paper's own counts are mutually inconsistent (see 2.14).
- Le/Qin/Chin PLDI 2015: abstract only, via a bibliographic API summary.
- LiquidHaskell shipping status, Spyro follow-ups, Horn-ICE variants, MagicHaskeller's default library: FROM-MEMORY.
- All LOC figures are my ESTIMATES.
- Absence claims ("no work learns a termination guard from timeouts alone"; "no measured false-positive rate for timeout ⇒ diverges") rest on direct-URL reading only; open-ended search was cut off by the session search budget.


===================================================================================================

# PART 3 — Inverse / solver / propagator discovery (fact-check notes)

Date of check: 2026-11-24. Tags: **VERIFIED** = read in a primary source this session (URL + quote/table given);
**SNIPPET** = seen only in a search-result summary or third-party record; **FROM-MEMORY** = not verified online.
Caveat on method: the shared WebSearch budget ran out part-way through this slice. After that only direct fetches of
already-known URLs were possible, so the 2023-2026 "learned inverse semantics" sweep is narrower than intended (see
"Could not verify" at the end). Local text extracts are under `.../lit-search/pol/txt3/`.

Maturity tags: SHIPPED / PROVEN-RESEARCH / SINGLE-PAPER / SPECULATIVE.

---

## 3A. Program inversion proper

### 3A.1 Universal Resolving Algorithm (Abramov & Glück, MPC 2000; SCP 43(2-3) 2002)
- (i) What: an *inverse interpreter* for a first-order functional language (TSG, a typed S-Graph dialect). Given program p
  and output y it enumerates inputs x with p(x)=y by building a "perfect process tree" (driving with positive and
  negative constraints on a partially-known input) and walking it breadth-first. No inverse program is produced.
- (ii) Measured: abstract only. VERIFIED abstract (Semantic Scholar record for DOI 10.1016/S0167-6423(02)00023-0,
  https://api.semanticscholar.org/graph/v1/paper/DOI:10.1016/S0167-6423(02)00023-0?fields=abstract ): "sound and
  complete, and computes each solution for which the given program terminates, in finite time"; implemented for TSG;
  "remarkable results for the inverse computation of ... a pattern matcher and an interpreter for imperative programs".
  No timing table could be read (Elsevier and Springer copies returned 403 / login redirect).
- (iii) Failure modes: (a) it is a semi-decision procedure — each solution appears in finite time but the search need
  not *stop* (FROM-MEMORY: terminates only when the process tree is finite); (b) SNIPPET (abstract of the 2006/07
  follow-up, Abramov/Glück/Klimov, DOI 10.1007/978-3-540-70881-0_6): URA "was originally formulated for inverse
  computation of tail-recursive programs"; the extension to general recursion "improves the efficiency and
  termination" by using partially produced output — i.e. the original wastes work on non-tail-recursive code;
  (c) cost is that of exhaustive symbolic search per query, paid again for every output (FROM-MEMORY).
- (iv) Maturity: PROVEN-RESEARCH as a concept (it is essentially narrowing; functional-logic languages such as Curry
  and miniKanren do the same job); the URA implementation itself is a single group's research code.
- (v) Smallest sound version: a driving/narrowing interpreter for a first-order language with constructor patterns,
  breadth-first or interleaved. A few hundred LOC (FROM-MEMORY estimate; miniKanren core is famously < 100 LOC, the
  relational interpreter on top a few hundred).
- (vi) Relevance: the *sound and complete* baseline for "run f backwards"; useful as an oracle for small outputs, not
  as a way to obtain a fast reusable inverse.

### 3A.2 Dijkstra / Gries hand inversion
- (i) What: invert an imperative program statement by statement, reading it backwards, swapping guards and
  post-assertions. Dijkstra, EWD 671 "Program inversion".
- (ii) Measured: none (it is a derivation technique). VERIFIED (transcription
  https://www.cs.utexas.edu/~EWD/transcriptions/EWD06xx/EWD671.html ): statement pairs such as "y:hiext(j) and
  j,y:hipop are each other's inverse"; for deterministic programs "the inversion is a straightforward process".
  The worked example is the permutation/inversion-count program, which PINS reuses as benchmark "Permute count".
- (iii) Failure modes: works only when each statement has an inverse and the postcondition of each branch/loop
  determines which branch was taken; anything that discards information is not invertible this way.
- (iv) Maturity: textbook technique (Gries, *The Science of Programming*, ch. 21 — FROM-MEMORY citation); it is the
  semantics of Janus (below), so in that sense SHIPPED as a language design.
- (v) Smallest sound version: a table op -> inverse-op plus "reverse the sequence, swap test and assertion". ~100 LOC.
- (vi) Relevance: the cheapest route when the forward function is written from invertible primitives; it requires the
  per-primitive inverse table to be *supplied*.

### 3A.3 Glück & Kawabe: LR-based program inverter (APLAS 2003, FLOPS 2004, PADL 2005 "LRinv")
- (i) What: a *program inverter* (produces g = f^-1 as a program, once). Translate a first-order functional program
  to a stack-machine "grammar language", invert each operation locally and reverse each sequence, then remove the
  resulting nondeterminism with LR(0) parsing techniques (left-factoring etc.), translate back.
- (ii) Measured: VERIFIED from the authors' 2006 Dagstuhl slides
  (https://mw.hh.se/wg211/images/f/f4/RG-slides-Dagstuhl060127.pdf ): four steps "1. Translation to grammar language.
  2. Local inversion. 3. Elimination of nondeterminism. 4. Translation to source language."; worked examples are
  binary increment -> decrement and tail-recursive reverse. No benchmark table with times was available to me
  (Springer chapters are paywalled); FROM-MEMORY: the papers show a dozen or so small list/number programs
  (e.g. run-length encoding, pack/unpack, tree traversals) — sizes of ~10 lines each.
- (iii) Failure modes (VERIFIED, same slides): input programs must be "well-formed for inversion" — "Programs that
  never discard values"; and "As in PE, some programs invert well, others don't." The method applies to *injective*
  programs; when the inverted grammar has LR conflicts no deterministic inverse is produced (FROM-MEMORY).
- (iv) Maturity: SINGLE-GROUP research (a few related inverters exist: Matsuda et al.'s grammar-based inversion,
  Nishida's term-rewriting inversion — FROM-MEMORY).
- (v) Smallest sound version: local inversion + backtracking execution of the nondeterministic inverse (skip step 3);
  that is sound and small (~200-300 LOC) but may be exponentially slow. Step 3 (LR(0) item sets) is the expensive part.
- (vi) Relevance: the most direct deterministic route *if* the kernel's primitives each have an inverse in the
  language and programs are linear (no value discarded/duplicated). It is a transformation, not a learner.

### 3A.4 Janus and reversible languages
- (i) What: a language in which every statement is locally invertible, so every procedure can be `uncall`ed.
- (ii) Measured: none relevant. VERIFIED (Wikipedia,
  https://en.wikipedia.org/wiki/Janus_(time-reversible_computing_programming_language) ): "written at Caltech in 1982";
  2007 formalisation "together with a program inverter and an invertible self-interpreter" (Yokoyama & Glück);
  on inversion "the assertion becomes the test, and the test becomes the assertion".
- (iii) Failure modes / restrictions (VERIFIED, same page): only reversible updates (+=, -=, ^=, swap); the assigned
  variable may not occur on the right-hand side; conditionals and loops need a programmer-written exit assertion;
  no heap allocation. The burden of injectivity is moved to the programmer.
- (iv) Maturity: PROVEN-RESEARCH (several implementations and successor languages, e.g. RFun, Jeopardy — FROM-MEMORY).
- (v) Smallest sound version: interpreter with forward/backward modes, ~300 LOC.
- (vi) Relevance: shows what a kernel needs so that inverses come for free: an inverse per primitive, linearity, and
  explicit exit assertions (which are exactly the "guards" of Part 2).

### 3A.5 miniKanren "run it backwards" (Byrd, Ballantyne, Rosenblatt, Might, ICFP 2017)
- (i) What: write the interpreter as a relation `evalo`; put logic variables in the program, input or output position;
  interleaving complete search fills them in. One mechanism gives inverse evaluation, example-based synthesis and
  refutation.
- (ii) Measured — VERIFIED from the paper text
  (https://www.cs.tufts.edu/~nr/cs257/archive/william-byrd/kanren-solving-pearl.pdf ):
  - "a run 100 query finds 100 in 1.7 seconds on an early 2013 MacBook Pro" (programs that return 137 under dynamic
    and 42 under lexical scope);
  - quine generation through the meta-circular evaluator: "this query takes 5 minutes with our current hardware";
  - with the unoptimised `evalo` "only small parts of append can be synthesized in a reasonable amount of time";
    after goal-reordering optimisations the whole body of `append` is synthesised from 4 example calls.
- (iii) Failure modes — VERIFIED quotes: "The search space grows exponentially with the size of the smallest correct
  definition ... Our current implementation can't synthesize complete recursive programs much larger than append.";
  "The thrines-generating query may not find a thrine before running out of memory"; a goal-order change makes a
  query "very slow" because it "spends most of its time evaluating non-terminating programs"; `run*` on an
  inverse-append query "never returns a result" because infinitely many expressions denote the same value.
  Constants from the examples must be explicitly forbidden (`absento`) or the search returns the examples verbatim.
- (iv) Maturity: PROVEN-RESEARCH (many miniKanren implementations; Barliman demo). Not a shipped synthesis tool.
- (v) Smallest sound version: microKanren (~50-100 LOC, FROM-MEMORY) + relational interpreter (few hundred LOC).
  The engineering cost is in goal ordering, not in size.
- (vi) Relevance: confirms that generic backwards execution gives inverses of *values* cheaply but does not scale past
  `append`-sized program synthesis; interleaving tolerates non-termination but can starve.

### 3A.6 PINS (Srivastava, Gulwani, Chaudhuri, Foster, PLDI 2011)
- (i) What: semi-automatic inversion of imperative programs. From P and a *template* for P^-1 (control-flow skeleton
  with holes + candidate sets of expressions and predicates), symbolically execute chosen paths through P;P^-1 and
  use SMT/SAT to prune template instantiations until few remain.
- (ii) Measured — VERIFIED (https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/pldi11-inverse-synthesis.pdf ):
  - "invert 14 small but complex programs ranging in size from 5 to 25 lines of code" (compressors, encoders,
    arithmetic); Table 2 times: 1.07 s (sum-of-i) ... 1810.31 s (LZ77), 1376.82 s (Base64); "ranging from 1 second to
    30 minutes"; search spaces of 2^3 .. 2^37 instantiations reduced to 1-4 candidates;
  - "In 11 cases, PINS produced 1 candidate inverse, which was correct. In the remaining 3 cases ... at most 4";
  - "between 1 and 14 paths, with a median of 5 paths";
  - Sketch on the same templates: runnable on 6, "synthesize an inverse for 5 out of the 6" (Table 3), after
    bounding arrays to length 4.
- What the user supplies (VERIFIED): the template — "it is still up to a human to identify the final template";
  Table 1 shows mined candidate sets of 7-20 items cut down by hand and 0-4 manual modifications per benchmark;
  axioms for library functions ("8 of 14 benchmarks use library calls"; LZW needed 15 axioms). The inverse template
  usually has "the same shape as the original program".
- (iii) Failure modes — VERIFIED: "PINS does not guarantee their correctness" (only explored paths are checked);
  CBMC validation possible for only "6 of the 14"; "Scalability is clearly a challenge"; "Another challenge is the
  need to discover templates"; many-to-one programs are future work.
- (iv) Maturity: SINGLE-PAPER (the template/sketch idea itself is PROVEN-RESEARCH via Sketch).
- (v) Smallest sound version: needs a symbolic executor + SMT solver; not small. The portable idea — mine the inverse's
  vocabulary from the forward program text and keep the forward control skeleton — costs almost nothing.
- (vi) Relevance: the best-measured "search for an inverse" result, and it tops out at 25-line programs, minutes of
  SMT time, and a human-edited template.

### 3A.7 Hu & D'Antoni, "Automatic program inversion using symbolic transducers" (PLDI 2017), tool GENIC
- (i) What: model a list/string program as a symbolic extended finite transducer; show injectivity checking is
  undecidable in general and give an algorithm for a restricted class; invert transition by transition, each
  transition inverse being found by a SyGuS solver.
- (ii) Measured — VERIFIED from the abstract only
  (https://pldi17.sigplan.org/details/pldi-2017-papers/51/Automatic-Program-Inversion-using-Symbolic-Transducers ):
  can "invert 13 out 14 real complex string encoders and decoders", producing inverses "substantially identical to
  manually written ones". Per-benchmark times and sizes: NOT VERIFIED (paper is closed access; no open copy found).
- (iii) Failure modes: injectivity undecidable for the general class (VERIFIED, abstract and the CAV'17 tutorial by
  D'Antoni & Veanes, https://cseweb.ucsd.edu/~ldantoni/papers/cav17-tutorial ); 1 of 14 not inverted; restricted to
  finite-state, bounded-lookahead programs (FROM-MEMORY).
- (iv) Maturity: SINGLE-PAPER.
- (v) Smallest sound version: per-rule inversion — for each rewrite rule "guard(x) -> out = t(x)", synthesise t^-1 and
  the image guard by enumeration, check round trip. This decomposition (invert each *case* separately, then check the
  images of the cases are disjoint) is the transferable part. ~300 LOC plus an enumerator (estimate).
- (vi) Relevance: strongest evidence that "decompose into guarded cases, enumerate a small inverse per case, verify"
  works on real encoders (Base64/UTF-style), with injectivity = disjointness of case images.

### 3A.8 Bidirectional program synthesis: Synbit (Yamaguchi, Matsuda, David, Wang, OOPSLA 2021) and Optician (Miltner et al., POPL 2018)
- (i) What: Synbit takes a unidirectional `get` program plus a few (source, updated view, updated source) examples,
  uses `get` as a *sketch* for a bidirectional HOBiT program and fills holes, pruning by lens laws. Optician
  synthesises bijective string lenses from two regular expressions (the two formats) plus optional examples.
- (ii) Measured — VERIFIED via ar5iv (https://ar5iv.labs.arxiv.org/html/2108.13783 ): Table 1, 15 microbenchmarks,
  13 solved in 0.016 s - 5.6 s; "Any case running longer than 10 minutes was reported as a timeout" (2 timeouts:
  `lines`, `lookup`); "Synbit successfully synthesized 13 out of 15 cases, whereas Smyth succeeded only in 7 cases";
  larger cases: 6 XML queries in 0.14-10.0 s (Table 4), a lexer in 0.094 s and a parser in 0.55 s (Table 5).
  Optician (https://ar5iv.labs.arxiv.org/html/1710.03248 ): "a benchmark suite of 39 examples"; "succeeds on all
  benchmarks in under 5 seconds"; Flash Fill "was only able to complete synthesis of 3 out of 39".
- (iii) Failure modes — VERIFIED (Synbit): "our proposed method is incomplete" — the two timeouts are cases whose
  `put` does not follow the recursion structure of `get`; `reverse` needed an extra length parameter; the lexer and
  parser are injective, "which is uncommon in practice". Optician: bijections only; the user must write both regexes.
- (iv) Maturity: SINGLE-PAPER each; lenses as a field are PROVEN-RESEARCH (Boomerang, Augeas).
- (v) Smallest sound version: "reuse the forward program's recursion skeleton as the sketch for the backward one,
  enumerate hole fillers, test the round-trip laws on examples" — same idea as PINS' template, functional setting.
- (vi) Relevance: the closest functional-language demonstration of enumerate-and-test inverse search; its speed comes
  from the forward program's skeleton, and it fails exactly when the inverse needs a different recursion shape.

### 3A.9 Other (context only)
- Teegen, "Implementing Functional Patterns by Synthesizing Inverse Functions" (ICLP 2020 research summary,
  https://arxiv.org/abs/2009.10254 , VERIFIED abstract): aims at "the synthesis of the inverse of any given function in
  Curry itself"; direct derivation only for rules without extra variables / non-linear right-hand sides. No numbers.
- Semantic bidirectionalisation (Voigtländer POPL 2009), view-complement derivation (Matsuda et al. ICFP 2007),
  weak right inverses for parallelisation (Morita et al. PLDI 2007): FROM-MEMORY, not checked.

---

## 3B. Inverse semantics inside synthesisers: supplied or learned?

### 3B.1 FlashMeta / PROSE witness functions — HAND-WRITTEN (confirmed)
- VERIFIED (Polozov & Gulwani OOPSLA 2015,
  https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/oopsla15-pbe.pdf ):
  "it can be written by a domain expert who is not proficient in program synthesis"; "We call such domain-specific
  knowledge a witness function."; "A witness function captures the inverse semantics for the corresponding operator."
  Collaborators "focused only on domain-specific witness functions"; the authors "manually proved that all witness
  functions from our case studies" hold. For `Map(F, L)` "there is no domain-independent witness function".
- Measured: Table 2 — re-implementations in 2K-4K LOC vs 5K-17K original, 1-2 months vs 7-9 months. That is the
  engineering cost of hand-supplied inverse semantics for one domain.
- Maturity: SHIPPED (Flash Fill/Flash Extract reimplementations ship on it). Nothing is learned about inverses.

### 3B.2 Duet (Lee, POPL 2021) — inverse semantics HAND-WRITTEN
- VERIFIED indirectly, by the description in the follow-up from the same lab (Simba, Yoon/Lee/Yi PLDI 2023,
  https://ar5iv.labs.arxiv.org/html/2304.10768 , Sec. 5.1): Duet "requires inverse semantics operators that should be
  designed for each usable operator in the target language"; and its "inverse semantics often creates sub-problems
  that are hard to solve". The Duet paper itself (DOI 10.1145/3434335) was not readable (ACM 403).
- Simba in turn "requires an abstract domain designed by domain experts" with hand-devised forward and backward
  transfer functions; "Simba solves 1716 instances, while Duet and Probe solve 1671 and 409" of 1875 (1 h timeout;
  Probe was run only on the 544-task BitVec set).
- Maturity: SINGLE-PAPER each (PROVEN-RESEARCH as a family: top-down propagation with supplied inverses).

### 3B.3 lambda^2 (Feser, Chaudhuri, Dillig, PLDI 2015) — deduction rules HAND-WRITTEN per combinator
- VERIFIED (https://www.cs.utexas.edu/~isil/pldi15b.pdf ): Figures 4-5 give one deduction rule set each for
  map/mapt/filter/fold/foldt/recl; "Another limitation of our deduction procedure is that it critically depends on
  prior knowledge about the operators used for synthesis. This kind of knowledge is not in general available for
  external operators."; "The procedure DEDUCE is sound and incomplete."
- Measured (VERIFIED): "over 40" benchmarks; "median runtime is 0.43 seconds"; "88% of the benchmarks in under a
  minute"; 10-minute limit; with deduction "on average, 6 times faster" than without; without type-aware
  generalisation "more than 60% of the benchmarks do not terminate".
- Relevance: gives a measured size for what inverse semantics buys in an enumerative functional synthesiser: ~6x,
  far less than types (which decide solvability).

### 3B.4 Atlas (Wang, Anderson, Dillig, McMillan, CAV 2018) — LEARNS abstract domain + transformers
- (i) What: given a DSL *with its logical (SMT) semantics* and a few training synthesis problems, learns predicate
  templates (the abstract domain) by tree interpolation over failed/spurious programs, and synthesises sound abstract
  transformers for each DSL construct; plugs into the Blaze abstraction-refinement synthesiser.
- (ii) Measured — VERIFIED (https://ar5iv.labs.arxiv.org/html/1804.04152 , Sec. 7): "Atlas learns 5 predicate
  templates and 30 abstract transformers for the string domain in a total of 10.2 seconds"; "10 predicate templates
  and 59 abstract transformers in a total of 22.5 seconds" (matrix); 4 training problems per domain; "Blaze* solves
  133 (out of 148) benchmarks"; "an average 8.3x speed-up over Blaze†" (hand-written abstractions) on strings and
  "9.2x on average" on matrices; 20-minute limit.
- (iii) Failure modes — VERIFIED (Sec. 9): the designer must "provide the DSL's logical semantics"; transformers are
  restricted to a fixed shape (affine functions over numeric attributes); termination relies on a "unique best
  transformer" assumption that "may not hold in general". Two domains only.
- (iv) Maturity: SINGLE-PAPER.
- (v) Smallest sound version: needs an SMT solver with interpolation; not portable to an SMT-free kernel. The
  SMT-free analogue is "enumerate candidate abstract transformers from a template, test for soundness on samples" —
  which is unsound-by-testing and is what Amurth's "closed-box" future work points to.
- (vi) Relevance: the clearest positive result that *forward* abstract transformers can be learned and can beat
  hand-written ones (8-9x). It learns forward abstractions, not inverses, and it needs formal semantics as input.

### 3B.5 Amurth (Kalita, Muduli, D'Antoni, Reps, Roy, OOPSLA 2022) — SYNTHESISES abstract transformers
- (i) What: given concrete semantics of an operation, an abstract domain (order + concretisation check) and a DSL,
  runs two CEGIS loops (soundness counterexamples = positive examples, precision counterexamples = negative examples)
  to find a best transformer expressible in the DSL. Built on Sketch.
- (ii) Measured — VERIFIED (https://ar5iv.labs.arxiv.org/html/2105.00493 ): 57 transformers ("6x5 + 9x3": 6 string
  operations x 5 string domains, 9 bit-vector operations x 3 interval domains); string transformers "3.73s to
  1,983.83s"; interval transformers "4.23s to 1,449.85s"; 600 s timeout per Sketch call; the conclusion reports
  "four soundness bugs" in existing hand-written transformers.
- (iii) Failure modes — VERIFIED: the user supplies the DSL ("the user can supply a DSL of their own design") and
  "for some of the more involved transformers, we had to provide a template"; too rich a DSL caused a timeout and an
  imprecise `abs`, too poor a DSL an imprecise `contains` (Sec. 6.3); guarantees only within Sketch's unrolling bound;
  positives are hard constraints, negatives soft (MaxSAT drops conflicting negatives).
- Follow-up VERIFIED (abstract, https://arxiv.org/abs/2408.04040 , Amurth2): the earlier method fails on
  reduced-product domains because simultaneous synthesis "blows up the search space"; with one DSL per component
  it produces "more precise abstract transformers than the manually written ones" for 4 of 6 SAFEstr operations.
- (iv) Maturity: PROVEN-RESEARCH for forward transformers (Atlas, Amurth, Amurth2, plus neural-network-verifier and
  compiler transformer-synthesis lines — the latter FROM-MEMORY); SINGLE-GROUP for this algorithm.
- (v) Smallest sound version: the positive/negative-example loop is solver-agnostic: enumerate candidate transformer
  from a small DSL; a concrete input inside the abstract input whose output escapes the abstract output is a hard
  counterexample; an abstract element strictly smaller that still covers everything is a soft one. ~300-500 LOC with
  an existing enumerator, but soundness is then only test-based.
- (vi) Relevance: the best recipe for "learn a propagator from the concrete operation": same good/bad-example
  separation as the guard recipe of Part 2. It needs a per-domain DSL and minutes per operator.

### 3B.6 Absynthe (Guria, Foster, Van Horn, PLDI 2023) — abstract semantics USER-WRITTEN
- VERIFIED (https://arxiv.org/abs/2302.13145 and ar5iv): "based on user-defined abstract semantics"; the domains and
  semantics "are written by the user in a DSL"; no soundness check. "Absynthe solves around 77% of the benchmarks"
  (SyGuS strings, 22 tasks); "reaches parity with AutoPandas". Nothing about inverses is learned.
- Maturity: SINGLE-PAPER. Relevance: negative control — lightweight abstraction-guided synthesis still takes the
  abstractions as input.

### 3B.7 Mariano et al. (OOPSLA 2022, NGST2) — NOT inverse learning
- VERIFIED (abstract, https://arxiv.org/abs/2203.09452 ): neural-guided inductive synthesis for imperative-to-
  functional transpilation using "trace-compatibility" and a "cognate grammar network"; no inverses or witness
  functions are learned, and it relies on a trained neural network. Out of scope for the owner's constraints.

### 3B.8 2023-2026 items found
- Opera (Wang, Pailoor, Prakash, Wang, Dillig, PLDI 2024) — VERIFIED (https://ar5iv.labs.arxiv.org/html/2404.04743 ):
  derives an online/streaming algorithm from a batch program; "does not take any inputs beyond the implementation of
  the offline algorithm"; auxiliary state found by static analysis (one accumulator per list-dependent
  subexpression), holes solved by a computer-algebra system (quantifier elimination in REDUCE) with a
  template-enumeration fallback; 51 tasks, 98% solved (50/51), mean ~25 s, 10-minute timeout; CVC5 and Sketch
  baselines solve 2.6x and 7.2x fewer; ablations: 73% without symbolic reasoning, 67% without decomposition;
  equivalence checked only by "testing and bounded verification". This is solver discovery in a loose sense (it finds
  the incremental update, not an inverse), and it depends on fold/map/filter axioms and a CAS that are supplied.
  Maturity SINGLE-PAPER.
- Moito (Johnson, Krishnan, Reps, D'Antoni, 2024) — VERIFIED abstract (https://arxiv.org/abs/2408.15822 ): when the
  semantics is monotone, "one can obtain an abstract interval-based semantics for free from the concrete semantics";
  "can automate interval-based pruning without any a-priori knowledge of the problem domain". No numbers in the
  abstract. This is the nearest thing to a *derived* (not learned, not hand-written) pruning semantics; it is forward
  interval propagation, restricted to monotone operators. SINGLE-PAPER.
- Synantic (Liu et al., OOPSLA 2024) — VERIFIED abstract (https://arxiv.org/abs/2408.14668 ): synthesises
  "inductively defined syntax-directed semantics" as Horn clauses from a grammar and a closed-box interpreter, by
  CEGIS over SyGuS calls; "14 interpreters". Learns forward semantics, not inverses. SINGLE-PAPER.
- I found NO paper that learns FlashMeta-style witness functions or Duet-style inverse semantics automatically.
  The search was cut short (budget), so this is "none found", not "none exists".

---

## 3C. Recognisers / feature detectors invented from I/O data

### 3C.1 AutoML-Zero (Real, Liang, So, Le, ICML 2020)
- (i) What: regularised evolution over straight-line programs (Setup/Predict/Learn) built from 65 scalar/vector/matrix
  ops, scored on small proxy learning tasks.
- (ii) Measured — VERIFIED (https://arxiv.org/pdf/2003.03384 ): "Suppl. Section S2 contains the full list of 65 ops";
  good algorithms "can be as rare as 1 in 10^12"; infrastructure "searching through 10,000 models/second/cpu core";
  "Typically, 100<W<1000" worker processes, W=10k for the main experiment, "Run time: 5 days"; linear regression:
  "only 1 acceptable algorithm every 10^7"; "evolution is 5 times more efficient than RS" there.
  Discoveries: linear regression, 2-layer net with backprop, "bilinear interactions, normalized gradients, and weight
  averaging"; noisy-ReLU and learning-rate decay under task changes.
- (iii) Failure modes: the op set already contains `dot`, `outer`, `matmul`, `norm`, `mean`, `std` (Table S1) — the
  "inventions" are short recombinations (normalised gradient = gradient / norm) of supplied linear-algebra primitives;
  compute is of order 10^3-10^4 CPU cores for days; evolved code needs manual clean-up to interpret. No signal
  -analysis routine (FFT, autocorrelation, convolution) is reported; grep of the paper text finds none.
- (iv) Maturity: SINGLE-PAPER (with a few follow-ups, FROM-MEMORY).
- (vi) Relevance: upper bound on what blind evolutionary recombination found — 5-20-instruction idioms from a rich
  numeric op set — at a compute budget ~6-7 orders of magnitude above a single thread for a day.

### 3C.2 OEIS Superseeker — transforms HAND-CODED
- VERIFIED (https://oeis.org/ol.html and source https://oeis.org/ol_source.txt ): it will "apply a large number of
  algorithms in order to attempt to explain the sequence"; the source says "tmp2 contains the 115 or so transformed
  sequences" and "A list of the transforms used is in 'supertrans'"; it shells out to named human-written packages —
  gfun (guessgf, listtorec, listtoalgeq), Derksen's guesss, Gerard's seqtranslib.m, Krattenthaler's Rate, etc.
- Maturity: SHIPPED (decades in service). Nothing is discovered: it is a fixed portfolio of ~115 transforms + a
  handful of guessers + lookup. Relevance: the working design for "recognisers" is a hand-curated transform library
  plus table lookup, not invention.

### 3C.3 Self-learned OEIS program synthesis (Gauthier & Urban; Gauthier, Olšák, Urban) — uses a neural net
- VERIFIED abstracts (https://arxiv.org/abs/2202.11908 ; https://arxiv.org/abs/2301.11479 ): tree search "guided by a
  learned policy" "discovers, on its own, solutions for 27987 sequences"; the later system "discovers on its own
  programs for more than 78000 OEIS sequences", sometimes with "unusual programming methods".
- Caveat: the guide is a trained neural model, so it does not meet the owner's no-NN constraint; the abstracts do not
  claim any invented analysis routine of autocorrelation type. Maturity: SINGLE-GROUP.

### 3C.4 Koza's automatically defined functions (GP II, 1994) and GP feature synthesis
- Wikipedia (VERIFIED, https://en.wikipedia.org/wiki/Genetic_programming ) records only the human-competitive tally
  ("77 results where genetic programming was human competitive"), which are mostly circuits, controllers, antennas.
- FROM-MEMORY, NOT VERIFIED: Koza reports that ADFs cut the computational effort on even-parity problems by a factor
  that grows with problem size (single digits for even-5, tens for even-6); the ADFs found are small reusable
  sub-expressions (e.g. a 2-input parity), not analysis algorithms. GP-based feature construction for signal
  classification exists (PADO, Teller & Veloso mid-1990s; Guo/Jack/Nandi 2005 for vibration faults) with modest,
  dataset-specific results.
- Maturity: PROVEN-RESEARCH for "ADFs help on regular problems"; SPECULATIVE for "GP invents an analysis routine".

### 3C.5 Candid summary for 3C
I found **no verified precedent** in which a non-neural synthesiser, given only I/O data and primitives that do not
already contain the idea, invented a non-trivial analysis routine of the autocorrelation/FFT class. What exists is
(a) recombination of supplied numeric primitives into short idioms at very large compute (AutoML-Zero), (b) fixed
hand-written transform portfolios (Superseeker), (c) neural-guided self-play over OEIS. Note autocorrelation itself is
short if `shift`, pointwise product/equality and `sum` are primitives (sum_i x[i]*x[i+k], then argmax over k is ~10
nodes) — within enumerative reach only if those primitives and a scoring signal that rewards partial progress are
present; that reachability is the owner's design question, not something the literature has demonstrated.

---

## Conclusion of Part 3 — most reliable route to an inverse of a given forward function f in a small functional language

Ranked by evidence:

1. **Structural (local) inversion when f is built from primitives with known inverses and never discards a value**
   (Dijkstra/Gries, Janus, Glück-Kawabe LRinv). Exact, no search, no testing. Demonstrated on ~10-line first-order
   programs (inc/dec, reverse, encoders); fails on non-injective or value-discarding code. Requires the per-primitive
   inverse table — supplied, not learned.
2. **Skeleton-guided enumerate-and-test**: take f's own control/recursion skeleton as the template for g, mine g's
   vocabulary from f's text, enumerate hole fillers, check g(f(x)) = x (and for lenses the put/get laws) on samples
   or symbolic paths. Demonstrated by PINS (14 imperative programs of 5-25 LoC, 1 s - 30 min, human-edited template,
   correctness not guaranteed), Synbit (13/15 functional microbenchmarks in <= 5.6 s plus XML/lexer/parser cases;
   fails when the inverse needs a different recursion shape), Sketch (5 of 6 PINS templates), Optician (39/39
   bijective string lenses < 5 s from two regexes).
3. **Per-case decomposition with guards**: split f into guarded cases, enumerate a small inverse per case, and require
   the case images to be disjoint (= injectivity). Demonstrated by GENIC: 13 of 14 real string encoders/decoders.
   The image predicate of each case is precisely the guard for the region where g is defined; for non-injective f
   the honest outputs are a *set-valued* witness function (FlashMeta) or a right inverse g with f(g(y)) = y.
4. **Generic backwards execution** (URA, miniKanren, Curry narrowing): sound and complete for single queries; no
   reusable fast inverse; synthesis through it stops at about `append` size; non-termination handled by interleaving
   but can starve.

Unconstrained enumeration of g with only the round-trip test and no skeleton has no published success beyond
`append`-sized programs. Round-trip testing on samples cannot establish injectivity or totality; every tool above
either restricts the class (injective, bijective, well-formed) or says the result is unverified ("PINS does not
guarantee their correctness").

Inverse *semantics for synthesis operators* (witness functions, Duet inverses, lambda^2 deductions) are hand-written
in every system checked. What has been learned automatically is forward abstract transformers (Atlas: 30-59
transformers in 10-23 s giving 8-9x over hand-written; Amurth: 57 transformers at 4 s - 33 min each, finding 4 bugs
in hand-written ones) — both need formal semantics or a DSL per domain and an SMT/Sketch back end.

---

## Could not verify (Part 3)
- Hu & D'Antoni PLDI 2017 beyond the abstract: per-benchmark times, program sizes, which benchmark failed (closed access).
- URA cost: no complexity statement or timing table read; SCP/Springer copies inaccessible. Cost remarks are FROM-MEMORY.
- Glück & Kawabe benchmark lists and any timings (Springer paywall); only the authors' slides were read.
- Duet's own text (ACM 403); "hand-written inverse semantics" rests on the Simba paper's description of Duet.
- Koza ADF effort ratios; Gries ch. 21 citation; microKanren/LRinv LOC estimates; GP feature-synthesis precedents.
- Synbit AST-size figures (text and Table 4 disagree in the ar5iv rendering); Opera's per-domain split (34+18 was
  reported for a total of 51 — one of the two is off by one in the rendering).
- A full 2023-2026 sweep for learned witness functions / learned inverse semantics: search budget exhausted. Items
  recalled but unchecked: MLIR/LLVM abstract-transformer synthesis (2025), neural-verifier transformer synthesis,
  "Bee"-style PBE without witness functions.

===================================================================================================

# CONSOLIDATED — what could not be verified (all parts)

Part 1
- DreamCoder per-domain ablation percentages (only in Fig. 6); Bustle per-configuration solved counts (only in Fig. 3).
- Minton AIJ 1990 and Tambe/Newell/Rosenbloom MLJ 1990 (paywalled) — read through AAAI-88 and IJCAI-89 precursors;
  Minton's digits are from an OCR text layer. Korf AIJ 1985 — read through the AAAI-82 precursor (OCR); eight-puzzle
  macro count unverified. Laird/Rosenbloom/Newell 1986 chunking paper not opened.
- Phase saving (Pipatsrisawat & Darwiche 2007): no numbers. Clause-deletion ablations, MiniSat LOC, MapleSAT
  competition record: FROM-MEMORY.
- Korf's 1985 iterative-deepening analysis: only the Wikipedia restatement was read.
- Levin's original 1973 statement: read only via Schmidhuber's OOPS paper.
- Any shipped system using explicit Russell–Wefald value-of-computation: none found (search cut short).
- Follow-ups named in passing (Stitch, LILO, babble, CrossBeam, Trinity, Concord, Simba-in-Part-1 context): FROM-MEMORY.
- EC² Table 3 was re-assembled from a two-column PDF; the row/column assignment was cross-checked with a
  layout-preserving extraction and is consistent, but check the PDF before quoting the symbolic-regression row.

Part 2 — see "What I could not verify (Part 2)" at the end of Part 2. Headline gaps: Seghir & Kroening 2013 and
Cook et al. 2008 are abstract-only; Urban/FuncTion numbers absent; DynamiTe's own counts are mutually inconsistent;
DreamCoder's per-candidate timeout is verified only in repository code; the two absence claims (no work learns a
termination guard from timeout labels alone; no measured false-positive rate for "timeout ⇒ diverges") rest on a
truncated search.

Part 3 — see "Could not verify (Part 3)" at the end of Part 3. Headline gaps: GENIC (Hu & D'Antoni) beyond its
abstract; URA cost/timings; Glück–Kawabe benchmarks; Duet's own text; Koza ADF effort ratios; a complete 2023–2026
sweep for learned witness functions / inverse semantics.

All parts: every LOC figure is an estimate by the checker, not a sourced number.
