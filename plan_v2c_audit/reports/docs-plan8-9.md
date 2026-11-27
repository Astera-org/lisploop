# Audit report `docs-plan8-9`: plan8.md, plan9.md, plan9-audit.md, plan-exec.md, batteries-and-reflection.md

Auditor scope: the five documents above, read in full, checked against the root kernel on branch `reflective` (HEAD `15e64c6`, 24 Nov 2026). The repository was not modified and no test or bootstrap script was run; every code tag below comes from `grep`/reading, not from execution.

Tags used: **STILL-IN-CODE** (file:line in the root kernel), **GONE** (was built, no longer in the root kernel), **NEVER-BUILT** (zero grep hits in `*.lisp`, `tests/`, `milestones/`, `bootstrap/`, `experiments/`), **TEST-ONLY** (defined in the kernel, but the only callers are tests or experiment scripts).

Quotation convention: the owner's own words are marked **OWNER** and quoted verbatim. Everything else quoted is agent prose.

---

## Headline findings

1. **The existing geometry is one host function plus one library hook.** Residuals are priced in bits by `correction` (`frame.lisp:1533`), a fixed rule per value type. Plan 8 added a frame metric and "metric decoders" (a decoder paired with a solver for its delta), which serve as both a distance and a change of target space. It works, but each evaluation runs in the VM on Stage A's own budget (3,334 work on the one fixture, against a default budget of 2,000), and "A metric decoder taxes every search of its type". Programs are priced at the root and residuals in the child's own space, so the node score already mixes ambient and induced pricing.
2. **The topology Plan 8 built is almost all unwired.** Row edges are checked by exact search, but nothing in the kernel produces one. Row-order induction, locality keys and symbolic solving of a conserved quantity for the target are in the kernel and are called only by tests. Invariant discovery (`enumerate.lisp:728`) and reorientation (`laws.lisp:931`) both exist and no kernel path joins them. The stated reason is that wiring them would reorder rows or mutate the library mid-search.
3. **The "calculus" in Plan 9 is a naming of four host functions**, not a mechanism: projection, pullback and lift, fibre narrowing, fibre separation, over an "input-requirement bundle". None became a VM primitive. The parts that were later built are the solver obligations `:witness`, `:uniqueness`, `:necessity`, and solver induction from laws and from specs.
4. **The audit is the most reliable document in the set.** It ran experiments. Its hardest numbers: a 57-bit guard is not found by exact search in 60,000,000 work; a plausible budget gate stops the winning node five quanta early; changing one constant from 2 to 1, 3, 4 or 7 each breaks a test.
5. **Batteries did not make the kernel bootstrap.** Host builders were deleted on 18 Nov, but nine of ten functor transformers and the filter-map template are hand-built entries in `bootstrap/build-batteries.lisp`, and synthesized functions get a hand-picked grammar and curriculum. The generated `.sexp` files are not in the root tree.
6. **Reflection exists as a 128-line reader** (`messages.lisp`) that turns a job's messages into an ordinary frame, used once, offline, by `experiments/yield-gate.lisp`. Nothing flows back into a running search.
7. **Every budget in these documents is on the order of a second of evaluation or less** at the rate plan-exec measured (about 65 million work units per second for one benchmark; my arithmetic). More budget is not monotonically better: one probe solves at the default and fails at a larger Stage A budget.
8. **The kernel grew from 12,472 to 17,647 lines** across three plans that each promised to shrink it.

---

## 0. Provenance and how to read these documents

| Document | Dates (git) | What it is | Branch/commit it describes |
| :-- | :-- | :-- | :-- |
| `plan8.md` | created 13 Nov (`2b8a912`), cut down the same day (`484d0d7`, "simplified plan8; removed HMM part for later"), revised 13 Nov (`0949446`), implementation record added 16 Nov (`fb9d970`), appendices B and C pulled from `main` (`0f9a470`), §6.7 added 16–17 Nov (`1bfb69d`, `f08298a`) | Plan, then implementation record, then record of a merge and audit | Plan text: `54acfa3`. §6: branch `charlie`. |
| `plan9.md` | 16 Nov (`0d487a9`, "added plan for finishing heuristic induction"), redone 17 Nov after the audit (`019736f`, `f08298a`, `6436d68`) | v2.0 plan; **no implementation record in the working tree** | `charlie` at `019736f` |
| `plan9-audit.md` | 17 Nov (`f08298a`, `6436d68`) | Audit of plan9 v1.0, plus §11, a review of v2.0 | §1–§10 at `019736f`; §11 at `fafffd9` |
| `plan-exec.md` | 17 Nov (`a822990`) | Record of a finished change (closures) | branch `metered-closures` from `019736f` |
| `batteries-and-reflection.md` | 18 Nov (`ed4d059`, `4db20bc`, `6462cb4`) | The owner's prompt plus an agent's proposal | `reflective` at `7a0d6bf` |

Things the coordinating agent should know before trusting any of them:

1. **Two documents that plan8.md and plan-exec.md lean on were never in the repository.** `plan8-2.md` (the source of plan8 §1.1, "Where `plan8-2.md`'s Restrictive Calibration Holds") is absent from every branch; plan8 §6.1 (L188) says so itself. `plan-let.md` (plan-exec L4, L24) is likewise absent from every branch.
2. **Plan 8 was implemented twice by different agents.** Branch `main` holds an independent implementation (`67c015c`, owner's commit message: "plan8 1-4 as implemented by hydrogen. Reduction in code base, not audited; verified only by the supplied tests.") at 11,906 kernel lines. Branch `charlie` holds the one that plan8 §6 records, at 13,771 and then 15,154 lines. The working tree descends from `charlie`. Plan8 §6.7 is a hand-port of some of `main`'s behaviour into `charlie`'s code.
3. **The working-tree `plan9.md` stops at §7.** The `charlie` branch tip (`15514a4`) has a later version with a §8 "Implementation Record and Restated Gates" that the `reflective` branch never received. I read it with `git show charlie:plan9.md` and report it in §2.5 because it holds the only measurements of what Plan 9 actually built.
4. **The plan8 header is stale.** It says "v3.1 … 13 November" and "`12,481` LOC" (L3–L4); §6.1 corrects the count to 12,472 and §6.7 is dated 16–17 November.
5. **The acronym "SMOCE" is never expanded.** In every version back to the first (`2b8a912`, heading "Cover–Correspond–Orient–Conserve–Extract (SMOCE)") the five stage names are Cover, Correspond, Orient, Conserve, Extract, whose initials are C-C-O-C-E. No identifier containing "smoce" exists in any `.lisp` file.
6. **Current size.** The 25 modules of `load.lisp` are 17,647 lines today, against 12,472 at `54acfa3` (start of Plan 8), 15,154 at the end of the Plan 8 audit and 15,257 after the closures commit. Plan 8, Plan 9 and the batteries proposal each carried a goal of making the kernel smaller.

Owner's own status notes, from commit messages (every commit in the repository is authored by the owner, so I treat these as the owner's words, not the agents'):

- **OWNER** `7a0d6bf` (17 Nov): "partially through plan9; refactoring into the library not done - we shall bootstrap it."
- **OWNER** `15514a4` (17 Nov, `charlie`): "need to revise the batteries implementation; otherwise, plan 9 is sufficiently complete for it."
- **OWNER** `849013a` (18 Nov): "alright, we'll add the library - though the files within should be auto-generated.."
- **OWNER** `b3af2e6` (18 Nov): "step 2 of batteries +reflectivity done"
- **OWNER** `df33ed1` (19 Nov): "working through lifted index frames - which surprisingly were absent from the kernel!  Might need to re-examine it."
- **OWNER** `53b6c96` (20 Nov): "working on v2 / better foundational datastructure."

---

## 1. Plan 8

Title (L1): "Plan 8: Geometric & Topological Unification (SMOCE), Product & Sharing Completeness, and Kernel Simplification". Owner's commit message for it (`2b8a912`): "new plan8 for better unification of synthesis and anti-unification!".

### 1.0 The framing claims (plan8 §1.1, §2.1)

These are the conceptual content of the plan. They are assertions by the agent, taken from `plan8-2.md`, which cannot be inspected.

- **Unify the data model and the agenda, keep the engines apart** (L19). Anti-unification is linear and deterministic "because free-algebra constructors (`:cons`, `:tuple`, AST application nodes) are **injective**; all search on the AU side lives in **correspondence**". Synthesis works over many-to-one primitives, "where row alignment is fixed upfront and search lives in **conserved computation**". The two "meet as **complementary operators emitting `decomposition`s and `frame`s onto one full-path MDL agenda**".
- **Two senses of "fiber" are kept distinct** (L20–L22). A *preimage / value fiber* is `Fiber(ω) = {z | B_ω(z) = true}`, arising "when a non-injective operator aliases inputs"; anti-unification gives "**point substitutions**, not multi-valued preimage fibers". An *occurrence / bundle fiber* is "the k child occurrences (ω, c) unfolded from a parent object ω under a 1-to-many cover" (`lift-frame`, `collect-tree-occurrences`).
- **Table versus graph** (L23). "Root-aligned `anti-unify` is isomorphic to `observation-bucket` over root-to-leaf path selectors. True graph topology enters only with **unaligned correspondence** … and **cross-row linkage** (`pairs`, `anchors`, `frame-edges`)."
- **Where search lives** (§2.1 table, L66–L72). Each mechanism is described by the same four columns: ambient space, shared part `p`, per-instance part `θ_ω`, and where the search is. Aligned AU: no search. Unaligned subtree AU: correspondence search. Library AU: subset search. Exact and Stage A synthesis: computation search over fixed rows. Top-down pullback, product and lift: "decoder & partition search". This table is the nearest thing in the trail to the owner's "it's all lift, projection, fiber 'calculus', … substitution, conservation, and residuals" stated as one schema: a shared part plus a per-instance residual, with the search located in a different place for each mechanism.

### 1.1 What each phase proposed, what was built, the measured effect

Sources: proposal in §3–§4 (L89–L158); record in §6.2–§6.7 (L194–L323). "Work" is the kernel's metered unit.

| Phase | Proposed | Built (plan8 §6.2, §6.7) | Measured (plan8 §6.3, §6.7; plan9 §1.1) | Root kernel today |
| :-- | :-- | :-- | :-- | :-- |
| **P8.1 structural** | Share repeated bindings through `:code-eval` of a quoted body ("let-sharing"); solve the holes of an injective constructor in parallel ("product slots"); project tuple inputs to components; find exception guards by pairing features Stage A already evaluated | All of it: `let-call`, `bind-model`; `product-join`, `product-slot-frame`, `compose-product-model`; `component-bindings`; `feature-pair-predicates`; `au-substitutions-frame` moved to `unify.lisp`. Later: coupled products (4 candidates per slot, 256 combinations), `share-repeated-subterms`, `constructor-au-decompositions`, fold rules `fold-equal-code-apply`, `fold-equal-code-subst`, `fold-member-tuple` | Probe 5 (conditional tuple scan): failed at 800k and 4M work before; ~698,000 with `:heuristic-budget 16000`; then 264,353 at the default after §6.7; model 253 bits against 264. Coupled products: four slots 68,602 work against 387,378; five slots stop at the bound after 83,663 against 6,096,924. Bucket-pair guard: a 27-bit guard in 30,000 work and 231 comparisons (§1.3 probe 6) | STILL-IN-CODE: `frame.lisp:674` `let-call`, `:710` `bind-model`, `:768` `share-repeated-subterms`, `:582` `product-slot-frame`, `:868` `compose-product-model`; `synthesize.lisp:636`, `:639` (coupled limits); `proposals.lisp:388` `component-bindings`, `:543` `constructor-au-decompositions`; `decompose.lisp:187` `feature-pair-predicates`; `requirements.lisp:310`, `:345`, `:358`. `au-substitutions-frame` (`unify.lisp:75`) is TEST-ONLY |
| **P8.2 metrics** | A `:metric` on the frame; library pairs of a decoder and a solver as residual metrics; Stage A budget that grows with the number of inputs; frame descriptors and address lookup | `frame-metric`; `(:metric-decoder d q tag-bits)` edges priced in Stage A (`priced-correction`) and pulled back in Stage B (`metric-residual-decompositions`); `:shift-seq` with `:argmax-corr`; anti-unification "code-edit" corrections; `stage-a-budget`; `*max-eager-proposals-per-node*`; `evaluate-frame-descriptors`, `frame-addressed-entries`. **Not built:** moment-difference solvers; Stage B pullback for `:code` edits; `(* , /)` decoder; rotating shift; `:metric` keyword on the entry points | Probe 2 (irrelevant extra input): 158,461 to 34,067. Probe 4 (symmetric tuple scan) **regressed** 80,212 to 112,979. Shifted sequences: solved at ~180,000 with `:heuristic-budget 60000`, unsolved at the default | STILL-IN-CODE: `frame.lisp:19` (metric slot), `:508`, `:468`, `:1583`, `:1645`; `laws.lisp:1250`, `:1277`, `:1314`; `decompose.lisp:30`; `synthesize.lisp:373`, `:1042` (default `nil`). `:shift-seq`/`:argmax-corr` are GONE from the kernel and live in `bootstrap/build-batteries.lisp:827-949`. `frame-addressed-entries` (`descriptors.lisp:945`) has no caller |
| **P8.3 topology** | Typed, row-keyed `frame-edges`; an induced row order with a reusable `:locality-key`; an availability preorder on columns; symbolic solving of a conserved quantity for the target | `solve-equality-symbolically`, `target-sensitive-p`, `orient-conserved-quantity`; hard `:equal`/`:distinct` edges checked in exact search; `schema-availability`, `orient-available`; `induce-row-order`, `:locality-key`. **Not built:** `:recurrence` edges; pricing of `:persistence` edges; edges in nogood clauses; any call of `with-induced-row-order` from the search | Only pass/fail gates in `tests/topology.lisp`: hard edges prune; shuffled tables recover the same key; noise induces no edges; the index map of `reverse` is derived from `I + j - (n-1) = 0`; GF(5)/GF(7) solvers lift to `:int` | STILL-IN-CODE, mostly TEST-ONLY (details in §1.3) |
| **P8.4 theories and cleanup** | Monoid "motifs" from stars of law edges; anti-unify solvers across prime fields; archive library entries that do not pay for themselves; remove 800–1,050 lines | `induce-fold-motifs` (kind `:motif`), `lift-field-solvers`, `amortize-library-entries`; laws stored as knowledge entries; the M4 discovery harness moved to `milestones/` | A third fold instance receives its `:foldr = :foldl` law "in under `2,000` work, no search". Decoys archived on the third batch. **LOC gate not met:** 12,472 to 13,771 (+1,299), then 15,154 | STILL-IN-CODE: `consolidate.lisp:833`, `:951`, `:603`, `:466` |

Plan8 §6.6 gives its own account of the missed size goal (L279–L287): the four phases added about 1,530 lines against a budget of 550–650, and "§2.2's `800–1,050` removable lines are not there to remove at this commit. A reachability scan from the kernel tests finds no dead definition". Of the three estimated savings, 350–450 became 177, 250–350 became 32 and 200–250 became 6. On the second it says: "Replacing them with transformers learned from `(source, target)` pairs is a research change, not a cleanup: the one transformer the tests learn is `(code-child X0 0)`, within `20,000` work, and the inverters are `:code-match` / `:code-bind` / `:code-subst` trees many times that size. Whether enumeration can reach them was not measured."

### 1.2 (a) The metric engine: the existing geometry in embryo

**The idea** (plan8 §3.1, L105): "Heuristic condensation is **coordinate-chart induction**: Stage A finds π̂(X) placing targets near 0 displacement under a transformation action, and Stage B pulls targets back along that action." A library decoder `d(Ŷ, δ) → Y` paired with a solver `q(Ŷ, Y) → δ` "**co-induces** both a Stage A residual metric and its matching Stage B pullback `Y = d(π̂(X), Z)`" (L39).

**How a residual is priced today, read from the code:**

1. *Stage A* (`condense-heuristic`, `condense.lisp:24`) enumerates candidate programs over the frame's inputs. For each row it takes the allowed target value closest to the prediction (`select-closest-witness`, `frame.lisp:1719`) and pays for the difference with `priced-correction` (`frame.lisp:1645`).
2. *The built-in price* is `correction` (`frame.lisp:1533-1581`), **host code, one rule per type**, in bits: `:int` pays the bit size of the difference; `:bool` pays 1; a prime field pays the centred modular difference; a tuple pays 1 bit per equal part and a correction per unequal part; a sequence pays a positional `:seq-delta` (length change, elementwise corrections, raw tail), capped at replacement; `:code` pays an anti-unification edit (`code-edit`, `frame.lisp:1583`: number of holes, their positions, their fillings) or replacement.
3. *A frame metric* (`frame.lisp:17-19`) overrides the price: an `:int` expression over (predicted, target) that must be provably total; the price is `max(1, M(p, y))` (`frame.lisp:1655-1661`). The packet that rebuilds the target stays the built-in one.
4. *Library metric decoders* compete when the frame has no metric of its own (`frame.lisp:1662-1667`). For up to four pairs of the target type (`metric-decoders`, `laws.lisp:1277`, `limit 4`), `metric-delta` (`laws.lisp:1314`) runs the solver in the VM, replays the decoder to confirm `d(p, δ) = y`, and prices the miss at `tag-bits + value-bit-size(δ)`. The cheapest of built-in and decoders wins.
5. *Stage B* turns the residual into a child problem. Three routes exist: the additive one `Y = base(X) + Z`, host-coded (`make-additive-residual-decoder`, `decompose.lisp:13`); the metric one `Y = d(base(X), Z)` (`metric-residual-decompositions`, `decompose.lisp:30`), whose child has the delta's type; and the conditional one `(if G base Z)` with a guard search.
6. *The metric on a child* (`pulled-back-metric`, `frame.lisp:508-542`) survives in four cases only: the identity decoder; a conditional that passes the child through on one branch; a decoder that reads nothing but the child, composed as `M(d(z), d(z'))` if provably total; and a child of the target's type where replay on at most three rows shows `M(d(x,a), d(x,b)) = M(a,b)`. Otherwise the child falls back to the built-in price for its own type. The docstring states the limit: "A decoder that reads the row's inputs otherwise gives the child a price that depends on the row, which a metric of two values cannot state."

**In which space.** Always in bits, in the value space of the frame's *own* target type. A child node prices its residual in its own representation while its program is composed through every ancestor and priced at the root: the docstring of `node-stage-a-model` says "Its residual is priced in the node's representation, not the root's" (`synthesize.lisp:394`), and the audit describes the node price `B(n)` as "the root-priced program plus residual bits in the node's own representation" (plan9-audit §4.5, L116). So the kernel already mixes ambient (root) pricing for programs with induced (child) pricing for residuals, which is the question the owner leaves open ("I'm not sure if there are better options for bootstrapping generated and intermediate spaces other than pricing in the original or ambient spaces").

**What was found awkward.** Each item is a measured or code-read finding from these documents.

| # | Finding | Source |
| :-- | :-- | :-- |
| 1 | A library metric is paid for in VM work out of Stage A's own budget. One `metric-delta` on the shift fixture costs 3,334 units; Stage A completes at 12,377 units of which 10,662 are metric evaluation; at budgets 2,000 and 8,000 Stage A has no model at all. The task is unsolved at the default budget and solves at 100,050 work with `:heuristic-budget 16000` | plan9-audit §6.1 (L219–L226), App. B (L591–L609) |
| 2 | "**A metric decoder taxes every search of its type.** Stage A asks each decoder about every miss, on the same budget as its own enumeration. One unguarded solver more than doubled an unrelated search. The shift battery is now guarded; nothing in the kernel bounds the next one." | `charlie:plan9.md` §8.4 |
| 3 | The additive residual stays a host fast path; serving `+` as a library chart "would charge VM solver + replay steps on every missed row of every integer task". So there are two parallel mechanisms, one host-coded and one in the library, and unifying them was refused on cost | plan9 §1.3 Guardrail 3 (L68); plan9-audit §4.4 (L105–L107) |
| 4 | A partial chart conflicts. For `(*, /)`, "a row whose prediction does not divide its target keeps `(= (* 'p Z) 'y)`, which nothing satisfies, so the child frame conflicts". And a heuristic solver that misses a row "has not shown the row unsatisfiable" | plan9-audit §4.4 (L108), §11.3 item 2 (L467–L473) |
| 5 | Edits to code do not pull back. The anti-unifier "is taken per row against the predicted value. Its pattern is the same on every row only when the Stage A program is a literal"; otherwise "the edit paths differ by row and no single `code-subst` decoder exists". `:code-subst` "fills holes in a template and cannot edit a computed prediction" | plan9-audit §4.4 (L109), §11.6 (L532). `:code` metric is "pricing only" (plan8 §6.2, L199) |
| 6 | "A frame metric leaves no packet": when the frame has its own metric the decoders do not compete | plan9-audit §4.4 (L110) |
| 7 | A price of zero for a permutation "conflicts with the clamp to at least one bit … and with '0 iff equal'". Sets and unordered collections pay full positional mismatch | plan9-audit §8.8 (L359); plan8 App. B.1 (L458–L467) |
| 8 | Pricing `:persistence` edges "through the existing pair residual penalized exact models whose targets legitimately differ along the chain"; the proposed tie-breaker "is not a code length, yet it enters model ranking and node priority. It makes a cliff" | plan8 §6.4 item 15 (L245); plan9-audit §8.6 (L327–L330) |
| 9 | A lifted child "has one row per call site, so its residual carries more row names than its parent's. Correct lifts look non-improving" | plan9-audit §4.5 (L116) |
| 10 | The node price is "not pure MDL": it adds half a policy score and 16 bits per coupled requirement | plan9-audit §4.5 (L117); still so at `synthesize.lisp:499-500` |
| 11 | Budgets, not mechanisms, decide outcomes: "should be read as 'the mechanism works' rather than 'the policy finds it'" | plan8 §6.5 (L250–L256) |
| 12 | The residual's stored shape `(row-key . witness)` is read by consolidation, the hit mask and 11 tests, so the delta packet was thrown away and Stage B recomputed it; fixed by a parallel `heuristic-packets` field | plan9-audit §4.4 (L111). STILL-IN-CODE `decompose.lisp:34`, `:599` |

### 1.3 (b) Topology: what it was for and whether anything calls it

| Mechanism | Purpose in the plan | Root kernel today |
| :-- | :-- | :-- |
| `frame-edges` (`:equal`, `:distinct`, `:persistence`) | Replace positional `pairs`/`anchors` with typed relations between rows, keyed by row key (plan8 §3.4.1, L131–L133) | Slot at `frame.lisp:20-24`. Hard edges are enforced in exact search (`violated-edge`, `enumerate.lisp:449`; `settle-row-edges`, `:459`) and enter the scope signature (`synthesize.lisp:248-259`). **No kernel code creates an edge** except `with-induced-row-order` (`proposals.lisp:789`), which has no kernel caller; edges otherwise come from the caller of `make-frame`. They sit beside `pairs`/`anchors`, which were already keyed by row (plan8 §6.1, L190: the plan "overstated the problem"). A pullback drops them unless the decoder is the identity (`frame.lisp:562`). `:persistence` "constrains nothing" (`frame.lisp:22-23`) and is not priced. `:recurrence` is NEVER-BUILT |
| `solve-equality-symbolically` | Turn a conserved quantity `C(X, Y) = c0` into a closed form `Y = g(X)` by applying certified solver witnesses to the equation as syntax (plan8 §3.3, L122–L127) | `laws.lisp:809`. Its only caller is `orient-conserved-quantity`. TEST-ONLY in effect (`tests/topology.lisp`, `tests/audit.lisp`) |
| `target-sensitive-p` | Reject invariants that do not depend on the target, such as `(- Y Y) = 0` | `laws.lisp:892`; called only at `laws.lisp:948` inside `orient-conserved-quantity` |
| `orient-conserved-quantity` | The conservation-to-generation step: symbolic route first, numeric `conserved-quantity-frame` as fallback | `laws.lisp:931`. **Zero kernel callers.** TEST-ONLY. Plan9 §1.3 (L60) and the audit (§3, L43) both confirmed this on 17 Nov; it is still true |
| `induce-row-order`, `with-induced-row-order` | Sort rows by a synthesized key so that adjacent targets vary least; compare against independent and "star" baselines; attach the chain as `:persistence` edges | `proposals.lisp:707`, `:789`. TEST-ONLY |
| `:locality-key` | Store the key for reuse in correspondence search | Kind defined at `proposals.lisp:625`; registered only by `with-induced-row-order`; read by `milestones/corpus.lisp:464-493`, a milestone driver outside the kernel |
| `schema-availability`, `orient-available`, `rank-lt-p` | An "ontology-free" causal order on columns: a target may read only inputs whose rank strictly precedes its own | STILL-IN-CODE and live: `ast.lisp:338-368`, `frame.lisp:1365`, `:1380`; `start-synthesis`, `start-search` and `start-heuristic-search` assert it (`synthesize.lisp:174`, `enumerate.lisp:358`, `condense.lisp:83`) |
| `projection-row-keys` | Enumerate accessors of compound inputs as candidate row keys in the VM | `proposals.lisp:675`; reachable only through `induce-row-order` |

One further fact found while checking: invariants *are* discovered in the kernel (`observation-invariants`, `enumerate.lisp:728`, which marks observation buckets that are constant across rows and emits `:observed-invariant` messages), and reorientation *is* implemented (`laws.lisp:931`), but **no kernel path connects the two**. The only kernel reader of an invariant bucket is the descriptor builder (`descriptors.lisp:521`). The loop "find a conserved quantity, then solve it for the target" is closed only inside tests and milestone drivers.

### 1.4 (c) Theories: monoid fold motifs

Proposal (plan8 §3.5 item 1, L143): "Deduplicated quotienting of connected `(:refactored-by :foldr)` + `:associative` + `:identity` `:law` edge stars into reusable **Monoid / Fold-Homomorphism** motifs licensing `:foldr <-> :foldl` / `:scan` rewrites on new instances."

As built (plan8 §6.6, L262, and §6.7, L306, L312):

- Each `:law` that states an operator's associativity or identity gets an edge saying so (`(:associative op)`, `(:identity op (e))`).
- A function refactored through a fold as `(fold X 'e '(op X0 X1))` whose operator has both edges is an instance.
- When instances of two folds of one signature cover two or more operators and agree on probe sequences, the equation of the two folds is registered as a `:motif`.
- Every instance, including later ones, then gets the law `F(X) = other-fold(X, e, step)` as a sampled conjecture.

Departures recorded: transfer "emits a sampled law, not a rewrite rule … It licenses a proposal; it does not rewrite"; `:scan` is not covered; formation needs two operators. After the audit: "Replay licenses a proposal; a recorded law needs evidence", motif premises must be tested laws (`usable-motif-law-p`), and the licensed decoder is stored as a `:decoder-template`. The audit of plan9 v2.0 adds the limit that matters for any "theory" layer (§11.3 item 4, L489–L494): "A motif is an empirically found relation … Its premises may be certified; the step from them to the transferred law is not", so attesting the transferred law as `:derived` "promotes sampled evidence to that grade".

Status: STILL-IN-CODE (`consolidate.lisp:833` `induce-fold-motifs`, `:951` kind `:motif`, `:698` `usable-motif-law-p`, `:774` `record-other-identity`; `proposals.lisp:1020` `remember-motif-decoder`). The motif is the one place in these documents where the knowledge library's own edge graph is pattern-matched to produce new knowledge.

### 1.5 (d) The "SMOCE cycle" figure

`figures/smoce-cycle.dot` (19 lines) is a single loop of six boxes: `Frame Omega (Rows + row-key frame-edges + Availability Preorder + Metric d_L)` → `1. Cover` (lift, parallel slot cover, canonical `sort-by(k(X))`) → `2. Correspond` (locality align, match constructors in O(|t|)) → `3. Orient & Unwind` (availability, symbolic or heuristic solvers) → `4. Conserve` (closed-form least general generalization, or Stage A and bucket-pair search under the metric) → `5. Extract` (co-induced pullback, parallel product join, safe let-sharing), with a back edge labelled "Child subproblem(s) or CEGAR refinement".

It illustrates the table at plan8 L93–L99, which claims that "Both AU/library refactoring and TD+BU synthesis instantiate **one five-stage fibered factorization cycle** over `frame`s" and gives, per stage, what it is on syntax and what it is on computation. It is a description, not a mechanism: there is no operator, struct or function in the kernel that takes the five stages as steps (NEVER-BUILT as code). What was built are the individual boxes, as separate host functions.

### 1.6 What Plan 8 deferred or dropped

- **Removed from the document on day one** (first version `2b8a912` §4.2–§4.5, visible only in git): a "latent world model" design. Two "prediction contracts" (open-loop rollout through `:scan`, versus online "prequential" filtering through `:scan-filter` in which the model predicts, then reads the observation, then updates its latent); a price for latent channel capacity `C_cap` so that "neither 'latent = next observation' nor unbounded history-recording sequences can cheat MDL"; latent-hole decoders `F(o, a, Z)` proposed by running Stage A again on the rows it missed ("regime multiplexer") or by anti-unifying per-episode Stage A models into a shell such as `(+ s (* Z a))`; "hindsight fibers" `Fiber(L_t) = {z | F(o_t, a_t, z) = o_{t+1}}`; and alternating Viterbi decoding of the latent path with synthesis of the transition law. NEVER-BUILT. Plan8 §5.1 (L166–L170) keeps a four-line summary.
- **§5 deferred frontiers** (L162–L178): coupled intermediate fibers and latent accumulators; unaligned set and graph correspondence; "Active Intervention & Disambiguating Query Selection" ("Selecting inputs or online actions whose predicted outcomes maximally split surviving candidate programs or narrow ambiguous preimage fibers", L173–L174); branch-closing controllers, totality extensions, discriminative descriptors; decoder-shell anti-unification and "reifying `frame` views as object-language values behind a static capability firewall".
- **Appendix B** (L452–L515): minimum-cost bipartite matching as a set metric, and a fuel-bounded fixed-point combinator `(:fix-seq fuel init step)` that "decouples loop termination (bounded by a structural spine) from topology degree". NEVER-BUILT as kernel or library code; a `:fix-seq`-shaped function appears only as a totality-analysis fixture (`tests/totality.lisp:168-186`).
- **Appendix C** (L519–L565): monotone branch closing and marginal stopping; three totality extensions; contrastive descriptor synthesis; "variable-compute compositional address decoding". Of these only the totality extensions were built (`ast.lisp:1009-1023`, `tests/totality.lisp`).

---

## 2. Plan 9 and its audit

Title (L1): "Plan 9: Closing Heuristic Induction, Homoiconic Conditional Propagators, and Geometric-Topological Unification".

### 2.1 The calculus, as written (plan9 §2.1–§2.2, L73–L136)

Plan 9 organises the kernel around "Two Mathematical Motifs".

**Motif I, "Topological Projection, Pullback/Lift, and Fiber Calculus"** (L75–L82). The stated object: "Every structural step in `lisploop` acts on the **input-requirement bundle** E → Ω", where Ω is the set of rows and the fibre over a row is its requirement (the set of target values the row allows). Four operations are defined, each by pointing at existing host functions:

| # | Operation | Definition given | Host functions named | Today |
| :-- | :-- | :-- | :-- | :-- |
| 1 | **Projection** `π: Ω → V` | "Quotienting coordinates … or partitioning rows into behavioral equivalence classes" | `project-frame-rows`, `orient-available`, `observation-bucket` | `frame.lisp:1350`, `:1365`; `enumerate.lisp:604` |
| 2 | **Pullback and 1-to-many lift** `d*: A_ω(Y) ↦ B_{ω,c}(Z)` | "Pulling parent requirements through `Y = d(X, Z)`". `lift-frame` "constructs the full call-site cover by requirement folding"; `probe-frame-coordinates` folds only chosen output coordinates | `pullback-frame`, `product-slot-frame`, `lift-frame` | `frame.lisp:544`, `:582`, `:1194`; `probe-frame-coordinates` (`:1108`) has no kernel caller |
| 3 | **Fiber narrowing** (conditional propagators) | "Intersecting pulled-back requirements `B_{ω,c}(Z)` with guarded inverse preimages" | `propagate-requirements`, `solve-equality-symbolically` | `laws.lisp:736`, `:809` |
| 4 | **Fiber separation / sectioning** | "When π(ω1) = π(ω2) (or lifted call sites) collide on child inputs with incompatible requirements `B1 ∧ B2 = ⊥`, either recording a deductive `nogood-clause` … or adjoining a separating context coordinate κ(X)" | `nogoods.lisp`, `dip-repaired-decompositions`, `dependency-expander` | `nogoods.lisp:540`; `proposals.lisp:325` |

**Motif II, "Observed & Generated Geometries, Co-Induced Metrics, and Embeddings"** (L95–L101). A table of three spaces, each with an "observed geometry" and a "generated / library geometry":

| Space | Points | Observed geometry | Generated geometry |
| :-- | :-- | :-- | :-- |
| Target space `(Y, d_L)` | Values and ASTs of the target type | Host `+` delta and structural tuple, sequence and code deltas | Library `(:metric-decoder d q tag-bits)` and the pulled-back `frame-metric` |
| Row / corpus space `(Ω, d_Ω)` | Rows, or occurrences in ASTs | Chain variation `Σ d_L(y_u, y_v)` against independent and star baselines | `:locality-key` embeddings `k: X → Z^d` |
| Concept / library space `(F, d_F)` | Active functions and decoder templates | Probe input/output traces and job lift outcomes | `:descriptor` profiles and the compositional index |

**Identities claimed between operations**, collected from plan8, plan9 and batteries-and-reflection:

1. Anti-unification and synthesis are the same factorization (shared part plus per-instance part) with search in different places (plan8 §2.1).
2. Because constructors are injective, anti-unification yields "**point substitutions**, not multi-valued preimage fibers" (plan8 L21); put another way, it is the same pullback in the case where every fibre is a single point (the second half is my paraphrase).
3. Root-aligned anti-unification equals observation bucketing over path selectors (plan8 L23).
4. A residual metric and a residual pullback are one object, a decoder with a solver for its delta argument (plan8 §3.1; plan9 Motif II row 1).
5. A conserved quantity plus solvers is a generator: "Symmetric invariant search temporarily drops `<` to find `C(W) = c0`, then symbolically unwinds for the maximal-τ port" (plan8 §3.4.3, L137).
6. A nogood and a new separating coordinate are the two responses to one event, a collision of rows under a projection (plan9 Motif I item 4).
7. A solver is a section of a fibre with three obligations that together "complete the Galois connection on fibers": `:witness` (if the guard holds, the witness is a solution), `:uniqueness` (it is the only one), `:necessity` (if any solution exists, the guard holds; "equivalently ¬G(k, c) ⟹ Fiber(k, c) = ∅") (batteries-and-reflection §2.1 item 2, L59–L67; `:necessity` is STILL-IN-CODE at `laws.lisp:567`, `:614`, `:1114`).
8. Solver discovery is an experiment on fibres: evaluate `f` over a probe grid, group by known context into "empirical fibers `F(c) = {X_P | f(X_K, X_P) = y}`", build a child frame whose requirement is that set, synthesize a witness, then find the guard by partitioning the contexts where the witness replays from those where it fails (plan9 §3.1, L144–L149).
9. A law read in another orientation is a solver: a left-inverse law "proves surjectivity (`:witness`), not injectivity (`:uniqueness`)"; an unguarded involution gives injectivity algebraically; a dual left-cancellation law gives uniqueness (plan9 §3.2, L153–L159).

**What was implemented of the calculus.** Nothing in Plan 9 changed the standing of these operations. All four were already host Lisp functions over the `frame` struct before Plan 9, and Plan 9 names them and proposes patches to their callers. None became an operator of the VM or an object the synthesizer can search over. The VM's primitive table (`ast.lisp`, `+primitives+`) contains substitution and matching on code (`:code-subst`, `:code-match`, `:code-bind`, `:code-apply`, `:code-eval`, `:code-child`) but nothing for lift, projection, pullback or fibre; `lift-frame` is a host function (`frame.lisp:1194`). This is exactly the gap the owner names: "**lift has to be a synthesizer primitive just like substitution is!** Presently this is not true, it's wholly in the host lisp." (plan_v2_prompt.md L4). The parts of the calculus that did get built afterwards are items 7, 8 and 9: `:necessity`, `induce-conditional-solvers` (`consolidate.lisp:1512`, in a spec-driven form; the probe grid `solver-probe-values-for-type` is NEVER-BUILT) and `induce-law-solvers` (`consolidate.lisp:1581`).

### 2.2 The rest of Plan 9 v2.0, briefly

- §1.2 six "confirmed kernel defects" (L36–L52) and §1.3 five "unwired seams" (L54–L62), both taken from the audit.
- §1.3 four "guardrails" (L64–L69): no per-quantum Stage A cutoff; narrowing fallbacks stay active; host `+` stays a fast path; "Build & benchmark learned replacements *before* retiring host builders".
- §2.1 two "Motif-I improvements": complete the dependency-repair step on pure first-order projections; a "two-combinator pipeline lift" for list comprehensions.
- §2.2: a cache of prepared programs; a parallel packet field; closing six gaps relative to `main`; tuple-valued locality keys; "No Mid-Search Frame Reordering or Library Mutation"; three-stage descriptor scoring; memoized contrastive separators.
- §3: solver induction, law-to-solver extraction, finite-set propagation with at most 8 members, indexed dispatch.
- §4: follower-safe pruning, "soft priority parking" (+16 bits), marginal stopping; a learned residual around the analytical price, clamped to [-24, +48] over six node features; a one-call consolidation loop; a logarithmic "Levin" search tariff.
- §5: a rank-environment totality analyzer; `:fix-seq`; opt-in bipartite matching with a total `:sort-by`; `propose-disambiguating-query`; "trajectory-screened latent synthesis".
- §7: five "non-negotiable kernel invariants": pure-kernel isolation, deterministic unit-step preemption, zero-false-pruning soundness, permutation and renaming invariance, single-pass consolidation idempotence.

### 2.3 plan9-audit.md: every defect and over-claim

The audit tags each finding **(ran)** or **(read)** and gives its scripts' method. Its opening sentence (§1, L12): "The baseline in Plan 9 is accurate, but much of what it builds on that baseline is not. Three of the five 'latent bugs' in plan §1.2 are misdiagnosed, several cited functions do not exist, and a number of the proposals would break behaviour that works today or reverse decisions recorded in `plan8.md` §6.7."

**A. Proposals in Plan 9 v1.0 that would have broken working behaviour (§4).**

| Proposal | What the audit found | Kind |
| :-- | :-- | :-- |
| Yield-gated Stage A budget: continue only while a quantum improves the score or adds a feature bucket (§4.1) | Replayed on real runs, "The gate cuts live nodes and spares dead ones". The node that solves the conditional tuple scan reaches its exact model in quantum 8 with bucket counts `4 5 5 5 8 8 11 13`; the gate stops it at quantum 3. Two dead lifts grow buckets steadily and stop only at quantum 7. On the metric task there is no model after 8,000 work. "In both tuple probes the root's Stage A ends its budget with no model and no bucket." "The suite is tuned to the current multiplier": changing the constant 2 to 1, 3, 4 or 7 each breaks a test | ran |
| Queue ambiguous-narrowing fallbacks as deferred proposals (§4.2) | "It reverses a recorded fix" (plan8 §6.7: unsolved at 3,000,000 work without it, solved at 367,081 with it) and fails the test written for that fix. The stated cost was wrong: the reserve is "one turn in four times the number of actions, not 25% of turns". `:fallback-p` "carries two meanings" | ran |
| Narrow to a complete fibre "without fallback" (§4.3) | "The evidence rule forbids it on `:int`": completeness there "can only be `:sampled`, and sampled evidence keeps its fallback". "No 'necessary guard' obligation exists". "A list-valued witness fails validation" and six consumers would need to tell the two kinds apart; "The plan names only `propagate-requirements`" | read |
| Serve `+` through the metric-decoder protocol (§4.4) | Every missed row would run a solver and a replay in the VM; a clean library has no decoders and a test asserts it; the additive path also expands tuples and skips a literal-0 base; a partial chart conflicts; code-edit pullback has no single decoder; a frame metric leaves no packet; changing the residual's shape touches consolidation, the hit mask and 11 tests | read |
| Close branches that do not improve, with one "grace" (§4.5) | "Bound tightening can starve followers … As written this is false pruning." "The grace rule compares unlike quantities." "`B(n)` is not pure MDL." "Strictness is inconsistent … A chain of equal prices never spends grace and never closes." "It contradicts invariant 3." "At the default depth it does nothing." Structural nodes block the new promotion rule. For stopping: "A node's priority is an estimate, not a lower bound; the only true bounds are enumeration frontiers." | read, one ran |
| Retire `bootstrap-inverters.lisp` and `filter-map-decompositions` (§4.6) | "Filter-map is not reached by general lifts today (ran)." The gate sits in a phase before the work it depends on. "Templates do not bootstrap. A `:decoder-template` is learned from a successful decomposition of the same shape, so the first filter-map instance has nothing to retrieve." "Anti-unifying witnesses does not give the transfer rule … The link from a step's operator to its element solver … is a relation between two entries that anti-unification of one of them cannot recover." | ran, read |
| Consolidation changes (§4.7) | Fitting only the missed rows of a hybrid relation "overwrites the base" (a 27-bit law passes the size test and returns 13 where the base returns 8). `member-requirement` "does not exist". The shared-helper inequality "accepts a loss" (leaves 70 bits where the current rule leaves 44). Defaulting a flag to `t` breaks the archiving test. "The reorder moves the two-pass problem." A per-lift logarithmic charge is "not scale-free as written": 100 lifts of 100 work cost 700 bits against 10 linear. "Amortizing solvers and templates has no credit side … The ledger is keyed by category, not by entry." | ran |

**B. The five "latent bugs" Plan 9 v1.0 claimed (§5).** One is "not a bug" (the UIP clause keeping its bindings). One is "real, conditional" (the positional zip of a persisted nogood schema), and the proposed fix "misreads `probe-frame-coordinates`". One is "half right" (no kernel code calls `synthesis-episode-returns`; the learned target does replace the price; "The proposed target is ill-defined"). One has "facts right, cause wrong" (VM re-evaluation does not explain the budget override). One has "crash real, description and fixes wrong" (member tables). One is "partly right" (lineage edges: "Nothing downstream uses a closure edge").

**C. Gates (§6).** The headline gate, the metric test at the default budget, is "not reachable as planned": the 3,334 units are VM execution that the plan keeps metered, and a prepared program saves 11 of them. "`60000` was never required; `2000` cannot be reached without making the solver's own execution cheaper." Two P9.2 gates were "already met". The sort-versus-reverse separator: `<=` "is not an operator"; the example separators are 63 and 84 bits against a bound of 28; the kernel's sequence probes are all ascending, so "The best separator found on them was `(= X0 X1)`, which is false for any unsorted input"; and "`sort` and `reverse` take no code parameter, so `library-decompositions` never lifts them … The confusion class lies outside the path being optimised." Size: "Plan 8 budgeted `+550`–`650` and spent `+1,530`. It estimated `800`–`1,050` removable lines and removed about 215."

**D. Names and citations that do not match the source (§7, L251–L270).** Functions that do not exist: `prepare-program`, `evaluate-prepared`, `synthesize-recursive-function`, `member-requirement`, `call-bits`, `all-elements`, `sort-by`, a `:law` consolidation hook. Operators used in example guards that are not operators: `mod`, `<=`, `not`, `and`. Eight stale file:line ranges and one function cited in the wrong file. A capability list miscounted. "'Moment-difference heuristic solvers' (P9.4 row): No design section anywhere in the plan".

**E. Edge cases by section (§8).** The ones that matter for a redesign:

- §8.2 descriptors: "'Tier 1 is O(1)' does not describe today … Every `:necessary` descriptor is a Tier-1 descriptor that runs the VM on each pair. Tier-3 algebraic clauses are not evaluated at all." `frame-addressed-entries` "returns nothing on a frame whose rows allow more than one output, which is typical of pulled-back children". "A row whose evaluation errors is skipped, so a descriptor that errors on two of three rows came back satisfied (ran)."
- §8.3 solver induction: `probe-values-for-type` "returns `(0 1)` for `:int` … and nothing for sequences or tuples. On those probes `Y` is a valid witness for `(* X0 Z) = Y`, and no divisibility guard can be told apart from `t`." "Empirical fibers are cut off by the probe box."
- §8.5 propagation: "The union of tuple witnesses is not a conjunction of per-position memberships, and a disjunction blocks further unwinding." For inequalities, "Direction depends on the sign of the context value and on the position". "Simplifying before each unwinding step can move the target into two argument positions."
- §8.6 row embeddings: Stage A buckets "hold only target-typed expressions", so on a sequence target "the induced key became a noise column". `with-induced-row-order` "has side effects": it reorders rows, adds a hard edge and registers a library entry mid-search. "Nothing consumes `:persistence` edges."
- §8.7 totality: an off-by-one; a guard that "is itself partial"; counting `(tail ys)` in the slot of `xs` "would certify a diverging function (ran)"; halving "sticks at 0" under a negative bound; `:fix-seq` "type-checks and runs, but is not certified total"; the stationary law "must stay a conjecture with its fallback".
- §8.8 bipartite matching: "When it runs is unspecified"; registering a key from inside Stage B "makes library state depend on how far a search ran. Elsewhere search proposes and consolidation registers."
- §8.9 active queries: the requirement is not a membership, "Only exact search applies"; "'Maximise the number of distinct outputs' has no mechanism".
- §8.10 latent state: "The regime is a property of the decoder, not the schema." "Cross-time coupling is not what the product join handles." "The latent slot is unconstrained, so its search returns the smallest programs at once and its pool is the four smallest".

**F. Seven existing kernel defects found in passing (§9, L379–L389).** (1) The totality fixpoint iterates from stale flags, so a mutually recursive, diverging pair is marked total. (2) A call to a registered but undefined name is total. (3) Member tables crash relation consolidation. (4) A failed relation fit is never memoized ("One incompressible 6-row table costs `100,000` work on every bare consolidation"). (5) "Consolidation is not a fixed point after one call (ran). The docstring … says it is". (6) Lift templates are never generalized (later reclassified as a scope limit). (7) The positional schema zip. All but (6) have tests today in `tests/audit.lisp` (L432, L468, L486, L543, L574, L616).

**G. Review of v2.0 (§11).** "v2.0 fixes the large majority of what this audit found". Remaining: four items that would still break something, two that cannot be reached, a re-base, and smaller misreadings.

- Would break: requiring a definition for every callee "fails the suite at its seventh test" because the same branch makes primitives total; the all-rows chart rule breaks a metric test; the Levin formula with the count outside the logarithm charges 114 bits for a hundred cheap failures, "the effect the paragraph cites as the reason for the change"; attesting motif transfers as `:derived` "promotes sampled evidence".
- **Unreachable: the guard search.** "The example guard `(if (= X0 0) nil (= (* (/ Y X0) X0) Y))` has body size 57 … At 57, exact search does not find it within `60,000,000` work (ran)", on 49 contexts with a six-symbol grammar. "Guards of this size need the heuristic route (Stage A, then a conditional split), not `start-search`." This is the one direct measurement in these documents of what blind exact enumeration cannot reach.
- **Unreachable: contrastive separators.** The separators are 75 and 84 bits against a budget of 20,000 work; and "For higher-order combinators a separator over (X, Y) has to hold for every step function, so it usually does not exist: nothing over (X, Y) alone tells `map` from `map-twice`."
- Smaller: the "two-combinator pipeline lift" restates what `filter-map-decompositions` already does; a call "the plan says to add already happens"; a fold rule proposed for Probe 6 already exists and the real blocker is elsewhere (`rows-pin-values-p`).
- **Corrections to the audit itself (§11.7).** Its own suggested fix for the schema zip "was made without reading the function and is too loose"; one "defect" was "a documented limit of scope"; one finding omitted that the branch "also serves primitives".

### 2.4 What the audit says about why the design kept producing these

The audit does not offer a single root-cause thesis. What it states, in §10 (L393–L405) and in passing:

1. **Plans were written from reading, not from running.** Its remedy: "Test control changes by replay before building them. The method of Appendix C costs a few lines and would have shown the result of §4.1."
2. **Plans reversed recorded decisions without noticing.** "Keep the Plan 8 audit's decisions unless the plan argues against them by name. §4.2 and §4.3 each reverse one without saying so."
3. **Gates were not stated against measured baselines.** "State each gate against the measured baseline. Two of the P9.2 gates are met at `019736f`."
4. **Increments were not increments.** "P9.1 is not an increment. It bundles about fifteen deliverables across thirteen files, and its gate includes one test that cannot be reached … and two retirements that depend on P9.2".
5. **The behaviour is tuned to constants.** "The suite is tuned to the current multiplier" (§4.1, L68).
6. **Quantities of different kinds are added together.** "The grace rule compares unlike quantities"; "`B(n)` is not pure MDL"; "The term is not a code length, yet it enters model ranking and node priority" (§4.5, §8.6).

The audit's own slip (§11.7 item 1) shows the same mechanism acting on the auditor: a fix proposed without reading the function it relied on.

The explanation the *owner* gives is in the batteries prompt (§3.1 below): the agents were doing by hand, on the kernel, the experiment-and-patch loop that the kernel is meant to do on itself.

### 2.5 What Plan 9 actually built (from `charlie:plan9.md` §8, not in the working tree)

This section exists only on branch `charlie` (`15514a4`).

- **Landed:** the four fixes of P9.1; "batteries" as library sources read as data by a `batteries.lisp` (later deleted, see §3.3); a job uses the active library's solvers by default; solver dispatch by operator index; the totality analyzer of §5.1.A ("Only the sum measure is built; lexicographic orders are not. A bound must be a literal").
- **Baselines moved:** symmetric tuple scan 112,979 to 74,094; conditional tuple scan 264,353 to 220,691. Reason given: "their old figures included lifting the same combinator twice: `candidate-library-definitions` instantiated `:scan-tup` at the types it already had." So about a third of one headline figure was duplicated work that two rounds of audit had not noticed.
- **Shifted sequences:** unsolved at 300,000 at the default budget; 105,595 at 16000; 211,459 at 60000.
- **"Found and Left Open"** (§8.4), four items: "A metric decoder taxes every search of its type" (quoted in §1.2 above); "Preparation is linear in the lifts that score alike"; "Unchanged-library consolidation is not free" (4,266 work per run); "The loader reads functions and solvers. Laws, descriptors, decoder templates and transformers need forms before the host code that builds them can move."

---

## 3. batteries-and-reflection.md and plan-exec.md

### 3.1 The owner's original prompt, verbatim

`batteries-and-reflection.md` L3–L15, under the heading "Original prompt:". Everything in the block below is **OWNER**; typos are the owner's.

> Please familiarize yourself with the work in this repo. The lisp is the ultimate source of truth, but look also at plan8.md and plan9.md / plan9-audit.md, which describes the recent refactors.  Older plans, still relevant, are in plan7/*.md.  Plan9 was not completed, since we realized that the following would supersede it. Plan9 captures a lot of incidental complexity, imho, which really ought to live in the knowledge lib; the bug fixes of course have to land.
> 
> I'd like to explore adding 'batteries" to the repo through a built-in knowledge-library.  That is, It would be very helpful to try to abstract as much as possible to this library - functionality presently in the lisp source, including and especially the conditional propagators (which constitutes a lot of the details..) - while generalizing the VM to better reflect the underlying topological and geometric foundations.  Some of the complexity is unavoidable due to the structure of the VM / DSL: semantics of the language, e.g. handling tuples and sequences, but I wonder how much else can be abstracted using the homoiconic & reentrant design?  A lot of details there are "if <pattern> then apply this <pattern> to propagate information", which are rules learned in the process of programming the kernel.  [This is a commonality in addition to the topological motifs, which propagate information between different frames, and geometry, which (among other things) define what patterns are, and how similarity is mesured.]  But but!  These structures are exactly what the kernel seeks to learn in the process of search & looking for conserved quantities; they just happen to be conserved quantities known about the VM / DSL and so can live in the source rather than knowledge library.  What can we change on top of the recent refactor (plan9) to better support this?  Note that the batteries can still be tested through the current extensive lisp test suite, though I suppose testing also could profitably be put into a library; testing is also a way of better knowing what you know.  
> These goals cut closer to the original intent of the experiments, as you'll see in your investigations.  I'd like the batteries to be bootsrapped through application of tests - they emerge from the kernel, rather than being hand-coded.  
> The batteries should remove complexity pressure on the current kernel and, as always, open up opportunities for retiring old code / generalizing it for clarity, efficiency, and (where possible) speed.  Some aspects of batteries are already implemented, but that is provisional; I'd like for it to be bootstrapped .sexp files, not hand-coded (as this goes against the spirit of the project). 
> 
> Secondly, the kernel is reentrant, but in the original planning docs I meant this in a different way - that the search process of the kernel itself produces data that bootstraps rules and complexity for further search.  Elements like UIP and DIP do in a specific manner & allow for branches to communicate back to their calling procedure *why* a branch was bad (and which subsequent branches might also be, with this evidence, wrong or inadmissible) .  Another version of this might be a message saying "well I found this conserved quantity in the search" which then can dramatically factorize the search space.   Other messages might be the test suites themselves, which improve the quality of information – a thing that is hard to really propagate back to the original generator without symbolic messages. 
> Some of the complexity we're witnessing in plan9 and plan9-audit come from the agents running real simulations on the kernel and observing errors (or running mental simulations on the call graph) which again is what the kernel itself is supposed to be doing!!  Hence I mean both reflective, ala lisp-3, in addition to reentrant, to mean reinterpreting its own behavior as data to run synthesis on.  The sythesis on own-behavior can then later made actionable with the emission of rules, propagators, problem-dependent heuristics (hence not conserved across problems), or even just leaf residuals (such as preventing repeated applications of the same rules ... for which it appears some patches in plan9-audit are instances of), which are then used to structure subsequent search, exactly as is done now.  It will require some intelligent means of scoping the pattern application, plus the right means of applying the synthesized expressions; the former seems a bit less well defined and will require experimentation / thinking-though.  The latter is the nature of the simulator itself, so hopefully will be more straightforward. 
> Can we brainstorm a way of doing this cleanly?  
> 
> The batteries goal is largely independent of the reflective goal, but we should seek places where they can be made complementary - e.g. by bootstrapping some globally-general laws through reflection.  

The rest of the document (L18 onward) is an agent's reply. Its file links point into `~/.gemini/antigravity-cli/…`, and its one measured proof of concept cites a scratch file there (`probe-bootstrap.lisp`) that no longer exists, so that measurement cannot be re-checked from the repository.

Five statements in the prompt that bear directly on the current request:

1. On Plan 9: "Plan9 was not completed, since we realized that the following would supersede it. Plan9 captures a lot of incidental complexity, imho, which really ought to live in the knowledge lib; the bug fixes of course have to land."
2. On what the host code is: "A lot of details there are \"if <pattern> then apply this <pattern> to propagate information\", which are rules learned in the process of programming the kernel. … These structures are exactly what the kernel seeks to learn in the process of search & looking for conserved quantities; they just happen to be conserved quantities known about the VM / DSL and so can live in the source rather than knowledge library."
3. On bootstrapping: "I'd like the batteries to be bootsrapped through application of tests - they emerge from the kernel, rather than being hand-coded." and "I'd like for it to be bootstrapped .sexp files, not hand-coded (as this goes against the spirit of the project)."
4. On reentrancy and reflection: "the kernel is reentrant, but in the original planning docs I meant this in a different way - that the search process of the kernel itself produces data that bootstraps rules and complexity for further search. Elements like UIP and DIP do in a specific manner & allow for branches to communicate back to their calling procedure *why* a branch was bad … Another version of this might be a message saying \"well I found this conserved quantity in the search\" which then can dramatically factorize the search space."
5. On why the plans grew: "Some of the complexity we're witnessing in plan9 and plan9-audit come from the agents running real simulations on the kernel and observing errors (or running mental simulations on the call graph) which again is what the kernel itself is supposed to be doing!!  Hence I mean both reflective, ala lisp-3, in addition to reentrant, to mean reinterpreting its own behavior as data to run synthesis on." The open design problem the owner names: "It will require some intelligent means of scoping the pattern application, plus the right means of applying the synthesized expressions; the former seems a bit less well defined".

### 3.2 What the agent promised

**Four generalizations of the VM** (§2.1, L48–L74): let `:at` project heterogeneous tuples, so that "Products in the VM become true categorical products"; add a `:necessity` obligation to solvers; generalize type-template instantiation from functions to every knowledge kind (`instantiate-entry-template`), so that batteries are plain saved libraries; move a "rank-environment" totality analysis into the VM's static semantics.

**What moves from host Lisp to bootstrapped `.sexp`** (§2.2 table, L86–L93): hand-written batteries (439 lines); conditional propagators and solver guards; constructor and destructor fold rules (~155 lines of `requirements.lisp`); the functorial inverters (`bootstrap-inverters.lisp`, 292 lines); the descriptor builders (~190 lines); combinators, scans, motifs and metrics.

**The bootstrap pipeline** (§2.3, `figures/bootstrap-pipeline.dot`). A new knowledge kind `:spec`, "a serialized `frame` of I/O or relational test rows", linked to what it verifies. The figure: `Seed :spec Test Frames` → `Pure Kernel (Empty Library)` → three products, (1) `algebra.sexp & constructors.sexp` by "observe + certify + lift + guard search", (2) `sequences.sexp` by "recursive synthesis + AU consolidation", (3) `functors.sexp & descriptors.sexp` by "solve concrete inversions + learn-knowledge-transformer" → `Bootstrapped library/*.sexp` → (dashed) `Epistemic Self-Check & Query Refinement`. The text claims a "Zero-Hand-Coding Bootstrap" starting from "`(make-knowledge-library)` (completely empty!)", re-validation of evidence whenever an entry is retyped, and a regression gate in which "the kernel still regenerates equivalent `.sexp` batteries from scratch within bounded work".

**The reflective loop** (§3, `figures/reflective-loop.dot`). The figure: `Base Synthesis / Search Turn` → "Reify at Checkpoint (<= 1/8 work budget)" → `Reified Trace Frame Omega_meta` → "Op 1-4: AU, Invariant Search, Stage A/B" → `Reflective Synthesis on Own Behavior` → three sinks that feed back into the search: `L0: Tabu / Redundancy Guards` (absorbed into the node), `L1: Caller Factorization` (conserved quantities, partial regimes, nogoods, active test queries; absorbed into the parent or job), `L2/L3: Promoted Laws, Solvers, Descriptors & .sexp Batteries` (future jobs).

The diagnosis (§3.1, L109–L118): agents "repeatedly ran the same meta-loop *by hand*": run a probe, inspect the trace, "Notice a conserved pattern or invariant in the *search behavior itself*", and "Hand-code a specialized Lisp patch". The kernel "is already *reentrant* … and *homoiconic* … **but it is not yet genuinely *reflective***: the active search state … is locked inside opaque Common Lisp structs … rather than exposed as `frame` data".

Three components (§3.2–§3.3):

1. *Reification* of traces into ordinary frames: one row per node (parent decoder, proposal decoder, Stage A program, residual bits, work, outcome) and one row per evaluated candidate.
2. *Four classes of message*, generalizing the nogood, which is "the *only* upward symbolic channel from a child branch back to its caller". (i) Negative or redundancy messages, including "leaf residual" patterns such as `(code-match '(+ ?a (+ ?b ?z)) composed-decoder) -> :redundant`. (ii) Positive conservation messages: today, when a child finds a conserved quantity, an informative feature or a partial hit and then stalls, "**all of that discovered information is thrown away!**"; instead send it up, to a "**job-wide feature pool**" or to `orient-conserved-quantity`. (iii) "Epistemic" messages: when two small candidates agree on every active row, send up a disambiguating input, "literally *synthesizing better test suites mid-search*". (iv) Tariff messages: the per-node ledger breakdown, so the controller can "pace quanta by *information yield per candidate*".
3. *A four-level scope lattice* that separates what a rule depends on from how well it is established: L0 the node's subtree, L1 the job, L2 the library under a trigger, L3 the certified battery, with promotion from L1 to L2 "*only* when anti-unified across ≥ 2 jobs with zero task-specific constants AND positive Levin net utility". Reflection is capped at depth 1 and at one eighth of the job's work.

### 3.3 Done versus not done

The document's roadmap (§4, L182–L191) has no completion marks. The owner's commit `b3af2e6` says "step 2 of batteries +reflectivity done". Checked against the root kernel:

| Step | Item | Status | Evidence |
| :-- | :-- | :-- | :-- |
| 0 | Descriptor that errors on a row can no longer score satisfied | DONE | `tests/audit.lisp:687` |
| 0 | Dependency repair collects every collision of a pure projection | DONE | `synthesize.lisp:527-528`, `nogoods.lisp:181-182`; `tests/audit.lisp:739` |
| 0 | Learned predictor adds a clamped residual to the analytical price instead of replacing it | DONE | `synthesize.lisp:489-510`; `tests/audit.lisp:791` |
| 0 | `metric-delta` reuses its replay AST; `heuristic-packets` | DONE | `laws.lisp:1292-1327`; `decompose.lisp:34`, `:599`; `tests/audit.lisp:853` |
| 0 | Symbolic unwinding keeps the unsimplified form as fallback | DONE | `tests/audit.lisp:909` |
| 0 | Retyping a combinator whose state is itself a sequence | DONE | `tests/audit.lisp:967` |
| 1 | Heterogeneous tuple projection in `:at` | DONE | `ast.lisp:284-298` |
| 1 | `:necessity` obligation and bounded membership propagation | DONE | `laws.lisp:567`, `:614`, `:1114`; membership limit `*propagator-member-limit*` = 8 at `laws.lisp:674`; `tests/batteries.lisp:294` |
| 1 | Rank-environment totality | DONE | `ast.lisp:1009-1023`; `tests/totality.lisp`; `tests/batteries.lisp:472` |
| 1 | `instantiate-entry-template` for every kind; custom battery reader retired | DONE | `templates.lisp:392`; `batteries.lisp` deleted in `b3af2e6` |
| 2 | `:spec` kind, spec-driven synthesis and verification | DONE | `consolidate.lisp:1085`, `:1139`, `:1208`; `tests/batteries.lisp:633` |
| 2 | `bootstrap/build-batteries.lisp` writes `library/*.sexp` | BUILT, with the qualifications below | 949 lines, plus `bootstrap/recursion-schemas.lisp` (355 lines); `make bootstrap` (`Makefile:20-21`) |
| 2 | Retire `bootstrap-inverters.lisp`, `library/*.lisp`, `filter-map-decompositions` | DONE as deletions | all removed in `b3af2e6`; zero grep hits |
| 2 | Conditional and law solver induction | DONE | `consolidate.lisp:1512`, `:1581`; `tests/batteries.lisp:674` |
| 3 | Reify the search as frames | PARTLY | `messages.lisp` (128 lines): five "message readers" and `message-frame` |
| 3 | Upward `:conserved`, `:regime-hit`, `:disambiguate` messages; job-wide feature pool; leaf redundancy residuals; L0–L3 scopes; `*reflective-depth*`; a `:reflect` agenda action; `reify-search-frame`; `propose-disambiguating-query` | NEVER-BUILT | zero grep hits for each |

**Qualifications on Step 2, from reading `bootstrap/build-batteries.lisp`.** The batteries do not "emerge from the kernel" in the sense the owner asked for.

- Nine of the ten `:functor/*` transformers (the replacements for `bootstrap-inverters.lisp`) are ASTs built by hand with `term` templates and registered with `:status :validated` and `:origin :bootstrap-functor-transformer` (`reg-tr`, L354–L365; call sites L390, L417, L431, L443, L466, L516). One, `:functor/pointwise-param-witness`, is learned (L474–L495), in a language of two operators with the two constants it needs supplied, from one example row, with a budget of 50,000 work.
- `filter-map-decompositions` was replaced by a hand-registered decoder template, `:comprehension/filter-map` = `(map (filter X p) f)`, with `:status :validated` and a hand-set `:policy-score -18` (L711–L733).
- Integer cancellation laws are entered as `:trusted-axiom` (L105–L117); the `cons` destructor laws are stated by hand and then validated (L314–L320).
- Functions that are synthesized from `:spec` rows are synthesized in a per-spec grammar chosen by the author, in a hand-ordered curriculum. Example: `:argmax-corr` is searched over two operators, `:best-shift` and `:at`, after `:seq-corr` and `:best-shift` have been supplied as its stepping stones (L853, L867, L881–L886). A recursion-schema proposer is supplied from `bootstrap/recursion-schemas.lisp`.
- Budgets are small: `synthesize-spec-entry` defaults to 350,000 work with a heuristic budget of 15,000 (`consolidate.lisp:1208-1210`).
- The output is not in the working tree. `library/` does not exist at the root and was never tracked; a copy is tracked under `v2/library/` (eight files, 137 KB: algebra, arithmetic, constructors, descriptors, functors, scans, sequence-shift, sequences; the promised `metrics.sexp` does not exist). Root tests load batteries from `library/` (`tests/support.lisp:517-548`) and `read-battery` asserts that the packet exists (`consolidate.lisp:1687`), while `make test` does not depend on `make bootstrap` (`Makefile:16-30`). Read as written, the battery-dependent root tests cannot pass in this working tree until the bootstrap is run. I did not run either.

**What exists of reflection.** `messages.lisp` turns the messages a job publishes into rows of object-language values and those rows into "an ordinary frame: what the kernel does to a task it can then do to a record of its own search, and a rule about the search is an expression the VM evaluates on those rows" (L3–L7). Reading is free by design: "Reading messages charges no ledger of the job that sent them." No kernel code reads a message frame. The one consumer is `experiments/yield-gate.lisp`, which is worth knowing about because it is the complete reflective loop run once, offline: it records two searches, reads their Stage A messages as rows, writes the Plan 9 yield gate as an object-language expression, uses the kernel's own conflict check to ask "Is being needed a function of what the gate reads?", and uses observation search to propose gates that never stop a needed search on the recorded rows. Its header states the limit: "One that passes is a suggestion: the rows of two searches are sampled evidence, and they say nothing of a gate that would run longer than the recorded searches did." (I read the script; I did not run it.)

### 3.4 Numbers reported in batteries-and-reflection.md

| Claim | Where | Check |
| :-- | :-- | :-- |
| 196 kernel tests / 928,751 checks and 40 milestone tests / 186,771 checks at `7a0d6bf` | L19 | Not re-run. `tests/*.lisp` holds about 222 `deftest` forms today |
| `learn-knowledge-transformer` synthesizes the functorial inverter "de novo … in `52,751` work (`157` body-bits)—with zero host AST builders" | L83 | Unverifiable (scratch file gone; the number appears in no test). The shipped bootstrap hand-builds nine of ten such transformers |
| A `cons` solver narrows `(= (cons X0 '(20 30)) '(10 20 30))` to `(= X0 '10)` with `narrowed = 1`, `fallback = nil` | L84 | A joint `cons` solver is exercised at `tests/batteries.lisp:294-310`; the quoted figures were not re-run |
| Host code to move: 439 + ~155 + 292 + ~190 lines | L86–L93 | The three files named are gone; the kernel is larger than before (17,647 lines against 15,257), with `consolidate.lisp` now 2,118 lines |
| "`1` metric check costs `3,334` VM units so `2,000` budget evaluates `0` candidates" | L148 | Quoted from plan9-audit App. B |

### 3.5 plan-exec.md: the execution strategy

Not a lowering to another representation but a second evaluator that is **exact with respect to the first**. "Every evaluation of an expression built from primitives is now run by a host closure. It reports the status, value, error text and work that the interpreter reports, at every budget cutoff. No ledger in the test suite changes by a unit." (L11).

How (L28, L36–L39):

- `expression-closure` compiles an expression into a Lisp closure "that also counts, in `*closure-work*`, what the VM would charge".
- `start-evaluation` runs the closure at once and returns an evaluation with a single instruction, `:settle`, "which costs that count and yields the closure's outcome when paid". Because paying, cutting off and resuming are done by existing code, "no caller changed".
- There is "no second tariff": a primitive is priced and run by the VM's own `primitive-cost` and `execute-primitive`. A closure "charges an instruction before running it", so a failing primitive fails at the same work with the same message.
- Whatever is not closure-able goes to the interpreter: "a call of a defined function, a symbolic `:code-*` operator, code that is not a literal, a hole. In the kernel suite that is 3,798 evaluations of 244,865."

Measured (L13–L22): the search benchmark `quartic 77` in batch dispatch 1.83 s to 0.45 s (4.0×); `quadratic 70` 3.8×; the same benchmark in unit dispatch 1.9×; milestone suite 22.7 s to 12.1 s; kernel suite 3.39 s to 2.40 s; one evaluation of Probe 5's step function 15.7 µs to 2.1 µs (7.5×). Ledgers are byte-identical over 222 tests and 415,539,255 work units (`experiments/ledger-fingerprint.lisp`). The cost was +100 kernel lines.

Two further changes carried much of the gain and are about the data structure, not the evaluator (L29–L30): AST metadata for pooled symbols moved from a weak hash table to the symbol's property list, because lookups in that table "take a system lock and were 45% of the benchmark's samples"; and one of two type walks per enumerated candidate was removed. "with closures switched off, items 2 and 3 alone bring the quartic benchmark from 1.83 s to 1.18 s."

What is left (§5, L50–L60): metadata lookups on conses, still in the weak table, are 19% of the kernel suite; `invalidate-app-meta` "Walks the whole table at every function definition" (8%); calls of defined functions are not compiled ("recursion needs the cap"); and "One job step per unit" is "Inherent to stepping one unit at a time". "Host `compile` for hot entries was not built. Nothing measured needs it."

Status: STILL-IN-CODE (`vm.lisp:87` `*closure-evaluation*`, `:421` `*closure-limit*` = 32,768, `:439` `expression-closure`, `:530` `settled-evaluation`). The audit adds one caution (§11.5, L519): "the closure cache is keyed by node identity, so a fresh AST per replay adds entries on every call until the table is cleared".

A rate worth extracting for the budget question (my arithmetic, from plan-exec L15 and L66): the benchmark spends 29,382,492 work in 0.45 s, about 65 million work units per second in batch dispatch. On that scale the largest budget in these documents, the 60,000,000-work guard search, is on the order of a second, and the probe budgets (34,067 to 698,000) are milliseconds of evaluation. An hour would be roughly 2 × 10^11 units, about 3,900 times (2^12) the largest search any of these documents tried. The rate is for one arithmetic benchmark; unit dispatch and searches dominated by defined-function calls are slower.

---

## 4. Idea ledger

One line per mechanism. Status codes: **BM** built and measured; **B** built, no number beyond a passing test; **BU** built but unwired (TEST-ONLY); **BR** built then removed; **P** proposed, never built; **S** superseded or withdrawn after refutation.

### 4.1 From plan8.md

| # | Mechanism | Status | Numbers / location |
| :-- | :-- | :-- | :-- |
| 1 | Five-stage cycle (Cover, Correspond, Orient, Conserve, Extract) as one operator | P | Exists as a table and a figure only |
| 2 | Let-sharing: repeated bindings shared through `:code-eval` of a quoted body, with a definedness rule | BM | Probe 5 model 253 bits against 264; `frame.lisp:674`, `:710`, `:768` |
| 3 | Product slots: holes of an injective constructor solved in parallel, joined by an AND | BM | Probe 5: fails at 4M, then 264,353, then 220,691; `frame.lisp:582`, `:868` |
| 4 | Coupled product join with bounded pools (4 per slot, 256 combinations) | BM | 68,602 against 387,378; 83,663 against 6,096,924; `synthesize.lisp:636`, `:639` |
| 5 | Tuple inputs projected to component bindings | B | `proposals.lisp:388` |
| 6 | Exception guards from pairs of Stage A feature buckets | BM | 27-bit guard, 30,000 work, 231 comparisons; runs after the grammar search, not before; `decompose.lisp:187` |
| 7 | `au-substitutions-frame`: substitutions of an anti-unifier as a frame | BU | `unify.lisp:75` |
| 8 | Constructor anti-unification proposals with operator holes and lowered literals | B | `proposals.lisp:543` |
| 9 | Fold rules that split an equality through an injective constructor (`code-apply`, `code-subst`, tuple membership) | B | `requirements.lisp:310`, `:345`, `:358` |
| 10 | Stage A budget scaled by (inputs − 1)² inside lifted branches, doubled for lifted and recursive children | BM | Probe 2: 158,461 to 34,067; Probe 4 regressed 80,212 to 112,979; `synthesize.lisp:373` |
| 11 | Cap on eagerly prepared proposals per node | B, off | default `nil`; `synthesize.lisp:1042` |
| 12 | A metric carried by the frame | B | `frame.lisp:19`, `:1655` |
| 13 | Metric decoders: a decoder and a solver for its delta as both residual price and residual pullback | BM | 3,334 work per evaluation on the shift fixture; `laws.lisp:1250`, `:1277`, `:1314`; `decompose.lisp:30` |
| 14 | `:shift-seq` with `:argmax-corr` as the first non-additive chart | BM, moved out of the kernel | 100,050 work at budget 16000; unsolved at the default; `bootstrap/build-batteries.lisp:827-949` |
| 15 | Anti-unification "code-edit" as the correction between two code values | B (pricing only) | `frame.lisp:1583`, `:1626` |
| 16 | Metric pullback to a child in four cases, one by replay | B | `frame.lisp:468`, `:508` |
| 17 | Witness selection as a metered, resumable phase (`:heuristic-metric`) | B | `condense.lisp:247-251` |
| 18 | Frame descriptors evaluated once | B | `descriptors.lisp:915`, called at `proposals.lisp:205` |
| 19 | Address lookup of library entries from satisfied descriptors | BU | `descriptors.lisp:945`, `knowledge.lisp:273` |
| 20 | Symbolic solving of a conserved quantity for the target, with a sensitivity test by perturbing the target | BU | `laws.lisp:809`, `:892`, `:931` |
| 21 | Hard `:equal` / `:distinct` row edges checked row by row in exact search | B | `enumerate.lisp:449`, `:459`; no kernel producer of edges |
| 22 | `:persistence` edges | B, inert | recorded, constrain nothing, unpriced |
| 23 | `:recurrence` edges; edges in nogood clauses | P | |
| 24 | Availability preorder on columns, strict, as a DAG of symbolic ranks | B, live | `ast.lisp:338-368`; `frame.lisp:1365`, `:1380` |
| 25 | Induced row order against independent and star baselines; `:locality-key` | BU | `proposals.lisp:707`, `:789`, `:625` |
| 26 | Row keys enumerated from accessors of compound inputs | BU | `proposals.lisp:675` |
| 27 | Monoid fold motif from law-edge stars; transfer as a sampled law | BM | third instance in under 2,000 work; `consolidate.lisp:833`, `:951` |
| 28 | Solvers anti-unified across prime fields, lifted to `:int` as conjectures with sampled validations | B | `consolidate.lisp:603`; truncating division correctly fails to lift (`tests/topology.lisp:356`) |
| 29 | Net-utility archiving of library functions (bits saved minus search charged at 1/1024 bit per unit) | BM | decoys archived on the third batch; `consolidate.lisp:415`, `:466` |
| 30 | Laws and certificates as knowledge entries; evidence grades `:sampled` / `:exhaustive` / `:derived` / `:trusted-axiom` | B | `laws.lisp:1044`; `evidence.lisp` |
| 31 | Decoder templates generalized by anti-unification; motif decoders stored | B | `proposals.lisp:1020`, `:1033`, `:955` |
| 32 | Symbolic simplification by constant folding plus the library's rewrite laws | B | `laws.lisp:788` |
| 33 | Removing 800–1,050 kernel lines | not achieved | +1,299, then more |
| 34 | `(* , /)` decoder; moment-difference solvers; rotating shift; certified transfer laws; `:metric` keyword on the entry points | P (on this branch) | `start-synthesis` (`synthesize.lisp:155`) has no `:metric` key |
| 35 | Stage B pullback for code edits | P | found to have no single decoder (audit §4.4) |
| 36 | Bipartite set matching as a metric (App. B.2) | P | |
| 37 | `(:fix-seq fuel init step)` (App. B.3) | P | only a totality fixture, `tests/totality.lisp:168` |
| 38 | Branch closing by monotone full-path price; marginal stopping (App. C.1) | P | |
| 39 | Totality: multi-step tail, per-slot measures, integer descent and ascent, closed redexes (App. C.2) | B | `ast.lisp:1009-1023` |
| 40 | Contrastive descriptor synthesis over confusion classes (App. C.3) | P | found unreachable (audit §11.4) |
| 41 | Variable-compute address decoding: escalate descriptor tiers only on ambiguity (App. C.4) | P | |
| 42 | Latent world model: prediction contracts, latent capacity price, latent-hole decoders, hindsight fibres, Viterbi alternation | P, cut from the document | only in `2b8a912` |
| 43 | Active intervention and disambiguating query selection | P | |
| 44 | Frame views as object-language values behind a firewall on row keys | P | |

### 4.2 From plan9.md and plan9-audit.md

| # | Mechanism | Status | Numbers / location |
| :-- | :-- | :-- | :-- |
| 45 | Totality as a least fixed point; undefined callee not total, primitives kept | B | ledger fingerprint byte-identical; `knowledge.lisp:514`; `tests/audit.lisp:432`, `:468` |
| 46 | Persisted nogood schema zipped only for pointwise maps | B | `nogoods.lisp:283` |
| 47 | Relation consolidation skips member tables; failed fits memoized | B | 100,000 work per call saved; `relations.lisp:11` |
| 48 | One-call consolidation fixed point (hooks, retype, lift in a bounded loop) | B | `consolidate.lisp:964` |
| 49 | Parallel packet field; replay AST reuse | B | `decompose.lisp:34`; `laws.lisp:1292` |
| 50 | Solver induction from empirical fibres over a probe grid | B in spec-driven form; probe grid P | `consolidate.lisp:1512` |
| 51 | Solvers read off laws; uniqueness from involution or cancellation | B | `consolidate.lisp:1581` |
| 52 | Finite-set propagation (at most 8 members) | B | `laws.lisp:643-678` |
| 53 | Propagator dispatch indexed by operator and positions | B | `laws.lisp:664-668` |
| 54 | Dependency repair on pure projections | B | `synthesize.lisp:527` |
| 55 | Learned residual around the analytical price, six features, clamped | B | `consolidate.lisp:20`, `synthesize.lisp:489` |
| 56 | Follower-safe incumbent filtering; soft priority parking; marginal stopping | P | zero hits for `work-at-last-improvement` |
| 57 | Logarithmic search tariff | P | zero hits; correct form per audit: `ceil(log2(1 + W + N))` |
| 58 | Yield-gated Stage A budget | S | refuted by replay (audit App. C) |
| 59 | Deferring fallback siblings | S | refuted by a test |
| 60 | Fallback-free complete-fibre narrowing on `:int`; list-valued witnesses; inequality propagation | S | |
| 61 | `+` served as a library chart | S | Guardrail 3 |
| 62 | Branch closing with a grace step | S | replaced by item 56 |
| 63 | Two-combinator pipeline lift | S | restates existing code (audit §11.6) |
| 64 | Tuple-valued locality keys; `:partition` versus `:coordinate` distance | P | switching distance widened the window from 59 to 106 pairs (audit §8.6) |
| 65 | Three-stage descriptor scoring; memoized contrastive separators | P | |
| 66 | `:sort-by`, `:insert-by`, opt-in bipartite metric | P | zero hits |
| 67 | `propose-disambiguating-query` | P | zero hits |
| 68 | Trajectory-screened latent synthesis | P | zero hits |
| 69 | Replay of a control change on recorded runs before building it (audit method) | BM as a method | `experiments/yield-gate.lisp` |

### 4.3 From plan-exec.md and batteries-and-reflection.md

| # | Mechanism | Status | Numbers / location |
| :-- | :-- | :-- | :-- |
| 70 | Exact closures with a single `:settle` instruction | BM | 4.0× batch, 1.9× unit dispatch; `vm.lisp:439`, `:530` |
| 71 | Symbol metadata on property lists; one type walk fewer | BM | 1.83 s to 1.18 s alone |
| 72 | Ledger fingerprint as a zero-drift gate | BM | 415,539,255 units; `experiments/ledger-fingerprint.lisp` |
| 73 | Closures for defined-function calls; host `compile` for hot entries | P | |
| 74 | Heterogeneous tuple projection | B | `ast.lisp:284-298` |
| 75 | `:necessity` obligation | B | `laws.lisp:614` |
| 76 | Type-template instantiation for every kind | B | `templates.lisp:392` |
| 77 | `:spec` entries: tests as library data | B | `consolidate.lisp:1085` |
| 78 | Batteries as `.sexp` packets with `:from-battery` edges | B | loader `consolidate.lisp:1659-1900`; output only under `v2/library/` |
| 79 | Hand-written `batteries.lisp`, `library/*.lisp`, `bootstrap-inverters.lisp`, `filter-map-decompositions` | BR | deleted in `b3af2e6`; knowledge re-entered by hand in the bootstrap script |
| 80 | Message readers and message frames | B, used only by an experiment | `messages.lisp` |
| 81 | Upward conservation, regime and disambiguation messages; job-wide feature pool | P | |
| 82 | Leaf redundancy residuals (learned "do not nest this decoder" patterns) | P | |
| 83 | Four-level scope lattice with promotion by anti-unification across jobs | P | |
| 84 | Depth-1 reflective tower capped at one eighth of job work | P | |
| 85 | Search-pruning laws discovered from traces during the bootstrap | P | |

---

## 5. Recurring problems and the root causes the documents state

1. **Outcomes turn on budget constants, and more budget is not monotonically better.** Probe 5 needed `:heuristic-budget 16000` after P8.1 (plan8 §6.3); after §6.7 it solves at the default in 264,353 work and "passing `:heuristic-budget 16000` … now leaves it unsolved at `1,000,000`" (L296). Arity scaling fixed Probe 2 and regressed Probe 4. The shifted-sequence task is unsolved at the default, 100,050 at 16000, 133,743 at 30000, 205,914 at 60000. Changing one multiplier from 2 to 1, 3, 4 or 7 each breaks a test. Stated causes: Stage A has a fixed budget while the grammar grows with input arity (plan8 §1.2 item 5); metric work is charged to the same budget as enumeration (`charlie:plan9.md` §8.4); "Preparation is linear in the lifts that score alike" (same); a wrong lifted proposal "now spends a quadrupled Stage A budget in full" (plan8 §6.3). Plan8 §6.5 suggests, untried, "A budget that grows only while Stage A is still finding new features"; the audit's replay then showed that this signal also misleads.
2. **Mechanisms are built, tested in isolation, and never wired in.** Five "unwired seams" were listed on 17 Nov (plan9 §1.3) and four are still unwired: row-order induction, address lookup, conserved-quantity orientation, contrastive descriptors. Stated cause: wiring has side effects the search cannot tolerate. `with-induced-row-order` reorders rows, adds a hard edge and registers a library entry, while "Bucket values already computed are in the old row order, and `dependency-expander` and the guard search index them by position" (audit §8.6). The rule adopted, "search proposes and consolidation registers" (audit §8.8), then means "nothing in search consumes an induced key" (audit §11.6).
3. **Host-coded knowledge cannot be re-derived within the budgets tried.** The functor inverters ("a research change, not a cleanup", plan8 §6.6); filter-map ("Templates do not bootstrap", audit §4.6); a 57-bit guard not found in 60,000,000 work (audit §11.4); separators of 75 and 84 bits against 20,000 work. Stated causes: exact enumeration does not reach that size; anti-unification of one entry cannot recover "a relation between two entries"; the probe values are too poor to distinguish candidates (`(0 1)` for integers, ascending sequences only). The outcome was that the knowledge moved from host Lisp into hand-written library data (§3.3), not into discovery.
4. **Every plan promised a smaller kernel and delivered a larger one.** 12,472 → 13,771 → 15,154 → 15,257 → 17,647. Stated cause (plan8 §6.6): the removable lines "are not there to remove"; "Meeting the gate as written would take retiring a whole mechanism".
5. **Scores add quantities of different kinds.** Root-priced program bits plus child-space residual bits; half a "policy score"; 16 bits per coupled requirement; a learned correction; a linkage term that "is not a code length". Consequence named by the audit: "Correct lifts look non-improving".
6. **Evidence on infinite types can only be sampled, so nothing learned there ever eliminates.** "sampled evidence can propose and never eliminates" (plan8 §6.7); every narrowing on `:int` keeps a fallback sibling; a sampled descriptor "never prunes" (audit §6.3). The system's ability to cut the search by what it has learned is confined to finite fields and Booleans.
7. **Information found in a branch is discarded.** "all of that discovered information is thrown away!" (batteries §3.2); "In both tuple probes the root's Stage A ends its budget with no model and no bucket" while children hold the features (audit §4.1); "A job keeps no record of which entries competed" (audit §8.2); "The ledger is keyed by category, not by entry" (audit §4.7).
8. **Work is repeated without being noticed.** The same combinator lifted twice accounted for about a third of a headline figure (`charlie:plan9.md` §8.2); a failed relation fit re-ran at 100,000 work per consolidation; consolidation was not a fixed point despite its docstring; "Unchanged-library consolidation is not free". The owner's prompt names this class: "leaf residuals (such as preventing repeated applications of the same rules ... for which it appears some patches in plan9-audit are instances of)".
9. **Position stands in for identity.** The positional `:seq-delta`; the positional zip of nogood schemas; feature buckets indexed by row position; `rows-pin-values-p` requiring whole values; hard edges that do not survive a pullback because "An edge is a statement about the parent's target values and does not transfer to a child of another type" (plan8 §6.4 item 14).
10. **Unobserved intermediate state has been out of reach throughout.** The partially observed scan reports `rows=3 coupled=2` at every checkpoint from 13 Nov to the last record; plan8 §5.1, plan9 §5.4 and audit §8.10 each restate why.
11. **Plan text drifts from the code within days.** Nonexistent functions, operators that are not operators, stale line ranges, miscounted lists (audit §7); the audit's own unverified suggestion (§11.7).
12. **The agents, not the kernel, did the experiments.** The owner's diagnosis (§3.1 item 5 above) and the agent's restatement (batteries §3.1).

---

## 6. Nuggets for the current lens

### (a) Fibres and bundles, lift, project, pull back, residual calculus

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| Two different things are called "fiber": the set of values a row still allows (preimage), and the set of child occurrences a 1-to-many cover produces (bundle) | plan8 L20–L22 | A graph store must represent both, and they are different edge types: value-set constraints on a node versus fan-out from a node |
| Every mechanism is "shared part plus per-instance part"; they differ only in where the search is | plan8 §2.1 | The closest existing statement of a uniform calculus; a candidate schema for a single edge kind |
| Anti-unification gives point substitutions because constructors are injective; synthesis gives set-valued fibres because primitives are many-to-one | plan8 L19, L21 | Injectivity of an operator is the property that decides whether an inverse edge is a function or a relation; it could be learned per operator rather than assumed |
| Motif I: projection, pullback/lift, narrowing, separation over the "input-requirement bundle" | plan9 §2.1 | The four operations the owner asks to be first-class; today each is a host function over `frame` |
| A solver has three obligations, `:witness`, `:uniqueness`, `:necessity`, and the third turns a failed guard into a proof that the fibre is empty | batteries §2.1; `laws.lisp:614` | A complete, already-built description of an invertible edge with its domain; the guard is the learned partition |
| Bindings are strictly single-row; context across rows enters "**exclusively** through composable higher-order combinator lifts" | plan8 §3.4.1 (L133) | The one rule that keeps composed models self-contained; any graph design needs an equivalent of it |
| A metric survives a pullback in four cases; otherwise "a metric of two values cannot state" a price that depends on the row | `frame.lisp:508-518` | The exact reason residual pricing in an induced space fails today: the induced distance is a function of the base point, and the representation has no place for that |
| A product is an AND-join of sibling nodes; a requirement tying slots together stays on the join and is checked there | plan8 §6.4 item 1, §6.7 | An existing instance of a hyperedge (one join, many slots) with a residual constraint attached |
| An unconstrained latent slot "returns the smallest programs at once" | audit §8.10 | Pooling candidates per slot cannot find latent state; the constraint must come from rolling the composed step forward |
| "The regime is a property of the decoder, not the schema" | audit §8.10 | Whether a step sees its own past output is a property of which lift was used, that is, of the topology, not of column metadata |

### (b) Learning dependency structure by experiment and intervention

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| Solver discovery as an experiment: evaluate over a probe grid, group by context into empirical fibres, synthesize a witness, then find the guard by splitting contexts where replay holds from those where it "fails/errors" | plan9 §3.1 (L146–L148) | The owner's "holding all but a few constant" already written down as a procedure, including guards learned from failures |
| `target-sensitive-p`: accept an invariant only if perturbing the target changes it on some row | plan8 §3.3; `laws.lisp:892` | A built intervention test for "does this depend on that" |
| `metric-invariant-under-decoder-p`: replay to test whether a distance is unchanged under a decoder | `frame.lisp:468` | A built experimental symmetry test; the same shape would test any claimed invariance |
| Probes are too poor: `(0 1)` on integers, nothing on sequences or tuples, ascending sequences only; "Empirical fibers are cut off by the probe box" | audit §8.3, §6.3 | Experiment design (which inputs to try) is the missing piece, and it was host-coded |
| Disambiguating queries: find an input on which two surviving candidates differ; only exact search can pose it, since the requirement is not a membership | plan8 §5.3; plan9 §5.3; audit §8.9 | Active experimentation was proposed three times and never built |
| The audit's own method: one edit to a scratch copy, run, record the first failure; or replay recorded runs under a changed rule | audit §2, App. A, App. C | This is intervention on the kernel, done by an agent; `experiments/yield-gate.lisp` shows it can be expressed in the kernel's own terms |
| **OWNER**: "testing is also a way of better knowing what you know" | batteries L7 | `:spec` entries make experiments replayable library data |

### (c) Law discovery; conservation to generation

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| Numeric per-row inversion of a conservation "merely reproduces the starting frame" when targets are already single values; reorientation only helps if done on the expression | plan8 §1.2 item 4 | Reorientation must act on the structure (the edge), not on the rows |
| `solve-equality-symbolically` derives the index map of `reverse` from `I + j - (n-1) = 0` | plan8 §6.3; `laws.lisp:809` | A working example of conservation turned into a generator |
| Invariant discovery and reorientation both exist and are not connected | this audit, §1.3 | The loop the owner describes is two calls apart and has been for a week |
| A left-inverse law proves a witness, not uniqueness; an unguarded involution proves both; a dual cancellation law proves uniqueness | plan9 §3.2 | Precise rules for which orientation of a law yields which kind of edge |
| "A solver's `:unique-p` is a claim"; "Replay licenses a proposal; a recorded law needs evidence" | plan8 §6.7 | The discipline separating what may be searched from what may prune |
| Motifs are empirical: premises may be certified, "the step from them to the transferred law is not" | audit §11.3 item 4 | Any algebra-discovery layer needs its own evidence grade for transfers |
| Solvers over GF(5) and GF(7) that read alike lift to integer conjectures; truncating division does not | plan8 §6.6; `tests/topology.lisp:241`, `:356` | Small exhaustive domains as the laboratory, integers as the conjecture; a concrete bootstrapping route for laws |
| Simplifying before unwinding "can move the target into two argument positions" | audit §8.5 | Rewriting and solving interfere; keep both forms |

### (d) Graphs, hypergraphs, edges as the store

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| "True graph topology enters only with **unaligned correspondence** … and **cross-row linkage**" | plan8 L23 | An agent's own statement of where the table model ends |
| The frame carries three separate linkage slots (`pairs`, `anchors`, `edges`), none produced by the kernel's own search except through an unwired path | `frame.lisp:12-24`; §1.3 above | Evidence for the owner's doubt: relations between rows were bolted on and stayed inert |
| The knowledge library is already an edge-labelled graph: edges `:metric-decoder`, `:associative`, `:identity`, `:lifted-from`, `:induced-by`, `:retyped-from`, `:inverts`, `:describes`, `:relates`, `:from-battery`, `:specifies`. The motif hook pattern-matches stars of them | plan8 §6.6; `consolidate.lisp:833` | The one place where graph structure among learned objects is used to learn more |
| "there is no `:depends-on` edge in the kernel to follow", so live callers are found by scanning code; "Nothing downstream uses a closure edge" | plan8 §6.6 item 23; audit §5 item 5 | The dependency graph is implicit in ASTs; making it explicit is cheap and currently missing |
| "The ledger is keyed by category, not by entry", so work cannot be attributed to a rule | audit §4.7 | Reflection needs cost on edges, not in bins |
| The closure cache is "keyed by node identity"; metadata on conses lives in a locked weak table that is 19% of suite time | audit §11.5; plan-exec §5 | AST identity and metadata are already a performance problem; a store with canonical, shared nodes addresses both |
| Graph data inside the object language is `(:seq (:tuple …))` with positional pricing; traversal needs a fuel-bounded combinator | plan8 App. B | The object language has no native graph value |
| Canonical nodes with followers: one search serves several nodes whose scopes coincide, and a bound must cover "the loosest follower" | audit §4.5 | The search is already a DAG with sharing; pruning rules must be stated on the shared node |

### (e) Geometry: metrics, spaces, ambient versus induced pricing

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| "Heuristic condensation is **coordinate-chart induction**" | plan8 §3.1 (L105) | The existing bridge between the two halves of the owner's kernel: a chart is found by search, then used as a pullback |
| A decoder plus a solver for its delta is one object serving as both a distance and a change of space | plan8 §3.1 | A generated space is created by a library entry; this is "making spaces where residuals require" in embryo |
| "A metric decoder taxes every search of its type"; one evaluation cost 3,334 work | `charlie:plan9.md` §8.4; audit App. B | Generated geometries are not free; some retrieval or gating by cheap evidence must come first (the shift solver was given a guard "by what a shift must look like") |
| Programs are priced at the root, residuals in the node's own space | `synthesize.lisp:394`; audit §4.5 | The ambient-versus-induced question is already answered inconsistently in the code |
| Row-order induction tests a 1-D geometry against two baselines, independent and star: "Without the star, targets that are merely alike in no order induced a spurious key" | plan8 §6.4 item 16 | A clean description-length test for whether an induced space is real |
| Discrete class labels and coordinates need different distances; using the absolute difference of keys on parity labels widened the window from 59 to 106 pairs | plan9 §2.2.2; audit §8.6 | "Partition" and "coordinate" are different kinds of space and must be typed as such |
| Three spaces, each with observed and generated geometry: targets, rows, library concepts | plan9 §2.2 | A ready inventory of where a geometric component would attach |
| A zero-cost permutation conflicts with "0 iff equal" and the one-bit clamp | audit §8.8 | Quotient spaces (sets, orbits) cannot be priced by a metric on representatives; the space itself must be collapsed |
| Latent channel capacity `C_cap` charged per step so a latent cannot copy the next observation | plan8 first version §4.2 | A pricing rule for created spaces that was designed and dropped |
| Address decoding by executable predicates takes variable work, unlike constant-work vector retrieval | plan8 App. C.4 (L562–L565) | The only passage that contrasts symbolic addressing with flat embeddings |

### (f) Learned heuristics and policies

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| The learned priority is a regression over six hand-chosen node features, synthesized by the kernel's own Stage A, added to the analytical price and clamped to [−24, +48] | plan9 §4.2; `consolidate.lisp:20`; `synthesize.lisp:489` | The whole of "learned policy" in the kernel today; its target was first a "synthetic formula" that replaced the price |
| "A node's priority is an estimate, not a lower bound; the only true bounds are enumeration frontiers" | audit §4.5 | What a learned heuristic may and may not be used for |
| The yield gate, plausible on paper, stops the winning node five quanta early | audit §4.1, App. C | A policy must be tested on recorded searches; the features (score, buckets) did not separate needed from spent searches |
| Net-utility archiving: "The exchange rate is a free parameter"; a per-lift log overcharges cheap failures; one log of total work plus count is scale-free | plan8 §6.6 item 24; audit §4.7, §11.3 | The cost model for keeping or dropping a learned object is undecided and sensitive |
| Policy descriptors only move integer weights by ±1 | plan8 App. C.3; `consolidate.lisp:382` | No new discriminating feature is ever synthesized |
| Tariff messages: pace by "information yield per candidate" | batteries §3.2 item 4 | A proposed feature for a learned controller, unbuilt |

### (g) Language

These five documents contain almost nothing on the language component. The only relevant items: the compositional name is "a rigid 5-slot keyword symbol" and a learned separator "has no slot in the five-token address" (plan8 App. C.4; audit §8.2); descriptors are executable predicates used as address tokens; a library trigger is proposed as the least general generalization of frame descriptors (batteries §3.3 table, L2 row). None is compositional in the owner's sense.

### (h) Reflection and reentrancy

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| **OWNER**: reentrancy means "the search process of the kernel itself produces data that bootstraps rules and complexity for further search" | batteries L11 | The definition to design against |
| The nogood is "the *only* upward symbolic channel"; four more message classes are proposed | batteries §3.2 | A concrete list of what the search graph should carry |
| A scope lattice separating what a rule depends on from how well it is established | batteries §3.3 | An answer to the owner's "scoping" problem; untested |
| `messages.lisp` and `experiments/yield-gate.lisp` | code | The reflective loop exists end to end once, offline, at zero cost to the job's ledger |
| "search proposes and consolidation registers" | audit §8.8 | The current barrier between search and library; mid-search absorption (L0, L1) would have to breach it deliberately |
| Every mechanism must give identical results stepped 1 unit or 97 units at a time | plan9 §7 invariant 2 | Any reflective step has to be a metered, resumable action |
| Reifying frame views as object-language values behind a firewall on row keys | plan8 §5 item 5 | An early note that the candidate program must not see the data structure's identity fields |

### (i) Totality, crashes, learned guards

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| "`provably-total-p` does **not** limit which functions can execute in the VM (arbitrary general recursion still runs under `row-budget`); rather, it guards **sound compile-time and pullback rewrites**" | plan8 App. C.2 (L537) | The VM already tolerates non-termination; totality is needed only where a rewrite would otherwise change meaning |
| Totality was unsound for a week: a mutually recursive diverging pair was marked total | audit §9 item 1 | A static import can itself be wrong; it must be a least fixed point |
| Hoisting a shared binding into a call-by-value position can introduce an error that a lazy conditional avoided; the quoted body must be total by itself | plan8 §3.2 item 1, §6.4 item 6 | Sharing (a topological rewrite) interacts with definedness |
| A row that errors was skipped, so a descriptor that errors on two of three rows "came back satisfied" | audit §8.2 | Errors must be values in the evidence, not gaps |
| Solver certification and law validation "treat a forward error differently (not a solution vs. a refutation)" | plan8 §6.6 | Two meanings of a crash already coexist |
| Guards induced from where a witness fails to replay; a synthesized divisibility guard `(= (* (/ c k) k) c)` "sharper than hand-written `(not (= k 0))`" | plan9 §3.1; batteries §2.2 table | Learned guards from experiment, the owner's requirement, with one claimed success |
| That same guard at 57 bits is not found by exact search in 60,000,000 work | audit §11.4 | Guards of realistic size need a decomposed route, not enumeration |
| Totality under a guard (`provably-total-given-p`) | `laws.lisp:1270` | Conditional totality is already a notion in the code |

### (j) Budgets, lowering, compilation

| Nugget | Location | Why it matters now |
| :-- | :-- | :-- |
| Default budgets: Stage A 2,000 work; condensation 20,000; depth 2; guard bound about 18–22 bits beyond the header; spec synthesis 350,000 | `synthesize.lisp:157`; `decompose.lisp:676`, `:538-541`; `consolidate.lisp:1209` | These are milliseconds to a fraction of a second at the measured rate |
| About 65 million work units per second after closures (my arithmetic) | plan-exec L15, L66 | Every "unreachable" verdict in these documents was reached within roughly a second of compute |
| Exact closures give 4× with identical ledgers; the remaining cost is metadata lookup and per-unit stepping | plan-exec §1, §5 | The metered VM is not the bottleneck; the AST store and the scheduler are |
| Calls of defined functions are not compiled, and they are what dominates metric evaluation | plan-exec §3, §5; audit App. B | Library-heavy search, the kind the owner wants, runs on the slow path |
| "Host `compile` for hot entries was not built. Nothing measured needs it." | plan-exec §4 | True only at the budgets measured |
| More budget can make a task fail (Probe 5 at 16000) | plan8 §6.7 | Hours of search need a scheduler in which extra budget cannot hurt |
| If enumeration cost roughly doubles per bit of program, an hour buys about 12 bits over the largest search tried (my inference, from 2^12 ≈ 3,900) | derived | Long budgets alone do not reach 75–84-bit objects; reuse, decomposition and learned pruning must supply the rest |

---

## 7. Contradictions

### 7.1 Within and between the documents

1. **Probe 5 and its budget.** plan8 §6.3 and §6.5 say it needs `:heuristic-budget 16000`; §6.7 says it solves at the default and that 16000 "now leaves it unsolved at `1,000,000`". §6.3 and §6.5 were not rewritten.
2. **Same baseline, two numbers.** Probe 2 "before" is 158,433 in plan8 §1.3 (L53) and 158,461 in §6.3 (L209).
3. **Bucket-pair guards first or last.** plan8 §3.2 item 3 says pair buckets "Before running `observed-predicates`"; §6.4 item 5 records that pairs-first broke the inductive sequence lift, so the grammar runs first.
4. **"Replace positional pairs/anchors".** plan8 §3.4.1 versus §6.1: they "were already keyed by `row-key`"; the plan "overstated the problem".
5. **Removable lines.** plan8 §2.2 "~800–1,050 Kernel LOC Removable" versus §6.6 "not there to remove".
6. **Lifted solvers.** plan8 §6.6 "neither certified nor unique" versus §6.7 "a lifted `+` is tested unique".
7. **Which Stage A scaling Plan 9 preserves.** plan9 Guardrail 1 cites "the lifted-only … multipliers from `plan8.md` §6.4.7", which plan8 §6.7 had superseded ("covers every node inside a lifted branch").
8. **The schema-zip gate.** plan9 §1.2 item 2 gates on `function-body-length-preserving-p` at `abstraction.lisp:247`; audit §11.7 says the function is at `descriptors.lisp:73` and the gate "is too loose"; the code uses `pointwise-map-decoder-p` (`nogoods.lisp:283`).
9. **Defect or scope.** plan9 §1.2 item 5 lists unlifted templates as a defect; audit §11.7 item 2 calls it "a documented limit of scope".
10. **Undefined callees.** plan9 §1.2 item 1 "must require `def` to be present"; audit §11.3 item 1: that breaks every primitive.
11. **Transfer laws.** plan9 §2.2.1 item 5 attests motif transfers `:derived`; audit §11.3 item 4: unsound.
12. **The Levin formula.** plan9 §4.3 item 3 puts the count outside the logarithm; audit §11.3 item 3 shows this reproduces the overcharge it was meant to remove.
13. **Guard search.** plan9 §3.1 step 3 uses exact search at "header + 56" within a 40,000-work routine; audit §11.4: the example guard is 57 bits and is not found in 60,000,000.
14. **Increment count.** plan9 §6 heading says "`P9.1` – `P9.6`"; the table has P9.1, P9.2, P9.3a, P9.3b, P9.4, P9.5.
15. **Where solver discovery lives.** P8.4 moved the discovery harness out of the kernel to save lines; Plan 9 §3.1 and the batteries work moved solver induction back in (audit §4.6 notes it; `consolidate.lisp` is now 2,118 lines).
16. **Where the shift metric lives.** plan9 §3.2 and invariant 1: to `tests/support.lisp`; `charlie:plan9.md` §8.3: "went to `library/sequence-shift.lisp`"; today: `bootstrap/build-batteries.lisp` and a `.sexp` under `v2/`.
17. **Unify or keep apart.** plan8 §1.1 adopts "Unify the data model and agenda; keep the inner matching and search engines distinct" on the authority of a document that is not in the repository. The owner's current request is for one kernel in which substitution, anti-unification, lift and the rest are uniform operations. The plan of record took the conservative side of that question without the argument being available.

### 7.2 Between the documents and the current code

1. **"Zero host AST builders" / "Zero-Hand-Coding Bootstrap"** (batteries L83, L101) versus `bootstrap/build-batteries.lisp`, which builds nine of ten functor transformers and the filter-map template by hand (§3.3).
2. **"starts with `(make-knowledge-library)` (completely empty!)"** (batteries L101) versus trusted axioms and validated entries inserted by the script.
3. **Guardrail 4, "Build & benchmark learned replacements *before* retiring host builders"** (plan9 L69) versus the retirement of 18 Nov, which replaced host builders with hand-written library entries, not learned ones.
4. **Six promised battery files including `metrics.sexp`** (batteries §2.2, figure) versus eight actual files, none of them in the root tree.
5. **Kernel regression gate that regenerates batteries inside `make test`** (batteries L103) versus a `Makefile` in which `test` does not invoke `bootstrap`, and a root tree with no `library/`.
6. **`mod` "Not operators"** (audit §7) versus `:mod` now in `+primitives+` (`ast.lisp`, last row).
7. **Citations of `bootstrap-inverters.lisp`, `filter-map-decompositions`, `install-sequence-shift-metric`** in plan8, plan9 and the audit: all GONE from the kernel.
8. **Every file:line in all five documents is stale** against the current tree. Examples: `pulled-back-metric` cited at `frame.lisp:448-526`, now `:508`; `induce-row-order` cited at `proposals.lisp:798` and `:853`, now `:707`; `orient-conserved-quantity` cited at `laws.lisp:850`, now `:931`.
9. **The unwired seams of plan9 §1.3** are described as about to be wired; four of five remain unwired.
10. **`*max-eager-proposals-per-node*`** is described as a delivered P8.2 control; it is defined and left `nil`.

---

## 8. Verification summary

| Item | Tag | Where |
| :-- | :-- | :-- |
| Frame metric, priced correction, code edit, correction packets | STILL-IN-CODE | `frame.lisp:19`, `:1533`, `:1583`, `:1645`, `:1675`, `:1719` |
| Metric pullback and replay invariance | STILL-IN-CODE | `frame.lisp:468`, `:508` |
| Metric decoders, delta, registration | STILL-IN-CODE | `laws.lisp:1250`, `:1277`, `:1314` |
| Additive and metric residual decompositions | STILL-IN-CODE | `decompose.lisp:13`, `:30` |
| `:shift-seq`, `:argmax-corr`, `:best-shift` | GONE from kernel | `bootstrap/build-batteries.lisp:827-949`; `tests/support.lisp:545` |
| Frame edges, hard-edge checks | STILL-IN-CODE | `frame.lisp:20-24`; `enumerate.lisp:449`, `:459` |
| `:recurrence` edges | NEVER-BUILT | |
| `orient-conserved-quantity`, `solve-equality-symbolically`, `target-sensitive-p` | TEST-ONLY | `laws.lisp:931`, `:809`, `:892` |
| `induce-row-order`, `with-induced-row-order`, `:locality-key`, `projection-row-keys` | TEST-ONLY | `proposals.lisp:707`, `:789`, `:625`, `:675` |
| `frame-addressed-entries`, `probe-frame-coordinates`, `au-substitutions-frame` | TEST-ONLY | `descriptors.lisp:945`; `frame.lisp:1108`; `unify.lisp:75` |
| Availability preorder | STILL-IN-CODE, live | `ast.lisp:338-368`; `frame.lisp:1365`, `:1380` |
| Observed invariants | STILL-IN-CODE; not linked to orientation | `enumerate.lisp:728`; reader `descriptors.lisp:521` |
| Motifs, field-solver lifting, archiving | STILL-IN-CODE | `consolidate.lisp:833`, `:951`, `:603`, `:466` |
| Let-sharing, product slots, coupled join, component bindings, bucket-pair guards | STILL-IN-CODE | `frame.lisp:674`, `:710`, `:768`, `:582`, `:868`; `synthesize.lisp:636`; `proposals.lisp:388`; `decompose.lisp:187` |
| Stage A budget rule | STILL-IN-CODE | `synthesize.lisp:373` |
| `filter-map-decompositions`, `bootstrap-inverters.lisp`, `batteries.lisp`, `library/*.lisp` | GONE | deleted in `b3af2e6` |
| Plan 9 fixes (totality, schema zip, relations, consolidation loop, packets) | STILL-IN-CODE | `knowledge.lisp:514`; `nogoods.lisp:283`; `relations.lisp:11`; `consolidate.lisp:964`; `decompose.lisp:34` |
| `induce-conditional-solvers`, `induce-law-solvers`, `:necessity` | STILL-IN-CODE | `consolidate.lisp:1512`, `:1581`; `laws.lisp:614` |
| `solver-probe-values-for-type`, `propose-disambiguating-query`, `:sort-by`, `:insert-by`, bipartite matching, `trajectory-admissible-p`, `work-at-last-improvement`, `:marginal-search-weight`, Levin tariff | NEVER-BUILT | zero hits |
| `:fix-seq` | NEVER-BUILT as library or kernel code | fixture only, `tests/totality.lisp:168-186` |
| Exact closures | STILL-IN-CODE | `vm.lisp:87`, `:421`, `:439`, `:530` |
| Heterogeneous `:at`, `instantiate-entry-template`, `:spec`, battery loader | STILL-IN-CODE | `ast.lisp:284-298`; `templates.lisp:392`; `consolidate.lisp:1085`, `:1659-1900` |
| Root `library/*.sexp` | not present, never tracked | copy at `v2/library/` |
| Message readers and frames | STILL-IN-CODE; consumed only by `experiments/yield-gate.lisp` and tests | `messages.lisp` |
| `reify-search-frame`, `*reflective-depth*`, `:conserved`, `:regime-hit`, `:reflect`, L0–L3 scopes, job-wide feature pool | NEVER-BUILT | zero hits |
| Lift, projection, pullback, fibre as VM primitives | NEVER-BUILT | `+primitives+` in `ast.lisp` has code substitution and matching only; `lift-frame` is host code at `frame.lisp:1194` |

Not verified: no test, probe, benchmark or bootstrap was run, so every work figure in this report is as reported by the documents. The statement that battery-dependent root tests cannot pass without first running `make bootstrap` is inferred from reading the loader and the `Makefile`.
