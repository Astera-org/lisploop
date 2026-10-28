# lisploop --- results

28 October 2026. Current implementation of milestones 1--3 in [plan 4](plan4.md).
There is one fixed binary description encoding (version 7) and one structural
work tariff (version 7), with simulator semantics version 5. Their version numbers identify the specification; they
are not selectable alternatives. Earlier measurements and explanations remain in
[the historical results](results-history.md), tied to Git revision `f6bf54ef`.

```sh
make test                       # contracts, independent references, codec and work checks
make m1                         # GF(5) and integer synthesis experiments
make m2                         # GF(5) and integer observation experiments
make m3                         # law discovery, validation, guarded rewriting, search comparison
make results.pdf                # Pandoc / LaTeX report
make benchmark                  # scaling and dispatch measurements under current accounting
sbcl --load load.lisp            # interactive inspection
```

Tested with SBCL 2.5.2; no external Lisp libraries are required. Scripts load
relative to their own location. The default Make target builds the planning
documents, this report, and the historical report with the same Pandoc settings.
`make m1`, `make m2`, and `make m3` write the current traces to
[milestone1.txt](intermediate_results/milestone1.txt) and
[milestone2.txt](intermediate_results/milestone2.txt), and
[milestone3.txt](intermediate_results/milestone3.txt).

## One accounting specification

Description size $S$ is the exact bit length of an encoded model. Work $W$ counts
the operations and payload visits specified by the simulator and search tariff.
They answer different questions: the small expression `x*x` can require substantial
work on large arguments. The work meter does not consult encoded length, printed
text, or symbol frequencies.

The experiment objectives are declared before comparison:

$$
J(M)=S(M)+\lambda_{\rm run}W_{\rm run}(M),\qquad
J_{\rm procedure}=J(M_{\rm best})+\lambda_{\rm search}W_{\rm search}.
$$

M1 reports pure description $(0,0)$ and positive work $(1/100,1/1000)$ settings.
These are exact-function fixtures with no residual. In a reconstruction task,
the residual and any selectors, definitions, permutations, or reassembly programs
must also be encoded. Acquisition includes failed candidates and checking; the
separate $W_{\rm run}$ figure describes future execution of an acquired program.

The byte-cost branch, arithmetic/general encoding profiles, alternate experiment
targets, and duplicate tests have been removed. Text is for displaying the AST.
The fixed code is a declared prior, not an estimate of observed frequencies.
Frequency learning and dynamic code allocation are deferred. Future explicit
definitions and ordered references can support reuse within a fixed coding scheme;
those library mechanisms are not implemented here.

### Encoding and the frame

The data structure is `Frame(schema, rows)`. A row contains an occurrence `key`,
its declared `known` input values, and an `allowed` requirement on the output.
The input schema is an ordered list of variable IDs and types. Row keys and
pair/start selections never become predictor arguments. Equal-valued occurrences
remain distinct.

Types include integers, Booleans, prime fields, tuples, finite sequences, and
quoted expressions with explicit types and variable scopes. Integer arithmetic is exact with no fixed bit-width limit. Field values
are canonical residues and field arithmetic reduces modulo the declared prime.
Arithmetic includes `+`, `*`, `-`, and `/`. Integer division truncates toward zero:
`5/2=2`, `-5/2=-2`, and `1/2=0`; it never creates a rational value. Field division
multiplies by the denominator's modular reciprocal. Both reject a zero denominator.
The typed `if(condition, then, else)` evaluates only the selected branch, so
`if(x=0, 0, 1/x)` is defined everywhere. Both branches must still typecheck.
Other arithmetic is eager: `0*(1/0)` is an error, not zero. The DSL has no exception
handler; conditionals avoid a failing operation before it executes.
Expressions are typed literal, variable, or application trees. They contain no
host callbacks or pointers to the observation store.

Positions are ordinary integers. A calculated integer can serve as a lookup key,
and `gather(items, positions)` accepts a sequence of integers. It requires
`0 <= position < length(items)` at every access: negative positions do not count
from the end, and oversized positions do not wrap. Invalid positions produce an
evaluation error; an empty position sequence returns an empty sequence, including
when `items` is empty. Integer values themselves remain unrestricted. Quotient
residuals and inverse permutations use the same integer representation and checks.
Frame occurrence keys remain metadata unless explicitly supplied as inputs;
unifying numeric types does not expose them to a model.

`concat(chunks)` joins a sequence of sequences in order. Empty chunks are allowed;
the element type is unchanged. This is the mechanical decoder operation used by
the AU law-compression experiment below. It supplies no arithmetic identities or
symbolic inference rules. Its work charge is one plus the structural `value-work`
of its complete input, prepaid by the same interruptible VM as other primitives.

`codec.lisp` implements the sole encoder and decoder. A packet includes its version,
ordered input schema, result type, and expression body. The schema header is paid
once per standalone model. Nested expressions share it. Variable references use
their position in the declared input order, with $\lceil\log_2 m\rceil$ bits for
$m$ inputs; a single available input needs zero slot bits.

Every expression uses the same two-bit constructor tags: `00` for a variable,
`01` for a literal, and `10` for an application (`11` is reserved). An application
then uses a four-bit opcode prefix: the original arithmetic, conditional, tuple,
membership, lookup, gather, and concatenation codes retain their assignments.
The additional symbolic operators use the remaining prefixes, with prefix `1111`
followed by a positive self-delimiting extension for operator numbers 15 and above.
Arity and operand types follow from the operator
and expected type; otherwise the necessary operand type is encoded explicitly.
There is no special arithmetic profile.

Signed integer $n$ maps to positive $z=2n+1$ for $n\geq0$, or $z=-2n$ otherwise.
If $L$ is the bit length of $z$, its self-delimiting payload costs
$D(z)=L+2\lfloor\log_2 L\rfloor$ bits. Encode the binary representation of $L$
preceded by one fewer zero than its own bit length, then the lower $L-1$ bits of
$z$. This supplies both payload and boundary information. A field value instead
uses $\lceil\log_2 p\rceil$ bits; unused bit patterns are rejected.

The header encodes version `7`, input count plus one, each input ID plus one,
the input types, and the result type. Positive counts use the same self-delimiting
code. Three-bit type tags identify integers, Booleans, fields, tuples,
sequences, and quoted syntax, using codes 0 through 5; codes 6 and 7 are reserved.
Moduli, tuple arities, and component types follow where needed.
Sequence lengths are encoded after adding one. Positional values use the same
signed integer code as arithmetic values. Boolean payloads
cost one bit; tuple values concatenate their typed components.
The quoted-syntax type encodes its own input schema and result sort. A sort can
also be an operator signature, allowing a quoted operator symbol as data.
Quoted expression values encode their AST under that schema; quoted operators
encode their name and operand type. Symbolic primitives encode their full type
parameter, including any source and destination scopes. No schema or template is
recovered from an external store during decoding.

```{=latex}
\begin{figure}[tbp]
\centering
\setlength{\fboxsep}{10pt}
\fbox{\begin{minipage}{\dimexpr\linewidth-2\fboxsep-2\fboxrule\relax}
\small
```

**Concrete costs with two integer inputs `a`, `b`.** The header costs 23 bits.
Each variable body costs $2+1=3$ bits. Addition costs a two-bit application tag
and a four-bit opcode, so

$$S(a+b)=23+6+3+3=35\text{ bits}.$$

Literal bodies cost 3 bits for `0`, 6 for `±1`, 7 for `±2,±3`, and 10 for
`±4,...,±7`. Exactly 31 integer literals are strictly cheaper than the 12-bit
body of `a+b`; another 32 tie with it. The integer vocabulary remains unrestricted.

For GF(5), the corresponding header is 38 bits; a field literal body costs
$2+3=5$ bits. Thus field `a+b` costs $38+12=50$ bits, and `a+(b+b)` costs
$38+21=59$ bits. Encoding size and execution work are separate quantities.

```{=latex}
\end{minipage}}
\end{figure}
```

`description-size(expression, inputs)` returns the total packet size in bits;
`body-size` and `header-size` expose its parts. `encode-model` returns an exact-length
bit vector; `decode-model` returns the reconstructed expression and input schema.
Malformed, truncated, trailing, and unsupported-version packets are rejected.
There is no legacy decoding or cost-model switch. Byte-file padding is not part
of the current in-memory packet format.

The index/integer unification introduced in version 5 remains in effect:
`gather([8,2,9], [0,1,2,0])` costs 66 bits, including its header and both lists.
Version 7 adds quoted syntax and symbolic operations. Its version field has the
same length as versions 5 and 6, and the original opcode assignments are unchanged,
so arithmetic and existing reconstruction packet sizes are unchanged. Previous
packet versions are rejected. M1--M3 were rerun; M1/M2 measurements are unchanged,
while M3 now reports the work of applying checked rules through the VM.

### Structural work tariff

Let $w(n)=\max(1,\operatorname{bitlength}(|n|))$. `value-work` charges one visit
per scalar or container, plus raw scalar payload widths: a sign bit and $w(n)$
for integers (including positions), one bit for Booleans, and the fixed field width
for residues. Containers additionally charge each component recursively. For
example, a sequence of 100 empty tuples incurs 101 visits even though its encoded
contents are small.

`syntax-work` charges one visit per AST node, visits to its explicit types, and
raw payload widths for literals, variable IDs, and moduli. Construction, copying,
composition, pullback construction, and validation use this structural measure.
Validation additionally charges the supplied input IDs, types, and values.
Evaluation charges one per visited expression node plus literal payload work.
Integer addition and subtraction cost the larger operand magnitude width;
multiplication and truncating division cost their width product. Fixed fields with
primes at most 257 retain a unit arithmetic tariff. For larger fields, division adds
the cube of the modulus width for extended Euclid; other arithmetic adds its square
for reduction. A conditional branch dispatch costs one unit and does not charge
execution of the unselected branch; validation still visits its syntax.
Other primitives charge one dispatch plus their operand value visits and payloads.
For `gather` on a sequence of length $n$, each requested position $i$ adds
$1+\max(w(i),w(n))$ for the sign and upper-bound checks. The whole primitive cost
is prepaid, including all checks when an access will fail, and can be interrupted
while being paid. A cutoff before payment completes remains unknown; completing
payment executes the access and reports either a value or a bounds error.

Observation setup and indexing charge input/output value visits and pair/start
comparison counts. Reorientation charges the copied values, and does not rerun
the simulator. Enumeration and scheduling retain fixed cursor/dispatch charges;
the auxiliary matching, abstraction, partition, and quotient routines retain their
declared traversal counters. These are deterministic abstract tariffs, not hardware
instruction counts. Wall time is reported separately; reporting and test harness
work, including isolated codec checks, are outside the search ledger.

## Search, interruption, and reuse

`make-language` declares the numeric domain, typed inputs, and primitive vocabulary.
It admits all domain literals by default; a finite `:literals` vocabulary remains
available for explicitly constrained tasks, but the milestone runs use all literals.
The default vocabulary remains `+`/`*` for the M1/M2 baseline. Explicit grammars may
also include `-`, `/`, equality, and numeric or Boolean `if`. Boolean literals are
admitted when the grammar uses Booleans. Typed size partitions and lazy Cartesian
cursors handle both binary and ternary operators. Numeric and Boolean intermediates
share the syntax index; the frame's target type determines eligible root programs
and the header used for the bound. Lookup and sequence reconstruction remain
available in the DSL but outside this enumerated grammar.

Search enumerates increasing **body-bit** sizes and retains every syntax tree in
buckets indexed by type and body size. It derives exact signed-integer payload
intervals lazily. Each finite bound admits finitely many literals. The caller's
description limit and completed-bound messages use total packet bits, adding the
shared header once. Changing input ID lengths cannot introduce empty header-size
scans into enumeration. No observational equivalence or algebraic rewrite prunes
the syntax buckets.

`start-search(frame, language)` creates a synthesis job. `resume-search(job,
description-limit, work-limit)` supplies a total-bit bound and an absolute,
cumulative work ceiling. Successful programs remain in `search-job-results`;
`search-job-best` selects by the declared description/execution objective.

**Interruption** stops at the cumulative work ceiling, retaining the cursor,
unfinished construction, evaluator stack, and unpaid instruction cost.
**Resumption** supplies a larger work ceiling to that saved job. **Extension**
raises the description limit, allowing larger programs. Execution in batches and
one-unit steps must preserve identical saved state and ledgers at matching cutoffs.
Host arithmetic executes atomically after its tariff is paid; this is not operating
system preemption. Checkpoints currently live in memory.

A frame row specifies both what a candidate program may read (`known`) and what
counts as an acceptable answer (`allowed`). These serve different roles during
search. First, the VM runs a candidate on the row's declared inputs and produces a
proposed output. Then search passes that output to a separate checker. The
candidate must pass the checker on every row to be accepted. The checker can use
the recorded answer to judge a prediction; that does not make the recorded answer
an input to the candidate.

There are two ways to supply this checker. `finite-allowed` lists the acceptable
outputs explicitly: `{4}` requires exactly 4, while `{1,4}` accepts either value.
An empty set accepts nothing. `predicate-allowed` instead supplies a Boolean
expression that tests a proposed output. For example, over GF(5), the expression
`z*z=4` accepts 2 and 3 without storing a list of those answers. Here `z` names
the proposed output; the checker returns a Boolean even though the candidate
returns a field value.

Both forms use the same VM and typed expression trees described above. An
abstract syntax tree (AST) is the stored structure of literals, variables, and
primitive applications. `finite-allowed` builds a membership-test expression with
the acceptable values stored as a literal sequence. `predicate-allowed` takes a
Boolean expression directly. In either case, the only variable the checker may
read is the proposed output; any other data it needs is encoded in its expression. Checking
uses the VM's ordinary arithmetic, error handling, and work meter. An interrupted
check remains unresolved and can resume; it does not establish rejection.

An output may itself be a tuple, and the checker tests that tuple as a whole.
For example, `{(0,0),(1,1)}` permits two answers whose coordinates agree. Replacing
this with two independent requirements, each allowing `{0,1}`, would also admit
`(0,1)` and `(1,0)`. Keeping whole values preserves the relationship between their
components. The same rule applies when a child problem has several coupled outputs.

The Lisp code surrounding the VM, called the scaffold, can use these executable
requirements to turn a problem into a child problem. The milestone 1 control
illustrates the mechanism. The parent receives `a` and `b` and must predict `y`,
all over GF(5). The recorded values were generated using `y=a+2b`, but that
generating program is withheld from search. The experiment supplies a
*decoder*, meaning a program that reconstructs the parent output from available
inputs and a still-unknown child value `z`. Here the supplied decoder is `a+z`,
and the child is allowed to read only `b`.

Consider the recorded row `a=1, b=2, y=0`. The parent checker asks whether its
proposed output belongs to `{0}`. To construct the child checker, `pullback-frame`
inserts the decoder into that test and fills in the row's known value of `a`:

| Problem | Inputs available to its candidate | Test applied to its proposed output |
|---|---|---|
| Parent | `a=1, b=2` | Proposed `v` belongs to `{0}` |
| Child | `b=2` | Reconstructed `1+z` belongs to `{0}`, modulo 5 |

This operation is called a *pullback*: the parent's requirement on the final
answer becomes a requirement on the child value used to construct that answer.
It builds the test `1+z` belongs to `{0}`; it does not solve the equation or list
the compatible values of `z`. When child search proposes a program, the VM runs
it on `b=2`, feeds its output through `1+z`, and checks the result. In this row,
`z=4` passes because `1+4=0` modulo 5. The same construction makes a child row
for every parent row, preserving its occurrence key. The constants in each
checker remain separate from the inputs available to the child program.

The existing enumerator then searches this child frame using `start-search` and
`resume-search`. In the control it finds `g(b)=b+b`. `compose-model` inserts that
expression into the supplied decoder, producing the ordinary DSL expression
`a+(b+b)`. The experiment encodes and independently decodes this assembled model,
runs it on every original parent input, and checks every original requirement.
Thus a successful child is followed by verification of the complete parent.

The division of responsibility is concrete: the Lisp scaffold in `frames.lisp`
constructs frames and substitutes expression trees; `search.lisp` enumerates and
checks candidates; the VM in `sim.lisp` executes both candidate programs and
checker expressions. The decoder and choice of child inputs are supplied in this
control. Automatic discovery of decompositions and general recursive scheduling
remain later research steps. Constructing the child problem, searching it, and
verifying the composition all incur acquisition work. The assembled program's
encoded size and execution work determine its cost as a reusable model.

Reconstruction can also need stored data. An executable lookup carries its table
entries as literals. A partition reconstruction carries the contents of its
groups and the integer positions needed to restore the original order. A quotient
stores distinct representatives plus a *residual*: the information needed to
recover the individual occurrences. For example, `[8,2,8]` can be represented by
representatives `[8,2]` and positions `[0,1,0]`; `gather` reconstructs the original
sequence, including its repeated 8. These tables, contents, and positions are
encoded inside the reconstruction program and contribute to its description
length. Once decoded, the model has the data it needs to run using only its
declared inputs. This is why a compression comparison must price the complete
reconstruction, including the residual, rather than only the shared formula or
the distinct representatives.

The scaffold also contains *anti-unification* (AU): a way to turn several
expression trees into a shared template plus the substitutions that recover each
original. This is an implemented building block for milestone 6's abstraction
work. Small controls supply the expressions to compare; milestone 3 now also
applies AU to its discovered laws and measures the resulting lossless compression.

For example, one control in `tests/core.lisp` supplies the integer expressions
`(+ 2 2)` and `(* 3 3)`. Their outer structure is the same: a binary operation
with two identical operands. `anti-unify` returns the template `(?op ?x ?x)`
and one set of substitutions per source:

| Original expression | Substitute for `?op` | Substitute for `?x` |
|---|---|---|
| `(+ 2 2)` | Integer addition | Integer literal 2 |
| `(* 3 3)` | Integer multiplication | Integer literal 3 |

The repeated `?x` matters: both argument positions must receive the same
expression within a substitution. The template can reconstruct both supplied
sources, but it cannot reconstruct `(* 3 4)`. If that expression replaces the
second source, AU instead needs separate argument holes, `(?op ?x ?y)`.
The operator hole is also typed: addition and multiplication both take two
integers and return an integer. An equality operator, which returns a Boolean,
cannot fill that same hole.

The algorithm in `au.lisp` walks the source trees together, comparing corresponding
positions. It retains identical parts, descends into applications with compatible
operator signatures, and replaces differing parts with typed holes. It remembers
the differences it has already encountered. In the example, both operand
positions present the same pair of differing terms, literals 2 and 3, so they
reuse one hole. This preserves shared structure that would be lost by giving
every position a fresh name. The result is called a *least general generalizer*:
the most specific common template under these syntactic and typing rules. That
property does not imply that the template provides the shortest encoding.

Three scaffold operations have distinct jobs. `instantiate` fills a supplied
template using supplied substitutions. `match-pattern` takes a template and a
source expression and recovers substitutions, or reports that they do not match.
`anti-unify` takes the source expressions and constructs the template itself;
it then uses matching to recover each source's substitutions. The controls check
all three operations separately and verify that substitution reproduces the
original trees exactly. Tiny cases are also compared with an independent
enumeration of possible templates.

Holes are placeholders in the scaffold's tree data, distinct from the runtime
input variables used by the VM. A substitution for `?x` is an expression tree,
which may be a literal, variable, or larger expression. A substitution for `?op`
is a compatible operator symbol. `instantiate` can perform this substitution in
the scaffold before execution. There is now a second route: `compile-au-constructor`
turns the template into a DSL program whose inputs are typed quoted hole fillings
and whose output is the reconstructed expression, still quoted. Operator holes
become quoted operator inputs, and `code-apply` constructs application nodes.
For example, supplying quoted `+` and quoted `2` to the constructor for
`(?op ?x ?x)` returns the syntax `(+ 2 2)`, without calculating 4.

Neither route leaves unresolved holes in executable programs or quoted values.
There are no callable function arguments hidden behind operator holes. AU remains
a metered scaffold proposal procedure; its output constructor runs through the
ordinary VM. The compiler's tree visits and construction work are reported
separately from executing that constructor.

The caller currently chooses which whole trees to align. AU does not search for
matching fragments under unrelated wrappers, reorder arguments, or infer algebraic
equivalence from execution. For example, `a+b` and `b+a` can have identical outputs
while remaining different trees. Milestone 3's checked rewrites provide a separate
mechanism for changing syntax while preserving behavior. That normalizer already
uses `match-pattern` to apply rules, but it does not call `anti-unify` to discover
their templates.

The connection to recursive synthesis follows the reconstruction contract above:
a template supplies a recipe for rebuilding each source, and the differing
substitutions become residual information. AU identifies what varies; it does not
explain why one occurrence uses addition and 2 while another uses multiplication
and 3. The new milestone 3 experiment takes a first step: it encodes the template
and substitutions as a dictionary of packet fragments plus an occurrence sequence,
then checks the resulting decoder through `start-search`. The source syntax has
an explicit representation as Boolean sequences containing canonical DSL packets.
All fragments, lengths, selectors, and reassembly operations contribute to model
size. Predicting substitutions from context, installing named definitions, and
automatically scheduling recursive AU child searches remain later work.

## Milestone 1: synthesis

The simulator generates the complete GF(5) table for `y=a+2*b`; only the declared
input/output frame enters search. The search completes 50 bits without a predictor,
then extends to 61 bits, the encoded size of the fixture oracle. It finds
`a+(b+b)` at 59 bits, along with nine other valid formulas. All 25 inputs pass
independent decoding and replay. The supplied pullback control discovers `b+b`
from the child requirement `a+z=y`, then reconstructs and checks the parent.
Contradictory singleton outputs for identical inputs yield no candidate.

| GF(5) representation | Total bits | Execution work on 25 inputs |
|---|---:|---:|
| Discovered `a+(b+b)` | 59 | 1,375 |
| Encoded executable lookup | 315 | 28,750 |
| Literal ordered target sequence | 103 | Different whole-object task |

The formula and executable lookup solve the same function task: given a supplied
pair `(a,b)`, return its corresponding output `y`. For example, on `(1,2)` both
return 0 modulo 5. Their packets include the input schema, but the input values
arrive as arguments at execution time. The comparison of 59 versus 315 bits is
therefore a comparison between two programs with the same interface. Their
execution-work figures both cover answering all 25 input queries.

The 103-bit literal sequence has a different interface. It takes no arguments
and returns all 25 recorded outputs as one ordered list. It contains the output
values and their order, but no input pairs. In the fixture, the *input grid* is
the complete set of pairs with `a` and `b` each ranging from 0 to 4. The fixture
orders those pairs as `(0,0),(0,1),...,(0,4),(1,0),...,(4,4)`, advancing `b`
first. The output list consequently starts `[0,2,4,1,3,...]`. Its third element
belongs to input `(0,2)` only because of that ordering convention. The literal
list alone does not say which element answers an arbitrary `(a,b)` query.

To use that list as a function, a decoder would need a mapping from the supplied
input pair to its position in the list, together with a way to retrieve that
element. Conversely, to use the formula as a generator of the whole list, a
decoder would need to visit every input pair in the required order, run the
formula, and collect the results. The 59-bit formula packet does not include
that traversal. In the current experiment, the Lisp fixture supplies the input
grid and iteration order; those operations have not been packaged and priced as
part of a sequence-generating model.

A fair comparison must therefore first choose the object to reconstruct and the
information already available to its decoder. If the grid and order are fixed
parts of the task, both alternatives may use that declared convention, and their
complete execution work must be measured on the same workload. If the goal is to
compress the entire recorded table, the representation must also account for
its input columns, schema, occurrence keys, and required row order. A regular grid
could be described by a short generating rule; a shuffled table might need a
permutation, and repeated occurrences must remain recoverable. Whatever supplies
this information must be declared and priced once at the comparison boundary.
Thus the table demonstrates a smaller formula for the function task and reports
the size of the literal output list, but it does not yet measure complete table
compression by both methods.

Discovery examines 649 expressions and costs **182,181 work units**; the
first formula is accepted at 22,727. Original acquisition, baseline construction,
and independent replay add 35,031 units. The supplied-child control has separate
ledgers: 3,892 for child search and 4,230 for pullback, composition, and parent replay.

The integer counterpart uses all 25 inputs in $[-2,2]^2$ and unrestricted signed
literals. It completes a 44-bit bound, retaining 9,243 expressions and six valid
formulas. `a+(b+b)` costs 44 bits and is first accepted at 1,018,877 work units;
complete discovery costs **1,089,220**. It passes six fresh signed pairs around
$2^{256}$, including cancellation and adjacent integers. Execution work is 862
on the training rows and 6,342 on fresh rows. Original generation, orientation,
and independent replay cost 3,185; the fresh-data stage costs 26,814. Integer
evidence remains finite observations, while the GF(5) table covers its full domain.

## Milestone 2: observed equivalence and invariants

**The conservation constraint is supplied; the conserved expression is searched.**
This experiment supplies recorded before/after pairs and asks for a function $h$
whose values agree on every linked pair. Those equality constraints imply a
grouping: states connected along a recorded trajectory must receive the same
$h$ value. The search is also required to produce different values at at least two
selected starting states, so a globally constant expression does not suffice.
The pairing and selected starts are prior structure in the task. The learner
discovers an expression consistent with that structure; it does not discover the
grouping, the conservation criterion, or the transition dynamics. No candidate
is assumed to satisfy the constraint before execution checks it.

The transition operator generates the fixture but is not a predictor input.
Search receives the states and pair/start metadata, with $h$ evaluated using
only the declared state coordinates. In the visualizer, `h` means the selected
candidate expression, and each node displays its value $h(a,b)$. Under the integer
transition $(a,b)\mapsto(a+1,b-1)$, the states $(2,3),(3,2),(4,1)$ have sums
$5,5,5$, while their products are $6,6,4$. Addition satisfies the supplied
conservation constraint; multiplication fails it.

A transition is not required by the general observation mechanism. An enumerator
or random sampler can supply inputs for comparing expressions' output vectors.
For conservation, a grouped generator could instead sample
$G(k,u)=(u,k-u)$, varying $u$ within each supplied group $k$. Requiring equal
outputs within groups and variation between groups would again admit $h(a,b)=a+b$;
$k$ would be grouping metadata, not an argument to $h$. This is an alternative
fixture, not an additional experiment reported here. Without relationships or
groups, arbitrary samples still support observed equalities such as
$a+b=b+a$, but do not by themselves specify what $h$ should be conserved across.
Pair/start metadata is optional in the implementation; milestone 3 uses the same
observation machinery on an enumerated grid without transitions.

An *observation scope* records the conditions under which these comparisons are
made. `make-observation-scope` takes a snapshot of the frame's ordered input rows
and their types, together with the language's variables, primitives, and literal
vocabulary. It also records the simulator, encoding, and work-tariff versions,
the rule for comparing values, and any supplied transition pairs and starting
rows. This gives each finding an explicit context: what was evaluated, on which
inputs, and under which semantics and accounting rules. The job's description
and work limits can grow during resumption while this context stays fixed.

The observation job uses the same expression enumerator and VM as the function
synthesis described earlier, but collects behavior across rows. It runs a
candidate expression once on each row's declared inputs and stores the results
in row order. This ordered list is the expression's *output vector*. Every row
occurrence contributes an entry, even when two rows contain identical inputs.
For this job, the frame's `allowed` checkers are not consulted: the transition
probes carry an always-true requirement because there is no supplied target value
for $h$. The scaffold instead compares the collected outputs with one another,
using the pair and starting-row metadata to test conservation and variation.

For a small illustration, take the two integer transition pairs
`(2,3) -> (3,2)` and `(0,0) -> (1,-1)`. Put those four states in that order in
the probe frame. The VM would produce:

| Candidate expression | Output vector on the four rows | Observation |
|---|---|---|
| `a+b` | `[5,5,0,0]` | Equal within each pair; different between starts |
| `b+a` | `[5,5,0,0]` | Exactly the same vector as `a+b` |
| `a*b` | `[6,6,0,-1]` | Unequal outputs on the second pair |
| Literal `0` | `[0,0,0,0]` | Equal within pairs, but no variation between starts |

A *bucket* is a group of expressions with the same complete output vector and
the same result type. In this illustration, `a+b` and `b+a` share a bucket;
the product and the constant occupy separate buckets. These buckets group
**expressions by observed behavior**. The transition relationships discussed above
group **states on which an invariant must agree**. The two groupings serve
different purposes: bucket membership compares two programs across all rows,
while invariance compares selected entries within one program's vector. This is
why the visualizer can display both a bucket's member expressions and whether
that bucket satisfies the conservation and variation tests.

The result type is part of the bucket key. For example, integer 0 and GF(5) 0
have the same printed numeral but belong to different arithmetic domains, so
their expressions do not share an equality bucket. Within a type, comparison
uses exact values, including every component of a tuple or sequence. This is
what *typed-value equality* means here. It does not compare printed text or
approximate numeric values.

Grouping expressions does not remove their syntax. The observation record keeps
each expression tree and its measured execution work, and the codec supplies its
description size. Expressions that agree on these rows may differ elsewhere,
have different costs, or expose different alignments for the anti-unification
mechanism described above. The enumerator therefore retains their trees for
building larger expressions. An empirical bucket provides evidence and possible
law proposals; it does not by itself authorize replacing one expression with
another throughout search.

Only successful evaluation on every row supplies a complete output vector for
an equality bucket. If a candidate errors on a row, its record retains the
diagnostic, the failing occurrence key, any earlier outputs, and the work already
spent. Two candidates failing in the same way are not counted as agreeing
programs. A budget interruption has a different meaning: the result is still
unknown, and the saved observation job and VM state can resume. Neither an error
nor an unfinished vector supplies the missing evidence of equal outputs.

Guard discovery adds an optional `:retain-outcomes t` mode. It continues after a
row errors and retains a separate value-or-error record for **every** row, including
its diagnostic and execution work. These records stay aligned with the scope's
input rows. An expression with any error still cannot enter a whole-scope equality
bucket, but its successful rows can contribute to the partial agreements used
below. The original observation mode still stops at the first error.

Finally, agreement belongs to the particular scope in which it was observed.
The implementation requires the records to refer to the same scope object;
matching names or similar-looking rows are insufficient. Adding inputs creates
a new scope in which the expressions are evaluated again. For example, `x` and
`x*x` both produce `[0,1]` on inputs `[0,1]`, but produce `[0,1,2]` and `[0,1,4]`
on `[0,1,2]`. The new scope separates them while the old observation remains a
correct statement about its two inputs. Milestone 3 adds the independent
validation needed to promote suitable observed agreements into reusable laws.

The field experiment records five steps from each of `(0,0)` and `(0,1)` under
$T(a,b)=(a+1,b+4)$ over GF(5). Reorientation produces 20 probes from ten transitions.
The integer experiment records three steps from each of `(-3,1)`, `(0,0)`, and
`(2,3)` under $T(a,b)=(a+1,b-1)$, producing 18 probes from nine transitions.
The search asks for a program whose value is unchanged across each pair and varies
across starts. Constants satisfy invariance but fail the variation requirement.

| Domain | Total bound | Expressions / buckets | Returned programs | Discovery work |
|---|---:|---:|---|---:|
| GF(5) | 50 bits | 15 / 13 | `a+b`, `b+a` | 13,016 |
| Integers | 35 bits | 83 / 71 | `a+b`, `b+a` | 52,481 |

Exactly one informative bucket contains both sums in each experiment. Field sums
stay at 0 and 1 along the two trajectories; integer sums stay at $-2,0,5$.
Execution work per sum is 800 over the field probes and 452 over the integer probes.
Original transition generation and reorientation add 1,150 and 711 units, respectively.
Extending the field bound to 54 bits includes all 105 single-application expressions
and costs 117,996 units. This larger bound does not change the informative bucket.

Both returned expressions pass six fresh transition pairs. Integer starts are
$(N,-N)$, $(N+1,-N)$, $(-N,N)$, $(-N-1,N)$, $(N,N)$, and $(-N,-N)$, with
$N=2^{256}$, checking exact sums $0,1,0,-1,2N,-2N$. Changing the transition to
`(a+1,b+3)` over GF(5), or `(a+1,b-2)` over integers, rejects both invariants.
Fresh successful replay costs 1,280 field units and 27,421 integer units, with
acquisition/reorientation costs of 690 and 15,788. Full ledgers include the nearby
negative cases separately.

The accidental-agreement control starts with `x` and `x*x` on `{0,1}`. Adding
`2` splits their shared vector; the integer control also tests `-1`, $N$, and $N+1$.
All programs survive the recheck, and earlier scoped evidence remains intact.
Original transition frames can be reoriented for later questions without charging
simulation again. These findings are **replayed observations**, including fresh
tests; they establish neither a general integer law nor a symmetry group.

`start-observation-search` enumerates syntax, or replays a supplied `:expressions`
list. Its `:replay-complete` message covers only that list; `:bounded-exhaustion`
covers the declared grammar bound. Rechecks currently execute all rows again,
without caching previous evaluation prefixes.

## Milestone 3: checked equations and guarded rewriting

M2 buckets now propose explicit DSL equations. Each bucket proposes every member's
equality with its first enumerated representative, avoiding a quadratic all-pairs
list. Proposals carry their observation scope and remain conjectures until checked.
The law record contains the numeric domain, ordered input types, equation, and a
Boolean guard. The equality relation is fixed typed-value equality. The complete
statement is itself executable and encodable DSL data: `if(guard, lhs=rhs, true)`.
Frame orchestration, validation, and matching remain in Lisp.

`start-law-validation` independently checks every assignment of the declared finite
input types. It evaluates the guard first, then the equation only when the guard is
true. A false equation or evaluation error refutes the proposal and records the
input assignment. `resume-law-validation` uses an absolute cumulative work ceiling;
an interruption remains unknown. A completed sample check is only a conjecture,
and a guard that is never true is marked vacuous. Only a completed exhaustive check
with at least one active assignment issues a rewrite certificate. Certificates bind
the exact equation, guard, schema, domain, equality, and implementation versions;
changed syntax or a different domain cannot reuse them.

The discovery experiment exhausts small `+`/`*` expressions on the complete field
grid, then evaluates all proposed equations again in the validator:

| Domain | Bound | Expressions / buckets | Checked laws | Discovery | Proposals | Validation |
|---|---:|---:|---:|---:|---:|---:|
| GF(5) | 54 bits | 105 / 25 | 80 | 143,894 | 3,038 | 222,298 |
| GF(7) | 54 bits | 171 / 35 | 136 | 464,216 | 5,182 | 739,762 |

Both runs recover `a+0=a` and `a+b=b+a`, with independent certificates covering
25 and 49 assignments respectively. Under GF(5), their complete guarded statements
cost 76 and 83 bits. Counts include ground constant equalities and syntactic
specializations; they do not mean 80 or 136 independent algebraic principles.
The supplied stress candidate `x*x*x*x*x=x` passes GF(5), fails GF(7) at `x=2`,
and fails integer testing at `x=2`. Sample agreement of `x*x` and `x` on `{0,1}`
never licenses universal substitution.

### Safe application and search comparison

`prepare-rewrite-library` accepts validated records and freezes typed matching
patterns. `start-rewriting` and `advance-rewriting` expose a resumable normalizer.
Every instantiated rewrite must strictly decrease packet length, or lexicographic
packet bits at equal length. This prevents commutativity cycles without requiring
confluence or an e-graph. The normalizer requires each substituted expression to
be syntactically provably total. Thus `0*x=0` can simplify `0*(a+b)`, but cannot
erase the error in `0*(1/0)`. Dropping an erroring conditional test is also blocked.
This conservative check may decline safe rewrites; it never infers totality from
the sampled input rows.

Guards are discharged only by literal truth or an exact predicate established by
the surrounding conditional branch. In a separate experiment, the grammar supplies
`-`, `/`, and `*`, and the observations use nonzero GF(5) inputs. With a **supplied**
nonzero guard, the buckets discover `x/x=1`. Exhaustive checking visits all five
inputs and validates the equation on the four active ones. The unguarded equation
fails at zero. A Boolean guard uses existing DSL constructs, for example
`if(x=0, false, true)`; no additional negation primitive is needed. Consequently,

```
if(x=0, 0, x/x)  -->  if(x=0, 0, 1)
```

is checked, while an unguarded `x/x` remains unchanged. This experiment proposes
86 laws from 114 expressions and 22 buckets. Observation, proposal construction,
and validation cost 88,007 units; the displayed rewrite costs 5,784 units plus
65 units for rule setup.
This is the supplied-guard control; the next experiment also discovers the guard.

### Discovering a guard from the rows where an equation holds

The new experiment starts with the full input domain, including zero. It enumerates
arithmetic expressions without supplying an equation to find, and uses the retained
per-row outcomes described above. For each pair of expressions of the same type,
the scaffold records a Boolean membership vector: a row is true exactly when both
expressions return values and those values are equal. A row is false when either
expression errors or the values differ. An unfinished evaluation supplies neither
label; observation must finish before this vector can be constructed.

For example, the pair `x/x` and `1` produces the following evidence in GF(5):

| Input `x` | `x/x` | `1` | Membership target for the guard |
|---:|---|---:|---|
| 0 | Division error | 1 | false |
| 1 | 1 | 1 | true |
| 2 | 1 | 1 | true |
| 3 | 1 | 1 | true |
| 4 | 1 | 1 | true |

The division error is evidence that this row must be excluded from the guard,
not evidence of equality. This is the proposed "retain a subset of non-error and
equal" operation, expressed as a membership vector over the original rows. Empty
subsets are discarded because they would support only vacuous laws. Agreement on
every row already belongs to the ordinary equality-bucket path.

The remaining question, "which inputs belong to this subset?", becomes an ordinary
synthesis task. `support-frame` copies the original input schema and rows, changes
the target type to Boolean, and gives each row the singleton requirement `{true}`
or `{false}` from this vector. `start-guard-search` then uses the existing enumerator,
VM, requirement checker, description-length objective, and resumable work budget.
The predictor sees only the original inputs. It cannot read the outcome records,
membership labels, or occurrence keys as additional arguments.

This is where the construction fits the residual machinery: after observing the
equation, the unresolved information is the membership of each input in its valid
subset. That information is represented by a normal frame, so existing frame and
sequence reconstruction operations can handle it. A test also reconstructs the
Boolean membership sequence through the existing quotient/occurrence residual
codec. The experiment itself searches the Boolean frame directly; it does not add
an automatic recursive decomposition scheduler. Keeping every row, including the
false rows, prevents the trivial guard `true` from passing and requires a guard
that recovers the **entire observed subset**, rather than a smaller convenient one.

Different equation pairs often have the same subset. `propose-guard-problems`
groups their membership vectors and runs one guard search per distinct vector.
Every equation pair is retained within its group. A successful predicate can thus
serve many equations without repeating the same synthesis task. `propose-guarded-laws`
attaches that predicate to each pair, but these proposals are still conjectures.
The existing law validator independently executes each complete guarded statement
over the full finite domain before issuing a certificate.

For the experiment, the observation grammar contains `-`, `*`, `/`, the input `x`,
and all field literals, with a 42-bit packet bound. The guard grammar contains
field equality, Boolean `if`, the input, and literals, with a 54-bit bound. Neither
`x/x=1` nor its nonzero guard is supplied to either search. Both runs recover the
guard `if(x=0, false, true)` for that equation. The guard costs 54 bits and its
complete guarded statement costs 92 bits. Independent validation visits all five
or seven field inputs, with four or six active assignments respectively.

| Domain | Expressions / erroring | Distinct proper subsets | Equation pairs on those subsets | Subsets with a guard at 54 bits | Validated guarded laws |
|---|---:|---:|---:|---:|---:|
| GF(5) | 114 / 12 | 16 | 2,390 | 6 | 2,306 |
| GF(7) | 200 / 16 | 31 | 6,404 | 8 | 6,229 |

As in the earlier experiment, these law counts include constant equations and
syntactic variants; they are not counts of independent algebraic principles. Each
law comes from one equation pair whose subset has a synthesized guard. Subsets
without a solution at the stated bound remain unresolved. A larger bound or a
different predicate vocabulary may express them; bounded exhaustion does not
establish that no guard exists.

All acquisition work is charged, including observations that error, subset
comparisons, child-frame construction, unsuccessful guard searches, proposal
construction, and independent validation:

| Domain | Full-row observations | Subset grouping, frames, proposals | Guard searches | Validation | Total acquisition |
|---|---:|---:|---:|---:|---:|
| GF(5) | 32,280 | 614,321 | 877,566 | 917,905 | 2,442,072 |
| GF(7) | 78,294 | 2,250,037 | 2,491,741 | 3,068,787 | 7,888,859 |

The tariff includes charges for retaining row outcomes, comparing and grouping
subsets, and constructing the resulting frames and equation proposals. The
existing execution and search charges are unchanged. The current implementation
compares all unordered expression pairs: 6,441 in GF(5) and 19,900 in GF(7), before
discarding empty and full subsets. This quadratic scan is synchronous and metered,
as is the earlier bucket-to-law proposal step. Observation, Boolean search, and
validation retain their interruptible jobs; the pair scan does not yet have its
own resumable continuation.

The learned and validated guard also works with the existing normalizer:
`if(guard, x/x, 0)` rewrites to `if(guard, 1, 0)`, while an unguarded `x/x` remains
unchanged. In each field run, this application costs 5,790 rewrite units plus 65
units for rule setup, separately from acquisition. This establishes usable guard
discovery on the declared finite domains, not a search speedup. For sampled scopes,
a predicate that fits the membership
vector can still overgeneralize. A test learns a nonzero guard for `x^4=1` from
GF(7) inputs `{0,1,6}`, then independently refutes the guarded equation at `x=2`.
Integer samples can likewise produce guard conjectures, but the current validator
cannot certify a universal integer law by exhaustive enumeration.

### Using AU to compress the discovered laws

This experiment asks whether AU can give a shorter, executable description of the
**actual collection of discovered law statements**. The target is their exact
syntax, including every guard, variable, literal, and operator, in the original
order. Comparing their Boolean outputs would be insufficient: thousands of valid
statements could all evaluate to `true` while expressing different equations.
Duplicate occurrences are retained. Provenance and validation certificates are
outside this declared syntax-storage task; reconstructing a statement does not
reconstruct or grant a certificate.

Each input corpus has one arithmetic domain and input schema. Each statement is
encoded as its complete canonical DSL packet, including its schema. A corpus
packet encodes a typed domain marker and the ordered list of these packets, with
all sequence lengths. That packet is ordinary Boolean-sequence data in the VM.
Consequently a closed decoder can reconstruct it using only its encoded data,
without fetching source laws, templates, or substitutions from the experiment
store. Decoding the result restores the individual statements and their schemas.

AU operates on the statement trees before they are serialized. For example,
`2+0=2` and `3+0=3`, with true guards, have the common equation template
`?x+0=?x`. Their residual substitutions contain the literal trees `2` and `3`.
The two occurrences of `?x` refer to the same tree within each substitution.
Operator holes work similarly, but carry a function signature and receive an
operator symbol. This structural generalization supplies a way to recover the
observed statements. It does not by itself prove the template for new substitutions.

`law-compression.lisp` translates the AU result into fixed bit fragments and
encoded hole fillings. Adjacent fixed parts are combined. A repeated fragment is
stored once in a dictionary, and an integer occurrence sequence records how to
reassemble every statement, including its lengths and position in the corpus.
The finished program has the form:

```
concat(gather(encoded-fragment-dictionary, encoded-occurrence-sequence))
```

The dictionary and occurrence sequence are literal data inside the program. The
human-readable AU template is compiled into these fragments and selectors; no
unpriced template is consulted at runtime. The ordinary codec prices the complete
program. `gather` uses the existing checked integer positions, and `concat` joins
the selected fragments. Neither primitive knows anything about algebraic truth.

Four complete descriptions are proposed: a literal corpus, a dictionary sharing
only whole statement packets, one AU template over the whole corpus, and AU
templates within groups of the same typed application shape. The last grouping
is a supplied structural view: it erases leaf values and compatible operator
names while retaining tree shape and types. It is not claimed to be a learned or
optimal partition. Both field corpora produce five such groups. Group-specific
substitutions are restored to their original occurrence positions before encoding.

**Acceptance and selection use the existing synthesis pipeline.** A normal frame
has no predictor inputs and requires the exact corpus packet as its output.
`start-search` now accepts an optional `:expressions` list of complete proposals,
analogous to observation replay. These proposals pass through the same construction
charges, VM evaluation, frame requirement checker, candidate records, objective,
and resumable work limits as enumerated programs. AU construction supplies the
candidates; it does not have a separate acceptance loop. Completion is reported as
`:replay-complete`, covering the declared list within the bit bound. It makes no
claim to exhaust arbitrary decoder programs, AU seeds, or partitions. The default
arithmetic enumeration path remains available with its existing coverage claim.

The corpora are all 2,306 and 6,229 independently validated guarded statements from
the preceding GF(5) and GF(7) discovery runs; no equation family is hand-selected.

| Domain | Literal | Whole-packet dictionary | One AU template | Shape-grouped AU | Selected reduction |
|---|---:|---:|---:|---:|---:|
| GF(5) | 238,967 bits | 303,967 bits | **157,885 bits** | 234,918 bits | 33.9% |
| GF(7) | 647,744 bits | 832,568 bits | **461,750 bits** | 648,098 bits | 28.7% |

The selected global pattern is `if(?guard, ?left = ?right, true)`, with the
arithmetic type fixed by the corpus. Its fragment dictionary shares recurring
guards and equation sides as well as fixed syntax. Thus the gain establishes
sharing of syntax across the law collection; it does not identify a basis of
independent algebraic principles. More detailed shape-specific templates cost
more here. The ordinary objective selects the simpler global representation.

The experiment runs both pure description minimization and
`J = S + lambda_run * W_run` with `lambda_run=1`. The global AU model wins in both.
A control with `lambda_run=100` selects the faster literal in both fields, checking
that the objective can prefer execution savings over the shorter description.

| Domain | Literal execution | Selected AU execution | AU score at `lambda_run=1` | Corpus/proposal construction | Core search per objective |
|---|---:|---:|---:|---:|---:|
| GF(5) | 955,714 | 966,611 | 1,124,496 | 9,269,635 | 17,206,870 |
| GF(7) | 2,590,814 | 2,663,760 | 3,125,510 | 41,203,742 | 46,809,871 |

These are compression-stage costs, additional to the law-acquisition totals
reported above. Construction includes corpus serialization, AU, matching, shape
grouping, fragment dictionaries, occurrence residuals, and the parent frame.
Proposal replay has a metered setup phase and charges for rejected descriptions
as well as successful ones. The current AU/proposal constructors are synchronous;
the core checking jobs and completed-model execution can be interrupted and resumed.
The result demonstrates storage savings, with modestly higher decoding work than
the literal. It does not establish that acquisition work has been amortized.

The selected program is independently encoded, decoded, and run with no inputs.
The recovered corpus matches every original statement exactly. The law validator
then rechecks all recovered statements over their finite domains, costing 917,905
and 3,068,787 additional units respectively. This uses the same VM as discovery;
no external algebraic validator is introduced. A separate control reconstructs an
unguarded `x/x=1` perfectly and still refutes it at zero, confirming that lossless
compression does not upgrade a false or unproved law.

This storage experiment still uses bit fragments. The following experiment takes
the next step: the VM receives expression trees as typed data and executes DSL
programs that construct and transform them.

### Quoted expressions and symbolic programs in the same VM

An expression can now be an ordinary frame input or output. Its type is
`(:code inputs sort)`: the result type of the represented expression together
with the variables it is allowed to mention. For example,
`(:code ((99 . :int)) :int)` describes an integer expression that may refer to
integer variable 99. The surrounding transformer has its own input schema.
Its input variable 0 might hold the quoted expression `x+0`, where `x` refers to
variable 99 inside that quoted value. Those are separate scopes.

Quotation does not execute its contents. A quoted `1/0` is valid syntax data and
can be inspected, compared, copied, or returned without division taking place.
The normal execution path still reports division by zero if that arithmetic
expression is submitted as a model. There is no DSL `eval`, host callback, closure,
or access to the observation store. Quoted values must be complete, well-typed
trees; undeclared variables and unresolved AU holes are rejected.

The symbolic vocabulary supplies structural operations:

| Operation | Meaning in a transformer |
|---|---|
| `code-kind`, `code-child`, `code-operator` | Inspect a node, select a checked child index, or extract an operator with the declared signature |
| `code-apply` | Construct an application from a quoted operator and a typed tuple of quoted arguments |
| `code-match`, `code-bind` | Match a typed template against a source tree; extract a named variable's matched subtree |
| `code-subst` | Simultaneously substitute quoted bindings into a template |
| `code-total` | Conservatively recognize syntax that is defined for every assignment of its declared inputs |
| `code-less` | Compare expressions by packet length, then lexicographic bits, for a strictly decreasing rewrite order |

Template variables are matching parameters. Repeated occurrences must match the
same tree. Source variables remain part of that tree; they are not read from the
transformer's environment. Substitution traverses application nodes, leaves type
metadata alone, and stops at literals, including nested quoted values. Inserted
trees are not substituted again. These rules reuse AU's matcher and frame
composition's substitution implementation.

The operations fit the existing accounting and failure model. Bad child indices,
wrong child types, missing bindings, and failed operator extraction are VM errors.
Lazy conditionals can guard those accesses. Quoted values pay for their full syntax
and type metadata. A symbolic primitive prepays one unit plus the structural work
of its operands; matching, binding, and substitution additionally pay the product
of their first two operand weights to cover repeated traversal or copying.
Ordering pays `4 * (1 + sum(operand weights) + type weight)`. This tariff is
a conservative structural measure, not a host timing measurement. Partial payment
keeps the operation unknown, with the same resumable continuation as arithmetic.

**Checked laws now execute as DSL transformers.** `prepare-rewrite-library` still
requires an unchanged exhaustive certificate in the same finite domain.
`compile-rule-transformer` then builds an ordinary DSL program taking a quoted
source and a sequence of quoted, established Boolean assumptions. That program
matches the source, checks that the matched substitutions are total, substitutes
into the guard and replacement, checks whether the guard is established, and
returns the replacement only when it decreases the ordering. Otherwise it returns
the source. This program can be encoded, decoded, and executed in isolation.

The normalizer in `laws.lisp` still schedules tree traversal and supplies branch
assumptions: the condition in a true branch, its negation in a false branch.
It also selects rules by the outer operator. Rule application itself now runs
through the VM, including matching, guard handling, substitution, and ordering.
`code-total` and `code-less` expose the structural checks already used by the
normalizer; they introduce no supplied algebraic identities. Certificates remain
scaffold evidence, and are not conferred by constructing a transformer. In
particular, an arbitrary quoted Boolean expression is not automatically an
established assumption.

**AU constructors are checked against the complete discovered corpora.** The
global AU pattern for each field becomes a constructor with three quoted inputs.
Each frame row supplies that statement's hole fillings and requires its exact
original guarded syntax. The ordinary `start-search` proposal path checks the
encoded-and-decoded constructor over every row:

| Corpus | Constructor bits | Execution work over all rows | Constructor/frame preparation | Complete search/replay work |
|---|---:|---:|---:|---:|
| GF(5), 2,306 statements | 247 | 1,255,732 | 400,000 | 2,258,927 |
| GF(7), 6,229 statements | 247 | 3,408,671 | 1,086,333 | 6,133,583 |

This is a function task with explicit residual inputs. The 247 bits describe the
constructor, not the entire stored corpus: the hole fillings and occurrence order
must also be encoded to claim compression. The preceding bit-fragment experiment
does price that complete object. Here the result establishes that typed symbolic
construction works inside the same VM and checker, including on actual discovered
laws. It does not prove the AU pattern for unseen substitutions.

**The canonical synthesizer can also search symbolic programs.** `grammar.lisp`
now accepts any of the VM's typed primitive signatures and input types. Explicit
typed literal constants supplement the numeric vocabulary; each pays its full
packet cost, and duplicate leaves are emitted only once. A small independent
enumeration control recovers `code-child(source, 0)` through ordinary bounded
search. There is no separate symbolic enumerator.

A second control exercises the residual route needed for later milestones. Eight
before/after rows require the transformation `term+0 -> term` for total terms,
and preservation of several nonmatches and a partial term. The supplied decoder
matches that shape and checks totality; its unknown is the child position to return.
`pullback-frame` turns the parent requirements into predicates on that integer.
The ordinary integer search discovers position 0 at a 15-bit bound, composition
inserts it into the decoder, and the core checker replays the complete parent.

| Subject domain | Composed transformer bits | Pullback/composition | Selector search | Complete parent replay |
|---|---:|---:|---:|---:|
| Integers | 324 | 2,630 | 7,335 | 5,686 |
| GF(5) | 416 | 4,097 | 14,087 | 10,972 |
| GF(7) | 416 | 4,097 | 14,087 | 10,972 |

Additional tests check held-out expression shapes and arithmetic assignments,
including large integers. This is a supplied-context control learning only the
selector, not discovery of the entire rewrite or proof of a universal integer law.
It demonstrates the intended connection: expression transformations use ordinary
frames, integer residuals, composition, enumeration, and VM checking.

### Cost of using checked equations in a second search

The search-reuse comparison uses only the discovered GF(5) rule `a+0=a` on the original
`y=a+2b` task. A normalized expression can reuse a previously witnessed rejection
in the same frame. Errors do not enter this cache. Every original syntax tree still
enters the enumeration buckets, and successful programs execute normally, retaining
their own description length and execution work. This provides a concrete use of
checked equality in search without conflating equivalent programs' execution costs.

| Same 61-bit synthesis bound | Plain search | Checked-rule search |
|---|---:|---:|
| Retained trees / successful programs | 649 / 10 | 649 / 10 |
| Reused rejections | 0 | 31 |
| Evaluation plus requirement checking | 158,150 | 150,418 |
| Total search work | 182,181 | 2,126,539 |

**This first implementation does not yield a net search speedup.** It saves 7,732
evaluation/checking units but spends 1,932,008 on rewriting and 19,536 on cache keys,
plus setup and scheduling. Rewriting now pays for constructing the DSL transformers
and their actual VM execution under the symbolic tariff above; traversal tasks
cost one. The current lowering repeats binding extraction and template substitution,
and recompiles the rule programs for each normalization job. Moving rule application
into the common VM therefore increases charged work compared with the previous
host implementation. GF(5) discovery, proposal construction, and all-law validation
add 369,230 units, giving **2,495,769** for acquisition plus checked reuse. The GF(7)
and guarded-law controls are separate experiments. Faster matching, cached normal
forms, or a more precise metered traversal would need their own measured comparison;
the current result establishes sound reuse, not amortized savings.

Subtraction, division, equality, and conditionals are supplied primitives. In
particular, the modular reciprocal inside division is host-implemented extended
Euclid. This is not learned inversion, and milestone 4's bootstrap experiments
have not been run. Their original `+`/`*` grammar remains available unchanged.

## Validation and implementation boundary

The combined suite passes **64 tests and 158,624 checks**. It retains the earlier
frame, runtime, and observation controls while merging duplicate encoding-specific
tests. Independent references enumerate tiny trees by application count and check
their values against host arithmetic. Tests also cover codec roundtrips and invalid
packets, signed payload boundaries, finite vocabulary snapshots, isolated replay,
correlated and empty fibers, lookup costs, occurrence reconstruction, typed matching,
repeated/operator holes, and aligned anti-unification.

Integer-position checks cover computed lookup keys feeding positional
reconstruction, zero and last positions, duplicates, empty sequences, negative
and oversized positions (including bignums), signed payload pricing, and exact
budget cutoffs immediately before successful or failing accesses. Removed index
types, retired packets, and unused type tags are rejected.

New checks cover truncating division with all sign combinations and large integers,
field division against an independent reciprocal reference, zero denominators,
lazy branches, and conditional type errors. A separate tiny-grammar reference
checks mixed Boolean/numeric binary and nested ternary enumeration; a synthesized predicate
is used directly as a frame requirement. Law controls check domain transfer,
vacuous/erroring guards, modified certificates, and error-preserving substitution.
Exhaustive evaluation of tiny GF(2) trees containing `+`, `*`, `-`, and `/` confirms
that normalization preserves both defined values and error status.
The identity `2*(x/2)=x` is checked in GF(5) and refuted at integer `x=3`, making
the effect of truncation explicit.

Guard-discovery checks compare every expression-pair subset in the two field runs
against independent host arithmetic, including an independently enumerated
reciprocal. They verify exact guard outputs, certificate coverage, and statement
codec roundtrips. Further controls cover successful Boolean false values, errors
on both sides, unequal defined values, whole-tuple equality, duplicate input
occurrences, scope isolation, multi-input guards, empty/full subsets, insufficient
predicate grammars, and sampled guards refuted outside their discovery rows.
Resumption tests cross row errors and partially paid outcome storage, compare unit
and batched execution, and extend a failed 53-bit guard search to success at 54
bits. Incomplete observations cannot silently become negative membership labels.

The AU compression controls cover repeated expression/operator holes, exact
guarded-statement reconstruction, domain and schema boundaries, input-free replay,
duplicate occurrences, and isolation from later source mutation. A deliberately
changed guard is rejected even when all statements still evaluate to `true`.
A tiny corpus where AU increases size selects the literal baseline. The full
discovered field corpora are reconstructed and independently revalidated. New
continuation checks cover concatenation and proposal replay, including setup,
first acceptance, final completion, growing description bounds, and coexistence
with the existing checked-rule search path.

Symbolic controls cover quotation without execution, free-variable scopes, nested
quotation boundaries, simultaneous substitution, repeated parameters, operator
signatures, bounds failures, and codec roundtrips. They check AU lowering with
operator holes, independent tiny symbolic enumeration, duplicate constants,
zero-argument constructors, residual-based transformation search, and isolated
checked-rule transformer replay. Symbolic copying, errors, and rewriting have
unit-versus-batched continuation checks. The visualizer exporter also preserves
quoted values as syntax without executing them.

Budget tests compare complete continuations and every ledger category, including
cutoffs immediately before and after measured first-solution and completion points,
partly paid large multiplications, and errors. Additional controls check that text
printer settings affect neither sizes nor work and that schema header length does
not affect enumeration work. The same continuation checks cover law validation,
normalization, and equality-constrained search. M1--M3 scripts assert their positive and negative
controls. The current linear benchmark smoke check agrees with M1's work and results;
the historical scaling timings have not been reinterpreted under the new tariff.

| File | Responsibility |
|---|---|
| `syntax.lisp`, `codec.lisp` | Typed trees, substitution, sole binary codec |
| `sim.lisp` | Structural tariff and resumable evaluator |
| `frames.lisp` | Requirements, reorientation, pullbacks, reconstruction |
| `grammar.lisp` | Typed grammar, snapshots, canonical enumeration |
| `search.lisp`, `observations.lisp` | Candidate checking, scheduling, empirical buckets |
| `au.lisp` | Typed matching and aligned syntactic anti-unification |
| `symbolic.lisp` | Quoted-code primitives, structural checks, AU constructor lowering |
| `laws.lisp` | Scoped certificates, DSL rule lowering, normalization traversal |
| `guards.lisp` | Agreement subsets, Boolean child frames, guarded-law proposals |
| `law-compression.lisp` | Law corpus packets, AU descriptions, ordinary reconstruction frames |
| `fixtures.lisp`, `experiments.lisp`, `law-experiments.lisp` | Fixtures and milestone runs |
| `tests/` | Separate harness, core/observation/codec/law/guard/compression/symbolic suites, visualizer checks |

The cleanup separates grammar/enumeration from search orchestration and moves
the test harness and suites out of the source modules. Language snapshots now
share one implementation. Search, observation, law validation, and rewriting
share `advance-accounted-evaluation` for VM work and unpaid-error accounting.
Matching and substitution are shared by frames, AU, and symbolic primitives;
there is no second implementation of those mechanics inside the rule compiler.

Milestone 4 remains deferred: no inverse-rule search or inverse-value enumeration
is implemented. E-graphs, general theorem proving, multi-level automatic
decomposition, library learning, and general recursive orchestration are also later
work. The fixed encoding and accounting boundary will remain stable unless a concrete
result calls for revisiting them.

### Deferred option: runtime compilation of DSL expressions

The evaluator is compiled Lisp, while DSL expressions remain interpreted data.
The rule and AU lowering above produces DSL ASTs, not native executable code.
Revisit selective lowering of frequently reused predicates, accepted models, or
library functions when repeated execution warrants it. First consider caching sizes
and validation results, then measure compilation against that baseline. Frames remain
structured data, with their executable expressions eligible for compilation.

Keep the typed AST, binary encoding, and provenance authoritative. Compiled caches
must include the expression, input schema, and implementation versions, and preserve
integer/field semantics, isolation, errors, and exact tariff cutoffs. Compilation
would need budget checks and resumable state, or a sufficient-budget fast path with
VM fallback. Integer instruction costs depend on intermediate values and cannot
generally be prepaid as one fixed total.

The break-even condition is $C_{\rm compile}<N(T_{\rm interpreted}-T_{\rm compiled})$,
including bookkeeping in both times. Include compilation time and retained code
memory in measurements, and declare any abstract compilation charge. No native-code
DSL compiler or compilation speedup is implemented or claimed yet.
