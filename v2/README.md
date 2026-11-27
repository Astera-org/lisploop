# The topology-geometry kernel: Stages A and B of `plan_v2c.md`

This directory holds a new kernel, written from the plan. It replaces the copy of the original kernel that used to be here; that copy, with the Stage 0 and Stage 1 changes of the earlier v2 plans, is in git history (`git show a4e19fa:v2/...`). The original kernel itself is in `../v1/`.

Nothing here loads code from `v1/`. What was carried over is named in the file that carries it.

## How to run it

```
make test       # the contracts: 28 tests, under a second
make baselines  # regenerate and verify the v1/Stage-0 baseline data in ../baselines/
make x1         # gate X1: classes and laws, against the recorded baseline
make x2         # gate X2: solvers and guards from operator tables
make x3         # gate X3: the 16-spec ladder; about four minutes
make gates      # all three gates
make clean      # remove gates/results/ and generated baseline files/logs in ../baselines/
```

Each gate builds its baseline data automatically if absent, prints what it measured, and writes the same text to `gates/results/` (gitignored). SBCL is the only dependency.

## What is here

The whole structure is the four nouns of the plan's §5.2: a **space** is a finite set of rows, a **column** has one cell for each row, a **term** is an operator applied to terms and is stored once, and a **class** is all the terms that denote one column on a space.

| File | Lines | What it holds | Plan |
|:--|--:|:--|:--|
| `ledger.lisp` | 56 | Exact accounting of work, carried over from `v1/vm.lisp:10-54`. The unit is one cell: one operator applied on one row. | §9 |
| `values.lisp` | 150 | Cells and types. A cell is a value or a status: a fault that records which operator failed on which arguments, out of fuel, or pending. Two faults are equal as cells, because no program can tell them apart. | §5.2, §7.1 |
| `ops.lisp` | 211 | The operators: `+ - * / mod < =`, the two that are not strict (`if`, `try`), the six that build sequences and take them apart (`length at tabulate fold scan where`), pairs, and `call`. Arithmetic works on the integers and on prime fields. | §7.1 |
| `terms.lisp` | 201 | Hash-consed terms, with variables, constants, applications, lambdas and holes; reading and printing them. | §5.2 |
| `eval.lisp` | 73 | The evaluator: one term in one environment, metered, with a fuel limit. It is the reference semantics, and every finished program is verified with it. | §7.1 |
| `store.lisp` | 357 | Spaces and the maps between them (unnest, sub-space, re-index, collect), the group-by and the dependency test, banks of classes, evaluation by column, and enumeration by size that can be stopped and resumed with the same result however its budget is cut. | §5, §7.1 |
| `codec.lisp` | 198 | A prefix code for terms, directed by types, with a decoder that rejects any code but the canonical one. The design is v1's; the prices are not. | §9 |
| `laws.lisp` | 190 | Laws from collisions, exhaustive certification on finite domains with counterexamples, and rewriting by kept laws. | §5.3, §8.3 |
| `reorient.lisp` | 224 | Inverses and their guards from a table: the dependency test, a search for the answer, the replay guard, and the uniqueness guard. It works on any term with one unknown, of which a single operator is the simplest case. | §5.3, §7.2 |
| `evidence.lisp` | 61 | The three grades, and certificates that lapse by themselves when a definition they depend on changes. The rule is v1's. | §5.5 |
| `synth.lisp` | 918 | The synthesizer: problems, the routes of the refinement table, the scheduler, and the rules of acceptance. | §7.2 |
| `task.lisp` | 233 | Tasks from rows, verification at the root, made-up probe rows, and the check for rival programs. | §5.5, §7.2 |

That is about 2,900 lines. The present kernel is 17,647.

## The three gates

The baselines were recorded from `v1/` and from the old `v2/` before any of this was written, as the plan's working rule asks. Their reports, checksums, and regeneration scripts live in `../baselines/` (built on demand via `make baselines`).

**X1, classes: passed, with one reading of "10 times less work" that is on the line.** All 187 baseline equations have both sides in one class of the store, and all 187 follow from the store's own collision equations. Distributivity is found, stated as a collision, and certified. The store keeps 274 classes where the present kernel keeps 3,477 trees. The baseline report showed that the gate's "10 times less work" depends on the unit. In the present kernel's ledger units the store does 247 times less at the bound where distributivity appears, and that is the change of unit, not classes. Counted like for like, operator applications on rows, it does 9.9 times less at that bound (four leaves) and 38.9 times less one size up. Pruning by laws already found, which the plan asked to have measured, finds the same classes with 3.2 to 4.7 times fewer cells, and takes longer: 0.24 s against 0.16 s at six leaves, because on 27 rows matching a candidate against the kept laws costs more than evaluating it.

**X2, reorientation: passed.** All 24 baseline solvers (`+ - * /` in each argument, on GF(5), GF(7) and the integers) come out with the same answer term, text for text, and a guard with the same truth table. That includes the unknown divisor and the integer divisibility guard, which the prototype did not produce. Nothing is supplied beyond the operator's table and the operators in scope: no rows off the table, no language of answers. All sixteen field solvers are certified sound, and exact once the uniqueness guard is added. Both composite cases of risk 2, `a*x + b = c` and `x + x = c`, are solved from their own tables.

**X3, the ladder: 12 of 16 programs are sound on all 201 held-out rows, and no program is returned that fits its rows and fails held-out.** The other four are reported as not determined by their rows, each for a stated reason: `foldl` because its function argument has one value in every row; `seq-corr` because two programs of the same size fit and differ on made-up rows; `best-shift` and `argmax-corr` because so many candidates had been compared that a fit would be expected by chance. Today's kernel is sound on 7 to 10. Whether this passes the gate's "14 of 16" depends on how a report of underdetermination is to be judged, which the gate does not say.

The whole ladder takes 20 seconds and 367 million cells, at a budget of 400 million cells for each spec. Ten of the twelve are found within a million cells each, in a tenth of a second for all sixteen; `map-adjacent` and `shift-seq` need between ten and a hundred million. No budget from a million to a billion cells returned an impostor.

The size-order rule was not exercised by the ladder, because no spec needs a conditional once `try` is in the grammar. Measured apart, on five small tasks whose answer is a conditional, ruling out every smaller term cost 12 to 2,569 times the work of finding the conditional, and the look-ahead in its types-only form cut that by 1.27 to 1.33 times.

## What is not built

- **Requirements are not yet terms.** A problem's requirement is an exact target column or a host function that checks a class. The plan's §5.6 wants a Boolean term with holes; the hole is a kind of term here, and the replay guard of a solver is a real term, but the requirements of the refinement routes are not.
- **Four rows of the refinement table**: `gather` with index sets, `scan` with a step that is searched (a `scan` over a function argument is found as a plain term), the self-call, and `decode`. The coarse row that needs verb tables belongs to Stage C.
- **Nested conditionals**, and conditionals inside a requirement that has no exact target.
- **Carried-over pieces that nothing here needs yet**: persistence, anti-unification, and abstraction. They belong with the library, in Stages C and D.
- **The contract on requirement simplification** has nothing to test, since there is no simplifier.

## Decisions that the plan did not make

Each of these came from a result, and each has a switch and a measurement in `gates/results/x3.txt`.

1. **`try` is in the grammar.** With it, `shift-seq` is `(try (at x0 (+ i k)) 0)` and no spec of the ladder needs a conditional. Without it the right conditional is found at 1.6 million cells, and at a billion cells it is still held under the size-order rule: terms without a conditional had been ruled out up to 11 of the 12 nodes required, with the look-ahead or without.
2. **The evidence rule.** A fit is accepted only if naming it, by its place in the order of search, is a shorter description of the target than the best description without it: the outputs written out, or a small class with its corrections. This is §6.3's rule 4 used as the test of acceptance. It is what stops the search on `argmax-corr`, whose three outputs carry ten bits. Without it two specs return impostors, `argmax-corr` (32 of 201) and `sum-all` (20 of 201), and the ladder takes 2.4 times the work.
3. **A requirement is reoriented when the rows support it.** If a few cheap columns determine the target and every group of rows that agree on them has at least two rows, the problem is solved on those columns alone. This is §5.4's reorientation applied to a requirement. Without it the length of `map-adjacent` comes out as a term that reads the product of the elements.
4. **Smallest first, across routes.** The first fit is held while routes that could still find a smaller term go on, until none is left or confirming has cost as much as finding. The rule is strict, with no cap, for a conditional and for a term found through an inverse, because both are found ahead of their size. On this ladder the capped form changed no verdict and cost 2.3 times the work. The strict form is what stops `map-adjacent` from returning a term found through an inverse that is right for `+` and `-` and wrong for `*`.
5. **Rivals of the same size.** After a program is accepted, each sub-term is replaced in turn by another term of the same size that had the same column, and the two programs are compared on rows the kernel makes up. If they differ, the task is reported as not determined. This is the check of §5.5.
6. **The scheduler** gives the next step to whichever route predicts the cheapest one. There are no shares set by hand.
7. **A bound on stored classes for each task**, because the first run at a billion cells exhausted a 20 GB heap.

One row of the table did not pay. The inverse row, fed by the solvers of gate X2, changed no verdict on the ladder and added a third to its work (367 million cells against 278 million without it). In the prototype it made two searches 60 to 150 times cheaper, but there a term found through an inverse was accepted at first fit, and here it is held under the size-order rule.

## What the measurements showed

- The size-order rule is dear. On five small conditional tasks it cost 12 to 2,569 times the work of finding the conditional, and the types-only look-ahead cut that by only about 1.3 times.
- The inverse row did not pay. Held under the size-order rule, it changed no verdict and added a third to the ladder's work.
- Memory is the wall. The first run at a billion cells exhausted a 20 GB heap, so each task now has a bound on stored classes.
- Pruning by laws on top of classes saves 3 to 5 times in evaluations and is slower in time on 27 rows.
- One statement in the plan does not reproduce. Risk 2 says the present kernel cannot solve a*x + b = c; a function that only its tests call does solve it.
