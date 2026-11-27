#!/bin/bash
cd /home/tlh24/lisploop
for fn in pullback-frame lift-frame product-slot-frame conserved-quantity-frame context-label-frame support-frame probe-frame-coordinates project-frame-rows orient-available orient-observations transition-probes lookup-model frame-oracle-table compose-model compose-product-model compose-lifted-model let-call share-repeated-subterms partition-rows reassemble-partition quotient-values restore-quotient quotient-model partition-model partition-pairs-and-anchors with-frame-linkage priced-correction correction-bit-size correction-packet apply-correction-packet select-closest-witness relational-linkage-residual pulled-back-metric frame-metric metric-decoders metric-delta register-metric-decoder anti-unify match-pattern au-substitutions-frame compile-au-constructor shared-subterm-cover abstract-over-subterms infer-fibers fiber-pairs-and-anchors instantiate map-ast replace-subexpression fold-constants conjoin-requirements check-requirement extract-allowed-values frame-conflict-p solve-equality-symbolically orient-conserved-quantity hard-edges frame-edges frame-pairs frame-anchors pair-connected-component minimum-disambiguation-bit-size shuffle-frame-rows code-edit expression-less-p; do
  echo "== $fn"
  grep -c "($fn \|#'$fn\b" *.lisp | grep -v ":0" | tr '\n' ' '
  echo
done
