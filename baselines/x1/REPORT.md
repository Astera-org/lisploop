
# Baseline for gate X1 (classes and law discovery)

Recorded on 26 November 2026 from a copy of `v1/` at repository commit `65d1df2` (branch `reflective`).
SBCL 2.6.4.debian, Linux, Intel i9-11900H. Nothing under `/home/tlh24/lisploop` was created, edited or deleted.
No bootstrap was run anywhere: the runs load only `v1/load.lisp` from the copy and never touch `library/`.

All files named below are in this directory:
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/stageA/base-x1/`

Tags: **[M]** measured by a run I made (the log is named); **[C]** read from code (file and line, relative to the
repository root); **[D]** read from a document. "Work" always means v1 ledger units unless a sentence says otherwise.

---

## 0. Summary

**The baseline reproduces exactly.** The four observation jobs of `v1/bootstrap/build-batteries.lisp:119-150`
propose 66 + 50 + 35 + 36 = **187 equations** on GF(3), for **206,907 work units** in about **3.0 ms**, observing
**255 terms** that fall into **68 behaviour classes** and keeping about **197 KB** alive [M: `x1-baseline.log`
sections A and A2, `x1-memory.log`]. All 187 pass exhaustive certification; 14 pass the bootstrap's shape filter.
These are the same figures as `plan_v2c_audit/reports/laws-library.md` §1.1 [D].

Three facts change how the gate has to be read. Each is explained in the section given.

1. **187 is not the content of a size bound. It is where a work limit happened to fall (§1.9).** The two
 three-variable jobs are declared with a 44-bit bound, which admits 3,873 terms each, but their work limit of
 80,000 units stops each after exactly 52 terms. The count 187 holds only for work limits from 79,232 to 80,825.
 A new engine with a different tariff cannot reach the same stopping point by "running to the same bound"; it has
 to be told to stop after the same 52 terms, or the comparison has to be made at a bound that ends on a whole
 number of leaves. I recorded both.
2. **187 is a count of lines over four separate runs, not of distinct equations (§2.1).** 156 are distinct; 29
 equations appear in more than one job. Also, the equations are stated over every syntactic term, including
 terms whose sub-terms are not class representatives. An engine that only builds terms from representatives
 states fewer equations (38 instead of 66 for the first job) unless it also lists the members of each class.
3. **"10× less work" is decided by the unit, not by the engine (§4.5).** v1 charges 22 to 33 ledger units for each
 operator applied on each row, almost all of it for re-validating the term and its inputs before every row. An
 evaluator that charges one unit per cell is therefore about 25× cheaper than v1 before it does anything clever,
 and passes a 10× gate stated in ledger units without having classes at all. Counted like for like, in operator
 applications times rows, grouping by class saves 2.4× to 2.8× at the bounds that yield the 187, about 10× with
 four leaves, and 39× to 61× with five leaves (my estimate, §4.5). The gate should name its unit and its bound
 before the new engine is measured.

Distributivity is **not** among the 187, because no job has both `+` and `*` with three variables (§2.3). The v1
engine finds it when given that grammar and a 34-bit bound: 3,477 terms, 274 classes, 3,203 equations,
6,831,983 work units, 75 ms [M: `x1-baseline.log` section E]. That run is recorded here as the baseline for the
"plus distributivity" half of the gate.

---

## 1. What "the 187 equations on GF(3)" are

### 1.1 The code that produces them

`build-algebra-battery` creates four *observation jobs* and runs each once
[C: `v1/bootstrap/build-batteries.lisp:119-150`]. An observation job is the v1 kernel's "bucket engine"
[C: `v1/enumerate.lisp:563-877`]. It draws terms one at a time from the size-ordered enumerator
[C: `v1/enumerate.lisp:59-214`], evaluates each term on every row of a table of inputs, and files the term under the
list of values it produced. A *bucket* is the set of terms filed under one list of values; this report calls it a
*class*. `propose-observed-laws` then reads every class as equations [C: `v1/laws.lisp:215-228`].

The enumerator and the bucket engine are not two engines. The bucket engine is the enumerator plus evaluation and
filing: `start-observation-search` creates the enumerator [C: `v1/enumerate.lisp:714`], and every step of the job goes
through `row-job-step`, which draws the next term from it [C: `v1/enumerate.lisp:263-304`]. So "the v1 kernel's
enumerator at the same bound" and "the bucket engine run to the end of its bound" are the same run.

These four jobs are created only by the bootstrap script. `consolidate-knowledge-library` can also turn
observation jobs that a caller hands it into validated laws, with no shape filter
[C: `v1/consolidate.lisp:1000-1006`], but it creates none itself. The plan notes that nothing in the kernel
initiates discovery [D: `plan_v2c.md` §2.4].

### 1.2 The four jobs

| Job (my name) | Variables | Rows | Operators | Literals | Bound on body bits | Work limit | How it ended |
|:--|--:|--:|:--|:--|--:|--:|:--|
| `obs1` | x0 | 3 | `+ *` | `0 1` | 20 | 20,000 | bound exhausted at 12,516 |
| `obs2` | x0 x1 | 9 | `+ *` | none | 24 | 40,000 | bound exhausted at 34,391 |
| `obs3+` | x0 x1 x2 | 27 | `+` | none | 44 | 80,000 | **cut off** at 80,000 |
| `obs3*` | x0 x1 x2 | 27 | `*` | none | 44 | 80,000 | **cut off** at 80,000 |

Source of every column: [C: `v1/bootstrap/build-batteries.lisp:120-150`]; outcomes [M: `x1-baseline.log` section A].
The four jobs are independent. Each has its own variables, rows and classes, and terms of different jobs are never
compared [C: `v1/enumerate.lisp:689-696`, agreement requires the same scope].

### 1.3 Operators and their meaning

The field is GF(3): the values are the integers 0, 1, 2. `(+ a b)` is `(a + b) mod 3` and `(* a b)` is
`(a * b) mod 3` [C: `v1/vm.lisp:213-221`]. Both are total, so no term in any of the four jobs can fail.

The engine does have a rule for failure, which these jobs never exercise. Division in a field multiplies by the
reciprocal and raises "Division by zero" when the divisor is 0 [C: `v1/vm.lisp:162-170, 219-220`]. A term whose
evaluation fails on any row is recorded with status `:error`, its observation stops at the first failing row, and it
is put in **no** class, so it yields no equation [C: `v1/enumerate.lisp:822-839, 768`]. Only terms that return a value
on every row (`:complete`) are classified.

### 1.4 Leaves

The leaves are the job's variables and its listed literals, all of type GF(3). `obs1` has the literals 0 and 1
and not 2. The other three jobs are given `:literals nil`, which means no literal at all
[C: `v1/bootstrap/build-batteries.lisp:131, 136, 141, 146`; `v1/enumerate.lisp:8-25`]. There are no other constants.

### 1.5 Size, and what the bound admits

Size is counted in **bits of the kernel's code for a term**, not in nodes [C: `v1/ast.lisp:1168-1175`;
`v1/codec.lisp:96-110`]. The bound passed to a job is `header + slack`; the header is the same for every term of a
job (24, 35 and 47 bits for one, two and three variables), so the bound that matters is the slack, the *body bits*
[C: `v1/codec.lisp:89-94`; M: `x1-baseline.log` section 0].

| Node | Body bits | Why |
|:--|--:|:--|
| variable, job with 1 / 2 / 3 variables | 2 / 3 / 4 | 2 tag bits, plus the bits needed to index the variable: 0, 1, 2 |
| literal of GF(3) | 4 | 2 tag bits + 2 value bits |
| application of `+` or `*` | 6 + its arguments | 2 tag bits + 4 opcode bits; no type bits |

[M: `x1-baseline.log` section 0 prints these.] In terms of leaves the four bounds mean the following.

- `obs1`, 20 bits: every term with one or two leaves, and every three-leaf term with at most one literal among its
leaves. Three-leaf terms cost 12 bits plus their leaves, so three variables (18) and two variables with one
literal (20) fit, and two literals (22) do not. That is 3 + 18 + 56 = **77 terms**.
- `obs2`, 24 bits: every term with at most three leaves (two leaves cost 12 bits, three cost 21, four cost 30).
That is 2 + 8 + 64 = **74 terms**. Any bound from 21 to 29 gives the same set.
- `obs3+` and `obs3*`, 44 bits: every term with at most five leaves (14, 24, 34 and 44 bits for two to five
leaves). That is 3 + 9 + 54 + 405 + 3,402 = **3,873 terms** each. The work limit stops both jobs long before
that (§1.9).

[M: counts by leaf in `x1-baseline.log` sections A and B, line `complete-by-leaf-count`.]

### 1.6 The order of enumeration

The order matters twice: it decides which member of a class is the representative, and it decides which 52 terms
the cut-off jobs see. Terms are produced in this order [C: `v1/enumerate.lisp:131-214`]:

1. By body bits, smallest first.
2. Within one size: variables in the order of the input list (x0, x1, x2); then literals in the order listed (0, 1);
 then applications.
3. Applications of one size: by operator, in the order of the language's operator list (`+` before `*`); then by
 the size of the left argument, smallest first (which fixes the size of the right argument); then by the left
 argument's own position in this order; then by the right argument's position. The right argument moves fastest.

So for three variables and `+` the order begins x0, x1, x2, `(+ x0 x0)`, `(+ x0 x1)`, `(+ x0 x2)`, `(+ x1 x0)`, …,
`(+ x2 x2)`, `(+ x0 (+ x0 x0))`, `(+ x0 (+ x0 x1))`, …, `(+ x2 (+ x2 x2))`, `(+ (+ x0 x0) x0)`, `(+ (+ x0 x0) x1)`, ….
The files `x1-observed-obs1.txt`, `x1-observed-obs2.txt`, `x1-observed-obs3plus.txt` and `x1-observed-obs3times.txt`
list every observed term in order, with its leaf count, body bits, class and values [M].

### 1.7 Rows

Each job observes its terms on **every assignment** to its variables: 3, 9 and 27 rows
[C: `v1/bootstrap/build-batteries.lisp:124-126`]. Row *i* assigns x_j = floor(i / 3^j) mod 3, so x0 varies fastest
[C: `v1/laws.lisp:74-90, 116-118`; M: `x1-baseline.log` section 0 prints the nine rows for two variables]. A term is
evaluated on all rows of its job even when it does not mention every variable. The order of rows does not affect
the classes, only the printed value vectors.

### 1.8 When two terms are equal, and which equation is written

Two terms of one job are equal when they have the same type and the same list of values on all rows, compared with
`equal` [C: `v1/enumerate.lisp:765, 769`; the classes are an `equal` hash table keyed on `(type values)`, `:702`]. On
GF(3) with every assignment as a row this is equality as functions, so every equation is true on the whole field.

The classes are kept in order of creation and their members in order of observation. For each class, the **first
member observed is the representative**, and each later member contributes one equation
`(= later-member representative)` [C: `v1/laws.lisp:219-227`]. The left side is the later term and the right side is
the representative. Because of the order in §1.6 the representative is the smallest member in body bits, with ties
broken by that order. A class with *m* members gives *m* − 1 equations, a spanning star and not all pairs.

So for every job: **equations = terms observed − classes.**

### 1.9 No filter is applied; 187 is where the work limit fell

Nothing removes equations between the classes and the count of 187. In particular instances of other equations
are **not** removed: `(+ (+ x0 x0) x1) = (+ x0 (+ x0 x1))` is kept beside associativity. The only filter in the
bootstrap comes afterwards: `law-operator-fact` keeps an equation only if it has the shape of commutativity,
associativity or an identity [C: `v1/consolidate.lisp:709-735`, applied at `v1/bootstrap/build-batteries.lisp:155`].
It keeps 14 of the 187 (4 + 2 + 4 + 4) [M: `x1-baseline.log` section A, `pass-law-operator-fact`].

| Job | Terms observed | Classes | Equations | Work | Ended by |
|:--|--:|--:|--:|--:|:--|
| `obs1` | 77 | 11 | 66 | 12,516 | bound |
| `obs2` | 74 | 24 | 50 | 34,391 | bound |
| `obs3+` | 52 | 17 | 35 | 80,000 | work limit |
| `obs3*` | 52 | 16 | 36 | 80,000 | work limit |
| **Total** | **255** | **68** | **187** | **206,907** | |

[M: `x1-baseline.log` section A.]

**The two three-variable jobs stop after 52 of their 3,873 terms.** The 52 are: the 3 variables, all 9 two-leaf
terms, all 27 three-leaf terms of the form `(op a (op b c))`, and the first 13 of the 27 of the form
`(op (op a b) c)`, namely (a, b, c) from (x0, x0, x0) to (x1, x1, x0) in the order of §1.6. The last term observed is
`(op (op x1 x1) x0)`. The 53rd, `(op (op x1 x1) x1)`, had been built and stored by the enumerator but not yet
evaluated on all rows when the limit was reached, so it is in no class [M: `x1-observed-obs3plus.txt`,
`x1-observed-obs3times.txt`; `trees-kept-by-enumerator=53` in `x1-baseline.log`].

The ledger total at the moment the *k*-th term is filed is 79,232 for k = 52 and 80,826 for k = 53, in both jobs
[M: `x1-baseline.log` section D]. So:

| Work limit of each three-variable job | Terms each | Equations (`obs3+` / `obs3*`) | Total with `obs1`, `obs2` |
|--:|--:|:--|--:|
| 60,000 | 40 | 23 / 24 | 163 |
| 79,000 | 51 | 34 / 35 | 185 |
| **79,232 to 80,825** (shipped: 80,000) | **52** | **35 / 36** | **187** |
| 81,000 | 53 | 36 / 37 | 189 |
| 100,000 | 64 | 47 / 48 | 211 |
| 102,113 or more, with the bound lowered to 24 bits (three leaves) | 66 | 49 / 50 | 215 |
| 1,000,000 | 509 | 484 / 485 | 1,085 |
| no limit, bound 34 bits (four leaves) | 471 | 448 / 449 | 1,013 |
| no limit, bound 44 bits as declared (five leaves) | 3,873 | 3,847 / 3,848 | 7,811 |

[M: `x1-baseline.log` sections B, C and D.] The 35 and 36 shipped equations are subsets of the equations at 24, 34
and 44 bits, because the 52 terms are a prefix of the order and the representative of a class never changes once
chosen [M: `x1-check.log`, "the cut-off jobs against their natural bounds"]. Associativity survives the cut only
because `(op (op x0 x1) x2)` is the 45th term.

Neighbouring bounds for the two jobs that do finish [M: `x1-baseline.log` section C]:

| Job | Body-bit bound | Terms | Classes | Equations | Work |
|:--|--:|--:|--:|--:|--:|
| `obs1` | 18 | 29 | 9 | 20 | 4,106 |
| `obs1` | **20** (shipped) | **77** | **11** | **66** | **12,516** |
| `obs1` | 22 | 173 | 12 | 161 | 30,918 |
| `obs1` | 24 | 237 | 12 | 225 | 44,308 |
| `obs2` | 12 to 20 | 10 | 8 | 2 | 3,443 to 3,651 |
| `obs2` | **21 to 29** (shipped: 24) | **74** | **24** | **50** | 34,274 to 34,626 (**34,391** at 24) |
| `obs2` | 30 | 714 | 66 | 648 | 421,873 |

Every size in `obs1` is an even number of bits, so an odd bound admits the same terms as the even bound below it
[C, from the sizes in §1.5]. A bound that admits no new term still costs a few hundred units more, because the
enumerator steps through each empty size.

---

## 2. The equations themselves

### 2.1 Files

| File | Content |
|:--|:--|
| `x1-equations.txt` | **The 187**, one `(= LHS RHS)` per line, sorted by byte order. LHS is the later member, RHS the representative. 31 lines are repeats of another line, because a job repeats what a smaller job found. |
| `x1-equations-by-job.txt` | The same 187 as `job<tab>(= LHS RHS)`, in the order v1 proposes them: jobs in the order above, classes in order of creation, members in order of observation. |
| `x1-equations-distinct.txt` | The 156 distinct lines. |
| `x1-equations-typed.sexp` | The same 187 in the kernel's portable typed form (`ast->sexp`), one `("job" (:APP (:OP := (:GF 3)) …))` per line; `sexp->ast` reads the second element back [C: `v1/ast.lisp:1286-1326`]. |
| `x1-classes.txt` | All 68 classes: job, class index, member count, values on the rows, representative, then every member in order of observation. |
| `x1-observed-obs1.txt`, `-obs2`, `-obs3plus`, `-obs3times` | Every observed term in order, with leaves, body bits, status, class and values. |
| `x1-exhausted-<job>.equations.txt`, `.classes.txt` | The same four grammars run to the end of their declared bit bounds (3,847 and 3,848 equations for the three-variable jobs). |
| `x1-bound24-obs3plus.*`, `x1-bound24-obs3times.*`, `x1-bound34-…` | The three-variable jobs at 24 bits (three leaves: 49 and 50 equations) and 34 bits (four leaves: 448 and 449). |
| `x1-dist24.*`, `x1-dist33.*`, `x1-dist34.*` | Three variables with both `+` and `*`, at 24, 33 and 34 bits: equations and full classes. The 33-bit files equal the 24-bit ones. Distributivity is line 1849 of `x1-dist34.equations.txt`. |
| `x1-dist44.classes-reps.txt` | The same grammar at 44 bits: the 1,241 classes with member count and representative only. |
| `x1-SHA256SUMS` | Checksums of all the data files above; `run-baseline.sh` checks a fresh run against them. |

The syntax is the surface form that the kernel's `term` reader takes [C: `v1/ast.lisp:1384-1390`]: lower-case
operator names, variables written `x0`, `x1`, `x2`, literals as bare numbers. Variable names are per job: `x0` in
`obs1` and `x0` in `obs3+` are different variables of different runs that happen to share a name, which is why a
line can repeat.

### 2.2 Which familiar laws are among the 187

[M: `x1-named-laws.log`, produced by `x1-named-laws.sh` from `x1-equations-by-job.txt`.]

| Law | Equation as written | Present | Job |
|:--|:--|:--|:--|
| Commutativity of `+` | `(= (+ x1 x0) (+ x0 x1))` and the pairs with x2 | yes | `obs2`, `obs3+` |
| Commutativity of `*` | `(= (* x1 x0) (* x0 x1))` and the pairs with x2 | yes | `obs2`, `obs3*` |
| Associativity of `+` | `(= (+ (+ x0 x1) x2) (+ x0 (+ x1 x2)))` | yes | `obs3+` |
| Associativity of `*` | `(= (* (* x0 x1) x2) (* x0 (* x1 x2)))` | yes | `obs3*` |
| Identity of `+`, both sides | `(= (+ x0 0) x0)`, `(= (+ 0 x0) x0)` | yes | `obs1` |
| Identity of `*`, both sides | `(= (* x0 1) x0)`, `(= (* 1 x0) x0)` | yes | `obs1` |
| Zero of `*`, both sides | `(= (* x0 0) 0)`, `(= (* 0 x0) 0)` | yes | `obs1` |
| Distributivity | `(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))` | **no** | |
| One instance of distributivity | `(= (* x0 (+ x0 1)) (+ x0 (* x0 x0)))` | yes | `obs1` |
| Inverse laws | any equation with `-`, `/` or a negation | **no** | |
| True on GF(3) only | `(= (* x0 (* x0 x0)) x0)`, `(= (+ x0 (+ x0 x0)) 0)` | yes | `obs1`, `obs2`, `obs3*` |

The fourteen equations that the bootstrap's shape filter keeps are exactly the first six rows: 6 commutativity
equations in the three-variable jobs and 2 in `obs2`, 2 associativity, 4 identities [M: `x1-baseline.log` section A].

There are no inverse laws because no job's grammar can state one. The only operators that occur anywhere in the
187 are `+` and `*`, and the only literals are 0 and 1 [M: `x1-named-laws.log`]. Subtraction, division and negation
are not offered, and neither is the literal 2, which is −1 in GF(3). The nearest thing is `x + x + x = 0`, which
says that `x + x` is the additive inverse of `x` but is a fact of characteristic 3, not a law of rings. The audit
found that 16 of the 187 are false on the integers for this reason [D: `plan_v2c_audit/reports/laws-library.md` §1.1;
not re-measured here].

### 2.3 Distributivity

Distributivity is not among the 187, and the reason is the configuration, not size or pruning
[C: `v1/bootstrap/build-batteries.lisp:127-146`]:

- It needs three variables and both operators in one job. `obs1` and `obs2` have both operators but one and two
variables; `obs3+` and `obs3*` have three variables but one operator each.
- Nothing is pruned. If a job contained both sides they would land in one class.

Its two sides measure 24 body bits for `(* x0 (+ x1 x2))` (three leaves) and 34 for `(+ (* x0 x1) (* x0 x2))`
(four leaves). So it **first appears at a 34-bit bound, with three variables and the operators `+` and `*`**
[M: `x1-baseline.log` section E]:

| Grammar: x0 x1 x2, `+ *`, no literals | Terms | Classes | Equations | Work | Wall time | Both sides in one class |
|:--|--:|--:|--:|--:|--:|:--|
| 24 bits (three leaves) | 237 | 63 | 174 | 376,299 | 4.6 ms | right side not yet built |
| 33 bits | 237 | 63 | 174 | 376,767 | 4.7 ms | right side not yet built |
| **34 bits (four leaves)** | **3,477** | **274** | **3,203** | **6,831,983** | **75 ms** | **yes** |
| 44 bits (five leaves) | 57,909 | 1,241 | 56,668 | 135,437,377 | 1.46 s | yes |
| 34 bits with the bootstrap's limit of 80,000 | 54 | 34 | 20 | 80,000 | | neither side reached |

At 34 bits the class of `(* x0 (+ x1 x2))` has 12 members: the four ways of writing the left side with `+` and `*`
commuted, and the eight ways of writing the right side. Its representative is `(* x0 (+ x1 x2))`, and the equation
proposed is `(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))`. All 3,203 equations at this bound pass exhaustive
certification [M: `x1-baseline.log` section E]. With two variables an instance such as
`(* x0 (+ x0 x1)) = (+ (* x0 x0) (* x0 x1))` needs four leaves, 30 bits, so `obs2` at 24 bits does not reach it either.

---

## 3. Certification

The plan's "finite-field certification, with counterexamples, about 228 lines" is `v1/laws.lisp:1-228`
[D: `plan_v2c.md` §9; C]. It checks a law by running it on **every assignment** of its declared inputs in the
metered VM.

**Entry points and arguments** [C]:

| Function | Where | Arguments and result |
|:--|:--|:--|
| `make-law` | `v1/laws.lisp:30-50` | `(domain inputs left right &key guard origin)`. Builds an unregistered `:law` entry whose expression is `(= left right)`; the guard defaults to the literal true; status `:conjecture`. |
| `start-law-validation` | `v1/laws.lisp:96-114` | `(law &key samples)`. Without `samples` the validation is exhaustive over `finite-type-cardinality` of the tuple of all inputs. Returns a `law-validation` state that works on a private copy of the law. |
| `resume-law-validation` | `v1/laws.lisp:178-185` | `(state work-limit &key quantum)`. Runs until the status is no longer `:unknown` or the validation's own ledger reaches `work-limit`. Resumable. |
| `law-validation-step` | `v1/laws.lisp:141-176` | `(state budget)`. One phase of the check. |
| `validate-law` | `v1/laws.lisp:187-191` | `(law work-limit sampled-p samples)`. Start and resume in one call. |
| `law-assignment` | `v1/laws.lisp:116-118` | `(inputs &optional index)`. The index-th assignment; the same function generates the observation rows. |
| `law-validation-status`, `-counterexample`, `-ledger`, `-law` | struct at `v1/laws.lisp:55-57` | Status is `:unknown`, `:validated`, `:refuted`, `:vacuous` or `:conjecture`. |
| `law-validation-certificate` | `v1/laws.lisp:59-64` | The certificate, or nil if the law no longer reads as it did when checked. |
| `attest-knowledge-entry`, `knowledge-evidence-current-p`, `knowledge-evidence-tested-p`, `knowledge-statement-snapshot` | `v1/evidence.lisp:23-73` | The evidence grades (below). |
| `register-knowledge-law` | `v1/laws.lisp:1031-1042` | `(law-or-validation &key id library status edges metadata ledger)`. Files a validated law in a library with the evidence it earned. |
| `propose-observed-laws` | `v1/laws.lisp:215-228` | `(job &key guard ledger)`. Classes to equations; these are proposals, "not certificates". |

**What is checked** [C: `v1/laws.lisp:141-176, 120-139`]. For each index from 0 to N − 1, where N is the product of the
sizes of the types of **all** the law's inputs (27 for a three-variable job even when the equation mentions two
variables): build the assignment; evaluate the guard; if the guard raises an error the law is refuted; if it is
false the assignment is skipped; if it is true the assignment is counted as *active* and the expression
`(= left right)` is evaluated. If that raises an error or returns false, the law is **`:refuted`** and the state
keeps a counterexample `(:inputs values :phase :guard-or-:equation :status … :error …)`. If every assignment passes,
the status is `:validated`, or `:vacuous` when no assignment was active. If the work limit is reached first the
status stays `:unknown` and there is no certificate.

**The evidence grade** [C: `v1/laws.lisp:132-139`; `v1/evidence.lisp:45-73`]. A validated law is attested with method
`:exhaustive` and obligation `(:equivalence)`, and its certificate also records `:assignments`, `:active` and
`:work`. The certificate carries a snapshot of the statement (expression, guard, inputs, domain, the simulator and
encoding versions, and the definitions it depends on) and counts only while that snapshot still matches, so it
lapses when anything it rests on changes. `:exhaustive`, `:derived` and `:trusted-axiom` are *current* evidence,
the only grades that let a law be used as a rewrite [C: `v1/evidence.lisp:62-65`; `v1/laws.lisp:1016`]. A validation on
samples gives status `:conjecture` and a `:sampled` certificate, which is *tested* but not current evidence:
"Samples NEVER certify a law" [C: `v1/laws.lisp:97`].

**Measured** [M: `x1-baseline.log` sections A, E and G]:

| What | Result |
|:--|:--|
| All 187, exhaustive on GF(3) | 187 validated, 0 refuted; every certificate is `(:exhaustive (:equivalence))`; 2,565 assignments; 320,157 work units (20,390 + 52,326 + 123,379 + 124,062) |
| Dearest single law in each job | 391, 1,077, 3,655 and 3,655 units |
| All 3,203 equations of the distributivity run at 34 bits | 3,203 validated; 86,481 assignments; 13,417,591 units |
| `(+ x1 x0) = (+ x0 x1)`, two variables | `:validated`; 9 assignments, 9 active; 823 units (39 setup, 10 scheduling, 774 checking) |
| `(+ x0 x1) = (* x0 x1)` | `:refuted` after 213 units; counterexample `(:inputs (1 0) :phase :equation :status :value)`; no certificate |
| The first law with a work limit of 50 | status `:unknown`, no certificate |
| `(* x0 (* x0 x0)) = x0` retyped to the integers and sampled | `:refuted` at input −3 |

Two things follow for the new engine. Certifying the 187 costs v1 more than finding them (320,157 against
206,907), and the bootstrap avoids that cost only by certifying the 14 it keeps
[C: `v1/bootstrap/build-batteries.lisp:155-158`]. And on a finite field, where the rows are the whole domain,
certification repeats the evaluation that formed the class, as the audit observed
[D: `plan_v2c_audit/reports/laws-library.md` §1.1].

---

## 4. The work baseline

### 4.1 What a work unit is, and what v1 charges for

The ledger is a counter with a breakdown by category; `charge` adds to it, and a job stops when its total reaches
the limit it was given [C: `v1/vm.lisp:10-54`; `v1/enumerate.lisp:315-343`]. The same totals result whether terms are
run by the interpreter or by compiled closures, and however the run is cut into slices
[M: `x1-baseline.log` section H: identical ledger, terms and equations in all three modes for all four jobs].

For these jobs the charges are as follows. *n* is the number of variables and R = 3^n the number of rows.
[C for each rule; M for the whole: the Python re-implementation in `x1-check.py` rebuilds every category of every
ledger from these rules and matches the Lisp log exactly, including the two cut-off jobs; `x1-check.log`.]

| Category | Charge | Code |
|:--|:--|:--|
| `:setup` | Once per job: R × (1 + 3n) | `v1/enumerate.lisp:718-723` |
| `:enumeration` | 1 per step of the enumerator's cursor, whether or not the step yields a term | `v1/enumerate.lisp:273` |
| `:construction` | Per term built: its *syntax work*. A variable costs 5 (6 for x2), a literal 7, an application 5 plus its arguments | `v1/enumerate.lisp:279, 286`; `v1/ast.lisp:607-612, 638, 685, 966` |
| `:scheduling` | Per term: R + 1 | `v1/enumerate.lisp:295` |
| `:evaluation` | Per term **and per row**: the term's syntax work again, plus 7 per variable of the job (8 for x2) to re-validate the input declarations and values, plus the instructions: 1 per variable leaf, 4 per literal leaf, and **2 per operator application (1 to visit it and 1 to apply it)** | `v1/vm.lisp:256-278, 530-551, 100-108` |
| `:indexing` | Per term: 1 + 3R, for hashing its value list | `v1/enumerate.lisp:799-803` |

So one work unit is **not** one operator applied on one row. Applying `+` or `*` once on GF(3) costs exactly one
unit [C: `v1/vm.lisp:100-103`], but around each such unit v1 spends twenty to thirty more. For the distributivity
run at 34 bits the 6,831,983 units divide as follows [M: `x1-baseline.log` section E; split of `:evaluation` from
`x1-check.log`]:

| Part | Units | Share |
|:--|--:|--:|
| Re-validating the term's syntax before every row | 3,338,118 | 48.9% |
| Re-validating the input declarations and values before every row | 2,065,338 | 30.2% |
| Visiting nodes (`:eval` instructions) | 643,059 | 9.4% |
| **Applying operators (`:apply` instructions) = operator applications × rows** | **274,590** | **4.0%** |
| Indexing | 285,114 | 4.2% |
| Construction | 123,634 | 1.8% |
| Scheduling, enumeration, setup | 102,130 | 1.5% |

v1 also evaluates each whole term from its leaves on every row. It does not reuse the values of the sub-terms it
has already observed, so a four-leaf term costs three operator applications per row, not one.

### 4.2 The run that yields the 187

[M: `x1-baseline.log` sections A and A2; memory from `x1-memory.log`.]

| | `obs1` | `obs2` | `obs3+` | `obs3*` | Total |
|:--|--:|--:|--:|--:|--:|
| Equations | 66 | 50 | 35 | 36 | **187** |
| Ledger work | 12,516 | 34,391 | 80,000 | 80,000 | **206,907** |
| … `:evaluation` | 9,183 | 29,232 | 72,386 | 72,386 | 183,187 |
| … `:indexing` | 770 | 2,072 | 4,264 | 4,264 | 11,370 |
| … `:construction` | 1,833 | 1,730 | 1,216 | 1,216 | 5,995 |
| … `:scheduling` | 308 | 740 | 1,470 | 1,470 | 3,988 |
| … `:enumeration` | 410 | 554 | 394 | 394 | 1,752 |
| … `:setup` | 12 | 63 | 270 | 270 | 615 |
| Wall time, median of 50 runs (µs) | 341 | 612 | 1,014 | 1,040 | **3,007** |
| Terms observed (filed in a class) | 77 | 74 | 52 | 52 | **255** |
| Trees built and kept by the enumerator | 77 | 74 | 53 | 53 | **257** |
| Classes | 11 | 24 | 17 | 16 | **68** |
| Operator applications × rows | 390 | 1,224 | 2,403 | 2,403 | **6,420** |
| Nodes × rows | 1,011 | 3,114 | 6,210 | 6,210 | 16,545 |
| Non-leaf trees × rows | 222 | 648 | 1,323 | 1,323 | 3,516 |
| Bytes kept alive by the job | 39,172 | 47,614 | 55,223 | 55,052 | **197,061** |
| … with the closure cache | 45,188 | 53,375 | 59,224 | 59,052 | 216,839 |

Wall time for the four jobs together varied between 3.0 and 3.7 ms across five runs of the whole script; the
final log has 3,007 µs as the sum of medians and 2,959 µs as the sum of minima. That is about 69 million work
units per second. The audit's log shows 0.000 s for these jobs because `get-internal-real-time` advances in 4 ms
steps on this host; I timed with the monotonic clock.

### 4.3 The enumerator at the same bound and grammar

As §1.1 explains, the baseline for "the v1 kernel's enumerator, which keeps every syntactic tree it builds" is the
same observation job run to the end of its bound. Two of the four shipped jobs already are that. For the other
two, and for the distributivity grammar, I ran the bound to exhaustion [M: `x1-baseline.log` sections B, C, E; wall
time from one run each].

| Grammar and body-bit bound | Trees built and kept | Classes | Equations | Ledger work | Wall time | Operator applications × rows | Non-leaf trees × rows |
|:--|--:|--:|--:|--:|--:|--:|--:|
| `obs1`, 20 | 77 | 11 | 66 | 12,516 | 0.35 ms | 390 | 222 |
| `obs2`, 24 | 74 | 24 | 50 | 34,391 | 0.6 ms | 1,224 | 648 |
| `obs3+`, 24 (three leaves) | 66 | 17 | 49 | 102,113 | 1.3 ms | 3,159 | 1,701 |
| `obs3*`, 24 | 66 | 16 | 50 | 102,113 | 1.3 ms | 3,159 | 1,701 |
| `obs3+`, 34 (four leaves) | 471 | 23 | 448 | 909,310 | 10 ms | 35,964 | 12,636 |
| `obs3*`, 34 | 471 | 22 | 449 | 909,310 | 10 ms | 35,964 | 12,636 |
| `obs3+`, 44 (as declared) | 3,873 | 26 | 3,847 | 8,947,503 | 89 ms | 403,380 | 104,490 |
| `obs3*`, 44 (as declared) | 3,873 | 25 | 3,848 | 8,947,503 | 90 to 104 ms | 403,380 | 104,490 |
| x0 x1 x2, `+ *`, 24 | 237 | 63 | 174 | 376,299 | 4.6 ms | 12,150 | 6,318 |
| **x0 x1 x2, `+ *`, 34 (distributivity)** | **3,477** | **274** | **3,203** | **6,831,983** | **75 ms** | **274,590** | **93,798** |
| x0 x1 x2, `+ *`, 44 | 57,909 | 1,241 | 56,668 | 135,437,377 | 1.46 s | 6,153,246 | 1,563,462 |

The four shipped bit bounds run to exhaustion come to 12,516 + 34,391 + 2 × 8,947,503 = **17,941,913** units and
7,897 trees in 86 classes.

"Operator applications × rows" is what v1 actually executes, since it evaluates every term from its leaves.
"Non-leaf trees × rows" is what the same enumeration would cost an evaluator that applies only the top operator
of each new tree to the stored columns of its parts, with no notion of class.

The enumerator **by itself**, drawing and storing trees without evaluating them, charges very little
[M: `x1-baseline.log` section F]:

| Grammar and bound | Cursor steps | Trees built and kept | Construction units | Work (steps + construction) | Wall time |
|:--|--:|--:|--:|--:|--:|
| `obs1`, 20 | 410 | 77 | 1,833 | 2,243 | 0.15 ms |
| `obs2`, 24 | 554 | 74 | 1,730 | 2,284 | 0.13 ms |
| `obs3+` or `obs3*`, 44 | 4,922 | 3,873 | 175,036 | 179,958 | 4.5 ms |
| x0 x1 x2, `+ *`, 34 | 4,504 | 3,477 | 123,634 | 128,138 | 4.0 ms |
| x0 x1 x2, `+ *`, 44 | 59,658 | 57,909 | 2,663,794 | 2,723,452 | 68 ms |

For the three larger runs that is 2% of the job's work (18% and 7% for the two small jobs). The rest is
evaluating and filing the trees.

### 4.4 What is kept in memory

What v1 keeps for a job, per object [C]:

- **Every tree, in the enumerator.** `index-expression` appends each built term to a vector keyed by type and size,
and nothing is ever removed [C: `v1/enumerate.lisp:59-82`]. A tree is three cons cells that point at its operator
and at its two argument trees, which are shared with earlier trees, so the store is a graph
[C: `v1/ast.lisp:1110-1116`]. Each node also has a nine-field metadata record in a global weak table
[C: `v1/ast.lisp:21-33`].
- **Every observed term, with its values.** One record per term holding the list of its R values, one entry in a
hash table from term to record, and one cell each in the job's list of records and in its class's list of
members [C: `v1/enumerate.lisp:601-602, 766-767, 776, 788`].
- **Every class**, one record with its value list [C: `v1/enumerate.lisp:604-605, 796`].
- A cache of compiled closures, at most 32,768 nodes, shared by all jobs [C: `v1/vm.lisp:421-426`].

So the count of retained term objects equals the count of trees: 257 for the shipped run, 3,477 for the
distributivity run. Memory grows with trees × rows, not with classes.

Bytes were measured as live dynamic-space usage after two full garbage collections, before the job exists and
again while it is reachable, in a fresh SBCL process for each line. Small jobs are below the resolution of that
method, so each was measured with 200 identical jobs held at once and the difference divided by 200; a second
measurement with 50 copies agreed within 3%. "Enumerator only" is what remains reachable when everything but the
enumerators is dropped. [M: `x1-memory.log`; method in `x1-memory.lisp`.]

| Grammar and bound | Rows | Trees | Classes | Bytes kept by the job | Per tree | Per class | Enumerator only, per tree |
|:--|--:|--:|--:|--:|--:|--:|--:|
| `obs1`, 20 (shipped) | 3 | 77 | 11 | 39,172 | 509 | 3,561 | 264 |
| `obs2`, 24 (shipped) | 9 | 74 | 24 | 47,614 | 643 | 1,984 | 252 |
| `obs3+`, cut at 80,000 (shipped) | 27 | 53 | 17 | 55,223 | 1,042 | 3,248 | 288 |
| `obs3*`, cut at 80,000 (shipped) | 27 | 53 | 16 | 55,052 | 1,039 | 3,441 | 288 |
| `obs3+`, 34 | 27 | 471 | 23 | 397,238 | 843 | 17,271 | 234 |
| `obs3+`, 44 | 27 | 3,873 | 26 | 3,236,572 | 836 | 124,484 | 248 |
| x0 x1 x2, `+ *`, 24 | 27 | 237 | 63 | 216,797 | 915 | 3,441 | 252 |
| x0 x1 x2, `+ *`, 34 | 27 | 3,477 | 274 | 2,848,672 to 2,876,516 | 819 to 827 | 10,397 to 10,498 | 230 to 238 |
| x0 x1 x2, `+ *`, 44 | 27 | 57,909 | 1,241 | 47,888,224 | 827 | 38,588 | 235 |

Read down the last three rows for the statement the gate wants reversed: from 34 to 44 bits the trees grow 16.7×,
the classes 4.5×, and v1's memory 16.7×. Bytes per tree are steady at about 830 with 27 rows, of which about 240
are the enumerator's own store and the rest is the observation record, mostly the 27 stored values at 16 bytes
each. Bytes per class are not steady: they grow 3.7×. For `obs3+` at 44 bits v1 keeps 3.2 MB for 26 classes.

The plan's figure of "about 430 bytes" per kept tree [D: `plan_v2c.md` §2.3] was measured on search jobs over other
grammars. I did not re-measure it. It is not comparable with the 830 here, which includes a stored list of values
for every term.

### 4.5 The baseline in cells, and what "10× less" means under each reading

A new evaluator that charges one unit per cell, meaning one operator applied on one row, can be compared with v1
in three ways. They give very different answers, so the gate has to say which it means.

**Reading 1: v1 ledger units against the new engine's cells.** This is the literal wording, since the ledger is
what v1 calls work. v1 spends 22 to 33 ledger units per operator application per row (206,907 / 6,420 = 32.2 for
the shipped run; 24.9 for the distributivity run; 22.0 at 44 bits) [M: `x1-baseline.log`, lines
`work/(operator-application*row)`]. An engine that evaluates the same trees from their leaves, with no classes and
no reuse, already beats v1 by that factor. **A 10× gate in these units is passed by the change of unit alone and
says nothing about classes.**

**Reading 2: operator applications × rows on both sides.** This is like for like on evaluation. It is v1's
`:apply` count, the "operator applications × rows" column of §4.3.

**Reading 3: one column per non-leaf tree on the v1 side.** This compares against an imagined v1 that already
evaluates by column but still enumerates every tree. It isolates what classes add.

To see what a class engine can gain under readings 2 and 3, I counted, in the Python re-implementation and not in
v1, how many columns the simplest class-based evaluator must compute at each bound: terms are built from class
representatives only, and one column is computed for each distinct combination of an operator and two classes.
This is an **estimate of the least work the simplest class engine needs, not a baseline**. It uses no law (not
even commutativity) to skip a combination. It finds the same classes and the same representatives as v1 at every
bound tried [M: `x1-check.log`, last section].

| Grammar and bound | v1 ledger | v1 operator applications × rows | v1 non-leaf trees × rows | Class engine: columns | Class engine: cells | Reading 1 | Reading 2 | Reading 3 |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| `obs1`, 20 | 12,516 | 390 | 222 | 46 | 138 | 91× | 2.8× | 1.6× |
| `obs2`, 24 | 34,391 | 1,224 | 648 | 56 | 504 | 68× | 2.4× | 1.3× |
| `obs3+`, 24 | 102,113 | 3,159 | 1,701 | 45 | 1,215 | 84× | 2.6× | 1.4× |
| `obs3+`, 34 | 909,310 | 35,964 | 12,636 | 129 | 3,483 | 261× | 10.3× | 3.6× |
| `obs3+`, 44 | 8,947,503 | 403,380 | 104,490 | 261 | 7,047 | 1,270× | 57× | 14.8× |
| `obs3*`, 44 | 8,947,503 | 403,380 | 104,490 | 243 | 6,561 | 1,364× | 61× | 15.9× |
| x0 x1 x2, `+ *`, 24 | 376,299 | 12,150 | 6,318 | 162 | 4,374 | 86× | 2.8× | 1.4× |
| **x0 x1 x2, `+ *`, 34** | 6,831,983 | 274,590 | 93,798 | 1,026 | 27,702 | 247× | **9.9×** | 3.4× |
| x0 x1 x2, `+ *`, 44 | 135,437,377 | 6,153,246 | 1,563,462 | 5,862 | 158,274 | 856× | 39× | 9.9× |

The consequences for the gate:

- At the bounds that yield the 187 (three leaves) a class engine does about 2.5× fewer operator applications
than v1, not 10×. **No engine can do 10× fewer there.** Even one column for each class whose representative has
an operator, which is the floor for any engine that evaluates each class once, is 8 × 3 + 22 × 9 + 14 × 27 +
13 × 27 = 951 cells, and a tenth of v1's 6,420 is 642 [M: class counts from `x1-classes.txt`].
- At the bound where distributivity appears (34 bits, four leaves) the simplest class engine is at 9.9× under
reading 2, on the edge of the gate. It would need one further saving, such as skipping `(op b a)` once
`(op a b)` is known for a commutative operator, to pass with room.
- At the declared 44-bit bound of the three-variable jobs the gain is 57× to 61× under reading 2 and about 15×
under reading 3. This is the bound at which "10× less work than the enumerator at the same bound" is a real
test of classes.

The numbers to beat, for whichever reading is chosen:

| Configuration | v1 ledger units | 10% of it | v1 operator applications × rows | 10% of it |
|:--|--:|--:|--:|--:|
| The shipped run (two jobs cut off) | 206,907 | 20,690 | 6,420 | 642 |
| Four jobs, three-variable ones at 24 bits | 251,133 | 25,113 | 7,932 | 793 |
| Four jobs at their declared bit bounds, exhausted | 17,941,913 | 1,794,191 | 808,374 | 80,837 |
| Distributivity grammar at 34 bits | 6,831,983 | 683,198 | 274,590 | 27,459 |
| Distributivity grammar at 44 bits | 135,437,377 | 13,543,737 | 6,153,246 | 615,324 |

---

## 5. How to re-run

```
bash run-baseline.sh
```

run in this directory. It deletes and re-creates the copy `./v1` from `/home/tlh24/lisploop/v1` (set `REPO=` for
another checkout), runs `x1-baseline.lisp` in SBCL (about 6 to 10 s), compares every data file with `x1-SHA256SUMS`,
runs the independent Python check, measures memory (16 short SBCL processes, about 40 s; skip with
`X1_SKIP_MEMORY=1`), and prints the work numbers. Its last output is kept in `run-baseline.out`. Two further full
runs from a fresh copy, made after the checksums were recorded, reproduced every data file byte for byte.

| Script | What it does | Log |
|:--|:--|:--|
| `run-baseline.sh` | Everything, from a fresh copy | `run-baseline.out` |
| `x1-baseline.lisp`, `x1-lib.lisp` | The v1 runs: the four jobs as shipped (A), their wall time (A2), the same bounds exhausted (B), neighbouring bounds (C), work-limit sensitivity (D), distributivity (E), the enumerator alone (F), certification shown on single laws (G), independence of the ledger from evaluation mode and slicing (H). Writes all `x1-*.txt` and `.sexp` data files. Calls only the kernel's own entry points; changes no kernel code. | `x1-baseline.log` |
| `x1-check.py` | A re-implementation in Python written from §1 and §4.1 of this report, sharing no code with the kernel. It regenerates the observed terms, classes and equations of every recorded configuration and every ledger category, and compares them with the Lisp output. 56 checks, all pass. Also produces the class-engine estimate of §4.5. | `x1-check.log` |
| `x1-memory.lisp`, `run-memory.sh` | Retained bytes, one process per configuration | `x1-memory.log` |
| `x1-named-laws.sh` | Looks up the familiar laws in the 187 | `x1-named-laws.log` |

Because `x1-check.py` reproduces the v1 output from this report's description alone, §1 is complete enough to
implement a comparable run on another engine.

---

## 6. What a new engine must match

To reproduce **the 187** it must run four separate spaces with this configuration.

| Item | Value |
|:--|:--|
| Field | GF(3): values 0, 1, 2; `+` and `*` are integer addition and multiplication reduced mod 3 |
| Spaces | Four, independent: `obs1`, `obs2`, `obs3+`, `obs3*`. Terms of different spaces are never compared. |
| Variables | `obs1`: x0. `obs2`: x0, x1. `obs3+` and `obs3*`: x0, x1, x2. |
| Operators, in this order | `obs1`: `+`, `*`. `obs2`: `+`, `*`. `obs3+`: `+`. `obs3*`: `*`. |
| Literals, in this order | `obs1`: 0, 1. The others: none. |
| Rows | Every assignment: 3, 9, 27 rows. Row i sets x_j = floor(i / 3^j) mod 3. |
| Size of a term | Body bits: variable 2, 3 or 4 bits in a space of 1, 2 or 3 variables; literal 4; application 6 plus its arguments. |
| Size bound | `obs1`: 20 bits (77 terms). `obs2`: 24 bits (74 terms). `obs3+`, `obs3*`: declared 44 bits, but see the next row. |
| Stopping point of `obs3+`, `obs3*` | After the first **52** terms in the order below: the 3 variables, the 9 two-leaf terms, the 27 terms `(op a (op b c))`, and the 13 terms `(op (op a b) c)` from (x0, x0, x0) through (x1, x1, x0). Listed in `x1-observed-obs3plus.txt` and `x1-observed-obs3times.txt`. |
| Order of terms | By body bits; then variables in input order, literals in listed order, applications; applications by operator order, then left-argument size ascending, then the left argument's position in this order, then the right argument's. |
| Failure | Not possible in these grammars. In v1 a term that fails on any row joins no class. |
| Equality | Same list of values on all rows of the space. |
| Representative | The first term of the class in the order above. |
| Equations | For each class, one `(= member representative)` per non-representative member. Members are **all** syntactic terms within the bound, including those whose sub-terms are not representatives. |
| Filters | None. Instances of other equations are kept. |
| Expected counts | Terms 77 / 74 / 52 / 52; classes 11 / 24 / 17 / 16; equations 66 / 50 / 35 / 36 = 187 lines, 156 distinct. |
| Certification | Every equation true on all 3^n assignments of its space (v1 grade: `:exhaustive`, obligation `:equivalence`). |

**How to check equality mechanically.** Write one line per equation as `(= LHS RHS)` with lower-case operators,
variables `x0`, `x1`, `x2`, bare literals, and single spaces. Then either sort the 187 lines by byte order and
compare with `x1-equations.txt`, or prefix each line with the job name and a tab and compare as a set with
`x1-equations-by-job.txt`. If the new engine picks representatives by a different rule, the equations will differ
while the classes agree; in that case compare the partition instead: `x1-classes.txt` lists every member of every
class, and two engines agree when each class has the same set of members.

**For "plus distributivity"** the matching v1 run is one more space: x0, x1, x2; operators `+`, `*` in that order;
no literals; 27 rows; bound 34 body bits; run to exhaustion. Expected: 3,477 terms, 274 classes, 3,203 equations
(`x1-dist34.equations.txt`, `x1-dist34.classes.txt`), among them
`(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))`.

**Bounds free of the cut-off.** If the owner prefers a target that does not depend on v1's tariff, the natural
ones are the three-variable spaces at 24 bits (66 terms; 49 and 50 equations; with `obs1` and `obs2` that makes
215 lines, a superset of the 187) or at their declared 44 bits (3,873 terms; 3,847 and 3,848 equations). Both
are recorded (`x1-bound24-*`, `x1-exhausted-*`).

**The numbers to beat** are in the last table of §4.5, and the memory figures in §4.4: v1 keeps about 830 bytes
per tree at 27 rows, 2.85 MB for the 3,477 trees and 274 classes of the distributivity run, and 47.9 MB for
57,909 trees and 1,241 classes one size up.

---

## 7. What did not reproduce, and what I could not determine

**Everything in the plan and the audit that I re-measured reproduced exactly**: 187 proposed and 14 kept; the
per-job terms, classes, equations and work of `laws-library.md` §1.1; the cut-off of the two three-variable jobs;
and, from the distributivity table of `laws-library.md` §1.2 for GF(3), the 54 terms at the bootstrap's limit and
the 3,477 terms, 274 classes, 6,831,983 units and class of 12 at exhaustion. I did not re-run the row of that
table at a limit of 2,000,000, its GF(5) half, or the count of 16 equations that fail on the integers.

Points where the documents are imprecise rather than wrong:

1. `plan_v2c.md` §11.2 says "the same 187 equations … at the same bound". The 187 are not the equations of any
 bound for two of the four jobs (§1.9). The gate needs either the 52-term stopping rule or a different target.
2. The same sentence compares the new engine with "the v1 kernel's bucket engine" for the equations and with
 "the v1 kernel's enumerator" for the work, as if they were two things. They are one run (§1.1).
3. "At least 10× less work" has no stated unit. Under the ledger it is passed by any per-cell evaluator; counted
 like for like it cannot be passed at the bounds that give the 187 (§4.5).
4. `plan_v2c.md` §2.3 gives about 430 bytes per kept tree. In an observation job with 27 rows I measure about 830,
 because the job also stores each term's values (§4.4).
5. The audit's log prints a wall time of 0.000 s for the four jobs. That is clock resolution; they take 0.34 to
 1.04 ms each.

What I could not determine:

- **Which bound and which unit the owner intends for the 10× comparison.** I recorded every candidate instead.
- **Whether a real class engine reaches the estimate of §4.5.** The column counts come from a forty-line Python
model, not from a store with hash-consing, class tables and its own overheads. They describe the simplest
design and say nothing about wall time.
- **Retained bytes for a single small job to better than a few percent.** One job of 50 KB is below the
resolution of a garbage-collection reading; the figures are averages over 200 held copies.
- The second half of the gate, "measure what pruning by already-found laws would add on top of classes", has no
v1 baseline. v1 never prunes observation by laws; the enumerator "is a function of the language only"
[D: `plan_v2c_audit/reports/laws-library.md` §0, finding 4].

