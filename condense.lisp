(in-package #:lisploop)

;;; Stage A: resumable heuristic search and condensation to a priced heuristic model.

;;; Operation 4: Heuristic Condensation (condense-heuristic)
(defstruct (heuristic-model (:conc-name heuristic-))
  program residual (unresolved-keys nil) (exact-p nil :type boolean) (total-p t :type boolean)
  (exhausted-p nil :type boolean) (program-bits 0 :type fixnum) (residual-bits 0 :type fixnum)
  (run-work 0 :type fixnum) (work-used 0 :type fixnum) (score 0)
  (metric-decoder nil) (alternatives nil) (buckets nil))

(defun heuristic-model< (a b)
  "Order models by score, then by program bits."
  (lex< a b #'heuristic-score #'heuristic-program-bits))

(defun condense-heuristic (frame language &key description-limit (work-limit 100000)
                                               grace-work-limit (run-weight 0)
                                               stop-on-exact-p (metric nil metric-p)
                                               (library *knowledge-library*) ledger)
  "Budgeted selector approximation on ORIGINAL requirements; residuals are training costs."
  (let* ((job (apply #'start-heuristic-search frame language
                     :description-limit description-limit :run-weight run-weight
                     :stop-on-exact-p stop-on-exact-p :library library
                     (when metric-p (list :metric metric))))
         (message (resume-heuristic-search job (remaining-work ledger work-limit)))
         (best (heuristic-search-best job)))
    (when (and (null best) grace-work-limit (> grace-work-limit work-limit))
      (let ((extra-limit (remaining-work ledger grace-work-limit)))
        (when (> extra-limit (ledger-total (heuristic-search-ledger job)))
          (setf message (resume-heuristic-search job extra-limit :stop-on-first-model-p t)
                best (heuristic-search-best job)))))
    (charge ledger :heuristic-search (ledger-total (heuristic-search-ledger job)))
    (when (and best (heuristic-search-models job))
      (setf (heuristic-alternatives best)
            (remove best (stable-sort (reverse (heuristic-search-models job)) #'heuristic-model<))))
    (values best message)))

;;; The resumable search job behind condense-heuristic.
(defstruct (heuristic-search (:constructor %make-heuristic-search))
  observation bound (ledger (make-ledger)) (phase :prepare) (debt 0) record rows outcomes
  (resolved-rows 0) evaluation (index 0) residual (unresolved nil) (residual-bits 0) best (models nil)
  (run-weight 0) (stop-on-exact-p nil) (library *knowledge-library*)
  (pending-witness nil) (pending-linkage nil) (metric-decoders nil))

(defun frame-has-empty-sequence-row-p (frame)
  "True when FRAME has a sequence input Xi whose value is empty ('()) on some constrained row."
  (loop for (nil . type) in (schema-inputs (frame-schema frame)) for pos from 0
        thereis (and (seq-type-p type)
                     (some (lambda (row) (and (constrained-row-p row) (null (nth pos (row-known row)))))
                           (frame-rows frame)))))

(defun stage-a-observation-language (frame language)
  "When FRAME has an empty-sequence row, exclude partial destructors, control ops, and oracle functions."
  (if (not (frame-has-empty-sequence-row-p frame))
      language
      (let* ((target (schema-target (frame-schema frame)))
             (ops (remove-if (lambda (o)
                               (and (operator-p o)
                                    (or (member (operator-name o) '(:at :tail :if :=))
                                        (let ((d (find-function-definition (operator-name o))))
                                          (and d (function-definition-oracle-table d))))))
                             (language-operators language)))
             (lits (if (and (eq :int target) (listp (language-literals language)))
                       (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                       (language-literals language))))
        (derive-language language :operators ops :literals lits))))

(defun start-heuristic-search (frame language &key description-limit (run-weight 0) stop-on-exact-p
                                                   (metric nil metric-p) (library *knowledge-library*))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (let* ((ef (if metric-p (derive-frame frame :metric metric) frame))
         (elib (or library *knowledge-library*)))
    (%make-heuristic-search
     :observation (start-observation-search
                   (make-observation-scope ef (stage-a-observation-language ef language)
                                           :respect-availability-p t :library elib)
                   :retain-outcomes t)
     :debt (+ 1 (length (frame-pairs ef)) (length (frame-anchors ef))
              (loop for row in (frame-rows ef) sum (syntax-work (row-requirement row))))
     :bound (or description-limit (header-bound (schema-inputs (frame-schema ef)) (schema-target (frame-schema ef)) 18))
     :run-weight run-weight :stop-on-exact-p stop-on-exact-p :library elib)))

(defun record-witness-cost (job bits metric-info)
  (when (and (consp metric-info) (eq :metric-decoder (first metric-info)))
    (push (second metric-info) (heuristic-search-metric-decoders job)))
  (incf (heuristic-search-residual-bits job)
        (+ (positive-bit-size (1+ (heuristic-search-index job))) bits)))

(defun price-row-witness (job values type &optional outcome frame ledger)
  "Add residual cost of correcting the current row to VALUES, returning the closest witness."
  (multiple-value-bind (witness bits packet metric-info)
      (select-closest-witness (and outcome (observation-outcome-value outcome)) values type
                              (and outcome (eq :value (observation-outcome-status outcome)))
                              (when frame (frame-metric frame)) (heuristic-search-library job) ledger)
    (declare (ignore packet))
    (record-witness-cost job bits metric-info)
    witness))

(defun note-unresolved-row (job row type)
  (when (constrained-row-p row)
    (push (row-key row) (heuristic-search-unresolved job))
    (let ((values (extract-allowed-values (row-requirement row))))
      (when (consp values) (price-row-witness job values type)))))

(defun dominant-metric-decoder (decoders)
  (when decoders
    (let ((ordered (reverse decoders)) best-id (best-count 0))
      (dolist (id ordered best-id)
        (let ((cnt (count id ordered :test #'eq)))
          (when (> cnt best-count) (setf best-id id best-count cnt)))))))

(defun record-heuristic-model (job frame type)
  "Convert the fully visited candidate in JOB into a priced `heuristic-model` and keep the best."
  (let* ((record (heuristic-search-record job))
         (program (observed-expression-expression record))
         (bits (description-size program (schema-inputs (frame-schema frame))))
         (row-res (nreverse (heuristic-search-residual job)))
         (pre (prog1 (heuristic-search-pending-linkage job) (setf (heuristic-search-pending-linkage job) nil))))
    (multiple-value-bind (rel-entries rel-bits pb ab rel-dec)
        (if pre (values-list pre)
            (relational-linkage-residual frame (observed-expression-outcomes record)
                                         :row-residuals row-res :type type
                                         :metric (frame-metric frame) :library (heuristic-search-library job)))
      (declare (ignore pb ab))
      (when rel-dec (push rel-dec (heuristic-search-metric-decoders job)))
      (let* ((residual (append row-res rel-entries))
             (rbits (+ (heuristic-search-residual-bits job) rel-bits
                       (if residual (positive-bit-size (1+ (length residual))) 0)))
             (rwork (observed-expression-run-work record))
             (model (make-heuristic-model
                     :program program :residual residual
                     :unresolved-keys (nreverse (copy-list (heuristic-search-unresolved job)))
                     :exact-p (null residual)
                     :total-p (not (null (member (observed-expression-status record) '(:complete :unresolved))))
                     :program-bits bits :residual-bits rbits :run-work rwork
                     :metric-decoder (dominant-metric-decoder (heuristic-search-metric-decoders job))
                     :score (+ bits rbits (* (heuristic-search-run-weight job) rwork))))
             (old (heuristic-search-best job)))
        (push model (heuristic-search-models job))
        (when (or (null old) (heuristic-model< model old)) (setf (heuristic-search-best job) model))))))

(defun settle-heuristic-row (job row satisfied-p &optional frame type outcome)
  (when (constrained-row-p row) (incf (heuristic-search-resolved-rows job)))
  (if satisfied-p
      (setf (heuristic-search-pending-witness job) nil (heuristic-search-phase job) :next)
      (let ((priv (make-ledger)) pending)
        (when (and frame (constrained-row-p row))
          (let ((vals (extract-allowed-values (row-requirement row))))
            (when (consp vals)
              (multiple-value-bind (w bits packet info)
                  (select-closest-witness (and outcome (observation-outcome-value outcome)) vals type
                                          (and outcome (eq :value (observation-outcome-status outcome)))
                                          (frame-metric frame) (heuristic-search-library job) priv)
                (declare (ignore packet))
                (setf pending (list w bits info))))))
        (setf (heuristic-search-pending-witness job) pending
              (heuristic-search-phase job) :residual
              (heuristic-search-debt job) (+ (syntax-work (row-requirement row)) (ledger-total priv))))))

(defun heuristic-search-step (job)
  (let* ((obs (heuristic-search-observation job))
         (frame (observation-scope-frame (observation-job-scope obs)))
         (type (schema-target (frame-schema frame)))
         (ledger (heuristic-search-ledger job))
         (row (first (heuristic-search-rows job)))
         (outcome (first (heuristic-search-outcomes job))))
    (case (heuristic-search-phase job)
      (:prepare
       (assert (plusp (heuristic-search-debt job)) () "A heuristic search starts with preparation to pay")
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-preparation)
       (when (zerop (heuristic-search-debt job)) (setf (heuristic-search-phase job) :observe)))
      (:observe
       (let ((before (ledger-total (observation-job-ledger obs))) (recs (observation-job-records obs)))
         (observation-step obs 1)
         (charge ledger :observation (- (ledger-total (observation-job-ledger obs)) before))
         (unless (eq recs (observation-job-records obs))
           (setf (heuristic-search-record job) (first (observation-job-records obs))
                 (heuristic-search-rows job) (frame-rows frame)
                 (heuristic-search-outcomes job) (observed-expression-outcomes (heuristic-search-record job))
                 (heuristic-search-resolved-rows job) 0 (heuristic-search-index job) 0
                 (heuristic-search-residual job) nil (heuristic-search-unresolved job) nil
                 (heuristic-search-residual-bits job) 0 (heuristic-search-pending-witness job) nil
                 (heuristic-search-pending-linkage job) nil (heuristic-search-metric-decoders job) nil
                 (heuristic-search-phase job) :row))))
      (:row
       (charge ledger :heuristic-checking)
       (cond ((null row)
              (if (>= (heuristic-search-resolved-rows job) (frame-min-resolved-rows frame))
                  (let ((priv (make-ledger)) pending)
                    (when (or (frame-pairs frame) (frame-anchors frame))
                      (setf pending (multiple-value-list
                                     (relational-linkage-residual
                                      frame (observed-expression-outcomes (heuristic-search-record job))
                                      :row-residuals (reverse (heuristic-search-residual job))
                                      :type type :metric (frame-metric frame)
                                      :library (heuristic-search-library job) :ledger priv))))
                    (setf (heuristic-search-pending-linkage job) pending
                          (heuristic-search-phase job) :score
                          (heuristic-search-debt job)
                          (+ (syntax-work (observed-expression-expression (heuristic-search-record job)))
                             (length (frame-pairs frame)) (length (frame-anchors frame)) (ledger-total priv))))
                  (setf (heuristic-search-phase job) :observe)))
             ((eq :value (observation-outcome-status outcome))
              (setf (heuristic-search-evaluation job)
                    (start-evaluation (row-requirement row) (list (cons 0 type)) (list (observation-outcome-value outcome)))
                    (heuristic-search-phase job) :check))
             ((eq :unresolved (observation-outcome-status outcome))
              (note-unresolved-row job row type) (setf (heuristic-search-phase job) :next))
             (t (settle-heuristic-row job row nil frame type outcome))))
      (:check
       (let ((run (advance-accounted-evaluation (heuristic-search-evaluation job) 1 ledger
                                                :heuristic-checking :heuristic-checking)))
         (case (evaluation-status run)
           (:unknown)
           (:unresolved (note-unresolved-row job row type) (setf (heuristic-search-phase job) :next))
           (t (settle-heuristic-row job row (and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))
                                    frame type outcome)))))
      (:residual
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-residual)
       (when (zerop (heuristic-search-debt job))
         (let ((pending (prog1 (heuristic-search-pending-witness job) (setf (heuristic-search-pending-witness job) nil))))
           (setf (heuristic-search-phase job)
                 (cond ((not (constrained-row-p row)) :next)
                       (pending (destructuring-bind (w bits minfo) pending
                                  (record-witness-cost job bits minfo)
                                  (push (cons (row-key row) w) (heuristic-search-residual job)))
                                :next)
                       (t :observe))))))
      (:next
       (charge ledger :heuristic-checking)
       (pop (heuristic-search-rows job)) (pop (heuristic-search-outcomes job))
       (incf (heuristic-search-index job)) (setf (heuristic-search-phase job) :row))
      (:score
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-ranking)
       (when (zerop (heuristic-search-debt job))
         (record-heuristic-model job frame type)
         (setf (heuristic-search-phase job) :observe))))))

(defun heuristic-search-complete-p (job)
  (and (eq :observe (heuristic-search-phase job))
       (or (observation-bound-complete-p (heuristic-search-observation job) (heuristic-search-bound job))
           (and (heuristic-search-stop-on-exact-p job) (zerop (heuristic-search-run-weight job))
                (let ((best (heuristic-search-best job)))
                  (and best (heuristic-exact-p best) (heuristic-total-p best)
                       (null (heuristic-unresolved-keys best))))))))

(defun observation-feature-buckets (observation)
  "Return `(expression . values)` pairs for each distinct complete observation bucket."
  (loop for b in (reverse (observation-job-buckets observation))
        for rec = (car (last (observation-bucket-members b)))
        when rec collect (cons (observed-expression-expression rec) (observation-bucket-values b))))

(defun resume-heuristic-search (job work-limit &key stop-on-first-model-p)
  "Absolute cumulative budget covers observation, checking, residuals, and ranking."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (heuristic-search-ledger job)) work-limit)
                   (not (heuristic-search-complete-p job))
                   (not (and stop-on-first-model-p (heuristic-search-best job))))
        do (heuristic-search-step job))
  (let ((best (heuristic-search-best job))
        (complete-p (heuristic-search-complete-p job))
        (work (ledger-total (heuristic-search-ledger job))))
    (when best
      (setf (heuristic-buckets best) (observation-feature-buckets (heuristic-search-observation job))
            (heuristic-work-used best) work (heuristic-exhausted-p best) (not (null complete-p))))
    (make-message :claim (if complete-p :bounded-exhaustion :cutoff)
                  :evidence (list :description-limit (heuristic-search-bound job)
                                  :work work :phase (heuristic-search-phase job) :best best))))
