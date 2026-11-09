(in-package #:lisploop)

;;; Module 4: frame.lisp
;;; Frames, S-expression requirements, pullbacks, requirement conjunction,
;;; conflict detection, support frames, partitions, and quotients.

(defstruct (row (:constructor %make-row))
  key
  known
  requirement)

(defstruct (frame (:constructor %make-frame))
  schema
  rows
  pairs
  anchors)

(defun snapshot-frame (frame)
  "Own the problem's mutable data before starting a resumable computation."
  (let ((schema (copy-schema (frame-schema frame))))
    (setf (schema-domain schema) (copy-tree (schema-domain schema))
          (schema-inputs schema) (copy-tree (schema-inputs schema))
          (schema-target schema) (copy-tree (schema-target schema)))
    (make-frame schema
                (mapcar (lambda (row)
                          (make-row :key (copy-tree (row-key row))
                                    :known (copy-tree (row-known row))
                                    :requirement (copy-tree (row-requirement row))))
                        (frame-rows frame))
                :pairs (frame-pairs frame) :anchors (frame-anchors frame))))

(defun extract-slot-constraint (conjunct)
  "If CONJUNCT is `(= (at x0 'idx) 'v)` or `(member (at x0 'idx) '(v1 ... vm))` on tuple var 0,
return (VALUES tuple-type idx allowed-values)."
  (labels ((var0-slot (term)
             (multiple-value-bind (base tuple-type idx) (tuple-slot-term term)
               (when (and base (var-p base) (zerop (ast-id base)))
                 (values tuple-type idx)))))
    (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct)
      (declare (ignore term-type))
      (if term
          (multiple-value-bind (ttype idx) (var0-slot term)
            (when ttype
              (values ttype idx (list (ast-value lit-node)))))
          (when (and (app-p conjunct) (eq :member (operator-name (first conjunct)))
                     (lit-p (third conjunct)))
            (multiple-value-bind (ttype idx) (var0-slot (second conjunct))
              (when ttype
                (values ttype idx (copy-tree (ast-value (third conjunct)))))))))))

(defun cartesian-product-lists (lists)
  (if (null lists)
      (list nil)
      (let ((rest-prod (cartesian-product-lists (rest lists))))
        (loop for item in (first lists)
              append (mapcar (lambda (tail) (cons item tail)) rest-prod)))))

(defun extract-allowed-values (expression)
  "Extract explicit finite values from `(= x0 'v)`, `(member x0 '(v1 ...))`, `'nil`,
or a complete conjunction of coordinate constraints on `(at x0 'i)`; otherwise return :UNKNOWN."
  (multiple-value-bind (term term-type lit-node) (match-literal-equality expression)
    (declare (ignore term-type))
    (cond
      ((and (lit-p expression) (eq :bool (ast-type expression)) (null (ast-value expression)))
       nil)
      ((and term (var-p term) (zerop (ast-id term)))
       (list (ast-value lit-node)))
      ((and (app-p expression) (eq :member (operator-name (first expression))))
       (let ((lhs (second expression))
             (rhs (third expression)))
         (if (and (var-p lhs) (zerop (ast-id lhs)) (lit-p rhs))
             (copy-tree (ast-value rhs))
             :unknown)))
      ((and (app-p expression) (eq :if (operator-name (first expression))))
       (let ((conjuncts (extract-conjuncts expression))
             (tuple-type nil)
             (slots nil))
         (dolist (c conjuncts)
           (multiple-value-bind (ttype idx vals) (extract-slot-constraint c)
             (unless ttype
               (return-from extract-allowed-values :unknown))
             (unless tuple-type
               (setf tuple-type ttype
                     slots (make-array (length (rest ttype)) :initial-element :unbound)))
             (unless (equal tuple-type ttype)
               (return-from extract-allowed-values :unknown))
             (setf (aref slots idx)
                   (if (eq :unbound (aref slots idx))
                       vals
                       (intersection (aref slots idx) vals :test #'equal)))))
         (if (and slots (loop for s across slots never (eq s :unbound)))
             (cartesian-product-lists (coerce slots 'list))
             :unknown)))
      (t :unknown))))

(defun singleton-requirement (type value)
  (assert (value-p value type))
  (app (op := type) (var 0 type) (lit type value)))

(defun set-requirement (type values)
  "An explicit finite set of whole values: tuples are never split into marginal sets."
  (assert (every (lambda (v) (value-p v type)) values))
  (app (op :member type) (var 0 type) (lit (sequence-type type) (copy-tree values))))

(defun make-row (&key key known requirement)
  (assert requirement () "make-row requires :requirement")
  (%make-row :key key :known known :requirement requirement))

(defun make-frame (schema rows &key pairs anchors)
  (assert (valid-type-p (schema-target schema)))
  (assert (valid-inputs-p (schema-inputs schema)))
  (assert (= (length rows) (length (remove-duplicates rows :key #'row-key :test #'equal))))
  (dolist (row rows)
    (assert (= (length (row-known row)) (length (schema-inputs schema))))
    (assert (every (lambda (value spec) (or (eq value :unresolved) (value-p value (cdr spec))))
                   (row-known row) (schema-inputs schema)))
    (assert (eq :bool (expression-type (row-requirement row)
                                       (list (cons 0 (schema-target schema)))))))
  (%make-frame :schema schema :rows (copy-list rows)
               :pairs (copy-tree pairs) :anchors (copy-tree anchors)))

(defun find-var-type (expression &optional (id 0))
  (cond
    ((and (var-p expression) (= id (ast-id expression)))
     (ast-type expression))
    ((app-p expression)
     (some (lambda (child) (find-var-type child id)) (rest expression)))
    (t nil)))

(defun check-requirement (requirement value &key (budget 1000000) ledger type)
  (let ((target-type (or type
                         (find-var-type requirement 0)
                         (when (and (app-p requirement)
                                    (member (operator-name (first requirement)) '(:= :member)))
                           (operator-operand-type (first requirement)))
                         :int)))
    (evaluate requirement (list (cons 0 target-type))
              (list value) :budget budget :ledger ledger)))

(defun conjoin-requirements (req1 req2 target-type &key ledger (budget 10000))
  "Conjoin two row requirements over variable 0 of TARGET-TYPE and fold closed subtrees."
  (let ((schema (make-schema :inputs (list (cons 0 target-type)) :target :bool)))
    (fold-constants (bool-and req1 req2) schema :ledger ledger :budget budget)))

(defstruct (frame-conflict (:predicate frame-conflict-struct-p))
  kind
  keys
  known
  expression)

(defun unsatisfiable-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (null (ast-value expr))))

(defun unconstrained-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (eq t (ast-value expr))))

(defun frame-constrained-row-count (frame)
  "Count rows in FRAME whose requirement is not trivially `'t`."
  (count-if-not (lambda (row) (unconstrained-requirement-p (row-requirement row)))
                (frame-rows frame)))

(defun frame-min-resolved-rows (frame)
  "Minimum number of constrained rows that must resolve (not be :unresolved) for a candidate to be accepted."
  (min 2 (frame-constrained-row-count frame)))

(defun unconstrained-frame (frame target-type &key domain)
  "Clone FRAME's rows and inputs with target TARGET-TYPE and unconstrained `'t` requirements."
  (let ((schema (frame-schema frame)))
    (make-frame (make-schema :domain (or domain (schema-domain schema))
                             :inputs (copy-tree (schema-inputs schema))
                             :target target-type)
                (loop for row in (frame-rows frame)
                      collect (make-row :key (copy-tree (row-key row))
                                        :known (copy-tree (row-known row))
                                        :requirement (lit :bool t))))))

(defun frame-conflict-p (frame &key ledger (budget 10000))
  "Detect whether any row requirement in FRAME folds to `nil` or whether rows
sharing identical known inputs have mutually incompatible requirements.
Returns (VALUES conflict folded-frame), where FOLDED-FRAME is a fresh frame
carrying the folded row requirements when no conflict is detected."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (checker-schema (make-schema :inputs (list (cons 0 target-type)) :target :bool))
         (by-known (make-hash-table :test #'equal))
         (folded-rows nil))
    (dolist (row (frame-rows frame))
      (let* ((req (row-requirement row))
             (folded (fold-constants req checker-schema :ledger ledger :budget budget)))
        (when (unsatisfiable-requirement-p folded)
          (return-from frame-conflict-p
            (values (make-frame-conflict :kind :unsatisfiable-row
                                         :keys (list (row-key row))
                                         :known (row-known row)
                                         :expression folded)
                    nil)))
        (push (make-row :key (row-key row)
                        :known (row-known row)
                        :requirement folded)
              folded-rows)
        (unless (member :unresolved (row-known row))
          (let ((existing (gethash (row-known row) by-known)))
            (if existing
                (let* ((prev-keys (first existing))
                       (prev-req (second existing))
                       (joint (conjoin-requirements prev-req folded target-type
                                                    :ledger ledger :budget budget)))
                  (when (unsatisfiable-requirement-p joint)
                    (return-from frame-conflict-p
                      (values (make-frame-conflict :kind :incompatible-rows
                                                   :keys (append (reverse prev-keys) (list (row-key row)))
                                                   :known (row-known row)
                                                   :expression joint)
                              nil)))
                  (setf (gethash (row-known row) by-known)
                        (list (cons (row-key row) prev-keys) joint)))
                (setf (gethash (row-known row) by-known)
                      (list (list (row-key row)) folded)))))))
    (values nil
            (make-frame (copy-schema schema)
                        (nreverse folded-rows)
                        :pairs (frame-pairs frame)
                        :anchors (frame-anchors frame)))))

(defun orient-observations (types records input-columns target-columns &key lookup-p ledger)
  "Re-use witnessed (key . values) records; orientation performs no simulation."
  (assert (and target-columns
               (null (intersection input-columns target-columns))))
  (let* ((target (if (rest target-columns)
                     (apply #'tuple-type (mapcar (lambda (i) (nth i types)) target-columns))
                     (nth (first target-columns) types)))
         (schema (make-schema :inputs (mapcar (lambda (i) (cons i (nth i types))) input-columns)
                              :target target :lookup-p lookup-p)))
    (make-frame
     schema
     (loop for (key . values) in records collect
       (progn
         (assert (= (length values) (length types)))
         (assert (every #'value-p values types))
         (charge ledger :orientation (+ 1 (loop for value in values for type in types sum (value-work value type))))
         (make-row :key key :known (mapcar (lambda (i) (nth i values)) input-columns)
                   :requirement (set-requirement
                                 target (list (if (rest target-columns)
                                                  (mapcar (lambda (i) (nth i values)) target-columns)
                                                  (nth (first target-columns) values))))))))))

(defun transition-probes (frame output-type &optional ledger)
  "Reorient recorded singleton state transitions into before/after input probes.
The original frame remains available; this conversion executes no transition."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (requirement (lit :bool t))
         (rows nil) (pairs nil))
    (assert (equal (schema-target schema) (apply #'tuple-type (mapcar #'cdr inputs))))
    (dolist (row (frame-rows frame))
      (let ((targets (extract-allowed-values (row-requirement row)))
            (before-key (list (row-key row) :before))
            (after-key (list (row-key row) :after)))
        (assert (and (listp targets) (= (length targets) 1)) ()
                "Transition probes require a recorded singleton successor")
        (push (make-row :key before-key :known (copy-tree (row-known row))
                        :requirement requirement) rows)
        (push (make-row :key after-key :known (copy-tree (first targets))
                        :requirement requirement) rows)
        (push (list before-key after-key) pairs)
        (charge ledger :orientation
                (+ 2 (loop for spec in inputs for before in (row-known row)
                           for after in (first targets)
                           sum (+ (value-work before (cdr spec)) (value-work after (cdr spec))))))))
    (values (make-frame (make-schema :inputs (copy-tree inputs) :target output-type)
                        (nreverse rows) :pairs (nreverse (copy-tree pairs)))
            (nreverse pairs))))

(defun lookup-model (frame &optional ledger)
  "Package actual available witnesses. Reject unavailable or contradictory tables."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (key-type (apply #'tuple-type (mapcar #'cdr inputs)))
         (entry-type (tuple-type key-type (schema-target schema)))
         (groups nil))
    (assert (schema-lookup-p schema))
    (dolist (row (frame-rows frame))
      (let* ((values (extract-allowed-values (row-requirement row)))
             (old (assoc (row-known row) groups :test #'equal)))
        (when (eq values :unknown) (error "No explicit witnesses for lookup"))
        (charge ledger :baseline (+ 1 (loop for value in values sum (value-work value (schema-target schema)))))
        (if old
            (setf (cdr old) (intersection (cdr old) values :test #'equal))
            (push (cons (row-known row) (copy-list values)) groups))))
    (assert (every #'cdr groups) () "Inconsistent requirements for a lookup key")
    (let ((model (app (op :lookup entry-type)
                      (apply #'app (op :tuple key-type)
                             (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs))
                      (lit (sequence-type entry-type)
                           (mapcar (lambda (group) (list (car group) (second group)))
                                   (reverse groups))))))
      (charge ledger :baseline (syntax-work model))
      model)))

(defun frame-oracle-table (frame &optional ledger)
  "Extract an input-output alist ((known-args . target-val) ...) from singleton rows of FRAME."
  (let ((target-type (schema-target (frame-schema frame)))
        (table nil))
    (dolist (row (frame-rows frame) (nreverse table))
      (unless (member :unresolved (row-known row))
        (let ((allowed (extract-allowed-values (row-requirement row))))
          (when (and (consp allowed) (= 1 (length allowed))
                     (not (assoc (row-known row) table :test #'equal)))
            (charge ledger :orientation (1+ (value-work (first allowed) target-type)))
            (push (cons (copy-tree (row-known row)) (copy-tree (first allowed))) table)))))))

(defun evaluate-row-bindings (bindings inputs known &key ledger (error-p t)
                                                         allow-unresolved-p default-on-failure-p)
  "Evaluate BINDINGS ((id . expr) ...) on KNOWN under INPUTS.
When ALLOW-UNRESOLVED-P is true, an :unresolved evaluation binds :unresolved.
When DEFAULT-ON-FAILURE-P is true, a non-:value evaluation substitutes (default-value-for-type type).
Otherwise, when ERROR-P is true, signal an error if any binding does not produce :value, or return :error."
  (mapcar (lambda (binding)
            (let ((run (evaluate (cdr binding) inputs known :ledger ledger)))
              (cond
                ((eq (evaluation-status run) :value)
                 (evaluation-value run))
                (default-on-failure-p
                 (default-value-for-type (expression-type (cdr binding) inputs)))
                ((and allow-unresolved-p (eq (evaluation-status run) :unresolved))
                 :unresolved)
                (error-p
                 (error "Context binding did not finish: ~S" run))
                (t
                 (return-from evaluate-row-bindings :error)))))
          bindings))

(defun pullback-frame (parent decoder child-id child-type bindings &optional ledger)
  "B(z)=A(d(c,z)). BINDINGS is an alist of child input IDs to parent expressions.
The checker closes over encoded observations; the child receives only computed
bindings. No inverse values are enumerated."
  (let* ((schema (frame-schema parent))
         (inputs (schema-inputs schema))
         (decoder-inputs (acons child-id child-type inputs))
         (child-inputs (mapcar (lambda (b) (cons (car b) (expression-type (cdr b) inputs)))
                               bindings))
         (partial-bindings-p (some (lambda (b) (not (provably-total-p (cdr b)))) bindings))
         (multi-row-p (> (length (frame-rows parent)) 1))
         (decoder-free-vars (ast-meta-free-vars (ensure-ast-meta decoder)))
         (checker-schema (make-schema :inputs (list (cons 0 child-type)) :target :bool)))
    (assert (not (assoc child-id inputs)))
    (assert (equal (schema-target schema) (expression-type decoder decoder-inputs)))
    (make-frame
     (make-schema :inputs child-inputs :target child-type)
     (loop for row in (frame-rows parent) collect
       (let* ((unresolved-decoder-p
                (loop for (id . nil) in inputs
                      for val in (row-known row)
                      thereis (and (eq val :unresolved)
                                   (member id decoder-free-vars :test #'eql))))
              (constants (literal-bindings inputs (row-known row)))
              (closed-decoder (unless unresolved-decoder-p
                                (instantiate decoder
                                             (acons child-id (var 0 child-type) constants) :var)))
              (predicate (if unresolved-decoder-p
                             (lit :bool t)
                             (instantiate (row-requirement row)
                                          (list (cons 0 closed-decoder)) :var)))
              (dead-row-p (and multi-row-p
                               (or (unconstrained-requirement-p (row-requirement row))
                                   (and partial-bindings-p
                                        (unconstrained-requirement-p
                                         (fold-constants predicate checker-schema))))))
              (known (evaluate-row-bindings bindings inputs (row-known row)
                                            :ledger ledger
                                            :allow-unresolved-p t
                                            :default-on-failure-p dead-row-p)))
         (charge ledger :pullback (syntax-work predicate))
         (make-row :key (row-key row) :known known
                   :requirement predicate)))
     :pairs (frame-pairs parent)
     :anchors (frame-anchors parent))))

(defun compose-model (decoder child-id child-model bindings &optional ledger)
  "Inline the context and child; the resulting ordinary AST pays for duplication."
  (let ((model (instantiate decoder
                            (list (cons child-id (instantiate child-model bindings :var))) :var)))
    (charge ledger :composition (syntax-work model))
    model))

(defun default-value-for-type (type)
  "Construct a canonical witness value belonging to TYPE."
  (case type
    (:int 0)
    (:bool nil)
    (otherwise
     (ecase (first type)
       (:gf 0)
       (:tuple (mapcar #'default-value-for-type (rest type)))
       (:seq nil)
       (:code (lit (code-sort type) (default-value-for-type (code-sort type))))))))

(defun collect-code-eval-calls (expr code-var)
  "Return (VALUES ground-calls non-ground-p) for all (:code-eval CODE-VAR ...) subterms in EXPR."
  (let ((ground nil)
        (non-ground-p nil))
    (labels ((walk (node)
               (when (app-p node)
                 (mapc #'walk (rest node))
                 (when (and (operator-p (first node))
                            (eq :code-eval (operator-name (first node)))
                            (equal (second node) code-var))
                   (if (every #'lit-p (cddr node))
                       (pushnew node ground :test #'equal)
                       (setf non-ground-p t))))))
      (walk expr)
      (values (nreverse ground) non-ground-p))))

(defun extract-code-eval-equation (conjunct code-var)
  "If CONJUNCT is ready to lift with a single ground call G = (:code-eval CODE-VAR 'a0 ... 'ak-1)
and equates G with a literal 'val, return (VALUES G 'val)."
  (multiple-value-bind (ground non-ground-p) (collect-code-eval-calls conjunct code-var)
    (when (and (not non-ground-p) (null (rest ground)) (first ground))
      (if (and (equal conjunct (first ground)) (eq :bool (ast-type conjunct)))
          (values (first ground) (lit :bool t))
          (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct)
            (declare (ignore term-type))
            (when (equal term (first ground))
              (values (first ground) lit-node)))))))

(defun congruence-close-code-evals (row-reqs extra-knowns code-var checker-schema
                                    &key ledger (budget 10000))
  "Iteratively propagate ground equations `(= (:code-eval CODE-VAR 'a0 ...) 'val)` across
non-decoupled conjuncts sharing identical EXTRA-KNOWNS, folding after each substitution pass."
  (let ((reqs (copy-list row-reqs))
        (known-evals (make-hash-table :test #'equal)))
    (loop
      (let ((changed nil))
        (loop for req in reqs
              for extra in extra-knowns
              do (dolist (c (extract-conjuncts req))
                   (multiple-value-bind (call val-lit) (extract-code-eval-equation c code-var)
                     (when call
                       (let ((key (cons extra call)))
                         (unless (gethash key known-evals)
                           (setf (gethash key known-evals) val-lit)))))))
        (setf reqs
              (loop for req in reqs
                    for extra in extra-knowns
                    collect (let ((row-changed nil)
                                  (new-conjuncts nil))
                              (dolist (c (extract-conjuncts req))
                                (multiple-value-bind (ground non-ground-p)
                                    (collect-code-eval-calls c code-var)
                                  (if (or non-ground-p (> (length ground) 1))
                                      (let ((sub c))
                                        (dolist (g-call ground)
                                          (let ((val-lit (gethash (cons extra g-call) known-evals)))
                                            (when val-lit
                                              (charge ledger :pullback (syntax-work val-lit))
                                              (setf sub (replace-subexpression sub g-call val-lit)))))
                                        (if (equal sub c)
                                            (push c new-conjuncts)
                                            (progn
                                              (setf row-changed t changed t)
                                              (push (fold-constants sub checker-schema
                                                                    :ledger ledger :budget budget)
                                                    new-conjuncts))))
                                      (push c new-conjuncts))))
                              (if row-changed
                                  (fold-constants (reduce #'bool-and (nreverse new-conjuncts)
                                                          :from-end t :initial-value (lit :bool t))
                                                  checker-schema :ledger ledger :budget budget)
                                  req))))
        (unless changed (return reqs))))))

(defun extract-outermost-code-eval (expr code-var)
  "Find a unique outermost (:code-eval CODE-VAR ...) subterm in EXPR, or NIL if zero or multiple exist."
  (let ((outer nil)
        (multiple-p nil))
    (labels ((walk (node)
               (when (and (not multiple-p) (app-p node))
                 (if (and (operator-p (first node))
                          (eq :code-eval (operator-name (first node)))
                          (equal (second node) code-var))
                     (if (and outer (not (equal outer node)))
                         (setf multiple-p t)
                         (setf outer node))
                     (mapc #'walk (rest node))))))
      (walk expr)
      (unless multiple-p outer))))

(defparameter *max-active-lifted-rows* 16
  "Maximum number of active fiber rows retained by LIFT-FRAME before holding remaining rows in reserve for CEGAR.")

(defun flatten-lifted-conjuncts (expr code-var)
  "Extract atomic conjuncts from EXPR, resolving any ambiguous (:if (:code-eval CODE-VAR ...) yes no)
subsequence branch deterministically via its first-match (YES) branch."
  (let ((raw (extract-conjuncts expr))
        (out nil))
    (labels ((expand (c)
               (if (and (app-p c)
                        (operator-p (first c))
                        (eq :if (operator-name (first c)))
                        (not (and (lit-p (fourth c)) (null (ast-value (fourth c)))))
                        (app-p (second c))
                        (operator-p (first (second c)))
                        (eq :code-eval (operator-name (first (second c))))
                        (equal (second (second c)) code-var))
                   (if (not (unsatisfiable-requirement-p (third c)))
                       (progn
                         (push (second c) out)
                         (mapc #'expand (extract-conjuncts (third c))))
                       (progn
                         (push (app (op := :bool) (second c) (lit :bool nil)) out)
                         (mapc #'expand (extract-conjuncts (fourth c)))))
                   (push c out))))
      (mapc #'expand raw)
      (nreverse out))))

(defun select-active-fiber-rows (rows max-active-rows)
  "When ROWS exceeds MAX-ACTIVE-ROWS, partition ROWS into (VALUES active-rows reserve-rows),
retaining all unsatisfiable rows, boundary occurrences per parent row, and diverse input values."
  (if (or (null max-active-rows) (<= (length rows) max-active-rows))
      (values rows nil)
      (let ((selected (make-hash-table :test #'eq))
            (by-parent (make-hash-table :test #'equal))
            (seen-first-arg (make-hash-table :test #'equal))
            (count 0))
        (flet ((pick (r)
                 (unless (gethash r selected)
                   (setf (gethash r selected) t)
                   (incf count))))
          ;; 1. Always keep unsatisfiable rows so conflicts are detected immediately
          (dolist (r rows)
            (when (unsatisfiable-requirement-p (row-requirement r))
              (pick r)))
          ;; 2. Group by parent row key and keep first + last occurrence of each parent row
          (dolist (r rows)
            (let ((pkey (if (consp (row-key r)) (first (row-key r)) (row-key r))))
              (push r (gethash pkey by-parent))))
          (maphash (lambda (pkey group)
                     (declare (ignore pkey))
                     (let ((ordered (reverse group)))
                       (when (< count max-active-rows)
                         (pick (first ordered)))
                       (when (and (< count max-active-rows) (rest ordered))
                         (pick (car (last ordered))))))
                   by-parent)
          ;; 3. Keep rows with distinct first known argument (covering extrema/diversity)
          (dolist (r rows)
            (when (and (< count max-active-rows) (row-known r))
              (let ((k0 (first (row-known r))))
                (unless (gethash k0 seen-first-arg)
                  (setf (gethash k0 seen-first-arg) t)
                  (pick r)))))
          ;; 4. Fill remaining slots up to MAX-ACTIVE-ROWS in row order
          (dolist (r rows)
            (when (< count max-active-rows)
              (pick r)))
          (let ((active nil)
                (reserve nil))
            (dolist (r rows (values (nreverse active) (nreverse reserve)))
              (if (gethash r selected)
                  (push r active)
                  (push r reserve))))))))

(defun lift-frame (parent decoder child-id child-type &optional bindings ledger (budget 10000)
                                                      (max-active-rows *max-active-lifted-rows*))
  "Lift a parent frame through a higher-order DECODER parameterized by CHILD-ID of (:code inputs ret)
into a 1-to-many child frame over the code parameter's inputs (plus any extra parent BINDINGS).
Unfolds DECODER on each parent row, runs cross-row congruence closure on ground :code-eval calls,
and emits one child row per distinct ground call requirement.
Returns (VALUES lifted-frame coupled-conjuncts reserve-rows)."
  (assert (and (code-type-p child-type) (not (function-sort-p (code-sort child-type)))))
  (let* ((raw (pullback-frame parent decoder child-id child-type bindings ledger))
         (code-in (code-inputs child-type))
         (ret (code-sort child-type))
         (extra-in (schema-inputs (frame-schema raw)))
         (child-inputs (append (copy-tree code-in) (copy-tree extra-in)))
         (code-var (var 0 child-type))
         (ret-var (var 0 ret))
         (checker-schema (make-schema :inputs (list (cons 0 child-type)) :target :bool))
         (ret-checker-schema (make-schema :inputs (list (cons 0 ret)) :target :bool))
         (extra-knowns (mapcar #'row-known (frame-rows raw)))
         (initial-reqs (mapcar (lambda (row)
                                 (fold-constants (row-requirement row) checker-schema
                                                 :ledger ledger :budget budget))
                               (frame-rows raw)))
         (closed-reqs (congruence-close-code-evals initial-reqs extra-knowns code-var checker-schema
                                                   :ledger ledger :budget budget))
         (seen-known-req (make-hash-table :test #'equal))
         (lifted-rows nil)
         (coupled nil)
         (coupled-details nil))
    (assert (null (intersection (mapcar #'car code-in) (mapcar #'car extra-in))))
    (loop for parent-row in (frame-rows raw)
          for req in closed-reqs
          for extra in extra-knowns
          do (if (unsatisfiable-requirement-p req)
                 (push (make-row :key (list (row-key parent-row) :unsat)
                                 :known (append (mapcar (lambda (s) (default-value-for-type (cdr s))) code-in)
                                                (copy-tree extra))
                                 :requirement (lit :bool nil))
                       lifted-rows)
                 (loop for c in (flatten-lifted-conjuncts req code-var)
                       for occ-idx from 0
                       do (multiple-value-bind (ground non-ground-p) (collect-code-eval-calls c code-var)
                            (cond
                              ((and (not non-ground-p) (= 1 (length ground)))
                               (let* ((call (first ground))
                                      (call-known (mapcar #'ast-value (cddr call)))
                                      (known (append (copy-tree call-known) (copy-tree extra)))
                                      (raw-lifted (if (and (equal c call) (eq :bool ret))
                                                      (app (op := :bool) ret-var (lit :bool t))
                                                      (replace-subexpression c call ret-var)))
                                      (lifted-req (fold-constants raw-lifted
                                                                  ret-checker-schema
                                                                  :ledger ledger :budget budget))
                                      (dedup-key (list known lifted-req)))
                                 (unless (gethash dedup-key seen-known-req)
                                   (setf (gethash dedup-key seen-known-req) t)
                                   (charge ledger :pullback (syntax-work lifted-req))
                                   (push (make-row :key (list (row-key parent-row) occ-idx)
                                                   :known known
                                                   :requirement lifted-req)
                                         lifted-rows))))
                              ((or non-ground-p (> (length ground) 1))
                               (push (cons (row-key parent-row) c) coupled)
                               (push (list (row-key parent-row) occ-idx extra c) coupled-details))
                              ((unsatisfiable-requirement-p c)
                               (push (make-row :key (list (row-key parent-row) occ-idx)
                                               :known (append (mapcar (lambda (s) (default-value-for-type (cdr s))) code-in)
                                                              (copy-tree extra))
                                               :requirement (lit :bool nil))
                                     lifted-rows)))))))
    (when (and coupled (< (length lifted-rows) 2))
      (dolist (detail (nreverse coupled-details))
        (destructuring-bind (p-key occ-idx extra c) detail
          (let* ((outer (extract-outermost-code-eval c code-var))
                 (replaced (when outer (replace-subexpression c outer ret-var)))
                 (clean-p (and replaced
                               (multiple-value-bind (g ng) (collect-code-eval-calls replaced code-var)
                                 (and (null g) (not ng)))))
                 (known (if clean-p
                            (append (mapcar (lambda (a) (if (lit-p a) (ast-value a) :unresolved))
                                            (cddr outer))
                                    (copy-tree extra))
                            (mapcar (lambda (s) (declare (ignore s)) :unresolved) child-inputs)))
                 (lifted-req (if clean-p
                                 (fold-constants replaced ret-checker-schema
                                                 :ledger ledger :budget budget)
                                 (app (op := ret) ret-var (lit ret (default-value-for-type ret))))))
            (charge ledger :pullback (syntax-work lifted-req))
            (push (make-row :key (list p-key :coupled occ-idx)
                            :known known
                            :requirement lifted-req)
                  lifted-rows)))))
    (unless lifted-rows
      (push (make-row :key :vacuous
                      :known (mapcar (lambda (s) (default-value-for-type (cdr s))) child-inputs)
                      :requirement (lit :bool t))
            lifted-rows))
    (multiple-value-bind (active-rows reserve-rows)
        (select-active-fiber-rows (nreverse lifted-rows) max-active-rows)
      (values (make-frame (make-schema :inputs child-inputs :target ret)
                          active-rows)
              (nreverse coupled)
              reserve-rows))))

(defun compose-lifted-model (decoder child-id child-type child-model &optional bindings ledger)
  "Package a synthesized CHILD-MODEL of type (code-sort CHILD-TYPE) into a :code expression
of type CHILD-TYPE (using :code-subst when CHILD-MODEL references outer BINDINGS) and
inline it for CHILD-ID in DECODER."
  (assert (and (code-type-p child-type) (not (function-sort-p (code-sort child-type)))))
  (let* ((code-in (code-inputs child-type))
         (ret (code-sort child-type))
         (free (free-vars child-model))
         (used-ids (when bindings
                     (loop for (bid . nil) in bindings
                           when (member bid free :test #'eql)
                             collect bid)))
         (code-expr
           (if (null used-ids)
               (lit child-type child-model)
               (let* ((max-used-id (reduce #'max used-ids))
                      (active-bindings (remove-if (lambda (b) (> (car b) max-used-id)) bindings))
                      (extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) active-bindings))
                      (full-code-type (code-type (append code-in extra-in) ret))
                      (tuple-args (append (mapcar (lambda (s)
                                                    (lit (code-type code-in (cdr s))
                                                         (var (car s) (cdr s))))
                                                  code-in)
                                          (mapcar #'cdr active-bindings)))
                      (subst-tuple-type (apply #'tuple-type (mapcar #'ast-type tuple-args))))
                 (app (op :code-subst (tuple-type full-code-type subst-tuple-type child-type))
                      (lit full-code-type child-model)
                      (apply #'app (op :tuple subst-tuple-type) tuple-args)))))
         (model (instantiate decoder (list (cons child-id code-expr)) :var)))
    (charge ledger :composition (syntax-work model))
    model))

(defun conserved-quantity-frame (obs-frame target-id conserved-expr constant-value &optional ledger)
  "Reorient a conserved observation C(u, T) = CONSTANT-VALUE on OBS-FRAME into a pulled-back
frame solving for column TARGET-ID in terms of the remaining columns u.
Returns (VALUES pulled-back-frame const-frame)."
  (let* ((schema (frame-schema obs-frame))
         (inputs (schema-inputs schema))
         (target-pos (position target-id inputs :key #'car))
         (target-type (cdr (nth target-pos inputs)))
         (u-inputs (remove target-id inputs :key #'car))
         (c-type (expression-type conserved-expr inputs))
         (const-req (singleton-requirement c-type constant-value))
         (const-frame
           (make-frame (make-schema :domain (schema-domain schema) :inputs u-inputs :target c-type)
                       (loop for row in (frame-rows obs-frame)
                             collect (make-row :key (row-key row)
                                               :known (loop for val in (row-known row)
                                                            for idx from 0
                                                            unless (= idx target-pos) collect val)
                                               :requirement const-req))
                       :pairs (frame-pairs obs-frame)
                       :anchors (frame-anchors obs-frame))))
    (values (pullback-frame const-frame conserved-expr target-id target-type
                            (identity-bindings u-inputs) ledger)
            const-frame)))

(defun context-label-frame (parent labels &key bindings (label-type :int) (lookup-p t) ledger)
  "Project PARENT rows through BINDINGS (an alist of (child-input-id . parent-expr),
defaulting to all parent inputs) onto singleton requirements for LABELS of type LABEL-TYPE.
Charges evaluation of each context binding expression on LEDGER."
  (let* ((parent-schema (frame-schema parent))
         (parent-inputs (schema-inputs parent-schema))
         (parent-rows (frame-rows parent))
         (effective-bindings (or bindings (identity-bindings parent-inputs)))
         (child-inputs (mapcar (lambda (b)
                                 (cons (car b) (expression-type (cdr b) parent-inputs)))
                               effective-bindings)))
    (assert (= (length labels) (length parent-rows)) ()
            "Label count (~D) must match parent row count (~D)"
            (length labels) (length parent-rows))
    (make-frame
     (make-schema :domain (if (eq label-type :bool) (schema-domain parent-schema) label-type)
                  :inputs child-inputs
                  :target label-type
                  :lookup-p lookup-p)
     (loop for row in parent-rows
           for label in labels
           collect (let* ((known (evaluate-row-bindings effective-bindings parent-inputs
                                                        (row-known row) :ledger ledger))
                          (req (singleton-requirement label-type label)))
                     (charge ledger :context-frame (syntax-work req))
                     (make-row :key (copy-tree (row-key row))
                               :known known
                               :requirement req)))
     :pairs (frame-pairs parent)
     :anchors (frame-anchors parent))))

(defun project-frame-rows (frame bindings &optional ledger)
  "Project FRAME's `row-known` values through BINDINGS (an alist of (child-id . parent-expr))."
  (if (null bindings)
      frame
      (let* ((schema (frame-schema frame))
             (parent-inputs (schema-inputs schema))
             (child-inputs (mapcar (lambda (b)
                                     (cons (car b) (expression-type (cdr b) parent-inputs)))
                                   bindings)))
        (make-frame
         (make-schema :domain (schema-domain schema)
                      :inputs child-inputs
                      :target (schema-target schema)
                      :lookup-p (schema-lookup-p schema))
         (loop for row in (frame-rows frame)
               collect (let ((known (evaluate-row-bindings bindings parent-inputs
                                                           (row-known row) :ledger ledger)))
                         (charge ledger :orientation (length known))
                         (make-row :key (copy-tree (row-key row))
                                   :known known
                                   :requirement (copy-tree (row-requirement row)))))
         :pairs (frame-pairs frame)
         :anchors (frame-anchors frame)))))

(defun shuffle-frame-rows (frame permutation &optional ledger)
  "Permute the physical storage order of FRAME's rows according to PERMUTATION
(a bijection of 0..N-1) while preserving declared coordinates and occurrence keys."
  (let* ((rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec)))
    (assert (= n (length permutation)))
    (assert (= n (length (remove-duplicates permutation :test #'eql))))
    (assert (every (lambda (idx) (and (integerp idx) (<= 0 idx) (< idx n))) permutation))
    (charge ledger :orientation n)
    (make-frame (copy-schema (frame-schema frame))
                (loop for idx in permutation
                      for row = (aref rows-vec idx)
                      collect (make-row :key (copy-tree (row-key row))
                                        :known (copy-tree (row-known row))
                                        :requirement (copy-tree (row-requirement row))))
                :pairs (frame-pairs frame)
                :anchors (frame-anchors frame))))

(defun support-frame (scope-or-frame support &optional ledger)
  "Turn an observed membership residual into an ordinary Boolean synthesis frame.
Every occurrence stays present. The predictor receives only the original inputs."
  (let ((frame (if (frame-p scope-or-frame)
                   scope-or-frame
                   (observation-scope-frame scope-or-frame))))
    (assert (= (length support) (length (frame-rows frame))))
    (assert (every (lambda (value) (value-p value :bool)) support))
    (make-frame
     (make-schema :inputs (copy-tree (schema-inputs (frame-schema frame))) :target :bool)
     (loop for row in (frame-rows frame) for member-p in support collect
       (let ((req (set-requirement :bool (list member-p))))
         (charge ledger :guard-frame
                 (+ 1 (syntax-work req)
                    (loop for value in (row-known row)
                          for input in (schema-inputs (frame-schema frame))
                          sum (value-work value (cdr input)))))
         (make-row :key (copy-tree (row-key row)) :known (copy-tree (row-known row)) :requirement req))))))

(defstruct partition positions groups)

(defun partition-rows (rows labels &optional ledger)
  "A supplied partition, with occurrence positions retained as its reassembly data."
  (assert (= (length rows) (length labels)))
  (let ((keys nil) (positions nil) (groups nil))
    (loop for row in rows for label in labels for index from 0 do
      (let ((part (position label keys :test #'equal)))
        (unless part
          (setf part (length keys) keys (append keys (list label))
                groups (append groups (list nil))))
        (push row (nth part groups))
        (push (list index part) positions)
        (charge ledger :partition (1+ (length keys)))))
    (make-partition :positions (nreverse positions) :groups (mapcar #'nreverse groups))))

(defun reassemble-partition (partition &optional ledger)
  (let* ((groups (mapcar #'copy-list (partition-groups partition)))
         (result (make-array (length (partition-positions partition))))
         (seen (make-hash-table)))
    (dolist (position (partition-positions partition))
      (destructuring-bind (index part) position
        (assert (and (not (gethash index seen)) (< -1 index (length result))
                     (< -1 part (length groups)) (nth part groups)))
        (setf (gethash index seen) t
              (aref result index) (pop (nth part groups)))
        (charge ledger :reassembly)))
    (assert (every #'null groups))
    (coerce result 'list)))

(defun quotient-values (values &optional ledger)
  "Return first-occurrence representatives and the complete occurrence-index residual."
  (let ((representatives nil) (residual nil))
    (dolist (value values)
      (let ((index (position value representatives :test #'equal)))
        (unless index
          (setf index (length representatives)
                representatives (append representatives (list value))))
        (charge ledger :quotient (1+ (length representatives)))
        (push index residual)))
    (values representatives (nreverse residual))))

(defun restore-quotient (representatives residual &optional ledger)
  (let ((length (length representatives)))
    (mapcar (lambda (index)
              (checked-position index length)
              (charge ledger :reassembly)
              (nth index representatives)) residual)))

(defun quotient-model (type representatives residual &optional ledger)
  "Construct a reconstructing program charging representatives AND occurrence indexes:
when RESIDUAL is a sequence of integer indices, emits batch `(gather 'R 'residual)`;
when RESIDUAL is an `:int` AST expression, emits per-row `(at 'R residual)`."
  (let ((model (if (ast-kind residual)
                   (app (op :at (sequence-type type))
                        (lit (sequence-type type) representatives)
                        residual)
                   (app (op :gather type)
                        (lit (sequence-type type) representatives)
                        (lit (sequence-type :int) residual)))))
    (charge ledger :construction (syntax-work model))
    model))

(defun partition-model (partition type &optional ledger)
  "Encode all part contents and their inverse permutation, including duplicate values."
  (reassemble-partition partition ledger)
  (let* ((groups (partition-groups partition))
         (offsets (loop with offset = 0 for group in groups
                        collect (prog1 offset (incf offset (length group)))))
         (cursors (make-array (length groups) :initial-element 0))
         (permutation (make-array (length (partition-positions partition)))))
    (dolist (position (partition-positions partition))
      (destructuring-bind (index part) position
        (setf (aref permutation index) (+ (nth part offsets) (aref cursors part)))
        (incf (aref cursors part))))
    (quotient-model type (apply #'append groups) (coerce permutation 'list) ledger)))

(defun partition-pairs-and-anchors (partition-or-rows &optional labels ledger)
  "Derive intra-block must-agree `pairs` and cross-block must-vary `anchors` from a
`partition` (or from PARTITION-OR-ROWS and LABELS via `partition-rows`).
Each block G_k with >= 2 rows contributes a chain of adjacent key pairs
`((k_{k,0} k_{k,1}) (k_{k,1} k_{k,2}) ...)` and representative anchor `k_{k,0}`.
Returns (VALUES pairs anchors partition)."
  (let* ((part (if (partition-p partition-or-rows)
                   partition-or-rows
                   (partition-rows (if (frame-p partition-or-rows)
                                       (frame-rows partition-or-rows)
                                       partition-or-rows)
                                   labels ledger)))
         (pairs nil)
         (anchors nil))
    (dolist (group (partition-groups part))
      (let ((keys (mapcar (lambda (item) (if (row-p item) (row-key item) item)) group)))
        (when (>= (length keys) 2)
          (push (copy-tree (first keys)) anchors)
          (loop for (a b) on keys
                while b
                do (charge ledger :orientation)
                   (push (list (copy-tree a) (copy-tree b)) pairs)))))
    (setf pairs (nreverse pairs)
          anchors (if (>= (length anchors) 2) (nreverse anchors) nil))
    (values pairs anchors part)))

(defun with-frame-linkage (frame &key pairs anchors partition labels ledger)
  "Construct a new `frame` over FRAME's schema and rows carrying updated `:pairs`
and `:anchors` (either supplied directly or derived from `:partition` / `:labels`
via `partition-pairs-and-anchors`)."
  (multiple-value-bind (derived-pairs derived-anchors)
      (if (or partition labels)
          (partition-pairs-and-anchors (or partition (frame-rows frame)) labels ledger)
          (values nil nil))
    (let ((eff-pairs (or pairs derived-pairs))
          (eff-anchors (or anchors derived-anchors)))
      (charge ledger :orientation (length (frame-rows frame)))
      (make-frame (copy-schema (frame-schema frame))
                  (mapcar (lambda (row)
                            (make-row :key (copy-tree (row-key row))
                                      :known (copy-tree (row-known row))
                                      :requirement (copy-tree (row-requirement row))))
                          (frame-rows frame))
                  :pairs eff-pairs
                  :anchors eff-anchors))))

(defun centered-mod-difference (predicted target modulus)
  "Return the minimal signed modular displacement DELTA in [-floor(p/2), ceil(p/2)-1]
such that (mod (+ predicted delta) modulus) = (mod target modulus)."
  (let* ((raw (mod (- target predicted) modulus))
         (half (floor modulus 2)))
    (if (> raw half)
        (- raw modulus)
        raw)))

(defun correction-packet (predicted target type &optional (predicted-p t))
  "Construct an executable correction packet transforming PREDICTED into TARGET in TYPE.
When PREDICTED-P is nil (e.g. evaluation failed with :error), returns the replacement TARGET."
  (if (not predicted-p)
      target
      (case type
        (:int (- target predicted))
        (:bool target)
        (otherwise
         (ecase (first type)
           (:gf (centered-mod-difference predicted target (second type)))
           (:tuple (loop for p-part in predicted
                         for t-part in target
                         for part-type in (rest type)
                         collect (correction-packet p-part t-part part-type t)))
           ((:seq :code) target))))))

(defun apply-correction-packet (predicted packet type &optional (predicted-p t))
  "Apply a correction PACKET produced by `correction-packet` to PREDICTED in TYPE,
reconstructing the target witness value."
  (if (not predicted-p)
      packet
      (case type
        (:int (+ predicted packet))
        (:bool packet)
        (otherwise
         (ecase (first type)
           (:gf (mod (+ predicted packet) (second type)))
           (:tuple (loop for p-part in predicted
                         for pkt-part in packet
                         for part-type in (rest type)
                         collect (apply-correction-packet p-part pkt-part part-type t)))
           ((:seq :code) packet))))))

(defun correction-bit-size (predicted target type &optional (predicted-p t))
  "Price the correction packet from PREDICTED to TARGET in TYPE in bits.
Returns 0 when PREDICTED-P is true and (equal predicted target).
When PREDICTED-P is nil, falls back to replacement (value-bit-size target type)."
  (cond
    ((not predicted-p)
     (value-bit-size target type))
    ((equal predicted target)
     0)
    (t
     (case type
       (:int (value-bit-size (- target predicted) :int))
       (:bool 1)
       (otherwise
        (ecase (first type)
          (:gf (value-bit-size (centered-mod-difference predicted target (second type)) :int))
          (:tuple (loop for p-part in predicted
                        for t-part in target
                        for part-type in (rest type)
                        sum (if (equal p-part t-part)
                                1
                                (correction-bit-size p-part t-part part-type t))))
          ((:seq :code) (value-bit-size target type))))))))

(defun select-closest-witness (predicted values type &optional (predicted-p t))
  "Select the witness W in VALUES minimizing (correction-bit-size predicted W type predicted-p),
breaking ties by first appearance in VALUES.
Returns (VALUES best-witness best-bits best-packet)."
  (assert (and (listp values) values))
  (let* ((best-witness (first values))
         (best-bits (correction-bit-size predicted best-witness type predicted-p)))
    (dolist (candidate (rest values))
      (let ((bits (correction-bit-size predicted candidate type predicted-p)))
        (when (< bits best-bits)
          (setf best-witness candidate
                best-bits bits))))
    (values best-witness best-bits (correction-packet predicted best-witness type predicted-p))))

(defun minimum-disambiguation-bit-size (type)
  "Minimum bit cost of a non-zero disambiguating step in TYPE."
  (case type
    (:int (value-bit-size 1 :int))
    (:bool 1)
    (otherwise
     (ecase (first type)
       (:gf (value-bit-size 1 :int))
       (:tuple (+ (1- (length (rest type)))
                  (reduce #'min (rest type) :key #'minimum-disambiguation-bit-size)))
       ((:seq :code) (1+ (type-bit-size type)))))))

(defun pair-connected-component (seed-key pairs)
  "Return the list of row keys in the undirected connected component of SEED-KEY in PAIRS."
  (let ((visited (list seed-key))
        (queue (list seed-key)))
    (loop while queue
          for current = (pop queue)
          do (dolist (pair pairs)
               (let ((neighbor (cond ((equal current (first pair)) (second pair))
                                     ((equal current (second pair)) (first pair))
                                     (t nil))))
                 (when (and neighbor (not (member neighbor visited :test #'equal)))
                   (push neighbor visited)
                   (setf queue (append queue (list neighbor)))))))
    (nreverse visited)))
