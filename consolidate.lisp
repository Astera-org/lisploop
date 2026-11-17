(in-package #:lisploop)

;;; Search-trace condensation, committing a finished job to the library, and consolidation.

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
         (eff-limit (or description-limit (header-bound inputs :int 24)))
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
             (let ((fast-fn (compile-ast-fn program inputs)))
               (lambda (node frame node-lang node-h-model)
                 (declare (ignore node-lang))
                 (if (null node-h-model)
                     most-positive-fixnum
                     (let ((features (node-trace-features node frame node-h-model)))
                       (if fast-fn
                           (let ((val (ignore-errors (funcall fast-fn features))))
                             (if (integerp val) val most-positive-fixnum))
                           (multiple-value-bind (val ok) (eval-expr-value program inputs features)
                             (if (and ok (integerp val)) val most-positive-fixnum))))))))))
    (values predictor-fn h-model)))

;;; Library kinds for nogood schemas, DIP features, and priority heuristics.

(defun register-knowledge-nogood-schema (nogood-or-expr &key id (library *knowledge-library*)
                                                             domain inputs parent-clause-expr decoder
                                                             child-id child-type parent-incompatible-p
                                                             edges metadata ledger)
  "Register a reusable UIP nogood schema (`nogood-clause` or Boolean pattern AST) in LIBRARY.
A clause supplies its own parent clause, decoder and child signature; a bare pattern takes
them from the keyword arguments."
  (let* ((clause (and (nogood-clause-p nogood-or-expr) nogood-or-expr))
         (clause-expr (if clause (nogood-clause-clause-expr clause) nogood-or-expr))
         (eff-inputs (or inputs (infer-exprs-inputs (list clause-expr))))
         (pattern-bits (multiple-value-bind (constructor scope)
                           (compile-au-constructor clause-expr eff-inputs ledger)
                         (description-size constructor scope))))
    (register-knowledge-entry
     (make-knowledge-entry
      :id id
      :kind :nogood-schema
      :domain (or domain :int)
      :inputs eff-inputs
      :target :bool
      :expression clause-expr
      :guard (if clause (nogood-clause-parent-clause-expr clause) parent-clause-expr)
      :auxiliary-code (if clause (nogood-clause-decoder clause) decoder)
      :status :validated
      :certificate '(:kind :uip-anti-unification)
      :bits pattern-bits
      :edges edges
      :metadata (list* :bits-representation :au-constructor
                       :child-id (if clause (nogood-clause-child-id clause) child-id)
                       :child-type (if clause (nogood-clause-child-type clause) child-type)
                       :parent-incompatible-p (if clause
                                                  (nogood-clause-parent-incompatible-p clause)
                                                  parent-incompatible-p)
                       metadata)
      :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :nogood-schema
  (:priority 45)
  (:validate (entry library)
    (declare (ignore library))
    (assert (knowledge-entry-expression entry)))
  (:consume (entry context ledger)
    (let ((expr (knowledge-entry-expression entry))
          (inputs (knowledge-entry-inputs entry)))
      (if (pattern-has-holes-p expr)
          (evaluate (lit :bool (clause-expr-matches-known-p expr inputs context ledger))
                    nil nil :ledger ledger)
          (consume-entry-executable entry context ledger)))))

(defun register-knowledge-dip-feature (expr &key id (library *knowledge-library*) domain inputs target
                                              trigger edges metadata ledger)
  "Register a reusable Dual Implication Point (DIP) context separator expression in LIBRARY."
  (let ((eff-inputs (or inputs (infer-exprs-inputs (list expr)))))
    (register-knowledge-entry
     (make-knowledge-entry
      :id id
      :kind :dip-feature
      :domain domain
      :inputs eff-inputs
      :target (or target (expression-type expr eff-inputs))
      :expression expr
      :trigger trigger
      :status :empirical
      :certificate '(:kind :dip-row-separator)
      :edges edges
      :metadata metadata
      :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :dip-feature
  (:priority 50)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry)))

(defun register-knowledge-heuristic (heuristic-or-program &key id (library *knowledge-library*)
                                                            (inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
                                                            (target :int) residual edges metadata ledger)
  "Register a Stage A/M8D search priority predictor program (`heuristic-model` or AST) into LIBRARY."
  (let* ((model (and (heuristic-model-p heuristic-or-program) heuristic-or-program))
         (program (if model (heuristic-program model) heuristic-or-program))
         (eff-residual (if model (heuristic-residual model) residual)))
    (register-knowledge-entry
     (make-knowledge-entry
      :id id
      :kind :heuristic
      :domain :int
      :inputs inputs
      :target target
      :expression program
      :residual eff-residual
      :status (if eff-residual :empirical :validated)
      :certificate '(:kind :trace-priority-predictor)
      :bits (if model (heuristic-program-bits model) 0)
      :edges edges
      :metadata (append (when model
                          (list :residual-bits (heuristic-residual-bits model)
                                :score (heuristic-score model)))
                        metadata)
      :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :heuristic
  (:priority 60)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (setf (knowledge-library-priority-predictor library)
          (knowledge-entry-expression entry))))

;;; Committing a finished job, and consolidation.

(defun commit-synthesis-job (job &key
                                   (library *knowledge-library*)
                                   name
                                   (register-residual-p t)
                                   (register-nogoods-p t)
                                   (register-dip-p t)
                                   (register-templates-p nil)
                                   ledger)
  "Commit learned artifacts from completed `synthesis-job` JOB into LIBRARY:
1. Finalized recursive or named function definition (with discovery work and edges).
2. UIP nogood schemas (`:nogood-schema`) discovered during search.
3. DIP context separator expressions (`:dip-feature`) that repaired lifted conflicts.
4. Hybrid `(expression + residual)` `:relation` entry when JOB terminated with a non-exact
   Stage A heuristic model and no exact root candidate."
  (with-knowledge-library (library)
    (let* ((committed nil)
           (root (synthesis-job-root job))
           (best (synthesis-job-best job))
           (fn-name (or name (synthesis-job-self-name job)))
           (kname (and fn-name (canonical-op-name fn-name))))
      ;; 1. Commit verified root candidate as a :function entry when named or self-recursive
      (when (and best kname)
        (let ((root-schema (frame-schema (synthesis-node-frame root)))
              (expr (candidate-expression best)))
          (define-function kname (schema-inputs root-schema) (schema-target root-schema) expr)
          (let ((fn-entry (find-knowledge-entry kname library)))
            (when fn-entry
              (setf (knowledge-entry-work fn-entry)
                    (ledger-total (synthesis-job-ledger job)))
              ;; Record if the winning candidate lifted a library combinator
              (dolist (lib-fn (knowledge-library-function-names library))
                (when (and (not (eq lib-fn kname))
                           (expression-calls-operator-p expr lib-fn))
                  (add-knowledge-edge fn-entry :refactored-by lib-fn)
                  (add-knowledge-edge lib-fn :abstracts kname)))
              (push fn-entry committed)))))
      ;; 2. Commit UIP nogood schemas
      (let ((job-nogood-entries nil))
        (when register-nogoods-p
          (dolist (ng (synthesis-job-nogoods job))
            (when (and (eq :uip-clause (nogood-clause-kind ng))
                       (nogood-clause-clause-expr ng))
              (let ((existing (find (nogood-clause-clause-expr ng)
                                    (knowledge-entries-of-kind :nogood-schema library)
                                    :key #'knowledge-entry-expression :test #'equal)))
                (unless existing
                  (setf existing (register-knowledge-nogood-schema ng :library library :ledger ledger))
                  (push existing committed))
                (push existing job-nogood-entries)))))
        ;; 3. Commit DIP context separators from `:dip-repair` nodes
        (when register-dip-p
          (dolist (node (synthesis-job-nodes job))
            (let* ((prop (synthesis-node-proposal node))
                   (dip-name (and prop
                                  (consp (decomposition-name prop))
                                  (eq :dip-repair (first (decomposition-name prop)))
                                  (decomposition-name prop)))
                   (sep-expr (third dip-name))
                   (parent (synthesis-node-parent node))
                   (p-inputs (and parent (schema-inputs (frame-schema (synthesis-node-frame parent))))))
              (when (and sep-expr p-inputs
                         (notany (lambda (existing)
                                   (and (equal (knowledge-entry-inputs existing) p-inputs)
                                        (equal (knowledge-entry-expression existing) sep-expr)))
                                 (knowledge-entries-of-kind :dip-feature library)))
                (let ((dip-entry (register-knowledge-dip-feature sep-expr :library library
                                                                          :inputs p-inputs
                                                                          :ledger ledger)))
                  (when kname
                    (add-knowledge-edge dip-entry :repairs kname))
                  (dolist (ng-entry (reverse job-nogood-entries))
                    (add-knowledge-edge dip-entry :repairs (knowledge-entry-id ng-entry)))
                  (push dip-entry committed)))))))
      ;; 4. When no exact root candidate was found, optionally commit the best Stage A hybrid residual
      (when (and (null best) register-residual-p root)
        (let* ((root-frame (synthesis-node-frame root))
               (root-schema (frame-schema root-frame))
               (inputs (schema-inputs root-schema))
               (h-model (or (synthesis-node-heuristic root)
                            (node-stage-a-model job root root-frame (synthesis-node-language root) ledger))))
          (when (and h-model (heuristic-residual h-model))
            (let ((single-p (= 1 (length inputs))))
              (push (register-knowledge-relation
                     (or fn-name (next-knowledge-entry-id library :relation))
                     (loop for (rkey . witness) in (heuristic-residual h-model)
                           for row = (find rkey (frame-rows root-frame) :key #'row-key :test #'equal)
                           when row
                             collect (list (if single-p (first (row-known row)) (copy-list (row-known row)))
                                           witness))
                     :library library
                     :domain (schema-domain root-schema)
                     :inputs inputs
                     :target (schema-target root-schema)
                     :parametric (heuristic-program h-model)
                     :status :empirical
                     :ledger ledger)
                    committed)))))
      (append (nreverse committed)
              (when (and best register-templates-p)
                (remember-successful-decompositions job library ledger))))))

(defun job-winning-node (job)
  "The node whose candidate JOB verified as its best, or nil."
  (let* ((best (synthesis-job-best job))
         (message (and best
                       (find-if (lambda (m)
                                  (and (eq :candidate (message-claim m))
                                       (eq best (getf (message-evidence m) :candidate))))
                                (synthesis-job-messages job)))))
    (and message
         (find (message-call-id message) (synthesis-job-nodes job) :key #'synthesis-node-id))))

(defun node-library-entry (node library &optional (origins '(:library :library-filter-map)))
  "The entry of LIBRARY whose function NODE's proposal, one of ORIGINS, lifts; or nil."
  (let ((name (and (synthesis-node-proposal node)
                   (decomposition-name (synthesis-node-proposal node)))))
    (and (consp name)
         (member (first name) origins)
         (find-knowledge-entry (second name) library))))

(defun consolidate-policy-descriptors (library synthesis-jobs &key ledger)
  "Update empirical descriptor clause weights across LIBRARY from completed SYNTHESIS-JOBS
search episodes: reinforce descriptor clauses of library combinators that produced verified
root candidates, and decay empirical descriptor clauses of sibling combinators that conflicted
or failed on matching root frames."
  (let ((updated nil))
    (dolist (job synthesis-jobs (nreverse (remove-duplicates updated :test #'eq)))
      (let ((root (synthesis-job-root job))
            (win-node (job-winning-node job)))
        (when (and (synthesis-job-best job) root (synthesis-node-frame root))
          (dolist (node (synthesis-job-nodes job))
            (let ((entry (node-library-entry node library)))
              (when (and entry (knowledge-entry-descriptor-profile entry))
                (charge ledger :orientation 1)
                (flet ((adjust (delta)
                         ;; Move each eligible clause's weight by DELTA, in the profile and
                         ;; in the descriptor entries that state the clause's concept.
                         (dolist (clause (knowledge-entry-descriptor-profile entry))
                           (when (if (plusp delta)
                                     (< (descriptor-clause-weight-bits clause) 12)
                                     (and (eq :empirical (descriptor-clause-status clause))
                                          (> (descriptor-clause-weight-bits clause) 1)))
                             (incf (descriptor-clause-weight-bits clause) delta)
                             (dolist (edge (knowledge-edges-to (knowledge-entry-id entry) :describes library))
                               (let ((d (find-knowledge-entry (second edge) library)))
                                 (when (and d (eq :descriptor (knowledge-entry-kind d))
                                            (eq (descriptor-clause-id clause)
                                                (getf (knowledge-entry-metadata d) :concept)))
                                   (setf (getf (knowledge-entry-metadata d) :weight-bits)
                                         (descriptor-clause-weight-bits clause)))))
                             (push (knowledge-entry-id entry) updated)))))
                  (cond ((and win-node (synthesis-descendant-p win-node node)) (adjust 1))
                        ((and (eq (synthesis-node-parent node) root)
                              (eq :done (synthesis-node-phase node))
                              (null (synthesis-node-search node)))
                         (adjust -1))))))))))))

;;; Amortization: a function the library lifts earns the bits it saves the solutions found
;;; through it and owes the search its failed lifts cost. One that stays in debt is archived.

(defparameter *search-weight* 1/1024
  "Bits a library entry is charged for each unit of search work a failed lift of it consumed.")

(defparameter *archive-epochs* 3
  "Workload batches in a row an entry may cost more than it saves before it is archived.")

(defun entry-live-callers (entry library)
  "The active substantive entries of LIBRARY, other than ENTRY, whose code calls the function
ENTRY defines (`:decoder-template` and `:descriptor` metadata entries do not block archiving)."
  (let ((name (knowledge-entry-id entry)))
    (remove-if-not
     (lambda (other)
       (and (not (eq other entry))
            (knowledge-entry-active-p other)
            (not (member (knowledge-entry-kind other) '(:decoder-template :descriptor)))
            (some (lambda (code) (and code (expression-calls-operator-p code name)))
                  (list (knowledge-entry-expression other)
                        (knowledge-entry-guard other)
                        (knowledge-entry-trigger other)
                        (knowledge-entry-residual other)
                        (knowledge-entry-auxiliary-code other)))))
     (knowledge-library-entries library))))

(defun amortize-library-entries (library jobs &key (search-weight *search-weight*) ledger)
  "Settle the workload JOBS, a batch of finished synthesis jobs, with the functions of
LIBRARY that they lifted. An entry is credited the body bits a call to it saved each solution
verified under one of its lifts, and charged one unit of work for each lift proposed plus
the search every failed lift's subtree consumed, at SEARCH-WEIGHT bits a unit. The balance
accumulates in its :net-utility; :stale-epochs counts the batches in a row that left it worse
off. An entry in debt for `*archive-epochs*` such batches, which no active entry calls, is
archived: marked :active-p nil, so it stays defined and is no longer lifted. Entries that no
job lifted are untouched, so an empty batch changes nothing. Returns the entries archived."
  (let ((accounts nil))                 ; (entry saved . work), latest first
    (dolist (job jobs)
      (let ((win-node (job-winning-node job)))
        (dolist (node (synthesis-job-nodes job))
          (let ((entry (node-library-entry node library
                                           '(:library :library-filter-map :library-partial))))
            (when entry
              (charge ledger :orientation)
              (let ((account (or (assoc entry accounts) (first (push (list* entry 0 0) accounts)))))
                (if (and win-node (synthesis-descendant-p win-node node))
                    (progn (incf (cadr account)
                                 (max 0 (- (knowledge-entry-bits entry)
                                           (application-overhead (op (knowledge-entry-id entry))))))
                           (incf (cddr account)))
                    (incf (cddr account)
                          (1+ (loop for other in (synthesis-job-nodes job)
                                    when (and (synthesis-node-search other)
                                              (synthesis-descendant-p other node))
                                      sum (ledger-total
                                           (search-job-ledger (synthesis-node-search other)))))))))))))
    (loop for (entry saved . work) in (reverse accounts)
          for balance = (- saved (ceiling (* search-weight work)))
          do (incf (getf (knowledge-entry-metadata entry) :net-utility 0) balance)
             (setf (getf (knowledge-entry-metadata entry) :stale-epochs)
                   (if (minusp balance)
                       (1+ (getf (knowledge-entry-metadata entry) :stale-epochs 0))
                       0))
          when (and (knowledge-entry-active-p entry)
                    (minusp (getf (knowledge-entry-metadata entry) :net-utility))
                    (>= (getf (knowledge-entry-metadata entry) :stale-epochs) *archive-epochs*)
                    (null (entry-live-callers entry library)))
            do (setf (getf (knowledge-entry-metadata entry) :active-p) nil)
            and collect entry)))

(defun int-solver-replays-on-samples-p (operator position context-map inputs witness guard ledger)
  "Validate a candidate `:int` solver witness and guard against forward evaluation of OPERATOR
over small integer sample tuples. Returns (VALUES valid-p unique-on-samples-p)."
  (let* ((sample-ints '(-3 -1 0 1 2 3 5))
         (alt-ints '(-3 -2 -1 0 1 2 3 4 5 6 7))
         (arity (length (second (operator-type operator))))
         (pos-index (first (solver-positions position)))
         (cmap (or context-map (solver-context-map operator position)))
         (active-hits 0)
         (unique-p t))
    (dolist (vals (cartesian-product-lists (make-list (length inputs) :initial-element sample-ints)))
      (let ((g-run (evaluate guard inputs vals :ledger ledger)))
        (unless (eq :value (evaluation-status g-run))
          (return-from int-solver-replays-on-samples-p (values nil nil)))
        (when (evaluation-value g-run)
          (let ((w-run (evaluate witness inputs vals :ledger ledger)))
            (unless (eq :value (evaluation-status w-run))
              (return-from int-solver-replays-on-samples-p (values nil nil)))
            (let ((w-val (evaluation-value w-run))
                  (f-args (make-array arity :initial-element nil))
                  (expected nil))
              (loop for item in cmap
                    for val in vals
                    do (if (eq item :target)
                           (setf expected val)
                           (setf (aref f-args (second item)) (lit :int val))))
              (flet ((forward (candidate-val)
                       (setf (aref f-args pos-index) (lit :int candidate-val))
                       (evaluate (apply #'app operator (coerce f-args 'list)) nil nil :ledger ledger)))
                (let ((f-run (forward w-val)))
                  (unless (and (eq :value (evaluation-status f-run))
                               (equal expected (evaluation-value f-run)))
                    (return-from int-solver-replays-on-samples-p (values nil nil))))
                (incf active-hits)
                (when unique-p
                  (dolist (alt alt-ints)
                    (unless (= alt w-val)
                      (let ((alt-run (forward alt)))
                        (when (and (eq :value (evaluation-status alt-run))
                                   (equal expected (evaluation-value alt-run)))
                          (setf unique-p nil)
                          (return))))))))))))
    (values (>= active-hits 2) unique-p)))

(defun lift-field-solvers (library &key ledger)
  "Lift to :int what LIBRARY's active, witness-certified solvers say alike over several prime
fields. For each primitive operator and position that is inverted over two or more fields: when
the witnesses and guards read with their field erased anti-unify without a hole AND pass forward
sample replay on `:int` (rejecting field-division artifacts such as `:*` -> `:/` truncating
division), that common reading is registered as a `:conjecture` solver over `:int`."
  (let ((solvers (knowledge-entries-of-kind :solver library))
        (groups nil)                    ; ((name position context-map) entry ...), latest first
        (added nil))
    (flet ((signature (entry)
             (let ((meta (knowledge-entry-metadata entry)))
               (list (getf meta :operator-name) (getf meta :position) (getf meta :context-map)))))
      (dolist (entry solvers)
        (when (and (knowledge-entry-active-p entry)
                   (gf-type-p (knowledge-entry-domain entry))
                   (knowledge-evidence-current-p entry :witness)
                   (member (first (signature entry)) +operator-names+))
          (let ((group (or (assoc (signature entry) groups :test #'equal)
                           (first (push (list (signature entry)) groups)))))
            (push entry (cdr group)))))
      (dolist (group (reverse groups) (nreverse added))
        (destructuring-bind ((name position context-map) . entries) group
          (setf entries (reverse entries))
          (when (and (rest (remove-duplicates (mapcar #'knowledge-entry-domain entries) :test #'equal))
                     (notany (lambda (entry)
                               (and (eq :int (knowledge-entry-domain entry))
                                    (equal (subseq (signature entry) 0 2) (list name position))))
                             solvers))
            (flet ((erased (accessor)
                     (mapcar (lambda (entry)
                               (retype-expr (funcall accessor entry) (knowledge-entry-domain entry) :int))
                             entries)))
              (let* ((first-entry (first entries))
                     (inputs (mapcar (lambda (input)
                                       (cons (car input)
                                             (retype-type (cdr input) (knowledge-entry-domain first-entry) :int)))
                                     (knowledge-entry-inputs first-entry)))
                     (witnesses (erased #'knowledge-entry-expression))
                     (guards (erased #'knowledge-entry-guard))
                     (int-op (op name :int)))
                (unless (or (pattern-has-holes-p (anti-unify witnesses inputs ledger))
                            (pattern-has-holes-p (anti-unify guards inputs ledger)))
                  (multiple-value-bind (replays-p sample-unique-p)
                      (int-solver-replays-on-samples-p int-op position context-map inputs
                                                       (first witnesses) (first guards) ledger)
                    (when replays-p
                      (push (register-knowledge-solver
                             int-op
                             :domain :int :inputs inputs :position position :context-map context-map
                             :witness (first witnesses) :guard (first guards)
                             :unique-p (and sample-unique-p
                                            (every (lambda (e)
                                                     (knowledge-evidence-current-p e :uniqueness))
                                                   entries))
                             :edges (list (cons :lifted-from (mapcar #'knowledge-entry-id entries)))
                             :library library :ledger ledger)
                            added))))))))))))

;;; Theory motifs: functions refactored through one fold whose steps share a star of laws,
;;; associativity and an identity, are instances of one theory. What is found to hold of the
;;; fold for them is conjectured of every instance, those that come later included.

(defun usable-motif-law-p (law)
  "True when `:law` LAW is active, unconditional, and neither `:refuted` nor malformed."
  (and (knowledge-entry-active-p law)
       (member (knowledge-entry-status law) '(:validated :conjecture))
       (unconstrained-requirement-p (knowledge-entry-guard law))
       (app-of-p (knowledge-entry-expression law) :=)))

(defun law-operator-fact (law)
  "What `:law` LAW says of a binary operator, as the edge that records it: (:associative
name) when LAW reads (op (op a b) c) = (op a (op b c)) over three distinct variables,
(:identity name (e)) when it reads (op a 'e) = a or (op 'e a) = a; nil otherwise."
  (flet ((binary-p (term &optional operator)
           (and (app-p term) (= 3 (length term)) (operator-p (first term))
                (or (null operator) (eq operator (first term))))))
    (destructuring-bind (left right) (rest (knowledge-entry-expression law))
      (loop for (from to) in (list (list left right) (list right left))
            when (binary-p from)
              do (destructuring-bind (operator a b) from
                   (cond ((and (var-p to) (or (and (equal a to) (lit-p b))
                                              (and (equal b to) (lit-p a))))
                          (return (list :identity (operator-name operator)
                                        (list (ast-value (if (lit-p a) a b))))))
                         ((and (binary-p a operator) (binary-p to operator)
                               (binary-p (third to) operator)
                               (every #'var-p (list (second a) (third a) b))
                               (= 3 (length (remove-duplicates
                                             (list (ast-id (second a)) (ast-id (third a)) (ast-id b)))))
                               (equal (list (second a) (third a) b)
                                      (list (second to) (second (third to)) (third (third to)))))
                          (return (list :associative (operator-name operator))))))))))

(defun fold-signature (entry)
  "When active recursive `:function` ENTRY folds a sequence of tau to a tau, taking a (:seq tau),
a base tau and a step code of two tau to tau in some order, the positions (sequence base step)."
  (let* ((inputs (knowledge-entry-inputs entry))
         (tau (knowledge-entry-target entry))
         (body (knowledge-entry-expression entry))
         (positions (loop for type in (list (sequence-type tau) tau
                                            (code-type (list (cons 0 tau) (cons 1 tau)) tau))
                          collect (position type inputs :key #'cdr :test #'equal))))
    (and (knowledge-entry-active-p entry)
         (= 3 (length inputs))
         (notany #'null positions)
         body
         (expression-calls-operator-p body (knowledge-entry-id entry))
         (expression-calls-operator-p body :code-eval)
         positions)))

(defun fold-call (fold sequence base step)
  "The call of the fold entry FOLD on the expressions SEQUENCE, BASE and STEP."
  (let ((arguments (make-list 3)))
    (loop for position in (fold-signature fold)
          for argument in (list sequence base step)
          do (setf (nth position arguments) argument))
    (apply #'app (op (knowledge-entry-id fold)) arguments)))

(defun two-sided-identity-on-probes-p (operator base tau)
  "Verify on small probe values of TAU that BASE acts as both a left and right identity of OPERATOR."
  (let ((probes (sensitivity-probe-values tau)))
    (every (lambda (val)
             (let ((x (lit tau val)))
               (multiple-value-bind (l l-ok) (eval-expr-value (app operator base x) nil nil)
                 (multiple-value-bind (r r-ok) (eval-expr-value (app operator x base) nil nil)
                   (and l-ok r-ok (equal val l) (equal val r))))))
           (subseq probes 0 (min 3 (length probes))))))

(defun monoid-fold-instance (entry library)
  "When active `:function` ENTRY of one sequence input is refactored through a fold as
(fold X 'e '(op X0 X1)), and LIBRARY's active unconditional laws make op associative with
two-sided identity e over the element type, returns (fold-entry base step)."
  (when (knowledge-entry-active-p entry)
    (let ((body (knowledge-entry-expression entry))
          (inputs (knowledge-entry-inputs entry)))
      (loop for (nil name) in (knowledge-edges-from entry :refactored-by library)
            for fold = (find-knowledge-entry name library)
            for positions = (and fold (app-of-p body name) (fold-signature fold))
            when (and positions (= 1 (length inputs)))
              do (destructuring-bind (sequence base step)
                     (mapcar (lambda (position) (nth position (rest body))) positions)
                   (let* ((tau (knowledge-entry-target fold))
                          (code (and (lit-p step) (ast-value step)))
                          (operator (and (app-p code) (first code)))
                          (facts (and operator
                                      (loop for law in (knowledge-entries-of-kind :law library)
                                            when (and (usable-motif-law-p law)
                                                      (equal tau (knowledge-entry-domain law)))
                                              append (knowledge-edges-from law nil library)))))
                     (when (and (equal sequence (var (caar inputs) (cdar inputs)))
                                (lit-p base)
                                (or (equal (rest code) (list (var 0 tau) (var 1 tau)))
                                    (equal (rest code) (list (var 1 tau) (var 0 tau))))
                                (member (list :associative (operator-name operator)) facts :test #'equal)
                                (member (list :identity (operator-name operator) (list (ast-value base)))
                                        facts :test #'equal)
                                (two-sided-identity-on-probes-p operator base tau))
                       (return (list fold base step)))))))))

(defun induce-fold-motifs (library &key ledger)
  "Quotient the monoid folds of LIBRARY. Each active unconditional law that states an operator's
associativity or identity gets the edge saying so (`law-operator-fact`). Where the instances of
two folds of one signature (`monoid-fold-instance`) cover two or more operators and each
instance's step and base give both folds the same value on every probe sequence, the equation of
the two folds is registered as a `:motif` over the first fold's inputs. Every instance of a
motif's folds is then conjectured to equal the other fold applied to its step and base: a
`:law` replayed on the probes and induced by the motif, with no search. Returns the entries
added; a second call on an unchanged library adds none."
  (unless (eq library *knowledge-library*)
    (return-from induce-fold-motifs
      (with-knowledge-library (library) (induce-fold-motifs library :ledger ledger))))
  (let ((added nil))
    (dolist (law (knowledge-entries-of-kind :law library))
      (when (usable-motif-law-p law)
        (let ((fact (law-operator-fact law)))
          (when fact (apply #'add-knowledge-edge law fact)))))
    (let* ((functions (knowledge-entries-of-kind :function library))
           (folds (remove-if-not #'fold-signature functions))
           (instances (loop for entry in functions
                            for instance = (monoid-fold-instance entry library)
                            when instance collect (cons entry instance))))
      (loop for (left . others) on folds do
        (dolist (right others)
          (let* ((tau (knowledge-entry-target left))
                 (probes (and (equal (mapcar #'cdr (knowledge-entry-inputs left))
                                     (mapcar #'cdr (knowledge-entry-inputs right)))
                              (probe-sequences-for-type (sequence-type tau))))
                 (members (remove-if-not (lambda (instance) (member (second instance) (list left right)))
                                         instances))
                 (id (keyword-id "~A=~A/MONOID" (knowledge-entry-id left) (knowledge-entry-id right))))
            (flet ((agree-p (base step)
                     (every (lambda (probe)
                              (let ((xs (lit (sequence-type tau) probe)))
                                (multiple-value-bind (a a-p)
                                    (eval-expr-value (fold-call left xs base step) nil nil ledger)
                                  (multiple-value-bind (b b-p)
                                      (eval-expr-value (fold-call right xs base step) nil nil ledger)
                                    (and a-p b-p (equal a b))))))
                            probes)))
              (when (and probes
                         (null (find-knowledge-entry id library))
                         (rest (remove-duplicates members :key #'fourth :test #'equal))
                         (every (lambda (instance) (agree-p (third instance) (fourth instance))) members))
                (destructuring-bind (sequence base step)
                    (mapcar (lambda (position)
                              (let ((input (nth position (knowledge-entry-inputs left))))
                                (var (car input) (cdr input))))
                            (fold-signature left))
                  (push (register-knowledge-entry
                         (make-knowledge-entry
                          :id id :kind :motif :inputs (knowledge-entry-inputs left) :target :bool
                          :expression (term `(= ,(fold-call left sequence base step)
                                                ,(fold-call right sequence base step)))
                          :status :conjecture
                          :edges (list (list :relates (knowledge-entry-id left) (knowledge-entry-id right))
                                       (list :requires :associative :identity))
                          :metadata (list :origin :theory-motif)
                          :library library)
                         :library library :ledger ledger)
                        added)))
              ;; Transfer: each instance equals the other fold on its own step and base.
              (when (find-knowledge-entry id library)
                (loop for (entry fold base step) in members
                      for other = (if (eq fold left) right left)
                      for inputs = (knowledge-entry-inputs entry)
                      for law-id = (keyword-id "~A/VIA-~A" (knowledge-entry-id entry) (knowledge-entry-id other))
                      do (add-knowledge-edge id :instance (knowledge-entry-id entry))
                      unless (find-knowledge-entry law-id library)
                        do (let ((validation
                                   (validate-law
                                    (make-law (infer-domain-from-types (list tau)) inputs
                                              (app (op (knowledge-entry-id entry)) (var (caar inputs) (cdar inputs)))
                                              (fold-call other (var (caar inputs) (cdar inputs)) base step)
                                              :origin (list :motif id))
                                    100000 t (mapcar #'list probes))))
                             (charge ledger :law-checking (ledger-total (law-validation-ledger validation)))
                             (when (eq :conjecture (law-validation-status validation))
                               (push (register-knowledge-law
                                      validation :id law-id :library library :ledger ledger
                                      :edges (list (list :induced-by id)))
                                     added))))))))))
    (nreverse added)))

(define-knowledge-kind :motif
  (:priority 45)
  (:validate (entry library)
    (declare (ignore library))
    (assert (eq :bool (knowledge-entry-target entry)))
    (assert-entry-expression-type entry))
  (:consolidate (entries library ledger)
    (declare (ignore entries))
    (induce-fold-motifs library :ledger ledger)))

(defun consolidate-knowledge-library (library &key synthesis-jobs observation-jobs law-validations
                                                   retype-domains library-names
                                                   (min-gain 0) (condense-heuristic-p t)
                                                   (ledger (make-ledger)))
  "Consolidate LIBRARY across accumulated synthesis jobs, law validations and registered
entries:
1. Ingest SYNTHESIS-JOBS, LAW-VALIDATIONS and OBSERVATION-JOBS.
2. Run each registered `define-knowledge-kind` `:consolidate` hook in priority order; for
   example `:function` discovers higher-order combinators with MDL gain above MIN-GAIN,
   `:relation` compresses pooled residual tables into expressions, and `:motif` quotients
   the folds whose steps share a star of laws.
3. Retype validated laws into each of RETYPE-DOMAINS, and lift to :int the solvers that
   read alike over several prime fields (`lift-field-solvers`).
4. Settle the SYNTHESIS-JOBS with the functions they lifted (`amortize-library-entries`),
   update descriptor weights and condense a priority predictor from their traces.
Without SYNTHESIS-JOBS step 4 does nothing, so consolidating an unchanged library again is
a fixed point. Returns a structured consolidation report plist."
  (let ((before-version (knowledge-library-version library))
        (ingested nil)
        (consolidated nil)
        (*consolidation-options* (list :min-gain min-gain :library-names library-names)))
    (flet ((note (kind result)
             (when result (push (cons kind result) consolidated))))
      (with-knowledge-library (library)
        (dolist (job synthesis-jobs)
          (setf ingested (append ingested (commit-synthesis-job job :library library :ledger ledger))))
        (dolist (validation law-validations)
          (push (register-knowledge-law validation :library library :ledger ledger) ingested))
        (dolist (observation observation-jobs)
          (dolist (law (propose-observed-laws observation :ledger ledger))
            (when (finite-type-p (knowledge-entry-domain law))
              (let ((validation (resume-law-validation (start-law-validation law) 100000)))
                (when (eq :validated (law-validation-status validation))
                  (push (register-knowledge-law validation :library library :ledger ledger) ingested))))))
        (dolist (spec *knowledge-kind-specs*)
          (let ((kind (knowledge-kind-spec-name spec))
                (hook (knowledge-kind-spec-consolidate-fn spec)))
            (when hook
              (note kind (funcall hook (knowledge-entries-of-kind kind library) library ledger)))))
        (dolist (domain retype-domains)
          (note :retyped-laws (retype-knowledge-laws library domain :validate-p t :ledger ledger)))
        (note :lifted-solvers (lift-field-solvers library :ledger ledger))
        (when synthesis-jobs
          (note :archived (amortize-library-entries library synthesis-jobs :ledger ledger)))
        (when (and condense-heuristic-p synthesis-jobs)
          (note :policy-descriptors (consolidate-policy-descriptors library synthesis-jobs :ledger ledger))
          (let ((trace-frame (make-search-trace-frame synthesis-jobs :ledger ledger)))
            (when (frame-rows trace-frame)
              (let ((model (nth-value 1 (condense-search-heuristic trace-frame :ledger ledger))))
                (when (and model (heuristic-program model))
                  (note :heuristic (list (register-knowledge-heuristic
                                          model :id :default-priority-predictor
                                          :library library :ledger ledger))))))))))
    (list :library library
          :before-version before-version
          :after-version (knowledge-library-version library)
          :ingested (nreverse ingested)
          :consolidated (nreverse consolidated)
          :work (ledger-total ledger))))
