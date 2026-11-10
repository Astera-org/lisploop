(in-package #:lisploop)

;;; Milestone 8B: feature enumeration followed by feature-conditioned synthesis.

(defstruct (dependency-search (:constructor %make-dependency-search))
  frame language observation feature-bound selector-bound synthesis
  (ledger (make-ledger)) (phase :features) records features (debt 0))

(defun start-dependency-search (frame feature-language selector-language feature-bound selector-bound)
  "Synthesize dependency features, then solve under each induced context.
Feature equivalence is scoped to the observed rows, never promoted to a law."
  (let ((frame (snapshot-frame frame)))
    (%make-dependency-search :frame frame :language (snapshot-language selector-language)
     :feature-bound feature-bound :selector-bound selector-bound
     :observation (start-observation-search
                   (make-observation-scope
                    (unconstrained-frame frame (language-domain feature-language))
                    feature-language)))))

(defun resume-dependency-search (job work-limit)
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (let ((ledger (dependency-search-ledger job)) (obs (dependency-search-observation job)))
    (loop while (< (ledger-total ledger) work-limit) do
      (case (dependency-search-phase job)
        (:features
         (if (observation-bound-complete-p obs (dependency-search-feature-bound job))
             (setf (dependency-search-phase job) :collect
                   (dependency-search-records job) (reverse (observation-job-buckets obs)))
             (let ((before (ledger-total (observation-job-ledger obs))))
               (observation-step obs 1)
               (charge ledger :feature-search (- (ledger-total (observation-job-ledger obs)) before)))))
        (:collect
         (charge ledger :dependency-proposal)
         (if (dependency-search-records job)
             (let* ((bucket (pop (dependency-search-records job)))
                    ;; Enumeration visits shorter expressions first; bucket members are newest first.
                    (record (car (last (observation-bucket-members bucket)))))
               (push (observed-expression-expression record) (dependency-search-features job)))
             (let ((features (nreverse (dependency-search-features job))))
               (setf (dependency-search-debt job)
                     (1+ (reduce #'+ features :key #'syntax-work :initial-value 0))
                     (dependency-search-features job) features
                     (dependency-search-phase job) :prepare))))
        (:prepare
         (pay-debt (dependency-search-debt job) (- work-limit (ledger-total ledger))
                   ledger :dependency-proposal)
         (when (zerop (dependency-search-debt job))
           (setf (dependency-search-synthesis job)
                 (start-synthesis (dependency-search-frame job) (dependency-search-language job)
                                  (dependency-search-selector-bound job)
                  :decompositions (dependency-proposals (dependency-search-frame job) (dependency-search-language job)
                                                        (dependency-search-selector-bound job)
                                                        :features (dependency-search-features job)))
                 (dependency-search-phase job) :solve)))
        (:solve
         (let* ((search (dependency-search-synthesis job)) (before (ledger-total (synthesis-job-ledger search))))
           (resume-synthesis search (+ before (- work-limit (ledger-total ledger))))
           (charge ledger :dependency-synthesis (- (ledger-total (synthesis-job-ledger search)) before))
           (when (synthesis-finished-p search) (setf (dependency-search-phase job) :done))))
        (:done (return))))
    (make-message :claim (if (eq :done (dependency-search-phase job)) :bounded-exhaustion :cutoff)
                  :evidence (list :phase (dependency-search-phase job) :work (ledger-total ledger)
                                  :features (dependency-search-features job)
                                  :synthesis (dependency-search-synthesis job)))))
