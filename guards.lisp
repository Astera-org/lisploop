(in-package #:lisploop)

;;; A support mask is execution evidence, not a rewrite certificate. Its false
;;; rows include both unequal values and errors; neither is equality evidence.
(defstruct (guard-problem (:constructor %make-guard-problem)) scope support frame equations)

(defun complete-outcomes-p (record)
  (and (member (observed-expression-status record) '(:complete :error))
       (= (length (observed-expression-outcomes record))
          (length (frame-rows (observation-scope-frame (observed-expression-scope record)))))
       (every (lambda (outcome) (member (observation-outcome-status outcome) '(:value :error)))
              (observed-expression-outcomes record))))

(defun observed-support (left right &optional ledger)
  "Exact row membership where both expressions return equal, same-typed values.
Require all outcomes from the SAME scope. Unknown rows never become false labels."
  (assert (eq (observed-expression-scope left) (observed-expression-scope right)))
  (assert (equal (observed-expression-type left) (observed-expression-type right)))
  (assert (and (complete-outcomes-p left) (complete-outcomes-p right)) ()
          "Support requires completed per-row outcomes; resume observation first")
  (loop with type = (observed-expression-type left)
        for a in (observed-expression-outcomes left)
        for b in (observed-expression-outcomes right) collect
          (progn
            (charge ledger :support-comparison
                    (+ 2 (if (eq :value (observation-outcome-status a))
                             (value-work (observation-outcome-value a) type) 0)
                         (if (eq :value (observation-outcome-status b))
                             (value-work (observation-outcome-value b) type) 0)))
            (and (eq :value (observation-outcome-status a))
                 (eq :value (observation-outcome-status b))
                 (equal (observation-outcome-value a) (observation-outcome-value b))))))

(defun support-frame (scope support &optional ledger)
  "Turn an observed membership residual into an ordinary Boolean synthesis frame.
Every occurrence stays present. The predictor receives only the original inputs."
  (let ((frame (observation-scope-frame scope)))
    (assert (= (length support) (length (frame-rows frame))))
    (assert (every (lambda (value) (value-p value :bool)) support))
    (make-frame
     (make-schema :inputs (copy-tree (schema-inputs (frame-schema frame))) :target :bool)
     (loop for row in (frame-rows frame) for member-p in support collect
       (let ((allowed (finite-allowed :bool (list member-p))))
         (charge ledger :guard-frame
                 (+ 1 (syntax-work (allowed-expression allowed))
                    (loop for value in (row-known row)
                          for input in (schema-inputs (frame-schema frame))
                          sum (value-work value (cdr input)))))
         (make-row :key (copy-tree (row-key row)) :known (copy-tree (row-known row)) :allowed allowed))))))

(defun propose-guard-problems (job &optional ledger)
  "Compare all pairs of finished expressions and group proper nonempty supports.
The finite scan is synchronous and metered, like PROPOSE-OBSERVED-LAWS. Guard
search and independent validation use their existing resumable jobs."
  (assert (observation-job-retain-outcomes-p job))
  (assert (and (eq :enumerate (observation-job-phase job))
               (observation-bound-complete-p job (observation-job-requested-bound job))) ()
          "Finish the requested observation bound before constructing guard problems")
  (let* ((scope (observation-job-scope job))
         (domain (language-domain (observation-scope-language scope)))
         (records (reverse (observation-job-records job)))
         (groups (make-hash-table :test #'equal)) (problems nil))
    (assert (every #'complete-outcomes-p records))
    (loop for tail on records for left = (first tail) do
      (dolist (right (rest tail))
        (charge ledger :support-pairs)
        (when (and (equal (observed-expression-type left) (observed-expression-type right))
                   (member (observed-expression-type left) (list domain :bool) :test #'equal))
          (let ((support (observed-support left right ledger)))
            ;; Empty support has no useful equation; full support belongs to the
            ;; ordinary equality buckets. Retain ALL pairs on a proper support.
            (charge ledger :support-index (1+ (length support)))
            (when (and (some #'identity support) (not (every #'identity support)))
              (let ((problem (gethash support groups))
                    (a (observed-expression-expression left))
                    (b (observed-expression-expression right)))
                (unless problem
                  (setf problem (%make-guard-problem :scope scope :support support
                                                    :frame (support-frame scope support ledger))
                        (gethash support groups) problem)
                  (push problem problems))
                (charge ledger :guard-equations (+ (syntax-work a) (syntax-work b)))
                (push (list (copy-tree a) (copy-tree b)) (guard-problem-equations problem))))))))
    (dolist (problem problems)
      (setf (guard-problem-equations problem) (nreverse (guard-problem-equations problem))))
    (nreverse problems)))

(defun start-guard-search (problem language &key (call-id (incf *next-call-id*)) (run-weight 0))
  "Synthesize the complete observed support, including its false rows."
  (let ((source (observation-scope-language (guard-problem-scope problem))))
    (assert (equal (language-domain source) (language-domain language)))
    (assert (equal (language-inputs source) (language-inputs language)))
    (start-search (guard-problem-frame problem)
                  (snapshot-language language)
                  :call-id call-id :run-weight run-weight)))

(defun propose-guarded-laws (problem search &optional ledger)
  "Attach the best successful guard so far to each equation, as conjectures only.
No candidate means no proposals; a cutoff never means that no guard exists."
  (assert (eq (search-job-frame search) (guard-problem-frame problem)))
  (let* ((scope (guard-problem-scope problem)) (language (observation-scope-language scope))
         (best (search-job-best search)) (guard (and best (candidate-expression best))))
    (when best
      (loop for (left right) in (guard-problem-equations problem) collect
        (progn
          (charge ledger :law-proposal (+ (syntax-work left) (syntax-work right) (syntax-work guard)
                                         (length (guard-problem-support problem))))
          (make-law (language-domain language) (language-inputs language) left right :guard guard
                    :origin (list :observed-scope (observation-scope-id scope)
                                  :support (copy-list (guard-problem-support problem))
                                  :evidence :replayed-observations)))))))
