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
  "Package subtree-grounded signed MDL residuals `(J_real(n) - B_MDL(n))` clamped to
`[-24, 48]` from explored branches of JOBS-OR-JOB into an ordinary `frame` over the
6-feature schema `((0 . :int) ... (5 . :int)) -> :int` so `condense-heuristic` can
induce a residual priority predictor `\\hat{\\Delta}`."
  (let* ((jobs (if (listp jobs-or-job) jobs-or-job (list jobs-or-job)))
         (inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int) (4 . :int) (5 . :int)))
         (by-known (make-hash-table :test #'equal))
         (ordered-knowns nil))
    (dolist (job jobs)
      (let ((by-id (make-hash-table :test #'eql))
            (min-win (make-hash-table :test #'eq))
            (direct-work (make-hash-table :test #'eql))
            (subtree-work (make-hash-table :test #'eq)))
        (dolist (node (synthesis-job-nodes job))
          (setf (gethash (synthesis-node-id node) by-id) node))
        ;; Propagate minimum verified candidate score upward from winning nodes to ancestors.
        (dolist (msg (synthesis-job-messages job))
          (when (eq :candidate (message-claim msg))
            (let ((cand (getf (message-evidence msg) :candidate))
                  (owner (gethash (message-call-id msg) by-id)))
              (when (and cand owner)
                (let ((score (candidate-score cand (synthesis-job-run-weight job))))
                  (loop for cur = owner then (synthesis-node-parent cur)
                        while cur
                        for prev = (gethash cur min-win)
                        when (or (null prev) (< score prev))
                          do (setf (gethash cur min-win) score)))))))
        ;; Accumulate execution work per node (from trace slices and local searches) upward.
        (let* ((chronological (reverse (synthesis-job-trace job)))
               (w-final (ledger-total (synthesis-job-ledger job))))
          (loop for (entry . rest) on chronological
                for lane = (getf entry :lane)
                for next-w = (if rest (getf (first rest) :work) w-final)
                for delta = (max 0 (- next-w (getf entry :work 0)))
                for nid = (cond ((integerp lane) lane)
                                ((and (consp lane) (eq :expand (first lane))) (second lane)))
                when nid
                  do (incf (gethash nid direct-work 0) delta)))
        (dolist (node (synthesis-job-nodes job))
          (let* ((search (synthesis-node-search node))
                 (own-work (max (gethash (synthesis-node-id node) direct-work 0)
                                (if search (ledger-total (search-job-ledger search)) 0))))
            (when (plusp own-work)
              (loop for cur = node then (synthesis-node-parent cur)
                    while cur
                    do (incf (gethash cur subtree-work 0) own-work)))))
        ;; Record signed bounded residuals B_MDL -> clamp(J_real - B_MDL, -24, 48) per branch.
        (dolist (node (synthesis-job-nodes job))
          (let ((h-model (synthesis-node-heuristic node))
                (frame (synthesis-node-frame node)))
            (when (and h-model frame)
              (let* ((known (node-full-trace-features node frame h-model))
                     (b-mdl (node-analytical-mdl job node h-model))
                     (j-win (gethash node min-win))
                     (w-sub (gethash node subtree-work 0))
                     (j-real (min (+ b-mdl 48)
                                  (+ (or j-win (+ b-mdl 24))
                                     (floor w-sub (max 1 work-scale)))))
                     (outcome (max -24 (min 48 (- j-real b-mdl))))
                     (existing (gethash known by-known)))
                (charge ledger :orientation 1)
                (if existing
                    (setf (gethash known by-known) (min existing outcome))
                    (progn
                      (setf (gethash known by-known) outcome)
                      (push known ordered-knowns)))))))))
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
         (arity (length inputs))
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
                     (let* ((full (node-full-trace-features node frame node-h-model))
                            (features (loop for i from 0 below arity
                                            collect (or (nth i full) 0))))
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
                                                            (inputs '((0 . :int) (1 . :int) (2 . :int)
                                                                      (3 . :int) (4 . :int) (5 . :int)))
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
                                   (ledger (make-ledger)))
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
        (let* ((root-schema (frame-schema (synthesis-node-frame root)))
               (self-name (synthesis-job-self-name job))
               (self-sym (and self-name (canonical-op-name self-name)))
               (raw-expr (candidate-expression best)))
          (define-function kname (schema-inputs root-schema) (schema-target root-schema)
            (if (and self-sym (not (eq kname self-sym))
                     (expression-calls-operator-p raw-expr self-sym))
                (lambda (self) (rename-function-calls raw-expr self-sym self))
                raw-expr))
          (when (and self-sym (not (eq kname self-sym)))
            (let ((placeholder (find-knowledge-entry self-sym library)))
              (when (and placeholder (null (knowledge-entry-expression placeholder)))
                (remove-knowledge-entry self-sym library))))
          (let* ((fn-entry (find-knowledge-entry kname library))
                 (expr (and fn-entry (knowledge-entry-expression fn-entry))))
            (when fn-entry
              (setf (knowledge-entry-work fn-entry)
                    (ledger-total (synthesis-job-ledger job)))
              ;; Record if the winning candidate lifted a library combinator
              (dolist (lib-fn (knowledge-library-function-names library))
                (when (and (not (eq lib-fn kname))
                           expr
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

(defun node-library-entry (node library &optional (origins '(:library)))
  "The entry of LIBRARY that NODE's proposal, one of ORIGINS, was made from: the function it
lifts or, for the origin :learned-template, the decoder template it was retrieved from; or nil."
  (let ((name (and (synthesis-node-proposal node)
                   (decomposition-name (synthesis-node-proposal node)))))
    (and (consp name)
         (member (first name) origins)
         (find-knowledge-entry (second name) library))))

(defun consolidate-policy-descriptors (library synthesis-jobs &key ledger)
  "Update empirical descriptor clause weights across LIBRARY from completed SYNTHESIS-JOBS
search episodes: reinforce descriptor clauses of the library combinators and decoder
templates that produced verified root candidates, and decay empirical descriptor clauses of
their siblings that conflicted or failed on matching root frames."
  (let ((updated nil))
    (dolist (job synthesis-jobs (nreverse (remove-duplicates updated :test #'eq)))
      (let ((root (synthesis-job-root job))
            (win-node (job-winning-node job)))
        (when (and (synthesis-job-best job) root (synthesis-node-frame root))
          (dolist (node (synthesis-job-nodes job))
            ;; A decoder template's descriptors are reinforced and decayed like a combinator's.
            (let ((entry (node-library-entry node library '(:library :learned-template))))
              (when (and entry (knowledge-entry-descriptor-profile entry))
                (charge ledger :orientation 1)
                (flet ((adjust (delta)
                         ;; Move each eligible clause's weight by DELTA in ENTRY's profile.
                         (dolist (clause (knowledge-entry-descriptor-profile entry))
                           (when (if (plusp delta)
                                     (< (descriptor-clause-weight-bits clause) 12)
                                     (and (eq :empirical (descriptor-clause-status clause))
                                          (> (descriptor-clause-weight-bits clause) 1)))
                             (incf (descriptor-clause-weight-bits clause) delta)
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
  "The active entries of LIBRARY, other than ENTRY, whose code calls the function ENTRY
defines and that are uses of it. An entry of a kind declared :passive
(`define-knowledge-kind`), a decoder template or a descriptor, only mentions the function
and does not keep it from being archived."
  (let ((name (knowledge-entry-id entry)))
    (remove-if-not
     (lambda (other)
       (and (not (eq other entry))
            (knowledge-entry-active-p other)
            (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind other))))
              (not (and spec (knowledge-kind-spec-passive-p spec))))
            (some (lambda (code) (and code (expression-calls-operator-p code name)))
                  (list (knowledge-entry-expression other)
                        (knowledge-entry-guard other)
                        (knowledge-entry-trigger other)
                        (knowledge-entry-residual other)
                        (knowledge-entry-auxiliary-code other)))))
     (knowledge-library-entries library))))

(defun node-template-functions (node library)
  "The function entries of LIBRARY that the decoder template NODE's proposal was retrieved
from depends on; nil for any other proposal."
  (let* ((name (and (synthesis-node-proposal node)
                    (decomposition-name (synthesis-node-proposal node))))
         (template (and (consp name) (eq :learned-template (first name))
                        (find-knowledge-entry (second name) library))))
    (and template
         (loop for (function-name) in (getf (knowledge-entry-metadata template) :dependencies)
               for entry = (find-knowledge-entry function-name library)
               when (and entry (eq :function (knowledge-entry-kind entry))) collect entry))))

(defun archive-dependent-templates (entry library)
  "Archive the active decoder templates of LIBRARY whose decoders call the function ENTRY,
which has just been archived: such a template could no longer be proposed, and says so by
the edge (:archived-with function). Returns the templates archived."
  (loop for template in (knowledge-entries-of-kind :decoder-template library)
        when (and (knowledge-entry-active-p template)
                  (assoc (knowledge-entry-id entry)
                         (getf (knowledge-entry-metadata template) :dependencies)))
          do (setf (getf (knowledge-entry-metadata template) :active-p) nil)
             (with-knowledge-library (library)
               (add-knowledge-edge template :archived-with (knowledge-entry-id entry)))
          and collect template))

(defun amortize-library-entries (library jobs &key (search-weight *search-weight*) ledger)
  "Settle the workload JOBS, a batch of finished synthesis jobs, with the functions of
LIBRARY that they lifted. An entry is credited the body bits a call to it saved each solution
verified under one of its lifts, or under a decoder template that calls it, and charged one
unit of work for each lift proposed plus the search every failed lift's subtree consumed, at
SEARCH-WEIGHT bits a unit. The balance accumulates in its :net-utility; :stale-epochs counts
the batches in a row that left it worse off. An entry in debt for `*archive-epochs*` such
batches, which no active entry uses, is archived: marked :active-p nil, so it stays defined
and is no longer lifted; the decoder templates that call it are archived with it. Entries
that no job lifted are untouched, so an empty batch changes nothing. Returns the entries
archived."
  (let ((accounts nil))                 ; (entry saved . work), latest first
    (flet ((account (entry)
             (or (assoc entry accounts) (first (push (list* entry 0 0) accounts))))
           (saving (entry)
             (max 0 (- (knowledge-entry-bits entry)
                       (application-overhead (op (knowledge-entry-id entry)))))))
      (dolist (job jobs)
        (let ((win-node (job-winning-node job)))
          (dolist (node (synthesis-job-nodes job))
            (let ((entry (node-library-entry node library '(:library :library-partial)))
                  (won-p (and win-node (synthesis-descendant-p win-node node))))
              (when entry
                (charge ledger :orientation)
                (if won-p
                    (progn (incf (cadr (account entry)) (saving entry))
                           (incf (cddr (account entry))))
                    (incf (cddr (account entry))
                          (1+ (loop for other in (synthesis-job-nodes job)
                                    when (and (synthesis-node-search other)
                                              (synthesis-descendant-p other node))
                                      sum (ledger-total
                                           (search-job-ledger (synthesis-node-search other))))))))
              ;; A solution found through a template is one its functions saved, too.
              (when won-p
                (dolist (function (node-template-functions node library))
                  (charge ledger :orientation)
                  (incf (cadr (account function)) (saving function)))))))))
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
            and collect entry
            and append (archive-dependent-templates entry library))))

(defun solver-application (operator position context-map inputs unknown)
  "OPERATOR applied to what a solver knows and to UNKNOWN: each argument CONTEXT-MAP lists is
the input it gives it among INPUTS, and the position, or positions, the solver inverts take
UNKNOWN, whose value for several positions is their tuple."
  (let ((positions (solver-positions position)))
    (apply #'app operator
           (loop for index below (length (second (operator-type operator)))
                 for place = (position index positions)
                 collect (cond ((null place)
                                (let ((input (nth (position (list :argument index) context-map
                                                            :test #'equal)
                                                  inputs)))
                                  (var (car input) (cdr input))))
                               ((rest positions) (term `(at ,unknown ,place)))
                               (t unknown))))))

(defparameter *lift-sample-limit* 4096
  "The most assignments on which a solver lifted from prime fields is replayed over :int.")

(defun residue-assignments (types residues)
  "Assignments to inputs of TYPES, an integer taking each of RESIDUES and a Boolean both
truth values, tuples of these taken part by part; thinned evenly to `*lift-sample-limit*`.
Nil when some type has no values to offer."
  (labels ((values-of (type)
             (cond ((eq type :int) residues)
                   ((eq type :bool) '(nil t))
                   ((tuple-type-p type)
                    (let ((parts (mapcar #'values-of (rest type))))
                      (and (every #'identity parts) (cartesian-product-lists parts)))))))
    (let ((columns (mapcar #'values-of types)))
      (when (and (every #'identity columns)
                 (<= (reduce #'* columns :key #'length) (* 64 *lift-sample-limit*)))
        (let* ((all (cartesian-product-lists columns))
               (stride (max 1 (ceiling (length all) *lift-sample-limit*))))
          (loop for assignment in all for index from 0
                when (zerop (mod index stride)) collect assignment))))))

(defun sampled-solver-validations (operator position context-map inputs witness guard residues ledger)
  "Replay over :int a solver read off prime fields, as laws the VM checks on samples built
from RESIDUES, the fields' own elements centred on zero. The witness law says that, under
GUARD, OPERATOR applied to WITNESS gives the target. The uniqueness law says that no other
value does: for an integer unknown, none at any nonzero offset in RESIDUES from the witness;
for a Boolean one, not its negation. Returns (VALUES witness-validation
uniqueness-validation), the second nil when the solver inverts several positions or an
unknown of another type; both nil when the solver's types admit no law or no samples."
  (let* ((signature (operator-type operator))
         (positions (solver-positions position))
         (unknown-type (and (null (rest positions)) (nth (first positions) (second signature))))
         (target-input (nth (position :target context-map) inputs))
         (target (var (car target-input) (cdr target-input)))
         (samples (residue-assignments (mapcar #'cdr inputs) residues)))
    (when (and samples
               (every (lambda (input) (rewrite-scope-type-p (cdr input) :int)) inputs)
               (rewrite-scope-type-p (third signature) :int))
      (flet ((validated (law samples)
               (let ((validation (validate-law law 1000000 t samples)))
                 (charge ledger :law-checking (ledger-total (law-validation-ledger validation)))
                 validation))
             (other-value-law (other extra-inputs extra-guard)
               (make-law :int (append inputs extra-inputs)
                         (term `(= ,(solver-application operator position context-map inputs other)
                                   ,target))
                         (lit :bool nil)
                         :guard (if extra-guard (bool-and guard extra-guard) guard))))
        (values
         (validated (make-law :int inputs
                              (solver-application operator position context-map inputs witness)
                              target :guard guard)
                    samples)
         (case unknown-type
           (:int (let* ((offset (var (next-child-id inputs) :int))
                        (offsets (remove 0 residues)))
                   (validated (other-value-law (term `(+ ,witness ,offset))
                                               (list (cons (ast-id offset) :int))
                                               (bool-not (term `(= ,offset 0))))
                              (let ((stride (max 1 (ceiling (* (length samples) (length offsets))
                                                            *lift-sample-limit*)))
                                    (index -1))
                                (loop for sample in samples
                                      append (loop for value in offsets
                                                   when (zerop (mod (incf index) stride))
                                                     collect (append sample (list value))))))))
           (:bool (validated (other-value-law (bool-not witness) nil nil) samples))))))))

(defun lift-field-solvers (library &key ledger)
  "Lift to :int what LIBRARY's active, witness-certified solvers say alike over several prime
fields. For each primitive operator and position that is inverted over two or more fields,
when the witnesses and the guards, read with their field erased, anti-unify without a hole,
that common reading is replayed over the integers (`sampled-solver-validations`) and, if its
witness law survives on at least two active samples, registered as a solver over :int. The
integers are not a field, so it is a conjecture and its evidence is :sampled: the witness,
and the uniqueness too when its law survives and every source solver is certified unique.
Such evidence lets the solver be proposed and its solutions replayed; it is not current
evidence, so a narrowing by it keeps the original requirement as a fallback. A reading the
samples refute, like division standing in for the inverse of multiplication, is not lifted.
An operator and position that already has an :int solver is left alone, so a second call
adds nothing. Returns the entries added."
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
            (let ((lifted-candidates
                    (mapcar (lambda (entry)
                              (ignore-errors
                               (instantiate-entry-template entry :domain :int :certify-p nil
                                                           :register-p nil :library library)))
                            entries)))
              (when (every #'knowledge-entry-p lifted-candidates)
                (let* ((first-lifted (first lifted-candidates))
                       (inputs (knowledge-entry-inputs first-lifted))
                       (witnesses (mapcar #'knowledge-entry-expression lifted-candidates))
                       (guards (mapcar #'knowledge-entry-guard lifted-candidates))
                       (operator (ignore-errors
                                  (sexp->ast (getf (knowledge-entry-metadata first-lifted) :operator))))
                       (prime (reduce #'max entries
                                      :key (lambda (entry) (second (knowledge-entry-domain entry)))))
                       (residues (loop for value from (- (floor prime 2)) to (floor prime 2)
                                       collect value)))
                  (when (and operator
                             (not (pattern-has-holes-p (anti-unify witnesses inputs ledger)))
                             (not (pattern-has-holes-p (anti-unify guards inputs ledger))))
                  (multiple-value-bind (witness-validation uniqueness-validation)
                      (sampled-solver-validations operator position context-map inputs
                                                  (first witnesses) (first guards) residues ledger)
                    (when (and witness-validation
                               (eq :conjecture (law-validation-status witness-validation))
                               (>= (law-validation-active witness-validation) 2))
                      (let* ((unique-p (and uniqueness-validation
                                            (eq :conjecture (law-validation-status uniqueness-validation))
                                            (every (lambda (entry)
                                                     (knowledge-evidence-current-p entry :uniqueness))
                                                   entries)))
                             (entry (make-knowledge-solver
                                     operator
                                     :domain :int :inputs inputs :position position
                                     :context-map context-map
                                     :witness (first witnesses) :guard (first guards)
                                     :unique-p unique-p
                                     :edges (list (cons :lifted-from (mapcar #'knowledge-entry-id entries)))
                                     :library library :ledger ledger)))
                        ;; The record of what was tested: on how many assignments, how many
                        ;; of them the guard admitted, and for what work.
                        (attest-knowledge-entry entry :sampled
                                                (if unique-p '(:witness :uniqueness) '(:witness)))
                        (setf (knowledge-entry-certificate entry)
                              (append (knowledge-entry-certificate entry)
                                      (list :assignments (law-validation-count witness-validation)
                                            :active (law-validation-active witness-validation)
                                            :work (+ (ledger-total (law-validation-ledger witness-validation))
                                                     (if uniqueness-validation
                                                         (ledger-total (law-validation-ledger
                                                                        uniqueness-validation))
                                                         0)))))
                        (push (register-knowledge-entry entry :library library :ledger ledger)
                              added))))))))))))))

;;; Theory motifs: functions refactored through one fold whose steps share a star of laws,
;;; associativity and an identity on both sides, are instances of one theory. What is found
;;; to hold of the fold for them is conjectured of every instance, those that come later
;;; included. The star rests on laws that have been tested; the conjecture is replayed.

(defun usable-motif-law-p (law)
  "True when `:law` LAW is active, unconditional, an equation, not refuted, and tested: it
carries evidence of its equivalence for what it states now, exhaustive or sampled
(`knowledge-evidence-tested-p`). A conjecture nobody has tested is not something a recorded
theory may rest on."
  (and (knowledge-entry-active-p law)
       (member (knowledge-entry-status law) '(:validated :conjecture))
       (unconstrained-requirement-p (knowledge-entry-guard law))
       (app-of-p (knowledge-entry-expression law) :=)
       (knowledge-evidence-tested-p law :equivalence)))

(defun law-operator-fact (law)
  "What `:law` LAW says of a binary operator, as the edge that records it: (:associative
name) when LAW reads (op (op a b) c) = (op a (op b c)) over three distinct variables;
(:commutative name) when it reads (op a b) = (op b a) over two; (:identity name (e) side)
when it reads (op a 'e) = a, a :right identity, or (op 'e a) = a, a :left one; nil otherwise."
  (flet ((binary-p (term &optional operator)
           (and (app-p term) (= 3 (length term)) (operator-p (first term))
                (or (null operator) (eq operator (first term))))))
    (destructuring-bind (left right) (rest (knowledge-entry-expression law))
      (loop for (from to) in (list (list left right) (list right left))
            when (binary-p from)
              do (destructuring-bind (operator a b) from
                   (cond ((and (var-p to) (equal a to) (lit-p b))
                          (return (list :identity (operator-name operator) (list (ast-value b)) :right)))
                         ((and (var-p to) (equal b to) (lit-p a))
                          (return (list :identity (operator-name operator) (list (ast-value a)) :left)))
                         ((and (var-p a) (var-p b) (not (equal a b))
                               (equal to (list operator b a)))
                          (return (list :commutative (operator-name operator))))
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
a base tau and a step code of two tau to tau in some order, and applies that step (the
kernel's own analysis of the definition lists it among the code parameters it evaluates),
the positions (sequence base step)."
  (let* ((inputs (knowledge-entry-inputs entry))
         (tau (knowledge-entry-target entry))
         (body (knowledge-entry-expression entry))
         (definition (find-function-definition (knowledge-entry-id entry)))
         (positions (loop for type in (list (sequence-type tau) tau
                                            (code-type (list (cons 0 tau) (cons 1 tau)) tau))
                          collect (position type inputs :key #'cdr :test #'equal))))
    (and (knowledge-entry-active-p entry)
         (= 3 (length inputs))
         (notany #'null positions)
         body
         (expression-calls-operator-p body (knowledge-entry-id entry))
         definition
         (member (third positions) (function-definition-conditional-code-params definition))
         positions)))

(defun fold-call (fold sequence base step)
  "The call of the fold entry FOLD on the expressions SEQUENCE, BASE and STEP."
  (let ((arguments (make-list 3)))
    (loop for position in (fold-signature fold)
          for argument in (list sequence base step)
          do (setf (nth position arguments) argument))
    (apply #'app (op (knowledge-entry-id fold)) arguments)))

(defun operator-law-facts (library tau)
  "The facts LIBRARY's usable laws over TAU state of operators, each as (fact . law)."
  (loop for law in (knowledge-entries-of-kind :law library)
        when (and (usable-motif-law-p law) (equal tau (knowledge-entry-domain law)))
          append (loop for edge in (knowledge-edges-from law nil library)
                       when (member (first edge) '(:associative :commutative :identity))
                         collect (cons edge law))))

(defun record-other-identity (library law name value side tau probes ledger)
  "LAW states that VALUE is an identity of the operator NAME on SIDE only. State the other
side as a law of its own and have it checked: exhaustively over a finite TAU, else on
PROBES, the element values the motif is replayed on. A law that survives is registered,
with the evidence its validation earned and the edge that it is `:implied-with` LAW, and
returned. One that does not is recorded as the edge (:no-identity name (value) other-side)
on LAW, so the question is asked once."
  (let* ((other (if (eq side :left) :right :left))
         (operator (op name tau))
         (a (var 0 tau))
         (unit (lit tau value)))
    (unless (member (list :no-identity name (list value) other)
                    (knowledge-edges-from law :no-identity library) :test #'equal)
      (let ((validation (validate-law
                         (make-law (knowledge-entry-domain law) (list (cons 0 tau))
                                   (if (eq other :left) (app operator unit a) (app operator a unit))
                                   a :origin (list :implied-with (knowledge-entry-id law)))
                         100000 (not (finite-type-p tau)) (mapcar #'list probes))))
        (charge ledger :law-checking (ledger-total (law-validation-ledger validation)))
        (if (member (law-validation-status validation) '(:validated :conjecture))
            (register-knowledge-law validation :library library :ledger ledger
                                    :edges (list (list :implied-with (knowledge-entry-id law))))
            (progn (add-knowledge-edge law :no-identity name (list value) other)
                   nil))))))

(defun monoid-fold-instance (entry library)
  "When active `:function` ENTRY of one sequence input is refactored through a fold as
(fold X 'e '(op X0 X1)), in either order of the step's arguments, and LIBRARY's tested laws
make op associative with e its identity on both sides (stated on each, or on one of a
commutative op), returns (fold-entry base step)."
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
                          (operator (and (app-p code) (operator-p (first code)) (first code)))
                          (facts (and operator (mapcar #'car (operator-law-facts library tau)))))
                     (flet ((fact-p (&rest fact) (member fact facts :test #'equal)))
                       (when (and operator
                                  (equal sequence (var (caar inputs) (cdar inputs)))
                                  (lit-p base)
                                  (or (equal (rest code) (list (var 0 tau) (var 1 tau)))
                                      (equal (rest code) (list (var 1 tau) (var 0 tau))))
                                  (fact-p :associative (operator-name operator))
                                  (let ((unit (list (ast-value base)))
                                        (name (operator-name operator)))
                                    (or (and (fact-p :identity name unit :left)
                                             (fact-p :identity name unit :right))
                                        (and (fact-p :commutative name)
                                             (or (fact-p :identity name unit :left)
                                                 (fact-p :identity name unit :right))))))
                         (return (list fold base step))))))))))

(defun induce-fold-motifs (library &key ledger)
  "Quotient the monoid folds of LIBRARY. Each tested, unconditional law that states an
operator's associativity, commutativity or identity gets the edge saying so
(`law-operator-fact`), and an identity stated on one side of an operator that is not known
to commute has its other side put to the test as a law (`record-other-identity`). Where the
instances of two folds of one signature (`monoid-fold-instance`) cover two or more
operators and each instance's step and base give both folds the same value on every probe
sequence, the equation of the two folds is registered as a `:motif` over the first fold's
inputs. Every instance of a motif's folds is then conjectured to equal the other fold
applied to its step and base: a `:law` replayed on the probes and induced by the motif,
with no search, beside which the decoder it licenses is kept as a `:decoder-template`
(`remember-motif-decoder`). Returns the entries added; a second call on an unchanged
library adds none."
  (unless (eq library *knowledge-library*)
    (return-from induce-fold-motifs
      (with-knowledge-library (library) (induce-fold-motifs library :ledger ledger))))
  (let ((added nil))
    (dolist (law (knowledge-entries-of-kind :law library))
      (when (usable-motif-law-p law)
        (let ((fact (law-operator-fact law)))
          (when fact (apply #'add-knowledge-edge law fact)))))
    (let* ((functions (knowledge-entries-of-kind :function library))
           (folds (remove-if-not #'fold-signature functions)))
      ;; An identity known on one side only: ask about the other, once, as a law.
      (dolist (tau (remove-duplicates (mapcar #'knowledge-entry-target folds) :test #'equal))
        (let ((facts (operator-law-facts library tau))
              (probes (remove-duplicates
                       (apply #'append (probe-sequences-for-type (sequence-type tau)))
                       :test #'equal)))
          (loop for ((kind name unit side) . law) in facts
                when (and (eq kind :identity)
                          (notany (lambda (fact)
                                    (or (equal (car fact) (list :commutative name))
                                        (equal (car fact)
                                               (list :identity name unit (if (eq side :left) :right :left)))))
                                  facts))
                  do (let ((other (record-other-identity library law name (first unit) side tau probes ledger)))
                       (when other
                         (apply #'add-knowledge-edge other (law-operator-fact other))
                         (push other added))))))
      (let ((instances (loop for entry in functions
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
                              probes))
                     (step-operator (instance) (first (ast-value (fourth instance)))))
                (when (and probes
                           (null (find-knowledge-entry id library))
                           ;; Two or more operators, however their steps order the arguments.
                           (rest (remove-duplicates members :key #'step-operator :test #'equal))
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
                        unless (or (find-knowledge-entry law-id library)
                                   (member (list :not-instance (knowledge-entry-id entry))
                                           (knowledge-edges-from id :not-instance library) :test #'equal))
                          do (let* ((sequence (var (caar inputs) (cdar inputs)))
                                    (decoder (fold-call other sequence base step))
                                    (validation
                                      (validate-law
                                       (make-law (infer-domain-from-types (list tau)) inputs
                                                 (app (op (knowledge-entry-id entry)) sequence)
                                                 decoder
                                                 :origin (list :motif id))
                                       100000 t (mapcar #'list probes))))
                               (charge ledger :law-checking (ledger-total (law-validation-ledger validation)))
                               (cond
                                 ((eq :conjecture (law-validation-status validation))
                                  (let ((law (register-knowledge-law
                                              validation :id law-id :library library :ledger ledger
                                              :edges (list (list :induced-by id)))))
                                    (add-knowledge-edge id :instance (knowledge-entry-id entry))
                                    (push law added)
                                    (let ((template (remember-motif-decoder law decoder (car (first inputs))
                                                                            :library library :ledger ledger)))
                                      (when template (push template added)))))
                                 ;; The probes refute it: the motif does not hold of this
                                 ;; function, which is recorded so it is not asked again.
                                 (t (add-knowledge-edge id :not-instance (knowledge-entry-id entry)))))))))))))
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

(defparameter *consolidation-pass-limit* 4
  "The most passes `consolidate-knowledge-library` makes over its stages in one call.")

(defun consolidate-knowledge-library (library &key synthesis-jobs observation-jobs law-validations
                                                   retype-domains library-names
                                                   (min-gain 0) (condense-heuristic-p t)
                                                   (ledger (make-ledger)))
  "Consolidate LIBRARY across accumulated synthesis jobs, law validations and registered
entries:
1. Ingest SYNTHESIS-JOBS, LAW-VALIDATIONS and OBSERVATION-JOBS.
2. Run the stages to a fixed point. The stages are each registered `define-knowledge-kind`
   `:consolidate` hook in priority order (for example `:function` discovers higher-order
   combinators with MDL gain above MIN-GAIN, `:relation` compresses pooled residual tables
   into expressions, and `:motif` quotients the folds whose steps share a star of laws),
   then the retyping of validated laws into each of RETYPE-DOMAINS, then the lifting to :int
   of the solvers that read alike over several prime fields (`lift-field-solvers`). A stage
   feeds stages on either side of it: a lifted solver is what the `:functor` hook maps
   through a combinator, and a law the `:motif` hook induces is one to retype. So the
   stages are passed over again, and in a pass a stage runs when the library has changed
   since that stage last began, its own changes included. The passes end when no stage is
   due, or after `*consolidation-pass-limit*` of them.
3. Settle the SYNTHESIS-JOBS with the functions they lifted (`amortize-library-entries`),
   update descriptor weights and condense a priority predictor from their traces.
Without SYNTHESIS-JOBS step 3 does nothing, so one call leaves a library that a second call
does not change, and that second call runs each stage once. Returns a structured
consolidation report plist; its :passes is the number of passes made and its :fixed-point-p
is false only when the limit cut them short."
  (let ((before-version (knowledge-library-version library))
        (ingested nil)
        (consolidated nil)
        (passes 0)
        (fixed-point-p nil)
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
        (let ((stages                   ; (name . thunk), in the order of a pass
                (append
                 (loop for spec in *knowledge-kind-specs*
                       for hook = (knowledge-kind-spec-consolidate-fn spec)
                       when hook
                         collect (let ((kind (knowledge-kind-spec-name spec))
                                       (hook hook))
                                   (cons kind
                                         (lambda ()
                                           (funcall hook (knowledge-entries-of-kind kind library)
                                                    library ledger)))))
                 (loop for domain in retype-domains
                       collect (let ((domain domain))
                                 (cons :retyped-laws
                                       (lambda ()
                                         (retype-knowledge-laws library domain
                                                                :validate-p t :ledger ledger)))))
                 (list (cons :lifted-solvers
                             (lambda () (lift-field-solvers library :ledger ledger))))))
              (begun (make-hash-table :test #'eq))) ; stage -> library version when it last began
          (flet ((due-p (stage)
                   (multiple-value-bind (version begun-p) (gethash stage begun)
                     (or (not begun-p) (/= version (knowledge-library-version library))))))
            (loop while (and (< passes *consolidation-pass-limit*) (some #'due-p stages))
                  do (incf passes)
                     (dolist (stage stages)
                       (when (due-p stage)
                         (setf (gethash stage begun) (knowledge-library-version library))
                         (note (car stage) (funcall (cdr stage))))))
            (setf fixed-point-p (notany #'due-p stages))))
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
                                          :inputs (schema-inputs (frame-schema trace-frame))
                                          :library library :ledger ledger))))))))))
    (list :library library
          :before-version before-version
          :after-version (knowledge-library-version library)
          :ingested (nreverse ingested)
          :consolidated (nreverse consolidated)
          :passes passes
          :fixed-point-p fixed-point-p
          :work (ledger-total ledger))))

;;; ============================================================================
;;; `:spec` Knowledge Kind, Solver Induction, Functorial Transformers & Batteries
;;; ============================================================================

(defun encode-spec-rows (inputs target rows &optional (target-kind :function))
  "Encode `((known expected) ...)` into portable S-expression literal ASTs so `:code` values
round-trip cleanly without uninterned symbols."
  (loop for (known expected) in rows
        do (assert (= (length known) (length inputs)))
           (assert (every #'value-p known (mapcar #'cdr inputs)))
           (assert (or (and (eq expected :none) (eq target-kind :solver))
                       (value-p expected target)))
        collect (list (loop for val in known
                            for (nil . ty) in inputs
                            collect (ast->sexp (lit ty val)))
                      (if (eq expected :none)
                          :none
                          (ast->sexp (lit target expected))))))

(defun spec-entry-rows (spec-entry)
  "Decode `(known expected)` rows stored in `knowledge-entry-residual` of `:spec` SPEC-ENTRY."
  (loop for (enc-known enc-exp) in (knowledge-entry-residual spec-entry)
        collect (list (mapcar (lambda (s) (ast-value (sexp->ast s))) enc-known)
                      (if (eq enc-exp :none)
                          :none
                          (ast-value (sexp->ast enc-exp))))))

(define-knowledge-kind :spec
  (:priority 5)
  (:passive t)
  (:validate (entry library)
    (declare (ignore library))
    (let ((inputs (knowledge-entry-inputs entry))
          (target (knowledge-entry-target entry))
          (tkind (getf (knowledge-entry-metadata entry) :target-kind :function)))
      (assert (valid-inputs-p inputs))
      (assert (valid-type-p target))
      (dolist (row (spec-entry-rows entry))
        (destructuring-bind (known expected) row
          (assert (= (length known) (length inputs)))
          (assert (every #'value-p known (mapcar #'cdr inputs)))
          (assert (or (and (eq expected :none) (eq tkind :solver))
                      (value-p expected target)))))))
  (:consume (entry context ledger)
    (let* ((spec-edge (first (knowledge-edges-from entry :specifies)))
           (target-id (second spec-edge))
           (target-entry (and target-id (find-knowledge-entry target-id))))
      (if target-entry
          (consume-knowledge-entry target-entry context :ledger ledger)
          (let ((hit (assoc context (spec-entry-rows entry) :test #'equal)))
            (if (and hit (not (eq :none (second hit))))
                (evaluate (lit (knowledge-entry-target entry) (second hit)) nil nil :ledger ledger)
                (make-evaluation :status :unresolved)))))))

(defun make-knowledge-spec (id inputs target rows &key domain target-id (target-kind :function)
                                                       operators literals constants
                                                       edges metadata (library *knowledge-library*))
  "Create an unregistered `:spec` `knowledge-entry` over INPUTS -> TARGET with ROWS."
  (let* ((eff-domain (or domain
                         (infer-domain-from-types (cons target (mapcar #'cdr inputs)))
                         :int))
         (enc-rows (encode-spec-rows inputs target rows target-kind))
         (eff-edges (append (when target-id
                              (list (list :specifies (canonical-op-name target-id))))
                            edges)))
    (make-knowledge-entry
     :id (canonical-op-name id)
     :kind :spec
     :domain eff-domain
     :inputs (copy-tree inputs)
     :target (copy-tree target)
     :residual enc-rows
     :status :validated
     :edges eff-edges
     :metadata (append (list :target-kind target-kind)
                       (when operators (list :operators (mapcar #'ast->sexp operators)))
                       (when literals (list :literals (copy-tree literals)))
                       (when constants (list :constants (mapcar #'ast->sexp constants)))
                       metadata)
     :library library)))

(defun register-knowledge-spec (id inputs target rows &rest keys
                                &key (library *knowledge-library*) ledger &allow-other-keys)
  "Register a `:spec` entry in LIBRARY."
  (register-knowledge-entry
   (apply #'make-knowledge-spec id inputs target rows
          (remove-keys '(:ledger) keys))
   :library library :ledger ledger))

(defun spec-entry-frame (spec-entry &key ledger)
  "Build an exact synthesis `frame` from positive `(known expected)` rows of SPEC-ENTRY."
  (declare (ignore ledger))
  (let ((inputs (knowledge-entry-inputs spec-entry))
        (target (knowledge-entry-target spec-entry))
        (pos-rows (remove-if (lambda (r) (eq :none (second r))) (spec-entry-rows spec-entry))))
    (simple-frame target inputs pos-rows)))

(defun verify-entry-against-spec (entry spec-entry &key (library *knowledge-library*) ledger)
  "Replay every row of `:spec` SPEC-ENTRY against ENTRY (`:function`, `:solver`, or `:transformer`)
on the VM, signalling an error if any example fails or fails to replay."
  (with-knowledge-library (library)
    (let* ((ent (if (knowledge-entry-p entry) entry (find-knowledge-entry entry library)))
           (id (and ent (knowledge-entry-id ent)))
           (kind (and ent (knowledge-entry-kind ent)))
           (inputs (knowledge-entry-inputs ent))
           (target (knowledge-entry-target ent)))
      (assert ent () "Missing knowledge entry ~S for spec ~S" entry (knowledge-entry-id spec-entry))
      (dolist (row (spec-entry-rows spec-entry) t)
        (destructuring-bind (known expected) row
          (ecase kind
            (:function
             (let* ((call (apply #'app (op id)
                                 (loop for val in known
                                       for (nil . ty) in inputs
                                       collect (lit ty val))))
                    (run (evaluate call nil nil :ledger ledger)))
               (assert (and (eq :value (evaluation-status run))
                            (equal expected (evaluation-value run)))
                       () "Function ~S failed spec example ~S => ~S (got ~S)"
                       id known expected (evaluation-value run))))
            (:transformer
             (let ((run (consume-knowledge-entry ent known :library library :ledger ledger)))
               (assert (and run (eq :value (evaluation-status run))
                            (equal expected (evaluation-value run)))
                       () "Transformer ~S failed spec example ~S" id known)))
            (:solver
             (let* ((meta (knowledge-entry-metadata ent))
                    (operator (sexp->ast (getf meta :operator)))
                    (pos (getf meta :position))
                    (cmap (or (getf meta :context-map) (solver-context-map operator pos)))
                    (solved (evaluate-guarded-entry ent known ledger)))
               (if (eq expected :none)
                   (assert (null solved) ()
                           "Solver ~S failed negative spec example ~S => :none (got ~S)"
                           id known solved)
                   (progn
                     (assert (and solved
                                  (eq :value (evaluation-status solved))
                                  (equal expected (evaluation-value solved)))
                             () "Solver ~S failed spec example ~S => ~S (got ~S)"
                             id known expected (and solved (evaluation-value solved)))
                     (let* ((fwd (solver-forward-expression operator pos cmap known expected))
                            (frun (evaluate fwd nil nil :ledger ledger))
                            (tpos (position :target cmap))
                            (want (nth tpos known)))
                       (assert (and (eq :value (evaluation-status frun))
                                    (equal want (evaluation-value frun)))
                               () "Solver ~S witness ~S failed forward replay on ~S"
                               id expected known))))))))))))

(defun synthesize-spec-entry (spec-entry &key (library *knowledge-library*)
                                              (bound 130) (budget 350000)
                                              (heuristic-budget 15000) (recursive-p t)
                                              expanders
                                              (ledger (make-ledger)))
  "Synthesize the `:function` specified by `:spec` SPEC-ENTRY de novo, commit it into LIBRARY,
and verify every spec row on the VM. EXPANDERS are further proposal sources for the job
(`heuristic-expander`)."
  (with-knowledge-library (library)
    (let* ((spec (if (knowledge-entry-p spec-entry) spec-entry (find-knowledge-entry spec-entry library)))
           (spec-edge (first (knowledge-edges-from spec :specifies library)))
           (fn-name (or (second spec-edge) (knowledge-entry-id spec)))
           (meta (knowledge-entry-metadata spec))
           (inputs (knowledge-entry-inputs spec))
           (domain (or (knowledge-entry-domain spec) :int))
           (ops (mapcar #'sexp->ast (getf meta :operators)))
           (lits (getf meta :literals))
           (consts (mapcar #'sexp->ast (getf meta :constants)))
           (frame (spec-entry-frame spec :ledger ledger))
           (lang (make-language domain inputs :operators ops :literals lits :constants consts))
           (job (if recursive-p
                    (start-recursive-synthesis frame lang bound
                                               :self-name fn-name
                                               :max-depth 2
                                               :heuristic-budget heuristic-budget
                                               :expanders expanders)
                    (start-heuristic-synthesis frame lang bound :max-depth 2
                                                                :expanders expanders))))
      (resume-synthesis job budget :stop-on-first t)
      (charge ledger :synthesis (ledger-total (synthesis-job-ledger job)))
      (assert (synthesis-job-best job) () "Failed to synthesize spec ~S within budget ~D" fn-name budget)
      (commit-synthesis-job job :library library :name fn-name :ledger ledger)
      (let ((fn-entry (find-knowledge-entry fn-name library)))
        (verify-entry-against-spec fn-entry spec :library library :ledger ledger)
        fn-entry))))

;;; ----------------------------------------------------------------------------
;;; Conditional & Algebraic Law Solver Induction
;;; ----------------------------------------------------------------------------

(defun synthesize-boolean-separator (frame hit-mask guard-language bound work-limit ledger)
  "Synthesize an exact Boolean expression separating `T` rows from `NIL` rows of HIT-MASK on FRAME
via observational feature + pair-predicate extraction and greedy MDL decision-list induction,
falling back to Stage A/B synthesis when no one-sided implicant exists."
  (let* ((rows (frame-rows frame))
         (row-count (length rows))
         (total-hits (count t hit-mask)))
    (when (zerop total-hits)
      (return-from synthesize-boolean-separator (lit :bool nil)))
    (when (= total-hits row-count)
      (return-from synthesize-boolean-separator (lit :bool t)))
    (let* ((inputs (schema-inputs (frame-schema frame)))
           (atomic-g-ops (remove-if (lambda (o)
                                      (and (operator-p o) (eq :if (operator-name o))))
                                    (language-operators guard-language)))
           (atomic-g-lang (derive-language guard-language :operators atomic-g-ops))
           (obs (start-observation-search (make-observation-scope frame atomic-g-lang)))
           (obs-before (ledger-total (observation-job-ledger obs)))
           (obs-bound (max bound (header-bound inputs :bool 38)))
           (obs-budget (min (floor work-limit 2) 20000))
           (dom (language-domain atomic-g-lang))
           (dom-frame (unless (eq dom :bool)
                        (probe-frame dom inputs (mapcar #'row-known rows))))
           (dom-obs (when dom-frame
                      (start-observation-search (make-observation-scope dom-frame atomic-g-lang))))
           (dom-before (if dom-obs (ledger-total (observation-job-ledger dom-obs)) 0)))
      (resume-observation-search obs obs-bound obs-budget)
      (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
      (when dom-obs
        (resume-observation-search dom-obs (header-bound inputs dom 28) (min (floor work-limit 3) 12000))
        (charge ledger :guard-search (- (ledger-total (observation-job-ledger dom-obs)) dom-before)))
      (let* ((bool-preds nil)
             (feat-buckets (loop for (id . type) in inputs
                                 for pos from 0
                                 for vals = (mapcar (lambda (r) (nth pos (row-known r))) rows)
                                 unless (member :unresolved vals)
                                   collect (cons (var id type) vals))))
        (dolist (bucket (observation-job-buckets obs))
          (let ((vals (observation-bucket-values bucket))
                (expr (observed-expression-expression (car (last (observation-bucket-members bucket))))))
            (when (= (length vals) row-count)
              (push (cons expr vals) bool-preds))))
        (when dom-obs
          (dolist (bucket (observation-job-buckets dom-obs))
            (let ((vals (observation-bucket-values bucket))
                  (expr (observed-expression-expression (car (last (observation-bucket-members bucket))))))
              (when (= (length vals) row-count)
                (push (cons expr vals) feat-buckets)))))
        (let* ((pair-preds (feature-pair-predicates (nreverse feat-buckets) inputs row-count
                                                    54 ledger guard-language))
               (candidates (loop for (expr . vals) in (append (nreverse bool-preds) pair-preds)
                                 collect (list expr (coerce vals 'vector)
                                               (description-size expr inputs))))
               (hit-vec (coerce (mapcar (lambda (h) (not (null h))) hit-mask) 'vector))
               (all-idxs (loop for i below row-count collect i)))
          (labels ((induce-list (idxs depth)
                     (let ((pos-cnt (count-if (lambda (i) (aref hit-vec i)) idxs)))
                       (cond
                         ((zerop pos-cnt) (lit :bool nil))
                         ((= pos-cnt (length idxs)) (lit :bool t))
                         ((>= depth 5) nil)
                         (t
                          ;; 1. Exact single-predicate separator on active rows?
                          (let ((exact nil))
                            (dolist (cand candidates)
                              (destructuring-bind (expr vvec bits) cand
                                (let ((same-p t) (inv-p t))
                                  (dolist (i idxs)
                                    (let ((v (not (null (aref vvec i))))
                                          (h (aref hit-vec i)))
                                      (unless (eq v h) (setf same-p nil))
                                      (when (eq v h) (setf inv-p nil))))
                                  (when (or same-p inv-p)
                                    (let* ((ast (if same-p expr (bool-not expr)))
                                           (abits (if same-p bits (description-size ast inputs))))
                                      (when (or (null exact) (< abits (second exact)))
                                        (setf exact (list ast abits))))))))
                            (when exact
                              (return-from induce-list (first exact))))
                          ;; 2. Best one-sided implicant (`expr=t => hit=b` or `expr=nil => hit=b`).
                          (let ((best nil))
                            (dolist (cand candidates)
                              (destructuring-bind (expr vvec bits) cand
                                (let ((t-pos 0) (t-neg 0) (f-pos 0) (f-neg 0))
                                  (dolist (i idxs)
                                    (if (aref vvec i)
                                        (if (aref hit-vec i) (incf t-pos) (incf t-neg))
                                        (if (aref hit-vec i) (incf f-pos) (incf f-neg))))
                                  (flet ((consider (cov polarity branch-val)
                                           (when (and (plusp cov)
                                                      (or (null best)
                                                          (> cov (first best))
                                                          (and (= cov (first best))
                                                               (< bits (second best)))))
                                             (setf best (list cov bits expr polarity branch-val)))))
                                    (when (zerop t-neg) (consider t-pos :when-true t))
                                    (when (zerop f-neg) (consider f-pos :when-false t))
                                    (when (zerop t-pos) (consider t-neg :when-true nil))
                                    (when (zerop f-pos) (consider f-neg :when-false nil))))))
                            (when best
                              (destructuring-bind (cov bits expr polarity branch-val) best
                                (declare (ignore cov bits))
                                (let* ((vvec (second (find expr candidates :key #'first :test #'equal)))
                                       (rem (remove-if (lambda (i)
                                                         (if (eq polarity :when-true)
                                                             (not (null (aref vvec i)))
                                                             (null (aref vvec i))))
                                                       idxs))
                                       (sub (induce-list rem (1+ depth))))
                                  (when sub
                                    (if (eq polarity :when-true)
                                        (term `(if ,expr ,(lit :bool branch-val) ,sub))
                                        (term `(if ,expr ,sub ,(lit :bool branch-val))))))))))))))
            (let ((dl (induce-list all-idxs 0)))
              (when dl
                (return-from synthesize-boolean-separator dl)))))))
    ;; Fallback for non-implicant Boolean formulas (e.g. pure parity/XOR).
    (let* ((s-frame (support-frame frame hit-mask ledger))
           (s-inputs (schema-inputs (frame-schema s-frame)))
           (s-consts (remove-duplicates
                      (append (list (lit :bool t) (lit :bool nil))
                              (language-constants guard-language))
                      :test #'equal))
           (s-ops (remove-duplicates (cons (op :if :bool) (language-operators guard-language))
                                     :test #'equal))
           (s-lang (derive-language guard-language :operators s-ops :constants s-consts))
           (job (start-heuristic-synthesis s-frame s-lang
                                           (max bound (header-bound s-inputs :bool 48))
                                           :max-depth 2
                                           :additive-p nil
                                           :condense-budget (min 12000 (floor work-limit 3)))))
      (resume-synthesis job (max 1 (- work-limit 25000)) :stop-on-first t)
      (charge ledger :guard-search (ledger-total (synthesis-job-ledger job)))
      (and (synthesis-job-best job)
           (candidate-expression (synthesis-job-best job))))))

(defun default-solver-witness-language (domain inputs target)
  "Default witness search grammar for inverting an operator over DOMAIN and INPUTS -> TARGET."
  (let* ((ops (list (op :+ domain) (op :- domain) (op :* domain) (op :/ domain)))
         (seq-ops (loop for (nil . ty) in inputs
                        when (seq-type-p ty)
                          append (list (op :at ty) (op :tail (second ty)) (op :length (second ty)))))
         (tup-ops (when (tuple-type-p target) (list (op :tuple target)))))
    (make-language (if (or (eq domain :int) (gf-type-p domain)) domain :int)
                   inputs
                   :operators (remove-duplicates (append ops seq-ops tup-ops) :test #'equal)
                   :literals (if (eq domain :int) '(0 1) :all))))

(defun induce-conditional-solver (operator &key id (position :unary) domain spec
                                                witness-language guard-language
                                                (bound 70) (work-limit 60000) (guard-work-limit 120000)
                                                (unique-p t) finite-unique-p metric-p
                                                (certified-p nil certified-supplied-p)
                                                edges metadata
                                                (library *knowledge-library*) (ledger (make-ledger)))
  "Induce a `:solver` entry (witness, uniqueness/exception guard, and optional domain guard)
for OPERATOR at POSITION either from `:spec` SPEC (positive witness rows + `:none` rows) or
by exhaustive fiber analysis when DOMAIN and all context/target types are finite."
  (with-knowledge-library (library)
    (let* ((op-ast (cond ((operator-p operator) operator)
                         ((defined-function-p (canonical-op-name operator))
                          (op (canonical-op-name operator)))
                         (t (op (canonical-op-name operator) (or domain :int)))))
           (eff-domain (or domain
                           (and (knowledge-entry-p spec) (knowledge-entry-domain spec))
                           (infer-domain-from-types
                            (cons (third (operator-type op-ast)) (second (operator-type op-ast))))
                           :int))
           (cmap (solver-context-map op-ast position))
           (inputs (solver-context-types op-ast cmap))
           (unknowns (mapcar (lambda (p) (nth p (second (operator-type op-ast))))
                             (solver-positions position)))
           (target (if (rest unknowns) (cons :tuple unknowns) (first unknowns)))
           (finite-p (every #'finite-type-p (cons target (mapcar #'cdr inputs))))
           (pos-rows nil)
           (multi-rows nil)
           (empty-rows nil))
      (cond
        (spec
         (let ((rows (if (knowledge-entry-p spec) (spec-entry-rows spec) spec)))
           (dolist (r rows)
             (if (eq :none (second r))
                 (push (first r) empty-rows)
                 (push r pos-rows)))
           (setf pos-rows (nreverse pos-rows)
                 empty-rows (nreverse empty-rows))))
        (t
         (assert finite-p () "induce-conditional-solver requires SPEC on infinite types ~S" inputs)
         (let ((ctx-count (finite-type-cardinality (inputs-tuple-type inputs)))
               (tgt-count (finite-type-cardinality target))
               (tpos (position :target cmap)))
           (dotimes (ci ctx-count)
             (let* ((ctx (law-assignment inputs ci))
                    (want (nth tpos ctx))
                    (hits nil))
               (dotimes (ti tgt-count)
                 (let* ((cand (unrank-finite-value target ti))
                        (fwd (solver-forward-expression op-ast position cmap ctx cand))
                        (run (evaluate fwd nil nil :ledger ledger)))
                   (when (and (eq :value (evaluation-status run))
                              (equal want (evaluation-value run)))
                     (push cand hits))))
               (cond ((null hits) (push ctx empty-rows))
                     ((null (rest hits)) (push (list ctx (first hits)) pos-rows))
                     (t (push ctx multi-rows)))))
           (setf pos-rows (nreverse pos-rows)
                 multi-rows (nreverse multi-rows)
                 empty-rows (nreverse empty-rows)))))
      (assert pos-rows () "No solvable unique fibers for ~S at ~S" op-ast position)
      (let* ((w-frame (simple-frame target inputs pos-rows))
             (w-lang (or witness-language (default-solver-witness-language eff-domain inputs target)))
             (w-bound (max bound (header-bound inputs target 52)))
             (w-job (start-search w-frame w-lang))
             (_ (resume-search w-job w-bound work-limit))
             (_2 (charge ledger :synthesis (ledger-total (search-job-ledger w-job))))
             (best-w (search-job-best w-job)))
        (declare (ignore _ _2))
        (assert best-w () "Failed to synthesize witness for ~S at ~S" op-ast position)
        (let* ((witness (candidate-expression best-w))
               (neg-knowns (append multi-rows empty-rows))
               (all-rows (append (mapcar #'first pos-rows) neg-knowns))
               (all-frame (probe-frame :bool inputs all-rows))
               (g-lang (or guard-language (default-guard-language all-frame w-lang)))
               (g-bound (header-bound inputs :bool 40))
               (guard (if (null neg-knowns)
                          (lit :bool t)
                          (synthesize-boolean-separator
                           all-frame
                           (append (make-list (length pos-rows) :initial-element t)
                                   (make-list (length neg-knowns) :initial-element nil))
                           g-lang g-bound guard-work-limit ledger)))
               (domain-guard
                 (when (and multi-rows empty-rows)
                   (synthesize-boolean-separator
                    all-frame
                    (append (make-list (+ (length pos-rows) (length multi-rows)) :initial-element t)
                            (make-list (length empty-rows) :initial-element nil))
                    g-lang g-bound guard-work-limit ledger)))
                (eff-cert-p (if certified-supplied-p certified-p finite-p))
                (eff-meta (append (when finite-unique-p (list :finite-unique-p t)) metadata)))
          (assert guard () "Failed to synthesize guard for ~S at ~S" op-ast position)
          (let ((solver (register-knowledge-solver
                         op-ast
                         :id id :library library
                         :domain eff-domain :inputs inputs :target target :position position
                         :witness witness :guard guard
                         :domain-guard domain-guard
                         :certified-p eff-cert-p
                         :unique-p unique-p
                         :necessary-p (and finite-p (not (null empty-rows)))
                         :edges (append (when (knowledge-entry-p spec)
                                          (list (list :induced-from-spec (knowledge-entry-id spec))))
                                        edges)
                         :metadata eff-meta
                         :ledger ledger)))
            (when metric-p
              (register-metric-decoder solver :library library))
            (when (knowledge-entry-p spec)
              (verify-entry-against-spec solver spec :library library :ledger ledger))
            solver))))))

(defun induce-conditional-solvers (specs-or-operators &key domain (positions '(0 1))
                                                           (library *knowledge-library*)
                                                           (ledger (make-ledger)))
  "Batch-induce `:solver` entries across either a list of `:spec` entries or a list of operators
over finite DOMAIN across POSITIONS."
  (let ((added nil))
    (dolist (item specs-or-operators (nreverse added))
      (if (knowledge-entry-p item)
          (let* ((meta (knowledge-entry-metadata item))
                 (spec-edge (first (knowledge-edges-from item :specifies library)))
                 (sid (or (second spec-edge) (knowledge-entry-id item)))
                 (w-ops (and (getf meta :operators) (mapcar #'sexp->ast (getf meta :operators))))
                 (g-ops (and (getf meta :guard-operators)
                             (mapcar #'sexp->ast (getf meta :guard-operators))))
                 (lits (getf meta :literals))
                 (consts (mapcar #'sexp->ast (getf meta :constants)))
                 (inps (knowledge-entry-inputs item))
                 (dom (or (knowledge-entry-domain item) :int)))
            (push (induce-conditional-solver
                   (sexp->ast (getf meta :inverts))
                   :id sid
                   :position (getf meta :position :unary)
                   :domain dom
                   :spec item
                   :witness-language (when w-ops
                                       (make-language (if (or (eq dom :int) (gf-type-p dom)) dom :int)
                                                      inps :operators w-ops :literals (or lits '(0 1))
                                                      :constants consts))
                   :guard-language (when g-ops
                                     (default-guard-language
                                      (probe-frame :bool inps (mapcar #'first (spec-entry-rows item)))
                                      (make-language (if (or (eq dom :int) (gf-type-p dom)) dom :int)
                                                     inps :operators g-ops :literals (or lits '(0 1))
                                                     :constants consts)))
                   :unique-p (getf meta :unique-p)
                   :finite-unique-p (getf meta :finite-unique-p)
                   :metric-p (getf meta :metric-p)
                   :certified-p (getf meta :certified-p)
                   :library library :ledger ledger)
                  added))
          (dolist (pos positions)
            (push (induce-conditional-solver item :position pos :domain domain
                                                  :library library :ledger ledger)
                  added))))))

(defun solver-witness-unique-p (solver library ledger)
  "True when LIBRARY's certified laws prove the witness W(k, c) of SOLVER, which inverts one
argument of an operator, the only solution: they rewrite W(k, (op k z)), the witness of the
operator's own value, to z. Whatever z solves (op k z) = c is then W(k, c)."
  (let* ((meta (knowledge-entry-metadata solver))
         (operator (sexp->ast (getf meta :operator)))
         (position (getf meta :position)))
    (and operator
         (null (rest (solver-positions position)))
         (multiple-value-bind (equation unknown)
             (solver-template-probe-ast operator position
                                        (or (getf meta :context-map)
                                            (solver-context-map operator position))
                                        (knowledge-entry-inputs solver)
                                        (knowledge-entry-target solver))
           (let ((round-trip (instantiate (knowledge-entry-expression solver)
                                          (list (cons (ast-id (third equation)) (second equation)))
                                          :var)))
             (some (lambda (fold-p)
                     (equal (var (car unknown) (cdr unknown))
                            (simplify-symbolic-expr round-trip :library library :ledger ledger
                                                               :fold-p fold-p)))
                   '(nil t)))))))

(defun induce-law-solvers (library &key (ledger (make-ledger)))
  "Read LIBRARY's laws as solvers, and return the solvers this adds.
A tested law `(= (op a_0 ... W ... a_n) c)`, in which c and every argument but W are distinct
variables and W is more than c itself, states that W is a witness for OP at W's place. It is
registered as a `:solver`, on the law's evidence, where LIBRARY has none for that operator,
domain and place. An involution `(= (f (f x)) x)` is the unary case.
A solver whose witness LIBRARY's certified laws prove the only solution
(`solver-witness-unique-p`) gains `:uniqueness`: on the authority of an axiom when LIBRARY
holds a trusted one, and as derived otherwise."
  (let ((induced nil))
    (flet ((witness-solver (law call c position)
             (let* ((operator (first call))
                    (arguments (rest call))
                    (witness (nth position arguments))
                    (givens (cons c (loop for argument in arguments for index from 0
                                          unless (= index position) collect argument)))
                    (domain (or (knowledge-entry-domain law) :int))
                    (certified-p (knowledge-evidence-current-p law :equivalence)))
               (when (and (every #'var-p givens)
                          (= (length givens)
                             (length (knowledge-entry-inputs law))
                             (length (remove-duplicates (mapcar #'ast-id givens))))
                          (not (equal witness c))
                          (notany (lambda (solver)
                                    (let ((meta (knowledge-entry-metadata solver)))
                                      (and (equal domain (knowledge-entry-domain solver))
                                           (eq (operator-name operator) (getf meta :operator-name))
                                           (equal (list position)
                                                  (solver-positions (getf meta :position))))))
                                  (knowledge-entries-of-kind :solver library)))
                 (let* ((mapping (solver-context-map operator position))
                        (scope (solver-context-types operator mapping))
                        (renaming (loop for item in mapping
                                        for (id . type) in scope
                                        collect (cons (ast-id (if (eq item :target)
                                                                  c
                                                                  (nth (second item) arguments)))
                                                      (var id type))))
                        (solver (make-knowledge-solver
                                 operator :library library :domain domain
                                 :inputs scope :position position
                                 :witness (instantiate witness renaming :var)
                                 :guard (instantiate (knowledge-entry-guard law) renaming :var)
                                 :unique-p nil
                                 :edges (list (list :induced-by (knowledge-entry-id law)))
                                 :ledger ledger)))
                   (attest-knowledge-entry solver (if certified-p :derived :sampled) '(:witness))
                   (when certified-p (setf (knowledge-entry-status solver) :validated))
                   (push (register-knowledge-entry solver :library library :ledger ledger)
                         induced))))))
      (dolist (law (knowledge-entries-of-kind :law library))
        (when (and (knowledge-entry-active-p law)
                   (not (eq :refuted (knowledge-entry-status law)))
                   (knowledge-evidence-tested-p law :equivalence))
          (let ((sides (rest (knowledge-entry-expression law))))
            (loop for (call c) in (list sides (reverse sides))
                  when (and (var-p c) (app-p call) (operator-p (first call)))
                    do (dotimes (position (length (rest call)))
                         (witness-solver law call c position)))))))
    (let ((method (if (find :trusted-axiom (knowledge-entries-of-kind :law library)
                            :key (lambda (law) (getf (knowledge-entry-certificate law) :method)))
                      :trusted-axiom
                      :derived)))
      (dolist (solver (knowledge-entries-of-kind :solver library))
        (when (and (knowledge-entry-active-p solver)
                   (not (knowledge-evidence-current-p solver :uniqueness))
                   (solver-witness-unique-p solver library ledger))
          (let ((witness-current-p (knowledge-evidence-current-p solver :witness)))
            (setf (getf (knowledge-entry-metadata solver) :unique-p) t)
            (attest-knowledge-entry solver method
                                    (append (when witness-current-p '(:witness)) '(:uniqueness)))
            (unless witness-current-p
              (setf (knowledge-entry-status solver) :conjecture
                    (getf (knowledge-entry-metadata solver) :certified-p) nil))
            (invalidate-knowledge-caches library)))))
    (nreverse induced)))

;;; ----------------------------------------------------------------------------
;;; Battery `.sexp` Packet Loader (`library/*.sexp`)
;;; ----------------------------------------------------------------------------

(defparameter *battery-directory*
  (merge-pathnames (make-pathname :directory '(:relative "library"))
                   (make-pathname :name nil :type nil
                                  :defaults (or *compile-file-truename* *load-truename*
                                                *default-pathname-defaults*)))
  "Directory holding auto-generated `.sexp` knowledge-library battery packets.")

(defvar *battery-packets* (make-hash-table :test #'equal)
  "Cached `.sexp` battery packets: namestring -> (write-date packet).")

(defun battery-names ()
  "The sorted keyword names of all `.sexp` battery packets in `*battery-directory*`."
  (sort (mapcar (lambda (path) (keyword-id "~:@(~A~)" (pathname-name path)))
                (directory (merge-pathnames (make-pathname :name :wild :type "sexp")
                                            *battery-directory*)))
        #'string< :key #'symbol-name))

(defun read-battery (name)
  "Read and cache the `.sexp` knowledge-library packet for battery NAME."
  (let* ((bname (canonical-op-name name))
         (path (merge-pathnames (make-pathname :name (string-downcase (symbol-name bname))
                                               :type "sexp")
                                *battery-directory*))
         (date (and (probe-file path) (file-write-date path)))
         (cached (gethash (namestring path) *battery-packets*)))
    (assert date () "No battery packet ~S at ~A" name path)
    (unless (and cached (eql date (first cached)))
      (with-open-file (stream path :direction :input)
        (with-standard-io-syntax
          (let* ((*read-eval* nil)
                 (packet (read stream nil nil)))
            (assert (and (consp packet) (eq :knowledge-library (first packet)))
                    () "Malformed battery packet at ~A" path)
            (let ((meta (getf (rest packet) :metadata)))
              (when (and meta (getf meta :battery))
                (assert (eq bname (canonical-op-name (getf meta :battery)))
                        () "Battery ~A declares name ~S, expected ~S"
                        path (getf meta :battery) bname)))
            (setf cached (list date packet)
                  (gethash (namestring path) *battery-packets*) cached)))))
    (second cached)))

(defun rename-entry-calls (entry renames)
  "Return a shallow copy of ENTRY with any non-self defined function calls in RENAMES renamed."
  (let* ((self-id (knowledge-entry-id entry))
         (active-renames (loop for (old . new) in renames
                               when (and (not (eq old new))
                                         (not (eq old self-id))
                                         (defined-function-p new))
                                 collect (cons old new))))
    (if (null active-renames)
        entry
        (let ((copy (copy-knowledge-entry entry))
              (meta (copy-list (knowledge-entry-metadata entry))))
          (flet ((rw (ast)
                   (when ast
                     (let ((cur ast))
                       (loop for (old . new) in active-renames
                             do (setf cur (rename-function-calls cur old (op new))))
                       cur))))
            (setf (knowledge-entry-expression copy) (rw (knowledge-entry-expression entry))
                  (knowledge-entry-guard copy) (rw (knowledge-entry-guard entry))
                  (knowledge-entry-trigger copy) (rw (knowledge-entry-trigger entry))
                  (knowledge-entry-auxiliary-code copy) (rw (knowledge-entry-auxiliary-code entry)))
            (when (getf meta :operator)
              (let* ((op-ast (sexp->ast (getf meta :operator)))
                     (hit (assoc (operator-name op-ast) active-renames :test #'eq)))
                (when hit
                  (setf (getf meta :operator) (ast->sexp (op (cdr hit)))
                        (getf meta :operator-name) (cdr hit)))))
            (setf (knowledge-entry-metadata copy) meta)
            copy)))))

(defun install-battery-entry-default (src-entry battery renames library ledger)
  "Install SRC-ENTRY at its default types into LIBRARY, re-certifying finite solvers."
  (let* ((renamed (rename-entry-calls src-entry renames))
         (id (knowledge-entry-id src-entry))
         (kind (knowledge-entry-kind renamed)))
    (case kind
      (:function
       (define-function id (knowledge-entry-inputs renamed) (knowledge-entry-target renamed)
         (lambda (self)
           (rename-function-calls (knowledge-entry-expression renamed) id self)))
       (let ((fn-entry (find-knowledge-entry id library)))
         (add-knowledge-edge fn-entry :from-battery battery)
         fn-entry))
      (:solver
       (let* ((meta (knowledge-entry-metadata renamed))
              (op-ast (sexp->ast (getf meta :operator)))
              (inputs (knowledge-entry-inputs renamed))
              (target (knowledge-entry-target renamed))
              (finite-p (every #'finite-type-p (cons target (mapcar #'cdr inputs))))
              (metric-edge (first (knowledge-edges-from src-entry :metric-decoder)))
              (built (if finite-p
                         (make-knowledge-solver
                          op-ast :id id :library library
                          :domain (knowledge-entry-domain renamed)
                          :inputs inputs :target target
                          :position (getf meta :position)
                          :context-map (getf meta :context-map)
                          :witness (knowledge-entry-expression renamed)
                          :guard (knowledge-entry-guard renamed)
                          :domain-guard (knowledge-entry-auxiliary-code renamed)
                          :certified-p t
                          :unique-p (if (getf meta :finite-unique-p) t (getf meta :unique-p))
                          :necessary-p (getf meta :necessary-p)
                          :edges (remove :from-battery (knowledge-entry-edges src-entry) :key #'first)
                          :ledger ledger)
                         (copy-knowledge-entry renamed)))
              (reg (register-knowledge-entry built :library library :ledger ledger)))
         (add-knowledge-edge reg :from-battery battery)
         (when metric-edge
           (register-metric-decoder reg :library library :tag-bits (fourth metric-edge)))
         reg))
      (:descriptor
       (let* ((existing (find-knowledge-entry id library))
              (c (copy-knowledge-entry renamed)))
         (when (and existing (eq :descriptor (knowledge-entry-kind existing)))
           (let* ((old-nec (getf (knowledge-entry-metadata existing) :necessary-for))
                  (new-meta (copy-list (knowledge-entry-metadata c)))
                  (merged (copy-list (getf new-meta :necessary-for))))
             (dolist (pair old-nec)
               (unless (assoc (car pair) merged :test #'eq)
                 (push pair merged)))
             (setf (getf new-meta :necessary-for) merged
                   (knowledge-entry-metadata c) new-meta
                   (knowledge-entry-edges c)
                   (remove-duplicates
                    (append (knowledge-edges-from existing :describes library)
                            (knowledge-entry-edges c))
                    :test #'equal))))
         (let ((reg (register-knowledge-entry c :library library :ledger ledger)))
           (add-knowledge-edge reg :from-battery battery)
           reg)))
      (otherwise
       (let* ((c (copy-knowledge-entry renamed))
              (reg (register-knowledge-entry c :library library :ledger ledger)))
         (add-knowledge-edge reg :from-battery battery)
         reg)))))

(defun load-battery (name &key types only (library *knowledge-library*)
                               ledger (check-examples-p t))
  "Load `.sexp` battery packet NAME into LIBRARY, optionally instantiating its type parameters
via TYPES or restricting to ONLY, verifying attached `:spec` rows at default types."
  (let* ((battery (canonical-op-name name))
         (packet (read-battery battery))
         (bmeta (getf (rest packet) :metadata))
         (parameters (getf bmeta :parameters))
         (src-lib (deserialize-knowledge-library packet :ledger ledger))
         (primary-entries
           (remove-if-not (lambda (e)
                            (and (not (eq :spec (knowledge-entry-kind e)))
                                 (or (null bmeta)
                                     (member (list :from-battery battery)
                                             (knowledge-entry-edges e) :test #'equal))))
                          (knowledge-library-entries src-lib)))
         (wanted (mapcar #'canonical-op-name only)))
    (assert (every (lambda (binding)
                     (find (symbol-name (car binding)) parameters
                           :key (lambda (p) (symbol-name (first p))) :test #'string=))
                   types)
            () "Battery ~S has parameters ~S, not ~S" name (mapcar #'first parameters) types)
    (assert (subsetp wanted (mapcar #'knowledge-entry-id primary-entries))
            () "Battery ~S has no entry ~S"
            name (set-difference wanted (mapcar #'knowledge-entry-id primary-entries)))
    (let* ((resolved-params
             (loop for (param default) in parameters
                   for given = (assoc (symbol-name param) types
                                      :key #'symbol-name :test #'string=)
                   collect (cons param (if given (cdr given) default))))
           (slugs (loop for (nil default) in parameters
                        for (nil . actual) in resolved-params
                        unless (equal actual default)
                          collect (type-slug actual)))
           (eff-domain (cdar resolved-params))
           (selected (if only
                         (remove-if-not (lambda (e) (member (knowledge-entry-id e) wanted))
                                        primary-entries)
                         primary-entries))
           (renames (loop for e in selected
                          for sid = (knowledge-entry-id e)
                          collect (cons sid (if slugs
                                                (keyword-id "~A/~{~A~^-~}" sid slugs)
                                                sid))))
           (src-fn-names (mapcar #'knowledge-entry-id
                                 (knowledge-entries-of-kind :function src-lib))))
      ;; Check intra-battery function dependencies before installing anything into LIBRARY.
      (with-knowledge-library (library)
        (dolist (e selected)
          (dolist (slot-ast (list (knowledge-entry-expression e)
                                  (knowledge-entry-guard e)
                                  (knowledge-entry-trigger e)
                                  (knowledge-entry-auxiliary-code e)))
            (when slot-ast
              (dolist (callee (collect-expression-operators slot-ast))
                (when (and (member callee src-fn-names :test #'eq)
                           (not (eq callee (knowledge-entry-id e))))
                  (assert (or (assoc callee renames :test #'eq)
                              (defined-function-p callee))
                          () "Battery entry ~S requires ~S to be loaded"
                          (knowledge-entry-id e) callee))))))
        (let ((installed-by-src (make-hash-table :test #'eq))
              (ordered (stable-sort (copy-list selected) #'<
                                    :key (lambda (e) (knowledge-kind-priority (knowledge-entry-kind e))))))
          (dolist (e ordered)
            (let* ((src-id (knowledge-entry-id e))
                   (dst-id (cdr (assoc src-id renames :test #'eq)))
                   (installed
                     (if (null slugs)
                         (install-battery-entry-default e battery renames library ledger)
                         (let* ((renamed (rename-entry-calls e renames))
                                (inst (instantiate-entry-template
                                       renamed :domain eff-domain :id dst-id
                                       :register-p t :certify-p t
                                       :library library :ledger ledger))
                                (metric-edge (first (knowledge-edges-from e :metric-decoder src-lib))))
                           (add-knowledge-edge inst :from-battery battery)
                           (when metric-edge
                             (register-metric-decoder inst :library library
                                                           :tag-bits (fourth metric-edge)))
                           inst))))
              (setf (gethash src-id installed-by-src) installed)))
          (when (and check-examples-p (null slugs))
            (dolist (spec (knowledge-entries-of-kind :spec src-lib))
              (let* ((s-edge (first (knowledge-edges-from spec :specifies src-lib)))
                     (target-id (second s-edge))
                     (inst (and target-id (gethash target-id installed-by-src))))
                (when inst
                  (verify-entry-against-spec inst spec :library library :ledger ledger)))))
          (loop for e in selected
                collect (gethash (knowledge-entry-id e) installed-by-src)))))))

;;; ----------------------------------------------------------------------------
;;; Second-Order `:functor` & `:transformer`-Driven Solver Induction
;;; ----------------------------------------------------------------------------

(defvar *cached-functor-library* nil
  "Cached isolated library of `functors.sexp` transformers `(write-date . library)`.")

(defun functor-transformer-library (library)
  "Return LIBRARY when it holds `:functor/*` transformers, or the cached `functors.sexp` library."
  (if (find-knowledge-entry :functor/map-guard-0 library)
      library
      (let* ((path (merge-pathnames (make-pathname :name "functors" :type "sexp")
                                    *battery-directory*))
             (date (and (probe-file path) (file-write-date path))))
        (when date
          (unless (and *cached-functor-library* (eql date (car *cached-functor-library*)))
            (setf *cached-functor-library*
                  (cons date (deserialize-knowledge-library (read-battery :functors)))))
          (cdr *cached-functor-library*)))))

(defun run-functor-transformer (id elem-type args tlib ledger)
  "Instantiate polymorphic `:transformer` ID at ELEM-TYPE and execute it on ARGS in the VM."
  (let* ((src (and tlib (find-knowledge-entry id tlib)))
         (inst (and src (if (eq elem-type :int)
                            src
                            (instantiate-entry-template src :domain elem-type
                                                        :register-p nil :certify-p nil
                                                        :library tlib :ledger ledger))))
         (run (and inst (evaluate-guarded-entry inst args ledger))))
    (assert (and run (eq :value (evaluation-status run)))
            () "Functor transformer ~S failed on ~S at ~S" id args elem-type)
    (evaluation-value run)))

(defun map-like-combinator-signature (fdef)
  "If FDEF is a higher-order list-mapping combinator taking `(X0 : (:seq elem))` and
`(X1 : (:code ((0 . elem)) elem))` and returning `(:seq elem)` via `function-body-length-preserving-p`,
return `(VALUES elem-type seq-type code-type)`."
  (when (and (function-definition-p fdef)
             (function-definition-body fdef)
             (= 2 (length (function-definition-inputs fdef))))
    (let* ((inps (function-definition-inputs fdef))
           (t0 (cdr (first inps)))
           (t1 (cdr (second inps)))
           (ret (function-definition-return-type fdef)))
      (when (and (seq-type-p t0)
                 (equal t0 ret)
                 (code-type-p t1)
                 (= 1 (length (code-inputs t1)))
                 (eql 0 (caar (code-inputs t1)))
                 (equal (second t0) (cdar (code-inputs t1)))
                 (equal (second t0) (code-sort t1))
                 (function-body-length-preserving-p (function-definition-name fdef)
                                                    (function-definition-body fdef)))
        (values (second t0) t0 t1)))))

(defun extract-pointwise-binary-step (src-entry elem-type seq-type)
  "If `:function` entry SRC-ENTRY has signature `((0 . seq-type) (1 . elem-type)) -> seq-type`
and applies a binary scalar operator `(op elem param)` or `(op param elem)` to each element
of `X0` with parameter `X1`, return `(VALUES op-name elem-pos param-pos)`."
  (let ((expr (knowledge-entry-expression src-entry))
        (aux (knowledge-entry-auxiliary-code src-entry))
        (v0 (var 0 elem-type))
        (v1 (var 1 elem-type)))
    (flet ((binary-step (step element parameter)
             (when (and (app-p step) (operator-p (first step)) (= 2 (length (rest step))))
               (cond ((and (equal (second step) element) (equal (third step) parameter))
                      (list (operator-name (first step)) 0 1))
                     ((and (equal (second step) parameter) (equal (third step) element))
                      (list (operator-name (first step)) 1 0))))))
      (when (and (equal (knowledge-entry-inputs src-entry)
                        (list (cons 0 seq-type) (cons 1 elem-type)))
                 (equal seq-type (knowledge-entry-target src-entry)))
        (values-list
         (or (and aux (binary-step aux v0 v1))
             (and (app-p expr) (= 2 (length (rest expr)))
                  (app-of-p (third expr) :code-subst)
                  (lit-p (second (third expr)))
                  (binary-step (ast-value (second (third expr))) v0 v1))
             (and (app-of-p expr :if)
                  (app-of-p (fourth expr) :cons)
                  (binary-step (second (fourth expr)) (term `(at ,(var 0 seq-type) 0)) v1))))))))

(defun induce-combinator-solvers (library ledger map-name elem-type seq-type src-ctype elem-solvers)
  "Register `:functor` for MAP-NAME and lift ELEM-SOLVERS through `:functor/*` VM `:transformer`s."
  (let ((functor-id (keyword-id "~A/FUNCTOR" map-name))
        (map-inputs (list (cons 0 src-ctype) (cons 1 seq-type)))
        (tlib (functor-transformer-library library))
        (induced nil))
    (assert tlib () "Functorial solver induction requires functors.sexp or :functor/* transformers")
    (labels
        ((new-p (id) (null (find-knowledge-entry id library)))
         (induce (id function esolver &rest fields)
           (push (apply #'register-knowledge-solver function
                        :id id :library library :ledger ledger
                        :unique-p (getf (knowledge-entry-metadata esolver) :unique-p t)
                        :edges (list (list :induced-by functor-id (knowledge-entry-id esolver)))
                        fields)
                 induced))
         (element-solver (operator position)
           (find-if (lambda (solver)
                      (let ((meta (knowledge-entry-metadata solver)))
                        (and (eq operator (getf meta :operator-name))
                             (eql position (getf meta :position)))))
                    elem-solvers))
         (map-inverter (esolver)
           (let* ((meta (knowledge-entry-metadata esolver))
                  (op-name (operator-name (sexp->ast (getf meta :operator))))
                  (elem-pos (getf meta :position))
                  (pattern (app (op op-name elem-type) (var 0 elem-type) (var 1 elem-type)))
                  (ewit (knowledge-entry-expression esolver))
                  (guard-tid (if (zerop elem-pos) :functor/map-guard-0 :functor/map-guard-1))
                  (inv-tid (if (zerop elem-pos) :functor/map-inverse-0 :functor/map-inverse-1))
                  (wit-tid (if (zerop elem-pos) :functor/map-witness-0 :functor/map-witness-1))
                  (guard (run-functor-transformer guard-tid elem-type (list pattern ewit) tlib ledger))
                  (inverse (run-functor-transformer inv-tid elem-type (list pattern ewit) tlib ledger))
                  (witness (run-functor-transformer wit-tid elem-type
                                                    (list (op map-name) pattern ewit) tlib ledger))
                  (id (keyword-id "~A/INVERT-~A-~D" map-name op-name elem-pos)))
             (when (new-p id)
               (induce id map-name esolver :domain elem-type :inputs map-inputs
                       :target seq-type :position 0 :witness witness :guard guard))
             (dolist (edge (knowledge-edges-from map-name :abstracts library))
               (dolist (src-fn (rest edge))
                 (refactored-inverter src-fn esolver guard inverse)))))
         (refactored-inverter (src-fn esolver guard inverse)
           (let* ((src-entry (find-knowledge-entry src-fn library))
                  (step (and src-entry
                             (= 1 (length (knowledge-entry-inputs src-entry)))
                             (knowledge-entry-auxiliary-code src-entry)))
                  (id (keyword-id "~A/INVERTER" src-fn)))
             (when (and step (new-p id))
               (let ((grun (evaluate guard map-inputs (list step nil) :ledger ledger)))
                 (when (and (eq :value (evaluation-status grun)) (evaluation-value grun))
                   (let ((irun (evaluate inverse (list (cons 0 src-ctype)) (list step) :ledger ledger)))
                     (when (eq :value (evaluation-status irun))
                       (let ((uwit (run-functor-transformer :functor/unary-map-witness elem-type
                                                            (list (op map-name) (evaluation-value irun))
                                                            tlib ledger)))
                         (induce id src-fn esolver :domain elem-type
                                 :inputs (list (cons 0 seq-type)) :target seq-type :position :unary
                                 :witness uwit)))))))))
         (pointwise-inverters (src-entry)
           (multiple-value-bind (operator elem-pos param-pos)
               (extract-pointwise-binary-step src-entry elem-type seq-type)
             (when operator
               (let* ((src-fn (knowledge-entry-id src-entry))
                      (seq-solver (element-solver operator elem-pos))
                      (seq-id (keyword-id "~A/INVERT-0" src-fn))
                      (param-solver (element-solver operator param-pos))
                      (param-id (keyword-id "~A/INVERT-1" src-fn)))
                 (when (and seq-solver (new-p seq-id))
                   (let* ((swit (run-functor-transformer :functor/pointwise-seq-witness elem-type
                                                         (list (op map-name)
                                                               (knowledge-entry-expression seq-solver))
                                                         tlib ledger))
                          (e-guard (knowledge-entry-guard seq-solver))
                          (sguard (if (member 1 (free-vars e-guard)) (lit :bool t) e-guard)))
                     (induce seq-id src-fn seq-solver :domain seq-type
                             :inputs (list (cons 0 elem-type) (cons 1 seq-type)) :target seq-type
                             :position 0 :witness swit :guard sguard)))
                 (when (and param-solver (new-p param-id))
                   (let ((pwit (run-functor-transformer :functor/pointwise-param-witness elem-type
                                                        (list (knowledge-entry-expression param-solver))
                                                        tlib ledger))
                         (pguard (run-functor-transformer :functor/pointwise-param-guard elem-type
                                                          (list (knowledge-entry-guard param-solver))
                                                          tlib ledger)))
                     (induce param-id src-fn param-solver :domain seq-type
                             :inputs (list (cons 0 seq-type) (cons 1 seq-type)) :target elem-type
                             :position 1 :witness pwit :guard pguard))))))))
      (when (new-p functor-id)
        (push (register-knowledge-entry
               (make-knowledge-entry
                :id functor-id :kind :functor :domain elem-type
                :inputs map-inputs :target seq-type
                :expression (app (op map-name) (var 1 seq-type) (var 0 src-ctype))
                :status :conjecture
                :metadata (list :origin :functor-transformer :combinator map-name)
                :edges (list (list :lifts-inverter map-name))
                :library library)
               :library library :ledger ledger)
              induced))
      (map-inverter (first elem-solvers))
      (mapc #'pointwise-inverters (knowledge-entries-of-kind :function library))
      (mapc #'map-inverter (rest elem-solvers))
      (nreverse induced))))

(defun induce-functorial-solvers (library &key (ledger (make-ledger)))
  "Induce `:functor` theories and sequence/pointwise/algebraic `:solver` entries in LIBRARY
by executing `:functor/*` `:transformer` programs in the VM and scanning `:law` entries."
  (with-knowledge-library (library)
    (let ((induced nil))
      (dolist (fn-entry (knowledge-entries-of-kind :function library))
        (let ((map-name (knowledge-entry-id fn-entry)))
          (multiple-value-bind (elem-type seq-type src-ctype)
              (map-like-combinator-signature
               (or (gethash map-name (knowledge-library-functions library))
                   (find-function-definition map-name)))
            (let ((elem-solvers
                    (and elem-type
                         (remove-if-not
                          (lambda (s)
                            (and (equal elem-type (knowledge-entry-domain s))
                                 (equal elem-type (knowledge-entry-target s))
                                 (equal (knowledge-entry-inputs s)
                                        (list (cons 0 elem-type) (cons 1 elem-type)))
                                 (member (getf (knowledge-entry-metadata s) :position) '(0 1))))
                          (knowledge-entries-of-kind :solver library)))))
              (when elem-solvers
                (setf induced
                      (nconc induced
                             (induce-combinator-solvers library ledger map-name elem-type seq-type
                                                        src-ctype elem-solvers))))))))
      (nconc induced
             (induce-law-solvers library :ledger ledger)
             (induce-solvers-from-transformers library ledger)))))

(define-knowledge-kind :functor
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry))
  (:consolidate (entries library ledger)
    (declare (ignore entries))
    (induce-functorial-solvers library :ledger ledger)))
