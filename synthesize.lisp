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
              (values (extract-allowed-values (row-requirement row))))
         (if (and (listp values) values)
             (multiple-value-bind (witness witness-bits)
                 (select-closest-witness (observation-outcome-value outcome)
                                         values
                                         type
                                         (eq :value (observation-outcome-status outcome)))
               (push (cons (row-key row) witness) (heuristic-search-residual job))
               (incf (heuristic-search-residual-bits job)
                     (+ (positive-bit-size (1+ (heuristic-search-index job)))
                        witness-bits))
               (setf (heuristic-search-phase job) :next))
             ;; No available correction witness; do not call an unresolved predicate false.
             (setf (heuristic-search-phase job) :observe))))
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
  name decoder child-id child-type bindings language bound children (fiber-p nil))

(defstruct synthesis-node
  id parent proposal frame language bound search (phase :prepare) prepared (debt 0))

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node pending (next-id 1))

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

(defun start-synthesis (frame language description-limit &key decompositions (run-weight 0) (quantum 32))
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber proposals."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (let* ((root (make-synthesis-node :id 0 :frame (snapshot-frame frame)
                                   :language (snapshot-language language) :bound description-limit))
         (job (%make-synthesis-job :root root :nodes (list root) :run-weight run-weight :quantum quantum)))
    (dolist (proposal decompositions) (add-synthesis-node job root (copy-decomposition-tree proposal)))
    job))

(defun copy-decomposition-tree (proposal)
  (let ((copy (copy-decomposition proposal)))
    (setf (decomposition-decoder copy) (copy-tree (decomposition-decoder copy))
          (decomposition-bindings copy) (copy-tree (decomposition-bindings copy))
          (decomposition-child-type copy) (copy-tree (decomposition-child-type copy))
          (decomposition-language copy) (snapshot-language (decomposition-language copy))
          (decomposition-children copy) (mapcar #'copy-decomposition-tree (decomposition-children copy)))
    copy))

(defun prepare-synthesis-node (node)
  "Stage atomic host preparation privately; publish only after its tariff is paid.
This is accounting preemption, not OS-level interruption of Lisp traversals."
  (let* ((ledger (make-ledger)) (proposal (synthesis-node-proposal node))
         (parent (synthesis-node-parent node))
         (frame (if parent
                    (pullback-frame (synthesis-node-frame parent) (decomposition-decoder proposal)
                                    (decomposition-child-id proposal) (decomposition-child-type proposal)
                                    (decomposition-bindings proposal) ledger)
                    (synthesis-node-frame node)))
         (language (if proposal (decomposition-language proposal) (synthesis-node-language node))))
    (when (and proposal (decomposition-fiber-p proposal))
      (let ((refined (nth-value 2 (infer-fibers frame ledger))))
        (when refined (setf frame refined))))
    (let ((conflict (frame-conflict-p frame :ledger ledger)))
      (charge ledger :problem-snapshot
              (+ 1 (loop for row in (frame-rows frame) sum
                     (+ (syntax-work (row-requirement row))
                        (loop for value in (row-known row) for spec in (language-inputs language)
                              sum (value-work value (cdr spec)))))))
      (setf (synthesis-node-prepared node) (list frame language conflict)
            (synthesis-node-debt node) (ledger-total ledger)
            (synthesis-node-phase node) :preparation))))

(defun finish-synthesis-preparation (job node)
  (destructuring-bind (frame language conflict) (synthesis-node-prepared node)
    (setf (synthesis-node-frame node) frame (synthesis-node-language node) language
          (synthesis-node-bound node) (or (synthesis-node-bound node)
                                          (decomposition-bound (synthesis-node-proposal node)))
          (synthesis-node-prepared node) nil)
    (if conflict
        (progn (setf (synthesis-node-phase node) :done)
               (synthesis-message job node :conflict (list :conflict conflict :scope :child-frame)))
        (progn
          (setf (synthesis-node-search node) (start-search frame language)
                (synthesis-node-phase node) :search)
          (dolist (proposal (when (synthesis-node-proposal node)
                              (decomposition-children (synthesis-node-proposal node))))
            (add-synthesis-node job node proposal))))))

(defun reconstruct-synthesis-candidate (node expression ledger)
  (loop while (synthesis-node-parent node) do
    (let ((proposal (synthesis-node-proposal node)))
      (setf expression (compose-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                                      expression (decomposition-bindings proposal) ledger)
            node (synthesis-node-parent node)))
    finally (return expression)))

(defun synthesis-finished-p (job)
  (and (every (lambda (n) (eq :done (synthesis-node-phase n))) (synthesis-job-nodes job))
       (null (synthesis-job-pending job)) (null (synthesis-job-verification job))))

(defun select-synthesis-lane (job)
  (let* ((root (synthesis-job-root job))
         (others (remove-if (lambda (node)
                              (or (eq node root) (eq :done (synthesis-node-phase node))
                                  (and (synthesis-node-parent node)
                                       (null (synthesis-node-frame (synthesis-node-parent node))))))
                            (synthesis-job-nodes job)))
         (root-active (not (eq :done (synthesis-node-phase root))))
         (reserve (= 3 (mod (synthesis-job-turn job) 4))))
    (incf (synthesis-job-turn job))
    (setf (synthesis-job-active job)
          (cond ((and root-active reserve) root)
                ((or (synthesis-job-pending job) (synthesis-job-verification job)) :verify)
                (others (nth (mod (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job)))
                                  (length others)) others))
                (root-active root))
          (synthesis-job-remaining job) (synthesis-job-quantum job))))

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
      (:prepare (charge ledger :preparation) (prepare-synthesis-node node))
      (:preparation
       (charge ledger :preparation) (decf (synthesis-node-debt node))
       (when (<= (synthesis-node-debt node) 0) (finish-synthesis-preparation job node)))
      (:search
       (let* ((search (synthesis-node-search node)) (before (ledger-total (search-job-ledger search)))
              (results (search-job-results search)))
         (search-step search 1)
         (charge ledger :child-search (- (ledger-total (search-job-ledger search)) before))
         (unless (eq results (search-job-results search))
           (let* ((candidate (first (search-job-results search))) (preparation (make-ledger))
                  (model (reconstruct-synthesis-candidate node (candidate-expression candidate) preparation)))
             (synthesis-message job node :child-candidate (list :candidate candidate :scope :child-frame))
             (setf (synthesis-job-pending job)
                   (append (synthesis-job-pending job)
                           (list (list node model (max 1 (ledger-total preparation))))))))
         (when (search-bound-complete-p search (synthesis-node-bound node))
           (setf (synthesis-node-phase node) :done)
           (synthesis-message job node :bounded-exhaustion
                              (list :scope :child-grammar :results (length (search-job-results search))))))))))

(defun resume-synthesis (job work-limit &key stop-on-first)
  "Absolute cumulative tariff budget. Every fourth quantum reserves the root search.
All composed candidates are checked and scored at the root; no local gain is required."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (synthesis-job-ledger job)) work-limit)
                   (not (synthesis-finished-p job))
                   (not (and stop-on-first (synthesis-job-best job)))) do
    (cond
      ((or (null (synthesis-job-active job)) (zerop (synthesis-job-remaining job)))
       (charge (synthesis-job-ledger job) :scheduling) (select-synthesis-lane job))
      (t
       (let ((active (synthesis-job-active job)))
         (if (eq active :verify)
             (synthesis-verification-step job)
             (if (eq :done (synthesis-node-phase active))
                 (setf (synthesis-job-active job) nil)
                 (synthesis-node-step job active))))
       (decf (synthesis-job-remaining job)))))
  (synthesis-message job (synthesis-job-root job)
                     (cond ((synthesis-finished-p job) :bounded-exhaustion)
                           ((and stop-on-first (synthesis-job-best job)) :candidate) (t :cutoff))
                     (list :scope :configured-proposals :best (synthesis-job-best job))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p))
  "Make dependency hypotheses explicit. FEATURES are synthesized DSL expressions;
the default seed vocabulary is each available coordinate and the empty context.
Every hypothesis competes with direct synthesis on the full original frame."
  (let* ((target (schema-target (frame-schema frame)))
         (child-id (1+ (reduce #'max (schema-inputs (frame-schema frame)) :key #'car :initial-value 0))))
    (loop for feature in (cons nil (if features-p features
                                     (mapcar (lambda (spec) (var (car spec) (cdr spec)))
                                             (schema-inputs (frame-schema frame)))))
          for inputs = (when feature (list (cons 0 (ast-type feature))))
          collect (make-decomposition
                   :name (list :dependency feature) :decoder (var child-id target)
                   :child-id child-id :child-type target :bindings (when feature (list (cons 0 feature)))
                   :language (make-language (language-domain language) inputs :operators (language-operators language)
                                            :literals (language-literals language) :constants (language-constants language))
                   :bound child-bound))))

(defun start-selector-search (frame language description-limit &key (fibers t) dependencies)
  "Price direct selector synthesis alongside optional fiber and dependency proposals."
  (let* ((target (schema-target (frame-schema frame)))
         (inputs (schema-inputs (frame-schema frame)))
         (id (1+ (reduce #'max inputs :key #'car :initial-value 0)))
         (proposals (when fibers
                      (list (make-decomposition :name :fibers :decoder (var id target) :child-id id
                              :child-type target :bindings (mapcar (lambda (s) (cons (car s) (var (car s) (cdr s)))) inputs)
                              :language language :bound description-limit :fiber-p t)))))
    (when dependencies (setf proposals (append proposals (dependency-proposals frame language description-limit))))
    (start-synthesis frame language description-limit :decompositions proposals)))

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
