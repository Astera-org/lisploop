# lisploop --- plan 4

## Nine research pillars, one small synthesis kernel

26 October 2026. Reorganizes prompt3 and plan3 around the nine numbered research goals. This is an experimental proposal; no implementation or successful results are claimed.

The prompt that motivated this document (`prompt4.md`), verbatim. The
`# prompt` heading is dropped, trailing spaces are removed, nested items are
indented four spaces per level instead of two, and a blank line is added
before the list so that they render as lists:

> Updated Monday 26 October 2026
>
> The goal of this research is to make a recursive program synthesis system.
> This system takes output or input-output data, tagged by time and/or space, and iteratively and recursively derives a program, run on a fixed simulator with a growing library, which generates the data.   In the case of input-output data, this means generates the output data from the input data.
> The objective of the program synthesizer is thus to find a representation or compression of the data which minimizes the overall description length as well as metrics for computational cost, including the cost to search for the compression. The pricing mechanism for this will be a mix of fixed costs, information-theoretic estimates, and (of course, given the recursive nature) computed, bootstrapped metrics.
> The research is motivated by N pillars:
>
> 1. **Search**.  Search over computation is fundamentally unavoidable: the *a priori* shortest way to predict the **exact** effects of a computation is simply to do it.  Hence the simulator / computation engine + the supplied data are the ultimate sources of truth.
>     a. Execution, conditional input values and state, is similarly the ultimate source of equivalence: a given (set of) outputs is equivalent a program executed via a simulator on the inputs (e.g.).
>         1. Trick is to look for shortcuts!
> 2. **Learned equivalence.** That said, it is possible to re-represent computations into different forms.
>     a. For example, it is strategic to look for conserved quantities by taking the observed data and treating it as input to a computation.
>         1. This constitutes inference of symmetry - equivalence under action.
>     b. Likewise inverting causality can propagate information from an observed output back to an input.
>         1. Learning the rules of this over a library + simulator is inspired by the work of [[FlashFill]] and FlashMeta,
>             a. Though here we will **learn** the propagation rules.
>         2. This is a more general form of backpropagation, adapted to discrete structures.
>     c. Exact computation can be approximated and shorted (in time and space) by heuristics.
>         1. This entails the emission of residuals from a given computation.
>             a. Which may or may not be used.
>         2. Heuristics are particularly useful in search with real-world data, which has finite Markov blankets hence finite dependencies / mixing.
> 3. **Laws.** Conserved quantities can be learned aspects of the simulator (+library) itself
>     a. Like commutativity laws - these can reduce search & representation space by proving equivalence.
>         1. Particularly relevant with babble library learning <http://arxiv.org/abs/2212.04596>
>     b. Laws can be synthesized from ongoing interaction with the simulator.
> 4. **Algebra.** Other learned rules take the form of algebras -
>     a. rules for exactly & symbolically converting inputs to outputs
>     b. Aka 'solve rules' for exactly propagating information through a computational graph, per 2.b.1
> 5. **Lifting.** Computational compression requires re-use of programmatic structures:
>     a. Library calls, loops, recursion,
>         1. Often with guards / conditions.
>     b. This means a topological projection or loss-of-information during computation, e.g. the loop index or function calling context
>         1. Such variables are stored on the stack in typical environments.  In general they may be only weakly observed.
>         2. Inference of them may be through sorting, hard EM, propagation, or at the limit (again) search.
>             a. See the Sudoku experiment, where EM was used to infer what class a mutex belonged to.
>     c. Hence a pillar is to "unproject" or lift data with induced or introduced context, thereby forming fibers through which attribution can be traced.
> 6. **Abstraction.** A critical starting point for lifting is to move from base values to variables which can be substituted.
>     a. This is anti-unification, which forms the key method for variable introduction.
>     b. Anti-unification, like everything else here, is contextual, and depends on a frame or reference: *what* expressions are anti-unified into a LGG.
>         1. The cost structure remains the same: description length (DL).
> 7. **Partitioning & Locality**.  In many cases, there are an unlimited number of ways of deciding what expressions to anti-unify or build a library from.
>     a. Human search proceeds with some intrinsic metric of locality: data that is close in time or space.
>     b. This serves to bias any breadth-first search to local neighborhoods, and is reflective of the dependency structure of the real world: things generally don't depend on variables that are distant.
>     c. Locality can of course be bootstrapped: items that have a certificate for being co-local via search & computational validation can have induced locality (which, in turn, can be amortized / synthesized / explained through a subsequent synthesis step).
>         1. Or, vice-versa, locality can be imposed (via sorting), and equivalence checked.
>     d. Partitioning hence can be through basic equality (same types and/or values for each expression), through ordering, through basic computation.
>         1. Factoring is another matter (as happens with library learning over one graph).
>     e. Partitions form frames for recursive program synthesis.
>         1. They are hence a straightforward form of lifting followed by a conditional.
>         2. Aside: deep learning does this in pre- and statically- allocated high-dimensional space; critical here is that space is allocated on the stack, in the search tree.
> 8. **Recursion**. The program synthesis problem is recursive in several distinct ways:
>     a. Synthesis can proceed in stages: you solve a problem, which emits residuals or fiber indexes that need to be predicted; these serve as recursive target for another round of synthesis.
>         1. Sometimes early or first stages yield no compression, e.g. basis expansion to make a problem linear, so the full DL cost must be measured by the *full* path.
>     b. The search procedure itself is a program which emits an oft-repetitive computational graph.
>         1. Synthesis can proceed on the search tree and execution graph itself to derive messages about in accessible regions of solution space.
>             a. For example, when solving a hard Sudoku, following a strategic guess it's common to encounter chains of implication that indicate there are no possible solutions along that path.
>             b. In SAT solving, these take the form of CDCL clauses, unique implication points, or dual implication points; the latter permits the introduction of new variables.  We aim to analogously replicate these powerful methods here.
>         2. The messages, in the form of expressions, partition a given search problem.
>             a. Messages, like again everything else here, can be target for anti-unification / generalization / library learning, which lifts them out of the local problem context to be general for all problems - eg creation of a new (partial) conservation.   This is how CDCL and UIP / DIP was invented, afterall!
>         3. Other messages can simply be lossy condensations of the computation performed in a search branch, approximate expressions of "why this worked or didn't"
>             a. Aka heuristics.   The residuals they emit are discarded.
>             b. Which is why the computational cost is essential.
>     c. Recursion through library learning + local messages serves to partition exponential to super-exponential search space such that it's tractable in linear time - which is all we get in the real world.
> 9. **Vocabulary and language**. The combination of locality, analogy, and heuristic compression motivates the final element of the proposal: that of vocabulary and language development.
>     a. Viz: the names of functions are short, easy-to decode, heuristic / approximate descriptions of what the functions do. Without them, libraries and code are un-navigable.
>     b. Language is compositional, which means that the decoder needs to execute some variable time/space computation
>         1. But: it is not infinitely compositional like actual computer code, so that a fixed allocation of time or space is sufficient (like in a transformer).
>     c. This is a last goal/pillar of the research; like many of the preceding goals, it may be updated as the research is fleshed out.


**Aim.** Given observations indexed by time and/or space, learn a program that reconstructs them, or predicts specified outputs from supplied inputs, using a fixed simulator and a growing library. Measure description size, execution work, and the work of discovery. Investigate whether reusable structure, learned solve rules, and search feedback make related tasks substantially cheaper.

**Design principle.** Each pillar asks one question of the same small machinery. Establish a mechanism with a known answer, then hide the answer and test discovery. Add expressivity only when an experiment identifies why it is needed.

## Reading and implementation order

Milestone numbers match the nine pillars exactly. They identify research questions, not a requirement to finish every extension of one pillar before touching the next.

| Milestone | Research question | First decisive result |
|---|---|---|
| **1. Search** | Can we search, resume, verify, and price a transparent baseline? | A known solution remains reachable under increasing work and description limits |
| **2. Learned equivalence** | Can execution expose useful agreements and conserved quantities? | A useful observed agreement is retained with its scope; accidental agreement is rejected on new data |
| **3. Laws** | Can such findings become reusable rules about the simulator? | A checked finite-domain law helps another search and does not escape its domain |
| **4. Algebra** | Can solve rules be learned from forward experiments? | Addition inversion over GF(p), then integers, without inverse-value enumeration |
| **5. Lifting** | Can explicit context make a shared computation reconstruct its different instances? | One supplied lift and residual reconstruct all occurrences; missing context is exposed |
| **6. Abstraction** | Can variables and reusable patterns be recovered from known factorizations? | Typed AU, matching, and occurrence search pass separate positive controls |
| **7. Partitioning and locality** | Can useful contexts and correspondences be selected economically? | A discovered view pays for selection and reassembly; locality helps on a declared workload |
| **8. Recursion** | Can child synthesis improve both the model and the decisions that generated it? | Correct composition, scoped feedback, and measured reuse; later, useful learned preferences |
| **9. Vocabulary and language** | Can short compositional descriptions make a growing library easier to search? | A learned retrieval vocabulary improves total work over simple indexes |

**Recommended first pass:** implement the shared contract and milestone 1; immediately run milestone 6's tiny replay/matching/AU controls. Then run 2--4, in that order, with GF(p) before integers. Use 5 for supplied contexts, finish 6's hidden-occurrence tests, and use 7 to discover views. Integrate them in 8 before attempting 9. No general RL system, theorem prover, or natural-language model is a prerequisite.

The short experiment descriptions below are the work list. The shared contract and closing research decisions explain why the tests have these boundaries.

## Shared contract

### Meaning, representation, and availability

Start with a pure, deterministic, typed interpreter for tagged S-expressions. Each primitive has a signature, executable meaning, and metered cost. Errors are explicit; interrupted evaluation is unknown, not a semantic error or a proof of failure. The simulator defines executable meaning; observations define the requested behavior.

The initial arithmetic language contains +, *, equality for checking, variables, and literals. Add pairs, finite sequences, quoted ASTs, and first-order named definitions where their tests need them. Represent application uniformly as (app operator arguments); compatible operator symbols can occupy typed holes without introducing higher-order unification. Keep domain types explicit: a GF(p) value, an integer, an index, and a quoted expression are different objects.

The evaluator remains fixed within a comparison. New handwritten primitives, metadata operations, validators, or proposal shortcuts are declared changes to the prior. Initially omit binders, polymorphism, unrestricted generated recursion, e-graphs, and general graph matching. A synthesizer calling itself does not require its generated programs to recurse.

The only data frame is:

~~~text
Frame = (schema, rows)
Row   = (key, known, allowed)
~~~

The schema specifies types and the selected input/target columns. A row requires a predicted target to belong to its allowed set. Represent that set by explicit values or an executable membership predicate. Ordinary examples use singleton sets. Tuple-valued targets retain joint assignments: {(0,0),(1,1)} cannot be replaced by two independent copies of {0,1}.

Keys preserve occurrence identity and multiplicity; they are not automatic predictor inputs. Time and space coordinates can be declared inputs. Keep view programs, derivation records, and search records outside the rows.

Whole objects are also targets. One row with the entire original table as target supplies a literal compression baseline. A function-synthesis frame instead needs compatible outputs for identical inputs; a lookup is admissible only when the task permits it and its entries or witnesses are actually available.

**Reuse.** Recorded triples c=f(a,b) can support $(a,b)\to c$, $(a,c)\to b$, and $(b,c)\to a$ without rerunning the experiment. Input/output roles belong to the new question. Historical dependence of c on b does not make c unavailable when a new task supplies c to predict b. Multiple answers require a relation, not contradictory singleton function examples.

**No informational loops.** Discovery may inspect all recorded observations. A completed model may read only declared arguments, encoded model data and definitions, and values obtained through an executable decoding order. Reorientation creates a new question; decomposition must preserve the existing parent's interface. No helper may silently fetch an answer through a key, closure, provenance link, or live experiment-store pointer.

Explicitly encoded lookup tables, target-derived constants, and supplied constraint ASTs are legitimate inputs or model data when declared and priced. A training-only checker is not automatically a predictor input. Mutually defining two unavailable values does not supply either value: an iterative decoder needs initial information and executable steps.

### Reconstruction, fibers, and residuals

Let d reconstruct a parent target from available context c and a child value z. Let $\pi$ select or compute the child's available context. For parent requirement $A_i$, define:

$$
B_i(z)\ \Longleftrightarrow\ A_i(d(c_i,z)),
\qquad
\widehat y_i=d(c_i,g(\pi(c_i))).
$$

The child frame contains $(\mathit{key}_i, \pi(c_i), B_i)$. Its checker retains the parent requirement; its candidate g sees only $\pi(c_i)$. A successful child therefore yields a successful parent composition, subject to replay. The decoder, context program, and their costs are part of the model.

This predicate pullback requires forward evaluation only. It does not enumerate inverse values or require a finite semantic domain. Explicit finite fibers are optional test oracles; they are disabled in the required algebra bootstrap. Unknown emptiness remains unknown. A frame can also be inconsistent because individually nonempty requirements demand incompatible outputs from the same child input.

**Fiber** means the compatible values satisfying a requirement. **Residual** means the retained value, index, or other information needed to reconstruct a particular original. **Provenance** records where observations, constraints, and decisions came from. These are related but distinct.

If several holes or rows are coupled, retain a joint child requirement until conditional independence is justified. A reconstruction procedure that changes row count uses a block or whole-object contract. Selecting one acceptable inverse witness does not encode every original witness or occurrence.

A lossless quotient keeps a representative plus sufficient residual. A lossy summary may guide search while the exact state remains available. Discarding the original data's residual changes the reconstruction task and needs a separately declared approximation objective.

### One search and one return channel

Use an enumerator ordered by increasing finite description bound. Counting AST nodes alone is insufficient if every integer literal occupies one node: bound literal payload length too. Each finite bound must yield finitely many candidates.

~~~text
search(frame, limits):
    schedule direct programs and view/decoder proposals
    for each resumed proposal:
        if it is a complete program:
            check it across every required row; emit successful candidates
        otherwise:
            remember its parent decision, decoder, and input binding
            form the child predicate frame
            resume the same search on that child
            route each result to its originating decision
            compose each child candidate and recheck the parent
    report cutoffs, completed bounds, and any checked refutations
~~~

A seed pair proposes a pattern; all covered rows must still check. Partial coverage needs a guard, membership description, or literal remainder. AU, views, and arithmetic decoder contexts are proposal families, not separate acceptance mechanisms. Begin with one joint child tuple per proposal.

Jobs are resumable and metered. Retain a fair canonical search path when preferences are added; a fixed one-in-four share of work quanta is an initial convention to test. Limits must grow, jobs must advance, and evaluations must be interruptible for a coverage claim. Immediate repeated goals are deferred or rejected; cycle handling must preserve a route to deeper finite solutions.

A partial description may be larger than the incumbent. Accept compression gains after full composition; do not require each intermediate step to improve description length.

~~~text
Message = (call-id, claim, evidence)
~~~

The call identifies the originating goal, view/orientation/partition, decoder, input binding, assumptions, language, and relevant bounds. This uses search records rather than new row fields.

| Claim | Permitted effect |
|---|---|
| Candidate or scoped finding | Compose and check; propose to compatible goals |
| Conditional rule | Apply inside its established scope; recheck empirical proposals |
| Checked conflict or sound cost lower bound | Prune exactly the excluded continuations |
| Completed bounded exhaustion | Avoid repeating that completed bounded search |
| Cutoff or empirical utility | Retain unresolved work or adjust ordering |

A failed candidate does not refute all candidates for its decoder. A proof of an unsatisfiable child refutes the corresponding decomposition under its assumptions. Interrupted evaluation prevents an unqualified exhaustion claim. Late messages retain their original call; useful child findings can survive a failed parent.

### Cost and evidence

Use one published canonical encoding, initially serialized S-expression bytes with explicit literal payloads and fixed symbol allocation. Report:

- $S$: description size, including required definitions, residuals, selectors, guards, anchors, permutations, and reassembly.
- $W_{\rm run}$: completed-model execution work on the declared workload.
- $W_{\rm search}$: acquisition work, including simulation, failed proposals, matching, validation, indexing, scheduling, and later learning.

$$
J(M)=S(M)+S(E\mid M)+\lambda_{\rm run}W_{\rm run}(M),
\qquad
J_{\rm procedure}=J(M_{\rm best})+\lambda_{\rm search}W_{\rm search}.
$$

Count each original observation and required shared definition once at the declared task/batch boundary. Reorientation neither reruns a simulator experiment nor creates extra independent compression credit; new processing still costs work. Charge a residual once, whether inside M or in E given M. If compressing the entire store, encode its input columns, schema, and keys as well.

Initially meter interpreter operations, literal sizes, and tree visits; also report wall time. Unit-cost field arithmetic is acceptable only for fixed tiny primes. Integer-size growth and larger primes require a declared bit-sensitive tariff. Publish both a pure-description setting and a positive-work setting before comparisons.

Later learned cost estimates may guide proposals. Actual work remains measured; a learned coding scheme must provide an actual decoder and include its model cost. Do not silently change the objective while comparing policies.

Every result states: **replayed observations**, **exhaustive finite-domain validation**, or **proof under assumptions**. Exact AST spelling is a different equality from matching program outputs. Finite samples over integers justify conjectures and further testing, not unrestricted rewrite or pruning.

Every discovery test has a planted positive case, a nearby failure or ambiguity case, and a simple baseline. Keep the oracle recipe out of learner inputs. Record syntax/work bounds, seeds, vocabulary, and evidence scope. A mechanism can pass without demonstrating a speedup; report those outcomes separately.

## 1. Search

**Question.** Can a small, inspectable search find and price a known explanation, then resume when its initial budget is insufficient?

**Experiment.** Generate the complete GF(5) table for y=a+2b. Enumerate typed expressions over its declared variables, +, *, and field literals. Compare the best verified formula with literal storage. Interrupt the run before a planted solution is reached, then resume with larger description and work limits.

**Controls and exit.** Run the common contract checks below; recover an admissible solution and reproduce its costs. A contradictory same-input/different-output frame must not acquire a spurious predictor. A cutoff must remain resumable. Compare against an independent exhaustive reference only at a genuinely complete tiny bound.

| Contract check | Required observation |
|---|---|
| Reorientation and isolated replay | Earlier outputs may become supplied inputs; direct and indirect hidden-answer access fails |
| Explicit model data | A packaged, charged lookup can work; an undeclared store lookup cannot |
| Joint pullback | Predicate checking agrees with explicit fibers on tiny finite cases; correlated alternatives remain joint |
| Views and reconstruction | One supplied partition and one quotient-plus-residual restore multiplicity and order as required |
| Tiny syntax controls | Supplied substitutions reconstruct atoms, repeated holes, and typed operator holes |
| Work and scheduling | Failed work is counted; increasing limits retains access to a known deeper candidate |

**Reasoning.** Execution defines the reference meaning; it is not necessarily the cheapest equivalent computation. This experiment establishes a baseline from which shortcuts can be measured. It does not assume that all programs require exhaustive execution or that the shortest description is the fastest program.

## 2. Learned equivalence

**Question.** Can computed representations reveal useful agreements without confusing observed agreement with a general law?

**Experiment.** Over GF(5), record paired states under T(a,b)=(a+1,b+4), using starts with different sums, such as (0,0) and (0,1). Enumerate small expressions h and compare their output vectors. Seek an h with h(s)=h(T(s)) on the recorded pairs that also varies across starting states. The planted example is h(a,b)=a+b. Retain bounded alternative syntax for matching output vectors.

**Controls and exit.** Constant h is excluded from this particular informativeness test. Test fresh states. Separately give x and x*x only the inputs {0,1}, then add x=2: their initially matching buckets must split. Retain the recorded transitions for later questions without charging simulation again.

**Reasoning.** The result is a frame-scoped observation or invariant candidate. Conservation under a supplied transition does not identify a symmetry group. For this fixture, invariance is h(Ts)=h(s); a symmetry of dynamics F would require a specified action with an appropriate compatibility condition, such as F(gs)=gF(s). Inverse reasoning later reorients execution relations; it does not reverse causal interventions.

Empirical output buckets may prioritize search and suggest laws. Preserve syntax alternatives that may expose different abstractions. Globally deleting alternatives requires stronger equivalence evidence and a declared scope.

## 3. Laws

**Question.** Can agreements become checked, reusable rules about a specified simulator domain?

**Experiment.** Enumerate pairs of small expressions with free variables, using milestone 2's output buckets to propose equalities. Exhaustively check candidates over GF(5), then independently over GF(7). Recover simple identities such as a+b=b+a and a+0=a. Apply a checked rule in a second search and compare total work with the same search without that rule.

**Controls and exit.** Rule records state domain, types, guard, equality, and evidence. The equation $x^5=x$ is valid in GF(5) but must fail transfer to GF(7) and to integers; the power is shorthand for repeated multiplication, not a new primitive. A rule supported only on {0,1} must not become universal. Prevent rewrite cycles and retain bounded alternate syntax.

A law validated on total field values may be substituted into larger programs only when evaluation behavior is preserved. For example, dropping a subexpression that can error or diverge requires more than a value-level identity.

**Reasoning.** Learning the law and benefiting from it are separate results. A rule may reduce candidate work but cost more to check and apply. On integers, sample-based equalities remain conjectures unless a separate symbolic validator is introduced and its supplied mathematics declared.

babble uses an equational theory supplied to library learning; discovering that theory is our added research question [R7]. The least general generalizer and the shortest encoding are also different objectives: laws may expose patterns, while complete-description cost selects among them.

## 4. Algebra

**Question.** Can forward experiments bootstrap shared solve programs without a supplied inverse or per-example search over inverse values?

**Experiment A --- GF(p) first.** Generate triples c=a+b over GF(5), then GF(7). Reuse them as $(a,c)\to b$ examples. Supply only +, *, and field literals to the candidate program grammar. Equivalently check the relational requirement a+g(a,c)=c. One oracle solution form is g(a,c)=c+k*a with the appropriate field coefficient; do not supply that sketch during discovery. Reuse learned programs on fresh equations and validate them exhaustively over the declared field.

**Experiment B --- integers next.** Repeat with exact integer arithmetic and signed literals, including -1. Include negative, zero, and positive examples; evaluate held-out inputs far outside the training range. The planted solve rule is g(a,c)=c+(-1)*a. Test it as a library call on another batch.

**Controls and exit.** Disable inverse-value enumeration and supplied solve rules in both bootstrap runs. Program enumeration remains enabled. Reveal the oracle rule only in a separate positive-control run. Report discovery cost, reuse cost, and the scope of validation. GF(p)-only success does not pass milestone 4.

**Propagation test.** After validating the learned inverse q and uniqueness throughout a finite field, reuse it on a parent decoder y=a+z. Replace the child predicate $a_i+z=y_i$ by the equivalent singleton target $z=q(a_i,y_i)$. The child predictor still receives only its declared context, excluding $y_i$. Check equivalence through exhaustive forward validation; do not feed enumerated inverse answers into bootstrap search. A single witness for a multivalued relation is only a candidate, not the whole fiber. Integer samples alone do not license replacing the predicate by a supposedly equivalent singleton.

**Expressivity decision.** Test the multiplication relation a*b=c as a requirement, including zero and inconsistent cases. At a=c=0, every b is acceptable; different recorded b values must not become inconsistent singleton outputs for one deterministic input. Unsolvable inputs test rejection separately; a solver returning ``no solution'' requires an explicit output specification. For nonzero integer a, solutions require divisibility. Straight-line + and * with integer literals express polynomials, not general exact division: either defer that solver or explicitly admit iteration or a division operation. Do not label a supplied inverse as learned.

FlashMeta's supplied witness functions transform output requirements into operand requirements [R2]. Here the predicate supplies the requirement; the learner first discovers an acceptable-operand program, then tests a checked requirement simplification. Learning richer or more efficient requirement transformations is a later extension.

## 5. Lifting

**Question.** Can context and residuals make a shared computation account for distinct occurrences?

**Experiment.** Generate two short indexed sequences over GF(7):

$$
y_{j,t}=a_j+\iota(t),\qquad a_0=1,\quad a_1=3.
$$

Here j is a two-valued context tag, t is an index, and $\iota$ is the declared, metered conversion into GF(7). The parent receives (r,t), where r is an explicitly supplied occurrence coordinate, not an automatically exposed internal row key. First supply the map $r\to j$ and decoder $d((r,t),z)=\iota(t)+z$. The child receives j and predicts the shared offset $a_j$. Retain call/context links and reconstruct every occurrence; increase repetitions to test compression.

**Controls and exit.** Restrict the child to input t while retaining both sequences: identical t then requires different offsets. Restore its context through a supplied or encoded map $r\to j$, using the parent's available r, and charge the map. An encoded map without an available lookup key cannot repair the contradictory t-only frame. Target-derived assignments are usable during discovery, but deployment needs a computable selector or paid labels addressed by available context.

**Reasoning.** This tests a supplied lift before milestone 7 searches for one. Reuse does not inherently lose information; the issue is which context a particular representation retains. A fiber describes compatible child values, while the occurrence/call records carry attribution. An arbitrary latent label is not an explanation until its use, reconstruction, and cost are specified.

This finite instantiation test does not claim discovery of loops or general recursion. A later variable-length extension must state its iterator/recurrence language, bounds, anchors, and ordering costs. Hard EM is deferred until a bounded context search demonstrably needs it.

## 6. Abstraction

**Question.** Can the system recover variables, shared structure, and useful occurrences when a reconstructing factorization is known?

**Experiment.** Generate a tiny typed template p, substitutions $\theta_i$, and later wrappers and occurrence paths; construct $t_i=p[\theta_i]$. Keep the recipe as a hidden test oracle. Begin with atoms and single applications, then increase a published description-size bound.

| Reveal to the learner | Test |
|---|---|
| Pattern and substitutions | Exact reconstruction and full pricing |
| Pattern and source trees | Matching and substitution recovery |
| Aligned source trees | Syntactic AU and repeated-hole consistency |
| Whole trees, occurrence paths hidden | Correspondence discovery and abstraction selection |
| Optional validated alternate syntax | Whether a checked law exposes a better pattern |

Run the first three rows immediately after milestone 1, before depending on AU in open-ended experiments.

**Controls and exit.** Include varying atoms; compatible operator holes; repeated holes; subtrees under different wrappers; and an incompatible-type case. Incompatible signatures forbid that operator hole, not necessarily a more general whole-AST hole. For example, (+ 2 2) and (* 3 3) admit (?op ?x ?x); replacing the latter by (* 3 4) breaks the shared-hole pattern. Memoize repeated disagreement tuples so repeated holes retain the same binding.

Randomize planted templates and substitutions, rather than assuming arbitrary random ASTs contain compressible structure. Add unrelated trees as a separate control. Compare aligned AU with a tiny independent reference up to hole renaming. A planted template need not itself be the LGG: its substitutions may share additional structure.

The hidden recipe proves feasibility, not uniqueness, compression, or optimality. Accept alternative factorizations of equal or lower complete cost. Claim an optimum only within an independently exhausted encoding space. Tiny atoms need not compress; increase repetition for a compression-positive fixture. Count definitions, arguments, calls, wrappers, occurrence selection, and reassembly.

**Reasoning.** AU exposes substitution variables; it does not explain their values. The substitution tuple becomes a child target under the common reconstruction contract. Ordinary ordered-tree AU, occurrence search, and library selection remain separate operations. A general graph-isomorphism solver is unnecessary.

Stitch motivates structural abstraction search; babble motivates alternate syntax under validated laws [R3, R7]. Start with fixed syntactic AU and bounded alternative representatives. The Alpuente correction cautions against assuming unrestricted equational AU has a simple complete basis [R1]. Replacing c by (* 1 c) preserves behavior but not original AST spelling: exact syntax compression must retain the difference.

## 7. Partitioning and locality

**Question.** Can search find useful frames without spending more on selection and reconstruction than it saves?

**Experiment.** Reuse the indexed sequences and planted AST corpora. Supply a correct view first; then search a tiny published grammar of equality keys, simple guards, and orderings for it. For interleaved sequences, a candidate key may be parity of a supplied occurrence index; declare parity as a metadata primitive if used. Compare a single model, a partition with separate models, and a shared template with context-dependent arguments.

**Controls and exit.** Shuffle physical storage while preserving declared coordinates and occurrence keys: canonical replay must preserve results. Sorting an ordered object must retain an inverse permutation or another complete reconstruction recipe, including ties and multiplicity. Target-based grouping or sorting cannot be free runtime information.

For locality, place repeated structures nearby, then interleave them with unrelated structures. Compare canonical enumeration and locality-prioritized scheduling under identical candidates and total work, with a fair canonical reserve. Include a case where useful matches are distant. Record selection work and the complete encoding, not just the smaller per-part models.

**Reasoning.** A partition is disjoint and exhaustive over its selected occurrences. Windows may overlap; joins may duplicate rows; reorientation may preserve all rows. These are views, not necessarily partitions. Factoring shared AST fragments is another operation and need not partition observations.

Initially use supplied time/space distance as a scheduling prior. Later, a learned key or shared property may propose a new neighborhood; cost and validate that computation. A finite Markov neighborhood does not imply short mixing time or weak long-range dependence. Locality may guide search without proving that distant alternatives can be discarded.

If the correct view cannot be recovered in the bounded positive case, inspect the selector grammar and its costs before adding flexible clustering or latent assignment procedures.

## 8. Recursion

**Question.** Can the same synthesizer solve its own subproblems and turn their outcomes into useful information for future decisions?

Separate four tests. They share the kernel but have different evidence requirements.

### 8A. Recursive reconstruction

On the complete GF(7) table y=a+3b, first supply the two decoder choices as a mechanism control, then ask bounded search to find them:

$$
y=a+z,\qquad z=bk,\qquad k=3.
$$

The nested requirement is a+b*k=y. Rows with b=0 leave k unconstrained; other rows determine it. Check candidates through the predicate, without listing compatible k values. Use the same solver at both child calls; return alternatives rather than committing permanently to a locally cheapest child.

Repeat with milestone 4's learned singleton propagation enabled for the first child. Check that requirements remain equivalent and compare total work.

Record the full path's description and work. The first decoder plus a literal residual may be larger than literal storage; the final composition must still remain reachable. Compare with a direct enumerator using the same language, inputs, library, and work ledger. Success of the recursive trace does not by itself establish a speed advantage.

Also run one AU-generated child: abstract the coefficient in a compatible family of witnessed addition-solve programs for several primes. This mechanism control does not assume unconstrained discovery returns the same syntactic shape. Predict an integer representative $k_p$ from $p$, then instantiate and check each field program. Quote syntax to avoid pretending GF(5) and GF(7) share one runtime type. Metadata arithmetic supporting p+(-1) is declared prior knowledge. Transfer to another prime tests an instance, not a theorem for all primes.

### 8B. Backtracking, depth, and memory

Suspend and resume a child; revisit a completed bound with a larger bound; reclaim an abandoned branch. Cache identity includes the goal, input context, domain, language/library version, and relevant bounds. Retained results must retain their evidence or a replayable recipe.

Run two suspended calls over shared observations with different orientations or partitions. Backtrack before either returns. Each result must reach the correct continuation; transfer to another call requires a new binding and check. A useful child finding survives an unsuitable parent decoder.

Keep active jobs, original observations, incumbents, and deliberately retained results as GC roots. Eviction may cause repeated work; measure it. Do not require finite memory and permanent retention of every visited branch.

### 8C. Returning explanations

Return and reuse two small checked conflicts:

1. pair(z,z) cannot reconstruct pair(2,3), when pair is injective under the declared equality.
2. Rows requiring 2 and 3 cannot share a part if the child receives only that part identifier and must output one value per part.

Route each reason to the decoder or partition choice responsible. Use it to exclude a second family of branches. Confirm that separate holes, separate parts, and a richer admissible child context remain reachable. The contradiction for a genuinely constant-per-part model stays valid even when another model can use the same partition.

The general rule about unequal pair components needs the constructor argument; AU of failed traces alone is insufficient. A quotient that discards a component may invalidate the argument. Most semantic failures may still return only counterexamples or budget observations.

Later, name repeated explanation expressions with explicit definitions and test whether they improve reuse. CDCL/DIP and explanation-based integer constraint programming motivate this direction; provenance chronology alone is not an implication proof [R9, R10]. No SAT engine or general conflict learner is required for this gate.

### 8D. Learning search preferences

An action resumes one job for a fixed work quantum. Begin with cheap features: target type, proposal family, row-count bucket, residual depth, remaining-budget bucket, and declared locality class. These form a lossy observation, not an assertion of a sufficient or Markov state.

For compression tasks, let $B_t$ be the best completed root score and $W_t$ cumulative search work. Log:

$$
r_t=B_t-B_{t+1}-\lambda_{\rm search}(W_{t+1}-W_t),
\qquad
G_t=B_t-B_T-\lambda_{\rm search}(W_T-W_t).
$$

The first quantity gives a telescoping episode objective; the second credits the observed continuation after a decision. Neither invents a gain for an unfinished child. $G_t$ is not the decision's isolated causal contribution; sibling costs and later choices are included. A synthesis task without an admissible literal incumbent needs a separately declared bounded-success objective.

Compare, in order:

1. Canonical search with the declared locality preference.
2. A table of mean continuation returns, shrunk toward that baseline.
3. A short synthesized predictor using a declared metadata language of comparisons and conditionals.

For group k, the initial estimate is:

$$
\widehat G_k=\frac{\kappa G_{0,k}+\sum_{i:k_i=k}G_i}{\kappa+n_k}.
$$

Choose one $\kappa$ before comparison and report sensitivity. Sparse groups retain the prior. This is shrinkage, not calibrated uncertainty. A timeout informs success within its budget, not impossibility.

To reuse an exact synthesizer, encode heuristic training labels as prediction plus residual error; the deployed heuristic uses only the prediction. Discarding these heuristic errors does not discard the exact search state or relax answer verification.

Freeze the starting library and preference function per evaluation episode. In-episode candidate reuse, scoped messages, and exact caches remain active; initially promote new global definitions and learned parameters between episodes. Split training, validation, and evaluation by task families, not events in one trace. Rerun the entire search with comparable starting conditions.

Count feature extraction, policy inference, training, and library acquisition at a stated amortization horizon. Plot incumbent quality against work; identical final return does not distinguish early from late success. Keep the simpler estimator if a synthesized policy adds no held-out benefit [R4--R6].

**Exit for pillar 8.** Establish correct composition and communication first. Separately measure whether shared subproblems, explanations, or learned preferences save total work. Record distinct subproblems, repeated work, candidates checked, and branches excluded.

The intended factorization is conditional: k subproblems with n alternatives need not require $n^k$ joint trials when their validity and costs separate after fixing a small interface. Shared constraints must stay in that interface or a joint requirement. FlashFill's substring subproblems illustrate a language-specific factorization of this kind [R8]. No general exponential-to-linear guarantee follows from recursion or a compact representation.

## 9. Vocabulary and language

**Question.** Can learned, compositional descriptions help select useful programs from a growing library?

**Experiment.** Reuse the small functions and findings learned above. Assign exact opaque symbol IDs. Separately learn a tiny descriptor/ranking program from existing types, checked properties, and cheap behavioral probes, using 8D's measured search-return objective. Allow short compositions of descriptors. Queries are partial input-output specifications. Score any function satisfying the declared acceptance test; a hidden generating ID is a witness, not a mandatory retrieval target.

Start with shifts x+c, scalings c*x, and short compositions: the oracle knows these families, while different constants create descriptor collisions. First supply the descriptor rule as a positive control; then hide it. Evaluate on new queries and held-out compositions. Any held-out behavioral checks used to disambiguate queries must be declared in advance.

**Controls and exit.** Compare canonical ID order, simple structure/type/probe indexing, and learned descriptions at the same retrieval and verification budget. Randomly rename exact IDs to expose accidental lexical advantages. Include a complete-probe case where an exact signature index is sufficient. The learned vocabulary must beat these simpler baselines in total work, including descriptor learning and evaluation.

Descriptions rank candidates; execution checks them. If a description is used in an encoding, the decoder must resolve it to the exact intended definition and pay for any disambiguation. Charge the vocabulary and its decoder. Preserve a canonical search route when retrieval misses.

**Reasoning.** An identifier bound to a definition is exact. A description used to find that identifier can be approximate. This experiment studies the latter without assuming that human-readable naming emerges automatically.

LAPS shows that supplied natural-language annotations can help library learning and search; autonomous vocabulary induction is a different claim [R11]. Begin with symbolic descriptors. A richer language, learned descriptor grammar, or natural-language interface is a later decision if the small retrieval test succeeds. Bounded decoding is an explicit engineering choice, not a presumed property of natural language.

## Research decisions and stopping points

| Decision | Start here | Evidence needed to expand |
|---|---|---|
| Semantic equivalence | Scoped execution results; exhaustive checks on tiny finite domains | A recurring useful law is inaccessible without a declared proof or inverse procedure |
| Primitive expressivity | Tiny fixed typed language; signed integer literals when integers begin | A target is inexpressible, rather than merely hard to find |
| Context discovery | Supplied lift, then a bounded view grammar | A known positive case needs a reusable new selector or latent-variable method |
| Search factorization | Shared exact subproblems and small interfaces | Savings persist after all matching, indexing, and acquisition costs |
| Explanation reuse | Two checked structural/partition conflicts | Wider reason schemas can be validated and exclude repeated work safely |
| RL and calibration | Fixed actions, continuation logs, shrunk table | Delayed effects or sparse observations defeat the simple estimator on held-out tasks |
| Learned cost/codes | Fixed constructive accounting | A learned estimate improves decisions, or an actual learned codec saves net description |
| Vocabulary | Tiny descriptors and exact retrieval checks | Benefits exceed type/probe indexing and survive new compositions |

The most urgent theoretical questions are the validity scopes of learned explanations and the relationship between a compact heuristic, sparse evidence, and a changing search process. The most urgent empirical question is whether any discovered decomposition repays its additional work on the positive controls.

Use paired bounded replays to investigate decision credit before enlarging the RL model. Use adversarially ambiguous and nonlocal examples to investigate interfaces before enlarging the view language. A failed speed comparison is useful evidence; it is not repaired by adding machinery without identifying the missing capability.

## Translation from plan 3

| Earlier commitment | Location in plan 4 |
|---|---|
| Minimal frame, simulator hooks, joint constraints | Shared contract; milestone 1 |
| Experiment reuse and prevention of informational loops | Availability contract; 1 and 4 |
| Finite/predicate pullbacks, fibers, residuals | Reconstruction contract; 4, 5, and 8A |
| Positive AST controls and operator holes | 1 preflight; 6 before open-ended AU |
| GF(p) and integer bootstrap | 4A then 4B, both required |
| Cost ranking and temporary description increases | Cost contract; 1 and 8A |
| Ordering, partitions, quotients, locality | 1, 5, and 7 |
| Recursive parameter prediction and arithmetic trace | 8A |
| Backtracking, depth, garbage collection, late messages | Shared search contract; 8B |
| Scoped conflict learning and surviving child findings | Return channel; 8B--8C |
| Heuristic induction and lossy state summaries | 8D, then retrieval in 9 |

## Literature: one contribution and one boundary per source

**[R1] Alpuente, Escobar, Meseguer, and Sapi\~{n}a. _Order-sorted Equational Generalization Algorithm Revisited._** [Primary preprint](https://elp.webs.upv.es/papers/AMAI2021-preprint.pdf). The corrected account explains difficulties with identity axioms and conditions for finitary generalization. ``Nullary'' concerns absence of an appropriate minimal complete basis, not simply absence of any generalizer. It motivates caution about semantic AU, not a claim about the particular arithmetic fixtures.

**[R2] Polozov and Gulwani. _FlashMeta: A Framework for Inductive Program Synthesis_ (2015).** [Official paper page](https://www.microsoft.com/en-us/research/publication/flashmeta-framework-inductive-program-synthesis/). Witness functions propagate requirements to subexpressions; domain-specific inverse knowledge is supplied. Our generic predicate contract preserves requirements, while learning efficient solve programs remains a research goal.

**[R3] Bowers et al. _Top-Down Synthesis for Library Learning_ (2023), Stitch.** [Paper](https://mlb2251.github.io/stitch.pdf). Corpus-guided structural search finds useful abstractions. Its efficient rewriting of a corpus using a fixed abstraction does not make abstraction discovery or arbitrary synthesis linear-time.

**[R4] Minton. _Quantitative Results Concerning the Utility of Explanation-Based Learning_ (1988).** [Paper](https://cdn.aaai.org/AAAI/1988/AAAI88-100.pdf). Learned control knowledge can cost more to apply than it saves. Measure its utility including matching overhead; an observed trace alone is not a domain-theory explanation.

**[R5] Odena et al. _BUSTLE: Bottom-Up Program Synthesis Through Learning-Guided Exploration_ (2021).** [Paper](https://arxiv.org/pdf/2007.14381). Properties of executed values can guide candidate ordering. Lossy guidance does not justify exact-state merging or unverified pruning; a tiny synthesized policy is our proposed alternative.

**[R6] Orseau, Hutter, and Lelis. _Levin Tree Search with Context Models_ (2023).** [Paper](https://arxiv.org/pdf/2305.16945). Contextual policies motivate a small non-neural baseline. Its specified guarantees and fixed-trajectory loss do not automatically apply to our changing library or minimum-description objective.

**[R7] Cao et al. _babble: Learning Better Abstractions with E-Graphs and Anti-Unification_ (2023).** [Paper](https://arxiv.org/abs/2212.04596). A supplied equational theory exposes alternate syntax for abstraction. This supports combining laws and library learning; it does not establish autonomous law discovery or complete abstraction selection.

**[R8] Gulwani. _Automating String Processing in Spreadsheets Using Input-Output Examples_ (2011), FlashFill.** [Paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/popl11-synthesis.pdf). Compact candidate representations exploit the string language's particular decomposition. Comparable independence must be established in our frames; compactness alone does not make selection cheap.

**[R9] Buss, Chung, Ganesh, and Oliveras. _Extended Resolution Clause Learning via Dual Implication Points_ (2026).** [Paper](https://arxiv.org/pdf/2406.14190). Fresh definitions and clauses exploit explained implication structure. This motivates named reusable reasons; it does not turn unexplained failed attempts into proofs or guarantee easy proof discovery.

**[R10] Chu and Stuckey. _Structure Based Extended Resolution for Constraint Programming_ (2013).** [Paper](https://arxiv.org/pdf/1306.4418). Finite-domain integer propagators can supply explanations using richer named predicates. Maintaining their definitions and explanations costs work. This is a bridge beyond Boolean variables, not a solver for unrestricted integer synthesis.

**[R11] Wong et al. _Leveraging Language to Learn Program Abstractions and Search Heuristics_ (2021), LAPS.** [Paper](https://arxiv.org/pdf/2106.11053). Supplied language annotations guide library and search learning. This informs the optional descriptive channel; autonomous vocabulary emergence is not an established consequence.

## Required record for each experiment

Produce one short trace: **observations $\to$ declared frame/view $\to$ proposal $\to$ child requirement, if any $\to$ returned result $\to$ assembled model $\to$ replay $\to$ costs and evidence scope**. Include the originating decision and any message that changes a later branch. Keep oracle data visibly separate.

Alongside the trace, report the baseline, positive and negative controls, description/work limits, and one conclusion the experiment supports. This record is the standard of understanding; broader experiments follow only when it makes the relevant mechanism clear.
