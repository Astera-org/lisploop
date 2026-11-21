# `lisploop` — Plan v2b: Audit of the Frame-Guard Kernel and a Topology-Geometry Re-Foundation

**Date:** 20 November 2026. **Tree:** branch `reflective` at `df33ed1`. **Status:** analysis only; no kernel code, test or library file was changed.

**Method.** Ten parallel audits, each with a narrow brief: four over the kernel source (frame and lift core; laws, algebra and anti-unification; search control and reflection; library, bootstrap and baseline), four over the planning trail (plans 1 to 5; plan 6 and the results record; the plan 7 family; plans 8 and 9, the plan 9 audit and the batteries document), and two literature surveys (symbolic and topological; geometric, neural and linguistic). The code audits ran about twenty scratch experiments against the kernel; their numbers are marked "measured" below and listed in Appendix C. The Lisp source was treated as authoritative over every document. Literature claims carry a confidence tag in Appendix B; most were checked at the level of an abstract or proceedings page, not a full read.

**Baseline at the time of the audit.** Kernel suite 222 tests, 938,737 checks, all pass (5.2 s). Milestone suite 40 tests, 186,771 checks, all pass (12.1 s). Plan 8 probes 71,782 / 212,096 / 34,067. Ledger fingerprint 236 tests, 419.7M work units.

---

## 1. Summary and Verdict

1. **The frame is half right. Keep the requirement; replace the row.** Stating each example's target as a Boolean program, and moving it through a decoder by substitution, is the best idea in the kernel and should survive unchanged. The *row* is the wrong unit. It is unary: it has no place for anything that connects two rows, two unknowns, or a row and its position. Every such connection (agreement, difference, order, derivation, coupling, shared latent, distance) has been added as a side field, a naming convention or a host function, which is where the incidental complexity you feel comes from (sections 3.1, 5).

2. **The index-frame gap is the oldest open item in the project, and it has that same cause.** Plans 1 and 2 were relational designs in which a row carried its index as data and list programs were index maps. Plan 3 replaced them in one step, for legibility and without a measurement, and deferred index structure by name. Plan 7 then designed the index frame, passed its milestone on rows typed in by hand, and never wired it. Today `lift-frame` computes the loop index and stores it in the one place programs are forbidden to read (section 3.2).

3. **An index frame and a fold are one structure that differs by one edge.** Both replicate a small pattern over an index set. A map or stencil reads other columns at offset positions; a fold or scan also reads *itself* at an offset, a carry. Autocorrelation tests for the carry, cross-correlation for the offset, and an algebraic law about the step (associativity, linearity) is what licenses adding or removing the carry. This is where your intro and your argument meet (sections 6.4, 7.4).

4. **The kernel already holds the pieces of a unified store, uncomposed.** Outcome vectors are exact coordinates for expressions; correction bits are a metric on values; observation buckets are equivalence classes; the library is a typed edge graph; the search tree is a DAG; substitution is a VM primitive. None is shared across jobs, and no two are joined (sections 3.7, 3.9).

5. **A single topology-geometry kernel is feasible, as one store with about six kinds of edge, not one kind.** The closest formal match for the datastructure is "finite base sets with named structure maps, plus columns over them" (attributed C-sets); for the engine, a relational equivalence store (egglog) with guards as contexts (colored e-graphs). No existing system combines them. The literature is equally clear about three limits: the controller (budgets, tentative narrowing) stays outside the store; truth stays in the exact store while geometry only ranks, retrieves and prices; and unifying the substrate does not by itself produce learning (sections 6, 7, 9).

6. **The bedrock notion of "close" should be conditional description length**: the bits of the shortest verified program from one thing to another under the current library. It is in the kernel's own currency, every distance comes with an executable witness (so "close" always implies "connected"), and distances shrink as the library learns. It is too expensive to be a first filter, so behaviour signatures, structural hashes and graph distances serve as its estimators. On flat versus nested: keep the topology nested and exact, keep the geometry flat and local to each space, and compare across spaces only through verified maps (sections 6.5, 6.6, 7.5).

7. **Bootstrapping is the weakest point, and a new datastructure does not fix it alone.** Of the library's 8,884 bits, 31% were found by kernel search, inside grammars that in 9 of 11 cases contain exactly the answer's operators. No library entry is about search. In the one test that checks, every trace-derived artifact can be removed with zero change in later work. The kernel never chooses its own experiments and records no attribution (sections 3.7, 3.8).

8. **Recommendation.** Do not refactor the 17,647-line kernel in place, and do not rewrite it wholesale. Run three cheap in-place experiments first, each testing one load-bearing assumption of the redesign: index coordinates as readable columns; a shared behaviour table that enumeration composes from; and an ablation harness that makes attribution a kernel operation. If they pay as predicted, build the new store as a small core beside the existing kernel, with the present test suite as its acceptance criterion (sections 10, 11).

What would change this verdict: if experiment E1 shows index tasks stay out of reach even with the coordinate available as a column, the problem is in search and not in representation; if E2 shows behaviour-class enumeration gives far less than the measured 22-to-1 and 38-to-1 ratios suggest, the case for a persistent equivalence store weakens considerably.

---

## 2. Direct Answers to Points in the Prompt

| Your statement | What the audit found |
| :---------------------------- | :------------------------------------------------------------- |
| "the kernel did not have provision for indexing frames" | Confirmed, and older than it looks: deferred by name in plan 3, designed and left unwired in plan 7 (section 3.2). |
| "this really should be doable with the tuple slicing machinery" | Yes, for *use*. `:at` and `:gather` consume an index, and the generic lift decouples an index frame posed by hand in 10k to 20k work. What is missing is generation as a proposal, totality for computed indices, and boundary handling. |
| "foldl [is] recursive and not facilitated by index frame generation" | True of the kernel today. Structurally they are one thing: replication over an index, with or without a carry edge (sections 6.4, 7.4). |
| autocorrelation and cross-correlation recognizers "apparently work in the kernel presently" | One exists: cross-correlation for a zero-padded forward shift, as a library battery that only tests load. It has no trigger and is tried on every miss. There is no autocorrelation, period, difference or recurrence recognizer (section 3.6). |
| "Propagator = transformer in the current kernel, I think?" | No. A stored *solver*, prepared for dispatch, is a propagator. A *transformer* is a code-to-code program, used only to lift element solvers through `map` (section 3.5). |
| anti-unification "is a form of quotienting and trivial lifting under substitution" | Agreed, and it can be made literal: anti-unification is constant-column detection applied recursively down term positions (section 7.3). Today it is host-only, and a pattern with holes is not an object-language value. |
| "lift has to be a synthesizer primitive just like substitution is" | Confirmed absent. Two plans rule the opposite as a design position. Prior art for lift as a store primitive exists (section 6.2). |
| topology "can be learned ... through experimentation (holding all but a few constant)" | The kernel never chooses its experiments: grids, grammars and bounds are caller arguments. One intervention test exists (`target-sensitive-p`). Dependence can also be read off a single recorded run (section 6.3). |
| guards as "calculated regions ... where the law or propagator does not hold" | Today a guard is an exact program or nothing, and discovery mostly finds single points. The mechanism that works computes the region from a failure set (sections 3.4, 7.6). |
| "there are a good number of guards" against repeated calculation | About nineteen, all quotients with separate canonicalizers. The behavioural one is not used where it would save the most: enumeration produces 38 candidates per distinct behaviour (section 3.7). |
| residuals are "a bit clunky"; are there "better options ... other than pricing in the original or ambient spaces"? | Yes. There are three exact rules for pricing in a generated space, one per kind of map (section 7.5). |
| "underwhelmed with the quantity of information that can be abstracted to the bootstrapped knowledge library" | Quantified: about 4,000 host lines of rule content against 2,771 library bits found by search (section 3.8). |
| "it's been the AI agents that are doing the majority of search" | Confirmed and measurable (sections 3.7, 3.8). |
| totality is a fine import, "but we also need to support learning" it by tolerating crashes | Learnable today: a 20-line harness over existing kernel functions learns the definedness guards of the partial primitives from evaluation status alone. The static analyzer cannot consume the one index frames need (section 3.4). |
| is the brain "flat"? | Flat substrate, structured addressing: a separate pre-structured index space bound to content (section 6.6). |

---

## 3. Findings: The Kernel as It Stands

Line references are to the tree at `df33ed1`. "Measured" means a scratch script was run against the kernel during this audit (Appendix C lists them); everything else was read in the source.

### 3.1 The frame, and what has accreted on it

A `row` is `(key, known, requirement)` and a `frame` is `(schema, rows, pairs, anchors, metric, edges)` (`frame.lisp:7-24`). Plan 3 specified only the row triple. Every other slot was added later, each when one experiment needed one relation among rows.

The row triple does three things well, and all three should survive any redesign:

- The target of each example is a *set*, written as a Boolean program over the target value. Pullback through a decoder is then plain substitution, `B(Z) = A(d(x, Z))`, and needs no inverse. Multi-valued and empty fibers survive: `Z / 2 = 1` keeps accepting 2 and 3.
- One metered VM checks everything, because a requirement is a program.
- A child problem has the same type as its parent, so synthesis can recurse.

What the row cannot say is anything that involves two rows, or two unknowns, because a requirement is unary in the row and a frame has one target. Each such relation has therefore been encoded separately, some of them several times:

| Relation | Encodings in the kernel today |
| :------------------- | :--------------------------------------------------------------- |
| "these rows take the same value" | `pairs` (soft, priced); `:equal` edges (hard); partition groups and `fiber-class` blocks; joins of rows with identical `known`; de-duplication inside `lift-frame` |
| "these rows differ" | `anchors` (soft); `:distinct` edges (hard) |
| "this row derives from row p at place j" | only the naming convention of the key, `(parent-key occ-idx)`, read back with `(first key)` (`frame.lisp:1062`, `1244`) |
| "these rows are neighbours" | `:persistence` edges; and, separately, the storage order of `frame-rows` |
| "this constraint ties two unknowns" | two formats of `coupled` list returned beside the frame; placeholder rows with `:unresolved` inputs |

Three consequences follow directly.

- `lift-frame` builds a fresh frame and drops pairs, anchors, edges, metric and availability (`frame.lisp:1269`). Structure does not survive the kernel's central operation.
- A frame's metric survives a pullback in four syntactic cases or after a 3 by 3 sampled invariance test (`frame.lisp:468-542`); otherwise the child has none. Hard edges survive only the identity decoder (`frame.lisp:562`).
- The only producer of `:persistence` and `:distinct` edges, `induce-row-order`, is called only from tests. `:equal` edges are created nowhere in the kernel. About 200 lines of `frame.lisp` have only test or milestone callers.

### 3.2 Where the index went

The absence of index frames is not an oversight of the last few weeks. It is the oldest open item in the project, and the documents record each step.

| When | Where | What was said or done |
| :----- | :---------- | :---------------------------------------------------------------- |
| 14 Oct | plan 1 | A frame is a table whose rows carry index tags; expressions hold relative references `(@ x k)`; six frame operators include re-index. "`x[i-1]` is the anti-unifier of `x[3]` at row 4 and `x[4]` at row 5." |
| 19 Oct | plan 2 | One flat store of tagged entries. "The list tasks ... need no list operators: their programs are index maps over tags." Measured: reverse found as `(- n (+ i 1))`, rotate as `(mod (+ i 1) n)`; 19,205 candidate index expressions cut to 39 and 8 by four or five rare rows. |
| 22 Oct | plan 3 | `Row = (key, known, allowed)`. The key is "an occurrence identifier, not an additional predictive feature". "Defer cubic finite differences. That example additionally needs index alignment, variable-length sequence handling, a scan decoder, anchors ..." |
| 29 Oct | results.md | "the Lisp fixture supplies the input grid and iteration order; those operations have not been packaged and priced as part of a sequence-generating model." |
| 6 Nov | plan 7 (recursion), Phase 3 | "Path A: Output / Index Conservation Lift" is exactly an index frame: lift outputs to rows `(x, j, n, I, y_j)`, find a conserved relation such as `(I + j) - (n - 1) = 0`, invert it to `(at X (- (- (length X) '1) J))`. The milestone passed on rows typed in by hand (`tests/recursion.lisp:553-560`), and the two stage functions have no kernel caller. The document header says "Complete". |
| 13 Nov | plan 8, section 3.4.1 | Bindings "remain strictly single-row"; cross-element context "enters exclusively through composable higher-order combinator lifts". |
| 19 Nov | `df33ed1` | Adds a 27th primitive `:mod`, a learned library function `:positions`, and a set-valued solver `:solve-at-1`. `frame.lisp` is unchanged. |

`lift-frame` cannot fill the gap, for a precise reason. It does compute the occurrence index of every call site, and it stores that index in the row *key*. The availability contract says a candidate program cannot read the key. So the loop index exists in the harness and is withheld from the programs that need it. DIP context repair cannot recover it either: it requires two distinct parent rows and adds a binding that is constant within one parent row (`nogoods.lisp:434-444`).

What the kernel can and cannot do today was measured (each run under one second of wall time):

| Task | Setup | Result |
| :-------------- | :------------------------------------- | :------------------------------------------ |
| `y[i] = x[i] + i` | decoder `(map (positions X0 0) Z)` posed by hand, then `lift-frame` | child rows `(i, xs)`, no coupling; child `(+ X0 (at X1 X0))` found at 10k to 20k work; generalizes to held-out input |
| `y[i] = x[i] + i` | automatic search, 8M work | no model; the only proposals were `(map X0 Z)` and `(if (= X0 '()) X0 Z)` |
| `y[i] = x[i] + i` | index list supplied as a second input column | solved automatically, 418,727 work |
| `y[i] = i` | recursive synthesis, no `:positions`, 8M work | no model |
| `y[i] = x[i+1] + x[i]` | `:map-adjacent` in the library | solved, 22,311 work |
| `y[i] = x[i+2] + x[i]` | same library, 1.5M work | no model |

So your instinct that this "should be doable with the tuple slicing machinery" is correct as far as *use* goes: `:at` and `:gather` already consume an index, and the generic lift already decouples an index frame when one is posed. Three things are missing.

1. **Generation as a proposal.** `library-decompositions` binds a combinator's primary sequence argument only to a frame input variable (`proposals.lisp:195-196`). An expression such as `(positions X0 0)` is never a candidate. Recursion cannot stand in: a one-input self-recursive function has nowhere to carry a counter, and nothing proposes an accumulator.
2. **Totality for computed indices.** `(at xs i)` with a variable index is never provably total, not under `(< i (length xs))`, not under both bounds, not as `(at xs (mod i (length xs)))`. Totality facts carry literal bounds only (`ast.lisp:718-735`), and `:gather` is never total. Every index-frame model is therefore second-class wherever totality is consulted: fold rules, let-sharing, conjunction simplification.
3. **Offsets and boundaries.** `(at xs (+ i k))` is expressible, but boundary rows error, so the model needs a guard or a shortened index list, and nothing proposes one. That lag 1 succeeds through a dedicated combinator while lag 2 fails is the cost: each offset needs its own hand-specified recursion schema today (lockstep zip, filter alignment, `:map-adjacent`, nested `:map`, and now `:positions`).

The caveat on the failed runs is that they are at the bounds and languages chosen for the audit; they were not tuned further.

### 3.3 Substitution is a primitive; lift and anti-unification are not

Matching, substitution, construction and application are VM primitives (`:code-match`, `:code-bind`, `:code-subst`, `:code-apply`, `:code-eval`), and pullback, model composition, hole filling and rewriting all share one matcher and one substituter. That part of the design is already what you describe.

Lift is different. "Run the decoder with an unknown function Z and report each call of Z as a row" is done by folding syntax, not by execution. `requirements.lisp` is in effect a second, symbolic interpreter with nine structural fold rules, and it has none for `:gather`, `:lookup`, `:concat` or `:mod`. Host policy is baked in: `flatten-lifted-conjuncts` special-cases the shape `:filter` leaves and commits to the YES branch; `select-active-fiber-rows` keeps the first two and the last occurrence per parent row and assumes argument 0 is the informative one. `congruence-close-code-evals` is not congruence closure: it substitutes ground calls equated to literals, to a fixpoint. There is no union-find anywhere in the kernel, and only atoms are hash-consed.

Anti-unification is host-only as well. A pattern with holes is not an object-language value (`:code-kind` has no hole case), so the synthesizer can run a substitution but cannot run, enumerate over, or learn a generalization step.

No document in the trail proposes lift as a primitive. Plan 7 states the opposite as a design position: "Frames, laws, certificates, and continuations are Lisp structs around them, not object-language programs."

### 3.4 Guards

A region of validity has at least five representations in the kernel that do not translate into one another: a Boolean program over the target (row requirements); a Boolean program over inputs (`if` conditions, law and solver guards); host fact lists for totality (`(:length id k)`, `(:nonzero id)`, with literal bounds only); row masks and label lists parallel to the rows; and status symbols (`:error`, `:unresolved`, cutoff). The only algebra over them is conjunction plus "folds to the literal `nil`". There is no disjunction and no implication test between two guards. A guarded rewrite fires only if its guard is literally true or syntactically present in the enclosing `if` conditions.

Guard discovery for laws is exact program synthesis of a support indicator. Measured on GF(5), one variable, operators `- / *`: 114 expressions give 16 distinct proper supports. Five of them are single points and carry 2,270 of the 2,390 equations; one is the real region `x != 0`; ten get no guard at the bound. Comparing all pairs to find the supports cost 454,795 work against 32,280 for the observations being compared. Plan 9's audit records the ceiling: the 57-bit divisibility guard is not found by exact search in 60,000,000 work.

The one mechanism that works at scale is the newest: the `:necessity` obligation computes a guard region from a solver's own failure set instead of searching for a program. That is the precedent to generalize (section 7.6).

Definedness guards can also be learned from failure today, with no new search code. A 20-line harness over existing kernel functions evaluates a partial expression on a handful of rows, takes "returned a value" as the hit mask, and calls the existing Boolean separator (measured):

| Expression | Learned guard | Work | Static analyzer accepts it |
| :------------------- | :--------------------------------------- | -------: | :------ |
| `(tail xs)` | `(if (= xs ()) nil t)` | 4,894 | yes |
| `(/ a b)` | `(if (= b 0) nil t)` | 8,284 | yes |
| `(at xs 0)` | `(if (= xs ()) nil t)` | 4,442 | yes |
| `(at xs 1)` | `(< 1 (length xs))` | 11,600 | yes |
| `(at xs i)` | `(if (< i (length xs)) (if (< i 0) nil t) nil)` | 24,077 | **no** |

The last row is the one index frames need, and the host totality table cannot use it, because it only knows literal indices. Learned knowledge is ahead of the mechanism that would consume it. A second limit showed up in the same experiment: the separator only admits atoms that have a value on every row, so a guard built from partial operators cannot be assembled. Guards need to be sequenced under earlier guards, which is the staged structure you describe. In the kernel proper, an observed error still rejects a candidate or refutes a law outright; the general guard-from-support search lives in `milestones/`, which the kernel never loads.

### 3.5 Laws and algebra

The lifecycle of a law runs through twelve stages (observation, bucketing, proposal, guard problem, guard search, validation, retyping, rewrite rule, operator fact, solver, propagator, transformer or functor). The kernel's *search* contributes at exactly three of them: enumerating expressions on a grid, synthesizing a Boolean guard, and synthesizing a witness expression. Everything else is host code moving one object into the shape another consumer wants. Of roughly 5,800 lines in this layer, about 1,050 (18%) only convert between views of one relation; 28% counting retyping.

To your question, **a propagator is not a transformer**:

| Term | What the code means by it |
| :----------- | :------------------------------------------------------------- |
| law | `(= L R)` under a Boolean guard; a passive statement |
| rewrite rule | one usable direction of a law, rebuilt and cached, compiled to a VM program |
| solver | for one operator and one argument position: a witness expression over the known arguments and the target, plus a guard (a FlashMeta witness function) |
| propagator | a solver entry unpacked for dispatch; it rewrites conjuncts `(= (op 'k T) 'c)` of a requirement |
| transformer | any program from code to code; used today only as ten `:functor/*` programs that lift an element solver through `map`, nine of them written by hand |
| template | three unrelated things: a polymorphic type schema, a remembered decoder with a hole, and an anti-unification pattern |

Six facts about this layer bear on the redesign.

1. **Discovered laws do not rewrite anything during synthesis.** `start-search` has a `:laws` filter, and no kernel caller passes it; only tests do. The controller's only algebra is solver propagation.
2. **Conservation-to-generator reorientation is not wired in.** `orient-conserved-quantity`, `solve-equality-symbolically` and `conserved-quantity-frame` are called only from tests.
3. **Nothing over `:int` is certified except four hand-written axioms.** With all eight batteries loaded, all 15 laws are conjectures, 11 with only sampled evidence; the integer rewrite library holds exactly the four `:int/cancel-*` axioms. The cause is structural: the only proof rule is exhausting a finite type. There is no induction, so nothing about integers or sequences can be more than a replayed conjecture.
4. **Discovery yields a closure, not a theory.** Over GF(3)^3 with `+`, 4M work gives 1,779 expressions in 26 behaviour classes and 1,753 validated laws, all consequences of two. Nothing minimizes the set. The bootstrap script then keeps the eight it wants with a host pattern matcher (`build-batteries.lisp:153-173`).
5. **The rewrite library is not a canonicalizer.** With validated commutativity and associativity of `+`, the 12 arrangements of `x0+x1+x2` reach 3 distinct normal forms. Deciding that no rule applies to a 5-node term costs about 26,000 work; observing all 74 expressions of that language on the full grid costs 34,391 in total.
6. **Reuse has lost to matching cost in every small measured case on record**: one rewrite rule saved 7,732 units and cost 545,921; propagation cut child search from 17,763 to 14,771 while total work rose from 19,338 to 21,514. Rules are a list scanned in order. The one recorded win needed an expensive forward context.

Orientation is baked into the kind system: `:law` and `:solver` are different kinds with different validators, caches and certificates, and each orientation of a relation is a separately searched, separately certified entry (eight for integer arithmetic).

### 3.6 Recognizers

You were told that autocorrelation and cross-correlation recognizers "work in the kernel presently". The accurate statement is narrower. There is exactly one, and it is a library entry: `:solve-shift-seq-by-correlation` in `library/sequence-shift.sexp`, a solver whose witness is `(argmax-corr X0 X1)` with a replay guard, registered as a metric decoder for `(:seq :int)`. It handles a forward shift with zero padding.

- Nothing triggers it. Once the battery is loaded (only tests and the bootstrap do that), it is tried on *every* miss of that type.
- A true shift is priced at 19 bits against 26 to 52 for the built-in correction, for 6,500 to 19,000 VM work. A non-shift costs 3,637 work to reject.
- There is no autocorrelation, periodicity, finite-difference or linear-recurrence recognizer anywhere in the repository. Plan 7 (higher-order) planned `:argmax-corr` after your prompt and shipped a first-element-pair solver instead.

The entry is nonetheless a good template for how such things should enter: a solver whose witness is an algorithm, paired with a decoder, so that the pair gives both a metric and a pullback (plan 8, section 3.1). What is missing is exactly what you named: something that decides when.

### 3.7 Search control and reflection

Four measurements from this audit describe the state of the reflective loop.

1. **Trace-derived artifacts do not move later search.** In `library-l4-continual-learning-curriculum-amortization`, the one test that asserts warm < cold, cold costs 20,076 and warm 16,687. Removing the priority predictor, the nogood schema, the DIP feature and the heuristic entry from the warm library leaves warm at exactly 16,687. Removing the four descriptor entries makes it *cheaper* (16,262). The whole gain is the `:map` function that anti-unification abstracted from two solved tasks.
2. **The learned priority predictor is degenerate.** Trained as the tests train it, the condensed program was `X0` in one run and `X1` in another: one raw feature. Ten of eleven training targets sat at the clamp ceiling. Held-out work was 7,816 with no predictor, with the learned one, with constant +500 and with constant -500.
3. **Priority has little to steer.** Jobs have 2 to 6 nodes. About 70% of a job's work is preparation and expansion, paid for every materialized proposal before a priority exists; about 23% is the prioritized child search.
4. **The enumerator never prunes by behaviour.** Behaviour classes are computed (observation buckets, keyed by outcome vector) and never fed back into enumeration. At 30 body bits: 12,139 candidates for 316 behaviours over two integer inputs (38 to 1), and 3,489 for 160 over GF(5) (22 to 1). Stage A and exact search then enumerate the same grammar on the same rows twice, each with a private table; the kernel has thirteen such call sites.

Around these sit three structural observations.

- **Messages expose only scalars.** Five readers over three claims, all integer or Boolean columns. The decoder tried, the bindings, the library entry used, the conflict, and the candidates are not reachable as data, so no learned rule can condition on *which decoder was tried*. No node reads another node's messages; branches communicate through host channels.
- **Every proposal generator emits the same record** (a decoder with a hole, bindings, a child language, a bound), and they are four moves written many times: project, lift over an index, partition by a guard, substitute. A declarative path for them exists (`:decoder-template` entries), yet the shipped batteries hold exactly one such entry among about a hundred, and the generators sit beside it as host code. There are four separate guard searches in this layer alone.
- **Policy is about ninety constants and two dozen gating predicates** in host code, and the test suite is tuned to them: changing the Stage A budget multiplier from 2 to 1, 3, 4 or 7 each breaks a test (plan 9 audit). The nineteen or so duplicate-work guards you remembered are all quotients ("do the work once per equivalence class"), each with its own canonicalizer, and the two that matter most (by normal form and by behaviour) are never joined.

### 3.8 The library and the bootstrap

The library holds 92 entries in eight files: 31 `:spec` entries and 61 primary ones. How the 61 came to exist was traced through `bootstrap/build-batteries.lisp` entry by entry:

| Origin | Entries | Bits | Share of bits |
| :------------------------------------------ | ------: | ----: | ------: |
| Expression found by kernel search | 32 | 2,771 | 31% |
| Derived by a kernel procedure from other entries | 12 | 1,052 | 12% |
| Syntax tree built by hand in the bootstrap script | 17 | 5,061 | 57% |

Nine hand-built functor transformers alone are 4,728 bits. No entry carries exhaustive or derived evidence. Six of the fourteen knowledge kinds never appear in the shipped library, and they are exactly the ones that record something about search: nogood schemas, DIP features, heuristics, relations, locality keys, functors.

The searches that do succeed are narrow, and three measurements show how narrow.

- **The grammar is the answer.** In 9 of the 11 function specs that carry an operator list, the list is exactly the set of operators in the answer, with no distractors. Every spec also fixes types, literals, constants, bound and budget.
- **Recursion shape is supplied.** With the hand-written `bootstrap/recursion-schemas.lisp` removed, 9 of 16 function specs still yield the intended function. Five fail even at 20M work: `positions`, `scan`, `map-adjacent`, `shift-seq`, `best-shift`. That is the index-frame and scan class. The kernel's own inductive split only ever proposes a self-call on the tail with the *other arguments unchanged*; a self-call with a changed counter, state or index is never proposed.
- **Specs under-determine, and nothing notices.** Two more specs pass without the schema and return the wrong function. Schema-free `foldl` is a tail-first fold that agrees only because every spec row uses subtraction (on the step `2a - b` it gives 79 where the library's gives 85). Schema-free `last-or` returns 5 for `(last-or '(5 7) 7)`. The schemas were acting as the inductive bias that hid this.

Law discovery has the same shape: the four observation searches propose 187 equalities, and a host pattern matcher (`law-operator-fact`) keeps the 14 it recognizes as identity, commutativity or associativity. Distributivity has no shape there and cannot enter.

The trend across the batteries work is that content was re-expressed beside the host code, not moved out of it. The kernel grew from 15,639 to 17,647 lines while the library went from 207 hand-written lines to 137 KB of generated s-expressions, and total test work changed by +0.46%. The 540 lines of fold rules in `requirements.lisp` and the 190-line descriptor prototype builder are still there; `constructors.sexp` and `descriptors.sexp` sit beside them, and three of the eight batteries are referenced by name nowhere outside the tests that load them. `library/` is also untracked, so a fresh clone fails `make test` until `make bootstrap` is run, and no test regenerates it (it regenerates byte-identically in 0.33 s, about 2.5M work).

By function, the kernel's 17,647 lines divide roughly as follows (a judgment estimate, good to about three points per row):

| Category | Lines | Share |
| :---------------------------------------------------------- | ----: | ----: |
| Trust: VM, codec, ledger, typed syntax, totality, evidence, certification | 2,356 | 14% |
| Search control and scheduling | 4,571 | 28% |
| Rule content and recognizers that could be library entries | 2,975 | 18% |
| Frame, requirement and rewrite calculus (pullback, lift, fold walker, anti-unification, propagation) | 2,834 | 17% |
| Plumbing: store, persistence, loader, retyping, messages | 3,789 | 23% |

Adding the 340 lines of totality rules, the 355 lines of recursion schemas and about 300 lines of hand-built syntax in the bootstrap script gives roughly 4,000 host lines of rule content. Against that stand 2,771 library bits that the kernel found. Lines and bits are not commensurable, but on any reading well under a tenth of what the system knows about its own language is in the library as something the kernel discovered, and nothing in the library is about search.

### 3.9 Geometry

The kernel's geometry is thin and of one kind. There is one ambient correction code per type (signed difference on integers, centred modular difference on GF(p), componentwise on tuples, positional on sequences) or one metric supplied per frame, and it is always a function of two *target values*. There is no distance between rows, between inputs, between expressions, between frames or between library entries. Sequence corrections assume positional alignment, so a shifted sequence is all-different unless the shift battery is loaded.

Reading the plan 8 and plan 9 record against the code gives a sharper statement: **the topological half of those plans is wired into search and the geometric half is not.** Pullback, lift, product join, hard edges, availability and symbolic unwinding are used by search. Row-order induction, compositional addressing, persistence edges, conserved-quantity orientation, coordinate probes and message frames are each built, tested in isolation, and called only from tests. The search loop has one way to consume a new idea, a proposal that yields a child frame, and things that are not proposals (an ordering, an address, a metric, a trace) have nowhere to plug in.

Two pieces of a geometry do already exist and are never composed. Expressions have exact coordinates: their outcome vectors on the rows. Values have a metric: correction bits. The distance between two expressions (the sum over rows of correction bits between their outcomes) is never formed, although the special case "distance from an expression to the requirement" is precisely the Stage A residual.

### 3.10 Growth

| Point | Kernel lines |
| :------------------------------------ | -----------: |
| Before plan 8 (`54acfa3`) | 12,472 |
| After plan 8, phases 1 to 4 | 13,771 |
| After merge with `main` and audit | 15,154 |
| After exact closures | 15,257 |
| Now (`df33ed1`), 25 files | 17,647 |

Each plan in this stretch set kernel shrinkage as a goal. Plan 8 estimated 800 to 1,050 removable lines and removed about 215. The independent implementation of plan 8 on `main` was 11,906 lines, so the growth was not forced by the plan. Plan 8 recorded 25 numbered departures; by this audit's reading 9 were budget or scheduling interactions, 7 were places the frame abstraction did not carry the planned structure, 5 were soundness, and 4 scope. Plan 5 had projected about 900 lines for the M1 to M4 scope.

---

## 4. Nuggets from the Planning Trail

These are the ideas in the plan documents that bear most directly on the redesign, each checked against the current source by search. Quotation marks are verbatim. "Lost" means the idea was in a plan and no trace of it is in the kernel.

### 4.1 Structure: frames, indices, fibers

| Nugget | Source | Status today |
| :----------------------------------------------- | :--------- | :-------------------------------- |
| "`x[i-1]` is the anti-unifier of `x[3]` at row 4 and `x[4]` at row 5." A relative reference *is* the generalization. | plan 1, 5.5 | Lost with index tags. This is the index frame, stated as anti-unification. |
| Factorization is "the right-inverse of Apply" over three carriers: terms (Apply is substitution), tables (Apply is `gather`), requirements (fiber intersection). | plans 5 and 6 | Three separate implementations (`unify.lisp`, `frame.lisp`, `fibers.lisp`). The `gather` line is the tuple-slicing route to index frames. |
| "A recurrence is a cycle in the program DAG that becomes acyclic once it is unrolled along the axis, and its unrolled trace is a frame." | plan 1 | Lost. It is the carry edge of section 7.4. |
| "No column is designated as input or output. All directions are searched." All three orientations of `+` were found from one shuffled store: "The solve rules are simply the other directions of the same relation." | plan 2 | Narrowed: one direction per frame; eight separately certified solver entries for integer arithmetic. |
| A pattern "matches only where all of its templates exist", so boundary rows become initial conditions structurally. | plan 2, 4.5 | Lost. Boundaries now need a guard that nothing proposes. |
| Pullback of a predicate "uses forward execution only; it does not compute or enumerate compatible z values." | plan 3 | Implemented. The load-bearing idea of the frame layer. |
| "The information a computation destroys is the mean log size of the fiber its input lands in": $H(X) = H(f(X)) + E \log \lvert f^{-1}(f(X)) \rvert$. Checked: GF(59) squared holds 11.77 bits and `+` destroys 5.88. | plan 2, 1.1 | Never implemented as a measurement. The cleanest statement of "computation is projection; lift supplies the fiber index". |
| "Every correspondence that is computed (a join on values, a sort, an EM assignment) belongs to the model and is paid for in bits." | plan 2 | Honoured for sort keys only. |
| A meta-function "with b bits of freedom is constrained by O(b) scalar fiber observations." | plan 7 (M9) | Built as the fiber window in `lift-frame`. |

### 4.2 Symmetry, laws, algebra

| Nugget | Source | Status today |
| :----------------------------------------------- | :--------- | :-------------------------------- |
| "A symmetry of the data is a pair (sigma, tau) ... with x(sigma(i)) = tau(x(i))." An arithmetic progression is (shift, +2); a palindrome is (reflect, id). | plan 1, 5.10 | Narrowed to invariance under a supplied transition (`pairs`, `anchors`). |
| Joining both argument orders on the shared instance tag gives commutativity at once: "That is how a connection becomes a shared variable." | plan 2 | Replaced by bucket collisions. This was a topological discovery of a law. |
| Laws save work, not bits. Commuted pairs are exactly 1/p of value-joined pairs; coding them loses 2,447 bits at p = 59. "A law on a finite domain is a theorem about the simulator: its truth is no news about any data." | plan 2, 1.5 | The three cost accounts were kept; the Levin-style derivation account was not. |
| Anti-unify equivalence classes, not representatives. The representatives of the GF(p) multiplication table generalize to a bare variable; aligned bucket members give `(* ?K c)`. | plan 2 | Not built. Buckets keep their members but no aligned generalization exists. |
| An e-graph is "a few hundred lines, not a heavy import", to be adopted on three triggers: collection failures above 10%, over-general generalizations, a non-confluent law set. | plan 1, 7.6 | None was ever measured as a trigger. Plan 2 observed the second. This audit measured the third (section 3.5, item 5). E-graphs were then deferred five more times and dismissed once in a single clause. |
| Normalizing by validated laws before anti-unification takes a template from 5 holes to 2. | plan 6 | Implemented for library anti-unification only. |
| The coarsest template wins: one global pattern compressed the law corpus by 33.9%; shape-grouped templates and a dictionary were worse. | results.md | Measured. Nothing derives a basis of independent laws. |

### 4.3 Geometry and spaces

| Nugget | Source | Status today |
| :----------------------------------------------- | :--------- | :-------------------------------- |
| "A metric and a decoder shell are two views of one correction code: the shell reconstructs a value from a residual, and the metric prices that residual before it is synthesized." | plan 7 | One instance (the shift decoder). The best single sentence on how geometry enters. |
| A recognizer is a solver paired with a decoder; the pair gives a metric for Stage A and a pullback for Stage B. | plan 8, 3.1 | One instance. |
| Re-indexing creates a space: `1,10,2,20,3,30` re-indexed by `(i mod 2, i div 2)`. Candidates "come from structure the expansion has already found: a parity guard proposes `i mod 2`". | plan 1, 3.4 | Never built. The earliest concrete form of "the engine makes spaces where needed". |
| "A constant difference defines the successor, and a successor is what makes the difference constant." Orderings are searched as sort keys, never as permutations. | plan 2 | Sort-key half built (`induce-row-order`), unwired. |
| Fiber coordinates "chosen any other way make the residual column look random however regular the lift is." | plan 2 | Implicit only. Section 7.5 gives the exact rule. |
| Incommensurable child spaces: children under different decoders can only be compared by recomposing to the root. | plan 7 | Implemented as full-path price; the plan 9 audit shows it "compares unlike quantities". |

### 4.4 Reflection and language

| Nugget | Source | Status today |
| :----------------------------------------------- | :--------- | :-------------------------------- |
| "Errors are data, and guards are learned from them." | plan 2 | Reversed in practice: an error rejects a candidate or refutes a law. |
| "Chronology is not justification": ancestry records what happened; a certificate establishes what must follow. | plan 3 | Kept. A true invariant. |
| "Sampled evidence can propose and never eliminates." | plan 8 audit | Kept. A true invariant. |
| "Structural scope (what free constants or decoders a rule depends on) and epistemic grade (proved versus empirical) get conflated." | batteries document | Unresolved. Section 7.7 proposes that scope is a context and grade sits on the edge. |
| The utility problem: learned rules can make the system slower. Measured: stored templates raised warm work on `inc-list` from 19,147 to 48,573. | plans 2 and 7 | Demotion implemented; the cause (no index, so every rule pays a match) is not addressed. |
| Two kinds of address: structural and compositional, where decoding "costs work proportional to the term"; and behavioural, a fingerprint "much like a linear code". | plan 2, 1.9 | Neither built. Descriptors took a third route: a hand-enumerated menu of concepts. |
| An accepted pattern becomes one symbol for later matching: vocabulary is what amortizes matching. | plan 2 | Not built as such. |
| "Testing is also a way of better knowing what you know." | batteries prompt | `:spec` entries exist for the bootstrap curriculum; no host test was converted. |

---

## 5. One Cause Behind the Recurring Symptoms

Read end to end, the plans return to the same problems under different names. The list below gives each with the places it recurs.

- **Coordinates live in the harness and are smuggled back as columns one mechanism at a time.** Row key, occurrence index, call path, block label and physical row order are each computed by host code and withheld from programs. Each time a program needed one, a mechanism was added to hand it over: `context-label-frame`, `dependency-proposals`, DIP bindings, `:locality-key`, a hand-defined `map-indexed`, and now `:positions`.
- **One mechanism per shape.** Map, right fold, left fold, filter, lockstep zip, adjacent stencil, filter-map and two-dimensional nesting each needed its own totality case, fold rule, recursion-shape classifier case, descriptor and often its own decomposition.
- **Linkage between rows is per-transform bookkeeping.** `pairs`, then `anchors`, then computed linkage, then `metric`, then typed `edges`. Each transform must decide whether to carry them, and most drop them.
- **Built, tested in isolation, never wired**, always on the geometric or reflective side (section 3.9).
- **Budgets stand in for dependency structure.** The arity-squared Stage A multiplier exists because irrelevant inputs enter every tier of the grammar. Something that said which inputs a target can depend on would remove the need. Instead the suite is tuned to the constant.
- **Unlike quantities are compared.** A lifted child has one row per call site, so its residual carries more row names than its parent's, and "correct lifts look non-improving". The only common currency is at the root, reached by recomposing.
- **Sharing is by exact equality only.** The scope cache matches identical frames within one job; nogoods match identical keys; congruence is confined to one lift. Nothing persists across branches or jobs.
- **Latent and coupled state is deferred in every plan** (probe 7 of plan 8, section 5.4 of plan 9, `:fix-seq`). It is the same problem as a left fold: a chain of unknowns linked by one unknown function.
- **Correspondence for unordered data** has been open since plan 1.
- **Milestones are certified on supplied controls.** Path A on a hand-built index frame, the indexed-map control on a hand-defined combinator, locality on supplied keys, every lift and view on a supplied decoder. The plan bodies say "supplied" honestly; the headers say "Complete".
- **Exact ledger parity gates generality.** New behaviour is repeatedly restricted (UIP only on lifted nodes, for instance) to keep older jobs' work figures identical to the unit.

All but the last two have the same shape. Each is something that connects rows to one another (a coordinate, a correspondence, a class label, a distance, an action) or connects one search step to another, and `(key, known, requirement)` has no home for it. So each was deferred, or added as a side field, or written as host code around the frame.

Two facts about how this came about are worth holding on to. First, the row-predicate frame was chosen at plan 3 on stated grounds of legibility ("every demonstration should admit a short trace") and to avoid "a universal graph-matching engine". Its real technical gain was the predicate pullback, and that gain does not depend on the row being the unit. Second, the frame was specified against a prompt that had no geometric requirement: the text on metrics, relaxed partitioning and constructed spaces entered `prompt4.md` on 4 and 5 November, after all of plans 1 to 5. The datastructure predates half of what is now being asked of it.

---

## 6. Eight Perspectives on the Same Question

Each lens below answers "what is the fundamental structure?" from a different literature, says what it buys and where it stops. Citations and confidence tags are in Appendix B.

### 6.1 The relational view: a frame is a small database

Attributed C-sets (Patterson, Lynch and Fairbanks, 2022) are one generic datastructure for graphs, hypergraphs, wiring diagrams and data frames: a small schema of object types and arrows, a finite set for each object, a function for each arrow, and typed attribute columns. In those terms a frame is an instance of a small schema, `pairs` and `anchors` are arrows, and an index frame is simply a frame whose base set is a set of positions. Functorial data migration (Spivak, 2012) then supplies three operations along any map between base sets, and they read as your vocabulary:

- $\Delta$ (pull back): reindex, gather, lift a column to a finer base;
- $\Sigma$ (push forward by union): quotient, group, existential image;
- $\Pi$ (push forward by product): the fiberwise meet; applied to a requirement column it is exactly the test that a block of rows can share one latent value.

This is the closest existing datastructure to what you describe, with generic double-pushout rewriting already implemented over it. It stops in two places. It says what to compute once the map between bases is given; *finding* the map (which rows share a latent, which positions correspond) is the searched part. And moving a requirement through a decoder is not one of the three: it is pullback of a predicate along a term, a second fibration (Mellies and Zeilberger, 2015). So two fiber structures are in play, data over index shapes and predicates over values, and the kernel has only ever had the second.

### 6.2 The equivalence view: laws are merges, guards are contexts

An e-graph stores equivalence classes of expressions with congruence maintained automatically. Three recent extensions line up with three of your requirements.

- **Guards.** Colored e-graphs (Singher and Itzhaky, 2023) keep one base congruence shared by all assumptions plus a thin layer per assumption. A law that holds under a guard is a merge in that layer. Tentative narrowing by a non-unique solver, which the kernel handles by cloning a fallback frame, is also a layer.
- **Substitution.** Slotted e-graphs (Schneider et al., 2025) parameterize a class by its free variables and make every reference carry a renaming. A class with slots is "an expression lifted to independent contexts".
- **Lift.** Lifting e-graphs (Zucker, 2026, workshop stage) make weakening into a larger context a built-in operation with its own union-find. This is literal prior art for "lift has to be a primitive".

Rule inference by experiment is the same lineage: Ruler and Enumo enumerate terms, fingerprint them by outcome vector, and keep a *minimal* rule set by testing derivability, which is the step the kernel lacks (1,753 laws where two suffice). Chompy (2026) adds implication reasoning between guards. Babble anti-unifies classes instead of representatives, the nugget from plan 2.

What this view does not give: evidence grades, definedness, pricing, or any account of row-indexed data. Extraction of the cheapest term with sharing is NP-hard and not approximable within a constant, so it must be anytime. Associativity and commutativity run as rewrite rules blow up exponentially; the known fix is to change the node encoding (multisets), which means a learned law should be allowed to change the representation.

### 6.3 The propagator view: a requirement is a cell of partial information

In propagator networks (Radul and Sussman), cells accumulate partial information by a monotone merge, and contradiction carries its premises. A row requirement is such a cell: the lattice of allowed sets under reverse inclusion, merge by intersection, bottom unconstrained, top empty. The kernel's `:necessary` contract is a sound over-approximation in that lattice. Narrowing by a non-unique witness is *not* monotone, which is the formal reason it needs a fallback, and why it belongs in a context rather than in the cell.

The sheaf reading of constraint satisfaction says the same thing geometrically: a solution is a global section, propagation prunes local sections, and "every local piece is satisfiable but they do not glue" is the exact content of a conflict that propagation cannot see. With metric stalks (Robinson, 2020), the distance by which local data fail to glue is the *consistency radius*, a definition of residual that works in any generated space. No published work links this to clause learning; that link would be ours to make.

Dependence itself need not be found by intervention. For one recorded run, forward and backward slicing form a Galois connection between parts of the input and parts of the output (Perera et al., 2012): the trace yields the least input needed for each output part. That is "hold all but a few constant" obtained from a single metered execution.

### 6.4 The array view: an index frame is a tabulated function

Array languages have had the word and the mechanism for a decade. In Remora, every array is a *frame* of *cells*, and a function is implicitly lifted over the frame. Gibbons (2017) isolates the structure needed: a container whose positions form a fixed index type, with `tabulate` (build from a function of the index) and `index` (look up) as inverses. "Generate an index array, then use it to access data or feed an offset expression" is tabulate followed by index. Dex makes index sets first-class types; Halide defines whole pipelines as pure functions of integer coordinates with offset references; the polyhedral model treats iteration domains as integer polyhedra (guards), accesses as affine maps (offsets and strides), and dependences as relations between iterations. In that model a constant dependence distance is a lag, and an empty carried-dependence set is the law that licenses a map in place of a fold.

The relation between recursion and index form is also settled work. The third list-homomorphism theorem (Gibbons, 1996) says a function computable as both a left and a right fold is a homomorphism over an associative combine, and so can be evaluated over any partition of the index. Farzan and Nicolet (2017) automate it: they search for the combine, and when none exists they *lift* the loop by adding auxiliary accumulators until one does, with the need for an accumulator detected from a failed attempt. Over a finite field, Berlekamp-Massey recovers the coefficients of a linear recurrence exactly from twice as many terms as its order. Szalinski (2020) is the nearest published system to what you want: inside an e-graph, solvers turn flat lists into maps and folds over index ranges and solve for the index function algorithmically.

The common shape: an algebraic law about the step is the certificate that a carry edge can be removed or introduced. What nobody has published is description-length induction of the index *function* from a flat execution graph; existing graph-grammar induction stops at "repeat n times".

### 6.5 The information view: distance is conditional description length

Information distance (Bennett et al., 1998) is the length of the shortest program that transforms one object into another. It is a metric up to a logarithmic term and it is universal: every other computable similarity is bounded by it up to a constant. With general-purpose compressors the practical record is mixed. In this kernel the compressor is the synthesizer plus the library, and the distance is bounded above by the shortest *verified* program found. Three properties then hold by construction: composing found programs gives the triangle inequality; every distance has an executable witness; and distances shrink as the library learns. The asymmetry between the two directions is information too: it is the projection and lift direction. One targeted search found no prior use of this as the geometry of a growing program library, so it should be treated as new and unproven.

The same literature answers your question about pricing residuals in generated spaces.

- If the map between the ambient and the generated space is a bijection on the data, code length transports exactly; there is no Jacobian term in the discrete case (integer discrete flows).
- If it is many-to-one, the residual *is* the fiber coordinate and is priced by a conditional code.
- If the latent is under-determined (fiber labels up to permutation, several equally good witnesses), the arbitrary choice must be refunded, or latent-variable models are overcharged by up to the log of the symmetry group size (bits-back coding).

Two refinements follow. The price of a generated space should be the log count of settings the data can tell apart, not the bit width of its coordinates (Fisher-volume forms of MDL), which removes dependence on how the space happens to be coordinatized. And a model and residual split is finished when the residual is incompressible given the model (Kolmogorov structure functions): operationally, recurse on the residual until synthesis on it finds nothing.

### 6.6 The flat-space view, and the brain

Flat vector spaces do some things very well: content-addressable storage of exponentially many patterns, representing m sparse features in O(log m) dimensions, shallow binding of a few entities through reserved "binding ID" subspaces, and taking on the spectral geometry of whatever graph the context supplies. The last was shown directly in 2025: given random walks on an arbitrary graph, a language model's representations of the node names reorganize to the graph's layout. That is your conjecture that a transformer "changes context to change the composition", observed.

They also have measured limits, and the limits are exactly the things a nested store is for. *Computing* in superposition compresses only quadratically where storage compresses exponentially. One attention layer cannot compose functions over large domains. Compressed binding accumulates noise with nesting depth and needs a discrete clean-up memory after every unbinding. Regions closed under intersection are not closed under union: a disjunction of boxes needs dimension proportional to the number of entities, so every working system keeps unions symbolic.

The brain is not a counter-example to nesting. The current picture is a flat substrate with *structured addressing*: grid modules provide a separate, pre-structured index space with group structure (a product of cyclic codes, like a residue number system), and content is bound to those addresses. The Tolman-Eichenbaum machine factorizes "where in the structure" from "what is there" and binds them only in memory. Clone-structured cognitive graphs lift aliased observations into latent states by splitting a state and learning by EM which clone is active in which context, which is your pillar 5 implemented; "making a space" there is a discrete split inside a fixed pool, and geometry is derived from the learned graph afterwards.

The design consequence is that because the kernel stores nesting exactly, its geometric side never has to *represent* nesting. It only has to answer "which entries are near this one" and "how large is this residual". Both are shallow jobs for which cheap, non-learned vectors suffice.

### 6.7 The language view

Categorical compositional semantics is the one formal account in which your three word classes are literal: like-terms are states (vectors), modifiers and analogies are maps on one wire, and action terms are gates across wires or processes that introduce a wire. Grammar is a string diagram, which is a hypergraph, and meaning lives in the boxes: topology from grammar, geometry inside. Its empirical record is toy-scale and its parameter count explodes with type order, so it is a vocabulary for the design and not a method.

The practical evidence is from library learning. LILO (2024) found that giving learned abstractions names and descriptions improves *search*, not only readability. That supports pillar 9 directly, though it relied on a language model for the names; nobody has shown a self-bootstrapped vocabulary doing the same.

For learning which entry to try, the best record in the data-scarce, update-after-every-solution regime belongs to instance-based learners: k-nearest-neighbour and naive Bayes over sparse symbolic features, as used for premise and tactic selection in theorem provers, are competitive with and complementary to neural guidance. Naive Bayes weights are log-odds, that is, bits of evidence, so they sit natively in a description-length ledger.

### 6.8 The sceptic's view

There are serious arguments against unifying under one hypergraph, and the design in section 7 is shaped by them.

- **Density.** Lenat and Brown (1984) explained why AM worked and EURISKO struggled: AM's discoveries came from mutating short Lisp forms in a domain where small syntactic changes were often meaningful, and the same was not true of heuristics. A uniform substrate is not uniformly learnable. Each level needs its own small schema so that generalizing over it means something.
- **Track record.** OpenCog has had programs, data and rules in one reflective metagraph for over a decade without a published demonstration of compounding discovery.
- **Monotone stores versus control.** The successful engines unify *monotone* systems. Budgets, reserve schedules, tentative narrowing and deletion are not monotone, and the literature keeps them outside the store.
- **Cost of generality.** Stitch beats e-graph library learning by orders of magnitude when no theory is needed. Matching cost grows with pattern width. General hypergraphs have no cheap canonical form. And in this project, reuse has already lost to matching cost in every small measured case.
- **Hybrids fail when geometry is asked to carry truth.** Graph-plus-vector retrieval often loses to plain vector retrieval on simple queries; learned sheaf maps show no reliable benefit over identity maps. Every successful system the survey found (AlphaGeometry, DreamCoder, BUSTLE, the theorem-prover learners) keeps truth in an exact engine and lets geometry only rank or propose.
- **The flat alternative is live.** CompressARC (2025) solves a fifth of ARC-AGI-1 with description length as the only objective, gradient descent as the only search, and no pretraining. If sample efficiency were not a requirement, that would be an argument for not building the hybrid at all.

The net reading is one schema language and one store with a handful of edge kinds; lift, substitution and guard as store primitives; scheduling and budgets outside; and no expectation that learning follows from unification itself.

---

## 7. Synthesis: A Topology-Geometry Kernel

This section proposes a concrete structure. It is a synthesis of the audit and the literature, not a tested design; section 9 lists what could be wrong with it and section 10 the experiments that would show it. In one sentence: **it is the relational store of plans 1 and 2, carrying the predicate requirement of plan 3, with equivalence classes and contexts added, and with description length as its geometry.**

### 7.1 Principles

1. **Truth lives in the exact store.** Anything a result depends on is a verified edge. Geometry ranks, retrieves, proposes and prices; it never decides.
2. **One store, a few kinds of edge.** Data, expressions, executions, search and library share one schema language. Each level keeps its own small schema, so that generalizing over it is meaningful (the density argument of section 6.8).
3. **Whatever a rule could condition on is data.** The index of an occurrence, the decoder that was tried, the error that occurred, the entry that was used.
4. **Structure belongs to shared objects, not to containers.** A metric belongs to a space that many problems reference, an index to a base set, an equality to a context. Then a transform cannot drop them, because it does not own them.
5. **The controller is outside the store.** Agenda, budgets and the reserve schedule read and write the store and are not part of it.
6. **The invariants that are really invariants are kept** (section 8).

### 7.2 The store

Four kinds of object.

- A **base** is a finite set of *sites* with named **structure maps** out of it, to another base or to itself. A map may be partial. Examples: the rows of a task; the positions of the sequences in those rows, with a map `row` back to the rows and a partial map `next` to the following position; the call sites of an unknown function under a decoder; the subterm positions of a corpus of expressions; the nodes of a search; the entries of the library; the labels of a partition.
- A **column** over a base assigns each site a **cell** of some type. A cell holds partial information: a value; a set of allowed values written as a Boolean program (today's requirement); nothing yet; or an outcome status (an error class, a cutoff).
- An **expression class**. Applications are hash-consed. An expression evaluated over a base *is* a column, its behaviour. Two expressions belong to one class *in a context* when their columns agree there.
- A **context** is a sub-base cut out by a Boolean column, together with any assumptions in force. Contexts are ordered by implication. A guard is a context.

Six kinds of edge.

| Edge | Connects | What it carries |
| :------------- | :-------------------------------- | :------------------------------------------ |
| application | operator and argument columns to a result column | the topology of computation |
| structure map | a base to a base | the topology of data: what a lift or a projection runs along |
| equality | two cells or two classes, in a context | conservation, with a grade (observed, required, hypothesized, certified) and a reason |
| constraint | any number of cells | a Boolean program that must hold: requirements, coupling between unknowns |
| derivation | a problem, a decoder and bindings to a child problem; a candidate; a conflict and its explanation | the search DAG, with its labels as data |
| space | a column to its type-in-context and code; a space to a space | geometry (section 7.5) |

A small picture, for the task "each output element is the input element plus its position":

```
base R  (rows)        columns:  x : seq int        y : seq int, required
base P  (positions)   maps:     row  : P -> R
                                next : P -> P      (partial: undefined at the last position)
                      columns:  j    = ordinal of the site within its row
                                x@   = (at x j)    x pulled back along row, read at j
                                y@   = (at y j)    the requirement, pulled back the same way
problem on P:  find e with  e(j, x@) = y@          answer:  (+ x@ j)
```

The hypergraph is the *semantics*. The implementation should be columnar tables, as in the acset libraries, not a pointer graph: a column is an array, a structure map is an integer array, a behaviour is an array of values. That is also what makes the recognizers of section 7.4 vectorized arithmetic and not search.

### 7.3 Six moves, and what they generate

These are the operations that should be synthesizer primitives, on the same footing as substitution is now.

1. **Apply.** Run an expression over a base on the metered VM and record the result column, including outcome status.
2. **Substitute and match.** As today.
3. **Reindex (lift).** Pull a column back along a structure map. This includes *generating* a base: the positions of a sequence column; the call sites of an unknown under a decoder; the subterm positions of a code column; the product of two bases; a sub-base by a predicate; a quotient by a column.
4. **Aggregate (project).** Push a column forward along a map with a fiberwise reducer: all-equal (the conservation test, and the quotient); collect in order (the inverse of positions); meet (intersect constraints); reduce by an associative operator.
5. **Merge and split.** Assert two classes or cells equal in a context, with a grade. Split a context by a Boolean column.
6. **Price.** The bits needed to encode a column given a predicted column, under the code of its space.

Everything in the present kernel that the audit classed as mechanism or as rule content can be written with these. The correspondence is the core of the proposal:

| Today | In the store |
| :------------------------------- | :--------------------------------------------------------------- |
| `pullback-frame` | substitute the decoder into the constraint (move 2); unchanged |
| `lift-frame` | generate the call-site base by *recorded execution* with a logging oracle, then reindex the requirement along it |
| index frame | generate the positions base; reindex |
| quotient, lookup and partition models | quotient a base by a column; aggregate all-equal; gather |
| anti-unification | on a code-valued column: aggregate all-equal on the head; if constant, reindex to the child positions and recurse; if not, the column itself is a hole, and equal columns share one hole |
| observation buckets, law proposal | merge classes whose columns agree on a full-domain base |
| guard of a law | the context in which two classes coincide; its complement is an ordinary Boolean target column |
| solver, propagator | the application table read with a different choice of key columns: unique is a functional dependency in a context, set-valued is the fiber listed, necessity is the fiber empty |
| invariants (`pairs`, `anchors`) | a column equal to itself reindexed along the transition map, and non-constant across orbits |
| a symmetry (sigma, tau) | a column reindexed along sigma equals tau applied to the column |
| fibers, latent labels | search for a map from rows to labels whose fiberwise meet is satisfiable |
| DIP repair | add a column that separates colliding sites |
| products, coupled conjuncts | several unknown columns sharing constraint edges |
| nogood, UIP | a constraint edge to false with its explanation; anti-unify explanations |
| descriptor | a Boolean column over a base of problems or entries |
| message, trace row | a site in the base of search nodes, with the decoder as a code-valued column |
| scope cache and the other duplicate-work guards | one canonical identity: hash-consing plus class membership |

Three of these lines deserve a sentence each.

*Anti-unification* becomes the same algorithm as constant-column detection, run down the positions of a term. That is your "quotienting and trivial lifting under substitution" made literal, and it explains the plan 2 observation that anti-unification should act on classes: the all-equal test on the head is a test in the equivalence store, not on syntax.

*Reorientation* stops being a conversion. One recorded table of `(k, z, c)` with `c = op(k, z)` serves the forward direction keyed by `(k, z)` and the solver keyed by `(k, c)`. Whether that second reading is a function, a finite set or empty on a region is a measured property of the fiber. The three flags and three proof obligations on today's hand-oriented solver entries are that measurement.

*Lift by recorded execution* replaces the symbolic second interpreter. The VM already has half of it: a function backed by an oracle table returns stored values and raises `:unresolved` on a miss. A recording mode logs each call and returns a placeholder that flows through constructors untouched; equating the output with the required value then gives each placeholder its constraint. A placeholder demanded by arithmetic is exactly the coupled case, where the symbolic path is still needed. So this covers the decoupled majority and leaves coupling to constraints over several unknowns, which the store can now hold directly.

### 7.4 Index frames and recursion as one structure

On the positions base P of section 7.2, every sequence computation is a *plate*: one small pattern replicated at each site. The patterns differ only in which columns they read and where.

- **Map:** the result at a site reads other columns at the same site.
- **Stencil, offset, zip:** it reads other columns at sites reached by `next` or `prev`, or by a computed map such as "position `n - 1 - j`".
- **Scan, fold:** it reads *its own column* at `prev`. That self-reference is the carry.

So the difference between "facilitated by index frames" and "recursive" is one topological fact about the dependency graph of columns, taken modulo the base: whether a column has an edge to itself. Plan 1 had it in a sentence: a recurrence is a cycle that becomes acyclic once unrolled along the axis.

This gives the recognizers of your intro a home and a uniform shape. Each is a test of conservation under a structure map, computed on arrays:

- period k: the column equals itself reindexed along `next` applied k times (the autocorrelation peak);
- shift k between two columns: one equals the other reindexed along `next` k times (the cross-correlation peak);
- arithmetic progression: the column minus itself at `prev` is constant;
- linear recurrence over a field: Berlekamp-Massey on the column, which returns the carry's coefficients;
- reverse, rotate, stride: a conserved relation between two ordinals, such as `(I + j) - (n - 1) = 0`, which is the plan 7 Path A that was never wired.

Each such recognizer is a library entry of the form plan 8 already identified: a solver whose witness is an algorithm, paired with a decoder. "Knowing when to apply" becomes a classification problem over cheap features of the columns involved (section 7.5).

The three gaps of section 3.2 close for structural reasons, not by adding cases.

1. *Generation.* Opening a sequence column into its positions is move 3, available wherever a sequence column exists. No combinator has to be guessed first.
2. *Totality.* A position generated from a column is in range by construction. The fact belongs to the structure map, not to an arithmetic proof about the index expression, so the static analyzer does not need to bound `i` against `(length xs)`.
3. *Boundaries.* `next` is a partial map. Its domain is a context. A pattern that reads `next` twice is simply defined on the smaller context, and the sites outside it are initial conditions, as plan 2 observed.

Finally, laws act on this picture as edge rewrites. Associativity of the step lets a fold's carry be regrouped (the third homomorphism theorem). A closed form for a recurrence deletes the carry. Finite differencing introduces one. That is the concrete sense in which algebra and lifting are one calculus.

### 7.5 Geometry

**Where it attaches.** A *space* is a type together with a code, referenced by every column of that type-in-context. The built-in correction codes are the ambient spaces. A decoder `d(X, Z)` creates a new space for `Z`, whose code is obtained from the target's code by the three rules of section 6.5: transported exactly if `d` is a bijection on the data; conditional on the fiber if it is many-to-one; refunded for arbitrary choices if the latent is under-determined. Because the space is a shared object, a lift or pullback cannot lose it.

**The distance.** Between any two columns over a common base there is already a distance: the sum over sites of the correction bits between their cells. Its special cases are familiar. Between an expression's behaviour and the requirement it is the Stage A residual. Between two expressions it is a behavioural distance the kernel never forms. The *defined* distance, of which this is the cheapest upper bound, is conditional description length: the size of the smallest verified program found that maps one to the other, plus the residual. Shortest paths over found programs make it a geodesic metric on the graph of verified maps, which is "proximity flows along verified topological links" stated exactly.

**Estimators, cheapest first.**

1. Behaviour signatures on shared probe sites: outcome vectors, which the kernel computes anyway. Equal signatures are observational equivalence, the exact limit.
2. Structural hashes with context: colour refinement over the term or execution graph, and MinHash of the label multiset. Linear time, no training.
3. Exact graph distances in the store: shortest path, distance in the library hierarchy, personalized PageRank from a query set. The kernel owns the graph, so these need no embedding. (Raw commute time should be avoided: on large graphs it degenerates to a function of the two node degrees.)
4. Spectral coordinates, only when some consumer needs a fixed-length vector. One sparse eigenproblem, no gradient descent. This is also the geometry a language model converges to in context, and what the successor representation computes.

**Creating, collapsing and moving.**

| You asked for | In the store |
| :------------------------- | :------------------------------------------------------------------ |
| make a space when instructed, or when residuals require | a decoder, a generated base, or a new column creates one; the trigger is a residual that stays compressible |
| collapse spaces when computational symmetry shows they are the same | verified maps both ways whose composites are the identity on the data: merge, and keep the maps as the transport. The cheap pre-test is that both induce the same similarity profile on shared anchor sites |
| move vectors when suggested by ambient or induced spaces | apply the map along the edge (reindex or apply); a signature computed in one space is carried to the other only through such a map |

**The geometry of an index set.** A positions base carries its own group action: shift, reflection, stride. Lag and offset detection is reading off a character of that group, which is the sense in which the plate structure of section 7.4 and geometry are the same object. A cyclic index gets a circle; a re-indexing by `(i mod 2, i div 2)` is a product decomposition of the index group, the plan 1 nugget, and the same construction as a grid-module code.

**Policy.** The learner on top should be instance-based: nearest neighbours and naive Bayes with log-odds weights over sparse features of the problem and of the edge being considered. Its inputs must include the labels the present predictor cannot see: which decoder, which entry. Its weights are bits.

**Flat versus nested.** The store is nested and exact. Each space is flat and local. Nothing is compared across spaces except through a verified map or through shared anchors. This is the same division the brain appears to use (structured addressing, flat content), and it is the only division with a working record in hybrid systems.

**Area, volume, orientation.** If these are needed as values, an exterior-algebra value type gives them with exact integer arithmetic. That is content for the library, not kernel structure, and it only pays for small fixed dimension.

### 7.6 Guards and totality, learned from failure

In the store, outcome status is cell content, so "this expression has no value at these sites" is a Boolean column like any other. Four changes follow.

1. **An error creates a context, not a rejection.** A law that holds wherever it is defined is kept under the context of definedness, where today it is refuted.
2. **Regions are computed before they are searched.** The support of an agreement is a column obtained by restriction; the `:necessity` precedent computes a guard from a failure set. Program synthesis of the guard is then compression of a known region, and can be approximate with the exceptions kept as a residual.
3. **Cheap abstract facts sit on classes.** Interval, non-zero, non-empty and length facts attached to equivalence classes discharge most guards without search. This is the lattice form of the host's totality facts, and it is where a relation such as "0 is at most i and i is below the length of xs" becomes expressible.
4. **Guards have an implication order.** A store of implications between guards is what prevents the single-point guards of section 3.4 from being treated like regions, and what lets a guarded rule fire under a stronger guard.

The static totality analyzer stays, as the trusted fallback and as the source of axioms. What changes is that it reads learned definedness entries, with their evidence grades, in addition to its own table. Non-termination is already tolerated by metering. A learned bound on work as a function of the inputs would be a termination measure found by ordinary synthesis, since the ledger gives exact work for every terminating row; this is untested.

The hard limit remains evidence. The only proof rule today is exhausting a finite type. Without one more rule (structural induction over the positions base is the natural candidate, and implication examples in the style of ICE learning are the natural data), nothing about integers or sequences can be more than a sampled conjecture, and every use must keep its fallback.

### 7.7 Reflection

Putting the search in the same store changes three things.

- **Edge labels become data.** A derivation edge carries its decoder and bindings as code-valued columns. A learned rule can then say "this decoder composed with that one is redundant", which five integer features cannot express.
- **Explanations are edges.** Why two things were merged, or why a branch closed, is a stored path of rule applications. Anti-unifying explanations is how a local nogood becomes a general one, and it is the form clause learning takes here.
- **Attribution becomes an operation.** With a per-edge ledger, the ablation this audit ran by hand (remove an entry, rerun, read the change in work) is something the kernel can do to its own library. An artifact that does not move work is archived.

Scope, which you named as the ill-defined part, gets a definition: **the scope of a learned message is a context**, in the same lattice as guards. A leaf nogood holds in the context of one node; a task-specific conserved quantity in the context of one problem; a library rule in a context given by a descriptor; a battery law in the root context. The evidence grade sits on the edge, separately. That separates the two things the batteries document found conflated.

Reflection should be coarse and declarative. The lesson of 3-Lisp's own retrospective is that fine-grained procedural access to interpreter state was hard to use; what was missing was a way to describe. The store exposes a designed trace schema, not raw controller state.

### 7.8 Language

The three kinds of thing in the store are the three kinds of word you listed. Regions (contexts, descriptors) are like-terms. Maps between bases and between spaces are analogy terms. Rewrites are action terms: they create a base, lift, or partition. A name is a short code for one of these; a compositional address is a small expression over them; and decoding an address is traversal of the store, which is the variable compute that pillar 9 asks for. Nothing in this proposal builds the vocabulary. It only ensures the things to be named exist as first-class objects, and that naming can be judged by whether it reduces search.

### 7.9 What stays outside, and how small the mechanism is

Outside the store: the metered VM; the codec and the three cost accounts; the evidence grades; the agenda with staged payment and a reserve lane; root verification. The search-control audit estimated that of the 8,646 lines in its layer, 2,500 to 3,000 are mechanism of this kind, 4,500 to 5,000 are rule content or policy that could be data, and 600 to 900 disappear under one canonical identity. Those are rough figures from one reading. The honest test of how small the core is, is to build it (experiment E7).

---

## 8. What Survives, What Changes, What Goes

**Kept unchanged.** These survived every refactor in the trail and are invariants of the research programme, not of the representation.

- Execution on the metered simulator is the source of truth; there is no host `eval` in the object language.
- A requirement is a predicate, and it moves through a decoder by substitution.
- A candidate is accepted only by running it on every root row.
- Description length is the objective, with model size, run work and search work kept distinct.
- Evidence grades, with the rule that sampled evidence can propose and never eliminates; certificates bind to a snapshot of what they depend on.
- A rewrite may not turn an erroring program into a valid one.
- Search is anytime: it can be cut off and resumed without changing its result.
- Heuristics must never starve sound search.

**Generalized.**

| Today | Becomes |
| :----------------------------------------- | :--------------------------------------------------- |
| row; frame | site with cells; base with columns |
| `pairs`, `anchors`, `edges`, partitions, fiber classes, same-input joins | equality and disequality edges in a context, with a grade |
| provenance in row-key naming | structure maps |
| `lift-frame` and the symbolic fold walker | reindex as a primitive; call sites from recorded execution |
| observation buckets, private to a job | a persistent behaviour table that enumeration composes from |
| a metric slot on a frame | a space shared by columns |
| law, rewrite rule, solver, propagator | one relation with several readings |
| `messages.lisp` readers and `make-search-trace-frame` | one reifier from any node or edge type to rows |

**Moved to the library.** The proposal generators (additive, conditional, inductive, lockstep, product) as decoder templates with triggers. The descriptor concept menu. The constructor fold rules, as laws. The four recursion schemas, replaced by one general proposal: a self-call whose other arguments are child holes. The host recognizers of particular theories (monoid, functor, fold). The roughly ninety policy constants, as a parameter table that reflection can read and, with evidence, rewrite.

**Dropped, as artifacts of the present representation or of tuning.**

- Unit-exact ledger parity as an invariant. Resumability is the invariant. You have already said that work drift is tolerable; parity to the unit is what forced every host step to be wrapped as staged work and gated new behaviour to protect old figures.
- The search for shared subterms when composing models (about 165 lines), which hash-consing makes structural.
- "Never mutate frames or the library during search." This exists because buckets, masks and caches are aligned by position and identity. With keyed, persistent structure, learning during search is not unsound in itself.
- Cloning a whole un-narrowed frame as the mechanism for soundness. The invariant is zero false pruning; a context does the same job.
- The reserve ratio replicated at five sites, in favour of one reserve policy.
- The wall between kernel and `milestones/`. Guard search from supports, views and locality scheduling are capabilities the kernel needs and never loads.

---

## 9. Risks and Open Problems

1. **Density.** A uniform store is not uniformly learnable. Arithmetic laws are dense in short expressions; search policies are not. Each level needs a schema designed so that small changes are likely to be meaningful, and that design is not done here.
2. **Matching cost.** Reuse has lost to the cost of finding where a rule applies in every small measured case in this project. A store with rules as data makes matching the dominant operation. It has to be a relational join with indexes from the start, and the experiments must charge for it.
3. **Extraction.** Choosing the cheapest description from a store with sharing is NP-hard and not approximable within a constant. Root-priced, staged, anytime search remains necessary; the store does not replace it.
4. **Enumeration modulo behaviour changes a claim.** Composing only class representatives turns "bounded exhaustion" into "bounded exhaustion modulo behaviour on these rows". Candidates that error or are unresolved on some row are not bucketed today and need a defined treatment.
5. **Conditional equality in a relational store is unfinished research**, and shared latents (two holes that must agree) need equality constraints between paths that plain e-graphs cannot express.
6. **Evidence over infinite domains.** Without a second proof rule, everything about integers and sequences stays sampled. No datastructure changes that.
7. **Three parts of the proposal are new, as far as the survey could tell:** conditional description length as the geometry of a growing library; description-length induction of an index function from a flat execution graph; and any link between sheaf-style obstruction and clause learning. New means unproven.
8. **Second-system risk.** The kernel grew 41% across three plans that each set out to shrink it, and the plan 9 audit found sixteen names or citations in the plan that did not match the source. Plans written by agents against a model of 17,647 lines drift from the code. A redesign authored the same way can repeat this. The mitigations are a small core, experiments before commitments, gates stated against measured baselines, and a line count that must fall at every migration step.
9. **Unification does not produce learning.** What is additionally needed is that the kernel chooses experiments (asks for the row that separates two candidates), records attribution, and can condition rules on edge labels. Experiments E4 and E5 address these; the store only makes them expressible.
10. **The flat alternative may simply win** where sample efficiency is not required. This project's bet is that it is required.

---

## 10. Experiments That Decide

Each experiment tests one assumption the redesign rests on. E1, E2 and E4 are changes to the present kernel and need no new store. Predictions are stated so they can fail.

**E1. Index coordinates as readable columns.**

- *Change:* expose the occurrence ordinal and the parent sequence length as input columns of lifted rows; let a combinator's primary sequence argument be a generated index list; give generated positions a totality fact.
- *Measure:* the six tasks of section 3.2; reverse and rotate from plan 2; the five bootstrap functions that fail without hand-written schemas.
- *Prediction:* all are solved automatically within about 500,000 work each (the run with a supplied index column took 418,727).
- *Decides:* whether index structure is a representation problem, as claimed here, or a search problem.

**E2. One behaviour table.**

- *Change:* the enumerator composes one representative per behaviour class, and Stage A and exact search share the table within a node. Outcome status is part of the behaviour.
- *Measure:* candidates per class; work on the plan 8 probes and the fingerprint.
- *Prediction:* at least ten times fewer candidates at 30 body bits (the measured ratios are 22 and 38 to 1).
- *Decides:* the value of a persistent equivalence store, and finally measures the triggers plan 1 set for adopting one.

**E3. Laws as minimized merges.**

- *Change:* persist the bucket table; propose a law only if it is not derivable from those already accepted; store associative-commutative terms as multisets.
- *Measure:* laws kept for `+` over GF(3) cubed (now 1,753); normal forms of the twelve arrangements of a three-term sum (now 3); whether distributivity appears unprompted.
- *Prediction:* a handful of laws; one normal form.
- *Decides:* whether the host shape filter `law-operator-fact` can be deleted.

**E4. Attribution by ablation, as a kernel operation.**

- *Change:* record which entries were consumed by each node; add a consolidation step that reruns a recorded job with one entry inactive; expose the decoder and the entry used as message columns.
- *Measure:* the change in work per entry, on the L4 curriculum and the plan 8 probes.
- *Prediction (from the ablation done by hand):* only function entries move work; the predictor, nogood schema and descriptor entries do not, and are archived.
- *Decides:* what reflection buys today, and gives the kernel the means to find out for itself afterwards.

**E5. One general recursion proposal.**

- *Change:* a self-call whose other arguments are child holes to be synthesized, in place of the four hand-written schemas; a step that asks for a disambiguating row when two candidates pass a spec.
- *Measure:* the sixteen bootstrap function specs with `recursion-schemas.lisp` removed.
- *Prediction:* `positions`, `scan`, `map-adjacent`, `shift-seq` and `best-shift` become reachable; `foldl` and `last-or` come out right once a separating row is requested.
- *Decides:* whether a lift with a carry can be a synthesizer primitive in the present kernel.

**E6. Recognizers with learned triggers.**

- *Change:* add period (autocorrelation), finite-difference and Berlekamp-Massey recognizers as solver-and-decoder pairs like the shift battery; train a naive Bayes trigger on cheap column features, labelled by whether each recognizer's replay guard held.
- *Measure:* work per miss with and without the trigger (a rejected non-shift costs 3,637 today, on every miss); the trigger's precision and recall.
- *Decides:* whether "knowing when to apply" is learnable with bit-weighted counts.

**E7. The core store, built small beside the kernel.**

- *Change:* bases, structure maps, columns of partial-information cells, hash-consed classes with a behaviour table, contexts, and the six moves, reusing the VM and codec. Port the M1 to M4 controls, the E1 tasks, one map lift, one fold with a carry, and anti-unification as recursive constant-column detection.
- *Measure:* lines; work against the kernel on the same tasks; how many of the present tests' assertions can be restated.
- *Decides:* whether to migrate.

**E8. Geometry as retrieval.**

- *Change:* a behaviour signature and a structural hash per library entry; nearest-neighbour retrieval of decoder templates for a new problem.
- *Measure:* the rank of the correct entry, and work, against descriptor scoring (which in ablation had zero or negative effect).
- *Decides:* whether the cheap estimators carry signal before anything heavier is considered.

Two measurements are nearly free and worth doing first. Gate the `requirements.lisp` fold rules and the descriptor prototypes behind a switch, load `constructors.sexp` and `descriptors.sexp` in their place, and read the fingerprint: nothing currently tests whether those library entries can carry the load they were written for. And delete the per-spec operator lists in the bootstrap, taking each language from the active library: the present 0.33 s bootstrap leaves three to four orders of magnitude of headroom to see what survives.

---

## 11. A Staged Path

- **Stage 0, in place:** E1, E2, E4 and the two free measurements. Gate: both suites pass; fingerprint and probe drift measured and reported.
- **Stage 1, in place:** E3, E5, E6. Each, if it passes, deletes host code: the law shape filter, the recursion schemas, the try-on-every-miss path.
- **Stage 2, beside the kernel:** E7 and E8. Decide on migration from the measured comparison.
- **Stage 3, migration, in the order that deletes the most:** enumeration and the behaviour table; frames to bases, with lift by recorded execution; laws and solvers as one relation; proposal generators as templates; the search DAG into the store, with attribution; spaces and the policy learner; vocabulary.

One rule for every step: kernel lines are deleted only when a store primitive or a library entry carries their load and the suites pass, and the kernel line count must fall at each step. That gate failed in plans 8 and 9, so it should be read per step and not at the end.

---

## Appendix A. Each Kernel Module Under the Proposal

Line counts are at `df33ed1`. "Fate" is a judgment from the audits, not a commitment.

| Module | Lines | Fate |
| :---------------- | ----: | :------------------------------------------------------------------ |
| `package.lisp` | 254 | plumbing |
| `ast.lisp` | 1,442 | keep types and syntax; hash-cons applications; totality stays as the trusted fallback and reads learned definedness entries |
| `knowledge.lisp` | 668 | becomes the store (bases, columns, edges); the untyped metadata plists become typed columns |
| `codec.lisp` | 221 | keep |
| `vm.lisp` | 645 | keep; add the recording mode for oracle-backed functions |
| `evidence.lisp` | 73 | keep; grades move onto edges |
| `persistence.lisp` | 141 | keep, over the store |
| `requirements.lisp` | 540 | the contracts stay; most fold rules become constructor laws; lift no longer depends on it |
| `frame.lisp` | 1,761 | pullback and composition stay; lift becomes reindexing; correction pricing becomes spaces; subterm sharing disappears |
| `enumerate.lisp` | 877 | keep, composing from the shared behaviour table |
| `unify.lisp` | 255 | keep; anti-unification acts on classes |
| `fibers.lisp` | 177 | becomes a search for a map between bases |
| `laws.lisp` | 1,349 | one relation with several readings; validation stays |
| `templates.lisp` | 653 | retyping stays in function; simpler if operator nodes stop carrying concrete operand types (untested) |
| `condense.lisp` | 301 | Stage A becomes pricing against the behaviour table |
| `abstraction.lisp` | 580 | keep; library discovery over classes |
| `descriptors.lisp` | 1,045 | descriptors become Boolean columns; the concept menu moves to the library |
| `relations.lisp` | 242 | residual relations become columns |
| `synthesize.lisp` | 1,310 | the controller; stays outside the store, smaller |
| `nogoods.lisp` | 580 | constraint edges with explanations |
| `decompose.lisp` | 725 | templates with triggers, in the library |
| `proposals.lisp` | 1,417 | one template-instantiation step; the rest to the library |
| `consolidate.lisp` | 2,118 | the fixed-point driver stays; recognizers and solver induction to the library |
| `messages.lisp` | 128 | one reifier |
| `explain.lisp` | 145 | largely unnecessary: a graph with typed edges is its own provenance |

---

## Appendix B. Literature

Confidence: **[A]** bibliographic data and the stated claim were confirmed from an abstract, proceedings page or publisher record during this audit; **[M]** cited from memory and not checked. No paper was read in full for this document. Several 2025 and 2026 items are workshop papers or preprints.

**Relational structure and fibrations**

- Patterson, Lynch, Fairbanks, "Categorical Data Structures for Technical Computing", Compositionality 4, 2022. Attributed C-sets: one structure for graphs, hypergraphs and data frames. [A]
- Brown, Patterson, Hanks, Fairbanks, "Computational Category-Theoretic Rewriting", ICGT 2022. Generic double-pushout rewriting over C-sets. [A]
- Spivak, "Functorial Data Migration", 2012 (arXiv 1009.1166). The operations $\Delta$, $\Sigma$, $\Pi$ along a schema map. [A] No use in program synthesis or array languages was found.
- Mellies, Zeilberger, "Functors are Type Refinement Systems", POPL 2015. Pullback of a predicate along a term. [A]
- Chiang, Riley, "Factor Graph Grammars", NeurIPS 2020. Plates and recurrences as hyperedge-replacement productions. [A]

**Equivalence stores**

- Willsey et al., "egg: Fast and Extensible Equality Saturation", POPL 2021. [M]
- Zhang et al., "Better Together: Unifying Datalog and Equality Saturation" (egglog), PLDI 2023. One relational engine with equivalence and lattice merges. [A]
- Singher, Itzhaky, "Colored E-Graph: Equality Reasoning with Conditions", arXiv 2305.19203. A layered congruence per assumption. [A]
- Schneider, Rossel, Shaikhha, Goens, Koehler, Steuwer, slotted e-graphs, PLDI 2025. Classes parameterized by free variables. [A]
- Zucker, "Lifting E-Graphs: A Function Isn't a Constant", EGRAPHS workshop 2026. Lift as a built-in combinator. [A]
- Tiurin, Barrett, Ghica, Hu, "Equivalence Hypergraphs: DPO Rewriting for Monoidal E-Graphs", LICS 2025. The nearest theory to an equivalence store over a hypergraph; no engine. [A]
- Goharshady, Lam, Parreaux, "Fast and Optimal Extraction for Sparse Equality Graphs", OOPSLA 2024. Extraction is not approximable within a constant. [A]
- Rosin, Ullrich, Hack, "Associativity and Commutativity in Equality Saturation", arXiv, 2026. Exponential blowup under rewrite rules; fix by multiset encoding. [A]
- Flatt et al., "Small Proofs from Congruence Closure", FMCAD 2022. Explanations of equalities as stored data. [A]
- Koppel et al., "Searching Entangled Program Spaces" (ECTA), ICFP 2022. Equality constraints between paths. [A]
- Koehler et al., "Guided Equality Saturation", POPL 2024. Waypoints, not rule priorities, are the effective control. [A]

**Law discovery and library learning**

- Nandi et al., "Rewrite Rule Inference Using Equality Saturation" (Ruler), OOPSLA 2021; Pal et al., Enumo, OOPSLA 2023. Outcome-vector fingerprints plus derivability minimization. [A]
- Cheung, Nandi, Lerner, Chompy, FMCAD 2026. Conditional rules with implication reasoning between guards. [A]
- Smallbone, Johansson, Claessen, Algehed, "Quick specifications for the busy programmer" (QuickSpec 2), JFP 2017. Test only what current laws do not derive. [A]
- Singher, Itzhaky, "Theory Exploration Powered by Deductive Synthesis" (TheSy), CAV 2021. Experiments on symbolic inputs. [A]
- Cao et al., babble, POPL 2023. Anti-unification over equivalence classes. [A]
- Bowers et al., Stitch, POPL 2023. Top-down corpus-guided abstraction; orders of magnitude faster than e-graph methods when no theory is needed. [A]
- Ellis et al., DreamCoder, PLDI 2021. [A]
- Grand et al., LILO, ICLR 2024. Naming learned abstractions improves search. [A]
- Cook, Holder, SUBDUE, JAIR 1994. Description-length substructure discovery in graphs. [A]
- Polozov, Gulwani, FlashMeta, OOPSLA 2015. Witness functions as inverse semantics. [M]

**Arrays, indices and recursion**

- Slepak, Shivers, Manolios, Remora, ESOP 2014. Frames and cells; implicit lifting. [A]
- Gibbons, "APLicative Programming with Naperian Functors", ESOP 2017. Tabulate and index. [A]
- Paszke et al., Dex, ICFP 2021. Index sets as types. [A]
- Ragan-Kelley et al., Halide, PLDI 2013; the polyhedral model (Feautrier). [M]
- Gibbons, "The Third Homomorphism Theorem", JFP 1996. [A]
- Farzan, Nicolet, "Synthesis of Divide and Conquer Parallelism for Loops", PLDI 2017. Lifting a loop by adding accumulators. [A]
- Nandi et al., Szalinski, PLDI 2020. Flat lists to maps and folds over index ranges inside an e-graph. [A]
- Kamil et al., "Verified Lifting of Stencil Computations", PLDI 2016. [A]
- Miltner et al., Burst, POPL 2022. Angelic recursion, the analogue of the kernel's oracle table. [A]
- Massey, Berlekamp-Massey, 1969 [M]; Kauers, Koutschan, "Guessing with Little Data", ISSAC 2022 [A].

**Propagators, sheaves, dependence**

- Radul, "Propagation Networks", MIT thesis, 2009. Cells of partial information with a monotone merge. [A]
- Kuper, Newton, LVars, 2013. Lattice cells with threshold reads. [A]
- Robinson, "Assignments to sheaves of pseudometric spaces", Compositionality 2020. The consistency radius. [A]
- Hansen, Ghrist, "Toward a spectral theory of cellular sheaves", 2019. [A]
- Abramsky, Brandenburger, "The sheaf-theoretic structure of non-locality and contextuality", 2011. Local consistency without a global section. [A]
- Perera, Acar, Cheney, Levy, "Functional programs that explain their work", ICFP 2012. Slicing as a Galois connection on one run. [A]
- Buss, Chung, Ganesh, Oliveras, dual implication points, LMCS 2026. [A]
- Cropper, Morel, "Learning programs by learning from failures" (Popper), Machine Learning 2021; Feng et al., Neo, PLDI 2018. Failures as constraints on the hypothesis space. [A]

**Geometry and description length**

- Bennett, Gacs, Li, Vitanyi, Zurek, "Information distance", IEEE Trans. Inf. Theory 1998. [A for the citation; the max formula from memory]
- Vereshchagin, Vitanyi, "Kolmogorov's structure functions and model selection", 2004. [A]
- Hoogeboom et al., "Integer Discrete Flows and Lossless Compression", NeurIPS 2019. [A]
- Townsend, Bird, Barber, bits-back coding with asymmetric numeral systems, ICLR 2019. [A]
- Balasubramanian, 1997; Myung, Balasubramanian, Pitt, PNAS 2000. Model complexity as the log count of distinguishable distributions. [A]
- von Luxburg, Radl, Hein, "Hitting and Commute Times in Large Random Neighborhood Graphs", JMLR 2014. Commute distance degenerates. [A]
- Memoli, Gromov-Wasserstein distances, 2011; Moschella et al., "Relative representations", ICLR 2023. Tests that two spaces are the same. [A]
- Ren, Hu, Leskovec, Query2box, ICLR 2020. Disjunction is not embeddable in low dimension. [A]
- Desbrun, Hirani, Leok, Marsden, "Discrete Exterior Calculus", 2005. Incidence exact, metric in separate weights. [A]

**Flat spaces, the brain, language, guidance**

- Park et al., "ICLR: In-Context Learning of Representations", ICLR 2025. [A]
- Adler, Shavit, "On the Complexity of Neural Computation in Superposition", arXiv 2409.15318. [A]
- Peng, Narayanan, Papadimitriou, "On Limitations of the Transformer Architecture", 2024. [A]
- Feng, Steinhardt, "How do Language Models Bind Entities in Context?", ICLR 2024. [A]
- Whittington et al., "The Tolman-Eichenbaum Machine", Cell 2020. [A]
- George et al., clone-structured cognitive graphs, Nature Communications 2021; Raju et al., "Space is a latent sequence", Science Advances 2024. [A; the EM detail from memory]
- Chandra, Sharma, Chaudhuri, Fiete, Vector-HaSH, Nature 2025; Gershman, Fiete, Irie, "Key-value memory in the brain", Neuron 2025. [A]
- Coecke, Sadrzadeh, Clark, compositional distributional semantics, 2010. [A]
- Kuhlwein et al., MaSh, ITP 2013; Gauthier et al., TacticToe, 2021; Blaauwbroek et al., Graph2Tac, ICML 2024. Nearest-neighbour and naive Bayes guidance. [A]
- Lenat, Brown, "Why AM and EURISKO Appear to Work", Artificial Intelligence 1984. [A]
- Goertzel et al., OpenCog Hyperon, arXiv 2023. [A]
- Liao, Gu, CompressARC, arXiv 2025. [A]
- Smith, "Reflection and Semantics in Lisp", POPL 1984. [A]

---

## Appendix C. Measurements Made in This Audit

All runs were against the tree at `df33ed1` with scratch scripts kept outside the repository. Nothing in the repository was modified. The failures reported are at the bounds and languages chosen for the audit and were not tuned further.

| What | Result | Section |
| :------------------------------------------ | :------------------------------------------- | :-------- |
| Kernel and milestone suites | 222 and 40 tests, all pass | preamble |
| Plan 8 probes | 71,782 / 212,096 / 34,067 (on record at `6d2f412`: 74,094 / 220,691 / 34,067) | preamble |
| Ledger fingerprint | 236 tests, 419,655,232 work; +0.46% against the last commit with hand-written batteries | 3.8 |
| Bootstrap regenerated in a scratch copy | byte-identical, 0.33 s, about 2.5M work | 3.8 |
| Eight index-frame tasks | table in section 3.2 | 3.2 |
| Totality of variable-index access | never provable, under any guard tried | 3.2 |
| Law discovery on five grids | 47 to 3,623 validated laws; validation costs about 1.5 times observation and refutes nothing on a complete grid | 3.5 |
| Normal forms under validated associativity and commutativity | 12 arrangements reach 3 normal forms | 3.5 |
| Guard discovery on GF(5) | 16 supports; 5 single points carry 2,270 of 2,390 equations | 3.4 |
| Correlation solver | 19 bits against 26 to 52; 6,581 to 18,804 work; 3,637 to reject a non-shift | 3.6 |
| Warm-library ablation | warm work unchanged at 16,687 without any trace-derived entry | 3.7 |
| Priority predictor | condenses to one raw feature; no effect on held-out work | 3.7 |
| Enumeration against behaviour | 12,139 candidates for 316 behaviours; 3,489 for 160 | 3.7 |
| Bootstrap without recursion schemas | 9 of 16 intended; 5 fail at 20M work; 2 pass with the wrong function | 3.8 |
| Operator lists in specs | exactly the answer's vocabulary in 9 of 11 | 3.8 |
| Definedness guards from outcomes | five guards learned at 4,442 to 24,077 work | 3.4 |

---

## Appendix D. Document and Code Discrepancies Found

- `architecture2.md` lists 24 kernel modules including `bootstrap-inverters.lisp`, which is not in `load.lisp`; the functorial solvers are at `consolidate.lisp:1976-2118`. There are 25 modules.
- `architecture2.md` counts 26 primitives (there are 27, with `:mod`) and 11 knowledge kinds (there are 14); `tests/library.lisp:56` says 9.
- `architecture2.md` section 3.2 describes a built-in `:at` inversion and a rule that reserves half the budget for the head fiber; neither is in `requirements.lisp`. Its formula for the per-row fiber cap differs from `frame.lisp:1211-1213`. It gives the coupled penalty as 128; the code uses 16.
- `architecture2.md` names `filter-map-decompositions` (now `multi-hole-decoder-decompositions`) and `*descriptor-table*` (no such variable).
- The plan 7 recursion document's header says its Phase 3 is "Complete ... implemented, audited, and verified"; Path A has no kernel caller. `plan7.md` says there is no M9 implementation; there is. The higher-order document says "Proposed" and contains an implementation record.
- `plan6.md` credits the anti-unification compression gain to shape-grouped templates; the measured record in `results.md` credits one global template.
- `batteries-and-reflection.md` section 2.2 describes field-certified solvers lifted to integers with divisibility guards; the shipped solvers are induced from hand-given integer rows with guard `k != 0`, uncertified, and the bootstrap never calls `lift-field-solvers`. Its "dedicated bootstrap test" does not exist. Spec replay is skipped for retyped loads (`consolidate.lisp:1884`).
- The docstring of `synthesis-message` says parents may consume messages; no node reads another node's messages.
- The name `congruence-close-code-evals` and the architecture reference suggest congruence closure; the function is ground substitution to a fixpoint.
- The ledger fingerprint script's module list predates `closures`, `batteries`, `messages` and `totality`, so it does not cover them.
- `library/` is untracked and not ignored, and the tests depend on it.

