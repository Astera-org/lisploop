;;;; dump-prereqs.lisp -- write x3-prerequisites.lisp: the two library functions that the Stage 0 harness
;;;; loads from the batteries before the seventh spec and that are not themselves among the sixteen:
;;;; :map and :foldr (v2/library/sequences.sexp).  Same plain style as x3-specs.lisp.
(load (merge-pathnames "x3-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

(let* ((path (merge-pathnames "x3-prerequisites.lisp" cl-user::*x3-work*))
       (lib (deserialize-knowledge-library (read-battery :sequences))))
  (with-open-file (out path :direction :output :if-exists :supersede)
    (format out ";;;; x3-prerequisites.lisp -- library functions in scope for the last ten of the sixteen specs~%")
    (format out ";;;; that are not themselves among the sixteen.  The bootstrap derives both by anti-unification~%")
    (format out ";;;; of the six seed functions (build-batteries.lisp:569-584); the Stage 0 harness loads them from~%")
    (format out ";;;; v2/library/sequences.sexp just before foldl (stage0-audit.lisp:195-196).~%")
    (format out ";;;; Written by base-x3/dump-prereqs.lisp.  Same conventions as x3-specs.lisp.~%")
    (with-clean-kernel-state
      (load-battery :sequences :only '(:map :foldr) :check-examples-p nil)
      (dolist (id '(:map :foldr))
        (let* ((ent (find-knowledge-entry id lib))
               (spec (find-knowledge-entry (keyword-id "SPEC/~A" id) lib))
               (inputs (knowledge-entry-inputs ent)) (target (knowledge-entry-target ent)))
          (format out "~%(:name ~(~A~)~% :params " id)
          (emit (loop for (pid . ty) in inputs collect (list (psym "X~D" pid) ty)) out)
          (format out "~% :returns ") (emit target out)
          (format out "~% :rows (")
          (loop for (known expected) in (spec-entry-rows spec)
                do (format out "~%   ")
                   (emit (list (loop for v in known for (nil . ty) in inputs collect (plain-value v ty))
                               (plain-value expected target))
                         out))
          (format out ")~% :definition ") (emit (ast->sexp (knowledge-entry-expression ent)) out)
          (format out "~% :definition-readable ")
          (emit (plain (knowledge-entry-expression (find-knowledge-entry id))) out)
          (format out "~% :definition-bits ~D" (knowledge-entry-bits ent))
          (format out "~% :notes ~S)~%"
                  (if (eq id :map)
                      "Applies the one-argument code x1 to every element. Its two rows are a check the bootstrap replays (verify-entry-against-spec), not rows it synthesizes from."
                      "Right fold: f(e0, f(e1, ... f(en, x1))), the element first and the accumulated value second. Its two rows are a check the bootstrap replays, not rows it synthesizes from."))))))
  (format t "~&wrote ~A~%" (namestring path))
  (let ((forms (read-plain-file path))) (format t "read back ~D forms~%" (length forms))))
