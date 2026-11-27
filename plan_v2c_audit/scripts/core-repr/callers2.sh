#!/bin/bash
cd /home/tlh24/lisploop
for fn in context-label-frame probe-frame-coordinates orient-available transition-probes lookup-model restore-quotient partition-model with-frame-linkage correction-packet au-substitutions-frame fiber-pairs-and-anchors check-requirement orient-conserved-quantity shuffle-frame-rows quotient-model partition-rows conserved-quantity-frame product-slot-frame lift-frame probe-frame relational-linkage-residual pulled-back-metric infer-fibers solve-equality-symbolically; do
  k=$(grep -n "[(']$fn\b" *.lisp | grep -v "(defun $fn" | grep -v "^package.lisp" | wc -l)
  t=$(grep -rn "[(']$fn\b" tests | wc -l)
  m=$(grep -rn "[(']$fn\b" milestones bootstrap experiments 2>/dev/null | wc -l)
  echo "$fn kernel=$k tests=$t milestones/bootstrap/experiments=$m"
done
