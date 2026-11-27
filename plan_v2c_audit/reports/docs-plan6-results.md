# docs-plan6-results — audit report

Auditor scope: `deprecated/plan5.md`, `deprecated/plan6.md`, `deprecated/plan6-refactor.md`,
`deprecated/results.md`, `deprecated/results-history.md` (all read in full), cast against
`plan_v2_prompt.md`. Code tags come from a grep of the root kernel (`*.lisp`, `milestones/`,
`tests/`) on branch `reflective`; I did not run anything.

Conventions: `RH` = results-history.md, `R` = results.md, `P5` = plan5.md, `P6` = plan6.md,
`PR` = plan6-refactor.md; `L123` = line number. "wu" = work units of the tariff in force in
that document. Items marked **[inference]** are my arithmetic or reading, not a statement in
the documents.

---

## 0. What these five documents are, and when

| Document | Content dated | Kernel it describes | Owner's own commit-message verdict |
|---|---|---|---|
| results-history.md | 2026-10-27 (rev `f6bf54ef`) | first "Astra" VM, plan4 M1–M2, byte encoding v1 + bit pilot v2 | "needs critical review" (861424f) |
| results.md | 10-27 … 10-29 | same VM, plan4 M1–M4, encoding v7 / tariff v8 | "law results - not validated" (6adc80e); "milestone dispatched, though needs verification / auditing" (cd68027); last commit: "going to transition to a homoiconic kernel, rather than the bloated VM Astra designed" (c3709ad) |
| plan5.md | text 29 Oct, committed 10-30 | proposal only: 7-module homoiconic rewrite | "adding the refactored plan - needs auditing" (d48fade) |
| plan6.md | 10-30 … 11-03, 12 commits | the rewritten homoiconic kernel, M1–M9 as spec + test inventory | "milestones 1-4 check out, need to do 5, 7, 8 (6 is already mostly done)" (a23e454); "M5, m6 done" (940cb0a); ":at … tests pass, though this one has not been checked" (596eb13) |
| plan6-refactor.md | 11-03 | post-audit corrections to the plan6 kernel, tariff v9 | "astra refactor - need to cross-check" (9cb88c9) |

All five were moved to `deprecated/` on 11-04 / 11-09. Two different kernels are described:
R/RH measure the *pre*-homoiconic scaffold (16 files, ~2,600 LOC per P5 L15); P6/PR describe
its replacement. **Only RH and R contain work ledgers; P6 contains almost no cost numbers of
its own** (it re-quotes R's M1/M4 numbers and gives bit sizes for M5/M7) and PR contains
none. Only RH contains wall-clock times. So the measured record is thin and almost entirely
about M1–M4 on the discarded scaffold.

A keyword census of the five files is itself a finding: zero occurrences of *intervention*,
*embedding*, *topology*, *reentran-*, *crash*, *non-terminat-*, *hours*; "reflect" and
"policy" occur once each in unrelated senses ("tariff policy"); "geometr-" occurs only as a
TikZ library name; "metric" only as "Resource Metrics"; "distance" five times, all in the M7
locality scheduler. The owner's geometry, reflection, reentrancy and language concerns are
simply not present in this stratum of the trail; what is present is the topology half
(fibers, pullback, reorientation, partitions, laws) in frame vocabulary.

---

## 1. Idea ledger (chronological)

Status vocabulary: BM = built and measured, B = built (tests only, no cost numbers), BR =
built then removed, P = proposed never built, S = superseded. Code tag = current root kernel.

### Stage A — 27 Oct, first VM, M1–M2 (results-history.md)

| # | Idea | Where | Status / numbers | Code tag |
|---|---|---|---|---|
| A1 | `Frame(schema, rows)`; row = `key`, `known`, `allowed`; keys never enter the predictor | RH L102-105; R L59-63 | BM | STILL-IN-CODE `frame.lisp:7,12` (`allowed` is now `requirement`; frame has since grown `pairs anchors metric edges`) |
| A2 | Two requirement forms: `finite-allowed` (whole values; correlated tuples not split) and `predicate-allowed` (Boolean AST over var 0) | RH L165-167; R L251-272 | BM; S by one Boolean S-expression requirement (P5 §1.3 L51, P6 §1.3 L93-99) | GONE as two types; constructors `set-requirement` etc. survive |
| A3 | Pullback: child requirement = parent requirement composed with a *supplied* decoder and input bindings; `compose-model` re-inlines the child | RH L169-192; R L274-315 | BM (child search 3,892 wu + 4,230 pullback/compose/replay, R L466-467) | STILL-IN-CODE `frame.lisp:544`, `:839` |
| A4 | A fiber is an implicit predicate, never an enumerated inverse set; "a fiber describes compatible values; a residual is a particular value or index retained for reconstruction" | RH L179-187 | principle, kept | holds |
| A5 | Reorientation of recorded tuples without re-simulation (`orient-observations`) | RH L258-262; R L201-203 | BM | STILL-IN-CODE `frame.lisp:342` |
| A6 | Paid lookup tables; quotient (representatives + per-occurrence index) and partition (groups + inverse permutation) views, reconstructed by `gather` | RH L201-217; R L317-328 | BM | STILL-IN-CODE `frame.lisp:392,1419,1443,1463,1473` |
| A7 | Exact-size bottom-up enumeration with (type × size) buckets, retaining every syntax tree; resumable cursors | RH L235-283 | BM (scaling table, §2.2) | STILL-IN-CODE `enumerate.lisp:353,558` |
| A8 | Abstract work tariff + ledger; interruption / resumption / extension; unit-step vs batch parity | RH L298-365 | BM | STILL-IN-CODE `vm.lisp:10`; tariff now v10 (`vm.lisp:7`) |
| A9 | Batched charging | RH L367-413 | BM: 1.83–1.87× on whole searches; 3,300× on one 4096-bit multiply | n/a |
| A10 | Runtime compilation of validated DSL expressions to host Lisp, break-even `C_compile < N(T_int − T_comp)` | RH L459-482; R L1625-1645 | P, deferred twice, never measured (**dropped for convenience**: "would need budget checks and resumable state") | later built in another form: `vm.lisp:87,439` (`*closure-evaluation*`, `expression-closure`) |
| A11 | Messages = (call-id, claim, evidence); `:bounded-exhaustion` vs `:cutoff`, neither a refutation | RH L303-309 | B | STILL-IN-CODE `enumerate.lisp:219` |
| A12 | Typed aligned anti-unification with repeated holes and operator holes | RH L97; R L330-408 | B (reference-checked on 64 GF(2) pairs) | STILL-IN-CODE `unify.lisp:36` |
| A13 | Output-vector buckets as observed equivalence; invariants = equal across supplied `pairs`, varying across supplied `starts` | RH L525-584; R L478-628 | BM | STILL-IN-CODE `enumerate.lisp:569,704,728,731` |
| A14 | Observation *scope*: agreement is a fact about a row set + grammar + versions; adding rows makes a new scope, old one stays true | RH L573-578; R L511-518, L582-589 | BM (x vs x·x split) | STILL-IN-CODE `enumerate.lisp:569` |
| A15 | Byte encoding v1 → compact bit encoding v2 with a special arithmetic profile → single prefix code v7 | RH L676-819; R L50-55, L94-130 | BM; byte branch and profiles BR ("ran into problems with integers", commit 7446706) | STILL-IN-CODE `codec.lisp:7` (v7) |
| A16 | Declared literal vocabulary | RH L595-601, L645-648 | BM | STILL-IN-CODE (`make-language :literals`) |
| A17 | Counterexample-as-data: "counts the rejection without learning a generalized explanation" | RH L285-290 | P (explanation learning) | later: `nogoods.lisp`, `explain.lisp` exist (outside my docs) |

### Stage B — 27–29 Oct, first VM, M3–M4 (results.md)

| # | Idea | Where | Status / numbers | Code tag |
|---|---|---|---|---|
| B1 | A law is executable DSL data `if(guard, lhs=rhs, true)`; each bucket proposes member = first representative (avoids all-pairs) | R L632-638 | BM | STILL-IN-CODE `laws.lisp`, `milestones/algebra-discovery.lisp` |
| B2 | Exhaustive finite-domain validation → certificate bound to equation, guard, schema, domain, versions | R L640-648 | BM | STILL-IN-CODE `laws.lisp:96,178` |
| B3 | Normalizer whose every rewrite strictly decreases (packet length, then lexicographic bits): "prevents commutativity cycles without requiring confluence or an e-graph" | R L668-676 | BM | STILL-IN-CODE `laws.lisp:313-407` |
| B4 | Rewrites require *syntactic* provable totality of every substituted subterm; "never infers totality from the sampled input rows" | R L672-676 | BM | STILL-IN-CODE `ast.lisp:1160` |
| B5 | Guards discharged only by literal truth or the enclosing branch condition | R L678-694 | BM | STILL-IN-CODE (`rewriting` task `:choose`, `laws.lisp:364`) |
| B6 | Guard discovery from retained per-row outcomes: membership vector of "both defined and equal" per expression pair → Boolean `support-frame` → ordinary synthesis; pairs grouped by identical subset | R L696-795 | BM (table §2.1) | STILL-IN-CODE `frame.lisp:1397`, `milestones/algebra-discovery.lisp:167,200,209` |
| B7 | Lossless law-corpus compression: AU template → fragment dictionary + occurrence sequence, `concat(gather(dict, occ))`, accepted through the ordinary search as a listed proposal | R L797-899 | BM (34 % / 29 %) | STILL-IN-CODE `milestones/corpus.lisp:202,219`; `law-compression.lisp` GONE |
| B8 | Shape-grouped AU ("a supplied structural view") | R L840-846 | BM, loses to the single global template | STILL-IN-CODE `milestones/corpus.lisp:162` |
| B9 | Quoted syntax as a first-class value `(:code inputs sort)` + nine `code-*` primitives; explicitly **no DSL `eval`** | R L905-948 | BM | STILL-IN-CODE `vm.lisp:172-195,516-518`; **but `:code-eval` now exists** (`vm.lisp:338,436,503`) |
| B10 | Checked laws lowered to DSL transformer programs (`compile-rule-transformer`); per-library preparation cache | R L950-992 | BM (65.2 % less than the uncached version, still a net loss) | STILL-IN-CODE `laws.lisp:284` (same `code-match` + k×`code-bind` lowering) |
| B11 | AU template lowered to a typed constructor program (`compile-au-constructor`) | R L377-388, L994-1010 | BM (247-bit constructor replays 2,306 / 6,229 laws) | STILL-IN-CODE `unify.lisp:103` |
| B12 | Ordinary search over symbolic programs; "residual route": pull a rewrite task back to an integer selector | R L1012-1037 | BM (selector `0` at a 15-bit bound; 324/416-bit composed transformer) | STILL-IN-CODE test `tests/symbolic.lisp:170` |
| B13 | Checked-rule search: reuse witnessed rejections of the normal form | R L1039-1084 | BM, **net loss** | STILL-IN-CODE `enumerate.lisp:472` (`rewrite-filter-step`) |
| B14 | Solver discovery: forward table + learned definedness guard → reorient twice keeping the forward predicate `R(k,c,z)` → enumerate witness `q(k,c)` under a max-coverage prior → guard via a computed-feature frame → two laws (witness, uniqueness) | R L1146-1246 | BM (table §2.1) | STILL-IN-CODE `milestones/algebra-discovery.lisp:49,259,276,298` |
| B15 | Propagator: under a certificate and a true guard, replace a child predicate by the singleton `z = q(k,c)`; otherwise keep the predicate | R L1117-1144, L1329-1343 | BM, net loss on small fixtures | STILL-IN-CODE as `propagate-requirements` `laws.lisp:736`; `propagate-arithmetic-child` GONE |
| B16 | Propagator selection by a DSL structural matcher (`compile-propagator-matcher`), linear library scan, first applicable rule | R L1248-1303 | BM (735-bit matcher; 5,237 cold / 2,705 warm wu) | matcher functions GONE; `propagator-library` `laws.lisp:453`, `propagator-rules-for` `:658` |
| B17 | Tentative (uncertified) witness use: preferred frame with singleton targets + retained original frame, every 4th quantum to the original, forward re-verification | R L1371-1457 | BM (−79.3 % only with 2^128 operands) | STILL-IN-CODE `milestones/propagation-search.lisp:50-58` |
| B18 | Adaptive scheduling of "check a rule / use a propagator / keep enumerating" | R L1086-1090 | P — "deferred until larger problems expose its costs and benefits" (**convenience**; larger problems were never run) | not in these docs |
| B19 | Richer fiber representations: interval descriptions of integer-division fibers, an explicit "no solution" value | R L1242-1246, L1618 | P (**convenience**) | not found |
| B20 | Learned code (frequency learning, dynamic code allocation, named definitions) | R L52-55 | P, "deferred" | later `knowledge.lisp` (outside my docs) |
| B21 | Grouped generator for conservation: sample `G(k,u)=(u,k−u)`, vary `u` inside a supplied group `k` | R L499-507 | P — "an alternative fixture, not an additional experiment reported here" (**convenience**) | not found |

### Stage C — 29/30 Oct, plan5.md (proposal only)

| # | Idea | Where | Status | Code tag |
|---|---|---|---|---|
| C1 | Diagnosis: tagged ASTs + a second `:code-*` sub-language; six hand-rolled state machines; three engines for pullback/rewrite/propagation; four mechanisms for AU/lowering/quotient/law-compression | P5 §1 L13-53 | diagnosis | partly still true: 9 resumable state structs today (`evaluation`, `row-job`→`search-job`/`observation-job`, `law-validation`, `rewriting`, `synthesis-job`, `heuristic-search`, `dependency-search`, `propagation-search`) |
| C2 | Everything is three operations over one frame: observational conservation, factorization (inverse of Apply), causal reorientation + pullback | P5 §2 L55-181 | S by P6's four operations | conceptual |
| C3 | The single object is the outcome matrix `M(e,ω)`; M1 synthesis, M2 equivalence, M2 invariants, M3 laws, M3/4 guards are five queries on it, so "there is only one evaluation engine" | P5 §2.1 L118-132 | B in the plan6 kernel (shared enumerator) | STILL-IN-CODE `enumerate.lisp:231` (`row-job` base) |
| C4 | Homoiconic S-expressions against a lexical schema; one substitution function | P5 §3 Ex.1 L185-201 | B | STILL-IN-CODE `ast.lisp:561-582` |
| C5 | O(1) cached `(body-bits . lex-rank)` so rewrite ordering is one integer compare | P5 Ex.2 L218-220 | B as `*node-meta*`; PR L211-212 corrects: `body-size`/`description-size` "must not be described as constant-time" | `ast.lisp:32` |
| C6 | Rules applied directly on S-expressions, matching once (`apply-rule`, `match-expr`, `subst-expr`, `expr-less-p`) | P5 Ex.2 L221-238 | **P — never built**; the kernel still lowers each rule to `code-match` + one `code-bind` per variable + `code-subst` + `code-less` | NEVER-BUILT; contrary code at `laws.lisp:284-311` |
| C7 | Propagation *is* guarded law rewriting + constant folding of the pulled-back checker; "`propagation.lisp` disappears into `laws.lisp`"; nested decoders "for free" | P5 §2.3 L174-181, Ex.3 L240-288 | BR/S — rejected for cause in P6 App. A.2 #2 (unsound for tentative integer witnesses), but the certified-field case, where it *is* valid, was dropped with it | separate propagator library remains `laws.lisp:448-760` |
| C8 | One `job` struct and one `advance-job` loop for all resumable work; schedulers are queues of jobs | P5 Ex.5 L309-338 | **P — never built** | NEVER-BUILT (no `advance-job`) |
| C9 | 16 files / ~2,600 LOC → 7 modules / ~900 LOC | P5 §4 L340-352 | built as 7 modules of ~4,600 LOC (P6 L454); now 27 files / 17,656 LOC + 1,585 in `milestones/` | — |
| C10 | Lifting = pullback where a withheld coordinate shows up as contradictory requirements on the same child input | P5 §5 L358-360 | B (P6 M5 control) | STILL-IN-CODE `frame.lisp:300` |
| C11 | Conflicts as a requirement folding to `nil` (tuple injectivity; same-input conjunction) | P5 §5 L371-373 | B | STILL-IN-CODE `frame.lisp:254,300` |
| C12 | Keep encoding v7 and the tariff bit-exact through the rewrite | P5 §6 L378-383 | done | owner now says he is "not at all strict about keeping the tariffs similar" |

### Stage D — 30 Oct – 3 Nov, plan6.md

| # | Idea | Where | Status | Code tag |
|---|---|---|---|---|
| D1 | Theme: "many levels of conservation, interacting through different views of the same data and meta-data, equipped with algorithms for inferring hidden or aliased information"; movements Symmetry → Algebra → Views | P6 L17-23 | framing | — |
| D2 | Four operations (adds Op 4, lossy heuristic condensation, to P5's three) | P6 L30-34, §2 | framing | — |
| D3 | Requirement = unary Boolean S-expression in var 0, closed over the row's inputs; four standard shapes (singleton, member-set, support indicator, pulled-back/conjoined) | P6 L93-99 | B | STILL-IN-CODE `frame.lisp:7` |
| D4 | `pairs` (must-agree) and `anchors` (must-vary) as row linkages *computed* from any partition, view or fiber clustering, as O(m) chain links | P6 L101, L220-225 | B | STILL-IN-CODE `frame.lisp:1487,1513`; `fibers.lisp:166` |
| D5 | Pullback (exact preimage of a predicate, always exists) vs right-inverse/section (constructive choice); factorization as a right-inverse of Apply chosen by description length | P6 L191-195 | conceptual, sound | — |
| D6 | Decoder = any well-typed expression + a context-projection map `bindings`; four decoder classes (outer shell, conditional view shell, AU constructor, latent-concept wrapper) | P6 L196-205 | B (all decoders supplied) | STILL-IN-CODE `synthesize.lisp:8` (`decomposition`) |
| D7 | `fold-constants` inside pullback: fold closed subtrees once, Boolean identities, tuple-equality injectivity, `:at` β-reduction, **1-D and 2-D literal-table inversion** | P6 L400-406, App. A.2 #1 | B; table inversions **BR** (PR L35-38: "also changed errors into false and was unsafe under negation") | `requirements.lisp:529`; docstring L531 "No table inversion" |
| D8 | `frame-conflict-p`: `:unsatisfiable-row`, `:incompatible-rows`, before any child enumeration | P6 L409-413 | B | STILL-IN-CODE `frame.lisp:258,300` |
| D9 | Dual-grade propagation: certified ⇔ replaces in place; tentative ⇐ runs 3:1 against the un-narrowed frame | P6 L415-429, App. A.2 #2 | B (numbers are R's) | STILL-IN-CODE `milestones/propagation-search.lisp:55` |
| D10 | `infer-fibers` ("Hard-EM"): Stage A same-input tightening + conflict-free single-coordinate projection search; Stage B branch-and-bound over compatible groups (min K, then bits, then concentration); Stage C computed pairs/anchors | P6 L375-383, App. A.2 #3 | B; PR L57-60, L233-234 demotes it: "bounded combinatorial proposal search, not Hard EM", objective "a lexicographic proxy, not global MDL or entropy", singleton fallback under a branch cap | STILL-IN-CODE `fibers.lisp:12,156` (budget 1e6, branch-limit 2048) |
| D11 | `condense-heuristic`: learn a control program by MDL with *priced* exceptions (position bits + value bits per miss), then **drop the exception table at deployment** behind a 1-in-4 canonical reserve | P6 L433-448 | B (one toy test: 7 clean rows + 1 corrupted → `(mod X0 2)`) | STILL-IN-CODE `condense.lisp:24,81`; test `tests/lifting.lisp:46` |
| D12 | "Unaligned subgraph correspondence search" (`discover-subexpression-abstractions`) | P6 L369, §4.6 | B, no numbers | STILL-IN-CODE `milestones/corpus.lisp:704` |
| D13 | Law-normalized AU: normalize a corpus through a validated rewrite library before anti-unifying | P6 L721, L730 | B (5 holes → 2) | STILL-IN-CODE test `tests/milestones/corpus.lisp:330`; `abstraction.lisp` |
| D14 | Autonomous Boolean view discovery: enumerate guards, dedupe by behaviour and by complement, prune by conflict, assemble `:separate-parts` or `:shared-decoder` | P6 §4.7 L747-756 | B (bit sizes only) | STILL-IN-CODE `milestones/views.lisp:15,90,234` |
| D15 | Locality scheduling of occurrence pairs by distance in a *generated* coordinate space (ℓ1 on tuple coordinates, quotient-class agreement, 1-D position) from a priced `:locality-key` expression | P6 L757-759, L765 | B (pair budgets 1 and 6) | STILL-IN-CODE `milestones/corpus.lisp:464,509`; `proposals.lisp:625` |
| D16 | M8A multi-step chain through two supplied decoders; cross-prime AU of solvers to `(+ C (* ?coeff K))` | P6 L785-789 | B | not checked individually |
| D17 | M8B DAG memory: reuse a child when two decoders reduce to the same canonical requirement signature | P6 L790-791 | **over-claimed**: PR L213-214 "This refactor does not add cross-problem DAG reuse" | later: `synthesize.lisp:264` `child-scope-signature`, test `tests/refactor.lisp:486` (after these docs) |
| D18 | M8D learned search preferences: condense shrunk continuation returns `G_t = B_t − B_T − λ(W_T − W_t)` into a priority program | P6 L782, L795-796 | **P** in these docs (only the toy parity test exists); PR L87-89 "learned scheduling policies are not implemented" | later work (`tests/refactor.lisp:427`) outside my docs |
| D19 | M9 vocabulary: learned functions under opaque symbols `F0…`, behavioural probe signatures + "algebraic property bits", descriptors condensed from probe tables, 3:1 retrieval | P6 §4.9 L800-812 | **P** — no test or result listed in P6 | later `descriptors.lisp` (1,045 lines; `canonical-probe-codes` L285, `derive-compositional-name` L164) |

### Stage E — 3 Nov, plan6-refactor.md

| # | Idea | Where | Status | Code tag |
|---|---|---|---|---|
| E1 | Keep false / error / unresolved distinct everywhere; conservative folder | PR L10-11, L28-43 | B | STILL-IN-CODE `requirements.lisp:529` |
| E2 | Dependency selection as an explicit, priced *proposal* (empty context, coordinate context, supplied or grammar-enumerated feature) instead of silently strengthening a frame | PR L12-13, L47-54 | B | STILL-IN-CODE `proposals.lisp:274`; `milestones/dependency-search.lisp:8` |
| E3 | Direct selector synthesis competes with fiber and dependency proposals | PR L14-15, L55-56 | B | STILL-IN-CODE `proposals.lisp:832` |
| E4 | Small resumable decomposition controller; a decomposition need not compress immediately; every child candidate is rebuilt through its ancestors and checked on the root frame; all child candidates retained for parent scoring | PR L66-80 | B | STILL-IN-CODE `synthesize.lisp:8,155,1278` (now 1,310 lines) |
| E5 | One cumulative budget owned by the caller (`with-work-limit`); "a cutoff is not a conflict" | PR L18, L22, L103-109 | B | STILL-IN-CODE `vm.lisp:20` |
| E6 | Scope-tagged child→parent messages carrying counterexamples, bounds, work | PR L81-89 | B; "learned explanations … not implemented" | `messages.lisp` |
| E7 | Learned table inversion "belongs in the library/proposal layer" | PR L237-238, L151-153 | B as one test | STILL-IN-CODE `tests/refactor.lisp:132` |
| E8 | Union of incompatible inverse observations into an existential fiber on reorientation | PR L218-220 | P — "remains explicit future work" | not found |

**Ideas dropped for convenience rather than for cause** (collected): A10 compiled execution;
B18 adaptive scheduling; B19 interval / no-solution fibers; B21 the grouped (intervention-style)
generator; C6 direct rule application; C8 one job abstraction; E8 existential fibers;
observational-equivalence pruning of the enumerator (R L227-228: "No observational
equivalence or algebraic rewrite prunes the syntax buckets" — a design stance, never measured
against the alternative; a grep of `enumerate.lisp` still finds no such pruning); e-graphs
(deferred in every one of the five documents: RH L522, R L672 and L1620, P5 none, P6 [R8]
only as literature, PR L5 and L196); evaluation-prefix caching on recheck (R L627-628).

---

## 2. The results record

### 2.1 Every reported experiment

Hand-supplied items are in the last column; "grammar" means the operator list, the variable
list and the literal policy were declared by the agent.

**First VM, byte encoding v1 (results-history.md)**

| Task | Found | Bound / size | Work, time | Hand-supplied |
|---|---|---|---|---|
| M1 GF(5) `y=a+2b`, 25 rows (RH L44-78) | nothing at 41 bytes; `a+(b+b)` + 9 others at 71 bytes | 71 bytes; 2,849 trees | 876,490 wu to finish the bound; first solution at 31,138; 0.024 s | grammar `{+,*}`, 2 vars, 5 literals; both bounds chosen by the script |
| same, compression check (RH L64-74) | formula 71 bytes vs literal output list 65 bytes: **formula does not compress** | — | lookup 375 bytes / 22,325 wu | — |
| Scaling: `a+2b`, `a+b(b+2)`, `a+b⁴` (RH L378-402) | planted targets reached | 71 / 101 / 131 bytes; 2,849 / 98,889 / 3,863,657 trees | 876,490 / 36,625,916 / 1,772,480,257 wu; 0.024 / 0.92 / 44.4 s; 328 MiB live, 67 GiB allocated | targets, bounds |
| M2 GF(5) invariant under `T(a,b)=(a+1,b+4)` (RH L535-571) | bucket `{a+b, b+a}` | 41 bytes; 105 exprs → 25 buckets | 108,840 wu (+1,270 +60) | transition pairs, two start rows, the conservation criterion itself |
| M2 integers `T=(a+1,b−1)` (RH L586-617) | `{a+b, b+a}` | 31 bytes; 55 exprs → 19 buckets | 41,204 wu | literal vocabulary restricted to `{-1,0,1}` because ">10^22 literal expressions are shorter than the 29-byte `a+b`" |
| Bit pilot v2 (RH L747-791) | same programs | M1 GF(5) 53 bits / 649 exprs / 250,320 wu; M1 int 36 bits / 435 / 79,411; M2 GF(5) 46 bits / 15 / 16,870; M2 int 31 bits / 27 / 18,990 | — | "The profiles and code allocation are supplied prior knowledge" (RH L734) |

**First VM, encoding v7 / tariff v8 (results.md)**

| Task | Found | Bound / size | Work | Hand-supplied |
|---|---|---|---|---|
| M1 GF(5) `y=a+2b` (R L412-467) | `a+(b+b)`, 59 bits (38 header + 21 body) + 9 others | 61 bits = size of the fixture oracle; 649 trees | 182,181 wu; first accept 22,727; lookup 315 bits / 28,750 wu; literal list 103 bits (different interface) | grammar, bound |
| M1 supplied pullback (R L416-417, L466-467) | child `b+b` | — | 3,892 + 4,230 wu | decoder `a+z`, child sees only `b` |
| M1 integers, `[-2,2]²` (R L469-476) | `a+(b+b)`, 44 bits | 44 bits; 9,243 trees | 1,089,220 wu; first accept at 1,018,877 | grammar (literals unrestricted) |
| M2 GF(5) / integers (R L591-616) | `{a+b, b+a}` | 50 bits: 15 exprs/13 buckets; 35 bits: 83/71 | 13,016 / 52,481 wu; 54-bit extension = all 105 single applications, 117,996 wu | pairs, starts, criterion (R L480: "The conservation constraint is supplied; the conserved expression is searched") |
| M3 laws GF(5) / GF(7) (R L650-664) | `a+0=a`, `a+b=b+a` among 80 / 136 "checked laws" | 54 bits; 105/25 and 171/35 exprs/buckets — **every side is a single application** | discovery 143,894 / 464,216; proposals 3,038 / 5,182; validation 222,298 / 739,762 | grammar `{+,*}`, two variables; stress candidate `x⁵=x` supplied |
| M3 supplied-guard control (R L678-694) | `x/x=1` under a **supplied** non-zero guard; rewrite `if(x=0,0,x/x) → if(x=0,0,1)` | 86 laws from 114 exprs / 22 buckets | 88,007 wu; one rewrite 5,792 + 65 | guard; grammar `{-,/,*}`; inputs restricted to non-zero |
| M3 guard discovery (R L696-795) | guard `if(x=0,false,true)` (54 bits; statement 92 bits) for `x/x=1`; 2,306 / 6,229 guarded laws | obs. grammar 42 bits, guard grammar 54 bits; 114/200 exprs; 16/31 distinct proper subsets; **only 6/8 subsets got a guard** | total acquisition 2,442,072 (GF5) / 7,888,859 (GF7): obs 32,280 / 78,294; grouping 614,321 / 2,250,037; guard search 877,566 / 2,491,741; validation 917,905 / 3,068,787 | two grammars and both bounds; one variable |
| M3 AU law compression (R L797-899) | global template `if(?guard, ?left = ?right, true)` | GF5 238,967 → 157,885 bits (−33.9 %); GF7 647,744 → 461,750 (−28.7 %); whole-packet dictionary is *worse* (303,967 / 832,568); shape-grouped AU ≈ literal (234,918 / 648,098) | construction 9,269,635 / 41,203,742; core search 17,206,870 / 46,809,871; decode costs ~1–3 % more than the literal | which trees to align ("the caller currently chooses", R L390); shape grouping; proposal list |
| M3 AU constructor (R L994-1010) | 247-bit constructor rebuilds every law from its hole fillings | — | exec 1,255,732 / 3,408,671; search 2,258,927 / 6,133,583 | hole fillings are inputs ("247 bits describe the constructor, not the entire stored corpus") |
| M3 symbolic selector (R L1019-1037) | child position `0` | 15-bit bound; transformer 324 (int) / 416 (GF) bits | selector search 7,335 / 14,087 | decoder that matches `term+0` and checks totality ("learning only the selector, not discovery of the entire rewrite") |
| M3 rule reuse in search (R L1041-1084) | 31 reused rejections | same 61-bit bound, same 649 trees | **182,181 → 740,452 wu** (was 2,126,539 before caching); saves 7,732, spends 545,921 + 19,536 | the single rule `a+0=a` |
| M4 solvers, 8 orientations × {GF5, GF7, Z} (R L1146-1246) | witnesses `c−k`, `k+c`, `k−c`, `c/k`, `k·c`, `k/c` — each **one application**; field guards `k≠0`, `c≠0 ∧ k/c≠0`; integer guards add `k·(c/k)=c`, `k/(k/c)=c` | numeric body bound 16 bits; Boolean body bound 35 bits | nine discoveries + validations: 28,784,653 (GF5), 79,382,348 (GF7), 54,995,245 (Z); shared forward tables 721,345 / 1,302,073 / 2,006,462 | `-` and `/` in the grammar; integer literals `{-1,0,1}`; integer grid −4…4; max-coverage "declared proposal prior"; the computed feature `(k,c,recovered-output)` is "a declared guard-search proposal"; which column is unknown |
| M4 weak grammar (R L1212-1217) | `c+4·k` (GF5), `c+6·k` (GF7), `c+(−1)·k` (Z) | 24-bit body bound, `{+,*}` only | included above | bound |
| M4 certified field reuse (R L1305-1369) | same child programs with or without propagation | — | child search 17,763 → 14,771 (−17 %) but **total reuse 19,338 → 21,514; worse in all 16 cells** | decoder with hidden `h(b)=b+1`; which operand is unknown |
| M4 integer tentative reuse (R L1411-1431) | same bounded result sets | — | first verified child 4,340 → 11,262; full search 7,847 → 21,612 (**worse in all 8 rows**) | as above |
| M4 expensive-context control (R L1433-1457) | child `g(b)=b·b+1` | 22-bit body bound; 7 rows, `a=2^128+i` | preparation + first verified child **2,193,913 → 454,724 (−79.3 %)**; preparation + full bounded search 2,973,192 → 3,522,367 (worse) | decoder `a·a+z`; literals `{-1,0,1}`; solver acquisition (55 M) excluded |
| M4 AU of 8 solver statements (R L1479-1492) | constructor with two holes | S = 256 bits (fields), 206 (Z) | W_run 5,327 / 3,622 | hole bindings supplied |

**Homoiconic kernel (plan6.md) — bit sizes and pass/fail only**

| Task | Found | Sizes | Work | Hand-supplied |
|---|---|---|---|---|
| M5 supplied lift, `y_{r,t}=a_{j(r)}+ι(t)` mod 7 (P6 L696) | child `(+ '1 (+ X2 X2))` | lifted program constant 105 bits over reps 1,2,4,8 (14–112 rows); lookup 249 → 1,689 bits; literal 69 → 370 bits (so the lift loses to the literal at reps = 1) | none reported | decoder `ι(t)+Z`; regime coordinate `j`; the conversion `ι` |
| M5 t-only control (P6 L697) | `:incompatible-rows` on `((:seq 0 0) (:seq 1 0))`; 0 solutions | — | none | which coordinate to withhold |
| M5 unsupervised (P6 L698) | K = 2 classes `(= Z '1)`, `(= Z '3)`; selector via lookup or `condense-heuristic` "with 0 residual bits" | — | none ("positive work savings from M4 propagation" asserted, not quantified) | decoder; PR L156-157: "Two lifting tests now make their intended coordinate projection explicit" |
| M5 integer (P6 L699) | 28 forward-verified suggestions; replay at 2^256 | — | none | decoder |
| M6 stage 4 (P6 L729, L737-738) | planted `(+ (* ?0 ?0) ?1)` recovered at paths `NIL`, `(1)`, `(0)`, `(1 0)`; 4 seeded random trials | beats literal / dictionary / root-AU at reps 2 and 4; negative gain on 2-tree corpora | none | the corpus (planted); pattern count = 1 |
| M6 stage 5 (P6 L730) | raw AU 5 holes → law-normalized 2-hole `(+ (* ?0 ?1) (* ?0 ?1))` | "reducing total AU bits" (no figure) | none | the two laws to validate; the disguised corpus |
| M7 views, integers, 28 rows (P6 L763) | parity guard `(= (- X0 (* (/ X0 '2) '2)) '0)`, "both supplied and grammar-discovered" | shared-decoder 101 bits / W_run 3,106; separate-parts 110 / 3,274; lookup 528 / 35,698 | none | guard grammar; shared decoder |
| M7 views GF(7) (P6 L763) | guard `(= '0 X0)` | shared-decoder 160 < lookup 224 < separate-parts 261 | none | as above |
| M7 shuffle / permutation (P6 L764) | identical model after shuffling; inverse permutation priced at 526 bits | — | none | — |
| M7 locality (P6 L765) | co-local match found at pair budget 6 where canonical order misses; distant match rescued by the 1-in-4 reserve; parity key gives adjacency at pair budget 1 | ΔS +5, +5, +116 bits | none | pair budgets; the parity key |
| M8A (P6 L785-789) | `(+ X0 (* X1 '3))` on 49 rows; constant child `'3` (7 body bits); cross-prime template `(+ C (* ?coeff K))` | — | none | both decoders, in order |
| M8B–D, M9 | — | — | none | described, not run (see D17–D19) |

plan6-refactor.md reports only "119 tests, 195,446 checks" (PR L162).

### 2.2 (a) Budgets, their exhaustion, the largest things found, growth

Statements about budgets, in the documents' words:

- "The experiment script chooses these limits" (RH L61-62) — every bound and work ceiling in
  every experiment is set by the agent per task, usually to the encoded size of the planted
  oracle (R L413-414: "extends to 61 bits, the encoded size of the fixture oracle").
- The only search ever allowed to run to a non-trivial size is the RH benchmark: 131 bytes,
  3.86 M retained trees, 1.77 × 10⁹ wu, 44 s, with a "default wall cap [of] 300 seconds per
  search" (RH L440). "The next five-operation bound, 161 bytes, would contain about 162
  million expressions … calculated, not a completed run" (RH L421-423). "The measured
  programs are still shallow; deep recursive synthesis remains untested" (RH L424).
- "Exhaustive retention also remains a scaling limit" (RH L421); "Checkpoints currently live
  in memory, and syntax retention grows with the bound" (RH L523).
- "Finite bit bounds still have exponentially many possible payloads; this pilot fixes the
  severe small-expression distortion, not general search growth" (RH L809-810).
- "Subsets without a solution at the stated bound remain unresolved. A larger bound or a
  different predicate vocabulary may express them" (R L763-766) — 10 of 16 (GF5) and 23 of
  31 (GF7) guard problems were left unsolved at 54 bits and are not revisited in these
  documents.
- "the historical scaling timings have not been reinterpreted under the new tariff"
  (R L1588-1589) — after 27 Oct there is **no wall-clock figure anywhere** in these documents.
- PR L114-119: published tariff work is bounded, "but does not preempt host Lisp traversals
  or guarantee a wall-clock deadline".

Growth rates:

- Enumeration, 2 variables, `{+,*}`, 5 literals (RH L388-402): trees ×34.7, ×39.1, then
  ×41.9 (calculated) per added operator; work ×41.8, ×48.4; time ×38, ×48.
  **[inference]** at that rate the fifth operator costs roughly 35 minutes and ~14 GiB of
  retained trees, and the sixth roughly a day and ~600 GiB: with this enumerator an "hours"
  budget buys one more operator, and memory, not time, is the first wall.
- Unrestricted integer literals: the same 2-operator program needs 9,243 trees and
  1,089,220 wu instead of 649 trees and 182,181 wu (R L464, L469-472).
- Field size: guard discovery ×3.2 from GF(5) to GF(7) (2.44 M → 7.89 M wu); the pair scan
  is quadratic in expressions (6,441 → 19,900 pairs, R L780); solver discovery ×2.76
  (28.8 M → 79.4 M), matching the p³ uniqueness check (R L1226).
  **[inference]** exhaustive certification is cubic in the field size, so the "certified"
  half of the system is confined to tiny primes.

Largest objects actually found by search:

- Programs: `a+(b+b)` (2 operators, 21 body bits) in M1; `c+4·k` (2 operators + literal,
  24-bit bound) in M4; `b·b+1` (22-bit bound) as a child; the M7 parity guard
  `(= (- X0 (* (/ X0 '2) '2)) '0)` (4 operators) is the largest single expression reported
  as "grammar-discovered", with no work figure.
- Laws: 76 and 83 bits (`a+0=a`, `a+b=b+a` as guarded statements, R L659-660); 92 bits
  (`x/x=1` with its guard, R L752-753). Both sides of every discovered law are at most one
  operator deep, over at most two variables.
- Guards: `if(x=0,false,true)` (54 bits total); the integer divisibility guard
  `k≠0 ∧ k·(c/k)=c` was not found by flat search but assembled from two searches through an
  agent-declared feature (R L1174-1188).

**[inference]** using RH's only rate (1.77 × 10⁹ wu in 44 s ≈ 4 × 10⁷ wu/s, a different
tariff, so order of magnitude only), the whole of M4 solver discovery for a domain (29–79 M
wu) is on the order of one or two seconds of search, and the largest compression search
(46.8 M wu) about the same. Current tests still top out at ceilings of 10⁷–10⁸ wu
(`tests/`, `milestones/`). The owner's statement that budgets were "very limited" is
quantitatively correct by three to four orders of magnitude against "hours".

### 2.3 (b) What algebra / law / solver discovery actually achieved, and its price

- **Laws**: identity and commutativity of `+` in GF(5) and GF(7) (R L658), plus ground and
  specialised equalities, from all 105 / 171 *single-application* expressions over two
  variables. "Counts include ground constant equalities and syntactic specializations; they
  do not mean 80 or 136 independent algebraic principles" (R L660-661). Price: 369,230 wu
  (GF5; R L1080-1081), ≈1.21 M (GF7). Associativity and distributivity are not reported
  anywhere in the five documents and are out of reach of a two-variable, one-operator
  grammar. The owner's "algebra emerges from … depth ≥ 2 experiments" was not attempted here.
- **Guarded laws**: one meaningful one, `x≠0 ⇒ x/x=1`, plus 2,305 / 6,228 others sharing six
  / eight learned support sets; 2.44 M / 7.89 M wu.
- **Solvers**: for each of `+ − × /` and each operand, which *single supplied operator*
  inverts it and on what support (R L1203-1210). "The richer main grammar explicitly supplies
  division; its multiplication solvers learn where to use that primitive, rather than
  learning modular reciprocal computation from `+` and `*`" (R L1215-1217); "the modular
  reciprocal inside division is host-implemented extended Euclid. Learning a solve expression
  that uses this primitive does not discover Euclid's algorithm" (R L1092-1095). Price: 29 M
  (GF5), 79 M (GF7), 55 M (Z) wu for nine solvers per domain — about 160× the GF(5) M1
  search (182,181 wu) and about 50× the integer one (1,089,220 wu) that such solvers are
  meant to accelerate.
- **Certification**: fields only. Integer witnesses stay conjectures; integer-division
  uniqueness is *refuted* (`z/2=1` admits 2 and 3; R L1238-1240).
- **Pay-back**: negative on every ordinary fixture (§2.4); positive once, on first-solution
  time with 2^128-sized operands, excluding acquisition.
- **Compression of the law set**: one skeleton `if(?g, ?l = ?r, true)` plus a dictionary of
  sides; "the gain establishes sharing of syntax across the law collection; it does not
  identify a basis of independent algebraic principles" (R L869-871).

### 2.4 (c) What failed outright, and the diagnosis given

| Failure | Numbers | Diagnosis in the document |
|---|---|---|
| A found formula is larger than the data it explains | 71 vs 65 bytes (RH L64-72) | "Much of the current encoding is punctuation and repeated type information" (RH L156) → codec replaced. Even after: the formula is a function, the list is an object; "it does not yet measure complete table compression" (R L460-462) |
| Integer search drowned by literals | >10²² literals shorter than `a+b` (RH L598-600) | encoding → v2; then literal vocabulary restricted again in M4 (R L1191-1192) |
| Checked rewriting slows search | 182,181 → 740,452 wu (R L1048-1053) | "The current lowering still repeats binding extraction and template substitution, including four extractions per successful application; most attempted matches fail" (R L1077-1079); P5 §1.1 blames the `:code-*` lowering; that lowering is still in `laws.lisp:284-311` |
| Certified propagation costs more than it saves | all 16 field cells (R L1349-1367) | "The savings come from cheaper requirement checks, rather than fewer enumerated candidates" (R L1340-1341); rule selection is charged |
| Tentative integer propagation costs more | all 8 rows (R L1417-1426) | "Additional verification and the retained branch cost more than they save here" (R L1414-1415) |
| Whole-packet dictionary and shape-grouped AU | worse than, or equal to, literal (R L862-865) | "More detailed shape-specific templates cost more here" (R L871-872) |
| Most guard problems unsolved | 10/16 and 23/31 (R L756-759) | bound / vocabulary |
| Sampled guard over-generalises | `x⁴=1` guard learned on `{0,1,6}` ⊂ GF(7), refuted at 2 (R L791-793) | sampling is not certification |
| plan5's simplifications | five items (P6 App. A.2 L869-895) | pure-substitution pullback recomputes context and hides conflicts; uniform in-place propagation is unsound on Z; "just quotient-values" lifting merges only identical predicates and greedy merging hits the bridge trap; a recursive evaluator cannot suspend mid-instruction; one global objective conflates exact and lossy |
| Greedy fiber merging | K = 3 instead of 2 on `{1,2},{2,3},{1,4},{3,5}` (P6 L380) | "fiber intersection is non-associative with respect to greedy merging" → branch-and-bound, later capped |
| Hand-written table inversion in the folder | — | "changed errors into false and was unsafe under negation" (PR L35-37) → removed |
| Same-input tightening over projected inputs | — | silently strengthened frames; "Contradictory identical-input requirements correctly remain contradictory instead of being silently kept in separate feasible-looking classes" (PR L157-158) |
| Abstraction on small corpora | negative gain at reps = 1 and on 2-tree corpora (P6 L737-738) | template overhead |

### 2.5 (d) Where the kernel was patched or knowledge was imported because search could not get there

1. **The description code itself** was redesigned three times so that `a+b` would outrank
   literals (RH L678-683; commits 1d6ce44, 7446706). "The fixed code is a declared prior"
   (R L52).
2. **Literal vocabulary** `{-1,0,1}` for integers (RH L595-601; R L1191-1192, L1438).
3. **Primitives `−`, `/`, `=`, lazy `if`**, with host extended-Euclid inside `/` (R L1092-1096);
   later `:at` (commit 596eb13) and `:mod` (`ast.lisp:145`; the condensed parity selector
   `(mod X0 2)` at P6 L682 needs it, whereas M7 had to spell parity as `x − (x/2)·2`).
4. **Every decomposition**: decoders `a+z`, `a·a+z`, `ι(t)+Z`, `X0+Z1` then `X1·Z2`, the
   `term+0` matcher, which inputs the child sees. "Automatic discovery of decompositions and
   general recursive scheduling remain later research steps" (R L311-313); "Decoder proposals
   and their nesting are explicit inputs to the new controller. Automatic decoder discovery …
   remain research work" (PR L193-195).
5. **The conservation question**: pairs, anchors and the invariance criterion (R L480-489).
6. **Solver-discovery scaffolding**: the max-coverage proposal prior (R L1168-1172), the
   computed-feature guard frame (R L1174-1194), the designation of the unknown operand.
7. **Propagator triggering**: "The matcher pattern and selection procedure are supplied
   mechanisms derived from each rule's recorded orientation. They are not learned retrieval
   programs" (R L1279-1281).
8. **Simplifier rules in `fold-constants`**: Boolean identities, tuple injectivity, `:at`
   β-reduction, coordinate reassembly, finite-set intersection, and (until removed) table
   inversion — "explicit trusted structural deductions; this refactor does not claim they
   were learned" (PR L39-41).
9. **Totality**: `provably-total-p` is a hand-written syntactic judgement (R L672-676).
10. **Corpus structure**: which trees to align (R L390), the shape grouping (R L843-845),
    one pattern per corpus and the "eight structurally best" cut-off
    (`milestones/corpus.lisp:743-750`).
11. **View and locality hints**: the guard grammar, the shared decoder, the parity
    `:locality-key`, pair budgets (P6 L763-765).
12. **M9 descriptors' feature set**: "algebraic property bits (such as f(0)=0,
    f(1)−f(0)=f(2)−f(1))" (P6 L809).
13. **Tests rewritten to supply what inference had silently assumed**: "Two lifting tests now
    make their intended coordinate projection explicit" (PR L156-157).

---

## 3. Recurring problems (representation, not patch)

1. **Learned knowledge never shrinks the search space.** Every syntax tree is retained by
   design (RH L292-296; R L227-228, L558-565); laws only cheapen or skip individual checks
   (R L1042-1046, L1340-1341). So each new law or solver adds per-candidate matching cost
   against a constant number of candidates, and reuse loses in M3, in M4 fields and in M4
   integers. The stated reason for retention — different spellings give AU different
   alignments (R L560-562) — is a property of storing *trees per bucket* rather than one
   shared structure with many spellings.
2. **Decomposition is always an input.** Stated as future work on 27 Oct (RH L258-265), 29
   Oct (R L311-313), 3 Nov (PR L193-195). The frame can *check* a decoder (pullback) but has
   no operation that *proposes* one from the data.
3. **A law is an isolated closed statement.** `if(guard, lhs=rhs, true)` with a certificate
   pinned to one domain, one schema, one set of versions (R L646-648); corpora of thousands
   with no implication, basis or orientation structure among them (R L660-661, L869-871);
   GF(5) and GF(7) corpora cannot be mixed (P6 L631). Reorienting a law into a solver is a
   separate pipeline (M4) with its own record type (`arithmetic-solver`, now
   `arithmetic-propagator`, `laws.lisp:451`), not a re-reading of the same object.
4. **The extensional/intensional split keeps returning.** `finite-allowed` vs
   `predicate-allowed` (RH L165) → unified as Boolean S-expressions (P5 Ex.3 L282) → the
   folder must then recognise `(= X0 'v)` and `(member X0 '(…))` shapes to recover fibers
   (P6 L403-406; `extract-allowed-values` `frame.lisp:126`), and soundness bugs appear exactly
   there (PR L33-38).
5. **Partiality leaks through every transformation.** `0·(1/0)` (R L673-674); error ≠ false
   ≠ unknown (R L567-573; PR L10); "Equality of top-level accepted sets alone does not justify
   rewriting below negation or a conditional" (PR L227-229).
6. **Parallel engines regrow after each consolidation.** P5 counted 6 state machines, 3
   rewrite-like engines, 4 factorization mechanisms; P6 consolidated to 7 modules but the
   kernel was 4,600 LOC, not 900; PR added a controller and split files again; today there
   are 9 resumable state structs and 17.7 k LOC.
7. **Metering shapes the architecture.** Unit-quantum parity is why P5's simple evaluator was
   rejected (P6 App. A.2 #4) and why compiled execution was deferred (RH L471-474). A large
   share of the listed tests are parity tests (P6 §4.1 items 10-14, §4.2 items 9-11).
8. **Certification exists only on tiny finite domains.** Everything on Z is `:conjecture`
   (R L1236-1238; P6 L157); nothing in these documents moves a conjecture toward a proof.
9. **Documents drift ahead of the code.** PR L207-223 retracts five P6 claims; P6 M8B, M8D
   and M9 read as done and were not.
10. **Search results are discarded as soon as they are bucketed.** Output vectors are used
    only as exact-equality hash keys (R L541-549); nothing records how *near* two behaviours
    are, so there is no notion of a near-miss to steer search. **[inference]**

**What plan6-refactor.md tried to fix structurally, and whether it did.** It fixed (i)
soundness of requirement simplification, by deleting the unsafe rules and requiring totality
for reordering; (ii) silent strengthening, by turning coordinate projection and feature
choice into explicit competing proposals; (iii) budget ownership; (iv) orchestration, with a
resumable parent/child controller that scores completed parents rather than children; (v)
honesty of labels ("not Hard EM", "not constant-time", "no cross-problem DAG reuse"). All of
(i)–(iv) are still in the code. It did **not** touch the representation: frame, row and
requirement are unchanged; decoders remain inputs; it explicitly declined a "wholesale
corpus/observation representation rewrite" (PR L200-201) and deferred automatic decoder
discovery, DAG memoization, conflict-explanation learning, learned policies, e-graphs,
object-language recursion and learned host traversals (PR L5-6, L191-205). It is a
correctness and plumbing repair; problems 1–3 above are untouched.

---

## 4. Nuggets for the current lens

### (a) Frames as fibers / bundles; lift, project, pullback; residual calculus

- "A fiber describes compatible values; a residual is a particular value or index retained
  for reconstruction" (RH L186-187). *Why now:* the cleanest statement of the
  fiber/section distinction in the trail; a graph kernel needs both as different edge kinds.
- Pullback "always exists, never loses solutions"; a witness solver is "a guarded
  right-inverse"; only with certified injectivity is it two-sided and may replace the
  predicate (P6 L191-194). *Why now:* this is the exact condition under which a relation
  edge may be re-oriented into a function edge.
- Factorization as "the right-inverse (dual) of Apply" in three algebras — term (AU),
  sequence (quotient/gather), value (lifting through a decoder) (P5 §2.2 L134-155; P6
  L363-383). *Why now:* supports the owner's claim that AU, quotienting and lifting are one
  operation; the documents never implemented them as one.
- "Value-space fiber Fiber(ω) ⊆ V vs. row-space partition block Ω_k ⊆ Ω … a block is jointly
  realizable … iff the intersection of its value-space fibers is non-empty" (P6 L218-219).
  *Why now:* a guard/partition is defined by connectivity of rows through shared admissible
  values — a topological criterion already in use.
- Don't-care rows: where the decoder absorbs (`0·Z`), the child requirement is `'t` and
  "pays 0 extra description bits" (P6 L212-213); M8A relies on it (P6 L787). *Why now:* the
  residual calculus must carry "unconstrained" as a value, not a missing datum.
- "A compression comparison must price the complete reconstruction, including the residual"
  (R L326-328), and the long caveat that a formula and a literal list have different
  interfaces because the grid and its order are supplied by the host (R L433-462). *Why now:*
  the iteration/traversal ("lift within the execution engine") was already identified as
  unpriced host structure on 29 Oct.
- Guard discovery "fits the residual machinery: after observing the equation, the unresolved
  information is the membership of each input in its valid subset. That information is
  represented by a normal frame" (R L730-733). *Why now:* a guard is the residual of a law.

### (b) Learning dependency structure by intervention / experiment

- The grouped generator `G(k,u)=(u,k−u)`: hold `k`, vary `u`, require equal outputs within
  groups and variation between (R L499-507). Noted, not run. *Why now:* this is literally
  "holding all but a few constant"; it would have made M2's conservation question
  kernel-posed instead of supplied.
- M4 does run a designed experiment: the full forward grid plus "an additional query grid
  [of] every pair of declared k and c values, including pairs with no answer" (R L1148-1163).
  *Why now:* the one place where the kernel's knowledge came from exhaustive probing of the
  simulator; it worked, at p² / p³ cost.
- Withholding a coordinate and watching for contradictions identifies what a latent depends
  on (P5 §5 L358-360; P6 L697; Stage A "conflict-free projection", P6 L381). PR L230-231:
  "Projecting away inputs is a hypothesis and must retain alternatives." *Why now:* a passive
  version of an intervention test; the audit's rule is the right epistemic status for it.
- Scope splitting: `x` and `x·x` agree on `{0,1}` and split when 2 is added (RH L573-578; R
  L618-620). The discriminating input was chosen by the agent. *Why now:* choosing the next
  input that would split a bucket is the missing active step.
- An `oracle` "may only evaluate candidate inputs and charge `:simulation` work" (P6 L105);
  reorientation charges "zero `:simulation` work" (P6 L392). *Why now:* the cost category
  for experiments already exists; nothing spends it adaptively.
- "A single-orbit scope (`anchors = nil`) reports 0 informative invariants because constants
  cannot be separated from orbit invariants without cross-orbit anchors" (P6 L573). *Why
  now:* conservation needs at least two disconnected components to be informative.

### (c) Algebra / law discovery; reorientation of laws into solvers / generators

- "A conserved relation R(X,Y) … is initially a passive test … Algebra turns passive
  conservation into active generation and backward constraint propagation: reorienting which
  coordinates of a recorded relation serve as known inputs vs. unknown targets" (P6 L22).
- "Once forward execution on a grid records tuples (a,b,c) ∈ Γ_f, the causal asymmetry is
  converted into a relational table … Reorientation simply changes which columns … are
  declared inputs (the base of the fibration)" (P5 §2.3 L161-164). *Why now:* an n-ary
  relation with re-choosable base is a hyperedge; this is the owner's "tuple = edge with
  coordinates".
- The solver as two ordinary laws: witness `G ⇒ R(k, q(k,c), c)` and uniqueness
  `G ⇒ (R(k,z,c) ⇔ z = q(k,c))` (R L1221-1224; P5 Ex.3 L262). *Why now:* a solver is
  already expressible as a law about a relation; the separate solver record is incidental.
- "Propagation IS guarded law rewriting + constant folding on B_ω(z)" with multi-step
  nesting for free (P5 L174-181, L283-288) — and the audit's limit on it (P6 App. A.2 #2).
  *Why now:* the unification is right for certified equivalences and wrong for one-sided
  witnesses; a new kernel should carry the grade on the edge.
- The integer divisibility guard `k·(c/k)=c` learned by feeding the witness back through the
  forward operator (R L1183-1188). *Why now:* a depth-2 experiment (solve, then re-apply)
  yielding a guard — the one instance of the owner's "depth ≥ 2" recipe in these files.
- Cross-prime AU of `C+4K`, `C+6K`, `C+(−1)K` to `(+ C (* ?coeff K))` (P6 L789). *Why now:*
  the only attempt to connect laws across domains; the hole is exactly the residual.
- Law-normalized AU (P6 L721, L730): validated laws change which abstractions are visible.
  *Why now:* direct evidence that quotienting by laws must precede anti-unification.
- Strictly-decreasing rewriting "without requiring confluence or an e-graph" (R L670-672).
  *Why now:* this is the cheap alternative that was chosen; it cannot represent that two
  spellings are the same node.

### (d) Graphs / hypergraphs / corpus graphs as the store

- **What "subgraph correspondence search" was.** `discover-subexpression-abstractions`
  (P6 L369, L720-730; `milestones/corpus.lisp:704-768`): index every subterm of every tree
  by path (`collect-tree-occurrences`), bucket by sort/signature, anti-unify *pairs* of
  occurrences from different trees in a scheduled order, relax each candidate pattern over
  the remaining trees, then price the root-aligned template and the eight structurally best
  candidates as a "spliced pre-order packet" (wrapper + path + template + substitutions),
  with path `:none` for unrelated trees. It is tree-occurrence anti-unification: no DAG, no
  sharing, no isomorphism test, one pattern per corpus, at most one occurrence per tree.
- **What it showed.** Recovery of one planted pattern at four different paths, with
  distractor trees and four seeded random corpora; a bit win over literal, dictionary and
  root-aligned AU at 2 and 4 repetitions and a loss on 2-tree corpora (P6 L737-738); that a
  locality order finds a co-local pair within 6 pair-attempts where canonical order does
  not, and that the reserve lane rescues the adversarial case (P6 L765). No work numbers.
  PR L198-199: "still uses its bounded greedy proposal strategy; lazy occurrence wrappers
  and incremental pair generation are deferred." *Why now:* it demonstrates the need (shared
  structure under different wrappers) and the absence of the data structure (an occurrence
  index is a poor man's hash-consed graph).
- `pairs` and `anchors` are edges over row keys: per block, m−1 chain links; one
  representative per block (P6 L220-225). The current frame has since added `metric` and
  `edges` slots (`frame.lisp:12-18`). *Why now:* the frame has been accreting graph
  structure field by field.
- "Law and tree corpus containers remain separate adapters … A wholesale corpus/observation
  representation rewrite is unnecessary here" (PR L200-201). *Why now:* the decision the
  owner is now reversing, with its date.
- Observation buckets retain all member trees with a shortest representative (P6 L564).
  *Why now:* this is an e-class without the congruence closure.

### (e) Geometry: metrics, neighbourhoods, residual pricing, fiber clustering

- Residual pricing in the ambient target space: each miss costs
  `positive-bit-size(i+1) + value-bit-size(w_i)` (P6 L441), later plus a correction-count
  prefix (PR L101-102); hits inside a multi-valued fiber cost zero (P6 L216). *Why now:* the
  existing "ambient pricing" the owner asks about; it is a 0/1 metric per row — no partial
  credit for a near value. (A per-frame `metric` slot exists in today's `frame.lisp:17`.)
- "Generated-space distance": ℓ1 on tuple coordinates, quotient-class agreement, or 1-D
  position, computed from a priced `:locality-key` expression evaluated in the VM (P6
  L757-759). *Why now:* the only induced metric in these documents, and it is a space made
  by a program — the "make a space where instructed" operation in miniature.
- Fiber clustering: bridge-vs-leaf non-associativity (P6 L380), and the audit's verdict
  "bounded combinatorial proposal search, not Hard EM … Concentration is not Shannon
  entropy" (PR L233-234). *Why now:* exact set-intersection clustering is combinatorial; a
  metric relaxation was never tried.
- The outcome vector `M(e,·)` is already a coordinate for every expression (R L520-524; P5
  L120). It is used only for equality. *Why now* **[inference]**: it is a free behavioural
  embedding with a natural Hamming-style distance (rows agreed on); "these things are close"
  is available without any learned embedding.
- The 3:1 lane schedule (P6 L227; `synthesize.lisp:968`) is a fixed mixing weight between a
  heuristic order and the canonical order. *Why now:* the one scalar a learned policy would
  first replace.

### (f) Heuristics / policies and how they were to be learned

- A control heuristic "cannot corrupt soundness provided every candidate solution is still
  checked by the authoritative verifier and a canonical reserve lane remains active" (P6
  L435). *Why now:* the licence for lossy, geometric guidance over an exact topology.
- Learn it as lossy MDL condensation of a table, price the exceptions while choosing, drop
  them when deploying (P6 L437-442).
- Intended training signal: continuation returns `G_t = B_t − B_T − λ_search(W_T − W_t)`,
  shrunk per feature bucket by `(κ G_0 + Σ G_i)/(κ + n)` (P6 L447, L796). Never run in these
  documents; "Adaptive search scheduling is deferred until larger problems expose its costs
  and benefits" (R L1086). *Why now:* the reflective loop was specified and waited on scale
  that the budgets never provided.
- Retrieval by descriptors condensed from probe tables (P6 L808-812). *Why now:* a library
  index keyed by behaviour on probes is an embedding in all but name.

### (g) Language

- Nothing on natural or compositional language. The nearest items: opaque symbols carrying
  "only their input-output type signature … and no human-chosen names" (P6 L803) with
  descriptors synthesized "in its own DSL"; and "Predicting substitutions from context,
  installing named definitions … remain later work" (R L407-408). *Why now:* confirms the
  language component is untouched in this stratum.

### (h) Reflection and reentrancy

- Laws, guards, solvers and AU templates are data in the same VM: a law corpus is a frame
  target (R L848-857); a rule is a DSL program on quoted syntax (R L950-957); "the canonical
  synthesizer can also search symbolic programs. … There is no separate symbolic enumerator"
  (R L1012-1017); AU runs over the system's own laws and solvers (R L1479-1492).
  *Why now:* object-level reentrancy on *results* was reached early.
- The boundary: "Frame orchestration, validation, and matching remain in Lisp" (R L638);
  "learned replacements for arbitrary host traversals remain later work" (PR L5-6); the
  controller "does not preempt host Lisp traversals" (PR L118). *Why now:* the search's own
  operations were never data; this is precisely the owner's "lift … is wholly in the host
  lisp".
- Scope-tagged messages "are evidence-bearing data for later sub-synthesis. Learned
  explanations, synthesized return messages, and learned scheduling policies are not
  implemented or implied by the envelope" (PR L87-89). *Why now:* the trace exists as a
  record; nothing consumes it.
- The second-language warning (P5 §1.1): nine `:code-*` primitives duplicated what Lisp
  quotation gives for free and cost 545,921 wu to save 7,732. *Why now:* reflection through
  an interpreted mirror language is the expensive way to be homoiconic.

### (i) Totality, crashes, learned guards

- Three outcomes — value, error, unknown — with "a work cutoff … neither a semantic error
  nor evidence of impossibility" (RH L299-301) and "a cutoff is not a conflict" (PR L22).
- Errors are evidence: `:retain-outcomes` keeps a value-or-error per row (R L575-580); "the
  division error is evidence that this row must be excluded from the guard" (R L716-717);
  the forward definedness guard of `/` is *learned* from error rows before anything else in
  M4 (R L1149-1153). *Why now:* this is already "tolerate crashing and assemble guards for
  it"; it only lacks the non-termination case (cutoff rows are excluded, never learned from:
  "An unfinished evaluation supplies neither label", R L703-704).
- Imported totality: `provably-total-p` is syntactic and "may decline safe rewrites" (R
  L675); learned guards are not fed back to discharge it.
- "Failure to detect a contradiction is unknown satisfiability, not a witness" (PR L232).

### (j) Budgets and compiled / lowered execution

- The scaling table and its extrapolation (§2.2) — the only empirical growth curve.
- "Wall-clock time is already an appropriate measure of practical search latency. Report it
  alongside … the deterministic tariff" (RH L415-417) — advice not followed afterwards.
- The deferred compiler with its break-even inequality and its obstacle: "Integer instruction
  costs depend on intermediate values and cannot generally be prepaid as one fixed total"
  (RH L472-474; R L1639-1640).
- Preparation amortization: compile and validate a rule once per library and schema; −65.2 %
  (R L1055-1073). *Why now:* evidence that lowering pays, and of how much overhead the
  interpreted path carries.
- The expensive-context control (R L1433-1457): learned inverses pay when forward evaluation
  is expensive. *Why now:* with hours-scale budgets and costly simulators this regime
  becomes the normal one; on toy arithmetic it never is.

---

## 5. Contradictions

**Between the documents**

1. *Which compression model wins.* R L862-872: the single global AU template wins (157,885 /
   461,750 bits); shape-grouped AU is ≈ literal. P6 L604 and L629: "Shape-grouped AU achieves
   33.9 % … (180,828 → 119,532)" and 28.7 % (513,294 → 366,184). Same percentages, different
   absolute sizes, opposite winner. The current test asserts the third model, the global
   template, is best (`tests/milestones/compression.lisp:141`; order in
   `milestones/corpus.lisp:209`). P6's attribution is wrong; its absolute numbers are
   unverifiable here.
2. *M2 counts.* R L598-601: GF(5) 15 exprs / 13 buckets at 50 bits and 105 / 25 at 54 bits;
   integers 83 / 71. P6 L569-570: 70 / 29 and 50 / 35 "at body limit 21 bits". RH: 105 / 25
   at 41 bytes. Three kernels, three counts; the current test compares against a reference
   enumeration at 16 body bits and asserts none of these figures (`tests/observations.lisp:18-24`).
3. *"~5× less work" as "the common case"* (P6 L429) vs R: propagation is slower on every
   ordinary fixture and 4.8× faster to first solution only with 2^128 operands (R L1349-1445).
4. *O(1) sizes* (P5 L218-220; P6 L29, L82-84) vs PR L211-212.
5. *Packet kinds for lookup / concatenation / AU* (P6 L123) vs PR L209-210 "there are no
   separate … packet kinds"; *Elias-gamma integers* (P6 L124) vs "delta coding" (PR L209;
   `codec.lisp:5`).
6. *Global `*prepared-rewrite-cache*` and DAG subproblem reuse* (P6 L599, L780, L791) vs PR
   L213-214.
7. *`message-status / -best / -proposals …`* (P6 L115) vs PR L215-217 (`call-id, claim,
   evidence`; confirmed `enumerate.lisp:219`).
8. *Reorientation conjoins colliding rows* (P6 L655) vs PR L218-220 "does not silently union
   incompatible inverse observations".
9. *"Hard-EM", "host-bias-free MDL partition search", "global optimum"* (P6 L380-382) vs PR
   L57-60, L233-234.
10. *No `eval`* (P6 L69, L636; R L918) vs P6's own decoder class 4, "a `:code-eval` rewrite
    context" (P6 L205).
11. *Propagation is rewriting* (P5 L174-181) vs a retained propagator library (P6 L415-429).
12. *One objective* (P5, per P6 App. A.2 #5) vs two-level objectives (P6 L143-150).
13. *Kernel size*: ~900 LOC (P5 L342) vs ~4,600 (P6 L454).
14. *Suite size*: "77 test suites and 185,011 checks" (P5 L15) vs "82 tests and 187,382
    checks" (R L1496).
15. *Bounded-integer "validation"*: `x/x=1` is "`:validated` on bounded integer window
    [−4,4]" (P6 L603) while R L794-795 says integer laws cannot be certified; a window
    certificate is a different claim and P6 does not flag the difference.
16. *M4 numbers re-used across kernels*: P6 L664 quotes 2,193,913 → 454,724 from R, measured
    on the discarded VM under tariff v8; PR L110-113 says "historical work totals must retain
    their original version". The current test asserts only that guided < plain
    (`tests/milestones/propagation.lisp:137-138`).

**Between the documents and the current code**

| Claim | Code |
|---|---|
| Tariff v8 (P6 L128), v9 (PR L110) | v10 (`vm.lisp:7`) |
| No `eval` in the DSL | `:code-eval` implemented (`vm.lisp:338,436,503`) |
| No DSL compiler (R L1644-1645) | closure lowering exists (`vm.lisp:87,417-439`) |
| 7 modules (P6 §3) | 27 root files; `factor.lisp` deleted 11-09 (commit 8a06293) and split into `unify`, `fibers`, `condense`, `abstraction`, `proposals`, `milestones/*` |
| `propagate-arithmetic-child`, `compile-propagator-matcher`, `match-arithmetic-propagator`, `apply-guarded-rewrite`, `prepare-program`, `execute-model`, `verify-model`, `row-allowed-values`, `row-target-witness`, `enumerate-domain-rows`, `frame-covers-domain-p` | GONE under those names (nearest: `propagate-requirements` `laws.lisp:736`; `extract-allowed-values` `frame.lisp:126`; `select-closest-witness` `frame.lisp:1719`) |
| Experiment runners `run-m1 … run-m7`, `make m1 … m4`, `intermediate_results/*.txt` | GONE; milestone logic lives in `milestones/` and `tests/milestones/`; no saved traces in the repository, so none of R's ledgers can be diffed against a file |
| Tests `m5-supplied-lift-and-repetition-compression`, `m5-unsupervised-hard-em-…`, `view-supplied-vs-discovered-…`, `recursive-control` | GONE or renamed (`m5-finite-field-lifting-and-certified-propagation` `tests/lifting.lisp:383`; `view-discovery-and-three-way-comparison` `tests/milestones/views.lisp:86`; `recursive-composition-budget-and-informative-messages` `tests/refactor.lisp:94`) |
| `infer-fibers` is "not Hard EM" (PR) | still labelled Hard-EM in `package.lisp:122` and five test names |
| P5's direct rule application | never built; `code-match`/`code-bind` lowering unchanged (`laws.lisp:284-311`) |

---

## 6. What these documents do not contain (for the synthesis)

- No experiment in which the kernel chose its own inputs, decoder, grammar, bound or budget.
- No law relating expressions deeper than one operator; no three-variable law.
- No search longer than 44 seconds; no wall-clock figure after 27 Oct.
- No graph, DAG or hash-consed store; no isomorphism or e-graph; "subgraph" means subtree.
- No metric other than exact equality, per-row hit/miss, and the M7 locality ℓ1.
- No learned policy that was ever trained on search traces.
- No object-language recursion or iteration: "Recursion here means decomposition of
  synthesis problems" (PR L235-236).
- No saved traces to check the reported numbers against.

Scratch notes: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/docs-plan6-results/notes.md`
