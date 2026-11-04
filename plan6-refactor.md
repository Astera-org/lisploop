# Plan 6 refactor log

This document records the implementation following the November 2026 audit.
`plan6.md` remains the research plan; this log supersedes implementation claims
where the audit identified discrepancies. E-graphs, general object-language
recursion, and learned replacements for arbitrary host traversals remain later work.

## Accepted scope

1. Preserve false, error, and unresolved evaluation as distinct outcomes. Remove
   built-in two-dimensional table inversion and reduce the VM's responsibilities.
2. Make dependency selection an explicit synthesis proposal, not an implicit
   strengthening of a frame's requirements.
3. Offer direct selector synthesis alongside fiber-based proposals, charging both
   search work and the completed reconstruction's description/runtime cost.
4. Introduce a small resumable decomposition controller. Allow intermediate
   expansion; verify and score completed parent models against the original frame.
5. Enforce shared cumulative budgets across child work and preparation/checking.
6. Consolidate duplicated corpus construction and related orchestration where it
   reduces complexity without changing the DSL or introducing e-graphs.
7. Preserve informative child-to-parent messages: evidence, scope, counterexamples,
   bounded coverage, cutoff state, and candidate costs. A cutoff is not a conflict.

## Implementation and validation

### Conservative simplification and VM boundary

- Moved requirement simplification out of `vm.lisp` into `requirements.lisp`.
  The VM now handles execution, preparation, and tariff accounting.
- Replaced the large folder with a conservative implementation. Closed subtree
  errors and cutoffs retain the original expression. Boolean/set deductions that
  reorder or erase evaluations require structural totality.
- Finite-set filtering checks the whole conjunction, including sibling constraints.
  It no longer drops unrelated tuple-coordinate conditions.
- Removed both 2D and 1D literal-table inversion from the folder. The 1D rule also
  changed errors into false and was unsafe under negation. Raw pullbacks still
  express the exact forward requirement, so ordinary search can learn inverse
  witnesses without either rule.
- Preserved useful total tuple projection, equality propagation, coordinate
  reconstruction, and finite-set intersection. These remain explicit trusted
  structural deductions; this refactor does not claim they were learned.
- `fold-constants :budget` now covers one traversal plus its VM evaluations rather
  than renewing the budget at every recursive call.

### Dependency and selector synthesis

- `tighten-same-input-requirements` intersects only complete input tuples, including
  empty tuples for zero-input functions. Conflicting tuples remain contradictory.
- `dependency-proposals` explicitly represents empty-context and coordinate-context
  hypotheses. Supplied feature expressions are also supported.
- `start-dependency-search` / `resume-dependency-search` enumerate feature programs,
  group their observed input signatures, and search for selectors under each induced
  context. The feature's syntax and execution are included when reconstructing the
  parent model. The full-input direct search remains available.
- `start-selector-search` compares direct synthesis with optional fiber proposals
  and dependency proposals. It uses the original predicates for final verification.
- `infer-fibers` is an optional bounded partition proposal. Its fifth return value
  reports branch completion/cutoff and explicitly unresolved feasibility. The
  objective is identified as a lexicographic proxy, not global MDL or entropy.
  A singleton-group fallback exists even when the branch cap prevents a full DFS.
- Fiber work limits now bound the entire call. `fiber-pairs-and-anchors` propagates
  cutoff without dereferencing a missing refined frame.

### Recursive orchestration and informative returns

`synthesize.lisp` introduces `decomposition`, `start-synthesis`, and
`resume-synthesis`. A decomposition specifies a decoder, child variable/type,
context bindings, child language/bound, and optional nested decompositions.

- Root enumeration is reserved every fourth work quantum. Other quanta service
  child searches and verification, with round-robin progress among children.
- Every child candidate is reconstructed through the entire ancestor chain and
  checked against the original root frame. The root scores complete models by
  `S + run-weight * W_run`; discovery work is reported separately, not silently
  added to the object-level objective.
- All child candidates are retained for parent scoring. A locally shorter child
  that duplicates an expensive binding cannot hide a better completed model.
- There is no immediate-compression requirement on a decomposition. Completed
  proposals may exceed the root enumeration bound; that bound describes the
  direct grammar lane, while child bounds describe their respective searches.
- Parent/child continuations survive budget cutoffs. Scope-tagged messages carry
  child and parent IDs, proposal identity, bounds, work, candidates, checked
  conflicts, and bounded-exhaustion information. Root rejection can include row,
  input values, expression, phase, value/error status, and diagnostics.
- `start-search :diagnostics t` enables counterexample messages without retaining
  every rejection during ordinary large enumeration runs.
- These messages are evidence-bearing data for later sub-synthesis. Learned
  explanations, synthesized return messages, and learned scheduling policies are
  not implemented or implied by the envelope.

### Budget ownership and state isolation

- `start-search` snapshots frames and languages, matching observation isolation.
  `snapshot-frame` owns schema, row data, requirements, and linkage. Guard proposal
  validation now compares snapshot contents rather than pointer identity.
- `start-heuristic-search` / `resume-heuristic-search` interleave observation with
  requirement checking, correction extraction, and scoring under one cumulative
  ledger. `condense-heuristic` is a convenience wrapper returning best model and
  status. It evaluates the original requirements, without hidden projection or
  same-input strengthening of the lossy training objective.
- Residual pricing now includes the correction-count prefix. Residuals remain a
  training criterion and are dropped from the deployed heuristic program.
- The synchronous view APIs share a single additional-work budget across guard
  discovery, child searches, propagation, construction, and final verification.
  They return status as the third value (supplied view) or fourth value (discovery).
  Their cutoff is not a claim that the view is impossible.
- `with-work-limit` prevents nested synchronous helpers from renewing an enclosing
  budget. Resumable APIs use absolute cumulative limits; convenience wrappers use
  additional work per call. Existing ledger history is not erased.
- Tariff version increases from **8 to 9** because orchestration/simplification
  accounting changed. Encoding remains 7 and simulator semantics remain 5.
  Historical work totals must retain their original version.

**Preemption boundary:** the recursive controller stages atomic host preparation
(pullback, folding, optional bounded partitioning) privately, records its tariff,
then drains preparation debt before publishing the child search or conflict.
Suspension preserves that prepared result and does not redo it. This bounds
published tariff work, but does not preempt host Lisp traversals or guarantee a
wall-clock deadline. Low-level VM and search evaluation remain resumable.
The synchronous view/fiber convenience APIs report cutoff and do not expose a
resumable traversal cursor; use the recursive controller for preserved child state.

### Consolidation

- AU packet fragments share `au-body-pieces`; law/tree corpus prefixes and row
  assembly share generic functions. Existing packet encoding is unchanged.
- View reconstruction uses one `price-view-combinations` path for separate-parts
  and shared-decoder models, scoring all discovered child combinations at the parent.
- Ordinary view children use the new synthesis controller. Tentative arithmetic
  propagation keeps its existing verified two-lane adapter. Conflict pruning checks
  a tentative branch's original fallback, so a restricted witness cannot refute it.
- Separate-parts failure no longer prevents trying a shared decoder that can retain
  additional context outside the projected child inputs.
- Updated loader, public API exports, benchmark source fingerprints, and test loader.
  Visualizer export checks use the current tariff; archived v8 bundles remain readable.

### Validation

`tests/refactor.lisp` adds semantic and integration coverage for:

- Exhaustive small Boolean contexts containing partial division and indexing,
  including negation and nested conjunctions; independent tuple-coordinate predicates.
- Caller mutation after search creation; complete-input and zero-input determinism.
- One-unit versus uninterrupted heuristic/controller execution and identical ledgers
  and selected models; global convenience-wrapper budget cutoffs.
- A nested decoder reconstruction with a failed dependency branch and informative
  parent/child messages, without requiring immediate description-length reduction.
- Parent-level ranking when the shortest child duplicates an expensive binding.
- Grammar-synthesized dependency features, direct selectors competing with fiber
  proposals, and explicit partition uncertainty/cutoff reporting.
- An inverse-grid witness synthesized through ordinary tuple enumeration, serialized,
  decoded, and verified through the original decoder. This is a reusable scoped
  witness program, not a claim of learning a general table-inversion algorithm.

Existing table tests now check forward relational semantics and errors instead of
requiring built-in inversions. Two lifting tests now make their intended coordinate
projection explicit. Contradictory identical-input requirements correctly remain
contradictory instead of being silently kept in separate feasible-looking classes.

Verification completed:

- `make test`: **119 tests, 195,446 checks passed**, plus the separate visualizer
  exporter tests.
- `sbcl --script experiments.lisp m1` through `m5`: all completed successfully.
  M6 and M7 experiment runners also pass inside the full test suite.
- `git diff --check`: clean.
- The original audit probes now preserve the error under negation, retain the
  unrelated tuple conjunct, retain the full-input selector solution, and isolate
  running searches from caller mutation. A one-unit heuristic call charges one unit.

Useful entry points (after loading `load.lisp`):

```lisp
;; FRAME, LANGUAGE, and BOUND describe the original selector problem.
(let ((job (start-selector-search frame language bound :fibers t :dependencies t)))
  (resume-synthesis job 10000)
  ;; A later cumulative allowance continues the same child and verification states.
  (resume-synthesis job 100000)
  (values (synthesis-job-best job)
          (reverse (synthesis-job-messages job))
          (synthesis-job-ledger job)))
```

For grammar-synthesized context expressions, use `start-dependency-search` and
`resume-dependency-search`; the returned `dependency-search-synthesis` is the same
controller. For a concrete nested decoder setup, see `recursive-control` in
`tests/refactor.lisp`. Its direct language cannot express the target, the first
dependency branch conflicts, and the nested alternative reconstructs and verifies
the parent without expanding the object-language grammar.

## Remaining M8 work and deliberately deferred refactors

- Decoder proposals and their nesting are explicit inputs to the new controller.
  Automatic decoder discovery, cross-problem DAG memoization, and generalized
  conflict explanation learning remain research work.
- No e-graphs, general DSL recursion, callable learned-function registry, or
  arbitrary learned host traversals were added.
- The existing occurrence/locality search still uses its bounded greedy proposal
  strategy; lazy occurrence wrappers and incremental pair generation are deferred.
- Law and tree corpus containers remain separate adapters over shared encoding
  helpers. A wholesale corpus/observation representation rewrite is unnecessary here.
- Legacy view convenience APIs remain synchronous. Their children share the new
  controller, but a fully resumable guard/view agenda is still an extension point.
- The controller verifies proposed models and preserves canonical progress; it does
  not establish globally optimal decomposition search or a fourfold wall-clock bound.

## Corrections to older architecture descriptions

- Integer encoding is delta coding, and model packets contain ordinary expressions;
  there are no separate lookup/partition/AU model packet kinds.
- Cached metadata access is cheap, but `body-size` and `description-size` still
  invoke recursive validation. They must not be described as constant-time APIs.
- Rewrite preparation caches are library-local, not a global
  `*prepared-rewrite-cache*`. This refactor does not add cross-problem DAG reuse.
- `message` retains its existing `call-id`, `claim`, `evidence` envelope. Rich
  recursive evidence is added within that envelope rather than inventing a parallel
  success/failure interface or implying that validation drivers already all use it.
- Observation reorientation still preserves per-occurrence requirements. It does
  not silently union incompatible inverse observations into an existential fiber.
  That semantic choice remains explicit future work.
- `plan6.md` and `architecture.md` now link here; the older long-form descriptions
  have not been comprehensively regenerated. Historical experiment records remain
  unchanged and must be read with their original tariff versions.

## Mathematical boundaries

- Expression rewrites must preserve values and definedness in all supported
  contexts. Equality of top-level accepted sets alone does not justify rewriting
  below negation or a conditional.
- Intersecting requirements for identical complete inputs follows from functional
  determinism. Projecting away inputs is a hypothesis and must retain alternatives.
- Failure to detect a contradiction is unknown satisfiability, not a witness.
- Fiber partitioning is bounded combinatorial proposal search, not Hard EM or a
  proof of globally minimal description length. Concentration is not Shannon entropy.
- Recursion here means decomposition of synthesis problems. General recursive
  object programs and synthesis of arbitrary host traversals are not added.
- Learned table inversion belongs in the library/proposal layer. Removing a built-in
  inversion does not claim that an unbounded table-inversion algorithm was learned.
