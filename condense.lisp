(in-package #:lisploop)

;;; Stage A: resumable heuristic search and condensation to a priced heuristic model.

;;; Operation 4: Heuristic Condensation (condense-heuristic)
(defstruct (heuristic-model (:conc-name heuristic-))
  program
  residual
  (unresolved-keys nil)
  (exact-p nil :type boolean)
  (total-p t :type boolean)
  (program-bits 0 :type fixnum)
  (residual-bits 0 :type fixnum)
  (run-work 0 :type fixnum)
  (score 0)
  (alternatives nil)
  (buckets nil))

(defun heuristic-model< (a b)
  "Order models by score, then by program bits."
  (lex< a b #'heuristic-score #'heuristic-program-bits))

(defun condense-heuristic (frame language &key description-limit (work-limit 100000) (run-weight 0) stop-on-exact-p ledger)
  "Budgeted selector approximation on ORIGINAL requirements; residuals are training costs.
Return the best completed model and an informative completion/cutoff message."
  (let* ((job (start-heuristic-search frame language :description-limit description-limit
                                     :run-weight run-weight
                                     :stop-on-exact-p stop-on-exact-p))
         (message (resume-heuristic-search job (remaining-work ledger work-limit)))
         (best (heuristic-search-best job)))
    (charge ledger :heuristic-search (ledger-total (heuristic-search-ledger job)))
    (when (and best (heuristic-search-models job))
      (setf (heuristic-alternatives best)
            (remove best (stable-sort (reverse (heuristic-search-models job)) #'heuristic-model<))))
    (values best message)))

;;; The resumable search job behind condense-heuristic.
(defstruct (heuristic-search (:constructor %make-heuristic-search))
  observation bound (ledger (make-ledger)) (phase :prepare) (debt 0) record rows outcomes
  (resolved-rows 0) evaluation (index 0) residual (unresolved nil) (residual-bits 0) best (models nil) (run-weight 0)
  (stop-on-exact-p nil)
  decoders ; the library's metric decoders for the target type, frozen when the search starts
  staged)  ; a result computed ahead of its payment: a row's (witness bits), or a model

(defun frame-has-empty-sequence-row-p (frame)
  "True when FRAME has a sequence input Xi whose value is empty ('()) on some constrained row."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (loop for (nil . type) in inputs
          for pos from 0
          thereis (and (seq-type-p type)
                       (some (lambda (row)
                               (and (constrained-row-p row)
                                    (null (nth pos (row-known row)))))
                             (frame-rows frame))))))

(defun stage-a-observation-language (frame language)
  "When FRAME has an empty-sequence row, exclude partial sequence destructors, control operators,
and unverified oracle functions from Stage A unconditional observation."
  (if (not (frame-has-empty-sequence-row-p frame))
      language
      (let* ((target (schema-target (frame-schema frame)))
             (ops (remove-if (lambda (o)
                               (and (operator-p o)
                                    (or (member (operator-name o) '(:at :tail :if :=))
                                        (let ((def (find-function-definition (operator-name o))))
                                          (and def (function-definition-oracle-table def))))))
                             (language-operators language)))
             (lits (if (and (eq :int target) (listp (language-literals language)))
                       (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                       (language-literals language))))
        (derive-language language :operators ops :literals lits))))

(defun start-heuristic-search (frame language &key description-limit (run-weight 0) stop-on-exact-p)
  (assert (and (realp run-weight) (>= run-weight 0)))
  (assert-inputs-available frame)
  (let ((obs-language (stage-a-observation-language frame language)))
    (%make-heuristic-search
     :observation (start-observation-search (make-observation-scope frame obs-language) :retain-outcomes t)
     :debt (+ 1 (length (frame-pairs frame)) (length (frame-anchors frame))
              (loop for row in (frame-rows frame) sum (syntax-work (row-requirement row))))
     :bound (or description-limit (header-bound (schema-inputs (frame-schema frame))
                                                (schema-target (frame-schema frame)) 18))
     :decoders (metric-decoders (schema-target (frame-schema frame)))
     :run-weight run-weight
     :stop-on-exact-p stop-on-exact-p)))

(defun closest-row-witness (job frame values type &optional outcome ledger)
  "The witness among VALUES closest to OUTCOME, the candidate's observed outcome on the
current row if it has one, and its correction bits, as two values. The frame's metric and
the library's metric decoders run in the VM and are charged to LEDGER."
  (select-closest-witness (and outcome (observation-outcome-value outcome)) values type
                          (and outcome (eq :value (observation-outcome-status outcome)))
                          :metric (frame-metric frame)
                          :decoders (heuristic-search-decoders job)
                          :ledger ledger))

(defun charge-row-witness (job bits)
  "Add to JOB's residual bits the cost of naming the current row and of a correction of BITS."
  (incf (heuristic-search-residual-bits job)
        (+ (positive-bit-size (1+ (heuristic-search-index job))) bits)))

(defun note-unresolved-row (job frame row type)
  "Record that the candidate leaves ROW unresolved, pricing a witness for it when one is listed."
  (when (constrained-row-p row)
    (push (row-key row) (heuristic-search-unresolved job))
    (let ((values (extract-allowed-values (row-requirement row))))
      (when (consp values)
        (charge-row-witness job (nth-value 1 (closest-row-witness job frame values type)))))))

(defun price-heuristic-model (job frame type ledger)
  "The priced model of the candidate whose rows have all been visited. The metric programs
that price its relational residual are charged to LEDGER."
  (let* ((record (heuristic-search-record job))
         (program (observed-expression-expression record))
         (bits (description-size program (schema-inputs (frame-schema frame))))
         (row-residual (nreverse (heuristic-search-residual job))))
    (multiple-value-bind (rel-entries rel-bits)
        (relational-linkage-residual frame (observed-expression-outcomes record)
                                     :row-residuals row-residual :type type
                                     :decoders (heuristic-search-decoders job) :ledger ledger)
      (let* ((residual (append row-residual rel-entries))
             ;; Residual length is encoded, too; exact synthesis needs no correction packet.
             (residual-bits (+ (heuristic-search-residual-bits job)
                               rel-bits
                               (if residual (positive-bit-size (1+ (length residual))) 0)))
             (run-work (observed-expression-run-work record)))
        (make-heuristic-model
         :program program :residual residual
         :unresolved-keys (nreverse (copy-list (heuristic-search-unresolved job)))
         :exact-p (null residual)
         :total-p (not (null (member (observed-expression-status record)
                                     '(:complete :unresolved))))
         :program-bits bits :residual-bits residual-bits :run-work run-work
         :score (+ bits residual-bits (* (heuristic-search-run-weight job) run-work)))))))

(defun record-heuristic-model (job model)
  "Keep MODEL among the job's models, and as its best when it is."
  (let ((old (heuristic-search-best job)))
    (push model (heuristic-search-models job))
    (when (or (null old) (heuristic-model< model old))
      (setf (heuristic-search-best job) model))))

(defun settle-heuristic-row (job row satisfied-p)
  "Count ROW, whose check gave a definite verdict, as resolved; a failing row needs a witness."
  (when (constrained-row-p row) (incf (heuristic-search-resolved-rows job)))
  (if satisfied-p
      (setf (heuristic-search-phase job) :next)
      (setf (heuristic-search-phase job) :residual
            (heuristic-search-debt job) (syntax-work (row-requirement row)))))

(defun heuristic-search-step (job)
  (let* ((observation (heuristic-search-observation job))
         (frame (observation-scope-frame (observation-job-scope observation)))
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
       (let ((before (ledger-total (observation-job-ledger observation)))
             (records (observation-job-records observation)))
         (observation-step observation 1)
         (charge ledger :observation (- (ledger-total (observation-job-ledger observation)) before))
         (unless (eq records (observation-job-records observation))
           (setf (heuristic-search-record job) (first (observation-job-records observation))
                 (heuristic-search-rows job) (frame-rows frame)
                 (heuristic-search-outcomes job) (observed-expression-outcomes (heuristic-search-record job))
                 (heuristic-search-resolved-rows job) 0
                 (heuristic-search-index job) 0 (heuristic-search-residual job) nil
                 (heuristic-search-unresolved job) nil
                 (heuristic-search-residual-bits job) 0 (heuristic-search-phase job) :row))))
      (:row
       (charge ledger :heuristic-checking)
       (cond ((null row)
              (if (>= (heuristic-search-resolved-rows job) (frame-min-resolved-rows frame))
                  ;; The model is priced now and published once its ranking is paid for.
                  (let ((private (make-ledger)))
                    (setf (heuristic-search-staged job) (price-heuristic-model job frame type private)
                          (heuristic-search-phase job) :score
                          (heuristic-search-debt job)
                          (+ (syntax-work (observed-expression-expression (heuristic-search-record job)))
                             (length (frame-pairs frame))
                             (length (frame-anchors frame))
                             (ledger-total private))))
                  (setf (heuristic-search-phase job) :observe)))
             ((eq :value (observation-outcome-status outcome))
              (setf (heuristic-search-evaluation job)
                    (start-evaluation (row-requirement row) (list (cons 0 type))
                                      (list (observation-outcome-value outcome)))
                    (heuristic-search-phase job) :check))
             ((eq :unresolved (observation-outcome-status outcome))
              (note-unresolved-row job frame row type)
              (setf (heuristic-search-phase job) :next))
             (t (settle-heuristic-row job row nil))))
      (:check
       (let ((run (advance-accounted-evaluation (heuristic-search-evaluation job) 1 ledger
                                                :heuristic-checking :heuristic-checking)))
         (case (evaluation-status run)
           (:unknown)  ; the check needs more work
           (:unresolved
            (note-unresolved-row job frame row type)
            (setf (heuristic-search-phase job) :next))
           (t (settle-heuristic-row job row (and (eq :value (evaluation-status run))
                                                 (eq t (evaluation-value run))))))))
      (:residual
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-residual)
       (when (zerop (heuristic-search-debt job))
         (let ((values (extract-allowed-values (row-requirement row))))
           (setf (heuristic-search-phase job)
                 (cond ((not (constrained-row-p row)) :next)
                       ((consp values)
                        ;; The witness is chosen now; a metric program that ran to price it
                        ;; is paid for before the choice counts.
                        (let ((private (make-ledger)))
                          (multiple-value-bind (witness bits)
                              (closest-row-witness job frame values type outcome private)
                            (cond ((zerop (ledger-total private))
                                   (charge-row-witness job bits)
                                   (push (cons (row-key row) witness) (heuristic-search-residual job))
                                   :next)
                                  (t (setf (heuristic-search-staged job) (list witness bits)
                                           (heuristic-search-debt job) (ledger-total private))
                                     :witness)))))
                       ;; No available correction witness; do not call an unresolved predicate false.
                       (t :observe))))))
      (:witness
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-metric)
       (when (zerop (heuristic-search-debt job))
         (destructuring-bind (witness bits) (heuristic-search-staged job)
           (charge-row-witness job bits)
           (push (cons (row-key row) witness) (heuristic-search-residual job)))
         (setf (heuristic-search-phase job) :next)))
      (:next
       (charge ledger :heuristic-checking)
       (pop (heuristic-search-rows job)) (pop (heuristic-search-outcomes job))
       (incf (heuristic-search-index job)) (setf (heuristic-search-phase job) :row))
      (:score
       (pay-debt (heuristic-search-debt job) 1 ledger :heuristic-ranking)
       (when (zerop (heuristic-search-debt job))
         (record-heuristic-model job (heuristic-search-staged job))
         (setf (heuristic-search-phase job) :observe))))))

(defun heuristic-search-complete-p (job)
  (and (eq :observe (heuristic-search-phase job))
       (or (observation-bound-complete-p (heuristic-search-observation job) (heuristic-search-bound job))
           (and (heuristic-search-stop-on-exact-p job)
                (zerop (heuristic-search-run-weight job))
                (let ((best (heuristic-search-best job)))
                  (and best
                       (heuristic-exact-p best)
                       (heuristic-total-p best)
                       (null (heuristic-unresolved-keys best))))))))

(defun observation-feature-buckets (observation)
  "Return `(expression . values)` pairs for each distinct complete observation bucket in
enumeration order, keeping the first (smallest) representative expression per bucket."
  (loop for bucket in (reverse (observation-job-buckets observation))
        for rec = (car (last (observation-bucket-members bucket)))
        when rec
          collect (cons (observed-expression-expression rec)
                        (observation-bucket-values bucket))))

(defun resume-heuristic-search (job work-limit)
  "Absolute cumulative budget covers observation, checking, residuals, and ranking."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (heuristic-search-ledger job)) work-limit)
                   (not (heuristic-search-complete-p job))) do (heuristic-search-step job))
  (let ((best (heuristic-search-best job)))
    (when best
      (setf (heuristic-buckets best)
            (observation-feature-buckets (heuristic-search-observation job)))))
  (make-message :claim (if (heuristic-search-complete-p job) :bounded-exhaustion :cutoff)
                :evidence (list :description-limit (heuristic-search-bound job)
                                :work (ledger-total (heuristic-search-ledger job))
                                :phase (heuristic-search-phase job) :best (heuristic-search-best job))))
