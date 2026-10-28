(in-package #:lisploop)

;;; An equation is ordinary DSL data. Its evidence is separate, scoped metadata.
(defstruct (law (:constructor %make-law)) domain inputs equation guard origin)

(defun make-law (domain inputs left right &key (guard (lit :bool t)) origin)
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (assert (= (length inputs) (length (remove-duplicates inputs :key #'car))))
  (assert (every (lambda (input) (member (cdr input) (list domain :bool) :test #'equal)) inputs))
  (let ((type (expression-type left inputs)))
    (assert (equal type (expression-type right inputs)))
    (assert (member type (list domain :bool) :test #'equal))
    (assert (eq :bool (expression-type guard inputs)))
    (%make-law :domain (copy-tree domain) :inputs (copy-tree inputs)
               :equation (copy-tree (app (op := type) left right))
               :guard (copy-tree guard) :origin (copy-tree origin))))

(defun law-statement (law)
  (app (op :if :bool) (law-guard law) (law-equation law) (lit :bool t)))

(defun law-snapshot (law)
  (list (copy-tree (law-domain law)) (encode-model (law-equation law) (law-inputs law))
        (encode-model (law-guard law) (law-inputs law))
        :typed-value +simulator-version+ +encoding-version+ +tariff-version+))

(defstruct (law-certificate (:constructor %make-law-certificate))
  snapshot (evidence :exhaustive-finite-domain) assignments active work)

(defstruct (law-validation (:constructor %make-law-validation))
  law snapshot (status :unknown) (phase :setup) (debt 0) (ledger (make-ledger))
  exhaustive-p samples (index 0) (count 0) (active 0) values evaluation
  certificate counterexample)

(defun finite-type-cardinality (type)
  (if (eq type :bool) 2
      (if (and (consp type) (eq (first type) :gf)) (second type)
          (error "No exhaustive validator for ~S" type))))

(defun start-law-validation (law &key (samples nil supplied-p))
  "Exhaust finite types, or test explicit assignments. Samples NEVER certify a law."
  (let* ((snapshot (law-snapshot law))
         (copy (make-law (law-domain law) (law-inputs law)
                         (first (third (law-equation law))) (second (third (law-equation law)))
                         :guard (law-guard law) :origin (law-origin law)))
         (count (if supplied-p (length samples)
                    (reduce #'* (law-inputs law) :key (lambda (input) (finite-type-cardinality (cdr input)))
                            :initial-value 1))))
    (dolist (values samples)
      (assert (= (length values) (length (law-inputs law))))
      (assert (every (lambda (value input) (value-p value (cdr input))) values (law-inputs law))))
    (%make-law-validation :law copy :snapshot snapshot
                          :debt (+ (syntax-work (law-equation law)) (syntax-work (law-guard law))
                                   (loop for values in samples sum
                                     (loop for value in values for input in (law-inputs law)
                                           sum (value-work value (cdr input)))))
                          :exhaustive-p (not supplied-p)
                          :samples (copy-tree samples) :count count)))

(defun law-assignment (state)
  (if (law-validation-exhaustive-p state)
      (let ((index (law-validation-index state)))
        (mapcar (lambda (input)
                  (let* ((type (cdr input)) (cardinality (finite-type-cardinality type))
                         (value (mod index cardinality)))
                    (setf index (floor index cardinality))
                    (if (eq type :bool) (= value 1) value)))
                (law-inputs (law-validation-law state))))
      (nth (law-validation-index state) (law-validation-samples state))))

(defun finish-law-validation (state)
  (assert (equalp (law-validation-snapshot state) (law-snapshot (law-validation-law state)))
          () "Law changed during validation")
  (setf (law-validation-status state)
        (cond ((zerop (law-validation-active state)) :vacuous)
              ((law-validation-exhaustive-p state) :validated)
              (t :conjecture)))
  (when (eq :validated (law-validation-status state))
    (setf (law-validation-certificate state)
          (%make-law-certificate :snapshot (copy-tree (law-validation-snapshot state))
                                 :assignments (law-validation-count state)
                                 :active (law-validation-active state)
                                 :work (ledger-total (law-validation-ledger state))))))

(defun law-validation-step (state budget)
  (let ((law (law-validation-law state)) (ledger (law-validation-ledger state)))
    (case (law-validation-phase state)
      (:setup
       (let ((spent (min budget (law-validation-debt state))))
         (charge ledger :law-setup spent) (decf (law-validation-debt state) spent))
       (when (zerop (law-validation-debt state)) (setf (law-validation-phase state) :row)))
      (:row
       (charge ledger :validation-scheduling)
       (if (= (law-validation-index state) (law-validation-count state))
           (finish-law-validation state)
           (setf (law-validation-values state) (law-assignment state)
                 (law-validation-evaluation state)
                 (start-evaluation (law-guard law) (law-inputs law) (law-validation-values state))
                 (law-validation-phase state) :guard)))
      (otherwise
       (let ((evaluation (law-validation-evaluation state)))
         (advance-accounted-evaluation evaluation budget ledger :law-checking :validation-error)
         (cond
           ((eq :unknown (evaluation-status evaluation)))
           ((or (eq :error (evaluation-status evaluation))
                (and (eq :equation (law-validation-phase state)) (not (evaluation-value evaluation))))
            (setf (law-validation-status state) :refuted
                  (law-validation-counterexample state)
                  (list :inputs (copy-list (law-validation-values state))
                        :phase (law-validation-phase state) :status (evaluation-status evaluation)
                        :error (evaluation-error evaluation))))
           ((and (eq :guard (law-validation-phase state)) (evaluation-value evaluation))
            (incf (law-validation-active state))
            (setf (law-validation-evaluation state)
                  (start-evaluation (law-equation law) (law-inputs law) (law-validation-values state))
                  (law-validation-phase state) :equation))
           (t (incf (law-validation-index state)) (setf (law-validation-phase state) :row))))))))

(defun resume-law-validation (state work-limit &key quantum)
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (assert (or (null quantum) (and (integerp quantum) (plusp quantum))))
  (loop while (and (eq :unknown (law-validation-status state))
                   (< (ledger-total (law-validation-ledger state)) work-limit))
        for remaining = (- work-limit (ledger-total (law-validation-ledger state)))
        do (law-validation-step state (if quantum (min quantum remaining) remaining)))
  state)

(defun retype-law (law domain)
  "A new conjecture in another domain; no certificate transfers with the syntax."
  (labels ((walk (tree)
             (cond ((equal tree (law-domain law)) (copy-tree domain))
                   ((consp tree) (cons (walk (car tree)) (walk (cdr tree)))) (t tree))))
    (let ((equation (walk (law-equation law))))
      (make-law domain (mapcar (lambda (input) (cons (car input) (walk (cdr input)))) (law-inputs law))
                (first (third equation)) (second (third equation))
                :guard (walk (law-guard law)) :origin (list :retyped-from (law-domain law))))))

(defstruct (rewrite-rule (:constructor %make-rewrite-rule)) inputs pattern replacement guard)
(defstruct (rewrite-library (:constructor %make-rewrite-library)) domain rules (setup-work 0))

(defun prepare-rewrite-library (validations domain)
  "Freeze checked rules. Integer samples, modified laws and cross-domain reuse fail."
  (let ((rules nil) (work 0))
    (dolist (validation validations)
      (let* ((law (law-validation-law validation)) (certificate (law-validation-certificate validation)))
        (assert (and certificate (eq :validated (law-validation-status validation))
                     (equal domain (law-domain law))
                     (eq :exhaustive-finite-domain (law-certificate-evidence certificate))
                     (equalp (law-certificate-snapshot certificate) (law-snapshot law)))
                () "Rewrite requires unchanged, current, exhaustive evidence in this domain")
        (incf work (+ (syntax-work (law-equation law)) (syntax-work (law-guard law))))
        (destructuring-bind (left right) (third (law-equation law))
          ;; Offer both directions; each concrete application must strictly decrease.
          (dolist (pair (list (list left right) (list right left)))
            (destructuring-bind (from to) pair
              (when (and (eq :app (first from))
                         (subsetp (append (expression-variables to) (expression-variables (law-guard law)))
                                  (expression-variables from)))
                (push (%make-rewrite-rule
                       :inputs (copy-tree (remove-if-not (lambda (input) (member (car input) (expression-variables from)))
                                                        (law-inputs law)))
                       :pattern (copy-tree from) :replacement (copy-tree to)
                       :guard (copy-tree (law-guard law))) rules)))))))
    (%make-rewrite-library :domain (copy-tree domain) :rules (nreverse rules) :setup-work work)))

(defun negate-predicate (expression)
  (app (op :if :bool) expression (lit :bool nil) (lit :bool t)))

(defun compile-rule-transformer (rule inputs)
  "Lower a frozen checked direction to an ordinary DSL program on quoted syntax.
Inputs are source code and established Boolean-code assumptions. No EVAL, host
callback, certificate lookup, or hidden substitutions occur in the program."
  (let* ((parameters (rewrite-rule-inputs rule))
         (sort (expression-type (rewrite-rule-pattern rule) parameters))
         (source-type (code-type inputs sort)) (guard-type (code-type inputs :bool))
         (pattern-type (code-type parameters sort))
         (source (var 0 source-type)) (assumptions (var 1 (sequence-type guard-type)))
         (pattern (lit pattern-type (rewrite-rule-pattern rule)))
         (binding-types (mapcar (lambda (parameter) (code-type inputs (cdr parameter))) parameters))
         (bindings (loop for parameter in parameters for type in binding-types collect
                     (app (op :code-bind (tuple-type pattern-type source-type type))
                          pattern source (lit :int (car parameter)))))
         (binding-tuple-type (apply #'tuple-type binding-types))
         (binding-tuple (apply #'app (op :tuple binding-tuple-type) bindings)))
    (flet ((fill-template (expression type)
             (let ((template-type (code-type parameters (code-sort type))))
               (app (op :code-subst (tuple-type template-type binding-tuple-type type))
                    (lit template-type expression) binding-tuple))))
      (let* ((replacement (fill-template (rewrite-rule-replacement rule) source-type))
             (guard (fill-template (rewrite-rule-guard rule) guard-type))
             (established (app (op :if :bool)
                               (app (op := guard-type) guard (lit guard-type (lit :bool t)))
                               (lit :bool t) (app (op :member guard-type) guard assumptions)))
             (result (app (op :if source-type) established
                          (app (op :if source-type) (app (op :code-less source-type) replacement source)
                               replacement source) source)))
        (loop for binding in (reverse bindings) for type in (reverse binding-types) do
          (setf result (app (op :if source-type) (app (op :code-total type) binding) result source)))
        (values (app (op :if source-type)
                     (app (op :code-match (tuple-type pattern-type source-type)) pattern source) result source)
                (list (cons 0 source-type) (cons 1 (sequence-type guard-type))))))))

(defstruct (rewriting (:constructor %make-rewriting))
  inputs library programs evaluation attempt tasks stack (setup-work 0)
  (debt 0) (work 0) (steps 0) (status :unknown) value)

(defun start-rewriting (expression inputs library)
  (expression-type expression inputs)
  (assert (every (lambda (input) (member (cdr input) (list :bool (rewrite-library-domain library)) :test #'equal)) inputs))
  (let ((programs (loop for rule in (rewrite-library-rules library) collect
                   (multiple-value-bind (model schema) (compile-rule-transformer rule inputs)
                     (list rule model schema)))))
    (%make-rewriting :inputs inputs :library library :programs programs
                     :setup-work (1+ (reduce #'+ programs :key (lambda (entry) (syntax-work (second entry))) :initial-value 0))
                     :tasks (list (list :setup nil nil) (list :walk expression nil)))))

(defun rewriting-push-try (state expression assumptions)
  (push (list :try expression assumptions
              (remove-if-not (lambda (rule) (equal (second expression) (second (rewrite-rule-pattern rule))))
                             (rewrite-library-rules (rewriting-library state))))
        (rewriting-tasks state)))

(defun execute-rewrite-task (state task)
  (destructuring-bind (kind expression assumptions &rest extra) task
    (ecase kind
      (:setup nil)
      (:walk
       (if (eq :app (first expression))
           (if (eq :if (second (second expression)))
               (progn (push (list :choose expression assumptions) (rewriting-tasks state))
                      (push (list :walk (first (third expression)) assumptions) (rewriting-tasks state)))
               (progn (push (list :rebuild expression assumptions) (rewriting-tasks state))
                      (dolist (child (reverse (third expression)))
                        (push (list :walk child assumptions) (rewriting-tasks state)))))
           (push expression (rewriting-stack state))))
      (:choose
       (let* ((condition (pop (rewriting-stack state))) (args (third expression)))
         (push (list :finish-if expression assumptions condition) (rewriting-tasks state))
         (push (list :walk (third args) (cons (negate-predicate condition) assumptions)) (rewriting-tasks state))
         (push (list :walk (second args) (cons condition assumptions)) (rewriting-tasks state))))
      (:finish-if
       (let ((no (pop (rewriting-stack state))) (yes (pop (rewriting-stack state))))
         (rewriting-push-try state (app (second expression) (first extra) yes no) assumptions)))
      (:rebuild
       (rewriting-push-try state
                           (apply #'app (second expression)
                                  (nreverse (loop repeat (length (third expression)) collect (pop (rewriting-stack state)))))
                           assumptions))
      (:try
       (let ((rules (first extra)))
         (if (null rules) (push expression (rewriting-stack state))
             (let ((program (assoc (first rules) (rewriting-programs state))))
               (setf (rewriting-attempt state) task
                     (rewriting-evaluation state)
                     (start-evaluation (second program) (third program) (list expression assumptions))))))))))

(defun finish-rewrite-evaluation (state)
  (let ((evaluation (rewriting-evaluation state)))
    (when (eq :error (evaluation-status evaluation))
      (error "Compiled rewrite failed: ~A" (evaluation-error evaluation)))
    (when (eq :value (evaluation-status evaluation))
      (destructuring-bind (kind expression assumptions rules) (rewriting-attempt state)
        (declare (ignore kind))
        (let ((replacement (evaluation-value evaluation)))
          (if (equal replacement expression)
              (push (list :try expression assumptions (rest rules)) (rewriting-tasks state))
              (progn (incf (rewriting-steps state))
                     (push (list :walk replacement assumptions) (rewriting-tasks state))))))
      (setf (rewriting-evaluation state) nil (rewriting-attempt state) nil))))

(defun advance-rewriting (state budget &optional ledger)
  (assert (and (integerp budget) (>= budget 0)))
  (loop while (and (plusp budget) (eq :unknown (rewriting-status state))) do
    (if (rewriting-evaluation state)
        (multiple-value-bind (evaluation spent)
            (advance-accounted-evaluation (rewriting-evaluation state) budget ledger :rewriting :rewriting)
          (declare (ignore evaluation))
          (decf budget spent) (incf (rewriting-work state) spent)
          (finish-rewrite-evaluation state))
        (progn
          (when (zerop (rewriting-debt state))
            (setf (rewriting-debt state) (if (eq :setup (first (first (rewriting-tasks state))))
                                           (rewriting-setup-work state) 1)))
          (let ((spent (min budget (rewriting-debt state))))
            (decf budget spent) (decf (rewriting-debt state) spent)
            (incf (rewriting-work state) spent) (charge ledger :rewriting spent))
          (when (zerop (rewriting-debt state)) (execute-rewrite-task state (pop (rewriting-tasks state))))))
    (unless (or (rewriting-tasks state) (rewriting-evaluation state))
      (assert (= 1 (length (rewriting-stack state))))
      (setf (rewriting-status state) :complete (rewriting-value state) (first (rewriting-stack state)))))
  state)
