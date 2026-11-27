# docs-origins: the original ambition and the first four plans

Auditor: `docs-origins`. Repository read-only; all code tags come from a quick grep of the root
kernel (`/home/tlh24/lisploop/*.lisp`, `tests/`, `milestones/`), not from an audit.

Documents read in full, in order: `deprecated/prompt.md`, `deprecated/plan.md`, `deprecated/plan2.md`,
`deprecated/plan3.md`, `deprecated/plan4.md`, `prompt4.md`; lens: `plan_v2_prompt.md`.
Not read (other auditors): `plan_v2.md`, `plan_v2b.md`, `plan_v2.tex`, and `deprecated/results.md`
(which plan4 names as the home of its measurements).

Conventions.
- **[OWNER]** = the owner's own words (prompt files, prompts quoted verbatim inside plans, commit
  messages). **[AI]** = agent-written plan text. Quotes are verbatim; where the source hard-wraps a
  sentence across lines the wrap is joined, nothing else is changed.
- Code tags: **STILL-IN-CODE** (file:line), **GONE**, **NEVER-BUILT**, plus **ALTERED** where the
  idea survives in a different form.
- Short names: P0 = owner prompt of 14 Oct (quoted in `deprecated/plan.md` L16-182); P2 = owner
  outline of 19 Oct (quoted in `deprecated/plan2.md` L33-190); Porig = `deprecated/prompt.md`;
  P4 = `prompt4.md`; V2P = `plan_v2_prompt.md`; plan1..plan4 = `deprecated/plan.md` .. `plan4.md`.

---

## 0. Dating, authorship, and what each document is

From `git log --follow` plus `--name-status` on the prompt/plan files:

| date | commit | file | owner's commit message (verbatim) | what it is |
|---|---|---|---|---|
| 2026-10-14 | 8630973 | plan.md | "initial work on lisploop learned symmetries / AU.  Claude has expanded my prompt, need to review it." | [AI] plan1; embeds P0. "Nothing is implemented" (L6); 5 throwaway python checks "not in the repo" (L7-8) |
| 2026-10-19 | ad4ea84 | plan2.md | "much better - need to check the DL claim, though." | [AI] plan2; embeds P2. "Nothing is implemented" (L22); 9 throwaway python checks (L22-24) |
| 2026-10-20 | 11ab3c7 | prompt.txt | "adding v2 of the prompt so we can git-diff it after updating." | [OWNER]; renamed to prompt.md at b5e6ccb (26 Oct) |
| 2026-10-23 | 95eed0f | plan3.md | "Cleaner tighter plan - some loose edges, but I'm starting to feel that it won 't simple run in circles" | [AI] plan3, a different, much more cautious voice. "does not report an implementation or successful results" (L7) |
| 2026-10-26 | b5e6ccb / bf51858 | prompt.md, prompt4.md, plan4.md | "prompt added, needs work." / "I'm feeling more confident now about the plan, let's see if it can be implemented." | Porig = 8 pillars + the P2 outline. P4 = 9 pillars. plan4 embeds P4 as of 26 Oct (L12-79) |
| 2026-10-27 | 861424f .. 7446706 | results.md, code | "results from the implementation of milestone 1, needs critical review."; "switched to a bit-cost model; the original ran into problems with integers, and might not scale well to larger libraries." | plan4 is the first plan that was implemented |
| 2026-10-28/29 | 739a852, cd68027, c3709ad | plan4.md revisions | "AU enabled, term rewriting now built into the DSL.."; "milestone dispatched, though needs verification / auditing."; "going to transition to a homoiconic kernel, rather than the bloated VM Astra designed." | plan4's implementation abandoned within two days of reaching milestone 4 |
| 2026-10-30 | d48fade, a23e454 | plan5.md, plan6.md | "plan6 revised, milestones 1-4 check out, need to do 5, 7, 8" | successor kernel (out of my scope) |
| 2026-11-04 | 4428061 | all of the above moved to `deprecated/`; P4 gets the outline re-attached | "revised plan again!  #7 now. Continuing the cleanup." | |
| 2026-11-04/05 | d5cf69f, b37fb35 | prompt4.md | "revised the prompt, but not yet complete..."; "revised the prompt again" | [OWNER] pillar 7 rewritten: metrics, learned spaces, geometry (see 1.3) |
| 2026-11-21/24 | 300c6bd, 15e64c6 | plan_v2_prompt.md | "revised the prompt; running again." | the current request |

Facts that matter for reading the trail:

1. **Nothing in plan1 or plan2 was ever run in this repository** (no `.lisp` file exists in the
   tree before 27 Oct). Every "checked" number in plan1 and plan2 comes from python scratch
   scripts that were never committed (plan1 L6-9, plan2 L22-24). They are unverifiable. plan3
   contains no measurement at all and was implemented only through plan4. plan4 contains no
   number of its own; it points to `results.md` ("The current implementation and measurements are in
   `results.md`", plan4 L286).
2. **plan4's implementation is GONE.** At commit c3709ad the tree held `au.lisp frames.lisp
   search.lisp sim.lisp syntax.lisp algebra.lisp guards.lisp symbolic.lisp grammar.lisp
   observations.lisp ...`; at a23e454 (30 Oct) those are replaced by `ast.lisp vm.lisp frame.lisp
   enumerate.lisp factor.lisp laws.lisp`. The owner's reason, in the commit message: "going to
   transition to a homoiconic kernel, rather than the bloated VM Astra designed." What survived the
   rewrite is the *contract* of plan3/plan4 (frame/row/pullback/message/ledger), not the code.
3. The four prompts are one text growing by accretion. P2 (19 Oct) is reproduced word for word
   as the lower half of Porig (L63-200) and of P4 (L88-226, re-titled "Original motivating sketch
   outline"). Checked by `diff`: Porig's and P4's lower halves differ only in the heading line,
   and plan2's quotation differs from Porig only by the typographic transliterations plan2
   declares. So the outline is still the owner's standing statement, not a superseded one.
4. plan3 has no embedded prompt. plan4 says it "Reorganizes prompt3 and plan3" (L5); no file
   named prompt3 exists in the history, so the owner prompt behind plan3 is presumably the
   `prompt.txt` of 20 Oct. Commit b5e6ccb (26 Oct) also changed 87 lines of plan3.md, so plan3 as
   it stands is not purely the 23 Oct text.

---

## 1. The original ambition

### 1.1 The goal, in the owner's words

- 14 Oct (P0, plan1 L16-18): "I'm looking to experiment with approaches to program synthesis using a
  combination of experimentation, simulator execution, and anti-unification in computed spaces."
- 19 Oct (P2, plan2 L51): "The goal of this research is to make a recursive program synthesis system."
- 26 Oct (Porig L7-8 = P4 L6-7): "This system takes output or input-output data, tagged by time
  and/or space, and iteratively and recursively derives a program, run on a fixed simulator with a
  growing library, which generates the data." and "The objective of the program synthesizer is thus
  to find a representation or compression of the data which minimizes the overall description
  length as well as metrics for computational cost, including the cost to search for the
  compression. The pricing mechanism for this will be a mix of fixed costs, information-theoretic
  estimates, and (of course, given the recursive nature) computed, bootstrapped metrics."
- What "pivotal" meant (P2, plan2 L173-183 = P4 L209-219): "Pivotal now is to show / Quotienting &
  AU under a simulator, with the right flexible datastructure and (graph-isomorphism) algorithm /
  yields algebra, solvers /  propagators, rewrite rules / Recursive program synthesis with residual
  / fiber targets / With allowance for unobserved inference (big question mark), / and optional
  heuristics for search, / Under a DL objective. / Recursive rule expression / Derived rules are
  themselves entries in the flat datastructure / Which means, as sketched above, that we need a
  means of organizing their use / triggering their execution / In a way that is _less expensive_
  than blind enumeration."

Note the phrase "with the right flexible datastructure and (graph-isomorphism) algorithm": the
owner flagged the data structure as the open question on 19 Oct, five weeks before V2P.

### 1.2 Requirement table

"P4 status" compares the first statement with `prompt4.md` as it stands (5 Nov): RESTATES (same
words), SHARPENS, CHANGES, or ABSENT. "V2P" notes how the current request treats it.

| # | requirement / intuition | first statement, verbatim | P4 status | V2P |
|---|---|---|---|---|
| A1 | Simulator execution is ground truth; search is unavoidable | Porig L10: "Search over computation is fundamentally unavoidable: the *a priori* shortest way to predict the **exact** effects of a computation is simply to do it.  Hence the simulator / computation engine + the supplied data are the ultimate sources of truth." | SHARPENS (P4 L10-11 adds "Execution, conditional input values and state, is similarly the ultimate source of equivalence ... Trick is to look for shortcuts!") | kept: "falling back to raw search, as needed and known" |
| A2 | Learn by experimenting on the simulator | P0 (plan1 L37-40): "Any given operator in the base language - take arithmetic, for example - can be run repeatedly on inputs while observing the output."; (L84-88) "with no knowledge of what a + b = c means, you can run many experiments with various a and b to see what results. This is a very tiny generative model." | RESTATES only in summary form (P4 L26 "Laws can be synthesized from ongoing interaction with the simulator.") | SHARPENS strongly: "telling you explicitly through experimentation (holding all but a few constant) what is related to what through computation" |
| A3 | Depth 2 experiments are essential | P0 (plan1 L86-88): "Then you do the same for all the other elementary operators in the toolbox, including negation, up to (say) depth=2 (this is essential!)." | ABSENT from P4 | RESTATES: "Algebra emerges from running parallel and depth >= 2 experiments on the simulator" |
| A4 | Reorientation: swap input and output, recurse | P0 (plan1 L44-49): "we should take the experimental outputs as direct targets (inputs) for a recursive call of the program synthesis pipeline, only with the input and output transposed."; (L82-84) "to learn algebraic operations, relabel one output as an input, and look for expressions that anti-unify the new expression with constant operators (I say anti-unification b/c you keep around symbols, not base values!)." | RESTATES (P4 L142-144: "Algebras ... allow for transformation of LHS of expressions to RHS and vice-versa / This enables exact conversion from inferred conserved quantities to generative expressions, / via the exchange of input and outputs.") | elevated to a design test: "reorientation (conservation and symmetries to generative expressions, or vice-versa when learning laws and propagators)" |
| A5 | Conserved quantities first, then algebra to a generator ("Noether") | P0 (plan1 L51-59): "This is "something like" Noether's theorem, albeit for discrete domains ... look for conserved quantities in the output or input-output pairing, then do algebra to convert this (possibly partly) acausal graph to a causal program." | RESTATES (P4 L13-14, adds "This constitutes inference of symmetry - equivalence under action.") | kept ("conservation (laws)") |
| A6 | Learn the propagation rules, do not hand-write them | Porig L14-16: "Learning the rules of this over a library + simulator is inspired by the work of [[FlashFill]] and FlashMeta, / Though here we will **learn** the propagation rules. / This is a more general form of backpropagation, adapted to discrete structures." | RESTATES (P4 L16-18) | SHARPENS into the bootstrapping complaint: "it's been the AI agents that are doing the majority of search and changing the code, not the kernel" |
| A7 | Withheld operators must be rediscovered | P0 (plan1 L93-96): "if we operate over GF(59), and subtraction is omitted, then a suitable inverse can still be found: c + 58a = b.  Showing that this can be inferred is a first step." | ABSENT (only "GF(p) but only at the start", P4 L222) | implicit in "derive algebras, propagators, laws, transformers, inverters" |
| A8 | Computation is projection; reversing it is a lift | P2 (plan2 L69-70 = P4 L105-106): "Topologically, computation may be seen as a projection, / In which case the reverse process requires a lift." | RESTATES | SHARPENS: "it's all lift, projection, fiber 'calculus', computation, substitution, conservation, and residuals" |
| A9 | Residuals are fibers; fibers carry information to a lifted space | P2 (plan2 L82-85 = P4 L118-121): "Most equivalences are approximate or partial, / And so require residuals. / The previous proposal indicates that these constitute the fibers of a projection (\*\*) / These fibers permit information flow to a lifted space." | RESTATES; Porig L34 = P4 L37 adds pillar 5c: "a pillar is to "unproject" or lift data with induced or introduced context, thereby forming fibers through which attribution can be traced." | CHANGES tone: "resulting in things like 'residuals' of frame becoming a bit clunky" |
| A10 | Lifting is what loops, calls and recursion need | Porig L28-33: "Computational compression requires re-use of programmatic structures: / Library calls, loops, recursion, / Often with guards / conditions. / This means a topological projection or loss-of-information during computation, e.g. the loop index or function calling context / Such variables are stored on the stack in typical environments.  In general they may be only weakly observed." Earlier, P0 (plan1 L104-108): "if observed symmetry indicates the presence of a loop, then that loop indexing variable is tagged onto (as in: list, tuple) the residual data, just like the time/space is tagged on to supplied input and output data." | RESTATES (P4 L30-37) | SHARPENS to a hard requirement: "**lift has to be a synthesizer primitive just like substitution is!**  Presently this is not true, it's wholly in the host lisp." |
| A11 | Information is measured in a fixed ambient space | P2 (plan2 L66-68 = P4 L102-104): "Information is "created" or "destroyed" by computation / This information (e.g. MI) has to be simply measured, with a fixed ambient space / correspondence. / Computation is not allowed here." | RESTATES | re-opened: "I'm not sure if there are better options for bootstrapping generated and intermediate spaces other than pricing in the original or ambient spaces.." |
| A12 | Residuals recurse: residual of one stage is the next stage's target | P0 (plan1 L102-104): "permit residuals and references in the conserved expressions, and let these be the targets for the next level of synthesis."; (L149-151) "At the limit, we have to permit bare residuals to permanently stay in the tree (bare facts, so to speak)." | SHARPENS (P4 L68: "emits new frames, residuals, or fiber indexes"; L69: "the full DL cost must be measured by the *full* path") | kept |
| A13 | Unobserved residuals must be inferred | P2 (plan2 L86-91 = P4 L122-127): "Some residuals cannot be a priori ordered (form a set), or cannot be otherwise observed, / Which means that they must be inferred. ... This can be as large of a problem as the program synthesis task / And so needs quotienting, partitioning, and computational description just like PS." Flagged "(big question mark)" at P4 L213. | RESTATES (P4 L35-36 adds the Sudoku EM pointer) | not mentioned |
| A14 | Description length is the objective | P0 (plan1 L125-127): "Critical is iterating over a model of the data with a MDL bound, and learning algebra and inverses from interaction."; P2 (plan2 L112): "The goal and final metric in all of this is description length (DL)." | SHARPENS (P4 L7: DL *plus* computational cost *plus* cost of search; "computed, bootstrapped metrics") | CHANGES: "being not at all strict about e.g. keeping the tarrifs similar" |
| A15 | Anti-unification is the primary route to abstraction, and it is contextual | P2 (plan2 L115-120): "Anti-unification (AU) is a symbolic means of quotienting, / One that allows for the introduction of new variables = abstractions. ... initially should be the primary means of introducing abstractions.  (Unless literature suggests otherwise (\*\*)) / Beta-expansion is another, but imho only supported where there is evidence; thence \~= AU."; Porig L37: "Anti-unification, like everything else here, is contextual, and depends on a frame or reference: *what* expressions are anti-unified into a LGG." | RESTATES (P4 L38-41, L151-156) | CHANGES: AU demoted to an instance - "really it's a form of quotienting and trivial lifting under substitution" |
| A16 | One flat, order-invariant store; rules live in it too | P2 (plan2 L121-124 = P4 L157-160): "This suggests that all data / experience should be in one 'flat' store. / A list.  In lisp. / It can be ordered by time (ordered execution), / but the algorithm should be largely invariant to this."; (L144-147) "it contains rules that rewrite expressions, / so contains data, functions, functors, and functionals, solvers..." | RESTATES | CHANGES: "re-expressed as a graph, hypergraph, or other datastructure" |
| A17 | The matching problem is graph-shaped | P0 (plan1 L21-25): "As a program can be represented as a DAG ... this process can be broken into sub-tasks of filling in holes in the graph (and possible re-representing the DAG or execution trace, but more on that later)."; P2 (plan2 L134-137): "This makes the quotienting-AU problem that of a structure & type-aware & locality-seeded subgraph isomorphism problem. ... The quotienting / AU problem is not *actually* graph isomorphism, just saying that we may be able to extract lessons from this literature." | RESTATES (P4 L170-173) | SHARPENS: the graph is now the store itself; "hypotheticalyl we'd need an efficient graph isomorphism test (not for AU of course), or e-graphs" |
| A18 | Locality seeds the search and can be bootstrapped | P0 (plan1 L25-28): "assume that both output and input (if provided) data are indexed by at least one axis, e.g. time or space.  This is important as search needs some initial essence of locality to reduce BFS."; Porig L42: "Locality can of course be bootstrapped: items that have a certificate for being co-local via search & computational validation can have induced locality (which, in turn, can be amortized / synthesized / explained through a subsequent synthesis step)." | SHARPENS a great deal (see 1.3) | SHARPENS: "proximity flows along verified topological links" |
| A19 | Partitions are frames; a conditional is a lift | Porig L45-46: "Partitions form frames for recursive program synthesis. / They are hence a straightforward form of lifting followed by a conditional." | SHARPENS (P4 L53: "a straightforward form of conditional-driven lifting"; L55-56: "Partitioning is a hard form of ordering, effectively selection with ha Heaviside function or Dirac delta ... Basically saying 'these are the same, and everything else is different'.") | SHARPENS: "A conditional is a partition: a disconnected region of space; here it's learned experimentally" |
| A20 | Space is allocated on the stack, not statically | Porig L47 = P4 L54: "Aside: deep learning does this in pre- and statically- allocated high-dimensional space; critical here is that space is allocated on the stack, in the search tree." | RESTATES | CHANGES / re-opened: "there could be good reason for keeping the vectors flat high-D, and just doing what a transformer does" |
| A21 | Heuristics are lossy equivalences whose residuals are discarded | P2 (plan2 L92-96): "Approximate equivalences \~= heuristics, / Which can be thought of as loose, lossy approximations to data. / They are essential in bootstrapping combinatorial search / provided the heuristic is easier to evaluate and infer than running many branches of a search tree. / In this case, the residuals are immaterial; the full branching search needs to recreate state, as the approximations only guide decisions." | SHARPENS (P4 L63-66: ranked by a "learned or ambient metric"; "anytime"; no decision-tree datastructure in the kernel) | SHARPENS: "policies that can be learned by reflection, instead of hard-coded" |
| A22 | Reflection: synthesize on the search's own graph | Porig L51-56: "The search procedure itself is a program which emits an oft-repetitive computational graph. / Synthesis can proceed on the search tree and execution graph itself to derive messages about in accessible regions of solution space. ... In SAT solving, these take the form of CDCL clauses, unique implication points, or dual implication points; the latter permits the introduction of new variables.  We aim to analogously replicate these powerful methods here." | SHARPENS (P4 L74: messages "strongly partition a given search problem -- even if they are not general to *all* problems, so only hold in the context of one problem") | RESTATES and names it: "Reflection means that the graph of operations of the search becomes available as data to the synthesizer itself" |
| A23 | Search must be factored to be tractable | Porig L60 = P4 L80: "Recursion through library learning + local messages serves to partition exponential to super-exponential search space such that it's tractable in linear time - which is all we get in the real world." | RESTATES | kept, with the budget correction (A30) |
| A24 | Library rules need cheap triggering (an addressing space) | P2 (plan2 L151-164): "amortization can be considered to form a type of semantic 'addressing space' over the learned rules, algebras, solvers. / In ML, this is a geometric space - continuous $\mathbb{R}^d$ - which enables self-organization. / In programming and human language, the space is expansive and compositional (e.g. docstrings, function names). / This makes it more of a topology than a geometry, / And so you could think of it as a graph over the graph of heterogenous experience data." | RESTATES | SHARPENS: "what is really needed is a hybrid geometry-topology engine" |
| A25 | Language: compositional labels as heuristics | P2 (plan2 L165-169): "A language enables compositional description of the labeled computation, / In a form that is shorter and cheaper than executing the function / rule / algorithm itself. / Thus it is a form of heuristic. / You can and should use the language to label the entries in the growing library." | SHARPENS: new pillar 9 (P4 L81-85): "the names of functions are short, easy-to decode, heuristic / approximate descriptions of what the functions do. Without them, libraries and code are un-navigable." and "it is not infinitely compositional like actual computer code, so that a fixed allocation of time or space is sufficient (like in a transformer)." | SHARPENS: "each word/atom modifies semantic meaning (which could be a 'like' term (proximity), an 'analogy' term (vector in some space), or 'action' (add a new space, do an operation between them)" |
| A26 | Geometry is deferred but must be afforded | P2 (plan2 L141-143): "Vocab and language may also induce their own geometry, / Or be embedded in a space with geometry, / Which can help search - though TBD."; (L170-172) "We don't need this self-organization yet - first the simulator-bootstrapped data and algorithm / but affordances should be made for its later addition. / E.g. potential bindings to linear algebra or ML libraries." | SHARPENS, hedged (see 1.3): "Geometry is not essential for this proposal, except ..." (P4 L62) | CHANGES: "We _must_ start with some bedrock of "these things are close" in addition to "these things are (topologically) connected"." |
| A27 | Richer data structures by computed addressing | P0 (plan1 L162-165): "Among many others are the need to induce datastructures more complex than bare variables; I surmise this can be handled through computed and algebraic addressing schemes on lifted/augmented data, but that remains to be determined" | RESTATES as "computed lifting, or computed addressing. (\*\*)" (P4 L134) | subsumed: "Making a tuple is an explicit example of instantiating a connection or edge, albeit one with coordinates." |
| A28 | Errors exist | P2 (plan2 L59-62): "Ability to execute those expressions / Over the domains / Over the expressions / (Which my yield errors)" | RESTATES (P4 L95-98) | SHARPENS: "support learning them by tolerating crashing or non-terminating behavior, and assembling guards for them" |
| A29 | The simulator may one day be the stateful world | P2 (plan2 L72-75): "Execution here is on a simulator / the lisp machine / but, in general, it may be external: the real world. / Which has state and is very much not functional." | RESTATES | not mentioned |
| A30 | Start minimal; plan before code | P0 (plan1 L178-179): "Goal is to start as absolutely minimally as possible, and be very deliberate; do not implement code without letting me read a plan." | ABSENT | CHANGES: "a very critical oversight in the work so far is that the budged for search was very limited, where we realisically should tolerate hours of search" |
| A31 | E-graphs / version spaces may be worth their weight | P0 (plan1 L170-172): "it may be advantageous to use a e-graph or version space to exploit learned symmetries and equivalence rewrite rules; these are a heavy import that nonetheless may be worthwhile." | RESTATES as a pointer (P4 L184-186) | ambivalent: e-graphs named as possibly needed, yet "too much technical and scientific risk through unverified or academic imports" |
| A32 | Linear algebra is out of scope (but will be needed) | P2 meta (plan2 L42-45): "Don't pay attention to the symbolic regression experiments. / That proved that, to do a minimal 'program synthesis' task you very much need linear algebra, / from which Gauss-Jordan is built. / Discovering or building in linear algebra and the trove of learned and found algorithms is _out of scope_ for this document / planned experiments." | ABSENT as an instruction (P4 L208 keeps only "potential bindings to linear algebra or ML libraries") | reversed in ambition: "inverters (like autocorrelation) and higher-order functors" are now things to *derive* |
| A33 | Parallel search | P2 (plan2 L140): "This search is also highly amenable to parallelization." | RESTATES (P4 L176) | CHANGES: "switching to multi-threaded operation is alas not within scope, it's orthogonal to the design" |

Non-negotiables the coordinator asked about that are **not** owner statements in these documents:

- *Homoiconicity.* The word never appears in a prompt. The owner's version is "A list.  In lisp."
  (P4 L158), "Derived rules are themselves entries in the flat datastructure" (P4 L217), "Ability to
  execute those expressions / Over the domains / Over the expressions" (P4 L95-97), and the commit
  message of 29 Oct ("going to transition to a homoiconic kernel"). It is an owner decision, taken
  between plan4 and plan5, recorded only in git.
- *No host eval.* This is [AI] text, added to plan4 on 28-29 Oct: "Supply structural inspection,
  matching, substitution, and construction primitives, without `eval` or host callbacks." (plan4
  L262-264). The owner's prompts say only "run on a fixed simulator with a growing library".

### 1.3 What `prompt4.md` adds: the first appearance of geometry (4-5 Nov)

The only substantive change between Porig and P4 is the rewriting of pillar 7 (`git diff 4428061
d5cf69f`, then `d5cf69f b37fb35`) and the new pillar 9. Pillar 7 grows from 9 lines to 25. New
owner text, all verbatim from P4:

- L42: the things to decide now include what to "segment and co-lift, or build a library from, or
  look to unify through a conserved executable description."
- L43-44: "data that is close in time or space, or close in a constructed / learned space. /
  Spaces can extend to even abstract concepts, like 'colonies' or 'mountain passes', wherein
  similarity and hence locality is purely computational."
- L45-46: "Segmentation often tries to be a max-cut." and "abstract locality helps to transform
  computable attributes, like arithmetic in a constructed space."
- L47-48: co-locality certificates "(beyond supplied data: from search, comparison, or
  computational validation)"; "Or, vice-versa, locality can be imposed (via selection and sorting),
  and equivalence checked."
- L51: "Here similarity is typically exact and structural, though human cognition also softly
  treats these as invented & analogical spaces."
- L57-62: "A **relaxed** form of partitioning involves ordering and sorting, and learned metrics: /
  Each which says, effectively, 'these are this-much similar, and other things are that-much
  dissimilar'. / Metrics allow for sample-based approximation and generalization, as is common in
  machine learning (and learning or approximation in general!) / They enable a related form of
  conservation, beyond equivalence: change is bounded for a map y = f(x) in both x and y / This
  means both input and output need a geometry / Geometry is not essential for this proposal,
  except ..."
- L63-66: "when deriving heuristics, we have to accomidate lossy and imperfect compressions and
  approximations, hence need a way of ranking them. / Much of perception is seeking entities,
  attributes, and functions that are conserved through time or space.  Heuristics couple tightly
  to this, as they approximate data where the residual (and hence the residual) is measured with a
  learned or ambient metric.  This metric (or metrics) enables judging whether a given
  computational or DL compression fits supplied data. / Heuristics can also be "anytime"
  algorithms - more compute yields greater accuracy. This extends to e.g. decsion trees / But this
  does not need we need a decision tree datastructure in the kernel!  Should be subsumed by other
  primitives."

Reading: by 5 Nov the owner already held (i) partition = hard limit of a metric relation, (ii) a
Lipschitz-like "conservation beyond equivalence", (iii) residuals of heuristics priced by "a learned
or ambient metric", and (iv) spaces that are constructed. V2P's geometry half is this passage with
the hedge removed. The sentence that trails off at L62 ("Geometry is not essential for this
proposal, except ...") is the exact point where the earlier position and the current one part.
The kernel's one explicit metric today is the frame's `metric` slot ("the bits it takes to correct
a predicted value 0 to the value 1", `frame.lisp:16-18`, STILL-IN-CODE); it entered `frame.lisp`
on 16 Nov (commits fb9d970 / 2484d19), after this passage, and reads as its implementation -
an inference from dates, not something a document here states. `:locality-key` entries
(`proposals.lisp:625`) and `:persistence` edges (`frame.lisp:22-23`) are the other traces of
induced neighbourhood.

### 1.4 Net reading of the ambition against V2P

Constant from 14 Oct to 24 Nov: simulator as truth; experiments including depth 2; reorientation;
projection/lift/fiber/residual vocabulary; DL plus work as price; reflection on the search graph;
language as compositional heuristic addressing; the kernel must learn its own propagation rules.

Changed by the owner: the store (flat list to graph/hypergraph); AU (primary mechanism to one
instance of quotient-and-lift); geometry (deferred "TBD" to co-equal bedrock); budget ("absolutely
minimally" to hours); space allocation (stack only, now re-opened); tolerance for imports (e-graphs
"may be worthwhile" to wariness of "unverified or academic imports").

Never delivered at any stage covered here: learned (as opposed to supplied) lift, view, matching,
isolation, and experiment design; the withheld-operator bootstrap beyond addition; anything
geometric; the language component.

---

## 2. Idea ledger, chronological

Status vocabulary for the documents: **PY-CHECKED** (a number from an uncommitted python scratch
script; treat as a claim), **PROPOSED** (never built in the plan that proposed it), **SUPERSEDED-BY**.
Code tags as defined above. **FLAG** marks an idea dropped or weakened for convenience or caution
rather than because a measurement said so.

### 2.1 plan1 (14 Oct) - "program synthesis from conserved quantities, lifts, and learned inverses"

| # | idea (where) | status in documents | current code |
|---|---|---|---|
| 1 | **Frame = a table**: rows carry index tags; columns are *given* or *coded*; rows grouped into examples; each frame records its lineage `:data :transpose :lift E :reindex sigma :group-by E :join` (plan1 §1.2 L266-275). This is where the frame was born, and it was born as a relation with a derivation history. | SUPERSEDED-BY plan2 #31 (frame = AU substitution table), then plan3 #53 | ALTERED: `row (key known requirement)`, `frame (schema rows pairs anchors metric edges)` at `frame.lisp:7-24`. Lineage slot GONE (0 hits for `lineage`). |
| 2 | Relative references `(@ x k)`, k in {0,-1,-2}, as the built-in form of locality (§1.3 L297-299) | PROPOSED | NEVER-BUILT as a leaf. An absolute `:at` indexing operator exists (`ast.lisp:139`); locality is now a library kind `:locality-key` (`proposals.lisp:625`) plus `induce-row-order` (`proposals.lisp:707`). |
| 3 | Depth-2 "computational expansion", value vectors, hash **buckets** = observational equivalence; one representative per bucket builds larger terms; every collision recorded as a candidate equation (§1.4 L314-325, §7.1-7.2) | PY-CHECKED (17 399 raw / 6 754 classes) | ALTERED: size-bounded enumeration (`enumerate.lisp:131`), `observation-bucket` (`enumerate.lisp:604`), `classify-observation-bucket` (`enumerate.lisp:731`), `propose-observed-laws` (`laws.lisp:215`). |
| 4 | **Null frame** (coded columns replaced by iid uniform draws over D) to separate laws of the operators from facts about the data (§1.4 L327-330) | PY-CHECKED (0 of 120 random sequences accepted anything) | NEVER-BUILT (0 hits). The bucket flags `invariant-p informative-p` (`enumerate.lisp:604`) do a related job. |
| 5 | One engine, three findings: explicit generator / conserved quantity / implicit equation / partial finding, all "level sets of a short expression" (§0 claim 1, §1.5) | PY-CHECKED on toy sequences | ALTERED: requirements are Boolean predicates; `conserved-quantity-frame` (`frame.lisp:1303`), `orient-conserved-quantity` (`laws.lisp:931`). |
| 6 | **Fiber code**: bits saved = sum over rows of log2\|D\| - log2\|F_r\|; DL(X) = header + sum DL(phi) + sum log2\|F_r(Phi)\|; "No syntactic triviality filter is needed" (§0 claim 2, §1.6 L352-364) | PY-CHECKED; kept by plan2 ("unchanged"); SUPERSEDED-BY plan3 #57 (predicate pullback, fibers optional) | NEVER-BUILT in this form (0 hits for `log2`/`fiber-size`). Residuals are priced as packets through the bit codec. |
| 7 | Program = nested frames, each a decision list of guarded findings + lifts + bare facts; accepted only after forward execution reproduces the data (§1.7 L371-383) | PROPOSED | ALTERED: replay verification is everywhere; a "greedy MDL decision-list induction" appears in `synthesize-boolean-separator` (`consolidate.lisp:1248-1250`). |
| 8 | Design principle: "Every symbolic shortcut has an enumeration fallback over a finite domain, and the fallback's results are the training data for the shortcut. Enumeration teaches the algebra." (L235-237) | PROPOSED; restated by plan3 as the predicate fallback | In spirit STILL-IN-CODE (propagation keeps the original predicate as `fallback`, `laws.lisp:448`). |
| 9 | Algebra by **transposition**: run an operator table, swap one argument with the result, rerun the same pipeline (§2 "outer loop" L422-427, §6.3) | PY-CHECKED for GF(p) `+`; SUPERSEDED-BY plan2 #34 then plan3 #56 | ALTERED: `milestones/algebra-discovery.lisp` (reoriented requirement R(k,c,z), L27-35); transition reorientation `frame.lisp:367`. |
| 10 | Solve-rule record `(solve (+ ?a ?b) :for ?b :result ?c :inverse ... :guard t :fiber 1 :domain (gf 59) :verified :exhaustive)` (§6.3 L929-935) | PROPOSED | ALTERED: `arithmetic-propagator (operator position witness guard inputs context-map ...)` (`laws.lisp:451`); `:solver` kind (`laws.lisp:1337`). The `:fiber` size field is GONE; `solver-set-valued-p` (`laws.lisp:633`) is the remnant. |
| 11 | Typed holes `?k` fitted to data: by enumerating the hole's domain in the bootstrap, by isolation once solve rules exist (§5.3 L644-653) | PY-CHECKED as a need (58 unreachable from {0,1,2}) | NEVER-BUILT as constant fitting; literals are enumerated as syntax. |
| 12 | Guards and covers after EUSolver, with splits chosen by bits saved; guards may read only tags and already-decoded values (§5.4 L655-682) | PROPOSED | ALTERED: guards learned as Boolean child frames (`tests/milestones/guards.lisp:21-251`); availability rule at `ast.lisp:418`. |
| 13 | Three meanings of anti-unification: (i) relative reference across rows, (ii) varying constant = value-vector lift, (iii) Plotkin LGG across instances that cannot share a value vector (§5.5 L686-708) | PROPOSED; (iii) PY-CHECKED in plan2 | (iii) STILL-IN-CODE `anti-unify` (`unify.lisp:36`). |
| 14 | "LGG is syntactic, so it needs canonical forms"; orient learned laws first; AU modulo a theory (babble) deferred (§5.5 L710-714) | PROPOSED; becomes the recurring problem R2 | `normalize-trees-with-library` (`abstraction.lisp:7`). |
| 15 | **Lift by an injective expression E**: child frame v = E on the same tags; try lifts best-first by DL(E), "Do not rank lifts by how small the lifted values are"; memoize children by content (§2 step 3, §5.6, §7.4) | PY-CHECKED on cubes / fourth powers; SUPERSEDED-BY plan3 #57 | ALTERED: `lift-frame` (`frame.lisp:1194`), `pullback-frame` (`frame.lisp:544`), `child-scope-signature` (`synthesize.lisp:264`). |
| 16 | Lossy lift: a non-injective E adds its fiber index as a second child (§5.6 L733-734) | "Deferred." Never returned to. **FLAG** | NEVER-BUILT as stated. |
| 17 | **Six frame operators** - select, extend, re-index, group-by, join, lift - "Frames are relations, and a new data structure is a new frame made by one of six operators, each a target for a recursive call" (§5.7 L741-751). "This is the least worked-out part of the plan." (L763) | PROPOSED; SUPERSEDED-BY plan2 #33, plan3 "view programs" | PARTIAL: `partition-rows` (`frame.lisp:1419`), `quotient-values` (`frame.lisp:1443`), `induce-row-order`; re-index and value-join as general operators NEVER-BUILT. |
| 18 | "Meet in the middle" correspondence: backward set of each output row vs. forward index expressions; rare rows decide (§3.9, §5.8) | By hand in plan1; PY-CHECKED in plan2 §4.7 | ALTERED: set-valued row requirements. |
| 19 | Knowledge levels 0-3; **level 2 (isolation and collection, i.e. the reorientation engine itself) is "given and small"**: "Level 2 could also be learned, but it is about forty lines and generic." (§5.9 L809-819) | **FLAG: dropped for convenience.** The meta-level was declared host code on day one. | `solve-equality-symbolically` (`laws.lisp:809`) is host code. |
| 20 | Symmetry = pair (sigma, tau) with x(sigma(i)) = tau(x(i)); "Which expressions are invariants of which transformations is itself a family of laws, E(Ta, Tb) = E(a, b), which the experiment loop can learn." (§5.10 L823-842) | "open; optional in M1"; reduced in plan4 M2 to one planted invariant | Partly: transition probes (`frame.lisp:367`). The learnable invariance-law family NEVER-BUILT. |
| 21 | Laws hold per domain; every rule records domain and how verified (§5.11) | Kept through plan4 ("replayed / exhaustive / proof", L216) | STILL-IN-CODE: `law-validation` certificates (`laws.lisp:55-59`); `truncating-division-does-not-transfer-field-identities` (`tests/laws.lisp:243`). |
| 22 | Identifiability: where an operator loses information, the transposed generator holds on a subset and "the guard learned for that subset is the region where the operator is identifiable" (§5.12 L853-859) | PY-CHECKED in plan2 §1.1 (fiber profile of transposed `*`) | STILL-IN-CODE in effect (`zero-empty-and-multivalued-fibers-remain-predicates`, `tests/milestones/algebra.lisp:75`). |
| 23 | Greedy acceptance by marginal net bits with fiber intersection (§5.13) | PROPOSED | not found. |
| 24 | Group findings by the continuation they predict ("dedupe by prediction, not by program") (§5.2) | PY-CHECKED (57 variants of one finding) | NEVER-BUILT (0 hits). |
| 25 | Laws after QuickSpec/Ruler from collisions on a grid with nothing coded; three uses: canonical forms for AU, pruning the expansion, collection during isolation (§6.2) | PY-CHECKED for use 2 only ("commutativity removes a third of the raw evaluations but no classes") | STILL-IN-CODE: `propose-observed-laws` (`laws.lisp:215`), `rewrite-filter-step` (`enumerate.lisp:472`). |
| 26 | Rules about rules: anti-unify the per-prime solve rules, lift the hole to a child frame keyed by p, find `?K = p - 1` (§3.8, §6.4) | By hand in plan1; PY-CHECKED in plan2 §4.2; "mechanism control" in plan4 8A | ALTERED: `retype-law` (`templates.lisp:524`), `lift-field-solvers` (`consolidate.lisp:603`). |
| 27 | **Tabled operator**: when no inverse exists at depth 2 (GF(p) `*`, p >= 7), cover by partial generators `(* k c)`, anti-unify to `(* ?k c)`, lift `a -> ?k`, keep the 58-entry table as a new operator `inv` (§3.7 L525-538) | PY-CHECKED in plan2 §4.3; dropped by plan3 L601; replaced in plan4 by supplying division. **FLAG** | NEVER-BUILT. `field-reciprocal`: "Extended Euclid inside the supplied division primitive, not learned inversion." (`vm.lisp:162-163`). |
| 28 | E-graph deferred behind three measurable triggers; "The buckets already are the version space of a frame"; "In Lisp a minimal e-graph (hash-consing, union-find and rebuilding) is a few hundred lines, not a heavy import." (§7.6 L1016-1031) | PROPOSED; trigger (b) effectively fired in plan2's own check and was patched instead | NEVER-BUILT. Nearest thing: `congruence-close-code-evals` (`frame.lisp:975`). |
| 29 | Bounds, dominance, subsumption after Stitch (§7.3) | PROPOSED | not checked. |
| 30 | Provenance records so that "every predicted value can be traced to the finding and the rows that fixed it" (§7.5) | PROPOSED | ALTERED: `explain.lisp`, `synthesis-node` (`synthesize.lisp:19`). |
| 31 | Falsifiable baseline: lift search vs. plain enumeration at equal wall time - "If the lift search does not solve strictly more problems, the claim fails in 1D, and that is reported." (§9 "M3's baseline") | PROPOSED; restated in plan2 M2, plan3 §7.2, plan4 8A. **No result for it appears in any of these documents.** | - |

### 2.2 plan2 (19 Oct) - "recursive program synthesis by quotienting one flat store"

| # | idea (where) | status in documents | current code |
|---|---|---|---|
| 32 | **Flat store** of seven-field entries `(id type tags body prov label stats)`, one entry per observation or execution; derived indexes by type, skeleton, atom, tag, fingerprint; results independent of list order (§2.1 L709-748) | PROPOSED. Dropped by plan3 L86 without a measurement. **FLAG** | NEVER-BUILT for observations. Survives for knowledge only: "one flat, append-ordered list of typed entries with relational edges" (`knowledge.lisp:3-5`). |
| 33 | **Frames are built, not given**: anti-unify *connected* entries (tag relation or shared value); the pattern is a conjunctive query, its table of substitutions is the frame (§0, §2.4 L790-811); "Frames are then built by AU and never given" (L736) | PY-CHECKED only for grouping by type + skeleton (7 690 entries into 10 frames). SUPERSEDED-BY plan3 #53/#54 (declared frames, view programs). **FLAG** | NEVER-BUILT. Frames are constructed by drivers and tests. |
| 34 | All-directions relation search: "No column is designated as input or output. All directions are searched, and the solve rules are the directions other than the one in which the data were produced." (§2.5 item 3, L835-837) | PY-CHECKED (§4.1) | ALTERED: orientation is chosen per frame (`orient-available`, `frame.lisp:1365`); `all-arithmetic-orientations-match-independent-field-reference` (`tests/milestones/algebra.lisp:23`). |
| 35 | Five quotient structures of a frame: constant, shared variable, functional relation, partition, ordering (§1.3 L406-412, §2.5) | PROPOSED | PARTIAL, scattered over `fibers.lisp`, `frame.lisp:1417-1500`, `proposals.lisp:632-810`. |
| 36 | Ordering as a latent successor, "searched as a sort key or as a chain of a functional relation, never as a permutation"; "Constants and orderings are duals" (§1.3 L414-423) | PROPOSED | STILL-IN-CODE in altered form: `induce-row-order` (`proposals.lisp:707`), `:persistence` edges (`frame.lisp:22-23`). |
| 37 | Residual taxonomy: exact set-valued (fiber index) / partial (mask or synthesized guard) / approximate ("an error under a non-uniform code, which needs an order or a metric on D") (§1.2 L368-375) | PROPOSED | The metric case is `frame-metric` (`frame.lisp:16-18`). |
| 38 | Condition: "Fiber coordinates come from the ambient space" (§1.2 L384-387) | PY-CHECKED (asserted) | not checkable by grep. |
| 39 | Set-valued targets / backward sets; "the rare rows decide" (§1.2 L388-396, §4.7) | PY-CHECKED: 19 205 index expressions cut to 39 (reverse) and 8 (rotate) by 4-5 singleton rows | ALTERED (requirement predicates). Rarity ordering NEVER-BUILT (0 hits for `rare`). |
| 40 | Observable vs. latent residuals; **votes, hard EM, describe the label column, price it** (§1.3 L426-449, §7) | PY-CHECKED (GF(251) switch) | Built later: "Hard-EM fiber clustering & linkage extraction" (`package.lisp:122`), `infer-fibers` (`fibers.lisp:156`), `tests/lifting.lisp:19-187`. |
| 41 | **Three DL accounts**: data (fiber code), library (charged once), derivations ("bits of work", Levin Kt) (§1.5 L473-515, §2.7) | PROPOSED; SUPERSEDED-BY plan3 #65, which rejects the log-rank code | ALTERED: `ledger` (`vm.lisp:10`), `*search-weight*` 1/1024 (`consolidate.lisp:415`). |
| 42 | Laws come from **designed experiments that share inputs**, plus universal validation; they cannot come from compressing observations (§1.4 L464-471, §4.4) | PY-CHECKED | STILL-IN-CODE in effect: an `observation-scope` freezes one set of rows and every candidate is evaluated on those same rows (`enumerate.lisp:564-573`). |
| 43 | Propagator model (Sussman/Radul): cells hold fibers, later intervals; a relation propagates in every direction it has a solve rule for (§1.6 L530-538); interval propagators learned on a lifted domain (M5) | PROPOSED | PARTIAL: `propagate-requirements` (`laws.lisp:736`). Interval propagators NEVER-BUILT. |
| 44 | **Anti-unify equivalence classes (buckets), not representatives** - "babble's anti-unification over e-graphs in miniature" (§1.7 L569-579, §4.3) | PY-CHECKED (representative AU gives a bare variable) | ALTERED: bounded alternate syntax (`abstraction-validated-law-alternate-syntax`, `tests/milestones/corpus.lisp:330`). |
| 45 | Explanation-based generalization and chunking for macro rules from stored derivations (§1.7 L580-586, §4.10, §6.3) | PROPOSED | NEVER-BUILT (0 hits). |
| 46 | Matching = conjunctive queries / theta-subsumption; restricted to "patterns of at most three templates, acyclic, joined by tag constraints with offsets of at most 2 or by values (rarest first)" (§1.8 L608-641) | PROPOSED | NEVER-BUILT. |
| 47 | Two kinds of address: structural (discrimination trees, Rete) and behavioral (fingerprint = "a hash ... much like a linear code") (§1.9 L653-666, §6.1) | PROPOSED | Discrimination tree / Rete NEVER-BUILT (0 hits). Solver dispatch is by typed structural matching (`propagator-rules-for`, `laws.lisp:658`). |
| 48 | Symbolic labels (signature, domain, laws satisfied, fiber profile, use count); "The graph over the graph is the set of links between entries (derived from, generalizes, inverse of, used with), stored as entries." (§1.9 L668-674) | PROPOSED | ALTERED: knowledge "relational edges" (`knowledge.lisp:4`); `:descriptor` kind (`descriptors.lisp:175`). |
| 49 | Utility U(R) = work saved - matching work; negative-utility rules are demoted from the index, never deleted (§6.2 L1132-1140) | PROPOSED | STILL-IN-CODE in altered form: `amortize-library-entries`, `:net-utility`, `:stale-epochs` (`consolidate.lisp:466-512`), `*archive-epochs*` (`consolidate.lisp:418`). |
| 50 | Heuristics = property-signature orderings; "Nothing is pruned"; value = reduction in sum log2(rank) minus the work of computing it (§1.5 L503-508, §6.4) | PROPOSED; SUPERSEDED-BY plan3 #66 | ALTERED: `condense.lisp`, `:heuristic` kind (`consolidate.lisp:237`). |
| 51 | Expressions as values with `eval`, `match`, `inst`, "so rules are expressions over expressions" (§1.10 L700-703) | PROPOSED; becomes plan4 #73 | STILL-IN-CODE: `:code-match`, `:code-subst`, `:code-eval` (`ast.lisp:134-144`). |
| 52 | "errors are data, and guards are learned from them" (§2.2 L763-764) | PROPOSED; realized in plan4 #74 | STILL-IN-CODE (`tests/milestones/guards.lisp`). |
| 53a | Affordances: simulator behind a protocol with optional state (hidden state = causal states); foreign numeric primitives; "an index protocol (`add`, `query`); an embedding index is one more index"; parallel seeds (§8 L1192-1200) | PROPOSED | All NEVER-BUILT (0 hits for stateful / foreign / embedding / thread). |
| 53b | The round: seed (locality, then rare values) - grow - quotient - accept - emit (§3.1 L887-900) | PROPOSED | NEVER-BUILT. |

### 2.3 plan3 (22-23 Oct) - "a small recursive synthesizer that can learn how to search"

| # | idea (where) | status in documents | current code |
|---|---|---|---|
| 54 | Representation / Construction / Control separation: "All three can use tagged S-expressions. They do not thereby acquire the same semantics." (L14-20) | adopted | - |
| 55 | The prior is declared: "These mechanisms are prior knowledge. Listing them is more informative than claiming a knowledge-free learner. Every new handwritten primitive or proposal shortcut must join this list." (§1 L38) | adopted in plan3/4; not checked afterwards | no such list in code. |
| 56 | **Frame = (schema, rows); Row = (key, known, allowed)**: "A frame is a typed relation with a chosen prediction direction."; allowed set = explicit values or an executable predicate; tuple targets keep joint assignments; whole tables are values (§2 L46-76) | adopted; restated as "The only data frame" in plan4 L116 | STILL-IN-CODE as the core (`frame.lisp:7-13`), now with four extra slots. |
| 57 | View program, derivation record, search record live outside the frame: "The core algorithm should not require every row to carry a query plan, uncertainty model, search score, proof status, and provenance graph." (L78-86) | adopted | ALTERED: `pairs anchors metric edges` are now on the frame (`frame.lisp:14-24`). |
| 58 | Child inheritance "is therefore a projection with a contract, not a copy of every attribute"; no informational loops; availability starts at the call boundary (§2.1-2.2 L88-120) | adopted | STILL-IN-CODE: availability preorder (`ast.lisp:12-19`), `expression-respects-availability-p` (`ast.lisp:418`). |
| 59 | **Reorientation as a change of roles**, no rerun, no copy, no extra compression credit; "reorientation for invention" vs. "decomposition of an existing goal" (§2.2 L98-112) | adopted | STILL-IN-CODE in spirit (`frame.lisp:367`, `frame.lisp:1303`). |
| 60 | **Residual defined by a reconstruction program: the predicate pullback** B_i(z) <=> A_i(d(c_i, z)), forward execution only; "Explicit finite fibers remain an optional representation and a useful test oracle." (§3 L122-148) | adopted | STILL-IN-CODE: `pullback-frame` (`frame.lisp:544`), `lift-frame` (`frame.lisp:1194`), `compose-lifted-model` (`frame.lisp:1273`). |
| 61 | **AU is a decomposition**: "Pattern instantiation is the decoder. The substitutions become the child targets." Uniform `(app operator arguments)` gives operator holes without higher-order unification (§3.1 L166-194) | adopted | STILL-IN-CODE: `anti-unify ... :operator-holes-p` (`unify.lisp:36`), `compile-au-constructor` (`unify.lisp:103`). |
| 62 | Fixed syntactic AU kernel + a bounded collection of equivalent alternative syntax (§3.2) | adopted | STILL-IN-CODE (see #44). |
| 63 | Views vs. partitions vs. quotients; lossless quotient (representative + residual) vs. lossy quotient (heuristic state only) (§4 L206-220) | adopted | STILL-IN-CODE: `quotient-values`, `restore-quotient`, `partition-model` (`frame.lisp:1443-1473`). |
| 64 | One recursive obligation ("Propose a decoder, construct its child requirement, solve that requirement, and check the composition."), resumable metered jobs, literal fallback (§5 L224-257) | adopted | STILL-IN-CODE: `resume-search` (`enumerate.lisp:558`), `row-job` (`enumerate.lisp:231`), `with-work-limit` (`vm.lisp:20`). |
| 65 | Fair canonical reserve: "allocate every fourth work quantum to it" (§5.2 L294) | adopted | ALTERED: "a 3:1 locality-to-canonical contiguous window" in row selection (`frame.lisp:1041`); `view-locality-scheduling-and-canonical-reserve` (`tests/milestones/views.lisp:249`). |
| 66 | **Message = (call-id, claim, evidence)** with a table of what each claim licenses (§5.3 L298-326) | adopted | STILL-IN-CODE, literally: `(defstruct message call-id claim evidence)` (`enumerate.lisp:219`); `messages.lisp`. |
| 67 | Checked structural conflicts routed to the responsible decision (pair(z,z); one constant per part) (§5.3 L322, §9.5) | PROPOSED ("later gate") | ALTERED and extended: `nogoods.lisp` ("Deductive leaf nogoods, UIP generalization & DIP context repair", `package.lisp:210`). |
| 68 | Cost as S (bytes of canonical S-expressions), W_run, W_search with declared lambdas; "No logarithm of a choice rank is treated as a valid code without an actual decodable coding scheme." (§6 L334-370) | adopted; bytes replaced by bits within four days (commit 7446706) | ALTERED: bit codec (`codec.lisp`), tariff (`vm.lisp:7`). |
| 69 | Search-preference learning ladder: fixed-quantum actions; lossy features phi(s); telescoping reward r_t; continuation return G_t; shrunk table; then a synthesized piecewise-constant policy trained as "heuristic prediction plus literal error" (§8 L420-535) | PROPOSED (milestone 3) | Shrunk table NEVER-BUILT (0 hits for kappa/shrink/incumbent). Synthesized heuristic built later: `make-search-trace-frame` (`consolidate.lisp:20`), `condense-search-heuristic` (`consolidate.lisp:95`). **FLAG: the baseline the plan said to establish first was skipped.** |
| 70 | Staged planted-factorization controls: replay, match, aligned AU, find occurrences, semantic variants (§9.2) | adopted | STILL-IN-CODE as tests (`tests/milestones/corpus.lisp:181-330`). |
| 71 | Backtracking / GC roots / cache keys that include bounds (§9.4) | PROPOSED | PARTIAL (`reused-from`, `synthesize.lisp:22`); eviction not found. |
| 72 | "The first deliverable": one human-readable transcript (§12) | adopted | `explain.lisp`. |

### 2.4 plan4 (26-29 Oct) - "nine research pillars, one small synthesis kernel"

| # | idea (where) | status in documents | current code |
|---|---|---|---|
| 73 | **Symbolic VM gate**: quoted typed expressions as ordinary frame values; inspection, matching, substitution, construction primitives "without `eval` or host callbacks"; "Lower AU templates and checked rewrite directions to DSL programs on those values." (L261-270) | built in the discarded VM (`symbolic.lisp` present at commit cd68027; owner's commit 739a852: "AU enabled, term rewriting now built into the DSL.."; numbers in results.md, not read) | STILL-IN-CODE in the successor: `:code-*` operators (`ast.lisp:134-144`), `compile-rule-transformer` (`laws.lisp:284`). |
| 74 | **Learned definedness and guards**: "Execute each operator on a declared input grid, retaining both values and errors. Learn its definedness predicate through the existing Boolean synthesis path."; solve candidates keep their "non-error, successful subset"; the guard is a Boolean child frame (M4, L288-306) | built in the discarded VM (`algebra.lisp`, `guards.lisp` at cd68027; numbers in results.md, not read) | STILL-IN-CODE: `arithmetic-definedness` (`milestones/algebra-discovery.lisp:21`), `tests/milestones/guards.lisp`. |
| 75 | Two-statement certification before a predicate may be replaced by a singleton: (i) under the guard, q satisfies the relation; (ii) the relation is equivalent to z = q for every z (L316-324) | built in the discarded VM (as above) | STILL-IN-CODE: `solve-discovery ... validation uniqueness` (`milestones/algebra-discovery.lisp:8-9`); `certified-propagators-preserve-entire-field-child-frames` (`tests/milestones/algebra.lisp:110`). |
| 76 | Scope change of 28 Oct: "The main eight-orientation experiment explicitly admits subtraction and division as candidate primitives." "The richer grammar learns how to use division; it does not learn the primitive's implementation of modular reciprocals." (L308-314) | **FLAG: the handicap of requirement A7 was relaxed for tractability.** The `+`/`*`-only bootstrap is kept as "a separate unseeded control" for addition only. | `original-addition-bootstrap-and-separate-oracle` (`tests/milestones/algebra.lisp:57`). |
| 77 | Solver triggering by typed structural matching against the proposed decoder: "This is a supplied matching mechanism over learned rules; learning retrieval descriptions or a selection policy remains outside milestone 4." (L345-353) | built as supplied. **FLAG** | STILL-IN-CODE: `propagator-rules-for` (`laws.lisp:658`). |
| 78 | Planted invariant under a supplied transition: T(a,b) = (a+1, b+4) in GF(5), find h = a+b (M2, L243-249) | built in the discarded VM (`observations.lisp` at cd68027; results.md not read) | ALTERED: `conserved-quantity-frame`. |
| 79 | Law proposal from output buckets, exhaustive check, mandatory non-transfer control (x^5 = x holds in GF(5), must fail in GF(7) and Z) (M3, L255-257) | built in the discarded VM (`laws.lisp`, `law-experiments.lisp` at cd68027; results.md not read) | STILL-IN-CODE: `tests/laws.lisp:107`. |
| 80 | Supplied lift: y_{j,t} = a_j + iota(t), with the map r -> j and the decoder supplied; "This tests a supplied lift before milestone 7 searches for one." (M5, L372-384) | PROPOSED at the time; "Hard EM is deferred until a bounded context search demonstrably needs it." | fixture at `tests/support.lisp:659`; `tests/lifting.lisp:220`. |
| 81 | View discovery over "a tiny published grammar of equality keys, simple guards, and orderings"; "Supply a correct view first; then search" (M7, L416-426) | PROPOSED | STILL-IN-CODE: `milestones/views.lisp`, `tests/milestones/views.lisp:86`. |
| 82 | Vocabulary experiment: opaque IDs; learn "a tiny descriptor/ranking program from existing types, checked properties, and cheap behavioral probes"; random renaming control; must beat type/probe indexing in total work (M9, L509-523) | PROPOSED | `descriptors.lisp` (1045 lines, `:descriptor` kind L175) exists; whether it implements this experiment was not audited. No `rank`/`retriev` function found. |
| 83 | Method: "Establish a mechanism with a known answer, then hide the answer and test discovery." (L84); "Every discovery test has a planted positive case, a nearby failure or ambiguity case, and a simple baseline." (L218) | adopted | visible in the test names. |

### 2.5 Ideas dropped for convenience or caution, not for cause (collected)

1. **Learning the reorientation engine itself** (#19). Host code since 14 Oct.
2. **Active experiment design** - "Choosing experiments that separate rival rules ... waits until
   the uniform tables are saturated." (plan1 L889-891; plan2 L768-770). plan3/4 use "a declared
   input grid". Never built. This is the mechanism V2P now puts at the centre ("holding all but a
   few constant").
3. **The tabled inverse / bootstrapping `*` inversion** (#27, #76). The one worked example of the
   kernel inventing an operator it was not given. Replaced by a supplied primitive.
4. **Frames constructed by the kernel from connected entries** (#33). Replaced by declared frames
   and supplied views after one plan; the stated reason is scope control (plan3 L86), not a result.
5. **The flat store and its indexes** (#32), and with them order-invariance as a tested property of
   observations.
6. **E-graph / AU modulo theory** (#28, #44). Deferred in all four plans; the trigger written in
   plan1 fired in plan2's own check and was answered with a patch.
7. **Lossy lifts** (#16) - precisely the case where residual pricing gets hard.
8. **Shrunk-table policy baseline** (#69) - the control that would show whether a synthesized
   heuristic earns its keep.
9. **Prediction grouping and the null frame** (#24, #4) - two cheap, checked defences against
   degenerate findings.
10. **Geometric index, stateful simulator, foreign numeric primitives** (#53a) - each an
    "affordance" that was never exercised.
11. **EBG over derivations** (#45) - the only proposed mechanism in these documents that turns one
    derivation graph into a general rule, i.e. reflection in V2P's sense.

---

## 3. Measured results and failures reported in these documents

### 3.1 Standing of the numbers

Every number below is from plan1 §4 or plan2 §5: "small throwaway python scripts ... run in the
scratch directory; they are not in the repo" (plan1 L566-567; plan2 L1093-1094). None was produced
by Lisp code, none can be rerun, and none was produced by a kernel that discovers anything on its
own - in each check a human chose the frame, the roles, the operator set and the literal set.
plan3 reports nothing ("it does not report an implementation or successful results", L7). plan4
reports nothing itself and marks its own traces as "a constructed mechanism test, not a reported
performance result" (the phrase is plan3 L412; plan4 defers to `results.md`).

### 3.2 Search size, depth, and what was reachable

| quantity | value | source |
|---|---|---|
| 1D expansion, leaves `x0 x1 x2 i 0 1 2 3`, ops `+ - *`, depth <= 2 | 17 399 raw expressions, 6 754 behavioural classes; 0.2 s in python | plan1 §4 L572 |
| same without argument-order canonicalization | 25 955 raw; "classes unchanged (hashing removes the duplicates anyway)" | plan1 §4 L573 |
| depth 3, 1D | "about 1.4 x 10^8 raw (3 x 6754^2): out of reach for brute expansion" | plan1 §4 L574; §7.7 L1038 "Depth 2 is the ceiling of the raw expansion" |
| GF(59) `+` table, all 59 constants as leaves | 295 classes at depth <= 1, 38 700 at depth <= 2; 0.4 s on 64 hashed rows | plan1 §4 L575 |
| GF(59), constants {0,1,2} only | "inverse of + not reachable: 58 cannot be built at depth <= 1, so holes are needed" | plan1 §4 L576 |
| store of 5 primes x 2 operator tables | 7 690 entries grouped into 10 frames in 0.01 s; 30 targets, depth 2, one fitted constant: 2.7 s (numpy) | plan2 §3.3 L936-937, §5 L1101 |
| value joins on the GF(59) `+` table | 100 949 joined pairs | plan2 §3.3 L939 |
| index-expression space for list tasks | 19 205 with `mod`; 6 055 with `+ -` only | plan2 §4.7 L1041-1044 |
| largest program actually exhibited | 7 nodes (e.g. `(+ (- x0 x1) (- x2 x1))`, plan1 L460); effective depth 4 only by composing lifts (cubes: one lift; fourth powers: two) | plan1 §3.5 L499-508 |
| longest wall time mentioned anywhere | 2.7 s | plan2 L937 |

No document in this set contemplates a search longer than seconds. plan2's budgets are "patterns of
at most three templates, expansion depth 2, one fitted constant per expression, four residual
rounds" (§3.2 L928-930); plan3's are an unspecified fixed quantum b (§8.1); plan4's fixtures are
25-row and 49-row tables (GF(5), GF(7)). For comparison only, the root kernel's default limits are
10^4 to 10^6 tariff units (e.g. `fibers.lisp:156`, `templates.lisp:537`, `consolidate.lisp:1388`),
a decomposition-tree `max-depth` defaulting to 1 (`synthesize.lisp:69`) or 2 (`decompose.lisp:676`), and the largest limit in
any test is 10^7. The owner's V2P statement - "nothing "very interesting" was findable in the
small budgets with rigid enumeration" - describes a ceiling that was written into plan1 on day one
and never lifted.

### 3.3 What was found (all PY-CHECKED unless noted)

- `2 4 6 8 10`: `x0 = (+ x1 2)` net +14.2 bits; 57 accepted variants, all predicting the same
  continuation (plan1 §3.1).
- Fibonacci as equation net +21.2; as conserved quantity only +3.8 (plan1 §3.2) - "equations must
  be detected directly, not only constants".
- Squares closed form net +14.3; second difference net -3.2 at n = 6 (plan1 §3.2).
- Period 2: `x0 = x2` (+21.1) beats `(+ x0 x1) = 12` (+17.6) because constants are not leaves
  (plan1 §3.3).
- Partial finding `(* x0 x0) = (* 3 x0)` with fiber {0, 3}: 6 bits saved per row, 1 bit residual
  (plan1 §3.3).
- Cubes via the lift `x0 - x1` then second difference 6 (plan1 §3.5).
- GF(p) additive inverse `(+ c (* a k))`, k = p - 1, for p = 5, 7, 11, 13, 59; "verified on all
  3481 rows" for p = 59 (plan1 §3.6; plan2 §4.1: all three directions of `+`).
- One rule for all fields: LGG `(+ c (* ?K a))`, child frame p -> ?K gives `(- p 1)` (plan2 §4.2:
  "Here the engine ran on its own output").
- Multiplicative inverse by parts: `(* ?K c)` with ?K = a^-1 for p = 5, 7, 11, 13 - only after
  anti-unifying buckets rather than representatives (plan2 §4.3).
- Information accounting: on GF(59)^2 (11.765 bits) `+` destroys 5.883 bits and `*` 5.892; the
  identity H(X) = H(f(X)) + E log|fiber| "holds to 10^-9"; transposed `*` has fiber 1 on 3422 pairs,
  59 at (0,0), 0 at 58 pairs (plan2 §5 L1098).
- Commutativity: in a value-joined store commuted pairs are exactly 1/p of joined pairs (21 of 147
  at p = 7; 1711 of 100 949 at p = 59); coding them as a subset nets -28 and -2447 bits. With both
  orders run on the same 50 inputs the tuple LGG is `((+ ?v0 ?v1) (+ ?v1 ?v0))` (plan2 §4.4).
- Computed addresses: rare rows cut 19 205 candidates to 39 (reverse) and 8 (rotate); cheapest
  survivors correct on "100 of 100" held-out lists (plan2 §4.7).
- Hidden switch in GF(251), n = 40: votes 27 and 13 against at most 2 for any other value; hard EM
  converges in one pass; label `(= (mod i 3) 0)` costs about 5 bits against 40; "Total DL is roughly
  45 bits against 319 raw" (plan2 §4.8).
- Lift ordering: ranked by magnitude of lifted values, `x0 - x1` is 66th of 2661 and "none of the
  top 12 children has structure"; ranked by size of E, 4 of the first 23 children are exact (plan1
  §4 L579).
- Null control: 0 of 120 random sequences accept any constant or equation (plan1 §4 L577).

### 3.4 What was not found, or failed

- Depth 2 finds nothing for the interleaving `1, 10, 2, 20, 3, 30` - "This is the first example
  where the representation has to change, not just the expression." (plan1 §3.4 L494-495).
- No multiplicative inverse at depth 2 for p >= 7 (needs a^(p-2)) (plan1 §3.7; plan2 §4.3).
- Rotate has no survivor without `mod`: "with only `+` and `-`, no expression survives" (plan2
  L395-396).
- Fourth powers: "none of the 21 size-3 lifts gives an exact child: two levels are needed" (plan1
  L580).
- Representative AU fails at an identity element: the part a = 1 yields `c`, so the LGG is a bare
  variable (plan2 §4.3).
- Laws are not discoverable by compression of observational data (plan2 §4.4).
- Two traps hit while checking: a null drawn from the data's range makes every finding look
  trivial; undefined boundary rows split buckets so `x0 = (+ x1 x2)` was missed (plan1 §4 L582-590).
- A constant sequence yields 196 330 candidate equations if all pairs in a bucket are enumerated
  (plan1 L594-597).
- plan3 states in advance what will not work: "Do not promise a general integer multiplication
  solver in a straight-line language containing only +, *, and integer literals. Such expressions
  are integer-coefficient polynomials and cannot express general exact division." (L601).
- Byte-length description cost failed within a day of implementation: "switched to a bit-cost
  model; the original ran into problems with integers, and might not scale well to larger
  libraries." ([OWNER], commit 7446706, 27 Oct).
- The whole first implementation was judged a failure of form: "the bloated VM" ([OWNER], commit
  c3709ad).

### 3.5 What had to be supplied by hand (cumulative)

| supplied | where admitted |
|---|---|
| the frame, its axis tags, which column is the unknown, scan order | plan1 §1.2, §1.5 ("the newest reference to a coded column") |
| the choice to transpose, and which argument | plan1 §6.3 |
| the literal set (all field elements, or a fitted hole) | plan1 §4 L575-576, §5.3 |
| isolation / collection | plan1 §5.9: "given and small" |
| the experimental design that makes a law visible (both argument orders on shared inputs) | plan2 §4.4; experiments are "chosen by a fixed policy" (L766) |
| `mod` for rotate; tag arithmetic for `(- p 1)` | plan2 §4.7, §4.2; plan3 L388: "Supplying metadata subtraction has supplied relevant structure." |
| caps on latent inference (4 labels per row, backward sets of 8) | plan2 §1.3 L446-449 |
| the whole "irreducible starting machinery" list | plan3 §1 L26-38 |
| signed literal -1 for integers | plan3 L40 |
| subtraction and division as candidate primitives; the VM's truncating division | plan4 L282-286, L308-314 |
| the lift (map r -> j and decoder) | plan4 M5 L378 |
| the correct view, before any search for one | plan4 M7 L416 |
| the two decoder choices of the recursive trace, before searching for them | plan4 8A L436 |
| the solver-matching mechanism | plan4 L352 |
| the descriptor rule, as positive control | plan4 M9 L515 |
| metadata arithmetic p + (-1) | plan4 8A L448: "declared prior knowledge" |

plan2 stated the test that all of this fails: "If (a) to (d) need frames or roles supplied by
hand, the AU half of P1 is not doing the work." (M1, L1292-1293).

---

## 4. Recurring problems

Each reappears in at least three of the four plans with a different local patch. That pattern is
the evidence that the representation, not the patch, is at fault.

**R1. Deciding what goes with what (the correspondence / frame-construction problem).**
plan1: frames and windows are given; the open question is "which residual to recurse on" among
2661 candidate lifts (§5.6) and the frame algebra is "the least worked-out part" (§5.7). plan2:
frames built by AU over connected entries; hardness "enters in exactly three places: choosing
which entries form an instance tuple (the correspondence), unordered parts ..., and patterns that
span many entries" (L619-622). plan3: "view programs" outside the frame; occurrence search split
off as its own operation (§4). plan4: "Supply a correct view first; then search a tiny published
grammar" (L416). Four mechanisms in two weeks for the one question V2P calls topology - "what
connects to what" - and in every one the answer is ultimately handed in. Connectivity never became
a stored, queryable object; it was recomputed or supplied per frame.

**R2. Syntactic AU breaks on equivalent syntax.**
plan1 §5.5: commutativity makes `(+ c (* a 4))` and `(+ (* 6 a) c)` generalize "to the useless
`(+ ?x ?y)`". plan2 §4.3: an identity element makes the LGG "a bare variable". plan3 §3.2: fixed
syntactic AU plus "a bounded collection of their alternative syntax"; "This is incomplete semantic
abstraction search". plan4 M6: "Replacing c by (* 1 c) preserves behavior but not original AST
spelling". The principled answer (classes of equivalent terms as the unit of AU) was identified in
plan1 §7.6 and plan2 §1.7 and deferred each time. This is the clearest case for an equivalence-
class-aware store.

**R3. The depth-2 ceiling and constants as leaves.**
plan1 §7.7; plan2 §3.2; plan3 "Bound candidate syntax and evaluation work"; plan4 "Counting AST
nodes alone is insufficient if every integer literal occupies one node" (L157). Every route to
anything deeper is a hand-chosen decomposition (lift, decoder, view). The one empirical lever
reported is the composition of lifts: "a lift composes two depth-2 searches at the cost of their
product, not of a depth-4 enumeration" (plan1 L1040-1042).

**R4. What do laws, solve rules and heuristics pay for?**
plan1: everything priced by one fiber code. plan2: laws carry zero bits about data given the
simulator, hence a third "derivations" account in log-rank bits. plan3: rejects that ("No logarithm
of a choice rank is treated as a valid code without an actual decodable coding scheme", L370);
bytes plus lambda-weighted work. 27 Oct: bytes abandoned for bits. V2P: "not at all strict about
e.g. keeping the tarrifs similar". Four cost models in two weeks; the constant is that knowledge
about the *simulator* is worth work, not data bits. The owner's commit message on plan2 already
doubted it: "need to check the DL claim, though."

**R5. Latent / unobserved structure.**
Owner: "(big question mark)". plan1 §5.8: hidden variable per row. plan2 §7: votes and hard EM,
bounded. plan3: absent. plan4: "Hard EM is deferred until a bounded context search demonstrably
needs it." It came back in the successor kernel (`fibers.lisp`).

**R6. Guards and partial findings get a new mechanism each time.**
EUSolver-style cover by bits saved (plan1 §5.4); partition quotient plus description of the label
column (plan2 §2.5, §7); explicit selectors and "computable selector or an explicitly described
label" (plan3 §4); Boolean child frames over retained non-error subsets (plan4 M4). V2P reads all
of these as one thing: a partition of a space, learned experimentally.

**R7. The meta-level is always host code.**
Isolation "given and small" (plan1). "Rules run on the same simulator, so rules apply to rules"
promised (plan2 L207) but the engine round is Lisp pseudocode (§3.1). "The synthesizer may call
itself before its generated programs can recurse." (plan3 L44). Matching "supplied" (plan4 L352).
Lift supplied (plan4 M5). This is the direct ancestor of V2P's "lift has to be a synthesizer
primitive just like substitution is!  Presently this is not true, it's wholly in the host lisp."

**R8. Experiments are a fixed grid.**
"Experiments start uniform. Choosing experiments that separate rival rules ... waits until the
uniform tables are saturated." (plan1 L888-891); "Experiments are executions chosen by a fixed
policy at first" (plan2 L766); "a declared input grid" (plan4 L288). No plan ever lets the kernel
choose an intervention.

**R9. Where does the derivation graph live?**
On the frame as lineage (plan1 §1.2); on every store entry as `prov` (plan2 §2.1); explicitly
*off* the frame in three separate records (plan3 L78-86); as call-ids on messages (plan3 §5.3,
plan4). Then, in the present kernel, back on the frame as `pairs`, `anchors`, `edges`
(`frame.lisp:14-24`). A structure that keeps being relocated is a structure that wants to be
primary.

**R10. Locality is supplied, induced locality is "later".**
plan1: axis tags. plan2: "Locality first: the smallest tag distance" (§3.2). plan4 M7: "Initially
use supplied time/space distance as a scheduling prior. Later, a learned key or shared property may
propose a new neighborhood" (L424). The owner's "Locality can of course be bootstrapped" (P4 L47)
is acknowledged in every plan and scheduled in none.

**R11. Scope shrinks under the weight of controls.**
plan1 and plan2 are expansive and over-claim; plan3 and plan4 over-correct. plan4's pillar 5
"does not claim discovery of loops or general recursion" (L384); pillar 4's AU step is "a
functional reconstruction test with supplied hole inputs, not a whole-corpus compression result or
new mathematical evidence" (L357-359); pillar 9 studies retrieval "without assuming that
human-readable naming emerges automatically" (L521). Each pillar was reduced to a planted
positive control. The controls are good science; the consequence is that the kernel was never
asked to discover anything it was not first shown.

---

## 5. Nuggets for the current lens

Format: the statement, its location and voice, then **Why now**.

### (a) Frames as fibers / bundles; lift, project, pullback; residual calculus

a1. [OWNER] "Topologically, computation may be seen as a projection, / In which case the reverse
process requires a lift." (P4 L105-106; first in P2, 19 Oct). And pillar 5: "a pillar is to
"unproject" or lift data with induced or introduced context, thereby forming fibers through
which attribution can be traced." (P4 L37).
**Why now:** the V2P vocabulary is not new; it is the oldest stable layer of the project. What is
new is the demand that it be the kernel's own operation rather than a description of host code.

a2. [AI, PY-CHECKED] The counting identity H(X) = H(f(X)) + E log2|f^-1(f(X))|, and "x -> (f(x),
index of x in its fiber) is a bijection. Running a computation backwards is lifting: given f(x),
supply the index." (plan2 §1.1 L319-351). Checked on GF(59)^2: 11.77 bits in, `+` destroys 5.88,
`*` 5.89.
**Why now:** this gives every edge of a computation graph an exact scalar - bits destroyed - and
makes "residual = fiber coordinate" a theorem rather than an analogy. It is the natural edge weight
for a topology store, and it is measured by counting on experiment tables, i.e. by running the
simulator.

a3. [AI] Residual taxonomy: exact/set-valued = "the index in the fiber, under a uniform code";
partial = "which rows (a mask, or a guard that is itself synthesized), and full values on the
other rows"; approximate = "an error under a non-uniform code, which needs an order or a metric
on D". "In all three, the residual is u's codeword under the conditional code that the finding
induces; the uniform fiber is the special case." (plan2 §1.2 L368-375).
**Why now:** one definition covers the topological residual (fiber index), the partition residual
(guard) and the geometric residual (metric error). It is the cleanest statement in the trail of
how topology and geometry meet in pricing, and of exactly where a metric becomes necessary.

a4. [AI] "Fiber coordinates come from the ambient space: sort the fiber by value, or use a
reference's position tuple. Per-row coordinates chosen any other way make the residual column
look random however regular the lift is." (plan2 L384-387). Companion: "every correspondence that
is *computed* (a join on values, a sort, an EM assignment) belongs to the model and is paid for in
bits. It never belongs to the measurement; otherwise the alignment would overfit." (plan2 L344-347).
**Why now:** this is the only argued position in the trail on V2P's open question - whether there
are "better options for bootstrapping generated and intermediate spaces other than pricing in the
original or ambient spaces". The answer given: an induced space is model, so it may be used but
must be paid for; coordinates on a fiber must be inherited from a space the decoder already has.
Unverified (the check is not in the repo), but it is a precise, testable claim.

a5. [AI] The predicate pullback. "Let a proposed decoder d reconstruct a parent target y from
available context c and a child value z ... B_i = {z in Z : d(c_i, z) in A_i}" and, in predicate
form, "B_i(z) <=> A_i(d(c_i, z)) ... This uses forward execution only; it does not compute or
enumerate compatible z values beforehand." (plan3 §3 L124-148; plan4 L137-147).
**Why now:** lift is defined here as pulling a *requirement* back along a decoder. It needs no
finite domain and no inverse. This is a working component worth importing: STILL-IN-CODE as
`pullback-frame` (`frame.lisp:544`). It is also exactly the thing the owner says is "wholly in the
host lisp" - the definition is one line of algebra; nothing forces it to be host code.

a6. [AI] "AU is a particularly simple decomposition ... Pattern instantiation is the decoder. The
substitutions become the child targets." (plan3 §3.1 L166-174). And earlier: a lift "can be read
as the value vector of an expression that is injective in u, or as the per-row values of a hole.
The template view is what anti-unification produces; the value view is what the expansion
computes." (plan1 §5.5 L698-701).
**Why now:** V2P's "anti-unification ... really it's a form of quotienting and trivial lifting
under substitution" was already reached on 22 Oct and is in code (`compile-au-constructor`,
`unify.lisp:103`). The unification of AU with lift is a verified nugget, not a new conjecture.

a7. [AI] "A target may be a tuple. Its allowed values are **joint assignments**. The set {(0,0),
(1,1)} must not become two independent sets {0,1}" (plan3 L72); "Multiple holes belong to the same
child tuple until there is a justified conditional decomposition." (plan3 L267).
**Why now:** this is the argument for n-ary edges. A relation over several unknowns cannot be
stored as per-node sets without losing the constraint; a hyperedge (or a tuple with coordinates,
as V2P says) is the minimal faithful representation.

a8. [AI] "Inherited information is therefore a projection with a contract, not a copy of every
attribute." (plan3 L94); "Fiber means the compatible values satisfying a requirement. Residual
means the retained value, index, or other information needed to reconstruct a particular original.
Provenance records where observations, constraints, and decisions came from. These are related but
distinct." (plan4 L149).
**Why now:** three different graphs are in play - the constraint graph (fibers), the
reconstruction graph (residuals), the derivation graph (provenance). A single hypergraph store
must type its edges so these are not conflated; the frame conflated none of them only by keeping
two of them outside itself.

a9. [OWNER] "Sometimes early or first stages yield no compression, e.g. basis expansion to make a
problem linear, so the full DL cost must be measured by the *full* path." (P4 L69). [AI] worked
example y = a + 3b: "storing d1 plus a literal z lookup adds decoder syntax while keeping equally
many one-digit field values" (plan3 §7.2 L412); "Accept compression gains after full composition;
do not require each intermediate step to improve description length." (plan4 L178).
**Why now:** any residual calculus must allow price to rise along a path. Greedy per-edge pricing
is ruled out by the owner's own example.

a10. [AI] "A lossless quotient retains a representative plus enough residual information to
reconstruct the original object." vs. "A lossy quotient keeps only a summary." (plan3 §4 L216-220).
**Why now:** quotient + residual = lossless; quotient alone = heuristic state. The same operation
serves both halves of V2P (exact topology, approximate geometry) depending on whether the residual
is kept.

### (b) Learning dependency structure by intervention / experiment

b1. [OWNER] "Any given operator in the base language ... can be run repeatedly on inputs while
observing the output. You could use the resulting table ... to directly infer operations and
arguments based on indexing from the output - this is memory-based inversion, and it generally
works, though would suffer horribly here due to geometric scaling and non-injectivity." (plan1
L38-44) and "up to (say) depth=2 (this is essential!)" (L88).
**Why now:** V2P's "parallel and depth >= 2 experiments" restates a requirement first written on
14 Oct. It has never been implemented as stated: no plan runs depth-2 *experiments*; they run
depth-2 *expression enumeration over fixed observations*.

b2. [AI, PY-CHECKED] Laws are invisible to passive compression and immediate under shared-input
experiments. "Join the GF(p) `+` table on equal results. For p = 59 that gives 100 949 pairs, of
which 1711 are commuted pairs: a fraction 1/p, exactly. Coding them as a subset ... costs 2447
bits more than not doing so ... In a value-joined store commutativity is invisible, as it must be,
since given the simulator it is no news about these data. Running both orders on the same 50
random inputs and joining on the shared instance tag gives the tuple LGG `((+ ?v0 ?v1) (+ ?v1
?v0))` at once ... Laws come from designed experiments plus validation" (plan2 §4.4 L999-1009).
**Why now:** the single strongest piece of evidence in the trail for V2P's method. Algebra is
found by holding inputs fixed and varying the computation ("parallel experiments"), not by
compressing a table. It also says what an experiment record must contain: a shared instance tag,
i.e. an explicit edge saying "these executions had the same inputs".

b3. [AI] "Count a simulator experiment once when performed; subsequent views incur only the work
actually done for selection, matching, or checking. Reorientation creates neither a new
independent observation nor additional compression credit." (plan3 L110).
**Why now:** accounting rule for an experiment-driven store: the experiment is an immutable
hyperedge; orientations are views of it.

b4. [AI, PY-CHECKED] The experiment table tells you where an inverse exists: transposed `*` over
GF(59) "has fiber size 1 on 3422 of the 3481 pairs (a, c), 59 at (0, 0), and 0 at the 58 pairs (0,
c != 0). So its solve rule must carry the guard a != 0" (plan2 §1.1 L328-331).
**Why now:** a guard read directly off experimental fiber sizes - "conditional guards = calculated
regions of base or lifted space where the law or propagator does not hold", measured.

b5. [AI] Probes refine equivalence classes: "give x and x*x only the inputs {0,1}, then add x=2:
their initially matching buckets must split." (plan4 M2 L245).
**Why now:** connectivity learned from experiments is defeasible; the store needs split as well
as merge.

b6. [AI] Proposed and never built: experiments chosen to "separate rival rules" (plan1 L889-891,
plan2 L768-770). And for stateful worlds: "the quotient of histories by future behavior (Nerode;
causal states ...), whose classes are the hidden state" (plan2 §8 L1194).
**Why now:** the missing half of "holding all but a few constant". The second sentence is the
only place the trail says how topology would be learned from a simulator with state.

b7. [AI] Caution: "Inverse reasoning later reorients execution relations; it does not reverse
causal interventions." and "Conservation under a supplied transition does not identify a symmetry
group." (plan4 M2 L247).

### (c) Algebra / law discovery and reorientation

c1. [AI] "No column is designated as input or output. All directions are searched, and the solve
rules are the directions other than the one in which the data were produced. The prompt's
"exchange of input and outputs" thus needs no transposition step" (plan2 L835-838). Then
"Input and output are roles in these questions." (plan3 L108).
**Why now:** this is the relation-first reading that a hypergraph makes native: an operator
application is one n-ary edge (a, b, c); forward evaluation, each solve rule, and the law are
orientations of it. plan1 needed a "transpose" step, plan2 removed it, plan3 made it a role. The
trajectory points at undirected hyperedges with orientation as an annotation.

c2. [AI] One relation, four uses: "Forward, from input to output, is the simulator. From output
to input on values is a solve rule; on expressions it is isolation; from input and output to an
expression is the synthesis recursion." (plan2 §1.6 L534-536).

c3. [AI] "Turning a conserved quantity into a generator is a fiber computation." (plan1 §0 claim
3, L218).

c4. [AI, PY-CHECKED] When algebra is actually needed: "In 1D with {+, -, *}, every exact case's
explicit generator was already in u's bucket. Algebra is needed when: (a) the inverse is not
shallow in the base operators ...; (b) the unknown is fixed only jointly by several findings ...;
(c) the fiber is larger than one; (d) holes are to be fitted without enumeration." (plan1 §5.9
L794-803).
**Why now:** tells the new kernel which demonstrations can distinguish "algebra was learned" from
"enumeration found it anyway". Most early fixtures cannot.

c5. [AI, PY-CHECKED] Laws and solve rules save work, not data bits: "With the simulator in the
decoder, a law on a finite domain is a theorem about the simulator: its truth is no news about
any data ... What both save is work. A solve rule saves a factor of about |D| in decoding" (plan2
§1.5 L476-482); canonical argument order gives "a factor of 1.49 at depth 2, which should compound
with depth" (L485-486). But also: commutativity "removes a third of the raw evaluations but no
classes" (plan1 L909-910) - observational hashing already removes the duplicates.
**Why now:** pricing of algebraic knowledge belongs on the search/work side. And the second
number is a warning: at fixed depth, behavioural bucketing subsumes law-based pruning; laws earn
their keep only by enabling reorientation and by aligning syntax for AU.

c6. [AI] Rules about rules by the same engine: anti-unify the per-prime solve rules, lift the
hole, synthesize the child `p -> ?K` (plan1 §3.8; plan2 §4.2). Caveat: "Supplying metadata
subtraction has supplied relevant structure." (plan3 L388).
**Why now:** the smallest existing example of reentrancy across abstraction level (values, then
rules as values). Worth keeping as a regression fixture; the caveat says what must be declared.

c7. [AI] Witness vs. inverse: "Check two distinct statements: under the learned guard, q satisfies
the original relation; and that relation is equivalent to z=q for every z." (plan4 L316-318).
"Selecting one acceptable inverse witness does not encode every original witness or occurrence."
(plan4 L151).
**Why now:** a reorientation is only a propagator when uniqueness on the fiber is certified;
otherwise it is a section of the bundle, not an inverse. STILL-IN-CODE (`validation uniqueness`,
`milestones/algebra-discovery.lisp:8-9`).

c8. [AI] Symmetry as data: "a pair (sigma, tau), an index map and a value map, with x(sigma(i)) =
tau(x(i))"; "Which expressions are invariants of which transformations is itself a family of laws,
E(Ta, Tb) = E(a, b), which the experiment loop can learn. With those laws, the system can go from
a detected symmetry to its candidate conserved quantities and back." (plan1 §5.10 L823-839).
**Why now:** the only concrete proposal in the trail for V2P's "conservation and symmetries to
generative expressions, or vice-versa". Never built.

c9. [AI] Expressivity is not search: `+`, `*`, integer literals "are integer-coefficient
polynomials and cannot express general exact division" (plan3 L601). And a soundness boundary: "A
law validated on total field values may be substituted into larger programs only when evaluation
behavior is preserved ... dropping a subexpression that can error or diverge requires more than a
value-level identity." (plan4 L272).

### (d) Graphs / hypergraphs as the store, and why they were not adopted

d1. [OWNER] The graph was in the first prompt: "a program can be represented as a DAG ... filling
in holes in the graph (and possible re-representing the DAG or execution trace" (plan1 L21-25);
and in the second: "a structure & type-aware & locality-seeded subgraph isomorphism problem"
(plan2 L134); "a graph over the graph of heterogenous experience data" (plan2 L155). But the
owner also specified the opposite container: "one 'flat' store. / A list.  In lisp." (plan2
L121-122).
**Why now:** the flat list was the owner's choice, made for order-invariance and homogeneity, not
an agent's simplification. V2P reverses it knowingly.

d2. [AI] What the matching problem really is: "A pattern is a set of typed templates with shared
variables and constraints between their tags: a conjunctive query ... Its instances are the
homomorphisms from the pattern into the store, which in ILP is theta-subsumption. Requiring
distinct variables to map to distinct entries ... makes it subgraph isomorphism ... Matching is
NP-complete in the size of the pattern (Chandra and Merlin 1977) and polynomial for acyclic
patterns (Yannakakis 1981) ... Ordered trees with known roots, on the other hand, anti-unify in
linear time." (plan2 §1.8 L608-622).
**Why now:** the complexity budget for a hypergraph kernel, stated once and correctly. It answers
V2P's worry about needing "an efficient graph isomorphism test": the needed operation is
homomorphism of *small, mostly acyclic* patterns into a large store, which is join processing, not
isomorphism. Literature claims here are standard but were not re-verified by me.

d3. [AI] Engineering lessons listed for such matching: filter by type and label first; bind the
most constrained (rarest) variable first; give patterns a canonical code so each is grown once
(gSpan); bound a pattern's best possible utility before growing it (Stitch, SUBDUE); seed and
extend along locality (plan2 L624-635). Plus "an accepted pattern becomes one symbol for later
matching, so later patterns are smaller (SUBDUE's hierarchical compression)" (L643-645).

d4. [AI] Two kinds of edge with different prices: "A tag join on a functional relation picks a
unique partner and costs nothing. A value join can offer several partners; the choice is then a
latent correspondence and is paid for" (plan2 L821-823).
**Why now:** given edges vs. inferred edges; the latter are model.

d5. [AI] "A partition is only one kind of view. Sliding windows overlap; joins may duplicate rows;
a change of prediction direction may preserve every row. Preserve occurrence links instead of
pretending every view is a partition of the original table." (plan3 L210).
**Why now:** an explicit statement that the table abstraction leaks; what is actually preserved
is a set of occurrence links - a graph.

d6. [AI] "Frames are relations, and a new data structure is a new frame made by one of six
operators" - "a tree is a frame with a parent-reference column (a computed reference)" (plan1
§5.7 L741-757).
**Why now:** the frame began as a relational-algebra object able to encode graphs by reference
columns. The relational reading and the hypergraph reading are the same structure (a relation is
a set of hyperedges); the choice is about what is indexed and what is first-class.

d7. **Stated reasons graph machinery was not adopted** (all [AI], none a measurement):
- plan1 L241-244: "No SAT, no e-graph, no learned priors, no ARC ... Each later structure enters
  only after a measurement says it is needed".
- plan1 L1016-1024: "The buckets already are the version space of a frame"; yet in the same
  paragraph "a minimal e-graph (hash-consing, union-find and rebuilding) is a few hundred lines,
  not a heavy import."
- plan2 L637-641: restrictions (three templates, acyclic) "lifted only after a measurement says it
  binds".
- plan3 L44: "Do not initially add polymorphism, binders, general recursive programs, e-graphs, a
  theorem prover, or a universal graph-matching engine."
- plan3 L86: "The core algorithm should not require every row to carry a query plan, uncertainty
  model, search score, proof status, and provenance graph."
- plan3 L212 and plan4 L408: "General graph isomorphism is unnecessary." / "A general
  graph-isomorphism solver is unnecessary."
**Why now:** the graph store was declined on grounds of minimalism four times and never on
evidence. No document reports trying one and finding it too slow or too complex. V2P's suspicion
that "poor data representation seems to have induced overbearing incidental complexity" is
consistent with the record: the edges came back anyway, as side slots (`pairs`, `anchors`,
`edges` at `frame.lisp:14-24`; knowledge "relational edges", `knowledge.lisp:4`).

d8. [AI] "The graph over the graph is the set of links between entries (derived from,
generalizes, inverse of, used with), stored as entries." (plan2 L672-674).
**Why now:** typed meta-edges between library items, themselves in the store - the reflective
layer of a hypergraph design, proposed on 19 Oct.

### (e) Geometry: metrics, embeddings, neighbourhoods, spaces, ambient vs. induced pricing

e1. [OWNER] The owner's first statement of the topology/geometry split (19 Oct): "In ML, this is
a geometric space - continuous R^d - which enables self-organization. / In programming and human
language, the space is expansive and compositional (e.g. docstrings, function names). / This makes
it more of a topology than a geometry" (plan2 L152-154); "Linear codes work in the same way, /
though in a discrete and non-compositional geometry / True compositional addressing requires
variable compute when decoding the address" (L159-161).
**Why now:** V2P's "high-D embeddings are 'flat', whereas the native topology of graphs,
hypergraphs, are very much folded and recursively nested" is this passage five weeks later. The
owner has held the hybrid view throughout; what changed is its priority.

e2. [OWNER] The 4-5 Nov additions quoted in 1.3: metrics as relaxed partitions; "change is bounded
for a map y = f(x) in both x and y / This means both input and output need a geometry"; residuals
of heuristics "measured with a learned or ambient metric"; constructed spaces ("'colonies' or
'mountain passes', wherein similarity and hence locality is purely computational").
**Why now:** these are requirements for the geometry half, in the owner's words, predating V2P:
(i) a metric per space, on inputs and outputs; (ii) spaces can be constructed by computation;
(iii) a partition is the hard limit of a metric; (iv) heuristic residuals are metric-priced.

e3. [OWNER] "Locality can of course be bootstrapped: items that have a certificate for being
co-local (beyond supplied data: from search, comparison, or computational validation) can have
induced locality -- which, in turn, can be amortized / synthesized / explained through a subsequent
synthesis step. / Or, vice-versa, locality can be imposed (via selection and sorting), and
equivalence checked." (P4 L47-48).
**Why now:** this is "proximity flows along verified topological links" in its original form, and
it supplies the two directions of the hybrid engine: topology induces geometry (certified links
pull things close), and geometry proposes topology (sort, then check equivalence).

e4. [OWNER] "Aside: deep learning does this in pre- and statically- allocated high-dimensional
space; critical here is that space is allocated on the stack, in the search tree." (P4 L54).
**Why now:** direct tension with V2P's closing thought that "there could be good reason for
keeping the vectors flat high-D". The owner's earlier answer was dynamic allocation; the new
engine that "*makes* spaces where needed" is the reconciliation.

e5. [OWNER] "This information (e.g. MI) has to be simply measured, with a fixed ambient space /
correspondence. / Computation is not allowed here." (P4 L103-104). [AI] reading: "the fixed
measurement is the ambient code: per-row uniform codes over the domain D, with rows put in
correspondence by their tags." (plan2 L342-344), citing usable information under a restricted
predictor family.
**Why now:** the origin of ambient-space pricing. The owner's rule is stronger than the code's:
the measuring instrument must not compute.

e6. [AI] A metric is a property of a space, not of values in general: "Locality and guards need
an order, and GF(p) has none compatible with addition (a < b does not give a + c < b + c). So
inequalities apply to tags at first, and to values only from M5." (plan2 §1.10 L691-694).
**Why now:** an early, concrete case where two spaces in the same problem (indices, field values)
have different geometry. A geometry engine must attach metrics to spaces/types, and some spaces
have none.

e7. [AI] Pricing lesson imported from a sibling project: "An unexplained value costs a constant
log2|D| whatever the size of the residual (... a code whose marginal cost falls as the residual
grows lets memorization beat rules)." (plan2 §2.7 L870-873).

e8. [AI, PY-CHECKED] Small residuals are not evidence of structure: ranked by magnitude of lifted
values, the right lift for cubes is 66th of 2661 and "none of the top 12 children has structure";
"Do not rank lifts by how small the lifted values are: that rewards near-cancellations with no
structure" (plan1 L579, L730-731).
**Why now:** a caution for metric-priced residuals: nearness in the ambient metric is a poor
heuristic for compressibility. The quantity that worked was description length of the lift.

e9. [AI] Nearness for control, equivalence for truth: "phi(s1) = phi(s2) permits sharing a
preference estimate. It does not establish that s1 and s2 have the same solutions, interchangeable
continuations, or equal program semantics." (plan3 §8.5 L527-533).
**Why now:** the working division of labour between the two halves of the proposed kernel.

e10. [AI] Never built: "learned, geometric addressing: an index protocol (`add`, `query`); an
embedding index is one more index" (plan2 §8 L1196). 0 hits for embedding/geometry in the root
kernel.

### (f) Heuristics / policies and how they were to be learned

f1. [OWNER] "Other messages can simply be lossy condensations of the computation performed in a
search branch, approximate expressions of "why this worked or didn't" / Aka heuristics.   The
residuals they emit are discarded. / Which is why the computational cost is essential." (P4
L77-79).

f2. [AI] Use the same synthesizer, same residual mechanism: "model the training labels as
"heuristic prediction plus literal error." This reuses the existing decoder/child mechanism. At
deployment the policy evaluates only the heuristic; its training residuals do not accompany it."
(plan3 §8.4 L517).
**Why now:** a heuristic is a lossy quotient whose residual is thrown away - the owner's
definition made operational with no new machinery. STILL-IN-CODE in spirit
(`make-search-trace-frame`, `consolidate.lisp:20`: search residuals packaged "into an ordinary
`frame`").

f3. [AI] The learning signal: r_t = B_t - B_{t+1} - lambda dW; "Do not finalize a child's credit
when it returns; its effect may appear only when the parent is assembled."; G_t "is a return under
the behavior that actually followed the decision, **not** the isolated causal contribution of that
action." (plan3 §8.2 L448-474).

f4. [AI] Order, never prune, unless proven: "Learned scores initially change order only. Pruning
needs an independently sound contradiction or lower bound." (plan3 L296); "A timeout is a negative
observation for "success within b," but it is censored evidence about eventual success." (L502).
Keep "a resumable canonical enumerator even after learning preferences" (L294).

f5. [AI] The utility problem: learned rules can make the system slower; U(R) = work saved minus
matching work (plan2 §1.9 L676-680, §6.2).

f6. [AI] Start simple and stop there if it suffices: "If the shrunk table works and the
synthesized policy adds no benefit, keep the table." (plan3 L633). The table was never built.

f7. [AI] "The foremost open theoretical problem is the relationship between a short heuristic, its
limited evidence, and its effect on a changing search process." (plan3 L650).

### (g) The language component

g1. [OWNER] Language is a heuristic address: "A language enables compositional description of the
labeled computation, / In a form that is shorter and cheaper than executing the function / rule /
algorithm itself. / Thus it is a form of heuristic." (P4 L201-203). "the names of functions are
short, easy-to decode, heuristic / approximate descriptions of what the functions do. Without
them, libraries and code are un-navigable." (P4 L82).

g2. [OWNER] Bounded compositionality: "Language is compositional, which means that the decoder
needs to execute some variable time/space computation / But: it is not infinitely compositional
like actual computer code, so that a fixed allocation of time or space is sufficient (like in a
transformer)." (P4 L83-84). Compare the earlier "True compositional addressing requires variable
compute when decoding the address" (P4 L197).
**Why now:** the owner had already moved toward a bounded-depth, transformer-like decoder for
language by 26 Oct - the same move V2P contemplates for vectors.

g3. [AI] Exact vs. approximate naming: "An identifier bound to a definition is exact. A
description used to find that identifier can be approximate." "Descriptions rank candidates;
execution checks them." (plan4 L519-521). Design of the test: opaque IDs, random renaming "to
expose accidental lexical advantages", must beat type/probe indexing in total work (L513-517).

g4. [AI] What symbolic labels can be made of today: "type signature, domain, the laws the entry
satisfies, its fiber profile, its use count" (plan2 L669-670).
**Why now:** these are all topological facts about an entry. A first vocabulary can be read off
the graph; V2P's 'like' / 'analogy' / 'action' words are then operations on it.

### (h) Reflection and reentrancy

h1. [OWNER] "The search procedure itself is a program which emits an oft-repetitive computational
graph." (P4 L70); "Messages, like again everything else here, can be target for anti-unification
/ generalization / library learning, which lifts them out of the local problem context to be
general for all problems - eg creation of a new (partial) conservation." (P4 L75).

h2. [AI] The message contract: `Message = (call-id, claim, evidence)`; "Scalar rewards and
logical explanations are separate: ancestry records what happened, while a certificate
establishes what must follow." (plan3 L302-326). Limits: "AU of failed traces may propose a
generalization; it does not prove that generalization." (L623); "Neither an implication graph nor
a proof is obtained merely by retaining provenance links." (L625).
**Why now:** reflection needs two edge types on the search graph - chronology and implication.
Only the second licenses pruning. STILL-IN-CODE (`enumerate.lisp:219`); and `messages.lisp:3-9`
states the reflective intent outright: "a frame built from such rows is an ordinary frame: what
the kernel does to a task it can then do to a record of its own search".

h3. [AI] Search factorization, stated without hype: "If k subproblems each have n alternatives and
become independent after a small interface is fixed, solving them separately can avoid enumerating
n^k combinations. When they share unresolved constraints, the interface or a joint requirement
must carry those constraints." (plan3 §5.4 L332).
**Why now:** this is a statement about cut sets in a dependency graph. It is the precise sense in
which topology buys tractability, and the place where graph structure (separators) would be used
by the kernel on itself.

h4. [AI] Expressions as values: "Expressions are values (quoted trees) with `eval`, `match` and
`inst` (instantiate), so rules are expressions over expressions." (plan2 L700-702); then the
tightened form "without `eval` or host callbacks" (plan4 L263).

h5. [AI] The admission that blocks reentrancy: "The synthesizer may call itself before its
generated programs can recurse." (plan3 L44; the same point at plan4 L114).
**Why now:** from plan3 on, recursion of the *search* is host recursion and is not available to
synthesized programs. V2P's demand that lift be a synthesizer primitive is the demand to undo this
sentence.

h6. [AI] Never built: EBG - "generalizes one solved instance by variablizing whatever its
derivation did not depend on. It needs the derivation, which the store keeps as provenance, and
one instance rather than two." (plan2 L580-584).
**Why now:** this is dependency analysis on the derivation graph (what the result did *not*
depend on becomes a variable) - structurally identical to V2P's "holding all but a few constant",
applied to the search's own record. It is the trail's best-specified reflective operation.

### (i) Totality, crashes, learned guards

i1. [OWNER] "(Which my yield errors)" (P4 L98) - the only owner statement before V2P.

i2. [AI] "An execution that yields bottom is stored like any other: errors are data, and guards
are learned from them." (plan2 L763-764).

i3. [AI] Three outcomes, kept apart: "Errors are explicit results of evaluation; divergence is
interrupted by a work limit." (plan3 L24); "interrupted evaluation is unknown, not a semantic
error or a proof of failure" (plan4 L110); "Failure to find a witness within a budget is not an
emptiness proof." (plan3 L158).

i4. [AI] The learned-guard recipe: "Execute each operator on a declared input grid, retaining both
values and errors. Learn its definedness predicate through the existing Boolean synthesis path."
(plan4 L288-290); candidates keep "non-error, successful subset"; "Learn a guard for that subset
using Boolean child frames." (L299-302). And the honest limit: a guard learned on samples is not a
certificate (test `learned-guard-on-samples-is-not-a-certificate`, `tests/milestones/guards.lisp:194`).
**Why now:** V2P asks to "support learning [totality] by tolerating crashing or non-terminating
behavior, and assembling guards for them, via application of propagators, laws, and
experimentation". The October design already did this for arithmetic: errors are observations;
the guard is a synthesized partition. It is a working component to import. The present kernel
added a structural totality prover on top (`provably-total-p`, `ast.lisp:1160`).

i5. [AI] Guard = identifiability region: "the transposed generator holds on a subset of rows, and
the guard learned for that subset is the region where the operator is identifiable." (plan1
L855-856).

### (j) Search budgets and compiled / lowered execution

j1. The numbers of 3.2. In one line: depth 2 costs 10^4 expressions and a fraction of a second;
depth 3 costs 10^8; nothing deeper was ever attempted except by composing depth-2 searches
through hand-chosen lifts.

j2. [AI] Sample, hash, verify: fingerprint on 64 rows, verify hits on all rows (plan1 §7.1; plan2
§2.3 with the Schwartz-Zippel bound (d/p)^k for polynomial identities).
**Why now:** the cheap way to maintain behavioural equivalence classes over a large candidate set
- relevant to any e-class-like node in a graph store, and compatible with hours-long search.

j3. [AI] The work meter must be fine-grained: "Initially meter small interpreter operations and
tree visits, using a published tariff ... One arbitrary simulator call is not an adequate work
unit. The tiny fixed-prime experiments may treat field operations as unit cost; scaling P requires
revisiting that choice." (plan3 L366).

j4. [AI] Conditions under which backtracking search actually covers its space: "branching is
effectively enumerable, limits grow, work is preemptible, and scheduling is fair." (plan3 L292);
"Finite memory, permanent retention of every visited branch, and infinite exploration cannot all
be required simultaneously. If eviction causes repeated work, measure it." (L613).
**Why now:** these are the constraints an hours-long run will meet first. Nothing in the trail
measures memory.

j5. [AI] Compiled execution was planned from the start: "native compilation with type
declarations for the inner loops (value vectors as simple arrays of fixnums)" (plan1 §8.1
L1058-1059). It arrived a month later (`compile-ast-fn`, `vm.lisp:432`).

j6. [OWNER] The cost of search was always part of the objective: "metrics for computational cost,
including the cost to search for the compression" (P4 L7). V2P's "hours of search" does not relax
this; it says the constant was set too low.

---

## 6. Contradictions

### 6.1 Between the documents

| # | topic | earlier | later |
|---|---|---|---|
| X1 | How reorientation is done | plan1 §6.3: an explicit "transpose" step per operator and argument | plan2 L835-838: "needs no transposition step"; plan3 L108: roles of a question. Three designs in nine days. |
| X2 | Are fibers computed? | plan1 §1.6 and M0: "Fibers are computed by enumerating D"; the whole DL is built on \|F_r\| | plan3 L148: "Explicit finite fibers remain an optional representation and a useful test oracle. They are disabled in the required bootstrap runs". The fiber *code* of plan1/plan2 has no successor; fiber sizes are generally unknown under predicates ("cardinality and emptiness may be unknown", plan3 L158). |
| X3 | Pricing of search | plan2 §2.7: derivations account = "sum over choice points of log2 of the rank of the chosen candidate" | plan3 L370: "No logarithm of a choice rank is treated as a valid code without an actual decodable coding scheme." |
| X4 | Unit of description | plan1 §1.3: size x log2(#symbols) bits; plan2: prefix code bits | plan3 §6: "UTF-8 byte length of canonical S-expressions"; then bits again four days later (commit 7446706). |
| X5 | Who builds frames | plan2 L736: "Frames are then built by AU and never given" | plan3 §2: frames are declared, views are explicit programs; plan4 L416: "Supply a correct view first". |
| X6 | The store | plan2 §2.1: everything is an entry in one list, with provenance, label and stats on each | plan3 L86: the core "should not require every row to carry a query plan, uncertainty model, search score, proof status, and provenance graph." |
| X7 | The withheld-operator handicap | plan1 §5.9: "the base operator set is kept incomplete on purpose"; plan2 §1.10; plan3 L40 | plan4 L310: the main experiment "explicitly admits subtraction and division as candidate primitives". |
| X8 | Inverting multiplication | plan1 §3.7 and plan2 §4.3: learn a tabled `inv` | plan3 L601: "Do not promise"; plan4 L313: "it does not learn the primitive's implementation of modular reciprocals." |
| X9 | E-graph cost | plan1 L1023-1024: "a few hundred lines, not a heavy import" (contradicting the owner's "a heavy import", plan1 L171) | plan3 L44: excluded outright. plan2's check met plan1's trigger (b) and patched around it. |
| X10 | Latent inference | plan2 §7: a designed milestone (M4) | plan3: absent; plan4 L384: "Hard EM is deferred". |
| X11 | Heuristic features | plan2 §6.4: property signatures of the *task data* | plan3 §8.1: features of the *search state* (target type, proposal family, row count, depth, budget bucket). Different objects under one name. |
| X12 | Whether findings must each pay | plan1 §5.13 / plan2 §2.5: "accepted greedily by marginal net bits" | plan3 §5.2: "A partial decomposition can be larger and slower than the current description. Keep it while its search budget lasts." The later position is the owner's (P4 L69). |
| X13 | Scope of a "law" | plan1 §1.4: a collision that also holds on the null frame "is a law of the operators" | plan4 L216: finite samples "justify conjectures and further testing, not unrestricted rewrite or pruning"; three evidence grades required. |
| X14 | Graph matching | plan2 §1.8 treats conjunctive matching as the engine's core operation | plan3 L212: "General graph isomorphism is unnecessary." (true but beside the point: plan2 never proposed isomorphism). The useful plan2 analysis was discarded along with the straw man. |
| X15 | Voice | plan1/plan2: "holds", "checked", confident | plan3/plan4: "does not claim", "is not thereby". The owner's commit messages track this: "need to review it" / "need to check the DL claim" / "won 't simple run in circles" / "needs critical review". |

### 6.2 Between the owner's own statements over time

| # | then | now (V2P) |
|---|---|---|
| Y1 | "one 'flat' store. / A list.  In lisp." (P4 L157-158) | "re-expressed as a graph, hypergraph, or other datastructure" |
| Y2 | "Geometry is not essential for this proposal, except ..." (P4 L62) | "We _must_ start with some bedrock of "these things are close"" |
| Y3 | "critical here is that space is allocated on the stack, in the search tree" (P4 L54) | "there could be good reason for keeping the vectors flat high-D, and just doing what a transformer does" |
| Y4 | "This search is also highly amenable to parallelization." (P4 L176) | "switching to multi-threaded operation is alas not within scope" |
| Y5 | "Goal is to start as absolutely minimally as possible" (plan1 L178) | "we realisically should tolerate hours of search" |
| Y6 | e-graphs "a heavy import that nonetheless may be worthwhile" (plan1 L171-172) | "too much technical and scientific risk through unverified or academic imports", yet e-graphs named as a possible need |
| Y7 | AU "initially should be the primary means of introducing abstractions" (P4 L155) | AU "is something like ... a form of quotienting and trivial lifting under substitution" |
| Y8 | Linear algebra "_out of scope_" (plan2 L45) | inverters "like autocorrelation" and "higher-order functors" are to be derived |
| Y9 | "True compositional addressing requires variable compute when decoding the address" (P4 L197) | already softened in pillar 9: "a fixed allocation of time or space is sufficient (like in a transformer)" (P4 L84) |

None of these is an inconsistency to be resolved against the owner; each is a recorded change of
position that the synthesis should name, because the earlier position is embodied in the code.

### 6.3 Between these documents and the current root kernel (quick grep only)

| # | document says | code shows |
|---|---|---|
| Z1 | "The only data frame is: Frame = (schema, rows); Row = (key, known, allowed)" (plan4 L116-121); view, derivation and search records "stay outside the frame" (plan3 L78) | `frame` has six slots: `schema rows pairs anchors metric edges` (`frame.lisp:12-24`). The relational/graph structure was added to the frame after all. |
| Z2 | "Frames are then built by AU and never given" (plan2 L736) | no frame-from-store constructor; no observation store. |
| Z3 | GF(p) inverse to be learned (plan1 §3.6-3.7; plan2 §4.3) | `field-reciprocal`, "not learned inversion" (`vm.lisp:162-163`). Only the additive bootstrap is a test (`tests/milestones/algebra.lisp:57`). |
| Z4 | "without `eval` or host callbacks" (plan4 L263) | ASTs are compiled to host closures for speed (`compile-ast-fn`, `vm.lisp:432`), and a priority predictor may be a raw host `function` (`synthesize.lisp:466-468`). `eval` appears once, in profiling (`benchmark.lisp:157`). Whether the closures preserve the metered semantics was not audited here. |
| Z5 | "No SAT" (plan1 L241; plan2 §8) | `nogoods.lisp` implements UIP/DIP-style clause learning (`package.lisp:210-216`). This matches the owner's pillar 8b, contradicting only the early plans' exclusions. |
| Z6 | "Hard EM is deferred" (plan4 L384) | `infer-fibers` (`fibers.lisp:156`), five hard-EM tests (`tests/lifting.lisp:19-187`). |
| Z7 | Shrunk-table estimator first, synthesized policy second (plan3 §8.3-8.4, §9.6) | no table (0 hits for kappa / shrink / incumbent); `condense-search-heuristic` (`consolidate.lisp:95`) goes straight to synthesis. |
| Z8 | Null frame, prediction grouping, fiber-size code, discrimination trees, EBG, embedding index, stateful simulator protocol, foreign primitives, threads | 0 hits each. |
| Z9 | S in bytes (plan3 §6; plan4 L198) | bit codec (`codec.lisp:50-68`), tariff version 10 (`vm.lisp:7`). |
| Z10 | Budgets grow, search is resumable for coverage (plan3 §5.2) | resumable jobs exist (`enumerate.lisp:315`, `:558`), but default limits are 10^4-10^6 units and decomposition depth 1-2 (see 3.2). The mechanism for long search exists; the settings do not use it. |
| Z11 | plan2's flat, append-only, typed store with links between entries | exists for knowledge only: `knowledge.lisp:3-5`, 14 registered kinds (`:law :solver :function :relation :descriptor :transformer :locality-key :decoder-template :nogood-schema :dip-feature :heuristic :motif :spec :functor`). The library, not the data, is where the store idea survived. |

---

## 7. Reading for the synthesis

1. **The fiber / lift / projection / residual language is the owner's, original, and stable.** It
   predates every plan. The plans gave it two exact forms that are worth keeping: the counting
   identity (a2) and the predicate pullback (a5). Between them they define projection (bits
   destroyed), lift (requirement pulled back along a decoder), fiber (compatible set), residual
   (codeword under the induced conditional code). AU, partition, guard, quotient, heuristic were
   each shown, somewhere in these four documents, to be an instance: AU = lift along pattern
   instantiation (a6); partition/guard = synthesized label column (R6); heuristic = quotient with
   the residual discarded (f2, a10); reorientation = change of role on one relation (c1).
   The uniformity V2P asks for was argued piecemeal in October and never assembled, because each
   instance was implemented as its own host procedure.

2. **The graph was present in the first prompt and was declined four times on grounds of
   minimalism, never on evidence** (d7). The frame started as a relation with lineage (#1), lost
   its relational algebra to "views outside the frame", and regained edges as side slots. The
   only place the store idea was honoured is the knowledge library.

3. **The single most transferable empirical lesson is b2**: algebra is invisible to compression
   of observations and immediate under shared-input experiments. It supports V2P's method
   directly and tells the store what an experiment must record. It is a python-scratch result;
   it should be reproduced in the kernel before being relied on.

4. **What blocked bootstrapping is visible as a list of supplied items (3.5) and a list of
   convenience drops (2.5).** The common factor is that everything at the meta-level - choose
   the view, choose the lift, choose the experiment, match the rule, isolate the unknown - was
   host code or handed in. V2P's "lift has to be a synthesizer primitive" names one member of a
   family.

5. **Budget.** The depth-2 ceiling and second-scale searches were design constants from plan1.
   The machinery for long search (resumable, metered, fair) was specified in plan3 and exists;
   what is missing is a search space in which more time buys more - i.e. the composition of
   small searches through learned decompositions, which plan1 already identified as the only
   way past depth 2 (R3).

6. **Geometry has almost no history here.** Two owner passages (19 Oct, 4-5 Nov), one residual
   taxonomy (a3), one pricing rule for induced spaces (a4), one warning (e8), one unbuilt
   affordance (e10), and one slot in the code. Whatever the synthesis proposes for the geometric
   half will be new design, constrained mainly by the owner's own requirements listed in e2-e5.

7. **Things in these documents that are sound working components to carry into a rewrite**
   (each STILL-IN-CODE): the (key, known, requirement) row; predicate pullback and composition;
   AU as decoder + substitution child; messages with scoped claims; the three evidence grades for
   laws; errors-as-observations with synthesized guards; two-statement certification of solvers;
   metered resumable jobs with a canonical reserve; the availability rule against informational
   loops.

8. **Things that were checked on paper, never built, and bear directly on the new design:**
   active experiment selection; AU over equivalence classes; conjunctive-pattern matching with
   the stated restrictions and indexes; EBG on derivations; the invariance-law family linking
   symmetries and conserved quantities; lossy lifts; an embedding index; causal-state quotients
   for stateful simulators.
