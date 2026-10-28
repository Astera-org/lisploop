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

(defun valid-inputs-p (inputs)
  (and (listp inputs) (= (length inputs) (length (remove-duplicates inputs :key #'car)))
       (every (lambda (input) (and (consp input) (integerp (car input)) (<= 0 (car input))
                                   (valid-type-p (cdr input)))) inputs)))

(defun function-sort-p (sort) (and (consp sort) (eq :fn (first sort))))

(defun valid-sort-p (sort)
  (if (function-sort-p sort)
      (and (= 3 (length sort)) (listp (second sort))
           (every #'valid-type-p (second sort)) (valid-type-p (third sort)))
      (valid-type-p sort)))

(defun code-type (inputs sort)
  "Quoted typed syntax in an explicit free-variable scope; never an executable closure."
  (assert (and (valid-inputs-p inputs) (valid-sort-p sort)))
  (list :code (copy-tree inputs) (copy-tree sort)))

(defun code-type-p (type) (and (consp type) (eq :code (first type))))
(defun code-inputs (type) (second type))
(defun code-sort (type) (third type))

(defparameter *symbolic-primitives*
  '(:code-kind :code-child :code-operator :code-apply :code-match :code-bind
    :code-subst :code-total :code-less))

(defun valid-type-p (type)
  (or (member type '(:int :bool))
      (and (consp type)
           (case (first type)
             (:gf (and (= (length type) 2) (integerp (second type))
                       (>= (second type) 2)
                       (equal type (gf (second type)))))
             (:tuple (every #'valid-type-p (rest type)))
             (:seq (and (= (length type) 2) (valid-type-p (second type))))
             (:code (and (= 3 (length type)) (valid-inputs-p (code-inputs type))
                         (valid-sort-p (code-sort type))))))))

(defun value-p (value type)
  "Values carry their domain through the surrounding typed syntax/schema."
  (case type
    (:int (integerp value))
    (:bool (or (eq value t) (null value)))
    (otherwise
     (and (consp type)
          (case (first type)
            (:gf (and (integerp value) (<= 0 value) (< value (second type))))
            (:tuple (and (listp value) (= (length value) (length (rest type)))
                         (every #'value-p value (rest type))))
            (:seq (and (listp value)
                       (every (lambda (v) (value-p v (second type))) value)))
            (:code (handler-case
                       (equal (code-sort type)
                              (if (function-sort-p (code-sort type)) (operator-type value)
                                  (expression-type value (code-inputs type))))
                     (error () nil))))))))

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
        (:gather (signature (list (sequence-type type) (sequence-type :int))
                            (sequence-type type)))
        (:concat (signature (list (sequence-type (sequence-type type))) (sequence-type type)))
        (otherwise (if (member name *symbolic-primitives*) (symbolic-operator-type name type)
                       (error "Unknown primitive ~S" name)))))))

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
  "Simultaneous AST substitution; literals and type metadata are boundaries."
  (cond
    ((atom tree) tree)
    ((eq (first tree) tag)
     (let ((entry (assoc (second tree) substitutions)))
       (if entry (copy-tree (cdr entry)) tree)))
    ((eq (first tree) :app)
     (apply #'app (instantiate (second tree) substitutions tag)
            (mapcar (lambda (x) (instantiate x substitutions tag)) (third tree))))
    (t tree)))
