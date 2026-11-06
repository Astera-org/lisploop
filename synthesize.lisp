(in-package #:lisploop)

;;; Shared orchestration. The DSL remains unchanged; recursion is in the search.

(defstruct (heuristic-search (:constructor %make-heuristic-search))
  observation bound (ledger (make-ledger)) (phase :prepare) (debt 0) record rows outcomes
  evaluation (index 0) residual (residual-bits 0) best (run-weight 0))

(defun start-heuristic-search (frame language &key description-limit (run-weight 0))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (%make-heuristic-search
   :observation (start-observation-search (make-observation-scope frame language) :retain-outcomes t)
   :debt (+ 1 (length (frame-pairs frame)) (length (frame-anchors frame))
            (loop for row in (frame-rows frame) sum (syntax-work (row-requirement row))))
   :bound (or description-limit (+ (header-size (schema-inputs (frame-schema frame))
                                                (schema-target (frame-schema frame))) 18))
   :run-weight run-weight))

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
                 (heuristic-search-index job) 0 (heuristic-search-residual job) nil
                 (heuristic-search-residual-bits job) 0 (heuristic-search-phase job) :row))))
      (:row
       (charge ledger :heuristic-checking)
       (if (null (heuristic-search-rows job))
           (setf (heuristic-search-phase job) :score
                 (heuristic-search-debt job)
                 (+ (syntax-work (observed-expression-expression (heuristic-search-record job)))
                    (length (frame-pairs frame))
                    (length (frame-anchors frame))))
           (let ((outcome (first (heuristic-search-outcomes job))))
             (if (eq :value (observation-outcome-status outcome))
                 (setf (heuristic-search-evaluation job)
                       (start-evaluation (row-requirement (first (heuristic-search-rows job)))
                                         (list (cons 0 type)) (list (observation-outcome-value outcome)))
                       (heuristic-search-phase job) :check)
                 (setf (heuristic-search-phase job) :residual
                       (heuristic-search-debt job) (syntax-work (row-requirement (first (heuristic-search-rows job)))))))))
      (:check
       (let ((run (advance-accounted-evaluation (heuristic-search-evaluation job) 1 ledger
                                                :heuristic-checking :heuristic-checking)))
         (unless (eq :unknown (evaluation-status run))
           (setf (heuristic-search-debt job) (syntax-work (row-requirement (first (heuristic-search-rows job)))))
           (setf (heuristic-search-phase job)
                 (if (and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))
                     :next :residual)))))
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
                  (old (heuristic-search-best job)))
             (when (or (null old) (< score (heuristic-score old))
                       (and (= score (heuristic-score old)) (< bits (heuristic-program-bits old))))
               (setf (heuristic-search-best job)
                     (make-heuristic-model :program program :residual residual :exact-p (null residual)
                                           :total-p (eq :complete (observed-expression-status record))
                                           :program-bits bits :residual-bits residual-bits
                                           :run-work (observed-expression-run-work record) :score score)))
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

(defstruct decomposition
  name decoder child-id child-type bindings language bound children (fiber-p nil) (solver nil) (fallback-p nil))

(defstruct synthesis-node
  id parent proposal frame language bound search (phase :prepare) prepared (debt 0)
  priority heuristic followers reused-from
  ;; Lazy expansion: nil (not yet), :paying (branches staged, debt owed), or :done.
  expansion expansions (expansion-debt 0))

;; Privately staged result of `prepare-synthesis-node`, published once its debt is paid.
(defstruct node-preparation
  frame language conflict reused-nogood-p fallback-p priority heuristic)

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node pending (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
  library expand (max-depth 1)
  (nogoods nil) (scope-cache (make-hash-table :test #'equal)) (reused-subproblems 0)
  (trace nil))

(defun synthesis-message (job node claim evidence)
  "Messages carry child and parent identities, scope, and evidence for later synthesis.
Only verified candidates and checked conflicts assert semantic facts; cutoff/coverage
messages describe computation. Parents may consume these without trusting a heuristic."
  (let ((message (make-message :call-id (synthesis-node-id node) :claim claim
                               :evidence (append (list :parent-id (when (synthesis-node-parent node)
                                                                   (synthesis-node-id (synthesis-node-parent node)))
                                                      :proposal (when (synthesis-node-proposal node)
                                                                  (decomposition-name (synthesis-node-proposal node)))
                                                      :description-limit (synthesis-node-bound node)
                                                      :work (ledger-total (synthesis-job-ledger job))) evidence))))
    (push message (synthesis-job-messages job)) message))

(defun add-synthesis-node (job parent proposal)
  (let ((node (make-synthesis-node :id (prog1 (synthesis-job-next-id job)
                                       (incf (synthesis-job-next-id job)))
                                   :parent parent :proposal proposal)))
    (setf (synthesis-job-nodes job) (append (synthesis-job-nodes job) (list node))) node))

(defun start-synthesis (frame language description-limit
                        &key decompositions (run-weight 0) (quantum 32)
                             (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
                             library expand (max-depth 1))
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
                                   :language (snapshot-language language) :bound description-limit))
         (job (%make-synthesis-job :root root :nodes (list root) :run-weight run-weight :quantum quantum
                                   :policy policy :heuristic-bound heuristic-bound
                                   :heuristic-budget heuristic-budget
                                   :priority-predictor priority-predictor
                                   :expand expand :max-depth max-depth)))
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
       (or (null (synthesis-job-max-depth job)) (< (node-depth node) (synthesis-job-max-depth job)))))

(defun node-expandable-p (job node)
  "An expansion of NODE is still owed: it is prepared, conflict free, and not yet expanded."
  (and (not (eq :done (synthesis-node-expansion node)))
       (member (synthesis-node-phase node) '(:search :done))
       (node-may-expand-p job node)))

(defun copy-decomposition-tree (proposal)
  (let ((copy (copy-decomposition proposal)))
    (setf (decomposition-decoder copy) (copy-tree (decomposition-decoder copy))
          (decomposition-bindings copy) (copy-tree (decomposition-bindings copy))
          (decomposition-child-type copy) (copy-tree (decomposition-child-type copy))
          (decomposition-language copy) (snapshot-language (decomposition-language copy))
          (decomposition-children copy) (mapcar #'copy-decomposition-tree (decomposition-children copy)))
    copy))

(defun pure-projection-decomposition-p (proposal)
  "True when PROPOSAL is a pure dependency projection `decoder = (var child-id child-type)`."
  (and proposal
       (var-p (decomposition-decoder proposal))
       (= (ast-id (decomposition-decoder proposal))
          (decomposition-child-id proposal))))

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
        (destructuring-bind (p-id . keys) entry
          (when (= p-id parent-id)
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

(defun reconstruct-synthesis-candidate (node expression ledger)
  (loop while (synthesis-node-parent node) do
    (let ((proposal (synthesis-node-proposal node)))
      (setf expression (compose-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                                      expression (decomposition-bindings proposal) ledger)
            node (synthesis-node-parent node)))
    finally (return expression)))

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
    (let ((frame (if parent
                     (pullback-frame (synthesis-node-frame parent) (decomposition-decoder proposal)
                                     (decomposition-child-id proposal) (decomposition-child-type proposal)
                                     (decomposition-bindings proposal) ledger)
                     (synthesis-node-frame node)))
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

(defun exact-heuristic-program (node)
  "The node's own Stage A program when it already satisfies every row, else nil."
  (let ((h-model (synthesis-node-heuristic node)))
    (when (and h-model (heuristic-exact-p h-model)) (heuristic-program h-model))))

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
    (when (and (node-preparation-fallback-p prepared) (synthesis-node-parent node) (synthesis-node-proposal node))
      (let ((fb (copy-decomposition-tree (synthesis-node-proposal node))))
        (setf (decomposition-name fb) (list :fallback (decomposition-name fb))
              (decomposition-solver fb) nil
              (decomposition-fallback-p fb) t)
        (add-synthesis-node job (synthesis-node-parent node) fb)))
    (if conflict
        (progn
          (when (and (not reused-nogood-p)
                     (eq :incompatible-rows (frame-conflict-kind conflict))
                     (synthesis-node-parent node)
                     (pure-projection-decomposition-p (synthesis-node-proposal node))
                     (>= (length (frame-conflict-keys conflict)) 2))
            (pushnew (cons (synthesis-node-id (synthesis-node-parent node))
                           (frame-conflict-keys conflict))
                     (synthesis-job-nogoods job) :test #'equal))
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
          (when (exact-heuristic-program node)
            (setf (synthesis-node-expansion node) :done))
          ;; Fast-path an exact Stage A hit directly to root verification.
          (when (exact-heuristic-program node)
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
            (setf (synthesis-job-verification job) nil)))
        (let ((pending (first (synthesis-job-pending job))))
          (when pending
            (charge ledger :composition)
            (decf (third pending))
            (when (<= (third pending) 0)
              (pop (synthesis-job-pending job))
              (setf (synthesis-job-verification-node job) (first pending)
                    (synthesis-job-verification job)
                    (start-search (synthesis-node-frame root) (synthesis-node-language root)
                                  :run-weight (synthesis-job-run-weight job) :diagnostics t
                                  :expressions (list (second pending))))))))))

(defun synthesis-node-step (job node)
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
                            (exact-heuristic-program node)))
           (let ((candidate (first (search-job-results search))))
             (enqueue-node-candidate job node (candidate-expression candidate) candidate)
             (dolist (follower (synthesis-node-followers node))
               (when (<= (candidate-size candidate) (synthesis-node-bound follower))
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

;;; Stage A -> Stage B Residual Pullback Decompositions & Heuristic Synthesis

(defun next-child-id (inputs)
  (1+ (reduce #'max inputs :key #'car :initial-value 0)))

(defun identity-bindings (inputs)
  (mapcar (lambda (s) (cons (car s) (var (car s) (cdr s)))) inputs))

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

(defun heuristic-hit-mask (frame heuristic-model)
  "Return the per-row Boolean hit mask (T on satisfied rows, NIL on unary residual rows)."
  (let ((residuals (heuristic-residual heuristic-model)))
    (loop for row in (frame-rows frame)
          collect (null (assoc (row-key row) residuals :test #'equal)))))

(defun default-guard-language (frame language)
  "Construct a Boolean guard language over FRAME's inputs for exception-patching."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (domain (language-domain language))
         (eq-ops (cons (op := domain) (mapcar (lambda (spec) (op := (cdr spec))) inputs)))
         (domain-ops (remove-if (lambda (o)
                                  (and (consp (operator-type o))
                                       (eq :bool (car (last (operator-type o))))))
                                (language-operators language))))
    (make-language domain inputs
                   :operators (remove-duplicates (append eq-ops (list (op :if :bool)) domain-ops) :test #'equal)
                   :literals (if (listp (language-literals language))
                                 (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                                 (language-literals language))
                   :constants (language-constants language))))

(defun find-sound-exception-guard (frame hit-mask guard-language guard-bound work-limit ledger)
  "Synthesize a Boolean guard G(X) separating hit and miss rows.
Returns (VALUES guard invert-p): when INVERT-P is NIL, G(X) is T only on hits; when
INVERT-P is T, G(X) is NIL only on hits. Guards are grouped observationally; the most
covering sound one wins (an exact separator covers every hit), then the shortest."
  (let* ((obs (start-observation-search (make-observation-scope (support-frame frame hit-mask ledger)
                                                                guard-language)))
         (obs-before (ledger-total (observation-job-ledger obs)))
         (inputs (schema-inputs (frame-schema frame)))
         (best-expr nil) (best-inv nil) (best-hits 0) (best-bits most-positive-fixnum))
    (resume-observation-search obs guard-bound work-limit)
    (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
    (dolist (bucket (observation-job-buckets obs) (values best-expr best-inv))
      (when (eq :bool (observation-bucket-type bucket))
        (let ((vals (observation-bucket-values bucket))
              (sound-hit-p t) (sound-miss-p t) (hits 0) (inv-hits 0))
          (loop for v in vals for h in hit-mask do
            (if h (if v (incf hits) (incf inv-hits))
                (if v (setf sound-hit-p nil) (setf sound-miss-p nil))))
          (when (or (and sound-hit-p (plusp hits)) (and sound-miss-p (plusp inv-hits)))
            (let* ((use-inv-p (and sound-miss-p (or (not sound-hit-p) (> inv-hits hits))))
                   (eff-hits (if use-inv-p inv-hits hits))
                   (expr (observed-expression-expression (car (last (observation-bucket-members bucket)))))
                   (bits (description-size expr inputs)))
              (when (or (> eff-hits best-hits) (and (= eff-hits best-hits) (< bits best-bits)))
                (setf best-expr expr best-inv use-inv-p best-hits eff-hits best-bits bits)))))))))

(defun heuristic-decompositions (frame language &key heuristic-model child-language guard-language
                                                     description-limit child-bound guard-bound
                                                     (work-limit 50000) (run-weight 0)
                                                     (additive-p t) (conditional-p t) solver ledger)
  "Bridge Stage A heuristic condensation to Stage B recursive synthesis by turning
a non-exact `heuristic-model` into additive displacement and/or conditional
exception-patching `decomposition` proposals.
Returns (VALUES proposals heuristic-model)."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (bound (or description-limit (+ (header-size inputs target) 18)))
         (c-bound (or child-bound bound))
         (g-bound (or guard-bound (+ (header-size inputs :bool) 20)))
         (c-lang (or child-language language))
         (condense-budget (if heuristic-model 0 (max 1 (if conditional-p (floor work-limit 2) work-limit))))
         (h-model (or heuristic-model
                      (condense-heuristic frame language
                                          :description-limit bound
                                          :work-limit condense-budget
                                          :run-weight run-weight
                                          :ledger ledger))))
    (when (or (null h-model) (heuristic-exact-p h-model))
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
                 (some #'null hit-mask))
        (push (make-decomposition
               :name (list :heuristic-additive program)
               :decoder (make-additive-residual-decoder program child-var target)
               :child-id child-id
               :child-type target
               :bindings bindings
               :language c-lang
               :bound c-bound
               :solver solver)
              proposals))
      ;; Path B2: Conditional exception-patching decoder d(X, Z) = (if G pi_hat Z) or (if G_miss Z pi_hat)
      (when (and conditional-p (some #'identity hit-mask) (some #'null hit-mask))
            (let ((g-lang (or guard-language (default-guard-language frame language))))
              (multiple-value-bind (guard invert-p)
                  (find-sound-exception-guard frame hit-mask g-lang g-bound
                                              (max 1 (- work-limit condense-budget)) ledger)
                (when guard
                  (push (make-decomposition
                         :name (list :heuristic-conditional guard program)
                         :decoder (if invert-p
                                      (app (op :if target) guard child-var program)
                                      (app (op :if target) guard program child-var))
                         :child-id child-id
                         :child-type target
                         :bindings bindings
                         :language c-lang
                         :bound c-bound)
                        proposals)))))
      (values (nreverse proposals) h-model))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p))
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
                   :bound child-bound))))

(defun selector-decompositions (frame language bound &key fibers dependencies)
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (id (next-child-id inputs)))
    (append (when fibers
              (list (make-decomposition :name :fibers :decoder (var id target) :child-id id
                                        :child-type target :bindings (identity-bindings inputs)
                                        :language language :bound bound :fiber-p t)))
            (when dependencies
              (dependency-proposals frame language bound)))))

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
                                          :ledger ledger))))))

(defun start-heuristic-synthesis (frame language description-limit
                                  &key decompositions child-language guard-language
                                       child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 2000) (max-depth 2)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       library (run-weight 0) (quantum 32)
                                       priority-predictor)
  "Launch a `:policy :heuristic` synthesis job in which every node shallower than MAX-DEPTH,
root included, condenses a Stage A model of its own frame and proposes Stage B residual
branches through `heuristic-expander`. LIBRARY narrows every pulled-back child frame."
  (let ((c-lang (or child-language language))
        (c-bound (or child-bound description-limit)))
    (start-synthesis frame language description-limit
                     :decompositions (append (selector-decompositions frame c-lang c-bound
                                                                      :fibers fibers :dependencies dependencies)
                                             decompositions)
                     :run-weight run-weight
                     :quantum quantum
                     :policy :heuristic
                     :heuristic-budget heuristic-budget
                     :priority-predictor priority-predictor
                     :library library
                     :max-depth max-depth
                     :expand (heuristic-expander :child-language c-lang :guard-language guard-language
                                                 :child-bound c-bound :guard-bound guard-bound
                                                 :work-limit condense-budget
                                                 :additive-p additive-p :conditional-p conditional-p))))

(defstruct (dependency-search (:constructor %make-dependency-search))
  frame language observation feature-bound selector-bound synthesis
  (ledger (make-ledger)) (phase :features) records features (debt 0))

(defun start-dependency-search (frame feature-language selector-language feature-bound selector-bound)
  "Synthesize dependency features, then solve under each induced context.
Feature equivalence is scoped to the observed rows, never promoted to a law."
  (let* ((frame (snapshot-frame frame)) (schema (copy-schema (frame-schema frame))))
    (setf (schema-target schema) (language-domain feature-language))
    (%make-dependency-search :frame frame :language (snapshot-language selector-language)
     :feature-bound feature-bound :selector-bound selector-bound
     :observation (start-observation-search
                   (make-observation-scope
                    (make-frame schema (mapcar (lambda (row) (make-row :key (row-key row) :known (row-known row)
                                                                      :requirement (lit :bool t)))
                                               (frame-rows frame))) feature-language)))))

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
