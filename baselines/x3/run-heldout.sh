#!/bin/sh
# 1. Re-run the audit's own cross-check (run-xref.sh) in the writable copy vr/run: it regenerates
#    logs/xref-data.sexp (the 200 held-out examples per task) and re-evaluates the library's definitions
#    in the kernel VM on them.  The script needs kernel/v2 beside it; link the copy.
# 2. Write x3-heldout.lisp with heldout-dump.lisp.
# 3. Compare the regenerated xref-data.sexp with the audit's stored one.
W="$(cd "$(dirname "$0")" && pwd)"
cd "$W/vr/run" || exit 1
[ -e kernel ] || ln -s "$W/kernel" kernel
sh ./run-xref.sh > "$W/logs/vr-run-xref.out" 2>&1
cat "$W/logs/vr-run-xref.out"
cp logs/xref-kernel.log "$W/logs/vr-xref-kernel.log"
cp logs/xref-data.sexp "$W/logs/vr-xref-data.sexp"
if cmp -s logs/xref-data.sexp "$W/vr/orig/logs/xref-data.sexp"; then
  echo "xref-data.sexp: regenerated copy is byte-identical to the audit's stored log"
else
  echo "xref-data.sexp: regenerated copy DIFFERS from the audit's stored log"
fi > "$W/logs/vr-xref-data-compare.txt"
cat "$W/logs/vr-xref-data-compare.txt"
timeout 300 sbcl --dynamic-space-size 4GB --noinform --non-interactive \
   --load tg-probe-r1.lisp --load r1-spec.lisp --load "$W/heldout-dump.lisp" \
   --out "$W/x3-heldout.lisp" --src "$W/vr/run/r1-spec.lisp" > "$W/logs/heldout-dump.log" 2>&1
echo "heldout-dump exit $?"
tail -3 "$W/logs/heldout-dump.log"
