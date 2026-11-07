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
  frame language conflict reused-nogood-p fallback-p priority heuristic)

(defstruct (nogood-clause (:predicate nogood-clause-p))
  parent-id
  kind
  keys
  known
  bindings
  clause-expr)

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node verification-expression (verification-row-budget 2000)
  pending (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
  library expand (max-depth 1) self-name oracle-table
  (nogoods nil) (scope-cache (make-hash-table :test #'equal)) (reused-subproblems 0)
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
                             (debug-p *synthesis-debug-mode*))
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber/residual proposals.
LIBRARY (solve discoveries or propagator libraries) is applied to every pulled-back child
frame. EXPAND, a function (job node frame language heuristic-model ledger) -> decompositions,
proposes further branches below a prepared node shallower than MAX-DEPTH, root included.
Expansion is a scheduled action, chosen like search by the node's full-path price; with
MAX-DEPTH nil the tree grows for as long as the budget lasts (an anytime search)."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (assert (member policy '(:round-robin :heuristic)))
  (assert (or (null priority-predictor) (functionp priority-predictor)))
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

(defun build-nogood-clause (parent proposal conflict)
  "Construct a homoiconic S-expression nogood clause over PARENT's scope from a child CONFLICT."
  (let* ((parent-id (synthesis-node-id parent))
         (parent-inputs (schema-inputs (frame-schema (synthesis-node-frame parent))))
         (keys (copy-list (frame-conflict-keys conflict)))
         (known (copy-tree (frame-conflict-known conflict)))
         (bindings (copy-tree (and proposal (decomposition-bindings proposal))))
         (clause-expr
           (cond
             ((and proposal (decomposition-lift-p proposal) (code-type-p (decomposition-child-type proposal)))
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
                        :kind (if (and proposal (decomposition-lift-p proposal))
                                  :lift-incompatible-rows
                                  (frame-conflict-kind conflict))
                        :keys keys
                        :known known
                        :bindings bindings
                        :clause-expr clause-expr)))

(defun nogood-entry-parent-and-keys (entry)
  "Extract (VALUES parent-id keys kind) from a `nogood-clause` or legacy `(parent-id . keys)` list."
  (if (nogood-clause-p entry)
      (values (nogood-clause-parent-id entry)
              (nogood-clause-keys entry)
              (nogood-clause-kind entry))
      (values (first entry) (rest entry) :incompatible-rows)))

(defun check-parent-nogoods (job parent proposal ledger)
  "Check whether PROPOSAL's bindings alias any incompatible row set (nogood)
already discovered on PARENT."
  (when (and job parent proposal (pure-projection-decomposition-p proposal))
    (let* ((parent-id (synthesis-node-id parent))
           (parent-frame (synthesis-node-frame parent))
           (inputs (schema-inputs (frame-schema parent-frame)))
           (rows (frame-rows parent-frame))
           (bindings (decomposition-bindings proposal)))
      (dolist (entry (synthesis-job-nogoods job))
        (multiple-value-bind (p-id keys kind) (nogood-entry-parent-and-keys entry)
          (when (and (= p-id parent-id) (eq kind :incompatible-rows))
            (let ((matched-rows (mapcar (lambda (k) (find k rows :key #'row-key :test #'equal)) keys)))
              (when (and (>= (length matched-rows) 2) (every #'identity matched-rows))
                (let ((first-known (evaluate-row-bindings bindings inputs (row-known (first matched-rows))
                                                          :ledger ledger :error-p nil)))
                  (when (and (not (eq first-known :error))
                             (every (lambda (r)
                                      (equal first-known
                                             (evaluate-row-bindings bindings inputs (row-known r)
                                                                    :ledger ledger :error-p nil)))
                                    (rest matched-rows)))
                    (return-from check-parent-nogoods
                      (make-frame-conflict :kind :incompatible-rows
                                           :keys (copy-list keys)
                                           :known first-known
                                           :expression (lit :bool nil))))))))))))
  nil)

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
  (let ((budget (synthesis-job-heuristic-budget job)))
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

(defun node-priority (job node frame language h-model ledger)
  "Lower is better: the Stage A model composed through every ancestor and priced at the
root, plus its residual bits; or a supplied predictor's score."
  (let ((predictor (synthesis-job-priority-predictor job)))
    (cond
      (predictor (funcall predictor node frame language h-model))
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
               (h-model (when priced-p (node-stage-a-model job node effective language ledger))))
          (setf (synthesis-node-prepared node)
                (make-node-preparation
                 :frame effective :language language :conflict conflict :fallback-p fallback-p
                 :heuristic h-model
                 :priority (when (and priced-p (heuristic-routing-p job))
                             (node-priority job node effective language h-model ledger)))
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
          (when (and (not reused-nogood-p)
                     (eq :incompatible-rows (frame-conflict-kind conflict))
                     (synthesis-node-parent node)
                     (or (pure-projection-decomposition-p (synthesis-node-proposal node))
                         (and (synthesis-node-proposal node)
                              (decomposition-lift-p (synthesis-node-proposal node))))
                     (>= (length (frame-conflict-keys conflict)) 2))
            (pushnew (build-nogood-clause (synthesis-node-parent node)
                                          (synthesis-node-proposal node)
                                          conflict)
                     (synthesis-job-nogoods job)
                     :test (lambda (a b)
                             (and (nogood-clause-p a) (nogood-clause-p b)
                                  (eql (nogood-clause-parent-id a) (nogood-clause-parent-id b))
                                  (eq (nogood-clause-kind a) (nogood-clause-kind b))
                                  (equal (nogood-clause-keys a) (nogood-clause-keys b))))))
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
         (hole-ast (when target (reconstruct-synthesis-candidate node (hole 0 target))))
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
               (cand-model
                 (find-if (lambda (m)
                            (and (not (and eff-self
                                           (heuristic-exact-p m)
                                           (null (heuristic-unresolved-keys m))
                                           (not (expression-calls-operator-p (heuristic-program m) eff-self))))
                                 (let ((mask (heuristic-hit-mask frame m)))
                                   (and (some #'identity mask)
                                        (some #'null mask)
                                        (or (not empty-seq-frame-p)
                                            (model-satisfies-empty-sequence-rows-p frame mask))))))
                          candidates)))
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
                                (work-limit 20000) (additive-p t) (conditional-p t))
  "An `:expand` function: each node turns its own Stage A model into Stage B additive and
conditional residual branches, so a residual exposed in one representation is condensed
and patched again in the child's. Supplied languages apply only where their inputs match."
  (lambda (job node frame language h-model ledger)
    (let* ((inputs (schema-inputs (frame-schema frame)))
           (proposal (synthesis-node-proposal node))
           (bound (or (synthesis-node-bound node) (and proposal (decomposition-bound proposal)))))
      (flet ((matching (lang) (and lang (equal (language-inputs lang) inputs) lang)))
        (values (heuristic-decompositions frame language
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
                                          :debug-p (synthesis-job-debug-p job)))))))

(defun start-heuristic-synthesis (frame language description-limit
                                  &key decompositions child-language guard-language
                                       child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 2000) (max-depth 2)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       library (run-weight 0) (quantum 32)
                                       self-name oracle-table (verification-row-budget 2000)
                                       priority-predictor (debug-p *synthesis-debug-mode*))
  "Launch a `:policy :heuristic` synthesis job in which every node shallower than MAX-DEPTH,
root included, condenses a Stage A model of its own frame and proposes Stage B residual
branches through `heuristic-expander`. LIBRARY narrows every pulled-back child frame."
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
                     :debug-p debug-p
                     :expand (heuristic-expander :child-language c-lang :guard-language guard-language
                                                 :child-bound c-bound :guard-bound guard-bound
                                                 :work-limit condense-budget
                                                 :additive-p additive-p :conditional-p conditional-p))))

(defun start-recursive-synthesis (frame language description-limit
                                  &key self-name oracle-table decompositions
                                       child-language guard-language child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 5000) (max-depth 2)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       library (run-weight 0) (quantum 32)
                                       (verification-row-budget 2000)
                                       priority-predictor (debug-p *synthesis-debug-mode*))
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
                               :library library
                               :run-weight run-weight
                               :quantum quantum
                               :self-name fn-name
                               :oracle-table eff-oracle
                               :verification-row-budget verification-row-budget
                               :priority-predictor priority-predictor
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
