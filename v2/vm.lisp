(in-package #:lisploop)

;;; Module 3: vm.lisp
;;; Structural tariff, resumable homoiconic evaluator,
;;; and symbolic primitive execution. Simplification lives in requirements.lisp.

(defconstant +tariff-version+ 10)
(defconstant +simulator-version+ 6)

(defstruct ledger (total 0) (counts nil))

(defvar *work-limit-ledger* nil)
(defvar *work-limit* nil)
(defvar *work-limit-tag* nil)

(defun remaining-work (ledger limit)
  (max 0 (min limit (if (and (eq ledger *work-limit-ledger*) *work-limit*)
                        (- *work-limit* (ledger-total ledger)) limit))))

(defmacro with-work-limit ((ledger limit cutoff) &body body)
  "Bound synchronous orchestration, including nested preparation/checking.
LIMIT is additional work for this invocation; nested calls cannot renew it.
CUTOFF is returned on interruption. Resumable controllers use explicit state."
  (let ((l (gensym)) (end (gensym)) (tag (gensym)) (answer (gensym)))
    `(let* ((,l ,ledger)
            (,end (+ (ledger-total ,l) (remaining-work ,l ,limit)))
            (,tag (gensym))
            (,answer
              (let ((*work-limit-ledger* ,l) (*work-limit* ,end) (*work-limit-tag* ,tag))
                (catch ,tag (cons :complete (multiple-value-list (progn ,@body)))))))
       (if (eq :complete (car ,answer)) (values-list (cdr ,answer)) ,cutoff))))

(defmacro pay-debt (place budget ledger category)
  "Charge up to BUDGET units of the staged work held in PLACE to LEDGER under CATEGORY,
reduce PLACE by that amount, and return it. A job publishes staged results once PLACE is zero."
  (let ((spent (gensym "SPENT")))
    `(let ((,spent (min ,budget ,place)))
       (charge ,ledger ,category ,spent)
       (decf ,place ,spent)
       ,spent)))

(defun charge (ledger category &optional (amount 1))
  (assert (and (integerp amount) (>= amount 0)))
  (when (and ledger (eq ledger *work-limit-ledger*) *work-limit*
             (> (+ (ledger-total ledger) amount) *work-limit*))
    (let ((remaining (- *work-limit* (ledger-total ledger))))
      (when (plusp remaining) (charge ledger category remaining)))
    (throw *work-limit-tag* '(:cutoff)))
  (when ledger
    (incf (ledger-total ledger) amount)
    (let ((entry (assoc category (ledger-counts ledger))))
      (if entry (incf (cdr entry) amount)
          (push (cons category amount) (ledger-counts ledger)))))
  amount)

;;; Resumable VM Evaluation
(defstruct (evaluation (:constructor %make-evaluation))
  (status :unknown) value error (work 0) tasks stack environment inputs
  values prepared-p (remaining-cost 0))

;;; Private preparation evidence, never a DSL value or a flag on raw evaluation.
(defstruct (validated-program (:constructor %make-validated-program))
  (expression nil :read-only t) (inputs nil :read-only t) (versions nil :read-only t))

(define-condition unresolved-evaluation (error)
  ((name :initarg :name :initform nil :reader unresolved-evaluation-name)
   (arguments :initarg :arguments :initform nil :reader unresolved-evaluation-arguments))
  (:report (lambda (condition stream)
             (format stream "Unresolved evaluation for ~S on ~S"
                     (unresolved-evaluation-name condition)
                     (unresolved-evaluation-arguments condition)))))

(defun vm-versions ()
  (list +encoding-version+ +tariff-version+ +simulator-version+ *function-library-version*))

(defun start-program-validation (expression inputs)
  "Snapshot and validate static code through the same prepaid, resumable VM."
  (%make-evaluation :tasks (list (list :validate-program (copy-tree expression)
                                       (copy-tree (input-alist inputs))))))

(defun start-validated-evaluation (program values)
  "Reuse completed static validation; still validate/copy every new input value."
  (assert (and (validated-program-p program) (equal (validated-program-versions program) (vm-versions))))
  (%make-evaluation :inputs (validated-program-inputs program) :values values :prepared-p t
                    :tasks (list (list :validate) (list :eval (validated-program-expression program)))))

(defparameter *closure-evaluation* t
  "When true, `start-evaluation` runs an expression that `expression-closure` accepts as a host
closure and returns an evaluation that only has to be paid for (`settled-evaluation`). When
nil every evaluation is interpreted. Either way an evaluation reports the same status,
value, error and work, however its budget is sliced.")

(defun start-evaluation (expression inputs values)
  "An isolated, resumable machine. Its environment contains supplied arguments only."
  (let ((inputs (input-alist inputs)))
    (or (and *closure-evaluation* (settled-evaluation expression inputs values))
        (%make-evaluation :inputs inputs :values values
                          :tasks (list (list :validate expression) (list :eval expression))))))

(defun arithmetic-cost (name type values)
  "Unit arithmetic only for fixed primes <= 257; otherwise a bit-sensitive tariff."
  (if (and (gf-type-p type) (<= (second type) 257))
      1
      (let ((a (integer-width (first values)))
            (b (integer-width (second values))))
        (+ (if (member name '(:* :/ :mod)) (* a b) (max a b))
           (if (consp type)
               (expt (integer-length (second type)) (if (eq name :/) 3 2)) 0)))))

(defun expression-pattern (expression)
  "EXPRESSION with each variable turned into the hole of the same id and type."
  (map-ast (lambda (node meta)
             (declare (ignore node))
             (when (eq :var (ast-meta-kind meta))
               (hole (ast-meta-id meta) (ast-meta-type meta))))
           expression))

(defvar *last-code-match* nil
  "Single-entry memo cache (pattern source scope bindings matched) so :code-bind reuses :code-match.")

(defun match-code (pattern source source-type)
  (let ((scope (code-inputs source-type)))
    (if (and *last-code-match*
             (eq (first *last-code-match*) pattern)
             (eq (second *last-code-match*) source)
             (equal (third *last-code-match*) scope))
        (values (fourth *last-code-match*) (fifth *last-code-match*))
        (multiple-value-bind (bindings matched)
            (match-pattern (expression-pattern pattern) source scope)
          (setf *last-code-match* (list pattern source scope bindings matched))
          (values bindings matched)))))

(defun primitive-cost (operator values)
  "The prepaid cost of applying OPERATOR to VALUES. A call pays one unit, its body being
charged as it runs, and arithmetic has its own tariff. Any other primitive pays one unit and
the work of its arguments, plus what its own traversal, copying or matching can add."
  (let ((name (operator-name operator))
        (type (operator-operand-type operator)))
    (cond
      ((or (eq name :code-eval) (defined-function-p name)) 1)
      ((member name '(:+ :* :- :/ :mod :<)) (arithmetic-cost name type values))
      (t
       (let* ((weights (mapcar #'value-work values (second (operator-type operator))))
              (base (1+ (reduce #'+ weights))))
         (case name
           ;; Nested substitutions and failed matches are paid for in advance.
           ((:code-match :code-bind :code-subst) (+ base (* (first weights) (second weights))))
           (:code-less (* 4 (+ base (type-work type))))
           ((:gather :at)
            ;; Each access compares an index with the length of the container.
            (let ((width (integer-width (length (first values)))))
              (+ base (loop for index in (if (eq name :at) (list (second values)) (second values))
                            sum (1+ (max width (integer-width index)))))))
           (otherwise base)))))))

(defun checked-position (index length)
  "An integer becomes a position only at access; no wrapping or negative offsets."
  (unless (and (integerp index) (<= 0 index) (< index length))
    (error "Sequence index ~S out of bounds for length ~D" index length))
  index)

(defun field-reciprocal (value modulus)
  "Extended Euclid inside the supplied division primitive, not learned inversion."
  (when (zerop value) (error "Division by zero"))
  (loop with r = modulus with next-r = value with s = 0 with next-s = 1
        while (plusp next-r) do
          (let ((q (truncate r next-r)))
            (psetf r next-r next-r (- r (* q next-r))
                   s next-s next-s (- s (* q next-s))))
        finally (return (mod s modulus))))

(defun execute-symbolic-primitive (name type values)
  (case name
    (:code-kind (ecase (ast-kind (first values)) (:var 0) (:lit 1) (:app 2) (:op 3)))
    (:code-total (not (null (provably-total-p (first values)))))
    (:code-less (not (null (expression-less-p (first values) (second values) (code-inputs type)))))
    (:code-operator
     (let ((source (first values)))
       (assert (and (app-p source) (equal (operator-type (first source)) (code-sort type))))
       (first source)))
    (:code-apply (apply #'app (first values) (copy-list (second values))))
    (:code-child
     (let ((source (first values)) (index (second values)))
       (assert (app-p source))
       (checked-position index (length (rest source)))
       (let ((child (nth index (rest source))))
         (assert (value-p child (third type)))
         (copy-tree child))))
    (:code-match (nth-value 1 (match-code (first values) (second values) (third type))))
    (:code-bind
     (multiple-value-bind (bindings matched) (match-code (first values) (second values) (third type))
       (let ((entry (assoc (third values) bindings)))
         (assert (and matched entry (value-p (cdr entry) (fourth type))))
         (copy-tree (cdr entry)))))
    (:code-subst
     (let ((inputs (code-inputs (second type)))
           (binding-types (rest (third type)))
           (out-type (fourth type)))
       (instantiate (first values)
                    (loop for (id . input-type) in inputs
                          for b-type in binding-types
                          for value in (second values)
                          collect (cons id (if (code-subst-code-binding-p b-type out-type input-type)
                                               value
                                               (lit input-type value))))
                    :var)))
    (otherwise (error "Unknown primitive ~S" name))))

(defun execute-primitive (operator values)
  (let ((name (operator-name operator))
        (type (operator-operand-type operator)))
    (case name
      ((:+ :* :- :/ :mod)
       (let* ((a (first values)) (b (second values))
              (result (ecase name
                        (:+ (+ a b)) (:* (* a b)) (:- (- a b))
                        ;; The modulus takes the sign of its divisor: an index stays in range.
                        (:mod (mod a b))
                        (:/ (if (eq type :int) (truncate a b)
                                (* a (field-reciprocal b (second type))))))))
         (if (eq type :int) result (mod result (second type)))))
      (:< (< (first values) (second values)))
      (:= (equal (first values) (second values)))
      (:tuple values)
      (:cons (cons (copy-tree (first values)) (copy-list (second values))))
      (:tail
       (let ((items (first values)))
         (when (null items)
           (error "Cannot take :tail of empty sequence"))
         (copy-list (rest items))))
      (:length (length (first values)))
      (:concat (loop for part in (first values) append (copy-list part)))
      (:member (not (null (member (first values) (second values) :test #'equal))))
      (:lookup
       (let ((entry (assoc (first values) (second values) :test #'equal)))
         (if entry
             (second entry)
             (error "No encoded lookup entry for ~S" (first values)))))
      (:gather
       (let* ((items (coerce (first values) 'vector)) (length (length items)))
         (mapcar (lambda (index) (aref items (checked-position index length))) (second values))))
      (:at
       (let* ((items (first values))
              (index (checked-position (second values) (length items)))
              (elem (nth index items))
              (container-type (at-container-type type)))
         (when (tuple-type-p container-type)
           (let ((slot-type (nth index (rest container-type)))
                 (expected-type (third (operator-type operator))))
             (unless (equal slot-type expected-type)
               (error "Tuple slot ~D has type ~S, expected ~S"
                      index slot-type expected-type))))
         elem))
      (otherwise (execute-symbolic-primitive name type values)))))

(defun validation-work (expression inputs values)
  "What a :validate instruction costs: the syntax of EXPRESSION, when it checks one, and
the declaration and the value of every input."
  (+ (if expression (syntax-work expression) 0)
     (loop for spec in inputs
           for value in values
           sum (+ (integer-width (car spec)) (type-work (cdr spec))
                  (value-work value (cdr spec))))))

(defun instruction-cost (state task)
  (ecase (first task)
    (:validate-program (syntax-work (second task)))
    ;; A :validate task checks the input values, and the expression too when it names one.
    (:validate (validation-work (second task) (evaluation-inputs state) (evaluation-values state)))
    (:eval (let ((expression (second task)))
             (if (lit-p expression)
                 (1+ (value-work (ast-value expression) (ast-type expression)))
                 1)))
    ((:branch :restore-env) 1)
    (:apply (primitive-cost (second task)
                            (reverse (subseq (evaluation-stack state) 0 (third task)))))
    ;; A closure has already run this evaluation: what is left is to pay for it.
    (:settle (second task))))

(defun execute-instruction (state task)
  (ecase (first task)
    (:validate-program
     (let ((expression (second task)) (inputs (third task)))
       (assert (valid-inputs-p inputs))
       (expression-type expression inputs)
       (push (%make-validated-program :expression expression :inputs inputs :versions (vm-versions))
             (evaluation-stack state))))
    (:validate
     (let ((inputs (evaluation-inputs state)) (values (evaluation-values state)))
       (assert (= (length inputs) (length values)))
       (assert (every (lambda (spec value) (or (eq value :unresolved) (value-p value (cdr spec))))
                      inputs values))
       (when (rest task) (expression-type (second task) inputs))
       (setf (evaluation-environment state)
             (bind-inputs inputs (mapcar #'copy-tree values)))))
    (:eval
     (let* ((expression (second task))
            (meta (ensure-ast-meta expression)))
       (ecase (ast-meta-kind meta)
         (:lit (push (if (evaluation-prepared-p state)
                         (copy-tree (ast-meta-value meta))
                         (ast-meta-value meta))
                     (evaluation-stack state)))
         (:var
          (let ((binding (assoc (ast-meta-id meta) (evaluation-environment state))))
            (unless binding (error "Unavailable variable ~S" (ast-meta-id meta)))
            (when (eq :unresolved (cdr binding))
              (error 'unresolved-evaluation :name :var :arguments (list (ast-meta-id meta))))
            (push (cdr binding) (evaluation-stack state))))
         (:app
          (let ((operator (first expression))
                (args (rest expression)))
            (if (eq :if (operator-name operator))
                (destructuring-bind (condition yes no) args
                  (push (list :branch yes no) (evaluation-tasks state))
                  (push (list :eval condition) (evaluation-tasks state)))
                (progn
                  (push (list :apply operator (length args))
                        (evaluation-tasks state))
                  (dolist (argument (reverse args))
                    (push (list :eval argument) (evaluation-tasks state))))))))))
    (:branch
     (push (list :eval (if (pop (evaluation-stack state)) (second task) (third task)))
           (evaluation-tasks state)))
    (:restore-env
     (setf (evaluation-environment state) (second task)))
    (:apply
     (let* ((operator (second task))
            (name (operator-name operator))
            (type (operator-operand-type operator))
            (ordered-values (reverse (loop repeat (third task)
                                           collect (pop (evaluation-stack state))))))
       (flet ((call-body (inputs args body)
                (push (list :restore-env (evaluation-environment state)) (evaluation-tasks state))
                (setf (evaluation-environment state) (bind-inputs inputs args))
                (push (list :eval body) (evaluation-tasks state))))
         (cond
           ((eq name :code-eval)
            (let ((code-expr (first ordered-values)))
              (assert (value-p code-expr type))
              (call-body (code-inputs type) (rest ordered-values) code-expr)))
           ((defined-function-p name)
            (let ((def (find-function-definition name)))
              (cond
                ((function-definition-oracle-table def)
                 (let ((entry (assoc ordered-values (function-definition-oracle-table def) :test #'equal)))
                   (if entry
                       (push (copy-tree (cdr entry)) (evaluation-stack state))
                       (error 'unresolved-evaluation :name name :arguments ordered-values))))
                ((function-definition-body def)
                 (call-body (function-definition-inputs def) ordered-values (function-definition-body def)))
                (t (error "Undefined body for function ~S" name)))))
           (t
            (push (execute-primitive operator ordered-values) (evaluation-stack state)))))))
    (:settle
     (destructuring-bind (status outcome) (cddr task)
       (ecase status
         (:value (push outcome (evaluation-stack state)))
         (:unresolved (error 'unresolved-evaluation :name (first outcome) :arguments (second outcome)))
         (:error (error "~A" outcome)))))))

(defun advance-evaluation (state budget &optional ledger (category :simulation))
  "Spend at most BUDGET units, retaining unpaid instructions on interruption."
  (assert (and (integerp budget) (>= budget 0)))
  (let ((instruction-paid-p nil) (unpaid-error-p nil))
    (handler-case
      (loop while (and (plusp budget) (eq (evaluation-status state) :unknown)) do
        (setf instruction-paid-p nil)
        (let ((task (first (evaluation-tasks state))))
          (when (zerop (evaluation-remaining-cost state))
            (setf (evaluation-remaining-cost state) (instruction-cost state task)))
          (let ((spent (pay-debt (evaluation-remaining-cost state) budget ledger category)))
            (decf budget spent)
            (incf (evaluation-work state) spent)
            (setf instruction-paid-p t))
          (when (zerop (evaluation-remaining-cost state))
            (pop (evaluation-tasks state))
            (execute-instruction state task)
            (unless (evaluation-tasks state)
              (assert (= (length (evaluation-stack state)) 1))
              (setf (evaluation-status state) :value
                    (evaluation-value state) (first (evaluation-stack state)))))))
      (error (condition)
        (setf (evaluation-status state) (if (typep condition 'unresolved-evaluation) :unresolved :error)
              (evaluation-error state) (princ-to-string condition)
              unpaid-error-p (not instruction-paid-p))))
    (values state unpaid-error-p)))

(defun evaluate (expression inputs values &key (budget 1000000) ledger)
  (advance-evaluation (start-evaluation expression inputs values) budget ledger))

(defun advance-accounted-evaluation (state budget ledger category error-category)
  "Shared job accounting: charge even errors before an instruction can be priced."
  (assert (plusp budget))
  (let ((before (evaluation-work state)))
    (multiple-value-bind (result unpaid) (advance-evaluation state budget ledger category)
      (let* ((spent (- (evaluation-work state) before))
             (diagnostic (if (or unpaid (zerop spent)) 1 0)))
        (when (plusp diagnostic) (charge ledger error-category diagnostic))
        (values result (+ spent diagnostic))))))

;;; Derived Fast Executable Closures for Symbolic Library ASTs

(defstruct (entry-executable (:constructor %make-entry-executable))
  "Derived runtime execution cache for a `knowledge-entry`, kept in sync with its AST slots."
  expression
  guard
  auxiliary
  inputs
  (expr-cost 1 :type fixnum)
  (guard-cost 1 :type fixnum)
  (aux-cost 1 :type fixnum)
  expr-fn
  guard-fn
  aux-fn)

(defvar *closure-work* 0
  "While a closure of `expression-closure` runs, the work the VM would have charged so far
for the instructions the closure stands for. A caller that wants the count binds it.")

(defparameter *closure-limit* 32768
  "The most nodes whose closures `expression-closure` remembers before it starts afresh.")

(defvar *closures* (make-hash-table :test #'eq)
  "Node -> (scope . closure or nil): what `expression-closure` made of the nodes compiled
most recently, in the scope each was compiled in.")

(defvar *closures-version* nil
  "The `*function-library-version*` that `*closures*` holds closures for. No closure calls a
function, but whether quoted code that does is well typed depends on its definition.")

(defun compile-ast-fn (expression inputs)
  "The closure of EXPRESSION over INPUTS (`expression-closure`) for a caller that charges a
fixed cost for running it, or NIL. Such callers evaluate what has no closure in the VM, at
the VM's price; literal code is left to them as it always was, so their charges are the same."
  (and expression (not (contains-call-to-p expression :code-eval))
       (expression-closure expression inputs)))

(defun expression-closure (expression inputs)
  "Compile a hole-free AST over INPUTS that applies primitives only into a host closure
`(lambda (args) ...)` on the list of its input values. Returns NIL when EXPRESSION is
ill-typed, calls a defined function or a symbolic `:code-*` operator, or evaluates code that
is not a literal, so callers fall back to the VM. The closure computes what the VM
computes and fails where the VM fails, with the same condition. It adds to `*closure-work*`
what the VM charges for its :eval, :branch, :apply and :restore-env instructions, in the
VM's order, so that the count is the VM's at a failure as well as at a value.
The closure of every node is remembered with its scope (`*closures*`): an expression
evaluated on row after row is compiled once, and one built from parts already compiled, as
the enumerator's are, costs one closure more. A node is type-checked as it is compiled, by
the rules of `expression-type`."
  (let ((scope (input-alist inputs)))
    (labels ((closure (node scope)
               (let ((entry (gethash node *closures*)))
                 (unless (and entry (or (eq scope (car entry)) (equal scope (car entry))))
                   (when (>= (hash-table-count *closures*) *closure-limit*)
                     (clrhash *closures*))
                   (setf entry (cons scope (build node scope))
                         (gethash node *closures*) entry))
                 (cdr entry)))
             (closures (nodes types scope)
               ;; The closures of NODES if each has one and they have TYPES, else :none.
               (let ((parts (loop for node in nodes collect (closure node scope))))
                 (if (and (notany #'null parts) (equal types (mapcar #'ast-type nodes)))
                     parts
                     :none)))
             (build (node scope)
               (let ((meta (ignore-errors (ensure-ast-meta node))))
                 (case (and meta (ast-meta-kind meta))
                   (:lit
                    (let ((value (ast-meta-value meta)) (type (ast-meta-type meta)))
                      (when (and (valid-type-p type) (value-p value type))
                        (let ((cost (1+ (value-work value type))))
                          (lambda (args) (declare (ignore args)) (incf *closure-work* cost) value)))))
                   (:var
                    (let* ((id (ast-meta-id meta))
                           (position (position id scope :key #'car)))
                      (when (and position (equal (ast-meta-type meta) (cdr (nth position scope))))
                        (lambda (args)
                          (incf *closure-work*)
                          (let ((value (nth position args)))
                            (when (eq value :unresolved)
                              (error 'unresolved-evaluation :name :var :arguments (list id)))
                            value)))))
                   (:app
                    (let ((operator (ignore-errors (ensure-ast-meta (first node)))))
                      (when (and operator (eq :op (ast-meta-kind operator)))
                        (application (first node) (ast-meta-id operator) (ast-meta-type operator)
                                     (second (ast-meta-value operator)) (rest node) scope)))))))
             (application (operator name type argument-types arguments scope)
               (let ((parts (closures arguments argument-types scope)))
                 (cond
                   ((eq parts :none) nil)
                   ((eq name :if)
                    (destructuring-bind (condition yes no) parts
                      (lambda (args)
                        (incf *closure-work*)
                        (let ((test (funcall condition args)))
                          (incf *closure-work*) ; the :branch
                          (if test (funcall yes args) (funcall no args))))))
                   ;; Literal code is a let: its arguments are evaluated and bound, and its
                   ;; body runs as a closure over them. PARTS holds the code's own closure
                   ;; first, which stands for the :eval of the literal.
                   ((eq name :code-eval)
                    (let* ((code (first arguments))
                           (body (and (lit-p code) (closure (ast-value code) (code-inputs type)))))
                      (when body
                        (destructuring-bind (literal &rest bound) parts
                          (lambda (args)
                            (incf *closure-work*)
                            (funcall literal args)
                            (let ((values (loop for part in bound collect (funcall part args))))
                              (incf *closure-work*) ; the :apply
                              (prog1 (funcall body values)
                                (incf *closure-work*))))))))  ; the :restore-env
                   ((and (member name +operator-names+)
                         (not (member name '(:code-kind :code-child :code-operator :code-apply
                                             :code-match :code-bind :code-subst :code-total
                                             :code-less))))
                    ;; The :apply of a primitive, priced and run by the VM's own functions.
                    (lambda (args)
                      (incf *closure-work*)
                      (let ((values (loop for part in parts collect (funcall part args))))
                        (incf *closure-work* (primitive-cost operator values))
                        (execute-primitive operator values))))))))
      (unless (eql *closures-version* *function-library-version*)
        (clrhash *closures*)
        (setf *closures-version* *function-library-version*))
      (and expression (closure expression scope)))))

(defun settled-evaluation (expression inputs values)
  "EXPRESSION run to its end on VALUES by its closure, as an evaluation with one instruction
left, :settle. The instruction costs what the VM's instructions would have cost up to the
same end, and once paid it yields the closure's value or fails as the closure did; so the
evaluation is paid for, cut off and resumed exactly as an interpreted one. Returns nil when
EXPRESSION has no closure or VALUES are not values of INPUTS, which the VM reports itself."
  (let ((closure (expression-closure expression inputs)))
    (when (and closure
               (= (length inputs) (length values))
               (every (lambda (spec value) (or (eq value :unresolved) (value-p value (cdr spec))))
                      inputs values))
      (let ((*closure-work* (validation-work expression inputs values)))
        (multiple-value-bind (status outcome)
            (handler-case (let ((value (funcall closure values)))
                            ;; As in the VM, the value shares nothing with the caller's VALUES.
                            (values :value (if (consp value) (copy-tree value) value)))
              (unresolved-evaluation (condition)
                (values :unresolved (list (unresolved-evaluation-name condition)
                                          (unresolved-evaluation-arguments condition))))
              (error (condition) (values :error (princ-to-string condition))))
          (%make-evaluation :inputs inputs :values values
                            :tasks (list (list :settle *closure-work* status outcome))))))))

(defun sync-entry-executable (entry)
  "Compile and cache synchronized fast closures for ENTRY's symbolic AST slots."
  (when (knowledge-entry-p entry)
    (let* ((inputs (knowledge-entry-inputs entry))
           (expr (knowledge-entry-expression entry))
           (guard (knowledge-entry-guard entry))
           (aux (knowledge-entry-auxiliary-code entry)))
      (setf (knowledge-entry-executable entry)
            (%make-entry-executable
             :expression expr
             :guard guard
             :auxiliary aux
             :inputs inputs
             :expr-cost (if expr (max 1 (or (ignore-errors (syntax-work expr)) 1)) 1)
             :guard-cost (if guard (max 1 (or (ignore-errors (syntax-work guard)) 1)) 1)
             :aux-cost (if aux (max 1 (or (ignore-errors (syntax-work aux)) 1)) 1)
             :expr-fn (compile-ast-fn expr inputs)
             :guard-fn (compile-ast-fn guard inputs)
             :aux-fn (compile-ast-fn aux inputs))))))

(defun ensure-entry-executable (entry)
  "Return ENTRY's `entry-executable`, rebuilding it automatically if uninitialized or if any
AST/input slot on ENTRY was mutated since compilation."
  (let ((exec (knowledge-entry-executable entry)))
    (if (and (entry-executable-p exec)
             (eq (knowledge-entry-expression entry) (entry-executable-expression exec))
             (eq (knowledge-entry-guard entry) (entry-executable-guard exec))
             (eq (knowledge-entry-auxiliary-code entry) (entry-executable-auxiliary exec))
             (equal (knowledge-entry-inputs entry) (entry-executable-inputs exec)))
        exec
        (sync-entry-executable entry))))

(defun eval-entry-slot (entry slot args &key ledger (category :simulation) (check-types-p t))
  "Evaluate SLOT (`:expr`, `:guard`, or `:aux`) of ENTRY on ARGS via its synchronized
`entry-executable` closure (falling back to `evaluate` for general/recursive ASTs).
Returns `(VALUES value status error work)`."
  (let* ((exec (ensure-entry-executable entry))
         (inputs (entry-executable-inputs exec)))
    (multiple-value-bind (ast fn cost)
        (ecase slot
          (:expr (values (entry-executable-expression exec)
                         (entry-executable-expr-fn exec)
                         (entry-executable-expr-cost exec)))
          (:guard (values (entry-executable-guard exec)
                          (entry-executable-guard-fn exec)
                          (entry-executable-guard-cost exec)))
          (:aux (values (entry-executable-auxiliary exec)
                        (entry-executable-aux-fn exec)
                        (entry-executable-aux-cost exec))))
      (cond
        ((null ast) (values nil :empty nil 0))
        ((and check-types-p
              (not (and (= (length args) (length inputs))
                        (every (lambda (spec v) (or (eq v :unresolved) (value-p v (cdr spec))))
                               inputs args))))
         (values nil :type-mismatch nil 0))
        (fn
         (when ledger (charge ledger category cost))
         (handler-case
             (values (funcall fn args) :value nil cost)
           (unresolved-evaluation (c)
             (values nil :unresolved (princ-to-string c) cost))
           (error (c)
             (values nil :error (princ-to-string c) cost))))
        (t
         (let ((run (evaluate ast inputs args :ledger ledger)))
           (values (evaluation-value run) (evaluation-status run)
                   (evaluation-error run) (evaluation-work run))))))))

(defun consume-entry-executable (entry context ledger &key (slot :expr) guarded-p guard-default)
  "Consume ENTRY on CONTEXT using its synchronized `entry-executable` and return an `evaluation`."
  (let ((inputs (knowledge-entry-inputs entry)))
    (when (= (length context) (length inputs))
      (flet ((as-eval (val status err work)
               (%make-evaluation :status status :value val :error err :work work
                                 :inputs inputs :values context)))
        (if (not guarded-p)
            (multiple-value-bind (val status err work)
                (eval-entry-slot entry slot context :ledger ledger)
              (unless (eq status :empty)
                (as-eval val status err work)))
            (multiple-value-bind (gval gstatus gerr gwork)
                (eval-entry-slot entry :guard context :ledger ledger)
              (cond
                ((not (eq gstatus :value))
                 (when guard-default
                   (as-eval gval gstatus gerr gwork)))
                (gval
                 (multiple-value-bind (val status err work)
                     (eval-entry-slot entry slot context :ledger ledger)
                   (as-eval val status err (+ gwork work))))
                (guard-default
                 (as-eval (cdr guard-default) :value nil gwork)))))))))
