;;;; r6-au.lisp -- verify-review R6.  Root kernel from the scratch copy; anti-unify (unify.lisp:36-73).
(load (merge-pathnames "kernel/load.lisp" *load-truename*))
(in-package :lisploop)
(setf *print-pretty* nil *print-right-margin* 100000)

(defun show-au (label sources scope &rest keys)
  (multiple-value-bind (pattern substitutions) (apply #'anti-unify sources scope nil keys)
    (format t "~a~%   sources:  ~{~a~^   ~}~%   pattern:  ~a~%   holes:    ~d distinct ~a~%   fillings: ~{~a~^   ~}~%"
            label (mapcar #'ast->sexp sources) (ast->sexp pattern)
            (length (pattern-holes pattern)) (pattern-holes pattern)
            (mapcar (lambda (s) (mapcar (lambda (b) (list (car b) (ast->sexp (cdr b)))) s)) substitutions))))

(let* ((scope '((0 . :int) (1 . :int) (2 . :int))) (x (var 0 :int)) (y (var 1 :int)) (z (var 2 :int)))
  (format t "=== R6. anti-unify (unify.lisp:36-73); x = (var 0 :int), y = (var 1 :int), z = (var 2 :int) ===~%")
  (show-au "1. (+ x x) vs (+ y y)" (list (term `(+ ,x ,x)) (term `(+ ,y ,y))) scope)
  (show-au "2. (+ x y) vs (+ y x)" (list (term `(+ ,x ,y)) (term `(+ ,y ,x))) scope)
  (show-au "3. (+ x x) vs (+ y z)   (no sharing possible)" (list (term `(+ ,x ,x)) (term `(+ ,y ,z))) scope)
  (show-au "4. (* (+ x 1) (+ x 1)) vs (* (+ y 1) (+ y 1))   (sharing below the root)"
           (list (term `(* (+ ,x 1) (+ ,x 1))) (term `(* (+ ,y 1) (+ ,y 1)))) scope)
  (show-au "5. three sources (+ x x), (+ y y), (+ z z)"
           (list (term `(+ ,x ,x)) (term `(+ ,y ,y)) (term `(+ ,z ,z))) scope)
  (show-au "6. (+ x x) vs (* y y), default (operator holes on): the operator varies too"
           (list (term `(+ ,x ,x)) (term `(* ,y ,y))) scope)
  (show-au "7. (+ x x) vs (* y y), :operator-holes-p nil"
           (list (term `(+ ,x ,x)) (term `(* ,y ,y))) scope :operator-holes-p nil)
  (show-au "8. (+ x 3) vs (+ y 3): a constant column stays in the pattern"
           (list (term `(+ ,x 3)) (term `(+ ,y 3))) scope))
(finish-output)
