# Fact-check, round 3, scope C, part A: §2 (intro), §2.1, §2.2, §2.3

Frozen copy: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md`, lines 120 to 219. Line numbers below are line numbers of that file. Report paths are under `/home/tlh24/lisploop/plan_v2c_audit/reports/`, code paths under `/home/tlh24/lisploop/`, and logs under `/home/tlh24/lisploop/plan_v2c_audit/scripts/`. The section files `sections/02.0.md` to `02.3.md` were confirmed to be byte-for-byte what the frozen copy contains.

Scripts used: `fc-c/A-tokdiff.py` (numbers, tags, code spans, quotations and section pointers that differ between the pre-clarity and current files) and `fc-c/A-words.py` (the words that the review lists as used in two senses).

## Findings, most serious first

**1. FACTUAL ERROR. The definition of "full grammar" is wrong, and the error bears on the budget table.**

Line 179: "The *full grammar* is every operator the kernel has, including the library functions defined so far, with no whitelist."

What the source says. The grammar that the audit builds when it ignores the whitelist is constructed by `active-library-spec-operators` (`v2/consolidate.lisp:1213-1246`). It contains `+ - * / mod < =` over the spec's domain, `if`, and then, only for each type that appears in the spec's own signature, `=` and `if` at that type, the sequence primitives `cons tail length concat at`, the tuple primitives `tuple` and `at`, and `code-eval`; and finally every active `:function` entry of the library. It also adds the literals 0, 1, 2 and raises the bit bound from 130 to 154 (`v2/consolidate.lisp:1264-1271`; `empirical.md:262-265`). It does not contain `gather`, `member`, `lookup`, or the code-reflection primitives. The printed grammar for `map-adjacent` has 28 operators (`empirical.md:329-330`), against 27 primitives plus the library. The omission is not harmless: the empirical report says that `argmax-corr` cannot be expressed in this grammar because tuple operators are added only for tuple types in the spec's own signature (`empirical.md:416-418`, `empirical.md:519`). The gap log (`clarity-gaps-sec2.md:14`) cites `empirical.md:262-265` and `:329-330`, and neither says "every operator the kernel has".

Replacement: "The *full grammar* is the grammar that the audit builds when it ignores the whitelist. It contains the arithmetic and comparison primitives, `if`, the sequence, tuple and code primitives for each type that appears in the spec's own signature, and every library function defined so far. It is not every operator the kernel has: it leaves out `gather`, `member`, `lookup` and the primitives that inspect code, and it adds tuple operators only when the spec's signature contains a tuple type. For that reason one of the sixteen specs, `argmax-corr`, cannot be expressed in it."

**2. FACTUAL ERROR. The rewording turned "6–7 bits per tenfold of work" into "an AST node is 6–7 bits".**

Line 197: "One node of a program's syntax tree, an *AST node*, is 6–7 bits. So **each tenfold increase in work buys about one more AST node**."

What the source says. `empirical.md:250-252`: "exact enumeration gains 5.7–7.5 bits per 10× of work; deduped enumeration gains 9.7–14 bits per 10×. A variable costs 3–5 bits and an application 6 bits or more plus its operands, so each 10× buys roughly one more AST node without dedupe and roughly two with it." The 6–7 bits is the gain per tenfold of work (a factor of 1.38–1.50 per bit gives 5.7 to 7.2 bits per factor of ten). The size of a node is given separately, and it is 3–5 bits for a variable and 6 bits or more for an operator (the same report lists operator overheads of 6, 9 and 14 bits at `empirical.md:183-184` and `:208`). The pre-clarity text was "**Each tenfold increase in work buys about one more AST node** (6–7 bits)", in which the parenthesis could be read either way. The rewrite, which follows clarity-review item A6 (written without opening the sources), fixed the wrong reading and made it the premise of the bold sentence. The gap log has no entry for it.

Replacement: "At a factor of 1.38–1.50 per bit, each tenfold increase in work buys 6–7 more bits. One node of a program's syntax tree, an *AST node*, costs 3–5 bits when it is a variable and 6 bits or more when it is an operator. So **each tenfold increase in work buys about one more AST node**."

**3. FACTUAL ERROR (small). "One for each constructor" is not what the ten rules are.**

Line 136: "To turn a pulled-back requirement into an explicit set of allowed values, the kernel uses ten hard-coded rules, one for each constructor; the learned *solver* entries, ..."

What the source says. `requirements.lisp:245-256` (`*fold-rules*`) holds ten rules, each for one pairing of an outer operator with an inner constructor: `at` on `tuple` and on `cons`; `tail` on `cons`; `length` on `cons`; `=` on `tuple`, `cons`, `if`, `code-apply` and `code-subst`; `member` on `tuple`. That is ten rules over five constructors (`tuple` has three, `cons` has four). `core-repr.md:30` says "ten hard-coded per-constructor fold rules". The pre-clarity text said "ten hard-coded constructor rules". The rewrite added "one for each".

Replacement: "To turn a pulled-back requirement into an explicit set of allowed values, the kernel uses ten hard-coded rules, each of which takes one operation off one constructor (for example, an equality with a literal off a `tuple`, or `at` off a `cons`); the learned *solver* entries, ..."

**4. OVER-STATEMENT. The tree is "a root with one or two children" only for the four specs that stay unsolved.**

Line 196: "At every budget tried, this tree is a root with one or two children." The same claim, unqualified, is in §1.1 at line 57 ("the search tree has two or three nodes at every budget").

What the source says. `empirical.md:293-297`: "For the four unsolved recursive specs the node census is identical at every rung from 350k to 350M", with 3 nodes for `map-adjacent` and `shift-seq` and 2 for `scan` and `best-shift`. For `argmax-corr`, which is one of the seven specs of the table's second row, the same report gives 34 sub-problems at 35 million work units, and 49 and 64 when `:max-depth` is raised to 3 and 4 (`empirical.md:356-362`; log `empirical/logs/e4_x100_argmax-corr.log`, ":NODES 34"). That tree did grow, and it returned an impostor. The pre-clarity sentence ("The search tree has two or three nodes at every budget") had the same gap; the rewrite made it more definite. The next sentences of the paragraph already speak of "these children" and of "the four specs that stay unsolved", so the qualifier only needs to move up.

Replacement: "On the four specs that stay unsolved, this tree is a root with one or two children at every budget tried. (The tree of a fifth spec, `argmax-corr`, did grow, to 34 sub-problems, and to 49 and 64 when it was allowed more depth. What it returned was an impostor.)"

**5. OVER-STATEMENT. The gloss on reentrancy is attributed to you and has no source.**

Line 162: "*Reentrancy*, your "freely shifting abstraction level", would be the kernel applying its own search to its own programs and records."

What the source says. Your prompt (`plan_v2_prompt.md:5`): "Reentrancy I think means freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph - whether that's an execution graph, a literal graph described by the data, graph generated by an AST, or some combination of all these". The gloss "the kernel applying its own search to its own programs and records" comes from the clarity review's proposed rewrite (item A35), which was written without opening any source. The worker on §4 declined to use it for that reason (`clarity-gaps-sec4-9.md:12`: "was not used, because no source states it"), and §4.6 (line 412) quotes you instead. The worker on §2 used it, and the §2 gap log has no entry for it. The sentence was not in the pre-clarity §2.2. What the search audit does say, in the section the plan cites, is what exists today toward reentrancy: synthesis over code values, frames built from the search's own messages, and searches nested in searches (`search-engine.md:752-771`), and then "What concretely stops full reentrancy" (`search-engine.md:773`).

Replacement: "*Reentrancy* is, in your words, "freely shifting abstraction level when recognizing, transforming, simplifying, expanding a graph". The search audit took this to mean that the kernel's search can be applied to the kernel's own products: code, the tables built from its own messages, and searches nested inside searches (search-engine report, §6.1). It lists eight concrete things that block this (search-engine report, §6.2) **[C]**:"

**6. OVER-STATEMENT. "Raised as well" says that two budgets were raised; the source varies one.**

Line 217: "One test problem from Plan 8 is solved at the default budget. It is not solved at a budget of 1,000,000 work units when the budget of the kernel's first phase is raised as well **[D]**."

What the source says. `plan8.md:296`: "Probe 5 now solves at the default budget in `264,353` work; passing `:heuristic-budget 16000`, which §6.3 and §6.5 recommend, now leaves it unsolved at `1,000,000`." (Quoted the same way at `docs-plan8-9.md:497`.) "The default budget" there is the default budget of the first phase (`:heuristic-budget`, 2,000). The only thing that differs between the two runs is that phase's budget. Nothing says the job's own budget was at its default in the first run and raised in the second. The bold claim ("More budget is not even monotone") stands, but for the first phase's budget.

Replacement: "One test problem from Plan 8 is solved in 264,353 work units when the kernel's first phase has its default budget. When that phase is given a larger budget, 16,000 units, the same problem is still unsolved after 1,000,000 work units **[D]**."

**7. MISSING CAVEAT. "Held-out-sound" in this section means one hand-written test case per spec.**

Line 179: "A solution is *held-out-sound* when it is also right on fresh inputs that were not among the spec's rows." (The Terms table, line 27, says "*Held-out* scores count fresh inputs.")

What the source says. The harness that produced "8, then 10, then 10, then 10, of 16" checks each solution on exactly one fresh input, written by hand for that spec: `v2/experiments/stage0-audit.lisp:59-84` (`held-out-test-cases`), copied into the empirical auditor's script (`empirical/scripts/e4_rescue.lisp:64-82`, checked by `held-out-ok` at `:94-103`). A reader who has seen "200/200 on held-out examples" in §1.4 will assume something similar here. With one case per spec, the counts of sound solutions in the first table are upper bounds.

Replacement: "A solution is *held-out-sound* when it is also right on a fresh input that was not among the spec's rows. In the kernel's own audit harness, which produced the counts below, that is one hand-written input for each spec, so a count of sound solutions here is an upper bound."

**8. MISSING CAVEAT. None of the four pruner tests ran inside a synthesis job, and the new label on row 2 suggests that the others did.**

Lines 204-213, in particular line 209: "Arithmetic problems over `+` and `*`, searched on their own rather than inside a synthesis job | Pruning cut work 11–31×." and line 211: "`map-adjacent` | The same work reached 70 bits instead of 47."

What the source says. The 11–31× figures are from two observation searches over a six-row integer problem with `+` and `*` (`search-engine.md:1027-1035`; log `search-engine/exp-d.out`, 141,501 / 12,555 and 1,412,531 / 45,249), so the gloss on "closed arithmetic frames" is right as far as it goes. But the other three rows were flat searches too. The finite-field row is the repository's flat benchmark (`docs-v2tex.md:720-733`). The integer-grammar row and the `map-adjacent` row are "One flat `start-search` over a frame whose target no candidate satisfies" on the root lane's grammar (`empirical.md:172`, `:220-229`). The empirical report says "v2's `:prune-behaviors-p` was measured in flat searches only (E3, E3b). I did not wire it into the synthesis job's node searches, so there is no E4 number with dedupe on" (`empirical.md:540-541`), and the search audit lists as not determined "Whether the dormant v2 pruning stays sound inside the full tree (recursive jobs, CEGAR, shared tables)" (`search-engine.md:1078-1079`). The pre-clarity text did not have the caveat either, but it also did not draw a contrast that only one row satisfies.

Replacement for the cell at line 209: "Integer arithmetic problems over `+` and `*`, on six rows". Replacement for the sentence at line 204 that introduces the table: "Three auditors switched them on by hand **[M]**. All four tests were flat searches. The pruner was not run inside a synthesis job, and whether it stays sound there was not determined."

**9. INCONSISTENCY (term). "Spec" is defined as a function, and the library's `:spec` entries are a wider set.**

Line 177 (and the Terms table, line 25): "A *spec* is one function that the bootstrap asks the kernel to synthesize, given as a few rows of inputs and outputs."

What the source says. A `:spec` entry "holds: the input and target types; the example rows ...; a `:specifies` edge naming the entry to produce", with metadata for solvers as well as functions (`bootstrap-reflection.md:313-321`). The library holds 31 of them (`bootstrap-reflection.md:157`), and they specify solvers, guards and transformers besides functions (`bootstrap-reflection.md:358-359`, `:401-402`, `:811`). §2.5 at line 238 speaks of "31 `:spec` entries" beside "the 16 specs of §2.3". The definition fits the sixteen of this section and does not fit the thirty-one.

Replacement: "A *spec* is one entry that the bootstrap asks the kernel to produce, given as a few rows of inputs and outputs. The library holds 31 specs. The sixteen used in this section are the ones that specify functions."

**10. COSMETIC (precision). "Its own budget, separate from the job's" can be read as "not charged to the job".**

Line 177: "It has its own budget, separate from the job's."

What the source says. The first phase has a cap of its own (2,000 units by default, 15,000 in the bootstrap), which is "fixed at job creation and does not scale with the top-level budget" (`search-engine.md:60-61`, `:266`; `synthesize.lisp:373-390`). Its work is still charged to the job: it "runs synchronously on a private ledger and is then "paid off"" out of the job's work (`search-engine.md:118-121`).

Replacement: "It has a cap of its own, which is fixed when the job is created and does not grow when the job's budget is raised. The work it does is still charged to the job."

**11. COSMETIC (precision). Two phrases in the Structure paragraph come from the review's rewrite, not from the report.**

Line 196: "a fixed list of *proposal generators*: host functions that each suggest one way to decompose it. The main one is a skeleton for recursion."

What the source says. The search audit lists 18 generators in the kernel (`search-engine.md:703-723`). Several return many decompositions at once (one for each library function, one for each tuple component, up to two features). It calls the recursion skeleton "The kernel's only recursion skeleton" (`search-engine.md:340`), not the main generator. The pre-clarity text said "The kernel's main recursion skeleton".

Replacement: "a fixed list of *proposal generators*: host functions that each suggest one kind of decomposition for it. The one that matters for these specs is the kernel's skeleton for recursion."

**12. COSMETIC (precision). A schema is not "supplied for one function".**

Line 179: "A *schema* is a hand-written skeleton of a recursive program, supplied for one function."

What the source says. There are five schemas for seven functions: `:lookahead-inductive` serves `map-adjacent` and `last-or`, and `:counter-inductive` serves `positions` and `best-shift` (`search-engine.md:733-737`; `bootstrap/recursion-schemas.lisp:8-9`). All five are passed to every synthesis call of the bootstrap (`bootstrap-reflection.md:320-321`), and each fires when its shape applies.

Replacement: "A *schema* is a hand-written skeleton of a recursive program. The bootstrap has five. Each was written with one or two of its functions in mind, and all five are offered to every job."

**13. COSMETIC. The file-and-line reference now reads as the location of `lift-frame`, and it is the interior of that function.**

Line 133: "The nearest thing is the host function `lift-frame` (`frame.lisp:1214-1256`) **[C]**."

What the source says. `lift-frame` is defined at `frame.lisp:1194` and runs to line 1271 (`core-repr.md:385`: "`lift-frame` (frame.lisp:1194-1271, 78 LOC)"). Lines 1214-1256 are the part that expands the decoder. In the pre-clarity text the same reference stood at the end of the sentence, after "and discards it", where it read as the location of the expansion.

Replacement: "The nearest thing is the host function `lift-frame` (`frame.lisp:1194-1271`) **[C]**."

**14. COSMETIC. Two cells of the budget table can be misread.**

Line 189: "The same seven, with 100 and 1000 times the budget (350 million units, about a minute each, 2.6–3.5 GB of live memory)". The parenthesis describes the 1000× runs only. The 100× runs were 35 million units and 6–8 s (`empirical.md:33`, `:35`).

Line 187: the fourth figure of "8, then 10, then 10, then 10" was not measured on a run of all sixteen specs. The whole sequence was run at 1, 10 and 100 times the budget (`empirical.md:370-375`; logs `empirical/logs/e4_seq_x1_nofix.log`, `e4_seq_x10_nofix.log`, `e4_seq_x100_nofix.log`, which give 8, 10 and 10). At 1000 times, "×1000 was run per spec for the five specs unsolved at ×100, not as a whole 16-spec sequence" (`empirical.md:538`). The count of 10 follows, because none of the five gained a sound solution. Both cells were the same in the pre-clarity text.

Replacement for line 189: "The same seven, with 100 times the budget (35 million units), and the five still unsolved with 1000 times (350 million units, about a minute each, 2.6–3.5 GB of live memory)". Replacement for the right-hand cell of line 187: "The number of specs with a held-out-sound solution was 8, then 10, then 10, then 10, of 16. The last figure comes from running each of the five specs still unsolved at 100 times, one at a time."

## Changes against the pre-clarity version

No number, quotation, evidence tag or file-and-line reference was dropped from any of the four files (`fc-c/A-tokdiff.py`). Everything below is a change or an addition.

| Section | Item | What changed | Supported by |
|:--|:--|:--|:--|
| 2 intro | pointer | "Appendix F" became "Appendix D" | re-lettering; Appendix D (line 1511) does list the audit reports |
| 2.1 | `pairs`, `anchors`, `edges` | one sentence each on what they record; the words "equal" and "distinct" | A4; gap log line 23; `core-repr.md:147-150`; `frame.lisp:20-24`; `enumerate.lisp:607-687`. Correct |
| 2.1 | pullback, decoder, lift | three definitions, the example `map`, pointer to §5.6 | A4; gap log lines 20-21; `frame.lisp:544-547` and `:1194-1201` (docstrings); `docs-origins.md:600-607`. Correct. §5.6 (line 553) says what the pointer promises |
| 2.1 | coupled constraints | "capped at 4 candidate models per slot and 256 combinations" became "keeps up to 4 candidate programs for each unknown and tries up to 256 combinations" | A4; gap log line 22; `synthesize.lisp:636-642`. Correct |
| 2.1 | terms not shared | Lisp shorthand unpacked; "which the kernel takes before it starts a resumable computation such as a search on it" added | A17; gap log line 24; `frame.lisp:96-98`; `enumerate.lisp:361`; `synthesize.lisp:177`; `core-repr.md:36-38`. Correct |
| 2.1 | `lift-frame` | sentence rewritten; reference `frame.lisp:1214-1256` and **[C]** moved next to the function name | A18. Wording correct; reference placement is finding 13 |
| 2.1 | ten rules | "ten hard-coded constructor rules" became "ten hard-coded rules, one for each constructor" | UNSUPPORTED. Finding 3 |
| 2.1 | solver | gloss "computes an unknown argument of an operator from its other arguments and its result" added | gap log line 32; `laws-library.md:150`, `:176`. Correct |
| 2.2 | host and object language | new paragraph | A3. No fact added |
| 2.2 | root kernel | "It describes the root kernel (v1, as distinct from the copy in `v2/`)" added | A56. Correct (`core-repr.md:386` and `:390` note what v2 adds) |
| 2.2 | `iota` | gloss "a primitive that produces the index list 0, 1, …" | A56; gap log line 29; `v2/vm.lisp:262`; `core-repr.md:746`. Correct |
| 2.2 | table, Fiber row | "one fold rule per constructor" became "one simplification rule per constructor" | A7. Supported as a renaming. (The row has the same looseness as finding 3: `tuple` has two preimage rules, `core-repr.md:390`.) |
| 2.2 | reentrancy | new paragraph, the list of eight, a second **[C]**, pointers to §2.3 and §2.6 | C8 and A51; gap log line 30. The eight are correct (see below). The opening gloss is UNSUPPORTED: finding 5 |
| 2.2 | "model" | "where the child's model is its candidate program" added | A16; gap log line 28. Correct for `compose-through` (`core-repr.md:401-406`) |
| 2.2 | four senses of "lift" | the four named, with functions | A16; gap log line 26. Each description matches the function's docstring (`frame.lisp:1194-1201`, `decompose.lisp:384-388`, `consolidate.lisp:603-606`, `consolidate.lisp:2081-2083` and `:1977`). The count of four rests on one cell of the report, `core-repr.md:387`, which names three "other things called lift" and says "four meanings of one word"; reading `lift-frame` as the fourth is the natural reading and the gap log says so |
| 2.2 | three senses of "fiber" | the three named | A16; gap log line 27; `core-repr.md:390` word for word. Correct |
| 2.3 | definitions | two new paragraphs: spec, work unit, recursion-synthesis job, flat search, first search phase, schema, whitelist, full grammar, held-out-sound, impostor, bit bound | A1, A2; gap log lines 5-18. Correct: work unit, recursion-synthesis job, flat search, first search phase (but see finding 10), whitelist, impostor, bit bound. Wrong: full grammar (finding 1). Caveat missing: held-out-sound (finding 7). Imprecise: spec (finding 9), schema (finding 12) |
| 2.3 | budget table | cells made into sentences; "350k" became "350,000 units"; "350M work" became "350 million units"; "bounded exhaustion" became "tried every program that its bounds allow"; "the depth and stage budgets" became "the depth limit of the search tree and the budgets of the kernel's internal search phases" | A2; gap log lines 17-18; `search-engine.md:328`, `:330`; logs `search-engine/exp-b-ma-noschemas-exhaust.out`, `exp-b-ma-allknobs.out`. Correct. Finding 14 concerns cells that did not change |
| 2.3 | Structure | "two or three nodes" became "a root with one or two children"; proposal generators defined; "the four stuck specs" became "the four specs that stay unsolved" | A5; gap log lines 33-34. The count is correct for those four; scope is finding 4; two phrases are finding 11 |
| 2.3 | Exponent | body bit and lane defined; "(6–7 bits)" became a statement about the size of an AST node; "are 132–259 bits" became "have bodies of 132–259 bits" | A6; gap log lines 35-37. Body bit, lane and "bodies" are correct (`empirical.md:302`, `:293-297`, `:318-320`). The AST-node sentence is UNSUPPORTED: finding 2 |
| 2.3 | the 260-bit answer | explanation added; `:lookahead-inductive`; "(search-engine report, §0)" | A10; gap log line 38; `search-engine.md:45-47`, `:325`; log `search-engine/exp-b-ma-schemas.out` (every sub-problem has "bound=130", "best-bits=260", the third sub-problem is ":LOOKAHEAD-INDUCTIVE"). Correct |
| 2.3 | "v1" | "the root kernel (v1, as distinct from the copy in `v2/`)"; "they give the same outputs on the spec's rows as a tree built earlier" added | A56; `empirical.md:57-59`. Correct |
| 2.3 | pruner | paragraph became a table; definitions of the pruner and the columnar evaluator; gloss on "closed arithmetic frames"; the reason a five-element field flatters pruning; "covered the same horizon" became "The same size bound was reached" | A11; gap log lines 39-43; `search-engine.md:1021`, `:1027-1035`; `docs-v2tex.md:738-739`; `empirical.md:203-204`. The figures and definitions are correct. The missing caveat is finding 8 |
| 2.3 | profile | list of four items unpacked; "weak hash table" became "hash table"; "which advances the search one work unit at a time" added | A13; gap log line 45; `empirical.md:504-506`, `:136-137`. Correct |
| 2.3 | non-monotone budget | "One Plan 8 probe solves at the default budget and fails at 1,000,000 with a larger Stage A budget" rewritten | A1, A9. "raised as well" is UNSUPPORTED: finding 6 |
| 2.3 | 158 decisions | "By class" became "five categories"; explanation of why the figures exceed 158; a definition of reflection with pointer to §7.4 | A12; gap log line 44; `search-engine.md:485-487`, `:690-691`. Correct. §7.4 (line 913) opens with the same definition |

## Checked and found correct

- The eight blockers of reentrancy (lines 164-171) against `search-engine.md:775-815`: each of the eight in the plan corresponds to one of the eight in the report, in the same order, with none merged, split or invented. Item 3's "create" stands for the report's "synthesise", and item 8's "tables" for the report's "message rows".
- Frame facts of §2.1: the row and its requirement over one unknown (`frame.lisp:7-10`, `:221-222`); `frame.lisp:14-24`; the 4 and 256 at `synthesize.lisp:636-642`; pullback at `frame.lisp:544-580` being 37 lines; the soundness test at `tests/invariants.lisp:120-236`; seven extractor functions and 27 call sites (`core-repr.md:413-415`, `:541`); 4–60 ms at 4,000 rows (`core-repr.md:593`, `:810`).
- The operation table of §2.2 against `core-repr.md:380-397`: 34 call sites of `instantiate` (counted in the code: 34), "nine further variants", "about 350 lines" (78 + about 270), `anti-unify` at 38 lines with six call sites (counted in the code: six), and every operator name in the middle column.
- The quotations "wholly in the host lisp" (`plan_v2_prompt.md:4`) and "very limited" (`plan_v2_prompt.md:10`) are verbatim. "freely shifting abstraction level" is verbatim (`plan_v2_prompt.md:5`).
- Throughput and budgets of §2.3: 5–7 million and 33–69 million units per second (`empirical.md:123-133`; `empirical/logs/e4_fit.txt` gives 4.90 to 6.10 million at 350 million units); 350,000 at `consolidate.lisp:1209`; 0.06–0.07 s (`empirical.md:23`); about 2 × 10¹⁰ per hour (`empirical.md:145`); 0.4 s and byte-identical (`empirical.md:87-88`, `:103`); 44 s (`docs-plan6-results.md:691`).
- The budget table: 8, 10, 10 from the sequence logs; `positions` and `seq-corr` (`empirical.md:32`); the four still cut off, 2.6–3.5 GB (`empirical.md:35`; `e4_fit.txt`: 3,219, 3,460, 3,366 and 2,597 MiB); 2.83 × 10⁹ and 8,085× (log: 2,829,937,699); 130 to 300 and 1.5 × 10⁹ (`search-engine.md:330`); the `foldl` impostor (`empirical.md:38`).
- Exponent and memory: 1.38–1.50 per body bit (`empirical.md:304-313`); 18–23 bits (recomputed from the table: 18 to 23); 53–63 bits in an hour (`empirical.md:316`); bodies of 132–259 bits (`empirical.md:319-320`); about 430 bytes per tree, 11 GB exhausted before 7 × 10⁸, 180–240 GB (`empirical.md:51-54`; log `empirical/logs/e4_x2000_shift-seq.log`).
- 109,012 work units and 260 bits under a bound of 130 (log `search-engine/exp-b-ma-schemas.out`).
- Duplicates: 99.0–99.8% (recomputed: 98.97%, 99.58%, 99.76%); 315,388 trees and 767 behaviours (log `empirical/logs/e3b_map-adjacent_exact.log`); ×1.37–1.42 and ×1.17–1.25 (`empirical.md:233-235`).
- Pruner figures: 6–79× and 11–118× (recomputed from `docs-v2tex.md:722-733`: 5.8, 16.9, 78.9 and 10.6, 27.5, 118.4); 11–31× (log `search-engine/exp-d.out`); 1/470 (1,427,679,951 / 3,039,877 = 469.6, logs `e3_v2_g2_exact.log` and `e3_v2_g2_prune.log`); 70 bits against 47 (logs `e3b_map-adjacent_prune.log` and `_exact.log`); about two nodes per tenfold with the pruner (`empirical.md:250-252`).
- Profile: 3% (log `e6_profile_synthesis_map-adjacent.log`: 3.0%); about half in flat search (log `e6_benchmark_profile_root_quartic_86.log`: 52.4%).
- The 158 decisions and 52 / 51 / 30 / 30 / 6 (`search-engine.md:690-691`); the recursion skeleton at `decompose.lisp:341-382` (read in the code); the lockstep form (`search-engine.md:717`).
- Definitions checked against the code as well as the reports and found right: work unit (`core-repr.md:239-249`, `:320-323`; `search-engine.md:113-121`); the kernel's first search phase (`condense.lisp:3`, `:117-144`; `synthesize.lisp:392-408`; the run-weight term that the plan leaves out is zero by default, `synthesize.lisp:156`); lane; body bit; the pruner; the columnar evaluator; snapshot; `pairs`, `anchors`, `edges`.
- Consistency with the Terms table (lines 19-43) and §1.1 (lines 55-60): host and object language, frame, work unit, impostor and "Stages A to D" agree with §2.1 to §2.3. §1.1 item 3 (0.06 s, 8 to 10 of 16, one AST node per tenfold) and item 4 (99%, 6× to 470×) agree with §2.3.
- Words used in a second sense inside lines 120-219: "class" at line 173 ("a class of rows whose requirements can be satisfied together"), which is the code's `fiber-class` and not a class in the plan's sense; "Quotient" at line 155, in the merging sense that §5.4 keeps. Outside the slice, §1.1 at line 57 still says "the search tree has two or three nodes", where the rest of the document now says "sub-problems". No use of "Stage", "fold", "witness", "signature", "probe" or "index" in a second sense was found in the slice.
- Old terms of §6 ("property signatures", "usage counts", "retrieval index", "four geometries"): none in lines 120-219.

## Not checked, and why

- The 6–79× and 11–118× figures rest on the table in `docs-v2tex.md`. The script is kept (`scripts/docs-v2tex/e2flags.lisp`) and its output is not, so the figures were recomputed from the report's table and not from a log.
- "4–60 ms at 4,000 rows" rests on `core-repr.md`. The script is kept (`scripts/core-repr/probe10.lisp`) and its output is not.
- "Four auditors tested this independently and agree" (line 183) and "Three auditors switched them on by hand" (line 204): the rows of the two tables were traced to the empirical, search-engine and docs-v2tex reports. Which auditor is the fourth for the first table was not established.
- The count "four" for the senses of "lift" (line 173) cannot be confirmed beyond the one cell at `core-repr.md:387`. The report does not list the four.
- The two rates of the synthesis job disagree between reports (5–7 million in `empirical.md`, 6.1–8.7 million in `search-engine.md:246`), and so does the size of the schema-assisted answer (260 bits in `search-engine.md:45`, 262 in `empirical.md:319`). Both disagreements predate this round, and `factcheck.md` is said to tabulate the first; neither was re-run.
- Nothing was executed. No Lisp was loaded and no experiment was repeated.
- Gap-log entries about §2.4 to §2.9 that fall inside lines 5-46 of the log (line 7, `02.7.md`; line 31, `target-sensitive-p`) were left to the fork that has those sections.
