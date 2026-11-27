(in-package #:lisploop2)

;;; Laws from collisions, certification on a finite field, and reorientation.

(defun field-bank (p variable-count op-names constants)
  "A bank on every assignment of VARIABLE-COUNT variables X0, X1, ... over the field of P elements."
  (let* ((type (gf p))
         (variables (loop for k below variable-count
                          collect (var (intern (format nil "X~d" k) '#:lisploop2) type))))
    (multiple-value-bind (space leaves) (exhaustive-space variables)
      (let ((bank (make-bank space op-names)))
        (loop for v in variables for (nil . column) in leaves do (add-leaf bank v column))
        (dolist (c constants) (add-constant bank c type))
        bank))))

(defun field-term (sexp p)
  (parse-term sexp `((x0 . ,(gf p)) (x1 . ,(gf p)) (x2 . ,(gf p))) (gf p)))

(deftest test-exhaustive-space
  (multiple-value-bind (space leaves) (exhaustive-space (list (var 'x0 (gf 3)) (var 'x1 (gf 3))))
    (check-equal 9 (space-n space))
    (check-equal (vector 0 0 0 1 1 1 2 2 2) (cdr (assoc 'x0 leaves)) "the first variable varies slowest")
    (check-equal (vector 0 1 2 0 1 2 0 1 2) (cdr (assoc 'x1 leaves))))
  (check-equal '((nil nil) (nil t) (t nil) (t t)) (type-values '(:tuple :bool :bool))))

(deftest test-certification
  (check-equal :certified (certify-equation (field-term '(* x0 (+ x1 x2)) 3)
                                            (field-term '(+ (* x0 x1) (* x0 x2)) 3)))
  (check-equal :certified (certify-equation (field-term '(* x0 (* x0 x0)) 3) (field-term 'x0 3))
               "Fermat's little theorem on GF(3)")
  (multiple-value-bind (verdict counterexample)
      (certify-equation (field-term '(* x0 (* x0 x0)) 5) (field-term 'x0 5))
    (check-equal :refuted verdict)
    (check-equal '((x0 . 2)) counterexample "a refutation comes with a counterexample"))
  ;; an equation between terms that fail on the same rows is certified; one that fails on
  ;; different rows is not
  (check-equal :certified (certify-equation (field-term '(/ (* x0 x1) x1) 3) (field-term '(/ (* x1 x0) x1) 3)))
  (check-equal :refuted (certify-equation (field-term '(/ (* x0 x1) x1) 3) (field-term 'x0 3))))

(deftest test-laws-from-collisions
  (let* ((bank (field-bank 3 3 '(+ *) '(0 1)))
         (book (collect-laws bank :grade :certified))
         (ledger (make-ledger)))
    (enumerate bank 7 ledger most-positive-fixnum)
    (check-equal (bank-collisions bank) (law-book-collisions book))
    (check-equal (law-book-collisions book) (+ (length (law-book-laws book)) (law-book-instances book)))
    ;; every kept law is true, and rewrites its later side to its earlier side
    (check (every (lambda (law) (eq :certified (certify-equation (law-lhs law) (law-rhs law))))
                  (law-book-laws book)))
    (check (every (lambda (law) (term< (law-rhs law) (law-lhs law))) (law-book-laws book)))
    ;; what the store knows: two terms are equal on the space exactly when they share a class
    (flet ((same-class (a b)
             (let ((ca (term-class bank (field-term a 3))) (cb (term-class bank (field-term b 3))))
               (and ca (eq ca cb)))))
      (check (same-class '(+ x1 x0) '(+ x0 x1)))
      (check (same-class '(* (* x0 x1) x2) '(* x0 (* x1 x2))))
      (check (same-class '(* x0 (+ x1 x2)) '(+ (* x0 x1) (* x0 x2))) "distributivity")
      (check (same-class '(+ x0 (+ x0 x0)) 0))
      (check (not (same-class '(+ x0 x1) '(* x0 x1)))))
    ;; the kept laws rewrite an instance of a law to its normal form
    (check (derivable-p (field-term '(+ (* x1 x2) 0) 3) (field-term '(* x1 x2) 3) (law-book-rules book)))
    (check (derivable-p (field-term '(* x2 x1) 3) (field-term '(* x1 x2) 3) (law-book-rules book)))))

(deftest test-certificates-lapse
  ;; a law about a library function is certified under that function's definition
  (define-function 'twice (list 'x0) (list (gf 3)) '(+ x0 x0))
  (let ((law (make-law (field-term '(twice x0) 3) (field-term '(+ x0 x0) 3))))
    (check-equal :certified (certify-law law))
    (check (certificate-current-p (law-certificate law)))
    (check (licenses-elimination-p (law-certificate law)))
    (check-equal '(twice +) (mapcar #'car (certificate-dependencies (law-certificate law))))
    ;; defining the function again makes the certificate lapse, with no flag to remember to clear
    (define-function 'twice (list 'x0) (list (gf 3)) '(* x0 x0))
    (check (not (certificate-current-p (law-certificate law))))
    (check (not (licenses-elimination-p (law-certificate law)))))
  ;; a refuted law gets no certificate, and an observed one never licenses elimination
  (let ((law (make-law (field-term '(* x0 x0) 3) (field-term 'x0 3))))
    (check-equal :refuted (certify-law law))
    (check (null (law-certificate law))))
  (check (not (licenses-elimination-p (attest :tested :sampled (field-term '(+ x0 x1) 3)))))
  ;; a solver certified on its whole domain carries a certificate too
  (let ((solver (reorient '* (list (gf 5) (gf 5)) 0 :op-names '(+ - * / = if) :constants `((,(gf 5) 0 1)))))
    (certify-solver solver)
    (check (licenses-elimination-p (solver-certificate solver)))))

(deftest test-term-order
  (let ((terms (mapcar (lambda (s) (field-term s 3))
                       '(x0 x1 0 (+ x0 x1) (+ x1 x0) (* x0 x1) (+ x0 (* x1 x2)) (* (+ x0 x1) x2)))))
    ;; a strict total order: exactly one of a < b, b < a, a = b
    (dolist (a terms)
      (dolist (b terms)
        (check-equal 1 (count t (list (term< a b) (term< b a) (eq a b))))))
    (check (term< (field-term 'x2 3) (field-term '(+ x0 x0) 3)) "fewer nodes first")))

(deftest test-reorientation-on-a-field
  ;; the eight arithmetic solvers, from each operator's own table (plan section 8.2; gate X2)
  (let ((type (gf 5)) (expected '((+ 0 (- c k)) (+ 1 (- c k)) (- 0 (+ k c)) (- 1 (- k c))
                                  (* 0 (/ c k)) (* 1 (/ c k)) (/ 0 (* k c)) (/ 1 (/ k c)))))
    (loop for (name position answer) in expected
          do (let* ((solver (reorient name (list type type) position
                                      :op-names '(+ - * / = if) :constants `((,type 0 1))))
                    (report (and (solver-guard solver) (certify-solver solver))))
               (check-equal answer (and (solver-answer solver) (term->sexp (solver-answer solver)))
                            (format nil "~a, argument ~d" name position))
               (check (getf report :sound))
               (check (getf report :exact) "the two guards hold exactly where one solution exists")
               (check-equal :certified (solver-grade solver))))))

(deftest test-reorientation-on-integers
  (flet ((range (lo hi) (loop for v from lo to hi collect v)))
    (let ((inner (range -6 6)) (wide (range -12 12)) (scope '(+ - * / mod < = if)))
      ;; c = u * k: the answer is c / k, and the replay guard is divisibility
      (let* ((s (reorient '* '(:int :int) 0 :ranges (list wide inner) :inner inner
                          :op-names scope :constants '((:int 0 1)) :max-size 7))
             (guard (solver-guard s)))
        (check-equal '(/ c k) (term->sexp (solver-answer s)))
        (check-equal t (values (run-term guard '((k . 3) (c . 12)))))
        (check-equal nil (values (run-term guard '((k . 3) (c . 13)))) "3 does not divide 13")
        (check-equal nil (values (run-term guard '((k . 0) (c . 0)))) "a replay that fails is false")
        (check (solver-unique-guard s))
        (let ((report (check-solver s (list (range -400 400) (range -9 9)) (range -40 40))))
          (check (getf report :sound))
          (check (getf report :exact))))
      ;; c = u / k with truncating division: a solution is u = k * c, unique only when k is 1 or -1
      (let ((s (reorient '/ '(:int :int) 0 :ranges (list wide inner) :inner inner
                         :op-names scope :constants '((:int 0 1)) :max-size 7)))
        (check-equal '(* k c) (term->sexp (solver-answer s)))
        (check-equal 1/6 (solver-share s))
        (let ((report (check-solver s (list (range -400 400) (range -9 9)) (range -40 40))))
          (check (getf report :sound))
          (check (getf report :complete))
          (check (getf report :exact))))
      ;; a boundary creates false dependencies: without the wider range, u looks determined by
      ;; (k, c) more often than it is
      (let ((narrow (reorient '/ '(:int :int) 0 :ranges (list inner inner)
                              :op-names scope :constants '((:int 0 1)) :max-size 3 :budget 1000)))
        (check (> (solver-share narrow) 1/6)))
      ;; mod has no inverse in its first argument
      (let ((s (reorient 'mod '(:int :int) 0 :ranges (list wide inner) :inner inner
                         :op-names scope :constants '((:int 0 1)) :max-size 5)))
        (check-equal 0 (solver-share s))
        (check (null (solver-answer s)))))))

(deftest test-reorientation-of-terms
  ;; the two composite cases of plan section 10, risk 2
  (flet ((range (lo hi) (loop for v from lo to hi collect v)))
    (let ((env '((a . :int) (b . :int) (x . :int))) (inner (range -4 4)) (wide (range -8 8)))
      (let ((s (reorient-term (parse-term '(+ (* a x) b) env) (var 'x :int)
                              :ranges (list inner wide inner) :inner inner
                              :op-names '(+ - * / = if) :constants '((:int 0 1)) :max-size 7
                              :budget 50000000)))
        (check-equal '(/ (- c b) a) (term->sexp (solver-answer s)))
        (check (getf (check-solver s (list (range -5 5) (range -60 60) (range -5 5)) (range -20 20))
                     :exact)))
      (let ((s (reorient-term (parse-term '(+ x x) env) (var 'x :int)
                              :ranges (list wide) :inner inner
                              :op-names '(+ - * / = if) :constants '((:int 0 1)) :max-size 7)))
        (check-equal '(/ c (+ 1 1)) (term->sexp (solver-answer s)))
        (check-equal 1 (solver-share s))
        (check-equal nil (values (run-term (solver-guard s) '((c . 7)))) "an odd number is not x + x")
        (check (getf (check-solver s (list (range -60 60)) (range -30 30)) :exact))))))
