(in-package #:lisploop)

;;; Conservative expression simplification; VM errors remain errors.
(defun match-literal-equality (expr &key singleton-member-p)
  "If EXPR equates a non-literal TERM to a literal value (or a singleton :member set when
SINGLETON-MEMBER-P is true), return (VALUES term term-type lit-node)."
  (when (and (app-p expr) (operator-p (first expr)))
    (let ((op-name (operator-name (first expr)))
          (lhs (second expr))
          (rhs (third expr))
          (type (operator-operand-type (first expr))))
      (cond
        ((eq := op-name)
         (cond
           ((and (not (lit-p lhs)) (lit-p rhs)) (values lhs type rhs))
           ((and (lit-p lhs) (not (lit-p rhs))) (values rhs type lhs))))
        ((and singleton-member-p (eq :member op-name)
              (not (lit-p lhs)) (lit-p rhs))
         (let ((vals (remove-duplicates (ast-value rhs) :test #'equal)))
           (when (and vals (null (rest vals)))
             (values lhs type (lit type (first vals))))))))))

(defun extract-term-equality (expr)
  "If EXPR is `(= term 'val)` or `(= 'val term)` for a provably-total non-literal TERM,
return (VALUES term term-type lit-node)."
  (multiple-value-bind (term type lit-node) (match-literal-equality expr)
    (when (and term (provably-total-p term))
      (values term type lit-node))))

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

(defun tuple-slot-term (term)
  "If TERM is `(at base 'idx)` on a tuple-typed BASE, return (VALUES base tuple-type idx)."
  (when (and (app-p term) (operator-p (first term)) (eq :at (operator-name (first term))))
    (let* ((base (second term))
           (idx-node (third term))
           (base-meta (ignore-errors (ensure-ast-meta base)))
           (base-type (and base-meta (ast-meta-type base-meta))))
      (when (and base-type (consp base-type) (eq :tuple (first base-type))
                 (lit-p idx-node) (integerp (ast-value idx-node))
                 (<= 0 (ast-value idx-node)) (< (ast-value idx-node) (length (rest base-type))))
        (values base base-type (ast-value idx-node))))))

(defun extract-at-coordinate-equality (expr)
  "If EXPR is `(= (at base 'idx) 'val)` on a tuple-typed BASE, return (VALUES base tuple-type idx val)."
  (multiple-value-bind (term term-type lit-node) (extract-term-equality expr)
    (declare (ignore term-type))
    (when term
      (multiple-value-bind (base tuple-type idx) (tuple-slot-term term)
        (when (and base (provably-total-p base))
          (values base tuple-type idx (ast-value lit-node)))))))

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

(defvar *fold-contract* :equivalent)

(defun unfoldable-seq-part-p (expr)
  "Return T if EXPR is provably total or built from total constructors, holes,
`:code-eval`, and structurally terminating functions without unguarded partial primitives."
  (or (provably-total-p expr)
      (and (eq *fold-contract* :necessary) (hole-p expr))
      (and (eq *fold-contract* :necessary) (app-p expr)
           (let ((head (first expr)) (args (rest expr)))
             (and (every #'unfoldable-seq-part-p args)
                  (or (hole-p head)
                      (operator-step-total-p
                       (operator-name head) args
                       (lambda (c) (provably-total-code-arg-p c t)))))))))

(defun demanded-vars (expr)
  "Variables evaluated on every successful path. Quoted syntax has its own scope."
  (cond ((var-p expr) (list (ast-id expr)))
        ((not (app-p expr)) nil)
        ((eq :if (ast-id expr))
         (union (demanded-vars (second expr))
                (intersection (demanded-vars (third expr))
                              (demanded-vars (fourth expr)) :test #'eql)
                :test #'eql))
        (t (reduce (lambda (a b) (union a b :test #'eql))
                   (mapcar #'demanded-vars (rest expr)) :initial-value nil))))

(defun non-total-args-preserved-p (inputs call-args target-template)
  "Verify that every argument in CALL-ARGS that is not strictly `provably-total-p`
is demanded in TARGET-TEMPLATE, so call-by-value errors are never dropped."
  (let ((used-vars (demanded-vars target-template)))
    (loop for (id . nil) in inputs
          for arg in call-args
          always (or (provably-total-p arg)
                     (member id used-vars :test #'eql)))))

(defun fold-constants (expression &optional schema &key ledger (budget 10000)
                                                       (contract :equivalent))
  "Preserve values AND definedness. One budget covers the complete traversal.
An error or cutoff leaves its expression intact. No table inversion is built in."
  (declare (ignore schema))
  (assert (member contract '(:equivalent :necessary)))
  (when (eq contract :necessary) (assert (eq :bool (ast-type expression))))
  (let ((remaining budget) (*fold-contract* contract))
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
                   (let* ((code-eval-cond-p (and (app-p condition)
                                                 (operator-p (first condition))
                                                 (eq :code-eval (operator-name (first condition)))))
                          (raw-yes (propagate-conjunct-equalities (extract-conjuncts condition)
                                                                  (third expr)))
                          (yes (walk (if code-eval-cond-p
                                         (replace-subexpression raw-yes condition (lit :bool t))
                                         raw-yes)))
                          (no (walk (if code-eval-cond-p
                                        (replace-subexpression (fourth expr) condition (lit :bool nil))
                                        (fourth expr))))
                          (rebuilt (app operator condition yes no)))
                     (cond
                       ;; Knowing that a condition is code does not prove that running
                       ;; it terminates or succeeds. Equal branches may discard only
                       ;; a total condition; branch-local assumptions above still
                       ;; retain the original condition's evaluation.
                       ((and (provably-total-p condition) (equal yes no)) yes)
                       ((and (equal yes (lit :bool t)) (equal no (lit :bool nil))) condition)
                       ((and (eq :bool (ast-type rebuilt))
                             (equal yes (lit :bool nil))
                             (not (equal no (lit :bool nil)))
                             (or (provably-total-p condition) code-eval-cond-p))
                        (let ((neg-cond (app (op := :bool) condition (lit :bool nil))))
                          (if (equal no (lit :bool t))
                              neg-cond
                              (bool-and neg-cond no))))
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
                           (lit-p (second args)) (every #'unfoldable-seq-part-p (rest (first args))))
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
                      (multiple-value-bind (compound comp-type literal) (match-literal-equality rebuilt)
                        (declare (ignore comp-type))
                        (let ((comp-op (and (app-p compound) (operator-p (first compound))
                                            (operator-name (first compound)))))
                          (cond
                            ((and (eq :tuple comp-op)
                                  (every #'unfoldable-seq-part-p (rest compound)))
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
                            ((and (eq :if comp-op)
                                  (consp (ast-type compound))
                                  (eq :seq (first (ast-type compound)))
                                  (unfoldable-seq-part-p (second compound)))
                             (if (zerop remaining)
                                 rebuilt
                                 (let* ((seq-type (ast-type compound))
                                        (distributed (app (op :if :bool)
                                                          (second compound)
                                                          (app (op := seq-type) (third compound) literal)
                                                          (app (op := seq-type) (fourth compound) literal)))
                                        (res (walk distributed)))
                                   (if (zerop remaining) rebuilt res))))
                            (t rebuilt)))))
                     (t (try-unfold-call rebuilt op-name args)))))))
         (try-unfold-call (rebuilt op-name args)
           (when (zerop remaining) (return-from try-unfold-call rebuilt))
           (multiple-value-bind (inputs body call-args recursive-p)
               (cond
                 ((and op-name (defined-function-p op-name))
                  (let ((def (find-function-definition op-name)))
                    (when (and def (function-definition-body def)
                               (null (function-definition-oracle-table def)))
                      (values (function-definition-inputs def) (function-definition-body def)
                              args (contains-call-to-p (function-definition-body def) op-name)))))
                 ((eq :code-eval op-name)
                  (let ((code-arg (first args)) (eval-args (rest args)))
                    (cond
                      ((lit-p code-arg)
                       (values (code-inputs (ast-type code-arg)) (ast-value code-arg) eval-args nil))
                      ((and (app-p code-arg) (eq :code-subst (ast-id code-arg))
                            (lit-p (second code-arg))
                            (app-p (third code-arg)) (eq :tuple (ast-id (third code-arg))))
                       (let* ((a-inputs (code-inputs (ast-type (second code-arg))))
                              (c-type (ast-type code-arg))
                              (c-inputs (code-inputs c-type))
                              (eval-bindings (bind-inputs c-inputs eval-args))
                              (parts (rest (third code-arg)))
                              (sub-args (loop for b in parts
                                              for (nil . in-type) in a-inputs
                                              collect (if (code-subst-code-binding-p (ast-type b) c-type in-type)
                                                          (if (lit-p b)
                                                              (instantiate (ast-value b) eval-bindings :var)
                                                              (apply #'app (op :code-eval (ast-type b)) b eval-args))
                                                          b))))
                         (when (and (every #'unfoldable-seq-part-p sub-args)
                                    (loop for (cid . nil) in c-inputs
                                          for earg in eval-args
                                          always (or (provably-total-p earg)
                                                     (loop for b in parts
                                                           for (nil . in-type) in a-inputs
                                                           thereis (and (code-subst-code-binding-p (ast-type b) c-type in-type)
                                                                        (lit-p b)
                                                                        (member cid (demanded-vars (ast-value b)) :test #'eql))))))
                           (values a-inputs (ast-value (second code-arg)) sub-args nil))))))))
             (when body
               (let ((bindings (bind-inputs inputs call-args)))
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

