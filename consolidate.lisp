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

(defun consolidate-policy-descriptors (library synthesis-jobs &key ledger)
  "Update empirical descriptor clause weights across LIBRARY from completed SYNTHESIS-JOBS
search episodes: reinforce descriptor clauses of library combinators that produced verified
root candidates, and decay empirical descriptor clauses of sibling combinators that conflicted
or failed on matching root frames."
  (let ((updated nil))
    (dolist (job synthesis-jobs (nreverse (remove-duplicates updated :test #'eq)))
      (let* ((best (synthesis-job-best job))
             (root (synthesis-job-root job))
             (root-frame (and root (synthesis-node-frame root)))
             (win-msg (and best
                           (find-if (lambda (m)
                                      (and (eq :candidate (message-claim m))
                                           (eq best (getf (message-evidence m) :candidate))))
                                    (synthesis-job-messages job))))
             (win-node (and win-msg
                            (find (message-call-id win-msg)
                                  (synthesis-job-nodes job)
                                  :key #'synthesis-node-id))))
        (when (and best root-frame)
          (dolist (node (synthesis-job-nodes job))
            (let* ((prop (synthesis-node-proposal node))
                   (pname (and prop (decomposition-name prop)))
                   (fn-name (and (consp pname)
                                 (member (first pname) '(:library :library-filter-map))
                                 (second pname)))
                   (entry (and fn-name (find-knowledge-entry fn-name library))))
              (when (and entry (knowledge-entry-descriptor-profile entry))
                (charge ledger :orientation 1)
                (flet ((sync-descriptor-weight (cid new-weight)
                         (dolist (edge (knowledge-edges-to (knowledge-entry-id entry) :describes library))
                           (let ((d (find-knowledge-entry (second edge) library)))
                             (when (and d (eq :descriptor (knowledge-entry-kind d))
                                        (eq cid (getf (knowledge-entry-metadata d) :concept)))
                               (setf (getf (knowledge-entry-metadata d) :weight-bits) new-weight))))))
                  (cond
                    ((and win-node (synthesis-descendant-p win-node node))
                     (dolist (clause (knowledge-entry-descriptor-profile entry))
                       (when (< (descriptor-clause-weight-bits clause) 12)
                         (incf (descriptor-clause-weight-bits clause))
                         (sync-descriptor-weight (descriptor-clause-id clause)
                                                 (descriptor-clause-weight-bits clause))
                         (push (knowledge-entry-id entry) updated))))
                    ((and (eq (synthesis-node-parent node) root)
                          (eq :done (synthesis-node-phase node))
                          (null (synthesis-node-search node)))
                     (dolist (clause (knowledge-entry-descriptor-profile entry))
                       (when (and (eq :empirical (descriptor-clause-status clause))
                                  (> (descriptor-clause-weight-bits clause) 1))
                         (decf (descriptor-clause-weight-bits clause))
                         (sync-descriptor-weight (descriptor-clause-id clause)
                                                 (descriptor-clause-weight-bits clause))
                         (push (knowledge-entry-id entry) updated))))))))))))))

(defun consolidate-knowledge-library (library &key synthesis-jobs observation-jobs law-validations
                                                   solve-discoveries retype-domains library-names
                                                   (min-gain 0) (condense-heuristic-p t)
                                                   (ledger (make-ledger)))
  "Consolidate LIBRARY across accumulated synthesis jobs, law validations, solver discoveries,
and registered entries:
1. Ingest SYNTHESIS-JOBS, LAW-VALIDATIONS, SOLVE-DISCOVERIES, and OBSERVATION-JOBS.
2. Run each registered `define-knowledge-kind` `:consolidate` hook in priority order; for
   example `:function` discovers higher-order combinators with MDL gain above MIN-GAIN, and
   `:relation` compresses pooled residual tables into expressions.
3. Retype validated laws into each of RETYPE-DOMAINS.
4. Update descriptor weights and condense a priority predictor from the SYNTHESIS-JOBS traces.
Returns a structured consolidation report plist."
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
        (dolist (discovery solve-discoveries)
          (push (register-knowledge-solver discovery :library library :ledger ledger) ingested))
        (dolist (observation observation-jobs)
          (dolist (law (propose-observed-laws observation :ledger ledger))
            (when (finite-type-p (law-domain law))
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
