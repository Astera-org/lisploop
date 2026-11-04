# Tests

Run `make test` from the project directory. This runs `tests/run.lisp` and the
separate visualizer exporter checks in `tests/visualizer.lisp`. Both scripts load
relative to themselves, so absolute paths also work from another directory.
SBCL is the only dependency for these tests.

`run.lisp` loads the kernel (`../load.lisp`) and shared test support/fixtures
(`support.lisp`) before registering and running the suites. Pass optional module
names or milestone aliases (`m1`..`m7`) to run a subset, e.g.
`sbcl --script tests/run.lisp lifting views` or `sbcl --script tests/run.lisp m4`.
Loading `load.lisp` alone never loads or runs tests. The suites use the kernel
package to inspect internal continuations and ledgers without expanding the
public API just for testing.

| Module | Coverage |
|---|---|
| `support.lisp` | Test harness, shared fixtures, reference evaluators, and cross-suite law/algebra helpers |
| `core.lisp` | Frames, VM, reconstruction, AU, bounded synthesis and continuations |
| `observations.lisp` | Observed equality, invariants, scopes and replay |
| `codec.lisp` | Canonical encoding, independent enumeration and structural work |
| `laws.lisp` | Arithmetic, validation, guarded rewrites and checked search |
| `guards.lisp` | Exact agreement subsets and core Boolean guard search |
| `compression.lisp` | Complete law-corpus reconstruction and objective selection |
| `symbolic.lisp` | Quoted expressions, DSL transformers, AU lowering and symbolic synthesis |
| `amortization.lisp` | Reusable validation, preparation accounting, cache isolation and cold/warm continuations |
| `algebra.lisp` | Both operands of all four arithmetic operators, learned guards, finite certificates, integer counterexamples, exact propagation and AU |
| `propagation.lisp` | DSL rule matching, library isolation, forward-verified integer targets, retained alternatives, fair branch scheduling, resumption, and expensive-context reuse |
| `lifting.lisp` | Hard-EM fiber clustering, cannot-links, heuristic condensation, supplied and unsupervised lifting, and tentative integer propagation |
| `abstraction.lisp` | Aligned anti-unification, subtree occurrence indexing, tree corpus packets, subgraph correspondence search, and law-normalized syntax |
| `views.lisp` | Guarded partition views, 3-way model comparison, physical shuffle invariance, locality-prioritized AU scheduling, and 2D tuple projections |
| `refactor.lisp` | Partial-expression semantics, immutable problem snapshots, recursive reconstruction, dependency/selector synthesis, global budgets, resumption, and informative messages |
| `visualizer.lisp` | Read-only export, quoted/exact values and JSON boundaries |

After `make visualizer`, `node visualizer/check-data.cjs` checks the generated
data and HTML. The optional desktop browser check is documented in
[`visualizer/README.md`](../visualizer/README.md).
