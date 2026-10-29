# Milestone 2 frame visualizer

Open [report.html](report.html) directly in a desktop browser. It is self-contained:
no server, network connection, JavaScript packages, or Graphviz installation is
needed. [data.json](data.json) contains the same exported records for inspection
with other tools.

Regenerate from the repository root:

```sh
make visualizer
```

This runs `sbcl --script visualizer/generate.lisp`, using the Makefile's `SBCL`
setting. The script also works by absolute path from another directory. It loads the
current kernel and fixtures, runs the small milestone 2 experiments, and writes
only `visualizer/report.html` and `visualizer/data.json`. No root source, build
targets, experiment logs, or documentation are modified. Generated snapshots
reflect the kernel at generation time; rerun after another agent changes it.

Choose an experiment and scope at the top. Two experiments cover GF(5)
and exact integers using the kernel's single binary encoding. The 11 scopes include
discovery, fresh-data replay, changed-transition counterexamples, accidental
agreement, expanded-input replay, and the extended GF(5) bound of 54 bits.

- Transition diagrams show the recorded state paths and the selected observable.
  Equal outputs share a color; red arrows identify failing pairs.
- Select an output bucket and a syntax form to inspect its vector, typed AST,
  exact binary packet, description size, and execution work. Constants and failed
  invariant proposals remain visible.
- Frame tables preserve every occurrence key, declared input, and requirement.
  Expand the original transition frame to see its joint successor targets.
- The agreement control compares `x` and `x*x` across two separate scopes.
- Scope metadata, work categories, messages, and raw JSON remain available below.

Large integer values are exact decimal strings in JSON. For readability the viewer
uses `N = 2^256` and abbreviates long values. Hover for the exact decimal value or
select **Show full integers**. It never converts domain values to floating point.

Bucket membership means equality on that scope's ordered observations. It does
not license universal laws, rewrites, or pruning. Row keys, pair links, and selected
anchors are metadata, not predictor inputs. Probe `allowed` predicates remain
visible but are not used by the observation index. Original transition targets
are exported as joint values, without splitting correlated components.

Both experiments allow all domain literals, as in `results.md`. Description length
is the exact bit length of the standalone binary packet: schema header plus body.
The inspector displays that breakdown and the actual encoded bits. Work follows
the separate structural tariff. Encoding version 7 and tariff version 8 are saved
with every scope; they identify the current specification, not selectable models.
Text displays the AST and does not determine its price. A replay checks only its
explicit expression list; its bound is not grammar exhaustion. Exporting and
rendering are outside the work ledgers. The browser performs no synthesis or evaluation.

## Inspect an existing job

The exporter is reusable independently of the demo generator:

```lisp
(load "visualizer/export.lisp")

;; JOB is an existing observation job. This does not resume or modify it.
(lisploop-visualizer:write-job-report
 job #p"visualizer/my-job.html" :title "My observations")

;; Or export just a frame or job snapshot to JSON.
(with-open-file (out #p"visualizer/my-frame.json"
                     :direction :output :if-exists :supersede)
  (lisploop-visualizer:write-json
   (lisploop-visualizer:frame-data frame) out))
```

`write-job-report` and `job-data` accept optional `:transitions`, `:acquisition`,
and `:orientation` records. Without transitions, the probe table and scope's pair
links still work. Error records retain diagnostics and never enter equality
buckets; a pending record remains separate. Predicate requirements are exported
as syntax and are never solved or sampled by the exporter.

`export.lisp` keeps a small inspection boundary to the kernel's internal
scope/job accessors. It adds no exports to the kernel package and installs no hooks.
`viewer.html`, `viewer.css`, and `viewer.js` are the report template and assets;
edit those and regenerate. `write-report` assembles a custom multi-job bundle.

## Checks

```sh
sbcl --script tests/visualizer.lisp
node visualizer/check-data.cjs
```

The Lisp checks cover joint and empty requirements, exact and quoted values, safe JSON
embedding, read-only snapshots during interruption, and error isolation. The
data check validates all scopes, pair links, retained syntax, bucket vectors,
counts and work totals from `results.md`, including the 105-expression extended bound.
It also checks that the standalone HTML embeds the same JSON.
The JSON/report schema version is 2; regenerate old snapshots after updating the kernel.

An optional desktop interaction check uses a locally installed Chromium and
Node's standard library (no npm install):

```sh
node visualizer/browser-test.cjs
```

Set `CHROMIUM` to another Chromium binary if needed. This checks scope switching,
bucket selection, filters, and exact integer display. Chromium may require local
permission to run outside a restricted sandbox.
