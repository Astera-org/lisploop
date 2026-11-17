(in-package #:lisploop)

;;; Conflict clauses from failed child frames: construction, UIP generalisation, DIP repair.

(defstruct (nogood-clause (:predicate nogood-clause-p))
  parent-id
  kind
  keys
  known
  bindings
  decoder
  child-id
  child-type
  parent-incompatible-p
  clause-expr
  parent-clause-expr)

(defun nogood-identity (clause)
  "What makes CLAUSE the same deduction as another: its parent, its kind, and the row keys
it names or, for a UIP generalisation, the conjuncts of its pattern, either in canonical order."
  (flet ((canonical (items)
           (sort (mapcar (lambda (item) (with-standard-io-syntax (prin1-to-string item))) items)
                 #'string<)))
    (list (nogood-clause-parent-id clause)
          (nogood-clause-kind clause)
          (if (eq :uip-clause (nogood-clause-kind clause))
              (canonical (mapcar #'ast->sexp (extract-conjuncts (nogood-clause-clause-expr clause))))
              (canonical (nogood-clause-keys clause))))))

(defun pure-projection-decomposition-p (proposal)
  "True when PROPOSAL is a pure dependency projection `decoder = (var child-id child-type)`."
  (and proposal
       (var-p (decomposition-decoder proposal))
       (= (ast-id (decomposition-decoder proposal))
          (decomposition-child-id proposal))))

(defun eval-expr-value (expr inputs known &optional ledger)
  "Evaluate EXPR on KNOWN under INPUTS in the VM and return (VALUES value ok-p)."
  (let ((run (evaluate expr inputs known :ledger ledger)))
    (if (eq :value (evaluation-status run))
        (values (evaluation-value run) t)
        (values nil nil))))

(defun normalize-proposal-decoder (decoder child-id child-type)
  "Normalize DECODER by replacing CHILD-ID with `(var 0 child-type)`."
  (when (and decoder child-id child-type)
    (instantiate decoder (list (cons child-id (var 0 child-type))) :var)))

(defun same-lifted-decoder-p (entry proposal)
  "True when NOGOOD-CLAUSE ENTRY and PROPOSAL lift through the same higher-order decoder."
  (and proposal
       (decomposition-lift-p proposal)
       (nogood-clause-decoder entry)
       (equal (nogood-clause-child-type entry) (decomposition-child-type proposal))
       (equal (normalize-proposal-decoder (nogood-clause-decoder entry)
                                          (nogood-clause-child-id entry)
                                          (nogood-clause-child-type entry))
              (normalize-proposal-decoder (decomposition-decoder proposal)
                                          (decomposition-child-id proposal)
                                          (decomposition-child-type proposal)))))

(defun proposal-parent-expressions (proposal parent-inputs)
  "Return the list of parent-scope AST expressions whose values determine PROPOSAL on parent rows."
  (let ((binding-exprs (mapcar #'cdr (decomposition-bindings proposal))))
    (if (pure-projection-decomposition-p proposal)
        binding-exprs
        (let* ((decoder (decomposition-decoder proposal))
               (child-id (decomposition-child-id proposal))
               (free-ids (remove child-id (free-vars decoder) :test #'eql))
               (decoder-vars (loop for id in free-ids
                                   for spec = (assoc id parent-inputs :test #'eql)
                                   when spec collect (var id (cdr spec)))))
          (remove-duplicates (append decoder-vars binding-exprs) :test #'equal)))))

(defun lifted-nogood-p (clause)
  "True when CLAUSE's keys name occurrences `(parent-row-key index)` on a lifted frame."
  (member (nogood-clause-kind clause) '(:lift-incompatible-rows :uip-clause)))

(defun parent-row-keys (keys)
  "KEYS with every lifted occurrence key `(parent-row-key index)` replaced by its parent row key."
  (mapcar (lambda (k) (if (consp k) (first k) k)) keys))

(defun nogood-parent-keys (clause)
  "The keys of the parent rows that CLAUSE names, directly or through their lifted occurrences."
  (let ((keys (nogood-clause-keys clause)))
    (if (lifted-nogood-p clause) (parent-row-keys keys) keys)))

(defun matched-parent-rows (keys rows)
  "The rows of ROWS named by KEYS, in order; nil unless there are at least two and all are present."
  (let ((matched (mapcar (lambda (k) (find k rows :key #'row-key :test #'equal)) keys)))
    (and (>= (length matched) 2) (every #'identity matched) matched)))

(defun shared-row-values (exprs inputs rows ledger)
  "Evaluate EXPRS on the first of ROWS, then on each later row until one fails or disagrees.
Returns (VALUES values agree-p)."
  (flet ((row-values (row)
           (evaluate-row-bindings (mapcar (lambda (expr) (cons nil expr)) exprs) inputs (row-known row)
                                  :ledger ledger :error-p nil)))
    (let ((shared (row-values (first rows))))
      (if (and (not (eq shared :error))
               (every (lambda (row) (equal shared (row-values row))) (rest rows)))
          (values shared t)
          (values nil nil)))))

(defun binding-equalities (exprs values inputs)
  "The equalities `(= expr 'value)` over EXPRS and VALUES in step, skipping unresolved values.
Every expression must be well scoped under INPUTS."
  (loop for expr in exprs
        for value in values
        do (expression-type expr inputs)
        unless (eq value :unresolved)
          collect (term `(= ,expr ',value))))

(defun equalities-conjunction (equalities)
  "The conjunction of EQUALITIES, or the true literal when there are none."
  (if equalities (reduce #'bool-and equalities :from-end t) (lit :bool t)))

(defun incompatible-rows-conflict (keys known)
  "A checked conflict: the rows named by KEYS cannot all be met under the context values KNOWN."
  (make-frame-conflict :kind :incompatible-rows :keys (copy-list keys) :known known
                       :expression (lit :bool nil)))

(defun build-nogood-clause (parent proposal conflict &optional ledger)
  "Construct a homoiconic S-expression nogood clause over PARENT's scope from a child CONFLICT."
  (let* ((parent-frame (synthesis-node-frame parent))
         (parent-inputs (schema-inputs (frame-schema parent-frame)))
         (keys (copy-list (frame-conflict-keys conflict)))
         (known (copy-tree (frame-conflict-known conflict)))
         (bindings (copy-tree (and proposal (decomposition-bindings proposal))))
         (binding-exprs (mapcar #'cdr bindings))
         (lift-p (and proposal (decomposition-lift-p proposal)))
         (parent-keys (if lift-p (parent-row-keys keys) keys))
         (matched-rows (matched-parent-rows parent-keys (frame-rows parent-frame)))
         ;; Parent-scope expressions whose values fix the lifted proposal on a parent row.
         (parent-exprs (and lift-p matched-rows (proposal-parent-expressions proposal parent-inputs)))
         (parent-incompatible-p
           (and (eq :incompatible-rows (frame-conflict-kind conflict))
                matched-rows
                (or (pure-projection-decomposition-p proposal)
                    (and lift-p
                         (every #'consp keys)
                         (not (equal (first parent-keys) (second parent-keys)))
                         (every (lambda (k) (equal (second k) (second (first keys)))) (rest keys))
                         (nth-value 1 (shared-row-values parent-exprs parent-inputs matched-rows ledger))))))
         (parent-clause-expr
           (when (and lift-p matched-rows)
             (equalities-conjunction
              (loop for expr in parent-exprs
                    for (shared agree-p) = (multiple-value-list
                                            (shared-row-values (list expr) parent-inputs matched-rows ledger))
                    when agree-p
                      append (binding-equalities (list expr) shared parent-inputs)))))
         (clause-expr
           (equalities-conjunction
            (if (and lift-p (code-type-p (decomposition-child-type proposal)))
                (let ((code-in (code-inputs (decomposition-child-type proposal))))
                  (append (binding-equalities (loop for (id . type) in code-in collect (var id type))
                                              known code-in)
                          (binding-equalities binding-exprs (nthcdr (length code-in) known) parent-inputs)))
                (binding-equalities binding-exprs known parent-inputs)))))
    (make-nogood-clause :parent-id (synthesis-node-id parent)
                        :kind (if lift-p
                                  :lift-incompatible-rows
                                  (frame-conflict-kind conflict))
                        :keys keys
                        :known known
                        :bindings bindings
                        :decoder (and proposal (copy-tree (decomposition-decoder proposal)))
                        :child-id (and proposal (decomposition-child-id proposal))
                        :child-type (and proposal (copy-tree (decomposition-child-type proposal)))
                        :parent-incompatible-p parent-incompatible-p
                        :clause-expr clause-expr
                        :parent-clause-expr (or parent-clause-expr clause-expr))))

(defun collect-frame-nogood-clauses (parent proposal frame primary-conflict &optional ledger (budget 1000))
  "Collect the `nogood-clause` for PRIMARY-CONFLICT plus any additional colliding `known`
buckets on a lifted FRAME so UIP anti-unification and DIP context introduction see all collisions."
  (let ((clauses (list (build-nogood-clause parent proposal primary-conflict ledger))))
    (when (and frame
               proposal
               (decomposition-lift-p proposal)
               (eq :incompatible-rows (frame-conflict-kind primary-conflict)))
      (let ((joints (make-hash-table :test #'equal))
            ;; input tuples whose collision already has a clause
            (collided (list (frame-conflict-known primary-conflict))))
        (dolist (row (frame-rows frame))
          (unless (member :unresolved (row-known row))
            (let ((folded (fold-constants (row-requirement row)
                                          :ledger ledger :budget budget)))
              (unless (or (unsatisfiable-requirement-p folded)
                          (member (row-known row) collided :test #'equal))
                (let ((extra-conflict
                        (nth-value 1 (join-same-input joints row folded
                                                      :ledger ledger :budget budget))))
                  (when extra-conflict
                    (push (row-known row) collided)
                    (push (build-nogood-clause parent proposal extra-conflict ledger)
                          clauses)))))))))
    (nreverse clauses)))

(defun infer-exprs-inputs (exprs)
  "Extract the ((var-id . type) ...) alist from all `var` nodes appearing in EXPRS."
  (let ((inputs nil))
    (labels ((walk (node)
               (cond
                 ((var-p node)
                  (let ((id (ast-id node))
                        (ty (ast-type node)))
                    (unless (assoc id inputs)
                      (push (cons id ty) inputs))))
                 ((app-p node)
                  (dolist (arg (rest node))
                    (walk arg))))))
      (dolist (e exprs) (walk e))
      (sort inputs #'< :key #'car))))

(defun anti-unify-nogood-clauses (nogoods &optional ledger)
  "Anti-unify the S-expression conflict clauses of NOGOODS (2 or more `nogood-clause`s)
to extract their Unique Implication Point (UIP) least general generalization pattern.
Returns (VALUES uip-clause pattern substitutions)."
  (let ((valid (remove-if-not (lambda (ng)
                                (and (not (eq :uip-clause (nogood-clause-kind ng)))
                                     (nogood-clause-clause-expr ng)))
                              nogoods)))
    (when (>= (length valid) 2)
      (let* ((first-ng (first valid))
             (compatible (remove-if-not
                          (lambda (ng)
                            (and (eql (nogood-clause-parent-id ng) (nogood-clause-parent-id first-ng))
                                 (eq (nogood-clause-kind ng) (nogood-clause-kind first-ng))
                                 (equal (nogood-clause-child-type ng) (nogood-clause-child-type first-ng))))
                          valid))
             (exprs (remove-duplicates (mapcar #'nogood-clause-clause-expr compatible)
                                       :test #'equal)))
        (when (>= (length exprs) 2)
          (multiple-value-bind (pattern substitutions)
              (anti-unify exprs (infer-exprs-inputs exprs) ledger)
            (let* ((parent-exprs (remove nil (mapcar #'nogood-clause-parent-clause-expr compatible)))
                   (unique-parent-exprs (remove-duplicates parent-exprs :test #'equal))
                   (parent-pattern (when (>= (length unique-parent-exprs) 2)
                                     (nth-value 0 (anti-unify unique-parent-exprs
                                                              (infer-exprs-inputs unique-parent-exprs)
                                                              ledger))))
                   (uip (copy-nogood-clause first-ng)))
              (setf (nogood-clause-kind uip) :uip-clause
                    (nogood-clause-parent-incompatible-p uip)
                    (every #'nogood-clause-parent-incompatible-p compatible)
                    (nogood-clause-clause-expr uip) pattern
                    (nogood-clause-parent-clause-expr uip)
                    (or parent-pattern (nogood-clause-parent-clause-expr first-ng)))
              (values uip pattern substitutions))))))))

(defun clause-expr-matches-known-p (clause-expr scope-inputs known ledger)
  "Check whether CLAUSE-EXPR (either a concrete Boolean S-expression or a UIP pattern
containing holes `?h`) holds on KNOWN under SCOPE-INPUTS in the VM."
  (let ((hole-env (make-hash-table :test #'eql))) ; hole id -> the value it stands for
    (labels ((value (expr) (eval-expr-value expr scope-inputs known ledger))
             (holds-p (expr) (multiple-value-bind (val ok) (value expr) (and ok (eq t val))))
             ;; Bind HOLE to the value of CLOSED, or compare it with the value already bound.
             (hole-equals-p (hole closed)
               (multiple-value-bind (val ok) (value closed)
                 (and ok
                      (multiple-value-bind (bound present-p) (gethash (ast-id hole) hole-env)
                        (if present-p
                            (equal bound val)
                            (progn (setf (gethash (ast-id hole) hole-env) val) t))))))
             (conjunct-holds-p (conjunct)
               (if (pattern-has-holes-p conjunct)
                   (and (app-of-p conjunct :=)
                        (let ((lhs (second conjunct))
                              (rhs (third conjunct)))
                          ;; Only an equation of a hole with a closed term constrains the match.
                          (cond ((and (hole-p rhs) (not (pattern-has-holes-p lhs))) (hole-equals-p rhs lhs))
                                ((and (hole-p lhs) (not (pattern-has-holes-p rhs))) (hole-equals-p lhs rhs))
                                (t t))))
                   (holds-p conjunct))))
      (cond
        ((or (null clause-expr) (equal clause-expr (lit :bool t))) t)
        ((pattern-has-holes-p clause-expr) (every #'conjunct-holds-p (extract-conjuncts clause-expr)))
        (t (holds-p clause-expr))))))

(defun pointwise-map-decoder-p (decoder child-id seq-id)
  "True when DECODER calls a defined function on the parent input X_SEQ-ID and on the child
code CHILD-ID, each passed as a bare variable, and that function maps the code over the list
element by element (`function-body-pointwise-map-p`)."
  (and (app-p decoder)
       (operator-p (first decoder))
       (let* ((definition (find-function-definition (operator-name (first decoder))))
              (inputs (and definition (function-definition-inputs definition)))
              (arguments (rest decoder)))
         (flet ((parameter-receiving (id)
                  ;; The id of the parameter that the variable ID is passed to, if any.
                  (let ((position (position-if (lambda (argument)
                                                 (and (var-p argument) (eql id (ast-id argument))))
                                               arguments)))
                    (and position (car (nth position inputs))))))
           (and definition
                (function-definition-body definition)
                (null (function-definition-oracle-table definition))
                (= (length inputs) (length arguments))
                (let ((seq-parameter (parameter-receiving seq-id))
                      (code-parameter (parameter-receiving child-id)))
                  (and seq-parameter code-parameter
                       (function-body-pointwise-map-p (function-definition-name definition) inputs
                                                      (function-definition-body definition)
                                                      seq-parameter code-parameter))))))))

(defun check-library-nogood-schemas (library parent proposal ledger)
  "Check whether a unary higher-order `:lift-p t` PROPOSAL on PARENT is refuted by any
persisted `:nogood-schema` entry in the knowledge LIBRARY. When refuted, returns
`(VALUES primary-conflict nogood-clauses)` without running full `lift-frame`.
The check pairs the i-th input element of a row with its i-th output element and calls two
occurrences of one input with different outputs a conflict. That reading is the decoder's
only when it maps its code over the parent's list element by element, so the check is made
for such a decoder (`pointwise-map-decoder-p`) and for no other: of a decoder that permutes
its list, or whose step reads more than one element, it would refute lifts that hold."
  (when (and parent
             proposal
             (decomposition-lift-p proposal)
             (null (decomposition-bindings proposal))
             (code-type-p (decomposition-child-type proposal)))
    (let* ((schemas (knowledge-entries-of-kind :nogood-schema library))
           (prop-ctype (decomposition-child-type proposal))
           (code-in (code-inputs prop-ctype))
           (parent-inputs (schema-inputs (frame-schema (synthesis-node-frame parent))))
           (prop-norm-dec (normalize-proposal-decoder (decomposition-decoder proposal)
                                                      (decomposition-child-id proposal)
                                                      prop-ctype)))
      (when (and schemas
                 (= 1 (length code-in))
                 (= 1 (length parent-inputs))
                 (pointwise-map-decoder-p (decomposition-decoder proposal)
                                          (decomposition-child-id proposal)
                                          (caar parent-inputs)))
        (let ((matching-schema
                (find-if (lambda (entry)
                           (let* ((meta (knowledge-entry-metadata entry))
                                  (e-cid (getf meta :child-id))
                                  (e-ctype (getf meta :child-type))
                                  (e-dec (knowledge-entry-auxiliary-code entry)))
                             (and e-dec e-cid e-ctype
                                  (equal e-ctype prop-ctype)
                                  (equal (normalize-proposal-decoder e-dec e-cid e-ctype)
                                         prop-norm-dec))))
                         schemas)))
          (when matching-schema
            (let* ((clause-expr (knowledge-entry-expression matching-schema))
                   (parent-frame (synthesis-node-frame parent))
                   (by-elem (make-hash-table :test #'equal))
                   (conflicts nil))
              (dolist (row (frame-rows parent-frame))
                (when (and (constrained-row-p row)
                           (= 1 (length (row-known row)))
                           (listp (first (row-known row))))
                  (let ((seq-in (first (row-known row)))
                        (allowed (extract-allowed-values (row-requirement row))))
                    (when (and (consp allowed)
                               (= 1 (length allowed))
                               (listp (first allowed))
                               (= (length seq-in) (length (first allowed))))
                      (loop for elem-in in seq-in
                            for elem-out in (first allowed)
                            for idx from 0
                            for occ-key = (list (row-key row) idx)
                            do (charge ledger :nogood-check 1)
                               (let ((prev (gethash elem-in by-elem)))
                                 (if (null prev)
                                     (setf (gethash elem-in by-elem)
                                           (list (row-key row) occ-key elem-out))
                                     (when (and (not (equal (first prev) (row-key row)))
                                                (not (equal (third prev) elem-out))
                                                (clause-expr-matches-known-p clause-expr
                                                                             code-in
                                                                             (list elem-in)
                                                                             ledger))
                                       (push (incompatible-rows-conflict (list (second prev) occ-key)
                                                                         (list elem-in))
                                             conflicts)))))))))
              (when conflicts
                (let* ((ordered (nreverse conflicts))
                       (clauses (mapcar (lambda (c) (build-nogood-clause parent proposal c ledger))
                                        ordered)))
                  (values (first ordered) clauses))))))))))

(defun check-parent-nogoods (job parent proposal ledger)
  "Deductively check whether PROPOSAL's context projection/lifting is refuted by any
`nogood-clause` (including anti-unified UIP clauses) already discovered on PARENT or
persisted in the job's knowledge library."
  (when (and job (synthesis-job-deductive-nogoods-p job) parent proposal
             (or (pure-projection-decomposition-p proposal)
                 (decomposition-lift-p proposal)))
    (let* ((parent-frame (synthesis-node-frame parent))
           (inputs (schema-inputs (frame-schema parent-frame)))
           (binding-exprs (mapcar #'cdr (decomposition-bindings proposal)))
           (pure-p (pure-projection-decomposition-p proposal)))
      (dolist (entry (synthesis-job-nogoods job))
        (let* ((parent-keys (nogood-parent-keys entry))
               (matched-rows (and (= (nogood-clause-parent-id entry) (synthesis-node-id parent))
                                  (matched-parent-rows parent-keys (frame-rows parent-frame)))))
          (when matched-rows
            ;; 1. Pure projection or cross-row parent incompatibility
            (when (or (and pure-p (eq :incompatible-rows (nogood-clause-kind entry)))
                      (nogood-clause-parent-incompatible-p entry))
              (if pure-p
                  (multiple-value-bind (known agree-p)
                      (shared-row-values binding-exprs inputs matched-rows ledger)
                    (when agree-p
                      (return-from check-parent-nogoods (incompatible-rows-conflict parent-keys known))))
                  (when (and (nth-value 1 (shared-row-values (proposal-parent-expressions proposal inputs)
                                                             inputs matched-rows ledger))
                             (clause-expr-matches-known-p (nogood-clause-parent-clause-expr entry)
                                                          inputs (row-known (first matched-rows)) ledger))
                    ;; The proposal's own context on the first row, or nil when it does not evaluate.
                    (let ((known (shared-row-values binding-exprs inputs (list (first matched-rows)) ledger)))
                      (return-from check-parent-nogoods (incompatible-rows-conflict parent-keys known))))))
            ;; 2. Lifted occurrence incompatibility across sibling higher-order proposals
            (when (and (lifted-nogood-p entry) (same-lifted-decoder-p entry proposal))
              (let* ((code-in (code-inputs (decomposition-child-type proposal)))
                     (code-known (subseq (nogood-clause-known entry)
                                         0 (min (length code-in) (length (nogood-clause-known entry))))))
                (when (or (nogood-clause-bindings entry)
                          (clause-expr-matches-known-p (nogood-clause-clause-expr entry)
                                                       code-in code-known ledger))
                  (multiple-value-bind (extra agree-p)
                      (shared-row-values binding-exprs inputs matched-rows ledger)
                    (when agree-p
                      (return-from check-parent-nogoods
                        (incompatible-rows-conflict (nogood-clause-keys entry)
                                                    (append code-known extra)))))))))))
      ;; 3. Persisted library `:nogood-schema` check on unary higher-order lifts
      (check-library-nogood-schemas (synthesis-job-knowledge job) parent proposal ledger))))

(defun conflict-distinct-parent-row-pairs (parent-frame nogoods)
  "Extract pairs `(row1 . row2)` of distinct parent rows from NOGOODS that collided."
  (let ((pairs nil))
    (dolist (ng nogoods (nreverse pairs))
      (when (and (or (lifted-nogood-p ng) (eq :incompatible-rows (nogood-clause-kind ng)))
                 (>= (length (nogood-clause-keys ng)) 2))
        (destructuring-bind (&optional r1 r2)
            (matched-parent-rows (subseq (nogood-parent-keys ng) 0 2) (frame-rows parent-frame))
          (when (and r1 (not (equal (row-key r1) (row-key r2))))
            ;; A key names one row of the frame, so equal keys give the same row objects.
            (pushnew (cons r1 r2) pairs :test #'equal)))))))

(defun candidate-dip-context-expressions (parent-frame language &key existing-bindings allow-sequence-p)
  "Generate candidate parent-scope expressions (0-step variables and 1-step operator
applications) that can serve as new intermediate context variables in DIP repairs."
  (let* ((inputs (schema-inputs (frame-schema parent-frame)))
         (existing-exprs (mapcar #'cdr existing-bindings))
         (candidates nil))
    (flet ((acceptable-type-p (type)
             (and (not (code-type-p type))
                  (or allow-sequence-p
                      (not (seq-type-p type)))))
           (add-cand (expr)
             (unless (member expr existing-exprs :test #'equal)
               (pushnew expr candidates :test #'equal))))
      (dolist (spec inputs)
        (when (acceptable-type-p (cdr spec))
          (add-cand (var (car spec) (cdr spec)))))
      (dolist (op-sym (language-operators language))
        (when (operator-p op-sym)
          (let* ((sig (operator-type op-sym))
                 (arg-types (second sig))
                 (ret-type (third sig)))
            (when (and (acceptable-type-p ret-type)
                       (not (member (operator-name op-sym) '(:= :< :if :tuple :cons))))
              (cond
                ((= 1 (length arg-types))
                 (dolist (spec inputs)
                   (when (equal (cdr spec) (first arg-types))
                     (add-cand (app op-sym (var (car spec) (cdr spec)))))))
                ((and (= 2 (length arg-types))
                      (eq :at (operator-name op-sym)))
                 (dolist (spec inputs)
                   (when (equal (cdr spec) (first arg-types))
                     (add-cand (app op-sym (var (car spec) (cdr spec)) (lit :int 0))))))
                ((= 2 (length arg-types))
                 (dolist (s1 inputs)
                   (when (equal (cdr s1) (first arg-types))
                     (dolist (s2 inputs)
                       (when (and (not (eql (car s1) (car s2)))
                                  (equal (cdr s2) (second arg-types)))
                         (add-cand (app op-sym
                                        (var (car s1) (cdr s1))
                                        (var (car s2) (cdr s2))))))))))))))
      (stable-sort (nreverse candidates) #'<
                   :key (lambda (e) (description-size e inputs))))))

(defun propose-dip-context-bindings (parent-frame language nogoods
                                     &key existing-bindings (max-candidates 2)
                                          allow-sequence-p ledger (library *knowledge-library*))
  "Dual Implication Point (DIP) context introduction: inspect conflicting parent row pairs
in NOGOODS and return up to MAX-CANDIDATES minimal total parent-scope expressions that
separate all distinct-row conflict pairs. The `:dip-feature` entries of the knowledge
LIBRARY are tried before the grammar's own candidates."
  (let* ((pairs (conflict-distinct-parent-row-pairs parent-frame nogoods))
         (inputs (schema-inputs (frame-schema parent-frame)))
         (existing-exprs (mapcar #'cdr existing-bindings))
         (constrained-rows (remove-if-not #'constrained-row-p (frame-rows parent-frame))))
    (when pairs
      (labels ((eval-candidate (expr-or-entry known)
                 (if (knowledge-entry-p expr-or-entry)
                     (multiple-value-bind (val status)
                         (eval-entry-slot expr-or-entry :expr known :ledger ledger)
                       (values val (eq status :value)))
                     (eval-expr-value expr-or-entry inputs known ledger)))
               (separates-all-p (cand)
                 (and (every (lambda (pair)
                               (multiple-value-bind (v1 ok1)
                                   (eval-candidate cand (row-known (car pair)))
                                 (multiple-value-bind (v2 ok2)
                                     (eval-candidate cand (row-known (cdr pair)))
                                   (and ok1 ok2 (not (equal v1 v2))))))
                             pairs)
                      (every (lambda (row)
                               (nth-value 1 (eval-candidate cand (row-known row))))
                             constrained-rows))))
        (let ((lib-separators
                (loop for entry in (knowledge-entries-of-kind :dip-feature library)
                      for expr = (knowledge-entry-expression entry)
                      when (and expr
                                (not (member expr existing-exprs :test #'equal))
                                (equal (ignore-errors (expression-type expr inputs))
                                       (knowledge-entry-target entry))
                                (separates-all-p (if (equal (knowledge-entry-inputs entry) inputs)
                                                     entry
                                                     expr)))
                        collect expr)))
          (if lib-separators
              (let ((deduped (remove-duplicates lib-separators :test #'equal :from-end t)))
                (subseq deduped 0 (min max-candidates (length deduped))))
              (let ((grammar-cands (candidate-dip-context-expressions parent-frame language
                                                                      :existing-bindings existing-bindings
                                                                      :allow-sequence-p allow-sequence-p))
                    (separators nil))
                (dolist (expr grammar-cands (nreverse separators))
                  (when (< (length separators) max-candidates)
                    (when (separates-all-p expr)
                      (push expr separators)))))))))))

(defun dip-repaired-decompositions (parent proposal nogoods
                                    &key (max-repairs 1) ledger (debug-p *synthesis-debug-mode*)
                                         (library *knowledge-library*))
  "Given a conflicting PROPOSAL on PARENT and its induced NOGOODS, use DIP context
introduction (`propose-dip-context-bindings`) to propose repaired decompositions with
an added intermediate context variable separating the conflicting parent rows."
  (when (and parent proposal nogoods
             (not (and (consp (decomposition-name proposal))
                       (eq :dip-repair (first (decomposition-name proposal)))))
             (or (decomposition-lift-p proposal)
                 (pure-projection-decomposition-p proposal)))
    (let* ((parent-frame (synthesis-node-frame parent))
           (parent-lang (synthesis-node-language parent))
           (parent-inputs (schema-inputs (frame-schema parent-frame)))
           (separators (propose-dip-context-bindings parent-frame parent-lang nogoods
                                                     :existing-bindings (decomposition-bindings proposal)
                                                     :max-candidates max-repairs
                                                     :ledger ledger :library library)))
      (loop for sep-expr in separators
            for sep-type = (expression-type sep-expr parent-inputs)
            for base-in = (if (decomposition-lift-p proposal)
                              (append (code-inputs (decomposition-child-type proposal))
                                      (decomposition-bindings proposal))
                              (decomposition-bindings proposal))
            for new-cid = (next-child-id base-in)
            for new-bindings = (append (copy-tree (decomposition-bindings proposal))
                                       (list (cons new-cid sep-expr)))
            for old-lang = (decomposition-language proposal)
            for new-lang-inputs = (append (copy-tree (language-inputs old-lang))
                                          (list (cons new-cid sep-type)))
            for new-lang = (derive-language old-lang :inputs new-lang-inputs)
            for repaired = (copy-decomposition-tree proposal)
            do (setf (decomposition-name repaired) (list :dip-repair (decomposition-name proposal) sep-expr)
                     (decomposition-bindings repaired) new-bindings
                     (decomposition-language repaired) new-lang
                     (decomposition-provenance repaired)
                     (when debug-p
                       (list :origin :dip-repair
                             :from (decomposition-name proposal)
                             :introduced-binding (cons new-cid sep-expr))))
            collect repaired))))
