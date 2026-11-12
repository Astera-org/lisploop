(in-package #:lisploop)

;;; Milestone 7: Boolean partition views, supplied and discovered.

;;; Partitioning, Autonomous View Discovery, and Locality (M7 & M8C)
(defstruct partition-view-proposal
  (kind :separate-parts)
  guard
  part-models
  model
  conflict
  (bits 0 :type fixnum)
  (run-work 0 :type fixnum))

(defun evaluate-guard-partition (frame guard-expr &key child-bindings ledger (budget 100000))
  "Evaluate Boolean GUARD-EXPR on every row of FRAME in the metered VM, split into
TRUE-FRAME and FALSE-FRAME (projected through CHILD-BINDINGS if supplied), and record
the occurrence-preserving `partition` via `partition-rows`.
Returns (VALUES true-frame false-frame labels partition linked-frame), where LINKED-FRAME is
FRAME carrying that partition. Only LABELS is non-nil when one side is empty, and every value
is nil when the guard fails to evaluate on some row."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (rows (frame-rows frame))
         (labels nil)
         (true-rows nil)
         (false-rows nil))
    (assert (eq :bool (expression-type guard-expr inputs)))
    (dolist (row rows)
      (let ((run (evaluate guard-expr inputs (row-known row) :ledger ledger :budget budget)))
        (unless (eq :value (evaluation-status run))
          (return-from evaluate-guard-partition (values nil nil nil nil)))
        (let ((val (not (null (evaluation-value run)))))
          (push val labels)
          (if val
              (push row true-rows)
              (push row false-rows)))))
    (setf labels (nreverse labels)
          true-rows (nreverse true-rows)
          false-rows (nreverse false-rows))
    (when (or (null true-rows) (null false-rows))
      (return-from evaluate-guard-partition (values nil nil labels nil)))
    (let* ((part (partition-rows rows labels ledger))
           (linked-frame (with-frame-linkage frame :partition part :ledger ledger))
           (raw-true (make-frame (copy-schema schema) true-rows))
           (raw-false (make-frame (copy-schema schema) false-rows))
           (true-frame (project-frame-rows raw-true child-bindings ledger))
           (false-frame (project-frame-rows raw-false child-bindings ledger)))
      (values true-frame false-frame labels part linked-frame))))

(defun solve-part-subframe (part-frame language bound work-limit &key propagation ledger)
  "Return all discovered child expressions so parent reconstruction determines cost."
  (if (and propagation (propagation-fallback propagation))
      (let ((search (start-propagation-search propagation language)))
        (resume-propagation-search search bound (remaining-work ledger work-limit))
        (charge ledger :view-child-search (ledger-total (propagation-search-ledger search)))
        (mapcar #'candidate-expression (reverse (propagation-search-results search))))
      (let ((search (start-synthesis (if propagation (propagation-frame propagation) part-frame) language bound)))
        (resume-synthesis search (remaining-work ledger work-limit))
        (charge ledger :view-child-search (ledger-total (synthesis-job-ledger search)))
        (mapcar #'candidate-expression (reverse (synthesis-job-results search))))))

(defun evaluate-model-run-work (model frame &optional ledger)
  "Verify MODEL across all rows of FRAME in the metered VM and return total runtime work W_run."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target-type (schema-target schema)))
    (loop for row in (frame-rows frame)
          sum (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
                (unless (eq :value (evaluation-status run))
                  (return-from evaluate-model-run-work nil))
                (let ((chk (check-requirement (row-requirement row) (evaluation-value run)
                                              :ledger ledger :type target-type)))
                  (unless (and (eq :value (evaluation-status chk))
                               (eq t (evaluation-value chk)))
                    (return-from evaluate-model-run-work nil)))
                (evaluation-work run)))))

(defun price-view-combinations (frame guard true-models false-models
                                bindings type ledger &key decoder child-id)
  "One reconstruction/scoring path for separate branches and shared decoders."
  (let ((best nil) (inputs (schema-inputs (frame-schema frame))))
    (dolist (yes true-models)
      (dolist (no false-models)
        (let* ((branch (term `(if ,guard
                                  ,(if bindings (instantiate yes bindings :var) yes)
                                  ,(if bindings (instantiate no bindings :var) no))))
               (model (if decoder (instantiate decoder (list (cons child-id branch)) :var) branch))
               (bits (description-size model inputs)))
          (charge ledger :construction (syntax-work model))
          (when (or (null best) (<= bits (partition-view-proposal-bits best)))
            (let ((work (evaluate-model-run-work model frame ledger)))
              (when (and work (or (null best) (< bits (partition-view-proposal-bits best))
                                  (< work (partition-view-proposal-run-work best))))
                (setf best (make-partition-view-proposal
                            :kind (if decoder :shared-decoder :separate-parts)
                            :guard guard :part-models (list yes no)
                            :model model :bits bits :run-work work))))))))
    best))

(defun %synthesize-supplied-partition-view (frame guard-expr child-language
                                          &key child-bindings child-bound (work-limit 1000000)
                                               decoder child-id child-type solver ledger)
  "Both reconstruction alternatives use the same child solver and parent scorer."
  (let* ((schema (frame-schema frame)) (target (schema-target schema)) (proposals nil) (conflicts nil))
    (multiple-value-bind (true-frame false-frame labels)
        (evaluate-guard-partition frame guard-expr :child-bindings child-bindings :ledger ledger)
      (unless (and true-frame false-frame)
        (return-from %synthesize-supplied-partition-view (values nil nil)))
      (labels ((solve-parts (yes no language type &optional outer yes-prop no-prop)
                 ;; A tentative narrowing cannot refute its retained original branch.
                 (let ((conflict (or (frame-conflict-p (or (and yes-prop (propagation-fallback yes-prop)) yes) :ledger ledger)
                                     (frame-conflict-p (or (and no-prop (propagation-fallback no-prop)) no) :ledger ledger))))
                   (if conflict
                       (push (make-partition-view-proposal :kind :conflict :guard guard-expr
                                                           :conflict conflict) conflicts)
                       (let* ((bound (or child-bound (header-bound (language-inputs language) type 48)))
                              (yes-models (solve-part-subframe yes language bound work-limit :propagation yes-prop :ledger ledger))
                              (no-models (when yes-models
                                           (solve-part-subframe no language bound work-limit :propagation no-prop :ledger ledger)))
                              (proposal (price-view-combinations frame guard-expr yes-models no-models
                                                                 child-bindings type ledger :decoder outer :child-id child-id)))
                         (when proposal (push proposal proposals)))))))
        (solve-parts true-frame false-frame child-language target)
        (when decoder
          (let* ((type (or child-type target))
                 (library (when solver (as-propagator-library solver ledger)))
                 (parents (loop for truth in '(t nil) collect
                            (make-frame (copy-schema schema)
                                        (loop for row in (frame-rows frame) for label in labels
                                              when (eq truth label) collect row))))
                 (pulled (mapcar (lambda (parent)
                                   (pullback-frame parent decoder child-id type child-bindings ledger))
                                 parents))
                 (props (mapcar (lambda (child)
                                  (when library (propagate-requirements child library ledger)))
                                pulled))
                 (children (loop for child in pulled for prop in props collect
                             (if prop (propagation-frame prop) child)))
                 (language (derive-language child-language :inputs (schema-inputs (frame-schema (first children))))))
            (solve-parts (first children) (second children) language type decoder (first props) (second props)))))
      (values (nreverse proposals) (first (nreverse conflicts))))))

(defun %discover-partition-views (frame guard-language child-language
                                 &key guard-bound child-bindings child-bound (work-limit 1000000)
                                      decoder child-id child-type solver ledger)
  "Autonomously search GUARD-LANGUAGE for Boolean view selectors on FRAME:
1. Enumerates candidate guards via `start-observation-search` and deduplicates equivalent
   partitions via `observation-bucket` (including complement symmetry G vs (not G)).
2. Prunes inconsistent view splits in O(|Omega|) via `frame-conflict-p` (recording M8C conflicts).
3. Synthesizes `:separate-parts` and `:shared-decoder` models via recursive child search and
   compares them against the unfactored `:lookup` baseline by total description size S.
Returns (VALUES best-proposal proposals conflicts)."
  (let* ((schema (frame-schema frame))
         (parent-inputs (schema-inputs schema))
         (bool-frame (unconstrained-frame frame :bool :domain (language-domain guard-language)))
         (eff-guard-bound (or guard-bound (header-bound parent-inputs :bool 48)))
         (scope (make-observation-scope bool-frame guard-language))
         (obs-job (start-observation-search scope))
         (proposals nil)
         (conflicts nil)
         (seen-partitions (make-hash-table :test #'equal)))
    (resume-observation-search obs-job eff-guard-bound (remaining-work ledger work-limit))
    (charge ledger :view-guard-search (ledger-total (observation-job-ledger obs-job)))
    ;; Include unfactored lookup baseline when available
    (when (schema-lookup-p schema)
      (handler-case
          (let* ((lookup (lookup-model frame ledger))
                 (bits (description-size lookup parent-inputs))
                 (run-work (evaluate-model-run-work lookup frame ledger)))
            (when run-work
              (push (make-partition-view-proposal
                     :kind :lookup
                     :model lookup
                     :bits bits
                     :run-work run-work)
                    proposals)))
        (error () nil)))
    ;; Inspect each distinct Boolean observation bucket (shortest guard representative)
    (dolist (bucket (reverse (observation-job-buckets obs-job)))
      (when (eq :bool (observation-bucket-type bucket))
        (let* ((vals (observation-bucket-values bucket))
               (non-trivial-p (and (member t vals) (member nil vals)))
               ;; Canonicalize complement symmetry so G and (not G) share one partition key
               (canon-vals (if (first vals) vals (mapcar #'not vals))))
          (when (and non-trivial-p (not (gethash canon-vals seen-partitions)))
            (setf (gethash canon-vals seen-partitions) t)
            (let ((guard-expr (observed-expression-expression
                               (best-by (observation-bucket-members bucket)
                                        (lambda (record)
                                          (description-size (observed-expression-expression record)
                                                            parent-inputs))))))
              (multiple-value-bind (guard-proposals conflict-prop)
                  (synthesize-supplied-partition-view
                   frame guard-expr child-language
                   :child-bindings child-bindings :child-bound child-bound :work-limit work-limit
                   :decoder decoder :child-id child-id :child-type child-type
                   :solver solver :ledger ledger)
                (when conflict-prop
                  (push conflict-prop conflicts))
                (dolist (p guard-proposals)
                  (push p proposals))))))))
    (setf proposals (nreverse proposals)
          conflicts (nreverse conflicts))
    (values (best-by proposals #'partition-view-proposal-bits #'partition-view-proposal-run-work)
            proposals conflicts)))

(defun synthesize-supplied-partition-view (frame guard-expr child-language
                                         &rest options &key (work-limit 1000000) ledger &allow-other-keys)
  "A single additional-work budget covers both branches, preparation and replay.
Returns proposals, conflict, and a status message; synchronous cutoffs retain no cursor.
OPTIONS are those of `%synthesize-supplied-partition-view`."
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger work-limit
                      (values nil nil (make-message :claim :cutoff :evidence (list :work (ledger-total ledger)))))
      (multiple-value-bind (proposals conflict)
          (apply #'%synthesize-supplied-partition-view frame guard-expr child-language
                 :ledger ledger options)
        (values proposals conflict
                (make-message :claim (if (zerop (remaining-work ledger 1)) :cutoff :proposal-results)
                              :evidence (list :work (ledger-total ledger) :scope :supplied-view)))))))

(defun discover-partition-views (frame guard-language child-language
                                &rest options &key (work-limit 1000000) ledger &allow-other-keys)
  "Share one additional-work budget across guard discovery and every child branch.
OPTIONS are those of `%discover-partition-views`."
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger work-limit
                      (values nil nil nil (make-message :claim :cutoff :evidence (list :work (ledger-total ledger)))))
      (multiple-value-bind (best proposals conflicts)
          (apply #'%discover-partition-views frame guard-language child-language
                 :ledger ledger options)
        (values best proposals conflicts
                (make-message :claim (if (zerop (remaining-work ledger 1)) :cutoff :proposal-results)
                              :evidence (list :work (ledger-total ledger) :scope :view-proposals)))))))
