#!/bin/sh
# A second copy of v2/, used only to run the real bootstrap with one function instrumented, so that the
# sixteen function specs and the programs the bootstrap derives for them are dumped as it runs.
# The bootstrap writes library/*.sexp beside itself; here that is inside this copy, never the repository.
W="$(cd "$(dirname "$0")" && pwd)"
SRC="${REPO:-$(cd "$W/../.." && pwd)}"
X3_BASE_COMMIT="${X3_BASE_COMMIT:-65d1df2}"
mkdir -p "$W/boot"
rm -rf "$W/boot/v2"
git -C "$SRC" archive "$X3_BASE_COMMIT" v2 | tar -x -C "$W/boot"
cp "$W/boot/v2/bootstrap/build-batteries.lisp" "$W/boot/v2/bootstrap/build-batteries.orig.lisp"
patch -s "$W/boot/v2/bootstrap/build-batteries.lisp" "$W/bootstrap-instrumentation.diff"
echo "copied to boot/v2 (from $X3_BASE_COMMIT) and applied instrumentation"
