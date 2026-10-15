# lisploop --- program synthesis from conserved quantities, lifts, and learned inverses --- plan

Planning document, 2026-10-14. New subdirectory `team/tlh/lisploop`.
Background, cited by short name: `../arc1/plan.md` (*ARC1*, with its
section numbers), `../sudoku/antiunify-notes.md` (*Notes*),
`../symbreg/plan.md` (*symbreg*). Nothing is implemented. While writing,
five small throwaway python checks were run in the session's scratch
directory (not in the repo); their numbers are in \S4 and are marked
"checked" where used.

The prompt that motivated this document, verbatim. The circled numerals
and en dashes are transliterated to ASCII for pdflatex, the URL is wrapped
in angle brackets so that it renders as a link, and blank lines are added
before the two lists so that they render as lists:

> I'm looking to experiment with approaches to program synthesis using a
> combination of experimentation, simulator execution, and anti-unification
> in computed spaces.
> Program synthesis is broadly the task of converting raw data (which may be
> input-output data, or just output data) to a executable that, when run,
> reproduces the data (perhaps approximately).  As a program can be
> represented as a DAG (the actual execution trace does permit cycles/loops),
> this process can be broken into sub-tasks of filling in holes in the graph
> (and possible re-representing the DAG or execution trace, but more on that
> later).  [For this task, also assume that both output and input (if
> provided) data are indexed by at least one axis, e.g. time or space.  This
> is important as search needs some initial essence of locality to reduce
> BFS.]
>
> Holes are either variables or operators on those variables; the messages
> between them, along the edges, are deterministic.  When given data, these
> are directly outputs of some number of operations and variables, and so
> the task is to infer operators and variables from the limited data
> available in the output.  This is a highly underspecificed problem, and
> yet humans are competent at it - so it's certainly possible.
>
> This is where experimentation, enumeration, and inference of inverses (or
> inference of inference algorithms) come in.  Any given operator in the base
> language - take arithmetic, for example - can be run repeatedly on inputs
> while observing the output.  You could use the resulting table (which will
> have to be instantiated) to directly infer operations and arguments based
> on indexing from the output - this is memory-based inversion, and it
> generally works, though would suffer horribly here due to geometric
> scaling and non-injectivity.  Instead, we should take the experimental
> outputs as direct targets (inputs) for a recursive call of the program
> synthesis pipeline, only with the input and output transposed.  That is,
> rather than taking an operation and arguments, performing the computation
> to produce output, you take the outputs and possible inputs, and do
> different computation to infer the operations and inputs.
>
> This is "something like" Noether's theorem, albeit for discrete domains,
> with discrete operators / actions - observation of conserved quantities and
> symmetries inform, usually incompletely, the search for the expressions
> that generate them.  Namely, to solve a program synthesis problem you can
> enumerate possible DAGs, simulate them on the inputs, and compare their
> outputs to the desired outputs.  This will work, but will be very slow.  A
> second way to attack the problem is to look for conserved quantities in the
> output or input-output pairing, then do algebra to convert this (possibly
> partly) acausal graph to a causal program.  For example, if the outputs is
> 2, 4, 6, 8, 10 ... the conserved quantities approach would be to try out
> all the elementary operators, with the arguments selected based on
> proximity (which is why indexing is important, per above).  The result is
> that the difference (a constant op) between successive terms (need to avoid
> trivial expressions, e.g. same term) is always 2 (a constant).  We can find
> these low-description length expressions via straightforward clustering
> (constants) and/or anti-unification (shared variables) in the
> computationally expanded space.  Here clustering is perfect, though
> allowance should be made for adding residuals, provided they do not exceed
> the DL of the original sequence; this sort of approach is applied well in
> <https://link.springer.com/10.1007/978-3-662-54577-5_18> - value
> expressions are the leaves on a decision tree, and the decisions are made
> based on boolean expressions).  Then the trick is to convert these observed
> conserved quantities to a generative model, or in general to restrict the
> hypothesis space of plausible generative models via the symmetries induced
> by the conserved expression.
>
> Exact conversion from conserved model to generative model includes algebra
> (& if the domain where continuous, calculus).  Non-exact inference or
> restriction is more broadly the domain of inference, which spills out onto
> enumeration as mentioned above.  Any program synthesis engine needs to
> accommodate a range algorithms along this axis.  At one end, to learn
> algebraic operations, relabel one output as an input, and look for
> expressions that anti-unify the new expression with constant operators (I
> say anti-unification b/c you keep around symbols, not base values!).  For
> example, with no knowledge of what a + b = c means, you can run many
> experiments with various a and b to see what results.  This is a very tiny
> generative model.  Then you do the same for all the other elementary
> operators in the toolbox, including negation, up to (say) depth=2 (this is
> essential!).  Now, to figure out how to do algebra / rearrangement, swap b
> and c as inputs / outputs, look for instances in the expanded table of
> experiments where the substituted values match exactly under a different
> operator, or tree of operators (needed: if a + b = c then a - c = -b..).
> Done correctly, this even enables the inference of new operators that 'look
> like' expansions: if we operate over GF(59), and subtraction is omitted,
> then a suitable inverse can still be found: c + 58a = b.  Showing that this
> can be inferred is a first step.  This entails learning and representing
> substitution rules and are one level of abstraction removed from the base
> computations, as well as learning properties (and rules) like commutativity
> -- a + b = b + a, always -- that take the search from applying base
> computation operators to applying rules to symbolic expressions.
>
> Yet these expressions often have holes; algebra becomes partial inference.
> The next step would be to permit residuals and references in the conserved
> expressions, and let these be the targets for the next level of synthesis.
> This demands a form of lifting those residuals: if observed symmetry
> indicates the presence of a loop, then that loop indexing variable is
> tagged onto (as in: list, tuple) the residual data, just like the
> time/space is tagged on to supplied input and output data.  In the case of
> ARC-AGI-1 puzzles, 'residuals' often ultimately reduce to references to
> input data, and the composite transformation involves transforming the
> indexes that make up the references.  Hence, when running the synthesis
> pipeline, you roll out the conserved-quantity search including the
> referencing operator with say constant values (base values) as the index,
> and then take the indexes as targets for anti-unification, under a shallow
> computational budget.  For example, instead of equating coordinates, you
> equate values (colors in the case of ARC) and find which
> indexes/coordinates lead to them, given input data.  This demands a more
> complicated (meta) inference algorithm, that keeps track of expansions and
> tries to 'meet in the middle': equating values yields a set of input
> indexes and a set of output indexes; which input corresponds to which
> output (a mapping that might not be bijective!) is unknown, and has to be
> inferred from contextutal tagged information.
>
> The partial inference stage is still a sketch, and I'll need your help +
> experimentation to refine the ideas.  Critical is iterating over a model of
> the data with a MDL bound, and learning algebra and inverses from
> interaction.
> Generally:
>
> (1) You are given input and output, tagged with structural information
>     (time, space, example number etc).
> (2) Run a fixed-prior 'computational expansion' that applies limited-depth
>     basic operators (arithmetic, indexing/referencing, variables,
>     constants, booleans, and branches/guards - loops through map() ) in
>     order to look for conserved quantities, via basic clustering or
>     anti-unification.\
>     -- This solves the timeseries example above by calculation
>     (x[i] - x[i-1] = 2), not enumeration.\
>     -- I don't think there is any shortcut to this particular computation,
>     though symmetries in the computational structure itself (e.g.
>     commutativity, algebra) can and should reduce the expansion.\
>     -- As mentioned above, we want to learn these symmetries, and use them
>     to reduce the search space.\
>     -- A lightweight built-in type system can also be used to bound the
>     search space.
> (3) If no exactly conserved expressions are found, permit
>     intermediate-expression residuals that have symmetry or
>     conserved-quantity aware tags or lifts, enabling the next round of
>     recursive synthesis to proceed on a reduced target.  At the limit, we
>     have to permit bare residuals to permanently stay in the tree (bare
>     facts, so to speak).
> (4) Do algebra or inference to convert (partly) conserved expressions into
>     generative equations.  Learning this is the target of the 'exact
>     conversion' above, seeded from experimentation.
>
> Let's prototype this in a lisp - common lisp seems OK to me, though Scheme
> and Racket are also OK.  (sbcl and mit-scheme are installed on this
> computer).
> Before that is to happen, I'd like the plan to be thoroughly walked over so
> that we can resolve any conceptual holes.
>
> * Among many others are the need to induce datastructures more complex
>   than bare variables; I surmise this can be handled through computed and
>   algebraic addressing schemes on lifted/augmented data, but that remains
>   to be determined
> * There are a *lot* of details wrt handling expression-value provenance,
>   finding exact covers for the data in the clusters / anti-unifications,
>   and managing time-memory tradeoffs in backtracking search on base and
>   progressively more abstracted rules ... one bridge at a time.
> * -- For example, it may be advantageous to use a e-graph or version space
>   to exploit learned symmetries and equivalence rewrite rules; these are a
>   heavy import that nonetheless may be worthwhile.
> * -- Likewise, Stitch (Bowers 2023) leverages top-down synthesis with
>   pruning to eliminate impossible refactorings; the equivalent here is to
>   eliminate expressions (both for generative and conserved quantities)
>   that either cannot be better than the current best, or are subsumed by
>   another hypothesis.
> * Goal is to start as absolutely minimally as possible, and be very
>   deliberate; do not implement code without letting me read a plan.  Keep
>   consistent with the protocol in the other experiments in this repo -
>   latex-compatible markdown, etc. (This is a new subdir in the sandbox
>   repo)

---

## 0. Summary

**Problem.** Data are indexed by at least one axis (time, space, example
number). Find a program whose forward execution reproduces them, minimizing
$\mathrm{DL}(\text{program}) + \mathrm{DL}(\text{data} \mid \text{program})$.
A program is a DAG of variables and operators. A loop unrolls along an axis,
so the execution trace of a recurrence is a table with one row per
iteration. Filling the holes means finding the operators (expressions) and
the variables (latent values).

**Claims, to be tested in order.**

1. *One engine yields three kinds of finding.* A bounded computational
   expansion is all typed expressions up to depth 2 over references near
   each row, index tags and constants. Evaluate them row by row into value
   vectors and hash those vectors into buckets of expressions that agree on
   the data. The buckets then give three kinds of finding from one data
   structure: *explicit generators* (`x[i] = x[i-1] + 2`, from the
   unknown's own bucket), *conserved quantities* (`x[i] - x[i-1] = 2`, from
   constant buckets), and *implicit equations* (any bucket holding both an
   expression of the unknown and one free of it). All three say that the
   data lie on a level set of a short expression, and one quantity scores
   them all.
2. *Fibers decide what is informative.* The bits a finding saves are
   $\sum_r (\log_2 \lvert D \rvert - \log_2 \lvert F_r \rvert)$. Here $F_r$ is
   the *fiber*: the set of values the unknown at row $r$ could take, given
   the finding and the rows already decoded. An identity such as
   `x - x = 0` has $F_r = D$ and saves nothing. A generator has singleton
   fibers. A partial relation has intermediate fibers, and its fiber index
   is a residual. No syntactic triviality filter is needed. The null model
   is the raw code's own model (iid uniform over $D$), and "also holds on
   null data" is a cheap pre-filter for identities.
3. *Turning a conserved quantity into a generator is a fiber computation.*
   Computing $F_r$ symbolically means solving the finding for the unknown
   by isolation with *solve rules* (inverses). Solve rules are learned by
   running the same engine on operator experiment tables, with the input
   and output roles transposed: the recursion the prompt asks for.
   Checked: in GF(59) with only $+$ and $\times$, the transposed table of
   $+$ gives $b = c + 58a$ at depth 2.
4. *Anti-unification produces lifted residuals.* When instances (rows,
   examples, fields) share structure but differ in a constant, their least
   general generalization is a template with a hole. The hole's
   substitutions, tagged with each instance's index, form a new frame,
   which is the target of the next recursive call. Value clustering within
   one frame is the special case where all instances share a domain.
5. *A program is a decision list* of guarded findings, lifts and bare facts.
   It is accepted under an MDL bound and verified by forward execution (the
   simulator), never by fit statistics alone.

**Design principle.** Every symbolic shortcut has an enumeration fallback
over a finite domain, and the fallback's results are the training data for
the shortcut. Enumeration teaches the algebra. In the bootstrap everything
is enumeration, and as rules are learned it recedes. This is the
"range of algorithms along this axis" of the prompt, made into a schedule.

**Deliberately absent at the start.** No SAT, no e-graph, no learned
priors, no ARC. The first two milestones (\S9) are a one-dimensional engine
and the algebra-by-experiment loop. Each later structure enters only after
a measurement says it is needed (\S7.6).

**Language.** SBCL Common Lisp with no dependencies (\S8).

---

## 1. Objects and vocabulary

### 1.1 Values and domains

A *domain* fixes the value set and the operator semantics. Four are used:

- GF($p$), with all operators taken mod $p$;
- integers, with exact arithmetic inside expressions and a bounded coding
  range $D = [lo, hi)$ sent in a header;
- booleans (comparison results), used at first only in guards;
- categorical values (colors, equality only), not needed before M5.

A distinguished value $\bot$ marks anything undefined: a reference past the
edge of the data, or a partial operator outside its domain. Operators are
strict in $\bot$.

### 1.2 Frames

A *frame* is a table. Each row carries *tags*, its index tuple: `i`, or
`(e, i)`, or `(e, y, x)`, or an experiment's argument tuple `(a, b)`. Each
column has a role. *Given* columns (inputs, tags, experiment arguments) are
never coded. *Coded* columns are the data to be explained. Rows may be
partitioned into *groups* (examples), and references never cross a group
boundary. Every frame records its lineage: its parent frame and how it was
derived (`:data`, `:transpose`, `:lift E`, `:reindex sigma`, `:group-by E`,
`:join`).

| frame | rows (tags) | given | coded |
|---|---|---|---|
| one sequence | `i = 0..n-1` | `i` | `x` |
| several sequences | `(e, i)` | `e, i` | `x` |
| list input-output pairs | `(e, i)` | `e, i, in` | `out` |
| an operator's experiments | `(a, b)` over the domain | `a, b` | `c = f(a, b)` |
| the same, transposed | `(a, b)` | `a, c` | `b` |
| a lifted residual | parent rows where $E$ is defined | parent tags | `v = E` |

A recurrence is a cycle in the program DAG that becomes acyclic once it is
unrolled along the axis, and its unrolled trace is a frame. The prompt's
"re-representing the DAG or execution trace" means, concretely, deriving a
new frame (\S5.7).

### 1.3 Expressions

Expressions are s-expressions over a typed grammar.

*Leaves:*

- references `(@ x k)`: column `x` at row $i + k$ along the axis, with
  $k \in \{0, -1, -2\}$ at first. This is the locality the prompt
  requires. `x0, x1, x2` abbreviate `(@ x 0), (@ x -1), (@ x -2)`.
- tags: `i`, and the length `n`;
- small integer literals;
- *holes* `?k`: constants fitted to the data (\S5.3).

*Operators:* the domain's base set, kept incomplete on purpose. The GF($p$)
runs omit subtraction and division (\S5.9).

Each expansion has depth at most 2 ("this is essential", says the prompt).
Size is the node count. $\mathrm{DL}(E)$ is a prefix code under a uniform
grammar, $\mathrm{size}(E) \cdot \log_2(\#\text{symbols})$, with priors
later (\S9, after M3).

### 1.4 Value vectors and buckets

Every expression $E$ in the expansion is evaluated at every row, giving a
value vector $v_E$. Expressions are bucketed by $v_E$ restricted to the
*hash rows*, which are interior rows: rows where every leaf of the window
is defined. A short sequence hashes all of its interior rows. An
experiment table hashes a fixed sample of 64, and every hit is then
checked on all rows (sample, hash, verify, \S7.1).

One representative per bucket (the smallest) is used to build larger
expressions. This is observational equivalence on the data, as in
bottom-up enumerative synthesis. Every collision with an existing bucket
is recorded rather than discarded, because a collision is a candidate
equation (\S7.2).

The *null frame* is the same frame with every coded column replaced by iid
uniform draws from $D$. Given columns are left untouched. A collision that
also holds on the null frame is a law of the operators, not a fact about
the data, and is set aside (as a law candidate for \S6.2).

### 1.5 Findings

Let $u$ be the *unknown*: the newest reference to a coded column. It is
`x0` in a sequence and `b` in the transposed table. Findings are read off
the buckets:

| finding | bucket holds | example |
|---|---|---|
| explicit generator | $u$ itself and a $u$-free $G$ | `x0 = (+ x1 2)` |
| conserved quantity | a $u$-dependent $E$ and a constant | `(- x0 x1) = 2` |
| implicit equation | a $u$-dependent $E$ and a $u$-free $G$ | `(* x0 x1) = (+ x2 9)` |
| partial finding | one of the above, on a subset of rows | `x0 = (+ x2 1)` where `i` is even |

A finding is *exact* if it holds on every row where both of its sides are
defined, and *partial* otherwise, in which case it needs a guard (\S5.4).
Rows where it is undefined, such as the first rows of a recurrence, are
coded as *bare facts* (initial conditions).

### 1.6 Fibers and the code

Rows are decoded in scan order: along the axis, or in raster order in 2D.
Given a set $\Phi$ of accepted findings, the unknown's fiber at row $r$ is
$$F_r(\Phi) = \{\, w \in D : \varphi_r(\text{decoded rows},\ u \mapsto w)
\text{ holds for every } \varphi \in \Phi \text{ applying at } r \,\},$$
and the frame costs
$$\mathrm{DL}(X) = \mathrm{DL}(\text{header}) + \sum_{\varphi \in \Phi}
\mathrm{DL}(\varphi) + \sum_r \log_2 \lvert F_r(\Phi) \rvert .$$

Where no finding constrains a row, $F_r = D$, so a bare fact costs
$\log_2 \lvert D \rvert$. The true value always lies in its fiber, so the
code is decodable. A singleton fiber costs 0 bits. At a row with
$\lvert F_r \rvert = k$, the residual is an index in $[0, k)$. The raw
baseline is $\Phi = \emptyset$.

Every comparison in this plan uses this one quantity: findings, covers,
lifts and rival programs alike, as in ARC1 \S2.5.

### 1.7 Programs and execution

A program is a nested set of frames. Each frame has a decision list of
guarded findings, optional lifts to child frames, and bare facts. Execution
runs the child frames first, then reconstructs each parent row by its
generator:

- explicit: evaluate $G$;
- implicit: search the fiber over a finite $D$;
- partial: index into the fiber with the residual.

Executing past the end of the data is extrapolation. Every accepted program
is executed and must reproduce its data exactly. Behavioral verification is
the ground truth, as the ARC1 M3 notebook found for inverters ("labels are
the wrong ground truth").

---

## 2. The pipeline: steps (1)--(4) restated

**(1) Frames.** The data arrive as frames with tags (\S1.2). The axis tags
are what make locality available, because references are relative to the
row.

**(2) Expansion and detection.** Expand to depth 2, bucket (\S1.4), read
findings off the buckets (\S1.5), score them by fibers (\S1.6), and assemble
a guarded cover (\S5.4). This *computes* `x[i] - x[i-1] = 2` instead of
enumerating programs: the finding is a bucket, found by hashing. Its cost is
the expansion itself, for which, as the prompt says, there is no shortcut.
Learned laws reduce that cost (\S6.2) and types bound it (\S1.3).

**(3) Residuals and lifts.** If no exact finding covers the frame, or a
cheaper description may exist one level down, try *lifts*. An expression
$E$ that is injective in $u$ turns the frame into a child frame $v = E$ on
the same tags. The child is synthesized recursively, and the parent is
recovered from it through $E$'s singleton fibers.

Anti-unifying per-instance solutions gives the same kind of child another
way: as a template with a hole, whose substitutions are the child's
values (\S5.5). The recursion stops where the MDL bound prunes it, and
what remains is bare facts.

**(4) Conserved to generative.** A finding with singleton fibers is already
a generator, but an implicit one. There are four ways to handle it, tried
in order:

(a) the unknown's bucket often already holds the explicit form (checked,
    \S4);
(b) otherwise, isolate the unknown with learned solve rules (\S6.5);
(c) otherwise, keep the implicit generator (fiber search);
(d) fibers larger than one leave a residual index, which is itself a
    frame for step (3).

**The outer loop: algebra by experiment.** For each operator, run it over
its domain to get the experiment frame. Call the same pipeline with the
input and output roles transposed, and store the results (laws, solve
rules, new operators) in a library file (\S6). This is the prompt's
"recursive call of the program synthesis pipeline, only with the input and
output transposed".

---

## 3. Worked examples

All examples are worked by hand, using the code lengths of \S1. Those marked
(checked) were reproduced by the scratch scripts of \S4. The common setting
is leaves `x0 x1 x2 i 0 1 2 3`, operators `+ - *`, and $D = [-64, 64)$, so a
bare value costs 7 bits and a node $\log_2 11 = 3.46$ bits.

### 3.1 `2, 4, 6, 8, 10` (checked)

| finding | rows | bits saved | DL | net |
|---|---|---|---|---|
| `(- x0 x1) = 2` | 1--4 | 28 | 17.4 (3 nodes + constant) | +10.6 |
| `x0 = (+ x1 2)` | 1--4 | 28 | 13.8 (4 nodes) | +14.2 |
| `x0 = (+ (+ i i) 2)` | 0--4 | 35 | 20.8 (6 nodes) | +14.2 |

The recurrence and the closed form tie. Both predict `12, 14, 16`. In all,
57 equation variants were accepted (sign flips, constant shifts,
`(- (- x0 x1) 1) = 1`, ...), and every one predicts the same continuation,
so grouping by prediction keeps one (\S5.2). The identity `(- x0 x0) = 0`
also holds on the null frame and never reaches scoring.

### 3.2 Fibonacci, squares, and `x[i] = x[i-1] + i`

- **Fibonacci `1 1 2 3 5 8 13`.** As an equation, `x0 = (+ x1 x2)` saves 35
  bits for 13.8 (net +21.2). As a conserved quantity,
  `(+ (+ x1 x2) (- 0 x0)) = 0` costs 7 nodes plus a constant (net +3.8,
  checked). So equations must be detected directly, not only constants;
  this is the second trap of \S4.
- **Squares `1 4 9 16 25 36`.** The closed form `x0 = (* (+ 1 i) (+ 1 i))`
  nets +14.3 (checked). The second difference `(+ (- x0 x1) (- x2 x1)) = 2`
  nets $-3.2$ at $n = 6$ (checked), because four rows cannot pay for seven
  nodes. MDL correctly prefers the closed form here; at $n = 12$ both are
  positive.
- **`1 2 4 7 11 16`.** `x0 = (+ x1 i)` nets +21.2. The checked run, which
  had the boundary bug, found the closed form
  `(+ x0 x0) = (+ (* i i) (+ 2 i))` instead.

### 3.3 Constants, period 2, and a partial finding

- **`3 3 3 3 3`.** The finding is `x0 = 3`, net +28.1 (checked). That
  number holds only once the null is drawn over $D$: drawn over the data's
  range, the null is itself constant and every finding looks trivial (the
  first trap of \S4).
- **`5 7 5 7 5 7`.** The equation `x0 = x2` saves 28 bits for 6.9 (net
  +21.1). It beats `(+ x0 x1) = 12` and `(* x0 x1) = 35` (net +17.6 each,
  checked), even though those need only one initial condition instead of
  two: their constants, 12 and 35, are not leaves and cost 7 bits each.
- **The partial finding.** The constant sequence also yields
  `(* x0 x0) = (* 3 x0)`, whose fiber is $\{0, 3\}$: 6 bits saved per row,
  plus one bit of residual (checked). This is the smallest instance of
  "algebra becomes partial inference": the finding restricts the unknown
  but does not determine it.

### 3.4 Interleaving `1, 10, 2, 20, 3, 30` (checked negative)

Nothing is exact at depth 2. There are two ways forward:

- a guard on parity: `x0 - x2 = 1` where `i mod 2 = 0`, and `= 10`
  otherwise (partial findings plus a cover, \S5.4);
- re-indexing by `(i mod 2, i div 2)` into a two-column frame. There each
  column has `x0 - x1 = const`, and the columns either anti-unify (`1`
  versus `10`) or satisfy `col1 = 10 col0` (\S5.7).

This is the first example where the representation has to change, not just
the expression.

### 3.5 Cubes and fourth powers: lifts (checked)

For the cubes `1 8 27 ... 512` nothing is exact at depth 2. The lift by
`x0 - x1` gives the child `7 19 37 61 91 127 169`, whose second difference
is 6, which is exact at depth 2 inside the child. Fourth powers need two
lifts.

The lift composes depth 2 in the parent's window with depth 2 in the child.
That reaches a depth-4 program for the cost of (lifts tried) $\times$ (one
depth-2 expansion), instead of a depth-4 enumeration. \S4 also measures
which order to try lifts in: by the size of the lift expression, not by
how small the lifted values are.

### 3.6 GF(59): the additive inverse by transposition (checked)

The experiment frame has rows $(a, b) \in \mathrm{GF}(59)^2$ and
$c = a + b$. Transpose the roles, so that $a$ and $c$ are given and $b$ is
coded. Expand over $\{a, c\}$ and the constants with operators $\{+,
\times\}$ only (no subtraction). The cheapest member of $b$'s bucket is
`(+ c (* a 58))`, verified on all 3481 rows: the prompt's $c + 58a = b$.
The same run gives `(+ c (* a 4))` for $p = 5$, `(+ c (* a 6))` for $p =
7$, and `(+ c (* a 10))` for $p = 11$.

### 3.7 GF(59): no multiplicative inverse at depth 2 (checked negative)

The answer is $b = c \cdot a^{-1} = c \cdot a^{57}$. That is out of reach
for $\{+, \times\}$ at depth 2, where the degree in $a$ is at most 4. For
$p = 5$ it is in reach, since $a^{-1} = a^3$, and `(* (* a a) (* a c))`
was found. For $p \ge 7$ the pipeline should go through four steps:

1. A cover by partial generators `(* k c)`, each of which holds where
   $a = k^{-1}$ (and wherever $b = 0$).
2. Anti-unification of those generators into `(* ?k c)`, with $?k$ varying
   across rows and tagged by $a$.
3. A lift to the child frame $a \mapsto ?k$, which is $a^{-1}$. The
   recursion finds nothing for it at depth 2.
4. Bare facts: a 58-entry table, about $58 \log_2 59 \approx 340$ bits,
   promoted to a new operator `inv`.

After that, $b$ = `(* c (inv a))` at depth 1. This is still memory-based
inversion, but factorized: a unary table plus a symbolic rule, instead of
the $p^2$-entry table the prompt warns about.

### 3.8 Across fields: $?K = p - 1$ (by hand)

The four solve rules of \S3.6 are identical up to one constant. Their least
general generalization is `(+ c (* a ?K))`, with $?K \mapsto 4, 6, 10, 58$
tagged by $p$. The child frame $p \mapsto ?K$ has the explicit generator
`(- p 1)` at depth 1. The result is one parametric solve rule covering
every field tested.

### 3.9 A list with references (by hand; M4)

The input is `in = 3 1 4 1 5` and the output is `out = 5 1 4 1 3`. No
constant-offset reference works, but the computed reference
`(@ in (- (- n 1) i))` does. This is "meet in the middle":

- the *backward set* of row $i$ is the input positions that hold `out[i]`
  (value 5: $\{4\}$; value 1: $\{1, 3\}$; ...);
- the *forward set* is the index expressions over `i, n`.

`(- (- n 1) i)` is the forward expression that lands in every row's
backward set. Rows with rare values (5, 4 and 3, one candidate each) fix
the expression; rows with repeated values (the 1s) only check it.

---

## 4. Pre-checks run while writing this plan

Five small throwaway python scripts were run in the scratch directory; they
are not in the repo. The 1D setting is as in \S3. The GF($p$) runs use
operators `+ *` only.

| check | result |
|---------|---------------------|
| expansion size, 1D | 17 399 raw expressions, 6 754 classes; buckets on the data alone: 893 (constant sequence) to 6 754 (no coincidences); 0.2 s in python |
| effect of commutativity | 25 955 raw without argument-order canonicalization, 17 399 with; classes unchanged (hashing removes the duplicates anyway) |
| depth 3, 1D | about $1.4 \times 10^8$ raw ($3 \times 6754^2$): out of reach for brute expansion |
| GF(59) table, all 59 constants | 295 classes at depth $\le 1$, 38 700 at depth $\le 2$; 0.4 s in python on 64 hashed rows; $b = c + 58a$ verified on 3481 rows |
| GF(59) table, constants $\{0, 1, 2\}$ only | inverse of $+$ not reachable: 58 cannot be built at depth $\le 1$, so holes are needed (\S5.3) |
| null control | 0 of 120 random sequences (lengths 5, 6, 8; values 0--20) accept any constant or equation |
| prediction grouping | in every test sequence, all accepted findings predict the same continuation, apart from one partial finding |
| lift order, cubes | ranked by the magnitude of the lifted values, `x0 - x1` comes 66th of 2661 and none of the top 12 children has structure; ranked by the size of $E$, 4 of the first 23 children are exact |
| lift order, fourth powers | none of the 21 size-3 lifts gives an exact child: two levels are needed |

Two traps were found, and both are now in the design:

1. **The null must be the raw code's model** (uniform over $D$), not drawn
   from the data's range. With `3 3 3 3 3`, a range-based null is constant
   and every finding looks trivial.
2. **Undefined boundary rows split buckets.** `x0` is defined at row 0 and
   `(+ x1 x2)` is not, so their vectors differ and `x0 = (+ x1 x2)` was
   missed. The fix is to hash on interior rows only and extend coverage to
   boundary rows by verification (\S7.1).

The checks also turned up two scaling facts:

- A constant sequence puts thousands of expressions into one bucket.
  Enumerating all pairs in it gave 196 330 candidate equations. Pair only
  the cheapest $u$-dependent member with the cheapest $u$-free member
  (\S7.2).
- Keeping separate classes for expressions that agree on the data but not
  on the null doubles the class count (6 754 against 3 615 for
  `2 4 6 8 10`). The design in \S1.4 avoids this: one representative per
  data bucket builds larger expressions, and the null check is applied
  only to recorded collisions.

---

## 5. Conceptual holes and how this plan resolves them

Each item states the hole, the resolution, and its status: *design*
(settled here), *measure* (to be settled at a milestone by a stated
experiment), or *open* (needs a decision or more thought).

### 5.1 What counts as a conserved quantity [design; checked]

**Hole.** On short data, many expressions are constant by accident or by
identity.

**Resolution.** Fibers (\S1.6). An identity has full fibers and saves
nothing. An accident on $n$ rows can save up to $n \log_2 \lvert D \rvert$
bits, but it pays $\mathrm{DL}(E)$ under a prefix code fixed in advance.
That payment is the multiple-comparisons correction (an Occam bound), and
the 0-of-120 null control is its check. The null filter is only a cheap
stand-in for "the fiber is everything".

This is the problem of trivial invariants that Schmidt and Lipson met in
continuous data. They solved it by comparing predicted and observed
partial-derivative ratios; fibers are the discrete counterpart.

### 5.2 Many variants of one finding [design]

**Hole.** `2 4 6 8 10` yields 57 accepted variants.

**Resolution.** Group findings by the continuation they predict (the next
$k$ rows, by forward execution) and keep the cheapest in each group. This
is ARC1's "dedupe by prediction, not by program" (\S12). Groups that
predict different continuations are the rivals, and the best few are kept.
Learned laws (\S6.2) remove the sign and constant-shift variants before
scoring.

### 5.3 Constants and holes [design]

**Hole.** GF(59) needs the constant 58, which a small literal set cannot
build at depth 2.

**Resolution.** Typed holes `?k`, fitted per candidate on a few hash rows
and verified on all rows:

- in the bootstrap, by enumerating the hole's domain (59 values:
  memory-based, and cheap);
- once solve rules exist, by isolation (one row gives $?k$, the rest
  verify it).

A hole costs $\log_2 \lvert D \rvert$, or a universal integer code in
$\mathbb{Z}$. Start with one hole per expression.

### 5.4 Partial findings, guards and covers [design]

**Hole.** The paper the prompt cites (EUSolver, Alur, Radhakrishna and
Udupa 2017) proceeds in two stages. It enumerates terms until each point
is covered by some term, then learns a decision tree over enumerated
predicates. That works only for *point-wise* specifications, where the
value at one point does not constrain the value at another. Recurrences
are not point-wise.

**Resolution.** After the expansion they are. A reference brings the
neighbors into the row, so `x0 = (+ x1 2)` is a per-row predicate over the
expanded row, and EUSolver then applies:

- generators that hold on subsets of rows are its terms;
- boolean expressions over tags and decoded values are its predicates;
- a decision list (first match wins) is the cover.

The expansion is the change of variables that makes the specification
point-wise. Unlike EUSolver, splits are chosen by bits saved rather than
by information gain, since DL is the objective.

Two restrictions apply:

- Partial findings are searched only where a target is given: `u = G` on
  a subset, or the most common value of $E$. "$E_1 = E_2$ on some subset"
  over all pairs would be quadratic in the expansion.
- Guards may read only tags and already-decoded values, so the code stays
  decodable.

### 5.5 What anti-unification means here [design]

**Hole.** The prompt uses anti-unification for three things that the code
must keep apart.

**Resolution.**

1. *Within a frame, across rows.* The relative reference already is the
   generalization: `x[i-1]` is the anti-unifier of `x[3]` at row 4 and
   `x[4]` at row 5. The bucket is the clustering.
2. *Across rows with a varying constant.* The per-row solutions
   `x0 = x1 + 1`, `x0 = x1 + 2`, ... anti-unify to `x0 = x1 + ?k`. The
   substitution of $?k$, tagged by `i`, is the lifted child frame, and it
   equals the value vector of `x0 - x1`. So this case is the value-vector
   lift: a lift can be read as the value vector of an expression that is
   injective in $u$, or as the per-row values of a hole. The template view
   is what anti-unification produces; the value view is what the expansion
   computes.
3. *Across instances that cannot share a value vector* (examples of
   different lengths, different fields, different operators). Take the
   Plotkin least general generalization (LGG) of the per-instance symbolic
   solutions. The holes' substitutions, tagged by instance (example index,
   $p$, ...), form a child frame (\S3.8). This is the prompt's "keep around
   symbols, not base values": the LGG is taken over expressions, never over
   raw values.

LGG is syntactic, so it needs canonical forms. `(+ c (* a 4))` and
`(+ (* 6 a) c)` generalize to the useless `(+ ?x ?y)` unless commutativity
has first sorted their arguments. Learned laws are oriented into a
canonical order (\S6.2). Anti-unification modulo a theory (babble) is the
principled version; it is deferred, with triggers (\S7.6).

### 5.6 Lifts: which residual to recurse on [measure, M3]

**Hole.** Every expression injective in $u$ is a candidate lift: 2661 of
them for the cubes.

**Resolution, from \S4.**

- Try lifts best-first by $\mathrm{DL}(E)$, running a full depth-2
  detection on each child.
- Branch and bound on $\mathrm{DL}(E)$ plus a lower bound for the child,
  against the current best.
- Memoize children by content, because different parents often produce the
  same child.

Do not rank lifts by how small the lifted values are: that rewards
near-cancellations with no structure (`x1 + x2 - x0` for cubes).

A *lossy* lift ($E$ not injective) adds its fiber index as a second child.
Deferred.

### 5.7 Data structures beyond bare variables [open; a proposal]

**Hole.** The prompt surmises "computed and algebraic addressing schemes
on lifted/augmented data".

**Proposal.** Frames are relations, and a new data structure is a new
frame made by one of six operators, each a target for a recursive call:

| operator | makes | example |
|---|---|---|
| select (guard) | a sub-frame | the even rows |
| extend (the expansion) | new columns | `x0 - x1` |
| re-index $\sigma$ | new axes from index expressions | `(i mod 2, i div 2)` makes a sequence a 2D array |
| group-by $E$ | one row per value of $E$, with aggregate columns | objects; per-example constants |
| join on values | candidate correspondences | \S3.9, \S5.8 |
| lift $E$ | a coded child frame of latent values | differences; substitutions of $?k$ |

In these terms:

- a list of tuples is a frame with a field axis;
- a tree is a frame with a parent-reference column (a computed reference);
- a periodic or interleaved sequence is a re-indexed 2D frame.

Re-indexing candidates come from structure the expansion has already
found: a parity guard proposes `i mod 2`, and `x0 = (@ x -3)` proposes
period 3.

This is the least worked-out part of the plan. M3 tests re-indexing only,
M4 tests join, and group-by waits for M5.

### 5.8 References and correspondence ("meet in the middle") [open; M4--M5]

**Hole.** In ARC, residuals reduce to references into the input, and the
index map is unknown.

**Resolution sketch.**

1. Join output rows to input rows on equal values. This gives each output
   row its backward set.
2. Expand index expressions over the output row's tags. This is the
   forward set.
3. A candidate index map covers a row if it lands in that row's backward
   set. Coverage is still point-wise, so the EUSolver cover applies.
4. Process rare values first, since they constrain most (Notes \S3,
   "confident first"). Holes in the map, such as an offset, are fitted on
   one rare row and verified on the rest.

Sometimes one output row has many candidates and context must decide (the
non-bijective maps of the prompt). Then the choice is a hidden variable per
row, which is the clause and credit-assignment structure of the sudoku EM
(Notes \S2.3, ARC1 \S3). The anti-unification then runs over the chosen
pairs. This is designed in M4 for lists and carried to 2D in M5.

### 5.9 Algebra: when it is needed, and what is learned [design]

**Hole.** If the expansion already contains `x0 = (+ x1 2)`, why learn
algebra at all?

**Measured answer** (\S4). In 1D with $\{+, -, \times\}$, every exact
case's explicit generator was already in $u$'s bucket. Algebra is needed
when:

(a) the inverse is not shallow in the base operators (GF($p$) without
    subtraction; $a^{-1}$);
(b) the unknown is fixed only jointly by several findings (row and column
    constraints in 2D, as in sudoku);
(c) the fiber is larger than one;
(d) holes are to be fitted without enumeration.

So the base operator set is kept incomplete on purpose. This is a
deliberate handicap, like the address fields withheld from the learner in
sudoku (Notes \S2.3).

What is learned, by level:

| level | content | source |
|--|----------------|---------|
| 0 | operators and their evaluation | given (the simulator) |
| 1 | laws $E_1 = E_2$; solve rules (an inverse per operator and argument, with guard and fiber size); new operators (intensional or tabled) | experiments, \S6 |
| 2 | isolation and collection: using level 1 to solve a finding for $u$ | given and small (the methods of PRESS) |
| 3 | which lifts, re-indexings and findings tend to pay | solved tasks (priors; deferred) |

The prompt's "inference of inference algorithms" is levels 1 and 3. Level 2
could also be learned, but it is about forty lines and generic.

### 5.10 Symmetries and conserved quantities: the Noether analogy, operationally [open; optional in M1]

A *symmetry* of the data is a pair $(\sigma, \tau)$, an index map and a
value map, with $x(\sigma(i)) = \tau(x(i))$. That is a finding: an equation
between a (computed) reference and a value expression. An arithmetic
progression is $(\text{shift}, +2)$; a palindrome is
$(\text{reflect}, \mathrm{id})$.

Conserved quantities are invariants of the value map:

- differences are invariant under adding a constant to every value;
- ratios under scaling;
- residues under translation by $k$;
- symmetric functions under permutation.

Which expressions are invariants of which transformations is itself a
family of laws, $E(Ta, Tb) = E(a, b)$, which the experiment loop can learn.
With those laws, the system can go from a detected symmetry to its
candidate conserved quantities and back. It can also restrict generators to
those equivariant under the symmetry, which is the prompt's "restrict the
hypothesis space ... via the symmetries". That is the operational content
of the analogy; no theorem is relied on.

### 5.11 Laws hold per domain [design]

Laws found in GF($p$) can fail in saturating integer arithmetic
(associativity) or in $\mathbb{Z}$ with floor division. So every law and
solve rule records its domain and how it was verified: exhaustively on a
finite domain, or by $N$ random tests otherwise (as QuickSpec does).

### 5.12 Identifiability and non-injective operators [design]

Where an operator loses information ($\times 0$, `mod`, saturation), the
inverse is undefined or multivalued. The experiment table shows exactly
where: the transposed generator holds on a subset of rows, and the guard
learned for that subset is the region where the operator is identifiable.
This is ARC1's notebook lesson that relations hold only where the operator
is identifiable, obtained here from the same cover instead of a separate
filter.

### 5.13 Several findings at once [design]

Savings are not additive: once `x0 - x1 = 2` is accepted, `x0 - x2 = 4` is
worth nothing. The fiber intersection of \S1.6 handles this. Acceptance is
greedy by marginal net bits, and the marginals are recomputed after each
acceptance (ARC1's exact-$\Delta$DL rule).

Joint determination, where no single finding fixes $u$ but several do
together, is the case where step (4) needs algebra over several equations.
In 1D it is rare; in 2D it is the norm.

### 5.14 Approximate reproduction [design; M3]

The prompt allows a program to reproduce the data "perhaps approximately".
A residual frame `x0 - G`, coded with a universal integer code, is
accepted when it costs less than the raw frame: the prompt's "residuals,
provided they do not exceed the DL of the original sequence". Under exact
MDL this is simply a lift whose child ends in bare facts.

---

## 6. Learning the algebra by experiment

### 6.1 Experiments

For an operator $f$ of arity $k$ in a domain, the experiment frame has one
row per argument tuple, plus the result column. It is exhaustive when
$\lvert D \rvert^k \le 10^5$ and sampled otherwise. Experiments start
uniform. Choosing experiments that separate rival rules (the CEGIS and
exposure-seeking item of Notes \S5 and the ARC1 notebook) waits until the
uniform tables are saturated.

### 6.2 Laws (in the manner of QuickSpec and Ruler)

Expand over the variables of a domain grid, with columns $a, b, c$ all
given and nothing coded. Every collision is then a law on that grid. Keep a
law unless it is an instance of a more general law already kept, or
follows from kept laws by one rewrite. (Ruler minimizes its rule set with
equality saturation; QuickSpec prunes derivable laws with a small theorem
prover.)

Laws are used three ways:

1. orientation into canonical forms, for anti-unification (\S5.5);
2. pruning the expansion: skip `(+ b a)` once `(+ a b)` is in, skip
   `(* a 1)`;
3. collection and attraction during isolation (\S6.5).

The checks put a ceiling on use 2: commutativity removes a third of the
raw evaluations but no classes. The main value is expected from uses 1 and
3, and M1 measures all three.

### 6.3 Solve rules

For each operator and each argument position $j$: transpose (argument $j$
coded; the other arguments and the result given) and run the pipeline. The
possible outcomes are:

- an explicit generator on all rows: an inverse, such as $b = c + 58a$ for
  GF(59) `+`;
- a generator on a subset, with a guard: a guarded inverse, such as
  $b = c / a$ where $a \ne 0$ and $a$ divides $c$, for $\times$ in
  $\mathbb{Z}$;
- a cover that anti-unifies into a lifted table: a new tabled operator
  (`inv`, \S3.7);
- fibers larger than one everywhere: a multivalued inverse, recorded with
  its fiber size (`mod`).

A solve rule is stored as

```
(solve (+ ?a ?b) :for ?b :result ?c
       :inverse (+ ?c (* ?a 58)) :guard t :fiber 1
       :domain (gf 59) :verified :exhaustive)
```

and a new operator as a library entry carrying its definition (an
expression or a table) and that definition's DL. For example,
`(op sub (?x ?y) (+ ?x (* ?y 58)) :domain (gf 59))` is the prompt's "new
operator that looks like an expansion".

### 6.4 Generalizing over domains

Run \S6.3 for several values of $p$, anti-unify the canonicalized rules,
and make the holes a child frame tagged by $p$ (\S3.8). Beyond the tested
values of $p$ the result is a conjecture, and is marked as one.

### 6.5 Isolation (step 4)

If $u$ occurs once in $E(u, \ldots) = G$:

1. peel the outermost operator of $E$, using its solve rule for the
   argument that holds $u$;
2. move the result to the other side;
3. repeat until $u$ stands alone.

This is isolation as in PRESS (Bundy and Welham 1981). If $u$ occurs two or
more times, try collection with learned laws (distributivity:
$ua + ub \to u(a + b)$), bounded to a few rewrites; failing that, keep the
implicit generator. Every isolation result is verified by forward
execution.

---

## 7. Search control, provenance, time and memory

### 7.1 Sample, hash, verify

Hash on a fixed sample of interior rows: 64 for experiment tables, and all
interior rows for short sequences. Every bucket hit is then verified on all
rows, boundary rows included. Boundary rows that no finding reaches become
initial conditions.

### 7.2 Recording collisions

Each bucket keeps three things: its representative, its cheapest
$u$-free member, and its cheapest few $u$-dependent members that pass the
null check. The candidate equation is then (cheapest $u$-dependent) =
(cheapest $u$-free), which costs linear time in the bucket size. If $u$ is
itself in the bucket, the candidate is the explicit generator.

### 7.3 Bounds and dominance, as in Stitch

The current best $\mathrm{DL}(X)$ bounds everything below it:

- a lift is not expanded if $\mathrm{DL}(E)$ plus the cheapest possible
  child (one constant) exceeds the budget;
- a finding that saves no more bits on any row than a cheaper finding is
  dropped (dominance);
- a finding implied by accepted findings has zero marginal saving and is
  dropped (subsumption).

### 7.4 Memoizing children by content

Child frames are memoized by content (values plus tag structure), so a
child reached from different parents is synthesized only once. This is the
recursion's transposition table.

### 7.5 Provenance

Each record carries the following:

| record | carries |
|-----|---------------|
| node | expression, children, depth, size, DL |
| finding | frame, node ids, rows supported, guard, bits saved |
| frame | parent, derivation (`:lift E`, `:transpose j`, `:reindex sigma`, ...) |
| program | its lineage, printed as an s-expression |

So every predicted value can be traced to the finding and the rows that
fixed it, which is enough for the later backward flow of evidence
(Notes \S8.3).

### 7.6 E-graphs and version spaces: not yet, and what would change that

The buckets already are the version space of a frame: all expressions
consistent with the data, grouped by behavior. The prediction groups
(\S5.2) are its rivals.

An e-graph would buy three things: anti-unification modulo theory
(babble); isolation when the unknown occurs several times (equality
saturation finds a form with one occurrence); and minimal law sets (Ruler).
In Lisp a minimal e-graph (hash-consing, union-find and rebuilding) is a
few hundred lines, not a heavy import. Build one if any of these triggers
fires:

(a) more than about 10 % of single-finding conversions fail for want of
    collection;
(b) cross-instance LGGs come out over-general because canonical forms
    fail to align them;
(c) the law set stops being confluent under orientation.

### 7.7 Time and memory

In 1D everything is small: 17 399 raw expressions and at most a hundred
rows. Experiment tables are handled by sampling, hashing and verifying.

Depth 2 is the ceiling of the raw expansion; depth 3 in 1D is around
$10^8$ raw expressions. Effective depth grows only through lifts and new
operators, and that is the point of the recursion: a lift composes two
depth-2 searches at the cost of their product, not of a depth-4
enumeration.

2D is where memory bites (tens of thousands of classes times thousands of
cells). Types, proximity rings (ARC1 \S8.1) and sampling are deferred to
M5.

---

## 8. Implementation

### 8.1 Language

SBCL 2.5.2 Common Lisp, with fixnums up to $2^{62}$ and ASDF 3.3.1
bundled. MIT
Scheme 12.1 is also installed; Racket is not. The reasons for SBCL:

- native compilation with type declarations for the inner loops (value
  vectors as simple arrays of fixnums);
- `equalp` hash tables keyed by vectors: buckets in one line;
- s-expressions as the representation of expressions, findings, rules and
  the library, all readable and writable with `read` and `print`;
- exact integers;
- a REPL for inspecting buckets interactively, and a statistical profiler
  (`sb-sprof`).

Quicklisp is set up in `~/.quicklisp` (with `alexandria` fetched), but M0
needs no libraries. The matcher, unifier and anti-unifier are each a few
dozen lines, and writing them keeps the rule machinery visible.

### 8.2 Layout (M0 only; later files are listed in \S9)

```
lisploop/
  plan.md, plan.pdf, Makefile
  engine.lisp   domains, frames, expressions, evaluation with bot,
                depth-2 expansion, buckets, collision records
  mdl.lisp      grammar DL, fibers over a finite D, scoring,
                prediction groups
  m0.lisp       the M0 demonstrations, as assertions
```

`sbcl --script m0.lisp` runs the checks. `--script` skips `~/.sbclrc`,
which is fine without libraries. At the REPL, `(load "m0.lisp")` does the
same. `make` builds this document; a `make m0` target arrives with the
code.

### 8.3 Style

- Intent docstrings.
- Assertions for invariants: the true value is in its fiber; a finding
  holds on every row it claims; a lift is injective on the rows it lifts; a
  verified program reproduces its frame.
- Small clarifying comments; no capitalized emphasis.
- Indentation: Lisp's alignment-based indentation does not mix well with
  tabs, so spaces as Emacs produces them, unless you would rather keep tabs
  (\S10).

---

## 9. Milestones

| # | milestone | deliverable | exit test |
|--|-------|---------|--------------------|
| M0 | engine | `engine.lisp`, `mdl.lisp`, `m0.lisp` | the GF($p$) inverse of $+$ for $p \in \{5, 7, 11, 13, 59\}$, verified on full tables; no $\times$ inverse for $p \ge 7$ (expected, \S3.7); \S3.1--3.3 reproduced without either trap of \S4; no finding accepted on 200 random sequences; timings reported |
| M1 | algebra by experiment | `algebra.lisp`, `library.sexp` | the standard laws of $+, \times$ in GF($p$) and of $+, -, \times$ in bounded $\mathbb{Z}$, with no false law; the solve rules of \S6.3, including tabled `inv`; $?K = p - 1$; law-based pruning measured on M0's suite with unchanged answers |
| M2 | conserved to generative | isolation and collection in `algebra.lisp` | at least 15 cases whose generator lies outside the depth-2 expansion but whose finding lies inside: an explicit generator for every single-occurrence case, the implicit fallback otherwise, all verified by execution |
| M3 | lifts, guards, re-indexing | `synth.lisp` | all of \S3.1--3.5 solved; about 40 hand-made sequences plus 200 from `../symbreg/datagen.py`, scored by accuracy on held-out suffixes against a brute-force generator baseline at equal wall time; null controls |
| M4 | lists with references | computed references, value join, membership cover | map, shift, rotate, reverse, scan, pairwise sums and tiling, each from 2--3 examples |
| M5 | 2D bridge | typed 2D frames, local windows, index maps by meet-in-the-middle | a small same-shape ARC subset, compared with ARC1 M2 on the same tasks; expansion sizes and memory reported |

M2 and M3 depend only on M1, and either may go first. Priors over lifts
and findings, group-by and objects, correspondence EM, SAT and e-graphs come
after M5 and only on measured need.

### M0 in detail (the first step the prompt names)

1. **Domains and frames.** Domains: GF($p$), and integers with a coding
   range. Frames: rows, tags, given and coded columns, groups, lineage.
2. **Expressions and evaluation.** S-expressions with leaves `(@ col k)`,
   tags, literals and the unknown. Evaluation is row by row into
   simple-vectors, strict in $\bot$.
3. **Expansion.** Depth $\le 2$, no learned laws yet, hashed on the
   interior rows (sampled for tables). One representative builds larger
   expressions. Collisions are recorded per bucket as in \S7.2, with the
   null check applied to each recorded pair.
4. **Findings and scoring.** Explicit generators from $u$'s bucket,
   constants and implicit equations from the rest. Fibers are computed by
   enumerating $D$. Findings are scored by net bits, grouped by the
   prediction of the next 3 rows, and accepted greedily by marginal net
   bits.
5. **Demonstrations.**
   - The transposed $+$ table in GF($p$), for the five primes, with
     constants as all field elements, and again with the hole `?k` fitted
     by enumeration. The expected answer is `(+ c (* a k))` with
     $k = p - 1$.
   - The same with negation as a base operator and no constants. The
     expected answer is `(+ c (neg a))`.
   - The $\times$ table, reporting the absence of an inverse.
   - Sequences, each with its expected top finding and continuation:
     `2 4 6 8 10`; Fibonacci; squares; `1 2 4 7 11 16`; `3 3 3 3 3`;
     `5 7 5 7 5 7`; `3 6 12 24 48` (`x0 = (+ x1 x1)`); `1 3 7 15 31`
     (`x0 = (+ (+ x1 x1) 1)`); `1 -1 1 -1 1` (`x0 = (- 0 x1)`).
   - Interleaving and cubes, both reported as unsolved at M0.
   - 200 random sequences as null controls.

### M3's baseline

The scientific claim behind steps (2)--(4) is that finding conserved
quantities and lifting beats enumerating generators. M3 tests it against a
plain enumeration of explicit generators (size $\le 7$) at equal wall
time. If the lift search does not solve strictly more problems, the claim
fails in 1D, and that is reported.

---

## 10. Open questions for you

1. **Domain for the sequence runs.** Exact integers with a coding range
   (the plan's default), or GF($p$) throughout?
2. **The handicap.** Is "omit subtraction and division" meant for M0--M2 as
   a whole, or only for the GF($p$) demonstrations? The plan omits them in
   GF($p$) and keeps `-` in the integer sequence runs.
3. **Benchmarks.** `../symbreg/datagen.py` generates recurrences with known
   ground truth. Its `x_0` is our `x1`, and its arithmetic saturates at
   $10^6$. Use it in M3 (restricted to `add sub mul`, at most 5 nodes and 3
   lags), or keep to hand-made sequences?
4. **Indentation** in `.lisp` files: spaces (the Emacs default) or tabs?
5. **The partial-inference sketch.** \S5.5--5.8 (anti-unification produces
   children; lifts by size; six frame operators; meet in the middle as a
   point-wise membership cover) is my reading of the prompt's sketch. Is
   this the intended shape, especially \S5.7?

---

## 11. Related work (short)

- **Alur, Radhakrishna, Udupa (TACAS 2017), EUSolver.** The paper the
  prompt cites. It enumerates terms until each point is covered by some
  term, enumerates predicates, and learns a multi-label decision tree by
  information gain, with terms at the leaves. It requires point-wise
  specifications; \S5.4 explains why the expansion supplies them.
- **Udupa et al. (PLDI 2013), TRANSIT; Albarghouthi, Gulwani, Kincaid (CAV
  2013), Escher.** Bottom-up enumeration with observational equivalence:
  the buckets.
- **Claessen, Smallbone, Hughes (2010), QuickSpec; Nandi et al. (OOPSLA
  2021), Ruler; Pal et al. (OOPSLA 2023), Enumo; Singher and Itzhaky (CAV
  2021), TheSy.** Equational laws found by enumerating terms and testing
  them on sampled values, then minimized. This is \S6.2. None of them
  learns solve rules.
- **Polozov and Gulwani (OOPSLA 2015), FlashMeta.** Witness functions, the
  hand-written inverse semantics of each operator; ours are learned
  (\S6.3).
- **Lee (POPL 2021), Duet.** Bottom-up enumeration combined with top-down
  propagation through inverse semantics: a meet in the middle.
- **Bundy and Welham (AI 1981), PRESS.** Equation solving by isolation,
  collection and attraction, under meta-level control (\S6.5).
- **Plotkin (1970); Reynolds (1970); Cerna and Kutsia (IJCAI 2023, a
  survey).** Anti-unification. **Cao et al. (POPL 2023), babble.**
  Anti-unification modulo an equational theory, on e-graphs.
  **Willsey et al. (POPL 2021), egg.**
- **Bowers et al. (POPL 2023), Stitch; Ellis et al. (PLDI 2021),
  DreamCoder.** Library learning: compression bounds for pruning, and
  version spaces for refactoring.
- **Schmidt and Lipson (Science 2009).** Conserved quantities found by
  symbolic regression, with an explicit criterion against trivial
  invariants (\S5.1). **Udrescu and Tegmark (Sci. Adv. 2020), AI
  Feynman.** Recursive decomposition by symmetry and separability tests.
  **Liu and Tegmark (PRL 2021), AI Poincare.** Conservation laws from
  trajectories. **Alet et al. (NeurIPS 2021), Noether Networks.**
- **Stuhlmuller, Taylor, Goodman (NIPS 2013).** Inverses learned from
  forward samples (amortized inference): the probabilistic relative of
  \S6.
- **Kiselyov, Byrd, Friedman, Shan (FLOPS 2008).** Relational arithmetic,
  run backwards by search: the built-in alternative to learned inverses.
- **Simon and Kotovsky (Psych. Rev. 1963).** Human sequence completion by
  relations over positions ("same", "next", period): the human competence
  the prompt appeals to.
- **Rissanen (1978); Grunwald (2007).** MDL.

---

## 12. Progress log

Kept short: one entry per milestone, with the measured exit criteria.
Nothing yet.
