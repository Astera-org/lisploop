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
        ((:+ :*)
         (assert (or (eq type :int) (and (consp type) (eq (first type) :gf))))
         (signature (list type type) type))
        (:= (signature (list type type) :bool))
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

;;; The codec uses only integers and lists, hence ASCII, no packages or reader
;;; state. Numeric tags and operator allocation are fixed by this file.
(defparameter +operator-names+ '(:+ :* := :tuple :member :lookup :gather))

(defun encode-type (type)
  (case type
    (:int 0) (:bool 1) (:index 2)
    (otherwise
     (case (first type)
       (:gf (list 3 (second type)))
       (:tuple (cons 4 (mapcar #'encode-type (rest type))))
       (:seq (list 5 (encode-type (second type))))
       (:fn (list 6 (mapcar #'encode-type (second type))
                  (encode-type (third type))))
       (otherwise (error "Unencodable type ~S" type))))))

(defun decode-type (code)
  (if (integerp code)
      (ecase code (0 :int) (1 :bool) (2 :index))
      (ecase (first code)
        (3 (gf (second code)))
        (4 (cons :tuple (mapcar #'decode-type (rest code))))
        (5 (sequence-type (decode-type (second code))))
        (6 (list :fn (mapcar #'decode-type (second code))
                 (decode-type (third code)))))))

(defun code-value (value type decode-p)
  (cond
    ((eq type :bool)
     (if decode-p (ecase value (0 nil) (1 t)) (if value 1 0)))
    ((and (consp type) (eq (first type) :tuple))
     (mapcar (lambda (v ty) (code-value v ty decode-p)) value (rest type)))
    ((and (consp type) (eq (first type) :seq))
     (mapcar (lambda (v) (code-value v (second type) decode-p)) value))
    (t value)))

(defun encode-expression (expression)
  (ecase (first expression)
    (:lit (list 0 (encode-type (second expression))
                (code-value (third expression) (second expression) nil)))
    (:var (list 1 (second expression) (encode-type (third expression))))
    (:app (list 2 (encode-expression (second expression))
                (mapcar #'encode-expression (third expression))))
    (:op (list 3 (position (second expression) +operator-names+)
               (encode-type (third expression))))
    (:hole (list 4 (second expression) (encode-type (third expression))))))

(defun decode-expression (code)
  (assert (and (listp code) (= (length code) 3)))
  (ecase (first code)
    (0 (let ((type (decode-type (second code))))
         (lit type (code-value (third code) type t))))
    (1 (var (second code) (decode-type (third code))))
    (2 (apply #'app (decode-expression (second code))
              (mapcar #'decode-expression (third code))))
    (3 (op (or (nth (second code) +operator-names+) (error "Invalid opcode"))
           (decode-type (third code))))
    (4 (hole (second code) (decode-type (third code))))))

(defun canonical-data-string (data)
  (with-output-to-string (stream)
    (labels ((emit (x)
               (cond ((integerp x) (format stream "~D" x))
                     ((listp x)
                      (write-char #\( stream)
                      (loop for tail on x do
                        (emit (first tail))
                        (when (rest tail) (write-char #\Space stream)))
                      (write-char #\) stream))
                     (t (error "Noncanonical data ~S" x)))))
      (emit data))))

(defun canonical-string (expression)
  (canonical-data-string (encode-expression expression)))

(defun description-size (expression) (length (canonical-string expression)))

(defun read-model (string inputs)
  "Decode only our numeric grammar, with reader execution and dispatch disabled."
  (assert (every (lambda (c) (find c "0123456789- ()")) string))
  (let ((*read-eval* nil) (*read-base* 10) (*readtable* (copy-readtable nil)))
    (multiple-value-bind (code end) (read-from-string string)
      (assert (= end (length string)))
      (let ((expression (decode-expression code)))
        (expression-type expression inputs)
        (assert (string= string (canonical-string expression)))
        expression))))
