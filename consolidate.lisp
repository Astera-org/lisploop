(in-package #:lisploop)

;;; Search-trace condensation, committing a finished job to the library, and consolidation.

(defun synthesis-episode-returns (job &key (search-weight 0) (default-baseline 1000))
  "Compute realized M8D search-episode returns `G_t = B_t - B_T - search-weight * (W_T - W_t)`."
  (let* ((w-final (ledger-total (synthesis-job-ledger job)))
         (b-final (if (synthesis-job-best job)
                      (candidate-score (synthesis-job-best job) (synthesis-job-run-weight job))
                      default-baseline)))
    (loop for entry in (reverse (synthesis-job-trace job))
          for bt = (or (getf entry :best-score) default-baseline)
          collect (append entry (list :bt bt :b-final b-final :w-final w-final
                                      :return (- (- bt b-final) (* search-weight (- w-final (getf entry :work)))))))))

(defun make-search-trace-frame (jobs-or-job &key (work-scale 64) ledger)
  "Package quantitative leaf outcomes from explored branches into an `:int` trace frame."
  (let ((jobs (if (listp jobs-or-job) jobs-or-job (list jobs-or-job)))
        (by-known (make-hash-table :test #'equal))
        ordered)
    (dolist (job jobs)
      (dolist (node (synthesis-job-nodes job))
        (let ((h (synthesis-node-heuristic node)) (frame (synthesis-node-frame node)))
          (when (and h frame)
            (let* ((known (node-trace-features node frame h))
                   (search (synthesis-node-search node))
                   (swork (if search (ledger-total (search-job-ledger search)) 0))
                   (solved-p (or (exact-heuristic-program node job) (and search (search-job-best search))))
                   (outcome (+ (first known) (* 2 (second known)) (floor swork (max 1 work-scale))
                               (if solved-p 0 10)))
                   (existing (gethash known by-known)))
              (charge ledger :orientation 1)
              (if existing
                  (setf (gethash known by-known) (min existing outcome))
                  (progn (setf (gethash known by-known) outcome) (push known ordered))))))))
    (make-frame (make-schema :domain :int :inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)) :target :int)
                (loop for k in (nreverse ordered) for idx from 0
                      collect (make-row :key idx :known (copy-list k)
                                        :requirement (singleton-requirement :int (gethash k by-known)))))))

(defun condense-search-heuristic (trace-frame &key language description-limit (work-limit 10000) ledger)
  "Condense a search-trace frame into a VM-evaluated priority predictor function and `heuristic-model`."
  (let* ((inputs (schema-inputs (frame-schema trace-frame)))
         (eff-lang (or language (make-language :int inputs :operators (list (op :+ :int) (op :* :int) (op :- :int))
                                               :literals '(0 1 2))))
         (h-model (condense-heuristic trace-frame eff-lang
                                      :description-limit (or description-limit (header-bound inputs :int 24))
                                      :work-limit work-limit :ledger ledger))
         (program (and h-model (heuristic-program h-model)))
         (pred (when program
                 (let ((fast-fn (compile-ast-fn program inputs)))
                   (lambda (node frame nlang nh)
                     (declare (ignore nlang))
                     (if (null nh) most-positive-fixnum
                         (let ((feats (node-trace-features node frame nh)))
                           (if fast-fn (let ((v (ignore-errors (funcall fast-fn feats))))
                                         (if (integerp v) v most-positive-fixnum))
                               (multiple-value-bind (v ok) (eval-expr-value program inputs feats)
                                 (if (and ok (integerp v)) v most-positive-fixnum))))))))))
    (values pred h-model)))

;;; Library kinds for nogood schemas, DIP features, and priority heuristics.

(defun register-knowledge-nogood-schema (nogood-or-expr &key id (library *knowledge-library*)
                                                             domain inputs parent-clause-expr decoder
                                                             child-id child-type parent-incompatible-p
                                                             edges metadata ledger)
  "Register a reusable UIP nogood schema (`nogood-clause` or Boolean pattern AST) in LIBRARY."
  (let* ((c (and (nogood-clause-p nogood-or-expr) nogood-or-expr))
         (cexpr (if c (nogood-clause-clause-expr c) nogood-or-expr))
         (eff-in (or inputs (infer-exprs-inputs (list cexpr))))
         (bits (multiple-value-bind (ctor scope) (compile-au-constructor cexpr eff-in ledger)
                 (description-size ctor scope))))
    (register-knowledge-entry
     (make-knowledge-entry
      :id id :kind :nogood-schema :domain (or domain :int) :inputs eff-in :target :bool
      :expression cexpr :guard (if c (nogood-clause-parent-clause-expr c) parent-clause-expr)
      :auxiliary-code (if c (nogood-clause-decoder c) decoder) :status :validated
      :certificate '(:kind :uip-anti-unification) :bits bits :edges edges
      :metadata (list* :bits-representation :au-constructor
                       :child-id (if c (nogood-clause-child-id c) child-id)
                       :child-type (if c (nogood-clause-child-type c) child-type)
                       :parent-incompatible-p (if c (nogood-clause-parent-incompatible-p c) parent-incompatible-p)
                       metadata)
      :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :nogood-schema
  (:priority 45)
  (:validate (entry library) (declare (ignore library)) (assert (knowledge-entry-expression entry)))
  (:consume (entry context ledger)
    (let ((expr (knowledge-entry-expression entry)) (inputs (knowledge-entry-inputs entry)))
      (if (pattern-has-holes-p expr)
          (evaluate (lit :bool (clause-expr-matches-known-p expr inputs context ledger)) nil nil :ledger ledger)
          (consume-entry-executable entry context ledger)))))

(defun register-knowledge-dip-feature (expr &key id (library *knowledge-library*) domain inputs target
                                              trigger edges metadata ledger)
  "Register a reusable Dual Implication Point (DIP) context separator expression in LIBRARY."
  (let ((eff-in (or inputs (infer-exprs-inputs (list expr)))))
    (register-knowledge-entry
     (make-knowledge-entry :id id :kind :dip-feature :domain domain :inputs eff-in
                           :target (or target (expression-type expr eff-in)) :expression expr
                           :trigger trigger :status :empirical :certificate '(:kind :dip-row-separator)
                           :edges edges :metadata metadata :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :dip-feature
  (:priority 50)
  (:validate (entry library) (declare (ignore library)) (assert-entry-expression-type entry)))

(defun register-knowledge-heuristic (heuristic-or-program &key id (library *knowledge-library*)
                                                            (inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
                                                            (target :int) residual edges metadata ledger)
  "Register a Stage A/M8D search priority predictor program into LIBRARY."
  (let* ((m (and (heuristic-model-p heuristic-or-program) heuristic-or-program))
         (prog (if m (heuristic-program m) heuristic-or-program))
         (res (if m (heuristic-residual m) residual)))
    (register-knowledge-entry
     (make-knowledge-entry
      :id id :kind :heuristic :domain :int :inputs inputs :target target :expression prog :residual res
      :status (if res :empirical :validated) :certificate '(:kind :trace-priority-predictor)
      :bits (if m (heuristic-program-bits m) 0) :edges edges
      :metadata (append (when m (list :residual-bits (heuristic-residual-bits m) :score (heuristic-score m))) metadata)
      :library library)
     :library library :ledger ledger)))

(define-knowledge-kind :heuristic
  (:priority 60)
  (:validate (entry library) (declare (ignore library)) (assert-entry-expression-type entry))
  (:install (entry library ledger) (declare (ignore ledger))
    (when (active-knowledge-entry-p entry)
      (setf (knowledge-library-priority-predictor library) (knowledge-entry-expression entry)))))

;;; Committing a finished job, and consolidation.

(defun job-winning-node (job)
  (let* ((best (and job (synthesis-job-best job)))
         (msg (and best (find-if (lambda (m) (and (eq :candidate (message-claim m))
                                                  (eq best (getf (message-evidence m) :candidate))))
                                 (synthesis-job-messages job)))))
    (and msg (find (message-call-id msg) (synthesis-job-nodes job) :key #'synthesis-node-id))))

(defun reactivate-existing-entry (entry library)
  (unless (active-knowledge-entry-p entry) (setf (knowledge-entry-active-p entry) t))
  (setf (knowledge-entry-last-used-epoch entry) (knowledge-library-epoch library))
  entry)

(defun commit-synthesis-job (job &key (library *knowledge-library*) name
                                   (register-residual-p t) (register-nogoods-p t) (register-dip-p t)
                                   (register-templates-p nil) ledger)
  "Commit learned artifacts from completed JOB into LIBRARY."
  (with-knowledge-library (library)
    (let* ((committed nil) (root (synthesis-job-root job)) (best (synthesis-job-best job))
           (fn-name (or name (synthesis-job-self-name job))) (kname (and fn-name (canonical-op-name fn-name))))
      (when (and best kname)
        (let ((rschema (frame-schema (synthesis-node-frame root))) (expr (candidate-expression best)))
          (define-function kname (schema-inputs rschema) (schema-target rschema) expr)
          (let ((fn-entry (find-knowledge-entry kname library)))
            (when fn-entry
              (setf (knowledge-entry-work fn-entry) (ledger-total (synthesis-job-ledger job)))
              (dolist (lfn (knowledge-library-function-names library))
                (when (and (not (eq lfn kname)) (expression-calls-operator-p expr lfn))
                  (add-knowledge-edge fn-entry :refactored-by lfn) (add-knowledge-edge lfn :abstracts kname)))
              (push fn-entry committed)))))
      (let (ng-entries)
        (when register-nogoods-p
          (dolist (ng (synthesis-job-nogoods job))
            (when (and (eq :uip-clause (nogood-clause-kind ng)) (nogood-clause-clause-expr ng))
              (let ((ex (find (nogood-clause-clause-expr ng) (knowledge-entries-of-kind :nogood-schema library)
                              :key #'knowledge-entry-expression :test #'equal)))
                (if ex (reactivate-existing-entry ex library)
                    (progn (setf ex (register-knowledge-nogood-schema ng :library library :ledger ledger))
                           (push ex committed)))
                (push ex ng-entries)))))
        (when register-dip-p
          (dolist (node (synthesis-job-nodes job))
            (let* ((prop (synthesis-node-proposal node)) (pname (and prop (decomposition-name prop)))
                   (sep (and (consp pname) (eq :dip-repair (first pname)) (third pname)))
                   (parent (synthesis-node-parent node))
                   (p-in (and parent (schema-inputs (frame-schema (synthesis-node-frame parent))))))
              (when (and sep p-in)
                (let ((ex (find-if (lambda (e) (and (equal (knowledge-entry-inputs e) p-in)
                                                    (equal (knowledge-entry-expression e) sep)))
                                   (knowledge-entries-of-kind :dip-feature library))))
                  (if ex (reactivate-existing-entry ex library)
                      (let ((de (register-knowledge-dip-feature sep :library library :inputs p-in :ledger ledger)))
                        (when kname (add-knowledge-edge de :repairs kname))
                        (dolist (nge (reverse ng-entries)) (add-knowledge-edge de :repairs (knowledge-entry-id nge)))
                        (push de committed)))))))))
      (when (and (null best) register-residual-p root)
        (let* ((rf (synthesis-node-frame root)) (rs (frame-schema rf)) (inputs (schema-inputs rs))
               (h (or (synthesis-node-heuristic root)
                      (node-stage-a-model job root rf (synthesis-node-language root) ledger))))
          (when (and h (heuristic-residual h))
            (let ((single-p (= 1 (length inputs))))
              (push (register-knowledge-relation
                     (or fn-name (next-knowledge-entry-id library :relation))
                     (loop for (rk . w) in (heuristic-residual h)
                           for row = (find rk (frame-rows rf) :key #'row-key :test #'equal)
                           when row collect (list (if single-p (first (row-known row)) (copy-list (row-known row))) w))
                     :library library :domain (schema-domain rs) :inputs inputs :target (schema-target rs)
                     :parametric (heuristic-program h) :status :empirical :ledger ledger)
                    committed)))))
      (append (nreverse committed) (when (and best register-templates-p) (remember-successful-decompositions job library ledger))))))

(defun consolidate-policy-descriptors (library synthesis-jobs &key ledger)
  "Reinforce descriptor clause weights along winning paths and decay empirical failing siblings."
  (let (updated)
    (dolist (job synthesis-jobs (nreverse (remove-duplicates updated :test #'eq)))
      (let* ((best (synthesis-job-best job)) (root (synthesis-job-root job)) (win-node (job-winning-node job)))
        (when (and best root (synthesis-node-frame root))
          (dolist (node (synthesis-job-nodes job))
            (let* ((prop (synthesis-node-proposal node)) (pname (and prop (decomposition-name prop)))
                   (fn (and (consp pname) (member (first pname) '(:library :library-filter-map)) (second pname)))
                   (entry (and fn (find-knowledge-entry fn library))))
              (when (and entry (knowledge-entry-descriptor-profile entry))
                (charge ledger :orientation 1)
                (flet ((bump (clause dir)
                         (incf (descriptor-clause-weight-bits clause) dir)
                         (let ((cid (descriptor-clause-id clause)) (nw (descriptor-clause-weight-bits clause)))
                           (dolist (edge (knowledge-edges-to (knowledge-entry-id entry) :describes library))
                             (let ((d (find-knowledge-entry (second edge) library)))
                               (when (and d (eq :descriptor (knowledge-entry-kind d))
                                          (eq cid (getf (knowledge-entry-metadata d) :concept)))
                                 (setf (getf (knowledge-entry-metadata d) :weight-bits) nw)))))
                         (push (knowledge-entry-id entry) updated)))
                  (cond ((and win-node (synthesis-descendant-p win-node node))
                         (dolist (c (knowledge-entry-descriptor-profile entry))
                           (when (< (descriptor-clause-weight-bits c) 12) (bump c 1))))
                        ((and (eq (synthesis-node-parent node) root) (eq :done (synthesis-node-phase node))
                              (null (synthesis-node-search node)))
                         (dolist (c (knowledge-entry-descriptor-profile entry))
                           (when (and (eq :empirical (descriptor-clause-status c))
                                      (> (descriptor-clause-weight-bits c) 1))
                             (bump c -1))))))))))))))

(defun knowledge-entry-net-utility (entry &optional (search-weight 1/100))
  "Compute `NetUtility(e) = sum saved-bits - search-weight * sum (dispatch-work + failed-lift-work)`."
  (let ((meta (and (knowledge-entry-p entry) (knowledge-entry-metadata entry))))
    (- (or (getf meta :saved-bits) 0)
       (* search-weight (+ (or (getf meta :dispatch-work) 0) (or (getf meta :failed-lift-work) 0))))))

(defun walk-ast-operators (ast fn)
  (when (ignore-errors (ast-kind ast))
    (cond ((and (lit-p ast) (code-type-p (ast-type ast))) (walk-ast-operators (ast-value ast) fn))
          ((operator-p ast) (when (operator-name ast) (funcall fn (operator-name ast))))
          ((app-p ast) (walk-ast-operators (first ast) fn)
                       (dolist (a (rest ast)) (walk-ast-operators a fn))))))

(defun collect-all-entry-operators (entry)
  (let (names)
    (dolist (slot (list (knowledge-entry-expression entry) (knowledge-entry-guard entry)
                        (knowledge-entry-trigger entry) (knowledge-entry-auxiliary-code entry)
                        (knowledge-entry-residual entry))
                  names)
      (walk-ast-operators slot (lambda (op) (pushnew op names :test #'eq))))))

(defun knowledge-entry-has-live-caller-p (entry library)
  (let ((eid (knowledge-entry-id entry)))
    (some (lambda (other)
            (and (not (eq other entry)) (active-knowledge-entry-p other)
                 (or (member eid (collect-all-entry-operators other) :test #'eq)
                     (some (lambda (edge)
                             (and (consp edge)
                                  (member (first edge) '(:depends-on :refactored-by :certified-by
                                                         :has-residual :lifts-inverter :normalized-by))
                                  (member eid (rest edge) :test #'eq)))
                           (knowledge-entry-edges other)))))
          (knowledge-library-entries library))))

(defun collect-proposal-library-ids (pname library &optional dip-exprs)
  (let (ids)
    (labels ((add-id (x) (when (and (symbolp x) (find-knowledge-entry x library)) (pushnew x ids :test #'eq)))
             (add-dip (expr) (when expr
                               (dolist (de (knowledge-entries-of-kind :dip-feature library))
                                 (when (equal expr (knowledge-entry-expression de))
                                   (add-id (knowledge-entry-id de))))))
             (walk-pname (p)
               (cond ((symbolp p) (add-id p))
                     ((consp p)
                      (case (first p)
                        ((:library :library-filter-map) (dolist (it (rest p)) (when (symbolp it) (add-id it))))
                        (:learned-template (add-id (second p)))
                        (:learned-template-au (dolist (tid (second p)) (add-id tid)))
                        (:dip-repair (add-dip (third p)) (walk-pname (second p)))
                        (:fallback (walk-pname (second p))))))))
      (walk-pname pname)
      (dolist (e dip-exprs ids) (add-dip e)))))

(defun accrue-consolidation-usage (library epoch synthesis-jobs usage-events search-weight)
  (labels ((update-stats (entry &key (saved 0) (dispatch 0) (failed 0) used-p)
             (when entry
               (let ((meta (copy-list (knowledge-entry-metadata entry))))
                 (when (plusp saved) (setf (getf meta :saved-bits) (+ (or (getf meta :saved-bits) 0) saved)))
                 (when (plusp dispatch) (setf (getf meta :dispatch-work) (+ (or (getf meta :dispatch-work) 0) dispatch)))
                 (when (plusp failed) (setf (getf meta :failed-lift-work) (+ (or (getf meta :failed-lift-work) 0) failed)))
                 (when (or used-p (plusp saved)) (setf (knowledge-entry-last-used-epoch entry) epoch))
                 (setf (knowledge-entry-metadata entry) meta
                       (getf (knowledge-entry-metadata entry) :net-utility)
                       (knowledge-entry-net-utility entry search-weight))))))
    (dolist (job synthesis-jobs)
      (let* ((best (synthesis-job-best job)) (root (synthesis-job-root job))
             (root-h (and root (synthesis-node-heuristic root))) (win-node (job-winning-node job))
             (win-ancs (when win-node (loop for cur = win-node then (synthesis-node-parent cur) while cur collect cur)))
             winning-ids
             (saved (when best (max 1 (- (or (and root-h (heuristic-score root-h))
                                             (and root (synthesis-node-bound root))
                                             (+ (candidate-size best) 8))
                                         (candidate-size best))))))
        (when best
          (walk-ast-operators (candidate-expression best)
                              (lambda (name)
                                (when (find-knowledge-entry name library)
                                  (pushnew name winning-ids :test #'eq)
                                  (dolist (edge (knowledge-edges-from name :refactored-by library))
                                    (dolist (tid (rest edge)) (pushnew tid winning-ids :test #'eq))))))
          (dolist (n win-ancs)
            (when (synthesis-node-proposal n)
              (dolist (id (collect-proposal-library-ids (decomposition-name (synthesis-node-proposal n)) library))
                (pushnew id winning-ids :test #'eq))))
          (when (some (lambda (m) (and (eq :conflict (message-claim m)) (getf (message-evidence m) :reused-nogood)))
                      (synthesis-job-messages job))
            (dolist (ng (active-knowledge-entries-of-kind :nogood-schema library))
              (pushnew (knowledge-entry-id ng) winning-ids :test #'eq)))
          (dolist (id winning-ids)
            (let ((e (find-knowledge-entry id library)))
              (when (active-knowledge-entry-p e)
                (update-stats e :saved saved
                                :dispatch (if (and win-node (synthesis-node-search win-node))
                                              (ledger-total (search-job-ledger (synthesis-node-search win-node))) 1)
                                :used-p t)))))
        (dolist (node (synthesis-job-nodes job))
          (when (and (not (eq node root)) (synthesis-node-proposal node) (not (member node win-ancs :test #'eq)))
            (let ((fail-work (max 100 (if (synthesis-node-search node)
                                          (ledger-total (search-job-ledger (synthesis-node-search node))) 0))))
              (dolist (id (collect-proposal-library-ids (decomposition-name (synthesis-node-proposal node)) library))
                (unless (member id winning-ids :test #'eq)
                  (let ((e (find-knowledge-entry id library)))
                    (when (active-knowledge-entry-p e) (update-stats e :failed fail-work))))))))
        (when (synthesis-job-priority-predictor job)
          (dolist (he (active-knowledge-entries-of-kind :heuristic library))
            (when (equal (knowledge-entry-expression he) (synthesis-job-priority-predictor job))
              (if best (update-stats he :saved 1 :used-p t) (update-stats he :dispatch 100)))))))
    (dolist (ev usage-events)
      (when (consp ev)
        (let ((e (find-knowledge-entry (getf ev :id) library)))
          (when e (update-stats e :saved (or (getf ev :saved-bits) 0) :dispatch (or (getf ev :dispatch-work) 0)
                                :failed (or (getf ev :failed-lift-work) 0) :used-p (getf ev :used-p))))))))

(defun demote-stale-knowledge-entries (library epoch search-weight grace-epochs min-utility ledger)
  "Archive stale non-amortizing entries without live active callers to `:active-p nil`."
  (let (demoted heuristic-demoted-p)
    (loop
      (let (progress)
        (dolist (e (knowledge-library-entries library))
          (when (and (active-knowledge-entry-p e)
                     (>= (- epoch (knowledge-entry-last-used-epoch e)) grace-epochs)
                     (<= (knowledge-entry-net-utility e search-weight) min-utility)
                     (not (knowledge-entry-has-live-caller-p e library)))
            (charge ledger :archive 1)
            (setf (knowledge-entry-active-p e) nil
                  (getf (knowledge-entry-metadata e) :archived-epoch) epoch
                  (getf (knowledge-entry-metadata e) :net-utility) (knowledge-entry-net-utility e search-weight)
                  progress t)
            (when (eq :heuristic (knowledge-entry-kind e)) (setf heuristic-demoted-p t))
            (push (knowledge-entry-id e) demoted)))
        (dolist (d (knowledge-entries-of-kind :descriptor library))
          (when (and (active-knowledge-entry-p d) (getf (knowledge-entry-metadata d) :auto-descriptor))
            (let ((targets (loop for edge in (knowledge-edges-from d :describes library) append (rest edge))))
              (when (and targets (notany (lambda (tid) (active-knowledge-entry-p (find-knowledge-entry tid library))) targets))
                (setf (knowledge-entry-active-p d) nil
                      (getf (knowledge-entry-metadata d) :archived-epoch) epoch
                      progress t)
                (push (knowledge-entry-id d) demoted)))))
        (unless progress (return))))
    (when demoted
      (when heuristic-demoted-p
        (let ((last (car (last (active-knowledge-entries-of-kind :heuristic library)))))
          (setf (knowledge-library-priority-predictor library) (when last (knowledge-entry-expression last)))))
      (invalidate-knowledge-caches library))
    (nreverse demoted)))

(defun consolidate-knowledge-library (library &key synthesis-jobs observation-jobs law-validations
                                                   solve-discoveries usage-events retype-domains library-names
                                                   (min-gain 0) (condense-heuristic-p t)
                                                   (search-weight 1/100) (grace-epochs 3) (min-utility 0)
                                                   (demote-p t) (ledger (make-ledger)))
  "Consolidate LIBRARY across synthesis jobs, validations, solver discoveries, and registered entries."
  (let* ((workload-p (or synthesis-jobs observation-jobs law-validations solve-discoveries usage-events))
         (before-version (knowledge-library-version library))
         (before-epoch (knowledge-library-epoch library))
         (epoch (if workload-p (incf (knowledge-library-epoch library)) before-epoch))
         ingested consolidated demoted
         (*consolidation-options* (list :min-gain min-gain :library-names library-names)))
    (flet ((note (kind res) (when res (push (cons kind res) consolidated))))
      (with-knowledge-library (library)
        (dolist (job synthesis-jobs) (setf ingested (append ingested (commit-synthesis-job job :library library :ledger ledger))))
        (dolist (v law-validations) (push (register-knowledge-law v :library library :ledger ledger) ingested))
        (dolist (d solve-discoveries) (push (register-knowledge-solver d :library library :ledger ledger) ingested))
        (dolist (obs observation-jobs)
          (dolist (law (propose-observed-laws obs :ledger ledger))
            (when (finite-type-p (law-domain law))
              (let ((v (resume-law-validation (start-law-validation law) 100000)))
                (when (eq :validated (law-validation-status v))
                  (push (register-knowledge-law v :library library :ledger ledger) ingested))))))
        (when workload-p (accrue-consolidation-usage library epoch synthesis-jobs usage-events search-weight))
        (dolist (spec *knowledge-kind-specs*)
          (let ((k (knowledge-kind-spec-name spec)) (hook (knowledge-kind-spec-consolidate-fn spec)))
            (when hook (note k (funcall hook (active-knowledge-entries-of-kind k library) library ledger)))))
        (dolist (dom retype-domains) (note :retyped-laws (retype-knowledge-laws library dom :validate-p t :ledger ledger)))
        (when (and condense-heuristic-p synthesis-jobs)
          (note :policy-descriptors (consolidate-policy-descriptors library synthesis-jobs :ledger ledger))
          (let ((tf (make-search-trace-frame synthesis-jobs :ledger ledger)))
            (when (frame-rows tf)
              (let ((m (nth-value 1 (condense-search-heuristic tf :ledger ledger))))
                (when (and m (heuristic-program m))
                  (note :heuristic (list (register-knowledge-heuristic
                                          m :id :default-priority-predictor :library library :ledger ledger))))))))
        (when (and workload-p demote-p)
          (setf demoted (demote-stale-knowledge-entries library epoch search-weight grace-epochs min-utility ledger))
          (note :demoted demoted))))
    (list :library library :before-version before-version :after-version (knowledge-library-version library)
          :before-epoch before-epoch :after-epoch (knowledge-library-epoch library)
          :ingested (nreverse ingested) :consolidated (nreverse consolidated)
          :demoted demoted :work (ledger-total ledger))))
