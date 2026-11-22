#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== Pure Kernel (load.lisp 25 modules + benchmark.lisp) ==="
cccc package.lisp ast.lisp knowledge.lisp codec.lisp vm.lisp evidence.lisp persistence.lisp requirements.lisp frame.lisp enumerate.lisp unify.lisp fibers.lisp laws.lisp templates.lisp condense.lisp abstraction.lisp descriptors.lisp relations.lisp synthesize.lisp nogoods.lisp decompose.lisp proposals.lisp consolidate.lisp messages.lisp explain.lisp benchmark.lisp | jq '.summary | {files, functions, cognitive, cyclomatic}'
echo "=== All v2 Lisp Modules (incl. bootstrap & milestones) ==="
cccc *.lisp bootstrap/*.lisp milestones/*.lisp | jq '.summary | {files, functions, cognitive, cyclomatic}'
