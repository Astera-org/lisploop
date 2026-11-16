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
  anchors
  ;; An optional metric of the problem's own: an :int expression over ((0 . target)
  ;; (1 . target)), the bits it takes to correct a predicted value 0 to the value 1.
  metric
  ;; Typed relations between rows, each (kind key-a key-b) over row keys. A model must give
  ;; the two rows of an :equal edge the same value and those of a :distinct edge different
  ;; ones; exact search enforces both. A :persistence edge records that the two rows are
  ;; neighbours in an induced order, and constrains nothing.
  edges)

(defun derive-row (row &key (known (copy-tree (row-known row)))
                            (requirement (copy-tree (row-requirement row))))
  "A row with a copy of ROW's key and with KNOWN and REQUIREMENT, which default to copies
of ROW's own."
  (make-row :key (copy-tree (row-key row)) :known known :requirement requirement))

(defun snapshot-row (row)
  "A copy of ROW that shares no list structure with it."
  (derive-row row))

(defun derive-frame (frame &key (rows (mapcar #'snapshot-row (frame-rows frame)))
                                (domain (schema-domain (frame-schema frame)))
                                (inputs (schema-inputs (frame-schema frame)))
                                (target (schema-target (frame-schema frame)))
                                (lookup-p (schema-lookup-p (frame-schema frame)))
                                (pairs (frame-pairs frame))
                                (anchors (frame-anchors frame))
                                (edges (frame-edges frame)))
  "A fresh frame that differs from FRAME only in the parts given: its rows, the fields of
its schema, and its linkage. A nil DOMAIN is inferred from the input and target types.
FRAME's metric goes with its target type and is dropped with it; the availability of the
inputs that remain is kept, and the target's while the target is the same. EDGES relate
values of the target, so a frame with another target must not inherit them."
  (let ((schema (frame-schema frame)))
    (make-frame (make-schema :domain domain :inputs inputs :target target :lookup-p lookup-p
                             :availability (remove-if-not (lambda (entry) (assoc (car entry) inputs))
                                                          (schema-availability schema))
                             :target-availability (and (equal target (schema-target schema))
                                                       (schema-target-availability schema)))
                rows :pairs pairs :anchors anchors :edges edges
                :metric (and (equal target (schema-target schema)) (frame-metric frame)))))

(defun binding-inputs (bindings inputs)
  "The input list ((id . type) ...) of a child whose inputs BINDINGS, an alist of child
input ids to expressions over INPUTS, compute."
  (mapcar (lambda (binding) (cons (car binding) (expression-type (cdr binding) inputs)))
          bindings))

(defun snapshot-frame (frame)
  "Own the problem's mutable data before starting a resumable computation."
  (derive-frame frame :domain (copy-tree (schema-domain (frame-schema frame)))))

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
  (term `(= ,(var 0 type) ',value)))

(defun set-requirement (type values)
  "An explicit finite set of whole values: tuples are never split into marginal sets."
  (assert (every (lambda (v) (value-p v type)) values))
  (term `(member ,(var 0 type) ',values)))

(defun make-row (&key key known requirement)
  (assert requirement () "make-row requires :requirement")
  (%make-row :key key :known known :requirement requirement))

(defun metric-inputs (type)
  "The scope of a metric on TYPE: the predicted value, then the value it should have been."
  (list (cons 0 type) (cons 1 type)))

(defun hard-edges (frame)
  "The edges of FRAME that a model must satisfy: its :equal and :distinct edges."
  (remove :persistence (frame-edges frame) :key #'first))

(defun make-frame (schema rows &key pairs anchors metric edges)
  (assert (valid-type-p (schema-target schema)))
  (assert (every (lambda (edge)
                   (and (= 3 (length edge)) (member (first edge) '(:equal :distinct :persistence))))
                 edges))
  (assert (or (null metric)
              (eq :int (expression-type metric (metric-inputs (schema-target schema))))))
  (assert (valid-inputs-p (schema-inputs schema)))
  (assert (= (length rows) (length (remove-duplicates rows :key #'row-key :test #'equal))))
  (dolist (row rows)
    (assert (= (length (row-known row)) (length (schema-inputs schema))))
    (assert (every (lambda (value spec) (or (eq value :unresolved) (value-p value (cdr spec))))
                   (row-known row) (schema-inputs schema)))
    (assert (eq :bool (expression-type (row-requirement row)
                                       (list (cons 0 (schema-target schema)))))))
  (%make-frame :schema schema :rows (copy-list rows)
               :pairs (copy-tree pairs) :anchors (copy-tree anchors) :metric metric
               :edges (copy-tree edges)))

(defun find-var-type (expression &optional (id 0))
  (cond
    ((and (var-p expression) (= id (ast-id expression)))
     (ast-type expression))
    ((app-p expression)
     (some (lambda (child) (find-var-type child id)) (rest expression)))
    (t nil)))

(defun check-requirement (requirement value &key (budget 1000000) ledger type)
  "Evaluate REQUIREMENT on the candidate target VALUE of type TYPE. A requirement does not
record its target type, so without TYPE it is read off an occurrence of variable 0, then
off a top-level comparison's operand type, and is otherwise taken to be :int."
  (let ((target-type (or type
                         (find-var-type requirement 0)
                         (when (and (app-p requirement)
                                    (member (operator-name (first requirement)) '(:= :member)))
                           (operator-operand-type (first requirement)))
                         :int)))
    (evaluate requirement (list (cons 0 target-type))
              (list value) :budget budget :ledger ledger)))

(defun fold-necessary (requirement ledger budget &optional max-fibers)
  "Fold REQUIREMENT under the :necessary contract, which may weaken it but never rejects
a value it accepted."
  (fold-constants requirement :ledger ledger :budget budget :contract :necessary
                              :max-fibers max-fibers))

(defun conjoin-requirements (req1 req2 &key ledger (budget 10000))
  "Conjoin two row requirements over the same target variable and fold closed subtrees."
  (fold-necessary (bool-and req1 req2) ledger budget))

(defstruct (frame-conflict (:predicate frame-conflict-struct-p))
  kind
  keys
  known
  expression)

(defun unsatisfiable-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (null (ast-value expr))))

(defun unconstrained-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (eq t (ast-value expr))))

(defun constrained-row-p (row)
  "True when ROW's requirement is anything other than the trivial `'t`."
  (not (unconstrained-requirement-p (row-requirement row))))

(defun frame-constrained-row-count (frame)
  "Count rows in FRAME whose requirement is not trivially `'t`."
  (count-if #'constrained-row-p (frame-rows frame)))

(defun frame-min-resolved-rows (frame)
  "Minimum number of constrained rows that must resolve (not be :unresolved) for a candidate to be accepted."
  (min 2 (frame-constrained-row-count frame)))

(defun empty-sequence-row-p (row position)
  "True when ROW is constrained and its input at POSITION is the empty sequence."
  (and (constrained-row-p row) (null (nth position (row-known row)))))

(defun row-singleton-value (row)
  "Return (VALUES value t) when ROW's requirement allows exactly one explicit value."
  (let ((allowed (and (constrained-row-p row) (extract-allowed-values (row-requirement row)))))
    (when (and (consp allowed) (null (rest allowed)))
      (values (first allowed) t))))

(defun unconstrained-frame (frame target-type &key domain)
  "Clone FRAME's rows and inputs with target TARGET-TYPE and unconstrained `'t` requirements."
  (derive-frame frame
                :rows (mapcar (lambda (row) (derive-row row :requirement (lit :bool t)))
                              (frame-rows frame))
                :domain (or domain (schema-domain (frame-schema frame)))
                :target target-type :lookup-p nil :pairs nil :anchors nil :edges nil))

(defun frame-conflict-p (frame &key ledger (budget 10000))
  "Detect whether any row requirement in FRAME folds to `nil` or whether rows
sharing identical known inputs have mutually incompatible requirements.
Returns (VALUES conflict folded-frame), where FOLDED-FRAME is a fresh frame
carrying the folded row requirements when no conflict is detected."
  (let ((joints (make-hash-table :test #'equal))
        (folded-rows nil))
    (dolist (row (frame-rows frame))
      (let* ((folded (fold-necessary (row-requirement row) ledger budget))
             (conflict
               (cond ((unsatisfiable-requirement-p folded)
                      (make-frame-conflict :kind :unsatisfiable-row
                                           :keys (list (row-key row))
                                           :known (row-known row)
                                           :expression folded))
                     ((not (member :unresolved (row-known row)))
                      (nth-value 1 (join-same-input joints row folded
                                                    :ledger ledger :budget budget))))))
        (when conflict
          (return-from frame-conflict-p (values conflict nil)))
        (push (derive-row row :known (row-known row) :requirement folded) folded-rows)))
    (values nil (derive-frame frame :rows (nreverse folded-rows)))))

(defun join-same-input (joints row requirement &key ledger (budget 10000))
  "Conjoin REQUIREMENT, the folded requirement of ROW, with those of the rows that joined
before it under the same known inputs. JOINTS is an `equal` hash table from a fully resolved
input tuple to (joint . keys), the keys latest first; it is updated in place.
Returns (VALUES joint conflict), where CONFLICT reports the rows joined so far, in joining
order, when their joint requirement is unsatisfiable."
  (assert (not (member :unresolved (row-known row))))
  (let* ((known (row-known row))
         (earlier (gethash known joints))
         (keys (cons (row-key row) (cdr earlier)))
         (joint (if earlier
                    (conjoin-requirements (car earlier) requirement :ledger ledger :budget budget)
                    requirement)))
    (setf (gethash known joints) (cons joint keys))
    (values joint
            (when (and earlier (unsatisfiable-requirement-p joint))
              (make-frame-conflict :kind :incompatible-rows :keys (reverse keys)
                                   :known known :expression joint)))))

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
     (loop for (key . values) in records
           do (assert (= (length values) (length types)))
              (assert (every #'value-p values types))
              (charge ledger :orientation
                      (+ 1 (loop for value in values for type in types
                                 sum (value-work value type))))
           collect (make-row :key key :known (mapcar (lambda (i) (nth i values)) input-columns)
                             :requirement
                             (set-requirement
                              target (list (if (rest target-columns)
                                               (mapcar (lambda (i) (nth i values)) target-columns)
                                               (nth (first target-columns) values)))))))))

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
    ;; The table maps each tuple of known inputs to its first surviving witness.
    (let ((model (term `(lookup (tuple ,@(mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs))
                                ',(mapcar (lambda (group) (list (car group) (second group)))
                                          (reverse groups)))
                       (schema-target schema))))
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
  (loop for (nil . expression) in bindings
        for run = (evaluate expression inputs known :ledger ledger)
        for status = (evaluation-status run)
        collect (cond ((eq status :value) (evaluation-value run))
                      (default-on-failure-p
                       (default-value-for-type (expression-type expression inputs)))
                      ((and allow-unresolved-p (eq status :unresolved)) :unresolved)
                      (error-p (error "Context binding did not finish: ~S" run))
                      (t (return :error)))))

(defun pulled-back-row (row predicate bindings inputs dead-row-p ledger)
  "ROW of a parent frame over INPUTS as a child row that requires PREDICATE: its known inputs
are BINDINGS evaluated on ROW's own. A binding that fails takes a default value when
DEAD-ROW-P, the row constraining nothing, and is an error otherwise."
  (let ((known (evaluate-row-bindings bindings inputs (row-known row)
                                      :ledger ledger
                                      :allow-unresolved-p t
                                      :default-on-failure-p dead-row-p)))
    (charge ledger :pullback (syntax-work predicate))
    (derive-row row :known known :requirement predicate)))

(defun row-decoder-unresolved-p (row inputs decoder)
  "True when DECODER mentions an input whose value ROW leaves unresolved."
  (let ((free (ast-meta-free-vars (ensure-ast-meta decoder))))
    (loop for (id . nil) in inputs
          for value in (row-known row)
          thereis (and (eq value :unresolved) (member id free :test #'eql)))))

(defun partial-bindings-p (bindings)
  (some (lambda (binding) (not (provably-total-p (cdr binding)))) bindings))

(defun pullback-frame (parent decoder child-id child-type bindings &optional ledger)
  "B(z)=A(d(c,z)). BINDINGS is an alist of child input IDs to parent expressions.
The checker closes over encoded observations; the child receives only computed
bindings. No inverse values are enumerated."
  (let* ((schema (frame-schema parent))
         (inputs (schema-inputs schema))
         (decoder-inputs (acons child-id child-type inputs))
         (child-inputs (binding-inputs bindings inputs))
         (partial-p (partial-bindings-p bindings))
         (multi-row-p (> (length (frame-rows parent)) 1)))
    (assert (not (assoc child-id inputs)))
    (assert (equal (schema-target schema) (expression-type decoder decoder-inputs)))
    (derive-frame
     parent
     :domain nil :inputs child-inputs :target child-type :lookup-p nil
     ;; Only the identity decoder gives the child the parent's own values to relate.
     :edges (and (var-p decoder) (eql child-id (ast-id decoder)) (frame-edges parent))
     :rows
     (loop for row in (frame-rows parent) collect
       (let* ((constants (literal-bindings inputs (row-known row)))
              (predicate (if (row-decoder-unresolved-p row inputs decoder)
                             (lit :bool t)
                             (instantiate (row-requirement row)
                                          (list (cons 0 (instantiate
                                                         decoder
                                                         (acons child-id (var 0 child-type) constants)
                                                         :var)))
                                          :var))))
         (pulled-back-row row predicate bindings inputs
                          (and multi-row-p
                               (or (unconstrained-requirement-p (row-requirement row))
                                   (and partial-p
                                        (unconstrained-requirement-p (fold-constants predicate)))))
                          ledger))))))

(defun product-slot-frame (parent decoder slots child-id bindings &optional ledger (budget 10000))
  "The frame of one slot of a product. DECODER is an expression over PARENT's inputs and the
variables SLOTS, ((id . type) ...), of which CHILD-ID names this slot. A row keeps the
conjuncts of the folded parent requirement A(d(c, z_0 ... z_m)) that mention this slot
alone. Through an injective constructor the requirement is the conjunction of such
conjuncts over the slots; elsewhere a dropped conjunct only weakens it, so no slot of a
valid product is rejected. A row whose requirement folds to false stays false in every
slot. Pairs carry over, a product being equal only where its slots are; anchors do not.
Returns (VALUES frame coupled), the conjuncts that tie this slot to another as
(row-key . conjunct)."
  (let* ((schema (frame-schema parent))
         (inputs (schema-inputs schema))
         (child-type (cdr (assoc child-id slots)))
         (slot-ids (mapcar #'car slots))
         (rename (list (cons child-id (var 0 child-type))))
         (partial-p (partial-bindings-p bindings))
         (multi-row-p (> (length (frame-rows parent)) 1))
         (coupled nil))
    (assert (and child-type (null (intersection slot-ids (mapcar #'car inputs)))))
    (assert (equal (schema-target schema) (expression-type decoder (append slots inputs))))
    (values
     (derive-frame
      parent
      :domain nil :inputs (binding-inputs bindings inputs) :target child-type :lookup-p nil
      :anchors nil :edges nil
      :rows
      (loop for row in (frame-rows parent) collect
        (let* ((folded (if (row-decoder-unresolved-p row inputs decoder)
                           (lit :bool t)
                           (fold-necessary
                            (instantiate (row-requirement row)
                                         (list (cons 0 (instantiate
                                                        decoder
                                                        (literal-bindings inputs (row-known row))
                                                        :var)))
                                         :var)
                            ledger budget)))
               (own (unless (unsatisfiable-requirement-p folded)
                      (loop for conjunct in (extract-conjuncts folded)
                            for mentioned = (intersection slot-ids (free-vars conjunct))
                            if (equal mentioned (list child-id))
                              collect (instantiate conjunct rename :var)
                            else if (member child-id mentioned)
                                   do (push (cons (row-key row) conjunct) coupled)
                            ;; A closed conjunct that did not fold away still has to hold.
                            else if (and (null mentioned) (not (unconstrained-requirement-p conjunct)))
                                   collect conjunct)))
               (predicate (cond ((unsatisfiable-requirement-p folded) folded)
                                (own (reduce #'bool-and own :from-end t))
                                (t (lit :bool t)))))
          (pulled-back-row row predicate bindings inputs
                           (and multi-row-p
                                (or (unconstrained-requirement-p (row-requirement row))
                                    (and partial-p (unconstrained-requirement-p predicate))))
                           ledger))))
     (nreverse coupled))))

;;; Composition. A model goes back into its parent's scope by substitution or, where that
;;; would compute one value several times, under a let: quoted code applied by `:code-eval`.

(defun scoped-bits (expression width)
  "The body bits of EXPRESSION in a scope whose variable references take WIDTH bits each."
  (let ((meta (ensure-ast-meta expression)))
    (+ (ast-meta-non-var-bits meta) (* (ast-meta-var-count meta) width))))

(defun reference-width (inputs expression)
  "The bits of a variable reference in the scope INPUTS or, when INPUTS is nil, in the
smallest scope that declares the variables of EXPRESSION."
  (integer-length (max 0 (1- (if inputs
                                 (length (input-alist inputs))
                                 (length (ast-meta-free-vars (ensure-ast-meta expression))))))))

(defun expression-variables (expression)
  "The variables of EXPRESSION outside quoted code, as an (id . type) alist in order of
first occurrence."
  (let ((found nil))
    (labels ((walk (node)
               (cond ((var-p node)
                      (pushnew (cons (ast-id node) (ast-type node)) found :key #'car))
                     ((app-p node) (mapc #'walk (rest node))))))
      (walk expression)
      (nreverse found))))

(defun variable-use-count (expression id)
  "How often variable ID occurs in EXPRESSION outside quoted code."
  (cond ((var-p expression) (if (eql id (ast-id expression)) 1 0))
        ((app-p expression)
         (loop for part in (rest expression) sum (variable-use-count part id)))
        (t 0)))

(defun let-call (body bindings)
  "`(code-eval 'BODY e ...)`: BODY quoted over the ids of the BINDINGS ((id . expression) ...)
it mentions and applied to their expressions, each of which is then evaluated once.
Returns nil unless that has the value and the definedness of substituting them: BODY must
be provably total by itself and mention bound ids only, and a binding that is not provably
total must be demanded on every path through BODY, since the call evaluates it eagerly."
  (let* ((free (ast-meta-free-vars (ensure-ast-meta body)))
         (used (remove-if-not (lambda (binding) (member (car binding) free)) bindings))
         (demanded (demanded-vars body)))
    (when (and used
               (provably-total-p body)
               (subsetp free (mapcar #'car used))
               (every (lambda (binding)
                        (or (provably-total-p (cdr binding)) (member (car binding) demanded)))
                      used))
      (let ((type (code-type (loop for (id . expression) in used
                                   collect (cons id (ast-type expression)))
                             (ast-type body))))
        (apply #'app (op :code-eval type) (lit type body) (mapcar #'cdr used))))))

(defun bind-model (body bindings width)
  "BODY, an expression over the ids of BINDINGS, in the scope of the bindings' expressions:
by substitution or, when a binding that is not a leaf is mentioned more than once and
`let-call` is smaller at WIDTH bits per variable reference, under that let."
  (let ((inline (instantiate body bindings :var))
        (meta (ensure-ast-meta body)))
    (or (and (> (ast-meta-var-count meta) (length (ast-meta-free-vars meta)))
             (some (lambda (binding)
                     (and (app-p (cdr binding)) (> (variable-use-count body (car binding)) 1)))
                   bindings)
             (let ((shared (let-call body bindings)))
               (and shared (< (scoped-bits shared width) (scoped-bits inline width)) shared)))
        inline)))

(defun compose-model (decoder child-id child-model bindings &optional ledger inputs)
  "DECODER with the model of its child in place of the variable CHILD-ID, the child's inputs
being computed by BINDINGS. A value is substituted where it is used. A binding the child
model mentions more than once, or a child the decoder mentions more than once, is instead
evaluated once and passed to quoted code by `:code-eval`, when that is smaller and keeps the
model's definedness (`let-call`). INPUTS, the scope of the result, prices variable
references; without it the variables the result mentions stand in for the scope."
  (let* ((width (reference-width
                 inputs
                 (unless inputs
                   (instantiate decoder
                                (list (cons child-id (instantiate child-model bindings :var))) :var))))
         (child (bind-model child-model bindings width))
         (variables (expression-variables decoder))
         ;; The decoder as a let of its child, whose other arguments are its own variables.
         (model (bind-model decoder
                            (loop for (id . type) in variables
                                  collect (cons id (if (eql id child-id) child (var id type))))
                            width)))
    (charge ledger :composition (syntax-work model))
    model))

(defun compose-product-model (decoder slot-models bindings &optional ledger inputs)
  "DECODER with SLOT-MODELS, ((slot-id . model) ...) over the ids of BINDINGS, in place of its
slot variables. When the decoder mentions nothing but its slots, the product is one
expression over the bindings, which are then bound around all of it at once; otherwise each
slot model is bound by itself. Sharing follows `compose-model`."
  (let* ((width (reference-width
                 inputs
                 (unless inputs
                   (instantiate decoder
                                (loop for (id . model) in slot-models
                                      collect (cons id (instantiate model bindings :var)))
                                :var))))
         (variables (expression-variables decoder)))
    (flet ((product (models)
             ;; The decoder over MODELS for its slots and itself for its other variables.
             (bind-model decoder
                         (loop for (id . type) in variables
                               collect (cons id (or (cdr (assoc id models)) (var id type))))
                         width)))
      (let ((model (if (subsetp (mapcar #'car variables) (mapcar #'car slot-models))
                       (bind-model (product slot-models) bindings width)
                       (product (loop for (id . model) in slot-models
                                      collect (cons id (bind-model model bindings width)))))))
        (charge ledger :composition (syntax-work model))
        model))))

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

(defun congruence-close-code-evals (row-reqs extra-knowns code-var &key ledger (budget 10000))
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
                                        (cond ((equal sub c)
                                               (push c new-conjuncts))
                                              (t
                                               (setf row-changed t changed t)
                                               (push (fold-necessary sub ledger budget)
                                                     new-conjuncts))))
                                      (push c new-conjuncts))))
                              (if row-changed
                                  (fold-necessary (reduce #'bool-and (nreverse new-conjuncts)
                                                          :from-end t :initial-value (lit :bool t))
                                                  ledger budget)
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
               (cond ((not (and (app-of-p c :if)
                                (not (and (lit-p (fourth c)) (null (ast-value (fourth c)))))
                                (app-of-p (second c) :code-eval)
                                (equal (second (second c)) code-var)))
                      (push c out))
                     ((unsatisfiable-requirement-p (third c))
                      (push (term `(= ,(second c) nil)) out)
                      (mapc #'expand (extract-conjuncts (fourth c))))
                     (t
                      (push (second c) out)
                      (mapc #'expand (extract-conjuncts (third c)))))))
      (mapc #'expand raw)
      (nreverse out))))

(defun select-active-fiber-rows (rows max-active-rows)
  "When ROWS exceeds MAX-ACTIVE-ROWS, partition ROWS into (VALUES active-rows reserve-rows),
retaining all unsatisfiable rows, a 3:1 locality-to-canonical contiguous window per parent row
(preserving adjacent fiber pairs (0, 1) and boundary occurrences), and diverse input values."
  (if (or (null max-active-rows) (<= (length rows) max-active-rows))
      (values rows nil)
      (let ((selected (make-hash-table :test #'eq))
            (by-parent (make-hash-table :test #'equal))
            (parent-keys nil)
            (seen-first-arg (make-hash-table :test #'equal))
            (locality-limit (max 2 (ceiling (* 3 max-active-rows) 4)))
            (count 0))
        (flet ((pick (r)
                 (unless (gethash r selected)
                   (setf (gethash r selected) t)
                   (incf count))))
          ;; 1. Always keep unsatisfiable rows so conflicts are detected immediately
          (dolist (r rows)
            (when (unsatisfiable-requirement-p (row-requirement r))
              (pick r)))
          ;; 2. Group by parent row key in parent-row order and keep contiguous adjacent pair (0, 1)
          ;;    plus right boundary within the 75% locality quota
          (dolist (r rows)
            (let ((pkey (if (consp (row-key r)) (first (row-key r)) (row-key r))))
              (unless (gethash pkey by-parent)
                (push pkey parent-keys))
              (push r (gethash pkey by-parent))))
          (setf parent-keys (nreverse parent-keys))
          (dolist (pkey parent-keys)
            (let ((ordered (reverse (gethash pkey by-parent))))
              (when (< count max-active-rows)
                (pick (first ordered)))
              (when (and (< count max-active-rows) (rest ordered))
                (pick (second ordered)))
              (when (and (< count locality-limit) (cddr ordered))
                (pick (car (last ordered))))))
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

(defun code-call-row (key call extra requirement)
  "The child row that CALL, a :code-eval application, asks for: its known inputs are the
call's literal arguments (:unresolved where an argument is not a literal) followed by a
copy of EXTRA, the values of the bound parent inputs."
  (make-row :key key
            :known (append (mapcar (lambda (arg)
                                     (if (lit-p arg) (copy-tree (ast-value arg)) :unresolved))
                                   (cddr call))
                           (copy-tree extra))
            :requirement requirement))

(defun default-known (inputs)
  "A canonical witness value for each of INPUTS, in order."
  (mapcar (lambda (input) (default-value-for-type (cdr input))) inputs))

(defun probe-frame-coordinates (frame decoder child-id child-type
                                &optional bindings ledger
                                &key (coordinates '((0) (1))) (budget 4000))
  "Project sequence/grid requirements of FRAME at COORDINATES (each a list of integer indices,
e.g. '((0) (1)) for 1D or '((0 0) (0 1) (1 0) (1 1)) for 2D) through DECODER without unfolding
the full sequence or matrix spine."
  (let* ((raw (pullback-frame frame decoder child-id child-type bindings ledger))
         (code-p (code-type-p child-type))
         (ret (if code-p (code-sort child-type) child-type))
         (target-type (schema-target (frame-schema frame)))
         (probed-target nil)
         (probed-rows nil))
    (labels ((project-coord (expr val type coord)
               (if (null coord)
                   (values (term `(= ,expr ',val)) type val)
                   (when (and (seq-type-p type) (listp val))
                     (let* ((raw-idx (first coord))
                            (idx (if (minusp raw-idx) (+ (length val) raw-idx) raw-idx))
                            (elem-type (second type)))
                       (when (and (<= 0 idx) (< idx (length val)))
                         (project-coord (term `(at ,expr ,idx))
                                        (nth idx val)
                                        elem-type
                                        (rest coord))))))))
      (dolist (row (frame-rows raw))
        ;; COMPOUND is the decoded term that the row pins to the value of WITNESS.
        (multiple-value-bind (compound compound-type witness)
            (match-literal-equality (row-requirement row) :singleton-member-p t)
          (declare (ignore compound-type))
          (if (and compound (seq-type-p target-type))
              (dolist (coord coordinates)
                (multiple-value-bind (proj leaf-type leaf-val)
                    (project-coord compound (ast-value witness) target-type coord)
                  (when proj
                    (setf probed-target leaf-type)
                    (let* ((key (list (row-key row) coord))
                           (folded (fold-necessary proj ledger budget
                                                   (+ 2 (reduce #'max coord :initial-value 1))))
                           (call (when code-p
                                   (extract-outermost-code-eval folded (var 0 child-type)))))
                      (cond
                        ((not code-p)
                         (push (make-row :key key
                                         :known (copy-tree (row-known row))
                                         :requirement (if (equal compound (var 0 target-type))
                                                          (singleton-requirement leaf-type leaf-val)
                                                          folded))
                               probed-rows))
                        ((and call (every #'lit-p (cddr call)))
                         (push (code-call-row key call (row-known row)
                                              (replace-subexpression folded call (var 0 ret)))
                               probed-rows)))))))
              (unless code-p
                (push row probed-rows)))))
      (make-frame (make-schema :domain (schema-domain (frame-schema frame))
                               :inputs (append (when code-p (code-inputs child-type))
                                               (schema-inputs (frame-schema raw)))
                               :target (if code-p
                                           ret
                                           (or probed-target (schema-target (frame-schema raw)))))
                  (nreverse probed-rows)))))

(defun coupled-fallback-rows (coupled code-var ret child-inputs ledger budget)
  "One child row for each entry (parent-key occurrence extra conjunct) of COUPLED, whose
conjunct mentions CODE-VAR in more than one ground call or in a call that is not ground.
When replacing the conjunct's single outermost call by the child's value removes every
call, the row constrains that value at the call's arguments. Otherwise the row is a
placeholder at unresolved inputs."
  (loop for (key occ-idx extra c) in coupled
        collect
        (let* ((outer (extract-outermost-code-eval c code-var))
               (replaced (when outer (replace-subexpression c outer (var 0 ret))))
               (clean-p (and replaced
                             (multiple-value-bind (ground non-ground-p)
                                 (collect-code-eval-calls replaced code-var)
                               (not (or ground non-ground-p)))))
               (row (if clean-p
                        (code-call-row (list key :coupled occ-idx) outer extra
                                       (fold-necessary replaced ledger budget))
                        (make-row :key (list key :coupled occ-idx)
                                  :known (mapcar (constantly :unresolved) child-inputs)
                                  :requirement (singleton-requirement
                                                ret (default-value-for-type ret))))))
          (charge ledger :pullback (syntax-work (row-requirement row)))
          row)))

(defun lift-frame (parent decoder child-id child-type &optional bindings ledger (budget 10000)
                                                      (max-active-rows *max-active-lifted-rows*))
  "Lift a parent frame through a higher-order DECODER parameterized by CHILD-ID of (:code inputs ret)
into a 1-to-many child frame over the code parameter's inputs (plus any extra parent BINDINGS).
Unfolds DECODER on each parent row (capped at a partial fiber window when MAX-ACTIVE-ROWS is
specified), runs cross-row congruence closure on ground :code-eval calls, and emits one child
row per distinct ground call requirement.
Returns (VALUES lifted-frame coupled-conjuncts reserve-rows)."
  (assert (and (code-type-p child-type) (not (function-sort-p (code-sort child-type)))))
  (let* ((raw (pullback-frame parent decoder child-id child-type bindings ledger))
         (code-in (code-inputs child-type))
         (ret (code-sort child-type))
         (extra-in (schema-inputs (frame-schema raw)))
         (child-inputs (append code-in extra-in))
         (code-var (var 0 child-type))
         (ret-var (var 0 ret))
         (extra-knowns (mapcar #'row-known (frame-rows raw)))
         (max-fibers-per-row
           (when max-active-rows
             (max 4 (+ 2 (ceiling max-active-rows (max 1 (frame-constrained-row-count raw)))))))
         (closed-reqs
           (congruence-close-code-evals
            (mapcar (lambda (row)
                      (fold-necessary (row-requirement row) ledger budget max-fibers-per-row))
                    (frame-rows raw))
            extra-knowns code-var :ledger ledger :budget budget))
         (seen (make-hash-table :test #'equal)) ; (known requirement) of each row lifted so far
         (lifted-rows nil)
         (coupled nil))                         ; (parent-key occurrence extra conjunct)
    (assert (null (intersection (mapcar #'car code-in) (mapcar #'car extra-in))))
    (flet ((refuted-row (key extra)
             (make-row :key key
                       :known (append (default-known code-in) (copy-tree extra))
                       :requirement (lit :bool nil))))
      (loop for parent-row in (frame-rows raw)
            for key = (row-key parent-row)
            for req in closed-reqs
            for extra in extra-knowns
            do (if (unsatisfiable-requirement-p req)
                   (push (refuted-row (list key :unsat) extra) lifted-rows)
                   (loop for c in (flatten-lifted-conjuncts req code-var)
                         for occ-idx from 0
                         do (multiple-value-bind (ground non-ground-p)
                                (collect-code-eval-calls c code-var)
                              (cond
                                ((or non-ground-p (rest ground))
                                 (push (list key occ-idx extra c) coupled))
                                (ground
                                 (let* ((call (first ground))
                                        (row (code-call-row
                                              (list key occ-idx) call extra
                                              (fold-necessary
                                               (if (and (equal c call) (eq :bool ret))
                                                   (term `(= ,ret-var t))
                                                   (replace-subexpression c call ret-var))
                                               ledger budget)))
                                        (dedup-key (list (row-known row) (row-requirement row))))
                                   (unless (gethash dedup-key seen)
                                     (setf (gethash dedup-key seen) t)
                                     (charge ledger :pullback (syntax-work (row-requirement row)))
                                     (push row lifted-rows))))
                                ((unsatisfiable-requirement-p c)
                                 (push (refuted-row (list key occ-idx) extra) lifted-rows))))))))
    (setf lifted-rows (nreverse lifted-rows)
          coupled (nreverse coupled))
    (when (and coupled (null (rest lifted-rows)))
      (setf lifted-rows
            (append lifted-rows
                    (coupled-fallback-rows coupled code-var ret child-inputs ledger budget))))
    (multiple-value-bind (active-rows reserve-rows)
        (select-active-fiber-rows
         (or lifted-rows
             (list (make-row :key :vacuous :known (default-known child-inputs)
                             :requirement (lit :bool t))))
         max-active-rows)
      (values (make-frame (make-schema :inputs child-inputs :target ret) active-rows)
              (mapcar (lambda (entry) (cons (first entry) (fourth entry))) coupled)
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
                                          (mapcar #'cdr active-bindings))))
                 (term `(code-subst ,(lit full-code-type child-model) (tuple ,@tuple-args))
                       child-type))))
         (model (instantiate decoder (list (cons child-id code-expr)) :var)))
    (charge ledger :composition (syntax-work model))
    model))

(defun conserved-quantity-frame (obs-frame target-id conserved-expr constant-value &optional ledger)
  "Reorient a conserved observation C(u, T) = CONSTANT-VALUE on OBS-FRAME into a pulled-back
frame solving for column TARGET-ID in terms of the remaining columns u.
Returns (VALUES pulled-back-frame const-frame)."
  (let* ((inputs (schema-inputs (frame-schema obs-frame)))
         (target-pos (position target-id inputs :key #'car))
         (target-type (cdr (nth target-pos inputs)))
         (u-inputs (remove target-id inputs :key #'car))
         (c-type (expression-type conserved-expr inputs))
         (const-req (singleton-requirement c-type constant-value))
         (const-frame
           (derive-frame
            obs-frame
            :inputs u-inputs :target c-type :lookup-p nil :edges nil
            :rows (loop for row in (frame-rows obs-frame)
                        collect (derive-row row :known (loop for val in (row-known row)
                                                             for idx from 0
                                                             unless (= idx target-pos) collect val)
                                                :requirement const-req)))))
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
         (child-inputs (binding-inputs effective-bindings parent-inputs)))
    (assert (= (length labels) (length parent-rows)) ()
            "Label count (~D) must match parent row count (~D)"
            (length labels) (length parent-rows))
    (derive-frame
     parent
     :domain (if (eq label-type :bool) (schema-domain parent-schema) label-type)
     :inputs child-inputs :target label-type :lookup-p lookup-p :edges nil
     :rows (loop for row in parent-rows
                 for label in labels
                 collect (let* ((known (evaluate-row-bindings effective-bindings parent-inputs
                                                              (row-known row) :ledger ledger))
                                (req (singleton-requirement label-type label)))
                           (charge ledger :context-frame (syntax-work req))
                           (derive-row row :known known :requirement req))))))

(defun project-frame-rows (frame bindings &optional ledger)
  "Project FRAME's `row-known` values through BINDINGS (an alist of (child-id . parent-expr))."
  (if (null bindings)
      frame
      (let* ((parent-inputs (schema-inputs (frame-schema frame)))
             (child-inputs (binding-inputs bindings parent-inputs)))
        (derive-frame
         frame
         :inputs child-inputs
         :rows (loop for row in (frame-rows frame)
                     collect (let ((known (evaluate-row-bindings bindings parent-inputs
                                                                 (row-known row) :ledger ledger)))
                               (charge ledger :orientation (length known))
                               (derive-row row :known known)))))))

(defun orient-available (frame &optional ledger)
  "FRAME as a model of its target is allowed to see it: with only the inputs that its
schema's availability preorder places before the target (`available-inputs`). Rows, keys,
requirements and linkage are kept. Search for a conserved quantity may read every column;
a model of one column is searched on the oriented frame."
  (let* ((schema (frame-schema frame))
         (available (available-inputs schema)))
    (if (= (length available) (length (schema-inputs schema)))
        frame
        (project-frame-rows frame (identity-bindings available) ledger))))

(defun assert-inputs-available (frame)
  "Signal an error when FRAME offers a model an input its availability preorder withholds."
  (assert (equal (available-inputs (frame-schema frame)) (schema-inputs (frame-schema frame))) ()
          "The frame offers inputs that are not available to its target; orient it first (`orient-available`)."))

(defun shuffle-frame-rows (frame permutation &optional ledger)
  "Permute the physical storage order of FRAME's rows according to PERMUTATION
(a bijection of 0..N-1) while preserving declared coordinates and occurrence keys."
  (let* ((rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec)))
    (assert (= n (length permutation)))
    (assert (= n (length (remove-duplicates permutation :test #'eql))))
    (assert (every (lambda (idx) (and (integerp idx) (<= 0 idx) (< idx n))) permutation))
    (charge ledger :orientation n)
    (derive-frame frame :rows (loop for idx in permutation
                                    collect (snapshot-row (aref rows-vec idx))))))

(defun support-frame (scope-or-frame support &optional ledger)
  "Turn an observed membership residual into an ordinary Boolean synthesis frame.
Every occurrence stays present. The predictor receives only the original inputs."
  (let ((frame (if (frame-p scope-or-frame)
                   scope-or-frame
                   (observation-scope-frame scope-or-frame))))
    (assert (= (length support) (length (frame-rows frame))))
    (assert (every (lambda (value) (value-p value :bool)) support))
    (derive-frame
     frame
     :domain nil :target :bool :lookup-p nil :pairs nil :anchors nil :edges nil
     :rows (loop for row in (frame-rows frame) for member-p in support collect
             (let ((req (set-requirement :bool (list member-p))))
               (charge ledger :guard-frame
                       (+ 1 (syntax-work req)
                          (loop for value in (row-known row)
                                for input in (schema-inputs (frame-schema frame))
                                sum (value-work value (cdr input)))))
               (derive-row row :requirement req))))))

(defstruct partition positions groups)

(defun partition-rows (rows labels &optional ledger)
  "A supplied partition, with occurrence positions retained as its reassembly data."
  (assert (= (length rows) (length labels)))
  (multiple-value-bind (keys parts) (quotient-values labels ledger :partition)
    (make-partition
     :positions (loop for part in parts for index from 0 collect (list index part))
     :groups (loop for group below (length keys)
                   collect (loop for row in rows for part in parts
                                 when (= part group) collect row)))))

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

(defun quotient-values (values &optional ledger (category :quotient))
  "Return first-occurrence representatives and the complete occurrence-index residual.
The search for each value's representative is charged to CATEGORY."
  (let ((representatives nil) (residual nil))
    (dolist (value values)
      (let ((index (position value representatives :test #'equal)))
        (unless index
          (setf index (length representatives)
                representatives (append representatives (list value))))
        (charge ledger category (1+ (length representatives)))
        (push index residual)))
    (values representatives (nreverse residual))))

(defun restore-quotient (representatives residual &optional ledger)
  (let ((length (length representatives)))
    (mapcar (lambda (index)
              (checked-position index length)
              (charge ledger :reassembly)
              (nth index representatives)) residual)))

(defun quotient-model (type representatives residual &optional ledger)
  "Construct a reconstructing program charging representatives and occurrence indexes:
when RESIDUAL is a sequence of integer indices, emits batch `(gather 'R 'residual)`;
when RESIDUAL is an `:int` AST expression, emits per-row `(at 'R residual)`."
  (let ((model (if (ast-kind residual)
                   (term `(at ,(lit (sequence-type type) representatives) ,residual))
                   (term `(gather ,(lit (sequence-type type) representatives) ',residual)))))
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
    (charge ledger :orientation (length (frame-rows frame)))
    (derive-frame frame :pairs (or pairs derived-pairs) :anchors (or anchors derived-anchors))))

(defun centered-mod-difference (predicted target modulus)
  "Return the minimal signed modular displacement DELTA in [-floor(p/2), ceil(p/2)-1]
such that (mod (+ predicted delta) modulus) = (mod target modulus)."
  (let* ((raw (mod (- target predicted) modulus))
         (half (floor modulus 2)))
    (if (> raw half)
        (- raw modulus)
        raw)))

(defun correction (predicted target type &optional (predicted-p t))
  "The packet from which `apply-correction-packet` rebuilds TARGET given PREDICTED in TYPE,
and its price in bits, as (VALUES packet bits). An exact prediction costs 0 bits. When
PREDICTED-P is nil (e.g. evaluation failed with :error) the packet is the replacement
TARGET at its plain value price."
  (flet ((replacement ()
           (values target (value-bit-size target type)))
         (delta (difference)
           ;; Not capped by the replacement price: in GF(5), 3 to 4 costs 4 bits against 3.
           (values difference (value-bit-size difference :int)))
         (parts (part-types unequal-bits)
           ;; Packets of corresponding parts and their total price: an equal part costs
           ;; one bit, any other its own correction plus UNEQUAL-BITS.
           (loop for p-part in predicted
                 for t-part in target
                 for part-type in part-types
                 for (packet bits) = (multiple-value-list (correction p-part t-part part-type))
                 collect packet into packets
                 sum (if (equal p-part t-part) 1 (+ unequal-bits bits)) into total
                 finally (return (values packets total)))))
    (if (not predicted-p)
        (replacement)
        (multiple-value-bind (packet bits)
            (case type
              (:int (delta (- target predicted)))
              (:bool (values target 1))
              (otherwise
               (ecase (first type)
                 (:gf (delta (centered-mod-difference predicted target (second type))))
                 (:tuple (parts (rest type) 0))
                 (:seq
                  (if (and (listp predicted) (listp target))
                      (let ((elem-type (second type))
                            (len-delta (- (length target) (length predicted)))
                            (tail (nthcdr (length predicted) target)))
                        (multiple-value-bind (packets shared-bits)
                            (parts (mapcar (constantly elem-type) predicted) 1)
                          ;; The price is capped at replacement, yet the packet stays a delta.
                          (values (list :seq-delta len-delta packets (copy-tree tail))
                                  (min (value-bit-size target type)
                                       (+ (if (zerop len-delta)
                                              1
                                              (1+ (value-bit-size len-delta :int)))
                                          shared-bits
                                          (loop for t-elem in tail
                                                sum (value-bit-size t-elem elem-type)))))))
                      (replacement)))
                 (:code (code-edit predicted target type)))))
          (values packet (if (equal predicted target) 0 bits))))))

(defun code-edit (predicted target type)
  "The correction of the quoted expression PREDICTED to TARGET, both of the code TYPE, as
(VALUES packet bits): the subterms of TARGET at the positions where the two differ, which
their anti-unifier marks with holes, or TARGET itself when that is no dearer. An edit pays
for the number of positions, for each position by its index among the nodes of the
anti-unifier, and for each distinct subterm once; a position that repeats an earlier
subterm names it instead."
  (flet ((replacement () (values target (value-bit-size target type))))
    (if (function-sort-p (code-sort type))
        (replacement)
        (let* ((scope (code-inputs type))
               (unified (multiple-value-list
                         (anti-unify (list predicted target) scope nil :operator-holes-p nil)))
               (pattern (first unified))
               (fillings (second (second unified))) ; what the holes stand for in TARGET
               (index -1)
               (positions nil))         ; (node-index . hole-id) of each hole, in pre-order
          (labels ((walk (node)
                     (incf index)
                     (cond ((hole-p node) (push (cons index (ast-id node)) positions))
                           ((app-p node) (mapc #'walk (rest node))))))
            (walk pattern))
          (let ((bits (+ (positive-bit-size (1+ (length positions)))
                         (loop for (position . nil) in positions
                               sum (positive-bit-size (1+ position)))
                         (loop for (nil . filling) in fillings
                               sum (body-size filling scope))
                         (* (- (length positions) (length fillings))
                            (positive-bit-size (1+ (length fillings)))))))
            (if (and positions (< bits (value-bit-size target type)))
                (values (list :code-edit pattern fillings) bits)
                (replacement)))))))

(defun priced-correction (predicted target type &key (predicted-p t) metric decoders ledger)
  "`correction` under what the problem and the library know of TYPE, as (VALUES packet bits).
A frame's METRIC, an :int expression over `metric-inputs`, prices the correction by itself;
its packet is TARGET. Otherwise each of DECODERS, from `metric-decoders`, competes with the
built-in packet: a decoder d whose solver gives a delta with d(PREDICTED, delta) = TARGET
describes TARGET by that delta, for its tag and the bits of the delta. The programs run in
the VM and are charged to LEDGER."
  (multiple-value-bind (packet bits) (correction predicted target type predicted-p)
    (cond ((or (not predicted-p) (zerop bits)))
          (metric
           (let ((run (evaluate metric (metric-inputs type) (list predicted target) :ledger ledger)))
             (when (and (eq :value (evaluation-status run)) (plusp (evaluation-value run)))
               (setf packet target
                     bits (evaluation-value run)))))
          (t
           (dolist (decoder decoders)
             (multiple-value-bind (delta delta-bits) (metric-delta decoder predicted target type ledger)
               (when (and delta-bits (< delta-bits bits))
                 (setf packet (list :metric-decoder (first decoder) delta)
                       bits delta-bits))))))
    (values packet bits)))

(defun correction-packet (predicted target type &optional (predicted-p t))
  "Construct an executable correction packet transforming PREDICTED into TARGET in TYPE.
When PREDICTED-P is nil (e.g. evaluation failed with :error), returns the replacement TARGET."
  (values (correction predicted target type predicted-p)))

(defun apply-correction-packet (predicted packet type &optional (predicted-p t))
  "Apply a correction PACKET produced by `correction-packet` to PREDICTED in TYPE,
reconstructing the target witness value."
  (cond
    ((not predicted-p) packet)
    ((and (consp packet) (eq :metric-decoder (first packet)))
     ;; (:metric-decoder d delta): the library's decoder d rebuilds the target from the delta.
     (destructuring-bind (operator delta) (rest packet)
       (let ((run (evaluate (app operator (lit type predicted)
                                 (lit (second (second (operator-type operator))) delta))
                            nil nil)))
         (assert (eq :value (evaluation-status run)))
         (evaluation-value run))))
    (t
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
          (:seq (if (and (listp predicted) (consp packet) (eq :seq-delta (first packet)))
                    (let ((elem-type (second type)))
                      (append (loop for p-elem in predicted
                                    for pkt-elem in (third packet)
                                    collect (apply-correction-packet p-elem pkt-elem elem-type t))
                              (copy-tree (fourth packet))))
                    packet))
          (:code (if (and (consp packet) (eq :code-edit (first packet)))
                     (instantiate (second packet) (third packet))
                     packet))))))))

(defun correction-bit-size (predicted target type &optional (predicted-p t))
  "Price the correction packet from PREDICTED to TARGET in TYPE in bits.
Returns 0 when PREDICTED-P is true and (equal predicted target).
When PREDICTED-P is nil, falls back to replacement (value-bit-size target type)."
  (nth-value 1 (correction predicted target type predicted-p)))

(defun select-closest-witness (predicted values type &optional (predicted-p t)
                                                         &key metric decoders ledger)
  "Select the witness W in VALUES minimizing (correction-bit-size predicted W type predicted-p),
breaking ties by first appearance in VALUES. METRIC, DECODERS and LEDGER are those of
`priced-correction`.
Returns (VALUES best-witness best-bits best-packet)."
  (assert (and (listp values) values))
  (let (best-witness best-bits best-packet)
    (dolist (candidate values (values best-witness best-bits best-packet))
      (multiple-value-bind (packet bits)
          (priced-correction predicted candidate type :predicted-p predicted-p
                                                      :metric metric :decoders decoders :ledger ledger)
        (when (or (null best-bits) (< bits best-bits))
          (setf best-witness candidate
                best-bits bits
                best-packet packet))))))

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
