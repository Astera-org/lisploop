(in-package #:lisploop)

(defconstant +tariff-version+ 2)

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
  values (remaining-cost 0))

(defun start-evaluation (expression inputs values)
  "An isolated, resumable machine. Its environment contains supplied arguments only."
  (%make-evaluation :inputs inputs :values values
                    :tasks (list (list :validate expression) (list :eval expression))))

(defun integer-width (value) (max 1 (integer-length (abs value))))

(defun value-work (value type)
  "One visit per value/container plus raw payload bits; independent of the codec."
  (1+ (case type
        (:int (1+ (integer-width value))) ; sign and magnitude
        (:index (integer-width value))
        (:bool 1)
        (otherwise
         (ecase (first type)
           (:gf (integer-width (1- (second type))))
           (:tuple (loop for item in value for part in (rest type) sum (value-work item part)))
           (:seq (loop for item in value sum (value-work item (second type)))))))))

(defun type-work (type)
  "Type-node visits and modulus payloads; no printed or compressed lengths."
  (if (atom type) 1
      (1+ (ecase (first type)
            (:gf (integer-width (second type)))
            (:tuple (reduce #'+ (rest type) :key #'type-work :initial-value 0))
            (:seq (type-work (second type)))
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
        (+ (if (eq name :*) (* a b) (max a b))
           (if (consp type) (expt (integer-length (second type)) 2) 0)))))

(defun primitive-cost (operator values)
  (let ((name (second operator)) (type (third operator)))
    (case name
      ((:+ :*) (arithmetic-cost name type values))
      (otherwise
       (1+ (loop for value in values
                 for input-type in (second (operator-type operator))
                 sum (value-work value input-type)))))))

(defun execute-primitive (operator values)
  (let ((name (second operator)) (type (third operator)))
    (case name
      ((:+ :*)
       (let ((result (if (eq name :+) (+ (first values) (second values))
                         (* (first values) (second values)))))
         (if (eq type :int) result (mod result (second type)))))
      (:= (equal (first values) (second values)))
      (:tuple values)
      (:member (not (null (member (first values) (second values) :test #'equal))))
      (:lookup
       (let ((entry (assoc (first values) (second values) :test #'equal)))
         (if entry (second entry) (error "No encoded lookup entry for ~S" (first values)))))
      (:gather
       (let ((items (coerce (first values) 'vector)))
         (mapcar (lambda (index) (aref items index)) (second values))))
      (otherwise (error "Unknown primitive ~S" name)))))

(defun instruction-cost (state task)
  (ecase (first task)
    (:validate (+ (syntax-work (second task))
                  (loop for spec in (evaluation-inputs state)
                        for value in (evaluation-values state)
                        sum (+ (integer-width (car spec)) (type-work (cdr spec))
                               (value-work value (cdr spec))))))
    (:eval (let ((expression (second task)))
             (if (eq (first expression) :lit)
                 (1+ (value-work (third expression) (second expression))) 1)))
    (:apply (primitive-cost (second task)
                            (reverse (subseq (evaluation-stack state) 0 (third task)))))))

(defun execute-instruction (state task)
  (ecase (first task)
    (:validate
     (let ((inputs (evaluation-inputs state)) (values (evaluation-values state)))
       (assert (= (length inputs) (length values)))
       (assert (every (lambda (spec value) (value-p value (cdr spec))) inputs values))
       (expression-type (second task) inputs)
       (setf (evaluation-environment state)
             (mapcar (lambda (spec value) (cons (car spec) (copy-tree value))) inputs values))))
    (:eval
     (let ((expression (second task)))
       (ecase (first expression)
         (:lit (push (third expression) (evaluation-stack state)))
         (:var
          (let ((binding (assoc (second expression) (evaluation-environment state))))
            (unless binding (error "Unavailable variable ~S" (second expression)))
            (push (cdr binding) (evaluation-stack state))))
         (:app
          (push (list :apply (second expression) (length (third expression)))
                (evaluation-tasks state))
          (dolist (argument (reverse (third expression)))
            (push (list :eval argument) (evaluation-tasks state)))))))
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
