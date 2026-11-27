## Short summary

**The file `REPORT.md` was not written.** The harness refused the write ("Subagents should return findings as text, not write report files"), and I did not work around it. The full report text is below, ready to be saved verbatim as `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/stageA/base-x2/REPORT.md`. Every data file, script and log it names does exist.

**The baseline in a few lines.**
- "Eight solvers" means `+ - * /` times two argument positions. The test fixture runs them on GF(5), GF(7) and the integers (grid −4..4), so the baseline has 24 rows. All 24 reproduce, byte-identical across repeated runs.
- GF(5) and GF(7) agree term for term. The integers give the same answer terms, with different guards for `*` and for the unknown divisor.
- Unknown divisor, `(/ k z) = c`: answer `(/ x0 x1)`. On fields the guard is `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) T NIL) NIL)`, certified. On the integers the innermost `T` becomes `(= x1 (/ x0 (/ x0 x1)))`, and the uniqueness law is refuted.
- Integer divisibility guard for `(* k z) = c`: `(if (if (= x0 0) NIL T) (= x1 (* x0 (/ x1 x0))) NIL)`. It is a forward replay with no `mod`, and equals "k ≠ 0 and k divides c" on all 1,681 pairs of [−20, 20]².
- Cost of the 24: 122,728,215 ledger units over every ledger (28,847,867 by the audit's narrower count, which matches its report to the unit), and about 1.8 s wall.

**Did not reproduce.**
- Plan §10 risk 2 says the present kernel cannot solve `a*x + b = c`. It can: `solve-equality-symbolically` returns `x = (/ (- c b) a)` with guard, certified over GF(5) and GF(7), and as a conjecture over the integers with the milestone-discovered rules. The kernel's own `tests/topology.lisp:57-70` already tests such a case. `x + x = c` is confirmed unsolved.
- Plan §8.5's "guard built from the table's uniqueness test and a forward replay" was not built by any mechanism. `r3-guard.lisp` (76 lines) hard-codes the guard term on line 12 and checks it by brute force. Its numbers reproduce exactly.

**Three things in the gate's wording need a decision before comparison.**
1. "From operator tables alone": the baseline's integer guards exist only because of "query rows" (every grid pair (k, c), on the table or not). With no query rows the milestone code itself loses divisibility.
2. The milestone guard is a replay (existence) guard only, with uniqueness as a separate law. The plan's §7.2 two-part guard would differ on the two integer division rows.
3. Text-for-text equality needs the kernel's connectives (nested `if`, no `and`/`not`) and its composition order; otherwise compare truth tables (provided in `x2-solvers.sexp`).

**Also worth knowing.**
- On GF(3), the field of X1, the milestone code returns different terms for 3 of the 8. On GF(11) and GF(13) it fails for `*` and `/`, because of a hard-coded 35-bit guard bound.
- The answer language at its 16-bit bound holds only one-operator terms. A conditional answer would win the selection rule if the language contained it.

**Could not be determined:** what the milestone code returns from an answer language containing conditionals at a bound large enough to hold them (beyond its 10⁸ work limit). Neither route to `x + x = c` was run.

**Process note:** one early patch to `x2-dump.lisp` was made with an inline heredoc before I caught the rule; the script on disk is the final version and no result depends on that command.

**Files** (all under `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/stageA/base-x2/`):
- `run-baseline.sh` — reproduces everything from a fresh copy in about 1 min 50 s. Helpers: `copy-v1.sh`, `run-tests.sh`, `run-one.sh`, `run-proto.sh`, `work-ranges.py`.
- `x2-solvers.txt` — one block per solver and domain (24 blocks).
- `x2-solvers.sexp` and `x2-solvers.reference.sexp` — machine-readable, with guard truth tables and answer values over the grid.
- `x2-match-table.tsv` — the comparison table.
- `x2-candidates.txt` — every enumerated answer term.
- Lisp scripts: `x2-common.lisp`, `x2-dump.lisp`, `x2-time.lisp`, `x2-semantics.lisp`, `x2-variants.lisp`, `x2-composite.lisp`, `x2-extras.lisp`, `x2-floor.lisp`, `x2-section.lisp`, `proto-table-check.lisp`.
- `logs/` — one log per step, plus `logs/run-baseline.out`.
- `source-sha256.txt`, `source-commit.txt`; `v1/` (private copy), `proto-copy/`.

The repository was not touched (`git status` unchanged).

---

## Full report text (save as `REPORT.md`)

# Baseline for gate X2 (reorientation: solvers and guards)

Recorded on 26 November 2026 from a private copy of `v1/` at commit `65d1df2` (the working tree of `v1/` is clean at that commit). Nothing under `/home/tlh24/lisploop` was written.

Every claim carries a tag. **[M]** means measured by a run made for this report, with the log named. **[C]** means read from code, with file and line. **[D]** means read from a document. File names without a directory are in this report's directory; `logs/` is its sub-directory. Kernel paths are relative to `v1/`.

Terms used throughout. The equation is `op(…) = c` with one argument unknown. The unknown is `z`. The other argument, which is known, is `k`. In the kernel's terms the known argument is variable `x0` and the result `c` is variable `x1`. "Unknown = argument 0" means the equation is `(op z k) = c`; "unknown = argument 1" means `(op k z) = c`. The kernel calls the answer term a *witness*.

## 1. Summary

1. **The eight solvers are four operators times two positions.** The milestone code inverts `+`, `-`, `*` and `/` in each of their two arguments. The test fixture runs all eight on three domains: GF(5), GF(7) and the integers. That is 24 discoveries, and all 24 reproduce, byte for byte across repeated runs **[M: `x2-solvers.sexp`, `logs/run-baseline.out`]**.
2. **GF(5) and GF(7) give the same eight answer terms and the same eight guards.** The integers give the same eight answer terms, and different guards for `*` (both positions) and for `/` with the divisor unknown **[M: `x2-match-table.tsv`]**.
3. **The guard is a replay guard, not a uniqueness guard.** The code composes it from three learned parts: where the answer term is defined, where the forward operator is defined on that answer, and whether the forward replay returns `c`. Uniqueness is tested afterwards as a separate law and is not part of the guard **[C: `milestones/algebra-discovery.lisp:343-371`, `:41-47`]**. On the integers the uniqueness law is refuted for both division solvers, and the solvers are kept all the same **[M]**.
4. **The integer divisibility guard and the integer form of the unknown-divisor guard come from rows that are not in the operator's table.** The milestone code adds one "query" row for every pair (k, c) of grid values, whether or not any `z` gives that `c`. Run with no query rows, it loses the divisibility condition and finds only `k ≠ 0` **[M: `logs/x2-variants.log`, section V3]**. Gate X2 says "from operator tables alone"; the baseline does not meet that wording itself.
5. **One statement of the plan does not reproduce.** Risk 2 of §10 says the present kernel cannot solve `a*x + b = c`. It can. `solve-equality-symbolically` returns `x = (/ (- c b) a)` with its guard, certified over GF(5) and GF(7), and as a conjecture over the integers when given the rules the milestone code discovers **[M: `logs/x2-composite.log`]**. The other composite case, `x + x = c`, is confirmed unsolved in all six configurations tried.
6. **Cost.** The 24 discoveries, with validation, take 122,728,215 ledger units counted over every ledger, or 28,847,867 counted the way the audit's empirical report counted them, and about 1.8 seconds of wall time (1.71 to 1.83 across runs) **[M: `x2-solvers.txt`, `logs/x2-time.log`]**.

## 2. The eight solvers

### 2.1 Which code, and how the eight are counted

The code is `milestones/algebra-discovery.lisp` (371 lines). The kernel never calls it: `milestones/load.lisp:2` says "The kernel (../load.lisp) never calls into milestones/" **[C]**. Its only callers are the tests in `tests/milestones/algebra.lisp` and the fixtures in `tests/milestones/support.lisp` **[C]**.

The count of eight is the fixture's loop, `arithmetic-controls` (`tests/milestones/support.lisp:198-208`): for each operator name in `(:+ :- :* :/)` it observes the operator once, and for each position 0 and 1 it discovers a solver **[C]**. The tests call this fixture for GF(5), GF(7) and `:int` (`tests/milestones/algebra.lisp:24`, `:58`, `:129`, `:206`) **[C]**. So "eight" is eight per domain, and the recorded baseline has 24 rows.

The eight answer terms are six distinct terms, because both positions of `+` give the same term and so do both positions of `*` **[M]**.

A second set of eight arithmetic solvers exists and must not be confused with this one. The bootstrap script builds `library/arithmetic.sexp` from hand-written spec rows (`bootstrap/build-batteries.lisp:188-248`), and that file holds entries `:solve-+-0` to `:solve-/-1` **[C]**. Their answer terms are the same as the milestone code's. Their guards are not: the library has `(if (= x0 0) NIL T)` for `*` on the integers, with no divisibility condition, and `(if (= (* x0 x1) 0) NIL T)` for the unknown divisor **[C: `library/arithmetic.sexp:72-125`; M: `logs/x2-composite.log`, the rule listing]**. Gate X2 names the milestone code, so this report's baseline is the milestone code's output.

The kernel has no operator called `div`, `neg`, `max` or `min`. Its arithmetic primitives are `:+ :* :- :/ :mod :<`, with `:=` and `:if` (`ast.lisp:117-145`) **[C]**. On the integers `:/` is integer division. The plan and the prototype write `div`; the kernel's term is `(/ a b)`.

### 2.2 What is found

GF(5) and GF(7), identical term for term **[M: `x2-match-table.tsv`; the dump prints "GF(5) and GF(7) disagree on 0 of 8 solvers"]**:

| Operator | Unknown | Equation | Answer term | Guard | Guard true on (GF(5), GF(7)) |
|:--|:--|:--|:--|:--|:--|
| `+` | arg 0 | `(+ z k) = c` | `(- x1 x0)` | `T` | 25 of 25, 49 of 49 |
| `+` | arg 1 | `(+ k z) = c` | `(- x1 x0)` | `T` | 25, 49 |
| `-` | arg 0 | `(- z k) = c` | `(+ x0 x1)` | `T` | 25, 49 |
| `-` | arg 1 | `(- k z) = c` | `(- x0 x1)` | `T` | 25, 49 |
| `*` | arg 0 | `(* z k) = c` | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) T NIL)` | 20, 42 |
| `*` | arg 1 | `(* k z) = c` | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) T NIL)` | 20, 42 |
| `/` | arg 0 | `(/ z k) = c` | `(* x0 x1)` | `(if (if (= x0 0) NIL T) T NIL)` | 20, 42 |
| `/` | arg 1 | `(/ k z) = c` | `(/ x0 x1)` | `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) T NIL) NIL)` | 16, 36 |

All 16 field solvers are certified: both laws of §2.4 are validated exhaustively **[M]**.

Integers, grid −4..4 **[M: `x2-match-table.tsv`]**:

| Operator | Unknown | Answer term | Guard | Guard true on the 81 grid pairs | Witness law | Uniqueness law |
|:--|:--|:--|:--|--:|:--|:--|
| `+` | arg 0 | `(- x1 x0)` | `T` | 81 | conjecture, sampled | conjecture, sampled |
| `+` | arg 1 | `(- x1 x0)` | `T` | 81 | conjecture, sampled | conjecture, sampled |
| `-` | arg 0 | `(+ x0 x1)` | `T` | 81 | conjecture, sampled | conjecture, sampled |
| `-` | arg 1 | `(- x0 x1)` | `T` | 81 | conjecture, sampled | conjecture, sampled |
| `*` | arg 0 | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) (= x1 (* (/ x1 x0) x0)) NIL)` | 40 | conjecture, sampled | conjecture, sampled |
| `*` | arg 1 | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) (= x1 (* x0 (/ x1 x0))) NIL)` | 40 | conjecture, sampled | conjecture, sampled |
| `/` | arg 0 | `(* x0 x1)` | `(if (if (= x0 0) NIL T) T NIL)` | 72 | conjecture, sampled | **refuted**, at (k c z) = (−3 1 −4) |
| `/` | arg 1 | `(/ x0 x1)` | `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) (= x1 (/ x0 (/ x0 x1))) NIL) NIL)` | 32 | conjecture, sampled | **refuted**, at (k c z) = (−4 1 −3) |

No integer solver is certified **[M]**.

`x2-solvers.txt` gives, for each of the 24, the kernel's own serialisation of both terms (the output of `ast->sexp`), the three learned parts of the guard, the guard's truth table over the grid, the top of the ranking of answer terms, both laws as terms, and the work.

### 2.3 How each is found

The procedure is the same for all 24 **[C: `milestones/algebra-discovery.lisp`, lines as given]**.

1. *Observe the operator* (`observe-arithmetic-relation`, `:259-274`). `(op x0 x1)` is run on every pair of grid values, and an error counts as an outcome. A Boolean program is then fitted to the rows where it returned a value; this is the operator's *forward definedness guard*. It is `T` for `+`, `-` and `*`, and `(if (= x1 0) NIL T)` for `/` **[M]**.
2. *Build the solver's rows* (`orient-arithmetic-requirements`, `:276-292`). There is one row for each forward observation, with (k, c) as its known values, and one further row for each pair (k, c) of grid values, called a query row. The row's requirement is a predicate on the unknown: "`op` is defined here and returns `c`" (`:25-32`). Fibers are not solved at this step.
3. *Enumerate the answer language* (`:305-308`). Every term over `x0`, `x1`, the literals, and the operators `+ - * /`, up to 16 bits of body, is run on every row.
4. *Score and select* (`:309-336`). Each term is scored by the number of rows on which the row's predicate holds of the term's value. The term with the most rows wins. A tie is broken by the smaller description, and then by enumeration order. The winner's set of rows is the *support*.
5. *Learn the guard* (`learn-solver-guard`, `:343-371`). §4.2 gives the rule.
6. *Validate* (`validate-arithmetic-solver`, `:49-71`). §2.4.

The margin of the winner over the runner-up is wide in every case. On the integers, for `*` the winner satisfies 112 of 162 rows and the next term 58; for the unknown divisor it is 72 of 153 against 40 **[M: `x2-solvers.txt`, "top of ranking"]**. In two cases two terms share the winning support exactly and differ only in the order of the arguments of a commutative operator: `(+ x0 x1)` and `(+ x1 x0)` for `-` with argument 0 unknown, and `(* x0 x1)` and `(* x1 x0)` for `/` with argument 0 unknown. Enumeration order decides, and it lists `x0` first **[M]**.

### 2.4 How the result is recorded and certified: "a solver is two laws"

The discovery is a host structure, `solve-discovery` (`:8-9`), holding the relation, the position, the rows, the answer term, the guard, a ledger, and two validations **[C]**. Two laws are built from it **[C: `:34-47`]**:

- the **witness law**: under the guard, the row predicate holds of the answer term. For `(* k z) = c` on a field it prints as `(if G (= (= (* x0 (/ x1 x0)) x1) T) T)`.
- the **uniqueness law**: under the guard, the row predicate holds of a third variable `x2` exactly when `x2` equals the answer term. The code's comment says it "validates the WHOLE fiber, not just a witness" (`:42`).

On a field both laws are checked on every assignment: p² for the witness law and p³ for the uniqueness law, so 25 and 125 on GF(5), and 49 and 343 on GF(7) **[M]**. `certified-solve-discovery-p` (`:73-80`) is true when the forward grid was the whole field and both laws are validated with a certificate that still matches the law's text **[C]**. On the integers the laws can only be sampled. The fixture samples the witness law on 53 to 79 pairs and the uniqueness law on 1,419 to 1,507 triples, built from the grid and from seven held-out values (−2⁶⁴, −17, −1, 0, 1, 17, 2⁶⁴) (`tests/milestones/support.lisp:123-145`) **[C, M]**.

The evidence grades are those of `evidence.lisp:62-73`: `:exhaustive`, `:derived` and `:trusted-axiom` count as current evidence, and `:sampled` records only that a test was made **[C]**.

A discovery becomes a library-style record only through `prepare-propagator-library` (`:109-125`), which builds a `:solver` entry "of no library" with `make-knowledge-solver` (`laws.lisp:1184-1238`) **[C]**. What it records **[M: `x2-solvers.txt`, "recorded as"]**:

| Domain | Solvers | Entry status | Certificate | `unique-p` |
|:--|:--|:--|:--|:--|
| GF(5), GF(7) | all eight | `:validated` | `:exhaustive (:witness :uniqueness)` | T |
| integers | `+`, `-`, `*` | `:conjecture` | `:derived (:uniqueness)` | T |
| integers | `/`, both positions | `:conjecture` | none | NIL |

The middle row repeats a point the audit already made: an integer solver's uniqueness is attested with the grade `:derived`, which counts as current evidence, on the strength of a law that was only sampled (`:122-124`) **[C; D: `plan_v2c_audit/reports/laws-library.md`, line 293]**.

The solver schema that §9 of the plan lists for carrying over ("Solver schema and fiber certification, `laws.lisp`, 186 lines") is `laws.lisp:1059-1244` **[C]**. It is the other route to a certificate: `certify-solver-entry` (`:1112-1182`) checks every fiber of a finite type directly, up to 65,536 checks (`:1136`), for three obligations, `:witness`, `:uniqueness` and `:necessity` **[C]**. The milestone code does not use it; it passes its own two validated laws as attestation (`:attested-p`, `algebra-discovery.lisp:101`) **[C]**.

## 3. What the milestone code is given

Gate X2 allows "no spec rows, and no language for the answer terms beyond the operators in scope". These are all the inputs the milestone code receives. The last column is my reading of each against the gate.

| Input | Value in the baseline | Where set | Reading against X2 |
|:--|:--|:--|:--|
| Spec rows | none | — | The baseline already has none **[C]**. |
| The operator to invert, and the position | one of `+ - * /`, position 0 or 1 | fixture, `support.lisp:203-205` | Presumably allowed: it names the question. |
| The forward grid | the whole field; −4..4 on the integers | fixture, `support.lisp:201-202` | A choice. §7 shows what depends on it. |
| The query grid | the same values, giving every pair (k, c) | argument `query-values`, `algebra-discovery.lisp:298`, used at `:284-286` | **This goes beyond "operator tables alone".** See §4.2. |
| Operators of the answer language | `(:+ :- :* :/)` | a default argument, `:299` | **A whitelist.** It leaves out `mod`, `<`, `=` and `if`. |
| Literals of the answer language | every field element; `(-1 0 1)` on the integers | fixture, `support.lisp:206`; default `:all`, `:299` | A choice. It changes nothing (§7). |
| Size bound of the answer language | 16 bits of body | default, `:300` | A choice with a large effect: at 16 bits no term has more than one operator **[M: `x2-candidates.txt`]**. |
| The guard language | operators `=` and `if`, the literal `0`, the variables, `T` and `NIL`; 35 bits of body | **hard-coded**, `:230-238` | **A supplied language of guards.** |
| The shape of the guard | `(if D (if F E NIL) NIL)`, three learned parts in a fixed frame | **hard-coded**, `:365-367` | A hand-written schema, though a general one. |
| The selection rule | most rows, then smallest | hard-coded, `:323-328` | A rule the new engine must also fix. |
| Work limits | 10⁸ per job (`laws.lisp:429`), 10⁷ to observe the operator (`:259`) | defaults | — |
| Integer validation samples | seven held-out values, and `z` in −4..4 | fixture, `support.lisp:126`, `:139` | They affect only the grade. |

The answer language, as enumerated, is 203 terms on GF(5), 333 on GF(7), and 89 on the integers: two variables, the literals, and one-operator terms only **[M: `x2-candidates.txt`, `logs/x2-extras.log`]**. So the audit's remark that the solver search "has a one-operator answer" in every case (plan §10, risk 2) is also a property of the language: at the default bound nothing larger can be proposed.

**No hand-set flag is on the milestone path.** The flag the audit describes ("arithmetic solvers for `*` and `/` carry no certificate, only a hand-set flag") is `:finite-unique-p t`, and it belongs to the bootstrap path: it is written at `bootstrap/build-batteries.lisp:219, 225, 231, 238`, stored in `library/arithmetic.sexp` at lines 84, 97, 110 and 125 beside `:CERTIFICATE NIL`, and read at `templates.lisp:446` and `consolidate.lisp:1766` **[C]**. On the milestone path `unique-p` and `attested-p` are computed from the two validations (`algebra-discovery.lisp:88-107`) **[C]**.

**Operators in scope, if only the arithmetic primitives are available** **[C: `ast.lisp:117-145`]**. On the integers: `+`, `*`, `-`, `/`, `mod` (integers to integer), `<` (integers to Boolean), `=` (any type to Boolean), and `if`. On a prime field: `+`, `*`, `-`, `/`, `=`, and `if`. `mod` is rejected on a field **[M: `logs/x2-semantics.log`, A2]**, and `<` is declared for integers only (`ast.lisp:143`). There is no `not`, `and` or `or`: the kernel writes `(if g NIL T)` for negation and nests `if` for conjunction, which is why every guard above has that form.

## 4. The two hard cases

### 4.1 The unknown-divisor solver

**Equation:** `(/ k z) = c`, where `k` is the dividend (`x0`), `c` is the quotient (`x1`), and the divisor `z` is unknown.

**On GF(5) and GF(7)** **[M: `x2-solvers.txt`]**. The answer term is `(/ x0 x1)`, that is z = k / c. The guard is `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) T NIL) NIL)`, that is c ≠ 0 and k / c ≠ 0. It holds on 16 of 25 pairs and on 36 of 49, which are exactly the pairs with k ≠ 0 and c ≠ 0. Both laws are validated exhaustively and the solver is certified. By brute force, wherever the guard holds exactly one `z` solves the equation, and where it fails there is either no solution or, at k = c = 0, several **[M: `logs/x2-semantics.log`, part B]**.

**On the integers, grid −4..4** **[M]**. The answer term is the same, `(/ x0 x1)`, with truncating division. The guard gains a third condition, the forward replay: `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) (= x1 (/ x0 (/ x0 x1))) NIL) NIL)`. It holds on 32 of the 81 grid pairs. The witness law is a sampled conjecture (53 samples, 28 under the guard). The uniqueness law is refuted: at k = −4, c = 1 the answer term gives z = −4, and z = −3 solves the equation too. The solver is kept as a conjecture with `unique-p` NIL and no certificate.

What this guard means was measured over all 1,681 pairs (k, c) in [−20, 20]² against a brute-force count of the solutions **[M: `logs/x2-semantics.log`, part B]**. The guard holds on 392 pairs: 260 of them have exactly one solution and 132 have several. It fails on 1,289 pairs: 1,248 have no solution and 41 have many, and those 41 are the pairs with c = 0. It never fails on a pair that has exactly one solution, and the answer term is a correct solution on every pair where the guard holds. So the guard says "c ≠ 0 and a solution exists". It does not say the solution is unique.

### 4.2 The integer divisibility guard

**The exact terms** **[M]**:

- unknown first factor, `(* z k) = c`: `(if (if (= x0 0) NIL T) (= x1 (* (/ x1 x0) x0)) NIL)`
- unknown second factor, `(* k z) = c`: `(if (if (= x0 0) NIL T) (= x1 (* x0 (/ x1 x0))) NIL)`

They differ only in the order of the two arguments of `*`, which follows the position of the unknown. In words: k ≠ 0, and c equals k times the truncated quotient c / k. There is no `mod` in it. Over [−20, 20]² the guard differs from "k ≠ 0 and k divides c" on 0 of 1,681 pairs. It holds on 304 pairs, each with exactly one solution, and fails on 1,377: 1,376 with no solution and one, k = c = 0, with many **[M: `logs/x2-semantics.log`, part B]**. The same guard is tested in `tests/milestones/algebra.lisp:144-149`, with values near 2¹²⁸ **[C]**.

**Where it comes from in the code** **[C: `milestones/algebra-discovery.lisp:343-371`]**. The guard is composed as

  guard = LC(D, LC(F, E, NIL), NIL)

where `LC(g, yes, no)` is `yes` when `g` is the literal `T`, `no` when it is the literal `NIL`, and `(if g yes no)` otherwise (`:15-19`). The three parts are:

- **D**, where the answer term is defined. The smallest Boolean program over `x0`, `x1`, `0`, `=` and `if` that is true on exactly the rows where the answer term returned a value (`:348-349`).
- **F**, the operator's forward definedness guard from step 1 of §2.3, with the known argument and the answer term put in the operator's two places (`:21-23`, `:366`).
- **E**, the replay. The answer term is put in the unknown's place and the operator is run forward on every row (`:351-354`). On the rows where that returns a value, a Boolean program over `x0`, `x1` and a third variable `x2` holding the replayed value is fitted to "the replayed value equals c" (`:355-362`). Then `x2` is replaced by the replay term itself (`:363-364`).

Finally the composed guard is checked against the support on every row (`:369-370`).

For `*` on the integers the three parts are `(if (= x0 0) NIL T)`, `T`, and `(= x1 x2)` **[M: `x2-solvers.txt`, "learned parts"]**. The replay is defined on 144 of the 162 rows and equals `c` on 112 of them, so the fitted program is the equality and not the constant `T`. On a field the replay equals `c` on every row where it is defined, the fitted program is `T`, and the guard is `(if D T NIL)`.

**The divisibility condition exists only because of the query rows.** Every forward row has c = k·z, so the replay equals `c` on all of them. With `query-values` set to none, the same code returns `(if (if (= x0 0) NIL T) T NIL)` for `*` on the integers, the guard it finds on a field **[M: `logs/x2-variants.log`, V3]**. The same run loses the replay condition of the unknown-divisor guard. On GF(5) and GF(7) it also changes the first condition of the unknown-divisor guard from `(= x1 0)` to `(= x0 0)`: the two agree on every row of the operator's table and differ off it **[M: same log]**. This is the plan's sentence "every row of a product table is divisible, so the table alone cannot show it" (§8.2), confirmed on the kernel's own code.

### 4.3 Why the prototype found neither

The prototype's experiment C is `fd-probe` in `plan_v2c_audit/proto/tg-probe.lisp:675-707`. Re-run from a copy, it reproduces the repository's log exactly, apart from the timing column **[M: `logs/proto-c.log`, `logs/proto-c.diff` (empty)]**. Four things in its code explain the two gaps **[C]**.

1. *Its rows are the operator's table and nothing else* (`:682-688`). Each row is (unknown argument, other argument, `c`), with `c` computed forward, and rows that give an error are dropped. A pair (b, c) for which no `a` exists is never a row.
2. *It asks a different question* (`:693-706`). Its mask marks the rows on which the unknown argument is the only value in its group, which is uniqueness. The guard it seeks is a Boolean class equal to that mask on every row, and the inverse it seeks is a term equal to the unknown wherever the mask holds. Existence is never tested, because on a table every row exists.
3. *Its `div` floors* (`:205`), where the kernel's `/` truncates.
4. *Its leaves are the other argument, `c`, 0 and 1, and its terms have at most 9 nodes, within 300,000 candidates* (`:698-700`, `:707`, `:709`).

*For the divisibility guard*, point 1 is enough. On the 169 rows of the prototype's table for c = a·b, the condition `(= (* (div c b) b) c)` is true on all 156 rows with b ≠ 0, false on none, and an error on the 13 rows with b = 0. It therefore agrees with `(not (= b 0))` on all 169 rows, and `(not (= b 0))` is smaller **[M: `logs/proto-table-check.log`]**.

*For the unknown divisor*, points 2 and 3 combine. Under the prototype's floor division `b` is determined by (a, c) on 38 of 156 rows, which is the 24.4% of its log. On 3 of those 38 rows the natural answer `a div c` is not `b`, for example at a = −5, b = −2, c = 2, where it gives −3. So the prototype's goal for an inverse is not met by that term, and its mask of 38 rows has no small Boolean description. Under the kernel's truncating division the same table has 44 rows on which `b` is determined, and `a div c` equals `b` on all 44 **[M: `logs/proto-table-check.log`]**. That second figure is a what-if in host arithmetic on the prototype's grid, not a run of the prototype. It suggests that with truncating division the prototype's own goal for the inverse would be met by a three-node term. The guard is another matter: the milestone code gets its guard by replay, and never fits a uniqueness mask.

### 4.4 The plan's remedy, checked against `plan_v2c_audit/verify-review/`

The plan's row reads "Inverse guard for `c = a·b`: the guard built from the table's uniqueness test and a forward replay of the answer is exact on all 1,681 pairs in [−20, 20]²" (§8.5).

**What was built** **[C: `plan_v2c_audit/verify-review/r3-guard.lisp`; D: `plan_v2c_audit/reports/verify-review.md`, section 3]**. A script of 76 lines; the part for multiplication, `r3-mul`, is lines 8 to 45. It contains no search and no kernel code. The report says so: "No kernel code; the unmodified probe is loaded only for its `ev`". The guard term is written by hand on line 12, `(and (not (= b 0)) (= (* (div c b) b) c))`, and its truth is computed in host code on line 20. For each (b, c) the script counts by brute force the integers `a` with a·b = c and compares. Re-run from a copy, it reproduces the repository's log byte for byte **[M: `logs/proto-r3.log`, `logs/proto-r3.diff` (empty)]**.

**What it shows** **[M: the same log]**. The hand-written guard has no false positive and no false negative on the 1,681 pairs, under both floor and truncating division: 304 pairs have exactly one `a`, 1,376 have none, and one has many. `(not (= b 0))` alone has 1,336 false positives. In the prototype's own evaluator the term is an error, not false, on the 41 pairs with b = 0, because its `and` is strict.

**What it does not show.** Nothing was built that derives the guard from a table. The "23 lines" that §8.5 mentions are the review's modifications to the prototype for the spec-row and aggregate experiments ("23 lines in six marked places", `plan_v2c_audit/README.md:11`), not for this **[D]**. So the row is a check that a given term is right. It is not a measurement of a mechanism that produces the term.

**The guard it yields against the milestone code's.** The two are the same predicate: both equal "k ≠ 0 and k divides c" on all 1,681 pairs **[M: `logs/proto-r3.log` and `logs/x2-semantics.log`]**. They are not the same term. The kernel has no `and` and no `not`, so its guard is a nested `if`. The kernel's equality has `c` on the left. The order of the arguments of `*` follows the position of the unknown. And the kernel's guard is `NIL` at k = 0 where the prototype's is an error. A comparison "up to renaming of variables" will not make these equal; §9 says what to do about it.

## 5. Reproduction

`bash run-baseline.sh` makes a fresh copy of `v1/`, runs everything below, and takes about 1 minute 50 seconds **[M: `logs/run-baseline.out`]**. Its last step compares the fresh `x2-solvers.sexp` with `x2-solvers.reference.sexp`; repeated runs were byte-identical **[M]**.

| Step | Script | Output |
|:--|:--|:--|
| Copy `v1/` (sources and the tracked `library/`) | `copy-v1.sh` | `v1/`, `source-sha256.txt`, `source-commit.txt` |
| The test suites `algebra`, `guards`, `propagation`, `topology` | `run-tests.sh` | `logs/test-*.log` |
| The 24 solvers | `x2-dump.lisp` | `x2-solvers.txt`, `x2-solvers.sexp`, `x2-match-table.tsv` |
| Work ranges per solver | `work-ranges.py` | `logs/work-ranges.log` |
| Wall time, uninstrumented | `x2-time.lisp` | `logs/x2-time.log` |
| Primitive semantics; meaning of each guard | `x2-semantics.lisp` | `logs/x2-semantics.log` |
| One choice changed at a time | `x2-variants.lisp` | `logs/x2-variants.log` |
| The composite cases | `x2-composite.lisp` | `logs/x2-composite.log` |
| The enumerated language; guard sizes | `x2-extras.lisp` | `x2-candidates.txt`, `logs/x2-extras.log` |
| What-if: floor division | `x2-floor.lisp` | `logs/x2-floor.log` |
| Would a conditional answer win the selection? | `x2-section.lisp` | `logs/x2-section.log` |
| The prototype's experiment C and the review's R3 | `run-proto.sh`, `proto-table-check.lisp` | `logs/proto-*.log` |

`x2-common.lisp` is shared. It loads the copy and wraps the kernel's `charge` function so that every unit charged to any ledger is added up. It changes no result. `x2-time.lisp` does not load it.

**The tests pass**: `algebra` has 8 tests and 27,871 checks, in 2.7 seconds **[M: `logs/test-algebra.log`]**. These are the counts the audit recorded **[D: `laws-library.md`, line 350]**.

**Work**, in ledger units **[M: `x2-solvers.txt`, the totals at its end; `x2-match-table.tsv` for each solver; `logs/work-ranges.log`]**. Two counts are given because the audit used the narrower one.

| Domain (8 solvers) | Every ledger: observe, discover, learn the guard, validate | The discovery's ledger and its enumeration ledger only |
|:--|--:|--:|
| GF(5) | 22,373,065 | 5,515,907 |
| GF(7) | 62,248,951 | 17,819,925 |
| integers | 38,106,199 | 5,512,035 |
| all 24 | 122,728,215 | 28,847,867 |

The narrow count equals, to the unit, the totals in the audit's empirical report **[D: `plan_v2c_audit/reports/empirical.md`, lines 437-439]**. The wide count is about four times larger because it includes the second pass that scores every term on every row, the three guard searches, and validation, whose ledgers the discovery does not keep. Per solver, discovery plus validation is 2.3 to 3.1 million units on GF(5), 6.6 to 8.9 million on GF(7), and 3.3 to 5.3 million on the integers. Observing an operator adds 0.04 to 0.64 million, once for its two positions. Most of the work is the category `evaluation` **[M]**.

**Wall time**, uninstrumented, five repetitions in one process **[M: `logs/x2-time.log`]**: 1.71 to 1.79 seconds for all 24 solvers with validation in the last run, and 1.71 to 1.83 across four such runs. By domain it is about 0.33 seconds for GF(5), 0.76 for GF(7), and 0.70 for the integers, so 40 to 100 milliseconds per solver. Loading the kernel takes about 2 seconds more.

## 6. Semantics a new engine must share

All of this was measured in the VM **[M: `logs/x2-semantics.log`, part A]** and agrees with the code **[C: `vm.lisp:209-221`]**.

- **Integer `(/ a b)` truncates toward zero.** It equals the host's `truncate` on all 3,660 pairs with b ≠ 0 in [−30, 30]², and differs from `floor` on 1,578 of them. So `(/ -7 2)` is −3 and `(/ 7 -2)` is −3. The code is `(truncate a b)` (`vm.lisp:219`).
- **Integer `(mod a b)` takes the sign of the divisor.** It is the host's `mod`: `(mod -7 2)` is 1 and `(mod 7 -2)` is −1. It differs from the host's `rem` (`vm.lisp:217-218`).
- **Division or `mod` by zero is an error, for every dividend, zero included.** Both are errors on all 61 pairs with b = 0.
- **Integers are unbounded.** `(/ 2^200 3)` and `2^200 * 2^200` are exact.
- **A prime field's values are 0 to p − 1.** −1 is not a value of GF(5). `+`, `-` and `*` reduce modulo p, so `(- 1 3)` is 3 in GF(5). `(/ a b)` is `a` times the reciprocal of `b`, found by the extended Euclidean algorithm (`vm.lisp:162-170`). `(/ a 0)` is an error, with the text "Division by zero". The full division tables of GF(5) and GF(7) are in the log.
- **An error is a status, not a value.** An evaluation ends with status `:value`, `:error` or `:unresolved`, or stays `:unknown` when its budget runs out (`vm.lisp:362-387`). On an error the value is `NIL` and the message is kept as text. The observation engine keeps one outcome for each row, `:value` or `:error`, and marks the whole expression `:error` if any row failed.
- **Every operator is strict; only `if` is lazy.** `(= (/ 5 0) (/ 5 0))` is an error, and so is `(* (/ 5 0) 0)`. `(if (= b 0) 0 (/ a b))` at b = 0 is 0, because `if` evaluates only the chosen branch (`vm.lisp:313-316`). An error in the condition is an error of the whole `if`. The guards depend on this: `(if (if (= x0 0) NIL T) (= x1 (* x0 (/ x1 x0))) NIL)` is `NIL` at x0 = 0, and not an error, only because the second branch is not evaluated.
- **`=` is structural equality of two values of one type, and `<` exists only on the integers.**

Does floor against truncate matter? As a what-if, the VM's integer division was made to floor, without editing the copy, and the four integer solvers for `*` and `/` were re-run. The same four answer terms and the same four guard terms came out. The meaning of one changed: the unknown-divisor guard, which under truncation never fails on a pair with exactly one solution, fails on 54 such pairs under floor **[M: `logs/x2-floor.log`]**. So the terms survive the difference between the two divisions, and the truth tables do not.

`v2/` has the same milestone code and fixture, byte for byte, and the same two lines of division semantics **[M: `cmp`; C: `v2/vm.lisp:246-247`]**.

## 7. Which results depend on choices

Each line is the milestone code re-run with one choice changed **[M: `logs/x2-variants.log`]**.

| Choice changed | Effect on the eight (answer term, guard) pairs |
|:--|:--|
| Integer literals: none, `(0 1)`, `(-1 0 1 2)`, all | none |
| Body bound of the answer language: 12, 14, 18, 20, 22, 24 on the integers; 12 to 22 on GF(5) | none |
| `mod` added to the answer language, at 16 and at 28 bits | none |
| Integer grid −3..3, −6..6, 0..4, or the irregular (−7 −3 0 2 5 11) | none |
| Integer grid −2..2 | the unknown-divisor guard loses its replay condition |
| Integer grid 1..5, with no zero and no negative number | 4 differ: both `*` guards lose `k ≠ 0`; the `/` argument-0 guard becomes `T`; the unknown divisor fails with an assertion |
| No query rows, integers | 3 differ: both `*` guards lose divisibility; the unknown-divisor guard loses its replay condition |
| No query rows, GF(5) or GF(7) | 1 differs: the unknown-divisor guard starts with `(= x0 0)` in place of `(= x1 0)` |
| Field GF(3) | 3 differ. `*` gets the answer `(* x0 x1)` with guard `(= x1 (* (* x0 x1) x0))`, and the unknown divisor gets `(* x0 x1)`. In GF(3) every non-zero element is its own reciprocal, so multiplying and dividing coincide off zero and the tie falls to `*`. |
| Field GF(2) | 7 differ |
| Field GF(11) or GF(13) | all four solvers for `*` and `/` fail with "Membership search unresolved". `(if (= x0 0) NIL T)` needs 38 bits there and the guard bound is fixed at 35 **[M: `logs/x2-extras.log`]**. `+` and `-` are unchanged. |
| Answer language without `/` | 3 differ: `*` gets `(* x0 x1)` with a replay guard; the unknown divisor gets `(* x0 x1)` |
| Answer language `+` and `*` only, bound 24 | 6 differ; `+` gets `(+ x1 (* x0 -1))`, as `tests/milestones/algebra.lisp:57-73` expects |

Three consequences for the gate.

- **The answer terms are robust; the guards depend on the rows.** No variant with `-` and `/` in the language, on GF(5), GF(7) or the integers, changed an answer term. The guards changed whenever the rows lacked a zero, lacked pairs off the operator's table, or covered too small a range.
- **GF(3), the field of gate X1, is not a domain on which this baseline holds.** On GF(3) the milestone code itself returns different terms for three of the eight.
- **The selection rule would not return the plain inverse from a richer language.** The rule takes the term that satisfies the most rows. A conditional such as `(if (= x0 0) 0 (/ x1 x0))` satisfies 122 rows of the integer `*` frame where `(/ x1 x0)` satisfies 112, and 46 against 40 on GF(5); the same holds for the unknown divisor (81 or 97 rows against 72 on the integers) **[M: `logs/x2-section.log`]**. These conditionals take 36 to 54 bits of body, so the 16-bit bound keeps them out. Whether the milestone code would in fact return one at such a bound could not be run: enumerating to 36 bits is beyond its 10⁸ work limit, which the audit met at 26 to 30 bits **[D: `empirical.md`, lines 453-461]**. A new engine that searches all operators in scope, `if` and `=` among them, needs a selection rule that still prefers the plain inverse. The prototype had one: it kept "inverse" and "section" as separate goals.

## 8. The composite cases

The kernel has one mechanism that composes inverses through a term: `solve-equality-symbolically` (`laws.lisp:809-887`). At each level the expression must be an operator applied to arguments of which exactly one contains the unknown. A solver rule for that operator and position, with evidence of uniqueness of any grade, rewrites `(= (op K T) c)` to `(= T q(K, c))`, with the rule's answer term and guard written over the expressions `K` and `c` **[C]**. Its only callers are `orient-conserved-quantity` and the tests `tests/topology.lisp` and `tests/audit.lisp`; no kernel path reaches it **[C: a search of `v1/` for both names]**.

It was asked five equations, on three domains, with two sets of rules: the bootstrap library's eight solvers and the eight the milestone code discovers. Each closed form returned was checked by brute force **[M: `logs/x2-composite.log`]**.

| Equation, solved for `x` | GF(5), GF(7), either rule set | Integers, bootstrap library's rules | Integers, milestone code's rules |
|:--|:--|:--|:--|
| `a*x + b = c` | **solved**: `x = (/ (- c b) a)`, guard `a ≠ 0`, certified | not solved | **solved**: `x = (/ (- c b) a)`, guard `a ≠ 0` and `(- c b) = a * ((- c b) / a)`, not certified |
| `b + x*a = c` | solved, the same | not solved | solved, the same |
| `x + x = c` | not solved | not solved | not solved |
| `x * x = c` | not solved | not solved | not solved |
| `a*x + x = c` | not solved | not solved | not solved |

**`x + x = c`: confirmed.** The kernel does not solve it, on any domain, with either rule set. The same is asserted in `tests/topology.lisp:47` **[C]**.

**`a*x + b = c`: the plan's statement does not reproduce.** Over GF(5) the closed form is right on all 100 assignments of (a, b, c) on which the guard holds, and over GF(7) on all 294. The guard fails where a solution exists only on the 5 and the 7 assignments with a = 0 and b = c, where every `x` is a solution. Over the integers with the milestone code's rules it is right on all 340 of the 729 assignments in [−4, 4]³ on which the guard holds, and it is returned as a conjecture to be replayed. The kernel's own test suite already contains this case: `tests/topology.lisp:57-70` solves `x*y + x = 3` for `y` over GF(5) and checks that the result is certified, and that test passes **[C; M: `logs/test-topology.log`]**. With the bootstrap library's rules on the integers it is not solved, because the library's `*` solver carries no evidence of uniqueness (§3). What is true of the present kernel is narrower than the plan says: the *discovery* code cannot pose a composite equation, because it takes one binary operator with one known argument (`arithmetic-application`, `algebra-discovery.lisp:11-13`) **[C]**; and no kernel path calls the code that composes.

**What composing known inverses through a term needs.** For an unknown that occurs once, as in `a*x + b = c`, it needs what `solve-equality-symbolically` has. Solver entries are indexed by operator and position, each with an answer term and a guard over (k, c). The walk goes from the root of the term toward the unknown, and at each operator it substitutes the sibling expression for `k` and the current right-hand side for `c`, takes the answer term as the new right-hand side, and collects the guard instance. The guards are kept in order, outermost first, because an inner one may be undefined where an outer one fails. The grade of the result is the weakest grade used, and a result that is not certified is replayed on the rows. X2's output, a table of (operator, position, answer term, guard), is exactly that function's input. For an unknown that occurs more than once, as in `x + x = c`, the walk has no single branch to follow, and one of two further things is needed. The first is a rewrite by laws that gathers the occurrences. `x + x = (1 + 1) * x` uses the identity of `*` and distributivity, which X1 is to supply; the `*` solver then gives `x = c / 2`, with a guard that is false in GF(2) and is divisibility by 2 on the integers. The second is to treat the whole term `(+ x x)` as one new unary operator, tabulate it, and run the same table-based discovery on it. With the milestone code's integer literals (−1, 0, 1) and its 16-bit bound the answer `(/ c 2)` is not in the language, so that route also needs either the literal 2 or a two-operator term. This paragraph is inference from the code and from the runs above; no run of either route was made.

## 9. What a new engine must match

Variables: `x0` is the known argument and `x1` is the result. The machine-readable form of this table is `x2-match-table.tsv` (answer term and guard as text) and `x2-solvers.sexp` (the kernel's serialisation of both terms, the guard's truth table over the grid as `:guard-on-grid`, and the answer term's values over the grid as `:answer-on-grid`).

| # | Operator | Unknown | Domain | Answer term | Guard |
|--:|:--|:--|:--|:--|:--|
| 1 | `+` | arg 0 | GF(5), GF(7), integers | `(- x1 x0)` | `T` |
| 2 | `+` | arg 1 | GF(5), GF(7), integers | `(- x1 x0)` | `T` |
| 3 | `-` | arg 0 | GF(5), GF(7), integers | `(+ x0 x1)` | `T` |
| 4 | `-` | arg 1 | GF(5), GF(7), integers | `(- x0 x1)` | `T` |
| 5 | `*` | arg 0 | GF(5), GF(7) | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) T NIL)` |
| 5i | `*` | arg 0 | integers | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) (= x1 (* (/ x1 x0) x0)) NIL)` |
| 6 | `*` | arg 1 | GF(5), GF(7) | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) T NIL)` |
| 6i | `*` | arg 1 | integers | `(/ x1 x0)` | `(if (if (= x0 0) NIL T) (= x1 (* x0 (/ x1 x0))) NIL)` |
| 7 | `/` | arg 0 | GF(5), GF(7), integers | `(* x0 x1)` | `(if (if (= x0 0) NIL T) T NIL)` |
| 8 | `/` | arg 1 | GF(5), GF(7) | `(/ x0 x1)` | `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) T NIL) NIL)` |
| 8i | `/` | arg 1 | integers | `(/ x0 x1)` | `(if (if (= x1 0) NIL T) (if (if (= (/ x0 x1) 0) NIL T) (= x1 (/ x0 (/ x0 x1))) NIL) NIL)` |

Evidence to match. On GF(5) and GF(7), all eight have both laws validated exhaustively and are certified. On the integers, rows 1 to 6i have both laws as sampled conjectures. Rows 7 and 8i on the integers have the witness law as a sampled conjecture and the uniqueness law **refuted**.

**Which rows are certain.**

- *The answer-term column is certain* on GF(5), GF(7) and the integers. It did not change under any variation of grid, query rows, literals, or bound, nor when `mod` was added (§7). It depends on three things: `-` and `/` being in the answer language; no conditional being in it, or else a selection rule that prefers the plain inverse (§7); and the field being neither GF(2) nor GF(3). Rows 3 and 7 are fixed only up to the order of the arguments of a commutative operator.
- *Guards of rows 1 to 4 are certain.* They are `T` in every variant.
- *Guards of rows 5, 6 and 7 are certain given a zero in the grid.* On a field the grid is the whole field, so they are certain there.
- *The guard of row 8 on a field depends on the query rows* for its first condition (§7).
- *The guards of rows 5i, 6i and 8i depend on the query rows and on the grid.* They need pairs (k, c) that are not in the operator's table, a zero in the grid, and a range of at least −3..3 or 0..4. With those they were the same on every grid tried.
- *The integer grades depend on the fixture's sample set.* The two refutations do not: each has a counterexample inside the grid.
- *The guard truth tables in `x2-solvers.sexp` depend on truncating integer division.* The terms do not (§6).

**Three points the gate's wording leaves open.** Each should be settled before the comparison is made.

1. **"From operator tables alone" against the query rows.** The baseline's integer guards for rows 5i, 6i and 8i cannot be found from the table (§4.2). A new engine can reach them by replaying each candidate answer on pairs (k, c) outside the table, which is what the plan's §7.2 proposes; then the set of such pairs is an input, and the baseline's is every pair of grid values.
2. **Which guard is "the same guard".** The milestone code's guard is the replay guard alone, and uniqueness is a separate law. The plan's §7.2 describes a guard with two parts, uniqueness read from the table and existence by replay. For rows 1 to 6i the two readings give the same predicate. For rows 7 and 8i on the integers they do not. The table's uniqueness test gives k = ±1 for the unknown dividend, which is what the prototype found, and an irregular mask for the unknown divisor; the milestone code's guards are `k ≠ 0` and "c ≠ 0 and a solution exists", and they hold on many pairs that have several solutions (1,558 of 1,640 and 132 of 392 in [−20, 20]²) **[M: `logs/x2-semantics.log`]**. To match the baseline on these two rows, a new engine must report the replay guard as the guard and report uniqueness separately, as refuted.
3. **Equality of terms.** The table can be matched text for text only by an engine that has the kernel's connectives (`if`, with no `and` or `not`), composes the guard in the kernel's order, puts `c` on the left of the replay equality, and orders the arguments of `*` by the unknown's position. If the new engine's Boolean vocabulary differs, the mechanical check that remains is extensional: the same truth table as `:guard-on-grid` and the same values as `:answer-on-grid` wherever the guard holds, with an error counted as distinct from false. On the integers the counts over [−20, 20]² in `logs/x2-semantics.log` give a second check (304 pairs for rows 5i and 6i, 1,640 for row 7, 392 for row 8i).

## 10. What did not reproduce, and what could not be determined

- **Did not reproduce:** the plan's statement (§10, risk 2) that the present kernel cannot solve `a*x + b = c`. See §8.
- **Reproduced with a qualification:** the plan's row "Inverse guard for `c = a·b` … built from the table's uniqueness test and a forward replay" (§8.5). The numbers reproduce exactly. The guard was written by hand in the checking script and was not built by any mechanism (§4.4).
- **Reproduced:** the audit's table of answer terms and guards (`laws-library.md`, lines 98-103), which omits the two rows for `-`; its candidate counts (203, 333, 89); the empirical report's work totals, to the unit; the test counts (8 tests, 27,871 checks); the prototype's experiment C; and the review's R3 log.
- **Could not be determined:** what the milestone code would return from an answer language that contains conditionals, at a bound large enough to hold them (§7). The selection rule says a conditional would win. The enumeration needed to confirm it is beyond the code's work limit.
- **Not run:** either route to `x + x = c` described in §8.