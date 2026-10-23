# lisploop — plan 3

## A small recursive synthesizer that can learn how to search

Planning proposal, 2026-10-22. Supersedes the experimental scope of plan2.
This document specifies experiments; it does not report an implementation or successful results.
Revised 2026-10-23: integer bootstrapping without inverse-value enumeration; frame-local reorientation of experiments; known-factorization controls; and scoped child-to-parent messages.

**Aim.** Build a small generator of complexity: a synthesizer that can turn an unsuccessful direct search into a new, explicitly related synthesis problem, and eventually learn which such decisions are worth trying.

The first objective is understanding. Every demonstration should admit a short trace showing the observations, proposed transformation, child problem, completed decoder, and cost. Generality and speed are questions to investigate after that trace works.

The central separation is:

- **Representation:** what is observed, known, and required?
- **Construction:** what program or decomposition could satisfy that requirement?
- **Control:** which construction should receive the next unit of search?

All three can use tagged S-expressions. They do not thereby acquire the same semantics.

## 1. The irreducible starting machinery

Start with a typed, first-order expression language and a deterministic, metered interpreter. A primitive has a name, argument/result types, and executable meaning. Errors are explicit results of evaluation; divergence is interrupted by a work limit.

Provide only the following mechanisms:

| Mechanism | Initial form |
|---|---|
| Syntax and substitution | Tagged trees, typed holes, structural equality |
| Execution | Primitive evaluation with a work counter |
| Candidate generation | Enumeration by increasing expression size |
| Data organization | Explicit small programs for selecting, grouping, and joining rows |
| Abstraction | Ordinary syntactic anti-unification of aligned trees |
| Search | Resumable bounded jobs, backtracking, a literal fallback |
| Checking | Replay against observations; exhaustive checking on declared finite domains |

These mechanisms are prior knowledge. Listing them is more informative than claiming a knowledge-free learner. Every new handwritten primitive or proposal shortcut must join this list.

**Working interpretation of “omit operators.”** In milestone 1, provide addition and multiplication over both GF(P) and the integers, while withholding subtraction, division, and inverse as named synthesis primitives. Integer expressions admit signed integer literals, including -1; otherwise the desired subtraction program would be inexpressible in this grammar. Support operator-valued holes in the representation, but initially keep the operator vocabulary fixed. If “omit operators” meant hiding the operator labels in the observations, that is a separate identification experiment and is deferred.

The environment supplies the prime P. Field values and metadata integers are different types: P is not a nonzero element of GF(P). Supply ordinary metadata operations only when a demonstration actually needs them, and record their contribution to the prior.

Do not initially add polymorphism, binders, general recursive programs, e-graphs, a theorem prover, or a universal graph-matching engine. The synthesizer may call itself before its generated programs can recurse.

## 2. The frame: one small semantic object

A frame is a typed relation with a chosen prediction direction.

~~~text
Frame = (schema, rows)
Row   = (key, known, allowed)
~~~

The schema describes the types and selected columns of the known tuple and target tuple. These roles belong to this frame, not permanently to the stored observations. A row means:

> Given this known tuple, the predicted target tuple must belong to this allowed set.

Ordinary observations use singleton allowed sets. A relational inverse can have several acceptable answers. Represent an allowed set either by explicit values or by an executable predicate on a proposed target tuple. Both use the same membership-check interface; no extra frame field is needed. A predicate describes a requirement without computing its solutions.

For example, over GF(5):

~~~lisp
(frame
  ((known (a GF5) (c GF5)) (target (b GF5)))
  ((r0 (2 1) ((4)))
   (r1 (3 2) ((4)))))
~~~

This is the goal of predicting b from a and c in a + b = c. The observation key is an occurrence identifier, not an additional predictive feature. Repeated observations retain separate keys.

A target may be a tuple. Its allowed values are **joint assignments**. The set {(0,0), (1,1)} must not become two independent sets {0,1}: that would also admit the forbidden assignments (0,1) and (1,0).

Whole tables and sequences are also values. Exact storage compression can begin with one row whose target is the whole stored object; a literal constant then provides a fallback. Opening that object into elementwise prediction rows requires an explicit view and reassembly rule.

An ordinary function-synthesis frame can instead be inconsistent: rows with the same known tuple may have allowed sets with empty intersection. No deterministic predictor satisfies that frame. A literal lookup is admissible only when the frame is consistent and lookup is allowed by the task.

Three things stay outside the frame:

| Separate object | Meaning |
|---|---|
| View program | How rows and correspondences were assembled |
| Derivation record | Which observations and transformations support a result |
| Search record | Which branches were tried, their work, and their outcomes |

A physical list may contain all these objects, distinguished by tags. The core algorithm should not require every row to carry a query plan, uncertainty model, search score, proof status, and provenance graph.

### 2.1 What a decomposition child inherits

A child retains links to its parent observations and receives an explicitly selected known context. It uses the same interpreter and applicable type/domain assumptions.

It does **not** automatically inherit all parent columns as inputs. Some parent columns are precisely the answers being predicted. Other context is available only after an earlier decoding step.

Inherited information is therefore a projection with a contract, not a copy of every attribute. For sequential decoding, state the decoding order and charge the initial values. For an unordered table, a reference to another target does not become available merely because that target exists in the training data.

The search procedure may inspect the whole observed table when proposing a model. The completed decoder may inspect only its declared inputs, encoded constants/residuals, and previously decoded values.

### 2.2 Reusing experiments in another direction

An experiment such as c = f(a,b) records relational evidence, including its domain and execution provenance. Several frames may reference those same immutable observations:

| Question | Known columns | Target |
|---|---|---|
| Forward computation | a, b | c |
| Solve for the second argument | a, c | b |
| Solve for the first argument | b, c | a |

Input and output are roles in these questions. Reorientation does not require rerunning the simulator or copying the facts. It does not assert that every orientation has a unique solution.

Count a simulator experiment once when performed; subsequent views incur only the work actually done for selection, matching, or checking. Reorientation creates neither a new independent observation nor additional compression credit.

Distinguish two ways to create a frame. **Reorientation for invention** asks a new question of recorded facts and may choose any observed columns as its new supplied inputs. **Decomposition of an existing goal** must preserve that goal's runtime interface and reconstruction contract. An inverse rule learned in an auxiliary frame is a reusable result; it is not automatically a solution to the original goal until its arguments are available and its composition checks.

Availability starts at the current call boundary. In the inverse task (a,c) -> b, c is available even though its historical production depended on b. Following provenance and forbidding every descendant of the current target would incorrectly prevent inverse learning.

Instead, audit runtime dependencies. Replay receives only declared arguments, named library definitions, explicitly encoded model data, and earlier decoded values. A helper cannot silently follow a row or provenance pointer into the live experiment store to fetch an answer. A fixed lookup table is legitimate when included in the model or already-counted library, keyed by available inputs, and charged for storage and execution. Constants learned from targets are likewise permitted and counted.

A constraint expression may itself be a declared input when learning a solver. A training-only requirement checker is not automatically such an input.

Learned programs are not confined to their source frames. They may be proposed elsewhere with compatible signatures and assumptions. Their old evidence retains its validity scope; a program checked on one table is not thereby a universally valid rewrite.

## 3. Residuals are defined by a reconstruction program

Let a proposed decoder d reconstruct a parent target y from available context c and a child value z:

\[
y=d(c,z).
\]

For parent row i with allowed target set A_i, construct the child requirement

\[
B_i=\{z\in Z : d(c_i,z)\in A_i\}.
\]

Let pi(c) be the explicitly selected, computable child context; identity is the default. The child frame has rows (key_i, pi(c_i), B_i). Its checker retains the parent requirement, but its predictor receives only pi(c_i). Synthesize g satisfying these rows, then test the composition d(c,g(pi(c))) on the original parent.

The context program pi belongs to the originating call and assembled model; count its description and execution cost.

The domain Z must be stated, but it need not be finite. The default construction retains the requirement as a predicate:

\[
B_i(z)\ \Longleftrightarrow\ A_i(d(c_i,z)).
\]

Here A_i is interpreted as a membership predicate. To test a candidate child program g, evaluate d(c_i,g(pi(c_i))) and check the parent requirement. This uses forward execution only; it does not compute or enumerate compatible z values beforehand. On integers, exact + and * suffice for checking the corresponding equations.

Explicit finite fibers remain an optional representation and a useful test oracle. They are disabled in the required bootstrap runs of milestone 1. Learned solve programs may later produce compatible values directly. Search over candidate programs and constants remains; it is distinct from enumerating inverse values separately for every row.

The same equation applies to a joint block or whole-table target. A decoder that changes row count or couples rows must use that joint contract; it cannot silently treat the rows as independent. The required experiments below use rowwise arithmetic decoders.

This definition gives three immediately useful cases:

- A proven-empty B_i refutes this decoder under the stated domain.
- A known singleton B_i gives an ordinary child observation.
- A larger B_i gives genuine choice; one compatible value must still be produced.

With predicate requirements, cardinality and emptiness may be unknown. Failure to find a witness within a budget is not an emptiness proof.

A fiber is this set of compatible values. **Provenance is the derivation record explaining where the constraint came from.** Fibers can be linked through a derivation, but they are not themselves an account of which decisions caused success.

An address example makes the distinction concrete. If d(c,z) looks up position z in a known list, the fiber contains all positions whose contents match the target. Computing that fiber uses the observed target during synthesis. The deployed address program must predict a valid position from c; the fiber is not free side information at execution time.

This construction follows the inverse-specification lesson of FlashMeta [R2]. Retaining a predicate is a generic specification mechanism, not an efficient inverse solver. The bootstrap experiment asks whether searching for a shared program can turn those requirements into reusable solve rules.

### 3.1 AU is a particularly simple decomposition

Given aligned trees t_i, syntactic anti-unification produces a common pattern p and substitutions theta_i with

\[
p[\theta_i]=t_i.
\]

Pattern instantiation is the decoder. The substitutions become the child targets. Recursive synthesis tries to describe those substitutions from the available context.

For example:

~~~lisp
(+ c (* 4 a))
(+ c (* 6 a))
(+ c (* 10 a))
~~~

can produce

~~~lisp
(+ c (* ?K a))
~~~

and a child table with target values 4, 6, and 10. AU has exposed a parameter. It has not explained why the parameter changes.

Use a memo table for disagreement pairs so repeated disagreements become the same hole. Represent application uniformly as `(app operator arguments)`, with a type for the operator's signature. This permits an operator hole when the operators have compatible signatures. No higher-order unification is needed for this representation.

Initially AU acts on syntax already present in observations or witnessed candidate programs. AU on rows of unrelated ground numbers usually gives very general holes; it does not invent the arithmetic law hidden in the numbers.

### 3.2 Keep the AU kernel fixed as the simulator grows

Use syntactic AU throughout the initial experiments. If two programs are equivalent on a declared domain, retain a bounded collection of their alternative syntax and try AU on those alternatives.

This is incomplete semantic abstraction search, but its incompleteness is visible and adjustable through a budget. Adding a primitive requires a signature and evaluator; it need not require a new complete equational AU algorithm.

The corrected Alpuente results concern the existence and computation of suitable complete sets of equational generalizations, including difficulties introduced by identity axioms [R1]. “Nullary” does not simply mean that no generalizer exists: a common-typed fresh variable can still be a generalizer. The issue can be the absence of an appropriate minimal complete basis.

This does not remove the user's concern. Efficient semantic search may still need specialized knowledge. The experiment asks how far fixed syntax, execution, and learned shortcuts get before specialization pays for itself. Recording a shortcut as another expression makes it representable; it does not discover or justify it.

## 4. Frames, partitions, and quotients have different jobs

A view program constructs a frame from observations. It may select rows, join equal keys, align neighboring indices, or group by a computed value.

A partition is only one kind of view. Sliding windows overlap; joins may duplicate rows; a change of prediction direction may preserve every row. Preserve occurrence links instead of pretending every view is a partition of the original table.

For the first experiments, enumerate only explicit selectors and small key computations. Match ordered trees by ordinary pattern matching and tables by explicit joins. General graph isomorphism is unnecessary.

The operations to test separately are aligned tree AU, occurrence/correspondence search, and abstraction selection. Ordinary syntactic AU traverses aligned ordered trees. Stitch searches for useful corpus patterns; babble additionally searches equivalent syntax under a supplied theory; FlashFill represents and intersects families of candidate programs; FlashMeta propagates requirements to subprograms [R2, R3, R7, R8]. These are related mechanisms, not interchangeable graph-isomorphism algorithms. Milestone 0a isolates them before open-ended discovery.

A **lossless quotient** retains a representative plus enough residual information to reconstruct the original object. A partition used for compression must likewise explain its selector, membership labels, exceptions, and reassembly where those are not already known.

Grouping by an observed target is permitted during discovery. Using that grouping at prediction time requires a computable selector or an explicitly described label. Otherwise the grouping has exposed the answer.

A **lossy quotient** keeps only a summary. In milestone 3, this will describe the state seen by a search heuristic. The heuristic may ignore distinctions while the actual search state retains them.

## 5. The core search

The core has one recursive obligation:

> Propose a decoder, construct its child requirement, solve that requirement, and check the composition.

A direct candidate expression is the zero-child case. Literal data supplies a fallback for whole-object compression. For a function-synthesis goal, a literal lookup must meet the consistency and task-admissibility conditions above, and compatible witnesses must already be available. A predicate alone does not provide them. Neither fallback establishes predictive generalization.

Each bounded search job emits completed candidates. A parent must be able to resume the child for alternatives; committing permanently to the first or locally cheapest child can lose a better parent composition.

~~~text
search(goal, limits):
    if a literal candidate is admissible:
        emit candidate(literal_encoding(goal))

    for proposal in scheduled_proposals(goal, limits):
        if proposal is a complete program:
            if verifies(proposal, goal):
                emit candidate(proposal)
        else:
            call = remember_origin(goal, proposal)
            child = pull_back(goal, proposal.decoder, proposal.inputs)
            if child is not refuted:
                for message in search(child, smaller_limits):
                    route_to_origin(call, message)
                    if message contains a candidate g:
                        model = compose(proposal.decoder, g, proposal.inputs)
                        if verifies(model, goal):
                            emit candidate(model)

    also report scoped refutations, cutoffs, and completed bounds
~~~

This describes the logical recursion, not an uninterruptible nested loop. Every enumeration, pullback, evaluation, and child call is a resumable job. A concrete first implementation can use an explicit stack and increasing finite limits.

Search emits candidates and scoped outcome messages. Initially the extra outcomes are just cutoff and bounded exhaustion; checked structural refutations arrive in milestone 2b. Remembering the call origin is necessary before adding more elaborate feedback.

The first proposal families are:

1. Typed expressions of increasing size.
2. Explicit views and decoder contexts containing one unresolved child tuple.
3. AU patterns from aligned, witnessed syntax.

Generate decoder contexts from the same typed expression grammar by adding a distinguished child variable z of a declared type, including integers. Initially use one scalar or bounded-arity tuple z. Bound candidate syntax and evaluation work, not the semantic domain of z. Enumerate views only from the stated selectors and joins; an unrestricted language of table programs is deferred.

Multiple holes belong to the same child tuple until there is a justified conditional decomposition. Do not split correlated holes into independently solved problems.

Every admitted decoder context has a finite description and a declared child domain. Trivial “call the same goal again” contexts are skipped. More general repeated-goal detection includes known context, active language, and limits.

### 5.1 How this traverses the whole table

For each declared view and prediction direction:

1. Enumerate or retrieve candidate syntax.
2. Execute it across the frame's rows.
3. Use exact output vectors to find agreements and counterexamples.
4. For a proposed decomposition, construct the child constraint for **every** covered row.
5. Recurse on the child and replay the completed model on the parent.
6. Compare the resulting complete encoding of the original observations.

A seed pair can suggest a pattern. It does not exempt the remaining rows from checking. Partial coverage requires an explicit guard, partition, or literal remainder.

Start by evaluating each proposed complete encoding against a literal encoding of the entire task. This avoids a second, premature optimization problem over overlapping rules. Any combination of rules must specify dispatch and coverage, and pay for unexplained original observations.

Derived frames and generated facts may inform search. They do not count as additional independent observations whose repeated compression earns additional credit.

### 5.2 Acceptance and search order are separate

A partial decomposition can be larger and slower than the current description. Keep it while its search budget lasts. Accept an improvement only after its children complete and the assembled decoder verifies.

Backtracking is generic machinery, with a conditional coverage claim: it explores every expressible finite candidate only if branching is effectively enumerable, limits grow, work is preemptible, and scheduling is fair. It does not decide semantic equivalence or termination in general.

Keep a resumable canonical enumerator even after learning preferences. A simple initial convention is to allocate every fourth work quantum to it and the others to preferred jobs. The exact fraction is an experimental parameter. The canonical job must advance rather than restart.

Learned scores initially change order only. Pruning needs an independently sound contradiction or lower bound. A score estimating likely usefulness is neither.

### 5.3 Returning learned information to the originating decision

Each child call retains an immutable handle to the parent decision, its view/orientation/partition, the decoder, and the input binding. This is a reference into existing search records, not additional fields on every data row.

Use a small envelope:

~~~text
Message = (call-id, claim, evidence)
~~~

The claim's default scope is the referenced call: its goal, assumptions, domain, decoder, language, and relevant bounds. A broader rule explicitly states its parameters and conditions.

| Claim | What the recipient may do |
|---|---|
| Candidate or scoped finding | Compose and verify it; propose it to another compatible goal |
| Conditional rule | Apply within its stated validity scope; recheck if supported only by examples |
| Checked conflict or sound cost lower bound | Prune exactly the continuations excluded by the evidence |
| Bounded exhaustion | Avoid repeating the same fully completed bounded search |
| Cutoff or empirical utility observation | Retain unknown work or alter ordering; do not declare impossibility |

A candidate failing on one row rejects that candidate. Rejecting every child program for a decoder requires stronger evidence. Exhaustion must include execution limits when some evaluations were interrupted.

The reconstruction contract supplies the composition rule: if g satisfies every B_i at pi(c_i), then d(c_i,g(pi(c_i))) satisfies every A_i. Conversely, a proof that no admissible g can satisfy the child under assumptions Gamma rejects that decomposition under Gamma. It does not reject other decoders, contexts, partitions, or larger search bounds that the proof did not cover.

For example, d(z) = pair(z,z) cannot reconstruct pair(2,3) when pair is injective under the goal's declared equality: the shared hole would have to equal both 2 and 3. This checked contradiction rejects the shared-hole choice, while pair(z1,z2) remains possible. A partition proposing one constant per part encounters the same contradiction if it merges rows requiring 2 and 3. Its message must retain the constant-per-part/input-projection condition. The same partition may become viable with a child allowed to depend on additional distinguishing context; the contradiction for a genuinely constant-per-part model remains valid.

Return messages to their originating call even after backtracking. A late result may be cached but cannot attach to whichever partition is currently active. Exact-goal sharing may notify several waiting calls, each with its own binding and reconstruction check.

A useful child rule can survive a parent failure. Root compression acceptance controls the chosen complete model, not whether a scoped result is worth retaining. Scalar rewards and logical explanations are separate: ancestry records what happened, while a certificate establishes what must follow.

### 5.4 What search factorization is meant to accomplish

Measure distinct subproblems, repeated work, complete candidates examined, and branches excluded by checked explanations, alongside total work. Reusing subproblems, retaining factored candidate sets, and learning conditional conflicts are separate possible savings.

If k subproblems each have n alternatives and become independent after a small interface is fixed, solving them separately can avoid enumerating n^k combinations. When they share unresolved constraints, the interface or a joint requirement must carry those constraints. A compact representation of many candidates alone does not make selection cheap. The objective is demonstrable savings on structured families, without a general claim that arbitrary synthesis becomes logarithmic or polynomial.

## 6. Cost: description, execution, and acquisition

Use a constructive cost model and call its units what they are. Initially:

- S is serialized description size under one published S-expression encoding.
- W_run is metered work to execute the completed decoder on the declared workload.
- W_search is all metered work spent constructing, matching, evaluating, validating, and scheduling proposals, including failures.

For S, a simple reproducible encoding can be the UTF-8 byte length of canonical S-expressions with numeric symbol IDs and explicit literal payloads. This avoids treating an arbitrary large constant or quoted table as one cheap atom. Fix symbol allocation, serialization, and the initially supplied vocabulary before comparisons. This is an engineering description measure, not a claim to Kolmogorov complexity.

One completed explanation has score

\[
J(M)=S(M)+S(E\mid M)+\lambda_{\rm run}W_{\rm run}(M).
\]

E is the original observation set. Residual tables, selectors, guards, anchors, shapes, and new library definitions belong in the description. Count each required definition once at the declared task-batch boundary, and count its uses. Do not separately charge a residual both inside M and again in E given M.

The score is conditional on the declared root inputs and initially supplied interpreter. If the task is to compress the entire raw store, its input columns, keys, and schema also need an encoding or a generating recipe, counted once.

Satisfying a set-valued specification means producing one permitted witness. Lossless encoding must preserve every original observation and occurrence. Choosing one inverse value does not encode all alternative values for free; the residual account retains the required distinctions.

Compare search procedures through

\[
J(M_{\rm best})+\lambda_{\rm search}W_{\rm search}.
\]

Past search work is sunk when choosing between two already available descriptions. It matters when comparing the procedures that found them.

An evaluator execution during validation contributes to acquisition work. W_run estimates future use of the resulting decoder; it is a different accounting question.

Initially meter small interpreter operations and tree visits, using a published tariff. Report wall time alongside them. One arbitrary simulator call is not an adequate work unit. The tiny fixed-prime experiments may treat field operations as unit cost; scaling P requires revisiting that choice.

Always report the components (S, W_run, W_search). The lambda values express workload preferences, not universal conversion factors. Milestone 1a chooses and freezes them before comparing policies; include a pure-size setting and a positive-work setting. If conclusions reverse, report the tradeoff.

No logarithm of a choice rank is treated as a valid code without an actual decodable coding scheme.

## 7. The first use of recursion

Use two demonstrations, each with an inspectable trace.

### 7.1 Predicting substitutions

For several primes, solve a + b = c for b using only field + and * in the candidate language. A possible family of witnessed solutions is

\[
b=c+k_Pa.
\]

AU can expose k_P as a hole. The child problem asks how k_P depends on the environment.

Cross-prime AU operates on quoted program syntax, with the field domain recorded separately. The child predicts an integer representative; each instantiated expression is converted and checked in its own field. This is metalevel syntax manipulation, not a general polymorphic type system.

If the system proposes k_P = P - 1, explain the types and the prior: P - 1 is computed in metadata integers and converted to a field value. Supplying metadata subtraction has supplied relevant structure. An alternative is a bounded relational search for the representative k satisfying k + 1 = P, but that too has a declared metadata language.

Checking a few primes validates those instances, not a theorem for every prime. This example tests transfer of a common program shape and recursive parameter prediction.

### 7.2 A temporarily unprofitable transform

Use the complete table y = a + 3b in GF(7). The following four rows illustrate the construction; a run must check all 49 input pairs.

| Known (a,b) | Target y | Child z under y = a + z | Allowed k under z = b*k |
|---|---:|---:|---|
| (1,1) | 4 | 3 | {3} |
| (2,2) | 1 | 6 | {3} |
| (4,3) | 6 | 2 | {3} |
| (5,0) | 5 | 0 | {0,1,2,3,4,5,6} |

The trace is:

1. Propose decoder d1(a,b,z) = a + z. Pullback retains the requirement a + z = y; the displayed z table illustrates its solutions.
2. Call the same synthesizer on that table. It proposes d2(a,b,k) = b*k.
3. Pull back again. The composed predicate checks a + b*k = y. Every row with b nonzero requires k = 3; rows with b = 0 allow every field value. These fibers need not be enumerated to test a proposed k.
4. The second child returns the constant 3.
5. Compose to obtain z = 3b, then y = a + 3b.
6. Reconstruct the displayed targets as 4, 1, 6, and 5, and verify the full table.

Before either child is compressed, storing d1 plus a literal z lookup adds decoder syntax while keeping equally many one-digit field values and the same lookup keys. Its description is larger. The completed formula can replace the large lookup entirely. Record actual serialized size and work at each stage; the proposed trace is a constructed mechanism test, not a reported performance result.

This trace uses constructor proposals; the previous trace uses AU. Both use exactly the same pullback, recursive search, and composition mechanism.

A direct enumerator can find the formula too. Give it the same inputs, primitives, library, and total-work accounting. The first test establishes that recursive search can cross an intermediate cost increase; a separate comparison asks whether it helps.

Defer cubic finite differences. That example additionally needs index alignment, variable-length sequence handling, a scan decoder, anchors, and an efficient inverse procedure. Add it only after this scalar trace works.

## 8. Learning search preferences, before committing to RL

There are two different objects to learn:

- A program that explains observations.
- A program that predicts which bounded search action will be useful.

Both can be S-expressions evaluated by the same interpreter. They have different targets, evidence, and acceptance tests.

The second object is the route toward RL. Start with a decision log and a measured return; postpone a general RL architecture.

Only the log is needed before milestone 3. The estimator and policy options below are provisional research choices, not prerequisites for the earlier kernel.

### 8.1 A replayable action and a small observation

An action means “resume this proposal job for at most b work units.” Fix b initially. Freeze the starting language/library and learned preference function during each episode. In-episode candidate reuse, exact-goal caching, and checked scoped messages remain active. Initially promote new global definitions and update learned preference parameters between episodes.

The true state includes the goal, open decoders, pending jobs, limits, incumbent, and caches. A heuristic sees a cheap projection phi(s), initially just:

- Target type and proposal family.
- Coarse row count.
- Residual depth and remaining-budget bucket.
- A declared locality class, when meaningful.

This projection is intentionally lossy. It is not asserted to be Markov or sufficient.

Record the parent decision, observed features, chosen action, cumulative work, incumbent score, and outcome. The parent link explains how a child call contributed to a composed result; the chronological log also records the failed siblings paid for along the way.

### 8.2 Credit comes from completed root improvements

Let B_t be the score of the best completed, verified root explanation at decision t. The literal fallback supplies B_0 for a compression task.

Define

\[
r_t=B_t-B_{t+1}-\lambda_{\rm search}\Delta W_t.
\]

Then, without discounting,

\[
\sum_t r_t=B_0-B_T-\lambda_{\rm search}W_{\rm search}.
\]

A partial transformation receives no invented compression gain. It can still be useful because a later composed decoder improves the root incumbent.

At the end of the bounded episode, a decision at time t can receive the observed continuation return

\[
G_t=B_t-B_T-\lambda_{\rm search}(W_T-W_t).
\]

Do not finalize a child's credit when it returns; its effect may appear only when the parent is assembled.

This is a simple RL-style learning signal, without differentiation through the program interpreter. It is a return under the behavior that actually followed the decision, **not** the isolated causal contribution of that action. Sibling failures, later choices, and correlated samples remain research issues.

The telescoping objective does not prefer earlier success when final score and total work are identical. Record an incumbent-versus-work curve; add an explicit preference for early answers only if the experiment needs it.

For a pure synthesis specification where literal memorization is not an admissible solution, declare a bounded task-success objective separately. Do not treat fitting a finite training table as success on that stronger task.

### 8.3 First estimator: a small table

Begin with a count and return sum for each coarse context/action group k:

\[
\widehat G_k=
\frac{\kappa G_{0,k}+\sum_{i:k_i=k}G_i}{\kappa+n_k}.
\]

The prior score G_0 expresses the initial canonical/locality ordering; kappa controls shrinkage. Sparse groups stay near the prior. Start with one fixed kappa and treat sensitivity to it as a decision point.

This is sample-sensitive shrinkage, not a calibrated probability or a theorem about exploration. Keep training and evaluation splits at the task-family level; many events in one run are not independent tasks.

Distinguish:

| Outcome | Permitted conclusion |
|---|---|
| Verified improvement | This completed model improved the incumbent |
| Sound contradiction | This particular branch cannot meet the stated requirement |
| Exhausted bounded space | No solution in this explicit finite search space |
| Work limit reached | No qualifying result was found within this budget |

A timeout is a negative observation for “success within b,” but it is censored evidence about eventual success. It is never a permanent impossibility certificate.

### 8.4 Then synthesize a short heuristic

Once the table is a useful baseline, give the synthesizer a new task: predict returns or bounded-success labels from state features and actions.

Start with tiny piecewise-constant programs using comparisons, conditionals, and small integer constants. These require a declared metadata language. Do not start with a neural model, arbitrary policy recursion, or a learned representation of the entire search state.

There are two small implementation options:

1. Fit a predictor to quantized returns and explicitly describe the prediction errors.
2. Predict “improved by at least delta within b work” and fit a finite probabilistic table.

Choose one after inspecting the first traces. Such labels are noisy observations, not exact mathematical functions. A longer heuristic must earn its extra description and evaluation cost across multiple tasks.

If the initial synthesizer requires exact frames, model the training labels as “heuristic prediction plus literal error.” This reuses the existing decoder/child mechanism. At deployment the policy evaluates only the heuristic; its training residuals do not accompany it. A dedicated statistical learner is an alternative only if this exact-coding route proves too awkward.

Select candidates using training/validation tasks, then assess them on untouched task families by rerunning the **whole search**. Include policy inference, policy training, and library construction costs at an explicit amortization horizon. Predictive fit alone is not the deployment criterion.

Context models in Levin Tree Search provide evidence that learned search guidance need not begin with a deep network [R6]. Their guarantees do not transfer to arbitrary synthesized policies.

### 8.5 What lossy quotienting may discard

A heuristic partition phi may merge states and discard residual distinctions from its own input. The search continues to carry the exact states.

Thus

\[
\phi(s_1)=\phi(s_2)
\]

permits sharing a preference estimate. It does not establish that s_1 and s_2 have the same solutions, interchangeable continuations, or equal program semantics.

Merging exact search states, learned pruning, or accepting approximate answers would require additional contracts and experiments. They are not part of this milestone.

## 9. Milestones and exit decisions

Implement only what the current milestone needs. The intended result is a handful of readable demonstrations, not a broad benchmark suite.

| Milestone | Smallest experiment | Exit evidence |
|---|---|---|
| **0 — frames and simulator** | One finite relation, one partition, one lossless quotient, one AU substitution frame | Exact replay; joint constraints preserved; decoder cannot read withheld targets; all work is metered |
| **0a — known AST factorizations** | Tiny planted templates, substitutions, and occurrence paths; hide them in stages | Recover and reconstruct admissible factorizations; correct costs and repeated/operator holes; bounded reference answers |
| **1 — algebra over GF(P) and integers** | Forward-generated arithmetic examples; solve-rule synthesis with inverse-value enumeration disabled | Integer addition inverse learned from +, *, and signed literals; finite-field counterpart; reuse of learned rules; declared domains and representation limits |
| **1a — costs** | Compare literal, formula, and table-based descriptions under the same workload | Complete size/execution/search ledger; failed attempts included; published encoding, work tariff, and chosen tradeoffs |
| **2 — recursive calls** | Parameter child plus the two-stage arithmetic trace | Same solver for parent and child; full reconstruction; temporary cost increase; results return to the correct originating decision |
| **2a — backtracking, depth, GC** | Resume a cutoff; revisit with larger limits; reclaim abandoned branches | Deeper solutions remain reachable; late messages retain their scopes; no timeout becomes a false refutation |
| **2b — explanation reuse (later gate)** | One checked structural conflict and one partition conflict reused in another branch | A small reason excludes several impossible continuations without excluding a repaired context; useful findings survive parent failure |
| **3 — heuristic induction** | Canonical/locality order, shrunk table, then one short synthesized policy | Comparable frozen-policy runs on held-out task families; policy overhead included; lossy features do not change exact answers |

### 9.1 Milestone 0: the essential checks

Keep the unit tests semantic and small:

1. A partition is disjoint and exhaustive over the selected row occurrences; reassembly preserves multiplicity.
2. Quotient plus residual plus decoder reproduces the source.
3. Joint pullback preserves correlated alternatives; explicit finite fibers and predicate checks agree on tiny cases. A known-empty finite fiber is rejected, while an unresolved predicate remains unresolved.
4. AU substitutions reconstruct every source tree, including a repeated-hole case and a typed operator-hole case.
5. Reconstruction works with original target columns inaccessible.
6. Shuffling storage order preserves semantic results when an explicit canonical schedule is used.

Views that overlap are tested as views, not incorrectly subjected to the partition invariant.

Also check both sides of the runtime boundary: inverse learning may reuse a historically target-dependent input; indirect hidden-answer access must fail isolated replay. An explicitly packaged and charged lookup table must pass. This distinguishes legitimate reuse from an undeclared dependency.

### 9.2 Milestone 0a: witnessed factorizations before discovery

Generate corpora from a small typed template p and substitutions theta_i, retaining an independent oracle manifest with occurrence paths, wrappers, and the full reconstruction recipe. Begin with atoms and single applications. Increase a published AST-size bound gradually; random sampling extends these small fixtures, rather than replacing them with arbitrary trees that may contain no useful shared structure.

| Stage | Supplied to the learner | Question |
|---|---|---|
| Replay | Template and substitutions | Can the representation reconstruct and price the source? |
| Match | Template and source trees | Can matching recover substitutions? |
| Aligned AU | Corresponding source trees | Can AU recover their common structure? |
| Find occurrences | Whole trees, locations hidden | Can search find useful correspondences? |
| Semantic variants, optional | Tiny validated alternative sets | Can alternate syntax reveal a useful pattern? |

The manifest is a test oracle, not a predictor input. Keep five fixture families: varying atoms; compatible operator holes; repeated holes with correlated bindings; matching subtrees at different paths under different wrappers; and a supplied equivalent representative such as (* 1 c) for c. Include a case that breaks a repeated-hole equality and one with incompatible operator signatures.

Exact aligned AU is checked up to hole renaming against a tiny independent reference. Hole variation and distinct substitution columns are necessary checks for an intended pattern, but are not sufficient: substitutions may themselves share further structure. Establish identifiability before demanding the planted pattern exactly. A planted factorization establishes feasibility, not uniqueness, optimality, or a compression gain.

For the tiniest finite grammar and corpus, an independent exhaustive reference enumerates admissible patterns and encodings within a stated bound. Report reconstruction, correspondence recovery, found cost versus reference cost, and work. A different valid factorization of equal or lower cost is acceptable outside the uniquely identified AU cases. Claim bounded optimality only when the reference really covers the whole declared encoding space.

Count definitions, calls, wrappers, membership/reassembly information, and residuals. Tiny atom fixtures need not compress. For a compression-positive fixture, increase repetition until the measured complete planted encoding beats literal storage.

Semantic-variant tests must declare their target equality. Behaviorally equivalent programs can satisfy a semantic goal, but reconstructing the original AST spelling requires its residual or reconstruction recipe. Do not silently switch equality modes.

### 9.3 Milestone 1: deliberately modest algebra

**Required bootstrap path, in both domains.** Generate forward observations (a,b,c) by executing c = a + b. Reorient them to the synthesis task (a,c) -> b, withholding b from the predictor's inputs. These are already witnessed examples; no inverse operation is needed to create their targets. Alternatively, keep the requirement a + g(a,c) = c as a predicate and evaluate candidate programs directly. Disable inverse-value enumeration and supplied solve rules in these runs.

**Integers.** Use exact integer + and *, equality, and signed constants. The intended first result is g(a,c) = c + (-1)*a. Search discovers a shared expression; it does not scan possible b values for each example. Include negative, zero, and positive observations, then test on held-out inputs well outside the training range. Reuse the discovered expression on fresh equations and count all discovery and execution work.

Finite tests establish those instances only. A universal claim over integers needs a separate symbolic argument or verifier, whose supplied mathematical knowledge must be declared. Also search for a few polynomial identities by forward evaluation; agreement on integer samples is a conjecture, not permission for unrestricted semantic pruning.

**Finite fields.** Run the same bootstrap path for P = 5 and 7. Exhaustive forward validation is allowed: checking a proposed program on every input is different from obtaining its inverse answers by value enumeration. Test transfer to a further prime such as 11 after the protocol is fixed. An explicit-fiber implementation may be compared separately as an optional optimization; it cannot be necessary for the bootstrap result.

**Multiplication and expressivity.** Retain a*b = c as a predicate. In a field, b is unique when a is nonzero, arbitrary when a = c = 0, and nonexistent when a = 0 but c is nonzero. Over integers, a nonzero a also requires c to be divisible by a. Forward-generated triples cover only solvable inputs. Their recorded b values are valid singleton inverse targets only on a functional inverse region; at a = c = 0 use the relation rather than requiring every observed b as a separate singleton output.

Do not promise a general integer multiplication solver in a straight-line language containing only +, *, and integer literals. Such expressions are integer-coefficient polynomials and cannot express general exact division. Decide explicitly whether to admit a division primitive or suitable iteration, or keep general multiplicative inversion outside this first gate. Neither option is counted as having learned an unavailable operation from nothing. Guarded partial solving and reporting “no solution” also require explicit specifications.

Retain bounded alternative syntax within validated finite-domain equivalence buckets or explicitly labeled empirical-agreement buckets. Choosing one permitted witness remains distinct from losslessly encoding the original relation.

**Exit gate.** A learned integer addition solve rule and its finite-field counterpart must operate without a per-row inverse-value enumerator. Report whether the rule was checked on samples, exhaustively on a finite domain, or proved. The finite-field-only experiment does not satisfy milestone 1.

### 9.4 Milestone 2a: memory and backtracking

GC first reclaims unreachable, branch-local objects. Roots are the original observations, active/deferred jobs, incumbent model, and intentionally retained library results. Cached derived rows may be discarded if their recipes remain replayable.

Cache keys include goal, context, language/library version, and relevant limits. A record of bounded exhaustion carries its bound. Resuming a suspended job is different from declaring it impossible.

Detect active-stack cycles and preserve a route to deferred candidates. Finite memory, permanent retention of every visited branch, and infinite exploration cannot all be required simultaneously. If eviction causes repeated work, measure it.

Use a minimal trace now; elaborate retention policies wait until logs or caches actually cause a problem.

Check return routing with two suspended calls over shared observations but different orientations or partitions. Backtrack before one completes. Each result must reach its own continuation; transferring it to another goal requires the appropriate new binding and check.

### 9.5 Milestone 2b: one reusable explanation

Start with the shared-hole and constant-per-part contradictions in section 5.3. Return a small checked reason to the choice that caused it, then use that reason to avoid a second family of failing branches. Confirm that separate holes or additional legitimate context remain reachable. A failed child constant must not be mistaken for a refutation of its decoder.

The first generalized structural rule can say that unequal u,v cannot be represented as pair(z,z), provided pair is injective under the goal's declared equality. A quotient that discards a component need not preserve this argument. AU of failed traces may propose a generalization; it does not prove that generalization.

Later, repeated explanation expressions may receive fresh names with explicit definitions. DIP-based extended resolution offers a relevant example [R9], while explanation-based integer constraint propagation offers a bridge beyond Boolean variables [R10]. Neither an implication graph nor a proof is obtained merely by retaining provenance links. No SAT engine or DIP algorithm is required for this gate.

### 9.6 Milestone 3: stop if the simple estimator is sufficient

The decisive comparison is whether a short policy makes better use of the same total work than canonical/locality order and the empirical table. All methods share candidates, language, verification, and the fair-search reserve.

Include one unfamiliar task family and a small unrelated/random-table control. Report variability across tasks rather than demanding that chance compression never occur.

If the shrunk table works and the synthesized policy adds no benefit, keep the table. If neither works, inspect the state/action definition and delayed-credit problem before adding model capacity.

## 10. Research decisions to make from evidence

| Question | Initial decision | Evidence that warrants changing it |
|---|---|---|
| **How much semantic AU?** | Fixed syntactic AU plus bounded equivalent representatives | Repeated useful abstractions are inaccessible without a specific semantic law |
| **Which views and decoders?** | A tiny declared grammar, one joint child at a time | Missed tasks expose a reusable transform rather than a one-off patch |
| **Can inverse rules bootstrap?** | Predicate requirements and reoriented forward examples; inverse-value enumeration disabled in milestone 1 | A reusable solve program succeeds on new inputs; otherwise inspect search and expressivity separately |
| **What should a child inherit?** | Only explicitly available context and derivation links | A counterexample identifies a missing dependency; revise the interface and replay tests |
| **Can learned information return constructively?** | Origin-bound candidates and outcome messages; later, small checked conditional conflicts | The same explanation safely removes repeated branches; new names shorten reusable explanations enough to repay their cost |
| **What does computation cost?** | Published constructive tariffs; separate size, execution, acquisition | Rankings are dominated by a meter artifact or change with deployment workload |
| **How much search preference is learnable?** | Locality ordering, then shrunk context/action returns | Held-out savings exceed the cost of collecting and applying the preference |
| **When is RL needed?** | Observed continuation returns and bounded-action replay | Long delayed decisions defeat these estimators; paired replays expose systematic miscredit |
| **How should sparse evidence be calibrated?** | Shrinkage and task-family validation | Overconfident ranking on sparse groups persists; compare explicit bounded-success or uncertainty models |
| **Which distinctions can be discarded?** | Discard only from heuristic observations | Prove a stronger state equivalence before allowing exact-state merging or pruning |

The foremost open theoretical problem is the relationship between a short heuristic, its limited evidence, and its effect on a changing search process. Description penalties, shrinkage, and held-out trials are useful controls; they do not establish calibrated uncertainty or a universal learning rule.

The foremost empirical problem is simpler: does recursive decomposition expose enough reusable structure to repay the extra search? If that fails on the small traces, expanding the architecture is premature.

## 11. A short reading map

Each source contributes one lesson. None establishes the whole proposed pipeline.

**[R1] Alpuente, Escobar, Meseguer, and Sapiña. _Order-sorted Equational Generalization Algorithm Revisited._**  
[Primary preprint](https://elp.webs.upv.es/papers/AMAI2021-preprint.pdf). Use the corrected account of identity axioms, incompleteness of the earlier algorithm, and restrictions supporting finitary results. This motivates a fixed syntactic kernel and explicit semantic budgets; it does not imply that the particular finite-field experiment has a nullary AU theory.

**[R2] Polozov and Gulwani. _FlashMeta: A Framework for Inductive Program Synthesis_ (OOPSLA 2015).**  
[Paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2018/01/oopsla2015-flashmeta.pdf). The transferable idea is propagating an output requirement into requirements on subexpressions, preserving dependencies. Efficient inverse semantics are supplied by the DSL designer; the paper does not show that AU automatically learns them.

**[R3] Bowers et al. _Top-Down Synthesis for Library Learning_ (POPL 2023), Stitch.**  
[Paper](https://mlb2251.github.io/stitch.pdf). Structural abstraction proposals and their compression utility are separate search concerns. Its program-corpus setting motivates bounded, evidence-driven abstraction search; raw simulator tables require the additional execution and correspondence machinery specified here.

**[R4] Minton. _Quantitative Results Concerning the Utility of Explanation-Based Learning_ (AAAI 1988).**  
[Paper](https://cdn.aaai.org/AAAI/1988/AAAI88-100.pdf). Learned control knowledge can cost more to apply than it saves. Measure applicability, execution, and acquisition overhead. Explanation-based learning relies on a domain theory; an observed successful trace alone is not a proof of a general control rule.

**[R5] Odena et al. _BUSTLE: Bottom-Up Program Synthesis Through Learning-Guided Exploration_ (ICLR 2021).**  
[Paper](https://arxiv.org/pdf/2007.14381). Compact properties of intermediate values can guide search, and model-evaluation overhead matters. A lossy feature signature can guide an exact synthesis procedure. Replacing its trained model with a tiny synthesized S-expression is our experimental proposal.

**[R6] Orseau, Hutter, and Lelis. _Levin Tree Search with Context Models_ (IJCAI 2023).**  
[Paper](https://arxiv.org/pdf/2305.16945). Contextual probability models offer a concrete alternative to deep policy networks. Its convex-loss result concerns its specified model and fixed solution trajectories; its satisficing search objective is not automatically our minimum-description objective.

**[R7] Cao et al. _babble: Learning Better Abstractions with E-Graphs and Anti-unification_ (POPL 2023).**  
[Paper](https://cseweb.ucsd.edu/~npolikarpova/publications/popl23.pdf). Uses a supplied equational theory, e-graphs, and AU to propose library abstractions. This motivates the optional semantic-variant control. It does not require the initial kernel to implement equality saturation or make abstraction selection universally complete.

**[R8] Gulwani. _Automating String Processing in Spreadsheets Using Input-Output Examples_ (POPL 2011), the FlashFill line of work.**  
[Paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/popl11-synthesis.pdf). Compact DAG representations and intersection retain many candidate programs without listing every combination. The decomposition exploits its string-language structure; comparable independence must be established in our frames.

**[R9] Buss, Chung, Ganesh, and Oliveras. _Extended Resolution Clause Learning via Dual Implication Points_ (LMCS 2026).**  
[Paper](https://arxiv.org/pdf/2406.14190). Introduces fresh Boolean definitions for separating literal pairs and learns clauses using explained implications. The transferable lesson is to retain reasons and consider names that make those reasons reusable; a chronology of failed attempts cannot substitute for logical justification.

**[R10] Chu and Stuckey. _Structure Based Extended Resolution for Constraint Programming_ (2013).**  
[Paper](https://arxiv.org/pdf/1306.4418). Finite-domain integer propagators explain deductions, and richer named predicates can strengthen those explanations. Their definitions and propagation have costs and correctness obligations. This is motivation for later typed explanation reuse, not a solver for arbitrary integer program synthesis.

**Optional for milestone 1a:** Orseau and Lelis, _Policy-Guided Heuristic Search with Guarantees_ (AAAI 2021), [paper](https://arxiv.org/pdf/2103.11505). Read for the distinction between successful-path cost and total search effort. Implementing that algorithm is not an initial milestone.

## 12. The first deliverable

Before broad experiments, produce one complete human-readable transcript:

~~~text
original frame
view and declared known context
candidate decoder
child frame, including any ambiguous joint values
recursive candidate
assembled decoder
reconstruction check
description / execution / search costs
decision links and final observed returns
scoped child messages and the parent choices they affect
~~~

That transcript is the standard of understanding for the project. New machinery should make a demonstrated part of it more general, cheaper, or easier to express.

