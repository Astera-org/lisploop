(in-package #:lisploop)

;;; Laws, validation, checked rewriting, solver certification, and requirement propagation.

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
  "The law LEFT = RIGHT under GUARD over DOMAIN: an unregistered `:law` entry, a conjecture
until a validation attests it."
  (assert (or (eq domain :int) (gf-type-p domain)))
  (assert (= (length inputs) (length (remove-duplicates inputs :key #'car))))
  (assert (every (lambda (input) (rewrite-scope-type-p (cdr input) domain)) inputs))
  (let ((type (expression-type left inputs))
        (equation (copy-tree (term `(= ,left ,right))))
        (guard (copy-tree guard)))
    (assert (equal type (expression-type right inputs)))
    (assert (rewrite-scope-type-p type domain))
    (assert (eq :bool (expression-type guard inputs)))
    (make-knowledge-entry
     :kind :law :domain domain :inputs inputs :target :bool :expression equation :guard guard
     :status :conjecture
     :bits (+ (body-size equation inputs) (body-size guard inputs))
     :work (+ (syntax-work equation) (syntax-work guard))
     :edges (loop for name in (collect-expression-operators equation)
                  unless (eq := name) collect (list :governs name))
     :metadata (and origin (list :origin origin))
     :library nil)))

(defun law-statement (law)
  (term `(if ,(knowledge-entry-guard law) ,(knowledge-entry-expression law) t)))

(defstruct (law-validation (:constructor %make-law-validation))
  law snapshot (status :unknown) (phase :setup) (debt 0) (ledger (make-ledger))
  exhaustive-p samples (index 0) (count 0) (active 0) values evaluation counterexample)

(defun law-validation-certificate (state)
  "The certificate an exhaustive validation gave STATE's law, with the :assignments it
visited, how many were :active under the guard and the :work spent; nil unless the law
still reads as it did when it was checked."
  (let ((law (law-validation-law state)))
    (and (knowledge-evidence-current-p law :equivalence) (knowledge-entry-certificate law))))

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
  (let* ((inputs (knowledge-entry-inputs law))
         (copy (copy-knowledge-entry law))
         (count (if supplied-p (length samples)
                    (finite-type-cardinality (inputs-tuple-type inputs)))))
    (dolist (values samples)
      (assert (= (length values) (length inputs)))
      (assert (every (lambda (value input) (value-p value (cdr input))) values inputs)))
    (setf (knowledge-entry-certificate copy) nil
          (knowledge-entry-metadata copy) (copy-tree (knowledge-entry-metadata law)))
    (%make-law-validation :law copy :snapshot (knowledge-statement-snapshot copy)
                          :debt (+ (syntax-work (knowledge-entry-expression law))
                                   (syntax-work (knowledge-entry-guard law))
                                   (loop for values in samples sum
                                     (loop for value in values for input in inputs
                                           sum (value-work value (cdr input)))))
                          :exhaustive-p (not supplied-p)
                          :samples (copy-tree samples) :count count)))

(defun law-assignment (inputs &optional (index 0))
  "The INDEX-th assignment to INPUTS in the order an exhaustive validation visits them."
  (values (unrank-finite-value (inputs-tuple-type inputs) index)))

(defun finish-law-validation (state)
  (let ((law (law-validation-law state)))
    (assert (equalp (law-validation-snapshot state) (knowledge-statement-snapshot law))
            () "Law changed during validation")
    (setf (law-validation-status state)
          (cond ((zerop (law-validation-active state)) :vacuous)
                ((law-validation-exhaustive-p state) :validated)
                (t :conjecture)))
    (when (eq :validated (law-validation-status state))
      (attest-knowledge-entry law :exhaustive '(:equivalence))
      (setf (knowledge-entry-certificate law)
            (append (knowledge-entry-certificate law)
                    (list :assignments (law-validation-count state)
                          :active (law-validation-active state)
                          :work (ledger-total (law-validation-ledger state))))))))

(defun law-validation-step (state budget)
  (let* ((law (law-validation-law state)) (ledger (law-validation-ledger state))
         (inputs (knowledge-entry-inputs law)))
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
                     (law-assignment inputs (law-validation-index state))
                     (nth (law-validation-index state) (law-validation-samples state)))
                 (law-validation-evaluation state)
                 (start-evaluation (knowledge-entry-guard law) inputs (law-validation-values state))
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
                  (start-evaluation (knowledge-entry-expression law) inputs (law-validation-values state))
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
  (let ((old-domain (knowledge-entry-domain law)))
    (destructuring-bind (left right) (rest (knowledge-entry-expression law))
      (make-law domain
                (mapcar (lambda (input)
                          (cons (car input) (retype-type (cdr input) old-domain domain)))
                        (knowledge-entry-inputs law))
                (retype-expr left old-domain domain)
                (retype-expr right old-domain domain)
                :guard (retype-expr (knowledge-entry-guard law) old-domain domain)
                :origin (list :retyped-from old-domain)))))

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

(defun law-rewrite-rules (law)
  "The directions of LAW that can run as rewrite rules: a side rewrites to the other when it
is an application that binds every variable of the other side and of the guard."
  (let ((inputs (knowledge-entry-inputs law)) (guard (knowledge-entry-guard law)))
    (destructuring-bind (left right) (rest (knowledge-entry-expression law))
      (loop for (from to) in (list (list left right) (list right left))
            when (and (app-p from)
                      (subsetp (append (free-vars to) (free-vars guard)) (free-vars from)))
              collect (%make-rewrite-rule
                       :inputs (copy-tree (remove-if-not
                                           (lambda (input) (member (car input) (free-vars from)))
                                           inputs))
                       :pattern (copy-tree from) :replacement (copy-tree to)
                       :guard (copy-tree guard))))))

(defun freeze-rewrite-library (domain laws)
  "A rewrite library over DOMAIN from LAWS, checked `:law` entries. Its setup work is the
syntax of every law, usable as a rule or not."
  (%make-rewrite-library
   :domain (copy-tree domain)
   :%rules (loop for law in laws append (law-rewrite-rules law))
   :setup-work (loop for law in laws
                     sum (+ (syntax-work (knowledge-entry-expression law))
                            (syntax-work (knowledge-entry-guard law))))))

(defun prepare-rewrite-library (validations domain)
  "Freeze checked rules. Integer samples, modified laws and cross-domain reuse fail."
  (freeze-rewrite-library
   domain
   (loop for validation in validations
         for law = (law-validation-law validation)
         do (assert (and (eq :validated (law-validation-status validation))
                         (equal domain (knowledge-entry-domain law))
                         (law-validation-certificate validation))
                    () "Rewrite requires unchanged, current, exhaustive evidence in this domain")
         collect law)))

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

;;; Evaluation to completion on a ledger
(defconstant +completion-work+ 100000000
  "Work allowed to a job that is run to completion in one call; reaching it is a cutoff.")

(defun arithmetic-inputs (domain &optional (count 2))
  (loop for id below count collect (cons id domain)))

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

;;; A rule is a `:solver` entry prepared for dispatch, with the statement it was prepared from.
(defstruct arithmetic-propagator operator position witness guard inputs context-map source source-snapshot)

(defstruct propagator-library rules (versions (vm-versions)) (matchers (make-hash-table :test #'equal)))

(defun prepare-propagation-program (model inputs ledger category)
  (evaluation-value
   (finish-accounted-evaluation (start-program-validation model inputs)
                                ledger category "Propagation preparation unresolved" t)))

(defun evaluate-propagation-program (program values ledger category)
  (finish-accounted-evaluation (start-validated-evaluation program values)
                               ledger category "Propagation evaluation unresolved"))

;;; Requirement-Level Propagation: learned solvers applied inside pulled-back predicates
(defun knowledge-entry->propagator-rule (entry &optional (snapshot (knowledge-statement-snapshot entry)))
  "Prepare `:solver` ENTRY, whose present statement snapshot is SNAPSHOT, as an
`arithmetic-propagator` rule; nil when ENTRY names no operator or has no witness."
  (let* ((meta (knowledge-entry-metadata entry))
         (operator (sexp->ast (getf meta :operator))))
    (when (and operator (knowledge-entry-expression entry))
      (make-arithmetic-propagator
       :operator operator :position (getf meta :position)
       :witness (knowledge-entry-expression entry) :guard (knowledge-entry-guard entry)
       :inputs (knowledge-entry-inputs entry) :context-map (getf meta :context-map)
       :source entry :source-snapshot snapshot))))

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

(defun as-propagator-library (sources)
  "Merge SOURCES, a propagator library, a knowledge library, or a list of either, into one
library; nil when they hold no rule. A lone library is returned as is."
  (flet ((fresh (library)
           (assert (equal (propagator-library-versions library) (vm-versions)) ()
                   "Stale propagator library")
           library))
    (cond
      ((propagator-library-p sources) (fresh sources))
      ((knowledge-library-p sources) (knowledge-library-propagator-library sources))
      (t (let ((rules (loop for source in sources
                            for library = (if (knowledge-library-p source)
                                              (knowledge-library-propagator-library source)
                                              source)
                            when library append (propagator-library-rules (fresh library)))))
           (and rules (make-propagator-library :rules rules)))))))

(defun callable-rules-library (library)
  "The rules of LIBRARY that invert a defined function, as a library of their own, or nil
when it has none. Folding a requirement may unfold a call to such a function, after which
no rule would recognise it, so these rules are applied to a requirement before it is folded."
  (let ((cache (propagator-library-matchers library)))
    (multiple-value-bind (found present-p) (gethash :callable-rules cache)
      (if present-p
          found
          (setf (gethash :callable-rules cache)
                (let ((rules (remove-if-not
                              (lambda (rule)
                                (defined-function-p
                                 (operator-name (arithmetic-propagator-operator rule))))
                              (propagator-library-rules library))))
                  (and rules
                       (make-propagator-library :rules rules
                                                :versions (propagator-library-versions library)))))))))

(defun propagator-program (library rule slot ledger)
  "Prepared guard or witness program of RULE, cached in LIBRARY."
  (let ((key (list rule slot)) (cache (propagator-library-matchers library)))
    (or (gethash key cache)
        (setf (gethash key cache)
              (prepare-propagation-program (if (eq slot :guard) (arithmetic-propagator-guard rule)
                                               (arithmetic-propagator-witness rule))
                                           (arithmetic-propagator-inputs rule)
                                           ledger :propagation-preparation)))))

(defun extract-equality-target (conjunct)
  "If CONJUNCT is `(= term 'c)` or a singleton `(member term '(c))`, return (VALUES term 'c)."
  (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct :singleton-member-p t)
    (declare (ignore term-type))
    (when term
      (values term lit-node))))

(defun propagator-evidence (rule)
  "Whether RULE's witness and its uniqueness have current evidence, as two values. A rule
counts only while its entry still states what the rule was prepared from; the entry's
statement is snapshotted once for both answers."
  (let* ((source (arithmetic-propagator-source rule))
         (snapshot (knowledge-statement-snapshot source)))
    (if (equalp snapshot (arithmetic-propagator-source-snapshot rule))
        (values (knowledge-evidence-current-p source :witness snapshot)
                (knowledge-evidence-current-p source :uniqueness snapshot))
        (values nil nil))))

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
  (let ((library (as-propagator-library source))
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
                   (derive-frame frame :rows (mapcar #'narrow (frame-rows frame))))
             (when (or (plusp (propagation-suggested result))
                       (plusp (propagation-ambiguous result)))
               (setf (propagation-fallback result) frame))))
      result)))

;;; Symbolic unwinding: the same rules applied to expressions instead of row values.

(defun simplify-symbolic-expr (expr)
  "Lightweight algebraic cleanup on a symbolically unwound expression: folds closed subterms
and strips provably-total additive/multiplicative identities (`+ 0`, `- 0`, `* 1`, `* 0`)."
  (cond
    ((not (app-p expr)) expr)
    ((and (null (free-vars expr)) (not (pattern-has-holes-p expr)))
     (let ((run (evaluate expr nil nil :budget 64)))
       (if (eq :value (evaluation-status run))
           (lit (ast-type expr) (evaluation-value run))
           expr)))
    (t
     (let* ((rebuilt (apply #'app (first expr) (mapcar #'simplify-symbolic-expr (rest expr))))
            (name (ast-id rebuilt))
            (a (second rebuilt))
            (b (third rebuilt)))
       (flet ((lit-val-p (node v) (and (lit-p node) (eql v (ast-value node)))))
         (cond
           ((and (null (free-vars rebuilt)) (not (pattern-has-holes-p rebuilt)))
            (let ((run (evaluate rebuilt nil nil :budget 64)))
              (if (eq :value (evaluation-status run))
                  (lit (ast-type rebuilt) (evaluation-value run))
                  rebuilt)))
           ((and (eq name :+) (lit-val-p a 0)) b)
           ((and (eq name :+) (lit-val-p b 0)) a)
           ((and (eq name :-) (lit-val-p b 0)) a)
           ((and (eq name :*) (lit-val-p a 1)) b)
           ((and (eq name :*) (lit-val-p b 1)) a)
           ((and (eq name :*) (lit-val-p a 0) (provably-total-p b)) a)
           ((and (eq name :*) (lit-val-p b 0) (provably-total-p a)) b)
           (t rebuilt)))))))

(defun solve-equality-symbolically (expression constant target-id &key (library *knowledge-library*) ledger)
  "Unwind the equation EXPRESSION = CONSTANT (or a two-sided `(= lhs rhs)` when CONSTANT is
nil or `'t`) for the variable TARGET-ID. At each level EXPRESSION must apply an operator whose
arguments mention the target in one place only; a rule of LIBRARY that inverts the operator
there, and whose witness is marked unique, then turns `(= (op K T) c)` into `(= T q(K, c))`
with the rule's witness written over the expressions K and c themselves. Returns
(VALUES solution guards certified-p): the closed form of the target, the instances of the
rules' guards it holds under, and whether every rule used has current witness and uniqueness
evidence; a solution that is not certified is a conjecture to replay. Returns nil when some
level has no such rule."
  (when (and (app-of-p expression :=)
             (or (null constant)
                 (and (lit-p constant) (eq :bool (ast-type constant)) (eq t (ast-value constant)))))
    (let ((lhs (second expression))
          (rhs (third expression)))
      (cond ((and (member target-id (free-vars lhs)) (not (member target-id (free-vars rhs))))
             (setf expression lhs constant rhs))
            ((and (member target-id (free-vars rhs)) (not (member target-id (free-vars lhs))))
             (setf expression rhs constant lhs)))))
  (when (null constant)
    (return-from solve-equality-symbolically nil))
  (let* ((propagators (as-propagator-library library))
         (rules (and propagators (propagator-library-rules propagators)))
         (guards nil)
         (certified-p t))
    (loop
      (when (and (var-p expression) (eql target-id (ast-id expression)))
        (return (values (simplify-symbolic-expr constant)
                        (mapcar #'simplify-symbolic-expr (nreverse guards))
                        certified-p)))
      (let* ((open (and (app-p expression)
                        (loop for argument in (rest expression) for position from 0
                              when (member target-id (free-vars argument)) collect position)))
             (rule (and open (null (rest open))
                        (find-if (lambda (rule)
                                   (and (equal (first expression) (arithmetic-propagator-operator rule))
                                        (equal open (solver-positions (arithmetic-propagator-position rule)))
                                        (or (propagator-certified-current-p rule :uniqueness)
                                            (let ((src (arithmetic-propagator-source rule)))
                                              (and src (getf (knowledge-entry-metadata src) :unique-p))))))
                                 rules))))
        (unless rule (return nil))
        (charge ledger :symbolic-unwinding (syntax-work expression))
        (let ((context (loop for item in (or (arithmetic-propagator-context-map rule)
                                             (solver-context-map (first expression)
                                                                 (arithmetic-propagator-position rule)))
                             for (id . nil) in (arithmetic-propagator-inputs rule)
                             collect (cons id (if (eq item :target)
                                                  constant
                                                  (nth (second item) (rest expression)))))))
          (unless (and (propagator-certified-current-p rule :witness)
                       (propagator-certified-current-p rule :uniqueness))
            (setf certified-p nil))
          (let ((guard (instantiate (arithmetic-propagator-guard rule) context :var)))
            (unless (unconstrained-requirement-p guard) (push guard guards)))
          (setf constant (instantiate (arithmetic-propagator-witness rule) context :var)
                expression (nth (first open) (rest expression))))))))

(defun sensitivity-probe-values (type)
  "Synthetic fallback probe values of TYPE for `target-sensitive-p`."
  (cond ((eq type :int) '(0 1 -1 2 7))
        ((eq type :bool) '(nil t))
        ((gf-type-p type) (loop for v from 0 below (min (second type) 7) collect v))
        ((seq-type-p type)
         (let ((d (default-value-for-type (second type))))
           (list nil (list d) (list d d))))
        (t (list (default-value-for-type type)))))

(defun target-sensitive-p (expression target-id frame &optional ledger)
  "True when EXPRESSION mentions the input TARGET-ID of FRAME and, on some row, takes another
value once that input is perturbed across all observed or synthetic probe values of its type.
A conserved quantity that mentions the target only to cancel it, like `(- Y Y)`, says nothing
about it."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (position (position target-id inputs :key #'car))
         (target-type (and position (cdr (nth position inputs))))
         (observed (and position
                        (loop for row in (frame-rows frame)
                              for val = (nth position (row-known row))
                              unless (eq val :unresolved) collect val)))
         (probes (and position
                      (remove-duplicates (append observed (sensitivity-probe-values target-type))
                                         :test #'equal))))
    (and (member target-id (free-vars expression))
         (rest probes)
         (some (lambda (row)
                 (let* ((known (row-known row))
                        (orig (nth position known)))
                   (and (not (eq orig :unresolved))
                        (multiple-value-bind (here here-p) (eval-expr-value expression inputs known ledger)
                          (and here-p
                               (some (lambda (other)
                                       (and (not (equal other orig))
                                            (let ((perturbed (substitute-if other (constantly t) known
                                                                            :start position :count 1)))
                                              (multiple-value-bind (there there-p)
                                                  (eval-expr-value expression inputs perturbed ledger)
                                                (and there-p (not (equal here there)))))))
                                     probes))))))
               (frame-rows frame)))))

(defun orient-conserved-quantity (obs-frame target-id conserved-expr constant-value
                                  &key (library *knowledge-library*) ledger)
  "Turn the conservation C(u, T) = CONSTANT-VALUE observed on OBS-FRAME, whose rows know
every column, into a way to predict column TARGET-ID (or `:auto` for the unique top-ranked
column under the schema's availability preorder) from the others. Returns nil when C is not
sensitive to T. When unique solvers unwind the equation, the closed form and its guards read
only inputs available at T's rank, and they meet every row, returns (VALUES model :symbolic guards).
Otherwise returns (VALUES frame :numeric), the pulled-back frame of `conserved-quantity-frame`
oriented to T's available inputs."
  (let* ((obs-schema (frame-schema obs-frame))
         (inputs (schema-inputs obs-schema))
         (target-id (if (eq target-id :auto)
                        (schema-maximal-availability-id obs-schema)
                        target-id))
         (position (and target-id (position target-id inputs :key #'car))))
    (when (and position (target-sensitive-p conserved-expr target-id obs-frame ledger))
      (let* ((target-type (cdr (nth position inputs)))
             (u-inputs (remove target-id inputs :key #'car))
             (target-rank (or (cdr (assoc target-id (schema-availability obs-schema) :test #'equal))
                              (schema-target-availability obs-schema)))
             (u-schema (make-schema :domain (schema-domain obs-schema)
                                    :inputs u-inputs :target target-type
                                    :availability (remove target-id (schema-availability obs-schema)
                                                          :key #'car)
                                    :target-availability target-rank
                                    :availability-order (schema-availability-order obs-schema)))
             (constant (lit (expression-type conserved-expr inputs) constant-value)))
        (multiple-value-bind (model guards)
            (solve-equality-symbolically conserved-expr constant target-id
                                         :library library :ledger ledger)
          (if (and model
                   (expression-respects-availability-p model u-schema)
                   (every (lambda (g) (expression-respects-availability-p g u-schema)) guards)
                   (every (lambda (row)
                            (let ((known (row-known row)))
                              (and (every (lambda (guard)
                                            (multiple-value-bind (value ok)
                                                (eval-expr-value guard inputs known ledger)
                                              (and ok value)))
                                          guards)
                                   (multiple-value-bind (value ok)
                                       (eval-expr-value model inputs known ledger)
                                     (and ok (equal value (nth position known)))))))
                          (frame-rows obs-frame)))
              (values model :symbolic guards)
              (let ((pulled (conserved-quantity-frame obs-frame target-id conserved-expr
                                                      constant-value ledger)))
                (values (if target-rank
                            (orient-available
                             (make-frame u-schema (frame-rows pulled)
                                         :pairs (frame-pairs pulled)
                                         :anchors (frame-anchors pulled)
                                         :edges (frame-edges pulled)
                                         :metric (frame-metric pulled))
                             ledger)
                            pulled)
                        :numeric))))))))

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
     (let* ((laws (remove-if-not (lambda (e) (knowledge-evidence-current-p e :equivalence))
                                 (knowledge-entries-of-kind :law source)))
            (domain (or domain (and laws (knowledge-entry-domain (first laws))) :int))
            (laws (remove-if-not (lambda (e) (equal domain (knowledge-entry-domain e))) laws)))
       (when laws
         (let ((key (list domain (knowledge-library-version source) (vm-versions)
                          (mapcar #'knowledge-statement-snapshot laws)))
               (cache (knowledge-library-rewrite-libraries source)))
           (or (gethash key cache)
               (let ((library (freeze-rewrite-library domain laws)))
                 (when (rewrite-library-%rules library)
                   (setf (gethash key cache) library))))))))
    (t (prepare-rewrite-library
        source (or domain (knowledge-entry-domain (law-validation-law (first source))))))))

(defun register-knowledge-law (law-or-validation &key id (library *knowledge-library*) status
                                                   edges metadata ledger)
  "Register a law, or the law of a `law-validation` with the evidence it earned, in LIBRARY."
  (let* ((validation (and (law-validation-p law-or-validation) law-or-validation))
         (entry (copy-knowledge-entry (if validation (law-validation-law validation) law-or-validation))))
    (setf (knowledge-entry-id entry) (if id (canonical-op-name id) (next-knowledge-entry-id library :law))
          (knowledge-entry-status entry) (or status (if validation (law-validation-status validation) :conjecture))
          (knowledge-entry-edges entry) (append (knowledge-entry-edges entry) (copy-tree edges))
          (knowledge-entry-metadata entry) (append (knowledge-entry-metadata entry) (copy-tree metadata)))
    (when validation
      (setf (knowledge-entry-work entry) (ledger-total (law-validation-ledger validation))))
    (register-knowledge-entry entry :library library :ledger ledger)))

(defun retype-knowledge-laws (library new-domain &key (validate-p t) (samples nil samples-p)
                                                   (work-limit 1000000) ledger)
  "Retype `:law` entries in LIBRARY from their source domain to NEW-DOMAIN, recording
`:retyped-from` edges, optionally validating them in NEW-DOMAIN, and registering non-refuted laws."
  (let ((created nil))
    (dolist (entry (knowledge-entries-of-kind :law library) (nreverse created))
      (let ((new-law (and (not (equal new-domain (knowledge-entry-domain entry)))
                          (ignore-errors (retype-law entry new-domain)))))
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
                          (equal (knowledge-entry-expression new-law) (knowledge-entry-expression existing))
                          (equal (knowledge-entry-guard new-law) (knowledge-entry-guard existing))))
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
    (consume-entry-executable entry context ledger :guarded-p t :guard-default '(t . t))))

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

(defun make-knowledge-solver (operator &key id (library *knowledge-library*) domain inputs target
                                          position witness guard certified-p trusted-p attested-p
                                          context-map (unique-p t) status work edges metadata ledger)
  "WITNESS, under GUARD, as a `:solver` entry that inverts OPERATOR (an operator, or the name
of one or of a defined function) at POSITION; the entry is not registered. CERTIFIED-P asks
for the exhaustive check of `certify-solver-entry`, TRUSTED-P records an axiom instead, and
ATTESTED-P states that exhaustive law validation has already established witness and
uniqueness; without current witness evidence the entry is a conjecture."
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
    entry))

(defun register-knowledge-solver (operator &rest arguments
                                  &key (library *knowledge-library*) ledger &allow-other-keys)
  "Register the `:solver` entry `make-knowledge-solver` builds from these arguments in LIBRARY."
  (register-knowledge-entry (apply #'make-knowledge-solver operator arguments)
                            :library library :ledger ledger))

;;; Metric decoders: a binary decoder d : (tau, delta) -> tau together with a solver for its
;;; second argument prices a miss in tau by its delta, and is the residual decoder of the
;;; child that then predicts the delta.

(defun register-metric-decoder (solver &key (library *knowledge-library*) tag-bits)
  "Mark SOLVER, a `:solver` entry of LIBRARY (or its id) that inverts a decoder
d : (tau, delta) -> tau in its second argument, as a residual metric of tau: a value y is
described from a prediction p by the delta q(p, y) wherever d(p, q(p, y)) = y. TAG-BITS, by
default what applying d costs a program, is the price of choosing this decoder. The solver's
witness must be provably total; it need not be certified, since every delta is replayed.
Records the edge (:metric-decoder d q tag-bits) on the entry and returns it."
  (let* ((entry (if (knowledge-entry-p solver) solver (find-knowledge-entry solver library)))
         (meta (and entry (knowledge-entry-metadata entry)))
         (operator (and meta (sexp->ast (getf meta :operator))))
         (signature (and operator (operator-type operator))))
    (assert (and entry (eq :solver (knowledge-entry-kind entry))) () "Not a solver entry: ~S" solver)
    (assert (and (= 2 (length (second signature)))
                 (equal (first (second signature)) (third signature))
                 (equal '(1) (solver-positions (getf meta :position)))
                 (equal '((:argument 0) :target)
                        (or (getf meta :context-map) (solver-context-map operator 1))))
            () "~S does not invert a decoder (tau, delta) -> tau in its delta" solver)
    (assert (provably-total-p (knowledge-entry-expression entry)))
    (with-knowledge-library (library)
      (add-knowledge-edge entry :metric-decoder (operator-name operator) (knowledge-entry-id entry)
                          (or tag-bits (application-overhead operator))))
    entry))

(defun metric-decoders (type &optional (library *knowledge-library*) (limit 4))
  "The metric decoders LIBRARY holds for TYPE, cheapest tag first and at most LIMIT of them,
each as (operator solver-entry tag-bits delta-type)."
  (let ((found nil))
    (dolist (entry (knowledge-entries-of-kind :solver library))
      (when (knowledge-entry-active-p entry)
        (let ((edge (first (knowledge-edges-from entry :metric-decoder library))))
          (when edge
            (let* ((operator (sexp->ast (getf (knowledge-entry-metadata entry) :operator)))
                   (signature (operator-type operator)))
              (when (equal type (third signature))
                (push (list operator entry (fourth edge) (second (second signature))) found)))))))
    (let ((ordered (stable-sort (nreverse found) #'< :key #'third)))
      (subseq ordered 0 (min limit (length ordered))))))

(defun metric-delta (decoder predicted target type ledger)
  "The delta from which DECODER, an element of `metric-decoders` for TYPE, rebuilds TARGET
from PREDICTED, and its price in bits, as two values; nil when the solver has no witness
there or its witness does not replay through the decoder."
  (destructuring-bind (operator entry tag-bits delta-type) decoder
    (let ((solved (evaluate-guarded-entry entry (list predicted target) ledger)))
      (when (and solved (eq :value (evaluation-status solved)))
        (let* ((delta (evaluation-value solved))
               (replay (evaluate (app operator (lit type predicted) (lit delta-type delta))
                                 nil nil :ledger ledger)))
          (when (and (eq :value (evaluation-status replay))
                     (equal target (evaluation-value replay)))
            (values delta (+ tag-bits (value-bit-size delta delta-type)))))))))

(defun metric-decoder-library (decoder)
  "A propagator library holding only the solver of DECODER, an element of `metric-decoders`."
  (make-propagator-library :rules (list (knowledge-entry->propagator-rule (second decoder)))))

(defun evaluate-guarded-entry (entry context ledger)
  "Evaluate ENTRY's expression on CONTEXT when its guard holds there; nil when it does not."
  (consume-entry-executable entry context ledger :guarded-p t))

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
