(in-package #:lisploop)

;;; Shared orchestration. The DSL remains unchanged; recursion is in the search.

(defstruct (heuristic-search (:constructor %make-heuristic-search))
  observation bound (ledger (make-ledger)) (phase :prepare) (debt 0) record rows outcomes
  evaluation (index 0) residual (residual-bits 0) best (run-weight 0))

(defun modular-or-integer-add (a b type)
  (cond
    ((eq type :int) (+ a b))
    ((and (consp type) (eq :gf (first type))) (mod (+ a b) (second type)))
    (t nil)))

(defun modular-or-integer-sub (a b type)
  (cond
    ((eq type :int) (- a b))
    ((and (consp type) (eq :gf (first type))) (mod (- a b) (second type)))
    (t nil)))

(defun unwrap-linear-var0-term (term target scalar-type &optional expected-slot)
  "Solve for (var 0 ...) or (at (var 0 tuple-type) 'expected-slot) inside a linear
chain of :+ and :- with literal operands over :int or (:gf p).
Returns (VALUES value found-p)."
  (cond
    ((and (null expected-slot) (var-p term) (zerop (ast-id term)) (equal (ast-type term) scalar-type))
     (values target t))
    ((and expected-slot (app-p term) (eq :at (operator-name (first term)))
          (var-p (second term)) (zerop (ast-id (second term)))
          (lit-p (third term)) (eql expected-slot (ast-value (third term))))
     (values target t))
    ((and (app-p term) (member (operator-name (first term)) '(:+ :-))
          (or (eq scalar-type :int) (and (consp scalar-type) (eq :gf (first scalar-type)))))
     (let ((op-name (operator-name (first term)))
           (lhs (second term))
           (rhs (third term)))
       (cond
         ((and (eq op-name :+) (lit-p lhs))
          (unwrap-linear-var0-term rhs (modular-or-integer-sub target (ast-value lhs) scalar-type)
                                   scalar-type expected-slot))
         ((and (eq op-name :+) (lit-p rhs))
          (unwrap-linear-var0-term lhs (modular-or-integer-sub target (ast-value rhs) scalar-type)
                                   scalar-type expected-slot))
         ((and (eq op-name :-) (lit-p rhs))
          (unwrap-linear-var0-term lhs (modular-or-integer-add target (ast-value rhs) scalar-type)
                                   scalar-type expected-slot))
         ((and (eq op-name :-) (lit-p lhs))
          (unwrap-linear-var0-term rhs (modular-or-integer-sub (ast-value lhs) target scalar-type)
                                   scalar-type expected-slot))
         (t (values nil nil)))))
    (t (values nil nil))))

(defun solve-linear-var0-equality (expr scalar-type &optional expected-slot)
  (when (and (app-p expr) (eq := (operator-name (first expr))))
    (let ((lhs (second expr))
          (rhs (third expr)))
      (cond
        ((lit-p rhs)
         (unwrap-linear-var0-term lhs (ast-value rhs) scalar-type expected-slot))
        ((lit-p lhs)
         (unwrap-linear-var0-term rhs (ast-value lhs) scalar-type expected-slot))
        (t (values nil nil))))))

(defun resolve-heuristic-witnesses (requirement type)
  "Extract explicit witnesses for REQUIREMENT on variable 0 of TYPE.
Fast-paths explicit `singleton-requirement` and `set-requirement` via `extract-allowed-values`,
and otherwise folds REQUIREMENT, solves linear additive/subtractive equalities (including
tuple coordinate conjunctions), or sweeps small finite domains."
  (let ((direct (extract-allowed-values requirement)))
    (unless (eq direct :unknown)
      (return-from resolve-heuristic-witnesses direct)))
  (let* ((folded (fold-constants requirement (make-schema :inputs (list (cons 0 type)) :target :bool)
                                 :budget 500))
         (after-fold (extract-allowed-values folded)))
    (unless (eq after-fold :unknown)
      (return-from resolve-heuristic-witnesses after-fold))
    (when (and (lit-p folded) (eq :bool (ast-type folded)) (eq t (ast-value folded)))
      (return-from resolve-heuristic-witnesses :unconstrained))
    ;; 1. Scalar linear additive/subtractive equation on var 0.
    (when (or (eq type :int) (and (consp type) (eq :gf (first type))))
      (multiple-value-bind (sol found-p) (solve-linear-var0-equality folded type nil)
        (when (and found-p
                   (let ((run (check-requirement folded sol :type type :budget 200)))
                     (and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))))
          (return-from resolve-heuristic-witnesses (list sol)))))
    ;; 2. Tuple conjunction of linear coordinate equations on (at (var 0 type) 'i).
    (when (and (consp type) (eq :tuple (first type)))
      (let* ((conjuncts (extract-conjuncts folded))
             (parts (rest type))
             (coords (make-array (length parts) :initial-element :unbound)))
        (loop for i from 0 below (length parts)
              for part-type in parts
              do (dolist (c conjuncts)
                   (multiple-value-bind (sol found-p) (solve-linear-var0-equality c part-type i)
                     (when found-p
                       (setf (aref coords i) sol)))))
        (when (loop for c across coords never (eq c :unbound))
          (let* ((tuple-sol (coerce coords 'list))
                 (run (check-requirement folded tuple-sol :type type :budget 200)))
            (when (and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))
              (return-from resolve-heuristic-witnesses (list tuple-sol)))))))
    ;; 3. Small finite domain sweep.
    (when (and (finite-type-p type) (<= (finite-type-cardinality type) 64))
      (let ((card (finite-type-cardinality type))
            (matches nil))
        (dotimes (idx card)
          (let* ((candidate (unrank-finite-value type idx))
                 (run (check-requirement folded candidate :type type :budget 200)))
            (when (and (eq :value (evaluation-status run)) (eq t (evaluation-value run)))
              (push candidate matches))))
        (return-from resolve-heuristic-witnesses (nreverse matches))))
    :unknown))

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
              (values (resolve-heuristic-witnesses (row-requirement row) type)))
         (cond
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
           ((eq values :unknown)
            ;; Unresolved symbolic predicate on an infinite/large domain: charge conservative replacement fallback.
            (push (cons (row-key row) :unknown) (heuristic-search-residual job))
            (incf (heuristic-search-residual-bits job)
                  (+ (positive-bit-size (1+ (heuristic-search-index job)))
                     (1+ (type-bit-size type))))
            (setf (heuristic-search-phase job) :next))
           (t
            ;; Genuinely empty witness set ('nil or empty finite fiber).
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
  priority heuristic followers reused-from)

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node pending (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
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
                             (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor)
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber/residual proposals."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (assert (member policy '(:round-robin :heuristic)))
  (let* ((root (make-synthesis-node :id 0 :frame (snapshot-frame frame)
                                   :language (snapshot-language language) :bound description-limit))
         (job (%make-synthesis-job :root root :nodes (list root) :run-weight run-weight :quantum quantum
                                   :policy policy :heuristic-bound heuristic-bound
                                   :heuristic-budget heuristic-budget
                                   :priority-predictor priority-predictor)))
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

(defun pure-projection-decomposition-p (proposal)
  "True when PROPOSAL is a pure dependency projection `decoder = (var child-id child-type)`."
  (and proposal
       (var-p (decomposition-decoder proposal))
       (= (ast-id (decomposition-decoder proposal))
          (decomposition-child-id proposal))))

(defun check-parent-nogoods (job parent proposal ledger)
  "Check whether PROPOSAL's bindings alias any incompatible row pair (nogood)
already discovered on PARENT."
  (when (and job parent proposal (pure-projection-decomposition-p proposal))
    (let* ((parent-id (synthesis-node-id parent))
           (parent-frame (synthesis-node-frame parent))
           (inputs (schema-inputs (frame-schema parent-frame)))
           (rows (frame-rows parent-frame))
           (bindings (decomposition-bindings proposal)))
      (dolist (entry (synthesis-job-nogoods job))
        (destructuring-bind (p-id k1 k2) entry
          (when (= p-id parent-id)
            (let ((row1 (find k1 rows :key #'row-key :test #'equal))
                  (row2 (find k2 rows :key #'row-key :test #'equal)))
              (when (and row1 row2)
                (labels ((eval-bindings (known)
                           (mapcar (lambda (binding)
                                     (let ((run (evaluate (cdr binding) inputs known :ledger ledger)))
                                       (unless (eq (evaluation-status run) :value)
                                         (return-from eval-bindings :error))
                                       (evaluation-value run)))
                                   bindings)))
                  (let ((known1 (eval-bindings (row-known row1)))
                        (known2 (eval-bindings (row-known row2))))
                    (when (and (not (eq known1 :error))
                               (not (eq known2 :error))
                               (equal known1 known2))
                      (return-from check-parent-nogoods
                        (make-frame-conflict :kind :incompatible-rows
                                             :keys (list k1 k2)
                                             :known known1
                                             :expression (lit :bool nil)))))))))))))
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

(defun score-node-heuristic-priority (job node frame language ledger)
  "Compute a Stage A heuristic lookahead model and priority score for NODE."
  (let* ((proposal (synthesis-node-proposal node))
         (parent (synthesis-node-parent node))
         (bound (or (synthesis-job-heuristic-bound job)
                    (synthesis-node-bound node)
                    (and proposal (decomposition-bound proposal))
                    (+ (header-size (schema-inputs (frame-schema frame))
                                    (schema-target (frame-schema frame))) 18)))
         (budget (synthesis-job-heuristic-budget job))
         (h-model (when (and (eq (synthesis-job-policy job) :heuristic)
                             (integerp budget) (plusp budget))
                    (condense-heuristic frame language
                                        :description-limit bound
                                        :work-limit budget
                                        :run-weight (synthesis-job-run-weight job)
                                        :ledger ledger)))
         (decoder-bits (if (and parent proposal)
                           (body-size (decomposition-decoder proposal)
                                      (acons (decomposition-child-id proposal)
                                             (decomposition-child-type proposal)
                                             (schema-inputs (frame-schema (synthesis-node-frame parent)))))
                           0))
         (predictor (synthesis-job-priority-predictor job))
         (priority
           (cond
             ((functionp predictor)
              (funcall predictor node frame language h-model))
             ((and predictor (ast-kind predictor))
              (let* ((feat-inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
                     (feat-values (list decoder-bits
                                        (length (schema-inputs (frame-schema frame)))
                                        (length (frame-rows frame))
                                        (if h-model (heuristic-residual-bits h-model) 1000)))
                     (run (evaluate predictor feat-inputs feat-values :ledger ledger :budget 500)))
                (if (and (eq :value (evaluation-status run)) (realp (evaluation-value run)))
                    (evaluation-value run)
                    most-positive-fixnum)))
             (h-model
              (+ decoder-bits (heuristic-score h-model)))
             (t most-positive-fixnum))))
    (values priority h-model)))

(defun prepare-synthesis-node (node &optional job)
  "Stage atomic host preparation privately; publish only after its tariff is paid.
This is accounting preemption, not OS-level interruption of Lisp traversals."
  (let* ((ledger (make-ledger))
         (proposal (synthesis-node-proposal node))
         (parent (synthesis-node-parent node))
         (language (if proposal (decomposition-language proposal) (synthesis-node-language node)))
         (nogood-conflict (check-parent-nogoods job parent proposal ledger)))
    (when nogood-conflict
      (charge ledger :problem-snapshot 1)
      (setf (synthesis-node-prepared node) (list nil language nogood-conflict t nil nil nil)
            (synthesis-node-debt node) (max 1 (ledger-total ledger))
            (synthesis-node-phase node) :preparation)
      (return-from prepare-synthesis-node))
    (let* ((fallback-needed-p nil)
           (frame (cond
                   ((and parent proposal (decomposition-solver proposal))
                    (let ((prop (propagate-arithmetic-child
                                 (synthesis-node-frame parent)
                                 (decomposition-decoder proposal)
                                 (decomposition-child-id proposal)
                                 (decomposition-bindings proposal)
                                 (decomposition-solver proposal)
                                 ledger)))
                      (setf fallback-needed-p
                            (and (not (null (propagation-fallback prop)))
                                 (not (decomposition-fallback-p proposal))))
                      (propagation-frame prop)))
                   (parent
                    (pullback-frame (synthesis-node-frame parent) (decomposition-decoder proposal)
                                    (decomposition-child-id proposal) (decomposition-child-type proposal)
                                    (decomposition-bindings proposal) ledger))
                   (t (synthesis-node-frame node)))))
      (when (and proposal (decomposition-fiber-p proposal))
        (let ((refined (nth-value 2 (infer-fibers frame ledger))))
          (when refined (setf frame refined))))
      (multiple-value-bind (conflict folded-frame) (frame-conflict-p frame :ledger ledger)
        (charge ledger :problem-snapshot
                (+ 1 (loop for row in (frame-rows frame) sum
                       (+ (syntax-work (row-requirement row))
                          (loop for value in (row-known row) for spec in (language-inputs language)
                                sum (value-work value (cdr spec)))))))
        (let ((effective-frame (if (and (null conflict) folded-frame) folded-frame frame)))
          (multiple-value-bind (priority h-model)
              (if (and (null conflict) parent job
                       (or (eq (synthesis-job-policy job) :heuristic)
                           (synthesis-job-priority-predictor job)))
                  (score-node-heuristic-priority job node effective-frame language ledger)
                  (values nil nil))
            (setf (synthesis-node-prepared node)
                  (list effective-frame language conflict nil fallback-needed-p priority h-model)
                  (synthesis-node-debt node) (ledger-total ledger)
                  (synthesis-node-phase node) :preparation)))))))

(defun enqueue-node-candidate (job node expression candidate-obj)
  (let* ((preparation (make-ledger))
         (model (reconstruct-synthesis-candidate node expression preparation)))
    (when candidate-obj
      (synthesis-message job node :child-candidate (list :candidate candidate-obj :scope :child-frame)))
    (setf (synthesis-job-pending job)
          (append (synthesis-job-pending job)
                  (list (list node model (max 1 (ledger-total preparation))))))))

(defun finish-synthesis-preparation (job node)
  (destructuring-bind (frame language conflict reused-nogood-p fallback-needed-p priority h-model)
      (synthesis-node-prepared node)
    (setf (synthesis-node-frame node) frame
          (synthesis-node-language node) language
          (synthesis-node-bound node) (or (synthesis-node-bound node)
                                          (when (synthesis-node-proposal node)
                                            (decomposition-bound (synthesis-node-proposal node))))
          (synthesis-node-priority node) priority
          (synthesis-node-heuristic node) h-model
          (synthesis-node-prepared node) nil)
    (when (and fallback-needed-p (synthesis-node-parent node) (synthesis-node-proposal node))
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
            (let ((nogood (list (synthesis-node-id (synthesis-node-parent node))
                                (first (frame-conflict-keys conflict))
                                (car (last (frame-conflict-keys conflict))))))
              (pushnew nogood (synthesis-job-nogoods job) :test #'equal)
              ;; Short-circuit any sibling currently mid-preparation that aliases this nogood.
              (dolist (sib (synthesis-job-nodes job))
                (when (and (not (eq sib node))
                           (eq (synthesis-node-parent sib) (synthesis-node-parent node))
                           (eq :preparation (synthesis-node-phase sib))
                           (synthesis-node-prepared sib)
                           (third (synthesis-node-prepared sib))
                           (pure-projection-decomposition-p (synthesis-node-proposal sib)))
                  (let ((sib-conflict (third (synthesis-node-prepared sib))))
                    (when (and (eq :incompatible-rows (frame-conflict-kind sib-conflict))
                               (equal (first (frame-conflict-keys sib-conflict)) (second nogood))
                               (equal (car (last (frame-conflict-keys sib-conflict))) (third nogood)))
                      (setf (fourth (synthesis-node-prepared sib)) t
                            (synthesis-node-debt sib) (min (synthesis-node-debt sib) 1))))))))
          (setf (synthesis-node-phase node) :done)
          (synthesis-message job node :conflict
                             (append (list :conflict conflict :scope :child-frame)
                                     (when reused-nogood-p (list :reused-nogood t)))))
        (progn
          (dolist (proposal (when (synthesis-node-proposal node)
                              (decomposition-children (synthesis-node-proposal node))))
            (add-synthesis-node job node proposal))
          ;; Fast-path exact heuristic child hit directly to root verification.
          (when (and h-model (heuristic-exact-p h-model) (synthesis-node-parent node))
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
                        (synthesis-node-phase node) :done)
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

(defun select-heuristic-child-node (job others)
  "Select the next child node under :heuristic or priority-predictor routing:
prepare un-prepared children first, then prefer the lowest priority score while
reserving every 4th child selection for round-robin exploration."
  (let ((unprepared (find-if (lambda (n) (member (synthesis-node-phase n) '(:prepare :preparation)))
                             others)))
    (if unprepared
        unprepared
        (let ((turn-index (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job)))))
          (if (= 3 (mod turn-index 4))
              (nth (mod (floor turn-index 4) (length others)) others)
              (let ((best (first others)))
                (dolist (candidate (rest others) best)
                  (let ((p-cand (or (synthesis-node-priority candidate) most-positive-fixnum))
                        (p-best (or (synthesis-node-priority best) most-positive-fixnum)))
                    (when (< p-cand p-best)
                      (setf best candidate))))))))))

(defun select-synthesis-lane (job)
  (let* ((root (synthesis-job-root job))
         (others (remove-if (lambda (node)
                              (or (eq node root) (eq :done (synthesis-node-phase node))
                                  (and (synthesis-node-parent node)
                                       (null (synthesis-node-frame (synthesis-node-parent node))))))
                            (synthesis-job-nodes job)))
         (root-active (not (eq :done (synthesis-node-phase root))))
         (turn (synthesis-job-turn job))
         (reserve (= 3 (mod turn 4)))
         (chosen
           (cond ((and root-active reserve) root)
                 ((or (synthesis-job-pending job) (synthesis-job-verification job)) :verify)
                 (others
                  (if (or (eq (synthesis-job-policy job) :heuristic)
                          (synthesis-job-priority-predictor job))
                      (select-heuristic-child-node job others)
                      (nth (mod (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job)))
                                (length others))
                           others)))
                 (root-active root))))
    (incf (synthesis-job-turn job))
    (when chosen
      (push (list :turn turn
                  :lane (if (eq chosen :verify) :verify (synthesis-node-id chosen))
                  :work (ledger-total (synthesis-job-ledger job))
                  :best-score (when (synthesis-job-best job)
                                (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job)))
                  :priority (when (synthesis-node-p chosen) (synthesis-node-priority chosen)))
            (synthesis-job-trace job)))
    (setf (synthesis-job-active job) chosen
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
      (:prepare (charge ledger :preparation) (prepare-synthesis-node node job))
      (:preparation
       (charge ledger :preparation) (decf (synthesis-node-debt node))
       (when (<= (synthesis-node-debt node) 0) (finish-synthesis-preparation job node)))
      (:search
       (let* ((search (synthesis-node-search node)) (before (ledger-total (search-job-ledger search)))
              (results (search-job-results search)))
         (search-step search 1)
         (charge ledger :child-search (- (ledger-total (search-job-ledger search)) before))
         (unless (eq results (search-job-results search))
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
         (eq-ops (remove-duplicates
                  (cons (op := domain)
                        (mapcar (lambda (spec) (op := (cdr spec))) inputs))
                  :test #'equal))
         (bool-ops (list (op :if :bool)))
         (domain-ops (remove-if (lambda (o)
                                  (and (consp (operator-type o))
                                       (eq :bool (car (last (operator-type o))))))
                                (language-operators language)))
         (obs-lits (loop for row in (frame-rows frame)
                         append (loop for val in (row-known row)
                                      for spec in inputs
                                      when (equal (cdr spec) domain)
                                      collect val)))
         (base-lits (if (listp (language-literals language))
                        (language-literals language)
                        '(0 1)))
         (lits (remove-duplicates (append base-lits obs-lits) :test #'equal)))
    (make-language domain inputs
                   :operators (remove-duplicates (append eq-ops bool-ops domain-ops) :test #'equal)
                   :literals lits
                   :constants (language-constants language))))

(defun find-sound-exception-guard (frame hit-mask guard-language guard-bound work-limit ledger)
  "Synthesize a Boolean guard G(X) that is T on hit rows and NIL on miss rows.
Searches both HIT-MASK and its complement MISS-MASK (wrapping a miss-selector in `bool-not`),
and falls back to the most-covering sound guard from observation buckets."
  (let* ((miss-mask (mapcar #'not hit-mask))
         (per-search-budget (max 1 (floor work-limit 3)))
         (hit-frame (support-frame frame hit-mask ledger))
         (miss-frame (support-frame frame miss-mask ledger)))
    ;; 1. Exact search on the sparser mask first (e.g. single-row outlier `(= x0 '0)`).
    (dolist (pair (if (<= (count t miss-mask) (count t hit-mask))
                      (list (cons miss-frame t) (cons hit-frame nil))
                      (list (cons hit-frame nil) (cons miss-frame t))))
      (let* ((s-frame (car pair))
             (invert-p (cdr pair))
             (search (start-search s-frame guard-language))
             (before (ledger-total (search-job-ledger search))))
        (resume-search search guard-bound per-search-budget)
        (charge ledger :guard-search (- (ledger-total (search-job-ledger search)) before))
        (when (search-job-best search)
          (let ((expr (candidate-expression (search-job-best search))))
            (return-from find-sound-exception-guard
              (if invert-p (bool-not expr) expr))))))
    ;; 2. Fallback: search observation buckets for a sound partial guard (or sound miss guard).
    (let* ((scope (make-observation-scope hit-frame guard-language))
           (obs (start-observation-search scope))
           (obs-before (ledger-total (observation-job-ledger obs))))
      (resume-observation-search obs guard-bound per-search-budget)
      (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
      (let ((best-expr nil)
            (best-hits 0)
            (best-bits most-positive-fixnum)
            (inputs (schema-inputs (frame-schema frame))))
        (dolist (bucket (observation-job-buckets obs) best-expr)
          (when (eq :bool (observation-bucket-type bucket))
            (let ((vals (observation-bucket-values bucket))
                  (sound-hit-p t)
                  (sound-miss-p t)
                  (hits 0)
                  (inv-hits 0))
              (loop for v in vals
                    for h in hit-mask
                    do (when (and (not h) v) (setf sound-hit-p nil))
                       (when (and (not h) (not v)) (setf sound-miss-p nil))
                       (when (and h v) (incf hits))
                       (when (and h (not v)) (incf inv-hits)))
              (when (or (and sound-hit-p (plusp hits))
                        (and sound-miss-p (plusp inv-hits)))
                (let* ((use-inv-p (and sound-miss-p (> inv-hits hits)))
                       (eff-hits (if use-inv-p inv-hits hits))
                       (record (car (last (observation-bucket-members bucket))))
                       (raw-expr (observed-expression-expression record))
                       (expr (if use-inv-p (bool-not raw-expr) raw-expr))
                       (bits (description-size expr inputs)))
                  (when (or (> eff-hits best-hits)
                            (and (= eff-hits best-hits) (< bits best-bits)))
                    (setf best-expr expr
                          best-hits eff-hits
                          best-bits bits)))))))))))

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
         (condense-budget (max 1 (if conditional-p (floor work-limit 2) work-limit)))
         (h-model (or heuristic-model
                      (condense-heuristic frame language
                                          :description-limit bound
                                          :work-limit condense-budget
                                          :run-weight run-weight
                                          :ledger ledger))))
    (when (or (null h-model) (heuristic-exact-p h-model))
      (return-from heuristic-decompositions (values nil h-model)))
    (let* ((program (heuristic-program h-model))
           (child-id (1+ (reduce #'max inputs :key #'car :initial-value 0)))
           (child-var (var child-id target))
           (bindings (mapcar (lambda (s) (cons (car s) (var (car s) (cdr s)))) inputs))
           (proposals nil))
      ;; Path B1: Additive / displacement residual decoder d(X, Z) = pi_hat(X) + Z
      (when (and additive-p (additive-residual-type-p target))
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
      ;; Path B2: Conditional exception-patching decoder d(X, Z) = (if G(X) pi_hat(X) Z)
      (when conditional-p
        (let ((hit-mask (heuristic-hit-mask frame h-model)))
          (when (and (some #'identity hit-mask)
                     (some #'null hit-mask))
            (let* ((g-lang (or guard-language (default-guard-language frame language)))
                   (guard (find-sound-exception-guard
                           frame hit-mask g-lang g-bound
                           (max 1 (- work-limit condense-budget))
                           ledger)))
              (when guard
                (push (make-decomposition
                       :name (list :heuristic-conditional guard program)
                       :decoder (app (op :if target) guard program child-var)
                       :child-id child-id
                       :child-type target
                       :bindings bindings
                       :language c-lang
                       :bound c-bound
                       :solver solver)
                      proposals))))))
      (values (nreverse proposals) h-model))))

(defun start-heuristic-synthesis (frame language description-limit
                                  &key decompositions child-language guard-language
                                       child-bound guard-bound
                                       (condense-budget 20000) (heuristic-budget 2000)
                                       (fibers nil) (dependencies nil)
                                       (additive-p t) (conditional-p t)
                                       solver (run-weight 0) (quantum 32)
                                       priority-predictor)
  "Condense a Stage A heuristic model on FRAME, generate Stage B additive and/or
conditional residual decompositions, and launch a `:policy :heuristic` synthesis job."
  (let ((prep-ledger (make-ledger)))
    (multiple-value-bind (h-proposals h-model)
        (heuristic-decompositions frame language
                                  :child-language child-language
                                  :guard-language guard-language
                                  :description-limit description-limit
                                  :child-bound (or child-bound description-limit)
                                  :guard-bound guard-bound
                                  :work-limit condense-budget
                                  :run-weight run-weight
                                  :additive-p additive-p
                                  :conditional-p conditional-p
                                  :solver solver
                                  :ledger prep-ledger)
      (let* ((target (schema-target (frame-schema frame)))
             (inputs (schema-inputs (frame-schema frame)))
             (id (1+ (reduce #'max inputs :key #'car :initial-value 0)))
             (fiber-proposals
               (when fibers
                 (list (make-decomposition
                        :name :fibers :decoder (var id target) :child-id id
                        :child-type target
                        :bindings (mapcar (lambda (s) (cons (car s) (var (car s) (cdr s)))) inputs)
                        :language (or child-language language)
                        :bound (or child-bound description-limit)
                        :fiber-p t))))
             (dep-proposals
               (when dependencies
                 (dependency-proposals frame (or child-language language)
                                       (or child-bound description-limit))))
             (all-proposals (append h-proposals fiber-proposals dep-proposals decompositions))
             (job (start-synthesis frame language description-limit
                                   :decompositions all-proposals
                                   :run-weight run-weight
                                   :quantum quantum
                                   :policy :heuristic
                                   :heuristic-budget heuristic-budget
                                   :priority-predictor priority-predictor)))
        (charge (synthesis-job-ledger job) :heuristic-preparation (ledger-total prep-ledger))
        (setf (synthesis-node-heuristic (synthesis-job-root job)) h-model)
        (when (and h-model (heuristic-exact-p h-model))
          (enqueue-node-candidate job (synthesis-job-root job) (heuristic-program h-model) nil))
        job))))

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
