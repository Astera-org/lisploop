;;;; Do :map and :foldr still emerge when the six seed specs get NO whitelist (full generic
;;;; grammar) and NO recursion schemas, and when seeds are perturbed? (scratch copy)
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)
(defun pp (x)
  (cond ((and (lit-p x) (code-type-p (ast-type x))) (list :code (pp (ast-value x))))
        ((lit-p x) (list 'quote (ast-value x)))
        ((var-p x) (intern (format nil "X~D" (ast-id x))))
        ((app-p x) (cons (if (operator-p (first x)) (operator-name (first x)) (pp (first x))) (mapcar #'pp (rest x))))
        (t x)))
(defun trial (label active-p seeds)
  (with-clean-kernel-state
    (let* ((seq-t (sequence-type :int)) (in1 (list (cons 0 seq-t))) (ledger (make-ledger))
           (*use-active-library-grammar* active-p)
           (s-ops (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t) (op :if seq-t) (op :+ :int) (op :* :int)))
           (i-ops (list (op :tail :int) (op :at seq-t) (op := seq-t) (op :if :int) (op :+ :int) (op :* :int)))
           (solved nil) (work 0))
      (loop for (id ret rows lits) in seeds
            do (handler-case
                   (let ((l (make-ledger)))
                     (synthesize-spec-entry
                      (register-knowledge-spec (keyword-id "SPEC/~A" id) in1 ret rows :target-id id
                                               :operators (if (eq ret :int) i-ops s-ops) :literals lits
                                               :constants (list (lit seq-t '())) :ledger ledger)
                      :bound 90 :budget 350000 :ledger l)
                     (incf work (ledger-total l))
                     (push id solved))
                 (error () (format t "   seed ~A failed~%" id))))
      (setf solved (nreverse solved))
      (let ((accepted (discover-library-abstractions (mapcar #'find-function-definition solved)
                                                     :register-p nil :ledger ledger)))
        (format t "~&[~A] seeds solved ~D/~D (work ~:D); abstractions accepted: ~D~%" label (length solved) (length seeds) work (length accepted))
        (dolist (a accepted)
          (format t "    ~A : inputs ~S -> ~S  gain=~D bits  covers ~S~%      ~S~%"
                  (library-abstraction-name a) (mapcar #'cdr (library-abstraction-inputs a))
                  (library-abstraction-return-type a) (library-abstraction-gain a)
                  (library-abstraction-programs a) (pp (library-abstraction-body a))))))))
(defparameter *seeds*
  '((:copy (:seq :int) (((()) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))) nil)
    (:inc-all (:seq :int) (((()) ()) (((3)) (4)) (((1 3)) (2 4)) (((4 1 3)) (5 2 4))) (1))
    (:dbl-all (:seq :int) (((()) ()) (((3)) (6)) (((1 3)) (2 6)) (((4 1 3)) (8 2 6))) (2))
    (:sum-all :int (((()) 0) (((3)) 3) (((2 3)) 5) (((4 2 3)) 9)) (0))
    (:len-all :int (((()) 0) (((3)) 1) (((2 3)) 2) (((4 2 3)) 3)) (0 1))
    (:prd-all :int (((()) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24)) (1))))
(trial "bootstrap as written (whitelist)" nil *seeds*)
(trial "full generic grammar, no whitelist, no schemas" t *seeds*)
;; only two seeds per signature
(trial "generic grammar, 2+2 seeds (inc,dbl / sum,prd)" t (list (second *seeds*) (third *seeds*) (fourth *seeds*) (sixth *seeds*)))
;; one seed per signature: nothing to anti-unify
(trial "generic grammar, 1+1 seeds (inc / sum)" t (list (second *seeds*) (fourth *seeds*)))
