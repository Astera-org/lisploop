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
(defun type-kind (type)
  "The constructor of TYPE: itself for :int and :bool, and otherwise :gf, :tuple, :seq or :code."
  (if (consp type) (first type) type))
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
    (:code-eval ?t (?t . _) _)
    (:mod :int (:int :int) :int)
    (:iota :int (:int) (:seq :int))
    (:tabulate ?t (:int _) (:seq ?t))
    (:where ?t (?t (:seq ?t)) (:seq :int))
    (:evolve (:tuple ?a ?s) ((:seq ?a) ?s _) (:seq ?s))
    (:code-arity ?c (?c) :int)
    (:code-var ?e (:int) ?e)
    (:code-var-id ?c (?c) :int)
    (:code-quote ?e (_) ?e)
    (:code-value ?e (?e) _)
    (:code-anti-unify ?t (_ _) _))
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
  (if (eq name :at)
      (at-container-type type)
      (let ((variable (encoded-variable name)))
        (and variable
             (cdr (assoc variable (match-type-pattern (first (primitive-pattern name)) type)))))))

(defun operator-decoded-type (name result read-type)
  "The inverse of `operator-encoded-type`: the parameter of operator NAME in an application
of type RESULT, calling READ-TYPE for the part that was emitted."
  (if (eq name :at)
      (let ((container (funcall read-type)))
        (if (tuple-type-p container)
            (tuple-type container result)
            container))
      (let ((pattern (primitive-pattern name))
            (variable (encoded-variable name)))
        (if pattern
            (sublis (match-type-pattern (third pattern) result
                                        (and variable (list (cons variable (funcall read-type)))))
                    (first pattern))
            result))))

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
  (let* ((kname (canonical-op-name name))
         (prim-pos (position kname +operator-names+))
         (extra-prims (max 0 (- (length +operator-names+) 27))))
    (cond ((and prim-pos (< prim-pos 27)) prim-pos)
          (prim-pos (+ 35 (- prim-pos 27)))
          (t (let ((fn-pos (position kname *registered-function-names*)))
               (when fn-pos
                 (if (< fn-pos 8)
                     (+ 27 fn-pos)
                     (+ 35 extra-prims (- fn-pos 8)))))))))

(defun operator-by-index (index)
  (let ((extra-prims (max 0 (- (length +operator-names+) 27))))
    (cond ((< index 27) (nth index +operator-names+))
          ((< index 35) (nth (- index 27) *registered-function-names*))
          ((< index (+ 35 extra-prims)) (nth (+ 27 (- index 35)) +operator-names+))
          (t (nth (+ 8 (- index (+ 35 extra-prims))) *registered-function-names*)))))

(defun homogeneous-tuple-type-p (type)
  "True when TYPE is a non-empty (:tuple tau ... tau) with identical component types."
  (and (tuple-type-p type) (rest type)
       (every #'valid-type-p (rest type))
       (every (lambda (part) (equal part (second type))) (cddr type))))

(defun normalize-at-container-type (type)
  "Normalize `:at` operand type:
- `(:seq tau)` stays `(:seq tau)` (element type `tau`);
- `(:tuple tup-type slot-type)` with `slot-type` among `tup-type`'s slots stays as-is;
- homogeneous `(:tuple tau ... tau)` normalizes to `(:tuple (:tuple tau ... tau) tau)`;
- any scalar/non-tuple element type `tau` normalizes to `(:seq tau)`."
  (assert (valid-type-p type))
  (cond
    ((seq-type-p type) type)
    ((and (tuple-type-p type)
          (= 3 (length type))
          (tuple-type-p (second type))
          (rest (second type))
          (member (third type) (rest (second type)) :test #'equal))
     type)
    ((homogeneous-tuple-type-p type)
     (tuple-type type (second type)))
    (t
     (assert (not (tuple-type-p type)) ()
             "Heterogeneous or empty tuple ~S in `:at` requires `(:tuple tup-type slot-type)`." type)
     (sequence-type type))))

(defun at-container-type (type)
  (let ((norm (normalize-at-container-type type)))
    (if (tuple-type-p norm) (second norm) norm)))

(defun at-container-element-type (type)
  (let ((norm (normalize-at-container-type type)))
    (if (tuple-type-p norm) (third norm) (second norm))))

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
      (1+ (ecase (type-kind type)
            (:int (1+ (integer-width value)))
            (:bool 1)
            (:gf (integer-width (1- (second type))))
            (:tuple (loop for item in value for part in (rest type) sum (value-work item part)))
            (:seq (loop for item in value sum (value-work item (second type))))
            (:code (syntax-work value))))))

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
  (ecase (type-kind type)
    (:int (positive-bit-size (signed-code value)))
    (:bool 1)
    (:gf (integer-length (1- (second type))))
    (:tuple (loop for item in value for part in (rest type) sum (value-bit-size item part)))
    (:seq (+ (positive-bit-size (1+ (length value)))
             (loop for item in value sum (value-bit-size item (second type)))))
    (:code (let ((sort (code-sort type)))
             (if (function-sort-p sort)
                 (let ((meta (ensure-ast-meta value)))
                   (+ (operator-name-bit-size (ast-meta-id meta))
                      (type-bit-size (ast-meta-type meta))))
                 (body-size value (code-inputs type)))))))

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
      (:at (sig (list (at-container-type type) :int) (at-container-element-type type)))
      (:code-eval
       (assert (expression-code-p type))
       (sig (cons type (mapcar #'cdr (code-inputs type)))
            (code-sort type)))
      (:tabulate
       (sig (list :int (code-type '((0 . :int)) type)) (sequence-type type)))
      (:evolve
       (assert (and (tuple-type-p type) (= 3 (length type))))
       (let ((a (second type)) (s (third type)))
         (sig (list (sequence-type a) s (code-type (list (cons 0 s) (cons 1 a)) s))
              (sequence-type s))))
      (:code-quote
       (assert (expression-code-p type))
       (sig (list (code-sort type)) type))
      (:code-value
       (assert (expression-code-p type))
       (sig (list type) (code-sort type)))
      (:code-anti-unify
       (assert (and (tuple-type-p type) (= 3 (length type))))
       (let ((a (second type)) (b (third type)))
         (assert (and (expression-code-p a) (expression-code-p b)
                      (equal (code-sort a) (code-sort b))))
         (sig (list a a) b)))
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
                                                   (type-work (if (eq kname :at)
                                                                  (at-container-type norm-type)
                                                                  norm-type))))
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

;;; Totality: what is provably defined and terminates.
;;;
;;; The analysis carries facts about the variables and symbolic expressions in scope at a
;;; point of a body, each established by the conditions on the way there:
;;;   (:length id k)       the sequence X_id has at least k elements
;;;   (:above id b)        the integer X_id is greater than b
;;;   (:below id b)        the integer X_id is less than b
;;;   (:nonzero id)        the number X_id is not zero
;;;   (:nonzero-expr expr) the compound numeric expression EXPR is not zero
;;;   (:kind expr k)       `(code-kind EXPR)` equals integer tag k
;;;   (:diff u v k)        symbolic integer difference bound u - v <= k (:zero = 0)
;;; A fact holds of one scope. Quoted code is a scope of its own unless called by a bounded
;;; container combinator (`:tabulate`) that supplies index bounds to its body.

(defvar *certified-length-preserving-ops* (make-hash-table :test #'eq)
  "Operators certified (via `:ind1` or `:necessary` `:DESC/LEN-EQ`) to preserve primary sequence length.")

(defvar *mod-range-certified-p* nil
  "Set T only when a certified library law attests `0 < m => 0 <= (mod a m) < m` (Stage 1 E1/E3).")

(defun fact-bound (kind id facts tighter)
  "The tightest value among the facts of KIND about X_ID in FACTS, or nil."
  (let ((best nil))
    (dolist (fact facts best)
      (when (and (eq kind (first fact)) (eql id (second fact)))
        (setf best (if best (funcall tighter best (third fact)) (third fact)))))))

(defun known-length (id facts)
  (let ((explicit (or (fact-bound :length id facts #'max) 0))
        (len-key (cons :len id)))
    (dolist (fact facts explicit)
      (when (and (eq :diff (first fact)) (eq :zero (second fact)) (equal len-key (third fact)))
        (setf explicit (max explicit (- (fourth fact))))))))

(defun known-above (id facts)
  (let ((best (fact-bound :above id facts #'max))
        (var-key (cons :var id)))
    (dolist (fact facts best)
      (when (and (eq :diff (first fact)) (eq :zero (second fact)) (equal var-key (third fact)))
        (let ((bound (- (- (fourth fact)) 1)))
          (setf best (if best (max best bound) bound)))))))

(defun known-below (id facts)
  (let ((best (fact-bound :below id facts #'min))
        (var-key (cons :var id)))
    (dolist (fact facts best)
      (when (and (eq :diff (first fact)) (equal var-key (second fact)) (eq :zero (third fact)))
        (let ((bound (1+ (fourth fact))))
          (setf best (if best (min best bound) bound)))))))

(defun tail-chain (expr)
  "If EXPR is `(tail^k X)` for a sequence variable X and some k >= 0, the id of X and k."
  (let ((depth 0))
    (loop while (and (consp expr) (eq :tail (ast-meta-id (ensure-ast-meta expr))))
          do (incf depth)
             (setf expr (second expr)))
    (let ((meta (ensure-ast-meta expr)))
      (when (and (eq :var (ast-meta-kind meta)) (seq-type-p (ast-meta-type meta)))
        (values (ast-meta-id meta) depth)))))

(defun length-chain (expr)
  "If EXPR is `(length (tail^k X))` for a sequence variable X, the id of X and k."
  (when (and (consp expr) (eq :length (ast-meta-id (ensure-ast-meta expr))))
    (tail-chain (second expr))))

(defun literal-integer (expr)
  "The value of EXPR when it is an integer literal, else nil."
  (let ((meta (ensure-ast-meta expr)))
    (and (eq :lit (ast-meta-kind meta)) (integerp (ast-meta-value meta)) (ast-meta-value meta))))

(defun numeric-variable-id (expr)
  "The id of EXPR when it is a variable of an integer or field type, else nil."
  (let ((meta (ensure-ast-meta expr)))
    (and (eq :var (ast-meta-kind meta))
         (or (eq :int (ast-meta-type meta)) (gf-type-p (ast-meta-type meta)))
         (ast-meta-id meta))))

(defun seq-length-key-offset (seq-expr &optional facts)
  "Decompose the length of SEQ-EXPR as `(VALUES key offset)` representing `key + offset` when exact."
  (let ((meta (ensure-ast-meta seq-expr)))
    (case (ast-meta-kind meta)
      (:lit (when (listp (ast-meta-value meta))
              (values :zero (length (ast-meta-value meta)))))
      (:var (when (seq-type-p (ast-meta-type meta))
              (values (cons :len (ast-meta-id meta)) 0)))
      (:app (let ((name (ast-meta-id meta))
                  (args (rest seq-expr)))
              (cond
                ((eq name :cons)
                 (multiple-value-bind (k o) (seq-length-key-offset (second args) facts)
                   (when k (values k (1+ o)))))
                ((and (eq name :tail) (plusp (minimum-length (first args) facts)))
                 (multiple-value-bind (k o) (seq-length-key-offset (first args) facts)
                   (when k (values k (1- o)))))
                ((and (member name '(:iota :tabulate))
                      (diff-expr-le-p (lit :int 0) (first args) 0 facts))
                 (diff-term-offset (first args) facts))
                ((eq name :gather)
                 (seq-length-key-offset (second args) facts))
                ((eq name :evolve)
                 (seq-length-key-offset (first args) facts))
                ((and (gethash name *certified-length-preserving-ops*)
                      args (seq-type-p (ast-type (first args))))
                 (seq-length-key-offset (first args) facts))))))))

(defun diff-term-offset (expr &optional facts)
  "Normalize integer EXPR into `(VALUES canonical-key integer-offset)` meaning `key + offset`."
  (let ((meta (ensure-ast-meta expr)))
    (when (eq :int (ast-meta-type meta))
      (case (ast-meta-kind meta)
        (:lit (values :zero (ast-meta-value meta)))
        (:var (values (cons :var (ast-meta-id meta)) 0))
        (:app (let ((name (ast-meta-id meta))
                    (args (rest expr)))
                (cond
                  ((eq name :+)
                   (let ((c1 (literal-integer (first args)))
                         (c2 (literal-integer (second args))))
                     (cond (c2 (multiple-value-bind (k o) (diff-term-offset (first args) facts)
                                 (when k (values k (+ o c2)))))
                           (c1 (multiple-value-bind (k o) (diff-term-offset (second args) facts)
                                 (when k (values k (+ o c1)))))
                           (t (values expr 0)))))
                  ((eq name :-)
                   (let ((c2 (literal-integer (second args))))
                     (if c2
                         (multiple-value-bind (k o) (diff-term-offset (first args) facts)
                           (when k (values k (- o c2))))
                         (values expr 0))))
                  ((eq name :length)
                   (multiple-value-bind (k o) (seq-length-key-offset (first args) facts)
                     (if k (values k o) (values expr 0))))
                  (t (values expr 0)))))))))

(defun diff-key-le-p (u v k facts)
  "True when `u - v <= k` holds trivially, directly, or by 2-step transitivity in FACTS."
  (or (and (equal u v) (<= 0 k))
      ;; All sequence lengths `:len` are >= 0 (`:zero - (:len id) <= 0`).
      (and (eq u :zero) (consp v) (eq :len (car v)) (<= 0 k))
      (loop for f in facts
            thereis (and (eq :diff (first f))
                         (equal u (second f))
                         (or (and (equal v (third f)) (<= (fourth f) k))
                             (let ((w (third f)) (k1 (fourth f)))
                               (or (and (eq w :zero) (consp v) (eq :len (car v)) (<= k1 k))
                                   (loop for f2 in facts
                                         thereis (and (eq :diff (first f2))
                                                      (equal w (second f2))
                                                      (equal v (third f2))
                                                      (<= (+ k1 (fourth f2)) k))))))))
      ;; Bridge legacy `(:length id m)` -> `0 - (:len id) <= -m` when combined with another edge.
      (and (consp v) (eq :len (car v))
           (let ((min-len (fact-bound :length (cdr v) facts #'max)))
             (and min-len
                  (or (and (eq u :zero) (<= (- min-len) k))
                      (diff-key-le-p u :zero (+ k min-len) facts)))))))

(defun diff-expr-le-p (left right k facts)
  "True when integer inequality `LEFT - RIGHT <= K` is entailed by FACTS (plus certified `:mod` range)."
  (or (multiple-value-bind (uk uo) (diff-term-offset left facts)
        (multiple-value-bind (vk vo) (diff-term-offset right facts)
          (and uk vk (diff-key-le-p uk vk (- k (- uo vo)) facts))))
      ;; Certified `:mod` output range: when `0 < m`, `0 <= (mod a m) <= m - 1`.
      (and *mod-range-certified-p*
           (cond
             ((and (app-of-p right :mod)
                   (diff-expr-le-p (lit :int 1) (third right) 0 facts))
              (diff-expr-le-p left (lit :int 0) k facts))
             ((and (app-of-p left :mod)
                   (diff-expr-le-p (lit :int 1) (third left) 0 facts))
              (diff-expr-le-p (third left) right (1+ k) facts))))))

(defun index-in-sequence-bounds-p (idx container facts)
  "True when integer expression IDX satisfies `0 <= IDX < length(CONTAINER)` under FACTS,
including affine subtraction `(- L B)` (`reverse`-style indexing)."
  (multiple-value-bind (lk lo) (seq-length-key-offset container facts)
    (let ((low-ok (or (diff-expr-le-p (lit :int 0) idx 0 facts)
                      (and (app-of-p idx :-)
                           (diff-expr-le-p (third idx) (second idx) 0 facts))))
          (high-ok
            (cond
              (lk
               (or (multiple-value-bind (ik io) (diff-term-offset idx facts)
                     (and ik (diff-key-le-p ik lk (- -1 (- io lo)) facts)))
                   (and *mod-range-certified-p*
                        (app-of-p idx :mod)
                        (diff-expr-le-p (lit :int 1) (third idx) 0 facts)
                        (multiple-value-bind (mk mo) (diff-term-offset (third idx) facts)
                          (and mk (diff-key-le-p mk lk (- 0 (- mo lo)) facts))))
                   ;; `(- A B) <= L - 1` when `A <= L` and `1 <= B`.
                   (and (app-of-p idx :-)
                        (multiple-value-bind (ak ao) (diff-term-offset (second idx) facts)
                          (and ak (diff-key-le-p ak lk (- 0 (- ao lo)) facts)))
                        (diff-expr-le-p (lit :int 1) (third idx) 0 facts))))
              (t (let ((min-len (minimum-length container facts)))
                   (and (plusp min-len)
                        (diff-expr-le-p idx (lit :int (1- min-len)) 0 facts)))))))
      (and low-ok high-ok))))

(defun condition-facts (condition facts)
  "What is known once CONDITION has evaluated to true, and once it has evaluated to false,
as two values, given FACTS before it."
  (let ((meta (ensure-ast-meta condition)))
    (if (not (eq :app (ast-meta-kind meta)))
        (values facts facts)
        (destructuring-bind (&optional left right other) (rest condition)
          (flet ((literal-p (expr value)
                   (let ((m (ensure-ast-meta expr)))
                     (and (eq :lit (ast-meta-kind m)) (eq :bool (ast-meta-type m))
                          (eq value (ast-meta-value m)))))
                 (with-list (new-facts base)
                   (let ((acc base))
                     (dolist (f new-facts acc)
                       (when f (push f acc)))))
                 (sized (expr more)
                   (multiple-value-bind (id depth) (length-chain expr)
                     (and id more (list :length id (+ depth more))))))
            (case (ast-meta-id meta)
              (:=
               (flet ((emptiness (sequence empty)
                        (let ((m (ensure-ast-meta empty)))
                          (and (eq :lit (ast-meta-kind m)) (seq-type-p (ast-meta-type m))
                               (null (ast-meta-value m))
                               (multiple-value-bind (id depth) (tail-chain sequence)
                                 (and id (list :length id (1+ depth)))))))
                      (zero (number zero)
                        (when (eql 0 (literal-integer zero))
                          (let ((id (numeric-variable-id number)))
                            (if id
                                (list :nonzero id)
                                (when (or (eq :int (ast-type number)) (gf-type-p (ast-type number)))
                                  (list :nonzero-expr number))))))
                      (kind-eq (kexpr klit)
                        (let ((kv (literal-integer klit)))
                          (when (and kv (app-of-p kexpr :code-kind))
                            (list :kind (second kexpr) kv))))
                      (counted (length count truth)
                        (let ((n (literal-integer count)))
                          (sized length (and n (if truth
                                                   (and (plusp n) n)
                                                   (and (zerop n) 1))))))
                      (eq-diffs (a b)
                        (multiple-value-bind (uk uo) (diff-term-offset a facts)
                          (multiple-value-bind (vk vo) (diff-term-offset b facts)
                            (when (and uk vk)
                              (list (list :diff uk vk (- vo uo))
                                    (list :diff vk uk (- uo vo))))))))
                 (values (with-list (append (list (or (counted left right t) (counted right left t))
                                                  (or (kind-eq left right) (kind-eq right left)))
                                            (eq-diffs left right))
                                    facts)
                         (with-list (list (or (emptiness left right) (emptiness right left))
                                          (or (zero left right) (zero right left))
                                          (or (counted left right nil) (counted right left nil)))
                                    facts))))
              (:<
               (let ((low (literal-integer left))
                     (high (literal-integer right))
                     (left-id (numeric-variable-id left))
                     (right-id (numeric-variable-id right)))
                 (multiple-value-bind (uk uo) (diff-term-offset left facts)
                   (multiple-value-bind (vk vo) (diff-term-offset right facts)
                     (let ((t-diff (when (and uk vk) (list :diff uk vk (- (- vo uo) 1))))
                           (f-diff (when (and uk vk) (list :diff vk uk (- uo vo))))
                           (t-legacy (cond ((and low right-id) (list :above right-id low))
                                           ((and left-id high) (list :below left-id high))
                                           (t (sized right (and low (1+ low))))))
                           (f-legacy (cond ((and low right-id) (list :below right-id (1+ low)))
                                           ((and left-id high) (list :above left-id (1- high)))
                                           (t (sized left high)))))
                       (values (with-list (list t-legacy t-diff) facts)
                               (with-list (list f-legacy f-diff) facts)))))))
              (:if
               (cond ((and (literal-p right nil) (literal-p other t)) ; not left
                      (multiple-value-bind (when-true when-false) (condition-facts left facts)
                        (values when-false when-true)))
                     ((literal-p other nil) ; left and right
                      (values (condition-facts right (condition-facts left facts)) facts))
                     ((literal-p right t) ; left or other
                      (values facts (nth-value 1 (condition-facts
                                                  other (nth-value 1 (condition-facts left facts))))))
                     (t (values facts facts))))
              (otherwise (values facts facts))))))))

(defun minimum-length (expr facts)
  "A number of elements that the sequence expression EXPR is sure to have, given FACTS."
  (let ((meta (ensure-ast-meta expr)))
    (case (ast-meta-kind meta)
      (:lit (let ((value (ast-meta-value meta))) (if (listp value) (length value) 0)))
      (:var (known-length (ast-meta-id meta) facts))
      (:app (let ((name (ast-meta-id meta)))
              (case name
                (:cons (1+ (minimum-length (third expr) facts)))
                (:tail (max 0 (1- (minimum-length (second expr) facts))))
                ((:iota :tabulate)
                 (let ((c (literal-integer (second expr))))
                   (if c
                       (max 0 c)
                       (or (loop for m downfrom 8 above 0
                                 when (diff-expr-le-p (lit :int m) (second expr) 0 facts)
                                   return m)
                           0))))
                (:gather (minimum-length (third expr) facts))
                (:evolve (minimum-length (second expr) facts))
                (:if (multiple-value-bind (when-true when-false) (condition-facts (second expr) facts)
                       (min (minimum-length (third expr) when-true)
                            (minimum-length (fourth expr) when-false))))
                (otherwise
                 (if (and (gethash name *certified-length-preserving-ops*)
                          (rest expr) (seq-type-p (ast-type (second expr))))
                     (minimum-length (second expr) facts)
                     0)))))
      (otherwise 0))))

(defun nonzero-expr-p (expr facts)
  "True when the number EXPR is sure not to be zero: a nonzero literal, a variable bound away
from zero, or an expression explicitly guarded by `(not (= EXPR 0))` or difference bounds."
  (let ((meta (ensure-ast-meta expr)))
    (or (case (ast-meta-kind meta)
          (:lit (and (numberp (ast-meta-value meta)) (not (zerop (ast-meta-value meta)))))
          (:var (let* ((id (ast-meta-id meta))
                       (above (known-above id facts))
                       (below (known-below id facts)))
                  (or (and above (>= above 0))
                      (and below (<= below 0))
                      (and (find-if (lambda (fact) (and (eq :nonzero (first fact)) (eql id (second fact))))
                                    facts)
                           t)))))
        (and (find-if (lambda (fact) (and (eq :nonzero-expr (first fact)) (equal expr (second fact))))
                      facts)
             t)
        (and (eq :int (ast-meta-type meta))
             (or (diff-expr-le-p (lit :int 1) expr 0 facts)
                 (diff-expr-le-p expr (lit :int -1) 0 facts))))))

(defun tabulate-code-total-under-p (n-expr code-arg code-total-fn facts)
  "True when `:tabulate`'s code argument CODE-ARG is total on every index `0 <= j < N-EXPR`."
  (or (funcall code-total-fn code-arg)
      (let ((idx-var (var -1 :int)))
        (multiple-value-bind (body bindings)
            (cond
              ((lit-p code-arg)
               (values (ast-value code-arg) (list (cons 0 idx-var))))
              ((and (app-of-p code-arg :code-subst)
                    (lit-p (second code-arg))
                    (app-of-p (third code-arg) :tuple))
               (let* ((a-inputs (code-inputs (ast-type (second code-arg))))
                      (c-type (ast-type code-arg))
                      (parts (rest (third code-arg))))
                 (when (and parts
                            (lit-p (first parts))
                            (var-p (ast-value (first parts)))
                            (zerop (ast-id (ast-value (first parts))))
                            (loop for b in (rest parts)
                                  for (nil . in-type) in (rest a-inputs)
                                  never (code-subst-code-binding-p (ast-type b) c-type in-type)))
                   (values (ast-value (second code-arg))
                           (cons (cons (caar a-inputs) idx-var)
                                 (loop for (aid . nil) in (rest a-inputs)
                                       for b in (rest parts)
                                       collect (cons aid b))))))))
          (when body
            (let* ((inst (instantiate body bindings :var))
                   (idx-key (cons :var -1))
                   (base-facts (cons (list :diff :zero idx-key 0) facts))
                   (ext-facts (multiple-value-bind (nk no) (diff-term-offset n-expr facts)
                                (if nk
                                    (cons (list :diff idx-key nk (- no 1)) base-facts)
                                    base-facts))))
              (expr-total-under-p inst ext-facts)))))))

(defun gather-indices-in-bounds-p (container indices facts)
  "True when every element of INDICES (`(:seq :int)`) lies in `[0, length(CONTAINER))`."
  (cond
    ((lit-p indices)
     (let ((vals (ast-value indices)))
       (every (lambda (v) (index-in-sequence-bounds-p (lit :int v) container facts)) vals)))
    ((app-of-p indices :iota)
     (multiple-value-bind (lk lo) (seq-length-key-offset container facts)
       (multiple-value-bind (nk no) (diff-term-offset (second indices) facts)
         (and lk nk (diff-key-le-p nk lk (- lo no) facts)))))
    ((app-of-p indices :where)
     (equal container (third indices)))
    ((app-of-p indices :tabulate)
     (let ((n-expr (second indices))
           (code-arg (third indices))
           (idx-var (var -2 :int)))
       (multiple-value-bind (body bindings)
           (cond
             ((lit-p code-arg) (values (ast-value code-arg) (list (cons 0 idx-var))))
             ((and (app-of-p code-arg :code-subst)
                   (lit-p (second code-arg))
                   (app-of-p (third code-arg) :tuple))
              (let ((a-inputs (code-inputs (ast-type (second code-arg))))
                    (parts (rest (third code-arg))))
                (when (and parts (lit-p (first parts)) (var-p (ast-value (first parts)))
                           (zerop (ast-id (ast-value (first parts)))))
                  (values (ast-value (second code-arg))
                          (cons (cons (caar a-inputs) idx-var)
                                (loop for (aid . nil) in (rest a-inputs)
                                      for b in (rest parts)
                                      collect (cons aid b))))))))
         (when body
           (let* ((elem-expr (instantiate body bindings :var))
                  (idx-key (cons :var -2))
                  (base-facts (cons (list :diff :zero idx-key 0) facts))
                  (ext-facts (multiple-value-bind (nk no) (diff-term-offset n-expr facts)
                               (if nk (cons (list :diff idx-key nk (- no 1)) base-facts) base-facts))))
             (and (expr-total-under-p elem-expr ext-facts)
                  (index-in-sequence-bounds-p elem-expr container ext-facts)))))))))

(defun operator-step-total-p (op-name arguments code-total-fn &optional facts expected-type)
  "Single-step totality rule for OP-NAME applied to ARGUMENTS assuming children are total,
given FACTS about the variables in scope."
  (case op-name
    ((:/ :mod) (nonzero-expr-p (second arguments) facts))
    (:at (let ((container (first arguments))
               (idx-expr (second arguments))
               (container-type (ast-type (first arguments))))
           (if (tuple-type-p container-type)
               (and (lit-p idx-expr)
                    (let ((idx (ast-value idx-expr)))
                      (and (integerp idx) (<= 0 idx)
                           (< idx (length (rest container-type)))
                           (or (null expected-type)
                               (equal (nth idx (rest container-type)) expected-type)))))
               (index-in-sequence-bounds-p idx-expr container facts))))
    (:gather (gather-indices-in-bounds-p (first arguments) (second arguments) facts))
    (:tail (plusp (minimum-length (first arguments) facts)))
    (:code-eval (funcall code-total-fn (first arguments)))
    (:tabulate (tabulate-code-total-under-p (first arguments) (second arguments) code-total-fn facts))
    (:evolve (funcall code-total-fn (third arguments)))
    ((:iota :where :code-arity :code-quote) t)
    (:code-var
     (let ((scope (and expected-type (code-type-p expected-type) (code-inputs expected-type)))
           (sort (and expected-type (code-type-p expected-type) (code-sort expected-type)))
           (idx (literal-integer (first arguments))))
       (and idx scope (equal sort (cdr (assoc idx scope))))))
    (:code-var-id
     (and (find-if (lambda (f) (and (eq :kind (first f)) (equal (first arguments) (second f)) (= 0 (third f))))
                   facts)
          t))
    (:code-value
     (and (find-if (lambda (f) (and (eq :kind (first f)) (equal (first arguments) (second f)) (= 1 (third f))))
                   facts)
          t))
    ((:lookup :code-child :code-operator :code-bind :code-anti-unify) nil)
    (otherwise
     (let ((def (find-function-definition op-name)))
       (if def
           (or (function-definition-total-p def)
               (and (function-definition-conditional-code-params def)
                    (every (lambda (param-idx)
                             (and (< param-idx (length arguments))
                                  (funcall code-total-fn (nth param-idx arguments))))
                           (function-definition-conditional-code-params def))))
           (not (null (primitive-pattern op-name))))))))

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

(defun expr-total-under-p (expr facts)
  "True when EXPR is provably total given FACTS about its variables."
  (let ((meta (ensure-ast-meta expr)))
    (or (ast-meta-total-p meta)
        (case (ast-meta-kind meta)
          ((:lit :var) t)
          (:app
           (let ((op-name (ast-meta-id meta))
                 (args (rest expr)))
             (and op-name
                  (if (eq :if op-name)
                      (multiple-value-bind (when-true when-false) (condition-facts (first args) facts)
                        (and (expr-total-under-p (first args) facts)
                             (expr-total-under-p (second args) when-true)
                             (expr-total-under-p (third args) when-false)))
                      (and (every (lambda (a) (expr-total-under-p a facts)) args)
                           (operator-step-total-p op-name args #'provably-total-code-arg-p
                                                  facts (ast-meta-type meta)))))))))))

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
                             ;; A branch that is not total by itself may be total given what
                             ;; the condition establishes on the way into it.
                             (let ((yes-p (ast-meta-total-p (second child-metas)))
                                   (no-p (ast-meta-total-p (third child-metas))))
                               (or (and yes-p no-p)
                                   (multiple-value-bind (when-true when-false)
                                       (condition-facts (first arguments) nil)
                                     (and (or yes-p (and when-true
                                                         (expr-total-under-p (second arguments) when-true)))
                                          (or no-p (and when-false
                                                        (expr-total-under-p (third arguments) when-false)))))))))
                    (and (every #'ast-meta-total-p child-metas)
                         (operator-step-total-p op-name arguments #'provably-total-code-arg-p
                                                nil (third sig))))))
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

(defun self-call-changes (inputs arguments facts)
  "How a self-call with ARGUMENTS moves each parameter of INPUTS, given FACTS at the call:
  :same     the parameter is passed on as it is
  :shorter  a sequence, passed on with elements taken off its front that it is sure to have
  :down     an integer bounded below, passed on reduced by a literal of at least 1, or, when
            the bound is at least 0, divided by a literal of at least 2
  :up       an integer bounded above, passed on increased by a literal of at least 1
  nil       anything else.
Each is read off the argument in the parameter's own position against that same parameter:
the tail of another parameter says nothing of this one."
  (loop for (id . type) in inputs
        for argument in arguments
        collect
        (let ((meta (ensure-ast-meta argument)))
          (flet ((self-p (expr)
                   (let ((m (ensure-ast-meta expr)))
                     (and (eq :var (ast-meta-kind m)) (eql id (ast-meta-id m))))))
            (cond
              ((self-p argument) :same)
              ((seq-type-p type)
               (multiple-value-bind (variable depth) (tail-chain argument)
                 (and (eql variable id) (<= 1 depth (known-length id facts)) :shorter)))
              ((and (eq :int type) (eq :app (ast-meta-kind meta)) (= 2 (length (rest argument))))
               (destructuring-bind (left right) (rest argument)
                 (let ((step (literal-integer right))
                       (above (known-above id facts))
                       (below (known-below id facts)))
                   (case (ast-meta-id meta)
                     (:- (and (self-p left) step (>= step 1) above :down))
                     (:/ (and (self-p left) step (>= step 2) above (>= above 0) :down))
                     (:+ (and below
                              (or (and (self-p left) step (>= step 1))
                                  (and (self-p right) (literal-integer left)
                                       (>= (literal-integer left) 1)))
                              :up)))))))))))

(defun self-calls-descend-p (sites)
  "True when the self-calls of a body, each given as its `self-call-changes`, cannot go on
for ever. A measure is a parameter read one way: a sequence's length, an integer's height
above its lower bound, or its depth below its upper one. Some measure must fall at one call
at least and rise at none. The calls at which it falls are then accounted for, and the
rest, which leave it as it is, must descend by another measure in the same way. That is a
lexicographic order: a call that lowers an earlier measure may do anything to a later one."
  (or (null sites)
      (loop for slot below (length (first sites))
            thereis (loop for way in '(:shorter :down :up)
                          thereis (flet ((change (site) (nth slot site)))
                                    (and (find way sites :key #'change)
                                         (every (lambda (site) (member (change site) (list :same way)))
                                                sites)
                                         (self-calls-descend-p (remove way sites :key #'change))))))))

(defun analyze-function-body-totality (name inputs body)
  "Conservative structural termination & totality check for a function definition.
Returns (values total-p conditional-code-params). Every step of BODY must be total given
the facts its conditions establish (`condition-facts`), and its self-calls must descend
(`self-calls-descend-p`). A `code-eval` of literal code that is not total by itself is
read as its body with the arguments in place of its parameters, so a self-call written
inside a binding is judged where it runs, under the facts that hold there."
  (when (null body)
    (return-from analyze-function-body-totality (values nil nil)))
  (let ((sites nil)
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
             (walk (expr facts)
               (case (ast-kind expr)
                 ((:lit :var) t)
                 (:app
                  (let* ((operator (first expr))
                         (op-name (and (operator-p operator) (operator-name operator)))
                         (args (rest expr)))
                    (flet ((walk-all (parts) (every (lambda (part) (walk part facts)) parts)))
                      (cond
                        ((null op-name) nil)
                        ((eq op-name :if)
                         (destructuring-bind (cond-expr yes-expr no-expr) args
                           (multiple-value-bind (when-true when-false) (condition-facts cond-expr facts)
                             (and (walk cond-expr facts)
                                  (walk yes-expr when-true)
                                  (walk no-expr when-false)))))
                        ((eq op-name name)
                         (and (= (length args) (length inputs))
                              (walk-all args)
                              (progn (push (self-call-changes inputs args facts) sites)
                                     (push args self-call-arg-lists)
                                     t)))
                        ((and (eq op-name :code-eval) (lit-p (first args))
                              (not (provably-total-code-arg-p (first args))))
                         (and (walk-all (rest args))
                              (walk (instantiate (ast-value (first args))
                                                 (bind-inputs (code-inputs (ast-type (first args)))
                                                              (rest args))
                                                 :var)
                                    facts)))
                        (t
                         (and (walk-all args)
                              (operator-step-total-p op-name args #'code-arg-safe-p facts
                                                     (third (operator-type operator))))))))))))
      (when (and (walk body nil) (self-calls-descend-p sites))
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

(defun provably-total-given-p (expression condition)
  "True when EXPRESSION is provably total wherever CONDITION, itself provably total,
evaluates to true: a witness that divides by what its guard has found not to be zero."
  (and (provably-total-p condition)
       (expr-total-under-p expression (condition-facts condition nil))))

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
      ;; A literal part has no type of its own; the result type then supplies them all.
      (:tuple (or (apply #'tuple-of types)
                  (and (tuple-type-p expected)
                       (= (length types) (length (rest expected)))
                       expected)))
      (:at (let ((container (first types)))
             (cond
               ((tuple-type-p container)
                (cond (expected (tuple-type container expected))
                      ((homogeneous-tuple-type-p container)
                       (tuple-type container (second container)))))
               ((seq-type-p container) container)
               (expected (sequence-type expected)))))
      (:code-match (tuple-of (first types) (second types)))
      (:code-child (tuple-of (first types) expected))
      ((:code-bind :code-subst) (tuple-of (first types) (second types) expected))
      (:code-operator expected)
      (:tabulate (or (and (code-type-p (second types)) (code-sort (second types)))
                     (and (seq-type-p expected) (second expected))))
      (:evolve (tuple-of (and (seq-type-p (first types)) (second (first types)))
                         (or (second types)
                             (and (code-type-p (third types)) (code-sort (third types)))
                             (and (seq-type-p expected) (second expected)))))
      (:code-quote expected)
      (:code-value (first types))
      (:code-anti-unify (tuple-of (or (first types) (second types)) expected))
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
                                             ((and (eq name :at) (= index 1)) (term raw :int))
                                             ((and (member name '(:iota :tabulate :code-var)) (zerop index))
                                              (term raw :int))
                                             ((and (eq name :code-child) (= index 1)) (term raw :int))
                                             ((and (eq name :code-bind) (= index 2)) (term raw :int))
                                             (t (ignore-errors (term raw))))))
                  (inferred-expected
                    (or expected
                        (and (eq name :at)
                             (first built) (tuple-type-p (ast-type (first built)))
                             (second built) (lit-p (second built))
                             (let ((idx (ast-value (second built)))
                                   (slots (rest (ast-type (first built)))))
                               (and (integerp idx) (<= 0 idx) (< idx (length slots))
                                    (nth idx slots))))))
                  (operator (cond (head-meta head)
                                  (declared (op name))
                                  (t (let ((parameter (operator-parameter-from-arguments
                                                       name
                                                       (mapcar (lambda (node) (and node (ast-type node))) built)
                                                       inferred-expected)))
                                       (assert parameter () "Cannot infer the type of ~S in ~S." head form)
                                       (op name parameter)))))
                  (wanted (or declared (second (operator-type operator))))
                  (arguments (loop for node in built for raw in (rest form) for type in wanted
                                   collect (or node (term raw type)))))
             (assert (and (= (length arguments) (length wanted))
                          (every (lambda (node type) (equal type (ast-type node))) arguments wanted))
                     () "Ill-typed arguments in ~S: wanted ~S." form wanted)
             (apply #'app operator arguments))))))
