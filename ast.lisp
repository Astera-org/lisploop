(in-package #:lisploop)

;;; Module 1: ast.lisp
;;; Homoiconic S-expressions `(op arg1 arg2 ...)`, bidirectional type checking over
;;; schema \Gamma = (domain, inputs, target), and O(1) cached structural metadata.

(defstruct (schema (:constructor %make-schema))
  (domain :int)
  inputs
  target
  (lookup-p nil))

(defstruct ast-meta
  kind            ; :var | :lit | :op | :hole | :app
  id              ; var/hole id or operator name
  type            ; monomorphic type or (:fn arg-types ret-type)
  value           ; literal payload (for :lit)
  (non-var-bits 0 :type fixnum)
  (var-count 0 :type fixnum)
  (syntax-work 0 :type fixnum)
  (total-p nil :type boolean)
  free-vars)

(defvar *node-meta* (make-hash-table :test #'eq :weakness :key)
  "O(1) pointer-keyed metadata table for constructed S-expression nodes and symbols.")

(defvar *typed-symbol-Pool* (make-hash-table :test #'equal)
  "Canonical pool of typed variable, operator, and hole symbols so EQUAL and EQ agree.")

(defun integer-width (value)
  (max 1 (integer-length (abs value))))

(defun gf (p)
  "Construct a prime-field type; composite moduli are rejected."
  (assert (and (integerp p) (>= p 2)
               (loop for d from 2 to (isqrt p) never (zerop (mod p d)))))
  (list :gf p))

(defun tuple-type (&rest types) (cons :tuple types))
(defun sequence-type (type) (list :seq type))

(defun function-sort-p (sort)
  (and (consp sort) (eq :fn (first sort))))

(defun valid-inputs-p (inputs)
  (and (listp inputs)
       (= (length inputs) (length (remove-duplicates inputs :key #'car :test #'equal)))
       (every (lambda (input)
                (and (consp input)
                     (or (and (integerp (car input)) (<= 0 (car input)))
                         (and (symbolp (car input)) (not (null (car input)))))
                     (valid-type-p (cdr input))))
              inputs)))

(defun valid-sort-p (sort)
  (if (function-sort-p sort)
      (and (= 3 (length sort)) (listp (second sort))
           (every #'valid-type-p (second sort)) (valid-type-p (third sort)))
      (valid-type-p sort)))

(defun code-type (inputs sort)
  "Quoted typed syntax in an explicit free-variable scope; never an executable closure."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (assert (and (valid-inputs-p norm-inputs) (valid-sort-p sort)))
    (list :code (copy-tree norm-inputs) (copy-tree sort))))

(defun code-type-p (type) (and (consp type) (eq :code (first type))))
(defun code-inputs (type) (second type))
(defun code-sort (type) (third type))

(defparameter *symbolic-primitives*
  '(:code-kind :code-child :code-operator :code-apply :code-match :code-bind
    :code-subst :code-total :code-less :code-eval))

(defparameter +operator-names+
  '(:+ :* := :tuple :member :lookup :gather :- :/ :if :concat
    :code-kind :code-child :code-operator :code-apply :code-match :code-bind
    :code-subst :code-total :code-less :at
    :cons :tail :length :< :code-eval))

(defstruct (function-definition (:constructor %make-function-definition))
  name
  inputs
  return-type
  code-type
  signature
  body
  oracle-table
  total-p
  conditional-code-params)

(defvar *function-definitions* (make-hash-table :test #'eq))
(defvar *registered-function-names* nil)
(defvar *function-library-version* 0)
(defvar *de-novo-function-counter* 0)

(defun canonical-op-name (name)
  (if (keywordp name) name (intern (symbol-name name) :keyword)))

(defun de-novo-function-name (&optional (index *de-novo-function-counter*))
  "Short alphabetic de novo function symbol in the keyword namespace (:FA, :FB, ..., :FZ, :FAA, ...)."
  (assert (and (integerp index) (not (minusp index))))
  (let ((chars nil)
        (n index))
    (loop
      (multiple-value-bind (q r) (floor n 26)
        (push (code-char (+ (char-code #\A) r)) chars)
        (if (zerop q)
            (return)
            (setf n (1- q)))))
    (intern (concatenate 'string "F" chars) :keyword)))

(defun next-function-name ()
  "Allocate the next unused de novo function keyword symbol (:FA, :FB, ...)."
  (loop
    (let ((candidate (de-novo-function-name *de-novo-function-counter*)))
      (incf *de-novo-function-counter*)
      (unless (or (member candidate +operator-names+)
                  (member candidate *registered-function-names*))
        (return candidate)))))

(defun find-function-definition (name)
  (gethash (canonical-op-name name) *function-definitions*))

(defun defined-function-p (name)
  (not (null (find-function-definition name))))

(defun all-operator-names ()
  (append +operator-names+ *registered-function-names*))

(defun operator-index (name)
  (position (canonical-op-name name) (all-operator-names)))

(defun operator-by-index (index)
  (nth index (all-operator-names)))

(defun homogeneous-tuple-type-p (type)
  "True when TYPE is a non-empty (:tuple tau ... tau) with identical component types."
  (and (consp type) (eq :tuple (first type)) (rest type)
       (every #'valid-type-p (rest type))
       (every (lambda (part) (equal part (second type))) (cddr type))))

(defun normalize-at-container-type (type)
  "Normalize `:at` operand type: accepts `(:seq tau)`, homogeneous `(:tuple tau ... tau)`,
or element type `tau` (normalized to `(:seq tau)`)."
  (assert (valid-type-p type))
  (if (and (consp type) (or (eq :seq (first type)) (homogeneous-tuple-type-p type)))
      type
      (sequence-type type)))

(defun at-container-element-type (type)
  (let ((norm (normalize-at-container-type type)))
    (second norm)))

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

(defun infer-domain-from-types (types)
  (dolist (type types :int)
    (when (and (consp type) (eq :gf (first type)))
      (return type))
    (when (and (consp type) (member (first type) '(:tuple :seq)))
      (let ((sub (infer-domain-from-types (rest type))))
        (unless (eq sub :int) (return sub))))))

(defun make-schema (&key domain inputs (target :int) lookup-p)
  (let ((inferred-domain (or domain
                             (infer-domain-from-types (cons target (mapcar #'cdr inputs))))))
    (%make-schema :domain inferred-domain :inputs (copy-tree inputs)
                  :target (copy-tree target) :lookup-p lookup-p)))

;;; Structural work & bit-size helpers needed at AST construction time

(defun type-work (type)
  "Type-node visits and modulus payloads; independent of printed or compressed lengths."
  (if (atom type) 1
      (1+ (ecase (first type)
            (:gf (integer-width (second type)))
            (:tuple (reduce #'+ (rest type) :key #'type-work :initial-value 0))
            (:seq (type-work (second type)))
            (:code (+ (loop for input in (code-inputs type)
                            sum (+ (integer-width (if (integerp (car input)) (car input) 0))
                                   (type-work (cdr input))))
                      (type-work (code-sort type))))
            (:fn (+ (reduce #'+ (second type) :key #'type-work :initial-value 0)
                    (type-work (third type))))))))

(defun value-work (value type)
  "One visit per value/container plus raw payload bits; independent of the codec."
  (1+ (case type
        (:int (1+ (integer-width value)))
        (:bool 1)
        (otherwise
         (ecase (first type)
           (:gf (integer-width (1- (second type))))
           (:tuple (loop for item in value for part in (rest type) sum (value-work item part)))
           (:seq (loop for item in value sum (value-work item (second type))))
           (:code (syntax-work value)))))))

(defun signed-code (value)
  (if (minusp value) (* -2 value) (1+ (* 2 value))))

(defun decode-signed-code (value)
  (if (oddp value) (/ (1- value) 2) (- (/ value 2))))

(defun positive-bit-size (value)
  (assert (plusp value))
  (let* ((width (integer-length value))
         (length-width (integer-length width)))
    (+ (1- length-width) length-width (1- width))))

(defun type-bit-size (type)
  (case type
    ((:int :bool) 3)
    (otherwise
     (ecase (first type)
       (:gf (+ 3 (positive-bit-size (second type))))
       (:tuple (+ 3 (positive-bit-size (length type))
                  (reduce #'+ (rest type) :key #'type-bit-size :initial-value 0)))
       (:seq (+ 3 (type-bit-size (second type))))
       (:code (+ 3 (inputs-bit-size (code-inputs type)) 1
                 (let ((sort (code-sort type)))
                   (if (function-sort-p sort)
                       (+ (positive-bit-size (1+ (length (second sort))))
                          (reduce #'+ (second sort) :key #'type-bit-size :initial-value 0)
                          (type-bit-size (third sort)))
                       (type-bit-size sort)))))))))

(defun inputs-bit-size (inputs)
  (+ (positive-bit-size (1+ (length inputs)))
     (loop for (id . type) in inputs
           sum (+ (positive-bit-size (1+ (if (integerp id) id 0)))
                  (type-bit-size type)))))

(defun operator-name-bit-size (name)
  (let ((index (or (operator-index name) (error "Unknown operator ~S" name))))
    (+ 4 (if (>= index 15) (positive-bit-size (- index 14)) 0))))

(defun operator-bit-size (name type)
  (+ (operator-name-bit-size name)
     (case name
       ((:= :member :at :length) (type-bit-size type))
       (:lookup (type-bit-size (second type)))
       (otherwise
        (if (or (member name *symbolic-primitives*)
                (member name *registered-function-names*))
            (type-bit-size type)
            0)))))

(defun value-bit-size (value type)
  (case type
    (:int (positive-bit-size (signed-code value)))
    (:bool 1)
    (otherwise
     (ecase (first type)
       (:gf (integer-length (1- (second type))))
       (:tuple (loop for item in value for part in (rest type) sum (value-bit-size item part)))
       (:seq (+ (positive-bit-size (1+ (length value)))
                (loop for item in value sum (value-bit-size item (second type)))))
       (:code (let ((sort (code-sort type)))
                (if (function-sort-p sort)
                    (let ((meta (ensure-ast-meta value)))
                      (+ (operator-name-bit-size (ast-meta-id meta))
                         (type-bit-size (ast-meta-type meta))))
                    (body-size value (code-inputs type)))))))))

;;; Symbolic operator typing

(defun expression-code-p (type)
  (and (code-type-p type) (not (function-sort-p (code-sort type)))))

(defun same-code-scope-p (left right)
  (and (code-type-p left) (code-type-p right) (equal (code-inputs left) (code-inputs right))))

(defun symbolic-operator-signature (name type)
  (flet ((sig (inputs output) (list :fn inputs output)))
    (case name
      (:code-kind (assert (code-type-p type)) (sig (list type) :int))
      (:code-total (assert (expression-code-p type)) (sig (list type) :bool))
      (:code-less (assert (expression-code-p type)) (sig (list type type) :bool))
      (:code-eval
       (assert (expression-code-p type))
       (sig (cons type (mapcar #'cdr (code-inputs type)))
            (code-sort type)))
      ((:code-operator :code-apply)
       (assert (and (code-type-p type) (function-sort-p (code-sort type))))
       (let* ((sort (code-sort type)) (scope (code-inputs type))
              (result (code-type scope (third sort))))
         (if (eq name :code-operator)
             (sig (list result) type)
             (sig (list type (apply #'tuple-type
                                    (mapcar (lambda (arg) (code-type scope arg)) (second sort))))
                  result))))
      (otherwise
       (assert (and (consp type) (eq :tuple (first type)) (member (length type) '(3 4))))
       (let ((a (second type)) (b (third type)) (c (fourth type)))
         (assert (expression-code-p a))
         (ecase name
           (:code-child
            (assert (and (null c) (expression-code-p b) (same-code-scope-p a b)))
            (sig (list a :int) b))
           (:code-match
            (assert (and (null c) (expression-code-p b) (equal (code-sort a) (code-sort b))))
            (sig (list a b) :bool))
           (:code-bind
            (assert (and (expression-code-p b) (expression-code-p c) (same-code-scope-p b c)
                         (equal (code-sort a) (code-sort b))))
            (sig (list a b :int) c))
           (:code-subst
            (assert (and (consp b) (eq :tuple (first b)) (expression-code-p c)
                         (equal (code-sort a) (code-sort c))
                         (= (length (rest b)) (length (code-inputs a)))
                         (every (lambda (binding input)
                                  (and (same-code-scope-p binding c)
                                       (equal (code-sort binding) (cdr input))))
                                (rest b) (code-inputs a))))
            (sig (list a b) c))))))))

(defun compute-operator-signature (name type)
  (assert (valid-type-p type))
  (flet ((sig (inputs output) (list :fn inputs output)))
    (case name
      ((:+ :* :- :/)
       (assert (or (eq type :int) (and (consp type) (eq (first type) :gf))))
       (sig (list type type) type))
      (:<
       (assert (eq type :int))
       (sig '(:int :int) :bool))
      (:= (sig (list type type) :bool))
      (:if (sig (list :bool type type) type))
      (:tuple
       (assert (and (consp type) (eq (first type) :tuple)))
       (sig (rest type) type))
      (:member (sig (list type (sequence-type type)) :bool))
      (:lookup
       (assert (and (consp type) (eq (first type) :tuple) (= (length type) 3)))
       (sig (list (second type) (sequence-type type)) (third type)))
      (:gather (sig (list (sequence-type type) (sequence-type :int)) (sequence-type type)))
      (:at (sig (list type :int) (at-container-element-type type)))
      (:concat (sig (list (sequence-type (sequence-type type))) (sequence-type type)))
      (:cons (sig (list type (sequence-type type)) (sequence-type type)))
      (:tail (sig (list (sequence-type type)) (sequence-type type)))
      (:length (sig (list (sequence-type type)) :int))
      (otherwise
       (cond ((member name *symbolic-primitives*)
              (symbolic-operator-signature name type))
             ((and (expression-code-p type)
                   (member name *registered-function-names*))
              (sig (mapcar #'cdr (code-inputs type)) (code-sort type)))
             (t (error "Unknown primitive ~S" name)))))))

;;; Homoiconic AST constructors:
;;; - Applications are native S-expressions `(op arg1 arg2 ...)`
;;; - Compound/typed literals are quoted `'(quote val)` (which prints as `'val`)
;;; - Variables (`x0`, `x1`), operators (`+`, `*`), and holes (`?0`, `?1`) are pooled
;;;   symbols carrying O(1) `ast-meta` in `*node-meta*`.

(defun normalize-operator-type (kname type)
  (cond ((eq kname :at)
         (normalize-at-container-type type))
        ((defined-function-p kname)
         (let ((def (find-function-definition kname)))
           (cond ((null type) (function-definition-code-type def))
                 ((and (expression-code-p type)
                       (equal type (function-definition-code-type def)))
                  type)
                 ((equal type (function-definition-return-type def))
                  (function-definition-code-type def))
                 (t (error "Incompatible type ~S for function ~S (expected ~S)"
                           type kname (function-definition-code-type def))))))
        (t type)))

(defun op (name &optional type)
  "Construct a monomorphic operator symbol that prints cleanly (e.g. +, *, =, or defined :fa)."
  (let* ((kname (canonical-op-name name))
         (norm-type (normalize-operator-type kname type))
         (sig (compute-operator-signature kname norm-type))
         (key (list :op kname norm-type)))
    (or (gethash key *typed-symbol-pool*)
        (let ((sym (make-symbol (symbol-name kname))))
          (setf (gethash sym *node-meta*)
                (make-ast-meta :kind :op :id kname :type (copy-tree norm-type) :value sig
                               :non-var-bits (+ 2 (operator-bit-size kname norm-type))
                               :var-count 0
                               :syntax-work (1+ (type-work norm-type))
                               :total-p t :free-vars nil)
                (gethash key *typed-symbol-pool*) sym)
          sym))))

(defun operator-p (term)
  (let ((meta (and (symbolp term) (gethash term *node-meta*))))
    (and meta (eq :op (ast-meta-kind meta)))))

(defun operator-name (operator)
  (let ((meta (gethash operator *node-meta*)))
    (assert (and meta (eq :op (ast-meta-kind meta))))
    (ast-meta-id meta)))

(defun operator-operand-type (operator)
  (let ((meta (gethash operator *node-meta*)))
    (assert (and meta (eq :op (ast-meta-kind meta))))
    (ast-meta-type meta)))

(defun operator-type (operator)
  (let ((meta (gethash operator *node-meta*)))
    (assert (and meta (eq :op (ast-meta-kind meta))))
    (ast-meta-value meta)))

(defun application-overhead (operator)
  (let ((meta (gethash operator *node-meta*)))
    (assert (and meta (eq :op (ast-meta-kind meta))))
    (ast-meta-non-var-bits meta)))

(defun var (id type)
  "Construct a typed variable symbol (e.g. X0, X1)."
  (assert (and (integerp id) (not (minusp id)) (valid-type-p type)))
  (let ((key (list :var id type)))
    (or (gethash key *typed-symbol-pool*)
        (let ((sym (make-symbol (format nil "X~D" id))))
          (setf (gethash sym *node-meta*)
                (make-ast-meta :kind :var :id id :type (copy-tree type)
                               :non-var-bits 2 :var-count 1
                               :syntax-work (+ 1 (integer-width id) (type-work type))
                               :total-p t :free-vars (list id))
                (gethash key *typed-symbol-pool*) sym)
          sym))))

(defun hole (id type)
  "Construct a typed pattern hole symbol (e.g. ?0, ?1)."
  (assert (and (integerp id) (not (minusp id)) (valid-sort-p type)))
  (let ((key (list :hole id type)))
    (or (gethash key *typed-symbol-pool*)
        (let ((sym (make-symbol (format nil "?~D" id))))
          (setf (gethash sym *node-meta*)
                (make-ast-meta :kind :hole :id id :type (copy-tree type)
                               :non-var-bits 2 :var-count 0
                               :syntax-work (+ 1 (integer-width id) (type-work type))
                               :total-p t :free-vars nil)
                (gethash key *typed-symbol-pool*) sym)
          sym))))

(defun hole-p (term)
  (let ((meta (and (symbolp term) (gethash term *node-meta*))))
    (and meta (eq :hole (ast-meta-kind meta)))))

(defun value-p (value type)
  "Check whether VALUE belongs to domain/type TYPE."
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
                              (if (function-sort-p (code-sort type))
                                  (operator-type value)
                                  (expression-type value (code-inputs type))))
                     (error () nil))))))))

(defun quote-symbol (type)
  "Return the pooled typed quote head symbol for literal domain TYPE."
  (let ((key (list :quote type)))
    (or (gethash key *typed-symbol-pool*)
        (let ((sym (make-symbol "QUOTE")))
          (setf (gethash sym *node-meta*)
                (make-ast-meta :kind :quote :type (copy-tree type))
                (gethash key *typed-symbol-pool*) sym)
          sym))))

(defun compute-lit-meta (type value)
  (make-ast-meta :kind :lit :type (copy-tree type) :value value
                 :non-var-bits (+ 2 (value-bit-size value type))
                 :var-count 0
                 :syntax-work (+ 1 (type-work type) (value-work value type))
                 :total-p t :free-vars nil))

(defun lit (type value)
  "Construct a literal S-expression `(QUOTE value)` carrying O(1) ast-meta."
  (assert (and (valid-type-p type) (value-p value type)))
  (let* ((copied (copy-tree value))
         (node (list (quote-symbol type) copied)))
    (setf (gethash node *node-meta*) (compute-lit-meta type copied))
    node))

(defun compute-app-meta (operator arguments)
  (let* ((op-meta (ensure-ast-meta operator))
         (sig (if (eq :hole (ast-meta-kind op-meta))
                  (ast-meta-type op-meta)
                  (ast-meta-value op-meta)))
         (child-metas (mapcar #'ensure-ast-meta arguments))
         (op-name (when (eq :op (ast-meta-kind op-meta)) (ast-meta-id op-meta)))
         (total-p
           (and (eq :op (ast-meta-kind op-meta))
                (case op-name
                  (:/ (and (every #'ast-meta-total-p child-metas)
                           (eq :lit (ast-meta-kind (second child-metas)))
                           (not (zerop (ast-meta-value (second child-metas))))))
                  (:at (and (every #'ast-meta-total-p child-metas)
                            (eq :lit (ast-meta-kind (second child-metas)))
                            (let ((idx (ast-meta-value (second child-metas)))
                                  (container-type (ast-meta-type (first child-metas)))
                                  (container-arg (first arguments)))
                              (and (integerp idx) (<= 0 idx)
                                   (cond
                                     ((and (consp container-type) (eq :tuple (first container-type)))
                                      (< idx (length (rest container-type))))
                                     ((eq :lit (ast-meta-kind (first child-metas)))
                                      (< idx (length (ast-meta-value (first child-metas)))))
                                     ((and (consp container-arg) (symbolp (first container-arg))
                                           (let ((m (gethash (first container-arg) *node-meta*)))
                                             (and m (eq :op (ast-meta-kind m))
                                                  (or (and (eq :tuple (ast-meta-id m))
                                                           (< idx (length (rest container-arg))))
                                                      (and (eq :cons (ast-meta-id m))
                                                           (zerop idx))))))
                                      t)
                                     (t nil))))))
                  (:tail (and (every #'ast-meta-total-p child-metas)
                              (let ((seq-meta (first child-metas))
                                    (seq-arg (first arguments)))
                                (or (and (eq :lit (ast-meta-kind seq-meta))
                                         (not (null (ast-meta-value seq-meta))))
                                    (and (consp seq-arg) (symbolp (first seq-arg))
                                         (let ((m (gethash (first seq-arg) *node-meta*)))
                                           (and m (eq :op (ast-meta-kind m)) (eq :cons (ast-meta-id m)))))))))
                  (:code-eval (and (every #'ast-meta-total-p child-metas)
                                   (eq :lit (ast-meta-kind (first child-metas)))
                                   (provably-total-p (ast-meta-value (first child-metas)))))
                  ((:lookup :gather :code-child :code-operator :code-bind) nil)
                  (:if (and (ast-meta-total-p (first child-metas))
                            (if (eq :lit (ast-meta-kind (first child-metas)))
                                (ast-meta-total-p (if (ast-meta-value (first child-metas))
                                                      (second child-metas)
                                                      (third child-metas)))
                                (and (ast-meta-total-p (second child-metas))
                                     (ast-meta-total-p (third child-metas))))))
                  (otherwise
                   (if (defined-function-p op-name)
                       (and (every #'ast-meta-total-p child-metas)
                            (let ((def (find-function-definition op-name)))
                              (and def
                                   (or (function-definition-total-p def)
                                       (and (function-definition-conditional-code-params def)
                                            (every (lambda (param-idx)
                                                     (let ((arg-meta (nth param-idx child-metas)))
                                                       (and arg-meta
                                                            (eq :lit (ast-meta-kind arg-meta))
                                                            (provably-total-p (ast-meta-value arg-meta)))))
                                                   (function-definition-conditional-code-params def)))))))
                       (every #'ast-meta-total-p child-metas))))))
         (free-vars (remove-duplicates
                     (loop for m in child-metas append (copy-list (ast-meta-free-vars m))))))
    (make-ast-meta :kind :app :id op-name :type (third sig)
                   :non-var-bits (+ (if (eq :op (ast-meta-kind op-meta))
                                        (ast-meta-non-var-bits op-meta)
                                        2)
                                    (reduce #'+ child-metas :key #'ast-meta-non-var-bits :initial-value 0))
                   :var-count (reduce #'+ child-metas :key #'ast-meta-var-count :initial-value 0)
                   :syntax-work (+ 1 (ast-meta-syntax-work op-meta)
                                   (reduce #'+ child-metas :key #'ast-meta-syntax-work :initial-value 0))
                   :total-p (not (null total-p))
                   :free-vars free-vars)))

(defun empty-sequence-guard-var-id (condition seq-param-ids)
  "If CONDITION is `(= Xi '())` or `(= '() Xi)` for a sequence parameter Xi, return Xi's id."
  (when (and (app-p condition) (eq := (operator-name (first condition))))
    (let ((lhs (second condition))
          (rhs (third condition)))
      (cond ((and (var-p lhs) (member (ast-id lhs) seq-param-ids :test #'eql)
                  (lit-p rhs) (null (ast-value rhs)))
             (ast-id lhs))
            ((and (var-p rhs) (member (ast-id rhs) seq-param-ids :test #'eql)
                  (lit-p lhs) (null (ast-value lhs)))
             (ast-id rhs))
            (t nil)))))

(defun analyze-function-body-totality (name inputs body)
  "Conservative structural termination & totality check for a function definition.
Returns (values total-p conditional-code-params)."
  (when (null body)
    (return-from analyze-function-body-totality (values nil nil)))
  (let ((seq-param-ids (loop for (id . type) in inputs
                             when (and (consp type) (eq :seq (first type)))
                             collect id))
        (decreasing-param-id nil)
        (code-params nil))
    (labels ((tail-of-var-p (expr var-id)
               (and (app-p expr)
                    (eq :tail (operator-name (first expr)))
                    (var-p (second expr))
                    (eql var-id (ast-id (second expr)))))
             (walk (expr non-empty-vars)
               (let ((kind (ast-kind expr)))
                 (case kind
                   ((:lit :var) t)
                   (:app
                    (let* ((operator (first expr))
                           (op-name (and (operator-p operator) (operator-name operator)))
                           (args (rest expr)))
                      (when (null op-name) (return-from walk nil))
                      (case op-name
                        (:if
                         (destructuring-bind (cond-expr yes-expr no-expr) args
                           (and (walk cond-expr non-empty-vars)
                                (let ((guarded-id (empty-sequence-guard-var-id cond-expr seq-param-ids)))
                                  (if guarded-id
                                      (and (walk yes-expr (remove guarded-id non-empty-vars :test #'eql))
                                           (walk no-expr (adjoin guarded-id non-empty-vars :test #'eql)))
                                      (and (walk yes-expr non-empty-vars)
                                           (walk no-expr non-empty-vars)))))))
                        (:tail
                         (and (walk (first args) non-empty-vars)
                              (or (provably-total-p expr)
                                  (and (var-p (first args))
                                       (member (ast-id (first args)) non-empty-vars :test #'eql)))))
                        (:at
                         (and (every (lambda (a) (walk a non-empty-vars)) args)
                              (or (provably-total-p expr)
                                  (and (var-p (first args))
                                       (member (ast-id (first args)) non-empty-vars :test #'eql)
                                       (lit-p (second args))
                                       (eql 0 (ast-value (second args)))))))
                        (:/
                         (and (every (lambda (a) (walk a non-empty-vars)) args)
                              (lit-p (second args))
                              (not (zerop (ast-value (second args))))))
                        (:code-eval
                         (and (every (lambda (a) (walk a non-empty-vars)) (rest args))
                              (let ((code-arg (first args)))
                                (cond ((and (lit-p code-arg) (provably-total-p (ast-value code-arg)))
                                       t)
                                      ((and (var-p code-arg) (assoc (ast-id code-arg) inputs :test #'eql))
                                       (pushnew (position (ast-id code-arg) inputs :key #'car :test #'eql)
                                                code-params)
                                       t)
                                      (t nil)))))
                        ((:lookup :gather :code-child :code-operator :code-bind)
                         nil)
                        (otherwise
                         (cond ((eq op-name name)
                                (and (every (lambda (a) (walk a non-empty-vars)) args)
                                     (let ((matched-id
                                             (loop for (id . type) in inputs
                                                   for arg in args
                                                   when (and (member id non-empty-vars :test #'eql)
                                                             (tail-of-var-p arg id))
                                                   return id)))
                                       (and matched-id
                                            (or (null decreasing-param-id)
                                                (eql decreasing-param-id matched-id))
                                            (progn (setf decreasing-param-id matched-id) t)))))
                               ((defined-function-p op-name)
                                (and (every (lambda (a) (walk a non-empty-vars)) args)
                                     (let ((callee (find-function-definition op-name)))
                                       (and callee (function-definition-total-p callee)))))
                               (t
                                (every (lambda (a) (walk a non-empty-vars)) args)))))))
                   (otherwise nil)))))
      (if (walk body nil)
          (let ((sorted-params (sort (copy-list code-params) #'<)))
            (values (null sorted-params) sorted-params))
          (values nil nil)))))

(defun refresh-expression-meta (expression)
  "Recompute cached ast-meta bottom-up on EXPRESSION after a function definition update."
  (when (and (consp expression) (symbolp (first expression)))
    (let ((head-meta (gethash (first expression) *node-meta*)))
      (when (and head-meta (member (ast-meta-kind head-meta) '(:op :hole)))
        (dolist (child (rest expression))
          (refresh-expression-meta child))
        (setf (gethash expression *node-meta*)
              (compute-app-meta (first expression) (rest expression))))))
  expression)

(defun declare-function-signature (name inputs return-type)
  "Pre-register a callable function symbol so recursive bodies can construct self-calls."
  (let* ((kname (canonical-op-name name))
         (norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (assert (and (not (member kname +operator-names+))
                 (valid-inputs-p norm-inputs)
                 (valid-type-p return-type)))
    (let* ((ctype (code-type norm-inputs return-type))
           (sig (list :fn (mapcar #'cdr norm-inputs) (copy-tree return-type)))
           (existing (find-function-definition kname)))
      (unless (member kname *registered-function-names*)
        (setf *registered-function-names*
              (append *registered-function-names* (list kname))))
      (let ((def (%make-function-definition
                  :name kname
                  :inputs (copy-tree norm-inputs)
                  :return-type (copy-tree return-type)
                  :code-type ctype
                  :signature sig
                  :body (and existing (function-definition-body existing))
                  :oracle-table (and existing (function-definition-oracle-table existing))
                  :total-p nil
                  :conditional-code-params nil)))
        (setf (gethash kname *function-definitions*) def)
        (op kname ctype)
        def))))

(defun define-function (name inputs return-type body &key oracle-table)
  "Register a homoiconic Lisp function definition (or oracle table) under NAME."
  (let* ((def (declare-function-signature name inputs return-type))
         (kname (function-definition-name def))
         (norm-inputs (function-definition-inputs def))
         (ctype (function-definition-code-type def))
         (self-op (op kname ctype))
         (resolved-body (if (functionp body) (funcall body self-op) body)))
    (when resolved-body
      (assert (equal return-type (expression-type resolved-body norm-inputs))))
    (when oracle-table
      (dolist (entry oracle-table)
        (assert (and (consp entry)
                     (= (length (car entry)) (length norm-inputs))
                     (every (lambda (val spec) (value-p val (cdr spec))) (car entry) norm-inputs)
                     (value-p (cdr entry) return-type)))))
    (let ((copied-body (when resolved-body
                         (let ((tree (copy-tree resolved-body)))
                           (ensure-ast-meta tree)
                           tree))))
      (multiple-value-bind (total-p cond-params)
          (if oracle-table
              (values nil nil)
              (analyze-function-body-totality kname norm-inputs copied-body))
        (setf (function-definition-body def) copied-body
              (function-definition-oracle-table def) (copy-tree oracle-table)
              (function-definition-total-p def) total-p
              (function-definition-conditional-code-params def) cond-params)
        (when copied-body
          (refresh-expression-meta copied-body))
        (incf *function-library-version*)
        def))))

(defun clear-function-definitions ()
  "Remove all dynamically registered function definitions and reset de novo naming."
  (let ((names (copy-list *registered-function-names*)))
    (clrhash *function-definitions*)
    (setf *registered-function-names* nil
          *de-novo-function-counter* 0)
    (dolist (kname names)
      (let ((keys-to-remove nil))
        (maphash (lambda (key sym)
                   (declare (ignore sym))
                   (when (and (consp key) (eq :op (first key)) (eq kname (second key)))
                     (push key keys-to-remove)))
                 *typed-symbol-pool*)
        (dolist (key keys-to-remove)
          (let ((sym (gethash key *typed-symbol-pool*)))
            (remhash key *typed-symbol-pool*)
            (when sym (remhash sym *node-meta*))))))
    (setf *function-library-version* 0)
    nil))

(defun app (operator &rest arguments)
  "Construct a homoiconic application `(op arg1 arg2 ...)` with O(1) cached metadata."
  (let ((op-meta (and (symbolp operator) (gethash operator *node-meta*))))
    (assert (and op-meta (member (ast-meta-kind op-meta) '(:op :hole))))
    (let ((node (cons operator (copy-list arguments))))
      (setf (gethash node *node-meta*) (compute-app-meta operator arguments))
      node)))

(defun ensure-ast-meta (expression)
  (or (gethash expression *node-meta*)
      (when (and (consp expression) (symbolp (first expression)))
        (let ((head-meta (gethash (first expression) *node-meta*)))
          (when head-meta
            (setf (gethash expression *node-meta*)
                  (ecase (ast-meta-kind head-meta)
                    (:quote (compute-lit-meta (ast-meta-type head-meta) (second expression)))
                    ((:op :hole) (compute-app-meta (first expression) (rest expression))))))))
      (error "Not a valid AST node: ~S" expression)))

(defun ast-kind (expression)
  (let ((meta (ignore-errors (ensure-ast-meta expression))))
    (and meta (ast-meta-kind meta))))

(defun ast-id (expression)
  (ast-meta-id (ensure-ast-meta expression)))

(defun ast-type (expression)
  (ast-meta-type (ensure-ast-meta expression)))

(defun ast-value (expression)
  (ast-meta-value (ensure-ast-meta expression)))

(defun var-p (term) (eq :var (ast-kind term)))
(defun lit-p (term) (eq :lit (ast-kind term)))
(defun app-p (term) (eq :app (ast-kind term)))

(defun bool-not (expression)
  (app (op :if :bool) expression (lit :bool nil) (lit :bool t)))

(defun bool-and (left right)
  (app (op :if :bool) left right (lit :bool nil)))

(defun syntax-work (expression)
  "O(1) cached structural AST/type visits and raw payload bits."
  (ast-meta-syntax-work (ensure-ast-meta expression)))

(defun provably-total-p (expression)
  "O(1) cached conservative structural definedness."
  (ast-meta-total-p (ensure-ast-meta expression)))

(defun free-vars (expression)
  "O(1) cached list of free variable IDs."
  (copy-list (ast-meta-free-vars (ensure-ast-meta expression))))

(defun body-size (expression inputs)
  "O(1) expression bit length conditional on a declared schema; used by the enumerator."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (meta (ensure-ast-meta expression)))
    (expression-type expression norm-inputs)
    (+ (ast-meta-non-var-bits meta)
       (* (ast-meta-var-count meta)
          (integer-length (max 0 (1- (length norm-inputs))))))))

(defun expression-type (expression &optional inputs (allow-holes nil))
  "Validate syntax and variable scope, returning the expression's monomorphic type."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
        (meta (ignore-errors (ensure-ast-meta expression))))
    (assert meta () "Not an expression: ~S" expression)
    (ecase (ast-meta-kind meta)
      (:lit
       (assert (and (valid-type-p (ast-meta-type meta))
                    (value-p (ast-meta-value meta) (ast-meta-type meta))))
       (ast-meta-type meta))
      (:var
       (let ((binding (assoc (ast-meta-id meta) norm-inputs)))
         (assert (and binding (equal (cdr binding) (ast-meta-type meta))))
         (ast-meta-type meta)))
      (:hole
       (assert allow-holes)
       (ast-meta-type meta))
      (:app
       (let* ((operator (first expression))
              (args (rest expression))
              (op-meta (ensure-ast-meta operator))
              (sig (if (and allow-holes (eq :hole (ast-meta-kind op-meta)))
                       (ast-meta-type op-meta)
                       (progn
                         (assert (eq :op (ast-meta-kind op-meta)))
                         (ast-meta-value op-meta))))
              (actual (mapcar (lambda (e) (expression-type e norm-inputs allow-holes)) args)))
         (assert (and (eq :fn (first sig)) (equal actual (second sig))))
         (third sig))))))

(defun instantiate (tree substitutions &optional (tag :hole))
  "Simultaneous AST substitution on homoiconic S-expressions; literals are boundaries."
  (let ((meta (ignore-errors (ensure-ast-meta tree))))
    (cond
      ((null meta) tree)
      ((eq (ast-meta-kind meta) tag)
       (let ((entry (assoc (ast-meta-id meta) substitutions)))
         (if entry (cdr entry) tree)))
      ((eq (ast-meta-kind meta) :app)
       (let ((new-op (instantiate (first tree) substitutions tag))
             (new-args (mapcar (lambda (x) (instantiate x substitutions tag)) (rest tree))))
         (if (and (eq new-op (first tree))
                  (every #'eq new-args (rest tree)))
             tree
             (apply #'app new-op new-args))))
      (t tree))))
