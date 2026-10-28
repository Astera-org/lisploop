# lisploop --- results

27 October 2026. Current implementation of milestones 1 and 2 in [plan 4](plan4.md).
There is one fixed binary description encoding (version 3) and one structural
work tariff (version 2). Their version numbers identify the specification; they
are not selectable alternatives. Earlier measurements and explanations remain in
[the historical results](results-history.md), tied to Git revision `f6bf54ef`.

```sh
make test                       # contracts, independent references, codec and work checks
make m1                         # GF(5) and integer synthesis experiments
make m2                         # GF(5) and integer observation experiments
make results.pdf                # Pandoc / LaTeX report
make benchmark                  # scaling and dispatch measurements under current accounting
sbcl --load load.lisp            # interactive inspection
```

Tested with SBCL 2.6.4; no external Lisp libraries are required. Scripts load
relative to their own location. The default Make target builds the planning
documents, this report, and the historical report with the same Pandoc settings.
`make m1` and `make m2` write the current traces to
[milestone1.txt](intermediate_results/milestone1.txt) and
[milestone2.txt](intermediate_results/milestone2.txt).

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

Types include integers, Booleans, indices, prime fields, tuples, and finite
sequences. Integer arithmetic is exact with no fixed bit-width limit. Field values
are canonical residues and field arithmetic reduces modulo the declared prime.
Expressions are typed literal, variable, or application trees. They contain no
host callbacks or pointers to the observation store.

`codec.lisp` implements the sole encoder and decoder. A packet includes its version,
ordered input schema, result type, and expression body. The schema header is paid
once per standalone model. Nested expressions share it. Variable references use
their position in the declared input order, with $\lceil\log_2 m\rceil$ bits for
$m$ inputs; a single available input needs zero slot bits.

Every expression uses the same two-bit constructor tags: `00` for a variable,
`01` for a literal, and `10` for an application (`11` is reserved). An application
then uses a fixed three-bit opcode: `+`, `*`, equality, tuple construction,
membership, lookup, or gather. Arity and operand types follow from the operator
and expected type; otherwise the necessary operand type is encoded explicitly.
There is no special arithmetic profile.

Signed integer $n$ maps to positive $z=2n+1$ for $n\geq0$, or $z=-2n$ otherwise.
If $L$ is the bit length of $z$, its self-delimiting payload costs
$D(z)=L+2\lfloor\log_2 L\rfloor$ bits. Encode the binary representation of $L$
preceded by one fewer zero than its own bit length, then the lower $L-1$ bits of
$z$. This supplies both payload and boundary information. A field value instead
uses $\lceil\log_2 p\rceil$ bits; unused bit patterns are rejected.

The header encodes version `3`, input count plus one, each input ID plus one,
the input types, and the result type. Positive counts use the same self-delimiting
code. Three-bit type tags identify integers, Booleans, indices, fields, tuples,
and sequences; moduli, tuple arities, and component types follow where needed.
Sequence lengths and index values are encoded after adding one. Boolean payloads
cost one bit; tuple values concatenate their typed components.

```{=latex}
\begin{figure}[tbp]
\centering
\setlength{\fboxsep}{10pt}
\fbox{\begin{minipage}{\dimexpr\linewidth-2\fboxsep-2\fboxrule\relax}
\small
```

**Concrete costs with two integer inputs `a`, `b`.** The header costs 22 bits.
Each variable body costs $2+1=3$ bits. Addition costs a two-bit application tag
and a three-bit opcode, so

$$S(a+b)=22+5+3+3=33\text{ bits}.$$

Literal bodies cost 3 bits for `0`, 6 for `±1`, 7 for `±2,±3`, and 10 for
`±4,...,±7`. Exactly 15 integer literals are strictly cheaper than the 11-bit
body of `a+b`; another 16 tie with it. The integer vocabulary remains unrestricted.
The change from the pilot's 8-bit body is the explicit operator code.

For GF(5), the corresponding header is 37 bits; a field literal body costs
$2+3=5$ bits. Thus field `a+b` costs $37+11=48$ bits, and `a+(b+b)` costs
$37+19=56$ bits. Encoding size and execution work are separate quantities.

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

### Structural work tariff

Let $w(n)=\max(1,\operatorname{bitlength}(|n|))$. `value-work` charges one visit
per scalar or container, plus raw scalar payload widths: a sign bit and $w(n)$
for integers, $w(n)$ for indices, one bit for Booleans, and the fixed field width
for residues. Containers additionally charge each component recursively. For
example, a sequence of 100 empty tuples incurs 101 visits even though its encoded
contents are small.

`syntax-work` charges one visit per AST node, visits to its explicit types, and
raw payload widths for literals, variable IDs, and moduli. Construction, copying,
composition, pullback construction, and validation use this structural measure.
Validation additionally charges the supplied input IDs, types, and values.
Evaluation charges one per visited expression node plus literal payload work.
Integer addition costs the larger operand magnitude width; multiplication costs
their width product. Fixed fields with primes at most 257 retain a unit arithmetic
tariff; larger fields include the declared bit-sensitive reduction charge.
Other primitives charge their operand value visits and payloads.

Observation setup and indexing charge input/output value visits and pair/start
comparison counts. Reorientation charges the copied values, and does not rerun
the simulator. Enumeration and scheduling retain fixed cursor/dispatch charges;
the auxiliary matching, abstraction, partition, and quotient routines retain their
declared traversal counters. These are deterministic abstract tariffs, not hardware
instruction counts. Wall time is reported separately; reporting and test harness
work, including isolated codec checks, are outside the search ledger.

## Search, interruption, and reuse

`make-language` declares the domain, inputs, and binary arithmetic primitives.
It admits all domain literals by default; a finite `:literals` vocabulary remains
available for explicitly constrained tasks, but the milestone runs use all literals.
The current enumerator covers homogeneous `+`/`*` arithmetic; the codec and evaluator
also support the richer executable DSL used by requirements and reconstruction.

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

`finite-allowed` represents sets of whole output values; `predicate-allowed`
represents a Boolean AST over the proposed value. Correlated tuple requirements
are not split into independent coordinates. A supplied pullback substitutes a
decoder into the parent's requirement, forming a child predicate without listing
inverse values. Composition then substitutes the child expression into its parent
and rechecks the complete result. Lookups, partition contents, quotient representatives,
and occurrence-index residuals are encoded inside their reconstruction programs.

## Milestone 1: synthesis

The simulator generates the complete GF(5) table for `y=a+2*b`; only the declared
input/output frame enters search. The search completes 48 bits without a predictor,
then extends to 58 bits, the encoded size of the fixture oracle. It finds
`a+(b+b)` at 56 bits, along with nine other valid formulas. All 25 inputs pass
independent decoding and replay. The supplied pullback control discovers `b+b`
from the child requirement `a+z=y`, then reconstructs and checks the parent.
Contradictory singleton outputs for identical inputs yield no candidate.

| GF(5) representation | Total bits | Execution work on 25 inputs |
|---|---:|---:|
| Discovered `a+(b+b)` | 56 | 1,375 |
| Encoded executable lookup | 312 | 28,750 |
| Literal ordered target sequence | 102 | Different whole-object task |

The function and ordered sequence remain different tasks. A full compression
comparison must specify the input grid and ordering. The formula costs fewer bits
than either displayed baseline, but this alone is not a complete store-compression
claim. Discovery examines 649 expressions and costs **182,138 work units**; the
first formula is accepted at 22,686. Original acquisition, baseline construction,
and independent replay add 35,031 units. The supplied-child control has separate
ledgers: 3,879 for child search and 4,230 for pullback, composition, and parent replay.

The integer counterpart uses all 25 inputs in $[-2,2]^2$ and unrestricted signed
literals. It completes a 41-bit bound, retaining 2,715 expressions and six valid
formulas. `a+(b+b)` costs 41 bits and is first accepted at 247,862 work units;
complete discovery costs **301,343**. It passes six fresh signed pairs around
$2^{256}$, including cancellation and adjacent integers. Execution work is 862
on the training rows and 6,342 on fresh rows. Original generation, orientation,
and independent replay cost 3,185; the fresh-data stage costs 26,814. Integer
evidence remains finite observations, while the GF(5) table covers its full domain.

## Milestone 2: observed equivalence and invariants

An observation scope fixes its input rows, types, grammar, versions, typed-value
equality, and optional before/after pairs and starting rows. Each expression's
complete output vector is indexed in a bucket with all other expressions producing
that vector and type. Every syntax alternative is retained. Errors preserve their
diagnostic and work but supply no equality evidence; interrupted evaluations remain
unknown. Agreement is only asserted within the exact same scope.

The field experiment records five steps from each of `(0,0)` and `(0,1)` under
$T(a,b)=(a+1,b+4)$ over GF(5). Reorientation produces 20 probes from ten transitions.
The integer experiment records three steps from each of `(-3,1)`, `(0,0)`, and
`(2,3)` under $T(a,b)=(a+1,b-1)$, producing 18 probes from nine transitions.
The search asks for a program whose value is unchanged across each pair and varies
across starts. Constants satisfy invariance but fail the variation requirement.

| Domain | Total bound | Expressions / buckets | Returned programs | Discovery work |
|---|---:|---:|---|---:|
| GF(5) | 48 bits | 15 / 13 | `a+b`, `b+a` | 13,004 |
| Integers | 33 bits | 51 / 39 | `a+b`, `b+a` | 30,549 |

Exactly one informative bucket contains both sums in each experiment. Field sums
stay at 0 and 1 along the two trajectories; integer sums stay at $-2,0,5$.
Execution work per sum is 800 over the field probes and 452 over the integer probes.
Original transition generation and reorientation add 1,150 and 711 units, respectively.
Extending the field bound to 52 bits includes all 105 single-application expressions
and costs 117,988 units. This larger bound does not change the informative bucket.

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

## Validation and implementation boundary

The combined suite passes **30 tests and 8,803 checks**. It retains the earlier
frame, runtime, and observation controls while merging duplicate encoding-specific
tests. Independent references enumerate tiny trees by application count and check
their values against host arithmetic. Tests also cover codec roundtrips and invalid
packets, signed payload boundaries, finite vocabulary snapshots, isolated replay,
correlated and empty fibers, lookup costs, occurrence reconstruction, typed matching,
repeated/operator holes, and aligned anti-unification.

Budget tests compare complete continuations and every ledger category, including
cutoffs immediately before and after measured first-solution and completion points,
partly paid large multiplications, and errors. Additional controls check that text
printer settings affect neither sizes nor work and that schema header length does
not affect enumeration work. M1 and M2 scripts assert their positive and negative
controls. The current linear benchmark smoke check agrees with M1's work and results;
the historical scaling timings have not been reinterpreted under the new tariff.

| File | Responsibility |
|---|---|
| `syntax.lisp`, `codec.lisp` | Typed trees, substitution, sole binary codec |
| `sim.lisp` | Structural tariff and resumable evaluator |
| `frames.lisp` | Requirements, reorientation, pullbacks, reconstruction |
| `search.lisp`, `observations.lisp` | Enumeration, checking, empirical buckets |
| `au.lisp` | Typed matching and aligned syntactic anti-unification |
| `fixtures.lisp`, `experiments.lisp` | Isolated fixtures and both milestone runs |
| `tests.lisp`, `observation-tests.lisp`, `codec-tests.lisp` | Unified test suite |

Milestones 3 and 4 remain deferred: no learned-law application, inverse-rule search,
inverse-value enumeration, or semantic pruning is implemented. Multi-level automatic
decomposition, library learning, and general recursive orchestration are also later
work. The fixed encoding and accounting boundary will remain stable unless a concrete
result calls for revisiting them.

### Deferred option: runtime compilation of DSL expressions

The evaluator is compiled Lisp, while DSL expressions remain interpreted data.
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
memory in measurements, and declare any abstract compilation charge. No DSL compiler
or compilation speedup is implemented or claimed yet.
