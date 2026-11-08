(in-package #:lisploop)

;;; Module 7: laws.lisp
;;; Algebraic laws, exhaustive/sampled validation, guarded law discovery,
;;; S-expression rewriting, arithmetic solver discovery, and checker propagation.

(defstruct (law (:constructor %make-law)) domain inputs equation guard origin)

(defun law-lhs (law) (first (rest (law-equation law))))
(defun law-rhs (law) (second (rest (law-equation law))))

(defun law-type-p (type domain)
  "True when TYPE is DOMAIN, :BOOL, or a valid tuple of law types in DOMAIN."
  (and (valid-type-p type)
       (or (equal type domain)
           (eq type :bool)
           (and (consp type) (eq :tuple (first type))
                (every (lambda (part) (law-type-p part domain)) (rest type))))))

(defun finite-type-p (type)
  "True when TYPE is a finite enumerable type (:BOOL, (:GF p), or a tuple thereof)."
  (and (valid-type-p type)
       (or (eq type :bool)
           (and (consp type) (eq :gf (first type)))
           (and (consp type) (eq :tuple (first type))
                (every #'finite-type-p (rest type))))))

(defun make-law (domain inputs left right &key (guard (lit :bool t)) origin)
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (assert (= (length inputs) (length (remove-duplicates inputs :key #'car))))
  (assert (every (lambda (input) (law-type-p (cdr input) domain)) inputs))
  (let ((type (expression-type left inputs)))
    (assert (equal type (expression-type right inputs)))
    (assert (law-type-p type domain))
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
  (cond
    ((eq type :bool) 2)
    ((and (consp type) (eq (first type) :gf)) (second type))
    ((and (consp type) (eq (first type) :tuple))
     (reduce #'* (rest type) :key #'finite-type-cardinality :initial-value 1))
    (t (error "No exhaustive validator for ~S" type))))

(defun unrank-finite-value (type index)
  (cond
    ((eq type :bool)
     (multiple-value-bind (quotient remainder) (floor index 2)
       (values (= remainder 1) quotient)))
    ((and (consp type) (eq (first type) :gf))
     (multiple-value-bind (quotient remainder) (floor index (second type))
       (values remainder quotient)))
    ((and (consp type) (eq (first type) :tuple))
     (let ((cursor index))
       (values (mapcar (lambda (part)
                         (multiple-value-bind (value next) (unrank-finite-value part cursor)
                           (setf cursor next)
                           value))
                       (rest type))
               cursor)))
    (t (error "No exhaustive validator for ~S" type))))

(defun start-law-validation (law &key (samples nil supplied-p))
  "Exhaust finite types, or test explicit assignments. Samples NEVER certify a law."
  (let* ((snapshot (law-snapshot law))
         (eq-args (rest (law-equation law)))
         (copy (make-law (law-domain law) (law-inputs law)
                         (first eq-args) (second eq-args)
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

(defun law-assignment (state-or-inputs &optional (index 0))
  (if (law-validation-p state-or-inputs)
      (if (law-validation-exhaustive-p state-or-inputs)
          (law-assignment (law-inputs (law-validation-law state-or-inputs))
                          (law-validation-index state-or-inputs))
          (nth (law-validation-index state-or-inputs)
               (law-validation-samples state-or-inputs)))
      (let ((cursor index))
        (mapcar (lambda (input)
                  (multiple-value-bind (value next) (unrank-finite-value (cdr input) cursor)
                    (setf cursor next)
                    value))
                state-or-inputs))))

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
                  (list :inputs (copy-tree (law-validation-values state))
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

(defun retype-type (type old-domain new-domain)
  (cond
    ((equal type old-domain) (copy-tree new-domain))
    ((consp type) (cons (retype-type (car type) old-domain new-domain)
                        (retype-type (cdr type) old-domain new-domain)))
    (t type)))

(defun retype-value (value new-type)
  (cond
    ((and (consp new-type) (eq :gf (first new-type)) (integerp value))
     (mod value (second new-type)))
    ((and (consp new-type) (eq :tuple (first new-type)) (listp value))
     (mapcar #'retype-value value (rest new-type)))
    ((and (consp new-type) (eq :seq (first new-type)) (listp value))
     (mapcar (lambda (item) (retype-value item (second new-type))) value))
    (t value)))

(defun retype-expr (expr old-domain new-domain)
  (ecase (ast-kind expr)
    (:var (var (ast-id expr) (retype-type (ast-type expr) old-domain new-domain)))
    (:lit (let ((new-type (retype-type (ast-type expr) old-domain new-domain)))
            (lit new-type (retype-value (ast-value expr) new-type))))
    (:op (op (operator-name expr) (retype-type (operator-operand-type expr) old-domain new-domain)))
    (:hole (hole (ast-id expr) (retype-type (ast-type expr) old-domain new-domain)))
    (:app (let ((new-op (retype-expr (first expr) old-domain new-domain)))
            (if (operator-p new-op)
                (apply #'app new-op
                       (mapcar (lambda (arg expected-type)
                                 (if (and (eq old-domain :int) (equal expected-type :int))
                                     (copy-tree arg)
                                     (retype-expr arg old-domain new-domain)))
                               (rest expr) (second (operator-type new-op))))
                (apply #'app new-op
                       (mapcar (lambda (arg) (retype-expr arg old-domain new-domain)) (rest expr))))))))

(defun retype-law (law domain)
  "A new conjecture in another domain; no certificate transfers with the syntax."
  (let* ((old-domain (law-domain law))
         (eq-args (rest (law-equation law)))
         (new-inputs (mapcar (lambda (input)
                               (cons (car input) (retype-type (cdr input) old-domain domain)))
                             (law-inputs law))))
    (make-law domain new-inputs
              (retype-expr (first eq-args) old-domain domain)
              (retype-expr (second eq-args) old-domain domain)
              :guard (retype-expr (law-guard law) old-domain domain)
              :origin (list :retyped-from old-domain))))

(defun propose-observed-laws (job &key (guard (lit :bool t)) ledger)
  "Propose a spanning set of equalities per complete output bucket, not certificates."
  (let* ((scope (observation-job-scope job)) (language (observation-scope-language scope))
         (inputs (language-inputs language)) (laws nil))
    (dolist (bucket (reverse (observation-job-buckets job)))
      (let* ((members (reverse (observation-bucket-members bucket)))
             (first (observed-expression-expression (first members))))
        (dolist (member (rest members))
          (let ((other (observed-expression-expression member)))
            (charge ledger :law-proposal (+ (syntax-work first) (syntax-work other) (syntax-work guard)))
            (push (make-law (language-domain language) inputs other first :guard guard
                            :origin (list :observed-scope (observation-scope-id scope)
                                          :evidence :replayed-observations)) laws)))))
    (nreverse laws)))

;;; Guard Discovery & Support Frames

(defstruct (guard-problem (:constructor %make-guard-problem)) scope support frame equations)

(defun complete-outcomes-p (record)
  (and (member (observed-expression-status record) '(:complete :error))
       (= (length (observed-expression-outcomes record))
          (length (frame-rows (observation-scope-frame (observed-expression-scope record)))))
       (every (lambda (outcome) (member (observation-outcome-status outcome) '(:value :error)))
              (observed-expression-outcomes record))))

(defun observed-support (left right &optional ledger)
  "Exact row membership where both expressions return equal, same-typed values."
  (assert (eq (observed-expression-scope left) (observed-expression-scope right)))
  (assert (equal (observed-expression-type left) (observed-expression-type right)))
  (assert (and (complete-outcomes-p left) (complete-outcomes-p right)) ()
          "Support requires completed per-row outcomes; resume observation first")
  (loop with type = (observed-expression-type left)
        for a in (observed-expression-outcomes left)
        for b in (observed-expression-outcomes right) collect
          (progn
            (charge ledger :support-comparison
                    (+ 2 (if (eq :value (observation-outcome-status a))
                             (value-work (observation-outcome-value a) type) 0)
                         (if (eq :value (observation-outcome-status b))
                             (value-work (observation-outcome-value b) type) 0)))
            (and (eq :value (observation-outcome-status a))
                 (eq :value (observation-outcome-status b))
                 (equal (observation-outcome-value a) (observation-outcome-value b))))))

(defun propose-guard-problems (job &optional ledger)
  "Compare all pairs of finished expressions and group proper nonempty supports."
  (assert (observation-job-retain-outcomes-p job))
  (assert (and (eq :enumerate (observation-job-phase job))
               (observation-bound-complete-p job (observation-job-requested-bound job))) ()
          "Finish the requested observation bound before constructing guard problems")
  (let* ((scope (observation-job-scope job))
         (domain (language-domain (observation-scope-language scope)))
         (records (reverse (observation-job-records job)))
         (groups (make-hash-table :test #'equal)) (problems nil))
    (assert (every #'complete-outcomes-p records))
    (loop for tail on records for left = (first tail) do
      (dolist (right (rest tail))
        (charge ledger :support-pairs)
        (when (and (equal (observed-expression-type left) (observed-expression-type right))
                   (law-type-p (observed-expression-type left) domain))
          (let ((support (observed-support left right ledger)))
            (charge ledger :support-index (1+ (length support)))
            (when (and (some #'identity support) (not (every #'identity support)))
              (let ((problem (gethash support groups))
                    (a (observed-expression-expression left))
                    (b (observed-expression-expression right)))
                (unless problem
                  (setf problem (%make-guard-problem :scope scope :support support
                                                     :frame (support-frame scope support ledger))
                        (gethash support groups) problem)
                  (push problem problems))
                (charge ledger :guard-equations (+ (syntax-work a) (syntax-work b)))
                (push (list (copy-tree a) (copy-tree b)) (guard-problem-equations problem))))))))
    (dolist (problem problems)
      (setf (guard-problem-equations problem) (nreverse (guard-problem-equations problem))))
    (nreverse problems)))

(defun start-guard-search (problem language &key (call-id (incf *next-call-id*)) (run-weight 0))
  "Synthesize the complete observed support, including its false rows."
  (let ((source (observation-scope-language (guard-problem-scope problem))))
    (assert (equal (language-domain source) (language-domain language)))
    (assert (equal (language-inputs source) (language-inputs language)))
    (start-search (guard-problem-frame problem)
                  (snapshot-language language)
                  :call-id call-id :run-weight run-weight)))

(defun propose-guarded-laws (problem search &optional ledger)
  "Attach the best successful guard so far to each equation, as conjectures only."
  (assert (equalp (search-job-frame search) (guard-problem-frame problem)))
  (let* ((scope (guard-problem-scope problem)) (language (observation-scope-language scope))
         (best (search-job-best search)) (guard (and best (candidate-expression best))))
    (when best
      (loop for (left right) in (guard-problem-equations problem) collect
        (progn
          (charge ledger :law-proposal (+ (syntax-work left) (syntax-work right) (syntax-work guard)
                                          (length (guard-problem-support problem))))
          (make-law (language-domain language) (language-inputs language) left right :guard guard
                    :origin (list :observed-scope (observation-scope-id scope)
                                  :support (copy-list (guard-problem-support problem))
                                  :evidence :replayed-observations)))))))

;;; Rewrite Library & S-Expression Normalizer

(defstruct (rewrite-rule (:constructor %make-rewrite-rule)) inputs pattern replacement guard)
(defstruct (rewrite-library (:constructor %make-rewrite-library))
  domain (%rules nil :read-only t) (setup-work 0)
  (versions (vm-versions) :read-only t)
  (program-cache (make-hash-table :test #'equal) :read-only t))

(defun rewrite-library-rules (library)
  "Inspection copies; changing these cannot change the frozen library or its cache."
  (mapcar (lambda (rule)
            (%make-rewrite-rule :inputs (copy-tree (rewrite-rule-inputs rule))
                                :pattern (copy-tree (rewrite-rule-pattern rule))
                                :replacement (copy-tree (rewrite-rule-replacement rule))
                                :guard (copy-tree (rewrite-rule-guard rule))))
          (rewrite-library-%rules library)))

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
        (destructuring-bind (left right) (rest (law-equation law))
          (dolist (pair (list (list left right) (list right left)))
            (destructuring-bind (from to) pair
              (when (and (app-p from)
                         (subsetp (append (free-vars to) (free-vars (law-guard law)))
                                  (free-vars from)))
                (push (%make-rewrite-rule
                       :inputs (copy-tree (remove-if-not (lambda (input) (member (car input) (free-vars from)))
                                                         (law-inputs law)))
                       :pattern (copy-tree from) :replacement (copy-tree to)
                       :guard (copy-tree (law-guard law))) rules)))))))
    (%make-rewrite-library :domain (copy-tree domain) :%rules (nreverse rules) :setup-work work)))

(defun negate-predicate (expression)
  (app (op :if :bool) expression (lit :bool nil) (lit :bool t)))

(defun compile-rule-transformer (rule inputs)
  "Lower a frozen checked direction to an ordinary DSL program on quoted syntax."
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
  inputs library programs pending-programs cache-key evaluation attempt tasks stack (setup-work 0)
  (debt 0) (work 0) (steps 0) (status :unknown) value)

(defun rewrite-scope-type-p (type domain)
  "True when TYPE is a valid input type in a rewrite scope over DOMAIN."
  (and (valid-type-p type)
       (or (law-type-p type domain)
           (and (consp type) (eq :seq (first type))
                (rewrite-scope-type-p (second type) domain))
           (and (consp type) (eq :tuple (first type))
                (every (lambda (part) (rewrite-scope-type-p part domain)) (rest type))))))

(defun start-rewriting (expression inputs library)
  (assert (equal (rewrite-library-versions library) (vm-versions)) () "Stale rewrite library")
  (expression-type expression inputs)
  (assert (every (lambda (input) (rewrite-scope-type-p (cdr input) (rewrite-library-domain library))) inputs))
  (let* ((scope (copy-tree inputs)) (key (list (vm-versions) scope))
         (lookup-work (+ 1 (length (first key))
                         (loop for input in scope sum (+ (integer-width (car input)) (type-work (cdr input)))))))
    (multiple-value-bind (programs present-p) (gethash key (rewrite-library-program-cache library))
      (let ((pending (unless present-p
                       (loop for rule in (rewrite-library-%rules library) collect
                         (multiple-value-bind (model schema) (compile-rule-transformer rule scope)
                           (list rule model schema))))))
        (%make-rewriting :inputs scope :library library :programs programs :pending-programs pending :cache-key key
                         :setup-work (+ lookup-work
                                        (reduce #'+ pending :key (lambda (entry) (syntax-work (second entry))) :initial-value 0))
                         :tasks (list (list :setup nil nil) (list :walk expression nil)))))))

(defun prepare-next-rewrite-program (state)
  (let ((entry (first (rewriting-pending-programs state))))
    (if entry
        (setf (rewriting-evaluation state) (start-program-validation (second entry) (third entry)))
        (setf (gethash (rewriting-cache-key state) (rewrite-library-program-cache (rewriting-library state)))
              (rewriting-programs state)))))

(defun rewriting-push-try (state expression assumptions)
  (push (list :try expression assumptions
              (remove-if-not (lambda (rule) (equal (first expression) (first (rewrite-rule-pattern rule))))
                             (rewrite-library-%rules (rewriting-library state))))
        (rewriting-tasks state)))

(defun execute-rewrite-task (state task)
  (destructuring-bind (kind expression assumptions &rest extra) task
    (ecase kind
      (:setup (prepare-next-rewrite-program state))
      (:walk
       (if (app-p expression)
           (if (eq :if (operator-name (first expression)))
               (progn (push (list :choose expression assumptions) (rewriting-tasks state))
                      (push (list :walk (first (rest expression)) assumptions) (rewriting-tasks state)))
               (progn (push (list :rebuild expression assumptions) (rewriting-tasks state))
                      (dolist (child (reverse (rest expression)))
                        (push (list :walk child assumptions) (rewriting-tasks state)))))
           (push expression (rewriting-stack state))))
      (:choose
       (let* ((condition (pop (rewriting-stack state))) (args (rest expression)))
         (push (list :finish-if expression assumptions condition) (rewriting-tasks state))
         (push (list :walk (third args) (cons (negate-predicate condition) assumptions)) (rewriting-tasks state))
         (push (list :walk (second args) (cons condition assumptions)) (rewriting-tasks state))))
      (:finish-if
       (let ((no (pop (rewriting-stack state))) (yes (pop (rewriting-stack state))))
         (rewriting-push-try state (app (first expression) (first extra) yes no) assumptions)))
      (:rebuild
       (rewriting-push-try state
                           (apply #'app (first expression)
                                  (nreverse (loop repeat (length (rest expression)) collect (pop (rewriting-stack state)))))
                           assumptions))
      (:try
       (let ((rules (first extra)))
         (if (null rules) (push expression (rewriting-stack state))
             (let ((program (assoc (first rules) (rewriting-programs state))))
               (setf (rewriting-attempt state) task
                     (rewriting-evaluation state)
                     (start-validated-evaluation (cdr program) (list expression assumptions))))))))))

(defun finish-rewrite-evaluation (state)
  (let ((evaluation (rewriting-evaluation state)))
    (when (eq :error (evaluation-status evaluation))
      (error "Compiled rewrite failed: ~A" (evaluation-error evaluation)))
    (when (eq :value (evaluation-status evaluation))
      (when (rewriting-pending-programs state)
        (let ((entry (pop (rewriting-pending-programs state))))
          (push (cons (first entry) (evaluation-value evaluation)) (rewriting-programs state)))
        (setf (rewriting-evaluation state) nil)
        (when (null (rewriting-pending-programs state))
          (setf (rewriting-programs state) (nreverse (rewriting-programs state))))
        (prepare-next-rewrite-program state)
        (return-from finish-rewrite-evaluation))
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

;;; M4 Solver Discovery & Arithmetic Relations

(defstruct arithmetic-relation domain operator observations records guard guard-search ledger exhaustive-p)
(defstruct solve-discovery relation position frame observations recovery proposals search
  witness guard guard-searches ledger validation uniqueness)

(defun arithmetic-inputs (domain &optional (count 2))
  (loop for id below count collect (cons id domain)))

(defun arithmetic-application (operator position known unknown)
  (assert (member position '(0 1)))
  (if (zerop position) (app operator unknown known) (app operator known unknown)))

(defun literal-conditional (condition yes no)
  "Only fold literal Boolean conditions; no algebraic identity is supplied."
  (if (lit-p condition)
      (if (ast-value condition) yes no)
      (app (op :if :bool) condition yes no)))

(defun finish-observations (job bound work-limit)
  (let ((message (resume-observation-search job bound work-limit)))
    (assert (member (message-claim message) '(:bounded-exhaustion :replay-complete)) ()
            "Observation cutoff; resume the ordinary observation job before using its outcomes")
    job))

(defun search-membership-frame (frame domain &key (body-bound 35) (work-limit 10000000) expressions)
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (language (make-language domain inputs :operators (list (op := domain) (op :if :bool)) :literals '(0)))
         (job (if expressions (start-search frame language :expressions expressions) (start-search frame language)))
         (bound (if expressions (reduce #'max expressions :key (lambda (e) (description-size e inputs)))
                    (+ (header-size inputs :bool) body-bound))))
    (resume-search job bound work-limit)
    (assert (search-job-best job) () "Membership search unresolved at the supplied bounds")
    job))

(defun observe-arithmetic-values (domain operator values work-limit &optional expression)
  (let* ((inputs (arithmetic-inputs domain))
         (forward (or expression (app operator (var 0 domain) (var 1 domain))))
         (frame (make-frame (make-schema :inputs inputs :target domain)
                            (loop for a in values for block from 0 append
                              (loop for b in values for key from (* block (length values)) collect
                                (make-row :key key :known (list a b) :requirement (lit :bool t))))))
         (job (start-observation-search (make-observation-scope frame (make-language domain inputs :operators nil :literals nil))
                                        :expressions (list forward) :retain-outcomes t)))
    (finish-observations job (description-size forward inputs) work-limit)
    job))

(defun arithmetic-forward-records (observations ledger)
  (loop for row in (frame-rows (observation-scope-frame (observation-job-scope observations)))
        for outcome in (observed-expression-outcomes (first (observation-job-records observations)))
        do (charge ledger :forward-records)
        when (eq :value (observation-outcome-status outcome)) collect
          (cons (row-key row) (append (row-known row) (list (observation-outcome-value outcome))))))

(defun observe-arithmetic-relation (domain name values &key (work-limit 10000000))
  "Acquire forward executions, including errors, and learn their definedness guard."
  (let* ((operator (op name domain)) (ledger (make-ledger))
         (job (observe-arithmetic-values domain operator values work-limit))
         (forward (app operator (var 0 domain) (var 1 domain))))
    (let* ((record (find-observation job forward))
           (support (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome)))
                            (observed-expression-outcomes record)))
           (guard-job (search-membership-frame (support-frame (observation-job-scope job) support ledger) domain :work-limit work-limit))
           (records (arithmetic-forward-records job ledger)))
      (make-arithmetic-relation
       :domain domain :operator operator :observations job :records records :ledger ledger
       :guard (copy-tree (candidate-expression (search-job-best guard-job))) :guard-search guard-job
       :exhaustive-p (and (consp domain) (eq :gf (first domain))
                          (= (second domain) (length (remove-duplicates values)))
                          (every (lambda (value) (value-p value domain)) values))))))

(defun arithmetic-definedness (relation position known unknown)
  (let ((args (if (zerop position) (list unknown known) (list known unknown))))
    (instantiate (arithmetic-relation-guard relation) (list (cons 0 (first args)) (cons 1 (second args))) :var)))

(defun arithmetic-requirement (relation position)
  "R(k,c,z): a Boolean predicate describing the complete defined forward fiber."
  (let* ((domain (arithmetic-relation-domain relation))
         (k (var 0 domain)) (c (var 1 domain)) (z (var 2 domain)))
    (literal-conditional
     (arithmetic-definedness relation position k z)
     (app (op := domain) (arithmetic-application (arithmetic-relation-operator relation) position k z) c)
     (lit :bool nil))))

(defun orient-arithmetic-requirements (relation position query-values ledger)
  "Retain witnessed occurrences and add declared queries, without solving fibers."
  (let* ((domain (arithmetic-relation-domain relation)) (inputs (arithmetic-inputs domain))
         (oriented (orient-observations (list domain domain domain) (arithmetic-relation-records relation)
                                        (list (- 1 position) 2) (list position) :ledger ledger))
         (predicate (arithmetic-requirement relation position))
         (queries (append (loop for row in (frame-rows oriented) collect
                            (cons (list :forward (row-key row)) (row-known row)))
                          (loop for k in query-values for block from 0 append
                            (loop for c in query-values for i from (* block (length query-values))
                                  collect (list (list :query i) k c))))))
    (make-frame (make-schema :inputs inputs :target domain)
                (loop for (key k c) in queries collect
                  (let ((requirement (instantiate predicate (list (cons 0 (lit domain k)) (cons 1 (lit domain c))
                                                                  (cons 2 (var 0 domain))) :var)))
                    (charge ledger :relational-frame (syntax-work requirement))
                    (make-row :key key :known (list k c) :requirement requirement))))))

(defun covered-frame (frame support)
  (make-frame (frame-schema frame)
              (loop for row in (frame-rows frame) for keep in support when keep collect row)))

(defun discover-arithmetic-solver (relation position query-values &key
                                   (operators '(:+ :- :* :/)) (literals :all)
                                   (body-bound 16) (work-limit 100000000))
  "Observe a bounded program vocabulary, select maximum observed coverage, and
learn guards through Boolean frames."
  (let* ((domain (arithmetic-relation-domain relation)) (inputs (arithmetic-inputs domain))
         (ledger (make-ledger)) (frame (orient-arithmetic-requirements relation position query-values ledger))
         (language (make-language domain inputs :operators (mapcar (lambda (name) (op name domain)) operators) :literals literals))
         (observations (start-observation-search (make-observation-scope frame language) :retain-outcomes t))
         (requirement (arithmetic-requirement relation position)))
    (finish-observations observations (+ (header-size inputs domain) body-bound) work-limit)
    (let* ((records (remove-if-not (lambda (record) (equal domain (observed-expression-type record)))
                                   (reverse (observation-job-records observations))))
           (checks (mapcar (lambda (record)
                             (let ((model (instantiate requirement (list (cons 2 (observed-expression-expression record))) :var)))
                               (charge ledger :solve-proposal (syntax-work model)) model)) records))
           (recovery (start-observation-search (make-observation-scope frame language)
                                               :expressions (cons (lit :bool t) checks) :retain-outcomes t)))
      (finish-observations recovery (reduce #'max (cons (lit :bool t) checks) :key (lambda (e) (description-size e inputs))) work-limit)
      (let* ((truth (find-observation recovery (lit :bool t)))
             (proposals (loop for record in records for check in checks collect
                          (let ((mask (observed-support (find-observation recovery check) truth ledger))
                                (model (observed-expression-expression record)))
                            (charge ledger :solve-ranking (+ (length (frame-rows frame)) (syntax-work model)))
                            (list record mask (count t mask) (description-size model inputs)))))
             (ranked (stable-sort (copy-list proposals)
                                  (lambda (a b)
                                    (charge ledger :solve-ranking)
                                    (let ((ca (third a)) (cb (third b)))
                                      (if (/= ca cb) (> ca cb)
                                          (< (fourth a) (fourth b)))))))
             (support (second (first ranked))))
        (assert (some #'identity support) () "No acceptable witness at the declared bounds")
        (let* ((models (loop for (record mask) in proposals do (charge ledger :solve-selection (length mask))
                             when (equal mask support) collect (observed-expression-expression record)))
               (search (start-search (covered-frame frame support) language :expressions models)))
          (assert (eq :replay-complete (message-claim (resume-search search
                       (reduce #'max models :key (lambda (e) (description-size e inputs))) work-limit))))
          (let* ((witness (candidate-expression (search-job-best search)))
                 (record (find-observation observations witness))
                 (discovery (make-solve-discovery :relation relation :position position :frame frame :observations observations
                                                  :recovery recovery :proposals proposals :search search :witness witness :ledger ledger)))
            (learn-solver-guard discovery record support work-limit)
            discovery))))))

(defun learn-solver-guard (discovery record support work-limit)
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation))
         (inputs (arithmetic-inputs domain)) (ledger (solve-discovery-ledger discovery))
         (scope (observation-job-scope (solve-discovery-observations discovery)))
         (frame (solve-discovery-frame discovery))
         (defined (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome))) (observed-expression-outcomes record)))
         (domain-search (search-membership-frame (support-frame scope defined ledger) domain :work-limit work-limit))
         (witness (solve-discovery-witness discovery))
         (forward (arithmetic-application (arithmetic-relation-operator relation) (solve-discovery-position discovery) (var 0 domain) witness))
         (forward-job (start-observation-search (make-observation-scope frame (make-language domain inputs :operators nil :literals nil))
                                                :expressions (list forward) :retain-outcomes t)))
    (finish-observations forward-job (description-size forward inputs) work-limit)
    (let* ((outcomes (observed-expression-outcomes (find-observation forward-job forward)))
           (records (loop for row in (frame-rows frame) for outcome in outcomes
                          when (eq :value (observation-outcome-status outcome)) collect
                            (append (list (row-key row)) (row-known row)
                                    (list (observation-outcome-value outcome)
                                          (equal (second (row-known row)) (observation-outcome-value outcome))))))
           (features (orient-observations (list domain domain domain :bool) records '(0 1 2) '(3) :ledger ledger))
           (equality-search (search-membership-frame features domain :work-limit work-limit))
           (equality (compose-model (var 9 :bool) 9 (candidate-expression (search-job-best equality-search))
                                    (list (cons 0 (var 0 domain)) (cons 1 (var 1 domain)) (cons 2 forward)) ledger))
           (guard (literal-conditional (candidate-expression (search-job-best domain-search))
                                       (literal-conditional (arithmetic-definedness relation (solve-discovery-position discovery) (var 0 domain) witness)
                                                            equality (lit :bool nil)) (lit :bool nil)))
           (recheck (search-membership-frame (support-frame scope support ledger) domain :work-limit work-limit :expressions (list guard))))
      (setf (solve-discovery-guard discovery) guard
            (solve-discovery-guard-searches discovery) (list domain-search equality-search recheck forward-job)))))

(defun solve-witness-law (discovery)
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation)))
    (make-law domain (arithmetic-inputs domain)
              (instantiate (arithmetic-requirement relation (solve-discovery-position discovery))
                           (list (cons 2 (solve-discovery-witness discovery))) :var)
              (lit :bool t) :guard (solve-discovery-guard discovery))))

(defun solve-uniqueness-law (discovery)
  "Under G(k,c), R(k,c,z) iff z=q(k,c): validates the WHOLE fiber, not just a witness."
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation)))
    (make-law domain (arithmetic-inputs domain 3)
              (arithmetic-requirement relation (solve-discovery-position discovery))
              (app (op := domain) (var 2 domain) (solve-discovery-witness discovery))
              :guard (solve-discovery-guard discovery))))

(defun validate-arithmetic-solver (discovery &key (samples nil samples-p)
                                               (uniqueness-samples nil uniqueness-samples-p)
                                               (work-limit 100000000))
  (let* ((relation (solve-discovery-relation discovery))
         (domain (arithmetic-relation-domain relation))
         (position (solve-discovery-position discovery))
         (exhaustive-p (finite-type-p domain))
         (witness (solve-witness-law discovery))
         (unique (solve-uniqueness-law discovery))
         (eff-samples (cond (samples-p samples)
                            ((not exhaustive-p)
                             (remove-duplicates (mapcar #'row-known (frame-rows (solve-discovery-frame discovery)))
                                                :test #'equal))))
         (eff-unique (cond (uniqueness-samples-p uniqueness-samples)
                           ((not exhaustive-p)
                            (loop for record in (arithmetic-relation-records relation)
                                  collect (list (nth (1+ (- 1 position)) record)
                                                (fourth record)
                                                (nth (1+ position) record)))))))
    (setf (solve-discovery-validation discovery)
          (resume-law-validation (if (or samples-p (not exhaustive-p))
                                     (start-law-validation witness :samples eff-samples)
                                     (start-law-validation witness))
                                 work-limit)
          (solve-discovery-uniqueness discovery)
          (resume-law-validation (if (or uniqueness-samples-p (not exhaustive-p))
                                     (start-law-validation unique :samples eff-unique)
                                     (start-law-validation unique))
                                 work-limit))
    discovery))

(defun certified-solve-discovery-p (discovery)
  (and (arithmetic-relation-exhaustive-p (solve-discovery-relation discovery))
       (loop for state in (list (solve-discovery-validation discovery) (solve-discovery-uniqueness discovery))
             for expected in (list (solve-witness-law discovery) (solve-uniqueness-law discovery))
             always (and state (eq :validated (law-validation-status state))
                         (law-validation-certificate state)
                         (equalp (law-certificate-snapshot (law-validation-certificate state)) (law-snapshot expected))))))

(defun finish-accounted-evaluation (state ledger category error-msg &optional require-value-p)
  (advance-accounted-evaluation state 100000000 ledger category category)
  (assert (if require-value-p
              (eq :value (evaluation-status state))
              (not (eq :unknown (evaluation-status state))))
          () error-msg)
  state)

(defun run-algebra-program (model inputs values ledger category)
  (finish-accounted-evaluation (start-evaluation model inputs values)
                               ledger category "Algebra evaluation cutoff"))

;;; Checker-AST Propagation (Dual-Grade Propagators)

(defstruct propagation frame original fallback (narrowed 0) (suggested 0) (retained 0) (rejected 0) (ambiguous 0))
(defstruct arithmetic-propagator domain operator position witness guard certified-p unique-p)
(defstruct propagator-library rules (versions (vm-versions)) (matchers (make-hash-table :test #'equal)))

(defun current-witness-conjecture-p (discovery)
  (let ((validation (solve-discovery-validation discovery)))
    (and validation (eq :conjecture (law-validation-status validation))
         (equalp (law-validation-snapshot validation) (law-snapshot (solve-witness-law discovery))))))

(defun prepare-propagator-library (discoveries ledger)
  "Freeze certified field rules and current integer witness conjectures."
  (let ((rules nil))
    (dolist (discovery discoveries)
      (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation))
             (certified (certified-solve-discovery-p discovery)))
        (charge ledger :propagator-library (+ (syntax-work (law-statement (solve-witness-law discovery)))
                                              (syntax-work (law-statement (solve-uniqueness-law discovery)))))
        (when (or certified (and (eq domain :int) (current-witness-conjecture-p discovery)))
          (push (make-arithmetic-propagator
                 :domain (copy-tree domain) :operator (copy-tree (arithmetic-relation-operator relation))
                 :position (solve-discovery-position discovery)
                 :witness (copy-tree (solve-discovery-witness discovery)) :guard (copy-tree (solve-discovery-guard discovery))
                 :certified-p certified
                 ;; Uniqueness is what licenses narrowing a fiber to one witness without a fallback.
                 :unique-p (or certified
                               (let ((uniqueness (solve-discovery-uniqueness discovery)))
                                 (and uniqueness (member (law-validation-status uniqueness) '(:conjecture :validated))
                                      t)))) rules))))
    (make-propagator-library :rules (nreverse rules))))

(defun prepare-propagation-program (model inputs ledger category)
  (evaluation-value
   (finish-accounted-evaluation (start-program-validation model inputs)
                                ledger category "Propagation preparation unresolved" t)))

(defun evaluate-propagation-program (program values ledger category)
  (finish-accounted-evaluation (start-validated-evaluation program values)
                               ledger category "Propagation evaluation unresolved"))

;;; Requirement-Level Propagation: learned solvers applied inside pulled-back predicates

(defun as-propagator-library (sources ledger)
  "Merge SOURCES (solve discoveries, propagator libraries, or a list of either) into one
library, or nil when there is nothing to merge. A lone library is returned as is."
  (if (propagator-library-p sources)
      (progn
        (assert (equal (propagator-library-versions sources) (vm-versions)) () "Stale propagator library")
        sources)
      (let ((discoveries nil) (rules nil))
        (dolist (source (if (listp sources) sources (list sources)))
          (etypecase source
            (solve-discovery (push source discoveries))
            (propagator-library
             (assert (equal (propagator-library-versions source) (vm-versions)) () "Stale propagator library")
             (setf rules (append rules (propagator-library-rules source))))))
        (when (or discoveries rules)
          (let ((library (prepare-propagator-library (nreverse discoveries) ledger)))
            (setf (propagator-library-rules library) (append rules (propagator-library-rules library)))
            library)))))

(defun propagator-program (library rule slot ledger)
  "Prepared guard or witness program of RULE, cached in LIBRARY."
  (let ((key (list rule slot)) (cache (propagator-library-matchers library)))
    (or (gethash key cache)
        (setf (gethash key cache)
              (prepare-propagation-program (if (eq slot :guard) (arithmetic-propagator-guard rule)
                                               (arithmetic-propagator-witness rule))
                                           (arithmetic-inputs (arithmetic-propagator-domain rule))
                                           ledger :propagation-preparation)))))

(defun extract-equality-target (conjunct)
  "If CONJUNCT is `(= term 'c)` or a singleton `(member term '(c))`, return (VALUES term 'c)."
  (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct :singleton-member-p t)
    (declare (ignore term-type))
    (when term
      (values term lit-node))))

(defun solve-learned-equality (conjunct library ledger &optional result)
  "If CONJUNCT is `(= (op a b) 'c)` or `(member (op a b) '(c))` with one closed operand and
one open operand, and LIBRARY holds a rule for OP at the open position whose learned guard
accepts (k, c), return (VALUES (= unknown 'q(k,c)) rule). Uncertified witnesses are forward
checked first."
  (multiple-value-bind (term c) (extract-equality-target conjunct)
    (when (and term (app-p term) (= 2 (length (rest term))))
      (let* ((arg0 (second term)) (arg1 (third term))
             (closed0 (and (null (free-vars arg0)) (not (contains-hole-p arg0))))
             (closed1 (and (null (free-vars arg1)) (not (contains-hole-p arg1))))
             (position (cond ((and closed0 (not closed1)) 1)
                             ((and closed1 (not closed0)) 0))))
        (when position
          (let ((known-expr (if (= position 1) arg0 arg1))
                (unknown (if (= position 1) arg1 arg0)))
            (dolist (rule (propagator-library-rules library))
              (charge ledger :propagator-dispatch (+ 1 (syntax-work (arithmetic-propagator-operator rule))))
              (when (and (equal (first term) (arithmetic-propagator-operator rule))
                         (= position (arithmetic-propagator-position rule)))
                (let ((known (if (lit-p known-expr)
                                 known-expr
                                 (let ((context (run-algebra-program known-expr nil nil ledger :propagation-context)))
                                   (when (eq :value (evaluation-status context))
                                     (lit (ast-type known-expr) (evaluation-value context)))))))
                  (when known
                    (let* ((values (list (ast-value known) (ast-value c)))
                           (guard (evaluate-propagation-program (propagator-program library rule :guard ledger)
                                                                values ledger :propagation-guard)))
                      (when (and (eq :value (evaluation-status guard)) (evaluation-value guard))
                        (let ((witness (evaluate-propagation-program (propagator-program library rule :witness ledger)
                                                                     values ledger :propagation-witness)))
                          (when (eq :value (evaluation-status witness))
                            (let* ((type (ast-type unknown))
                                   (w (lit type (evaluation-value witness))))
                              (if (or (arithmetic-propagator-certified-p rule)
                                      (let ((check (run-algebra-program
                                                    (app (op := (ast-type c))
                                                         (arithmetic-application (first term) position known w) c)
                                                    nil nil ledger :propagation-verification)))
                                        (and (eq :value (evaluation-status check)) (evaluation-value check))))
                                  (return (values (app (op := type) unknown w) rule))
                                  (when result (incf (propagation-rejected result)))))))))))))))))))

(defun propagate-requirements (frame source ledger)
  "Rewrite every top-level conjunct (= (op 'k T) 'c) or (member (op 'k T) '(c)) of FRAME's
requirements to (= T 'w) using SOURCE's learned guards and witnesses, repeatedly, so nested
operators unwind. Only conjuncts are rewritten: a narrowing is not sound under negation.
Certified rules are equivalences; others are suggestions, and rules without uniqueness
evidence mark the propagation ambiguous, so the caller keeps the original frame as a fallback."
  (let ((library (as-propagator-library source ledger))
        (result (make-propagation :frame frame :original frame)))
    (unless library
      (setf (propagation-retained result) (length (frame-rows frame)))
      (return-from propagate-requirements result))
    (setf (propagation-frame result)
          (make-frame (frame-schema frame)
                      (loop for row in (frame-rows frame) collect
                        (let ((certified t) (changed nil) (unique t))
                          (flet ((solve (conjunct)
                                   (loop (multiple-value-bind (next rule)
                                             (solve-learned-equality conjunct library ledger result)
                                           (unless next (return conjunct))
                                           (setf changed t conjunct next
                                                 certified (and certified (arithmetic-propagator-certified-p rule))
                                                 unique (and unique (arithmetic-propagator-unique-p rule)))))))
                            (let ((conjuncts (mapcar #'solve (extract-conjuncts (row-requirement row)))))
                              (cond ((not changed) (incf (propagation-retained result)) row)
                                    (t (if certified (incf (propagation-narrowed result)) (incf (propagation-suggested result)))
                                       (unless unique (incf (propagation-ambiguous result)))
                                       (let ((req (reduce #'bool-and conjuncts :from-end t)))
                                         (charge ledger :propagation-frame (syntax-work req))
                                         (make-row :key (row-key row) :known (row-known row) :requirement req))))))))
                      :pairs (frame-pairs frame) :anchors (frame-anchors frame)))
    (when (plusp (propagation-suggested result)) (setf (propagation-fallback result) frame))
    result))
