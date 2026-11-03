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
    :code-subst :code-total :code-less))

(defparameter +operator-names+
  (append '(:+ :* := :tuple :member :lookup :gather :- :/ :if :concat) *symbolic-primitives* '(:at)))

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
  (let ((index (or (position name +operator-names+) (error "Unknown operator ~S" name))))
    (+ 4 (if (>= index 15) (positive-bit-size (- index 14)) 0))))

(defun operator-bit-size (name type)
  (+ (operator-name-bit-size name)
     (case name
       ((:= :member :at) (type-bit-size type))
       (:lookup (type-bit-size (second type)))
       (otherwise (if (member name *symbolic-primitives*) (type-bit-size type) 0)))))

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
      (otherwise
       (if (member name *symbolic-primitives*)
           (symbolic-operator-signature name type)
           (error "Unknown primitive ~S" name))))))

;;; Homoiconic AST constructors:
;;; - Applications are native S-expressions `(op arg1 arg2 ...)`
;;; - Compound/typed literals are quoted `'(quote val)` (which prints as `'val`)
;;; - Variables (`x0`, `x1`), operators (`+`, `*`), and holes (`?0`, `?1`) are pooled
;;;   symbols carrying O(1) `ast-meta` in `*node-meta*`.

(defun canonical-op-name (name)
  (if (keywordp name) name (intern (symbol-name name) :keyword)))

(defun op (name type)
  "Construct a monomorphic operator symbol that prints cleanly (e.g. +, *, =)."
  (let* ((kname (canonical-op-name name))
         (norm-type (if (eq kname :at) (normalize-at-container-type type) type))
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
                                             (and m (eq :op (ast-meta-kind m)) (eq :tuple (ast-meta-id m)))))
                                      (< idx (length (rest container-arg))))
                                     (t nil))))))
                  ((:lookup :gather :code-child :code-operator :code-bind) nil)
                  (:if (and (ast-meta-total-p (first child-metas))
                            (if (eq :lit (ast-meta-kind (first child-metas)))
                                (ast-meta-total-p (if (ast-meta-value (first child-metas))
                                                      (second child-metas)
                                                      (third child-metas)))
                                (and (ast-meta-total-p (second child-metas))
                                     (ast-meta-total-p (third child-metas))))))
                  (otherwise (every #'ast-meta-total-p child-metas)))))
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
