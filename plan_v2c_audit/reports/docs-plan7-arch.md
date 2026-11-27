# docs-plan7-arch — audit of plan7 (+4 sub-plans) and architecture.md / architecture2.md

Auditor: `docs-plan7-arch`. Repository read-only; code checks are greps against the root kernel
(`/home/tlh24/lisploop/*.lisp`, `milestones/`, `bootstrap/`, `tests/`) as it stands on branch `reflective`.
Tags used for code checks: **STILL-IN-CODE (file:line)**, **GONE**, **NEVER-BUILT**. "GONE under that name"
means the `defun` is absent; I did not audit whether the behaviour survives elsewhere unless I say so.

Line numbers `Lnnn` refer to the document being discussed.

---

## 0. Dating and standing of the seven documents

| Document | Git dates (`git log --follow`) | Self-declared status | What it actually is |
| :-- | :-- | :-- | :-- |
| `architecture.md` | 2026-11-02 … 11-08 (11-13 touch) | "The Lisp source is authoritative" (L9) | API reference for the **9-module** kernel (`factor.lisp` era). Cautious; lists non-features. |
| `plan7/plan7.md` | 10-30 … 11-08 (as plan6 → plan7 on 11-04); moved to `plan7/` 11-13 | "distinguishes implemented mechanisms and tests from proposed extensions" (L33) | The most careful document of the seven. Milestones M1–M9, four-operation framework. Partly stale against its own sub-plans (see §7). |
| `plan7/plan7-recursion.md` | 11-06 … 11-08 | "Complete… implemented, audited, and verified" (L3) | Plan + implementation notes for R1–R6 (sequences, `:code-eval`, `lift-frame`, oracle self-lift, library AU, nogoods). Commit message of the same day says "recursion done - only lightly tested" (eff7be6). |
| `plan7/plan7-library.md` | 11-08 (one commit) | plan ("This plan specifies the next evolutionary step") | Pure design for the persistent knowledge library (L1–L4). No results section. |
| `plan7/plan7-higher-order.md` | 11-08 … 11-09 | "Status: Proposed" (L3) but §4 is "Implementation Notes (H1-H4)" | Owner prompts verbatim (§0), design answers, then partial implementation notes. Commit: "preliminary implementation… Needs a critical eye as always" (6436c76). |
| `plan7/plan7-m9-policy.md` | 11-09, edited 11-13 | diagnosis + design, no results | M9.1–M9.4: partial fiber unfolding, sequence residual pricing, descriptor names, policy scoring, deferred proposals. |
| `architecture2.md` | single commit b6e289e, 2026-11-13 10:10 ("also missed the new arch doc!") | "authoritative architectural reference for the refactored kernel" (L9) | Rewrite of architecture.md for the **24-module** kernel, absorbing all four sub-plans. Uniformly affirmative tone; no "not implemented" list. Already stale when committed (see §1.3). |

Context from commit messages (not from the documents): 8a06293 (11-09) "multi-agent refactor… documentation very out of date now"; c4cb6e8 (11-13 09:39) "removed descriptor-tables, and merged bottom-up dependency-expander into core synthesis"; 54acfa3 (11-13) owner: "moved /removed plan7 - which is still relevant and important; not quite depeciated yet"; b3af2e6 (11-18) "step 2 of batteries +reflectivity done" (deletes `bootstrap-inverters.lisp`, `filter-map-decompositions`). plan8 (11-13…17), plan9 (11-16/17) and batteries-and-reflection (11-18) come after everything here.

Two documents cited by my set do not exist in the repository or its history: `plan7-recursion2.md` (cited for items K3/K4/K5 at plan7-recursion L4, L49, L132) and `audit-review.txt` (cited at plan7-m9-policy L21). All `file:///home/tlh24/sandbox/team/tlh/lisploop/...` links in architecture2 and plan7-m9-policy point to a different checkout; the line anchors in them do not match the root files.

---

## 1. The architecture as documented

### 1.1 Claimed invariants and layering (both versions, in brief)

Representation
- Programs, requirement predicates, law equations/guards, AU templates, quoted syntax are typed S-expressions; variables and holes are pooled uninterned symbols; metadata (type, bits, totality, free vars) lives in a weak `eq` table `*node-meta*` (architecture L46-48; architecture2 §2.2 L119-129). Canonical positional variables `X0, X1, …` make quoted code "zero-copy" (architecture2 L126).
- **Frames, rows, schemas, jobs, laws, certificates, decompositions are host structs, not object-language data** (architecture L15; plan7.md L27 "Frames, laws, certificates, and continuations are Lisp structs around them, not object-language programs").
- A frame is `schema, rows, pairs, anchors`; a row is `(key, known, requirement)` with the requirement a Boolean AST over target variable 0 (architecture §2.2 L59-67). Strict input availability: programs cannot read `row-key`; constants baked into a pulled-back requirement are visible only to the checker (architecture2 "Eight Governing Distinctions" #1, L245-246).
- Types: `:int`, `(:gf p)`, `:bool`, `(:tuple …)`, `(:seq τ)`, `(:code inputs sort)` (architecture L33-42).
- No host `eval`, no host-call escape; execution of code values only through `:code-eval` under the VM budget (architecture L44; architecture2 L117).

Accounting
- Three quantities kept distinct: description bits `S(M)`, run work `W_run(M)`, search work `W_search(P)` (architecture L19-25; architecture2 §1.2).
- Encoding v7 (Elias-delta, zigzag, 2-bit AST tags, 4-bit opcodes with extension); Tariff v10; Simulator v6 (architecture L11, §2.3).
- One resumable VM; instructions prepay work; one-unit stepping is bit-identical to batch execution, including errors (architecture §2.4 L104-116; architecture2 §2.6).
- Host preparation is staged in a private ledger and its "debt" drained before results are published: "accounting preemption, not interruption of arbitrary host traversals or a wall-clock deadline" (architecture L116).

Epistemics
- Graded claims: `:replayed-observations`, `:conjecture`, `:vacuous`, `:refuted`, `:validated`, `:cutoff`, `:bounded-exhaustion`, `:partition-proposal` (architecture §6 L242-251). Only exhaustive finite-domain validation certifies a law; samples never do (architecture L128).
- Evaluation errors and cutoffs never simplify to false; static totality gates any rewrite that would erase or reorder a partial computation (architecture L160; architecture2 §2.4).
- Tentative shortcuts never starve sound search: every fourth quantum is reserved (root lane / fallback frame / canonical pair order) (architecture L193; architecture2 §1.2 calls this "a ubiquitous 3:1 Reserve Schedule").
- All candidate branches are compared at the root: child candidates are composed through every ancestor decoder and verified on the original frame (architecture L189; architecture2 distinction #8 L264-265).

Layering ("four operations", identical in both)
1. Observational conservation: enumerate, evaluate, bucket by output vector, invariants on `pairs`/`anchors`, propose laws and guards.
2. Factorization: anti-unification, quotient/partition, fiber clustering (`infer-fibers`).
3. Reorientation, pullback, conservative folding, propagation with learned solvers.
4. Heuristic condensation (Stage A residual pricing) and recursive search orchestration (Stage B decompositions).

### 1.2 architecture.md → architecture2.md: what was added, what was quietly dropped

Added in architecture2
- A thesis statement and "three pillars" (Symmetry / Algebra / Interacting views), copied from plan7.md's Aim (architecture2 §1.1 L19-36 ≈ plan7.md L13-21).
- Module map of 24 kernel + 5 milestone modules with a hard rule "the kernel never calls into `milestones/`" (architecture2 §1.3 L56-98).
- Static totality as a first-class section, incl. structural recursion and higher-order totality (`conditional-code-params`) (§2.4 L153-163); closure capture by `:code-subst` (L165-174).
- `:unresolved` as a fourth evaluation outcome and partial oracle tables (§2.6 item 4 L219-220).
- `lift-frame` in detail: spine unfolding, cross-row congruence closure, ground vs coupled fibers, active window + reserve rows, coordinate probes, closure reification (§3.3 L415-437).
- `fold-constants` contracts `:equivalent` vs `:necessary`, `:max-fibers`, spine rationing (§3.2 L386-388).
- Higher-order library AU ("Stitch-style"), with the R5 bit trace (§4.2 L476-509).
- Transformers, functors, polymorphic retyping (§4.3 L539-548).
- Smooth sequence residual pricing (§4.4 L564).
- Scope-cache DAG sharing, staged work, deferred proposals, full-path priority formula with `128·|coupled|` and `ΔJ_policy` (§5.1 L589-596).
- Stage B recursion paths (single-sequence and lockstep inductive lifts), oracle self-lift (§5.2).
- Library proposals, filter-map comprehension, reentrant 2D lifting, decoder templates (§5.3).
- Nogoods (UIP/DIP) and CEGAR (§5.4).
- Persistent knowledge library with 11 kinds, evidence snapshots, persistence, descriptors, relations, consolidation (§6).

Quietly dropped from architecture.md
- The explicit negative list: "Learned residual geometry, graded pair/anchor constraints, loss transport through decoders, and automatic locality-key synthesis are not implemented" (architecture L214). architecture2 has no equivalent sentence.
- The "Remaining boundary" column of the milestone table (architecture L255-264: e.g. "No general latent-model identification guarantee", "Bounded/greedy correspondence search", "Online continual meta-learning across unbounded task streams", "Mutual recursion and unbounded higher-order type synthesis"). architecture2 §7.3 has only "Implemented Capabilities".
- "Supplied decoders, feature vocabularies, locality keys, and candidate lists remain explicit controls… Tests distinguish supplied controls from grammar-discovered artifacts" (architecture L17). No such statement in architecture2.
- The whole "Views and locality" section (architecture §4 L197-214): the locality metric (equal keys → coarse classes; equal-length integer lists → Manhattan distance; scalar keys → coarse-class fallback, "not numeric scalar distance"), the note that host-function locality keys are not VM-metered. architecture2 mentions locality only as one line under `milestones/corpus.lisp` (L730).
- The disclaimer that `J(M_P)+λ_search·W_search(P)` "is an experimental comparison criterion, not an implemented learned scheduler objective" (architecture L238).
- "`message` has only `call-id`, `claim`, and `evidence`… there is no universal status/best/cursor envelope" (architecture L240) → reduced to one neutral sentence (architecture2 L740).
- "A `priority-predictor` is a host function of the node, frame, language, and Stage A model" (architecture L187) → architecture2 presents it as a "VM-executable priority predictor AST" (L712).
- Caveats on `infer-fibers` ("neither Hard EM nor global MDL optimization; concentration is not Shannon entropy. The legacy `hard-em-...` test names remain", architecture L144) and on subexpression abstraction ("not a globally optimal subgraph or compression solver", L132).
- "The kernel has no cross-branch child-problem DAG cache" (architecture L17) — replaced by its opposite (and architecture.md already contradicted itself on this, see §7).
- "`body-size` and `description-size` recursively validate… They are not constant-time size APIs" (architecture L48) → architecture2 says body-size "is computed in O(1) from cached `ast-meta`" (L182).

Net effect: architecture2 is larger and more complete as an inventory, but it converts a document that separated "implemented / supplied / not implemented" into one that only asserts. For the synthesis, architecture.md + plan7.md are the better guide to what was *not* solved; architecture2 is the better index of mechanism names.

### 1.3 Spot-check of load-bearing claims against current root code

| # | Claim (source) | Current code | Tag |
| :- | :-- | :-- | :-- |
| 1 | Encoding 7 / Tariff 10 / Simulator 6 (architecture L11; architecture2 L11) | `codec.lisp:7`, `vm.lisp:7`, `vm.lisp:8` | STILL-IN-CODE |
| 2 | "24 kernel modules"; `bootstrap-inverters.lisp` is module 14 (architecture2 L78) | `load.lisp` loads 24 modules, but `bootstrap-inverters` is gone (deleted b3af2e6, 11-18) and `messages.lisp` is new; functor induction now in `consolidate.lisp:2081` | Count holds, composition changed |
| 3 | "26 primitives" (architecture L50; architecture2 §2.3) | `+primitives+` has 27 rows (`:mod` appended), `ast.lisp:118-146` | Changed |
| 4 | No host `eval` in the object language (architecture L44) | No `(eval` in kernel files; only `benchmark.lisp:157`. But `vm.lisp:432-444` (`compile-ast-fn`, `expression-closure`) now compiles primitive-only ASTs to host closures | STILL-IN-CODE (plus a later lowered path) |
| 5 | `pullback-frame` does not fold or solve (architecture L158; architecture2 L401) | `frame.lisp:544`; it now also carries a pulled-back metric (`frame.lisp:563`) | STILL-IN-CODE |
| 6 | 1-to-many `lift-frame` with congruence closure, active window, reserve rows (architecture2 §3.3) | `frame.lisp:1194`, `congruence-close-code-evals` `frame.lisp:975`, `select-active-fiber-rows` `frame.lisp:1039`, `*max-active-lifted-rows*` = 16 `frame.lisp:1016`, `probe-frame-coordinates` `frame.lisp:1108` | STILL-IN-CODE. Per-row cap is `(max 4 (+ 2 (ceiling K rows)))`, not the documented max(4, ceil(2K / rows)) |
| 7 | `fold-constants` default `(budget 64)` (architecture2 L371) | `requirements.lisp:529` default budget 10000 | Changed |
| 8 | `infer-fibers` `(budget 50000) (branch-limit 2048)` (architecture2 L512) | `fibers.lisp:156` budget 1000000, branch-limit 2048 | Changed |
| 9 | Priority = full-path bits + residual + 128 × (number of coupled requirements) + `ΔJ_policy` (architecture2 L591) | `synthesize.lisp:489-507`: 16 × (number of coupled requirements), half the policy score, plus a predictor term clamped to [-24, 48] bits | Changed |
| 10 | `*max-eager-proposals-per-node*` is 3 (architecture2 L704) | `synthesize.lisp:1042` default `nil` (no limit) | Changed |
| 11 | "5-facet / 3-tier `*descriptor-table*`" (architecture2 L81, §6.2) | No `*descriptor-table*` anywhere; removed in c4cb6e8, 31 minutes before architecture2 was committed. `descriptors.lisp` now synthesizes descriptors from I/O (`synthesize-io-descriptor-specs` `descriptors.lisp:392`); `make-descriptor-clause` `knowledge.lisp:67` | GONE (superseded) |
| 12 | "11 knowledge kinds" (architecture2 §6.1) | 14 `define-knowledge-kind` forms: adds `:motif` (`consolidate.lisp:951`), `:spec` (`consolidate.lisp:1085`), `:locality-key` (`proposals.lisp:625`) | Changed |
| 13 | Scope-cache DAG sharing (architecture2 L589) vs "no cross-branch child-problem DAG cache" (architecture L17) | `synthesize.lisp:70`, `child-scope-signature` `synthesize.lisp:264` | STILL-IN-CODE; architecture.md L17 was wrong |
| 14 | Every 4th turn reserved (architecture L193) | `reserved-turn-p` `synthesize.lisp:968` `(= 3 (mod turn 4))` | STILL-IN-CODE |
| 15 | `filter-map-decompositions`, `function-body-subsequence-filter-p` (architecture2 L86, L624-625) | Neither `defun` exists; a `:comprehension/filter-map` decoder template is registered by hand in `bootstrap/build-batteries.lisp:711-718` | GONE (b3af2e6) |
| 16 | `induce-involution-solvers`, `build-functorial-map-inverter` (architecture2 L546-548) | Neither `defun` exists; `induce-law-solvers` `consolidate.lisp:1581`, `induce-combinator-solvers` `consolidate.lisp:1976` look like successors (not audited) | GONE under those names |
| 17 | `evaluate-priority-predictor-expr` (architecture2 L712) | Absent; `priority-predictor-function` `synthesize.lisp:~455` | GONE under that name |
| 18 | `discover-arithmetic-solvers`, `discover-arithmetic-propagators`, `observe-arithmetic-relations` (architecture2 L96) | Only `discover-arithmetic-solver` (singular) `milestones/algebra-discovery.lisp:298` | Partly GONE |
| 19 | Nogoods, UIP, DIP, CEGAR (architecture2 §5.4) | `nogoods.lisp:5,175,218,386,489,540`; `refine-lifted-node-from-counterexample` `synthesize.lisp:1189` | STILL-IN-CODE |
| 20 | Trace condensation and episode returns (architecture2 L711-712) | `consolidate.lisp:5,20,95` | STILL-IN-CODE |
| 21 | Frame = `schema, rows, pairs, anchors` | `frame.lisp:12-24` adds `metric` and typed `edges` (`:equal`, `:distinct`, `:persistence`) | Extended since |

---

## 2. Idea ledger

Status vocabulary: **B-M** built and measured (numbers cited); **B** built, no number in these documents; **B-R** built then removed; **P** proposed, never built; **S** superseded.

### 2.1 plan7.md (M1–M9)

| Mechanism (what; where) | Status | Evidence / code |
| :-- | :-- | :-- |
| Typed bottom-up enumeration by body-size tiers; exact search on row requirements (§2.1, §4.1) | B-M | body 21 bits / packet 44 bits example (L482-493). `enumerate.lisp` |
| Observation buckets: group expressions by output vector; invariant on `pairs`, informative on `anchors` (§2.1 L286-303) | B | `observation-invariants` `enumerate.lisp:728`. No incremental bucket refinement (L295) |
| Guarded laws from buckets; guards synthesized to reproduce a support mask; exhaustive finite validation by mixed-radix grid (§1.1 L55, §2.1 L305, §4.3) | B | `propose-observed-laws` `laws.lisp:215`, `start-law-validation` `laws.lisp:96`, `start-guard-search` now in `milestones/algebra-discovery.lisp:200` |
| `retype-law` across `(:gf p)` and `:int` (L317) | B | `templates.lisp:524` |
| Lossless law-corpus compression; negative gain allowed (§4.3 3B) | B | `milestones/corpus.lisp:64,202` (milestone-only now) |
| Rewrite rules compiled to `:code-*` VM programs (§4.3 3C) | B | `compile-rule-transformer` `laws.lisp:284` |
| Reorientation of recorded tuples (`orient-observations`) without re-simulation (§2.3.1) | B | `frame.lisp:342` |
| Pullback `B(Z)=A(d(x,Z))` and composition by AST inlining; no let-sharing (§2.3.2, L174) | B | `frame.lisp:544,839` |
| Conservative folding; conflicts `:unsatisfiable-row`, `:incompatible-rows` (§2.3.3) | B | `requirements.lisp:529`, `frame.lisp:300` |
| Dual-grade solvers: witness law + uniqueness law; certified replaces, tentative keeps fallback sibling (§2.3.4) | B | `propagate-requirements` `laws.lisp:736`; `validate-arithmetic-solver` `milestones/algebra-discovery.lisp:49` |
| 3:1 reserve scheduling (§2.3.4, L29) | B | `synthesize.lisp:968` |
| `infer-fibers`: branch-and-bound row partition, lexicographic proxy, feasibility unresolved (§2.2 L323-330) | B | `fibers.lisp:156` |
| Competing fiber hypotheses judged only at root (§2.2 L332-342) | B | design rule |
| Typed anti-unification with memoized disagreement tuples, operator holes; lowering to DSL constructor (§2.2 L317) | B | `unify.lisp:36,103` |
| Unaligned subexpression abstraction with occurrence pairs (§2.2 L319, §4.6) | B | `milestones/corpus.lisp:704` (milestone-only) |
| Quotient / partition / lookup models as ordinary ASTs (§1.3 L85) | B | `frame.lisp:392,1463,1473` |
| Boolean views `(if G b1 b2)`; bits-then-runtime ranking (§4.7) | B | `milestones/views.lisp:15,90,234` (milestone-only) |
| Locality scheduling of AU pairs: Manhattan on integer-list keys, tree/rank/path distance, `:locality-only` negative control (§4.7 L601-603) | B | `milestones/corpus.lisp:447,464,509` (milestone-only). Supplied keys only |
| Stage A correction pricing: signed difference, Lee displacement, componentwise tuples, min over witness set (§2.4 L389-409) | B | `correction-bit-size` `frame.lisp:1713`, `select-closest-witness` `frame.lisp:1719` |
| Relational residual: pair drift and anchor collision in bits (§2.4 L411-414) | B | `relational-linkage-residual` `enumerate.lisp:607` |
| Stage B: additive residual decoder `π̂(X)+Z`; conditional exception decoder `(if G π̂ Z)` (§4.8 L615-618) | B | `heuristic-decompositions` `decompose.lisp:515`, `find-sound-exception-guard` `decompose.lisp:240` |
| Lazy `:expand`, full-path pricing, anytime best-first over a flat agenda (§4.8 L620-622) | B-M (qualitative) | "y = x0+x1+x2+1 needs three nested residual spaces: not found at `:max-depth 2`, found without a limit" (L622) |
| Child scope cache; sibling nogoods as `(parent-id k1…km)` (§4.8 8B/8C) | B → S | scope cache STILL (`synthesize.lisp:264`); key-tuple nogoods superseded by S-expression `nogood-clause` (plan7-recursion §5.2) |
| Episode returns `G_t = B_t − B_T − λ(W_T − W_t)` (§4.8 L628-634) | B | `consolidate.lisp:5` |
| Pluggable DSL metric primitives / problem-supplied metric (§2.4 design note L435; open item 2 L641) | P in plan7 → built later | frame `metric` slot `frame.lisp:17-19`, `pulled-back-metric` `frame.lisp:563` (plan8 era) |
| Autonomous outer-decoder shell enumeration (open item 1 L640) | P | Only additive and conditional shells are built in; others "plug into `:expand`". NEVER-BUILT as general enumeration |
| Evidence-based stopping of expansion (open item 3 L642) | P | "such a branch is only deprioritised, never closed" |
| Autonomous locality-key synthesis (§4.7 L607) | P in plan7 → built later in another form | `:locality-key` kind and `induce-row-order` `proposals.lisp:625,707` |
| M9 vocabulary: opaque names, descriptor synthesis from behavioural probe frames, retrieval lane, eviction (§4.9) | P in plan7 → partially built in sub-plans | see §2.4, §2.5 |
| `J_procedure = J(M_P) + λ_search W_search(P)` as controller objective (§1.5 L117-123) | P | "not yet an automatically learned controller objective" |
| Experiment trace standard (§5.2 L684-692) | P | "a reporting requirement for new experiments" — not followed by the sub-plans (none report work/ledger numbers for their headline results) |

### 2.2 plan7-recursion.md (R1–R6)

| Mechanism | Status | Evidence / code |
| :-- | :-- | :-- |
| `:cons`, `:tail`, `:length`, `:<` primitives (Phase 1.1) | B | `ast.lisp:139-142` |
| Sequence-equality splitting and guarded call unfolding in `fold-constants` (Phase 1.2) | B | `try-unfold-call` `requirements.lisp:438` |
| `:code-eval`; named functions as `:code` S-expressions with de novo names `:fa, :fb…` (Phase 2.1) | B | `ast.lisp:143`, `define-function` `knowledge.lisp:591` |
| Closure capture by `:code-subst` (quasiquote) instead of closure structs (L72, App. A.2) | B | primitive `:code-subst` `ast.lisp:135` |
| Zero-copy call dispatch; O(1) call-step tariff (Phase 2.2) | B | `vm.lisp` |
| Structural totality analysis; transitive fixed point; cache invalidation (L76-78, App. A.1) | B | `analyze-function-body-totality` `ast.lisp:1023`, `provably-total-p` `ast.lisp:1160` |
| `:unresolved` outcome; constrained-row filtering (L80-81) | B | `frame-oracle-table` `frame.lisp:415` |
| Conserved-quantity observation → algebraic inversion to a generative model (Phase 3.1) | B (narrow) | `orient-conserved-quantity` `laws.lisp:931`; test `recursion-r3-conserved-quantity-observation-and-inversion` `tests/recursion.lisp:543`. `collect-observation-buckets` does not exist as a function |
| 1-to-many `lift-frame`; congruence closure over ground applications; symmetry refutation (Phase 3.2) | B | `frame.lisp:975,1194` |
| Call-path position as locality coordinate; adjacent call sites generate `pairs` (L141) | P | `lift-frame` returns `(make-frame schema active-rows)` with no pairs, anchors or edges (`frame.lisp:1267`); the occurrence index survives only inside the row key. NEVER-BUILT as stated |
| Oracle self-lift (`start-recursive-synthesis`), root verification with real recursion, per-row cutoff (Phase 3.2 item 4, App. A.3) | B-M (bits only) | `decompose.lisp:701`. Bodies: copy 89 b, inc-all 100 b, double-all 116 b, sum 84 b, length 68 b, product 87 b, insert 188 b (App. A.4, A.5) |
| Inductive sequence context lift: on guard `(= Xi '())`, inject `(at Xi '0)` and `(:self (tail Xi))` into child bindings (L149) | B | `lift-inductive-sequence-context` `decompose.lisp:384` |
| Stitch-style library AU: self-call normalization, control-spine AU, shared-subterm cover, positional `:code` extraction, MDL acceptance (Phase 4) | B-M | map: 305 → 127 + 80 = 207 bits, gain +98; foldr: 239 → 133 + 105 = 238, gain **+1** on three folds, +55 with a fourth, −16 on a pair (App. A.4 L377, L398). `abstraction.lisp:67,98,137,380`, `unify.lisp:134,211` |
| Library expander: learned combinators proposed as `:lift-p` decompositions; first-order argument population; empty-row filter (Phase 5.1, §5.3) | B-M (bits) | triple-all 75 b, add-scalar 86 b, sum-plus-one 88 b, sort `(:ff X0 '() '(:fd X0 X1))` 72 b (App. A.5). `proposals.lisp:6,71,108,152,252` |
| "Proposals are not ranked by hardcoded host rules (such as 'equal lengths ⟹ map')" (L192) | S | Reversed by plan7-m9-policy §2.2 and `:DESC/LEN-EQ` necessary-descriptor pruning |
| Nogood clauses as S-expressions; sibling/descendant pruning before lift (§5.2) | B | `nogoods.lisp:5,175,386`. Test compares work with/without (`tests/recursion.lisp:2061`), no number in the document |
| UIP: anti-unify conflict clauses into a pattern with holes (§5.2) | B | `nogoods.lisp:218,254` |
| DIP: find a minimal parent expression separating colliding row pairs, add it to bindings (§5.2) | B-M (bits) | add-len via `(length X0)`: 90 b (App. A.5 L422). `nogoods.lisp:446,489,540`. Candidates are 0-step variables and 1-step total applications only |
| Search-trace frame → condensed priority predictor (§5.2 L205-206, L228-230) | B | `consolidate.lisp:20,95`. Default description limit 59 bits (35-bit header + 24) |
| `node-may-expand-p` returns nil on lifted nodes (L216) | S | Relaxed in H2; current code has no lift condition at all (`synthesize.lisp:212`) |
| De novo names as vocabulary tokens "whose usage probabilities and context affinities are coupled to the search policy and language tariffs" (L65-67) | P | NEVER-BUILT (no usage-frequency code or context affinity anywhere) |
| Multi-step descent `(tail (tail Xi))`, non-lockstep multi-sequence recursion (`merge`), alternative emptiness guards, bounded integer recursion (§2.3) | P ("deferred refinements") | NEVER-BUILT in the kernel. `bootstrap/recursion-schemas.lisp` supplies lookahead, state-threading and counter schemas by hand |
| Stitch / e-graph efficiency roadmap (Phase 4.1 item 3) | P | Only rewrite-normalization before AU was built |

### 2.3 plan7-library.md (L1–L4)

| Mechanism | Status | Evidence / code |
| :-- | :-- | :-- |
| One flat list of `knowledge-entry` records with typed edges and derived indexes (§1, §3) | B | `knowledge.lisp:84,104` |
| `define-knowledge-kind` with `:validate/:install/:consume/:consolidate` hooks (§2.3) | B | `knowledge.lisp:36`; 14 kinds now |
| Entry = transform + applicability (types, guard, trigger) + residual (§2.1) | B | struct slots as planned |
| Generic S-expression persistence; storage bits (§4 Phase 1) | B | `persistence.lisp:61,131` |
| Evidence snapshots / currency check (appears in architecture2 §6.1, not in this plan) | B | `evidence.lisp:3,45,62` |
| `:relation` residual tables; hybrid `(if (member k keys) (lookup …) π̂)`; delayed pooled condensation ("cryogenic empirical buffer") (§2.1 item 3) | B | `relations.lisp:22,45,97`; test `library-l2-…` `tests/library.lisp:196` |
| Solvers generalized to invert learned functions, not only primitives (§4 Phase 2.2) | B | `propagate-requirements` over library; not audited |
| `:functor`: anti-unify `:inverts` edges across `:map` instances to get an inverse for any new `:map` call (§2.2 item 1) | B | `induce-functorial-solvers` `consolidate.lisp:2081` (was `bootstrap-inverters.lisp`, B-R as a file) |
| Theory motifs (Monoid / fold-homomorphism schema from shared edge stars; `foldr ↔ foldl`) (§2.2 item 2) | P here → built later | `:motif` kind, `induce-fold-motifs` `consolidate.lisp:833,951` (post-plan7; `:foldr=foldl/monoid` named in `bootstrap/build-batteries.lisp:766`) |
| Graph-neighbourhood locality: edge distance between entries as `:locality-key` for AU pair scheduling (§2.2 item 3) | P | NEVER-BUILT in that form. The `:locality-key` kind that exists orders *rows of a frame*, not library entries |
| Descriptors as VM-executable triggers computed at install (§4 Phase 3.1) | B → S | First host-computed (`compute-function-descriptor` `descriptors.lisp:130`), then a hand table (M9), now I/O-synthesized |
| Persistent `:nogood-schema`, `:dip-feature` with `:repairs` edges, `:heuristic` (§4 Phase 3.3) | B | `consolidate.lisp:170,203,237` |
| `consolidate-knowledge-library` closed loop (§4 Phase 4) | B | `consolidate.lisp:964`; pass limit 4 (`consolidate.lisp:961`) |
| Continual curriculum "strictly reduce search work on subsequent calls" (§5 Test 4) | B-M (inequality only) | `tests/library.lisp:419-450` asserts warm work < cold work on inc / shift-by-4 / add-len; no magnitudes in any document |

### 2.4 plan7-higher-order.md (H1–H4)

| Mechanism | Status | Evidence / code |
| :-- | :-- | :-- |
| Polymorphic retyping of learned combinators (H1.1) | B | `retype-function-definition` `templates.lisp:564`, `infer-function-template` `templates.lisp:314`, `*auto-retyped-functions*` `knowledge.lisp:650` |
| `:filter` pullback: three extra `fold-constants` rules keyed on a `:code-eval` condition (§4.1) | B | in `requirements.lisp` (rules described at architecture2 L381-383) |
| `function-body-subsequence-filter-p` linear-time prune (§4.1) | B-R | GONE (b3af2e6) |
| Lockstep multi-sequence recursion when lengths match (H1.3, §4.1) | B | `lockstep-inductive-sequence-decomposition` `decompose.lisp:416` |
| Reentrant expansion of lifted nodes for 2D (H2.1, §4.2) | B | `node-may-expand-p` `synthesize.lisp:212`; test H2 registers `:sum` and `:dot-product` by hand first (`tests/higher-order.lisp:206-211`). Outer product, matrix-vector and row sums are tested; the matrix-matrix contraction / `einsum` that architecture2 L627 lists as flattening the same way has no test (no `einsum` or `contraction` in `tests/higher-order.lisp`) |
| `filter-map-decompositions` host template `(:map (:filter X pred) Z)` (§4.2) | B-R | GONE; replaced by a hand-registered `:comprehension/filter-map` decoder template (`bootstrap/build-batteries.lisp:711-718`) |
| Coupled-requirement penalty in priority (§4.2) | B | `synthesize.lisp:445,503` (16 per coupled requirement) |
| `propose-locality-stencil-bindings` (1D shifts, 2D row/column/diagonal/minor moves) (H2.2) | P | NEVER-BUILT (no `stencil` proposer in kernel) |
| 2×2 determinant, 1D convolution `y_i = x_i + x_{i+1}`, Laplace determinant (matrix row H2.3) | P | NEVER-BUILT as described (an adjacent-pair test exists under the later M9 suite, `tests/higher-order.lisp:630`; determinant/minor appear only in `tests/metrics.lisp`) |
| Sampled-fiber active set with reserve rows (H3.1) | B | `*max-active-lifted-rows*`; planned keyword `:max-lifted-rows`/`sample-lifted-rows` never existed under those names |
| CEGAR promotion of a refuting reserve fiber after root verification fails (H3.3) | B-M (one case) | `synthesize.lisp:1189`; test with `*max-active-lifted-rows*` = 2 promotes row `(3)` and converges to `(* X0 X0)` (`tests/higher-order.lisp:336-381`). The planned "36 fibers vs 6, strictly less work" comparison (L243) is not reported |
| Quotient-canonicalized scope sharing for lifted frames (H3.2) | B | `child-scope-signature` `synthesize.lisp:264` |
| Pointwise binary step → position-0 sequence inverter and position-1 parameter solver (§4.4) | B | `extract-pointwise-binary-step` `consolidate.lisp:1949` |
| Involution law → unary solver (§4.4) | B (renamed) | `induce-involution-solvers` GONE under that name |
| Group-action law `(= (F (F X0 X1) (- '0 X1)) X0)` → inverse by negated parameter (H4.1) | P | NEVER-BUILT |
| Cross-correlation lag estimator `:argmax-corr`, moment estimators as tentative solvers (H4.2) | P here → supplied later | Not in the H4 notes. `:spec/argmax-corr` and `:spec/solve-shift-seq-by-correlation` are hand-written specs in `bootstrap/build-batteries.lisp:878-904`. In the H4 test `:shift` is an elementwise additive shift over GF(5), not an index shift (`tests/higher-order.lisp:387-407`) |
| Reported totals | B-M | "4 comprehensive test suites (203 checks) and 155 total tests (345,194 checks)" (L292) |

### 2.5 plan7-m9-policy.md (M9.1–M9.4)

| Mechanism | Status | Evidence / code |
| :-- | :-- | :-- |
| Diagnosis: `lift-frame` unfolds everything before Stage A can score; budget exhaustion reverts the whole spine (§0 item 1) | measured problem | "warm discovery work on `inc-list` to jump from 19,147 to 48,573" when all decoder templates are proposed (L21) |
| `:max-fibers` partial head-prefix unfolding under `:contract :necessary` (§1.1) | B | `requirements.lisp:134,466` |
| `deferred-conjuncts` third return value of `fold-constants` (§1.1 item 2) | P | NEVER-BUILT (no such symbol) |
| `probe-frame-coordinates` (§1.2) | B | `frame.lisp:1108` |
| 3:1 contiguous-window fiber selection (fixes "Pass 2 selects first and last, destroying adjacency") (§1.2) | B | `frame.lisp:1039` |
| Evidence-calibrated fiber schedule `k(t)`, `expand-lifted-reserve-fibers` doubling (§1.3) | partly | `unfolded-reserve-rows` `synthesize.lisp:1155` unfolds a full spine on demand; no doubling schedule found |
| Smooth sequence residual pricing (length delta + per-element deltas, capped) (§2.1) | B | within `correction-bit-size` `frame.lisp:1713`; test `tests/library.lisp:468-470` |
| Substance-specialized fast guards (map: equal length; filter: subset; derivative: length−1; outer product: 2×2 minors; permutation: equal sum) (§2.2) | B then S | hand-listed here; the table was removed (c4cb6e8); some `:DESC/…` keywords survive in `descriptors.lisp` |
| `descriptor-clause` (id, facet, tier, status, weight-bits, work-cost); five facets (§3) | B (table B-R) | `make-descriptor-clause` `knowledge.lisp:67`; `*descriptor-table*` GONE |
| Compositional name as secondary address (§0 design decision 1, §3.1) | B | `derive-compositional-name` `descriptors.lisp:164`, `find-knowledge-entries-by-address` `knowledge.lisp:273` |
| Overlapping policy score `ΔJ_policy` (prune / bonus / half penalty / 0) (§4.1) | B | `score-entry-by-descriptors` `descriptors.lisp:966`, `evaluate-frame-descriptors` `descriptors.lisp:915` |
| Deferred proposal queue (§4.2) | B (off by default) | `synthesize.lisp:915,1042` — limit defaults to nil |
| `consolidate-policy-descriptors`: update weights from traces; "synthesize new discriminative `:descriptor` guards when two operators share a type signature" (§4.3) | half | Weight update only: ±1 bit per job, bounded to [1, 12] (`consolidate.lisp:382-411`). Discriminative-guard synthesis not in that function; descriptor synthesis from I/O exists separately (`descriptors.lisp:392`) |
| Arity-safe 4-/6-input predictor (§4.3) | B | `priority-predictor-function` in `synthesize.lisp` |
| Post-M9 measurement | none | The document reports only the pre-fix regression; architecture2 reports no number |

---

## 3. Recursion and lifting

### 3.1 How each piece was meant to work

Sequences. A sequence is a host list typed `(:seq τ)`. Induction is by `:cons`/`:tail`/`(at xs '0)`; emptiness is `(= xs '())` (plan7-recursion Phase 1.1 L40-43).

Recursion. A recursive function is a named body over positional variables; a self-call is an ordinary operator application `(:fa (tail X0))`. The VM executes it on its explicit task stack, charging one unit per call (Phase 2.1-2.2). Non-termination ends in `:cutoff`.

De novo recursive synthesis ("oracle self-lift", Phase 3.2 item 4 and App. A.3):
1. Register the unknown function with the specification frame as a partial lookup table; calls on inputs absent from the table return `:unresolved` ("unrefuted rather than false").
2. Run ordinary Stage A (find a base model) and Stage B (find a guard separating hits from misses). When the guard found is exactly `(= Xi '())`, the host function `lift-inductive-sequence-context` adds `(at Xi '0)` and `(:self … (tail Xi) …)` to the child's inputs and grammar. The child then solves a non-recursive problem "given head H and recursive result R, produce Y".
3. At root verification the oracle is swapped for the candidate body and the real recursion is executed on every row under a per-row step budget; oracle-only fits such as `(:fa X0)` loop and are rejected by cutoff.

Map/fold/filter. Not primitives. `:map` and `:foldr` were obtained by anti-unifying solved recursive bodies along their shared control spine and abstracting the differing step into a `:code` parameter (Phase 4; numbers in §2.2). `:filter` has the same shape and passes the totality check (plan7-higher-order H1.2).

`:code` parameters. A `(:code inputs sort)` value is quoted syntax in an explicit scope. A higher-order function calls it with `:code-eval`. Outer variables are captured by `:code-subst`, which splices a runtime value into the quoted template as a literal (App. A.2).

"Inductive lift" vs "1-to-many lift". Two different things share the word:
- The inductive lift (above) projects head and recursive call into the child's inputs.
- `lift-frame` (Phase 3.2 items 1-3; architecture2 §3.3) handles an unknown `:code` hole inside a known higher-order decoder: pull the requirement back through the decoder, let `fold-constants` unfold the recursion on concrete inputs and split sequence equalities, run congruence closure so nested unknown-function applications become ground, and emit one child row per distinct ground call `F(a)`. The second-order problem becomes a first-order frame.

Functor lifting. Given an elementwise solver for `step` and a function refactored as `(:map xs 'step)`, build the sequence-level inverse `(:map y 'step⁻¹)` with a fold-conjunction guard (plan7-library §2.2 item 1; architecture2 L546-547). The artifact is a `:code-*` meta-program stored as a `:functor` entry.

Nogoods / DIP repair. A failed lift records the colliding input bucket as an S-expression clause; identical lifts are pruned; clauses are anti-unified into a pattern (UIP); DIP looks for a small parent expression that takes different values on the colliding parent rows and re-proposes the lift with that expression as an extra binding (plan7-recursion §5.2; worked on `add-len`, App. A.5).

CEGAR. Solve the lifted child on a sample of fibers, verify the composed program on all root rows, and on failure promote a refuting reserve fiber into the child frame (plan7-higher-order §1.3, H3).

### 3.2 Host Lisp versus object language

What a synthesized program can itself invoke (VM primitives, `ast.lisp:118-146`):
- substitution into syntax: `:code-subst`; matching and binding: `:code-match`, `:code-bind`; construction and inspection: `:code-apply`, `:code-kind`, `:code-child`, `:code-operator`; syntax order and totality tests: `:code-less`, `:code-total`;
- execution of syntax: `:code-eval`;
- sequence induction primitives and calls to named functions, including itself.

What exists only as host Lisp over host structs (not callable from a program, not representable as a program's value):
- frames, rows, schemas, decompositions, synthesis nodes and jobs (plan7.md L27);
- `pullback-frame`, `lift-frame`, `compose-lifted-model`, `congruence-close-code-evals`;
- `fold-constants`, including recursion unfolding and the `:filter`-specific rules;
- `lift-inductive-sequence-context` and the lockstep variant — the step that turns "a guard was found" into "a recursion is proposed";
- the oracle table mechanism and implementation swapping;
- `anti-unify`, `anti-unify-for-library`, `shared-subterm-cover`, `abstract-over-subterms` (only AU's *result* is lowered to a `:code-*` constructor by `compile-au-constructor`);
- nogood creation, UIP, DIP candidate enumeration; CEGAR; scope cache;
- `infer-fibers`, partitioning, quotienting;
- functor induction (the induced artifact runs on the VM; the induction does not).

So in these documents substitution is an object primitive and lift is not, exactly as the owner says. The documents never frame this as a deficiency; architecture2 presents `lift-frame` as a finished feature. The current code is more candid: `bootstrap/recursion-schemas.lisp:2-12` opens with "Recursion schemas the battery curriculum is given, not ones the kernel finds… written by hand… Retiring one means giving the kernel a general way to propose its recursion (a self call whose arguments are synthesized) or storing it as a decoder template."

Partial counter-examples worth keeping (kernel operations that *were* moved into the object language):
- rewrite rules are compiled to `:code-*` programs and applied on the VM (plan7.md §4.3 3C; `laws.lisp:284`);
- AU patterns are lowered to constructor programs (`unify.lisp:103`);
- nogood clauses are S-expressions evaluated on the VM (`nogoods.lisp:254`);
- functor entries are meta-programs that build solvers;
- the search trace is packaged as an ordinary frame (`consolidate.lisp:20`).

### 3.3 What was hand-supplied

- The recursion schema itself: structural descent on one list by `(tail Xi)` under `(= Xi '())`. It is hard-wired three times: in the inductive lift (`decompose.lisp:384`), in the totality analysis (`ast.lisp:1023`), and in descriptor shape proofs (`descriptors.lisp:28`). plan7-recursion App. A.3 L345 says "Neither the base-case expression nor the `(= Xi '())` split is hardcoded"; true of the guard search, not of what is done once that guard appears.
- Per-task grammars. Each R4 task gets just the operators and literals it needs, e.g. inc-all: `:literals '(1)`; insert: `{cons, at, tail, <, =, if}` and no arithmetic (`tests/recursion.lisp:954-1000, 1080-1095`).
- Example design. Inputs are suffix-closed so the oracle resolves (`()`, `(3)`, `(1 3)`, `(4 1 3)`); fold examples are "prefix-closed" so congruence closure grounds the accumulator (plan7-recursion L136, L243). One deliberately incomplete row exercises `:unresolved` (`tests/recursion.lisp:1080`).
- Curriculum order. `insert` is synthesized first; `sort`'s language then contains `insert` as an operator and omits `:<` (`tests/recursion.lisp:1108-1119`).
- Library corpus. The six functions anti-unified into map and foldr were chosen as three of each. The foldr abstraction clears MDL by one bit on three examples and fails on two (App. A.4 L398).
- In the R6 test, `:map` and `:foldr` are written out by hand with `define-function` and the competing decompositions are constructed explicitly (`tests/recursion.lisp:2043-2085`).
- H2 registers `:sum` and `:dot-product` by hand before the matrix-vector task (`tests/higher-order.lisp:206-211`).
- Host templates: filter-map detection rules (`|out| ≤ |in|`, not a pure subsequence, …), lockstep detection by equal lengths, first-order argument population from empty-row targets.
- The descriptor vocabulary of M9 (§2.5).

### 3.4 Budgets and outcomes

The seven documents report description bits but almost no search work for recursion. The only work figures are the 129-bit multiply tariff (16,641 units; plan7.md L517) and the M9 regression (19,147 → 48,573; plan7-m9-policy L21). plan7-recursion's verification matrix promises a "search-work comparison with and without deductive leaf clauses" (L246) and gives no number.

From the tests as they stand (my grep, not the documents): description limits 60–110 bits; `resume-synthesis` budgets in `tests/recursion.lisp` range 2,000–500,000 units (mode 50,000; insert 100,000), `tests/higher-order.lisp` 30,000–150,000, `tests/library.lisp` 120,000. Stage A default budget 2,000 (`synthesize.lisp:66`); trace condensation 10,000 (`consolidate.lisp:96`). These are seconds, not hours.

Found (as claimed, with tests present): copy, inc-all, double-all, sum, length, product, insert, sort (through insert), map and foldr by AU, triple-all, add-scalar, sum-plus-one, add-len (DIP), dot-product and zip-with by lockstep recursion, outer product, matrix-vector product, row sums.

Not found or not attempted: anything needing a second base case, threaded state, a counter, or `(tail (tail xs))` (foldl, scan, map-adjacent, shift, best-shift — all later supplied as hand schemas); merge-style recursion; mutual recursion; stencils; determinant; matrix-matrix contraction (planned at plan7-higher-order L242, not in the H2 test list); correlation-based inverses.

---

## 4. Library and policy

### 4.1 Intended library (plan7-library)

- Store: one append-ordered list of `knowledge-entry` records; hash indexes are derived (§3.3). Edges are alists on entries plus an incoming-edge index; vocabulary of twelve edge kinds (§3.2): `:abstracts`, `:refactored-by`, `:normalized-by`, `:rewrites`, `:inverts`, `:certified-by`, `:retyped-from`, `:describes`, `:repairs`, `:has-residual`, `:induces`, `:condensed-from`.
- Entry anatomy: `expression` (transform), `guard` (exact validity), `trigger` (cheap heuristic applicability), `residual` (bare table), `auxiliary-code` (compiled matcher/transformer), `status`, `certificate`, `bits`, `gain`, `work`, `edges`, `metadata` (§3.1).
- Evidence: status symbol plus certificate; architecture2 §6.1 adds statement snapshots (versions, schema, ASTs, transitive function dependencies) that every consumer rechecks.
- Addressing: primary opaque id (`:fa`, `:LAW-0`); M9 adds a compositional name built from descriptor facets, e.g. `:COMB/CODE+SEQ->SEQ/LEN-EQ/EMPTY->EMPTY/POINTWISE` (plan7-m9-policy §0, §3).
- Closed loop: synthesis consumes the library (grammar, propagators, rewrites, nogood schemas, predictor); consolidation re-derives abstractions, validates pending laws, pools residuals, induces functors, updates policy (§4 Phase 4).

### 4.2 The M9 policy / heuristic-induction design

| What was to be learned | Signal | Mechanism | Built? |
| :-- | :-- | :-- | :-- |
| Node priority correction | Per-node trace tuples `(program-bits, residual-bits, depth, constrained-rows[, policy-score, coupled-count]) → realized cost` (documents). In the current code the target is the signed gap between the best verified score in the node's subtree and its analytic price, clamped to [−24, 48] (`consolidate.lisp:20-24`) | Package tuples as an integer frame; run ordinary Stage A condensation; deploy the resulting expression, discarding its residual | Yes. Hypothesis space: `{+, *, −}`, literals `{0,1,2}`, at most header + 24 bits, 10,000 work units (`consolidate.lisp:95-112`). Output clamped to [−24, +48] bits and added to the analytic price (`synthesize.lisp:489-507`; `priority-predictor-function` `synthesize.lisp:459`) |
| Per-entry descriptor weights `w_{e,i}` | Which library entry lay on the winning path of a finished job; which sibling finished without a search | +1 bit to all clauses of winners (cap 12); −1 bit to empirical clauses of losers (floor 1) | Yes (`consolidate.lisp:382-411`) |
| Which descriptors exist | (M9 as written) nothing — a hand list of length/shape/boundary/minor tests | Hand table | Built, then removed; replaced by descriptors found by a short observation search over an entry's sampled I/O (`descriptors.lisp:340-392`) |
| Hard applicability | A descriptor marked `:necessary` that is false on the frame | Prune before any pullback | Yes |
| Proposal order | `ΔJ_policy` sum of bonuses/penalties | Sort, prepare top-B, defer the rest | Yes, but B defaults to unlimited |
| DIP repair preference | `:repairs` edges from past repairs | Try linked features first | Yes |
| Episode return `G_t` | Best score and ledger at each scheduling step | Computed and stored | Computed (`consolidate.lisp:5`); I found no consumer that trains on `G_t` itself — the trace frame is built from candidate messages and per-lane work, not from `synthesis-episode-returns` |
| When to stop expanding | — | — | No (plan7.md L642) |
| Search objective `J + λ W_search` | — | — | No (plan7.md L123) |

Measured effect, as far as these documents go: none after the fix. The single number is the *problem* M9 was written to solve — registering decoder templates made warm search 2.5× more expensive (19,147 → 48,573). Tests assert only strict inequalities on a family of near-identical tasks.

plan7-m9-policy's own assessment of the pre-M9 predictor is the most useful sentence in the document for the owner's purpose: it "sees only 4 scalar integers `(prog-bits, res-bits, depth, constrained-rows)` — completely blind to frame types, shapes, shape deltas, sampled contents, and operator identity" (L22). Adding two more integers did not change that in kind.

### 4.3 Bearing on geometry and reflection

- The descriptor profile is a sparse binary feature vector per library entry and per frame, with integer log-odds weights, scored additively. It is the only "embedding" in v1, and it is addressed by exact keyword match, with no notion of two descriptors being near each other.
- The trace frame is the only place where the search's own behaviour re-enters as data. What re-enters is six integers per node; the graph of nodes, decoders, conflicts and reuse does not.

---

## 5. Recurring problems the documents themselves acknowledge

1. Lifting cost explodes and is paid before scoring. "`lift-frame` executes before Stage A… forcing every proposed higher-order combinator or template to pay full unfolding work before the agenda can even score whether the branch is plausible" (plan7-m9-policy L16); child rows grow as `|Ω|·M·N` (plan7-higher-order L90).
2. All-or-nothing folding. Running out of budget mid-spine discards every fiber already extracted (plan7-m9-policy L15).
3. Library growth makes search slower. 19,147 → 48,573 (plan7-m9-policy L21). Names and triggers are "opaque and unweighted" (L18-20).
4. The learned predictor is nearly blind (plan7-m9-policy L22) and suffered an arity mismatch between kernel and tests (L22, §4.3).
5. Local prices are not comparable across child spaces, so everything is repriced at the root; the price is "one step deep" (plan7.md L338, L437).
6. Inlining duplicates cost: "there is no implicit `let`-sharing" (plan7.md L174, L455).
7. Fiber clustering is a proxy with unresolved feasibility; pre-clustering can hurt (plan7.md L326-334).
8. Row-to-row linkage is fragile: preserved by one-to-one transforms, dropped by row-subsetting transforms (plan7.md L172) and absent on lifted frames.
9. Supplied controls everywhere: decoders, feature vocabularies, locality keys, candidate lists (architecture L17); only two decoder shells are built in (plan7.md L640).
10. Return contracts are producer-specific; no uniform message envelope (architecture L240; plan7.md App. A item 6).
11. Totality analysis covers one recursion shape (plan7-recursion §2.3).
12. Symbolic misses cannot be priced: "If a miss has no extractable witness list, the candidate is not scored" (architecture L181).
13. Credit assignment through non-injective aggregators is unsolved except by sampling and re-verification (plan7-higher-order L91).
14. Documentation drift: "documentation very out of date now" (commit 8a06293); architecture2 stale on commit day (§1.3 row 11).
15. Per-level machinery. The owner's own diagnosis, recorded verbatim in plan7-higher-order §0 L13: the VM/synthesizer "has to handle each level of abstraction with dedicated machinery". The H1–H4 response added more dedicated machinery (three `:filter` fold rules, a filter-map template, a lockstep detector).

---

## 6. Nuggets for the current lens

### (a) Frames as fibers/bundles; lift, project, pullback; residual calculus

1. "A metric and a decoder shell are two views of one correction code: the shell reconstructs a value from a residual, and the metric prices that residual before it is synthesized." — plan7.md §4.8 open item 2, L641.
   Why now: the cleanest statement in the trail that a topological edge (decoder) and a geometric object (metric on its residual space) are the same thing seen twice. A unified kernel can store one object with both readings.
2. Pullback versus inversion: pullback substitutes the decoder into the check and "preserves the entire set of valid Z values—whether empty, unique, or multi-valued"; inversion "directly computes one solution value", dropping the others unless uniqueness is certified — plan7.md L156.
   Why now: pullback is the fiber; inversion is a choice of section; the uniqueness law is the statement that the fiber is a point. Reorientation in a graph kernel needs all three as distinct, typed operations.
3. Value fibers versus row blocks — plan7.md L160. The word "fiber" names both the allowed-value set over one row and a block of rows sharing a latent value.
   Why now: the first is the domain of a free port on a hyperedge; the second is a partition of the base. v1 conflates them in naming (`infer-fibers` computes blocks).
4. Two residuals: θ (AU substitution or quotient index — "part of the program") and ε (correction packets — paid in training, dropped at deployment) — plan7.md L170.
   Why now: the owner's "labeled residual" of a substitution is θ; ε is the geometric remainder. v1 keeps them in unrelated structures.
5. "Stage A runs at every node on that node's own pulled-back frame. A decoder that changes representation (for instance mapping to an angle) therefore has its residual priced in the new space, using witnesses that the learned library exposes by inverting the decoder… The routing priority adds the candidate composed to the root to the child's residual bits, so branches in different spaces compete in one currency. This price is one step deep" — plan7.md L437.
   Why now: this is v1's actual answer to "ambient or induced space?": residual in the induced space, program in the ambient one, compared at the root. Its admitted weakness ("one step deep") is where a learned geometry would help.
6. `lift-frame` as a generic construction: unfold on concrete inputs, congruence-close, one child row per ground call keyed `(parent-key . path)`, same-input tightening as a "symmetry test" — plan7-recursion Phase 3.2 L133-141; architecture2 §3.3.
   Why now: the algorithm is sound and general (a second-order unknown becomes a first-order table); what is wrong is its location (host code over host structs).
7. Cross-row congruence closure "resolving intermediate accumulators on prefix-closed fold data without any combinator-specific deduction rules" via "union-find congruence closure over hash-consed ground application terms" — plan7-recursion L136.
   Why now: v1 already contains a small e-graph-like step; the owner asks whether e-graphs are needed.
8. Entry anatomy `(π̂, G, T, ε)`: transform, logical guard, heuristic trigger, residual — plan7-library §2.1.
   Why now: a candidate uniform payload for a hyperedge: what it computes, where it is valid (partition), when to try it (geometry), what it leaves over.
9. "Cryogenic empirical buffer": keep incompressible residual tables and condense them jointly later, when `Σ S(ε_k) > S(L) + Σ S(ε_k | L)` — plan7-library §2.1 item 3.
   Why now: residuals as first-class stored objects that structure can later be found in; supports long-horizon search.
10. Generated linkage: a partition yields must-agree chains (`pairs`) and must-differ representatives (`anchors`) — plan7.md L172.
   Why now: row-to-row relations were already edges; the current frame struct has a typed `edges` slot (`frame.lisp:20-24`).

### (b) Learning dependency structure by experiment

1. Projection as experiment: projecting rows onto a feature subset "changes which rows collide as 'same-input' tuples during tightening" — plan7.md L335; a collision with incompatible requirements is a refutation of "the target depends only on these inputs".
   Why now: this is the v1 form of "hold all but a few constant". It works on recorded rows only; nothing in these documents runs the simulator on chosen inputs except exhaustive law validation.
2. DIP: after a lift fails because two parent rows collide on one child input, search for the smallest parent expression that separates every colliding pair and add it as a dependency — plan7-recursion §5.2 L203, App. A.5 L420-422.
   Why now: a dependency edge learned from a failed experiment, with the failure stored as data. The candidate space (variables and one-step applications) is the limit.
3. "A meta-function with b bits of freedom is constrained by O(b) scalar fiber observations" — plan7-m9-policy governing principle, L5.
   Why now: an experiment-budget rule that does not depend on frames: sample in proportion to hypothesis size, ratify afterwards.
4. Structural probes that test a dependency pattern directly: `Y00·Y11 = Y01·Y10` for a multiplicative outer product, `Y00+Y11 = Y01+Y10` for an additive one — plan7-m9-policy §2.2 L89.
   Why now: these are separability tests (does the output factor through two independent inputs?). Hand-listed in v1; in a topology kernel they are instances of one "does this hyperedge factor" experiment.
5. Sound refutation on a sample: "a conflict… on Ω_sample is 100% sound for the full frame" — plan7-higher-order §1.3 L114.
   Why now: refutations need few fibers, confirmations need all; this asymmetry should shape experiment scheduling.
6. `transition-probes`: reorient recorded transitions into before/after pairs "without rerunning the transition" — plan7.md L541.

### (c) Law discovery and reorientation

1. "A conserved relation R(X,Y)… is initially a passive test… Algebra turns passive conservation into active generation and backward constraint propagation" — plan7.md L20.
2. The three-stage pipeline from conserved quantity to generator, with worked cases: copy `I − j = 0`; reverse `(I + j) − (n − 1) = 0 ⟹ I = (n−1) − j`; map-inc `Y_j − X_j = 1`; fold-sum `(Y − Z) − H = 0 ⟹ Y = H + Z`; sort as conserved length, membership and adjacent order — plan7-recursion Phase 3.1 L112-130. Code: `orient-conserved-quantity` `laws.lisp:931`.
   Why now: the only place in my documents where a law is found from data and then turned into the program. It is the owner's "conservation → generative expression" in miniature, and it produced `reverse` without a recursion schema.
3. A solver is two laws: witness soundness `G ⟹ f(k, q(k,c)) = c` and fiber uniqueness `G ⟹ [f(k,z)=c ⟺ z=q(k,c)]` — plan7.md L379.
   Why now: reorientation of an edge is itself certified by laws about that edge, so laws and inverters can live in one store.
4. Guards as learned partitions: "Support masks for partial equations become Boolean `support-frame` targets… Guards must reproduce the observed support exactly" — plan7.md L305.
   Why now: matches the owner's "a conditional is a partition… learned experimentally".
5. Second-order induction over edges: anti-unify `:inverts` edges across `:map` instances to obtain an inverter for every future `:map` call — plan7-library §2.2 item 1.
6. Theory motifs from shared edge stars (Monoid / fold homomorphism; `F(append(a,b)) = F(a) ⊕ F(b)`) — plan7-library §2.2 item 2. Later built as `:motif`.
7. Unbuilt but well-posed: group-action law `F(F(x, δ), −δ) = x` gives the inverse for free — plan7-higher-order H4.1 L222.
8. Owner's remark: "the inverses to linear algebra operators are themselves linear algebra operators… to determine an offset for a shift operation, it usually suffices to do a cross-correlation" — plan7-higher-order §0 L17. The design answer was to *register* such an estimator as a tentative solver, not to discover it.

### (d) Graphs / hypergraphs / relational edges as the store

1. "One Flat Homoiconic Store with Relational Linkage ('Graph over a Graph')" and "Edges… are second-order relational facts… stored in the same flat homoiconic format" — plan7-library §1 item 1, §2.2.
   Why now: the library is already a typed multigraph over entries. What it leaves out is everything transient: frames, rows, nodes, conflicts, traces.
2. "Frames, laws, certificates, and continuations are Lisp structs around them, not object-language programs" — plan7.md L27.
   Why now: the precise boundary the owner wants removed.
3. Scope-cache sharing: prepared `(frame, language)` signatures are canonicalized "up to row-order isomorphism" and reused across branches — architecture2 L589; plan7-higher-order H3.2.
   Why now: v1 avoided graph isomorphism by canonical serialization: rows are sorted by their printed `(known, requirement)` form and linkage is rewritten in terms of those ranks (`canonical-linkage-signature` and `child-scope-signature`, `synthesize.lisp:243-275`). That is a data point on how much isomorphism testing is really needed.
4. Synthesis DAG with followers: one canonical child, many parents each re-pricing through their own decoder — plan7.md L342.
5. Nogoods carry both a child-scope and a parent-scope clause plus the normalized decoder — plan7-recursion L218. A conflict is a small subgraph (decoder, bindings, two rows), already stored as such.

### (e) Geometry

1. Type-directed correction metrics: signed difference on integers; "centered modular Lee displacement" on `GF(p)` "rather than a flat ⌈log₂ p⌉ constant"; componentwise on tuples; length delta plus per-element deltas on sequences — plan7.md L404-409; plan7-m9-policy §2.1.
   Why now: the ambient metric of v1, fixed per type. It is a bit-priced distance, which is what a geometry layer would have to generalize.
2. Pair drift and anchor collision priced in bits; anchors exist "preventing constant collapse from scoring zero residual bits" — plan7.md L411-414.
   Why now: attract-pairs / repel-anchors is a contrastive objective in MDL units, already implemented.
3. Locality as a supplied key: Manhattan distance on integer-list keys, plus tree, rank and path distances; "A scalar key is not interpreted as an ordinary numeric distance" — plan7.md L601-603; architecture §4 L210.
4. "Sharing relational edges defines a natural graph distance between library entries" — plan7-library §2.2 item 3. Never built.
   Why now: the owner's "proximity flows along verified topological links", stated a fortnight earlier and left on the table.
5. Compositional descriptor address as a discrete embedding of library entries and frames — plan7-m9-policy §3.
6. Locality bias from description length: "coordinated local moves… cost only a few bits and are enumerated first, giving a natural locality bias without baking grid heuristics into the VM" — plan7-higher-order §1.2 L77.
7. Operators as space constructors: every multidimensional operator "constructs a target space from origin spaces via two small `:code` parameters": a coordinate/neighbourhood projection rule and a local combination rule — plan7-higher-order §1.2 L40-43; and the owner's wording in §0 L13 ("construct new spaces that are also of a relatively simple parametric form from the origin spaces").
   Why now: a concrete proposal for what "make a space" means: (projection, combination) pairs.
8. architecture.md's explicit list of missing geometry: "Learned residual geometry, graded pair/anchor constraints, loss transport through decoders, and automatic locality-key synthesis are not implemented" (L214). Since then: frame metric and metric pullback, and row-order locality keys, exist in code; learned residual geometry does not.

### (f) Learned heuristics and policies

1. The trace-frame idea: turn node outcomes into an ordinary frame and reuse the one condensation routine — plan7-recursion §5.2 L205-206.
   Why now: right shape (search experience becomes a synthesis problem), wrong content (six integers).
2. Diagnosis of blindness — plan7-m9-policy L22 (quoted in §4.2).
3. Policy as overlapping weighted predicates with necessary/empirical grades — plan7-m9-policy §4.1.
4. Score before you pay: deferred proposals — plan7-m9-policy §0 design decision 2, §4.2.
5. Episode return `G_t` — plan7.md L628-634.
6. Reserve scheduling as the safety net that makes learned bias harmless — plan7.md L29, L383.
7. Negative result: adding library knowledge without a policy more than doubled work — plan7-m9-policy L21.

### (g) Language

1. De novo names as "vocabulary tokens whose usage probabilities and context affinities are coupled to the search policy and language tariffs" — plan7-recursion L65-67. Never built.
   Why now: the only sentence in my set that ties names to a learned code. In the code a name's cost is its registration index (4-bit opcode, then Elias-delta), not its usage.
2. A name composed of behavioural predicates, each token narrowing meaning — plan7-m9-policy §3; "should not be addressed solely by an opaque symbol… but also by a secondary compositional address formed from the overlapping set of cheap… descriptors" (L5).
   Why now: nearest precedent for "each word modifies semantic meaning". It covers the owner's "like" terms only; there is no "analogy" (vector) or "action" (make a space) term.
3. M9's original question: "Can learned functions be exposed through opaque names and retrieved using compact symbolic descriptions of their behavior?" — plan7.md §4.9.

### (h) Reflection and reentrancy

1. Owner, verbatim: "reentrancy 'flattens' recursive datastructures like nested frames/fibers, and allows flexible shifting levels of abstraction, which combats ballooning complexity in the VM, which has to handle each level of abstraction with dedicated machinery" — plan7-higher-order §0 L13.
2. The agent's reading of reentrancy was narrower: one VM task stack for nested calls, and lifted nodes allowed to expand again on the same agenda — plan7-higher-order §1.3 L84-86. Nothing about the synthesizer operating on its own structures.
3. "Search leaf messages… should act as first-class S-expression deduction rules / learned clauses… rather than imperative host callbacks" — plan7-recursion §1 item 4 L30, §5.2.
   Why now: a worked precedent for moving control knowledge into data the VM evaluates.
4. Pluggable metrics were deferred because they are "likely to be unified with general search reentrancy" — plan7.md L435, L641.
5. Existence proofs listed in §3.2 (compiled rewrites, lowered AU constructors, functor meta-programs).
6. Staged work: host steps are charged to the ledger and published only when paid — architecture L116; architecture2 §5.1 item 1. Costs of host operations are therefore already observable, even though the operations are not data.
7. Provenance records and `explain-synthesis-job` — architecture L191. The search graph exists as host data for a human reader.

### (i) Totality, crashes, learned guards

1. Four outcomes: `:value`, `:error`, `:unresolved`, `:cutoff` — plan7-recursion App. A.1 L254-258.
2. "Static totality… only gates algebraic erasure, substitution, and constructor splitting… it does not restrict what functions can be defined, enumerated, or executed in the VM (where the step budget handles arbitrary general recursion)" — plan7-recursion §2.3 L97.
   Why now: v1 already tolerates crashing and non-terminating candidates at run time; totality is needed only to license rewrites. That separation can be kept.
3. Errors and cutoffs "never simplify to nil (false)" — architecture2 L374.
4. `:unresolved` means "unrefuted rather than false" — plan7-recursion L94.
5. Non-termination used as evidence: oracle-only fits "loop infinitely… hit the per-row VM cutoff, and are rejected" — plan7-recursion App. A.3 L342.
6. Guards learned from support masks (see (c)4); solver guards `G(K,C)`; tests on zero divisors — plan7.md §4.3 3A.
7. Branch-sensitive totality: inside the else-branch of `(= Xi '())`, `(at Xi '0)` and `(tail Xi)` are total — architecture2 L161.
   Why now: a guard creates a region in which a partial operation is safe — a partition with a certificate. In v1 this one case is hand-coded; the general "learn the guard under which this never crashes" is what the owner asks for.
8. Workaround, not learning: Stage A's language "filters out partial sequence destructors/oracles when the frame contains empty-sequence rows" — architecture2 L552.
9. Listed boundaries of the totality check — plan7-recursion §2.3 L99-101.

### (j) Budgets and compiled / lowered execution

1. Three quantities, never merged — architecture L19-25.
2. Tariff facts: unit cost for fields with p ≤ 257; integer multiply costs the product of widths (129-bit: 16,641); a call costs one unit — plan7.md L107, L517; plan7-recursion L75.
3. Exact step parity of the VM and of staged host work — architecture2 §2.6, §5.1.
4. "A small program can be expensive to execute, and discovering it can be more expensive still. The structural work tariff is not elapsed time" — architecture L25.
5. Everything in the documents is sized for small budgets: fold budget 64, VM check step limit 64, fiber window 16, default depth 2, predictor ≤ 59 bits (architecture2 L371, L622, L426; plan7.md L620; plan7-recursion L230).
6. `J_procedure` exists as a formula only — plan7.md L117-123.
7. Reporting standard for experiments — plan7.md §5.2 L684-692. Worth adopting as written.
8. Code observation outside my documents: `expression-closure` / `compile-ast-fn` (`vm.lisp:432-444`) lower primitive-only ASTs to host closures; the priority predictor uses it (`synthesize.lisp:~470`). No document in my set discusses lowered execution.

---

## 7. Contradictions

### 7.1 Within and between the documents

1. DAG cache. architecture.md L17: "The kernel has no cross-branch child-problem DAG cache." Same document L189: child scopes are "cached in `synthesis-job-scope-cache`". plan7.md L342 and architecture2 L589 agree with L189.
2. Does the controller use learned/heuristic priorities? plan7.md L447: "The current controller does not consume `heuristic-model` priorities"; L457: "Current node selection is deterministic: root reserve, pending verification priority, then round-robin children." plan7.md L622, L628: actions are ranked by full-path Stage A price, 3 of 4 selections go to the best.
3. `:code-eval`. plan7.md L73 lists it among the primitives; L555 speaks of "a nonexistent `:code-eval` primitive".
4. Callable learned functions. plan7.md L591 ("Learned abstractions are not automatically registered as callable new DSL primitives"), L648 ("no opaque `:f0` registry, callable learned-function installation…"), versus plan7.md L73 and plan7-recursion Phase 2/4 (functions `:fa, :fb…` are defined and registered).
5. Learned clauses. plan7.md L707: "Current conflicts are local checked diagnostics, not learned clauses"; plan7-recursion §5.2: S-expression nogood clauses with UIP generalization.
6. Hard-coded proposal rules. plan7-recursion L192: proposals "are not ranked by hardcoded host rules (such as 'equal lengths ⟹ map')". plan7-m9-policy §2.2 L86 introduces exactly that rule as a fast guard, and architecture2 L704 prunes on it.
7. Expansion of lifted nodes. plan7-recursion L216 (never), plan7-higher-order §4.2 (when a sequence type remains), architecture2 L627 (same), current code (no condition).
8. Fiber sampling. plan7-higher-order §1.3 promises a "locality-biased stratified sample"; its own §4.3 says the implementation "retains the first K distinct fiber inputs"; plan7-m9-policy §1.2 then calls the selection a "current bug".
9. Default of `*max-active-lifted-rows*`: nil (plan7-higher-order L277) versus 16 (architecture2 L426).
10. Status lines. plan7-recursion "audited, and verified" versus its commit message "only lightly tested"; plan7-higher-order "Status: Proposed" with implementation notes.
11. Module counts: nine (architecture, plan7.md §3), sixteen (plan7-m9-policy L11), twenty-four plus five (architecture2). Evolution, but plan7.md and architecture.md were never updated.
12. "R" numbering. R1–R6 are recursion milestones in plan7-recursion; plan7-m9-policy L11, L21 uses R1–R11 and "R8" for refactor/audit items.
13. Priority predictor: "a host function" (architecture L187) versus "VM-executable… AST" (architecture2 L712).
14. Cost of sizing: "not constant-time size APIs" (architecture L48) versus "computed in O(1)" (architecture2 L182).
15. Descriptors: to be *synthesized* from probe frames (plan7.md §4.9), to be *computed and attached* (plan7-library §4 Phase 3.1), then *hand-listed* (plan7-m9-policy §2.2, §3.2).
16. "Strictly VM-Executable Knowledge" and "No new kernel concepts outside the VM" (plan7-library §1 item 2, §6) versus four host-code hooks per kind (§2.3) and host-side structural proofs for descriptors.
17. Test aliases: "m1 through m7… There is no m8 alias" (plan7.md L525, L680) versus "m1–m9 and r1–r6" (architecture L234).
18. Reserve schedule: "not an unrestricted completeness or wall-clock guarantee" (plan7.md L29) versus "preserves 100% search completeness" (plan7-higher-order L146) and "guarantee" language in architecture2 §1.2.
19. Fold-library gain. plan7-recursion App. A.4 itself shows the foldr abstraction gaining 1 bit; architecture2 quotes only the +98-bit map trace (L493-509).

### 7.2 Between the documents and the current code

Collected from §1.3 and §2: primitive count (26 → 27); knowledge kinds (11 → 14); `*descriptor-table*` gone; `bootstrap-inverters.lisp` gone; `filter-map-decompositions`, `function-body-subsequence-filter-p`, `induce-involution-solvers`, `build-functorial-map-inverter`, `evaluate-priority-predictor-expr`, `discover-arithmetic-solvers`, `rewrite-expression`, `solve-learned-equality`, `expand-synthesis-node` absent under those names; coupling penalty 128 → 16; eager-proposal limit 3 → nil; `fold-constants` budget 64 → 10000; `infer-fibers` budget 50000 → 1000000; frame struct gained `metric` and `edges`; M3B/M6/M7/M4 drivers now live only in `milestones/`; referenced files `plan7-recursion2.md`, `audit-review.txt` never existed in the repository; link targets point to another checkout.

One further mismatch of substance: plan7-recursion App. A.3 presents recursion as emerging from standard Stage A/B. The code's own comment (`bootstrap/recursion-schemas.lisp:1-12`) states that beyond the single head/tail split the recursion shapes are "written by hand".

---

## 8. Reading guide for the synthesis

- For what v1 genuinely established, trust plan7.md §1–§2 and architecture.md, then check names in architecture2.
- The mechanisms with the best claim to survive a rewrite, on the evidence here: metered resumable VM with exact step parity; S-expression programs with `:code-*` primitives; pullback with conservative folding; dual-grade solvers certified by two laws; the conserved-quantity → inversion pipeline; congruence closure in lifting; sample-then-ratify with sound refutation; correction-packet pricing with pair/anchor terms; evidence snapshots; reserve scheduling.
- The mechanisms that are host-side special cases of something more general: the inductive lift, lockstep lift, filter rules, filter-map template, descriptor vocabulary, the two built-in decoder shells, DIP's candidate space.
- The ideas stated and never built that match the owner's request most closely: decoder ≡ metric (plan7.md L641); graph distance between entries as locality (plan7-library §2.2.3); names with learned usage statistics (plan7-recursion L65-67); call-path position as a coordinate generating pairs (plan7-recursion L141); group-action laws as free inverters (plan7-higher-order H4.1); evidence-based stopping (plan7.md L642); autonomous decoder-shell enumeration (plan7.md L640).
