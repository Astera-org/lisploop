(in-package #:lisploop)

;;; Conservative expression simplification; VM errors remain errors.
(defun extract-term-equality (expr)
  "If EXPR is `(= term 'val)` or `(= 'val term)` for a provably-total non-literal TERM,
return (VALUES term term-type lit-node)."
  (when (and (app-p expr) (eq := (operator-name (first expr))))
    (let ((lhs (first (rest expr)))
          (rhs (second (rest expr)))
          (type (operator-operand-type (first expr))))
      (cond
        ((and (not (lit-p lhs)) (lit-p rhs) (provably-total-p lhs))
         (values lhs type rhs))
        ((and (lit-p lhs) (not (lit-p rhs)) (provably-total-p rhs))
         (values rhs type lhs))
        (t nil)))))

(defun extract-term-membership (expr)
  "If EXPR is `(member term '(v1 ... vk))` for a provably-total non-literal TERM,
return (VALUES term term-type values-list)."
  (when (and (app-p expr) (eq :member (operator-name (first expr))))
    (let ((lhs (first (rest expr)))
          (rhs (second (rest expr)))
          (type (operator-operand-type (first expr))))
      (when (and (not (lit-p lhs)) (lit-p rhs) (provably-total-p lhs))
        (values lhs type (ast-value rhs))))))

(defun replace-subexpression (expr target replacement)
  "Replace every subtree of EXPR that is EQUAL to TARGET with REPLACEMENT."
  (cond
    ((equal expr target) replacement)
    ((app-p expr)
     (let* ((args (rest expr))
            (new-args (mapcar (lambda (arg) (replace-subexpression arg target replacement)) args)))
       (if (every #'eq new-args args)
           expr
           (apply #'app (first expr) new-args))))
    (t expr)))

(defun extract-conjuncts (expr)
  "Return the list of atomic conjuncts of a `(if A B 'nil)` conjunction tree."
  (let ((meta (ignore-errors (ensure-ast-meta expr))))
    (if (and meta
             (eq :app (ast-meta-kind meta))
             (eq :bool (ast-meta-type meta))
             (eq :if (operator-name (first expr)))
             (lit-p (fourth expr))
             (null (ast-value (fourth expr))))
        (nconc (extract-conjuncts (second expr))
               (extract-conjuncts (third expr)))
        (list expr))))

(defun propagate-conjunct-equalities (conjuncts target-expr)
  "Substitute every singleton equality `(= term 'c)` found in CONJUNCTS into TARGET-EXPR."
  (let ((result target-expr))
    (dolist (c conjuncts result)
      (multiple-value-bind (eq-term eq-type eq-lit) (extract-term-equality c)
        (declare (ignore eq-type))
        (when eq-term
          (setf result (replace-subexpression result eq-term eq-lit)))))))

(defun extract-at-coordinate-equality (expr)
  "If EXPR is `(= (at base 'idx) 'val)` on a tuple-typed BASE, return (VALUES base tuple-type idx val)."
  (multiple-value-bind (term term-type lit-node) (extract-term-equality expr)
    (declare (ignore term-type))
    (when (and term (app-p term) (eq :at (operator-name (first term))))
      (let* ((base (second term))
             (idx-node (third term))
             (base-meta (ignore-errors (ensure-ast-meta base)))
             (base-type (and base-meta (ast-meta-type base-meta))))
        (when (and base-type (consp base-type) (eq :tuple (first base-type))
                   (provably-total-p base)
                   (lit-p idx-node) (integerp (ast-value idx-node))
                   (<= 0 (ast-value idx-node)) (< (ast-value idx-node) (length (rest base-type))))
          (values base base-type (ast-value idx-node) (ast-value lit-node)))))))

(defun try-reassemble-tuple-coordinates (conjuncts)
  "When CONJUNCTS pin every slot 0..k-1 of a tuple term V via `(= (at V 'i) 'v_i)`,
reassemble those conjuncts into `(= V '(v_0 ... v_{k-1}))`. Returns (VALUES expr changed-p)."
  (let ((by-base nil))
    (dolist (c conjuncts)
      (multiple-value-bind (base tuple-type idx val) (extract-at-coordinate-equality c)
        (when base
          (let ((entry (assoc base by-base :test #'equal)))
            (unless entry
              (setf entry (list base tuple-type (make-array (length (rest tuple-type)) :initial-element :unbound) nil)
                    by-base (cons entry by-base)))
            (let ((slots (third entry)))
              (cond
                ((eq :unbound (aref slots idx))
                 (setf (aref slots idx) val)
                 (push c (fourth entry)))
                ((not (equal (aref slots idx) val))
                 (return-from try-reassemble-tuple-coordinates (values (lit :bool nil) t)))
                (t
                 (push c (fourth entry)))))))))
    (dolist (entry (nreverse by-base))
      (destructuring-bind (base tuple-type slots used-conjuncts) entry
        (when (loop for s across slots never (eq s :unbound))
          (let* ((tuple-val (coerce slots 'list))
                 (tuple-eq (app (op := tuple-type) base (lit tuple-type tuple-val)))
                 (remaining (remove-if (lambda (c) (member c used-conjuncts :test #'equal)) conjuncts))
                 (all-conjuncts (cons tuple-eq remaining)))
            (return-from try-reassemble-tuple-coordinates
              (values (reduce #'bool-and all-conjuncts :from-end t) t))))))
    (values nil nil)))

(defun fold-constants (expression &optional schema &key ledger (budget 10000))
  "Preserve values AND definedness. One budget covers the complete traversal.
An error or cutoff leaves its expression intact. No table inversion is built in."
  (declare (ignore schema))
  (let ((remaining budget))
    (labels
        ((walk (expr)
           (when (zerop remaining) (return-from walk expr))
           (decf remaining) (charge ledger :simplification)
           (unless (app-p expr) (return-from walk expr))
           (let ((operator (first expr)))
             (if (eq :if (operator-name operator))
                 (let ((condition (walk (second expr))))
                   (when (lit-p condition)
                     (return-from walk (walk (if (ast-value condition) (third expr) (fourth expr)))))
                   (let* ((yes (walk (propagate-conjunct-equalities (extract-conjuncts condition)
                                                                  (third expr))))
                          (no (walk (fourth expr)))
                          (rebuilt (app operator condition yes no)))
                     (cond
                       ((and (provably-total-p condition) (equal yes no)) yes)
                       ((and (equal yes (lit :bool t)) (equal no (lit :bool nil))) condition)
                       ;; Set filtering/reordering is safe only for a total conjunction.
                       ((and (eq :bool (ast-type rebuilt)) (equal no (lit :bool nil))
                             (provably-total-p condition) (provably-total-p yes))
                        (simplify-conjunction rebuilt condition yes))
                       (t rebuilt))))
                 (let* ((args (mapcar #'walk (rest expr)))
                        (rebuilt (apply #'app operator args)))
                   (cond
                     ((null (free-vars rebuilt))
                      (let ((run (evaluate rebuilt nil nil :budget remaining :ledger ledger)))
                        (decf remaining (evaluation-work run))
                        (if (eq :value (evaluation-status run))
                            (lit (ast-type rebuilt) (evaluation-value run)) rebuilt)))
                     ((and (eq :at (operator-name operator)) (app-p (first args))
                           (eq :tuple (operator-name (first (first args))))
                           (lit-p (second args)) (every #'provably-total-p (rest (first args))))
                      (let ((i (ast-value (second args))) (parts (rest (first args))))
                        (if (and (integerp i) (<= 0 i) (< i (length parts))) (nth i parts) rebuilt)))
                     ((and (eq :member (operator-name operator)) (lit-p (second args))
                           (provably-total-p (first args)))
                      (let ((values (remove-duplicates (ast-value (second args)) :test #'equal)))
                        (cond ((null values) (lit :bool nil))
                              ;; Walk the equality too, so a tuple operand splits into coordinates.
                              ((null (rest values)) (walk (app (op := (ast-type (first args))) (first args)
                                                              (lit (ast-type (first args)) (first values)))))
                              (t rebuilt))))
                     ((eq := (operator-name operator))
                      (let* ((lhs (first args)) (rhs (second args))
                             (tuple (cond ((and (app-p lhs) (lit-p rhs)) lhs)
                                          ((and (app-p rhs) (lit-p lhs)) rhs)))
                             (literal (if (eq tuple lhs) rhs lhs)))
                        (if (and tuple (eq :tuple (operator-name (first tuple)))
                                 (every #'provably-total-p (rest tuple)))
                            (walk (reduce #'bool-and
                                          (loop for part in (rest tuple)
                                                for value in (ast-value literal)
                                                collect (app (op := (ast-type part)) part
                                                             (lit (ast-type part) value)))
                                          :from-end t :initial-value (lit :bool t)))
                            rebuilt)))
                     (t rebuilt))))))
         (simplify-conjunction (whole condition yes)
           (let* ((conjuncts (append (extract-conjuncts condition) (extract-conjuncts yes)))
                  (substituted (propagate-conjunct-equalities (extract-conjuncts yes) condition)))
             (unless (equal substituted condition)
               (return-from simplify-conjunction (walk (bool-and substituted yes))))
             (loop for c in conjuncts
                   for c-pos from 0
                   do (multiple-value-bind (term type values) (extract-term-membership c)
                        (when (and term values)
                          (let* (( probe (lit type (first values)))
                                 (mentions-p
                                   (loop for other in conjuncts
                                         for o-pos from 0
                                         collect (and (/= o-pos c-pos)
                                                      (not (eq other (replace-subexpression other term probe)))))))
                            (when (some #'identity mentions-p)
                              (let ((kept nil)
                                    (entailed (copy-list mentions-p))
                                    (aborted nil))
                                (dolist (value values)
                                  (let ((val-lit (lit type value))
                                        ( refuted nil))
                                    (loop for other in conjuncts
                                          for mention-p in mentions-p
                                          for o-pos from 0
                                          when mention-p
                                          do (let ((res (walk (replace-subexpression other term val-lit))))
                                               (when (zerop remaining)
                                                 (setf aborted t))
                                               (cond
                                                 ((and (lit-p res) (null (ast-value res)))
                                                  (setf refuted t)
                                                  (return))
                                                 ((not (and (lit-p res) (eq t (ast-value res))))
                                                  (setf (nth o-pos entailed) nil)))))
                                    (unless refuted
                                      (push value kept))))
                                (setf kept (nreverse kept))
                                (when (and (not aborted)
                                           (or (< (length kept) (length values))
                                               (some #'identity entailed)))
                                  (when (null kept)
                                    (return-from simplify-conjunction (lit :bool nil)))
                                  (let* ((new-c (if (null (rest kept))
                                                    (app (op := type) term (lit type (first kept)))
                                                    (app (op :member type) term (lit (sequence-type type) kept))))
                                         (rebuilt-conjuncts
                                           (loop for item in conjuncts
                                                 for ent-p in entailed
                                                 for o-pos from 0
                                                 unless ent-p
                                                 collect (if (= o-pos c-pos) new-c item))))
                                    (return-from simplify-conjunction
                                      (walk (reduce #'bool-and rebuilt-conjuncts :from-end t)))))))))))
             (multiple-value-bind (rebuilt changed) (try-reassemble-tuple-coordinates conjuncts)
               (if changed rebuilt whole)))))
      (walk expression))))

