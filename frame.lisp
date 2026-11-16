(in-package #:lisploop)

;;; Module 4: frame.lisp
;;; Frames, S-expression requirements, pullbacks, requirement conjunction,
;;; conflict detection, support frames, partitions, and quotients.

(defstruct (row (:constructor %make-row)) key known requirement)
(defstruct (frame (:constructor %make-frame)) schema rows (edges nil) (metric nil))

(defun pairs-and-anchors->edges (pairs anchors &optional hard-p)
  "Convert row-key PAIRS and ANCHORS lists into tagged `frame-edges`."
  (nconc (loop for (a b) in pairs
               collect (list (if hard-p :equal :persistence) (copy-tree a) (copy-tree b)))
         (when anchors (list (cons (if hard-p :distinct :distinct-soft) (copy-tree anchors))))))

(defun frame-hard-edges (frame)
  "Hard equality/distinctness constraints (`:equal`, `:distinct`) enforced during exact search."
  (remove-if-not (lambda (e) (member (first e) '(:equal :distinct))) (frame-edges frame)))

(defun frame-soft-edges (frame)
  "Soft relational pricing edges (`:persistence`, `:recurrence`, `:distinct-soft`)."
  (remove-if-not (lambda (e) (member (first e) '(:persistence :recurrence :distinct-soft))) (frame-edges frame)))

(defun frame-pairs (frame)
  "Derived list of `(k1 k2)` pairs from `frame-edges` (`:equal`, `:persistence`, `:recurrence`)."
  (loop for e in (frame-edges frame)
        when (member (first e) '(:equal :persistence :recurrence)) collect (list (second e) (third e))))

(defun frame-anchors (frame)
  "Derived list of distinct anchor keys from `:distinct` / `:distinct-soft` `frame-edges`."
  (let ((anchors nil))
    (dolist (e (frame-edges frame))
      (when (member (first e) '(:distinct :distinct-soft))
        (dolist (k (rest e)) (pushnew (copy-tree k) anchors :test #'equal))))
    (when (>= (length anchors) 2) (nreverse anchors))))

(defun edge-row-keys (edge)
  (if (member (first edge) '(:equal :persistence :recurrence))
      (list (second edge) (third edge))
      (rest edge)))

(defun hard-edges-satisfied-for-row-p (row-key predicted hard-edges row-values)
  "Check HARD-EDGES involving ROW-KEY against already-settled entries in ROW-VALUES."
  (flet ((check (other expect-equal-p)
           (multiple-value-bind (v found-p) (gethash other row-values)
             (or (not found-p) (if expect-equal-p (equal predicted v) (not (equal predicted v)))))))
    (dolist (edge hard-edges t)
      (case (first edge)
        (:equal (cond ((equal row-key (second edge)) (unless (check (third edge) t) (return nil)))
                      ((equal row-key (third edge)) (unless (check (second edge) t) (return nil)))))
        (:distinct (when (member row-key (rest edge) :test #'equal)
                     (dolist (other (rest edge))
                       (unless (or (equal row-key other) (check other nil)) (return-from hard-edges-satisfied-for-row-p nil)))))))))

(defun normalize-frame-metric (metric target)
  "Validate and normalize optional frame METRIC for TARGET type (provably total `:int` AST or `:code`)."
  (when metric
    (let* ((expected-inputs (list (cons 0 target) (cons 1 target)))
           (body (cond
                   ((and (lit-p metric) (code-type-p (ast-type metric)))
                    (assert (equal expected-inputs (code-inputs (ast-type metric))) ()
                            "Frame metric :code inputs ~S do not match ~S" (code-inputs (ast-type metric)) expected-inputs)
                    (assert (eq :int (code-sort (ast-type metric))) ()
                            "Frame metric :code sort ~S must be :int" (code-sort (ast-type metric)))
                    (copy-tree (ast-value metric)))
                   (t (assert (eq :int (expression-type metric expected-inputs)) ()
                              "Frame metric expression must return :int under ~S" expected-inputs)
                      (copy-tree metric)))))
      (assert (provably-total-p body) () "Frame metric ~S must be provably total" body)
      body)))

(defun derive-row (row &key (known (copy-tree (row-known row)))
                            (requirement (copy-tree (row-requirement row))))
  "A row with a copy of ROW's key and supplied/copied KNOWN and REQUIREMENT."
  (make-row :key (copy-tree (row-key row)) :known known :requirement requirement))

(defun snapshot-row (row) (derive-row row))

(defun derive-frame (frame &key (rows (mapcar #'snapshot-row (frame-rows frame)))
                                (domain (schema-domain (frame-schema frame)))
                                (inputs (schema-inputs (frame-schema frame)) inputs-p)
                                (target (schema-target (frame-schema frame)))
                                (lookup-p (schema-lookup-p (frame-schema frame)))
                                (availability nil availability-p)
                                (edges nil edges-p)
                                (pairs (frame-pairs frame) pairs-p)
                                (anchors (frame-anchors frame) anchors-p)
                                (metric nil metric-p))
  "A fresh frame differing from FRAME only in the supplied parts."
  (let ((schema (frame-schema frame)))
    (make-frame
     (make-schema :domain domain :inputs inputs :target target :lookup-p lookup-p
                  :availability (cond (availability-p availability)
                                      ((or (not inputs-p) (equal inputs (schema-inputs schema)))
                                       (schema-availability schema))
                                      (t nil)))
     rows
     :edges (cond (edges-p edges)
                  ((or pairs-p anchors-p) (pairs-and-anchors->edges pairs anchors))
                  (t (frame-edges frame)))
     :metric (if metric-p metric (when (equal target (schema-target schema)) (frame-metric frame))))))

(defun binding-inputs (bindings inputs)
  "The input alist `((id . type) ...)` computed by BINDINGS over INPUTS."
  (mapcar (lambda (b) (cons (car b) (expression-type (cdr b) inputs))) bindings))

(defun snapshot-frame (frame)
  "Own the problem's mutable data before starting a resumable computation."
  (derive-frame frame :domain (copy-tree (schema-domain (frame-schema frame)))))

(defun extract-slot-constraint (conjunct)
  "If CONJUNCT is `(= (at x0 'idx) 'v)` or `(member (at x0 'idx) '(v1 ...))`, return `(VALUES tuple-type idx allowed)`."
  (labels ((var0-slot (term)
             (multiple-value-bind (base tuple-type idx) (tuple-slot-term term)
               (when (and base (var-p base) (zerop (ast-id base))) (values tuple-type idx)))))
    (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct)
      (declare (ignore term-type))
      (cond (term (multiple-value-bind (tt idx) (var0-slot term)
                    (when tt (values tt idx (list (ast-value lit-node))))))
            ((and (app-p conjunct) (eq :member (operator-name (first conjunct))) (lit-p (third conjunct)))
             (multiple-value-bind (tt idx) (var0-slot (second conjunct))
               (when tt (values tt idx (copy-tree (ast-value (third conjunct)))))))))))

(defun cartesian-product-lists (lists)
  (if (null lists)
      (list nil)
      (let ((rest-prod (cartesian-product-lists (rest lists))))
        (loop for item in (first lists)
              append (mapcar (lambda (tail) (cons item tail)) rest-prod)))))

(defun extract-allowed-values (expression)
  "Extract explicit finite values from `(= x0 'v)`, `(member x0 'vs)`, `'nil`,
or a complete conjunction of coordinate constraints on `(at x0 'i)`; else `:unknown`."
  (multiple-value-bind (term term-type lit-node) (match-literal-equality expression)
    (declare (ignore term-type))
    (cond
      ((and (lit-p expression) (eq :bool (ast-type expression)) (null (ast-value expression))) nil)
      ((and term (var-p term) (zerop (ast-id term))) (list (ast-value lit-node)))
      ((and (app-p expression) (eq :member (operator-name (first expression))))
       (if (and (var-p (second expression)) (zerop (ast-id (second expression))) (lit-p (third expression)))
           (copy-tree (ast-value (third expression)))
           :unknown))
      ((and (app-p expression) (eq :if (operator-name (first expression))))
       (let ((tuple-type nil) (slots nil))
         (dolist (c (extract-conjuncts expression))
           (multiple-value-bind (tt idx vals) (extract-slot-constraint c)
             (unless tt (return-from extract-allowed-values :unknown))
             (unless tuple-type (setf tuple-type tt slots (make-array (length (rest tt)) :initial-element :unbound)))
             (unless (equal tuple-type tt) (return-from extract-allowed-values :unknown))
             (setf (aref slots idx) (if (eq :unbound (aref slots idx)) vals
                                        (intersection (aref slots idx) vals :test #'equal)))))
         (if (and slots (loop for s across slots never (eq s :unbound)))
             (cartesian-product-lists (coerce slots 'list))
             :unknown)))
      (t :unknown))))

(defun singleton-requirement (type value)
  (assert (value-p value type))
  (term `(= ,(var 0 type) ',value)))

(defun set-requirement (type values)
  "An explicit finite set of whole values."
  (assert (every (lambda (v) (value-p v type)) values))
  (term `(member ,(var 0 type) ',values)))

(defun make-row (&key key known requirement)
  (assert requirement () "make-row requires :requirement")
  (%make-row :key key :known known :requirement requirement))

(defun make-frame (schema rows &key (edges nil edges-p) pairs anchors metric)
  (assert (and (valid-type-p (schema-target schema)) (valid-inputs-p (schema-inputs schema))))
  (assert (= (length rows) (length (remove-duplicates rows :key #'row-key :test #'equal))))
  (let ((row-keys (mapcar #'row-key rows))
        (eff-edges (if edges-p (copy-tree edges) (pairs-and-anchors->edges pairs anchors))))
    (dolist (row rows)
      (assert (and (= (length (row-known row)) (length (schema-inputs schema)))
                   (every (lambda (v s) (or (eq v :unresolved) (value-p v (cdr s))))
                          (row-known row) (schema-inputs schema))
                   (eq :bool (expression-type (row-requirement row) (list (cons 0 (schema-target schema))))))))
    (dolist (edge eff-edges)
      (let ((tag (first edge)) (keys (edge-row-keys edge)))
        (assert (member tag '(:equal :distinct :persistence :recurrence :distinct-soft)))
        (dolist (k keys) (assert (member k row-keys :test #'equal)))
        (if (member tag '(:equal :persistence :recurrence))
            (assert (and (= (length keys) 2) (not (equal (first keys) (second keys)))))
            (assert (and (>= (length keys) 2) (= (length keys) (length (remove-duplicates keys :test #'equal))))))))
    (%make-frame :schema schema :rows (copy-list rows) :edges eff-edges
                 :metric (normalize-frame-metric metric (schema-target schema)))))

(defun find-var-type (expression &optional (id 0))
  (cond ((and (var-p expression) (= id (ast-id expression))) (ast-type expression))
        ((app-p expression) (some (lambda (child) (find-var-type child id)) (rest expression)))))

(defun check-requirement (requirement value &key (budget 1000000) ledger type)
  "Evaluate REQUIREMENT on candidate VALUE of TYPE."
  (let ((target-type (or type (find-var-type requirement 0)
                         (when (and (app-p requirement) (member (operator-name (first requirement)) '(:= :member)))
                           (operator-operand-type (first requirement)))
                         :int)))
    (evaluate requirement (list (cons 0 target-type)) (list value) :budget budget :ledger ledger)))

(defun fold-necessary (requirement ledger budget &optional max-fibers)
  "Fold REQUIREMENT under the :necessary contract."
  (fold-constants requirement :ledger ledger :budget budget :contract :necessary :max-fibers max-fibers))

(defun conjoin-requirements (req1 req2 &key ledger (budget 10000))
  "Conjoin two row requirements over the same target variable and fold closed subtrees."
  (fold-necessary (bool-and req1 req2) ledger budget))

(defstruct (frame-conflict (:predicate frame-conflict-struct-p)) kind keys known expression)

(defun unsatisfiable-requirement-p (expr) (and (lit-p expr) (eq :bool (ast-type expr)) (null (ast-value expr))))
(defun unconstrained-requirement-p (expr) (and (lit-p expr) (eq :bool (ast-type expr)) (eq t (ast-value expr))))
(defun constrained-row-p (row) "True when ROW's requirement is non-trivial." (not (unconstrained-requirement-p (row-requirement row))))
(defun frame-constrained-row-count (frame) "Count non-trivial rows in FRAME." (count-if #'constrained-row-p (frame-rows frame)))
(defun frame-min-resolved-rows (frame) "Minimum constrained rows needed to accept a candidate." (min 2 (frame-constrained-row-count frame)))
(defun empty-sequence-row-p (row position) (and (constrained-row-p row) (null (nth position (row-known row)))))

(defun row-singleton-value (row)
  "Return `(VALUES value t)` when ROW's requirement allows one explicit value."
  (let ((allowed (and (constrained-row-p row) (extract-allowed-values (row-requirement row)))))
    (when (and (consp allowed) (null (rest allowed))) (values (first allowed) t))))

(defun unconstrained-frame (frame target-type &key domain)
  "Clone FRAME's rows and inputs with target TARGET-TYPE and `'t` requirements."
  (derive-frame frame :rows (mapcar (lambda (r) (derive-row r :requirement (lit :bool t))) (frame-rows frame))
                :domain (or domain (schema-domain (frame-schema frame))) :target target-type :lookup-p nil :edges nil))

(defun frame-conflict-p (frame &key ledger (budget 10000))
  "Detect unsatisfiable rows or contradictory same-input rows. Returns `(VALUES conflict folded-frame)`."
  (let ((joints (make-hash-table :test #'equal)) (folded-rows nil))
    (dolist (row (frame-rows frame) (values nil (derive-frame frame :rows (nreverse folded-rows))))
      (let* ((folded (fold-necessary (row-requirement row) ledger budget))
             (conflict (cond ((unsatisfiable-requirement-p folded)
                              (make-frame-conflict :kind :unsatisfiable-row :keys (list (row-key row))
                                                   :known (row-known row) :expression folded))
                             ((not (member :unresolved (row-known row)))
                              (nth-value 1 (join-same-input joints row folded :ledger ledger :budget budget))))))
        (when conflict (return-from frame-conflict-p (values conflict nil)))
        (push (derive-row row :known (row-known row) :requirement folded) folded-rows)))))

(defun join-same-input (joints row requirement &key ledger (budget 10000))
  "Conjoin REQUIREMENT into JOINTS keyed by resolved known tuple. Returns `(VALUES joint conflict)`."
  (assert (not (member :unresolved (row-known row))))
  (let* ((known (row-known row))
         (earlier (gethash known joints))
         (keys (cons (row-key row) (cdr earlier)))
         (joint (if earlier (conjoin-requirements (car earlier) requirement :ledger ledger :budget budget) requirement)))
    (setf (gethash known joints) (cons joint keys))
    (values joint (when (and earlier (unsatisfiable-requirement-p joint))
                    (make-frame-conflict :kind :incompatible-rows :keys (reverse keys)
                                         :known known :expression joint)))))

(defun orient-observations (types records input-columns target-columns &key lookup-p ledger)
  "Re-use witnessed (key . values) records without simulation."
  (assert (and target-columns (null (intersection input-columns target-columns))))
  (let* ((target (if (rest target-columns)
                     (apply #'tuple-type (mapcar (lambda (i) (nth i types)) target-columns))
                     (nth (first target-columns) types)))
         (schema (make-schema :inputs (mapcar (lambda (i) (cons i (nth i types))) input-columns)
                              :target target :lookup-p lookup-p)))
    (make-frame
     schema
     (loop for (key . values) in records
           do (assert (and (= (length values) (length types)) (every #'value-p values types)))
              (charge ledger :orientation (+ 1 (loop for v in values for tp in types sum (value-work v tp))))
           collect (make-row :key key :known (mapcar (lambda (i) (nth i values)) input-columns)
                             :requirement (singleton-requirement target
                                           (if (rest target-columns)
                                               (mapcar (lambda (i) (nth i values)) target-columns)
                                               (nth (first target-columns) values))))))))

(defun transition-probes (frame output-type &optional ledger)
  "Reorient recorded singleton state transitions into before/after input probes."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (req (lit :bool t)) (rows nil) (pairs nil))
    (assert (equal (schema-target schema) (apply #'tuple-type (mapcar #'cdr inputs))))
    (dolist (row (frame-rows frame))
      (let ((targets (extract-allowed-values (row-requirement row)))
            (bk (list (row-key row) :before)) (ak (list (row-key row) :after)))
        (assert (and (listp targets) (= (length targets) 1)) () "Transition probes require a recorded singleton successor")
        (push (make-row :key bk :known (copy-tree (row-known row)) :requirement req) rows)
        (push (make-row :key ak :known (copy-tree (first targets)) :requirement req) rows)
        (push (list bk ak) pairs)
        (charge ledger :orientation
                (+ 2 (loop for s in inputs for b in (row-known row) for a in (first targets)
                           sum (+ (value-work b (cdr s)) (value-work a (cdr s))))))))
    (values (make-frame (make-schema :inputs (copy-tree inputs) :target output-type)
                        (nreverse rows) :edges (loop for (b a) in (nreverse (copy-tree pairs))
                                                     collect (list :recurrence b a)))
            (nreverse pairs))))

(defun lookup-model (frame &optional ledger)
  "Package actual available witnesses into a lookup model."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (groups nil))
    (assert (schema-lookup-p schema))
    (dolist (row (frame-rows frame))
      (let* ((vals (extract-allowed-values (row-requirement row)))
             (old (assoc (row-known row) groups :test #'equal)))
        (when (eq vals :unknown) (error "No explicit witnesses for lookup"))
        (charge ledger :baseline (+ 1 (loop for v in vals sum (value-work v (schema-target schema)))))
        (if old (setf (cdr old) (intersection (cdr old) vals :test #'equal))
            (push (cons (row-known row) (copy-list vals)) groups))))
    (assert (every #'cdr groups) () "Inconsistent requirements for a lookup key")
    (let ((model (term `(lookup (tuple ,@(mapcar (lambda (s) (var (car s) (cdr s))) inputs))
                                ',(mapcar (lambda (g) (list (car g) (second g))) (reverse groups)))
                       (schema-target schema))))
      (charge ledger :baseline (syntax-work model))
      model)))

(defun frame-oracle-table (frame &optional ledger)
  "Extract an input-output alist `((known-args . target-val) ...)` from singleton rows of FRAME."
  (let ((target-type (schema-target (frame-schema frame))) (table nil))
    (dolist (row (frame-rows frame) (nreverse table))
      (unless (member :unresolved (row-known row))
        (let ((allowed (extract-allowed-values (row-requirement row))))
          (when (and (consp allowed) (= 1 (length allowed)) (not (assoc (row-known row) table :test #'equal)))
            (charge ledger :orientation (1+ (value-work (first allowed) target-type)))
            (push (cons (copy-tree (row-known row)) (copy-tree (first allowed))) table)))))))

(defun evaluate-row-bindings (bindings inputs known &key ledger (error-p t)
                                                         allow-unresolved-p default-on-failure-p)
  "Evaluate BINDINGS `((id . expr) ...)` on KNOWN under INPUTS."
  (loop for (nil . expr) in bindings
        for run = (evaluate expr inputs known :ledger ledger)
        for status = (evaluation-status run)
        collect (cond ((eq status :value) (evaluation-value run))
                      (default-on-failure-p (default-value-for-type (expression-type expr inputs)))
                      ((and allow-unresolved-p (eq status :unresolved)) :unresolved)
                      (error-p (error "Context binding did not finish: ~S" run))
                      (t (return :error)))))

(defun pullback-frame (parent decoder child-id child-type bindings &optional ledger)
  "B(z)=A(d(c,z)): pull PARENT's requirements back through DECODER over BINDINGS."
  (let* ((schema (frame-schema parent)) (inputs (schema-inputs schema))
         (child-inputs (binding-inputs bindings inputs))
         (partial-p (some (lambda (b) (not (provably-total-p (cdr b)))) bindings))
         (multi-p (> (length (frame-rows parent)) 1))
         (dec-free (ast-meta-free-vars (ensure-ast-meta decoder))))
    (assert (and (not (assoc child-id inputs))
                 (equal (schema-target schema) (expression-type decoder (acons child-id child-type inputs)))))
    (derive-frame
     parent :domain nil :inputs child-inputs :target child-type :lookup-p nil
     :availability (project-schema-availability (schema-availability schema) bindings)
     :rows (loop for row in (frame-rows parent) collect
             (let* ((unres-dec (loop for (id . nil) in inputs for v in (row-known row)
                                     thereis (and (eq v :unresolved) (member id dec-free :test #'eql))))
                    (closed (unless unres-dec
                              (instantiate decoder (acons child-id (var 0 child-type)
                                                          (literal-bindings inputs (row-known row)))
                                           :var)))
                    (pred (if unres-dec (lit :bool t)
                              (instantiate (row-requirement row) (list (cons 0 closed)) :var)))
                    (dead-p (and multi-p (or (unconstrained-requirement-p (row-requirement row))
                                             (and partial-p (unconstrained-requirement-p (fold-constants pred))))))
                    (known (evaluate-row-bindings bindings inputs (row-known row) :ledger ledger
                                                  :allow-unresolved-p t :default-on-failure-p dead-p)))
               (charge ledger :pullback (syntax-work pred))
               (derive-row row :known known :requirement pred))))))

(defun walk-ast-shallow (expr fn)
  "Call FN on every AST node in EXPR without descending into quoted `:code` literals."
  (funcall fn expr)
  (when (app-p expr) (dolist (arg (rest expr)) (walk-ast-shallow arg fn))))

(defun max-var-id-in-expr (expr)
  (let ((best -1))
    (walk-ast-shallow expr (lambda (n) (when (and (var-p n) (> (ast-id n) best)) (setf best (ast-id n)))))
    best))

(defun count-ast-var-occurrences (id expr)
  (let ((count 0))
    (walk-ast-shallow expr (lambda (n) (when (and (var-p n) (eql id (ast-id n))) (incf count))))
    count))

(defun count-subexpr-occurrences (sub expr)
  (let ((count 0))
    (walk-ast-shallow expr (lambda (n) (when (equal n sub) (incf count))))
    count))

(defun compose-model-score (expr inputs &key rows (run-weight 0) ledger)
  "Score EXPR as `S(EXPR) + RUN-WEIGHT * total-run-work`."
  (let ((bits (description-size expr inputs)))
    (if (and rows (plusp run-weight))
        (+ bits (* run-weight (loop for row in rows unless (member :unresolved (row-known row))
                                    sum (evaluation-work (evaluate expr inputs (row-known row) :budget 2000 :ledger ledger)))))
        bits)))

(defun factor-shared-subexpressions (inline &key inputs (run-weight 0) rows ledger)
  "Introduce definedness-safe homoiconic `:code-eval` let-sharing for repeated compound subexpressions."
  (when (or (not (app-p inline)) (pattern-has-holes-p inline))
    (return-from factor-shared-subexpressions inline))
  (let* ((eff-inputs (input-alist (or inputs (infer-exprs-inputs (list inline)))))
         (ret-type (ignore-errors (expression-type inline eff-inputs))))
    (when (null ret-type) (return-from factor-shared-subexpressions inline))
    (let ((counts (make-hash-table :test #'equal)) (ordered nil))
      (labels ((walk (node)
                 (when (app-p node)
                   (unless (eq node inline)
                     (unless (gethash node counts) (push node ordered))
                     (incf (gethash node counts 0)))
                   (mapc #'walk (rest node)))))
        (walk inline))
      (let* ((next-temp (+ 1000 (max 0 (max (if eff-inputs (reduce #'max eff-inputs :key #'car) -1)
                                            (max-var-id-in-expr inline)))))
             (ranked (stable-sort (loop for e in (nreverse ordered) for c = (gethash e counts 0)
                                        when (and (>= c 2) (ignore-errors (expression-type e eff-inputs)))
                                          collect (list e (* (1- c) (syntax-work e))))
                                  #'> :key #'second))
             (eligible (loop for item in (subseq ranked 0 (min 8 (length ranked)))
                             collect (cons (first item) (prog1 next-temp (incf next-temp))))))
        (when (null eligible) (return-from factor-shared-subexpressions inline))
        (let ((inline-total-p (provably-total-p inline))
              (score-cache (make-hash-table :test #'equal)))
          (labels ((score (expr)
                     (or (gethash expr score-cache)
                         (setf (gethash expr score-cache)
                               (compose-model-score expr eff-inputs :rows rows :run-weight run-weight :ledger ledger))))
                   (build-shared (subset)
                     (when subset
                       (let* ((active (stable-sort (copy-list subset) #'> :key (lambda (e) (syntax-work (car e)))))
                              (raw-body (map-ast (lambda (node meta)
                                                   (declare (ignore meta))
                                                   (let ((e (assoc node active :test #'equal)))
                                                     (when e (var (cdr e) (ast-type node)))))
                                                 inline :root-first t)))
                         (loop (let* ((demanded (demanded-vars raw-body))
                                      (drop (remove-if-not
                                             (lambda (e)
                                               (or (and (not (provably-total-p (car e)))
                                                        (not (member (cdr e) demanded :test #'eql)))
                                                   (< (count-ast-var-occurrences (cdr e) raw-body) 2)))
                                             active)))
                                 (if (null drop) (return)
                                     (setf active (remove-if (lambda (e) (member e drop :test #'eq)) active)
                                           raw-body (instantiate raw-body (mapcar (lambda (e) (cons (cdr e) (car e))) drop) :var)))))
                         (when active
                           (let* ((raw-free (free-vars raw-body))
                                  (active-tids (mapcar #'cdr active))
                                  (outer-specs (loop for spec in eff-inputs
                                                     when (and (member (car spec) raw-free :test #'eql)
                                                               (not (member (car spec) active-tids :test #'eql)))
                                                       collect spec))
                                  (pid -1) body-subst body-inputs eval-args)
                             (dolist (spec outer-specs)
                               (incf pid)
                               (push (cons (car spec) (var pid (cdr spec))) body-subst)
                               (push (cons pid (cdr spec)) body-inputs)
                               (push (var (car spec) (cdr spec)) eval-args))
                             (dolist (entry active)
                               (incf pid)
                               (let ((et (ast-type (car entry))))
                                 (push (cons (cdr entry) (var pid et)) body-subst)
                                 (push (cons pid et) body-inputs)
                                 (push (car entry) eval-args)))
                             (let* ((bci (nreverse body-inputs)) (bct (code-type bci ret-type))
                                    (cand (apply #'app (op :code-eval bct)
                                                 (lit bct (instantiate raw-body (nreverse body-subst) :var))
                                                 (nreverse eval-args))))
                               (when (and (ignore-errors (expression-type cand eff-inputs))
                                          (or (not inline-total-p) (provably-total-p cand)))
                                 cand))))))))
            (let* ((best inline) (best-score (score inline))
                   (cur eligible) (cur-cand (build-shared cur))
                   (cur-score (if cur-cand (score cur-cand) best-score)))
              (when (and cur-cand (< cur-score best-score)) (setf best cur-cand best-score cur-score))
              (loop while (rest cur) do
                (let (ncand ncur nscore)
                  (dolist (item cur)
                    (let* ((sub (remove item cur :test #'eq :count 1)) (c (build-shared sub)))
                      (when c (let ((sc (score c)))
                                (when (or (null nscore) (< sc nscore)) (setf ncur sub ncand c nscore sc))))))
                  (if (and nscore (< nscore cur-score))
                      (progn (setf cur ncur cur-cand ncand cur-score nscore)
                             (when (< cur-score best-score) (setf best cur-cand best-score cur-score)))
                      (return))))
              best)))))))

(defun compose-model (decoder child-id child-model bindings &rest options)
  "Compose CHILD-MODEL into DECODER with BINDINGS, adding safe `:code-eval` let-sharing when smaller."
  (let ((ledger (when (and options (not (keywordp (first options)))) (pop options))))
    (destructuring-bind (&key inputs (run-weight 0) rows) options
      (let* ((inline (instantiate decoder (list (cons child-id (instantiate child-model bindings :var))) :var))
             (result (if (or (pattern-has-holes-p inline) (pattern-has-holes-p child-model))
                         inline
                         (factor-shared-subexpressions inline :inputs inputs :run-weight run-weight
                                                       :rows rows :ledger ledger))))
        (charge ledger :composition (syntax-work result))
        result))))

(defun default-value-for-type (type)
  "Construct a canonical witness value belonging to TYPE."
  (case type (:int 0) (:bool nil)
    (otherwise (ecase (first type)
                 (:gf 0)
                 (:tuple (mapcar #'default-value-for-type (rest type)))
                 (:seq nil)
                 (:code (lit (code-sort type) (default-value-for-type (code-sort type))))))))

(defun collect-code-eval-calls (expr code-var)
  "Return `(VALUES ground-calls non-ground-p)` for `:code-eval CODE-VAR ...` subterms in EXPR."
  (let ((ground nil) (non-ground-p nil))
    (labels ((walk (n)
               (when (app-p n)
                 (mapc #'walk (rest n))
                 (when (and (operator-p (first n)) (eq :code-eval (operator-name (first n)))
                            (equal (second n) code-var))
                   (if (every #'lit-p (cddr n)) (pushnew n ground :test #'equal) (setf non-ground-p t))))))
      (walk expr)
      (values (nreverse ground) non-ground-p))))

(defun extract-code-eval-equation (conjunct code-var)
  (multiple-value-bind (ground non-ground-p) (collect-code-eval-calls conjunct code-var)
    (when (and (not non-ground-p) (null (rest ground)) (first ground))
      (if (and (equal conjunct (first ground)) (eq :bool (ast-type conjunct)))
          (values (first ground) (lit :bool t))
          (multiple-value-bind (term term-type lit-node) (match-literal-equality conjunct)
            (declare (ignore term-type))
            (when (equal term (first ground)) (values (first ground) lit-node)))))))

(defun congruence-close-code-evals (row-reqs extra-knowns code-var &key ledger (budget 10000))
  "Propagate ground equations `(= (:code-eval CODE-VAR 'args...) 'val)` across rows sharing EXTRA-KNOWNS."
  (let ((reqs (copy-list row-reqs)) (known-evals (make-hash-table :test #'equal)))
    (loop
      (let ((changed nil))
        (loop for req in reqs for extra in extra-knowns
              do (dolist (c (extract-conjuncts req))
                   (multiple-value-bind (call val-lit) (extract-code-eval-equation c code-var)
                     (when call (setf (gethash (cons extra call) known-evals)
                                      (or (gethash (cons extra call) known-evals) val-lit))))))
        (setf reqs
              (loop for req in reqs for extra in extra-knowns
                    collect (let ((row-changed nil) (new-cs nil))
                              (dolist (c (extract-conjuncts req))
                                (multiple-value-bind (ground non-ground-p) (collect-code-eval-calls c code-var)
                                  (if (or non-ground-p (> (length ground) 1))
                                      (let ((sub c))
                                        (dolist (gc ground)
                                          (let ((vl (gethash (cons extra gc) known-evals)))
                                            (when vl (charge ledger :pullback (syntax-work vl))
                                                  (setf sub (replace-subexpression sub gc vl)))))
                                        (cond ((equal sub c) (push c new-cs))
                                              (t (setf row-changed t changed t)
                                                 (push (fold-necessary sub ledger budget) new-cs))))
                                      (push c new-cs))))
                              (if row-changed
                                  (fold-necessary (reduce #'bool-and (nreverse new-cs)
                                                          :from-end t :initial-value (lit :bool t))
                                                  ledger budget)
                                  req))))
        (unless changed (return reqs))))))

(defun extract-outermost-code-eval (expr code-var)
  (let ((outer nil) (mult-p nil))
    (labels ((walk (n)
               (when (and (not mult-p) (app-p n))
                 (if (and (operator-p (first n)) (eq :code-eval (operator-name (first n)))
                          (equal (second n) code-var))
                     (if (and outer (not (equal outer n))) (setf mult-p t) (setf outer n))
                     (mapc #'walk (rest n))))))
      (walk expr) (unless mult-p outer))))

(defparameter *max-active-lifted-rows* 16
  "Maximum active fiber rows retained by LIFT-FRAME before holding remainder in reserve for CEGAR.")

(defun flatten-lifted-conjuncts (expr code-var)
  (let ((out nil))
    (labels ((expand (c)
               (cond ((not (and (app-of-p c :if) (not (and (lit-p (fourth c)) (null (ast-value (fourth c)))))
                                (app-of-p (second c) :code-eval) (equal (second (second c)) code-var)))
                      (push c out))
                     ((unsatisfiable-requirement-p (third c))
                      (push (term `(= ,(second c) nil)) out)
                      (mapc #'expand (extract-conjuncts (fourth c))))
                     (t (push (second c) out)
                        (mapc #'expand (extract-conjuncts (third c)))))))
      (mapc #'expand (extract-conjuncts expr))
      (nreverse out))))

(defun select-active-fiber-rows (rows max-active-rows)
  "Partition ROWS into `(VALUES active-rows reserve-rows)` retaining unsat rows, 3:1 locality
window per parent row, diverse first arguments, and remaining rows up to MAX-ACTIVE-ROWS."
  (if (or (null max-active-rows) (<= (length rows) max-active-rows))
      (values rows nil)
      (let ((selected (make-hash-table :test #'eq)) (by-parent (make-hash-table :test #'equal))
            (parent-keys nil) (seen-k0 (make-hash-table :test #'equal))
            (loc-limit (max 2 (ceiling (* 3 max-active-rows) 4))) (count 0))
        (flet ((pick (r) (when (and (< count max-active-rows) (not (gethash r selected)))
                           (setf (gethash r selected) t) (incf count))))
          (dolist (r rows) (when (unsatisfiable-requirement-p (row-requirement r))
                             (unless (gethash r selected) (setf (gethash r selected) t) (incf count))))
          (dolist (r rows)
            (let ((pk (if (consp (row-key r)) (first (row-key r)) (row-key r))))
              (unless (gethash pk by-parent) (push pk parent-keys))
              (push r (gethash pk by-parent))))
          (dolist (pk (nreverse parent-keys))
            (let ((ord (reverse (gethash pk by-parent))))
              (pick (first ord))
              (when (rest ord) (pick (second ord)))
              (when (and (< count loc-limit) (cddr ord)) (pick (car (last ord))))))
          (dolist (r rows)
            (when (row-known r)
              (let ((k0 (first (row-known r))))
                (unless (gethash k0 seen-k0) (setf (gethash k0 seen-k0) t) (pick r)))))
          (dolist (r rows) (pick r))
          (let (active reserve)
            (dolist (r rows (values (nreverse active) (nreverse reserve)))
              (if (gethash r selected) (push r active) (push r reserve))))))))

(defun code-call-row (key call extra requirement)
  (make-row :key key
            :known (append (mapcar (lambda (a) (if (lit-p a) (copy-tree (ast-value a)) :unresolved)) (cddr call))
                           (copy-tree extra))
            :requirement requirement))

(defun default-known (inputs) (mapcar (lambda (i) (default-value-for-type (cdr i))) inputs))

(defun probe-frame-coordinates (frame decoder child-id child-type
                                &optional bindings ledger &key (coordinates '((0) (1))) (budget 4000))
  "Project sequence/grid requirements of FRAME at COORDINATES through DECODER."
  (let* ((raw (pullback-frame frame decoder child-id child-type bindings ledger))
         (code-p (code-type-p child-type)) (ret (if code-p (code-sort child-type) child-type))
         (target-type (schema-target (frame-schema frame)))
         probed-target probed-rows)
    (labels ((project-coord (expr val type coord)
               (if (null coord)
                   (values (term `(= ,expr ',val)) type val)
                   (when (and (seq-type-p type) (listp val))
                     (let* ((raw-i (first coord)) (idx (if (minusp raw-i) (+ (length val) raw-i) raw-i)))
                       (when (and (<= 0 idx) (< idx (length val)))
                         (project-coord (term `(at ,expr ,idx)) (nth idx val) (second type) (rest coord))))))))
      (dolist (row (frame-rows raw))
        (multiple-value-bind (compound _t witness)
            (match-literal-equality (row-requirement row) :singleton-member-p t)
          (declare (ignore _t))
          (if (and compound (seq-type-p target-type))
              (dolist (coord coordinates)
                (multiple-value-bind (proj ltype lval) (project-coord compound (ast-value witness) target-type coord)
                  (when proj
                    (setf probed-target ltype)
                    (let* ((key (list (row-key row) coord))
                           (folded (fold-necessary proj ledger budget (+ 2 (reduce #'max coord :initial-value 1))))
                           (call (when code-p (extract-outermost-code-eval folded (var 0 child-type)))))
                      (cond ((not code-p)
                             (push (make-row :key key :known (copy-tree (row-known row))
                                             :requirement (if (equal compound (var 0 target-type))
                                                              (singleton-requirement ltype lval) folded))
                                   probed-rows))
                            ((and call (every #'lit-p (cddr call)))
                             (push (code-call-row key call (row-known row)
                                                  (replace-subexpression folded call (var 0 ret)))
                                   probed-rows)))))))
              (unless code-p (push row probed-rows)))))
      (make-frame (make-schema :domain (schema-domain (frame-schema frame))
                               :inputs (append (when code-p (code-inputs child-type)) (schema-inputs (frame-schema raw)))
                               :target (if code-p ret (or probed-target (schema-target (frame-schema raw)))))
                  (nreverse probed-rows)))))

(defun coupled-fallback-rows (coupled code-var ret child-inputs ledger budget)
  (loop for (key occ-idx extra c) in coupled collect
    (let* ((outer (extract-outermost-code-eval c code-var))
           (replaced (when outer (replace-subexpression c outer (var 0 ret))))
           (clean-p (and replaced (multiple-value-bind (g ng) (collect-code-eval-calls replaced code-var)
                                    (not (or g ng)))))
           (row (if clean-p
                    (code-call-row (list key :coupled occ-idx) outer extra (fold-necessary replaced ledger budget))
                    (make-row :key (list key :coupled occ-idx)
                              :known (mapcar (constantly :unresolved) child-inputs)
                              :requirement (singleton-requirement ret (default-value-for-type ret))))))
      (charge ledger :pullback (syntax-work (row-requirement row)))
      row)))

(defun lift-frame (parent decoder child-id child-type &optional bindings ledger (budget 10000)
                                                      (max-active-rows *max-active-lifted-rows*))
  "Lift PARENT through higher-order DECODER into a 1-to-many child frame.
Returns `(VALUES lifted-frame coupled-conjuncts reserve-rows)`."
  (assert (and (code-type-p child-type) (not (function-sort-p (code-sort child-type)))))
  (let* ((raw (pullback-frame parent decoder child-id child-type bindings ledger))
         (code-in (code-inputs child-type)) (ret (code-sort child-type))
         (extra-in (schema-inputs (frame-schema raw))) (child-inputs (append code-in extra-in))
         (code-var (var 0 child-type)) (ret-var (var 0 ret))
         (extra-knowns (mapcar #'row-known (frame-rows raw)))
         (max-fibers (when max-active-rows
                       (max 4 (+ 2 (ceiling max-active-rows (max 1 (frame-constrained-row-count raw)))))))
         (closed-reqs (congruence-close-code-evals
                       (mapcar (lambda (r) (fold-necessary (row-requirement r) ledger budget max-fibers))
                               (frame-rows raw))
                       extra-knowns code-var :ledger ledger :budget budget))
         (seen (make-hash-table :test #'equal))
         lifted-rows coupled)
    (assert (null (intersection (mapcar #'car code-in) (mapcar #'car extra-in))))
    (flet ((refuted-row (key extra)
             (make-row :key key :known (append (default-known code-in) (copy-tree extra))
                       :requirement (lit :bool nil))))
      (loop for parent-row in (frame-rows raw) for key = (row-key parent-row)
            for req in closed-reqs for extra in extra-knowns do
              (if (unsatisfiable-requirement-p req)
                  (push (refuted-row (list key :unsat) extra) lifted-rows)
                  (loop for c in (flatten-lifted-conjuncts req code-var) for occ-idx from 0 do
                    (multiple-value-bind (ground ng-p) (collect-code-eval-calls c code-var)
                      (cond ((or ng-p (rest ground)) (push (list key occ-idx extra c) coupled))
                            (ground
                             (let* ((call (first ground))
                                    (row (code-call-row (list key occ-idx) call extra
                                                        (fold-necessary
                                                         (if (and (equal c call) (eq :bool ret))
                                                             (term `(= ,ret-var t))
                                                             (replace-subexpression c call ret-var))
                                                         ledger budget)))
                                    (dkey (list (row-known row) (row-requirement row))))
                               (unless (gethash dkey seen)
                                 (setf (gethash dkey seen) t)
                                 (charge ledger :pullback (syntax-work (row-requirement row)))
                                 (push row lifted-rows))))
                            ((unsatisfiable-requirement-p c)
                             (push (refuted-row (list key occ-idx) extra) lifted-rows))))))))
    (setf lifted-rows (nreverse lifted-rows) coupled (nreverse coupled))
    (when (and coupled (null (rest lifted-rows)))
      (setf lifted-rows (append lifted-rows (coupled-fallback-rows coupled code-var ret child-inputs ledger budget))))
    (multiple-value-bind (active reserve)
        (select-active-fiber-rows
         (or lifted-rows (list (make-row :key :vacuous :known (default-known child-inputs) :requirement (lit :bool t))))
         max-active-rows)
      (values (make-frame (make-schema :inputs child-inputs :target ret
                                       :availability (schema-availability (frame-schema raw)))
                          active)
              (mapcar (lambda (e) (cons (first e) (fourth e))) coupled)
              reserve))))

(defun compose-lifted-model (decoder child-id child-type child-model &optional bindings ledger)
  "Package synthesized CHILD-MODEL into a `:code` value (with `:code-subst` closures if needed)
and instantiate DECODER at CHILD-ID."
  (assert (and (code-type-p child-type) (not (function-sort-p (code-sort child-type)))))
  (let* ((code-in (code-inputs child-type)) (ret (code-sort child-type))
         (free (free-vars child-model))
         (used-ids (when bindings (loop for (bid . nil) in bindings
                                        when (member bid free :test #'eql) collect bid)))
         (code-expr
           (if (null used-ids)
               (lit child-type child-model)
               (let* ((max-uid (reduce #'max used-ids))
                      (active (remove-if (lambda (b) (> (car b) max-uid)) bindings))
                      (full-ct (code-type (append code-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) active)) ret))
                      (targs (append (mapcar (lambda (s) (lit (code-type code-in (cdr s)) (var (car s) (cdr s)))) code-in)
                                     (mapcar #'cdr active))))
                 (term `(code-subst ,(lit full-ct child-model) (tuple ,@targs)) child-type))))
         (model (instantiate decoder (list (cons child-id code-expr)) :var)))
    (charge ledger :composition (syntax-work model))
    model))

(declaim (ftype function conserved-expression-sensitive-p solve-equality-symbolically))

(defun conserved-quantity-frame (obs-frame target-id conserved-expr constant-value &rest args)
  "Reorient conserved `C(u, T) = CONSTANT-VALUE` on OBS-FRAME to solve for TARGET-ID (`:auto` = maximal availability).
Returns `(VALUES pulled-back-frame const-frame solved-expr target-id)`."
  (let* ((opt-l (when (and args (not (keywordp (first args)))) (first args)))
         (plist (if (and args (not (keywordp (first args)))) (rest args) args))
         (ledger (or (getf plist :ledger) opt-l))
         (symbolic-p (getf plist :symbolic-p))
         (library (or (getf plist :library) *knowledge-library*))
         (allow-tentative-p (if (member :allow-tentative-p plist) (getf plist :allow-tentative-p) t))
         (schema (frame-schema obs-frame)) (inputs (schema-inputs schema))
         (eff-tid (if (eq target-id :auto) (schema-maximal-availability-id schema) target-id))
         (tpos (position eff-tid inputs :key #'car :test #'equal))
         (ttype (cdr (nth tpos inputs)))
         (u-inputs (remove eff-tid inputs :key #'car :test #'equal))
         (c-type (expression-type conserved-expr inputs))
         (const-req (singleton-requirement c-type constant-value)))
    (when (and (getf plist :check-sensitivity-p)
               (not (conserved-expression-sensitive-p conserved-expr eff-tid obs-frame ledger)))
      (return-from conserved-quantity-frame (values nil nil nil eff-tid)))
    (let* ((const-frame
             (derive-frame obs-frame :inputs u-inputs :target c-type :lookup-p nil
                           :availability (project-schema-availability (schema-availability schema) nil
                                                                      :new-target-id eff-tid :drop-ids (list eff-tid))
                           :rows (loop for row in (frame-rows obs-frame)
                                       collect (derive-row row :known (loop for val in (row-known row) for idx from 0
                                                                            unless (= idx tpos) collect val)
                                                           :requirement const-req))))
           (pulled (pullback-frame const-frame conserved-expr eff-tid ttype (identity-bindings u-inputs) ledger))
           (solved (when symbolic-p
                     (solve-equality-symbolically
                      (app (op := c-type) conserved-expr (lit c-type constant-value))
                      eff-tid ttype library :inputs inputs
                      :sample-knowns (loop for r in (frame-rows obs-frame)
                                           unless (member :unresolved (row-known r)) collect (row-known r))
                      :allow-tentative-p allow-tentative-p :ledger ledger))))
      (values pulled const-frame solved eff-tid))))

(defun project-frame-by-bindings (frame bindings ledger row-fn &rest derive-keys)
  "Shared schema/availability/row-binding projection helper for derived frames."
  (let* ((schema (frame-schema frame))
         (p-inputs (schema-inputs schema))
         (c-inputs (binding-inputs bindings p-inputs)))
    (apply #'derive-frame frame
           :inputs c-inputs
           :availability (project-schema-availability (schema-availability schema) bindings)
           :rows (loop for row in (frame-rows frame) for idx from 0
                       collect (funcall row-fn row idx (evaluate-row-bindings bindings p-inputs (row-known row) :ledger ledger)))
           derive-keys)))

(defun context-label-frame (parent labels &key bindings (label-type :int) (lookup-p t) ledger)
  "Project PARENT rows through BINDINGS onto singleton requirements for LABELS."
  (let* ((parent-schema (frame-schema parent))
         (eff-b (or bindings (identity-bindings (schema-inputs parent-schema)))))
    (assert (= (length labels) (length (frame-rows parent))) ()
            "Label count (~D) must match parent row count (~D)" (length labels) (length (frame-rows parent)))
    (project-frame-by-bindings
     parent eff-b ledger
     (lambda (row idx known)
       (let ((req (singleton-requirement label-type (nth idx labels))))
         (charge ledger :context-frame (syntax-work req))
         (derive-row row :known known :requirement req)))
     :domain (if (eq label-type :bool) (schema-domain parent-schema) label-type)
     :target label-type :lookup-p lookup-p)))

(defun project-frame-rows (frame bindings &optional ledger)
  "Project FRAME's `row-known` values through BINDINGS."
  (if (null bindings) frame
      (project-frame-by-bindings
       frame bindings ledger
       (lambda (row idx known) (declare (ignore idx))
         (charge ledger :orientation (length known))
         (derive-row row :known known)))))

(defun shuffle-frame-rows (frame permutation &optional ledger)
  "Permute physical storage order of FRAME's rows according to bijection PERMUTATION."
  (let* ((vec (coerce (frame-rows frame) 'vector)) (n (length vec)))
    (assert (and (= n (length permutation)) (= n (length (remove-duplicates permutation :test #'eql)))
                 (every (lambda (i) (and (integerp i) (<= 0 i) (< i n))) permutation)))
    (charge ledger :orientation n)
    (derive-frame frame :rows (loop for idx in permutation collect (snapshot-row (aref vec idx))))))

(defun support-frame (scope-or-frame support &optional ledger)
  "Turn a Boolean membership vector SUPPORT over rows into an ordinary Boolean synthesis frame."
  (let ((frame (if (frame-p scope-or-frame) scope-or-frame (observation-scope-frame scope-or-frame))))
    (assert (and (= (length support) (length (frame-rows frame))) (every (lambda (v) (value-p v :bool)) support)))
    (derive-frame
     frame :domain nil :target :bool :lookup-p nil :edges nil
     :rows (loop for row in (frame-rows frame) for member-p in support collect
             (let ((req (set-requirement :bool (list member-p))))
               (charge ledger :guard-frame
                       (+ 1 (syntax-work req)
                          (loop for v in (row-known row) for in in (schema-inputs (frame-schema frame))
                                sum (value-work v (cdr in)))))
               (derive-row row :requirement req))))))

(defstruct partition positions groups)

(defun partition-rows (rows labels &optional ledger)
  "A supplied partition, retaining occurrence positions as reassembly data."
  (assert (= (length rows) (length labels)))
  (multiple-value-bind (keys parts) (quotient-values labels ledger :partition)
    (make-partition
     :positions (loop for p in parts for i from 0 collect (list i p))
     :groups (loop for g below (length keys)
                   collect (loop for r in rows for p in parts when (= p g) collect r)))))

(defun reassemble-partition (partition &optional ledger)
  (let* ((groups (mapcar #'copy-list (partition-groups partition)))
         (result (make-array (length (partition-positions partition))))
         (seen (make-hash-table)))
    (dolist (pos (partition-positions partition))
      (destructuring-bind (index part) pos
        (assert (and (not (gethash index seen)) (< -1 index (length result))
                     (< -1 part (length groups)) (nth part groups)))
        (setf (gethash index seen) t (aref result index) (pop (nth part groups)))
        (charge ledger :reassembly)))
    (assert (every #'null groups))
    (coerce result 'list)))

(defun quotient-values (values &optional ledger (category :quotient))
  "Return first-occurrence representatives and the complete occurrence-index residual."
  (let (reps residual)
    (dolist (v values (values reps (nreverse residual)))
      (let ((index (position v reps :test #'equal)))
        (unless index (setf index (length reps) reps (append reps (list v))))
        (charge ledger category (1+ (length reps)))
        (push index residual)))))

(defun restore-quotient (representatives residual &optional ledger)
  (let ((len (length representatives)))
    (mapcar (lambda (i) (checked-position i len) (charge ledger :reassembly) (nth i representatives)) residual)))

(defun quotient-model (type representatives residual &optional ledger)
  "Construct a reconstructing program using `(gather ...)` or `(at ...)`."
  (let ((model (if (ast-kind residual)
                   (term `(at ,(lit (sequence-type type) representatives) ,residual))
                   (term `(gather ,(lit (sequence-type type) representatives) ',residual)))))
    (charge ledger :construction (syntax-work model))
    model))

(defun partition-model (partition type &optional ledger)
  "Encode all part contents and their inverse permutation."
  (reassemble-partition partition ledger)
  (let* ((groups (partition-groups partition))
         (offsets (loop with off = 0 for g in groups collect (prog1 off (incf off (length g)))))
         (cursors (make-array (length groups) :initial-element 0))
         (perm (make-array (length (partition-positions partition)))))
    (dolist (pos (partition-positions partition))
      (destructuring-bind (idx part) pos
        (setf (aref perm idx) (+ (nth part offsets) (aref cursors part)))
        (incf (aref cursors part))))
    (quotient-model type (apply #'append groups) (coerce perm 'list) ledger)))

(defun partition-pairs-and-anchors (partition-or-rows &optional labels ledger)
  "Derive intra-block pairs and cross-block anchors from a partition or rows+labels."
  (let* ((part (if (partition-p partition-or-rows)
                   partition-or-rows
                   (partition-rows (if (frame-p partition-or-rows) (frame-rows partition-or-rows) partition-or-rows)
                                   labels ledger)))
         pairs anchors)
    (dolist (group (partition-groups part))
      (let ((keys (mapcar (lambda (x) (if (row-p x) (row-key x) x)) group)))
        (when (>= (length keys) 2)
          (push (copy-tree (first keys)) anchors)
          (loop for (a b) on keys while b
                do (charge ledger :orientation)
                   (push (list (copy-tree a) (copy-tree b)) pairs)))))
    (values (nreverse pairs) (when (>= (length anchors) 2) (nreverse anchors)) part)))

(defun with-frame-linkage (frame &key (edges nil edges-p) pairs anchors partition labels hard-p ledger)
  "Construct a new `frame` carrying updated `:edges`."
  (multiple-value-bind (dp da)
      (if (or partition labels) (partition-pairs-and-anchors (or partition (frame-rows frame)) labels ledger) (values nil nil))
    (charge ledger :orientation (length (frame-rows frame)))
    (derive-frame frame :edges (if edges-p edges (pairs-and-anchors->edges (or pairs dp) (or anchors da) hard-p)))))

(declaim (ftype function anti-unify pattern-holes))

(defun centered-mod-difference (predicted target modulus)
  "Minimal signed modular displacement DELTA in `[-floor(p/2), ceil(p/2)-1]`."
  (let ((raw (mod (- target predicted) modulus)))
    (if (> raw (floor modulus 2)) (- raw modulus) raw)))

(defun evaluate-frame-metric (metric predicted candidate type ledger &optional (budget 20000))
  "Evaluate explicit frame METRIC AST on `(PREDICTED CANDIDATE)` in TYPE."
  (when metric
    (let ((run (evaluate metric (list (cons 0 type) (cons 1 type)) (list predicted candidate)
                         :budget budget :ledger ledger)))
      (when (and (eq :value (evaluation-status run)) (integerp (evaluation-value run)) (>= (evaluation-value run) 0))
        (values (evaluation-value run) t)))))

(defun ast-hole-paths (pattern hole-id)
  "Return tree paths in PATTERN where `(hole HOLE-ID ...)` occurs."
  (let (hits)
    (labels ((walk (node rev-path)
               (cond ((and (hole-p node) (eql hole-id (ast-id node))) (push (nreverse (copy-list rev-path)) hits))
                     ((app-p node)
                      (walk (first node) (cons 0 rev-path))
                      (loop for a in (rest node) for i from 1 do (walk a (cons i rev-path)))))))
      (walk pattern nil) (nreverse hits))))

(defun replace-ast-at-paths (ast paths replacement)
  "Replace every subtree of AST located at PATHS with a copy of REPLACEMENT."
  (labels ((rep (node path)
             (cond ((null path) (copy-tree replacement))
                   ((app-p node)
                    (let ((p (first path)))
                      (if (zerop p)
                          (apply #'app (rep (first node) (rest path)) (rest node))
                          (apply #'app (first node)
                                 (loop for a in (rest node) for i from 1 collect (if (= i p) (rep a (rest path)) a))))))
                   (t (error "Invalid AST replacement path ~S in ~S" path ast)))))
    (reduce #'rep paths :initial-value ast)))

(defun match-code-var-substitution (predicted target scope)
  "If TARGET equals PREDICTED under substituting scope variables, return `((var-id . replacement) ...)`."
  (when (and scope (listp predicted) (listp target))
    (let (subs)
      (labels ((walk (p s)
                 (cond ((var-p p)
                        (let ((id (ast-id p)) (existing (assoc (ast-id p) subs :test #'eql)))
                          (and (assoc id scope) (equal (ast-type p) (expression-type s scope t))
                               (if existing (equal (cdr existing) s) (progn (push (cons id s) subs) t)))))
                       ((equal p s) t)
                       ((and (app-p p) (app-p s) (= (length (rest p)) (length (rest s))) (equal (first p) (first s)))
                        (every #'walk (rest p) (rest s))))))
        (when (walk predicted target) (nreverse subs))))))

(defun apply-code-metric-edit (predicted edit type)
  (declare (ignore type))
  (cond ((and (consp edit) (eq :subst (first edit))) (instantiate predicted (second edit) :var))
        ((and (consp edit) (eq :edit (first edit))) (replace-ast-at-paths predicted (second edit) (third edit)))
        (t edit)))

(defun compute-code-metric-delta (predicted target code-type &optional (tag-bits 2) ledger)
  "Attempt a compact `(:code-subst / :anti-unify)` edit transforming PREDICTED into TARGET."
  (when (and (code-type-p code-type) (not (equal predicted target)))
    (let ((scope (code-inputs code-type)) best-edit best-bits)
      (let ((vsubs (match-code-var-substitution predicted target scope)))
        (when (and vsubs (equal target (apply-code-metric-edit predicted (list :subst vsubs) code-type)))
          (setf best-edit (list :subst vsubs)
                best-bits (+ tag-bits (loop for (nil . sub) in vsubs
                                            sum (+ 1 (value-bit-size sub (code-type scope (expression-type sub scope t)))))))))
      (dolist (op-holes-p '(nil t))
        (multiple-value-bind (pat subs)
            (ignore-errors (anti-unify (list predicted target) scope ledger :operator-holes-p op-holes-p))
          (let ((holes (and pat (pattern-holes pat))))
            (when (and pat (not (hole-p pat)) (= 1 (length holes)))
              (let* ((h (first holes)) (htype (code-type scope (cdr h)))
                     (rep (cdr (assoc (car h) (second subs)))) (paths (ast-hole-paths pat (car h))))
                (when (and rep paths (valid-type-p htype)
                           (equal target (apply-code-metric-edit predicted (list :edit paths rep) code-type)))
                  (let ((rbits (ignore-errors (value-bit-size rep htype))))
                    (when rbits
                      (let ((bits (+ tag-bits (loop for p in paths sum (1+ (* 2 (length p)))) rbits)))
                        (when (or (null best-bits) (< bits best-bits))
                          (setf best-edit (list :edit paths rep) best-bits bits)))))))))))
      (when best-edit (values best-edit best-bits)))))

(defun library-metric-decoders (library target-type &optional (max-k 4))
  "Return up to MAX-K active `:metric-decoder` entries from LIBRARY matching TARGET-TYPE."
  (when library
    (let ((matches (stable-sort
                    (loop for e in (active-knowledge-entries-of-kind :metric-decoder library)
                          when (or (equal target-type (knowledge-entry-target e))
                                   (and (code-type-p target-type) (getf (knowledge-entry-metadata e) :any-code-target-p)))
                            collect e)
                    #'< :key (lambda (e) (or (getf (knowledge-entry-metadata e) :tag-bits) 2)))))
      (subseq matches 0 (min max-k (length matches))))))

(defun evaluate-metric-decoder-entry (entry predicted target type library ledger)
  "Evaluate `:metric-decoder` ENTRY on `(PREDICTED, TARGET)`. Returns `(VALUES delta bits info)`."
  (let* ((meta (knowledge-entry-metadata entry))
         (tag-bits (or (getf meta :tag-bits) 2)))
    (charge ledger :metric-evaluation 1)
    (if (and (eq :anti-unify (getf meta :solver-op)) (code-type-p type))
        (multiple-value-bind (edit bits) (compute-code-metric-delta predicted target type tag-bits ledger)
          (when edit (values edit bits (list :metric-decoder (knowledge-entry-id entry) :op (getf meta :decoder-op)))))
        (let ((q-ast (knowledge-entry-residual entry))
              (g-ast (knowledge-entry-guard entry))
              (delta-type (or (getf meta :delta-type) (cdr (second (knowledge-entry-inputs entry))))))
          (call-with-knowledge-library (or library *knowledge-library*)
           (lambda ()
             (multiple-value-bind (delta qs)
                 (when q-ast (eval-entry-slot entry :residual (list predicted target)
                                              :ledger ledger :category :metric-evaluation :check-types-p nil))
               (when (and (eq :value qs) (value-p delta delta-type))
                 (multiple-value-bind (dval ds)
                     (eval-entry-slot entry :expr (list predicted delta)
                                      :ledger ledger :category :metric-evaluation :check-types-p nil)
                   (when (and (eq ds :value) (equal dval target)
                              (or (equal g-ast (lit :bool t))
                                  (multiple-value-bind (gv gs)
                                      (eval-entry-slot entry :guard (list predicted delta)
                                                       :ledger ledger :category :metric-evaluation :check-types-p nil)
                                    (and (eq gs :value) gv))))
                     (values delta (+ tag-bits (value-bit-size delta delta-type))
                             (list :metric-decoder (knowledge-entry-id entry) :op (getf meta :decoder-op)))))))))))))

(defun correction (predicted target type &optional (predicted-p t) metric (library *knowledge-library*) ledger)
  "Compute minimal `(VALUES packet bits metric-info)` rebuilding TARGET from PREDICTED in TYPE."
  (flet ((replacement () (values target (value-bit-size target type)))
         (delta (diff) (values diff (value-bit-size diff :int)))
         (parts (ptypes unequal-bits)
           (loop for p in predicted for tr in target for pt in ptypes
                 for (pkt bits) = (multiple-value-list (correction p tr pt t nil library ledger))
                 collect pkt into pkts
                 sum (if (equal p tr) 1 (+ unequal-bits bits)) into tot
                 finally (return (values pkts tot)))))
    (if (not predicted-p)
        (values target (value-bit-size target type) nil)
        (multiple-value-bind (def-pkt def-bits)
            (case type
              (:int (delta (- target predicted)))
              (:bool (values target 1))
              (otherwise
               (ecase (first type)
                 (:gf (delta (centered-mod-difference predicted target (second type))))
                 (:tuple (parts (rest type) 0))
                 (:seq (if (and (listp predicted) (listp target))
                           (let ((et (second type)) (ld (- (length target) (length predicted)))
                                 (tail (nthcdr (length predicted) target)))
                             (multiple-value-bind (pkts sbits) (parts (mapcar (constantly et) predicted) 1)
                               (values (list :seq-delta ld pkts (copy-tree tail))
                                       (min (value-bit-size target type)
                                            (+ (if (zerop ld) 1 (1+ (value-bit-size ld :int)))
                                               sbits (loop for e in tail sum (value-bit-size e et)))))))
                           (replacement)))
                 (:code (replacement)))))
          (when (equal predicted target) (return-from correction (values def-pkt 0 nil)))
          (when metric
            (multiple-value-bind (ms mok) (evaluate-frame-metric metric predicted target type ledger)
              (when mok (return-from correction (values def-pkt (max 1 ms) :explicit-metric)))))
          (let ((best-pkt def-pkt) (best-bits def-bits) (best-info nil))
            (dolist (entry (library-metric-decoders library type 4))
              (let* ((meta (knowledge-entry-metadata entry))
                     (tb (or (getf meta :tag-bits) 2))
                     (dop (getf meta :decoder-op))
                     (min-db (if (and (eq :* dop) (eq type :int) (not (eql 0 target))) 4 1)))
                (unless (or (<= best-bits (+ tb min-db))
                            (and (eq :+ dop) (>= tb 0) (or (eq type :int) (gf-type-p type))))
                  (multiple-value-bind (delta bits info)
                      (evaluate-metric-decoder-entry entry predicted target type library ledger)
                    (when (and bits (< bits best-bits))
                      (setf best-pkt (if (eq :anti-unify (getf meta :solver-op))
                                         (list :metric-decoder (knowledge-entry-id entry) :code-edit delta)
                                         (list :metric-decoder (knowledge-entry-id entry)
                                               (ast->sexp (knowledge-entry-expression entry)) (copy-tree delta)))
                            best-bits bits best-info info))))))
            (values best-pkt best-bits best-info))))))

(defun correction-packet (predicted target type &optional (predicted-p t) metric (library *knowledge-library*) ledger)
  "Construct an executable correction packet transforming PREDICTED into TARGET in TYPE."
  (values (correction predicted target type predicted-p metric library ledger)))

(defun apply-correction-packet (predicted packet type &optional (predicted-p t) metric (library *knowledge-library*) ledger)
  "Apply PACKET from `correction-packet` to PREDICTED in TYPE."
  (declare (ignore metric))
  (cond
    ((not predicted-p) packet)
    ((and (consp packet) (eq :metric-decoder (first packet)))
     (if (eq :code-edit (third packet))
         (apply-code-metric-edit predicted (fourth packet) type)
         (call-with-knowledge-library (or library *knowledge-library*)
          (lambda ()
            (let* ((entry (find-knowledge-entry (second packet) *knowledge-library*))
                   (delta (fourth packet))
                   (dtype (or (and entry (or (getf (knowledge-entry-metadata entry) :delta-type)
                                             (cdr (second (knowledge-entry-inputs entry)))))
                              (infer-domain-from-types (list delta)) :int))
                   (dast (if entry (knowledge-entry-expression entry) (sexp->ast (third packet))))
                   (run (evaluate dast (list (cons 0 type) (cons 1 dtype)) (list predicted delta)
                                  :budget 20000 :ledger ledger)))
              (assert (eq :value (evaluation-status run)) () "Metric decoder packet ~S failed on ~S" packet predicted)
              (evaluation-value run))))))
    (t
     (case type
       (:int (+ predicted packet))
       (:bool packet)
       (otherwise (ecase (first type)
                    (:gf (mod (+ predicted packet) (second type)))
                    (:tuple (loop for pp in predicted for pk in packet for pt in (rest type)
                                  collect (apply-correction-packet pp pk pt t nil library ledger)))
                    (:seq (if (and (listp predicted) (consp packet) (eq :seq-delta (first packet)))
                              (append (loop for pp in predicted for pk in (third packet)
                                            collect (apply-correction-packet pp pk (second type) t nil library ledger))
                                      (copy-tree (fourth packet)))
                              packet))
                    (:code packet)))))))

(defun correction-bit-size (predicted target type &optional (predicted-p t) metric (library *knowledge-library*) ledger)
  "Price the correction packet from PREDICTED to TARGET in TYPE in bits."
  (nth-value 1 (correction predicted target type predicted-p metric library ledger)))

(defun select-closest-witness (predicted values type &optional (predicted-p t) metric (library *knowledge-library*) ledger)
  "Select W in VALUES minimizing `correction-bit-size`. Returns `(VALUES w bits pkt info)`."
  (assert (and (listp values) values))
  (let (bw bb bp bi)
    (dolist (c values (values bw bb bp bi))
      (multiple-value-bind (p b i) (correction predicted c type predicted-p metric library ledger)
        (when (or (null bb) (< b bb)) (setf bw c bb b bp p bi i))))))

(defun minimum-disambiguation-bit-size (type)
  (case type (:int (value-bit-size 1 :int)) (:bool 1)
    (otherwise (ecase (first type)
                 (:gf (value-bit-size 1 :int))
                 (:tuple (+ (1- (length (rest type))) (reduce #'min (rest type) :key #'minimum-disambiguation-bit-size)))
                 ((:seq :code) (1+ (type-bit-size type)))))))

(defun pair-connected-component (seed-key pairs)
  (let ((visited (list seed-key)) (queue (list seed-key)))
    (loop while queue for cur = (pop queue) do
      (dolist (pair pairs)
        (let ((nb (cond ((equal cur (first pair)) (second pair))
                        ((equal cur (second pair)) (first pair)))))
          (when (and nb (not (member nb visited :test #'equal)))
            (push nb visited) (setf queue (append queue (list nb)))))))
    (nreverse visited)))
