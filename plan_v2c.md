# `lisploop` — Plan v2c: one topology–geometry kernel

*Audit of the kernel, its documents, and the literature, and a proposal for a single store. Written 24 November 2026 against commit `15e64c6` (root kernel unchanged since `df33ed1`; `v2/` at `a4e19fa`).*

**How this was made.** Fourteen AI auditors, working in parallel and independently, each took one slice: five read and ran the code, six read the planning trail, three reviewed the literature. A fifteenth built and ran a small prototype of the proposed store. A sixteenth then checked a draft of this document against the reports, the logs, and the code; its 77 findings were applied. Three of the code auditors (data structures, search, laws) were told not to read the earlier v2 plans, so that their view came from the code. Their reports, with file-and-line citations, are in `plan_v2c_audit/` (Appendix F).

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

Geometry is description length. The distance from one column to another is the bits needed to write the second given the first, which the codec already defines per value type. The graph is the factorization of the description; the geometry is the code on each factor. For guiding search, four derived geometries are available in order of evidence: behaviour distance, property signatures, usage counts, and graph proximity. None is trained by gradient descent. Nesting stays in the exact store; one flat signature space indexes it (§6).

The synthesizer has one move: refine a hole with a program construct, and split the requirement the way that construct splits it. Each construct the VM can run is paired with the law that splits a requirement on it. The search's own record is a space like any other (§7).

Each part of the store's core has shipped precedent: shared terms, value vectors with behaviour classes, relational tables, law discovery by collision. The search-literature review's own "most reliable recipe" overlaps this parts list, with one departure noted in §5.8. Three things are this plan's own: spaces with maps as the lifting mechanism, inverses read off an operator's table, and keeping all three graphs in one structure (§5.8).

### 1.4 What a prototype showed

A standalone prototype of the store, 874 lines of Lisp with no kernel code, was run on four questions (§8) **[M]**.

- **Lift.** Fifteen sequence tasks were solved from input/output rows by one fixed procedure with one 12-operator grammar and no skeleton written per function, each scoring 200/200 on held-out examples; 134 of 135 runs over nine example sets. The procedure grants the container forms (`tabulate`, selection, `where`, one guard, `fold`); what is found is the term inside. The tasks include the prototype's versions of three of the four functions the existing kernel does not find at a thousand times its budget (`map-adjacent`, `scan`, `shift-seq`; `best-shift` was not attempted), on the prototype's own example rows. The first-order ones took between 3 and 703,183 candidate columns and under half a second; `map-adjacent` with a function argument took five seconds. None needed recursion.
- **Inverses.** The inverses of `+`, `−`, and `neg` were found from the operators' own tables within 25 candidates; `*` with its guard `b ≠ 0` in about a quarter of a second. Feeding those inverses back made three later searches 60–150× cheaper.
- **Laws.** Commutativity, associativity, the identities, and distributivity were derivable by size 7 in 0.01 s, with no false law once the probe space had 8 rows.
- **Limits.** Measured: nested guard splits overfit; folds to a scalar need a `fold` form, since lifting alone cannot express them; the set of kept laws does not converge. Extrapolated from 90-second runs: a single deep search would exhaust 24 GB in one to eight minutes, and ten hours would reach one or two nodes further than one hour.

### 1.5 Where this plan qualifies your prompt

- **Budget.** Hours are right, but not as one deep search. An hour should be thousands of small bounded problems, re-validation on fresh rows, and ablation (§7.6). By one auditor's model of the published results, cutting a grammar from a hundred primitives to ten is worth more nodes than the step from one second of search to one hour (§4.1).
- **Anti-unification.** Your reading of it as quotienting plus lifting holds as intuition. On the store it comes apart into a shared pattern (the constant columns of an instance space) and a quotient (the class). Taking instances modulo classes is meant to make it robust to equivalent syntax; that is untested (§5.4).
- **Graph isomorphism and e-graphs.** Neither is needed. Shared, ordered terms compare by hash. An e-graph's store is worth having; its saturation is not (§4.3).
- **Flat versus nested.** Not a question of what can be represented. A flat space buys storage economy that a library of a few hundred entries does not need. Keep nesting exact and use one flat space as an index (§6.4).
- **Lifting forms as primitives.** A primitive may encode the shape of a container, never the content of a domain. `tabulate`, `fold`, and `where` are granted on that rule; what goes inside them is found (§7.1).

### 1.6 What is research, not engineering

- A closed loop in which laws, inverses, and abstractions found on the store become the next round's primitives on the same store. Abstraction alone has precedent, and there it roughly doubles solve rates and then plateaus; the full loop has none (§10).
- Learned inverses beyond one operator; guarded laws with guards larger than about four nodes; general recursion with hidden state.
- Algebra from depth-two experiments, over spaces whose rows range over functions (§5.4).
- Learned coordinate spaces, and language. The plan builds a name slot and a count table for language and nothing more (§6.6).

### 1.7 Recommendation

Rewrite, in four stages. About 3,500 lines of the present kernel and its milestone code are worth carrying over: roughly 2,200 as code or as a design, and roughly 1,300 that work through a frame today and need that interface moved. About 750 more are ideas to re-implement (§9). Stage A is the store core plus two experiments: law discovery by class, which is shipped technique, and inverses from tables, which is this plan's own and so far shown only on the prototype. If either fails, the plan is wrong at the root and that is known first (§11). The standing metric is the kernel-found fraction of the library, which is 2.5% today.

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

- **Structure.** The search tree has two or three nodes at every budget. A node expands once, through a fixed list of host-coded proposal generators. The kernel's main recursion skeleton recurses on `(tail Xi)` with every other argument unchanged, and removes `at`, `tail`, `if` and `=` from the child's grammar (`decompose.lisp:341-382`); a second, lockstep form walks two sequences in step. More work buys more leaves under the same two nodes. It cannot buy more structure.
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
- totality facts for variable indices, and guards derived from an operator's own preconditions;
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

*Evidence.* Nesting is not a representability problem. Trees embed exactly in squared-Euclidean space (a textbook result, not re-checked); language models encode hierarchy as orthogonal subspaces; shown a graph in context, a transformer reorganizes its representation toward that graph's spectral embedding **[L]**. The economics are the issue. A shared flat space saves *storage*: m features can be represented in O(log m) neurons. It does not save *computation*: computing m features in superposition needs Ω(√(m log m)) neurons and Ω(m log m) parameters, for a broad class of problems (Adler and Shavit, verified against the paper; these are theorems about neural networks). A library of 10²–10³ entries has no storage pressure. Meanwhile every method that *learns* coordinates needs gradient descent and on the order of 10⁵ examples.

The paper you cited in the margin, arXiv 2611.17309, was fetched and read by two auditors independently. It is a learned pairwise energy trained by pseudolikelihood, with inference by local energy descent, and it supports the first half of your note more than the second: it works because the hypothesis space is tiny (one hand-set value already solves every Sudoku puzzle, and three every maze), not because evaluation is fast. Its authors' own message is that the benchmarks are too easy and that learning latent quantities "remains open".

*Take.* A flat space is the right shape for *retrieval and ranking*, and the wrong place for truth. Use flat, explicit, recomputable feature vectors as an index over the exact store (§6.3). Defer learned coordinates until there is data to learn them from.

### 4.6 "A requirement is a cell of partial information; computation runs both ways"

*Claim.* The propagator view: every operator is a relation among cells, and information flows in whichever direction is known.

*Evidence.* Inverse semantics is shipped technology: the witness functions of FlashMeta are per-operator partial inverses, load-bearing in commercial products. They are also written by hand; learning them is open **[L]**. Running a general interpreter backwards does not scale; its authors say interpretive overhead "makes the relational interpreter approach impractical for most applications", and each extra interpretive level costs 6–178× until staged away **[L]**. In this kernel, pullback is 37 sound lines (§2.1).

*Take.* Keep pullback. Treat an inverse as another orientation of an operator's own table, found by a dependency test and a small search (§5.4, measured in §8). Never run an interpreter backwards, and do not build reentrancy out of nested interpreters.

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
| Anti-unification | stack k terms as k rows of an *instance space*, one column per position. Constant columns are the shared pattern. Varying columns are the parameters | total term size | a definition and k calls |
| Quotient | merge rows (projection), or merge terms (a class) | n | — |
| Partition, guard, conditional | a Boolean column; the sub-space of its true rows | n | `if` |
| Conservation, law | two terms in one class; or a term whose column is unchanged when re-indexed along an endomap | n | a rewrite, an invariant |
| Reorientation | test whether one column is a function of some others; if so, search for a term over those others that denotes it | n, then a small search | a solver |
| Residual | the column `r` with `y = decode(m, r)` for a target `y` and a model `m`. It is a column like any other | n | `decode(m, r)` |
| Tuple | a row is a tuple; a tuple-valued column splits into columns | n | `tuple`, `at` |
| Recursion | an endomap `s` on the space of calls. The function's column re-indexed along `s` is the value of the recursive call | n | a self-call |

Three remarks.

**There is one underlying description.** Lift, split, projection, anti-unification, and recursion all do the same thing: build a space, give it a map to a space you already have, and move columns along the map (re-index one way, collect the other). You said of the earlier six-move list that several were "flavors of the same". On this store they share one description, with different maps **[P]**. The prototype implements it as three short routines, 22 lines, and uses them only for lifts over output and input positions. Its split used a separate index, and the instance, call, and derivation spaces are not built.

**Anti-unification separates into a pattern and a quotient.** You wrote of anti-unification that "really it's a form of quotienting and trivial lifting under substitution". As intuition that holds. On the store the two halves separate: the generalization is the *shared pattern*, the constant columns of the instance space, and the quotient is the merging of terms that denote one column. (One categorical treatment, a single paper the auditor could read only in summary, likewise makes the generalization a product and reserves the quotient for merging.) If cells of the instance space hold classes rather than raw syntax, anti-unification is taken modulo the equivalences the store has observed **[P]**. The trail measured why that could matter: normalizing by laws first took one pattern from five holes to two. Two cautions. In the one published system that anti-unifies over classes, the cost is quadratic in the size of the corpus. And the trail once kept alternative spellings on purpose, because "different spellings give AU different alignments".

**Depth-two experiments are spaces whose cells hold terms.** A space whose rows range over `(f, g, xs)`, with `f` and `g` drawn from the classes of some smaller space, lets `(map f (map g xs))` and `(map (compose f g) xs)` fall into one class. A cell that holds a function is a reference to a class elsewhere, so two such cells are equal when the functions behave alike. This is the "folded and recursively nested" structure you describe: nesting is a cell that points into another space. It is untested, and it is one of the places where the literature offers no precedent (§10) **[P]**.

### 5.5 What a class means, and why sampled knowledge can prune

Plan 8 recorded that sampled evidence "can propose and never eliminates", and the audit confirmed the consequence: on the integers, nothing the kernel learns ever reduces the search (§2.4). That constraint is real but it is narrower than it has been treated.

A class is always a class *on a space*. Three grades:

- **Observed**: the same column on this space. This is exact, not sampled, for any question about this space. Two terms in one class are interchangeable as sub-terms of any program that is judged on these rows, so enumeration can keep one and build only from it. No law, proof, or certificate is involved. The one condition is that the sub-term is evaluated on that space: a term under a `tabulate`, or inside a recursive body, is evaluated on the position space or the call space, and its class is taken there.
- **Tested**: also the same column on several fresh spaces with boundary values. Good for anything where a mistake costs time or a missed answer, never truth: ordering enumeration, normalizing before anti-unification, proposing a decomposition.
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

Each piece has shipped precedent: hash-consed terms; value vectors with observational-equivalence classes, the backbone of every bottom-up enumerative synthesizer; relational tables with unnest and group-by; law discovery by collision, as in QuickSpec. The search-literature review's own recommended recipe, assembled only from shipped or independently replicated parts, overlaps this list (lit-search report, section B).

It differs in one respect that matters. The published recipe's decisive step is pruning the term space with laws already found; dedupe by behaviour comes second. This plan leans on classes for pruning and keeps laws by use (§8.5). The reason is the kernel's own measurement that rewriting during search cost more than it saved (§2.4), and X1 should measure what the choice costs.

Three things are this plan's own and are marked as such throughout:

1. using *spaces with maps* as the lifting mechanism inside a synthesizer (nearest precedents: deduction through `map` and `fold` in λ², and array languages);
2. finding inverses by a dependency test on an operator's own table followed by a small search. Inverses do appear in the literature, as laws of the form g(f(x)) = x found by testing and as structural inversion from a table of primitive inverses. What has no precedent is a synthesizer learning the inverse rules it then uses; those are hand-written in every synthesizer the review checked;
3. keeping all three graphs in one structure so the search can read its own record.

§8 measures the first two on a prototype.
## 6. Geometry

You consider the geometry question open, and it is. This section says what the evidence supports now, what it does not, and how the store leaves room for more. It has three jobs to cover: pricing residuals, guiding search, and language.

### 6.1 One definition: distance is description length

In a space, the distance from column `u` to column `v` is the number of bits needed to write `v` when `u` is known.

The kernel already has this. Its codec assigns every value a prefix code, and its correction rules price a value given a prediction: for integers, a universal code of the difference, so roughly its logarithm; for Booleans, which rows differ; for sequences, a correction per position and a change of length; for code, an anti-unification edit. These per-type codes are the bedrock "these things are close". They are not symmetric, and should not be.

So the tariff and the metric are one object. Plan 7 said the same of decoders: "A metric and a decoder shell are two views of one correction code."

### 6.2 Pricing residuals

Start from the counting identity in plan 2: H(X) = H(f(X)) + E log|fiber|. Running `f` forward destroys the bits that say which member of the fiber you started from. Running it backward means supplying them.

Four rules follow. They are standard coding theory, confirmed by the literature review; the previous plans stated the first three but gave no procedure for using them.

1. **A verified bijection transfers code lengths for free.** If two spaces or two value types are related by a map with a checked inverse, a residual costs the same on either side.
2. **A many-to-one map owes the fiber.** Pricing on the coarse side costs an extra log₂|fiber| bits per row to name the member, or the bits of a term that predicts it.
3. **A new latent column is paid for adaptively.** Cluster labels, chosen indices, and the like are coded cell by cell, each using the counts of the cells before it. This is a valid code because a decoder can rebuild the same counts. It is also what makes count-based or nearest-neighbour predictors safe to use for pricing.
4. **The graph gives the coding order.** Code the columns in dependency order. A column that a term derives from earlier columns costs only the term. A column no term derives is *free* and costs its code. The total is the description length.

Rule 4 is the precise sense in which topology and geometry interlock: **the graph is the factorization of the description, and the geometry is the code on each factor.** A move is good when it turns an expensive free column into a term plus a cheaper free column.

**Is there something better than pricing in the ambient space?** You asked this directly. The theory says no induced space can price a residual below its ambient cost, except through rule 1 or by paying rule 2. What an induced space can do is make the residual smaller or more regular, so the same ambient code is shorter; and counts can replace a fixed code with an adaptive one. So ambient pricing is not what made residuals clunky. Three implementation facts did (§2.7):

- eight unrelated representations of a residual, where the store has one: a residual is a column;
- a metric that cannot depend on the row, where a column's code can depend on any earlier column;
- adding program bits sized at the root to residual bits sized in a child space. The fix is to move the child's residual back along the map and price each root row once.

One caution from the trail belongs here: small residual magnitude is not structure. In plan 1's measurement, from a scratch script that was never committed, the correct lift ranked 66th of 2,661 by residual size. Residual size should rank proposals only together with regularity, meaning whether the residual column itself falls in a class with a small term.

### 6.3 Guiding search

The control problem with the most leverage is choosing a small grammar for each problem (§4.1). Published results agree: five extra helper functions took one recursion synthesizer from 0.07 s to 128 s **[L]**; in this kernel, offering library functions as plain operators never helped and once cost 6.6× (§2.5).

Four geometries can do that job. All are computed from the store, none is trained by gradient descent, and all only rank or propose. They are listed in order of evidence.

1. **Behaviour.** A column is already a vector, one coordinate per row. The distance from a candidate's column to the target says how nearly it fits. A near miss proposes a split (find a guard for the rows that disagree) or a residual. A library function whose column on these inputs is near the target proposes itself. Reported gains for distance-on-behaviour synthesis are 56–664× in search-space size in one study, whose metric was supplied by an expert and whose figures come from a 2018 draft, and more than 10× over the prior state of the art in another **[L]**. The known weakness is that program spaces are rugged, so this ranks; it never prunes.
2. **Signatures.** A signature is a fixed-length vector of cheap yes/no properties of a problem: output the same length as an input; output elements a subset of an input's; output sorted; target constant along some map. In one published comparison, 45 hand-written properties of this kind beat learned embeddings as the input to a small trained network **[L]**. That is evidence for the features, not for using them without training. Here the properties would be small Boolean terms over the problem's own columns, generated by the store's enumerator rather than listed by hand **[P]**; today's descriptors are a fixed menu of ten, written in kernel source. **The signature space is the flat space.** Every problem from every space maps into it, and nearest neighbours among past problems are found there.
3. **Counts.** How often each operator, each move, and each library entry appeared in an accepted solution, given the parent operator and given the signature. Counts become code lengths. They order enumeration, they select the ten or so primitives in scope, and they set the price of an operator's name, which today is an accident of list order (§2.7). The published precedent reweights a grammar during search with no training data, within a single task; its gain is large against a weak baseline and modest against a strong one **[L]**. Counts across tasks, as proposed here, go beyond it. Naive Bayes over signature bits, with backoff to coarser signatures, is the simplest form that has shipped elsewhere. An earlier audit of this project classed it as unproven at a library of under a hundred entries, and X4 is the test.
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

### 6.6 Language

This is the least supported part of the ambition, and the plan builds almost nothing for it.

The one approach with evidence on small data treats words as labels for program fragments, aligned by co-occurrence counts. In its published form it raised solve rates in one domain from 42.6% to 82.0%, with gains persisting when no language was given at test time **[L, one research lineage]**. That system sits on a neural search component, and with human rather than synthetic descriptions its best result in that domain fell from 98.2% to 58.6%. Words as vector offsets are documented as unreliable; words as tensors have been shown only at toy scale.

Read against your three word types:

- a **'like'** word is a nearest-neighbour query in behaviour or signature distance;
- an **'analogy'** word is a verified map between two spaces, applied. It is not a vector offset;
- an **'action'** word names a move: make a space, lift, split.

All three already exist as store objects, which is the argument for the store, not for a language component. The only affordance to build now is a name slot and a co-occurrence table on every library entry, move, and signature property. Anything further should wait until the kernel has a library it found itself.

### 6.7 What remains open

- Whether behaviour distance ranks well enough in practice to pay for computing it. The existing metric decoder taxed every search of its type (§2.7).
- Whether store-generated signatures separate problems as well as hand-written ones.
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
| `(fold ?init (λ acc x. ?step) xs)` | does not split unless intermediate values are observed (§7.3); otherwise `?step` is enumerated by class | — |
| a self-call `(self ?s)` inside a recursive body | `?s` is any term whose value is a row of the call space | the call space, with an endomap |
| `(decode ?m ?r)` | `?m` need only be near; `?r` is solved from `?m` and the target | — |

Each row pairs a construct the VM can run with the law that splits a requirement on it. This is what the previous plan was reaching for with a "symmetric instruction set", stated as one table.

The selection row needs one more granted piece than the others. To recover which input positions survive, the output has to be aligned to the input as a subsequence. That alignment is the preimage of selection, in the way the index sets are the preimage of `gather`. An earlier audit pass rejected a subsequence propagator as specific to `filter` (Appendix D), and the prototype uses one (§8.1). The case for it is the rule of §7.1: it concerns the container, not any domain. It should be judged on that.

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
4. **Folds to a scalar** (`sum`, `foldl`): the intermediate accumulator is not observed, so the requirement on the step function does not split. Two routes:
   - enumerate step functions by class over the leaves `acc` and `x`, each candidate costing one fold per row (§8 measures this);
   - notice when the rows themselves contain the intermediates. If one row's input is a prefix or a tail of another's, that relation is an endomap on the space of examples, and the accumulator column is observed after all. The bootstrap's "trace-complete rows" are this, supplied by hand as a convention. On the store it is a property the data either has or lacks, and a group-by detects it.
5. **General recursion**: the calls a function makes are rows of a call space, and the recursive call is an endomap on it. The argument of the self-call is one more hole. Candidates are ranked by how many rows land on a known row and by whether some measure decreases; the kernel's termination check (about 50 portable lines) imports for the second.

Case 5 is research with replicated precedent, not engineering: published recursion synthesizers need examples closed under the recursive call, or angelic execution to relax that **[L]**. By inspection, cases 1–4 are the shapes of the functions in the current library **[P]**. The prototype tested first-order instances and two function-argument forms (§8.1). It did not test `foldl` with a function argument, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`, or the higher-order `map`, `foldr`, and `filter`. `best-shift` plausibly needs two lifts, which were not tested either.

### 7.4 Reflection: the search as a space

Each problem posed is a row of the **derivation space**. Columns: parent problem, construct chosen, signature, context size, work spent, classes created, outcome, bits of the best answer.

Its readers, in order of evidence:

1. **Memo.** Two problems with the same space, the same requirement class, and the same context are one problem. This replaces the present reuse key, a sorted printed string, and it holds across branches and across jobs. Your margin note on "Nothing persists across branches or jobs" was "yeah that's a big problem"; this is the fix.
2. **Counts** (§6.3).
3. **Attribution by ablation.** Re-run a held-out set with one learned thing removed, and keep only what pays. The literature's warning is specific: one planner kept 4–6% of its learned rules and ran 65% slower without that validation; one lemma library showed a single reuse among 20,000 entries **[L]**. Stage 0's ablation harness imports for this.
4. **Explanation-based generalization.** On a shared term graph, "what did the winning derivation actually read" is a walk over edges. Whatever it did not read can be made a variable. Plans 1–3 specified this and never built it.

Because the derivation space is a space, the synthesizer can be pointed at it: find a term that predicts `outcome` from the signature columns. The existing `yield-gate` experiment proves that plumbing. It is not on the critical path, and the one learned predictor that exists today learned a constant (§2.6).

The audit's inventory gives this a concrete target (§2.3). Of the 158 hard-coded decisions, the 30 dedupe and memo guards become the class table and the problem memo; the 30 ordering rules become counts; the 52 caps become budget accounts that defer rather than drop; the 51 pieces of domain knowledge become library entries or are deleted. That mapping is a goal to check item by item, not a result **[P]**.

### 7.5 Discovery: an agenda the kernel fills itself

The audit found that nothing in the kernel initiates discovery (§2.4). On the store the questions can be listed mechanically. For each library entry `f`, starting from the primitives:

- **Laws.** Classes on a standard probe space over `f` and the operators in scope, to a size bound.
- **Inverses.** Per argument: the dependency test; a guard for the rows where it fails; a small search for the term.
- **Definedness.** A guard for the rows where `f` returns an error. The kernel's milestone code already does this for arithmetic (§2.4).
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

No operation on the store needs subgraph isomorphism, and none saturates.

| Operation | Cost |
|:--|:--|
| Intern a term | constant, by hash |
| Evaluate one operator over a space of n rows | n |
| Find a column's class | n, by hash |
| Dependency test (is this column a function of those?) | n, by hash |
| Unnest, re-index, collect | number of cells touched |
| Anti-unify k plain terms | their total size. Over classes, quadratic in the corpus in the one published system |
| Conditional laws under g candidate guards over c classes | g × c × n, with guards limited to about four nodes in published systems |
| Enumerate by class to size s | exponential in s: ×3–7 per unit of size after dedupe, against ×9–14 for raw syntax (§8.4) |
| Compare laws up to renaming of variables | brute force over at most 5 variables |

The only exponential is leaf enumeration, and its exponent is the reason for everything else in this section. With behaviour dedupe each tenfold of work buys one to two nodes (§2.3, §8.4). Deep single searches also meet memory before time: extrapolating from 90-second runs, the prototype would exhaust 24 GB within one to eight minutes of one deep search, and ten hours would reach one or two nodes further than one hour (§8.4).

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

- **Nested guard splits overfit.** Allowed at every size, they return case analyses whose guards fit the training rows by accident: rotate-left on 3 of 9 example sets, map-adjacent with `f` on 6 of 9. The prototype therefore accepts a single guard at first fit and tries nested splits only when the budget is spent. Requiring a split to be size-minimal changed no outcome and cost 35–1,100× more candidates. A split needs an acceptance test stronger than "fits the rows"; §8.5 says what the design takes from this.
- **A function argument is only as determined as its examples.** The one miss in 135 is an example set in which the only non-commutative operator appears on one-element sequences, so nothing fixes the argument order. This is the kernel's `foldl` impostor again, and the store's check for it is the one in §5.5.
- **Folds to a scalar are outside change of space**, as §7.3 expected: `sum`, alternating sum, and a Horner evaluation all fail under lifting alone. With a `fold` form whose step is enumerated by class, they are found after 21, 51, and 157 fold programs. Alternating sum needs a right fold.
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

- **Memory is the wall, not time.** By that extrapolation, the sizes an hour could reach by time alone would need about 0.2 TB, and ten hours 1.2–2.4 TB. Two of the prototype's own runs did die at a 10 GB heap.
- **Dedupe is worth less on rich arithmetic than on polynomials or on the kernel's list grammars.** Once `div`, `mod`, `max`, and `min` are in, 30–40% of candidates are genuinely new behaviours on 32 random rows. The 99% duplicate rate of §2.3 was on few rows and list-heavy grammars. Both are real; the gain depends on the grammar and the rows.
- **Ten hours buys one or two more nodes than one hour.** This is the same logarithm as §2.3, on a different engine.

The kernel's measured candidate rate is 118–248 thousand per second (empirical report, §2), so the prototype evaluates 8–17 times as many candidates per second, on four to five times as many rows. The prototype does no metering and no bit accounting, so read that as an upper bound on what evaluation by column could give, not as a prediction.

### 8.5 What the prototype changes in the plan

1. **The lift claim stands, for position-wise, selective, and observed-recurrence functions.** It has not been tested on the kernel's own short spec rows, on fewer than 12 examples, or on tasks that need two lifts. X3 does that.
2. **Split needs a stricter acceptance rule than fit.** The store offers three, in increasing cost: the guard must pay for itself in description length; the two branches must not fall into one class on a wider probe space; and a nested split must survive rows held back from the search. This is added to X3's gate.
3. **`fold` belongs in the refinement table** (§7.2), with its step enumerated by class. That was expected and is now measured.
4. **Laws are kept by use, not by completeness.** Classes do the pruning. A law earns a place in the library only when something reads it: to normalize before anti-unification, to carry a class to a new space, or to certify. The small-size basis, about 59 laws here, is kept; anything larger is derived on demand.
5. **Hours go to breadth.** By extrapolation, the memory wall is reached in minutes on any one deep search. §7.6 already says this; the prototype's runs are consistent with it.
6. **Dependency experiments need designed rows.** The boundary artifact is a concrete instance of why experiment choice has to be a mechanism.
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
| 1 | Lifting by a change of space works on the prototype's rows (§8.1) and not on the kernel's own short spec rows, or on tasks needing two lifts | the 16-spec ladder without whitelist, schema, or trace-shaped rows (§11, X3) |
| 2 | Inverses from tables stop at one-operator inverses. The audit's own run found the solver search "has a one-operator answer" in every case | compose known inverses through a term; test on `a*x + b = c` and on `x + x = c`, which the present kernel cannot solve |
| 3 | Classes on a small probe space merge terms that are not equal, and false laws accumulate | count laws that fail on fresh rows. On the prototype: none at 8 or more probe rows, 199 at 3 rows (§8.3) |
| 4 | Counts over tens of solved problems carry no signal. The one existing learned predictor learned a constant | the guidance ablation (X4), before building any of §6.3 beyond types |
| 5 | The agenda fills the library with true, useless entries. One published law finder at 33 functions "generate[s] too many laws"; another's authors say more depth "does not lead to many useful lemmas" | utility accounting by ablation on every entry (X5). The prototype's kept-law set already grows ×2.8 per unit of size (§8.3) |
| 6 | The rewrite grows. Three successive plans each promised a smaller kernel and delivered a larger one | a complexity-score gate per stage (your margin note: complexity scores are "less gameable" than line counts), and the ported test contracts |
| 7 | Deep searches exhaust memory before time | bank memory bounded per problem account; measure retained classes per hour |
| 8 | "The store's operations are programs" turns out elegant and unprofitable. The review found reflection paid off only in cheap, measured forms: memoization, dependency graphs, partial evaluation, bandit allocation | keep it off the critical path; X8 is last |
| 9 | Geometry costs more than it saves, as the metric decoder did | X4 again; the per-column codes are needed regardless, the rest is optional |
| 10 | Anti-unification over few instances over-generalizes | the existing description-length gate; negative controls already in `tests/theories.lisp` |

**No convincing precedent anywhere**, per the three literature reviews. The plan depends on the first three. The last is the plan itself. The others are deferred or avoided by design.

- A synthesizer learning the inverse rules it then uses. Hand-written in every synthesizer checked. *Depended on, in Stage A; shown for single operators on the prototype (§8.2).*
- A closed loop in which discovered laws, inverses, and abstractions become the next round's primitives on the same store. Abstraction alone has precedent, and plateaus. *Depended on; X5 is the test.*
- Algebra from depth-two experiments, and conditional equalities with learned guards kept in one store. Published guard search stops at about four nodes. *Depended on, in Stage D (X6) and for guarded laws (§5.5).*
- A self-generated curriculum. *Not depended on: tasks still come from external data.*
- A search policy learned by the synthesizer about itself that keeps improving. *Not depended on.*
- Higher-order functions from first-order primitives in hours. The one precedent used about 7,700 CPU-hours. *Avoided: the lifting forms are granted (§7.1), and `:map`/`:foldr` already emerge by anti-unification.*
- Recognizers of the autocorrelation kind invented from data. *Not depended on.*
- Termination guards learned from timeouts. *Deferred (§7.5).*
- Coordinate spaces created from few samples without gradient descent; words as geometric modifiers. *Not depended on (§6.4, §6.6).*
- A unified topology–geometry kernel. Nothing attempts it, and this plan is such an attempt. The working pieces elsewhere are value vectors and hash tables, which §5 uses, and rewrite systems, e-graphs, and decision trees, which it does not.

One cautionary sentence from the authors of the best-known library learner is worth keeping in view: "We do not advocate such blank-slate learning as a route to AI."

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

### 11.2 Next, in order

Each experiment has a gate fixed in advance. The standing metric for all of them is the **kernel-found fraction**: the share of library bits produced by search with no operator whitelist, no recursion schema, no trace-shaped rows, and no hand-written entry. Today it is 2.5%.

- **X1. Classes.** Build the store core (spaces, columns, hash-consed terms, classes, columnar evaluation) and run law discovery on it. *Gate:* the same 187 equations on GF(3) as the present bucket engine, plus distributivity; at least 10× less work than v1's enumerator at the same bound; retained memory proportional to classes, not trees. Also measure what pruning by already-found laws would add on top of classes (§5.8).
- **X2. Reorientation.** Find the eight arithmetic solvers and their guards from operator tables alone: no spec rows, no witness language beyond the operators in scope. *Gate:* the same witnesses and guards the milestone code finds, including the unknown-divisor solver and the integer divisibility guard, neither of which the prototype produced. The two composite cases in risk 2 are reported, not gated.
- **X3. Lift.** Run the 16-spec ladder with the full grammar, no schemas, and ordinary input/output rows. *Gate:* at least 14 of 16 held-out-sound (today 8–10); nothing returned that fits the rows and fails held-out; `foldl` either solved or reported as underdetermined; no guard split accepted that fails the rule of §8.5.
- **X4. Does guidance pay?** On X3's tasks with 30 or more distractor primitives in scope, compare no guidance, types only, and signatures with counts. *Gate:* at least 3× lower median work on held-out tasks, or §6.3 is not built further.
- **X5. Compounding over hours.** Run the agenda of §7.5 for one hour and for ten, from the primitives and the task data only. Report entries found per hour by kind, held-out tasks solved before and after, and an ablation of every entry. *Gate:* the function set of today's library recovered with zero hand-written entries, and later tasks measurably cheaper than earlier ones.
- **X6. Depth two.** Laws over spaces whose rows range over functions (map fusion; fold over map); anti-unification over accepted solutions on the instance space. *Gate:* `:map` re-emerges with a positive gain, as it does now; at least one two-function law is found and survives fresh rows.
- **X7. Reflection.** Counts and the problem memo from the derivation space, each under ablation. *Gate:* a measured reduction in work on problems not used to collect the counts.
- **X8. Self-description.** Write the store's own operations as VM programs and pose one of them as a synthesis task. *Gate:* none; this is exploratory.

### 11.3 Stages

| Stage | Contains | Ends when |
|:--|:--|:--|
| A | Store core; imported VM, codec, evidence, enumerator, certification; ported test contracts | X1 and X2 pass |
| B | Requirements with holes; the refinement table of §7.2; spaces with maps | X3 passes |
| C | The agenda; utility accounting; types-only guidance, then X4 decides the rest | X5 passes |
| D | Depth-two spaces; the derivation space and its readers | X6 and X7 reported |

Stage A is the smallest piece that tests the central claim. X1 is shipped technique throughout. X2 is this plan's own mechanism, shown so far only on the prototype and only for single operators. If X1 or X2 fails, the plan is wrong at the root and that is known within the first stage. Stage B rests on the plan's own lifting mechanism, shown so far on the prototype's rows. The larger research risk sits in X5 and X6.

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
| "we'd need an efficient graph isomorphism test (not for AU of course), or e-graphs" | Neither. Rooted, ordered, shared terms are compared by hash. Laws are compared up to renaming by brute force over at most five variables. The e-graph's store is useful; its saturation is not. | §4.3, §7.6 |
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
| Words as program fragments with count alignment (LAPS) | one lineage, on a neural search component | 42.6% → 82.0% in one domain; weaker with human descriptions | the only language affordance |
| Reflection that compounds (EURISKO) | unreproduced | its author credited the representation | not depended on |

Verification gaps the auditors declared: three of four sub-searches on 2025–26 work ran out of quota, so "none found" for learned inverses and learned termination guards is a weak negative; some figures exist only in plots; all line-count estimates for minimal implementations are the auditors' own.

## Appendix F. Audit reports, and housekeeping

**Reports.** Fifteen reports stand behind this document, about 174,000 words, each with file-and-line citations and its own list of what it could not determine. A sixteenth, `factcheck.md`, is an independent check of a draft of this document against the others, the logs, and the code. It found 10 factual errors, 19 over-statements, and 48 smaller points; all were applied. It also tabulates where the reports disagree with one another (throughput, candidate rate, a few line counts) and which figure this document uses. They are copied to `plan_v2c_audit/` beside this file, because the session's scratch directory is not durable.

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
| `factcheck.md` | independent check of a draft of this document |

**Things found along the way that are not about the design.**

- The root kernel test suite fails on a clean checkout: root has no tracked `library/`, and `lifting`, `metrics`, `structural`, `invariants`, and `theories` need it. `make bootstrap` first, or track the generated files as `v2/` does.
- Five documents cited by the trail were never in the repository on any branch: `plan7-recursion2.md`, `audit-review.txt`, `plan8-2.md`, `plan-let.md`, and `plan_v2_annotated.pdf`.
- `architecture2.md` was stale on the day it was committed and has drifted further (27 primitives, not 26; 14 kinds, not 11; several named functions are gone).
- `v2/package.lisp:66-69` exports about ten symbols that are defined nowhere.
- In `v2/`, `(tabulate n F)` with `F` a code variable fails an assertion at construction (`v2/ast.lisp:1096` against `:673`).
- One defect in the Stage 0 harness, seen twice: a failed synthesis leaves its oracle stub defined, so later specs lose a prerequisite, and the `argmax-corr` "FAIL" is the resulting commit error after a correct search. With that repaired, and a clean library for each spec, one auditor's recount of the four regimes is 16, 10, 11, and 9 of 16, not 16, 9, 9, and 8. This document keeps the harness's own figure of 8 as the baseline in §2.3 and X3, because the budget ladder was run against it.
- Evidence soft spots: one milestone path attests sampled integer uniqueness as `:derived`; arithmetic solvers for `*` and `/` carry no certificate, only a hand-set flag.
- `body-size` is documented as constant-time and is linear.
