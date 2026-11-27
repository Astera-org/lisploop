# core-repr — the kernel's fundamental data structures and VM

Auditor: `core-repr`. Subject: `/home/tlh24/lisploop` root (v1) files `package.lisp ast.lisp codec.lisp vm.lisp
evidence.lisp requirements.lisp frame.lisp fibers.lisp relations.lisp unify.lisp`, their `v2/` counterparts, and the
tests that document intended semantics. `plan_v2.md`, `plan_v2b.md`, `plan_v2.tex` were not read.

Conventions. Every claim carries `file:line`. **V** = VERIFIED (I read the code and/or ran it); **I** = INFERRED.
Paths without a prefix are in the repository root (v1). Probe scripts and their output are in
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/core-repr/` (`probe1.lisp` …
`probe10.lisp`, `fnsize.lisp`, `runtests.sh`, `diff_*.txt`). Nothing under the repository was written.

What was run (SBCL 2.6.4): the ten in-scope kernel test modules (`core codec invariants structural topology metrics
lifting closures totality symbolic`) pass on both trees — **89 tests, 532,575 checks**, 4.2 s (root) / 4.7 s (v2),
identical check counts (V, `runtests.sh`). Ten probe scripts confirm the behaviours quoted below.

---

## 0. The ten things that matter most

1. **A frame is a table of *unary* constraints.** A row is `(key, known-inputs, requirement)` where the requirement
   is one Boolean AST over the single variable `x0` = the unknown target (frame.lisp:7-10, 221-222). The only
   relations *between* unknowns that a frame can hold are three kinds of binary row-to-row edge (`:equal`,
   `:distinct`, `:persistence`, frame.lisp:20-24) and the older `pairs`/`anchors` lists. Anything n-ary that
   pullback or lift produces is either dropped (a sound weakening) or returned out-of-band as a `coupled` list and
   handled by a bounded brute-force join (frame.lisp:582-593, 1239-1240; synthesize.lisp:636-642). This is the precise
   representational limit; it is where a hypergraph would say more than a frame.
2. **Pullback itself is tiny, general and sound.** `pullback-frame` is 37 lines: substitute the decoder into each
   row's predicate, `B(z) = A(d(c, z))` (frame.lisp:544-580). The "Galois soundness / zero false pruning" contract is
   tested (tests/invariants.lisp:120-236, tests/structural.lisp:78). The complexity is not in pullback; it is in
   *solving* the pulled-back predicate into explicit values, which is done by ten hard-coded per-constructor fold
   rules (`*fold-rules*`, requirements.lisp:245-256, bodies to 399) plus learned `:solver` entries (laws.lisp).
3. **Substitution is an opcode; lift, pullback, fiber, quotient, partition, reorientation, residual are not.** Of the
   twelve operations in §3, only substitution/matching/application of quoted code, tuple construction/projection
   and the conditional exist as VM opcodes. Frames and rows are host structs and are not values of the object
   language at all, so no synthesized program can touch one (V, §3).
4. **Terms are plain conses over pooled uninterned symbols — not hash-consed.** `eq` fails, `equal` is the
   identity; metadata lives in a weak `eq` side table; every "snapshot" `copy-tree`s the AST and thereby discards
   the cached metadata and closure (V, §1.1, probe1/probe9).
5. **The VM is the cleanest component**: 27 opcodes, prepaid per-instruction metering, exact resumption after a
   budget cutoff, a status of `:value | :error | :unresolved | :unknown`. A crash or cutoff *is* returned as data
   to the host caller — but as a keyword plus an unstructured string, and there is no opcode by which a
   synthesized program can observe a failure (V, §2.6).
6. **No index sets in v1.** Positions of sequence elements appear only as components of host-side row keys.
   Variable-index `at` and every `gather` are never provably total, there is no `iota`/range, and pulling a
   requirement back through an indexing decoder yields a predicate that can be *checked* but not *solved*
   (tests/core.lisp:607, 627-633) (V, §4).
7. **v2 Stage 1 adds exactly that** (`:iota :tabulate :where :evolve` + six code-reflection opcodes incl.
   `:code-anti-unify`), **but is untested and partly broken**: `(tabulate n F)` with a code variable `F`,
   `(tabulate n '<not-unconditionally-total code>)` and `(gather xs (tabulate …))` all raise a *host assertion* when
   the AST is constructed (v2/ast.lisp:1096, 1144 call `(var -1 …)`/`(var -2 …)`, which v2/ast.lisp:671-673 forbids).
   Eleven exported Stage-1 symbols (the mini e-graph, PIT/induction certifiers) are defined nowhere (V, §9).
8. **Residuals have at least eight unrelated representations** and the built-in geometry is a per-type `ecase`
   (`correction`, frame.lisp:1533-1581). The one *learned* notion of distance is the "metric decoder": an
   invertible binary operator `d : (τ, δ) → τ` plus its solver, distance = tag bits + bits of δ (laws.lisp:1246-1326).
   A frame metric is an AST of two target values and by its own docstring cannot be row-dependent (frame.lisp:508-518).
9. **The tariff, not the host, is what makes sequence programs expensive.** A linear recursive sum over n list
   elements costs Θ(n²) work units (measured: work/n² = 7.9 → 7.5 from n=100 to 800); two `at` reads on a
   10,000-element list cost 430,941 units. Host throughput is fine (≈17 M work-units/s interpreted) (V, §10).
10. **No execution graph is ever recorded.** `evaluation` has no trace slot (vm.lisp:57-59). The closest thing the
    kernel has to an explicit dependency graph is the knowledge library's n-ary edge lists with an incoming index
    (knowledge.lisp:286-330) and the synthesis-node tree; the closest thing to an *execution* graph is the implicit
    one that `lift-frame` builds by symbolically unfolding a decoder into `code-eval` call sites (frame.lisp:1194-1271).

---

## 1. DATA MODEL

### 1.1 Terms / expressions

| Aspect | What it is | Where | Tag |
|---|---|---|---|
| Representation | Native Lisp lists `(op-symbol arg …)`; a literal is `(QUOTE-symbol value)`; variables, operators, holes are *uninterned symbols* | ast.lisp:560-564, 1110-1116, 688-694 | V |
| Leaf interning | One symbol per `(kind id type)` in an `equal` hash table `*typed-symbol-pool*`; the quote head is pooled per literal type | ast.lisp:35, 578-583, 629-639, 675-679 | V |
| Hash-consing of applications | **None.** `app` conses a fresh list every time | ast.lisp:1110-1116 | V (probe1: `eq` of two `(+ x0 1)` → NIL, `equal` → T) |
| Equality | Structural `equal`. Works because leaves are pooled: `X0:int` and `X0:(seq int)` are different symbols with the same print name (probe1: `equal` → NIL) | — | V |
| Metadata | `ast-meta` struct (kind, id, type, value, non-var-bits, var-count, syntax-work, total-p, free-vars); for symbols on the property list, for conses in the weak `eq` table `*node-meta*` | ast.lisp:21-47 | V |
| Rebuild on demand | A `copy-tree`d AST is still an AST; `ensure-ast-meta` recomputes metadata from the head symbol | ast.lisp:1118-1127 | V (probe1) |
| Monomorphism | Every operator symbol carries a concrete type parameter: `(op :+ :int)` and `(op :+ (gf 5))` are distinct symbols. No polymorphic term exists; polymorphism is host-side retyping in templates.lisp | ast.lisp:585-613; package.lisp:147-151 | V |
| Canonical form | Not of terms. A canonical *bitstring* exists (`encode-model`; `decode-model` rejects non-canonical packets, codec.lisp:205), and `expression-less-p` orders by size then bits (codec.lisp:208-221) | codec.lisp | V |
| Subterm sharing | Only what the builder happens to share. `map-ast` preserves unchanged subtrees (ast.lisp:1213, 1218); `derive-row`/`snapshot-frame`/`lit`/`make-frame` `copy-tree` by default (frame.lisp:26-34, 96-98; ast.lisp:691; frame.lisp:223-225). `copy-tree` appears on 136 lines of the kernel (22 in frame.lisp) | — | V |
| Portable form | `ast->sexp` / `sexp->ast`: keyword-tagged, self-typed s-expression with no uninterned symbols | ast.lisp:1286-1326 | V |

Consequences that bear on a redesign:

* The price of a node is **cached at construction** (`non-var-bits`, `var-count`, `syntax-work`), computed by calling
  into the codec (`operator-bit-size`, `value-bit-size`; ast.lisp:595, 683; codec.lisp:35-37). ast.lisp and
  codec.lisp are mutually dependent. An operator's name costs 4 bits if its index in `+primitives+` is below 15 and
  `4 + δ-code(index − 14)` otherwise (codec.lisp:18-21) — measured: `:+ :if :lookup :gather` 4 bits; `:at :cons` 9 bits;
  `:code-eval :mod` 12 bits (probe1 §E). The prior over operators is therefore an accident of list order (I).
* `total-p` is cached per node but **depends on the global function table**. Redefining any function calls
  `invalidate-app-meta`, which `maphash`es the whole weak table and evicts every `:app` entry (ast.lisp:1103-1108),
  inside a fixed-point loop (knowledge.lisp:514-545). Term attributes are not a pure function of the term (V).
* The pooled metadata of a defined function's operator symbol is *mutated in place* on (re)definition
  (ast.lisp:596-601; knowledge.lisp:604-613) (V).
* Memory: a default 1 GB SBCL heap held 1.75 M live `(+ x 'k)` terms (3.5 M metadata entries) and was exhausted
  before reaching 3.75 M, i.e. roughly 150–300 bytes per live AST node including metadata and weak-table entry;
  GC was 65 % of the time spent adding the last million (probe8). Transient
  construction runs at ≈1.5 M nodes/s (probe9) (V).
* `body-size` is documented "O(1)" (ast.lisp:1168-1169) but calls `expression-type`, a full recursive type check
  (ast.lisp:1172, 1203): 1 ms per call on a 6,000-node cached term (probe9) (V).
* SBCL's `sxhash` gives **one** hash value for 2,000 terms differing at depth ≥ 1 (probe1/probe3), yet `equal` tables
  keyed by ASTs scale linearly here (40,000 keys in 8 ms, probe3). I attribute this to SBCL 2.6's adaptive `equal`
  hashing (I); on an older SBCL the 35 `equal` hash tables in the kernel (frame.lisp has 6, enumerate.lisp 6) would
  degrade. Nothing in the kernel calls `sxhash` directly (V, grep).

### 1.2 Types

`valid-type-p` (ast.lisp:315-325) admits exactly:

| Type | Values (host representation) | Notes |
|---|---|---|
| `:int` | bignum | |
| `:bool` | `t` / `nil` | |
| `(:gf p)` | integer in `[0,p)`; `gf` asserts p prime (ast.lisp:52-56) | arithmetic mod p |
| `(:tuple τ1 … τk)` | Lisp list of length k | |
| `(:seq τ)` | Lisp list | `nil` is the empty sequence, the empty tuple and false at once |
| `(:code inputs sort)` | an AST (or an operator symbol when `sort` is `(:fn (args) ret)`) | "Quoted typed syntax in an explicit free-variable scope; never an executable closure" (ast.lisp:102-106) |

No sum/option type, no error value, no reals, no strings, no first-class function type other than quoted code, no
type of frames, rows, sets or indices. `:unresolved` is a sentinel that may stand in for an input value in a row or
a VM call but belongs to no type (ast.lisp:452; frame.lisp:219; vm.lisp:291, 307) (V). `infer-domain-from-types`
picks the first prime field found, else `:int`, as a schema's "domain" (ast.lisp:327-333) (V).

### 1.3 Structs in scope

**`schema`** (ast.lisp:7-19): `domain`; `inputs` = ordered alist `((id . type) …)`, ids are non-negative integers or
symbols (ast.lisp:86-94); `target` type; `lookup-p` (licenses a lookup-table model, frame.lisp:397);
`availability` = `((input-id . rank) …)`, `target-availability`, `availability-order` = DAG pairs `((low . high) …)`.
A model of the target may read only inputs whose rank strictly precedes the target's (`available-inputs`,
ast.lisp:402-416; reachability by BFS in `rank-le-p`, ast.lisp:338-362). This is a *declared* dependency order on
columns — the kernel's only notion of "what may depend on what" at the data level (V).

**`row`** (frame.lisp:7-10):

| Slot | Meaning |
|---|---|
| `key` | any `equal`-comparable datum, unique within the frame (frame.lisp:206). Derived frames build provenance paths into it: `(parent-key :before)`/`:after` (frame.lisp:375-376), `(parent-key coord)` (1143), `(parent-key occurrence-index)` (1244), `(parent-key :unsat)` (1233), `(parent-key :coupled i)` (1185), `:vacuous` (1266), `(entry-index row-index)` (relations.lisp:145). `select-active-fiber-rows` parses `(first key)` back out as "the parent row" (frame.lisp:1062) |
| `known` | list of input values, positionally aligned with `schema-inputs`; an element may be `:unresolved` (frame.lisp:218-220) |
| `requirement` | a `:bool` AST over `((0 . target))` only (frame.lisp:221-222). Canonical shapes: `(= x0 'v)` (`singleton-requirement`, 164-166), `(member x0 '(v…))` (`set-requirement`, 168-171), `'t` unconstrained, `'nil` refuted (264-268), or any predicate left by a pullback |

**`frame`** (frame.lisp:12-24):

| Slot | Meaning |
|---|---|
| `schema` | above |
| `rows` | list of rows (copied on construction, frame.lisp:223) |
| `pairs` | `((key-a key-b) …)` must-agree links, *priced softly* in Stage A (enumerate.lisp:607-670) |
| `anchors` | list of keys whose values must differ, priced softly (enumerate.lisp:671-687) |
| `metric` | optional `:int` AST over `((0 . target) (1 . target))`: bits to correct predicted value 0 to value 1; must be provably total (frame.lisp:17-19, 185-200) |
| `edges` | `((kind key-a key-b) …)`, kind ∈ `:equal :distinct :persistence`. The first two are *hard*, enforced by exact search (`violated-edge`, enumerate.lisp:449-457); `:persistence` "records that the two rows are neighbours in an induced order, and constrains nothing" (frame.lisp:20-24) |

There is **no guard slot** anywhere in a frame. "Guards" exist as (a) `:if` conditions inside model ASTs, (b) the
`guard` slot of a `knowledge-entry` (knowledge.lisp:95), (c) a Boolean child frame made by `support-frame` from a
hit mask (frame.lisp:1397-1415), (d) path facts in the totality checker (ast.lisp:764-830) (V).

Other structs: `frame-conflict` (kind, keys, known, expression; frame.lisp:258-262); `partition` (positions,
groups; frame.lisp:1417); `fiber-class` (id, requirement, rows, keys; fibers.lisp:6-10); `fold-state`
(requirements.lisp:130-134); `function-definition` (name, inputs, return-type, body, oracle-table, total-p,
conditional-code-params; ast.lisp:220-221); `ledger` (total, counts alist; vm.lisp:10); `evaluation` (status, value,
error, work, tasks, stack, environment, inputs, values, prepared-p, remaining-cost; vm.lisp:57-59);
`validated-program` (vm.lisp:62-63); `entry-executable` (vm.lisp:404-415).

### 1.4 Residuals (eight representations)

| # | Residual | Shape | Where |
|---|---|---|---|
| 1 | Correction packet | integer delta; replacement value; list of sub-packets; `(:seq-delta len-delta packets tail)`; `(:code-edit edits fillings)`; `(:metric-decoder op-sexp delta)` | frame.lisp:1533-1711 |
| 2 | Stage-A model residual | `((row-key . witness) …)` ++ `(((:pair a b) . packet) …)` ++ `(((:anchor k) . :disambiguate) …)` | condense.lisp:117-143; enumerate.lisp:607-687 |
| 3 | Quotient residual | list of class indices | frame.lisp:1443-1454 |
| 4 | Partition positions | `((index part) …)` | frame.lisp:1419-1427 |
| 5 | Relation table | `((key value) …)` in `knowledge-entry-residual`, guarded by `:member` | relations.lisp:22-43, 84 |
| 6 | AU substitutions | per-source alists hole-id → subterm | unify.lisp:68-73 |
| 7 | `coupled` conjuncts | `((row-key . conjunct) …)` returned beside a child frame | frame.lisp:592-593, 639, 1270 |
| 8 | Reserve rows | rows withheld from an over-large lifted frame for CEGAR | frame.lisp:1016-1017, 1263-1271 |

### 1.5 Evidence grades

A `knowledge-entry` carries `certificate` = `(:method m :obligations (…) :snapshot s)` (evidence.lisp:45-50).
`:exhaustive`, `:derived`, `:trusted-axiom` are "current" evidence that may authorise eliminating an alternative
(evidence.lisp:62-65); `:sampled` only licenses a conjecture that is replayed where used (evidence.lisp:67-73). The
snapshot is the statement itself — kind, inputs, target, the four code slots as s-expressions, and the transitive
function definitions it calls (evidence.lisp:3-43) — compared with `equalp`, so a certificate lapses automatically
when any dependency changes. Separately every entry has a `status` label (knowledge.lisp:99) that "alone never
authorizes semantic elimination" (evidence.lisp:63). 73 lines, clean, but two overlapping notions (V).

### 1.6 Ownership / reference graph

```
knowledge-library ──entries──► knowledge-entry ──edges: ((key . targets) …) by *id*──► other entries / function names
        │  functions (name → function-definition)          │  expression, guard, trigger, auxiliary-code : AST
        │                                                   │  residual : table     certificate : plist(snapshot)
        ▼                                                   ▼  executable : entry-executable (host closures)
function-definition ── body : AST ── calls by *operator symbol name* ──► function-definition (global table)

synthesis-node ──parent──► synthesis-node          (synthesize.lisp:19-24)
      │ proposal : decomposition (decoder AST with a hole, child-id, bindings, flags lift-p/slots/fiber-p)
      │ frame, reserve-rows, coupled-requirements
      ▼
    frame ──► schema (inputs alist, target, availability DAG)
      │──► rows : list of row ──► key (provenance path, by value)
      │                        ├─► known : values (positional)
      │                        └─► requirement : AST over x0
      │──► pairs / anchors / edges : refer to rows **by key value**, never by pointer
      └──► metric : AST over (x0 x1)

AST cons ──(weak eq table)──► ast-meta        AST leaf symbol ──(plist)──► ast-meta
AST cons ──(eq table *closures*, ≤32768)──► host closure
evaluation ──► tasks (continuation), stack, environment alist        ledger ──► (category . amount) alist
```

Row-to-row and entry-to-entry links are by key/id (symbolic), so the "graph" is a set of relations joined by
`equal` lookups (`member … :test #'equal`, `assoc`, `position`), not pointers (frame.lisp:58-59, 213-214;
enumerate.lisp:580-582) (V).

### 1.7 Mutability

Everything is a mutable `defstruct`, treated as immutable by convention ("Own the problem's mutable data before
starting a resumable computation", frame.lisp:96-98). Real mutation: `make-observation-scope` `setf`s pairs/anchors
on its private copy (enumerate.lisp:578-579); `consolidate-residual-relations` rewrites entry slots in place
(relations.lisp:169-181); the function table, registered-name list, de-novo counter and library version are global
specials (ast.lisp:230-233); `set-function-active-implementation` swaps a function between oracle table and
candidate body during verification (knowledge.lisp:631-648) (V).

### 1.8 Sharing of evaluation results

None at the value level. Caches that exist: host closures per AST node (`*closures*`, cleared wholesale at 32,768
entries or on any library version change; vm.lisp:421-431, 455-456, 525-527); a single-entry memo so `:code-bind`
reuses `:code-match` (vm.lisp:118-131); `validated-program` (vm.lisp:62-63, 81-85); metric replay templates
(laws.lisp:1289-1312); a per-job rejection cache keyed by normal form (enumerate.lisp:241, 397); observation buckets,
which group expressions by their value vector on a frame's rows (enumerate.lisp:604) — the only place where a
computed result identifies an expression (V).

---

## 2. THE VM

### 2.1 Opcodes (v1: 27, in opcode order; ast.lisp:118-150)

Type parameter = what the operator symbol carries. `n` = `:int` or a prime field. Costs from `primitive-cost`
(vm.lisp:133-154) and `arithmetic-cost` (vm.lisp:100-108); `W` = 1 + Σ `value-work`(arguments).

| # | Opcode | Signature | Semantics / failure | Cost of the `:apply` |
|---|---|---|---|---|
| 0,1,7 | `:+ :* :-` | (n n) → n | mod p for fields | 1 if GF(p≤257); else max(a,b) (+,−) or a·b (×) bit widths, + len(p)² for fields |
| 8 | `:/` | (n n) → n | `truncate` on `:int`; reciprocal by extended Euclid in a field; **error** on zero | a·b (+ len(p)³) |
| 26 | `:mod` | (int int) → int | sign of divisor; error on zero | a·b |
| 24 | `:<` | (int int) → bool | | max(a,b) |
| 2 | `:=` | (τ τ) → bool | host `equal` | W |
| 9 | `:if` | (bool τ τ) → τ | **lazy**, not an `:apply`: a `:branch` task (vm.lisp:313-316, 322-324) | 1 + 1 |
| 3 | `:tuple` | (τ1…τk) → tuple | | W |
| 20 | `:at` | (seq τ, int) → τ, or (tuple, int) → slot type | **error** out of bounds (vm.lisp:156-160) or slot type mismatch | W + 1 + max(width(len), width(i)) |
| 21,22,23 | `:cons :tail :length` | | `tail` of `()` is an **error** (vm.lisp:228-229) | W (so `tail` costs O(length)) |
| 10 | `:concat` | (seq (seq τ)) → seq τ | | W |
| 6 | `:gather` | (seq τ, seq int) → seq τ | error out of bounds | W + Σ per index |
| 4 | `:member` | (τ, seq τ) → bool | | W |
| 5 | `:lookup` | (k, seq (tuple k v)) → v | **error** when the key is absent (vm.lisp:234-238) | W |
| 25 | `:code-eval` | (code, a1…ak) → sort | binds the code's declared inputs, replaces the environment, evaluates the body (vm.lisp:333-341) | 1; body charged as it runs |
| 11 | `:code-kind` | code → int | var 0, lit 1, app 2, op 3 | W |
| 12 | `:code-child` | (code, int) → code | asserts an application, the index, and the child's declared type | W |
| 13 | `:code-operator` | code → operator value | asserts an application of the declared signature | W |
| 14 | `:code-apply` | (operator value, tuple of code) → code | builds an application | W |
| 15 | `:code-match` | (pattern, source) → bool | the pattern's *variables* become holes; first-order typed matching (vm.lisp:110-131) | W + w1·w2 |
| 16 | `:code-bind` | (pattern, source, hole index) → code | asserts the match | W + w1·w2 |
| 17 | `:code-subst` | (template code, tuple of bindings) → code | simultaneous substitution; a non-code binding is lifted to a literal (vm.lisp:195-206) | W + w1·w2 |
| 18 | `:code-total` | code → bool | exposes `provably-total-p` | W |
| 19 | `:code-less` | (code, code) → bool | exposes `expression-less-p` | 4·(W + type-work) |
| — | defined function | declared | body via `call-body`, or oracle table (vm.lisp:342-352) | 1; body charged as it runs |

Other instructions: `:validate` costs the syntax of the expression plus the declaration and value of every input
(vm.lisp:256-263); `:eval` costs 1, or 1 + `value-work` for a literal; `:branch`, `:restore-env` cost 1
(vm.lisp:265-278). No `not/and/or` (encoded by `:if`, ast.lisp:1150-1154), no `>`/`≤`, no slice/take/drop, no map,
no try/catch, no way to mint a variable or count arity (V).

### 2.2 Quoted code

A code value is an AST plus, in its *type*, the scope it is closed over: `(:code ((id . type) …) sort)`
(ast.lisp:102-106). `:code-eval` therefore needs no closures: it *replaces* the environment with the code's inputs
bound to the supplied arguments and pushes a `:restore-env` (vm.lisp:333-336). Capturing an outer value means
building a specialised code value with `:code-subst` — `compose-lifted-model` does exactly that
(frame.lisp:1285-1298). The opcodes together give a synthesized program: match, bind, substitute, apply/build,
destructure, evaluate, ask totality, ask MDL order. They do not give: anti-unification, fresh variables, quoting a
value except through `:code-subst`, arity, or any polymorphic traversal — `:code-child` is typed by a fixed pair
of code types (ast.lisp:531-533), so one function cannot walk children of different sorts (I).

### 2.3 `define-function` (knowledge.lisp:591-629)

Registers `name` in the global function table and name list; builds the operator symbol; accepts the body as an
AST or as a host function of the self-operator (how recursion is written, knowledge.lisp:614); checks the body's
type; optionally stores an **oracle table** `((args . value) …)`; then recomputes totality for *every* registered
function as a least fixed point (knowledge.lisp:514-545), bumps `*function-library-version*` (which empties the
closure cache and invalidates every `validated-program`), and records a `:function` knowledge entry. While a
recursive function is being synthesized its self-calls are answered from the oracle table; a call the table does
not hold raises `unresolved-evaluation` (vm.lisp:345-349). `:unresolved` is thus a third outcome — "no information"
— distinct from a crash (V).

### 2.4 Recursion and totality (ast.lisp:696-1101, ≈400 lines)

* `provably-total-p` is a cached Boolean computed bottom-up when a node is built (`compute-app-meta`,
  ast.lisp:929-969), with one path-sensitive refinement: a branch of an `:if` is judged under facts its condition
  establishes (`condition-facts`, ast.lisp:764-830; facts `(:length id k)`, `(:above id b)`, `(:below id b)`,
  `(:nonzero id)`, ast.lisp:718-724).
* `operator-step-total-p` (ast.lisp:862-894) hard-codes: `/` and `mod` need a divisor known non-zero; `tail` a
  sequence known non-empty; `at` a **literal** index within the known length (or a tuple slot); `:lookup :gather
  :code-child :code-operator :code-bind` are **never** total; a call is total if its definition is.
* A definition is total if every step is total under path facts and its self-calls descend lexicographically on
  per-parameter measures — a sequence shortened by `tail^k`, an integer bounded below reduced by a literal, an
  integer bounded above increased (`self-call-changes`, `self-calls-descend-p`, `analyze-function-body-totality`,
  ast.lisp:971-1095). Only self-recursion is measured; mutual recursion can never certify because the fixed point
  starts every function as not total (knowledge.lisp:514-545) (I).
* Probe results (probe1): `(at xs 0)` not total; `(if (< 0 (length xs)) (at xs 0) 0)` total; a *variable* index
  guarded on both sides is **not** total; a self-looping `:spin` is not total; structural `:sum` is.
* What totality gates: let-sharing (`let-call`, frame.lisp:674-708), every fold rule that drops or reorders a
  subterm (`unfoldable-parts-p`, requirements.lisp:136-149), frame metrics (frame.lisp:198), metric decoders
  (laws.lisp:1269). **Search does not require totality**: a non-total candidate is simply run under a budget.

### 2.5 Metering

* `ledger` = running total plus an alist of per-category counts (vm.lisp:10, 42-54); at least 54 literal categories are in use
  across the kernel (grep of `charge`/`pay-debt`), e.g. `:simulation :pullback :orientation :anti-unification`.
* Every VM instruction is **prepaid**: its cost is computed from the operator and the argument values on the stack
  (`instruction-cost`, vm.lisp:265-278), paid down across calls (`pay-debt`, vm.lisp:33-40), and executed only once
  fully paid (vm.lisp:369-378). `advance-evaluation` spends at most `budget` and leaves the continuation intact
  (vm.lisp:362-387); "exact VM step-determinism" is tested (tests/core.lisp:71).
* Host orchestration is bounded cooperatively: `with-work-limit` binds a limit and `charge` `throw`s `(:cutoff)`
  when the ledger would exceed it (vm.lisp:20-31, 44-48). Host code that does not call `charge` is unmetered:
  `instantiate`/`map-ast`, `extract-allowed-values` (including its Cartesian product, frame.lisp:119-124, 159-160),
  `share-repeated-subterms` (only its result is charged, frame.lisp:865), `canonical-row-order` (V).
* Resumable host jobs use "staged work": compute the result, record its cost as `debt`, publish once the debt is
  paid (vm.lisp:33-35; enumerate.lisp:231-236). For host code the ledger is an accounting model, not a clock (I).

### 2.6 Errors, divergence, and "crash as data"

`advance-evaluation` wraps the loop in `handler-case` (vm.lisp:366-386). What a caller gets:

| Situation | `status` | Other fields | Verified by |
|---|---|---|---|
| finished | `:value` | `value`, `work` | probe1 |
| any host `error` in a primitive, assertion or type check | `:error` | `error` = `princ-to-string` of the condition; `work` spent so far | probe1: `(/ 6 0)` → `"arithmetic error DIVISION-BY-ZERO signalled …"`, work 27; `(tail ())` → `"Cannot take :tail of empty sequence"`; `(at xs 9)` → `"Sequence index 9 out of bounds for length 3"` |
| read of an `:unresolved` input, or oracle miss | `:unresolved` | error string | probe1 |
| budget exhausted (incl. non-termination) | `:unknown` | `tasks`/`stack`/`environment` hold the live continuation; `work` = budget; resumable | probe1: `(spin 1)` with budget 5000 → `:unknown`, work 5000, 1664 pending tasks |

So divergence and crashes are already tolerated and reported to the host, and a cut-off run can be resumed rather
than restarted. Limits that matter for *learning guards from crashes*:

1. The fault is a string. The `unresolved-evaluation` condition has structured `name`/`arguments` slots
   (vm.lisp:65-71) but they are flattened at vm.lisp:384-385. One v1 call site tests the string with
   `(typep (evaluation-error run) 'unresolved-evaluation)`, which can never be true (synthesize.lisp:1108) (V).
2. Neither the failing operator, its argument values, nor its position in the term is recorded. The failing task
   has been popped before it runs (vm.lisp:377-378); on the closure path there is only one `:settle` task
   (vm.lisp:550-551) (V).
3. There is no opcode with which a program can observe a failure, so "defined-here" cannot be a term of the
   object language; a guard can only be learned by host code building a Boolean frame (`support-frame`) from a
   status vector. Today that is done for *value mismatches* (`heuristic-hit-mask`, decompose.lisp:91-99), where an
   erroring row is just another miss (V).
4. Exact search discards the information at once: `:error` → reject the candidate, `:unresolved` → skip the row,
   `:unknown` past the row budget → reject (enumerate.lisp:426-441). Only Stage-A observation with
   `retain-outcomes` keeps a per-row `observation-outcome` (status, value, error, work; enumerate.lisp:599, 822-839).
   The widely used helper `eval-expr-value` collapses every non-value outcome to `(values nil nil)`
   (nogoods.lisp:37-42; 16 call sites) (V).
5. No tail-call elimination: each call pushes a `:restore-env` task (vm.lisp:334), so recursion depth is heap
   (1664 tasks after 5000 units of `spin`). No host stack risk (V).

### 2.7 The closure evaluator (vm.lisp:402-551)

`expression-closure` compiles a hole-free AST that applies **only primitives** — no defined function, no `:code-*`
opcode, `:code-eval` only of a literal — into a host closure over the argument list, incrementing `*closure-work*`
by exactly what the interpreter would charge, in the interpreter's order (vm.lisp:439-528). `settled-evaluation`
runs the closure to completion immediately and returns an `evaluation` with one `:settle` instruction whose cost is
the whole run (vm.lisp:530-551), so budget slicing, cutoff and resumption look identical to the interpreter
(tests/closures.lisp, 3 tests; "search is the same job with and without closures"). Everything recursive, and
everything that manipulates code, runs in the interpreter (V).

---

## 3. THE OPERATION TABLE

(a) = VM opcode usable inside a synthesized program; (b) = host Lisp over kernel data, invisible to programs;
(c) = absent. LOC = lines of the named function(s).

| Operation | (a) opcode | (b) host implementation(s) | (c) / remarks |
|---|---|---|---|
| **Substitution** | `:code-subst` (vm.lisp:195-206; typing ast.lisp:541-549); `:code-eval` = substitution by environment (vm.lisp:338-341); `:code-match`/`:code-bind` = its inverse on one pattern (vm.lisp:189-194) | `instantiate` (ast.lisp:1235-1241, on `map-ast` 1207-1233); `replace-subexpression` (requirements.lisp:38-43, subterm for subterm by `equal`); `propagate-conjunct-equalities` (requirements.lisp:52-59); `substitute-known-evals` + `congruence-close-code-evals` (frame.lisp:962-998); `rename-function-calls` (ast.lisp:1263-1284); `let-call`/`bind-model` (frame.lisp:674-722, substitution as a let); `call-unfolding`/`try-unfold-call` (requirements.lisp:401-469, β-unfolding); `abstract-over-subterms` (unify.lisp:211-241, the inverse); type-level `substitute-type-variables` (templates.lisp:5) | The one operation that really is a synthesizer primitive. Nine host variants beside two opcodes. `instantiate` is called at 34 sites (12 in frame.lisp) |
| **Lift — over rows** | none: a program sees one row's inputs | implicit in every frame operator as `loop for row in (frame-rows …)` (frame.lisp:565, 610, 1317, 1342, 1359, 1408) and in the enumerator's `row-job` (enumerate.lisp:231-343) | rows are not a value |
| **Lift — over a container** | none | — | (c) as a primitive. Expressible as a *library function*: `:map`/`:foldr`/`:filter` are recursive `:function` entries with a `:code` parameter applied by `:code-eval` (library/sequences.sexp:5, 67; loaded by tests/support.lisp:534-542). The bootstrap script has the kernel synthesize six first-order instances (`copy inc-all dbl-all sum-all len-all prd-all`, four examples each, hand-picked operator sets) and then abstract them by AU into `:map` and `:foldr` (bootstrap/build-batteries.lisp:549-581) |
| **Lift — of a requirement through a higher-order decoder** | none | `lift-frame` (frame.lisp:1194-1271, 78 LOC) with `collect-code-eval-calls`, `extract-code-eval-equation`, `record-code-eval-equations`, `substitute-known-evals`, `congruence-close-code-evals`, `extract-outermost-code-eval`, `flatten-lifted-conjuncts`, `select-active-fiber-rows`, `code-call-row`, `coupled-fallback-rows` (frame.lisp:924-1192, ≈270 LOC); inverse `compose-lifted-model` (frame.lisp:1273-1301) | host only — confirms the owner's statement |
| **Lift — over an index set** | none in v1 | — | (c). v2 adds `:iota`, `:tabulate`, `:evolve` (§9) |
| other things called "lift" | | `lift-inductive-sequence-context` (decompose.lisp:384-417: bind head and recursive call on the tail); `lift-field-solvers` (consolidate.lisp:603: retype GF solvers to `:int`); `induce-functorial-solvers` (consolidate.lisp:2081) | four meanings of one word |
| **Projection** | `:at` (tuple slot or sequence element), `:tail`, `:length` | `project-frame-rows` (frame.lisp:1350-1363); `orient-available` (1365-1378); `context-label-frame` (1326-1348, tests only); `probe-frame-coordinates` (1108-1168, 62 LOC, tests only); `product-slot-frame` (582-639: project a requirement onto one slot); `projection-language`/`projection-row-keys` (proposals.lisp:660-689); `inductive-projections` (decompose.lisp:355); symbolic rules `fold-at-tuple`, `fold-at-cons`, `fold-tail-cons`, `fold-length-cons` (requirements.lisp:275-299) | value projection is an opcode; frame projection is host |
| **Pullback** (predicate through decoder) | none. The ingredients exist — a requirement and a decoder are both code, and `:code-subst` composes code — but there is no row or frame value to apply it to (I) | `pullback-frame` (frame.lisp:544-580, 37 LOC) + `pulled-back-row` (443-452) + `evaluate-row-bindings` (427-441); metric: `pulled-back-metric` (508-542) + `metric-invariant-under-decoder-p` (468-506); `conserved-quantity-frame` (1303-1324) is a pullback | host |
| **Fiber / preimage** | `:member`, `:lookup` test or read an *explicit* set/table; nothing computes a preimage | explicit sets: `extract-allowed-values` (frame.lisp:126-162); constructor preimages, one rule each: `fold-equal-tuple`, `fold-member-tuple`, `fold-equal-cons`, `fold-equal-code-apply`, `fold-equal-code-subst`, `fold-equal-if` (requirements.lisp:301-399); finite narrowing by trial: `filter-membership` (requirements.lisp:471-511); arithmetic preimages: `:solver` entries applied by `propagate-requirements` (laws.lisp). "Fibers" in the other sense — classes of rows whose requirements are jointly satisfiable: `infer-fibers` (fibers.lisp:12-164) | v2 adds `:where` (index fiber) as an opcode *and* `fold-equal-gather` computing the same fibers in the host. "Fiber" names three things: a preimage, a row class (`fiber-class`), and the child rows over one parent row (`select-active-fiber-rows`) |
| **Anti-unification** | none in v1 | `anti-unify` (unify.lisp:36-73, 38 LOC: n-ary, typed, optional operator holes, shared holes for equal disagreement tuples); `match-pattern` (13-34); `au-substitutions-frame` (75-101, tests only); `compile-au-constructor` (103-121: lowers a pattern to an object-language program built from `:code-apply`); `shared-subterm-cover` (134-209, 77 LOC); `anti-unify-for-library` (abstraction.lisp:98); `anti-unify-nogood-clauses` (nogoods.lisp:218); `constructor-au-product` (proposals.lisp:487); `code-edit` (frame.lisp:1583-1624: AU as an edit distance) | v2 adds `:code-anti-unify` (binary, no operator holes) |
| **Quotient** | none | `quotient-values`/`restore-quotient`/`quotient-model` (frame.lisp:1443-1471; the only kernel caller is `partition-model`, itself called only from tests); `join-same-input` (323-340: rows quotiented by equal inputs); observation buckets (enumerate.lisp:604: expressions quotiented by behaviour); AU (terms quotiented by a pattern) | the emitted *model* is an ordinary program `(gather 'R 'idx)` or `(at 'R idx)` |
| **Partition / guard / conditional** | `:if` | `partition` struct, `partition-rows`, `reassemble-partition`, `partition-model`, `partition-pairs-and-anchors`, `with-frame-linkage` (frame.lisp:1417-1522); `infer-fibers` (fibers.lisp); `support-frame` (frame.lisp:1397-1415); `find-sound-exception-guard` (decompose.lisp:240); `condition-facts` (ast.lisp:764-830); `fold-if` (requirements.lisp:183-217); guarded consumption of an entry (vm.lisp:622-645); `compose-hybrid-residual-program` (relations.lisp:22-43) | conjunction has no representation of its own: `bool-and` is `(if a b 'nil)` (ast.lisp:1153-1154) and every consumer re-flattens with `extract-conjuncts` (requirements.lisp:45-50; 14 call sites, 7 in frame.lisp) |
| **Tuple / product construction and slicing** | `:tuple`, `:at`, `:cons`, `:tail`, `:concat`, `:gather`, `:length` | `product-slot-frame` (frame.lisp:582-639, 58 LOC); `compose-product-model` (868-892); `extract-slot-constraint`, `cartesian-product-lists` (100-124); `try-reassemble-tuple-coordinates` (requirements.lisp:78-102); product join with bounded combination (synthesize.lisp:636-730) | no slice/take/drop opcode: only `tail^k` and `gather` with an index list |
| **Reorientation** | none | `orient-observations` (frame.lisp:342-364: choose input and target columns of recorded rows); `transition-probes` (366-390); `orient-available` (1365-1378); `conserved-quantity-frame` (1303-1324); `solve-equality-symbolically` (laws.lisp:809-888) and `orient-conserved-quantity` (laws.lisp:931 ff.) | the *inverses* are object-language data — a `:solver` entry holds a witness AST and a guard AST run by the VM — but the act of inverting is host |
| **Composition** | `:code-eval` (apply), `:code-subst`/`:code-apply` (build composed code) | `compose-model` (frame.lisp:839-866), `bind-model` (710-722), `let-call` (674-708), `share-repeated-subterms` (768-837, 70 LOC), `compose-product-model`, `compose-lifted-model`; `compose-through` (synthesize.lisp:290-306) | |
| **Residual computation** | none. A frame metric and a metric decoder *are* object-language programs, evaluated by the VM (frame.lisp:1655-1661; laws.lisp:1314-1326) | `correction` (frame.lisp:1533-1581), `code-edit` (1583-1624), `priced-correction` (1645-1668), `apply-correction-packet` (1675-1711), `select-closest-witness` (1719-1734), `minimum-disambiguation-bit-size` (1736-1746); `relational-linkage-residual` (enumerate.lisp:607-687); `price-heuristic-model` (condense.lisp:117-143); `metric-delta` (laws.lisp:1314-1326); `make-additive-residual-decoder`, `metric-residual-decompositions` (decompose.lisp:13-83); `consolidate-residual-relations` (relations.lisp:97-221) | distance functions are data; residual computation is host |

**One concept, several implementations — the clearest cases**

* *Pull a requirement to a child / compose the child's model back* exists three times, chosen by flags on the
  `decomposition` record: `pull-through` dispatches to `product-slot-frame`, `lift-frame` or `pullback-frame`, and
  `compose-through` to `compose-product-model`, `compose-lifted-model` or `compose-model`
  (synthesize.lisp:290-320). All three begin with the same substitution of the decoder into the row requirement
  (frame.lisp:569-574, 614-619, and 1203 via `pullback-frame`) and differ only in how they *factor* the result:
  not at all; by slot variable; by `code-eval` call site.
* *Inverting a constructor* is a hard-coded fold rule for `tuple`, `cons`, `code-apply`, `code-subst`
  (requirements.lisp:245-256), while *inverting an arithmetic operator* is a learned `:solver` entry. v2 added a
  switch `*enable-host-cons-folds*` precisely "to test whether `library/constructors.sexp` can carry their load"
  (v2/requirements.lisp:300-302).
* *Row-to-row relations* are stored twice: `pairs`/`anchors` (soft, priced) and `edges` (hard, enforced)
  (frame.lisp:15-24).
* *"The set of values a row allows"* is recovered from requirement syntax by `extract-allowed-values`,
  `row-singleton-value`, `match-literal-equality`, `extract-term-equality`, `extract-term-membership`,
  `extract-slot-constraint`, `extract-at-coordinate-equality` (frame.lisp:100-162, 286-290; requirements.lisp:4-76).

---

## 4. INDICES

**How positions are represented in v1.** A sequence-valued target is one value inside one row's requirement, e.g.
`(member x0 '((5 11)))`. Element positions do not exist in the frame until an operator explodes the sequence:

| Operator | Where the position goes | Citation |
|---|---|---|
| `lift-frame` | the child row key is `(parent-key occurrence-index)`, the index being the position of the *conjunct* after unfolding; the child's inputs are the call's arguments (the element value), not its index | frame.lisp:1234-1244, 1093-1102 |
| `probe-frame-coordinates` | key `(parent-key coord)`; requirement projected with `(at expr 'i)`; inputs stay the parent's. No kernel caller | frame.lisp:1108-1168 |
| `au-substitutions-frame` | "by default a row knows its position `(i)`" — the one place a position is a *column*. No kernel caller | unify.lisp:80-87 |
| `induce-row-order` | an integer key expression over the inputs along which targets vary little; stored as a chain of `:persistence` edges and a `:locality-key` library entry | proposals.lisp:707-815 |
| inductive decomposition | none: `(at X 0)` and `(tail X)` are bound for the child; structure is consumed head-first | decompose.lisp:355-417 |

So an index is a row key (host-side, opaque to programs), a storage order, or absent; never a first-class value
that a model computes and then uses (V).

**Can an expression generate an index array and use it?** In v1 only in the degenerate senses: a literal list fed to
`:gather`, or a hand-written recursive function that conses up integers. What blocks it:

1. No generator: nothing among the 27 opcodes produces `0..n-1` (probe1: `:iota` absent) (V).
2. Totality: `:gather` is unconditionally non-total and `:at` is total only for a literal index
   (ast.lisp:870-882; probe1 shows even a two-sided guard on a variable index does not certify). A non-total
   subterm cannot be let-shared, reordered or dropped by a fold, or used in a metric (§2.4) (V).
3. No inverse: there is no fold rule for `(= (gather …) 'ys)` or `(at … var)` (requirements.lisp:245-251), so a
   requirement pulled back through an indexing decoder stays opaque. Probe1: the child requirement of
   `(gather x0 Z)` folds only to `(= (gather '(10 20 30 20) x0) '(20 10))` and `extract-allowed-values` returns
   `:unknown`. The kernel's own tests assert this for a quotient index and for a 2-D grid read
   `(at (at 'G (at Z 0)) (at Z 1))` (tests/core.lisp:607, 627-628), and that a bad index is a VM `:error`
   (tests/core.lisp:633) (V).
4. Much of the kernel needs explicit witnesses and gives up on `:unknown`: `lookup-model` signals an error
   (frame.lisp:401), Stage A prices an unresolved row only `(when (consp values) …)` (condense.lisp:113-115),
   `induce-row-order` requires every row to be a singleton (proposals.lisp:726-727) (V).
5. Rows, keys and row order are not values, so "the i-th row" cannot be an input unless a caller copies i into
   `known` (V).

The commit the owner cites (`df33ed1`) did not add index frames to v1; within my files it added the `:mod`
opcode ("a count taken modulo a positive length is a position", tests/totality.lisp:198-210) and, in laws.lisp,
set-valued solvers for "reading a sequence at an unknown index" (`solver-set-valued-p`, laws.lisp:633-638) (V, `git
show df33ed1`).

**What v2 Stage 1 added toward this** — see §9.2; in short: generators (`:iota`, `:tabulate`), an index-fiber opcode
(`:where`), a scan (`:evolve`), difference-bound reasoning so a variable index can be proved in range, the inverse
rules `fold-equal-gather`/`-tabulate`/`-evolve`, and an extension of `extract-allowed-values` to fixed-length
sequences. Probe6 confirms the gather case now works end to end: the same child requirement folds to
`(= (length x0) 2) ∧ (member (at x0 0) '(1 3)) ∧ (= (at x0 1) 0)` and `extract-allowed-values` returns
`((1 0) (3 0))` (V).

---

## 5. RESIDUALS AND GEOMETRY TODAY

**Representation and price.** `correction predicted target type` returns `(values packet bits)` (frame.lisp:1533-1581):

| Type | Packet | Bits | Probe1 |
|---|---|---|---|
| `:int` | `target − predicted` | Elias-δ size of the signed delta | 3→5: packet 2, 5 bits |
| `:bool` | target | 1 | |
| `(:gf p)` | centred modular difference | δ size; deliberately *not* capped at replacement | GF(5) 3→4: 4 bits |
| tuple | list of part packets | 1 bit per equal part, else the part's bits | `(1 t)→(2 t)`: 5 bits |
| seq | `(:seq-delta len-delta packets tail)` — elements aligned **by position only** | 1 + per-element + tail, capped at replacement | `(1 2 3)→(1 2 4)`: 8 bits; append 9: 17 bits |
| code | `(:code-edit paths fillings)` from the AU of the two terms, or replacement if no cheaper | positions + fillings | `(+ x 1)→(+ x 2)`: replacement, 15 bits |
| no prediction (`:error`) | target | plain value size | 5: 8 bits |

An exact prediction costs 0. `priced-correction` (frame.lisp:1645-1668) overrides the bits with the frame's metric
when it has one (clamped to ≥1 on a miss), otherwise lets each library *metric decoder* compete with the built-in.
A Stage-A model's residual bits are, per missed row, the bits to name the row plus the correction to the closest
allowed witness (`charge-row-witness`, `closest-row-witness`, condense.lisp:91-108; `select-closest-witness`,
frame.lisp:1719-1734), plus the relational residual over pairs and anchors (enumerate.lisp:607-687), plus the
length of the residual list (condense.lisp:131-134).

**"Pricing in the ambient space" in code** is `node-analytical-mdl` / `node-priority` (synthesize.lisp:447-457,
485-505):

```
price(node) = bits of the node's Stage-A program composed through every ancestor and sized at the ROOT scope
            + residual bits of that program on the node's OWN frame, in the node's OWN target type
            + policy-score/2 (if inexact) + 16 × (number of coupled requirements) + run-weight × run-work
            [+ a learned correction clamped to −24…48]
```

Program bits are priced in the ambient (root) space; residual bits are priced in whatever intermediate space the
child lives in and simply added. They are commensurable only where the decoder is an isometry for the metric.
`pulled-back-metric` carries the parent's metric to the child in four cases — identity decoder; an `:if` that
passes the child through on one branch; a decoder that reads nothing but the child (metric composed with the
decoder, kept only if provably total); and a child of the target's type whose metric survives a replay on at most
3 rows × 3 values (`*metric-invariance-rows*`, frame.lisp:464-506) — and otherwise the child has no metric: "A
decoder that reads the row's inputs otherwise gives the child a price that depends on the row, which a metric of
two values cannot state" (frame.lisp:508-542). Product slots always lose the metric (frame.lisp:608) (V).

**Every metric / distance / neighbourhood notion, and who calls it**

| Notion | Definition | Callers |
|---|---|---|
| built-in `correction` | per-type `ecase` above | `priced-correction`; `correction-bit-size` in `induce-row-order` (proposals.lisp) |
| frame metric | `:int` AST over two target values, provably total | read in condense.lisp (4 sites), enumerate.lisp, frame.lisp (3), laws.lisp, proposals.lisp |
| pulled-back metric | above | only `pullback-frame` (frame.lisp:563) |
| metric decoder | a `:solver` entry inverting `d:(τ,δ)→τ` in δ, registered by an edge `(:metric-decoder d q tag-bits)`; distance = tag bits + size of δ, accepted only if `d(p, δ)` replays to the target | `register-metric-decoder` (laws.lisp:1250-1275; called from consolidate.lisp ×3); `metric-decoders` (condense, decompose, enumerate, proposals); `metric-delta` (laws.lisp:1314-1326) |
| `:locality-key` | integer key expression giving rows a 1-D order; kept when a chain of corrections along it is cheaper than independent or star coding | `induce-row-order`, `with-induced-row-order`, `stored-row-keys` (proposals.lisp:625-815) |
| `:persistence` edges | adjacency in that induced order; "constrains nothing" | written by `induce-row-order`; consumed outside my files |
| code edit distance | AU-based (`code-edit`) | via `correction` on code types |
| MDL order on terms | `expression-less-p`; exposed as opcode `:code-less` | proposals.lisp, vm.lisp |
| pair/anchor residual | drift along must-agree pairs priced by `priced-correction`; must-vary anchors priced by `minimum-disambiguation-bit-size` | `relational-linkage-residual` (condense.lisp, enumerate.lisp) |
| descriptor scores | Boolean descriptor clauses with `weight-bits`; `score-entry-by-descriptors` returns a policy delta in bits | descriptors.lisp:966 ff. (outside my scope) |
| learned priority | an `:int` AST run in the VM on six integers `(program-bits residual-bits depth constrained-rows policy-score coupled-count)` | synthesize.lisp:459-482 |

There is no embedding, no vector, no neighbourhood query, no notion of "these two *expressions* / *frames* /
*library entries* are close" other than MDL size and descriptor matches. All geometry is one-dimensional (bits) and
attached to a *type*, an explicit AST, or an invertible operator (V).

A point in favour of the existing design: the metric-decoder idea already identifies a residual with a pullback.
Stage B proposes `Y = d(PROGRAM(X), Z)` and lets the child predict the delta Z, the decoder's own solver turning
each requirement into its delta (decompose.lisp:30-83; additive case decompose.lisp:13-24). "The space of deltas of
an invertible action" is the kernel's one working example of a *made* space (V).

---

## 6. INCIDENTAL COMPLEXITY

### 6.1 Where the representation forces special-casing

1. **A requirement is syntax, and half the kernel needs it to be a value.** One slot holds an exact target, a
   finite set, "anything", "nothing", or an arbitrary predicate; consumers pattern-match the syntax to find out
   which (27 call sites of the extractor family across 7 files). `check-requirement` must even *guess* the target
   type from an occurrence of `x0` (frame.lisp:235-246).
2. **Conjunction is nested `if`.** 14 `extract-conjuncts` sites and 20 `bool-and` sites rebuild and re-flatten the
   same set.
3. **Constraints are unary.** `product-slot-frame` keeps "the conjuncts … that mention this slot alone" and
   reports the rest as `coupled` (frame.lisp:582-593, 621-630); `lift-frame` does the same for conjuncts with more
   than one or a non-ground call (frame.lisp:1239-1240) and, when that leaves at most one row, fabricates fallback
   rows (frame.lisp:1259-1262, 1170-1192). The join is exponential and capped at 4 models per slot, 256
   combinations (synthesize.lisp:636-642).
4. **Variables are numbered per scope.** Moving a term between scopes means renumbering: `binding-inputs`,
   `identity-bindings`, `next-child-id`, the canonical renumbering inside `let-call` (frame.lisp:700-707), the
   positional variables of `abstract-over-subterms` (unify.lisp:219-224), the `rename` step of `product-slot-frame`
   (frame.lisp:598, 625).
5. **Operators carry an operator-specific type parameter.** `compute-operator-signature` has six special groups
   (ast.lisp:504-558); `operator-parameter-from-arguments` eight (ast.lisp:1358-1382); `:at` alone needs
   `normalize-at-container-type`, `at-container-type`, `at-container-element-type` and its own branch in both codec
   directions (ast.lisp:285-313, 196-218).
6. **Frames have no identity**, so equal subproblems are recognised by printing: `child-scope-signature` sorts the
   `prin1` strings of every row's inputs and requirement (synthesize.lisp:233-277; same device in
   `canonical-row-order`, proposals.lisp:632-648).
7. **Partiality is a sentinel.** `:unresolved` appears on about 50 lines in 14 kernel files.
8. **Definedness must be preserved by every rewrite**, because a model may be partial. That is why folding has two
   contracts (`:equivalent`, `:necessary`, requirements.lisp:529-540), why `let-call` checks that non-total bindings
   are demanded on every path (frame.lisp:694-699), and why `fold-if` has four guarded cases
   (requirements.lisp:203-217). This complexity is essential to a partial language, not an artefact of frames (I).

### 6.2 The largest / most branchy functions (LOC and branch counts from `fnsize.lisp`)

| Function | Where | LOC / branches | Cases it handles | One general operation? |
|---|---|---|---|---|
| `lift-frame` | frame.lisp:1194-1271 | 78 / 8 | unsat row → refuted row; conjunct with one ground call → child row (deduplicated); coupled conjunct → side list; unsat conjunct; nothing liftable → fallback rows; too many rows → active/reserve split; nothing at all → `:vacuous` row | Yes: "pull back, then factor the predicate by `code-eval` call site". The cases exist because a frame cannot hold a constraint over several call sites or a non-ground one |
| `product-slot-frame` | frame.lisp:582-639 | 58 / 5 | unresolved decoder input; unsat; conjunct on this slot only; conjunct coupling slots; closed conjunct; dead rows | Yes: the same pullback factored by slot variable |
| `pullback-frame` + `pulled-back-metric` | frame.lisp:508-580 | 73 / 6 | unresolved; dead rows under partial bindings; metric: identity / if-passthrough / child-only / replay-invariant | Pullback is general; the metric cases exist because a metric cannot depend on the row |
| `probe-frame-coordinates` | frame.lisp:1108-1168 | 61 / 14 | code vs non-code child; sequence vs other target; coordinate paths incl. negative indices; identity decoder shortcut | Projection composed with pullback; tests-only; exists because positions are not values |
| `select-active-fiber-rows` | frame.lisp:1039-1091 | 53 / 12 | keep unsat rows; first two and last per parent; distinct first argument; fill in order | No: a hand-written sampling policy (3:1 locality quota) baked into the representation layer |
| `share-repeated-subterms` | frame.lisp:768-837 | 70 / 9 | greedy backward elimination over ≤8 repeated subterms; forced sharing of path-repeated oracle calls | Common-subexpression elimination — needed only because terms are trees; a DAG has sharing by construction |
| `correction` / `apply-correction-packet` / `code-edit` | frame.lisp:1533-1711 | 50+38+42 / 10+13+4 | one branch per type, twice (make and apply), plus the metric-decoder packet | One operation (delta in a type's own geometry) spelled as an `ecase`; `(:seq-delta …)`, `(:code-edit …)`, `(:metric-decoder …)` are ad hoc tagged lists |
| `extract-allowed-values` | frame.lisp:126-162 | 37 / 11 | `'nil`; `(= x0 'v)`; `(member x0 'S)`; conjunction of slot constraints → Cartesian product; else `:unknown` | "Enumerate the solution set of a predicate" for four recognised syntactic shapes |
| `fold-if` | requirements.lisp:183-217 | 35 / 11 | literal condition; equal branches (only if the condition is total); `(if c t nil)`; negation; total conjunction → `simplify-conjunction` | Essential (definedness), plus the conjunction encoding |
| `fold-equal-code-subst` | requirements.lisp:358-393 | 36 / 12 | variable bound to code vs lifted value; application; literal | Matching a tree against a substitution instance — `match-pattern` again, re-derived inside a fold rule so that it yields equations |
| `call-unfolding` + `try-unfold-call` | requirements.lisp:401-469 | 37+32 / 9+8 | defined function; literal `code-eval`; `code-eval` of `code-subst`; recursive vs not; spine-depth rationing; fiber cap | β-reduction, with budget heuristics mixed in |
| `filter-membership` | requirements.lisp:471-511 | 41 / 10 | try each allowed value in the other conjuncts; drop refuted values and entailed conjuncts | Arc-consistency for one variable, on syntax |
| `condition-facts` | ast.lisp:764-830 | 67 / 14 | `=` with empty list, zero, a length count; `<` with a literal on either side or a length; `if` encodings of not/and/or | An abstract interpreter for three fact kinds with every operator's meaning hard-coded |
| `analyze-function-body-totality` | ast.lisp:1023-1095 | 73 / 12 | `if`; self-call; `code-eval` of a non-total literal read through; other operators; fixed point over code parameters | Essential, but written against specific opcodes |
| `compute-operator-signature` | ast.lisp:504-558 | 55 / 12 | `tuple`; `at`; `code-eval`; `code-operator`/`apply`; `code-child`/`match`/`bind`/`subst`; pattern rows; registered functions | Artefact of the typed-operator-symbol design |
| `term` | ast.lisp:1384-1442 | 59 / 17 | host-side surface syntax with type inference | Convenience only |
| `shared-subterm-cover` | unify.lisp:134-209 | 76 / 12 | common subterms across bodies; "atomic bound units" `tail x`, `at x k`, self-calls | A heuristic cover for abstraction, with `tail`/`at` special-cased |

Counted another way: of frame.lisp's 1,761 lines roughly 400 are the lift machinery (894-1301), 250 composition and
sharing (641-892), 220 correction packets (1524-1746), 210 pullback (427-639), 190 requirement-shape helpers, 105
partition/quotient, 110 reorientation/projection frames (I, from the line ranges cited).

Measured counter-evidence: basic frame operations are **not** a performance problem. With 4,000 rows,
`simple-frame` 16 ms, `snapshot-frame` 4 ms, `pullback-frame` 24 ms, `frame-conflict-p` (folds every row) 60 ms,
`canonical-row-order` 16 ms — all linear (probe10) (V).

### 6.3 Duplicated concepts under different structs

| Concept | Incarnations |
|---|---|
| "inputs → output with a condition" | `row` (known, requirement); `knowledge-entry` (inputs, target, expression, guard, trigger, residual, auxiliary-code; knowledge.lisp:84-102); `function-definition` (inputs, return-type, body, oracle-table); oracle-table entry `(args . value)`; relation-table row `(key value)`; `observation-outcome`; message row (messages.lisp) |
| typed input list | `schema-inputs`; `function-definition-inputs`; `knowledge-entry-inputs`; the scope inside a `:code` type; `language-inputs`; `metric-inputs` |
| equivalence classes of rows | `partition`; `fiber-class`; `pairs`+`anchors`; `:equal` edges; `join-same-input` hash; observation buckets |
| a lookup table | `:lookup` literal; `oracle-table`; `knowledge-entry-residual`; `lookup-model` |
| evidence that something holds | `certificate`; `status`; `validated-program`; `function-definition-total-p`; the `:fit-attempted` metadata record (relations.lisp:129-139) |
| a term with places to fill | hole pattern (`hole`); `:code` value with declared inputs; `decomposition` (decoder + child-id); AU constructor program (`compile-au-constructor`) |

---

## 7. WHAT IS CLEAN (candidates to import)

| Component | Where / LOC | Depends on | Tests | Verdict |
|---|---|---|---|---|
| **Prefix codec** | codec.lisp, 221 | AST accessors, operator index; and ast.lisp calls back into it for cached sizes | tests/codec.lisp (5 tests; round-trip, truncation, trailing bits, non-canonical rejection), tests/core.lisp | Import the *mechanism* (emitter-as-counter `emitted-bits`, Elias-δ, canonical decode). The opcode table and 4-bit prefix are a tariff decision the owner has waived |
| **Ledger and work limit** | vm.lisp:10-54, 45 | nothing | every resumption test (tests/core.lisp:440-504) | Import unchanged |
| **Resumable metered evaluator** | vm.lisp:56-400, 345 | AST, type predicates, function table, `match-pattern`, `expression-less-p` | tests/core.lisp (21), tests/closures.lisp (3), tests/symbolic.lisp (8), tests/amortization.lisp (5) | Import the *design*: prepaid instructions, explicit task stack, exact resume, four statuses. `execute-primitive` is a 22-branch `case` to re-derive from the new opcode set. Add a structured fault |
| **Closure compiler** | vm.lisp:402-551, 150 | evaluator | tests/closures.lisp ("the same status, value, error text and work … at every budget cutoff") | Import the idea of a cost-equivalent fast path; rewrite with the opcodes |
| **Evidence grades** | evidence.lisp, 73 | `knowledge-entry`, `walk-typed-ast`, function table | tests/library.lisp, tests/topology.lisp:427 | Import; small and principled (statement snapshot ⇒ automatic staleness) |
| **Totality checker** | ast.lisp:696-1101 (≈400) + knowledge.lisp:514-545 | hard-wired to `tail at / mod length cons if code-eval code-subst`; cached in node metadata; global invalidation | tests/totality.lisp (6 tests, each with diverging/undefined negative controls), tests/recursion.lisp, tests/audit.lisp | Well tested and conservative, but *not* separable as written. Portable parts: the fact/measure scheme (`self-call-changes`, `self-calls-descend-p`, 50 LOC) and the least-fixed-point discipline |
| **Matching and anti-unification** | unify.lisp:5-73, 70 | AST, ledger | tests/core.lisp:282, 430 (exhaustive tiny reference), tests/symbolic.lisp, tests/abstraction.lisp | Import; n-ary, typed, shared holes, operator holes |
| **Pullback with its soundness contract** | frame.lisp:427-452, 544-580 (≈65) | `instantiate`, `fold-constants` | tests/invariants.lisp:120-236; tests/structural.lisp:78 | The idea and the metamorphic tests are worth more than the code |
| **Definedness-preserving folding** | requirements.lisp:129-540 (≈410) | AST, VM, totality | tests/invariants.lisp:7-119 (`:equivalent` and `:necessary` soundness) | The two-contract discipline and its tests are valuable; the rule set is per-opcode |
| **Typed AST builder + s-expression I/O** | ast.lisp:560-694, 1110-1326 | codec for sizes | tests/core.lisp:634-713 | Works; a rewrite that interns terms replaces it |
| Quotient / partition views | frame.lisp:1417-1522, 105 | ledger | tests/core.lisp:257-281 | Trivial; no kernel caller of consequence |
| Correction packets | frame.lisp:1524-1746, 220 | AU, codec sizes, `metric-delta` | tests/metrics.lisp (9), tests/lifting.lisp:46 | The prices are tested; the representation is the "clunky" part |

The semantic test contracts are an asset independent of the code: budget obedience and resumption parity
(tests/README.md, "Anytime Resumption Parity"), codec round-trip, Galois soundness of pull/compose pairs, fold
soundness under both contracts, closure/interpreter equivalence.

---

## 8. GRAPH READING

If kernel state were one typed hypergraph (nodes = values, terms, rows, types; hyperedges = operator applications,
tuples, observations, equalities, guards):

**Maps directly**

| Existing structure | As graph | Citation |
|---|---|---|
| AST application | hyperedge (operator; argument nodes → result node); leaves are already unique nodes | ast.lisp:1110-1116, 629-639 |
| `:tuple` / `:at` | product hyperedge and its projections | vm.lisp:224, 242-253 |
| row with a singleton requirement | observation hyperedge (input value nodes → target value node), labelled by its key | frame.lisp:74-80 |
| `edges`, `pairs`, `anchors` | labelled binary edges between row nodes | frame.lisp:15-24 |
| library `edges` | **already** n-ary labelled hyperedges `(key . targets)` with an incoming index | knowledge.lisp:286-330 |
| function call dependencies | directed edges, computed on demand | evidence.lisp:3-21 |
| availability order | DAG on column nodes | ast.lisp:338-362 |
| synthesis tree, subproblem reuse | `parent`, `followers`, `reused-from` | synthesize.lisp:19-24, 834-835 |
| each `decomposition` | an edge parent-frame → child-frame carrying its adjoint pair (`pull-through`, `compose-through`) | synthesize.lisp:290-320 |
| row-key provenance paths | child-row → parent-row edges (today encoded in the key's list structure) | frame.lisp:1062, 1244 |
| observation bucket | a class node (value vector) with member-expression edges | enumerate.lisp:604 |
| AU result | pattern node + one substitution edge per source | unify.lisp:67-73 |
| `partition`, quotient | surjection row → block / value → representative, with the index residual | frame.lisp:1417-1454 |
| child rows of `lift-frame` | hyperedges of the unknown function's graph: (argument values → constrained result) | frame.lisp:1093-1102, 1242-1254 |
| `coupled` conjuncts | hyperedges joining *several* unknown nodes — exactly what a frame cannot hold | frame.lisp:1239-1240 |
| metric decoder | a labelled edge predicted → target carrying a delta | laws.lisp:1314-1326 |

**Maps awkwardly**

* A general requirement: a predicate AST over a distinguished variable — a constraint node attached to one value
  node, with conjunction encoded in `if` (frame.lisp:221-222; ast.lisp:1153-1154).
* Scopes and numbered variables: identity is `(id, type)` relative to a scope; a graph node has no name, so every
  renumbering step (§6.1 item 4) is either unnecessary or must be re-expressed as binding structure.
* Quoted code: the scope is part of the *type* (ast.lisp:102-106); a pattern with holes is a different kind of leaf
  from a code value with inputs, though both are "a term with places".
* Path-sensitive facts (totality): attributes of a node *in a context*, not of the node (ast.lisp:764-830).
* Cached prices: `var-count × width` depends on the enclosing scope's size (ast.lisp:1173-1175) and on the global
  function table.
* The frame metric: a function of two values, not of an edge or a row (frame.lisp:508-518).
* `:unresolved`: a missing edge represented as a value.
* Evidence snapshots: a deep copy of the dependency closure compared by `equalp`, where a graph would compare
  versioned node identities (evidence.lisp:23-60).

**No natural place**

* Correction packets as tagged host lists (frame.lisp:1571, 1620, 1666).
* The resumable machine state (`tasks`, `stack`, `environment`) and the ledger — process state, not knowledge.
* Bitstreams; version counters; the closure cache.
* The row-sampling policy of `select-active-fiber-rows` and the fold budget heuristics (spine depth, fiber caps,
  requirements.lisp:456-459) — policies living in the representation layer.

**Where the code already builds an explicit dependency / execution graph**

1. The knowledge library: per-entry edge lists plus an incoming-edge hash (knowledge.lisp:103-120, 286-330). The
   only explicit, indexed, typed multigraph in the kernel.
2. The synthesis job: a tree of nodes with reuse links, keyed by the printed `child-scope-signature`
   (synthesize.lisp:263-277).
3. `messages.lisp`: the search flattened into relational rows with `(:node :parent :depth …)` columns, from which
   "a frame built from such rows is an ordinary frame" (messages.lisp:3-9, 97-108). This is the existing reflection
   substrate: a table, not a graph, and it carries only what a reader was written to extract.
4. Reachability walks: `rank-le-p` over availability pairs (ast.lisp:338-362); `pair-connected-component` over
   pairs (frame.lisp:1748-1761).
5. **Not** the VM. No evaluation records which operator consumed which value. The nearest thing is
   `lift-frame`, which symbolically unfolds a decoder until the unknown's call sites appear, congruence-closes
   them across rows that share inputs, and emits one row per distinct call (frame.lisp:1214-1256) — an execution
   graph of the decoder with respect to the unknown, built implicitly inside requirement ASTs and thrown away (V).

---

## 9. v2/ DELTA

`git show 397499a:v2/<file>` is Stage 0; `HEAD:v2/<file>` adds Stage 1 (commit `a4e19fa`, "WIP: stage 1 in
progress"). Line counts of change, in-scope files (V, `git diff`):

| File | Stage 0 (lines changed vs root) | Stage 1 (lines changed) |
|---|---|---|
| ast.lisp | 0 | 470 (1,442 → 1,775 lines) |
| vm.lisp | 0 | 99 (645 → 735) |
| requirements.lisp | 11 | 177 (540 → 705) |
| frame.lisp | 61 | 116 (1,761 → 1,828) |
| unify.lisp | 0 | 29 |
| evidence.lisp | 0 | 12 |
| package.lisp | 9 | 6 |
| knowledge.lisp | 0 | 1 |
| codec.lisp, fibers.lisp, relations.lisp | 0 | 0 |

Whole tree: 17,818 → 19,276 lines.

### 9.1 Stage 0 (soundness fixes; tested in v2/tests/stage0.lisp)

* `flatten-lifted-conjuncts`: v1 resolved an ambiguous `(if (code-eval F …) yes no)` "deterministically via its
  first-match (YES) branch" (frame.lisp:1019-1037). v2 commits to a branch only when the
  other is unsatisfiable, else leaves the conjunct whole so it is reported as coupled (v2/frame.lisp:1072-1105).
* `coupled-fallback-rows`: v1's placeholder row *required the type's default value* at unresolved inputs
  (frame.lisp:1187-1190); v2 makes it `'t` (v2/frame.lisp, same function). Row key
  `(key :coupled i)` → `(key (:coupled . i))`.
* `evaluate-row-bindings` gained a per-binding budget (it ran with the 1,000,000 default).
* Fold: under `:necessary`, an `if` with both branches false is false.
* `*enable-host-cons-folds*` switch (see §3).

The code differences are V. That both v1 behaviours over-constrain the child, and so break the zero-false-pruning
contract that tests/invariants.lisp states for `lift-frame`, is I (I did not construct a failing case); the root
tree still has them, and the invariants suite passes on it.

### 9.2 Stage 1 (new opcodes and their support; **no tests**)

`diff -rq tests v2/tests` differs only in `run.lisp` and the added `stage0.lisp`; no file under `v2/tests`,
`v2/library`, `v2/bootstrap`, `v2/experiments` or `v2/milestones` uses `:iota`, `:tabulate`, `:evolve`, `:where`,
`:code-anti-unify`, `:code-quote` or `:code-var` (V, grep).

New opcodes (v2/ast.lisp:146-155; 37 primitives in all):

| Opcode | Signature | VM | Probe6 |
|---|---|---|---|
| `:iota` | int → seq int | v2/vm.lisp:262; cost 1 + width(n) + n (141-142) | `(iota 4)` → `(0 1 2 3)`; `(gather xs (iota (length xs)))` is provably total |
| `:tabulate` | (int, code((0 . int)) → τ) → seq τ | a VM-level loop: `:tabulate-step` tasks (v2/vm.lisp:358-370, 400-411) | `(tabulate (length xs) '(* j j))` → `(0 1 4)`, total, 46 bits, no closure |
| `:where` | (τ, seq τ) → seq int | positions equal to the value (v2/vm.lisp:263-264) | `(where 6 '(5 6 7 6))` → `(1 3)` |
| `:evolve` | (seq a, s, code((0 . s) (1 . a)) → s) → seq s | a scan: `:evolve-step` (v2/vm.lisp:371-384, 412-428) | prefix sums → `(1 3 6 10)`, total, 37 bits |
| `:code-arity`, `:code-var`, `:code-var-id`, `:code-quote`, `:code-value` | reflection: arity; mint a variable of the declared scope; read its id; value ↔ literal code | v2/vm.lisp:180-200 | all return as expected |
| `:code-anti-unify` | (code, code) → code in a wider scope whose extra variables stand for the holes | `code-anti-unify-values` (v2/unify.lisp:75-103); never provably total | `'(+ x 1)`, `'(+ x 2)` → `(+ X0 X1)`; different heads → `X1` |

`:tabulate` and `:evolve` are the first real "lift as a VM primitive"; `:where` is a fiber primitive;
`:code-anti-unify` is in-language AU. The opcode *index* was remapped (27 old primitives, then 8 function slots,
then the new primitives, v2/ast.lisp:283-299) to keep existing bit prices unchanged — the constraint the owner now
waives.

Support code:

* Totality: difference-bound facts `(:diff u v k)`, `(:kind expr k)`, `(:nonzero-expr e)`; `seq-length-key-offset`,
  `diff-term-offset`, `diff-key-le-p` (two-step transitivity), `diff-expr-le-p`, `index-in-sequence-bounds-p`,
  `tabulate-code-total-under-p`, `gather-indices-in-bounds-p` (v2/ast.lisp:760-1167). `:at` with a variable index
  and `:gather` can now be total.
* Fold rules: `fold-at-iota`, `fold-at-tabulate`, `fold-length-{iota,tabulate,gather,evolve}`, and the inverses
  `fold-equal-gather` (per-position preimage fibers), `fold-equal-tabulate`, `fold-equal-evolve` (unrolled along
  the observed trajectory) (v2/requirements.lisp:304-463); a memo table for `(= call literal)` under `:necessary`
  (v2/requirements.lisp:135, 274-289).
* `extract-allowed-values` also reads `(= (length x0) m) ∧ …(at x0 i)…`, enumerating at most 64 sequences
  (v2/frame.lisp:126-214).
* Evidence methods `:pit` and `:ind1` are accepted as current (v2/evidence.lisp:62-71).

Verified working (probe6): gather-index pullback (§4); `lift-frame` through `(evolve '(1 2 3 4) 0 F)` with target
`(1 3 6 10)` yields four child rows with inputs `(state element)` = `(0 1) (1 2) (3 3) (6 4)` and singleton
requirements 1, 3, 6, 10, nothing coupled — a clean lifted frame along a trajectory.

Verified broken or unfinished:

1. **Host assertion on AST construction.** `tabulate-code-total-under-p` and `gather-indices-in-bounds-p` create
   scratch variables `(var -1 :int)` and `(var -2 :int)` (v2/ast.lisp:1096, 1144); `pooled-leaf` asserts ids are
   non-negative (v2/ast.lisp:671-673). Consequently `(app (op :tabulate τ) n F)` fails for a code *variable* F —
   the decoder that the Stage-1 "tabulate cover" proposals build (v2/proposals.lisp:309, 431) — and for a literal
   body that is not unconditionally total (e.g. `(/ 1 j)`, or a reverse that reads `(at xs (- (- (length xs) 1)
   j))`); `(gather xs (tabulate n '…))` fails for *any* body. Probe5 and probe6 reproduce all three.
2. **Dangling exports.** `mini-egraph make-mini-egraph egraph-add-expr egraph-merge egraph-rebuild egraph-equal-p
   ac-canonicalize-expr minimize-laws-with-egraph certify-law-by-pit certify-law-by-induction
   totalize-forward-replay` are exported (v2/package.lisp:66-69) and defined nowhere in `v2/*.lisp`.
3. **Dead switches.** `*certified-length-preserving-ops*` and `*mod-range-certified-p*` are read by the totality
   checker (v2/ast.lisp:859, 921, 942, 1066) and written by nothing; the library slot `op-props`
   (v2/knowledge.lisp:119) has no reader or writer.
4. `:tabulate`, `:evolve` and the new code opcodes are excluded from closures (v2/vm.lisp:603-608): interpreter only.
5. `:tabulate`'s body is closed over `((0 . :int))` alone (v2/vm.lisp:403-404); reading an outer sequence requires
   building the body with `:code-subst`, which is the construction that trips defect 1.

---

## 10. MEASUREMENTS (all V; scripts in the scratch directory)

| What | Result | Script |
|---|---|---|
| In-scope kernel tests | 89 tests / 532,575 checks pass on root and v2 | runtests.sh |
| Term identity | `eq` NIL / `equal` T for separately built equal terms; leaves `eq` | probe1 |
| Recursive `:sum` over n ints (interpreter) | work 6,096 (n=25) … 4,771,918 (n=800); work/n² = 9.8, 8.5, 7.9, 7.7, 7.5, 7.5 | probe7 |
| `(+ (at xs 0) (at xs 1))` on n ints | 2,395 (n=100); 33,013 (n=1,000); 430,941 (n=10,000) | probe7 |
| Interpreter throughput | `(count 100000)`: 4,837,952 units in 288 ms ≈ 17 M units/s | probe7 |
| Live AST memory | 1 GB heap holds 1.75 M live `(+ x 'k)` terms (3.5 M metadata entries), exhausted before 3.75 M ⇒ ≈150–300 bytes/node; GC 2.3 s of the 3.5 s spent adding 1 M terms | probe8 |
| Transient AST construction | 4 M `(+ x 'k)` in 5.3 s (1.4 s GC) | probe9 |
| `body-size` on a cached 6,000-node term | 1 ms per call (O(n), not O(1)) | probe9 |
| `ensure-ast-meta (copy-tree …)` of that term | 5 ms; `instantiate` of one variable 4.7 ms | probe9 |
| `equal` hash tables keyed by ASTs | linear to 40,000 keys although `sxhash` collides totally | probe3 |
| Frame operations at 4,000 rows | 4–60 ms each, linear | probe10 |

---

## 11. WHAT CONTRADICTS, QUALIFIES OR SHARPENS THE OWNER'S HYPOTHESES

* *"Lift … is wholly in the host lisp."* Confirmed for v1 (§3). Qualification: mapping over a container is already
  expressible in the object language as a library function with a code parameter (and `:map`/`:foldr` were
  obtained by the kernel's own AU over six synthesized instances, under a host script); what is host-only is the
  *inverse* direction — pulling a specification through such a function — and that is true of pullback, fiber,
  partition, quotient, reorientation and residual too. The asymmetry is not lift versus substitution; it is that
  **terms are values of the language and frames are not**.
* *"The frame representation may be wrong."* The frame's core — a row requirement as a predicate, pullback as
  substitution, a tested no-false-pruning contract — is the small, sound part. What is demonstrably inadequate is
  narrower: constraints are unary; the solution set of a predicate exists only as recognisable syntax; rows,
  keys, positions and order are not data; one metric per frame, not per row.
* *"Residuals are clunky."* Confirmed: eight representations, a per-type `ecase`, positional-only sequence
  alignment. But the metric-decoder mechanism already treats a residual as a pullback into a delta space and is
  the kernel's one learned geometry — a nugget worth keeping.
* *"There are a good number of guards against repeating a calculation."* Confirmed and all ad hoc: closure cache,
  single-entry match memo, rejection cache, `:fit-attempted` records, printed subproblem signatures, metric replay
  templates, v2's fold memo. None arises from term or subproblem identity, because neither exists.
* *"Totality is probably a fine and necessary import."* Its tests and conservative discipline are; its code is
  welded to particular opcodes and to node metadata, and v2's extension of it is where the Stage-1 crash lives.
* *"Tolerate crashing or non-terminating behaviour and assemble guards."* The VM half is done: budgets, `:error`,
  `:unknown`, exact resumption. Missing: a structured fault, retention of outcomes in exact search, and any way
  for a program to refer to definedness.
* *"Hours of search, provided nothing is big-O hopeless."* Within my files nothing is asymptotically hopeless on
  the host. The quadratic cost is in the *tariff* for list-valued arguments; the practical ceilings are the 150–300 bytes
  per retained AST node and the exponential, capped join over coupled slots.

**Implications I am confident of** (not a design):

1. Any replacement must let one constraint mention several unknowns; the present `coupled` side channel is the
   evidence.
2. Interning terms (identity = structure) would remove, rather than optimise, the `copy-tree`/revalidate cycle,
   common-subexpression search, printed signatures and most caches listed above; but definition-dependent
   attributes (totality, price) must then live outside the interned node.
3. For any operation to be reentrant, its *operands* — rows, constraints, index sets, the outcome of a run — must be
   values of the object language. Adding opcodes that only take and return terms and sequences (the Stage-1 route)
   moves lift and AU into the VM without making specifications manipulable.
4. The VM's four-status, prepaid, resumable evaluation is the right substrate to keep; extend its result with
   (operator, arguments, position) on a fault.
5. v2 Stage 1 should be mined for its ideas (index generators, index fibers, scan/tabulate as lifts, in-language
   AU, difference-bound index safety) and its code not carried forward as is.

---

## 12. NOT DETERMINED

* Whether the Stage-1 tabulate crash is reached by any v2 run in practice: I verified the construction fails and
  that the proposal code builds exactly that term (v2/proposals.lisp:309, 431), but did not drive a v2 synthesis job
  into it.
* Whether v2's full kernel and milestone suites pass; I ran the ten in-scope modules only.
* The adaptive-hashing explanation for probe3 is an inference from SBCL's behaviour, not from its source.
* How often `coupled` requirements arise, how the product join behaves at scale, how observation buckets and the
  enumerator's size-indexed tables grow, and how `:persistence` edges are consumed: these are in
  enumerate.lisp / synthesize.lisp / proposals.lisp, outside this scope; I cite them only where they bound a
  structure in my files.
* I did not measure end-to-end search throughput or memory under a long run.
* The interpreter/tariff measurements use small synthetic programs; I did not profile a real benchmark.

---

## 13. HOUSEKEEPING NOTE FOR THE COORDINATOR

* The root tree's batteries `library/*.sexp` are **generated, not tracked**: `git ls-files library` is empty (the
  `.lisp` batteries were deleted in `b3af2e6`), and only `bootstrap/build-batteries.lisp:91-92` writes them. Root
  test modules that call `load-battery` (e.g. `define-standard-int-combinators`, tests/support.lisp:534-542) need
  them, so a clean checkout of the root cannot run `lifting`, `metrics`, `structural` or `invariants` without
  `make bootstrap`. `v2/library/` is tracked (V).
* At the start of this session `git status` showed no `library/`. An untracked `/home/tlh24/lisploop/library/`
  with eight `.sexp` files now exists, all written between 20:10:50 and 20:10:51 — the signature of one bootstrap
  run. None of my commands writes there: loading the kernel has no file-writing path (the only writer is
  `save-knowledge-library`, persistence.lisp:114, called by the bootstrap script and by the `library` and
  `batteries` test modules, which write under `/tmp` and which I did not run), and I never ran the bootstrap. My root test run at 20:13 passed *because* those files were present by then. If the repository is
  meant to end the audit unchanged, that directory is the one difference `git status` reports.

