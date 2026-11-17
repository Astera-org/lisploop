(in-package #:lisploop)

;;; Module 1: ast.lisp
;;; Homoiconic S-expressions `(op arg1 arg2 ...)`, bidirectional type checking over
;;; schema \Gamma = (domain, inputs, target), and O(1) cached structural metadata.

(defstruct (schema (:constructor %make-schema))
  (domain :int)
  inputs
  target
  (lookup-p nil)
  ;; Optional availability preorder: ((input-id . rank) ...), the rank of the target, and
  ;; optional DAG order pairs ((low . high) ...). A model of the target may read only inputs
  ;; whose rank strictly precedes the target's (`rank-lt-p`): an input at the target's own
  ;; rank, later, or incomparable is withheld. An input without an explicit rank has rank
  ;; `:bottom`, which precedes every other rank. Nothing here names what a column means.
  (availability nil)
  (target-availability nil)
  (availability-order nil))

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

(declaim (inline node-meta))
(defun node-meta (node)
  "The metadata cached for NODE, or nil. A pooled symbol carries its own on its property
list, which costs no table lookup; a cons has its in `*node-meta*`."
  (if (symbolp node) (get node 'ast-meta) (gethash node *node-meta*)))

(defun (setf node-meta) (meta node)
  (if (symbolp node)
      (setf (get node 'ast-meta) meta)
      (setf (gethash node *node-meta*) meta)))

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

(defun input-alist (inputs)
  "The ordered (id . type) list of INPUTS, which may be a schema or already such a list."
  (if (schema-p inputs) (schema-inputs inputs) inputs))

(defun lex< (a b &rest keys)
  "Lexicographic order on A and B: the first key on which they differ decides.
A key is a function whose value is minimised, or (:desc function) to maximise it."
  (dolist (key keys nil)
    (let* ((descending (and (consp key) (eq :desc (first key))))
           (function (if descending (second key) key))
           (x (funcall function a))
           (y (funcall function b)))
      (unless (= x y)
        (return (if descending (> x y) (< x y)))))))

(defun best-by (items &rest keys)
  "The earliest element of ITEMS that is minimal under LEX< with KEYS, or nil."
  (let ((best (first items)))
    (dolist (item (rest items) best)
      (when (apply #'lex< item best keys)
        (setf best item)))))

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
  (let ((norm-inputs (input-alist inputs)))
    (assert (and (valid-inputs-p norm-inputs) (valid-sort-p sort)))
    (list :code (copy-tree norm-inputs) (copy-tree sort))))

(defun code-type-p (type) (and (consp type) (eq :code (first type))))
(defun seq-type-p (type) (and (consp type) (eq :seq (first type))))
(defun gf-type-p (type) (and (consp type) (eq :gf (first type))))
(defun tuple-type-p (type) (and (consp type) (eq :tuple (first type))))
(defun code-inputs (type) (second type))
(defun code-sort (type) (third type))

(defparameter +primitives+
  '((:+ ?n (?n ?n) ?n)
    (:* ?n (?n ?n) ?n)
    (:= ?t (?t ?t) :bool)
    (:tuple ?t _ ?t)
    (:member ?t (?t (:seq ?t)) :bool)
    (:lookup (:tuple ?k ?v) (?k (:seq (:tuple ?k ?v))) ?v)
    (:gather ?t ((:seq ?t) (:seq :int)) (:seq ?t))
    (:- ?n (?n ?n) ?n)
    (:/ ?n (?n ?n) ?n)
    (:if ?t (:bool ?t ?t) ?t)
    (:concat ?t ((:seq (:seq ?t))) (:seq ?t))
    (:code-kind ?c (?c) :int)
    (:code-child ?t (_ :int) _)
    (:code-operator ?t (_) _)
    (:code-apply ?t (?t _) _)
    (:code-match ?t (_ _) :bool)
    (:code-bind ?t (_ _ :int) _)
    (:code-subst ?t (_ _) _)
    (:code-total ?e (?e) :bool)
    (:code-less ?e (?e ?e) :bool)
    (:at ?t (?t :int) _)
    (:cons ?t (?t (:seq ?t)) (:seq ?t))
    (:tail ?t ((:seq ?t)) (:seq ?t))
    (:length ?t ((:seq ?t)) :int)
    (:< :int (:int :int) :bool)
    (:code-eval ?t (?t . _) _))
  "Every primitive operator, in opcode order, as (name parameter argument-types result-type).
The last three are patterns over type variables, the parameter being the type an operator
symbol carries. ?n stands for :int or a prime field, ?c for a code type, ?e for the code
type of an expression, and any other variable for any type. The wildcard _ marks a part
that no pattern can express; `compute-operator-signature` computes such a row's signature.")

(defparameter +operator-names+ (mapcar #'first +primitives+))

(defun primitive-pattern (name)
  "The (parameter argument-types result-type) patterns of primitive NAME, or nil."
  (rest (assoc name +primitives+)))

(defun pattern-variables (pattern)
  "The distinct variables of a type PATTERN, the wildcard included."
  (cond ((consp pattern)
         (union (pattern-variables (car pattern)) (pattern-variables (cdr pattern))))
        ((or (null pattern) (keywordp pattern)) nil)
        (t (list pattern))))

(defun signature-pattern (name)
  "The patterns of primitive NAME if they express its whole signature, else nil."
  (let ((pattern (primitive-pattern name)))
    (unless (member '_ (pattern-variables pattern)) pattern)))

(defun match-type-pattern (pattern type &optional bindings)
  "Extend BINDINGS, an alist from the variables of PATTERN to types, so that PATTERN
matches TYPE. It is an error if they cannot match."
  (cond ((eq pattern '_) bindings)
        ((consp pattern)
         (assert (consp type))
         (match-type-pattern (cdr pattern) (cdr type)
                             (match-type-pattern (car pattern) (car type) bindings)))
        ((or (null pattern) (keywordp pattern)) (assert (eq pattern type)) bindings)
        ((assoc pattern bindings) (assert (equal type (cdr (assoc pattern bindings)))) bindings)
        (t (assert (case pattern
                     (?n (or (eq type :int) (gf-type-p type)))
                     (?c (code-type-p type))
                     (?e (expression-code-p type))
                     (otherwise t)))
           (acons pattern type bindings))))

(defun encoded-variable (name)
  "The variable in the parameter of primitive NAME that the result type of an application
does not determine, or nil. The codec emits the type bound to it after the opcode."
  (let* ((pattern (primitive-pattern name))
         (free (set-difference (pattern-variables (first pattern))
                               (pattern-variables (third pattern)))))
    (assert (null (rest free)))
    (first free)))

(defun operator-encoded-type (name type)
  "The part of TYPE, the parameter of operator NAME, that is emitted in the bitstream, or nil."
  (let ((variable (encoded-variable name)))
    (and variable
         (cdr (assoc variable (match-type-pattern (first (primitive-pattern name)) type))))))

(defun operator-decoded-type (name result read-type)
  "The inverse of `operator-encoded-type`: the parameter of operator NAME in an application
of type RESULT, calling READ-TYPE for the part that was emitted."
  (let ((pattern (primitive-pattern name))
        (variable (encoded-variable name)))
    (if pattern
        (sublis (match-type-pattern (third pattern) result
                                    (and variable (list (cons variable (funcall read-type)))))
                (first pattern))
        result)))

(defstruct (function-definition (:constructor %make-function-definition))
  name inputs return-type body oracle-table total-p conditional-code-params)

(defun function-definition-code-type (def)
  (code-type (function-definition-inputs def) (function-definition-return-type def)))

(defun code-parameters (definition)
  "The `:code`-typed parameter specs of DEFINITION, in declaration order."
  (remove-if-not #'code-type-p (function-definition-inputs definition) :key #'cdr))

(defvar *function-definitions* (make-hash-table :test #'eq))
(defvar *registered-function-names* nil)
(defvar *function-library-version* 0)
(defvar *de-novo-function-counter* 0)

(defun canonical-op-name (name)
  (if (keywordp name) name (intern (symbol-name name) :keyword)))

(defun keyword-id (control &rest arguments)
  "The keyword named by CONTROL formatted with ARGUMENTS; symbols print as their names."
  (intern (apply #'format nil control arguments) :keyword))

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
  (and (tuple-type-p type) (rest type)
       (every #'valid-type-p (rest type))
       (every (lambda (part) (equal part (second type))) (cddr type))))

(defun normalize-at-container-type (type)
  "Normalize `:at` operand type: accepts `(:seq tau)`, homogeneous `(:tuple tau ... tau)`,
or element type `tau` (normalized to `(:seq tau)`)."
  (assert (valid-type-p type))
  (if (or (seq-type-p type) (homogeneous-tuple-type-p type))
      type
      (sequence-type type)))

(defun at-container-element-type (type)
  (second (normalize-at-container-type type)))

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
    (when (gf-type-p type)
      (return type))
    (when (and (consp type) (member (first type) '(:tuple :seq)))
      (let ((sub (infer-domain-from-types (rest type))))
        (unless (eq sub :int) (return sub))))))

(defun valid-availability-rank-p (rank)
  (not (null rank)))

(defun rank-le-p (low high &optional order)
  "True when availability rank LOW precedes or equals HIGH under ORDER (`((u . v) ...)`):
reflexive, with the universal bounds `:bottom` and `:top`, `<=` between real ranks, and the
transitive closure of these with ORDER: a path may follow a pair of ORDER or pass from one
real rank to a greater one, in any alternation."
  (flet ((at-or-before-p (from to) ; without consulting ORDER
           (or (equal from to) (and (realp from) (realp to) (<= from to)))))
    (cond ((at-or-before-p low high) t)
          ((eq low :bottom) t)
          ((eq high :top) t)
          ((or (eq low :top) (eq high :bottom)) nil)
          (order
           (let ((queue (list low))
                 (visited (list low)))
             (loop while queue
                   do (let ((current (pop queue)))
                        (dolist (edge order)
                          (when (at-or-before-p current (car edge))
                            (let ((next (cdr edge)))
                              (when (at-or-before-p next high)
                                (return-from rank-le-p t))
                              (unless (member next visited :test #'equal)
                                (push next visited)
                                (setf queue (append queue (list next))))))))
                   finally (return nil)))))))

(defun rank-lt-p (low high &optional order)
  "True when availability rank LOW strictly precedes HIGH under ORDER: LOW is at or before
HIGH (`rank-le-p`) and HIGH is not at or before LOW. Equal ranks do not precede one another,
nor do ranks that a cycle of ORDER makes equivalent."
  (and (rank-le-p low high order) (not (rank-le-p high low order))))

(defun make-schema (&key domain inputs (target :int) lookup-p
                         availability target-availability availability-order)
  (let* ((plist-p (and (consp availability) (keywordp (first availability))))
         (ranks (if plist-p (getf availability :ranks) availability))
         (target-rank (or target-availability (and plist-p (getf availability :target))))
         (order (or availability-order (and plist-p (getf availability :le))))
         (inferred-domain (or domain
                              (infer-domain-from-types (cons target (mapcar #'cdr inputs))))))
    (assert (or (not plist-p)
                (loop for (key nil) on availability by #'cddr
                      always (member key '(:ranks :target :le))))
            () "Availability ~S is neither an alist ((input-id . rank) ...) nor a plist of :ranks, :target and :le."
            availability)
    (assert (= (length ranks) (length (remove-duplicates ranks :key #'car :test #'equal)))
            () "Availability ranks ~S name an input more than once." ranks)
    (assert (every (lambda (entry)
                     (and (consp entry)
                          (assoc (car entry) inputs :test #'equal)
                          (valid-availability-rank-p (cdr entry))))
                   ranks))
    (assert (or (null target-rank) (valid-availability-rank-p target-rank)))
    (assert (every (lambda (edge)
                     (and (consp edge)
                          (valid-availability-rank-p (car edge))
                          (valid-availability-rank-p (cdr edge))))
                   order))
    (%make-schema :domain inferred-domain :inputs (copy-tree inputs)
                  :target (copy-tree target) :lookup-p lookup-p
                  :availability (copy-tree ranks)
                  :target-availability (copy-tree target-rank)
                  :availability-order (copy-tree order))))

(defun available-inputs (schema)
  "The inputs of SCHEMA that a model of its target may read: those whose availability rank
strictly precedes the target's (`rank-lt-p`). An input at the target's own rank is withheld,
since it may be the target under another name. An input without an explicit rank has rank
`:bottom` and is available to every target except one that is itself ranked `:bottom`. A
schema without a target rank withholds nothing."
  (let ((limit (schema-target-availability schema))
        (ranks (schema-availability schema))
        (order (schema-availability-order schema)))
    (if (null limit)
        (schema-inputs schema)
        (remove-if-not (lambda (input)
                         (let ((entry (assoc (car input) ranks :test #'equal)))
                           (rank-lt-p (if entry (cdr entry) :bottom) limit order)))
                       (schema-inputs schema)))))

(defun expression-respects-availability-p (expression schema)
  "True when EXPRESSION reads only inputs permitted by SCHEMA's availability preorder."
  (let ((allowed (available-inputs schema)))
    (every (lambda (id) (assoc id allowed :test #'equal))
           (free-vars expression))))

(defun schema-maximal-availability-id (schema)
  "Return the unique input ID of SCHEMA whose explicit availability rank dominates every
ranked input under `rank-le-p`, or nil when no unique top-ranked input exists."
  (let* ((ranks (schema-availability schema))
         (order (schema-availability-order schema))
         (top (loop for (id . rank) in ranks
                    when (every (lambda (other) (rank-le-p (cdr other) rank order)) ranks)
                      collect id)))
    (and (= 1 (length top)) (first top))))

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
  (if (eq value :unresolved)
      1
      (1+ (case type
            (:int (1+ (integer-width value)))
            (:bool 1)
            (otherwise
             (ecase (first type)
               (:gf (integer-width (1- (second type))))
               (:tuple (loop for item in value for part in (rest type) sum (value-work item part)))
               (:seq (loop for item in value sum (value-work item (second type))))
               (:code (syntax-work value))))))))

(defun signed-code (value)
  (if (minusp value) (* -2 value) (1+ (* 2 value))))

(defun decode-signed-code (value)
  (if (oddp value) (/ (1- value) 2) (- (/ value 2))))

(defun positive-bit-size (value)
  (assert (plusp value))
  (let* ((width (integer-length value))
         (length-width (integer-length width)))
    (+ (1- length-width) length-width (1- width))))

(defun value-bit-size (value type)
  "The bits `emit-bit-value` writes, computed directly because candidate scoring calls this
constantly and quoted code is sized from cached metadata."
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

;;; Operator typing

(defun expression-code-p (type)
  (and (code-type-p type) (not (function-sort-p (code-sort type)))))

(defun same-code-scope-p (left right)
  (and (code-type-p left) (code-type-p right) (equal (code-inputs left) (code-inputs right))))

(defun code-subst-code-binding-p (binding-type out-code-type input-type)
  "True when a :code-subst tuple element of BINDING-TYPE substitutes a code AST into INPUT-TYPE."
  (and (same-code-scope-p binding-type out-code-type)
       (equal (code-sort binding-type) input-type)))

(defun compute-operator-signature (name type)
  "The (:fn argument-types result-type) signature of operator NAME with parameter TYPE."
  (assert (valid-type-p type))
  (flet ((sig (inputs output) (list :fn inputs output)))
    (case name
      (:tuple
       (assert (tuple-type-p type))
       (sig (rest type) type))
      (:at (sig (list type :int) (at-container-element-type type)))
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
      ((:code-child :code-match :code-bind :code-subst)
       (assert (and (tuple-type-p type) (member (length type) '(3 4))))
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
            (assert (and (tuple-type-p b) (expression-code-p c)
                         (equal (code-sort a) (code-sort c))
                         (= (length (rest b)) (length (code-inputs a)))
                         (every (lambda (binding input)
                                  (or (code-subst-code-binding-p binding c (cdr input))
                                      (equal binding (cdr input))))
                                (rest b) (code-inputs a))))
            (sig (list a b) c)))))
      (otherwise
       (let ((pattern (signature-pattern name)))
         (cond (pattern
                (let ((bindings (match-type-pattern (first pattern) type)))
                  (sig (sublis bindings (second pattern)) (sublis bindings (third pattern)))))
               ((and (expression-code-p type)
                     (member name *registered-function-names*))
                (sig (mapcar #'cdr (code-inputs type)) (code-sort type)))
               (t (error "Unknown primitive ~S" name))))))))

;;; Homoiconic AST constructors:
;;; - Applications are native S-expressions `(op arg1 arg2 ...)`
;;; - Compound/typed literals are quoted `'(quote val)` (which prints as `'val`)
;;; - Variables (`x0`, `x1`), operators (`+`, `*`), and holes (`?0`, `?1`) are pooled
;;;   symbols carrying O(1) `ast-meta` in `*node-meta*`.

(defun normalize-operator-type (kname type)
  (cond ((eq kname :at) (normalize-at-container-type type))
        ((defined-function-p kname)
         (let* ((def (find-function-definition kname))
                (ctype (function-definition-code-type def)))
           (assert (or (null type)
                       (equal type ctype)
                       (equal type (function-definition-return-type def)))
                   () "Incompatible type ~S for function ~S" type kname)
           ctype))
        (t type)))

(defun pool-symbol (key name meta)
  "Enter a new symbol called NAME, carrying META, in the pool under KEY and return it."
  (let ((sym (make-symbol name)))
    (setf (node-meta sym) meta
          (gethash key *typed-symbol-pool*) sym)
    sym))

(defun op (name &optional type)
  "Construct a monomorphic operator symbol that prints cleanly (e.g. +, *, =, or defined :fa)."
  (let* ((kname (canonical-op-name name))
         (norm-type (normalize-operator-type kname type))
         (key (list :op kname norm-type))
         (existing (gethash key *typed-symbol-pool*)))
    (if (and existing (primitive-pattern kname))
        ;; The signature and opcode of a pooled primitive never change.
        existing
        (let ((sig (compute-operator-signature kname norm-type))
              (overhead (+ 2 (operator-bit-size kname norm-type))))
          (if existing
              (let ((meta (node-meta existing)))
                (when meta
                  (setf (ast-meta-non-var-bits meta) overhead
                        (ast-meta-value meta) sig))
                existing)
              (pool-symbol
               key (symbol-name kname)
               (make-ast-meta :kind :op :id kname :type (copy-tree norm-type) :value sig
                              :non-var-bits overhead
                              :var-count 0
                              :syntax-work (1+ (if (or (defined-function-p kname)
                                                       (member kname *registered-function-names*))
                                                   1
                                                   (type-work norm-type)))
                              :total-p t :free-vars nil)))))))

(defun operator-p (term)
  (let ((meta (and (symbolp term) (node-meta term))))
    (and meta (eq :op (ast-meta-kind meta)))))

(defun operator-meta (operator)
  (let ((meta (node-meta operator)))
    (assert (and meta (eq :op (ast-meta-kind meta))))
    meta))

(defun operator-name (operator) (ast-meta-id (operator-meta operator)))
(defun operator-operand-type (operator) (ast-meta-type (operator-meta operator)))
(defun operator-type (operator) (ast-meta-value (operator-meta operator)))
(defun application-overhead (operator) (ast-meta-non-var-bits (operator-meta operator)))

(defun pooled-leaf (kind prefix id type)
  "The canonical symbol for variable or hole ID of TYPE, created on first use."
  (assert (and (integerp id) (not (minusp id))))
  (let ((key (list kind id type))
        (var-p (eq kind :var)))
    (or (gethash key *typed-symbol-pool*)
        (pool-symbol key (format nil "~A~D" prefix id)
                     (make-ast-meta :kind kind :id id :type (copy-tree type)
                                    :non-var-bits 2 :var-count (if var-p 1 0)
                                    :syntax-work (+ 1 (integer-width id) (type-work type))
                                    :total-p t :free-vars (and var-p (list id)))))))

(defun var (id type)
  "Construct a typed variable symbol (e.g. X0, X1)."
  (assert (valid-type-p type))
  (pooled-leaf :var "X" id type))

(defun hole (id type)
  "Construct a typed pattern hole symbol (e.g. ?0, ?1)."
  (assert (valid-sort-p type))
  (pooled-leaf :hole "?" id type))

(defun hole-p (term)
  (let ((meta (and (symbolp term) (node-meta term))))
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
        (pool-symbol key "QUOTE" (make-ast-meta :kind :quote :type (copy-tree type))))))

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
    (setf (node-meta node) (compute-lit-meta type copied))
    node))

(defun provably-total-code-arg-p (expr &optional allow-open-code-p)
  "True when EXPR is a literal total code AST or a :code-subst of a total template with total bindings."
  (let ((meta (ensure-ast-meta expr)))
    (or (and allow-open-code-p (member (ast-meta-kind meta) '(:var :hole)))
        (and (eq :lit (ast-meta-kind meta))
             (provably-total-p (ast-meta-value meta)))
        (and (eq :app (ast-meta-kind meta))
             (eq :code-subst (ast-meta-id meta))
             (or allow-open-code-p (ast-meta-total-p meta))
             (let ((template-arg (second expr))
                   (tuple-arg (third expr)))
               (and (lit-p template-arg)
                    (provably-total-p (ast-value template-arg))
                    (app-of-p tuple-arg :tuple)
                    (every (lambda (b)
                             (if (code-type-p (ast-type b))
                                 (provably-total-code-arg-p b allow-open-code-p)
                                 (or allow-open-code-p (provably-total-p b))))
                           (rest tuple-arg))))))))

(defun non-empty-seq-expr-p (expr &optional non-empty-vars)
  "True when sequence expression EXPR is guaranteed non-empty."
  (let ((meta (ensure-ast-meta expr)))
    (case (ast-meta-kind meta)
      (:lit (not (null (ast-meta-value meta))))
      (:var (and non-empty-vars (member (ast-meta-id meta) non-empty-vars :test #'eql)))
      (:app (or (eq :cons (ast-meta-id meta))
                (and (eq :if (ast-meta-id meta))
                     (multiple-value-bind (then-vars else-vars)
                         (branch-non-empty-vars (second expr) non-empty-vars)
                       (and (non-empty-seq-expr-p (third expr) then-vars)
                            (non-empty-seq-expr-p (fourth expr) else-vars)))))))))

(defun operator-step-total-p (op-name arguments code-total-fn &optional non-empty-vars)
  "Single-step totality rule for OP-NAME applied to ARGUMENTS assuming children are total."
  (case op-name
    (:/ (and (lit-p (second arguments))
             (not (zerop (ast-value (second arguments))))))
    (:at (and (lit-p (second arguments))
              (let ((idx (ast-value (second arguments)))
                    (container (first arguments))
                    (container-type (ast-type (first arguments))))
                (and (integerp idx) (<= 0 idx)
                     (cond
                       ((tuple-type-p container-type)
                        (< idx (length (rest container-type))))
                       ((lit-p container)
                        (< idx (length (ast-value container))))
                       ((zerop idx)
                        (non-empty-seq-expr-p container non-empty-vars))
                       (t nil))))))
    (:tail (non-empty-seq-expr-p (first arguments) non-empty-vars))
    (:code-eval (funcall code-total-fn (first arguments)))
    ((:lookup :gather :code-child :code-operator :code-bind) nil)
    (otherwise
     (let ((def (find-function-definition op-name)))
       (or (null def)
           (function-definition-total-p def)
           (and (function-definition-conditional-code-params def)
                (every (lambda (param-idx)
                         (and (< param-idx (length arguments))
                              (funcall code-total-fn (nth param-idx arguments))))
                       (function-definition-conditional-code-params def))))))))

(defun empty-sequence-guard-var-id (condition &optional seq-param-ids)
  "If CONDITION is `(= Xi '())` or `(= '() Xi)` for a sequence variable Xi, return Xi's id."
  (let ((meta (ensure-ast-meta condition)))
    (when (and (eq :app (ast-meta-kind meta)) (eq := (ast-meta-id meta)))
      (flet ((guard (variable empty)
               (let ((vm (ensure-ast-meta variable)) (em (ensure-ast-meta empty)))
                 (and (eq :var (ast-meta-kind vm))
                      (seq-type-p (ast-meta-type vm))
                      (or (null seq-param-ids) (member (ast-meta-id vm) seq-param-ids))
                      (eq :lit (ast-meta-kind em)) (null (ast-meta-value em))
                      (ast-meta-id vm)))))
        (or (guard (second condition) (third condition))
            (guard (third condition) (second condition)))))))

(defun branch-non-empty-vars (condition non-empty-vars &optional seq-param-ids)
  "The sequence variables known to be non-empty in the then-branch and in the else-branch
of an `if` on CONDITION, as two values, given NON-EMPTY-VARS before it. The guard
`(= Xi '())` makes Xi empty in the first and non-empty in the second."
  (let ((id (empty-sequence-guard-var-id condition seq-param-ids)))
    (if id
        (values (remove id non-empty-vars) (adjoin id non-empty-vars))
        (values non-empty-vars non-empty-vars))))

(defun expr-total-under-non-empty-p (expr non-empty-vars)
  "True when EXPR is provably total given that sequence variables in NON-EMPTY-VARS are non-empty."
  (let ((meta (ensure-ast-meta expr)))
    (or (ast-meta-total-p meta)
        (case (ast-meta-kind meta)
          ((:lit :var) t)
          (:app
           (let ((op-name (ast-meta-id meta))
                 (args (rest expr)))
             (and op-name
                  (if (eq :if op-name)
                      (multiple-value-bind (then-vars else-vars)
                          (branch-non-empty-vars (first args) non-empty-vars)
                        (and (expr-total-under-non-empty-p (first args) non-empty-vars)
                             (expr-total-under-non-empty-p (second args) then-vars)
                             (expr-total-under-non-empty-p (third args) else-vars)))
                      (and (every (lambda (a) (expr-total-under-non-empty-p a non-empty-vars)) args)
                           (operator-step-total-p op-name args #'provably-total-code-arg-p non-empty-vars))))))))))

(defun compute-app-meta (operator arguments)
  (let* ((op-meta (ensure-ast-meta operator))
         (sig (if (eq :hole (ast-meta-kind op-meta))
                  (ast-meta-type op-meta)
                  (ast-meta-value op-meta)))
         (child-metas (mapcar #'ensure-ast-meta arguments))
         (op-name (when (eq :op (ast-meta-kind op-meta)) (ast-meta-id op-meta)))
         (total-p
           (and (eq :op (ast-meta-kind op-meta))
                (if (eq :if op-name)
                    (and (ast-meta-total-p (first child-metas))
                         (if (eq :lit (ast-meta-kind (first child-metas)))
                             (ast-meta-total-p (if (ast-meta-value (first child-metas))
                                                   (second child-metas)
                                                   (third child-metas)))
                             (and (ast-meta-total-p (second child-metas))
                                  (or (ast-meta-total-p (third child-metas))
                                      (let ((else-vars (nth-value 1 (branch-non-empty-vars
                                                                     (first arguments) nil))))
                                        (and else-vars
                                             (expr-total-under-non-empty-p (third arguments) else-vars)))))))
                    (and (every #'ast-meta-total-p child-metas)
                         (operator-step-total-p op-name arguments #'provably-total-code-arg-p)))))
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

(defun analyze-function-body-totality (name inputs body)
  "Conservative structural termination & totality check for a function definition.
Returns (values total-p conditional-code-params)."
  (when (null body)
    (return-from analyze-function-body-totality (values nil nil)))
  (let ((seq-param-ids (loop for (id . type) in inputs
                             when (seq-type-p type) collect id))
        (decreasing-param-id nil)
        (self-call-arg-lists nil)
        (code-params nil))
    (labels ((code-arg-safe-p (arg)
               (or (provably-total-code-arg-p arg)
                   (and (var-p arg)
                        (let ((pos (position (ast-id arg) inputs :key #'car :test #'eql)))
                          (when pos (pushnew pos code-params) t)))
                   (and (app-of-p arg :code-subst)
                        (lit-p (second arg)) (provably-total-p (ast-value (second arg)))
                        (app-of-p (third arg) :tuple)
                        (every (lambda (b)
                                 (if (code-type-p (ast-type b))
                                     (code-arg-safe-p b)
                                     t))
                               (rest (third arg))))))
             (walk (expr non-empty-vars)
               (case (ast-kind expr)
                 ((:lit :var) t)
                 (:app
                  (let* ((operator (first expr))
                         (op-name (and (operator-p operator) (operator-name operator)))
                         (args (rest expr)))
                    (cond
                      ((null op-name) nil)
                      ((eq op-name :if)
                       (destructuring-bind (cond-expr yes-expr no-expr) args
                         (multiple-value-bind (then-vars else-vars)
                             (branch-non-empty-vars cond-expr non-empty-vars seq-param-ids)
                           (and (walk cond-expr non-empty-vars)
                                (walk yes-expr then-vars)
                                (walk no-expr else-vars)))))
                      ((eq op-name name)
                       (and (every (lambda (a) (walk a non-empty-vars)) args)
                            (let ((matched-id
                                    (loop for (id . nil) in inputs for arg in args
                                          when (and (member id non-empty-vars :test #'eql)
                                                    (app-p arg) (eq :tail (operator-name (first arg)))
                                                    (var-p (second arg)) (eql id (ast-id (second arg))))
                                          return id)))
                              (and matched-id
                                   (or (null decreasing-param-id) (eql decreasing-param-id matched-id))
                                   (progn
                                     (setf decreasing-param-id matched-id)
                                     (push args self-call-arg-lists)
                                     t)))))
                      (t
                       (and (every (lambda (a) (walk a non-empty-vars)) args)
                            (operator-step-total-p op-name args #'code-arg-safe-p non-empty-vars)))))))))
      (when (walk body nil)
        (loop
          (let ((prev-count (length code-params)))
            (dolist (pos (copy-list code-params))
              (dolist (call-args self-call-arg-lists)
                (unless (and (< pos (length call-args))
                             (code-arg-safe-p (nth pos call-args)))
                  (return-from analyze-function-body-totality (values nil nil)))))
            (when (= (length code-params) prev-count)
              (return))))
        (let ((sorted-params (sort (copy-list code-params) #'<)))
          (return-from analyze-function-body-totality
            (values (null sorted-params) sorted-params))))
      (values nil nil))))

(defun invalidate-app-meta ()
  "Evict cached :app metadata so redefined functions recompute totality on demand."
  (maphash (lambda (node meta)
             (when (and (consp node) (eq :app (ast-meta-kind meta)))
               (remhash node *node-meta*)))
           *node-meta*))

(defun app (operator &rest arguments)
  "Construct a homoiconic application `(op arg1 arg2 ...)` with O(1) cached metadata."
  (let ((op-meta (and (symbolp operator) (node-meta operator))))
    (assert (and op-meta (member (ast-meta-kind op-meta) '(:op :hole))))
    (let ((node (cons operator (copy-list arguments))))
      (setf (node-meta node) (compute-app-meta operator arguments))
      node)))

(defun ensure-ast-meta (expression)
  (or (node-meta expression)
      (when (and (consp expression) (symbolp (first expression)))
        (let ((head-meta (node-meta (first expression))))
          (when head-meta
            (setf (node-meta expression)
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

(defun app-of-p (term name)
  "True when TERM applies the operator named NAME."
  (and (app-p term) (eq name (ast-id term))))

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
  (let* ((norm-inputs (input-alist inputs))
         (meta (ensure-ast-meta expression)))
    (expression-type expression norm-inputs)
    (+ (ast-meta-non-var-bits meta)
       (* (ast-meta-var-count meta)
          (integer-length (max 0 (1- (length norm-inputs))))))))

(defun expression-type (expression &optional inputs (allow-holes nil))
  "Validate syntax and variable scope, returning the expression's monomorphic type."
  (let ((norm-inputs (input-alist inputs))
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

(defun map-ast (function tree &key code root-first)
  "Rebuild TREE, replacing nodes as FUNCTION directs. FUNCTION is called with a node and its
metadata and returns the node's replacement, or nil to keep it. By default the tree is
rebuilt from the leaves up: an application is offered after its operator and arguments
have been mapped. With ROOT-FIRST a node is offered before its parts, and a node that is
replaced is not descended into, so FUNCTION sees exactly the nodes outside every
replacement. Subtrees that do not change are shared with TREE. Quoted code is mapped only
when CODE is true."
  (labels ((map-parts (node meta)
             (case (ast-meta-kind meta)
               (:app (let ((parts (mapcar #'walk node)))
                       (if (every #'eq parts node) node (apply #'app parts))))
               (:lit (let ((type (ast-meta-type meta)) (value (ast-meta-value meta)))
                       (if (and code (code-type-p type))
                           (let ((inner (walk value)))
                             (if (eq inner value) node (lit type inner)))
                           node)))
               (t node)))
           (walk (node)
             (let ((meta (ignore-errors (ensure-ast-meta node))))
               (cond ((null meta) node)
                     (root-first (or (funcall function node meta) (map-parts node meta)))
                     (t (let ((rebuilt (map-parts node meta)))
                          (or (funcall function rebuilt
                                       (if (eq rebuilt node) meta (ensure-ast-meta rebuilt)))
                              rebuilt)))))))
    (walk tree)))

(defun instantiate (tree substitutions &optional (tag :hole))
  "Simultaneous AST substitution on homoiconic S-expressions; literals are boundaries."
  (map-ast (lambda (node meta)
             (declare (ignore node))
             (and (eq tag (ast-meta-kind meta))
                  (cdr (assoc (ast-meta-id meta) substitutions))))
           tree))

(defun bind-inputs (inputs values)
  "Pair input variable IDs from INPUTS (or a schema) with corresponding VALUES."
  (mapcar (lambda (spec value) (cons (car spec) value)) (input-alist inputs) values))

(defun identity-bindings (inputs)
  "Build the identity variable substitution ((id . (var id type)) ...) for INPUTS."
  (mapcar (lambda (spec) (cons (car spec) (var (car spec) (cdr spec)))) (input-alist inputs)))

(defun literal-bindings (inputs values)
  "Build the literal substitution ((id . (lit type value)) ...) for INPUTS and VALUES."
  (loop for spec in (input-alist inputs)
        for value in values
        unless (eq value :unresolved)
          collect (cons (car spec) (lit (cdr spec) value))))

(defun next-child-id (inputs)
  "Return the next fresh variable ID after all IDs in INPUTS (or 0 if empty)."
  (let ((norm-inputs (input-alist inputs)))
    (if norm-inputs (1+ (reduce #'max norm-inputs :key #'car)) 0)))

(defun rename-function-calls (expr from-name to-target &optional extra-args)
  "Replace applications of operator FROM-NAME in EXPR with TO-TARGET (an operator symbol or function name),
optionally appending EXTRA-ARGS to each replaced call."
  (let ((kfrom (and from-name (canonical-op-name from-name)))
        (target-op (when (operator-p to-target) to-target))
        (kto (when (and to-target (not (operator-p to-target)))
               (canonical-op-name to-target))))
    (flet ((rename ()
             (map-ast (lambda (node meta)
                        (when (and (eq :app (ast-meta-kind meta)) (eq kfrom (ast-meta-id meta)))
                          (apply #'app
                                 (or target-op
                                     (if (defined-function-p kto)
                                         (op kto)
                                         (op kto (operator-operand-type (first node)))))
                                 (append (rest node) extra-args))))
                      expr :code t)))
      (cond ((or (null kfrom) (and kto (eq kfrom kto) (null extra-args))) expr)
            ((and kto (not (defined-function-p kto)) (not (member kto *registered-function-names*)))
             (let ((*registered-function-names* (append *registered-function-names* (list kto))))
               (rename)))
            (t (rename))))))

(defun ast->sexp (expr)
  "Convert an in-memory AST (including variables, holes, literals, `:code` values, and operators)
into a canonical, portable, self-typed S-expression without uninterned symbols."
  (when expr
    (let ((meta (ensure-ast-meta expr)))
      (ecase (ast-meta-kind meta)
        (:var (list :var (ast-meta-id meta) (copy-tree (ast-meta-type meta))))
        (:hole (list :hole (ast-meta-id meta) (copy-tree (ast-meta-type meta))))
        (:op (list :op (ast-meta-id meta) (copy-tree (ast-meta-type meta))))
        (:lit (let ((type (ast-meta-type meta))
                    (val (ast-meta-value meta)))
                (list :lit (copy-tree type)
                      (if (code-type-p type)
                          (ast->sexp val)
                          (copy-tree val)))))
        (:app (list* :app (ast->sexp (first expr)) (mapcar #'ast->sexp (rest expr))))))))

(defun sexp->ast (sexp)
  "Reconstruct an in-memory pooled, metadata-cached AST from a portable `ast->sexp` form."
  (when sexp
    (assert (and (consp sexp) (keywordp (first sexp))))
    (ecase (first sexp)
      (:var (var (second sexp) (third sexp)))
      (:hole (hole (second sexp) (third sexp)))
      (:op (let ((kname (canonical-op-name (second sexp)))
                 (otype (third sexp)))
             (if (defined-function-p kname)
                 (op kname)
                 (if (and (code-type-p otype) (not (member kname +operator-names+)))
                     (let ((*registered-function-names*
                             (if (member kname *registered-function-names*)
                                 *registered-function-names*
                                 (append *registered-function-names* (list kname)))))
                       (op kname otype))
                     (op kname otype)))))
      (:lit (let ((type (second sexp))
                  (raw-val (third sexp)))
              (lit type (if (code-type-p type)
                            (sexp->ast raw-val)
                            raw-val))))
      (:app (apply #'app (sexp->ast (second sexp)) (mapcar #'sexp->ast (cddr sexp)))))))

(defun walk-typed-ast (expression scope visitor)
  "Visit AST nodes with their lexical input schema; quotation starts a fresh scope.
Literal data is opaque. Function definitions are dependencies, not AST children."
  (when expression
    (funcall visitor expression scope)
    (case (ast-kind expression)
      (:app (dolist (part expression) (walk-typed-ast part scope visitor)))
      (:lit (when (code-type-p (ast-type expression))
              (walk-typed-ast (ast-value expression) (code-inputs (ast-type expression)) visitor)))))
  expression)

;;; A surface syntax for building typed ASTs in host code.

(defun operator-parameter-from-pattern (name types expected)
  "The type parameter of primitive NAME, as far as its type patterns determine it from
the argument TYPES that are known (nil marks one that is not) and the EXPECTED result type."
  (destructuring-bind (&optional parameter arguments result) (primitive-pattern name)
    (let ((bindings nil))
      (flet ((learn (pattern type)
               (when type
                 (setf bindings (or (ignore-errors (match-type-pattern pattern type bindings))
                                    bindings)))))
        (loop for (pattern) on arguments
              for type in types
              do (learn pattern type))
        (learn result expected)
        ;; A variable that nothing bound is left in place and is not a type.
        (let ((type (sublis bindings parameter)))
          (and (valid-type-p type) type))))))

(defun operator-parameter-from-arguments (name types expected)
  "The type parameter of primitive NAME, read off whichever argument TYPES are already
known (nil marks an argument that is not), or else off the EXPECTED result type."
  (flet ((tuple-of (&rest parts)
           (and (notany #'null parts) (apply #'tuple-type parts))))
    (case name
      ;; These carry a tuple of the types involved, which no single pattern expresses.
      (:tuple (apply #'tuple-of types))
      (:code-match (tuple-of (first types) (second types)))
      (:code-child (tuple-of (first types) expected))
      ((:code-bind :code-subst) (tuple-of (first types) (second types) expected))
      (:code-operator expected)
      (otherwise (operator-parameter-from-pattern name types expected)))))

(defun term (form &optional expected)
  "Build a typed AST from FORM, a plain S-expression whose operators are named by symbols
or keywords; each operator's type parameter is inferred from its arguments.
Anything in FORM that is already an AST is used as it stands, so a backquoted template
can splice in variables, sub-expressions, or an operator in head position. A bare literal
(a number, nil, t, or a quoted datum) takes its type from context: the type its operator
requires at that position, or EXPECTED at the top."
  (flet ((node-p (x)
           ;; The metadata of X if it is an AST. Copied trees are ASTs too; their metadata
           ;; is rebuilt on demand, so the cache alone cannot decide.
           (and x (or (symbolp x) (consp x)) (ignore-errors (ensure-ast-meta x))))
         (literal (value)
           (assert expected () "The literal ~S needs a type from its context." value)
           (lit expected value)))
    (cond ((node-p form) form)
          ((eq form t) (lit :bool t))
          ((atom form) (literal form))
          ((eq 'quote (first form)) (literal (second form)))
          (t
           (let* ((head (first form))
                  (head-meta (node-p head))
                  (name (cond ((null head-meta) (canonical-op-name head))
                              ((eq :op (ast-meta-kind head-meta)) (ast-meta-id head-meta))))
                  ;; Argument types fixed before the operator is: a supplied operator or
                  ;; hole, or a registered function, declares them.
                  (declared (cond ((and head-meta (eq :hole (ast-meta-kind head-meta)))
                                   (second (ast-meta-type head-meta)))
                                  (head-meta (second (ast-meta-value head-meta)))
                                  ((defined-function-p name) (second (operator-type (op name))))))
                  ;; First pass builds every argument that needs no type from this operator.
                  (built (loop for raw in (rest form) for index from 0
                               collect (cond (declared (term raw (nth index declared)))
                                             ((and (eq name :if) (zerop index)) (term raw :bool))
                                             (t (ignore-errors (term raw))))))
                  (operator (cond (head-meta head)
                                  (declared (op name))
                                  (t (let ((parameter (operator-parameter-from-arguments
                                                       name
                                                       (mapcar (lambda (node) (and node (ast-type node))) built)
                                                       expected)))
                                       (assert parameter () "Cannot infer the type of ~S in ~S." head form)
                                       (op name parameter)))))
                  (wanted (or declared (second (operator-type operator))))
                  (arguments (loop for node in built for raw in (rest form) for type in wanted
                                   collect (or node (term raw type)))))
             (assert (and (= (length arguments) (length wanted))
                          (every (lambda (node type) (equal type (ast-type node))) arguments wanted))
                     () "Ill-typed arguments in ~S: wanted ~S." form wanted)
             (apply #'app operator arguments))))))
