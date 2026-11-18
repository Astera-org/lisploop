# Tests

Run `make test` from the project directory. This runs:
1. `make test-kernel` (`sbcl --script tests/run.lisp kernel`) in a fresh SBCL process with **only** `load.lisp` loaded (zero `milestones/` code), and
2. `make test-milestones` (`sbcl --script tests/run.lisp milestones`) in a fresh SBCL process with `milestones/load.lisp` layered on top of the kernel.

All scripts load relative to themselves, so absolute paths also work from another working directory. SBCL is the only dependency for these tests.

## Running Subsets

`tests/run.lisp` accepts group selectors (`all`, `kernel`, `milestones`), milestone aliases (`m1`..`m9`, `r1`..`r6`, `l1`..`l4`, `h1`..`h4`), or individual module names:

```bash
sbcl --script tests/run.lisp kernel
sbcl --script tests/run.lisp milestones
sbcl --script tests/run.lisp invariants recursion
sbcl --script tests/run.lisp m9
```

When a command selects both kernel and milestone modules (including the default `all` run), `run.lisp` asserts pure-kernel isolation and executes all selected kernel modules *before* loading `milestones/load.lisp` and `tests/milestones/support.lisp`. Loading `load.lisp` alone never loads milestone code or tests.

## Architecture & Shared Contract Oracles

Test assertions target **semantic contracts** rather than incidental internal struct layouts:
- **Anytime Resumption Parity (`check-anytime-resumption` and domain wrappers in `support.lisp`)**: Verifies step-budget obedience (`delta-work <= limit`), monotonic progress, and identical terminal claims, verified outputs, optimal MDL candidate sizes, and total ledger work between unit-step and batch runs without locking in transient queue/hash-table internals via `equalp`.
- **Synthesized Model & Task Oracles (`check-synthesized-model`, `check-synthesis-task`)**: Validates codec round-trip (`decode-model`/`encode-model`), frame verification (`verify`), optional held-out generalization, structural call contracts, and resumption parity.
- **Library Abstraction & M9 Policy Alignment (`check-library-abstractions-contract`)**: Validates net corpus MDL bit compression, compositional call sites, and public M9 descriptor/addressing invariants (`score-entry-by-descriptors`, `find-knowledge-entries-by-address`) without locking in brittle internal names or magic score constants.

## Kernel Suites (`tests/*.lisp` — pure `load.lisp`)

| Module | Coverage |
|---|---|
| `support.lisp` | Pure-kernel test harness, state isolation (`with-clean-kernel-state`), semantic resumption/synthesis/library contract helpers, multi-arity reference tree generator, and pure-kernel fixtures. The combinator, arithmetic-solver and shift-metric fixtures load the batteries in `library/` (`load-battery`) and hold no definitions of their own |
| `core.lisp` | Types, frames, total metered VM (including exact VM step-determinism), codec round-trips, anti-unification, and bounded search |
| `codec.lisp` | Canonical prefix-free encoding, multi-arity/0-ary completeness against independent reference trees, and structural work |
| `observations.lisp` | Observed equality, invariants, scopes, anchor/pair stability, and replay |
| `laws.lisp` | Certified finite-field and counterexample-checked integer laws, guarded rewrites, orientation, and checked search |
| `symbolic.lisp` | Quoted expressions (`:code`), DSL transformers, AU lowering, and symbolic synthesis |
| `amortization.lisp` | Reusable validation, preparation accounting, cache isolation, and cold/warm continuations |
| `lifting.lisp` | Hard-EM fiber clustering, cannot-links, heuristic condensation, supplied and unsupervised lifting, and tentative integer propagation |
| `abstraction.lisp` | Aligned anti-unification, subtree occurrence indexing, law-normalized syntax, higher-order body abstraction, and library compression |
| `refactor.lisp` | Partial-expression semantics, immutable snapshots, recursive reconstruction, selector/dependency decomposition, global budgets, and resumption |
| `recursion.lisp` | Sequences, structural totality, recursive `define-function`, inductive lifts, nogoods/DIP repair, active-set CEGAR, corpus abstraction, and de-novo combinator synthesis (`R1`–`R6`) |
| `library.lisp` | Unified `knowledge-library`, relational edges, epistemic evidence/attestation, behavioural descriptors, S-expression persistence, and consolidation (`L1`–`L4` / `M9`) |
| `higher-order.lisp` | `:code` parameters, `:code-eval` / `:code-subst`, library combinators (`:map`, `:foldr`, `:filter`), learned decoder templates, and polymorphic functor lifting (`H1`–`H4`) |
| `audit.lisp` | Focused regression and soundness probes (totality bypass rejection, occurs-check, nogood soundness, CEGAR unit-budget accounting, cache isolation), and the defects found by the audit of Plan 9: totality as a least fixed point and of calls to undefined names, the persisted nogood-schema zip on decoders that are not pointwise maps, `:relation` consolidation of member tables and of tables with a default, failed fits searched once, and one consolidation call reaching a fixed point |
| `invariants.lisp` | Cross-module property & metamorphic contracts: `fold-constants` (`:equivalent` / `:necessary`), `pullback-frame` / `lift-frame` Galois soundness, row-order & input-schema alpha-renaming invariance, and warm-library distractor resilience + consolidation idempotence |
| `structural.lisp` | Plan 8 `P8.1`: definedness-safe `:code-eval` let-sharing in `compose-model`, Galois soundness of `product-slot-frame` / `compose-product-model`, tuple and Constructor-AU products joined slot by slot (`au-substitutions-frame` agreement, conditional tuple scan, symbolic rewrite), alpha-invariant component bindings, Stage A feature-pair exception guards, operator and expression holes in Constructor-AU, the bounded and filtered join of coupled slots, repeated-subterm sharing, and stored template generalisation |
| `metrics.lisp` | Plan 8 `P8.2`: arity-scaled Stage A budget for lifted frames, `*max-eager-proposals-per-node*`, AU code-edit corrections, co-induced `(decoder, :solver)` metric decoders (`:shift-seq` / `:argmax-corr`) in Stage A pricing and Stage B pullback with replay-checked fallback, problem-supplied frame metrics and where a pullback keeps them, the fallback of an ambiguous narrowing, and once-per-frame descriptor evaluation with address lookup |
| `topology.lisp` | Plan 8 `P8.3`: symbolic equation unwinding with target sensitivity (`solve-equality-symbolically`, `orient-conserved-quantity`), row-keyed hard `frame-edges` enforced by exact search and root verification, strict schema availability preorders over real and symbolic ranks (`orient-available`), evidence grades for solver uniqueness (`knowledge-evidence-tested-p`), and storage-invariant induced row order with enumerated accessor keys and `:locality-key` registration |
| `theories.lisp` | Plan 8 `P8.4`: Monoid fold motifs formed from law stars and transferred to later instances (`induce-fold-motifs`), the decoder templates their transfer laws license, and net-utility archiving of library entries that do not amortize (`amortize-library-entries`, `:active-p nil`) together with the templates that call them, each with negative controls and persistence fixed points |
| `closures.lisp` | Closure evaluation (`start-evaluation`, `expression-closure`, `settled-evaluation`): the same status, value, error text and work as the interpreted VM on values, errors and unresolved inputs, at every budget cutoff and one unit at a time; literal `:code-eval`; what closures decline; and exact search and observation jobs that are identical with `*closure-evaluation*` on and off |
| `batteries.lisp` | The battery loader (`batteries.lisp`) and the sources in `library/`: every battery loads into an empty library and replays its examples, type parameters instantiate and name their instances, solvers over finite types are certified by the load and integer uniqueness is recorded as an axiom, a wrong example or type refuses the load, a job consumes the active library's solvers without being given them, dispatch costs one lookup whatever the library's size, and a job's rules survive a function defined during the search |
| `trace.lisp` | The search trace as relations (`trace.lisp`): the events a Stage A search notes give, for any quantum, what the same search shows when resumed in quanta of that size; a job sends what its staged work noted only once that work is paid, identically however it is stepped; and a frame built from trace rows is an ordinary frame, whose conflict check says whether one column is a function of others and whose rules the VM evaluates |

## Milestone Suites (`tests/milestones/*.lisp` — `milestones/load.lisp`)

| Module | Coverage |
|---|---|
| `milestones/support.lisp` | Milestone-only test fixtures for corpus packets, guard discovery, algebraic solver discovery, and propagation controls |
| `milestones/guards.lisp` | Exact agreement subsets and core Boolean guard search (`M3`) |
| `milestones/compression.lisp` | Complete law-corpus reconstruction and MDL objective selection (`M3`) |
| `milestones/algebra.lisp` | Algebraic inverter discovery across all four arithmetic operators, learned guards, certificates, and exact propagation (`M4`) |
| `milestones/propagation.lisp` | Propagator-library isolation, forward-verified integer targets, branch scheduling, resumption, and expensive-context reuse (`M4`) |
| `milestones/corpus.lisp` | Standalone tree-corpus packet encoding and subgraph correspondence search (`milestones/corpus.lisp`, `M6`) |
| `milestones/views.lisp` | Guarded partition views, 3-way model comparison, shuffle invariance, locality-prioritized AU, 2D tuple projections, and standalone dependency search (`M7`–`M8`) |
