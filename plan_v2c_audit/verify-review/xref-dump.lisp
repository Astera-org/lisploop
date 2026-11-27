;;;; xref-dump.lisp -- probe side of the reference cross-check.  After tg-probe-r1.lisp + r1-spec.lisp.
;;;; Writes (1) my hand-copied spec rows and (2) the 200 held-out examples per task (the exact ones
;;;; VERIFY uses: seed 999, maxlen 12) with MY reference's output, for the kernel to re-evaluate.
(in-package :tg)
(let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
  (with-open-file (out "logs/xref-data.sexp" :direction :output :if-exists :supersede)
    (dolist (e *spec*)
      (let ((task (car e)))
        (format out "(~s~% :spec ~s~% :held-out (" (task-name task) (cdr e))
        (dolist (ex (gen-examples task 999 200 12))
          (format out "~%  ~s" (list (mapcar #'cdr (car ex)) (cdr ex))))
        (format out "))~%"))))
  (format t "wrote logs/xref-data.sexp~%"))
