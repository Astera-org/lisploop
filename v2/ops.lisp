(in-package #:lisploop2)

;;; Operators.
;;;
;;; An operator definition (OPDEF) has a name, a signature that may contain type variables, and a
;;; way to make its cell function once the type variables are known. An operator (OP) is a
;;; definition at one concrete signature: + on :int and + on (:gf 3) are two operators.
;;;
;;; A cell function works on single cells. The store applies it down a column, and the evaluator
;;; applies it at one node. A strict operator's function sees only values: if any argument is a
;;; status, the result is the first such status and the function is not called. IF and TRY are the
;;; two operators that are not strict.
;;;
;;; The primitives are those of v1 (+ * - / mod < = if), the six that build sequences and take
;;; them apart (plan section 7.1, change 3), and TRY and CALL. A primitive may encode the shape of
;;; a container, never the content of a domain.

(defvar *spent* 0
  "Work spent inside cell functions beyond the one unit per application that the caller charges:
the work of the functions a higher-order operator calls, and of a library function's body.")
(declaim (type fixnum *spent*))

(defvar *fuel* most-positive-fixnum
  "The value of *SPENT* past which an evaluation is cut off and yields the out-of-fuel cell.")
(declaim (type fixnum *fuel*))

(defstruct opdef
  name     ; a symbol
  args     ; list of type patterns
  res      ; type pattern
  maker    ; function of the type bindings, returning the cell function
  strict)  ; true when a status argument is passed through without calling the cell function

(defstruct (op (:constructor %make-op))
  id name args res fn (arity 0 :type fixnum) strict def)

(defmethod print-object ((op op) stream)
  (format stream "#<op ~a ~a -> ~a>" (op-name op) (op-args op) (op-res op)))

(defvar *opdefs* (make-hash-table :test 'eq) "name -> list of definitions, one per overload")
(defvar *ops* (make-hash-table :test 'equal) "(name . argument types) -> operator")
(defvar *op-count* 0)
(defvar *definition-versions* (make-hash-table :test 'eq)
  "name -> how many times the operator has been defined. Evidence about a statement records the
versions it was checked under, and lapses when one of them changes (evidence.lisp).")

(defun definition-version (name) (gethash name *definition-versions* 0))

(defun define-op (name args res maker &key (strict t))
  (let ((def (make-opdef :name name :args args :res res :maker maker :strict strict)))
    (incf (gethash name *definition-versions* 0))
    ;; a redefinition replaces the overload with the same signature, and drops its instances
    (setf (gethash name *opdefs*)
          (append (remove-if (lambda (d) (equal (opdef-args d) args)) (gethash name *opdefs*))
                  (list def)))
    (maphash (lambda (key op) (when (eq (op-name op) name) (remhash key *ops*))) *ops*)
    def))

(defun find-op (name arg-types &optional (errorp t))
  "The operator NAME at the concrete argument types ARG-TYPES."
  (or (gethash (cons name arg-types) *ops*)
      (dolist (def (gethash name *opdefs*))
        (when (= (length arg-types) (length (opdef-args def)))
          (let ((bindings (match-type (opdef-args def) arg-types nil)))
            (unless (eq bindings :fail)
              (return (setf (gethash (cons name arg-types) *ops*)
                            (%make-op :id (incf *op-count*) :name name :args arg-types
                                      :res (substitute-type (opdef-res def) bindings)
                                      :fn (funcall (opdef-maker def) bindings)
                                      :arity (length arg-types)
                                      :strict (opdef-strict def) :def def)))))))
      (and errorp (error "No operator ~a at argument types ~s" name arg-types))))

(defun op-instances (names types)
  "Every operator named in NAMES whose argument types can all be drawn from TYPES, closed under
the result types that appear. This is how a bank turns a list of names into operators."
  (let ((types (copy-list types)) (found '()) (changed t))
    (loop while changed do
      (setf changed nil)
      (dolist (name names)
        (dolist (def (or (gethash name *opdefs*) (error "Unknown operator ~a" name)))
          (labels ((fill-args (patterns bindings chosen)
                     (if (null patterns)
                         (let ((op (find-op name (reverse chosen))))
                           (unless (member op found) (push op found) (setf changed t))
                           (unless (member (op-res op) types :test #'equal)
                             (setf types (append types (list (op-res op))) changed t)))
                         (dolist (type types)
                           (let ((b (match-type (first patterns) type bindings)))
                             (unless (eq b :fail)
                               (fill-args (rest patterns) b (cons type chosen))))))))
            (fill-args (opdef-args def) nil nil)))))
    ;; keep the order of NAMES, then of first appearance, so that enumeration order is stable
    (stable-sort (reverse found) #'< :key (lambda (op) (position (op-name op) names)))))

(defmacro defop (name (&rest args) res (&rest lambda-list) &body body)
  "Define a strict operator whose cell function does not depend on the type bindings."
  `(define-op ',name ',args ',res
     (lambda (bindings) (declare (ignore bindings)) (lambda ,lambda-list ,@body))))

;;; --- arithmetic ---

(defun modular-inverse (a p)
  "The inverse of A modulo the prime P, for A not divisible by P."
  (let ((r0 p) (r1 (mod a p)) (s0 0) (s1 1))
    (loop until (zerop r1)
          do (let ((q (floor r0 r1)))
               (psetf r0 r1 r1 (- r0 (* q r1)))
               (psetf s0 s1 s1 (- s0 (* q s1)))))
    (mod s0 p)))

(defun numeric-maker (int-fn)
  "A maker for a two-argument arithmetic operator: INT-FN on the integers, and INT-FN followed by
reduction modulo p on the field of p elements."
  (lambda (bindings)
    (let ((type (cdr (assoc '?n bindings))))
      (if (eq type :int)
          int-fn
          (let ((p (second type)))
            (lambda (a b) (mod (funcall int-fn a b) p)))))))

(define-op '+ '(?n ?n) '?n (numeric-maker #'+))
(define-op '* '(?n ?n) '?n (numeric-maker #'*))
(define-op '- '(?n ?n) '?n (numeric-maker #'-))

;;; Division is truncating on the integers, as in v1, and exact in a field. Division by zero is a
;;; fault in both.
(define-op '/ '(?n ?n) '?n
  (lambda (bindings)
    (let ((type (cdr (assoc '?n bindings))))
      (if (eq type :int)
          (lambda (a b) (if (zerop b) (make-fault '/ (list a b)) (values (truncate a b))))
          (let ((p (second type)))
            (lambda (a b)
              (if (zerop b) (make-fault '/ (list a b)) (mod (* a (modular-inverse b p)) p))))))))

(defop mod (:int :int) :int (a b)
  (if (zerop b) (make-fault 'mod (list a b)) (mod a b)))

(defop < (:int :int) :bool (a b) (< a b))
(defop = (?a ?a) :bool (a b) (cell= a b))

;;; --- the two operators that are not strict ---

(define-op 'if '(:bool ?a ?a) '?a
  (lambda (bindings) (declare (ignore bindings))
    (lambda (g a b) (cond ((status-p g) g) (g a) (t b))))
  :strict nil)

;;; (try e fallback): the value of E, or of FALLBACK where E fails. It lets a guard that was
;;; learned from failures be written in the object language. It applies to faults, not to
;;; running out of fuel (plan section 7.1, change 4).
(define-op 'try '(?a ?a) '?a
  (lambda (bindings) (declare (ignore bindings))
    (lambda (e fallback) (if (fault-p e) fallback e)))
  :strict nil)

;;; --- sequences: three that take them apart, three that build them ---

(defop length ((:seq ?a)) :int (s) (length s))

(defop at ((:seq ?a) :int) ?a (s i)
  (if (and (<= 0 i) (< i (length s))) (svref s i) (make-fault 'at (list s i))))

(defun apply-fn (f &rest args)
  "Apply the function value F. The call itself costs one unit; what F does inside is charged by F."
  (if (> (incf *spent*) *fuel*) *fuel-out* (apply (fnval-fn f) args)))

;;; (tabulate n f): the sequence f(0), f(1), ..., f(n-1).
(defop tabulate (:int (:fn (:int) ?a)) (:seq ?a) (n f)
  (if (minusp n)
      (make-fault 'tabulate (list n))
      (let ((out (make-array n)))
        (dotimes (i n out)
          (let ((v (apply-fn f i)))
            (when (status-p v) (return v))
            (setf (svref out i) v))))))

;;; (fold init f xs): f(... f(f(init, xs[0]), xs[1]) ..., xs[n-1]).
(defop fold (?b (:fn (?b ?a) ?b) (:seq ?a)) ?b (init f xs)
  (let ((acc init))
    (dotimes (i (length xs) acc)
      (setf acc (apply-fn f acc (svref xs i)))
      (when (status-p acc) (return acc)))))

;;; (scan init f xs): every intermediate value of the accumulator of FOLD, as a sequence.
(defop scan (?b (:fn (?b ?a) ?b) (:seq ?a)) (:seq ?b) (init f xs)
  (let ((acc init) (out (make-array (length xs))))
    (dotimes (i (length xs) out)
      (setf acc (apply-fn f acc (svref xs i)))
      (when (status-p acc) (return acc))
      (setf (svref out i) acc))))

;;; (where n f): the positions i below n at which f(i) is true, in increasing order.
(defop where (:int (:fn (:int) :bool)) (:seq :int) (n f)
  (if (minusp n)
      (make-fault 'where (list n))
      (let ((out '()))
        (dotimes (i n (coerce (nreverse out) 'simple-vector))
          (let ((v (apply-fn f i)))
            (when (status-p v) (return v))
            (when v (push i out)))))))

;;; Pairs. A tuple is built by the tuple row of the refinement table and read with LEFT and RIGHT.
(defop tuple (?a ?b) (:tuple ?a ?b) (a b) (list a b))
(defop left ((:tuple ?a ?b)) ?a (pair) (first pair))
(defop right ((:tuple ?a ?b)) ?b (pair) (second pair))

;;; (call f a ...): apply a function-valued input.
(defop call ((:fn (?a) ?r) ?a) ?r (f a) (apply-fn f a))
(defop call ((:fn (?a ?b) ?r) ?a ?b) ?r (f a b) (apply-fn f a b))
