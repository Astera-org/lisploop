(in-package #:lisploop)

;;; Module 3: vm.lisp
;;; Structural tariff, resumable homoiconic evaluator,
;;; and symbolic primitive execution. Simplification lives in requirements.lisp.

(defconstant +tariff-version+ 9)
(defconstant +simulator-version+ 5)

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

(defun vm-versions () (list +encoding-version+ +tariff-version+ +simulator-version+))

(defun start-program-validation (expression inputs)
  "Snapshot and validate static code through the same prepaid, resumable VM."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (%make-evaluation :tasks (list (list :validate-program (copy-tree expression) (copy-tree norm-inputs))))))

(defun start-validated-evaluation (program values)
  "Reuse completed static validation; still validate/copy every new input value."
  (assert (and (validated-program-p program) (equal (validated-program-versions program) (vm-versions))))
  (%make-evaluation :inputs (validated-program-inputs program) :values values :prepared-p t
                    :tasks (list (list :validate-inputs) (list :eval (validated-program-expression program)))))

(defun start-evaluation (expression inputs values)
  "An isolated, resumable machine. Its environment contains supplied arguments only."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (%make-evaluation :inputs norm-inputs :values values
                      :tasks (list (list :validate expression) (list :eval expression)))))

(defun arithmetic-cost (name type values)
  "Unit arithmetic only for fixed primes <= 257; otherwise a bit-sensitive tariff."
  (if (and (consp type) (eq (first type) :gf) (<= (second type) 257))
      1
      (let ((a (integer-width (first values)))
            (b (integer-width (second values))))
        (+ (if (member name '(:* :/)) (* a b) (max a b))
           (if (consp type)
               (expt (integer-length (second type)) (if (eq name :/) 3 2)) 0)))))

(defun expression-pattern (expression)
  (ecase (ast-kind expression)
    (:var (hole (ast-id expression) (ast-type expression)))
    (:app (apply #'app (first expression) (mapcar #'expression-pattern (rest expression))))
    ((:lit :op :hole) expression)))

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

(defun symbolic-primitive-cost (name type values)
  "Prepay traversal/copying, including nested substitutions and failed matches."
  (let* ((weights (mapcar #'value-work values (second (symbolic-operator-signature name type))))
         (base (1+ (reduce #'+ weights))))
    (case name
      ((:code-match :code-bind :code-subst) (+ base (* (first weights) (second weights))))
      (:code-less (* 4 (+ base (type-work type))))
      (otherwise base))))

(defun primitive-cost (operator values)
  (let ((name (operator-name operator))
        (type (operator-operand-type operator)))
    (when (member name *symbolic-primitives*)
      (return-from primitive-cost (symbolic-primitive-cost name type values)))
    (case name
      ((:+ :* :- :/) (arithmetic-cost name type values))
      (otherwise
       (+ 1 (loop for value in values
                  for input-type in (second (operator-type operator))
                  sum (value-work value input-type))
          (case name
            (:gather
             (loop with width = (integer-width (length (first values)))
                   for index in (second values)
                   sum (1+ (max width (integer-width index)))))
            (:at
             (let ((width (integer-width (length (first values))))
                   (index (second values)))
               (1+ (max width (integer-width index)))))
            (otherwise 0)))))))

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
     (instantiate (first values)
                  (mapcar (lambda (input value) (cons (car input) value))
                          (code-inputs (second type)) (second values)) :var))))

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
      (:= (equal (first values) (second values)))
      (:tuple values)
      (:concat (loop for part in (first values) append (copy-list part)))
      (:member (not (null (member (first values) (second values) :test #'equal))))
      (:lookup
       (let ((entry (assoc (first values) (second values) :test #'equal)))
         (if entry (second entry) (error "No encoded lookup entry for ~S" (first values)))))
      (:gather
       (let* ((items (coerce (first values) 'vector)) (length (length items)))
         (mapcar (lambda (index) (aref items (checked-position index length))) (second values))))
      (:at
       (let* ((items (first values)) (length (length items)))
         (nth (checked-position (second values) length) items)))
      (otherwise (if (member name *symbolic-primitives*)
                     (execute-symbolic-primitive name type values)
                     (error "Unknown primitive ~S" name))))))

(defun instruction-cost (state task)
  (ecase (first task)
    (:validate-program (syntax-work (second task)))
    ((:validate :validate-inputs)
     (+ (if (eq :validate (first task)) (syntax-work (second task)) 0)
        (loop for spec in (evaluation-inputs state)
              for value in (evaluation-values state)
              sum (+ (integer-width (car spec)) (type-work (cdr spec))
                     (value-work value (cdr spec))))))
    (:eval (let ((expression (second task)))
             (if (lit-p expression)
                 (1+ (value-work (ast-value expression) (ast-type expression)))
                 1)))
    (:branch 1)
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
    ((:validate :validate-inputs)
     (let ((inputs (evaluation-inputs state)) (values (evaluation-values state)))
       (assert (= (length inputs) (length values)))
       (assert (every (lambda (spec value) (value-p value (cdr spec))) inputs values))
       (when (eq :validate (first task)) (expression-type (second task) inputs))
       (setf (evaluation-environment state)
             (mapcar (lambda (spec value) (cons (car spec) (copy-tree value))) inputs values))))
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
    (:apply
     (let* ((values (loop repeat (third task) collect (pop (evaluation-stack state))))
            (result (execute-primitive (second task) (reverse values))))
       (push result (evaluation-stack state))))))

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
          (let ((spent (min budget (evaluation-remaining-cost state))))
            (decf budget spent)
            (decf (evaluation-remaining-cost state) spent)
            (incf (evaluation-work state) spent)
            (charge ledger category spent)
            (setf instruction-paid-p t))
          (when (zerop (evaluation-remaining-cost state))
            (pop (evaluation-tasks state))
            (execute-instruction state task)
            (unless (evaluation-tasks state)
              (assert (= (length (evaluation-stack state)) 1))
              (setf (evaluation-status state) :value
                    (evaluation-value state) (first (evaluation-stack state)))))))
      (error (condition)
        (setf (evaluation-status state) :error
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
