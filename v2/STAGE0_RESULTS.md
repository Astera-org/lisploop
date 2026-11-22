# Stage 0 Results (`v2/`): Soundness Fixes (`E0a`) & Battery/Distractor Audit (`E0b`)

This document records the empirical baseline and audit outcomes of **Stage 0** in [`v2/`](file:///home/tlh24/lisploop/v2), corresponding to [`plan_v2.tex`](file:///home/tlh24/lisploop/plan_v2.tex) §6 (Stage 0: `E0a` + `E0b`). All root (`v1`) files remain untouched at baseline `df33ed1`.

---

## 1. Gate Summary & Verification Metrics

| Gate / Check | Baseline (`v1` / pre-`E0a`) | Post-Stage 0 (`v2/`) | Status |
| :--- | :--- | :--- | :--- |
| **Kernel unit suite** (`make test`) | 222 tests | **228 tests**, **938,281 checks** (`5.00 s`, incl. 6 new `stage0` tests) | PASS |
| **Milestone suite** (`make test`) | 40 tests | **40 tests**, **186,771 checks** (`11.91 s`) | PASS |
| **Cold battery bootstrap** (`make bootstrap`) | 8 `.sexp` batteries | **8 `.sexp` batteries** (`61` entries, `31` specs in `0.34 s`) | PASS |
| **Plan 8 probes** (`make probes`) | `71,782` / `212,096` / `34,067` / `62,942` | **`71,782` / `212,096` / `34,067` / `62,942`** (bit-for-bit identical) | PASS |
| **Pure-kernel `cccc` cognitive** (`26` modules) | sum `6,515`, max `141`, p95 `20` | **sum `6,658`** (`+143`), **max `141`**, median `1`, p95 `20` | PASS |
| **Pure-kernel `cccc` cyclomatic** (`26` modules) | sum `6,338`, max `74`, p95 `15` | **sum `6,448`** (`+110`), **max `74`**, median `2`, p95 `15` | PASS |
| **All-`v2` `cccc` cognitive** (`35` modules) | sum `7,376`, max `311`, p95 `20` | **sum `7,519`** (`+143`), **max `311`**, median `1`, p95 `20` | PASS |

**Ledger fingerprint diff (`experiments/ledger-fingerprint.lisp`):** Across all `2,772` lines of benchmark ledger categories, every suite is bit-identical except `HIGHER-ORDER-H1` and `HIGHER-ORDER-H2`, where `H2` checks **decreased** (`69,667 -> 69,171`) and `PREPARATION` / `SIMPLIFICATION` work slightly **improved** (`117,433 -> 117,079`) because active certified algebra laws now wire into prepared node searches (`E0a-3`) and coupled fallback rows no longer pay redundant requirement checks (`E0a-5`).

---

## 2. `E0a`: Soundness & Sandbox Fixes Implemented

Covered by dedicated regression tests in [`v2/tests/stage0.lisp`](file:///home/tlh24/lisploop/v2/tests/stage0.lisp):

1. **`retype-knowledge-laws` without `:samples` ([`templates.lisp`](file:///home/tlh24/lisploop/v2/templates.lisp#L536-L598)):**
   - **Bug:** Calling `consolidate-knowledge-library` with `:retype-domains '(:int)` and default `:samples nil` evaluated candidate laws on 0 rows (`tested = 0`), discarding 100% of retyped `:int` laws as `:vacuous`.
   - **Fix:** Added `default-law-samples` generating deterministic cartesian sample assignments over `(-3 -2 -1 0 1 2 3 5)` (or finite-field/boolean elements) when `:samples` is omitted. Sound ring laws (`a + b = b + a`) survive as `:conjecture` with `:tested-p t, :certified-p nil`; finite-field wrap-around coincidences (`a + a + a = 0` from $\text{GF}(3)$) are refuted.
2. **`:unresolved` oracle handling in `row-satisfaction` & `finish-observation-rows` ([`synthesize.lisp`](file:///home/tlh24/lisploop/v2/synthesize.lisp#L1120-L1142), [`enumerate.lisp`](file:///home/tlh24/lisploop/v2/enumerate.lisp#L844-L858)):**
   - **Bug:** `row-satisfaction` checked `(typep (evaluation-error pred) 'unresolved-evaluation)` on a formatted string (always `nil`) and did not treat `:status :unresolved` as `:unknown`, misclassifying oracle misses as `:refuted` or `nil`; `finish-observation-rows` overwrote `status` with `:complete` when `retain-outcomes-p` was true even after `:unresolved`.
   - **Fix:** Explicitly return `:unknown` when either candidate evaluation or requirement evaluation yields `:status :unresolved` or `:cutoff`; preserve non-`:complete` status in `finish-observation-rows`.
3. **Active certified rewrite laws in synthesis node search ([`synthesize.lisp`](file:///home/tlh24/lisploop/v2/synthesize.lisp#L172-L202), [`laws.lisp`](file:///home/tlh24/lisploop/v2/laws.lisp#L502-L526), [`enumerate.lisp`](file:///home/tlh24/lisploop/v2/enumerate.lisp#L486-L497)):**
   - **Bug:** `open-prepared-node` and `restart-revised-node` never passed `:laws` to `start-search`, leaving certified equational pruning dead inside hierarchical synthesis; meanwhile, defining a function mid-search bumped `*function-library-version*` and crashed `rewrite-step` with `"Stale rewrite library"`.
   - **Fix:** Added `node-rewrite-laws` (wired into `open-prepared-node` and `restart-revised-node` when `library` is non-nil and scope has no `:code` variables) and `current-rewrite-library` to refresh function-version metadata safely at `:rewrite-start`.
4. **Universal per-row VM fuel & child-binding sandboxing ([`enumerate.lisp`](file:///home/tlh24/lisploop/v2/enumerate.lisp#L345-L378), [`laws.lisp`](file:///home/tlh24/lisploop/v2/laws.lisp#L48-L62), [`frame.lisp`](file:///home/tlh24/lisploop/v2/frame.lisp#L31-L58), [`synthesize.lisp`](file:///home/tlh24/lisploop/v2/synthesize.lisp#L951-L977)):**
   - **Bug:** Enumerated candidates and observations ran with `row-budget = nil` (allowing diverging recursive definitions to burn the entire search budget on row 0); `propagate-requirements` ran with `+completion-work+ = 10^8` + `(assert (eq status :value))`; partial child bindings in `prepare-synthesis-node` crashed on out-of-domain rows (e.g., `(at '() 0)`).
   - **Fix:** Defaulted `*default-row-budget* = 100,000` in `:enumeration` mode on `start-search` and `start-observation-search` (with matching budget-clamp in `observation-step`), added `*propagation-eval-budget* = 100,000` with graceful cutoff fallback in `laws.lisp`, bounded `evaluate-row-bindings`, and caught `pull-through` binding errors in `prepare-synthesis-node` as clean `:binding-error` node conflicts.
5. **Coupled fallback nogood key collision ([`frame.lisp`](file:///home/tlh24/lisploop/v2/frame.lisp#L1185-L1200), [`nogoods.lisp`](file:///home/tlh24/lisploop/v2/nogoods.lisp#L140-L154)):**
   - **Bug:** `coupled-fallback-rows` assigned every fallback row the identical occurrence key `:coupled`, colliding distinct parent rows in `build-nogood-clause` (`(= 1 (length occs))` falsely triggered `parent-incompatible-p`) and preserving the parent's incompatible target requirement on the child's placeholder row.
   - **Fix:** Indexed coupled fallback keys as `(:coupled . occ-idx)` with unconstrained `(lit :bool t)` placeholder requirements, and required integer occurrence indices before asserting `parent-incompatible-p`.
6. **Branch-safe `:filter` lifting ([`frame.lisp`](file:///home/tlh24/lisploop/v2/frame.lisp#L1019-L1068), [`requirements.lisp`](file:///home/tlh24/lisploop/v2/requirements.lisp#L204-L214)):**
   - **Bug:** `flatten-lifted-conjuncts` picked the first surviving `:if` branch (`(or (go yes) (go no))`) and discarded alternatives, hallucinating unconditional `YES` commitments on non-injective outer wrappers (e.g., `(= (length (filter '(1 2) Z)) 1)`) while failing to fold `(if C 'nil 'nil) -> 'nil` under `:necessary` on impossible duplicate-element rows (`(filter '(1 2 1 3) Z) = '(1 3)`).
   - **Fix:** Replaced greedy branch selection with intersection of branch commitments (emitting facts only when one branch is refuted and routing two-branch ambiguity to `coupled-fallback`), and added `((and (eq :necessary (fold-contract state)) (equal yes false) (equal no false)) false)` to `fold-if`.

---

## 3. `E0b`: Battery Load-Bearing & Bootstrap Distractor Audit

Reproducible via `make -C v2 stage0` ([`v2/experiments/stage0-audit.lisp`](file:///home/tlh24/lisploop/v2/experiments/stage0-audit.lisp)).

### `E0b-1a`: Host `:cons` Fold Rules vs. `library/constructors.sexp`

Gated `:cons` simplification rules (`fold-cons`, `fold-at-cons`, `fold-tail-cons`, `fold-length-cons`, `fold-member-cons`, `fold-equal-cons`) in [`requirements.lisp`](file:///home/tlh24/lisploop/v2/requirements.lisp#L305-L315) behind `*enable-host-cons-folds*`:

| Regime | `:map` Lift Synthesis | `:cons` Equality Propagation `(= (cons (at V 0) (at V 1)) '(10 20))` |
| :--- | :--- | :--- |
| **Host `:cons` folds ON** (`constructors.sexp` unloaded) | Solved in **`7,139`** work | Folded directly to `(= V '(10 (20)))` (`:certified` equivalence) |
| **Host `:cons` folds OFF** (`constructors.sexp` unloaded) | Solved in **`9,896`** work (`+38.6%`, falls back to coupled verification) | **Unnarrowed** (`0` narrowed/suggested; stuck as opaque `(= (cons ...) '(10 20))`) |
| **Host `:cons` folds OFF + `constructors.sexp` loaded** | Solved in **`9,896`** work (`lift-frame` calls `fold-constants`, not `propagate-requirements`) | **Narrowed (`1` suggested)** via `:INVERT-CONS-HEAD` + `:INVERT-CONS-TAIL` to `(if (= (at V 0) 10) (= (at V 1) '(20)) nil)`, `:certified nil` |

**Takeaway:** `library/constructors.sexp` genuinely carries inverse `:cons` solvers in `propagate-requirements`, **except** (1) `lift-frame` (`unroll-lifted-application`) only invokes `fold-constants`, never `propagate-requirements`, and (2) infinite-domain (`:int` / `(:seq :int)`) constructor laws/solvers in `constructors.sexp` remain `:conjecture` (`:certified-p nil`), so they cannot perform certified branch refutation without algebraic ADT injectivity/disjointness axioms (Stage 1 `E1a`).

### `E0b-1b`: Host Descriptor Prototype Synthesis vs. `library/descriptors.sexp`

Gated `synthesize-io-descriptor-specs` in [`descriptors.lisp`](file:///home/tlh24/lisploop/v2/descriptors.lisp#L862-L940) behind `*enable-host-descriptor-synthesis*`, falling back to `match-library-io-descriptors` over preloaded `descriptors.sexp`:

| Mode | Fresh Profile Work (`5` HO/seq fns) | `:map` Frame Scores `(:map / :filter / :map-adjacent)` | `:filter` Frame Scores | `:map-adjacent` Frame Scores |
| :--- | :--- | :--- | :--- | :--- |
| **Host prototype synthesis (`T`)** | `18,030` | `(T -17) / (T -4) / (NIL +inf)` | `(NIL +inf) / (T -15) / (NIL +inf)` | `(NIL +inf) / (T -9) / (T -12)` |
| **`library/descriptors.sexp` (`NIL`)** | `23,398` | `(T -17) / (T -4) / (NIL +inf)` | `(NIL +inf) / (T -15) / (NIL +inf)` | `(NIL +inf) / (T -9) / (T -17)` |

**Takeaway (plus latent `v1` finding):**
1. Preloaded `descriptors.sexp` reproduces **100% of pruning/compatibility decisions** (`NIL +inf` vs `T`) without calling `synthesize-io-descriptor-specs`, and actually scores `:map-adjacent` slightly more sharply (`-17` vs `-12`) because `match-library-io-descriptors` tests all library descriptors uniformly rather than gating `:DESC/SUBSET-ELEMENTS` behind prototype branches.
2. **Latent `v1` certificate gap uncovered on `:filter`:** In `library/sequences.sexp`, `:filter` synthesizes base branch `(:VAR 0 (:SEQ :INT))` instead of `(:LIT (:SEQ :INT) NIL)` under `(= X0 '())`. Because `empty-sequence-base` (`descriptors.lisp:25`) checks `(lit-p then-b)` without substituting the `(= X0 '())` branch equality, `:filter` received `:status :empirical` (not `:necessary`) on `:DESC/LEN-LE` and `:DESC/EMPTY->EMPTY`, and `trigger = NIL`.

### `E0b-2`: Bootstrap Distractor & Recursion-Schema Survival (`16` `:function` Specs, `350k` Work Cap)

Tested all `16` bootstrap `:function` specs (`6` L3 seed-corpus recursions + `10` battery specs across `:sequences`, `:scans`, `:sequence-shift`) across `(per-spec whitelist vs. full active-library grammar)` $\times$ `(recursion-schemas.lisp ON vs. OFF)`, with non-symmetric held-out semantic checks:

| Spec | Battery | Whitelist + Schemas | Whitelist, No Schemas | Active Grammar + Schemas | Active Grammar, No Schemas |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `copy` | seed | YES (`17,630`) | YES (`16,748`) | YES (`29,645`) | YES (`27,291`) |
| `inc-all` | seed | YES (`33,929`) | YES (`31,445`) | YES (`196,724`) | YES (`195,020`) |
| `dbl-all` | seed | YES (`32,113`) | YES (`29,409`) | YES (`65,100`) | YES (`63,333`) |
| `sum-all` | seed | YES (`26,298`) | YES (`25,978`) | YES (`28,222`) | YES (`27,868`) |
| `len-all` | seed | YES (`34,444`) | YES (`34,038`) | YES (`43,772`) | YES (`42,759`) |
| `prd-all` | seed | YES (`28,337`) | YES (`27,984`) | YES (`37,158`) | YES (`36,804`) |
| `foldl` | `:sequences` | YES (`82,539`) | **IMPOSTOR** (`121,367`) | **IMPOSTOR** (`213,355`) | **IMPOSTOR** (`209,723`) |
| `filter` | `:sequences` | YES (`76,871`) | YES (`76,203`) | YES (`122,687`) | YES (`120,369`) |
| `map-adjacent` | `:sequences` | YES (`110,559`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `positions` | `:sequences` | YES (`47,136`) | TIMEOUT (`350,000`) | YES (`92,605`) | TIMEOUT (`350,000`) |
| `scan` | `:scans` | YES (`264,818`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `shift-seq` | `:sequence-shift` | YES (`100,600`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `seq-corr` | `:sequence-shift` | YES (`88,666`) | YES (`88,066`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `best-shift` | `:sequence-shift` | YES (`199,252`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `argmax-corr` | `:sequence-shift` | YES (`98,921`) | FAIL (`51,825`) | TIMEOUT (`350,000`) | TIMEOUT (`350,000`) |
| `last-or` | `:sequence-shift` | YES (`32,798`) | YES (`51,078`) | YES (`152,471`) | YES (`162,173`) |
| **Total Solved** | `16` specs | **`16 / 16` (`100%`)** | **`10 / 16` (`62.5%`)** | **`10 / 16` (`62.5%`)** | **`9 / 16` (`56.3%`)** |
| **Held-Out Sound** | `16` specs | **`16 / 16` (`100%`)** | **`9 / 16` (`56.3%`)** | **`9 / 16` (`56.3%`)** | **`8 / 16` (`50.0%`)** |

#### Three Distinct `foldl` Impostors Exposed by `E0b-2`

Because all `9` I/O rows of `:SPEC/FOLDL` in `sequences.sexp` use the single higher-order argument `X2 = (- A B)`, and right-subtraction satisfies $(acc - a) - b = (acc - b) - a$, removing either the recursion schema or the per-spec operator whitelist causes MDL search to converge to **unsound impostors** that satisfy 100% of `:SPEC/FOLDL` while failing non-right-commutative held-out `X2 = (- (* 2 A) B)`:

1. **Whitelist, No Schemas (`121,367` work) — Right-to-Left Order Impostor:**
   ```lisp
   (if (= '() X0) X1 (code-eval X2 (foldl (tail X0) X1 X2) (at X0 0)))
   ```
   Ties true `foldl` in bit-size (`133` bits) and passes every `(- A B)` row despite consuming elements right-to-left.
2. **Active Grammar + Schemas (`213,355` work) — Hardcoded-`:-` Tail-Recursive Impostor:**
   ```lisp
   (if (= X0 '()) X1 (foldl (tail X0) (- X1 (at X0 0)) X2))
   ```
   Once `:-` enters the grammar, ignoring `X2` and hardcoding `(- X1 (at X0 0))` is strictly smaller in MDL bits than `(code-eval X2 X1 (at X0 0))`!
3. **Active Grammar, No Schemas (`209,723` work) — Hardcoded-`:-` Non-Tail Impostor:**
   ```lisp
   (if (= '() X0) X1 (- (foldl (tail X0) X1 X2) (at X0 0)))
   ```

---

## 4. Architectural Implications for Stage 1 (`plan_v2.tex` §6)

1. **Per-spec micro-grammars and `recursion-schemas.lisp` were doing heavy hidden lifting in `v1`:** Dropping both reduces held-out sound bootstrap survival from **`16/16` (`100%`)** to **`8/16` (`50%`)**, with all multi-step index/window/correlation tasks (`map-adjacent`, `scan`, `shift-seq`, `seq-corr`, `best-shift`, `argmax-corr`) timing out at `350k` work under full grammar branching.
2. **Higher-order specs MUST vary their `:code` probes across non-commuting, non-associative functions** (fixing `:SPEC/FOLDL` immediately in Stage 1 so `:-` cannot impersonate `X2` and right-to-left evaluation cannot impersonate left-to-right accumulation).
3. **`tabulate` / `iota` + chart lifting (`E1a` + `E1b`) directly targets the exact 6 timeouts (`map-adjacent`, `positions`, `scan`, `shift-seq`, `seq-corr`, `best-shift`):** `positions`, `map-adjacent`, `shift-seq`, and `seq-corr` become non-recursive flat index/fiber compositions over `tabulate`, eliminating recursive self-call branching under the full active library grammar.
