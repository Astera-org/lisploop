# search-engine audit: the synthesizer / search machinery of `lisploop`

Auditor: `search-engine`. Scope: `enumerate.lisp`, `synthesize.lisp`, `decompose.lisp`,
`proposals.lisp`, `nogoods.lisp`, `templates.lisp`, `condense.lisp`, `messages.lisp`,
`explain.lisp`, `benchmark.lisp`, `experiments/*.lisp`, `bootstrap/recursion-schemas.lisp`
(root = primary), each diffed against `v2/`. Lens: `plan_v2_prompt.md`.

Tags: **VERIFIED** = I read the cited code or ran it. **INFERRED** = deduction or extrapolation.
All paths are relative to `/home/tlh24/lisploop` unless absolute. Line numbers are of the root
(v1) files unless prefixed `v2/`.

Method: full read of the ~7,100 lines in scope plus the callers that drive them
(`consolidate.lisp` 1-135, 205-370, 1020-1060, 1195-1300; `vm.lisp` 1-130, 355-475;
`codec.lisp` 1-135; parts of `frame.lisp`, `knowledge.lisp`, `bootstrap/build-batteries.lisp`),
`diff` of every file against `v2/` plus `git show 397499a` / `a4e19fa` to separate Stage 0 from
Stage 1, and four small confirmation experiments (scripts and raw output in
`/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine/`).
I did not read `plan_v2.md`, `plan_v2b.md`, `plan_v2.tex`. I did read `v2/STAGE0_RESULTS.md`
(a results file); claims taken from it are marked "doc-claimed".

Housekeeping note for the coordinator: an untracked `library/` directory (8 `.sexp` battery
files, written 20:10:50-20:10:51 local) appeared in the repository root during the session.
It is the output signature of `bootstrap/build-batteries.lisp` (`bootstrap/build-batteries.lisp:17-24`).
My scripts never load that file or call a battery writer; I did not create, modify or remove it.
Batteries are only read on demand (`consolidate.lisp:1662-1700`, `1898-1910`), and no code path I
exercised reads them, so my measurements are unaffected (INFERRED from the call graph).

---

## 0. The ten findings that matter most

1. **The shipped budgets are milliseconds, not hours.** One tariff unit of "work" costs about
   0.12-0.16 microseconds here (6.1-8.7 M work/s measured). `synthesize-spec-entry`'s default
   budget of 350,000 work (`consolidate.lisp:1209`) is **0.04 s of wall-clock** (VERIFIED, EXP-B);
   the 80,000 used for the seed corpus (`bootstrap/build-batteries.lisp:562`) is about 10 ms at
   that rate (INFERRED).
   The owner's "budget was very limited" is true by about five orders of magnitude.
2. **But multiplying the top-level budget does not rescue the failing tasks.** Without the
   hand-written recursion schemas, `map-adjacent` ends in `:bounded-exhaustion` with no solution
   after 2.83e9 work (8,085x the shipped budget, 369 s), and `scan` after 3.12e8 work (891x, 38 s).
   In both the search tree has **two nodes at every budget**. Raising every internal knob 100x
   as well (bound 300, depth unbounded, Stage A 1.5 M, condense 2 M) still leaves two nodes and
   no solution at 1.5e9 work. VERIFIED (EXP-B). The binding constraint is the fixed, one-shot,
   host-coded proposal space, not the budget.
3. **The solution that the schema-assisted run finds is 260 bits under a root bound of 130**
   (VERIFIED, EXP-B). Per-node bounds limit enumeration, not composition; flat enumeration at
   the root could never have reached it, at any budget.
4. **The v1 enumerator has no semantic dedupe at all.** Every syntactic expression is kept
   and reused as a subterm (`enumerate.lisp:67-82`, `199-210`). On a 6-row frame 3,788
   expressions are evaluated to find 109 distinct behaviours (35x redundancy, and the ratio
   grows with size). VERIFIED (EXP-A).
5. **v2 contains a working observational-equivalence pruner and a columnar evaluator that
   nothing calls.** `:prune-behaviors-p` / `:columnar-p` / `:effective-horizon-p` are referenced
   only in `v2/enumerate.lisp` and `v2/condense.lisp`; no caller, test or experiment passes them
   (VERIFIED by grep). Switched on by hand, pruning cuts work 11-31x (26-77x with the columnar
   evaluator) and finds the same behaviour set (VERIFIED, EXP-D).
6. **Stage A at its default budget prices 3-4 candidates** (6-row integer frame). 2,000 work
   (`synthesize.lisp:66`) buys the bare variables and a literal; the bootstrap's 15,000 buys ~25;
   the default Stage A bound (header + 18 bits, `condense.lisp:89-90`) exhausts after 36
   candidates in a two-operator grammar. VERIFIED (EXP-C). Stage A's budget is fixed at job
   creation and does not scale with the top-level budget (`synthesize.lisp:373-390`).
7. **v1 cannot run for hours as written.** `synthesis-job-trace` gains one 10-cons plist per
   scheduling turn (`synthesize.lisp:1030-1038`); at the default quantum of 32 that is ~5 GB of
   heap per 1e9 work, i.e. roughly 40 MB/s (2,050 MiB after 3.5e8 work versus 186 MiB with a
   quantum of 1e6). VERIFIED (EXP-B).
8. **Reflection exists as plumbing but is not on any production path.** Messages can be read
   as frames (`messages.lisp`), and a search trace can be condensed into a priority predictor
   (`consolidate.lisp:20-131`), but no kernel, bootstrap or milestone file calls
   `consolidate-knowledge-library` or passes `:synthesis-jobs` (VERIFIED by grep): the
   trace-to-predictor loop runs only in tests, and message frames are read only by tests and
   `experiments/yield-gate.lisp`. Within a job, messages and the trace are write-only.
9. **Policy is about 150 host-coded decisions** (158 inventoried in section 4), including literal
   knowledge of list recursion (`(at Xi 0)` / `(self (tail Xi))`, `decompose.lisp:355-363`) and, in
   the curriculum file, five recursion skeletons that the file itself says are "the shape of one
   battery function ..., written by hand" (`bootstrap/recursion-schemas.lisp:8-9`).
10. **What is genuinely clean and worth importing is small** (about 1,450 of the 7,101 LOC in
    scope, section 9): chiefly the bit-exact size-ordered enumerator (148 LOC), the resumable
    row-job stepping (~90 LOC), the ledger / staged-debt accounting (~60 LOC), observation search
    with behaviour buckets (~215 LOC), scope-signature subproblem sharing (57 LOC), the 3:1
    reserve scheduler (~125 LOC), root verification of every composed candidate (~45 LOC), and
    the message-reader-to-frame bridge (128 LOC). The rest is glue tied to the frame
    representation (~1,900 LOC) or task-shaped patching and tooling (~2,900 LOC).

---

## 1. The algorithm, end to end

### 1.1 Data structures (all host `defstruct`s; none is an object-language value)

| Structure | Where | Role |
|---|---|---|
| `language` | `enumerate.lisp:5-6` | domain, inputs, operator list, literals (`:all` or finite), typed constants |
| `enumerator` | `enumerate.lisp:59-62` | cursor (size, phase, operator index, composition, indices) + `buckets`: `equal` hash `(type size)` -> adjustable vector of every expression built so far |
| `row-job` | `enumerate.lisp:231-236` | shared resumable state: frame, language, enumerator or replay queue, private `ledger`, `phase`, `debt`, current expression/rows/evaluation, `completed-bound`, messages |
| `search-job` (includes `row-job`) | `enumerate.lisp:238-243` | exact search: results, best, rejection cache (normal form -> witness), hard edges |
| `observation-job` (includes `row-job`) | `enumerate.lisp:698-702` | observes every candidate on every row; `record-index` (expr -> record), `bucket-index` (`(type values)` -> bucket) |
| `heuristic-search`, `heuristic-model` | `condense.lisp:6-18`, `43-51` | Stage A: an observation job plus per-row residual pricing; the model is program + residual + bits + `buckets` (features) + `alternatives` |
| `decomposition` | `synthesize.lisp:8-17` | a proposal: decoder AST with one child variable, bindings (child inputs as parent expressions), child language and bound, flags `fiber-p lift-p fallback-p structural-p`, `policy-score`, `slots` for products, optional `solver` |
| `synthesis-node` | `synthesize.lisp:19-25` | id, parent, proposal, frame, language, bound, its `search-job`, phase (`:prepare -> :preparation -> :search -> :done`), staged work, priority, Stage A model, followers, reserve rows, coupled requirements, expansion state (`nil / :paying / :done`), deferred proposals, product join |
| `product-join` | `synthesize.lisp:33-34` | AND-join of product slots: per-slot model pools, coupling conjuncts, value memo |
| `staged-work`, `node-preparation` | `synthesize.lisp:37-45` | host results computed ahead of payment, published when the debt is paid |
| `synthesis-job` | `synthesize.lisp:61-71` | nodes (a list, appended to), ledger, messages, results/best, `turn`, `cursor`, `active`, `remaining`, `quantum` 32, one active root `verification`, `pending` FIFO, `refinement`, policy, Stage A budget, predictor, propagator library, expander closure, `max-depth`, `self-name` + oracle table, `nogoods` list, `scope-cache` hash, `trace` list |
| `nogood-clause` | `nogoods.lisp:5-16` | a conflict lifted to an S-expression clause over the parent scope |
| `ledger` | `vm.lisp:10` | total + alist of per-category counts |
| `message` | `enumerate.lisp:219` | `call-id`, `claim`, `evidence` plist |

There is no priority queue. The agenda is rebuilt by scanning the node list at every lane
selection (`synthesize.lisp:1003-1014`) and the best action is found by a linear `best-by`
(`synthesize.lisp:997`). Adding a node is `append` (`synthesize.lisp:153`). VERIFIED.

### 1.2 Unit of work

One unit is one VM tariff unit (`vm.lisp:33-54`). The controller advances **exactly one unit per
loop iteration**: `synthesis-node-step` calls `(search-step search 1)` (`synthesize.lisp:1259`),
verification calls `(search-step search 1)` (`1225`), and staged host work is paid one unit at a
time (`pay-staged-work`, `52-59`). A lane keeps the processor for `quantum` = 32 iterations
(`synthesize.lisp:1039-1040`, `1302`), and each lane selection itself costs one `:scheduling` unit
(`1292`). Host work that cannot be sliced (pullback, folding, propagation, the whole of Stage A,
every expander) runs synchronously on a private ledger and is then "paid off" before its result
becomes visible; the code states this is "accounting preemption, not OS-level interruption"
(`synthesize.lisp:535-536`). VERIFIED.

### 1.3 Flow

```
caller: frame + language + description-limit (+ explicit decompositions, expander, max-depth)
   |
start-synthesis (synthesize.lisp:155-200)
   root node(id 0, bound = description-limit); explicit decompositions become root children
   self-name? -> bind it globally to a partial ORACLE TABLE (activate-job-oracle, 73-87)
   |
resume-synthesis(job, absolute work-limit, stop-on-first)        (1278-1310)
   loop while ledger < limit and not finished and not (stop-on-first and best):
     refinement staged?  -> pay 1 unit                                         (1288-1290)
     quantum spent?      -> charge :scheduling; select-synthesis-lane          (1291-1292)
     else step the active lane by one unit                                     (1293-1302)

select-synthesis-lane (999-1040), first match wins:
   1. root still active and turn mod 4 = 3   -> ROOT   (the 1-in-4 root reserve)
   2. something pending or verifying          -> :verify
   3. root not yet prepared                   -> ROOT
   4. a preparation / expansion already begun -> finish paying it
   5. agenda = live non-root nodes + (:expand . node) for expandable nodes
        :round-robin  -> rotate by cursor
        :heuristic    -> any unprepared primary (non-fallback) node first;
                         else 3 turns in 4 the lowest action-priority,
                         1 turn in 4 round-robin over ALL actions            (976-997)
      (only if the agenda is empty and nothing is verifying:
       promote ONE deferred proposal into a node, 1010-1013)
   6. root

node lifecycle (synthesis-node-step 1250-1276):
 :prepare      prepare-synthesis-node (534-619), all at once on a private ledger:
                 check-parent-nogoods            -> conflict without building the frame
                 pull-through: pullback-frame | lift-frame | product-slot-frame
                 fiber-p? infer-fibers refinement
                 early propagation by callable (function-inverting) rules
                 frame-conflict-p (fold same-input rows)
                 propagate-requirements with the learned solver library
                     ambiguous narrowing -> remember to add a FALLBACK sibling
                 STAGE A: condense-heuristic on the child's own frame
                     (budget = stage-a-budget, 373-390)  -> heuristic-model
                 priority = full-path MDL of that model (489-508)
                 conflict? -> nogood clauses, UIP anti-unification, DIP repairs
 :preparation  pay the debt 1 unit/step, then finish-synthesis-preparation (879-904):
                 conflict -> close-conflicting-node: record nogoods, add DIP-repaired siblings
                 else open-prepared-node (847-877):
                    add nested children; Stage A model exact? -> queue it for root verification
                    same frozen scope as an earlier node? -> become its FOLLOWER (no search)
                    else start-search(frame, language)   <- a fresh enumerator, STAGE B leaf
 :search       search-step 1 unit; each new result -> enqueue-node-candidate (732-754)
               bound exhausted -> :done, message :bounded-exhaustion

expansion ((:expand . node) action, 1083-1101): ONCE per node per frame revision
   call the job's expander closure synchronously -> list of decompositions
   publish-node-expansion (1062-1081): sort by policy-score;
       primary proposals become nodes now; fallback-p proposals wait in deferred-proposals

candidate path:
   product slot?  join-slot-candidates (685-730): combine with the other slots' pooled models,
                  drop combinations that falsify a coupling conjunct, recurse at the parent
   otherwise      compose through every ancestor's decoder to a ROOT expression (322-331),
                  stage it on job.pending
   :verify lane   start-root-verification (621-634): a replay-mode search-job of that one
                  expression against the ORIGINAL root frame (the self-name is rebound to the
                  candidate body, 89-112; row budget 2000 for recursive jobs)
       accepted -> job.results / job.best, message :candidate
       rejected -> message :rejected (+ counterexamples);
                   refine-lifted-node-from-counterexample (1189-1217): CEGAR row promotion

end of resume-synthesis: self-name? define-function best body (totality analysis) or restore
   the oracle (1303-1306); final message :bounded-exhaustion | :candidate | :cutoff
commit (outside the job): commit-synthesis-job (consolidate.lisp:249-360):
   :function entry, UIP :nogood-schema entries, :dip-feature entries, or a residual :relation;
   decoder templates only when :register-templates-p t (default NIL, consolidate.lisp:255)
```

All of the above VERIFIED by reading the cited lines.

### 1.4 Stage A and Stage B, precisely

* **Stage A** (`condense.lisp`) is an *observation search*: enumerate the node's grammar in
  size order, evaluate every target-typed candidate on every row keeping the outcomes, and
  price each candidate as `program bits + residual bits + run-weight * run-work`
  (`condense.lisp:118-144`). The residual of a row that the candidate gets wrong is the row index
  plus the bits of a correction from the predicted value to the nearest allowed witness
  (`charge-row-witness`, `105-108`; `closest-row-witness`, `95-103`), plus relational pair/anchor
  corrections (`enumerate.lisp:607-687`). The best model, its `alternatives` (all other models,
  sorted), and its `buckets` (one representative expression per distinct value vector,
  `condense.lisp:280-287`) are what the rest of the node sees.
* **Stage B** is two things under one name: (a) the node's own exact enumerative `search-job`
  (`open-prepared-node`, `synthesize.lisp:876`), and (b) the decompositions that
  `heuristic-decompositions` (`decompose.lisp:515-666`) derives from the Stage A model:
  additive residual, metric residual, and conditional exception-patching with a searched guard.
* The two enumerations are separate. A node's `search-job` builds a new enumerator and
  re-enumerates and re-evaluates everything its Stage A just evaluated on the same frame
  (`synthesize.lisp:392-408` then `876`). Nothing is shared except the feature buckets, which go
  to guard search and the dependency expander. VERIFIED.

### 1.5 Tentative versus fallback, and the reserves

Two distinct mechanisms carry the word "fallback":

1. *Narrowing fallback.* If propagation narrowed a child frame without uniqueness evidence
   (`propagation-ambiguous > 0`), the narrowed frame is searched as the primary and a sibling is
   added with the same proposal and **no** propagators (`synthesize.lisp:584-590`, `787-797`,
   `510-514`). This is deferral, not loss.
2. *Deferred proposals.* `decomposition-fallback-p` proposals (all partial library applications
   and all learned templates) are not materialised until nothing else is left to do
   (`synthesize.lisp:1067-1075`, `1010-1013`).

Reserves: one lane turn in four goes to the root's flat enumeration while the root is live
(`synthesize.lisp:968-970`, `1021`); of the agenda's own turns, one in four is round-robin over all
actions including unprepared fallbacks (`992-997`). Net shares when everything is live: root
>= 25%, best-priced action ~56%, rotation ~19% (INFERRED from the two rules). Lifted frames keep
at most 16 active rows and hold the rest in reserve for CEGAR (`frame.lisp:1016`, `1036-1075`).

---

## 2. Budget inventory

### 2.1 What a work unit is worth (measured)

| Measurement | Value | Source |
|---|---|---|
| Throughput | 6.1-8.7 M work/s, single thread | EXP-B, VERIFIED |
| 350,000 work (default spec budget) | 0.04 s | EXP-B, VERIFIED |
| Work per enumerated expression, 6-8 rows | 340-375 | EXP-A (1,412,531 / 3,788), EXP-B (3.39e8 / 999,634), VERIFIED |
| Candidates per second | ~21,000 | INFERRED from the two rows above |
| Stage A work per priced candidate, 6 rows | 500-850 | EXP-C, VERIFIED |
| One hour | ~2.5e10 work, ~7.5e7 candidates | INFERRED |
| Whole cold battery bootstrap | "61 entries, 31 specs in 0.34 s" | doc-claimed, `v2/STAGE0_RESULTS.md:13` |

### 2.2 Top-level and per-job budgets

"On hit": **T** = terminal for that search space (candidates beyond it are never produced),
**D** = deferred (still reachable later), **R** = candidate rejected, **S** = silently truncated set.

| Budget | Value | Where | Gates | On hit |
|---|---|---|---|---|
| `resume-synthesis` work-limit | caller; 350,000 / 80,000 / 500,000 / 400,000-1,000,000 | `consolidate.lisp:1209`; `bootstrap/build-batteries.lisp:562`, `693`; `experiments/probes.lisp:58,78,114` | whole job | D (job is resumable with a larger limit, `synthesize.lisp:1281-1282`) |
| root `description-limit` | caller; 90 / 130 / 160-260 | `bootstrap/build-batteries.lisp:562`; `consolidate.lisp:1209`; `experiments/probes.lisp:57,77` | root enumeration | **T**: node goes `:done` (`synthesize.lisp:1273-1276`); no code re-opens a node with a larger bound |
| child bound | `child-bound` or the description limit, raised by literal slacks 18/24/32/40/44/48/64/72 | `decompose.lisp:43`, `506-507`, `530-531`; `proposals.lisp:142`, `164`, `167-170`, `438`, `570`, `603`, `951`; `bootstrap/recursion-schemas.lisp:132,171,189,251,325` | each child's enumeration | **T** |
| `max-depth` | 1 (`start-synthesis`), 2 (`start-heuristic-synthesis`, `synthesize-spec-entry`), 3 (one bootstrap call) | `synthesize.lisp:158`; `decompose.lisp:676`; `consolidate.lisp:1231,1234`; `bootstrap/build-batteries.lisp:692` | which nodes may expand (structural steps are free, `synthesize.lisp:205-210`) | **T** |
| `quantum` | 32 | `synthesize.lisp:63`, `156` | lane time slice | n/a |
| `heuristic-budget` (Stage A per node) | 2,000 default; 5,000 recursive; 15,000 spec; 8,000 one call | `synthesize.lisp:66`, `157`; `decompose.lisp:704`; `consolidate.lisp:1210`; `bootstrap/build-batteries.lisp:692` | quality of the Stage A model, hence priority and every Stage B proposal | **T** for that node: Stage A runs once per preparation and is not resumed |
| Stage A multipliers | x2 lifted or recursive child; x(inputs-1)^2 lifted | `synthesize.lisp:386-390` | same | hand-tuned ("plan 8, probes 2 & 5", `380-381`) |
| Stage A description limit | `heuristic-bound`, else node bound, else proposal bound, else header + 18 | `synthesize.lisp:399-404`; `condense.lisp:89-90` | Stage A enumeration depth | **T** |
| `condense-budget` / expander `work-limit` | 20,000 (50,000 / 100,000 in unused defaults) | `decompose.lisp:676`, `517`; `proposals.lisp:839`, `326` | guard search, feature search, re-condensation | **T** per expansion |
| guard-search split | half to re-condensing, a third to feature observation | `decompose.lisp:554`, `254-262`, `637` | guards | **T** |
| guard bound | header + max(18 + 2*ilog2(#inputs-1), 16 + code-eval overhead) | `decompose.lisp:532-541` | guard size | **T** |
| `*feature-guard-bits*` | 54 body bits | `decompose.lisp:166` | two-feature comparison guards | S |
| domain-feature bound | header + 28 | `decompose.lisp:233` | features compared in guards | **T** |
| `verification-row-budget` | 2,000 VM work per row (recursive jobs only) | `synthesize.lisp:64`, `159`, `631-632`; reject at `enumerate.lisp:439-441` | root verification of a recursive candidate | **R**: a correct but slow program is rejected |
| `row-satisfaction` budget | 2,000 | `synthesize.lisp:1103`, `1118` | base-case tests, CEGAR attribution | `:unknown` treated as "not satisfied" |
| coupled conjunct evaluation | 2,000 | `synthesize.lisp:680` | slot combination filter | undecided -> left to verification (D) |
| `evaluate` default | 1,000,000 | `vm.lisp:389` | every unbudgeted host evaluation | status `:unknown` |
| `frame-min-resolved-rows` | min(2, constrained rows) | `frame.lisp:278-280`; used `enumerate.lisp:445`, `condense.lisp:197` | acceptance: a candidate needs only 2 resolved rows, unresolved rows are skipped (`enumerate.lisp:432-434`) | admits false positives (351 of 351 child candidates rejected at the root in the `positions` run, EXP-B) |

### 2.3 Caps buried in proposal generation

| Cap | Value | Where | On hit |
|---|---|---|---|
| `*max-eager-proposals-per-node*` | nil (no limit) | `synthesize.lisp:1042` | D |
| `*max-coupled-slot-candidates*` | 4 models per coupled slot | `synthesize.lisp:636`, `698-705` | S (pool truncated to the 4 smallest) |
| `*max-coupled-combinations*` | 256 per product | `synthesize.lisp:639`, `724-725` | S ("a product that reaches it combines no further") |
| `*product-arity-limit*` | 6 components / holes | `proposals.lisp:385`, `397`, `499`, `579` | S (no proposal) |
| sufficient-statistic features | first 2 by syntax work | `proposals.lisp:361-362` | S |
| `*library-code-argument-bits*` | 20 body bits | `proposals.lisp:881`, `906` | S |
| `*library-code-argument-work*` | 1,000 enumerator steps per code type | `proposals.lisp:884`, `905` | S |
| `*library-partial-proposal-limit*` | 256 | `proposals.lisp:887`, `945-946`, `1363-1364`, `1380-1381` | S (`return-from`, no message) |
| first-order argument guesses | unused parent vars, empty-row target, constants, `'()`, int literals, type default | `proposals.lisp:71-106` | S (fixed set) |
| library primary path | only functions with exactly one code parameter | `proposals.lisp:176-177` | others go to the fallback-only partial path |
| empty-row compatibility fold | 500 | `proposals.lisp:118` | proposal dropped |
| guard choice | one best guard only | `decompose.lisp:306-318` | S |
| conditional base | first valid base among model + alternatives | `decompose.lisp:611-628` (`find-if`) | S |
| lockstep base | first candidate satisfying the empty rows | `decompose.lisp:460-466` | S |
| multi-hole template | `lift-frame` budget 4,000 / 4 rows; predicate bound header + 20; 3,000 work | `proposals.lisp:1290-1291`, `1321` | S |
| DIP repairs | `max-repairs` 1, `max-candidates` 2, context = variables and one-step applications | `nogoods.lisp:541`, `490`, `446-487` | S |
| extra nogood collection fold | 1,000 | `nogoods.lisp:175` | S |
| `*max-active-lifted-rows*` | 16 | `frame.lisp:1016` | D (reserve rows, CEGAR) |
| `lift-frame` fold budget, fibers per row | 10,000; max(4, 2 + ceil(16 / rows)) | `frame.lisp:1194`, `1211-1213` | rows not unfolded stay in reserve (D) |
| `*unfold-work-per-row*` | 4,000 x 2 x max(4, rows) | `synthesize.lisp:1152`, `1160-1163` | CEGAR finds no row (S) |
| `frame-conflict-p`, `product-slot-frame`, `fold-constants` | 10,000 each | `frame.lisp:300`, `582`; `requirements.lisp:529` | conflict or narrowing missed |
| `infer-fibers` | 1,000,000 work, 2,048 branches | `fibers.lisp:156` | cutoff message |
| `*propagator-member-limit*` | 8 | `laws.lisp:674` | no inversion |
| `*projection-key-work*`, `*projection-key-slack*`, `*row-order-star-centres*` | 20,000; 40; 8 | `proposals.lisp:650-656` | S (row-order induction has no kernel caller anyway, see 5) |
| `*closure-limit*` | 32,768 compiled nodes, then cleared | `vm.lisp:421`, `455-456` | recompile (sound) |
| priority predictor clamp | [-24, +48] bits | `synthesize.lisp:506` | bounded influence |
| `consolidate` trace model budget | 10,000 | `consolidate.lisp:96` | predictor quality |

### 2.4 Benchmark-only limits

`+benchmark-chunk+` 1e6, `+benchmark-work-cap+` 1e10, `+benchmark-heap-cap+` 768 MiB
(`benchmark.lisp:13-15`); wall seconds from the command line. The benchmark measures the flat
`search-job` over GF(5) with `+`/`*` only (`benchmark.lisp:29-52`).

### 2.5 If the top-level budget is multiplied by 1000: what still binds

Experiment (EXP-B; root kernel, per-spec whitelist grammar, `start-recursive-synthesis` exactly
as `synthesize-spec-entry` calls it, recursion schemas off unless stated):

| Run | Knobs | Result |
|---|---|---|
| `map-adjacent`, schemas ON | bound 130, depth 2, Stage A 15,000 | **solved at 109,012 work, 0.02-0.05 s; solution is 260 bits** via `:lookahead-inductive` |
| `map-adjacent` | same, 350,000 work | cutoff, 0.04 s, 2 nodes |
| `map-adjacent` | same, 3.5e8 work (1000x) | cutoff, 40-51 s, **2 nodes**, root at body size 75 of 82, 999,634 expressions retained |
| `map-adjacent` | same, run to the end | **`:finished-without-solution` at 2,829,937,699 work (8,085x), 369 s**; root exhausted: 9,121,603 expressions, 7,203,492 rejections |
| `map-adjacent` | depth unbounded, 5e6 work | still 2 nodes |
| `map-adjacent` | bound 300, depth unbounded, Stage A 1.5e6, condense 2e6, 1.5e9 work | cutoff, **2 nodes**; the one child exhausted its whole grammar to 233 body bits with 1,526 expressions |
| `scan` | bound 130, depth 2, Stage A 15,000 | **`:finished-without-solution` at 312,017,873 work (891x), 38 s**, 2 nodes |
| `positions` | same, 7e8 work (2000x) | cutoff, 2 nodes; 351 child candidates, all 351 rejected at the root |

All VERIFIED (raw output: `exp-b-*.out` in my scratch directory). Why, from the code:

1. **Expansion is one-shot and host-authored.** A node expands once per frame revision
   (`node-may-expand-p`, `synthesize.lisp:212-216`; set `:done` at `1081`). If the fixed generators
   return nothing new, the tree stops growing regardless of budget or `max-depth`. In all three
   runs the single child was the kernel's own inductive split and its expansion returned nothing.
2. **The kernel's only recursion skeleton is fixed.** The recursive call is on `(tail Xi)` of
   each sequence input with every other argument unchanged (`inductive-projections`,
   `decompose.lisp:355-363`; `typed-recursive-call`, `341-353`), and the child's grammar has
   `:at`, `:tail`, `:if`, the self call and (mostly) `:=` removed (`inductive-child-language`,
   `365-382`). A second case split (`map-adjacent`), a changed accumulator (`scan`), or an
   incremented counter (`positions`) is therefore not expressible in the child at any size.
   The hand-written file supplies exactly these: lookahead, state threading, countdown, counter
   (`bootstrap/recursion-schemas.lisp:79-137`, `161-194`, `195-256`, `257-330`).
3. **Node bounds are terminal** (2.2). The root's 82 body bits of flat enumeration is a
   finite space with no solution in it; the true program is 260 bits.
4. **Stage A does not scale with the job** (2.2), so the hit mask, guard and base case that
   Stage B is built from do not improve with more top-level budget.
5. **Recursive jobs discard any candidate that does not call the function being defined**
   (`valid-job-node-candidate-p`, `synthesize.lisp:356-366`).
6. Silent truncations in 2.3 (single guard, first valid base, top-2 features, 256-proposal and
   256-combination caps, 2,000-work row verification) each remove alternatives without a message.

Engineering limits that would stop an hours-long run even where the space is open:

* `synthesis-job-trace` growth, ~5 GB per 1e9 work at quantum 32 (finding 7). VERIFIED.
* Every enumerated expression is retained for the life of the job (`enumerate.lisp:79-81`):
  9.1 M expressions ~ 1.8 GB (heap 1,966 MiB against a 160 MiB baseline; EXP-B, quantum 1e6 so
  the trace is negligible). VERIFIED.
* Agenda construction is O(nodes) per lane selection and node insertion is O(nodes)
  (`synthesize.lisp:1003-1014`, `153`); `add-synthesis-node` also scans all nodes for a product
  sibling (`142-147`). Quadratic once the tree is large (INFERRED; the trees I ran had 2-3 nodes).
* One `:cutoff` message is pushed per `resume-synthesis` call (`1307-1310`); harmless.

Verdict on the owner's hypothesis: **supported in its strong form, contradicted in its weak
form.** The budgets were absurdly small in wall-clock terms, and "nothing very interesting was
findable ... with rigid enumeration without clean reentrancy and reflection, so it all had to be
imported" is exactly what the runs show. But "the budget was the oversight" alone is not
enough: at 1000x-8000x the same kernel reports exhaustion, because the space it searches is
closed by host-coded generators and bounds.

---

## 3. Enumeration

### 3.1 How candidates are generated

Bottom-up, by **exact body size in codec bits**, not top-down with holes (`enumeration-step`,
`enumerate.lisp:131-214`). For each size `s` in turn the phases are: variables; literals (all
integers whose code is exactly `s` bits, non-negative then negative, when literals are `:all`,
`84-96`, `152-169`; or the finite list); the two booleans at size 3 if the language mentions
`:bool` (`170-173`); typed constants (`174-182`); then, for each operator in list order and each
composition of `s - overhead` into `arity` positive parts in lexicographic order
(`108-120`), the full Cartesian product of the typed buckets of those sizes (`183-210`). One
cursor step yields at most one expression ("No eager Cartesian products", `132`). VERIFIED.

Consequences:

* Order of generation is order of description length, so the first accepted candidate is a
  minimum-size one for the node; `run-weight` can reorder only among accepted candidates
  (`candidate-score`, `382-383`).
* It is typed: buckets are keyed by `(type size)` and an application draws its arguments from
  the buckets of its operator's argument types (`64-65`, `199-200`). Expressions of every type
  are built; only target-typed ones are evaluated (`admit-search-candidate`, `417-424`).
* Sizes are exact: `index-expression` asserts the enumerator size equals the codec size
  (`77-78`). Measured prices: variable 3 bits (2 inputs), literal 0 = 3, literal 1 = 6, `+`/`*`/`-`
  /`if` overhead 6, `=` 9, `<` 14, `cons` 11, `tail` 14, `at` on a sequence 17 (EXP-A, VERIFIED).

### 3.2 Dedupe: what exists and what does not

| Mechanism | Where | Scope | Status in v1 |
|---|---|---|---|
| Syntactic duplicate removal on the *language* (operators, constants, literals) | `enumerate.lisp:22-25` | language construction | active |
| Constant already offered by the literal/boolean phase is skipped | `enumerate.lisp:177-181` | enumerator | active |
| **Observational equivalence in the enumerator** | none | - | **absent**: every expression is filed and reused (`67-82`) |
| Commutativity / associativity canonical forms | none | - | absent: both `(+ x y)` and `(+ y x)` are built (`199-210`) |
| Observation buckets `(type, values)` | `enumerate.lisp:762-781`, `783-803` | observation jobs only | groups *records* by behaviour for reporting and features; does not prune the enumerator |
| Rejection cache keyed by law normal form | `enumerate.lisp:396-398`, `472-498` | a `search-job` started with `:laws` | **dead in hierarchical synthesis**: `synthesize.lisp:629`, `876`, `1128` never pass `:laws`; no kernel file does (VERIFIED by grep) |
| Subproblem sharing by frozen scope signature | `synthesize.lisp:264-276`, `855-877`, `831-845` | nodes of one job | active; cleared on any CEGAR revision (`1150`) |
| Proposal queue dedupe | `enumerate.lisp:247-253` | replay mode | active |
| AST metadata cache (type, bits, syntax work, free vars) | `ast.lisp:32`, `1156-1175` | global, weak | active |
| Compiled closure cache | `vm.lisp:421-459` | global, 32,768 nodes | active |

Measured cost of the absent dedupe (EXP-A, 6 rows, VERIFIED):

| Grammar | Body bits | Target-typed expressions evaluated | Distinct behaviours | Redundancy |
|---|---|---|---|---|
| `{+,*}`, literals {0,1}, 2 int inputs | 26 | 468 | 38 | 12.3x |
| same | 30 | 3,788 | 109 | 34.8x |
| `{+,*,-,if,=,<}`, same | 24 | 1,704 | 91 | 18.7x |

### 3.3 What persists and what is recomputed

* Persists within one job: its enumerator buckets; within a synthesis job: the scope cache,
  the nogood list, product-join pools and value memo (`synthesize.lisp:645-662`), Stage A models
  and feature buckets on the node.
* Shared between nodes: only via follower/canonical reuse of an *identical* frozen scope.
  Two children with the same language and different frames each re-enumerate the syntax from
  size 1. Syntax construction is cheap relative to evaluation (evaluation is 84% of the ledger
  in EXP-A), so the loss is in re-evaluation, not re-construction. VERIFIED / INFERRED.
* Recomputed from scratch: Stage A then the node's own search (1.4); the node's search after
  every CEGAR row promotion (`restart-revised-node`, `synthesize.lisp:1124-1150`, a new
  `start-search` and all descendants closed); Stage A again inside `heuristic-decompositions`
  whenever the node carries no model (`decompose.lisp:554-560`; `experiments/yield-gate.lisp:216-226`
  reports "Nodes that ran Stage A more than once"); root verification re-evaluates the composed
  program on every root row (necessary for soundness).
* Across jobs: nothing of the search itself. Only library entries (functions, nogood schemas,
  DIP features, optionally decoder templates and a priority predictor).

### 3.4 Growth

The code is a prefix code, so at most 2^s programs have exactly `s` bits. Measured (EXP-A,
VERIFIED):

| Grammar | Growth | Evidence |
|---|---|---|
| `{+,*}`, literals `:all` | ~x2.0 per bit (saturates the code) | 2,272 / 4,696 / 9,024 / 16,640 new at 20-23 bits; 36,992 / 72,480 / 148,800 at 26-28 |
| `{+,*}`, literals {0,1}, 2 inputs | x11.5-15 per 9 bits (one more binary node) = ~x1.33 per bit | cumulative 22 @12, 252 @21, 3,788 @30 |
| `{+,*,-,if,=,<}`, same leaves | ~x1.43 per bit | 597 @21, 15,094 @30 |
| list grammar of `map-adjacent` (cons, tail, at, =, if, code-eval) | ~x1.25 per bit overall, lumpy by size | retained expressions 1,102 while at size 41; 999,634 at 75; 4,319,428 at 78; 9,121,603 with size 82 complete (EXP-B) |
| operators 2 -> 6 at 30 bits | x4.0 expressions | 3,788 vs 15,094 |

Cost model: time = Theta(N(s) x rows x evaluation), N(s) ~ beta^s; memory = Theta(N(s))
(everything retained). At ~21,000 candidates/s an hour is ~7.5e7 candidates. In the list
grammar that is roughly 92 body bits (INFERRED: 9.1 M at 82 bits in 6 minutes, x1.25 per bit).
The 260-bit `map-adjacent` program has 212 body bits; flat enumeration would need of order
1e11-1e12 times more (1.22^130 to 1.25^130), i.e. it is hopeless, whereas the decomposed
search found it in 109,012 work. With v2's behaviour pruning switched on, the two-operator grammar grows
38 / 109 / 143 / 502 / 1,509 behaviours at 26 / 30 / 36 / 42 / 48 bits, about x1.14-1.2 per bit
(EXP-D, VERIFIED): a much smaller base, still exponential.

### 3.5 How the grammar is chosen

Always an explicit operator list handed to `make-language` (`enumerate.lisp:8-25`; default `+`
and `*`). In the bootstrap it is a **per-spec whitelist** stored in the spec's metadata
(`consolidate.lisp:1223-1227`). The lists are hand-picked and tight: `foldl` is given exactly
`tail, at, =, if, code-eval`, the five operators of its answer, plus the constant `'()`
(`bootstrap/build-batteries.lisp:622-623`); `positions` gets `cons, tail, at, =, if, +` and
literals `(0 1)` (`669-671`). VERIFIED. The whole active library is never the grammar in v1.
Library functions enter in two ways: named in the operator list (e.g. `(op :seq-corr)`,
`bootstrap/build-batteries.lisp:872`), or as lifted decoders through `library-decompositions`,
whose candidate set is the caller's `:functions`, else the higher-order operators in the
language, else **every registered function** (`proposals.lisp:16-21`). v2 adds an experiment
switch `*use-active-library-grammar*` (`v2/consolidate.lisp:1208`, `1264-1271`); with it and no
schemas, 9 of 16 bootstrap specs are solved and 8 are sound on held-out rows at 350,000 work
(doc-claimed, `v2/STAGE0_RESULTS.md:99-100`).

---

## 4. Hard-coded policy inventory

Classes: **D** soundness-preserving dedupe / memo / "do not compute twice" guard;
**C** incompleteness-inducing cap or prune; **O** ordering heuristic; **K** domain knowledge
(structure smuggled in); **A** accounting convention. All VERIFIED by reading unless noted.

### 4.1 `enumerate.lisp`

| Line | Class | Policy |
|---|---|---|
| 8 | K | default operators are `+` and `*` |
| 22-25 | D | duplicate operators / constants / literals removed from a language |
| 84-96, 152-169 | O | integer literals by exact code length, non-negative pass then negative pass |
| 149-213 | O | phase order variables, literals, booleans, constants, applications; operators in list order; compositions lexicographic |
| 170-173 | K | booleans offered only at size 3 and only if the language mentions `:bool` |
| 177-181 | D | constant already produced by an earlier phase is skipped |
| 247-253 | D, O | replay queue deduplicated and sorted by description size |
| 282-284 | A | `completed-bound` advances only when a size is fully enumerated |
| 382-383 | O | score = size + run-weight x run-work |
| 396-398, 493-498 | D | rejection cache: a candidate whose law normal form was refuted is rejected unevaluated (needs `:laws`) |
| 417-424 | C | only target-typed candidates are evaluated |
| 430-441 | C | error on any row rejects; `:unresolved` row is skipped; row-budget overrun rejects |
| 443-447 | C | accept when at least `min(2, constrained rows)` rows resolved |
| 449-470 | C | hard `:equal` / `:distinct` edges checked row by row |
| 550-551 | A | a row evaluation stops at its budget so overruns are slice-independent |
| 689-696 | D | observed agreement only within the same scope and type |
| 725-726, 762-781 | D | record index (expression -> record), bucket index (behaviour -> bucket) |
| 736-742 | K | "invariant" = equal across all pairs; "informative" = also separates anchors |
| 829-839 | C | without `retain-outcomes`, observation of a candidate stops at its first failing row |

### 4.2 `condense.lisp`

| Line | Class | Policy |
|---|---|---|
| 20-22 | O | models ordered by score, then program bits |
| 38-39 | O | `alternatives` = all other models, sorted |
| 64-79 | K | on a frame with an empty-sequence row Stage A drops `:at`, `:tail`, `:if`, `:=` and oracle functions and adds literals 0, 1 |
| 89-90 | C | default bound header + 18 |
| 105-108 | A | residual = row index bits + correction bits |
| 110-116 | A | unresolved constrained row priced by its cheapest listed witness |
| 137-138, 242-243 | D | witness packets remembered so Stage B need not re-run metric decoders |
| 197 | C | model recorded only if at least `min(2, ...)` rows resolved |
| 248-249 | C | "No available correction witness" -> candidate abandoned |
| 269-278 | C | stop on first exact total model when `stop-on-exact-p` and run-weight is 0 |
| 280-287 | D | feature buckets: first (smallest) representative per behaviour |

### 4.3 `synthesize.lisp`

| Line | Class | Policy |
|---|---|---|
| 63-66 | C | quantum 32, verification row budget 2,000, Stage A budget 2,000 |
| 73-112 | K | recursion by rebinding the *global* function name between oracle table and candidate body |
| 142-147 | D | slots of one product share one join |
| 205-210 | K | structural decompositions do not count toward depth |
| 212-221 | C | expansion only above `max-depth`, once |
| 264-276, 855-877 | D | frozen scope signature; identical subproblem becomes a follower |
| 356-366 | C, K | a recursive job's candidate must call the function being defined (unless inside a lifted library branch or a slot) |
| 373-390 | O, K | Stage A budget x2 and x(inputs-1)^2 rules |
| 399-404 | C | Stage A bound fallback chain ending in header + 18 |
| 407 | C | Stage A stops at an exact model inside lifted / recursive children |
| 410-420 | D | `*precomputed-program-bits*`: avoid recomposing a model for the predictor |
| 430-433 | A | feature defaults of 100 when there is no model |
| 447-457, 489-508 | O | priority = full-path program bits + residual bits + policy-score/2 (if not exact) + 16 x coupled requirements + run-weight x run-work; predictor delta clamped to [-24, 48] |
| 510-514 | C | fallback branch gets no propagators |
| 523-532 | C | DIP only for lifted or pure-projection proposals |
| 552-558 | D | nogood check before building the child frame |
| 584-590 | C | ambiguous narrowing keeps the original as a fallback sibling |
| 595-596 | C | Stage A runs only if the node has a parent or may expand, and routing is heuristic or expanding |
| 598-604 | C | nogoods recorded only for `:incompatible-rows` conflicts of pure-projection or lifted proposals with >= 2 keys |
| 607-610 | K | UIP anti-unification only for lifted proposals |
| 636-643, 698-705, 724-725 | C | coupled-slot pool 4, 256 combinations |
| 645-662 | D | slot model row values memoised in the join |
| 703 | D | a model already in a slot pool is not added twice |
| 729 | D | duplicate composed products dropped |
| 756-761, 860-869 | O | exact Stage A program goes straight to root verification |
| 799-805, 817-823 | D | a DIP repair is not added if a sibling already poses the same child problem |
| 812-816 | D | nogoods deduplicated by identity |
| 861-863 | C | a node whose Stage A model is exact with nothing unresolved is not expanded |
| 870-871 | C | follow a canonical node only if its bound covers this one |
| 934-946 | O | a satisfied product slot yields to slots that have no model |
| 948-955 | O | a structural node is priced at most as its parent |
| 957-966 | O | ties: expansion -1/2, structural search -1/4 |
| 968-970, 1021 | O | one lane turn in four to the root |
| 976-997 | O | prepare unprepared primaries first; then 3:1 best-price to round-robin |
| 1010-1013 | O | a deferred proposal is promoted only when nothing else is left |
| 1016-1017, 1025 | A | staged work already begun is paid first |
| 1022 | O | verification before any other non-reserved work |
| 1066-1075 | O | proposals sorted by policy score; primaries now, fallbacks deferred; if no primary, exactly one fallback |
| 1103-1116 | C | row-satisfaction budget 2,000; error counts as refuted |
| 1134-1150 | D | on revision: followers detached, descendants closed, pending work of the subtree dropped, scope cache cleared |
| 1152-1163 | C | unfold budget 4,000 x 2 x max(4, rows) |
| 1165-1172 | D | reserve rows deduplicated by content |
| 1197-1214 | O | CEGAR promotes one refuted reserve row at the nearest ancestor that has one |
| 1261-1266 | D | do not re-verify the candidate already promoted from Stage A; skip invalid ones |
| 1269-1272 | D | a canonical node's candidates are forwarded to its followers |

### 4.4 `decompose.lisp`

| Line | Class | Policy |
|---|---|---|
| 6-11 | K | additive residuals for `:int`, prime fields and tuples of them |
| 13-24 | K | tuple residual decoder built componentwise with `:at` |
| 43, 530, 570 (proposals) | C | residual slack at least 18 bits |
| 49-67 | D | cached metric-decoder hits from Stage A reused instead of re-running the decoder |
| 59 | K | `:+` metric decoder skipped where the additive decoder applies |
| 84-99 | K | hit mask / active mask rules for guards |
| 101-126 | K | default guard language: `=` at the domain and every input type, `<` if present, `(if :bool)`, the domain operators less `= < if` (and `tuple` without `at`), literals plus {0,1}, empty-sequence constants |
| 128-154 | K | every one-step Boolean `:code-eval` application over the inputs is a guard candidate |
| 166 | C | feature guard at most 54 body bits |
| 187-217 | K | guards from pairs of features: `=` at equal types, `<` both ways on integers, never two literals |
| 219-238 | K | features observed without `:if`, bound header + 28 |
| 254-262 | O | a third of the guard budget to feature observation for Boolean targets |
| 297-318 | O | guard must be one-sided sound; most hits covered, then shortest; feature pairs only if no exact separator |
| 320-326 | K | any oracle-backed operator in the language is taken as the function being defined |
| 328-339 | K | a base case must answer every empty-sequence row |
| 341-363 | K | **recursion skeleton: head `(at Xi 0)`, call of self on `(tail Xi)`** |
| 365-382 | K, C | child grammar loses `:at :tail :if`, self, and `=` |
| 384-414 | K | the skeleton is triggered by a guard of the form `(= Xi '())` |
| 416-513 | K | lockstep recursion over >= 2 sequences; base candidates in a fixed order; slack 72 with a code parameter, else 40 |
| 532-541 | C | guard bound formula |
| 549-553 | K | "empty-sequence frame" test |
| 554 | O | half the expander budget to re-condensing when no model is supplied |
| 561-566 | C | no decomposition of an exact model (that calls self) |
| 575-578 | K | additive branch skipped when the base is literal 0, or for recursive jobs with empty rows or tuple targets |
| 595-596 | K | metric branch skipped for recursive empty-sequence frames |
| 602-628 | O, C | conditional base = first valid among model and alternatives |
| 676, 704 | C | condense budget 20,000, depth 2, recursive Stage A budget 5,000 |
| 716-718 | K | the root grammar of a recursive job excludes the function being defined |

### 4.5 `proposals.lisp`

| Line | Class | Policy |
|---|---|---|
| 16-21 | O | candidate functions: named, else higher-order operators of the language, else all registered |
| 24-36 | C | excludes self, auto-retyped and archived functions, bodiless or oracle functions, functions without code parameters or with operator-sorted code parameters |
| 40-69 | K | sequence functions are retyped to the frame's element types |
| 71-106 | K, C | fixed menu of first-order argument guesses |
| 108-120 | C | a decoder that contradicts an empty-sequence row is not proposed |
| 122-127 | K | inputs the decoder does not consume pass through to the child |
| 146, 149 | O | policy scores 8 (partial application) and 6 (learned template) |
| 164, 167-170 | C | child bound header + 24; slack 32 if the child may call defined functions |
| 176-177 | C | primary path only for one-code-parameter functions whose return type equals the target |
| 198-209 | O, C | descriptor verdicts give compatibility and policy score; verdicts cached per input (D) |
| 294-307 | K | sufficient statistic: strictly merges fibers without colliding outputs |
| 309-323 | D | Stage A buckets reused as features instead of a second observation search |
| 341-354 | C | sufficient-only mode needs >= 2 inputs, a non-recursive job, a non-exact model, >= 3 pinned rows with a repeated output |
| 357-362 | O, C | features exclude bare variables and literals; cheapest two |
| 385-402 | C, K | tuples of up to 6 components are projected |
| 404-417 | K | child loses the `:at` / `:tuple` operators the structural step already applied |
| 419-424 | K | "rows pin values" trigger |
| 442-469 | K | code-slot child grammar: quoted operators of the hole's sort, or quoted variables and literals |
| 471-485 | C | an operator hole no slot could fill kills the product |
| 487-541 | K | anti-unifier hole lowered to a literal slot when every tree fills it with a literal and no input is code |
| 543-558 | D | plain product omitted when identical to the operator-hole product |
| 578-605 | K | which structural proposal applies: tuple target, code target, tuple inputs with scalar target |
| 611-612 | C | no structural proposal at the root of a recursive job |
| 632-648 | D | canonical row order by printed content |
| 650-787 | K | row-order induction (chain versus star versus independent pricing); no kernel caller |
| 881-887 | C | 20 bits, 1,000 steps, 256 proposals |
| 898-913 | D | per-type cache of enumerated code arguments (`939-941`) |
| 928-931 | C | partial path only for multi-code functions or functions with no matching parent input |
| 949-953 | O | partial applications are `fallback-p`, slack 24 |
| 980-985, 1005-1009 | D | a template already held is not registered twice |
| 1047-1051, 1078-1083 | C | which templates may be generalised: observed, non-lifted, live, one hole, child not mentioned elsewhere |
| 1103-1125 | C | template proposed only while its dependencies and licensing laws stand |
| 1127-1151 | K | sequence-element retyping of templates |
| 1210-1236 | K | two-hole "predicate + map" templates and the `:strict-contraction-p` trigger |
| 1257-1265, 1303-1321 | K | predicate candidates: comparisons of atoms with literals {0,1}, then a bounded observation search |
| 1353-1355 | O | template score = 6 + descriptor delta |
| 1396, 1326 | O | learned templates are `fallback-p` |

### 4.6 `nogoods.lisp`

| Line | Class | Policy |
|---|---|---|
| 18-28 | D | nogood identity (parent, kind, sorted keys or sorted pattern conjuncts) |
| 44-60 | D | decoders compared up to the name of the child variable |
| 136-144 | K | "parent incompatible" test for lifted conflicts |
| 175-199 | C | additional colliding buckets collected with a 1,000-unit fold budget |
| 222-235 | C | UIP only over clauses of one parent, kind and child type |
| 268-277 | K | only hole-equals-closed-term conjuncts constrain a pattern match |
| 283-307, 318-335 | K, C | library nogood schemas apply only to a decoder that maps its code pointwise over the parent's single list input, with a one-input code |
| 397-430 | D | three reuse cases (projection agreement, parent incompatibility, same lifted decoder) |
| 446-487 | K, C | DIP context candidates: non-code non-sequence variables and one-step applications, excluding `= < if tuple cons`; `(at x 0)` for `:at` |
| 518-538 | O | library `:dip-feature`s tried before grammar candidates; at most 2 |
| 541, 547-548 | C | one repair; no repair of a repair |

### 4.7 `bootstrap/recursion-schemas.lisp`

| Line | Class | Policy |
|---|---|---|
| 16-42 | K | base-case candidate menu, including tuples of defaults and inputs |
| 79-137 | K | two-step lookahead skeleton (`map-adjacent`, `last-or`), slack 48, score 4 |
| 161-176 | K | state-fold skeleton (`foldl`), slack 44, score 4 |
| 177-194 | K | state-scan skeleton (`scan`), score 3 |
| 195-256 | K | guarded countdown skeleton (`shift-seq`), slack 64, score -4 |
| 257-330 | K | incrementing counter skeleton (`positions`, `best-shift`), slack 48, score -2 |
| 340-350 | C | when the expander fires |

### 4.8 Elsewhere but on the search path

`frame-min-resolved-rows` (`frame.lisp:278-280`, C); `select-active-fiber-rows` 3:1 locality
window (`frame.lisp:1036-1075`, O/K); `*closures*` memo and its version stamp (`vm.lisp:421-430`,
D); `*last-code-match*` single-entry memo (`vm.lisp:118-130`, D); `vm-versions` stamp checked by
validated programs (`vm.lisp:73-85`, D); `current-propagator-library` refresh against the function
table version (`synthesize.lisp:515-517`, D).

Counted from the tables above: 158 rows; 52 carry C, 51 K, 30 D, 30 O, 6 A (a row with two
classes is counted under both). None is represented as data the search can inspect or change; the one learned
influence is the clamped predictor delta (section 7).

---

## 5. Proposal generators and decompositions

"General" means it uses only types, the frame and the grammar. "Smuggles" names what specific
knowledge is built in. All VERIFIED by reading.

### 5.1 In the kernel

| # | Name tag | Where | Proposes | Trigger | Verdict |
|---|---|---|---|---|---|
| 1 | `:fibers` | `proposals.lisp:824-828`; refinement `synthesize.lisp:568-570` | same target on a frame refined by `infer-fibers` | caller passes `:fibers` | general |
| 2 | `(:dependency feature)` | `proposals.lisp:274-292` | target as a function of one feature (or of nothing) | caller passes `:dependencies`, or expander 7/8 | general |
| 3 | `(:library fn . args)` | `proposals.lisp:152-240` | `fn(parent input, guessed first-order args, CHILD code)`, child = the code body over the lifted frame | a registered higher-order function with exactly one code parameter and matching return type; descriptor-compatible | general mechanism; argument menu (71-106) and empty-row check are list-shaped |
| 4 | `(:library-partial fn slot args)` | `proposals.lisp:915-953` | any code slot lifted, sibling code slots filled by enumeration to 20 bits | > 1 code parameter, or no matching parent input | general, heavily capped, fallback-only |
| 5 | `(:learned-template id)` | `proposals.lisp:1331-1398` | a remembered single-hole decoder context re-instantiated on this frame | active live `:decoder-template` of matching target | general (retrieval); templates are registered only with `:register-templates-p t` (`consolidate.lisp:255`) |
| 6 | `(:learned-template id pred)` | `proposals.lisp:1195-1329` | two-hole template: predicate hole filled by a small comparison search, map hole lifted | template with `:child-ids (pred map)`, Boolean code hole | smuggles the filter-then-map comprehension shape and a length-contraction trigger |
| 7 | dependency expander, sufficient-only | `proposals.lisp:325-370` | up to 2 features that are sufficient statistics | >= 2 inputs, not recursive, model not exact, repeated outputs | general |
| 8 | dependency expander, `:all` | `proposals.lisp:371-380` | every Stage A feature and the empty context | caller option | general |
| 9 | `(:heuristic-additive program)` | `decompose.lisp:575-593` | `base(X) + Z` (componentwise on tuples) | total non-exact model, additive target type | smuggles `+` as the residual group |
| 10 | `(:heuristic-metric op program)` | `decompose.lisp:30-82`, `595-600` | `op(base(X), Z)` for a library metric decoder | decoder describes some miss | general given a library of decoders |
| 11 | `(:heuristic-conditional guard program)` | `decompose.lisp:602-665` | `(if G base Z)` or `(if G Z base)` | a sound one-sided guard is found | general idea; guard grammar is hand-built (101-126, 187-217) |
| 12 | inductive sequence lift (same tag as 11) | `decompose.lisp:384-414` | child of the non-empty branch receives `(at Xi 0)` and `(self ... (tail Xi) ...)` | the guard found is `(= Xi '())` | **smuggles structural recursion on lists** |
| 13 | `(:lockstep-inductive ids base)` | `decompose.lisp:416-513` | nested empty checks over >= 2 sequences, child gets all heads and the lockstep call | >= 2 sequence inputs with `:at`, `:tail`, `=` available | **smuggles zip-style recursion** |
| 14 | `(:tuple-product i)` | `proposals.lisp:579-587` | one slot per tuple component, AND-joined | tuple target whose rows pin values | general |
| 15 | `(:constructor-au i)`, `(:constructor-au-operators i)` | `proposals.lisp:487-558`, `588-597` | anti-unify the target code trees; one slot per hole | code target with >= 2 distinct pinned trees | general; the closest thing in the kernel to "substitution as pattern of the graph" |
| 16 | `:components` | `proposals.lisp:599-605` | tuple inputs replaced by their components | scalar target, tuple among inputs | general |
| 17 | `(:dip-repair name sep)` | `nogoods.lisp:540-580` | the conflicting proposal plus one separating context binding | incompatible-rows conflict on a lifted or projection child | general, shallow (one-step contexts) |
| 18 | `(:fallback name)` | `synthesize.lisp:787-797` | the same proposal without propagators | ambiguous narrowing | general |
| - | explicit `decompositions` | `synthesize.lisp:199` | whatever the caller passes | caller | caller knowledge by definition |

Not a decomposition but adjacent: `induce-row-order` / `with-induced-row-order`
(`proposals.lisp:707-818`) has **no caller outside tests** (`tests/topology.lisp:213-238`; VERIFIED
by grep), as does `start-selector-search` (`proposals.lisp:832`).

### 5.2 Curriculum file `bootstrap/recursion-schemas.lisp` (supplied through `:expanders`)

| # | Name tag | Lines | Shape | For |
|---|---|---|---|---|
| 19 | `:lookahead-inductive` | 79-137 | `(if (= xs ()) b0 (if (= (tail xs) ()) b1 Z))`, child sees two heads and the call | `map-adjacent`, `last-or` |
| 20 | `:state-fold-inductive` | 161-176 | `(if (= xs ()) s (self (tail xs) Z ...))` | `foldl` |
| 21 | `:state-scan-inductive` | 177-194 | `(if (= xs ()) () (cons Z (self (tail xs) Z ...)))` | `scan` |
| 22 | `:countdown-inductive` | 195-256 | `(if (= xs ()) b (if (< 0 k) Z b'))` with `(self (tail xs) (- k 1))` | `shift-seq` |
| 23 | `:counter-inductive` | 257-330 | `(if (= xs ()) b Z)` with `(self (tail xs) (+ k 1))` | `positions`, `best-shift` |

The file's own header: "Recursion schemas the battery curriculum is given, not ones the kernel
finds ... Each is the shape of one battery function ..., written by hand"
(`bootstrap/recursion-schemas.lisp:2-9`). Doc-claimed effect: with the per-spec whitelist, 16/16
specs with schemas and 10/16 without (9 sound) at 350,000 work (`v2/STAGE0_RESULTS.md:81-100`); my
runs confirm three of the six failures and show they persist at 900x-8000x budget.

My count is 18 kernel generators plus 5 curriculum ones (23); a count of 21 results from not
counting the fallback sibling and DIP repair as generators. v2 adds five more (section 10).

---

## 6. Reentrancy

### 6.1 What exists

* **Synthesis over code values.** `:code` is an object-language type with primitives
  `:code-kind`, `:code-child`, `:code-operator`, `:code-apply`, `:code-match`, `:code-bind`,
  `:code-subst`, `:code-total`, `:code-less`, `:code-eval` (`ast.lisp:118-146`). A frame whose
  target is code is an ordinary frame: `learn-knowledge-transformer` runs the ordinary
  `start-search` on one (`templates.lisp:598-617`); the constructor-AU decomposition splits a code
  target into hole slots (`proposals.lisp:487-558`); `induce-solvers-from-transformers` executes
  learned programs over the quoted bodies of library solvers (`templates.lisp:628-653`). VERIFIED.
* **Frames built from the search's own messages.** `message-frame` turns reader rows into an
  ordinary frame (`messages.lisp:60-81`); `experiments/yield-gate.lisp:204-214` runs
  `frame-conflict-p` on it and `233-262` runs an observation search over it to propose stopping
  rules. `make-search-trace-frame` (`consolidate.lisp:20-93`) builds a 6-feature frame from job
  traces and `condense-search-heuristic` (`95-131`) runs Stage A on it. VERIFIED.
* **Nested searches.** Host code calls a nested job synchronously in: Stage A in every node
  (`synthesize.lisp:398`); guard search (`decompose.lisp:155-157`, `231-233`); feature search
  (`proposals.lisp:319-321`); row keys (`proposals.lisp:684-687`); code-argument enumeration
  (`proposals.lisp:898-913`); multi-hole predicates (`proposals.lisp:1317-1321`); descriptor
  discovery (`descriptors.lisp:379`); relations (`relations.lisp:162`); Boolean separators, which
  fall back to a whole nested `start-heuristic-synthesis` (`consolidate.lisp:1364-1369`). VERIFIED.

### 6.2 What concretely stops full reentrancy

1. **Synthesis is not an operation of the VM.** No primitive poses a sub-problem; frames,
   rows, requirements-as-frames, languages, decompositions, nodes, jobs and ledgers are host
   structs with no object-language type (`synthesize.lisp:8-71`; primitive list `ast.lisp:118-146`).
   A learned program can transform code, but cannot build a frame, ask for a search, or read a
   result. VERIFIED.
2. **The operations the owner lists are host functions.** Pullback, lift, product slotting,
   fiber inference, anti-unification, conflict detection, folding, propagation, composition
   (`pull-through` / `compose-through`, `synthesize.lisp:290-320`) are Lisp functions called by the
   controller; a decomposition is data only in the sense of a decoder AST plus flags that select
   which host function handles it (`lift-p`, `slots`, `fiber-p`). v2's Stage 1 began to move
   pieces into the VM (`:code-anti-unify`, `:code-quote`, `:code-value`, `:tabulate`, `:evolve`,
   `:iota`, `:where` in `v2/ast.lisp`'s primitive list; typing at `v2/templates.lisp:241-269`). VERIFIED.
3. **Proposal generation is a host closure.** `:expand` is `(lambda (job node frame language
   h-model ledger) ...)` (`synthesize.lisp:169`, `1092-1094`); `combine-expanders` appends closures
   (`proposals.lisp:267-272`). The search cannot synthesise, rank, or switch off a generator.
4. **Recursion is implemented by mutating the global function table.** A recursive job binds
   its `self-name` to an oracle table and flips it to each candidate body during verification
   (`activate-job-oracle`, `activate-job-candidate-body`, `synthesize.lisp:73-112`;
   `set-function-active-implementation`, `knowledge.lisp:631-648`); every step function begins by
   re-asserting the binding (`539`, `1085`, `1251`, `1224`). Two jobs can interleave only with
   different names, and a nested job that defines a function bumps `*function-library-version*`
   (`knowledge.lisp:626`), which invalidates caches of the outer one.
5. **Other global state on the path:** `*knowledge-library*` and `*function-definitions*`
   (default propagator and template source, `synthesize.lisp:190`, `197-198`; `proposals.lisp:244`);
   `*registered-function-names*` and `*auto-retyped-functions*` (`proposals.lisp:19`, `28`;
   `templates.lisp:595`); `*next-call-id*` (`enumerate.lisp:245`); `*noted*` (`enumerate.lisp:221`);
   `*closures*` (`vm.lisp:424`); `*precomputed-program-bits*` (`synthesize.lisp:410`).
   `with-knowledge-library` exists to isolate a library (`knowledge.lisp:178`), and the bootstrap
   uses it, so this is manageable rather than fatal.
6. **Nested searches are not resumable and their budgets are literals.** `condense-heuristic`
   creates a job, runs it to its limit, and drops the handle (`condense.lisp:28-40`), although the
   underlying `heuristic-search` is resumable (`289-301`). The same holds for every nested
   observation search in 6.1. A nested search cannot be suspended, re-prioritised against its
   siblings, or given more work later; its budget comes from a constant, not from the parent's
   agenda.
7. **No shift of abstraction level in the tree.** A child problem is always "the same target
   through a decoder with one hole" (`decomposition`, `synthesize.lisp:8-17`). A node cannot pose
   a problem whose inputs are other nodes' results, whose target is a decomposition, a guard
   language or a policy, or whose rows are the search's own messages.
8. **Message rows are hand-typed.** Five readers with fixed integer / Boolean columns
   (`messages.lisp:88-128`); the lane-choice trace is explicitly excluded (`messages.lisp:8-9`).

---

## 7. Reflection

### 7.1 What the search records

| Record | Form | Where written |
|---|---|---|
| Leaf-job messages | `:cutoff` / `:bounded-exhaustion` / `:replay-complete` per resume; `:candidate`; `:counterexample` (verification jobs only, `:diagnostics t` at `synthesize.lisp:633`); `:observed-invariant` | `enumerate.lisp:331-343`, `386-395`, `413-414`, `464-468`, `778-779` |
| Job messages | `:prepared` (depth, inputs, constrained rows, conflict-p); `:stage-a` (work limit, spent, history of buckets and models with their work stamps); `:expanded` (proposal names, deferred names); `:child-candidate`; `:candidate`; `:rejected` (with the verification job's messages); `:conflict`; `:subproblem-reused`; `:cegar-refinement`; `:bounded-exhaustion`; final claim | `synthesize.lisp:114-131` and call sites `739`, `826`, `840`, `893`, `1076`, `1183`, `1239`, `1241`, `1275`, `1307`; `condense.lisp:35-36` |
| Lane trace | one plist per lane selection: turn, lane, work, best score, priority | `synthesize.lisp:1030-1038` |
| Ledgers | total + per-category counts, per job and per leaf job | `vm.lisp:42-54` |
| Provenance (debug mode only) | origin, depth, frame summary, Stage A program and score | `synthesize.lisp:763-785`; `*synthesis-debug-mode*` defaults to nil (`5`) |

### 7.2 Who reads it

| Reader | Reads | Effect | Called from |
|---|---|---|---|
| `message-rows` / `message-frame` | job messages through 5 readers | rows and frames | `experiments/yield-gate.lisp`, `tests/messages.lisp` only (VERIFIED by grep) |
| `job-winning-node`, `remember-successful-decompositions` | the `:candidate` message of the best result | finds the winning path; registers decoder templates | `consolidate.lisp:361`, `359-360`; templates only with `:register-templates-p t` |
| `make-search-trace-frame` + `condense-search-heuristic` | trace, `:candidate` messages, node Stage A models | a `:heuristic` library entry = priority predictor | `consolidate-knowledge-library` (`consolidate.lisp:1039-1048`) |
| `consolidate-policy-descriptors` | winning and failed nodes | moves descriptor clause weights by +/-1 | same (`consolidate.lisp:382-412`, `1040`) |
| `amortize-library-entries` | jobs | archives entries that cost more than they save | same (`consolidate.lisp:1038`) |
| `explain-synthesis-node` / `-job` / `explain-knowledge-library` | everything | human-readable plists | no kernel caller (`explain.lisp`) |
| `synthesis-episode-returns` | trace | returns per decision | no kernel caller; one test (`tests/refactor.lisp:481`) (VERIFIED by grep) |

`consolidate-knowledge-library` itself is called from no kernel, bootstrap or milestone file
(VERIFIED by grep; it is called from tests). `synthesize-spec-entry`, the bootstrap's driver,
calls only `commit-synthesis-job` (`consolidate.lisp:1239`), and starts its job without naming a
library, so no predictor is read (`synthesize.lisp:182-185` reads one only "from a library that is
named").

### 7.3 Is any search decision influenced by recorded search history?

* **Across jobs, in principle: one decision.** A learned predictor adds a delta clamped to
  [-24, +48] bits to node priority (`synthesize.lisp:503-507`). Its inputs are six integers:
  program bits, residual bits, depth, constrained rows, policy score, coupled count
  (`440-445`). Also descriptor weights (via `score-entry-by-descriptors`), remembered decoder
  templates, nogood schemas and DIP features change which proposals appear and in what order.
  On the production (bootstrap) path only nogood schemas and DIP features are written, and the
  failing runs I made produced none (`nogoods=0`).
* **Within a job: no decision reads messages or the trace.** What does feed back within a job
  is state, not record: the nogood list (prunes sibling proposals), the scope cache (reuse),
  product-join pools, CEGAR row promotion, and the rejection cache when laws are supplied.
* **The demonstrated reflective loop is an offline experiment.** `experiments/yield-gate.lisp`
  shows the kernel's own conflict check and observation search applied to rows of its own
  Stage A history, and proposes stopping rules; nothing installs such a rule, and the file
  itself says a rule that passes "is a suggestion" (`experiments/yield-gate.lisp:8-10`).

So the owner's description holds: the "do not repeat this calculation" guards and the search
strategy are hard-coded (section 4); the search's operation graph is partly recorded, readable
as frames, and unused.

---

## 8. Nogoods, CEGAR, DIP repair

**What is learned (nogoods).** When preparing a child finds an `:incompatible-rows` conflict
(two child rows with the same known inputs and incompatible requirements), for a pure
projection or a lifted proposal with >= 2 conflicting keys (`synthesize.lisp:598-606`),
`build-nogood-clause` (`nogoods.lisp:123-173`) records: parent node id, kind, the row keys, the
shared input tuple, the proposal's bindings and decoder, a `clause-expr` (conjunction of
`(= binding-expression 'value)` over the child's inputs), a `parent-clause-expr`, and a flag
that the parent rows themselves are incompatible under this decoder. All further colliding
buckets of the same frame get a clause too (`175-200`). In plain words the content is always
the same: *this choice of context merges rows that need different outputs* (a functional
dependency violation).

**Generalisation (UIP).** For lifted proposals, the clause expressions of one parent, kind and
child type are anti-unified into a pattern with holes (`nogoods.lisp:218-252`;
`synthesize.lisp:607-610`).

**Reuse within the job.** Before a sibling's frame is built, `check-parent-nogoods`
(`nogoods.lisp:386-432`) refutes it if (1) it is a projection whose bindings agree on the rows
of a recorded conflict, or the parent rows were incompatible and the proposal's parent
expressions agree on them; (2) it lifts through the same decoder and the clause matches.

**Generality.** Clauses carry `parent-id` and row keys, so they are specific to a node of one
job. Only UIP patterns leave the job, as `:nogood-schema` entries
(`consolidate.lisp:297-309`), and `check-library-nogood-schemas` applies them only to a decoder
that maps a one-input code pointwise over the parent's single list input, with the same
normalised decoder and child type (`nogoods.lisp:309-346`). The comment explains why it is that
narrow: for any other decoder the check "would refute lifts that hold" (`314-317`). So the
persisted, reusable knowledge is close to one fact about `map`.

**Persistence.** `:nogood-schema` and `:dip-feature` are library kinds and are committed by
`commit-synthesis-job` by default (`consolidate.lisp:253-254`, `297-333`).

**CEGAR.** A lifted frame keeps 16 active rows and reserves the rest (`frame.lisp:1016`,
`1036-1075`). When root verification rejects a candidate,
`refine-lifted-node-from-counterexample` (`synthesize.lisp:1189-1217`) walks up from the node,
recomposes the candidate to each ancestor that has reserve rows or is lifted, finds a reserve
row it refutes (unfolding more fibers on demand, `1155-1172`), appends that row to the frame,
and restarts that node (`1124-1150`): new search from size 1, descendants closed, followers
detached, scope cache cleared. What is learned is one more example. It is not generalised and
not persisted.

**DIP repair.** On a conflict, up to one repaired sibling is proposed whose bindings gain a
context expression that takes different values on every conflicting row pair and is defined on
every constrained row (`nogoods.lisp:489-538`, `540-580`). Candidates are library
`:dip-feature`s first, else variables and one-step applications from the parent grammar. Used
separators are committed as `:dip-feature` entries (`consolidate.lisp:310-333`) and tried first
in later jobs.

Assessment: the CDCL vocabulary (UIP, DIP) overstates what is there. There is no implication
graph, no clause database queried by unit propagation, and no backjumping; there is a
functional-consistency check, a least-general-generalisation of its failures, and a one-step
feature search to repair it. The idea that survives is sound and small: *a failed pullback
names the rows it wrongly merged, and that set is reusable evidence*.

---

## 9. Clean versus accreted

LOC are source lines of the cited spans (from a top-level-form listing of each file).

### 9.1 Small, principled, worth importing

| Component | Where | LOC | Why |
|---|---|---|---|
| Bit-exact, size-ordered, typed enumerator with a one-step cursor | `enumerate.lisp:59-214` | 148 | Exact MDL order, no eager products, resumable. Needs behaviour dedupe added (v2 shows ~30 lines suffice, `v2/enumerate.lisp:373-382`, `405-425`) and a retention policy. |
| Resumable row-job stepping with absolute cumulative limits | `enumerate.lisp:231-343` | ~90 | Slice-invariant: the same work however the budget is cut (`enumerate.lisp:548-551`; checked by `tests/messages.lisp:94` and `experiments/ledger-fingerprint.lisp`). |
| Ledger, `pay-debt`, `with-work-limit`, staged work | `vm.lisp:10-54`; `synthesize.lisp:45-59` | ~60 | Exact per-category accounting; "compute privately, publish when paid" gives deterministic preemption. |
| Exact search job (accept / reject / hard edges) | `enumerate.lisp:345-561` | ~215 | Clean apart from the frame-row assumptions; the law-normal-form rejection cache (`472-498`) is a good idea that v1 never wires in. |
| Observation search and behaviour buckets | `enumerate.lisp:698-877` less `607-687` | ~215 | The right primitive for features, guards, laws and reflection; one behaviour table should serve enumeration, Stage A and Stage B. |
| Scope-signature subproblem sharing | `synthesize.lisp:233-276`, `831-845` | 57 | Canonical, order-independent identity of a subproblem; the nearest v1 comes to hash-consing the problem graph. |
| Lane scheduler with reserves | `synthesize.lisp:906-1040` | ~125 | The 3:1 best-price / rotation split and the root reserve keep unpriced alternatives alive. The formula is hard-coded; the shape is reusable. |
| Controller loop | `synthesize.lisp:1219-1310` | ~90 | Anytime: best verified candidate available after every call (`1281-1282`). |
| Root verification of every composed candidate | `synthesize.lisp:621-634`, `1219-1248` | ~45 | No local acceptance is trusted; this is what makes the aggressive heuristics safe. |
| Message readers and `message-frame` | `messages.lisp` | 128 | The only place where the search's record becomes an ordinary task. Small and correct; needs the trace and a richer schema. |
| Stage A residual-priced condensation | `condense.lisp` | 301 | A coherent idea (price a partial model by program + corrections). It is entangled with frame rows, witnesses and the empty-sequence special case (`64-79`); import the idea, not the file. |

Subtotal: roughly 1,450 LOC of the 7,101 in scope.

### 9.2 Reasonable ideas tied to the frame representation (re-derive rather than import)

| Component | Where | LOC | Note |
|---|---|---|---|
| Node preparation pipeline | `synthesize.lisp:510-619`, `847-904` | ~230 | The order pull back, fold, propagate, price, record conflicts is sensible; the code is a single 86-line function dispatching on proposal flags. |
| Product join / coupled slots | `synthesize.lisp:278-306`, `636-754` | ~150 | An AND-node with a bounded join. The pools and caps exist because slots are searched independently and re-coupled after the fact. |
| CEGAR row promotion | `synthesize.lisp:1103-1217` | ~110 | Needed only because lifted frames are windowed to 16 rows. |
| Nogood clause construction and reuse | `nogoods.lisp:1-432` | ~430 | 430 lines to express "this projection merges rows with different outputs" for three proposal shapes. In a dependency-graph representation this is one check. |
| DIP repair | `nogoods.lisp:434-580` | ~147 | A one-step feature search; subsumed by a general "find a separating feature" operation. |
| Structural products and constructor anti-unification | `proposals.lisp:382-621` | ~240 | The most "topological" generator; worth understanding closely before a rewrite. |
| Type-template inference / instantiation | `templates.lisp:1-596` | ~595 | Polymorphism bolted on after the fact by re-unifying primitive signatures; 227 lines in one function (`68-294`). A rewrite with polymorphic types from the start removes it. |

### 9.3 Patches around the representation or around specific tasks

| Component | Where | LOC | Note |
|---|---|---|---|
| Self-recursion by global rebinding, "must call self" rule | `synthesize.lisp:73-112`, `333-366` | ~70 | Recursion handled outside the search by mutating the function table. |
| Inductive sequence lift, lockstep lift | `decompose.lisp:320-513` | ~194 | List recursion written into the kernel. |
| Curriculum recursion schemas | `bootstrap/recursion-schemas.lisp` | 355 | One skeleton per battery function, by the file's own statement. |
| Guard machinery | `decompose.lisp:84-318` | ~235 | Hand-built guard grammar, feature-pair comparisons, a 71-line guard chooser. |
| `heuristic-decompositions` | `decompose.lisp:515-666` | 152 | One function with ~20 special-case conditions on recursion, empty sequences and tuples. |
| Library decompositions and argument guessing | `proposals.lisp:6-272` | ~267 | The lift mechanism is general; the argument menu, empty-row test and retyping are list-specific. |
| Partial library applications | `proposals.lisp:881-953` | ~73 | A capped Cartesian product, fallback-only. |
| Decoder templates incl. the two-hole comprehension | `proposals.lisp:955-1398` | ~444 | 135 lines (`1195-1329`) for one filter-map shape. |
| Row-order induction | `proposals.lisp:623-818` | ~196 | No kernel caller. |
| Stage A budget rules, priority formula, predictor shim | `synthesize.lisp:373-508` | ~135 | Hand-tuned constants (x2, squared arity, 16 bits per coupling, policy/2, clamp). |
| `explain.lisp` | whole file | 145 | Debug printing; harmless, not kernel. |
| `benchmark.lisp`, `experiments/*` | - | 610 | Tooling. `ledger-fingerprint.lisp` (59) is a good regression idea; `yield-gate.lisp` (265) is the one worked example of reflection. |

Subtotals: 9.2 ~1,900 LOC; 9.3 ~2,900 LOC (including 355 curriculum and 610 tooling).

### 9.4 Defects worth knowing before importing anything

* Trace leak (finding 7); unbounded syntax retention (2.5).
* Stage A and Stage B duplicate enumeration and evaluation (1.4).
* Law-normal-form pruning is never wired into the tree in v1 (3.2).
* Acceptance on 2 resolved rows produces systematic false positives in recursive jobs (2.2).
* In v1, `row-satisfaction` tests `(typep (evaluation-error run) 'unresolved-evaluation)` on a
  value that `advance-evaluation` has already turned into a string (`synthesize.lisp:1108`;
  `vm.lisp:384-385`), so the branch can never be true; v2 Stage 0 fixes it
  (`v2/synthesize.lisp:1139-1140`). VERIFIED by reading both.

---

## 10. What v2 changed in these files

Attribution by commit: `397499a` "adding pass 0 for v2" = Stage 0; `a4e19fa` "WIP: stage 1 in
progress" = Stage 1 (VERIFIED with `git log` / `git show`). Unchanged between root and v2:
`messages.lisp`, `explain.lisp`, `benchmark.lisp`, `experiments/ledger-fingerprint.lisp`,
`probes.lisp`, `yield-gate.lisp`, `bootstrap/recursion-schemas.lisp`. Added:
`v2/experiments/stage0-audit.lisp` (275 lines), `v2/tests/stage0.lisp` (222 lines, 6 tests).

### 10.1 Stage 0 (soundness and sandboxing)

| File | Change | Lines (v2) |
|---|---|---|
| `enumerate.lisp` | `*default-row-budget*` 100,000 for enumerated candidates and observations; `:cutoff` status; rewrite library refreshed at `:rewrite-start` | `489-490`, `500-507`, `640`, `926-931`, `1049-1086`, `1147-1151` |
| `synthesize.lisp` | new `laws` slot; `node-rewrite-laws` passes certified laws to node searches (so the normal-form rejection cache finally runs inside the tree); `pull-through` errors become a `:binding-error` conflict; `row-satisfaction` treats `:unresolved` as unknown | `68`, `191-199`, `568-579`, `864-875`, `905-908`, `1136-1146`, `1159-1167` |
| `nogoods.lisp` | lifted occurrence indices must be integers before a parent incompatibility is asserted | `143-144` |
| `templates.lisp` | `default-law-samples` so retyped laws are tested when no samples are given | `565-596`, `618-628` |

Effect on behaviour: the plan-8 probe figures are "bit-for-bit identical" (doc-claimed,
`v2/STAGE0_RESULTS.md:14`). New silent cap: a candidate that needs more than 100,000 VM work on
one row is now rejected in every enumerating search (`v2/enumerate.lisp:489`), which matters for
exactly the expensive programs (correlations, long recursions) the owner wants.

### 10.2 Stage 1, work in progress

| File | Change | Lines (v2) | Comment |
|---|---|---|---|
| `enumerate.lisp` (+296) | enumerator options `effective-horizon-p`, `prune-behaviors-p`, shared `behavior-table` and `column-cache`; `compute-expression-column` (bottom-up evaluation of only the root operator over cached child columns); `column-pure-behavior-key`; duplicate behaviours dropped at construction; columnar settlement phases | `59-79`, `282-382`, `405-437`, `658-716`, `728-731`, `1094-1131` | **Opt-in and unused**: no file other than `v2/enumerate.lisp` and `v2/condense.lisp` mentions these keywords, and no test covers them (VERIFIED by grep). |
| `condense.lisp` (+23) | passes the same options through `condense-heuristic` / `start-heuristic-search` | `24-37`, `88-101` | plumbing only; `node-stage-a-model` does not pass them |
| `decompose.lisp` (+76) | `definedness-guard-for-expr`: derive a totality guard for a partial program (`/`, `mod`, `tail`, `at`) and use it as the conditional's guard when it matches the frame | `515-573`, `695-706` | a principled addition (guards from partiality) |
| `proposals.lisp` (+201) | `container-cover-decompositions`: `:tabulate-cover`, `:index-map`, `:index-filter`, `:gather-cover`, `:tabulate-int`, with policy scores -14, +2 / -12, -13, -11, -14 | `243`, `248-439` | **new hard-coded generators keyed on function names** `:positions`, `:map`, `:filter` and primitives `:tabulate`, `:gather`, with negative scores that put them ahead of everything else, and a length-offset detector over `d in {0,1,2,3}` (`248-258`). The stated purpose is the six bootstrap timeouts (doc-claimed, `v2/STAGE0_RESULTS.md:127`). |
| `templates.lisp` (+29) | typing rules for `:tabulate`, `:evolve`, `:code-quote`, `:code-value`, `:code-anti-unify` | `241-269` | follows the new primitives in `v2/ast.lisp` |

Measured, v2 enumerator options switched on by hand (EXP-D, VERIFIED):

| Case | Plain | `prune-behaviors-p` | + `columnar-p` |
|---|---|---|---|
| Observation, `{+,*}`, 26 body bits | 141,501 work | 12,555 (11x) | 5,360 (26x) |
| Observation, 30 body bits | 1,412,531 | 45,249 (31x) | 18,244 (77x) |
| Exact search, 39-bit target, total | 8,904,757 | 98,107 (91x) | 72,786 (122x) |
| Same, work to first solution | 2,136,907 | 49,880 (43x) | 30,841 (69x) |
| Behaviour sets equal to plain | - | yes | yes |

So v2 holds the single most valuable search improvement in the repository, unconnected.
Caveat (INFERRED): the behaviour key treats two expressions that are both `:unresolved` on a
row as equal there (`v2/enumerate.lisp:373-382`), which in recursive jobs with oracle tables
could merge programs that differ off the table; and a shared table must be rebuilt when CEGAR
adds a row.

Direction of travel: Stage 0 fixed real defects. Stage 1 split in two: an engine improvement
left dormant, and a new batch of task-shaped proposal generators. The second is the pattern
the owner objects to.

---

## 11. Implications I am confident of, and what I could not determine

### Confident

1. A rewrite should treat "hours of search" as roughly 1e10-1e11 work units and design the
   records (trace, retained syntax, node list) for that scale; v1's records are sized for 1e5.
2. More budget must be able to buy more *structure*, not only more leaves. In v1 the set of
   decoders is closed after one expansion per node, Stage A budgets are constants, and bounds
   are terminal. An anytime design needs resumable proposal generation and re-openable nodes;
   the leaf jobs already have exactly this property (`resume-row-job` accepts a larger bound and
   limit, `enumerate.lisp:315-321`).
3. One behaviour table should be the shared memory of enumeration, Stage A, guard search and
   feature search. v1 computes it four times in different guises (observation buckets,
   heuristic buckets, guard predicates, dependency features) and v2's column cache shows the
   unification is mechanical.
4. The recursion skeletons are the clearest instance of the owner's "lift must be a
   synthesizer primitive". Each of the five curriculum schemas, and the kernel's own, is the
   same act (bind the recursive call's value as a new input of the child) with a different
   hand-chosen argument tuple. The search cannot choose that tuple because the call is built
   by host code (`typed-recursive-call`, `decompose.lisp:341-353`).
5. Reflection needs the trace as first-class rows (it is excluded today) and a consumer inside
   the loop. The existing predictor is a six-integer regression with a clamp; it is a proof of
   plumbing, not a policy language.
6. Root verification of every composed candidate, exact ledgers and slice-invariant stepping
   are the properties that made aggressive heuristics safe and experiments reproducible. Keep
   them whatever the representation becomes.

### Not determined

* Whether the dormant v2 pruning stays sound inside the full tree (recursive jobs, CEGAR,
  shared tables). I tested it only on closed arithmetic frames.
* Whether v2's container-cover generators actually solve the six timeouts; I did not run v2's
  synthesis (the `empirical` auditor's remit).
* How the tree behaves when it is large. Every tree I produced had 2-3 nodes, so the quadratic
  agenda cost and the behaviour of the 3:1 reserve under real contention are INFERRED from code.
* The exact share of the 0.34 s bootstrap spent in search versus consolidation; that figure is
  doc-claimed and I did not re-run the bootstrap.
* Whether a larger Stage A budget changes which guard is found on the specs that do succeed
  (it did not help the three failures I ran).
* Throughput and tariff fidelity on VM-heavy rows (long lists, nested recursion); my rate of
  6-9 M work/s is for short rows.

---

## Appendix: experiments

All in `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/search-engine/`.
Each loads the kernel sources read-only and writes only into that directory.

| Id | Script / output | What it measures |
|---|---|---|
| EXP-A | `exp-a.lisp`, `run-a.sh` -> `exp-a.out` | leaf prices; expressions per body-bit size for four grammars; syntactic versus behavioural counts on a 6-row frame (root kernel) |
| EXP-B | `exp-b.lisp`, `run-b.sh` -> `exp-b-*.out` | `map-adjacent`, `scan`, `positions` through `start-recursive-synthesis` with the bootstrap's own rows and whitelists, with and without the curriculum schemas, at 350,000 to 2.8e9 work; node dump, ledger, heap, throughput (root kernel) |
| EXP-C | `exp-c.lisp`, `run-c.sh` -> `exp-c.out` | candidates priced by Stage A at budgets 2,000 to 1e7; exhaustion point of the default bound (root kernel) |
| EXP-D | `exp-d.lisp`, `run-d.sh` -> `exp-d.out` | v2's `prune-behaviors-p` and `columnar-p` switched on by hand: work, retained syntax, behaviour-set equality, exact search for a 39-bit target (v2 kernel) |

EXP-B run index (`exp-b-<tag>.out`): `ma-schemas`, `ma-noschemas-350k`, `ma-noschemas-350M`,
`ma-noschemas-350M-q32` (heap at quantum 32), `ma-noschemas-exhaust` (quantum 1e6, run to the
end), `ma-nodepth`, `ma-allknobs`, `scan-350k`, `scan-350M`, `pos-350M`.
