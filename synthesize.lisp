(in-package #:lisploop)

;;; Recursive synthesis controller: nodes, preparation, scheduling, verification.

(defparameter *synthesis-debug-mode* nil
  "When non-NIL, record rich causal provenance on synthesis decompositions, nodes, and messages.")

(defparameter *max-eager-proposals-per-node* 8
  "Maximum primary decomposition proposals materialized immediately per node expansion;
excess primaries wait in `synthesis-node-deferred-proposals` ahead of fallbacks.")

(defstruct decomposition
  name decoder child-id child-type bindings language bound children
  (product-slots nil) (product-pattern nil) (structural-p nil)
  (fiber-p nil) (lift-p nil) (solver nil) (fallback-p nil) (policy-score 0 :type fixnum) (provenance nil))

(defstruct synthesis-node
  id parent proposal frame language bound search (phase :prepare) staged
  priority heuristic followers reused-from (revision 0) (reserve-rows nil) (coupled-requirements nil)
  (slot-frames nil) (slot-solutions nil) (slot-enqueued nil)
  expansion (deferred-proposals nil) (provenance nil))

(defstruct node-preparation
  frame language conflict reused-nogood-p fallback-p priority heuristic
  nogoods uip-nogood dip-repairs reserve-rows product-frames)

(defstruct staged-work node (debt 1) category publish)

(defun stage-work (node private category publish)
  "Stage PUBLISH behind the work recorded on the PRIVATE ledger; staging costs at least one unit."
  (make-staged-work :node node :debt (max 1 (ledger-total private)) :category category :publish publish))

(defun pay-staged-work (staged ledger)
  "Charge one unit of STAGED's debt to LEDGER. Once nothing is owed, publish and return true."
  (assert (plusp (staged-work-debt staged)))
  (pay-debt (staged-work-debt staged) 1 ledger (staged-work-category staged))
  (when (zerop (staged-work-debt staged))
    (when (staged-work-publish staged) (funcall (staged-work-publish staged)))
    t))

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node verification-expression verification-child-expression (verification-row-budget 2000)
  pending refinement (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
  library knowledge expand (max-depth 1) self-name oracle-table
  (nogoods nil) (deductive-nogoods-p t) (scope-cache (make-hash-table :test #'equal)) (reused-subproblems 0)
  (trace nil) (debug-p *synthesis-debug-mode*))

(defun sync-job-self-implementation (job body oracle-table finalize-p)
  (let ((self-name (and job (synthesis-job-self-name job))))
    (when self-name
      (let ((schema (frame-schema (synthesis-node-frame (synthesis-job-root job))))
            (def (find-function-definition self-name)))
        (cond
          ((null body)
           (unless (and def (null (function-definition-body def))
                        (eq (function-definition-oracle-table def) oracle-table))
             (set-function-active-implementation
              self-name (schema-inputs schema) (schema-target schema) :body nil :oracle-table oracle-table)))
          (finalize-p
           (unless (and def (null (function-definition-oracle-table def))
                        (equal (function-definition-body def) body) (function-definition-total-p def))
             (define-function self-name (schema-inputs schema) (schema-target schema) body)))
          ((not (and def (null (function-definition-oracle-table def))
                     (equal (function-definition-body def) body)))
           (set-function-active-implementation
            self-name (schema-inputs schema) (schema-target schema) :body body :oracle-table nil)))))))

(defun activate-job-oracle (job)
  "Ensure JOB's self-recursive function symbol is bound to its partial oracle table."
  (sync-job-self-implementation job nil (and job (synthesis-job-oracle-table job)) nil))

(defun activate-job-candidate-body (job candidate-expr &key finalize-p)
  "Bind JOB's self-recursive function symbol to CANDIDATE-EXPR for root VM verification.
When FINALIZE-P is true, run full `define-function` totality analysis and cache invalidation."
  (sync-job-self-implementation job candidate-expr nil finalize-p))

(defun synthesis-message (job node claim evidence)
  "Messages carry child and parent identities, scope, and evidence for later synthesis."
  (let* ((prop (and node (synthesis-node-proposal node)))
         (debug-extra (when (and job (synthesis-job-debug-p job) node)
                        (list :node-provenance (synthesis-node-provenance node)
                              :proposal-provenance (and prop (decomposition-provenance prop)))))
         (message (make-message
                   :call-id (synthesis-node-id node) :claim claim
                   :evidence (append (list :parent-id (when (synthesis-node-parent node)
                                                        (synthesis-node-id (synthesis-node-parent node)))
                                           :proposal (and prop (decomposition-name prop))
                                           :description-limit (synthesis-node-bound node)
                                           :work (ledger-total (synthesis-job-ledger job)))
                                     evidence debug-extra))))
    (push message (synthesis-job-messages job))
    message))

(defun add-synthesis-node (job parent proposal)
  (let ((node (make-synthesis-node :id (prog1 (synthesis-job-next-id job) (incf (synthesis-job-next-id job)))
                                   :parent parent :proposal proposal)))
    (setf (synthesis-job-nodes job) (append (synthesis-job-nodes job) (list node)))
    node))

(defun copy-decomposition-tree (proposal)
  (let ((copy (copy-decomposition proposal)))
    (setf (decomposition-decoder copy) (copy-tree (decomposition-decoder copy))
          (decomposition-bindings copy) (copy-tree (decomposition-bindings copy))
          (decomposition-child-type copy) (copy-tree (decomposition-child-type copy))
          (decomposition-language copy) (snapshot-language (decomposition-language copy))
          (decomposition-product-slots copy) (copy-tree (decomposition-product-slots copy))
          (decomposition-product-pattern copy) (copy-tree (decomposition-product-pattern copy))
          (decomposition-provenance copy) (copy-tree (decomposition-provenance copy))
          (decomposition-children copy) (mapcar #'copy-decomposition-tree (decomposition-children copy)))
    copy))

(defun start-synthesis (frame language description-limit
                        &key decompositions (run-weight 0) (quantum 32)
                             (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
                             library (metric nil metric-p) expand (max-depth 1)
                             self-name oracle-table (verification-row-budget 2000)
                             (deductive-nogoods-p t) (debug-p *synthesis-debug-mode*))
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber/residual proposals.
LIBRARY is applied to every pulled-back child frame and consulted for nogood schemas and DIP features.
METRIC, when given, overrides `(frame-metric frame)` for Stage A heuristic pricing.
EXPAND, a function (job node frame language heuristic-model ledger) -> decompositions,
proposes further branches below a prepared node shallower than MAX-DEPTH."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (assert (member policy '(:round-robin :heuristic)))
  (assert (or (null max-depth) (and (integerp max-depth) (>= max-depth 0))))
  (let* ((root-frame (if metric-p (derive-frame frame :metric metric) (snapshot-frame frame)))
         (root (make-synthesis-node :id 0 :frame root-frame :language (snapshot-language language)
                                    :bound description-limit :provenance (when debug-p (list :origin :root))))
         (eff-oracle (when self-name (copy-tree (or oracle-table (frame-oracle-table frame)))))
         (eff-predictor (or priority-predictor
                            (when (and (eq policy :heuristic) (knowledge-library-p library))
                              (knowledge-library-priority-predictor library))))
         (job (%make-synthesis-job
               :root root :nodes (list root) :run-weight run-weight :quantum quantum :policy policy
               :heuristic-bound heuristic-bound :heuristic-budget heuristic-budget
               :priority-predictor (priority-predictor-function eff-predictor)
               :knowledge (if (knowledge-library-p library) library *knowledge-library*)
               :expand expand :max-depth max-depth :self-name self-name :oracle-table eff-oracle
               :verification-row-budget verification-row-budget
               :deductive-nogoods-p deductive-nogoods-p :debug-p debug-p)))
    (activate-job-oracle job)
    (setf (synthesis-job-library job) (as-propagator-library library (synthesis-job-ledger job)))
    (dolist (proposal decompositions) (add-synthesis-node job root (copy-decomposition-tree proposal)))
    job))

(defun heuristic-routing-p (job)
  (or (eq :heuristic (synthesis-job-policy job)) (synthesis-job-priority-predictor job)))

(defun node-depth (node)
  "Edge distance from the synthesis root to NODE."
  (loop for parent = (synthesis-node-parent node) then (synthesis-node-parent parent) while parent count t))

(defun node-computational-depth (node)
  "Count non-structural ancestors from NODE up to (excluding) the root."
  (loop for cur = node then (synthesis-node-parent cur)
        while (and cur (synthesis-node-parent cur))
        for proposal = (synthesis-node-proposal cur)
        count (not (and proposal (decomposition-structural-p proposal)))))

(defun node-may-expand-p (job node)
  "True when the job expands, NODE is not a product coordinator, and NODE lies above the computational depth limit."
  (let ((prop (synthesis-node-proposal node)))
    (and (synthesis-job-expand job)
         (not (eq :done (synthesis-node-expansion node)))
         (not (and prop (decomposition-product-slots prop)))
         (or (null (synthesis-job-max-depth job))
             (< (node-computational-depth node) (synthesis-job-max-depth job))))))

(defun node-expandable-p (job node)
  (and (member (synthesis-node-phase node) '(:search :done)) (node-may-expand-p job node)))

(defun canonical-row-signature (row inputs)
  (list (loop for value in (row-known row) for (nil . type) in inputs
              collect (if (eq value :unresolved) :unresolved (ast->sexp (lit type value))))
        (ast->sexp (row-requirement row))))

(defun canonical-constraint-rows (rows inputs)
  (sort (mapcar (lambda (r) (canonical-row-signature r inputs)) rows) #'string< :key #'prin1-to-string))

(defun canonical-frame-edges (frame inputs)
  (let ((edges (frame-edges frame)))
    (when edges
      (let ((row-sigs (make-hash-table :test #'equal)))
        (dolist (row (frame-rows frame))
          (setf (gethash (row-key row) row-sigs) (canonical-row-signature row inputs)))
        (sort (loop for e in edges for tag = (first e)
                    for key-sigs = (mapcar (lambda (k) (prin1-to-string (gethash k row-sigs))) (edge-row-keys e))
                    collect (cons tag (if (member tag '(:distinct :distinct-soft :equal :persistence))
                                          (sort key-sigs #'string<) key-sigs)))
              #'string< :key #'prin1-to-string)))))

(defun child-scope-signature (frame language &optional reserve)
  "Frozen constraint identity, independent of occurrence names/order; keep linkage and preorder distinct."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)))
    (list (copy-tree inputs) (copy-tree (schema-target schema)) (canonicalize-schema-availability schema)
          (canonical-constraint-rows (frame-rows frame) inputs) (canonical-constraint-rows reserve inputs)
          (canonical-frame-edges frame inputs) (copy-tree (language-domain language))
          (copy-tree (language-inputs language)) (mapcar #'ast->sexp (language-operators language))
          (copy-tree (language-literals language)) (mapcar #'ast->sexp (language-constants language)))))

(defun product-coordinator-p (node)
  "True when NODE's proposal decomposes into parallel `product-slots`."
  (let ((proposal (and node (synthesis-node-proposal node))))
    (and proposal (not (null (decomposition-product-slots proposal))))))

(defun product-slot-index-for-node (parent node)
  (let ((slots (and parent (synthesis-node-proposal parent)
                    (decomposition-product-slots (synthesis-node-proposal parent))))
        (prop (synthesis-node-proposal node)))
    (when (and slots prop) (position (decomposition-child-id prop) slots :key #'first :test #'eql))))

(defun nearest-product-slot-ancestor (node)
  (loop for cur = node then (synthesis-node-parent cur)
        for parent = (and cur (synthesis-node-parent cur))
        while parent
        when (product-coordinator-p parent)
          do (let ((idx (product-slot-index-for-node parent cur)))
               (when idx (return-from nearest-product-slot-ancestor (values cur parent idx))))))

(defun node-under-product-slot-p (node)
  (not (null (nearest-product-slot-ancestor node))))

(defun factor-tuple-conjuncts (req tuple-type k ledger)
  "Attempt to factor a non-finite tuple requirement REQ into K independent per-slot requirements."
  (let ((per-slot (make-array k :initial-element nil)))
    (flet ((single-slot-conjunct (c)
             (let (target-slot coupled-p)
               (labels ((slot-at-p (node)
                          (and (app-of-p node :at) (var-p (second node)) (eql 0 (ast-id (second node)))
                               (equal (ast-type (second node)) tuple-type) (lit-p (third node))
                               (integerp (ast-value (third node))) (<= 0 (ast-value (third node)) (1- k))))
                        (walk (node)
                          (cond ((slot-at-p node)
                                 (let ((idx (ast-value (third node))))
                                   (cond ((null target-slot) (setf target-slot idx))
                                         ((/= target-slot idx) (setf coupled-p t)))))
                                ((and (var-p node) (eql 0 (ast-id node)) (equal (ast-type node) tuple-type))
                                 (setf coupled-p t))
                                ((app-p node) (dolist (arg (rest node)) (walk arg))))))
                 (walk c)
                 (cond (coupled-p :coupled)
                       (target-slot
                        (let* ((ptype (nth target-slot (rest tuple-type)))
                               (rw (map-ast (lambda (node meta)
                                              (declare (ignore meta))
                                              (when (and (slot-at-p node) (eql target-slot (ast-value (third node))))
                                                (var 0 ptype)))
                                            c :root-first t)))
                          (values target-slot (fold-necessary rw ledger 2000))))
                       (t :closed))))))
      (dolist (c (extract-conjuncts req))
        (multiple-value-bind (tag rw) (single-slot-conjunct c)
          (cond ((eq tag :coupled) (return-from factor-tuple-conjuncts nil))
                ((eq tag :closed)
                 (let ((f (fold-necessary c ledger 2000)))
                   (when (unsatisfiable-requirement-p f)
                     (return-from factor-tuple-conjuncts (make-list k :initial-element (lit :bool nil))))
                   (unless (unconstrained-requirement-p f) (return-from factor-tuple-conjuncts nil))))
                (t (push rw (aref per-slot tag))))))
      (loop for j below k for cs = (nreverse (aref per-slot j))
            collect (if cs (reduce (lambda (a b) (conjoin-requirements a b :ledger ledger)) cs) (lit :bool t))))))

(defun factor-cartesian-tuple-reqs (allowed slots k)
  (let* ((uniq (remove-duplicates allowed :test #'equal))
         (per-slot (loop for j below k collect (remove-duplicates (mapcar (lambda (tup) (nth j tup)) uniq) :test #'equal))))
    (when (= (length uniq) (reduce #'* per-slot :key #'length))
      (loop for slot in slots for vals in per-slot
            collect (if (= 1 (length vals))
                        (singleton-requirement (second slot) (first vals))
                        (set-requirement (second slot) vals))))))

(defun pullback-product-frames (proposal parent-frame &optional ledger)
  "Factor PARENT-FRAME's rows into K independent per-slot child frames preserving Galois soundness.
Returns `(VALUES slot-frames conflict)`."
  (let* ((slots (decomposition-product-slots proposal)) (pattern (decomposition-product-pattern proposal))
         (bindings (decomposition-bindings proposal)) (k (length slots))
         (schema (frame-schema parent-frame)) (parent-inputs (schema-inputs schema))
         (target (schema-target schema)) (inner-in (and pattern (code-inputs target)))
         (pat-sort (and pattern (term-sort pattern inner-in)))
         (identity-p (or (null bindings) (equal bindings (identity-bindings parent-inputs))))
         (child-inputs (if identity-p parent-inputs (binding-inputs bindings parent-inputs)))
         (rows (frame-rows parent-frame))
         (slot-vecs (loop repeat k collect (make-array (length rows) :initial-element nil)))
         au-matches)
    (flet ((conflict (kind row known expr)
             (return-from pullback-product-frames
               (values nil (make-frame-conflict :kind kind :keys (list (row-key row)) :known known :expression expr)))))
      (loop for row in rows for idx from 0
            for known = (if identity-p (copy-tree (row-known row))
                            (evaluate-row-bindings bindings parent-inputs (row-known row) :ledger ledger
                                                   :allow-unresolved-p t
                                                   :default-on-failure-p (unconstrained-requirement-p (row-requirement row))))
            for req = (row-requirement row) do
              (cond ((unconstrained-requirement-p req)
                     (loop for sv in slot-vecs do (setf (aref sv idx) (derive-row row :known known :requirement (lit :bool t)))))
                    ((unsatisfiable-requirement-p req) (conflict :unsatisfiable-row row known req))
                    (pattern
                     (multiple-value-bind (val found-p) (row-singleton-value row)
                       (unless (and found-p (equal pat-sort (term-sort val inner-in)))
                         (conflict :unsatisfiable-row row known (lit :bool nil)))
                       (multiple-value-bind (sub ok-p) (match-pattern pattern val inner-in ledger)
                         (unless ok-p (conflict :unsatisfiable-row row known (lit :bool nil)))
                         (push (list idx row known sub) au-matches))))
                    (t
                     (let* ((allowed (extract-allowed-values req))
                            (slot-reqs (cond ((and (consp allowed) (= 1 (length allowed)))
                                              (loop for slot in slots for val in (first allowed)
                                                    collect (singleton-requirement (second slot) val)))
                                             ((and (consp allowed) (> (length allowed) 1))
                                              (or (factor-cartesian-tuple-reqs allowed slots k)
                                                  (conflict :incompatible-rows row known (lit :bool nil))))
                                             (t (or (factor-tuple-conjuncts req target k ledger)
                                                    (conflict :incompatible-rows row known (lit :bool nil)))))))
                       (loop for sv in slot-vecs for sreq in slot-reqs
                             do (charge ledger :pullback (syntax-work sreq))
                                (setf (aref sv idx) (derive-row row :known known :requirement sreq)))))))
      (when (and pattern au-matches)
        (let* ((ordered (nreverse au-matches))
               (au-frame (au-substitutions-frame pattern (mapcar #'fourth ordered)
                                               :keys (mapcar (lambda (m) (row-key (second m))) ordered)
                                               :known (mapcar #'third ordered) :known-inputs child-inputs
                                               :inputs inner-in :ledger ledger)))
          (loop for (idx row known) in ordered for au-row in (frame-rows au-frame)
                for tuple-vals = (first (extract-allowed-values (row-requirement au-row))) do
                  (loop for sv in slot-vecs for slot in slots for val in tuple-vals
                        for sreq = (if (fourth slot)
                                       (if (lit-p val) (singleton-requirement (second slot) (ast-value val)) (lit :bool nil))
                                       (singleton-requirement (third slot) val))
                        do (charge ledger :pullback (syntax-work sreq))
                           (setf (aref sv idx) (derive-row row :known known :requirement sreq))))))
      (let (folded-frames)
        (loop for slot in slots for sv in slot-vecs do
          (let ((raw-frame (derive-frame parent-frame :domain nil :inputs child-inputs :target (second slot)
                                         :lookup-p nil
                                         :availability (project-schema-availability (schema-availability schema) bindings)
                                         :rows (coerce sv 'list))))
            (multiple-value-bind (conflict folded) (frame-conflict-p raw-frame :ledger ledger)
              (when conflict (return-from pullback-product-frames (values nil conflict)))
              (push folded folded-frames))))
        (values (nreverse folded-frames) nil)))))

(defun compose-product-model (proposal slot-exprs ledger &key inputs (run-weight 0) rows)
  "Assemble SLOT-EXPRS through product PROPOSAL into a parent-frame AST."
  (let* ((slots (decomposition-product-slots proposal)) (pattern (decomposition-product-pattern proposal))
         (decoder (decomposition-decoder proposal)) (bindings (decomposition-bindings proposal))
         (eff-exprs (if bindings (loop for e in slot-exprs collect (instantiate e bindings :var)) slot-exprs))
         (result
           (cond
             ((some #'pattern-has-holes-p eff-exprs)
              (instantiate decoder (loop for slot in slots for e in eff-exprs collect (cons (first slot) e)) :var))
             ((and pattern (every (lambda (s e) (if (fourth s) (lit-p e) (and (lit-p e) (code-type-p (ast-type e)))))
                                  slots eff-exprs))
              (let* ((inner-in (code-inputs (third (first slots))))
                     (ttype (code-type inner-in (term-sort pattern inner-in))))
                (lit ttype (instantiate pattern (loop for h in (pattern-holes pattern) for s in slots for e in eff-exprs
                                                      collect (cons (car h) (if (fourth s) e (ast-value e))))
                                        :hole))))
             (t
              (let ((assembled (instantiate decoder (loop for s in slots for e in slot-exprs collect (cons (first s) e))
                                            :var)))
                (if (null bindings)
                    (factor-shared-subexpressions
                     assembled :inputs (or inputs (infer-exprs-inputs (list assembled)))
                     :run-weight run-weight :rows rows :ledger ledger)
                    (let* ((rtype (expression-type assembled (binding-inputs bindings
                                                                             (or inputs (infer-exprs-inputs eff-exprs)))))
                           (proxy-cid (1+ (reduce #'max slots :key #'first :initial-value 0))))
                      (compose-model (var proxy-cid rtype) proxy-cid assembled bindings ledger
                                     :inputs inputs :run-weight run-weight :rows rows))))))))
    (charge ledger :composition (syntax-work result))
    result))

(defun compose-through (proposal expression ledger &optional inputs (run-weight 0) rows)
  "EXPRESSION, a model of PROPOSAL's child frame, composed into a model of the parent frame."
  (if (decomposition-lift-p proposal)
      (compose-lifted-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                            (decomposition-child-type proposal) expression (decomposition-bindings proposal) ledger)
      (compose-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                     expression (decomposition-bindings proposal) ledger :inputs inputs :run-weight run-weight :rows rows)))

(defun pull-through (proposal parent-frame ledger &rest lift-limits)
  "PARENT-FRAME lifted or pulled back through PROPOSAL into the child's frame."
  (apply (if (decomposition-lift-p proposal) #'lift-frame #'pullback-frame)
         parent-frame (decomposition-decoder proposal) (decomposition-child-id proposal)
         (decomposition-child-type proposal) (decomposition-bindings proposal) ledger lift-limits))

(defun reconstruct-candidate-to-ancestor (node target-ancestor expression ledger &optional (run-weight 0))
  "Reconstruct EXPRESSION from NODE up to TARGET-ANCESTOR."
  (loop until (or (null node) (eq node target-ancestor) (null (synthesis-node-parent node)))
        do (let* ((parent (synthesis-node-parent node))
                  (p-frame (synthesis-node-frame parent))
                  (p-inputs (when p-frame (schema-inputs (frame-schema p-frame))))
                  (p-rows (when p-frame (frame-rows p-frame))))
             (setf expression
                   (cond ((product-coordinator-p node) expression)
                         ((product-coordinator-p parent)
                          (let* ((slots (decomposition-product-slots (synthesis-node-proposal parent)))
                                 (sidx (product-slot-index-for-node parent node))
                                 (sols (synthesis-node-slot-solutions parent))
                                 (sexprs (loop for j below (length slots) for s in slots
                                               collect (cond ((eql j sidx) expression)
                                                             ((and sols (aref sols j)) (first (aref sols j)))
                                                             (t (fifth s))))))
                            (compose-product-model (synthesis-node-proposal parent) sexprs ledger
                                                   :inputs p-inputs :run-weight run-weight :rows p-rows)))
                         (t (compose-through (synthesis-node-proposal node) expression ledger p-inputs run-weight p-rows)))
                   node parent)))
  expression)

(defun reconstruct-synthesis-candidate (node expression &optional ledger (run-weight 0))
  "EXPRESSION, a model of NODE's frame, composed through every ancestor into a root model."
  (reconstruct-candidate-to-ancestor node nil expression ledger run-weight))

(defun expression-calls-operator-p (expr op-name)
  "True when EXPR (or any embedded `:code` literal template) contains an application of OP-NAME."
  (cond ((and (lit-p expr) (code-type-p (ast-type expr))) (expression-calls-operator-p (ast-value expr) op-name))
        ((app-p expr) (or (and (operator-p (first expr)) (eq op-name (operator-name (first expr))))
                          (some (lambda (arg) (expression-calls-operator-p arg op-name)) (rest expr))))
        (t nil)))

(defun lifted-node-p (node)
  (let ((p (synthesis-node-proposal node))) (and p (decomposition-lift-p p))))

(defun node-in-lifted-library-branch-p (node)
  (loop for cur = node then (synthesis-node-parent cur) while cur thereis (lifted-node-p cur)))

(defun valid-job-node-candidate-p (job node expr)
  (let ((self-name (and job (synthesis-job-self-name job))))
    (or (null self-name) (node-in-lifted-library-branch-p node) (node-under-product-slot-p node)
        (expression-calls-operator-p (reconstruct-synthesis-candidate node expr) self-name))))

(defun node-stage-a-budget (job node frame)
  (let ((base (synthesis-job-heuristic-budget job)))
    (when (and (integerp base) (plusp base))
      (let* ((schema (frame-schema frame)) (arity (length (schema-inputs schema))) (target (schema-target schema))
             (self (and job (synthesis-job-self-name job)))
             (scale (if (<= arity 2) 1 (expt 2 (min 4 (- arity 2)))))
             (budget (cond ((lifted-node-p node) (min (* 16 base) (* base scale (if (> arity 2) 5 2))))
                           ((and self (synthesis-node-parent node)) (* 2 base))
                           (self base)
                           (t (min (* 16 base) (* base scale)))))
             (grace (when (and (null self) (or (seq-type-p target) (code-type-p target))
                               (library-metric-decoders (synthesis-job-knowledge job) target 1))
                      (min (* 16 base) (max budget (if (seq-type-p target) 24000 8000))))))
        (values budget grace)))))

(defun node-stage-a-model (job node frame language ledger)
  (let ((rec-child-p (and job (synthesis-job-self-name job) (synthesis-node-parent node))))
    (multiple-value-bind (budget grace-budget) (node-stage-a-budget job node frame)
      (when (and (integerp budget) (plusp budget))
        (condense-heuristic
         frame language
         :description-limit (or (synthesis-job-heuristic-bound job) (synthesis-node-bound node)
                                (let ((p (synthesis-node-proposal node))) (and p (decomposition-bound p)))
                                (header-bound (schema-inputs (frame-schema frame))
                                              (schema-target (frame-schema frame)) 18))
         :work-limit (+ (ledger-total ledger) budget)
         :grace-work-limit (when grace-budget (+ (ledger-total ledger) grace-budget))
         :run-weight (synthesis-job-run-weight job)
         :stop-on-exact-p (or (node-in-lifted-library-branch-p node) rec-child-p (not (null (synthesis-node-parent node))))
         :library (synthesis-job-knowledge job) :ledger ledger)))))

(defun full-path-program-bits (node h-model ledger)
  (let ((root (loop for cur = node then (synthesis-node-parent cur) while (synthesis-node-parent cur) finally (return cur))))
    (description-size (reconstruct-synthesis-candidate node (heuristic-program h-model) ledger)
                      (schema-inputs (frame-schema (synthesis-node-frame root))))))

(defun node-trace-features (node frame h-model &optional ledger)
  "Extract the 4-element integer feature vector `(program-bits residual-bits depth constrained-rows)`."
  (list (if h-model (full-path-program-bits node h-model ledger) 100)
        (if h-model (heuristic-residual-bits h-model) 100)
        (node-depth node) (if frame (frame-constrained-row-count frame) 0)))

(defun node-policy-score (node)
  (let ((p (synthesis-node-proposal node))) (if p (decomposition-policy-score p) 0)))

(defun priority-predictor-function (predictor)
  "Normalise PREDICTOR to a function of `(node frame language h-model ledger)`, or NIL for none."
  (etypecase predictor
    (null nil)
    (function (lambda (node frame language h-model ledger)
                (declare (ignore ledger))
                (funcall predictor node frame language h-model)))
    (heuristic-model (priority-predictor-function (heuristic-program predictor)))
    ((or cons symbol)
     (let* ((arity (1+ (reduce #'max (infer-exprs-inputs (list predictor)) :key #'car :initial-value 3)))
            (inputs (loop for i below arity collect (cons i :int)))
            (fast-fn (compile-ast-fn predictor inputs))
            (cost (max 1 (or (ignore-errors (syntax-work predictor)) 1))))
       (lambda (node frame language h-model ledger)
         (declare (ignore language))
         (if (null h-model) most-positive-fixnum
             (let* ((feats (append (node-trace-features node frame h-model ledger)
                                   (list (node-policy-score node) (length (synthesis-node-coupled-requirements node)))))
                    (args (loop for i below arity collect (or (nth i feats) 0))))
               (if fast-fn
                   (progn (when ledger (charge ledger :simulation cost))
                          (let ((v (ignore-errors (funcall fast-fn args))))
                            (if (integerp v) v most-positive-fixnum)))
                   (multiple-value-bind (v ok) (eval-expr-value predictor inputs args ledger)
                     (if (and ok (integerp v)) v most-positive-fixnum))))))))))

(defun node-priority (job node frame language h-model ledger)
  (let ((pred (synthesis-job-priority-predictor job)))
    (cond (pred (funcall pred node frame language h-model ledger))
          (h-model (+ (full-path-program-bits node h-model ledger) (heuristic-residual-bits h-model)
                      (if (heuristic-exact-p h-model) 0 (ash (node-policy-score node) -1))
                      (* 16 (length (synthesis-node-coupled-requirements node)))
                      (* (synthesis-job-run-weight job) (heuristic-run-work h-model))))
          (t most-positive-fixnum))))

(defun node-library (job proposal ledger)
  (unless (and proposal (decomposition-fallback-p proposal))
    (let ((shared (and job (synthesis-job-library job))) (local (and proposal (decomposition-solver proposal))))
      (if local (as-propagator-library (if shared (list shared local) local) ledger) shared))))

(defun node-dip-repairs (job parent proposal nogoods ledger)
  (when (and nogoods (decomposition-lift-p proposal) (or (heuristic-routing-p job) (node-may-expand-p job parent)))
    (dip-repaired-decompositions parent proposal nogoods :ledger ledger :debug-p (synthesis-job-debug-p job)
                                 :library (synthesis-job-knowledge job))))

(defun maybe-collect-node-nogoods (job parent proposal target-frame conflict ledger)
  (when (and job (synthesis-job-deductive-nogoods-p job) parent proposal conflict
             (eq :incompatible-rows (frame-conflict-kind conflict))
             (or (pure-projection-decomposition-p proposal) (decomposition-lift-p proposal))
             (>= (length (frame-conflict-keys conflict)) 2))
    (collect-frame-nogood-clauses parent proposal target-frame conflict ledger)))

(defun prepare-synthesis-node (node &optional job)
  "Stage atomic host preparation privately; publish only after its tariff is paid."
  (activate-job-oracle job)
  (let* ((ledger (make-ledger)) (proposal (synthesis-node-proposal node))
         (parent (synthesis-node-parent node))
         (language (if proposal (decomposition-language proposal) (synthesis-node-language node))))
    (flet ((stage (&rest results)
             (let ((prepared (apply #'make-node-preparation :language language results)))
               (setf (synthesis-node-staged node)
                     (stage-work node ledger :preparation (lambda () (finish-synthesis-preparation job node prepared)))
                     (synthesis-node-phase node) :preparation)))
           (charge-frame-snapshot (f lang)
             (charge ledger :problem-snapshot
                     (+ 1 (loop for r in (frame-rows f)
                                sum (+ (syntax-work (row-requirement r))
                                       (loop for v in (row-known r) for s in (language-inputs lang) sum (value-work v (cdr s)))))))))
      (multiple-value-bind (ng-conflict ng-clauses) (check-parent-nogoods job parent proposal ledger)
        (when ng-conflict
          (charge ledger :problem-snapshot 1)
          (return-from prepare-synthesis-node
            (stage :conflict ng-conflict :reused-nogood-p t :nogoods ng-clauses
                   :dip-repairs (node-dip-repairs job parent proposal ng-clauses ledger)))))
      (when (and parent (product-coordinator-p node))
        (let ((pframe (synthesis-node-frame parent)))
          (multiple-value-bind (slot-frames conflict) (pullback-product-frames proposal pframe ledger)
            (if conflict (charge-frame-snapshot pframe (synthesis-node-language parent))
                (loop for sf in slot-frames for c in (decomposition-children proposal)
                      do (charge-frame-snapshot sf (decomposition-language c))))
            (return-from prepare-synthesis-node
              (stage :frame (snapshot-frame pframe) :product-frames slot-frames :conflict conflict
                     :priority (when (and (null conflict) (heuristic-routing-p job)) (node-policy-score node))
                     :nogoods (maybe-collect-node-nogoods job parent proposal pframe conflict ledger))))))
      (multiple-value-bind (frame coupled reserve-rows)
          (cond ((null parent) (synthesis-node-frame node))
                ((product-coordinator-p parent)
                 (let ((idx (product-slot-index-for-node parent node)) (cached (synthesis-node-slot-frames parent)))
                   (if (and idx cached) (snapshot-frame (nth idx cached))
                       (nth (or idx 0) (pullback-product-frames (synthesis-node-proposal parent)
                                                                (synthesis-node-frame parent) ledger)))))
                (t (pull-through proposal (synthesis-node-frame parent) ledger)))
        (setf (synthesis-node-coupled-requirements node) coupled)
        (when (and proposal (decomposition-fiber-p proposal))
          (let ((refined (nth-value 2 (infer-fibers frame ledger)))) (when refined (setf frame refined))))
        (charge-frame-snapshot frame language)
        (multiple-value-bind (conflict folded) (frame-conflict-p frame :ledger ledger)
          (let ((library (and parent (null conflict) (node-library job proposal ledger))) fallback-p)
            (when library
              (let ((prop (propagate-requirements folded library ledger)))
                (when (plusp (+ (propagation-narrowed prop) (propagation-suggested prop)))
                  (multiple-value-setq (conflict folded) (frame-conflict-p (propagation-frame prop) :ledger ledger)))
                (setf fallback-p (or (plusp (propagation-ambiguous prop))
                                     (and conflict (not (null (propagation-fallback prop))))))))
            (let* ((eff (if conflict frame folded))
                   (priced-p (and job (null conflict) (or parent (node-may-expand-p job node))
                                  (or (heuristic-routing-p job) (node-may-expand-p job node))))
                   (h-model (when priced-p (node-stage-a-model job node eff language ledger)))
                   (ngs (maybe-collect-node-nogoods job parent proposal frame conflict ledger)))
              (stage :frame eff :conflict conflict :fallback-p fallback-p :heuristic h-model
                     :priority (when (and priced-p (heuristic-routing-p job)) (node-priority job node eff language h-model ledger))
                     :nogoods ngs
                     :uip-nogood (when (and ngs (decomposition-lift-p proposal))
                                   (nth-value 0 (anti-unify-nogood-clauses (append ngs (synthesis-job-nogoods job)) ledger)))
                     :dip-repairs (node-dip-repairs job parent proposal ngs ledger) :reserve-rows reserve-rows))))))))

(defun start-root-verification (job node model child-expression)
  (let ((root (synthesis-job-root job)))
    (activate-job-candidate-body job model)
    (setf (synthesis-job-verification-node job) node
          (synthesis-job-verification-expression job) model
          (synthesis-job-verification-child-expression job) child-expression
          (synthesis-job-verification job)
          (start-search (synthesis-node-frame root) (synthesis-node-language root)
                        :run-weight (synthesis-job-run-weight job)
                        :row-budget (when (synthesis-job-self-name job) (synthesis-job-verification-row-budget job))
                        :diagnostics t :expressions (list model)))))

(defun node-satisfies-frame-p (frame expr &optional ledger (budget 2000))
  "Verify that EXPR respects availability, satisfies all resolved constrained rows and hard `frame-edges`."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
         (hard-edges (frame-hard-edges frame)) (row-values (when hard-edges (make-hash-table :test #'equal)))
         (resolved 0))
    (unless (expression-respects-availability-p expr schema) (return-from node-satisfies-frame-p nil))
    (dolist (row (frame-rows frame) (>= resolved (frame-min-resolved-rows frame)))
      (let ((run (evaluate expr inputs (row-known row) :ledger ledger :budget budget)))
        (case (evaluation-status run)
          (:unresolved nil)
          (:value (let* ((val (evaluation-value run))
                         (chk (evaluate (row-requirement row) (list (cons 0 target)) (list val) :ledger ledger :budget budget)))
                    (cond ((and (eq :value (evaluation-status chk)) (eq t (evaluation-value chk)))
                           (when hard-edges
                             (unless (hard-edges-satisfied-for-row-p (row-key row) val hard-edges row-values)
                               (return-from node-satisfies-frame-p nil))
                             (setf (gethash (row-key row) row-values) val))
                           (when (constrained-row-p row) (incf resolved)))
                          ((eq :unresolved (evaluation-status chk)) nil)
                          (t (return-from node-satisfies-frame-p nil)))))
          (otherwise (return-from node-satisfies-frame-p nil)))))))

(defun queue-pending-work (job node private category &optional publish)
  (when (or publish (plusp (ledger-total private)))
    (setf (synthesis-job-pending job) (append (synthesis-job-pending job) (list (stage-work node private category publish))))))

(defun row-satisfaction (row expression inputs &key ledger (budget 2000))
  (let ((run (evaluate expression inputs (row-known row) :ledger ledger :budget budget)))
    (case (evaluation-status run)
      (:unknown :unknown)
      (:error (if (typep (evaluation-error run) 'unresolved-evaluation) :unknown :refuted))
      (:value (let ((chk (evaluate (row-requirement row) (list (cons 0 (expression-type expression inputs)))
                                   (list (evaluation-value run)) :ledger ledger :budget budget)))
                (case (evaluation-status chk)
                  (:unknown :unknown) (:value (if (evaluation-value chk) :satisfied :refuted)) (otherwise :refuted)))))))

(defun row-satisfied-p (row expression inputs &key ledger (budget 2000))
  (eq :satisfied (row-satisfaction row expression inputs :ledger ledger :budget budget)))

(defun synthesis-descendant-p (node ancestor)
  (loop for n = node then (synthesis-node-parent n) while n thereis (eq n ancestor)))

(defun clear-product-slot-state (node)
  (setf (synthesis-node-slot-frames node) nil (synthesis-node-slot-solutions node) nil (synthesis-node-slot-enqueued node) nil))

(defun restart-revised-node (job node frame)
  (incf (synthesis-node-revision node))
  (setf (synthesis-node-frame node) frame
        (synthesis-node-search node) (start-search frame (synthesis-node-language node) :run-weight (synthesis-job-run-weight job))
        (synthesis-node-heuristic node) nil (synthesis-node-phase node) :search
        (synthesis-node-expansion node) nil (synthesis-node-reused-from node) nil)
  (clear-product-slot-state node)
  (let ((affected (remove-if-not (lambda (n) (synthesis-descendant-p n node)) (synthesis-job-nodes job))))
    (dolist (donor affected)
      (dolist (f (synthesis-node-followers donor))
        (unless (member f affected) (restart-revised-node job f (snapshot-frame (synthesis-node-frame f)))))
      (setf (synthesis-node-followers donor) nil))
    (dolist (desc affected)
      (clear-product-slot-state desc)
      (unless (eq node desc) (setf (synthesis-node-phase desc) :done (synthesis-node-expansion desc) :done))))
  (setf (synthesis-job-pending job)
        (remove-if (lambda (p) (synthesis-descendant-p (staged-work-node p) node)) (synthesis-job-pending job)))
  (clrhash (synthesis-job-scope-cache job)))

(defparameter *unfold-work-per-row* 4000
  "Lifting budget per expected fiber row when a counterexample has a lifted frame unfolded in full.")

(defun unfolded-reserve-rows (node reserve ledger)
  (let* ((active (frame-rows (synthesis-node-frame node)))
         (expected (* 2 (max 4 (+ (length active) (length reserve)))))
         (full (pull-through (synthesis-node-proposal node) (synthesis-node-frame (synthesis-node-parent node))
                             ledger (* *unfold-work-per-row* expected) nil))
         (seen (make-hash-table :test #'equal)))
    (flet ((new-row-p (r) (let ((c (list (row-known r) (row-requirement r))))
                            (unless (gethash c seen) (setf (gethash c seen) t)))))
      (mapc #'new-row-p active) (mapc #'new-row-p reserve)
      (loop for r in (frame-rows full) when (new-row-p r) collect r))))

(defun reserve-row-promotion (job node failed reserve)
  (let ((revised (snapshot-frame (synthesis-node-frame node)))
        (remaining (remove failed reserve :test #'eq :count 1)))
    (setf (frame-rows revised) (append (frame-rows revised) (list failed)))
    (lambda ()
      (setf (synthesis-node-reserve-rows node) remaining)
      (restart-revised-node job node revised)
      (synthesis-message job node :cegar-refinement
                         (list :promoted-row (row-known failed) :revision (synthesis-node-revision node)
                               :active-rows (length (frame-rows revised)) :scope :child-frame)))))

(defun refine-lifted-node-from-counterexample (job node child-expression)
  (let ((private (make-ledger)) publish)
    (when child-expression
      (loop for target = node then (synthesis-node-parent target) while (and target (null publish))
            when (or (synthesis-node-reserve-rows target) (lifted-node-p target))
              do (let ((expr (reconstruct-candidate-to-ancestor node target child-expression private))
                       (inputs (language-inputs (synthesis-node-language target)))
                       (reserve (synthesis-node-reserve-rows target)))
                   (flet ((refuted () (find-if (lambda (r) (eq :refuted (row-satisfaction r expr inputs :ledger private))) reserve)))
                     (let ((failed (or (refuted)
                                       (let ((unf (and (lifted-node-p target) (unfolded-reserve-rows target reserve private))))
                                         (when unf (setf reserve (append reserve unf)) (refuted))))))
                       (when failed (setf publish (reserve-row-promotion job target failed reserve))))))))
    (when (or publish (plusp (ledger-total private)))
      (setf (synthesis-job-refinement job) (stage-work nil private :refinement publish)))
    (not (null publish))))

(defun publish-product-slot-candidate (job p-node slot-idx slot-expr candidate-obj)
  (let* ((proposal (synthesis-node-proposal p-node)) (slots (and proposal (decomposition-product-slots proposal)))
         (sols (synthesis-node-slot-solutions p-node)) (seen (synthesis-node-slot-enqueued p-node)))
    (when (and slots sols seen (not (member slot-expr (aref sols slot-idx) :test #'equal)))
      (setf (aref sols slot-idx) (append (aref sols slot-idx) (list slot-expr)))
      (when (loop for s across sols always s)
        (let* ((choices (loop for i below (length sols)
                              collect (if (= i slot-idx) (list slot-expr)
                                          (let ((es (aref sols i))) (subseq es 0 (min 4 (length es)))))))
               (parent (synthesis-node-parent p-node))
               (p-inputs (when parent (schema-inputs (frame-schema (synthesis-node-frame parent)))))
               (p-rows (when parent (frame-rows (synthesis-node-frame parent)))) (emitted 0))
          (dolist (tuple (cartesian-product-lists choices))
            (when (>= emitted 8) (return))
            (unless (gethash tuple seen)
              (let* ((private (make-ledger))
                     (assembled (compose-product-model proposal tuple private :inputs p-inputs
                                                       :run-weight (synthesis-job-run-weight job) :rows p-rows)))
                (if (valid-job-node-candidate-p job p-node assembled)
                    (progn (setf (gethash tuple seen) t) (incf emitted)
                           (enqueue-node-candidate job p-node assembled
                                                   (or candidate-obj (make-candidate :expression assembled
                                                                                     :size (description-size assembled p-inputs)))
                                                   private))
                    (queue-pending-work job p-node private :composition))))))))))

(defun enqueue-node-candidate (job node expression candidate-obj &optional pre-ledger)
  (let ((private (or pre-ledger (make-ledger)))
        (rw (if job (synthesis-job-run-weight job) 0)))
    (flet ((note () (when candidate-obj (synthesis-message job node :child-candidate
                                                           (list :candidate candidate-obj :scope :child-frame)))))
      (multiple-value-bind (slot-node p-node slot-idx) (nearest-product-slot-ancestor node)
        (if slot-node
            (let ((slot-expr (reconstruct-candidate-to-ancestor node slot-node expression private rw)))
              (cond ((node-satisfies-frame-p (synthesis-node-frame slot-node) slot-expr private)
                     (note)
                     (queue-pending-work job p-node private :composition
                                         (lambda () (publish-product-slot-candidate job p-node slot-idx slot-expr candidate-obj))))
                    ((not (or (eq node slot-node) (refine-lifted-node-from-counterexample job node expression)))
                     (queue-pending-work job slot-node private :composition))))
            (let ((model (reconstruct-synthesis-candidate node expression private rw)))
              (note)
              (queue-pending-work job node private :composition
                                  (lambda () (start-root-verification job node model expression)))))))))

(defun exact-heuristic-program (node &optional job)
  (let ((h (synthesis-node-heuristic node)))
    (when (and h (heuristic-exact-p h) (valid-job-node-candidate-p job node (heuristic-program h)))
      (heuristic-program h))))

(defun heuristic-candidate (job expr h-model inputs)
  (make-candidate :expression expr
                  :size (if h-model (heuristic-program-bits h-model) (description-size expr inputs))
                  :run-work (if h-model (heuristic-run-work h-model) 0)
                  :discovery-work (ledger-total (synthesis-job-ledger job))))

(defun preparation-provenance (node prepared)
  (let ((prop (synthesis-node-proposal node)) (frame (node-preparation-frame prepared))
        (h (node-preparation-heuristic prepared)))
    (list :origin (or (and prop (or (getf (decomposition-provenance prop) :origin) (decomposition-name prop))) :root)
          :depth (node-depth node)
          :frame-summary (when frame (let ((total (length (frame-rows frame))) (c (frame-constrained-row-count frame)))
                                       (list :total-rows total :constrained-rows c :dead-rows (- total c)
                                             :unresolved-rows (count-if (lambda (r) (member :unresolved (row-known r)))
                                                                        (frame-rows frame)))))
          :conflict (node-preparation-conflict prepared) :reused-nogood-p (node-preparation-reused-nogood-p prepared)
          :stage-a-program (when h (heuristic-program h)) :stage-a-exact-p (when h (heuristic-exact-p h))
          :stage-a-score (when h (heuristic-score h)) :priority (node-preparation-priority prepared))))

(defun add-fallback-sibling (job node)
  (let* ((prop (synthesis-node-proposal node)) (fb (copy-decomposition-tree prop)))
    (setf (decomposition-name fb) (list :fallback (decomposition-name prop))
          (decomposition-solver fb) nil (decomposition-fallback-p fb) t
          (decomposition-provenance fb) (when (synthesis-job-debug-p job)
                                          (list :origin :fallback :from (decomposition-name prop))))
    (add-synthesis-node job (synthesis-node-parent node) fb)))

(defun proposal-identity (proposal)
  (list (decomposition-bindings proposal)
        (normalize-proposal-decoder (decomposition-decoder proposal)
                                    (decomposition-child-id proposal) (decomposition-child-type proposal))))

(defun close-conflicting-node (job node prepared)
  (let ((parent (synthesis-node-parent node)) (uip (node-preparation-uip-nogood prepared)))
    (dolist (ng (reverse (node-preparation-nogoods prepared)))
      (pushnew ng (synthesis-job-nogoods job) :key #'nogood-identity :test #'equal))
    (when (and uip (not (member (nogood-identity uip) (synthesis-job-nogoods job) :key #'nogood-identity :test #'equal)))
      (setf (synthesis-job-nogoods job) (append (synthesis-job-nogoods job) (list uip))))
    (dolist (repaired (node-preparation-dip-repairs prepared))
      (let ((id (proposal-identity repaired)))
        (unless (find-if (lambda (s) (and (eq parent (synthesis-node-parent s))
                                          (equal id (proposal-identity (synthesis-node-proposal s)))))
                         (synthesis-job-nodes job))
          (add-synthesis-node job parent repaired))))
    (setf (synthesis-node-phase node) :done (synthesis-node-expansion node) :done)
    (synthesis-message job node :conflict
                       (append (list :conflict (node-preparation-conflict prepared) :scope :child-frame)
                               (when (node-preparation-reused-nogood-p prepared) (list :reused-nogood t))))))

(defun follow-canonical-node (job node canonical)
  (setf (synthesis-node-followers canonical) (append (synthesis-node-followers canonical) (list node))
        (synthesis-node-reused-from node) (synthesis-node-id canonical)
        (synthesis-node-phase node) :done (synthesis-node-expansion node) :done)
  (incf (synthesis-job-reused-subproblems job))
  (synthesis-message job node :subproblem-reused
                     (list :canonical-id (synthesis-node-id canonical) :scope :child-frame))
  (let ((c-exact (exact-heuristic-program canonical job)) (ch (synthesis-node-heuristic canonical)))
    (when (and c-exact (not (exact-heuristic-program node job))
               (or (null ch) (<= (heuristic-program-bits ch) (synthesis-node-bound node)))
               (valid-job-node-candidate-p job node c-exact))
      (enqueue-node-candidate job node c-exact
                              (heuristic-candidate job c-exact ch (language-inputs (synthesis-node-language node))))))
  (when (synthesis-node-search canonical)
    (dolist (cand (reverse (search-job-results (synthesis-node-search canonical))))
      (when (and (<= (candidate-size cand) (synthesis-node-bound node))
                 (valid-job-node-candidate-p job node (candidate-expression cand)))
        (enqueue-node-candidate job node (candidate-expression cand) cand)))))

(defun open-prepared-node (job node)
  (let* ((prop (synthesis-node-proposal node)) (frame (synthesis-node-frame node))
         (lang (synthesis-node-language node)) (h (synthesis-node-heuristic node))
         (exact (exact-heuristic-program node job))
         (sig (when (synthesis-node-parent node) (child-scope-signature frame lang (synthesis-node-reserve-rows node))))
         (canonical (when sig (gethash sig (synthesis-job-scope-cache job)))))
    (dolist (child (and prop (decomposition-children prop))) (add-synthesis-node job node child))
    (when exact
      (when (null (heuristic-unresolved-keys h)) (setf (synthesis-node-expansion node) :done))
      (enqueue-node-candidate job node exact (heuristic-candidate job exact h (language-inputs lang))))
    (if (and canonical (not (eq canonical node)) (<= (synthesis-node-bound node) (synthesis-node-bound canonical)))
        (follow-canonical-node job node canonical)
        (progn (when sig (setf (gethash sig (synthesis-job-scope-cache job)) node))
               (setf (synthesis-node-search node) (start-search frame lang) (synthesis-node-phase node) :search)))))

(defun finish-synthesis-preparation (job node prepared)
  (let ((prop (synthesis-node-proposal node)))
    (setf (synthesis-node-frame node) (node-preparation-frame prepared)
          (synthesis-node-reserve-rows node) (node-preparation-reserve-rows prepared)
          (synthesis-node-language node) (node-preparation-language prepared)
          (synthesis-node-bound node) (or (synthesis-node-bound node) (and prop (decomposition-bound prop)))
          (synthesis-node-priority node) (node-preparation-priority prepared)
          (synthesis-node-heuristic node) (node-preparation-heuristic prepared))
    (when (synthesis-job-debug-p job) (setf (synthesis-node-provenance node) (preparation-provenance node prepared)))
    (when (and (node-preparation-fallback-p prepared) (synthesis-node-parent node) prop)
      (add-fallback-sibling job node))
    (cond ((node-preparation-conflict prepared) (close-conflicting-node job node prepared))
          ((and prop (decomposition-product-slots prop))
           (setf (synthesis-node-slot-frames node) (node-preparation-product-frames prepared)
                 (synthesis-node-slot-solutions node) (make-array (length (decomposition-product-slots prop)) :initial-element nil)
                 (synthesis-node-slot-enqueued node) (make-hash-table :test #'equal)
                 (synthesis-node-phase node) :done (synthesis-node-expansion node) :done)
           (dolist (child (decomposition-children prop)) (add-synthesis-node job node child)))
          (t (open-prepared-node job node)))))

(defun synthesis-finished-p (job)
  (and (every (lambda (n) (and (eq :done (synthesis-node-phase n))
                               (not (node-expandable-p job n))
                               (null (synthesis-node-deferred-proposals n))))
              (synthesis-job-nodes job))
       (null (synthesis-job-pending job)) (null (synthesis-job-verification job)) (null (synthesis-job-refinement job))))

(defun promote-next-deferred-proposal (job)
  "When no active child node or expansion remains on JOB, materialize the next deferred proposal."
  (let ((target (find-if #'synthesis-node-deferred-proposals (synthesis-job-nodes job))))
    (when target (add-synthesis-node job target (pop (synthesis-node-deferred-proposals target))))))

(defun action-node (action) (if (consp action) (cdr action) action))

(defun action-priority (action)
  (let* ((node (action-node action)) (price (or (synthesis-node-priority node) most-positive-fixnum)))
    (if (consp action) (- price 1/2)
        (let ((sj (and (< price most-positive-fixnum) (synthesis-node-search node))))
          (+ price (if sj (floor (ledger-total (row-job-ledger sj)) 128) 0))))))

(defun reserved-turn-p (turn) (= 3 (mod turn 4)))
(defun node-preparing-p (node) (member (synthesis-node-phase node) '(:prepare :preparation)))

(defun select-agenda-action (job actions)
  (flet ((next-cursor () (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job))))
         (rotate (pool i) (nth (mod i (length pool)) pool))
         (unprepared-primary-p (a)
           (and (atom a) (node-preparing-p a)
                (not (and (synthesis-node-proposal a) (decomposition-fallback-p (synthesis-node-proposal a)))))))
    (cond ((not (heuristic-routing-p job)) (rotate actions (next-cursor)))
          ((find-if #'unprepared-primary-p actions))
          (t (let ((turn (next-cursor)))
               (if (reserved-turn-p turn) (rotate actions (floor turn 4)) (best-by actions #'action-priority)))))))

(defun node-solved-product-slot-p (node)
  (multiple-value-bind (slot-node parent slot-idx) (nearest-product-slot-ancestor node)
    (declare (ignore slot-node))
    (let ((sols (and parent (synthesis-node-slot-solutions parent))))
      (and slot-idx sols (aref sols slot-idx) (loop for s across sols thereis (null s))))))

(defun select-synthesis-lane (job)
  (let* ((root (synthesis-job-root job)) (root-prep-p (node-preparing-p root))
         (verifying-p (or (synthesis-job-pending job) (synthesis-job-verification job)))
         (raw-others (remove-if (lambda (n) (or (eq n root) (eq :done (synthesis-node-phase n))
                                                (and (synthesis-node-parent n) (null (synthesis-node-frame (synthesis-node-parent n))))))
                                (synthesis-job-nodes job)))
         (raw-exps (loop for n in (synthesis-job-nodes job) when (node-expandable-p job n) collect (cons :expand n)))
         (open-others (remove-if #'node-solved-product-slot-p raw-others))
         (open-exps (remove-if (lambda (a) (node-solved-product-slot-p (cdr a))) raw-exps))
         (promoted (when (and (null open-others) (null open-exps) (not verifying-p) (not root-prep-p))
                     (promote-next-deferred-proposal job)))
         (others (cond (open-others open-others) (promoted (list promoted)) (open-exps nil) (t raw-others)))
         (exps (if (or open-others open-exps promoted) open-exps raw-exps))
         (actions (append others exps))
         (in-prog (or (find :preparation others :key #'synthesis-node-phase)
                      (find :paying exps :key (lambda (a) (synthesis-node-expansion (cdr a))))))
         (root-active (not (eq :done (synthesis-node-phase root))))
         (turn (synthesis-job-turn job))
         (chosen (cond ((and root-active (reserved-turn-p turn)) root) (verifying-p :verify)
                       (root-prep-p root) (in-prog in-prog) (actions (select-agenda-action job actions))
                       (root-active root))))
    (incf (synthesis-job-turn job))
    (when chosen
      (push (list :turn turn :lane (cond ((eq chosen :verify) :verify) ((consp chosen) (list :expand (synthesis-node-id (cdr chosen))))
                                         (t (synthesis-node-id chosen)))
                  :work (ledger-total (synthesis-job-ledger job))
                  :best-score (when (synthesis-job-best job) (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job)))
                  :priority (unless (eq chosen :verify) (synthesis-node-priority (action-node chosen))))
            (synthesis-job-trace job)))
    (setf (synthesis-job-active job) chosen (synthesis-job-remaining job) (synthesis-job-quantum job))))

(defun publish-node-expansion (job node proposals)
  "Materialize up to `*max-eager-proposals-per-node*` primary PROPOSALS; queue remainder in deferred-proposals."
  (let* ((ordered (stable-sort (copy-list proposals) #'< :key #'decomposition-policy-score))
         (primaries (remove-if #'decomposition-fallback-p ordered))
         (fallbacks (remove-if-not #'decomposition-fallback-p ordered))
         (limit (or *max-eager-proposals-per-node* most-positive-fixnum))
         (eager (if primaries (subseq primaries 0 (min limit (length primaries))) (and fallbacks (list (first fallbacks)))))
         (excess (when (and primaries (> (length primaries) limit)) (subseq primaries limit)))
         (rest-fb (if primaries fallbacks (rest fallbacks))))
    (dolist (p eager) (add-synthesis-node job node p))
    (setf (synthesis-node-deferred-proposals node) (append (synthesis-node-deferred-proposals node) excess rest-fb))
    (synthesis-message job node :expanded
                       (list :proposals (mapcar #'decomposition-name ordered)
                             :deferred-proposals (mapcar #'decomposition-name (synthesis-node-deferred-proposals node))
                             :depth (node-depth node)))
    (setf (synthesis-node-expansion node) :done)))

(defun synthesis-expansion-step (job node)
  (activate-job-oracle job)
  (let ((ledger (synthesis-job-ledger job)))
    (if (synthesis-node-expansion node)
        (pay-staged-work (synthesis-node-staged node) ledger)
        (let ((private (make-ledger)))
          (charge ledger :expansion)
          (let ((proposals (funcall (synthesis-job-expand job) job node (synthesis-node-frame node)
                                    (synthesis-node-language node) (synthesis-node-heuristic node) private)))
            (setf (synthesis-node-staged node) (stage-work node private :expansion (lambda () (publish-node-expansion job node proposals)))
                  (synthesis-node-expansion node) :paying))))))

(defun synthesis-verification-step (job)
  (let ((ledger (synthesis-job-ledger job)))
    (if (synthesis-job-verification job)
        (let* ((search (synthesis-job-verification job)) (before (ledger-total (search-job-ledger search))))
          (when (synthesis-job-verification-expression job)
            (activate-job-candidate-body job (synthesis-job-verification-expression job)))
          (search-step search 1)
          (charge ledger :parent-verification (- (ledger-total (search-job-ledger search)) before))
          (when (search-bound-complete-p search most-positive-fixnum)
            (let ((cand (search-job-best search)) (node (synthesis-job-verification-node job))
                  (cexpr (synthesis-job-verification-child-expression job)))
              (if cand
                  (progn (setf (candidate-discovery-work cand) (ledger-total ledger))
                         (push cand (synthesis-job-results job))
                         (when (or (null (synthesis-job-best job))
                                   (< (candidate-score cand (synthesis-job-run-weight job))
                                      (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))))
                           (setf (synthesis-job-best job) cand))
                         (synthesis-message job node :candidate (list :candidate cand :scope :original-root)))
                  (progn (synthesis-message job node :rejected (list :scope :original-root :messages (search-job-messages search)))
                         (refine-lifted-node-from-counterexample job node cexpr))))
            (setf (synthesis-job-verification job) nil (synthesis-job-verification-expression job) nil
                  (synthesis-job-verification-child-expression job) nil)))
        (let ((pending (first (synthesis-job-pending job))))
          (when (and pending (pay-staged-work pending ledger)) (pop (synthesis-job-pending job)))))))

(defun synthesis-node-step (job node)
  (activate-job-oracle job)
  (let ((ledger (synthesis-job-ledger job)))
    (case (synthesis-node-phase node)
      (:prepare (charge ledger :preparation) (prepare-synthesis-node node job))
      (:preparation (pay-staged-work (synthesis-node-staged node) ledger))
      (:search
       (let* ((search (synthesis-node-search node)) (before (ledger-total (search-job-ledger search)))
              (results (search-job-results search)))
         (search-step search 1)
         (charge ledger :child-search (- (ledger-total (search-job-ledger search)) before))
         (unless (or (eq results (search-job-results search))
                     (equal (candidate-expression (first (search-job-results search))) (exact-heuristic-program node job))
                     (not (valid-job-node-candidate-p job node (candidate-expression (first (search-job-results search))))))
           (let ((c (first (search-job-results search))))
             (enqueue-node-candidate job node (candidate-expression c) c)
             (dolist (f (synthesis-node-followers node))
               (when (and (<= (candidate-size c) (synthesis-node-bound f))
                          (valid-job-node-candidate-p job f (candidate-expression c)))
                 (enqueue-node-candidate job f (candidate-expression c) c)))))
         (when (search-bound-complete-p search (synthesis-node-bound node))
           (setf (synthesis-node-phase node) :done)
           (synthesis-message job node :bounded-exhaustion
                              (list :scope :child-grammar :results (length (search-job-results search))))))))))

(defun resume-synthesis (job work-limit &key stop-on-first)
  "Absolute cumulative tariff budget. Every fourth quantum reserves the root search.
The best verified candidate is available after every call."
  (assert (and (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (ledger-total (synthesis-job-ledger job)) work-limit)
                   (not (synthesis-finished-p job))
                   (not (and stop-on-first (synthesis-job-best job)))) do
    (cond ((synthesis-job-refinement job)
           (when (pay-staged-work (synthesis-job-refinement job) (synthesis-job-ledger job))
             (setf (synthesis-job-refinement job) nil)))
          ((or (null (synthesis-job-active job)) (zerop (synthesis-job-remaining job)))
           (charge (synthesis-job-ledger job) :scheduling) (select-synthesis-lane job))
          (t (let ((active (synthesis-job-active job)))
               (cond ((eq active :verify) (synthesis-verification-step job))
                     ((consp active) (if (eq :done (synthesis-node-expansion (cdr active)))
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
