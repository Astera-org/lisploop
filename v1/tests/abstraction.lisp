(in-package #:lisploop)

;;; Pure-kernel tests for syntactic anti-unification (`unify.lisp`) and
;;; higher-order library abstraction (`abstraction.lisp`).

(defun kernel-alpha-equivalent-patterns-p (left right)
  "Check syntactic equality of two patterns up to bijective hole-ID renaming."
  (let ((fwd nil)
        (rev nil))
    (labels ((walk (a b)
               (cond
                 ((and (hole-p a) (hole-p b))
                  (and (equal (ast-type a) (ast-type b))
                       (let ((id-a (ast-id a))
                             (id-b (ast-id b)))
                         (let ((mapped-b (assoc id-a fwd))
                               (mapped-a (assoc id-b rev)))
                           (cond
                             ((and mapped-b mapped-a)
                              (and (= (cdr mapped-b) id-b)
                                   (= (cdr mapped-a) id-a)))
                             ((or mapped-b mapped-a) nil)
                             (t (push (cons id-a id-b) fwd)
                                (push (cons id-b id-a) rev)
                                t))))))
                 ((and (app-p a) (app-p b))
                  (and (= (length a) (length b))
                       (every #'walk a b)))
                 (t (equal a b)))))
      (walk left right))))

(defun kernel-reference-aligned-au (sources &optional inputs)
  "Independent reference aligned anti-unification assigning holes from 100 upward."
  (assert sources)
  (let ((memo nil)
        (next-hole 100))
    (labels ((ref-sort (term)
               (if (operator-p term)
                   (operator-type term)
                   (expression-type term inputs t)))
             (walk (terms)
               (let ((sorts (mapcar #'ref-sort terms)))
                 (assert (every (lambda (s) (equal s (first sorts))) sorts))
                 (cond
                   ((every (lambda (term) (equal term (first terms))) terms)
                    (first terms))
                   ((and (every #'app-p terms)
                         (let ((sigs (mapcar (lambda (term) (operator-type (first term))) terms)))
                           (every (lambda (sig) (equal sig (first sigs))) sigs)))
                    (apply #'app
                           (walk (mapcar #'first terms))
                           (loop for i below (length (rest (first terms)))
                                 collect (walk (mapcar (lambda (term) (nth i (rest term))) terms)))))
                   (t
                    (let ((existing (assoc terms memo :test #'equal)))
                      (if existing
                          (cdr existing)
                          (let ((h (hole (prog1 next-hole (incf next-hole)) (first sorts))))
                            (push (cons terms h) memo)
                            h))))))))
      (walk sources))))

(deftest kernel-aligned-au-and-constructor-compilation
  (let* ((domain :int)
         (work (make-ledger))
         (inputs (list (cons 0 domain) (cons 1 domain)))
         (x0 (var 0 domain))
         (x1 (var 1 domain))
         (plus (op :+ domain))
         (mul (op :* domain))
         (t1 (app plus (lit domain 2) (lit domain 2)))
         (t2 (app mul (lit domain 3) (lit domain 3))))
    (multiple-value-bind (pat substs) (anti-unify (list t1 t2) inputs work)
      (let ((ref-pat (kernel-reference-aligned-au (list t1 t2) inputs)))
        (check (kernel-alpha-equivalent-patterns-p pat ref-pat))
        (multiple-value-bind (ctor-expr ctor-inputs) (compile-au-constructor pat inputs work)
          (check (= 2 (length ctor-inputs)))
          (check-codec-roundtrip ctor-expr ctor-inputs)
          (loop for target in (list t1 t2)
                for subst in substs
                for vals = (mapcar (lambda (inp) (cdr (assoc (car inp) subst))) ctor-inputs)
                do (check (equal target (result ctor-expr ctor-inputs vals)))))))
    ;; LGG tightness when substitutions share structure
    (let* ((loose-pat (app plus (hole 0 domain) (hole 1 domain)))
           (s1 (list (cons 0 x0) (cons 1 (app mul (lit domain 2) x0))))
           (s2 (list (cons 0 x1) (cons 1 (app mul (lit domain 2) x1))))
           (inst1 (instantiate loose-pat s1))
           (inst2 (instantiate loose-pat s2))
           (tight-pat (anti-unify (list inst1 inst2) inputs work))
           (expected-lgg (app plus (hole 0 domain) (app mul (lit domain 2) (hole 0 domain)))))
      (check (kernel-alpha-equivalent-patterns-p tight-pat expected-lgg))
      (check (not (kernel-alpha-equivalent-patterns-p tight-pat loose-pat))))))

(deftest kernel-higher-order-abstraction-and-compression-contract
  (with-clean-kernel-state
    ;; 1. 2-function fold pair (:sum + :product) has negative net MDL gain because
    ;;    2-parameter higher-order fold header overhead exceeds 2-call savings under `:min-gain 0`.
    (let* ((r4 (standard-r4-corpus))
           (pair (list (fourth r4) (sixth r4))))
      (multiple-value-bind (accepted refactored all-cands)
          (discover-library-abstractions pair :register-p nil :min-gain 0)
        (check (null accepted))
        (check (= 2 (length refactored)))
        (check (= 1 (length all-cands)))
        (check (minusp (library-abstraction-gain (first all-cands))))))
    ;; 2. Full 6-function recursive list corpus discovers positive-gain higher-order combinators
    ;;    (:map and :foldr equivalents) and refactors all 6 programs with exact held-out semantics.
    (let ((held-out '((:copy       (((1 -2 3)) (1 -2 3)) ((()) ()))
                      (:inc-all    (((1 -2 3)) (2 -1 4)) ((()) ()))
                      (:double-all (((1 -2 3)) (2 -4 6)) ((()) ()))
                      (:sum        (((1 -2 3 4)) 6)      ((()) 0))
                      (:length     (((10 20 30)) 3)      ((()) 0))
                      (:product    (((2 -3 4)) -24)      ((()) 1)))))
      (check-library-abstractions-contract
       (standard-r4-corpus)
       :register-p t
       :min-gain 0
       :expected-count 2
       :held-out-by-name held-out))))
