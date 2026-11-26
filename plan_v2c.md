# `lisploop` — Plan v2c: one topology–geometry kernel

*Audit of the kernel, its documents, and the literature, and a proposal for a single store. Written 24 November 2026 against commit `15e64c6` (root kernel unchanged since `df33ed1`; `v2/` at `a4e19fa`). Revised 25 November after your annotations and an outside review; Appendix G lists the changes of substance.*

**How this was made.** Fourteen AI auditors, working in parallel and independently, each took one slice: five read and ran the code, six read the planning trail, three reviewed the literature. A fifteenth built and ran a small prototype of the proposed store. A sixteenth then checked a draft of this document against the reports, the logs, and the code; its 77 findings were applied. Three of the code auditors (data structures, search, laws) were told not to read the earlier v2 plans, so that their view came from the code. For the revision, the outside review's empirical claims were reproduced before they were used, and further measurements were made of search across spaces (§8.6–8.8). Their reports, with file-and-line citations, are in `plan_v2c_audit/` (Appendix F).

**Evidence tags.** Claims of fact are tagged with where they come from. Sections 5–7 are the proposal: read every statement there as **[P]** unless it cites a measurement in §2 or §8.

| Tag | Meaning |
|:--|:--|
| **[M]** | measured during this audit; the script is kept |
| **[C]** | read in the code; file and line given here or in the cited report |
| **[D]** | stated in a project document; not re-measured |
| **[L]** | from the literature, with its maturity noted |
| **[P]** | this plan's proposal; not yet tested |

The earlier v2 plans are treated as claims to check, not as foundations. Appendix D lists what their own audit passes rejected; none of it is re-imported.

---

## 1. Summary

**The question.** Can the kernel's requirements be met by one topology–geometry kernel, with one attendant data structure?

**The answer.** For the topology, yes. The store is assembled from shipped parts, and the two mechanisms that are this plan's own, lifting by a change of space and reading inverses off an operator's table, each have a prototype result behind them and a gate ahead of them. For the geometry, yes in a derived sense and not yet in a learned one. Several parts of the ambition are research rather than engineering (§1.6).

### 1.1 What the audit found

1. **A frame is a table of unary constraints.** Each row holds one predicate on one unknown. Relations among unknowns, positions in a sequence, and anything about expressions have nowhere to live. This is the exact place where a graph says more than a frame (§2.1).
2. **Lift is host-only, and so is nearly everything else.** Of the operations you list, a synthesized program can perform substitution, value projection, tupling, and `if`. Pullback, fiber, quotient, partition, reorientation, and residual are host Lisp, because terms are values of the object language and frames, rows, and positions are not (§2.2).
3. **The budget was milliseconds, and it is not the binding constraint.** The whole library regenerates in 0.4 s of search, and one spec gets 0.06 s, so you are right by four to five orders of magnitude. But with hand-written help removed, raising the budget a thousandfold moves sound solutions from 8 to 10 of 16 and no further. The failures are structural first (the search tree has two or three nodes at every budget), exponential second (each tenfold of work buys about one AST node), and memory-bound third (§2.3).
4. **The kernel computes the right things and discards them.** 99% of enumerated trees on the real grammars duplicate the behaviour of an earlier tree. Law discovery already groups expressions by behaviour; enumeration never uses the groups. A working behaviour pruner sits in `v2/` behind a flag nothing sets; switched on, it cut work by between 6× and 470×, depending on the grammar (§2.3).
5. **The library is mostly authored.** 2.5% of its bits come from search with a generic grammar; 59% are hand-written expressions. Nothing in the kernel initiates discovery. Yet the library does compound on some tasks when it is used for lifting, and `:map` does emerge from the kernel's own anti-unification (§2.4, §2.5).
6. **Your requirements have not changed since October.** What goes with what was handed in by every plan and never stored. Graph machinery was declined four times, on minimalism, never on a measurement (§2.8).

### 1.2 The diagnosis

The kernel computes three graphs and stores none: the execution graph (which value came from which), the equivalence graph (which expressions agree on which rows), and the derivation graph (which sub-problem came from which). And the one structure that holds rows and requirements, the frame, is not a value of the object language (§3).

### 1.3 The proposal

Evaluating one expression over N rows produces N copies of one small graph. So the execution graph factors as **pattern × rows**, and the store keeps the factors:

- a **space** is a set of rows, the independent contexts;
- a **column** holds one cell per row, and a column of row references is a **map** between spaces;
- a **term** is a shared expression that denotes a column on a space;
- a **class** is all the terms denoting the same column.

On that store your operations share one description: build a space, give it a map to a space you have, and move columns along the map. Lift builds a space of positions. A guard builds a sub-space. Anti-unification builds a space of instances. Recursion is a map from a space of calls to itself. A law is two terms in one class; a guarded law is a class on a sub-space; an inverse is an operator's own table read in another direction; a residual is a column (§5).

The store draws one line that the rest of the design follows. Within a space everything is computed, in time linear in the cells touched; the one search there is for the term itself. Across spaces nearly everything has to be found: relating two spaces means finding a map between them, which is cheap to check and can be hard to find. Compression lives on that second side, so the search has to be allowed, budgeted, and prioritized (§5.9).

Two different things do the work that "geometry" names. The *pricing metric* is description length: the distance from one column to another is the bits needed to write the second given the first, which the codec already defines per value type. The graph is the factorization of the description; the metric is the code on each factor. The *retrieval index* is separate: behaviour distance, property signatures, usage counts, and graph proximity, none trained by gradient descent, used only to rank and to choose what to try. Its main job is to prioritize the search across spaces. Nesting stays in the exact store; one flat signature space indexes it. The index's vocabulary is also where language starts: small quotients of values, and for each operator a table of what it does to them (§6).

The synthesizer has one move: refine a hole with a program construct, and split the requirement the way that construct splits it. Each construct the VM can run is paired with the law that splits a requirement on it. The search's own record is a space like any other (§7).

Each part of the store's core has shipped precedent: shared terms, value vectors with behaviour classes, relational tables, law discovery by collision. The search-literature review's own "most reliable recipe" overlaps this parts list, with one departure noted in §5.8. Three things are this plan's own: spaces with maps as the lifting mechanism, inverses read off an operator's table, and keeping all three graphs in one structure (§5.8).

### 1.4 What a prototype showed

A standalone prototype of the store, 874 lines of Lisp with no kernel code, was run on four questions (§8) **[M]**.

- **Lift.** Fifteen sequence tasks were solved from input/output rows by one fixed procedure with one 12-operator grammar and no skeleton written per function, each scoring 200/200 on held-out examples; 134 of 135 runs over nine example sets. The procedure grants the container forms (`tabulate`, selection, `where`, one guard, `fold`); what is found is the term inside. The tasks include the prototype's versions of three of the four functions the existing kernel does not find at a thousand times its budget (`map-adjacent`, `scan`, `shift-seq`; `best-shift` was not attempted), on the prototype's own example rows. The first-order ones took between 3 and 703,183 candidate columns and under half a second; `map-adjacent` with a function argument took five seconds. None needed recursion.
- **Inverses.** The inverses of `+`, `−`, and `neg` were found from the operators' own tables within 25 candidates; `*` with its guard `b ≠ 0` in about a quarter of a second. Feeding those inverses back made three later searches 60–150× cheaper.
- **Laws.** Commutativity, associativity, the identities, and distributivity were derivable by size 7 in 0.01 s, with no false law once the probe space had 8 rows.
- **On the kernel's own spec rows** (added in revision; §8.6). The outside review ran the prototype on the kernel's `:spec` rows, and the runs were reproduced. Thirteen of the sixteen specs reach 200/200 on held-out inputs from their own 4 to 13 rows, in some configuration of the prototype; no one configuration was run on all sixteen. Three need a change: `map-adjacent` only when a guard split is never accepted ahead of a smaller unsplit term, `seq-corr` only once collect can take an aggregate, and `filter` only with a Boolean call added to the grammar. Two more, `sum-all` and `prd-all`, are right only through the `fold` route; the unlifted route returns impostors for them. `foldl` is underdetermined by its rows and returns an impostor; `best-shift` and `argmax-corr` are not solved.
- **Across spaces** (added in revision; §8.7). Signatures generated by the store find problems of the same form at three times chance and do not find the operators a problem needs, so they saved no more work than a control that ignores the task. An analogy between two operators' tables that is carried by a small term is nearly free to find: 350 tested in 1.3 ms, 29 hold. Matching rows with no key needed no backtracking on irregular or symmetric data, only choices that were never undone. It needed backtracking on regular structures without symmetry, and a great deal of it to reject look-alikes that are not isomorphic.
- **A vocabulary** (added in revision; §8.8). The outside review proposed giving each operator a small table of what it does to coarse labels of its inputs. Rebuilt in Python on a hand-written library of 61 operators, that cut candidates about 15 times and time 1.3 to 4 times, more at larger sizes, and it worked for the two operators held out of every solved task. It lost 0.3% of answers at a thousand random probes per operator. Over the sizes tried it behaved as a constant factor in candidates.
- **Limits.** Measured: nested guard splits overfit; folds with sequential state need a `fold` form, though plain reductions do not once collect can take an aggregate (§8.6); the set of kept laws does not converge. Extrapolated from 90-second runs: a single deep search would exhaust 24 GB in one to eight minutes, and ten hours would reach one or two nodes further than one hour.

### 1.5 Where this plan qualifies your prompt

- **Budget.** Hours are right, but not as one deep search. An hour should be thousands of small bounded problems, re-validation on fresh rows, and ablation (§7.6). By one auditor's model of the published results, cutting a grammar from a hundred primitives to ten is worth more nodes than the step from one second of search to one hour (§4.1).
- **Anti-unification.** Your reading of it as quotienting plus lifting holds as intuition. On the store it comes apart into a shared pattern (the constant columns of an instance space) and a quotient (the class). Taking instances modulo classes, to make it robust to equivalent syntax, is cheap only as normalize-then-generalize, which can miss a pattern; the full version is a search across spaces (§5.4, §5.9).
- **Graph isomorphism and e-graphs.** Within a space neither is needed: shared, ordered terms compare by hash. Across spaces a matching engine is needed, as you say. It is colour refinement with backtracking, built from group-by and re-index, and run only on what the cheap index proposes (§5.9). An e-graph's store is worth having; its saturation is not (§4.3).
- **Flat versus nested.** Not a question of what can be represented. A flat space buys storage economy that a library of a few hundred entries does not need. Keep nesting exact and use one flat space as an index (§6.4).
- **Lifting forms as primitives.** A primitive may encode the shape of a container, never the content of a domain. `tabulate`, `fold`, and `where` are granted on that rule; what goes inside them is found (§7.1).

### 1.6 What is research, not engineering

- A closed loop in which laws, inverses, and abstractions found on the store become the next round's primitives on the same store. Abstraction alone has precedent, and there it roughly doubles solve rates and then plateaus; the full loop has none (§10).
- Learned inverses beyond one operator; guarded laws with guards larger than about four nodes; general recursion with hidden state.
- Algebra from depth-two experiments, over spaces whose rows range over functions (§5.4).
- A vocabulary the kernel chooses for itself and that goes on improving its own search. Its parts are now in Stage C and have a first measurement (§6.6, §8.8); the compounding has no precedent.
- Learned coordinate spaces, and language with people.

### 1.7 Recommendation

Rewrite, in four stages. About 3,500 lines of the present kernel and its milestone code are worth carrying over: roughly 2,200 as code or as a design, and roughly 1,300 that work through a frame today and need that interface moved. About 750 more are ideas to re-implement (§9). Stage A is the store core plus two experiments: law discovery by class, which is shipped technique, and inverses from tables, which is this plan's own and so far shown only on the prototype. If either fails, the plan is wrong at the root and that is known first (§11). The revision moves two things forward into Stage C: search across spaces (§5.9) and the vocabulary (§6.6). The standing metric is the kernel-found fraction of the library, which is 2.5% today.

---

## 2. What the audit found

Each subsection gives the facts that bear on the design, with the source. Full detail, with file and line for every claim, is in the audit reports listed in Appendix F.

### 2.1 The frame is a table of unary constraints

A frame row is `(key, known-inputs, requirement)`. The requirement is one Boolean expression over a single unknown, `x0` (`frame.lisp:7-10, 221-222`) **[C]**. So a frame can say "on this row the unknown must equal 7", or "must lie in this set", or "must satisfy this predicate". It cannot say anything that relates two unknowns, or the unknown on two rows, except through three later additions: `pairs`, `anchors`, and typed `edges` between rows (`frame.lisp:14-24`).

This is the precise limit of the representation. When a pullback or a lift produces a constraint that joins several unknowns, the kernel either weakens it (soundly) or returns it beside the frame as a `coupled` list. Coupled constraints are then solved by a brute-force join capped at 4 candidate models per slot and 256 combinations (`synthesize.lisp:636-642`) **[C]**.

Three more facts about the representation:

- **Terms are not shared.** They are plain conses; identity is structural equality; every snapshot copies the tree and discards cached metadata and compiled closures **[C]**.
- **Nothing records an execution.** No evaluation notes which operator consumed which value. The nearest thing is `lift-frame`, which unfolds a decoder symbolically until the unknown's call sites appear, builds what is in effect an execution graph inside requirement expressions, and discards it (`frame.lisp:1214-1256`) **[C]**.
- **Frames themselves are cheap.** At 4,000 rows every basic frame operation is linear and takes 4–60 ms **[M]**. The frame is not a performance problem. It is an expressiveness problem.

Pullback itself is good: 37 lines, with a tested contract that it never prunes a true solution (`frame.lisp:544-580`; `tests/invariants.lisp:120-236`). The cost is in what follows it. Turning a pulled-back predicate into explicit values takes ten hard-coded constructor rules, the learned solver entries, and seven separate functions that recover "the set of values this row allows" from requirement syntax, called from 27 sites **[C]**.

### 2.2 Where each operation lives

You wrote that lift is "wholly in the host lisp". That is confirmed, and the asymmetry is wider than lift. The table condenses the audit's operation table (core-repr report, §3).

| Operation | Available to a synthesized program | Host Lisp only |
|:--|:--|:--|
| Substitution | `:code-subst`, `:code-eval`, `:code-match`, `:code-bind` | nine further variants; `instantiate` alone has 34 call sites |
| Lift over rows | no (a program sees one row) | implicit in every frame loop |
| Lift over a container | no primitive; only as recursive library functions | — |
| Lift of a requirement through a higher-order decoder | no | `lift-frame` and helpers, about 350 lines |
| Lift over an index set | no (v1 has no `iota`) | — |
| Projection | `:at`, `:tail`, `:length` on values | all frame projection |
| Pullback | no | `pullback-frame` |
| Fiber / preimage | `:member`, `:lookup` on explicit sets | one fold rule per constructor; learned solvers for arithmetic |
| Anti-unification | no | `anti-unify` (38 lines) and six call sites |
| Quotient | no | `quotient-values`; observation buckets |
| Partition / guard | `:if` | `partition`, `infer-fibers`, `support-frame`, guard search |
| Reorientation | no | `orient-conserved-quantity`, `solve-equality-symbolically` |
| Residual | metric programs are evaluated by the VM | all residual computation |

The root cause is one fact: **terms are values of the object language; frames, rows, keys, and positions are not.** A learned program can transform code. It cannot build a frame, ask for a search, or read a result **[C]**.

The same concept is also implemented several times. "Pull a requirement to a child and compose the child's model back" exists as three function pairs chosen by flags (`synthesize.lisp:290-320`). All three begin with the same substitution and differ only in how they factor the result. "Lift" names four different things, and "fiber" three.

### 2.3 Search: the budgets were milliseconds, and the limit is structural

**Budgets.** A recursion-synthesis job runs at 5–7 million work units per second, and flat search at 33–69 million **[M]**. The default per-spec budget is 350,000 units (`consolidate.lisp:1209`), which is 0.06–0.07 s. An hour of a synthesis job is about 2 × 10¹⁰ units. The whole knowledge library regenerates, byte-identically, in about 0.4 s of search **[M]**. Across the entire planning trail, the longest wall-clock time reported for any search is 44 s **[D]**. Your statement that the budget was "very limited" is correct by four to five orders of magnitude.

**More budget alone does not help.** Four auditors tested this independently and agree **[M]**:

| Test | Result |
|:--|:--|
| 16 bootstrap specs, full grammar, no schemas; budget per spec ×1 → ×10 → ×100 → ×1000 | held-out-sound solutions: 8 → 10 → 10 → 10 of 16 |
| The seven specs that time out at 350k, budget ×10 | two more solved (`positions`, `seq-corr`) |
| The same, ×100 and ×1000 (350M work, about a minute each, 2.6–3.5 GB live) | nothing more; `map-adjacent`, `scan`, `shift-seq`, `best-shift` still cut off |
| `map-adjacent` with its own whitelist, schemas removed | bounded exhaustion, no solution, at 2.83 × 10⁹ work (8,085× the shipped budget) |
| Same, with the bit bound raised from 130 to 300 and the depth and stage budgets raised as well | still no solution when cut off at 1.5 × 10⁹ work |
| `foldl`, any budget | the same impostor: a program that fits the spec rows and is wrong |

The failures are structural first, exponential second, and memory-bound third.

- **Structure.** The search tree has two or three nodes at every budget. A node expands once, through a fixed list of host-coded proposal generators. The kernel's main recursion skeleton recurses on `(tail Xi)` with every other argument unchanged, and removes `at`, `tail`, `if` and `=` from the child's grammar (`decompose.lisp:341-382`); a second, lockstep form walks two sequences in step. The tree cannot grow deeper: a child is expanded only when some generator proposes a decomposition for it, none does, and on the four stuck specs raising `:max-depth` to 3 or 4 changed nothing. More work buys longer expressions at the same two or three nodes. It cannot buy more structure.
- **Exponent.** Work grows ×1.38–1.50 per body bit in every lane. **Each tenfold increase in work buys about one more AST node** (6–7 bits). The 1,000× budget advanced each lane by 18–23 bits. By extrapolation, an hour reaches 53–63 body bits; the known solutions for the four stuck functions are 132–259 bits.
- **Memory.** The enumerator keeps every tree, about 430 bytes each. An 11 GB heap died before 7 × 10⁸ work, about 100 s of search. By extrapolation, an hour would need roughly 180–240 GB.

The schema-assisted answer for `map-adjacent` is 260 bits under a root bound of 130, found in 109,012 work. Decomposition did that, not enumeration.

**Enumeration ignores what it computes.** v1 keeps and reuses every syntactic expression. On the real sequence grammars, 99.0–99.8% of enumerated trees are behavioural duplicates: `map-adjacent` produces 315,388 trees with 767 distinct behaviours **[M]**. Trees grow ×1.37–1.42 per bit on those grammars; distinct behaviours ×1.17–1.25.

A behaviour pruner and a columnar evaluator already exist in `v2/enumerate.lisp`, behind flags that no caller sets. Three auditors switched them on by hand **[M]**. On the three finite-field benchmarks, pruning alone cut work 6–79×, and 11–118× together with the column evaluator, with the same best model each time; a five-element field flatters pruning. On closed arithmetic frames it cut work 11–31×. On a two-variable integer grammar at 48 bits it covered the same horizon in 1/470 of the work. On `map-adjacent` it let the same work reach 70 bits instead of 47. With dedupe, each tenfold of work buys about two nodes instead of one. That is still logarithmic.

**Evaluation is not where the time goes.** In a synthesis job, evaluating candidates is about 3% of the time. The rest is the one-unit scheduling loop, ledger charging, expression construction, and metadata lookups in a weak hash table. In flat exact search evaluation is about half **[M]**.

**More budget is not even monotone.** One Plan 8 probe solves at the default budget and fails at 1,000,000 with a larger Stage A budget **[D]**.

**Policy is hard-coded in 158 places.** By class, with a decision that falls in two classes counted in both: 52 caps or prunes, 51 pieces of domain knowledge, 30 dedupe or memo guards, 30 ordering rules, 6 accounting rules (search-engine report, §4) **[C]**. This list is the concrete target for reflection.

### 2.4 Laws and algebra: a sound generic core, steered by hand

The generic core of algebra discovery is about 550 lines and works: enumerate every expression to a bit bound, run each on every row of a full finite-field grid, group by result vector, and read each group as equations **[C]**.

Everything around it is supplied by `bootstrap/build-batteries.lisp`: the field, the number of variables, the operator list for each job, the bounds, and the budgets (20,000–80,000 units). Then a host function, `law-operator-fact` (`consolidate.lisp:709-735`), keeps only three shapes: commutativity, associativity, identity. The four jobs propose 187 equations, all exhaustively true on GF(3); 14 pass the filter **[M]**.

- **Distributivity is missing for three reasons, none of them the engine.** No job contains both operators with three variables; the shape filter has no two-operator case; and the battery's budget for a job of that size is about 85 times too small. Asked directly, the existing engine puts `a*(b+c)` and `a*b+a*c` in one group in under a second **[M]**.
- **On the integers, nothing learned ever prunes.** A law may be used as a rewrite only with exhaustive, derived, or trusted-axiom evidence. Integer laws can only be sampled. So the integer rewrite set is exactly the four hand-written axioms **[M]**.
- **Where laws are wired into search, they cost more than they save.** One finite-field fixture: 182,000 work plain; 741,000 with one law; 70.2 million with 80 laws; identical results **[M]**. The documents' own diagnosis from October still holds: learned knowledge produced "cheaper requirement checks, rather than fewer enumerated candidates" **[D]**.
- **The 14 knowledge kinds are one struct with role tags.** A `:solver` is a law plus a chosen unknown port; the code builds that law to validate the solver. Six kinds have no instance in the library. About 30 edge types are written and about 10 are ever read **[C]**.
- **Every conversion that carries algebra is a hand-written shape recognizer**: law → operator fact (3 shapes), law → solver (1 shape), law star → fold motif, element solver → sequence solver **[C]**.
- **Guards are already found the way you describe.** The rows where two expressions both return a value and agree become a Boolean target, and a guard program is searched to fit it. VM errors are first-class outcomes there. It works, within a caller-supplied guard language **[C]**.
- **Nothing in the kernel initiates discovery.** Every discovery entry point is called only from tests or from the bootstrap script **[C]**.

### 2.5 The library is mostly authored

Provenance of the 61 operational library entries, recomputed from the build script **[M]**:

| How the entry came to exist | Entries | Share of bits |
|:--|--:|--:|
| Search with a generic grammar | 8 | 2.5% |
| Search with an author-chosen operator whitelist | 16 | 13.5% |
| Search steered by a hand-written recursion schema | 7 | 13.0% |
| Generic derivation (anti-unification, retyping) | 3 | 5.8% |
| Stamped by a single-purpose host template | 9 | 6.1% |
| Hand-authored expression | 18 | 59.1% |

Further:

- The eight generic-search entries are the arithmetic solver witnesses, three atoms each. Across all 19 synthesis jobs, 19% of answer bits were found at a leaf; the rest is decoder skeleton supplied by a proposal generator. The largest expression enumerated anywhere has 8 atoms.
- In 9 of 10 function specs the operator whitelist equals the operator set of the answer.
- Three specs (`foldl`, `scan`, `best-shift`) need rows that are the execution trace of the intended program, including its intermediate accumulator states.
- There was an answer key. Hand-written `library/*.lisp` (commit `849013a`) defined the same 21 entries; the bootstrap script re-derives 20 of them equivalently.

Against that, two results go the other way and matter for the design:

- **`:map` and `:foldr` come out of the kernel's own anti-unification** over six synthesized functions, and still emerge with the full generic grammar and no schemas, at 2.4× the work **[M]**. Two qualifications: `:foldr`'s measured gain is zero bits after naming, and it is not accepted when each signature has only two seed functions; and both names are supplied by the script.
- **The library compounds when it is used for lifting, on some tasks.** On 8 held-out tasks, lifting through library entries solved 3 in 25,000–42,000 work that the kernel alone misses at 35 million, and made one 3.2× cheaper; three or four others became 1.7–3× dearer. Offering library functions as plain operators, which is what the bootstrap does, never helped, and in a separate experiment with stand-in functions cost 6.6× **[M]**.

### 2.6 Reflection is plumbing without a reader

`messages.lisp` (128 lines) turns a job's messages into an ordinary frame. Its only readers are a test and an offline experiment **[C]**. Within a job, no decision reads messages or the trace.

One older loop exists in the code, though no production path calls it: search traces are condensed into a predictor that adds a clamped delta to node priority. Run on the kernel's own 16-spec curriculum, it learns the constant 0 and changes work by +0.02%. The cause is concrete: 40 of its 42 training labels saturate at the clamp, and the jobs are too small to reorder **[M]**.

An ablation corrects one claim from `plan_v2b.md`. Trace-derived artifacts are not useless: the nogood/feature group saves 2,332 work on `add-len`, but only on a re-run of the task they were learned from. Nothing trace-derived transfers. What transfers is the abstracted functions **[M]**.

### 2.7 Geometry as built

Geometry today is one number: bits.

- Residuals have eight unrelated representations (correction packets, Stage A residual lists, quotient indices, partition positions, relation tables, anti-unification substitutions, coupled conjuncts, reserve rows) **[C]**.
- The built-in distance is a fixed rule per value type, with position-only alignment for sequences (`frame.lisp:1533`).
- A frame metric is an expression over two values that, by its own documentation, cannot depend on the row; it survives a pullback in only four cases (`frame.lisp:508-518`) **[C]**.
- Node scores add program bits sized at the root to residual bits sized in the child's own space. Ambient and induced pricing are already mixed **[C]**.
- An operator's price is an accident of its position in a list: `:lookup` and `:gather` cost 4 name bits, `:at` and `:cons` 9, `:code-eval` and `:mod` 12 **[C]**.
- The work tariff is quadratic where the host is not: a recursive sum over n list elements costs about 7.5·n² work units, and two `at` reads on a 10,000-element list cost 430,941 **[M]**.
- One learned geometry exists and is worth keeping: the **metric decoder**, an invertible operator paired with its solver, where distance is the bits of the delta. It already treats a residual as a pullback into a delta space. Its measured cost was the problem: one metric evaluation took 3,334 work against a default Stage A budget of 2,000 **[D]**.

### 2.8 What the planning trail says

**Your requirements have been stable since October.** From the October prompts (14–26 October): "Topologically, computation may be seen as a projection, / In which case the reverse process requires a lift"; experiments "up to (say) depth=2 (this is essential!)"; "here we will **learn** the propagation rules"; synthesis "on the search tree and execution graph itself". From the batteries prompt: "the search process of the kernel itself produces data that bootstraps rules and complexity for further search", and, of the agents' debugging, "which again is what the kernel itself is supposed to be doing!!"

**Three things changed, by your own hand.** The store went from "one 'flat' store. A list. In lisp." to a hypergraph. Geometry went from "not essential for this proposal, except ..." (`prompt4.md`, 5 November) to bedrock. The budget went from minimal to hours.

**The same problems recur in every plan** (the reports list ten to twelve each; these four matter most):

1. *What goes with what* is always handed in. Four plans used four mechanisms. Connectivity never became a stored object. The derivation graph moved from the frame, to store entries, off the frame, and back as `pairs`/`anchors`/`edges`.
2. *The meta-level is always host code.* Plan 5 diagnosed "a second parallel language of nine `:code-*` primitives" and "Six hand-rolled state machines". There are now nine resumable state structs.
3. *Reuse loses.* Checked rewriting, certified propagation, and tentative integer propagation all cost more than they saved in nearly every measured cell, because learned knowledge never reduced the number of candidates enumerated.
4. *Each plan promised to shrink the kernel.* It grew from 900 projected lines to 4,600 to 17,647.

**Graph machinery was declined four times, on minimalism, never on a measurement.**

**Nuggets worth carrying forward** (locations in Appendix B). Numbers attributed to plans 1 and 2 came from Python scratch scripts that were never committed, so none of them can be re-run.

- *The counting identity* (plan 2): H(X) = H(f(X)) + E log|fiber|. "Running a computation backwards is lifting: given f(x), supply the index." Every computation edge has an exact bits-destroyed weight.
- *One residual definition for three cases* (plan 2): fiber index, guard or mask, and metric error. The approximate case "needs an order or a metric on D". This is where topology meets geometry in pricing.
- *Relations before directions* (plan 2): "No column is designated as input or output." An operator application is one n-ary relation; a solver is another orientation of it. Your own outline has the same move, converting conserved quantities to generative expressions "via the exchange of input and outputs".
- *Fiber versus section* (plan 7): pullback keeps the whole fiber; inversion chooses a section; a uniqueness law certifies the fiber is a point. A solver is two laws.
- *A metric and a decoder are one thing* (plan 7): "A metric and a decoder shell are two views of one correction code."
- *A guard is what a law leaves unresolved* (results, October): after an equation is observed, "the unresolved information is the membership of each input in its valid subset".
- *Laws are invisible to compression and immediate under shared-input experiments* (plan 2): run both argument orders on the same inputs and commutativity appears at once. This was a scratch result and was never reproduced in the kernel.
- *Quotient by laws before anti-unifying* (results): law-normalized anti-unification took a pattern from 5 holes to 2.
- *The matching problem is not graph isomorphism* (plan 2). It is conjunctive-query matching: hard in pattern size, polynomial for acyclic patterns.
- *Small residual magnitude is not structure* (plan 1): the correct lift ranked 66th of 2,661 by magnitude.
- *Explanation-based generalization* (plans 1–3): variabilize whatever a derivation did not depend on. It is dependency analysis on the search's own record; the best-specified reflective operation in the trail; never built.
- *Sampled evidence can propose and never eliminates* (plan 8). True as stated, and the reason nothing learned prunes on the integers. Section 5.5 shows the way around it.

### 2.9 The earlier v2 plans

`plan_v2b.md` is reliable where checked: about 35 code claims, three errors. Its Stage 0 (index columns, one behaviour table, attribution by ablation) has no imported risk. `plan_v2.md` has six academic imports and ten unverified novelties on its critical path. `plan_v2.tex` went from v2.1 to v2.4 in four hours, each pass finding fatal flaws in the one before; 21 of the 40 mechanisms its gates depend on are academic imports or the plan's own inventions; its headline numbers have no artifact behind them.

The Stage 1 code in `v2/` added 1,393 lines and no tests. The main new opcode, `:tabulate`, fails at expression construction in the form its own proposals build (`v2/ast.lisp:1096` against `:673`). Ten exported symbols are defined nowhere. Complexity rose. The Stage 0 survival audit gives the identical result on all 64 runs.

What to keep from those plans (all cheap, all grounded in something measured here):

- the Stage 0 soundness fixes and its ablation harness;
- enumeration modulo behaviour;
- index lift as preimage of `gather`, which works in the v2 code: `(= (gather C Z) Y)` splits into a length condition and, per position, a set of admissible indices;
- the distinction between lift (one program over all fiber rows) and split (a guard and a program per region);
- totality facts for variable indices, guards derived from an operator's own preconditions, and the replay guard for inverses (§7.2);
- the pricing discipline: no symmetry refund, each root row priced once;
- the list of mechanisms those audits rejected, in Appendix D, which this plan does not re-import.

Both plans share four gaps against your current prompt, and this plan treats them as requirements:

1. no analysis of hours-long budgets;
2. lift of a *requirement* is never an object-language operation;
3. experiment choice is a line item, not a mechanism;
4. as you noted in your own follow-up, too much indexing and too little general treatment of fibers and residuals.

Your margin note on `plan_v2b.md`, beside "keep the topology nested and exact, keep the geometry flat and local to each space, and compare across spaces only through verified maps", was "how, though?" Neither plan answers it. Section 6 does.

## 3. Diagnosis: three graphs computed, none stored

The findings above have one cause, stated two ways.

**The kernel computes three graphs and stores none of them.**

1. **The execution graph**: which value came from which values, by which operator, on which row. The VM computes it and returns only the final value.
2. **The equivalence graph**: which expressions agree with which, on which rows. Law discovery computes it as "buckets", reads off some equations, and drops it. Enumeration never sees it.
3. **The derivation graph**: which sub-problem came from which, by which move, and what came back. It exists as a two-node tree per job and a write-only message list.

Each is rebuilt on demand by a different host function, in a different shape, and discarded. That is why the same idea appears three or four times under different names (§2.2), why nothing persists across branches or jobs, why learned knowledge never reduces the number of candidates, and why reflection has nothing to read.

**Frames are not values.** A frame is the one place where rows, positions, and requirements live, and it is a host structure. So every operation on rows, positions, or requirements is host code, and a synthesized program can reach none of them. "Lift is not a synthesizer primitive" is one symptom. Pullback, fiber, quotient, partition, reorientation, and residual are the others.

A frame also holds one unknown per row. Constraints among several unknowns have nowhere to live, so they are weakened or carried on the side.

The remedy follows directly: store the three graphs, in one structure, made of things the object language can name.

## 4. Six perspectives on the same question

You asked for several perspectives. Each of these is a serious position on what the kernel's store should be. For each: the claim, what the evidence says, and what this plan takes from it.

### 4.1 "The representation is fine; the budget was too small"

*Claim.* Keep frames. Run for hours.

*Evidence.* The budget was milliseconds (§2.3), so the premise is right. But with hand-written help removed, sound solutions went 8, 10, 10, 10 of 16 over three decades of budget, and the search tree stayed at two nodes. Enumeration reach grows with the logarithm of the budget: each tenfold of work buys about one AST node, or two with behaviour dedupe. Going from one second to ten hours is 4.5 decades, so five to nine nodes. A model fitted by the search-literature auditor to four published enumerators agrees to within a node or two. It is an estimate, not a published figure, and it assumes 10⁶ evaluations per second: one hour of deduplicated bottom-up enumeration reaches about 17 nodes over 10 primitives (range 13–22), 10 over 30 (8–13), and 7 over 100 (6–8) **[L, estimate]**. DreamCoder needed roughly five days on 64 CPUs to rediscover fold and unfold from a fixed-point combinator; an hours-long single-thread budget is about a thousandth of that **[L]**.

Note what that estimate says about where the leverage is. Over an hour, cutting the grammar from 100 primitives to 10 is worth about ten nodes. Multiplying the budget by 3,600 is worth seven and a half nodes at 10 primitives, and three at 100.

*Take.* Design every record for 10¹⁰–10¹¹ work units. Make budget buy structure, not only leaves: resumable proposal generation, re-openable nodes, and many small searches instead of one deep one. Treat the choice of a small grammar for each problem as the main control problem (§6.3).

### 4.2 "Store the execution hypergraph literally and learn by rewriting it"

*Claim.* The most literal reading of your prompt: nodes are values, hyperedges are operator applications and tuples, and learning is pattern-directed graph rewriting.

*Evidence.* Uniform hypergraph stores have a poor record as learning substrates. OpenCog and its successor Hyperon span about 17 years with no quantitative benchmark in their own overview paper (the span is from the auditor's memory; the benchmark claim was checked against the paper's abstract); algebraic graph rewriting tools, attributed C-sets, and interaction nets are representations, not learners **[L]**. The matching each needs is conjunctive-query matching, hard in the size of the pattern. And there is a structural objection specific to this project: evaluating one expression over N rows produces N isomorphic copies of one small graph. The regularity you want to find *is* that repetition. A store that materializes the copies must rediscover it by subgraph matching; a store that is factored by rows has it for free.

*Take.* The hypergraph is the meaning of the store. It should not be its layout. Store the factorization: pattern × rows.

### 4.3 "Use an e-graph: a law is a merge of two classes"

*Claim.* Keep terms in a shared graph with an equivalence relation; apply laws as merges until saturation.

*Evidence.* The store half is cheap and mature: hash-consing, union-find, and congruence closure sit in every SMT solver. The saturation half is the hazard. Under associativity and commutativity a sum of n variables saturates to 2ⁿ − 1 classes. The one production compiler built on e-graphs reports an average class size of 1.13 and about 0.1% benefit from keeping multiple representations; its gain came from hash-consing and eager directed rewrites. Binders and conditional equalities inside e-graphs are single-group research **[L]**. In this kernel a different mechanism with the same intent, rewriting each candidate to a normal form with VM-interpreted rules, multiplied work by 385 with 80 laws (§2.4). That is evidence about rewriting during search, not about e-graphs.

There is also a point of theory that turns out to be the most useful sentence in the literature review: **e-graphs, version-space algebras, and finite tree automata are one data structure.** Classes are states; operator applications are transitions. They differ only in what a class means: "provably equal under these rules", or "same outputs on these examples". This is a research-level identification, which the auditor verified from abstracts; it is not a shipped product.

*Take.* Keep the classes. Define them by observed behaviour on a set of rows, which needs no rules, no saturation, and no rebuilding. Treat a law as a statement that a class is real beyond its rows (§5.5).

### 4.4 "A frame is a small database"

*Claim.* Rows are tuples; a frame is a relation; lift, projection and fiber are unnest, project and group-by.

*Evidence.* This is the diagnosis of `plan_v2b.md`, and its code claims held up. Frames already are tables. Plan 2 put it as "No column is designated as input or output"; your own October outline has conserved quantities converted to generative expressions "via the exchange of input and outputs". The standard relational operations have fifty years of shipped implementations, linear or n log n cost, and no research risk.

What the relational view lacks, on its own, is the other two graphs: it has no notion of a term that denotes a column, and no notion of a problem derived from another problem.

*Take.* This is the core of the proposal. Add terms that denote columns, classes of terms, and maps between tables.

### 4.5 "Keep everything in one flat vector space, as a transformer or cortex does"

*Claim.* You raised this yourself: neurons cannot be created per concept, so perhaps vectors should stay flat and high-dimensional, with context doing the composing.

*Evidence.* Nesting is not a representability problem. A tree embeds exactly in squared-Euclidean space, at one dimension per edge: give each edge its own axis, and the squared distance between two nodes is the length of the path between them; language models encode hierarchy as orthogonal subspaces; shown a graph in context, a transformer reorganizes its representation toward that graph's spectral embedding **[L]**. The economics are the issue. A shared flat space saves *storage*: m features can be represented in O(log m) neurons. It does not save *computation*: computing m features in superposition needs Ω(√(m log m)) neurons and Ω(m log m) parameters, for a broad class of problems (Adler and Shavit, verified against the paper; these are theorems about neural networks). So storage in superposition is exponentially efficient, and computation only quadratically: n neurons compute at most about n² features. A library of 10²–10³ entries has no storage pressure. Meanwhile every method that *learns* coordinates needs gradient descent and on the order of 10⁵ examples.

The paper you cited in the margin, arXiv 2611.17309, bears on this differently than the first draft said. Its model is a small pairwise energy that can represent the puzzle's rules exactly, so fitting it takes milliseconds; one hand-set value already solves every Sudoku puzzle, and three every maze. Its *solving* is search by a very large number of very cheap moves: single-cell updates in Triton kernels that touch only the cells coupled to the one that moved, at a mean of 2.0 × 10⁹ FLOPs per Sudoku. So both halves of your note hold, and the second is the one that matters here: the bits of the answer come from fast evaluation, not from the model. That argues for an exact store with cheap evaluation and scheduled lowering. It does not argue for a learned embedding. The authors add that these benchmarks are too easy, and that learning latent quantities "remains an important open research direction".

*Take.* A flat space is the right shape for *retrieval and ranking*, and the wrong place for truth. Use flat, explicit, recomputable feature vectors as an index over the exact store (§6.3). Defer learned coordinates until there is data to learn them from.

### 4.6 "A requirement is a cell of partial information; computation runs both ways"

*Claim.* The propagator view: every operator is a relation among cells, and information flows in whichever direction is known.

*Evidence.* Inverse semantics is shipped technology: the witness functions of FlashMeta are per-operator partial inverses, load-bearing in commercial products. They are also written by hand; learning them is open **[L]**. Running a general interpreter backwards does not scale; its authors say interpretive overhead "makes the relational interpreter approach impractical for most applications", and each extra interpretive level costs 6–178× until staged away **[L]**. In this kernel, pullback is 37 sound lines (§2.1).

*Take.* Keep pullback. Treat an inverse as another orientation of an operator's own table, found by a dependency test and a small search (§5.4, measured in §8). Never run an interpreter backwards. Reentrancy can be given its meaning by nested interpreters, but it should not be executed as a tower of them: collapse the tower first, by staging or lowering, or use one evaluator whose terms can mention terms, spaces, and requirements (§7.1).

### 4.7 What the perspectives agree on

| | Budget only | Literal hypergraph | E-graph | Relational | Flat vectors | Propagators |
|:--|:--|:--|:--|:--|:--|:--|
| Substitution, composition | yes | yes | yes | as re-indexing | weak | yes |
| Lift over a container or index set | host only | by rewriting | research (2026) | **unnest / nest** | no | per-operator rule |
| Fiber, preimage | host only | by matching | index on output | **group-by** | no | **native** |
| Equivalence, laws | host only | by rewriting | **native** | by equal columns | approximate | no |
| Guards, partitions | host only | by rewriting | research | **selection** | soft | conditional cells |
| Reorientation | host only | by rewriting | no | **re-keying a table** | no | **native** |
| Closeness | bits only | graph distance | no | per-column codes | **native** | no |
| Mature at the scale needed | — | no | store yes, saturation no | **yes** | needs training data | hand-written inverses only |

No single view covers every row. The relational view covers the most with the least risk, the e-graph view supplies the classes, the propagator view supplies the direction-free reading, and the flat view supplies ranking. The proposal in §5 is those four, on one store.

## 5. The proposal: one store

Sections 5 to 7 are proposal. A statement backed by a measurement cites §2 or §8. Everything else is untested, whether or not it carries a **[P]**.

### 5.1 The observation

Evaluate one expression on N rows of input. The execution graph is N copies of the same small graph: the expression's own shape, once per row, with different values on the nodes.

So the execution graph factors exactly:

> **execution graph = pattern × rows**

The *pattern* is the expression, as a graph of operator applications with shared sub-expressions. The *rows* are the independent contexts it was run in. The *values* sit at the crossings: one per (sub-expression, row).

This is your sentence from the prompt, made literal: "an expression is a common pattern found in the execution graph, just lifted to independent contexts (the labeled residual, so to speak), with the remainder a constant or conserved expression". The pattern is the conserved part. The per-row values of its leaves are the labeled residual.

The store keeps the factors, not the product.

### 5.2 Four nouns

**Space.** A finite set of rows. Rows have no content of their own; they are the independent contexts. A frame's rows are a space. So are the positions of all the sequences in a frame, the calls a recursive function makes, the instances of a pattern across a corpus, and the events of a search.

**Column.** One cell per row of a space. A cell holds one of:

- a value: integer, Boolean, tuple, sequence, or quoted code;
- a status in place of a value: *error* (with the operator and arguments that failed), *out of fuel*, or *pending* (waiting on a named call);
- a reference to a row of another space.

A column whose cells are all row references is a **map** between spaces. A map from a space to itself is an **endomap**; "previous position", "the tail of this list", and "the next time step" are endomaps.

**Term.** An operator applied to terms, or a leaf. Terms are stored once each (hash-consed), so a term is a node in a shared graph and a sub-term is an edge. A leaf names a column or a constant. A term has no rows. Evaluated over a space, it *denotes* a column.

**Class.** All the terms that denote the same column on a given space. A class stores that column once, its smallest term, and its evidence grade (§5.5).

That is the whole structure: **spaces of rows, columns over them, terms that denote columns, and classes of terms.** Everything below is these four, plus ordinary hash tables to find things.

It is a hypergraph in three senses at once. Classes are nodes and operator applications are n-ary edges from argument classes to a result class. A row is a tuple, an n-ary edge among its cell values. A map is a set of binary edges between rows of two spaces. It is laid out as arrays, because the factorization is the point (§4.2).

### 5.3 Two small examples

**An operator's own table.** Take the space of four rows below, with columns `a` and `b`, and evaluate three terms.

| row | `a` | `b` | `(+ a b)` | `(+ b a)` | `(- (+ a b) a)` |
|:--|--:|--:|--:|--:|--:|
| 0 | 2 | 5 | 7 | 7 | 5 |
| 1 | 4 | 1 | 5 | 5 | 1 |
| 2 | −3 | 7 | 4 | 4 | 7 |
| 3 | 0 | 0 | 0 | 0 | 0 |

- `(+ a b)` and `(+ b a)` have the same column, so they are one class. That is commutativity, as a conjecture on this space.
- `(- (+ a b) a)` has the same column as `b`. Name the sum `c`: the class of `b` now contains `(- c a)`. That is the inverse of `+` in its second argument.
- One could have known an inverse existed before searching for it: any two rows that agree on `a` and on the sum also agree on `b`. That test is a group-by.

Nothing here is a special mechanism for laws or for solvers. Both are terms landing in a class.

**A lifted sequence function.** The task is `map-adjacent` with `+`: from `xs` produce the sums of neighbours. The space S has one row per example. The move is to make a second space S′ with one row per *output position*, and a map from S′ back to S.

| S′ row | parent row | `i` | `xs` (from parent) | target `y = ys[i]` | `(+ (at xs i) (at xs (+ i 1)))` |
|:--|--:|--:|:--|--:|--:|
| 0 | 0 | 0 | (3 1 4) | 4 | 4 |
| 1 | 0 | 1 | (3 1 4) | 5 | 5 |
| 2 | 1 | 0 | (2 2) | 4 | 4 |

On S′ this is an ordinary scalar problem, and a nine-node term solves it. On S there is one more scalar problem, the output length. The term that is also right for an empty list is `(- (length xs) (min (length xs) 1))`. The program is `(tabulate (- (length xs) (min (length xs) 1)) (lambda (i) (+ (at xs i) (at xs (+ i 1)))))`.

No recursion was searched. The comparison with the kernel needs care. The kernel's `map-adjacent` takes the function as an argument, and without a hand-written skeleton the kernel does not find it in 2.8 × 10⁹ work (§2.3). The prototype finds the fixed-`+` version above in about a quarter of a second. It finds the function-argument version in about five seconds, on twelve of its own examples rather than the spec's eight, and not robustly (§8.1).

### 5.4 Your operations, on this store

"Re-index" below means: each row of S′ reads the cell of its parent row in S. "Collect" means the reverse: each row of S gathers the cells of its child rows, as a sequence or through an aggregate.

| Your term | What it is on the store | Cost | The program form it yields |
|:--|:--|:--|:--|
| Computation | evaluate a term over a space, giving a column | n per operator | — |
| Substitution | replace a leaf of a term by a term | size of the term | a call |
| Projection | drop columns; rows that become identical merge, leaving a map from the old space onto the smaller one | n | — |
| Fiber | the rows on which a column takes a given value; all fibers at once is a group-by | n | `where` |
| Lift over a container | unnest a sequence-valued column into a space of positions, with a map back; re-index the other columns | number of elements | `tabulate`, `select`, `scan`, `fold` |
| Lift as the reverse of projection | choose, per row, one member of the fiber. The choice is a new column, and costs log₂|fiber| bits per row unless a term predicts it | n | an index argument |
| Anti-unification | stack k terms as k rows of an *instance space*, one column per position. Constant columns are the shared pattern. Varying columns are the parameters, and varying columns that are equal are one parameter | total term size | a definition and k calls |
| Quotient | merge rows (projection), or merge terms (a class) | n | — |
| Partition, guard, conditional | a Boolean column; the sub-space of its true rows | n | `if` |
| Conservation, law | two terms in one class; or a term whose column is unchanged when re-indexed along an endomap | n | a rewrite, an invariant |
| Reorientation | test whether one column is a function of some others; if so, search for a term over those others that denotes it | n, then a small search | a solver |
| Residual | the column `r` with `y = decode(m, r)` for a target `y` and a model `m`. It is a column like any other | n | `decode(m, r)` |
| Tuple | a row is a tuple; a tuple-valued column splits into columns | n | `tuple`, `at` |
| Recursion | an endomap `s` on the space of calls. The function's column re-indexed along `s` is the value of the recursive call | n | a self-call |

Three remarks.

**There is one underlying description.** Lift, split, projection, anti-unification, and recursion all do the same thing: build a space, give it a map to a space you already have, and move columns along the map (re-index one way, collect the other). You said of the earlier six-move list that several were "flavors of the same". On this store they share one description, with different maps **[P]**. The prototype implements it as three short routines, 22 lines, and uses them only for lifts over output and input positions. Its split used a separate index, and the instance, call, and derivation spaces are not built.

**Anti-unification separates into a pattern and a quotient.** You wrote of anti-unification that "really it's a form of quotienting and trivial lifting under substitution". As intuition that holds. On the store the two halves separate: the generalization is the *shared pattern*, the constant columns of the instance space, and the quotient is the merging of terms that denote one column. (One categorical treatment, a single paper the auditor could read only in summary, likewise makes the generalization a product and reserves the quotient for merging.) Three refinements follow, from the outside review and from your "???" on the first draft's last sentence here.

- *Shared holes are equal columns.* `(+ x x)` and `(+ y y)` generalize to `(+ ?0 ?0)`, not `(+ ?0 ?1)`, because the two varying columns are the same column. The kernel's `anti-unify` already does this (§8.6). On the store it is the class test, applied to the instance space.
- *The table is only as wide as the shared spine.* Positions line up into columns only along the constructors the instances share. Where operators diverge, the sub-terms below them have no common positions, and the whole sub-term is the cell. The exception is an operator that can itself be made a hole, which the kernel's `anti-unify` does when the two operators have the same signature.
- *One class has many spellings, and the spelling decides the pattern.* The October results kept every expression's tree partly for this reason: expressions that agree on the rows may "expose different alignments for the anti-unification mechanism". If a cell holds one representative per class, anti-unification is normalize-then-generalize, which the kernel already does, and it can miss a pattern that another spelling would have shown. Taking every spelling into account means generalizing two classes rather than two terms. That is a product of two automata, quadratic in the corpus in the one published system that does it **[L]**.

The first draft said that classes in the cells would give anti-unification modulo the store's equivalences, and noted only the cost. It missed that a class has many spellings. So the cheap version is a heuristic. The full version is a search across spaces in the sense of §5.9, and is deferred to Stage D. The trail measured why the cheap version is still worth having: normalizing by laws first took one pattern from five holes to two.

**Depth-two experiments are spaces whose cells hold terms.** A space whose rows range over `(f, g, xs)`, with `f` and `g` drawn from the classes of some smaller space, lets `(map f (map g xs))` and `(map (compose f g) xs)` fall into one class. A cell that holds a function is a reference to a class elsewhere, so two such cells are equal when the functions behave alike. This is the "folded and recursively nested" structure you describe: nesting is a cell that points into another space. It is untested, and it is one of the places where the literature offers no precedent (§10) **[P]**.

### 5.5 What a class means, and why sampled knowledge can prune

Plan 8 recorded that sampled evidence "can propose and never eliminates", and the audit confirmed the consequence: on the integers, nothing the kernel learns ever reduces the search (§2.4). That constraint is real but it is narrower than it has been treated.

A class is always a class *on a space*. Three grades:

- **Observed**: the same column on this space. This is exact, not sampled, for any question about this space. Two terms in one class are interchangeable as sub-terms of any program that is judged on these rows, so enumeration can keep one and build only from it. No law, proof, or certificate is involved. The one condition is that the sub-term is evaluated on that space: a term under a `tabulate`, or inside a recursive body, is evaluated on the position space or the call space, and its class is taken there.
- **Tested**: also the same column on several fresh spaces with boundary values. Good for anything where a mistake costs time or a missed answer, never truth: ordering enumeration, normalizing before anti-unification, proposing a decomposition. The verb tables of §6.6 are of this grade.
- **Certified**: exhaustive on a finite domain, derived from certified laws, or a declared axiom. Needed only to eliminate an alternative for all inputs: to commit to a solver's answer without a fallback, or to drop a guard.

The kernel's evidence record (73 lines), its tentative-then-fallback discipline, and root verification of every finished program all carry over (§9). What changes is that the first grade, which is where almost all pruning comes from, stops waiting on the third.

The same split suggests a check on the `foldl` problem **[P]**. If the programs that fit the task rows fall into different classes on a wider probe space, the task is underdetermined. The check is not free: a class keeps only its smallest term, so the rivals must be kept or rebuilt, and evaluated a second time. The prototype does not do it, and returned its one impostor as an answer (§8.1). Today the problem surfaces only as a wrong answer on held-out data.

A **guarded law** has a simple representation: it is a class on a sub-space. Two terms that differ on S but agree on the rows where a Boolean column `g` is true are one class there. Finding guarded laws is another matter. Published systems search guards only to about four nodes, and only with pruning by implication between guards, without which the search does not finish in hours **[L]**. The prototype tested unconditional laws only. The October results put the same idea from the other side: after an equation is observed, "the unresolved information is the membership of each input in its valid subset".

### 5.6 Requirements are terms with holes

A frame row carries a predicate over one unknown. Here, a **requirement** is a Boolean term over known columns and any number of **holes**, which must come out true on every row of a space. A frame is the one-hole case.

- *Pullback* through a decoder is substitution of the decoder for a hole. The kernel does this on frames in 37 lines; here it is re-implemented on terms, against the same soundness tests (§9).
- *Coupled constraints*, the thing a frame cannot hold, are requirements with two or more holes. They are stored like any other term.
- *Splitting* a requirement is what each program construct does to it (§7.2): a tuple splits it by slot, a conditional by sub-space, a tabulation into a length requirement and an element requirement on the position space.

Because a requirement is a term, it is a value of the object language, so lifting a requirement can be an operation of that language **[P]**. Neither earlier plan made it one (§2.9). This plan has not built it either: the prototype's goals are host predicates.

### 5.7 The three graphs, stored

- The **execution graph** is the term graph together with the columns: every intermediate value of every evaluation, shared.
- The **equivalence graph** is the classes, per space.
- The **derivation graph** is a space like any other: one row per problem posed, with columns for the parent problem, the move, the work spent, and the outcome (§7.4).

### 5.8 What is and is not new here

Each piece has shipped precedent: hash-consed terms; value vectors with observational-equivalence classes, the backbone of every bottom-up enumerative synthesizer; relational tables with unnest and group-by; law discovery by collision, as in QuickSpec. In standard terms, as the outside review puts it, the classes on a space form a deterministic bottom-up tree automaton, equivalently a ground e-graph, indexed by the space; and spaces with their maps and columns are what the database literature calls an attributed C-set, which is also the core of `plan_v2b.md`. The search-literature review's own recommended recipe, assembled only from shipped or independently replicated parts, overlaps this list (lit-search report, section B).

The same review names what separates this plan from the earlier v2 plans. They tried to put *intensional* equality, true for all inputs, with binders and conditions, inside the store's merge relation. This plan merges only on *extensional* equality, on a concrete space. That is what makes the store cheap, and it is exactly what moves the hard part to §5.9.

It differs from the published recipe in one respect that matters. The published recipe's decisive step is pruning the term space with laws already found; dedupe by behaviour comes second. This plan leans on classes for pruning and keeps laws by use (§8.5). The reason is the kernel's own measurement that rewriting during search cost more than it saved (§2.4), and X1 should measure what the choice costs.

Three things are this plan's own and are marked as such throughout:

1. using *spaces with maps* as the lifting mechanism inside a synthesizer (nearest precedents: deduction through `map` and `fold` in λ², and array languages);
2. finding inverses by a dependency test on an operator's own table followed by a small search. Inverses do appear in the literature, as laws of the form g(f(x)) = x found by testing and as structural inversion from a table of primitive inverses. What has no precedent is a synthesizer learning the inverse rules it then uses; those are hand-written in every synthesizer the review checked;
3. keeping all three graphs in one structure so the search can read its own record.

§8 measures the first two on a prototype.

### 5.9 Within a space, and across spaces

The outside review named the trade this store makes, and your note on it was that it "is a fundamental limit for compression and needs to be allowed". This section takes that as a requirement. An earlier draft of this document said that no operation on the store needs subgraph matching. That is true of the store's primitives and false of the system, and the difference is the subject here.

**Within a space, everything is computed.** Given a space and the maps it already has, the operations are evaluate, hash, group, re-index, and collect. Each is linear in the cells it touches. A class is found by hashing a column. Nothing is searched for except the term itself.

**Across spaces, nearly everything has to be found.** Whenever two things are not already joined by a map, relating them means finding a witness. Checking the witness is cheap. Finding it is a search, and in the worst case a hard one.

| Question across spaces | The witness | Checking it | Finding it |
|:--|:--|:--|:--|
| Does this equality, seen on one space, hold on another? | none | evaluate both sides there | no search; this is the "probe evaluation" the review mentions |
| Is this term an instance of that pattern? | a substitution | substitute and compare | linear for a tree pattern; NP-complete modulo associativity and commutativity, or when the pattern shares structure |
| Which rows of S go with which rows of T? | a map | re-index and compare columns | a hash join when some term computes a key; graph matching when none does |
| What do these k terms, or these k derivations, have in common? | a pattern and its substitutions | substitute | linear on trees; quadratic over classes; choosing which subsets to generalize, for the best total compression, contains the smallest-grammar problem, which is NP-hard **[L, from memory]** |
| Is this problem like that one? | a map between their spaces that carries one problem's columns to the other's | re-index and compare | homomorphism search, NP-complete in general |
| Does this operator act on a coarse description of its inputs? Is this operator like that one? | a quotient and its small table; or a map between two operators' tables | the dependency test, one group-by | enumerate small terms |
| Which library entries belong in this problem's grammar? | a subset | try it | exponential in the library |

So the split you describe is exact. Computation within a space is deterministic and polynomial. Search across spaces is NP in the textbook sense: the answer is easy to check and may be hard to find. And compression lives on the second side, because shared structure between two contexts *is* a witness of one of these kinds. A store that only ever worked within spaces could compress each space separately and nothing more.

Three consequences shape the design.

**1. A witness is a store object, so finding one is an ordinary problem.** A row correspondence is a map, which is a column. A substitution is the varying columns of an instance space. A pattern is a term. Finding any of them is therefore a requirement with a hole (§5.6) whose hole has the type of a map or of code, and the synthesizer's one move applies to it. Once found, the witness is stored, and from then on moving along it is computation. The search is paid once. The witness's own description length is what the compression has to repay.

**2. There are three ways to find a map, and they should be tried in order of cost.**

- *By a term.* Some term computes, for each row of S, a key that identifies a row of T. Candidates are ordinary terms, enumerated by class; checking one is a hash join. When a key term exists, crossing spaces costs no more than working inside one. Position i of an output going with position i + 1 of an input is this case. So is an analogy between two operators carried by a function: `max` goes to `min` under negation (§8.7).
- *By refinement.* No key exists, so rows must be told apart by how they are connected. Give every row a colour; repeatedly recolour each row by the group-by key of its own cells and the colours of the rows it reaches through maps, until nothing changes; rows with a colour of their own are matched. This is polynomial, and it uses only group-by and re-index. It is the "graph walker": a signature that flows along verified links.
- *By backtracking.* Rows that refinement cannot separate look alike to it: either they are truly interchangeable, or the structure is too regular for colours to tell them apart. Pick one, try each pairing, refine again, and back up on contradiction. This is the "graph isomorphism engine". In the version measured it is 65 lines on top of 36 for refinement, and it is exponential in the worst case. In §8.7 it was needed for regular structures that have no symmetry, and to reject look-alikes that are not isomorphic. Symmetric structures matched against their own copy needed choices, and none had to be undone.

For matching a pattern into a larger structure, rather than pairing two whole spaces, the known line holds: tree-shaped patterns are polynomial, as a sequence of joins; patterns with cycles are the hard case. Plan 2 recorded this in October.

One piece of the prototype was already a cross-space search and should be read as one. To lift a selective function, the output's positions have to be mapped to the input's (§7.2). The candidates for that map are the index sets that the `gather` rule yields; the choice among them is made by a term when one fits (a shift), by a constraint when one applies (the indices increase), and otherwise it is paid for at log₂|fiber| bits per row. The subsequence aligner in the prototype is the second of those cases, written by hand.

**3. The expensive choice is which pairs to try, and that is the job of the cheap geometry.** With n problems there are n² pairs to relate and 2ⁿ subsets to generalize over. Your October outline, which still stands in `prompt4.md` (L170–175), says this in advance. The matching problem is "structure & type-aware & locality-seeded". "This is NP-hard, think, and yet some of the search can be amortized", "Hypothetically through the development of a vocabulary / short descriptive language". Plan 7 proposed the same seeding for anti-unification, by graph distance between library entries, and never built it.

On the store the seeding signals are the ones of §6.3, pointed across spaces: overlap between two problems' signatures; distance between two columns' behaviour; the colour histograms of two spaces; and counts of which pairings paid off before. They differ in one useful way. An invariant that differs between two spaces *refutes* a correspondence outright, in polynomial time. Agreement only *suggests* one. So the cheap layer prunes with certainty and proposes without it, and the exact search runs only on what survives.

Two measurements say which signals work. Overlap of store-generated signatures finds problems of the same *form* at three times chance, and does not find the *operators* a problem needs; it saved no more work than a control that ignores the task (§8.7). What did save work avoids choosing a subset at all: each operator carries a small table of what it does to coarse descriptions, and each candidate is tested against the target's description before it is evaluated (§8.8). That table is found once per operator and used in every later search. It is the amortization your outline describes, and §6.6 builds on it.

**The compromise.** Work within a space has a cost known before it runs. A search across spaces does not: §8.7 has a pair of 30-row structures that took 257,214 backtracks to tell apart. So the two are budgeted differently. Work within a space is simply done. Every search across spaces runs as a tentative attempt on its own account, with a cap, under the reserve rule the kernel already has (three parts tentative to one part fallback, §9). Its cost and its yield are rows of the derivation space, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust (X9). The order of attack is fixed by cost: refute with invariants; propose with the index; try a key term; refine; and only then backtrack.

**What allowing this costs.** Refinement and backtracking: 36 and 65 lines in the version measured. Tree-pattern matching, which is joins. Anti-unification over classes rather than over single representatives, which is a product of two automata and quadratic in the corpus; this is deferred to Stage D. Choosing what to abstract, for which the kernel's description-length-gated abstraction imports (§9).

**Where it enters the stages.** Stage A is entirely within spaces. Stage B crosses spaces only along maps it builds itself, except for the selection case above. Stage C is the first place where the choice of what to mix decides the outcome, as context selection; the quotients and tables of §6.6 are first used there, and analogies between operator tables are found as terms (X9). Stage D is cross-space throughout: abstraction over solutions, and depth-two laws.

## 6. Geometry

You consider the geometry question open, and it is. This section says what the evidence supports now, what it does not, and how the store leaves room for more. It has three jobs to cover: pricing residuals, guiding search, and language.

The outside review asked that two layers be named apart, and they are. The exact *pricing metric* is §6.1–6.2. The heuristic *retrieval index* is §6.3–6.4. Language (§6.6) grows out of the second.

### 6.1 One definition: distance is description length

In a space, the distance from column `u` to column `v` is the number of bits needed to write `v` when `u` is known.

The kernel already has this. Its codec assigns every value a prefix code, and its correction rules price a value given a prediction: for integers, a universal code of the difference, so roughly its logarithm; for Booleans, which rows differ; for sequences, a correction per position and a change of length; for code, an anti-unification edit. These per-type codes are the bedrock "these things are close". They are not symmetric, and should not be.

So the tariff and the metric are one object. Plan 7 said the same of decoders: "A metric and a decoder shell are two views of one correction code."

Measured on the kernel's own functions (§8.6), the present codes behave as follows. Integer distance is symmetric and logarithmic: 0, 4, 5, 5, 8 bits at differences 0 to 4, and 17 bits at 1000. Being concave, it has no averages and no angles, and it favours a few exact hits over many small errors. Sequence and code distances are strongly asymmetric: building costs far more than erasing, as the counting identity of §6.2 says it should. And on sequences and code, once element values are large, the present prices break the triangle inequality on some triples, where going through a third value is cheaper than going directly. That marks where the present correction code is looser than it could be.

### 6.2 Pricing residuals

Start from the counting identity in plan 2: H(X) = H(f(X)) + E log|fiber|. Running `f` forward destroys the bits that say which member of the fiber you started from. Running it backward means supplying them.

Five rules follow. The first four are standard coding theory, confirmed by the literature review; the previous plans stated the first three but gave no procedure for using them.

1. **A verified bijection transfers code lengths for free.** If two spaces or two value types are related by a map with a checked inverse, a residual costs the same on either side.
2. **A many-to-one map owes the fiber.** Pricing on the coarse side costs an extra log₂|fiber| bits per row to name the member, or the bits of a term that predicts it.
3. **A new latent column is paid for adaptively.** Cluster labels, chosen indices, and the like are coded cell by cell, each using the counts of the cells before it. This is a valid code because a decoder can rebuild the same counts. It is also what makes count-based or nearest-neighbour predictors safe to use for pricing.
4. **The graph gives the coding order.** Code the columns in dependency order. A column that a term derives from earlier columns costs only the term. A column no term derives is *free* and costs its code. The total is the description length.

5. **An exact cell is not free.** If a cell that matches its prediction costs zero bits while every other cell pays a full prefix code, the lengths sum to more than a prefix code allows. In a column priced row by row, every cell's code must include the zero, so an exact cell costs at least one bit; one more bit per column can then say that the whole column is exact. The kernel avoids the per-cell violation in its main pricing path only because it lists exception rows with their indices, and what it leaves unpaid there is one bit per model. A store that prices a residual column row by row would not avoid it (§8.6).

Rule 4 is the precise sense in which topology and geometry interlock: **the graph is the factorization of the description, and the geometry is the code on each factor.** A move is good when it turns an expensive free column into a term plus a cheaper free column.

**Is there something better than pricing in the ambient space?** You asked this directly. The theory says no induced space can price a residual below its ambient cost, except through rule 1 or by paying rule 2. What an induced space can do is make the residual smaller or more regular, so the same ambient code is shorter; and counts can replace a fixed code with an adaptive one. So ambient pricing is not what made residuals clunky. Three implementation facts did (§2.7):

- eight unrelated representations of a residual, where the store has one: a residual is a column;
- a metric that cannot depend on the row, where a column's code can depend on any earlier column;
- adding program bits sized at the root to residual bits sized in a child space. The fix is to move the child's residual back along the map and price each root row once.

One caution from the trail belongs here: small residual magnitude is not structure. In plan 1's measurement, from a scratch script that was never committed, the correct lift ranked 66th of 2,661 by residual size. Residual size should rank proposals only together with regularity, meaning whether the residual column itself falls in a class with a small term.

### 6.3 Guiding search

The control problem with the most leverage is choosing what to mix into each problem: which library entries, which other problems' solutions, which pairs of spaces to try to relate (§5.9). Choosing a small grammar is its commonest form (§4.1). Published results agree: five extra helper functions took one recursion synthesizer from 0.07 s to 128 s **[L]**; in this kernel, offering library functions as plain operators never helped and once cost 6.6× (§2.5).

Four signals can do that job. None is a description length between columns; together they are an index over the exact store. All are computed from the store, none is trained by gradient descent, and all only rank or propose. They are listed in order of evidence.

1. **Behaviour.** A column is already a vector, one coordinate per row. The distance from a candidate's column to the target says how nearly it fits. A near miss proposes a split (find a guard for the rows that disagree) or a residual. A library function whose column on these inputs is near the target proposes itself. Reported gains for distance-on-behaviour synthesis are 56–664× in search-space size in one study, whose metric was supplied by an expert and whose figures come from a 2018 draft, and more than 10× over the prior state of the art in another **[L]**. The known weakness is that program spaces are rugged, so this ranks; it never prunes.
2. **Signatures.** A signature is a fixed-length vector of cheap yes/no properties of a problem: output the same length as an input; output elements a subset of an input's; output sorted; target constant along some map. In one published comparison, 45 hand-written properties of this kind beat learned embeddings as the input to a small trained network **[L]**. That is evidence for the features, not for using them without training. Here the properties would be small Boolean terms over the problem's own columns, generated by the store's enumerator rather than listed by hand **[P]**; today's descriptors are a fixed menu of ten, written in kernel source. **The signature space is the flat space.** Every problem from every space maps into it, and nearest neighbours among past problems are found there. Measured for this revision: such properties recognise a problem's *form* at three times chance, and do not pick its operators (§8.7). §6.6 gives the form that composes: a property becomes one label of a quotient, and each operator gets a table of what it does to labels.
3. **Counts.** How often each operator, each move, and each library entry appeared in an accepted solution, given the parent operator and given the signature. Counts become code lengths. They order enumeration, they select the ten or so primitives in scope, and they set the price of an operator's name, which today is an accident of list order (§2.7). The published precedent reweights a grammar during search with no training data, within a single task; its gain is large against a weak baseline and modest against a strong one **[L]**. Counts across tasks, as proposed here, go beyond it. Naive Bayes over signature bits, with backoff to coarser signatures, is the simplest form that has shipped elsewhere. An earlier audit of this project classed it as unproven at a library of under a hundred entries, and X4 is the test. A first measurement, on a hand-written library of 61 operators, is in §8.8: as an ordering it gave 2.6×, and it ranked operators it had never seen in a solution 51st to 58th of 61, which as prices sent most tasks that need one past the search cap. So counts cannot be the only source of a name's price (§6.6).
4. **Graph proximity.** A random-walk score over the store's own links, seeded at the current problem: "proximity flows along verified topological links". The algorithm is mature and updates locally when the graph changes. It has the least evidence for this use, and comes last. It is in the same family as the spectral embedding that an earlier audit pass rejected as too heavy for a library of a few hundred (Appendix D), and it is open to the same objection.

### 6.4 Making, collapsing and moving spaces

Your margin note on "compare across spaces only through verified maps" was "how, though?" On this store the answer is short.

- **A space is made by a move.** Lift makes a position space; split makes a sub-space; anti-unification makes an instance space; recursion makes a call space; a residual makes a new column. Whether the result is kept is a description-length decision: total bits with it against total bits without. That is the one principled, gradient-free criterion the review found for "when is a new space needed", and the kernel already has it.
- **Two spaces collapse when a bijection between them is verified.** For example, the positions of `xs` and the positions of `ys` are one space when the lengths agree on every row; then `zip` is just two columns side by side. Geometry may propose candidate pairs. The test is exact.
- **A vector moves by re-indexing or collecting along a map.** To compare columns from two spaces, move both to a space they share, in the end the root, and compare there.

That keeps nesting in the exact store, where a cell may point into another space, and keeps the geometry flat, explicit, and local: a column's own code inside its space, and one signature space across all of them.

What this does **not** provide, stated plainly because nothing in the literature provides it at this scale either:

- coordinate spaces learned from a handful of samples;
- vectors that keep their meaning while spaces are created and merged around them;
- collapsing spaces on geometric evidence alone;
- a nested engine shown to beat both a flat embedding and a plain symbolic graph.

On the flat-versus-nested dilemma itself: it is not a question of what can be represented (§4.5). A flat shared space buys storage economy, which a brain needs and a library of a few hundred entries does not. If the library reaches a scale where learned coordinates have data to learn from, the signature space is where they would attach. Nothing in the store has to change for that.

### 6.5 Values that carry real geometry

Lengths, areas, orientations, and real-valued measurements enter as value types. A type brings three things: a code for its values, an invertible `decode` operator that applies a correction, and the solver for that operator. That triple is exactly the existing metric decoder. This plan does not design those types. It notes that adding one touches no other part of the store.

One of your margin notes reads "new (local) metrics may be admissible, even if they are not desireable". Its placement, beside the bullet on ledger parity, leaves open whether it is about metrics of work or of distance. If the second, this design admits a local metric in that sense: it is a code attached to one column, and it must still pay its way in total description length.

### 6.6 Language: the amortization of search across spaces

The first version of this section built almost nothing and said language could wait. Your note on it asked whether nothing could be adopted from the other plans, and you wrote that the representation which yields language probably unlocks other expensive parts of the research. Both points hold. The reason is already in your October outline (`prompt4.md` L174–203):

- the matching problem across frames "is NP-hard, think, and yet some of the search can be amortized", "Hypothetically through the development of a vocabulary / short descriptive language";
- amortization forms "a type of semantic 'addressing space' over the learned rules, algebras, solvers", compositional like docstrings and function names, "a graph over the graph of heterogenous experience data";
- "True compositional addressing requires variable compute when decoding the address";
- "A language enables compositional description of the labeled computation", "In a form that is shorter and cheaper than executing the function / rule / algorithm itself. Thus it is a form of heuristic."

Read against §5.9, that is a design: **language is the amortization of search across spaces.** The outside review's second section supplies the mechanism this section lacked. Two measurements made for this revision say how far it goes: one of a vocabulary without that mechanism (§8.7), one of the mechanism itself (§8.8). The section also keeps the like and analogy rows of the mapping in `plan_v2b.md` §7.8, the `like`/`analogy`/`act` query forms named in `plan_v2.tex` without the vectors `plan_v2.md` gave those words, and plan 7's coupling of names to tariffs.

**What a flat description cannot do [M].** The obvious design makes a word a property of a problem, and a description the set of properties that hold. §8.7 measured it. Properties were generated by the store's own enumerator, kept when true on every example of a task, and used to find each task's nearest neighbours among solved tasks. The neighbours share the task's *form* three times as often as chance. But a grammar built from the neighbours' operators solves the task no more often than one built from the commonest operators without looking at the task (67% against 69%), and summed over tasks no search work is saved. A set of tags on a problem has no account of what each operator does to the tags. Your outline says so in advance: the description has to be compositional, and decoding it has to take compute.

**Words, and what operators do to them.** The first two rows are the review's proposal, restated in the store's nouns; the third comes from §8.7.

| Your word type | The store object | Its meaning | Cost |
|:--|:--|:--|:--|
| 'like' | a *quotient*: a small term that takes a value to one of a few labels, such as `(sgn x)`, `(mod x 2)`, or `(min (len xs) 5)`. A Boolean property is the two-label case | the labels are the words; two values with the same label are alike in that respect | one small term per value |
| 'action' | a *verb table*: for one operator and one quotient, the table from the labels of the inputs to the labels the output was seen to take, with counts | what the operator does to descriptions | one group-by over the operator's probe table (§7.5), once, when the operator enters the library |
| 'analogy' | a *map that carries one operator's table onto another's*: negation carries `max` to `min`, because `neg(max(a, b)) = min(neg(a), neg(b))` | "as A is to B" is the map; "so C is to ?" is the map applied to C | one equality, checked over the rows |

The three rows are one object seen three ways. A quotient that an operator respects is an analogy: it carries the operator's large table onto a small one. The test has one form in every row: are the labels of the output determined by the labels of the inputs? When the small table is not known in advance, that is the store's dependency test (§7.6), and the table is what the test returns. When both tables are known, as between two existing operators, it is an equality checked row by row; §8.7 tested 350 candidate maps between operator tables that way in 1.3 ms, and 29 held, 12 of them between two different operators. The review uses a fractional form of the test, the share of the output label's uncertainty that the input labels remove, and calls it lumpability.

**A description is a run on labels.** The description of a value is its labels. The description of a program is what comes out when it is run on labels through the verb tables: a few look-ups, and no data touched. That makes your sentence literal. The description is shorter, since a label is a few bits, and cheaper than executing, since it is a look-up. The description of a problem is the labels of its inputs and of its required output on each row, which is the signature of §6.3. So signatures and language are one mechanism. This is the first change the review proposes, and it is adopted. What the flat design lacked is the middle term: the verb tables, which let a description pass through a program.

**What it buys in search [M].** The review reported experiments whose code is not in the repository, so one auditor rebuilt them (§8.8). The setting is a hand-written library of 61 operators in Python, most of them on whole sequences, six quotients, and tables learned from 2,000 probe values per operator in 180 ms. It is not the kernel's library and not the prototype.

- The search evaluates 14 to 18 times fewer candidates (geometric means over 20 tasks, in two task sets, with the operators in listing order and averaged over random orders; between 3 and 60 times on all but one task in listing order).
- It works for the two operators held out of every solved task. With the baseline averaged over operator orders the gain is 21 and 14 times on tasks that need one (the two task sets), against 15 and 26 on the others; in listing order it is 11 and 12 against 16 and 26. A table needs the operator's own probe rows, and no solved tasks.
- As prices, counts fail there, as the review says. Naive Bayes over signature bits, which §6.3 proposed, ranked the never-used operators 51st to 58th of 61, and used as prices it sent 5 of 8 such tasks past a cap of three million candidates (6 of 11 in the second task set). Used only as an order it still gave 1.7 and 3.1 times on those tasks.
- Used only to order the operators, with nothing pruned and so no answer lost, the tables give 6 times, against 2.6 for Naive Bayes.
- Quotients chosen automatically keep about two thirds of the gain of the six listed by hand (10.7 against 15.8).

**What it does not buy [M].** The same reproduction found five limits. The first corrects the review.

- *It is not sound.* The review reports zero misses. On 300 random tasks the rebuilt version lost 11% of answers with 100 probes per operator, 0.3% with 1,000 to 3,000, and none only from 10,000 random probes, or from 1,000 when the probes are chosen to include edge cases. The cause is specific: a combination of input labels never seen is treated as "anything", but a combination seen with an output label not yet seen is treated as impossible. Merging three quotients into one product, a plain version of what the review does, lost 8% at 3,000 probes. So a verb table is *tested* knowledge in the sense of §5.5. It may order. It may filter a tentative first attempt that has a fallback. It may not eliminate.
- *In candidates it behaved as a constant factor over the sizes tried.* The gain was 11 to 16 times for programs of 3 to 6 nodes, on 38 single-input chains with the six quotients; the data cannot exclude a drift of 15% per node either way. So the filter removes about one level of branching. The factor depends on the vocabulary: one quotient gave 3 to 6 times, three gave 6 to 13, six gave 16, and merging three into one product gave 24, with answers lost. Only the six-quotient setting was run against program size. A later split of the 60-task comparison by size shows the merged product's gain rising, 12, 23, and 30 times at sizes 3, 4, and 5, on the tasks it did not lose. That is the one hint that a finer vocabulary might change the growth rate and not only the constant, and it comes with lost answers.
- *It does less for memory than for candidates.* Stored classes fell 2.3 to 2.8 times, or 7 to 9 with a one-step look-ahead the auditor added. §8.4 found memory to be the wall.
- *The saving in time is smaller than in candidates.* Each candidate that survives costs about seven look-ups. Wall time improved 1.3 times at size 4, 2 times at size 5, and 4 times at size 6.
- *Nearly all of it is one test,* made before a candidate is evaluated: could this operator, on arguments with these labels, give the labels the target has? Discarding a candidate only after evaluating it gives 1.5 times. Planning further ahead over the tables added almost nothing: the bound on how many steps remain rarely exceeds one or two, because a two-argument operator with a free second argument connects nearly any label to any other. Ranking by how surprising a candidate's labels are, which the review folds into its headline method without a separate figure, added 3–5%.

**Where words come from.** Choosing quotients is the slow part: 19 s in the reproduction, against 0.18 s to learn the tables. Candidates are small terms into few labels, generated by the store's enumerator and deduplicated by the partition they induce, so that `(mod (+ (* 3 x) 1) 4)` and `(mod x 4)` are one candidate. Each is scored by the dependency test against every operator in the library. On the integers this reproduced the review to within 0.002: over `+ − * neg` every `(mod x k)` scores exactly 1; `(sgn x)` ranks first of 1,109 once `div`, `mod`, `max`, and `min` are counted, on this grid and with floor division; the arbitrary predicates the review used as distractors rank 330th or lower. On sequences the capped length ranks first of 5,475 **[M]**. Four things had to be supplied by hand, and each is a design item:

- a rule against redundancy: ranked by score alone, the top fifteen sequence quotients are all the length;
- the grammar of candidates: the sign, parity, and order patterns of a whole list, which did most of the work in the search experiment, could not be written in the pool that was enumerated;
- the pairing of a quotient on lists with one on integers, which is what makes `sum`, `head`, and `len` informative;
- a convention: a quotient whose output label is constant must score 0, or vacuous predicates rank first.

Two further sources are proposal **[P]**. The rows where the VM faults give two-label quotients directly (`x = 0`, `len = 0`): a guard learned from a crash (§7.5) is a word. And once the kernel has solved problems of its own, a word can also be kept for shortening the derivation space of §7.4, that is, for predicting which refinement succeeds. That criterion needs history. The dependency score does not, which is why it comes first.

**The code for names.** Plan 7 asked for names "whose usage probabilities and context affinities are coupled to the search policy and language tariffs". The measured form of that coupling is the ordering above: an operator's place in the enumeration, and so its price, is read from how well its verb tables fit the labels of the problem at hand. Prices from counts of past use are the form that failed on new operators. So the rule is that a name's price comes first from its tables, and from counts only as a correction that cannot price a name out **[P]**.

**What the vocabulary unlocks.** You suspected that the representation behind language would pay for itself elsewhere. Here is the list, with evidence where there is some.

1. *Signatures* (§6.3). The same mechanism.
2. *Choosing what to mix* (§5.9). "Which library entries belong in this problem's grammar" asks for a subset, and is exponential in the library. The tables replace it with a few look-ups per candidate **[M]**.
3. *A library whose new entries are not starved.* A new entry gets its tables at once **[M]**. In this kernel, offering library functions as plain operators once cost 6.6× (§2.5). No run varied the size of the library, so whether the filter keeps search from slowing as a library grows is not measured.
4. *Guards* (§5.5). A guard is a two-label quotient, and a Boolean column is a bit mask over rows, so "this guard is valid for this law" and "this guard implies that one" are each one mask operation. For four laws, the weakest of 47 to 151 valid guards was found that way, 0.5 ms for all six laws tried: `(<= b a)` for `max(a, b) = a`, `(!= b 0)` for `div(a*b, b) = a` **[M]**. It is unique only when some guard in the pool agrees with the law on exactly the right rows; a divisibility law had seven weakest guards.
5. *The memory wall on arithmetic* (§8.4). On `+ − * neg`, reduction modulo a small prime is an exact analogy, and it can be applied to a whole column at once. Stored classes fell 8.5 to 26 times on six targets, and none of 200 random targets was lost **[M]**. With `div` and `mod` in the grammar it is not an analogy, and lost 117 of 120 targets that need them. So it serves pure ring sub-problems, or a tentative first pass.
6. *Reflection* (§7.4), in part. The tables are themselves reflective knowledge of the cheapest kind: what the kernel knows about its own operators, got by running them. Operators with similar tables are near-synonyms: of the 32 operators placed in a hand-listed family, 22 have a family member as their nearest table among operators of their type, where chance gives 9 **[M]**. But an index of past problems did not pay in the one small test. In five streams of 20 tasks, replaying every stored solution found all 25 repeated tasks at no more than 57 candidates per task; an index keyed on 23 hand-written properties that hold on every row found 19, and keyed on the labels of the six quotients, 9 to 14. That test was an outline, and replay costs three candidates per stored solution, with at most 19 stored here. The third change the review proposes is not adopted for now (Appendix G).
7. *Descriptors of functions.* The kernel's fixed menu of ten becomes learned quotients **[P]**.

**The three query forms** named in `plan_v2.tex` get exact meanings, with no vectors and no interpreter of their own, which was an earlier audit pass's objection to them (Appendix D): `like x` returns what shares x's labels, or for an operator, what has a near table; `analogy a b c` finds a stored map, or a small term, that carries a to b, and applies it to c; `act` applies a move.

**Language with people** comes last and attaches to the same tables: a human label is aligned to words by co-occurrence counts. That is the one approach with evidence on small data. In its published form it raised solve rates in one domain from 42.6% to 82.0%, with gains persisting when no language was given at test time **[L, one research lineage]**. That system sits on a neural search component, and with human rather than synthetic descriptions its best result in that domain fell from 98.2% to 58.6%.

**Precedent, and what has none.** Guiding synthesis by running candidates on abstract values is established, and the review's citations for it were checked against the papers **[L]**. One system, Simba, solved 519 of 544 bit-vector problems against 456 and 409 for two leading enumerative solvers, though on the conditional problems of the same suite one of those two wins. Another, Blaze, reports a 90-fold speed-up over a deployed synthesizer in one domain. In all of them the abstract meaning of each operator is written by hand, with one exception, and the review overstates how much is automatic. The exception, Atlas, learns its predicates from four training problems per domain, fits each operator's abstract behaviour from random samples, and then checks the fit against operator axioms supplied by hand. It reports 8.3× and 9.2× over hand-written abstractions on its own benchmarks, and 2.1× and 3.1× on its predecessor's. A 2024 paper still describes this kind of pruning as one that "requires manually designed, domain-specific abstract domains and semantics". No published synthesizer was found that reads an operator's table off its own samples by grouping, with no solved tasks and no hand-written semantics; and no use of the dependency score to choose abstractions for synthesis. Both were measured here, once, in Python. What has no precedent at all is the compounding: a vocabulary that a system chooses for itself and that goes on improving its own search as its library grows.

**Staging.** The vocabulary is not a late stage. Stage A already builds probe tables, for laws and inverses; a verb table is one more group-by on such a table, so X2 can report them. The tables must be larger for this: a thousand or more probes per operator, chosen to include edge cases, against the 8 to 32 rows that laws need. Stage C is where they are used, and X4 is rewritten as the test. Labels from people remain last.

### 6.7 What remains open

- Whether behaviour distance ranks well enough in practice to pay for computing it. The existing metric decoder taxed every search of its type (§2.7).
- Whether store-generated signatures separate problems as well as hand-written ones. For a problem's form they do better than chance by three times; for its operators they do not (§8.7). No hand-written set was run beside them.
- Whether verb tables pay on the kernel's own library, and inside lifted forms, where the terms are element-level arithmetic and a single row carries little (§8.8). X4 is the test.
- Whether quotients the store chooses for itself reach the gain of a list made by hand. In the one measurement they kept two thirds.
- Whether any vocabulary changes the exponent of search, and not only its constant. In candidates, six separate quotients did not over sizes 3 to 6; a merged quotient showed a rising gain and lost answers (§6.6).
- Whether counts over tens of solved problems carry signal at all. The existing six-number predictor learned a constant (§2.6).
- Whether any use of geometry beats the plain store with no guidance. §11 puts that ablation ahead of building anything in this section beyond the per-column codes.

## 7. The VM and the synthesizer

### 7.1 The VM: what stays and what changes

The metered VM is the cleanest part of the kernel and stays in design: prepaid instructions, exact resumption after a cutoff, exact ledgers, and results that are identical however the run is sliced. So does the rule that every finished program is verified at the root on every row.

Five changes.

**1. Evaluate by column.** The unit of evaluation becomes one operator applied down one column, memoized by (term, space). The class table is that memo. The ledger still charges one unit per cell, so accounting stays exact. This is aimed at the measured cost: in a synthesis job, evaluating candidates is 3% of the time and per-unit scheduling and bookkeeping is most of the rest (§2.3).

**2. Keep faults as data.** A failed cell records which operator failed on which arguments. A pending cell records the call it waits on. Today a fault is an unstructured string that exact search discards immediately (`vm.lisp:384`, `enumerate.lisp:426-441`). Kept, it is the training data for guards and for totality (§7.5).

Pending cells also close a soundness gap the audit flagged in v2's dormant pruner, which treats two unresolved cells as equal. Two pending cells are equal only when they wait on the same call.

**3. Give sequences their introduction and elimination forms.** Six primitives: `length`, `at`, `tabulate` (build a sequence from a length and a function of position), `fold`, `scan`, and `where` (the positions satisfying a predicate). Sequences become arrays, so `at` is one unit instead of linear in the index.

An earlier audit pass removed `:tabulate` and `:loop` because they "Smuggled `map-indexed`/`foldl` into host Lisp via higher-order opcodes", and the next pass put them back. The line this plan draws is: **a primitive may encode the shape of a container, never the content of a domain.** `tabulate` is to a sequence what `tuple` is to a tuple, and `fold` is to a sequence what `at` is to a tuple. They say how a sequence is built and consumed. They say nothing about arithmetic, correlation, or any particular function. What goes inside those forms is then a term to be found. §8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter`. It did not attempt the higher-order `map` and `filter` themselves.

The same rule says what a *learned* container would be. On the store a container is a recipe for a space: which rows a value unfolds into, the map back, and how to rebuild or reduce. A library entry of that shape, a pair of terms that unfold and build and are inverse on the examples, would describe a data structure in the store's own nouns: a matrix as two nested position spaces, a tree as a position space with a parent endomap **[P]**. Nothing before Stage D depends on it.

The evidence for granting this much: with such combinators and deduction through them, one published synthesizer has a median of 0.43 s on its benchmark suite; without them, rediscovering `fold` from a fixed-point combinator took about 7,700 CPU-hours **[L]**. Demanding that the kernel find lifting from raw recursion, in hours, on one thread, is not a realistic test of anything.

**4. Let a program observe a failure.** One form, `(try e fallback)`, so that a guard learned from failures can be written in the object language. It applies to errors, not to running out of fuel.

**5. Price names by use.** An operator's name costs −log₂ of its share of uses in accepted solutions (§6.3), under a prefix code as now.

**A consequence worth stating.** With these six primitives, the store's own operations are ordinary programs over sequences. A column is a sequence indexed by row. A map is a sequence of row indices. Re-indexing along a map is `gather`, which is `tabulate` over `at`. A fiber is `where`. Unnesting is `tabulate` over the lengths. So "lift is a synthesizer primitive" can hold in the strong sense you asked for: the operations the synthesizer performs on its store are expressible in the language it synthesizes, and the records of those operations (§7.4) are data it can be pointed at. This is homoiconicity extended from code to the layout of data **[P]**.

### 7.2 The synthesizer: one move

A **problem** is a space, a requirement with holes (§5.6), a context (the classes available as leaves), and a budget account.

The one move is: **refine a hole with a construct.** Choose a hole. Choose a program construct with fresh holes of its own. Substitute it. Split the requirement the way that construct splits it. The children are problems of the same kind, possibly on a new space.

| Construct | How the requirement on the hole splits | New space |
|:--|:--|:--|
| a leaf from the context | checked directly; this is enumeration by class | — |
| `(f k ?z)`, a library function with a known inverse | a requirement on `?z`, through the inverse | — |
| `(tuple ?a ?b)` | one requirement per slot | — |
| `(if ?g ?a ?b)` | `?a` on the rows where `?g` holds, `?b` on the rest; accepted only under the rule of §8.5 | two sub-spaces |
| `(tabulate ?n (λ i. ?e))` | `?n` is the length, on the same space; `?e` is the element, on the position space | positions of the output |
| `(gather xs ?idx)` | per position, `?idx` lies in the set of indices where `xs` has the wanted value | positions of the output |
| `(where n (λ j. ?keep))`, and selection of elements | `?keep` is whether position j survives | positions of the input |
| `(scan ?init (λ acc x. ?step) xs)` | `?step` on the position space, with the previous output as a column | positions, with a "previous" endomap |
| an aggregate of `?e` over `?n` positions (a sum, product, maximum, minimum, or count) | `?n` is the number of positions; `?e` is not observed, so each candidate element term is collected under each aggregate in scope and compared (§8.6) | positions |
| `(fold ?init (λ acc x. ?step) xs)` | does not split unless intermediate values are observed (§7.3); otherwise `?step` is enumerated by class | — |
| a self-call `(self ?s)` inside a recursive body | `?s` is any term whose value is a row of the call space | the call space, with an endomap |
| `(decode ?m ?r)` | `?m` need only be near; `?r` is solved from `?m` and the target | — |

Each row pairs a construct the VM can run with the law that splits a requirement on it. This is what the previous plan was reaching for with a "symmetric instruction set", stated as one table.

The selection row needs one more granted piece than the others. To recover which input positions survive, the output has to be aligned to the input as a subsequence. That alignment is the preimage of selection, in the way the index sets are the preimage of `gather`. An earlier audit pass rejected a subsequence propagator as specific to `filter` (Appendix D), and the prototype uses one (§8.1). The case for it is the rule of §7.1: it concerns the container, not any domain. §5.9 gives the better reading: it is a search for a map between two position spaces under an order constraint, and it should be built as that.

Two further rules for this table come from the outside review and were reproduced (§8.6). An inverse's guard has two parts with different sources. *Uniqueness* is read from the operator's table by the dependency test. *Existence* needs no search at all: a candidate answer is replayed forward and compared. And a split competes in the same size order as everything else: it is never accepted ahead of a smaller unsplit term.

Those splitting laws are Boolean equivalences. For example, `(= (tuple ?a ?b) y)` holds exactly when `(= ?a (at y 0))` and `(= ?b (at y 1))` both do. So they are laws in the store's own sense: two Boolean terms in one class. The handful for the structural constructs are seeded by hand, as the ten constructor rules are today. They can be checked by the collision engine, and in principle found by it **[P]**. Library functions get theirs by reorientation (§5.3), not by hand.

**Control.**

- The agenda holds problems. A problem's budget is an account that can be topped up, so every problem is resumable and can be re-opened.
- When leaf enumeration under a problem reaches its current horizon, further budget goes to the next-ranked *refinement* as well as to deeper leaves. This is what lets budget buy structure (§2.3).
- Refinements are ranked by signature and counts (§6.3). At cold start the order is a short fixed list keyed on types.
- The tentative-versus-fallback reserve imports unchanged: a refinement that rests on tested rather than certified knowledge always leaves budget for the plain alternative.
- One bank of classes per (space, context) serves everything that enumerates there. Today the same grammar is enumerated separately for Stage A, for the node's own search, for guards, and for features (search-engine report, §11).

### 7.3 Recursion without hand-written skeletons

The audit found that the kernel's recursion is one main template, with a lockstep variant, plus five hand-written schemas, each of which is the same act with a different hand-chosen argument tuple (§2.3). On this store the cases separate, and most stop being recursion.

1. **Position-wise functions** (`map`, `zip`, `reverse`, `shift`, `map-adjacent`, `gather`, and the library's `positions`, which is the index list k, k+1, …): a `tabulate`. No recursion.
2. **Selective functions** (`filter`, positions of a value): a `where` over input positions, with the keep-column recovered by aligning output to input.
3. **Recurrences on the observed output** (`scan`, running totals): the previous output is a column on the position space, re-indexed along the "previous" endomap. An ordinary scalar problem.
4. **Reductions to a scalar.** There are two kinds. A reduction of an element-wise term under an associative aggregate (a sum, a product, a count, a dot product) is a change of space after all: enumerate the element term on the position space and collect it under each aggregate in scope (§8.6). A fold with sequential state (`foldl` with an arbitrary step, a Horner evaluation) is not. Its intermediate accumulator is not observed, so the requirement on the step function does not split. For those, two routes:
   - enumerate step functions by class over the leaves `acc` and `x`, each candidate costing one fold per row (§8 measures this);
   - notice when the rows themselves contain the intermediates. If one row's input is a prefix or a tail of another's, that relation is an endomap on the space of examples, and the accumulator column is observed after all. The bootstrap's "trace-complete rows" are this, supplied by hand as a convention. On the store it is a property the data either has or lacks, and a group-by detects it.
5. **General recursion**: the calls a function makes are rows of a call space, and the recursive call is an endomap on it. The argument of the self-call is one more hole. Candidates are ranked by how many rows land on a known row and by whether some measure decreases; the kernel's termination check (about 50 portable lines) imports for the second.

Case 5 is research with replicated precedent, not engineering: published recursion synthesizers need examples closed under the recursive call, or angelic execution to relax that **[L]**. By inspection, cases 1–4 are the shapes of the functions in the current library **[P]**. The prototype tested first-order instances and two function-argument forms (§8.1). It did not test `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`, or the higher-order `map`, `foldr`, and `filter`; §8.6 has since run the first five on the kernel's spec rows. `best-shift` plausibly needs two lifts, which were not tested either.

### 7.4 Reflection: the search as a space

Each problem posed is a row of the **derivation space**. Columns: parent problem, construct chosen, signature, context size, work spent, classes created, outcome, bits of the best answer.

Its readers, in order of evidence:

1. **Memo.** Two problems with the same space, the same requirement class, and the same context are one problem. This replaces the present reuse key, a sorted printed string, and it holds across branches and across jobs. Your margin note on "Nothing persists across branches or jobs" was "yeah that's a big problem"; this is the fix. The memo is exact, so it misses the same problem posed on fresh rows. For that there is *replay*: before any search, run every stored solution of the right type on the new rows. On 25 repeated tasks with fresh inputs and at most 19 stored solutions, replay found all 25 at no more than 57 candidates per task; an index of past problems found 19 at best (§8.8). Replay's cost grows with the store, so an index may still be needed later; the one tried did not earn its place.
2. **Counts** (§6.3).
3. **Attribution by ablation.** Re-run a held-out set with one learned thing removed, and keep only what pays. The literature's warning is specific: one planner kept 4–6% of its learned rules and ran 65% slower without that validation; one lemma library showed a single reuse among 20,000 entries **[L]**. Stage 0's ablation harness imports for this.
4. **Explanation-based generalization.** On a shared term graph, "what did the winning derivation actually read" is a walk over edges. Whatever it did not read can be made a variable. Plans 1–3 specified this and never built it.

**Messages, nogoods, and the pruner are one table.** You asked whether behaviour pruning is a case of the message idea in the old code, and whether UIP and DIP are too. They are. The pruner's fact is "this column equals one already kept": a claim with its evidence, which is what plan 4 called a message. A nogood is the same kind of fact about a requirement, a dependency test that failed: this projection gives equal inputs to rows that need different outputs. The UIP step generalizes such a fact by anti-unifying clauses. The DIP step searches for a column that separates the conflicting rows. Today these live in three structures (observation buckets, clause lists tied to node ids, `:dip-feature` entries), and only two narrow forms are persisted: nogood schemas for one map-shaped decoder, and the separating features. On the store they are all facts about classes on a space, kept in one table and shared across nodes and jobs. The pruner is also the cheapest reflection there is: the search reading its own record so as not to repeat itself. What a learned policy could add is prediction, skipping an evaluation that a law or a count says will collide.

Because the derivation space is a space, the synthesizer can be pointed at it: find a term that predicts `outcome` from the signature columns. The existing `yield-gate` experiment proves that plumbing. It is not on the critical path, and the one learned predictor that exists today learned a constant (§2.6).

The audit's inventory gives this a concrete target (§2.3). Of the 158 hard-coded decisions, the 30 dedupe and memo guards become the class table and the problem memo; the 30 ordering rules become counts; the 52 caps become budget accounts that defer rather than drop; the 51 pieces of domain knowledge become library entries or are deleted. That mapping is a goal to check item by item, not a result **[P]**.

### 7.5 Discovery: an agenda the kernel fills itself

The audit found that nothing in the kernel initiates discovery (§2.4). On the store the questions can be listed mechanically. For each library entry `f`, starting from the primitives:

- **Laws.** Classes on a standard probe space over `f` and the operators in scope, to a size bound.
- **Inverses.** Per argument: the dependency test; a guard for the rows where it fails; a small search for the term.
- **Definedness.** A guard for the rows where `f` returns an error. The kernel's milestone code already does this for arithmetic (§2.4).
- **Words.** For each quotient in the vocabulary, `f`'s verb table: one group-by over a probe table of the same kind, with a thousand or more rows. And `f` becomes one more operator against which candidate quotients are scored (§6.6).
- **Lifted forms.** `f` under `tabulate`, `fold`, and `scan`.
- **Abstraction.** Anti-unify the terms of accepted solutions, over the instance space.

Each is a small bounded problem; §8 gives their measured cost. An entry is accepted by utility: it must shorten the total description of the store's accepted solutions, or reduce work on held-out problems under ablation.

**Choosing experiments.** Both earlier plans left this as a line item. Three rules cover what the store can decide for itself:

1. *Refute before promoting.* Before a class moves from observed to tested, evaluate its members on fresh rows that include boundary values.
2. *Split ambiguities.* When two candidate programs fit, search for a row on which they differ. If the target is a function the kernel can run, run it. If not, report the task as underdetermined.
3. *Isolate.* To test whether a column depends on an input, build rows that vary that input and hold the others. This is "holding all but a few constant", and it is the shared-input experiment under which plan 2 found commutativity appears at once.

**Limits.** A self-generated curriculum has no convincing precedent: every measured bootstrap needed a graded external task set **[L]**. The best-known attempt at open-ended discovery, AM, is a caution of a different kind: its authors traced its success to "the density of worthwhile math concepts as represented in Lisp" and its limit to an "inability to discover new, powerful, domain-specific heuristics". The bet here is narrower. Questions are generated mechanically from entries and kept only on measured utility. Functions still come from external data. What the kernel should stop needing is the operator whitelist, the recursion schema, the trace-shaped rows, and the hand-written entry: the four things that account for most of the library today (§2.5).

**Learning from crashes and timeouts.** A guard for errors is the same problem as a guard for a law: a Boolean target fitted by a small term, with a published five-step recipe behind it **[L]**. Timeouts are harder. An out-of-fuel cell cannot distinguish slow from divergent, and the review found no system that learns termination guards from timeouts. The cheap version is to treat out-of-fuel as a third outcome, re-test with doubled fuel, and learn a guard only for cells that stay out of fuel **[P]**.

### 7.6 What an hour buys

Within a space no operation needs graph matching, and none saturates. Across spaces nearly every operation is a search for a witness (§5.9).

| Operation | Cost |
|:--|:--|
| Intern a term | constant, by hash |
| Evaluate one operator over a space of n rows | n |
| Find a column's class | n, by hash |
| Dependency test (is this column a function of those?) | n, by hash |
| Learn one operator's verb table for one quotient | one group-by over its probe rows |
| Test a candidate against the target's labels before evaluating it | about 7 look-ups per candidate that survives, in the reproduction (§8.8) |
| Unnest, re-index, collect | number of cells touched |
| Anti-unify k plain terms | their total size. Over classes, quadratic in the corpus in the one published system |
| Conditional laws under g candidate guards over c classes | g × c × n, with guards limited to about four nodes in published systems |
| Enumerate by class to size s | exponential in s: ×3–7 per unit of size after dedupe, against ×9–14 for raw syntax (§8.4) |
| Compare laws up to renaming of variables | brute force over at most 5 variables |
| Across spaces: find a row correspondence by a key term | one hash join per candidate term |
| Across spaces: find one by colour refinement | polynomial; a group-by per round |
| Across spaces: find one by backtracking | exponential in the worst case; needed for regular structures without symmetry, and to reject look-alikes (§8.7) |
| Across spaces: match a tree-shaped pattern | a sequence of joins |
| Across spaces: match a pattern with cycles, or modulo associativity and commutativity | NP-complete |

Within a space the only exponential is leaf enumeration, and its exponent is the reason for everything else in this section. Across spaces the exponential is the search for witnesses, and it is controlled by choosing what to try (§5.9). With behaviour dedupe each tenfold of work buys one to two nodes (§2.3, §8.4). Deep single searches also meet memory before time: extrapolating from 90-second runs, the prototype would exhaust 24 GB within one to eight minutes of one deep search, and ten hours would reach one or two nodes further than one hour (§8.4).

So an hour should not be one deep search. It should be:

- **breadth**: thousands of small bounded problems from the agenda of §7.5, each milliseconds to seconds;
- **re-validation**: fresh rows for every class that something depends on;
- **ablation**: re-running held-out problems to decide what stays.

A problem's bank of classes is scratch memory, bounded by its account. The persistent store holds the library, the banks of a few standard probe spaces, the derivation rows, and the counts.

Hours then compound in the way the audit measured they can: three of eight held-out tasks became solvable, in under 50,000 work, once the library was used for lifting, though three or four others became dearer (§2.5).

## 8. A prototype of the store, measured

To test §5 by measurement rather than by argument, one auditor built a standalone prototype: `tg-probe.lisp`, 874 lines of Common Lisp, using no kernel code. Its core store is 206 lines and its change-of-space routines are 22. It is a measuring instrument, not a design. Source, driver, and logs are in `plan_v2c_audit/proto/`; every number below is copied from a log there **[M]**.

Two cautions before the numbers. A *candidate* here is one operator applied down one column; it is not the kernel's work unit, and the two cannot be compared directly. And the examples are the prototype's own random rows (12 per task, sequences of length 0–7), not the kernel's `:spec` rows.

### 8.1 Lift by change of space

One procedure and one 12-operator grammar (`+ - * mod max min at = < and not call`) for every task, plus a four-operator grammar over lengths for the shape. Shape first, then the element on the position space, with a split by guard if no single term fits, and the input-position lift for selective functions. The procedure grants the container forms: `tabulate` with the previous output available as a column, selection and `where` over input positions (the keep-column recovered by subsequence alignment), a single-guard `if`, and `fold`. What is searched for is the term inside. Held-out means 200 fresh examples with sequences up to length 12.

| Task | Candidates | Time | Held-out | Element term found |
|:--|--:|--:|:--|:--|
| reverse | 86,434 | 56 ms | 200/200 | `(at xs (- (len xs) (+ i 1)))` |
| shift-seq (the kernel spec's semantics) | 9,175 | 4 ms | 200/200 | `(if (< i (- (len xs) k)) (at xs (+ i k)) 0)` |
| rotate-left by k | 217,920 | 108 ms | 200/200 | `(at xs (mod (+ i k) (len xs)))` |
| map-adjacent with `+` | 291,481 | 244 ms | 200/200 | `(+ (at xs i) (at xs (+ i 1)))` |
| map-adjacent with `−` | 703,183 | 436 ms | 200/200 | `(- (at xs (+ i 1)) (at xs i))` |
| running sum | 4,771 | 4 ms | 200/200 | `(if (< 0 i) (+ prev (at xs i)) (at xs i))` |
| scan with `+` and an initial value | 9,369 | 8 ms | 200/200 | as above, with `(+ a (at xs i))` at position 0 |
| scan with step 2·acc − x | 304,540 | 204 ms | 200/200 | `(if (< 0 i) (+ prev (- prev (at xs i))) …)` |
| positions (the kernel spec's semantics: the index list k, k+1, …) | 3 | <4 ms | 200/200 | `(+ i k)` |
| positions of a value | 8,332 | <4 ms | 200/200 | `(where xs … (= x v))` |
| filter x > k | 7,002 | <4 ms | 200/200 | `(select xs … (< k x))` |
| take k | 267 | <4 ms | 200/200 | shape `(min (len xs) k)` |
| zip-add | 30,265 | 20 ms | 200/200 | shape `(min (len xs) (len zs))` |
| map-adjacent with a function argument `f` | 8,458,580 | 5.0 s | 200/200 | `(call f (at xs (+ i 1)) (at xs i))` |
| scan with a function argument `f` | 14,186 | 16 ms | 200/200 | `(if (< 0 i) (call f prev (at xs i)) (call f a (at xs i)))` |

Over nine example sets, 134 of 135 runs score 200/200.

These include the prototype's versions of three of the four functions the existing kernel does not find without a hand-written schema at a thousand times its budget (§2.3): `map-adjacent`, `scan`, and `shift-seq`. The fourth, `best-shift`, was not attempted. Nor were `seq-corr`, `argmax-corr`, or `foldl` with a function argument. The comparison that matters is not speed. It is that here the terms come from input/output rows, with one grammar and one procedure, with no skeleton written per function, and that none needed recursion. For `filter` and for positions of a value, what was found is the predicate; the selecting form was granted.

**What did not work, or needed more than the hypothesis.**

- **Nested guard splits overfit.** Allowed at every size, they return case analyses whose guards fit the training rows by accident: rotate-left on 3 of 9 example sets, map-adjacent with `f` on 6 of 9. The prototype therefore accepts a single guard at first fit and tries nested splits only when the budget is spent. On these example sets, requiring a split to be size-minimal changed no outcome and cost 35–1,100× more candidates. On the kernel's own, much shorter spec rows it does change the outcome (§8.6). A split needs an acceptance test stronger than "fits the rows"; §8.5 says what the design takes from this.
- **A function argument is only as determined as its examples.** The one miss in 135 is an example set in which the only non-commutative operator appears on one-element sequences, so nothing fixes the argument order. This is the kernel's `foldl` impostor again, and the store's check for it is the one in §5.5.
- **Folds to a scalar fail under lifting as the prototype built it**: `sum`, alternating sum, and a Horner evaluation. With a `fold` form whose step is enumerated by class, they are found after 21, 51, and 157 fold programs; alternating sum needs a right fold. §8.6 shows that `sum` fails here only because the prototype's collect could build lists and nothing else.
- **A larger grammar can exhaust the budget.** With three more operators and a 12-million-candidate cap, map-adjacent with `f` returned an impostor from the last-resort nested split. The other fourteen tasks solved in at most 1.8 million.

The prototype's author lists every mechanism added beyond the stated hypothesis (proto report, §7). The ones that matter for the design: iterative deepening by size with a split attempt at each level; routing to the input-position lift when no shape term exists; the subsequence alignment behind selection; a lazy `if`; a cell type for function-valued inputs; and the `fold` form.

### 8.2 Inverses and guards from an operator's own table

For each operator and argument: test on a grid whether that argument is a function of the other argument and the result; if so search for the term; if only on some rows, search for a guard.

| Operator, argument | Dependency holds on | Guard found | Inverse found | Candidates |
|:--|--:|:--|:--|--:|
| `+`, either | 100% | — | `(- c b)` | 25 |
| `−`, first | 100% | — | `(+ b c)` | 6 |
| `−`, second | 100% | — | `(- a c)` | 22 |
| `neg` | 100% | — | `(neg c)` | 1 |
| `*`, either | 92.3% | `(not (= b 0))` | `(div c b)` | 141,652 (about 0.25 s) |
| `div`, dividend | 16.7% | `(= b (div 1 b))`, that is b = ±1 | `(* b c)` | 2,516 |
| `max`, either | 46.2% | `(< b c)` | `c` | 137 |
| `mod`; `div`, divisor | 23–24% | none | none | budget |

The count for `*` includes a further search for a section, a term that returns some preimage on every row; the guard itself has 4 nodes and the inverse 3.

For `+`, `−`, and `*` these are the witnesses the kernel reaches by two other routes: its milestone code, on a full grid with a supplied witness language, and its bootstrap, from hand-written spec rows. Here they come from the operator's table and the grammar already in scope.

The prototype does not match the milestone code everywhere. It finds no solver for an unknown divisor, where the milestone code finds one with its guard. For `*` on the integers it finds `b ≠ 0` only, where the milestone code also finds a divisibility condition: every row of a product table is divisible, so the table alone cannot show it. For an unknown dividend it finds the guard b = ±1, which is the integer answer; the milestone code's `k ≠ 0` is the answer over a field.

One caveat was found the hard way: **a finite grid creates false dependencies at its boundary.** Without widening the range of the argument being solved for, `max` and `div` find no guard. Experiments that test a dependency must be designed with that in mind (§7.5, rule 3).

**Feeding the inverses back made search cheaper.** With the inverses of `+` and `−` used to turn "find y" into "find y − k for some class k already present", map-adjacent fell from 291,481 and 703,183 candidates to about 4,800, and zip-add from 30,265 to 350. That is a small, measured instance of the compounding the plan is after: something the store found made a later search 60–150× cheaper.

### 8.3 Laws from collisions

Grammar `{+ * neg}` over x, y, z, 0, 1.

- Through size 7: 3,282 collisions, 105 laws kept after pruning, 0.01 s. Commutativity, both identities, x·0, and double negation are derivable from the kept set at size 3; associativity at size 5; distributivity at size 7.
- **Soundness.** Tested on 1,000 fresh rows with values up to ±1000: no kept law is false when the probe space has 8 or more rows. With 6 rows one is false; with 4 rows, 23; with 3 rows, 199.
- **The kept set does not converge.** It grows about ×2.8 per unit of size: 8,889 laws at size 12, and pruning then costs more than enumeration. A post-pass takes the 105 down to 59.

The last point is risk 5 of §10 in miniature. It matches the published experience that deeper law search "does not lead to many useful lemmas".

### 8.4 Growth, throughput, and memory

32 rows; leaves x, y, z, 0, 1, 2. About 2 million candidates per second, 60–65 million cells per second, and 452 bytes per stored class.

| | `{+ − * neg}` | plus `div mod max min` | plus Booleans and `if` |
|:--|:--|:--|:--|
| Growth per unit of size: raw syntax | ×9.3 | ×13.6 | ×13.7 |
| Growth per unit of size: classes | ×3.0 | ×7.2 | ×7.0 |
| Largest size fully enumerated in the run | 14 (25 s) | 9 (10 s) | 9 (13 s) |
| Size reachable in 1 min / 1 h / 10 h, by time alone, with dedupe | 14 / 18 / 20 | 10 / 12 / 13 | 9 / 12 / 13 |
| Same, without dedupe | 10 / 11 / 12 | 8 / 10 / 11 | 8 / 10 / 11 |
| Size at which 24 GB is exhausted (extrapolated) | 16, after about 4 min | 11, after about 8 min | 10, after about 1 min |

Only the first three rows are measured, in runs of about 90 seconds per grammar; for the two richer grammars the last size was counted by hash only. The remaining rows are extrapolations, under assumptions the prototype's author calls optimistic, from growth ratios that were still rising.

Three things follow.

- **Memory is the wall, not time.** By that extrapolation, the sizes an hour could reach by time alone would need about 0.2 TB, and ten hours 1.2–2.4 TB. Two of the prototype's own runs did die at a 10 GB heap. On that operator set with two variables, at sizes 7 to 13 and in Python, storing classes by their residues modulo small primes cut stored classes 8.5 to 26 times in a separate experiment (§8.8).
- **Dedupe is worth less on rich arithmetic than on polynomials or on the kernel's list grammars.** Once `div`, `mod`, `max`, and `min` are in, 30–40% of candidates are genuinely new behaviours on 32 random rows. The 99% duplicate rate of §2.3 was on few rows and list-heavy grammars. Both are real; the gain depends on the grammar and the rows.
- **Ten hours buys one or two more nodes than one hour.** This is the same logarithm as §2.3, on a different engine.

The kernel's measured candidate rate is 118–248 thousand per second (empirical report, §2), so the prototype evaluates 8–17 times as many candidates per second, on four to five times as many rows. The prototype does no metering and no bit accounting, so read that as an upper bound on what evaluation by column could give, not as a prediction.

### 8.5 What the prototype changes in the plan

1. **The lift claim stands, for position-wise, selective, and observed-recurrence functions.** §8.6 now covers the kernel's own short spec rows. Tasks that need two lifts remain untested.
2. **A split is accepted in size order, never ahead of a smaller unsplit term** (§8.6). Beyond that the store offers three further tests, in increasing cost: the guard must pay for itself in description length; the two branches must not fall into one class on a wider probe space; and a nested split must survive rows held back from the search. This is added to X3's gate.
3. **Collect takes an aggregate, and `fold` belongs in the refinement table as well** (§7.2, §8.6). The first covers reductions of an element-wise term. The second, with its step enumerated by class, covers sequential state.
4. **Laws are kept by use, not by completeness.** Classes do the pruning. A law earns a place in the library only when something reads it: to normalize before anti-unification, to carry a class to a new space, or to certify. The small-size basis, about 59 laws here, is kept; anything larger is derived on demand.
5. **Hours go to breadth.** By extrapolation, the memory wall is reached in minutes on any one deep search. §7.6 already says this; the prototype's runs are consistent with it.
6. **Dependency experiments need designed rows.** The boundary artifact is a concrete instance of why experiment choice has to be a mechanism.

### 8.6 The outside review's re-runs, reproduced

The outside review (`plan_v2c_audit.md`) ran a modified prototype on the kernel's actual `:spec` rows, which §8.1 had not done. Its own summary of §8 is fair and belongs here first: the prototype validates the store, not the general synthesizer. The prototype's control is a fixed, one-level procedure. Requirements with holes, refinement in more than one step, the instance space, and the derivation space are not built. Its modified code is not in the repository. One auditor therefore rebuilt the modifications, 23 lines in six marked places, and re-ran every claim. The held-out references are transliterations of the library's own definitions, confirmed against the kernel's VM on every held-out input **[M]**.

| Kernel spec | The review's claim | Reproduced | Note |
|:--|:--|:--|:--|
| `copy`, `inc-all`, `dbl-all`, `positions` | exact `tabulate`, 200/200 | yes | 151, 408, 8,607, and 3 candidates |
| `scan` with a function argument; `shift-seq` | exact with one guard, 200/200 | yes, one count differs | 11,604 candidates for `scan` (the review says 11,298) and 8,781 for `shift-seq`. `shift-seq` falls to 174/200 if held-out shifts may be negative; the spec's rows never are |
| `filter` | needs a one-argument Boolean call added; then 200/200 at 1,383 candidates | yes | without the addition, no answer after 1.58 million candidates |
| `sum-all`, `len-all`, `prd-all`, `last-or` | 200/200 through `fold`; the unlifted path overfits | partly | all four are 200/200 through `fold`. The unlifted path overfits two of them (23/200 and 20/200), not four |
| `map-adjacent`, on its 8 examples and 6 lifted rows | default policy returns a guard-split impostor, 29/200; with size-minimal split acceptance, the exact answer, 200/200, in 616,232 candidates and 64 ms | yes, with the impostor's size corrected | the impostor has 27 nodes, not 19 |
| `foldl` | returns `(fold a (- acc x) xs)`, 81/200 | yes | the spec supplies only `f = −`. With the function argument offered as a leaf, `(- acc x)` still wins on size and the right program is the next fit |
| `seq-corr` | unsolved; solved once collect can take an aggregate | yes | the sum, over positions below the shorter length, of `(* (at xs i) (at ys i))`; 200/200; 20,713 candidates and 8 ms with the shape given, 3.05 million and 0.7 s with it searched |
| `best-shift`, `argmax-corr` | unsolved | yes | the prototype returns impostors scoring at most 43/200, rather than no answer |

Three results change the plan.

**Split acceptance has to respect size order.** §8.1 reported that requiring a split to be size-minimal "changed no outcome" and cost far more. That was true on the prototype's own example sets of 31–51 lifted rows. On the kernel's own six lifted rows for `map-adjacent`, first-fit acceptance returns an impostor and size-minimal acceptance returns the right program. With size-minimal acceptance all eight sequence specs score 200/200, at 625× and 824× the candidates on the two that need a guard. The review's rule is the right one: a guard split must never be accepted ahead of a smaller unsplit term. The cost is real and is the price of few rows.

**Collect can take an aggregate.** The prototype's collect gathered child cells only into a list. Letting it sum them, or take their product, maximum, minimum, or count, is nine lines for the operator and 44–71 with the search around it. It solves `seq-corr`, `sum-all`, `len-all`, and `prd-all`. It does not replace `fold`. It returned nothing on `last-or`, an alternating sum, and a Horner evaluation, for three different reasons. `last-or` is an associative aggregate whose identity is an input, which none of the five fixed aggregates has. The alternating sum is a sum of an element term of about 17 nodes, beyond the size-9 search: a limit of budget, not of the mechanism. Horner needs a weight that no element term in the grammar computes; that one is sequential state. So the line §7.3 drew moves. Reductions of an element-wise term are a change of space. What stays outside is sequential state with a step that is not associative, when the intermediate values are not observed. With the shape searched rather than given, the aggregate path also returns impostors on `foldl` and `argmax-corr`.

**The `foldl` spec is underdetermined, and the prototype cannot tell.** This is the check of §5.5, still unbuilt.

The review also made claims about the kernel's prices, which bear on §6.

| The review's claim | Reproduced | What was found |
|:--|:--|:--|
| Integer distance is symmetric and logarithmic: 0, 4, 5, 5, 8, …, 17 bits at differences 0, 1, 2, 3, 4, …, 1000 | yes | exact, and symmetric for every difference to 10⁶ |
| Sequences and code are asymmetric: 13 bits from `()` to `(1 2)` and 1 bit back; 15 bits from `x0` to `x0 + 1` and 3 back | yes | the second pair needs a two-input scope |
| No violations of the triangle inequality | partly | none on integers, fields, or tuples, nor on sequence and code grids with small values. With large values they appear: 0, 2, and 3 in three random sequence grids of 3.4 million triples each, and 49 of 300,763 in a grid built to show them. From `(−100 −100)` to `(−100 0 0)` costs 21 bits directly and 6 + 9 through `(−100)`. On code, 10 in 11.7 million |
| Kraft sums above 1, because an exact cell costs 0 bits: 1.5 for Booleans, 1.1875 for GF(5), 1.4059 for integers | yes | the sums are exact as stated |
| That violation is "live" | partly | Stage A does not price cell by cell: it charges exception rows with their indices and a count. What goes unpaid there is one bit per model. The dense, row-by-row sum occurs in `induce-row-order` (`proposals.lisp:728-739`), which only tests call. A second, independent defect is at `frame.lisp:1572`: the minimum of two codes is taken without paying to say which |
| The guard for inverting `c = a·b`, built from the table's uniqueness test and a forward replay of the witness, is exact on all 1,681 pairs in [−20, 20]² | yes | for floor and for truncating division |
| For `a div b = c` solved for `b`, the guard `|a| < c(c+1)` gives uniqueness | partly | it is sound, but rejects 48 to 78 pairs that have exactly one answer |
| `anti-unify` gives `(+ x x)` and `(+ y y)` one shared hole | yes | `(+ ?0 ?0)`; and two holes for `(+ x y)`, `(+ y x)` |

### 8.7 Search across spaces, measured

Three measurements were made for this revision, on the unmodified prototype, to put numbers under §5.9 and §6.6 **[M]**. Source and logs are in `plan_v2c_audit/cross-space/`.

**Do store-generated signatures prioritize mixing between tasks?** Thirty sequence tasks, each program form represented at least three times. For each task the prototype's own enumerator generated every Boolean term up to a small size over generic leaves (lengths, sums, minima and maxima of inputs and output, the output's first and last elements, integer inputs, 0 and 1). A task's signature is the set of those properties that are never false on its examples and true on at least half. The leaves were chosen once, by hand; nothing was written per task. Four further tasks were tried and dropped because the full grammar returned impostors on them. Then, leaving each task out in turn, the other tasks were ranked by overlap of signatures. Figures are means over five independent example sets.

| Signature | Nearest neighbour has the same program form | A grammar restricted to the 3 nearest neighbours' operators solves the task |
|:--|--:|--:|
| 446 properties (comparisons only) | 0.48 | 0.67 |
| 7,465 properties (with `+` and `−`) | 0.54 | 0.66 |
| types only | 0.32 | 0.49 |
| chance, or 3 random tasks | 0.15 | 0.58 |
| control: the 4 commonest operators in the rest of the pool, ignoring the task | — | 0.69 |

Computing every signature cost 648 candidates for the smaller pool, against 10.1 million to solve the thirty tasks with the full grammar. So the signal is nearly free, and for *form* it is real: three times chance and half again above types.

For *operators* it is not. The restricted grammar is right two times in three, which is no better than a control that never looks at the task. And the search cost is in the operators:

| Restriction | Fair cost, as a fraction of the full grammar (geometric mean per task) | Same, with the restricted attempt cut off at 100,000 candidates |
|:--|--:|--:|
| 3 nearest by signature | 0.77–0.83 | 0.68–0.72 |
| control (commonest operators) | 0.73 | 0.60 |
| 3 random tasks | 1.86 | 1.35 |
| oracle: the task's own operators | 0.085 | 0.085 |

"Fair cost" is the restricted attempt, plus the full grammar whenever the attempt fails. Without a cut-off, summed over tasks, the signature restriction saves nothing (0.95–1.09 of the full cost): a miss costs a whole failed enumeration and then the full run. The oracle shows what a correct choice would be worth: a factor of 12 per task.

Three further findings:

- *Restricted grammars return wrong programs.* 2.7% of signature-restricted attempts, and 6% of the control's, return a program that fits the twelve examples and fails held-out.
- *Form is not what needed predicting.* The prototype's second route (selection, `where`, `fold`) fails at once when it does not apply, so trying it first costs nothing and matches an oracle.
- *The properties cannot see between positions.* The generic leaves reach a sequence only through its length and three aggregates, and the output also through its ends. Two of the five recurrences show only the single property "output as long as input", which five tasks that are not recurrences show as well. Parity is not expressible, so `mod` is among the operators most often missing. A function-valued input is not a leaf at all.

So the first measurement of risk 11 and risk 12 (§10) is in, and it is mostly negative: a flat signature computed at the boundary of a task tells the kind of program and not its content. §6.6 says what this changes.

**Is an analogy between two operators cheap to verify?** For unary maps f drawn from a small bank of terms, and pairs of binary operators p and q, the test is whether `f(p(a, b)) = q(f(a), f(b))` on every row of a grid. All 350 combinations were tested in 1.3 ms. Twenty-nine non-trivial ones hold, and none is false on 1,000 fresh rows. Seventeen carry an operator to itself, and the twelve that relate two different operators are all between `max` and `min`: negation carries `max` to `min` and back; doubling and negation carry `+` to `+`; shifts by a constant carry `max` to `max`. Against `append` on sequences, `len` and `sum` go to `+`, and `max` and `min` go to themselves. 96% of the combinations that fail are rejected by the first row read. A pre-filter that compares the operators' algebraic flags skipped a third of the failures, was unsound with a richer bank of maps, and what it saves is the reading of about one row. This is §5.9's first case: when the map is a small term, crossing between two tables costs almost nothing, and checking is the cheap part.

**How far does colour refinement go when no key identifies rows?** A directed graph was stored as a node space and an edge space with two maps, its rows were shuffled, and the node correspondence was recovered with group-by and re-index only.

| Structure | Rows | Matched by refinement alone | Choices | Backtracks | Time |
|:--|--:|--:|--:|--:|--:|
| sparse random graph, 3 out-edges | 10,000 | 9,977 | 22 | 0 | 0.16 s |
| random tree | 10,000 | 6,547 | 1,586 | 0 | 5.4 s |
| 30 × 30 grid | 900 | 0 | 2 | 0 | 57 ms |
| one cycle | 200 | 0 | 1 | 0 | 4.6 ms |
| two cycles against one cycle (must be rejected) | 200 | 0 | 200 | 200 | 0.35 s |
| random 3-regular graph | 3,000 | 0 | 1,836 | 1,835 | 4.6 s |
| 5 hexagons against 4 hexagons and 2 triangles (must be rejected) | 30 | 0 | 257,214 | 257,214 | 3.6 s |

Irregular structure is matched by refinement, plus choices that never have to be undone; so is a symmetric structure matched against its own copy. A regular structure with no symmetry needs backtracking in proportion to its size. And a pair that is *not* isomorphic but has interchangeable parts costs a factorial to reject, at thirty rows. This simple engine has none of the symmetry pruning that mature graph-matching tools add. So it is adequate where data is irregular, which is the usual case for tables of values; and every attempt needs a budget, because the bad cases are bad immediately.

### 8.8 Words and verb tables: the outside review's second section, reproduced

The second section of the outside review proposes the mechanism that §6.6 now adopts, and supports it with five experiments in Python. Their code is not in the repository. One auditor rebuilt four of them from the review's prose and the fifth, on reuse, only in outline, in standard-library Python with fixed seeds **[M]**. Source and logs are in `plan_v2c_audit/verify-quotients/`. None of this runs on the store prototype or on the kernel's library: the operators are a library written by hand for the experiment.

**Verb tables on a library of 61 operators.** The library has 31 list-to-list operators (`sort`, `reverse`, `filter_pos`, `running_sum`, `map_adj_sub`, and the like), 6 that combine two lists, 9 reductions, 11 on integers, and 4 that take an integer and a list. A task is 8 rows of a hidden composition of a few of them. The baseline is bottom-up search by size with behaviour dedupe. Six quotients were listed by hand: the signs present in a list, the parities present, whether it is sorted in either direction, its length capped at 5, its length modulo 2, and whether it is empty; with the matching quotients on integers. Each operator was run on 2,000 probe values and grouped, once, into a table from input labels to the output labels seen. A candidate is skipped, before it is evaluated, when its tables say it cannot give the target's labels within the size that remains. The target's size is not known, so the bound is deepened step by step and every pass is counted.

| Method | Candidates evaluated: gain over the baseline (geometric mean; two task sets of 20) |
|:--|--:|
| verb tables, six quotients | 17.5×, 18.5× |
| the same, on tasks that need an operator held out of all training | 21.4×, 14.2× |
| the same, on the other tasks | 15.3×, 25.5× |
| verb tables used only to order the operators; nothing skipped | 6.1×, 5.7× |
| Naive Bayes over 23 hand-written properties, trained on 80 solved tasks, used to order | 2.6×, 2.5× |
| verb tables, discarding only after evaluation | 1.5×, 1.5× |

The baseline is averaged over random orders of the operator list. In the first three rows the method is too; rows four and five are themselves orders; the last row uses the listing order on both sides. Rows two and three are means over the 8 and 11, and the 12 and 9, tasks of each kind. The order matters: with the library in its listing order the first row is 13.9× and 16.7×, and the tasks with a held-out operator fall to 11.2× and 11.7×.

On 60 tasks, varying one thing at a time:

| Variation | Gain in candidates | Answers lost, of 60 |
|:--|--:|--:|
| types only | 1.7× | 0 |
| one quotient | 2.8× to 6.4× | 0 |
| three quotients | 6.1× to 12.6× | 0 |
| all six | 15.7× | 0 |
| all six, labels read on 1 row of the 8 | 5.9× | 0 |
| all six, 200 probes per operator | 15.9× | 2 |
| sign, parity, and order merged into one quotient of 38 labels | 23.9× | 8 |
| six quotients chosen automatically by dependency score, with a rule against redundancy | 10.7×, where the hand list scored 15.8× in the same run | 0 |

Four findings qualify the headline.

- *Answers are lost.* The review reports none. On 300 random tasks:

| Tables | Probes per operator | Answers lost, of 300 |
|:--|--:|--:|
| six separate quotients | 100 | 34 |
| | 300 | 4 |
| | 1,000 | 1 |
| | 3,000 | 1 |
| | 10,000 | 0 |
| sign, parity, and order merged | 3,000 | 24 |
| | 30,000 | 4 |
| | 300,000 | 0 |

Of 115 losses across all 25 configurations tried, 113 coincide with one defect on the reference program's path: an input-label combination that the probes did see, with an output label they did not. `take3` of a non-increasing list whose first three elements are equal is constant, hence sorted both ways; that never occurred in 3,000 probes. The review's default, that an input never seen may give anything, covers only unseen inputs. With probes chosen to include edge cases, no answer was lost from 1,000 probes up.

- *The gain does not grow with the size of the program.* On single-input chains found at sizes 3, 4, 5, and 6 it was 14.4×, 11.1×, 11.6×, and 15.6×.
- *Time gains are smaller.* Summed over the 20 tasks, the baseline made 2.60 million evaluations; the filtered search made 0.17 million evaluations and 1.25 million table look-ups. Wall time improved by 1.3×, 2.0×, and 4.2× at sizes 4, 5, and 6.
- *Ranking by surprise adds 3–5%.* The review counts it as a second mechanism. Within the last level it moved the answer forward on some tasks and far back on others.
- *Planning further ahead adds little.* By the auditor's observation, which no log tabulates, the bound on the steps that remain rarely exceeds one or two: a two-argument operator with a free second argument connects nearly any label to any other. Discarding a class only after evaluating it gives 1.5×.
- *Memory gains are smaller than candidate gains.* Stored classes fell 2.3× to 2.8×, or 7× to 9× with a one-step look-ahead the auditor added.

Learning the tables took 180 ms (the review: 161 ms). Used as prices in the manner of the published grammar-reweighting method, rather than as an order, Naive Bayes was far worse than the review says: 5 of the 8 tasks with a held-out operator passed a cap of three million candidates. The review's own figure for it, 6.5× worse than plain on one task, reproduced as 7.6× worse with one task set and slightly better than plain with the other; in the rebuild, the baseline's listing order happens to put the needed operator second, and the review's own order is not known.

**Choosing quotients by the dependency score.** Every small term into 2–6 labels was enumerated and deduplicated by the partition it induces. Each was scored, per operator, by the share of the output label's uncertainty that the input labels remove.

| Quotient | Score over `+ − * neg` | over those and `max min` | over those and `div mod` | The review |
|:--|--:|--:|--:|:--|
| `(mod x 5)` | 1.000 | 0.888 | 0.714 | 0.888 |
| `(mod x 4)` | 1.000 | 0.876 | 0.717 | 0.876 |
| `(mod x 3)` | 1.000 | 0.861 | 0.696 | 0.860 |
| `(mod x 2)` | 1.000 | 0.833 | 0.699 | 0.833 |
| `(sgn x)` | 0.747 | 0.832 | 0.772, rank 1 of 1,109 | 0.830; 0.772 |
| `(= x 1)` | 0.117 | 0.302 | 0.243, rank 702 | 0.30–0.48 |

The review's figures reproduce to within 0.002 once its "ring" score is read as the mean over six operators. On sequences, over 15 operators and 5,475 candidates, the capped length `(min (len xs) 5)` ranks first at 0.877 (the review: 0.857). Its other named sequence quotients differ from the review's values by about 0.1 and rank 48th to 311th. Ranked by score alone, all of the top fifteen are variants of the length; a distractor the auditor added, "the maximum is below 3", outranks "all even". And if a quotient whose output label is constant is scored as perfectly predictable rather than as worthless, vacuous predicates take all of the top fifteen places.

**The weakest guard for a conditional law.** With 32 rows, every Boolean term is a 32-bit mask. A guard is valid for a law when it is true only on rows where the law holds, and one guard implies another when its mask is contained in the other's. Among 1,936 guard terms with 302 distinct masks:

| Law | Rows where it holds | Valid guards | Weakest |
|:--|--:|--:|:--|
| `max(a, b) = a` | 20 of 32 | 49 | `(<= b a)` |
| `div(a*b, b) = a` | 31 | 151 | `(!= b 0)` |
| `abs(a + b) = abs(a) + abs(b)` | 16 | 47 | `(<= 0 (* a b))` |
| `max(a, 0) = a` | 23 | 60 | `(<= 0 a)` |
| `div(a, b) * b = a` | 17 | 22 | seven incomparable guards |
| `mod(a, b) = a` | 11 | 10 | three incomparable guards |

All six took 0.48 ms. The first three are the review's, and match it term for term. The other three were added, and the last two show the limit: one weakest guard exists exactly when some guard in the pool is true on precisely the rows where the law holds.

**Arithmetic modulo small primes, by column.** On the grammar `+ − * neg`, reduction modulo a prime commutes with every operator, so a class's column of residues can be computed from its children's. Classes are stored by their residues on a few rows (modulo 2 on 12 rows, modulo 3 on 4, modulo 5 on 3), and a pair is evaluated in full only if its residues can still reach the target's.

| Target | Size | Stored classes, plain | Stored, with residues | Wall time, excluding a one-off 65–143 ms to build the tables |
|:--|--:|--:|--:|:--|
| `(x+x)*(y+1)` | 7 | 127 | 8 | slower |
| `(x+y)*(x−y) + 1` | 9 | 595 | 62 | slower |
| `(x+y)^2 − x*y + 1` | 11 | 3,147 | 119 | 1.1× faster |
| `2*(x^2 + y^2) − x*y` | 13 | 17,609 | 1,229 | 1.4× faster |

Stored classes fell 8.5× to 26× across six targets (the review: 8× to 23×), and 200 of 200 random polynomial targets were found at the size plain search finds them. With `div` and `mod` added the residues no longer commute, and 117 of 120 random targets that need `div` or `mod` were lost, as the review itself warns. Applied to single rows the same primes give 1.2× to 1.7×.

**Reuse across tasks.** In streams of 20 tasks, each with 5 repeats of earlier tasks on fresh inputs and 6 near relatives, the review reports 11 reuse hits and 2.2× fewer candidates from indexing past problems by labels that hold on every row, and trying one-operator variants within a family of similar operators. This experiment was rebuilt in outline only. With an index and such variants, hits were 4 to 6 per stream. Counts of 7 to 11 were reached only with no index, by replaying every earlier solution and then its variants. The saving is 1.2× to 1.3×; the review's 2.2× is what 11 free tasks of 20 would give if all tasks cost the same. Replaying every earlier solution on the new rows, with no index, found all 25 repeats in five streams, at no more than 57 candidates per task: three per stored solution, with at most 19 stored. The rebuilt index was keyed on 23 hand-written properties that hold on every row, and found 19, because a property that holds on every row of one input set need not hold on the next. A check with the key changed to the labels of the six quotients found 9 with input and output labels and 14 with output labels alone. The operator families themselves do come out of the tables: of the 32 operators placed by hand in seven families, 22 have a family member as their nearest table among operators of their type, where chance gives 9.

**How far the review's numbers can be trusted.** Its figures for the dependency scores and for the residue experiment match the rebuilt ones closely enough that those experiments were clearly run. Its table for the 61-operator library is not consistent with itself: one row lists 85 candidates evaluated and 812 classes stored, and storing a class takes at least one evaluation. Its direction, range, and ordering of tasks reproduce (rank correlation 0.69 over its eight tasks). Its zero misses holds on its own eight tasks and fails as a property of the method. It gives no separate figure for ranking, which added 3–5% here. Its 2.2× for reuse does not reproduce.

**What this changes.** §6.6 is rewritten around quotients and verb tables. X4 becomes the test of them on the kernel's own library (§11.2). Verb tables are graded as tested knowledge, never certified (§5.5). The reader added to the derivation space is replay, and not yet an index (§7.4).

## 9. What to import, and what to leave

You lean toward a rewrite that imports the working components. The audit supports that, with one qualification about how much imports unchanged.

About 3,500 lines are worth carrying over. Roughly 2,200 of them come across as code or as a design. Roughly 1,300 work through a frame today, and need that interface moved to spaces and requirements before they can be used. About 750 more are worth re-implementing from their idea and their tests. The kernel proper is 17,647 lines. Line counts are the auditors', from the root tree; where two auditors counted the same code differently, both figures are given.

**Carry over**

"As code" means the file can be lifted nearly unchanged. "As design" means the mechanism is kept and the code re-derived for the new opcode set. "Re-seat" means it is sound and tested but takes or returns frames today.

| Component | Where | Lines | How | Why |
|:--|:--|--:|:--|:--|
| Ledger and work limit | `vm.lisp:10-54` | 45 | as code | exact accounting; depends on nothing |
| Evidence grades | `evidence.lisp` | 73 | as code | a certificate lapses automatically when anything it depends on changes |
| Matching and anti-unification | `unify.lisp:5-73` | 70 | as code | n-ary, typed, shared holes, operator holes |
| Persistence | `persistence.lisp` | 141 | as code | fixed-point save and load; specs replayed and certificates recomputed on load |
| Finite-field certification, with counterexamples | `laws.lisp` | 228 | as code | the one working proof rule |
| Description-length-gated abstraction | `abstraction.lisp` | 580 | as code | it is what finds `:map` |
| Size-ordered enumerator | `enumerate.lisp:59-214` | ~150 | as code | to be joined with v2's behaviour table, which works when switched on |
| Metered, resumable evaluator | `vm.lisp:56-400` | 345 | as design | prepaid instructions, exact resume, four statuses. The per-opcode dispatch is re-derived, and §7.1 changes its unit of evaluation |
| Prefix codec | `codec.lisp` | 221 | as design | size by counting emitter, canonical decode. The opcode table is a tariff choice you have waived |
| Solver schema and fiber certification | `laws.lisp` | 186 | as design | "a solver is two laws" |
| Reserve scheduler | `synthesize.lisp` | ~125 | as design | the 3:1 tentative/fallback split. The formula is hard-coded; the shape is reusable |
| Resumable row-job stepping | `enumerate.lisp` | ~90 | re-seat | results identical however the run is sliced; assumes frame rows |
| Observation and bucket engine | `enumerate.lisp:563-877`, `laws.lisp:215-228` | 215–315 | re-seat | this already is "classes by behaviour"; depends on the enumerator and the row-job base |
| Requirement propagation, with replay and fallback | `laws.lisp:736` onward | 338 | re-seat | tentative use of tested knowledge, done safely; takes a frame |
| Root verification of every candidate | `synthesize.lisp` | ~45 | re-seat | what makes aggressive heuristics safe |
| Message-to-frame bridge | `messages.lisp` | 128 | re-seat | the seed of the derivation space; builds a frame |
| Guard and solver discovery | `milestones/algebra-discovery.lisp` | ~370 | re-seat | guards fitted to agreement masks, errors as outcomes; works through `support-frame` |

**Import the idea and the tests, rewrite the code**

- *Pullback* (`frame.lisp:544-580`): 37 lines; its soundness tests are worth more than the code.
- *Definedness-preserving folding* (`requirements.lisp:129-540`): keep the two-contract discipline (equivalent, or merely necessary) and its tests; the rule set is per-opcode and will change.
- *Totality checker* (`ast.lisp:696-1101`): keep the fact-and-measure scheme, about 50 lines, and the least-fixed-point discipline. The rest is wired to specific opcodes.
- *Closure compiler* (`vm.lisp:402-551`): keep the idea of a fast path with identical cost accounting.
- *Metric decoder* (`laws.lisp:1250-1327`): keep the concept, an invertible operator with its solver; it becomes the `decode` construct.
- *From v2*: the six Stage 0 soundness fixes; the ablation harness `stage0-audit.lisp`, with the harness defect the audit found repaired; and, from Stage 1, the pieces its auditor judged salvageable on their own: behaviour pruning and column evaluation (once tested), the definedness guard derived from an operator's preconditions, difference facts for variable indices, and the index-preimage rules for `gather` and `evolve`.

**The test contracts are an asset independent of the code**: budget obedience and resumption parity, codec round-trip, soundness of each pull-and-compose pair, fold soundness under both contracts, and closure/interpreter equivalence. They should be the first thing ported and the gate on every stage.

**Leave**

- Most of `frame.lisp`, and all of `proposals.lisp`, `decompose.lisp`, `nogoods.lisp`, `descriptors.lisp`, `templates.lisp`, and the shape recognizers in `consolidate.lisp`. They are glue around the one-unknown frame, or task-shaped patches. Within the search files alone, the search audit counts about 4,800 of 7,101 lines that way.
- `bootstrap/recursion-schemas.lisp`, which describes itself as "the shape of one battery function ..., written by hand".
- The rest of the Stage 1 additions in `v2/`, in particular the container-cover proposal generator. They should be mined, not continued (§2.9).

On tariffs: nothing here preserves the present bit prices or work prices, and three of them are artifacts (§2.7). What must be preserved is the discipline: prefix codes, exact ledgers, and no refunds.

## 10. Risks, and where there is no precedent

Each risk is paired with the cheapest test that would expose it. §11 orders those tests.

| # | Risk | What would show it |
|:--|:--|:--|
| 1 | Lifting by a change of space works in the prototype, on its own rows (§8.1) and on 13 of 16 of the kernel's spec rows (§8.6), and not inside the kernel, or on tasks needing two lifts | the 16-spec ladder without whitelist, schema, or trace-shaped rows (§11, X3) |
| 2 | Inverses from tables stop at one-operator inverses. The audit's own run found the solver search "has a one-operator answer" in every case | compose known inverses through a term; test on `a*x + b = c` and on `x + x = c`, which the present kernel cannot solve |
| 3 | Classes on a small probe space merge terms that are not equal, and false laws accumulate | count laws that fail on fresh rows. On the prototype: none at 8 or more probe rows, 199 at 3 rows (§8.3) |
| 4 | Counts over tens of solved problems carry no signal. The one existing learned predictor learned a constant | the guidance ablation (X4), before building any of §6.3 beyond types |
| 5 | The agenda fills the library with true, useless entries. One published law finder at 33 functions "generate[s] too many laws"; another's authors say more depth "does not lead to many useful lemmas" | utility accounting by ablation on every entry (X5). The prototype's kept-law set already grows ×2.8 per unit of size (§8.3) |
| 6 | The rewrite grows. Three successive plans each promised a smaller kernel and delivered a larger one | a complexity-score gate per stage (your margin note: complexity scores are "less gameable" than line counts), and the ported test contracts |
| 7 | Deep searches exhaust memory before time | bank memory bounded per problem account; measure retained classes per hour |
| 8 | "The store's operations are programs" turns out elegant and unprofitable. The review found reflection paid off only in cheap, measured forms: memoization, dependency graphs, partial evaluation, bandit allocation | keep it off the critical path; X8 is last |
| 9 | Geometry costs more than it saves, as the metric decoder did | X4 again; the per-column codes are needed regardless, the rest is optional |
| 10 | Anti-unification over few instances over-generalizes | the existing description-length gate; negative controls already in `tests/theories.lisp` |
| 11 | Search across spaces is spent on the wrong pairs, and costs more than it finds | the retrieval measurement of §8.7, repeated on the kernel's tasks (X4); a budget account for every attempt (X9) |
| 12 | A vocabulary the kernel generates for itself carries no signal beyond a control that ignores the task. Flat signatures did not, for operators (§8.7); verb tables did, on a hand-written library in Python (§8.8) | X4, on the kernel's own library |
| 13 | Verb tables lose answers. They are tested knowledge, and lost from none to 11% of tasks, depending on the number and choice of probes | use them to order, or to filter a tentative attempt that has a fallback; count answers lost in X4 |

**No convincing precedent anywhere**, per the three literature reviews. The plan depends on the first three and on the vocabulary item below. The last is the plan itself. The others are deferred or avoided by design.

- A synthesizer learning the inverse rules it then uses. Hand-written in every synthesizer checked. *Depended on, in Stage A; shown for single operators on the prototype (§8.2).*
- A closed loop in which discovered laws, inverses, and abstractions become the next round's primitives on the same store. Abstraction alone has precedent, and plateaus. *Depended on; X5 is the test.*
- Algebra from depth-two experiments, and conditional equalities with learned guards kept in one store. Published guard search stops at about four nodes. *Depended on, in Stage D (X6) and for guarded laws (§5.5).*
- A self-generated curriculum. *Not depended on: tasks still come from external data.*
- A search policy learned by the synthesizer about itself that keeps improving. *Not depended on.*
- Higher-order functions from first-order primitives in hours. The one precedent used about 7,700 CPU-hours. *Avoided: the lifting forms are granted (§7.1), and `:map`/`:foldr` already emerge by anti-unification.*
- Recognizers of the autocorrelation kind invented from data. *Not depended on.*
- Termination guards learned from timeouts. *Deferred (§7.5).*
- A vocabulary that a system chooses for itself and that goes on improving its own search. *Depended on, in Stage C. Guiding search by abstract values is established where the abstractions are written by hand. Tables read off an operator's own probe rows, and quotients chosen by the store, were measured once here (§8.8). The compounding has no precedent.*
- Coordinate spaces created from few samples without gradient descent; words as geometric modifiers. *Not depended on (§6.4, §6.6).*
- A unified topology–geometry kernel. Nothing attempts it, and this plan is such an attempt. The working pieces elsewhere are value vectors and hash tables, which §5 uses, and rewrite systems, e-graphs, and decision trees, which it does not.

One cautionary sentence is worth keeping in view. It is from the authors of DreamCoder, about their own run that rediscovered `fold` from first principles in about a year of CPU time: "We do not advocate such blank-slate learning as a route to AI."

## 11. Experiments, and a staged path

### 11.1 Already run in this audit

| Question | Result | Where |
|:--|:--|:--|
| Does raising the budget rescue the existing engine? | No: 8 → 10 → 10 → 10 of 16 over three decades | §2.3 |
| Does behaviour dedupe matter? | Yes: between 6× and 470× less work, depending on the grammar; 99% of trees on the real grammars are duplicates | §2.3 |
| How much of the library did the kernel find? | 2.5% of bits by generic search; 59% hand-authored | §2.5 |
| Does the library compound? | On some tasks, when used for lifting (3 of 8 unreachable tasks solved; 3 or 4 dearer); not when offered as plain operators | §2.5 |
| Does anything trace-derived transfer? | No; only abstracted functions do | §2.6 |
| Can the existing engine find distributivity? | Yes, in under a second, when asked directly | §2.4 |
| Does a factored store make lifts, inverses, guards, and laws cheap? | Yes on the prototype: 15 of 15 sequence tasks, the arithmetic inverses with guards, and the ring laws; with four measured limits | §8 |
| Does the prototype hold up on the kernel's own spec rows? | Mostly: 13 of 16 specs reach 200/200 in some configuration, three of them only after a change (splits accepted in size order; collect under an aggregate; a Boolean call in the grammar), and two more only through the `fold` route. `foldl` is underdetermined; `best-shift` and `argmax-corr` are not solved | §8.6 |
| Do store-generated signatures say which problems to mix? | For a program's form, yes, at three times chance. For its operators, no: no more work saved than by a control that ignores the task | §8.7 |
| Is an analogy between two operators' tables cheap to find? | Yes when a small term carries it: 350 tested in 1.3 ms, 29 hold, none false on fresh rows | §8.7 |
| Does matching rows without a key need backtracking? | Not on irregular or symmetric data, where choices are never undone. Yes on regular structures without symmetry, and heavily to reject look-alikes | §8.7 |
| Do tables of what operators do to coarse labels cut search, including for never-used operators? | Yes, on a hand-written library in Python: about 15× in candidates and 1.3× to 4× in time, more at larger sizes, with 0.3% of answers lost at 1,000–3,000 random probes | §8.8 |

### 11.2 Next, in order

Each experiment has a gate fixed in advance. The standing metric for all of them is the **kernel-found fraction**: the share of library bits produced by search with no operator whitelist, no recursion schema, no trace-shaped rows, and no hand-written entry. Today it is 2.5%.

- **X1. Classes.** Build the store core (spaces, columns, hash-consed terms, classes, columnar evaluation) and run law discovery on it. *Gate:* the same 187 equations on GF(3) as the present bucket engine, plus distributivity; at least 10× less work than v1's enumerator at the same bound; retained memory proportional to classes, not trees. Also measure what pruning by already-found laws would add on top of classes (§5.8).
- **X2. Reorientation.** Find the eight arithmetic solvers and their guards from operator tables alone: no spec rows, no witness language beyond the operators in scope. *Gate:* the same witnesses and guards the milestone code finds, including the unknown-divisor solver and the integer divisibility guard, neither of which the prototype produced. The two composite cases in risk 2 are reported, not gated.
- **X3. Lift.** Run the 16-spec ladder with the full grammar, no schemas, and ordinary input/output rows. *Gate:* at least 14 of 16 held-out-sound (today 8–10); nothing returned that fits the rows and fails held-out; `foldl` either solved or reported as underdetermined; no guard split accepted that fails the rule of §8.5.
- **X4. Does a vocabulary pay?** On X3's tasks with 30 or more distractor library entries in scope, some of them never used in any solved task, compare five arms: no guidance; types only; flat signatures with counts (§6.3); verb tables used only to order; verb tables used to filter a tentative first attempt, with a fallback (§6.6). The quotients are chosen by the store, with none listed by hand. Count the fair cost: every pass of the search, the fallback whenever a filtered attempt misses, the look-ups, and the time to choose the quotients. Report wall time beside candidates, the baseline averaged over operator orders, and every answer lost. *Gate:* at least 3× lower median wall time on held-out tasks, including those that need a never-used entry, with no answer lost after the fallback; or §6.3 and §6.6 are not built further. This is the outside review's second proposed change, with the accounting that its reproduction showed to be necessary (§8.8).
- **X5. Compounding over hours.** Run the agenda of §7.5 for one hour and for ten, from the primitives and the task data only. Report entries found per hour by kind, held-out tasks solved before and after, and an ablation of every entry. *Gate:* the function set of today's library recovered with zero hand-written entries, and later tasks measurably cheaper than earlier ones.
- **X6. Depth two.** Laws over spaces whose rows range over functions (map fusion; fold over map); anti-unification over accepted solutions on the instance space. *Gate:* `:map` re-emerges with a positive gain, as it does now; at least one two-function law is found and survives fresh rows.
- **X7. Reflection.** Counts and the problem memo from the derivation space, each under ablation. *Gate:* a measured reduction in work on problems not used to collect the counts.
- **X8. Self-description.** Write the store's own operations as VM programs and pose one of them as a synthesis task. *Gate:* none; this is exploratory.
- **X9. Search across spaces** (runs alongside X4). Build colour refinement with backtracking on the store's group-by and re-index, and the map-hole form of §5.9, each attempt on its own budget account. Re-express the prototype's subsequence aligner as a map search under an order constraint. *Gate:* the selective specs still solve with the hand-written aligner removed, and analogies between operator tables are found as terms, as in §8.7.

### 11.3 Stages

| Stage | Contains | Ends when |
|:--|:--|:--|
| A | Store core; imported VM, codec, evidence, enumerator, certification; ported test contracts | X1 and X2 pass |
| B | Requirements with holes; the refinement table of §7.2; spaces with maps | X3 passes |
| C | The agenda; utility accounting; the vocabulary of §6.6 (quotients, verb tables, name prices); search across spaces by term, by refinement, and by capped backtracking | X4, X5, and X9 pass |
| D | Depth-two spaces; abstraction over classes; the derivation space and its readers | X6 and X7 reported |

Stage A is the smallest piece that tests the central claim. X1 is shipped technique throughout. X2 is this plan's own mechanism, shown so far only on the prototype and only for single operators. If X1 or X2 fails, the plan is wrong at the root and that is known within the first stage. Stage B rests on the plan's own lifting mechanism, shown so far only in the prototype, though now on the kernel's own spec rows as well (§8.6). The larger research risk sits in X5 and X6.

Three working rules, drawn from what went wrong before (§2.9; plan 9 audit):

1. **Run, then write.** No number enters a plan document without a script that reproduces it.
2. **One increment, one gate.** Each gate is tied to a recorded baseline before the work starts.
3. **The kernel does the next experiment.** When an agent finds itself running a simulation on the kernel and reading the result, that experiment is a candidate for the agenda of §7.5. This was your own observation during plan 9.

---

## Appendix A. Direct answers to the points in your prompt

| Your statement | Finding | See |
|:--|:--|:--|
| "wondered if the frame representation is correct and properly supportive of all the operations required" | A frame is right for one thing: a per-row predicate on one unknown, pulled back by substitution. It cannot hold a relation among unknowns, a position, or anything about expressions. | §2.1 |
| Of anti-unification: "really it's a form of quotienting and trivial lifting under substitution" | As intuition, yes. On the store it separates into a shared pattern (the constant columns of an instance space) and a quotient (the class of terms with one behaviour). The "trivial lifting" is the instance space, with the substitutions as its varying columns. | §5.4 |
| "an expression is a common pattern found in the execution graph, just lifted to independent contexts" | Exactly the factorization pattern × rows. The store is built on it. | §5.1 |
| Topology "can be learned in the process of executing the simulator ... (holding all but a few constant)" | Supported. A dependency test is a group-by on a table. The kernel has it in one function, `target-sensitive-p`, whose only caller is itself reached only from tests. The method has long precedent for numeric laws and for program slicing. | §2.4, §7.5 |
| "Algebra emerges from running parallel and depth >= 2 experiments" | Depth one exists and works; a script limits it. Nothing today runs the observation engine over expression-valued inputs. Spaces whose cells hold terms are the proposal. The closed loop has no precedent. | §2.4, §5.4, §10 |
| "A conditional is a partition ... here it's learned experimentally" | Already implemented that way in the milestone code: an agreement mask becomes a Boolean target. A guarded law is a class on a sub-space. | §2.4, §5.5 |
| "Making a tuple is an explicit example of instantiating a connection or edge, albeit one with coordinates" | Yes. A row is a tuple is an n-ary edge; a table is a relation. Store the factorization, not the instance graph. | §4.2, §5.2 |
| "lift has to be a synthesizer primitive just like substitution is ... Presently ... wholly in the host lisp" | Confirmed, and wider: of the operations you list, only substitution, value projection, tuples, and `if` are available to a program. | §2.2 |
| Reentrancy as "freely shifting abstraction level" | Blocked by eight concrete things, among them: synthesis is not a VM operation; frames are host structures; proposals are host closures; recursion mutates a global table; nested searches are not resumable and take literal budgets; a child is always the same target through a one-hole decoder. | §2.2; search-engine report §6.2 |
| "there are a good number of guards for this in the kernel, afaik" | 30 of the 158 hard-coded decisions are dedupe or memo guards. | §2.3 |
| "'residuals' of frame becoming a bit clunky ... not sure if there are better options ... other than pricing in the original or ambient spaces" | Eight representations of one thing. Ambient pricing is not the fault, and cannot be beaten except through a verified bijection or by paying for the fiber. | §2.7, §6.2 |
| Policies and heuristics "harder to naturally implement" | The one learned policy is a clamped regression on six integers. It learned the constant 0. | §2.6 |
| "high-D embeddings are 'flat' ... there could be good reason for keeping the vectors flat" | Not a question of what can be represented. A flat space buys storage, not computation, and this library has no storage pressure. Use one flat signature space as an index. | §4.5, §6.4 |
| "Poor data representation seems to have induced overbearing incidental complexity & compartmentalized algorithms" | Supported: one concept implemented three or four times; fourteen kinds that are one struct; eight residual forms. | §2.2, §2.4, §2.7 |
| "underwhelmed with the quantity of information that can be abstracted to the bootstrapped knowledge library" | 2.5% of library bits come from generic search. | §2.5 |
| Totality: "support learning them by tolerating crashing or non-terminating behavior" | The VM already returns a crash and a cutoff as data, and totality gates only rewrites, never execution. Three gaps: the fault is an unstructured string; search discards it; no opcode observes it. Timeouts have no precedent. | §7.1, §7.5 |
| "it's been the AI agents that are doing the majority of search" | Confirmed. Nothing in the kernel initiates discovery, and an answer key preceded the bootstrap. | §2.4, §2.5 |
| The search budget "was very limited" | True by four to five orders of magnitude, and not the binding constraint. | §2.3 |
| "we'd need an efficient graph isomorphism test (not for AU of course), or e-graphs" | Within a space, neither: rooted, ordered, shared terms are compared by hash, and laws up to renaming by brute force over at most five variables. Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run on what the index proposes. The e-graph's store is useful; its saturation is not. | §4.3, §5.9, §7.6 |
| "nothing 'very interesting' was findable in the small budgets" | The largest expression found by enumeration has 8 atoms. But distributivity was findable in under a second: no job asked for it, the shape filter had no case for it, and the budget was 85 times too small. Some of "not findable" was "not asked". | §2.4, §2.5 |
| "some of the fundamental datastructure choices are OK" | Agreed. Columns, a behaviour table, and a shared term graph are common to both earlier plans and survive here. | §2.9 |
| The geometry dialog is "not ... a closed case" | Agreed. | §6.7 |

## Appendix B. Nuggets from the trail, with locations

Locations are as given by the document auditors. "Code" says whether the idea is in the root kernel today. Numbers from plans 1 and 2 came from Python scratch scripts that were never committed.

| Nugget | Location | Code |
|:--|:--|:--|
| Counting identity H(X) = H(f(X)) + E log|fiber|; running backwards is supplying the index | `deprecated/plan2.md` §1.1 | not as such |
| One residual definition for fiber index, guard or mask, and metric error | `deprecated/plan2.md` §1.2 | no; eight forms |
| "No column is designated as input or output"; solve rules are the other directions | `deprecated/plan2.md` L835-837 | `orient-observations`, tests only |
| Matching is conjunctive-query matching, not isomorphism | `deprecated/plan2.md` §1.8 | never built |
| Laws are invisible to compression, immediate under shared-input experiments | `deprecated/plan2.md` §4.4 | never reproduced |
| Small residual magnitude is not structure (correct lift ranked 66th of 2,661) | `deprecated/plan.md` L579 | — |
| Lift as predicate pullback, B(z) ⇔ A(d(c, z)); "Pattern instantiation is the decoder. The substitutions become the child targets." | `deprecated/plan3.md` §3 | `frame.lisp:544`, `unify.lisp:103` |
| Explanation-based generalization: variabilize what the derivation did not depend on | `deprecated/plan.md`–`plan3.md` | never built |
| Forward tables as relations with a re-choosable base; a solver as two ordinary laws | `deprecated/plan5.md` §2.3 | solver obligations in `laws.lisp` |
| After an equation is observed, "the unresolved information is the membership of each input in its valid subset" | `deprecated/results.md` L730-733 | milestone guard search |
| An intervention-style generator, G(k, u) = (u, k − u), written and never run | `deprecated/results.md` L499-507 | no |
| Quotient by laws before anti-unifying (5 holes → 2) | `deprecated/results.md`; `deprecated/plan6.md` | pre-normalization only |
| Pullback keeps the fiber; inversion chooses a section; uniqueness certifies the fiber is a point | `plan7/plan7.md` L156, L379 | `:witness`, `:uniqueness` |
| "A metric and a decoder shell are two views of one correction code" | `plan7/plan7.md` L641 | metric decoders |
| "This price is one step deep": residual in the child's space, program at the root | `plan7/plan7.md` L437 | `synthesize.lisp:447-457` |
| "b bits of freedom is constrained by O(b) scalar fiber observations" | `plan7/plan7-m9-policy.md` L5 | — |
| Graph distance between library entries as locality | `plan7/plan7-library.md` §2.2.3 | never built |
| Names "whose usage probabilities and context affinities are coupled to the search policy and language tariffs" | `plan7/plan7-recursion.md` L65-67 | never built |
| Totality "only gates algebraic erasure ...; it does not restrict what functions can be defined, enumerated, or executed" | `plan7/plan7-recursion.md` L97 | true of the code |
| The "shared part plus per-instance part, search in a different place" table | `plan8.md` §2.1 | — |
| Solver discovery as an experiment on empirical fibers, guards from where replay fails | `plan9.md` §3.1 | `induce-conditional-solver` |
| "A node's priority is an estimate, not a lower bound; the only true bounds are enumeration frontiers" | `plan9-audit.md` | — |
| Sampled evidence "can propose and never eliminates" | `plan8.md` §6.7 | `evidence.lisp:62-73` |
| Discrete labels and coordinates need different distances (59 pairs became 106 when confused) | `plan9-audit.md` L331 | — |

## Appendix C. Your annotations on `plan_v2b.md`

The annotated PDF holds 28 annotation objects: 11 typed notes, 14 highlights, 3 ink strokes. `plan_v2.tex` listed seven notes, with wrong page numbers. The four typed notes it missed:

| Beside | Note |
|:--|:--|
| §9 risk 3: extraction is NP-hard; anytime search remains necessary | "Yes, I know." |
| §9 risk 7: a link between sheaf-style obstruction and clause learning | "what exactly does this mean?" |
| §9 risk 9: the kernel "chooses experiments" | "Yes!" |
| §8, the unit-exact ledger parity bullet ("work drift is tolerable") | "yes. and new (local) metrics may be admissible, even if they are not desireable." |

Highlights it missed include "Reuse has lost to matching cost in every small measured case on record", the passage on distributivity having no shape in the law filter, and "Lifting e-graphs". It also missed an ink bracket around the paragraph on a recognizer being a solver plus a decoder.

Read together, the notes accept the sober claims without comment and ask for mechanism or evidence wherever the text leans on literature: "how, though?", "what is the evidence for this? Or proof?", "Which successful engines?", "what exactly does this mean?". This plan was written to that standard: each proposal names its mechanism, and each number names its source.

## Appendix D. Mechanisms the earlier audit passes rejected

This plan re-imports none of these, with two exceptions that are argued for in the open: the lifting forms (§7.1) and subsequence alignment for selection (§7.2). Two further proposals are close relatives of rejected items and are flagged where they appear: random-walk proximity and count-based triggers (§6.3). Reasons are those recorded in the revisions of `plan_v2.tex`.

| Mechanism | Why it was rejected |
|:--|:--|
| A 256-dimensional vector-symbolic bus, with binding as "creating a space" | computation in superposition does not compress; unbinding noise; no composition in one layer |
| Sheaves with learned restriction maps | learned maps rarely beat the identity |
| A five-extension e-graph (relational matching, thinning union-find, colored classes, AC multisets, e-graph anti-unification) | never combined in any published system; the plan's own combination equated `x0 − x1` with `x1 − x0` |
| Consistency radius as a residual price | double-counts rows covered by three or more patches |
| Cohomology as a source of nogoods | signed combinations cancel when no discrete solution exists |
| A symmetry refund of −log₂|Sym| bits | violates the Kraft inequality when the child is a program |
| Branch forking on every `if` | 2ⁿ worlds on `filter` |
| Accumulator synthesis from a source loop | input/output synthesis has no source loop |
| Cross-multiplying through integer division | division truncates |
| A trained attention router | more weights than library entries |
| Associativity and commutativity hard-coded in the term constructor | domain content in host code |
| Host probes for correlation, differences, and linear recurrences | domain solvers in the core |
| A spectral embedding and a `like`/`analogy`/`act` query language | interpreter weight at a library of a few hundred |
| A difference-bound matrix on every enumerated node | 10–30× more than needed |
| Permutation search for unordered covers | factorial |
| `:tabulate` and `:loop` opcodes (rejected in one pass, restored in the next) | "smuggled" higher-order functions; see §7.1 for the line this plan draws |
| A subsequence propagator specific to `filter` | hard-codes one library function. **The prototype's selection lift uses a subsequence alignment**; see §7.2 for the argument and the caution |

What survived every pass unchanged is short: columnar tables, a behaviour table, a single record for all knowledge, the Stage 0 fixes, and the audit of the kernel.

## Appendix E. Literature, with maturity

"Shipped" means load-bearing in widely used systems. "Replicated" means several independent working implementations. The literature reports carry a verification tag on every figure, and the citations. Most figures below were checked against the source online. These were not: the 17-year span for OpenCog (from memory; its benchmark claim was checked against an abstract); FlashMeta's deployment and the identity of e-graphs, version-space algebras, and tree automata (abstracts only); anti-unification as a product (a summary only; the paper could not be fetched).

| Technique | Maturity | The number that matters | Role here |
|:--|:--|:--|:--|
| Hash-consing, union-find, congruence closure | shipped | n log n | the term graph |
| Value vectors with observational-equivalence classes | shipped | standard backbone of bottom-up synthesis | classes |
| Law discovery by testing and collision (QuickSpec 2) | replicated | 398 laws over 33 functions to size 7 in 42 min, one thread; size 8 exhausts memory | §7.5 laws |
| Pruning the term space with laws already found (Ruler) | replicated | 350 s with it; unfinished at 24 h without | not adopted as such: the plan prunes by class and keeps laws by use (§5.8) |
| Conditional laws with searched guards (Speculate, Chompy) | replicated, small guards only | conditions to size 4; 26 min for 14 operators | classes on sub-spaces |
| Preconditions from failures (PIE and relatives) | replicated | 87 of 101 correct; a larger predicate grammar hurt in 65% of cases | guards |
| Equality saturation | shipped in one compiler, in a restricted form (acyclic, eager rewrites) | average class size 1.13; ~0.1% from multiple representations | not used |
| Binders and conditions inside e-graphs | single group | — | not used |
| Deduction through `map`/`fold` combinators (λ²) | one system; its family is replicated | median 0.43 s; >60% time out without type pruning | the refinement table |
| Recursion synthesis from examples (Myth, Escher, Burst) | replicated | 15–30 node functions in under 1 s with minimal contexts; five extra helpers: 0.07 s → 128 s | §7.3 case 5; context selection |
| Library learning by compression (EC², DreamCoder, Stitch) | replicated | roughly doubles solve rates, then plateaus; fold from first principles ≈ 7,700 CPU-hours | abstraction; the argument for granting lifting forms |
| Grammar reweighting during search (Probe) | one lineage | 91 of 140 against a weak baseline's 44; modest against a strong one | counts |
| Property signatures (BUSTLE) | one lineage | 45 hand-written properties beat learned embeddings, both as input to a trained network | signatures |
| Witness functions (FlashMeta) | shipped, hand-written | — | precedent for inverses, not for learning them |
| Relational interpreters run backwards | replicated, impractical | each interpretive level costs 6–178× | avoided |
| Uniform hypergraph stores as learners (OpenCog, Hyperon) | no quantitative result in ~17 years | — | avoided |
| Learned coordinate embeddings (hyperbolic, knowledge-graph, sheaf) | need gradient descent and ~10⁵ examples | Euclidean matches hyperbolic from 50 dimensions; a rule miner matches graph embeddings | not used |
| Computation in superposition (Adler and Shavit) | theorem | n neurons compute at most O(n²/log n) features; representing needs O(log m) | the flat-versus-nested answer |
| Words as program fragments with count alignment (LAPS) | one lineage, on a neural search component | 42.6% → 82.0% in one domain; weaker with human descriptions | labels from people, last (§6.6) |
| Synthesis guided by abstract values, with abstract semantics written by hand (Blaze, Simba, Absynthe) | replicated | 519 of 544 bit-vector problems against 456 and 409 for two enumerative solvers; one of those two wins on the suite's conditional problems | the filter of §6.6, where the tables are instead read off probe rows |
| Abstractions learned for such a synthesizer (Atlas) | one system | 8.3× and 9.2× over hand-written abstractions on its own benchmarks, 2.1× and 3.1× on its predecessor's; needs training problems and hand-supplied operator axioms | nearest precedent for choosing quotients (§6.6) |
| Abstractions merged and shrunk automatically, for planning heuristics (Merge-and-Shrink) | replicated, in planning | perfect heuristics in polynomial time in three of six benchmark domains; lower total coverage than most competitors in the paper's own comparison | not adopted: merged quotients lost answers (§8.8) |
| Reflection that compounds (EURISKO) | unreproduced | its author credited the representation | not depended on |

Verification gaps the auditors declared: three of four sub-searches on 2025–26 work ran out of quota, so "none found" for learned inverses and learned termination guards is a weak negative; some figures exist only in plots; all line-count estimates for minimal implementations are the auditors' own. The three rows on abstract values were added in the revision and checked against the papers' text (`lit-abstraction.md`); a 1977 paper by Knuth that the outside review also cites could not be fetched.

## Appendix F. Audit reports, and housekeeping

**Reports.** Fifteen reports stand behind this document, about 174,000 words, each with file-and-line citations and its own list of what it could not determine. A sixteenth, `factcheck.md`, is an independent check of a draft of this document against the others, the logs, and the code. It found 10 factual errors, 19 over-statements, and 48 smaller points; all were applied. It also tabulates where the reports disagree with one another (throughput, candidate rate, a few line counts) and which figure this document uses. They are copied to `plan_v2c_audit/` beside this file, because the session's scratch directory is not durable. The revision of 25 November added six more, listed last in the table, with their scripts and logs in `plan_v2c_audit/verify-review/`, `cross-space/`, and `verify-quotients/`.

| Report | Scope |
|:--|:--|
| `core-repr.md` | data structures and VM; the operation table; index handling |
| `search-engine.md` | search algorithm; budget inventory; the 158 hard-coded decisions; reentrancy |
| `laws-library.md` | algebra discovery traced; the 14 kinds; conversions; anti-unification |
| `bootstrap-reflection.md` | provenance of every library entry; what reflection exists |
| `empirical.md` | baseline, throughput, growth, the budget ladder, algebra scaling, profile |
| `docs-origins.md` | original prompts and plans 1–4 |
| `docs-plan6-results.md` | plans 5–6 and the measured results record |
| `docs-plan7-arch.md` | plan 7 and the two architecture documents |
| `docs-plan8-9.md` | plans 8–9, the plan 9 audit, batteries and reflection |
| `docs-v2b.md` | `plan_v2.md`, `plan_v2b.md`, and the PDF annotations |
| `docs-v2tex.md` | `plan_v2.tex`, its revisions, and the Stage 1 code |
| `lit-discrete.md` | graph stores, e-graphs, rewriting, anti-unification, reflection towers |
| `lit-search.md` | law discovery, enumeration at scale, library learning, guards |
| `lit-geometry.md` | embeddings, spectral methods, pricing, language |
| `proto.md` | the prototype of §8 |
| `factcheck.md` | independent check of the first draft of this document |
| `verify-review.md` | reproduction of the outside review's first section (§8.6) |
| `cross-space.md` | the measurements of §8.7 |
| `verify-quotients.md` | reproduction of the outside review's second section (§8.8) |
| `lit-abstraction.md` | check of the citations in the review's second section |
| `factcheck2-A.md`, `factcheck2-B.md` | two independent checks of the revision against the logs and sources. They made 41 findings, 14 of them factual errors; all were applied |

**Things found along the way that are not about the design.**

- The root kernel test suite fails on a clean checkout: root has no tracked `library/`, and `lifting`, `metrics`, `structural`, `invariants`, and `theories` need it. `make bootstrap` first, or track the generated files as `v2/` does.
- Five documents cited by the trail were never in the repository on any branch: `plan7-recursion2.md`, `audit-review.txt`, `plan8-2.md`, `plan-let.md`, and `plan_v2_annotated.pdf`.
- `architecture2.md` was stale on the day it was committed and has drifted further (27 primitives, not 26; 14 kinds, not 11; several named functions are gone).
- `v2/package.lisp:66-69` exports about ten symbols that are defined nowhere.
- In `v2/`, `(tabulate n F)` with `F` a code variable fails an assertion at construction (`v2/ast.lisp:1096` against `:673`).
- One defect in the Stage 0 harness, seen twice: a failed synthesis leaves its oracle stub defined, so later specs lose a prerequisite, and the `argmax-corr` "FAIL" is the resulting commit error after a correct search. With that repaired, and a clean library for each spec, one auditor's recount of the four regimes is 16, 10, 11, and 9 of 16, not 16, 9, 9, and 8. This document keeps the harness's own figure of 8 as the baseline in §2.3 and X3, because the budget ladder was run against it.
- Evidence soft spots: one milestone path attests sampled integer uniqueness as `:derived`; arithmetic solvers for `*` and `/` carry no certificate, only a hand-set flag.
- `body-size` is documented as constant-time and is linear.
- Two pricing defects. The outside review reported the first, and the second was found while checking it. An exact cell costs zero bits in `correction` (`frame.lisp:1581`), which breaks the prefix-code bound wherever cells are priced one by one; and `frame.lisp:1572` takes the cheaper of two codes without paying to say which. The first is not reached in Stage A's main pricing path, which under-pays one bit per model instead; it is live in `induce-row-order`, which only tests call. The second sits in the sequence branch of `correction`. By a reading of the code that was not run, Stage A reaches it for every exception row with a sequence target; how often it changes a price was not measured.

The outside review itself is `plan_v2c_audit.md` at the repository root; Appendix G records what was taken from it.

## Appendix G. Your annotations, and the outside review

This appendix records the revision of 25 November. It answers the two questions in your request, then each note on `plan_v2c_annotated.pdf` and `plan_v2c_audit_annotated.pdf`, and says what was taken from the outside review, `plan_v2c_audit.md`, and what was not. The review was read as it stood at 17:20 on 25 November (323 lines). It grew twice while this revision was in progress, after your annotated copy: first by its second section, then by an appendix that restates that section in plain words and makes no new claim.

### G.0 The two questions in your request

**Computation within frames against search across them.** Accepted as you put it, and made a section (§5.9). Within a space everything is computed, in time linear in the cells touched; the one search there is for the term itself. Across spaces nearly everything is a search for a witness: a map, a substitution, a pattern, or a quotient. The witness is cheap to check and can be hard to find. Compression lives on that side, so the search is allowed, and it is budgeted differently: every attempt is tentative, capped, and recorded. A matching engine is included, as colour refinement with backtracking. Measured for this revision: refinement matches irregular data of 10,000 rows with no backtracking; regular structures without symmetry, and look-alikes that must be rejected, need it at once; and a crossing whose map is a small term costs almost nothing (§8.7). You asked that the hybrid kernel cheaply prioritize mixing between frames. The obvious way, overlap of signatures between problems, was measured and does not do it: it finds the form of a program and not its operators. What did work is in the next paragraph.

**Language.** Your sense that the representation behind it would unlock other expensive parts is supported, within limits that are now measured. The representation is the outside review's: a word is a label of a small quotient of values, and each operator carries a table of what it does to labels. A description is then a run of the program on labels, which is your October sentence made literal. On a hand-written library of 61 operators this cut candidates about 15 times and time 1.3 to 4 times, more at larger sizes, and worked for operators never used before, where prices from counts of past use failed (§8.8). The same object serves signatures, the choice of what to mix, guards, and part of the memory wall on arithmetic. In the one small test it did not serve reflection as an index, where plain replay did better. Over the sizes tried it behaved as a constant factor in candidates, and it loses a small share of answers, so it may order and filter tentatively but not eliminate. The vocabulary moves into Stage C, and X4 is rewritten to test it on the kernel's own library (§6.6).

### G.1 Notes on this document

Highlights without a note are listed only where they changed something.

| Where | Your note | Answer | Changed |
|:--|:--|:--|:--|
| §1.5, "A primitive may encode the shape of a container" | "does this mean a learned library primitive describes a datastructure .. ?" | Yes, in this sense. A container, on the store, is a recipe for a space: which rows a value unfolds into, the map back, and how to rebuild or reduce. The granted forms are that recipe for the one container the VM is born with. A learned container would be a library entry of the same shape: a pair of terms, unfold and build, that are inverse on the examples. A matrix is two nested position spaces; a tree is a position space with a parent endomap. So a data structure is a learnable entry, written in the store's own nouns. It is proposal, and not before Stage D. | §7.1 |
| §2.3, "It cannot buy more structure" | "so - it cannot go any deeper -- ??" | Correct. The job's tree is a root with one or two children, and it stops there. A child is expanded only when some generator proposes a decomposition for it, and none does. On the four stuck specs, raising `:max-depth` to 3 or 4 changed nothing. More budget lengthens the expressions enumerated at those nodes; it does not add nodes. | §2.3 |
| §2.3, the behaviour pruner | "is this a subset of the message idea / prototypes in the old code? What about UIP / DIP, which might be a special case of messages? Can part of the action of a behavior pruner be done by reflection?" | Yes to all three. The pruner's fact is "this column equals one already kept", which is a message in plan 4's sense: a claim with its evidence. A nogood is the same kind of fact about a requirement: a dependency test that failed. The UIP step generalizes such a fact; the DIP step looks for a column that separates the conflicting rows. On the store all three are facts about classes on one space, kept in one table. The pruner is also the cheapest reflection there is. What reflection could add is prediction: skipping the evaluation when a law or a count says the candidate will collide. | §7.4 |
| §2.8, "Quotient by laws before anti-unifying" | "duh" | Agreed. It is kept only as the measured form of the claim. | — |
| §4.5, "Trees embed exactly in squared-Euclidean space" | "is this true? The other doc mentions that superposition can only store quadratic items, not exponential.." | It is true, at one dimension per edge, which the draft did not say. Give each edge its own axis; a node's vector has the square root of an edge's weight on the axis of every edge between it and the root; the squared distance between two nodes is then exactly the length of the path between them. So it shows that nesting can be represented, and nothing about economy. On economy the other document and this one agree, and the draft was too terse: *storing* features in superposition is exponentially efficient, *computing* with them only quadratically. | §4.5 |
| §4.5, on arXiv 2611.17309 | "it took several years for it to become 'too easy'. also note that their move application is very clever, costing 700-900 flops per move, written in Triton + leveraging TB/sec cache. So a B200 can dispatch millions of moves in ms. I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else." | You are right and the draft was wrong to set the two against each other. On "too easy": agreed that it took years; the authors' remark is about what the benchmarks can show today. The paper's own text: search moves "run in Triton kernels with one GPU warp per chain", a move updates only the fields of the cells coupled to the one that changed, and a Sudoku costs a mean of 2.0 × 10⁹ FLOPs. A small, exactly representable energy makes the *learning* trivial; the *solving* is done by a very large number of very cheap moves. The figure of 700–900 FLOPs per move and the B200 are not in the paper's text, which reports an H200; they do not conflict with its per-puzzle total. | §4.5 |
| §4.6, "do not build reentrancy out of nested interpreters" | "No, def never run an iterpreter backwards; but why not build reentrancy out of nested interpreters?" | You can, provided the tower is collapsed before it runs. The warning was about paying for each level at run time: 6–178× per level until staged away, in the published measurements, and 4× from removing one level in this kernel's own closure compiler. Nested interpreters as the meaning of reentrancy are fine. As the way it executes, they need the scheduled lowering you already want. For most of what reentrancy is wanted for, the store needs no second interpreter: one evaluator whose terms can mention terms, spaces, and requirements. | §4.6 |
| §5.2, "a reference to a row of another space" | "yes finally" | — | — |
| §5.4, "different spellings give AU different alignments" | "???" | The sentence was unclear, and the quotation was an auditor's paraphrase. The source says that expressions which agree on the rows may "expose different alignments for the anti-unification mechanism", and that the enumerator "therefore retains their trees". The point: one class has many spellings, and which spelling is handed to anti-unification decides what pattern comes out. Keeping one representative per class can therefore hide a pattern that another spelling would have shown. | §5.4 |
| §6.3, "store's enumerator rather than listed by hand" | (highlight) | Measured in §8.7. Properties generated that way recognise a problem's form at three times chance, and do not pick its operators. | §6.3, §8.7 |
| §6.6 Language | "can nothing be adopted from the other plans and versions of this plan?" | Yes, and the section is rewritten around your October outline. It keeps the like and analogy rows of the mapping in `plan_v2b.md` §7.8, the `like`/`analogy`/`act` query forms named in `plan_v2.tex` without the vectors `plan_v2.md` gave those words, and plan 7's coupling of names to tariffs. The mechanism is the outside review's, after reproduction. | §6.6, §8.8 |
| §10, "We do not advocate such blank-slate learning as a route to AI." | "who is this from?" | The authors of DreamCoder (Ellis and colleagues), about their own run that rediscovered `fold` from first principles in about a year of CPU time. | §10 |

### G.2 Notes on the outside review

| Where | Your note | Answer | Changed |
|:--|:--|:--|:--|
| Its §1.3.1: classes merge "only after evaluating them on S", so transfer "across spaces still requires an explicit normalizer or probe evaluation" | "this is a fundamental limit for compression and needs to be allowed." | Taken as a requirement. §5.9 is new: computation within a space, search across spaces, the three ways to find a map, and what prioritizes the search. The draft's statement that nothing on the store needs graph matching is withdrawn. | §5.9, §7.6, §1.5 |
| Its §1.3.2: "Adding an 8-line monoidal pushforward" | (highlight) | Reproduced. The operator itself is nine lines; with the search around it, 44 to 71. It solves `seq-corr` from the kernel's seven spec rows, 200/200. It does not replace `fold`. | §7.2, §7.3, §8.5, §8.6 |

### G.3 What was taken from the outside review

Its empirical claims were reproduced before use, since none of its code is in the repository (§8.6, §8.8).

*From its first section.*

| The review's point | What was done | Where |
|:--|:--|:--|
| In standard terms the store is a tree automaton, or ground e-graph, indexed by spaces; `plan_v2b.md`'s attributed C-set is its core | adopted, as one sentence | §5.8 |
| What separates this plan from its siblings is extensional against intensional equality | adopted | §5.8, §5.9 |
| Rewriting across spaces is traded away | adopted, and after your note made a requirement | §5.9 |
| Collect under an aggregate unifies `tabulate` with reductions | adopted after reproduction. It does not replace `fold` | §7.2, §7.3, §8.6 |
| Shared holes are equal columns; the instance table is ragged; classes in cells need a product of automata | adopted on the review's argument and the literature; the last point was not run. The draft's sentence on classes in cells is corrected | §5.4 |
| An inverse's guard is the table's uniqueness test and a forward replay | adopted after reproduction | §7.2, §8.6 |
| Its guard for `a div b = c` solved for `b` | not adopted. It is sound but rejects 48 to 78 pairs that have exactly one answer | §8.6 |
| The prices are an oriented metric: symmetric and logarithmic on integers, asymmetric on sequences and code | adopted for the symmetry and the asymmetry. They are a metric in the strict sense only on integers, fields, and tuples | §6.1 |
| No violations of the triangle inequality | not adopted as stated: it holds on small values, and fails on sequences and code once values are large | §6.1, §8.6 |
| A live violation of the prefix-code bound, and one bit per column as the fix | adopted in corrected form. The sums are right; the violation is not live in the main pricing path | §6.2, §8.6, Appendix F |
| Name the pricing metric and the retrieval index apart | adopted | §6 |
| The prototype on the kernel's own spec rows | adopted after reproduction, with four corrections | §8.6 |
| A split must not be accepted ahead of a smaller unsplit term | adopted. It reverses the conclusion the draft drew from its own data | §7.2, §8.5, §8.6 |
| The prototype validates the store, not the general synthesizer | adopted and stated | §8.6 |
| The categorical vocabulary: a fibration over finite sets, an adjoint triple, an enriched metric | not adopted as this document's language. §5.8 records only the automaton and table identifications. An earlier audit said of `plan_v2.tex` that its vocabulary was heavier than its content, and your prompt objected to academic imports; the same caution applies | §5.8 |
| Description length as a shortest path through the store | not adopted. It was not checked, and with shared sub-terms choosing the cheapest derivation is itself NP-hard | — |

*From its second section.*

| The review's point | What was done | Where |
|:--|:--|:--|
| A word is a quotient of values; a verb is the operator's table over its labels, read off probe rows by one group-by; signatures and language are one mechanism (its first proposed change) | adopted after reproduction | §6.3, §6.6, §8.8 |
| The gain: 1.5× to 26.5× in candidates, with zero misses | adopted in corrected form: about 15× in candidates and 1.3× to 4× in time; 0.3% of answers lost at 1,000–3,000 random probes per operator, 11% at 100 | §6.6, §8.8 |
| The tables default "soundly" | not adopted. They are tested knowledge: they may order and filter tentatively, not eliminate | §5.5, §6.6 |
| Tables need no solved tasks, so new library entries are not starved; Naive Bayes over signatures is | adopted. The review's 6.5× for Naive Bayes depends on the order of the operator list, which is not known for its run; used as prices it is far worse than the review says | §6.3, §6.6, §8.8 |
| Ranking by surprise, as part of its headline method | not adopted: it added 3–5% | §8.8 |
| A merged product of quotients, to save memory | not adopted: 8 of 60 tasks lost at 2,000 probes per operator | §8.8 |
| Planning over the tables by shortest paths | not adopted: the bound on remaining steps rarely exceeds one or two, and one test before evaluation gives nearly all the gain | §6.6, §8.8 |
| Choosing quotients by lumpability | adopted as the first selection rule, with the four parts that had to be supplied by hand named | §6.6, §8.8 |
| The weakest guard by comparing bit masks | adopted. It is unique only when some guard in the pool has exactly the law's rows | §6.6, §8.8 |
| Residues modulo small primes, by column, against the memory wall | adopted for pure ring grammars, which is the limit the review itself states | §6.6, §8.4, §8.8 |
| Upgrade X4 to compare types, flat signatures with counts, and tables, including never-used entries (its second proposed change) | adopted, with the reproduction's accounting added: order-averaged baseline, every pass counted, wall time, and answers lost | §11.2 |
| A column of labels that hold on every row, to index the derivation space (its third) | not adopted for now. In an outline of its experiment, replay with no index found all 25 repeats and an index found 9 to 19, depending on its key. Replay's cost grows with the store, so the question stays open | §7.4, §8.8 |
| The literature on synthesis guided by abstract values | checked against the papers and added. The citations exist, and the figures quoted from them are exact. Two corrections: in the synthesizers cited the abstract meaning of each operator is written by hand, except in one that learns it from training problems and hand-supplied operator axioms; and Ruby is one system's implementation language, not a benchmark. One paper, from 1977, could not be fetched | §6.6, Appendix E |
| Its Appendix A, a walk through the second section in plain words | nothing further to adopt: it makes no new claim. Its "safety rule", that a case the probes missed can only loosen the pruning and never discard a real answer, is the claim that did not reproduce | §8.8 |
