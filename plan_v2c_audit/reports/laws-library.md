# laws-library — audit of laws, algebra discovery, anti-unification and the knowledge library

Auditor: `laws-library`. Date of run: 2026-11-24.
All paths are relative to `/home/tlh24/lisploop/` unless they start with `/`. "root" = the v1 kernel in the repo root; "v2" = `v2/`.
Tags: **VERIFIED** = I read the code at the cited lines and/or ran it; **INFERRED** = my conclusion from verified facts.
I did not read `plan_v2.md`, `plan_v2b.md`, `plan_v2.tex`.

Scratch (scripts, logs): `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library/`
- `exp_algebra.lisp` / `exp_algebra.log` — replays the algebra battery's discovery with instrumentation; distributivity probe.
- `exp_solvers.lisp` / `exp_solvers.log` — solver discovery traces (milestone path and battery path); enumeration scaling.
- `exp_rewrite.lisp` / `exp_rewrite.log` — cost/benefit of the law-driven rewrite filter in `start-search :laws`.
- `exp_bootstrap.lisp` / `exp_bootstrap.log` — times every battery build with output redirected to scratch (`library-out/`).
- `test-*.log` — root test modules `laws abstraction symbolic guards algebra compression corpus propagation` (all pass), `theories` (see note), v2 `theories` (passes).
- `library-summary.txt` — one line per entry of `v2/library/*.sexp`.

**Housekeeping note for the coordinator.** At 20:10:50 local time an untracked directory `/home/tlh24/lisploop/library/` (8 `.sexp` files) appeared in the repository root (`git status` shows `?? library/`). I did not create it: my only bootstrap run (20:16:54) had its output directory redirected to scratch, and at 20:10:35 my root `theories` test had just failed with "No battery packet :SEQUENCES at /home/tlh24/lisploop/library/sequences.sexp". Some other process ran the root bootstrap. I left it alone (repo is read-only for me).

---

## 0. The ten findings that matter most

1. **The whole generated library is 0.37 s of search.** Running the root kernel's `bootstrap/build-batteries.lisp` builders (output redirected to scratch) regenerates all eight `v2/library/*.sexp` files **byte-identically** in 0.37 s wall-clock total; the algebra battery takes 0.01 s (VERIFIED: `exp_bootstrap.log`; `cmp` of all 8 files against `v2/library/`). The library has 92 entries, 31 of which are hand-written `:spec` tables. The owner's "budget was very limited" is true by five orders of magnitude relative to "hours".
2. **Algebra discovery is real, small and generic at its core, and hand-steered at its edges.** The engine is "enumerate every expression up to a bit bound, run each on every row of a finite grid, hash by the vector of results" (`enumerate.lisp:704-877`), then read each hash bucket as equations (`laws.lisp:215-228`). That core is ~315 + ~230 LOC and works. Everything around it is supplied by the host script: the field (GF(3)), variable counts, operator lists per job, bit bounds, work budgets, and a **host-coded shape filter that keeps only commutativity / associativity / identity** (`consolidate.lisp:709-735`, applied at `bootstrap/build-batteries.lisp:155,166`). Of 187 equations the four jobs propose (all 187 exhaustively true on GF(3)), 14 pass the filter and 173 are thrown away (VERIFIED: `exp_algebra.log`).
3. **Distributivity does not exist anywhere** — not in code, not in the library (`grep -i distribut` over all `.lisp` and `v2/library` returns nothing; VERIFIED). No observation job has both `+` and `*` with three variables (`bootstrap/build-batteries.lisp:127-146`), and the shape filter has no two-operator case. Yet the existing machinery finds it immediately when asked: with 3 variables, `{+,*}`, a 34-bit body bound, `a*(b+c)` and `a*b+a*c` land in the same bucket after 6.8 M work units on GF(3) (37 M on GF(5)), under one second (VERIFIED: `exp_algebra.log` part B). This is a caller/script limit, not an algorithm limit.
4. **The buckets are already behaviour-equivalence classes — and the enumerator ignores them.** At a 44-bit body bound (3 vars, `{+,*}`, GF(5)) 57,909 expressions fall into 1,762 classes; 97% of evaluations rediscover a known class. With 3 variables, expressions grow ×15–17 per extra leaf while classes grow ×~5 (237→3,477→57,909 expressions against 68→336→1,762 classes; VERIFIED: `exp_solvers.log` part E). The enumerator is a function of the language only (`enumerate.lisp:714`) and never consults the buckets. INFERRED: with the present enumerator, 3 variables and 2 operators, exhausting 5-leaf terms takes 10 s (measured); extrapolating ×16 per leaf, 6 leaves ≈ 3 min, 7 leaves ≈ 45 min, 8 leaves ≈ 12 h — and the job keeps every record in memory, so memory binds first. Hours therefore buy about two more leaves than ten seconds do. Enumerating from class representatives is the change that alters the exponent.
5. **On `:int` no discovered law is ever a rewrite rule.** Rewrite libraries admit only laws with *current* evidence (`laws.lisp:1016`); integer laws can only be `:sampled` (`laws.lisp:96-97,133`), so the integer rewrite library built from the algebra battery consists of exactly the 4 hand-written `:trusted-axiom` cancellation laws (VERIFIED by running: `exp_solvers.log` part D prints the 4 rules). There is no proof mechanism for infinite domains; v2 names evidence methods `:pit` and `:ind1` (`v2/evidence.lisp:66`) but nothing produces them (VERIFIED by grep).
6. **Laws were never wired into v1 search (confirmed), and where wired they cost far more than they save.** Root `synthesize.lisp:629,876,1128` call `start-search` without `:laws`; only tests pass it. v2 adds `node-rewrite-laws` (`v2/synthesize.lisp:865-876,908,1163`). Measured on the GF(5) fixture of `tests/laws.lisp`: plain search 182 K work; with one law 741 K (4×); with all 80 validated depth-1 laws 70.2 M (385×) — identical results, and the filter saved only ~106 K of evaluation/checking (VERIFIED: `exp_rewrite.log`). The mechanism (each rule a VM-interpreted program run on each candidate, used only as a key into a rejection cache) should not be imported as is.
7. **The 14 "kinds" are one struct with role tags.** All share `knowledge-entry` (`knowledge.lisp:84-102`): inputs, target, expression, guard, trigger, residual, auxiliary-code, certificate, edges, metadata. A `:solver` is literally the law `op(k, W(k,c)) = c` plus a chosen unknown port — the code constructs that law to validate a solver (`milestones/algebra-discovery.lisp:34-47`, `consolidate.lisp:556-601`) and reads laws back as solvers (`consolidate.lisp:1581-1639`). Six kinds have zero instances in the library; `:functor` entries have no reader at all.
8. **Every cross-kind conversion that carries "algebra" is a hand-written shape recogniser:** `law-operator-fact` (assoc/comm/identity only), `fold-signature` + `monoid-fold-instance` (monoid folds only), `map-like-combinator-signature` + `extract-pointwise-binary-step` (map only), `induce-law-solvers` (laws of the form `(= (op … W …) c)` only), plus 9 of 10 transformers written by hand. Nothing discovers a new *kind of* structure.
9. **Anti-unification is host-only, first-order, positionally aligned, and not modulo laws** (one n-ary implementation, `unify.lisp:36-73`, reused at about eight sites). v2 adds a VM primitive `:code-anti-unify` (`v2/unify.lisp:75-103`) with no caller and no test (VERIFIED by grep).
10. **Working, separable, tested pieces exist:** finite-field law certification, the sampled-vs-certified evidence discipline with statement snapshots, `propagate-requirements` with fallback, AU + MDL-gated abstraction, guard discovery from support masks, and the persistence format (§8).

---

## 1. Algebra discovery, traced

### 1.1 Commutativity and associativity of `+` (the path that produced `v2/library/algebra.sexp`)

Driver: `build-algebra-battery`, `bootstrap/build-batteries.lisp:101-175` (v2 copy is identical; `diff` = 0 lines). All VERIFIED by reading and by re-running the same calls in `exp_algebra.lisp`.

| Step | What happens | Where | Hand-supplied |
|---|---|---|---|
| 0 | Four integer cancellation laws `(z+k)−k=z`, `(k+z)−k=z`, `k+(z−k)=z`, `k−(k−z)=z` are written by hand and attested `:trusted-axiom` | `build-batteries.lisp:106-117` | the laws themselves |
| 1 | Domain GF(3); rows = *all* assignments of 1, 2, 3 variables (3, 9, 27 rows) via `law-assignment` | `:120-126`, `laws.lisp:74-90,116-118` | field, variable counts |
| 2 | Four observation jobs: (1 var, `{+,*}`, literals 0 1), (2 vars, `{+,*}`, no literals), (3 vars, `{+}`), (3 vars, `{*}`) | `:127-146` | operator lists, literal lists |
| 3 | Budgets: body slack 20/24/44/44 bits; work 20,000/40,000/80,000/80,000 | `:147-150` | all numbers |
| 4 | Enumeration + experiment: the canonical enumerator emits every well-typed expression in order of description size; each is run on every row in the metered VM; the vector of row values is the key `(type values)` into `bucket-index`; the expression joins that bucket | `enumerate.lisp:704-723` (start), `:762-781` (`finish-observation`), `:847-870` (step) | — |
| 5 | Proposal: for each bucket, one equation `member = first-member` per later member (a spanning star, "not certificates") | `laws.lisp:215-228` | — |
| 6 | **Shape filter**: keep a law only if `law-operator-fact` recognises it | `build-batteries.lisp:155`; recogniser `consolidate.lisp:709-735` | the three shapes |
| 7 | Certification on the field: exhaustive loop over all assignments, guard then equation, in the VM; attests `:exhaustive (:equivalence)` with a statement snapshot | `build-batteries.lisp:156-158`; `laws.lisp:96-114,120-139,141-176` | work limit 100,000 |
| 8 | Transfer to `:int`: `retype-law` re-instantiates the law's inferred type template at `:int` — "no certificate transfers" — then `validate-law … t samples` on the Cartesian product of residues `(-3 -1 0 1 2 5)` (6, 36, 216 samples). Survivors are `:conjecture` with certificate method `:sampled` | `build-batteries.lisp:159-165`; `templates.lisp:524-534`; `consolidate.lisp:538-554`; `laws.lisp:132-134` | the residue list |
| 9 | Naming by recognised shape: `INT/COMM-+`, `INT/ASSOC-+`, `INT/ID-+-RIGHT` … ; first of each name wins | `build-batteries.lisp:166-173` | name scheme |

Measured (root kernel, `exp_algebra.log`):

| job | expressions | buckets | proposed | pass filter | work | claim |
|---|---|---|---|---|---|---|
| 1 var, `{+,*}`, lits | 77 | 11 | 66 | 4 (identities) | 12,516 | exhausted |
| 2 vars, `{+,*}` | 74 | 24 | 50 | 2 (comm +, comm *) | 34,391 | exhausted |
| 3 vars, `{+}` | 52 | 17 | 35 | 4 (3 comm, assoc) | 80,000 | **cutoff** |
| 3 vars, `{*}` | 52 | 16 | 36 | 4 (3 comm, assoc) | 80,000 | **cutoff** |

- All 187 proposed equations validate exhaustively on GF(3) (they must: the grid *is* the whole domain, so step 7 re-does step 4 — INFERRED redundancy).
- The two 3-variable jobs hit their work limit before exhausting the bound; associativity is found because it happens to be enumerated before the cutoff (VERIFIED: claim `:CUTOFF` at work 80,000).
- Fate of the 173 discarded equations on `:int` sampling: 157 survive, 16 are refuted — the GF(3) artefacts `x·x·x = x` and `x+x+x = 0` in their variants (VERIFIED). The discarded survivors include `x*0 = 0`, `(x0+x1)*x0 = x0*(x0+x1)`, `x0*(x0+1) = x0 + x0*x0` (a distributivity instance), and all the permuted-association forms.
- Result in the library: 12 laws — 4 trusted axioms, 8 sampled (`v2/library/algebra.sexp:13,34,55,76` method `:TRUSTED-AXIOM`; `:94…:222` method `:SAMPLED`; origins `:INTEGER-RING-AXIOM` at `:24` vs `(:INSTANTIATED-FROM :LAW-n)` at `:103…:234`). All 12 carry `:STATUS :CONJECTURE`, including the trusted axioms (VERIFIED: `library-summary.txt`).
- Wall-clock for the whole battery: **0.01 s** (VERIFIED: `exp_bootstrap.log`).

**Orientation into a rewrite.** `law-rewrite-rules` (`laws.lisp:247-260`) yields a rule for each side that is an application binding every variable of the other side and of the guard — commutativity gives both directions. Each rule is *compiled into a DSL program over quoted code* (`compile-rule-transformer`, `laws.lisp:284-311`) using `code-match`, `code-bind`, `code-subst`, and fires only when `(code-less replacement source)` (`laws.lisp:306`), i.e. the replacement is strictly smaller in the total order "description size, then canonical packet bits" (`codec.lisp:208-221`). That order makes rewriting terminate and turns commutativity into ordered rewriting. But `INT/COMM-+` is `:sampled`, so `as-rewrite-library` (`laws.lisp:1016`) excludes it: **it is never applied as a rewrite on `:int`**. Its only readers are `induce-fold-motifs` (edge `(:commutative :+)`, `consolidate.lisp:850-853`) and `induce-law-solvers` (whose shape test it fails).

### 1.2 Distributivity (two operators)

- Not attempted, not representable in the filter (finding 3). VERIFIED.
- What the existing engine does when asked (`exp_algebra.log` part B; `a*(b+c)` body = 24 bits, `a*b+a*c` = 34 bits):

| field | work limit | expressions | buckets | both sides seen | same bucket |
|---|---|---|---|---|---|
| GF(3) | 80,000 | 54 | 34 | no | — |
| GF(3) | 2,000,000 | 1,051 | 171 | lhs only | — |
| GF(3) | exhausted at 6,831,983 | 3,477 | 274 | yes | **yes** (bucket of 12 members, representative `(* x0 (+ x1 x2))`) |
| GF(5) | exhausted at 37,182,909 | 3,477 | 336 | yes | **yes** (12 members) |

The battery's own budget for a 3-variable job (80,000) is 85× too small for GF(3) distributivity. Note also 274 vs 336 classes: GF(3) merges classes that GF(5) separates (Fermat artefacts), so the *choice of field changes the equivalence relation* (VERIFIED).

### 1.3 A solver: `x + a = b ⇒ x = b − a`

Two independent paths exist.

**Path A — `milestones/algebra-discovery.lisp` (tests only; "the kernel never calls into milestones/", `load.lisp:2-3`).** VERIFIED by reading and by `exp_solvers.log` part C.
1. `observe-arithmetic-relation` (`:259-274`): run `(op x0 x1)` on the grid `values × values` keeping per-row outcomes including errors; learn the *definedness guard* by searching a Boolean language `{=, if}` with literal 0 for a program that reproduces the defined/undefined mask (`search-membership-frame`, `:230-238`).
2. `orient-arithmetic-requirements` (`:276-292`): build a frame whose rows are contexts `(k, c)` and whose requirement is the *predicate* `R(k,c,z) = (if defined(k,z) (= (op k z) c) nil)` (`:25-32`) — the forward relation is kept as a predicate on the unknown, "without solving fibers".
3. `discover-arithmetic-solver` (`:298-341`): enumerate candidate programs `q(k,c)` over operators `(+ - * /)` and all literals, body bound 16 bits, by observation (`:305-308`); for each, observe the check `R(k,c,q(k,c))` on every row (`:311-316`); rank by number of rows satisfied, then size (`:323-328`); re-verify the top group by `start-search` on the covered rows (`:331-336`).
4. `learn-solver-guard` (`:343-371`): compose a guard from (a) where the witness is defined, (b) a learned Boolean feature for "forward replay equals target", (c) the relation's own definedness; re-check it against the support mask.
5. `validate-arithmetic-solver` (`:49-71`): two laws — witness `R(k,c,q(k,c))` and uniqueness `R(k,c,z) ⇔ z = q(k,c)` under the guard ("validates the WHOLE fiber", `:41-47`) — exhaustive on a field, sampled on `:int`.

Measured: GF(5): 203 candidates, ~0.05 s per orientation; GF(7): 333 candidates, ~0.13 s; `:int` (literals −1,0,1): 89 candidates, ~0.1 s. Results:

| operator, unknown | witness | guard found | GF(5)/GF(7) | `:int` |
|---|---|---|---|---|
| `+`, either | `(- c k)` | `T` | witness + uniqueness `:validated`, certified | both `:conjecture` |
| `*`, either | `(/ c k)` | `k≠0` | certified (20/25, 42/49 active) | guard gains divisibility `(= c (* (/ c k) k))`; `:conjecture` |
| `/`, dividend unknown | `(* k c)` | `k≠0` | certified | witness `:conjecture`, uniqueness **`:refuted`** (truncation) |
| `/`, divisor unknown | `(/ k c)` | `c≠0 ∧ k/c≠0` | certified (16/25, 36/49 active) | uniqueness `:refuted` |

With operators restricted to `{+,*}` the same code finds `c + (−1)·k` (`tests/milestones/algebra.lisp:57-73`). Note `-` and `/` are VM primitives (`ast.lisp:117-145`); the solver search selects among them, it does not invent them.

**Path B — `consolidate.lisp` (what produced `v2/library/arithmetic.sexp`).** VERIFIED by reading and `exp_solvers.log` part D.
1. A hand-written `:spec` of 3–6 rows, e.g. `((2 5) 3) ((4 1) -3) ((-3 7) 10)` for `+`, with `:none` rows for unsolvable contexts of `*` and `/` (`bootstrap/build-batteries.lisp:191-239`).
2. `induce-conditional-solver` (`consolidate.lisp:1386-1510`): witness by plain `start-search` over `default-solver-witness-language` = `(+ - * /)` + literals `(0 1)` (`:1374-1384`), work limit 60,000 (`:1388`); guard = the replay equation itself if it is provably total and separates the rows (`:1466-1479`), otherwise `synthesize-boolean-separator` (`:1248-1372`: observation features, pairwise `=`/`<` predicates from `decompose.lisp:187-217`, greedy decision list to depth 5, heuristic-synthesis fallback).
3. `induce-law-solvers` (`consolidate.lisp:1581-1656`) grants `:uniqueness` when rewriting `W(k, op(k,z))` with the library's certified laws yields `z` (`solver-witness-unique-p`, `:1557-1579`). With the 4 trusted cancellation axioms that succeeds for `+` and `−`, and the evidence is labelled `:trusted-axiom` whenever the library holds *any* trusted-axiom law (`:1640-1643`).

Measured: `+`: 60,132 work, 4 ms; `*`: 93,055 work, guard `(if (= x0 0) nil t)`; `/` (divisor unknown): 93,077 work, guard `(if (= (* x0 x1) 0) nil t)`. Certificates: `+`/`−` → `:TRUSTED-AXIOM (:UNIQUENESS)` (witness *not* attested: `v2/library/arithmetic.sexp:9,26,43,60`); `*` and `/` → **no certificate at all**, only the hand-set flag `:FINITE-UNIQUE-P T` (`arithmetic.sexp:84,97,110,125`; set at `build-batteries.lisp:219,225,231,238`) which makes finite-field instantiations claim uniqueness and re-certify exhaustively at load time (`templates.lisp:446-450`, `consolidate.lisp:1755-1769`).

Whole arithmetic battery: 0.04 s.

### 1.4 How the guard of a conditional *law* is found

`milestones/algebra-discovery.lisp:139-222` (tests: `tests/milestones/guards.lisp`, 8 tests, 112,896 checks, pass). VERIFIED.
1. Observe with `:retain-outcomes t`, so each expression keeps a per-row outcome `:value`/`:error` (`enumerate.lisp:599,822-839`).
2. `observed-support` (`:148-165`): for a pair of expressions, the Boolean row mask "both returned a value and the values are equal".
3. `propose-guard-problems` (`:167-198`): **all pairs** of finished expressions; keep proper non-empty masks; group equations by identical mask; each group becomes a Boolean frame (`support-frame`, `frame.lisp:1397`) — "synthesize the complete observed support, including its false rows".
4. `start-guard-search` (`:200-207`): ordinary enumerative search for a Boolean program reproducing the mask, in a caller-supplied guard language.
5. `propose-guarded-laws` (`:209-222`) attaches the best guard; exhaustive validation then counts `:assignments` and `:active` (e.g. `x/x = 1` under `x≠0`: 5 assignments, 4 active — `tests/milestones/guards.lisp:171-172`).

This is exactly "a conditional is a partition, learned experimentally": the guard is a program fitted to the region of the base space where two expressions agree, and VM errors are first-class outcomes. Limits: O(n²) pairs (the test uses ≤ 114 expressions); the guard language and bound are supplied by the caller — the test's bound is the size of the known answer `(if (= x c) nil t)` (`tests/milestones/support.lisp:18-24,38-39`); buckets themselves only hold expressions that are total on the grid (`enumerate.lisp:768`), so partial expressions enter law discovery only through this pairwise path. With `/` in the language most expressions are partial: 15,372 of 26,823 at a 34-bit bound on GF(7) (VERIFIED: `exp_solvers.log` part E).

A fourth guard mechanism, `milestones/views.lisp:155-217`, enumerates Boolean guards by observation bucket, dedupes partitions up to complement (`:196-198`), solves each side separately and prices `(if g yes no)` against a lookup baseline.

### 1.5 Does the code do what the owner describes?

| Owner's description | In the code | Verdict |
|---|---|---|
| "experimentation (holding all but a few constant) [tells] what is related to what" | `target-sensitive-p` (`laws.lisp:892-929`) swaps one input for ≤ 4 alternatives with the others fixed, to test whether an expression depends on it; its only caller is `orient-conserved-quantity` (`laws.lisp:948`), which has no kernel caller (tests/topology.lisp only). Finite fiber analysis fixes a context and varies the unknown exhaustively (`consolidate.lisp:1426-1442`, `laws.lisp:1152-1158`). Otherwise experiments are full Cartesian grids. | Present in two small places; not a general mechanism. VERIFIED |
| "depth ≥ 2 experiments … expressions themselves can be abstracted over" | AU over law statements as a compression proposal (`milestones/corpus.lisp:202-210`); AU across the eight solver witness laws yields a constructor with operator holes (`tests/milestones/algebra.lisp:205-222`); `lift-field-solvers` compares solvers across fields by AU (`consolidate.lisp:603-691`); `induce-fold-motifs` generalises over operators sharing a law "star" (`consolidate.lisp:833-949`); transformers are code→code programs. | Each exists as a special case with host-coded shape tests; nothing iterates the observation engine over expression-valued inputs. VERIFIED / INFERRED |
| "regions of expression space are connected = equivalent under computation" | Observation buckets (finding 4). | Present, literal, unused beyond law proposal. VERIFIED |
| "guards = calculated regions … where the law does not hold" | §1.4. | Present. VERIFIED |
| "reorientation (conservation ↔ generative expressions)" | `orient-conserved-quantity` + `solve-equality-symbolically` (`laws.lisp:809-992`): unwinds `C(u,T)=const` for `T` through solvers with uniqueness evidence, else falls back to a numeric pulled-back frame. Cannot handle the unknown on both sides: `x + x = 4` returns nil (`tests/topology.lisp:47`). | Present, narrow, no kernel caller. VERIFIED |
| "the kernel, not AI agents, should do the discovering" | `consolidate-knowledge-library`, `propose-observed-laws`, `discover-library-abstractions`, `induce-*` have no caller outside tests and `bootstrap/build-batteries.lisp` (VERIFIED by grep over `*.lisp milestones/ bootstrap/ experiments/ benchmark.lisp`). The decision *that* algebra should be looked for, over which operators and how far, is always a host script's. | Owner's concern confirmed. |

---

## 2. The kinds

All kinds share `knowledge-entry` (`knowledge.lisp:84-102`) and are registered by `define-knowledge-kind` with optional `:validate/:install/:consume/:consolidate` hooks (`knowledge.lisp:36-63`). Instance counts are parsed entries in `v2/library/*.sexp` (92 total; a raw `grep :KIND` double-counts because certificates embed snapshots). LOC are approximate ranges of kind-specific code. All rows VERIFIED by reading unless marked.

| Kind (definition) | Meaningful slots | Producer | Consumer | # in library | Kind-specific LOC |
|---|---|---|---|---|---|
| `:function` (`abstraction.lisp:559`) | inputs→target, expression = body, trigger = I/O predicate, aux = code argument passed to a combinator | `define-function` → `record-function-entry` (`knowledge.lisp:550-629`); AU abstraction (`abstraction.lisp:380-513`); `commit-synthesis-job` (`consolidate.lisp:249`) | VM function table; lifts (`proposals.lisp:6,152`); descriptors | 13 | `abstraction.lisp` 580 + `knowledge.lisp:512-668` |
| `:law` (`laws.lisp:1044`) | inputs, target `:bool`, expression `(= L R)`, guard | `make-law` (`laws.lisp:30`); `propose-observed-laws`; retyping (`templates.lisp:524-562`); motif transfer (`consolidate.lisp:928-940`) | rewrite library (`laws.lisp:1009-1029`); `law-operator-fact`; `induce-law-solvers` | 15 | `laws.lisp:1-426, 994-1057` ≈ 490; `templates.lisp:509-562` |
| `:solver` (`laws.lisp:1337`) | inputs = known context + target value, target = unknown's type, expression = witness, guard, aux = domain guard; metadata `:operator :position :context-map :unique-p :necessary-p :set-valued-p` | `make-knowledge-solver` (`laws.lisp:1184`); `induce-conditional-solver`; `induce-law-solvers`; `lift-field-solvers`; `induce-combinator-solvers` | `propagate-requirements` (`laws.lisp:736`); `solve-equality-symbolically`; metric decoders | 13 | `laws.lisp:447-992, 1059-1349` ≈ 835; `consolidate.lisp:519-691, 1244-1656` ≈ 585 |
| `:transformer` (`templates.lisp:619`) | code-typed inputs → code-typed target, expression = program over quoted syntax | 9 written by hand in `bootstrap/build-batteries.lisp:354-523`; 1 by `learn-knowledge-transformer` (`templates.lisp:598-617`) | by fixed id in `induce-combinator-solvers` (`consolidate.lisp:2004-2010,2029,2045,2055-2058`); `induce-solvers-from-transformers` (`templates.lisp:628`) is dead: it needs metadata `:solver-operator`, which nothing writes | 10 | `templates.lisp:598-653` + ~170 lines of script |
| `:functor` (`consolidate.lisp:2111`) | `(map x1 x0)` + edge `(:lifts-inverter map)` | `consolidate.lisp:2064-2075` | **none** (no `knowledge-entries-of-kind :functor`; edge never read). Serves as an idempotence marker and hosts the `:consolidate` hook | 0 | `consolidate.lisp:1894-2118` ≈ 225 |
| `:motif` (`consolidate.lisp:951`) | target `:bool`, expression `(= (foldr s b f) (foldl s b f))`, edges `(:relates …) (:requires :associative :identity)` | `induce-fold-motifs` (`consolidate.lisp:905-915`) | itself, to transfer to further instances (`:917-948`); the VM can evaluate it as a predicate | 1 | `consolidate.lisp:693-959` ≈ 267 |
| `:relation` (`relations.lisp:223`) | expression = parametric part, residual = lookup/member table, aux = composed program | `commit-synthesis-job` when no exact solution (`consolidate.lisp:335-357`) | its own condensation (`relations.lisp:97-221`) | 0 | 242 |
| `:descriptor` (`descriptors.lisp:175`) | inputs (seq-in, out) → `:bool`; expression = "holds", guard = applicability, aux = non-vacuity witness; edge `(:describes f …)` | `compute-entry-descriptor-profile` on function install, from a **fixed menu of 10 ids** (`descriptors.lisp:463-466,472,488,493,496,533,576`) | soft scoring and (only when `:necessary`) hard rejection of lifts (`descriptors.lisp:966-1045`) | 8 | 1,045 |
| `:decoder-template` (`proposals.lisp:955`) | decoder expression with a distinguished child variable; metadata `:child-id :bindings :lift-p` | `remember-decoder-template` (`proposals.lisp:970`), motif (`:1020`), AU generalisation (`:1033`); 1 hand-written (`build-batteries.lisp:712-734`) | `learned-decoder-decompositions` (`proposals.lisp:1331`) | 1 | ≈ 250 |
| `:locality-key` (`proposals.lisp:625`) | inputs → `:int` | `with-induced-row-order` (`proposals.lisp:789-822`) | `stored-row-keys` (`proposals.lisp:691`); corpus scheduling (`milestones/corpus.lisp:464-507`) | 0 | ≈ 200 |
| `:nogood-schema` (`consolidate.lisp:170`) | Boolean clause pattern (may hold holes), guard = parent clause, aux = decoder | `commit-synthesis-job` (`consolidate.lisp:298-309`) | `nogoods.lisp:323` | 0 | ≈ 60 + `nogoods.lisp` |
| `:dip-feature` (`consolidate.lisp:203`) | separator expression | `commit-synthesis-job` (`:310-333`) | `nogoods.lisp:519` | 0 | ≈ 30 |
| `:heuristic` (`consolidate.lisp:237`) | 6 `:int` trace features → `:int` priority, residual | `consolidate-knowledge-library` (`:1039-1048`) | `knowledge-library-priority-predictor` (`synthesize.lisp:185`) | 0 | ≈ 130 |
| `:spec` (`consolidate.lisp:1085`) | residual = I/O rows (`:none` for unsolvable), edge `(:specifies id)`, metadata operator whitelist | written by hand in the bootstrap script | `synthesize-spec-entry` (`consolidate.lisp:1208`), `induce-conditional-solvers` (`:1512`), `verify-entry-against-spec` (`:1155`) | 31 | ≈ 185 |

Provenance of the 61 non-spec entries (VERIFIED from `library-summary.txt` + script):
- Laws (15): 4 hand axioms; 8 from GF(3) observation (4 identity, 2 commutative, 2 associative); 3 `cons` laws written by hand and checked on 4 samples (`build-batteries.lisp:311-321`).
- Solvers (13): 8 arithmetic and 3 `cons` from hand specs; `:solve-at-1` synthesised then attested `:sampled`; `:solve-shift-seq-by-correlation` from a hand spec.
- Functions (13): `:map`, `:foldr` by AU over six synthesised functions; ten synthesised from hand specs with 2–8-operator whitelists; `:scan-pair` by type instantiation.
- Transformers (10): 9 hand-written, marked `:status :validated` by assignment (`build-batteries.lisp:359`) after replaying one example each; 1 "synthesised" from one training row in a language of one operator and the two needed constants (`build-batteries.lisp:475-494`).
- Motif (1): induced from two hand-defined instances with hand-added `:refactored-by` edges (`build-batteries.lisp:745-753`).

### 2.1 Which kinds are the same thing

Reading each entry as *a guarded relation among typed ports, read in some direction, at some evidence grade* (INFERRED, each line grounded in the cited code):

- **A term read forward, plus a role tag:** `:function`, `:transformer` (the same with code types; its validate hook only asserts a code target, `templates.lisp:621-624`), `:locality-key` (a function used as a coordinate), `:dip-feature` (a function used as a separator), `:heuristic` (a function over trace features).
- **A Boolean relation over ports with a guard:** `:law` (`(= L R)` under guard), `:descriptor` (`guard(x) ⇒ holds(x, f(x))` — a law about one function's graph, stated over (in, out) instead of with `=`), a function's `:trigger` slot (the same predicate stored on the function, `descriptors.lisp:875-878`), `:motif` (a law quantified over a code-valued port whose precondition is stored as an edge rather than an executable guard), `:nogood-schema` (a negative relation).
- **A relation with a distinguished unknown port:** `:solver` (law `op(k,z)=c` read `(k,c) ↦ z`, with uniqueness and necessity as claims about the fiber) and `:decoder-template` (`y = d(z, params)` with `z` to be solved for).
- **An extensional relation:** `:spec` (rows) and `:relation` (rows + parametric part).
- **A tag:** `:functor`.

The graph structure the library already has: `edges` on each entry, indexed in `incoming-edges` (`knowledge.lisp:308-314`). About 30 edge keys are written; only ~10 are ever read by `knowledge-edges-from/to` — `:describes`, `:specifies`, `:metric-decoder`, `:abstracts`, `:refactored-by`, `:not-instance`, `:no-identity`, `:licensed-by`, and the operator facts via an unfiltered read (`consolidate.lisp:770`). `:governs`, `:inverts`, `:induced-by`, `:lifted-from`, `:retyped-from`, `:implied-with`, `:relates`, `:requires`, `:generalizes`, `:lifts-inverter`, `:induced-from-spec`, `:archived-with`, `:repairs` are write-only provenance; `:laws` and `:functor-laws` are read (`descriptors.lisp:902-903`) but never written (VERIFIED by grep).

### 2.2 Conversions between kinds

| Conversion | Where | Generic or shape-specific | What it loses |
|---|---|---|---|
| law → rewrite rule(s) → VM program | `laws.lisp:247-311` | generic | needs current evidence; direction decided per application by `code-less`; no AC matching; a guarded rule fires only if its instantiated guard is literally `'t` or syntactically among the enclosing `if` conditions (`laws.lisp:304`); every bound subterm must be provably total (`:308-309`) |
| law → operator-fact edge | `consolidate.lisp:709-735` | **3 shapes** | every other law |
| law → solver | `consolidate.lisp:1591-1639` | **one shape**: `(= (op a… W …a) c)` with `c` and the other arguments distinct variables covering all inputs | guard copied; uniqueness not implied |
| solver → laws (for validation only) | `milestones/algebra-discovery.lisp:34-47`; `consolidate.lisp:573-601` | generic | laws are not registered |
| solver + certified laws → uniqueness | `consolidate.lisp:1557-1579` | generic (rewrite round-trip to the unknown) | limited to what ordered rewriting can normalise |
| solvers over ≥ 2 fields → `:int` solver | `consolidate.lisp:603-691` | generic test (AU without holes) + sampling | becomes `:sampled` |
| law(field) → law(`:int`) | `templates.lisp:524-562` | generic (type-template unification) | certificate |
| law star + folds → motif → per-instance law → decoder template | `consolidate.lisp:737-949`; `proposals.lisp:1020-1031` | **fold signature and monoid star hard-coded** | — |
| element solver × combinator → sequence solver | `consolidate.lisp:1927-2079` | **map-like signature, pointwise binary step, fixed transformer ids** | — |
| functions → combinator + refactored calls | `abstraction.lisp:230-513` | generic AU + recursion-idiom heuristics (`unify.lisp:149-160`) | — |
| function → descriptors / trigger | `descriptors.lisp:130-148, 392-581, 862-913` | **fixed menu** | — |
| table → expression | `relations.lisp:97-221` | generic search | — |
| decoder templates → generalised template | `proposals.lisp:1033-1098` | generic AU, exactly one hole | — |
| conservation + solvers → closed form | `laws.lisp:809-992` | generic unwinding, unknown in one place only | — |
| entry → type template → instance | `templates.lisp:68-507` | generic over kinds; per-primitive typing cases at `:169-265` | certificates never copy (`:396-397`) |
| spec → function / solver | `consolidate.lisp:1208-1242, 1386-1555` | generic search within a hand-given operator whitelist | — |

---

## 3. Anti-unification

**One implementation**, `anti-unify` (`unify.lisp:36-73`). VERIFIED.
- n-ary, typed, syntactic, first-order least general generalisation. Alignment is purely positional: applications are aligned when they have the same operator *signature* (with `:operator-holes-p t`, the operator position itself may become a hole of function sort) or the same operator (`nil`); otherwise the whole subterm becomes one hole (`:56-66`). No permutation of arguments is tried; no alignment search.
- "Equal disagreement tuples reuse the same hole" (`:45-50`): the table from a tuple of disagreeing subterms to its hole is what makes the result *least* general — this is the quotient step the owner refers to.
- Cost: one ledger unit per source per node (`:52`) plus a `match-pattern` of each source to recover its substitution (`:69-73`); linear.
- `match-pattern` (`unify.lisp:13-34`): typed first-order matching, non-linear patterns, holes allowed in operator position.

**How AU output becomes something usable**
1. *Constructor-AU*: `compile-au-constructor` (`unify.lisp:103-121`) lowers a pattern to a DSL program that maps quoted hole fillings to the instantiated quoted expression via `code-apply`. `au-substitutions-frame` (`unify.lisp:75-101`) packages the substitutions as an ordinary frame whose rows require tuples of quoted fillings — the "labelled residual lifted to independent contexts", as a new synthesis problem. It has no kernel caller (tests only; VERIFIED by grep).
2. *AU on `:code` targets*: `constructor-au-product` (`proposals.lisp:487-…`) anti-unifies the code-valued targets of a frame and proposes a product decomposition with one child slot per hole (≤ `*product-arity-limit*` holes).
3. *Library abstraction*: `anti-unify-for-library` (`abstraction.lisp:98-120`) calls AU with operator holes off and a `keep-application-p` predicate that preserves "recursive control spines" (an `if` whose guard is shared, self-calls, constructors wrapping self-calls) and collapses other differences. `abstraction-parameters` (`abstraction.lisp:181-228`) turns each hole into a first-order parameter, or into a `:code` parameter applied to a *shared subterm cover* — `(code-eval F a1 … am)` where the `a_j` are subterms common to all fillers (`shared-subterm-cover`, `unify.lisp:134-209`; `abstract-over-subterms`, `:211-241`). This is a restricted second-order generalisation; the cover's "atomic units" are hand-listed list-recursion idioms: a bound variable, `(tail X)`, `(at X c)`, a self-call (`unify.lisp:149-160`).
4. Others: UIP nogood patterns (`nogoods.lisp:218-250`); decoder-template generalisation (`proposals.lisp:1033-1098`, AU call at `:1075`); `code-edit`, which prices a correction between two quoted expressions by the holes of their anti-unifier (`frame.lisp:1583-1625`) — a metric on syntax; corpus compression (`milestones/corpus.lisp:202-210, 704-768`); the no-holes test in `lift-field-solvers`.

**MDL acceptance test** (`abstraction.lisp:380-464`): `gain = Σ S(p_i) − (S(L) + Σ S(p_i | L)) > min-gain` with `S` = `body-size` (`:44-55`). Search over subsets within one signature group: the whole set, then every pair, each pair grown greedily while gain improves, memoised by subset (`greedy-subset-search`, `:347-378`) — O(n²) pairs, O(n³) AU calls worst case. The test `kernel-higher-order-abstraction-and-compression-contract` shows a 2-function fold pair has negative gain and the 6-function corpus yields exactly two combinators (`tests/abstraction.lisp:94-119`; passes).

**Available to synthesised programs?** Root: no — AU is host Lisp. Synthesised programs do have `code-match`, `code-bind`, `code-subst`, `code-apply`, `code-child`, `code-operator`, `code-kind`, `code-total`, `code-less` (`ast.lisp:130-138`; `vm.lisp:172-205`), i.e. matching and substitution but not generalisation. v2 adds `:code-anti-unify` (`v2/ast.lisp:155`, `v2/vm.lisp:201-202`, `v2/unify.lisp:75-103`): binary, operator holes off, holes lowered onto extra scope variables; **no caller and no test** in v2 (VERIFIED by grep over `v2/**/*.lisp`).

**AU modulo laws?** No. The only interaction is pre-normalisation: `normalize-trees-with-library` (`abstraction.lisp:7-21`) rewrites each tree to normal form before AU when a rewrite library is passed (`abstraction.lisp:253-256, 402-412`; `milestones/corpus.lisp:712-714`), plus one hand-coded canonicalisation of `(if (= Xi 'c) …)` (`abstraction.lisp:67-79`). On `:int` the rewrite library is the 4 cancellation axioms (finding 5), so commutativity and associativity play no part in alignment (INFERRED).

---

## 4. Use of laws in search

- **Mechanism** (`enumerate.lisp:345-351, 417-424, 472-498`). VERIFIED. With `:laws`, each admitted candidate is rewritten to normal form; if a candidate with the same normal form was already *refuted by a row*, the new one is rejected without evaluation (`reused-rejections`). The normal form is a cache key only: enumeration is not pruned, accepted candidates are not deduplicated, and the candidate itself (not its normal form) is what gets evaluated.
- **Rewriting** (`laws.lisp:313-426`). VERIFIED. Innermost: walk children, then try each rule whose pattern head matches (`:345-349`); on a change, re-walk the replacement (`:401-404`). `if` branches carry path assumptions (`:364-368`). Rules run as prepared DSL programs in the metered VM (`:284-311, 338-343`), cached per (VM versions, scope) (`:325-336`).
- **Termination**: the strict order `code-less` (`laws.lisp:306`; `codec.lisp:208-221`). Test: `exhaustive-rewrite-preservation-on-tiny-grammar` checks size never increases and outcomes (including errors) are preserved (`tests/laws.lisp:223-241`).
- **Conditional laws**: applied only under a syntactically identical enclosing `if` test or a literally true guard (`laws.lisp:304`); test at `tests/laws.lisp:136-161`.
- **Constant folding** is a separate host routine (`fold-constants`, `requirements.lisp:529`) used on requirements (`frame.lisp:251`, `fibers.lisp:18`, `nogoods.lisp:190`, `proposals.lisp:118`) and in `simplify-symbolic-expr` (`laws.lisp:788-807`); it does not use laws.
- **Wired in?** Root: no. `start-search` accepts `:laws` (`enumerate.lisp:353`) but none of root's non-test call sites passes it (VERIFIED by grep: `synthesize.lisp:629, 876, 1128`; `consolidate.lisp:1450`; `relations.lisp:162`; `templates.lisp:604`; `benchmark.lisp:51`; `milestones/algebra-discovery.lisp:205, 233, 333`; `milestones/propagation-search.lisp:15, 16, 36`). v2: `node-rewrite-laws` (`v2/synthesize.lisp:865-876`) passes the knowledge library's certified laws at `:908` and `:1163`, with `current-rewrite-library` (`v2/laws.lisp:317-326`) to survive function-table version bumps. `v2/STAGE0_RESULTS.md:19` reports the effect as H2 checks 69,667 → 69,171.
- **Cost/benefit measured** (`exp_rewrite.log`; frame `y = a + 2b` on GF(5), language `{+,*}` + all literals, bound 61 bits, 649 candidates):

| configuration | total work | of which rewriting | reused rejections | results |
|---|---|---|---|---|
| no laws | 182,181 | 0 | 0 | 10 |
| 1 law (`x+0=x`) | 741,101 | 546,570 | 31 | 10 |
| 80 validated depth-1 laws | 70,181,164 | 70,086,191 | 502 of 639 | 10 |

The filter does recognise 79% of rejections as repeats, but pays ~660× what it saves.

---

## 5. Solvers, propagators, transformers, metric decoders

**`propagate-requirements`** (`laws.lisp:736-784`). VERIFIED.
- Works on each top-level conjunct of each row's requirement that has the form `(= (op 'k T) 'c)` or `(member (op 'k T) '(c1…cm))`, m ≤ 8 (`:674-687`). "Only conjuncts are rewritten: a narrowing is not sound under negation."
- Dispatch: rules indexed by (typed operator, set of open argument positions) (`:658-672`). For each target value: evaluate the known arguments (`:585-598`), run the rule's guard and then witness as prepared VM programs (`:600-611`, cache `:545-556`).
- Outcome per value: witness accepted if the rule's witness evidence is current, otherwise only if `op(known, witness)` replays to the target (`:624-631, 727-730`); guard false + necessity evidence refutes the value (`:613-622`); set-valued witnesses list every solution (`:633-638, 717-726`).
- The conjunct becomes `(= T 'w)`, a `member` set, or false (`:640-656`); the loop repeats so nested operators unwind (`:754-765`).
- Bookkeeping: `narrowed` (all rules certified), `suggested`, `ambiguous` (uniqueness not current), `rejected`; the original frame is kept as `fallback` whenever anything was suggested or ambiguous (`:776-783`).
- Called from `prepare-synthesis-node`: first with rules that invert defined functions, before folding can unfold the call (`synthesize.lisp:578-582`; `laws.lisp:527-543`), then on the folded frame (`synthesize.lisp:585-592`). Also `milestones/views.lisp:147`. `milestones/propagation-search.lisp` runs the narrowed and original frames as lanes, reserving every fourth quantum for the original and re-verifying narrowed candidates forward (`:50-59, 31-37`).

**`arithmetic-propagator`** (`laws.lisp:451`) is just a prepared `:solver` entry: operator, position, witness, guard, inputs, context-map, source entry, source snapshot (`:465-475`). Despite the name it is generic — it inverts `:cons`, `:at`, and defined functions such as `:shift-seq`.

**Transformers** are code→code programs evaluated in the VM; "a transform is never itself a rewrite law" (`templates.lisp:600-602`). A solver works on *values* at node-preparation time; a transformer works on *syntax* at consolidation time, turning an element solver's witness/guard code into the witness/guard code of the solver for the mapped operator (`consolidate.lisp:1998-2014`). Which transformer applies where is decided by host code with fixed ids.

**Metric decoders.** `register-metric-decoder` (`laws.lisp:1250-1275`) marks a solver that inverts `d : (τ, δ) → τ` in `δ` as a residual metric of `τ` (edge `(:metric-decoder d q tag-bits)`); it requires the witness to be provably total under its guard, not certified, "since every delta is replayed". `metric-delta` (`laws.lisp:1314-1327`): `δ = q(p, y)`, replay `d(p, δ) = y`, price = tag bits + bits of `δ`. Consumers: `priced-correction` (`frame.lisp:1646-1669`) where each decoder competes with the built-in correction packet; observation-bucket residual pricing (`enumerate.lisp:750-755`); Stage A (`condense.lisp:91`); Stage B decomposition `Y = d(PROGRAM(X), Z)` (`decompose.lisp:30-83`); row-order induction (`proposals.lisp:723`).

The single instance (`v2/library/sequence-shift.sexp:126-141`): `:shift-seq` with solver witness `(argmax-corr x0 x1)`, guard `(= (shift-seq x0 (argmax-corr x0 x1)) x1)` (the replay equation), tag 14 bits. `argmax-corr = (at (best-shift x0 x1 0) 1)`; `best-shift` recurses over the tails of `x0`, keeping the tail offset with the largest `seq-corr` (a dot product). It is triggered automatically whenever a frame's target type is `(:seq :int)` and the battery is loaded. It was built as a five-step curriculum of hand specs, each with its own operator whitelist — e.g. `:spec/best-shift` lists `seq-corr` among its operators and `:spec/argmax-corr` lists only `(best-shift at)` (`bootstrap/build-batteries.lisp:834-932`). The whole battery builds in 0.08 s.

---

## 6. Evidence

**Grades** (`evidence.lisp`, 73 lines). VERIFIED.
- A certificate is `(:method m :obligations (…) :snapshot s)` (`:45-50`). The snapshot binds evidence to the statement: simulator and encoding versions, kind, domain, inputs, target, the four code slots, solver context, and the transitive definitions of every function mentioned (`:23-43`). Editing the entry invalidates its evidence.
- *Current* evidence = method ∈ `{:exhaustive, :derived, :trusted-axiom}` (`:62-65`); *tested* adds `:sampled` (`:67-73`). "A status label alone never authorizes semantic elimination."
- Obligations in use: `:equivalence` (laws), `:witness`, `:uniqueness`, `:necessity` (solvers), `:necessary` (descriptors).
- The `status` slot (`:empirical :conjecture :validated :refuted :vacuous`) is a label, separate from the certificate. Law validation statuses: `:validated` only when exhaustive, `:conjecture` for surviving samples, `:vacuous` when the guard was never active, `:refuted` with a counterexample (`laws.lisp:124-127, 162-170`). "Samples NEVER certify a law" (`laws.lisp:97`).
- Several entries carry non-evidence certificates of the form `(:kind …)` — `:structural-totality` (`knowledge.lisp:579-581`), `:uip-anti-unification`, `:dip-row-separator`, `:trace-priority-predictor`, `:empirical-table`, `:induced-row-order` — which have no `:method` and therefore never count as evidence.

**Where the code refuses an uncertified fact**
| Site | Rule |
|---|---|
| `laws.lisp:1016` | only current `:equivalence` laws enter a rewrite library |
| `laws.lisp:272-282` | `prepare-rewrite-library` asserts validated, same domain, unchanged statement |
| `laws.lisp:322`, `:496-507` | stale rewrite/propagator libraries are errors (version checks) |
| `laws.lisp:558-568` | a rule counts only while its entry still states what the rule was prepared from |
| `laws.lisp:727-730` | an uncertified witness must replay forward |
| `laws.lisp:761-771, 781-783` | uncertified or non-unique narrowing keeps the original frame |
| `laws.lisp:850` | symbolic unwinding uses only rules with some uniqueness evidence, and reports `certified-p` |
| `consolidate.lisp:625` | only witness-certified field solvers are lifted |
| `consolidate.lisp:698-707, 1632-1634` | motifs and law-solvers rest only on tested laws |
| `descriptors.lisp:807-830, 1019-1020` | only a current `:necessary` descriptor can hard-reject a lift |
| `templates.lisp:396-397, 471-480` | certificates never copy across types; finite instances re-certify |
| `milestones/algebra-discovery.lisp:73-80` | a discovery is certified only with exhaustive forward evidence and both validations current |

**Soft spots** (VERIFIED by reading):
- `milestones/algebra-discovery.lisp:119-125` attests an *integer* rule's uniqueness as `:derived` (current) on the strength of a sampled conjecture. Soundness survives because the witness is not current, so the fallback is kept (`tests/milestones/algebra.lisp:128-143`), but the grade is mislabelled.
- `laws.lisp:615, 719` accept *tested* (sampled) necessity to refute a value; the row is then only "suggested", so again the fallback covers it.
- `consolidate.lisp:1640-1643` labels a uniqueness derivation `:trusted-axiom` if the library holds any trusted-axiom law.
- The 9 hand-written transformers are `:status :validated` with no certificate; the 4 trusted axioms are `:status :conjecture` with a current certificate (`v2/library/algebra.sexp:4-24`).
- There is no evidence method for infinite domains other than `:trusted-axiom`. Consequently every `:int` and `(:seq :int)` fact in the library is a sampled conjecture, a hand axiom, or uncertified.

---

## 7. The equivalence reading

**Where the code already keeps classes or treats laws as merges** (VERIFIED):
1. `observation-bucket` (`enumerate.lisp:604-605, 762-781`): hash from `(type, row-values)` to the list of expressions with that behaviour. This *is* a behaviour-equivalence class table over the scope's rows; `propose-observed-laws` just prints each class as a star of equations.
2. `rejection-cache` keyed by normal form (`enumerate.lisp:396-398, 496-498`): refutation shared across a class, with rewriting as the canonical-representative function.
3. `scope-cache` keyed by `child-scope-signature` (`synthesize.lisp:70, 264, 855-877`): identical sub-problems share one search.
4. Partition dedupe up to complement in view discovery (`milestones/views.lisp:173, 196-198`).
5. The AU disagreement table (`unify.lisp:45-50`).
6. Shared polymorphic descriptors: one entry, many `:describes` targets, merged when one instantiates to the other (`descriptors.lisp:679-698, 764-776`).
7. `quotient-values` / `quotient-model` (`frame.lisp:1443, 1463`; used by `milestones/corpus.lisp:128-134`) — representatives plus residual for a list of values.

Terms themselves are not shared: variables and operators are interned in `*typed-symbol-pool*` (`ast.lisp:582-680`), literals and applications are fresh conses with side metadata (`ast.lisp:1110-1116`), and identity is `equal` on trees; the hash tables above are ad hoc hash-consing.

**If terms lived in one shared graph with an equivalence relation on nodes** (INFERRED):

*Would collapse into "merge two nodes" or "read a relation in another direction":*
- observation buckets → the classes; `propose-observed-laws` → nothing to do;
- registering a law → a merge carrying a guard and a grade;
- normal-form rewriting + rejection cache + `code-less` orientation → class lookup and cost-based extraction (description size is already the cost);
- pre-normalisation before AU → AU over classes;
- `induce-law-solvers`, `solve-witness-law`, `sampled-solver-validations` → the same n+1-ary edge `op(k,z)=c` read from different port subsets; uniqueness = "this reading is functional", necessity = "this reading is total";
- `solver-witness-unique-p` → a congruence query (is `W(k, op(k,z))` in the class of `z`?);
- `solve-equality-symbolically` → walking edges from the unknown port toward known ports;
- `law-operator-fact`, `monoid-fold-instance`, `map-like-combinator-signature` → sub-graph patterns over law and definition edges (still to be written, but as data, not host predicates);
- `lift-field-solvers`, `retype-law`, `instantiate-entry-template` → substitution on type ports of one polymorphic node;
- `:refactored-by` / `:abstracts` → the substitution edges AU already computes.

*Would not collapse:*
- **The experiments.** Classes are found by running the VM on a finite grid; a graph stores the result, it does not produce it.
- **Domain-indexing and grades.** The relation depends on the domain: 274 classes on GF(3) vs 336 on GF(5) for the same 3,477 expressions, and 16 of 187 GF(3)-true equations are false on `:int`. Union is transitive, so a single ungraded class structure would let one sampled merge contaminate certified ones. Each merge needs its domain and evidence grade.
- **Guards.** A conditional law is equality on a *row subset*. Its natural carrier is the rows × expressions outcome table (support masks), which is what frames provide; guard synthesis is program search against a mask (§1.4).
- **Partiality.** Rewrites fire only on provably total bindings (`laws.lisp:308-309`); buckets exclude partial expressions. Merges are valid only where both sides are defined.
- **Search and pricing.** Witness and guard synthesis, MDL gain tests, totality analysis, metering, amortisation.
- **Metric notions.** `priced-correction`, `code-edit`, metric decoders, locality keys concern distance, not equivalence.
- **Evidence snapshots.** They hash statement text and dependencies; with shared nodes they would need content-addressed node identity.

---

## 8. Importable pieces

All tests below were run on the root kernel and pass (`test-*.log`), except where noted.

| Piece | Files / lines | ≈ LOC | Tests (count, checks, wall) | Verdict |
|---|---|---|---|---|
| Observational equivalence engine (scope, outcomes, buckets, resumable job) | `enumerate.lisp:563-877` | 315 | `tests/laws.lisp`, `tests/observations.lisp`, guards | Works; the heart of algebra discovery. Depends on the enumerator and row-job base in the same file. |
| Law object, exhaustive finite-field certification, sampled testing with counterexamples, resumable | `laws.lisp:1-228` | 228 | `tests/laws.lisp` 12 tests, 9,416 checks, 0.4 s | Works. Includes tuple and Boolean finite types (`:22-28, 66-90`). |
| Evidence grades + statement snapshots | `evidence.lisp` | 73 | exercised throughout; `tests/topology.lisp:427-…` "a claim of uniqueness authorises nothing without evidence" | Works; small; principled. Fix the soft spots in §6. |
| Persistence (plist per entry, AST/data/hybrid slots, priority-ordered install, forward declarations) | `persistence.lisp` | 141 | `tests/library.lisp`, `tests/batteries.lisp` (not run by me: they write files) ; round-trip verified indirectly — regenerated library is byte-identical to `v2/library` | Works. Entry-centric: one flat list plus an edge list per entry. |
| Rewrite rules as VM programs over quoted code; definedness-preserving, terminating normaliser | `laws.lisp:230-426` | 197 | `tests/laws.lisp:136-241` | Correct but expensive (§4). Import the soundness conditions, not the cost model. |
| `propagate-requirements` with witness replay, necessity refutation, set-valued witnesses, fallback | `laws.lisp:447-784` | 338 | `tests/milestones/algebra.lisp` 8 tests, 27,871 checks, 3.8 s; `propagation` 5 tests | Works; wired into root synthesis. |
| Solver schema + exhaustive fiber certification (witness / uniqueness / necessity) | `laws.lisp:1059-1244` | 186 | algebra, topology | Works; cap of 65,536 fiber checks (`:1136`). |
| Symbolic unwinding and conservation orientation | `laws.lisp:786-992` | 207 | `tests/topology.lisp` | Works within "unknown occurs once per level"; no kernel caller. |
| Metric decoders | `laws.lisp:1246-1335` | 90 | `tests/metrics.lisp`, `totality`, `audit` (not run by me) | Small, clean interface. |
| AU, matching, constructor compilation | `unify.lisp` | 255 | `tests/abstraction.lisp` 2 tests, 106 checks; `corpus` 7 tests | Works; first-order. |
| MDL-gated higher-order abstraction | `abstraction.lisp` | 580 | same + `tests/recursion.lisp` | Works on the 6-function corpus; cover heuristics are list-specific. |
| Guard discovery from support masks | `milestones/algebra-discovery.lisp:139-238` | 100 | `guards` 8 tests, 112,896 checks, 14.5 s | Works; O(n²). |
| Solver discovery from forward observations | `milestones/algebra-discovery.lisp:1-137, 240-371` | 270 | algebra | Works on 4 operators × 3 domains. |
| Type-template inference / instantiation | `templates.lisp:1-507` | 507 | laws (retyping), batteries | Works; per-primitive cases hand-written. |
| Law-corpus and tree-corpus compression by AU | `milestones/corpus.lisp` | 768 | `compression` 5 tests, 42,874 checks; `corpus` 7 tests | Works as a demonstration; exact bit pricing. |

Not worth importing as is (INFERRED): the shape recognisers of §2.2, the fixed descriptor menu, the nine hand-written transformers, `induce-solvers-from-transformers` (dead), `:functor` entries (unread), the battery loader's per-kind install switch (`consolidate.lisp:1735-1800`).

Root test caveat: `tests/run.lisp theories` failed on the tracked tree with "No battery packet :SEQUENCES at …/library/sequences.sexp" because root has no tracked `library/` directory (`git ls-files library` is empty; `tests/support.lisp:534-542` loads batteries). v2's `theories` passes (3 tests, 126 checks).

---

## 9. v2 differences in my scope

`diff` counts (changed lines): `laws` 22, `unify` 30, `evidence` 12, `knowledge` 1, `consolidate` 56, `templates` 77, `descriptors` 75; `abstraction`, `relations`, `persistence`, all `milestones/*`, `bootstrap/build-batteries.lisp` 0. VERIFIED.

- `v2/laws.lisp:317-326` `current-rewrite-library`; `:446-448, 458-459, 475-476` `*propagation-eval-budget*` = 100,000 with cutoff instead of assertion.
- `v2/unify.lisp:75-103` `code-anti-unify-values`; primitive `:code-anti-unify` — unused.
- `v2/evidence.lisp:64-71` methods `:pit`, `:ind1` accepted as current — no producer.
- `v2/knowledge.lisp:119` slot `op-props` "law-activated (:assoc :comm :id :cancel), empty at t=0" — never read or written.
- `v2/templates.lisp:565-596` `default-law-samples` (fixes retyped laws being tested on zero samples and discarded as vacuous, per `v2/STAGE0_RESULTS.md:27-29`); typing cases for new primitives `:tabulate :evolve :code-quote :code-value :code-anti-unify` (`:241-269`).
- `v2/consolidate.lisp:1208-1247` `*use-active-library-grammar*` (off by default): ignore the per-spec operator whitelist and use all primitives + active library functions.
- `v2/descriptors.lisp:862-904` `*enable-host-descriptor-synthesis*` (on by default) with a library-matching alternative.
- Laws wired into node search (§4).

The three stubs (`:code-anti-unify`, `:pit`/`:ind1`, `op-props`) are the visible edge of the unfinished Stage 1.

---

## 10. What I could not determine

- Whether class-based enumeration would in fact reach the growth factor suggested by bucket counts (×~5 per leaf): the ratio is measured, the consequence is inferred; partial expressions and multi-type languages would complicate it.
- The benefit of v2's law wiring on real synthesis workloads beyond the one figure in `v2/STAGE0_RESULTS.md:19`; I measured only the root mechanism on one fixture.
- Behaviour of `tests/batteries.lisp`, `tests/library.lisp`, `tests/audit.lisp`, `tests/metrics.lisp`, `tests/totality.lisp` — not run (two of them write files; the rest need batteries).
- How non-terminating candidates behave in root observation jobs. v2 adds a per-row budget (`v2/STAGE0_RESULTS.md:36-38`); I did not test root.
- Who created `/home/tlh24/lisploop/library/` during the audit.

---

## Appendix — enumeration scaling (root kernel, `exp_solvers.log` part E)

Exhaustive observation over the full grid. Work limit 3·10⁹ per job. "total on grid" = expressions that return a value on every row (only these are bucketed). For these languages body bits = 10 × leaves − 6 (3 leaves = 24, 4 = 34, 5 = 44, 6 = 54).

| field, vars, ops | slack | exprs | total on grid | buckets | work | wall | claim |
|---|---|---|---|---|---|---|---|
| GF(5), 2, `+ *` | 24 | 74 | 74 | 27 | 1.1·10⁵ | 0.00 s | exhausted |
| | 34 | 714 | 714 | 95 | 1.3·10⁶ | 0.02 s | exhausted |
| | 44 | 7,882 | 7,882 | 338 | 1.8·10⁷ | 0.22 s | exhausted |
| | 54 | 93,898 | 93,898 | 1,258 | 2.5·10⁸ | 3.12 s | exhausted |
| GF(5), 3, `+ *` | 24 | 237 | 237 | 68 | 2.1·10⁶ | 0.03 s | exhausted |
| | 34 | 3,477 | 3,477 | 336 | 3.7·10⁷ | 0.74 s | exhausted |
| | 44 | 57,909 | 57,909 | 1,762 | 7.3·10⁸ | 10.35 s | exhausted |
| | 54 | 212,282 | 212,282 | 5,286 | 3.0·10⁹ | 34.87 s | cutoff |
| GF(5), 3, `+ * −` | 24 | 516 | 516 | 150 | 4.5·10⁶ | 0.05 s | exhausted |
| | 34 | 11,451 | 11,451 | 1,078 | 1.2·10⁸ | 1.44 s | exhausted |
| | 44 | 236,794 | 236,794 | 6,890 | 3.0·10⁹ | 31.82 s | cutoff |
| GF(7), 3, `+ * − /` | 24 | 903 | 516 | 150 | 1.2·10⁷ | 0.18 s | exhausted |
| | 34 | 26,823 | 11,451 | 1,102 | 3.4·10⁸ | 5.28 s | exhausted |
| | 44 | 195,893 | 87,236 | 3,338 | 3.0·10⁹ | 42.21 s | cutoff |

Throughput ≈ 7–9·10⁷ work units/s; ≈ 5–7 thousand 125-row expressions per second.
