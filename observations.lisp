(in-package #:lisploop)

(defun propose-observed-laws (job &key (guard (lit :bool t)) ledger)
  "Propose a spanning set of equalities per complete output bucket, not certificates.
GUARD is supplied prior knowledge; the discovery step does not infer predicates."
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

;;; Empirical observations are indexes over frames, not another kind of frame or
;;; an equivalence relation licensed for substitution into arbitrary programs.
(defstruct (observation-scope (:constructor %make-observation-scope))
  id frame language pairs anchors
  (equality :typed-value) (evidence :replayed-observations) (simulator-version +simulator-version+)
  (encoding-version +encoding-version+) (tariff-version +tariff-version+))

(defun make-observation-scope (frame language &key (id (incf *next-call-id*)) pairs anchors)
  "Freeze the observed inputs and language. PAIRS and ANCHORS refer to row keys;
they stay outside predictor arguments. Allowed sets are not used by this index."
  (assert (frame-rows frame) () "An empirical scope needs observations")
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (or (null anchors) (and pairs (>= (length anchors) 2))))
  (assert (= (length anchors) (length (remove-duplicates anchors :test #'equal))))
  (let* ((schema (copy-schema (frame-schema frame)))
         (rows (mapcar (lambda (row)
                         (make-row :key (copy-tree (row-key row))
                                   :known (copy-tree (row-known row)) :allowed (row-allowed row)))
                       (frame-rows frame)))
         (snapshot (copy-language language)))
    (setf (schema-inputs schema) (copy-tree (schema-inputs schema))
          (schema-target schema) (copy-tree (schema-target schema))
          (language-domain snapshot) (copy-tree (language-domain language))
          (language-inputs snapshot) (copy-tree (language-inputs language))
          (language-literals snapshot) (copy-tree (language-literals language))
          (language-operators snapshot) (copy-tree (language-operators language)))
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

(defun transition-probes (frame output-type &optional ledger)
  "Reorient recorded singleton state transitions into before/after input probes.
The original frame remains available; this conversion executes no transition."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (requirement (predicate-allowed output-type (lit :bool t)))
         (rows nil) (pairs nil))
    (assert (equal (schema-target schema) (apply #'tuple-type (mapcar #'cdr inputs))))
    (dolist (row (frame-rows frame))
      (let ((targets (allowed-values (row-allowed row)))
            (before-key (list (row-key row) :before))
            (after-key (list (row-key row) :after)))
        (assert (and (listp targets) (= (length targets) 1)) ()
                "Transition probes require a recorded singleton successor")
        (push (make-row :key before-key :known (copy-tree (row-known row))
                        :allowed requirement) rows)
        (push (make-row :key after-key :known (copy-tree (first targets))
                        :allowed requirement) rows)
        (push (list before-key after-key) pairs)
        (charge ledger :orientation
                (+ 2 (loop for spec in inputs for before in (row-known row)
                           for after in (first targets)
                           sum (+ (value-work before (cdr spec)) (value-work after (cdr spec))))))))
    (values (make-frame (make-schema :inputs (copy-tree inputs) :target output-type)
                        (nreverse rows))
            (nreverse pairs))))

(defstruct observed-expression scope expression type (status :unknown)
  values (run-work 0) error failed-key)
(defstruct observation-bucket scope type values members invariant-p informative-p counterexample)

(defun observed-agreement-p (left right)
  "Agreement only between total evaluations in the exact same observation scope.
Errors and unknown computations never supply empirical equality evidence."
  (and left right
       (eq (observed-expression-scope left) (observed-expression-scope right))
       (eq (observed-expression-status left) :complete)
       (eq (observed-expression-status right) :complete)
       (equal (observed-expression-type left) (observed-expression-type right))
       (equal (observed-expression-values left) (observed-expression-values right))))

(defstruct (observation-job (:constructor %make-observation-job))
  scope enumerator (mode :enumeration) queue (ledger (make-ledger))
  (phase :enumerate) current rows evaluation (outputs nil) (debt 0)
  (completed-bound 0) (requested-bound 0) records buckets messages
  (record-index (make-hash-table :test #'equal))
  (bucket-index (make-hash-table :test #'equal)))

(defun start-observation-search (scope &key (expressions nil supplied-p))
  "Enumerate syntax, or replay an explicit list of expressions on a NEW scope.
Replay covers only that list, never claims grammar exhaustion or transfers a law."
  (let* ((language (observation-scope-language scope))
         (queue (when supplied-p (remove-duplicates (copy-tree expressions) :test #'equal)))
         (job (%make-observation-job :scope scope
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
  "Return informative invariant buckets; all constant buckets are still retained."
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
  "Pay for output storage, hashing, pair comparisons, and the anchor variation test."
  (let* ((record (observation-job-current job)) (scope (observation-job-scope job))
         (values (nreverse (observation-job-outputs job))))
    (setf (observed-expression-values record) values
          (observation-job-outputs job) nil
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
             (setf (observed-expression-status (observation-job-current job)) :complete)
             (prepare-observation-index job))))
      (:evaluate
       (let* ((state (observation-job-evaluation job))
              (before (ledger-total ledger)) (previous-work (evaluation-work state))
              (record (observation-job-current job)))
         (multiple-value-bind (result unpaid-error-p) (advance-evaluation state budget ledger :evaluation)
           (declare (ignore result))
           (when (or unpaid-error-p (= before (ledger-total ledger))) (charge ledger :validation)))
         (incf (observed-expression-run-work record) (- (evaluation-work state) previous-work))
         (case (evaluation-status state)
           (:value
            (push (evaluation-value state) (observation-job-outputs job))
            (pop (observation-job-rows job))
            (setf (observation-job-phase job) :row))
           (:error
            (setf (observed-expression-status record) :error
                  (observed-expression-error record) (evaluation-error state)
                  (observed-expression-failed-key record) (row-key (first (observation-job-rows job))))
            (prepare-observation-index job)))))
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
  "Resume empirical observation work under growing description limits and cumulative work
ceilings. Replay completion explicitly covers only the supplied expression list."
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
