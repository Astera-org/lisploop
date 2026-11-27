;; debug: per-level counters of the spec shift-seq / scan runs under *occam* with the :first filter
(in-package :tg)
(defun dbg-occam ()
  (dolist (n '("spec shift-seq" "spec scan"))
    (let* ((e (first (spec-tasks :occam t :only (list n))))
           (r (lrun *cfg-first* (third e)))
           (b (main-bank r)))
      (format t "~a: done ~a final ~a~%" n (getf b :done) (getf b :final))
      (dolist (l (getf b :levels)) (format t "   level ~a~%" l)))))
