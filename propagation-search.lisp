(in-package #:lisploop)

;;; A fixed two-branch control, using existing core jobs and VM continuations.
;;; No learned scheduler, new expression enumerator or unchecked acceptance path.
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
search; successful tentative branches never remove it. Continuations survive
cutoffs and increasing description bounds. Exhaustion covers both branches."
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
                   ;; A tentative acceptance must be checked before another is queued.
                   (setf (propagation-search-lane state) nil)
                   (when (eq lane :verification) (setf (propagation-search-verification state) nil)))))))))
    (make-message :call-id (search-job-call-id (propagation-search-primary state))
                  :claim (cond ((and stop-on-first (propagation-search-best state)) :candidate)
                               ((propagation-search-finished-p state description-limit) :bounded-exhaustion)
                               (t :cutoff))
                  :evidence (list :description-limit description-limit :work (ledger-total ledger)
                                  :first-verified-work (propagation-search-first-work state)))))
