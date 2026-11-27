# Clarity and redundancy review, round 3

Scope: `02.0`–`02.9`, `03.0`, `04.0`–`04.7`, `05.0`–`05.9`, `07.1`, `07.3`, `09.0`, `AA.0`, `AB.0`, `AD.0`, `AE.0` (15,135 words). The Summary (`01.*`) was read for repetition only. Sections 6, 7.2, 7.4–7.6, 8, 10, 11 and Appendices C, F, G were read only to follow cross-references.

Method: read as a first-time reader. No fact was checked and nothing under `/home/tlh24/lisploop` was opened. Where a rewrite needs a fact that the document does not give, the gap is marked inside the rewrite in square brackets, as `[confirm: ...]` or `[say ...]`. Line numbers are the line numbers of the section files.

## What the review found, in brief

1. **The main clarity problem is vocabulary, not sentence length.** About thirty internal names and coined terms are used with no definition, or before their definition. Eight ordinary words are used in two or three senses ("Stage", "node", "class", "fold", "witness", "quotient", "signature", "probe"). A reader who does not know the code has to reconstruct these. Items A1–A9, A12, A24 and A56 cover them.
2. **The telegraphic passages cluster in §2** (the audit findings), where facts are packed into bullets with semicolons, and in four paragraphs of §5.9. Sections 5.1–5.7, 7.1 and 7.3 are mostly clear already.
3. **Repetition inside these files is modest.** Firm cuts are about 940 words of repetition (list B) and about 370 words of material that belongs elsewhere (list C), with about 335 more that are optional. That is 9% of the 15,135 words, or 11% with the optional cuts.
4. **The clarity fixes add words.** The rewrites in list A add roughly 800 to 1,000 words, almost all of them definitions and connectives. So these sections end at about the same length, or a few hundred words shorter. The shortening the owner wants has to come mainly from the sections outside this scope. One place is visible from here: six answers in Appendix G.1 repeat, nearly word for word, text that the body now carries (B14).
5. **Cross-references into §6 and §8 are unstable.** The section files for §6 and §8 currently carry duplicate and shifted numbers, so 27 pointers from the reviewed files need checking after the rewrite (A55). One sentence in Appendix D points to two phrases that no longer appear anywhere (A53).

---

## A. Telegraphic or unclear passages

### Terms used in more than one sense, or never defined

**A1. "Stage" means three different things, and this plan's own stages are used before they are defined.**

Where:
- The present kernel's internal phase: `02.3.md` line 30, "One Plan 8 probe solves at the default budget and fails at 1,000,000 with a larger Stage A budget"; `02.7.md` line 5, "Stage A residual lists"; `02.7.md` line 11, "against a default Stage A budget of 2,000".
- The stages of the earlier v2 plans: `02.9.md` lines 3, 5, 9 ("Its Stage 0", "The Stage 1 code", "the Stage 0 soundness fixes"); `09.0.md` lines 38 and 46; `AD.0.md` line 25.
- This plan's Stages A to D: `05.4.md` line 32 ("deferred to Stage D"); `05.9.md` lines 43 and 45; `07.1.md` line 17. They are defined only in §11.3.

A reader cannot tell whether "a default Stage A budget of 2,000" belongs to this plan's Stage A. The document never says what the kernel's own Stage A phase does.

Rewrites:

`02.3.md` line 30:
> **A larger budget can do worse than a smaller one.** One test problem from Plan 8 is solved at the default budget. It is not solved at a budget of 1,000,000 when the budget of one internal phase of the kernel's search is raised as well **[D]**. The kernel's code calls that phase "Stage A" [say in one clause what the phase does]. It is not Stage A of this plan (§11.3).

`02.7.md` line 11, last sentence:
> Its measured cost was the problem. One evaluation of the metric took 3,334 work units, and the default budget of the kernel's own "Stage A" phase is 2,000 **[D]**.

`05.4.md` line 32:
> The full version is a search across spaces in the sense of §5.9. It is deferred to Stage D, the last of the four stages in which this plan is to be built (§11.3).

In §2.9, §9 and Appendix D, write "Stage 0 of the v2 plans" and "Stage 1 of the v2 plans" at the first use in each section.

**A2. The budget table uses eight terms that are defined later or nowhere.**

Where: `02.3.md` lines 3–14 ("**Budgets.** A recursion-synthesis job runs at 5–7 million work units per second" through the table).

A reader cannot tell what a work unit, a spec, a schema, a whitelist, the "full grammar", "held-out-sound", a "bit bound" or "bounded exhaustion" is. "Schema" and "whitelist" are explained only in §2.5. "Recursion-synthesis job" and "flat search" are not explained anywhere.

Rewrite, to insert before line 3:
> Some terms first. A *spec* is one function that the bootstrap asks the kernel to synthesize, given as a few rows of inputs and outputs. A *work unit* is the kernel's own unit of search effort [say what one unit pays for; §7.1 suggests one VM instruction, or one cell]. A *schema* is a hand-written skeleton of a recursive program, supplied for one function. A *whitelist* is the list of operators that the author allows the search to use for one spec. The *full grammar* is every operator, with no whitelist. A solution is *held-out-sound* when it is also right on fresh inputs that were not among the spec's rows. An *impostor* is a program that fits the spec's rows and is wrong on fresh inputs. The *bit bound* is the largest program size, in bits of the kernel's code for programs, that enumeration is allowed to reach.

Table row 1, as sentences in the cells:
> | The 16 bootstrap specs, with the full grammar and no schemas, at 1, 10, 100 and 1000 times the default budget per spec | The number of specs with a held-out-sound solution was 8, then 10, then 10, then 10, of 16 |

Table row 4, right-hand cell:
> the search tried every program that its bounds allow and found no solution; that took 2.83 × 10⁹ work units, which is 8,085× the shipped budget [confirm: this is what "bounded exhaustion" means]

Still missing: one clause each on what a "recursion-synthesis job" and "flat search" are (line 3), and on "the depth and stage budgets" (line 13).

**A3. "Host" and "object language" carry the whole diagnosis and are never defined.**

Where: `02.2.md` line 5 (table headings "Available to a synthesized program | Host Lisp only") and line 21 ("terms are values of the object language"); then `03.0.md` line 13, `05.6.md` line 9, `07.1.md` line 21.

A reader who is not a Lisp programmer cannot tell which of two languages is meant, or why it matters where an operation lives.

Rewrite, to open §2.2 after its first sentence:
> Two languages are involved, and the difference between them matters throughout this document. The *object language* is the small language of the programs that the kernel synthesizes and that its VM runs. The *host* is Common Lisp, the language the kernel itself is written in. An operation that exists only in the host can be performed by the kernel's own code. It can never be performed by a program that the kernel finds.

**A4. "Decoder", "pullback" and "lift" are used from §2.1 onward and never defined. The same paragraph ends in a noun stack.**

Where: `02.1.md` line 5, "When a pullback or a lift produces a constraint that joins several unknowns ... a brute-force join capped at 4 candidate models per slot and 256 combinations". "Decoder" also appears undefined at `02.1.md` line 10, `02.2.md` line 10, `02.5.md` line 16, `02.7.md` line 11, `02.8.md` line 22, `05.6.md` line 5 and `09.0.md` line 37.

A reader cannot tell what a decoder is, what pullback does, or what "models per slot" are.

Rewrite of `02.1.md` line 5:
> This is the precise limit of the representation. Two operations run into it. *Pullback* takes a requirement on a whole program and turns it into a requirement on a part of the program that is still missing. It works by substitution. The outer part of the program that is already known, with the place of the missing part left open, is called a *decoder*, and pullback substitutes the decoder into the requirement (§5.6). *Lift* [one sentence; the code uses "lift" in four senses, see A16]. When a pullback or a lift produces a constraint that joins several unknowns, the kernel does one of two things. It weakens the constraint, which is sound. Or it returns the constraint beside the frame, in a list called `coupled`. A coupled constraint is solved afterwards by brute force. The kernel takes up to 4 candidate programs for each unknown and tries up to 256 combinations of them (`synthesize.lisp:636-642`) **[C]** [confirm: "4 candidate models per slot" means 4 candidate programs per unknown].

Still missing: what `pairs`, `anchors` and `edges` each record (`02.1.md` line 3). The sentence names them and says nothing about what they hold.

**A5. "Node" means a sub-problem of the search and also a node of a program, in the same list. The count of search nodes is given three ways.**

Where: `02.3.md` line 18, "**Structure.** The search tree has two or three nodes at every budget ..."; line 19, "one more AST node"; `04.1.md` line 5, "the search tree stayed at two nodes"; `03.0.md` line 9, "a two-node tree per job".

A reader cannot tell that "two or three nodes" and "one more node per tenfold" count different things. The sentence about the recursion skeleton has no stated link to the claim it supports. The third sentence from the end joins three clauses with commas.

Rewrite of `02.3.md` line 18 (the phrase "a root with one or two children" is the document's own, from Appendix G.1):
> **Structure.** The kernel searches a tree of sub-problems. The root is the spec, and a child is a smaller problem that some decomposition of its parent produced. (These are nodes of the search tree. They are not the nodes of a program's syntax tree, which the next point counts.) At every budget tried, this tree is a root with one or two children. The reason is that a sub-problem is expanded only once, by a fixed list of *proposal generators*: host functions that each suggest one way to decompose it. The main one is a skeleton for recursion. It recurses on `(tail Xi)`, leaves every other argument unchanged, and removes `at`, `tail`, `if` and `=` from the child's grammar (`decompose.lisp:341-382`). A second form, called lockstep, walks two sequences in step. A child is expanded further only when some generator proposes a decomposition for it, and for these children none does. So the tree cannot grow deeper. On the four stuck specs, raising `:max-depth` to 3 or 4 changed nothing. More work therefore buys longer expressions inside the same two or three sub-problems. It cannot buy more structure.

Then make `04.1.md` line 5 and `03.0.md` line 9 say the same thing: "a root with one or two children".

**A6. "Body bit" and "lane" are not defined.**

Where: `02.3.md` line 19, "**Exponent.** Work grows ×1.38–1.50 per body bit in every lane."

A reader cannot tell what a lane is (the word occurs nowhere else in the document), or how bits relate to nodes until the parenthesis.

Rewrite:
> **Exponent.** The kernel measures the size of a program in bits of its code for programs, and a *body bit* is one bit of a function's body. [Say what a "lane" is.] In every lane, the work needed grows by a factor of 1.38–1.50 for each further body bit. One node of a program's syntax tree, an AST node, is 6–7 bits. So **each tenfold increase in work buys about one more AST node**. The 1,000× budget advanced each lane by 18–23 bits. By extrapolation, an hour of search reaches bodies of 53–63 bits. The known solutions for the four stuck functions have 132–259 bits.

**A7. "Fold" means simplification of an expression in three places and the sequence primitive everywhere else.**

Where: `02.2.md` line 14, "one fold rule per constructor"; `09.0.md` line 34, "*Definedness-preserving folding* ... keep the two-contract discipline (equivalent, or merely necessary)"; `09.0.md` line 40, "fold soundness under both contracts".

A reader who has just met `fold` as one of six sequence primitives (§7.1) cannot tell that these three uses are something else, or what the two contracts are.

Rewrite of `09.0.md` line 34:
> *Simplification of requirements that preserves definedness* (`requirements.lisp:129-540`). The kernel simplifies a requirement expression by rules, with one set of rules per opcode. Its code calls this "folding". It is unrelated to the sequence primitive `fold` of §7.1. Each rule is held to one of two contracts: the simplified requirement is equivalent to the original, or it is merely necessary for it [confirm, and say what "definedness-preserving" adds]. Keep the two contracts and their tests. The rules themselves are per-opcode and will change.

In `02.2.md` line 14 write "one simplification rule per constructor". In `09.0.md` line 40 write "soundness of requirement simplification under both contracts".

**A8. "Witness" and "quotient" each change meaning between sections.**

Where: `05.9.md` line 7, "relating them means finding a witness"; `05.9.md` line 16, "a quotient and its small table".

"Witness" in `02.5.md` line 16 (and in §8.2) is the term that computes a solver's unknown. In §5.9 it is any object that shows two things are related, and the word is not defined there. "Quotient" in `05.4.md` line 14 is the act of merging rows or terms. In `05.9.md` line 16 it is a small term that maps a value to a label, a sense that is defined only in §6.2.

Rewrite of `05.9.md` line 7:
> **Across spaces, nearly everything has to be found.** Whenever two things are not already joined by a map, relating them means finding a *witness*: a concrete object, such as a map, a substitution or a pattern, that shows how the two are related. Checking a witness is cheap. Finding one is a search, and in the worst case a hard one.

In the table at line 16, first use: "a quotient (a small term that takes a value to one of a few labels, §6.2) and its small table". For `02.5.md` line 16 see A15.

**A9. "Probe space" is used without a definition, and "probe" has three other uses.**

Where: `05.5.md` line 13, "The same split suggests a check on the `foldl` problem **[P]**. If the programs that fit the task rows fall into different classes on a wider probe space, the task is underdetermined."

A reader cannot tell what a probe space is, or what "the same split" refers to ("split" also means a guard split). Elsewhere "probe" means a test problem (`02.3.md` line 30, "One Plan 8 probe"), an evaluation (`05.9.md` line 11, "probe evaluation"), and a hand-written recognizer (`AD.0.md` line 18, "Host probes").

Rewrite:
> The same distinction, between agreeing on the task's rows and agreeing on fresh rows, suggests a check for the `foldl` problem of §2.3, in which a program fits the spec's rows and is wrong **[P]**. A *probe space* is a space whose rows the kernel makes up for itself in order to test terms. Its rows do not come from a task. If the programs that fit the task's rows fall into different classes on a wider probe space, then the task's rows do not determine the answer, and the task is underdetermined.

### Section 2: the audit findings

**A10. A 260-bit answer is said to be found under a 130-bit bound, with no explanation.**

Where: `02.3.md` line 22, "The schema-assisted answer for `map-adjacent` is 260 bits under a root bound of 130, found in 109,012 work. Decomposition did that, not enumeration."

A reader cannot tell how an answer can be twice as long as the bound.

Rewrite:
> With its hand-written schema, the kernel does find `map-adjacent`, in 109,012 work units. The answer is 260 bits long, although enumeration at the root is bounded at 130 bits. [Say how: presumably the schema supplies the outer skeleton, and each part that is left to enumeration is under the bound.] So decomposition found that answer. Enumeration did not.

**A11. Five results in a row, three undefined terms, and one claim with no reason.**

Where: `02.3.md` line 26, "A behaviour pruner and a columnar evaluator already exist in `v2/enumerate.lisp` ..."

A reader cannot tell what the pruner and the evaluator do, what "closed arithmetic frames" are, what "covered the same horizon" means, or why "a five-element field flatters pruning".

Rewrite:
> A behaviour pruner and a columnar evaluator already exist in `v2/enumerate.lisp`. The pruner drops a candidate whose outputs on every row equal those of a candidate already kept. The columnar evaluator applies one operator to a whole column of rows at once. Both sit behind flags that no caller sets. Three auditors switched them on by hand **[M]**.
>
> | Test | Effect |
> |:--|:--|
> | The three finite-field benchmarks | Pruning alone cut work 6–79×. Pruning together with the column evaluator cut it 11–118×. The best model found was the same each time. |
> | Closed arithmetic frames [say what these are] | Pruning cut work 11–31×. |
> | A two-variable integer grammar, enumerated to 48 bits | The same size bound was reached in 1/470 of the work. |
> | `map-adjacent` | The same work reached 70 bits instead of 47. |
>
> The finite-field figures overstate the gain, because [give the reason that "a five-element field flatters pruning"]. With the pruner on, each tenfold increase in work buys about two AST nodes instead of one. That is still logarithmic.

**A12. "Class" is used for a category two sections before it becomes the plan's central term, and "reflection" is not defined.**

Where: `02.3.md` line 32, "**Policy is hard-coded in 158 places.** By class, with a decision that falls in two classes counted in both: 52 caps or prunes ..."

A reader cannot tell why the five numbers add to 169 until the subordinate clause is unpacked, or what "the concrete target for reflection" means.

Rewrite:
> **Search policy is hard-coded in 158 places.** The search-engine report (§4) sorts these decisions into five categories **[C]**: 52 are caps or prunes, 51 are pieces of domain knowledge, 30 are guards against repeating work (dedupe or memo guards), 30 are ordering rules, and 6 are accounting rules. The five figures add up to more than 158 because a decision that belongs to two categories is counted in both. This list is the concrete target for reflection, by which this plan means the kernel reading the record of its own searches and making such decisions itself (§7.4).

**A13. Where the time goes: four pieces of implementation jargon.**

Where: `02.3.md` line 28, "The rest is the one-unit scheduling loop, ledger charging, expression construction, and metadata lookups in a weak hash table. In flat exact search evaluation is about half **[M]**."

Rewrite:
> **Evaluation is not where the time goes.** In a synthesis job, evaluating candidates takes about 3% of the time. The rest goes to bookkeeping: the scheduling loop, which advances the search one work unit at a time; charging each unit to the ledger; constructing expressions; and looking up metadata in a hash table. In flat exact search [define], evaluation is about half of the time **[M]**.

**A14. The finding about the library and lifting cannot be understood as written, and three other places rely on it.**

Where: `02.5.md` line 24, "**The library compounds when it is used for lifting, on some tasks.** On 8 held-out tasks, lifting through library entries solved 3 in 25,000–42,000 work that the kernel alone misses at 35 million ..."

A reader cannot tell what was done differently in the two arms. "Used for lifting" and "offered as plain operators" are not explained, and the count "three or four" is unexplained. The Summary, §7.6 and §11.1 all lean on this result.

Rewrite:
> **On some tasks the library makes later problems cheaper, but only when it is used for lifting.** [One sentence is needed here on what "used for lifting" means in this experiment, as distinct from offering a library function as one more operator.] The test was 8 held-out tasks **[M]**. With lifting through library entries, 3 of them were solved in 25,000–42,000 work units. The kernel alone does not solve those 3 in 35 million. One more task became 3.2× cheaper. Three or four others became 1.7–3× more expensive [say why the count is not exact]. The other way to use the library is to offer its functions as plain operators, which is what the bootstrap does. That never helped. In a separate experiment with stand-in functions it made search 6.6× more expensive.

**A15. Four undefined terms in one bullet, and five different denominators in one section.**

Where: `02.5.md` line 16, "The eight generic-search entries are the arithmetic solver witnesses, three atoms each. Across all 19 synthesis jobs, 19% of answer bits were found at a leaf; the rest is decoder skeleton supplied by a proposal generator."

A reader cannot tell what a witness, an atom, "found at a leaf" or a "decoder skeleton" is. The section also counts 61 entries, 19 synthesis jobs, 10 function specs and "the same 21 entries" (line 19, where "the same" has nothing to refer to), next to the 16 specs of §2.3.

Rewrite of line 16:
> The eight entries found by generic search are all small. Each is the *witness* of an arithmetic solver, that is, the expression that computes the unknown argument. Each has three atoms [confirm: an atom is one operator or one leaf]. Across all 19 synthesis jobs of the build, 19% of the bits of the answers were found by enumeration at a leaf of the search tree. The rest is decoder skeleton (§2.1), which a proposal generator supplied. The largest expression that enumeration produced anywhere has 8 atoms.

Still missing: one sentence relating 61 entries, 19 jobs, 16 specs, 10 function specs and 21 hand-written entries. For line 19, say "defined 21 of these entries".

**A16. Two counts with nothing counted.**

Where: `02.2.md` line 23, "\"Lift\" names four different things, and \"fiber\" three."

A reader cannot tell which four and which three. The table above has four rows that begin "Lift", which may be the four.

Rewrite:
> The code also uses one word for several things. "Lift" names four different operations [list them; if they are the four "Lift" rows of the table, say so]. "Fiber" names three [list them].

In the same paragraph, "compose the child's model back" needs "model" glossed as "candidate program".

**A17. "Terms are not shared" is written in Lisp shorthand.**

Where: `02.1.md` line 9, "They are plain conses; identity is structural equality; every snapshot copies the tree and discards cached metadata and compiled closures **[C]**."

Rewrite:
> **Terms are not shared.** Each expression is an ordinary Lisp list. Two occurrences of the same expression are therefore two separate objects, and the only way to see that they are the same is to compare them piece by piece. Every snapshot [say of what, and when one is taken] copies the whole tree. The copy loses the cached metadata and the compiled closures that were attached to the original **[C]**.

**A18. The sentence about `lift-frame` cannot be parsed without the code.**

Where: `02.1.md` line 10, "The nearest thing is `lift-frame`, which unfolds a decoder symbolically until the unknown's call sites appear, builds what is in effect an execution graph inside requirement expressions, and discards it".

Rewrite:
> **Nothing records an execution.** When an expression is evaluated, no note is kept of which operator consumed which value. The nearest thing is the host function `lift-frame` (`frame.lisp:1214-1256`) **[C]**. It expands a decoder step by step, without running it, until it reaches the places where the unknown function is called. In doing so it builds what is in effect an execution graph, written inside requirement expressions. It then discards that graph.

**A19. Two geometry bullets that only a reader of the code can follow.**

Where: `02.7.md` line 8, "Node scores add program bits sized at the root to residual bits sized in the child's own space. Ambient and induced pricing are already mixed **[C]**."; line 10, "The work tariff is quadratic where the host is not"; line 7, "it survives a pullback in only four cases".

A reader cannot tell what "sized at the root" means, what ambient and induced pricing are, what the host "is not", or what it means for a metric to "survive".

Rewrite of line 8 ("original or ambient" is the owner's own phrase, quoted in Appendix A):
> A search node's score is the sum of two numbers that are measured in different places. The bits of the program are measured at the root problem. The bits of the residual are measured in the child problem's own space. So pricing in the original, or ambient, space and pricing in a derived, or induced, space are already mixed in one score **[C]**.

Rewrite of line 10:
> The kernel's price list for work charges quadratic cost for operations that are not quadratic in the host. A recursive sum over a list of n elements is charged about 7.5·n² work units. Two `at` reads on a list of 10,000 elements are charged 430,941 work units **[M]**.

Rewrite of line 7:
> A frame can carry a metric of its own, which is an expression over two values. By its own documentation that metric cannot depend on the row. When the frame is pulled back, the metric can be carried over to the new frame in only four cases (`frame.lisp:508-518`) **[C]** [name the four, or say what they have in common].

Line 5 also needs a definition at first use: "A *residual* is what is left of a target after a model has accounted for part of it." The eight names in its parenthesis are internal names; either gloss each or give only the count and point to the report.

**A20. The paragraph on what surrounds law discovery assumes "the four jobs" are known.**

Where: `02.4.md` line 5, "Everything around it is supplied by `bootstrap/build-batteries.lisp` ... The four jobs propose 187 equations, all exhaustively true on GF(3); 14 pass the filter **[M]**."

Rewrite:
> Everything around that core is supplied by the bootstrap script, `bootstrap/build-batteries.lisp`. The script defines four discovery jobs. For each job it fixes the finite field, the number of variables, the list of operators, the bounds, and the budget (20,000–80,000 work units). A host function, `law-operator-fact` (`consolidate.lisp:709-735`), then filters what the jobs find. It keeps an equation only if it has one of three shapes: commutativity, associativity, or identity. Together the four jobs propose 187 equations. All 187 are true on every input in GF(3), the field of the integers modulo 3. Only 14 pass the filter **[M]**.

**A21. A bare string of numbers.**

Where: `02.4.md` line 9, "One finite-field fixture: 182,000 work plain; 741,000 with one law; 70.2 million with 80 laws; identical results **[M]**."

Rewrite:
> **Where laws are wired into search, they cost more than they save.** On one finite-field test problem, the search took 182,000 work units with no laws, 741,000 with one law switched on, and 70.2 million with 80 laws. The results were identical in all three runs **[M]**.

**A22. "The 14 knowledge kinds" arrive as if already introduced.**

Where: `02.4.md` line 10, "**The 14 knowledge kinds are one struct with role tags.** A `:solver` is a law plus a chosen unknown port; the code builds that law to validate the solver. Six kinds have no instance in the library. About 30 edge types are written and about 10 are ever read **[C]**."

A reader cannot tell what the kinds are, what an "unknown port" is, or what the edges connect.

Rewrite:
> **The library's 14 kinds of entry are one record with different labels.** The knowledge library files each entry under one of 14 kinds, such as law or `:solver`. In the code all 14 are the same structure, and the kind is only a tag on it. A `:solver`, for example, is a law together with a choice of which of the law's variables is the unknown. The code builds that law in order to validate the solver. Six of the 14 kinds have no entry in the library. Entries are linked by typed edges [say what an edge connects]. About 30 types of edge are written, and only about 10 are ever read **[C]**.

**A23. Four arrows, two of them between terms that are defined nowhere.**

Where: `02.4.md` line 11, "law → operator fact (3 shapes), law → solver (1 shape), law star → fold motif, element solver → sequence solver **[C]**."

Rewrite, as far as the document allows:
> **Every step that turns a discovered law into something the search can use is a hand-written recognizer of particular shapes.** There are four such steps **[C]**. A law becomes an operator fact (commutativity, associativity, or identity) only if it has one of 3 shapes. A law becomes a solver only if it has 1 shape. [The other two steps are written "law star → fold motif" and "element solver → sequence solver". Say what a "law star" and a "fold motif" are, and what each step does.]

**A24. Two qualifications on `:foldr` that use three undefined terms.**

Where: `02.5.md` line 23, "Two qualifications: `:foldr`'s measured gain is zero bits after naming, and it is not accepted when each signature has only two seed functions; and both names are supplied by the script."

"Signature" here seems to mean a type signature. Elsewhere it means a set of properties (§1.3, §8.6) and a refinement colour (`05.9.md` line 28).

Rewrite:
> Two qualifications apply. First, `:foldr` saves nothing. Once the cost of giving it a name is paid, its measured gain in description length is zero bits. It is also not accepted when [say what a "signature" and a "seed function" are here, then: each signature has only two seed functions]. Second, the kernel finds the two patterns and does not name them. The names `:map` and `:foldr` are supplied by the script.

**A25. Section 2.6 never says what reflection or a message is.**

Where: `02.6.md` line 3, "`messages.lisp` (128 lines) turns a job's messages into an ordinary frame."; line 7, "the nogood/feature group saves 2,332 work on `add-len`".

A reader cannot tell what a message records, what a nogood is, or what 2,332 work units is a saving out of.

Rewrite of line 3:
> *Reflection* means the kernel reading the record of its own search and acting on it. The plumbing for it exists. During a job the search emits *messages* [say what a message records], and `messages.lisp` (128 lines) turns a job's messages into an ordinary frame. But nothing reads that frame except a test and an offline experiment **[C]**. Within a job, no decision reads the messages or the trace.

Rewrite of line 7:
> An ablation shows what a search trace is good for **[M]**. `plan_v2b.md` treated the things learned from a trace as useless. That is not quite right. One group of them, the nogoods [define] and the features learned with them, saves 2,332 work units on the task `add-len` [out of how many]. But it does so only when the same task is run again. Nothing learned from a trace helped on a different task. What does carry over to other tasks is the abstracted functions.

**A26. The first recurring problem is stated in four fragments.**

Where: `02.8.md` line 9, "*What goes with what* is always handed in. Four plans used four mechanisms. Connectivity never became a stored object. The derivation graph moved from the frame, to store entries, off the frame, and back as `pairs`/`anchors`/`edges`."

Rewrite:
> *What goes with what is always supplied from outside.* In every plan, the author told the kernel which rows, values and sub-problems belong together. The kernel never found that for itself and never stored it. Four plans used four different mechanisms for it. The record of which sub-problem came from which shows the drift. It was kept first on the frame, then in store entries, then off the frame, and then on the frame again as `pairs`, `anchors` and `edges`.

**A27. A bold claim with nothing under it.**

Where: `02.8.md` line 14, "**Graph machinery was declined four times, on minimalism, never on a measurement.**"

This is the whole paragraph, and it is word for word the sentence in §1.1 item 6. A reader cannot tell which four occasions, who declined, or what was proposed. The body should carry the evidence that the Summary points to.

Rewrite, with the gap marked:
> **Graph machinery was proposed and declined four times.** [List the four: the plan, the date, and what was proposed.] Each time the reason given was minimalism. No measurement was cited.

**A28. Five nuggets that are labels rather than statements.**

Where: `02.8.md` lines 18, 19, 21, 24, 28.

Line 18, the counting identity. A reader gets a formula and two noun phrases.
> *The counting identity* (plan 2): H(X) = H(f(X)) + E log|fiber|. In words: the information in an input X equals the information in the output f(X), plus the average number of bits needed to say which of the inputs with that output was the actual one. The set of inputs that give one output is its *fiber*. So every step of a computation destroys a definite number of bits, and running the step backwards means supplying them. Plan 2 put it this way: "Running a computation backwards is lifting: given f(x), supply the index."

Line 19, one residual definition. "D" is never introduced, and the three cases are a bare list.
> *One definition of a residual covers three cases* (plan 2). The residual is a fiber index when the model is exact and many-to-one. It is a guard or mask when the model holds only on some rows. It is a metric error when the model is only approximately right [confirm this reading of the three cases]. Plan 2 noted that the approximate case "needs an order or a metric on D" [say what D is]. This is the point at which pricing needs geometry as well as topology.

Line 21, fiber versus section. "A solver is two laws" does not say which two.
> *Fiber versus section* (plan 7). A pullback keeps the whole fiber, that is, every value of the unknown that would satisfy the requirement. An inversion chooses one member of the fiber for each row, and that choice is called a section. A uniqueness law certifies that the fiber has only one member, so that there was no choice to make. A solver is therefore two laws [name the two; Appendix B suggests a witness law and a uniqueness law].

Line 24, laws and compression. No reason is given for "invisible to compression".
> *Compression does not reveal laws, and shared-input experiments reveal them at once* (plan 2). [Say why compression does not reveal a law.] If both argument orders of an operator are run on the same inputs, commutativity appears at once. This was a result from a scratch script, and it was never reproduced in the kernel.

Line 28, explanation-based generalization. "Variabilize" is jargon, and three clauses are joined by semicolons with no verbs.
> *Explanation-based generalization* (plans 1–3). After a derivation succeeds, find the parts of the problem that the derivation never depended on, and replace them by variables. This is a dependency analysis on the search's own record. Of the reflective operations in the trail it is the one specified most completely. It was never built.

**A29. The verdict on the earlier plans is written in the vocabulary of an earlier audit.**

Where: `02.9.md` lines 3 and 5, "`plan_v2b.md` is reliable where checked: about 35 code claims, three errors. Its Stage 0 ... has no imported risk ... its headline numbers have no artifact behind them." and "Complexity rose. The Stage 0 survival audit gives the identical result on all 64 runs."; line 17, "Both plans share four gaps".

A reader cannot tell what "imported risk", "unverified novelties" or "no artifact" mean, by what measure complexity rose, what follows from 64 identical runs, or which two of the three documents just named are "both plans".

Rewrite of lines 3 and 5:
> `plan_v2b.md` proved reliable where it was checked. Of about 35 claims that it makes about the code, three were wrong. Its Stage 0 (index columns, one behaviour table, attribution by ablation) depends on nothing taken from the literature without verification. `plan_v2.md` is different. Its critical path contains six mechanisms imported from academic papers and ten inventions of its own that were never verified. `plan_v2.tex` went from version 2.1 to version 2.4 in four hours, and each revision found fatal flaws in the one before. Its gates depend on 40 mechanisms, and 21 of the 40 are academic imports or the plan's own inventions. No script or log stands behind its headline numbers.
>
> The Stage 1 code in `v2/` added 1,393 lines and no tests. Its main new opcode, `:tabulate`, fails when an expression is constructed in the form that its own proposals build (`v2/ast.lisp:1096` against `:673`). Ten exported symbols are defined nowhere. Complexity rose [by what measure]. The Stage 0 survival audit gives the identical result on all 64 runs [say what follows from that].

Line 17: name the two plans.

**A30. The list of what to keep from v2 uses different names from §9 for what may be the same things.**

Where: `02.9.md` line 13, "totality facts for variable indices, guards derived from an operator's own preconditions, and the replay guard for inverses (§7.2)"; line 14, "no symmetry refund, each root row priced once"; `09.0.md` line 38, "the definedness guard derived from an operator's preconditions, difference facts for variable indices, and the index-preimage rules for `gather` and `evolve`".

A reader cannot tell whether "totality facts for variable indices" and "difference facts for variable indices" are one thing or two. "Symmetry refund" is explained only in Appendix D, `evolve` nowhere, and `gather` only in §7.1.

Rewrite of `02.9.md` line 14:
> the pricing discipline: no bits are refunded for symmetry (Appendix D), and each row of the root problem is priced exactly once;

For line 11, add after `gather`: "(`(gather C Z)` returns the elements of `C` at the positions listed in `Z`)". For line 13 and `09.0.md` line 38, choose one name and say in a clause what the fact is. The list itself should live in one place (B3).

### Section 4: the six perspectives

**A31. A model is said to "agree" with a figure it cannot be compared with.**

Where: `04.1.md` line 5, "Going from one second to ten hours is 4.5 decades, so five to nine nodes. A model fitted by the search-literature auditor to four published enumerators agrees to within a node or two ... about 17 nodes over 10 primitives (range 13–22), 10 over 30 (8–13), and 7 over 100 (6–8)".

"Five to nine nodes" is a gain. The model's figures are total sizes reached in one hour. A reader cannot tell what agrees with what. "17 nodes over 10 primitives" drops its verb.

Rewrite:
> Going from one second to ten hours is 4.5 tenfold steps, so it adds between five and nine nodes to the largest program reached. The search-literature auditor fitted a model to four published enumerators, and it agrees with that to within a node or two [say which two figures are compared: the figures below are sizes reached in an hour, and "five to nine" is a gain]. The model is an estimate, not a published figure, and it assumes 10⁶ evaluations per second. It says that one hour of bottom-up enumeration with deduplication reaches programs of about 17 nodes when the grammar has 10 primitives (range 13–22), about 10 nodes with 30 primitives (8–13), and about 7 nodes with 100 primitives (6–8) **[L, estimate]**.

**A32. The "Take" is three imperatives with a metaphor.**

Where: `04.1.md` line 9, "Design every record for 10¹⁰–10¹¹ work units. Make budget buy structure, not only leaves: resumable proposal generation, re-openable nodes, and many small searches instead of one deep one."

A reader cannot tell what "every record" is, or what it means for budget to "buy structure".

Rewrite:
> *Take.* Design for runs of 10¹⁰–10¹¹ work units [say what "every record" refers to]. Arrange the search so that more budget can add sub-problems to the tree, and not only longer expressions at its leaves. That needs three things: proposal generation that can be resumed, sub-problems that can be re-opened, and many small searches in place of one deep one. Treat the choice of a small grammar for each problem as the main control problem (§6.4).

**A33. Three unrelated literature results in one sentence.**

Where: `04.5.md` line 5, "A tree embeds exactly in squared-Euclidean space, at one dimension per edge: give each edge its own axis, ...; language models encode hierarchy as orthogonal subspaces; shown a graph in context, a transformer reorganizes its representation toward that graph's spectral embedding **[L]**."

Rewrite:
> *Evidence.* Nesting is not a problem of what a flat space can represent. Three results show it **[L]**. First, a tree can be embedded exactly in a flat space. Give each edge its own axis, and the squared Euclidean distance between two nodes is then the length of the path between them. This takes one dimension per edge. Second, language models encode hierarchy as orthogonal subspaces. Third, a transformer that is shown a graph in its context reorganizes its representation toward that graph's spectral embedding.

In the next sentences, define *superposition* at first use ("many features sharing the same neurons"). The bound on computation is then stated twice, once as Ω(√(m log m)) neurons and once as "n neurons compute at most about n² features"; one statement is enough (B11).

**A34. "Both halves of your note" refers to a note that is not quoted.**

Where: `04.5.md` line 7, "The paper you cited in the margin, arXiv 2611.17309, bears on this ... one hand-set value already solves every Sudoku puzzle, and three every maze ... So both halves of your note hold ... an exact store with cheap evaluation and scheduled lowering."

A reader cannot tell what the two halves are, what the "value" is a value of, or what "scheduled lowering" is.

Rewrite:
> The paper you cited in the margin, arXiv 2611.17309, bears on this. [Quote the note, so that "both halves" has something to refer to.] The paper's model is a small energy function over pairs of cells. It can represent the rules of the puzzle exactly, and so fitting it takes milliseconds. [The original says "one hand-set value already solves every Sudoku puzzle, and three every maze". Say what the value is a value of.] The solving is where the work is done. It is a search by a very large number of very cheap moves. Each move updates a single cell and touches only the cells coupled to it. The moves run as Triton kernels on a GPU, at a mean of 2.0 × 10⁹ FLOPs per Sudoku. So both halves of your note hold, and the second is the one that matters here: the bits of the answer come from fast evaluation, not from the model. That argues for an exact store with cheap evaluation, and for compiling the parts that run most often into faster code [confirm: this is what "scheduled lowering" means]. It does not argue for a learned embedding. The authors add that these benchmarks are too easy, and that learning latent quantities "remains an important open research direction".

Most of this paragraph also appears in Appendix G.1 and could be shortened here (C2).

**A35. "Its authors" has no antecedent, and the sentence on reentrancy assumes three terms.**

Where: `04.6.md` line 5, "Running a general interpreter backwards does not scale; its authors say interpretive overhead ... until staged away"; line 7, "Reentrancy can be given its meaning by nested interpreters, but it should not be executed as a tower of them: collapse the tower first, by staging or lowering, or use one evaluator whose terms can mention terms, spaces, and requirements (§7.1)."

The owner asked "who is this from?" of another quotation (Appendix G.1), so attribution matters to this reader.

Rewrite of the sentences in line 5:
> Running a general interpreter backwards does not scale. The authors of the relational interpreters that do this [name the system] say that interpretive overhead "makes the relational interpreter approach impractical for most applications". Each extra level of interpretation costs a factor of 6–178, until that level is compiled away **[L]**.

Rewrite of the last sentence of line 7:
> Reentrancy is your "freely shifting abstraction level": the kernel applying its own search to its own programs and records. One way to say what that means is a stack of interpreters, each interpreting the one above it. That is acceptable as a definition. It should not be how the kernel runs, because every level multiplies the cost. There are two ways out. The stack can be collapsed into one program before it runs, by compiling the upper levels away, which is called staging or lowering. Or there can be a single evaluator whose terms are allowed to mention terms, spaces and requirements (§7.1).

**A36. The comparison table has no key, and its heading does not describe it.**

Where: `04.7.md` lines 1–12, "### 4.7 What the perspectives agree on" and the table.

A reader cannot tell what bold marks, what "research (2026)", "soft", "weak" and "—" mean, or that the "Budget only" column describes the present kernel. The table shows what each perspective covers. It does not show agreement.

Rewrite of the heading and a caption to put above the table:
> ### 4.7 What each perspective covers
>
> Each cell says how that perspective would supply the operation named at the left. "Host only" means that the operation would stay in host Lisp, as it is in the present kernel. Bold marks [say what bold marks; it appears to mark the cells where the operation is native to the perspective]. "Research" means that only unreplicated research systems do it [confirm, and say what "(2026)" adds].

### Section 5: the proposal

**A37. The dependency test is described in §5.3 and named only elsewhere. `tabulate` is used before it is defined.**

Where: `05.3.md` line 14, "One could have known an inverse existed before searching for it: any two rows that agree on `a` and on the sum also agree on `b`. That test is a group-by."; line 26, "The program is `(tabulate ...`".

§4.6, §5.8, §5.9, §6.1, §6.2 and four sections of §7 all say "dependency test", and §6.1 says "the dependency test of §5.3". The words do not appear in §5.3.

Rewrite of line 14:
> - One could have known that an inverse existed before searching for it. Any two rows that agree on `a` and on the sum also agree on `b`, so `b` is a function of `a` and the sum. Checking that takes one group-by. This plan calls the check the *dependency test*.

Line 26, before the program: "`tabulate` builds a sequence from a length and a function of position (§7.1)." The phrase "The term that is also right for an empty list" implies a simpler term that is wrong for an empty list; name it.

**A38. Four small gaps in §5.4.**

Where and rewrite:
- `05.4.md` line 5, the "Cost" column uses "n" without saying what it is. Add under the two definitions at line 3: "In the Cost column, n is the number of rows of the space."
- Line 11, the program forms "`tabulate`, `select`, `scan`, `fold`". `select` is not one of the six primitives of §7.1, which has `where`. Use one name, or define `select`.
- Line 24, "You said of the earlier six-move list that several were \"flavors of the same\"." A reader cannot tell which list in which plan. Rewrite: "The [name the plan] listed six moves, and you said of that list that several were "flavors of the same"."
- Line 34, "**Depth-two experiments are spaces whose cells hold terms.**" The term is the owner's, and the document never says what depth two is. Add as the first sentence: "A depth-one experiment runs operators on values. A depth-two experiment has functions among its inputs, so its laws are about compositions of functions [confirm against your own use of "depth"]."

**A39. The "Tested" grade ends in a compressed phrase and a forward reference to an undefined term.**

Where: `05.5.md` line 8, "Good for anything where a mistake costs time or a missed answer, never truth: ordering enumeration, normalizing before anti-unification, proposing a decomposition. The verb tables of §6.4 are of this grade."

Rewrite:
> - **Tested**: the two terms also have the same column on several fresh spaces that include boundary values. A tested class may be used wherever a mistake would cost only time or a missed answer. It may never be used where a mistake would make the kernel accept something false. Its uses are ordering the enumeration, normalizing terms before anti-unification, and proposing a decomposition. The tables of what each operator does to coarse labels of its inputs, which §6.2 calls verb tables, are knowledge of this grade (§6.4).

**A40. "The same review" could be either of two reviews, and an experiment code appears before the experiments.**

Where: `05.8.md` line 5, "The same review names what separates this plan from the earlier v2 plans."; line 7, "This plan leans on classes for pruning and keeps laws by use (§8.8) ... and X1 should measure what the choice costs."

The paragraph before mentions the outside review and then the search-literature review. X1 is defined only in §11.2; X9 is used the same way at `05.9.md` lines 41 and 45.

Rewrite of line 5, first sentence:
> The outside review also names what separates this plan from the earlier v2 plans [confirm that the outside review is meant].

Rewrite of line 7:
> This plan differs from the published recipe in one respect that matters. The decisive step of the published recipe is pruning the term space with laws already found, and dedupe by behaviour comes second. This plan relies on classes for pruning, and it keeps a law only when something reads it (§8.8). The reason is the kernel's own measurement that rewriting during search cost more than it saved (§2.4). What the choice costs is not yet known. Experiment X1 (§11.2), which runs law discovery on the new store, should measure it.

At `05.9.md` line 41 write "(experiment X9, §11.2)".

**A41. Three quotations placed side by side with no verbs between them.**

Where: `05.9.md` line 35, "The matching problem is \"structure & type-aware & locality-seeded\". \"This is NP-hard, think, and yet some of the search can be amortized\", \"Hypothetically through the development of a vocabulary / short descriptive language\"."

Rewrite:
> **3. The expensive choice is which pairs to try, and that is the job of the cheap geometry.** With n problems there are n² pairs to relate and 2ⁿ subsets to generalize over. Your October outline, which still stands in `prompt4.md` (L170–175), said this in advance. It describes the matching problem as "structure & type-aware & locality-seeded". It goes on: "This is NP-hard, think, and yet some of the search can be amortized". And it suggests how: "Hypothetically through the development of a vocabulary / short descriptive language". Plan 7 proposed to seed anti-unification in the same way, using graph distance between library entries to choose the pairs, and never built it.

**A42. "Two resolutions" introduce a list of four signals, and "They differ" does not say what differs.**

Where: `05.9.md` line 37, "On the store the seeding signals are the two resolutions of §6.2, pointed across spaces: agreement between the labels ...; the cost of one column given another; the colour histograms of two spaces; and counts of which pairings paid off before. They differ in one useful way."

A reader cannot map four signals onto two resolutions. The contrast that follows is between a signal that disagrees and a signal that agrees. It is not a contrast among the four.

Rewrite:
> On the store, four cheap signals can say which pairs are worth trying. The first is agreement between the labels of two problems' columns (labels are defined in §6.2). The second is the cost of one column given another (§6.1). The third is the colour histograms of two spaces, from the refinement above. The fourth is a count of which pairings paid off before. [The original calls these "the two resolutions of §6.2, pointed across spaces". Say which signal belongs to which resolution, or drop the phrase.] A signal can be used in two ways, and the two are not equally strong. An invariant that differs between two spaces *refutes* a correspondence outright, in polynomial time. Agreement only *suggests* one. So the cheap layer rules pairs out with certainty and proposes pairs without it, and the exact search runs only on the pairs that survive.

**A43. The paragraph that reinterprets the prototype's aligner is one long conditional.**

Where: `05.9.md` line 33, "One piece of the prototype was already a cross-space search ... The candidates for that map are the index sets that the `gather` rule yields; the choice among them is made by a term when one fits (a shift), by a constraint when one applies (the indices increase), and otherwise it is paid for at log₂|fiber| bits per row."

"Selective function" is defined only in §7.3, and "the `gather` rule" only in §2.9.

Rewrite:
> One piece of the prototype was already a search across spaces, and it should be read as one. A *selective* function, such as `filter`, keeps some elements of its input and drops the rest. To lift it, each position of the output has to be mapped to the position of the input that its element came from (§7.2). For each output position, the candidates are the input positions that hold the wanted value. These are the index sets of the `gather` rule (§2.9). One candidate has to be chosen for each position, and there are three ways to choose. If a term fits, the term makes the choice; a shift is an example. If a constraint applies, the constraint makes the choice; here the constraint is that the indices increase. Otherwise the choice is paid for, at log₂|fiber| bits per row. The subsequence aligner in the prototype is the second of these ways, written by hand.

**A44. The cost paragraph of §5.9 has no main verbs.**

Where: `05.9.md` line 43, "**What allowing this costs.** Refinement and backtracking: 36 and 65 lines in the version measured. Tree-pattern matching, which is joins. Anti-unification over classes ... Choosing what to abstract, for which the kernel's description-length-gated abstraction imports (§9)."

"Imports" as an intransitive verb, meaning "can be carried over from the present kernel", also appears at `07.3.md` line 11 and in §7.2 and §7.4.

Rewrite:
> **What allowing this costs.** Four pieces of machinery are needed. The first is refinement and backtracking, which were 36 and 65 lines in the version measured. The second is matching of tree-shaped patterns, which is a sequence of joins. The third is anti-unification over classes instead of over single representatives. That is a product of two automata and quadratic in the corpus (§5.4), and it is deferred to Stage D. The fourth is a way to choose what to abstract. The kernel's existing abstraction code, which accepts an abstraction only when it shortens the total description, can be carried over for that (§9).

**A45. The stages paragraph assumes the stages, "context selection", and "what to mix".**

Where: `05.9.md` line 45, "**Where it enters the stages.** Stage A is entirely within spaces ... Stage C is the first place where the choice of what to mix decides the outcome, as context selection ..."

Rewrite:
> **Where it enters the stages.** The plan is to be built in four stages, A to D (§11.3). Stage A, the store core, works entirely within spaces. Stage B adds requirements with holes and spaces with maps. It crosses between spaces only along maps that it builds itself, except for the selection case above. Stage C is the first stage in which the outcome depends on a choice of what to bring together. There the kernel has to select which library entries go into each problem's grammar. The quotients and tables of §6.4 are first used in Stage C, and analogies between operator tables are found there as terms (experiment X9, §11.2). Stage D works across spaces throughout: it abstracts over solutions, and it looks for depth-two laws.

Two smaller points in §5.9. The heading "**The compromise.**" (line 41) does not say what is traded for what; "How the two kinds of work are budgeted" describes the paragraph. The phrases "graph walker" (line 28) and "graph isomorphism engine" (line 29) are in quotation marks with no source; say whose words they are.

### Sections 7.1, 7.3 and 9

**A46. The opening of §7.1 lists four properties as noun phrases.**

Where: `07.1.md` line 3, "The metered VM is the cleanest part of the kernel and stays in design: prepaid instructions, exact resumption after a cutoff, exact ledgers, and results that are identical however the run is sliced."

Rewrite:
> The metered VM is the cleanest part of the kernel. Its design is kept, and its code is re-derived for the new opcodes (§9). Four properties make up that design. Every instruction is paid for from a work budget before it runs. A run that is cut off when its budget is spent can be resumed exactly where it stopped. The ledgers of work spent are exact. And the results are identical however a run is cut into slices. The rule that every finished program is verified at the root, on every row, is kept as well.

**A47. Only two of the six primitives are glossed, and the heading is type-theory jargon.**

Where: `07.1.md` line 13, "**3. Give sequences their introduction and elimination forms.** Six primitives: `length`, `at`, `tabulate` (build a sequence from a length and a function of position), `fold`, `scan`, and `where` (the positions satisfying a predicate)."

Rewrite:
> **3. Give sequences primitives that build them and primitives that take them apart.** There are six. `length` gives the number of elements. `at` reads the element at a position. `tabulate` builds a sequence from a length and a function of position. `fold` reduces a sequence to one value, by applying a step function to each element in turn and carrying an accumulator. `scan` does the same and returns every intermediate value of the accumulator, as a sequence. `where` returns the positions that satisfy a predicate. Sequences become arrays, so `at` costs one work unit instead of a cost that grows linearly with the index.

**A48. The evidence sentence reads as if one system produced both figures.**

Where: `07.1.md` line 19, "The evidence for granting this much: with such combinators and deduction through them, one published synthesizer has a median of 0.43 s on its benchmark suite; without them, rediscovering `fold` from a fixed-point combinator took about 7,700 CPU-hours **[L]**."

Appendix E shows these are two different systems. The same figure is "roughly five days on 64 CPUs" at `04.1.md` line 5 and "about a year of CPU time" in §10, and a reader cannot tell that the three are one measurement.

Rewrite:
> Two published results are the evidence for granting this much **[L]**. One synthesizer that is given such combinators, and that splits requirements through them, has a median time of 0.43 s on its benchmark suite. A different system was not given them. It had to rediscover `fold` from a fixed-point combinator, and that took about 7,700 CPU-hours.

At `04.1.md` line 5 add the common unit: "roughly five days on 64 CPUs, which is about 7,700 CPU-hours".

**A49. Three unclear phrases in the recursion cases, and a closing paragraph in which "tested" hides the outcomes.**

Where: `07.3.md` line 3, "each of which is the same act with a different hand-chosen argument tuple (§2.3)"; line 6, "with the keep-column recovered by aligning output to input"; line 11, "Candidates are ranked by how many rows land on a known row and by whether some measure decreases; the kernel's termination check (about 50 portable lines) imports for the second."; line 13, the last paragraph.

A reader of line 13 can take "tested" to mean "passed". §8.5 says that `foldl` returns an impostor and that `best-shift` and `argmax-corr` are unsolved. "By inspection, cases 1–4 are the shapes of the functions in the current library" does not say whether every function is covered. §2.3, which line 3 cites, does not mention five schemas.

Rewrite of line 3:
> The audit found that the kernel has one main template for recursion, with a lockstep variant that walks two sequences in step (§2.3). There are also five hand-written schemas. Each schema does what the template does, and differs only in the tuple of arguments that its author chose to recurse on [confirm this reading of "the same act with a different hand-chosen argument tuple"]. On this store the cases separate, and most stop being recursion.

Rewrite of line 6:
> 2. **Selective functions** (`filter`, positions of a value). The program is a `where` over the positions of the input. What has to be found is the *keep-column*: the Boolean column that says, for each input position, whether its element survives. It is recovered by aligning the output to the input.

Rewrite of the last two sentences of line 11:
> Candidates for that argument are ranked by two tests. The first is how many calls they send to a row that is already in the call space [confirm this reading of "land on a known row"]. The second is whether some measure decreases from each call to the next. The kernel's termination check, about 50 lines that can be carried over, supplies the second test.

Rewrite of line 13:
> Case 5 is research, though research with replicated precedent. Published recursion synthesizers need examples that are closed under the recursive call, or else angelic execution to relax that condition **[L]** [one clause each on what "closed under the recursive call" and "angelic execution" mean]. Cases 1–4 are different. By inspection, every function in the current library has one of their shapes **[P]** [confirm that "every" is meant]. What has been run is narrower than that. On its own rows the prototype was run on first-order instances and on two forms that take a function argument (§8.1). On the kernel's spec rows it was run on `foldl`, `seq-corr`, `best-shift`, `argmax-corr` and `last-or`, and not all of these were solved (§8.5 gives the outcome of each). The higher-order `map`, `foldr` and `filter` were not tested. `best-shift` plausibly needs two lifts, and two lifts were not tested either.

**A50. Several "Why" cells and two import bullets in §9 are noun stacks.**

Where: `09.0.md` line 21, codec: "size by counting emitter, canonical decode. The opcode table is a tariff choice you have waived"; line 15, "n-ary, typed, shared holes, operator holes"; line 16, "fixed-point save and load"; line 35, "keep the fact-and-measure scheme, about 50 lines, and the least-fixed-point discipline"; line 48, "three of them are artifacts (§2.7)".

Rewrites:

Line 21:
> The size of a program is found by running the encoder in a mode that only counts bits, and every code decodes in exactly one way. The table that gives each opcode its code sets the prices. You have said that the present prices need not be kept [confirm this reading of "a tariff choice you have waived"].

Line 15:
> It handles operators with any number of arguments, respects types, gives equal sub-terms one shared hole, and can turn an operator itself into a hole.

Line 16:
> Saving, loading and saving again gives an identical file [confirm this reading of "fixed-point"]. On load, specs are replayed and certificates are recomputed.

Line 35: the document does not say what the "fact-and-measure scheme" or the "least-fixed-point discipline" is. One sentence each is needed.

Line 48: name the three prices. §2.7 offers the name bits set by list position and the quadratic work tariff; the third is not identifiable.

### Appendices

**A51. Appendix A: two compressed answers, and two rows whose facts appear nowhere in the body.**

Where and rewrite:
- `AA.0.md` line 15, "Eight representations of one thing. Ambient pricing is not the fault, and cannot be beaten except through a verified bijection or by paying for the fiber."
  > The clunkiness comes from having eight representations of one thing (§2.7). Pricing in the ambient space is not the cause. No derived space can price a residual below its ambient cost, with two exceptions: a verified bijection between the two spaces, or payment of the bits that name the member of the fiber (§6.3).
- Line 9, "Depth one exists and works; a script limits it."
  > Experiments at depth one exist and work, within the fields, operators and bounds that the bootstrap script fixes (§2.4).
- Line 11, "A row is a tuple is an n-ary edge": write "A row is a tuple, and a tuple is an n-ary edge."
- Line 8 cites §2.4 and §7.5 for `target-sensitive-p`, "whose only caller is itself reached only from tests". Neither section mentions it. Either the body states it, or the "See" cell cites the report.
- Line 13 says reentrancy is "Blocked by eight concrete things, among them:" and lists six, as a string of clauses. This is a finding of the audit that the body never states. It belongs in §2.2 as a short list, with the appendix pointing to it.

**A52. Appendix B: nine rows are labels with no statement.**

Where: `AB.0.md` lines 15, 17, 21, 22, 24, 26, 27, 28, 30. Line 9 also ends in a fragment, "solve rules are the other directions".

Twelve rows of the table have no counterpart in §2.8. Three of them are picked up elsewhere in the reviewed files (line 13 by §5.6, line 23 by §5.9, line 25 by Appendix A). The other nine are not explained anywhere. Examples: "An intervention-style generator, G(k, u) = (u, k − u), written and never run"; "\"b bits of freedom is constrained by O(b) scalar fiber observations\""; "The \"shared part plus per-instance part, search in a different place\" table"; "Discrete labels and coordinates need different distances (59 pairs became 106 when confused)". A reader cannot tell what the idea is, what was measured, or why it is worth carrying forward. Each needs one sentence, or should leave the plan (C1).

**A53. Appendix D contradicts the front matter and points to text that is gone.**

Where: `AD.0.md` line 3, "This plan re-imports none of these, with two exceptions that are argued for in the open ... Two further proposals are close relatives of rejected items and are flagged where they appear: random-walk proximity and count-based triggers (§6.4)."

The front matter says "none of it is re-imported", and `02.9.md` line 15 says "which this plan does not re-import". Neither mentions exceptions. The phrases "random-walk proximity" and "count-based triggers" occur nowhere else in the section files, so the flags they promise cannot be found.

Rewrite, if both proposals have left the plan:
> This plan re-imports none of these, with two exceptions that are argued for openly: the lifting forms (§7.1) and subsequence alignment for selection (§7.2). The reasons given for each rejection are those recorded in the revisions of `plan_v2.tex`.

The front matter and §2.9 should then say "none of it is re-imported, with the two exceptions named in Appendix D". The "why rejected" cells are terse ("factorial", "10–30× more than needed", "interpreter weight at a library of a few hundred"). That is acceptable for a record only if the table stays in the plan at all (C5).

**A54. Appendix E: one undefined maturity grade, three cryptic cells, and verification notes in two places.**

Where and rewrite:
- `AE.0.md` line 3 defines "Shipped" and "Replicated". The table also uses "one lineage" (lines 18, 19, 25), "single group" and "one system". Add: ""One lineage" means one research group and the systems that descend from its work."
- Line 16, "five extra helpers: 0.07 s → 128 s".
  > 15–30 node functions are found in under 1 s when the context is minimal. Adding five helper functions to the context raised one time from 0.07 s to 128 s [confirm].
  This number bears directly on §4.1's point that a small grammar is the main control problem, and it appears only in this cell.
- Line 25, "labels from people, last (§6.4)": write "aligning labels supplied by people, which comes last (§6.7)" [confirm the section].
- Line 29, "its author credited the representation": say what the author credited it with.
- Lines 3 and 31 are two paragraphs of verification notes, before and after the table. Merge them into one (B4).

**A55. Pointers into §6 and §8 need re-pointing once those sections settle.**

The section files currently have two sections titled "Making, collapsing and moving spaces" (`06.4.md` and `06.6.md`), `08.7.md` is headed "8.8", and `08.8.md` is headed "8.5". The reviewed files point into those sections as follows.

- To "§6.4" for the vocabulary, the index or name prices: `04.1.md` line 9; `04.5.md` line 9; `05.5.md` line 8; `05.9.md` lines 39 and 45; `07.1.md` line 23; `AD.0.md` line 3; `AE.0.md` lines 25, 26, 27. In the current files, quotients and verb tables are defined in §6.2.
- To "§6.6" and "§6.8": `AA.0.md` lines 17 and 26. There is no §6.8 in the current files.
- To "§6.2" and "§6.3": `05.9.md` line 37; `AA.0.md` line 15.
- To "§8.7" for verb tables: `05.9.md` line 39; `AE.0.md` line 28. To "§8.8" for laws kept by use: `05.8.md` line 7. In the current files the verb tables are under a heading numbered 8.8, and "laws are kept by use" is under a second heading numbered 8.5.
- To "§8.5" for the kernel's spec rows: `05.4.md` line 28; `07.3.md` lines 8 and 13. Two files are headed 8.5 at present. The pointers to "§8.1" and "§8.6" (`05.3.md`, `05.5.md`, `05.9.md`, `07.3.md`) look stable.

**A56. Smaller items, each one line.**

- `02.2.md` line 11 and `02.3.md` line 24, "v1": never defined. Write "the root kernel (v1, as distinct from the copy in `v2/`)". `iota` at `02.2.md` line 11 needs "(a primitive that produces the index list 0, 1, …)".
- `02.4.md` line 7, "the battery's budget": "battery" is the bootstrap script's word for a set of jobs; say so once.
- `04.3.md` line 3, "apply laws as merges until saturation": add "that is, until no law adds a new equality". Line 5, "single-group research": write "has been done by one research group only".
- `05.2.md` line 15, "A class stores that column once, its smallest term, and its evidence grade": write "A class stores three things: the column, once; the smallest term that denotes it; and an evidence grade (§5.5)."
- `05.4.md` line 26: anti-unification is the subject of seven paragraphs and is never said in plain words. One clause at first use would do: "anti-unification, which finds the most specific pattern that several expressions share, with holes where they differ" [confirm].
- `05.9.md` line 11, "this is the \"probe evaluation\" the review mentions": a reader who has not read the review cannot use this. Drop the clause or say what the review said.
- `02.8.md` line 7, "(the reports list ten to twelve each; ...)": "each" has no clear referent.

---

## B. Repetition

Estimated words saved are for the reviewed files unless stated. Firm total: about 940 words. Optional: about 110 more.

**B1. The nuggets from the trail: stated in §2.8, again in Appendix B, and again where they are used. About 385 words.**

Places: `02.8.md` lines 16–29 (383 words); `AB.0.md` (506 words in the table; twelve of its rows restate §2.8); and re-quotations at `04.4.md` line 5 (both "No column is designated as input or output" and "via the exchange of input and outputs"), `05.5.md` line 15 (the "unresolved information" quotation), `05.4.md` line 32 ("five holes to two"), `04.2.md` line 5 and `05.9.md` line 31 (matching is conjunctive-query matching, tree patterns are polynomial), `05.5.md` line 3 and `02.4.md` line 8 ("can propose and never eliminates"). The sentence about uncommitted Python scratch scripts is at `02.8.md` line 16 and `AB.0.md` line 3.

Keep: §2.8, because it states each idea in sentences. Add the location to each item there in parentheses. Appendix B then drops the twelve rows that §2.8 covers (about 240 words). Later sections name the nugget and cite "(§2.8)" in place of quoting it again: `04.4.md` (about 40 words), `05.5.md` line 15 (about 30), `05.4.md` line 32 (about 20), `05.9.md` line 31 with `04.2.md` (about 20), the scratch-script sentence (about 20). One exception: the opening of §5.5 should keep the plan 8 quotation, because the section answers it, and the last item of §2.8 then shrinks to one line (about 15).

The alternative is the reverse: Appendix B keeps everything, with a sentence per row, and §2.8 keeps three sentences and a pointer. It saves about the same number of words and moves about 330 out of the main text. It is the better choice if the owner reads §2 as findings and would rather meet each idea where it is used.

**B2. Appendix A restates §1.5 and the body at length. About 140 words.**

Places: `AA.0.md` line 6 (anti-unification) against §1.5 and `05.4.md` line 26; line 23 (graph isomorphism and e-graphs), which is nearly word for word §1.5's third bullet; line 17 (flat versus nested) against §1.5 and `04.5.md` line 9; line 20 (totality) against `07.1.md` item 2; line 24 (distributivity: "no job asked for it, the shape filter had no case for it, and the budget was 85 times too small") against `02.4.md` line 7.

Keep: the body. Each of these five "Finding" cells keeps its first sentence, which is the answer, and the "See" cell. Savings: about 30, 45, 18, 20 and 25 words.

A larger choice is open to whoever rewrites the Summary: §1.5 (270 words) and Appendix A answer the same thing, the owner's own points. One of the two could point to the other.

**B3. What to keep from the v2 plans: listed in four places under different names. About 95 words.**

Places: `02.9.md` lines 7–15 (128 words); `09.0.md` line 38, the "*From v2*" bullet (75 words); `AD.0.md` line 25, "What survived every pass unchanged is short: ..."; `AA.0.md` line 25.

Keep: §9, whose title is "What to import". Move into its bullet the three items that only §2.9 has (the distinction between lift and split; the replay guard for inverses; "each root row priced once"). §2.9 keeps one sentence: "What is worth keeping from these plans is listed with the other imports in §9." Appendix D drops its closing sentence.

**B4. The verification status of literature claims: stated where the claim is used and again in Appendix E. About 85 words.**

Places: `04.2.md` line 5, "(the span is from the auditor's memory; the benchmark claim was checked against the paper's abstract)"; `04.3.md` line 7, "which the auditor verified from abstracts; it is not a shipped product"; `04.5.md` line 5, "verified against the paper; these are theorems about neural networks"; `05.4.md` line 26, the parenthesis "(One categorical treatment, a single paper the auditor could read only in summary, ...)"; `AE.0.md` line 3, which lists the same four; `AE.0.md` line 31.

Keep: Appendix E, as a single paragraph. In the body, keep a short tag in the style the document already uses at `05.9.md` line 14, such as **[L, abstract only]** or **[L, from memory]**. That keeps the evidence standard visible and saves about 70 words in the body and about 15 in the appendix.

**B5. The budget ladder and the logarithm. About 35 words.**

Places: `02.3.md` lines 9 and 19 (home); `04.1.md` line 5, first three sentences; §1.1 item 3; also §7.6 and §11.1.

Keep: §2.3. `04.1.md` says: "The budget was milliseconds, so the premise is right. But §2.3 showed that budget alone does not help: a thousandfold increase solved two more of sixteen specs, because reach grows only with the logarithm of the work." It then goes straight to "Going from one second to ten hours ...".

**B6. Why operations are host-only. About 25 words.**

Places: `02.2.md` line 21, "The root cause is one fact: **terms are values of the object language; frames, rows, keys, and positions are not.**"; `03.0.md` line 13, "**Frames are not values.** ..."; §1.1 item 2 (the same list of six operations).

Keep: the fact and its **[C]** tag in §2.2. §3 keeps its bold sentence and its consequence, and cites §2.2 in place of restating the list of six operations.

**B7. "Reuse loses". About 25 words.**

Places: `02.4.md` line 9 (home, with the numbers); `02.8.md` line 11; `03.0.md` line 11; `04.3.md` line 5; `05.8.md` line 7; `05.5.md` line 3.

Keep: §2.4. The later mentions are short and each supports an argument, so they stay. `02.8.md` line 11 can become: "*Reuse loses.* Every mechanism that reused learned knowledge cost more than it saved, for the reason given in §2.4."

**B8. The defects of the Stage 1 code. About 25 words.**

Places: `02.9.md` line 5 (`:tabulate` fails at construction; ten exported symbols defined nowhere); Appendix F's housekeeping list, which has both with the same file references.

Keep: Appendix F for the detail. §2.9 keeps "The Stage 1 code in `v2/` added 1,393 lines and no tests, and its main new opcode fails in the form its own proposals build (Appendix F)."

**B9. The margin note "how, though?". About 30 words.**

Places: `02.9.md` line 24 (55 words); the opening of §6's section on making and moving spaces; Appendix C.

Keep: §6, where it is answered. §2.9 keeps: "Neither plan says how spaces are to be compared "only through verified maps", which you asked in the margin. Section 6 answers it."

**B10. "Not re-imported". About 20 words.**

Places: front matter; `02.9.md` line 15; `AD.0.md` line 3.

Keep: the front matter and Appendix D. The bullet in §2.9 is not something "to keep from those plans" and can go. See A53 for the inconsistency among the three.

**B11. Repetition inside §5.9 and §4.5. About 60 words.**

- The line counts "36" and "65" are at `05.9.md` line 29 and again at line 43. Keep line 43.
- "A product of two automata, quadratic in the corpus" is at `05.4.md` line 30, `05.9.md` line 14 ("quadratic over classes") and `05.9.md` line 43. "Deferred to Stage D" is at `05.4.md` line 32 and `05.9.md` line 43. Keep §5.4; §5.9 cites it.
- The outcome of the matching measurement is at `05.9.md` line 29 (last three sentences) and at line 41 ("257,214 backtracks"), as well as in §1.4, §7.6, §8.6 and §11.1. Line 29 can keep one sentence and the pointer.
- `04.5.md` line 5 gives the bound on computation in superposition twice (see A33). About 20 words.

**B12. Small numbers repeated as asides. About 15 words.**

"37 lines" for pullback is at `02.1.md` line 13, `04.6.md` line 5, `05.6.md` line 5 and `09.0.md` line 33. "73 lines" for the evidence record is at `05.5.md` line 11 and `09.0.md` line 14. "About 50 lines" for the termination check is at `07.3.md` line 11 and `09.0.md` line 35. Keep the number in §9, where the import list needs it, and in the first place it appears. Elsewhere the pointer is enough.

**B13. Optional cuts, about 110 words. Each is short and doing some work where it stands.**

- `05.9.md` line 39, the recap of the two measurements (100 words), repeats §1.4, §8.6 and §8.7. Two sentences and the pointers would carry the argument. About 40 words.
- `05.3.md` line 28, the comparison with the kernel (75 words), repeats numbers from §2.3 and §8.1. It could keep "No recursion was searched" and one sentence of caution with the pointer. About 40 words. It does guard the example against over-reading, so it is listed in D as well.
- "N copies of one small graph" is at `04.2.md` line 5 and `05.1.md` lines 3–5. §5.1 could open "As §4.2 observed, ...". About 30 words.

**B14. Outside the scope, noted because it is large: Appendix G.1 repeats the body.**

Six answers in `AG.s1.md` restate text that the reviewed sections now carry, nearly word for word: the learned container (`07.1.md` line 17), the depth of the search tree (`02.3.md` line 18), the tree embedding and superposition (`04.5.md` line 5), the arXiv paper (`04.5.md` line 7), reentrancy and nested interpreters (`04.6.md` line 7), and the spellings of a class (`05.4.md` line 30). If each of those answers became one sentence and a pointer, Appendix G.1 would lose roughly 400 words. This is not counted in the totals above.

**B15. No saving, but worth aligning.** The DreamCoder figure is given in three units (A48). `05.0.md` repeats the front matter's sentence about tags in §5–7; it is useful at the point of use and should stay.

---

## C. Material that belongs elsewhere

Firm total: about 370 words. Optional: about 225 more.

**C1. Appendix B, the nine rows that the plan does not use or explain. About 170 words.**

Where: `AB.0.md` lines 15, 17, 21, 22, 24, 26, 27, 28, 30 (191 words; see A52). They are a record of what the document auditors found in earlier plans. If a row matters to the design, it needs a sentence and a place in §2.8. If it does not, it can stay in the `docs-*.md` reports in `plan_v2c_audit/`, with one line in Appendix B: "The document auditors recorded further ideas from the trail; see the `docs-*.md` reports."

**C2. The detail of arXiv 2611.17309 in §4.5. About 100 words.**

Where: `04.5.md` line 7 (151 words). It answers a margin note, and Appendix G.1 already carries the same detail (Triton kernels, 2.0 × 10⁹ FLOPs, the hand-set values). §4.5 needs only the conclusion: "The paper you cited in the margin, arXiv 2611.17309, supports this. Its model is small and exact, and its answers come from a very large number of very cheap moves. So the bits of the answer come from fast evaluation, not from the model, which argues for an exact store with cheap evaluation and not for a learned embedding (Appendix G.1 gives the details)."

**C3. The audit of the earlier plans in §2.9. About 65 words beyond B8.**

Where: `02.9.md` lines 3 and 5 (134 words). How many claims of `plan_v2b.md` were checked, how many mechanisms of `plan_v2.tex` were imports, and how fast it was revised are findings about other documents. A reader of this plan needs two things from them: which earlier plan can be trusted, and what is kept. Suggested text: "`plan_v2b.md` proved reliable where it was checked (about 35 code claims, three errors), and its Stage 0 depends on nothing unverified. `plan_v2.md` and `plan_v2.tex` rest largely on unverified imports and inventions, and the Stage 1 code built on them does not work as it stands (Appendix F; the `docs-v2b.md` and `docs-v2tex.md` reports)."

**C4. Revision history in Appendix E. About 35 words.**

Where: `AE.0.md` line 31, "The three rows on abstract values were added in the revision and checked against the papers' text (`lit-abstraction.md`); a 1977 paper by Knuth that the outside review also cites could not be fetched." What was added in the revision belongs in Appendix G. The part of that paragraph that must stay is the weak negative: "none found" for learned inverses and learned termination guards rests on searches that were cut short, and §10's "no precedent" claims depend on it.

**C5. Optional: most of the Appendix D table. About 150 words.**

Where: `AD.0.md` lines 5–23 (342 words). It is a record of what earlier audit passes rejected. The plan touches five rows: the symmetry refund (cited by §2.9 and §9), `:tabulate` and `:loop`, the subsequence propagator, the five-extension e-graph (the contrast drawn in §5.8), and the flat vector bus (§4.5). The other twelve rows (171 words) could move to the `docs-v2tex.md` report with a one-line pointer. This is marked optional because the table is also a guard against re-importing, and the owner has rejected plans for that before.

**C6. Optional: the opening quotations of §2.8. About 50 words.**

Where: `02.8.md` line 3 (six quotations from the owner's October prompts). Two quotations would establish that the requirements are stable. The rest can stay in `docs-origins.md`. "Three things changed, by your own hand" (line 5) should stay whole.

**C7. Optional: the note on line counts in §9. About 25 words.**

Where: `09.0.md` line 5, "Line counts are the auditors', from the root tree; where two auditors counted the same code differently, both figures are given." Appendix F already says that the reports disagree on a few line counts and which figure is used.

**C8. Material that should move the other way, into the body.** Two findings exist only in Appendix A (A51): the eight things that block reentrancy, and the fact that the kernel's one dependency test is reached only from tests. If the design rests on them, they belong in §2.2 and §2.4. This adds about 60 words to the body.

---

## D. Clear because it is long: keep

1. **`05.3.md`, both worked examples with their tables.** They are the only place where a class, an inverse and a lift are shown on actual rows. Every later section relies on a reader having seen them.
2. **`05.2.md`, the four nouns**, including the list of what a cell can hold and the closing paragraph on the three senses in which the store is a hypergraph.
3. **`05.1.md`, the observation.** It is short, it carries the owner's own sentence, and the rest of §5 is built on it. If the overlap with §4.2 is trimmed (B13), trim it on the §5.1 side by a clause only.
4. **`05.5.md`, the three grades (observed, tested, certified).** Each bullet says what the grade allows and why. This is the argument for why sampled knowledge can prune, and it does not survive shortening.
5. **`05.4.md` line 3 and the operations table.** The two definitions ("re-index", "collect") are used through the rest of the document. The table is long because it answers every operation the owner listed.
6. **`05.4.md` lines 28–30, the three refinements of anti-unification.** The owner marked an earlier, shorter version of the third with "???". The `(+ x x)` example is what makes the first one clear.
7. **`05.9.md` lines 9–19 (the table of witnesses and the paragraph after it) and lines 25–29 (the three ways to find a map).** These define by-term, by-refinement and by-backtracking, which §7.6, §10 and §11 use without re-defining.
8. **`07.1.md` line 15, the container rule** ("`tabulate` is to a sequence what `tuple` is to a tuple ..."), and line 25, "A consequence worth stating". The first is the argument for granting the lifting forms. The second is the direct answer to "lift has to be a synthesizer primitive".
9. **`07.3.md`, the five cases.** They look like a list that could be a table. Each case says why it is or is not recursion, and case 4 carries the distinction between a reduction and sequential state.
10. **`02.3.md`, the budget table and the three failure modes** (structure, exponent, memory). This is the evidence that the first perspective of §4 is answered with. A1, A2, A5 and A6 make it clearer without making it shorter.
11. **`02.2.md` and `02.5.md`, the two tables.** Each is the whole finding of its section.
12. **`03.0.md`, complete.** It is 270 words and it is the hinge between the findings and the proposal. `05.7.md` mirrors it in 64 words and should stay too.
13. **`09.0.md` line 9, the definitions of "as code", "as design" and "re-seat".** The table is unreadable without them.
14. **`04.3.md` line 7, the paragraph that e-graphs, version-space algebras and tree automata are one data structure.** It explains why the plan keeps classes and drops rules.
15. **The statements of what the prototype did not test**, at `05.3.md` line 28, `05.4.md` line 24, `05.5.md` lines 13 and 15, `05.6.md` line 9, `07.1.md` line 15 and `07.3.md` line 13. They read as repeated hedging, and each one limits a different claim. They are the document's evidence standard at work.
