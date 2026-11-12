(in-package #:lisploop)

;;; Laws, validation, checked rewriting, solver certification, and requirement propagation.

(defstruct (law (:constructor %make-law)) domain inputs equation guard origin)

(defun law-lhs (law) (second (law-equation law)))

(defun law-rhs (law) (third (law-equation law)))

(defun law-type-p (type domain)
  "True when TYPE is DOMAIN, :BOOL, or a valid tuple of law types in DOMAIN."
  (and (valid-type-p type)
       (or (equal type domain)
           (eq type :bool)
           (and (tuple-type-p type)
                (every (lambda (part) (law-type-p part domain)) (rest type))))))

(defun rewrite-scope-type-p (type domain)
  "True when TYPE is a valid input type in a law or rewrite scope over DOMAIN."
  (and (valid-type-p type)
       (or (law-type-p type domain)
           (and (seq-type-p type)
                (rewrite-scope-type-p (second type) domain))
           (and (tuple-type-p type)
                (every (lambda (part) (rewrite-scope-type-p part domain)) (rest type))))))

(defun finite-type-p (type)
  "True when TYPE is a finite enumerable type (:BOOL, (:GF p), or a tuple thereof)."
  (and (valid-type-p type)
       (or (eq type :bool)
           (gf-type-p type)
           (and (tuple-type-p type)
                (every #'finite-type-p (rest type))))))

(defun make-law (domain inputs left right &key (guard (lit :bool t)) origin)
  (assert (or (eq domain :int) (gf-type-p domain)))
  (assert (= (length inputs) (length (remove-duplicates inputs :key #'car))))
  (assert (every (lambda (input) (rewrite-scope-type-p (cdr input) domain)) inputs))
  (let ((type (expression-type left inputs)))
    (assert (equal type (expression-type right inputs)))
    (assert (rewrite-scope-type-p type domain))
    (assert (eq :bool (expression-type guard inputs)))
    (%make-law :domain (copy-tree domain) :inputs (copy-tree inputs)
               :equation (copy-tree (term `(= ,left ,right)))
               :guard (copy-tree guard) :origin (copy-tree origin))))

(defun law-statement (law)
  (term `(if ,(law-guard law) ,(law-equation law) t)))

(defun law-snapshot (law)
  (list (copy-tree (law-domain law)) (encode-model (law-equation law) (law-inputs law))
        (encode-model (law-guard law) (law-inputs law))
        :typed-value +simulator-version+ +encoding-version+ +tariff-version+
        (expression-dependencies (list (law-equation law) (law-guard law)))))

(defstruct (law-certificate (:constructor %make-law-certificate))
  snapshot (evidence :exhaustive-finite-domain) assignments active work)

(defstruct (law-validation (:constructor %make-law-validation))
  law snapshot (status :unknown) (phase :setup) (debt 0) (ledger (make-ledger))
  exhaustive-p samples (index 0) (count 0) (active 0) values evaluation
  certificate counterexample)

(defun finite-type-cardinality (type)
  (cond
    ((eq type :bool) 2)
    ((gf-type-p type) (second type))
    ((tuple-type-p type)
     (reduce #'* (rest type) :key #'finite-type-cardinality :initial-value 1))
    (t (error "No exhaustive validator for ~S" type))))

(defun unrank-finite-value (type index)
  (cond
    ((eq type :bool)
     (multiple-value-bind (quotient remainder) (floor index 2)
       (values (= remainder 1) quotient)))
    ((gf-type-p type)
     (multiple-value-bind (quotient remainder) (floor index (second type))
       (values remainder quotient)))
    ((tuple-type-p type)
     (let ((cursor index))
       (values (mapcar (lambda (part)
                         (multiple-value-bind (value next) (unrank-finite-value part cursor)
                           (setf cursor next)
                           value))
                       (rest type))
               cursor)))
    (t (error "No exhaustive validator for ~S" type))))

(defun inputs-tuple-type (inputs)
  "The tuple type whose values are the assignments to INPUTS."
  (cons :tuple (mapcar #'cdr inputs)))

(defun start-law-validation (law &key (samples nil supplied-p))
  "Exhaust finite types, or test explicit assignments. Samples NEVER certify a law."
  (let* ((snapshot (law-snapshot law))
         (copy (make-law (law-domain law) (law-inputs law) (law-lhs law) (law-rhs law)
                         :guard (law-guard law) :origin (law-origin law)))
         (count (if supplied-p (length samples)
                    (finite-type-cardinality (inputs-tuple-type (law-inputs law))))))
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

(defun law-assignment (inputs &optional (index 0))
  "The INDEX-th assignment to INPUTS in the order an exhaustive validation visits them."
  (values (unrank-finite-value (inputs-tuple-type inputs) index)))

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
       (pay-debt (law-validation-debt state) budget ledger :law-setup)
       (when (zerop (law-validation-debt state)) (setf (law-validation-phase state) :row)))
      (:row
       (charge ledger :validation-scheduling)
       (if (= (law-validation-index state) (law-validation-count state))
           (finish-law-validation state)
           (setf (law-validation-values state)
                 (if (law-validation-exhaustive-p state)
                     (law-assignment (law-inputs law) (law-validation-index state))
                     (nth (law-validation-index state) (law-validation-samples state)))
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

(defun validate-law (law work-limit sampled-p samples)
  "Validate LAW up to WORK-LIMIT: on SAMPLES when SAMPLED-P, and exhaustively otherwise."
  (resume-law-validation (if sampled-p (start-law-validation law :samples samples)
                             (start-law-validation law))
                         work-limit))

(defun retype-type (type old-domain new-domain)
  (cond
    ((equal type old-domain) (copy-tree new-domain))
    ((consp type) (cons (retype-type (car type) old-domain new-domain)
                        (retype-type (cdr type) old-domain new-domain)))
    (t type)))

(defun retype-value (value new-type)
  (cond
    ((and (gf-type-p new-type) (integerp value))
     (mod value (second new-type)))
    ((and (tuple-type-p new-type) (listp value))
     (mapcar #'retype-value value (rest new-type)))
    ((and (seq-type-p new-type) (listp value))
     (mapcar (lambda (item) (retype-value item (second new-type))) value))
    (t value)))

(defun retype-expr (expr old-domain new-domain)
  (ecase (ast-kind expr)
    (:var (var (ast-id expr) (retype-type (ast-type expr) old-domain new-domain)))
    (:lit (let ((new-type (retype-type (ast-type expr) old-domain new-domain)))
            (lit new-type
                 (if (code-type-p new-type)
                     (retype-expr (ast-value expr) old-domain new-domain)
                     (retype-value (ast-value expr) new-type)))))
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
         (new-inputs (mapcar (lambda (input)
                               (cons (car input) (retype-type (cdr input) old-domain domain)))
                             (law-inputs law))))
    (make-law domain new-inputs
              (retype-expr (law-lhs law) old-domain domain)
              (retype-expr (law-rhs law) old-domain domain)
              :guard (retype-expr (law-guard law) old-domain domain)
              :origin (list :retyped-from old-domain))))

(defun type-slug (type)
  "Compact uppercase string slug for TYPE used in polymorphic combinator names."
  (cond
    ((symbolp type) (symbol-name type))
    ((gf-type-p type)
     (format nil "GF~D" (second type)))
    ((seq-type-p type)
     (format nil "SEQ-~A" (type-slug (second type))))
    ((tuple-type-p type)
     (format nil "TUPLE~{-~A~}" (mapcar #'type-slug (rest type))))
    (t (format nil "~A" type))))

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

(defun law-rewrite-rules (inputs equation guard)
  "The directions of EQUATION under GUARD that can run as rewrite rules: a side rewrites to
the other when it is an application that binds every variable of the other side and of GUARD."
  (destructuring-bind (left right) (rest equation)
    (loop for (from to) in (list (list left right) (list right left))
          when (and (app-p from)
                    (subsetp (append (free-vars to) (free-vars guard)) (free-vars from)))
            collect (%make-rewrite-rule
                     :inputs (copy-tree (remove-if-not
                                         (lambda (input) (member (car input) (free-vars from)))
                                         inputs))
                     :pattern (copy-tree from) :replacement (copy-tree to)
                     :guard (copy-tree guard)))))

(defun freeze-rewrite-library (domain statements)
  "A rewrite library over DOMAIN from STATEMENTS, each a list (inputs equation guard) of a
checked law. Its setup work is the syntax of every statement, usable as a rule or not."
  (%make-rewrite-library
   :domain (copy-tree domain)
   :%rules (loop for statement in statements append (apply #'law-rewrite-rules statement))
   :setup-work (loop for (nil equation guard) in statements
                     sum (+ (syntax-work equation) (syntax-work guard)))))

(defun prepare-rewrite-library (validations domain)
  "Freeze checked rules. Integer samples, modified laws and cross-domain reuse fail."
  (freeze-rewrite-library
   domain
   (loop for validation in validations
         for law = (law-validation-law validation)
         for certificate = (law-validation-certificate validation)
         do (assert (and certificate (eq :validated (law-validation-status validation))
                         (equal domain (law-domain law))
                         (eq :exhaustive-finite-domain (law-certificate-evidence certificate))
                         (equalp (law-certificate-snapshot certificate) (law-snapshot law)))
                    () "Rewrite requires unchanged, current, exhaustive evidence in this domain")
         collect (list (law-inputs law) (law-equation law) (law-guard law)))))

(defun compile-rule-transformer (rule inputs)
  "Lower a frozen checked direction to an ordinary DSL program on quoted syntax."
  (let* ((parameters (rewrite-rule-inputs rule))
         (sort (expression-type (rewrite-rule-pattern rule) parameters))
         (source-type (code-type inputs sort)) (guard-type (code-type inputs :bool))
         (pattern-type (code-type parameters sort))
         (source (var 0 source-type)) (assumptions (var 1 (sequence-type guard-type)))
         (pattern (lit pattern-type (rewrite-rule-pattern rule)))
         (binding-types (mapcar (lambda (parameter) (code-type inputs (cdr parameter))) parameters))
         ;; One quoted binding per rule parameter, read off the match of PATTERN on SOURCE.
         (bindings (loop for parameter in parameters for type in binding-types collect
                     (term `(code-bind ,pattern ,source ,(car parameter)) type)))
         (binding-tuple (term `(tuple ,@bindings))))
    (flet ((fill-template (expression type)
             (term `(code-subst ,(lit (code-type parameters (code-sort type)) expression)
                                ,binding-tuple)
                   type)))
      (let* ((replacement (fill-template (rewrite-rule-replacement rule) source-type))
             (guard (fill-template (rewrite-rule-guard rule) guard-type))
             ;; The instantiated guard is literally true, or is among the assumptions in force.
             (established (term `(if (= ,guard ',(lit :bool t)) t (member ,guard ,assumptions))))
             (result (term `(if ,established
                                (if (code-less ,replacement ,source) ,replacement ,source)
                                ,source))))
        (dolist (binding (reverse bindings))
          (setf result (term `(if (code-total ,binding) ,result ,source))))
        (values (term `(if (code-match ,pattern ,source) ,result ,source))
                (list (cons 0 source-type) (cons 1 (sequence-type guard-type))))))))

(defstruct (rewriting (:constructor %make-rewriting))
  inputs library programs pending-programs cache-key evaluation attempt tasks stack (setup-work 0)
  (debt 0) (work 0) (steps 0) (status :unknown) value)

(defun start-rewriting (expression inputs library)
  (let ((library (if (knowledge-library-p library)
                     (or (as-rewrite-library library :domain (infer-domain-from-types (mapcar #'cdr inputs)))
                         (error "No validated rewrite rules in knowledge library"))
                     library)))
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
                           :tasks (list (list :setup nil nil) (list :walk expression nil))))))))

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
         (push (list :walk (third args) (cons (bool-not condition) assumptions)) (rewriting-tasks state))
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
          (let ((spent (pay-debt (rewriting-debt state) budget ledger :rewriting)))
            (decf budget spent) (incf (rewriting-work state) spent))
          (when (zerop (rewriting-debt state)) (execute-rewrite-task state (pop (rewriting-tasks state))))))
    (unless (or (rewriting-tasks state) (rewriting-evaluation state))
      (assert (= 1 (length (rewriting-stack state))))
      (setf (rewriting-status state) :complete (rewriting-value state) (first (rewriting-stack state)))))
  state)

;;; M4 Solver Discovery & Arithmetic Relations
(defconstant +completion-work+ 100000000
  "Work allowed to a job that is run to completion in one call; reaching it is a cutoff.")

(defstruct arithmetic-relation domain operator observations records guard exhaustive-p)

(defstruct solve-discovery relation position frame observations witness guard ledger
  validation uniqueness)

(defun arithmetic-inputs (domain &optional (count 2))
  (loop for id below count collect (cons id domain)))

(defun arithmetic-application (operator position known unknown)
  (assert (member position '(0 1)))
  (if (zerop position) (app operator unknown known) (app operator known unknown)))

(defun literal-conditional (condition yes no)
  "Only fold literal Boolean conditions; no algebraic identity is supplied."
  (if (lit-p condition)
      (if (ast-value condition) yes no)
      (term `(if ,condition ,yes ,no))))

(defun arithmetic-definedness (relation position known unknown)
  (let ((args (if (zerop position) (list unknown known) (list known unknown))))
    (instantiate (arithmetic-relation-guard relation) (list (cons 0 (first args)) (cons 1 (second args))) :var)))

(defun arithmetic-requirement (relation position)
  "R(k,c,z): a Boolean predicate describing the complete defined forward fiber."
  (let* ((domain (arithmetic-relation-domain relation))
         (k (var 0 domain)) (c (var 1 domain)) (z (var 2 domain)))
    (literal-conditional
     (arithmetic-definedness relation position k z)
     (term `(= ,(arithmetic-application (arithmetic-relation-operator relation) position k z) ,c))
     (lit :bool nil))))

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
              (term `(= ,(var 2 domain) ,(solve-discovery-witness discovery)))
              :guard (solve-discovery-guard discovery))))

(defun validate-arithmetic-solver (discovery &key (samples nil samples-p)
                                               (uniqueness-samples nil uniqueness-samples-p)
                                               (work-limit +completion-work+))
  (let* ((relation (solve-discovery-relation discovery))
         (position (solve-discovery-position discovery))
         (exhaustive-p (finite-type-p (arithmetic-relation-domain relation))))
    (setf (solve-discovery-validation discovery)
          (validate-law (solve-witness-law discovery) work-limit (or samples-p (not exhaustive-p))
                        (cond (samples-p samples)
                              ((not exhaustive-p)
                               (remove-duplicates
                                (mapcar #'row-known (frame-rows (solve-discovery-frame discovery)))
                                :test #'equal))))
          (solve-discovery-uniqueness discovery)
          (validate-law (solve-uniqueness-law discovery) work-limit
                        (or uniqueness-samples-p (not exhaustive-p))
                        (cond (uniqueness-samples-p uniqueness-samples)
                              ((not exhaustive-p)
                               (loop for record in (arithmetic-relation-records relation)
                                     collect (list (nth (1+ (- 1 position)) record)
                                                   (fourth record)
                                                   (nth (1+ position) record)))))))
    discovery))

(defun certified-solve-discovery-p (discovery)
  (and (arithmetic-relation-exhaustive-p (solve-discovery-relation discovery))
       (loop for state in (list (solve-discovery-validation discovery) (solve-discovery-uniqueness discovery))
             for expected in (list (solve-witness-law discovery) (solve-uniqueness-law discovery))
             always (and state (eq :validated (law-validation-status state))
                         (law-validation-certificate state)
                         (equalp (law-certificate-snapshot (law-validation-certificate state)) (law-snapshot expected))))))

(defun finish-accounted-evaluation (state ledger category error-msg &optional require-value-p)
  (advance-accounted-evaluation state +completion-work+ ledger category category)
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

(defstruct arithmetic-propagator domain operator position witness guard certified-p unique-p inputs context-map source source-snapshot)

(defstruct propagator-library rules (versions (vm-versions)) (matchers (make-hash-table :test #'equal)))

(defun current-witness-conjecture-p (discovery)
  (let ((validation (solve-discovery-validation discovery)))
    (and validation (eq :conjecture (law-validation-status validation))
         (equalp (law-validation-snapshot validation) (law-snapshot (solve-witness-law discovery))))))

(defun solve-discovery-solver-arguments (discovery)
  "The operator and keyword arguments with which `register-knowledge-solver` records
DISCOVERY. Its evidence is its own law validations, so a certified discovery is passed as
attested instead of being checked again."
  (let* ((relation (solve-discovery-relation discovery))
         (domain (arithmetic-relation-domain relation))
         (certified (certified-solve-discovery-p discovery))
         (uniqueness (solve-discovery-uniqueness discovery))
         (ledger (solve-discovery-ledger discovery)))
    (list (arithmetic-relation-operator relation)
          :domain domain :inputs (arithmetic-inputs domain) :target domain
          :position (solve-discovery-position discovery)
          :witness (solve-discovery-witness discovery) :guard (solve-discovery-guard discovery)
          :attested-p certified
          ;; Uniqueness is what licenses narrowing a fiber to one witness without a fallback.
          :unique-p (or certified
                        (and uniqueness
                             (member (law-validation-status uniqueness) '(:conjecture :validated))
                             t))
          :work (and ledger (ledger-total ledger)))))

(defun prepare-propagator-library (discoveries ledger)
  "Freeze certified field rules and current integer witness conjectures."
  (let ((rules nil))
    (dolist (discovery discoveries)
      (destructuring-bind (operator &key domain position witness guard attested-p unique-p
                           &allow-other-keys)
          (solve-discovery-solver-arguments discovery)
        (charge ledger :propagator-library (+ (syntax-work (law-statement (solve-witness-law discovery)))
                                              (syntax-work (law-statement (solve-uniqueness-law discovery)))))
        (when (or attested-p (and (eq domain :int) (current-witness-conjecture-p discovery)))
          (push (make-arithmetic-propagator
                 :domain (copy-tree domain) :operator operator :position position
                 :witness (copy-tree witness) :guard (copy-tree guard)
                 :certified-p attested-p :unique-p unique-p)
                rules))))
    (make-propagator-library :rules (nreverse rules))))

(defun prepare-propagation-program (model inputs ledger category)
  (evaluation-value
   (finish-accounted-evaluation (start-program-validation model inputs)
                                ledger category "Propagation preparation unresolved" t)))

(defun evaluate-propagation-program (program values ledger category)
  (finish-accounted-evaluation (start-validated-evaluation program values)
                               ledger category "Propagation evaluation unresolved"))

;;; Requirement-Level Propagation: learned solvers applied inside pulled-back predicates
(defun knowledge-entry->propagator-rule (entry snapshot)
  "Convert `:solver` ENTRY, whose present statement snapshot is SNAPSHOT, into an executable
`arithmetic-propagator` rule; nil when ENTRY names no operator or has no witness."
  (let* ((meta (knowledge-entry-metadata entry))
         (operator (sexp->ast (getf meta :operator)))
         (inputs (knowledge-entry-inputs entry)))
    (when (and operator (knowledge-entry-expression entry))
      (make-arithmetic-propagator
       :domain (copy-tree (knowledge-entry-domain entry))
       :operator operator
       :position (getf meta :position)
       :witness (knowledge-entry-expression entry)
       :guard (knowledge-entry-guard entry)
       :certified-p (knowledge-evidence-current-p entry :witness snapshot)
       :unique-p (knowledge-evidence-current-p entry :uniqueness snapshot)
       :context-map (getf meta :context-map)
       :source entry
       :source-snapshot snapshot
       :inputs (unless (equal inputs (arithmetic-inputs (knowledge-entry-domain entry)))
                 (copy-tree inputs))))))

(defun knowledge-library-propagator-library (klib)
  "Return a version-fresh `propagator-library` containing all `:solver` entries in KLIB."
  (let* ((entries (knowledge-entries-of-kind :solver klib))
         ;; Present statements and certificates are part of the key, so an entry edited in
         ;; place is never served from the cache.
         (snapshots (mapcar #'knowledge-statement-snapshot entries))
         (key (list (knowledge-library-version klib) (vm-versions)
                    (loop for entry in entries for snapshot in snapshots
                          collect (list snapshot (copy-tree (knowledge-entry-certificate entry))))))
         (cache (knowledge-library-propagator-libraries klib)))
    (when entries
      (or (gethash key cache)
          (let ((rules (loop for entry in entries for snapshot in snapshots
                             for rule = (knowledge-entry->propagator-rule entry snapshot)
                             when rule collect rule)))
            (when rules
              (setf (gethash key cache)
                    (make-propagator-library :rules rules :versions (vm-versions)))))))))

(defun as-propagator-library (sources &optional (ledger (make-ledger)))
  "Merge SOURCES (solve discoveries, propagator libraries, knowledge libraries, or a list of any)
into one library, or nil when there is nothing to merge. A lone library is returned as is."
  (cond
    ((propagator-library-p sources)
     (assert (equal (propagator-library-versions sources) (vm-versions)) () "Stale propagator library")
     sources)
    ((knowledge-library-p sources)
     (knowledge-library-propagator-library sources))
    (t
     (let ((discoveries nil) (rules nil))
       (dolist (source (if (listp sources) sources (list sources)))
         (etypecase source
           (null nil)
           (solve-discovery (push source discoveries))
           (propagator-library
            (assert (equal (propagator-library-versions source) (vm-versions)) () "Stale propagator library")
            (setf rules (append rules (propagator-library-rules source))))
           (knowledge-library
            (let ((plib (knowledge-library-propagator-library source)))
              (when plib
                (setf rules (append rules (propagator-library-rules plib))))))))
       (when (or discoveries rules)
         (let ((library (prepare-propagator-library (nreverse discoveries) ledger)))
           (setf (propagator-library-rules library) (append rules (propagator-library-rules library)))
           library))))))

(defun propagator-program (library rule slot ledger)
  "Prepared guard or witness program of RULE, cached in LIBRARY."
  (let ((key (list rule slot)) (cache (propagator-library-matchers library)))
    (or (gethash key cache)
        (setf (gethash key cache)
              (prepare-propagation-program (if (eq slot :guard) (arithmetic-propagator-guard rule)
                                               (arithmetic-propagator-witness rule))
                                           (or (arithmetic-propagator-inputs rule)
                                               (arithmetic-inputs (arithmetic-propagator-domain rule)))
                                           ledger :propagation-preparation)))))

(defun extract-equality-target (conjunct)
  "If CONJUNCT is `(= term 'c)` or a singleton `(member term '(c))`, return (VALUES term 'c)."
  (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct :singleton-member-p t)
    (declare (ignore term-type))
    (when term
      (values term lit-node))))

(defun propagator-evidence (rule)
  "Whether RULE's witness and its uniqueness have current evidence, as two values. A rule
made from a knowledge entry counts only while the entry still states what the rule was made
from; the entry's statement is snapshotted once for both answers."
  (let ((source (arithmetic-propagator-source rule)))
    (if source
        (let ((snapshot (knowledge-statement-snapshot source)))
          (if (equalp snapshot (arithmetic-propagator-source-snapshot rule))
              (values (knowledge-evidence-current-p source :witness snapshot)
                      (knowledge-evidence-current-p source :uniqueness snapshot))
              (values nil nil)))
        (values (arithmetic-propagator-certified-p rule) (arithmetic-propagator-unique-p rule)))))

(defun propagator-certified-current-p (rule &optional (obligation :witness))
  (multiple-value-bind (certified unique) (propagator-evidence rule)
    (if (eq obligation :witness) certified unique)))

(defun solver-context-values (rule term target ledger)
  "Evaluate what RULE must know to invert TERM = TARGET: the known arguments of TERM and
TARGET itself, in the order of RULE's context mapping. Returns the values and the mapping,
or nil when some part has no value."
  (let ((mapping (or (arithmetic-propagator-context-map rule)
                     (solver-context-map (first term) (arithmetic-propagator-position rule)))))
    ;; The target is always part of the context, so nil can stand for failure.
    (assert (member :target mapping))
    (let ((runs (loop for item in mapping
                      for expr = (if (eq item :target) target (nth (second item) (rest term)))
                      collect (and expr (run-algebra-program expr nil nil ledger
                                                             :propagation-context)))))
      (when (every (lambda (run) (and run (eq :value (evaluation-status run)))) runs)
        (values (mapcar #'evaluation-value runs) mapping)))))

(defun run-learned-solver (library rule context ledger)
  "Run RULE on CONTEXT: its guard, then its witness when the guard holds. Returns the witness
value and true, or nil when the guard rejects CONTEXT or either program has no value."
  (let ((guard (evaluate-propagation-program (propagator-program library rule :guard ledger)
                                             context ledger :propagation-guard)))
    (when (and (eq :value (evaluation-status guard)) (evaluation-value guard))
      (let ((witness (evaluate-propagation-program (propagator-program library rule :witness ledger)
                                                   context ledger :propagation-witness)))
        (when (eq :value (evaluation-status witness))
          (values (evaluation-value witness) t))))))

(defun witness-replays-p (rule term target mapping context value ledger)
  "True when TERM's operator, applied to CONTEXT and the witness VALUE, evaluates to TARGET."
  (let ((check (run-algebra-program
                (solver-forward-expression (first term) (arithmetic-propagator-position rule)
                                           mapping context value)
                nil nil ledger :propagation-verification)))
    (and (eq :value (evaluation-status check))
         (equal (ast-value target) (evaluation-value check)))))

(defun solved-conjunct (rule term value)
  "The conjunction that pins each unknown argument of TERM to its part of the witness VALUE."
  (let ((positions (solver-positions (arithmetic-propagator-position rule))))
    (reduce #'bool-and
            (loop for position in positions
                  for part in (if (rest positions) value (list value))
                  for unknown = (nth position (rest term))
                  collect (term `(= ,unknown ',part)))
            :from-end t)))

(defun solve-learned-equality (conjunct library ledger certified-p result)
  "Invert any typed application with the rule's declared known-context mapping.
Multiple unknown positions use a tuple witness. A witness from a rule that CERTIFIED-P does
not vouch for must replay forward to the target; one that does not is counted in RESULT.
Returns the solved conjunct and the rule that solved it, or nil."
  (multiple-value-bind (term target) (extract-equality-target conjunct)
    (let ((open (and term (app-p term)
                     (loop for arg in (rest term) for i from 0
                           when (or (free-vars arg) (pattern-has-holes-p arg)) collect i))))
      (when open
        (dolist (rule (propagator-library-rules library))
          (charge ledger :propagator-dispatch (+ 1 (syntax-work (arithmetic-propagator-operator rule))))
          (when (and (equal (first term) (arithmetic-propagator-operator rule))
                     (null (set-exclusive-or open (solver-positions (arithmetic-propagator-position rule)))))
            (multiple-value-bind (context mapping) (solver-context-values rule term target ledger)
              (multiple-value-bind (value solved-p)
                  (and context (run-learned-solver library rule context ledger))
                (cond ((not solved-p))
                      ((or (funcall certified-p rule)
                           (witness-replays-p rule term target mapping context value ledger))
                       (return (values (solved-conjunct rule term value) rule)))
                      (t (incf (propagation-rejected result))))))))))))

(defun propagate-requirements (frame source ledger)
  "Rewrite every top-level conjunct (= (op 'k T) 'c) or (member (op 'k T) '(c)) of FRAME's
requirements to (= T 'w) using SOURCE's learned guards and witnesses, repeatedly, so nested
operators unwind. Only conjuncts are rewritten: a narrowing is not sound under negation.
Only current witness AND uniqueness evidence licenses dropping the original frame.
Witness-only rules mark propagation ambiguous; conjectures are checked suggestions.
Both retain the original frame as a fallback."
  (let ((library (as-propagator-library source ledger))
        (result (make-propagation :frame frame :original frame))
        (settled nil))                  ; rule -> (certified unique), found once per call
    (labels ((evidence (rule)
               (values-list
                (cdr (or (assoc rule settled)
                         (first (push (cons rule (multiple-value-list (propagator-evidence rule)))
                                      settled))))))
             (narrow (row)
               (let ((certified t) (changed nil) (unique t))
                 (flet ((solve (conjunct)
                          (loop (multiple-value-bind (next rule)
                                    (solve-learned-equality conjunct library ledger #'evidence result)
                                  (unless next (return conjunct))
                                  (multiple-value-bind (rule-certified rule-unique) (evidence rule)
                                    (setf changed t conjunct next
                                          certified (and certified rule-certified)
                                          unique (and unique rule-unique)))))))
                   (let ((conjuncts (mapcar #'solve (extract-conjuncts (row-requirement row)))))
                     (cond ((not changed) (incf (propagation-retained result)) row)
                           (t (if certified
                                  (incf (propagation-narrowed result))
                                  (incf (propagation-suggested result)))
                              (unless unique (incf (propagation-ambiguous result)))
                              (let ((req (reduce #'bool-and conjuncts :from-end t)))
                                (charge ledger :propagation-frame (syntax-work req))
                                (make-row :key (row-key row) :known (row-known row)
                                          :requirement req)))))))))
      (cond ((null library)
             (setf (propagation-retained result) (length (frame-rows frame))))
            (t
             (setf (propagation-frame result)
                   (make-frame (frame-schema frame) (mapcar #'narrow (frame-rows frame))
                               :pairs (frame-pairs frame) :anchors (frame-anchors frame)))
             (when (or (plusp (propagation-suggested result))
                       (plusp (propagation-ambiguous result)))
               (setf (propagation-fallback result) frame))))
      result)))

;;; ============================================================
;;; Persistent Knowledge Library: Laws, Solvers, and Functors
;;; ============================================================
(defun collect-expression-operators (expr)
  "Collect distinct operator keyword names appearing in EXPR."
  (let ((ops nil))
    (labels ((walk (node)
               (when (app-p node)
                 (when (operator-p (first node))
                   (pushnew (operator-name (first node)) ops :test #'eq))
                 (dolist (arg (rest node))
                   (walk arg)))))
      (walk expr)
      (nreverse ops))))

(defun as-rewrite-library (source &key domain)
  "Coerce SOURCE (`rewrite-library`, `knowledge-library`, or list of `law-validation`s) into a
version-fresh `rewrite-library` for DOMAIN (or NIL if no validated rules exist)."
  (cond
    ((null source) nil)
    ((rewrite-library-p source) source)
    ((knowledge-library-p source)
     (let* ((law-entries (remove-if-not (lambda (e) (knowledge-evidence-current-p e :equivalence))
                                        (knowledge-entries-of-kind :law source)))
            (eff-domain (or domain
                            (and law-entries (knowledge-entry-domain (first law-entries)))
                            :int))
            (domain-entries (remove-if-not (lambda (e) (equal eff-domain (knowledge-entry-domain e)))
                                           law-entries)))
       (when domain-entries
         (let* ((cache-key (list eff-domain (knowledge-library-version source) (vm-versions)
                                 (mapcar #'knowledge-statement-snapshot domain-entries)))
                (cached (gethash cache-key (knowledge-library-rewrite-libraries source))))
           (or cached
               (let ((library (freeze-rewrite-library
                               eff-domain
                               (loop for entry in domain-entries
                                     when (app-of-p (knowledge-entry-expression entry) :=)
                                       collect (list (knowledge-entry-inputs entry)
                                                     (knowledge-entry-expression entry)
                                                     (knowledge-entry-guard entry))))))
                 (when (rewrite-library-%rules library)
                   (setf (gethash cache-key (knowledge-library-rewrite-libraries source))
                         library))))))))
    ((listp source)
     (let ((eff-domain (or domain
                           (and source (law-validation-p (first source))
                                (law-domain (law-validation-law (first source))))
                           :int)))
       (prepare-rewrite-library source eff-domain)))
    (t nil)))

(defun register-knowledge-law (law-or-validation &key id (library *knowledge-library*) status
                                                   edges metadata ledger)
  "Register a `law` or `law-validation` into LIBRARY as a `:law` `knowledge-entry`."
  (let* ((validation (and (law-validation-p law-or-validation) law-or-validation))
         (law (if validation (law-validation-law validation) law-or-validation))
         (certificate (and validation (law-validation-certificate validation)))
         (equation (law-equation law))
         (guard (law-guard law))
         (inputs (law-inputs law))
         (entry (make-knowledge-entry
                 :id id :kind :law :domain (law-domain law) :inputs inputs :target :bool
                 :expression equation :guard guard
                 :status (or status (if validation (law-validation-status validation) :conjecture))
                 :bits (+ (body-size equation inputs) (body-size guard inputs))
                 :work (if validation
                           (ledger-total (law-validation-ledger validation))
                           (+ (syntax-work equation) (syntax-work guard)))
                 :edges (append (loop for name in (collect-expression-operators equation)
                                      unless (eq := name) collect (list :governs name))
                                (copy-tree edges))
                 :metadata (append (when (law-origin law) (list :origin (copy-tree (law-origin law))))
                                   (copy-tree metadata))
                 :library library)))
    (when (and certificate (eq :validated (law-validation-status validation))
               (equalp (law-certificate-snapshot certificate) (law-snapshot law)))
      (attest-knowledge-entry entry :exhaustive '(:equivalence)))
    (register-knowledge-entry entry :library library :ledger ledger)))

(defun knowledge-entry->law (entry)
  "The `law` that `:law` ENTRY states; an error when ENTRY is not a law over its domain."
  (let ((equation (knowledge-entry-expression entry)))
    (assert (app-of-p equation :=))
    (make-law (knowledge-entry-domain entry) (knowledge-entry-inputs entry)
              (second equation) (third equation) :guard (knowledge-entry-guard entry))))

(defun retype-knowledge-laws (library new-domain &key (validate-p t) (samples nil samples-p)
                                                   (work-limit 1000000) ledger)
  "Retype `:law` entries in LIBRARY from their source domain to NEW-DOMAIN, recording
`:retyped-from` edges, optionally validating them in NEW-DOMAIN, and registering non-refuted laws."
  (let ((created nil))
    (dolist (entry (knowledge-entries-of-kind :law library) (nreverse created))
      (let ((new-law (and (not (equal new-domain (knowledge-entry-domain entry)))
                          (ignore-errors (retype-law (knowledge-entry->law entry) new-domain)))))
        (flet ((register (law-or-validation &rest keys)
                 (push (apply #'register-knowledge-law law-or-validation :library library
                              :edges (list (list :retyped-from (knowledge-entry-id entry)))
                              :ledger ledger keys)
                       created)))
          (cond
            ((null new-law))
            ;; Avoid duplicate law equations in the target domain
            ((some (lambda (existing)
                     (and (equal new-domain (knowledge-entry-domain existing))
                          (equal (law-equation new-law) (knowledge-entry-expression existing))
                          (equal (law-guard new-law) (knowledge-entry-guard existing))))
                   (knowledge-entries-of-kind :law library)))
            (validate-p
             (let ((finished (validate-law new-law work-limit
                                           (or samples-p (not (finite-type-p new-domain))) samples)))
               (charge ledger :law-checking (ledger-total (law-validation-ledger finished)))
               (when (member (law-validation-status finished) '(:validated :conjecture))
                 (register finished))))
            (t (register new-law :status :conjecture))))))))

(define-knowledge-kind :law
  (:priority 30)
  (:validate (entry library)
    (declare (ignore library))
    (let ((expr (knowledge-entry-expression entry))
          (inputs (knowledge-entry-inputs entry)))
      (assert (app-of-p expr :=))
      (assert (eq :bool (expression-type expr inputs)))
      (assert (eq :bool (expression-type (knowledge-entry-guard entry) inputs)))))
  (:install (entry library ledger)
    (declare (ignore entry ledger))
    (clrhash (knowledge-library-rewrite-libraries library)))
  (:consume (entry context ledger)
    (let ((inputs (knowledge-entry-inputs entry)))
      (when (= (length context) (length inputs))
        (evaluate (law-statement (knowledge-entry->law entry)) inputs context :ledger ledger)))))

(defun solver-positions (position)
  (cond ((eq position :unary) '(0)) ((listp position) position) (t (list position))))

(defun solver-context-map (operator position)
  (append (loop for i below (length (second (operator-type operator)))
                unless (member i (solver-positions position)) collect (list :argument i))
          (list :target)))

(defun solver-context-types (operator context-map)
  (let ((signature (operator-type operator)))
    (loop for item in context-map for id from 0
          collect (cons id (if (eq item :target) (third signature)
                              (nth (second item) (second signature)))))))

(defun solver-forward-expression (operator position context-map context witness)
  "Reassemble a typed application from its known context and one or more witnesses."
  (let* ((positions (solver-positions position))
         (types (second (operator-type operator)))
         (unknown-values (if (= 1 (length positions)) (list witness) witness)))
    (apply #'app operator
           (loop for type in types for i from 0
                 collect (lit type
                              (let ((p (position i positions)))
                                (if p (nth p unknown-values)
                                    (nth (position (list :argument i) context-map :test #'equal)
                                         context))))))))

(defun validate-solver-shape (entry)
  "Check the inversion schema before constructing or trusting any witness."
  (let* ((meta (knowledge-entry-metadata entry))
         (operator (sexp->ast (getf meta :operator)))
         (types (second (operator-type operator)))
         (positions (solver-positions (getf meta :position)))
         (mapping (or (getf meta :context-map) (solver-context-map operator positions)))
         (expected (solver-context-map operator positions))
         (unknown-types (mapcar (lambda (p) (nth p types)) positions)))
    (assert (and positions (every (lambda (p) (and (integerp p) (<= 0 p) (< p (length types)))) positions)
                 (= (length positions) (length (remove-duplicates positions)))))
    (assert (and (= (length mapping) (length expected))
                 (null (set-exclusive-or mapping expected :test #'equal))))
    (assert (equal (mapcar #'cdr (knowledge-entry-inputs entry))
                   (mapcar #'cdr (solver-context-types operator mapping))))
    (assert (equal (knowledge-entry-target entry)
                   (if (= 1 (length positions)) (first unknown-types) (cons :tuple unknown-types))))
    (assert (equal (knowledge-entry-target entry)
                   (expression-type (knowledge-entry-expression entry) (knowledge-entry-inputs entry))))))

(defun certify-solver-entry (entry ledger &key trusted-p)
  "Check finite fibers exhaustively; unbounded certification requires an explicit axiom."
  (validate-solver-shape entry)
  (let* ((meta (knowledge-entry-metadata entry))
         (operator (sexp->ast (getf meta :operator)))
         (position (getf meta :position))
         (mapping (or (getf meta :context-map) (solver-context-map operator position)))
         (inputs (knowledge-entry-inputs entry))
         (target (knowledge-entry-target entry))
         (unique (getf meta :unique-p))
         (obligations (if unique '(:witness :uniqueness) '(:witness)))
         ;; Number of contexts to check, when every type involved is finite.
         (count (and (every #'finite-type-p (cons target (mapcar #'cdr inputs)))
                     (finite-type-cardinality (inputs-tuple-type inputs)))))
    (when trusted-p
      (return-from certify-solver-entry (attest-knowledge-entry entry :trusted-axiom obligations)))
    (when (and count (<= (* (finite-type-cardinality target) count) 65536))
      (let ((active 0))
        (dotimes (index count)
          (let* ((context (law-assignment inputs index))
                 (grun (evaluate (knowledge-entry-guard entry) inputs context :ledger ledger))
                 (expected (nth (position :target mapping) context)))
            (unless (eq :value (evaluation-status grun)) (return-from certify-solver-entry nil))
            (when (evaluation-value grun)
              (incf active)
              (let* ((wrun (evaluate (knowledge-entry-expression entry) inputs context :ledger ledger))
                     (witness (evaluation-value wrun)))
                (unless (eq :value (evaluation-status wrun)) (return-from certify-solver-entry nil))
                (flet ((forward (value)
                         (evaluate (solver-forward-expression operator position mapping context value)
                                   nil nil :ledger ledger)))
                  (let ((run (forward witness)))
                    (unless (and (eq :value (evaluation-status run))
                                 (equal expected (evaluation-value run)))
                      (return-from certify-solver-entry nil)))
                  (when unique
                    (dotimes (i (finite-type-cardinality target))
                      (let* ((alternative (unrank-finite-value target i)) (run (forward alternative)))
                        (when (and (eq :value (evaluation-status run))
                                   (equal expected (evaluation-value run))
                                   (not (equal witness alternative)))
                          (return-from certify-solver-entry nil))))))))))
        (when (plusp active) (attest-knowledge-entry entry :exhaustive obligations))))))

(defun register-knowledge-solver (operator &rest arguments
                                  &key id (library *knowledge-library*) domain inputs target
                                    position witness guard certified-p trusted-p attested-p
                                    context-map (unique-p t) status work edges metadata ledger)
  "Register WITNESS, under GUARD, as a `:solver` `knowledge-entry` of LIBRARY that inverts
OPERATOR (an operator, or the name of one or of a defined function) at POSITION.
CERTIFIED-P asks for the exhaustive check of `certify-solver-entry`, TRUSTED-P records an
axiom instead, and ATTESTED-P states that exhaustive law validation has already established
witness and uniqueness; without current witness evidence the entry is a conjecture.
A `solve-discovery` in place of OPERATOR supplies all of these itself, and is validated
first when its relation is exhaustive and it has not been."
  (when (solve-discovery-p operator)
    (when (and (null (solve-discovery-validation operator))
               (arithmetic-relation-exhaustive-p (solve-discovery-relation operator)))
      (validate-arithmetic-solver operator))
    (return-from register-knowledge-solver
      (apply #'register-knowledge-solver
             (append (solve-discovery-solver-arguments operator) arguments))))
  (let* ((operator (cond ((operator-p operator) operator)
                         ((defined-function-p (canonical-op-name operator))
                          (op (canonical-op-name operator)))
                         (t (op (canonical-op-name operator) (or domain :int)))))
         (name (operator-name operator))
         (position (or position :unary))
         (context-map (or context-map (solver-context-map operator position)))
         (inputs (or inputs (solver-context-types operator context-map)))
         (guard (or guard (lit :bool t)))
         (entry (make-knowledge-entry
                 :id id :kind :solver
                 :domain (or domain (infer-domain-from-types
                                     (cons (third (operator-type operator))
                                           (second (operator-type operator)))))
                 :inputs inputs :target (or target (expression-type witness inputs))
                 :expression witness :guard guard
                 :status (or status (if (or certified-p attested-p) :validated :conjecture))
                 :bits (+ (body-size witness inputs) (body-size guard inputs))
                 :work (or work (+ (syntax-work witness) (syntax-work guard)))
                 :edges (cons (list :inverts name position) (copy-tree edges))
                 :metadata (append (list :operator (ast->sexp operator) :operator-name name
                                         :position position :context-map context-map
                                         :certified-p (or certified-p attested-p)
                                         :unique-p unique-p)
                                   (copy-tree metadata))
                 :library library)))
    (cond (attested-p (attest-knowledge-entry entry :exhaustive '(:witness :uniqueness)))
          ((or certified-p trusted-p) (certify-solver-entry entry ledger :trusted-p trusted-p)))
    (unless (knowledge-evidence-current-p entry :witness)
      (setf (knowledge-entry-status entry) :conjecture
            (getf (knowledge-entry-metadata entry) :certified-p) nil))
    (register-knowledge-entry entry :library library :ledger ledger)))

(defun evaluate-guarded-entry (entry context ledger)
  "Evaluate ENTRY's expression on CONTEXT when its guard holds there; nil when it does not."
  (let* ((inputs (knowledge-entry-inputs entry))
         (guard (evaluate (knowledge-entry-guard entry) inputs context :ledger ledger)))
    (when (and (eq :value (evaluation-status guard)) (evaluation-value guard))
      (evaluate (knowledge-entry-expression entry) inputs context :ledger ledger))))

(define-knowledge-kind :solver
  (:priority 35)
  (:validate (entry library)
    (declare (ignore library))
    (validate-solver-shape entry)
    (assert (eq :bool (expression-type (knowledge-entry-guard entry)
                                       (knowledge-entry-inputs entry)))))
  (:install (entry library ledger)
    (declare (ignore entry ledger))
    (clrhash (knowledge-library-propagator-libraries library)))
  (:consume (entry context ledger)
    (when (= (length context) (length (knowledge-entry-inputs entry)))
      (evaluate-guarded-entry entry context ledger))))
