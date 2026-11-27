# `lisploop` — Audit of Plan 9

> **Status:** Audit of `plan9.md` (v1.0) against the Common Lisp kernel on branch `charlie` at commit `019736f`, 17 November 2026.
> The Lisp source is the reference. `plan8.md` §6 is used as the record of what the Plan 8 refactor and its audit decided.
> Plan 9 is cited by section ("plan §4.2"), since its line numbers move with formatting. Source is cited as `file:line` at `019736f`.
> §11 is a later follow-up: a review of `plan9.md` v2.0 against the kernel at `fafffd9`. It also corrects three statements in the sections before it.

---

## 1. Summary

The baseline in Plan 9 is accurate, but much of what it builds on that baseline is not. Three of the five "latent bugs" in plan §1.2 are misdiagnosed, several cited functions do not exist, and a number of the proposals would break behaviour that works today or reverse decisions recorded in `plan8.md` §6.7.

The main conclusions:

- **The yield-gated Stage A budget (plan §4.2) cuts the wrong nodes.** Replayed on today's runs, it stops the node that solves the conditional tuple scan five quanta before its exact model, and lets dead lifts run to quantum 7.
- **Deferring fallback clones (plan §3.3.3) reverses a Plan 8 audit fix** and fails the test written for that fix.
- **Complete-fiber propagation "without fallback" (plan §3.3.1) contradicts the evidence rule on `:int`**, where completeness can only ever be sampled.
- **Three gates are already met or cannot be met by the listed mechanisms.** The default-budget `tests/metrics.lisp` gate is the clearest: the work it needs is VM execution that the plan keeps metered.
- **The two retirements (`bootstrap-inverters.lisp`, `filter-map-decompositions`) rest on search capability that has not been shown**, and their gate sits in a phase before the work it depends on.
- **The totality analysis has an existing soundness bug** that the plan does not mention and that plan §5.1 would build on.

## 2. Method

What was read: `plan9.md`, `plan8.md` in full, and the kernel sources the plan cites (`frame.lisp`, `nogoods.lisp`, `condense.lisp`, `decompose.lisp`, `synthesize.lisp`, `laws.lisp`, `vm.lisp`, `evidence.lisp`, `templates.lisp`, `bootstrap-inverters.lisp`, `relations.lisp`, and the cited parts of `ast.lisp`, `consolidate.lisp`, `proposals.lisp`, `descriptors.lisp`, `enumerate.lisp`, `abstraction.lisp`, `knowledge.lisp`, `milestones/corpus.lisp`).

What was run:

- The kernel and milestone suites, and the probes of `plan8.md` Appendix A.
- One-edit experiments: a single change applied to a scratch copy of the kernel, then `sbcl --script tests/run.lisp kernel`. The runner stops at the first failing test, so each result names only the first failure (Appendix A).
- Measurement scripts for the shifted-sequence task (Appendix B) and a replay of the proposed yield gate (Appendix C).
- Small reproduction scripts for individual claims about totality, descriptors, relations and consolidation.

Findings are tagged **(ran)** when a script was executed and **(read)** when they come from reading the code. Nothing in the repository was modified; the scripts lived in a temporary directory and are not part of the repo. The appendices give enough to redo the main ones.

## 3. What Checks Out

- **Baseline (ran).** 25 kernel modules, `15,157` LOC; `1,585` milestone LOC; `182` kernel tests / `418,400` checks; `40` milestone tests / `186,771` checks.
- **Probe figures (ran).** Symmetric tuple scan `112,979` work; conditional tuple scan `264,353`; irrelevant-input scan `34,067`; partially observed accumulator `rows=3 coupled=2`.
- **Unwired seams (plan §1.3).** All as stated:
  - `induce-row-order` and `with-induced-row-order` are called only from the topology tests.
  - `frame-addressed-entries` has no caller in `proposals.lisp`, nor does the address lookup it wraps.
  - `orient-conserved-quantity` has no kernel caller.
  - `install-sequence-shift-metric` has no kernel caller.
  - `consolidate-policy-descriptors` adjusts weights by one and synthesises nothing.
- **Line references.** Current for `laws.lisp`, `synthesize.lisp`, `consolidate.lisp`, `decompose.lisp`, `nogoods.lisp`, `evidence.lisp`, `templates.lisp:247-272` and most of `proposals.lisp`. Stale for most of `frame.lisp` and for `ast.lisp` (§7).
- **`plan8.md:287` and `plan8.md:274`** say what the plan says they say. Note that `plan8.md:287` adds that both retirements "change search behaviour and budgets".

---

## 4. Proposals That Would Break Working Behaviour

### 4.1 Yield-gated Stage A budget (plan §4.2)

The plan replaces the fixed multiplier with quanta of the base budget, continuing only while a quantum improves the best score or adds feature buckets. It claims that dead lifts then abort after one quantum and that the conditional tuple probes "scale smoothly".

**The gate cuts live nodes and spares dead ones (ran, Appendix C).** Today's Stage A runs were replayed in quanta of `2,000` with the gate applied at $\eta_{\min} = 1$, without changing the search.

- On the conditional tuple scan, the winning Stage B node reaches its exact model in quantum 8. Its bucket counts per quantum are `4 5 5 5 8 8 11 13`. Quantum 3 adds no bucket and improves no score, so the gate stops there.
- The sibling slot whose guard needs the late features is cut at the same point. `plan8.md` §6.3 already records that this slot needs about `16,000`–`20,000` work to reach the two features its guard compares.
- On the symmetric tuple scan, the two dead arity-3 lifts grow buckets steadily (`2 4 6 8 10 11`) and are stopped only at quantum 7. That saves about `4,000` of `18,076` each.
- The plan's extra qualifier on condition (b), "while enumeration is still in low-size tiers", can only stop a node earlier.

**Zero yield in the first quantum is normal for expensive candidates (ran, Appendix B).** On the shifted-sequence task Stage A has no model at all after `8,000` work, because pricing one candidate under the metric decoder costs more than that.

**The root often yields nothing (ran).** In both tuple probes the root's Stage A ends its budget with no model and no bucket.

**The suite is tuned to the current multiplier (ran, Appendix A).** Changing the `2` at `synthesize.lisp:377` to `1`, `3`, `4` or `7` each breaks a test.

**The ceilings move in both directions (read).**

| Inputs | Lifted node today | Plan ceiling |
| :-- | :-- | :-- |
| 1 | $2\times$ | $1\times$ |
| 2 | $2\times$ | $4\times$ |
| 3 | $8\times$ | $9\times$ |
| 4 | $18\times$ | $16\times$ |
| 5 | $32\times$ | $16\times$ |

- The $\times 2$ for the child of a recursive definition is dropped.
- The ceiling applies to "both lifted and multi-input frames". `plan8.md` §6.4.7 records that scaling every node broke `recursion-r4-insert-and-sort-synthesis` and Probe 5.
- The plan's description of today's rule ("by 1 outside lifted branches") omits the recursive-child $\times 2$.

**Ambiguity (read).** Stage A stops at an exact model only in lifted branches and recursive children (`synthesize.lisp:397`). If "stop immediately on exact hit" means every node, fewer buckets reach the guard pairing and the row-order keys.

### 4.2 Deferring fallback clones (plan §3.3.3)

The plan queues ambiguous-narrowing fallbacks on `synthesis-node-deferred-proposals` instead of adding them as nodes.

- **It reverses a recorded fix.** `plan8.md` §6.7: "the reserve turn reaches unprepared fallback siblings ... without it an ambiguous tentative narrowing was never rescued (unsolved at `3,000,000` work, solved at `367,081` with it)."
- **The test for that fix fails (ran).** With `add-fallback-sibling` pushing onto the parent's deferred list, `an-ambiguous-narrowing-is-rescued-by-its-fallback` fails.
- **The queue is already long (read).** Partial-application and learned-template proposals are themselves fallbacks (`proposals.lisp:1093`, `:1319`), and there can be 256 of them. A narrowing fallback is created later, at the narrowed node's preparation, so it would land behind them.
- **`:fallback-p` carries two meanings (read).** It defers a proposal, and `node-library` gives a fallback no propagators (`synthesize.lisp:467-474`).
- **The stated cost is wrong (read).** The reserve is one turn in four rotated over every open action (`synthesize.lisp:934-937`), so an unprepared fallback gets one turn in four times the number of actions, not 25% of turns.

### 4.3 Complete fibers and set propagation without fallback (plan §3.3.1, §3.3.2)

- **The evidence rule forbids it on `:int` (read).** A narrowing drops the original frame only on current evidence, which is `:exhaustive`, `:derived` or `:trusted-axiom` (`evidence.lisp:51-59`, `laws.lisp:680-723`). `certify-solver-entry` checks finite types only, up to `65,536` cases (`laws.lisp:1069-1073`). Completeness of `abs` or `sq` over `:int` can therefore only be `:sampled`, and sampled evidence keeps its fallback (`plan8.md` §6.7; the plan's own invariant 3).
- **The headline examples are on `:int`.** `(= (abs Z) '5)` and `(and (< '0 Z) (= (* Z Z) '9))` cannot narrow "with zero fallback" under that rule. On a prime field the mechanism is sound.
- **No "necessary guard" obligation exists (read).** A solver's obligations are `:witness` and `:uniqueness` (`laws.lisp:1067`). Refuting an infeasible member "under a certified-necessary guard" needs a new obligation and a new exhaustive check.
- **A list-valued witness fails validation (read).** `validate-solver-shape` asserts that the witness has the unknown's type (`laws.lisp:1049-1052`). Every solver consumer would have to tell the two kinds apart: `solve-equality-symbolically`, `metric-delta`, `certify-solver-entry`, `sampled-solver-validations`, `lift-field-solvers` and the functor inverters. The plan names only `propagate-requirements`.

### 4.4 Serving `+` through the chart protocol (plan §2.2.1)

- **Metered cost (read).** Today the integer delta is a host subtraction in `correction` (`frame.lisp:1494`), and a witness priced with no VM work skips the `:witness` phase (`condense.lisp:221-224`). Through `metric-delta` every missed row runs a solver and a replay in the VM. Given §4.1's sensitivity, that moves every integer task.
- **"Built-in default" is host code (read).** A clean library is empty (`tests/support.lisp:19-23`). `tests/metrics.lisp:168` checks `(null (metric-decoders :int))`.
- **The additive path does more than add (read).** `make-additive-residual-decoder` expands tuples slot by slot, and Path B1 skips a literal-0 base (`decompose.lisp:13-25`, `:437-440`). Componentwise chart lifting is new work, and a different chart may win per slot and per row.
- **A partial chart conflicts (read).** `metric-residual-decompositions` proposes a decoder that describes some missed row (`decompose.lisp:46-52`). For `(*, /)`, a row whose prediction does not divide its target keeps `(= (* 'p Z) 'y)`, which nothing satisfies, so the child frame conflicts. "Affine remainder via Stage B depth 2" does not follow: after `+` the child's target is again affine in the same quantity.
- **`:code-edit` pullback (read).** The anti-unifier is taken per row against the predicted value. Its pattern is the same on every row only when the Stage A program is a literal, which is the case `constructor-au-decompositions` already covers from the targets (`proposals.lisp:689`). Otherwise the edit paths differ by row and no single `code-subst` decoder exists.
- **A frame metric leaves no packet (read).** When the frame has its own metric the decoders do not compete (`frame.lisp:1592-1598`).
- **Changing the residual's shape (read).** `heuristic-residual` is `(row-key . witness)`. `commit-synthesis-job` writes it into hybrid relation tables (`consolidate.lisp:292`), the hit mask reads it (`decompose.lisp:78-84`), and 11 test sites use it. A parallel field for packets avoids all of that.

### 4.5 Branch closing and stopping (plan §4.3)

- **Bound tightening can starve followers (read).** A node closes as a follower because the canonical node's search covers its bound (`synthesize.lisp:819-821`). Tightening the canonical node to the incumbent through its own decoder overhead can drop child models that a follower with a cheaper path still needs. The bound must be the loosest over the node and its followers. As written this is false pruning.
- **The grace rule compares unlike quantities (read).** `B(n)` is the root-priced program plus residual bits in the node's own representation (`synthesize.lisp:382-384`). A lifted child has one row per call site, so its residual carries more row names than its parent's. Correct lifts look non-improving and spend the single grace.
- **`B(n)` is not pure MDL (read).** `node-priority` adds half the policy score and 16 bits per coupled requirement (`synthesize.lisp:460-464`), and after plan §4.4 a learned correction. The comparison should use the analytical part.
- **Strictness is inconsistent.** Grace is used when `B(c) > B(p)`, but the grandchild closes when `B(g) >= min(...)`. A chain of equal prices never spends grace and never closes.
- **It contradicts invariant 3.** Marking a grandchild's expansion `:done` is irreversible (`node-may-expand-p`), while the invariant says speculative branches are parked, not deleted.
- **At the default depth it does nothing.** `start-heuristic-synthesis` has `max-depth` 2 (`decompose.lisp:534`), so a grandchild cannot expand anyway.
- **Structural nodes block the new promotion rule (read).** A structural node's price is the minimum of its own and its parent's (`node-price`, `synthesize.lisp:889-896`), so it is never "worse than the parent's baseline". A product-slot group among the eager children holds promotion until its slots exhaust.
- **`*max-eager-proposals-per-node*` = 4 passes the suite (ran)**, but no test covers the starvation it is meant to cure.
- **Marginal stopping (read).** A node's priority is an estimate, not a lower bound; the only true bounds are enumeration frontiers. The test must depend on job state (work at the last improvement), not on the window of one `resume-synthesis` call, or unit-step resumption parity breaks. `:first` duplicates `:stop-on-first`.

### 4.6 The two retirements (plan §2.1, §3.2)

- **Filter-map is not reached by general lifts today (ran).** With `filter-map-decompositions` returning nothing, the H2 filter-map test fails (Appendix A). Every primary proposal is already eager at this commit, so scheduling is not what is missing.
- **Phase order.** The P9.1 gate removes `filter-map-decompositions`, but plan §2.1 makes that depend on plan §4.3 scheduling and on the template default, both in P9.2.
- **Templates do not bootstrap.** A `:decoder-template` is learned from a successful decomposition of the same shape, so the first filter-map instance has nothing to retrieve.
- **Anti-unifying witnesses does not give the transfer rule (read).** Two instance witnesses `(map Y '(- X0 1))` and `(map Y '(- X0 2))` generalise to `(map Y ?code)`. The link from a step's operator to its element solver, which `build-functorial-map-inverter` encodes with `:code-match` / `:code-bind` / `:code-subst`, is a relation between two entries that anti-unification of one of them cannot recover.
- **Plan 8 already flagged this.** `plan8.md` §6.6: the one transformer the tests learn is `(code-child X0 0)`, and "whether enumeration can reach [the inverters] was not measured".
- **Where the instance solvers come from.** With the builders gone they must come from `induce-conditional-solvers`, a full lifted synthesis per function and position, on the probe values of §8.3.
- **The dropped guard is documented and sound (read).** `bootstrap-inverters.lisp:68-70` omits a target-reading guard and says so; the result is a conjecture that is replayed. "Silently dropping" overstates it.
- **Side effects of the other removals (read).**
  - `tests/refactor.lisp:545` calls `make-additive-residual-decoder` directly.
  - Removing `induce-solvers-from-transformers` leaves the `:transformer` kind with no consumer.
  - Plan §3.1 moves solver discovery into the kernel, where P8.4 moved the discovery harness out to `milestones/algebra-discovery.lisp` to save lines.

### 4.7 Consolidation (plan §4.5)

- **Including hybrid relations overwrites the base (ran).** `condense` replaces a table with a law (`relations.lisp:140-150`). A hybrid entry stores the Stage A program plus the raw targets of the rows it misses. Fitting those rows alone gave `(+ 1 (* X0 3))` at 27 bits, which passes the `< 183` test and returns 13 at a key where the base returns 8. No frame exists for "base plus keyed exception law".
- **`member-requirement` does not exist**; the function is `set-requirement` (`frame.lisp:152`). A member table lists no non-members, so there is nothing to fit; the sound change is to exclude member tables at the gate.
- **The shared-helper inequality accepts a loss (ran).** On the audit fixture the tables are `57 + 63 = 120` bits, the law body 22, a call 16, a header 16. The current rule (copies) leaves 44 bits. The plan's rule leaves 70 and still passes `< 120`. It must compare against the copies, not only the tables. `call-bits` is not defined in the kernel. The current rule is deliberate and tested (`tests/audit.lisp:369-382`).
- **Defaulting the template flag to `t` breaks a test (ran).** The archiving test fails (Appendix A), because the remembered lift comes back as a learned-template proposal. The failing check is at `tests/theories.lisp:210-211`. Why the default is nil is recorded in `plan7-m9-policy.md`, line 21.
- **The reorder moves the two-pass problem (ran).** The `:motif` hook emits laws that retype consumes, and lift feeds the `:functor` hook.

  | Fixture | Current order | Plan order |
  | :------ | :------ | :------ |
  | `:map` over `:int`, certified `+` solvers over GF(5) and GF(7) | call 1 lifts 2 solvers; call 2 adds the functor and two inverters | all in call 1 |
  | Two monoid folds, right-identity laws, retype to GF(5) | call 1 adds 13 entries; call 2 adds none | call 1 adds 11; call 2 adds 2 retyped laws |

  Retype and lift have to sit inside the loop. The plan's step 3 also lists a `:law` hook, which does not exist, and omits the `:function` hook. Hooks run in priority order: function 10, relation 25, decoder-template 40, functor 40, motif 45.
- **The cited test does not need two calls (ran).** On its fixture the second call adds no entry and changes one edge on one law. Without the "stabilize" call the three checks still pass. The test is in `tests/invariants.lisp`, lines 424-428.
- **The log charge is not scale-free as written (ran).**

  | Failed lifts (count $\times$ work) | Linear | Log per lift | Log of total |
  | :------ | :-- | :-- | :-- |
  | 1 $\times$ 10,000 | 10 | 14 | 14 |
  | 100 $\times$ 100 | 10 | 700 | 14 |
  | 1 $\times$ 1,000,000 | 977 | 20 | 20 |

  - A per-lift log charges more than linear for every lift under about `14,000` work, which is every failed lift in the suite.
  - Read literally (search work only), it charges nothing for a lift that fails before any search, and `tests/theories.lisp:187` then fails. The per-proposal unit must be kept.
  - `plan8.md:274` says "log2 of failed work"; Levin's Kt takes one log of the total.
- **Amortizing solvers and templates has no credit side (ran).** `saving` goes through `(op id)` and fails for a solver or template id. The ledger is keyed by category, not by entry, so dispatch work cannot be attributed per solver.

---

## 5. The Five "Latent Bugs" of Plan §1.2

**1a. UIP bindings bypass — not a bug.**

- Case 2 of `check-parent-nogoods` (`nogoods.lisp:380-392`) fires when the proposal lifts through the entry's decoder and the proposal's own bindings agree on the entry's rows. That is sound whatever bindings the entry carried: the two occurrences have the same code inputs and incompatible requirements, and a context that does not separate their parent rows leaves them identical.
- A UIP clause is a copy of its first nogood, keys and values included. In case 2 it re-derives that nogood's own conflict. Its generalised pattern is evaluated only on the clause's own values, where it holds by construction.
- The pattern does its work in case 1 (through the parent clause) and in persisted schemas.
- With bindings cleared, a clause generalised from binding-carrying nogoods has parent-scope binding equalities (`nogoods.lisp:155-160`) evaluated in the code scope. That fails, so the clause stops pruning.
- The suite passes with and without the change (ran); no test tells them apart.

**1b. Positional schema zip — real, conditional.**

- `commit-synthesis-job` persists a schema for any lifted decoder (`consolidate.lisp:251-254`). `check-library-nogood-schemas` then assumes call `i` reads input element `i` and yields output element `i` (`nogoods.lisp:314-341`). For a decoder that permutes (a key function for a sort) this refutes valid lifts.
- It is sound for any elementwise combinator, single application or not.
- The proposed fix misreads `probe-frame-coordinates`. That function folds the decoded target at given output coordinates, by default `(0)` and `(1)`, and keeps only rows whose outermost call is ground (`frame.lisp:1045-1105`). It does not build the call-site cover and does not execute the VM; `lift-frame` builds the cover, by folding. Used here it would be sound but would see two elements per row.
- A cheaper sound fix is to gate the zip on the kernel's existing length-preserving test:
  - `function-body-length-preserving-p`
- *Correction (§11.7):* that gate alone is not enough. It needs two further conditions.

**2. M8D returns and features — half right.**

- No kernel code calls `synthesis-episode-returns`. One test does (`tests/refactor.lisp:481`).
- There is no runtime mismatch. `priority-predictor-function` pads or truncates the features to the predictor's arity (`synthesize.lisp:433-444`). A predictor trained on the 4-input trace frame receives 4 features.
- The trained target `f0 + 2 f1 + work/64 + (solved ? 0 : 10)` does replace the MDL price. That part is right.
- `tests/theories.lisp:175` is not forced to `nil`: it passes with `t` (ran). The jobs there pass no `:library`, so no predictor is consulted (`synthesize.lisp:173-176`).
- The proposed target is ill-defined. `G_t` is a job-level improvement per scheduling turn, credited to whichever lane ran at turn `t`. $J_{\mathrm{realized}}(n) - B_{\mathrm{MDL}}(n)$ subtracts a price from it. A per-node target needs its own definition, for example the best verified root score among candidates whose path passes through `n`, plus weighted work in its subtree, censored where there is none.

**3. VM re-evaluation — facts right, cause wrong.**

- `compile-ast-fn` does return nil for defined functions, `metric-delta` does build a fresh AST for the replay, and the packet is discarded (`condense.lisp:219-220`).
- None of that explains the budget override (§6.1).

**4. Relations — crash real, description and fixes wrong (ran).**

- A member table is a bare list of keys. With atomic keys the crash is the destructuring at `relations.lisp:114`, before `singleton-requirement` is reached. It also fires for any two member sets sharing a signature, whatever their size.
- Synthesis never creates a member table: `commit-synthesis-job` always passes a parametric base.
- Line 156 skips every hybrid entry, as stated. Since `consolidate.lisp:290` is the only kernel registrant, the `:relation` hook never acts on anything the kernel produces. This is a missing capability, not a wrong check: `condense` can only replace a table.
- A relation cannot be multi-valued; such a row fails registration.

**5. Lineage edges and ordering — partly right.**

- `combinator-call-code-args` recognises only literals (`abstraction.lisp:517-520`), as stated.
- Edges are recorded by `record-combinator-call` from the `:function` install hook, not by `define-function`. A second recorder on the commit path records them for any library function the winner calls (`consolidate.lisp:238-242`), so synthesis-committed parameterised lifts already carry them (ran).
- Nothing downstream uses a closure edge. The parameterised inverters match the closure shape directly over every function entry (`bootstrap-inverters.lisp:106-109`, `:247`); the motif hook needs a literal step. Adding the edges induced nothing more (ran).
- The template default and the ordering are covered in §4.7.

---

## 6. Gates

### 6.1 P9.1: `tests/metrics.lisp` at the default budget — not reachable as planned (ran)

- One `metric-delta` on the fixture costs `3,334` units, all VM execution of the correlation solver and the replay. The plan keeps VM steps metered.
- What a prepared program skips is the syntax work of the solver expression, `11` units. The existing prepared path still charges input value work by design ("still validate/copy every new input value", `vm.lisp:81-85`; tested in `tests/amortization.lisp`).
- Skipping the replay needs current witness evidence; this solver is a conjecture.
- The cached packet saves work in Stage B and in preparation, outside the Stage A budget.
- Stage A on the task completes at `12,377` units, `10,662` of them metric evaluation.
- The task solves at `:heuristic-budget 16000` (`100,050` work). `60000` was never required; `2000` cannot be reached without making the solver's own execution cheaper.

### 6.2 P9.2

- **"Probe 3 under 350k"** is already met: the conditional tuple scan solves in `264,353`.
- **Numbering.** That sentence uses `plan8.md` Appendix A's numbering for Probe 3 (conditional scan) and its §1.3 table numbering for Probe 4 (symmetric scan, `112,979` today). Plan §1.1 and §4.2 use the table numbering; plan §5.4 uses the appendix numbering.
- **`:condense-heuristic-p t` on `tests/theories.lisp`** already passes.
- **One-call idempotence** is a real target; see §4.7 for the cycle.

### 6.3 P9.3

- **Sort versus reverse separator (ran).**
  - `<=` is not an operator. With `<`, the two example separators have body sizes 63 and 84 bits; the bound allows 28.
  - The kernel's sequence probes are `() (2) (-1 2 5) (10 13 19)`, all ascending. The best separator found on them was `(= X0 X1)`, which is false for any unsorted input.
  - With richer hand-written probes the search exhausted the bound with no result.
  - Evidence over sequences can only be sampled, and a sampled descriptor never prunes (`descriptors.lisp:762`, `tests/invariants.lisp:372-395`).
  - `sort` and `reverse` take no code parameter, so `library-decompositions` never lifts them (`proposals.lisp:324-325`). The confusion class lies outside the path being optimised.
- **"More than 50% less orientation and false-lift work".** The two halves pull against each other: the early return saves a few hundred units of descriptor evaluation and lets through lifts that a necessary descriptor would have refuted (§8.2).

### 6.4 LOC balance

Plan 8 budgeted `+550`–`650` and spent `+1,530`. It estimated `800`–`1,050` removable lines and removed about 215 (`plan8.md` §6.6). Plan 9 budgets `+890` for considerably more, and `-1,052` of which `-496` depends on the two retirements of §4.6.

---

## 7. Names and Citations That Do Not Match the Source

| Plan text | Source |
| :------ | :------ |
| `prepare-program` (`vm.lisp:247-272`), `evaluate-prepared` | Neither exists. The API is `start-program-validation` and `start-validated-evaluation` (`vm.lisp:76-85`). A handle asserts on a version change (`vm.lisp:83`), so a cache must key on `(vm-versions)`. |
| `synthesize-recursive-function` | `start-recursive-synthesis` (`decompose.lisp:559`) |
| `retype-function-definition` (`proposals.lisp:24-110`), "1 sequence element type" | `templates.lisp:183-215`. Inference is by unification and already has independent variables; a direct call retypes `:fix-seq` to pair-fuel and sequence-state (ran). The gap is the caller, `candidate-library-definitions` (`proposals.lisp:47`, `:59-62`). |
| `member-requirement`, `call-bits`, `all-elements`, `sort-by`, a `:law` consolidate hook | Not in the kernel |
| `mod`, `<=`, `not`, `and` in example guards and separators | Not operators (`ast.lisp:103-130`). Connectives are `:if` encodings; divisibility must be written with `/` and `*`. |
| `probe-frame-coordinates` "materializes the evaluation cover ... by metered VM probe execution" | See §5, item 1b |
| `plan8.md:323` "five capabilities", third being the `:code-edit` pullback; "plan8 §5.5, L303" | Line 323 lists certified transfer laws, not the pullback. The pullback is in `plan8.md` §6.2. Certified transfer laws are dropped without comment. |
| `project-frame-rows` (`frame.lisp:620-645`) | `frame.lisp:1287` |
| `orient-available`, `schema-availability-order` (`frame.lisp:1625-1698`) | `frame.lisp:1302`; the latter is a schema slot in `ast.lisp` |
| `pullback-frame` ... `lift-frame` (`frame.lisp:886-1242`) | `frame.lisp:528-1208` |
| `apply-correction-packet` (`frame.lisp:1453-1489`) | `frame.lisp:1612-1648` |
| `dependency-expander` (`proposals.lisp:661-720`) | `proposals.lisp:474-532` |
| `analyze-function-body-totality` (`ast.lisp:704-851`) | `ast.lisp:721-868` |
| `observation-bucket` (`enumerate.lisp:545-580`) | A struct at `enumerate.lisp:588` |
| `find-knowledge-entries-by-address` (`knowledge.lisp:258-262`) | `knowledge.lisp:264-270` |
| "Moment-difference heuristic solvers" (P9.4 row) | No design section anywhere in the plan |

---

## 8. Further Edge Cases, by Plan Section

### 8.1 Fiber separation (plan §2.1)

- **Dropping the lift gate in `node-dip-repairs` passes the suite (ran)**, but the repair is weak for projections. `collect-frame-nogood-clauses` gathers the other collisions only for lifts (`nogoods.lisp:179-182`), and a repair is never repaired again (`nogoods.lisp:512-513`). A projection gets a separator for one colliding pair.
- **The three paths differ more than the plan says (read).** `dependency-expander` proposes single-feature projections and, in its sufficient-only mode, filters by collision consistency. It enumerates no separators.
- **Stage A buckets as separators** are sound to index by row, but exist only where the parent's Stage A produced a model (§4.1: often not at the root).

### 8.2 Descriptors and address decoding (plan §2.2.3)

- **Specs are already homoiconic (ran).** A spec is an AST triple stored as a `:descriptor` entry (`descriptors.lisp:589-603`). What is host-coded is which concept applies to which entry, the ids and weights, and the structural proof behind `:necessary` (`list-recursion-shape`). About half of the 190 lines are bounded observation searches, not AST builders.
- **Seeds.** `len-eq`, `len-le` and `empty->empty` exist. `preserves-head`, `monotone-int` and tuple-projection preservation are new. Seven existing concepts are not in the plan's list, and `tests/library.lisp:492`, `:542-554` and `:665-685` depend on some of them.
- **An entry-independent seed lacks three things (read).** A polymorphic schema (inputs are compared by `equal`, `descriptors.lisp:182-186`); evidence per descriptor and entry (`:necessary` belongs to the descriptor entry); and per-entry weights.
- **"Tier 1 is O(1)" does not describe today (ran).** Only the `:type` clause is free of the VM. Every `:necessary` descriptor is a Tier-1 descriptor that runs the VM on each pair. Tier-3 algebraic clauses are not evaluated at all. `max-tier` does not gate scoring: a descriptor missing from the verdicts is evaluated on demand (`descriptors.lisp:764-768`).
- **Returning early at two survivors skips the only pruning (ran).** On a contracting frame `:map` is refuted for 197 work and only `:filter` is proposed. An early return on that pair would lift both.
- **`frame-addressed-entries` is not a drop-in (ran).** It counts satisfied concepts without weights or pruning, and returns nothing on a frame whose rows allow more than one output, which is typical of pulled-back children. `library-decompositions` proposes three entries on the same frame.
- **"Within 4 policy bits"** is less than one clause weight; observed scores were `-17`, `-3`, `-2`, `+1`, `+3`.
- **Contrastive synthesis.**
  - A job keeps no record of which entries competed. The existing loser test also matches scope-reuse followers, and misses lifts that searched and found nothing (`consolidate.lisp:362-366`).
  - `start-search` takes neither a work limit nor a bound; those belong to `resume-search` (`enumerate.lisp:337`, `:542`).
  - A row whose evaluation errors is skipped, so a descriptor that errors on two of three rows came back satisfied (ran).
  - Address collisions are the wrong trigger: the warm library of `tests/invariants.lisp` has 34 colliding pairs, none involving a liftable entry (ran).
  - A separator has no slot in the five-token address, so the collision persists and the step would re-fire. The fixed-point test needs an explicit memo.

### 8.3 Solver induction (plan §3.1)

- **Probe values (read).** `probe-values-for-type` returns `(0 1)` for `:int`, two values for `:bool` and a field, and nothing for sequences or tuples (`descriptors.lisp:254-259`). On those probes `Y` is a valid witness for `(* X0 Z) = Y`, and no divisibility guard can be told apart from `t`.
- **Empirical fibers are cut off by the probe box.** A "complete fiber" list learned from them is wrong for contexts near the edge, for example truncating division, whose fiber has as many members as the divisor.
- **The example guards use operators that do not exist** (§7), and the equivalents are larger than the small bounds the plan quotes.
- **"A witness over non-zero elements"** needs a search over the sequence inside the witness. Stage A will find the head-based witness with a guard, which is what `bootstrap-inverters.lisp:78` hard-codes.

### 8.4 Law-to-solver extraction (plan §3.2)

- **Two conditions are stated as consequences.** The context variables must be distinct, or an equality guard is needed. The free variables of the witness and the guard must lie within the context and the target.
- **The `shift-seq` example does not match the rule.** It has `(- 0 K)` in a known position, where the rule requires a bare variable. Restated to fit, the law is false for a zero-padding shift.
- **No uniqueness follows from a law.** `induce-involution-solvers` sets `:unique-p` for a certified, unguarded involution (`bootstrap-inverters.lisp:147`). The general rule would lose it, and those narrowings would start to spawn fallbacks.
- **Evidence cannot be copied.** A certificate binds to its own entry's snapshot (`evidence.lisp:44-49`). `:derived` is the method to use.
- **Bidirectional shift.** A negative shift counts up to zero. Plan §5.1's integer rule covers only descent.

### 8.5 Propagation details (plan §3.3)

- **Set propagation with several unknown positions.** The union of tuple witnesses is not a conjunction of per-position memberships, and a disjunction blocks further unwinding. The cap of 8 must hold at every level.
- **Monotone inequalities.** Direction depends on the sign of the context value and on the position (`*`, `-`), not on a flag per operator. Truncating `/` is not strict. The equality witness exists only when the constant is in the image. Under a decreasing map the wrong choice of witness rejects valid values.
- **`:preserve-operator-p`.** It must match the operator and the open positions, and a failed solve still needs the ordinary fold. Otherwise a call is left opaque, and both conflict detection and witness extraction are lost.
- **Indexed dispatch** changes the `:propagator-dispatch` charge and so every work total. The index must use the full operator, type included (`laws.lisp:669`).
- **Simplifying before each unwinding step** can move the target into two argument positions. Try the original form as well.

### 8.6 Row embeddings (plan §2.2.2)

- **Stage A buckets are the wrong pool for non-`:int` targets (ran).** They hold only target-typed expressions (`enumerate.lisp:789-796`), and a non-nil list suppresses the accessor search (`proposals.lisp:908`). On a sequence target with the key inside a tuple input, the induced key became a noise column.
- **`:locality-key` is `:int` only** (`proposals.lisp:775`). Tuple keys need changes at `:887`, `:910`, `:918` and `:954`, and the plan does not say how a vector key orders rows into a chain.
- **`with-induced-row-order` has side effects (ran).** It returns a re-stored frame with a hard `:distinct` edge between the chain ends, and registers a library entry. Bucket values already computed are in the old row order, and `dependency-expander` and the guard search index them by position.
- **Nothing consumes `:persistence` edges.** They constrain nothing (`frame.lisp:22-23`), are not priced, and survive only identity pullbacks (`frame.lisp:546`).
- **The tie-breaker is not a tie-breaker (read).**
  - `relational-linkage-residual` does not read edges, and exactness is not known when it is called (`condense.lisp:117-134`).
  - The term is not a code length, yet it enters model ranking and node priority.
  - It makes a cliff: an exact varying model pays nothing, the same model with one wrong row pays its whole chain variation, and a constant model pays nothing. That is the failure of `plan8.md` §6.4.15 moved one row from exactness.
- **`generated-space-distance`.** The description is right. Every scalar key in the tests is a class label (parity), which is what the docstring says the branch is for. Switching to $|k_a - k_b|$ passes the 14 corpus and view tests, but widens the locality window from 59 occurrence pairs over 4 same-class tree pairs to 106 pairs including 6 cross-class ones (ran). Positions stay in first-occurrence class order.
- **"Multi-input keys (L478)".** That line is an assert refusing them, pinned by `tests/milestones/corpus.lisp:424`.

### 8.7 Totality and `:fix-seq` (plan §5.1)

- **The description of today's analyzer is right.**
- **Off by one.** The false branch of `(= (tail^k X) ())` proves length at least $k+1$, so the safe range is $1 \le d \le k+1$. As written, "$1 \le d \le k$" rejects the `evens` and `pairwise` examples.
- **The guard is itself partial.** It needs length at least $k$ before it is evaluated.
- **Definedness rules are missing.** Without rules for `(at X 'j)` and `(at (tail^j X) 'i)` under the rank environment, pairwise bodies still fail.
- **Deltas are per position against the same parameter.** Counting `(tail ys)` in the slot of `xs` as a decrease would certify a diverging function (ran).
- **Integer descent.**
  - `(- X 'c)` under `(< 'b X)` is sound for every $c \ge 1$. The side condition in the plan is not needed.
  - Halving is sound only for a bound of at least 0: under `(< -5 n)` it sticks at 0 (ran).
  - `(:int-neq 0)` alone must not license descent: it diverges from $-1$ (ran).
  - Several sites with different bounds need one measure. Ascending recursion is not covered.
- **`:fix-seq` as written type-checks and runs, but is not certified total (ran).** The self-call and the `(tail fuel)` sit inside a quoted literal, which the analyzer judges without context. Three routes work:

  | Route | Result |
  | :------ | :------ |
  | Beta-inline the closed `:code-eval` redex in the analyzer | Conditional totality on the step parameter; a small analyzer change |
  | Evaluate the step twice, with a direct self-call | Conditional totality today; costs a second step evaluation |
  | Four-parameter worker plus three-parameter wrapper | Conditional totality today; the wrapper cannot be retyped |

- **The stationary law.** The plan makes $y \ne \mathit{init}$ its precondition; `plan8.md` Appendix B.3 has two separate facts. "Converged within fewer than $|\mathit{fuel}|$ steps" cannot be decided from fuel, init and output: fuel of length 3 gives 3 with a step that maps 3 to 4 (ran). It must stay a conjecture with its fallback.

### 8.8 Bipartite matching (plan §5.2)

- **When it runs is unspecified.** If it competes on every sequence correction, each missed row costs a quadratic number of priced corrections inside Stage A, and prices change on ordinary ordered tasks, including the shifted-sequence one. Gating on the frame or on tuple elements avoids both.
- **A zero price for a permutation** conflicts with the clamp to at least one bit (`frame.lisp:1598`) and with "0 iff equal" (`plan8.md` §3.1).
- **`induce-row-order` is not the right tool for the element key.** It has no grouping by parent row, and adjacent variation is the same ascending and descending.
- **`sort-by` does not exist.** It needs a definition that the totality analysis accepts.
- **Registering a key from inside Stage B** makes library state depend on how far a search ran. Elsewhere search proposes and consolidation registers.

### 8.9 Active queries (plan §5.3)

- The requirement is not a membership, so `extract-allowed-values` gives `:unknown` and Stage A cannot price it. Only exact search applies.
- "Maximise the number of distinct outputs" has no mechanism: Stage A minimises correction bits to a witness.

### 8.10 Coupled and latent fibers (plan §5.4)

- **The regime is a property of the decoder, not the schema.** Availability ranks input columns against the whole target (`rank-lt-p`). "Step $t$ sees $y_{t-1}$" needs the target unfolded into rows.
- **Cross-time coupling is not what the product join handles.** The join evaluates a conjunct over slot values on one row (`coupled-combination-admissible-p`, `synthesize.lisp:613-632`). A trajectory conjunct applies the composed step repeatedly.
- **The latent slot is unconstrained**, so its search returns the smallest programs at once and its pool is the four smallest (`*max-coupled-slot-candidates*`). A useful accumulator update is unlikely to be among them.
- **The anchored row is not priced.** In Probe 6 it constrains one component of a tuple output, so `extract-allowed-values` gives `:unknown`.
- **Rollout validation on coupled rows** is what root verification already does for every candidate. The new part would be local screening.

---

## 9. Existing Defects Found in Passing

These are in the kernel at `019736f` and are not in the plan.

1. **The totality fixpoint iterates from stale flags (ran).** The driver starts from the other functions' previous flags (`knowledge.lisp:497-510`, `recompute-registered-functions-totality`). Define `g`, define `f` as `(g n)`, then redefine `g` as `(f n)`: both stay `total-p T`, `(provably-total-p (f n))` is true, and `(f 3)` diverges. Resetting all non-oracle flags before iterating should fix it. Plan §5.1 builds on this fixpoint.
2. **A call to a registered but undefined name is total (ran).** The `(null def)` branch at `ast.lisp:713`. *Note (§11.3):* the same branch is what makes primitives total, so the fix must keep it for them.
3. **Member tables crash `:relation` consolidation (ran).** §5, item 4. Not reachable from synthesis.
4. **A failed relation fit is never memoised (ran).** One incompressible 6-row table costs `100,000` work on every bare consolidation.
5. **Consolidation is not a fixed point after one call (ran).** The docstring at `consolidate.lisp:937-938` says it is; the first fixture of §4.7 shows otherwise.
6. **Lift templates are stored but never generalised (ran).** `generalize-decoder-templates` takes only templates without `:lift-p` (`proposals.lisp:1189-1191`), and the templates remembered from library-lift wins have it. *Correction (§11.7):* this is a documented limit of scope, not a defect.
7. **The positional schema zip.** §5, item 1b.

---

## 10. Structural Recommendations

P9.1 is not an increment. It bundles about fifteen deliverables across thirteen files, and its gate includes one test that cannot be reached (§6.1) and two retirements that depend on P9.2 (§4.6). A split that keeps each step testable:

1. **Fixes that leave work numbers unchanged.** The schema-zip gate, the totality fixpoint reset, the member-table gate, a parallel packet field. Gate: the suite and the probe figures of §3 are identical.
2. **The chart change, with its budget effects measured.** Decide first whether `+` stays a host fast path. Gate: the probe figures, stated before and after.
3. **Solver induction alongside the host builders.** Keep `bootstrap-inverters.lisp` and `filter-map-decompositions` until the new path reproduces their solvers and solves the filter-map test by itself. Retire them in a separate step.

Three further points:

- **Test control changes by replay before building them.** The method of Appendix C costs a few lines and would have shown the result of §4.1.
- **Keep the Plan 8 audit's decisions unless the plan argues against them by name.** §4.2 and §4.3 each reverse one without saying so.
- **State each gate against the measured baseline.** Two of the P9.2 gates are met at `019736f`.

---

## 11. Follow-Up: Plan 9 v2.0

> **Status:** Review of `plan9.md` v2.0 (the revision that incorporates this audit), 17 November 2026, against the kernel at `fafffd9`.
> That commit includes `a822990`, exact closure evaluation (`plan-exec.md`). Source lines in this section are at `fafffd9`; the sections above stay at `019736f`.
> "Plan §" in this section means a section of v2.0.

### 11.1 Verdict

v2.0 fixes the large majority of what this audit found, and its phase structure is sound. What remains is short:

- four items that would break something as written (§11.3),
- two that cannot be reached as specified (§11.4),
- a re-base onto the closure commit (§11.5),
- some smaller misreadings (§11.6).

Three of the remaining items trace back to statements in this audit that were too loose or mislabelled. They are corrected in §11.7.

### 11.2 What v2.0 Fixes

| Audit section | What v2.0 does |
| :-------- | :-------------- |
| §4.1 yield gate | Dropped. `stage-a-budget` is kept as it is (Guardrail 1). |
| §4.2 deferred fallbacks | Dropped. Fallbacks stay active siblings (Guardrail 2). |
| §4.3 complete fibers | Fallback-free narrowing only on current evidence; list-valued witnesses and inequality propagation dropped. |
| §4.4 `+` as a chart | Host subtraction kept (Guardrail 3); packets go in a parallel `heuristic-packets` field. |
| §4.5 branch closing | Follower-safe bound, soft parking in place of closing, structural nodes exempt, stopping keyed on job state. |
| §4.6 retirements | Build and measure first; retire in a separate gated step, P9.3b (Guardrail 4). |
| §4.7 consolidation | Hooks, retype and lift inside one bounded loop; hybrid relations left alone unless patched over all rows; template default stays nil. |
| §5 latent bugs | Replaced by the defects of §9. The UIP bindings and `relations.lisp:156` are recorded as intentional. |
| §6 gates | P9.1 is zero-drift against the measured probes; the metric tests are set to `16000`. |
| §7 names | `start-recursive-synthesis`, `set-requirement`, the real VM API and `templates.lisp` are now cited. |
| §8.4 law-to-solver | Distinct context variables, the free-variable condition, `:derived` attestation and a correct uniqueness rule. |
| §8.7 totality | The off-by-one, per-slot deltas, the halving bound, ascent, and beta-inlining for `:fix-seq`. |
| §10 structure | Six increments, each with its own gate. |

Three things were checked again on `fafffd9` (ran):

- The work figures of plan §1.1 reproduce exactly: `34,067`; `112,979`; `264,353`; `3,334` per `metric-delta`; `12,377` for Stage A; `100,050` end to end.
- The flag reset in the totality fixpoint passes all 185 tests and leaves the ledger fingerprint byte-identical.
- Both metric tests pass at `:heuristic-budget 16000`.

### 11.3 Would Break Something as Written

**1. The undefined-callee fix (plan §1.2.1, P9.1 item 1).**

- The plan says `(null def)` "must require `def` to be present and proven total". That branch is the `otherwise` clause of `operator-step-total-p` (`ast.lisp:722-730`), and it is also what makes every primitive total, apart from the few listed as partial.
- Requiring `def` fails the suite at its seventh test, `constant-folding-and-conflict-detection` (ran).
- Accepting `(null def)` only for primitives passes all 185 tests (ran):

  ```lisp
  (if (null def)
      (not (null (member op-name +operator-names+)))
      (or (function-definition-total-p def) ...))
  ```

- With that and the flag reset together, both defects are closed (ran): after the mutual redefinition `f` and `g` are both non-total, and a call to a registered but undefined name is non-total. The ledger fingerprint over the 222 tests is byte-identical, so P9.1 item 1 is zero-drift when done this way.
- The same branch also covers a self-call while a body is still being built, before its definition exists. Under the fix such a call is non-total until the function is defined; the fixpoint then recomputes it.

**2. The all-rows chart rule (plan §2.2.1, item 2).**

- The plan proposes an unconditional chart "only when every constrained row" is a hit or has a replay-valid `metric-delta`.
- That breaks `metric-decoder-pulls-a-residual-back-to-its-delta` at `(= 1 (length proposals))` (ran). The shift solver misses the row `((5 8 2 6) 3)` with target `(6 0 0 0)`, whose requirement is still satisfiable; the test says so ("which only 3 meets").
- A heuristic solver that misses a row has not shown the row unsatisfiable. Only a solver with current evidence can.
- Apply the all-rows rule to decoders whose solver has current evidence, and keep today's "describes some row" rule for conjectured ones.
- The rule also assumes a right identity for hit rows. Check it by running the solver on them.

**3. The Levin formula (plan §4.3.3).**

- The formula is $N + \lceil \log_2(1 + W) \rceil$, with the failed-proposal count $N$ outside the log. That charges a whole bit per failed proposal. Today a failed proposal adds one work unit, which is 1/1024 of a bit.

  | Failed lifts (count $\times$ work) | Linear today | v2.0 formula | Count inside the log |
  | :------ | :-- | :-- | :-- |
  | 1 $\times$ 10,000 | 10 | 15 | 14 |
  | 100 $\times$ 100 | 10 | 114 | 14 |
  | 1 $\times$ 1,000,000 | 977 | 21 | 20 |
  | 3 $\times$ 0 | 1 | 3 | 2 |

- A hundred cheap failures cost 114 bits. That is the effect the paragraph cites as the reason for the change.
- Put the count inside: $\lceil \log_2(1 + W + N) \rceil$. It stays nonzero for a lift that fails before any search, and the suite passes with it (§4.7, ran at `019736f`).

**4. `:derived` transfer laws (plan §2.2.1, item 5).**

- A motif is an empirically found relation: "what is found to hold of the fold for them is conjectured of every instance" (`consolidate.lisp:655-657`). Its premises may be certified; the step from them to the transferred law is not.
- `:derived` counts as current evidence (`evidence.lisp:56`), and current evidence licenses elimination. Attesting a motif's law `:derived` promotes sampled evidence to that grade.
- It is sound only for an inference the host itself proves, such as the fold theorem with associativity and a two-sided identity, matched exactly.
- "Domain isomorphism" does not apply between prime fields. Retyped laws are re-validated in the new domain today, which is the right behaviour.

### 11.4 Unreachable as Specified

**1. Guard search (plan §3.1, step 3).**

- The example guard `(if (= X0 0) nil (= (* (/ Y X0) X0) Y))` has body size 57. The stated bound is header + 56.
- At 57, exact search does not find it within `60,000,000` work (ran). The frame was the 49 contexts with `X0` and `Y` from $-3$ to $3$; the grammar was `=`, `<`, `/`, `*`, `if` and the literal 0.
- `induce-conditional-solvers` has a work limit of `40,000` in all.
- Guards of this size need the heuristic route (Stage A, then a conditional split), not `start-search`.

**2. Contrastive separators (plan §2.2.3).**

- The bound is header + 72 with `20,000` work. Written with `:if`, the sorted-adjacent separator is 75 bits and the endpoint one 84.
- By the measurement above, exact search at `20,000` work does not come near 72 bits.
- For higher-order combinators a separator over (X, Y) has to hold for every step function, so it usually does not exist: nothing over (X, Y) alone tells `map` from `map-twice`.
- The P9.4 gate needs a named pair for which a separator exists and is not already a shape descriptor.

### 11.5 Re-Basing on the Closure Commit

- **Baseline.** The kernel is `15,257` lines and has 185 tests / `928,458` checks. Milestones are unchanged at 40 / `186,771`. The P9.1 and P9.3b gates still say 182.
- **Prepared-execution cache (plan §2.2.1, first bullet).** It is largely superseded.
  - `expression-closure` (`vm.lisp:428`) already keeps a cache keyed on the function-library version (`*closures*`, `*closures-version*`). The one uncovered case is a call of a defined function, which `plan-exec.md` §5 lists as the next step.
  - Skipping the static check also skips its charge. That changes ledgers, against P9.1's zero-drift title, for 11 units out of `3,334`.
  - Either drop it, or recast it as closures for defined-function calls, with `experiments/ledger-fingerprint.lisp` as the gate.
- **Zero-allocation replay in `metric-delta`.** Still worth doing, for a new reason: the closure cache is keyed by node identity, so a fresh AST per replay adds entries on every call until the table is cleared at `*closure-limit*`.
- **Stale line references.**
  - `vm.lisp:473-526`: `entry-executable` is now at 393 and `eval-entry-slot` at 574.
  - The `ast.lisp` ranges are 11 lines later: `operator-step-total-p` at 701, `analyze-function-body-totality` at 810.
  - `enumerate.lisp:789-796` is 6 lines later.
  - `resume-synthesis` is at `synthesize.lisp:1215`, not 1148.

### 11.6 Smaller Misreadings

- **Schema-zip gate (plan §1.2.2).** See §11.7, item 1.
- **Two-combinator pipeline lift (plan §2.1.2).** `filter-map-decompositions` is already generic. It picks its mapper and selector from the library by signature (`proposals.lisp:239-256`), is gated on contracting frames, finds the predicate by alignment, and lifts the mapper. The proposal restates it. Its stated gate, `probe-frame-coordinates`, cannot align through an unknown predicate: the first output element does not fold to a ground call. Retiring one for the other saves nothing unless the new lift does something the old one cannot, such as leaving both code children unknown.
- **`candidate-library-definitions` (plan §5.1.B).** The call the plan says to add already happens (`proposals.lisp:62`). The gap is that line 47 strips the sequence from the target, so a sequence-typed state is never tried.
- **Fold rule for Probe 6 (plan §5.4.2).** `fold-at-tuple` already folds `(at (tuple ...) 'i)` (`requirements.lisp:275`). What blocks the tuple product is `rows-pin-values-p` (`proposals.lisp:565`, used at `:718`), which needs every constrained row to pin one whole value.
- **`:code-edit` pullback (plan §2.2.1, item 6).** The joint anti-unifier of the targets is what `constructor-au-decompositions` already proposes, so the P9.2 gate may be met today. `:code-subst` fills holes in a template and cannot edit a computed prediction; that needs `:code-child` and `:code-apply`.
- **Operators.** `mod` and `when` appear again in the moment solvers. `:functional` is not a term in `relations.lisp`; the predicate to gate on is `member-table-p` (`relations.lisp:11`).
- **Row order (plan §2.2.2).** With frames and the library left alone during search, nothing in search consumes an induced key. Recording keys there spends work for no effect in the job. Induce at consolidation, from the job's root frame.
- **Hybrid relation patch (plan §4.3.2).** The rows the base got right are not stored, and `probe-values-for-type` gives `(0 1)` for `:int`. Store the hit keys at commit so the guard has real negatives.
- **Budget `16000` (plan §2.2.1, item 4).** It was measured for the forward-only solver. A bidirectional solver does about twice the correlation work per `metric-delta`. Set the number after that change.
- **Soft parking (plan §4.1.2).** "Normalized residual bits" is not defined, and a 16-bit penalty moves scheduling. Given §4.1's sensitivity, measure it on the suite.
- **Trajectory join (plan §5.4.3).** The latent slot is constant on the $t = 0$ rows, so those rows cannot tell apart observed-slot candidates that differ only in how they read it. Keep that pool wide.

### 11.7 Corrections to This Audit

1. **§5, item 1b: the schema-zip gate.** The audit suggested gating on `function-body-length-preserving-p`, and v2.0 adopted it. The suggestion was made without reading the function and is too loose.
   - It is at `descriptors.lisp:73`. The plan's `abstraction.lisp:247` is also wrong.
   - It tests the shape `:preserving`: one `cons` per `tail` step (`descriptors.lisp:28-71`). It does not constrain what the emitted element reads. `(cons (code-eval f (length xs)) (self (tail xs) f))` passes it, and the zip is unsound for it.
   - A sound gate needs two more conditions: the emitted head applies the code to `(at X 0)` and to nothing else that varies, and the decoder's sequence argument is the row's bare input.
2. **§9, item 6: lift templates.** The audit listed this as a defect, and v2.0 repeats that (plan §1.2.5). The docstring of `generalize-decoder-templates` scopes it to "templates of pulled-back children" (`proposals.lisp:1175-1182`). It is a missing capability.
3. **§9, item 2: the `(null def)` branch.** The finding stands, but the audit did not say that the branch also serves primitives. §11.3 supplies the fix.

### 11.8 Experiments for This Section

All on `fafffd9`. Each edit was made in a scratch copy and followed by `sbcl --script tests/run.lisp kernel`; "fingerprint" is `experiments/ledger-fingerprint.lisp` compared with the unedited kernel.

- Flag reset in `recompute-registered-functions-totality` (`knowledge.lisp:492`): 185 pass; fingerprint identical.
- The reset plus the primitive-aware `(null def)`: 185 pass; fingerprint identical; both defects closed.
- `(null def)` replaced by requiring `def`:
  - `constant-folding-and-conflict-detection` fails
- `decompose.lisp:46-48`, `some` changed to `every` with a hit row counting as covered:
  - `metric-decoder-pulls-a-residual-back-to-its-delta` fails
- `tests/metrics.lisp:214` and `:442`, `60000` changed to `16000`: 185 pass.
- Guard search as described in §11.4: no result at slack 56 or 57 within `3,000,000` work, and none at 57 within `60,000,000`.
- The probes of `plan8.md` Appendix A and the measurements of Appendix B: unchanged.

---

## Appendix A. One-Edit Experiments

Each item is one change to a scratch copy of the kernel, followed by `sbcl --script tests/run.lisp kernel`. The runner stops at the first failure, so a failing edit names only its first failing test.

Edits after which all 182 tests pass:

- `tests/theories.lisp:175`: `:condense-heuristic-p t`.
- `synthesize.lisp:983`: `*max-eager-proposals-per-node*` set to 4.
- `synthesize.lisp:479`: the gate also admits pure projections.
- `nogoods.lisp:245`: the UIP clause's bindings are cleared.

Edits after which a test fails:

- `synthesize.lisp:377`, multiplier 2 changed to 1:
  - `higher-order-h1-polymorphic-retyping-filter-and-lockstep`
- `synthesize.lisp:377`, multiplier 2 changed to 3, and to 4:
  - `recursion-r4-oracle-controls-and-resume-parity`
- `synthesize.lisp:377`, multiplier 2 changed to 7:
  - the r4 insert job is unsolved, `(synthesis-job-best insert-job)`
- `proposals.lisp:389`, no filter-map proposals:
  - `higher-order-h2-nested-2d-grids-outer-product-matvec-and-filter-map`
- `synthesize.lisp:746`, the fallback pushed onto the parent's deferred list:
  - `an-ambiguous-narrowing-is-rescued-by-its-fallback`
- `consolidate.lisp:214`, `:register-templates-p t`:
  - `unamortized-library-entries-are-archived`

## Appendix B. Shifted-Sequence Budget Measurement

The fixture is `shifted-sequence-fixture` in `tests/metrics.lisp`, with the shift metric installed.

- One `metric-delta` on `(3 1 4 1 5)` and `(4 1 5 0 0)`: `3,334` units, all `:simulation`.
- Solver expression `(argmax-corr X0 X1)`: syntax work 11. Input value work 21 and 20.
- `condense-heuristic` alone: no model at budgets `2,000` and `8,000`; the identity with score 123 at `20,000` and above.
- Stage A run to completion: `12,377` units, by ledger category:
  - `:heuristic-metric` 10,662
  - `:observation` 867
  - `:heuristic-checking` 579
  - `:heuristic-preparation` 148
  - `:heuristic-residual` 117
  - `:heuristic-ranking` 4
- End to end, `start-heuristic-synthesis` at bound 120 with a limit of `300,000`, by `:heuristic-budget`:
  - default, `4000`, `8000`: unsolved
  - `16000`: solved at `100,050`
  - `30000`: solved at `133,743`
  - `60000`: solved at `205,914`

## Appendix C. Yield-Gate Replay

Method: `condense-heuristic` was redefined to resume its search in quanta of `2,000` up to the same limit, which leaves the search unchanged, and to log the best score and the number of observation buckets after each quantum. The gate stops at the first quantum that neither improves the score nor adds a bucket. "Score only" is the same gate without the bucket condition.

**Symmetric tuple scan** (`112,979` work; winning path nodes 5, 1, 0):

| Node | Proposal | Inputs | On winning path | Budget | Final model at | Gate stops at | Score-only stops at | Buckets per quantum |
| :-- | :------ | :-- | :-- | :-- | :-- | :-- | :-- | :------ |
| 0 | root | 2 | yes | 2,120 | none | q1 | q1 | 0 0 |
| 1 | library lift | 2 | yes | 5,966 | q1 | never | q2 | 2 4 6 |
| 2 | library lift | 3 | no | 18,076 | q1 | q7 | q2 | 2 4 6 8 10 11 11 11 11 11 |
| 3 | library lift | 2 | no | 5,966 | q1 | never | q2 | 2 4 6 |
| 4 | library lift | 3 | no | 18,076 | q1 | q7 | q2 | 2 4 6 8 10 11 11 11 11 11 |
| 5 | additive | 2 | yes | 5,885 | q2, exact | never | q1 | 2 2 |

**Conditional tuple scan** (`264,353` work; winning path nodes 10, 7, 1, 0):

| Node | Proposal | Inputs | On winning path | Budget | Final model at | Gate stops at | Score-only stops at | Buckets per quantum |
| :-- | :------ | :-- | :-- | :-- | :-- | :-- | :-- | :------ |
| 0 | root | 2 | yes | 2,162 | none | q1 | q1 | 0 0 |
| 1 | library lift | 2 | yes | 6,814 | q1 | q4 | q2 | 1 3 5 5 |
| 2 | library lift | 3 | no | 18,968 | q2 | q9 | q3 | 1 3 4 6 7 9 10 11 11 11 |
| 3 | library lift | 2 | no | 6,814 | q1 | q4 | q2 | 1 3 5 5 |
| 4 | library lift | 3 | no | 18,968 | q2 | q9 | q3 | 1 3 4 6 7 9 10 11 11 11 |
| 5 | additive | 2 | no | 6,680 | none | never | q1 | 2 4 6 7 |
| 6 | tuple slot | 3 | no | 17,560 | q8, exact | q3 | q3 | 3 5 5 5 6 8 8 11 |
| 7 | tuple slot | 3 | yes | 17,562 | q2 | q3 | q3 | 3 5 5 5 6 8 8 11 12 |
| 8 | dependency | 1 | no | 4,574 | q1 | q3 | q2 | 3 4 4 |
| 9 | additive | 3 | no | 17,014 | none | q3 | q1 | 4 5 5 7 8 11 13 16 17 |
| 10 | conditional | 3 | yes | 17,790 | q8, exact | q3 | q3 | 4 5 5 5 8 8 11 13 |

Node 10 is the one that solves the task. Either form of the gate stops it at quantum 3. The score-only form also stops node 5 of the symmetric scan one quantum before its exact model.
