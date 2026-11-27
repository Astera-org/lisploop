(in-package #:lisploop)

;;; ===========================================================================
;;; 1. Test Harness, Clean State Isolation & Core Semantic Assertions
;;; ===========================================================================

(defvar *tests* nil)
(defvar *checks* 0)

(defmacro check (form)
  `(progn (incf *checks*) (unless ,form (error "Check failed: ~S" ',form))))

(defmacro raises (form)
  `(check (handler-case (progn ,form nil) (error () t))))

(defmacro deftest (name &body body)
  `(progn (defun ,name () ,@body) (push ',name *tests*)))

(defmacro with-clean-kernel-state (&body body)
  "Execute BODY inside an isolated, fresh `knowledge-library` (with its own function table,
registered names, de-novo counter, and knowledge entries) and restore outer state on exit."
  `(with-knowledge-library ((make-knowledge-library))
     ,@body))

(defun result (expression &optional inputs values)
  (let ((state (evaluate expression inputs values)))
    (check (eq (evaluation-status state) :value))
    (evaluation-value state)))

(defun accepts (requirement value)
  (let ((state (check-requirement requirement value)))
    (check (eq (evaluation-status state) :value))
    (evaluation-value state)))

(defun outcome-signature (expression inputs values)
  "Observable evaluation outcome: (:value val), (:error), (:unresolved), or (:unknown)."
  (let ((run (evaluate expression inputs values)))
    (list (evaluation-status run)
          (when (eq :value (evaluation-status run))
            (evaluation-value run)))))

(defun check-codec-roundtrip (expression inputs)
  (let ((bits (encode-model expression inputs)))
    (check (= (length bits) (description-size expression inputs)))
    (multiple-value-bind (decoded schema) (decode-model bits)
      (check (equal expression decoded))
      (check (equal inputs schema)))
    (raises (decode-model (subseq bits 0 (1- (length bits)))))
    (raises (decode-model (concatenate 'bit-vector bits #*0)))))

(defun replay-model (expression frame &optional ledger)
  "Decode a fresh model, pass declared values only, and separately check each output."
  (multiple-value-bind (model inputs)
      (decode-model (encode-model expression (schema-inputs (frame-schema frame))))
    (check (equal inputs (schema-inputs (frame-schema frame))))
    (let ((target-type (schema-target (frame-schema frame))))
      (loop for row in (frame-rows frame) sum
        (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
          (check (eq (evaluation-status run) :value))
          (let ((ok (check-requirement (row-requirement row) (evaluation-value run)
                                       :ledger ledger :type target-type)))
            (check (and (eq (evaluation-status ok) :value) (evaluation-value ok))))
          (evaluation-work run))))))

(defun frame-satisfied-by-p (expression frame)
  "True when EXPRESSION meets every constrained row of FRAME."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (every (lambda (row)
             (or (equal (lit :bool t) (row-requirement row))
                 (let ((run (evaluate expression inputs (row-known row))))
                   (and (eq :value (evaluation-status run))
                        (accepts (row-requirement row) (evaluation-value run))))))
           (frame-rows frame))))

(defun same-set-p (xs ys &key (key #'identity) (test #'equal))
  "Order-independent set equality under KEY and TEST."
  (and (= (length (remove-duplicates xs :key key :test test))
          (length (remove-duplicates ys :key key :test test)))
       (null (set-exclusive-or xs ys :key key :test test))))

(defun canonical-expression-sort (expressions inputs)
  "Deterministically sort unique EXPRESSIONS by canonical codec order under INPUTS."
  (sort (remove-duplicates (copy-list expressions) :test #'equal)
        (lambda (a b) (expression-less-p a b inputs))))

(defun enumerated-expressions (job-or-enumerator)
  "Return all expressions materialized so far by a `search-job`, `observation-job`, or `enumerator`,
without coupling tests to internal hash-table bucket layouts."
  (let ((enum (etypecase job-or-enumerator
                (enumerator job-or-enumerator)
                (search-job (search-job-enumerator job-or-enumerator))
                (observation-job (observation-job-enumerator job-or-enumerator)))))
    (loop for bucket being the hash-values of (enumerator-buckets enum)
          append (coerce bucket 'list))))

(defun canonical-ledger-alist (ledger)
  "Order-normalized `(category . work)` alist for LEDGER."
  (sort (copy-alist (ledger-counts ledger))
        #'string< :key (lambda (pair) (symbol-name (car pair)))))

;;; ===========================================================================
;;; 2. Semantic Anytime Resumption Contract Helpers
;;; ===========================================================================

(defun default-resumption-limits (total &key exhaustive-p)
  (cond ((<= total 0) '(0))
        ((or exhaustive-p (<= total 64))
         (loop for k from 0 to total collect k))
        (t
         (sort (remove-duplicates
                (list 0 1 2 5 13
                      (floor total 4)
                      (floor total 2)
                      (floor (* 3 total) 4)
                      (max 0 (1- total))
                      total))
               #'<))))

(defun check-anytime-resumption
    (&key make-job advance work-fn finished-fn view-fn score-fn
          limits exhaustive-p (view-test #'equal) (check-exact-intermediate-work-p nil))
  "Validate the semantic anytime contract between a batch execution and a stepped execution:
1. Strict budget obedience (`work <= limit`) at every resume point (no synchronous budget leaks).
2. Monotone non-decreasing work and (when SCORE-FN is provided) monotone non-increasing score.
3. Terminal work parity and semantic equivalence of observable outcomes (`VIEW-FN`), without
   coupling to internal struct phases, debt counters, closures, or hash/alist ordering."
  (let ((batch (funcall make-job))
        (stepped (funcall make-job)))
    (funcall advance batch :final nil)
    (let* ((total (funcall work-fn batch))
           (schedule (or limits (default-resumption-limits total :exhaustive-p exhaustive-p)))
           (prev-work 0)
           (prev-score most-positive-fixnum))
      (dolist (limit schedule)
        (let ((capped (min limit total)))
          (funcall advance stepped :limit capped)
          (let ((w (funcall work-fn stepped)))
            (check (<= w capped))
            (check (>= w prev-work))
            (when (and check-exact-intermediate-work-p (< capped total))
              (check (= w capped)))
            (setf prev-work w))
          (when score-fn
            (let ((s (funcall score-fn stepped)))
              (when s
                (check (<= s prev-score))
                (setf prev-score s))))
          (when (and finished-fn (< capped total))
            (check (not (funcall finished-fn stepped))))))
      (when (< (funcall work-fn stepped) total)
        (funcall advance stepped :limit total))
      (when finished-fn
        (check (eq (not (null (funcall finished-fn batch)))
                   (not (null (funcall finished-fn stepped))))))
      (check (= total (funcall work-fn stepped)))
      (check (funcall view-test (funcall view-fn batch) (funcall view-fn stepped)))
      (values batch stepped))))

(defun check-evaluation-resumption (expression inputs values &key (budget 1000000) limits exhaustive-p)
  (check-anytime-resumption
   :make-job (lambda () (start-evaluation expression inputs values))
   :advance (lambda (ev &key limit final)
              (declare (ignore final))
              (let ((target (or limit budget)))
                (loop while (and (eq :unknown (evaluation-status ev))
                                 (< (evaluation-work ev) target))
                      do (advance-evaluation ev 1))))
   :work-fn #'evaluation-work
   :finished-fn (lambda (ev) (not (eq :unknown (evaluation-status ev))))
   :view-fn (lambda (ev)
              (list (evaluation-status ev)
                    (when (eq :value (evaluation-status ev)) (evaluation-value ev))))
   :limits limits
   :exhaustive-p exhaustive-p
   :check-exact-intermediate-work-p t))

(defun check-search-resumption (make-job-fn bound &key (budget 1000000) limits exhaustive-p)
  (let ((last-batch-claim nil)
        (last-step-claim nil))
    (multiple-value-prog1
        (check-anytime-resumption
         :make-job make-job-fn
         :advance (lambda (job &key limit final)
                    (declare (ignore final))
                    (let ((msg (resume-search job bound (or limit budget))))
                      (if limit
                          (setf last-step-claim (message-claim msg))
                          (setf last-batch-claim (message-claim msg)))))
         :work-fn (lambda (job) (ledger-total (search-job-ledger job)))
         :score-fn (lambda (job) (and (search-job-best job) (candidate-size (search-job-best job))))
         :view-fn (lambda (job)
                    (let ((inputs (schema-inputs (frame-schema (search-job-frame job)))))
                      (list (search-job-completed-bound job)
                            (and (search-job-best job) (candidate-size (search-job-best job)))
                            (and (search-job-best job)
                                 (candidate-score (search-job-best job) (search-job-run-weight job)))
                            (canonical-expression-sort
                             (mapcar #'candidate-expression (search-job-results job))
                             inputs))))
         :limits limits
         :exhaustive-p exhaustive-p)
      (check (eq last-batch-claim last-step-claim)))))

(defun check-observation-resumption (make-job-fn bound &key (budget 1000000) limits exhaustive-p)
  (check-anytime-resumption
   :make-job make-job-fn
   :advance (lambda (job &key limit final)
              (declare (ignore final))
              (resume-observation-search job bound (or limit budget)))
   :work-fn (lambda (job) (ledger-total (observation-job-ledger job)))
   :view-fn (lambda (job)
              (list (observation-job-completed-bound job)
                    (length (observation-job-records job))
                    (mapcar (lambda (b)
                              (list (observation-bucket-type b)
                                    (observation-bucket-values b)
                                    (observation-bucket-invariant-p b)
                                    (length (observation-bucket-members b))))
                            (observation-job-buckets job))))
   :limits limits
   :exhaustive-p exhaustive-p))

(defun check-law-validation-resumption (make-validation-fn &key (budget 1000000) limits exhaustive-p)
  (check-anytime-resumption
   :make-job make-validation-fn
   :advance (lambda (val &key limit final)
              (declare (ignore final))
              (resume-law-validation val (or limit budget)))
   :work-fn (lambda (val) (ledger-total (law-validation-ledger val)))
   :finished-fn (lambda (val) (not (eq :unknown (law-validation-status val))))
   :view-fn (lambda (val)
              (list (law-validation-status val)
                    (law-validation-counterexample val)
                    (let ((cert (law-validation-certificate val)))
                      (and cert (list (getf cert :method)
                                      (getf cert :assignments)
                                      (getf cert :active))))))
   :limits limits
   :exhaustive-p exhaustive-p))

(defun check-rewriting-resumption (make-rewriting-fn &key (budget 1000000) limits exhaustive-p)
  (check-anytime-resumption
   :make-job make-rewriting-fn
   :advance (lambda (rw &key limit final)
              (declare (ignore final))
              (let ((target (or limit budget)))
                (when (> target (rewriting-work rw))
                  (advance-rewriting rw (- target (rewriting-work rw))))))
   :work-fn #'rewriting-work
   :finished-fn (lambda (rw) (eq :complete (rewriting-status rw)))
   :view-fn (lambda (rw)
              (list (rewriting-status rw)
                    (rewriting-value rw)
                    (rewriting-steps rw)))
   :limits limits
   :exhaustive-p exhaustive-p))

(defun check-heuristic-search-resumption (make-job-fn &key (budget 1000000) limits exhaustive-p)
  (check-anytime-resumption
   :make-job make-job-fn
   :advance (lambda (job &key limit final)
              (declare (ignore final))
              (resume-heuristic-search job (or limit budget)))
   :work-fn (lambda (job) (ledger-total (heuristic-search-ledger job)))
   :score-fn (lambda (job)
               (and (heuristic-search-best job)
                    (heuristic-score (heuristic-search-best job))))
   :view-fn (lambda (job)
              (let ((best (heuristic-search-best job)))
                (and best
                     (list (heuristic-program best)
                           (heuristic-exact-p best)
                           (heuristic-score best)
                           (heuristic-residual best)))))
   :limits limits
   :exhaustive-p exhaustive-p))

(defun check-synthesis-resumption (make-job-fn &key (budget 1000000) stop-on-first limits exhaustive-p)
  (check-anytime-resumption
   :make-job make-job-fn
   :advance (lambda (job &key limit final)
              (declare (ignore final))
              (resume-synthesis job (or limit budget) :stop-on-first stop-on-first))
   :work-fn (lambda (job) (ledger-total (synthesis-job-ledger job)))
   :score-fn (lambda (job)
               (and (synthesis-job-best job)
                    (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))))
    :view-fn (lambda (job)
              (let ((best (synthesis-job-best job))
                    (inputs (schema-inputs (frame-schema (synthesis-node-frame (synthesis-job-root job))))))
                (list (synthesis-finished-p job)
                      (and best (candidate-size best))
                      (and best (candidate-score best (synthesis-job-run-weight job)))
                      (canonical-expression-sort
                       (mapcar #'candidate-expression (synthesis-job-results job))
                       inputs))))
   :limits limits
   :exhaustive-p exhaustive-p))

;;; ===========================================================================
;;; 3. Declarative Synthesis & Library Abstraction Contract Validators
;;; ===========================================================================

(defun check-synthesized-model (expression frame &key held-out (require-total-p t)
                                                      (check-codec-p t) must-call-ops max-bits)
  "Verify EXPRESSION as a valid, serializable, generalizing solution to FRAME."
  (check expression)
  (let ((inputs (schema-inputs (frame-schema frame))))
    (when check-codec-p
      (check-codec-roundtrip expression inputs))
    (when require-total-p
      (check (provably-total-p expression)))
    (when max-bits
      (check (<= (description-size expression inputs) max-bits)))
    (dolist (op-name must-call-ops)
      (check (contains-call-to-p expression op-name)))
    ;; Verify every constrained row of FRAME
    (dolist (row (frame-rows frame))
      (unless (or (equal (lit :bool t) (row-requirement row))
                  (member :unresolved (row-known row)))
        (let ((val (result expression inputs (row-known row))))
          (check (accepts (row-requirement row) val)))))
    ;; Verify held-out generalization examples: each entry is (args expected-value)
    (dolist (case-spec held-out)
      (destructuring-bind (args expected) case-spec
        (check (equal expected (result expression inputs args)))))
    expression))

(defun check-synthesis-task (frame language bound
                             &key (budget 100000) (runner :heuristic) (stop-on-first t)
                                  held-out (require-total-p t) must-call-ops max-bits
                                  self-name library max-depth expand decompositions
                                  policy priority-predictor (deductive-nogoods-p t) debug-p)
  "Run a synthesis task via RUNNER (`:heuristic`, `:recursive`, or `:direct`) and verify semantic
soundness, totality, serialization, and held-out generalization."
  (let ((job (ecase runner
               (:recursive
                (start-recursive-synthesis frame language bound
                                           :self-name (or self-name :fa)
                                           :library library
                                           :debug-p debug-p))
               (:heuristic
                (start-heuristic-synthesis frame language bound
                                           :library library
                                           :max-depth (or max-depth 2)
                                           :priority-predictor priority-predictor
                                           :deductive-nogoods-p deductive-nogoods-p
                                           :debug-p debug-p))
               (:direct
                (start-synthesis frame language bound
                                 :decompositions decompositions
                                 :expand expand
                                 :max-depth max-depth
                                 :policy (or policy :heuristic)
                                 :priority-predictor priority-predictor
                                 :deductive-nogoods-p deductive-nogoods-p
                                 :debug-p debug-p)))))
    (resume-synthesis job budget :stop-on-first stop-on-first)
    (check (synthesis-job-best job))
    (let* ((cand (synthesis-job-best job))
           (expr (candidate-expression cand)))
      (when (and (eq runner :recursive) self-name require-total-p)
        (let ((fdef (find-function-definition self-name)))
          (when fdef (check (function-definition-total-p fdef)))))
      (check-synthesized-model expr frame
                               :held-out held-out
                               :require-total-p require-total-p
                               :must-call-ops must-call-ops
                               :max-bits max-bits)
      (values expr job cand))))

(defun check-library-abstractions-contract
    (corpus &key (register-p t) rewrite-library (min-gain 0) expected-count held-out-by-name ledger)
  "Validate `discover-library-abstractions` by compression, typing, totality, and held-out
semantics rather than brittle de-novo naming order or hardcoded bit-gain integers."
  (multiple-value-bind (accepted refactored all-candidates out-ledger)
      (discover-library-abstractions corpus
                                     :register-p register-p
                                     :rewrite-library rewrite-library
                                     :min-gain min-gain
                                     :ledger ledger)
    (when expected-count
      (check (= expected-count (length accepted))))
    (dolist (abs accepted)
      (check (library-abstraction-p abs))
      (check (< (library-abstraction-refactored-bits abs)
                (library-abstraction-original-bits abs)))
      (check (> (library-abstraction-gain abs) min-gain))
      (check (plusp (library-abstraction-work abs)))
      (check-codec-roundtrip (library-abstraction-body abs)
                             (library-abstraction-inputs abs))
      (when register-p
        (let ((def (find-function-definition (library-abstraction-name abs))))
          (check def)
          (check (or (function-definition-total-p def)
                     (function-definition-conditional-code-params def))))))
    (when register-p
      (loop for item in corpus
            for rdef in refactored
            for pname = (if (function-definition-p item)
                            (function-definition-name item)
                            (getf item :name))
            for cases = (cdr (assoc pname held-out-by-name :test #'eq))
            do (check (function-definition-total-p rdef))
               (check (provably-total-p (function-definition-body rdef)))
               (check-codec-roundtrip (function-definition-body rdef)
                                      (function-definition-inputs rdef))
               (dolist (case-spec cases)
                 (destructuring-bind (args expected) case-spec
                   (check (equal expected
                                 (result (function-definition-body rdef)
                                         (function-definition-inputs rdef)
                                         args)))))))
    (values accepted refactored all-candidates out-ledger)))

;;; ===========================================================================
;;; 4. Shared Reference Enumerators & Evaluators
;;; ===========================================================================

(defun reference-node-trees (leaves operators applications)
  "Enumerate by application count, independently of the size-indexed search."
  (if (zerop applications) leaves
      (loop for left-count below applications append
        (loop for left in (reference-node-trees leaves operators left-count) append
          (loop for right in (reference-node-trees leaves operators (- applications 1 left-count)) append
            (loop for operator in operators collect (app operator left right)))))))

(defun reference-typed-trees (leaves operators max-applications &optional (inputs nil) (max-bits nil))
  "Independent multi-arity typed reference enumerator up to MAX-APPLICATIONS (and optional MAX-BITS)."
  (let ((by-apps (make-array (1+ max-applications) :initial-element nil)))
    (setf (aref by-apps 0) (copy-list leaves))
    (loop for apps from 1 to max-applications do
      (let ((acc nil))
        (dolist (op-term operators)
          (let* ((sort (operator-type op-term))
                 (arg-types (second sort))
                 (arity (length arg-types)))
            (labels ((partitions (rem k)
                       (cond ((zerop k) (when (zerop rem) (list nil)))
                             ((= k 1) (list (list rem)))
                             (t (loop for first from 0 to rem
                                      append (mapcar (lambda (rest) (cons first rest))
                                                     (partitions (- rem first) (1- k)))))))
                     (tuples (counts types)
                       (if (null counts)
                           (list nil)
                           (loop for arg in (aref by-apps (first counts))
                                 when (equal (expression-type arg inputs) (first types))
                                 append (mapcar (lambda (rest) (cons arg rest))
                                                (tuples (rest counts) (rest types)))))))
              (dolist (counts (partitions (1- apps) arity))
                (dolist (args (tuples counts arg-types))
                  (push (apply #'app op-term args) acc))))))
        (setf (aref by-apps apps) (nreverse acc))))
    (let ((all (loop for apps from 0 to max-applications append (aref by-apps apps))))
      (if max-bits
          (remove-if (lambda (e) (> (description-size e inputs) max-bits)) all)
          all))))

(defun reference-one-application (domain inputs operators bound)
  "Independent exhaustive reference: this bound permits leaves and ONE binary app."
  (let* ((leaves (append (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs)
                         (loop for i below (second domain) collect (lit domain i))))
         (candidates (copy-list leaves)))
    (dolist (operator operators)
      (dolist (left leaves)
        (dolist (right leaves) (push (app operator left right) candidates))))
    (check (< bound (+ (header-size inputs domain)
                       (* 3 (reduce #'min leaves :key (lambda (e) (body-size e inputs)))) 10)))
    (remove-if (lambda (expression) (> (description-size expression inputs) bound)) candidates)))

(defun reference-value (expression inputs prime)
  (case (ast-kind expression)
    (:lit (ast-value expression))
    (:var (cdr (assoc (ast-id expression) inputs)))
    (:app
     (let ((a (reference-value (first (rest expression)) inputs prime))
           (b (reference-value (second (rest expression)) inputs prime)))
       (ecase (operator-name (first expression))
         (:+ (mod (+ a b) prime)) (:* (mod (* a b) prime)))))))

(defun integer-reference-value (expression inputs)
  "Independent arithmetic oracle for the tiny integer grammar; no simulator calls."
  (ecase (ast-kind expression)
    (:lit (ast-value expression))
    (:var (cdr (assoc (ast-id expression) inputs)))
    (:app
     (let ((values (mapcar (lambda (e) (integer-reference-value e inputs)) (rest expression))))
       (ecase (operator-name (first expression))
         (:+ (+ (first values) (second values)))
         (:* (* (first values) (second values))))))))

;;; ===========================================================================
;;; 5. Pure-Kernel Propagator, Law, Combinator & Observation Fixtures
;;; ===========================================================================

(defun checked-law (law)
  (let ((validation (resume-law-validation (start-law-validation law) 1000000)))
    (check (eq :validated (law-validation-status validation)))
    validation))

(defun normalize-for-test (expression inputs validations domain)
  (let ((state (start-rewriting expression inputs (prepare-rewrite-library validations domain))))
    (advance-rewriting state 10000000)
    (check (eq :complete (rewriting-status state)))
    (rewriting-value state)))

(defun validation-for-equation (validations left right)
  (or (find-if (lambda (state)
                 (let ((sides (rest (knowledge-entry-expression (law-validation-law state)))))
                   (or (equal sides (list left right)) (equal sides (list right left)))))
               validations)
      (error "Required identity was not discovered")))

(defun register-kernel-arithmetic-solver (domain name position &key (library *knowledge-library*))
  "Register in LIBRARY the inverse of the arithmetic operator NAME at POSITION over DOMAIN, from
the `arithmetic` battery (library/arithmetic.lisp), and return its entry. Finite-field rules
are exhaustively certified; integer rules remain tentative, and those of addition and
subtraction are unique by axiom."
  (first (load-battery :arithmetic
                       :types (list (cons '?n domain))
                       :only (list (keyword-id "SOLVE-~A-~D" name position))
                       :library library)))

(defun kernel-propagator-library (domain &key (operators '(:+ :- :* :/)) (positions '(0 1)) ledger)
  "Construct an isolated `propagator-library` for DOMAIN using only kernel solver registration."
  (declare (ignore ledger))
  (let ((temp-lib (make-knowledge-library)))
    (dolist (op-name operators)
      (dolist (pos positions)
        (register-kernel-arithmetic-solver domain op-name pos :library temp-lib)))
    (as-propagator-library temp-lib)))

(defun define-standard-int-combinators (&key (which '(:map :foldr :filter)))
  "Register the standard higher-order combinators over `(:seq :int)` named by WHICH in the
active library, from the `sequences` battery (`library/sequences.sexp`), in its order."
  (let ((entries
          (load-battery :sequences
                        :only (if (and (member :map which) (member :filter which))
                                  (append which '(:comprehension/filter-map))
                                  which))))
    (remove-if-not (lambda (e) (eq :function (knowledge-entry-kind e))) entries)))

(defun install-sequence-shift-metric ()
  "Load the `sequence-shift` battery (library/sequence-shift.lisp) into the active library:
the decoder `:shift-seq`, its correlation solver, and their registration as a metric decoder
of `(:seq :int)`. Returns the solver entry."
  (first (last (load-battery :sequence-shift))))

(defun standard-r4-corpus (&key (self-name :fa))
  "Build the standard 6-program recursive list corpus (`:copy`, `:inc-all`, `:double-all`,
`:sum`, `:length`, `:product`) without redundantly re-running 6 synthesis searches."
  (let* ((seq-type (sequence-type :int))
         (inputs (list (cons 0 seq-type)))
         (xs (var 0 seq-type))
         (empty-xs (app (op := seq-type) xs (lit seq-type '())))
         (head-x0 (app (op :at seq-type) xs (lit :int 0)))
         (tail-x0 (app (op :tail :int) xs)))
    (flet ((entry (name ret build-fn)
             (let ((body (call-with-temporary-function-names
                          (list self-name)
                          (lambda ()
                            (funcall build-fn (op self-name (code-type inputs ret)))))))
               (list :name name :inputs inputs :return-type ret :body body :self-name self-name))))
      (list (entry :copy seq-type
                   (lambda (self)
                     (app (op :if seq-type) empty-xs (lit seq-type '())
                          (app (op :cons :int) head-x0 (app self tail-x0)))))
            (entry :inc-all seq-type
                   (lambda (self)
                     (app (op :if seq-type) empty-xs xs
                          (app (op :cons :int) (app (op :+ :int) head-x0 (lit :int 1))
                               (app self tail-x0)))))
            (entry :double-all seq-type
                   (lambda (self)
                     (app (op :if seq-type) empty-xs xs
                          (app (op :cons :int) (app (op :+ :int) head-x0 head-x0)
                               (app self tail-x0)))))
            (entry :sum :int
                   (lambda (self)
                     (app (op :if :int) empty-xs (lit :int 0)
                          (app (op :+ :int) head-x0 (app self tail-x0)))))
            (entry :length :int
                   (lambda (self)
                     (app (op :if :int) empty-xs (lit :int 0)
                          (app (op :+ :int) (app self tail-x0) (lit :int 1)))))
            (entry :product :int
                   (lambda (self)
                     (app (op :if :int) empty-xs (lit :int 1)
                          (app (op :* :int) head-x0 (app self tail-x0)))))))))

(defun gf5-fixture (&optional ledger)
  "The oracle generates observations only; neither its syntax nor sketch enters search."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (oracle (app (op :+ field) (var 0 field)
                      (app (op :* field) (lit field 2) (var 1 field))))
         (records
           (loop for a below 5 append
             (loop for b below 5 for key from (* a 5) collect
               (let ((run (evaluate oracle inputs (list a b) :ledger ledger)))
                 (check (eq (evaluation-status run) :value))
                 (list key a b (evaluation-value run)))))))
    (values (orient-observations (list field field field) records '(0 1) '(2)
                                  :lookup-p t :ledger ledger)
            oracle records)))

(defun additive-transition-fixture (domain starts steps shift-b key-prefix ledger)
  "Record forward transitions T(a,b)=(a+1,b+SHIFT-B). Return the frame and start keys."
  (check (and (integerp steps) (plusp steps)))
  (let* ((field domain) (state-type (tuple-type field field))
         (inputs (list (cons 0 field) (cons 1 field)))
         (transition (app (op :tuple state-type)
                          (app (op :+ field) (var 0 field) (lit field 1))
                          (app (op :+ field) (var 1 field) (lit field shift-b))))
         (rows nil) (anchors nil))
    (loop for start in starts for orbit from 0 do
      (let ((state start))
        (dotimes (step steps)
          (let* ((key (list key-prefix orbit step))
                 (run (evaluate transition inputs state :ledger ledger)))
            (check (eq (evaluation-status run) :value))
            (when (zerop step) (push (list key :before) anchors))
            (push (make-row :key key :known state
                            :requirement (set-requirement state-type (list (evaluation-value run)))) rows)
            (setf state (evaluation-value run))))))
    (values (make-frame (make-schema :inputs inputs :target state-type) (nreverse rows))
            (nreverse anchors))))

(defun gf5-transition-fixture (&key (starts '((0 0) (0 1))) (steps 5)
                                  (shift-b 4) (key-prefix :training) ledger)
  (additive-transition-fixture (gf 5) starts steps shift-b key-prefix ledger))

(defun integer-transition-fixture (&key (starts '((-3 1) (0 0) (2 3))) (steps 3)
                                       (shift-b -1) (key-prefix :integer-training) ledger)
  (additive-transition-fixture :int starts steps shift-b key-prefix ledger))

(defun integer-held-out-starts ()
  "Exact cancellation, adjacent large integers, and positive/negative large outputs."
  (let ((n (ash 1 256)))
    (list (list n (- n)) (list (1+ n) (- n))
          (list (- n) n) (list (- (1+ n)) n)
          (list n n) (list (- n) (- n)))))

(defun gf7-iota-conversion (t-expr &key (steps 7) ledger)
  "Declared, metered conversion \\iota(t) from :int index T-EXPR into GF(7)."
  (check (and (integerp steps) (plusp steps)))
  (let* ((field (gf 7))
         (entry-type (tuple-type :int field))
         (entries (loop for step below steps
                        collect (list step (mod step 7))))
         (expr (app (op :lookup entry-type)
                    t-expr
                    (lit (sequence-type entry-type) entries))))
    (charge ledger :construction (syntax-work expr))
    expr))

(defun domain-lifting-fixture (domain &key (offsets '(1 3)) (steps 7) (repetitions 1) schedule ledger)
  "Generate indexed sequences y_{j,t} = a_j + step(t) over DOMAIN (`:int` or `(:gf 7)`).
Returns `(values frame decoder r-to-j-map row-labels records)`."
  (check (and (integerp steps) (plusp steps)))
  (check (and (integerp repetitions) (plusp repetitions)))
  (let* ((seq-tags (or schedule
                       (loop repeat repetitions
                             append (loop for idx below (length offsets) collect idx))))
         (t-term (if (eq domain :int)
                     (var 1 :int)
                     (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger)))
         (decoder (app (op :+ domain) t-term (var 9 domain)))
         (oracle-inputs (list (cons 0 domain) (cons 1 :int)))
         (oracle (app (op :+ domain) (var 0 domain)
                      (if (eq domain :int)
                          (var 1 :int)
                          (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger))))
         (records nil)
         (row-labels nil))
    (charge ledger :construction (syntax-work decoder))
    (loop for tag in seq-tags
          for r from 0
          for offset = (nth tag offsets)
          do (dotimes (step steps)
               (let* ((key (list :seq r step))
                      (run (evaluate oracle oracle-inputs (list offset step) :ledger ledger)))
                 (check (eq (evaluation-status run) :value))
                 (push tag row-labels)
                 (push (list key r step (evaluation-value run)) records))))
    (setf records (nreverse records)
          row-labels (nreverse row-labels))
    (let* ((frame (orient-observations (list :int :int domain) records '(0 1) '(2)
                                       :lookup-p t :ledger ledger))
           (label-frame (context-label-frame frame row-labels
                                             :bindings (list (cons 0 (var 0 :int)))
                                             :label-type domain
                                             :ledger ledger))
           (r-to-j (lookup-model label-frame ledger)))
      (values frame decoder r-to-j row-labels records))))

(defun gf7-lifting-fixture (&rest args)
  (apply #'domain-lifting-fixture (gf 7) args))

(defun integer-lifting-fixture (&rest args)
  (apply #'domain-lifting-fixture :int args))
