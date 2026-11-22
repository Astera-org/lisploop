(in-package #:lisploop)

;;; Requirement fibers: same-input tightening and bounded partition proposals.

;;; Operation 2.4: Optional Fiber Partition Proposals (infer-fibers)
(defstruct fiber-class
  (id 0 :type fixnum)
  requirement
  rows
  keys)

(defun tighten-same-input-requirements (frame &optional ledger (budget 10000))
  "Intersect only identical complete input tuples, including zero-input problems.
Projection onto fewer inputs is a separate synthesis hypothesis.
Returns the vector of tightened requirements, one per row of FRAME."
  (let* ((rows (frame-rows frame))
         (requirements (map 'vector (lambda (row)
                                     (fold-constants (row-requirement row)
                                                     :ledger ledger :budget budget)) rows))
         (groups (make-hash-table :test #'equal))) ; input tuple -> its row indices, latest first
    (loop for row in rows for i from 0
          unless (member :unresolved (row-known row))
            do (push i (gethash (row-known row) groups)))
    (maphash (lambda (known indices)
               (declare (ignore known))
               (let ((joint (aref requirements (first indices))))
                 (dolist (i (rest indices))
                   (charge ledger :fiber-inference)
                   (setf joint (conjoin-requirements joint (aref requirements i)
                                                    :ledger ledger :budget budget)))
                 (dolist (i indices) (setf (aref requirements i) joint)))) groups)
    requirements))

(defun requirement-groups (requirements target-inputs)
  "Group the row indices of the vector REQUIREMENTS by identical requirement.
Returns (VALUES groups refuted) as fiber classes without ids or keys. GROUPS holds the
satisfiable requirements in the order the partition search assigns them: constrained before
unconstrained `'t`, then smaller body first, then first appearance. REFUTED holds one class
for each row whose requirement is unsatisfiable."
  (let ((groups nil)
        (refuted nil))
    (loop for requirement across requirements
          for i from 0
          for group = (find requirement groups :key #'fiber-class-requirement :test #'equal)
          do (cond ((unsatisfiable-requirement-p requirement)
                    (push (make-fiber-class :requirement requirement :rows (list i)) refuted))
                   (group
                    (push i (fiber-class-rows group)))
                   (t
                    (push (make-fiber-class :requirement requirement :rows (list i)) groups))))
    (dolist (group groups)
      (setf (fiber-class-rows group) (nreverse (fiber-class-rows group))))
    (values (stable-sort
             (nreverse groups)
             (lambda (a b)
               (lex< a b
                     (lambda (group)
                       (if (unconstrained-requirement-p (fiber-class-requirement group)) 1 0))
                     (lambda (group)
                       (body-size (fiber-class-requirement group) target-inputs)))))
            (nreverse refuted))))

(defun search-fiber-partition (groups target-inputs ledger budget branch-limit)
  "Bounded branch and bound over the ways to merge GROUPS, in order, into classes whose
joint requirement is not refuted: each group first tries every class built so far, then
starts a class of its own. Partitions are ranked by fewest classes, then fewest requirement
bits summed over rows, then greatest concentration (sum of squared class sizes); among
equals the first one found is kept.
Returns (VALUES classes branches); BRANCHES exceeds BRANCH-LIMIT when the search was cut off."
  (let ((best groups)
        (best-score (list (length groups) most-positive-fixnum -1)) ; (classes bits concentration)
        (branches 0))
    (labels ((score (classes)
               (loop for class in classes
                     for size = (length (fiber-class-rows class))
                     sum (* size (body-size (fiber-class-requirement class) target-inputs))
                       into bits
                     sum (* size size) into concentration
                     finally (return (list (length classes) bits concentration))))
             (dfs (groups classes)
               (cond
                 ;; Stop when cut off, or with more classes than the best partition has.
                 ((or (> (incf branches) branch-limit)
                      (> (length classes) (first best-score))))
                 ((null groups)
                  (let ((candidate (score classes)))
                    (when (lex< candidate best-score #'first #'second (list :desc #'third))
                      (setf best classes
                            best-score candidate))))
                 (t
                  (let ((group (first groups)))
                    (dolist (class classes)
                      (charge ledger :fiber-inference)
                      (let ((joint (conjoin-requirements (fiber-class-requirement class)
                                                         (fiber-class-requirement group)
                                                         :ledger ledger :budget budget)))
                        (unless (unsatisfiable-requirement-p joint)
                          (dfs (rest groups)
                               (substitute (make-fiber-class
                                            :requirement joint
                                            :rows (append (fiber-class-rows class)
                                                          (fiber-class-rows group)))
                                           class classes)))))
                    (when (< (length classes) (first best-score))
                      (dfs (rest groups) (append classes (list group)))))))))
      (dfs groups nil))
    (values best branches)))

(defun %infer-fibers (frame ledger budget branch-limit)
  "Bounded partition proposals over requirements not yet refuted.
Intersect identical complete inputs, then rank partitions by class count,
repeated requirement bits, and concentration. This proxy is neither an exact
model code length nor Shannon entropy; an unresolved intersection is not a witness."
  (let* ((rows (coerce (frame-rows frame) 'vector))
         (target-inputs (list (cons 0 (schema-target (frame-schema frame)))))
         (requirements (tighten-same-input-requirements frame ledger budget))
         (row-class (make-array (length rows)))) ; row index -> its class
    (multiple-value-bind (groups refuted) (requirement-groups requirements target-inputs)
      (multiple-value-bind (best branches)
          (search-fiber-partition groups target-inputs ledger budget branch-limit)
        ;; Every refuted row is a class of its own; ids follow first appearance in FRAME.
        (let ((classes (sort (append best refuted) #'<
                             :key (lambda (class) (reduce #'min (fiber-class-rows class))))))
          (loop for class in classes
                for id from 0
                for indices = (sort (copy-list (fiber-class-rows class)) #'<)
                do (setf (fiber-class-id class) id
                         (fiber-class-rows class) indices
                         (fiber-class-keys class) (mapcar (lambda (i) (row-key (aref rows i)))
                                                          indices))
                   (dolist (i indices)
                     (setf (aref row-class i) class)))
          (let* ((labels (map 'list #'fiber-class-id row-class))
                 (part (partition-rows (frame-rows frame) labels ledger))
                 (refined-rows
                   (map 'list (lambda (row class)
                                (derive-row row :requirement
                                                (copy-tree (fiber-class-requirement class))))
                        rows row-class)))
            (multiple-value-bind (inferred-pairs inferred-anchors)
                (partition-pairs-and-anchors part nil ledger)
              (values classes labels
                      (derive-frame frame
                                    :rows refined-rows
                                    :pairs (or (frame-pairs frame) inferred-pairs)
                                    :anchors (or (frame-anchors frame) inferred-anchors))
                      part
                      (make-message
                       :claim :partition-proposal
                       :evidence (list :search-status (if (> branches branch-limit)
                                                          :cutoff
                                                          :complete)
                                       :branches branches :feasibility :unresolved
                                       :objective :lexicographic-proxy))))))))))

(defun infer-fibers (frame &optional ledger (budget 1000000) (branch-limit 2048))
  "Optional bounded partition proposal. Unknown satisfiability is never a certificate.
The fifth value reports work/branch cutoff; BUDGET covers this whole invocation."
  (assert (and (integerp budget) (>= budget 0) (integerp branch-limit) (>= branch-limit 0)))
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger budget
                      (values nil nil nil nil (make-message :claim :cutoff
                                              :evidence (list :work (ledger-total ledger) :feasibility :unresolved))))
      (%infer-fibers frame ledger budget branch-limit))))

(defun fiber-pairs-and-anchors (frame &optional ledger (budget 1000000))
  "Compute intra-fiber must-agree `pairs` and cross-fiber must-vary `anchors` from FRAME
via `infer-fibers`. Returns (VALUES pairs anchors refined-frame classes labels partition)."
  (multiple-value-bind (classes labels refined-frame part status)
      (infer-fibers frame ledger budget)
    (unless refined-frame (return-from fiber-pairs-and-anchors (values nil nil nil nil nil nil status)))
    (values (frame-pairs refined-frame)
            (frame-anchors refined-frame)
            refined-frame
            classes
            labels
            part)))
