## Hand-back: baseline for gate X3 (the 16-spec ladder)

**One thing first.** `REPORT.md` was not written. The Write tool refuses report files from a subagent ("return findings as text"), and I did not work around it. The complete report is the text below under "REPORT"; save it verbatim as `REPORT.md` if you want it on disk. Every data file, script and log it names does exist.

Work directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/stageA/base-x3/`

### Short summary

- **Baseline.** The gate's regime is the harness's fourth, `:active-grammar-no-schemas`. Sound specs of 16, at 1, 10, 100 and 1000 times the default budget of 350,000 work units: **8, 10, 10, 10** judged on the harness's one hand-written input (the plan's "today 8–10" reproduces), and **7, 9, 9, 9** judged on the 200 held-out inputs of `verify-review/`.
- **Per spec.** Sound at the default budget: `copy`, `inc-all`, `dbl-all`, `sum-all`, `len-all`, `prd-all`, `filter`. Added at ten times: `positions`, `seq-corr`. Never found: `map-adjacent`, `scan`, `shift-seq`, `best-shift`. Impostors returned: `foldl` (81/200) and `last-or` (192/200) at every budget, `argmax-corr` (52/200) from 35,662,878 work units.
- **Everything in the plan about this ladder reproduces**: the harness's 16, 9, 9, 8; the clean-library recount's 16, 10, 11, 9; the `argmax-corr` commit error; the prototype's §8.5 table (logs identical). The thousand-fold figure, which the plan says was never measured on all sixteen in one run, now has been.
- **New findings, not in the plan.**
1. `last-or` is an impostor in the gate's regime; the harness's one input passes it.
2. The 200 inputs cannot tell a left fold from a right-end fold (`+`, `-`, `*` all satisfy f(f(a,x),y) = f(f(a,y),x)), so a wrong `foldl` scores 200/200 there. Each held-out procedure misses something the other catches.
3. The spec rows are trace-shaped: closed under the intended recursion for 14 of the 15 recursive specs. This conflicts with the gate's words "ordinary input/output rows" unless the rows are simply used as plain pairs.
4. The "full grammar" still carries author-written constants (`((0))` for `shift-seq`).
5. `shift-seq` and `best-shift`, not only `argmax-corr`, cannot be written in the full grammar as the library writes them (equivalents exist).
6. `best-shift`'s rows do not fix tie-breaking.
7. With a clean library per spec the ladder stays at 9 (one input) or 8 (200 inputs) at every budget, because `positions` is reached only through `inc-all`.
- **Not determined (needs the owner).** Which held-out procedure the gate intends; what "ordinary input/output rows" means if not these rows; how a claim of "underdetermined" is to be checked (it is defensible for `foldl`, `argmax-corr`, `best-shift` and `last-or`, so a kernel could approach 14 by declaring).
- **Not run.** Clean-library and complete-library arrangements at a thousand times the budget; the three other regimes above ten times the budget.

### Files written (all under the work directory above)

- `x3-specs.lisp` — the sixteen specs (107 rows), plain data
- `x3-heldout.lisp` — 200 held-out rows per spec, generators, oracle text
- `x3-prerequisites.lisp` — `map` and `foldr`
- `boot-specs.sexp`, `x3-row-analysis.sexp`, `results/*.sexp`, `logs/*` (`logs/tables.txt` holds the summary tables)
- scripts: `setup.sh`, `setup-boot.sh`, `run-stage0-unmodified.sh`, `run-boot.sh`, `run-heldout.sh`, `run-lisp.sh`, `run-harness.sh`, `run-all-harness.sh`, `run-prototype.sh`, `run-check-plain.sh`, `run-tabulate.sh`, `rerun-analysis.sh`, `compare-rerun.sh`, `finish.sh`; Lisp: `x3-common.lisp`, `x3-harness.lisp`, `heldout-dump.lisp`, `show-boot.lisp`, `analyze-rows.lisp`, `dump-specs.lisp`, `dump-prereqs.lisp`, `probe-primitives.lisp`, `check-plain-read.lisp`, `tabulate.lisp`

Two departures from the brief's rule 3, for the record: one small in-place patch of two scripts was made with an inline heredoc, and one comparison with a long one-liner. The patched scripts are kept in their final form, the comparison was redone from `run-prototype.sh`, and every output was regenerated from the kept scripts afterwards (`logs/rerun-analysis.txt`, `logs/compare-rerun.txt`). The repository is unchanged (`logs/repo-state-compare.txt`).

---

# REPORT

# Baseline for gate X3: the 16-spec ladder

This report records what the present kernel produces on the sixteen function specs of the bootstrap, so that a new kernel can be compared with it spec by spec. Nothing new was built. Every run was made in copies of `v2/` and of `plan_v2c_audit/verify-review/` inside the work directory. The repository was not written to: its HEAD and `git status` are the same before and after (`logs/repo-state-compare.txt`).

Each claim is tagged: **[M]** measured by a run made here (the log is named), **[C]** read from code (file and line), **[D]** read from a document. File names without a directory are in the work directory, `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/stageA/base-x3/`, and `logs/` and `results/` are its subdirectories. Environment: SBCL 2.6.4.debian, repository at commit `65d1df2`.

## 0. The baseline in brief

The gate names the regime "full grammar, no schemas". In the Stage 0 harness that is the fourth regime, `:active-grammar-no-schemas` **[C]** `v2/experiments/stage0-audit.lisp:175`.

| Budget per spec | Solved | Sound by the harness's one input | Sound on the 200 held-out inputs |
|:--|--:|--:|--:|
| 350,000 work units (the default) | 9 of 16 | **8** | **7** |
| 3,500,000 | 11 | **10** | **9** |
| 35,000,000 | 11 | **10** | **9** |
| 350,000,000 | 12 | **10** | **9** |

**[M]** `logs/harness-as-written-x1.log`, `logs/harness-as-written-x10.log`, `logs/harness-as-written-x100-active-grammar-no-schemas.log`, `logs/harness-as-written-x1000-active-grammar-no-schemas.log`; summary in `logs/tables.txt`, Table 1.

- The plan's "today 8–10" reproduces exactly when soundness is judged as the harness judges it, on one hand-written input per spec.
- Judged on the 200 held-out inputs that §8.5 of the plan uses for the prototype, the same runs give 7, 9, 9 and 9. The difference is one spec, `last-or`. In this regime the kernel returns a program that fits all seven rows, passes the harness's one input, and is right on only 192 of the 200. This impostor is not in the plan.
- The seven specs that are sound on both checks at the default budget are `copy`, `inc-all`, `dbl-all`, `sum-all`, `len-all`, `prd-all` and `filter`. At ten times the budget `positions` and `seq-corr` are added.
- `foldl` returns an impostor at every budget. `map-adjacent`, `scan`, `shift-seq` and `best-shift` are not found at any budget. `argmax-corr` is not found up to 35,000,000 work units, and at 35,662,878 the kernel returns an impostor for it.
- With a clean library for each spec, the count at the default budget is 9 by the one input (the recount in Appendix D of the plan) and 8 on the 200 inputs. It does not rise with budget, because `positions` is found only through the seed function `inc-all`, which a clean library does not hold.

What a new kernel is to be run on is in three data files: `x3-specs.lisp` (the sixteen specs), `x3-heldout.lisp` (200 held-out rows per spec) and `x3-prerequisites.lisp` (`map` and `foldr`). A forty-line interpreter that knows nothing of the kernel reproduces all 107 spec rows and all 3,200 held-out rows from the first two files **[M]** `logs/check-plain-read.log`.

## 1. The sixteen specs

### 1.1 Which they are

The bootstrap synthesizes exactly sixteen functions, in this order **[M]** `boot-specs.sexp`, written by the real bootstrap run in a copy with one function instrumented (`logs/bootstrap-instrumentation.diff`, `logs/bootstrap-instrumented.log`):

`copy`, `inc-all`, `dbl-all`, `sum-all`, `len-all`, `prd-all`, `foldl`, `filter`, `map-adjacent`, `positions`, `scan`, `shift-seq`, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`.

These are the sixteen names of the plan's §8.5 table. The plan lists them grouped by outcome; the order above is the order of the bootstrap and of the harness. The harness's own copy of each spec (rows, operators, literals, constants) is identical to what the bootstrap registers **[M]** `logs/show-boot.log`. The instrumented bootstrap regenerates all eight library files byte for byte **[M]** `logs/bootstrap-library-compare.txt`.

Where each spec lives **[C]** (`v1/bootstrap/build-batteries.lisp` and `v2/bootstrap/build-batteries.lisp` are identical files):

- The first six are the "seed corpus", `build-batteries.lisp:551-568`. They are synthesized in a scratch library, `:map` and `:foldr` are then derived from them by anti-unification (`:569-584`), and the six are discarded. Neither their specs nor their definitions are stored in any library file.
- `foldl`, `filter`, `map-adjacent`, `positions`: `:609-674`, stored in `v2/library/sequences.sexp`.
- `scan`: `:786-803`, stored in `v2/library/scans.sexp`.
- `shift-seq`, `seq-corr`, `best-shift`, `argmax-corr`, `last-or`: `:834-900`, stored in `v2/library/sequence-shift.sexp`.

The harness takes the ten stored specs from the library files and holds its own hand copy of the six seed specs **[C]** `stage0-audit.lisp:18-57`.

### 1.2 Parameters, rows, and definitions

Types are the kernel's: `:int`, `(:seq :int)`, `(:tuple :int :int)`, and a code type for a function argument (§1.3). "seq" below abbreviates `(:seq :int)`. The rows themselves, verbatim and in order, are in `x3-specs.lisp` under `:rows`; there are 107 in all.

| # | Spec | Parameters | Returns | Rows | Function or predicate argument, and its values in the rows |
|--:|:--|:--|:--|--:|:--|
| 1 | `copy` | x0 seq | seq | 4 | none |
| 2 | `inc-all` | x0 seq | seq | 4 | none |
| 3 | `dbl-all` | x0 seq | seq | 4 | none |
| 4 | `sum-all` | x0 seq | int | 4 | none |
| 5 | `len-all` | x0 seq | int | 4 | none |
| 6 | `prd-all` | x0 seq | int | 4 | none |
| 7 | `foldl` | x0 seq, x1 int, x2 binary code | int | 9 | x2 is `(- x0 x1)` in all 9 rows |
| 8 | `filter` | x0 seq, x1 predicate code | seq | 7 | x1 is `(< 0 x0)` in 4 rows and `(= (* (/ x0 2) 2) x0)` in 3 |
| 9 | `map-adjacent` | x0 seq, x1 binary code | seq | 8 | x1 is `(- x0 x1)` in 4 rows and `(+ x0 x1)` in 4 |
| 10 | `positions` | x0 seq, x1 int | seq | 11 | none |
| 11 | `scan` | x0 seq, x1 int, x2 binary code | seq | 9 | x2 is `(+ x0 x1)` in 6 rows and `(- x0 x1)` in 3 |
| 12 | `shift-seq` | x0 seq, x1 int | seq | 13 | none |
| 13 | `seq-corr` | x0 seq, x1 seq | int | 7 | none |
| 14 | `best-shift` | x0 seq, x1 seq, x2 int | (:tuple :int :int) | 9 | none |
| 15 | `argmax-corr` | x0 seq, x1 seq | int | 3 | none |
| 16 | `last-or` | x0 seq, x1 int | int | 7 | none |

**[M]** `logs/analyze-rows.log`, `x3-specs.lisp`.

The library's definitions, in readable form. `()` stands for the typed literal of the empty sequence; the exact typed form is in `x3-specs.lisp` under `:definition`. For the ten stored functions this is the `:EXPRESSION` of the library file. For the six seeds it is the program the bootstrap's seed synthesis returns **[M]** `boot-specs.sexp`, `logs/show-boot.log`.

```
copy          (if (= x0 ()) () (cons (at x0 0) (copy (tail x0))))
inc-all       (if (= x0 ()) x0 (cons (+ (at x0 0) 1) (inc-all (tail x0))))
dbl-all       (if (= x0 ()) x0 (cons (+ (at x0 0) (at x0 0)) (dbl-all (tail x0))))
sum-all       (if (= x0 ()) 0 (+ (at x0 0) (sum-all (tail x0))))
len-all       (if (= x0 ()) 0 (+ (len-all (tail x0)) 1))
prd-all       (if (= x0 ()) 1 (* (at x0 0) (prd-all (tail x0))))
foldl         (if (= x0 ()) x1 (foldl (tail x0) (code-eval x2 x1 (at x0 0)) x2))
filter        (if (= x0 ()) x0 (if (code-eval x1 (at x0 0))
                                 (cons (at x0 0) (filter (tail x0) x1))
                                 (filter (tail x0) x1)))
map-adjacent  (if (= x0 ()) () (if (= (tail x0) ()) ()
                                 (cons (code-eval x1 (at (tail x0) 0) (at x0 0))
                                       (map-adjacent (tail x0) x1))))
positions     (if (= x0 ()) x0 (cons x1 (positions (tail x0) (+ x1 1))))
scan          (if (= x0 ()) () (cons (code-eval x2 x1 (at x0 0))
                                   (scan (tail x0) (code-eval x2 x1 (at x0 0)) x2)))
shift-seq     (if (= x0 ()) () (if (< 0 x1)
                                 (concat (cons (shift-seq (tail x0) (- x1 1)) '((0))))
                                 x0))
seq-corr      (if (= x0 ()) 0 (if (= x1 ()) 0
                                (+ (* (at x0 0) (at x1 0)) (seq-corr (tail x0) (tail x1)))))
best-shift    (if (= x0 ()) (tuple 0 x2)
                (code-eval '(lambda (c rest k) (if (< c (at rest 0)) rest (tuple c k)))
                           (seq-corr x0 x1) (best-shift (tail x0) x1 (+ x2 1)) x2))
argmax-corr   (at (best-shift x0 x1 0) 1)
last-or       (if (= x0 ()) x1 (if (= (tail x0) ()) (at x0 0) (last-or (tail x0) x1)))
```

In `best-shift` the quoted lambda is a code literal with three parameters; `x3-specs.lisp` writes it `(code (x0 x1 x2) (if (< x0 (at x1 0)) x1 (tuple x0 x2)))`. In `shift-seq`, `'((0))` is a literal of type `(:seq (:seq :int))`: the definition appends one zero by building the two-element list of sequences `(<shifted tail> (0))` and concatenating it.

What the names mean, where the name alone could mislead **[C]** from the definitions, **[M]** by the rows:

- `positions` returns the index list x1, x1+1, … as long as x0. The elements of x0 do not matter. It is not "positions of a value".
- `map-adjacent` applies the function to each adjacent pair with the later element first: f(e[i+1], e[i]).
- `scan` returns the running values f(x1, e0), f(f(x1, e0), e1), …, without the initial value.
- `shift-seq` shifts left by x1 and fills with zeros; for x1 ≤ 0 it returns x0 unchanged.
- `seq-corr` is the sum of products over the common prefix of the two sequences.
- `best-shift` returns the tuple (largest correlation, shift at which it occurs) over the suffixes of x0 against x1, counting shifts from x2. The empty suffix scores 0, and an earlier shift wins a tie.
- `last-or` returns the last element of x0, or x1 when x0 is empty.

### 1.3 How a function-valued argument is represented

A function argument is **quoted code**. It is not the name of a library function and not a closure **[C]** `v2/ast.lisp:102-106` ("Quoted typed syntax in an explicit free-variable scope; never an executable closure"). Its type is `(:code INPUTS RESULT)`. Two kinds occur:

- a binary step, type `(:code ((0 . :int) (1 . :int)) :int)`: an expression over two integer variables x0 and x1;
- a predicate, type `(:code ((0 . :int)) :bool)`: an expression over one integer variable x0.

The value is the expression itself, for example the term `(- x0 x1)`. A program applies it with the primitive `code-eval`: `(code-eval f a b)` evaluates the expression with x0 = a and x1 = b and with nothing else in scope **[C]** `v2/vm.lisp:391-399`. Because the value is syntax, two code values can be compared with `=`, and the full grammar does offer `=` and `if` at the code type (§3.3) **[M]** `logs/probe-primitives.log`.

In the library files a row stores it as `(:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT) (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT)))` **[C]** `v2/library/scans.sexp`. In the data files written here it is `(code (x0 x1) (- x0 x1))`.

Four code values occur in the rows of the sixteen specs **[C]** `build-batteries.lisp:585-590`, **[M]** `logs/analyze-rows.log`:

| Name in the bootstrap | Value | Used by |
|:--|:--|:--|
| `sub-step` | `(- x0 x1)` | `foldl` (all 9 rows), `map-adjacent` (4), `scan` (3) |
| `add-step` | `(+ x0 x1)` | `map-adjacent` (4), `scan` (6) |
| `pos-pred` | `(< 0 x0)` | `filter` (4) |
| `even-pred` | `(= (* (/ x0 2) 2) x0)` | `filter` (3) |

Three more occur only in held-out inputs: `(* x0 x1)` and `(< x0 0)` in the 200-input sets, and `(- (* 2 x0) x1)` in the harness's one-input checks of `foldl` and `scan` (§4).

### 1.4 Metadata the bootstrap and the harness attach

All of this is in `x3-specs.lisp`, per spec, under the keys named here.

**Whitelist** (`:whitelist`, `:literals`, `:constants`). Each spec carries the list of operators its author allows the search to use, a list of integer literals, and a list of typed constants **[C]** `v2/consolidate.lisp:1112-1137`. Gate X3 ignores the operator whitelist. Examples: `copy` has `cons tail at = if + *` and no literals; `argmax-corr` has only `best-shift` and the tuple accessor, with literals 0 and 1; `shift-seq` has `concat`, `cons` at two types, `tail = < - if`, literals 0 and 1, and the two constants `()` and `((0))`.

**Search settings in the bootstrap** (`:bootstrap-settings`). Description bound 90 bits and budget 80,000 work units for the six seeds; bound 130 and budget 350,000 for the other ten; first-phase budget 15,000; `:max-depth 2`; every job recursive except `argmax-corr` **[C]** `build-batteries.lisp:562, 889`, `consolidate.lisp:1248-1281`.

**Recursion schemas** (`:schema-used`). The bootstrap offers all five hand-written schemas to every job **[C]** `build-batteries.lisp:13-15`, `bootstrap/recursion-schemas.lisp:332-355`. With the whitelist kept and the schemas removed, `map-adjacent`, `positions`, `scan`, `shift-seq` and `best-shift` are not found, `foldl` comes back as a fold from the wrong end, and `last-or` comes back as the 192/200 impostor **[M]** `logs/harness-clean-x1.log`, regime `WHITELIST-NO-SCHEMAS`. The audit's report says of `last-or` that it "uses one but does not need it" (`bootstrap-reflection.md` §4.2) **[D]**; on the 200 inputs it does need it. The schema written for each function is named in the same report, §4.1 **[D]**: lookahead for `map-adjacent` and `last-or`, state fold for `foldl`, state scan for `scan`, countdown for `shift-seq`, counter for `positions` and `best-shift`.

**Trace-complete rows** (`:trace-closed-rows`). The kernel's recursion search answers a candidate's recursive calls from a table made of the spec's own rows **[C]** `v2/decompose.lisp:767-791`, `v2/vm.lisp:429-436`. A row is therefore useful to it only if the recursive call that the intended program makes on that row is itself a row. I measured this directly: with each function replaced by the table of its rows, the library's definition was evaluated on every row **[M]** `logs/analyze-rows.log`.

- For fourteen of the fifteen recursive specs, every row evaluates: the rows are closed under the definition's own recursion. For the six seeds they are the four suffixes of one list. For `foldl`, `scan`, `positions` and `best-shift` they are the call trace of the intended program, intermediate states included (in `foldl` the second argument steps 12, 11, 9, 6).
- `shift-seq` is closed on 12 of its 13 rows. The row `((3 1 4 1 5) 2)` needs `((1 4 1 5) 1)`, which is not a row.
- `argmax-corr` is not recursive.

**Prerequisite library entries** (`:library-in-bootstrap-before`, `:calls-library-functions`). Two definitions call other library functions: `best-shift` calls `seq-corr`, and `argmax-corr` calls `best-shift`. In the bootstrap the library holds `map` and `foldr` when `foldl`, `filter`, `map-adjacent` and `positions` are synthesized; it is empty for `scan`; and it holds the earlier functions of the same battery for the last five **[M]** `logs/show-boot.log`. None of the sixteen definitions calls `map` or `foldr`.

**The harness's one held-out input** (`:harness-held-out-case`), §4.2.

## 2. The data files

All three are plain Lisp data: integers, lists, strings, keywords and unqualified symbols. They contain no package-qualified symbol and no reader macro.

- **`x3-specs.lisp`**: one form per spec, in bootstrap order: `(:name NAME :params ((x0 TYPE) ...) :returns TYPE :rows (((arg ...) expected) ...) :definition <typed form, verbatim from the library> :definition-readable <the same without types> ... :notes "...")`.
- **`x3-heldout.lisp`**: one form per spec, in the same order: `:generator` (how each parameter is drawn), `:oracle-source` (the text of the reference function), and `:rows`, the 200 inputs with the expected outputs.
- **`x3-prerequisites.lisp`**: `map` and `foldr`, in the style of `x3-specs.lisp`.

Conventions:

- A sequence is a list of integers; `()` is the empty sequence. A tuple is a list; `best-shift` returns `(c k)`.
- **Booleans.** The kernel's Booleans are `t` and `nil` **[C]** `v2/ast.lisp:701`. The empty sequence is also `nil`. The two are one Lisp object, and the kernel tells them apart only by the declared type: the literal `(:lit :bool nil)` is false and `(:lit (:seq :int) nil)` is the empty sequence. No parameter and no result of the sixteen specs is a Boolean, so the collision never arises in a row. Booleans occur only inside programs, as the result of `=`, `<` or a predicate and as the test of `if`. The files write the empty sequence as `()` everywhere.
- **Function arguments** are `(code (x0 x1) BODY)` or `(code (x0) BODY)`, as in §1.3. A list that begins with the symbol `code` cannot be confused with a sequence, whose members are integers.
- **Types** are written as the kernel writes them. `(0 :seq :int)` inside a code type is the dotted pair `(0 . (:seq :int))` as Lisp prints it.
- `:definition` is the kernel's portable typed form: `(:app OP ARG ...)`, `(:op NAME TYPE)`, `(:var N TYPE)`, `(:lit TYPE VALUE)`. `:definition-readable` drops the types: `x0`, `x1` for variables, bare integers, `(lit TYPE VALUE)` for any other literal.

Checks made on the files:

- `dump-specs.lisp` reads `x3-specs.lisp` back and compares every row and every definition with the bootstrap's dump: identical **[M]** `logs/dump-specs.log`.
- `check-plain-read.lisp` loads no kernel. It reads the two main files in an ordinary package, evaluates each `:definition-readable` with an interpreter of about forty lines written from the table in §3.3, and compares: 107 of 107 spec rows and 3,200 of 3,200 held-out rows agree **[M]** `logs/check-plain-read.log`.
- In the kernel's own VM, each of the sixteen definitions reproduces all of its spec rows and all 200 of its held-out rows **[M]** `logs/analyze-rows.log`.

## 3. What "full grammar, no schemas, ordinary rows" means

### 3.1 The four regimes, from the code

The harness is the function `measure-bootstrap-distractor-audit` **[C]** `v2/experiments/stage0-audit.lisp:168-233`. (`v2/tests/stage0.lisp` holds unit tests of the Stage 0 fixes and does not run the ladder.) It runs the sixteen specs four times. A regime is a pair of switches **[C]** `:172-175`:

| Regime | Grammar | Schemas | Harness prints (solved / sound) | Recount with a clean library |
|:--|:--|:--|:--|:--|
| `:whitelist+schemas` | the spec's whitelist | all five offered | 16 / 16 | 16 |
| `:whitelist-no-schemas` | the spec's whitelist | none | 10 / 9 | 10 |
| `:active-grammar+schemas` | the full grammar | all five offered | 10 / 9 | 11 |
| `:active-grammar-no-schemas` | the full grammar | none | 9 / 8 | 9 |

**[M]** `logs/stage0-unmodified.log` for the harness's own figures (the harness run exactly as committed), and `logs/harness-clean-x1.log` for the recount. Both sets of figures in the plan reproduce.

The two switches do the following.

- **Grammar.** The harness binds `*use-active-library-grammar*` **[C]** `:180`. When it is true, `synthesize-spec-entry` **[C]** `v2/consolidate.lisp:1264-1271`
- replaces the whitelist by the list that `active-library-spec-operators` builds (§3.3);
- sets the integer literals to 0, 1, 2 together with the spec's own literals, which for these specs is always {0, 1, 2};
- keeps the spec's typed constants as its author wrote them, so `shift-seq` still receives `((0))`, and `argmax-corr` receives no constant at all, not even `()`;
- raises the description bound by 24 bits, to 114 for the seeds and 154 for the others.
- **Schemas.** The harness passes `:expanders (list (recursion-schema-expander))` or nothing **[C]** `:211`. "No schemas" removes the five hand-written schemas of `bootstrap/recursion-schemas.lisp`. It does not remove the kernel's own two recursion forms, the split on the empty sequence with a recursive call on the tail and its lockstep variant for two sequences **[C]** `v2/decompose.lisp:365-416`.

Everything else is the same in all four regimes **[C]** `:186-232`:

- the specs run in the order of §1.1, in one library that accumulates through the regime;
- the budget is 350,000 work units per spec; the bound is 90 for the six seeds and 130 for the others, before the 24 bits;
- every job is recursive except `argmax-corr`;
- before `foldl` the harness loads `map` and `foldr` from the library files; before `best-shift` it loads `seq-corr`; before `argmax-corr` it loads `seq-corr` and `best-shift`; each only if the function is not already defined, which is where the defect of §5.2 lies;
- the search stops at the first program that fits every row (`:stop-on-first t`, `consolidate.lisp:1282`);
- any error counts as "not solved" (`:229`);
- a solved spec is called sound if the returned function gives the right output on one hand-written input, the evaluation limited to 20,000 work units (`:216-228`).

### 3.2 Which regime is "today 8–10"

It is the fourth, `:active-grammar-no-schemas`. The 8 is the harness's figure at 350,000 work units per spec. The 10 is the same regime at ten, a hundred and a thousand times that budget, where `positions` and `seq-corr` are added **[M]** the four logs of §0; **[D]** plan §2.3, `plan_v2c_audit/reports/empirical.md` §4.5. The regime exists only in `v2/`; `v1/consolidate.lisp` has no such switch **[C]**.

### 3.3 The full grammar

`active-library-spec-operators` **[C]** `v2/consolidate.lisp:1213-1246` builds the operator list from the spec's signature. Let T be the set of types in the signature (the result type and each parameter type). The list is, in this order:

1. `+ - * / mod < =`, each at `:int`;
2. `if` at the result type, and `if` at `:bool`;
3. for each type in T: `=` at that type and `if` at that type;
4. for each sequence type in T, with element type E: `cons`, `tail`, `length` and `concat` at E, and `at` on the sequence type;
5. for each tuple type in T: `tuple` at that type, and `at` for each of its slot types;
6. for each code type in T: `code-eval` at that type;
7. every function entry in the library that is active and defined, except the function being synthesized.

The grammar therefore differs from spec to spec. It has 15 or 16 primitives when the signature has only sequences and integers, three more (`=`, `if`, `code-eval` at the code type) when there is a function argument, and 20 for `best-shift`, the only spec with a tuple type **[M]** `logs/tables.txt`, Table 4.

It is not every operator the kernel has. `v2/ast.lisp:118-155` lists 37 primitives **[C]**. The full grammar leaves out `member`, `lookup`, `gather`, `iota`, `tabulate`, `where`, `evolve` and all the `code-…` primitives other than `code-eval`.

**The primitives of the full grammar, as the VM runs them.** Signatures are those the kernel computes; behaviour was probed in the VM **[M]** `logs/probe-primitives.log`; code references are to `v2/vm.lisp` **[C]**.

| Operator | Arity and types | Meaning | Error |
|:--|:--|:--|:--|
| `+`, `-`, `*` | (int, int) → int | exact integer arithmetic of any size (`:241-249`) | none |
| `/` | (int, int) → int | quotient truncated toward zero: 7/2 = 3, −7/2 = −3 (`:247`) | division by zero |
| `mod` | (int, int) → int | remainder with the sign of the divisor: −7 mod 3 = 2, 7 mod −3 = −2 (`:246`) | division by zero |
| `<` | (int, int) → bool | strictly less (`:250`) | none |
| `=` | (T, T) → bool, at any one type T | structural equality, on integers, sequences, tuples and code values (`:251`) | none |
| `if` | (bool, T, T) → T | **lazy**: the test is evaluated, then only the chosen branch (`:344-355`) | an error in the test or in the chosen branch |
| `cons` | (E, (:seq E)) → (:seq E) | prepend (`:253`) | none |
| `tail` | ((:seq E)) → (:seq E) | all but the first element (`:254-258`) | the empty sequence |
| `length` | ((:seq E)) → int | number of elements (`:259`) | none |
| `concat` | ((:seq (:seq E))) → (:seq E) | concatenation of a sequence of sequences, one level (`:260`) | none |
| `at` on a sequence | ((:seq E), int) → E | element at a zero-based index (`:273-284`) | index below 0, or not below the length; no wrapping (`:159-163`) |
| `at` on a tuple | (tuple, int) → slot type | component at a zero-based index | index out of range; a slot of another type |
| `tuple` | (T1, T2) → (:tuple T1 T2) | build a tuple (`:252`) | none |
| `code-eval` | (code, arguments of the code's parameter types) → the code's result type | evaluate the quoted expression with its own parameters bound to the arguments and nothing else in scope (`:391-399`) | whatever the expression raises |
| a library function | as declared | evaluate its body with its parameters bound; recursion is allowed (`:429-439`) | whatever the body raises |

Further rules that a re-implementation must match:

- **Strictness.** Every operator except `if` evaluates all of its arguments first, so an error in any argument is an error of the whole expression. `(+ 1 (/ 1 0))` is an error; `(if t 1 (/ 1 0))` is 1.
- **Outcomes.** An evaluation ends as a value, as an error, as "unresolved" (a call to a function known only by a table, with arguments not in the table), or as "unknown" when its work budget runs out first (`:449-477`). A candidate is right on a row only if the outcome is a value equal to the expected value.
- **No default values.** Nothing is returned for an out-of-range index or an empty tail; both are errors.
- **Budgets.** `evaluate` allows 1,000,000 work units by default (`:476`); the search gives each candidate 100,000 per row (`v2/enumerate.lisp:489`); the harness's one-input check allows 20,000.

One consequence of item 4 of the list above: `concat` is in every one of these grammars, but its argument type, `(:seq (:seq :int))`, can be built only from a constant, because `cons` is offered at the element type `:int` alone. Only `shift-seq` has such a constant.

**Whether the library's own definition can be written in the full grammar** **[M]** `logs/tables.txt`, Table 3 (the line "the library's definition uses, and the grammar lacks"); `logs/analyze-rows.log` for the equivalents:

- For thirteen specs, yes.
- `argmax-corr`: no. The grammar has no tuple accessor, because no tuple type occurs in the spec's signature. This is the case the plan names in §2.3.
- `shift-seq`: not as written. The definition needs `cons` at element type `(:seq :int)`, which the grammar lacks. An equivalent for x1 ≥ 0 does exist in the grammar, `(if (= x0 ()) x0 (cons (if (< x1 (length x0)) (at x0 x1) 0) (shift-seq (tail x0) x1)))`: it fits all 13 rows and all 200 held-out rows. The plan does not mention this case.
- `best-shift`: not as written. The definition applies a quoted three-argument lambda with `code-eval` at a code type that is not in the signature. An equivalent without the lambda exists when `seq-corr` is in scope. It calls itself twice at each step, fits all 9 rows, and is right on all 200 held-out rows when given enough evaluation work (4 of the 200 exceed 1,000,000 units).

### 3.4 Which library functions are in scope for each spec

This depends on how the library is managed between specs. Three arrangements were run **[M]** `logs/tables.txt`, Table 3.

| Spec | Harness as written | Clean library per spec (the auditor's recount) | Complete library |
|:--|:--|:--|:--|
| `copy` | none | none | none |
| `inc-all` … `prd-all` | the seeds found so far | none | the seeds before it |
| `foldl` | six seeds, `map`, `foldr` | `map`, `foldr` | six seeds, `map`, `foldr` |
| `filter` | those and `foldl` (the impostor it found) | `map`, `foldr` | those and `foldl` |
| `map-adjacent` | … and `filter` | `map`, `foldr` | … and `filter` |
| `positions` | the same as for `map-adjacent` | `map`, `foldr` | … and `map-adjacent` |
| `scan` | the same | `map`, `foldr` | … and `positions` |
| `shift-seq` | the same | `map`, `foldr` | … and `scan` |
| `seq-corr` | the same | `map`, `foldr` | … and `shift-seq` |
| `best-shift` | the same; **`seq-corr` is missing** | `map`, `foldr`, `seq-corr` | … and `seq-corr` |
| `argmax-corr` | the same; **`seq-corr` and `best-shift` are missing** | `map`, `foldr`, `seq-corr`, `best-shift` | … and `best-shift` |
| `last-or` | the same | `map`, `foldr` | … and `argmax-corr` |

- "Harness as written" is what produced the plan's figure of 8. A function enters the grammar only once it has been solved in the same regime, so at the default budget nothing after `filter` is added, and the two missing prerequisites are the defect of §5.2. At ten times the budget `positions` and `seq-corr` are solved and join the grammar of the specs after them.
- "Clean library" is the recount of `plan_v2c_audit/scripts/bootstrap-reflection/budget-scaling.lisp:63-68` **[C]**.
- "Complete library" is a third arrangement added here. Each spec starts from a fresh library that holds a correct definition of every function before it in the order of §1.1: the earlier seeds as the bootstrap synthesizes them, `map` and `foldr` from the seventh spec on, and the earlier stored functions from the library files. This is the literal reading of the plan's phrase "every library function defined so far", made independent of which searches succeeded. It is mode `curriculum` in `x3-harness.lisp`.

To the question in the task: `seq-corr` is in scope for `best-shift` in the bootstrap, in the clean-library recount and in the complete-library run. In the harness as written it is not, in the two full-grammar regimes at the default budget, because `seq-corr` itself fails there first. In none of the three arrangements is `best-shift` found (§5.3).

### 3.5 "Ordinary input/output rows"

The gate says "ordinary input/output rows", and the risk table of the plan says "without whitelist, schema, or trace-shaped rows" **[D]** plan §11.2 and §10, risk 1. The kernel's spec rows are trace-shaped: §1.4 shows that the rows of fourteen of the fifteen recursive specs are closed under the intended recursion. So the two instructions, "exactly these rows" and "ordinary rows", agree only on this reading: the new kernel is given these rows as plain input/output pairs and may not rely on their being closed. That is how the prototype of §8.5 used them. If the owner intends different rows, they do not exist yet as a set. The only ones I know of are in `plan_v2c_audit/scripts/bootstrap-reflection/trace-ablation.lisp` and `trace-ablation-foldl.lisp`, for `foldl`, `scan`, `best-shift`, `positions` and `shift-seq` **[D]** `bootstrap-reflection.md` §3.3. I did not run them. This needs a decision before X3 is scored.

## 4. Held-out scoring

There are two procedures. They are different, and neither contains the other.

### 4.1 The 200 inputs of `plan_v2c_audit/verify-review/`

**Generator** **[C]** `verify-review/tg-probe-r1.lisp:312-333`, with the per-spec integer ranges in `verify-review/r1-spec.lisp:64-124`. For each spec a random state is made by `(sb-ext:seed-random-state 999)`, and 200 examples are drawn one after another. Within an example the parameters are drawn in order:

| Kind of parameter | How it is drawn |
|:--|:--|
| sequence | a length uniform on 0…12, then that many elements, each uniform on −5…9 |
| integer | uniform on a range fixed per spec |
| binary function | one of `+`, `-`, `*`, uniformly; in the kernel's form `(+ x0 x1)`, `(- x0 x1)`, `(* x0 x1)` |
| predicate | one of positive, even, negative, uniformly; `(< 0 x0)`, `(= (* (/ x0 2) 2) x0)`, `(< x0 0)` |

The integer ranges are 0…4 for the start index of `positions`; 0…3 for the shift of `shift-seq` and for the starting shift of `best-shift`; −5…9 for the initial value of `foldl` and of `scan` and for the default of `last-or`. The seed is 999, the count 200, the maximum length 12.

Because the stream depends only on the list of parameter kinds, specs with the same kinds get the same inputs: the six seeds share one set of 200 sequences, `foldl` and `scan` share inputs, and so do `seq-corr` and `argmax-corr` **[M]** `logs/check-plain-read.log`, census.

**Oracle.** For each spec, a Lisp function that transliterates the library's definition line by line **[C]** `r1-spec.lisp:16-55`; its text is in `x3-heldout.lisp` under `:oracle-source`. There a function argument is the name `+`, `-` or `*`, applied with `funcall`, and a predicate is one of three names. For the six seeds, which have no library entry, the oracle is the function that the name and the four rows denote.

**Score.** The number of the 200 examples on which the candidate's output equals the oracle's. "200/200" in the plan's §8.5 means all of them.

**The rows as data.** `x3-heldout.lisp` holds the 200 inputs and expected outputs of every spec, generated here by the audit's own code in a copy **[M]** `logs/heldout-dump.log`. The audit's cross-check was repeated: the regenerated examples are byte-identical to the audit's stored `logs/xref-data.sexp`, and the library's definitions, run in the kernel VM, agree with the oracles on all 200 inputs of all sixteen specs **[M]** `logs/vr-xref-data-compare.txt`, `logs/vr-xref-kernel.log`. The random stream is SBCL's own, so a re-implementation should take the literal rows and not re-draw them.

Three properties of this set that matter for the gate **[M]** `logs/check-plain-read.log`, `logs/analyze-rows.log`:

- The inputs are not all new. Between 0 and 19 of the 200 inputs of a spec are also inputs of one of its spec rows, mostly the empty sequence.
- All shifts and start indices are non-negative, as they are in the spec rows. The plan notes that the prototype's `shift-seq` falls to 174/200 when the shift may be negative.
- **It cannot tell a left fold from a fold taken from the right end.** For each of `+`, `-` and `*`, f(f(a, x), y) = f(f(a, y), x). The program `(if (= x0 ()) x1 (code-eval x2 (foldl (tail x0) x1 x2) (at x0 0)))` scores 200/200 on the `foldl` set and is not `foldl`. The kernel returns exactly this program in the regime `:whitelist-no-schemas` **[M]** `logs/harness-as-written-x1.log`.

### 4.2 The one input of the v2 harness

`held-out-test-cases` **[C]** `stage0-audit.lisp:59-84` gives one hand-written input and expected output per spec. A solved spec is "held-out sound" if the returned function, called in the VM with at most 20,000 work units, returns that output **[C]** `:216-228`. The sixteen cases are in `x3-specs.lisp` under `:harness-held-out-case`. Some were chosen to catch a particular impostor: `foldl` and `scan` use the step `(- (* 2 x0) x1)`, for which the order of folding matters, and `last-or` uses a sequence whose head and last element differ.

### 4.3 Which one the plan's "held-out-sound" refers to

The plan defines the term in §2.3: "right on a fresh input that was not among the spec's rows. In the audit harness that produced the counts below, that is one hand-written input for each spec, so each count of sound solutions here is an upper bound" **[D]**. So the figures "8–10" in the gate were counted with the one input of §4.2. The prototype's figures in §8.5, and the target shape "200/200", use the 200 inputs of §4.1. The gate itself does not say which applies to the new kernel.

The two disagree on two programs that the present kernel returns **[M]** `logs/harness-as-written-x1.log`:

| Program | One input | 200 inputs |
|:--|:--|:--|
| `last-or` in the two regimes without schemas: `(if (= x0 ()) x1 (if (= x1 (last-or (tail x0) x1)) (at x0 0) (last-or (tail x0) x1)))` | passes | 192/200 |
| `foldl` in `:whitelist-no-schemas`: the fold from the right end | fails | 200/200 |

A further gap: a `best-shift` that breaks ties the other way fits all nine rows and passes the one input, and is right on 173 of the 200 (§6).

Since each check catches something the other misses, the safe rule for X3 is to require both: all 200 rows of `x3-heldout.lisp` and the hand-written case, 201 rows per spec. For `foldl` the 200 rows say nothing about the order of folding, and a few rows with a step such as `(- (* 2 x0) x1)` would be needed to make the larger set decisive on its own. I have not added any rows; this is for the owner to decide.

The work allowed for a held-out evaluation is part of the rule. I scored the 200 inputs with 1,000,000 units per evaluation. No program returned by the kernel ran out **[M]** harness logs. A correct program that recomputes its recursive call twice per step did run out on 4 inputs (§3.3).

## 5. Today's results, re-measured

### 5.1 The harness as committed

Run unmodified in the copy (`run-stage0-unmodified.sh`, the command of `make stage0`), the harness prints **[M]** `logs/stage0-unmodified.log`:

| Regime | Solved | Held-out sound |
|:--|--:|--:|
| `WHITELIST+SCHEMAS` | 16/16 | 16/16 |
| `WHITELIST-NO-SCHEMAS` | 10/16 | 9/16 |
| `ACTIVE-GRAMMAR+SCHEMAS` | 10/16 | 9/16 |
| `ACTIVE-GRAMMAR-NO-SCHEMAS` | 9/16 | 8/16 |

This is the plan's "16, 9, 9, 8". The whole run takes 3.7 s, most of it loading the kernel.

All further runs use `x3-harness.lisp`, which makes the same calls in the same order and records more: the grammar offered, the functions in the library, the text of any error, the program returned, and the score on the 200 inputs. In its mode `as-written` it reproduces every count and every work figure of the unmodified harness **[M]** `logs/harness-as-written-x1.log` against `logs/stage0-unmodified.log`. All harness runs up to a hundred times the budget were made twice and came out identical **[M]** `logs/compare-rerun.txt`.

### 5.2 The harness defect

A recursive synthesis begins by defining the function under construction as a stub that answers only from the table of spec rows **[C]** `v2/decompose.lisp:785`. If the search fails, nothing removes the stub. A stub is "defined" but has no library entry **[C]** `v2/knowledge.lisp:551-556`. The harness loads a prerequisite only `(when … (not (defined-function-p …)))` **[C]** `stage0-audit.lisp:195-200`, so after a failure the real function is never loaded, and since it has no entry it is also absent from the full grammar.

What this does, as measured **[M]** `logs/harness-as-written-x1.log` (each spec's lines "library functions" and "oracle stubs left defined"):

- In `:whitelist-no-schemas`, `best-shift` fails and leaves its stub. The attempt on `argmax-corr` then ends after 51,952 work units with the error `Unknown knowledge-entry :BEST-SHIFT`, which the harness counts as a failure. The error is raised by the commit, which runs only after the search has a candidate **[C]** `consolidate.lisp:1284-1285`. With the prerequisite loaded, `argmax-corr` is solved soundly in 99,198 work units **[M]** `logs/harness-repaired-x1.log`. This is the plan's "`argmax-corr` FAIL is a commit error after a correct search".
- In the two full-grammar regimes, `seq-corr` fails at the default budget, so `best-shift` is searched without `seq-corr` in its grammar, and `argmax-corr` without `seq-corr` or `best-shift`.

Three repairs were run, all four regimes each, at the default budget **[M]** `logs/tables.txt`, Table 1. Each cell is solved / sound by the one input / sound on the 200 inputs / sound on both.

| Library handling | `whitelist+schemas` | `whitelist-no-schemas` | `active-grammar+schemas` | `active-grammar-no-schemas` |
|:--|:--|:--|:--|:--|
| Harness as written | 16 / 16 / 16 / 16 | 10 / 9 / 9 / 8 | 10 / 9 / 9 / 9 | 9 / 8 / 7 / 7 |
| Repaired: a prerequisite is loaded when the library has no entry for it | 16 / 16 / 16 / 16 | 11 / 10 / 10 / 9 | 10 / 9 / 9 / 9 | 9 / 8 / 7 / 7 |
| Clean library per spec (the auditor's recount) | 16 / 16 / 16 / 16 | 11 / 10 / 10 / 9 | 12 / 11 / 11 / 11 | 10 / 9 / 8 / 8 |
| Complete library per spec | 16 / 16 / 16 / 16 | 11 / 10 / 10 / 9 | 10 / 9 / 9 / 9 | 9 / 8 / 7 / 7 |

- The second number of each cell is what the plan reports. The first row gives the harness's 16, 9, 9, 8 and the third row the recount's 16, 10, 11, 9. Both reproduce.
- In the gate's regime the defect does not change the count. Repairing it gives `best-shift` and `argmax-corr` their prerequisites, and they still fail. The clean library gains one spec, `seq-corr`, because its grammar is eight operators smaller without the six seeds, `foldl` and `filter`, and the search then finishes inside the budget (101,258 work units).

### 5.3 The gate's regime, spec by spec

Regime `:active-grammar-no-schemas`. "Work" is the kernel's own unit, the total of the job's ledger; a spec that is not found has spent its whole budget. "Sound" means right on the one input and on all 200. **[M]** `logs/tables.txt`, Table 2, from the logs named in §0 and the corresponding `harness-clean-*` logs.

| Spec | Harness as written, 350,000 | The same at 3.5 M, 35 M and 350 M | Clean library, 350,000 to 35 M |
|:--|:--|:--|:--|
| `copy` | sound, 27,291 | same | sound, 27,291 |
| `inc-all` | sound, 195,020 | same | sound, 194,720 |
| `dbl-all` | sound, 63,333 | same | sound, 61,386 |
| `sum-all` | sound, 27,868 | same | sound, 27,703 |
| `len-all` | sound, 42,759 | same | sound, 42,495 |
| `prd-all` | sound, 36,804 | same | sound, 36,507 |
| `foldl` | **impostor**, 209,723: fails the one input, 81/200 | same | the same impostor, 209,591 |
| `filter` | sound, 120,369 | same | sound, 120,006 |
| `map-adjacent` | not found | not found | not found |
| `positions` | not found | **sound at 1,251,491** | not found at any of the three budgets |
| `scan` | not found | not found | not found |
| `shift-seq` | not found | not found | not found |
| `seq-corr` | not found | **sound at 664,914** | sound at 101,258 |
| `best-shift` | not found | not found | not found |
| `argmax-corr` | not found | not found at 3.5 M and 35 M; **impostor at 35,662,878**: fails the one input, 52/200 | not found |
| `last-or` | **impostor**, 162,170: passes the one input, 192/200 | same | the same impostor, 161,783 |

The "complete library" run gives the same outcome as "harness as written" at every budget up to 35 M, with work figures within 0.2% (`logs/harness-curriculum-*.log`).

Programs returned where they are not the library's definition:

- `foldl`: `(if (= () x0) x1 (- (foldl (tail x0) x1 x2) (at x0 0)))`. It ignores the function argument and subtracts. It has 100 bits against 134 for the true definition in the same library.
- `last-or`: `(if (= x0 ()) x1 (if (= x1 (last-or (tail x0) x1)) (at x0 0) (last-or (tail x0) x1)))`. It returns the head whenever the answer for the tail equals the default. That is right when the tail is empty and wrong when the last element of a longer sequence happens to equal the default. First miss: `((-5 2 -5 0 8) 8)` should give 8 and gives 0.
- `positions`, from ten times the budget: `(if (= x0 ()) x0 (cons x1 (inc-all (positions (tail x0) x1))))`. It is correct, and it is found only because the seed `inc-all` is in the library; this is why the clean library does not find it.
- `seq-corr`: the library's definition with the two summands in the other order.
- `argmax-corr`, at 35,662,878 work units: a 250-bit program of the form `(foldr x0 2 (code-subst …))` that calls `len-all`. It fits the three rows and gives 2 where 0 is wanted on the first held-out input it misses. It contains `code-subst`, which is not an operator of the full grammar; the kernel's own proposal that wraps a library function taking a function argument around a synthesized step puts it there **[D]** plan §2.5.

**A thousand times the budget.** All sixteen specs were run in one sequence at 350,000,000 work units per spec, the harness as written **[M]** `logs/harness-as-written-x1000-active-grammar-no-schemas.log`. Twelve were solved, 10 are sound by the one input, and 9 are sound on the 200. `map-adjacent`, `scan`, `shift-seq` and `best-shift` each spent the whole budget, 50 to 65 CPU seconds, and returned nothing. The run took 242 s and a 12 GB heap was enough. The plan says its fourth figure of 10 "was not measured on a run of all sixteen"; it now has been, and it is 10.

**What was not run.** The clean-library and complete-library arrangements were not run at a thousand times the budget. The three regimes other than the gate's were not run above ten times the budget.

### 5.4 Against the conditions of the gate

- *At least 14 of 16 held-out-sound.* Today 7 at the default budget and 9 from ten times the budget on, by both checks; 8 and 10 by the one input alone.
- *Nothing returned that fits the rows and fails held-out.* Today two such programs are returned at every budget (`foldl`, `last-or`), and a third (`argmax-corr`) from 102 times the default budget.
- *No guard split accepted that fails the size-order rule.* The present kernel has no such rule. The comparison is with the prototype (§5.5): accepting the first split that fits returns an impostor on `map-adjacent`.
- *A spec correctly reported as underdetermined counts as sound.* The present kernel reports nothing of the kind; it returns the first program that fits.

### 5.5 The prototype on the same rows

The plan's §8.5 table was re-run with the audit's own drivers in a copy. The three logs are identical to the audit's stored logs once timings are masked **[M]** `logs/prototype-rerun.txt`, `logs/vr-r1.log`, `logs/vr-r1-occam.log`, `logs/vr-r2.log`. Scores are on the 200 inputs. "Candidates" is the prototype's own count and is not comparable with work units.

| Spec | Prototype result |
|:--|:--|
| `copy`, `inc-all`, `dbl-all`, `positions` | 200/200 as a `tabulate`; 151, 408, 8,607 and 3 candidates |
| `scan` | 200/200 with one guard; 11,604 candidates, and 7,257,787 when splits are accepted in size order |
| `shift-seq` | 200/200 with one guard; 8,781 candidates, and 7,238,105 in size order |
| `filter` | nothing after 1,576,693 candidates; 200/200 at 1,383 once a one-argument Boolean call is in the grammar |
| `sum-all`, `prd-all` | impostors on the unlifted path (23/200 and 20/200); 200/200 through `fold` |
| `len-all`, `last-or` | 200/200 on both paths |
| `map-adjacent` | impostor from a guard split under first-fit acceptance, 29/200; 200/200 in size order, 616,232 candidates |
| `foldl` | impostor `(fold a (- acc x) xs)`, 81/200 |
| `seq-corr` | nothing as built; 200/200 once collect can sum (20,713 candidates with the shape given, 3,050,322 with it searched) |
| `argmax-corr` | impostors: 31/200, 43/200, and 49/200 with the aggregate |
| `best-shift` | impostor, 1/200 |

The prototype scores 81/200 on `foldl` with the same wrong function as the kernel: subtraction in place of the argument.

## 6. Underdetermined specs

A finite set of rows never determines a function, so the question is narrower: is there something the rows leave open that a search is likely to exploit? Three tests were made on every spec **[M]** `logs/analyze-rows.log`, `x3-row-analysis.sexp`:

1. simple statistics of each parameter over the rows;
2. for each parameter, whether any two rows differ in that parameter alone, which is the only direct evidence in the rows that it matters;
3. variants of the library's definition, each evaluated on the rows, on the 200 inputs and on the one input.

### 6.1 What the three questions of the task find

- **A parameter constant across the rows.** One: the function argument of `foldl`, `(- x0 x1)` in all nine rows. No other parameter of any spec is constant.
- **A function argument drawn from one function only.** `foldl` again. `filter` has two predicates, `map-adjacent` two functions, `scan` two.
- **All sequences shorter than 2.** None. The first sequence of every spec takes the lengths 0, 1, 2 and 3 (`shift-seq` also 5), except in `argmax-corr`, where the lengths are 2, 3 and 5. No sequence anywhere is longer than 5. The second parameter of `best-shift` has length 2 in all nine rows and takes two values, `(4 1)` and `(5 0)`.

### 6.2 Variants that fit every row

| Spec | Variant | Fits rows | 200 inputs | One input |
|:--|:--|:--|:--|:--|
| `foldl` | the argument replaced by subtraction | 9 of 9 | 81/200 | fails |
| `foldl` | the kernel's impostor, `foldl(tail) − head` | 9 of 9 | 81/200 | fails |
| `foldl` | fold from the right end, f(foldl(tail), head) | 9 of 9 | **200/200** | fails |
| `last-or` | the kernel's impostor (§5.3) | 7 of 7 | 192/200 | **passes** |
| `best-shift` | a later shift wins a tie | 9 of 9 | 173/200 | **passes** |
| `argmax-corr` | `(if (= (length x1) 2) (- (length x0) (length x1)) 2)`, the prototype's impostor | 3 of 3 | 31/200 | fails |

For comparison, variants that the rows do exclude. In `scan` and `map-adjacent`, replacing the argument by `+`, by `-` or by `*`, or swapping its two inputs, fits at most 7 of 9 and 6 of 8 rows. In `filter`, replacing the predicate by either of its two values or by "true" fits at most 5 of 7. So the function argument is pinned down in those three specs against these variants. The kernel did once replace the function argument of `scan` by a quoted conditional that behaves as `+` on the `+` rows and as `-` on the `-` rows, in the regime `:active-grammar+schemas` at ten times the budget (33/200) **[M]** `logs/harness-as-written-x10.log`.

### 6.3 Spec by spec

| Spec | What the rows leave open |
|:--|:--|
| `foldl` | **The function argument, entirely**, and the direction of the fold. This is the spec the plan names. The honest answer from these rows is "underdetermined". |
| `argmax-corr` | Almost everything. Three rows, three distinct outputs (1, 0, 2); small programs over the lengths fit. |
| `best-shift` | Tie-breaking and negative correlations. No row has a tie, and no element is negative, so the score 0 of the empty suffix is never the maximum of a non-empty input. The second sequence takes only two values. |
| `last-or` | Whether the last element is compared with the default: no row has a sequence of length 2 or more whose last element equals the default. |
| `shift-seq` | Negative shifts. The shift is 0, 1 or 2 in the rows; the definition returns the input unchanged for a negative shift, and the natural element-wise program reads out of range there. |
| `scan` | Little by the variants tried. The second and third parameters are never varied alone between two rows. |
| `map-adjacent` | Little by the variants tried. At most two outputs per row, since no sequence is longer than 3. |
| `filter` | Nothing found. |
| `positions` | Nothing found. The start index takes the five values 0…4. |
| `seq-corr` | Nothing found. All elements are positive and each sequence has at most 3 elements. |
| the six seeds | Four rows each, the suffixes of one list, elements among 1, 2, 3, 4. The kernel finds the intended function for all six in every regime. The prototype's unlifted path returns impostors for `sum-all` and `prd-all`: arithmetic on the length alone fits four rows. |

The gate counts "correctly reported as underdetermined" as sound. On this evidence a report of that kind is plainly correct for `foldl`. For `argmax-corr`, `best-shift` and `last-or` it would also be defensible, and the gate does not say how a claim of underdetermination is to be checked. That too needs deciding before X3 is scored, or a kernel could approach 14 by declaring specs underdetermined.

## 7. What did not reproduce, and what is new

Everything the plan states about this ladder reproduces: the harness's 16, 9, 9, 8; the recount's 16, 10, 11, 9; the ladder 8, 10, 10, 10; the `argmax-corr` commit error; the `foldl` impostor at every budget; and the prototype's §8.5 table, log for log. A few work figures in `v2/STAGE0_RESULTS.md` differ slightly from what the current code gives (for example `best-shift` 199,252 there and 199,199 here), as `empirical.md` §1 already notes; the outcomes are the same.

Findings that the plan does not contain:

1. **`last-or` is an impostor in the gate's regime**, and in every regime without the schemas. The harness's one input passes it; the 200 inputs give 192/200. On the 200 inputs "today 8–10" is 7–9. The audit's statement that `last-or` does not need its schema holds only by the one input.
2. **The 200 inputs cannot see the direction of a fold.** A right-end fold scores 200/200 on the `foldl` set. The two held-out procedures each miss something the other catches (§4.3).
3. **The spec rows are trace-shaped**, measurably: closed under the intended recursion for fourteen of fifteen recursive specs. This bears on the gate's words "ordinary input/output rows" (§3.5).
4. **The full grammar keeps author-written constants**: `((0))` for `shift-seq`, and no `()` for `argmax-corr`.
5. **`shift-seq` and `best-shift` cannot be written in the full grammar as the library writes them**, though each has an equivalent there. The plan names only `argmax-corr`.
6. **`best-shift`'s rows do not fix tie-breaking**, and the one-input check does not either.
7. **Whether the ladder reaches 10 depends on the library**, not only on the budget. With a clean library per spec it stays at 9 (one input) or 8 (200 inputs) up to a hundred times the budget, because `positions` is reached through `inc-all`.
8. **The 200 "fresh" inputs include up to 19 that are inputs of spec rows.**

Not determined: which held-out procedure the gate intends for the new kernel; what rows "ordinary input/output rows" refers to if not these; how a report of underdetermination is to be checked.

## 8. Files, and how to reproduce

Data files for the new kernel: `x3-specs.lisp`, `x3-heldout.lisp`, `x3-prerequisites.lisp`. Intermediate data: `boot-specs.sexp` (the bootstrap's dump), `x3-row-analysis.sexp` (§6), `results/*.sexp` (one record per spec attempt of every harness run), `logs/tables.txt` (the summary tables).

Scripts, in the order to run them. Each writes its log under `logs/`.

| Script | What it does |
|:--|:--|
| `setup.sh`, `setup-boot.sh` | copy `v2/` twice and `verify-review/` into the work directory |
| `run-stage0-unmodified.sh` | the Stage 0 harness exactly as committed |
| `run-boot.sh` | the real bootstrap, instrumented, in the second copy; writes `boot-specs.sexp` |
| `run-heldout.sh` | the audit's cross-check, then `heldout-dump.lisp`; writes `x3-heldout.lisp` |
| `run-lisp.sh show-boot.lisp show-boot` | harness specs against bootstrap specs against library files |
| `run-lisp.sh analyze-rows.lisp analyze-rows` | §1.4 trace closure and §6; writes `x3-row-analysis.sexp` |
| `run-lisp.sh dump-specs.lisp dump-specs` | writes `x3-specs.lisp` and reads it back |
| `run-lisp.sh dump-prereqs.lisp dump-prereqs` | writes `x3-prerequisites.lisp` |
| `run-lisp.sh probe-primitives.lisp probe-primitives` | §3.3 |
| `run-all-harness.sh` (add `with-x1000` for the thousand-fold run) | every harness run of §5 (`x3-harness.lisp`, driven by `run-harness.sh MODE MULT`), then `run-tabulate.sh` |
| `run-prototype.sh` | §5.5 |
| `run-check-plain.sh` | the two data files replayed with no kernel |
| `finish.sh` | confirms that the repository is unchanged |

`x3-common.lisp` is the shared prelude of the kernel-side scripts. It refuses to load a kernel from outside the work directory. The whole set takes about four minutes without the thousand-fold run and about eight with it; that run needs roughly 9 GB of memory.

## 9. What a new kernel must match

### 9.1 The sixteen specs

Rows and held-out rows are in `x3-specs.lisp` and `x3-heldout.lisp`. In the generator column, "seq" means a length uniform on 0…12 with elements uniform on −5…9; "f" means one of `(+ x0 x1)`, `(- x0 x1)`, `(* x0 x1)`; "p" means one of `(< 0 x0)`, `(= (* (/ x0 2) 2) x0)`, `(< x0 0)`. Seed 999, 200 examples per spec; take the literal rows from the file.

| # | Spec | Rows | Parameters | Returns | Function argument | Held-out generator |
|--:|:--|--:|:--|:--|:--|:--|
| 1 | `copy` | 4 | seq | seq | no | seq |
| 2 | `inc-all` | 4 | seq | seq | no | seq |
| 3 | `dbl-all` | 4 | seq | seq | no | seq |
| 4 | `sum-all` | 4 | seq | int | no | seq |
| 5 | `len-all` | 4 | seq | int | no | seq |
| 6 | `prd-all` | 4 | seq | int | no | seq |
| 7 | `foldl` | 9 | seq, int, binary code | int | yes; one value in the rows | seq; int −5…9; f |
| 8 | `filter` | 7 | seq, predicate code | seq | yes; two values | seq; p |
| 9 | `map-adjacent` | 8 | seq, binary code | seq | yes; two values | seq; f |
| 10 | `positions` | 11 | seq, int | seq | no | seq; int 0…4 |
| 11 | `scan` | 9 | seq, int, binary code | seq | yes; two values | seq; int −5…9; f |
| 12 | `shift-seq` | 13 | seq, int | seq | no | seq; int 0…3 |
| 13 | `seq-corr` | 7 | seq, seq | int | no | seq; seq |
| 14 | `best-shift` | 9 | seq, seq, int | tuple (int, int) | no | seq; seq; int 0…3 |
| 15 | `argmax-corr` | 3 | seq, seq | int | no | seq; seq |
| 16 | `last-or` | 7 | seq, int | int | no | seq; int −5…9 |

### 9.2 The baseline result per spec

"Kernel today" is the gate's regime at 350,000 work units as the harness runs it, with the result at larger budgets where it differs. "Sound" means right on the harness's one input and on all 200.

| # | Spec | Kernel today | Kernel today, clean library | Prototype (§5.5) |
|--:|:--|:--|:--|:--|
| 1 | `copy` | sound, 27,291 work | sound | 200/200 |
| 2 | `inc-all` | sound, 195,020 | sound | 200/200 |
| 3 | `dbl-all` | sound, 63,333 | sound | 200/200 |
| 4 | `sum-all` | sound, 27,868 | sound | 200/200 through `fold`; impostor unlifted |
| 5 | `len-all` | sound, 42,759 | sound | 200/200 |
| 6 | `prd-all` | sound, 36,804 | sound | 200/200 through `fold`; impostor unlifted |
| 7 | `foldl` | impostor, 81/200, at every budget | the same | impostor, 81/200 |
| 8 | `filter` | sound, 120,369 | sound | 200/200 with a Boolean call in the grammar; nothing without |
| 9 | `map-adjacent` | not found at any budget to 350 M | not found to 35 M | 200/200 in size order; impostor under first fit |
| 10 | `positions` | not found; sound at 1,251,491 | not found to 35 M | 200/200 |
| 11 | `scan` | not found at any budget to 350 M | not found to 35 M | 200/200 with one guard |
| 12 | `shift-seq` | not found at any budget to 350 M | not found to 35 M | 200/200 with one guard |
| 13 | `seq-corr` | not found; sound at 664,914 | sound, 101,258 | 200/200 with an aggregating collect; nothing without |
| 14 | `best-shift` | not found at any budget to 350 M | not found to 35 M | impostor, 1/200 |
| 15 | `argmax-corr` | not found to 35 M; impostor (52/200) at 35.66 M | not found to 35 M | impostors, 31 to 49 of 200 |
| 16 | `last-or` | impostor, 192/200, passes the one input | the same | 200/200 |
| | **Sound of 16** | **7; 9 from ten times the budget** | **8** | 13 in some configuration; no single configuration was run on all sixteen |

By the harness's one input alone the first column reads 8 and 10, which are the plan's figures, and the second reads 9.

### 9.3 The regime

- **Operators.** The full grammar of §3.3, built per spec from its signature. The per-spec whitelist is ignored.
- **Literals and constants.** Integer literals 0, 1, 2. Typed constants: `()` for every spec except `argmax-corr`, which has none, and `((0))` in addition for `shift-seq`. A new kernel that is to use nothing author-written should drop `((0))` and say so, since the present baseline had it.
- **Library in scope.** One of the three arrangements of §3.4, stated with the result. The plan's figure of 8 comes from the first. The third, a correct definition of every earlier function, does not depend on which searches succeeded, and it gives the same baseline counts as the first.
- **Schemas.** None. The kernel's own two recursion forms were present in the baseline.
- **Budget of the baseline.** 350,000 work units per spec, 0.06 to 0.07 s; description bound 114 bits for the six seeds and 154 for the others.
- **Rows.** The 107 rows of `x3-specs.lisp`, used as plain input/output pairs.
- **Scoring.** All 200 rows of `x3-heldout.lisp` and the hand-written case of each spec; report both.

### 9.4 The primitives of the full grammar

`+ - * / mod` on integers; `<` on integers; `=` at integer, sequence, tuple and code types; `if` at every type in the signature and at Boolean; `cons`, `tail`, `length`, `concat`, `at` on sequences of integers; `tuple` and `at` on tuples, only when the signature has a tuple type; `code-eval`, only when the signature has a code type; and the library functions in scope. Their types, meanings and errors are in the table of §3.3. The points most likely to be got wrong:

- `/` truncates toward zero, and `mod` takes the sign of the divisor;
- `at` and `tail` raise errors and never return a default; an index is zero-based and is never wrapped;
- `if` is lazy and everything else is strict;
- `=` is structural and applies to sequences, tuples and quoted code as well as integers;
- `code-eval` gives the quoted expression its own parameters and nothing else;
- false and the empty sequence are the same Lisp object and are told apart only by type;
- an evaluation that runs out of its work budget is neither a value nor an error, and counts as wrong.