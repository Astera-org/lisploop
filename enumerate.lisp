(in-package #:lisploop)

;;; Module 5: enumerate.lisp
;;; Exact-bit grammar enumerator, unified matrix evaluator (search-job & observation-job),
;;; and multi-lane agenda (propagation-search).

(defstruct (language (:constructor %make-language))
  domain inputs operators (literals :all) constants (version 3))

(defun make-language (domain inputs &key (operators (list (op :+ domain) (op :* domain)))
                                        (literals :all) constants)
  "Finite typed productions over the VM's primitives, including quoted syntax.
LITERALS defaults to :ALL, or declares a finite vocabulary without bounding values.
CONSTANTS supplies additional typed literal ASTs. The default operators stay +/*."
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (assert (valid-inputs-p inputs))
  (mapc #'operator-type operators)
  (dolist (constant constants)
    (assert (lit-p constant))
    (expression-type constant nil))
  (assert (or (eq literals :all)
              (and (listp literals) (every (lambda (value) (value-p value domain)) literals))))
  (%make-language :domain (copy-tree domain) :inputs (copy-tree inputs)
                  :operators (remove-duplicates (copy-tree operators) :test #'equal)
                  :constants (remove-duplicates (copy-tree constants) :test #'equal)
                  :literals (if (eq literals :all) :all
                                (remove-duplicates (copy-list literals) :from-end t))))

(defun snapshot-language (language)
  (let ((snapshot (copy-language language)))
    (setf (language-domain snapshot) (copy-tree (language-domain language))
          (language-inputs snapshot) (copy-tree (language-inputs language))
          (language-operators snapshot) (copy-tree (language-operators language))
          (language-literals snapshot) (copy-tree (language-literals language))
          (language-constants snapshot) (copy-tree (language-constants language)))
    snapshot))

(defun language-header-size (language &optional (target (language-domain language)))
  (header-size (language-inputs language) target))

(defun language-booleans-p (language)
  (or (find :bool (language-inputs language) :key #'cdr)
      (some (lambda (operator)
              (member :bool (cons (third (operator-type operator))
                                  (second (operator-type operator)))))
            (language-operators language))))

(defstruct (enumerator (:constructor make-enumerator (language)))
  language (size 1) (phase :variables) (cursor 0) (literal-pass 0) (literal-index 0)
  literal-next literal-end (boolean-index 0) (constant-index 0) (operator-index 0) sizes indices
  (buckets (make-hash-table :test #'equal)))

(defun syntax-bucket (enumerator type size)
  (gethash (list type size) (enumerator-buckets enumerator)))

(defun index-expression (enumerator expression)
  (let* ((language (enumerator-language enumerator))
         (type (expression-type expression (language-inputs language)))
         (key (list type (enumerator-size enumerator)))
         (buckets (enumerator-buckets enumerator)))
    (assert (= (enumerator-size enumerator) (body-size expression (language-inputs language))))
    (unless (gethash key buckets)
      (setf (gethash key buckets) (make-array 0 :adjustable t :fill-pointer 0)))
    (vector-push-extend expression (gethash key buckets))
    type))

(defun literal-range (domain size pass)
  "Exact body-bit intervals, without visiting integers outside the current bound."
  (let ((payload (- size 2)))
    (if (eq domain :int)
        (let ((width (loop for width from 1 to payload
                           when (= payload (+ width (* 2 (1- (integer-length width))))) return width)))
          (if (null width) (values 1 0)
              (let ((lo (ash 1 (1- width))) (hi (1- (ash 1 width))))
                (if (= pass 0)
                    (values (ceiling (1- lo) 2) (floor (1- hi) 2))
                    (values (max 1 (ceiling lo 2)) (floor hi 2))))))
        (if (and (= pass 0) (= payload (integer-length (1- (second domain)))))
            (values 0 (1- (second domain))) (values 1 0)))))

(defun reset-enumerator-bound (enumerator)
  (incf (enumerator-size enumerator))
  (setf (enumerator-phase enumerator) :variables
        (enumerator-cursor enumerator) 0
        (enumerator-literal-pass enumerator) 0
        (enumerator-literal-index enumerator) 0
        (enumerator-literal-next enumerator) nil
        (enumerator-operator-index enumerator) 0
        (enumerator-boolean-index enumerator) 0
        (enumerator-constant-index enumerator) 0
        (enumerator-sizes enumerator) nil
        (enumerator-indices enumerator) nil))

(defun first-composition (total arity)
  (when (>= total arity)
    (append (make-list (1- arity) :initial-element 1) (list (- total (1- arity))))))

(defun next-composition (sizes)
  "Next positive composition of the same total, in lexicographic order."
  (loop for i downfrom (- (length sizes) 2) to 0
        for tail = (nthcdr (1+ i) sizes)
        for total = (reduce #'+ tail)
        when (> total (length tail)) do
          (return (append (subseq sizes 0 i) (list (1+ (nth i sizes)))
                          (make-list (1- (length tail)) :initial-element 1)
                          (list (- total (length tail)))))))

(defun advance-application-cursor (enumerator buckets)
  (let ((indices (enumerator-indices enumerator)))
    (loop for i downfrom (1- (length indices)) to 0 do
      (incf (nth i indices))
      (when (< (nth i indices) (length (nth i buckets))) (return-from advance-application-cursor))
      (setf (nth i indices) 0)))
  (setf (enumerator-sizes enumerator) (next-composition (enumerator-sizes enumerator)))
  (unless (enumerator-sizes enumerator) (incf (enumerator-operator-index enumerator))))

(defun enumeration-step (enumerator)
  "One cursor operation; return (candidate, event). No eager Cartesian products."
  (let* ((language (enumerator-language enumerator))
         (size (enumerator-size enumerator)))
    (ecase (enumerator-phase enumerator)
      (:variables
       (let ((input (nth (enumerator-cursor enumerator) (language-inputs language))))
         (if input
             (progn
               (incf (enumerator-cursor enumerator))
               (let ((expression (var (car input) (cdr input))))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate)))))
             (setf (enumerator-phase enumerator) :literals))))
      (:literals
       (unless (eq (language-literals language) :all)
         (let ((tail (nthcdr (enumerator-literal-index enumerator) (language-literals language))))
           (if tail
               (let ((expression (lit (language-domain language) (first tail))))
                 (incf (enumerator-literal-index enumerator))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate))))
               (setf (enumerator-phase enumerator) :booleans)))
         (return-from enumeration-step (values nil :progress)))
       (if (>= (enumerator-literal-pass enumerator) 2)
           (setf (enumerator-phase enumerator) :booleans)
           (progn
             (unless (enumerator-literal-next enumerator)
               (multiple-value-bind (lo hi)
                   (literal-range (language-domain language) size (enumerator-literal-pass enumerator))
                 (setf (enumerator-literal-next enumerator) lo
                       (enumerator-literal-end enumerator) hi)))
             (if (> (enumerator-literal-next enumerator) (enumerator-literal-end enumerator))
                 (setf (enumerator-literal-next enumerator) nil
                       (enumerator-literal-pass enumerator) (1+ (enumerator-literal-pass enumerator)))
                 (let ((value (enumerator-literal-next enumerator)))
                   (incf (enumerator-literal-next enumerator))
                   (return-from enumeration-step
                     (values (lit (language-domain language)
                                  (if (= 1 (enumerator-literal-pass enumerator)) (- value) value))
                             :candidate)))))))
      (:booleans
       (if (and (= size 3) (language-booleans-p language)
                (< (enumerator-boolean-index enumerator) 2))
           (return-from enumeration-step
             (values (lit :bool (= 1 (prog1 (enumerator-boolean-index enumerator)
                                       (incf (enumerator-boolean-index enumerator))))) :candidate))
           (setf (enumerator-phase enumerator) (if (language-constants language) :constants :applications))))
      (:constants
       (let ((constant (nth (enumerator-constant-index enumerator) (language-constants language))))
         (if constant
             (progn (incf (enumerator-constant-index enumerator))
                    (when (and (= size (body-size constant (language-inputs language)))
                               (not (and (equal (ast-type constant) (language-domain language))
                                         (or (eq :all (language-literals language))
                                             (member (ast-value constant) (language-literals language)))))
                               (not (and (eq :bool (ast-type constant)) (language-booleans-p language))))
                      (return-from enumeration-step (values constant :candidate))))
             (setf (enumerator-phase enumerator) :applications))))
      (:applications
       (let ((operator (nth (enumerator-operator-index enumerator) (language-operators language))))
         (if (null operator)
             (setf (enumerator-phase enumerator) :finish)
             (let ((types (second (operator-type operator))))
               (when (null types)
                 (incf (enumerator-operator-index enumerator))
                 (return-from enumeration-step
                   (if (= size (application-overhead operator)) (values (app operator) :candidate)
                       (values nil :progress))))
               (unless (enumerator-sizes enumerator)
                 (setf (enumerator-sizes enumerator)
                       (first-composition (- size (application-overhead operator)) (length types))
                       (enumerator-indices enumerator) (make-list (length types) :initial-element 0)))
               (if (null (enumerator-sizes enumerator))
                   (incf (enumerator-operator-index enumerator))
                   (let ((buckets (mapcar (lambda (type bits) (syntax-bucket enumerator type bits))
                                          types (enumerator-sizes enumerator))))
                     (if (some #'null buckets)
                         (progn
                           (setf (enumerator-sizes enumerator)
                                 (next-composition (enumerator-sizes enumerator)))
                           (unless (enumerator-sizes enumerator)
                             (incf (enumerator-operator-index enumerator))))
                         (let ((expression (apply #'app operator
                                                  (mapcar #'aref buckets (enumerator-indices enumerator)))))
                           (advance-application-cursor enumerator buckets)
                           (return-from enumeration-step (values expression :candidate))))))))))
      (:finish
       (reset-enumerator-bound enumerator)
       (return-from enumeration-step (values nil :bound))))
    (values nil :progress)))

;;; Search and Matrix Evaluation

(defstruct candidate expression size run-work discovery-work)
(defstruct message call-id claim evidence)

(defstruct (search-job (:constructor %make-search-job))
  call-id frame language enumerator (ledger (make-ledger))
  (mode :enumeration) proposals queue (requested-bound 0)
  (phase :enumerate) expression (construction-debt 0) rows evaluation predicted
  (run-work 0) (completed-bound 0) (results nil) best (run-weight 0)
  (rejected 0) (messages nil) library rewriting normal-form
  (reused-rejections 0) (rejection-cache (make-hash-table :test #'equal)))

(defvar *next-call-id* 0)

(defun start-search (frame language &key (call-id (incf *next-call-id*)) (run-weight 0) laws
                                        (expressions nil supplied-p))
  "Use the canonical enumerator, or check a declared list of complete proposals.
Listed proposals use the SAME construction, VM, checker and objective."
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (let* ((library (when laws (prepare-rewrite-library laws (language-domain language))))
         (job (%make-search-job :call-id call-id :frame frame :language language
                                :mode (if supplied-p :replay :enumeration)
                                :enumerator (unless supplied-p (make-enumerator language))
                                :run-weight run-weight :library library
                                :completed-bound (language-header-size language (schema-target (frame-schema frame))))))
    (when supplied-p
      (let ((queue (remove-duplicates (copy-tree expressions) :test #'equal)))
        (dolist (expression queue) (expression-type expression (language-inputs language)))
        (setf (search-job-queue job)
              (stable-sort queue #'< :key (lambda (expression)
                                           (description-size expression (language-inputs language))))
              (search-job-proposals job) (copy-list (search-job-queue job)))))
    (when library
      (setf (search-job-phase job) :rule-setup
            (search-job-construction-debt job) (rewrite-library-setup-work library)))
    (when supplied-p
      (let ((count (length expressions)))
        (setf (search-job-phase job) :proposal-setup
              (search-job-construction-debt job)
              (+ 1 (* count (1+ (integer-length count)))
                 (reduce #'+ expressions :key #'syntax-work :initial-value 0)))))
    job))

(defun candidate-score (candidate run-weight)
  (+ (candidate-size candidate) (* run-weight (candidate-run-work candidate))))

(defun reject-candidate (job &optional witnessed-p)
  (when (and witnessed-p (search-job-library job))
    (setf (gethash (search-job-normal-form job) (search-job-rejection-cache job))
          (list :row (row-key (first (search-job-rows job))) :value (search-job-predicted job))))
  (incf (search-job-rejected job))
  (setf (search-job-phase job) :enumerate))

(defun accept-candidate (job)
  (let ((candidate (make-candidate :expression (search-job-expression job)
                                   :size (description-size (search-job-expression job)
                                                           (language-inputs (search-job-language job)))
                                   :run-work (search-job-run-work job)
                                   :discovery-work (ledger-total (search-job-ledger job)))))
    (push candidate (search-job-results job))
    (when (or (null (search-job-best job))
              (< (candidate-score candidate (search-job-run-weight job))
                 (candidate-score (search-job-best job) (search-job-run-weight job))))
      (setf (search-job-best job) candidate))
    (push (make-message :call-id (search-job-call-id job) :claim :candidate
                        :evidence candidate) (search-job-messages job))
    (setf (search-job-phase job) :enumerate)))

(defun advance-search-evaluation (job budget category)
  (advance-accounted-evaluation (search-job-evaluation job) budget (search-job-ledger job) category :validation))

(defun search-step (job &optional (budget 1))
  "Advance one search phase using at most BUDGET tariff units."
  (assert (and (integerp budget) (plusp budget)))
  (let ((ledger (search-job-ledger job))
        (schema (frame-schema (search-job-frame job))))
    (ecase (search-job-phase job)
      (:proposal-setup
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :proposal-setup spent) (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job))
         (if (search-job-library job)
             (setf (search-job-phase job) :rule-setup
                   (search-job-construction-debt job) (rewrite-library-setup-work (search-job-library job)))
             (setf (search-job-phase job) :enumerate))))
      (:rule-setup
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :rule-setup spent) (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job)) (setf (search-job-phase job) :enumerate)))
      (:enumerate
       (charge ledger :enumeration)
       (multiple-value-bind (expression event)
           (if (search-job-enumerator job)
               (enumeration-step (search-job-enumerator job))
               (values (pop (search-job-queue job)) :candidate))
         (case event
           (:candidate
            (setf (search-job-expression job) expression
                  (search-job-construction-debt job) (syntax-work expression)
                  (search-job-phase job) :construct))
           (:bound
            (setf (search-job-completed-bound job)
                  (+ (language-header-size (search-job-language job) (schema-target schema))
                     (1- (enumerator-size (search-job-enumerator job)))))))))
      (:construct
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :construction spent)
         (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job))
         (let ((type (if (search-job-enumerator job)
                         (index-expression (search-job-enumerator job) (search-job-expression job))
                         (expression-type (search-job-expression job) (schema-inputs schema)))))
           (if (equal type (schema-target schema))
               (setf (search-job-rows job) (frame-rows (search-job-frame job))
                     (search-job-run-work job) 0
                     (search-job-phase job) (if (search-job-library job) :rewrite-start :row))
               (setf (search-job-phase job) :enumerate)))))
      (:rewrite-start
       (charge ledger :scheduling)
       (setf (search-job-rewriting job)
             (start-rewriting (search-job-expression job) (schema-inputs schema) (search-job-library job))
             (search-job-phase job) :rewrite))
      (:rewrite
       (let ((state (advance-rewriting (search-job-rewriting job) budget ledger)))
         (when (eq :complete (rewriting-status state))
           (setf (search-job-normal-form job) (rewriting-value state)
                 (search-job-construction-debt job) (syntax-work (rewriting-value state))
                 (search-job-phase job) :reuse))))
      (:reuse
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :equality-cache spent) (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job))
         (if (gethash (search-job-normal-form job) (search-job-rejection-cache job))
             (progn (incf (search-job-reused-rejections job)) (reject-candidate job))
             (setf (search-job-phase job) :row))))
      (:row
       (charge ledger :scheduling)
       (if (null (search-job-rows job))
           (accept-candidate job)
           (setf (search-job-evaluation job)
                 (start-evaluation (search-job-expression job) (schema-inputs schema)
                                   (row-known (first (search-job-rows job))))
                 (search-job-phase job) :evaluate)))
      (:evaluate
       (let ((state (advance-search-evaluation job budget :evaluation)))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:value
            (incf (search-job-run-work job) (evaluation-work state))
            (setf (search-job-predicted job) (evaluation-value state)
                  (search-job-phase job) :requirement)))))
      (:requirement
       (charge ledger :scheduling)
       (setf (search-job-evaluation job)
             (start-evaluation (allowed-expression (row-allowed (first (search-job-rows job))))
                               (list (cons 0 (schema-target schema)))
                               (list (search-job-predicted job)))
             (search-job-phase job) :check))
      (:check
       (let ((state (advance-search-evaluation job budget :checking)))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:value
            (if (eq t (evaluation-value state))
                (progn (pop (search-job-rows job)) (setf (search-job-phase job) :row))
                (reject-candidate job t)))))))))

(defun search-bound-complete-p (job bound)
  (if (eq :enumeration (search-job-mode job))
      (>= (search-job-completed-bound job) bound)
      (and (eq :enumerate (search-job-phase job))
           (or (null (search-job-queue job))
               (> (description-size (first (search-job-queue job))
                                    (language-inputs (search-job-language job))) bound)))))

(defun resume-search (job description-limit work-limit &key quantum)
  "Absolute cumulative work limit and total packet-bit bound."
  (assert (and (integerp description-limit) (>= description-limit 0)
               (integerp work-limit) (>= work-limit 0)))
  (assert (or (null quantum) (and (integerp quantum) (plusp quantum))))
  (assert (>= description-limit (search-job-requested-bound job)))
  (setf (search-job-requested-bound job) description-limit)
  (loop while (and (not (search-bound-complete-p job description-limit))
                   (< (ledger-total (search-job-ledger job)) work-limit))
        do (let ((remaining (- work-limit (ledger-total (search-job-ledger job)))))
             (search-step job (if quantum (min quantum remaining) remaining))))
  (when (and (eq :replay (search-job-mode job)) (search-bound-complete-p job description-limit))
    (setf (search-job-completed-bound job) description-limit))
  (let ((message
          (make-message
           :call-id (search-job-call-id job)
           :claim (cond ((not (search-bound-complete-p job description-limit)) :cutoff)
                        ((eq :replay (search-job-mode job)) :replay-complete)
                        (t :bounded-exhaustion))
           :evidence (list :description-limit description-limit
                           :completed-bound (search-job-completed-bound job)
                           :work (ledger-total (search-job-ledger job))
                           :phase (search-job-phase job)
                           :syntax-coverage (if (eq :replay (search-job-mode job)) :listed-expressions :grammar)
                           :encoding-version +encoding-version+ :tariff-version +tariff-version+
                           :language-version (language-version (search-job-language job))))))
    (push message (search-job-messages job))
    message))

;;; Empirical Observations & Equivalence Buckets

(defstruct (observation-scope (:constructor %make-observation-scope))
  id frame language pairs anchors
  (equality :typed-value) (evidence :replayed-observations) (simulator-version +simulator-version+)
  (encoding-version +encoding-version+) (tariff-version +tariff-version+))

(defun make-observation-scope (frame language &key (id (incf *next-call-id*)) pairs anchors)
  "Freeze the observed inputs and language. PAIRS and ANCHORS refer to row keys."
  (assert (frame-rows frame) () "An empirical scope needs observations")
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (or (null anchors) (and pairs (>= (length anchors) 2))))
  (assert (= (length anchors) (length (remove-duplicates anchors :test #'equal))))
  (let* ((schema (copy-schema (frame-schema frame)))
         (rows (mapcar (lambda (row)
                         (make-row :key (copy-tree (row-key row))
                                   :known (copy-tree (row-known row)) :allowed (row-allowed row)))
                       (frame-rows frame)))
         (snapshot (snapshot-language language)))
    (setf (schema-inputs schema) (copy-tree (schema-inputs schema))
          (schema-target schema) (copy-tree (schema-target schema)))
    (labels ((index (key)
               (or (position key rows :key #'row-key :test #'equal)
                   (error "Unknown observation key ~S" key))))
      (dolist (pair pairs)
        (assert (= (length pair) 2))
        (assert (not (equal (first pair) (second pair)))))
      (dolist (key anchors)
        (assert (member key pairs :key #'first :test #'equal)))
      (%make-observation-scope
       :id id :frame (make-frame schema rows) :language snapshot
       :pairs (mapcar (lambda (pair) (mapcar #'index pair)) pairs)
       :anchors (mapcar #'index anchors)))))

(defstruct observation-outcome status value error (work 0))
(defstruct observed-expression scope expression type (status :unknown)
  values outcomes (run-work 0) error failed-key)
(defstruct observation-bucket scope type values members invariant-p informative-p counterexample)

(defun observed-agreement-p (left right)
  "Agreement only between total evaluations in the exact same observation scope."
  (and left right
       (eq (observed-expression-scope left) (observed-expression-scope right))
       (eq (observed-expression-status left) :complete)
       (eq (observed-expression-status right) :complete)
       (equal (observed-expression-type left) (observed-expression-type right))
       (equal (observed-expression-values left) (observed-expression-values right))))

(defstruct (observation-job (:constructor %make-observation-job))
  scope enumerator (mode :enumeration) queue (ledger (make-ledger))
  (phase :enumerate) current rows evaluation (outputs nil) (debt 0)
  retain-outcomes-p (outcomes nil)
  (completed-bound 0) (requested-bound 0) records buckets messages
  (record-index (make-hash-table :test #'equal))
  (bucket-index (make-hash-table :test #'equal)))

(defun start-observation-search (scope &key (expressions nil supplied-p) retain-outcomes)
  (let* ((language (observation-scope-language scope))
         (queue (when supplied-p (remove-duplicates (copy-tree expressions) :test #'equal)))
         (job (%make-observation-job :scope scope :retain-outcomes-p (not (null retain-outcomes))
                                     :mode (if supplied-p :replay :enumeration)
                                     :enumerator (unless supplied-p (make-enumerator language))
                                     :completed-bound (if supplied-p 0 (language-header-size language
                                                        (schema-target (frame-schema (observation-scope-frame scope))))))))
    (dolist (expression queue)
      (expression-type expression (language-inputs language)))
    (setf (observation-job-queue job)
          (stable-sort queue #'< :key (lambda (expression) (description-size expression (language-inputs language)))))
    (setf (observation-job-phase job) :setup
          (observation-job-debt job)
          (+ (length queue) (length (observation-scope-pairs scope))
             (length (observation-scope-anchors scope))
             (loop for row in (frame-rows (observation-scope-frame scope))
                   sum (1+ (loop for value in (row-known row)
                                 for spec in (language-inputs language)
                                 sum (value-work value (cdr spec)))))))
    job))

(defun find-observation (job expression)
  (gethash expression (observation-job-record-index job)))

(defun observation-invariants (job)
  (remove-if-not #'observation-bucket-informative-p (reverse (observation-job-buckets job))))

(defun classify-observation-bucket (bucket)
  (let* ((scope (observation-bucket-scope bucket))
         (values (coerce (observation-bucket-values bucket) 'vector))
         (pairs (observation-scope-pairs scope))
         (anchors (observation-scope-anchors scope))
         (failed (find-if (lambda (pair)
                            (not (equal (aref values (first pair)) (aref values (second pair))))) pairs)))
    (setf (observation-bucket-invariant-p bucket) (and pairs (null failed))
          (observation-bucket-informative-p bucket)
          (and pairs (null failed) anchors
               (not (every (lambda (index) (equal (aref values index) (aref values (first anchors))))
                           (rest anchors)))))
    (when failed
      (let ((rows (frame-rows (observation-scope-frame scope))))
        (setf (observation-bucket-counterexample bucket)
              (list :before-key (row-key (nth (first failed) rows))
                    :after-key (row-key (nth (second failed) rows))
                    :before-value (aref values (first failed))
                    :after-value (aref values (second failed)))))))
  bucket)

(defun finish-observation (job)
  (let* ((record (observation-job-current job))
         (scope (observation-job-scope job))
         (key (list (observed-expression-type record) (observed-expression-values record))))
    (push record (observation-job-records job))
    (setf (gethash (observed-expression-expression record) (observation-job-record-index job)) record)
    (when (eq (observed-expression-status record) :complete)
      (let ((bucket (gethash key (observation-job-bucket-index job))))
        (unless bucket
          (setf bucket (classify-observation-bucket
                        (make-observation-bucket :scope scope :type (first key) :values (second key)))
                (gethash key (observation-job-bucket-index job)) bucket)
          (push bucket (observation-job-buckets job)))
        (push record (observation-bucket-members bucket))
        (when (observation-bucket-informative-p bucket)
          (push (make-message :call-id (observation-scope-id scope) :claim :observed-invariant
                              :evidence record) (observation-job-messages job)))))
    (setf (observation-job-phase job) :enumerate)))

(defun prepare-observation-index (job)
  (let* ((record (observation-job-current job)) (scope (observation-job-scope job))
         (values (nreverse (observation-job-outputs job))))
    (setf (observed-expression-values record) values
          (observed-expression-outcomes record) (nreverse (observation-job-outcomes job))
          (observation-job-outputs job) nil
          (observation-job-outcomes job) nil
          (observation-job-phase job) :index
          (observation-job-debt job)
          (+ 1 (loop for value in values sum (value-work value (observed-expression-type record)))
             (* 2 (length (observation-scope-pairs scope)))
             (length (observation-scope-anchors scope))))))

(defun observation-step (job budget)
  (assert (and (integerp budget) (plusp budget)))
  (let* ((scope (observation-job-scope job))
         (inputs (language-inputs (observation-scope-language scope)))
         (ledger (observation-job-ledger job)))
    (ecase (observation-job-phase job)
      (:setup
       (let ((spent (min budget (observation-job-debt job))))
         (charge ledger :setup spent)
         (decf (observation-job-debt job) spent))
       (when (zerop (observation-job-debt job))
         (setf (observation-job-phase job) :enumerate)))
      (:enumerate
       (charge ledger :enumeration)
       (multiple-value-bind (expression event)
           (if (eq (observation-job-mode job) :enumeration)
               (enumeration-step (observation-job-enumerator job))
               (values (pop (observation-job-queue job)) :candidate))
         (case event
           (:candidate
            (setf (observation-job-current job)
                  (make-observed-expression :scope scope :expression expression)
                  (observation-job-debt job) (syntax-work expression)
                  (observation-job-phase job) :construct))
           (:bound
            (setf (observation-job-completed-bound job)
                  (+ (language-header-size (observation-scope-language scope)
                                           (schema-target (frame-schema (observation-scope-frame scope))))
                     (1- (enumerator-size (observation-job-enumerator job)))))))))
      (:construct
       (let ((spent (min budget (observation-job-debt job))))
         (charge ledger :construction spent)
         (decf (observation-job-debt job) spent))
       (when (zerop (observation-job-debt job))
         (let ((record (observation-job-current job)))
           (setf (observed-expression-type record)
                 (if (observation-job-enumerator job)
                     (index-expression (observation-job-enumerator job) (observed-expression-expression record))
                     (expression-type (observed-expression-expression record) inputs))
                 (observation-job-rows job) (frame-rows (observation-scope-frame scope))
                 (observation-job-phase job)
                 (if (or (eq (observation-job-mode job) :replay)
                         (equal (observed-expression-type record)
                                (schema-target (frame-schema (observation-scope-frame scope)))))
                     :row :enumerate)))))
      (:row
       (charge ledger :scheduling)
       (if (observation-job-rows job)
           (setf (observation-job-evaluation job)
                 (start-evaluation (observed-expression-expression (observation-job-current job))
                                   inputs (row-known (first (observation-job-rows job))))
                 (observation-job-phase job) :evaluate)
           (progn
             (unless (eq :error (observed-expression-status (observation-job-current job)))
               (setf (observed-expression-status (observation-job-current job)) :complete))
             (prepare-observation-index job))))
      (:evaluate
       (let* ((state (observation-job-evaluation job))
              (previous-work (evaluation-work state))
              (record (observation-job-current job)))
         (advance-accounted-evaluation state budget ledger :evaluation :validation)
         (incf (observed-expression-run-work record) (- (evaluation-work state) previous-work))
         (when (and (observation-job-retain-outcomes-p job)
                    (member (evaluation-status state) '(:value :error)))
           (setf (observation-job-phase job) :outcome
                 (observation-job-debt job)
                 (+ 1 (if (eq :value (evaluation-status state))
                          (value-work (evaluation-value state) (observed-expression-type record)) 0))))
         (unless (observation-job-retain-outcomes-p job)
           (case (evaluation-status state)
             (:value
              (push (evaluation-value state) (observation-job-outputs job))
              (pop (observation-job-rows job))
              (setf (observation-job-phase job) :row))
             (:error
              (setf (observed-expression-status record) :error
                    (observed-expression-error record) (evaluation-error state)
                    (observed-expression-failed-key record) (row-key (first (observation-job-rows job))))
              (prepare-observation-index job))))))
      (:outcome
       (let ((spent (min budget (observation-job-debt job))))
         (charge ledger :outcomes spent) (decf (observation-job-debt job) spent))
       (when (zerop (observation-job-debt job))
         (let ((state (observation-job-evaluation job)) (record (observation-job-current job)))
           (push (make-observation-outcome :status (evaluation-status state)
                                           :value (evaluation-value state) :error (evaluation-error state)
                                           :work (evaluation-work state))
                 (observation-job-outcomes job))
           (if (eq :value (evaluation-status state))
               (push (evaluation-value state) (observation-job-outputs job))
               (unless (eq :error (observed-expression-status record))
                 (setf (observed-expression-status record) :error
                       (observed-expression-error record) (evaluation-error state)
                       (observed-expression-failed-key record) (row-key (first (observation-job-rows job))))))
           (pop (observation-job-rows job))
           (setf (observation-job-phase job) :row))))
      (:index
       (let ((spent (min budget (observation-job-debt job))))
         (charge ledger :indexing spent)
         (decf (observation-job-debt job) spent))
       (when (zerop (observation-job-debt job)) (finish-observation job))))))

(defun observation-bound-complete-p (job bound)
  (if (eq (observation-job-mode job) :enumeration)
      (>= (observation-job-completed-bound job) bound)
      (and (eq (observation-job-phase job) :enumerate)
           (or (null (observation-job-queue job))
               (> (description-size (first (observation-job-queue job))
                                    (language-inputs (observation-scope-language (observation-job-scope job)))) bound)))))

(defun resume-observation-search (job description-limit work-limit &key quantum)
  (assert (and (integerp description-limit)
               (>= description-limit (observation-job-requested-bound job))
               (integerp work-limit) (>= work-limit 0)))
  (assert (or (null quantum) (and (integerp quantum) (plusp quantum))))
  (setf (observation-job-requested-bound job) description-limit)
  (loop until (or (observation-bound-complete-p job description-limit)
                  (>= (ledger-total (observation-job-ledger job)) work-limit))
        do (let ((remaining (- work-limit (ledger-total (observation-job-ledger job)))))
             (observation-step job (if quantum (min quantum remaining) remaining))))
  (let* ((complete (observation-bound-complete-p job description-limit))
         (enumerated (eq (observation-job-mode job) :enumeration))
         (scope (observation-job-scope job)))
    (when (and complete (not enumerated))
      (setf (observation-job-completed-bound job) description-limit))
    (let ((message (make-message
                    :call-id (observation-scope-id scope)
                    :claim (cond ((not complete) :cutoff) (enumerated :bounded-exhaustion) (t :replay-complete))
                    :evidence (list :scope scope :description-limit description-limit
                                    :completed-bound (observation-job-completed-bound job)
                                    :work (ledger-total (observation-job-ledger job))
                                    :phase (observation-job-phase job)
                                    :encoding-version +encoding-version+ :tariff-version +tariff-version+
                                    :syntax-coverage (if enumerated :grammar :listed-expressions)))))
      (push message (observation-job-messages job))
      message)))

;;; Multi-Lane Agenda / Propagation Search

(defstruct agenda-lane
  name
  job
  weight
  verify-against)

(defstruct (propagation-search (:constructor %make-propagation-search))
  primary fallback original language (ledger (make-ledger)) (results nil) best first-work
  verification pending pending-origin (debt 0) (turn 0) (remaining 0) lane
  (requested-bound 0) (quantum 256))

(defun start-propagation-search (propagation language &key (quantum 256))
  "Keep the original search whenever tentative targets restrict the child frame."
  (assert (and (integerp quantum) (plusp quantum)))
  (%make-propagation-search
   :primary (start-search (propagation-frame propagation) language)
   :fallback (when (propagation-fallback propagation) (start-search (propagation-fallback propagation) language))
   :original (propagation-original propagation) :language language :quantum quantum))

(defun propagation-search-finished-p (state bound)
  (and (null (propagation-search-pending state)) (null (propagation-search-verification state))
       (search-bound-complete-p (propagation-search-primary state) bound)
       (or (null (propagation-search-fallback state))
           (search-bound-complete-p (propagation-search-fallback state) bound))))

(defun queue-propagation-candidate (state candidate origin)
  (assert (null (propagation-search-pending state)))
  (setf (propagation-search-pending state) candidate (propagation-search-pending-origin state) origin
        (propagation-search-debt state)
        (* (1+ (length (propagation-search-results state))) (syntax-work (candidate-expression candidate)))))

(defun finish-propagation-candidate (state)
  (let ((candidate (propagation-search-pending state)))
    (if (and (eq :primary (propagation-search-pending-origin state)) (propagation-search-fallback state))
        ;; Recheck the complete child program against the original forward predicates.
        (setf (propagation-search-verification state)
              (start-search (propagation-search-original state) (propagation-search-language state)
                            :expressions (list (candidate-expression candidate))))
        (unless (find (candidate-expression candidate) (propagation-search-results state)
                      :key #'candidate-expression :test #'equal)
          (setf candidate (copy-candidate candidate)
                (candidate-discovery-work candidate) (ledger-total (propagation-search-ledger state)))
          (push candidate (propagation-search-results state))
          (unless (propagation-search-first-work state)
            (setf (propagation-search-first-work state) (ledger-total (propagation-search-ledger state))))
          (when (or (null (propagation-search-best state))
                    (< (candidate-size candidate) (candidate-size (propagation-search-best state))))
            (setf (propagation-search-best state) candidate))))
    (setf (propagation-search-pending state) nil)))

(defun select-propagation-lane (state bound)
  (let* ((fallback (propagation-search-fallback state))
         (fallback-active (and fallback (not (search-bound-complete-p fallback bound))))
         (preferred (cond ((propagation-search-verification state) :verification)
                          ((not (search-bound-complete-p (propagation-search-primary state) bound)) :primary)))
         (reserved (= 3 (mod (propagation-search-turn state) 4))))
    (incf (propagation-search-turn state))
    (setf (propagation-search-lane state)
          (cond ((and fallback-active (or reserved (null preferred))) :fallback) (preferred preferred))
          (propagation-search-remaining state) (propagation-search-quantum state))))

(defun resume-propagation-search (state description-limit work-limit &key stop-on-first)
  "Absolute cumulative budget. Reserve every fourth work quantum for the original
search; successful tentative branches never remove it."
  (assert (and (integerp description-limit) (>= description-limit (propagation-search-requested-bound state))
               (integerp work-limit) (>= work-limit 0)))
  (setf (propagation-search-requested-bound state) description-limit)
  (let ((ledger (propagation-search-ledger state)))
    (loop while (and (< (ledger-total ledger) work-limit)
                     (not (propagation-search-finished-p state description-limit))
                     (not (and stop-on-first (propagation-search-best state)))) do
      (cond
        ((propagation-search-pending state)
         (let ((spent (min (propagation-search-debt state) (- work-limit (ledger-total ledger)))))
           (charge ledger :propagation-results spent) (decf (propagation-search-debt state) spent))
         (when (zerop (propagation-search-debt state)) (finish-propagation-candidate state)))
        ((or (null (propagation-search-lane state)) (zerop (propagation-search-remaining state)))
         (charge ledger :propagation-scheduling)
         (select-propagation-lane state description-limit))
        (t
         (let* ((lane (propagation-search-lane state))
                (job (ecase lane (:primary (propagation-search-primary state))
                                 (:fallback (propagation-search-fallback state))
                                 (:verification (propagation-search-verification state)))))
           (if (or (null job) (search-bound-complete-p job description-limit))
               (progn
                 (when (eq lane :verification) (setf (propagation-search-verification state) nil))
                 (setf (propagation-search-lane state) nil))
               (let ((before (ledger-total (search-job-ledger job))) (results (search-job-results job)))
                 (search-step job (min (propagation-search-remaining state) (- work-limit (ledger-total ledger))))
                 (let ((spent (- (ledger-total (search-job-ledger job)) before)))
                   (charge ledger (ecase lane (:primary :preferred-search) (:fallback :fallback-search)
                                             (:verification :forward-replay)) spent)
                   (decf (propagation-search-remaining state) spent))
                 (unless (eq results (search-job-results job))
                   (queue-propagation-candidate state (first (search-job-results job)) lane)
                   (setf (propagation-search-lane state) nil)
                   (when (eq lane :verification) (setf (propagation-search-verification state) nil)))))))))
    (make-message :call-id (search-job-call-id (propagation-search-primary state))
                  :claim (cond ((and stop-on-first (propagation-search-best state)) :candidate)
                               ((propagation-search-finished-p state description-limit) :bounded-exhaustion)
                               (t :cutoff))
                  :evidence (list :description-limit description-limit :work (ledger-total ledger)
                                  :first-verified-work (propagation-search-first-work state)))))

(defun start-agenda (propagation language &key (quantum 256))
  (start-propagation-search propagation language :quantum quantum))

(defun resume-agenda (state description-limit work-limit &key stop-on-first)
  (resume-propagation-search state description-limit work-limit :stop-on-first stop-on-first))
