# `lisploop` — Execution: Exact Closures in Place of the Interpreter

> **Status:** implemented, 17 November 2026, on branch `metered-closures` (from `019736f`). In the working tree, not committed.
> This is phase `L4` of `plan-let.md` §8, taken by itself: the `let` binder was not adopted and the quoted form stays.
> Figures are under SBCL 2.6.4, three runs each, median. The Lisp source remains authoritative.

---

## 1. Result

Every evaluation of an expression built from primitives is now run by a host closure. It reports the status, value, error text and work that the interpreter reports, at every budget cutoff. No ledger in the test suite changes by a unit.

| Workload | `019736f` | Now | Factor |
| :--- | :--- | :--- | :--- |
| `benchmark.lisp search quartic 77`, batch | 1.83 s | 0.45 s | 4.0 |
| `benchmark.lisp search quadratic 70`, batch | 0.168 s | 0.044 s | 3.8 |
| `quartic 77`, unit dispatch | 3.27 s | 1.74 s | 1.9 |
| Milestone suite (40 tests) | 22.7 s | 12.1 s | 1.9 |
| Kernel suite (the 182 tests of `019736f`) | 3.39 s | 2.40 s | 1.4 |
| One `evaluate` of Probe 5's step function | 15.7 µs | 2.1 µs | 7.5 |

`work` and the ledger are identical on every benchmark line. On `quartic 77` allocation falls from 486 to 184 MiB and the live heap rises from 18.3 to 20.4 MiB (the closure cache). The kernel is `15,257` lines, `+100`.

The gate set in `plan-let.md` was identical ledgers, the resumption contract on the whole suite, and a factor of 3 on the benchmark. It is met for batch dispatch. Unit dispatch gains less because there the cost is one job step per work unit, which is not evaluation.

## 2. What Was Built

1. **Exact closures (`vm.lisp`).** `expression-closure` compiles an expression into a closure that also counts, in `*closure-work*`, what the VM would charge. `start-evaluation` runs it at once and returns an evaluation with a single instruction, `:settle`, which costs that count and yields the closure's outcome when paid (`settled-evaluation`). Paying, cutting off and resuming are done by the code that already did them, so no caller changed: exact search, observation search, Stage A checks, law validation, folding and `evaluate` all take the fast path. A `:code-eval` of literal code, which is how `compose-model` shares a value, is compiled as a call of the closure of its body.
2. **Metadata of pooled symbols (`ast.lisp`).** An operator, variable or hole symbol now carries its `ast-meta` on its property list (`node-meta`). It was in the weak table `*node-meta*`, whose lookups take a system lock and were 45% of the benchmark's samples. Conses stay in the table. This speeds the interpreter as well: with closures switched off, items 2 and 3 alone bring the quartic benchmark from 1.83 s to 1.18 s.
3. **One type walk fewer per candidate (`enumerate.lisp`).** `index-expression` type-checked and sized every enumerated candidate by two full walks, though the enumerator builds it from buckets of the right types and sizes. It now reads both off the cached metadata. A candidate that is evaluated is still type-checked, once, when its closure is compiled.

`*closure-evaluation*`, when nil, restores the interpreter everywhere, which is what the tests compare against.

## 3. Why It Is Exact

- A primitive is priced and run by the VM's own `primitive-cost` and `execute-primitive`, and the input values by `validation-work`, which the `:validate` instruction now also calls. There is no second tariff.
- A closure adds its charges in the VM's order and charges an instruction before running it. So when a primitive fails, the count already includes it, as in the VM, and `:settle` fails at the same work with the same message.
- An expression is type-checked as it is compiled, by the rules of `expression-type`, and input values are checked by `value-p` on every evaluation. Whatever does not pass, or is not closure-able, goes to the interpreter: a call of a defined function, a symbolic `:code-*` operator, code that is not a literal, a hole. In the kernel suite that is 3,798 evaluations of 244,865.
- One assumption: pricing cannot fail on well-typed values. If it could, the VM would report an unpaid error and charge one diagnostic unit, which a closure does not reproduce.

Checked by: `tests/closures.lisp` (510,000 checks: every tree of up to two applications over integer and field arithmetic and conditionals, sequences, tuples, tables and literal code, on rows giving values, errors and unresolved inputs, run to the end, cut off at six budgets and paid one unit at a time; search and observation jobs compared with closures on and off, with a row budget and with counterexample messages); three deliberate tariff and status errors, each of which the tests catch; and `experiments/ledger-fingerprint.lisp`, which records what every ledger received per test and category over the 222 tests of `019736f`: 415,539,255 units, byte-identical before and after.

## 4. Departures from the `L4` Row

- **Row jobs were not touched.** The row said to run closures in `row-job-step` and pay their work as staged debt. Doing it inside `start-evaluation`, as an instruction, covers every caller and needs no new paying code.
- **Callers that charge a fixed cost keep their old domain.** `compile-ast-fn` (knowledge entries, the two priority predictors) still declines literal code, so those callers charge what they charged. Their closures now carry the count they do not use and are slower per call (1.4 µs against 0.25 µs on Probe 5's step). They are 1,376 calls and under 0.1% of the suites' time.
- **Host `compile` for hot entries was not built.** Nothing measured needs it.
- **Two changes are outside the VM** (items 2 and 3 above). Both were the largest remaining costs once evaluation was fast.

## 5. What Is Left

Evaluation is no longer the bottleneck: in the kernel suite 9% of samples are under `advance-evaluation`. What the profiles show next:

| Where | Share | Note |
| :--- | :--- | :--- |
| `ensure-ast-meta` on conses (the weak table) | 19% of the kernel suite | Applications and literals still pay the locked lookup. |
| `invalidate-app-meta` | 8% of the kernel suite | Walks the whole table at every function definition. |
| `equal` and `find` in `guard-problem-for` | about 30% of the milestone suite | A test fixture (`tests/milestones/guards.lisp`), not the kernel. |
| Calls of defined functions | within the 9% above | A closure could make them with a work cap and a lookup at call time; recursion needs the cap. |
| One job step per unit | all of unit dispatch | Inherent to stepping one unit at a time. |

## 6. Reproduction

```bash
make test                                                   # 185 + 40 tests
sbcl --script benchmark.lisp search quartic 77 300 batch    # work=29382492 before and after
sbcl --dynamic-space-size 4096 --script experiments/ledger-fingerprint.lisp /tmp/here.txt
git worktree add /tmp/base 019736f
sbcl --dynamic-space-size 4096 --script experiments/ledger-fingerprint.lisp /tmp/base.txt /tmp/base/
cmp /tmp/base.txt /tmp/here.txt                             # no output: identical ledgers
```

| File | Change |
| :--- | :--- |
| `vm.lisp` (+164, -81) | `*closure-evaluation*`, `start-evaluation`, `validation-work`, the `:settle` instruction, `expression-closure` in place of the old body of `compile-ast-fn`, `settled-evaluation` |
| `ast.lisp` (+22, -11) | `node-meta` and its call sites |
| `enumerate.lisp` (+8, -2) | `index-expression` |
| `knowledge.lisp` (+1, -1) | One `node-meta` call site |
| `tests/closures.lisp`, `tests/run.lisp`, `tests/README.md` | Three tests and their registration |
| `experiments/ledger-fingerprint.lisp` | The ledger comparison |
