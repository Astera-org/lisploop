# Evidence behind `plan_v2c.md`

Collected on 24 November 2026 by fifteen AI agents working in parallel, each on one slice. `plan_v2c.md` is the synthesis; this directory is what it cites.

- `reports/` — one report per auditor. Each gives file-and-line citations, tags claims as verified or inferred, and ends with what it could not determine. `plan_v2c.md` Appendix D lists their scopes. The four `lit-search-appendix-*.md` files are working notes behind `lit-search.md`. `factcheck.md` is an independent check of a draft of `plan_v2c.md` against the other reports, the logs, and the code; its 77 findings were applied, and it tabulates where the reports disagree with one another.
- `proto/` — the standalone prototype of the proposed store (`tg-probe.lisp`, 874 lines, no kernel code), its driver, and the logs that `plan_v2c.md` §8 quotes. It runs in place: `./run.sh d` (about a minute), `./run.sh c` (seconds), `./run.sh b`, `./run.sh a`. It asks SBCL for a 10 GB heap.
- `scripts/` — the measurement scripts and logs of the auditors who ran the kernel. They were run against scratch copies of this repository and still contain those paths; point them at a copy of the tree before re-running. Files over 200 KB and the tree copies themselves were left out.

Added on 25 November 2026, for the revision that answers the owner's annotations and the outside review (`plan_v2c_audit.md` at the repository root; that revision is recorded in Part 2 of `revision-notes.md`):

- `verify-review/` and `reports/verify-review.md` — the outside review's first section re-run: the prototype with the review's modifications rebuilt (23 lines in six marked places), on the kernel's own `:spec` rows, plus checks of its claims about prices. `./run-all.sh` runs everything; the kernel-side scripts expect a scratch copy of the tree.
- `cross-space/` and `reports/cross-space.md` — three measurements of search across spaces on the unmodified prototype: retrieval by store-generated signatures, analogies between operator tables, and row matching by colour refinement with backtracking. `./run.sh`.
- `verify-quotients/` and `reports/verify-quotients.md` — the outside review's second section rebuilt in standard-library Python (its own code is not in the repository): verb tables on a 61-operator library, quotient selection, weakest guards, residues modulo small primes, and reuse. The report's last section lists the command for each log. One 2.3 MB result file (`q2_sound.json`) was left out; `q2_sound.py` regenerates it in about six minutes.
- `reports/lit-abstraction.md` — a check of the citations in the review's second section.
- `reports/factcheck2-A.md`, `reports/factcheck2-B.md` — two independent checks of the revised `plan_v2c.md` against these logs and sources (41 findings, all applied). The second checker's small re-analysis scripts are in `verify-quotients/factcheck/`; they read the logs and result files in the directory above, and the two `fc_*.py` scripts import its modules.

Added on 26 November 2026, for the revision that takes in the outside review's unified design (its section 2.5 and Appendix B) after re-testing each of its claims:

- `revision-notes.md` — what each revision of the plan changed and why. Part 1 covers this revision: a table with one row for each claim of the review, saying whether it reproduced and what the plan did with it, and an account of the plan's length. Parts 2 and 3 are the two appendices that used to be in the plan: the revision of 25 November, and the answers to the owner's annotations on `plan_v2b.md`.
- `measurements-words.md` — the full record of the measurements on words, verb tables, near misses, probes, the vocabulary, and memory. Section 8.7 of the plan gives these in short form. When another section of the plan cites §8.7 for a figure that §8.7 does not give, the figure is here, with the arrangement it was measured in.
- `round3/` — the scripts and logs of the five re-tests, one folder for each: `q1-words/` (choosing the vocabulary), `q2-probes/` (choosing the rows that the tables are built from), `q3-memory/` (the memory rules), `q4-handoff/` (labels against corrections, the near-miss check, and the cost summed over tasks), and `l1-proto/` (the label filter and the look-ahead inside a copy of the Lisp prototype). `BRIEF.md` is the brief the five were given. Everything is standard-library Python except `l1-proto/`, which needs SBCL. The reports are `reports/verify-words.md`, `verify-probes.md`, `verify-memory.md`, `verify-handoff.md`, and `verify-proto-labels.md`, and each lists the command behind each of its figures.
- `round3/reviewer/` — a copy of the outside reviewer's own scripts, which are not in the review itself. Nine scripts in the folders above run them, in order to reproduce the review's figures before testing them, and they name this folder by its full path.
- `reports/factcheck3-A.md`, `factcheck3-B.md`, `factcheck3-C.md`, `factcheck3-final.md` — four independent checks of the revised plan against the logs, the code, and the full record. The `apply-*.md` files beside them log what was done with each finding. The checkers' scripts are in `round3/checks/`. Those scripts read drafts of the plan that were kept only in a scratch folder, so they are a record of what was run and cannot be re-run as they stand.
- `reports/clarity-review.md`, `clarity-review-new.md`, `clarity-gaps-*.md`, `glossary-*.md` — two readings of the plan by first-time readers, the gaps that the clarity pass could not fill from any source, and the terms it defined.

The five reports of 26 November name a scratch folder as their work directory. The same files are in `round3/`, and the scripts there have been pointed at this folder.

Things to know when reading the reports:

- The code auditors (`core-repr`, `search-engine`, `laws-library`) were told not to read `plan_v2.md`, `plan_v2b.md`, or `plan_v2.tex`.
- Line numbers refer to the original kernel at `df33ed1` and to `v2/` at `a4e19fa`. On 26 November 2026 the original kernel and the earlier plans were moved, unchanged, into `v1/`, so a reference such as `frame.lisp:1581` is to be read as `v1/frame.lisp:1581`.
- The experiments of 26 November on words and verb tables run on a library of 61 operators written by hand for the purpose, in Python. None of them runs on the kernel's own library.
- Hour-scale figures are extrapolations. No run was longer than about 75 seconds of search, because memory stops the present enumerator there.
- Literature claims carry the auditors' own verification tags. Coverage of 2025–26 work is incomplete; see the gaps each literature report declares.
