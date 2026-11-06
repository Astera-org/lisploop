---
header-includes:
  - \usepackage{tikz}
  - \usetikzlibrary{arrows.meta,positioning,fit,backgrounds,calc}
---

# Lisploop Architecture Reference

This reference describes the current Common Lisp kernel. The Lisp source is authoritative; [plan7.md](plan7.md) separates the implemented experiments from the remaining research program motivated by [prompt4.md](prompt4.md). [plan6-refactor.md](plan6-refactor.md) records the earlier audit and refactor.

The kernel has **nine implementation modules**, plus `package.lisp` and the loader. Current accounting versions are **encoding 7, tariff 9, simulator 5**. Historical reports in [deprecated/results.md](deprecated/results.md) and [deprecated/results-history.md](deprecated/results-history.md) retain their original versions and are not current execution traces.

## 1. Purpose and implementation boundary

Lisploop experiments with typed program synthesis, observational invariants, guarded algebraic laws, factorization, causal reorientation, and recursive decomposition of synthesis problems. Programs, predicates, and quoted syntax use the same S-expression representation. Frames, jobs, laws, certificates, and proposal records use host Lisp structs around those expressions.

The implemented search is bounded and experimental. Supplied decoders, feature vocabularies, locality keys, and candidate lists are explicit inputs, not discoveries. Tests distinguish supplied controls from grammar-discovered artifacts. The kernel has no general recursive object-language functions, learned function registry, learned scheduler, or cross-branch child-problem cache.

Three resource quantities remain distinct:

$$
S(M),\qquad W_{\mathrm{run}}(M),\qquad W_{\mathrm{search}}(P).
$$

A small program can be expensive to execute, and discovering it can be more expensive still. The structural work tariff is not elapsed time.

## 2. Representation and execution contracts

### 2.1 Types, schemas, and expressions

A `schema` contains `domain`, `inputs`, `target`, and `lookup-p`. Inputs are an ordered association list of variable IDs and types. `make-schema` infers a numeric domain from the types unless one is supplied; frame and expression construction validate the relevant types.

Supported types are:

| Type | Runtime value |
| :--- | :--- |
| `:int` | Arbitrary-precision signed integer |
| `(:gf p)` | Integer in $0,\ldots,p-1$; `gf` checks that $p$ is prime |
| `:bool` | `nil` or `t` |
| `(:tuple ...)` | Proper list of the specified component types |
| `(:seq type)` | Proper list of homogeneous elements |
| `(:code inputs sort)` | Typed syntax or an operator in the declared scope |

A quoted syntax literal `(lit (code-type inputs sort) expression)` evaluates to syntax data. It does not evaluate that syntax. The DSL has no `:code-eval`, host `eval`, or arbitrary host-call primitive.

Variables and holes are pooled uninterned symbols. Literals are two-element lists headed by a typed quote symbol; applications are ordinary lists headed by an operator or function-sorted hole. The actual constructors are `var`, `hole`, `lit`, `op`, and `app`; operator holes use `(hole id '(:fn argument-types return-type))`, with no `:kind` keyword.

`*node-meta*` caches type, non-variable bits, variable count, structural work, conservative totality, and free variables in a weak `eq` table. Cached metadata access is cheap, but `body-size` and `description-size` recursively validate expression scope and types. They are not constant-time size APIs. Metadata for copied trees can be reconstructed by `ensure-ast-meta`.

The fixed vocabulary has **21 operators**:

- Twelve object operators: `:+`, `:*`, `:=`, `:tuple`, `:member`, `:lookup`, `:gather`, `:-`, `:/`, `:if`, `:concat`, `:at`.
- Nine symbolic operators: `:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`, `:code-subst`, `:code-total`, `:code-less`.

There is no general numeric ordering operator. `:code-less` orders syntax by encoded size and then bits. Integer division truncates toward zero; field division uses `field-reciprocal`. Conditionals are lazy. Bounds violations, missing lookup keys, and division by zero are evaluation errors.

### 2.2 Frames, requirements, pairs, and anchors

A `frame` contains `schema`, `rows`, `pairs`, and `anchors`. A row is

$$
\omega=(\mathrm{key}_\omega,\mathbf{x}_\omega,A_\omega(Y)).
$$

`row-known` supplies the runtime inputs. `row-key` identifies the occurrence and is not an implicit predictor input. `row-requirement` is a Boolean AST whose only possible free variable is `(var 0 target-type)`.

`singleton-requirement` constructs equality; `set-requirement` constructs membership in an explicit list. `extract-allowed-values` also recognizes complete tuple-coordinate constraints, but returns `:unknown` for arbitrary predicates. Failure to extract witnesses does not prove a predicate false.

Ordinary synthesis checks requirements independently by row. Observation search additionally classifies cross-row relations:

$$
\begin{aligned}
\mathrm{invariant}(e)&\iff
\mathrm{pairs}\ne\varnothing
\;\land\;
\forall(a,b)\in\mathrm{pairs},\ e(\mathbf{x}_a)=e(\mathbf{x}_b),\\
\mathrm{informative}(e)&\iff
\mathrm{invariant}(e)
\;\land\;
\text{at least two anchor outputs differ}.
\end{aligned}
$$

All outputs must be successfully evaluated to enter an observation bucket. Anchors do not enforce pairwise distinctness, margins, or an ordering. Neither ordinary `search-job` acceptance nor heuristic residual scoring enforces these linkage classifications.

`partition-pairs-and-anchors` builds adjacent chains within blocks containing at least two rows and selects one representative from each such block. It returns anchors only when at least two multi-row blocks contribute. Singleton blocks do not contribute anchors. `with-frame-linkage` attaches supplied or computed linkage; `make-observation-scope` snapshots it and translates row keys into indexes.

### 2.3 Encoding and model artifacts

`encode-model` serializes an ordinary expression with its input signature; `decode-model` reconstructs it. `lookup-model`, `quotient-model`, `partition-model`, and corpus constructors all return ordinary ASTs, not distinct model wrappers.

Encoding v7 uses Elias delta codes for positive integers, zigzag mapping for signed integers, typed headers, two-bit AST tags, and four-bit operator tags with an extension for indexes at least 15. Headers encode the version, input count, each input ID and type, and the target type. Variable references in bodies use positions in the input signature; changing IDs can change header cost.

For $m$ inputs, the cached body formula is

$$
S_{\mathrm{body}}(e)=
\mathrm{nonvarbits}(e)+
\mathrm{varcount}(e)\,\mathrm{integer\text{-}length}(\max(0,m-1)),
$$

after validation. Quotation, types, literal payloads, permutations, representatives, and occurrence indexes are not free.

### 2.4 VM, work, and interruption

`vm.lisp` defines the ledger and the one resumable `evaluation` machine. Its states are `:unknown`, `:value`, and `:error`; a higher-level job reports `:cutoff` when its budget ends.

`start-evaluation` validates the raw expression and inputs. `start-program-validation` returns an evaluation whose successful value is a `validated-program`; `start-validated-evaluation` reuses static preparation while checking new input values. There is no separate `prepare-program` or `execute-model` API.

Instructions prepay structural work through `evaluation-remaining-cost`. Arithmetic on fields with $p\le257$ has unit primitive cost. Integer addition/subtraction cost the maximum operand width; multiplication/division cost the product of widths. Larger fields add the modular penalty specified by `arithmetic-cost`. Validation, traversal, and data operations charge additional work. `value-work` uses structural visits and raw payload widths, not compressed code length.

Errors arising before an instruction can be priced are accounted for by the job adapter `advance-accounted-evaluation`. Tests cover one-unit versus batched continuation and ledger parity, including errors.

Resumable search/controller budgets are absolute cumulative limits. `with-work-limit` bounds additional work in synchronous helpers; nested calls cannot renew an enclosing allowance. Synchronous view and fiber helpers return cutoff information but no resumable traversal cursor.

The recursive controller stages some atomic host preparation privately and drains its tariff debt before publishing results. This is accounting preemption, not interruption of arbitrary host traversals or a wall-clock deadline.

## 3. The four operations

### 3.1 Observational conservation

`enumeration-step` generates typed ASTs in nondecreasing body-size tiers under a `language`. `literal-range` derives integer payload intervals for each tier. Syntax alternatives are retained; empirical equality is not a global rewrite certificate.

`start-search` / `resume-search` check either enumeration or supplied `:expressions` against unary row requirements. Accepted candidates are stored in `search-job-results`; `search-job-proposals` holds the supplied replay list, not accepted child results.

`start-observation-search` evaluates expressions over a frozen `observation-scope`. Complete typed output vectors determine `observation-bucket` membership. Optional outcome retention records errors as well as values. Additional evidence is evaluated in a new scope; there is no automatic in-place refinement of a previous job.

`laws.lisp` proposes equations and exact support guards. `start-law-validation` exhausts supported finite inputs unless `:samples` is supplied. Law inputs and equation result types may be the ambient scalar domain, Booleans, or nested tuples over those types (`law-type-p`); the exhaustive validator enumerates finite scalar and tuple product grids (`finite-type-p`, `finite-type-cardinality`, `law-assignment`). Explicit samples never produce a certificate, even if they happen to cover a finite domain.

### 3.2 Factorization and fiber proposals

`anti-unify` returns a typed shared pattern and substitutions, memoizing repeated disagreement tuples. `compile-au-constructor` lowers a pattern into symbolic DSL construction. `discover-subexpression-abstractions` searches occurrence correspondences using bounded pair proposals and greedy extensions, then constructs reconstructing corpus ASTs. It is not a globally optimal subgraph or compression solver.

`quotient-values` returns first-occurrence representatives and occurrence indexes. `partition-rows` retains positions for exact ordered reassembly, including ties and duplicates. Corpus encodings preserve syntax; a validated rewrite can provide an alternate normalized corpus, not silently replace exact original spelling.

For row predicates $B_\omega$, define

$$
\mathrm{Fiber}(\omega)=\{z:B_\omega(z)=\mathrm{true}\}.
$$

`tighten-same-input-requirements` intersects predicates only for identical complete input tuples, including empty tuples. It does not choose coordinate projections.

`infer-fibers` proposes shared-value blocks by bounded partition search. Its lexicographic proxy minimizes class count, then repeated requirement body bits, then maximizes class concentration. This is neither Hard EM nor global MDL optimization; concentration is not Shannon entropy. The legacy `hard-em-...` test names remain.

A conjunction that does not simplify to false may still be unsatisfiable. The return contract is `(values classes labels refined-frame partition status)`. A branch-limit cutoff can retain a proposal with `:search-status :cutoff`; interruption by the total work limit returns nil proposal values and a cutoff message. Feasibility remains `:unresolved` until downstream witnesses and reconstructions are checked.

### 3.3 Reorientation, pullback, simplification, and propagation

`orient-observations` reuses recorded columns without simulation. It preserves per-occurrence requirements; it does not silently union conflicting targets after projecting away inputs. Arithmetic relation orientation separately constructs forward relational predicates that retain empty and multi-valued fibers.

For decoder $Y=d(X,Z)$, `pullback-frame` computes

$$
B_\omega(Z)=A_\omega(d(\mathbf{x}_\omega,Z))
$$

by substitution and evaluates the declared child input bindings. It **does not call `fold-constants`**, propagate pair/anchor relations, or introduce an inverse solver.

`fold-constants` lives in `requirements.lisp`. It conservatively evaluates closed subtrees and applies totality-guarded structural reductions under one local budget. Errors and unfinished evaluations retain their expression; they do not become false. It intersects finite constraints and can reconstruct tuple-coordinate equalities, but contains no built-in table inversion.

`frame-conflict-p` uses folding to detect false rows or incompatible requirements on identical inputs. It returns a `frame-conflict` struct or nil. It does not replace the frame with the folded predicates, and nil means no detected contradiction. Cost includes expression traversal and evaluation; it is not generally linear in row count alone.

`propagate-arithmetic-child` uses learned witness/guard programs. Certified witness and uniqueness laws authorize equivalent singleton replacement on applicable rows. Tentative witnesses are forward checked and retain an original fallback frame. `propagation-search` schedules primary search, original-frame verification, and a fallback reserve every fourth quantum. Certification is attached to `arithmetic-propagator`; there is no `propagation-certified-p` accessor.

### 3.4 Heuristic condensation and recursive search

`start-heuristic-search` / `resume-heuristic-search` in `synthesize.lisp` evaluate candidate expressions against the original requirements. The convenience wrapper `condense-heuristic` and `heuristic-model` struct remain in `factor.lisp`.

For miss indexes $I$, the implemented score is

$$
J(h)=S(h)+
\begin{cases}
0,&I=\varnothing,\\
L_+(|I|+1)+\displaystyle\sum_{i\in I}\bigl[L_+(i+1)+L_\tau(w_i)\bigr],&I\ne\varnothing
\end{cases}
+\lambda_{\mathrm{run}}W_{\mathrm{run}}(h).
$$

Here $L_+$ is `positive-bit-size`, $L_\tau$ is `value-bit-size`, and $w_i$ is the first explicitly extractable witness for the row. A hit accepts any value satisfying the original predicate. If a miss has no available correction witness, the candidate is not scored. The miss cost depends on physical row index and replacement value, not prediction distance. There is no correction-packet serializer or automatic lookup-baseline comparison in this API.

The returned `heuristic-model` retains its training residual for inspection. A consumer deploys `heuristic-program` alone to omit it. No general scheduler currently consumes the learned heuristic.

`decomposition` has slots `name`, `decoder`, `child-id`, `child-type`, `bindings`, `language`, `bound`, `children`, and `fiber-p`. There is no solver slot. Arithmetic propagation is available through its own adapter and the view helpers, not automatically inside every recursive node.

`start-synthesis` retains direct root search and supplied decomposition trees. Nodes progress through preparation and child search. `reconstruct-synthesis-candidate` composes a child through all ancestors; `synthesis-verification-step` checks and scores the resulting AST on the original root frame. `compose-model` inlines expressions, so repeated bindings pay repeated syntax and execution costs.

Every fourth scheduling quantum reserves the active root. Other quanta prioritize pending verification and otherwise round-robin active children. This preserves root progress within the configured grammar/bound; it is not a fourfold wall-time bound or unrestricted completeness claim. Completed reconstructions may exceed the direct root enumeration bound.

`dependency-proposals` supplies empty-input and coordinate hypotheses, or explicit feature expressions. `start-dependency-search` first enumerates and observationally groups features, then submits their induced decompositions alongside direct search. `start-selector-search` separately supports fiber and dependency proposals. These are distinct entry points, not one automatic pipeline.

## 4. Views and locality

The view APIs live in `factor.lisp`. They discover Boolean guards, deduplicate equivalent/complement splits, try separate branches and supplied shared decoders independently, and use `start-synthesis` or `propagation-search` for child work.

`price-view-combinations` considers assembled child combinations, ranks by description bits, and uses runtime work to break ties. View APIs have no `run-weight` option. `discover-partition-views` also includes a verified lookup baseline when `schema-lookup-p` permits it and explicit compatible witnesses are available; the supplied-view helper returns branch proposals without adding that baseline.

| API | Return values |
| :--- | :--- |
| `evaluate-guard-partition` | True frame, false frame, labels, partition, linked frame on a nontrivial successful split |
| `synthesize-supplied-partition-view` | Proposals, conflict, status |
| `discover-partition-views` | Best proposal, proposals, conflicts, status |
| `condense-heuristic` | Best completed heuristic model, status |

`compute-tree-locality-positions` evaluates a supplied key on tree indexes and constructs quotient/partition coordinates. With no key, it uses physical tree indexes. Equal keys form coarse classes; equal-length lists of integers use Manhattan distance; distinct scalar keys use the coarse-class fallback, not numeric scalar distance. Scheduling also uses rank distance, path-depth difference, and depth sum.

`:locality` interleaves three locality choices with one canonical occurrence-pair choice. `:locality-only` deliberately omits that reserve for controls. These count pair selections, not equal work quanta. The helper accepts DSL expressions and host functions; DSL keys are VM-metered, while the host-function path charges a fixed callback unit and does not meter the callback body or serialize it.

M7 demonstrates Boolean views and supplied locality scheduling. Learned residual geometry, graded pair/anchor constraints, loss transport through decoders, and automatic locality-key synthesis are not implemented.

## 5. Module and infrastructure map

The order below is the order in `load.lisp`; `package.lisp` loads first.

| Module | Responsibility |
| :--- | :--- |
| `ast.lisp` | Types, pooled symbols, AST construction/validation, metadata, bit/work helpers |
| `codec.lisp` | Model encoding/decoding, header and description sizing, encoded expression ordering |
| `vm.lisp` | Ledger, work limits, resumable execution, validated programs, primitive semantics |
| `requirements.lisp` | Conservative simplification and conjunction analysis |
| `frame.lisp` | Rows/frames, requirement constructors, conflict checks, reorientation, pullback, composition, quotient/partition linkage |
| `enumerate.lisp` | Grammar enumeration, exact and observation search, messages, propagation-search adapter |
| `factor.lisp` | AU, fiber proposals, law/tree corpus models, heuristic wrapper, locality and view orchestration |
| `laws.lisp` | Law/guard discovery, validation, rewrite libraries, solver discovery and propagation |
| `synthesize.lisp` | Resumable heuristic search, recursive decomposition, selector/dependency search |

Rewrite preparation caches belong to each `rewrite-library`; there is no global prepared-rewrite cache. `*last-code-match*` is a separate single-entry host memo used by symbolic match/bind/substitution primitives. Neither mechanism shares arbitrary child synthesis problems.

Fixtures now live in `tests/support.lisp` and the relevant suites. The former standalone experiment runners have been removed. `tests/run.lisp` loads fourteen suites and accepts module names or `m1`–`m7` aliases; `tests/visualizer.lisp` is separate. `benchmark.lisp` measures bounded GF(5) search scaling and VM dispatch. The visualizer exports observation data to static reports.

## 6. Status, evidence, and objectives

Exact search and the recursive controller rank accepted candidates by $S+\lambda_{\mathrm{run}}W_{\mathrm{run}}$; heuristic search adds the residual proxy above. View selection uses bits then runtime. The research procedure objective $J(M_P)+\lambda_{\mathrm{search}}W_{\mathrm{search}}(P)$ is an experimental comparison criterion, not an implemented learned scheduler objective.

`message` has only `call-id`, `claim`, and `evidence`. Evidence shape depends on the producer. Recursive messages include parent/proposal identities, scope, bounds, and work; there is no universal status/best/cursor envelope. Law validation uses its own status and certificate structs.

| Status or claim | Interpretation |
| :--- | :--- |
| `:replayed-observations` | Observation-scope evidence; not universal validity |
| `:conjecture` | A completed sampled law check with active support |
| `:vacuous` | Completed law check with no active support |
| `:refuted` | A witnessed law failure, including relevant evaluation errors |
| `:validated` | Completed exhaustive finite law validation with active support |
| `:cutoff` | Budget ended; resumable APIs preserve state, synchronous helpers need a new invocation |
| `:bounded-exhaustion` | Exhaustion within the reported grammar/proposal bounds |
| `:partition-proposal` | Bounded fiber proposal; feasibility remains unresolved |

A law certificate stores `snapshot`, `evidence`, `assignments`, `active`, and `work`. Consumers recheck snapshots and versions; it is not a theorem certificate for infinite domains.

| Milestone | Implemented evidence | Remaining boundary |
| :--- | :--- | :--- |
| M1–M4 | Typed search, observations, guarded laws, syntax compression, checked rewrites, arithmetic propagation | Finite grammars and validation scopes; supplied controls remain explicit |
| M5 | Supplied lifting, bounded fiber proposals, selector/dependency search | No general latent-model identification guarantee |
| M6 | Typed AU, occurrence proposals, reconstructing corpus models | Bounded/greedy correspondence search |
| M7 | Boolean views, reassembly controls, supplied locality schedules | General learned ordering and residual geometry |
| M8A/B | Nested supplied decompositions, resumable work accounting, root reconstruction | Autonomous decoder generation and cross-branch DAG sharing |
| M8C | Local checked conflicts and tentative fallback preservation | Reusable learned nogoods and generalized explanations |
| M8D | Resumable residual-priced condensation | Trace acquisition, learned node ordering, end-to-end policy evaluation |
| M9 | Prerequisite syntax/condensation machinery | Callable learned library entries and descriptor-guided retrieval |

## 7. Verification commands

From this directory:

```bash
make test
sbcl --script tests/run.lisp m7 refactor
sbcl --script tests/run.lisp algebra propagation
sbcl --script benchmark.lisp meter
```

`make test` runs all core suites and the visualizer exporter checks. Milestone aliases select tests; they do not regenerate the historical reports. `make visualizer` writes generated visualizer assets. `make benchmark` writes benchmark logs. The default `make` target builds document PDFs, not tests.
