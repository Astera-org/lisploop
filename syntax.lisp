(in-package #:lisploop)

;;; Trees and values are ordinary S-expressions, treated as immutable. There is
;;; deliberately no Lisp EVAL, host callback, global store, or closure in a model.

(defun gf (p)
  "Construct a prime-field type; composite moduli are not silently fields."
  (assert (and (integerp p) (>= p 2)
               (loop for d from 2 to (isqrt p) never (zerop (mod p d)))))
  (list :gf p))

(defun tuple-type (&rest types) (cons :tuple types))
(defun sequence-type (type) (list :seq type))

(defun valid-type-p (type)
  (or (member type '(:int :bool :index))
      (and (consp type)
           (case (first type)
             (:gf (and (= (length type) 2) (integerp (second type))
                       (>= (second type) 2)
                       (equal type (gf (second type)))))
             (:tuple (every #'valid-type-p (rest type)))
             (:seq (and (= (length type) 2) (valid-type-p (second type))))))))

(defun value-p (value type)
  "Values carry their domain through the surrounding typed syntax/schema."
  (case type
    (:int (integerp value))
    (:index (and (integerp value) (not (minusp value))))
    (:bool (or (eq value t) (null value)))
    (otherwise
     (and (consp type)
          (case (first type)
            (:gf (and (integerp value) (<= 0 value) (< value (second type))))
            (:tuple (and (listp value) (= (length value) (length (rest type)))
                         (every #'value-p value (rest type))))
            (:seq (and (listp value)
                       (every (lambda (v) (value-p v (second type))) value))))))))

(defun lit (type value)
  (assert (and (valid-type-p type) (value-p value type)))
  (list :lit type (copy-tree value)))

(defun var (id type)
  (assert (and (integerp id) (not (minusp id)) (valid-type-p type)))
  (list :var id type))

(defun hole (id type) (list :hole id type))

(defun operator-type (operator)
  (assert (and (listp operator) (= (length operator) 3)
               (eq (first operator) :op)))
  (destructuring-bind (tag name type) operator
    (declare (ignore tag))
    (assert (valid-type-p type))
    (flet ((signature (inputs output) (list :fn inputs output)))
      (case name
        ((:+ :* :- :/)
         (assert (or (eq type :int) (and (consp type) (eq (first type) :gf))))
         (signature (list type type) type))
        (:= (signature (list type type) :bool))
        (:if (signature (list :bool type type) type))
        (:tuple
         (assert (and (consp type) (eq (first type) :tuple)))
         (signature (rest type) type))
        (:member (signature (list type (sequence-type type)) :bool))
        (:lookup
         (assert (and (consp type) (eq (first type) :tuple) (= (length type) 3)))
         (signature (list (second type) (sequence-type type)) (third type)))
        (:gather (signature (list (sequence-type type) (sequence-type :index))
                            (sequence-type type)))
        (otherwise (error "Unknown primitive ~S" name))))))

(defun op (name type)
  "A monomorphic operator symbol. TYPE fixes its entire signature."
  (let ((operator (list :op name type)))
    (operator-type operator)
    operator))

(defun app (operator &rest arguments) (list :app operator arguments))

(defun expression-type (expression &optional inputs (allow-holes nil))
  "Check syntax and variable availability, returning its monomorphic type."
  (assert (consp expression))
  (case (first expression)
    (:lit
     (assert (= (length expression) 3))
     (assert (and (valid-type-p (second expression))
                  (value-p (third expression) (second expression))))
     (second expression))
    (:var
     (assert (= (length expression) 3))
     (let ((binding (assoc (second expression) inputs)))
       (assert (and binding (equal (cdr binding) (third expression))))
       (third expression)))
    (:hole
     (assert (and allow-holes (= (length expression) 3)))
     (third expression))
    (:app
     (assert (= (length expression) 3))
     (let* ((operator (second expression))
            (signature (if (and allow-holes (eq (first operator) :hole))
                           (third operator) (operator-type operator)))
            (actual (mapcar (lambda (e) (expression-type e inputs allow-holes))
                            (third expression))))
       (assert (and (eq (first signature) :fn)
                    (equal actual (second signature))))
       (third signature)))
    (otherwise (error "Not an expression: ~S" expression))))

(defun instantiate (tree substitutions &optional (tag :hole))
  "Simultaneous substitution; inserted trees are not recursively substituted."
  (cond
    ((atom tree) tree)
    ((eq (first tree) tag)
     (let ((entry (assoc (second tree) substitutions)))
       (if entry (copy-tree (cdr entry)) tree)))
    ((eq (first tree) :lit) tree)
    (t (mapcar (lambda (x) (instantiate x substitutions tag)) tree))))
