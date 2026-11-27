# `lisploop` — Plan v2c: one topology–geometry kernel

*Audit of the kernel, its documents, and the literature, and a proposal for a single store. Written 24 November 2026 against commit `15e64c6` (the original kernel unchanged since `df33ed1`; `v2/` at `a4e19fa`), and revised on 25 and 26 November. This document states the current design. What each revision changed, the answers to your margin notes, and what was and was not taken from the outside review are recorded in `plan_v2c_audit/revision-notes.md`.*

**Where the cited files are.** The audit was made against commit `15e64c6`. On 26 November the original kernel and the earlier plans were moved, unchanged, into the directory `v1/`. A file reference in this document such as `frame.lisp:1581` or `bootstrap/build-batteries.lisp` is therefore to be read under `v1/`. Paths that begin with `v2/` or `plan_v2c_audit/` are unaffected, and so are the plan files that remain at the repository root, such as `plan_v2b.md` and `plan_v2c_audit.md`. The text calls the original kernel "the v1 kernel", to keep it distinct from the copy in `v2/`.

**How this was made.** Fourteen AI auditors, working in parallel and independently, each took one slice: five read and ran the code, six read the planning trail, three reviewed the literature. A fifteenth built and ran a small prototype of the proposed store. Three of the code auditors (data structures, search, laws) were told not to read the earlier v2 plans, so that their view came from the code. An outside review, `plan_v2c_audit.md`, then proposed changes to the heuristics, the vocabulary, and the treatment of residuals. Every empirical claim of the review that this plan uses was re-tested independently before it was used here. Some reproduced, several were corrected, several did not hold or held only because of how the review's own test was built, and its experiment on reuse was rebuilt only in outline (§8.5 to §8.7; `plan_v2c_audit/revision-notes.md` gives the verdict on each). Each version of this document was checked by independent readers against the reports, the logs, and the code. The reports, scripts, and logs are in `plan_v2c_audit/` (Appendix D).

**Evidence tags.** Claims of fact are tagged with where they come from. Sections 5–7 are the proposal: read every statement there as **[P]** unless it cites a measurement in §2 or §8.

| Tag | Meaning |
|:--|:--|
| **[M]** | measured during this audit; the script is kept |
| **[C]** | read in the code; file and line given here or in the cited report |
| **[D]** | stated in a project document; not re-measured |
| **[L]** | from the literature, with its maturity noted |
| **[P]** | this plan's proposal; not yet tested |

The earlier v2 plans are treated as claims to check, not as foundations. Appendix B lists what their own audit passes rejected. None of it is re-imported, with the two exceptions named there.

**Terms.** These are used throughout. Each is defined again where it first matters.

| Term | Meaning |
|:--|:--|
| *host*, *object language* | The host is Common Lisp, the language the kernel is written in. The object language is the small language of the programs the kernel synthesizes and its VM runs. An operation that exists only in the host can never be performed by a program the kernel finds (§2.2). |
| *frame* | The present kernel's table of problem rows. Each row holds the known inputs and one requirement on a single unknown (§2.1). |
| *spec* | One entry that the bootstrap asks the kernel to produce, given as a few rows of inputs and outputs. Most of this document is about the sixteen specs that are functions on sequences (§2.3). |
| *work unit* | The present kernel's unit of search effort. The cheapest instruction of the kernel's VM costs one unit, larger instructions cost more, and host work such as scheduling is charged in the same units (§2.3). |
| *impostor* | A program that fits the given rows and is wrong on fresh inputs. A *held-out* score counts fresh inputs; how many there were is stated where a score is given. |
| *space*, *column*, *map* | A space is a set of rows. A column holds one cell per row. A column whose cells point to rows of another space is a map (§5.2). |
| *term*, *class* | A term is a shared expression that denotes a column on a space. A class is all the terms that denote the same column on a space (§5.2). |
| *bank* | The classes enumerated so far on one space with one set of leaves (§7.2). |
| *candidate* | One operator applied to classes already in the bank, and evaluated down one column (§8). It is the unit in which the measurements of §8 count search effort, and it is not the work unit. A *candidate word* (§6.5) is a different thing and is always called by that name. |
| *plain search* | Bottom-up enumeration of terms by size that keeps one term per class and uses no guidance (§8.7). |
| *gain* | The number of candidates that plain search evaluates on a task, divided by the number a method evaluates on the same task (§8.7). |
| *probe space* | A space whose rows the kernel makes up for itself in order to test terms, as opposed to rows that come from a task. |
| *dependency test* | The check of whether one column is a function of some others on a space. It is one group-by (§5.3). |
| *residual* | What is left of a target after a model has accounted for part of it. On the store it is a column (§5.4). |
| *correction* | The bits the kernel's codec charges to turn a predicted value into the true one (§6.1). |
| *quotient*, *label*, *word* | A quotient of values is a small term that takes a value to one of a few labels, such as its sign. A quotient that the kernel keeps in its vocabulary is called a word. So "sign" is a word, and "negative", "zero", and "positive" are its labels (§6.2). |
| *verb table* | For one operator and one word, the table from the labels of the inputs to the labels the output was seen to take, with counts (§6.2). |
| *label filter* | The test, made before a candidate is evaluated, of whether its verb tables allow it to give the target's labels within the size that remains. A candidate that fails is skipped (§7.2). |
| *near miss* | A candidate whose column is close to the target without equalling it (§6.2). |
| *one step from the answer*, *true parent* | The true parent is the class from which the answer is in fact built by one more operator. A class is one step from the answer when it has the true parent's size, whether or not any operator takes it to the target (§6.2). |
| *split*, *guard split* | A program of the form `(if g a b)`, in which a guard `g` divides the rows between two smaller programs. The text also calls it a conditional (§7.2). |
| *size-order rule* | A split is never accepted ahead of a smaller term that has no split (§8.5). |
| *held* | A program that fits the rows is held when it is kept as a provisional answer while the search checks that no smaller program also fits (§7.2). |
| *look-ahead* | The test of whether the target's labels and type can still be reached from a class within the size bound. A class that fails it is not stored. It needs a firm bound on the size of the whole answer (§7.2). |
| *observed*, *tested*, *certified* | The three grades of evidence for a class or a table: true on this space; also true on fresh spaces; proved or exhaustively checked (§5.5). |
| *tentative pass*, *fallback*, *round* | A search that relies on tested knowledge is a tentative pass, and budget is always reserved for the plain search behind it, the fallback. Because the size of the answer is not known in advance, a pass is repeated with a larger size bound each time, and each repetition is a round (§7.2). |
| *reserve* | The present kernel's rule for dividing a budget: three parts go to a tentative attempt and one part is kept for the fallback (§9). |
| *agenda* | The list of open problems with their budget accounts: tasks, their sub-problems, and the small problems the kernel poses to itself on probe spaces (§7.2, §7.5). |
| *derivation space* | The space whose rows are the problems the kernel has posed, with what was tried and what came of it (§7.4). |
| *Stages A to D* | The four stages in which this plan is to be built (§11.3). The present kernel's code also has a phase it calls "Stage A", and the earlier v2 plans had a Stage 0 and a Stage 1; the text says which is meant. |
| *X1 to X9* | The experiments of §11.2. Each has a gate fixed in advance, except X8, which is exploratory. |

---

## 1. Summary

**The question.** Can the kernel's requirements be met by one topology–geometry kernel, with one attendant data structure?

**The answer.** For the topology, yes. The store is assembled from shipped parts, and the two mechanisms that are this plan's own, lifting by a change of space and reading inverses off an operator's table, each have a prototype result behind them and a gate ahead of them. For the geometry, yes in one sense and not yet in another. The geometry this plan can build is derived, not learned: it is computed from the columns of the store, as the cost in bits of one column given others, asked of the values themselves and of coarse labels of the values (§6). A geometry of learned coordinates, such as an embedding, is not yet supported by the evidence (§6.6). Several parts of the ambition are research rather than engineering (§1.6).

### 1.1 What the audit found

1. **A frame is a table of unary constraints.** Each row holds one predicate on one unknown. Relations among unknowns, positions in a sequence, and anything about expressions have nowhere to live. This is the exact place where a graph says more than a frame (§2.1).
2. **Lift is host-only, and so is nearly everything else.** Of the operations you list, a synthesized program can perform substitution, value projection, tupling, and `if`. Pullback, fiber, quotient, partition, reorientation, and residual are host Lisp, because terms are values of the object language and frames, rows, and positions are not (§2.2).
3. **The budget was milliseconds, and it is not the binding constraint.** The whole library regenerates in 0.4 s of search, and one spec gets 0.06 s, so you are right by four to five orders of magnitude. But with hand-written help removed, raising the budget a thousandfold moves sound solutions from 8 to 10 of 16 and no further. The failures are structural first (the search tree has two or three sub-problems at every budget), exponential second (each tenfold of work buys about one AST node), and memory-bound third (§2.3).
4. **The kernel computes the right things and discards them.** 99% of enumerated trees on the real grammars duplicate the behaviour of an earlier tree. Law discovery already groups expressions by behaviour; enumeration never uses the groups. A working behaviour pruner sits in `v2/` behind a flag nothing sets; switched on, it cut work by between 6× and 470×, depending on the grammar (§2.3).
5. **The library is mostly authored.** 2.5% of its bits come from search with a generic grammar; 59% are hand-written expressions. Nothing in the kernel initiates discovery. Yet the library does compound on some tasks when it is used for lifting, and `:map` does emerge from the kernel's own anti-unification (§2.4, §2.5).
6. **Your requirements have not changed since October.** In every plan, the knowledge of which rows, values and sub-problems belong together was supplied from outside. The kernel never found it for itself and never stored it. Graph machinery was declined four times, on minimalism, never on a measurement (§2.8).

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

Geometry is one question about columns: how many bits does one column cost, once others are known? Asked of the values themselves, it prices residuals and finds laws and inverses. Asked of coarse *labels* of the values, such as the sign of an integer, its parity, or the length of a list up to five, it gives each operator a small table of what it does to labels. That table is a type signature the kernel has learned for the operator, and it is where guidance and language come from. A small term that gives such labels, and that the kernel keeps in its vocabulary, is a *word*: "sign" is a word, and "negative", "zero", and "positive" are its labels. A vocabulary is a set of words, and a description of a program is the program run on labels. Nesting stays in the exact store, and the labels are the flat layer over it (§6).

The synthesizer has one move: refine a hole with a program construct, and split the requirement the way that construct splits it. Each construct the VM can run is paired with the law that splits a requirement on it. A search consults what the store knows in a fixed order. It first replays stored solutions. It then orders the operators by labels. It then runs a tentative pass that is filtered by labels, and in that pass every candidate that is evaluated is also checked as a near miss. The plain search stands behind that pass as its fallback. Acceptance is by exact description length alone. A search on a task only reads tables. The problems that the kernel poses to itself, between searches on tasks, write them (§7).

Each part of the store's core has shipped precedent: shared terms, value vectors with behaviour classes, relational tables, law discovery by collision. The search-literature review's own "most reliable recipe" overlaps this parts list, with one departure noted in §5.8. Three things are this plan's own: spaces with maps as the lifting mechanism, inverses read off an operator's table, and keeping all three graphs in one structure (§5.8). The vocabulary is the outside review's proposal, checked and corrected by measurement (§8.7).

### 1.4 What was measured

Two instruments were built to test the proposal: a standalone prototype of the store, 874 lines of Lisp with no kernel code, and a set of Python experiments on a hand-written library of 61 operators (§8) **[M]**. Neither is the kernel.

- **Lift.** The prototype solved fifteen sequence tasks from input/output rows by one fixed procedure with one 12-operator grammar and no skeleton written per function, each scoring 200/200 on held-out examples. The procedure grants the container forms (`tabulate`, selection, `where`, one guard, `fold`); what is found is the term inside. The tasks include the prototype's versions of three of the four functions the existing kernel does not find at a thousand times its budget. None needed recursion (§8.1).
- **The kernel's own spec rows.** The kernel's own specs have 3 to 13 rows each. Thirteen of the sixteen reach 200/200 from them, in some configuration of the prototype. Three need a change. A guard split, which is a program of the form `(if g a b)`, must never be accepted ahead of a smaller term that has no split. Collecting must be able to sum as well as list. And one Boolean call must be in the grammar. `foldl` is underdetermined by its rows and returns an impostor. `best-shift` and `argmax-corr` are not solved (§8.5).
- **Inverses.** The inverses of `+`, `−`, and `neg` were found from the operators' own tables within 25 candidates, and `*` with its guard `b ≠ 0` in about a quarter of a second. Feeding those inverses back made three later searches 60–150× cheaper (§8.2).
- **Laws.** Commutativity, associativity, the identities, and distributivity were derivable by size 7 in 0.01 s, with no false law once the probe space had 8 rows (§8.3).
- **Across spaces.** A relation between two operators' tables that is carried by a small term is nearly free to find. When no term computes a key that says which row of one space goes with which row of another, the rows have to be matched by how they are connected. That matching needed backtracking in only two situations: on regular structures that have no symmetry, and to reject two structures that look alike and are not the same. Comparing whole problems by the properties they share found problems of the same form, and did not find the operators a problem needs (§8.6).
- **A vocabulary.** Giving each operator a table of what it does to labels cut the candidates a search evaluates 14 to 18 times, depending on the set of tasks, and its time 1.3 to 4 times, and it worked for operators never used in any solved task. A procedure that the kernel could run chose a vocabulary to within a fifth of the gain of one listed by hand, and another chose the rows the tables are built from better than the outside review's hand-picked ones. Both were run in Python, on one library, and not yet together. The tables are tested knowledge, not certified, and they act on the last step of a program. So a search filtered by them is a tentative pass, with the plain search behind it (§8.7).
- **Limits.** Three limits were measured. Nested guard splits overfit. Folds with sequential state need a `fold` form. The set of kept laws does not converge. Two more limits are extrapolated from 90-second runs: a single deep search would exhaust 24 GB in one to eight minutes, and ten hours would reach one or two nodes further than one hour (§8.4).

### 1.5 Where this plan qualifies your prompt

- **Budget.** Hours are right, but not as one deep search. An hour should be thousands of small bounded problems, re-validation on fresh rows, and ablation (§7.6). By one auditor's model of the published results, cutting a grammar from a hundred primitives to ten is worth more nodes than the step from one second of search to one hour (§4.1).
- **Anti-unification.** Your reading of it as quotienting plus lifting holds as intuition. On the store it comes apart into a shared pattern (the constant columns of an instance space) and a quotient (the class). Treating two instances as the same when they fall in one class would make anti-unification robust to equivalent syntax. That is cheap only as normalize-then-generalize, which can miss a pattern; the full version is a search across spaces (§5.4, §5.9).
- **Graph isomorphism and e-graphs.** Within a space neither is needed: shared, ordered terms compare by hash. Across spaces a matching engine is needed, as you say. It is colour refinement with backtracking, built from group-by and re-index, and run only on the pairs that cheaper signals propose (§5.9). An e-graph's store is worth having; its saturation is not (§4.3).
- **Flat versus nested.** The choice between flat and nested is not a question of what can be represented. A flat space buys storage economy that a library of a few hundred entries does not need. Keep nesting exact, and let the labels of §6.2 be the flat layer over it (§6.6).
- **Lifting forms as primitives.** A primitive may encode the shape of a container, never the content of a domain. `tabulate`, `fold`, and `where` are granted on that rule; what goes inside them is found (§7.1).

### 1.6 What is research, not engineering

- A closed loop in which laws, inverses, and abstractions found on the store become primitives for the next turn of the loop, on the same store. Abstraction alone has precedent, and there it roughly doubles solve rates and then plateaus; the full loop has none (§10).
- Learned inverses beyond one operator; guarded laws with guards larger than about four nodes; general recursion with hidden state.
- Algebra from depth-two experiments, over spaces whose rows range over functions (§5.4).
- A vocabulary that goes on improving the kernel's search as its library grows. Choosing a vocabulary and building its tables have a first measurement (§8.7). Compounding of that kind has no precedent. The one small test of it here, in which the words were chosen again as a library grew, showed little or none (§6.5).
- Words that see further than the last step of a program. Nothing measured so far changes the exponent of search (§6.8).
- Learned coordinate spaces, and language with people.

### 1.7 Recommendation

Rewrite, in four stages. About 3,500 lines of the present kernel and its milestone code are worth carrying over: roughly 2,200 as code or as a design, and roughly 1,300 that work through a frame today and need that interface moved. About 750 more are ideas to re-implement (§9). Stage A is the store core plus two experiments: law discovery by class, which is shipped technique, and inverses from tables, which is this plan's own and so far shown only on the prototype. If either fails, the plan is wrong at the root and that is known first. Search across spaces (§5.9) and the vocabulary (§6.4) enter in Stage C (§11). The standing metric is the kernel-found fraction of the library, which is 2.5% today.

---

## 2. What the audit found

Each subsection gives the facts that bear on the design, with the source. Full detail, with file and line for every claim, is in the audit reports listed in Appendix D.

### 2.1 The frame is a table of unary constraints

A frame row is `(key, known-inputs, requirement)`. The requirement is one Boolean expression over a single unknown, `x0` (`frame.lisp:7-10, 221-222`) **[C]**. So a frame can say "on this row the unknown must equal 7", or "must lie in this set", or "must satisfy this predicate". It cannot say anything that relates two unknowns, or the unknown on two rows, except through three later additions (`frame.lisp:14-24`). `pairs` links two rows whose values should agree, and `anchors` lists rows whose values should differ; both are priced as soft penalties, not enforced. `edges` are typed links between two rows. Two of their kinds, "equal" and "distinct", are enforced by exact search. The third only records that two rows are neighbours in an order, and constrains nothing.

This is the precise limit of the representation. Two operations run into it. *Pullback* takes a requirement on a whole program and turns it into a requirement on a part of the program that is still missing. It works by substitution. The outer part of the program that is already known, with the place of the missing part left open, is called a *decoder*, and pullback substitutes the decoder into the requirement (§5.6). *Lift* does the same when the missing part is a function that the decoder calls, such as the function argument of `map`: it turns the requirement into requirements on the calls of that function (`lift-frame`, below). When a pullback or a lift produces a constraint that joins several unknowns, the kernel does one of two things. It weakens the constraint, which is sound. Or it returns the constraint beside the frame, in a list called `coupled`. A coupled constraint is solved afterwards by brute force. The kernel keeps up to 4 candidate programs for each unknown and tries up to 256 combinations of them (`synthesize.lisp:636-642`) **[C]**.

Three more facts about the representation:

- **Terms are not shared.** Each expression is an ordinary Lisp list. Two occurrences of the same expression are therefore two separate objects, and the only way to see that they are the same is to compare them piece by piece. Every snapshot of a frame, which the kernel takes before it starts a resumable computation such as a search on it, copies the whole tree of each expression. The copy loses the cached metadata and the compiled closures that were attached to the original **[C]**.
- **Nothing records an execution.** When an expression is evaluated, no note is kept of which operator consumed which value. The nearest thing is the host function `lift-frame` (`frame.lisp:1194-1271`) **[C]**. It expands a decoder step by step, without running it, until it reaches the places where the unknown function is called. In doing so it builds what is in effect an execution graph, written inside requirement expressions. It then discards that graph.
- **Frames themselves are cheap.** At 4,000 rows every basic frame operation is linear and takes 4–60 ms **[M]**. The frame is not a performance problem. It is an expressiveness problem.

Pullback itself is good. It is 37 lines, with a tested contract that it never prunes a true solution (`frame.lisp:544-580`; `tests/invariants.lisp:120-236`). The cost is in what follows it. To turn a pulled-back requirement into an explicit set of allowed values, the kernel uses three things **[C]**. The first is ten hard-coded rules, each of which takes one operation off one constructor: for example, an equality with a literal off a `tuple`, or `at` off a `cons`. The second is the learned *solver* entries, each of which computes an unknown argument of an operator from its other arguments and its result. The third is seven separate functions, called from 27 sites, that recover "the set of values this row allows" from the syntax of the requirement.

### 2.2 Where each operation lives

You wrote that lift is "wholly in the host lisp". Two languages are involved, and the difference between them matters throughout this document. The *object language* is the small language of the programs that the kernel synthesizes and that its VM runs. The *host* is Common Lisp, the language the kernel itself is written in. An operation that exists only in the host can be performed by the kernel's own code. It can never be performed by a program that the kernel finds.

Your statement is confirmed, and the asymmetry is wider than lift. The table condenses the audit's operation table (core-repr report, §3). It describes the v1 kernel, which is the original kernel and is distinct from the copy in `v2/`.

| Operation | Available to a synthesized program | Host Lisp only |
|:--|:--|:--|
| Substitution | `:code-subst`, `:code-eval`, `:code-match`, `:code-bind` | nine further variants; `instantiate` alone has 34 call sites |
| Lift over rows | no (a program sees one row) | implicit in every frame loop |
| Lift over a container | no primitive; only as recursive library functions | — |
| Lift of a requirement through a higher-order decoder | no | `lift-frame` and helpers, about 350 lines |
| Lift over an index set | no (v1 has no `iota`, a primitive that produces the index list 0, 1, …) | — |
| Projection | `:at`, `:tail`, `:length` on values | all frame projection |
| Pullback | no | `pullback-frame` |
| Fiber / preimage | `:member`, `:lookup` on explicit sets | hand-written simplification rules, each for one constructor; learned solvers for arithmetic |
| Anti-unification | no | `anti-unify` (38 lines) and six call sites |
| Quotient | no | `quotient-values`; observation buckets |
| Partition / guard | `:if` | `partition`, `infer-fibers`, `support-frame`, guard search |
| Reorientation | no | `orient-conserved-quantity`, `solve-equality-symbolically` |
| Residual | metric programs are evaluated by the VM | all residual computation |

The root cause is one fact: **terms are values of the object language; frames, rows, keys, and positions are not.** A learned program can transform code. It cannot build a frame, ask for a search, or read a result **[C]**.

*Reentrancy* is what you called "freely shifting abstraction level". The search audit lists what exists toward it today: synthesis over values that are code, frames built from the search's own messages, and searches nested inside searches (search-engine report, §6.1). It then lists eight concrete things that block full reentrancy (search-engine report, §6.2) **[C]**:

1. Synthesis is not an operation of the VM. No primitive poses a sub-problem, and frames, rows, decompositions, search jobs and ledgers are host structures.
2. The operations you list, from pullback and lift to anti-unification, are host functions.
3. The proposal generators, which suggest how to split a problem into sub-problems (§2.3), are host functions that the search cannot create, rank, or switch off.
4. Recursion works by changing the global table of functions while a job runs.
5. Other global state lies on the same path, although a library can already be isolated.
6. Nested searches cannot be resumed, and their budgets are constants written in the code.
7. A child problem is always the parent's target seen through a decoder with one hole, so no sub-problem can be about a decomposition, a policy, or the search's own messages.
8. The tables that are read from the search's messages (§2.6) have fixed columns, chosen by hand.

The same concept is also implemented several times. One example is the step "Pull a requirement to a child and compose the child's model back", where the child's model is its candidate program. It exists as three pairs of functions, chosen by flags (`synthesize.lisp:290-320`). All three begin with the same substitution and differ only in how they factor the result. The code also uses one word for several things (core-repr report, §3). "Lift" names four different operations. Besides lifting a requirement through a decoder (`lift-frame`), it names giving a child problem the head of a list and the recursive call on its tail (`lift-inductive-sequence-context`), carrying solvers found over finite fields to the integers (`lift-field-solvers`), and carrying a solver for single elements through `map` to a solver for sequences (`induce-functorial-solvers`). "Fiber" names three things: the preimage of a value, a group of rows whose requirements can be satisfied together, and the child rows that come from one parent row.

### 2.3 Search: the budgets were milliseconds, and the limit is structural

Some terms first. A *spec* is one entry that the bootstrap asks the kernel to produce, given as a few rows of inputs and outputs. The sixteen specs used in this section are those of the sixteen functions that the bootstrap has the kernel synthesize. The bootstrap also writes specs for solvers and for other kinds of entry (§2.5). A *work unit* is the kernel's own unit of search effort. The cheapest instruction of the kernel's VM, such as adding two numbers in a small finite field, costs one unit. An instruction with larger arguments costs more, and host work such as scheduling the search is charged in the same units. A *recursion-synthesis job* is the kernel's full search for one recursive function. It builds a tree of sub-problems, searches each one, and checks every candidate answer on all of the spec's rows. *Flat search* is a single bottom-up enumeration over one table of rows, with no sub-problems. Inside each sub-problem, the kernel first runs a search of its own: the kernel's first search phase (its code calls it "Stage A"; it is not Stage A of this plan, §11.3). That phase enumerates programs in order of size, runs each on every row, and prices each by its own bits plus the bits needed to correct its errors. It has a cap of its own, which is fixed when the job is created and does not grow when the job's budget is raised. The work it does is still charged to the job.

A few more terms are used in the table below. A *schema* is a hand-written skeleton of a recursive program. The bootstrap has five. Each was written with one or two of its functions in mind, and all five are offered to every synthesis job of the bootstrap. A *whitelist* is the list of operators that the author allows the search to use for one spec. The *full grammar* is the grammar that the audit builds when it ignores the whitelist. It contains the arithmetic and comparison primitives and `if`. For each type that appears in the spec's own type signature, it adds primitives of that type: `cons`, `tail`, `length`, `concat` and `at` for a sequence type, `tuple` and `at` for a tuple type, and `code-eval` for a code type. It also contains every library function defined so far. It is not every operator the kernel has. It leaves out `gather`, `member`, `lookup` and the other code primitives, and it adds tuple operators only when the spec's type signature contains a tuple type. For that reason one of the sixteen specs, `argmax-corr`, cannot be expressed in it. A solution is *held-out-sound* when it is also right on a fresh input that was not among the spec's rows. In the audit harness that produced the counts below, that is one hand-written input for each spec, so each count of sound solutions here is an upper bound. An *impostor* is a program that fits the spec's rows and is wrong on fresh inputs. The *bit bound* is the largest program size, in bits of the kernel's code for programs, that enumeration is allowed to reach.

**Budgets.** A recursion-synthesis job runs at 5–7 million work units per second, and flat search at 33–69 million **[M]**. The default budget per spec is 350,000 units (`consolidate.lisp:1209`), which is 0.06–0.07 s. An hour of a synthesis job is about 2 × 10¹⁰ units. The whole knowledge library regenerates, byte-identically, in about 0.4 s of search **[M]**. Across the entire planning trail, the longest wall-clock time reported for any search is 44 s **[D]**. Your statement that the budget was "very limited" is correct by four to five orders of magnitude.

**More budget alone does not help.** Four auditors tested this independently and agree **[M]**:

| Test | Result |
|:--|:--|
| The 16 bootstrap specs, with the full grammar and no schemas, at 1, 10, 100 and 1000 times the default budget per spec | The number of specs with a held-out-sound solution was 8, then 10, then 10, then 10, of 16. The last figure was not measured on a run of all sixteen. At 1000 times the budget, only the five specs still unsolved at 100 times were run, one at a time, and none of them gained a sound solution |
| The seven specs that time out at 350,000 units, with 10 times the budget | Two more were solved (`positions`, `seq-corr`) |
| The same seven, with 100 times the budget (35 million units), and the five still unsolved with 1000 times (350 million units, about a minute each, 2.6–3.5 GB of live memory) | Nothing more was solved; `map-adjacent`, `scan`, `shift-seq` and `best-shift` were still cut off |
| `map-adjacent` with its own whitelist and the schemas removed | The search tried every program that its bounds allow and found no solution. That took 2.83 × 10⁹ work units, which is 8,085× the shipped budget |
| The same, with the bit bound raised from 130 to 300, and the depth limit of the search tree and the budgets of the kernel's internal search phases raised as well | Still no solution when the search was cut off at 1.5 × 10⁹ work units |
| `foldl`, at any budget | The same impostor each time |

The failures are structural first, exponential second, and memory-bound third.

- **Structure.** The kernel searches a tree of sub-problems. The root is the spec, and a child is a smaller problem that some decomposition of its parent produced. On the four specs that stay unsolved, this tree is a root with one or two children at every budget tried. The reason is that a sub-problem is expanded only once, by a fixed list of *proposal generators*: host functions that each suggest one kind of decomposition for it. The one that matters for these specs is the kernel's skeleton for recursion. It recurses on `(tail Xi)`, leaves every other argument unchanged, and removes `at`, `tail`, `if` and `=` from the child's grammar (`decompose.lisp:341-382`). A second form, called lockstep, walks two sequences in step. A child is expanded further only when some generator proposes a decomposition for it, and for these children none does. So the tree cannot grow deeper. Raising `:max-depth` to 3 or 4 changed nothing on these four specs. More work therefore buys longer expressions inside the same two or three sub-problems. It cannot buy more structure. One more of the seven specs that time out, `argmax-corr`, differs in shape and does no better in outcome. Its tree did grow, to 34 sub-problems at 35 million work units, and to 49 and 64 when `:max-depth` was raised to 3 and 4. What the job returned was an impostor.
- **Exponent.** The kernel measures the size of a program in bits of its code for programs, and a *body bit* is one bit of a program's body, not counting its header. A *lane* is one of the two or three sub-problems of a job, each with its own flat enumeration, which the scheduler serves in turns. In every lane, the work needed grows by a factor of 1.38–1.50 for each further body bit. At that rate, each tenfold increase in work buys 6–7 more bits. One node of a program's syntax tree, an *AST node*, costs 3–5 bits when it is a variable. When it is an operator application, it costs 6 bits or more, not counting its operands. So **each tenfold increase in work buys about one more AST node**. The 1,000× budget advanced each lane by 18–23 bits. By extrapolation, an hour of search reaches bodies of 53–63 bits. The known solutions for the four stuck functions have bodies of 132–259 bits.
- **Memory.** The enumerator keeps every tree it builds, at about 430 bytes each. An 11 GB heap was exhausted before 7 × 10⁸ work units, which is about 100 s of search. By extrapolation, an hour would need roughly 180–240 GB.

With its hand-written schema, the kernel does find `map-adjacent`, in 109,012 work units. The answer is 260 bits long, although enumeration at the root is bounded at 130 bits. The bound limits each enumeration, not the program that is composed from their results. The schema, `:lookahead-inductive`, supplied the outer skeleton, and each part left to enumeration was within the bound (search-engine report, §0). So decomposition found that answer. Enumeration did not.

**Enumeration ignores what it computes.** The v1 kernel, which is the original kernel and is distinct from the copy in `v2/`, keeps and reuses every syntactic expression it builds. On the real sequence grammars, 99.0–99.8% of enumerated trees are behavioural duplicates: they give the same outputs on the spec's rows as a tree built earlier. `map-adjacent` produces 315,388 trees with 767 distinct behaviours **[M]**. On those grammars the number of trees grows ×1.37–1.42 per bit, and the number of distinct behaviours ×1.17–1.25.

A behaviour pruner and a columnar evaluator already exist in `v2/enumerate.lisp`. The pruner drops a candidate whose outputs on every row equal those of a candidate already kept. The columnar evaluator computes a new expression's outputs on all rows at once, by applying its top operator to the stored output columns of its parts. Both sit behind flags that no caller sets. Three auditors switched them on by hand, in four tests **[M]**. All four were flat searches. The pruner was not run inside a synthesis job, and whether it stays sound there was not determined.

| Test | Effect |
|:--|:--|
| The three finite-field benchmarks | Pruning alone cut work 6–79×. Pruning together with the columnar evaluator cut it 11–118×. The best model found was the same each time. |
| Integer arithmetic problems over `+` and `*`, on six rows | Pruning cut work 11–31×. |
| A two-variable integer grammar, enumerated to 48 bits | The same size bound was reached in 1/470 of the work. |
| `map-adjacent` | The same work reached 70 bits instead of 47. |

The finite-field figures overstate the gain, because a field of only five elements soon runs out of new behaviours, which makes pruning look better than it would elsewhere. With the pruner on, each tenfold increase in work buys about two AST nodes instead of one. That is still logarithmic.

**Evaluation is not where the time goes.** In a synthesis job, evaluating candidates takes about 3% of the time. The rest goes to bookkeeping: the scheduling loop, which advances the search one work unit at a time; charging each unit to the ledger; constructing expressions; and looking up metadata in a hash table. In flat exact search, evaluation is about half of the time **[M]**.

**More budget is not even monotone.** One test problem from Plan 8 is solved in 264,353 work units when the kernel's first phase has its default budget. When that phase is given a larger budget, 16,000 units, the same problem is still unsolved after 1,000,000 work units **[D]**.

**Search policy is hard-coded in 158 places.** The search-engine report (§4) sorts these decisions into five categories **[C]**: 52 are caps or prunes, 51 are pieces of domain knowledge, 30 are guards against repeating work (dedupe or memo guards), 30 are ordering rules, and 6 are accounting rules. The five figures add up to more than 158 because a decision that belongs to two categories is counted in both. This list is the concrete target for reflection, by which this plan means the kernel reading the record of its own searches and making such decisions itself (§7.4).

### 2.4 Laws and algebra: a sound generic core, steered by hand

The generic core of algebra discovery is about 550 lines, and it works **[C]**. It enumerates every expression up to a bit bound and runs each one on every row of a grid that covers a whole finite field. It then groups the expressions by their vector of results, and reads each group as a set of equations.

Everything around that core is supplied by the bootstrap script, `bootstrap/build-batteries.lisp`. The script defines four discovery jobs. For each job it fixes the finite field, the number of variables, the list of operators, the bounds, and the budget (20,000–80,000 work units). A host function, `law-operator-fact` (`consolidate.lisp:709-735`), then filters what the jobs find. It keeps an equation only if it has one of three shapes: commutativity, associativity, or identity. Together the four jobs propose 187 equations. All 187 are true on every input in GF(3), the field of the integers modulo 3. Only 14 pass the filter **[M]**.

- **Distributivity is missing for three reasons, none of them the engine.** No job contains both `+` and `*` with three variables. The shape filter has no case for two operators. And the budget that the algebra battery gives a job of that size is about 85 times too small. (The script builds the library as eight *batteries*, each a file of library entries; the algebra battery is the one that holds the laws of arithmetic.) Asked directly, the existing engine puts `a*(b+c)` and `a*b+a*c` in one group in under a second **[M]**.
- **On the integers, nothing learned ever prunes.** A law may be used as a rewrite only when its evidence is exhaustive, derived, or a trusted axiom. Integer laws can only be sampled. So the set of rewrites on the integers is exactly the four hand-written axioms **[M]**.
- **Where laws are wired into search, they cost more than they save.** On one finite-field test problem, the search took 182,000 work units with no laws, 741,000 with one law switched on, and 70.2 million with 80 laws. The results were identical in all three runs **[M]**. The documents' own diagnosis from October still holds: learned knowledge produced "cheaper requirement checks, rather than fewer enumerated candidates" **[D]**.
- **The library's 14 kinds of entry are one record with different labels.** The knowledge library files each entry under one of 14 kinds, such as `:law` or `:solver`. In the code all 14 are the same structure, and the kind is only a tag on it. A `:solver`, for example, is a law about an operator together with a choice of which argument of the operator is the unknown. The code builds that law, with the expression that the solver computes for the unknown in the unknown's place, in order to validate the solver. Six of the 14 kinds have no entry in the library. Entries are linked by typed edges, each from one entry to other entries or to function names. About 30 types of edge are written, and only about 10 are ever read **[C]**.
- **Every conversion from one kind of library entry to another that carries algebra is a hand-written recognizer of particular shapes.** There are four such conversions **[C]**. A law becomes an operator fact (commutativity, associativity, or identity) only if it has one of 3 shapes. A law becomes a solver only if it has 1 shape. When the tested laws of an operator make it associative with an identity on both sides (the code calls this set of laws a *star*), a third conversion records a *fold motif*: the law that `foldr` and `foldl` give the same value when their step is such an operator. It recognizes only one type signature, that of a fold, and only that one star. The fourth conversion turns a solver for an operator on single elements into a solver for the same operator mapped over a sequence. It recognizes only functions shaped like `map`, with a step applied element by element. Two other conversions are generic: turning a law into a rewrite rule, and retyping a law from a finite field to the integers. The laws-library report (§2.2) lists every conversion.
- **Guards are already found the way you describe.** The rows where two expressions both return a value and agree become a Boolean target, and a guard program is searched to fit it. There, an error raised by the VM counts as an outcome like any value. It works, within a language of guards that the caller supplies **[C]**.
- **Nothing in the kernel initiates discovery.** Every discovery entry point is called only from tests or from the bootstrap script **[C]**.
- **The kernel has one test of dependency, and only the test suite reaches it.** `target-sensitive-p` (`laws.lisp:892-929`) checks whether an expression depends on one input. It swaps that input for up to four other values while the other inputs stay fixed. Its only caller in the kernel is `orient-conserved-quantity` (`laws.lisp:948`), and that function, like `target-sensitive-p` itself, is otherwise called only from the tests (`tests/topology.lisp`) **[C]**.

### 2.5 The library is mostly authored

The bootstrap writes 61 operational library entries, meaning entries other than specs: laws, solvers, functions, transformers, descriptors, one template and one motif. Beside them it writes 31 `:spec` entries. A `:spec` entry holds the example rows, the types and the operator whitelist for one entry to be produced. Among its searches, the bootstrap runs 19 synthesis jobs: one for each of the 16 functions it synthesizes, which are the 16 specs of §2.3, and three more that find two guards and the answer term of one solver (the first point below defines an answer term). The laws and the eight arithmetic solvers come from separate, plain searches. Ten of the 16 functions are saved in the library, and their specs are ten of the 31. The other 21 specs are for derived functions, solvers and transformers. The remaining six of the 16 functions are *seed functions*, from which anti-unification derives `:map` and `:foldr` (below). Provenance of the 61 entries, recomputed from the build script **[M]**:

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
- **On some tasks the library makes later problems cheaper, but only when it is used for lifting.** Used for lifting means that the kernel proposes a library function that takes a function argument, such as `:map`, `:scan` or `:foldl`, as the outer part of the answer, and then searches only for that argument (§2.1). The test was 8 held-out tasks **[M]**. With lifting through library entries, 3 of them were solved in 25,000–42,000 work units. The kernel alone does not solve those 3 in 35 million. One more task became 3.2× cheaper. Three or four others became 1.7–3× more expensive: the table of the bootstrap-reflection report shows four, and its summary counts three. The other way to use the library is to offer its functions as plain operators, which is what the bootstrap does. That never helped. In a separate experiment **[M]**, functions with dummy bodies were added to the grammar of three specs. Two of the three were unaffected, and the third, `seq-corr`, became 6.6× more expensive.

### 2.6 Reflection is plumbing without a reader

*Reflection* means the kernel reading the record of its own search and acting on it. The plumbing for it exists. During a job the search emits *messages*, each a short record of one event, such as a sub-problem being prepared, a candidate being found or rejected, a conflict, or a search exhausting its bound. `messages.lisp` (128 lines) turns a job's messages into an ordinary frame. But nothing reads that frame except a test and an offline experiment, `yield-gate` (§7.4) **[C]**. Within a job, no decision reads the messages or the trace, which is the job's log of each turn of its scheduler.

One older loop exists in the code, though no production path calls it. It condenses search traces into a predictor, which adds an adjustment, clamped to a fixed range, to the priority of each sub-problem. Run on the kernel's own curriculum of 16 specs, it learns the constant 0 and changes work by +0.02%. The cause is concrete. Of its 42 training labels, 40 sit at the limit of the clamp, and the jobs, with one to five sub-problems each, are too small to reorder **[M]**.

An ablation shows what a search trace is good for **[M]**. `plan_v2b.md` claimed that everything learned from a trace could be removed with no change in later work. That is not quite right. A *nogood* records that one choice of decomposition merged rows that need different outputs, so that the same choice can be refused later. One group of things learned from traces saves 2,332 work units on the task `add-len`, out of the 40,155 that the task takes without them. The group is a nogood, the feature learned with it to tell such rows apart, and the learned predictor. But it does so only when the same task is run again. Nothing learned from a trace helped on a different task. What does carry over to other tasks is the abstracted functions.

### 2.7 Geometry as built

Geometry today is one number: bits.

- A *residual* is the information still needed to reconstruct a target after a model has accounted for part of it. Residuals have eight unrelated representations in the code, from a correction that turns a predicted value into the wanted one, to rows held in reserve **[C]**. The core-repr report (§1.4) lists all eight, with file and line.
- The built-in distance is a fixed rule for each value type. Two sequences are compared only element by element, at the same positions (`frame.lisp:1533`).
- A frame can carry a metric of its own, which is an expression over two values. By its own documentation that metric cannot depend on the row. When the frame is pulled back, the metric can be carried over to the new frame in only four cases (`frame.lisp:508-518`) **[C]**: when the decoder is the identity; when the decoder is an `if` that passes the child through on one branch; when the decoder reads nothing but the child, and the metric composed with it can be proved to return a value on every input; and when the child has the target's type and the metric survives a replay on at most 3 rows and 3 values.
- A sub-problem's score adds two numbers that are measured in different places, together with three smaller terms (half a policy score, 16 bits for each coupled requirement, and a charge for run work). The bits of the program are measured at the root problem. The bits of the residual are measured in the child problem's own space. So pricing in the original, or ambient, space and pricing in a derived, or induced, space are already mixed in one score **[C]**. Plan 7 stated this rule and called the price "one step deep" (`plan7/plan7.md` L437); the code is `synthesize.lisp:447-457`.
- The price of naming an operator is an accident of its position in the list of primitives: `:lookup` and `:gather` cost 4 name bits, `:at` and `:cons` 9, `:code-eval` and `:mod` 12 **[C]**.
- The kernel's price list for work charges quadratic cost for operations that are not quadratic in the host. A recursive sum over a list of n elements is charged about 7.5·n² work units. Two `at` reads on a list of 10,000 elements are charged 430,941 work units **[M]**.
- One learned geometry exists and is worth keeping: the **metric decoder**. It is an invertible operator that applies a change to a value, paired with the solver that finds the change, and the distance between two values is the number of bits of the change that turns one into the other. It already treats a residual as a pullback into a space of changes. Its measured cost was the problem. One evaluation of the metric took 3,334 work units, and the default budget of the kernel's first phase is 2,000 **[D]**.

### 2.8 What the planning trail says

**Your requirements have been stable since October.** From the October prompts (14–26 October): "Topologically, computation may be seen as a projection, / In which case the reverse process requires a lift"; experiments "up to (say) depth=2 (this is essential!)"; "here we will **learn** the propagation rules"; synthesis "on the search tree and execution graph itself". From the batteries prompt: "the search process of the kernel itself produces data that bootstraps rules and complexity for further search", and, of the agents' debugging, "which again is what the kernel itself is supposed to be doing!!"

**Three things changed, by your own hand.** The store went from "one 'flat' store. A list. In lisp." to a hypergraph. Geometry went from "not essential for this proposal, except ..." (`prompt4.md`, 5 November) to bedrock. The budget went from minimal to hours.

**The same problems recur in every plan.** Four of the document auditors' reports, those on plans 1 to 9, each list between ten and fifteen such problems. These four problems matter most:

1. *What goes with what is always supplied from outside.* In every plan, the kernel was told which rows, values and sub-problems belong together. It never found that for itself, and never stored it. Four plans used four different mechanisms for it. The record of what is linked to what shows the drift. Plan 1 kept lineage on the frame, plan 2 kept provenance in every store entry, and plans 3 and 4 kept it off the frame, in separate records and in the call-ids of messages. In the present kernel, links are on the frame again as `pairs`, `anchors` and `edges`. But these relate rows of one frame (§2.1), and they do not record which sub-problem came from which.
2. *The meta-level is always host code.* Plan 5 diagnosed "a second parallel language of nine `:code-*` primitives" and "Six hand-rolled state machines". There are now nine resumable state structs.
3. *Reuse loses.* Checked rewriting, certified propagation, and tentative integer propagation, the mechanisms that reused learned knowledge, cost more than they saved in nearly every measured cell, for the reason given in §2.4.
4. *Each plan promised to shrink the kernel.* It grew from 900 projected lines to 4,600 to 17,647.

**Graph machinery was declined four times, on minimalism, never on a measurement.** Each of plans 1 to 4 declined it. The docs-origins report (part (d)) lists six such statements across the four plans, all of them written by the plans' AI authors. Plans 1 to 3 put it off. Plan 1 left out e-graphs until "a measurement says it is needed", although it judged that a minimal e-graph "is a few hundred lines, not a heavy import". Plan 2 kept its patterns small and acyclic until "a measurement says it binds". Plan 3 said not to add e-graphs or "a universal graph-matching engine" at first. Plan 4 went further and said that "A general graph-isomorphism solver is unnecessary." No document reports trying a graph store and finding it too slow or too complex.

**Nuggets worth carrying forward.** Each is followed by its location in the repository, as the document auditors gave it. Numbers attributed to plans 1 and 2 came from Python scratch scripts that were never committed, so none of them can be re-run.

- *The counting identity* (plan 2, `deprecated/plan2.md` §1.1): H(X) = H(f(X)) + E log|fiber|. In words: the information in an input X equals the information in the output f(X), plus the average number of bits needed to say which of the inputs with that output was the actual one. The set of inputs that give one output is its *fiber*. So every step of a computation destroys a definite number of bits, and running the step backwards means supplying them. Plan 2 put it this way: "Running a computation backwards is lifting: given f(x), supply the index."
- *One definition of a residual covers three cases* (plan 2, `deprecated/plan2.md` §1.2). The residual is the index in the fiber when a finding holds on every row and restricts the unknown to a set. It is a mask or a guard, together with the full values on the other rows, when the finding holds only on some rows. It is a metric error when the finding is only approximately right. Plan 2 noted that the approximate case "needs an order or a metric on D", where D is the domain, the set of values the unknown can take. This is the point at which pricing needs geometry as well as topology.
- *Relations before directions* (plan 2, `deprecated/plan2.md` L835-837): "No column is designated as input or output." An operator application is one n-ary relation, and a solver is another orientation of it. Plan 5 said the same of the table that running an operator forward records: reorienting it only changes which columns are declared inputs (`deprecated/plan5.md` §2.3). Your own outline has the same move, converting conserved quantities to generative expressions "via the exchange of input and outputs".
- *Fiber versus section* (plan 7, `plan7/plan7.md` L156, L379). A pullback keeps the whole fiber, that is, every value of the unknown that would satisfy the requirement. An inversion chooses one member of the fiber for each row, and that choice is called a section. A uniqueness law certifies that the fiber has only one member, so that there was no choice to make. A solver is therefore two laws. The first says that its answer term (§2.5) is correct: under the solver's guard, the operator applied to the answer term gives the known result. The second says that the fiber has one member: under the guard, any value that gives the known result equals the answer term.
- *A metric and a decoder are one thing* (plan 7, `plan7/plan7.md` L641): "A metric and a decoder shell are two views of one correction code."
- *A guard is what a law leaves unresolved* (results, October, `deprecated/results.md` L730-733): after an equation is observed, "the unresolved information is the membership of each input in its valid subset".
- *Compression does not reveal laws, and shared-input experiments reveal them at once* (plan 2, `deprecated/plan2.md` §4.4). Given the simulator, a law such as commutativity is no news about the data, so a store that compresses observations by joining equal results gains nothing by recording it; plan 2 found that coding it cost bits instead of saving them. If both argument orders of an operator are run on the same inputs, commutativity appears at once. This was a result from a scratch script, and it was never reproduced in the kernel.
- *Normalize by laws before anti-unifying* (results, `deprecated/results.md` and `deprecated/plan6.md`): anti-unification of expressions first normalized by known laws took a pattern from 5 holes to 2.
- *The matching problem is not graph isomorphism* (plan 2, `deprecated/plan2.md` §1.8). It is conjunctive-query matching: hard in pattern size, polynomial for acyclic patterns.
- *Small residual magnitude is not structure* (plan 1, `deprecated/plan.md` L579). Among 2,661 candidate lifts, the correct one ranked 66th by the size of its residual.
- *Explanation-based generalization* (plans 1–3, `deprecated/plan.md` to `deprecated/plan3.md`). After a derivation succeeds, find the parts of the problem that the derivation never depended on, and replace them by variables. This is a dependency analysis on the search's own record. Of the reflective operations in the trail it is the one specified most completely. It was never built.
- *Sampled evidence can propose and never eliminates* (plan 8, `plan8.md` §6.7). It is the reason nothing learned prunes on the integers, and §5.5 shows the way around it.

The document auditors recorded further ideas from the trail, which this plan does not use; see the `docs-*.md` reports in `plan_v2c_audit/reports/`.

### 2.9 The earlier v2 plans

`plan_v2b.md` proved reliable where it was checked: of about 35 claims that it makes about the code, all held except three: one miscount, one figure that could not be reproduced, and one over-statement. Its first stage, Stage 0 of the v2 plans (index columns, one behaviour table, attribution by ablation), depends on nothing unverified. `plan_v2.md` rests largely on mechanisms taken from papers without verification and on inventions of its own. About half of the mechanisms that the gates of `plan_v2.tex` depend on are of those two kinds (the `docs-v2b.md` and `docs-v2tex.md` reports).

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
3. **The derivation graph**: which sub-problem came from which, by which move, and what came back. It exists only as a small search tree for each job, and as a list of messages that no decision reads (§2.6). The tree has one to five sub-problems in the bootstrap's jobs (§2.6), and two or three on the specs that stay unsolved (§2.3).

Each is rebuilt on demand by a different host function, in a different shape, and discarded. That is why the same idea appears three or four times under different names (§2.2), why nothing persists across branches or jobs, why learned knowledge never reduces the number of candidates, and why reflection has nothing to read.

**Frames are not values.** A frame is the one place where rows, positions, and requirements live, and it is a host structure. So every operation on rows, positions, or requirements is host code, and a synthesized program can reach none of them. "Lift is not a synthesizer primitive" is one symptom. Pullback, fiber, quotient, partition, reorientation, and residual are the others.

A frame also holds one unknown per row. Constraints among several unknowns have nowhere to live, so they are weakened or carried on the side.

The remedy follows directly: store the three graphs, in one structure, made of things the object language can name.

## 4. Six perspectives on the same question

You asked for several perspectives. Each of these is a serious position on what the kernel's store should be. For each one, this section gives the claim, what the evidence says, and what this plan takes from it.

### 4.1 "The representation is fine; the budget was too small"

*Claim.* Keep frames. Run for hours.

*Evidence.* The budget was milliseconds (§2.3), so the premise is right. But §2.3 also showed that budget alone does not help. With hand-written help removed, a thousandfold increase in budget gave sound solutions to only two more of the sixteen specs, and on the four specs that stay unsolved the tree of sub-problems stayed a root with one or two children. Reach grows only with the logarithm of the work: each tenfold increase in work buys about one more AST node, or two with behaviour dedupe. Going from one second to ten hours is 4.5 tenfold steps, so it adds between five and nine nodes to the largest program reached.

The search-literature auditor built a model of enumeration from growth figures in the published systems, and then checked it against the program sizes that four published enumerators reached (EUSolver, Probe, TRANSIT and TF-Coder). It agrees with them to within about two nodes. The model is an estimate, not a published figure, and it assumes 10⁶ evaluations per second. It says that one hour of bottom-up enumeration with deduplication reaches programs of about 17 nodes when the grammar has 10 primitives (range 13–22), about 10 nodes with 30 primitives (8–13), and about 7 nodes with 100 primitives (6–8) **[L, estimate]**. DreamCoder needed roughly five days on 64 CPUs, which is about 7,700 CPU-hours, to rediscover fold and unfold from a fixed-point combinator. An hours-long budget on a single thread is about a thousandth of that **[L]**.

Note what that estimate says about where the leverage is. Over an hour, cutting the grammar from 100 primitives to 10 is worth about ten nodes. Multiplying the budget by 3,600 is worth seven and a half nodes at 10 primitives, and three at 100.

*Take.* Design the kernel's records, which are its trace, the syntax it retains, and its list of sub-problems, for runs of 10¹⁰–10¹¹ work units. Arrange the search so that more budget can add sub-problems to the tree, and not only longer expressions at its leaves. That needs three things: proposal generation that can be resumed, sub-problems that can be re-opened, and many small searches in place of one deep one. Treat the question of which library entries are tried on a problem as the main control problem. Choosing a small grammar for each problem would be worth about a factor of 12 if the choice were right, but the one way of choosing that was measured saved no more work than a control that ignores the task (§8.6). So this plan does not choose a subset of the library for a problem. Each operator carries a *verb table*, which records what the operator does to coarse labels of its inputs, and each candidate is tested against the labels of the target before it is evaluated (§6.4).

### 4.2 "Store the execution hypergraph literally and learn by rewriting it"

*Claim.* The most literal reading of your prompt: nodes are values, hyperedges are operator applications and tuples, and learning is pattern-directed graph rewriting.

*Evidence.* Uniform hypergraph stores have a poor record as learning substrates. OpenCog and its successor Hyperon span about 17 years **[L, from memory]**, and their own overview paper reports no quantitative benchmark **[L, abstract only]**. Algebraic graph rewriting tools, attributed C-sets, and interaction nets are representations, not learners **[L]**. The matching that each of them needs is conjunctive-query matching, which is hard in the size of the pattern (§2.8). And there is a structural objection specific to this project: evaluating one expression over N rows produces N isomorphic copies of one small graph. The regularity you want to find *is* that repetition. A store that materializes the copies must rediscover it by subgraph matching. A store that is factored by rows has it for free.

*Take.* The hypergraph is the meaning of the store. It should not be its layout. Store the factorization: pattern × rows.

### 4.3 "Use an e-graph: a law is a merge of two classes"

*Claim.* Keep terms in a shared graph with an equivalence relation. Apply laws as merges until saturation, that is, until no law adds a new equality.

*Evidence.* The store half is cheap and mature: hash-consing, union-find, and congruence closure sit in every SMT solver. The saturation half is the hazard. Under associativity and commutativity a sum of n variables saturates to 2ⁿ − 1 classes. The one production compiler built on e-graphs reports an average class size of 1.13 and about 0.1% benefit from keeping multiple representations; its gain came from hash-consing and eager directed rewrites. Binders inside e-graphs rest on one paper and one preprint, and conditional equalities inside e-graphs are the work of one research group **[L]**. In this kernel a different mechanism with the same intent, rewriting each candidate to a normal form with VM-interpreted rules, multiplied work by 385 with 80 laws (§2.4). That is evidence about rewriting during search, not about e-graphs.

There is also a point of theory that turns out to be the most useful sentence in the literature review: **e-graphs, version-space algebras, and finite tree automata are one data structure.** Classes are states; operator applications are transitions. They differ only in what a class means: "provably equal under these rules", or "same outputs on these examples". This is a research-level identification, not a shipped product **[L, abstract only]**.

*Take.* Keep the classes. Define them by observed behaviour on a set of rows, which needs no rules, no saturation, and no rebuilding. Treat a law as a statement that a class is real beyond its rows (§5.5).

### 4.4 "A frame is a small database"

*Claim.* Rows are tuples, and a frame is a relation. Lift, projection and fiber are unnest, project and group-by.

*Evidence.* This is the diagnosis of `plan_v2b.md`, and its claims about the code held up. Frames already are tables. Plan 2 and your own October outline both made the point that relations come before directions (§2.8). The standard relational operations have fifty years of shipped implementations, linear or n log n cost, and no research risk.

What the relational view lacks, on its own, is the other two graphs: it has no notion of a term that denotes a column, and no notion of a problem derived from another problem.

*Take.* This is the core of the proposal. Add terms that denote columns, classes of terms, and maps between tables.

### 4.5 "Keep everything in one flat vector space, as a transformer or cortex does"

*Claim.* You raised this yourself: neurons cannot be created per concept, so perhaps vectors should stay flat and high-dimensional, with context doing the composing.

*Evidence.* Nesting is not a problem of what a flat space can represent. Three results show it **[L]**. First, a tree can be embedded exactly in a flat space **[L, from memory]**. Give each edge its own axis, and the squared Euclidean distance between two nodes is then the length of the path between them. This takes one dimension per edge. Second, language models encode hierarchy as orthogonal subspaces. Third, a transformer that is shown a graph in its context reorganizes its representation toward that graph's spectral embedding.

The economics are the issue. A network can hold features in *superposition*, that is, with many features sharing the same neurons. A shared flat space of this kind saves *storage*: m features can be represented in O(log m) neurons. It does not save *computation*. For a broad category of problems, computing m features in superposition needs Ω(√(m log m)) neurons and Ω(m log m) parameters (Adler and Shavit; these are theorems about neural networks) **[L]**. So storing features in superposition is exponentially efficient, and computing with them is only quadratically efficient. A library of 10²–10³ entries has no storage pressure. Meanwhile every method that *learns* coordinates needs gradient descent and on the order of 10⁵ examples.

The paper you cited in the margin, arXiv 2611.17309, bears on this. Its model is small and represents the rules of the puzzle exactly, and its answers come from a very large number of very cheap moves. Its authors add that these benchmarks are too easy, and that learning latent quantities "remains an important open research direction". Your note on the paper said: "I don't think my assertion that much strength comes from fast evaluation is wrong. The information / bits certainly is not coming from anywhere else." For this paper that holds. An energy set by hand, with one distinct weight value, already solves every Sudoku test puzzle, and one with three values solves every maze. So the bits of the answer come from the search, which is fast evaluation of many cheap moves, and not from the model. That argues for an exact store with cheap evaluation, and not for a learned embedding. The two literature auditors who read the paper drew a narrower lesson from it: its space of hypotheses is tiny and matched exactly to the puzzle, and little of that carries over to program search (lit-search report, §9.3). Your note also said that "it took several years for it to become 'too easy'". The audit has no source on that point; the authors' remark is about what the benchmarks can show today. The details of the paper, and the full answer to your note, are in `plan_v2c_audit/revision-notes.md`.

*Take.* A flat space is the right shape for *ranking and filtering*, and the wrong place for truth. Use flat, explicit, recomputable features, which here are the labels of §6.2, as a layer over the exact store that ranks and filters (§6.4, §6.6). Defer learned coordinates until there is data to learn them from.

### 4.6 "A requirement is a cell of partial information; computation runs both ways"

*Claim.* The propagator view: every operator is a relation among cells, and information flows in whichever direction is known.

*Evidence.* Inverse semantics is shipped technology. The witness functions of FlashMeta are per-operator partial inverses, and they are load-bearing in commercial products **[L, abstract only]**. They are also written by hand, and learning them is open **[L]**. Running a general interpreter backwards does not scale. The relational interpreters of miniKanren synthesize programs in this way, and the authors of a 2025 paper on them say that interpretive overhead "makes the relational interpreter approach impractical for most applications". In the same paper's measurements, *staging*, which compiles a level of interpretation away before the program runs, made the benchmarks that run through nested interpreters 6 to 178 times faster **[L]**. In this kernel, pullback is already sound, and small (§2.1).

*Take.* Keep pullback. Treat an inverse as another orientation of an operator's own table, found by the dependency test and a small search (§5.3, §5.4; measured in §8). Never run an interpreter backwards.

Reentrancy is what your prompt called "freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph". One way to say what that means is a stack of interpreters, each interpreting the one above it. That is acceptable as a definition. It should not be how the kernel runs, because every level multiplies the cost. There are two ways out. The stack can be collapsed into one program before it runs, by compiling the upper levels away. That is the staging described above, which is also called lowering. Or there can be a single evaluator whose terms are allowed to mention terms, spaces and requirements (§7.1).

### 4.7 What each perspective covers

Each cell says how that perspective would supply the operation named at the left. The "Budget only" column is the present kernel, run for longer (§4.1). "Host only" means that the operation stays in host Lisp, as it is in the present kernel. "Research" means that only research systems do it; "(2026)" marks an operation whose first step in such a system was published in 2026. Bold marks, in each row, the perspective that the paragraph after the table names as the plan's source for it. The first row has none, because substitution is not special to any one perspective. The last row is not an operation: it says how mature each perspective is at the scale needed.

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

As §4.2 observed, evaluating one expression on N rows of input gives an execution graph that is N copies of the same small graph: the expression's own shape, once per row, with different values on the nodes.

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

**Class.** All the terms that denote the same column on a given space. A class stores three things: the column, once; the smallest term that denotes it; and an evidence grade (§5.5).

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
- One could have known that an inverse existed before searching for it. Any two rows that agree on `a` and on the sum also agree on `b`, so `b` is a function of `a` and the sum. Checking that takes one group-by. This plan calls the check the *dependency test*.

Nothing here is a special mechanism for laws or for solvers. Both are terms landing in a class.

**A lifted sequence function.** The task is `map-adjacent` with `+`: from `xs` produce the sums of neighbours. The space S has one row per example. The move is to make a second space S′ with one row per *output position*, and a map from S′ back to S.

| S′ row | parent row | `i` | `xs` (from parent) | target `y = ys[i]` | `(+ (at xs i) (at xs (+ i 1)))` |
|:--|--:|--:|:--|--:|--:|
| 0 | 0 | 0 | (3 1 4) | 4 | 4 |
| 1 | 0 | 1 | (3 1 4) | 5 | 5 |
| 2 | 1 | 0 | (2 2) | 4 | 4 |

On S′ this is an ordinary scalar problem, and a nine-node term solves it. On S there is one more scalar problem, the output length. The term that is also right for an empty list is `(- (length xs) (min (length xs) 1))`. `tabulate` builds a sequence from a length and a function of position (§7.1), so the program is `(tabulate (- (length xs) (min (length xs) 1)) (lambda (i) (+ (at xs i) (at xs (+ i 1)))))`.

No recursion was searched. The comparison with the kernel needs care. The kernel's `map-adjacent` takes the function as an argument, and without a hand-written skeleton the kernel does not find it in 2.8 × 10⁹ work (§2.3). The prototype finds the fixed-`+` version above in about a quarter of a second. It finds the function-argument version in about five seconds, on twelve of its own examples, and not robustly (§8.1). On the spec's own eight examples it returns an impostor if it accepts the first split by a guard that fits the rows. It returns the right program, in 64 ms, if a split is never accepted ahead of a smaller term without one (§8.5).

### 5.4 Your operations, on this store

"Re-index" below means: each row of S′ reads the cell of its parent row in S. "Collect" means the reverse: each row of S gathers the cells of its child rows, as a sequence or through an aggregate. In the Cost column, n is the number of rows of the space. Among the program forms, `select` is the prototype's form for keeping the elements of a sequence at the positions where a predicate holds; it is how the prototype writes `filter` (§8.1).

| Your term | What it is on the store | Cost | The program form it yields |
|:--|:--|:--|:--|
| Computation | evaluate a term over a space, giving a column | n per operator | — |
| Substitution | replace a leaf of a term by a term | size of the term | a call |
| Projection | drop columns; rows that become identical merge, leaving a map from the old space onto the smaller one | n | — |
| Fiber | the rows on which a column takes a given value; all fibers at once is a group-by | n | `where` |
| Lift over a container | unnest a sequence-valued column into a space of positions, with a map back; re-index the other columns | number of elements | `tabulate`, `select`, `scan`, `fold` |
| Lift as the reverse of projection | choose, per row, one member of the fiber. The choice is a new column, and costs log₂\|fiber\| bits per row unless a term predicts it | n | an index argument |
| Anti-unification | stack k terms as k rows of an *instance space*, one column per position. Constant columns are the shared pattern. Varying columns are the parameters, and varying columns that are equal are one parameter | total term size | a definition and k calls |
| Quotient | merge rows (projection), or merge terms (a class) | n | — |
| Partition, guard, conditional | a Boolean column; the sub-space of its true rows | n | `if` |
| Conservation, law | two terms in one class; or a term whose column is unchanged when re-indexed along an endomap | n | a rewrite, an invariant |
| Reorientation | test whether one column is a function of some others; if so, search for a term over those others that denotes it | n, then a small search | a solver |
| Residual | the column `r` with `y = decode(m, r)` for a target `y` and a model `m`. It is a column like any other | n | `decode(m, r)` |
| Tuple | a row is a tuple; a tuple-valued column splits into columns | n | `tuple`, `at` |
| Recursion | an endomap `s` on the space of calls. The function's column re-indexed along `s` is the value of the recursive call | n | a self-call |

Three remarks.

**There is one underlying description.** Lift, split, projection, anti-unification, and recursion all do the same thing: build a space, give it a map to a space you already have, and move columns along the map (re-index one way, collect the other). `plan_v2b.md` (its §7.3) listed six moves on its store, and you said of that list that several were "flavors of the same". On this store they share one description, with different maps **[P]**. The prototype implements it as three short routines and one helper, 22 lines in all, and uses them only for lifts over output and input positions. Its split used a separate index, and the instance, call, and derivation spaces are not built.

**Anti-unification separates into a pattern and a quotient.** Anti-unification finds the most specific pattern that several expressions share: it keeps their common skeleton and puts a hole wherever they differ. You wrote of it that "really it's a form of quotienting and trivial lifting under substitution". As intuition that holds. On the store the two halves separate: the generalization is the *shared pattern*, the constant columns of the instance space, and the quotient is the merging of terms that denote one column. (One categorical treatment, in a single paper, likewise makes the generalization a product and reserves the quotient for merging **[L, summary only]**.) Three refinements follow.

- *Shared holes are equal columns.* `(+ x x)` and `(+ y y)` generalize to `(+ ?0 ?0)`, not `(+ ?0 ?1)`, because the two varying columns are the same column. The kernel's `anti-unify` already does this (§8.5). On the store it is the class test, applied to the instance space.
- *The table is only as wide as the shared spine.* Positions line up into columns only along the constructors the instances share. Where operators diverge, the sub-terms below them have no common positions, and the whole sub-term is the cell. The exception is an operator that can itself be made a hole, which the kernel's `anti-unify` does when the two operators have the same type signature.
- *One class has many spellings, and the spelling decides the pattern.* The October results kept every expression's tree partly for this reason: expressions that agree on the rows may "expose different alignments for the anti-unification mechanism". If a cell holds one representative per class, anti-unification is normalize-then-generalize, which the kernel already does, and it can miss a pattern that another spelling would have shown. Taking every spelling into account means generalizing two classes rather than two terms. That is a product of two automata, quadratic in the corpus in the one published system that does it **[L]**.

So anti-unification over one representative per class is a heuristic, not anti-unification modulo the store's equivalences. The full version is a search across spaces in the sense of §5.9. It is deferred to Stage D, the last of the four stages in which this plan is to be built (§11.3). The trail measured why the cheap version is still worth having: normalizing expressions by known laws before anti-unifying gave a pattern with fewer holes (§2.8).

**Depth-two experiments are spaces whose cells hold terms.** In October you asked for experiments on operators composed "up to (say) depth=2" (§2.8), and your current prompt says that "depth >= 2 experiments" show "that expressions themselves can be abstracted over in the same way". This plan reads the second statement as experiments whose inputs include functions. That reading is the plan's own. A space whose rows range over `(f, g, xs)`, with `f` and `g` drawn from the classes of some smaller space, lets `(map f (map g xs))` and `(map (compose f g) xs)` fall into one class. A cell that holds a function is a reference to a class elsewhere, so two such cells are equal when the functions behave alike. This is the "folded and recursively nested" structure you describe: nesting is a cell that points into another space. It is untested, and it is one of the places where the literature offers no precedent (§10) **[P]**.

### 5.5 What a class means, and why sampled knowledge can prune

Plan 8 recorded that sampled evidence "can propose and never eliminates", and the audit confirmed the consequence: on the integers, nothing the kernel learns ever reduces the search (§2.4). That constraint is real but it is narrower than it has been treated.

A class is always a class *on a space*. Three grades:

- **Observed**: the same column on this space. This is exact, not sampled, for any question about this space. Two terms in one class are interchangeable as sub-terms of any program that is judged on these rows, so enumeration can keep one and build only from it. No law, proof, or certificate is involved. The one condition is that the sub-term is evaluated on that space: a term under a `tabulate`, or inside a recursive body, is evaluated on the position space or the call space, and its class is taken there.
- **Tested**: the two terms also have the same column on several fresh spaces that include boundary values. A tested class may be used wherever a mistake would cost only time or a missed answer. It may never be used where a mistake would make the kernel accept something false. Its uses are ordering the enumeration, normalizing terms before anti-unification, and proposing a decomposition. The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are knowledge of this grade (§6.4).
- **Certified**: exhaustive on a finite domain, derived from certified laws, or a declared axiom. Needed only to eliminate an alternative for all inputs: to commit to a solver's answer without a fallback, or to drop a guard.

The kernel's evidence record (73 lines), its tentative-then-fallback discipline, and root verification of every finished program all carry over (§9). What changes is that the first grade, which is where almost all pruning comes from, stops waiting on the third.

The same distinction, between agreeing on the task's rows and agreeing on fresh rows, suggests a check for the `foldl` problem of §2.3, in which a program fits the spec's rows and is wrong **[P]**. A *probe space* is a space whose rows the kernel makes up for itself in order to test terms; its rows do not come from a task. If the programs that fit the task's rows fall into different classes on a wider probe space, then the task's rows do not determine the answer, and the task is underdetermined. The check is not free: a class keeps only its smallest term, so the rivals must be kept or rebuilt, and evaluated a second time. The prototype does not do it. In its 135 default runs on its own rows it returned one impostor as an answer (§8.1), and on the kernel's much shorter spec rows it returned several (§8.5). Today the problem surfaces only as a wrong answer on held-out data.

A **guarded law** has a simple representation: it is a class on a sub-space. Two terms that differ on S but agree on the rows where a Boolean column `g` is true are one class there. Finding guarded laws is another matter. Published systems search guards only to about four nodes, and only with pruning by implication between guards, without which the search does not finish in hours **[L]**. The prototype tested unconditional laws only. In Python, for four laws, the weakest valid guard was picked out of a pool of candidate guards (§8.7). The October results put the same idea from the other side: a guard is what a law leaves unresolved (§2.8).

### 5.6 Requirements are terms with holes

A frame row carries a predicate over one unknown. Here, a **requirement** is a Boolean term over known columns and any number of **holes**, which must come out true on every row of a space. A frame is the one-hole case.

- *Pullback* through a decoder is substitution of the decoder for a hole. The kernel does this on frames, in `pullback-frame` (§2.1; `frame.lisp:544`). Plan 3 already defined the requirement on a child problem by a pullback of this kind: a value z is allowed for the child exactly when the decoder, applied to z, gives a value that the parent's requirement allows, or B(z) ⇔ A(d(c, z)) (`deprecated/plan3.md` §3). The document auditor reads that as a definition of lift (docs-origins report). Here it is re-implemented on terms, against the same soundness tests (§9).
- *Coupled constraints*, the thing a frame cannot hold, are requirements with two or more holes. They are stored like any other term.
- *Splitting* a requirement is what each program construct does to it (§7.2): a tuple splits it by slot, a conditional by sub-space, a tabulation into a length requirement and an element requirement on the position space.

Because a requirement is a term, it is a value of the object language, so lifting a requirement can be an operation of that language **[P]**. Neither earlier plan made it one (§2.9). This plan has not built it either: the prototype's goals are host predicates.

### 5.7 The three graphs, stored

- The **execution graph** is the term graph together with the columns: every intermediate value of every evaluation, shared.
- The **equivalence graph** is the classes, per space.
- The **derivation graph** is a space like any other: one row per problem posed, with columns for the parent problem, the move, the work spent, and the outcome (§7.4).

### 5.8 What is and is not new here

Each piece has shipped precedent: hash-consed terms; value vectors with observational-equivalence classes, the backbone of every bottom-up enumerative synthesizer; relational tables with unnest and group-by; law discovery by collision, as in QuickSpec. In standard terms, as the outside review puts it, the classes on a space form a deterministic bottom-up tree automaton, equivalently a ground e-graph, indexed by the space; and spaces with their maps and columns are what the database literature calls an attributed C-set, which is also the core of `plan_v2b.md`. The search-literature review's own recommended recipe, assembled only from shipped or independently replicated parts, overlaps this list (lit-search report, section B).

The outside review also names what separates this plan from the earlier v2 plans. They tried to put *intensional* equality, true for all inputs, with binders and conditions, inside the store's merge relation. This plan merges only on *extensional* equality, on a concrete space. That is what makes the store cheap, and it is exactly what moves the hard part to §5.9.

This plan differs from the published recipe in one respect that matters. The decisive step of the published recipe is pruning the set of all terms with laws already found, and dedupe by behaviour comes second. This plan relies on classes for pruning, and it keeps a law only when something reads it (§8.8). The reason is the kernel's own measurement that rewriting during search cost more than it saved (§2.4). What the choice costs is not yet known. Experiment X1 (§11.2), which runs law discovery on the new store, should measure it.

Three things are this plan's own and are marked as such throughout:

1. using *spaces with maps* as the lifting mechanism inside a synthesizer (nearest precedents: deduction through `map` and `fold` in λ², and array languages);
2. finding inverses by a dependency test on an operator's own table followed by a small search. Inverses do appear in the literature, as laws of the form g(f(x)) = x found by testing and as structural inversion from a table of primitive inverses. What has no precedent is a synthesizer learning the inverse rules it then uses; those are hand-written in every synthesizer that the literature review checked;
3. keeping all three graphs in one structure so the search can read its own record.

§8 measures the first two on a prototype.

### 5.9 Within a space, and across spaces

The store merges two terms only after evaluating both on one space. The outside review named what that trades away: carrying an equivalence to syntax that has not been evaluated, or to another space. Your note on it was that this "is a fundamental limit for compression and needs to be allowed". This section takes that as a requirement. No primitive of the store needs graph matching. The system as a whole does, and the difference is the subject here.

**Within a space, everything is computed.** Given a space and the maps it already has, the operations are evaluate, hash, group, re-index, and collect. Each is linear in the cells it touches. A class is found by hashing a column. Nothing is searched for except the term itself.

**Across spaces, nearly everything has to be found.** Whenever two things are not already joined by a map, relating them means finding a *witness*: a concrete object, such as a map, a substitution or a pattern, that shows how the two are related. Checking a witness is cheap. Finding one is a search, and in the worst case a hard one.

| Question across spaces | The witness | Checking it | Finding it |
|:--|:--|:--|:--|
| Does this equality, seen on one space, hold on another? | none | evaluate both sides there | no search; the outside review calls this "probe evaluation" |
| Is this term an instance of that pattern? | a substitution | substitute and compare | linear for a tree pattern; NP-complete modulo associativity and commutativity, or when the pattern shares structure |
| Which rows of S go with which rows of T? | a map | re-index and compare columns | a hash join when some term computes a key; graph matching when none does |
| What do these k terms, or these k derivations, have in common? | a pattern and its substitutions | substitute | linear on trees; quadratic over classes; choosing which subsets to generalize, for the best total compression, contains the smallest-grammar problem, which is NP-hard **[L, from memory]** |
| Is this problem like that one? | a map between their spaces that carries one problem's columns to the other's | re-index and compare | homomorphism search, NP-complete in general |
| Does this operator act on a coarse description of its inputs? Is this operator like that one? | a quotient of values (§6.2) and its small table; or a map between two operators' tables | the dependency test, one group-by | enumerate small terms |
| Which library entries belong in this problem's grammar? | a subset | try it | exponential in the library |

So the split you describe is exact. Computation within a space is deterministic and polynomial. Search across spaces is NP in the textbook sense: the answer is easy to check and may be hard to find. And compression lives on the second side, because shared structure between two contexts *is* a witness of one of these kinds. A store that only ever worked within spaces could compress each space separately and nothing more.

Three consequences shape the design.

**1. A witness is a store object, so finding one is an ordinary problem.** A row correspondence is a map, which is a column. A substitution is the varying columns of an instance space. A pattern is a term. Finding any of them is therefore a requirement with a hole (§5.6) whose hole has the type of a map or of code, and the synthesizer's one move (§7.2) applies to it. Once found, the witness is stored, and from then on moving along it is computation. The search is paid once. The witness's own description length is what the compression has to repay.

**2. There are three ways to find a map, and they should be tried in order of cost.**

- *By a term.* Some term computes, for each row of S, a key that identifies a row of T. Candidates are ordinary terms, enumerated by class; checking one is a hash join. When a key term exists, crossing spaces costs no more than working inside one. Position i of an output going with position i + 1 of an input is this case. So is an analogy between two operators carried by a function: `max` goes to `min` under negation (§8.6).
- *By refinement.* No key exists, so rows must be told apart by how they are connected. Give every row a colour; repeatedly recolour each row by the group-by key of its own cells and the colours of the rows it reaches through maps, until nothing changes; rows with a colour of their own are matched. This is polynomial, and it uses only group-by and re-index. It is a walk over the graph: a colour that flows along verified links, as in your phrase "proximity flows along verified topological links".
- *By backtracking.* Rows that refinement cannot separate look alike to it: either they are truly interchangeable, or the structure is too regular for colours to tell them apart. Pick one, try each pairing, refine again, and back up on contradiction. This is the graph isomorphism test that your prompt said might be needed. It is exponential in the worst case. In §8.6 it was needed for regular structures that have no symmetry, and to reject look-alikes that are not isomorphic.

For matching a pattern into a larger structure, rather than pairing two whole spaces, the finding that plan 2 recorded in October holds (§2.8): tree-shaped patterns can be matched in polynomial time, as a sequence of joins, and patterns with cycles are the hard case.

One piece of the prototype was already a search across spaces, and it should be read as one. A *selective* function, such as `filter`, keeps some elements of its input and drops the rest. To lift it, each position of the output has to be mapped to the position of the input that its element came from (§7.2). For each output position, the candidates are the input positions that hold the wanted value. These are the index sets of the `gather` rule (§7.2). One candidate has to be chosen for each position, and there are three ways to choose. If a term fits, the term makes the choice; a shift is an example. If a constraint applies, the constraint makes the choice; here the constraint is that the indices increase. Otherwise the choice is paid for, at log₂|fiber| bits per row. The subsequence aligner in the prototype is the second of these ways, written by hand.

**3. The expensive choice is which pairs to try, and that is the job of the cheap geometry.** With n problems there are n² pairs to relate and 2ⁿ subsets to generalize over. Your October outline, which still stands in `prompt4.md` (L170–175), said this in advance. It says that "the quotienting-AU problem" (AU is anti-unification) is a subgraph isomorphism problem that is "structure & type-aware & locality-seeded". It goes on: "This is NP-hard, think, and yet some of the search can be amortized". And it suggests how: "Hypothetically through the development of a vocabulary / short descriptive language". Plan 7 proposed to seed anti-unification in the same way, using graph distance between library entries to choose the pairs (`plan7/plan7-library.md` §2.2.3), and never built it.

On the store, four cheap signals can say which pairs are worth trying. The first is agreement between the labels of two problems' columns (labels are defined in §6.2). The second is the cost of one column given another (§6.1). These first two are the two resolutions of §6.2, coarse and full, pointed across spaces. The third is the colour histograms of two spaces, from the refinement above. The fourth is a count of which pairings paid off before. A count of pairings has not been measured. The counts that were measured, of how often each operator was used, said nothing about an entry not yet used (§8.7), so a count can only adjust what the other three signals propose. A signal can be used in two ways, and the two are not equally strong. An invariant that differs between two spaces *refutes* a correspondence outright, in polynomial time. Agreement only *suggests* one. So the cheap layer rules pairs out with certainty and proposes pairs without it, and the exact search runs only on the pairs that survive.

One of the four signals has been measured, and so has one alternative to choosing pairs at all. Comparing whole problems by the properties they share finds problems of the same *form* at three times chance, and does not find the *operators* a problem needs; it saved no more work than a control that ignores the task (§8.6). What did save work avoids choosing a subset at all. Each operator carries a small table of what it does to labels, and each candidate is tested against the target's labels before it is evaluated (§8.7). That table is found once per operator and read in every later search. It is amortization of the kind your outline describes, shown so far for the enumeration of terms and not yet for matching or anti-unification. The other three signals have not been measured as a way to propose pairs. §6.4 builds on the tables.

**How the two kinds of work are budgeted.** Work within a space has a cost known before it runs. A search across spaces does not: §8.6 has a pair of 30-row structures that took 257,214 backtracks to tell apart. So the two are budgeted differently. Work within a space is simply done. Every search across spaces runs as a tentative attempt on its own account, with a cap, under the reserve rule the kernel already has (three parts tentative to one part fallback, §9). Experiment X9 tests this arrangement (§11.2). Once the derivation space exists, in Stage D, the cost and the yield of each attempt are rows of it, so the share of an hour that goes across spaces is itself something the kernel can measure and adjust **[P]**. The order of attack is fixed by cost. First refute with invariants. Then propose pairs with the cheap signals above, labels first. Then try a key term, then refine, and only then backtrack.

**What allowing this costs.** Four pieces of machinery are needed. The first is refinement and backtracking, which were 36 and 65 lines in the version measured. The second is matching of tree-shaped patterns, which is a sequence of joins. The third is anti-unification over classes instead of over single representatives, which §5.4 prices and defers to Stage D (§11.3). The fourth is a way to choose what to abstract. The kernel's existing abstraction code, which accepts an abstraction only when it shortens the total description, can be carried over for that (§9).

**Where it enters the stages.** The plan is to be built in four stages, A to D (§11.3). Stage A, the store core, works entirely within spaces. Stage B adds requirements with holes and spaces with maps. It crosses between spaces only along maps that it builds itself, except for the selection case above. Stage C is the first stage in which the outcome depends on a choice of what to bring together. There, many library entries are in scope at once, and the outcome depends on which of them a search tries. The plan does not select a subset of the library for each problem, because the one way of selecting that was measured saved no more work than a control that ignores the task (§8.6). Each candidate is instead tested against the labels of the target, through the tables of what each operator does to labels (§6.4). Those tables are first used in Stage C. Analogies between operator tables are found there as terms (experiment X9, §11.2). Stage D works across spaces throughout: it abstracts over solutions, and it looks for depth-two laws.

## 6. Geometry

You consider the geometry question open, and it is. This section says what the evidence supports now, what it does not, and how the store leaves room for more.

Geometry has three jobs in this kernel: pricing residuals, guiding search, and language. They look like three mechanisms, and earlier plans built them as three. The argument of this section, which you and the outside reviewer arrived at, is that they are one question asked at two resolutions. The measurements of §8.7 support part of that and correct part of it, and the text says which is which.

### 6.1 One question: what does one column cost, given others?

Every use of geometry in this plan asks the same thing about columns on one space:

> How many bits does it take to write column B, once columns A are known?

Call the answer the *cost of B given A*. The distance from a column `u` to a column `v` is the cost of `v` given `u`. When the cost is zero, B is determined by A. When it is small, B is nearly determined, and what is left over is a *residual*: the part of B that A does not account for, which is itself a column.

The store answers the question by three computations. Each suits a different situation. All three give an answer in bits, so their answers can be added into one description length.

**By equality.** The simplest case is two columns that are the same. The store finds these by hashing: every column is hashed into its class (§5.2), and two terms whose columns collide cost nothing given each other. This is how laws are found.

**By counting, over groups.** Group the rows by their cells in A. Within each group, look at the cells of B. If every group shows a single value of B, then B is a function of A on this space, and the table from group to value is that function. This is the dependency test of §5.3, and it is one group-by. If some groups show several values, the cost of B is the number of bits needed to say which value each row has, given the counts in its group. Counting needs no knowledge of the value type. What it needs is many rows per group. On eight rows whose cells in A are all different, every B is "determined" by A, and the statement is empty. So counting is used where groups are large: on a probe space of thousands of rows, or after the values have been coarsened into a few labels (§6.2).

**By correction, row by row.** The kernel's codec assigns every value a prefix code. It also has a correction rule for each type of value, which prices a value when a prediction of it is given. For an integer, the rule codes the difference between the value and the prediction with a universal code, so the price grows roughly as the logarithm of the difference. For a Boolean, a wrong prediction costs one bit. For a sequence, the rule charges a correction for each position and a further amount for a change of length. For code, the rule charges for the edit that turns the predicted expression into the true one, which it finds by anti-unifying the two. For example, suppose a candidate's column is `u` = (7, 5, 4, 0) and the target is `y` = (8, 6, 5, 1). Each row is off by one. A difference of one costs 4 bits in the present integer code, so `y` costs 4 × 4 = 16 bits given `u`. Given only a prediction of zero on every row, `y` costs 29 bits. These per-type codes are the basic sense in which two things are close. They work on a handful of rows, because each row is priced on its own.

So the price list and the distance are one object. The price list, which earlier plans called the tariff, says how many bits a correction costs. The distance from a prediction to a value is that same number of bits. Plan 7 said the same of decoders: "A metric and a decoder shell are two views of one correction code."

Measured on the kernel's own functions (§8.5), the present correction codes behave as follows. Integer distance is symmetric, and it grows as the logarithm of the difference; the table in §8.5 gives the bit counts. Because it is concave in the difference, two things follow. The distance does not come from a vector space, so the average of two values and the angle between two differences have no meaning under it. And an error concentrated on a few rows costs less than the same total error spread thinly over all rows, so the code prefers a candidate that is exactly right on most rows and far off on a few to one that is slightly off everywhere. Sequence and code distances are strongly asymmetric: building costs far more than erasing, as the counting identity of §6.3 says it should. And on sequences and code, once element values are large, the present prices break the triangle inequality on some triples, where going through a third value is cheaper than going directly. That marks where the present correction code is looser than it could be.

### 6.2 Two resolutions, two outcomes

A **quotient** of values is a small term that takes a value to one of a few **labels**: `(sgn x)` gives the sign of an integer, `(mod x 2)` its parity, `(min (len xs) 5)` the length of a list up to five. It is the quotient of §5.4 applied to values instead of rows: values with the same label are merged. A Boolean property is the two-label case. Looking at a column through a quotient keeps a little of each value and discards the rest. A quotient that the kernel keeps in its vocabulary is called a **word**. So "sign" is a word, and "negative", "zero", and "positive" are its labels.

For one operator and one word, the operator's **verb table** records which output labels were seen to follow which combination of input labels, with counts. It is got by running the operator on probe rows and counting.

The question of §6.1 can be asked of the values themselves or of their labels. Call these the two *resolutions*. At either resolution the answer is "nothing is left over" or "something is". That gives four cases, and each is something the kernel needs. Each cell below also says which of the three computations of §6.1 answers it.

| | Nothing left over | Something left over |
|:--|:--|:--|
| **Full resolution:** the values themselves | An exact fact about the space. Two terms with one column are a *law*, and a column that is unchanged when re-indexed along a map is an *invariant*; both are *computed by equality*. An argument that is a function of the result and the other argument has an *inverse*, perhaps only on the rows where a guard holds (§5.3); *computed by counting*, followed by a small search for the inverse's term. | A *near miss*. A candidate's column is close to the target, and the leftover is a residual column (§6.3). It proposes a change to the candidate, or a guard for the rows where the two differ. *Computed by correction.* |
| **Coarse resolution:** their labels | An exact fact about labels. In the operator's verb table, every combination of input labels was followed by exactly one output label. The parity of a sum is determined by the parities of its parts, and doubling a non-empty list always gives a list whose elements are all even. *Computed by counting.* "Exact" here means exact on the probe rows; §6.5 says how little of this can be proved. | A *tendency*. Some combination of input labels was followed by more than one output label, and the counts say how often each occurred. Filtering a list says little about the parity of what remains. *Computed by counting.* |

The left column holds what the kernel can come to rely on, and the right column holds what it can use to steer. The top row sees a few rows of data exactly. The bottom row sees a whole operator roughly.

**How far the four cases are one mechanism.** Earlier plans built these as separate machinery. For the top left they had law discovery and solver search. For the top right they had residual pricing (§2.7) and a distance from a candidate's column to the target, which they called "behaviour distance". For the bottom right they had property sets, which are sets of yes-or-no properties of a problem (§8.6), and counts of past use. For the bottom left they had nothing. The outside review's claim is that all four are one group-by. That was tested by writing the one routine and running it on each case **[M]** (report `verify-handoff.md`, Appendix D).

- For exact facts about labels and for tendencies the claim holds exactly. One routine of 30 lines groups rows by some columns, looks at another column within each group, and returns the table. Given labels it returns the verb table, and nothing else is needed. For inverses the routine supplies the first step only. Given the table of `*` it reports that an argument is determined on 92.3% of the rows, as §8.2 found. The guard `b ≠ 0` was then picked from a pool of thirteen candidate guards, and the term `(div c b)` was found by a small search. Those two steps took 9 and 18 further lines.
- A law is a stronger statement than the routine tests. That one column is a function of another is true of `x + 1` and `x`, which are not equal. A law is two terms with the *same* column. Equality is as cheap as counting, but it is a different computation.
- A near miss is not a group-by at all. On a task's few rows, grouping by a candidate's values "determines" the target for more than half of all the classes in a bank (54–56% on eight rows, 81% on four), and it does so for a far-off term whose values are all different as readily as for a near miss. So counting says nothing about nearness. A near miss is measured by correction. The correction code is defined for any two values, because it can pay for a change of length or fall back to the plain code of the target. What is often not defined is the element-by-element difference from which an offset or a scale is read (§7.2). That needs two values of the same type and length, and it was undefined for 41–43% of the classes on the path one step from an answer, in the sense that is defined two paragraphs below.

So the design has one question, two resolutions, and three computations. Counting serves three of the four cells, at both resolutions, and one routine is its core. Equality and correction serve the rest, and only at full resolution.

**What labels can see, and what corrections can see.** The outside review also argued that labels see several steps ahead while corrections see only the last step. That is not what was measured **[M]**. The measurement was made in Python, on the library of 61 operators written for these experiments (§8.7). Call the class from which the answer is in fact built by one more operator the *true parent*, and call every class of the true parent's size a class *one step from the answer*, whether or not any operator takes it to the target. Among the classes one step from the answer, the labels ruled out nearly half. Among classes two or more steps away, they ruled out none. They never ruled out a class on the path to the answer, though in 3 of the 234 tasks a wrong table entry ruled out the last step itself. Corrections carried a signal at every distance: usually a strong one next to the answer, a weak one further out, and nowhere one reliable enough to discard classes by. So with the vocabularies tried, labels are a sharp test of the *last* step only, and corrections give a ranking of all classes that cannot be cut on.

The two do complement each other next to the answer. For a quarter of the true parents the labels left the true parent tied with other classes, and in about half of those ties the correction ranked the true parent first, where chance would give a little over a third. A correction can also do one thing that labels cannot. When a candidate differs from the target by the same amount on every row, the residual is a constant, and the constant names the last step outright.

How a search uses the two is in §7.2.

### 6.3 Full resolution: pricing and residuals

Start from the counting identity in plan 2: H(X) = H(f(X)) + E log|fiber|. The *fiber* of an output is the set of inputs that give that output. In words, the identity says that the information in an input is the information in the output, plus the bits that say which member of the fiber the input was (§2.8). Running `f` forward destroys those bits. Running it backward means supplying them.

Five rules follow. The first four are standard coding theory, confirmed by the literature review; the previous plans stated the first three but gave no procedure for using them.

1. **A verified bijection transfers code lengths for free.** If two spaces or two value types are related by a map with a checked inverse, a residual costs the same on either side.
2. **A many-to-one map owes the fiber.** Pricing on the coarse side costs an extra log₂|fiber| bits per row to name the member, or the bits of a term that predicts it.
3. **A new latent column is paid for adaptively.** A latent column is one that is not in the data and that a model introduces, such as the cluster each row is assigned to, or an index chosen for each row. It is coded cell by cell, each cell using the counts of the cells before it. This is a valid code because a decoder can rebuild the same counts. It is also what makes count-based or nearest-neighbour predictors safe to use for pricing.
4. **The graph gives the coding order.** Code the columns in dependency order. A column that a term derives from earlier columns costs only the bits of the term. A column that no term derives is called *underived* here, and it costs the full code of its cells. The total over all columns is the description length.
5. **An exact cell does not cost zero.** Suppose a cell that matches its prediction costs zero bits while every other cell pays a full prefix code. Then the code breaks the bound that every prefix code obeys: the sum over all code words of 2 to the power of minus the length exceeds 1. So in a column priced row by row, the zero correction must have a code word of its own, and an exact cell costs at least one bit. One more bit per column can then say that the whole column is exact. The kernel avoids the violation in its main pricing path only because it lists exception rows with their indices, and what it leaves unpaid there is one bit per model. A store that prices a residual column row by row would not avoid it (§8.5).

Rule 4 is the precise sense in which topology and geometry interlock: **the graph is the factorization of the description, and the geometry is the code on each factor.** A move is good when it replaces an expensive underived column by a term plus a cheaper underived column.

**Is there something better than pricing in the ambient space?** You asked this directly. The ambient space is the problem's original space, and an induced space is one derived from it by a move. The theory says that pricing in an induced space never makes a residual truly cheaper than pricing it in the ambient space. A price found in an induced space is valid in two cases only. If a verified bijection relates the two spaces, the price is the same on both sides (rule 1). If the map is many-to-one, the fiber bits of rule 2 must be added. What an induced space can do is make the residual smaller or more regular, so the same ambient code is shorter; and counts can replace a fixed code with an adaptive one. So ambient pricing is not what made residuals clunky. Three facts about the present implementation did (§2.7).

- The code has eight unrelated representations of a residual. The store has one: a residual is a column.
- A frame's metric cannot depend on the row. On the store, the code of a column can depend on any earlier column, and so on the row.
- A sub-problem's score adds two numbers measured in different places: the bits of the program, measured at the root, and the bits of the residual, measured in a child space. The fix is to move the child's residual back along the map to the root, and to price each root row once.

**A small residual is not yet structure.** In plan 1's measurement, from a scratch script that was never committed, the correct lift ranked 66th of 2,661 by residual size. So the size of a residual should rank a proposal only together with its *regularity*, and the reliable test of regularity is exact: does the residual column fall in a class with a small term, such as a constant? A residual that is small and irregular is noise that happens to be small. A residual that is regular is the next problem to solve, and §7.2 says where in a search that is used. The outside review proposed a coarser test as well, whether the residual's labels are the same on every row. Measured, that helps for exactly one case, a constant offset. On ordinary tasks it misled a little more often than it helped, and on conditionals it only misled (§8.7). It is not adopted as a general ranking.

### 6.4 Coarse resolution: words and verb tables

This is the language arm of the kernel, and the reason it belongs in a section on geometry is in your October outline (`prompt4.md` L174–203). You wrote there that matching across frames "is NP-hard, think, and yet some of the search can be amortized", "Hypothetically through the development of a vocabulary / short descriptive language". And you wrote what such a language is for: "A language enables compositional description of the labeled computation", "In a form that is shorter and cheaper than executing the function / rule / algorithm itself. Thus it is a form of heuristic." Read against §5.9, that is a design: **language is the amortization of search across spaces.** The bottom row of the table in §6.2 is its mechanism.

**Your three word types.** They correspond to three objects in the store.

| Your word type | The store object | Its meaning | Cost |
|:--|:--|:--|:--|
| 'like' | a word, that is, a quotient of values (§6.2) | its labels are what the word can say of a value; two values with the same label are alike in that respect | one small term per value |
| 'action' | a verb table: for one operator and one word, the table from the labels of the inputs to the labels the output was seen to take, with counts | what the operator does to descriptions | one group-by over probe evaluations of the operator, once, when the operator enters the library |
| 'analogy' | a map that carries one operator's table onto another's: negation carries `max` to `min`, because `neg(max(a, b)) = min(neg(a), neg(b))` | "as A is to B" is the map; "so C is to ?" is the map applied to C | one equality, checked over the rows |

The three are closely related. Say that an operator *respects* a word when the label of its output is determined by the labels of its inputs. Such a word is a map that carries the operator's large table on values onto a small table on labels, and that small table is the operator's verb table. An analogy is a map of the same kind between the tables of two operators. (§8.6 tested 350 candidate maps between operator tables in 1.3 ms, and 29 held, 12 of them between two different operators.)

**A description is a run on labels.** The description of a value is its labels. The description of a program is what comes out when it is run on labels through the verb tables: a few look-ups, with no data touched. That makes your sentence literal. The description is shorter than the computation, since a label is a few bits, and cheaper, since a step is a look-up.

**The same thing in other terms: a learned type system.** A type says what kind of value something is, and an operator's type signature says what kinds it takes and returns. A word refines a type: not just "a list of integers" but "a sorted one", "one with no negative element", "one of length three". A verb table is then a refined signature that the kernel has inferred from examples: `sort` returns a sorted list whatever it is given, and `reverse` returns an ascending list only when given a descending one. Checking a candidate against the target's labels before running it is type checking. This is why the mechanism is cheap, why it helps most on the last step of a program, and why it can be wrong: the signatures are inferred from samples, not proved. Types alone, with no vocabulary, are the degenerate case.

**What it buys in search [M]** (§8.7). The measurements are in Python, on a library of 61 operators written for these experiments. The baseline is *plain search*: bottom-up enumeration of terms by size that keeps one term per class and uses no guidance. A *candidate* is one operator applied to classes already found. The *gain* of a method is the number of candidates plain search evaluates, divided by the number the method evaluates.

- With six words listed by hand, the gain is 14× to 18×, depending on the set of tasks. Types alone gave 1.7×. The search also takes 1.3 to 4 times less time, and the saving in time is larger at larger program sizes.
- The tables work for an operator that has never appeared in a solved task, because a verb table needs only the operator's own probe rows. Counts of past use do not work for such an operator. When counts were used to set the order of enumeration, so that a rarely used operator is reached late, 5 of the 8 tasks that need such an operator ran past the cap of three million candidates. Used only to order the operators within each size, counts still gave 1.7× and 3.1× on those tasks.
- Used only to *order* the operators, with nothing skipped and so no answer lost, the tables give a gain of 6×, against 2.6× for counts.

None of these runs has the plainest control, which is to compare each candidate of the last size with the target one row at a time and stop at the first mismatch, with no tables. In the store prototype that control cut candidates exactly as much as ordering by labels did, and took less time (§8.7). Whether it would match the gains above is not measured.

**What it does not buy [M].** Five limits were measured, and they shape §7.2.

- *It is tested knowledge, not certified.* A verb table is learned on a probe space and read on a task's space. That is knowledge carried across spaces without being re-checked there (§5.9). It is of the tested grade (§5.5): it has held on the probe rows, it is not proved, and so it may be used only where a mistake costs time or a missed answer. A filter built on the tables is therefore a tentative first attempt with a fallback, never an elimination. §6.5 says how often the tables are wrong and what reduces it.
- *It acts on the last step* (§6.2). The gain was accordingly a constant factor and did not grow with program size: it was between 11× and 16× for programs of 3 to 6 nodes, with no trend.
- *A filter applied strictly at one size loses near misses.* A candidate that is right on most rows and wrong on a few fails the labels on exactly the rows it gets wrong. In the store prototype, a filter applied strictly at the size where a conditional would have been built lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted. With a size bound that is raised round by round, the branches were not lost: in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test asked only whether the two branches were kept. It did not ask whether the guard was kept as well, or whether the conditional was then put together. §7.2 uses the second arrangement.
- *It saves much memory only in two situations.* One is pure ring arithmetic. The other is a *look-ahead*, which declines to store a class that cannot reach the target within a size bound, and which needs a firm bound to work with (§7.2, §7.6).
- *Averages flatter it.* In one run of 234 tasks, with tables built from 2,000 random probes per operator, the filter lost 3 answers, two of them on larger tasks. The gain averaged per task was 16×. With the three lost tasks retried by plain search, the saving summed over all tasks was 12.7×. The kernel's *reserve* rule gives three parts of a budget to a tentative attempt and keeps one part for the fallback (§7.2), and under it a lost task costs four times its plain search. Under that three-to-one reserve the saving was 6.6×, against 12.1× under the same reserve had nothing been lost (report `verify-handoff.md`, Appendix D).

**The same words and tables serve five other purposes.**

1. *Guards* (§5.5). A guard is a two-label word. So a vocabulary is also a stock of ready-made guards. Each word enters a guard as a single leaf, however large the term behind it, and that matters because published guard search stops at guards of about four nodes **[L]** (§5.5). A word with several labels generalizes this: a word with k labels splits a space into k sub-spaces at once **[P]**.
2. *Requirements, coarsely* (§7.2). An operator with an exact inverse lets a requirement pass backward through it exactly. A verb table lets a requirement pass backward through *any* operator, coarsely: the labels of the argument must be among those the table takes to the labels required of the result. The filter above is one step of this, and that one step is all that was measured. Passing a requirement back through several operators is proposal **[P]**.
3. *Exact facts about labels* (§6.2, bottom left). On `+ − * neg`, reduction modulo a small prime is exact. In the Python experiments it is the clearest case of labels cutting stored classes by an order of magnitude **[M]**.
4. *Likeness between operators.* Operators with nearly the same tables behave alike. Of the 32 operators placed by hand in seven families, there are 22 for which the operator with the nearest table belongs to the same family, where chance gives 9 **[M]** (report `verify-quotients.md`, Appendix D).
5. *Descriptors of functions.* The present kernel describes each library function by a fixed menu of ten yes-or-no properties written in its source (`descriptors.lisp`) **[C]**. Those are words listed by hand, and the vocabulary replaces them **[P]**.

**The order of names, and their price.** Plan 7 asked for names "whose usage probabilities and context affinities are coupled to the search policy and language tariffs". The measurements separate two things that request runs together. The *order* in which operators are tried should come from how well their verb tables fit the labels of the problem at hand: that is the ordering above, and it works for new operators. The *price* of a name in bits, which is used only at acceptance to compare programs that fit (§7.2), can stay a prefix code built from counts of use, as §7.1 has it. What failed in the measurements was letting counts set the order. So counts may adjust the order that the tables give, and the adjustment is limited so that it can never push a name out of reach **[P]**.

### 6.5 Where words and tables come from

Nothing in §6.4 is useful if the vocabulary has to be listed by hand. The outside review proposed rules by which the kernel would choose its words, and rules for choosing the probe rows that verb tables are built from. Each rule was tested in a form the kernel could run, with nothing written by hand about which words or which cases matter **[M]**. The figures are in §8.7; this section gives the procedure and what was concluded. Most of the rules hold. Two of the review's reasons for them do not: that the grammar of candidate words should be grown from the library, and that the probes should be chosen by transforms picked to suit the words.

**Choosing the words.** The procedure has four steps.

1. *Enumerate candidate words.* A candidate word is a small term whose value is one of at most eight labels. It is either a single term of up to five nodes, over the library's operators together with `sgn`, `mod`, `<`, `=`, and small constants, or a *two-part word*, which is the values of two such terms of up to four nodes each, taken together. Two candidate words that sort the probe values into the same groups count as one, whatever their labels are called.
2. *Score each candidate word by a graded form of the dependency test.* For one operator, the score is the share of the uncertainty about the label of the output that the labels of the inputs remove. The score of a word on lists is the mean of that over the library's operators that take lists to a list. A word whose label is the same for every output scores zero for that operator, since it predicts nothing.
3. *Choose greedily, and skip repetition.* Take the best-scoring candidate word. Then take the best one that does not largely repeat a word already taken, and so on. Two words repeat each other when knowing the label of one nearly fixes the label of the other on the probe values. Without this step, in an earlier and smaller pool of candidate words, the fifteen best-scoring words were all versions of the length.
4. *Match each list word with an integer word.* Some operators, such as `sum`, `head`, and `len`, take a list and return an integer. Their tables need a word for the list that goes in and a word for the integer that comes out. Each chosen list word is therefore given the integer word that scores best with it on those operators. In the run measured, the integer word chosen was "is the value zero" for five of the six list words, so this is the weakest of the four steps.

On the 61-operator library this gave a gain of 13.0× with six words and 15.3× with ten, against 15.8× for six words listed by hand. That is the main result of this section: **a procedure with no word listed by hand chose a vocabulary nearly as good as a hand-made one, on this library.** It was run in Python, with the tables built from random probes; it has not been combined with the probe rule below, and nothing has been run in the kernel. Four observations qualify it.

- *The words it chooses are not the ones a person would list.* Nine of the ten include the length, usually joined in a two-part word with a property of an early element: "the length up to three, and whether the first element is negative". The hand list's words for the signs and parities present in a list are among the candidate words, and rank about 4,000th of 95,732. So the score does not rediscover human concepts. It finds different words that do most of the same work.
- *Words need several labels.* The gain falls steadily as the number of labels a word may have is reduced, to about a third of it when a word may have only two. This is the review's point that a vocabulary of yes-or-no properties is not enough, and in search it holds. The six words chosen were all two-part words, and with single terms only the gain was 10.4×.
- *The grammar of candidate words does not need the library in it.* The review proposed feeding each new library function back into the grammar, so that the vocabulary would grow with the library. With the library's list operators in the grammar the gain was 13.0×. With only `len`, `head`, `last`, and the integer operators in it, the gain was 12.8×. With the fold forms the review named also in the grammar, the gain fell to 10.3×, so a richer grammar of candidate words can do worse. As the library was grown in three steps the chosen words changed, and with six words the words chosen at the first step were still worth nearly as much at the last. With ten words the gain did rise between the first two steps, from 13.5× to 15.3×. So choosing the vocabulary again as the library grows does no harm, and on this evidence it is at most a small source of compounding.
- *The thresholds are knobs.* Changing how much repetition is allowed moved the gain between 11.5× and 14.8×. The six-word vocabulary above lost one answer of 60. Applying the repetition test to each of the two parts of a two-part word as well gave 13.9× and lost none at that setting, and 12.3× and 10.6× with one and three answers lost at the other two settings. It is the version to build, at the middle setting for now, because that is the setting that lost no answer. The setting remains a knob, to be tried again when the procedure is run in the kernel.

Choosing a vocabulary took about 21 CPU-minutes for that pool of candidate words. That is work for the agenda (§7.5), between searches, and never inside one.

**Choosing the probes.** A verb table is only as good as the rows it was built from. A table is wrong in one way that matters: the probes included some combination of input labels, and happened never to produce one of the output labels that combination allows. Random lists are poor probes, because the inputs an operator meets inside a program are not random lists. They are other operators' outputs: sorted lists, lists with repeated elements, two arguments computed from the same input. So the rule is:

> Draw each probe the way a small program would produce it: every argument is the output of a random term of up to two library operators, and all arguments are read on the same underlying row. Then spread the probes evenly over the pairs of labels that occur.

With that rule, at 1,000 probes per operator, no answer was lost in 1,700 searches over 700 tasks. Random probes lost 12, and the transforms the review chose by hand lost 5. The rule is still not sound: on streams of 4,000 tasks the tables met a wrong entry on about five tasks in a thousand. The second half of the rule is what the review calls stratifying by current words. The first half is not in the review, and matters as much: spreading random lists evenly cannot reach labels that random lists never show, such as a long constant list. This is in the spirit of your "depth >= 2 experiments": the probes for one operator are the results of experiments on the others.

Three further rules follow. The second and the third rest on measurements. The first was measured as well, but the measurement did not decide the matter, and the rule is adopted on the argument given with it.

- *A table for a two-argument operator is built from probes that vary both arguments together.* A table keyed on labels is a claim about every value that carries the label, and holding one argument fixed samples only a few of them. The review's evidence for the rule was that tables built from slices, in which one argument is held at a few fixed values, made 287 false rejections for `div` and 422 for `mod`. That depended on the slices it chose. Most random choices of slice rejected nothing, and at an equal budget random probes of both arguments rejected more true results than random slices did.
- *Tables are not repaired during a search, in the first version.* The review first proposed to add to the tables whatever a fallback search discovers, and then dropped the idea (its Appendix B.2). With good probes no answer was lost in the 700 tasks searched, so there was nothing to add there. On the streams of 4,000 tasks, where wrong entries were still met, repair cut their rate three- to fourfold. It is a cheap thing to add later.
- *No merged words.* Merging three words into one finer word raised the gain from 17× to 22×. It still lost 10 of 600 answers at 10,000 probes per operator, which is ten times the number of probes at which the separate words lost none.

**What can be certified.** Every entry of a verb table is tested knowledge, because every entry is a sample. About 71% of entries allow exactly one output label, and a filter that uses only those entries has a gain of 10.2×, where a filter that uses every entry has 17.0×. The only tables that follow from something provable cheaply are those for length, and a filter that uses those alone has a gain of 3.6×. So the fallback is part of the design, not a precaution.

**Two further sources of words [P].** The rows where the VM faults give two-label words directly, such as `x = 0` and `len = 0`: a guard learned from a crash (§7.5) is a word. And once the kernel has solved problems of its own, a word can also be kept for predicting, on the derivation space (§7.4), which refinement succeeds. That needs a history of solved problems. The dependency score does not, which is why it comes first.

### 6.6 Making, collapsing and moving spaces

Your margin note on "compare across spaces only through verified maps" was "how, though?" On this store the answer is short.

- **A space is made by a move.** Lift makes a position space; split makes a sub-space; anti-unification makes an instance space; recursion makes a call space. A residual makes a new column on a space that already exists, and not a new space. Whether the result of a move is kept is a description-length decision: total bits with it against total bits without. That is the one principled, gradient-free criterion the literature review found for "when is a new space needed", and the kernel already has it.
- **Two spaces collapse when a bijection between them is verified.** For example, the positions of `xs` and the positions of `ys` are one space when the lengths agree on every row; then `zip` is just two columns side by side. Labels may propose candidate pairs. The test is exact.
- **A column moves by re-indexing or collecting along a map.** To compare columns from two spaces, move both to a space they share, in the end the root, and compare there.

That keeps nesting in the exact store, where a cell may point into another space, and keeps the geometry explicit and local: a column's own code inside its space, and labels that mean the same thing in every space because a word is a term on values, not on rows.

What this does **not** provide, stated plainly because nothing in the literature provides it at this scale either:

- coordinate spaces learned from a handful of samples;
- vectors that keep their meaning while spaces are created and merged around them;
- collapsing spaces on geometric evidence alone;
- a nested engine shown to beat both a flat embedding and a plain symbolic graph.

On the flat-versus-nested dilemma itself: it is not a question of what can be represented (§4.5). A flat shared space buys storage economy, which a brain needs and a library of a few hundred entries does not. The labels of §6.2 are the flat layer here: every value in every space has them, and they are small. If the library reaches a scale where learned coordinates have data to learn from, that layer is where they would attach. Nothing in the store has to change for that.

**Values that carry real geometry.** Lengths, areas, orientations, and real-valued measurements enter as value types. A type brings three things: a code for its values, an invertible `decode` operator that applies a correction, and the solver for that operator. That triple is exactly the existing metric decoder. This plan does not design those types. It notes that adding one touches no other part of the store. One of your margin notes reads "new (local) metrics may be admissible, even if they are not desireable". If it is about metrics of distance, this design admits a local metric in that sense: it is a code attached to one column, and it must still pay its way in total description length.

### 6.7 Language with people, and precedent

**Language with people** comes last and attaches to the same tables: a name that a person supplies is aligned to a word by co-occurrence counts. That is the one approach with evidence on small data. In its published form it raised the share of held-out tasks solved in one domain from 42.6% without the method to 82.0% with it, as means over seeds, with gains persisting when no language was given at test time **[L, one research lineage]**. That system sits on a neural search component. Its best single run in that domain reached 98.2% with synthetic descriptions, and fell to 58.6% with descriptions written by people.

**Precedent.** Guiding synthesis by running candidates on abstract values is established, and the outside review's citations for it were checked against the papers **[L]**. One system, Simba, solved 519 of 544 bit-vector problems against 456 and 409 for two leading enumerative solvers, though on the conditional problems of the same suite one of those two wins. Another, Blaze, reports a 90-fold speed-up over a deployed synthesizer in one domain. In all of them the abstract meaning of each operator is written by hand, with one exception. That exception, Atlas, learns its predicates from four training problems per domain, fits each operator's abstract behaviour from random samples, and then checks the fit against operator axioms supplied by hand. It reports 8.3× and 9.2× over hand-written abstractions on its own benchmarks, and 2.1× and 3.1× on its predecessor's. A 2024 paper still describes this kind of pruning as one that "requires manually designed, domain-specific abstract domains and semantics".

**What has a near precedent, and what has none.** Two things have a near precedent in Atlas and no exact one. The first is reading an operator's table off its own samples by grouping, with no solved tasks and no hand-written semantics. The second is choosing abstractions by the dependency score. No published synthesizer was found that does either, and both were measured for this plan, in Python (§8.7). One thing has no precedent of any kind: the compounding, that is, a vocabulary that a system chooses for itself and that goes on improving its own search as its library grows (§10).

### 6.8 What remains open

- Whether verb tables pay on the kernel's own library. The search measurements so far are on a library of whole-sequence operators written for the experiment, and on the prototype's twelve element-level operators, where labels gained nothing over a plain comparison with the target except as a look-ahead (§8.7). Experiment X4 (§11.2) is the test.
- Whether words can be made to see more than the last step. With the vocabularies tried, the tables ruled out nothing two or more steps from the answer. A merged, finer word showed a gain that rose with program size against one of the two baselines and was flat against the other, and it lost answers. Nothing measured so far changes the exponent of search without that cost.
- Whether the rounds of increasing bound let near misses through inside the kernel as they did in Python. A filter applied strictly at one size discards them (§7.2).
- Whether the words the dependency score chooses stay useful as the library changes character, for example when it acquires operators on trees or on pairs. On one library grown in three steps, they did.
- Whether the correction code can be tightened. On sequences and code the present prices break the triangle inequality for large values (§6.1), and the element-by-element residual from which proposals are read is undefined between values of different type or length (§6.2).
- Whether any of this beats the plain store with no guidance, inside the kernel. §11 makes that ablation, X4, the gate for building any of this beyond a first version.

## 7. The VM and the synthesizer

### 7.1 The VM: what stays and what changes

The metered VM is the cleanest part of the kernel. Its design is kept, and its code is re-derived for the new opcodes (§9). Four properties make up that design. Every instruction is paid for from a work budget before it runs. A run that is cut off when its budget is spent can be resumed exactly where it stopped. The ledgers of work spent are exact. And the results are identical however a run is cut into slices. The rule that every finished program is verified at the root, on every row, is kept as well.

Five changes.

**1. Evaluate by column.** The unit of evaluation becomes one operator applied down one column, memoized by (term, space). The class table is that memo. The ledger still charges one unit per cell, so accounting stays exact. This is aimed at the measured cost: in a synthesis job, evaluating candidates is 3% of the time and per-unit scheduling and bookkeeping is most of the rest (§2.3).

**2. Keep faults as data.** A failed cell records which operator failed on which arguments. A pending cell records the call it waits on. Today a fault is an unstructured string that exact search discards immediately (`vm.lisp:384`, `enumerate.lisp:426-441`). Kept, it is the training data for guards and for totality (§7.5).

Pending cells also close a possible soundness gap in v2's dormant pruner. The search audit found, by reading the code and without a failing run, that the pruner treats two unresolved cells as equal. Two pending cells are equal only when they wait on the same call.

**3. Give sequences primitives that build them and primitives that take them apart.** There are six. `length` gives the number of elements. `at` reads the element at a position. `tabulate` builds a sequence from a length and a function of position. `fold` reduces a sequence to one value, by applying a step function to each element in turn and carrying an accumulator. `scan` does the same and returns every intermediate value of the accumulator, as a sequence. `where` returns the positions that satisfy a predicate. Sequences become arrays, so `at` costs one work unit instead of a cost that grows linearly with the index.

An earlier audit pass removed `:tabulate` and `:loop`, saying that the version before it had "smuggled `map-indexed`/`foldl` into host Lisp via higher-order `:tabulate`/`:loop` opcodes", and the next pass put them back. The line this plan draws is: **a primitive may encode the shape of a container, never the content of a domain.** `tabulate` is to a sequence what `tuple` is to a tuple, and `fold` is to a sequence what `at` is to a tuple. They say how a sequence is built and consumed. They say nothing about arithmetic, correlation, or any particular function. What goes inside those forms is then a term to be found. §8 finds the terms for `reverse`, `shift`, `zip`, and first-order instances of `map`, `scan`, and `filter` (§8.1). It also finds `scan`, `map-adjacent` and `filter` when the function or the predicate is an argument (§8.1, §8.5). It did not attempt the higher-order `map` or `foldr`.

The same rule says what a *learned* container would be. On the store a container is a recipe for a space: which rows a value unfolds into, the map back, and how to rebuild or reduce. A library entry of that shape, a pair of terms that unfold and build and are inverse on the examples, would describe a data structure in the store's own nouns: a matrix as two nested position spaces, a tree as a position space with a parent endomap **[P]**. Nothing before Stage D, the last of the four stages in which this plan is built (§11.3), depends on it.

Two published results are the evidence for granting this much **[L]**. One synthesizer, λ², is given such combinators and splits requirements through them; it has a median time of 0.43 s on its benchmark suite. A different system, DreamCoder, was not given them. It had to rediscover `fold` from a fixed-point combinator, and that took about 7,700 CPU-hours (§4.1). Demanding that the kernel find lifting from raw recursion, in hours, on one thread, is not a realistic test of anything.

**4. Let a program observe a failure.** One form, `(try e fallback)`, so that a guard learned from failures can be written in the object language. It applies to errors, not to running out of fuel.

**5. Price names by use.** An operator's name costs −log₂ of its share of uses in accepted solutions, under a prefix code as now. That price is used only at acceptance, to compare programs that fit the rows (§7.2). It does not set the order in which operators are tried during a search. The order comes from how well each operator's verb table fits the labels of the problem at hand, and counts of use may only adjust it, within a limit that keeps every name in reach (§6.4). Letting counts set the order was measured, and it failed for operators that had never been used: 5 of the 8 tasks that needed such an operator ran past the search's cap (§8.7).

**A consequence worth stating.** With these six primitives, the store's own operations are ordinary programs over sequences. A column is a sequence indexed by row. A map is a sequence of row indices. Re-indexing along a map is `gather`, which is `tabulate` over `at`. A fiber is `where`. Unnesting is `tabulate` over the lengths. So your requirement that "lift has to be a synthesizer primitive" can be met in the strong sense: the operations the synthesizer performs on its store are expressible in the language it synthesizes, and the records of those operations (§7.4) are data it can be pointed at. This is homoiconicity extended from code to the layout of data **[P]**.

### 7.2 The synthesizer: one move

A **problem** is a space, a requirement with holes (§5.6), a context (the classes available as leaves), and a budget account.

The one move is: **refine a hole with a construct.** Choose a hole. Choose a program construct with fresh holes of its own. Substitute it. Split the requirement the way that construct splits it. The children are problems of the same kind, possibly on a new space.

| Construct | How the requirement on the hole splits | New space |
|:--|:--|:--|
| a leaf from the context | checked directly; this is enumeration by class | — |
| `(f k ?z)`, where `f` is a library function with a known inverse and `k` is an argument that is already known | a requirement on `?z`, through the inverse | — |
| `(f k ?z)`, where `f` is any library function, with or without an inverse | a coarse requirement on `?z`: its labels must be among those that the function's verb table takes to the labels required of the result (§6.4) | — |
| `(tuple ?a ?b)` | one requirement per slot | — |
| `(if ?g ?a ?b)` | `?a` on the rows where `?g` holds, `?b` on the rest; accepted only under the size-order rule (step 3 below) | two sub-spaces |
| `(tabulate ?n (λ i. ?e))` | `?n` is the length, on the same space; `?e` is the element, on the position space | positions of the output |
| `(gather xs ?idx)` | per position, `?idx` lies in the set of indices where `xs` has the wanted value | positions of the output |
| `(where n (λ j. ?keep))`, and selection of elements | `?keep` is whether position j survives | positions of the input |
| `(scan ?init (λ acc x. ?step) xs)` | `?step` on the position space, with the previous output as a column | positions, with a "previous" endomap |
| an aggregate of `?e` over `?n` positions (a sum, product, maximum, minimum, or count) | `?n` is the number of positions; `?e` is not observed, so each candidate element term is collected under each aggregate in scope and compared (§8.5) | positions |
| `(fold ?init (λ acc x. ?step) xs)` | does not split unless intermediate values are observed (§7.3); otherwise `?step` is enumerated by class | — |
| a self-call `(self ?s)` inside a recursive body | `?s` is any term whose value is a row of the call space | the call space, with an endomap |
| `(decode ?m ?r)` | `?m` need only be near; `?r` is solved from `?m` and the target | — |

Each row pairs a construct the VM can run with the law that splits a requirement on it. This is what the previous plan was reaching for with a "symmetric instruction set", stated as one table.

The laws in the middle column of the table are Boolean equivalences. For example, `(= (tuple ?a ?b) y)` holds exactly when `(= ?a (at y 0))` and `(= ?b (at y 1))` both do. So they are laws in the store's own sense: two Boolean terms in one class. The handful for the structural constructs are seeded by hand, as the ten constructor rules are today. They can be checked by the collision engine, and in principle found by it **[P]**. Library functions get theirs by reorientation (§5.3), not by hand.

The selection row needs one more granted piece than the others. To recover which input positions survive, the output has to be aligned to the input as a subsequence. That alignment is the preimage of selection, in the way the index sets are the preimage of `gather`. An earlier audit pass rejected a subsequence propagator as specific to `filter` (Appendix B), and the prototype uses one (§8.1). The case for it is the rule of §7.1: it concerns the container, not any domain. §5.9 gives the better reading: it is a search for a map between two position spaces under an order constraint, and it should be built as that.

Two further rules for this table were measured (§8.5). One is the size-order rule for conditionals, which step 3 below states together with its reason. The other concerns the guard of an inverse. The guard has two parts, and they come from different sources. *Uniqueness* says that the known values determine the unknown argument, and it is read from the operator's table by the dependency test. *Existence* says that some value of the argument gives the known result, and it needs no search at all: a candidate answer is replayed forward and compared.

**One search, four steps.** The table says which moves exist. Its first row, a leaf from the context, is the workhorse: it fills a hole with a finished term, found by enumerating terms bottom-up in order of size. Call this *leaf enumeration*, and call the filling of a hole by any other row of the table a *refinement*. What follows is the order in which leaf enumeration consults what the store knows, and the points at which it hands over to the other rows of the table. The outside review proposed this as a handoff in four parts: verb tables consulted before enumeration, verb tables consulted during it, corrections on the classes that survive, and acceptance by the exact code. The order below keeps its outline and changes two things that the measurements of §8.7 forced. First, the check for near misses looks at every candidate that is evaluated, not only at the classes the labels keep. Second, a step is added in which an answer that is being held bounds the rest of the search. Each step has been measured on its own, in Python or in the store prototype. The four have not yet been run together as one search; that is experiment X4 (§11.2).

Take as the running example a task over whole-sequence operators: from `xs` = (3, −1, 4, 2) produce (2, 4, 6, 8). The answer is `(double (sort (abs xs)))`.

1. *Replay, then label, then order.* Every stored solution of the right type is first run on the new rows (§7.4), and a repeat of an earlier task ends here. Otherwise the inputs and the target are labelled. In the example the input has mixed signs, mixed parities, and no order, and the target is all-even, all-positive, ascending, and as long as the input. The verb tables then order the operators, putting first those whose tables lead to the target's labels: doubling makes any list all-even, so `double` is tried early as the last operator. Nothing is ruled out, so nothing can be lost. Used alone, this ordering cut the candidates evaluated to about a sixth of what plain search evaluates **[M]**.

2. *A tentative pass that tests labels before evaluating.* A *candidate* is an operator applied to classes already in the bank, which is the set of classes enumerated so far on this space from the problem's leaves. The size of the answer is not known in advance, so the enumeration is repeated in rounds, with a size bound of 1, 2, 3, and so on, and each round starts again from the leaves. Before a candidate is evaluated on the rows, its tables are read. The question is whether the target's labels can still be reached from the labels this candidate's result can have, within the number of operators the current bound leaves. For a candidate at the bound itself, the question is simply whether its result can have the target's labels. For a candidate one size below the bound, the question is whether one more operator can take its result to the target's labels, and the tables tried so far ruled out 43–47% of the classes of that size. For smaller candidates they ruled out nothing (§6.2). So in practice the test acts on the last step of each round and on the size just below it. Applying it throughout the enumeration gave twice the gain of applying it at the final size alone (§8.7). A skipped candidate costs a few look-ups and no evaluation. This test, made before a candidate is evaluated, is the *label filter*.

   In the example this pass finds the answer in the round with a bound of three operators. `(abs xs)` and `(sort (abs xs))` are evaluated, because nothing in their tables puts the target's labels out of reach. At the last step `(double c)` is evaluated for each class `c` in the bank, and `(reverse c)` is skipped for every `c` that is not descending, since reversing gives an ascending list only then.

   This pass evaluated 14 to 18 times fewer candidates than plain search, depending on the set of tasks **[M]** (§6.4). With the filter on, the ordering of step 1 changed the totals by only 3 to 5 percent. The pass is tentative because its tables are tested knowledge and can be wrong (§6.5). It runs under the kernel's reserve rule, which gives three parts of a budget to a tentative attempt and keeps one part for the fallback, the plain search with no filter (§9).

3. *Every candidate that is evaluated is checked as a near miss.* Each candidate that the tentative pass evaluates is compared with the target. Two proposals can come from the comparison, and both are rows of the table above. The running example has no near miss, so take two other cases. Write `U` for the candidate.
   - *A constant offset or scale.* Where the candidate and the target have the same type and length, their difference is taken element by element. If that residual is the same constant everywhere, the proposal is `(decode U ?r)` with the constant for `?r`. Had the target on this row been (3, 5, 7, 9), the class whose value here is (2, 4, 6, 8) would be off by one at every position, and likewise on every other row. On tasks built to contain such a step, the check was first run as the outside review arranged it, only on the classes that the label filter keeps. In that arrangement the search evaluated 2.4 to 3.0 times fewer candidates than the label-filtered search alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate **[M]**. Run on every candidate that is evaluated, which is the arrangement of this step, the check halved the candidates again, as the paragraph after this list reports. Only offsets and scales were tried. The general case, a residual that falls in the class of some other small term, is proposal **[P]**.
   - *A conditional.* If `U` agrees with the target on most rows, the proposal is `(if ?g U ?else)`. An example is a candidate that is right on every row whose input list is non-empty and wrong on the rows where it is empty. A guard `?g` is sought that separates the rows that agree from the rows that disagree, and `?else` is solved on the disagreeing rows alone. When both are found, the resulting conditional, which §8 calls a guard split, fits every row. It is then *held*: kept as a provisional answer, and not yet accepted. The reason is a measurement on tasks that were not built to need a conditional. A conditional that fits the rows existed for 64 of them, and it was the right program for 2 **[M]**. So a conditional is accepted only once every smaller term without one has been ruled out. This is the *size-order rule* (§8.5).

   Two findings fix where this check sits. The outside review ran it only on the classes that the label filter keeps. Running it on every candidate the filtered pass evaluates, including those the labels then decline to keep, halved the candidates needed **[M]**. And a near miss is, by its nature, a candidate whose labels do not match the target's on the rows it gets wrong. A filter applied strictly at the one size where the near miss sits therefore loses the conditional. With rounds of increasing bound, in Python, both branches of the conditional were evaluated and kept one or two rounds later. That test did not ask whether the guard was kept as well. The third limit of §6.4 gives both measurements **[M]**. So the check lives inside the tentative pass, and the rounds are what should let a near miss through. Whether they do so inside the kernel, with the guard included, is not known (§10, risk 14).

4. *A held answer bounds the rest of the search.* A held conditional has a known size. From then on the search needs only programs smaller than that, so it has a firm size bound for the whole answer. With such a bound, a *look-ahead* becomes possible: a class is not stored when the types and the verb tables say that the target cannot be reached from it within the bound, and an operator is not enumerated when its result type cannot lead to the target. This was measured in the store prototype, on seven runs whose answer needs a guard: five functions, two of them run a second time on the kernel's spec rows (§8.7). It cut candidates 36× and stored classes 34×, and it changed no answer **[M]**. Types alone gave the whole saving on five of the seven runs. Labels were needed on the other two, which are one function, `scan` with a function argument, on two sets of rows. The saving recovers part of the cost of the size-order rule, which was 625 and 824 times the candidates on the two kernel specs that need a guard (§8.5). The part of the look-ahead that rests on types is certain. The part that rests on labels is tested knowledge, so a conditional accepted after it is accepted tentatively, under the same reserve as step 2. The bound has to be the size of the whole answer. With the size of a conditional's branches as the bound instead, the look-ahead discarded the branches.

**Acceptance is by one exact code.** Whatever the route, a finished program is verified on every row at the root, and compared with its rivals by one description length: the bits of the term plus the bits of any residual, under the rules of §6.3. Labels and corrections decide what is tried. They never decide what is accepted.

**A search reads; the kernel's own questions write.** None of these steps learns anything. Words, verb tables, inverses, and laws are found by the problems the kernel poses to itself on probe spaces and on the derivation space (§7.5), between searches on tasks. A search on a task only looks them up. This keeps the inner loop free of nested searches, and it is how reentrancy is had without a tower of interpreters (§4.6): the levels meet in the store, as tables that one level writes and another reads, and not in the control flow. The arrangement was checked for the one failure it invites, a task whose target carries a label that no table mentions. That happened in none of 234 tasks **[M]** (report `verify-handoff.md`, Appendix D). What does happen is a wrong table entry (§6.5), and the fallback covers it.

**Control.**

- There is one agenda. It holds the open sub-problems of the tasks being solved, and also the small problems the kernel poses to itself on probe spaces (§7.5). A problem's budget is an account that can be topped up, so every problem can be resumed and re-opened.
- Leaf enumeration under a problem runs up to the size that the problem's present budget allows. When it reaches that size, further budget goes to the next-ranked refinement as well as to larger terms. This is what lets budget buy structure (§2.3).
- Refinements are to be ranked in the way step 1 orders operators: by the labels of the problem and by a table for each construct, which would play the part that a verb table plays for an operator. No table of a construct has been built, so this ranking is proposal **[P]**. Until such tables exist, the order is a short fixed list keyed on types.
- The reserve that splits budget between a tentative attempt and its fallback is carried over unchanged: anything that rests on tested rather than certified knowledge always leaves budget for the plain alternative. In the one run that measured it, three lost answers out of 234 halved the saving summed over tasks under this reserve, from 12.1× to 6.6× (§6.4). That is why X4 reports cost summed over tasks, with the fallback counted (§11.2).
- There is one bank of classes for each space and set of leaves, and everything that enumerates there uses it. Today the same grammar is enumerated separately for the kernel's first search phase, for the sub-problem's own search, for guards, and for the separating columns of §7.4, which the present kernel calls features (section 11 of the search-engine report). A search that prunes toward its own target, as in step 4, does so in a working copy of the bank. That working copy is scratch memory for the one search, and it is not the persistent store of classes (§7.6).

### 7.3 Recursion without hand-written skeletons

The audit found that the kernel has one main template for recursion, with a lockstep variant that walks two sequences in step (§2.3). There are also five hand-written schemas, which the bootstrap supplies (`bootstrap/recursion-schemas.lisp`). The template and the five schemas all do the same thing: they bind the value of the recursive call as a new input of the child problem. They differ in the arguments passed to the recursive call, which their author chose by hand, and in the base cases and the fixed code that the author wrote around the call. On this store the cases separate, and most stop being recursion.

1. **Position-wise functions** (`map`, `zip`, `reverse`, `shift`, `map-adjacent`, `gather`, and the library's `positions`, which is the index list k, k+1, …): a `tabulate`. No recursion.
2. **Selective functions** (`filter`, positions of a value). The program is a `where` over the positions of the input. What has to be found is the *keep-column*: the Boolean column that says, for each input position, whether its element survives. It is recovered by aligning the output to the input.
3. **Recurrences on the observed output** (`scan`, running totals): the previous output is a column on the position space, re-indexed along the "previous" endomap. An ordinary scalar problem.
4. **Reductions to a scalar.** There are two kinds. A reduction of an element-wise term under an associative aggregate (a sum, a product, a count, a dot product) is a change of space after all: enumerate the element term on the position space and collect it under each aggregate in scope (§8.5). A fold with sequential state (`foldl` with an arbitrary step, a Horner evaluation) is not. Its intermediate accumulator is not observed, so the requirement on the step function does not split. For those, two routes:
   - enumerate step functions by class over the leaves `acc` and `x`, each candidate costing one fold per row (§8 measures this);
   - notice when the rows themselves contain the intermediates. If one row's input is a prefix or a tail of another's, that relation is an endomap on the space of examples, and the accumulator column is observed after all. The bootstrap's "trace-complete rows" are this, supplied by hand as a convention. On the store it is a property the data either has or lacks, and a group-by detects it.
5. **General recursion**: the calls a function makes are rows of a call space, and the recursive call is an endomap on it. The argument of the self-call is one more hole. Candidates for that argument are ranked by two tests. The first is how many rows land on a known row. The second is whether some measure decreases from each call to the next. The kernel's termination check, about 50 lines that can be carried over, supplies the second test.

Case 5 is research with replicated precedent, not engineering. Published recursion synthesizers need examples that are closed under the recursive call, meaning that the examples include the result of every recursive call the program makes. The published ways around that requirement are three **[L]**. One is angelic execution, which assumes that a recursive call can return anything, synthesizes, and then checks. The other two each come from a single paper: one evaluates partly written programs in both directions, and the other searches for the missing traces together with the program. Cases 1–4 are different. By inspection, they are the shapes of the functions in the current library **[P]**. What has been run is narrower than that. On its own rows the prototype was run on first-order instances and on two forms that take a function argument (§8.1). On the kernel's spec rows it was run on all sixteen specs, and thirteen were solved in some configuration (§8.5 gives the outcome of each). Those sixteen include `filter` with its predicate as an argument, which was solved once a one-argument Boolean call was in the grammar, and `foldl` with its step as an argument, which returned an impostor. In these runs a function argument is one of three named functions, and a predicate is one of three named predicates; neither is arbitrary code. The higher-order `map` and `foldr` are not among the sixteen and were not tested. `best-shift` plausibly needs two lifts, and two lifts were not tested either.

### 7.4 Reflection: the search as a space

Reflection means the kernel reading the record of its own searches and acting on it. On this store the record is a space like any other. Each problem posed is a row of the **derivation space**. Its columns are the parent problem, the construct chosen, the labels of the problem's inputs and target (§6.2), the size of the context, the work spent, the classes created, the outcome, and the bits of the best answer.

Four uses of this record follow, in decreasing order of the evidence for each.

1. **Memo and replay.** Two problems with the same space, the same requirement class, and the same context are one problem. This replaces the present reuse key, a sorted printed string, and it holds across branches and across jobs. Your margin note on "Nothing persists across branches or jobs" was "yeah that's a big problem"; this is the fix. The memo is exact, so it misses the same problem posed on fresh rows. For that there is *replay*: before any search, run every stored solution of the right type on the new rows. Replay reads the library of stored solutions and not the derivation space, so it is available from Stage C of this plan (§11.3), before the derivation space is built. On 25 repeated tasks with fresh inputs and at most 19 stored solutions, replay found all 25, at no more than 57 candidates per task **[M]**. The alternative that was tried is an index of past problems: a key is computed from yes-or-no properties of the new task's inputs and output, and only the stored solutions whose tasks had the same key are replayed. An index found 19 of the 25, or 20 when variants of the retrieved solutions were tried as well (§8.7) **[M]**. Replay's cost grows with the number of stored solutions, so an index may be needed later. No index that was tried was good enough to replace replay.
2. **Counts of use.** Counts of which operators appeared in accepted solutions are kept with the library from Stage C, and counts of moves are read from this record. Both adjust the order that the verb tables give (§6.4). The tables themselves do not read the record. They are got by running the operators on probe rows, and they are reflective knowledge of the cheapest kind: what the kernel knows about its own operators.
3. **Attribution by ablation.** Re-run a held-out set with one learned thing removed, and keep only what pays. The literature's warning is specific: one planner kept 4–6% of its learned rules and ran 65% slower without that validation; one lemma library showed a single reuse among 20,000 entries **[L]**. The ablation harness of v2's Stage 0 can be carried over for this.
4. **Explanation-based generalization.** On a shared term graph, "what did the winning derivation actually read" is a walk over edges. Whatever it did not read can be made a variable. Plans 1–3 specified this and never built it (§2.8).

**Messages, nogoods, and the pruner are one table.** You asked whether behaviour pruning is a case of the message idea in the old code, and whether the kernel's two conflict-analysis steps are too. On this store they would be, and that is proposal **[P]**. The pruner's fact is "this column equals one already kept": a claim with its evidence, which is what plan 4 called a message. A *nogood* is the same kind of fact about a requirement. It records that a dependency test failed: some projection gives equal inputs to rows that need different outputs, so no program over that projection can work. The kernel then does two things with a nogood. One step, which its code calls UIP, generalizes the nogood by anti-unifying it with others. The other, which it calls DIP, searches for a further column that separates the conflicting rows. Today these facts live in three structures, and only two narrow forms of them are kept between jobs. On the store they are all facts about classes on a space, kept in one table and shared across sub-problems and jobs. The search for a separating column resembles the search for a word (§6.5): both look for a small term whose values tell rows apart. Whether the vocabulary could supply the separating columns is not tested **[P]**.

The pruner is also the simplest reflection there is: the search reading its own record so as not to repeat itself. What a learned policy could add is prediction, skipping an evaluation that a law or a table says will collide.

**The same question, asked of the search.** Because the derivation space is a space, the question of §6.1 can be put to it: how many bits does the `outcome` column cost, once the columns of labels are known? A table from problem labels to the move that succeeded is a verb table for moves, and a learned search policy is nothing more than that **[P]**. The present kernel has one experiment of this kind, called `yield-gate`. It reads the messages of two recorded searches as rows, and it searches those rows for a rule that says when a search should stop. It shows that the plumbing works **[C]** (§2.6). A learned policy is not on the critical path of this plan. The one learned predictor that exists today learned a constant (§2.6).

The audit's inventory gives this a concrete target (§2.3). Of the 158 hard-coded decisions, the 30 dedupe and memo guards become the class table and the problem memo; the 30 ordering rules become tables and counts; the 52 caps become budget accounts that defer rather than drop; the 51 pieces of domain knowledge become library entries or are deleted. The four figures add up to more than 158 because a decision that belongs to two categories is counted in both, and the 6 accounting rules of §2.3 are not part of this mapping. That mapping is a goal to check item by item, not a result **[P]**.

### 7.5 Discovery: an agenda the kernel fills itself

The audit found that nothing in the kernel initiates discovery (§2.4). On the store the questions can be listed mechanically, and most of them are the question of §6.1 put to some probe space: what does this column cost, given those? For each library entry `f`, starting from the primitives:

- **Laws.** Which small terms over `f` and the operators in scope have the same column? The agenda enumerates classes on a standard probe space, up to a size bound.
- **Inverses.** For each argument of `f`: is that argument a function of the result and the other arguments (the dependency test)? If that holds only on some rows, which guard picks out those rows? And which small term computes the argument?
- **Definedness.** Which guard picks out the rows where `f` returns an error? The kernel's milestone code already does this for arithmetic (§2.4).
- **Verb tables.** For each word in the vocabulary: which output labels follow which input labels? This is one group-by over `f`'s probe rows (§6.4).
- **Lifted forms.** What does `f` do when it is placed under `tabulate`, `fold`, and `scan`?
- **Abstraction.** What pattern do the terms of accepted solutions share? The agenda anti-unifies them over the instance space.

And for the library as a whole, from time to time: **re-choose the vocabulary** (§6.5). All of these are problems on the one agenda of §7.2, where they sit beside the open sub-problems of tasks.

The dependency test behind an inverse and the verb tables are one routine with different columns passed in (§6.2). Laws come from a different computation, the hashing of columns into classes. A guard for definedness, like the guard and the term of an inverse, is a small search on top. Each is a small bounded problem; §8 gives their measured cost. An entry is accepted by utility: it must shorten the total description of the store's accepted solutions, or reduce work on held-out problems under ablation.

**Choosing experiments.** Both earlier plans left this as a line item. Four rules cover what the store can decide for itself:

1. *Refute before promoting.* Before a class moves from observed to tested, evaluate its members on fresh rows that include boundary values.
2. *Split ambiguities.* When two candidate programs fit, search for a row on which they differ. If the target is a function the kernel can run, run it. If not, report the task as underdetermined.
3. *Isolate.* To test whether a column depends on an input, build rows that vary that input and hold the others. This is "holding all but a few constant", and it is the shared-input experiment under which plan 2 found commutativity appears at once. Isolation is for finding *which* inputs matter. It is the wrong way to build a table keyed on labels, which must see both arguments vary together (§6.5).
4. *Probe with what programs produce, spread over pairs of labels.* The rows on which an operator is tested are the outputs of small random programs over the library, spread evenly over the pairs of labels that occur (§6.5). At 1,000 such rows per operator the tables lost no answer in the searches that were measured, and they are still not sound; §6.5 gives the figures.

**Limits.** A self-generated curriculum has no convincing precedent: every measured bootstrap needed a graded external task set **[L]**. The best-known attempt at open-ended discovery, AM, is a caution of a different kind: its authors traced its success to "the density of worthwhile math concepts as represented in Lisp" and its limit to an "inability to discover new, powerful, domain-specific heuristics". The bet here is narrower. Questions are generated mechanically from entries and kept only on measured utility. Functions still come from external data. What the kernel should stop needing is the operator whitelist, the recursion schema, the trace-shaped rows, and the hand-written entry: the four things that account for most of the library today (§2.5).

**Learning from crashes and timeouts.** A guard for errors is the same problem as a guard for a law: a Boolean target fitted by a small term, with a published five-step recipe behind it **[L]**. Timeouts are harder. An out-of-fuel cell cannot distinguish slow from divergent, and the literature review found no system that learns termination guards from timeouts. The cheap version is to treat out-of-fuel as a third outcome, re-test with doubled fuel, and learn a guard only for cells that stay out of fuel **[P]**.

### 7.6 What an hour buys

Within a space no operation needs graph matching, and none saturates. Across spaces nearly every operation is a search for a witness (§5.9).

| Operation | Cost |
|:--|:--|
| Intern a term | constant, by hash |
| Evaluate one operator over a space of n rows | n |
| Find a column's class | n, by hash |
| Dependency test (is this column a function of those?) | n, by hash |
| Learn one operator's verb table for one word | one group-by over its probe rows |
| Choose a vocabulary for a library of 61 operators | minutes: about 21 CPU-minutes to score 95,732 candidate words (§8.7) |
| Test a candidate against the target's labels before evaluating it | about 7 look-ups per candidate that survives, in the Python experiments of §8.7 |
| Unnest, re-index, collect | number of cells touched |
| Anti-unify k plain terms | their total size. Over classes, quadratic in the corpus in the one published system |
| Conditional laws under g candidate guards over c classes | g × c × n, with guards limited to about four nodes in published systems |
| Enumerate by class to size s | exponential in s: ×3–7 per unit of size after dedupe, against ×9–14 for raw syntax (§8.4) |
| Compare laws up to renaming of variables | brute force over the law's variables, which are few **[P]** |
| Across spaces: find a row correspondence by a key term | one hash join per candidate term |
| Across spaces: find one by colour refinement | polynomial; one group-by for each step of the refinement |
| Across spaces: find one by backtracking | exponential in the worst case; needed for regular structures without symmetry, and to reject look-alikes (§8.6) |
| Across spaces: match a tree-shaped pattern | a sequence of joins |
| Across spaces: match a pattern with cycles, or modulo associativity and commutativity | NP-complete |

Within a space the only exponential is leaf enumeration, and its exponent is the reason for everything else in this section. Across spaces the exponential is the search for witnesses, and it is controlled by choosing what to try (§5.9). With behaviour dedupe each tenfold of work buys one to two nodes (§2.3, §8.4). Deep single searches also meet memory before time: extrapolating from 90-second runs, the prototype would exhaust 24 GB within one to eight minutes of one deep search, and ten hours would reach one or two nodes further than one hour (§8.4).

So an hour should not be one deep search. It should be:

- **breadth**: thousands of small bounded problems from the agenda of §7.5, each milliseconds to seconds;
- **re-validation**: fresh rows for every class that something depends on;
- **ablation**: re-running held-out problems to decide what stays.

There is one bank of classes for each space and set of leaves (§7.2). The bank of a task's space is scratch memory, bounded by the account of the problem that enumerates into it, and so is the working copy that a search prunes toward its own target. The persistent store holds the library, the banks of a few standard probe spaces, the derivation rows, the verb tables, and the counts.

**Memory within one search.** A bottom-up search holds each class in two places: the bank that larger terms are built from, and the table that detects duplicates. Three rules follow from the measurements of §8.7 **[M]**.

1. *Test before storing.* Whenever a search has a target and a size bound, a class is not stored when the types and the verb tables say that it cannot reach the target within the bound, and the test is made before the class enters the duplicate table. Made afterwards, the duplicate table keeps everything the test rejected. The bound must be the size of the whole answer sought. With the size of a conditional's branches as the bound, the test discarded the branches (§7.2).
2. *Restart at each new bound.* When the size of the answer is unknown the bound is deepened, and a class cut at one bound may be needed at the next. The search therefore restarts from the leaves at each bound. Peak memory is then that of the last round, and the restarts cost, on average at each size, between 1.0 and 2.1 times the evaluations of that round, more at larger sizes. Keeping the bank across bounds instead needs a record for every class that was cut, and those records outnumbered the classes kept.
3. *Expect a large saving in two situations.* The first is where the labels are exact. On pure ring arithmetic, with residues modulo small primes, these rules cut stored classes 8.5 to 26 times at sizes 7 to 13. If that holds at larger sizes and with a third variable, which was not measured, then with classes growing ×3.0 per unit of size it would move the extrapolated memory wall of §8.4 out by two or three sizes. The second is the look-ahead of §7.2, once there is a firm bound on the size of the whole answer. In the store prototype it cut the classes stored 34 times on the seven guarded runs, where a held answer gave the bound, and ten times or more on three lifted tasks, where the answer's size was handed over. The two instruments count plain search's classes differently, so their figures are not comparable. Elsewhere the saving is small. On the sequence library it was 1.5 times in bytes, or 4.3 times with a one-step look-ahead, which also drops a class of the largest stored size when no one-argument operator can take it to the target (§8.7). With no target, as in a search for laws, it is nothing.

Most of the saving of the one-step look-ahead needs no labels. It comes from a rule that was computed but not run, and that by calculation would save 5.8 times in bytes on its own, with labels then adding 1.3 to 2.5 times. Classes of the largest stored size can only be arguments of one-argument operators at the final size, so they can be held as hashes and their columns dropped, provided each one-argument operator is applied to a class when it is made, before its column is dropped. On the sequence library 94% of stored classes are of that size.

That hours spent on breadth, re-validation, and ablation will compound is proposal **[P]**. The audit measured one instance of the effect it relies on: three of eight held-out tasks became solvable, in under 50,000 work, once the library was used for lifting, though three or four others became dearer (§2.5).

## 8. Measurements

To test §5 to §7 by measurement rather than by argument, two instruments were built. Neither is the kernel.

The first is a standalone prototype of the store: `tg-probe.lisp`, 874 lines of Common Lisp, using no kernel code. Its core store is 206 lines and its change-of-space routines are 22. It is a measuring instrument, not a design. Source, driver, and logs are in `plan_v2c_audit/proto/`, and every number in §8.1 to §8.6 is copied from a log there or in a folder that section names **[M]**. The second is a set of Python experiments on a library of 61 operators written for the purpose, used in §8.7. One experiment of §8.7 was run on a copy of the prototype instead, and is marked there.

Two cautions before the numbers. A *candidate* is one operator applied down one column; it is not the kernel's work unit, and the two cannot be compared directly. And in §8.1 to §8.4 the examples are the prototype's own random rows (12 per task, sequences of length 0–7), not the kernel's `:spec` rows, which §8.5 uses.

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

- **Nested guard splits overfit.** Allowed at every size, they return case analyses whose guards fit the training rows by accident: rotate-left on 3 of 9 example sets, map-adjacent with `f` on 6 of 9. The prototype therefore accepts a single guard at first fit and tries nested splits only when the budget is spent. On these example sets, requiring a split to be size-minimal changed no outcome and cost 35–1,100× more candidates. On the kernel's own, much shorter spec rows it does change the outcome (§8.5). A split needs an acceptance test stronger than "fits the rows"; §8.8 says what the design takes from this.
- **A function argument is only as determined as its examples.** The one miss in 135 is an example set in which the only non-commutative operator appears on one-element sequences, so nothing fixes the argument order. This is the kernel's `foldl` impostor again, and the store's check for it is the one in §5.5.
- **Folds to a scalar fail under lifting as the prototype built it**: `sum`, alternating sum, and a Horner evaluation. With a `fold` form whose step is enumerated by class, they are found after 21, 51, and 157 fold programs; alternating sum needs a right fold. §8.5 shows that `sum` fails here only because the prototype's collect could build lists and nothing else.
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

For `+`, `−`, and `*` these are the answer terms (the kernel's code calls them witnesses) that the kernel reaches by two other routes: its milestone code, on a full grid with a supplied language of answer terms, and its bootstrap, from hand-written spec rows. Here they come from the operator's table and the grammar already in scope.

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

- **Memory is the wall, not time.** By that extrapolation, the sizes an hour could reach by time alone would need about 0.2 TB, and ten hours 1.2–2.4 TB. Two of the prototype's own runs did die at a 10 GB heap. A test on labels lets most classes go unstored in two situations, pure ring arithmetic with a target and a search whose answer has a firm size bound, but neither was measured near the wall of this table (§7.6, §8.7).
- **Dedupe is worth less on rich arithmetic than on polynomials or on the kernel's list grammars.** Once `div`, `mod`, `max`, and `min` are in, 30–40% of candidates are genuinely new behaviours on 32 random rows. The 99% duplicate rate of §2.3 was on few rows and list-heavy grammars. Both are real; what dedupe saves depends on the grammar and the rows.
- **Ten hours buys one or two more nodes than one hour.** This is the same logarithm as §2.3, on a different engine.

The kernel's measured candidate rate is 118–248 thousand per second (empirical report, §2), so the prototype evaluates 8–17 times as many candidates per second, on four to five times as many rows. The prototype does no metering and no bit accounting, so read that as an upper bound on what evaluation by column could give, not as a prediction.

### 8.5 The prototype on the kernel's own spec rows

§8.1 used the prototype's own examples. The outside review ran it instead on the kernel's `:spec` rows, which are far fewer: 3 to 13 rows per spec. Those runs were repeated independently, with the review's changes to the prototype rebuilt in 23 lines. Held-out scoring is on 200 fresh inputs, against transliterations of the library's own definitions that were confirmed against the kernel's VM **[M]**. Source and logs are in `plan_v2c_audit/verify-review/`.

One caution first, in the review's words and correct: the prototype validates the store, not the general synthesizer. Its control is a fixed, one-level procedure. Requirements with holes, refinement in more than one step, the instance space, and the derivation space are not built.

| Kernel spec | Result on its own rows | Note |
|:--|:--|:--|
| `copy`, `inc-all`, `dbl-all`, `positions` | 200/200, as a `tabulate` | 151, 408, 8,607, and 3 candidates |
| `scan` with a function argument; `shift-seq` | 200/200, with one guard | 11,604 and 8,781 candidates. `shift-seq` falls to 174/200 if held-out shifts may be negative; the spec's rows never are |
| `filter` | 200/200 at 1,383 candidates, once a one-argument Boolean call is in the grammar | without it, no answer after 1.58 million candidates |
| `sum-all`, `len-all`, `prd-all`, `last-or` | 200/200 through `fold` | on the prototype's unlifted path, which searches for a scalar term directly and uses no `fold`, `sum-all` and `prd-all` return impostors (23/200 and 20/200); `len-all` and `last-or` are solved on that path as well |
| `map-adjacent`, 8 examples giving 6 lifted rows | an impostor built from a guard split, 29/200, under first-fit acceptance; the right program, 200/200, when splits are accepted in size order | 616,232 candidates and 64 ms for the right one |
| `foldl` | an impostor, `(fold a (- acc x) xs)`, 81/200 | the spec's rows use only `f = −`, so they do not determine the function argument |
| `seq-corr` | unsolved as built; 200/200 once collect can take an aggregate | the sum over positions of `(* (at xs i) (at ys i))`; 20,713 candidates with the shape given, 3.05 million with it searched |
| `best-shift`, `argmax-corr` | unsolved | the prototype returns impostors scoring at most 43/200, where it should return nothing |

Thirteen of the sixteen specs reach 200/200 in some configuration of the prototype. No one configuration was run on all sixteen. Three results change the plan.

**Split acceptance has to respect size order.** On the prototype's own example sets of 31 to 51 lifted rows, requiring a split to be size-minimal changed no outcome and cost far more (§8.1). On the kernel's six lifted rows for `map-adjacent`, first-fit acceptance returns an impostor and size-minimal acceptance returns the right program. With size-minimal acceptance, all eight specs that return a sequence (`copy`, `inc-all`, `dbl-all`, `positions`, `scan`, `shift-seq`, `filter`, and `map-adjacent`) score 200/200. On the two that need a guard, `scan` and `shift-seq`, it costs 625 and 824 times the candidates. So the rule is the review's: a guard split is never accepted ahead of a smaller unsplit term. This plan calls it the *size-order rule*. The cost is real, and it is the price of having few rows.

**Collect can take an aggregate.** The prototype's collect gathered child cells only into a list. Letting it sum them, or take their product, maximum, minimum, or count, is nine lines for the operator and 44 to 71 with the search around it. It solves `seq-corr`, `sum-all`, `len-all`, and `prd-all`. It does not replace `fold`. It returned nothing on `last-or`, on an alternating sum, and on a Horner evaluation, for three different reasons. `last-or` is an associative aggregate whose identity is an input, which none of the five fixed aggregates has. The alternating sum needs an element term of about 17 nodes, beyond the size-9 search; that is a limit of budget, not of the mechanism. Horner needs a weight that no element term in the grammar computes; that one is genuinely sequential state. So the line that §7.3 draws is this: a reduction of an element-wise term is a change of space, and what stays outside is sequential state with a step that is not associative, when the intermediate values are not observed. The aggregate path has a limit of its own. With the shape searched rather than given, it also returns impostors on `foldl` and `argmax-corr`.

**The `foldl` spec is underdetermined, and the prototype cannot tell.** The check that would tell is the one in §5.5, and it is still unbuilt.

**The kernel's prices.** The same runs measured the kernel's present correction codes, which §6.1 and §6.3 rely on.

| Property | Finding |
|:--|:--|
| Integer distance | symmetric for every difference up to 10⁶, and logarithmic: 0, 4, 5, 5, 8 bits at differences 0 to 4, and 17 bits at 1000 |
| Sequences and code | asymmetric: 13 bits from `()` to `(1 2)` and 1 bit back; 15 bits from `x0` to `x0 + 1` and 3 back |
| Triangle inequality | holds on integers, fields, and tuples, and on sequences and code with small values. With large values it fails on some triples: 0, 2, and 3 violations in three random sequence grids of 3.4 million triples each, and 49 of 300,763 in a grid built to show them. From `(−100 −100)` to `(−100 0 0)` costs 21 bits directly and 6 + 9 through `(−100)` |
| Prefix-code bound | Broken wherever cells are priced one by one, because an exact cell costs 0 bits. A prefix code requires that 2 to the power of minus the length, summed over all code words, be at most 1. Here that sum is 1.5 for Booleans, 1.19 for GF(5), and 1.41 for integers. The present kernel's first search phase, which its code calls "Stage A" and which is not Stage A of this plan, does not price cell by cell, and leaves one bit per model unpaid instead. Pricing cell by cell occurs in the function `induce-row-order`, which is called only from the test suite |
| Inverse guard for `c = a·b` | the guard built from the table's uniqueness test and a forward replay of the answer is exact on all 1,681 pairs in [−20, 20]² |
| `anti-unify` | gives `(+ x x)` and `(+ y y)` one shared hole, `(+ ?0 ?0)`, and two holes for `(+ x y)` and `(+ y x)` |

### 8.6 Search across spaces, measured

Three measurements on the unmodified prototype put numbers under §5.9 **[M]**. Source and logs are in `plan_v2c_audit/cross-space/`.

**Do store-generated property sets prioritize mixing between tasks?** Thirty sequence tasks, each program form represented at least three times. For each task the prototype's own enumerator generated every Boolean term up to a small size over generic leaves (lengths, sums, minima and maxima of inputs and output, the output's first and last elements, integer inputs, 0 and 1). A task's *property set* is the set of those properties that are never false on its examples and true on at least half. The leaves were chosen once, by hand; nothing was written per task. Four further tasks were tried and dropped because the full grammar returned impostors on them. Then, leaving each task out in turn, the other tasks were ranked by the overlap of their property sets. Figures are means over five independent example sets.

| Property set | Nearest neighbour has the same program form | A grammar restricted to the 3 nearest neighbours' operators solves the task |
|:--|--:|--:|
| 446 properties (comparisons only) | 0.48 | 0.67 |
| 7,465 properties (with `+` and `−`) | 0.54 | 0.66 |
| types only | 0.32 | 0.49 |
| chance, or 3 random tasks | 0.15 | 0.58 |
| control: the 4 commonest operators in the rest of the pool, ignoring the task | — | 0.69 |

Computing every property set cost 648 candidates for the smaller pool, against 10.1 million to solve the thirty tasks with the full grammar. So the signal is nearly free, and for *form* it is real: three times chance and half again above types.

For *operators* it is not. The restricted grammar is right two times in three, which is no better than a control that never looks at the task. And the search cost is in the operators:

| Restriction | Fair cost, as a fraction of the full grammar (geometric mean per task) | Same, with the restricted attempt cut off at 100,000 candidates |
|:--|--:|--:|
| 3 nearest by property set | 0.77–0.83 | 0.68–0.72 |
| control (commonest operators) | 0.73 | 0.60 |
| 3 random tasks | 1.86 | 1.35 |
| oracle: the task's own operators | 0.085 | 0.085 |

"Fair cost" is the restricted attempt, plus the full grammar whenever the attempt fails. Without a cut-off, summed over tasks, the restriction by property set saves nothing (0.95–1.09 of the full cost): a miss costs a whole failed enumeration and then the full run. The oracle shows what a correct choice would be worth: a factor of 12 per task.

Three further findings:

- *Restricted grammars return wrong programs.* 2.7% of the attempts restricted by property set, and 6% of the control's, return a program that fits the twelve examples and fails held-out.
- *Form is not what needed predicting.* The prototype's second route (selection, `where`, `fold`) fails at once when it does not apply, so trying it first costs nothing and matches an oracle.
- *The properties cannot see between positions.* The generic leaves reach a sequence only through its length and three aggregates, and the output also through its ends. Two of the five recurrences show only the single property "output as long as input", which five tasks that are not recurrences show as well. Parity is not expressible, so `mod` is among the operators most often missing. A function-valued input is not a leaf at all.

So this first measurement is mostly negative: a set of properties computed at the boundary of a task tells the kind of program and not its content. A set of tags on a problem has no account of what each operator does to the tags. §6.4 gives the form that does, and §8.7 measures it.

**Is an analogy between two operators cheap to verify?** For unary maps f drawn from a small pool of terms, and pairs of binary operators p and q, the test is whether `f(p(a, b)) = q(f(a), f(b))` on every row of a grid. All 350 combinations were tested in 1.3 ms. Twenty-nine non-trivial ones hold, and none is false on 1,000 fresh rows. Seventeen carry an operator to itself, and the twelve that relate two different operators are all between `max` and `min`: negation carries `max` to `min` and back; doubling and negation carry `+` to `+`; shifts by a constant carry `max` to `max`. Against `append` on sequences, `len` and `sum` go to `+`, and `max` and `min` go to themselves. 96% of the combinations that fail are rejected by the first row read. A pre-filter that compares the operators' algebraic flags skipped a third of the failures, was unsound with a richer pool of maps, and what it saves is the reading of about one row. This is §5.9's first case: when the map is a small term, crossing between two tables costs almost nothing, and checking is the cheap part.

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

### 8.7 Words and verb tables, measured

The mechanism of §6.4 and §6.5 is the outside review's, and the review supports it with experiments of its own. Each of those was rebuilt independently before it was used here, except the experiment on reuse across tasks, which was rebuilt only in outline. Several questions the review did not ask were measured as well **[M]**. This section gives the main results. The full record is `plan_v2c_audit/measurements-words.md`. It gives the figures quoted elsewhere in this plan and the arrangement each was measured in. So where another section cites §8.7 for a figure that is not given below, the figure is in that record. The commands and logs behind each figure are in the reports that Appendix D lists for §8.7.

Everything here is standard-library Python on a library of operators written by hand for the purpose, except one experiment that was run on a copy of the Lisp prototype of §8.1 and is marked. Nothing here runs on the kernel's own library.

**The setting.** The library has 61 operators: 31 that take a list to a list (`sort`, `reverse`, `filter_pos`, `running_sum`, `map_adj_sub`, and the like), 6 that combine two lists, 9 reductions, 11 on integers, and 4 that take an integer and a list. A task is 8 rows of a hidden composition of a few of them. A *candidate* is one operator applied to classes already found, and evaluated on all the rows. The baseline, *plain search*, is bottom-up enumeration of terms by size that keeps one term per class and uses no guidance. Unless stated otherwise the vocabulary is six words listed by hand: the signs present in a list, the parities present, whether it is sorted in either direction, its length capped at 5, its length modulo 2, and whether it is empty, with the matching words on integers. Each operator is run on probe values and grouped, once, into a verb table. A candidate is skipped, before it is evaluated, when its tables say it cannot give the target's labels within the size that remains. This test is the *label filter*. The size of the answer is not known, so the search is repeated in *rounds*: the size bound is raised by one each round, each round starts again from the leaves, and the candidates of every round are counted. A *gain* is the number of candidates plain search evaluates divided by the number the method evaluates.

**What the tables buy.**

| Method | Gain over plain search (geometric mean over 20 tasks; two task sets) |
|:--|--:|
| verb tables with six words, on all tasks | 17.5×, 18.5× |
| the same, on the tasks that need one of two operators kept out of all training of the count-based method below | 21.4×, 14.2× |
| the same, on the remaining tasks | 15.3×, 25.5× |
| verb tables used only to order the operators, with nothing skipped | 6.1×, 5.7× |
| counts of past use, used only to order the operators | 2.6×, 2.5× |
| types only (one figure, over 60 tasks) | 1.7× |

Plain search is averaged over random orders of the operator list, because the order matters: with the library in its listing order the first row is 13.9× and 16.7×. So the gain of the six hand-listed words runs from 13.9× to 18.5× with the set of tasks and the order of the operators, and the rest of this plan gives it as 14× to 18×. Five qualifications apply.

- *One control is missing.* The plainest alternative is to compare each candidate of the last size with the target one row at a time and stop at the first mismatch, with no tables. No Python run has it. In the store prototype that control cut candidates exactly as much as ordering by labels did, and took less time. Whether it would match the gains in this table is not measured.
- *Time gains are smaller than candidate gains.* Each candidate that survives costs about seven table look-ups. Wall time improved by 1.3×, 2.0×, and 4.2× at program sizes 4, 5, and 6.
- *In candidates the gain behaved as a constant factor.* On chains found at sizes 3, 4, 5, and 6 it was 14.4×, 11.1×, 11.6×, and 15.6×, with no trend.
- *More and finer words give more.* One word gave 2.8× to 6.4×, three gave 6.1× to 12.6×, and all six gave 15.7×.
- *Counts of past use fail when they set the order of enumeration.* Counts ranked the two held-out operators 51st to 58th of 61. When each operator was then given a cost that grows as its count falls, and terms were enumerated in order of total cost, 5 of the 8 tasks that need one of the two ran past a cap of three million candidates.

**Answers are lost, and how many depends on the probes.** A table built from samples can be wrong in one way that matters: the probes saw a combination of input labels, and never saw one of the output labels that combination can produce. For example, `take3` of a list that never increases and whose first three elements are equal is a constant list, which is sorted both ways; that did not occur in 3,000 random probes. A candidate on the path to the answer is then skipped. With random probes, 34 of 300 tasks were lost at 100 probes per operator, 4 at 300, 1 at 1,000 and at 3,000, and none at 10,000.

The review proposes to spread the probes evenly over the labels that occur, and to add edge cases. Its own test of that used transforms chosen by hand to suit the words under test. So four ways of choosing probes that use nothing written by hand were compared with each other and with the review's transforms. A *run* is one search for one task with one set of tables. The first column has 900 runs: 300 random tasks, each with tables built from three seeds. The second has 800: two sets of 200 tasks in which one of the eight rows is replaced by an unusual list, such as a constant list, each with tables from two seeds.

| How the probes are chosen | Answers lost in 900 runs on random tasks, at 300 / 1,000 / 3,000 probes per operator | Answers lost in 800 runs on tasks with an unusual row, at the same numbers of probes |
|:--|:--|:--|
| at random | 17 / 5 / 1 | 21 / 7 / 4 |
| at random, then spread evenly over pairs of labels | 4 / 1 / 0 | 13 / 5 / 2 |
| as small programs produce them: each argument is the output of a random term of up to two library operators, and both arguments are read on one shared row | 10 / 2 / 0 | 12 / 0 / 0 |
| **as small programs produce them, then spread evenly over pairs of labels** | **3 / 0 / 0** | **3 / 0 / 0** |
| random lists and the review's hand-chosen transforms of them | 7 / 2 / 0 | 13 / 3 / 1 |

At 1,000 probes per operator, the rule in bold lost no answer in the 1,700 runs, which cover 700 tasks. Random probes lost 12 and the review's transforms lost 5. The reason is that the inputs an operator meets inside a program are other operators' outputs. Sorted lists, constant runs, and two arguments that are related to each other then arrive without anyone listing them. The gain is the same under every rule, 17×, and building the tables takes about sixteen times as long under the rule in bold as with random probes.

The tables are still not sound. On streams of 4,000 tasks, the rule in bold still met a wrong entry on about 5 tasks in 1,000 at 1,000 probes per operator, and on 0.55 in 1,000 at 3,000. So the fallback stays. Two proposals were tested against that background. Feeding the transitions of tasks solved by the fallback back into the tables cut the rate three- to fourfold on those streams; it is left out of the first version and is a cheap thing to add later. Merging sign, parity, and order into one word of 38 labels gave 22× in place of 17×, and still lost 10 of 600 answers at 10,000 probes per operator; it is left out.

About 71% of table entries allow exactly one output label. A filter that uses only those entries has a gain of 10.2×, where a filter that uses every entry has 17.0×. Only the tables for length follow from anything that can be proved cheaply, and a filter that uses those alone has a gain of 3.6×.

**What a lost answer costs.** In one run of 234 tasks, with tables from 2,000 random probes per operator, 3 answers were lost. The gain averaged per task was 16×. With the three lost tasks retried by plain search, the saving summed over all tasks was 12.7×. Under the kernel's three-to-one reserve, where a found task costs four thirds of its filtered search and a lost task four times its plain search, it was 6.6×, against 12.1× under the same reserve had nothing been lost. In the same 234 tasks no target carried a label that no table mentions.

**One routine for the counting cases.** The review claims that laws, inverses, near misses, exact facts about labels, and verb tables are all one group-by. A routine of 30 lines was written and run on each case. For verb tables and exact facts about labels it needs nothing more. For an inverse it supplies the first step: given the table of `*` it reports that an argument is determined on 92.3% of the rows, and the guard and the term then took two small searches and 27 further lines. A law needs a test of equality instead. A near miss is not a counting case at all: on eight rows, grouping by a candidate's values left nothing over for a near miss and equally for a far-off term whose values are all different.

**Where labels act, and where corrections do.** The review argues that labels look several steps ahead while corrections only see the last step. That was measured on the same 234 tasks.

- *Labels act on the last step.* A class one step from the answer is any class of the true parent's size (§6.2). Among these classes the tables rule out 43–47%. Among classes two or more steps away, they rule out none. They never rule out a class on the path to the answer, though in 3 of the 234 tasks a wrong table entry ruled out the last step itself. Applying the tables throughout enumeration still doubles the gain over applying them only at the final size, 15.6× and 16.9× against 7.8× and 8.0×.
- *Corrections carry a signal at every distance, and nowhere one strong enough to cut on.* Rank every class of one size by the cost of the target given that class. One step from the answer the class on the path has a median rank at about the 2nd percentile, but it is in the worse half in one case of five. Two and three steps out its mean is the 29th to 39th percentile, where the 50th is chance. Keeping only the better half at each size lost 31 of 119 answers in one task set and 37 of 115 in the other.
- *The difference from which an offset or a scale is read is often not defined.* The correction code is defined for any two values. The element-by-element difference between a class and the target needs the same type and length, and was undefined for 41–43% of the classes on the path one step from the answer.
- *Next to the answer the correction breaks some of the labels' ties.* The labels leave the true parent tied with other classes for a quarter of the true parents. Inside those ties the correction ranks it first in about half the cases, where chance would give a little over a third.

**Proposals from near misses.** Two proposals can be read off a near miss (§7.2), and a third idea was tested for ranking near misses.

- *An offset or a scale.* On 192 tasks built so that the answer is a stored class plus or times a constant, the check was run in three arrangements. Inside the label-filtered search, on the classes the filter keeps, which is the review's arrangement, it evaluated 2.4 to 3.0 times fewer candidates than the filter alone, or 1.6 to 2.0 times fewer when each check is itself counted as a candidate. Run instead on every candidate that search evaluates, it halved the candidates again; this is the arrangement of §7.2. In a plain search with no labels it took 1.6 times more candidates than the review's arrangement. On the ordinary tasks, which were not built to contain a near miss, the proposal applied in 70 of 234 and was right on fresh rows in 64 of those.
- *A conditional.* On 120 tasks built as conditionals, the first split that fits is right in 82. On the ordinary tasks a split that fits the rows exists in 64, and the smallest is right in 2. A split that fits is nearly always an impostor unless something smaller has been ruled out first, which is the size-order rule of §8.5 again.
- *Regularity of the residual's labels.* The review proposed to rank a near miss higher when the labels of its residual are the same on every row. That puts an offset near miss first in 56 of 64 tasks, where the size of the correction alone does so in 22 to 29. It does little for a scale. On the ordinary tasks it moved the true parent up in 47 cases and down in 62, and on conditionals it only moved the right branch down.

**In the store prototype.** The label filter was also built into the Lisp prototype, with parity, residue modulo 3, and sign as the words, and run on its lifted sequence tasks and on the kernel's spec rows.

- *A filter applied strictly at one size destroys guard splits, and with rounds of increasing bound the branches were kept.* A near miss fails the labels on exactly the rows it gets wrong. In the prototype a filter that skips candidates was applied at the one size where the near miss sits. That size was handed to it, and the search stopped there. It lost the conditional in all 9 runs in which plain search builds one, and in 7 of the 9 when candidates that return a Boolean were exempted. In Python, with a size bound raised round by round, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test asked whether both branches were kept. It did not ask whether the guard was kept, or whether the conditional was then put together. Whether the rounds save the whole conditional inside the kernel is not known (§10, risk 14).
- *Used only to order the candidates of one size, labels gained nothing that a plainer test does not.* When the size of the answer is not handed over, the prototype cannot skip. It keeps one bank across sizes and does not restart, so a candidate skipped at one size would be missing at the next, and the labels can only reorder the candidates of a size. Reordering cut candidates 2.73× over its 15 tasks. Comparing each candidate with the target one row at a time gave the same cut and saved more time, 2.01× against 1.68×.
- *Labels pay as a look-ahead, once a firm size bound exists.* When a program that fits is already held, its size bounds the rest of the search, and a class that cannot reach the target within the bound is not stored. On seven guarded runs this cut candidates 36×, time 17×, and the classes stored 34×, and changed no answer. Types alone gave the whole saving on five of the seven. With the answer's size given, the classes stored fell from 25,639 to 270 on `reverse` and from 2,306,369 to 34,919 on `map-adjacent` with a function argument.

**Choosing the vocabulary.** The four steps of the procedure are in §6.5. It was run on this one library, with its thresholds set by hand and with tables built from random probes. It has not been run together with the probe rule above.

- *On integers the score finds the expected words.* Over `+ − * neg` every `(mod x k)` scores exactly 1. Once `div`, `mod`, `max`, and `min` are counted, `(sgn x)` ranks first of 1,109 candidate words on a grid of −10 to 10 with floor division, and an arbitrary predicate such as `(= x 1)` ranks 702nd. The first place depends on those choices: with truncating division `(sgn x)` ranks 4th, and on a grid of −20 to 20 it ranks 2nd.
- *On sequences it reaches most of the hand list's gain by a different route.* From a pool of 95,732 candidate words it chose vocabularies that gave 13.0× with six words and 15.3× with ten, against 15.8× for the six listed by hand, with one answer of 60 lost. Nine of the ten words have the length in them. The hand list's words for signs and parities are in the pool and rank about 4,000th.
- *The settings matter.* Three settings of the repetition threshold gave 14.8×, 13.0×, and 11.5×. Allowing at most 2, 4, 6, or 8 labels per word gave 4.8×, 8.4×, 12.2×, and 13.0×. With the fold forms the review named added to the grammar of candidate words, the gain fell to 10.3×.
- *The library in the grammar adds little.* Without the library's list operators in the grammar the gain was 12.8×. As the library was grown from 26 to 45 to 61 operators, the six words chosen at the first step were still worth 12.0× at the last.
- *Cost.* Building and scoring the pool took about 21 CPU-minutes.

**Memory.**

- *On a pure ring grammar, residues cut stored classes by about ten times.* On `+ − * neg`, reduction modulo a small prime commutes with every operator, so a class whose residues cannot reach the target's within the size bound is not kept. With two variables, stored classes fell 8.5× to 26× on six polynomial targets of sizes 7 to 13, and none of 200 random targets was lost. With `div` and `mod` in the grammar, 117 of 120 targets that need them were lost.
- *The test must come before the class enters the table used for dedupe,* or the saving falls to 1.2× to 2.6×. With the answer's size unknown the search restarts at each bound, and the restarts cost, on average at each size, between 1.0 and 2.1 times the evaluations of the last round.
- *On the sequence library the saving from labels is small:* 2.4× in classes and 1.5× in bytes. With no target, as in a search for laws, it is nothing.

**Three smaller results.** A guard is a two-label word and a Boolean column is a bit mask over rows, so whether a guard is valid for a law, and whether one guard implies another, are single mask operations. For four laws the weakest of 47 to 151 valid guards was found that way, such as `(<= b a)` for `max(a, b) = a`. On reuse across tasks: in five streams of 20 tasks, replaying every stored solution on the new rows found all 25 repeats at no more than 57 candidates each, where an index of past problems found 19, or 20 when variants of the retrieved solutions were tried as well. On likeness between operators: of the 32 operators placed by hand in seven families, 22 have a family member as the operator with the most similar verb tables, where chance gives 9.

**What these measurements do not show.** Every Python search result above is on a library of whole-sequence operators written for the experiment, with six words that were also listed by hand except where the text says otherwise. None of the Python runs has the plain early-comparison control. The near-miss tasks were built to contain a near miss. The procedure that chooses words and the rule that chooses probes were each run on that one library, with thresholds set by hand, and never together. The prototype result is on element-level arithmetic, where parity alone does nearly all of what three words do. The four steps of §7.2 were each measured on their own and have not been run together as one search. Nothing here has been run inside the kernel.

### 8.8 What the measurements change in the plan

1. **The lift claim stands, for position-wise, selective, and observed-recurrence functions,** on the prototype's own rows and on the kernel's much shorter spec rows (§8.1, §8.5). Tasks that need two lifts remain untested.
2. **A split is accepted in size order, never ahead of a smaller unsplit term** (§8.5, §8.7). This is the size-order rule, and it is part of the gate of experiment X3 (§11.2). Beyond it the store offers three further tests, in increasing cost: the guard must pay for itself in description length; the two branches must not fall into one class on a wider probe space; and a nested split must survive rows held back from the search. These three are available and are not part of X3's gate.
3. **A held split bounds the rest of the search.** The size-order rule is costly, and most of its cost is spent looking for smaller programs after a split is already in hand. That search has a bound, and with the bound a look-ahead can refuse to store what cannot reach the target (§7.2, §8.7).
4. **Collect takes an aggregate, and `fold` belongs in the refinement table as well** (§7.2, §8.5). The first covers reductions of an element-wise term. The second, with its step enumerated by class, covers sequential state.
5. **Laws are kept by use, not by completeness.** Classes do the pruning. A law earns a place in the library only when something reads it: to normalize before anti-unification, to carry a class to a new space, or to certify. The small-size basis, about 59 laws in §8.3, is kept, and anything larger is derived on demand.
6. **Hours go to breadth.** By extrapolation, the memory wall is reached in minutes on any one deep search (§8.4). Labels were measured to save much memory in two situations only: on pure ring arithmetic with a target, and as a look-ahead once a held answer gives a firm size bound (§7.6, §8.7).
7. **Experiments need designed rows.** A finite grid creates false dependencies at its boundary (§8.2), and random probes make wrong verb tables (§8.7). The rule that came out of the second, probing with what small programs produce, is rule 4 of §7.5.
8. **Words replace property sets and counts as the first form of guidance.** Comparing whole problems by the properties they share did not find the operators a problem needs (§8.6). Tables of what each operator does to labels did, in Python on one library, including for operators never used before (§8.7). Counts only adjust the order that the tables give (§6.4).
9. **The label filter is one tentative pass, not the search.** Its tables are tested knowledge, and it acts on the last step (§8.7). The check for near misses runs inside that pass, on every candidate the pass evaluates, including those the labels then decline to keep, and the plain search is the fallback for wrong table entries (§7.2). A filter applied strictly at the one size where a near miss sits discards it, as the store prototype showed. With rounds of increasing bound, in Python, both branches of every conditional built for the test were kept (§8.7). Whether the guard was kept as well was not asked. Whether the rounds let the whole near miss through inside the kernel is not known, and that is risk 14 of §10.
10. **The vocabulary and the probes are chosen by procedures with nothing listed by hand** (§6.5). In Python, on one library, the first chose a vocabulary to within a fifth of the gain of one listed by hand, and the second chose probes that lost fewer answers than the outside review's hand-picked ones (§8.7). The two were not run together, and neither has been run inside the kernel.

## 9. What to import, and what to leave

You lean toward a rewrite that imports the working components. The audit supports that, with one qualification about how much can be carried over unchanged.

About 3,500 lines are worth carrying over. Roughly 2,200 of them come across as code or as a design. Roughly 1,300 work through a frame today, and need that interface moved to spaces and requirements before they can be used. About 750 more are worth re-implementing from their idea and their tests. The kernel proper is 17,647 lines; about 370 of the lines to carry over are milestone code outside that count.

**Carry over**

"As code" means the file can be lifted nearly unchanged. "As design" means the mechanism is kept and the code re-derived for the new opcode set. "Re-seat" means it is sound and tested but takes or returns frames today.

| Component | Where | Lines | How | Why |
|:--|:--|--:|:--|:--|
| Ledger and work limit | `vm.lisp:10-54` | 45 | as code | exact accounting; depends on nothing |
| Evidence grades | `evidence.lisp` | 73 | as code | a certificate lapses automatically when anything it depends on changes |
| Matching and anti-unification | `unify.lisp:5-73` | 70 | as code | It generalizes any number of terms at once and respects types. Where the terms differ, the differing sub-terms, one from each term, are replaced by a hole, and the same combination of differing sub-terms gets the same hole wherever it recurs. An operator itself can become a hole when the operators have the same type signature (§5.4) |
| Persistence | `persistence.lisp` | 141 | as code | Saving, loading and saving again gives equal entries. On load, specs are replayed and certificates are recomputed |
| Finite-field certification, with counterexamples | `laws.lisp` | 228 | as code | the one working proof rule |
| Description-length-gated abstraction | `abstraction.lisp` | 580 | as code | it is what finds `:map`. Its acceptance test, by total description length, carries over. Its heuristics for which sub-terms to share are written for recursion on lists and will need rewriting for the new sequence primitives |
| Size-ordered enumerator | `enumerate.lisp:59-214` | ~150 | as code | to be joined with v2's behaviour table, which works when switched on |
| Metered, resumable evaluator | `vm.lisp:56-400` | 345 | as design | prepaid instructions, exact resume, four statuses. The per-opcode dispatch is re-derived, and §7.1 changes its unit of evaluation |
| Prefix codec | `codec.lisp` | 221 | as design | The size of a program is found by running the encoder as a counter that only adds up bits. The decoder rejects any code that is not the canonical one, so each program has exactly one code. The table that gives each opcode its code sets the prices, and you have said that the present prices need not be kept |
| Solver schema and fiber certification | `laws.lisp` | 186 | as design | "a solver is two laws" |
| Reserve scheduler | `synthesize.lisp` | ~125 | as design | the 3:1 tentative/fallback split. The formula is hard-coded; the shape is reusable |
| Resumable row-job stepping | `enumerate.lisp` | ~90 | re-seat | results identical however the run is sliced; assumes frame rows |
| Observation and bucket engine | `enumerate.lisp:563-877`, `laws.lisp:215-228` (these 14 lines are also counted in the finite-field row above) | 215 by one auditor's count and 315 by another's | re-seat | this already is "classes by behaviour"; depends on the enumerator and the row-job base |
| Requirement propagation, with replay and fallback | `laws.lisp:447-784` | 338 | re-seat | tentative use of tested knowledge, done safely; takes a frame |
| Root verification of every candidate | `synthesize.lisp` | ~45 | re-seat | what makes aggressive heuristics safe |
| Message-to-frame bridge | `messages.lisp` | 128 | re-seat | the seed of the derivation space; builds a frame |
| Guard and solver discovery | `milestones/algebra-discovery.lisp` | ~370 | re-seat | guards fitted to agreement masks, errors as outcomes; works through `support-frame` |

**Import the idea and the tests, rewrite the code**

- *Pullback* (`frame.lisp:544-580`): 37 lines; its soundness tests are worth more than the code.
- *Simplification of requirements that preserves definedness* (`requirements.lisp:129-540`). The kernel simplifies a requirement expression by rules, with one set of rules per opcode. Its code calls this "folding"; it is unrelated to the sequence primitive `fold` of §7.1. Because a candidate program may be partial, no rule may change where a requirement is defined: a rule that drops or reorders a sub-term applies only when that sub-term is provably total or, under the weaker of the two contracts below, when it is built only from parts that cannot fail (`requirements.lisp:136-149`). Each call of the simplifier names one of two contracts: the simplified requirement must be equivalent to the original, or it need only be necessary for it. Keep the two contracts and their tests. The rules themselves are per-opcode and will change.
- *Totality checker* (`ast.lisp:696-1101`). Two parts of it can be carried over; the rest is wired to specific opcodes. The first is the fact-and-measure scheme. A branch is judged under the facts that its condition establishes (`condition-facts`, 68 lines). A recursive definition is total when every step of its body is total under those facts and its self-calls descend in a lexicographic order on measures of its parameters. A measure is a sequence shortened by `tail`, an integer bounded below that is reduced by a literal, or an integer bounded above that is increased. The order is lexicographic in that a call which lowers an earlier measure may do anything to a later one. The test on self-calls is about 50 lines (`self-call-changes`, `self-calls-descend-p`). The second is the least-fixed-point discipline. Whenever a function is defined, the totality of every function is recomputed together, starting from the assumption that no function is total (`knowledge.lisp:514-545`).
- *Closure compiler* (`vm.lisp:402-551`): keep the idea of a fast path with identical cost accounting.
- *Metric decoder* (`laws.lisp:1250-1327`): keep the concept, an invertible operator with its solver; it becomes the `decode` construct.
- *From the earlier v2 plans.* This is the one list of what is worth keeping from them.
  - From Stage 0 of the v2 plans: its six soundness fixes, and its ablation harness `stage0-audit.lisp`, with the harness defect that the audit found repaired.
  - From Stage 1 of the v2 plans, the pieces that its auditor judged salvageable on their own. The first is behaviour pruning and column evaluation, once they are tested. The second is the definedness guard derived from an operator's preconditions. The third is difference facts for variable indices: short facts of the form u − v ≤ k, which let the totality analysis prove that a variable index lies within its sequence. The fourth is the index-preimage rules for `gather` and `evolve`. `(gather C Z)` returns the elements of `C` at the positions listed in `Z`, and `evolve` is v2's scan with state. The rule for `gather` works in the v2 code: `(= (gather C Z) Y)` splits into a length condition and, for each position, a set of admissible indices.
  - From the designs of the v2 plans, three ideas. The first is the distinction between lift, which is one program over all fiber rows, and split, which is a guard and a program for each region. The second is the replay guard for inverses: a candidate answer is replayed forward and compared, inside the definedness guard of the term that computes it, so the guard of a conditional solver needs no search (§7.2). The third is the pricing rule that each row of the root problem is priced exactly once, with no refund of bits for symmetry (Appendix B).

**The test contracts are an asset independent of the code**: budget obedience and resumption parity, codec round-trip, soundness of each pull-and-compose pair, soundness of requirement simplification under both contracts, and closure/interpreter equivalence. They should be the first thing ported and the gate on every stage.

**Leave**

- Most of `frame.lisp`, and all of `proposals.lisp`, `decompose.lisp`, `nogoods.lisp`, `descriptors.lisp`, `templates.lisp`, and the shape recognizers in `consolidate.lisp`. They are glue around the one-unknown frame, or task-shaped patches. Within the search files alone, the search audit counts about 4,800 of 7,101 lines that way.
- `bootstrap/recursion-schemas.lisp`, which describes itself as "the shape of one battery function ..., written by hand".
- The rest of v2's Stage 1 additions in `v2/`, in particular the container-cover proposal generator. They should be mined, not continued (§2.9).

On tariffs: nothing here preserves the present prices in bits or in work, and two of them are artifacts (§2.7). One is the name bits, which follow an operator's position in the list of primitives. The other is the work price list, which charges quadratic cost for operations that are not quadratic in the host. What must be preserved is the discipline: prefix codes, exact ledgers, and no refunds.

## 10. Risks, and where there is no precedent

Each risk is paired with what the design does about it and with the cheapest test that would expose it. Some rows have only one of the two. §11 orders the tests.

| # | Risk | What the design does about it, and what would show it |
|:--|:--|:--|
| 1 | Lifting by a change of space works in the prototype, on its own rows (§8.1) and on 13 of 16 of the kernel's spec rows (§8.5), and not inside the kernel, or on tasks needing two lifts | *Test:* the 16-spec ladder without whitelist, schema, or trace-shaped rows (§11, X3). |
| 2 | Inverses from tables stop at one-operator inverses. The audit's own run found the solver search "has a one-operator answer" in every case | *Design:* compose known inverses through a term. *Test:* `a*x + b = c` and `x + x = c`, which the present kernel cannot solve. |
| 3 | Classes on a small probe space merge terms that are not equal, and false laws accumulate | *Test:* count laws that fail on fresh rows. On the prototype there were none at 8 or more probe rows, and 199 at 3 rows (§8.3). |
| 4 | Counts over tens of solved problems carry no signal. The one existing learned predictor learned a constant, and in the measurements of §8.7 counts ranked operators they had never seen near the bottom | *Design:* the order of operators comes from the verb tables first, and counts only adjust that order (§6.4). *Test:* the guidance ablation, X4, before more is built. |
| 5 | The agenda fills the library with true, useless entries. One published law finder at 33 functions "generate[s] too many laws"; another's authors say more depth "does not lead to many useful lemmas" | *Test:* utility accounting by ablation on every entry (X5). The prototype's kept-law set already grows ×2.8 per unit of size (§8.3). |
| 6 | The rewrite grows. Three successive plans each promised a smaller kernel and delivered a larger one | *Test:* a complexity-score gate at each stage (your margin note: complexity scores are "less gameable" than line counts), and the ported test contracts. |
| 7 | Deep searches exhaust memory before time. Labels were measured to save much memory in two situations only: on pure ring arithmetic with a target, and as a look-ahead once a held answer gives a firm size bound (§7.6) | *Design:* bank memory is bounded by each problem's account, and hours go to breadth. *Test:* measure the classes retained per hour. |
| 8 | "The store's operations are programs" turns out elegant and unprofitable. The literature review found that reflection paid off only in cheap, measured forms: memoization, dependency graphs, partial evaluation, bandit allocation | *Design:* keep it off the critical path. X8 is last. |
| 9 | Guidance costs more than it saves, as the metric decoder did. In the prototype, on element-level arithmetic, ordering by labels gained nothing over a plain early comparison with the target, and the Python runs have no such control (§8.7) | *Design:* the per-column correction codes of §6.1 and §6.3 are needed whatever X4 shows. The words and verb tables of §6.4 and §6.5 are built further only if X4 passes. *Test:* X4, reported in time and not only in candidates, with the plain early comparison as one of its arms. |
| 10 | Anti-unification over few instances over-generalizes | *Design:* the existing description-length gate. *Test:* the negative controls already in `tests/theories.lisp`. |
| 11 | Search across spaces is spent on the wrong pairs, and costs more than it finds | *Design:* a budget account for every attempt. *Test:* X9. The comparison of problems by their property sets in §8.6 is not repeated on the kernel's tasks in any experiment of §11. |
| 12 | The vocabulary result does not carry over from a Python library of whole-sequence operators to the kernel's own library and its lifted forms. Comparing problems by the properties they share already failed for operators (§8.6). Verb tables worked on the Python library (§8.7). The procedure that chooses words and the rule that chooses probes were each run on that one library, with thresholds set by hand, and never together | *Test:* X4, on the kernel's own library. |
| 13 | Verb tables lose answers. They are tested knowledge. With 100 random probes per operator they lost 34 of 300 tasks, which is 11%. With 1,000 probes chosen by the rule of §6.5 they lost none in 1,700 runs, and on longer streams of tasks those tables still met a wrong entry on about five tasks in a thousand (§8.7). A lost task costs a whole plain search, and four times that under the reserve. In the one run where this was measured, 3 of 234 answers were lost, two of them on larger tasks, and under the reserve that halved the saving summed over tasks, from 12.1× to 6.6× (§6.4) | *Design:* use the tables to order, or to filter a tentative pass that has a fallback. *Test:* in X4, count the answers lost, and report cost summed over tasks with the fallback included. |
| 14 | Inside the kernel, the rounds of the tentative pass do not let near misses through as they did in Python, and answers that need a guard are hidden. A filter applied strictly at the one size where the near miss sits lost the conditional in all 9 runs of the store prototype in which plain search builds one, and in 7 of the 9 with Boolean candidates exempted. A filter with a size bound raised round by round kept both branches of all 120 conditionals built for the test in Python; that test did not ask whether the guard was kept (§8.7). Which of the two the kernel's tentative pass resembles is not known | *Design:* the near-miss check runs inside the tentative pass, on every candidate that pass evaluates, including those the labels then decline to keep, and the plain search is the fallback (§7.2). *Test:* X4 counts the answers that only the fallback finds. |

**No convincing precedent anywhere**, per the three literature reviews. The plan depends on the first three and, in part, on the vocabulary item below. The last is the plan itself. The others are deferred or avoided by design.

- A synthesizer learning the inverse rules it then uses. Hand-written in every synthesizer checked. *Depended on, in Stage A; shown for single operators on the prototype (§8.2).*
- A closed loop in which discovered laws, inverses, and abstractions become primitives for the next turn of the loop, on the same store. Abstraction alone has precedent, and plateaus. *Depended on; X5 is the test.*
- Algebra from depth-two experiments, and conditional equalities with learned guards kept in one store. Published guard search stops at about four nodes. *Depended on, in Stage D (X6) and for guarded laws (§5.5).*
- A self-generated curriculum. *Not depended on: tasks still come from external data.*
- A search policy learned by the synthesizer about itself that keeps improving. *Not depended on.*
- Higher-order functions from first-order primitives in hours. The one precedent used about 7,700 CPU-hours. *Avoided: the lifting forms are granted (§7.1), and `:map`/`:foldr` already emerge by anti-unification.*
- Recognizers of the autocorrelation kind invented from data. *Not depended on.*
- Termination guards learned from timeouts. *Deferred (§7.5).*
- A vocabulary that a system chooses for itself and that goes on improving its own search. *Stage C depends on the first half only: a vocabulary chosen with nothing listed by hand that passes X4. That it goes on improving search as the library grows is hoped for and not depended on. Guiding search by abstract values is established where the abstractions are written by hand (§6.7). Tables read off an operator's own probe rows, and a vocabulary chosen by score, were measured here in Python (§8.7). The compounding has no precedent. The one small test of it, choosing the words again as a library grew in three steps, showed little: with six words, the words chosen at the first step were worth nearly as much as those chosen at the last, and with ten words the gain rose from 13.5× to 15.3× between the first two steps (§6.5).*
- Coordinate spaces created from few samples without gradient descent; words as geometric modifiers. *Not depended on (§6.6).*
- A unified topology–geometry kernel. Nothing attempts it, and this plan is such an attempt. The working pieces elsewhere are value vectors and hash tables, which §5 uses, and rewrite systems, e-graphs, and decision trees, which it does not.

One cautionary sentence is worth keeping in view. It is from the authors of DreamCoder, about their own run that rediscovered `fold` from first principles in about 7,700 CPU-hours, which is most of a year of CPU time: "We do not advocate such blank-slate learning as a route to AI."

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
| Does a factored store make lifts, inverses, guards, and laws cheap? | Yes on the prototype: 15 of 15 sequence tasks, the arithmetic inverses with their guards, and the ring laws. Four limits were measured (§8.1, "What did not work") | §8.1 to §8.3 |
| Does the prototype hold up on the kernel's own spec rows? | Mostly: 13 of 16 specs reach 200/200 in some configuration | §8.5 |
| Do properties shared between whole problems say which problems to mix? | For a program's form, yes, at three times chance. For its operators, no | §8.6 |
| Is an analogy between two operators' tables cheap to find? | Yes when a small term carries it: 350 tested in 1.3 ms, 29 hold, none false on fresh rows | §8.6 |
| Does matching rows without a key need backtracking? | Not on irregular or symmetric data. It does on regular structures without symmetry, and heavily to reject look-alikes | §8.6 |
| Do tables of what operators do to labels cut search, including for never-used operators? | Yes, in Python on a hand-written library: 14× to 18× fewer candidates and 1.3× to 4× less time. No Python run had the plain early-comparison control | §8.7 |
| Can procedures with nothing listed by hand choose the words, and the probe rows? | In Python, on one library, and each on its own, yes. Words chosen by score gave 13× to 15× against 15.8× for a hand list. Probes chosen by the rule of §6.5 lost no answer in 1,700 runs, where random probes lost 12, but the tables are still not sound | §8.7 |
| Do labels rule out candidates several steps before the answer, and do corrections matter only at the last step, as the outside review argued? | No. Labels ruled out nearly half of the classes one step from the answer and none further away. Corrections were a strong signal one step from the answer and a weak one further out, and too weak anywhere to cut on | §8.7 |
| Does a check for near misses pay? | Where a near miss exists, yes. On tasks built to contain a constant offset or scale, a check run only on the classes the label filter keeps evaluated 2.4 to 3.0 times fewer candidates than the label filter alone, and a check run on every evaluated candidate halved the candidates again. On ordinary tasks it added little | §8.7 |
| Does a label filter hide answers that need a conditional? | Applied strictly at one size, yes: the store prototype lost all 9 conditionals, and 7 of the 9 with Boolean candidates exempted. With a size bound raised round by round, the branches were not hidden: Python kept both branches of all 120. Whether the guard is kept as well was not asked | §8.7 |
| Do labels pay inside the store prototype? | As an order, no more than a plain early comparison with the target. In a look-ahead bounded by a held answer, yes: 36× fewer candidates and 34× fewer classes stored, with no answer changed | §8.7 |
| Do labels save memory? | Much, in two situations: 8.5× to 26× fewer stored classes on ring arithmetic with a target, and 34× fewer classes stored with the look-ahead on the seven guarded runs, where a held answer gives a firm bound. Little elsewhere | §8.7 |

### 11.2 Next, in order

Each experiment except X8 has a gate fixed in advance. The standing metric for all of them is the **kernel-found fraction**: the share of library bits produced by search with no operator whitelist, no recursion schema, no trace-shaped rows, and no hand-written entry. Today it is 2.5%.

- **X1. Classes.** Build the store core (spaces, columns, hash-consed terms, classes, columnar evaluation) and run law discovery on it. *Gate:* the same 187 equations on GF(3) as the v1 kernel's bucket engine, which already groups terms into classes by behaviour (§9), plus distributivity; at least 10× less work than the v1 kernel's enumerator, which keeps every syntactic tree it builds (§2.3), at the same bound; retained memory proportional to classes, not trees. Also measure what pruning by already-found laws would add on top of classes (§5.8).
- **X2. Reorientation.** Find the eight arithmetic solvers and their guards from operator tables alone: no spec rows, and no language for the answer terms beyond the operators in scope. *Gate:* the same answer terms and guards the milestone code finds, including the unknown-divisor solver and the integer divisibility guard, neither of which the prototype produced. The two composite cases in risk 2 are reported, not gated.
- **X3. Lift.** Run the 16-spec ladder with the full grammar, no schemas, and ordinary input/output rows. *Gate:* at least 14 of 16 held-out-sound (today 8–10), where a spec that is correctly reported as underdetermined by its rows counts as sound; nothing returned that fits the rows and fails held-out; no guard split accepted that fails the size-order rule (§8.8, item 2). Also measure what the size-order rule costs with and without the look-ahead of §7.2 (step 4), in its types-only form, since labels arrive in Stage C.
- **X4. Does a vocabulary pay, inside the kernel?** On X3's tasks with 30 or more distractor library entries in scope, some of them never used in any solved task, compare six arms.
  1. No guidance.
  2. No guidance, with each candidate of the last size compared with the target one row at a time, stopping at the first mismatch. This is the plain early comparison, which matched ordering by labels in the store prototype and which the Python runs lack (§8.7).
  3. Types only.
  4. Counts of past use.
  5. Verb tables used only to order.
  6. The four steps of §7.2 run together as one search: a tentative pass filtered by the verb tables, with the near-miss check inside that pass on every candidate it evaluates, including those the labels then decline to keep, and the plain search as the fallback.

  The words are chosen by the procedure of §6.5 and the probe rows by rule 4 of §7.5, with nothing listed by hand. This is also the first time those two are run together. Count the fair cost of each search: every round of every pass, the fallback whenever the tentative pass misses, and the look-ups. Report the one-off cost of choosing the words and building the tables separately, with the number of tasks after which it is repaid. Report wall time beside candidates; cost summed over tasks beside the per-task average; the no-guidance arm averaged over random orders of the operator list, because the order alone changes the gain (§8.7); every answer lost; and every answer that only the fallback found. *Gate:* arm 6 takes at least 3× less total search wall time than arm 1 on held-out tasks, including those that need a never-used entry, with no answer lost after the fallback, and a one-off cost that is repaid within the task set; or §6.4 and §6.5 are not built further. Arm 6 must also take less total time than arm 2. If it does not, the plain comparison is doing the work and the tables are not needed for it.
- **X5. Compounding over hours.** Run the agenda of §7.5 for one hour and for ten, from the primitives and the task data only. Report entries found per hour by kind, held-out tasks solved before and after, and an ablation of every entry. *Gate:* the function set of today's library recovered with zero hand-written entries, and later tasks measurably cheaper than earlier ones.
- **X6. Depth two.** Laws over spaces whose rows range over functions (map fusion; fold over map); anti-unification over accepted solutions on the instance space. *Gate:* `:map` re-emerges with a positive saving in description length, as it does now; at least one two-function law is found and survives fresh rows.
- **X7. Reflection.** Replay, the problem memo, and counts from the derivation space, each under ablation. Replay is built in Stage C, and so are the counts of operators in accepted solutions, which the price of a name and arm 4 of X4 need. The memo and the counts of moves, which are read from the derivation space, are built in Stage D. *Gate:* a measured reduction in work on problems not used to collect the counts.
- **X8. Self-description.** Write the store's own operations as VM programs and pose one of them as a synthesis task. *Gate:* none; this is exploratory.
- **X9. Search across spaces** (runs alongside X4). Build colour refinement with backtracking on the store's group-by and re-index, and the form of problem in which the hole of a requirement has the type of a map (§5.9, first consequence), each attempt on its own budget account. Re-express the prototype's subsequence aligner as a map search under an order constraint. *Gate:* the selective specs still solve with the hand-written aligner removed, and analogies between operator tables are found as terms, as in §8.6.

### 11.3 Stages

| Stage | Contains | Ends when |
|:--|:--|:--|
| A | Store core; imported VM, codec, evidence, enumerator, certification; ported test contracts | X1 and X2 pass |
| B | Requirements with holes; the refinement table of §7.2; spaces with maps; the size-order rule, with the look-ahead of §7.2 in its types-only form | X3 passes |
| C | The agenda; utility accounting; replay of stored solutions (step 1 of §7.2), which needs only the library and not the derivation space; the vocabulary of §6.4 and §6.5 (words chosen by score, verb tables, the order and price of names); the tentative pass with its near-miss check, and the look-ahead on labels (§7.2); search across spaces by term, by refinement, and by capped backtracking | X4, X5, and X9 pass |
| D | Depth-two spaces; abstraction over classes; the derivation space and its other readers (§7.4) | X6 and X7 reported |

Stage A is the smallest piece that tests the central claim. X1 is shipped technique throughout. X2 is this plan's own mechanism, shown so far only on the prototype and only for single operators. If X1 or X2 fails, the plan is wrong at the root and that is known within the first stage. Stage B rests on the plan's own lifting mechanism, shown so far only in the prototype, on its own rows and on the kernel's spec rows (§8.5). The larger research risk sits in X5 and X6.

Three working rules, drawn from what went wrong before (§2.9; plan 9 audit):

1. **Run, then write.** No number enters a plan document without a script that reproduces it.
2. **One increment, one gate.** Each gate is tied to a recorded baseline before the work starts.
3. **The kernel does the next experiment.** When an agent finds itself running a simulation on the kernel and reading the result, that experiment is a candidate for the agenda of §7.5. This was your own observation during plan 9.

---

## Appendix A. Direct answers to the points in your prompt

| Your statement | Finding | See |
|:--|:--|:--|
| "wondered if the frame representation is correct and properly supportive of all the operations required" | A frame is right for one thing: a per-row predicate on one unknown, pulled back by substitution. It cannot hold a relation among unknowns, a position, or anything about expressions. | §2.1, §2.2 |
| Of anti-unification: "really it's a form of quotienting and trivial lifting under substitution" | As intuition, yes. | §5.4 |
| "an expression is a common pattern found in the execution graph, just lifted to independent contexts" | Exactly the factorization pattern × rows. The store is built on it. | §5.1 |
| Topology "can be learned in the process of executing the simulator ... (holding all but a few constant)" | Supported. A dependency test is a group-by on a table. The kernel has it in one function, `target-sensitive-p`, whose only caller in the kernel is itself reached only from tests. The method has precedent for numeric laws, from BACON (1977 to 1981) onward, and for finding what a program's output depends on, as in dynamic slicing. The literature auditor checked these against abstracts only (lit-discrete report, its finding 7) **[L, abstract only]**. | §2.4, §5.3, §6.1, §7.5 |
| "Algebra emerges from running parallel and depth >= 2 experiments" | Experiments at depth one exist and work, within the fields, operators and bounds that the bootstrap script fixes. Nothing today runs the observation engine over expression-valued inputs. Spaces whose cells hold terms are the proposal. The closed loop has no precedent. | §2.4, §5.4, §10 |
| "A conditional is a partition ... here it's learned experimentally" | Already implemented that way in the milestone code: an agreement mask becomes a Boolean target. A guarded law is a class on a sub-space. | §2.4, §5.5 |
| "Making a tuple is an explicit example of instantiating a connection or edge, albeit one with coordinates" | Yes. A row is a tuple, and a tuple is an n-ary edge; a table is a relation. Store the factorization, not the instance graph. | §4.2, §5.2 |
| "lift has to be a synthesizer primitive just like substitution is ... Presently ... wholly in the host lisp" | Confirmed, and wider: of the operations you list, only substitution, value projection, tuples, and `if` are available to a program. | §2.2 |
| Reentrancy as "freely shifting abstraction level" | Blocked by eight concrete things, listed in §2.2. | §2.2; search-engine report §6.2 |
| "there are a good number of guards for this in the kernel, afaik" | 30 of the 158 hard-coded decisions are dedupe or memo guards. | §2.3 |
| "'residuals' of frame becoming a bit clunky ... not sure if there are better options ... other than pricing in the original or ambient spaces" | The clunkiness comes from three facts of the implementation, of which the first is that one thing has eight representations (§2.7, §6.3). Pricing in the ambient space is not the cause. No derived space can price a residual below its ambient cost, with two exceptions: a verified bijection between the two spaces, or payment of the bits that name the member of the fiber (§6.3). | §2.7, §6.3 |
| Policies and heuristics "harder to naturally implement" | The one learned policy is a small program, induced by the kernel's own search from six integers that describe a sub-problem, whose output is a clamped adjustment to that sub-problem's priority. It learned the constant 0. | §2.6; core-repr report, §5 |
| "high-D embeddings are 'flat' ... there could be good reason for keeping the vectors flat" | Not a question of what can be represented. | §4.5, §6.6 |
| "Poor data representation seems to have induced overbearing incidental complexity & compartmentalized algorithms" | Supported: one concept implemented three or four times; fourteen kinds that are one struct; eight residual forms. | §2.2, §2.4, §2.7 |
| "underwhelmed with the quantity of information that can be abstracted to the bootstrapped knowledge library" | 2.5% of library bits come from generic search. | §2.5 |
| Totality: "support learning them by tolerating crashing or non-terminating behavior" | The VM already returns a crash and a cutoff as data. Totality never gates execution. It gates certain rewrites, and also frame metrics and metric decoders. | §7.1, §7.5; `plan7/plan7-recursion.md` L97; core-repr report, §2.4 |
| "it's been the AI agents that are doing the majority of search" | Confirmed. Nothing in the kernel initiates discovery, and an answer key preceded the bootstrap. | §2.4, §2.5 |
| The search budget "was very limited" | True by four to five orders of magnitude, and not the binding constraint. | §2.3 |
| "we'd need an efficient graph isomorphism test (not for AU of course), or e-graphs" | Within a space, neither. Rooted, ordered, shared terms are compared by hash. This plan proposes to compare laws up to renaming of their variables by trying every renaming, which is affordable only while laws have few variables; that has not been built or measured **[P]**. Across spaces a matching engine is needed, as you say: colour refinement with backtracking, run only on the pairs that cheaper signals propose (§5.9). An e-graph's store is worth having, and its saturation is not (§4.3). | §4.3, §5.9, §7.6 |
| "nothing 'very interesting' was findable in the small budgets" | The largest expression found by enumeration has 8 atoms. But distributivity was findable in under a second, when asked directly. Some of "not findable" was "not asked". | §2.4, §2.5 |
| "some of the fundamental datastructure choices are OK" | Agreed. Columns, a behaviour table, and a shared term graph are common to both earlier plans and survive here. | §9; the `docs-v2b.md` and `docs-v2tex.md` reports |
| The geometry dialog is "not ... a closed case" | Agreed. | §6.8 |

## Appendix B. Mechanisms the earlier audit passes rejected

This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2). One further item has a relative here. The pass that removed the spectral embedding also removed graph hashes made by colour refinement. This plan uses colour refinement to match rows across spaces (§5.9), where every match is then checked exactly, and that use was measured (§8.6). The three word types of §6.4, 'like', 'action' and 'analogy', are your own, from the prompt. They are objects in the store, and they are not the rejected query language. The table lists the rejections that bear on this plan. The full record, of about thirty rows, is in the `docs-v2tex.md` report, §3.1. The reasons given for each rejection are those recorded in the revisions of `plan_v2.tex`.

| Mechanism | Why it was rejected |
|:--|:--|
| A 256-dimensional vector-symbolic bus, with binding as "creating a space" | computation in superposition is only quadratically efficient; unbinding noise; no composition in one layer |
| Sheaves with learned restriction maps | learned maps rarely beat the identity |
| A five-extension e-graph (relational matching, thinning union-find, colored classes, AC multisets, e-graph anti-unification) | never combined in any published system; the plan's own combination equated `x0 − x1` with `x1 − x0` |
| Consistency radius as a residual price | double-counts rows covered by three or more patches |
| Cohomology as a source of nogoods | signed combinations cancel when no discrete solution exists |
| A symmetry refund of −log₂\|Sym\| bits | violates the Kraft inequality when the child is a program |
| Branch forking on every `if` | 2ⁿ worlds on `filter` |
| Accumulator synthesis from a source loop | input/output synthesis has no source loop |
| Cross-multiplying through integer division | division truncates |
| A trained attention router | more weights than library entries |
| Associativity and commutativity hard-coded in the term constructor | domain content in host code |
| Hand-written recognizers in host code for correlation, differences, and linear recurrences | domain solvers in the core |
| A spectral embedding, graph hashes by colour refinement, and a `like`/`analogy`/`act` query language | interpreter weight at a library of a few hundred |
| A difference-bound matrix on every enumerated expression | 10–30× more than needed |
| Permutation search for unordered covers | factorial |
| `:tabulate` and `:loop` opcodes (rejected in one pass, restored in the next) | "smuggled" higher-order functions; see §7.1 for the line this plan draws |
| A subsequence propagator specific to `filter` | hard-codes one library function. **The prototype's selection lift uses a subsequence alignment**; see §7.2 for the argument |

## Appendix C. Literature, with maturity

"Shipped" means load-bearing in widely used systems. "Replicated" means several independent working implementations. "One lineage" means one original system together with the systems that build directly on it, which is less than replicated. The literature reports carry a verification tag on every figure, and the citations. Most figures below were checked against the source online. These were not: the 17-year span for OpenCog (from memory; its benchmark claim was checked against an abstract); FlashMeta's deployment and the identity of e-graphs, version-space algebras, and tree automata (abstracts only); anti-unification as a product (a summary only; the paper could not be fetched). The auditors also declared three gaps. Three of four sub-searches on 2025–26 work ran out of quota, so "none found" for learned inverses and learned termination guards is a weak negative. Some figures exist only in plots. All line-count estimates for minimal implementations are the auditors' own.

| Technique | Maturity | The number that matters | Role here |
|:--|:--|:--|:--|
| Hash-consing, union-find, congruence closure | shipped | n log n | the term graph |
| Value vectors with observational-equivalence classes | shipped | standard backbone of bottom-up synthesis | classes |
| Law discovery by testing and collision (QuickSpec 2) | replicated | 398 laws over 33 functions to size 7 in 42 min, one thread; size 8 exhausts memory | §7.5 laws |
| Pruning the set of all terms with laws already found (Ruler) | replicated | 350 s with it; unfinished at 24 h without | not adopted as such: the plan prunes by class and keeps laws by use (§5.8) |
| Conditional laws with searched guards (Speculate, Chompy) | replicated, small guards only | conditions to size 4; 26 min for 14 operators | classes on sub-spaces |
| Preconditions from failures (PIE and relatives) | replicated | 87 of 101 correct; a larger predicate grammar hurt in 65% of cases | guards |
| Equality saturation | shipped in one compiler, in a restricted form (acyclic, eager rewrites) | average class size 1.13; ~0.1% from multiple representations | not used |
| Binders and conditions inside e-graphs | one paper and one preprint for binders; one research group for conditions | — | not used |
| Deduction through `map`/`fold` combinators (λ²) | one system; its family is replicated | median 0.43 s; >60% time out without type pruning | the refinement table (§7.2) |
| Recursion synthesis from examples (Myth, Escher, Burst) | replicated | functions of 15–30 nodes in under 1 s when the context holds only the helper functions needed; adding five generic helper functions to the context raised one task from 0.07 s to 128 s | §7.3 case 5; the control problem of which library entries are tried on a problem (§4.1, §5.9) |
| Library learning by compression (EC², DreamCoder, Stitch) | replicated | roughly doubles solve rates, then plateaus; fold from first principles ≈ 7,700 CPU-hours | abstraction; the argument for granting lifting forms |
| Grammar reweighting during search (Probe) | one system, re-implemented once by another group | 91 of 140 against a weak baseline's 44; modest against a strong one | counts of past use: they failed when they set the order of search for operators never used before (§8.7), and are kept as the price of a name and as a limited adjustment to the order that the verb tables give (§6.4) |
| Property signatures (BUSTLE) | one lineage | 45 hand-written properties beat learned embeddings, both as input to a trained network | the property sets compared between whole problems, which did not find the operators a problem needs (§8.6) |
| Witness functions (FlashMeta) | shipped, hand-written | — | precedent for inverses, not for learning them |
| Relational interpreters run backwards | replicated, impractical | staging made the benchmarks that run through nested interpreters 6–178× faster | avoided |
| Uniform hypergraph stores as learners (OpenCog, Hyperon) | no quantitative result in ~17 years | — | avoided |
| Learned coordinate embeddings (hyperbolic, knowledge-graph, sheaf) | need gradient descent and ~10⁵ examples | Euclidean matches hyperbolic from 50 dimensions; a rule miner matches graph embeddings | not used |
| Computation in superposition (Adler and Shavit) | theorem | n neurons compute at most O(n²/log n) features; representing needs O(log m) | the flat-versus-nested answer |
| Words as program fragments with count alignment (LAPS) | one lineage, on a neural search component | 42.6% → 82.0% in one domain; weaker with human descriptions | aligning labels supplied by people, which comes last (§6.7) |
| Synthesis guided by abstract values, with abstract semantics written by hand (Blaze, Simba, Absynthe) | replicated | 519 of 544 bit-vector problems against 456 and 409 for two enumerative solvers; one of those two wins on the suite's conditional problems | the filter of §6.4, where the tables are instead read off probe rows (§6.5) |
| Abstractions learned for such a synthesizer (Atlas) | one system | 8.3× and 9.2× over hand-written abstractions on its own benchmarks, 2.1× and 3.1× on its predecessor's; needs training problems and hand-supplied operator axioms | nearest precedent for choosing words, which are quotients of values (§6.5) |
| Abstractions merged and shrunk automatically, for planning heuristics (Merge-and-Shrink) | replicated, in planning | perfect heuristics in polynomial time in three of the six benchmark domains that have polynomial-time optimal algorithms; lower total coverage than most competitors in the paper's own comparison | not adopted: merged words lost answers (§8.7) |
| Reflection that compounds (AM, EURISKO) | unreproduced | by their author's own analysis, their apparent discoveries leaned on a representation in which short programs happened to denote interesting concepts | not depended on |

## Appendix D. Audit reports, and housekeeping

**Reports.** The reports behind this document are in `plan_v2c_audit/reports/`. Each gives file-and-line citations and its own list of what it could not determine. The scripts and logs behind each measurement are in the folder named beside it. The outside review is `plan_v2c_audit.md` at the repository root, and `plan_v2c_audit/revision-notes.md` records what was taken from it and what was not.

| Report | Scope | Scripts and logs |
|:--|:--|:--|
| `core-repr.md` | data structures and VM; the operation table; index handling | `scripts/` |
| `search-engine.md` | search algorithm; budget inventory; the 158 hard-coded decisions; reentrancy | `scripts/` |
| `laws-library.md` | algebra discovery traced; the 14 kinds; conversions; anti-unification | `scripts/` |
| `bootstrap-reflection.md` | provenance of every library entry; what reflection exists | `scripts/` |
| `empirical.md` | baseline, throughput, growth, the budget ladder, algebra scaling, profile | `scripts/` |
| `docs-origins.md` | original prompts and plans 1–4 | |
| `docs-plan6-results.md` | plans 5–6 and the measured results record | |
| `docs-plan7-arch.md` | plan 7 and the two architecture documents | |
| `docs-plan8-9.md` | plans 8–9, the plan 9 audit, batteries and reflection | |
| `docs-v2b.md` | `plan_v2.md`, `plan_v2b.md`, and the PDF annotations | |
| `docs-v2tex.md` | `plan_v2.tex`, its revisions, and the code of v2's Stage 1 | |
| `lit-discrete.md` | graph stores, e-graphs, rewriting, anti-unification, reflection towers | |
| `lit-search.md`, with its working notes `lit-search-appendix-*.md` | law discovery, enumeration at scale, library learning, guards | |
| `lit-geometry.md` | embeddings, spectral methods, pricing, language | |
| `lit-abstraction.md` | the literature on synthesis guided by abstract values (§6.7) | |
| `proto.md` | the prototype of §8.1 to §8.4 | `proto/` |
| `verify-review.md` | the prototype on the kernel's spec rows, and the kernel's prices (§8.5) | `verify-review/` |
| `cross-space.md` | search across spaces (§8.6) | `cross-space/` |
| `verify-quotients.md` | verb tables on the 61-operator library; the dependency score on integers and on sequences; residues on ring arithmetic; weakest guards; reuse across tasks and likeness between operators (§8.7) | `verify-quotients/` |
| `verify-words.md` | choosing the vocabulary (§8.7) | `round3/q1-words/` |
| `verify-probes.md` | choosing the probe rows; feedback, merged words, and slices; what can be certified (§8.7) | `round3/q2-probes/` |
| `verify-memory.md` | the memory rules of §7.6, in Python (§8.7) | `round3/q3-memory/` |
| `verify-handoff.md` | the one counting routine of §6.2; labels against corrections; near-miss proposals; a target the tables do not predict, and the summed-cost figures (§8.7) | `round3/q4-handoff/` |
| `verify-proto-labels.md` | the label filter and the look-ahead inside the store prototype (§8.7) | `round3/l1-proto/` |
| `measurements-words.md`, which is in `plan_v2c_audit/` and not in `reports/` | the full record of the measurements that §8.7 gives in short | the folders of the six reports above |
| `factcheck.md`, `factcheck2-A.md`, `factcheck2-B.md`, `factcheck3-A.md`, `factcheck3-B.md`, `factcheck3-C.md`, `factcheck3-final.md` | independent checks of each version of this document against the logs and sources | `verify-quotients/factcheck/` for the second round |
| `clarity-review.md` | a first-time reader's review of the audit and proposal sections for clarity and repetition | |
| `clarity-review-new.md` | a first-time reader's review of the parts written on 26 November: the front matter, §1, §6, §7.2, §7.4 to §7.6, and parts of §8, §10, and §11 | |
| `clarity-gaps-sec2.md`, `clarity-gaps-sec4-9.md` | what the clarity pass had to look up to fill a gap, and the gaps it could not fill from any source | |
| `glossary-sec2.md`, `glossary-sec4-9.md` | the terms that the clarity pass defined, each with the section that defines it | |
| `apply-*.md` | the logs of applying the third round of checks: one line for each finding, saying whether it was applied, was already fixed, or was not applied and why | |

Where the reports disagree with one another (throughput, candidate rate, a few line counts), `factcheck.md` tabulates the disagreement and says which figure this document uses.

**Things found along the way that are not about the design.** They were found at commit `15e64c6`, before the move to `v1/` that the front matter describes, and the file references are to be read under `v1/`.

- At the time of the audit, the v1 kernel's test suite failed on a clean checkout. The repository root had no tracked `library/`, and the suites `lifting`, `metrics`, `structural`, `invariants`, and `theories` need it. The remedy then was to run `make bootstrap` first, or to track the generated files as `v2/` does. This was not rechecked after the move.
- Five documents cited by the trail were never in the repository on any branch: `plan7-recursion2.md`, `audit-review.txt`, `plan8-2.md`, `plan-let.md`, and `plan_v2_annotated.pdf`.
- `architecture2.md` was stale on the day it was committed and has drifted further (27 primitives, not 26; 14 kinds, not 11; several named functions are gone).
- `v2/package.lisp:66-69` exports about ten symbols that are defined nowhere.
- In `v2/`, `(tabulate n F)` with `F` a code variable fails an assertion at construction (`v2/ast.lisp:1096` against `:673`).
- One defect in the harness of v2's Stage 0, seen twice: a failed synthesis leaves its oracle stub defined, so later specs lose a prerequisite, and the `argmax-corr` "FAIL" is the resulting commit error after a correct search. With that repaired, and a clean library for each spec, one auditor's recount of the four regimes is 16, 10, 11, and 9 of 16, not 16, 9, 9, and 8. This document keeps the harness's own figure of 8 as the baseline in §2.3 and X3, because the budget ladder was run against it.
- Evidence soft spots: one milestone path attests sampled integer uniqueness as `:derived`; arithmetic solvers for `*` and `/` carry no certificate, only a hand-set flag.
- `body-size` is documented as constant-time and is linear.
- Two pricing defects. The outside review reported the first, and the second was found while checking it. An exact cell costs zero bits in `correction` (`frame.lisp:1581`), which breaks the prefix-code bound wherever cells are priced one by one; and `frame.lisp:1572` takes the cheaper of two codes without paying to say which. The first is not reached in the main pricing path of the kernel's first search phase (its code calls it "Stage A"), which under-pays one bit per model instead; it is live in `induce-row-order`, which is called only from the test suite. The second sits in the sequence branch of `correction`. By a reading of the code that was not run, the kernel's first phase reaches it for every exception row with a sequence target; how often it changes a price was not measured.
- The outside reviewer's own scripts are not part of the review. A copy of them is in `plan_v2c_audit/round3/reviewer/`, because nine scripts under `plan_v2c_audit/round3/` run them, and one figure of the full record behind §8.7 comes from one of those: that the review's result of no misses held for 7 of 20 probe seeds. The nine scripts name that folder by its full path. The five reports of 26 November name a scratch folder as their work directory; the same files are under `plan_v2c_audit/round3/`.
