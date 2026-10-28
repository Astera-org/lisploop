# lisploop --- results

27 October 2026. Current implementation of milestones 1--3 in [plan 4](plan4.md).
There is one fixed binary description encoding (version 4) and one structural
work tariff (version 3), with simulator semantics version 2. Their version numbers identify the specification; they
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

Tested with SBCL 2.6.4; no external Lisp libraries are required. Scripts load
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

Types include integers, Booleans, indices, prime fields, tuples, and finite
sequences. Integer arithmetic is exact with no fixed bit-width limit. Field values
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

`codec.lisp` implements the sole encoder and decoder. A packet includes its version,
ordered input schema, result type, and expression body. The schema header is paid
once per standalone model. Nested expressions share it. Variable references use
their position in the declared input order, with $\lceil\log_2 m\rceil$ bits for
$m$ inputs; a single available input needs zero slot bits.

Every expression uses the same two-bit constructor tags: `00` for a variable,
`01` for a literal, and `10` for an application (`11` is reserved). An application
then uses a fixed four-bit opcode: `+`, `*`, equality, tuple construction,
membership, lookup, gather, `-`, `/`, or `if`. Arity and operand types follow from the operator
and expected type; otherwise the necessary operand type is encoded explicitly.
There is no special arithmetic profile.

Signed integer $n$ maps to positive $z=2n+1$ for $n\geq0$, or $z=-2n$ otherwise.
If $L$ is the bit length of $z$, its self-delimiting payload costs
$D(z)=L+2\lfloor\log_2 L\rfloor$ bits. Encode the binary representation of $L$
preceded by one fewer zero than its own bit length, then the lower $L-1$ bits of
$z$. This supplies both payload and boundary information. A field value instead
uses $\lceil\log_2 p\rceil$ bits; unused bit patterns are rejected.

The header encodes version `4`, input count plus one, each input ID plus one,
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

Version 4 widens the opcode because ten primitives no longer fit in three bits;
the version field itself grows by one bit. All M1/M2 measurements below were rerun.
This changes the relative placement of expressions and unrestricted integer literals,
even though addition and multiplication retain their previous execution costs.

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
Integer addition and subtraction cost the larger operand magnitude width;
multiplication and truncating division cost their width product. Fixed fields with
primes at most 257 retain a unit arithmetic tariff. For larger fields, division adds
the cube of the modulus width for extended Euclid; other arithmetic adds its square
for reduction. A conditional branch dispatch costs one unit and does not charge
execution of the unselected branch; validation still visits its syntax.
Other primitives charge their operand value visits and payloads.

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

`finite-allowed` represents sets of whole output values; `predicate-allowed`
represents a Boolean AST over the proposed value. Correlated tuple requirements
are not split into independent coordinates. A supplied pullback substitutes a
decoder into the parent's requirement, forming a child predicate without listing
inverse values. Composition then substitutes the child expression into its parent
and rechecks the complete result. Lookups, partition contents, quotient representatives,
and occurrence-index residuals are encoded inside their reconstruction programs.

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

The function and ordered sequence remain different tasks. A full compression
comparison must specify the input grid and ordering. The formula costs fewer bits
than either displayed baseline, but this alone is not a complete store-compression
claim. Discovery examines 649 expressions and costs **182,181 work units**; the
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
and validation cost 88,007 units; the displayed rewrite costs 1,078 units plus
65 units for rule setup.
Guard discovery is not claimed.

The second synthesis run uses only the discovered GF(5) rule `a+0=a` on the original
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
| Total search work | 182,181 | 674,853 |

**This first implementation does not yield a net search speedup.** It saves 7,732
evaluation/checking units but spends 480,322 on rewriting and 19,536 on cache keys,
plus setup and scheduling. Its rewrite tariff deliberately prepays a conservative
structural bound: source `syntax-work` times the combined pattern, replacement, and
guard `syntax-work`, plus one, per attempted rule; other rewrite tasks cost one.
This covers matching, totality inspection, substitution, and ordering without hiding
them outside the budget. GF(5) discovery, proposal construction, and all-law validation
add 369,230 units, giving **1,044,083** for acquisition plus checked reuse. The GF(7)
and guarded-law controls are separate experiments. Faster matching, cached normal
forms, or a more precise metered traversal would need their own measured comparison;
the current result establishes sound reuse, not amortized savings.

Subtraction, division, equality, and conditionals are supplied primitives. In
particular, the modular reciprocal inside division is host-implemented extended
Euclid. This is not learned inversion, and milestone 4's bootstrap experiments
have not been run. Their original `+`/`*` grammar remains available unchanged.

## Validation and implementation boundary

The combined suite passes **41 tests and 19,425 checks**. It retains the earlier
frame, runtime, and observation controls while merging duplicate encoding-specific
tests. Independent references enumerate tiny trees by application count and check
their values against host arithmetic. Tests also cover codec roundtrips and invalid
packets, signed payload boundaries, finite vocabulary snapshots, isolated replay,
correlated and empty fibers, lookup costs, occurrence reconstruction, typed matching,
repeated/operator holes, and aligned anti-unification.

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
| `search.lisp`, `observations.lisp` | Enumeration, checking, empirical buckets |
| `au.lisp` | Typed matching and aligned syntactic anti-unification |
| `laws.lisp` | Scoped validation certificates and guarded normalizer |
| `fixtures.lisp`, `experiments.lisp`, `law-experiments.lisp` | Fixtures and milestone runs |
| `tests.lisp`, `observation-tests.lisp`, `codec-tests.lisp`, `law-tests.lisp` | Unified test suite |

Milestone 4 remains deferred: no inverse-rule search or inverse-value enumeration
is implemented. E-graphs, general theorem proving, multi-level automatic
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
