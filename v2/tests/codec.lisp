(in-package #:lisploop2)

;;; The codec's contract (plan section 9): a term decodes to itself, each term has one code, and
;;; a code that the encoder would not write is rejected.

(defparameter *codec-scope*
  (list (var 'x :int) (var 'y :int) (var 'xs '(:seq :int)) (var 'b :bool)
        (var 'f '(:fn (:int :int) :int))))

(defparameter *codec-terms*
  '((+ x (* y 2))
    (if (< x y) (- y x) 0)
    (if b x -17)
    (= b (< x 1))
    (at xs (mod x (length xs)))
    (try (/ x y) 1000000)
    (call f x (at xs 0))
    (tabulate (length xs) (lambda (v0) (+ (at xs v0) x)))
    (fold 0 (lambda (v0 v1) (+ v0 v1)) xs)
    (scan x (lambda (v0 v1) (call f v0 v1)) xs)
    (where (length xs) (lambda (v0) (< y (at xs v0))))
    (tabulate x (lambda (v0) (fold v0 (lambda (v1 v2) (+ v1 (* v2 v0))) xs)))
    (tabulate x (lambda (v0) (= v0 y)))))

(defun codec-env () (mapcar (lambda (v) (cons (term-head v) (term-type v))) *codec-scope*))

(deftest test-codec-round-trip
  (dolist (sexp *codec-terms*)
    (let* ((term (parse-term sexp (codec-env)))
           (bits (encode-term term *codec-scope*)))
      (check (eq term (canonical-term term)) (format nil "~s is written with canonical names" sexp))
      (check-equal (length bits) (term-bits term *codec-scope*) "the counter and the encoder agree")
      (check (eq term (decode-term bits (term-type term) *codec-scope*))
             (format nil "~s does not decode to itself" sexp)))))

(deftest test-codec-canonical
  (let* ((term (parse-term '(+ x (* y 2)) (codec-env)))
         (bits (encode-term term *codec-scope*)))
    ;; a truncated code and a code with trailing bits are both rejected
    (check (handler-case (progn (decode-term (subseq bits 0 (1- (length bits))) :int *codec-scope*) nil)
             (error () t)))
    (check (handler-case (progn (decode-term (concatenate 'simple-bit-vector bits #*0) :int *codec-scope*) nil)
             (error () t)))
    ;; a term decoded at the wrong type is rejected
    (check (handler-case (progn (decode-term bits :bool *codec-scope*) nil) (error () t))))
  ;; names of bound variables cost nothing, and renaming them gives the canonical term
  (let ((a (parse-term '(tabulate x (lambda (i) (+ i y))) (codec-env)))
        (b (parse-term '(tabulate x (lambda (v0) (+ v0 y))) (codec-env))))
    (check (not (eq a b)))
    (check (eq b (canonical-term a)))
    (check-equal (term-bits a *codec-scope*) (term-bits b *codec-scope*)))
  ;; a larger integer costs more bits, and the cost grows with the logarithm
  (flet ((bits (n) (term-bits (const n :int) nil)))
    (check (< (bits 0) (bits 5) (bits 1000) (bits 1000000)))
    (check (< (bits 1000000) 50)))
  ;; every integer in a range has its own code
  (let ((codes (loop for n from -40 to 40 collect (encode-term (const n :int) nil))))
    (check-equal 81 (length (remove-duplicates codes :test #'equal)))
    (check (loop for n from -40 to 40 for code in codes
                 always (eq (const n :int) (decode-term code :int nil))))))
