;;; Smoke test of Stage-1 WIP opcodes. Usage: sbcl --script smoke.lisp <path-to-v2-dir/>
(defvar *v2* (second sb-ext:*posix-argv*))
(load (merge-pathnames "load.lisp" *v2*))
(in-package #:lisploop)

(defmacro try (label form)
  `(handler-case
       (let ((v ,form)) (format t "~&OK    ~A => ~S~%" ,label v))
     (error (e) (format t "~&FAIL  ~A => ~A~%" ,label (remove #\Newline (princ-to-string e))))))

(defun run (expr &optional inputs values (budget 100000))
  (let ((s (evaluate expr inputs values :budget budget)))
    (list (evaluation-status s) (evaluation-value s) :work (evaluation-work s))))

(let* ((ints '(:seq :int))
       (idx-code (code-type '((0 . :int)) :int))
       (step-code (code-type '((0 . :int) (1 . :int)) :int)))
  (format t "~&--- operator table size: ~D primitives~%" (length +operator-names+))
  (try "iota 4" (run (app (op :iota :int) (lit :int 4))))
  (try "iota -2" (run (app (op :iota :int) (lit :int -2))))
  (try "length(iota n) n=5" (run (term `(length (iota ,(var 0 :int)))) '((0 . :int)) '(5)))
  (try "where 3 in (1 3 2 3)" (run (app (op :where :int) (lit :int 3) (lit ints '(1 3 2 3)))))
  (try "tabulate 4 (j -> j*j)"
       (run (app (op :tabulate :int) (lit :int 4)
                 (lit idx-code (term `(* ,(var 0 :int) ,(var 0 :int)))))))
  (try "tabulate paused budget=5"
       (run (app (op :tabulate :int) (lit :int 4)
                 (lit idx-code (term `(* ,(var 0 :int) ,(var 0 :int))))) nil nil 5))
  (try "tabulate 0" (run (app (op :tabulate :int) (lit :int 0) (lit idx-code (var 0 :int)))))
  (try "tabulate erroring body (/ 1 j)"
       (run (app (op :tabulate :int) (lit :int 3)
                 (lit idx-code (term `(/ 1 ,(var 0 :int)))))))
  (try "evolve (1 2 3) s0=0 (s,x -> s+x) [running sums]"
       (run (app (op :evolve (tuple-type :int :int)) (lit ints '(1 2 3)) (lit :int 0)
                 (lit step-code (term `(+ ,(var 0 :int) ,(var 1 :int)))))))
  (try "evolve () "
       (run (app (op :evolve (tuple-type :int :int)) (lit ints '()) (lit :int 0)
                 (lit step-code (term `(+ ,(var 0 :int) ,(var 1 :int)))))))
  ;; at/tabulate beta law and at/iota law through the VM
  (try "at (tabulate 4 j*j) 3"
       (run (term `(at ,(app (op :tabulate :int) (lit :int 4)
                             (lit idx-code (term `(* ,(var 0 :int) ,(var 0 :int)))))
                       3))))
  ;; provably-total-p on new forms
  (try "total? (iota x0)" (provably-total-p (term `(iota ,(var 0 :int)))))
  (try "total? (at (iota 4) 2)" (provably-total-p (term `(at (iota 4) 2))))
  (try "total? (at x0 (mod x1 (length x0))) [mod-range not certified]"
       (provably-total-p (term `(at ,(var 0 ints) (mod ,(var 1 :int) (length ,(var 0 ints)))))))
  (try "total? (if (< x1 (length x0)) (if (< -1 x1) (at x0 x1) 0) 0)"
       (provably-total-p (term `(if (< ,(var 1 :int) (length ,(var 0 ints)))
                                    (if (< -1 ,(var 1 :int)) (at ,(var 0 ints) ,(var 1 :int)) 0)
                                    0))))
  (try "total? (if (< (+ x1 x2) (length x0)) (if (< -1 (+ x1 x2)) (at x0 (+ x1 x2)) 0) 0)"
       (provably-total-p (term `(if (< (+ ,(var 1 :int) ,(var 2 :int)) (length ,(var 0 ints)))
                                    (if (< -1 (+ ,(var 1 :int) ,(var 2 :int)))
                                        (at ,(var 0 ints) (+ ,(var 1 :int) ,(var 2 :int))) 0)
                                    0))))
  (try "UNSOUND? total? (at x0 x1) unguarded" (provably-total-p (term `(at ,(var 0 ints) ,(var 1 :int)))))
  ;; definedness guard derivation
  (try "definedness-guard (/ x0 x1)"
       (definedness-guard-for-expr (term `(/ ,(var 0 :int) ,(var 1 :int)))))
  (try "definedness-guard (at x0 (+ x1 x2))"
       (definedness-guard-for-expr (term `(at ,(var 0 ints) (+ ,(var 1 :int) ,(var 2 :int))))))
  ;; code intro/elim
  (let* ((ct (code-type '((0 . :int)) :int)))
    (try "code-arity '(+ x0 1)" (run (app (op :code-arity ct) (lit ct (term `(+ ,(var 0 :int) 1))))))
    (try "code-var 0" (run (app (op :code-var ct) (lit :int 0))))
    (try "code-var-id 'x0" (run (app (op :code-var-id ct) (lit ct (var 0 :int)))))
    (try "code-quote 7" (run (app (op :code-quote ct) (lit :int 7))))
    (try "code-value '7" (run (app (op :code-value ct) (lit ct (lit :int 7)))))
    (try "code-value (code-quote 7) roundtrip"
         (run (app (op :code-value ct) (app (op :code-quote ct) (lit :int 7)))))
    ;; anti-unify (+ x0 1) and (+ x0 2) -> (+ x0 ?) with hole lowered to var 1
    (let* ((out (code-type '((0 . :int) (1 . :int)) :int)))
      (try "code-anti-unify '(+ x0 1) '(+ x0 2)"
           (run (app (op :code-anti-unify (tuple-type ct out))
                     (lit ct (term `(+ ,(var 0 :int) 1)))
                     (lit ct (term `(+ ,(var 0 :int) 2))))))
      (try "code-anti-unify with insufficient out scope (same ct)"
           (run (app (op :code-anti-unify (tuple-type ct ct))
                     (lit ct (term `(+ ,(var 0 :int) 1)))
                     (lit ct (term `(+ ,(var 0 :int) 2))))))
      (try "code-anti-unify identical terms"
           (run (app (op :code-anti-unify (tuple-type ct out))
                     (lit ct (term `(+ ,(var 0 :int) 1)))
                     (lit ct (term `(+ ,(var 0 :int) 1))))))))
  ;; codec roundtrip of new ops
  (dolist (e (list (app (op :iota :int) (var 0 :int))
                   (app (op :where :int) (var 0 :int) (lit ints '(1 3 2 3)))
                   (app (op :tabulate :int) (var 0 :int)
                        (lit idx-code (term `(* ,(var 0 :int) ,(var 0 :int)))))))
    (try (format nil "codec roundtrip ~S" (ast-id e))
         (let* ((inputs '((0 . :int)))
                (bits (encode-model e inputs)))
           (list :bits (length bits) :desc-size (description-size e inputs)
                 :roundtrip (equal e (decode-model bits))))))
  ;; requirement folding: (= (gather '(5 6 5) Z) '(5 6)) under :necessary
  (try "fold (= (gather '(5 6 5) Z) '(5 6)) :necessary"
       (fold-constants (term `(= (gather ,(lit ints '(5 6 5)) ,(var 0 ints)) ,(lit ints '(5 6))))
                       :contract :necessary))
  (try "fold (= (tabulate 3 F) '(0 1 4)) :necessary"
       (fold-constants (term `(= ,(app (op :tabulate :int) (lit :int 3) (var 0 idx-code))
                                 ,(lit ints '(0 1 4))))
                       :contract :necessary))
  (try "fold (= (evolve '(1 2 3) 0 F) '(1 3 6)) :necessary"
       (fold-constants (term `(= ,(app (op :evolve (tuple-type :int :int)) (lit ints '(1 2 3)) (lit :int 0)
                                       (var 0 step-code))
                                 ,(lit ints '(1 3 6))))
                       :contract :necessary))
  ;; effective horizon
  (try "application-overhead vs effective for :code-eval"
       (let ((o (op :code-eval (tuple-type (code-type '((0 . :int) (1 . :int)) :int) :int :int))))
         (list :exact (application-overhead o) :effective (effective-application-overhead o))))
  (try "application-overhead vs effective for :+"
       (let ((o (op :+ :int)))
         (list :exact (application-overhead o) :effective (effective-application-overhead o)))))
