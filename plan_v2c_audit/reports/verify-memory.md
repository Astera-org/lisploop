# verify-memory: the review's memory rule (§2.5.3, Appendix B.2 item 1)

Work directory: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/q3-memory/` (abbreviated `W/` below). Python 3.14, standard library only, fixed seeds. Nothing under `/home/tlh24/lisploop` was touched.

Terms used here. The **dedupe table** is the set of columns already seen (the review's `seen`). The **bank** is the per-size list of classes that larger terms are built from. **(a)** is plain search. **(b)** inserts into the dedupe table and then tests, so only the bank is pruned. **(c)** tests first and inserts only what is kept, which is the review's rule. The test is size + h(label) ≤ N, where h is the backward bound read off the label tables. **R** is deepening the size bound N with a restart on every pass. **K** is deepening with the bank kept across bounds; a class that is cut then leaves a *record* (its hash, its size, its budget size + h, and the candidate that produced it), and the candidate is evaluated again when the bound reaches that budget.

## 1. Bottom line

Testing before inserting is correct, and it is what the earlier reproduction's code already did. The plan's figures (8.5–26× on polynomials; 2.3–2.8×, or 7–9× with look-ahead, on the 61-operator library) already count the dedupe table, so the plan needs no correction for that. The review's "apparent 1.5×" corrects the reviewer's own first design. When the answer's size is unknown, the rule holds unchanged if every deepening pass restarts: peak memory is the last pass, at a cost of 1.0–2.1× more evaluations. Its gain in bytes is large only where the labels are exact and the bound h is deep: 8.5–29× on ring polynomials. On the library and in the lifted space the labels cut only the top stored size, and a rule that needs no labels gets most of that saving. The lifted-space "1.0×" holds only because of how EXP A2 was built.

## 2. Verdict table

| Claim | Verdict | Mine vs review |
|:--|:--|:--|
| Testing before inserting changes nothing that is found (the proof) | **REPRODUCED within one pass; FAILS across passes if the bank is kept** | The bank was identical under (b) and (c) on 206+106 polynomial targets, 16 unsound div/mod targets and 60 library tasks × 2 table sizes; 0 cases of a class cut at one test and kept at a later one. With the bank kept across bounds (K), 532 records (in 22 of 206 targets) had to be replaced by a smaller derivation found in a later pass. A cut set that stores no sizes put a class at the wrong size in 1 target per seed. |
| `len(seen) == len(bank)` | **TRUE BY CONSTRUCTION** | 206/206 |
| 9.4×/22.6×/22.9× true RAM (A4, A8, A12), 0 misses | **REPRODUCED, with the size given** | The reviewer's script prints exactly 9.4/22.6/22.9. Mine: 9.6×/26.4×/14.3× in entries, 11.8×/28.9×/14.8× in Python bytes; 8.5–26.4× on all six targets; 0 lost |
| …and the same with the size unknown | **REPRODUCED under R** | Same peak (the last pass is the peak on 206/206); evaluations 1.0–1.7× the last pass on the six targets, up to 2.1× on random targets |
| Pruning the bank only is an "apparent 1.5×" | **REPRODUCED; not the plan's number** | 1.2–2.6× entries, 1.5–3.4× SBCL bytes. The earlier code already tested first (`q3lib.py` 191, 206–212, 280–283, 323–325; `q2search.py` 470–478). Its counts equal mine on 6/6 targets and 60/60 tasks |
| 2.1× true RAM on the 61-operator library | **PARTLY** | 2.39× entries / 1.54× bytes without look-ahead; 7.10× / 4.34× with it. The reviewer's figure was taken with a look-ahead, on 41 unary operators and 8 tasks, with the size given |
| Undirected search: 1.0× | **TRUE BY CONSTRUCTION** | With no target, h ≡ 0 and the test never fails. Coarser dedupe keys: Table 3 |
| Lifted space: 1.0× RAM whenever `at` is at or inside the term | **TRUE BY CONSTRUCTION in EXP A2; NOT REPRODUCED when tested** | EXP A2 filters only the last size, which is never stored (lines 280, 294–306, 318), and gives `at` no table (237–255, 274–281). Filtering every size, with tables for every operator including `at`: 1.4–2.4× where `at` is outermost, 1.4–5.7× elsewhere. Controls with no `at` give the same numbers, so `at` is not the limit; the shallow bound is. 0 answers lost in 90 runs |
| Arithmetic-outermost lifts: 5.3–7.6× fewer evaluations | **PARTLY** | 2.2–3.0× with last-size filtering; 6.1–11.1× filtering every size with a sequence-keyed `at` table; `reverse`/`rotate-left` 1.0–1.1× (last size) and 1.1–1.5× (every size) |

**Table 1. Polynomials, G1, 32 random rows, residues mod 2 (12 rows), 3 (4 rows) and 5 (3 rows).** Entries are dedupe table / bank. Bytes use the SBCL figures defined in §3. Under R the peak equals the size-given column.

| Target | Size | (a) plain | (b) | (c) | (b) gain, entries / bytes | (c) gain (entries = SBCL bytes) | R: evals × one pass | K: kept + records |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| A2 `(x+x)*(y+1)` | 7 | 127 | 48 / 8 | 8 | 2.6× / 3.4× | 15.9× | 1.12 | 8 + 40 |
| A3 `x*y+x-y` | 7 | 127 | 70 / 15 | 15 | 1.8× / 2.3× | 8.5× | 1.00 | 15 + 55 |
| A4 `(x+y)*(x-y)+1` | 9 | 595 | 425 / 62 | 62 | 1.4× / 1.8× | 9.6× | 1.73 | 62 + 363 |
| A8 `(x+y)^2-xy+1` | 11 | 3,147 | 1,953 / 119 | 119 | 1.6× / 2.1× | 26.4× | 1.40 | 119 + 1,834 |
| A11 `(xy+x+1)(y-x)` | 11 | 3,147 | 2,631 / 333 | 333 | 1.2× / 1.5× | 9.5× | 1.53 | 333 + 2,298 |
| A12 `2(x^2+y^2)-xy` | 13 | 17,609 | 13,569 / 1,229 | 1,229 | 1.3× / 1.7× | 14.3× | 1.66 | 1,229 + 12,340 |

Plain is counted below the answer's size, as if the size were known. If plain stored each size as it went, it would hold 1.4–4.4× more at the hit (A12: 77,032), and 9× more on the library. So the gains quoted here are conservative.

**Table 2. Lifted positions, gains over plain (range over 3 row seeds; 22–28 rows; answer sizes 6–8).** "Stored" counts classes below the answer's size. LL filters the last size only; the other three columns filter every size.

| Task | Root | LL evals / stored | `at` by index: evals / stored | `at` by sequence | + guard word | Top as hashes |
|:--|:--|:--|:--|:--|:--|--:|
| `xs[i]+xs[i+1]` | + | 2.2–2.3 / 1.00 | 2.3–2.6 / 2.0–2.2 | 6.1–7.3 / 5.2–5.7 | 6.3–7.5 / 5.2–5.7 | 5.2–5.7 |
| `xs[i+1]-xs[i]` | − | 3.0 / 1.00 | 3.3–3.4 / 2.0–2.2 | 9.5–10.8 / 5.2–5.7 | 9.8–11.1 / 5.2–5.7 | 5.2–5.7 |
| `xs[len-1-i]` | at | 1.0 / 1.00 | 1.1 / 1.38–1.41 | 1.1 / 1.38–1.41 | 1.3 / 2.05–2.11 | 2.6–2.7 |
| `xs[(i+k) mod len]` | at | 1.0–1.1 / 1.00 | 1.2 / 1.40–1.43 | 1.2 / 1.40–1.43 | 1.4–1.5 / 2.27–2.36 | 3.7–3.8 |
| `xs[2i mod len]` | at | 1.0 / 1.00 | 1.1–1.2 / 1.38–1.41 | 1.1–1.2 / 1.38–1.41 | 1.3–1.4 / 2.05–2.11 | 2.6–2.7 |
| `xs[i]*(i+1)` | * | 2.9–3.0 / 1.00 | 2.8–3.0 / 1.38–1.41 | 6.0–8.6 / 2.57–2.68 | 6.4–11.0 / 2.57–2.68 | 2.6–2.7 |
| `xs[i]-xs[len-1]` | − | 2.3 / 1.00 | 2.6 / 1.99–2.12 | 6.4–8.2 / 5.1–5.6 | 6.5–8.5 / 5.1–5.6 | 5.1–5.6 |
| `xs[len-1-i]+i` | + | 1.2 / 1.00 | 1.3 / 1.67–1.69 | 3.3–3.4 / 2.71–2.88 | 3.5–3.8 / 2.71–2.88 | 2.7–2.9 |
| control `(i+1)(len-i)` | * | 2.7 / 1.00 | 3.0–3.1 / 1.99–2.12 | 6.9–8.6 / 5.1–5.6 | 7.3–10.1 / 5.1–5.6 | 5.1–5.6 |
| control `i*i-len*len` | − | 2.7 / 1.00 | 2.2 / 1.99–2.12 | 6.5–9.8 / 5.1–5.6 | 6.6–10.1 / 5.1–5.6 | 5.1–5.6 |

With `at` keyed on the index alone, its table is uninformative: under parity, mod 3 and sign, every index label maps to every output label. Keyed on the sequence's label, it rules out "the answer is `at(xs, …)`" on rows where the target's label does not occur in the sequence. That is how a sequence-level word lets information through `at`: it bounds the element's label rather than carrying the index's label across.

## 3. What changes for the plan

**The rule, as the kernel should implement it when the answer's size is unknown.**

1. Deepen the bound N from the tables' lower bound N_min (the forward bound g of the target's label) and restart on every pass.
2. Within a pass, a class of size s enters the dedupe table only if s + h(label) ≤ N.
3. Where the labels commute with the operators (residues on `+ − * neg`), predict the label before evaluating. The bank is the same, and evaluations fall a further 12–33× (A2 133→10, A12 236,398→8,131 in one pass).
4. Peak memory is the last pass's bank. Each pass's bank contains the previous one (checked on every pass of A8 and A12), so restarting costs evaluations, not memory: 1.0× at sizes up to 4, 1.19× at 7, 1.49× at 9 and 2.08× at 10 (geometric means), and 1.07× on the library.
5. Do not keep a cut set across bounds without sizes. Kept with sizes (K), records outnumber kept classes 1.5–15×, more at larger sizes (15× on A8). The byte gain on the six targets then falls to 3.9–7.9×, against 8.5–26× under R, and K saves only 1.0–1.5× in evaluations relative to R.

**A pruned bank depends on the target and the bound,** so it is scratch memory for one search. It cannot also be the persistent store of classes in §5. That follows from how the bank is defined; I did not test it.

**Gains in bytes.** "SBCL" means my own measurement of the prototype's structures (`m2_bytes.log`): 448.7 B per stored class (the prototype reports 452), 331.7 B per column held only in the dedupe table, 27.5 B per hash, and 91.7 B per K record. Residues do not shrink a class: each kept class still holds its full 32-row column. The gain comes entirely from storing fewer classes, so §8.4's "storing classes by their residues" should be reworded.

| Kind of problem | (b) bank only | (c) test first | Label-free alternative |
|:--|:--|:--|:--|
| Ring polynomials, exact residues | 1.2–3.4× | 8.5–26× SBCL, 8.8–29× Python; random targets of size ≥ 7: 9.7× [3.5–36], rising from 4× at size 3 to 25× at size 10 | top stored size as hashes: 1.12–1.16× |
| 61-operator library, sampled tables | 0.87–1.6× (**worse than plain** without the pre-evaluation filter) | 1.54×; 4.34× with look-ahead | top stored size as hashes: 5.8× in bytes (17.9× fewer full classes); labels then add 1.3–2.5× |
| Lifted positions | — | In entries: 1.4× where `at` is outermost (2.1–2.4× with the guard word); elsewhere 1.4–2.2× with an index-keyed `at` table and 2.6–5.7× with a sequence-keyed one; controls with no `at`: 2.0–2.1× and 5.1–5.6× | top as hashes: 2.6–5.7× |
| Undirected / law search | 1.0× | 1.0× | none found (Table 3) |

**Why the table looks like this.** The label test cuts below the top stored size only where h is deep. On polynomials, A12 keeps [363, 34, 604, 4, 97, 0] classes at sizes 7–12, against plain's [363, 105, 2,118, 434, 12,613, 1,849]. On the library and in all 90 lifted runs, nothing below the top stored size N−1 was cut. Classes of size N−1 feed only unary operators at size N. They can therefore be held as hashes, with the unary operators applied when each class is created, and this needs no labels. On the library, 94% of plain's stored classes are at size N−1.

**On the library the byte gain is smaller than the entry gain** because each kept class also stores its labels: 911 B per class against 666 B for a plain list class. Recomputing labels from the column would close most of that gap.

**Projection to the §8.4 wall (arithmetic, not measured).** Classes grow ×3.0 per size on G1, so a 10–25× cut in stored classes moves the 24 GB wall by about 2–3 sizes. That holds for directed ring searches only.

## 4. Supplied by hand

- **The reviewer.** The answer's size, as `max_ops` per target (`verify_ram_and_nmi.py` 116–123; `exp_devils_advocate.py` 185–188, 347–350). The 12 rows and the row subsets for each prime. In PART 2, a hard-coded word list labelled as the output of the "pairwise NMI < 0.65" selection (line 237); probes built to match those words (sorted, absolute, doubled, 2x+1, constant; lines 131–136); and a search over the 41 unary list operators only (`r0_count.log`). In EXP A2, no table for `at`, the filter applied on 6 rows at the last size only, and a 1.0× that the set-up guarantees.
- **Mine.**
  - The six library quotients and the residue rows come from the earlier reproduction.
  - In the lifted space I chose the integer quotients, the definition of a sequence's label (the set of labels its elements take) and the guard word `0 ≤ v < len`. The plan says a kernel would get that guard from the VM's faults; that is a proposal, not measured.
  - The task list.
  - SBCL bytes come from a microbenchmark of the prototype's structures, not from a real run.
  - The hash-top figures are computed from class counts. No search was run with that rule.

## 5. Commands (run in `W/`)

| Table / number | Command → log | Time |
|:--|:--|--:|
| Reviewer, unmodified | `bash r0_run_reviewer.sh` → `r0_expA.log`, `r0_verify_ram.log`; `python3 r0_count.py` → `r0_count.log` | 3 s |
| SBCL bytes per entry | `sbcl --script m2_bytes.lisp` → `m2_bytes.log` | 4 s |
| Polynomials: (a)–(c), R, K, 200 random targets, proof checks | `python3 m1_poly.py` → `m1_poly.log` (its div/mod block is uninformative; see the next row); `--seed 1 --nrand 100 --ng2 0 --procs 6` → `m1_poly_seed1.log` | 209 s, 249 s |
| Unsound labels (div/mod) | `python3 m1_g2.py` → `m1_g2.log` (13 of 16 lost under both (b) and (c); banks identical) | 55 s |
| Bank growth per bound | `python3 m1_passes.py` → `m1_passes.log` | 10 s |
| Library, 60 tasks | `python3 m3_lib61.py --procs 10` → `m3_lib61.log`, `.json`; then `m3_extra.py`, `m3_bytes_detail.py`, `m3_hashtop.py` → logs of the same names | 229 + 56 + 30 s |
| Lifted, 10 tasks × 3 variants × 3 seeds | `bash m4_run.sh` → `m4_lifted_seed{1,2,3}.log` | 20 s |
| Undirected | `python3 m5_undirected.py [--seed 1]` → `m5_undirected[_seed1].log` | 12 s |

**Table 3 (undirected, G1, every class up to size 11).** True laws are collisions of identical columns. False laws are collisions of labels whose columns differ.

| Dedupe key | Classes kept (2 seeds) | Gain | True laws kept | False laws |
|:--|--:|--:|--:|--:|
| Column (plain) | 15,760 | 1.0× | 100% | 0 |
| First 8 of 32 rows | 15,760 | 1.0× | 100% | 0 |
| Parity, mod 3, sign on 32 rows | 13,971 / 13,800 | 1.1× | 92% | 1,711 / 1,995 |
| Residues mod 2 (12 rows), 3 (4), 5 (3) | 11,407 / 9,300 | 1.4–1.7× | 81–90% | 8,681 / 13,077 |
| Parity alone | 16 | 985× | 0.2% | 303 |

## 6. Not done

- The hash-top rule was not run as a search.
- No SBCL implementation of the memory rule.
- Label storage was measured only in Python.
- Library tasks reach only size 5.
- No task with two lifts.
- K with records that hold no candidate (re-derive the class instead) was not tried.
