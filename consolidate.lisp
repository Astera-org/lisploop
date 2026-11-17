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
            (let ((entry (node-library-entry node library
                                             '(:library :library-filter-map :learned-template))))
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
            (let ((entry (node-library-entry node library
                                             '(:library :library-filter-map :library-partial)))
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
            (flet ((erased (accessor)
                     (mapcar (lambda (entry)
                               (retype-expr (funcall accessor entry) (knowledge-entry-domain entry) :int))
                             entries)))
              (let* ((first-entry (first entries))
                     (field (knowledge-entry-domain first-entry))
                     (inputs (mapcar (lambda (input)
                                       (cons (car input) (retype-type (cdr input) field :int)))
                                     (knowledge-entry-inputs first-entry)))
                     (witnesses (erased #'knowledge-entry-expression))
                     (guards (erased #'knowledge-entry-guard))
                     ;; The field operator at the type it has once its field is erased.
                     (operator (ignore-errors
                                (op name (retype-type
                                          (ast-type (sexp->ast (getf (knowledge-entry-metadata first-entry)
                                                                     :operator)))
                                          field :int))))
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
                              added)))))))))))))

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
