# docs-v2b — audit of `plan_v2b.md`, `plan_v2.md`, `plan_v2b_annotated.pdf`

Auditor: `docs-v2b`. Scope: the two superseded plans and the owner's annotated PDF. Repository treated read-only; all re-runs were done in a scratch copy (`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/docs-v2b/kcopy/`).

Tags: **VERIFIED** (I checked it against root `*.lisp` or re-ran it), **WRONG**, **UNCHECKED**, **AS-CLAIMED** (literature; not checked by me). Risk classes: **K** working in this kernel and measured; **S** standard technique with mature implementations elsewhere; **A** academic import with limited evidence at this scale/setting; **X** speculative / novel / unverified.

Housekeeping facts the coordinator should know:

- Root kernel `*.lisp` is byte-for-byte what both plans audited: `git diff --stat df33ed1 HEAD` touches only `Makefile` and the plan documents. So every `file:line` in either plan can be checked against the current root tree.
- A root `library/` directory appeared at 20:10 during my run (untracked; not created by me — presumably another auditor ran `make bootstrap`). It is byte-identical to `v2/library/` and to my scratch regeneration.
- `plan_v2.tex` §Marginalia refers to a `plan_v2_annotated.pdf`. No such file exists in the tree or anywhere in git history (`git log --all --name-only | grep annotated` returns only `plan_v2b_annotated.pdf`, three versions: `53b6c96`, `12b66e0`, `300c6bd`). **WRONG / phantom reference.**

---

## 0. Bottom line for the synthesis

1. **`plan_v2b.md` is the document to mine; `plan_v2.md` is the document to be wary of.** Of about 35 v2b code claims I spot-checked (§3, Appendix C, Appendix D), all held except one miscount (10 fold rules, not 9), one figure I could not reproduce (16,262), and one over-statement (item 4 below). plan_v2.md's *bug list* (§1.4) also held up, but its headline counts are wrong (library size, knowledge kinds, LOC attribution), it carries a phantom identifier, and its design rests on ten speculative mechanisms.
2. **Critical-path risk count.** plan_v2.md: **6 (A) + 10 (X)** on the critical path; only Phase 0 and the listed Phase 1 tasks are free of them, and its headline deliverables depend on all of them. plan_v2b: **0 (A)/(X) in Stage 0**, **1 (A) + 1 (X) in Stage 1**, **3 (A) + 1 (X)** from Stage 2 on. v2b's three self-declared novelties (its §9 risk 7) are *not* on its critical path.
3. **Neither plan closes the geometry question.** plan_v2.md asserts an "ambient-embedded sheaf = VSA" duality with no theorem and no measurement. v2b's bedrock distance (conditional description length) is by its own words "new and unproven", too expensive to use, and replaced in practice by four cheap estimators none of which has been measured for signal. v2b's slogan "compare across spaces only through verified maps" has no mechanism beyond what the kernel already does (recompose to the root) plus three coding rules that are stated but not operationalised. The owner's "how, though?" is unanswered.
4. **One v2b claim is over-stated and I can show it.** "Every trace-derived artifact can be removed with zero change in later work" (§1 item 7, §3.7 item 1) is true for the pair v2b quotes (shift4: 20,076 cold / 16,687 warm, reproduced exactly, unchanged under ablation) but false for the third task of the same test: removing the nogood schema, DIP feature and predictor raises `add-len` warm work from 37,823 back to 40,155 (= cold). That saving is same-task memoisation, not transfer, so the qualitative conclusion survives, but the sentence as written is wrong.
5. **The previous marginalia extraction was incomplete.** The PDF holds 28 annotation objects: 11 typed notes, 14 highlights, 3 ink strokes. `plan_v2.tex` lists 7 notes, with wrong page numbers. It missed 4 typed notes, 10 of the 14 highlights, and an ink bracket (§7 below).

---

## 1. Extraction, plan by plan

### 1A. `plan_v2b.md`

**Diagnosis of the current kernel** (with the evidence it gives, and my tag):

| # | Finding | Evidence cited | Tag |
|:--|:--|:--|:--|
| b1 | The row `(key, known, requirement)` is unary; every inter-row relation was bolted on as a side slot (`pairs`, `anchors`, `metric`, `edges`), a key-naming convention, or host code (§3.1) | `frame.lisp:7-24` | VERIFIED (struct is exactly that) |
| b2 | `lift-frame` builds a fresh frame and drops pairs/anchors/edges/metric (§3.1) | `frame.lisp:1269` | VERIFIED |
| b3 | Hard edges survive only the identity decoder; metric survives via `pulled-back-metric` (§3.1) | `frame.lisp:562`, `468-542` | VERIFIED (edges); metric cases UNCHECKED in detail |
| b4 | `induce-row-order` (only producer of `:persistence`/`:distinct`) is test-only; `:equal` edges are created nowhere (§3.1) | grep | VERIFIED (only caller chain is `with-induced-row-order` ← `tests/topology.lisp`) |
| b5 | Index frames were deferred at plan 3, designed in plan 7, milestone passed on hand-typed rows, never wired (§3.2) | `tests/recursion.lisp:553-560` | VERIFIED (rows are literal `'((0 2 0) (1 2 1) ...)`) |
| b6 | `lift-frame` computes the occurrence index and stores it in the row key, which programs cannot read; DIP repair needs two distinct parent rows (§3.2) | `nogoods.lisp:434-444` | VERIFIED |
| b7 | `library-decompositions` binds a combinator's primary sequence argument only to a frame input variable (§3.2) | `proposals.lisp:195-196` | VERIFIED (`(dolist (p-spec inputs) ...)`) |
| b8 | `(at xs i)` with a variable index is never provably total; `:gather` never total (§3.2) | `ast.lisp:718-735` | VERIFIED by re-run: `(if (< i (length xs)) (if (< i 0) 0 (at xs i)) 0)` and `(if (< 0 (length xs)) (at xs (mod i (length xs))) 0)` both come back not-total; `(gather xs '(0))` not-total |
| b9 | Six index-frame tasks: hand-posed decoder solves at 10–20k work; automatic 8M fails; supplied index column solves at 418,727; lag 1 solves (22,311), lag 2 fails at 1.5M (§3.2 table) | scratch runs | UNCHECKED (scripts not in repo) |
| b10 | Substitution/match are VM primitives; lift is a second symbolic interpreter in `requirements.lisp` with no rule for `:gather`, `:lookup`, `:concat`, `:mod`; no union-find anywhere; only atoms hash-consed (§3.3) | source read | VERIFIED (no occurrence of those four operators in `requirements.lisp`; no union-find in any `*.lisp`). "Nine structural fold rules": I count **10** in `*fold-rules*` (`requirements.lisp:245-250`) — minor miscount |
| b11 | `flatten-lifted-conjuncts` commits to the YES branch of a filter (§3.3) | `frame.lisp:1019-1037` | VERIFIED (docstring says so) |
| b12 | `congruence-close-code-evals` is ground substitution to a fixpoint, not congruence closure (§3.3, App. D) | `frame.lisp:975` | VERIFIED |
| b13 | A pattern with holes is not an object-language value (`:code-kind` has no hole case) (§3.3) | `vm.lisp:174` | VERIFIED (cases `:var :lit :app :op`) |
| b14 | Five non-inter-translatable guard representations; no disjunction or implication test (§3.4) | source read | UNCHECKED |
| b15 | GF(5) guard discovery: 114 expressions → 16 supports; 5 single points carry 2,270 of 2,390 equations; pairwise comparison 454,795 work vs 32,280 for the observations (§3.4) | scratch run | UNCHECKED |
| b16 | Definedness guards learnable from outcome status with a 20-line harness and the existing separator, 4,442–24,077 work; the `(at xs i)` guard is learned but the static analyzer cannot consume it (§3.4) | scratch run | Learning: UNCHECKED. "Analyzer cannot consume it": VERIFIED (b8) |
| b17 | Laws: 12-stage lifecycle, kernel search contributes at 3 stages (§3.5) | reading | UNCHECKED (judgment) |
| b18 | Discovered laws do not rewrite during synthesis: `start-search` has `:laws`, no kernel caller passes it (§3.5 fact 1) | grep | VERIFIED (`synthesize.lisp:629, 876, 1128`; no `:laws` in any kernel file) |
| b19 | `orient-conserved-quantity`, `solve-equality-symbolically`, `conserved-quantity-frame` reachable only from tests (§3.5 fact 2) | grep | VERIFIED (the latter two are called only from inside the first) |
| b20 | Nothing over `:int` is certified but four hand axioms; no entry carries exhaustive/derived evidence (§3.5 fact 3, §3.8) | library | VERIFIED on the regenerated library: 0 `:exhaustive`, 0 `:derived`; `trusted-axiom` present |
| b21 | GF(3)^3 with `+`: 1,779 expressions, 26 classes, 1,753 validated laws, all consequences of two (§3.5 fact 4) | scratch run | UNCHECKED |
| b22 | 12 arrangements of `x0+x1+x2` reach 3 normal forms under validated AC laws (§3.5 fact 5) | scratch run | UNCHECKED |
| b23 | Reuse lost to matching cost: 7,732 saved vs 545,921 spent; 17,763→14,771 child but 19,338→21,514 total (§3.5 fact 6) | "on record" | UNCHECKED (historical record) |
| b24 | One recognizer exists (`:solve-shift-seq-by-correlation`), no trigger, tried on every miss; 3,637 work to reject a non-shift (§3.6) | library + run | Existence VERIFIED (`sequence-shift.sexp` has one `:solver`); costs UNCHECKED. plan_v2.md gives 3,334 for the same event |
| b25 | Trace-derived artifacts do not move later search: cold 20,076 / warm 16,687, unchanged under ablation (§3.7 item 1) | scratch ablation | **PARTLY WRONG** — see §5 |
| b26 | Learned priority predictor degenerate (condenses to `X0` or `X1`); held-out work 7,816 regardless (§3.7 item 2) | scratch run | UNCHECKED |
| b27 | Jobs have 2–6 nodes; ~70% of work precedes any priority (§3.7 item 3) | scratch run | UNCHECKED |
| b28 | Enumerator never prunes by behaviour: 12,139 candidates / 316 behaviours (38:1); 3,489 / 160 (22:1); 13 call sites with private tables (§3.7 item 4) | scratch run | UNCHECKED |
| b29 | Messages expose only scalars: 5 readers over 3 claims; no node reads another's messages (§3.7) | `messages.lisp` | VERIFIED (5 `define-message-reader`, claims `:prepared`, `:stage-a`, `:candidate`; only consumer of the readers is `experiments/yield-gate.lisp`) |
| b30 | Policy is ~90 constants; suite tuned to them (§3.7) | plan 9 audit | UNCHECKED |
| b31 | Library: 92 entries = 31 `:spec` + 61 primary; 32 found by search (2,771 bits, 31%), 12 derived (1,052), 17 hand-built (5,061, 57%) (§3.8) | bootstrap trace | Counts VERIFIED (bootstrap prints 12+8+6+10+8+9+2+6 = 61 entries, 31 specs). Bit split UNCHECKED |
| b32 | In 9 of 11 function specs the operator list is exactly the answer's operators (§3.8) | spec read | UNCHECKED |
| b33 | Without `recursion-schemas.lisp`: 9 of 16 intended; 5 fail at 20M (`positions`, `scan`, `map-adjacent`, `shift-seq`, `best-shift`); 2 pass with the wrong function (§3.8) | scratch run | UNCHECKED. Supporting code fact VERIFIED: the inductive split only self-calls on tails with other arguments unchanged (`decompose.lisp:352-364`) |
| b34 | `law-operator-fact` keeps identity/commutativity/associativity only; distributivity "has no shape there" (§3.8) | `consolidate.lisp:709-735` | VERIFIED |
| b35 | 17,647 lines in 25 modules; growth 12,472 → 17,647 across plans that aimed to shrink (§3.8, §3.10) | wc, git | 17,647 VERIFIED; history UNCHECKED |
| b36 | Geometry is one ambient correction code per type or one metric per frame, always on two target values; the topological half of plans 8/9 is wired, the geometric half is test-only (§3.9) | reading | Consistent with b4, b19; otherwise UNCHECKED |
| b37 | 27 primitives, 14 knowledge kinds (App. D) | source | VERIFIED (27 rows in `+primitives+`; 14 `define-knowledge-kind`) |

**Proposed unifying structure** (§7.2), precisely:

- *Objects (four).* A **base** = a finite set of *sites* with named, possibly partial **structure maps** to another base or itself (rows; positions with `row : P→R` and partial `next : P→P`; call sites; subterm positions; search nodes; library entries; partition labels). A **column** over a base assigns each site a **cell** (a value, a set-as-Boolean-program, nothing yet, or an outcome status). An **expression class**: hash-consed applications; an expression evaluated over a base *is* a column; two expressions share a class *in a context* when their columns agree there. A **context** = sub-base cut by a Boolean column plus assumptions, ordered by implication; a guard is a context.
- *Edges (six kinds).* application; structure map; equality (in a context, with grade and reason); constraint (n-ary Boolean program); derivation (problem + decoder + bindings → child; candidates; conflicts); space (column → type-in-context and code; space → space).
- *Stored vs derived.* Stored: columnar arrays (a column is an array, a structure map is an integer array, a behaviour is an array of values). Derived: "the hypergraph is the *semantics*" (§7.2, line 467). Classes are derived from column agreement; distances are derived (§7.5).
- *Outside the store:* VM, codec, three cost accounts, evidence grades, agenda/budgets/reserve, root verification (§7.9).

**Operations** (§7.3, "six moves"): Apply; Substitute/match; Reindex (lift, incl. *generating* bases); Aggregate (project: all-equal, collect, meet, reduce); Merge/split; Price. A 17-row table maps today's mechanisms onto them (pullback, lift-frame, AU, law proposal, guards, solvers, invariants, fibers, DIP, nogoods, descriptors, messages, caches). Three get a paragraph: AU = recursive constant-column detection; reorientation = one application table read with different key columns; lift by recorded execution with a logging oracle and placeholders.

**Geometry:** §3 below.

**Reflection** (§7.7): derivation edges carry decoder and bindings as code-valued columns; explanations are stored paths; attribution by ablation with a per-edge ledger; scope of a learned message = a context; evidence grade sits on the edge; reflection is "coarse and declarative" (3-Lisp lesson), a designed trace schema, not raw controller state.

**Migration** (§11): Stage 0 in place (E1, E2, E4 + two free measurements); Stage 1 in place (E3, E5, E6, each deleting host code); Stage 2 beside the kernel (E7, E8, then decide); Stage 3 migrate in the order that deletes most. Rule: kernel line count must fall at every step.

**Experiments** (§10): E1 index coordinates as columns (prediction: all tasks within ~500k work); E2 one behaviour table (≥10× fewer candidates at 30 body bits); E3 laws as minimised merges (1,753 → a handful; 3 normal forms → 1); E4 attribution by ablation; E5 one general recursion proposal + ask for a disambiguating row; E6 recognizers with naive-Bayes triggers; E7 small core store; E8 geometry as retrieval. Two "nearly free" measurements: gate the fold rules and descriptor prototypes behind a switch and load the `.sexp` versions instead; delete per-spec operator lists.

### 1B. `plan_v2.md`

**Diagnosis** (evidence and tag):

| # | Finding | Tag |
|:--|:--|:--|
| a1 | "25 pure-kernel modules, 17,818 LOC" (header) | **WRONG**: 17,818 is all 26 root `*.lisp` including `benchmark.lisp`; the 25 `load.lisp` modules are 17,647. Milestones 1,585 and bootstrap 1,304: VERIFIED |
| a2 | `cccc` cognitive 7,376 / cyclomatic 7,021 over 1,638 functions, with a per-file table (§1.2) | UNCHECKED by me (`cccc` not runnable in my sandbox). The 7,376 figure is repeated in `v2/STAGE0_RESULTS.md` |
| a3 | "13 `define-knowledge-kind` silos" (§1.1, §5.1.5) | **WRONG**: 14. The plan's own table lists 14 names |
| a4 | "21 separate proposal generators" (§1.2) | Internally inconsistent: the parenthetical lists 22 names. UNCHECKED against code |
| a5 | Library "83 entries: 52 primary + 31 `:spec`"; provenance tiers 2 / 10 / 21 / 19 = 3.8% / 19.2% / 40.4% / 36.5% (§1.3) | **WRONG** denominator: 61 primary + 31 specs = 92 (bootstrap output; also `v2/STAGE0_RESULTS.md`). Nine primary entries are unaccounted for, so all four percentages are off |
| a6 | `consolidate-knowledge-library` calls `retype-knowledge-laws` without `:samples`; all retyped `:int` laws discarded as `:vacuous` (§1.4.1) | Call shape VERIFIED (`consolidate.lisp:1022-1023`); consequence corroborated by `v2/STAGE0_RESULTS.md`, not re-run by me |
| a7 | `row-satisfaction` tests `typep` of a *string* against a condition type and has no `:unresolved` case (§1.4.2) | VERIFIED (`synthesize.lisp:1102-1116`, `vm.lisp:386-387`) |
| a8 | `open-prepared-node` calls `start-search` without `:laws` (§1.4.3) | VERIFIED (`synthesize.lisp:876`) — same finding as b18 |
| a9 | Incomplete certificates in `arithmetic.sexp` / `constructors.sexp` (§1.4.4) | UNCHECKED |
| a10 | `flatten-lifted-conjuncts` asserts the filter predicate true unconditionally (§1.4.5) | Code shape VERIFIED; "fabricates false constraints" UNCHECKED |
| a11 | `:coupled` key collision between `frame.lisp:1185` and `nogoods.lisp:143` (§1.4.6) | Code shape VERIFIED (keys are `(key :coupled occ-idx)`; the nogood test compares `(second k)`) |
| a12 | Four sandbox holes incl. `finish-accounted-evaluation` `assert` (§1.4.7) | (b) VERIFIED (`laws.lisp:437-441`); others UNCHECKED |
| a13 | Duplicate Stage A at root: 2,120 then 10,000 work (§1.4.8) | UNCHECKED |
| a14 | Zero kernel callers for `orient-conserved-quantity`, `conserved-quantity-frame`, `transition-probes`, `probe-frame-coordinates`, `induce-row-order`, `frame-addressed-entries` (§1.4.9) | VERIFIED for all six. But §1.1's terminology table describes `solve-equality-symbolically` as if live; it is reachable only through the unwired function |
| a15 | `messages.lisp` is write-only (§1.4.10) | VERIFIED for the reader API. Loose: `make-search-trace-frame` (`consolidate.lisp:20`, called at `:1041`) does read raw job messages |
| a16 | `:at` requires a literal index; `:gather` hard-coded non-total (§2.1.B.1-2) | VERIFIED (`ast.lisp:870`, `882`) and by re-run |
| a17 | `:gather` sits at 4-bit opcode #6 (§2.1.A) | VERIFIED (`+opcode-width+ 4` in `codec.lisp:8`; index 6 in `+primitives+`) |
| a18 | Stage A budget multiplier `2·(k−1)²` (§1.2) | VERIFIED (`synthesize.lisp:376-390`) |
| a19 | Default `heuristic-budget` 2,000; `tests/metrics.lisp:209` overrides to 60,000 (§2.2) | VERIFIED both |
| a20 | `metric-delta` costs 3,334 work per candidate-row miss; evaluates `argmax-corr` twice (§2.2) | UNCHECKED |
| a21 | Seven "structural mismatches" of frame + row-requirement (§2.3): three-world schism; N× pullback duplication; `extract-allowed-values → :unknown` cliff; asymmetric orientation; AST vs execution-graph cleavage; de Bruijn rigidity; fiber-blind metric and "split-brain" pricing | Mostly argument. The metric type (target, target) is VERIFIED from the `frame` struct comment. The rest UNCHECKED |
| a22 | "hardcoded `*descriptor-table*`" to be retired (§6.2, §9 Phase 3) | **WRONG**: no such variable exists. The name comes from `architecture2.md`; v2b's Appendix D flags exactly this. plan_v2.md inherited a stale doc name |
| a23 | "7 live bugs" in Phase 0 vs "10 live defects" in §1.4 | Internal inconsistency |

**Proposed unifying structure** (§5.1, §6.1), precisely:

- *Nodes:* `pclass` = slotted e-class with `type`, named `slots` (context/index ports replacing de Bruijn numbering), `enodes`, `parents`, a `cell` (ATMS-labelled domain semilattice: `((assumption-set . dbound) ...)`), a 256-D `sketch`, an optional `stalk-metric`, `min-bits`, `best-enode`.
- *Hyperedges:* `penode` = `(op, args, slot-maps, out-class)`: primitive applications, `tabulate`/`gather`/`partition`/`quotient`, call sites; slot maps do the renaming.
- *Cells:* `dbound` = status ∈ {open, exact, finite-set, interval, container, conflict} with value vectors per example slot, integer interval + modulus/residue, shape bound, per-coordinate bounds, and unreduced relational guards.
- *Rules:* `grule` = one "universal guarded rule" `∀u. G(u) ⇒ R(p1(u)…pm(u))` with directional port propagators, an evidence plist, a sketch, bits and utility-bits; claimed to replace all knowledge kinds.
- *Stored:* everything, including the sketch on every node and rule. *Derived:* e-class membership by union-find congruence; ATMS nogoods when a world hits conflict.

**Operations** (§5.3): four "canonical morphisms" as VM + synthesizer primitives — `project`/`:gather`, `tabulate`/lift (incl. causal self-indexed tabulate for observed scans), `partition` (guard split), `quotient` — plus `(:loop fuel init step)` for hidden-state folds. §5.4: slice experiments for algebra discovery; law saturation before unwinding; AU as sub-hypergraph patterning via babble + Stitch.

**Geometry:** §3 below.

**Reflection** (§5.5.B): search states, evaluations, Stage A histories, ATMS conflicts and ledgers are hyperedges in the same store; duplicate work vanishes "by construction"; decoder chains are reified so laws merge redundant decompositions; a policy regresses realised work per residual bit over VSA sketches, clamped to [−24, +48]. Labelled "Genuine Lisp-3 reflection", but no reflective tower or object-language access is specified.

**Migration** (§9): Phase 0 bug fixes (1–2 days); Phase 1 container index lenses (`:tabulate`, `:loop`, totality for dynamic `:at`/`:gather`), gate = delete `recursion-schemas.lisp`; Phase 2 hyperstore + `dbound` + ATMS + `grule` + babble/Stitch, gate = cold-bootstrap `functors.sexp` with `:work > 0` and retire ~3,000 LOC; Phase 3 VSA sketch + four probes + "sheaf" residual pricing; Phase 4 VSA vocabulary + autonomous wake–sleep curriculum, gate = from 0 entries and ~6,200 LOC discover and certify >60 rules.

**Experiments:** none stated as falsifiable predictions. The phase gates and four "worked traces" (§7) are narrated outcomes of an unbuilt system ("solving … in < 500 work units"). Nothing in §5–§9 was run.

---

## 2. Risk classification

### 2A. `plan_v2.md`

| # | Mechanism | Class | Justification | Plan depends on it for |
|:--|:--|:--|:--|:--|
| 1 | Phase 0 fixes (a6–a12) | K | Bugs are real, several verified | Soundness of any imported component |
| 2 | `:tabulate`, generalised `:gather`/`:at` pullback (index frames) | S | iota/tabulate is standard (APL, Dex, Futhark); `:gather` already in the VM | Phase 1; retiring recursion schemas |
| 3 | Static totality for bounded dynamic index | S | Three small sound facts; the gap is verified | Phase 1 |
| 4 | Causal self-indexed tabulate (observed scan as stencil) | S, unmeasured here | Teacher-forced recurrence fitting is routine; never tried in this kernel | Retiring scan schemas |
| 5 | `(:loop fuel init step)` | S | Bounded iteration primitive | Hidden-state folds |
| 6 | Hankel rank / delay embedding as proxy for hidden state | **A** | System-identification technique; no evidence for integer program synthesis from a handful of rows | Tier-T4 tasks |
| 7 | Synthesised self-call arguments under empirical descent | **X** | Not in the kernel (b33); closest prior art is angelic recursion | Tier-T4 tasks |
| 8 | Four frame-once probes (normalised x-corr, autocorr/Hankel, mixed differences, polynomial degree) | S, with a catch | Textbook signal processing, but "native" probes with real-valued normalisation live in the host, outside the metered integer VM: hand-imported structure | Phase 3 triggers |
| 9 | Per-row fuel and 4-valued outcomes everywhere | K | VM already meters and returns statuses | Empirical partiality |
| 10 | `:totality` as a graded evidence obligation | K/S | Evidence grades exist | Empirical partiality |
| 11 | Guards from crash masks ("bi-abduction + PIE") | K for the simple form, **A** as named | v2b measured a 20-line version with the existing separator. Bi-abduction is a separation-logic technique and is only a label here; PIE is a 2016 research system | Guards, base cases |
| 12 | Wire `orient-conserved-quantity` into synthesis | K | Exists, tested in isolation | Reorientation |
| 13 | Compile library functions through `expression-closure` with amortised tariffs | K | Closures exist | Cost of library use |
| 14 | Union-find congruence closure | S | egg, egglog, SMT solvers; kernel has none | Phase 2 store |
| 15 | Domain-lattice cells (`dbound`) | S | Abstract-interpretation domains, e-class analyses | Replacing the `:unknown` cliff |
| 16 | Slotted e-graph with slot maps | **A** | One PLDI 2025 paper and prototype; no Lisp implementation | The store itself |
| 17 | ATMS worldviews on cells, cross-tree nogoods | **A** | Classical (1986) but known label blow-up; no mature implementation combined with an e-graph | Replacing fallback-frame cloning |
| 18 | Slotted + relational + lattice + ATMS as *one* engine | **X** | No existing system; four research lines integrated from scratch | Everything after Phase 1 |
| 19 | Universal `grule` replacing all knowledge kinds | **X** | Asserted; the 14 kinds have different validators, caches and certificates (b17) | −65% LOC claim |
| 20 | Equality saturation of local e-classes before unwinding | S, known hazard | AC blow-up is acknowledged in the plan's own "blind spot" and not mitigated | Reorientation of multi-occurrence terms |
| 21 | Slice experiments + "tuple-LGG over e-classes extracts *all* non-redundant laws" | **X** | The slice experiments are simple; the completeness claim has no support | Algebra discovery incl. distributivity |
| 22 | babble e-class AU + Stitch bound over the store | **A** | Published Rust systems over lambda-calculus corpora; not over a slotted relational hypergraph | Library extraction |
| 23 | "Relational conjunctive AU (egglog join + babble AU)" discovering functor lifters (Trace 4) | **X** | No such algorithm is described anywhere; Trace 4 is a narrative | Phase 2 gate (`functors.sexp` with `:work > 0`) |
| 24 | 256-D VSA sketch on every node/rule as trigger, ranker and analogy retriever | **X** | VSA/HRR is published (A) but there is no evidence it guides program synthesis; the analogy equation `sketch(:solve-map-0) ≈ …` is conjecture | Phase 3, Phase 4 |
| 25 | "Ambient-embedded cellular sheaf" duality; space creation = binding; collapse = key identification | **X** | Presented as "Mathematics gives a stunning answer"; no theorem is cited that says this; Johnson–Lindenstrauss and HRR do not imply it | The geometry answer |
| 26 | Resonator decoding of "action" tokens | **A** | Frady et al. 2020; known capacity/convergence limits | Language |
| 27 | Base-point pullback metric with `J_scale` and per-root-bit normalisation | **X** | Formula is invented in the plan; `J_scale` is never defined | Residual pricing |
| 28 | Price un-inverted candidates by evaluating forward in the parent's space | S | Plain forward evaluation | Removing Stage A blindness |
| 29 | Policy regression over sketches | K but measured ineffective, + **X** | The predictor exists; v2b measured it degenerate (b26) | Learned heuristics |
| 30 | Reified decoder chains merged by laws ("tabu laws") | **X** | Unbuilt | Search pruning |
| 31 | Compositional VSA vocabulary | **X** | No precedent of a self-bootstrapped VSA vocabulary improving search | Phase 4 |
| 32 | Autonomous wake–sleep curriculum from 0 entries to >60 certified rules | **X** at this setting | DreamCoder used a neural recogniser and large compute; "certified" conflicts with b20 (no proof rule beyond finite exhaustion) | Phase 4 gate |

**Critical path:** Phase 0 (K) → Phase 1 (S for the listed tasks) → Phase 2 needs 16, 17, 18, 19, 22, 23 → Phase 3 needs 24, 25, 27 → Phase 4 needs 26, 31, 32; algebra discovery needs 21. **On the critical path: 6 (A) [6, 11-as-named, 16, 17, 22, 26] and 10 (X) [7, 18, 19, 21, 23, 24, 25, 27, 31, 32].** Rows 29 and 30 are (X) but no gate depends on them. Phase 0 is free of imports. Phase 1's listed tasks (`positions`, `reverse`, `shift-seq`, `map-adjacent`, observed `scan`) are too, but its stated gate — delete `recursion-schemas.lisp` outright — also removes the schemas behind `foldl` and `best-shift`, which need rows 5–7. The Phase 2 gate asks for divisibility guards, which v2b records as not found by exact search in 60M work (§3.4). The headline numbers (17,818 → ~6,200 LOC, cognitive 7,376 → <2,400, 2 → 60+ discovered rules, ~6,500 LOC replaced by ~2,000) have no derivation in the document.

### 2B. `plan_v2b.md`

| # | Mechanism | Class | Justification | Plan depends on it for |
|:--|:--|:--|:--|:--|
| 1 | Requirement as Boolean program; pullback by substitution | K | The load-bearing idea of the frame layer | Kept unchanged |
| 2 | Metered VM, codec, cost accounts, evidence grades, root verification, anytime search | K | Suites pass (222 / 938,737 and 40 / 186,771, reproduced) | Kept unchanged |
| 3 | Bases + structure maps + columns (columnar tables with foreign keys) | S | Relational tables; ACSets in Catlab.jl is the cited mature form (Julia, not Lisp) | The store |
| 4 | Partial-information cells incl. outcome status | K/S | Row requirements already are this; statuses exist | The store; guards from failure |
| 5 | Hash-consed applications | S | Classic; kernel hash-conses atoms only | Canonical identity |
| 6 | Behaviour classes + one shared table that enumeration composes from (E2) | S | Observational-equivalence pruning is standard in bottom-up enumeration; buckets already exist; redundancy measured at 22–38:1 (unchecked) | Stage 0; the case for an equivalence store |
| 7 | Contexts as Boolean masks over a finite base | S | Row masks exist | Guards, scope |
| 8 | Conditional congruence in contexts (coloured-e-graph style); equality constraints between paths | **A** | arXiv 2023 prototype; v2b's own risk 5 calls it "unfinished research" | Stage 2–3 |
| 9 | Reindex/lift incl. generating a positions base (E1) | K/S | Hand-posed index frame decouples at 10–20k work; supplied index column solves at 418,727 (unchecked) | Stage 0 |
| 10 | Totality "by construction" for generated positions | S | Needs the same small analyzer extension as plan_v2.md #3 | Index frames usable where totality is consulted |
| 11 | Lift by recorded execution (logging oracle, placeholders) | **A** | Concolic/angelic execution is known; "covers the decoupled majority" is unmeasured; the VM has half of it | Stage 3; deleting the fold walker |
| 12 | Aggregate (group-by, all-equal, meet) | S | Relational algebra | Quotients, fibers |
| 13 | Price against a correction code | K | Existing | Residuals |
| 14 | AU as recursive constant-column detection | S | Plotkin anti-unification restated; "over classes" is the babble idea (A) | E7 |
| 15 | Reorientation = one table, several key choices | S for finite tables | Functional dependency / inverse index; plan 2 measured all three orientations of `+` from one store (historical) | Laws/solvers as one relation |
| 16 | Recognizers as conservation under a structure map (period, shift, differences, Berlekamp–Massey, ordinal relation) | S | Each is small textbook code; one instance in the kernel | E6 |
| 17 | Naive-Bayes / kNN triggers and policy with log-odds weights | S technique, **A** at this data scale | Proven in theorem-prover premise selection with thousands of proofs; here jobs have 2–6 nodes and the library 61 entries (b27) | E6, Stage 3 policy |
| 18 | Law minimisation by derivability; AC terms as multisets (E3) | S/A | Ruler/QuickSpec approach is published with implementations; needs a congruence engine the kernel lacks | Stage 1; deleting `law-operator-fact` |
| 19 | General recursion proposal: self-call with child-hole arguments (E5) | **X** in this kernel | Nothing proposes it today; five bootstrap functions fail without schemas | Stage 1; "lift with a carry as a primitive" |
| 20 | Ask for a disambiguating row | S, with a gap | Distinguishing-input queries are standard in oracle-guided synthesis; v2b does not say who answers the query | Catching under-determined specs |
| 21 | Attribution by ablation (E4) | K | Done by hand in the audit; I reproduced it | Stage 0; reflection that measures itself |
| 22 | Guards from failure: error → context; region from failure set (`:necessity` precedent); 20-line definedness learner | K | Precedent in kernel; learner measured (unchecked) | Totality learning |
| 23 | Abstract facts on classes; implication order between guards | S (mask subset) / A (Chompy 2026) | Simple version is a subset test on rows | Guard algebra |
| 24 | Second proof rule (structural induction over positions; ICE examples) | **A/X** | Named as a candidate, not designed | Not depended on; fallbacks stay |
| 25 | Space = (type, code) as a shared object | S | A refactor of the metric slot | Geometry cannot be dropped by a transform |
| 26 | Three code-transport rules (bijection; fiber-conditional; bits-back refund) | S as coding theory, **A** as applied | Deciding which case a synthesised decoder is in, and computing the refund, is not specified | Residual pricing in generated spaces |
| 27 | Fisher-volume price of a space | **A** | Defined for parametric statistical families | "Refinement", not required |
| 28 | Column-to-column correction-bit distance | K | Stage A residual is the special case | Geometry estimators |
| 29 | Conditional description length as the defined distance | **X** | v2b: "new and unproven"; uncomputable in general, expensive in practice | Definition only; estimators stand in |
| 30 | Structural hashes (colour refinement, MinHash); graph distances; spectral coordinates | S algorithms, signal unmeasured | Descriptor scoring had zero or negative effect in ablation; nothing shows these do better | E8 |
| 31 | Space collapse by verified inverse maps; anchor-profile pre-test | S (exact part) / A (pre-test) | "Relative representations" is a neural-network result | Collapsing spaces |
| 32 | Search DAG and explanations as store edges; AU of explanations | S/A | Proof-producing congruence closure is published; kernel has UIP-style nogoods | Stage 3 |
| 33 | The integrated store (E7) | **X** as a whole | "No existing system combines them" (§1 item 5) | Migration decision |
| 34 | Description-length induction of an index function from a flat execution graph | **X** | v2b risk 7 | Not depended on: E1 finds index expressions by ordinary enumeration over the ordinal and length columns |
| 35 | Sheaf consistency radius as residual; sheaf obstruction ↔ clause learning | **X** | v2b risk 7; owner asks "what exactly does this mean?" | Nothing in §10–11 |
| 36 | Vocabulary / language (§7.8) | no mechanism | "Nothing in this proposal builds the vocabulary" | Last migration item |

**Critical path:** Stage 0 (E1, E2, E4, two free measurements): all K/S — **0 (A), 0 (X)**. Stage 1 (E3, E5, E6): **1 (A)** [17] **+ 1 (X)** [19]; E3 additionally needs a congruence/derivability engine the kernel does not have (row 18). Stage 2–3 (E7, E8, migration): **3 (A)** [8, 11, 26] **+ 1 (X)** [33, the integration bet]. Rows 24, 27, 29, 34, 35 are (A)/(X) but nothing in the staged path needs them. v2b states its falsifiers up front (§1 "What would change this verdict").

---

## 3. The geometry discussion, reconstructed

### 3A. `plan_v2.md`: "Ambient VSA bus + local sheaf stalks" (Perspective 3; §5.2; §5.5.B.3; §6.2; Phases 3–4)

- **Position.** The owner's dilemma (make/collapse/move spaces over a folded graph, or keep one flat space and change composition by context) is declared dissolved: the two are "dual implementations of one object — an Ambient-Embedded Cellular Sheaf" (§5.2).
- **Argument.** Binding with a unit key is an orthogonal map into a quasi-orthogonal subspace of the same ℝ^D, so "creating a space" = binding with a fresh role key, "collapsing" = identifying two keys or setting a transport matrix to I, "moving" = applying a transport. A cellular sheaf whose stalks are realised as context-bound subspaces is then "isomorphic" to contextual routing in a flat space.
- **Objects and jobs.**
  - *Proposal ranking / triggers:* a D = 256 sketch on every e-class, frame and rule, built bottom-up by bundling and binding and "augmented" by four frame-once probes; thresholds on probe features fire recognizers; cosine/L1 gives "like"; a regression over sketches adjusts priority.
  - *Residual pricing:* an exact, lazily materialised "stalk" metric `(d*g)_x(z1,z2) = g(d(x,z1), d(x,z2))`; a child metric `min(bits_child, J_scale·bits)` normalised per root observation bit; and pricing un-inverted candidates forward in the parent's space.
  - *Language:* "like" = bundling, "analogy" = `B ⊛ A⁻¹`, "action" = role binding, decoded by a resonator pass of depth ≤ 3; a name is a token sequence whose composed vector approximates the entry's input→output change sketch.
- **Evidence.** None from this repo and none measured. Citations only (AS-CLAIMED). The self-stated limit: superposition signal-to-noise ~√(D/K) "past depth 5–7", and sketches cannot prove unsatisfiability.
- **Left open (not acknowledged as open):** how a value column, a frame or an e-class under merges gets a sketch at all; how probe statistics are embedded; who pays for sketch arithmetic (host floats sit outside the tariff); where token vectors come from; what `J_scale` is; whether any of it carries signal.
- **Grounded residue:** two cheap ideas that do not need VSA or sheaves — price un-inverted candidates forward in the parent space, and normalise lifted-child residuals per root observation (the "16-element fiber inflates residual 16×" problem, which v2b also records as "unlike quantities are compared").

### 3B. `plan_v2b.md`

- **§3.9 (state of the kernel).** One ambient correction code per type or one metric per frame, always between two *target values*. No distance between rows, inputs, expressions, frames or entries. Two pieces exist uncomposed: outcome vectors (exact coordinates for expressions) and correction bits (a metric on values); their composition, an expression-to-expression behavioural distance, is never formed, though Stage A's residual is its special case. The geometric half of plans 8/9 is built and test-only.
- **§4.3 (nuggets).** "A metric and a decoder shell are two views of one correction code" (plan 7, one instance); recognizer = solver + decoder pair (plan 8, one instance; owner ink-bracketed the matching paragraph in §3.6); re-indexing creates a space, e.g. `(i mod 2, i div 2)` (plan 1, never built); successor from constant difference (plan 2, half built, unwired); fiber coordinates chosen badly make residuals look random (plan 2); children under different decoders are comparable only by recomposing to the root (plan 7; implemented; the plan 9 audit says it "compares unlike quantities").
- **§6.5 (distance as conditional description length).**
  - *Position:* the bedrock "close" is the bits of the shortest *verified* program found from one thing to another under the current library.
  - *Argument:* it is in the kernel's own currency; composition gives the triangle inequality; every distance has an executable witness, so "close" implies "connected"; distances shrink as the library learns; asymmetry encodes projection vs lift.
  - *Evidence:* Bennett et al. 1998 (AS-CLAIMED); "one targeted search found no prior use of this as the geometry of a growing program library, so it should be treated as new and unproven."
  - *Problems I see:* (i) what is available is an upper bound from a budgeted search; the triangle inequality holds for it only if compositions are actually entered into the table. (ii) "Distances shrink as the library learns" ignores that later library operators cost more bits to reference (4-bit opcode, then a self-delimiting integer for index ≥ 15: `codec.lisp:18-21`, VERIFIED); the measure is non-stationary and not monotone. (iii) It is "too expensive to be a first filter" (§1 item 6), so in practice it is never the thing consulted.
  - *Residual pricing in generated spaces:* three rules — bijection on the data → code length transports exactly, no Jacobian; many-to-one → the residual *is* the fiber coordinate, priced by a conditional code; under-determined latent → refund the arbitrary choice (bits-back), else overcharge up to log |symmetry group|. Two refinements: price a space by the log count of settings the data can tell apart; stop splitting when the residual is incompressible (operationally: synthesis on it finds nothing).
- **§6.6 (flat space and the brain).** Flat vectors are good at content-addressable storage, sparse features in O(log m) dimensions, shallow binding, and adopting the spectral geometry of a context graph (Park et al. 2025). Limits claimed: computing in superposition compresses only quadratically (owner: "what is the evidence for this? Or proof?"); one attention layer cannot compose over large domains; compressed binding accumulates noise and needs clean-up; unions are not embeddable in low dimension. Brain: flat substrate + *structured addressing* (grid modules as a pre-structured index space; Tolman–Eichenbaum factorises where/what; clone-structured graphs split states by EM). Design consequence drawn: since the store holds nesting exactly, the geometric side only has to answer "which entries are near this one" and "how large is this residual", "shallow jobs for which cheap, non-learned vectors suffice." That last step is asserted, not argued: exact nesting in the store says nothing about whether cheap non-learned vectors carry useful signal.
- **§6.7 (language).** Categorical compositional semantics makes the owner's three word classes literal (states, maps on one wire, gates across wires) but is toy-scale: "a vocabulary for the design and not a method". LILO: naming abstractions improves search, with a language model supplying names. Guidance: kNN and naive Bayes do well in data-scarce theorem proving.
- **§7.5 (the design).**
  - *Residual pricing:* a **space** = type + code, a shared object referenced by every column of that type-in-context; decoders create spaces with codes derived by the three rules.
  - *Proposal ranking:* estimators cheapest first — (1) behaviour signatures on shared probe sites; (2) structural hashes (colour refinement, MinHash); (3) exact graph distances in the store (shortest path, hierarchy distance, personalised PageRank); (4) spectral coordinates only if a fixed-length vector is needed. Policy: kNN / naive Bayes over sparse features that include *which decoder* and *which entry*.
  - *Make / collapse / move:* make = a decoder, generated base or new column, triggered by "a residual that stays compressible"; collapse = verified maps both ways composing to identity on the data, with a similarity-profile pre-test on shared anchors; move = apply the map along the edge.
  - *Language:* nothing (§7.8).
  - *Index-set geometry:* a positions base carries shift/reflection/stride actions; lag detection "is reading off a character of that group". This is analogy; the operational content is the recognizer list of §7.4.
- **§9 risks touching geometry.** Risk 7: conditional description length as geometry, index-function induction, and the sheaf–clause-learning link are all new, "new means unproven". Risk 10: the flat alternative may simply win where sample efficiency is not required. Risk 1: each level needs a schema in which small changes are meaningful, "and that design is not done here" (owner highlighted; in the follow-up prompt he calls this "the point of the whole experiment").

**The "how, though?" sentence.** It appears three times: §1 item 6 (line 23, the highlighted and annotated instance), §6.6 final paragraph (line 397), §7.5 "Flat versus nested" (line 563: "The store is nested and exact. Each space is flat and local. Nothing is compared across spaces except through a verified map or through shared anchors."). What backs it:

1. Every space is created by a decoder or structure map, so a map to its parent exists by construction; cross-space comparison is by composing back. That is the status quo (full-path pricing at the root), which v2b itself records as comparing unlike quantities (§4.3, §5).
2. The three code-transport rules. Stated; no procedure for classifying a synthesised decoder as bijective / many-to-one / under-determined on the data, nor for computing the refund.
3. "Shared anchors" (similarity profiles on common sites). This is *not* a verified map, so it contradicts "only through verified maps" in the summary.

There is no mechanism for two sibling spaces under different decoders other than (1). E8 tests only retrieval among library entries within one space. **The margin note is not answered by v2b.**

### 3C. Where the two plans agree, and what remains open

- Both say geometry may rank, trigger and price but never decide truth (plan_v2.md Perspective 3 "blind spot"; v2b §7.1 principle 1). Owner: "yes. obviously."
- Both locate a real defect in residual accounting for lifted children.
- Open in both: what triggers space creation cheaply; how a new space gets a code before anything is synthesised in it; a distance between *problems* or *library entries* with demonstrated signal; any language mechanism. With 61 library entries, retrieval is not a bottleneck a geometry needs to solve today; v2b's own measurements (b26, b27) say priority has little to steer.

---

## 4. `plan_v2b.md` §6: the eight perspectives

| § | Perspective | Summary | Checkable | Rhetoric / leap |
|:--|:--|:--|:--|:--|
| 6.1 | Relational: a frame is a small database | Attributed C-sets give one structure for graphs, hypergraphs and data frames; functorial data migration gives Δ (reindex/gather), Σ (quotient/group), Π (fiberwise meet). An index frame is a frame over a base of positions. Stops in two places: *finding* the map is the search; and requirement pullback along a term is a second fibration not covered. | ACSets and DPO rewriting exist (AS-CLAIMED; Julia). The frame-as-schema-instance claim is testable by construction. "No use in program synthesis was found" is an absence claim. | "Closest existing datastructure to what you describe"; Δ/Σ/Π "read as your vocabulary" |
| 6.2 | Equivalence: laws are merges, guards are contexts | Coloured e-graphs (guards as layers), slotted e-graphs (classes with free variables), lifting e-graphs (weakening as a built-in). Ruler/Enumo keep a *minimal* rule set by derivability; Chompy adds guard implication; babble anti-unifies classes. Limits: no evidence grades, definedness, pricing or row-indexed data; extraction NP-hard and inapproximable; AC blows up. | In-repo: 1,753 laws where two suffice (unchecked), no union-find (VERIFIED). Papers AS-CLAIMED; note the maturity gradient: 2023 preprint, 2025 conference paper, 2026 workshop paper. | "Literal prior art for 'lift has to be a primitive'" rests on the workshop paper, the weakest source carrying the strongest claim |
| 6.3 | Propagator: a requirement is a cell | Requirements are cells in the lattice of allowed sets; `:necessary` is a sound over-approximation; non-unique narrowing is non-monotone, hence the fallback. Sheaf reading: solutions are global sections; the consistency radius defines a residual in any generated space. Slicing gives dependence from one run. | The lattice reading and the non-monotonicity point are logic and can be checked against `laws.lisp`. Radul, Robinson, Perera et al. AS-CLAIMED. | The sheaf link to clause learning: "that link would be ours to make". "Hold all but a few constant from a single execution" overreaches: a slice gives dependence for one run, not interventional dependence across inputs |
| 6.4 | Array: an index frame is a tabulated function | Remora frames/cells, Naperian tabulate/index, Dex, Halide, polyhedral model. Third homomorphism theorem; Farzan–Nicolet lift loops by adding accumulators; Berlekamp–Massey recovers a linear recurrence from 2× its order; Szalinski solves for index functions in an e-graph. | All standard results (AS-CLAIMED); the Berlekamp–Massey statement is correct. "Nobody has published description-length induction of the index function" is an absence claim. | "Settled work"; "the nearest published system to what you want" |
| 6.5 | Information: distance is conditional description length | See §3B. | The three coding rules are standard coding theory. Information distance is uncomputable; the kernel version is an upper bound. | "Three properties then hold by construction" (two of them need qualification, §3B) |
| 6.6 | Flat space and the brain | See §3B. | Each cited limit is a paper claim (AS-CLAIMED); the owner asked for the evidence on the superposition bound. | "The limits are exactly the things a nested store is for"; "which is your pillar 5 implemented"; "cheap, non-learned vectors suffice" |
| 6.7 | Language | See §3B. | LILO used a language model for names — stated honestly. kNN/naive-Bayes results come from corpora of thousands of proofs. | "Log-odds are bits, so they sit natively in a description-length ledger" |
| 6.8 | Sceptic | Six arguments against one hypergraph (below). Net reading: one schema language, one store, a handful of edge kinds, primitives for lift/substitute/guard, scheduling outside, "no expectation that learning follows from unification itself". | The in-project matching-cost record (b23). | "The successful engines unify monotone systems" names no engine (owner: "Which successful engines?") |

**The sceptic's historical examples (§6.8), as listed:**

1. **AM and EURISKO** — Lenat & Brown 1984: AM worked because small mutations of short Lisp forms were often meaningful in its domain; not true of heuristics. "A uniform substrate is not uniformly learnable."
2. **OpenCog (Hyperon)** — programs, data and rules in one reflective metagraph for over a decade "without a published demonstration of compounding discovery".
3. **Unnamed "successful engines"** that unify monotone systems; budgets, reserve schedules, tentative narrowing and deletion are kept outside. (Context implies Datalog/egglog, e-graphs, propagator networks, LVars.)
4. **Stitch vs e-graph library learning** — orders of magnitude faster when no theory is needed; matching cost grows with pattern width; general hypergraphs have no cheap canonical form.
5. **This project itself** — reuse lost to matching cost in every small measured case.
6. **Graph-plus-vector retrieval** often losing to plain vector retrieval on simple queries; **learned sheaf maps** showing no reliable benefit over identity maps.
7. **AlphaGeometry, DreamCoder, BUSTLE, theorem-prover learners** — the successes; all keep truth in an exact engine and let geometry rank or propose.
8. **CompressARC (2025)** — a fifth of ARC-AGI-1 with description length as the only objective and gradient descent as the only search.

Elsewhere in the two plans: **3-Lisp** (v2b §7.7: fine-grained procedural access to interpreter state was hard to use; owner highlighted); **Minton's utility problem** (plan_v2.md Perspective 1; v2b §4.4 with a measured instance: stored templates raised warm work on `inc-list` from 19,147 to 48,573); plan 1's own three triggers for adopting an e-graph, none measured until v2b.

---

## 5. Measurements and discrepancies

### 5A. v2b Appendix C (16 rows)

| Measurement | Reported | Tag |
|:--|:--|:--|
| Kernel and milestone suites | 222 and 40 tests, all pass | VERIFIED by re-run: 222 tests / 938,737 checks; 40 tests / 186,771 checks |
| Plan 8 probes | 71,782 / 212,096 / 34,067 | UNCHECKED by me; same figures in `v2/STAGE0_RESULTS.md` |
| Ledger fingerprint | 236 tests, 419,655,232 work; +0.46% | UNCHECKED |
| Bootstrap regeneration | byte-identical, 0.33 s, ~2.5M work | VERIFIED byte-identical (my regeneration = root `library/` = `v2/library/`); 0.46 s here |
| Eight index-frame tasks | table §3.2 (six rows shown) | UNCHECKED |
| Totality of variable-index access | never provable under any guard tried | VERIFIED by re-run |
| Law discovery on five grids | 47–3,623 validated laws; validation ≈1.5× observation, refutes nothing on a complete grid | UNCHECKED |
| Normal forms under AC | 12 arrangements → 3 | UNCHECKED |
| Guard discovery on GF(5) | 16 supports; 5 points carry 2,270 of 2,390 | UNCHECKED |
| Correlation solver | 19 bits vs 26–52; 6,581–18,804 work; 3,637 to reject | UNCHECKED (plan_v2.md says 3,334) |
| Warm-library ablation | warm unchanged at 16,687 without any trace-derived entry | **PARTLY WRONG** — below |
| Priority predictor | one raw feature; no effect on held-out work | UNCHECKED |
| Enumeration vs behaviour | 12,139 / 316; 3,489 / 160 | UNCHECKED |
| Bootstrap without schemas | 9 of 16; 5 fail at 20M; 2 wrong | UNCHECKED |
| Operator lists in specs | exactly the answer's vocabulary in 9 of 11 | UNCHECKED |
| Definedness guards from outcomes | five guards, 4,442–24,077 work | UNCHECKED |

**Warm-library ablation, re-run.** I instrumented a scratch copy of `tests/library.lisp` (`library-l4-continual-learning-curriculum-amortization`), which has three cold/warm pairs, and removed entries from the deserialised warm library before the warm runs:

| Warm library | inc (cold 18,090) | shift4 (cold 20,076) | add-len (cold 40,155) |
|:--|--:|--:|--:|
| intact | 15,948 | 16,687 | 37,823 |
| minus predictor, nogood schema, DIP feature | 15,882 | 16,687 | **40,155** |
| minus the four descriptors | 15,489 | 16,687 | 37,823 |
| minus both sets | 15,456 | 16,687 | 40,155 |
| minus the four `:function` entries | 18,090 | (test stops) | — |

- v2b's quoted pair (20,076 / 16,687) and its invariance are reproduced exactly.
- Removing descriptors makes `inc` cheaper, as v2b says in direction; its figure 16,262 is not one I can reproduce (shift4 stays at 16,687).
- The `add-len` saving of 2,332 (5.8%) disappears when the nogood schema / DIP feature / predictor are removed. So one trace-derived artifact does move work — on a re-run of the very task it was learned from. The claim should read: no trace-derived artifact *transfers*; the nogood schema memoises its own task.
- Removing function entries returns `inc` to cold: the transferable gain is the abstracted functions, as v2b says.

### 5B. v2b Appendix D (11 items)

| Discrepancy | Tag |
|:--|:--|
| `architecture2.md` lists 24 modules incl. `bootstrap-inverters.lisp`, not in `load.lisp`; there are 25 | VERIFIED |
| `architecture2.md` says 26 primitives (27) and 11 kinds (14); `tests/library.lisp:56` says 9 | VERIFIED (27; 14; comment says 9) |
| `architecture2.md` §3.2: built-in `:at` inversion, head-fiber reserve, different fiber-cap formula, coupled penalty 128 vs 16 in code | Penalty 16 VERIFIED (`synthesize.lisp:456, 500`); cap formula exists at `frame.lisp:1211-1213`; the rest UNCHECKED |
| `architecture2.md` names `filter-map-decompositions` and `*descriptor-table*` | VERIFIED (code has `multi-hole-decoder-decompositions`; no `*descriptor-table*`) |
| Plan 7 headers say "Complete" for an unwired Path A, etc. | Unwired VERIFIED (b5, b19); header text UNCHECKED |
| `plan6.md` vs `results.md` on the source of the AU compression gain | UNCHECKED |
| `batteries-and-reflection.md` §2.2: bootstrap never calls `lift-field-solvers`; spec replay skipped for retyped loads | VERIFIED (no call in `bootstrap/`; `consolidate.lisp:1884` guards on `(null slugs)`) |
| `synthesis-message` docstring says parents may consume messages | VERIFIED (`synthesize.lisp:114-117`) |
| `congruence-close-code-evals` is not congruence closure | VERIFIED |
| Fingerprint script module list predates `closures`, `batteries`, `messages`, `totality` | VERIFIED (`experiments/ledger-fingerprint.lisp:52-54`) |
| `library/` untracked and not ignored; tests depend on it | VERIFIED (`.gitignore` holds only `/intermediate_results/`) |

### 5C. plan_v2.md measurements

Listed with tags in table 1B (a1–a23). Summary: its *code-level defect reports* are reliable (a6–a8, a10–a12, a14, a16–a19 verified); its *aggregate counts* are not (a1, a3, a4, a5, a23), and a22 is a phantom identifier. Unverifiable numbers: all `cccc` figures (a2), 3,334 per `metric-delta` (a20), 2,120 / 10,000 duplicate Stage A (a13), "100× self-interpretation penalty" (no source given), and every projected figure in §6.2 and §9.

### 5D. Where the two plans disagree on facts

| Fact | plan_v2.md | plan_v2b.md | Correct |
|:--|:--|:--|:--|
| Knowledge kinds | 13 | 14 | 14 |
| Library | 52 primary + 31 specs = 83 | 61 + 31 = 92 | 92 |
| Kernel LOC | 17,818 "in 25 modules" | 17,647 in 25 modules | 17,647 |
| Kernel-discovered share | 2 entries (3.8%) "genuine", 10 more under curated grammars | 32 entries, 2,771 bits (31%), inside answer-shaped grammars | Different definitions; both say bootstrapping is weak. v2b's is the reproducible accounting |
| Non-shift rejection cost | 3,334 | 3,637 | Unresolved |
| Policy constants | "over 30" | "about ninety" | Unresolved |

---

## 6. What survives

### 6A. Cheap, grounded in this repo, and responsive to the owner's lens

1. **Coordinates as readable columns / a generated positions base** (v2b E1; plan_v2.md Phase 1). Grounded: the index is computed and withheld (b6); a hand-posed index frame decouples at 10–20k work. Responds to "lift has to be a synthesizer primitive" and to tuple slicing. Needs the small totality extension, whose absence I verified.
2. **One behaviour table that enumeration composes from** (E2). Grounded: buckets exist and are not fed back; 22–38:1 redundancy reported. This is the lever that makes hours-long budgets pay, since it cuts the effective branching factor. Caveat (v2b risk 4): the claim becomes "exhaustive modulo behaviour on these rows", and erroring/unresolved rows need a defined treatment.
3. **Attribution by ablation as a kernel operation** (E4). Grounded: I reproduced it in minutes. Responds to reflection and to "the kernel, not the agents". Owner (follow-up prompt, Q15): "I really like this!" — with the open question of whether it is integrated into the homoiconic kernel.
4. **Guards and totality learned from outcome status** (v2b §3.4, §7.6; plan_v2.md §5.5.A minus the bi-abduction label). Grounded: `:necessity` precedent; the 20-line learner. Responds to "tolerating crashing or non-terminating behavior, and assembling guards". Known limit found by v2b: the separator admits only atoms defined on every row, so guards must be staged.
5. **Wire or delete what is built and unwired**: `:laws` into `start-search`, `orient-conserved-quantity`, `induce-row-order` (all verified unwired). Responds to reorientation. Caution: b23 says rule use has cost more than it saved; wiring without an index repeats that.
6. **Minimise laws by derivability and drop the three-shape whitelist** (E3). Grounded: `law-operator-fact` verified; distributivity structurally excluded (owner highlighted). Responds to "underwhelmed with the quantity of information".
7. **One relation, several readings** (v2b §7.3 reorientation). Grounded historically (plan 2 found all three orientations of `+` from one store); today each orientation is a separately searched and certified entry.
8. **Anti-unification as recursive constant-column detection** (v2b §7.3). A restatement that makes AU an operation of the store and matches the owner's "quotienting and trivial lifting under substitution". Cheap to try in isolation.
9. **Keep list** (v2b §8): metered VM as truth, requirement-as-predicate with pullback by substitution, root verification, three cost accounts, evidence grades with "sampled can propose and never eliminates", anytime resumability, heuristics never starving sound search.
10. **Drop list** (v2b §8): unit-exact ledger parity (owner highlighted "work drift is tolerable" and wrote "yes"), "never mutate frames or the library during search", whole-frame cloning for soundness, the kernel/`milestones` wall.
11. **Persistence across branches and jobs** (v2b §5; owner: "yeah that's a big problem").
12. **Recognizer = solver + decoder pair**, with the shift battery as the template (owner ink-bracketed). One working instance; missing piece is the trigger.
13. **Two residual fixes that need no new theory** (plan_v2.md §5.2.3): forward pricing of un-inverted candidates in the parent space; normalising lifted-child residuals per root observation.
14. **plan_v2.md Phase 0 defect list** (a6–a12). Relevant to any rewrite "importing working components": several components are not sound as they stand.
15. **Honest bootstrap benchmarks**: schema-free bootstrap (9 of 16; five failures are exactly the index/scan class), spec operator lists stripped, under budgets three to four orders of magnitude above the 0.33–0.46 s bootstrap. This is the natural test of the owner's "hours of search" point, and neither plan ran it.
16. **plan_v2.md's T0–T4 tier table** (§2.1.C): which sequence functions reduce to index maps, stencils, selective subsequences, associative scans, or irreducibly hidden state. Standard mathematics, useful as a task taxonomy.

### 6B. Attractive but resting on (A)/(X)

- **VSA sketches, the "ambient sheaf" duality, resonator decoding, VSA vocabulary** (plan_v2.md) — X. No measurement anywhere.
- **Slotted relational e-graph + ATMS + universal `grule` as the one store** (plan_v2.md) — A × A × X.
- **Functor discovery by "relational conjunctive AU"** (plan_v2.md Trace 4) — X; the algorithm is not described.
- **All plan_v2.md projections** (−65% LOC, 60+ rules, < 500 work) — unsupported.
- **Conditional description length as *the* metric** (v2b) — X by its own account, and never consulted in practice.
- **Sheaf consistency radius; sheaf obstruction ↔ clause learning** (v2b) — X.
- **Coloured / slotted / lifting e-graphs as store primitives** (v2b §6.2) — A, at decreasing maturity.
- **Lift by recorded execution** (v2b) — A; plausible and would delete the second interpreter, but "covers the decoupled majority" is unmeasured.
- **Bits-back refunds and Fisher-volume pricing** (v2b) — A as applied.
- **Naive-Bayes / kNN policy, spectral or PageRank retrieval** (v2b) — standard algorithms with no evidence of signal here; the kernel's own measurements say there is little for a policy to steer at present job sizes.
- **Third-homomorphism / accumulator-lifting route from folds to index form** (v2b §6.4, §7.4) — A.
- **Brain analogies** (Tolman–Eichenbaum, clone-structured graphs, grid codes) — no mechanism is imported; the owner suspected hype.
- **A second proof rule by structural induction + ICE** (v2b §7.6) — A/X; named, not designed.

### 6C. Gaps in both plans relative to the current prompt

- Neither analyses **hours-long budgets** or asymptotic cost. plan_v2.md optimises for the 2,000-unit Stage A default. v2b notes the headroom but its failed runs stop at 8M–60M work.
- Neither makes **lift of a requirement** (today's `lift-frame`) an object-language operation. plan_v2.md adds data primitives (`:tabulate`, `:loop`); v2b's six moves are store operations whose exposure to the synthesizer is unspecified (owner Q12: "The hypergraph is the semantics (?!?)"; Q15).
- Neither has the **kernel choosing its experiments** beyond a line item (v2b risk 9, E5's disambiguating row; owner highlighted "chooses experiments" and wrote "Yes!").
- Owner Q9/Q9a on v2b: too much focus on indexing versus general fiber/cover computation, and "not enough consideration of residuals".

---

## 7. The owner's annotations

Extracted with PyMuPDF from `/home/tlh24/lisploop/plan_v2b_annotated.pdf` (36 pages; Okular; author `tlh24`); placements confirmed by rendering pages 9, 18, 27, 28. **28 annotation objects: 14 highlights, 11 typed notes, 3 ink strokes.** No annotation was deleted between the three committed versions (17 → 21 → 28).

| # | Page | v2b § | Type | Attached text | Note (verbatim) |
|:--|:--|:--|:--|:--|:--|
| 1 | 2 | §1 item 5 | highlight | "(attributed C-sets)" | — |
| 2–3 | 2 | §1 item 6 | highlight + note | "versus nested: keep the topology nested and exact, keep the geometry flat and local to each space, and compare across spaces only through verified maps" | **"how, though?"** |
| 4 | 8 | §3.5 fact 6 | highlight | "Reuse has lost to matching cost in every small measured case on record:" | — |
| 5–6 | 9 | §3.6 last paragraph | ink bracket in left margin (drawn twice) | "The entry is nonetheless a good template for how such things should enter: a solver whose witness is an algorithm, paired with a decoder, so that the pair gives both a metric and a pullback (plan 8, section 3.1). What is missing is exactly what you named: something that decides when." | — |
| 7 | 10 | §3.8 | highlight | "Distributivity has no shape there and cannot enter." | — |
| 8–9 | 15 | §5 "Sharing is by exact equality only" | highlight + note | "Nothing persists across branches or jobs." | **"yeah that's a big problem."** |
| 10 | 17 | §6.2 | highlight (21 Nov) | "Lifting e-graphs" | — |
| 11–13 | 18 | §6.6 | highlight + note + ink arrow joining them | "[Computing] in superposition compresses only quadratically where storage compresses exponentially." | **"what is the evidence for this?  Or proof?"** |
| 14–15 | 19 | §6.8 Monotone stores | highlight + note | "The successful engines unify monotone systems." | **"what does this mean?  Which successful engines?"** |
| 16 | 20 | §6.8 Hybrids fail… | note | "…keeps truth in an exact engine and lets geometry only rank or propose." | **"yes.  obviously."** |
| 17 | 20 | §6.8 | highlight | "[The flat alternative is] live. CompressARC" | — |
| 18 | 26 | §7.7 | highlight (21 Nov) | "fine-grained procedural access to interpreter state was hard to use;" | — |
| 19 | 27 | §8 Dropped, first bullet | highlight (21 Nov) | "work drift is tolerable;" | — |
| 20 | 27 | bottom-left margin, below the §8 "Dropped" bullets | note (21 Nov 16:22, the last annotation made) | nearest text: the unit-exact-ledger-parity bullet and its highlight | **"yes.  and new (local) metrics may be admissible, even if they are not desireable."** |
| 21 | 28 | §9 risk 1 | highlight | "Each level needs a schema designed so that small changes are likely to be meaningful, and that design is not done here." | — |
| 22 | 28 | §9 risk 3 (extraction NP-hard; anytime search remains necessary) | note | "…the store does not replace it." | **"Yes, I know."** |
| 26–27 | 28 | §9 risk 7 | highlight + note | "any link between sheaf-style obstruction and clause learning." | **"what exactly does this mean?"** |
| 23 | 28 | §9 risk 8 | note | "…and a line count that must fall at every migration step." | **"complexity score(s) are better than line counts - less gameable"** |
| 28, 24 | 28 | §9 risk 9 | highlight + note | "chooses experiments"; note sits at the end of "…the store only makes them expressible." | **"Yes!"** |
| 25 | 28 | §9 risk 10 | note | "The flat alternative may simply win where sample efficiency is not required. This project's bet is that it is required." | **"Yes, also - brute-force search works whenever the size of the search space is small enough and the speed of each evaluation is short enough. \nThis is how recent work in energy-based omdels were able to solve hard combinatorial problems. See, for example, https://arxiv.org/abs/2611.17309v1\nA good reason for the homiconic, scheduled lowering / compiling formulation."** |

**Against `plan_v2.tex` §Marginalia (M1–M7):**

- M1–M7 correspond to rows 2–3, 8–9, 11–13, 14–15, 16, 23, 25. Wording is right.
- **Page numbers are wrong** in all seven (tex says p. 1, 5, 6, 7, 8, 9, 9; actual 2, 15, 18, 19, 20, 28, 28).
- **Missed typed notes (4):** "Yes, I know." (risk 3); "what exactly does this mean?" (risk 7, sheaf ↔ clause learning); "Yes!" (risk 9, chooses experiments); "yes. and new (local) metrics may be admissible, even if they are not desireable." (p. 27).
- **Missed highlights (10 of 14; eight carry no note, the last two belong to missed notes):** attributed C-sets; reuse lost to matching cost; distributivity cannot enter; Lifting e-graphs; CompressARC; fine-grained procedural access was hard to use; work drift is tolerable; each level needs a schema…; sheaf obstruction and clause learning; chooses experiments. Plus the ink bracket on the recognizer paragraph.

**Reading of the p. 27 note.** Its placement is ambiguous. Two readings, both consistent with the current prompt: (a) agreement that ledger/tariff parity can go, and that new *local* accounting measures are acceptable ("not at all strict about e.g. keeping the tariffs similar"); (b) new local *geometric* metrics on generated spaces are admissible even if ambient pricing is preferred ("I'm not sure if there are better options … other than pricing in the original or ambient spaces"). Either way he is not insisting on one ambient metric.

**The owner's typed follow-up on v2b** (quoted verbatim in `plan_v2.tex` lines 153–208; outside my documents but it is his reaction to them) adds: v2b is "a bit more conservative"; it "sees the hypergraph as emergent through semantics, and thus does not quite as cleanly and elegantly embrace the underlying mathematics"; "The geometry part of that plan 'smells' flimsy, but yet it seems more substantiative than using a VSA"; Q1b asks whether "reuse has lost to matching cost" is "a matter of scale or implementation"; Q2 asks about "a small local-context BERT style transformer" instead of VSA; Tolman–Eichenbaum "could be hype-y"; Q8 agrees with all six moves but sees apply/substitute/match/project as "flavors of the same, as are lift and split"; Q9 worries about "focusing too much on the indexing … and not fiber (or sheaf, cover, chart..) computation, which is more general", and Q9a "Not enough consideration of residuals"; Q13 on the density risk: "this is the point of the whole experiment! Small changes meaningful ≃ information geometry of the library or language"; Q14 "what would a second proof rule be, then? Obviously we do have algebra!"; Q15 on E4: "I really like this! … Yet is it properly integrated into the homoiconic kernel?"

**What the annotations reveal.**

- *Priorities:* persistence across branches and jobs; the kernel choosing experiments; attribution; algebra beyond three hard-coded shapes; recognizers entering as solver + decoder pairs; relaxing ledger parity; complexity scores over line counts; raw evaluation speed and the homoiconic "scheduled lowering" design as the thing that makes brute-force search viable.
- *Doubts:* every doubt is a request for mechanism or evidence at a point where v2b leans on literature — "how, though?", "what is the evidence … Or proof?", "Which successful engines?", "what exactly does this mean?". He accepts v2b's sober claims without discussion ("yes. obviously.", "Yes, I know.").
- *Not persuaded that anything is settled on geometry:* the only geometry sentence he annotated is the one he questioned; he highlighted CompressARC and wrote a paragraph agreeing that the flat/brute-force alternative is live.
- *Interest without endorsement:* attributed C-sets and lifting e-graphs are highlighted with no note; the follow-up prompt asks whether C-sets are "a better or correct datastructure".
- He treats the density risk ("each level needs a schema in which small changes are meaningful, and that design is not done here") as the research question itself, not as a caveat.
