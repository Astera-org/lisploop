(in-package #:lisploop)

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
Listed proposals use the SAME construction, VM, checker and objective. Their
completion covers only that list; it makes no grammar-exhaustion claim."
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
  ;; Only a successful prediction rejected by its requirement is reusable.
  ;; Errors are not equality evidence. The cache belongs to this exact frame/job.
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
  "Advance one search phase using at most BUDGET tariff units.
Construction debt and VM instructions are paid in batches; single-unit stepping
remains available for diagnostics. Any unpaid work stays in the continuation."
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
  "Absolute cumulative work limit and total packet-bit bound. Return a scoped
cutoff or completed bounded exhaustion; neither claims the goal is impossible.
All successful programs remain available, including after an incumbent is found.
Batch up to the remaining budget within each phase. Optional QUANTUM caps the
batch size; QUANTUM=1 reproduces single-unit stepping without changing the tariff."
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
