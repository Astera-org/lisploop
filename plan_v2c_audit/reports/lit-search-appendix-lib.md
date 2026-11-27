# Library learning / compression, AM-EURISKO, Schmidhuber lineage, LLM-guided vs LLM-free discovery

Fact-check notes, compiled 2026-11-24. Calibration, not enthusiasm.

## Conventions

- **[V]** = verified online today from the cited URL (quote or table reference given). Quotes are <25 words.
- **[D]** = derived by me from verified numbers (arithmetic shown).
- **[FROM-MEMORY]** = not verified online in this session.
- Maturity tags: SHIPPED / PROVEN-RESEARCH / SINGLE-PAPER / SPECULATIVE.
- **Search limitation:** the session's WebSearch budget ran out about half-way through. After that I could only fetch URLs I already knew. Items 2 (2025-26 LLM-free advances) and 5 (2024-26 head-to-head papers) are therefore not exhaustive. See "Could not verify" at the end.
- Local text extractions of the PDFs are in this directory (`dc_supp.txt`, `ec2.txt`, `ec2013.txt`, `stitch.txt`, `babble.txt`, `laps.txt`, `lilo.txt`, `libdoesnt.txt`, `eacl2026.txt`, `lenatbrown.txt`, `eurisko83.txt`, `oops.txt`, `powerplay_exp.txt`).

---

## 1. EC / EC² / DreamCoder

### 1a. EC (Dechter, Malmaud, Adams, Tenenbaum, IJCAI 2013, "Bootstrap Learning via Modular Concept Discovery")
Source: https://www.ijcai.org/Proceedings/13/Papers/196.pdf

(i) Enumerate typed combinatory-logic programs best-first under a weighted grammar up to a fixed "frontier size"; keep those that hit tasks; compress hit solutions by promoting reused subtrees to new primitives and re-estimating weights; repeat. No neural net.

(ii) Measured scale [V]:
- Symbolic regression: 1000 tasks (all polynomials of degree <=2, coefficients 0-9). Initial library: "the basic combinators I, S, B, C and four arithmetic primitives 1, 0, *, and +".
- 15 iterations, frontier 10,000, so 150,000 expressions total. Same-budget baseline without learning: "the baseline run only hits 27 of the 1000 tasks (3%), whereas our algorithm nears 100% for a frontier of 10000."
- Boolean circuits: 1000 sampled circuit tasks from NAND; frontier sizes 100 / 500 / 10000.
- Compute not reported in CPU time, only in expressions enumerated.

(iii) Failure modes, in the paper's own words [V]:
- Curriculum dependence, measured. Removing constants or linear functions alone did not hurt; removing both gave "a sharp drop"; restricting to quadratics with coefficients >1: "performance drops to 0 because no task is hit in the initial frontier."
- "a minimal curriculum of simple tasks is sufficient to achieve high performance"
- Plateaus: "The algorithm can get stuck in plateaus after a rapid initial increase in performance, due to its circular nature".
- Boolean functions of cardinality <=3, frontier 2000: "most of the trajectories get stuck in a local minimum around 50%."
- "Our algorithm requires, as human learners do, a sufficiently graded 'curriculum'".

(iv) Maturity: PROVEN-RESEARCH (the explore-compress loop has been reimplemented many times); this exact system is SINGLE-PAPER.

(v) Smallest sound version: typed best-first enumerator + subtree-count compression + weight re-estimation. Roughly 500-1,500 LOC in a Lisp [my estimate, not from the paper].

### 1b. EC² (Ellis, Morales, Sable-Meyer, Solar-Lezama, Tenenbaum, NeurIPS 2018)
Source: https://papers.nips.cc/paper/2018/file/7aa685b3b1dc1d6780bf36f7340078c9-Paper.pdf

(i) EC plus a neural recognition model that predicts per-task grammar weights, plus fragment-based (anti-unification-style) compression.

(ii) Scale [V]: 236 list tasks (15 examples each, 50/50 split), 109 generated text-editing training tasks (tested on 108 SyGuS), 100 symbolic regression tasks. Learned: "The system composed 38 new subroutines" (lists); "a dozen new functions" (text); "13 new functions" (symbolic regression).

**Ablation, Table 3, % held-out tasks solved [V]:**

| Domain | Full EC² | No NN (library only) | SE (subexpression-only library, no NN) | NPS (NN only, fixed DSL) | PCFG (weights only) | Enum (no learning) |
|---|---|---|---|---|---|---|
| List processing | 94 | 79 | 71 | 35 | 62 | 37 |
| Text editing | 74 | 43 | 30 | 33 | 0 | 4 |
| Symbolic regression | 84 | 75 | 62 | 38 | 38 | 37 |

Reading: in EC² the library alone recovers most of the gain (79 of 94; 43 of 74; 75 of 84). The neural net alone is about equal to plain enumeration on lists and symbolic regression.

(iii) Failure, paper's words [V]: lesioning the recognition model causes it "to hit a lower 'plateau' after which it stops solving new tasks, following an initial spurt of learning".

Compute, as reported later in the DreamCoder supplement S3.3 [V]: EC² used "3 full-batch cycles ... consuming 6 hours of program search time (on 128 CPUs)" for lists/text = 768 CPU-hours of search [D]; symbolic regression "1500 minutes of program search time (on 40 CPUs)" = 1,000 CPU-hours [D].

(iv) SINGLE-PAPER, superseded by DreamCoder.

### 1c. DreamCoder (Ellis et al., arXiv 2006.08381; PLDI 2021 [FROM-MEMORY venue]; Phil. Trans. R. Soc. A 2023 [FROM-MEMORY venue, publisher page returned 403])
Sources: main text https://arxiv.org/abs/2006.08381 ; main + full supplement https://www.cs.cornell.edu/~ellisk/documents/dreamcoder_with_supplement.pdf (the supplement link printed in the arXiv PDF is dead).

(i) Wake: neurally guided type-directed enumeration on a minibatch of tasks. Abstraction sleep: refactor found programs via version spaces / beta-inversion and add the most compressive routine under a Bayesian (MDL) objective. Dream sleep: train the recognition model on replays and samples from the library.

**Per-domain setup [V, supplement S2.1 and hyperparameter table S4.7]:**

| Domain | Starting primitives | Tasks | Wake timeout | CPUs | Minibatch |
|---|---|---|---|---|---|
| List processing | fold, unfold, if, map, length, index, =, +, -, 0, 1, cons, car, cdr, nil, is-nil + mod, *, >, is-square, is-prime (21 [D]) | main text: "218 problems"; supplement: 236 minus 21 identity tasks, 50/50 split, then 31 easy test tasks removed | 12 m | 64 | 10 |
| Text editing | same sequence primitives + `string` hole | 128 train / 108 SyGuS test | 12 m | 64 | 10 |
| Regexes | [0-9], [a-z], [A-Z], any, printable ASCII chars, Kleene star, disjunction, optional | 256 (50/50) | 12 m | 64 | 10 |
| LOGO graphics | for, get/set, move, pen-up + naturals 1-9, 4 arithmetic ops, unit distance/angle, infinity, epsilon | 160 (80/80) | 1 h | 96 | 50 |
| Towers | same control flow + move, reverse, 2 block-drop primitives | 107 (53/54) | 1 h | 64 | 50 |
| Symbolic regression | arithmetic + real-valued parameter | 100 | 2 m | 20 | 10 |
| Physical laws | "0, 1, pi, power, +, *, /, -, map, fold, zip, cons, car, cdr, and nil" (15) | 60 | 4 h | 64 | all unsolved |
| Recursive functions ("origami") | "if, =, >, +, -, 0, 1, cons, car, cdr, nil, and is-nil" + Y combinator (13) | 20 | 4 h | 64 | all unsolved |

Note the list domain already starts with fold, unfold and map. The much-quoted "rediscovers filter / sort" result starts from higher-order primitives, not from bare Lisp.

**Compute [V]:**
- "typically takes around a day using moderate compute resources (20-100 CPUs)" per domain. That is roughly 20-100 CPU-days per domain [D].
- Lists/text: converges "after 10 wake/sleep cycles ... consuming 2 hours of program search time (on 64 CPUs)" = 128 CPU-hours of search alone [D], excluding compression and network training.
- Symbolic regression: "200 minutes of program search time (on 20 CPUs)" = about 67 CPU-hours [D].
- Recognition model: trained "for 5 x 10^3 gradient steps or 1 hour, whichever comes first" per cycle.
- Independent characterisations: LAPS says current approaches need "upwards of thousands of CPU hours to bootstrap learning" (https://arxiv.org/abs/2106.11053); LILO says DreamCoder needs "more than two CPU-months just to learn a single domain" (https://arxiv.org/abs/2310.19791).

**Per-task search budget in programs:**
- [V] Enumeration-only baseline: "type-directed enumeration for 24 hours per task, generating and testing up to 400 million programs for each task." That is about 4,600 programs/s [D].
- [D] DreamCoder itself: e.g. lists 12 min x 64 CPUs over 10 tasks is about 77 CPU-minutes per task per cycle, about 2x10^7 programs per task per cycle at the baseline's rate. This assumes CPUs are split evenly across the minibatch; the paper does not state the figure.
- [V] DreamCoder on ARC (Bober-Irizar & Banerjee): "DreamCoder enumerated 3.1 billion programs for 800 tasks" at 1 CPU-hour per task, about 3.9M programs per task [D].

**What was learned [V]:**
- Lists: "composed around 20 new library routines", and sort is reached "by invoking a library component four layers deep".
- A sort solution: "five function calls using the learned library ... found in less than 10 minutes"; the same program in base primitives has "32 function calls", claimed "in excess of 10^72 years of brute-force search".
- Across domains "deeper libraries correlate well with solving more tasks (r = 0.79)".
- Text editing: "Prior to learning, DreamCoder solves 3.7% of the problems within 10 minutes ... After learning, it solves 79.6%"; 84.3% with the SyGuS budget (1 hour, 8 CPUs), vs CVC4 82.4%.
- vs EC²: "EC2 solves 91.5% list processing problems vs. DreamCoder's median of 94%"; text 74% vs 84.3%.
- All main-domain runs are 20 wake/sleep cycles, 5 seeds.

**Ablations (no recognition model / no abstraction / EC baseline / enumeration / memorize):**
- The per-domain numbers exist only as curves in Fig. 6A and S11-S12. **I could not extract numeric values; they are not in the text.**
- Text-level claims [V]: "no alternative model ever solves more than 60% of held-out tasks [LOGO, towers] while DreamCoder learns to solve nearly 100% of them."
- Neural net vs library [V, supplement S3.3]: "for DreamCoder, the neural network by itself is always at least as effective as library learning by itself — yet for EC2, the opposite is true."
- Mechanism [V, S1.1]: the recognition model "allows more training tasks to be solved during waking, which are then compressed during the next sleep cycle."
- Independent re-measurements of library-only vs base DSL, pure enumeration at test time:
  - LAPS Table 1 [V]: Original DSL enumerative 0.06 / 0.00 / 27.8 % (strings / graphics / scenes); DreamCoder best library, enumerative 27.2 / 41.44 / 53.6 %; full DreamCoder 33.4 / 49.55 best (42.64 mean) / 67.8 curriculum (73.9 mean).
  - LILO Table 1 [V], mean % solved, REGEX / CLEVR / LOGO: Base DSL 22.00 / 29.13 / 0.90; DreamCoder 43.93 / 94.50 / 28.53 (online); LILO 77.07 / 96.76 / 48.95.
- Net attribution: on DreamCoder's own domains the authors say neural-only >= library-only. On LAPS's and LILO's harder domains a DreamCoder library with plain enumeration gets most of what full DreamCoder gets, but full DreamCoder itself tops out at 28-50% on graphics. The two components are complementary; neither alone reaches the headline numbers.

**Origami experiment (McCarthy-1959 Lisp primitives to fold/unfold/map) [V]:**
- 20 hand-chosen tasks ("like those used in introductory computer science classes"); full list in Fig. S10.
- "roughly five days on 64 CPUs" = 320 CPU-days, about 0.88 CPU-years [D]. The paper: "DreamCoder took approximately a year of total CPU time."
- "We did not use the recognition model for this experiment: a bottom-up pattern recognizer is of little use for acquiring this abstract knowledge from less than two dozen problems." So this is the one pure enumeration + compression bootstrap in the paper, and it is the most expensive result in it.
- Stitch paper on the same domain [V]: "DreamCoder with 4 steps of rewriting takes roughly 2.5 days of compute on this domain"; DreamCoder "only finds all five [higher-order functions] when run in its most expensive configuration".

**Physics-laws experiment [V]:** 60 laws/identities from AP and MCAT cheat sheets, 10 random I/O examples each, constants in Planck units; excluded "trigonometric functions, multivariate differentials, and integrals". "after 8 wake/sleep cycles DreamCoder learns 93% of the laws". Upper bound on search: 8 cycles x 4 h x 64 CPUs = 2,048 CPU-hours [D]. The curriculum is self-paced: "we gave the agent all tasks it had not solved in the past two wake cycles."

**What the authors say about curriculum and from-scratch learning [V]:**
- No hand-ordering: "DreamCoder moves through randomized batches of tasks". But the task *sets* are hand-built and dense with shared structure.
- "We do not advocate such blank-slate learning as a route to AI".
- "such approaches suffer from a notorious thirst for data ... or, if not data, then massive compute".
- Search cost model (footnote): search difficulty is "roughly proportional to breadth^depth ... Library learning decreases depth at the expense of breadth, while training a neural recognition model effectively decreases breadth".
- Compression cost: "we must explore on the order of 10^14 or more refactorings before finding a single new library component."
- Self-generated tasks not done: "Building agents that generate their own problems ... is a necessary next step."
- Each domain is learned separately. A single cross-domain library is posed as an open question, not shown.

**Documented scaling failures [V]:**
- Compression blows up on larger corpora. Stitch paper: "DreamCoder was unable to discover even a single abstraction when run directly on any of the datasets from Wong et al. 2022, despite being given hours of runtime and 256GB of RAM."
- ARC, Alford et al. 2021 (https://arxiv.org/abs/2110.11536): on a hand-picked subset of 36 symmetry tasks, 16 solved initially, 22 after the final iteration. Authors: DreamCoder's guidance is "too weak to scale to the complexity of ARC tasks."
- ARC, Bober-Irizar & Banerjee 2024 (https://arxiv.org/abs/2402.03507), with a hand-built 77-primitive DSL (PeARL):

  | System | ARC-Easy (400 training tasks) | ARC-Hard (400 public eval) |
  |---|---|---|
  | icecuber (hand DSL brute force) | 209 (52%) | 160 (40%) |
  | GPT-4 | 85 (21%) | 32 (8%) |
  | DreamCoder + PeARL | 70 (text says "16.5%") | 18 (4.5%) |

  Compression "allows the search to solve a few more tasks"; the recognition model mattered more, "almost doubling the number of tasks solvable within the same time". Learned primitives also made later solutions "longer and thus more complicated over time".
- LAPS / LILO: on the harder compositional graphics domain DreamCoder reaches only 28-50% and varies a lot with random task ordering (LILO LOGO std 13.79).

(iv) Maturity: PROVEN-RESEARCH for the wake/sleep library-learning loop on curated 100-250-task domains (reused by LAPS, LILO, AbstractBeam, PeARL-ARC, dream-decompiling). The from-scratch bootstraps (origami, physics) are SINGLE-PAPER; I found no independent reproduction.

(v) Smallest sound version: typed lambda-calculus enumerator (~500 LOC), a compressor, a likelihood-weighted grammar. Replacing version-space refactoring with Stitch-style top-down search removes the main cost centre. A recognition model is optional for soundness but, per the ablations, not for performance. The reference implementation (github.com/ellisk42/ec) is a large mixed OCaml/Python/Rust codebase [size not measured].

---

## 2. Stitch, babble, LAPS, LILO, and 2024-2026 library-learning results

### Stitch (Bowers et al., POPL 2023) - https://arxiv.org/abs/2211.16605
(i) Corpus-guided top-down search over abstraction templates with upper-bound pruning; one abstraction at a time; anytime. Syntactic only, apart from a prototype.
(ii) [V] "Stitch is 3-4 orders of magnitude faster and uses 2 orders of magnitude less memory" than DreamCoder's compressor, with DreamCoder given 8 CPUs and Stitch 1 thread. Takes "tens of milliseconds" on DreamCoder's five domains. On eight larger graphics corpora: "test set compression ratio of 2.55x-11.57x in 0.19s-60.16s, with a peak memory usage of 11.21MB-714.55MB". Recovers the origami higher-order functions on top of one step of version-space rewriting "while using <2% of its compute".
(iii) Evaluated on **compression and resource use only**. It does not measure whether a Stitch library raises downstream solve rate. Without all optimisations, "cannot run in <= 90 minutes and <= 50GB of RAM".
(iv) SHIPPED as a tool (Rust core, Python bindings; used inside LILO and Leroy).
(v) Core algorithm ~1-2k LOC [my estimate].

### babble (Cao et al., POPL 2023) - https://arxiv.org/abs/2212.04596
(i) Library learning modulo an equational theory: e-graph equality saturation, anti-unification over e-classes to propose abstractions, beam extraction.
(ii) [V] "consistently achieves better compression ratios than DreamCoder ... and it does so 1-2 orders of magnitude faster"; runs on 2D CAD corpora "(roughly 10x - 100x)" larger and "out of reach for DreamCoder". Stitch paper's comparison: "babble is 10-100x faster than DreamCoder while Stitch is 1,000-10,000x faster".
(iii) Needs a hand-supplied equational theory per domain (only List and Physics had one). Compression-only evaluation. Beam approximation of the joint objective.
(iv) SINGLE-PAPER research artifact.
(v) Requires an e-graph library; not small unless one is already available.

### LAPS (Wong, Ellis, Tenenbaum, Andreas, ICML 2021) - https://arxiv.org/abs/2106.11053
(i) DreamCoder plus natural-language task annotations, used in the search prior and in compression.
(ii) [V] Table 1 (strings n=500, graphics n=111, scenes n=115): DreamCoder without language 33.4 / 49.55 best, 42.64 mean / 67.8; best LAPS 54.6-57.0 / 98.19 best, 81.98 mean / 95.6-96.5. Budgets: 1800 s per task on 48 CPUs for graphics, up to 27 iterations; 1000 s per task and 5 iterations elsewhere.
(iii) Needs human or synthetic language per task. A curriculum ordering of the scene tasks is reported as its own column, i.e. ordering matters. Human-language training drops graphics to 58.55%.
(iv) SINGLE-PAPER.

### LILO (Grand et al., ICLR 2024) - https://arxiv.org/abs/2310.19791
(i) An LLM proposes programs, Stitch compresses, an LLM names and documents abstractions (AutoDoc); enumerative search is still run alongside.
(ii) [V] Table 1 above. Enumeration budgets REGEX 1000 s, CLEVR 600 s, LOGO 1800 s on 96-CPU machines. "one round of LLM synthesis is equivalent to 48 CPU-hours of DreamCoder search" in dollar cost.
(iii) [V] Negative finding inside the paper: adding Stitch abstractions to the LLM solver *hurt* until they were documented, "-30.60 (REGEX), -2.91 (CLEVR), and -11.11 (LOGO)", because "GPT struggled to deploy anonymous abstractions". LOGO variance is large (std 22.15).
(iv) SINGLE-PAPER.

### LLM "library learning" negative results (Berlot-Attwell, Rudzicz, Si, and co-authors)
- "Library Learning Doesn't: The Curious Case of the Single-Use 'Library'" (2024) - https://arxiv.org/abs/2410.20274 [V]
  - LEGO-Prover learned "over 20,000 lemmas"; "only 1,233 lemmas (~6%) are used in the final solving step"; "exactly one lemma is reused by the PROVER, and it is reused once". Table 1 shows 0-1 verbatim reuses and 1-2 name reuses per split, none twice.
  - TroVE: final libraries "only contain 15 learned functions"; "3 successful reuses in 3,201 test questions".
  - No-reuse ablation of TroVE matched or beat the original (count 0.250 vs 0.236; num 0.290 vs 0.258).
- "LLM Library Learning Fails: A LEGO-Prover Case Study" (2025) - https://arxiv.org/abs/2504.03048 [V]: "We find no evidence of the direct reuse of learned lemmas", and no advantage over repeated prompting at equal compute.
- "Is This LLM Library Learning? Evaluation Must Account For Compute and Behaviour" (EACL 2026) - https://aclanthology.org/2026.eacl-long.163/ [V]: three systems (LEGO-Prover, TroVE, AgentOptimizer); "all of them fail to consistently outperform the simple baseline of prompting the model" once compute is equalised.
- Scope: these are LLM in-context systems, not DreamCoder-style compression. The lesson that transfers is methodological: accuracy gains were credited to a library without checking reuse or equal-compute baselines.

### ReGAL (Stengel-Eskin, Prasad, Bansal, 2024) - https://arxiv.org/abs/2401.16467
[V, abstract only] LLM refactoring into helper functions; absolute gains for CodeLlama-13B of +11.5% (LOGO), +26.1% (Date), +8.1% (TextCraft). I found no independent reuse audit of ReGAL; it is not one of the three systems in the EACL 2026 study.

### LLM-free library learning, 2024-2026 (what I could verify)
- **AbstractBeam** (Zenkner et al. 2024) - https://arxiv.org/abs/2405.17514 [V]. LambdaBeam (small neural-guided bottom-up search, no LLM) plus library learning. Handwritten test sets: 53.6% vs 50.2% and 39.6% vs 36.0%. Synthetic test sets: no significant difference, and slower. Authors: "Library Learning only works if abstractions are possible"; unused abstractions "bloat the DSL"; "the abstractions it discovers do not generalize beyond the domain".
- **Dream decompiling** (Palmarini, Lucas, Siddharth, ICML 2024) - https://arxiv.org/abs/2306.07856 [V, abstract only]. Extracts library components from DreamCoder's own recognition model; claims "faster domain proficiency", no numbers in the abstract. LLM-free.
- **Leroy** (2024) - https://arxiv.org/abs/2410.06438 [V, abstract]. Stitch applied to Python: "achieves a compression ratio of 1.04x of the original code base". Effectively a null result on real imperative code.
- **Metaprogram search, MPL** (Rule et al., Nature Communications 2024) - https://www.nature.com/articles/s41467-024-50966-x [V]. LLM-free, not library learning, but relevant: on 100 list functions it matches human learners with 500K search steps per trial and keeps ">=84%" of that at 5K steps, while plain enumeration needed more than a million steps and performed at or below the human 25th percentile. Caveats in the paper: "MPL's success depends on having specific metaprimitives"; recursive solutions in "just 34.4% of runs".
- **Gauthier & Urban** (item 5) tried macro definitions inside an LLM-free self-learning loop; result "so far inconclusive".
- I could not run a systematic search for 2025-2026 LLM-free advances. I know of no 2025-26 result that changes the picture, but that is absence of search, not evidence of absence.

---

## 3. AM, EURISKO, critiques, replications; HR and Graffiti

### AM (Lenat 1976) and EURISKO (Lenat 1983)
Primary sources read: Lenat & Brown, "Why AM and Eurisko Appear to Work", AAAI-83 version https://cdn.aaai.org/AAAI/1983/AAAI83-059.pdf (the Artificial Intelligence 23, 1984 paper is the longer version); Lenat, "EURISKO: A Program That Learns New Heuristics and Domain Concepts", Artificial Intelligence 21 (1983), scan at https://users.cs.northwestern.edu/~mek802/papers/not-mine/Lenat_EURISKO.pdf

(i) AM: an agenda of tasks over frame-represented math concepts, driven by ~243 hand-written heuristics that mutate small Lisp predicates and score "interestingness". EURISKO: the same loop with heuristics represented as units so heuristics can mutate heuristics.

(ii) Measured scale [V, EURISKO paper]:
- AM had "243" heuristics; for EURISKO's math domain "Fifty heuristics were added, which subsumed most of AM's old set of 243."
- EURISKO math run: "About 200 math concepts were present ... After about 500 hours of running, another thousand concepts had been considered, and 200 of them had proven interesting". Of those, "11 were valuable, specific new heuristics, and 7 were useful new types of slots."
- Hit rate: useful new objects "about 50% of the time".
- Traveller TCS: "146 units were added, by hand"; "EURISKO has by now spent 1300 CPU hours on a personal Lisp machine".
- AM's initial concept count (~115) and ~1 CPU-hour runs are [FROM-MEMORY].

(iii) Failure modes, in the authors' own words [V]:
- "AM's ultimate limitation apparently was due to its inability to discover new, powerful, domain-specific heuristics for the various new fields it uncovered."
- Representation density: "it is, in part, the density of worthwhile math concepts as represented in Lisp that is the crucial factor."
- What AM really did: "'syntactically mutating small Lisp programs'".
- Why heuristics-about-heuristics did not bootstrap: mutating a two-page heuristic "is doomed to almost always giving garbage", and "For five years, that effort achieved mediocre results."
- The fix was human representation engineering: it was necessary "to evolve two orders of magnitude more kinds of slots", and heuristic code size "declined, from 60 lines to 3" before mutation produced winners again.
- Unary representation of numbers "was critical to AM's discovering arithmetic"; with place-value numbers the route "would not have worked at all."
- Plateau: the fortuitous "impedance match" let AM "proceed with great speed for a while, until it moved into a less well balanced state."
- Meaning attributed by observers: "we -- the human observers -- play another crucial role in attributing 'meaning' to a discovery in AM."
- **Human share of the Traveller win** [V]: Lenat "culled through the runs of EURISKO every 12 hours or so", "weeding out heuristics he deemed invalid", and concludes "the final crediting of the win should be about 60/40% Lenat/EURISKO ... neither party could have won alone."
- Number theory concepts were "discovered by EURISKO and later hand-smoothed by the author".
- Domain choice: "Mathematics was a poor choice of domain for AM ... since it has been so well explored".

### Ritchie & Hanna, "AM: A case study in AI methodology", Artificial Intelligence 23(3):249-268 (1984)
[V, abstract only; full text paywalled] https://researchportal.hw.ac.uk/en/publications/am-a-case-study-in-ai-methodology/ : AM's "techniques employed are somewhat obscure in spite of the impressive performance"; such work "is unproductive from the point of view of building a stable base for further research."
[V via Wikipedia's summary, https://en.wikipedia.org/wiki/Automated_Mathematician]: some heuristics were entangled with control code rather than separate rules; rule preconditions depended on history; published rules used vague terms; a rule boosting tasks the user recently mentioned suggests discovery work hidden in "unexplained procedures".
Lenat's reply reportedly conceded omitted heuristics [search-snippet level only].

### Haase's Cyrano
[V, abstracts only; MIT DSpace rate-limited the PDFs]
- AI Memo 898 (1986), https://dspace.mit.edu/handle/1721.1/6450 : "Cyrano is a thoughtful reimplementation of Lenat's controversial Eurisko program"; such systems are "search processes which dynamically reconfigure their search space by the formation of new concepts".
- WP-293 (1987), "Discovery Systems: From AM to CYRANO", https://dspace.mit.edu/handle/1721.1/41178 : after AM, "no generation of automated super-mathematicians appeared"; EURISKO's lesson: "a close coupling of representation syntax and semantics is necessary for a discovery program to prosper"; Cyrano adds "a requirement of 'closure' in concept formation" (new concepts must be valid inputs to the same concept-forming process).
- Whether Cyrano reproduced any EURISKO result: not verifiable from the abstracts. [FROM-MEMORY: it did not reproduce the headline results.]

### Source release and replication attempts, 2023-2024
- [V] https://white-flame.com/am-eurisko.html : AM and EURISKO sources found in the SAILDART archive under Lenat's account, password-protected "until Dr. Lenat's passing"; discovery discussed 2023-11-24.
- [V] https://github.com/white-flame/eurisko : RLL and Traveller-domain data searches "has all come up empty"; "the code is lacking some infrastructure described in the later papers"; the EUR file predates the 1981 tournament. A Common Lisp port is "slowly" in progress.
- [V] https://github.com/seveno4/EURISKO : runs under Medley Interlisp; README gives run instructions only.
- **No reproduction of any published AM or EURISKO discovery is reported on any of these pages.** The Traveller domain data is missing, so that result cannot be re-run from the recovered files.
- Wikipedia lists an open-source Prolog AM re-implementation as "claimed, not verified".

(iv) Maturity: SINGLE-PAPER. Never independently reproduced; methodology publicly criticised; substantial undocumented human steering.
(v) Smallest sound version: an agenda loop plus frame store is a few hundred LOC. The content (243 heuristics, 146 hand-added Traveller units) is the system, and that is not small or automatable.

### Colton's HR
[V] https://cs.uwaterloo.ca/journals/JIS/colton/joisol.html (Colton, J. Integer Sequences 1999): HR invented "refactorable numbers" (A033950); an addendum concedes they "were a machine re-invention" (Kennedy & Cooper 1990). Seven further HR sequences were submitted to the Encyclopedia, two more in the addendum. "HR did only the easy part - it invented the concept". HR "only knew the factorizations of the integers up to 100", and one of its conjectures was later refuted by large counterexamples. Its group-theory sequences were "mostly disappointing".
[FROM-MEMORY] ~10 production rules; later use for generating TPTP theorems and in bioinformatics; larger sequence counts in Colton's AAAI-2000 paper.
Maturity: PROVEN-RESEARCH as a concept/conjecture generator in narrow algebraic domains.

### Fajtlowicz's Graffiti
[V] https://en.wikipedia.org/wiki/Graffiti_(program) : written 1984-85; "the first 18 conjectures were announced" in 1986; conjectures led to "approximately 80 publications" by mathematicians including Erdős, Chung, Lovász. The Dalmatian heuristic keeps a conjectured bound only if it is sharper than existing ones for at least one known graph, to avoid being swamped by true trivia.
Maturity: PROVEN-RESEARCH for conjecture generation.

**Why neither compounded** [my analysis, not a quoted claim]: both operate in a fixed, human-supplied vocabulary (graph invariants; a fixed production-rule set). Their outputs go to human mathematicians, not back into the generator. Graffiti's published successes are human proofs or refutations of machine-posed inequalities. There is no loop in which a proved conjecture makes later conjectures cheaper.

---

## 4. Schmidhuber lineage

### Levin search, 1997
- "Discovering neural nets with low Kolmogorov complexity and high generalization capability", Neural Networks 10(5):857-873. Original PDF not retrieved. [V via independent replication, https://jellepiepenbrock.github.io/2020/04/02/searching-for-neural-networks-with-low-kolmogorov-complexity.html]:
  - Counting task: 100 binary inputs, 100 weights, **3 training examples**; a generalising solution is found after 9-13 programs.
  - Position-sum task: solution found after 16,733 programs (34,341 runs in total).
  - With different primitives: 69,349-73,902 programs.
  - Replicator: raising the work tape to the paper's 1000 cells "results in an explosion of the search"; "The exact formula's for some metrics ... are shrouded in mystery."
  - The paper's own abstract restricts the claim to "certain toy problems where it is computationally feasible".
- "Shifting inductive bias with success-story algorithm, adaptive Levin search, and incremental self-improvement" (Schmidhuber, Zhao, Wiering, Machine Learning 28, 1997). [V] https://people.idsia.ch/~juergen/mljssalevin/node8.html (Experiment 2):
  - 23x23 maze, 7 goals ordered by distance, four nested goal sets.
  - Plain Levin search: 27.8x10^6 steps to find all goals of the last set (17.3x10^6 for goal 7 alone).
  - Adaptive LS: 650x10^3 (method 1) or 289x10^3 (method 2). SSA+ALS: 405x10^3 or 230x10^3.
  - Whole-run totals: LS 39.4x10^6 steps; ALS 1.67-1.82x10^6; SSA+ALS 0.87-1.05x10^6. So roughly 20-45x from adaptive bias shift on one hand-ordered sequence [D].
  - Limits stated: no help on the first goal set; "Optimizing a policy for goals 1--4 will not necessarily help to speed up discovery of goal 5"; SSA kept only 61 of 377 (or 63 of 996) policy modifications.
- Maturity: SINGLE-PAPER / toy scale. Smallest version: a few hundred LOC (the replication is a short Python program).

### OOPS (Schmidhuber, Machine Learning 54, 2004) - https://arxiv.org/abs/cs/0207097
(i) Incremental universal search over a Forth-like language. Solutions to earlier tasks are frozen; half the search time goes to programs that start by calling or editing frozen code, including code that rewrites the search distribution.

(ii) Measured [V; my recollection of the experiment was correct]:
- "61 + 7 = 68 initial non-task-specific primitives", 73 with task-specific ones.
- 60 tasks: 30 of the 1^n 2^n language, then 30 Towers of Hanoi.
- "Within roughly 0.3 days, oops found and froze code solving all thirty 1^n 2^n-tasks. Thereafter, within 2-3 additional days, it also found a universal Hanoi solver."
- Whole run: "4-day search ... tested 93,994,568,009 prefixes corresponding to 345,450,362,522 instructions costing 678,634,413,962 time steps" on a 1.5 GHz PC at 1-2 million steps/s.
- Reuse speedup: probability of the Hanoi suffix rises from 4.5x10^-14 to 9.3x10^-11 for the whole 10-token program; "speeding up the search by a factor of 1000 or so"; without it, "a search time of several years".
- Implementation: "a dozen pages of code written in C, mostly comments and documentation".

(iii) Failure modes, paper's words [V]:
- Without the helper tasks: "within reasonable time (a week) on a personal computer, the system with 71 initial instructions was not able to solve instances involving more than 3 disks."
- The helper curriculum was chosen by the author, and instruction probabilities were hand-"boosted" per task family (c1, c2 for 1^n 2^n; c3, c4, c5 for Hanoi).
- The Hanoi solver "does not call the 1^n 2^n solver as a subprogram"; it only reuses a probability boost toward recursion-defining instructions.
- "the search for the universal solver for all 1^n 2^n-problems ... did not at all profit from solutions to earlier solved tasks".
- "Given a single task ... oops does not by itself invent an appropriate series of easier subtasks".
- "a badly chosen training sequence of intermediate tasks may cost more search time than required for solving just the final task".
- Substantial prior knowledge inserted in task representation: "we insert substantial, nontrivial prior knowledge".
- With hindsight-restricted primitives the 10-disk problem is solvable "within less than an hour, without having to learn easier tasks first".
- 5% of total time was simply running the found solver on n = 30.

(iv) SINGLE-PAPER. One demonstrated transfer between two task families. I found no independent replication.
(v) ~1k LOC of C.

### PowerPlay (Schmidhuber 2011, https://arxiv.org/abs/1112.5309) and "First Experiments with PowerPlay" (Srivastava, Steunebrink, Schmidhuber 2013, https://arxiv.org/abs/1210.8385)
(i) Search jointly for a new self-invented task and a solver modification such that the new solver solves it and all previous tasks; compression of the solver counts as a task.
(ii) The 2011 paper is a framework; "A first experimental analysis can be found in separate papers" [V]. In the experiments paper [V]:
- Experiment 1: a small feed-forward net invents and learns 2-D point-labelling tasks; decision boundaries go from linear to non-linear over ~43 tasks.
- Experiment 2: a SLIM RNN controlling a fovea over one static photo. "Within 8 hours on a standard PC, a SLIM RNN consisting of 20 WITAS, with 4 neurons in each WITAS, invented 67 novel action sequences". Of 340 learned tasks, 67 were non-compression; the rest were compressions of the weight matrix. "on average only 2.9 weights were changed to invent a new skill".
(iii) The "tasks" are internally generated input/internal-state pairs with no external meaning. No external benchmark is solved. The search bias favours tasks that are cheap to validate, i.e. trivial novelties. No demonstration that self-invented skills help on any externally posed problem.
(iv) SINGLE-PAPER; demonstrated far less than the framing claims.

### Gödel machine
[V] https://en.wikipedia.org/wiki/G%C3%B6del_machine : "Though theoretically possible, no full implementation has been created." Steunebrink & Schmidhuber (2011), "A Family of Gödel Machine Implementations", describes a partial virtual-machine implementation [search-snippet level].
[V] "Darwin Gödel Machine" (2025), https://arxiv.org/abs/2505.22954 : an LLM coding agent that replaces proof with empirical benchmarks, because the original is "in practice impossible to create"; SWE-bench 20.0% to 50.0%; one run "takes about 2 weeks and incurs significant API costs". It is LLM-driven and not a Gödel machine in Schmidhuber's sense.
Maturity: SPECULATIVE.

**Demonstrated vs claimed, lineage summary:** bias-optimality theorems are real but concern constant factors. Demonstrations are (a) toy nets from 3 examples, (b) one maze with ~20-45x speedup from adaptive bias, (c) one 1000x transfer across two author-chosen task families at 4 PC-days, (d) 67 self-invented fovea trajectories. Nothing shows open-ended accumulation.

---

## 5. LLM-guided vs LLM-free discovery (calibration)

### FunSearch (Romera-Paredes et al., Nature; volume/year from memory: 625, 2024) - https://www.nature.com/articles/s41586-023-06924-6
[V] LLM (Codey) proposes edits to one short Python function inside a human-written skeleton; an evaluator scores; island-model evolution.
- Cap set n=8: size 512. Capacity lower bound 2.2180 to 2.2202 ("the largest improvement in 20 years").
- Reliability: "only four out of 140 experiments discovering a cap set of size 512".
- Budget: samples "on the order of 10^6" per result; 15 samplers and 150 CPU evaluators.
- Total CPU-hours, dollar cost and ablation numbers are in the supplement and were not retrieved.

### AlphaEvolve (2025) - https://arxiv.org/abs/2506.13131
[V] 4x4 complex matrix multiplication with 48 scalar multiplications; over 50 open problems with ~75% matching best known and ~20% improved; kissing number in 11 dimensions 593 (from 592); Borg scheduling heuristic recovering 0.7% of fleet compute; 23% kernel speedup and 1% Gemini training-time reduction. "thousands of LLM samples suffice" versus "millions" for FunSearch; evaluations can take ~100 compute-hours each. Ablation values are figure-only.
Follow-up [V]: Georgiev, Gómez-Serrano, Tao, Wagner, "Mathematical exploration and discovery at scale" (https://arxiv.org/abs/2511.02864): 67 problems; mostly rediscovered best known results, improved several.
Maturity: PROVEN-RESEARCH; the paper reports infrastructure results at Google (production-deployment detail is FROM-MEMORY). Note neither system accumulates a reusable library across problems; each problem is a separate evolutionary run [my characterisation].

### ARC: pure program search vs LLM / test-time training
- [V] ARC Prize 2024 Technical Report, https://arxiv.org/abs/2412.04604 : icecuber (2020) "exclusively leveraged brute-force program search to achieve 20% on the private evaluation set"; an ensemble of 2020 entries reached 49%. 2024: MindsAI 55.5%, ARChitects 53.5% (test-time training). The best DSL-search-based 2024 entry scored 40% (Agnis Liukis, team alijs). Program-synthesis and transduction approaches "both score in the 40% range". Greenblatt: 42% public eval, GPT-4o writing "thousands of Python programs per task".
- [V] icecuber's repository, https://github.com/top-quarks/ARC-solution : depth-2 search over the hand-built DSL gives "129 / 419 correct predictions" on the public evaluation set in "70 seconds on my computer" (laptop i7, 16 GB); the full depth-3 test run "takes 9 hours". Single-thread-scale brute force over a well-chosen hand DSL was competitive until 2024. DSL size (~142 hand-coded unary functions) is [FROM-MEMORY].
- [V] Li et al. 2024, https://arxiv.org/abs/2411.02272 : icecuber 39% on the public validation split (with the caveat it was "designed by looking at val set"); LLM induction with 20k samples per task 38%; transduction + TTT 43%; ensemble 56.75%; CodeIt 15%.
- [V] ARC Prize 2025 Technical Report, https://arxiv.org/abs/2601.10904 : Kaggle top scores on ARC-AGI-2 private set: NVARC 24.03%, ARChitects 16.53%, MindsAI 12.64%. LLM-free but neural: TRM (7M parameters) 45% ARC-AGI-1 / 8% ARC-AGI-2; CompressARC (76K parameters, no pretraining) 20% / 4%. Gemini 3 Pro 31% at $0.81 per task; with a refinement harness 54% at $31 per task. The report does not mention any pure DSL-search result on ARC-AGI-2; the ARC Prize site (search-snippet level, arcprize.org/arc-agi/2) says ARC-AGI-2 removed tasks "susceptible to brute force search".
- [V, page fetched 2026-11-24; whether rows are "verified" entries is unknown] https://arcprize.org/leaderboard now lists frontier LLMs at 98.5% on ARC-AGI-1 and 92-96% on ARC-AGI-2 (e.g. GPT-6.2 Astra 95.8%, Gemini 4 Carbon 94.2%, Claude Fable 5.2 93.8%), with ARC-AGI-3 scores up to 81.2%. ARC-AGI-1 and -2 no longer separate methods. I found no LLM-free program-search entry on the current board.
- icecuber on ARC-AGI-2: not verified.

### Gauthier & Urban, OEIS program synthesis (LLM-free self-learning)
- "Learning Program Synthesis for Integer Sequences from Scratch" (2022) - https://arxiv.org/abs/2202.11908 [V]
  - Language: "13 basic operators" (0, 1, 2, x, y, +, -, x, div, mod, cond, loop, loop2, compr).
  - Guidance: tree neural network, embedding dimension 64, written in C, CPU only.
  - "The unguided generation 0 discovers only 993 solutions"; 27,987 OEIS sequences after 25 generations (of 351,663 OEIS entries, about 8% [D]).
  - Compute: 16 cores per search phase, total "less than 100 CPU days (no GPUs were used)".
  - Plateau: new solutions per generation fell from 8,438 (generation 1) to 187 (generation 25).
  - No definitions / library learning.
  - 92% of 12,639 checked solutions match further OEIS terms.
- "Alien Coding" (Gauthier, Olšák, Urban, 2023) - https://arxiv.org/abs/2301.11479 [V]
  - Tree network replaced by a small NMT model (2-layer bi-LSTM, 512 units), trained from scratch each iteration on its own solutions.
  - Random initial programs solve 3,771; 46,707 after 100 iterations; 78,118 after 190 iterations (84,587 across all runs).
  - Compute: about 3 h training + 10.5 h inference per iteration on GTX 1080 Ti GPUs, "about three months", ~1,836 kWh.
  - Plateau: the first NMT run fell below 200 new solutions per iteration after iteration 37; the tree-network baseline plateaued at about five per iteration; the main run "rarely dropped below 200".
  - **Library learning tried and inconclusive**: local and global macro definitions were "so far inconclusive"; the macro runs added fewer than 2,800 solutions each.
- "Learning Conjecturing from Scratch" (2025) - https://arxiv.org/abs/2503.01389 [V]: same loop for induction predicates; 5,565 of 16,197 problems vs 2,265 for CVC5/Vampire/Z3 at 60 s.
- Maturity: one group, several papers; PROVEN-RESEARCH within that group. This is the strongest LLM-free, from-random-initialisation compounding curve I found (3,771 to 78,118, about 20x). It compounds through a retrained *policy*, with program speed/size selection, **not** through an accumulated library.

### Same-benchmark comparisons of enumeration vs LLM-guided search (2024-2026)
- HySynth (Barke et al., NeurIPS 2024) - https://arxiv.org/abs/2405.15880 [V]: 299 tasks (ARC 160, String 70, Tensor 69), 10-minute timeout, 100 GPT-4o samples per task: "solving 58% of the tasks overall, compared to 40% for unguided search and 6% for LLMs without search."
- Li, Parsert, Polgreen (CAV 2024) - https://arxiv.org/abs/2403.03997 [V, Table 1]: 609 SyGuS benchmarks, 600 s. LLM only 49.8%; uniform A* enumerator 50.7%; cvc5 68.1%; LLM-guided A* 52.9%; LLM union guided enumerator 80.1%.
- LILO Table 1 (above): LLM solver vs DreamCoder enumeration on REGEX 76.13 vs 43.93, CLEVR 88.67 vs 94.50, LOGO 32.13 vs 28.53.
- Bober-Irizar (above): on ARC public eval, hand-DSL brute force 40% > GPT-4 8% > DreamCoder 4.5%.
- Rule et al. 2024 (above): enumeration at >1M steps is below human 25th percentile where metaprogram search matches humans at 5K-500K.
- Reading: in small formal DSLs with tight budgets, plain or classically guided enumeration was still equal to or better than 2023-24 LLMs alone, and the hybrid won. That was the 2024 picture. The 2026 ARC leaderboard suggests the LLM-alone side has moved a great deal since; I have no 2026 same-benchmark DSL comparison.

---

## 6. What makes a bootstrap compound, and where each lineage stalled

### Measured evidence that compounding happens at all
| Source | Before | After | Mechanism | Cost |
|---|---|---|---|---|
| EC 2013 | 3% (27/1000) at equal enumeration budget | ~100% | library + weights | 150k expressions |
| EC² Table 3 | Enum 37 / 4 / 37 % | 94 / 74 / 84 % | library + NN | ~770-1000 CPU-h search |
| DreamCoder text editing | 3.7% | 79.6% | library + NN | 64 CPUs; converges in ~10 cycles (2 h of search = 128 CPU-h, excl. compression/training) |
| DreamCoder origami | 0 recursive routines | fold, unfold, map, etc.; 20/20 tasks | library only | ~1 CPU-year |
| OOPS | Hanoi >3 disks unsolved in a week | universal solver in ~3 days | reused probability boost, ~1000x | 4 PC-days |
| Adaptive Levin search | 27.8M steps | 0.23-0.65M steps | adaptive instruction probabilities | one maze |
| Gauthier-Urban | 993 / 3,771 | 27,987 / 78,118 | retrained policy; no library | <100 CPU-days / 3 GPU-months |

### Conditions under which it compounded (each backed above)
1. **A dense, graded task set with shared sub-structure, supplied from outside.** EC 2013 measured the cliff directly: drop the constants and linear tasks and performance falls sharply; drop to hard quadratics and it is zero, "because no task is hit in the initial frontier". OOPS's 1000x needed an author-chosen helper family. DreamCoder's tasks are randomly batched, not ordered, but the sets are hand-built corpora of 20-256 related tasks per domain; the two from-scratch runs use "all unsolved" batching, which is self-pacing over a fixed human-built set. No system in this slice generated its own useful curriculum. PowerPlay generated tasks, but not useful ones.
2. **Search guidance that shrinks effective breadth as the library grows.** DreamCoder's own cost model is breadth^depth: libraries cut depth and add breadth. EC² without the network plateaus lower. DreamCoder says neural-only >= library-only. On ARC the recognition model nearly doubled solved tasks while compression added "a few". Gauthier-Urban compound with policy learning and no library at all, and their macros were inconclusive. AbstractBeam: unused abstractions "bloat the DSL" and gave nothing on a test set without repeated structure.
3. **A representation in which small syntactic edits are usually meaningful.** Lenat & Brown's whole argument: AM worked because of "the density of worthwhile math concepts as represented in Lisp", and stopped when it left that region. Heuristics did not bootstrap for five years until a human redesigned their representation. OOPS's result depends on instruction numbering and hand boosts. DreamCoder's list domain starts with map/fold/unfold.
4. **Compression that is semantic (refactoring), not just syntactic, and affordable.** DreamCoder motivates refactoring by EC²'s failure to find the origami and physics libraries, and pays for it: ~10^14 refactorings per new component; ~1 CPU-year for 20 tasks; cannot find one abstraction on larger corpora in 256 GB. Stitch makes syntactic compression nearly free, but shows compression, not downstream solve-rate.
5. **A human in the loop, usually under-reported.** EURISKO: 60/40 Lenat/EURISKO by Lenat's own accounting, with culling every 12 hours and 146 hand-added units. AM: results partly attributed by observers. HR "did only the easy part". FunSearch: human-written skeleton and evaluator, 4 of 140 runs.

### Where and why each lineage stalled
- **EC / DreamCoder.** (a) Compute: the only pure enumeration + compression bootstrap from Lisp-level primitives cost about a CPU-year for 20 tasks, and the authors explicitly disavow blank-slate learning afterwards. (b) Compression scalability. (c) Demonstrated depth is small: about 4 layers, ~20 routines, 20 cycles; curves converge by 10-20 cycles. (d) One domain at a time. (e) ARC: 4.5% of public eval. The line's own successors (LAPS, LILO) replaced the weak prior with language and then with an LLM.
- **LLM-era library learning.** Where reuse was audited, it was nearly absent (1 reused lemma of 1,233 used; 3 reuses in 3,201 questions), and gains disappeared under equal compute. LILO found raw abstractions hurt the LLM until documented.
- **AM / EURISKO.** Stalled when the concept frontier moved away from the region where Lisp mutations are dense in meaning; heuristic self-improvement needed years of human representation engineering; results never reproduced, and the recovered code lacks the Traveller data.
- **Schmidhuber.** Each demonstration is one hop of transfer on an author-designed sequence. OOPS states it cannot invent its own subtasks and that a bad sequence costs more than no sequence. PowerPlay invents tasks without external value. The Gödel machine has no full implementation.
- **HR / Graffiti.** Productive conjecture sources inside a fixed human vocabulary; no feedback from proofs into generation.
- **Gauthier-Urban.** The best LLM-free curve, but it is neural policy self-training on 350k human-curated targets (the OEIS), with sub-linear growth: thousands of new solutions per generation early, a couple of hundred later.

### Bearing on the owner's observation
The record does not contain a self-bootstrapping, LLM-free, enumeration + compression system that kept compounding beyond one curated domain. The closest (DreamCoder origami) needed ~0.9 CPU-years on 64 cores for 20 tasks chosen to share fold/unfold structure. In every lineage, the parts that carried the discovery were supplied from outside the kernel: primitives and representation, task corpus, culling, and in recent systems an LLM prior. A coding agent doing most of the discovery is the same pattern Lenat quantified as 60/40 in 1983.

---

## Could not verify / gaps

1. DreamCoder per-domain ablation numbers (no-recognition, no-abstraction, EC, memorize, enumeration): figure-only (Fig. 6A, S11, S12). Verified only text statements, EC² Table 3, and LAPS/LILO re-measurements.
2. DreamCoder per-task enumeration count during wake: derived, not stated in the paper.
3. PLDI 2021 and Phil. Trans. 2023 bibliographic details: publisher page returned 403; from memory.
4. Ritchie & Hanna 1984 full text (paywalled): abstract plus Wikipedia's summary only.
5. Haase's Cyrano reports: abstracts only (MIT DSpace returned 429; DTIC 403). Whether Cyrano reproduced EURISKO results is from memory.
6. Lenat & Brown: read the AAAI-83 version, not the longer 1984 journal version.
7. Schmidhuber 1997 (Neural Networks) original: numbers come from an independent 2020 replication blog, not the paper.
8. Steunebrink & Schmidhuber 2011 Gödel machine implementation: search-snippet and Wikipedia only.
9. HR scale beyond the 1999 JIS paper; Graffiti details beyond Wikipedia; any primary-source statement of why they did not compound (my analysis).
10. AM's initial concept count and run time: from memory.
11. icecuber DSL size; icecuber's ARC-AGI-2 score.
12. FunSearch total compute and ablation numbers; AlphaEvolve ablation numbers.
13. Any independent audit of ReGAL's reuse.
14. Any 2025-2026 LLM-free library-learning advance: not searchable after the search budget ran out. Coverage is limited to papers whose URLs I already knew.
15. ARC leaderboard 2026 figures: taken from a page fetch; verified/unverified status of rows unknown; no 2026 technical report read.
16. HySynth per-domain counts and FunSearch previous-best cap set size: not confirmed from text.
