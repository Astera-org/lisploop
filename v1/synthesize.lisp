(in-package #:lisploop)

;;; Recursive synthesis controller: nodes, preparation, scheduling, verification.

(defparameter *synthesis-debug-mode* nil
  "When non-NIL, record rich causal provenance on synthesis decompositions, nodes, and messages.")

(defstruct decomposition
  name decoder child-id child-type bindings language bound children
  (fiber-p nil) (lift-p nil) (solver nil) (fallback-p nil) (policy-score 0 :type fixnum) (provenance nil)
  ;; A product: DECODER has one variable for each of SLOTS, ((id . type) ...), and this
  ;; proposal poses the slot CHILD-ID. The proposals of one product share the same SLOTS
  ;; list and BINDINGS, and their models are joined into one model of the parent.
  (slots nil)
  ;; True when the decoder only takes values apart or puts them together: such a step is
  ;; not counted against the depth limit.
  (structural-p nil))

(defstruct synthesis-node
  id parent proposal frame language bound search (phase :prepare)
  staged ; the `staged-work` of a preparation or an expansion that is being paid for
  priority heuristic followers reused-from (revision 0) (reserve-rows nil) (coupled-requirements nil)
  ;; Lazy expansion: nil (not yet), :paying (branches staged, debt owed), or :done.
  expansion (deferred-proposals nil) (provenance nil)
  join) ; the `product-join` this node shares with the other slots of its product, or nil

;; The AND-join of a product's slots. MODELS holds (slot-id expression size pool) for every
;; slot that has a model: its smallest, and in POOL, ((expression . size) ...) smallest first,
;; the few it keeps for combination when a requirement couples it to another slot. COUPLED
;; holds each requirement that ties slots together, once, as (row-key . conjunct) over the
;; slot variables. VALUES remembers what a slot model evaluates to on those rows, and
;; EXAMINED counts the combinations of pooled models tested against COUPLED so far.
(defstruct product-join
  models coupled (examined 0) (values (make-hash-table :test #'equal)))

;; Privately staged result of `prepare-synthesis-node`, published once its debt is paid.
(defstruct node-preparation
  frame language conflict reused-nogood-p fallback-p priority heuristic
  nogoods uip-nogood dip-repairs reserve-rows
  events) ; what the preparation noted (`note-event`), earliest first

;; Host work done ahead of its payment, for NODE if it belongs to one. The result stays
;; private until DEBT units have been charged to the job under CATEGORY; PUBLISH, a thunk
;; or nil, then makes it visible.
(defstruct staged-work node (debt 1) category publish)

(defun stage-work (node private category publish)
  "Stage PUBLISH behind the work recorded on the PRIVATE ledger; staging costs at least one unit."
  (make-staged-work :node node :debt (max 1 (ledger-total private)) :category category
                    :publish publish))

(defun pay-staged-work (staged ledger)
  "Charge one unit of STAGED's debt to LEDGER. Once nothing is owed, publish and return true."
  (assert (plusp (staged-work-debt staged)))
  (pay-debt (staged-work-debt staged) 1 ledger (staged-work-category staged))
  (when (zerop (staged-work-debt staged))
    (when (staged-work-publish staged)
      (funcall (staged-work-publish staged)))
    t))

(defstruct (synthesis-job (:constructor %make-synthesis-job))
  root nodes (ledger (make-ledger)) (messages nil) results best (run-weight 0)
  (turn 0) (cursor 0) active (remaining 0) (quantum 32)
  verification verification-node verification-expression verification-child-expression (verification-row-budget 2000)
  pending refinement (next-id 1)
  (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
  library   ; the propagator library applied to every pulled-back child frame
  knowledge ; the knowledge library consulted for nogood schemas and DIP features
  expand (max-depth 1) self-name oracle-table
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

(defun send-noted-events (job node events)
  "Send EVENTS, which NODE's staged work noted (`note-event`), as messages of JOB."
  (loop for (claim . evidence) in events
        do (synthesis-message job node claim evidence)))

(defun add-synthesis-node (job parent proposal)
  "Add a node that poses PROPOSAL under PARENT. The slots of one product, which share their
`decomposition-slots` list, share one join."
  (let* ((slots (and proposal (decomposition-slots proposal)))
         (sibling (and slots
                       (find-if (lambda (other)
                                  (and (eq parent (synthesis-node-parent other))
                                       (synthesis-node-join other)
                                       (eq slots (decomposition-slots (synthesis-node-proposal other)))))
                                (synthesis-job-nodes job))))
         (node (make-synthesis-node :id (prog1 (synthesis-job-next-id job)
                                          (incf (synthesis-job-next-id job)))
                                    :parent parent :proposal proposal
                                    :join (cond (sibling (synthesis-node-join sibling))
                                                (slots (make-product-join))))))
    (setf (synthesis-job-nodes job) (append (synthesis-job-nodes job) (list node))) node))

(defun start-synthesis (frame language description-limit
                        &key decompositions (run-weight 0) (quantum 32)
                             (policy :round-robin) heuristic-bound (heuristic-budget 2000) priority-predictor
                             (library nil library-p) expand (max-depth 1)
                             self-name oracle-table (verification-row-budget 2000)
                             (deductive-nogoods-p t) (debug-p *synthesis-debug-mode*))
  "Direct selector search is always retained as the canonical root lane.
DECOMPOSITIONS are explicit alternatives, including dependency/fiber/residual proposals.
LIBRARY, a knowledge library or propagator libraries, supplies the solvers that narrow every
pulled-back child frame. Left out, it is the knowledge library active at this call, so what
that library holds is used without being asked for; given as nil, no solver is applied.
When LIBRARY is a knowledge library the job also reads its priority predictor, nogood
schemas and DIP features from it; the schemas and features otherwise come from the active
library, and the predictor is read only from a library that is named.
EXPAND, a function (job node frame language heuristic-model ledger) -> decompositions,
proposes further branches below a prepared node shallower than MAX-DEPTH, root included.
Expansion is a scheduled action, chosen like search by the node's full-path price; with
MAX-DEPTH nil the tree grows for as long as the budget lasts (an anytime search)."
  (assert (and (integerp quantum) (plusp quantum) (realp run-weight) (>= run-weight 0)))
  (assert-inputs-available frame)
  (assert (member policy '(:round-robin :heuristic)))
  (assert (or (null max-depth) (and (integerp max-depth) (>= max-depth 0))))
  (let* ((root (make-synthesis-node :id 0 :frame (snapshot-frame frame)
                                   :language (snapshot-language language) :bound description-limit
                                   :provenance (when debug-p (list :origin :root))))
         (eff-oracle (when self-name
                       (copy-tree (or oracle-table (frame-oracle-table frame)))))
         (eff-predictor (or priority-predictor
                            (when (and (eq policy :heuristic)
                                       (knowledge-library-p library))
                              (knowledge-library-priority-predictor library))))
         (job (%make-synthesis-job :root root :nodes (list root) :run-weight run-weight :quantum quantum
                                   :policy policy :heuristic-bound heuristic-bound
                                   :heuristic-budget heuristic-budget
                                   :priority-predictor (priority-predictor-function eff-predictor)
                                   :knowledge (if (knowledge-library-p library) library *knowledge-library*)
                                   :expand expand :max-depth max-depth
                                   :self-name self-name :oracle-table eff-oracle
                                   :verification-row-budget verification-row-budget
                                   :deductive-nogoods-p deductive-nogoods-p
                                   :debug-p debug-p)))
    (activate-job-oracle job)
    (setf (synthesis-job-library job)
          (as-propagator-library (if library-p library *knowledge-library*)))
    (dolist (proposal decompositions) (add-synthesis-node job root (copy-decomposition-tree proposal)))
    job))

(defun heuristic-routing-p (job)
  (or (eq :heuristic (synthesis-job-policy job)) (synthesis-job-priority-predictor job)))

(defun node-depth (node)
  "The number of decompositions between NODE and the root, structural ones aside: taking a
value apart or putting one together is not a step of computation."
  (loop for cur = node then (synthesis-node-parent cur)
        while (synthesis-node-parent cur)
        count (not (decomposition-structural-p (synthesis-node-proposal cur)))))

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

(defun canonical-constraint-rows (rows inputs)
  (sort (loop for row in rows
              collect (list (loop for value in (row-known row) for (nil . type) in inputs
                                  collect (if (eq value :unresolved) :unresolved
                                              (ast->sexp (lit type value))))
                            (ast->sexp (row-requirement row))))
        #'string<
        :key (lambda (item) (with-standard-io-syntax (prin1-to-string item)))))

(defun canonical-linkage-signature (frame)
  "The signature of FRAME's pairs, anchors and edges with every row key replaced by the
row's place in `canonical-row-order`, so it depends neither on the order the rows are
stored in nor on what they are called. Pairs and anchors keep their direction and their
order in the list, both of which Stage A prices (`relational-linkage-residual`); :equal and
:distinct edges are unordered, and edges are listed in canonical order."
  (when (or (frame-pairs frame) (frame-anchors frame) (frame-edges frame))
    (let* ((ordered (canonical-row-order frame))
           (ranks (loop for row in ordered for idx from 0 collect (cons (row-key row) idx))))
      (labels ((place (key) (or (cdr (assoc key ranks :test #'equal)) key))
               (printed (item) (with-standard-io-syntax (prin1-to-string item)))
               (unordered (a b)
                 (let ((pa (place a)) (pb (place b)))
                   (if (string< (printed pb) (printed pa)) (list pb pa) (list pa pb)))))
        (list (loop for (a b) in (frame-pairs frame) collect (list (place a) (place b)))
              (mapcar #'place (frame-anchors frame))
              (sort (loop for (kind a b) in (frame-edges frame)
                          collect (cons kind (if (eq kind :persistence)
                                                 (list (place a) (place b))
                                                 (unordered a b))))
                    #'string< :key #'printed))))))

(defun child-scope-signature (frame language &optional reserve)
  "Frozen constraint identity, independent of occurrence names/order; keep linkage contexts distinct."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (list (copy-tree inputs) (copy-tree (schema-target (frame-schema frame)))
          (canonical-constraint-rows (frame-rows frame) inputs)
          (canonical-constraint-rows reserve inputs)
          ;; Observation linkage carries occurrence semantics; canonicalize across storage order.
          (canonical-linkage-signature frame)
          (copy-tree (language-domain language))
          (copy-tree (language-inputs language))
          (mapcar #'ast->sexp (language-operators language))
          (copy-tree (language-literals language))
          (mapcar #'ast->sexp (language-constants language)))))

(defun slot-models (node expression &optional overrides)
  "A model for every slot of the product NODE is a slot of: EXPRESSION for its own, an explicit
entry in OVERRIDES or the best found so far for another, and a default literal for a slot that
has none yet."
  (let ((proposal (synthesis-node-proposal node))
        (found (product-join-models (synthesis-node-join node))))
    (loop for (id . type) in (decomposition-slots proposal)
          collect (cons id (cond ((eql id (decomposition-child-id proposal)) expression)
                                 ((cdr (assoc id overrides)))
                                 ((second (assoc id found)))
                                 (t (lit type (default-value-for-type type))))))))

(defun compose-through (node expression ledger &optional slot-overrides)
  "EXPRESSION, a model of NODE's frame, composed into a model of its parent's frame. A slot
of a product is composed with the models of the other slots (`slot-models`)."
  (let* ((proposal (synthesis-node-proposal node))
         (parent-frame (synthesis-node-frame (synthesis-node-parent node)))
         (inputs (and parent-frame (schema-inputs (frame-schema parent-frame)))))
    (cond ((synthesis-node-join node)
           (compose-product-model (decomposition-decoder proposal)
                                  (slot-models node expression slot-overrides)
                                  (decomposition-bindings proposal) ledger inputs))
          ((decomposition-lift-p proposal)
           (compose-lifted-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                                 (decomposition-child-type proposal) expression
                                 (decomposition-bindings proposal) ledger))
          (t
           (compose-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                          expression (decomposition-bindings proposal) ledger inputs)))))

(defun pull-through (proposal parent-frame ledger &rest lift-limits)
  "PARENT-FRAME lifted or pulled back through PROPOSAL into the child's frame. A lift also
returns its coupled requirements and reserve rows, and takes the LIFT-LIMITS of `lift-frame`;
a slot of a product returns the requirements that couple it to another slot."
  (cond ((decomposition-slots proposal)
         (product-slot-frame parent-frame (decomposition-decoder proposal)
                             (decomposition-slots proposal) (decomposition-child-id proposal)
                             (decomposition-bindings proposal) ledger))
        (t
         (apply (if (decomposition-lift-p proposal) #'lift-frame #'pullback-frame)
                parent-frame (decomposition-decoder proposal) (decomposition-child-id proposal)
                (decomposition-child-type proposal) (decomposition-bindings proposal) ledger
                lift-limits))))

(defun reconstruct-candidate-to-ancestor (node target-ancestor expression ledger)
  "Reconstruct EXPRESSION from NODE up to TARGET-ANCESTOR (without walking above TARGET-ANCESTOR)."
  (loop until (or (null node) (eq node target-ancestor) (null (synthesis-node-parent node)))
        do (setf expression (compose-through node expression ledger)
                 node (synthesis-node-parent node)))
  expression)

(defun reconstruct-synthesis-candidate (node expression &optional ledger)
  "EXPRESSION, a model of NODE's frame, composed through every ancestor into a root model."
  (reconstruct-candidate-to-ancestor node nil expression ledger))

(defun expression-calls-operator-p (expr op-name)
  "True when EXPR (or any embedded `:code` literal template) contains an application of operator OP-NAME."
  (cond
    ((and (lit-p expr) (code-type-p (ast-type expr)))
     (expression-calls-operator-p (ast-value expr) op-name))
    ((app-p expr)
     (or (and (operator-p (first expr))
              (eq op-name (operator-name (first expr))))
         (some (lambda (arg) (expression-calls-operator-p arg op-name))
               (rest expr))))
    (t nil)))

(defun lifted-node-p (node)
  "True when NODE's frame is lifted from its parent's through a higher-order decoder."
  (let ((proposal (synthesis-node-proposal node)))
    (and proposal (decomposition-lift-p proposal))))

(defun node-in-lifted-library-branch-p (node)
  "True when NODE or one of its ancestors lifts through a higher-order library combinator."
  (loop for cur = node then (synthesis-node-parent cur)
        while cur
        thereis (lifted-node-p cur)))

(defun valid-job-node-candidate-p (job node expr)
  "When JOB is synthesizing a recursive definition for SELF-NAME, any candidate must call SELF-NAME
unless NODE is inside a lifted higher-order library combinator branch that encapsulates the recursion.
A slot of a product is judged once it is joined: another slot may make the call."
  (let ((self-name (and job (synthesis-job-self-name job))))
    (or (null self-name)
        (node-in-lifted-library-branch-p node)
        (synthesis-node-join node)
        (expression-calls-operator-p
         (reconstruct-synthesis-candidate node expr)
         self-name))))

(defun structural-node-p (node)
  "True when NODE's proposal only takes values apart or puts them together."
  (let ((proposal (synthesis-node-proposal node)))
    (and proposal (decomposition-structural-p proposal))))

(defun stage-a-budget (job node frame)
  "The work NODE's Stage A condensation of FRAME may spend, or nil for none: the job's
heuristic budget, doubled inside a lifted branch and for the child of a recursive definition.
A node inside a lifted branch also receives the parent inputs its decoder does not consume,
and each one both adds its combinations to every tier of the grammar and makes a variable
reference dearer than a small literal, which puts the combinations of two inputs later. Its
budget is therefore multiplied by the square of its number of inputs beyond the first, the
least multiplier that keeps those combinations within reach as inputs are added (plan 8,
probes 2 & 5). Stage A stops at an exact model in a lifted branch, so the larger budget is
spent in full only where there is none."
  (let ((base (synthesis-job-heuristic-budget job))
        (lifted-p (node-in-lifted-library-branch-p node)))
    (when (and (integerp base) (plusp base))
      (* base
         (if (or lifted-p (and (synthesis-job-self-name job) (synthesis-node-parent node))) 2 1)
         (if lifted-p
             (expt (max 1 (1- (length (schema-inputs (frame-schema frame))))) 2)
             1)))))

(defun node-stage-a-model (job node frame language ledger)
  "Stage A: a budgeted heuristic condensation of NODE's own (pulled-back) frame.
Its residual is priced in the node's representation, not the root's."
  (let ((budget (stage-a-budget job node frame))
        (rec-child-p (and job (synthesis-job-self-name job) (synthesis-node-parent node))))
    (when budget
      (condense-heuristic frame language
                          :description-limit (or (synthesis-job-heuristic-bound job)
                                                 (synthesis-node-bound node)
                                                 (let ((proposal (synthesis-node-proposal node)))
                                                   (and proposal (decomposition-bound proposal)))
                                                 (header-bound (schema-inputs (frame-schema frame))
                                                               (schema-target (frame-schema frame)) 18))
                          :work-limit (+ (ledger-total ledger) budget)
                          :run-weight (synthesis-job-run-weight job)
                          :stop-on-exact-p (or (node-in-lifted-library-branch-p node) rec-child-p)
                          :ledger ledger))))

(defvar *precomputed-program-bits* nil
  "Optional `(node h-model . bits)` cache binding around `node-priority` so a predictor
that reads trace features reuses the already-computed `full-path-program-bits` without
recomputing compositions or double-charging `:composition`.")

(defun full-path-program-bits (node h-model &optional ledger)
  "The size of H-MODEL's program composed through every ancestor of NODE and described at the root."
  (if (and *precomputed-program-bits*
           (eq node (first *precomputed-program-bits*))
           (eq h-model (second *precomputed-program-bits*)))
      (cddr *precomputed-program-bits*)
      (let ((root (loop for cur = node then (synthesis-node-parent cur)
                        while (synthesis-node-parent cur)
                        finally (return cur))))
        (description-size (reconstruct-synthesis-candidate node (heuristic-program h-model) ledger)
                          (schema-inputs (frame-schema (synthesis-node-frame root)))))))

(defun node-trace-features (node frame h-model &optional ledger)
  "Extract the 4-element integer feature vector `(program-bits residual-bits depth constrained-rows)`
for NODE's Stage A condensation H-MODEL on FRAME."
  (list (if h-model (full-path-program-bits node h-model ledger) 100)
        (if h-model (heuristic-residual-bits h-model) 100)
        (node-depth node)
        (if frame (frame-constrained-row-count frame) 0)))

(defun node-policy-score (node)
  "The policy score of NODE's proposal; zero at the root."
  (let ((proposal (synthesis-node-proposal node)))
    (if proposal (decomposition-policy-score proposal) 0)))

(defun node-full-trace-features (node frame h-model &optional ledger)
  "Extract the 6-element integer feature vector
`(program-bits residual-bits depth constrained-rows policy-score coupled-count)`."
  (append (node-trace-features node frame h-model ledger)
          (list (node-policy-score node)
                (length (synthesis-node-coupled-requirements node)))))

(defun node-analytical-mdl (job node h-model &optional ledger)
  "Analytical full-path MDL priority of NODE under H-MODEL (composed through every ancestor
and priced at the root, plus residual bits, policy tie-break, coupling penalty, and run work),
or `most-positive-fixnum` when H-MODEL is nil."
  (if (null h-model)
      most-positive-fixnum
      (+ (full-path-program-bits node h-model ledger)
         (heuristic-residual-bits h-model)
         (if (heuristic-exact-p h-model) 0 (ash (node-policy-score node) -1))
         (* 16 (length (synthesis-node-coupled-requirements node)))
         (* (synthesis-job-run-weight job) (heuristic-run-work h-model)))))

(defun priority-predictor-function (predictor)
  "Normalise PREDICTOR to a function of (node frame language h-model ledger), or nil for none.
A callable is applied to the first four arguments. A `heuristic-model` or a homoiconic
S-expression AST is evaluated in the VM on the node's 6 trace features
`(program-bits residual-bits depth constrained-rows policy-score coupled-count)`."
  (etypecase predictor
    (null nil)
    (function (lambda (node frame language h-model ledger)
                (declare (ignore ledger))
                (funcall predictor node frame language h-model)))
    (heuristic-model (priority-predictor-function (heuristic-program predictor)))
    ((or cons symbol)
     (let* ((arity (1+ (reduce #'max (infer-exprs-inputs (list predictor)) :key #'car :initial-value 3)))
            (inputs (loop for i from 0 below arity collect (cons i :int)))
            (fast-fn (compile-ast-fn predictor inputs))
            (cost (max 1 (or (ignore-errors (syntax-work predictor)) 1))))
       (lambda (node frame language h-model ledger)
         (declare (ignore language))
         (if (null h-model)
             most-positive-fixnum
             (let* ((features (node-full-trace-features node frame h-model ledger))
                    (args (loop for i from 0 below arity collect (or (nth i features) 0))))
               (if fast-fn
                   (progn
                     (when ledger (charge ledger :simulation cost))
                     (let ((val (ignore-errors (funcall fast-fn args))))
                       (if (integerp val) val most-positive-fixnum)))
                   (multiple-value-bind (val ok) (eval-expr-value predictor inputs args ledger)
                     (if (and ok (integerp val)) val most-positive-fixnum))))))))))

(defun node-priority (job node frame language h-model ledger)
  "Lower is better: analytical full-path MDL (the Stage A model composed through every ancestor
and priced at the root, plus residual and penalty bits) plus the predictor's clamped signed
residual in `[-24, 48]`, or `most-positive-fixnum` when H-MODEL is nil."
  (if (null h-model)
      most-positive-fixnum
      (let* ((prog-bits (full-path-program-bits node h-model ledger))
             (*precomputed-program-bits* (list* node h-model prog-bits))
             (mdl (+ prog-bits
                     (heuristic-residual-bits h-model)
                     (if (heuristic-exact-p h-model) 0 (ash (node-policy-score node) -1))
                     (* 16 (length (synthesis-node-coupled-requirements node)))
                     (* (synthesis-job-run-weight job) (heuristic-run-work h-model))))
             (predictor (synthesis-job-priority-predictor job)))
        (if predictor
            (let ((delta (funcall predictor node frame language h-model ledger)))
              (if (and (integerp delta) (< delta most-positive-fixnum))
                  (+ mdl (max -24 (min 48 delta)))
                  mdl))
            mdl))))

(defun node-library (job proposal)
  "The job's learned propagators plus any supplied with PROPOSAL; none on a fallback branch.
The job's library is kept current with the VM, so that a function the search itself defines
does not leave it holding programs prepared for another function table."
  (unless (and proposal (decomposition-fallback-p proposal))
    (let ((shared (and job (synthesis-job-library job)
                       (setf (synthesis-job-library job)
                             (current-propagator-library (synthesis-job-library job)))))
          (local (and proposal (decomposition-solver proposal))))
      (if local
          (as-propagator-library (if shared (list shared local) local))
          shared))))

(defun node-dip-repairs (job parent proposal nogoods ledger)
  "DIP repairs of a lifted or pure-projection PROPOSAL refuted by NOGOODS, when the job can still branch under PARENT."
  (when (and nogoods
             proposal
             (or (decomposition-lift-p proposal)
                 (pure-projection-decomposition-p proposal))
             (or (heuristic-routing-p job) (node-may-expand-p job parent)))
    (dip-repaired-decompositions parent proposal nogoods
                                 :ledger ledger :debug-p (synthesis-job-debug-p job)
                                 :library (synthesis-job-knowledge job))))

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
         (*noted* nil))
    (flet ((stage (&rest results)
             (let ((prepared (apply #'make-node-preparation :language language
                                    :events (reverse *noted*) results)))
               (setf (synthesis-node-staged node)
                     (stage-work node ledger :preparation
                                 (lambda () (finish-synthesis-preparation job node prepared)))
                     (synthesis-node-phase node) :preparation))))
      (multiple-value-bind (nogood-conflict nogood-clauses)
          (check-parent-nogoods job parent proposal ledger)
        (when nogood-conflict
          (charge ledger :problem-snapshot 1)
          (return-from prepare-synthesis-node
            (stage :conflict nogood-conflict :reused-nogood-p t :nogoods nogood-clauses
                   :dip-repairs (node-dip-repairs job parent proposal nogood-clauses ledger)))))
      (multiple-value-bind (frame coupled reserve-rows)
          (if parent
              (pull-through proposal (synthesis-node-frame parent) ledger)
              (synthesis-node-frame node))
        (setf (synthesis-node-coupled-requirements node) coupled)
        (when (synthesis-node-join node)
          ;; A requirement that couples two slots reaches the join from each of them.
          (dolist (requirement coupled)
            (pushnew requirement (product-join-coupled (synthesis-node-join node)) :test #'equal)))
        (when (and proposal (decomposition-fiber-p proposal))
          (let ((refined (nth-value 2 (infer-fibers frame ledger))))
            (when refined (setf frame refined))))
        (charge ledger :problem-snapshot
                (+ 1 (loop for row in (frame-rows frame) sum
                       (+ (syntax-work (row-requirement row))
                          (loop for value in (row-known row) for spec in (language-inputs language)
                                sum (value-work value (cdr spec)))))))
        ;; A rule that inverts a defined function sees the requirement before folding can
        ;; unfold the call it would recognise.
        (let* ((callable (let ((library (and parent (node-library job proposal))))
                           (and library (callable-rules-library library))))
               (early (and callable (propagate-requirements frame callable ledger)))
               (early-ambiguous-p (and early (plusp (propagation-ambiguous early)))))
          (when (and early (plusp (+ (propagation-narrowed early) (propagation-suggested early))))
            (setf frame (propagation-frame early)))
          (multiple-value-bind (conflict folded) (frame-conflict-p frame :ledger ledger)
            (let ((library (and parent (null conflict) (node-library job proposal)))
                  (fallback-p early-ambiguous-p))
              (when library
                (let ((propagation (propagate-requirements folded library ledger)))
                  ;; A narrowing without uniqueness evidence may drop witnesses: keep the original.
                  (setf fallback-p (or fallback-p (plusp (propagation-ambiguous propagation))))
                  (when (plusp (+ (propagation-narrowed propagation) (propagation-suggested propagation)))
                    (multiple-value-setq (conflict folded)
                      (frame-conflict-p (propagation-frame propagation) :ledger ledger)))))
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
                     (dip-repairs (node-dip-repairs job parent proposal new-nogoods ledger)))
                (stage :frame effective :conflict conflict :fallback-p fallback-p
                       :heuristic h-model
                       :priority (when (and priced-p (heuristic-routing-p job))
                                   (node-priority job node effective language h-model ledger))
                       :nogoods new-nogoods
                       :uip-nogood uip-nogood
                       :dip-repairs dip-repairs
                       :reserve-rows reserve-rows)))))))))

(defun start-root-verification (job node model child-expression)
  "Start checking MODEL, the root composition of NODE's CHILD-EXPRESSION, on the root frame."
  (let ((root (synthesis-job-root job)))
    (activate-job-candidate-body job model)
    (setf (synthesis-job-verification-node job) node
          (synthesis-job-verification-expression job) model
          (synthesis-job-verification-child-expression job) child-expression
          (synthesis-job-verification job)
          (start-search (synthesis-node-frame root) (synthesis-node-language root)
                        :run-weight (synthesis-job-run-weight job)
                        :row-budget (when (synthesis-job-self-name job)
                                      (synthesis-job-verification-row-budget job))
                        :diagnostics t
                        :expressions (list model)))))

(defparameter *max-coupled-slot-candidates* 4
  "The most models a slot keeps for combination when a requirement couples it to another slot.")

(defparameter *max-coupled-combinations* 256
  "The most combinations of pooled slot models one product may test against the requirements
that couple its slots. Combining is exponential in the number of coupled slots: the bound
covers four slots of `*max-coupled-slot-candidates*` models each, and a product that
reaches it combines no further.")

(defun slot-model-row-value (join node slot-id expression row-key ledger)
  "The value EXPRESSION, a model of the slot SLOT-ID, takes on the row ROW-KEY of the slots'
frames, as (VALUES value known-p). Every slot of a product reads the same inputs, so NODE,
any slot of JOIN, supplies the row. Evaluated once on LEDGER and remembered in JOIN."
  (let* ((key (list slot-id expression row-key))
         (cached (gethash key (product-join-values join))))
    (unless cached
      (let* ((frame (synthesis-node-frame node))
             (row (find row-key (frame-rows frame) :key #'row-key :test #'equal)))
        (setf cached
              (or (and row (not (member :unresolved (row-known row)))
                       (multiple-value-bind (value known-p)
                           (eval-expr-value expression (schema-inputs (frame-schema frame))
                                            (row-known row) ledger)
                         (and known-p (list value t))))
                  (list nil nil))
              (gethash key (product-join-values join)) cached)))
    (values (first cached) (second cached))))

(defun coupled-combination-admissible-p (join node models ledger)
  "False when MODELS, ((slot-id . expression) ...) for every slot of NODE's product, give some
requirement that couples the slots a definite false on its row. The requirement is a
conjunct of what the parent requires of the product there, so such a combination cannot be
a model of the parent. One that cannot be decided here is left to verification."
  (let ((slots (decomposition-slots (synthesis-node-proposal node))))
    (every (lambda (requirement)
             (destructuring-bind (row-key . conjunct) requirement
               (let ((values (loop for (slot-id . nil) in slots
                                   collect (multiple-value-bind (value known-p)
                                               (slot-model-row-value
                                                join node slot-id (cdr (assoc slot-id models))
                                                row-key ledger)
                                             (if known-p value (return nil))))))
                 (or (null values)
                     (not (subsetp (free-vars conjunct) (mapcar #'car slots)))
                     (let ((run (evaluate conjunct slots values :ledger ledger :budget 2000)))
                       (not (and (eq :value (evaluation-status run))
                                 (null (evaluation-value run)))))))))
           (product-join-coupled join))))

(defun join-slot-candidates (job node expression ledger)
  "Record EXPRESSION as a model of NODE's slot and return the models of the parent's frame it
completes, once every slot has a model. Where no requirement couples the slots that is the
product of EXPRESSION with the smallest model of every other slot. Where one does, each
slot it names keeps its `*max-coupled-slot-candidates*` smallest models, and EXPRESSION is
combined with every choice among the other slots' models, smallest first: a combination
that falsifies a coupling requirement on its row is dropped here, for the price of
evaluating that conjunct on LEDGER, and the others are composed. A product tests at most
`*max-coupled-combinations*` combinations in all."
  (let* ((proposal (synthesis-node-proposal node))
         (join (synthesis-node-join node))
         (id (decomposition-child-id proposal))
         (size (description-size expression (schema-inputs (frame-schema (synthesis-node-frame node)))))
         (capacity (if (synthesis-node-coupled-requirements node) *max-coupled-slot-candidates* 1))
         (entry (assoc id (product-join-models join))))
    (if (null entry)
        (push (list id expression size (list (cons expression size))) (product-join-models join))
        (let ((pool (fourth entry)))
          (unless (assoc expression pool :test #'equal)
            (setf pool (stable-sort (cons (cons expression size) (copy-list pool)) #'< :key #'cdr)
                  (fourth entry) (subseq pool 0 (min capacity (length pool)))))
          (when (< size (third entry))
            (setf (second entry) expression
                  (third entry) size))))
    (flet ((product (others)
             (let ((model (compose-through node expression ledger others)))
               (and (valid-job-node-candidate-p job (synthesis-node-parent node) model)
                    model))))
      (when (every (lambda (slot) (assoc (car slot) (product-join-models join)))
                   (decomposition-slots proposal))
        (if (null (product-join-coupled join))
            (let ((model (product nil)))
              (and model (list model)))
            (let ((pools (loop for (slot-id . nil) in (decomposition-slots proposal)
                               unless (eql slot-id id)
                                 collect (loop for (model . nil) in (fourth (assoc slot-id (product-join-models join)))
                                               collect (cons slot-id model))))
                  (products nil))
              (dolist (others (cartesian-product-lists pools) (nreverse products))
                (when (>= (product-join-examined join) *max-coupled-combinations*)
                  (return (nreverse products)))
                (incf (product-join-examined join))
                (when (coupled-combination-admissible-p join node (acons id expression others) ledger)
                  (let ((model (product others)))
                    (when (and model (not (member model products :test #'equal)))
                      (push model products)))))))))))

(defun enqueue-node-candidate (job node expression candidate-obj &optional (private (make-ledger)))
  "Compose EXPRESSION, a model of NODE's frame, to the root and queue it for verification there.
A model of one slot of a product is first joined with the other slots' models into model(s)
of their parent's frame, which are queued in its place; it waits while a slot has none.
The work of composing is staged on PRIVATE: that of the join with the first model it
yields, and each further model's own."
  (when candidate-obj
    (synthesis-message job node :child-candidate (list :candidate candidate-obj :scope :child-frame)))
  (if (synthesis-node-join node)
      (let ((products (join-slot-candidates job node expression private)))
        (dolist (product products)
          (enqueue-node-candidate job (synthesis-node-parent node) product nil private)
          (setf private (make-ledger)))
        ;; The combinations a join tested are paid for even when none of them survives.
        (when (and (null products) (plusp (ledger-total private)))
          (setf (synthesis-job-pending job)
                (append (synthesis-job-pending job)
                        (list (stage-work node private :composition nil))))))
      (let ((model (reconstruct-synthesis-candidate node expression private)))
        (setf (synthesis-job-pending job)
              (append (synthesis-job-pending job)
                      (list (stage-work node private :composition
                                        (lambda () (start-root-verification job node model expression)))))))))

(defun exact-heuristic-program (node &optional job)
  "The node's own Stage A program when it already satisfies every row, else nil."
  (let ((h-model (synthesis-node-heuristic node)))
    (when (and h-model (heuristic-exact-p h-model)
               (valid-job-node-candidate-p job node (heuristic-program h-model)))
      (heuristic-program h-model))))

(defun preparation-provenance (node prepared)
  "The debug record of where NODE came from and what its preparation found."
  (let ((proposal (synthesis-node-proposal node))
        (frame (node-preparation-frame prepared))
        (h-model (node-preparation-heuristic prepared)))
    (list :origin (or (and proposal (getf (decomposition-provenance proposal) :origin))
                      (and proposal (decomposition-name proposal))
                      :root)
          :depth (node-depth node)
          :frame-summary (when frame
                           (let ((total (length (frame-rows frame)))
                                 (constrained (frame-constrained-row-count frame)))
                             (list :total-rows total
                                   :constrained-rows constrained
                                   :dead-rows (- total constrained)
                                   :unresolved-rows (count-if (lambda (r) (member :unresolved (row-known r)))
                                                              (frame-rows frame)))))
          :conflict (node-preparation-conflict prepared)
          :reused-nogood-p (node-preparation-reused-nogood-p prepared)
          :stage-a-program (when h-model (heuristic-program h-model))
          :stage-a-exact-p (when h-model (heuristic-exact-p h-model))
          :stage-a-score (when h-model (heuristic-score h-model))
          :priority (node-preparation-priority prepared))))

(defun add-fallback-sibling (job node)
  "Queue NODE's proposal again without its propagators, whose narrowing was ambiguous."
  (let* ((proposal (synthesis-node-proposal node))
         (fallback (copy-decomposition-tree proposal)))
    (setf (decomposition-name fallback) (list :fallback (decomposition-name proposal))
          (decomposition-solver fallback) nil
          (decomposition-fallback-p fallback) t
          (decomposition-provenance fallback) (when (synthesis-job-debug-p job)
                                                (list :origin :fallback
                                                      :from (decomposition-name proposal))))
    (add-synthesis-node job (synthesis-node-parent node) fallback)))

(defun proposal-identity (proposal)
  "What makes PROPOSAL pose the same child problem as a sibling: its context bindings and
its decoder up to the name of the child."
  (list (decomposition-bindings proposal)
        (normalize-proposal-decoder (decomposition-decoder proposal)
                                    (decomposition-child-id proposal)
                                    (decomposition-child-type proposal))))

(defun close-conflicting-node (job node prepared)
  "Close NODE on its checked conflict and record what was deduced from it: the nogoods,
their UIP generalisation, and DIP repairs that no sibling already poses."
  (let ((parent (synthesis-node-parent node))
        (uip (node-preparation-uip-nogood prepared)))
    (dolist (ng (reverse (node-preparation-nogoods prepared)))
      (pushnew ng (synthesis-job-nogoods job) :key #'nogood-identity :test #'equal))
    (when (and uip (not (member (nogood-identity uip) (synthesis-job-nogoods job)
                                :key #'nogood-identity :test #'equal)))
      (setf (synthesis-job-nogoods job) (append (synthesis-job-nogoods job) (list uip))))
    (dolist (repaired (node-preparation-dip-repairs prepared))
      (let ((identity (proposal-identity repaired)))
        (unless (find-if (lambda (sibling)
                           (and (eq parent (synthesis-node-parent sibling))
                                (equal identity (proposal-identity (synthesis-node-proposal sibling)))))
                         (synthesis-job-nodes job))
          (add-synthesis-node job parent repaired))))
    (setf (synthesis-node-phase node) :done
          (synthesis-node-expansion node) :done)
    (synthesis-message job node :conflict
                       (append (list :conflict (node-preparation-conflict prepared) :scope :child-frame)
                               (when (node-preparation-reused-nogood-p prepared)
                                 (list :reused-nogood t))))))

(defun follow-canonical-node (job node canonical)
  "Close NODE as a follower of CANONICAL, an earlier node with the same frozen scope whose
search covers NODE's bound, and queue the candidates that search has already found."
  (setf (synthesis-node-followers canonical) (append (synthesis-node-followers canonical) (list node))
        (synthesis-node-reused-from node) (synthesis-node-id canonical)
        (synthesis-node-phase node) :done
        ;; The canonical node expands this frame; a second subtree would duplicate it.
        (synthesis-node-expansion node) :done)
  (incf (synthesis-job-reused-subproblems job))
  (synthesis-message job node :subproblem-reused
                     (list :canonical-id (synthesis-node-id canonical) :scope :child-frame))
  (when (synthesis-node-search canonical)
    (dolist (cand (reverse (search-job-results (synthesis-node-search canonical))))
      (when (<= (candidate-size cand) (synthesis-node-bound node))
        (enqueue-node-candidate job node (candidate-expression cand) cand)))))

(defun open-prepared-node (job node)
  "Queue NODE's nested proposals and an exact Stage A program if it has one, then share the
search of an identical subproblem or start NODE's own."
  (let* ((proposal (synthesis-node-proposal node))
         (frame (synthesis-node-frame node))
         (language (synthesis-node-language node))
         (h-model (synthesis-node-heuristic node))
         (exact (exact-heuristic-program node job))
         (sig (when (synthesis-node-parent node)
                (child-scope-signature frame language (synthesis-node-reserve-rows node))))
         (canonical (when sig (gethash sig (synthesis-job-scope-cache job)))))
    (dolist (child (and proposal (decomposition-children proposal)))
      (add-synthesis-node job node child))
    (when exact
      ;; A node whose Stage A model is already exact has no residual left to branch on.
      (when (null (heuristic-unresolved-keys h-model))
        (setf (synthesis-node-expansion node) :done))
      ;; Fast-path an exact Stage A hit directly to root verification.
      (enqueue-node-candidate job node exact
                              (make-candidate :expression exact
                                              :size (heuristic-program-bits h-model)
                                              :run-work (heuristic-run-work h-model)
                                              :discovery-work (ledger-total (synthesis-job-ledger job)))))
    (if (and canonical (not (eq canonical node))
             (<= (synthesis-node-bound node) (synthesis-node-bound canonical)))
        (follow-canonical-node job node canonical)
        (progn
          (when sig
            (setf (gethash sig (synthesis-job-scope-cache job)) node))
          (setf (synthesis-node-search node) (start-search frame language)
                (synthesis-node-phase node) :search)))))

(defun finish-synthesis-preparation (job node prepared)
  "Publish NODE's paid preparation PREPARED: its frame and price, then either its conflict
or its branches and search."
  (let ((proposal (synthesis-node-proposal node)))
    (setf (synthesis-node-frame node) (node-preparation-frame prepared)
          (synthesis-node-reserve-rows node) (node-preparation-reserve-rows prepared)
          (synthesis-node-language node) (node-preparation-language prepared)
          (synthesis-node-bound node) (or (synthesis-node-bound node)
                                          (and proposal (decomposition-bound proposal)))
          (synthesis-node-priority node) (node-preparation-priority prepared)
          (synthesis-node-heuristic node) (node-preparation-heuristic prepared))
    (when (synthesis-job-debug-p job)
      (setf (synthesis-node-provenance node) (preparation-provenance node prepared)))
    (let ((frame (node-preparation-frame prepared)))
      (synthesis-message job node :prepared
                         (list :scope :child-frame
                               :depth (node-depth node)
                               :inputs (and frame (length (schema-inputs (frame-schema frame))))
                               :constrained-rows (and frame (frame-constrained-row-count frame))
                               :conflict-p (not (null (node-preparation-conflict prepared))))))
    (send-noted-events job node (node-preparation-events prepared))
    (when (and (node-preparation-fallback-p prepared) (synthesis-node-parent node) proposal)
      (add-fallback-sibling job node))
    (if (node-preparation-conflict prepared)
        (close-conflicting-node job node prepared)
        (open-prepared-node job node))))

(defun synthesis-finished-p (job)
  (and (every (lambda (n)
                (and (eq :done (synthesis-node-phase n))
                     (not (node-expandable-p job n))
                     (null (synthesis-node-deferred-proposals n))))
              (synthesis-job-nodes job))
       (null (synthesis-job-pending job)) (null (synthesis-job-verification job))
       (null (synthesis-job-refinement job))))

(defun promote-next-deferred-proposal (job)
  "When no active child node or expansion remains on JOB, materialize the next highest-priority
deferred proposal recorded on any node."
  (let ((target-node (find-if #'synthesis-node-deferred-proposals
                              (synthesis-job-nodes job))))
    (when target-node
      (let ((proposal (pop (synthesis-node-deferred-proposals target-node))))
        (add-synthesis-node job target-node proposal)))))

(defun action-node (action)
  "Agenda actions are a node (prepare or search it) or (:expand . node)."
  (if (consp action) (cdr action) action))

(defun slot-satisfied-p (node)
  "True when NODE is a slot of a product that already holds a model for it."
  (let ((join (synthesis-node-join node)))
    (and join (assoc (decomposition-child-id (synthesis-node-proposal node))
                     (product-join-models join)))))

(defun slot-waiting-p (node)
  "True when NODE is a product slot that has a model and should yield to other work. A slot
that no requirement couples to another needs no second model. One that is coupled keeps
looking for the models it may pool, but not before every slot has a first model, nor once
its pool is full or the product has spent its combinations."
  (let ((entry (slot-satisfied-p node))
        (join (synthesis-node-join node)))
    (and entry
         (or (null (synthesis-node-coupled-requirements node))
             (>= (length (fourth entry)) *max-coupled-slot-candidates*)
             (>= (product-join-examined join) *max-coupled-combinations*)
             (notevery (lambda (slot) (assoc (car slot) (product-join-models join)))
                       (decomposition-slots (synthesis-node-proposal node)))))))

(defun node-price (node)
  "NODE's full-path price: its Stage A model composed through every ancestor and priced at
the root, plus its residual. A structural node poses its parent's problem in another form,
so it is worth at least what its parent is."
  (let ((own (or (synthesis-node-priority node) most-positive-fixnum)))
    (if (structural-node-p node)
        (min own (node-price (synthesis-node-parent node)))
        own)))

(defun action-priority (action)
  "The full-path price of the action's node. Expansion wins ties: it is the cheaper
lookahead. A structural node's search wins ties with its parent's, whose candidates of that
form it finds sooner; but a slot that already has enough models waits for those that have none."
  (let* ((node (action-node action))
         (price (node-price node)))
    (cond ((consp action) (- price 1/2))
          ((slot-waiting-p node) most-positive-fixnum)
          ((structural-node-p node) (- price 1/4))
          (t price))))

(defun reserved-turn-p (turn)
  "One turn in four is held back from the preferred lane and given out in rotation."
  (= 3 (mod turn 4)))

(defun node-preparing-p (node)
  "True until NODE's preparation has been published."
  (member (synthesis-node-phase node) '(:prepare :preparation)))

(defun select-agenda-action (job actions)
  "Round-robin over ACTIONS or, under :heuristic or priority-predictor routing: prepare
unprepared primary nodes first, then take the lowest full-path price, reserving every 4th
selection for round-robin over all of ACTIONS."
  (flet ((next-cursor ()
           (prog1 (synthesis-job-cursor job) (incf (synthesis-job-cursor job))))
         (rotate (pool index)
           (nth (mod index (length pool)) pool))
         (unprepared-primary-p (action)
           (and (atom action)
                (node-preparing-p action)
                (not (and (synthesis-node-proposal action)
                          (decomposition-fallback-p (synthesis-node-proposal action)))))))
    (cond ((not (heuristic-routing-p job)) (rotate actions (next-cursor)))
          ((find-if #'unprepared-primary-p actions))
          (t
           (let ((turn (next-cursor)))
             (if (reserved-turn-p turn)
                 ;; The reserve reaches every action, unprepared fallback siblings included:
                 ;; they are the un-narrowed alternatives it exists to keep alive.
                 (rotate actions (floor turn 4))
                 (best-by actions #'action-priority)))))))

(defun select-synthesis-lane (job)
  (let* ((root (synthesis-job-root job))
         (root-preparing-p (node-preparing-p root))
         (verifying-p (or (synthesis-job-pending job) (synthesis-job-verification job)))
         (others (remove-if (lambda (node)
                              (or (eq node root) (eq :done (synthesis-node-phase node))
                                  (and (synthesis-node-parent node)
                                       (null (synthesis-node-frame (synthesis-node-parent node))))))
                            (synthesis-job-nodes job)))
         (expansions (loop for node in (synthesis-job-nodes job)
                           when (node-expandable-p job node) collect (cons :expand node))))
    (when (and (null others) (null expansions) (not verifying-p) (not root-preparing-p))
      (let ((promoted (promote-next-deferred-proposal job)))
        (when promoted
          (setf others (list promoted)))))
    (let* ((actions (append others expansions))
           ;; Staged work already started is paid off before anything else begins.
           (in-progress (or (find :preparation others :key #'synthesis-node-phase)
                            (find :paying expansions :key (lambda (a) (synthesis-node-expansion (cdr a))))))
           (root-active (not (eq :done (synthesis-node-phase root))))
           (turn (synthesis-job-turn job))
           (chosen
             (cond ((and root-active (reserved-turn-p turn)) root)
                   (verifying-p :verify)
                   ;; The root's own price and branches are needed before siblings can be ranked.
                   (root-preparing-p root)
                   (in-progress in-progress)
                   (actions (select-agenda-action job actions))
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
            (synthesis-job-remaining job) (synthesis-job-quantum job)))))

(defparameter *max-eager-proposals-per-node* nil
  "The most primary proposals one expansion materializes at once, or nil for no limit. Every
materialized proposal is prepared and priced by Stage A before the agenda can rank it, so
the limit bounds what an expansion commits; the proposals beyond it wait with the fallbacks.")

(defun eager-proposals (primaries)
  "The proposals of PRIMARIES, which are in policy-score order, to materialize at once: the
first `*max-eager-proposals-per-node*`, and with any slot of a product all its other slots,
which are of no use apart."
  (let ((limit *max-eager-proposals-per-node*))
    (if (or (null limit) (<= (length primaries) limit))
        primaries
        (let ((head (subseq primaries 0 limit)))
          (remove-if-not (lambda (proposal)
                           (or (member proposal head)
                               (and (decomposition-slots proposal)
                                    (member (decomposition-slots proposal) head
                                            :key #'decomposition-slots))))
                         primaries)))))

(defun publish-node-expansion (job node proposals)
  "Materialize NODE's PROPOSALS in policy-score order: the primary ones now, up to
`*max-eager-proposals-per-node*`, or failing any the first fallback. The others wait in
`(synthesis-node-deferred-proposals node)`, primaries first, until nothing else is left to do."
  (let* ((ordered (stable-sort (copy-list proposals) #'< :key #'decomposition-policy-score))
         (primaries (remove-if #'decomposition-fallback-p ordered))
         (fallbacks (remove-if-not #'decomposition-fallback-p ordered))
         (eager (eager-proposals primaries)))
    (dolist (proposal (or eager (and fallbacks (list (first fallbacks)))))
      (add-synthesis-node job node proposal))
    (setf (synthesis-node-deferred-proposals node)
          (append (synthesis-node-deferred-proposals node)
                  (remove-if (lambda (proposal) (member proposal eager)) primaries)
                  (if primaries fallbacks (rest fallbacks))))
    (synthesis-message job node :expanded
                       (list :proposals (mapcar #'decomposition-name ordered)
                             :deferred-proposals (mapcar #'decomposition-name
                                                         (synthesis-node-deferred-proposals node))
                             :depth (node-depth node)))
    (setf (synthesis-node-expansion node) :done)))

(defun synthesis-expansion-step (job node)
  "Stage NODE's branches privately, then publish them once their tariff is paid."
  (activate-job-oracle job)
  (let ((ledger (synthesis-job-ledger job)))
    (if (synthesis-node-expansion node)
        (pay-staged-work (synthesis-node-staged node) ledger)
        (let ((private (make-ledger))
              (*noted* nil))
          (charge ledger :expansion)
          (let ((proposals (funcall (synthesis-job-expand job) job node (synthesis-node-frame node)
                                    (synthesis-node-language node) (synthesis-node-heuristic node)
                                    private))
                (events (reverse *noted*)))
            (setf (synthesis-node-staged node)
                  (stage-work node private :expansion
                              (lambda ()
                                (send-noted-events job node events)
                                (publish-node-expansion job node proposals)))
                  (synthesis-node-expansion node) :paying))))))

(defun row-satisfaction (row expression inputs &key ledger (budget 2000))
  "Separate a demonstrated failure from an evaluation cutoff."
  (let ((run (evaluate expression inputs (row-known row) :ledger ledger :budget budget)))
    (case (evaluation-status run)
      (:unknown :unknown)
      (:error (if (typep (evaluation-error run) 'unresolved-evaluation) :unknown :refuted))
      (:value
       (let ((check (evaluate (row-requirement row)
                              (list (cons 0 (expression-type expression inputs)))
                              (list (evaluation-value run)) :ledger ledger :budget budget)))
         (case (evaluation-status check)
           (:unknown :unknown)
           (:value (if (evaluation-value check) :satisfied :refuted))
           (otherwise :refuted)))))))

(defun row-satisfied-p (row expression inputs &key ledger (budget 2000))
  (eq :satisfied (row-satisfaction row expression inputs :ledger ledger :budget budget)))

(defun synthesis-descendant-p (node ancestor)
  (loop for n = node then (synthesis-node-parent n) while n thereis (eq n ancestor)))

(defun restart-revised-node (job node frame)
  "Publish an immutable frame revision and invalidate context-dependent search decisions."
  (incf (synthesis-node-revision node))
  (setf (synthesis-node-frame node) frame
        (synthesis-node-search node) (start-search frame (synthesis-node-language node)
                                                  :run-weight (synthesis-job-run-weight job))
        (synthesis-node-heuristic node) nil
        (synthesis-node-phase node) :search
        (synthesis-node-expansion node) nil
        (synthesis-node-reused-from node) nil)
  (let ((affected (remove-if-not (lambda (n) (synthesis-descendant-p n node))
                                  (synthesis-job-nodes job))))
    ;; Sharing can cross occurrence subtrees. Detach followers of retired
    ;; descendants too, so they do not wait forever on an invalidated donor.
    (dolist (donor affected)
      (dolist (follower (synthesis-node-followers donor))
        (unless (member follower affected)
          (restart-revised-node job follower (snapshot-frame (synthesis-node-frame follower)))))
      (setf (synthesis-node-followers donor) nil))
    (dolist (descendant affected)
      (unless (eq node descendant)
        (setf (synthesis-node-phase descendant) :done
              (synthesis-node-expansion descendant) :done))))
  (setf (synthesis-job-pending job)
        (remove-if (lambda (pending) (synthesis-descendant-p (staged-work-node pending) node))
                   (synthesis-job-pending job)))
  (clrhash (synthesis-job-scope-cache job)))

(defparameter *unfold-work-per-row* 4000
  "Lifting budget per expected fiber row when a counterexample has a lifted frame unfolded in full.")

(defun unfolded-reserve-rows (node reserve ledger)
  "Lift NODE's frame again without a fiber window and return, in frame order, the rows that
are in neither its active rows nor RESERVE."
  (let* ((active (frame-rows (synthesis-node-frame node)))
         ;; The full fiber is expected to hold at most twice the rows seen so far, and at least 8.
         (expected-rows (* 2 (max 4 (+ (length active) (length reserve)))))
         (full-frame (pull-through (synthesis-node-proposal node)
                                   (synthesis-node-frame (synthesis-node-parent node))
                                   ledger (* *unfold-work-per-row* expected-rows) nil))
         (seen (make-hash-table :test #'equal)))
    (flet ((new-row-p (row) ; true the first time a row with this content is offered
             (let ((content (list (row-known row) (row-requirement row))))
               (unless (gethash content seen)
                 (setf (gethash content seen) t)))))
      (mapc #'new-row-p active)
      (mapc #'new-row-p reserve)
      (loop for row in (frame-rows full-frame)
            when (new-row-p row) collect row))))

(defun reserve-row-promotion (job node failed reserve)
  "A thunk that moves FAILED, a row of RESERVE that a candidate refutes, into NODE's frame
and restarts the search there. The revised frame is built now and published by the thunk."
  (let ((revised (snapshot-frame (synthesis-node-frame node)))
        (remaining (remove failed reserve :test #'eq :count 1)))
    (setf (frame-rows revised) (append (frame-rows revised) (list failed)))
    (lambda ()
      (setf (synthesis-node-reserve-rows node) remaining)
      (restart-revised-node job node revised)
      (synthesis-message job node :cegar-refinement
                         (list :promoted-row (row-known failed)
                               :revision (synthesis-node-revision node)
                               :active-rows (length (frame-rows revised))
                               :scope :child-frame)))))

(defun refine-lifted-node-from-counterexample (job node child-expression)
  "Stage counterexample attribution privately; publish only after its work debt is paid.
The nearest node at or above NODE with a reserve row that CHILD-EXPRESSION refutes has that
row promoted into its frame. If the counterexample lies beyond the initially unfolded
partial fiber window, additional fibers are unfolded from the parent frame on demand.
Returns true when a promotion was staged."
  (let ((private (make-ledger)) (publish nil))
    (when child-expression
      (loop for target = node then (synthesis-node-parent target)
            while (and target (null publish))
            when (or (synthesis-node-reserve-rows target) (lifted-node-p target))
              do (let ((expr (reconstruct-candidate-to-ancestor node target child-expression private))
                       (inputs (language-inputs (synthesis-node-language target)))
                       (reserve (synthesis-node-reserve-rows target)))
                   (flet ((refuted-row ()
                            (find-if (lambda (row)
                                       (eq :refuted (row-satisfaction row expr inputs :ledger private)))
                                     reserve)))
                     (let ((failed (or (refuted-row)
                                       (let ((unfolded (and (lifted-node-p target)
                                                            (unfolded-reserve-rows target reserve private))))
                                         (when unfolded
                                           (setf reserve (append reserve unfolded))
                                           (refuted-row))))))
                       (when failed
                         (setf publish (reserve-row-promotion job target failed reserve))))))))
    (when (or publish (plusp (ledger-total private)))
      (setf (synthesis-job-refinement job) (stage-work nil private :refinement publish)))
    (not (null publish))))

(defun synthesis-verification-step (job)
  (let ((ledger (synthesis-job-ledger job)))
    (if (synthesis-job-verification job)
        (let* ((search (synthesis-job-verification job)) (before (ledger-total (search-job-ledger search))))
          (when (synthesis-job-verification-expression job)
            (activate-job-candidate-body job (synthesis-job-verification-expression job)))
          (search-step search 1)
          (charge ledger :parent-verification (- (ledger-total (search-job-ledger search)) before))
          (when (search-bound-complete-p search most-positive-fixnum)
            (let ((candidate (search-job-best search))
                  (node (synthesis-job-verification-node job))
                  (child-expr (synthesis-job-verification-child-expression job)))
              (if candidate
                  (progn
                    (setf (candidate-discovery-work candidate) (ledger-total ledger))
                    (push candidate (synthesis-job-results job))
                    (when (or (null (synthesis-job-best job))
                              (< (candidate-score candidate (synthesis-job-run-weight job))
                                 (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))))
                      (setf (synthesis-job-best job) candidate))
                    (synthesis-message job node :candidate (list :candidate candidate :scope :original-root)))
                  (progn
                    (synthesis-message job node :rejected (list :scope :original-root :messages (search-job-messages search)))
                    (refine-lifted-node-from-counterexample job node child-expr))))
            (setf (synthesis-job-verification job) nil
                  (synthesis-job-verification-expression job) nil
                  (synthesis-job-verification-child-expression job) nil)))
        (let ((pending (first (synthesis-job-pending job))))
          (when (and pending (pay-staged-work pending ledger))
            (pop (synthesis-job-pending job)))))))

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
      ((synthesis-job-refinement job)
       (when (pay-staged-work (synthesis-job-refinement job) (synthesis-job-ledger job))
         (setf (synthesis-job-refinement job) nil)))
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
