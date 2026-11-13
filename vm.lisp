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

(defun start-evaluation (expression inputs values)
  "An isolated, resumable machine. Its environment contains supplied arguments only."
  (%make-evaluation :inputs (input-alist inputs) :values values
                    :tasks (list (list :validate expression) (list :eval expression))))

(defun arithmetic-cost (name type values)
  "Unit arithmetic only for fixed primes <= 257; otherwise a bit-sensitive tariff."
  (if (and (gf-type-p type) (<= (second type) 257))
      1
      (let ((a (integer-width (first values)))
            (b (integer-width (second values))))
        (+ (if (member name '(:* :/)) (* a b) (max a b))
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
      ((member name '(:+ :* :- :/ :<)) (arithmetic-cost name type values))
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
      ((:+ :* :- :/)
       (let* ((a (first values)) (b (second values))
              (result (ecase name
                        (:+ (+ a b)) (:* (* a b)) (:- (- a b))
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
       (let* ((items (first values)) (length (length items)))
         (nth (checked-position (second values) length) items)))
      (otherwise (execute-symbolic-primitive name type values)))))

(defun instruction-cost (state task)
  (ecase (first task)
    (:validate-program (syntax-work (second task)))
    ;; A :validate task checks the input values, and the expression too when it names one.
    (:validate
     (+ (if (rest task) (syntax-work (second task)) 0)
        (loop for spec in (evaluation-inputs state)
              for value in (evaluation-values state)
              sum (+ (integer-width (car spec)) (type-work (cdr spec))
                     (value-work value (cdr spec))))))
    (:eval (let ((expression (second task)))
             (if (lit-p expression)
                 (1+ (value-work (ast-value expression) (ast-type expression)))
                 1)))
    ((:branch :restore-env) 1)
    (:apply (primitive-cost (second task)
                            (reverse (subseq (evaluation-stack state) 0 (third task)))))))

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
            (push (execute-primitive operator ordered-values) (evaluation-stack state)))))))))

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

(defun compile-ast-fn (expression inputs)
  "Compile a pure, hole-free first-order primitive AST over INPUTS into a zero-allocation
host closure `(lambda (args) ...)`. Returns NIL when EXPRESSION calls defined functions,
symbolic `:code-*` operators, or contains holes, so callers fall back to `evaluate`."
  (let ((norm-inputs (input-alist inputs)))
    (when (and expression (ignore-errors (expression-type expression norm-inputs)))
      (labels ((build (node)
                 (let ((meta (ignore-errors (ensure-ast-meta node))))
                   (when meta
                     (case (ast-meta-kind meta)
                       (:lit
                        (let ((val (ast-meta-value meta)))
                          (if (consp val)
                              (lambda (args) (declare (ignore args)) (copy-tree val))
                              (lambda (args) (declare (ignore args)) val))))
                       (:var
                        (let* ((id (ast-meta-id meta))
                               (pos (position id norm-inputs :key #'car :test #'eql)))
                          (when pos
                            (lambda (args)
                              (let ((val (nth pos args)))
                                (when (eq val :unresolved)
                                  (error 'unresolved-evaluation :name :var :arguments (list id)))
                                val)))))
                       (:app
                        (let* ((operator (first node))
                               (name (and (operator-p operator) (operator-name operator)))
                               (type (and name (operator-operand-type operator)))
                               (subnodes (rest node)))
                          (unless (or (null name)
                                      (defined-function-p name)
                                      (member name '(:code-eval :code-kind :code-child :code-operator
                                                     :code-apply :code-match :code-bind :code-subst
                                                     :code-total :code-less)))
                            (let ((fns (mapcar #'build subnodes)))
                              (when (every #'identity fns)
                                (cond
                                  ((eq name :if)
                                   (destructuring-bind (cf yf nf) fns
                                     (lambda (args)
                                       (if (funcall cf args) (funcall yf args) (funcall nf args)))))
                                  ((and (eq name :length) (= 1 (length fns)))
                                   (let ((a1 (first fns)))
                                     (lambda (args) (length (funcall a1 args)))))
                                  ((and (eq name :=) (= 2 (length fns)))
                                   (let ((a1 (first fns)) (a2 (second fns)))
                                     (lambda (args) (equal (funcall a1 args) (funcall a2 args)))))
                                  ((and (eq name :<) (= 2 (length fns)))
                                   (let ((a1 (first fns)) (a2 (second fns)))
                                     (lambda (args) (< (funcall a1 args) (funcall a2 args)))))
                                  ((and (eq type :int) (member name '(:+ :- :*)) (= 2 (length fns)))
                                   (let ((a1 (first fns)) (a2 (second fns)))
                                     (ecase name
                                       (:+ (lambda (args) (+ (funcall a1 args) (funcall a2 args))))
                                       (:- (lambda (args) (- (funcall a1 args) (funcall a2 args))))
                                       (:* (lambda (args) (* (funcall a1 args) (funcall a2 args)))))))
                                  ((and (eq name :member) (= 2 (length fns)))
                                   (let ((a1 (first fns)) (a2 (second fns)))
                                     (lambda (args)
                                       (not (null (member (funcall a1 args) (funcall a2 args) :test #'equal))))))
                                  ((and (eq name :at) (= 2 (length fns)))
                                   (let ((a1 (first fns)) (a2 (second fns)))
                                     (lambda (args)
                                       (let* ((items (funcall a1 args))
                                              (idx (funcall a2 args)))
                                         (nth (checked-position idx (length items)) items)))))
                                  (t
                                   (lambda (args)
                                     (execute-primitive
                                      operator
                                      (mapcar (lambda (f) (funcall f args)) fns)))))))))))))))
        (build expression)))))

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
