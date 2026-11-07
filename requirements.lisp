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

(defun contains-hole-p (expr)
  "Return T if EXPR contains any value or function hole."
  (cond
    ((hole-p expr) t)
    ((app-p expr)
     (or (hole-p (first expr))
         (some #'contains-hole-p (rest expr))))
    (t nil)))

(defun contains-call-to-p (expr op-name)
  "Return T if EXPR contains an application of operator OP-NAME."
  (and (app-p expr)
       (or (and (operator-p (first expr))
                (eq op-name (operator-name (first expr))))
           (some (lambda (child) (contains-call-to-p child op-name)) (rest expr)))))

(defun unfoldable-seq-part-p (expr)
  "Return T if EXPR is provably total or built from total constructors, holes,
`:code-eval`, and structurally terminating functions without unguarded partial primitives."
  (or (provably-total-p expr)
      (hole-p expr)
      (and (app-p expr)
           (let ((head (first expr)) (args (rest expr)))
             (and (every #'unfoldable-seq-part-p args)
                  (or (hole-p head)
                      (let ((name (operator-name head)))
                        (or (member name '(:cons :tuple :length :+ :* :- :< := :member :concat :code-eval :code-subst))
                            (and (defined-function-p name)
                                 (function-definition-conditional-code-params (find-function-definition name)))))))))))

(defun non-total-args-preserved-p (inputs call-args target-template)
  "Verify that every argument in CALL-ARGS that is not strictly `provably-total-p`
is referenced in TARGET-TEMPLATE, so call-by-value errors are never dropped."
  (let ((used-vars (free-vars target-template)))
    (loop for (id . nil) in inputs
          for arg in call-args
          always (or (provably-total-p arg)
                     (member id used-vars :test #'eql)))))

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
             (if (and (operator-p operator) (eq :if (operator-name operator)))
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
                        (rebuilt (apply #'app operator args))
                        (op-name (and (operator-p operator) (operator-name operator))))
                   (cond
                     ((and (null (free-vars rebuilt)) (not (contains-hole-p rebuilt)))
                      (let ((run (evaluate rebuilt nil nil :budget remaining :ledger ledger)))
                        (decf remaining (evaluation-work run))
                        (if (eq :value (evaluation-status run))
                            (lit (ast-type rebuilt) (evaluation-value run)) rebuilt)))
                     ((and (eq :at op-name) (app-p (first args))
                           (operator-p (first (first args)))
                           (eq :tuple (operator-name (first (first args))))
                           (lit-p (second args)) (every #'provably-total-p (rest (first args))))
                      (let ((i (ast-value (second args))) (parts (rest (first args))))
                        (if (and (integerp i) (<= 0 i) (< i (length parts))) (nth i parts) rebuilt)))
                     ((and (eq :at op-name) (app-p (first args))
                           (operator-p (first (first args)))
                           (eq :cons (operator-name (first (first args))))
                           (lit-p (second args))
                           (every #'unfoldable-seq-part-p (rest (first args))))
                      (let ((i (ast-value (second args)))
                            (head (second (first args)))
                            (tail (third (first args))))
                        (cond
                          ((not (and (integerp i) (<= 0 i))) rebuilt)
                          ((zerop i) head)
                          ((zerop remaining) rebuilt)
                          (t (let ((res (walk (app (op :at (ast-type tail)) tail (lit :int (1- i))))))
                               (if (zerop remaining) rebuilt res))))))
                     ((and (eq :tail op-name) (app-p (first args))
                           (operator-p (first (first args)))
                           (eq :cons (operator-name (first (first args))))
                           (every #'unfoldable-seq-part-p (rest (first args))))
                      (third (first args)))
                     ((and (eq :length op-name) (app-p (first args))
                           (operator-p (first (first args)))
                           (eq :cons (operator-name (first (first args))))
                           (every #'unfoldable-seq-part-p (rest (first args))))
                      (if (zerop remaining)
                          rebuilt
                          (let* ((head (second (first args)))
                                 (tail (third (first args)))
                                 (res (walk (app (op :+ :int) (lit :int 1)
                                                 (app (op :length (ast-type head)) tail)))))
                            (if (zerop remaining) rebuilt res))))
                     ((and (eq :member op-name) (lit-p (second args)))
                      (let ((values (remove-duplicates (ast-value (second args)) :test #'equal)))
                        (cond ((and (null values) (provably-total-p (first args))) (lit :bool nil))
                              ;; Walk the equality too, so a tuple/cons operand splits into coordinates.
                              ((and values (null (rest values)))
                               (walk (app (op := (ast-type (first args))) (first args)
                                          (lit (ast-type (first args)) (first values)))))
                              (t rebuilt))))
                     ((eq := op-name)
                      (let* ((lhs (first args)) (rhs (second args))
                             (compound (cond ((and (app-p lhs) (lit-p rhs)) lhs)
                                             ((and (app-p rhs) (lit-p lhs)) rhs)))
                             (literal (if (eq compound lhs) rhs lhs))
                             (comp-op (and compound (operator-p (first compound))
                                           (operator-name (first compound)))))
                        (cond
                          ((and (eq :tuple comp-op)
                                (every #'provably-total-p (rest compound)))
                           (walk (reduce #'bool-and
                                         (loop for part in (rest compound)
                                               for value in (ast-value literal)
                                               collect (app (op := (ast-type part)) part
                                                            (lit (ast-type part) value)))
                                         :from-end t :initial-value (lit :bool t))))
                          ((and (eq :cons comp-op)
                                (every #'unfoldable-seq-part-p (rest compound)))
                           (let ((head (second compound))
                                 (tail (third compound))
                                 (vals (ast-value literal)))
                             (if (null vals)
                                 (lit :bool nil)
                                 (if (zerop remaining)
                                     rebuilt
                                     (let* ((elem-type (ast-type head))
                                            (seq-type (ast-type compound))
                                            (split (bool-and (app (op := elem-type) head
                                                                  (lit elem-type (first vals)))
                                                             (app (op := seq-type) tail
                                                                  (lit seq-type (rest vals)))))
                                            (res (walk split)))
                                       (if (zerop remaining) rebuilt res))))))
                          (t rebuilt))))
                     (t (try-unfold-call rebuilt op-name args)))))))
         (try-unfold-call (rebuilt op-name args)
           (when (zerop remaining) (return-from try-unfold-call rebuilt))
           (multiple-value-bind (inputs body call-args recursive-p)
               (cond
                 ((and op-name (defined-function-p op-name))
                  (let ((def (find-function-definition op-name)))
                    (when (and def (function-definition-body def)
                               (null (function-definition-oracle-table def))
                               (every #'unfoldable-seq-part-p args))
                      (values (function-definition-inputs def) (function-definition-body def)
                              args (contains-call-to-p (function-definition-body def) op-name)))))
                 ((and (eq :code-eval op-name) (every #'unfoldable-seq-part-p (rest args)))
                  (let ((code-arg (first args)) (eval-args (rest args)))
                    (cond
                      ((lit-p code-arg)
                       (values (code-inputs (ast-type code-arg)) (ast-value code-arg) eval-args nil))
                      ((and (app-p code-arg) (eq :code-subst (ast-id code-arg))
                            (lit-p (second code-arg))
                            (app-p (third code-arg)) (eq :tuple (ast-id (third code-arg)))
                            (every #'provably-total-p eval-args))
                       (let* ((a-inputs (code-inputs (ast-type (second code-arg))))
                              (c-type (ast-type code-arg))
                              (eval-bindings (mapcar #'cons (mapcar #'car (code-inputs c-type)) eval-args))
                              (parts (rest (third code-arg))))
                         (when (every (lambda (b spec)
                                        (if (and (same-code-scope-p (ast-type b) c-type)
                                                 (equal (code-sort (ast-type b)) (cdr spec)))
                                            (lit-p b)
                                            (unfoldable-seq-part-p b)))
                                      parts a-inputs)
                           (values a-inputs (ast-value (second code-arg))
                                   (mapcar (lambda (b spec)
                                             (if (and (same-code-scope-p (ast-type b) c-type)
                                                      (equal (code-sort (ast-type b)) (cdr spec)))
                                                 (instantiate (ast-value b) eval-bindings :var)
                                                 b))
                                           parts a-inputs)
                                   nil))))))))
             (when body
               (let ((bindings (mapcar #'cons (mapcar #'car inputs) call-args)))
                 (cond
                   ((and (app-p body) (operator-p (first body)) (eq :if (operator-name (first body))))
                    (let ((folded-cond (walk (instantiate (second body) bindings :var))))
                      (when (and (plusp remaining) (lit-p folded-cond))
                        (let ((branch (if (ast-value folded-cond) (third body) (fourth body))))
                          (when (non-total-args-preserved-p inputs call-args branch)
                            (let ((res (walk (instantiate branch bindings :var))))
                              (unless (zerop remaining) (return-from try-unfold-call res))))))))
                   ((and (not recursive-p) (non-total-args-preserved-p inputs call-args body))
                    (let ((res (walk (instantiate body bindings :var))))
                      (unless (zerop remaining) (return-from try-unfold-call res)))))))
             rebuilt))
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

