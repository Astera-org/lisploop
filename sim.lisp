(in-package #:lisploop)

(defconstant +tariff-version+ 8)
(defconstant +simulator-version+ 5)

(defstruct ledger (total 0) (counts nil))

(defun charge (ledger category &optional (amount 1))
  (when ledger
    (incf (ledger-total ledger) amount)
    (let ((entry (assoc category (ledger-counts ledger))))
      (if entry (incf (cdr entry) amount)
          (push (cons category amount) (ledger-counts ledger)))))
  amount)

(defstruct (evaluation (:constructor %make-evaluation))
  (status :unknown) value error (work 0) tasks stack environment inputs
  values prepared-p (remaining-cost 0))

;;; Private preparation evidence, never a DSL value or a flag on raw evaluation.
;;; Own the syntax/schema; prepared execution must not expose their mutable conses.
(defstruct (validated-program (:constructor %make-validated-program))
  (expression nil :read-only t) (inputs nil :read-only t) (versions nil :read-only t))

(defun vm-versions () (list +encoding-version+ +tariff-version+ +simulator-version+))

(defun start-program-validation (expression inputs)
  "Snapshot and validate static code through the same prepaid, resumable VM."
  (%make-evaluation :tasks (list (list :validate-program (copy-tree expression) (copy-tree inputs)))))

(defun start-validated-evaluation (program values)
  "Reuse completed static validation; still validate/copy every new input value."
  (assert (and (validated-program-p program) (equal (validated-program-versions program) (vm-versions))))
  (%make-evaluation :inputs (validated-program-inputs program) :values values :prepared-p t
                    :tasks (list (list :validate-inputs) (list :eval (validated-program-expression program)))))

(defun start-evaluation (expression inputs values)
  "An isolated, resumable machine. Its environment contains supplied arguments only."
  (%make-evaluation :inputs inputs :values values
                    :tasks (list (list :validate expression) (list :eval expression))))

(defun integer-width (value) (max 1 (integer-length (abs value))))

(defun value-work (value type)
  "One visit per value/container plus raw payload bits; independent of the codec."
  (1+ (case type
        (:int (1+ (integer-width value))) ; sign and magnitude
        (:bool 1)
        (otherwise
         (ecase (first type)
           (:gf (integer-width (1- (second type))))
           (:tuple (loop for item in value for part in (rest type) sum (value-work item part)))
           (:seq (loop for item in value sum (value-work item (second type))))
           (:code (syntax-work value)))))))

(defun type-work (type)
  "Type-node visits and modulus payloads; no printed or compressed lengths."
  (if (atom type) 1
      (1+ (ecase (first type)
            (:gf (integer-width (second type)))
            (:tuple (reduce #'+ (rest type) :key #'type-work :initial-value 0))
            (:seq (type-work (second type)))
            (:code (+ (loop for input in (code-inputs type)
                           sum (+ (integer-width (car input)) (type-work (cdr input))))
                      (type-work (code-sort type))))
            (:fn (+ (reduce #'+ (second type) :key #'type-work :initial-value 0)
                    (type-work (third type))))))))

(defun syntax-work (expression)
  "AST/type visits and raw payload bits for construction, validation and copying."
  (1+ (ecase (first expression)
        (:lit (+ (type-work (second expression)) (value-work (third expression) (second expression))))
        ((:var :hole) (+ (integer-width (second expression)) (type-work (third expression))))
        (:op (type-work (third expression)))
        (:app (+ (syntax-work (second expression))
                 (reduce #'+ (third expression) :key #'syntax-work :initial-value 0))))))

(defun arithmetic-cost (name type values)
  "Unit arithmetic only for fixed primes <= 257; otherwise a bit-sensitive tariff."
  (if (and (consp type) (eq (first type) :gf) (<= (second type) 257))
      1
      (let ((a (integer-width (first values)))
            (b (integer-width (second values))))
        (+ (if (member name '(:* :/)) (* a b) (max a b))
           (if (consp type)
               (expt (integer-length (second type)) (if (eq name :/) 3 2)) 0)))))

(defun primitive-cost (operator values)
  (let ((name (second operator)) (type (third operator)))
    (when (member name *symbolic-primitives*)
      (return-from primitive-cost (symbolic-primitive-cost name type values)))
    (case name
      ((:+ :* :- :/) (arithmetic-cost name type values))
      (otherwise
       (+ 1 (loop for value in values
                  for input-type in (second (operator-type operator))
                  sum (value-work value input-type))
          ;; Prepay every bounds check, including on a failing gather. The sign
          ;; check costs one; the upper-bound comparison costs the larger width.
          (if (eq name :gather)
              (loop with width = (integer-width (length (first values)))
                    for index in (second values)
                    sum (1+ (max width (integer-width index))))
              0))))))

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

(defun execute-primitive (operator values)
  (let ((name (second operator)) (type (third operator)))
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
      (otherwise (if (member name *symbolic-primitives*) (execute-symbolic-primitive name type values)
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
             (if (eq (first expression) :lit)
                 (1+ (value-work (third expression) (second expression))) 1)))
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
     (let ((expression (second task)))
       (ecase (first expression)
         (:lit (push (if (evaluation-prepared-p state) (copy-tree (third expression)) (third expression))
                     (evaluation-stack state)))
         (:var
          (let ((binding (assoc (second expression) (evaluation-environment state))))
            (unless binding (error "Unavailable variable ~S" (second expression)))
            (push (cdr binding) (evaluation-stack state))))
         (:app
          (if (eq :if (second (second expression)))
              (destructuring-bind (condition yes no) (third expression)
                (push (list :branch yes no) (evaluation-tasks state))
                (push (list :eval condition) (evaluation-tasks state)))
              (progn
                (push (list :apply (second expression) (length (third expression)))
                      (evaluation-tasks state))
                (dolist (argument (reverse (third expression)))
                  (push (list :eval argument) (evaluation-tasks state)))))))))
    (:branch
     (push (list :eval (if (pop (evaluation-stack state)) (second task) (third task)))
           (evaluation-tasks state)))
    (:apply
     (let* ((values (loop repeat (third task) collect (pop (evaluation-stack state))))
            (result (execute-primitive (second task) (reverse values))))
       (push result (evaluation-stack state))))))

(defun advance-evaluation (state budget &optional ledger (category :simulation))
  "Spend at most BUDGET units, retaining unpaid instructions on interruption.
Host arithmetic executes atomically once prepaid; this is an abstract work meter,
not an operating-system wall-clock preemption facility.
The second value reports an error before any work was charged for its instruction,
so search can account for that failed validation even after earlier batched work."
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
  "Shared job accounting: charge even errors before an instruction can be priced.
Return the VM state and total charged work, including the diagnostic unit."
  (assert (plusp budget))
  (let ((before (evaluation-work state)))
    (multiple-value-bind (result unpaid) (advance-evaluation state budget ledger category)
      (let* ((spent (- (evaluation-work state) before))
             (diagnostic (if (or unpaid (zerop spent)) 1 0)))
        (when (plusp diagnostic) (charge ledger error-category diagnostic))
        (values result (+ spent diagnostic))))))
