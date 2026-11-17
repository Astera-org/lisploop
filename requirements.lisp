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
  (when (app-of-p expr :member)
    (destructuring-bind (lhs rhs) (rest expr)
      (when (and (not (lit-p lhs)) (lit-p rhs) (provably-total-p lhs))
        (values lhs (operator-operand-type (first expr)) (ast-value rhs))))))

(defun replace-subexpression (expr target replacement)
  "Replace every subtree of EXPR that is EQUAL to TARGET with REPLACEMENT."
  (map-ast (lambda (node meta)
             (declare (ignore meta))
             (and (equal node target) replacement))
           expr :root-first t))

(defun extract-conjuncts (expr)
  "Return the list of atomic conjuncts of a `(if A B 'nil)` conjunction tree."
  (if (and (app-of-p expr :if) (eq :bool (ast-type expr))
           (lit-p (fourth expr)) (null (ast-value (fourth expr))))
      (nconc (extract-conjuncts (second expr)) (extract-conjuncts (third expr)))
      (list expr)))

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
  (when (app-of-p term :at)
    (let ((base-type (ast-type (second term)))
          (idx (and (lit-p (third term)) (ast-value (third term)))))
      (when (and (tuple-type-p base-type) (integerp idx) (< -1 idx (length (rest base-type))))
        (values (second term) base-type idx)))))

(defun extract-at-coordinate-equality (expr)
  "If EXPR is `(= (at base 'idx) 'val)` on a tuple-typed BASE, return (VALUES base tuple-type idx val)."
  (multiple-value-bind (term term-type lit-node) (extract-term-equality expr)
    (declare (ignore term-type))
    (when term
      (multiple-value-bind (base tuple-type idx) (tuple-slot-term term)
        (when (and base (provably-total-p base))
          (values base tuple-type idx (ast-value lit-node)))))))

(defun try-reassemble-tuple-coordinates (conjuncts)
  "When CONJUNCTS pin every slot 0..k-1 of a tuple term V via `(= (at V 'i) 'v_i)`, return
their conjunction with those conjuncts reassembled into `(= V '(v_0 ... v_{k-1}))`, or false
when two of them disagree on a slot. Returns nil when no tuple is pinned completely."
  (let ((by-base nil)) ; entries (base slots conjuncts-used), newest first
    (dolist (c conjuncts)
      (multiple-value-bind (base tuple-type idx val) (extract-at-coordinate-equality c)
        (when base
          (let ((entry (assoc base by-base :test #'equal)))
            (unless entry
              (setf entry (list base (make-array (length (rest tuple-type)) :initial-element :unbound)
                                nil))
              (push entry by-base))
            (let ((slots (second entry)))
              (cond ((eq :unbound (aref slots idx)) (setf (aref slots idx) val))
                    ((not (equal (aref slots idx) val))
                     (return-from try-reassemble-tuple-coordinates (lit :bool nil))))
              (push c (third entry)))))))
    (dolist (entry (nreverse by-base))
      (destructuring-bind (base slots used) entry
        (when (notany (lambda (slot) (eq slot :unbound)) slots)
          (return (reduce #'bool-and
                          (cons (term `(= ,base ',(coerce slots 'list)))
                                (remove-if (lambda (c) (member c used :test #'equal)) conjuncts))
                          :from-end t)))))))

(defun contains-call-to-p (expr op-name)
  "Return T if EXPR contains an application of operator OP-NAME."
  (and (app-p expr)
       (or (eq op-name (ast-id expr))
           (some (lambda (child) (contains-call-to-p child op-name)) (rest expr)))))

(defun demanded-vars (expr)
  "Variables evaluated on every successful path. Quoted syntax has its own scope."
  (cond ((var-p expr) (list (ast-id expr)))
        ((not (app-p expr)) nil)
        ((eq :if (ast-id expr))
         (union (demanded-vars (second expr))
                (intersection (demanded-vars (third expr)) (demanded-vars (fourth expr)))))
        (t (reduce #'union (mapcar #'demanded-vars (rest expr)) :initial-value nil))))

(defun non-total-args-preserved-p (inputs call-args target-template)
  "Verify that every argument in CALL-ARGS that is not strictly `provably-total-p`
is demanded in TARGET-TEMPLATE, so call-by-value errors are never dropped."
  (let ((used-vars (demanded-vars target-template)))
    (loop for (id . nil) in inputs
          for arg in call-args
          always (or (provably-total-p arg)
                     (member id used-vars :test #'eql)))))


;;; Folding: a budgeted walk that evaluates closed subterms and applies structural rules.
(defstruct (fold-state (:conc-name fold-))
  "One `fold-constants` traversal: the walk and evaluation steps left in its budget, the
ledger they are charged to, the contract, the fiber cap, and the number of elements already
unfolded along the enclosing `:cons` spine or conjunction."
  remaining ledger contract max-fibers (spine-depth 0))

(defun unfoldable-parts-p (parts contract)
  "True when a fold rule may drop or reorder every expression in PARTS: each is provably
total or, under the :necessary CONTRACT, built from holes, total constructors, `:code-eval`
and structurally terminating functions without unguarded partial primitives."
  (every (lambda (expr)
           (or (provably-total-p expr)
               (and (eq contract :necessary)
                    (or (hole-p expr)
                        (and (app-p expr)
                             (unfoldable-parts-p (rest expr) contract)
                             (or (hole-p (first expr))
                                 (operator-step-total-p (ast-id expr) (rest expr)
                                                        (lambda (c) (provably-total-code-arg-p c t)))))))))
         parts))

(defun fold-walk (state expr)
  "Fold EXPR within the remaining budget. Each node visited costs one unit, and a node
reached with nothing left is returned as it is."
  (when (zerop (fold-remaining state)) (return-from fold-walk expr))
  (decf (fold-remaining state))
  (charge (fold-ledger state) :simplification)
  (cond ((not (app-p expr)) expr)
        ((eq :if (ast-id expr)) (fold-if state expr))
        (t (fold-application state expr))))

(defun fold-walk-at-depth (state depth expr)
  "Fold EXPR as if DEPTH elements of its enclosing spine were already unfolded."
  (let ((outer (shiftf (fold-spine-depth state) depth)))
    (prog1 (fold-walk state expr)
      (setf (fold-spine-depth state) outer))))

(defun keep-or-revert (state reduced original &optional relaxed-p)
  "The budget policy for a rule that folded its result again. If that used up the budget,
REDUCED may be half simplified and the unreduced ORIGINAL stands, except that a relaxed rule
under the :necessary contract keeps REDUCED with whatever it had already unfolded."
  (if (and (zerop (fold-remaining state))
           (not (and relaxed-p (eq :necessary (fold-contract state)))))
      original
      reduced))

(defun fold-rewalk (state original reduced &optional relaxed-p)
  "Fold REDUCED, a one-step reduction of ORIGINAL, unless the budget is already spent, and
apply the budget policy to the result."
  (if (zerop (fold-remaining state))
      original
      (keep-or-revert state (fold-walk state reduced) original relaxed-p)))

(defun fold-if (state expr)
  "Fold the conditional EXPR. A condition that folds to a literal selects its branch.
Otherwise each branch is folded under what the condition tells it, and a Boolean result is
simplified where that cannot drop or reorder a partial computation."
  (let ((condition (fold-walk state (second expr))))
    (when (lit-p condition)
      (return-from fold-if (fold-walk state (if (ast-value condition) (third expr) (fourth expr)))))
    (let* ((true (lit :bool t))
           (false (lit :bool nil))
           (code-eval-cond-p (app-of-p condition :code-eval))
           (raw-yes (propagate-conjunct-equalities (extract-conjuncts condition) (third expr)))
           ;; The body of a conjunction lies one step further along the spine.
           (yes (fold-walk-at-depth
                 state (+ (fold-spine-depth state) (if (equal (fourth expr) false) 1 0))
                 (if code-eval-cond-p (replace-subexpression raw-yes condition true) raw-yes)))
           (no (fold-walk state (if code-eval-cond-p
                                    (replace-subexpression (fourth expr) condition false)
                                    (fourth expr))))
           (rebuilt (app (first expr) condition yes no))
           (bool-p (eq :bool (ast-type rebuilt))))
      (cond
        ;; Knowing that a condition is code does not prove that running
        ;; it terminates or succeeds. Equal branches may discard only
        ;; a total condition; branch-local assumptions above still
        ;; retain the original condition's evaluation.
        ((and (provably-total-p condition) (equal yes no)) yes)
        ((and (equal yes true) (equal no false)) condition)
        ((and bool-p (equal yes false) (not (equal no false))
              (or (provably-total-p condition) code-eval-cond-p))
         (let ((neg-cond (term `(= ,condition ,false))))
           (if (equal no true) neg-cond (bool-and neg-cond no))))
        ;; Set filtering/reordering is safe only for a total conjunction.
        ((and bool-p (equal no false) (provably-total-p condition) (provably-total-p yes))
         (simplify-conjunction state rebuilt condition yes))
        (t rebuilt)))))

(defun fold-application (state expr)
  "Fold the arguments of the application EXPR and reduce the rebuilt term: evaluate it when
it is closed, else apply a structural rule, narrow a literal membership, or unfold a call."
  (let* ((op-name (ast-id expr))
         (args (if (and (eq :cons op-name) (= 2 (length (rest expr))))
                   (list (fold-walk-at-depth state 0 (second expr))
                         (fold-walk-at-depth state (1+ (fold-spine-depth state)) (third expr)))
                   (mapcar (lambda (arg) (fold-walk state arg)) (rest expr))))
         (rebuilt (apply #'app (first expr) args)))
    (cond
      ((and (null (free-vars rebuilt)) (not (pattern-has-holes-p rebuilt)))
       (let ((run (evaluate rebuilt nil nil :budget (fold-remaining state) :ledger (fold-ledger state))))
         (decf (fold-remaining state) (evaluation-work run))
         (if (eq :value (evaluation-status run))
             (lit (ast-type rebuilt) (evaluation-value run))
             rebuilt)))
      ((apply-fold-rule state rebuilt))
      ((and (eq :member op-name) (lit-p (second args)))
       (let ((values (remove-duplicates (ast-value (second args)) :test #'equal)))
         (cond ((and (null values) (provably-total-p (first args))) (lit :bool nil))
               ;; Walk the equality too, so a tuple/cons operand splits into coordinates.
               ((and values (null (rest values)))
                (fold-walk state (term `(= ,(first args) ',(first values)))))
               (t rebuilt))))
      (t (try-unfold-call state rebuilt)))))

(defparameter *fold-rules*
  '((:at (:tuple . fold-at-tuple) (:cons . fold-at-cons))
    (:tail (:cons . fold-tail-cons))
    (:length (:cons . fold-length-cons))
    (:= (:tuple . fold-equal-tuple) (:cons . fold-equal-cons) (:if . fold-equal-if)
        (:code-apply . fold-equal-code-apply) (:code-subst . fold-equal-code-subst))
    (:member (:tuple . fold-member-tuple)))
  "The structural rules, as (outer-operator (inner-constructor . function) ...): each takes
a destructor, or an equality with a literal, off a constructor application. The function
receives the fold state, the whole term, the constructor application and the other operand
(the index or the literal, if there is one), and returns the reduced term or nil when it
does not apply.")

(defun apply-fold-rule (state whole)
  "Reduce WHOLE by the rule of `*fold-rules*` for its operator and the constructor that
operator is applied to, returning nil when no rule applies. A rule needs any other operand
to be a literal and the constructor's parts to be safe to drop or reorder."
  (let ((rules (rest (assoc (ast-id whole) *fold-rules*)))
        (inner (second whole))
        (other (third whole)))
    ;; An equality may carry its literal on either side.
    (when (and (eq := (ast-id whole)) (lit-p inner)) (rotatef inner other))
    (let ((rule (and rules (app-p inner) (cdr (assoc (ast-id inner) rules)))))
      (when (and rule
                 (or (null other) (lit-p other))
                 ;; The branches of an `if` stay behind its condition.
                 (unfoldable-parts-p (if (eq :if (ast-id inner)) (list (second inner)) (rest inner))
                                     (fold-contract state)))
        (funcall rule state whole inner other)))))

(defun fold-at-tuple (state whole tuple index)
  "`(at (tuple e0 ... ek) 'i)` is `ei`."
  (declare (ignore state whole))
  (let ((i (ast-value index)))
    (and (integerp i) (< -1 i (length (rest tuple))) (nth i (rest tuple)))))

(defun fold-at-cons (state whole pair index)
  "`(at (cons head tail) 'i)` is `head` when i is 0 and `(at tail 'i-1)` after that."
  (let ((i (ast-value index)))
    (when (and (integerp i) (<= 0 i))
      (if (zerop i)
          (second pair)
          (fold-rewalk state whole (term `(at ,(third pair) ,(1- i))))))))

(defun fold-tail-cons (state whole pair other)
  "`(tail (cons head tail))` is `tail`."
  (declare (ignore state whole other))
  (third pair))

(defun fold-length-cons (state whole pair other)
  "`(length (cons head tail))` is `(+ 1 (length tail))`."
  (declare (ignore other))
  (fold-rewalk state whole (term `(+ 1 (length ,(third pair))))))

(defun fold-equal-tuple (state whole tuple literal)
  "`(= (tuple e0 ... ek) '(v0 ... vk))` is the conjunction of every `(= ei 'vi)`."
  (declare (ignore whole))
  (fold-walk state (reduce #'bool-and
                           (loop for part in (rest tuple)
                                 for value in (ast-value literal)
                                 collect (term `(= ,part ',value)))
                           :from-end t :initial-value (lit :bool t))))

(defun fold-member-tuple (state whole tuple literal)
  "`(member (tuple e0 ... ek) 'S)` is the conjunction of every `(member ei 'Si)` when S is
exactly the product of the sets Si its tuples take in each place. A set that ties places
together says more than its places do and is left whole."
  (let* ((tuples (remove-duplicates (ast-value literal) :test #'equal))
         (places (loop for index below (length (rest tuple))
                       collect (remove-duplicates (mapcar (lambda (value) (nth index value)) tuples)
                                                  :test #'equal))))
    (when (and tuples (= (length tuples) (reduce #'* places :key #'length)))
      (fold-rewalk state whole
                   (reduce #'bool-and
                           (loop for part in (rest tuple)
                                 for set in places
                                 collect (term `(member ,part ',set)))
                           :from-end t :initial-value (lit :bool t))))))

(defun fold-equal-cons (state whole pair literal)
  "`(= (cons head tail) '(v . vs))` is `(= head 'v)` and `(= tail 'vs)`, and false against
the empty sequence. A refuted head settles it without a visit to the tail."
  (let ((vals (ast-value literal))
        (false (lit :bool nil))
        (deeper (1+ (fold-spine-depth state))))
    (cond
      ((null vals) false)
      ((zerop (fold-remaining state)) whole)
      (t
       (let* ((head-eq (fold-walk-at-depth state 0 (term `(= ,(second pair) ',(first vals)))))
              (both (if (equal head-eq false)
                        false
                        (fold-walk-at-depth
                         state deeper
                         (bool-and head-eq (fold-walk-at-depth
                                            state deeper (term `(= ,(third pair) ',(rest vals)))))))))
         (keep-or-revert state both whole t))))))

(defun fold-equal-code-apply (state whole application literal)
  "`(= (code-apply f (tuple a0 ... ak)) 'tree)` is `(= f 'op)` and `(= (tuple a0 ... ak)
'(t0 ... tk))` when TREE is the application `(op t0 ... tk)` of an operator of F's sort, and
false for any other tree: an application is built from its operator and arguments alone."
  (declare (ignore whole))
  (destructuring-bind (operator arguments) (rest application)
    (let ((tree (ast-value literal))
          (sort (code-sort (ast-type operator))))
      (if (and (app-p tree) (operator-p (first tree)) (equal sort (operator-type (first tree))))
          (fold-walk state (bool-and (term `(= ,operator ',(first tree)))
                                     (term `(= ,arguments ',(rest tree)))))
          (lit :bool nil)))))

(defun fold-equal-code-subst (state whole subst literal)
  "`(= (code-subst 'pat (tuple b0 ... bk)) 'tree)` matches TREE structurally against PAT,
projecting each substituted variable of PAT to an equality on its corresponding binding Bi
(either as quoted syntax in SUBST's output scope or as a lifted value literal)."
  (destructuring-bind (template bindings) (rest subst)
    (when (and (lit-p template) (app-of-p bindings :tuple))
      (let* ((a-inputs (code-inputs (ast-type template)))
             (out-type (ast-type subst))
             (out-inputs (code-inputs out-type))
             (parts (rest bindings)))
        (labels ((match-subst (pat tree)
                   (cond
                     ((var-p pat)
                      (let* ((pos (position (ast-id pat) a-inputs :key #'car :test #'equal))
                             (input-type (and pos (cdr (nth pos a-inputs))))
                             (b (and pos (nth pos parts)))
                             (b-type (and b (ast-type b))))
                        (cond
                          ((null pos) (lit :bool (if (equal pat tree) t nil)))
                          ((code-subst-code-binding-p b-type out-type input-type)
                           (if (equal input-type (ast-type tree))
                               (term `(= ,b ,(lit (code-type out-inputs input-type) tree)))
                               (lit :bool nil)))
                          ((and (lit-p tree) (equal input-type (ast-type tree)))
                           (term `(= ,b ,(lit input-type (ast-value tree)))))
                          (t (lit :bool nil)))))
                     ((app-p pat)
                      (if (and (app-p tree)
                               (equal (first pat) (first tree))
                               (= (length pat) (length tree)))
                          (reduce #'bool-and
                                  (mapcar #'match-subst (rest pat) (rest tree))
                                  :from-end t :initial-value (lit :bool t))
                          (lit :bool nil)))
                     (t (lit :bool (if (equal pat tree) t nil))))))
          (fold-rewalk state whole (match-subst (ast-value template) (ast-value literal))))))))

(defun fold-equal-if (state whole conditional literal)
  "`(= (if c a b) 'v)` on sequences is `(if c (= a 'v) (= b 'v))`, which exposes each branch."
  (when (seq-type-p (ast-type conditional))
    (destructuring-bind (condition yes no) (rest conditional)
      (fold-rewalk state whole (term `(if ,condition (= ,yes ,literal) (= ,no ,literal))) t))))

(defun call-unfolding (call contract)
  "How CALL can be replaced by a body, as (VALUES inputs body arguments recursive-p): the
definition of a function that has a body, the literal code that `:code-eval` runs, or the
template of a `:code-subst` that it runs, whose bindings then serve as the arguments.
Returns nil when the call has no such body."
  (let* ((op-name (ast-id call))
         (args (rest call))
         (def (and op-name (find-function-definition op-name)))
         (code-arg (first args))
         (eval-args (rest args)))
    (cond
      (def
       (let ((body (function-definition-body def)))
         (when (and body (null (function-definition-oracle-table def)))
           (values (function-definition-inputs def) body args (contains-call-to-p body op-name)))))
      ((not (eq :code-eval op-name)) nil)
      ((lit-p code-arg)
       (values (code-inputs (ast-type code-arg)) (ast-value code-arg) eval-args nil))
      ((and (app-of-p code-arg :code-subst) (lit-p (second code-arg)) (app-of-p (third code-arg) :tuple))
       (let* ((a-inputs (code-inputs (ast-type (second code-arg))))
              (c-type (ast-type code-arg))
              (c-inputs (code-inputs c-type))
              (eval-bindings (bind-inputs c-inputs eval-args))
              (demanded nil) ; inputs of the substituted code that a literal code binding demands
              (sub-args (loop for b in (rest (third code-arg))
                              for (nil . in-type) in a-inputs
                              collect (cond ((not (code-subst-code-binding-p (ast-type b) c-type in-type)) b)
                                            ((lit-p b)
                                             (setf demanded (union demanded (demanded-vars (ast-value b))))
                                             (instantiate (ast-value b) eval-bindings :var))
                                            (t (term `(code-eval ,b ,@eval-args)))))))
         (when (and (unfoldable-parts-p sub-args contract)
                    (loop for (cid . nil) in c-inputs
                          for earg in eval-args
                          always (or (provably-total-p earg) (member cid demanded))))
           (values a-inputs (ast-value (second code-arg)) sub-args nil)))))))

(defun try-unfold-call (state rebuilt)
  "Replace the call REBUILT by its instantiated body where that cannot lose an argument's
error: a non-recursive body outright, a conditional body by the branch its folded condition
selects. Returns REBUILT when the call does not unfold."
  (when (zerop (fold-remaining state)) (return-from try-unfold-call rebuilt))
  (multiple-value-bind (inputs body call-args recursive-p)
      (call-unfolding rebuilt (fold-contract state))
    (unless body (return-from try-unfold-call rebuilt))
    (let ((bindings (bind-inputs inputs call-args))
          ;; A recursive sequence builder: its unfolding is rationed by the spine depth.
          (seq-rec-p (and recursive-p (seq-type-p (ast-type rebuilt))))
          (depth (fold-spine-depth state)))
      (cond
        ((not (app-of-p body :if))
         (if (and (not recursive-p) (non-total-args-preserved-p inputs call-args body))
             (fold-rewalk state rebuilt (instantiate body bindings :var))
             rebuilt))
        ;; Past the first element, leave the call folded when the budget could not finish another.
        ((and seq-rec-p (eq :necessary (fold-contract state)) (plusp depth)
              (< (fold-remaining state)
                 (* 12 (reduce #'+ call-args :key #'syntax-work :initial-value 1))))
         rebuilt)
        (t
         (let* ((folded-cond (fold-walk state (instantiate (second body) bindings :var)))
                (branch (and (plusp (fold-remaining state)) (lit-p folded-cond)
                             (if (ast-value folded-cond) (third body) (fourth body)))))
           (if (and branch
                    (not (and seq-rec-p (app-of-p branch :cons)
                              (fold-max-fibers state) (>= depth (fold-max-fibers state))))
                    (non-total-args-preserved-p inputs call-args branch))
               (fold-rewalk state rebuilt (instantiate branch bindings :var) t)
               rebuilt)))))))

(defun filter-membership (state conjuncts position subject type values)
  "Try each of VALUES, which the conjunct at POSITION allows SUBJECT to take, in the other
CONJUNCTS that mention SUBJECT. Return the conjunction without the refuted values and
without the conjuncts that every value they were tried on satisfies, or nil when that
changes nothing or the budget runs out."
  (let* ((true (lit :bool t))
         (false (lit :bool nil))
         (probe (lit type (first values)))
         (mentions (loop for other in conjuncts
                         for index from 0
                         collect (and (/= index position)
                                      (not (eq other (replace-subexpression other subject probe))))))
         ;; Whether each mentioning conjunct folded to true for every value tried on it.
         (entailed (copy-list mentions))
         (kept nil))
    (dolist (value values)
      (let ((val-lit (lit type value))
            (refuted nil))
        (loop for other in conjuncts
              for mention-p in mentions
              for flag on entailed
              when mention-p
                do (let ((res (fold-walk state (replace-subexpression other subject val-lit))))
                     (cond ((zerop (fold-remaining state)) (return-from filter-membership nil))
                           ((equal res false) (setf refuted t) (return))
                           ((not (equal res true)) (setf (first flag) nil)))))
        (unless refuted (push value kept))))
    (setf kept (nreverse kept))
    (cond
      ((and (= (length kept) (length values)) (notany #'identity entailed)) nil)
      ((null kept) false)
      (t (fold-walk state
                    (reduce #'bool-and
                            (loop for item in conjuncts
                                  for entailed-p in entailed
                                  for index from 0
                                  unless entailed-p
                                    collect (cond ((/= index position) item)
                                                  ((rest kept) (term `(member ,subject ',kept)))
                                                  (t (term `(= ,subject ',(first kept))))))
                            :from-end t))))))

(defun simplify-conjunction (state whole condition yes)
  "Simplify WHOLE, the total conjunction of CONDITION and YES, by the first of these that
applies: substitute the equalities of YES into CONDITION, narrow a finite membership against
the conjuncts that mention its term, or reassemble tuple coordinates."
  (let ((conjuncts (append (extract-conjuncts condition) (extract-conjuncts yes)))
        (substituted (propagate-conjunct-equalities (extract-conjuncts yes) condition)))
    (cond
      ((not (equal substituted condition)) (fold-walk state (bool-and substituted yes)))
      ((loop for c in conjuncts
             for position from 0
             thereis (multiple-value-bind (subject type values) (extract-term-membership c)
                       (and subject values
                            (filter-membership state conjuncts position subject type values)))))
      ((try-reassemble-tuple-coordinates conjuncts))
      (t whole))))

(defun fold-constants (expression &key ledger (budget 10000) (contract :equivalent) max-fibers)
  "Simplify EXPRESSION, preserving its value and its definedness. One budget covers the
complete traversal. An error or cutoff leaves its expression intact. No table inversion is
built in. Under the :necessary contract a Boolean EXPRESSION may instead be weakened, and an
integer MAX-FIBERS then caps recursive sequence unfolding along any `:cons` spine at that
many elements while retaining all already-unfolded prefix conjuncts."
  (assert (member contract '(:equivalent :necessary)))
  (assert (and (integerp budget) (not (minusp budget))))
  (when (eq contract :necessary) (assert (eq :bool (ast-type expression))))
  (fold-walk (make-fold-state :remaining budget :ledger ledger :contract contract
                              :max-fibers max-fibers)
             expression))
