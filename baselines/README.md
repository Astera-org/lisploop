# The baselines that the gates are tied to

The plan's working rule is "one increment, one gate: each gate is tied to a recorded baseline before the work starts". These three folders are those baselines. They were recorded on 26 November 2026 by three AI agents working independently, each from the present kernel's own code, before the new kernel was written. Each agent ran the kernel only in a scratch copy and changed nothing in the repository.

| Folder | Gate | What was recorded | Start with |
|:--|:--|:--|:--|
| `x1/` | X1, classes and laws | The 187 equations that the present kernel's bucket engine proposes on GF(3), its classes, the same runs at neighbouring bounds, the run that finds distributivity, and the work and memory of each. | `x1/REPORT.md`, then `x1-equations-by-job.txt` and `x1-classes.txt` |
| `x2/` | X2, solvers and guards | The eight arithmetic solvers of the milestone code on GF(5), GF(7) and the integers: 24 records, each with its answer term, its guard, and the guard's truth table over the grid. | `x2/REPORT.md`, then `x2-solvers.sexp` |
| `x3/` | X3, the 16-spec ladder | The sixteen specs with their rows, the 200 held-out rows of each and the one hand-written held-out case, and the present kernel's results in the gate's regime at four budgets. | `x3/REPORT.md`, then `x3-specs.lisp` and `x3-heldout.lisp` |

Each report tags its claims as measured, read from code, or read from a document, and ends with what did not reproduce and what could not be determined. Three of their findings changed how the gates had to be read:

- **X1.** The count of 187 is where a work limit fell in two of the four jobs, not the content of a size bound. And "10 times less work" has no stated unit: the present kernel charges 22 to 33 ledger units for one operator applied on one row.
- **X2.** The milestone code's guard is the replay guard alone, and uniqueness is a separate law. The plan's statement that the present kernel cannot solve `a*x + b = c` does not reproduce: a function that only the tests call does solve it.
- **X3.** The gate does not say how a report of underdetermination is to be checked. The two held-out procedures each miss something the other catches, so the new kernel is scored on both.

The scripts in these folders reproduce the baseline data files from `../v1/`, `../plan_v2c_audit/verify-review/`, and the pre-rewrite `v2/` tree at commit `65d1df2`. Generated data files, logs, and scratch copies are gitignored and managed via `Makefile`:

```
make            # regenerate the baseline data read by v2/gates/ (~45 s) and verify SHA256SUMS
make full       # also run the full diagnostic/memory/harness suites and write logs
make clean      # remove all generated data files, logs, outputs, and scratch copies
```

From `v2/`, `make baselines`, `make gates` (which builds missing baselines automatically), and `make clean` delegate here.
