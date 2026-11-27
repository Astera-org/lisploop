#!/bin/sh
# Run the real bootstrap in the second copy (boot/v2), instrumented to dump the sixteen function specs.
# Output: boot-specs.sexp (one form per synthesized function), logs/bootstrap-instrumented.log.
# Then compare the regenerated library with the committed one.
W="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$W/logs"
cd "$W/boot/v2" || exit 1
( time timeout 600 sbcl --script bootstrap/build-batteries.lisp ) > "$W/logs/bootstrap-instrumented.log" 2>&1
echo "bootstrap exit $?"
diff "$W/boot/v2/bootstrap/build-batteries.orig.lisp" "$W/boot/v2/bootstrap/build-batteries.lisp" \
  > "$W/logs/bootstrap-instrumentation.diff"
for f in "$W/kernel/v2/library"/*.sexp; do
  b=$(basename "$f")
  if cmp -s "$f" "$W/boot/v2/library/$b"; then echo "identical  $b"; else echo "DIFFERENT  $b"; fi
done > "$W/logs/bootstrap-library-compare.txt"
cat "$W/logs/bootstrap-library-compare.txt"
wc -l "$W/boot-specs.sexp"
