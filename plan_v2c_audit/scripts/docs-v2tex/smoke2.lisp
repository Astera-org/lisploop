(defvar *v2* (second sb-ext:*posix-argv*))
(load (merge-pathnames "load.lisp" *v2*))
(in-package #:lisploop)
(defmacro try (label form)
  `(handler-case (let ((v ,form)) (format t "~&OK    ~A => ~S~%" ,label v))
     (error (e) (format t "~&FAIL  ~A => ~A~%" ,label (remove #\Newline (princ-to-string e))))))
(defun run (expr &optional inputs values (budget 100000))
  (let ((s (evaluate expr inputs values :budget budget)))
    (list (evaluation-status s) (evaluation-value s) :work (evaluation-work s))))
(let* ((ints '(:seq :int))
       (idx-code (code-type '((0 . :int)) :int))
       (f (var 0 idx-code)))
  (try "term (code-eval F 0) raw int" (term `(code-eval ,f 0)))
  (try "term (code-eval F '0) quoted" (term `(code-eval ,f ,(lit :int 0))))
  (try "term (= (code-eval F 0) '4)" (term `(= (code-eval ,f 0) '4)))
  (try "tabulate erroring body (/ 1 j)"
       (run (app (op :tabulate :int) (lit :int 3)
                 (lit idx-code (term `(/ ,(lit :int 1) ,(var 0 :int)))))))
  (try "fold (= (tabulate 3 F) '(0 1 4)) :necessary  [as the kernel itself would call it]"
       (fold-constants (term `(= ,(app (op :tabulate :int) (lit :int 3) f) ,(lit ints '(0 1 4))))
                       :contract :necessary))
  (try "fold (at (tabulate 3 F) 1) :equivalent"
       (fold-constants (term `(at ,(app (op :tabulate :int) (lit :int 3) f) 1))))
  (try "fold (length (tabulate 3 F))" (fold-constants (term `(length ,(app (op :tabulate :int) (lit :int 3) f)))))
  ;; tabulate with a body that needs outer variables: must go through code-subst
  (try "provably-total (tabulate (length x0) 'j)" 
       (provably-total-p (app (op :tabulate :int) (term `(length ,(var 0 ints))) (lit idx-code (var 0 :int)))))
  ;; closures decline tabulate? expression-closure
  (try "operator-index new prims" (mapcar #'operator-index '(:mod :iota :tabulate :where :evolve :code-anti-unify)))
  (try "operator-by-index 27..36" (loop for i from 25 to 46 collect (operator-by-index i))))
