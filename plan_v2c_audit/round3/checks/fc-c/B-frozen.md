### 2.4 Laws and algebra: a sound generic core, steered by hand

The generic core of algebra discovery is about 550 lines, and it works **[C]**. It enumerates every expression up to a bit bound and runs each one on every row of a grid that covers a whole finite field. It then groups the expressions by their vector of results, and reads each group as a set of equations.

Everything around that core is supplied by the bootstrap script, `bootstrap/build-batteries.lisp`. The script defines four discovery jobs. For each job it fixes the finite field, the number of variables, the list of operators, the bounds, and the budget (20,000–80,000 work units). A host function, `law-operator-fact` (`consolidate.lisp:709-735`), then filters what the jobs find. It keeps an equation only if it has one of three shapes: commutativity, associativity, or identity. Together the four jobs propose 187 equations. All 187 are true on every input in GF(3), the field of the integers modulo 3. Only 14 pass the filter **[M]**.

- **Distributivity is missing for three reasons, none of them the engine.** No job contains both `+` and `*` with three variables. The shape filter has no case for two operators. And the budget that the algebra battery gives a job of that size is about 85 times too small. (The script builds the library as eight *batteries*, each a file of library entries; the algebra battery is the one that holds the laws.) Asked directly, the existing engine puts `a*(b+c)` and `a*b+a*c` in one group in under a second **[M]**.
- **On the integers, nothing learned ever prunes.** A law may be used as a rewrite only when its evidence is exhaustive, derived, or a trusted axiom. Integer laws can only be sampled. So the set of rewrites on the integers is exactly the four hand-written axioms **[M]**.
- **Where laws are wired into search, they cost more than they save.** On one finite-field test problem, the search took 182,000 work units with no laws, 741,000 with one law switched on, and 70.2 million with 80 laws. The results were identical in all three runs **[M]**. The documents' own diagnosis from October still holds: learned knowledge produced "cheaper requirement checks, rather than fewer enumerated candidates" **[D]**.
- **The library's 14 kinds of entry are one record with different labels.** The knowledge library files each entry under one of 14 kinds, such as `:law` or `:solver`. In the code all 14 are the same structure, and the kind is only a tag on it. A `:solver`, for example, is a law together with a choice of which of the law's variables is the unknown. The code builds that law in order to validate the solver. Six of the 14 kinds have no entry in the library. Entries are linked by typed edges, each from one entry to other entries or to function names. About 30 types of edge are written, and only about 10 are ever read **[C]**.
- **Every step that turns a discovered law into something the search can use is a hand-written recognizer of particular shapes.** There are four such steps **[C]**. A law becomes an operator fact (commutativity, associativity, or identity) only if it has one of 3 shapes. A law becomes a solver only if it has 1 shape. When the tested laws of an operator make it associative with an identity on both sides (the code calls this set of laws a *star*), a third step records a *fold motif*: the law that `foldr` and `foldl` give the same value when their step is such an operator. It recognizes only that one fold signature and that one star. The fourth step turns a solver for an operator on single elements into a solver for the same operator mapped over a sequence. It recognizes only functions shaped like `map`, with a step applied element by element.
- **Guards are already found the way you describe.** The rows where two expressions both return a value and agree become a Boolean target, and a guard program is searched to fit it. There, an error raised by the VM counts as an outcome like any value. It works, within a language of guards that the caller supplies **[C]**.
- **Nothing in the kernel initiates discovery.** Every discovery entry point is called only from tests or from the bootstrap script **[C]**.
- **The kernel has one test of dependency, and only the test suite reaches it.** `target-sensitive-p` (`laws.lisp:892-929`) checks whether an expression depends on one input. It swaps that input for up to four other values while the other inputs stay fixed. Its only caller is `orient-conserved-quantity` (`laws.lisp:948`), and that function is called only from the tests (`tests/topology.lisp`) **[C]**.

### 2.5 The library is mostly authored

The bootstrap writes 61 library entries that the search can use, beside 31 `:spec` entries that only hold example rows. To make them it runs 19 synthesis jobs: one for each of the 16 functions it synthesizes, which are the 16 specs of §2.3, and three more that find two guards and one solver. Ten of the 16 functions are saved in the library with their specs. The other six are *seed functions*, from which anti-unification derives `:map` and `:foldr` (below). Provenance of the 61 entries, recomputed from the build script **[M]**:

| How the entry came to exist | Entries | Share of bits |
|:--|--:|--:|
| Search with a generic grammar | 8 | 2.5% |
| Search with an author-chosen operator whitelist | 16 | 13.5% |
| Search steered by a hand-written recursion schema | 7 | 13.0% |
| Generic derivation (anti-unification, retyping) | 3 | 5.8% |
| Stamped by a single-purpose host template | 9 | 6.1% |
| Hand-authored expression | 18 | 59.1% |

Further:

- The eight entries found by generic search are all small. Each is the *answer term* of an arithmetic solver: the expression that computes the unknown argument from the known ones (the kernel's code calls it a witness). Each has three atoms. An *atom* is one symbol or number of the printed expression: an operator, a variable, or a literal, which counts as two (its quote mark and its value). Across all 19 synthesis jobs of the bootstrap, 19% of the bits of the answers were found by enumeration at a leaf of the search tree. The rest is decoder skeleton (§2.1), which a proposal generator supplied. The largest expression that enumeration produced anywhere has 8 atoms.
- For 9 of the 10 saved functions, the whitelist equals the set of operators that the answer uses.
- Three specs (`foldl`, `scan`, `best-shift`) need rows that are the execution trace of the intended program, including its intermediate accumulator states.
- There was an answer key. Before the bootstrap existed, hand-written files `library/*.lisp` (commit `849013a`) defined 21 of these entries. The bootstrap script re-derives 20 of the 21 in an equivalent form.

Against that, two results go the other way and matter for the design:

- **`:map` and `:foldr` come out of the kernel's own anti-unification**, the operation that finds the most specific pattern that several expressions share, with holes where they differ. It was run over the six seed functions: three that map a list and three that reduce one. Both patterns still emerge with the full grammar and no schemas, at 2.4× the work **[M]**. Two qualifications apply. First, `:foldr` saves nothing: once the cost of giving it a name is paid, its measured gain in description length is zero bits. Anti-unification compares only functions that have the same type signature, and the seeds come three to a signature. With only two seed functions per type signature, `:foldr` is not accepted at all. Second, the kernel finds the two patterns and does not name them. The names `:map` and `:foldr` are supplied by the script.
- **On some tasks the library makes later problems cheaper, but only when it is used for lifting.** Used for lifting means that the kernel proposes a library function that takes a function argument, such as `:map`, `:scan` or `:foldl`, as the outer part of the answer, and then searches only for that argument (§2.1). The test was 8 held-out tasks **[M]**. With lifting through library entries, 3 of them were solved in 25,000–42,000 work units. The kernel alone does not solve those 3 in 35 million. One more task became 3.2× cheaper. Three or four others became 1.7–3× more expensive: the table of the bootstrap-reflection report shows four, and its summary counts three. The other way to use the library is to offer its functions as plain operators, which is what the bootstrap does. That never helped. In a separate experiment, with stand-in functions whose bodies were dummies, it made search 6.6× more expensive.

### 2.6 Reflection is plumbing without a reader

*Reflection* means the kernel reading the record of its own search and acting on it. The plumbing for it exists. During a job the search emits *messages*, each a short record of one event, such as a sub-problem being prepared, a candidate being found or rejected, a conflict, or a search exhausting its bound. `messages.lisp` (128 lines) turns a job's messages into an ordinary frame. But nothing reads that frame except a test and an offline experiment **[C]**. Within a job, no decision reads the messages or the trace, which is the job's log of each turn of its scheduler.

One older loop exists in the code, though no production path calls it. It condenses search traces into a predictor, which adds a correction, clamped to a fixed range, to the priority of each sub-problem. Run on the kernel's own curriculum of 16 specs, it learns the constant 0 and changes work by +0.02%. The cause is concrete. Of its 42 training labels, 40 sit at the limit of the clamp, and the jobs, with one to five sub-problems each, are too small to reorder **[M]**.

An ablation shows what a search trace is good for **[M]**. `plan_v2b.md` claimed that everything learned from a trace could be removed with no change in later work. That is not quite right. A *nogood* records that one choice of decomposition merged rows that need different outputs, so that the same choice can be refused later. One group of things learned from traces, the nogoods and the features learned with them to tell such rows apart, saves 2,332 work units on the task `add-len`, out of the 40,155 that the task takes without them. But it does so only when the same task is run again. Nothing learned from a trace helped on a different task. What does carry over to other tasks is the abstracted functions.

### 2.7 Geometry as built

Geometry today is one number: bits.

- A *residual* is the information still needed to reconstruct a target after a model has accounted for part of it. Residuals have eight unrelated representations in the code, from a correction that turns a predicted value into the wanted one, to rows held in reserve **[C]**. The core-repr report (§1.4) lists all eight, with file and line.
- The built-in distance is a fixed rule for each value type. Two sequences are compared only element by element, at the same positions (`frame.lisp:1533`).
- A frame can carry a metric of its own, which is an expression over two values. By its own documentation that metric cannot depend on the row. When the frame is pulled back, the metric can be carried over to the new frame in only four cases (`frame.lisp:508-518`) **[C]**: when the decoder is the identity; when the decoder is an `if` that passes the child through on one branch; when the decoder reads nothing but the child, and the metric composed with it can be proved to return a value on every input; and when the child has the target's type and the metric survives a replay on at most 3 rows and 3 values.
- A sub-problem's score is the sum of two numbers that are measured in different places. The bits of the program are measured at the root problem. The bits of the residual are measured in the child problem's own space. So pricing in the original, or ambient, space and pricing in a derived, or induced, space are already mixed in one score **[C]**. Plan 7 stated this rule and called the price "one step deep" (`plan7/plan7.md` L437); the code is `synthesize.lisp:447-457`.
- The price of naming an operator is an accident of its position in the list of primitives: `:lookup` and `:gather` cost 4 name bits, `:at` and `:cons` 9, `:code-eval` and `:mod` 12 **[C]**.
- The kernel's price list for work charges quadratic cost for operations that are not quadratic in the host. A recursive sum over a list of n elements is charged about 7.5·n² work units. Two `at` reads on a list of 10,000 elements are charged 430,941 work units **[M]**.
- One learned geometry exists and is worth keeping: the **metric decoder**. It is an invertible operator that applies a change to a value, paired with the solver that finds the change, and the distance between two values is the number of bits of the change that turns one into the other. It already treats a residual as a pullback into a space of changes. Its measured cost was the problem. One evaluation of the metric took 3,334 work units, and the default budget of the kernel's first phase is 2,000 **[D]**.

### 2.8 What the planning trail says

**Your requirements have been stable since October.** From the October prompts (14–26 October): "Topologically, computation may be seen as a projection, / In which case the reverse process requires a lift"; experiments "up to (say) depth=2 (this is essential!)"; "here we will **learn** the propagation rules"; synthesis "on the search tree and execution graph itself". From the batteries prompt: "the search process of the kernel itself produces data that bootstraps rules and complexity for further search", and, of the agents' debugging, "which again is what the kernel itself is supposed to be doing!!"

**Three things changed, by your own hand.** The store went from "one 'flat' store. A list. In lisp." to a hypergraph. Geometry went from "not essential for this proposal, except ..." (`prompt4.md`, 5 November) to bedrock. The budget went from minimal to hours.

**The same problems recur in every plan.** Each of the document auditors' reports lists ten to twelve of them; these four matter most:

1. *What goes with what is always supplied from outside.* In every plan, the kernel was told which rows, values and sub-problems belong together. It never found that for itself, and never stored it. Four plans used four different mechanisms for it. The record of which sub-problem came from which shows the drift. It was kept first on the frame, then in store entries, then off the frame, and then on the frame again as `pairs`, `anchors` and `edges`.
2. *The meta-level is always host code.* Plan 5 diagnosed "a second parallel language of nine `:code-*` primitives" and "Six hand-rolled state machines". There are now nine resumable state structs.
3. *Reuse loses.* Checked rewriting, certified propagation, and tentative integer propagation, the mechanisms that reused learned knowledge, cost more than they saved in nearly every measured cell, for the reason given in §2.4.
4. *Each plan promised to shrink the kernel.* It grew from 900 projected lines to 4,600 to 17,647.

**Graph machinery was declined four times, on minimalism, never on a measurement.** Each of plans 1 to 4 put it off (docs-origins report, part (d)). Plan 1 left out e-graphs until "a measurement says it is needed", although it judged that a minimal e-graph "is a few hundred lines, not a heavy import". Plan 2 kept its patterns small and acyclic until "a measurement says it binds". Plan 3 said not to add e-graphs or "a universal graph-matching engine" at first, and plan 4 said that "A general graph-isomorphism solver is unnecessary." No document reports trying a graph store and finding it too slow or too complex.

**Nuggets worth carrying forward.** Each is followed by its location in the repository, as the document auditors gave it. Numbers attributed to plans 1 and 2 came from Python scratch scripts that were never committed, so none of them can be re-run.

- *The counting identity* (plan 2, `deprecated/plan2.md` §1.1): H(X) = H(f(X)) + E log|fiber|. In words: the information in an input X equals the information in the output f(X), plus the average number of bits needed to say which of the inputs with that output was the actual one. The set of inputs that give one output is its *fiber*. So every step of a computation destroys a definite number of bits, and running the step backwards means supplying them. Plan 2 put it this way: "Running a computation backwards is lifting: given f(x), supply the index."
- *One definition of a residual covers three cases* (plan 2, `deprecated/plan2.md` §1.2). The residual is the index in the fiber when a finding holds on every row and restricts the unknown to a set. It is a mask or a guard, together with the full values on the other rows, when the finding holds only on some rows. It is a metric error when the finding is only approximately right. Plan 2 noted that the approximate case "needs an order or a metric on D", where D is the domain, the set of values the unknown can take. This is the point at which pricing needs geometry as well as topology.
- *Relations before directions* (plan 2, `deprecated/plan2.md` L835-837): "No column is designated as input or output." An operator application is one n-ary relation, and a solver is another orientation of it. Plan 5 said the same of the table that running an operator forward records: reorienting it only changes which columns are declared inputs (`deprecated/plan5.md` §2.3). Your own outline has the same move, converting conserved quantities to generative expressions "via the exchange of input and outputs".
- *Fiber versus section* (plan 7, `plan7/plan7.md` L156, L379). A pullback keeps the whole fiber, that is, every value of the unknown that would satisfy the requirement. An inversion chooses one member of the fiber for each row, and that choice is called a section. A uniqueness law certifies that the fiber has only one member, so that there was no choice to make. A solver is therefore two laws. The first says that its answer term (§2.5) is correct: under the solver's guard, the operator applied to the answer term gives the known result. The second says that the fiber has one member: under the guard, any value that gives the known result equals the answer term.
- *A metric and a decoder are one thing* (plan 7, `plan7/plan7.md` L641): "A metric and a decoder shell are two views of one correction code."
- *A guard is what a law leaves unresolved* (results, October, `deprecated/results.md` L730-733): after an equation is observed, "the unresolved information is the membership of each input in its valid subset".
- *Compression does not reveal laws, and shared-input experiments reveal them at once* (plan 2, `deprecated/plan2.md` §4.4). Given the simulator, a law such as commutativity is no news about the data, so a store that compresses observations by joining equal results gains nothing by recording it; plan 2 found that coding it cost bits instead of saving them. If both argument orders of an operator are run on the same inputs, commutativity appears at once. This was a result from a scratch script, and it was never reproduced in the kernel.
- *Quotient by laws before anti-unifying* (results, `deprecated/results.md` and `deprecated/plan6.md`): anti-unification of expressions first normalized by known laws took a pattern from 5 holes to 2.
- *The matching problem is not graph isomorphism* (plan 2, `deprecated/plan2.md` §1.8). It is conjunctive-query matching: hard in pattern size, polynomial for acyclic patterns.
- *Small residual magnitude is not structure* (plan 1, `deprecated/plan.md` L579). Among 2,661 candidate lifts, the correct one ranked 66th by the size of its residual.
- *Explanation-based generalization* (plans 1–3, `deprecated/plan.md` to `deprecated/plan3.md`). After a derivation succeeds, find the parts of the problem that the derivation never depended on, and replace them by variables. This is a dependency analysis on the search's own record. Of the reflective operations in the trail it is the one specified most completely. It was never built.
- *Sampled evidence can propose and never eliminates* (plan 8, `plan8.md` §6.7). It is the reason nothing learned prunes on the integers, and §5.5 shows the way around it.

The document auditors recorded further ideas from the trail, which this plan does not use; see the `docs-*.md` reports in `plan_v2c_audit/reports/`.

### 2.9 The earlier v2 plans

`plan_v2b.md` proved reliable where it was checked: of about 35 claims that it makes about the code, three were wrong. Its first stage, Stage 0 of the v2 plans (index columns, one behaviour table, attribution by ablation), depends on nothing unverified. `plan_v2.md` and `plan_v2.tex` rest largely on mechanisms taken from papers without verification and on inventions of their own (the `docs-v2b.md` and `docs-v2tex.md` reports).

The code for Stage 1 of the v2 plans, in `v2/`, added 1,393 lines and no tests, and its main new opcode fails in the form that its own proposals build (Appendix D). It also changes no outcome: v2's Stage 0 audit, which runs 64 syntheses, gives the same result on all 64 with the Stage 1 code as without it.

What is worth keeping from these plans is listed with the other imports in §9.

`plan_v2.md` and `plan_v2b.md` share four gaps against your current prompt, and this plan treats them as requirements:

1. Neither analyses budgets of hours.
2. In neither is the lift of a *requirement* an operation of the object language.
3. In both, the kernel's choice of its own experiments is a line item, not a mechanism.
4. As you noted in your own follow-up, both give too much attention to indexing and too little to a general treatment of fibers and residuals.

Your margin note "how, though?" on `plan_v2b.md` asked how spaces are to be compared "only through verified maps". Neither plan says. Section 6.6 answers it.

## 3. Diagnosis: three graphs computed, none stored

The findings above have one cause, stated two ways.

**The kernel computes three graphs and stores none of them.**

1. **The execution graph**: which value came from which values, by which operator, on which row. The VM computes it and returns only the final value.
2. **The equivalence graph**: which expressions agree with which, on which rows. Law discovery computes it as "buckets", reads off some equations, and drops it. Enumeration never sees it.
3. **The derivation graph**: which sub-problem came from which, by which move, and what came back. It exists only as a search tree with a root and one or two children (§2.3), and as a list of messages that no decision reads (§2.6).

Each is rebuilt on demand by a different host function, in a different shape, and discarded. That is why the same idea appears three or four times under different names (§2.2), why nothing persists across branches or jobs, why learned knowledge never reduces the number of candidates, and why reflection has nothing to read.

**Frames are not values.** A frame is the one place where rows, positions, and requirements live, and it is a host structure. So every operation on rows, positions, or requirements is host code, and a synthesized program can reach none of them. "Lift is not a synthesizer primitive" is one symptom. Pullback, fiber, quotient, partition, reorientation, and residual are the others.

A frame also holds one unknown per row. Constraints among several unknowns have nowhere to live, so they are weakened or carried on the side.

The remedy follows directly: store the three graphs, in one structure, made of things the object language can name.
