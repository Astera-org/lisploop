(in-package #:lisploop2)

;;; The prefix code for terms, and the description length it gives.
;;;
;;; The design is v1's (v1/codec.lisp; plan section 9, "Prefix codec, as design"). The size of a
;;; program is found by running the encoder as a counter that only adds up bits. Decoding is
;;; directed by types: both sides know the variables in scope and the type the term must have,
;;; so nothing that can be inferred is written. The decoder rejects any code that is not the
;;; canonical one, so each program has exactly one code. The prices are this file's own; v1's
;;; were not kept.
;;;
;;; A term is written as a two-bit tag and then:
;;;   variable   its index among the variables of the expected type that are in scope
;;;   constant   its value, by type
;;;   application  the operator's index in the list of operator names; the overload, when the
;;;              name has several; each type variable that the expected result type does not
;;;              fix; then the arguments, each at its now known type
;;;   lambda     its body; the parameter types are known from the expected type
;;;
;;; Bound variables are written by position, so their names cost nothing. The decoder names the
;;; parameters V0, V1, ... by depth of binding; CANONICAL-TERM gives any term those names.

(defun emit-positive (value emit)
  "Elias-delta code of the positive integer VALUE: about log2 + 2 log2 log2 bits."
  (assert (plusp value))
  (let* ((width (integer-length value)) (length-width (integer-length width)))
    (funcall emit (1- length-width) 0)
    (funcall emit length-width width)
    (funcall emit (1- width) (ldb (byte (1- width) 0) value))))

(defun signed-code (n) "A bijection from the integers to the positive integers." (if (minusp n) (* -2 n) (1+ (* 2 n))))
(defun signed-decode (k) (if (evenp k) (- (/ k 2)) (/ (1- k) 2)))

(defun index-width (count) "Bits to name one of COUNT things." (integer-length (max 0 (1- count))))

(defun operator-names ()
  "The names of all defined operators, in a fixed order. An operator's code is its index here."
  (let ((names '()))
    (maphash (lambda (name defs) (declare (ignore defs)) (push name names)) *opdefs*)
    (sort names #'string< :key #'symbol-name)))

(defun emit-type (type emit)
  (ecase (type-kind type)
    (:int (funcall emit 3 0))
    (:bool (funcall emit 3 1))
    (:gf (funcall emit 3 2) (emit-positive (second type) emit))
    (:tuple (funcall emit 3 3) (emit-positive (length type) emit)
            (dolist (part (rest type)) (emit-type part emit)))
    (:seq (funcall emit 3 4) (emit-type (second type) emit))
    (:fn (funcall emit 3 5) (emit-positive (1+ (length (second type))) emit)
         (dolist (part (second type)) (emit-type part emit))
         (emit-type (third type) emit))))

(defun emit-value (value type emit)
  (ecase (type-kind type)
    (:int (emit-positive (signed-code value) emit))
    (:bool (funcall emit 1 (if value 1 0)))
    (:gf (funcall emit (index-width (second type)) value))
    (:tuple (loop for item in value for part in (rest type) do (emit-value item part emit)))
    (:seq (emit-positive (1+ (length value)) emit)
          (loop for item across value do (emit-value item (second type) emit)))
    (:fn (let ((names (operator-names)))
           (funcall emit (index-width (length names))
                    (or (position (fnval-name value) names)
                        (error "Only a named operator can be written as a function constant")))))))

(defun type-variables (patterns)
  "The type variables of PATTERNS, each once, in order of first appearance."
  (let ((seen '()))
    (labels ((walk (p) (cond ((type-variable-p p) (pushnew p seen))
                             ((consp p) (mapc #'walk p)))))
      (walk patterns))
    (nreverse seen)))

(defun typed-variables (scope type)
  "The variables of SCOPE, a list of variable terms, that have TYPE, in order."
  (remove-if-not (lambda (v) (equal type (term-type v))) scope))

(defun emit-term (term type scope emit)
  "Write TERM, which must have TYPE, given the variables in SCOPE (innermost binding first)."
  (assert (equal type (term-type term)) () "~a does not have type ~s" term type)
  (ecase (term-kind term)
    (:var (let ((choices (typed-variables scope type)))
            (funcall emit 2 0)
            (funcall emit (index-width (length choices))
                     (or (position term choices) (error "The variable ~a is not in scope" term)))))
    (:const (funcall emit 2 1) (emit-value (term-head term) type emit))
    (:app (let* ((op (term-head term)) (def (op-def op)) (names (operator-names))
                 (overloads (gethash (op-name op) *opdefs*))
                 (bindings (match-type (opdef-args def) (op-args op) nil))
                 (fixed (match-type (opdef-res def) type nil)))
            (funcall emit 2 2)
            (funcall emit (index-width (length names)) (position (op-name op) names))
            (funcall emit (index-width (length overloads)) (position def overloads))
            (dolist (v (type-variables (opdef-args def)))
              (unless (assoc v fixed) (emit-type (cdr (assoc v bindings)) emit)))
            (loop for arg in (term-args term) for arg-type in (op-args op)
                  do (emit-term arg arg-type scope emit))))
    (:lam (funcall emit 2 3)
          (emit-term (term-body term) (third type) (append (reverse (term-head term)) scope) emit))))

(defun term-bits (term scope)
  "The description length of TERM in bits, given the variables in SCOPE."
  (let ((bits 0))
    (emit-term term (term-type term) scope (lambda (width value) (declare (ignore value)) (incf bits width)))
    bits))

(defun encode-term (term scope)
  (let ((bits (make-array 0 :element-type 'bit :adjustable t :fill-pointer 0)))
    (emit-term term (term-type term) scope
               (lambda (width value)
                 (loop for index downfrom (1- width) to 0
                       do (vector-push-extend (ldb (byte 1 index) value) bits))))
    (coerce bits 'simple-bit-vector)))

(defun bound-name (depth) (intern (format nil "V~d" depth) '#:lisploop2))

(defun canonical-term (term &optional (depth 0))
  "TERM with the parameters of its lambdas renamed V0, V1, ... by depth of binding."
  (labels ((walk (term depth renaming)
             (ecase (term-kind term)
               (:var (let ((hit (assoc term renaming))) (if hit (cdr hit) term)))
               ((:const :hole) term)
               (:app (app-op (term-head term)
                             (mapcar (lambda (a) (walk a depth renaming)) (term-args term))))
               (:lam (let* ((params (term-head term))
                            (fresh (loop for p in params for k from depth
                                         collect (var (bound-name k) (term-type p)))))
                       (lam fresh (walk (term-body term) (+ depth (length params))
                                        (append (mapcar #'cons params fresh) renaming))))))))
    (walk term depth nil)))

(defun decode-term (bits type scope)
  "The term of TYPE that BITS encodes, given SCOPE. Rejects a truncated code, trailing bits, an
unused code, and any code that is not the one the encoder writes for the decoded term."
  (let ((cursor 0))
    (labels ((take (width)
               (assert (<= (+ cursor width) (length bits)) () "Truncated code")
               (let ((value 0))
                 (dotimes (i width value)
                   (setf value (+ (* 2 value) (sbit bits cursor)))
                   (incf cursor))))
             (positive ()
               (let ((zeros 0))
                 (loop while (zerop (take 1)) do (incf zeros))
                 (let ((width (+ (ash 1 zeros) (take zeros))))
                   (+ (ash 1 (1- width)) (take (1- width))))))
             (read-type ()
               (ecase (take 3)
                 (0 :int) (1 :bool) (2 (gf (positive)))
                 (3 (cons :tuple (loop repeat (1- (positive)) collect (read-type))))
                 (4 (seq-of (read-type)))
                 (5 (let ((args (loop repeat (1- (positive)) collect (read-type))))
                      (fn-type args (read-type))))))
             (read-value (type)
               (ecase (type-kind type)
                 (:int (signed-decode (positive)))
                 (:bool (= 1 (take 1)))
                 (:gf (let ((v (take (index-width (second type)))))
                        (assert (< v (second type)) () "Unused field element") v))
                 (:tuple (mapcar #'read-value (rest type)))
                 (:seq (coerce (loop repeat (1- (positive)) collect (read-value (second type)))
                               'simple-vector))
                 (:fn (let* ((names (operator-names)) (k (take (index-width (length names)))))
                        (assert (< k (length names)) () "Unused operator code")
                        (apply #'primitive-fnval (nth k names) (second type))))))
             (read-term (type scope depth)
               (ecase (take 2)
                 (0 (let* ((choices (typed-variables scope type))
                           (k (take (index-width (length choices)))))
                      (assert (< k (length choices)) () "Unused variable code")
                      (nth k choices)))
                 (1 (const (read-value type) type))
                 (2 (let* ((names (operator-names)) (k (take (index-width (length names)))))
                      (assert (< k (length names)) () "Unused operator code")
                      (let* ((overloads (gethash (nth k names) *opdefs*))
                             (j (take (index-width (length overloads)))))
                        (assert (< j (length overloads)) () "Unused overload code")
                        (let* ((def (nth j overloads))
                               (bindings (match-type (opdef-res def) type nil)))
                          (assert (not (eq bindings :fail)) () "Operator of the wrong type")
                          (dolist (v (type-variables (opdef-args def)))
                            (unless (assoc v bindings)
                              (setf bindings (match-type v (read-type) bindings))
                              (assert (not (eq bindings :fail)) () "Type outside the operator's domain")))
                          (let ((arg-types (substitute-type (opdef-args def) bindings)))
                            (app-op (find-op (opdef-name def) arg-types)
                                    (mapcar (lambda (arg-type) (read-term arg-type scope depth))
                                            arg-types)))))))
                 (3 (assert (fn-type-p type) () "A lambda where no function is expected")
                    (let ((params (loop for p in (second type) for k from depth
                                        collect (var (bound-name k) p))))
                      (lam params (read-term (third type) (append (reverse params) scope)
                                             (+ depth (length params)))))))))
      (let ((term (read-term type scope 0)))
        (assert (= cursor (length bits)) () "Trailing bits")
        (assert (equal bits (encode-term term scope)) () "Not the canonical code")
        term))))
