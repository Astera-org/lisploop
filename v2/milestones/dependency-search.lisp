(in-package #:lisploop)

;;; Milestone 8B: dependency-feature synthesis delegated directly to `start-synthesis` + `dependency-expander`.

(defstruct (dependency-search (:constructor %make-dependency-search))
  synthesis)

(defun start-dependency-search (frame feature-language selector-language feature-bound selector-bound)
  "Synthesize dependency features, then solve under each induced context via `dependency-expander`.
Feature equivalence is scoped to the observed rows, never promoted to a law."
  (%make-dependency-search
   :synthesis (start-synthesis frame selector-language selector-bound
                               :expand (dependency-expander :feature-language feature-language
                                                            :feature-bound feature-bound
                                                            :child-bound selector-bound
                                                            :work-limit most-positive-fixnum)
                               :max-depth 1)))

(defun dependency-search-ledger (job)
  (synthesis-job-ledger (dependency-search-synthesis job)))

(defun dependency-search-features (job)
  (let* ((synth (dependency-search-synthesis job))
         (root (synthesis-job-root synth))
         (proposals (append (mapcar #'synthesis-node-proposal (rest (synthesis-job-nodes synth)))
                            (and root (synthesis-node-deferred-proposals root)))))
    (loop for p in proposals
          for name = (and p (decomposition-name p))
          when (and (consp name) (eq :dependency (first name)) (second name))
            collect (second name))))

(defun resume-dependency-search (job work-limit)
  (let* ((synth (dependency-search-synthesis job))
         (msg (resume-synthesis synth work-limit)))
    (make-message :claim (message-claim msg)
                  :evidence (list :phase (if (synthesis-finished-p synth) :done :solve)
                                  :work (ledger-total (synthesis-job-ledger synth))
                                  :features (dependency-search-features job)
                                  :synthesis synth))))
