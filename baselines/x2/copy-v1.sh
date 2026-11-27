#!/bin/bash
# Make a fresh private copy of the v1 kernel (source only) in this work directory.
# The repository itself is never written to.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$HERE/../.." && pwd)}"
SRC="$REPO/v1"
DST="$HERE/v1"
rm -rf "$DST"
mkdir -p "$DST"
# Lisp sources, the tracked library, tests, milestones, bootstrap, experiments. No PDFs or figures.
( cd "$SRC" && find . \( -name '*.lisp' -o -name '*.sexp' \) -print0 | cpio -0 -pdm --quiet "$DST" )
( cd "$SRC" && sha256sum milestones/algebra-discovery.lisp tests/milestones/algebra.lisp tests/milestones/support.lisp vm.lisp laws.lisp ast.lisp enumerate.lisp frame.lisp ) > "$HERE/source-sha256.txt"
( cd "$REPO" && git rev-parse HEAD ) > "$HERE/source-commit.txt" 2>/dev/null || true
echo "copied $(find "$DST" -type f | wc -l) files to $DST"
