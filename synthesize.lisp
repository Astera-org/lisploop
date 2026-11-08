(in-package #:lisploop)

;;; Shared orchestration. The DSL remains unchanged; recursion is in the search.

(defstruct (heuristic-search (:constructor %make-heuristic-search))
  observation bound (ledger (make-ledger)) (phase :prepare) (debt 0) record rows outcomes
  (resolved-rows 0) evaluation (index 0) residual (unresolved nil) (residual-bits 0) best (models nil) (run-weight 0))

(defun frame-has-empty-sequence-row-p (frame)
  "True when FRAME has a sequence input Xi whose value is empty ('()) on some constrained row."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (loop for (nil . type) in inputs
          for pos from 0
          thereis (and (consp type) (eq :seq (first type))
                       (some (lambda (row)
                               (and (not (unconstrained-requirement-p (row-requirement row)))
                                    (null (nth pos (row-known row)))))
                             (frame-rows frame))))))

(defun stage-a-observation-language (frame language)
  "When FRAME has an empty-sequence row, exclude partial sequence destructors, control operators,
and unverified oracle functions from Stage A unconditional observation."
  (if (not (frame-has-empty-sequence-row-p frame))
      language
      (let* ((target (schema-target (frame-schema frame)))
             (ops (remove-if (lambda (o)
                               (and (operator-p o)
                                    (or (member (operator-name o) '(:at :tail :if :=))
                                        (let ((def (find-function-definition (operator-name o))))
                                          (and def (function-definition-oracle-table def))))))
                             (language-operators language)))
             (lits (if (and (eq :int target) (listp (language-literals language)))
                       (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                       (language-literals language))))
        (make-language (language-domain language)
                       (language-inputs language)
                       :operators ops
                       :literals lits
                       :constants (language-constants language)))))

(defun start-heuristic-search (frame language &key description-limit (run-weight 0))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (let ((obs-language (stage-a-observation-language frame language)))
    (%make-heuristic-search
     :observation (start-observation-search (make-observation-scope frame obs-language) :retain-outcomes t)
     :debt (+ 1 (length (frame-pairs frame)) (length (frame-anchors frame))
              (loop for row in (frame-rows frame) sum (syntax-work (row-requirement row))))
     :bound (or description-limit (+ (header-size (schema-inputs (frame-schema frame))
                                                  (schema-target (frame-schema frame))) 18))
     :run-weight run-weight)))

(defun heuristic-search-step (job)
  (let* ((observation (heuristic-search-observation job))
         (frame (observation-scope-frame (observation-job-scope observation)))
         (type (schema-target (frame-schema frame)))
         (ledger (heuristic-search-ledger job)))
    (case (heuristic-search-phase job)
      (:prepare
       (charge ledger :heuristic-preparation) (decf (heuristic-search-debt job))
       (when (zerop (heuristic-search-debt job)) (setf (heuristic-search-phase job) :observe)))
      (:observe
       (let ((before (ledger-total (observation-job-ledger observation)))
             (records (observation-job-records observation)))
         (observation-step observation 1)
         (charge ledger :observation (- (ledger-total (observation-job-ledger observation)) before))
         (unless (eq records (observation-job-records observation))
           (setf (heuristic-search-record job) (first (observation-job-records observation))
                 (heuristic-search-rows job) (frame-rows frame)
                 (heuristic-search-outcomes job) (observed-expression-outcomes (heuristic-search-record job))
                 (heuristic-search-resolved-rows job) 0
                 (heuristic-search-index job) 0 (heuristic-search-residual job) nil
                 (heuristic-search-unresolved job) nil
                 (heuristic-search-residual-bits job) 0 (heuristic-search-phase job) :row))))
      (:row
       (charge ledger :heuristic-checking)
       (if (null (heuristic-search-rows job))
           (if (>= (heuristic-search-resolved-rows job) (frame-min-resolved-rows frame))
               (setf (heuristic-search-phase job) :score
                     (heuristic-search-debt job)
                     (+ (syntax-work (observed-expression-expression (heuristic-search-record job)))
                        (length (frame-pairs frame))
                        (length (frame-anchors frame))))
               (setf (heuristic-search-phase job) :observe))
           (let ((outcome (first (heuristic-search-outcomes job))))
             (case (observation-outcome-status outcome)
               (:value
                (setf (heuristic-search-evaluation job)
                      (start-evaluation (row-requirement (first (heuristic-search-rows job)))
                                        (list (cons 0 type)) (list (observation-outcome-value outcome)))
                      (heuristic-search-phase job) :check))
               (:unresolved
                (let* ((row (first (heuristic-search-rows job)))
                       (req (row-requirement row)))
                  (unless (unconstrained-requirement-p req)
                    (push (row-key row) (heuristic-search-unresolved job))
                    (let ((values (extract-allowed-values req)))
                      (when (and (listp values) values)
                        (incf (heuristic-search-residual-bits job)
                              (+ (positive-bit-size (1+ (heuristic-search-index job)))
                                 (nth-value 1 (select-closest-witness nil values type nil))))))))
                (setf (heuristic-search-phase job) :next))
               (otherwise
                (unless (unconstrained-requirement-p (row-requirement (first (heuristic-search-rows job))))
                  (incf (heuristic-search-resolved-rows job)))
                (setf (heuristic-search-phase job) :residual
                      (heuristic-search-debt job) (syntax-work (row-requirement (first (heuristic-search-rows job))))))))))
      (:check
       (let ((run (advance-accounted-evaluation (heuristic-search-evaluation job) 1 ledger
                                                :heuristic-checking :heuristic-checking)))
         (unless (eq :unknown (evaluation-status run))
           (setf (heuristic-search-debt job) (syntax-work (row-requirement (first (heuristic-search-rows job)))))
           (cond ((eq :unresolved (evaluation-status run))
                  (let* ((row (first (heuristic-search-rows job)))
                         (req (row-requirement row)))
                    (unless (unconstrained-requirement-p req)
                      (push (row-key row) (heuristic-search-unresolved job))
                      (let ((values (extract-allowed-values req)))
                        (when (and (listp values) values)
                          (incf (heuristic-search-residual-bits job)
                                (+ (positive-bit-size (1+ (heuristic-search-index job)))
                                   (nth-value 1 (select-closest-witness nil values type nil))))))))
                  (setf (heuristic-search-phase job) :next))
                 ((and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))
                  (unless (unconstrained-requirement-p (row-requirement (first (heuristic-search-rows job))))
                    (incf (heuristic-search-resolved-rows job)))
                  (setf (heuristic-search-phase job) :next))
                 (t
                  (unless (unconstrained-requirement-p (row-requirement (first (heuristic-search-rows job))))
                    (incf (heuristic-search-resolved-rows job)))
                  (setf (heuristic-search-phase job) :residual))))))
      (:residual
       (charge ledger :heuristic-residual)
       (when (plusp (decf (heuristic-search-debt job))) (return-from heuristic-search-step))
       (let* ((row (first (heuristic-search-rows job)))
              (outcome (first (heuristic-search-outcomes job)))
              (req (row-requirement row))
              (values (extract-allowed-values req)))
         (cond
           ((unconstrained-requirement-p req)
            (setf (heuristic-search-phase job) :next))
           ((and (listp values) values)
            (multiple-value-bind (witness witness-bits)
                (select-closest-witness (observation-outcome-value outcome)
                                        values
                                        type
                                        (eq :value (observation-outcome-status outcome)))
              (push (cons (row-key row) witness) (heuristic-search-residual job))
              (incf (heuristic-search-residual-bits job)
                    (+ (positive-bit-size (1+ (heuristic-search-index job)))
                       witness-bits))
              (setf (heuristic-search-phase job) :next)))
           (t
            ;; No available correction witness; do not call an unresolved predicate false.
            (setf (heuristic-search-phase job) :observe)))))
      (:next
       (charge ledger :heuristic-checking)
       (pop (heuristic-search-rows job)) (pop (heuristic-search-outcomes job))
       (incf (heuristic-search-index job)) (setf (heuristic-search-phase job) :row))
      (:score
       (charge ledger :heuristic-ranking)
       (when (plusp (decf (heuristic-search-debt job))) (return-from heuristic-search-step))
       (let* ((record (heuristic-search-record job))
              (program (observed-expression-expression record))
              (bits (description-size program (schema-inputs (frame-schema frame))))
              (row-residual (nreverse (heuristic-search-residual job))))
         (multiple-value-bind (rel-entries rel-bits)
             (relational-linkage-residual frame
                                          (observed-expression-outcomes record)
                                          :row-residuals row-residual
                                          :type type)
           (let* ((residual (append row-residual rel-entries))
                  ;; Residual length is encoded, too; exact synthesis needs no correction packet.
                  (residual-bits (+ (heuristic-search-residual-bits job)
                                    rel-bits
                                    (if residual (positive-bit-size (1+ (length residual))) 0)))
                  (score (+ bits residual-bits (* (heuristic-search-run-weight job)
                                                  (observed-expression-run-work record))))
                  (model (make-heuristic-model :program program :residual residual
                                               :unresolved-keys (nreverse (copy-list (heuristic-search-unresolved job)))
                                               :exact-p (null residual)
                                               :total-p (not (null (member (observed-expression-status record)
                                                                           '(:complete :unresolved))))
                                               :program-bits bits :residual-bits residual-bits
                                               :run-work (observed-expression-run-work record) :score score))
                  (old (heuristic-search-best job)))
             (push model (heuristic-search-models job))
             (when (or (null old) (< score (heuristic-score old))
                       (and (= score (heuristic-score old)) (< bits (heuristic-program-bits old))))
               (setf (heuristic-search-best job) model))
             (setf (heuristic-search-phase job) :observe))))))))

(defun heuristic-search-complete-p (job)
  (and (eq :observe (heuristic-search-phase job))
       (observation-bound-complete-p (heuristic-search-observation job) (heuristic-search-bound job))))

(defun resume-heuristic-search (job work-limit)
  "Absolute cumulative budget covers observation, checking, residuals, and ranking."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (heuristic-search-ledger job)) work-limit)
                   (not (heuristic-search-complete-p job))) do (heuristic-search-step job))
  (make-message :claim (if (heuristic-search-complete-p job) :bounded-exhaustion :cutoff)
                :evidence (list :description-limit (heuristic-search-bound job)
                                :work (ledger-total (heuristic-search-ledger job))
                                :phase (heuristic-search-phase job) :best (heuristic-search-best job))))

(defparameter *synthesis-debug-mode* nil
  "When non-NIL, record rich causal provenance on synthesis decompositions, nodes, and messages.")

(defstruct decomposition
  name decoder child-id child-type bindings language bound children
  (fiber-p nil) (lift-p nil) (solver nil) (fallback-p nil) (provenance nil))

(defstruct synthesis-node
  id parent proposal frame language bound search (phase :prepare) prepared (debt 0)
  priority heuristic followers reused-from
  ;; Lazy expansion: nil (not yet), :paying (branches staged, debt owed), or :done.
  expansion expansions (expansion-debt 0) (provenance nil))

;; Privately staged result of `prepare-synthesis-node`, published once its debt is paid.
(defstruct node-preparation
  frame language conflict reused-nogood-p fallback-p priority heuristic
  nogoods uip-nogood dip-repairs)

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

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node verification-expression (verification-row-budget 2000)
  pending (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
  library expand (max-depth 1) self-name oracle-table
  (nogoods nil) (deductive-nogoods-p t) (scope-cache (make-hash-table :test #'equal)) (reused-subproblems 0)
  (trace nil) (debug-p *synthesis-debug-mode*))

(defun activate-job-oracle (job)
  "Ensure JOB's self-recursive function symbol is bound to its partial oracle table."
  (let ((self-name (and job (synthesis-job-self-name job))))
    (when self-name
      (let* ((root-schema (frame-schema (synthesis-node-frame (synthesis-job-root job))))
             (def (find-function-definition self-name)))
        (unless (and def
                     (null (function-definition-body def))
                     (eq (function-definition-oracle-table def)
                         (synthesis-job-oracle-table job)))
          (set-function-active-implementation self-name
                                              (schema-inputs root-schema)
                                              (schema-target root-schema)
                                              :body nil
                                              :oracle-table (synthesis-job-oracle-table job)))))))

(defun activate-job-candidate-body (job candidate-expr &key finalize-p)
  "Bind JOB's self-recursive function symbol to CANDIDATE-EXPR for root VM verification.
When FINALIZE-P is true, run full `define-function` totality analysis and cache invalidation."
  (let ((self-name (and job (synthesis-job-self-name job))))
    (when self-name
      (let* ((root-schema (frame-schema (synthesis-node-frame (synthesis-job-root job))))
             (def (find-function-definition self-name)))
        (if finalize-p
            (unless (and def
                         (null (function-definition-oracle-table def))
                         (equal (function-definition-body def) candidate-expr)
                         (function-definition-total-p def))
              (define-function self-name
                (schema-inputs root-schema)
                (schema-target root-schema)
                candidate-expr))
            (unless (and def
                         (null (function-definition-oracle-table def))
                         (equal (function-definition-body def) candidate-expr))
              (set-function-active-implementation self-name
                                                  (schema-inputs root-schema)
                                                  (schema-target root-schema)
                                                  :body candidate-expr
                                                  :oracle-table nil)))))))

(defun synthesis-message (job node claim evidence)
  "Messages carry child and parent identities, scope, and evidence for later synthesis.
Only verified candidates and checked conflicts assert semantic facts; cutoff/coverage
messages describe computation. Parents may consume these without trusting a heuristic."
  (let* ((debug-extra (when (and job (synthesis-job-debug-p job) node)
                        (list :node-provenance (synthesis-node-provenance node)
                              :proposal-provenance (when (synthesis-node-proposal node)
                                                     (decomposition-provenance (synthesis-node-proposal node))))))
         (message (make-message :call-id (synthesis-node-id node) :claim claim
                                :evidence (append (list :parent-id (when (synthesis-node-parent node)
                                                                     (synthesis-node-id (synthesis-node-parent node)))
                                                        :proposal (when (synthesis-node-proposal node)
                                                                    (decomposition-name (synthesis-node-proposal node)))
                                                        :description-limit (synthesis-node-bound node)
                                                        :work (ledger-total (synthesis-job-ledger job)))
                                                  evidence
                                                  debug-extra))))
    (push message (synthesis-job-messages job)) message))

(defun add-synthesis-node (job parent proposal)
  (let ((node (make-synthesis-node :id (prog1 (synthesis-job-next-id job)
                                       (incf (synthesis-job-next-id job)))
                                   :parent parent :proposal proposal)))
    (setf (synthesis-job-nodes job) (append (synthesis-job-nodes job) (list node))) node))

(defun start-synthesis (frame language description-limit
                        &key decompositions (run-weight 0) (quantum 32)
                             (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
                             library expand (max-depth 1)
                             self-name oracle-table (verification-row-budget 2000)
                             (deductive-nogoods-p t) (debug-p *synthesis-debug-mode*))
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber/residual proposals.
LIBRARY (solve discoveries or propagator libraries) is applied to every pulled-back child
frame. EXPAND, a function (job node frame language heuristic-model ledger) -> decompositions,
proposes further branches below a prepared node shallower than MAX-DEPTH, root included.
Expansion is a scheduled action, chosen like search by the node's full-path price; with
MAX-DEPTH nil the tree grows for as long as the budget lasts (an anytime search)."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (assert (member policy '(:round-robin :heuristic)))
  (assert (or (null priority-predictor)
              (functionp priority-predictor)
              (heuristic-model-p priority-predictor)
              (consp priority-predictor)
              (symbolp priority-predictor)))
  (assert (or (null max-depth) (and (integerp max-depth) (>= max-depth 0))))
  (let* ((root (make-synthesis-node :id 0 :frame (snapshot-frame frame)
                                   :language (snapshot-language language) :bound description-limit
                                   :provenance (when debug-p (list :origin :root))))
         (eff-oracle (when self-name
                       (copy-tree (or oracle-table (frame-oracle-table frame)))))
         (job (%make-synthesis-job :root root :nodes (list root) :run-weight run-weight :quantum quantum
                                   :policy policy :heuristic-bound heuristic-bound
                                   :heuristic-budget heuristic-budget
                                   :priority-predictor priority-predictor
                                   :expand expand :max-depth max-depth
                                   :self-name self-name :oracle-table eff-oracle
                                   :verification-row-budget verification-row-budget
                                   :deductive-nogoods-p deductive-nogoods-p
                                   :debug-p debug-p)))
    (activate-job-oracle job)
    (setf (synthesis-job-library job) (as-propagator-library library (synthesis-job-ledger job)))
    (dolist (proposal decompositions) (add-synthesis-node job root (copy-decomposition-tree proposal)))
    job))

(defun heuristic-routing-p (job)
  (or (eq :heuristic (synthesis-job-policy job)) (synthesis-job-priority-predictor job)))

(defun node-depth (node)
  (loop for parent = (synthesis-node-parent node) then (synthesis-node-parent parent)
        while parent count t))

(defun node-may-expand-p (job node)
  "True when the job expands and NODE lies above the depth limit, if there is one."
  (and (synthesis-job-expand job)
       (not (eq :done (synthesis-node-expansion node)))
       (not (and (synthesis-node-proposal node)
                 (decomposition-lift-p (synthesis-node-proposal node))))
       (or (null (synthesis-job-max-depth job)) (< (node-depth node) (synthesis-job-max-depth job)))))

(defun node-expandable-p (job node)
  "An expansion of NODE is still owed: it is prepared, conflict free, and not yet expanded."
  (and (member (synthesis-node-phase node) '(:search :done))
       (node-may-expand-p job node)))

(defun copy-decomposition-tree (proposal)
  (let ((copy (copy-decomposition proposal)))
    (setf (decomposition-decoder copy) (copy-tree (decomposition-decoder copy))
          (decomposition-bindings copy) (copy-tree (decomposition-bindings copy))
          (decomposition-child-type copy) (copy-tree (decomposition-child-type copy))
          (decomposition-language copy) (snapshot-language (decomposition-language copy))
          (decomposition-provenance copy) (copy-tree (decomposition-provenance copy))
          (decomposition-children copy) (mapcar #'copy-decomposition-tree (decomposition-children copy)))
    copy))

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
  (and (nogood-clause-p entry)
       proposal
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

(defun build-nogood-clause (parent proposal conflict &optional ledger)
  "Construct a homoiconic S-expression nogood clause over PARENT's scope from a child CONFLICT."
  (let* ((parent-id (synthesis-node-id parent))
         (parent-frame (synthesis-node-frame parent))
         (parent-inputs (schema-inputs (frame-schema parent-frame)))
         (parent-rows (frame-rows parent-frame))
         (keys (copy-list (frame-conflict-keys conflict)))
         (known (copy-tree (frame-conflict-known conflict)))
         (bindings (copy-tree (and proposal (decomposition-bindings proposal))))
         (lift-p (and proposal (decomposition-lift-p proposal)))
         (parent-keys (if lift-p
                          (mapcar (lambda (k) (if (consp k) (first k) k)) keys)
                          keys))
         (matched-rows (mapcar (lambda (k) (find k parent-rows :key #'row-key :test #'equal))
                               parent-keys))
         (parent-incompatible-p
           (and (eq :incompatible-rows (frame-conflict-kind conflict))
                (>= (length matched-rows) 2)
                (every #'identity matched-rows)
                (or (pure-projection-decomposition-p proposal)
                    (and lift-p
                         (every #'consp keys)
                         (not (equal (first parent-keys) (second parent-keys)))
                         (every (lambda (k) (equal (second k) (second (first keys)))) (rest keys))
                         (let* ((p-exprs (proposal-parent-expressions proposal parent-inputs))
                                (p-binds (loop for e in p-exprs for i from 0 collect (cons i e)))
                                (v0 (evaluate-row-bindings p-binds parent-inputs
                                                           (row-known (first matched-rows))
                                                           :ledger ledger :error-p nil)))
                           (and (not (eq v0 :error))
                                (every (lambda (r)
                                         (equal v0 (evaluate-row-bindings p-binds parent-inputs
                                                                          (row-known r)
                                                                          :ledger ledger :error-p nil)))
                                       (rest matched-rows))))))))
         (parent-clause-expr
           (when (and lift-p (>= (length matched-rows) 2) (every #'identity matched-rows))
             (let* ((p-exprs (proposal-parent-expressions proposal parent-inputs))
                    (conjuncts
                      (loop for expr in p-exprs
                            for type = (expression-type expr parent-inputs)
                            for (v0 ok0) = (multiple-value-list
                                            (eval-expr-value expr parent-inputs
                                                             (row-known (first matched-rows)) ledger))
                            when (and ok0
                                      (not (eq v0 :unresolved))
                                      (every (lambda (r)
                                               (multiple-value-bind (vr okr)
                                                   (eval-expr-value expr parent-inputs (row-known r) ledger)
                                                 (and okr (equal v0 vr))))
                                             (rest matched-rows)))
                              collect (app (op := type) expr (lit type v0)))))
               (if conjuncts
                   (reduce #'bool-and conjuncts :from-end t)
                   (lit :bool t)))))
         (clause-expr
           (cond
             ((and lift-p (code-type-p (decomposition-child-type proposal)))
              (let* ((code-in (code-inputs (decomposition-child-type proposal)))
                     (conjuncts
                       (append
                        (loop for (id . type) in code-in
                              for val in known
                              unless (eq val :unresolved)
                                collect (app (op := type) (var id type) (lit type val)))
                        (loop for (nil . expr) in bindings
                              for val in (nthcdr (length code-in) known)
                              for type = (expression-type expr parent-inputs)
                              unless (eq val :unresolved)
                                collect (app (op := type) expr (lit type val))))))
                (if conjuncts
                    (reduce #'bool-and conjuncts :from-end t)
                    (lit :bool t))))
             ((null bindings)
              (lit :bool t))
             (t
              (let ((conjuncts
                      (loop for (nil . expr) in bindings
                            for val in known
                            for type = (expression-type expr parent-inputs)
                            unless (eq val :unresolved)
                              collect (app (op := type) expr (lit type val)))))
                (if conjuncts
                    (reduce #'bool-and conjuncts :from-end t)
                    (lit :bool t)))))))
    (make-nogood-clause :parent-id parent-id
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
      (let* ((schema (frame-schema frame))
             (target-type (schema-target schema))
             (checker-schema (make-schema :inputs (list (cons 0 target-type)) :target :bool))
             (by-known (make-hash-table :test #'equal))
             (collided-knowns (make-hash-table :test #'equal)))
        (setf (gethash (frame-conflict-known primary-conflict) collided-knowns) t)
        (dolist (row (frame-rows frame))
          (unless (member :unresolved (row-known row))
            (let ((folded (fold-constants (row-requirement row) checker-schema
                                          :ledger ledger :budget budget)))
              (unless (or (unsatisfiable-requirement-p folded)
                          (gethash (row-known row) collided-knowns))
                (let ((existing (gethash (row-known row) by-known)))
                  (if existing
                      (let* ((prev-keys (first existing))
                             (prev-req (second existing))
                             (joint (conjoin-requirements prev-req folded target-type
                                                          :ledger ledger :budget budget)))
                        (if (unsatisfiable-requirement-p joint)
                            (let ((extra-conflict
                                    (make-frame-conflict :kind :incompatible-rows
                                                         :keys (append (reverse prev-keys)
                                                                       (list (row-key row)))
                                                         :known (row-known row)
                                                         :expression joint)))
                              (setf (gethash (row-known row) collided-knowns) t)
                              (push (build-nogood-clause parent proposal extra-conflict ledger)
                                    clauses))
                            (setf (gethash (row-known row) by-known)
                                  (list (cons (row-key row) prev-keys) joint))))
                      (setf (gethash (row-known row) by-known)
                            (list (list (row-key row)) folded))))))))))
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
                                (and (nogood-clause-p ng)
                                     (not (eq :uip-clause (nogood-clause-kind ng)))
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
                   (uip (make-nogood-clause
                         :parent-id (nogood-clause-parent-id first-ng)
                         :kind :uip-clause
                         :keys (nogood-clause-keys first-ng)
                         :known (nogood-clause-known first-ng)
                         :bindings (copy-tree (nogood-clause-bindings first-ng))
                         :decoder (copy-tree (nogood-clause-decoder first-ng))
                         :child-id (nogood-clause-child-id first-ng)
                         :child-type (copy-tree (nogood-clause-child-type first-ng))
                         :parent-incompatible-p (every #'nogood-clause-parent-incompatible-p compatible)
                         :clause-expr pattern
                         :parent-clause-expr (or parent-pattern
                                                 (nogood-clause-parent-clause-expr first-ng)))))
              (values uip pattern substitutions))))))))

(defun clause-expr-matches-known-p (clause-expr scope-inputs known ledger)
  "Check whether CLAUSE-EXPR (either a concrete Boolean S-expression or a UIP pattern
containing holes `?h`) holds on KNOWN under SCOPE-INPUTS in the VM."
  (cond
    ((or (null clause-expr) (equal clause-expr (lit :bool t))) t)
    ((null (pattern-holes clause-expr))
     (multiple-value-bind (val ok) (eval-expr-value clause-expr scope-inputs known ledger)
       (and ok (eq t val))))
    (t
     (let ((hole-env (make-hash-table :test #'eql)))
       (every (lambda (conjunct)
                (if (null (pattern-holes conjunct))
                    (multiple-value-bind (val ok) (eval-expr-value conjunct scope-inputs known ledger)
                      (and ok (eq t val)))
                    (and (app-p conjunct)
                         (operator-p (first conjunct))
                         (eq := (operator-name (first conjunct)))
                         (let ((lhs (second conjunct))
                               (rhs (third conjunct)))
                           (cond
                             ((and (hole-p rhs) (null (pattern-holes lhs)))
                              (multiple-value-bind (val ok) (eval-expr-value lhs scope-inputs known ledger)
                                (and ok
                                     (multiple-value-bind (bound present-p) (gethash (ast-id rhs) hole-env)
                                       (if present-p
                                           (equal bound val)
                                           (progn (setf (gethash (ast-id rhs) hole-env) val) t))))))
                             ((and (hole-p lhs) (null (pattern-holes rhs)))
                              (multiple-value-bind (val ok) (eval-expr-value rhs scope-inputs known ledger)
                                (and ok
                                     (multiple-value-bind (bound present-p) (gethash (ast-id lhs) hole-env)
                                       (if present-p
                                           (equal bound val)
                                           (progn (setf (gethash (ast-id lhs) hole-env) val) t))))))
                             (t t))))))
              (extract-conjuncts clause-expr))))))

(defun nogood-entry-parent-and-keys (entry)
  "Extract (VALUES parent-id keys kind) from a `nogood-clause` or legacy `(parent-id . keys)` list."
  (if (nogood-clause-p entry)
      (values (nogood-clause-parent-id entry)
              (nogood-clause-keys entry)
              (nogood-clause-kind entry))
      (values (first entry) (rest entry) :incompatible-rows)))

(defun check-parent-nogoods (job parent proposal ledger)
  "Deductively check whether PROPOSAL's context projection/lifting is refuted by any
`nogood-clause` (including anti-unified UIP clauses) already discovered on PARENT."
  (when (and job (synthesis-job-deductive-nogoods-p job) parent proposal
             (or (pure-projection-decomposition-p proposal)
                 (decomposition-lift-p proposal)))
    (let* ((parent-id (synthesis-node-id parent))
           (parent-frame (synthesis-node-frame parent))
           (inputs (schema-inputs (frame-schema parent-frame)))
           (rows (frame-rows parent-frame))
           (bindings (decomposition-bindings proposal)))
      (dolist (entry (synthesis-job-nogoods job))
        (multiple-value-bind (p-id keys kind) (nogood-entry-parent-and-keys entry)
          (when (= p-id parent-id)
            ;; 1. Pure projection or cross-row parent incompatibility
            (when (or (and (pure-projection-decomposition-p proposal)
                           (eq kind :incompatible-rows))
                      (and (nogood-clause-p entry)
                           (nogood-clause-parent-incompatible-p entry)
                           (or (pure-projection-decomposition-p proposal)
                               (decomposition-lift-p proposal))))
              (let* ((parent-keys (if (and (nogood-clause-p entry)
                                           (member kind '(:lift-incompatible-rows :uip-clause)))
                                      (mapcar (lambda (k) (if (consp k) (first k) k)) keys)
                                      keys))
                     (matched-rows (mapcar (lambda (k) (find k rows :key #'row-key :test #'equal))
                                           parent-keys)))
                (when (and (>= (length matched-rows) 2) (every #'identity matched-rows))
                  (if (pure-projection-decomposition-p proposal)
                      (let ((first-known (evaluate-row-bindings bindings inputs
                                                                (row-known (first matched-rows))
                                                                :ledger ledger :error-p nil)))
                        (when (and (not (eq first-known :error))
                                   (every (lambda (r)
                                            (equal first-known
                                                   (evaluate-row-bindings bindings inputs (row-known r)
                                                                          :ledger ledger :error-p nil)))
                                          (rest matched-rows)))
                          (return-from check-parent-nogoods
                            (make-frame-conflict :kind :incompatible-rows
                                                 :keys (copy-list parent-keys)
                                                 :known first-known
                                                 :expression (lit :bool nil)))))
                      (let* ((p-exprs (proposal-parent-expressions proposal inputs))
                             (p-binds (loop for e in p-exprs for i from 0 collect (cons i e)))
                             (first-vals (evaluate-row-bindings p-binds inputs
                                                                (row-known (first matched-rows))
                                                                :ledger ledger :error-p nil)))
                        (when (and (not (eq first-vals :error))
                                   (every (lambda (r)
                                            (equal first-vals
                                                   (evaluate-row-bindings p-binds inputs (row-known r)
                                                                          :ledger ledger :error-p nil)))
                                          (rest matched-rows))
                                   (or (not (nogood-clause-p entry))
                                       (clause-expr-matches-known-p (nogood-clause-parent-clause-expr entry)
                                                                    inputs
                                                                    (row-known (first matched-rows))
                                                                    ledger)))
                          (let ((known-out (evaluate-row-bindings bindings inputs
                                                                  (row-known (first matched-rows))
                                                                  :ledger ledger :error-p nil)))
                            (return-from check-parent-nogoods
                              (make-frame-conflict :kind :incompatible-rows
                                                   :keys (copy-list parent-keys)
                                                   :known (if (eq known-out :error) nil known-out)
                                                   :expression (lit :bool nil))))))))))
            ;; 2. Lifted occurrence incompatibility across sibling higher-order proposals
            (when (and (nogood-clause-p entry)
                       (member kind '(:lift-incompatible-rows :uip-clause))
                       (same-lifted-decoder-p entry proposal))
              (let* ((parent-keys (mapcar (lambda (k) (if (consp k) (first k) k)) keys))
                     (matched-rows (mapcar (lambda (k) (find k rows :key #'row-key :test #'equal))
                                           parent-keys))
                     (code-in (code-inputs (decomposition-child-type proposal)))
                     (code-known (subseq (nogood-clause-known entry)
                                         0 (min (length code-in) (length (nogood-clause-known entry))))))
                (when (and (>= (length matched-rows) 2)
                           (every #'identity matched-rows)
                           (or (nogood-clause-bindings entry)
                               (clause-expr-matches-known-p (nogood-clause-clause-expr entry)
                                                            code-in code-known ledger)))
                  (let ((first-extra (evaluate-row-bindings bindings inputs
                                                            (row-known (first matched-rows))
                                                            :ledger ledger :error-p nil)))
                    (when (and (not (eq first-extra :error))
                               (every (lambda (r)
                                        (equal first-extra
                                               (evaluate-row-bindings bindings inputs (row-known r)
                                                                      :ledger ledger :error-p nil)))
                                      (rest matched-rows)))
                      (return-from check-parent-nogoods
                        (make-frame-conflict :kind :incompatible-rows
                                             :keys (copy-list keys)
                                             :known (append code-known first-extra)
                                             :expression (lit :bool nil)))))))))))))
  nil)

(defun conflict-distinct-parent-row-pairs (parent-frame nogoods)
  "Extract pairs `(row1 . row2)` of distinct parent rows from NOGOODS that collided."
  (let ((rows (frame-rows parent-frame))
        (pairs nil))
    (dolist (ng nogoods (nreverse pairs))
      (when (and (nogood-clause-p ng)
                 (member (nogood-clause-kind ng) '(:incompatible-rows :lift-incompatible-rows :uip-clause))
                 (>= (length (nogood-clause-keys ng)) 2))
        (let* ((raw-keys (nogood-clause-keys ng))
               (p-keys (if (eq :incompatible-rows (nogood-clause-kind ng))
                           raw-keys
                           (mapcar (lambda (k) (if (consp k) (first k) k)) raw-keys)))
               (r1 (find (first p-keys) rows :key #'row-key :test #'equal))
               (r2 (find (second p-keys) rows :key #'row-key :test #'equal)))
          (when (and r1 r2 (not (equal (row-key r1) (row-key r2))))
            (pushnew (cons r1 r2) pairs
                     :test (lambda (a b)
                             (and (equal (row-key (car a)) (row-key (car b)))
                                  (equal (row-key (cdr a)) (row-key (cdr b))))))))))))

(defun candidate-dip-context-expressions (parent-frame language &key existing-bindings allow-sequence-p)
  "Generate candidate parent-scope expressions (0-step variables and 1-step operator
applications) that can serve as new intermediate context variables in DIP repairs."
  (let* ((inputs (schema-inputs (frame-schema parent-frame)))
         (existing-exprs (mapcar #'cdr existing-bindings))
         (candidates nil))
    (flet ((acceptable-type-p (type)
             (and (not (code-type-p type))
                  (or allow-sequence-p
                      (not (and (consp type) (eq :seq (first type)))))))
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
                                          allow-sequence-p ledger)
  "Dual Implication Point (DIP) context introduction: inspect conflicting parent row pairs
in NOGOODS and return up to MAX-CANDIDATES minimal total parent-scope expressions that
separate all distinct-row conflict pairs."
  (let* ((pairs (conflict-distinct-parent-row-pairs parent-frame nogoods))
         (inputs (schema-inputs (frame-schema parent-frame)))
         (constrained-rows (remove-if (lambda (r) (unconstrained-requirement-p (row-requirement r)))
                                      (frame-rows parent-frame))))
    (when pairs
      (let ((candidates (candidate-dip-context-expressions parent-frame language
                                                           :existing-bindings existing-bindings
                                                           :allow-sequence-p allow-sequence-p))
            (separators nil))
        (dolist (expr candidates)
          (when (< (length separators) max-candidates)
            (when (and (every (lambda (pair)
                                (multiple-value-bind (v1 ok1)
                                    (eval-expr-value expr inputs (row-known (car pair)) ledger)
                                  (multiple-value-bind (v2 ok2)
                                      (eval-expr-value expr inputs (row-known (cdr pair)) ledger)
                                    (and ok1 ok2 (not (equal v1 v2))))))
                              pairs)
                       (every (lambda (row)
                                (nth-value 1 (eval-expr-value expr inputs (row-known row) ledger)))
                              constrained-rows))
              (push expr separators))))
        (nreverse separators)))))

(defun dip-repaired-decompositions (parent proposal nogoods
                                    &key (max-repairs 1) ledger (debug-p *synthesis-debug-mode*))
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
                                                     :ledger ledger)))
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
            for new-lang = (make-language (language-domain old-lang)
                                          new-lang-inputs
                                          :operators (language-operators old-lang)
                                          :literals (language-literals old-lang)
                                          :constants (language-constants old-lang))
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

(defun child-scope-signature (frame language)
  "Canonical structural key for child-frame and language equivalence across synthesis branches."
  (list (schema-inputs (frame-schema frame))
        (schema-target (frame-schema frame))
        (mapcar (lambda (row)
                  (list (row-key row) (row-known row) (row-requirement row)))
                (frame-rows frame))
        (frame-pairs frame)
        (frame-anchors frame)
        (language-domain language)
        (language-inputs language)
        (language-operators language)
        (language-literals language)
        (language-constants language)))

(defun reconstruct-synthesis-candidate (node expression &optional ledger)
  (loop while (synthesis-node-parent node) do
    (let ((proposal (synthesis-node-proposal node)))
      (setf expression (if (decomposition-lift-p proposal)
                           (compose-lifted-model (decomposition-decoder proposal)
                                                 (decomposition-child-id proposal)
                                                 (decomposition-child-type proposal)
                                                 expression
                                                 (decomposition-bindings proposal)
                                                 ledger)
                           (compose-model (decomposition-decoder proposal)
                                          (decomposition-child-id proposal)
                                          expression
                                          (decomposition-bindings proposal)
                                          ledger))
            node (synthesis-node-parent node)))
    finally (return expression)))

(defun expression-calls-operator-p (expr op-name)
  "True when EXPR contains an application of operator OP-NAME."
  (and (app-p expr)
       (or (and (operator-p (first expr))
                (eq op-name (operator-name (first expr))))
           (some (lambda (arg) (expression-calls-operator-p arg op-name))
                 (rest expr)))))

(defun valid-job-node-candidate-p (job node expr)
  "When JOB is synthesizing a recursive definition for SELF-NAME, any candidate must call SELF-NAME."
  (let ((self-name (and job (synthesis-job-self-name job))))
    (or (null self-name)
        (expression-calls-operator-p
         (reconstruct-synthesis-candidate node expr)
         self-name))))

(defun node-stage-a-model (job node frame language ledger)
  "Stage A: a budgeted heuristic condensation of NODE's own (pulled-back) frame.
Its residual is priced in the node's representation, not the root's."
  (let* ((base-budget (synthesis-job-heuristic-budget job))
         (lift-p (and (synthesis-node-proposal node)
                      (decomposition-lift-p (synthesis-node-proposal node))))
         (budget (if (and (integerp base-budget) lift-p)
                     (* 2 base-budget)
                     base-budget)))
    (when (and (integerp budget) (plusp budget))
      (condense-heuristic frame language
                          :description-limit (or (synthesis-job-heuristic-bound job)
                                                 (synthesis-node-bound node)
                                                 (let ((proposal (synthesis-node-proposal node)))
                                                   (and proposal (decomposition-bound proposal)))
                                                 (+ (header-size (schema-inputs (frame-schema frame))
                                                                 (schema-target (frame-schema frame))) 18))
                          :work-limit budget
                          :run-weight (synthesis-job-run-weight job)
                          :ledger ledger))))

(defun node-trace-features (node frame h-model &optional ledger)
  "Extract the 4-element integer feature vector `(program-bits residual-bits depth constrained-rows)`
for NODE's Stage A condensation H-MODEL on FRAME."
  (let* ((root (loop for cur = node then (synthesis-node-parent cur)
                     while (synthesis-node-parent cur)
                     finally (return cur)))
         (root-frame (and root (synthesis-node-frame root)))
         (root-inputs (and root-frame (schema-inputs (frame-schema root-frame))))
         (prog-bits (if h-model
                        (let ((composed (reconstruct-synthesis-candidate node (heuristic-program h-model) ledger)))
                          (if root-inputs
                              (description-size composed root-inputs)
                              (heuristic-program-bits h-model)))
                        100))
         (res-bits (if h-model (heuristic-residual-bits h-model) 100))
         (depth (node-depth node))
         (constrained (if frame (frame-constrained-row-count frame) 0)))
    (list prog-bits res-bits depth constrained)))

(defun evaluate-priority-predictor-expr (expr node frame h-model &optional ledger)
  "Evaluate an S-expression priority predictor EXPR on NODE's 4-element trace feature vector in the VM."
  (if (null h-model)
      most-positive-fixnum
      (let ((inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
            (features (node-trace-features node frame h-model ledger)))
        (multiple-value-bind (val ok) (eval-expr-value expr inputs features ledger)
          (if (and ok (integerp val)) val most-positive-fixnum)))))

(defun node-priority (job node frame language h-model ledger)
  "Lower is better: the Stage A model composed through every ancestor and priced at the
root, plus its residual bits; or a supplied predictor's score (callable function,
`heuristic-model`, or homoiconic S-expression AST evaluated in the VM)."
  (let ((predictor (synthesis-job-priority-predictor job)))
    (cond
      ((functionp predictor) (funcall predictor node frame language h-model))
      ((heuristic-model-p predictor)
       (evaluate-priority-predictor-expr (heuristic-program predictor) node frame h-model ledger))
      (predictor
       (evaluate-priority-predictor-expr predictor node frame h-model ledger))
      (h-model
       (let ((root-inputs (schema-inputs (frame-schema (synthesis-node-frame (synthesis-job-root job)))))
             (composed (reconstruct-synthesis-candidate node (heuristic-program h-model) ledger)))
         (+ (description-size composed root-inputs)
            (heuristic-residual-bits h-model)
            (* (synthesis-job-run-weight job) (heuristic-run-work h-model)))))
      (t most-positive-fixnum))))

(defun node-library (job proposal ledger)
  "The job's learned propagators plus any supplied with PROPOSAL; none on a fallback branch."
  (unless (and proposal (decomposition-fallback-p proposal))
    (let ((shared (and job (synthesis-job-library job)))
          (local (and proposal (decomposition-solver proposal))))
      (if local
          (as-propagator-library (if shared (list shared local) local) ledger)
          shared))))

(defun prepare-synthesis-node (node &optional job)
  "Stage atomic host preparation privately; publish only after its tariff is paid.
This is accounting preemption, not OS-level interruption of Lisp traversals.
A child frame is pulled back, folded, narrowed by the learned library, and folded again;
Stage A then prices it for routing and, when expandable, proposes the node's own branches."
  (activate-job-oracle job)
  (let* ((ledger (make-ledger))
         (proposal (synthesis-node-proposal node))
         (parent (synthesis-node-parent node))
         (language (if proposal (decomposition-language proposal) (synthesis-node-language node)))
         (nogood-conflict (check-parent-nogoods job parent proposal ledger)))
    (when nogood-conflict
      (charge ledger :problem-snapshot 1)
      (setf (synthesis-node-prepared node)
            (make-node-preparation :language language :conflict nogood-conflict :reused-nogood-p t)
            (synthesis-node-debt node) (max 1 (ledger-total ledger))
            (synthesis-node-phase node) :preparation)
      (return-from prepare-synthesis-node))
    (let ((frame (cond ((null parent)
                        (synthesis-node-frame node))
                       ((decomposition-lift-p proposal)
                        (lift-frame (synthesis-node-frame parent)
                                    (decomposition-decoder proposal)
                                    (decomposition-child-id proposal)
                                    (decomposition-child-type proposal)
                                    (decomposition-bindings proposal)
                                    ledger))
                       (t
                        (pullback-frame (synthesis-node-frame parent)
                                        (decomposition-decoder proposal)
                                        (decomposition-child-id proposal)
                                        (decomposition-child-type proposal)
                                        (decomposition-bindings proposal)
                                        ledger))))
          (fallback-p nil))
      (when (and proposal (decomposition-fiber-p proposal))
        (let ((refined (nth-value 2 (infer-fibers frame ledger))))
          (when refined (setf frame refined))))
      (charge ledger :problem-snapshot
              (+ 1 (loop for row in (frame-rows frame) sum
                     (+ (syntax-work (row-requirement row))
                        (loop for value in (row-known row) for spec in (language-inputs language)
                              sum (value-work value (cdr spec)))))))
      (multiple-value-bind (conflict folded) (frame-conflict-p frame :ledger ledger)
        (let ((library (and parent (null conflict) (node-library job proposal ledger))))
          (when library
            (let ((propagation (propagate-requirements folded library ledger)))
              ;; A narrowing without uniqueness evidence may drop witnesses: keep the original.
              (setf fallback-p (plusp (propagation-ambiguous propagation)))
              (when (plusp (+ (propagation-narrowed propagation) (propagation-suggested propagation)))
                (multiple-value-setq (conflict folded)
                  (frame-conflict-p (propagation-frame propagation) :ledger ledger))))))
        (let* ((effective (if conflict frame folded))
               (priced-p (and job (null conflict) (or parent (node-may-expand-p job node))
                              (or (heuristic-routing-p job) (node-may-expand-p job node))))
               (h-model (when priced-p (node-stage-a-model job node effective language ledger)))
               (record-nogood-p (and job (synthesis-job-deductive-nogoods-p job)
                                     conflict
                                     (eq :incompatible-rows (frame-conflict-kind conflict))
                                     parent
                                     (or (pure-projection-decomposition-p proposal)
                                         (and proposal (decomposition-lift-p proposal)))
                                     (>= (length (frame-conflict-keys conflict)) 2)))
               (new-nogoods (when record-nogood-p
                              (collect-frame-nogood-clauses parent proposal frame conflict ledger)))
               (uip-nogood (when (and new-nogoods (decomposition-lift-p proposal))
                             (nth-value 0 (anti-unify-nogood-clauses
                                           (append new-nogoods (synthesis-job-nogoods job))
                                           ledger))))
               (dip-repairs (when (and new-nogoods
                                       (decomposition-lift-p proposal)
                                       (or (heuristic-routing-p job)
                                           (node-may-expand-p job parent)))
                              (dip-repaired-decompositions parent proposal new-nogoods
                                                           :ledger ledger
                                                           :debug-p (synthesis-job-debug-p job)))))
          (setf (synthesis-node-prepared node)
                (make-node-preparation
                 :frame effective :language language :conflict conflict :fallback-p fallback-p
                 :heuristic h-model
                 :priority (when (and priced-p (heuristic-routing-p job))
                             (node-priority job node effective language h-model ledger))
                 :nogoods new-nogoods
                 :uip-nogood uip-nogood
                 :dip-repairs dip-repairs)
                (synthesis-node-debt node) (ledger-total ledger)
                (synthesis-node-phase node) :preparation))))))

(defun enqueue-node-candidate (job node expression candidate-obj)
  (let* ((preparation (make-ledger))
         (model (reconstruct-synthesis-candidate node expression preparation)))
    (when candidate-obj
      (synthesis-message job node :child-candidate (list :candidate candidate-obj :scope :child-frame)))
    (setf (synthesis-job-pending job)
          (append (synthesis-job-pending job)
                  (list (list node model (max 1 (ledger-total preparation))))))))

(defun exact-heuristic-program (node &optional job)
  "The node's own Stage A program when it already satisfies every row, else nil."
  (let ((h-model (synthesis-node-heuristic node)))
    (when (and h-model (heuristic-exact-p h-model)
               (valid-job-node-candidate-p job node (heuristic-program h-model)))
      (heuristic-program h-model))))

(defun finish-synthesis-preparation (job node)
  (let* ((prepared (synthesis-node-prepared node))
        (frame (node-preparation-frame prepared))
        (language (node-preparation-language prepared))
        (conflict (node-preparation-conflict prepared))
        (reused-nogood-p (node-preparation-reused-nogood-p prepared))
        (h-model (node-preparation-heuristic prepared)))
    (setf (synthesis-node-frame node) frame
          (synthesis-node-language node) language
          (synthesis-node-bound node) (or (synthesis-node-bound node)
                                          (when (synthesis-node-proposal node)
                                            (decomposition-bound (synthesis-node-proposal node))))
          (synthesis-node-priority node) (node-preparation-priority prepared)
          (synthesis-node-heuristic node) h-model
          (synthesis-node-prepared node) nil)
    (when (and job (synthesis-job-debug-p job))
      (setf (synthesis-node-provenance node)
            (list :origin (or (and (synthesis-node-proposal node)
                                   (getf (decomposition-provenance (synthesis-node-proposal node)) :origin))
                              (and (synthesis-node-proposal node)
                                   (decomposition-name (synthesis-node-proposal node)))
                              :root)
                  :depth (node-depth node)
                  :frame-summary (when frame
                                   (list :total-rows (length (frame-rows frame))
                                         :constrained-rows (frame-constrained-row-count frame)
                                         :dead-rows (- (length (frame-rows frame))
                                                       (frame-constrained-row-count frame))
                                         :unresolved-rows (count-if (lambda (r) (member :unresolved (row-known r)))
                                                                    (frame-rows frame))))
                  :conflict conflict
                  :reused-nogood-p reused-nogood-p
                  :stage-a-program (when h-model (heuristic-program h-model))
                  :stage-a-exact-p (when h-model (heuristic-exact-p h-model))
                  :stage-a-score (when h-model (heuristic-score h-model))
                  :priority (node-preparation-priority prepared))))
    (when (and (node-preparation-fallback-p prepared) (synthesis-node-parent node) (synthesis-node-proposal node))
      (let ((fb (copy-decomposition-tree (synthesis-node-proposal node))))
        (setf (decomposition-name fb) (list :fallback (decomposition-name fb))
              (decomposition-solver fb) nil
              (decomposition-fallback-p fb) t
              (decomposition-provenance fb) (when (and job (synthesis-job-debug-p job))
                                              (list :origin :fallback
                                                    :from (decomposition-name (synthesis-node-proposal node)))))
        (add-synthesis-node job (synthesis-node-parent node) fb)))
    (if conflict
        (progn
          (when (and (not reused-nogood-p) (node-preparation-nogoods prepared))
            (dolist (ng (reverse (node-preparation-nogoods prepared)))
              (pushnew ng (synthesis-job-nogoods job)
                       :test (lambda (a b)
                               (and (nogood-clause-p a) (nogood-clause-p b)
                                    (eql (nogood-clause-parent-id a) (nogood-clause-parent-id b))
                                    (eq (nogood-clause-kind a) (nogood-clause-kind b))
                                    (equal (nogood-clause-keys a) (nogood-clause-keys b))))))
            (let ((uip (node-preparation-uip-nogood prepared)))
              (when (and uip
                         (not (find-if (lambda (b)
                                         (and (nogood-clause-p b)
                                              (eql (nogood-clause-parent-id uip) (nogood-clause-parent-id b))
                                              (eq :uip-clause (nogood-clause-kind b))
                                              (equal (nogood-clause-clause-expr uip)
                                                     (nogood-clause-clause-expr b))))
                                       (synthesis-job-nogoods job))))
                (setf (synthesis-job-nogoods job)
                      (append (synthesis-job-nogoods job) (list uip)))))
            (let ((parent (synthesis-node-parent node)))
              (dolist (repaired (node-preparation-dip-repairs prepared))
                (unless (find-if (lambda (n)
                                   (and (eq (synthesis-node-parent n) parent)
                                        (synthesis-node-proposal n)
                                        (equal (decomposition-bindings (synthesis-node-proposal n))
                                               (decomposition-bindings repaired))
                                        (equal (normalize-proposal-decoder
                                                (decomposition-decoder (synthesis-node-proposal n))
                                                (decomposition-child-id (synthesis-node-proposal n))
                                                (decomposition-child-type (synthesis-node-proposal n)))
                                               (normalize-proposal-decoder
                                                (decomposition-decoder repaired)
                                                (decomposition-child-id repaired)
                                                (decomposition-child-type repaired)))))
                                 (synthesis-job-nodes job))
                  (add-synthesis-node job parent repaired)))))
          (setf (synthesis-node-phase node) :done
                (synthesis-node-expansion node) :done)
          (synthesis-message job node :conflict
                             (append (list :conflict conflict :scope :child-frame)
                                     (when reused-nogood-p (list :reused-nogood t)))))
        (progn
          (dolist (proposal (when (synthesis-node-proposal node)
                              (decomposition-children (synthesis-node-proposal node))))
            (add-synthesis-node job node proposal))
          ;; A node whose Stage A model is already exact has no residual left to branch on.
          (when (and (exact-heuristic-program node job)
                     (null (heuristic-unresolved-keys h-model)))
            (setf (synthesis-node-expansion node) :done))
          ;; Fast-path an exact Stage A hit directly to root verification.
          (when (exact-heuristic-program node job)
            (let ((cand (make-candidate :expression (heuristic-program h-model)
                                        :size (heuristic-program-bits h-model)
                                        :run-work (heuristic-run-work h-model)
                                        :discovery-work (ledger-total (synthesis-job-ledger job)))))
              (enqueue-node-candidate job node (heuristic-program h-model) cand)))
          (let* ((sig (when (synthesis-node-parent node)
                        (child-scope-signature frame language)))
                 (existing (when sig (gethash sig (synthesis-job-scope-cache job)))))
            (if (and existing (not (eq existing node))
                     (<= (synthesis-node-bound node) (synthesis-node-bound existing)))
                (progn
                  (setf (synthesis-node-followers existing)
                        (append (synthesis-node-followers existing) (list node))
                        (synthesis-node-reused-from node) (synthesis-node-id existing)
                        (synthesis-node-phase node) :done
                        ;; The canonical node expands this frame; a second subtree would duplicate it.
                        (synthesis-node-expansion node) :done)
                  (incf (synthesis-job-reused-subproblems job))
                  (synthesis-message job node :subproblem-reused
                                     (list :canonical-id (synthesis-node-id existing) :scope :child-frame))
                  (when (synthesis-node-search existing)
                    (dolist (cand (reverse (search-job-results (synthesis-node-search existing))))
                      (when (<= (candidate-size cand) (synthesis-node-bound node))
                        (enqueue-node-candidate job node (candidate-expression cand) cand)))))
                (progn
                  (when sig
                    (setf (gethash sig (synthesis-job-scope-cache job)) node))
                  (setf (synthesis-node-search node) (start-search frame language)
                        (synthesis-node-phase node) :search))))))))

(defun synthesis-finished-p (job)
  (and (every (lambda (n) (and (eq :done (synthesis-node-phase n)) (not (node-expandable-p job n))))
              (synthesis-job-nodes job))
       (null (synthesis-job-pending job)) (null (synthesis-job-verification job))))

(defun action-node (action)
  "Agenda actions are a node (prepare or search it) or (:expand . node)."
  (if (consp action) (cdr action) action))

(defun action-priority (action)
  "Full-path price: the node's Stage A model composed through every ancestor and priced
at the root, plus its residual. Expansion wins ties: it is the cheaper lookahead."
  (let ((price (or (synthesis-node-priority (action-node action)) most-positive-fixnum)))
    (if (consp action) (- price 1/2) price)))

(defun select-heuristic-action (job actions)
  "Under :heuristic or priority-predictor routing: prepare unprepared primary nodes first,
then take the lowest full-path price, reserving every 4th selection for round-robin."
  (or (find-if (lambda (action)
                 (let ((node (action-node action)))
                   (and (atom action)
                        (member (synthesis-node-phase node) '(:prepare :preparation))
                        (not (and (synthesis-node-proposal node)
                                  (decomposition-fallback-p (synthesis-node-proposal node)))))))
               actions)
      (let ((turn-index (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job)))))
        (if (= 3 (mod turn-index 4))
            (nth (mod (floor turn-index 4) (length actions)) actions)
            (let ((best (first actions)))
              (dolist (action (rest actions) best)
                (when (< (action-priority action) (action-priority best))
                  (setf best action))))))))

(defun select-synthesis-lane (job)
  (let* ((root (synthesis-job-root job))
         (others (remove-if (lambda (node)
                              (or (eq node root) (eq :done (synthesis-node-phase node))
                                  (and (synthesis-node-parent node)
                                       (null (synthesis-node-frame (synthesis-node-parent node))))))
                            (synthesis-job-nodes job)))
         (expansions (loop for node in (synthesis-job-nodes job)
                           when (node-expandable-p job node) collect (cons :expand node)))
         (actions (append others expansions))
         ;; Staged work already started is paid off before anything else begins.
         (in-progress (or (find :preparation others :key #'synthesis-node-phase)
                          (find :paying expansions :key (lambda (a) (synthesis-node-expansion (cdr a))))))
         (root-active (not (eq :done (synthesis-node-phase root))))
         (turn (synthesis-job-turn job))
         (reserve (= 3 (mod turn 4)))
         (chosen
           (cond ((and root-active reserve) root)
                 ((or (synthesis-job-pending job) (synthesis-job-verification job)) :verify)
                 ;; The root's own price and branches are needed before siblings can be ranked.
                 ((member (synthesis-node-phase root) '(:prepare :preparation)) root)
                 (in-progress in-progress)
                 (actions
                  (if (heuristic-routing-p job)
                      (select-heuristic-action job actions)
                      (nth (mod (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job)))
                                (length actions))
                           actions)))
                 (root-active root))))
    (incf (synthesis-job-turn job))
    (when chosen
      (push (list :turn turn
                  :lane (cond ((eq chosen :verify) :verify)
                              ((consp chosen) (list :expand (synthesis-node-id (cdr chosen))))
                              (t (synthesis-node-id chosen)))
                  :work (ledger-total (synthesis-job-ledger job))
                  :best-score (when (synthesis-job-best job)
                                (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job)))
                  :priority (unless (eq chosen :verify) (synthesis-node-priority (action-node chosen))))
            (synthesis-job-trace job)))
    (setf (synthesis-job-active job) chosen
          (synthesis-job-remaining job) (synthesis-job-quantum job))))

(defun synthesis-expansion-step (job node)
  "Stage NODE's branches privately, then publish them once their tariff is paid."
  (activate-job-oracle job)
  (let ((ledger (synthesis-job-ledger job)))
    (charge ledger :expansion)
    (if (null (synthesis-node-expansion node))
        (let ((private (make-ledger)))
          (setf (synthesis-node-expansions node)
                (funcall (synthesis-job-expand job) job node (synthesis-node-frame node)
                         (synthesis-node-language node) (synthesis-node-heuristic node) private)
                (synthesis-node-expansion-debt node) (ledger-total private)
                (synthesis-node-expansion node) :paying))
        (when (<= (decf (synthesis-node-expansion-debt node)) 0)
          (dolist (proposal (synthesis-node-expansions node))
            (add-synthesis-node job node proposal))
          (synthesis-message job node :expanded
                             (list :proposals (mapcar #'decomposition-name (synthesis-node-expansions node))
                                   :depth (node-depth node)))
          (setf (synthesis-node-expansion node) :done
                (synthesis-node-expansions node) nil)))))

(defun synthesis-verification-step (job)
  (let ((ledger (synthesis-job-ledger job)) (root (synthesis-job-root job)))
    (if (synthesis-job-verification job)
        (let* ((search (synthesis-job-verification job)) (before (ledger-total (search-job-ledger search))))
          (when (synthesis-job-verification-expression job)
            (activate-job-candidate-body job (synthesis-job-verification-expression job)))
          (search-step search 1)
          (charge ledger :parent-verification (- (ledger-total (search-job-ledger search)) before))
          (when (search-bound-complete-p search most-positive-fixnum)
            (let ((candidate (search-job-best search)) (node (synthesis-job-verification-node job)))
              (if candidate
                  (progn
                    (setf (candidate-discovery-work candidate) (ledger-total ledger))
                    (push candidate (synthesis-job-results job))
                    (when (or (null (synthesis-job-best job))
                              (< (candidate-score candidate (synthesis-job-run-weight job))
                                 (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))))
                      (setf (synthesis-job-best job) candidate))
                    (synthesis-message job node :candidate (list :candidate candidate :scope :original-root)))
                  (synthesis-message job node :rejected (list :scope :original-root :messages (search-job-messages search)))))
            (setf (synthesis-job-verification job) nil
                  (synthesis-job-verification-expression job) nil)))
        (let ((pending (first (synthesis-job-pending job))))
          (when pending
            (charge ledger :composition)
            (decf (third pending))
            (when (<= (third pending) 0)
              (pop (synthesis-job-pending job))
              (activate-job-candidate-body job (second pending))
              (setf (synthesis-job-verification-node job) (first pending)
                    (synthesis-job-verification-expression job) (second pending)
                    (synthesis-job-verification job)
                    (start-search (synthesis-node-frame root) (synthesis-node-language root)
                                  :run-weight (synthesis-job-run-weight job)
                                  :row-budget (when (synthesis-job-self-name job)
                                                (synthesis-job-verification-row-budget job))
                                  :diagnostics t
                                  :expressions (list (second pending))))))))))

(defun synthesis-node-step (job node)
  (activate-job-oracle job)
  (let ((ledger (synthesis-job-ledger job)))
    (case (synthesis-node-phase node)
      (:prepare (charge ledger :preparation) (prepare-synthesis-node node job))
      (:preparation
       (charge ledger :preparation) (decf (synthesis-node-debt node))
       (when (<= (synthesis-node-debt node) 0) (finish-synthesis-preparation job node)))
      (:search
       (let* ((search (synthesis-node-search node)) (before (ledger-total (search-job-ledger search)))
              (results (search-job-results search)))
         (search-step search 1)
         (charge ledger :child-search (- (ledger-total (search-job-ledger search)) before))
         (unless (or (eq results (search-job-results search))
                     ;; Already promoted from Stage A; verifying it again adds nothing.
                     (equal (candidate-expression (first (search-job-results search)))
                            (exact-heuristic-program node job))
                     (not (valid-job-node-candidate-p job node
                                                      (candidate-expression (first (search-job-results search))))))
           (let ((candidate (first (search-job-results search))))
             (enqueue-node-candidate job node (candidate-expression candidate) candidate)
             (dolist (follower (synthesis-node-followers node))
               (when (and (<= (candidate-size candidate) (synthesis-node-bound follower))
                          (valid-job-node-candidate-p job follower (candidate-expression candidate)))
                 (enqueue-node-candidate job follower (candidate-expression candidate) candidate)))))
         (when (search-bound-complete-p search (synthesis-node-bound node))
           (setf (synthesis-node-phase node) :done)
           (synthesis-message job node :bounded-exhaustion
                              (list :scope :child-grammar :results (length (search-job-results search))))))))))

(defun resume-synthesis (job work-limit &key stop-on-first)
  "Absolute cumulative tariff budget. Every fourth quantum reserves the root search.
All composed candidates are checked and scored at the root; no local gain is required.
The best verified candidate is available after every call, so a job may be resumed
with a larger limit at any time."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (synthesis-job-ledger job)) work-limit)
                   (not (synthesis-finished-p job))
                   (not (and stop-on-first (synthesis-job-best job)))) do
    (cond
      ((or (null (synthesis-job-active job)) (zerop (synthesis-job-remaining job)))
       (charge (synthesis-job-ledger job) :scheduling) (select-synthesis-lane job))
      (t
       (let ((active (synthesis-job-active job)))
         (cond ((eq active :verify) (synthesis-verification-step job))
               ((consp active)
                (if (eq :done (synthesis-node-expansion (cdr active)))
                    (setf (synthesis-job-active job) nil)
                    (synthesis-expansion-step job (cdr active))))
               ((eq :done (synthesis-node-phase active)) (setf (synthesis-job-active job) nil))
               (t (synthesis-node-step job active))))
       (decf (synthesis-job-remaining job)))))
  (when (synthesis-job-self-name job)
    (if (synthesis-job-best job)
        (activate-job-candidate-body job (candidate-expression (synthesis-job-best job)) :finalize-p t)
        (activate-job-oracle job)))
  (synthesis-message job (synthesis-job-root job)
                     (cond ((synthesis-finished-p job) :bounded-exhaustion)
                           ((and stop-on-first (synthesis-job-best job)) :candidate) (t :cutoff))
                     (list :scope :configured-proposals :best (synthesis-job-best job))))

(defun synthesis-episode-returns (job &key (search-weight 0) (default-baseline 1000))
  "Compute realized M8D search-episode returns G_t = B_t - B_T - search-weight * (W_T - W_t)
for each recorded scheduling decision in (synthesis-job-trace job)."
  (let* ((w-final (ledger-total (synthesis-job-ledger job)))
         (b-final (if (synthesis-job-best job)
                      (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))
                      default-baseline)))
    (loop for entry in (reverse (synthesis-job-trace job))
          for bt = (or (getf entry :best-score) default-baseline)
          for wt = (getf entry :work)
          collect (append entry
                          (list :bt bt :b-final b-final :w-final w-final
                                :return (- (- bt b-final)
                                           (* search-weight (- w-final wt))))))))

(defun make-search-trace-frame (jobs-or-job &key (work-scale 64) ledger)
  "Package quantitative leaf outcomes (work spent, residual bits, exhaustion status) from
explored branches of JOBS-OR-JOB into an ordinary `frame` over
`((0 . :int) (1 . :int) (2 . :int) (3 . :int)) -> :int` so `condense-heuristic` can
induce a priority predictor `\\hat{\\pi}`."
  (let* ((jobs (if (listp jobs-or-job) jobs-or-job (list jobs-or-job)))
         (inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
         (by-known (make-hash-table :test #'equal))
         (ordered-knowns nil))
    (dolist (job jobs)
      (dolist (node (synthesis-job-nodes job))
        (let ((h-model (synthesis-node-heuristic node))
              (frame (synthesis-node-frame node)))
          (when (and h-model frame)
            (let* ((known (node-trace-features node frame h-model))
                   (search (synthesis-node-search node))
                   (search-work (if search (ledger-total (search-job-ledger search)) 0))
                   (solved-p (or (exact-heuristic-program node job)
                                 (and search (search-job-best search))))
                   (outcome (+ (first known)
                               (* 2 (second known))
                               (floor search-work (max 1 work-scale))
                               (if solved-p 0 10)))
                   (existing (gethash known by-known)))
              (charge ledger :orientation 1)
              (if existing
                  (setf (gethash known by-known) (min existing outcome))
                  (progn
                    (setf (gethash known by-known) outcome)
                    (push known ordered-knowns))))))))
    (make-frame (make-schema :domain :int :inputs inputs :target :int)
                (loop for known in (nreverse ordered-knowns)
                      for idx from 0
                      for target-val = (gethash known by-known)
                      collect (make-row :key idx
                                        :known (copy-list known)
                                        :requirement (singleton-requirement :int target-val))))))

(defun condense-search-heuristic (trace-frame &key language description-limit
                                                   (work-limit 10000) ledger)
  "Condense a search-trace frame of quantitative leaf outcomes into an S-expression
priority predictor program `\\hat{\\pi}` + residual `\\varepsilon` using `condense-heuristic`.
At deployment time, the returned predictor function evaluates `\\hat{\\pi}` in the VM and
discards the training residual `\\varepsilon`.
Returns (VALUES predictor-fn heuristic-model)."
  (let* ((inputs (schema-inputs (frame-schema trace-frame)))
         (eff-limit (or description-limit (+ (header-size inputs :int) 24)))
         (eff-lang (or language
                       (make-language :int inputs
                                      :operators (list (op :+ :int) (op :* :int) (op :- :int))
                                      :literals '(0 1 2))))
         (h-model (condense-heuristic trace-frame eff-lang
                                      :description-limit eff-limit
                                      :work-limit work-limit
                                      :ledger ledger))
         (program (and h-model (heuristic-program h-model)))
         (predictor-fn
           (when program
             (lambda (node frame node-lang node-h-model)
               (declare (ignore node-lang))
               (if (null node-h-model)
                   most-positive-fixnum
                   (let ((features (node-trace-features node frame node-h-model)))
                     (multiple-value-bind (val ok) (eval-expr-value program inputs features)
                       (if (and ok (integerp val)) val most-positive-fixnum))))))))
    (values predictor-fn h-model)))

(defun explain-synthesis-node (node &key job stream)
  "Return a structured causal summary plist for NODE (and print it to STREAM when non-NIL).
Shows the ancestor decoder chain from the root, reconstructed partial AST with hole,
bindings, row status breakdown, Stage A heuristic model, conflicts/nogoods, and search results."
  (let* ((ancestors (loop for cur = node then (synthesis-node-parent cur)
                          while cur collect cur into chain
                          finally (return (nreverse chain))))
         (proposal (synthesis-node-proposal node))
         (frame (synthesis-node-frame node))
         (target (when frame (schema-target (frame-schema frame))))
         (hole-ast (when target (ignore-errors (reconstruct-synthesis-candidate node (hole 0 target)))))
         (rows-summary
           (when frame
             (loop for r in (frame-rows frame)
                   collect (list :key (row-key r)
                                 :known (row-known r)
                                 :status (cond ((unconstrained-requirement-p (row-requirement r))
                                                :dead-unconstrained)
                                               ((member :unresolved (row-known r))
                                                :unresolved)
                                               (t :constrained))
                                 :requirement (row-requirement r)))))
         (h-model (synthesis-node-heuristic node))
         (search (synthesis-node-search node))
         (report
           (list :node-id (synthesis-node-id node)
                 :depth (node-depth node)
                 :phase (synthesis-node-phase node)
                 :expansion (synthesis-node-expansion node)
                 :path (mapcar (lambda (n)
                                 (list :id (synthesis-node-id n)
                                       :proposal (when (synthesis-node-proposal n)
                                                   (decomposition-name (synthesis-node-proposal n)))))
                               ancestors)
                 :reconstructed-hole-ast hole-ast
                 :bindings (when proposal (decomposition-bindings proposal))
                 :lift-p (when proposal (decomposition-lift-p proposal))
                 :proposal-provenance (when proposal (decomposition-provenance proposal))
                 :node-provenance (synthesis-node-provenance node)
                 :priority (synthesis-node-priority node)
                 :stage-a (when h-model
                            (list :program (heuristic-program h-model)
                                  :exact-p (heuristic-exact-p h-model)
                                  :score (heuristic-score h-model)
                                  :residual (heuristic-residual h-model)
                                  :unresolved-keys (heuristic-unresolved-keys h-model)))
                 :reused-from (synthesis-node-reused-from node)
                 :rows rows-summary
                 :search-results (when search
                                   (mapcar #'candidate-expression (search-job-results search)))
                 :job-work (when job (ledger-total (synthesis-job-ledger job))))))
    (when stream
      (format stream "~&=== Synthesis Node ~D (depth ~D, phase ~S, priority ~S) ===~%"
              (getf report :node-id) (getf report :depth) (getf report :phase) (getf report :priority))
      (format stream "  Path: ~S~%" (getf report :path))
      (when hole-ast
        (format stream "  Reconstructed AST with ?0: ~S~%" hole-ast))
      (when (getf report :bindings)
        (format stream "  Bindings: ~S~%" (getf report :bindings)))
      (when (getf report :proposal-provenance)
        (format stream "  Proposal Provenance: ~S~%" (getf report :proposal-provenance)))
      (when (getf report :node-provenance)
        (format stream "  Node Provenance: ~S~%" (getf report :node-provenance)))
      (when (getf report :stage-a)
        (format stream "  Stage A: ~S~%" (getf report :stage-a)))
      (when rows-summary
        (format stream "  Rows (~D):~%" (length rows-summary))
        (dolist (rs rows-summary)
          (format stream "    ~S~%" rs)))
      (when (getf report :search-results)
        (format stream "  Search Results: ~S~%" (getf report :search-results))))
    report))

(defun explain-synthesis-job (job &key stream)
  "Return a structured causal summary plist of JOB's entire synthesis DAG (and print to STREAM when non-NIL)."
  (let* ((node-reports (mapcar (lambda (n) (explain-synthesis-node n :job job))
                               (synthesis-job-nodes job)))
         (summary
           (list :work (ledger-total (synthesis-job-ledger job))
                 :self-name (synthesis-job-self-name job)
                 :debug-p (synthesis-job-debug-p job)
                 :best (when (synthesis-job-best job)
                         (candidate-expression (synthesis-job-best job)))
                 :results (mapcar #'candidate-expression (synthesis-job-results job))
                 :reused-subproblems (synthesis-job-reused-subproblems job)
                 :nogoods (synthesis-job-nogoods job)
                 :nodes node-reports)))
    (when stream
      (format stream "~&=== Synthesis Job Summary (work ~D, self ~S, best ~S) ===~%"
              (getf summary :work) (getf summary :self-name) (getf summary :best))
      (when (getf summary :nogoods)
        (format stream "  Nogoods (~D): ~S~%" (length (getf summary :nogoods)) (getf summary :nogoods)))
      (dolist (n (synthesis-job-nodes job))
        (explain-synthesis-node n :job job :stream stream)))
    summary))

;;; Stage A -> Stage B Residual Pullback Decompositions & Heuristic Synthesis

(defun additive-residual-type-p (type)
  "True when TYPE supports additive displacement decoders (:int, (:gf p), or tuples thereof)."
  (or (eq type :int)
      (and (consp type) (eq :gf (first type)))
      (and (consp type) (eq :tuple (first type))
           (every #'additive-residual-type-p (rest type)))))

(defun make-additive-residual-decoder (base-expr residual-var type)
  "Construct outer decoder d(X, Z) = base(X) + Z for scalar or tuple TYPE."
  (cond
    ((or (eq type :int) (and (consp type) (eq :gf (first type))))
     (app (op :+ type) base-expr residual-var))
    ((and (consp type) (eq :tuple (first type)))
     (apply #'app (op :tuple type)
            (loop for part-type in (rest type)
                  for idx from 0
                  collect (make-additive-residual-decoder
                           (app (op :at type) base-expr (lit :int idx))
                           (app (op :at type) residual-var (lit :int idx))
                           part-type))))
    (t (error "Unsupported additive residual type ~S" type))))

(defun row-active-for-guard-p (row heuristic-model)
  "True when ROW is a constrained row whose outcome under HEURISTIC-MODEL is resolved,
or when HEURISTIC-MODEL has no concrete residuals and ROW is an unresolved constrained row."
  (and (not (unconstrained-requirement-p (row-requirement row)))
       (or (null (heuristic-residual heuristic-model))
           (not (member (row-key row) (heuristic-unresolved-keys heuristic-model) :test #'equal)))))

(defun heuristic-hit-mask (frame heuristic-model)
  "Return the per-row Boolean hit mask (T on satisfied rows, NIL on unary residual rows)."
  (let ((residuals (heuristic-residual heuristic-model))
        (unresolved (heuristic-unresolved-keys heuristic-model)))
    (loop for row in (frame-rows frame)
          for key = (row-key row)
          collect (if residuals
                      (null (assoc key residuals :test #'equal))
                      (not (member key unresolved :test #'equal))))))

(defun default-guard-language (frame language)
  "Construct a Boolean guard language over FRAME's inputs for exception-patching."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (domain (language-domain language))
         (eq-ops (cons (op := domain) (mapcar (lambda (spec) (op := (cdr spec))) inputs)))
         (lt-ops (remove-if-not (lambda (o)
                                  (and (operator-p o) (eq :< (operator-name o))))
                                (language-operators language)))
         (domain-ops (remove-if (lambda (o)
                                  (and (consp (operator-type o))
                                       (eq :bool (car (last (operator-type o))))))
                                (language-operators language)))
         (seq-empty-constants
           (loop for (nil . type) in inputs
                 when (and (consp type) (eq :seq (first type)))
                   collect (lit type '()))))
    (make-language domain inputs
                   :operators (remove-duplicates (append eq-ops lt-ops (list (op :if :bool)) domain-ops)
                                                 :test #'equal)
                   :literals (if (listp (language-literals language))
                                 (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                                 (language-literals language))
                   :constants (remove-duplicates (append seq-empty-constants (language-constants language))
                                                 :test #'equal))))

(defun find-sound-exception-guard (frame hit-mask guard-language guard-bound work-limit ledger
                                   &key active-mask)
  "Synthesize a Boolean guard G(X) separating hit and miss rows.
Returns (VALUES guard invert-p): when INVERT-P is NIL, G(X) is T only on hits; when
INVERT-P is T, G(X) is NIL only on hits. Guards are grouped observationally; the most
covering sound one wins (an exact separator covers every hit), then the shortest."
  (let* ((obs (start-observation-search (make-observation-scope (support-frame frame hit-mask ledger)
                                                                guard-language)))
         (obs-before (ledger-total (observation-job-ledger obs)))
         (inputs (schema-inputs (frame-schema frame)))
         (rows (frame-rows frame))
         (eff-active (or active-mask
                         (let ((constrained (mapcar (lambda (r)
                                                      (not (unconstrained-requirement-p (row-requirement r))))
                                                    rows)))
                           (if (some #'identity constrained)
                               constrained
                               (make-list (length rows) :initial-element t)))))
         (best-expr nil) (best-inv nil) (best-hits 0) (best-bits most-positive-fixnum))
    (resume-observation-search obs guard-bound work-limit)
    (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
    (dolist (bucket (observation-job-buckets obs) (values best-expr best-inv))
      (when (eq :bool (observation-bucket-type bucket))
        (let ((vals (observation-bucket-values bucket))
              (sound-hit-p t) (sound-miss-p t) (hits 0) (inv-hits 0))
          (loop for v in vals for h in hit-mask for active-p in eff-active
                when active-p do
                  (if h (if v (incf hits) (incf inv-hits))
                      (if v (setf sound-hit-p nil) (setf sound-miss-p nil))))
          (when (or (and sound-hit-p (plusp hits)) (and sound-miss-p (plusp inv-hits)))
            (let* ((use-inv-p (and sound-miss-p (or (not sound-hit-p) (> inv-hits hits))))
                   (eff-hits (if use-inv-p inv-hits hits))
                   (expr (observed-expression-expression (car (last (observation-bucket-members bucket)))))
                   (bits (description-size expr inputs)))
              (when (or (> eff-hits best-hits) (and (= eff-hits best-hits) (< bits best-bits)))
                (setf best-expr expr best-inv use-inv-p best-hits eff-hits best-bits bits)))))))))

(defun find-oracle-operator-name (language)
  "Return the operator name of any oracle-backed function in LANGUAGE, or NIL."
  (loop for o in (language-operators language)
        when (operator-p o) do
          (let ((def (find-function-definition (operator-name o))))
            (when (and def (function-definition-oracle-table def))
              (return (operator-name o))))))

(defun model-satisfies-empty-sequence-rows-p (frame hit-mask)
  "True when HIT-MASK is T on every constrained row where some sequence input Xi is '()."
  (let ((inputs (schema-inputs (frame-schema frame)))
        (rows (frame-rows frame)))
    (loop for (nil . type) in inputs
          for pos from 0
          thereis (and (consp type) (eq :seq (first type))
                       (let ((has-empty nil)
                             (all-hit t))
                         (loop for row in rows
                               for hit-p in hit-mask
                               when (and (not (unconstrained-requirement-p (row-requirement row)))
                                         (null (nth pos (row-known row))))
                                 do (setf has-empty t)
                                    (unless hit-p (setf all-hit nil)))
                         (and has-empty all-hit))))))

(defun lift-inductive-sequence-context (guard invert-p inputs language child-language child-id eff-self)
  "When GUARD is an empty-sequence check `(= Xi '())` with INVERT-P NIL (so the residual child
lives in the non-empty else branch) and LANGUAGE provides `:at` and `:tail`, lift `(at Xi '0)`
and `(<eff-self> ... (tail Xi) ...)` (or `(tail Xi)`) into the child's bindings and grammar.
Returns (VALUES bindings language lifted-seq-id)."
  (let ((seq-id (and (not invert-p)
                     (some (lambda (o) (and (operator-p o) (eq :at (operator-name o))))
                           (language-operators language))
                     (some (lambda (o) (and (operator-p o) (eq :tail (operator-name o))))
                           (language-operators language))
                     (empty-sequence-guard-var-id guard (mapcar #'car inputs)))))
    (if (null seq-id)
        (values (identity-bindings inputs) child-language nil)
        (let* ((seq-type (cdr (assoc seq-id inputs :test #'eql)))
               (elem-type (second seq-type))
               (other-inputs (remove seq-id inputs :key #'car :test #'eql))
               (head-expr (app (op :at seq-type) (var seq-id seq-type) (lit :int 0)))
               (tail-expr (app (op :tail elem-type) (var seq-id seq-type)))
               (recur-expr (when eff-self
                             (apply #'app (op eff-self)
                                    (loop for (id . type) in inputs
                                          collect (if (eql id seq-id) tail-expr (var id type))))))
               (step-expr (or recur-expr tail-expr))
               (lifted-bindings (if (null other-inputs)
                                    (list (cons 0 head-expr) (cons 1 step-expr))
                                    (append (identity-bindings inputs)
                                            (list (cons child-id head-expr)
                                                  (cons (1+ child-id) step-expr)))))
               (child-inputs (mapcar (lambda (b)
                                       (cons (car b) (expression-type (cdr b) inputs)))
                                     lifted-bindings))
               (child-ops (remove-if (lambda (o)
                                       (and (operator-p o)
                                            (member (operator-name o)
                                                    (list :at :tail := :if eff-self))))
                                     (language-operators language)))
               (child-constants (remove (lit seq-type '())
                                        (language-constants language)
                                        :test #'equal)))
          (values lifted-bindings
                  (make-language (language-domain language) child-inputs
                                 :operators child-ops
                                 :literals (language-literals language)
                                 :constants child-constants)
                  seq-id)))))

(defun heuristic-decompositions (frame language &key heuristic-model child-language guard-language
                                                     description-limit child-bound guard-bound
                                                     (work-limit 50000) (run-weight 0)
                                                     (additive-p t) (conditional-p t)
                                                     self-name solver ledger
                                                     (debug-p *synthesis-debug-mode*))
  "Bridge Stage A heuristic condensation to Stage B recursive synthesis by turning
a non-exact `heuristic-model` into additive displacement and/or conditional
exception-patching `decomposition` proposals. When a conditional guard is an
empty-sequence check `(= Xi '())`, lifts `(at Xi '0)` and `(<self-name> ... (tail Xi) ...)`
into the non-empty branch's child bindings via `lift-inductive-sequence-context`.
Returns (VALUES proposals heuristic-model)."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (bound (or description-limit (+ (header-size inputs target) 18)))
         (c-bound (or child-bound bound))
         (g-bound (or guard-bound (+ (header-size inputs :bool)
                                     (if (>= (length inputs) 4) 22 20))))
         (c-lang (or child-language language))
         (eff-self (or self-name (find-oracle-operator-name language)))
         (empty-seq-frame-p (frame-has-empty-sequence-row-p frame))
         (condense-budget (if heuristic-model 0 (max 1 (if conditional-p (floor work-limit 2) work-limit))))
         (h-model (or heuristic-model
                      (condense-heuristic frame language
                                          :description-limit bound
                                          :work-limit condense-budget
                                          :run-weight run-weight
                                          :ledger ledger))))
    (when (or (null h-model)
              (and (heuristic-exact-p h-model)
                   (null (heuristic-unresolved-keys h-model))
                   (or (null eff-self)
                       (expression-calls-operator-p (heuristic-program h-model) eff-self))))
      (return-from heuristic-decompositions (values nil h-model)))
    (let* ((program (heuristic-program h-model))
           (child-id (next-child-id inputs))
           (child-var (var child-id target))
           (bindings (identity-bindings inputs))
           (hit-mask (heuristic-hit-mask frame h-model))
           (proposals nil))
      ;; Path B1: Additive / displacement residual decoder d(X, Z) = pi_hat(X) + Z.
      ;; Purely relational residuals leave no row displacement to synthesize.
      (when (and additive-p (heuristic-total-p h-model) (additive-residual-type-p target)
                 (some #'null hit-mask)
                 (not (and eff-self empty-seq-frame-p)))
        (push (make-decomposition
               :name (list :heuristic-additive program)
               :decoder (make-additive-residual-decoder program child-var target)
               :child-id child-id
               :child-type target
               :bindings bindings
               :language c-lang
               :bound c-bound
               :solver solver
               :provenance (when debug-p
                             (list :origin :stage-b-additive
                                   :base-program program
                                   :stage-a-score (heuristic-score h-model)
                                   :stage-a-residual (heuristic-residual h-model))))
              proposals))
      ;; Path B2: Conditional exception-patching decoder d(X, Z) = (if G pi_hat Z) or (if G_miss Z pi_hat)
      (when conditional-p
        (let* ((candidates (if (or empty-seq-frame-p eff-self)
                               (cons h-model (heuristic-alternatives h-model))
                               (list h-model)))
               (valid-base-p
                 (lambda (m)
                   (and (not (and eff-self
                                  (heuristic-exact-p m)
                                  (null (heuristic-unresolved-keys m))
                                  (not (expression-calls-operator-p (heuristic-program m) eff-self))))
                        (let ((mask (heuristic-hit-mask frame m)))
                          (and (some #'identity mask)
                               (some #'null mask)
                               (or (not empty-seq-frame-p)
                                   (model-satisfies-empty-sequence-rows-p frame mask)))))))
               (cand-model (find-if valid-base-p candidates)))
          (when cand-model
            (let ((cand-program (heuristic-program cand-model))
                  (cand-hit-mask (heuristic-hit-mask frame cand-model))
                  (cand-active-mask (loop for row in (frame-rows frame)
                                          collect (row-active-for-guard-p row cand-model)))
                  (g-lang (or guard-language (default-guard-language frame language))))
              (multiple-value-bind (guard invert-p)
                  (find-sound-exception-guard frame cand-hit-mask g-lang g-bound
                                              (max 1 (- work-limit condense-budget)) ledger
                                              :active-mask cand-active-mask)
                (when guard
                  (multiple-value-bind (eff-bindings eff-lang seq-id)
                      (lift-inductive-sequence-context guard invert-p inputs language c-lang child-id eff-self)
                    (push (make-decomposition
                           :name (list :heuristic-conditional guard cand-program)
                           :decoder (if invert-p
                                        (app (op :if target) guard child-var cand-program)
                                        (app (op :if target) guard cand-program child-var))
                           :child-id child-id
                           :child-type target
                           :bindings eff-bindings
                           :language eff-lang
                           :bound c-bound
                           :solver solver
                           :provenance (when debug-p
                                         (list :origin (if seq-id :inductive-sequence-lift :stage-b-conditional)
                                               :base-program cand-program
                                               :guard guard
                                               :invert-p invert-p
                                               :lifted-sequence-id seq-id
                                               :lifted-bindings eff-bindings
                                               :stage-a-score (heuristic-score cand-model)
                                               :stage-a-residual (heuristic-residual cand-model)
                                               :stage-a-unresolved (heuristic-unresolved-keys cand-model))))
                          proposals))))))))
      (values (nreverse proposals) h-model))))

(defun candidate-library-definitions (language &key self-name functions)
  "Return higher-order `function-definition`s eligible for `library-decompositions`:
defined functions with a concrete body (excluding SELF-NAME) that take exactly one `:code`
parameter whose return sort is first-order."
  (let* ((op-names (loop for o in (language-operators language)
                         when (and (operator-p o) (defined-function-p (operator-name o)))
                           collect (operator-name o)))
         (names (remove-duplicates
                 (or functions
                     (append op-names (reverse *registered-function-names*)))
                 :test #'eq
                 :from-end t)))
    (loop for name in names
          for def = (and (not (eq name self-name)) (find-function-definition name))
          when (and def
                    (function-definition-body def)
                    (null (function-definition-oracle-table def))
                    (= 1 (count-if (lambda (spec) (code-type-p (cdr spec)))
                                   (function-definition-inputs def)))
                    (let ((code-spec (find-if (lambda (spec) (code-type-p (cdr spec)))
                                              (function-definition-inputs def))))
                      (not (function-sort-p (code-sort (cdr code-spec))))))
            collect def)))

(defun candidate-fo-argument-expressions (frame language primary-input-id param-type)
  "Return candidate AST expressions of PARAM-TYPE to supply a non-primary first-order
parameter (such as a fold base-case accumulator) of a higher-order library combinator."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (primary-pos (and primary-input-id (position primary-input-id inputs :key #'car :test #'eql)))
         (primary-type (and primary-pos (cdr (nth primary-pos inputs))))
         (exprs nil))
    (flet ((add-expr (e) (pushnew e exprs :test #'equal)))
      ;; 1. Empty-sequence row target value when primary input is a sequence and PARAM-TYPE = TARGET
      (when (and primary-pos
                 (consp primary-type) (eq :seq (first primary-type))
                 (equal param-type target))
        (dolist (row (frame-rows frame))
          (when (and (not (unconstrained-requirement-p (row-requirement row)))
                     (null (nth primary-pos (row-known row))))
            (let ((allowed (extract-allowed-values (row-requirement row))))
              (when (and (consp allowed) (= 1 (length allowed)))
                (add-expr (lit param-type (first allowed))))))))
      ;; 2. Unused parent input variables of matching type
      (dolist (spec inputs)
        (when (and (not (eql (car spec) primary-input-id))
                   (equal (cdr spec) param-type))
          (add-expr (var (car spec) (cdr spec)))))
      ;; 3. Language constants, literals, and default value of PARAM-TYPE
      (dolist (c (language-constants language))
        (when (equal (ast-type c) param-type)
          (add-expr c)))
      (when (and (consp param-type) (eq :seq (first param-type)))
        (add-expr (lit param-type '())))
      (when (and (eq param-type :int) (listp (language-literals language)))
        (dolist (v (language-literals language))
          (when (integerp v)
            (add-expr (lit :int v)))))
      (add-expr (lit param-type (default-value-for-type param-type)))
      (nreverse exprs))))

(defun library-decoder-compatible-with-empty-rows-p (frame seq-input-id decoder child-id child-type bindings ledger)
  "Check that DECODER does not immediately contradict any empty-sequence row of FRAME."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (seq-pos (and seq-input-id (position seq-input-id inputs :key #'car :test #'eql)))
         (seq-type (and seq-pos (cdr (nth seq-pos inputs))))
         (empty-rows (when (and seq-pos (consp seq-type) (eq :seq (first seq-type)))
                       (remove-if-not (lambda (row)
                                        (and (not (unconstrained-requirement-p (row-requirement row)))
                                             (null (nth seq-pos (row-known row)))))
                                      (frame-rows frame)))))
    (if (null empty-rows)
        t
        (let* ((sub-frame (make-frame (frame-schema frame) empty-rows))
               (raw (pullback-frame sub-frame decoder child-id child-type bindings ledger))
               (checker-schema (make-schema :inputs (cons (cons 0 child-type)
                                                          (schema-inputs (frame-schema raw)))
                                            :target :bool)))
          (every (lambda (r)
                   (not (unsatisfiable-requirement-p
                         (fold-constants (row-requirement r) checker-schema
                                         :ledger ledger :budget 500))))
                 (frame-rows raw))))))

(defun library-decompositions (frame language &key child-language child-bound
                                                   self-name functions solver ledger
                                                   (debug-p *synthesis-debug-mode*))
  "Propose registered higher-order library definitions (`:fa`, `:fb`, ...) whose return type
matches FRAME's target as `:lift-p t` decompositions. Function-typed (`:code`) parameters
become lifted child frames via `lift-frame`, while unconsumed parent inputs are passed
through `bindings` so `compose-lifted-model` can synthesize `:code-subst` closures."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (c-bound (or child-bound (+ (header-size inputs target) 24)))
         (base-lang (or child-language language))
         (child-id (next-child-id inputs))
         (defs (candidate-library-definitions language :self-name self-name :functions functions))
         (proposals nil))
    (dolist (def defs (nreverse proposals))
      (when (equal (function-definition-return-type def) target)
        (let* ((fn-name (function-definition-name def))
               (fn-inputs (function-definition-inputs def))
               (code-spec (find-if (lambda (s) (code-type-p (cdr s))) fn-inputs))
               (code-param-id (car code-spec))
               (code-param-type (cdr code-spec))
               (code-in (code-inputs code-param-type))
               (ret (code-sort code-param-type))
               (child-var (var child-id code-param-type))
               (fo-specs (remove code-param-id fn-inputs :key #'car :test #'eql)))
          (if (null fo-specs)
              (let* ((decoder (app (op fn-name) child-var))
                     (next-cid (next-child-id code-in))
                     (bindings (loop for (in-id . in-type) in inputs
                                     collect (prog1 (cons next-cid (var in-id in-type))
                                               (incf next-cid))))
                     (extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))
                     (child-inputs (append (copy-tree code-in) extra-in))
                     (c-lang (make-language (language-domain base-lang)
                                            child-inputs
                                            :operators (remove (op fn-name) (language-operators base-lang) :test #'equal)
                                            :literals (language-literals base-lang)
                                            :constants (language-constants base-lang))))
                (push (make-decomposition
                       :name (list :library fn-name)
                       :decoder decoder
                       :child-id child-id
                       :child-type code-param-type
                       :bindings bindings
                       :language c-lang
                       :bound c-bound
                       :lift-p t
                       :solver solver
                       :provenance (when debug-p
                                     (list :origin :library-expander
                                           :function fn-name
                                           :decoder decoder)))
                      proposals))
              (let ((primary-spec (first fo-specs))
                    (extra-fo-specs (rest fo-specs)))
                (dolist (p-spec inputs)
                  (when (equal (cdr p-spec) (cdr primary-spec))
                    (let* ((p-id (car p-spec))
                           (primary-expr (var p-id (cdr p-spec)))
                           (extra-options
                             (mapcar (lambda (espec)
                                       (candidate-fo-argument-expressions frame language p-id (cdr espec)))
                                     extra-fo-specs)))
                      (dolist (extra-tuple (cartesian-product-lists extra-options))
                        (let* ((fo-alist (cons (cons (car primary-spec) primary-expr)
                                               (mapcar #'cons (mapcar #'car extra-fo-specs) extra-tuple)))
                               (call-args (loop for (param-id . nil) in fn-inputs
                                                collect (if (eql param-id code-param-id)
                                                            child-var
                                                            (cdr (assoc param-id fo-alist :test #'eql)))))
                               (decoder (apply #'app (op fn-name) call-args))
                               (consumed-ids (loop for arg in call-args
                                                   when (var-p arg) collect (ast-id arg)))
                               (next-cid (next-child-id code-in))
                               (bindings (loop for (in-id . in-type) in inputs
                                               unless (member in-id consumed-ids :test #'eql)
                                                 collect (prog1 (cons next-cid (var in-id in-type))
                                                           (incf next-cid)))))
                          (when (library-decoder-compatible-with-empty-rows-p
                                 frame p-id decoder child-id code-param-type bindings ledger)
                            (let* ((extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))
                                   (child-inputs (append (copy-tree code-in) extra-in))
                                   (has-seq-in-p (some (lambda (s)
                                                         (and (consp (cdr s)) (eq :seq (first (cdr s)))))
                                                       child-inputs))
                                   (has-seq-ret-p (and (consp ret) (eq :seq (first ret))))
                                   (child-ops
                                     (remove-if
                                      (lambda (o)
                                        (and (operator-p o)
                                             (let ((oname (operator-name o)))
                                               (or (eq oname self-name)
                                                   (eq oname fn-name)
                                                   (let ((odef (find-function-definition oname)))
                                                     (and odef
                                                          (or (function-definition-oracle-table odef)
                                                              (some (lambda (s) (code-type-p (cdr s)))
                                                                    (function-definition-inputs odef)))))
                                                   (and (not has-seq-in-p)
                                                        (member oname '(:at :tail :length)))
                                                   (and (not has-seq-in-p)
                                                        (not has-seq-ret-p)
                                                        (eq oname :cons))
                                                   (and (not has-seq-in-p)
                                                        (eq oname :=)
                                                        (consp (operator-operand-type o))
                                                        (eq :seq (first (operator-operand-type o))))))))
                                      (language-operators base-lang)))
                                   (child-consts
                                     (if (or has-seq-in-p has-seq-ret-p)
                                         (language-constants base-lang)
                                         (remove-if (lambda (c)
                                                      (and (consp (ast-type c))
                                                           (eq :seq (first (ast-type c)))))
                                                    (language-constants base-lang))))
                                   (c-lang (make-language (language-domain base-lang)
                                                          child-inputs
                                                          :operators child-ops
                                                          :literals (language-literals base-lang)
                                                          :constants child-consts)))
                              (push (make-decomposition
                                     :name (cons :library (cons fn-name extra-tuple))
                                     :decoder decoder
                                     :child-id child-id
                                     :child-type code-param-type
                                     :bindings bindings
                                     :language c-lang
                                     :bound c-bound
                                     :lift-p t
                                     :solver solver
                                     :provenance (when debug-p
                                                   (list :origin :library-expander
                                                         :function fn-name
                                                         :decoder decoder
                                                         :bindings bindings)))
                                    proposals)))))))))))))))

(defun library-expander (&key child-language child-bound functions)
  "An `:expand` function that proposes registered higher-order library combinators
whose return type matches the node's target as `:lift-p t` decompositions."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    (let* ((proposal (synthesis-node-proposal node))
           (bound (or child-bound
                      (synthesis-node-bound node)
                      (and proposal (decomposition-bound proposal)))))
      (unless (and proposal (decomposition-lift-p proposal))
        (library-decompositions frame language
                                :child-language child-language
                                :child-bound bound
                                :self-name (and job (synthesis-job-self-name job))
                                :functions functions
                                :solver (and job (synthesis-job-library job))
                                :ledger ledger
                                :debug-p (and job (synthesis-job-debug-p job)))))))

(defun combine-expanders (&rest expanders)
  "Compose multiple `:expand` functions into a single expander without baked-in policy."
  (lambda (job node frame language h-model ledger)
    (loop for exp in expanders
          when exp
            append (funcall exp job node frame language h-model ledger))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p) (debug-p *synthesis-debug-mode*))
  "Make dependency hypotheses explicit. FEATURES are synthesized DSL expressions;
the default seed vocabulary is each available coordinate and the empty context.
Every hypothesis competes with direct synthesis on the full original frame."
  (let* ((inputs-spec (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (child-id (next-child-id inputs-spec)))
    (loop for feature in (cons nil (if features-p features
                                     (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs-spec)))
          for inputs = (when feature (list (cons 0 (ast-type feature))))
          collect (make-decomposition
                   :name (list :dependency feature) :decoder (var child-id target)
                   :child-id child-id :child-type target :bindings (when feature (list (cons 0 feature)))
                   :language (make-language (language-domain language) inputs :operators (language-operators language)
                                            :literals (language-literals language) :constants (language-constants language))
                   :bound child-bound
                   :provenance (when debug-p (list :origin :dependency :feature feature))))))

(defun selector-decompositions (frame language bound &key fibers dependencies (debug-p *synthesis-debug-mode*))
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (id (next-child-id inputs)))
    (append (when fibers
              (list (make-decomposition :name :fibers :decoder (var id target) :child-id id
                                        :child-type target :bindings (identity-bindings inputs)
                                        :language language :bound bound :fiber-p t
                                        :provenance (when debug-p (list :origin :fibers)))))
            (when dependencies
              (dependency-proposals frame language bound :debug-p debug-p)))))

(defun start-selector-search (frame language description-limit &key (fibers t) dependencies)
  "Price direct selector synthesis alongside optional fiber and dependency proposals."
  (start-synthesis frame language description-limit
                   :decompositions (selector-decompositions frame language description-limit
                                                            :fibers fibers :dependencies dependencies)))

(defun heuristic-expander (&key child-language guard-language child-bound guard-bound
                                (work-limit 20000) (additive-p t) (conditional-p t)
                                (library-proposals-p t) library-functions)
  "An `:expand` function: each node turns its own Stage A model into Stage B additive and
conditional residual branches (plus higher-order library combinator branches when
LIBRARY-PROPOSALS-P is true and no de novo SELF-NAME is active), so every proposal
competes under Stage A full-path pricing and the 3:1 reserve schedule."
  (lambda (job node frame language h-model ledger)
    (let* ((inputs (schema-inputs (frame-schema frame)))
           (proposal (synthesis-node-proposal node))
           (bound (or (synthesis-node-bound node) (and proposal (decomposition-bound proposal)))))
      (flet ((matching (lang) (and lang (equal (language-inputs lang) inputs) lang)))
        (let ((stage-b (heuristic-decompositions frame language
                                                 :heuristic-model h-model
                                                 :child-language (matching child-language)
                                                 :guard-language (matching guard-language)
                                                 :description-limit bound
                                                 :child-bound (or child-bound bound)
                                                 :guard-bound guard-bound
                                                 :work-limit work-limit
                                                 :run-weight (synthesis-job-run-weight job)
                                                 :additive-p additive-p
                                                 :conditional-p conditional-p
                                                 :self-name (synthesis-job-self-name job)
                                                 :solver (synthesis-job-library job)
                                                 :ledger ledger
                                                 :debug-p (synthesis-job-debug-p job)))
              (lib-props (when (and library-proposals-p
                                    (not (and proposal (decomposition-lift-p proposal))))
                           (library-decompositions frame language
                                                   :child-language child-language
                                                   :child-bound (or child-bound bound)
                                                   :self-name (and job (synthesis-job-self-name job))
                                                   :functions library-functions
                                                   :solver (and job (synthesis-job-library job))
                                                   :ledger ledger
                                                   :debug-p (and job (synthesis-job-debug-p job))))))
          (append lib-props stage-b))))))

(defun start-heuristic-synthesis (frame language description-limit
                                  &key decompositions child-language guard-language
                                       child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 2000) (max-depth 2)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       (library-proposals-p t) library-functions
                                       library (run-weight 0) (quantum 32)
                                       self-name oracle-table (verification-row-budget 2000)
                                       priority-predictor (deductive-nogoods-p t)
                                       (debug-p *synthesis-debug-mode*))
  "Launch a `:policy :heuristic` synthesis job in which every node shallower than MAX-DEPTH,
root included, condenses a Stage A model of its own frame and proposes Stage B residual
and higher-order library branches through `heuristic-expander`. LIBRARY narrows every
pulled-back child frame."
  (let ((c-lang (or child-language language))
        (c-bound (or child-bound description-limit)))
    (start-synthesis frame language description-limit
                     :decompositions (append (selector-decompositions frame c-lang c-bound
                                                                      :fibers fibers :dependencies dependencies
                                                                      :debug-p debug-p)
                                             decompositions)
                     :run-weight run-weight
                     :quantum quantum
                     :policy :heuristic
                     :heuristic-budget heuristic-budget
                     :priority-predictor priority-predictor
                     :library library
                     :max-depth max-depth
                     :self-name self-name
                     :oracle-table oracle-table
                     :verification-row-budget verification-row-budget
                     :deductive-nogoods-p deductive-nogoods-p
                     :debug-p debug-p
                     :expand (heuristic-expander :child-language c-lang :guard-language guard-language
                                                 :child-bound c-bound :guard-bound guard-bound
                                                 :work-limit condense-budget
                                                 :additive-p additive-p :conditional-p conditional-p
                                                 :library-proposals-p library-proposals-p
                                                 :library-functions library-functions))))

(defun start-recursive-synthesis (frame language description-limit
                                  &key self-name oracle-table decompositions
                                       child-language guard-language child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 5000) (max-depth 2)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       (library-proposals-p nil) library-functions
                                       library (run-weight 0) (quantum 32)
                                       (verification-row-budget 2000)
                                       priority-predictor (deductive-nogoods-p t)
                                       (debug-p *synthesis-debug-mode*))
  "Launch a recursive synthesis job with oracle self-lifting for SELF-NAME (defaulting to
`next-function-name`). Extracts the partial oracle table from FRAME (unless ORACLE-TABLE
is supplied), condenses base-case and guard splits through standard Stage A/B heuristic
synthesis, lifts non-empty sequence projections `(at Xi '0)` and `(<self-name> ... (tail Xi) ...)`
into child frames, and verifies every candidate at the root by executing the concrete
recursive definition in the VM."
  (let* ((fn-name (or self-name (next-function-name)))
         (inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (eff-oracle (copy-tree (or oracle-table (frame-oracle-table frame))))
         (root-ops (remove-if (lambda (o) (and (operator-p o) (eq fn-name (operator-name o))))
                              (language-operators language)))
         (root-lang (make-language (language-domain language)
                                   (language-inputs language)
                                   :operators root-ops
                                   :literals (language-literals language)
                                   :constants (language-constants language))))
    (define-function fn-name inputs target nil :oracle-table eff-oracle)
    (start-heuristic-synthesis frame root-lang description-limit
                               :decompositions decompositions
                               :child-language child-language
                               :guard-language guard-language
                               :child-bound child-bound
                               :guard-bound guard-bound
                               :condense-budget condense-budget
                               :heuristic-budget heuristic-budget
                               :max-depth max-depth
                               :fibers fibers
                               :dependencies dependencies
                               :additive-p additive-p
                               :conditional-p conditional-p
                               :library-proposals-p library-proposals-p
                               :library-functions library-functions
                               :library library
                               :run-weight run-weight
                               :quantum quantum
                               :self-name fn-name
                               :oracle-table eff-oracle
                               :verification-row-budget verification-row-budget
                               :priority-predictor priority-predictor
                               :deductive-nogoods-p deductive-nogoods-p
                               :debug-p debug-p)))

(defstruct (dependency-search (:constructor %make-dependency-search))
  frame language observation feature-bound selector-bound synthesis
  (ledger (make-ledger)) (phase :features) records features (debt 0))

(defun start-dependency-search (frame feature-language selector-language feature-bound selector-bound)
  "Synthesize dependency features, then solve under each induced context.
Feature equivalence is scoped to the observed rows, never promoted to a law."
  (let ((frame (snapshot-frame frame)))
    (%make-dependency-search :frame frame :language (snapshot-language selector-language)
     :feature-bound feature-bound :selector-bound selector-bound
     :observation (start-observation-search
                   (make-observation-scope
                    (unconstrained-frame frame (language-domain feature-language))
                    feature-language)))))

(defun resume-dependency-search (job work-limit)
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (let ((ledger (dependency-search-ledger job)) (obs (dependency-search-observation job)))
    (loop while (< (ledger-total ledger) work-limit) do
      (case (dependency-search-phase job)
        (:features
         (if (observation-bound-complete-p obs (dependency-search-feature-bound job))
             (setf (dependency-search-phase job) :collect
                   (dependency-search-records job) (reverse (observation-job-buckets obs)))
             (let ((before (ledger-total (observation-job-ledger obs))))
               (observation-step obs 1)
               (charge ledger :feature-search (- (ledger-total (observation-job-ledger obs)) before)))))
        (:collect
         (charge ledger :dependency-proposal)
         (if (dependency-search-records job)
             (let* ((bucket (pop (dependency-search-records job)))
                    ;; Enumeration visits shorter expressions first; bucket members are newest first.
                    (record (car (last (observation-bucket-members bucket)))))
               (push (observed-expression-expression record) (dependency-search-features job)))
             (let ((features (nreverse (dependency-search-features job))))
               (setf (dependency-search-debt job)
                     (1+ (reduce #'+ features :key #'syntax-work :initial-value 0))
                     (dependency-search-features job) features
                     (dependency-search-phase job) :prepare))))
        (:prepare
         (charge ledger :dependency-proposal) (decf (dependency-search-debt job))
         (when (zerop (dependency-search-debt job))
           (setf (dependency-search-synthesis job)
                 (start-synthesis (dependency-search-frame job) (dependency-search-language job)
                                  (dependency-search-selector-bound job)
                  :decompositions (dependency-proposals (dependency-search-frame job) (dependency-search-language job)
                                                        (dependency-search-selector-bound job)
                                                        :features (dependency-search-features job)))
                 (dependency-search-phase job) :solve)))
        (:solve
         (let* ((search (dependency-search-synthesis job)) (before (ledger-total (synthesis-job-ledger search))))
           (resume-synthesis search (+ before (- work-limit (ledger-total ledger))))
           (charge ledger :dependency-synthesis (- (ledger-total (synthesis-job-ledger search)) before))
           (when (synthesis-finished-p search) (setf (dependency-search-phase job) :done))))
        (:done (return))))
    (make-message :claim (if (eq :done (dependency-search-phase job)) :bounded-exhaustion :cutoff)
                  :evidence (list :phase (dependency-search-phase job) :work (ledger-total ledger)
                                  :features (dependency-search-features job)
                                  :synthesis (dependency-search-synthesis job)))))
