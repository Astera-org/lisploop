;;;; r1-occam.lisp -- extra: the size-minimal split policy (*occam* = t) on EVERY sequence-output spec,
;;;; to see what the review's recommendation costs on the kernel's own rows.  After tg-probe-r1.lisp, r1-spec.lisp.
(in-package :tg)
(defun r1-occam ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== *occam* = t on the sequence-output spec tasks (max size 10, budget 30M) ===~%")
    (let ((*occam* t) (*d-ops* (append *d-ops* (ops 'call1b))))
      (dolist (n '("copy" "inc-all" "dbl-all" "positions" "scan" "shift-seq" "filter" "map-adjacent"))
        (run-seq n :label "occam")))
    (finish-output)))
