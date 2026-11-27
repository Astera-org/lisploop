# Enumerative program synthesis at scale — fact-check notes

Compiled 2026-11-24. Slice: LLM-free enumerative search (bottom-up + observational equivalence (OE), top-down typed/recursive, superoptimisers/brute force) and the growth-number question.

**Method.** Every number tagged VERIFIED was read today from the primary PDF/README (downloaded, `pdftotext`, grepped); the URL and a short quote or table reference follow it. FROM-MEMORY = not checked online today. INFERRED = my arithmetic on verified numbers. Figures (cactus plots) are images and could not be read; only what the paper *text* says about them is reported.

**Search-budget caveat.** The session's shared web-search budget ran out about two thirds of the way through. After that I could only fetch URLs I already knew. Consequences are listed in "Could not verify" at the end.

Size conventions differ per paper: "size" is AST nodes including leaves unless stated; superoptimisers count instructions; Knuth counts gates in a DAG; icecuber counts unary-transformation depth.

---

## A. Bottom-up enumeration with observational equivalence

### A1. TRANSIT (Udupa et al., PLDI 2013)
URL: https://www.cis.upenn.edu/~alur/Pldi13.pdf

- (i) Protocol synthesis from "concolic snippets"; the expression-inference core enumerates expressions by increasing size, pruning any expression whose value vector on the concrete examples equals an earlier one (the canonical OE algorithm), wrapped in CEGIS with an SMT solver.
- (ii) VERIFIED scale:
  - Vocabulary: about 20 typed functions over Int/Set/Bool/PID (Table 1: add, sub, inc, dec, setadd, setsize, setunion, setinter, setminus, setof, or, and, not, setcontains, iszero, equals, ge, gt, ite, numcaches).
  - Table 3 (8 micro-benchmarks): sizes 6–15 solved. Size 15 "Max of a, b, c" took 536 s / 762 s (7 / 16 CEGIS iterations); size 15 "Sym. diff. of 4 sets" 132 s; sizes ≤ 11 all < 1 s. One benchmark (expected size > 20) timed out at 30 min.
  - Abstract: "can infer expressions with a size of 15 symbols within a few minutes."
  - Fig. 5 (text): pruned variant "often explores two to three orders of magnitude fewer expressions" for sizes > 10; exhaustive variant omitted above size 10 "where it exceeds the memory limit of 3.5 GB."
  - In real use (Table 4): 49 update expressions synthesised with 449 expressions tried in total (VI protocol); 157 with 3,330 tried (MSI). The expressions actually needed in the case studies were tiny.
- (iii) Failure: size > 20 not reached in 30 min. Unpruned enumeration dies of memory at size ~10.
- (iv) Maturity: the system is SINGLE-PAPER; the algorithm is PROVEN-RESEARCH (re-implemented in ESolver, EUSolver, Probe, Bustle, TF-Coder, Duet, and the baseline of TF-Coder's evaluation).
- (v) Smallest sound version: the paper's Algorithm (SolveConcrete) is ~25 lines of pseudocode. INFERRED: 100–300 LOC for a typed size-ordered enumerator with a signature hash set.

### A2. EUSolver (Alur, Radhakrishna, Udupa, TACAS 2017)
URL: https://www.cis.upenn.edu/~alur/Tacas17.pdf

- (i) Enumerates small terms correct on *subsets* of examples plus predicates, then unifies them into a decision tree (divide and conquer). Falls back to plain OE enumeration when the spec is not point-wise.
- (ii) VERIFIED: "6000 lines of Python code ... and 3000 lines of C++"; StarExec, "two 4-core 2.4GHz Intel processors and 256GB of RAM, with a timeout of 3600 seconds." PBE track: "solving 787 of the 852 benchmarks, while no other tool solved more than 39"; the plain enumerator ESolver "solved 1". General track 206 / 309 (ESolver 139).
- Independent re-measurement (Duet paper, Table 2, 1 h timeout, VERIFIED): EUSolver on string tasks: size-9 solution in 1887.6 s, size-12 in 2789.6 s, size-10 in 1291.3 s and 971.8 s; six of ten sampled string tasks > 1 h. On 205 string tasks EUSolver solved 132, average 6 m 44 s.
- (iii) Failure: solutions are large case-split trees (bit-vector average size 326.6 in Duet's table); "performance degrades drastically with the size of the smallest solution" for the non-decomposed enumerator (abstract).
- (iv) PROVEN-RESEARCH (SyGuS-Comp 2016 winner in general and PBE tracks per the paper; standard baseline since).
- (v) ~9K LOC as built; the decision-tree unifier is the non-trivial part.

### A3. Probe (Barke, Peleg, Polikarpova, OOPSLA 2020)
URL: https://arxiv.org/abs/2010.08663

- (i) Size-ordered bottom-up OE search generalised to cost order under a PCFG; the PCFG is learned during the search from partial solutions (programs satisfying a subset of examples). No pre-training.
- (ii) VERIFIED:
  - 140 SyGuS benchmarks: 82 String, 27 BitVec (Hacker's Delight), 31 Circuit. "String benchmark grammars have a median of 16 operations, 11 literals, and 1 variable"; BitVec median 17 operations, 3 literals, 1 variable; Circuit median 4 operations, 6 variables.
  - "10 minute timeout ... commodity Lenovo laptop with a i7 quad-core CPU @ 1.90GHz with 16GB of RAM." Implemented in Scala.
  - Solved: Probe 91 / 140; EuPhony 50; CVC4 107. String: Probe 48 (mean 29 s, median 8.3 s). BitVec: Probe 21 / 27 (mean 5 s). Circuit 22 / 31 (mean 90 s).
  - **Unguided baselines inside the same code**: size-based 42 / 82 String, 20 / 27 BitVec, 22 / 31 Circuit; height-based 9, 13, 22.
  - **Grammar-size sensitivity** (70 String benchmarks with one shared extended grammar, 48 string + 11 integer literals): Probe 25; "height-based and size-based enumeration solved 1 ... and 9". Paper's own comment: "the baseline synthesizers need the benefit of approaching each task with a different, carefully chosen grammar."
  - Growth numbers: see section D.
- (iii) Failure: no condition abduction, so excluded all case-splitting bit-vector benchmarks; CVC4 solves more String tasks (75) but with solutions "9 times larger ... on average" and one of "over 7100(!) AST nodes". In Simba's 1-hour re-run (below) Probe solved 31 / 44 HD and 378 / 500 deobfuscation tasks, average solution size only 6.5 and 7.9.
- (iv) PROVEN-RESEARCH: re-implemented by the Bee Search authors, used as a baseline by Simba, DryadSynth, Synthphonia.
- (v) Size-ordered OE enumerator + cost rounding + restart on PCFG update. INFERRED 500–1500 LOC.

### A4. Bustle (Odena et al., ICLR 2021) and its baseline, with CrossBeam's re-measurement
URLs: https://arxiv.org/abs/2007.14381 ; https://arxiv.org/abs/2203.10452 (CrossBeam, ICLR 2022) ; https://github.com/google-research/google-research/tree/master/bustle

- (i) Bottom-up OE search over a spreadsheet-string DSL; a small MLP on "property signatures" re-weights each intermediate value. Not an LLM, but a trained model. Java.
- (ii) VERIFIED:
  - DSL (Fig. 1): 22 operations over strings/ints/bools (Concat, Left, Right, Substr, Replace, Trim, Repeat, Substitute ×2, ToText, LowerCase, UpperCase, ProperCase, If, +, −, Find ×2, Len, Equals, GreaterThan, GreaterThanOrEqualTo), 25 fixed string constants plus constants extracted from the examples, integer constants 0, 1, 2, 3, 99.
  - 38 new tasks + 89 SyGuS tasks. "BUSTLE searches about 5 million expressions per benchmark attempt, and 1 million expressions per successful attempt." "solving 31 tasks within 30 million candidate expressions or 30 seconds."
  - CrossBeam Table 1 (wall clock, 127 tasks total): **unguided baseline (Java) 74 at 3.4 s, 91 at 30 s**; Bustle (Java) 101 at 3.4 s, 112 at 30 s; baseline in Python 74 at 30 s. "the Python version is about 9× slower than the Java one."
  - CrossBeam App. C (candidate budget): Bustle 59 / 127 at 50,000 candidates, 94 / 127 at 1 million candidates. A "candidate" includes values later pruned by OE.
- INFERRED throughput: Bustle's axes (30 M candidates, 30 s) and "1 M candidates → 94 tasks, 3.4 s → 101 tasks" imply ≥ 3×10^5 and plausibly ~10^6 candidate expressions/s in Java on string tasks with 2–4 examples. No paper states a rate.
- (iii) Failure: 6–7 of 38 hand-written tasks unsolved at 30 s; with the larger DSL used by Bee Search, Bustle drops from 180 to 117 of 205 SyGuS tasks.
- (iv) PROVEN-RESEARCH (re-implemented in CrossBeam and Bee Search).
- (v) Baseline enumerator is the TRANSIT algorithm.

### A5. TF-Coder (Shi, Bieber, Singh, TOPLAS 2022)
URL: https://arxiv.org/abs/2003.09040 ; https://github.com/google-research/tensorflow-coder

- (i) Weighted bottom-up enumeration over TensorFlow expressions with value-based (OE) pruning and two-stage type/shape/value filtering; two small models re-weight operations. Hand-assigned integer weights per operation.
- (ii) VERIFIED:
  - "our work supports 134 different operations"; the same operation set for every task.
  - 70 real tasks (50 StackOverflow, 20 industrial). Solves 63 / 70 within 5 minutes, "in 17 seconds on average"; without models 61 / 70; **plain TRANSIT (no weights, no filtering) 39 / 70**. Removing weights: 10 fewer; removing filtering: 19 fewer.
  - Task difficulty (footnote 3): 9 tasks need 1 operation, 19 need 2, 23 need 3, 11 need 4, 3 need 5, 5 need 6 or more.
  - Largest: "5 TensorFlow operations and 11 nodes in the expression tree", found in 65.6 s. "the largest TF-Coder solution among our benchmarks contains 5 operations."
  - Filtering "eliminates 98.6% of all potential candidate programs for a single operation."
  - Public tool logs: 415 unique problems solved ("73% of which are solved in under 10 seconds"), 194 unsolved; estimated ~85% success on well-specified problems.
- (iii) Failure (Section 6.3): the 7 timeouts need 3, 5, 6, 9, 10, 10, 13 operations. Given more time: the 3-operation one "is solved correctly in 31 minutes", the 5-operation one "in 58 minutes"; "The remaining problems are simply too difficult for TF-Coder to solve within an hour." Of 21 manually confirmed true failures in the wild, "13 of the 21 problems use 6 or more operations."
- (iv) SHIPPED (open-source Google tool with a public Colab and usage telemetry).
- (v) Python; the search core is small, the 134 operation wrappers and filters are the bulk.

### A6. cvc4sy / cvc5 enumerative SyGuS (Reynolds et al., CAV 2019)
URL: https://homepage.divms.uiowa.edu/~ajreynol/cav19b.pdf

- (i) Three term enumerators inside the SMT solver: "smart" (constraint-based with symmetry-breaking lemmas), "fast" (brute-force size-ordered generation keeping only terms unique up to the solver's rewriter), and a hybrid (variable-agnostic). PBE problems additionally use divide-and-conquer unification.
- (ii) VERIFIED: 2,428 benchmarks; "one core, 1800 seconds, and 8GB RAM for each job" on Intel E5-2637 v4. Table 1: auto strategy 1,814 solved; fast 1,789; smart 1,774; auto + single-invocation 1,949. PBE-BV 751 / 753 and PBE-Str 105 / 109 with fast enumeration. Fast without rewriting-based dedupe drops from 1,789 to 1,690. No terms-per-second figure is reported.
- (iii) Failure: CLIA 20 / 88 for pure enumeration (EUSolver 85); Lustre invariants 255 / 485. Text on the cactus plot: the enumerative strategies "solve more benchmarks than EUS for lower times but then EUS solves more benchmarks in the end." PBE solutions are large (Probe measured 9× larger than Probe's on average).
- (iv) SHIPPED (CVC4 / cvc5).
- (v) Not separable from the SMT solver; the FastEnum procedure itself is ~10 lines of pseudocode.

### A7. Duet (Lee, POPL 2021)
URL: https://psl.hanyang.ac.kr/assets/pdf/popl21.pdf

- (i) Bottom-up enumeration builds a component library of all OE-distinct expressions up to size n; top-down propagation with hand-written inverse semantics decomposes the goal into sub-goals that components can satisfy; n grows on failure.
- (ii) VERIFIED: "5K lines of OCaml code"; Intel Xeon 2.6 GHz, 256 GB; 1 h timeout. 1,443 / 1,536 solved (String 204 / 205, Bitvec 670 / 750, Circuit 569 / 581), average 27.3 s. EUSolver 1,258; CVC4 987.
  - **How big are the enumerated pieces?** "the maximum size of components range from 1 to 12 with an average of 4"; "92% of problems (1317) could be solved with component expressions of size ≤ 7."
  - Component-library sizes |C| (Table 2), see section D.
  - Motivating claim: for a size-18 string solution, bottom-up OE enumeration fails: "the solution cannot be found even within 6 hours."
- (iii) Failure: 80 bit-vector tasks unsolved; one sampled task ran out of time with n = 5 and |C| = 44,023. Needs an inverse-semantics rule per operator (domain engineering).
- (iv) SINGLE-PAPER implementation, but the standard baseline for Simba, DryadSynth, Synthphonia.
- (v) 5K LOC OCaml as built.

### A8. Simba (Yoon, Lee, Yi, PLDI 2023)
URL: https://arxiv.org/abs/2304.10768

- (i) Duet-style bidirectional search where pruning comes from iterated forward/backward abstract interpretation (bitwise abstract domain) of partial programs instead of inverse semantics.
- (ii) VERIFIED: "10K lines of OCaml code"; Xeon 2.6 GHz, 256 GB; 1 h timeout; 1,875 tasks. Solved: Simba 1,716; Duet 1,671; Probe 409 (Probe only applicable to 544).
  - Fig. 3d: HD (44): Simba 42, Duet 36, Probe 31. Deobfusc (500): 477 / 420 / 378. Average solution sizes: Probe 6.5 and 7.9; Simba 7.7 and 9.6.
  - Table 1 examples: hd-19-d1 size 19 in 10.79 s (Probe and Duet > 1 h); hd-20-d1 size 15 in 98 s; "11,365 out of total 11,710 partial programs" discarded (97.1%).
- (iii) Failure: slow with many examples (BitVec-Cond: Simba 619 vs Duet 646); the paper leaves other domains (loops, strings) as "an open question."
- (iv) SINGLE-PAPER (used as a baseline by DryadSynth).
- (v) 10K LOC OCaml + Z3.

### A9. 2024–2026 bottom-up work

**DryadSynth bit-vector (Ding & Qiu, POPL 2024).** URL: https://github.com/purdue-cap/DryadSynth/blob/master/docs/popl2024.pdf
- VERIFIED: "around 6K lines" of Rust; two Xeon E5 10-core 2.2 GHz, 128 GB; 1,273 benchmarks; 10-minute timeout; "solved 31 synthesis problems for the first time, including 5 renowned Hacker's Delight problems."
- **Not LLM-free**: one of its three techniques extends the grammar with ChatGPT-generated subexpressions ("gpt-3.5-turbo"), run in parallel with the traditional search. The repo README lists an OpenAI API dependency.
- Maturity: SINGLE-PAPER.

**Synthphonia (Ding & Qiu, PLDI 2025).** URL: https://github.com/purdue-cap/DryadSynth/blob/master/docs/pldi25.pdf
- VERIFIED: Rust, "approximately 7 KLOC"; concurrent deduction + "versatile" enumeration threads (default 4 worker threads, so not single-threaded); 694 string benchmarks (205 Duet, 354 PROSE, HardBench); **1-minute timeout**; "accurately solved 531 out of 694", 97 overfit; "solved 116 challenging string transformation tasks for the first time." HardBench examples were produced "with the aid of ChatGPT" (benchmarks only; the solver is LLM-free).
- Maturity: SINGLE-PAPER.

**Bee Search (Ameen & Lelis, JAIR 2023).** URL: https://arxiv.org/abs/2310.04327
- (i) Best-first bottom-up search performed in an abstract "cost-tuple" space so programs are generated in exact cost order without materialising programs that will not be evaluated.
- VERIFIED: 205 SyGuS string + 38 Bustle + 27 Hacker's Delight tasks; "2.4 GHz CPUs with 16 GB of RAM. The algorithms had 120 minutes to solve each task."
- Solved (smaller DSL → larger DSL): Bee Search with its own cost function 184 → 132 of 205; Bustle 180 → 117; Brute 143 → 95. 38-task set: 28–29 → 15 best. Bit-vector: 21 → 13 for Probe.
- Example: "Probe evaluates approximately one billion programs to find the solution ... Bee Search evaluates only approximately one million."
- Note: says Heap Search "is unable to perform observational equivalence"; the Eco Search paper says all three use OE in its framework.
- Maturity: SINGLE-PAPER, re-implemented by the Eco Search authors.

**Heap Search (Fijalkow et al., AAAI 2022).** URL: https://arxiv.org/abs/2110.12485
- (i) Bottom-up enumeration of a PCFG's programs in exact non-increasing probability order using per-nonterminal heaps; plus a grammar splitter for parallel search. Costs come from a small GRU, not an LLM.
- VERIFIED: DSLs of "around 40" (DeepCoder) and "around 20" (DreamCoder) primitives, depth ≤ 6; 137 filtered DreamCoder list tasks, "timeout of 100s and a maximum of 1M programs"; Heap Search solves 97 / 137; A* 85; threshold 83; "generates 2.35 times more programs than A*". Programs-per-second appear only in figures.
- Maturity: PROVEN-RESEARCH within one group's framework (DeepSynth).

**Eco Search (Matricon, Fijalkow, Lagarde; arXiv 2412.17330, version fetched today is marked "under review at JAIR").** URL: https://arxiv.org/abs/2412.17330
- (i) Best-first bottom-up search with constant delay between outputs.
- VERIFIED: Python (DeepSynth); one core of a Xeon Gold 6130 2.1 GHz; 300 s timeout; memory cap 16 GB.
  - FlashFill/SyGuS (205 tasks, 27–28 rules): Eco 129.6, Bee 106.8, Heap 76.4. DeepCoder (792 tasks, 1320–1383 rules): Eco 633.4, Heap 563.8, Bee 435.4.
  - **Pure enumeration throughput, no evaluation**: Bee "9.1 to 10.0 seconds per million programs", Eco "8.7 to 12.7 seconds", Heap about 39–100 s per million. That is ~0.8–1.1×10^5 programs/s in Python.
  - Memory: peak 5.4 GB (Heap Search) in 300 s; "memory linear in the number of programs it generates."
  - Honest limitation stated: learned cost functions were "close to the uniform grammar."
- Maturity: SINGLE-PAPER.

---

## B. Top-down typed / recursive-function synthesis

**Is it the same ~40–60 small list/tree benchmark set? Yes, VERIFIED.** Myth's 43 → SMyth 43 → Burst 45 → Trio 45 + 20 = 65 → SyRup 43 (32 need recursion). λ² has its own ~40; Escher 22; Synquid 64 of which the example-based ones are "top three most complex" from prior tools. Timeouts are 120 s in SMyth, Burst, Trio, SyRup, Synquid; 5 min Escher; 10 min λ².

### B1. Myth (Osera & Zdancewic, PLDI 2015)
URL: https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf
- (i) Type-and-example-directed search for typed recursive functions over algebraic datatypes: examples are pushed through introduction forms (refinement tree), and elimination-form terms are enumerated by size and checked by evaluation.
- (ii) VERIFIED: 43 benchmarks (Fig. 9) + 6 extended (Fig. 10); "Intel i7-4770 @ 3.4 GHz and 16 Gb of ram ... single-threaded"; OCaml.
  - Sizes 5–32 AST nodes in the main suite (tree_postorder 32, tree_binsert 31, list_compress 28); benchmarks described as "15–30 AST nodes". Extended: arith 47 nodes / 11.1 s; fvs_large **75 nodes in 3.9 s with 31 examples** ("largest example of a fully synthesized recursive function in the literature at 75 AST nodes").
  - Most minimal-context times < 0.2 s.
- (iii) **Hand-picked components — VERIFIED and large.** Each task gets a minimal context containing only the needed helper functions ("it cannot discover helper functions on its own, so we provide them"). Adding just five generic functions ("and, or, plus, div2, and append") gives "55% average increase" but: list_compress 0.073 s → 128.3 s; list_pairwise_swap 0.007 → 10.2 s; list_sorted_insert 0.122 → 22.0 s; tree_binsert 0.374 → 9.03 s.
  - Examples must be trace-complete (the user supplies the I/O of every recursive call): developing them "proved to be difficult initially."
  - No primitive ints or strings; unoptimised interpreter.
- (iv) PROVEN-RESEARCH (benchmarks and algorithm re-implemented by SMyth; baseline for Burst, Trio, SyRup).
- (v) INFERRED 2–4K LOC OCaml.

### B2. λ² (Feser, Chaudhuri, Dillig, PLDI 2015)
URL: https://www.cs.utexas.edu/~swarat/pubs/pldi15.pdf
- (i) Best-first search over hypotheses built from higher-order combinators (map, fold, filter, ...) with per-combinator deduction rules that infer sub-examples or refute; closed hypotheses filled by enumeration.
- (ii) VERIFIED: "∼4,000 lines of OCaml"; Xeon E5-2430 2.20 GHz, 8 GB; 10-minute limit; all of ~40 benchmarks solved; "median runtime is 0.43 seconds, and it can synthesize 88% of the benchmarks in under a minute." Hardest: tconcat 551.84 s, droplast 316.39 s, dedup 231.05 s, dropmins 114.65 s, cprod 83.83 s.
  - Ablations (Fig. 6): without deduction, dedup / droplast / tconcat / cprod time out; **without types almost every non-trivial benchmark times out** (median ⊥).
  - Solution sizes are not tabulated.
- (iii) **Hand-picked components — VERIFIED**: an "Extra primitives" column adds per-benchmark helpers (member, max, reverse, sum, join, min, pr). With random examples 5 benchmarks were not synthesised.
- (iv) SINGLE-PAPER (own benchmark suite).
- (v) ~4K LOC OCaml.

### B3. Escher (Albarghouthi, Gulwani, Kincaid, CAV 2013)
URL: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/cav13.pdf
- (i) Forward (bottom-up) component enumeration with OE, plus a goal graph that synthesises conditionals by splitting the example set; recursive calls are evaluated by asking an oracle.
- (ii) VERIFIED: 22 benchmarks; **one fixed set of "22 components" for all tasks** (Fig. 5: Boolean, integer, list, tree primitives); 5-minute limit, 1 GB memory limit; OCaml. Size-ordered Escher solves all, max 10.7 s (nodes_at_level).
  - **OE ablation**: with OE off, 3 tasks hit the memory limit (hbal_tree, nodes_at_level, insert) and stutter goes from 0.552 s to 67.3 s, reverse 0.224 → 10.5 s. With goal graph off, 4 time out (hbal_tree, nodes_at_level, insert, gcd). With both off, 5 run out of memory.
- (iii) Needs an oracle for recursive-call outputs; components are untyped ("run-time type error evaluate to err").
- (iv) System SINGLE-PAPER; OE and goal-graph ideas PROVEN-RESEARCH.
- (v) INFERRED ~1–2K LOC.

### B4. Synquid (Polikarpova, Kuraj, Solar-Lezama, PLDI 2016)
URL: https://arxiv.org/abs/1510.08419
- (i) Top-down enumeration of typed terms where each partial term is checked against a polymorphic refinement type by an SMT-backed liquid type checker ("round-trip" checking), with condition abduction. Specs are refinement types, not examples.
- (ii) VERIFIED: 64 benchmarks, all solved; 2-minute timeout; "all but 7 benchmarks are synthesized within 5 seconds." Sizes: "red-black tree insertion of size 69", "3-value binary heap constructor of size 246" (non-recursive); AVL rotate 11–19 s; AVL delete 15.67 s.
- (iii) **Hand-picked components and bounds — VERIFIED**: Table 1's "Components" column is per-benchmark (reverse is given "insert at end"; quicksort is given "partition, append w/pivot"; RBT insert is given "balance left, right"). Times are for "optimal exploration bounds, which could differ across benchmarks"; with shared default bounds 3 benchmarks time out. Without the MUSFix solver "37 out of 64 benchmarks time out."
  - Independent re-test (Burst paper): Synquid solves 49% of the 45 Myth-style tasks from logical specs; (SMyth paper) fails on several sketching tasks.
- (iv) PROVEN-RESEARCH as a baseline; one implementation lineage. Needs an SMT solver, so it is not in the same class as a pure evaluator-based kernel.
- (v) Not small: liquid type checker + Horn solver.

### B5. SMyth (Lubin, Collins, Omar, Chugh, ICFP 2020)
URL: https://arxiv.org/abs/1911.00583
- (i) Myth-style search plus "live bidirectional evaluation" so that examples can be pushed through partially written programs (sketches); does not need trace-complete examples.
- (ii) VERIFIED: Mid-2012 MacBook Pro 2.5 GHz i5, 16 GB; "passes 38 of the same 43 benchmarks (without sketches)"; 120-second limit; enumeration starts from tiny terms.
- (iii) VERIFIED failures: "did not terminate within 120 seconds for the remaining four (list_compress, tree_binsert, tree_nodes_at_level, and tree_postorder)"; list_even_parity over-specialised. Only minimal contexts were run: "we inherit any scalability issues of the prior techniques." Leon and Synquid fail on several of its tasks.
- (iv) SINGLE-PAPER.

### B6. Burst (Miltner et al., POPL 2022)
URL: https://arxiv.org/abs/2107.06253
- (i) Bottom-up synthesis of recursive programs with finite tree automata: assume recursive calls can return anything ("angelic"), synthesise, then check and strengthen the spec.
- (ii) VERIFIED: 45 benchmarks; 2.5 GHz Core i7, 16 GB; 120 s limit. IO specs: solves all but 2 (SMyth fails 4). Reference-implementation specs: all but 2, average 4.49 s (SMyth fails 12). Logical specs: 41 / 45 = 91% (Leon 76%, Synquid 49%).
- (iii) Fails on list-take and list-sorted-insert (IO), tree-nodes-at-level and list-rev-tailcall (Ref), nat-add and nat-max (logical, "very under-constrained"). Trio measured peak memory 5.3 GB for Burst on this suite.
- (iv) SINGLE-PAPER.

### B7. Trio (Lee & Cho, POPL 2023; numbers from the extended JFP 2025 version)
URL: https://www.cambridge.org/core/services/aop-cambridge-core/content/view/2BA53AFECEAB119C9E5439BC656BCDC3/S0956796825100063a.pdf/inductive-synthesis-of-structurally-recursive-functional-programs-from-non-recursive-expressions.pdf
- (i) Bottom-up enumerates recursion-free "blocks", then top-down propagation generalises them into recursive programs, pruning by block traces.
- (ii) VERIFIED: "about 4K lines of OCaml"; 2.0 GHz Core i5, 16 GB; 120 s limit; 65 benchmarks (45 prior + 20 from the OCaml tutorial). IO specs: Trio 65 solved (57 correct), Burst 54 (49), SMyth 53 (48); average 1.5 s. Ref specs: 60 / 56 / 42. Largest reported solution size 87 (tree_binsert). Peak memory 88 MB. Initial component size n = 6.
- (iii) 8 of 65 IO solutions are not the intended program (overfit); 5 Ref timeouts from too many CEGIS rounds; expr_div times out under Ref.
- (iv) SINGLE-PAPER.

### B8. SyRup (Yuan, Radhakrishna, Samanta — **PLDI 2023**, not POPL 2023)
URL: https://par.nsf.gov/servlets/purl/10498880 (DOI 10.1145/3591255)
- (i) Jointly searches recursion traces and programs with version spaces; goal is fewer and less carefully chosen examples.
- (ii) VERIFIED: 43 tasks (Myth/SMyth suite; "32 tasks require recursion"); single thread on Xeon E5-2690 2.9 GHz; 120 s limit; headline is success rate versus number of examples, not raw counts.
- (iii) VERIFIED: fails list_rev_tailcall and list_pairwise_swap; both SyRup and Burst "start to time out more often when the number of examples increases"; "scalability is not an issue for the current benchmarks."
- (iv) SINGLE-PAPER (distinguished paper).

### B9. MagicHaskeller (Katayama, 2005–2022)
URLs: https://www.haskell.org/haskell-symposium/2013/magichaskeller.pdf ; https://hackage.haskell.org/package/MagicHaskeller
- (i) Exhaustive generate-and-test of well-typed Haskell expressions from a fixed component library in a breadth-first stream, with memoisation by type and removal of semantically equivalent expressions by random testing.
- (ii) VERIFIED (2013 demo paper): runs as a service so that users "share a monolithic memoization table (of tens of gigabytes)"; on "16 problems ... from the first 20 of 99 Haskell Problems" it "could solve 11 of them, partially solve 1 of them, and could not solve 4"; "could solve 3 of the 9 examples" from the FlashFill paper. "only easy problems could be solved."
  - VERIFIED (AGI-09 comparison, below): version 0.8.3 solves most of 11 small list problems in ≤ 20 s, shiftr in 157.32 s.
  - Hackage: latest 0.9.7.1 uploaded 2022-06-02; 16,105 total downloads.
- (iii) Users cannot choose the component set in the web version; depth-bounded; memory-bound.
- (iv) SHIPPED in a niche sense (maintained Hackage package and web service), research-grade.
- **Not verified**: the per-depth tables of expression counts before/after equivalence filtering in Katayama's PRICAI 2008 paper. All mirrors I could reach refused automated fetches.

### B10. IGOR2 (Kitzelmann & Schmid)
URL (comparison paper, Hofmann, Kitzelmann, Schmid, AGI-09): https://www.atlantis-press.com/article/1839.pdf
- (i) FROM-MEMORY: analytical induction of constructor term-rewriting systems by anti-unifying example equations, with search only over a few refinement operators (partitioning, sub-function introduction, recursive call). Not generate-and-test.
- (ii) VERIFIED (Table 3, 11 problems, 10-minute timeout, Intel Dual Core 2.33 GHz, 4 GB): IGOR II times 0.007–5.695 s on the problems it solves (lasts 5.695, isort 0.105, reverse 0.103, shiftr 0.127); ADATE 1–467 s; MagicHaskeller 0.01–157 s.
- (iii) The text extraction dropped the timeout glyph, so I cannot say exactly which cells are timeouts; mult/add and allodds are not solved by IGOR II. Requires example sets closed under the recursion.
- (iv) SINGLE-PAPER lineage (one group).

### B11. FrAngel (Shi, Steinhardt, Liang, POPL 2019)
URL: https://arxiv.org/abs/1811.05175
- (i) Random (not enumerative) generation of Java programs from arbitrary library components, with two heuristics: mine fragments from programs that pass some tests, and "angelic" control-structure conditions resolved later.
- (ii) VERIFIED: "about 7500 lines of Java"; Xeon E5-2673 v3 2.4 GHz; "30 minute timeout per synthesis task and a 4 GB memory limit"; 120 tasks; average components per task 101 (ControlStructures), 292 (GitHub), 401 (Geometry), 3,639 (SyPet).
  - "FrAngel solves 94% within 30 minutes and 47% within 10 seconds"; SyPet 28%.
  - Throughput: pure random search 14,000 programs/s on SyPet tasks and 31,400 programs/s on the rest; FrAngel "only tries on average 5,300 PPS"; SyPet 37 programs/s.
  - Task size: "median task size of 11 and maximum of 22" AST nodes.
  - Search-space growth for one ~100-component task: "roughly 30K programs of size 5 ... 800K programs of size 6, and over 10M of size 7."
- (iii) Some tasks deliberately unsolved; outputs not minimal (≈1.16× task size); component library is chosen per task by naming classes.
- (iv) SINGLE-PAPER.

---

## C. Superoptimisers and brute force

### C1. Massalin's Superoptimizer (ASPLOS 1987)
URL: https://www.cse.iitm.ac.in/~krishna/courses/2022/odd-cs6013/MassalinCANews87.pdf
- VERIFIED: exhaustive enumeration of 68020 instruction sequences by length, a few hand-chosen test vectors as a probabilistic equivalence filter, plus bit-table pruning of sequences known to be non-optimal.
- "The initial version ... tested about 40 programs per second, and this allowed programs of up to 3 instructions." With the probabilistic test: "superoptimizer can test 50000 programs per second."
- "has generated programs 12 instructions long in several hours running time on a 16MHz 68020."
- Size: "about 300 lines of 68020 assembly code."
- Limits: "the exhaustive search still grows exponentially"; pointers unsupported; the instruction table is a chosen subset; results inspected manually rather than verified.
- INFERRED: 5×10^4/s × ~4 h ≈ 7×10^8 programs for length 12, so an effective branching factor of about 5.5 per instruction after pruning. STOKE's paper characterises this as requiring the opcode set to be restricted "to between 10 and 15."
- Maturity: PROVEN-RESEARCH (idea re-implemented many times).

### C2. GNU superopt (Granlund & Kenner, PLDI 1992)
URL (README of the tool): https://github.com/embecosm/gnu-superopt
- VERIFIED from the README only: time complexity "approximately O(m n^2n)" for m instructions and length n; "In most cases it is about 5, but for a rich instruction set as the HPPA it is just 4. The longest sequence ever generated was for the MC68020 and 7 instructions long. It took several weeks to generate it."
- Maturity: SHIPPED (GNU tool). The PLDI paper's own tables were not checked.

### C3. Denali (Joshi, Nelson, Randall, PLDI 2002)
- FROM-MEMORY only: E-graph saturation with axioms plus a SAT encoding of "is there a k-cycle schedule"; goal-directed rather than enumerative; demonstrated on short Alpha code sequences. I could not reach a copy today, so no numbers are given. Maturity: SINGLE-PAPER.

### C4. STOKE (Schkufza, Sharma, Aiken, ASPLOS 2013)
URL: https://theory.stanford.edu/~aiken/publications/papers/asplos13.pdf
- VERIFIED: MCMC over loop-free x86-64 sequences, cost = test-case mismatch + performance; sound SMT validation at the end.
- Emulator: "just under 500,000" test-case evaluations per second; proposals evaluated per second "at peak exceeds 50,000"; symbolic validations "well below 100" per second.
- Compute: "a small cluster consisting of 40 dual-core 1.8 GHz AMD Opterons ... computational budgets of 30 minutes" for each of synthesis and optimisation. Sequence length parameter ℓ = 50; headline result is an 11-instruction Montgomery multiplication kernel.
- Failure: "unable to synthesize a rewrite for three of the Hacker's Delight Benchmarks" (round up to power of 2, next higher with same bit count, exchanging two fields), because near-miss programs are indistinguishable by the cost function; loop-free code only.
- Maturity: PROVEN-RESEARCH (open source, many follow-ups).

### C5. Souper (Sasnauskas et al., arXiv 2017)
URL: https://arxiv.org/abs/1711.04422
- VERIFIED: synthesises cheaper right-hand sides for LLVM IR DAGs with solver-based CEGIS because plain enumeration "fails to produce results within an acceptable amount of time when the cheapest RHS either contains non-trivial constants or requires more than a handful of instructions."
- Windows kernel: "Out of 15,846 unique LHSs ... discovered a cheaper RHS for 935 of them within a one-minute timeout"; each LHS limited to five instructions.
- FROM-MEMORY: later Souper versions added an enumerative synthesiser with dataflow-based pruning (Mukherjee et al., OOPSLA 2020).
- Maturity: SHIPPED as an open-source tool used to find missed LLVM optimisations.

### C6. Lens / GreenThumb (Phothilimthana et al., ASPLOS 2016)
URL: https://mangpo.net/papers/lens-asplos16.pdf
- VERIFIED: bidirectional enumerative search with test-case-refined equivalence classes; prior enumerative search "could only synthesize up to three ARM instructions within an hour"; Lens raises enumerative solves "from 11 to 20 (out of 22)" with "11x reduction on the search time"; but "it still cannot synthesize ARM code with more than five instructions or GreenArrays (GA) code with more than 12 instructions."
- Window decomposition gives a (near-)optimal "ARM program of 16 instructions within 10 minutes"; cooperative (enumerative + stochastic + symbolic) superoptimiser "solves 29" of 32; 1-hour timeout.
- Maturity: SINGLE-PAPER.

### C7. AutoML-Zero (Real, Liang, So, Le, ICML 2020)
URL: https://arxiv.org/abs/2003.03384
- VERIFIED: evolutionary search (not enumeration) over three-function register-machine programs; "full list of 65 ops"; "searching through 10,000 models/second/cpu core"; functional-equivalence cache "results in a 4x speedup"; main experiment W = 10k worker processes, "Run time: 5 days"; Fig. 6 x-axis runs to 10^12 algorithms evaluated.
- Sparsity: acceptable linear regressors are 1 in 10^7 random programs even with "only using necessary ops and fixing component function lengths"; "as rare as 1 in 10^12" for harder tasks.
- Random search fails; evolution's advantage grows with task difficulty.
- INFERRED: 10^4 × 10^4 cores × 5 days = 4×10^13 evaluations upper bound, i.e. ~1.2 million core-hours.
- Maturity: SINGLE-PAPER at that scale (code open-sourced).

### C8. icecuber, Kaggle ARC 2020 winner
URLs: https://github.com/top-quarks/ARC-solution (README and ARC-solution_documentation.pdf) ; https://arxiv.org/abs/2412.04604 (ARC Prize 2024 report)
- VERIFIED: "applies up to 4 of 142 unary transformations (based on 42 different functions ...)", deduplicated, then greedily stacked; C++, parallel; "9 hour / 16 GB memory budget"; private leaderboard score 0.794 (error), i.e. about 20% solved, 1st place. ARC Prize report: "exclusively leveraged brute-force program search to achieve 20% on the private" set.
- **Depth scaling**: "running at depth 3 is about 20× faster (and takes 20× less memory)" than depth 4; depth 2 "is again about 15× faster than depth 3, while solving about 80% as many tasks." With the full 9 hours "I can run about half the problems at depth 4."
- README: depth 2 on the evaluation set "takes 70 seconds" on an i7-7700HQ (8 threads) and gives "129 / 419 correct predictions."
- Hand-built DSL: "constructed transformations by hand-solving 100 training tasks and 100 evaluation tasks"; "a bit over a month of full time work."
- ARC Prize report: ensembling all 2020 entries reaches 49%; best single brute-force submission later 40%.
- Maturity: one artifact, but independently scored on a hidden test set.

### C9. Knuth, optimal Boolean chains for all 5-variable functions (TAOCP 4A §7.1.2)
URL (draft pre-fascicle 0C): https://cs.stanford.edu/~knuth/fasc0c.ps.gz
- VERIFIED from the draft: "There are 616,126 classes of essentially different functions" of five variables; Table 2 gives the number of classes and functions at each minimum cost C(f) from 0 to 12; exactly one class needs 12 gates (truth table 169ae443).
- Functions by cost 0…12: 12; 100; 1,140; 11,570; 109,826; 995,240; 8,430,800; 63,401,728; 383,877,392; 1,519,125,536; 2,123,645,248; 195,366,784; 1,920.
- Compute: the last step generated "approximately 53 million special chains with n = 5 and r = 11 ... every such chain led to 5^11 = 48,828,125 functions"; preface thanks donors for "many hours of computer time on large, fast machines." No hour count given. Class representatives gave "a thousand-fold speedup."
- INFERRED: 53×10^6 × 4.9×10^7 ≈ 2.6×10^15 candidate functions in that step.
- Maturity: exhaustive, published result.

### C10. Optimal sorting networks, 9 inputs (Codish, Cruz-Filipe, Frank, Schneider-Kamp, 2014)
URL: https://arxiv.org/abs/1405.5754
- VERIFIED: "generate-and-prune" breadth-first over comparator networks modulo permutation and subsumption, in Prolog; "144 Intel E8400 cores clocked at 3 GHz ... 288 threads."
- Naive space for 24 comparators on 9 channels ≈ 2.25×10^37; representatives |R_k^9| for k = 1…14: 1, 3, 7, 20, 59, 208, 807, 3,415, 14,343, 55,991, 188,730, 490,322, 854,638, 914,444; then shrinking to 1 at k = 25.
- Compute: R_1…R_14 "in just over one week"; then either "five additional days" of generate-and-prune or a SAT step totalling 3,028 h + 333 h of CPU ("just under 12 hours" wall). Single-core estimate: "approx. 9 years of computation on a single core." "more than 10 trillion subsumption checks."
- Maturity: PROVEN-RESEARCH.

---

## D. The key question: growth numbers

### D1. Syntactically distinct terms versus OE classes, by size

| Source (grammar) | What is counted | Numbers | Reduction |
|---|---|---|---|
| Probe Fig. 6/7 (4 leaves, concat/2, replace/3; 2 examples) | OE bank entries per size | size 1: 4; 3: 9; 4: 6; 8: 349; 9: 714; 10: 2,048. By height: 4; 15; 1,023; ~30M | Height 1: "from 80 to 15" (VERIFIED). INFERRED syntactic counts for the same grammar: size 8: 21,504; 9: 129,024; 10: 540,672, so 62×, 181×, 264× |
| Probe text (same grammar, 3 examples) | size-19 solution rank | "within the first ∼4M programs in the order of size"; not found by size-based search "within 20 minutes" | INFERRED 2.6×10^12 syntactic terms up to size 19 |
| TRANSIT Fig. 5 (~20 typed functions, 10 examples) | expressions explored | pruned is "two to three orders of magnitude fewer" above size 10; exhaustive > 3.5 GB above size 10 | 100–1000× |
| QuickSpec (pretty-printing combinators, 3 variables) | terms of size ≤ 9 | "approximately 10^6 terms"; building only from representatives "goes down 10^6 to 10^4" | 100× |
| Exhaustive Symbolic Regression (8 operators, complexity ≤ 10) | expression trees | "5.2 million of these are valid trees, and 134,234 of these are unique" | 39× (symbolic, not OE) |
| Duet Table 2 (SyGuS grammars) | OE components up to size n | Bitvec: n=3: 464–485; n=4: 1,786–1,890; n=5: 44,023. String: n=2: 13–27; n=3: 46–118; n=4: 238–422. Circuit: n=5: 1,217–2,282; n=8: 8,968–31,086; n=11: 4,717 | — |
| FrAngel (~100 Java components, typed, no OE) | programs per size | 30K (size 5), 800K (size 6), > 10M (size 7) | none applied |
| Codish (36 comparators, 9 channels) | networks modulo symmetry + subsumption | 1, 3, 7, 20, 59, 208, 807, 3,415, 14,343, 55,991 … versus 36^k | at k = 10: 3.7×10^15 → 5.6×10^4 |
| Knuth (5 variables, all binary gates) | distinct functions by minimum gate count | 12; 100; 1,140; 11,570; 109,826; 995,240; 8.4M; 63M; 384M … | — |
| icecuber (142 unary image transformations) | time per extra depth | ×15 (depth 2 → 3), ×20 (3 → 4) | versus ×142 raw |

URLs: Probe https://arxiv.org/abs/2010.08663 ; QuickSpec https://www.cse.chalmers.se/~jomoa/papers/quickspec-JFP.pdf ; ESR https://arxiv.org/abs/2211.11461 ; others above.

**Effective branching factor per AST node after dedupe (INFERRED from the table):**
- ~6 productions (Probe toy): 2.0–2.9 per node measured at sizes 8–10; 2.3 from size 10 to 19. Raw syntactic growth for the same grammar is about 5.4.
- ~10 productions (circuits; sorting networks; Boolean chains): about 2–4.
- ~20–30 productions (SyGuS string / bit-vector): 3.5–4.5 (string), 4–24 (bit-vector) between consecutive sizes.
- ~100–150 primitives: 12–27 raw typed (FrAngel), 15–20 after dedupe (icecuber).
- Massalin: about 5.5 per instruction with a restricted instruction table.

### D2. Programs (candidates) per second, as stated

| System | Rate | Conditions | Source |
|---|---|---|---|
| Massalin 1987 | 50,000 programs/s (40/s with exact Boolean test) | native execution, a few test vectors, 16 MHz 68020 | VERIFIED |
| STOKE 2013 | > 50,000 proposals/s peak; ~500,000 test-case evaluations/s | x86-64 emulator, per core | VERIFIED |
| AutoML-Zero 2020 | 10,000 models/s/core | each model is trained on small tasks | VERIFIED |
| FrAngel 2019 | 5,300 (FrAngel), 14,000–31,400 (random) programs/s | Java reflection, programs with loops | VERIFIED |
| SyPet (per FrAngel) | 37 programs/s | SAT/ILP in the loop | VERIFIED |
| Eco / Bee Search 2025 | ~0.8–1.1×10^5 programs/s | Python, **generation only, no evaluation** | VERIFIED |
| Bustle baseline (Java) | ~3×10^5–10^6 candidates/s | strings, 2–4 examples | INFERRED |
| Python vs Java for the same enumerator | 9× | CrossBeam | VERIFIED |
| QuickSpec 2 | ~20 terms/s (50,000 terms, 874,000 tests in 42 min) | Haskell, random testing + rewriting, 33 functions | VERIFIED numbers, INFERRED rate |
| ESR | complexity 10 with 8 operators: 46 min on 196 cores | sympy simplification | VERIFIED |

### D3. Largest size exhaustively covered in a stated time (VERIFIED unless marked)

- TRANSIT: size 15 in 2–13 min, size > 20 not in 30 min (~20 functions, 4 types).
- Probe size-based baseline: a size-19 solution over a 6-production grammar not reached in 20 min.
- EUSolver (Python, ~28-production string grammars): solutions of size 9–12 in 16–46 min.
- Probe at 1 hour on bit-vectors (Simba's run): average solved size 6.5–7.9.
- Duet: enumerated components of size ≤ 7 suffice for 92% of solved tasks; maximum 12 (circuits).
- TF-Coder: 5 operations / 11 nodes in 65 s over 134 weighted, heavily filtered operations.
- QuickSpec: all terms to size 7 over 33 functions in 42 min; size 8 only with 26 functions and 2 hours; ran out of memory otherwise.
- icecuber: depth 3 of 142 transformations everywhere, depth 4 for about half the tasks in a 9-hour budget.
- Massalin: 12 instructions in several hours (tiny instruction table). GNU superopt: 4–5 instructions practical, 7 took weeks. Lens: ≤ 5 ARM instructions in an hour.
- Knuth: every 5-variable Boolean function up to 12 gates. Codish: all 9-channel networks to 25 comparators in ~12 days on 144 cores.

### D4. ESTIMATE TABLE — MY ESTIMATE, not a published result

Question: single-threaded, exhaustive-ish bottom-up enumeration with OE dedupe; what total AST size (nodes, leaves included) is covered?

Model: cumulative candidate evaluations to exhaust size s ≈ r · b^s, so s ≈ ln(E·T / r) / ln(b).

Assumptions:
- E = 10^6 candidate evaluations per second (construct + evaluate on all examples + hash). Anchors: Bustle Java inferred 3×10^5–10^6; Massalin 5×10^4 on 1987 hardware; STOKE 5×10^4–5×10^5; Python generation-only 10^5. A metered interpreter could be 10× lower.
- r = 30 candidates evaluated per retained class. Anchors: 5.3× (Probe height 1), 39× (ESR), 62–264× (Probe sizes 8–10), 100× (QuickSpec), 100–1000× (TRANSIT).
- b = effective per-node branching after OE: 3 for ~10 primitives (range 2.3–4), 6 for ~30 (range 4–10), 15 for ~100 (range 10–25), from D1.

Arithmetic: E·T/r = 3.3×10^4 (1 s), 2×10^6 (1 min), 1.2×10^8 (1 h), 1.2×10^9 (10 h); natural logs 10.4, 14.5, 18.6, 20.9; divide by ln b = 1.10, 1.79, 2.71.

| Primitives | b | 1 s | 1 min | 1 h | 10 h |
|---|---|---|---|---|---|
| ~10 | 3 (2.3–4) | 9.5 (7.5–12.5) | 13 (10.5–17) | 17 (13–22) | 19 (15–25) |
| ~30 | 6 (4–10) | 6 (4.5–7.5) | 8 (6–10.5) | 10 (8–13) | 12 (9–15) |
| ~100 | 15 (10–25) | 4 (3–4.5) | 5.5 (4.5–6) | 7 (6–8) | 8 (6.5–9) |

Parenthesised ranges vary b only. A 10× change in E or r shifts every cell by 2.1 nodes (b = 3), 1.3 (b = 6), 0.85 (b = 15). For binary-operator languages, operations ≈ (size − 1) / 2.

Checks against verified outcomes:
- ~30 primitives, ~0.5 h: model 9–10; EUSolver in Python reached 9–12 in 16–46 min; Probe at 1 h averaged 6.5–7.9 on solved bit-vector tasks. Consistent to ±2.
- ~10 primitives, 20 min: model ~16 (with E = 10^5, b = 2.3: ~18); Probe's Scala baseline had not reached size 19. TRANSIT reached 15 in ~10 min. Consistent.
- ~100+ primitives: model 5.5 at 1 min; icecuber reached 3–4 unary steps (with expensive image operations); TF-Coder's plain-TRANSIT variant solved 39 / 70 tasks where 51 / 70 need ≤ 3 operations (≤ 7 nodes). Consistent. TF-Coder's 11-node result relies on weights and 98.6% filtering.

**Memory binds before time.** Retained classes = E·T/r = 1.2×10^8 at 1 hour. At ~100 bytes per class that is ~12 GB. Evidence that memory is the real wall: TRANSIT exhaustive > 3.5 GB at size 10; Escher without OE hits a 1 GB limit; QuickSpec "starts to run out of memory" at size 8; MagicHaskeller's "tens of gigabytes" table; icecuber depth 4 needs 20× the memory of depth 3 within 16 GB; Eco Search peaks at 5.4 GB in 300 s. On a 16 GB machine the 1-hour column is effectively the ceiling; the 10-hour column needs ~100 GB or a bank-free search that gives up OE.

### D5. What do hours buy that seconds do not?

Model answer (INFERRED): 3,600× more time adds ln(3600)/ln(b) nodes: about 7.5 nodes at b = 3, 4.6 at b = 6, 3.0 at b = 15. Going from 1 hour to 10 hours adds 2.1, 1.3, 0.85 nodes.

Verified evidence, all pointing the same way (roughly logarithmic returns, about one more operation per decade of time, and flat tails):
- CrossBeam Table 1, unguided Java OE enumerator, 127 string tasks: 74 solved at 3.4 s → 91 at 30 s. About 9× time for 17 more tasks (+23%).
- CrossBeam App. C, Bustle: 59 / 127 at 50K candidates → 94 / 127 at 1M candidates. 20× budget for +35 tasks.
- TF-Coder: 63 / 70 at 5 min; raising to 1 hour (12×) adds 2 (at 31 and 58 min); the other 5 "simply too difficult ... within an hour."
- FrAngel: 47% at 10 s → 94% at 30 min (180×), on tasks with median size 11.
- icecuber: depth 2 → 3 costs 15× and depth 2 already solves "about 80% as many tasks"; depth 3 → 4 costs 20× time and memory and could only be afforded for half the tasks in 9 hours.
- Probe: EuPhony solves 23 / 82 in 10 min here and "27 of the 82 benchmarks ... with a 60 minute timeout" in its original paper (different machines). CVC4 "still solves new benchmarks long after Probe and EuPhony have plateaued", by emitting huge case-split programs.
- cvc4sy at 1800 s: enumerative strategies lead at short times "but then EUS solves more benchmarks in the end", i.e. the long tail is won by decomposition, not by more enumeration.
- Duet: a size-18 string program "cannot be found even within 6 hours" by OE enumeration; Duet's Table 2 lists a size-18 phone-number task solved in 0.03 s with components of size 1 (|C| = 13).
- GNU superopt: length 5 practical, length 7 "several weeks". Lens: 3 instructions in an hour for the earlier enumerator. Massalin: 3 instructions at 40/s, 12 at 50,000/s (a 1,250× faster test, plus pruning, bought 9 instructions on a tiny instruction table).
- Bee Search uses a 120-minute limit and EUSolver 3,600 s, but the gains over time are only in plots I could not read.

Typical timeouts found: 1 min (Synthphonia, Souper), 2 min (Synquid, SMyth, Burst, Trio, SyRup), 100 s (Heap Search), 5 min (Escher, TF-Coder, Eco Search), 10 min (λ², Probe, DryadSynth, AGI-09 comparison), 30 min (TRANSIT, FrAngel, cvc4sy, STOKE), 1 h (EUSolver, Duet, Simba, Lens), 2 h (Bee Search, QuickSpec stress test). Nothing in this slice reports a single-threaded enumerative run longer than about 2 hours per task, apart from the superoptimiser anecdotes ("several hours", "several weeks") and the cluster-scale exhaustive results (Knuth, Codish, AutoML-Zero).

What actually moved the frontier in these papers was not time: OE (100–1000×), type/shape filtering (98.6% in TF-Coder; λ² without types times out almost everywhere), per-task curated grammars (Probe's baseline 42 → 9 when grammars are merged; Myth 0.07 s → 128 s with five extra functions), divide-and-conquer on examples (EUSolver 787 vs ESolver 1 of 852), and top-down decomposition (Duet, Simba).

---

## Could not verify online today

- Denali: no primary or secondary source reached; description FROM-MEMORY, no numbers given.
- GNU superopt: only the tool's README (embecosm mirror) was checked, not the 1992 paper's tables.
- MagicHaskeller: per-depth counts of expressions before/after equivalence filtering (Katayama PRICAI 2008) and the component-library size. Only the 2013 demo paper, Hackage page and AGI-09 table were read.
- IGOR2: the algorithm description is FROM-MEMORY; in the AGI-09 table the timeout symbol was lost in text extraction, so which cells are timeouts is uncertain.
- SyGuS 2013 extended report tables (expressions enumerated per benchmark for ESolver): not reachable; the 6-page FMCAD version has charts only.
- Bustle's unguided-baseline throughput: inferred from axes and CrossBeam's table, never stated as a rate. The Bustle paper's own baseline solve counts are in figures only.
- Heap Search, Probe, Bee Search, EUSolver, cvc4sy cactus-plot curves: images; only the textual statements are verified.
- Souper's later enumerative synthesiser with dataflow pruning: FROM-MEMORY.
- Hardware for TF-Coder and Synquid experiments: not found in the text I searched.
- Trio's POPL 2023 numbers: I read the extended JFP 2025 version (65 benchmarks); the POPL abstract's "98%" figure was seen only in a search snippet.
- Eco Search: numbers are from the arXiv version fetched today (marked under review at JAIR); the AAAI 2025 version may differ.
- Knuth: read from the draft pre-fascicle 0C, not the printed Volume 4A.
- Probe grammar syntactic term counts, all effective branching factors, and the whole estimate table are my own arithmetic.
