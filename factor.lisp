(in-package #:lisploop)

;;; Module 6: factor.lisp
;;; First-order matching, anti-unification, Hard-EM fiber inference (infer-fibers),
;;; heuristic condensation (condense-heuristic), and law corpus compression.

(defun pattern-has-holes-p (term)
  (case (ast-kind term)
    (:hole t)
    (:app (or (pattern-has-holes-p (first term))
              (some #'pattern-has-holes-p (rest term))))
    (otherwise nil)))

(defun term-sort (term inputs)
  (if (operator-p term)
      (operator-type term)
      (expression-type term inputs t)))

(defun match-pattern (pattern source &optional inputs ledger)
  "Typed first-order matching, including symbols in operator position.
Return substitutions and a success flag; NIL substitutions can be a valid match."
  (unless (equal (term-sort pattern inputs) (term-sort source inputs))
    (return-from match-pattern (values nil nil)))
  (let ((substitutions nil))
    (labels ((walk (p s)
               (charge ledger :matching)
               (cond
                 ((hole-p p)
                  (and (equal (ast-type p) (term-sort s inputs))
                       (let ((entry (assoc (ast-id p) substitutions)))
                         (if entry (equal (cdr entry) s)
                             (progn (push (cons (ast-id p) s) substitutions) t)))))
                 ((equal p s) t)
                 ((and (app-p p) (app-p s)
                       (= (length (rest p)) (length (rest s))))
                  (and (walk (first p) (first s))
                       (every #'walk (rest p) (rest s))))
                 (t nil))))
      (let ((success (walk pattern source)))
        (values (and success (nreverse substitutions)) success)))))

(defun anti-unify (sources &optional inputs ledger)
  "Aligned typed syntactic LGG. Equal disagreement tuples reuse the same hole.
An incompatible operator signature falls back to a whole-expression hole if the
result types agree. Distinct result types have no common typed AST pattern."
  (assert sources)
  (let ((disagreements (make-hash-table :test #'equal)) (next-id 0))
    (labels ((generalize (terms)
               (charge ledger :anti-unification (length terms))
               (let ((sorts (mapcar (lambda (term) (term-sort term inputs)) terms)))
                 (assert (every (lambda (sort) (equal sort (first sorts))) sorts))
                 (cond
                   ((every (lambda (term) (equal term (first terms))) terms) (first terms))
                   ((and (every #'app-p terms)
                         (let ((signatures (mapcar (lambda (term) (operator-type (first term))) terms)))
                           (every (lambda (signature) (equal signature (first signatures))) signatures)))
                    (apply #'app (generalize (mapcar #'first terms))
                           (loop for i below (length (rest (first terms))) collect
                             (generalize (mapcar (lambda (term) (nth i (rest term))) terms)))))
                   (t (or (gethash terms disagreements)
                          (setf (gethash terms disagreements)
                                (hole (prog1 next-id (incf next-id)) (first sorts)))))))))
      (let ((pattern (generalize sources)))
        (values pattern
                (mapcar (lambda (source)
                          (multiple-value-bind (substitution matched)
                              (match-pattern pattern source inputs ledger)
                            (assert matched)
                            substitution)) sources))))))

(defun compile-au-constructor (pattern scope &optional ledger)
  "A DSL program maps quoted hole fillings to the instantiated quoted expression.
Operator holes are quoted operator values, not callable host functions."
  (let ((inputs nil))
    (labels ((walk (term)
               (charge ledger :au-lowering (syntax-work term))
               (let ((type (code-type scope (term-sort term scope))))
                 (cond
                   ((hole-p term)
                    (let ((previous (assoc (ast-id term) inputs)))
                      (when previous (assert (equal (cdr previous) type)))
                      (unless previous (push (cons (ast-id term) type) inputs)))
                    (var (ast-id term) type))
                   ((not (pattern-has-holes-p term)) (lit type term))
                   (t
                    (let* ((operator-sort (term-sort (first term) scope))
                           (operator-code (code-type scope operator-sort))
                           (arguments (apply #'tuple-type
                                             (mapcar (lambda (sort) (code-type scope sort)) (second operator-sort)))))
                      (app (op :code-apply operator-code) (walk (first term))
                           (apply #'app (op :tuple arguments) (mapcar #'walk (rest term))))))))))
      (let ((model (walk pattern)))
        (charge ledger :construction (syntax-work model))
        (values model (nreverse inputs))))))

;;; Operation 2.4: Minimal-MDL Fiber Partition Search (infer-fibers)

(defstruct fiber-class
  (id 0 :type fixnum)
  requirement
  rows
  keys)

(defun unconstrained-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (eq t (ast-value expr))))

(defun tighten-same-input-requirements (frame &optional ledger (budget 10000))
  "Fold each row's requirement and enforce functional determinism:
1. Rows sharing identical non-empty `row-known` conjoin their compatible requirements.
2. When `frame` has multiple input columns and distinct full `row-known` tuples, search
   candidate single-coordinate input projections `X_i` via the metered VM and adopt the
   minimum-MDL conflict-free projection (if one exists) that narrows all buckets."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target-type (schema-target schema))
         (checker-schema (make-schema :inputs (list (cons 0 target-type)) :target :bool))
         (rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec))
         (folded-reqs (make-array n))
         (repeated-full-known-p nil))
    ;; 1. Fold closed subtrees in each row's requirement
    (loop for i below n
          for row = (aref rows-vec i)
          for folded = (fold-constants (row-requirement row) checker-schema
                                       :ledger ledger :budget budget)
          do (charge ledger :fiber-inference (syntax-work folded))
             (setf (aref folded-reqs i) folded))
    ;; 2. Exact same-input functional determinism over full `row-known`
    (let ((by-known (make-hash-table :test #'equal)))
      (loop for i below n
            for known = (row-known (aref rows-vec i))
            when known
            do (push i (gethash known by-known)))
      (maphash
       (lambda (known indices)
         (declare (ignore known))
         (when (> (length indices) 1)
           (setf repeated-full-known-p t)
           (let ((joint (aref folded-reqs (first indices))))
             (dolist (idx (rest indices))
               (unless (unsatisfiable-requirement-p joint)
                 (charge ledger :fiber-inference)
                 (setf joint (conjoin-requirements joint (aref folded-reqs idx) target-type
                                                   :ledger ledger :budget budget))))
             (unless (unsatisfiable-requirement-p joint)
               (dolist (idx indices)
                 (setf (aref folded-reqs idx) joint))))))
       by-known))
    ;; 3. Candidate sub-projection search when full `row-known` has multiple columns and no repeats
    (when (and (> (length inputs) 1) (not repeated-full-known-p) (> n 1))
      (let ((best-reqs nil)
            (best-bits most-positive-fixnum))
        (dolist (spec inputs)
          (let ((proj-expr (var (car spec) (cdr spec)))
                (by-proj (make-hash-table :test #'equal))
                (consistent-p t)
                (narrowed-any-p nil)
                (candidate-reqs (make-array n))
                (total-bits 0))
            (loop for i below n
                  for row = (aref rows-vec i)
                  for run = (evaluate proj-expr inputs (row-known row) :ledger ledger :budget budget)
                  do (if (eq :value (evaluation-status run))
                         (push i (gethash (evaluation-value run) by-proj))
                         (setf consistent-p nil)))
            (when (and consistent-p (< (hash-table-count by-proj) n))
              (maphash
               (lambda (val indices)
                 (declare (ignore val))
                 (when consistent-p
                   (let ((joint (aref folded-reqs (first indices))))
                     (dolist (idx (rest indices))
                       (unless (unsatisfiable-requirement-p joint)
                         (charge ledger :fiber-inference)
                         (setf joint (conjoin-requirements joint (aref folded-reqs idx) target-type
                                                           :ledger ledger :budget budget))))
                     (if (or (unsatisfiable-requirement-p joint)
                             (unconstrained-requirement-p joint))
                         (setf consistent-p nil)
                         (let ((bits (body-size joint (list (cons 0 target-type)))))
                           (dolist (idx indices)
                             (unless (equal joint (aref folded-reqs idx))
                               (setf narrowed-any-p t))
                             (setf (aref candidate-reqs idx) joint)
                             (incf total-bits bits)))))))
               by-proj)
              (when (and consistent-p narrowed-any-p (< total-bits best-bits))
                (setf best-reqs candidate-reqs
                      best-bits total-bits)))))
        (when best-reqs
          (setf folded-reqs best-reqs))))
    folded-reqs))

(defstruct req-group
  requirement
  indices
  (count 0 :type fixnum))

(defun infer-fibers (frame &optional ledger (budget 10000))
  "Minimal-MDL fiber partition search over ambiguous or relational row requirements:
1. Folds closed subtrees and enforces same-input functional determinism (including
   conflict-free input coordinate projection search when multiple inputs are present).
2. Deduplicates rows sharing identical satisfiable requirements into unique groups.
3. Runs bounded branch-and-bound search over compatible group partitions using
   `conjoin-requirements`, minimizing class count K, then total requirement bit-length
   S_body, then empirical label entropy (maximizing class-size concentration).
Returns (VALUES classes labels refined-frame partition)."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (target-inputs (list (cons 0 target-type)))
         (rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec))
         (folded-reqs (tighten-same-input-requirements frame ledger budget))
         (groups nil)
         (unsat-indices nil)
         (assignments (make-array n :initial-element nil)))
    ;; 1. Deduplicate satisfiable rows with identical requirements into unique groups
    (loop for i below n
          for req = (aref folded-reqs i)
          do (if (unsatisfiable-requirement-p req)
                 (push i unsat-indices)
                 (let ((existing (find req groups :key #'req-group-requirement :test #'equal)))
                   (if existing
                       (progn
                         (push i (req-group-indices existing))
                         (incf (req-group-count existing)))
                       (push (make-req-group :requirement req :indices (list i) :count 1)
                             groups)))))
    (setf groups (nreverse groups)
          unsat-indices (nreverse unsat-indices))
    (dolist (g groups)
      (setf (req-group-indices g) (nreverse (req-group-indices g))))
    ;; Order constrained groups before unconstrained `'t` groups, then by ascending body-size
    (setf groups
          (stable-sort groups
                       (lambda (g1 g2)
                         (let ((u1 (unconstrained-requirement-p (req-group-requirement g1)))
                               (u2 (unconstrained-requirement-p (req-group-requirement g2))))
                           (if (not (eq u1 u2))
                               (not u1)
                               (< (body-size (req-group-requirement g1) target-inputs)
                                  (body-size (req-group-requirement g2) target-inputs)))))))
    ;; 2. Bounded branch-and-bound search for the minimum-MDL compatible partition of `groups`
    (let ((u (length groups))
          (groups-vec (coerce groups 'vector))
          (best-classes nil)
          (best-k most-positive-fixnum)
          (best-bits most-positive-fixnum)
          (best-conc -1)
          (branches 0)
          (max-branches 2048))
      (labels ((partition-better-p (k bits conc)
                 (or (< k best-k)
                     (and (= k best-k)
                          (or (< bits best-bits)
                              (and (= bits best-bits)
                                   (> conc best-conc))))))
               (dfs (g-idx current-classes)
                 (when (> (incf branches) max-branches)
                   (return-from dfs))
                 (let ((k (length current-classes)))
                   (when (> k best-k)
                     (return-from dfs))
                   (if (= g-idx u)
                       (let ((total-bits 0)
                             (conc 0))
                         (dolist (c current-classes)
                           (let* ((c-req (first c))
                                  (c-rows (second c))
                                  (cnt (length c-rows)))
                             (incf total-bits (* cnt (body-size c-req target-inputs)))
                             (incf conc (* cnt cnt))))
                         (when (partition-better-p k total-bits conc)
                           (setf best-k k
                                 best-bits total-bits
                                 best-conc conc
                                 best-classes (mapcar (lambda (c)
                                                        (list (first c) (copy-list (second c))))
                                                      current-classes))))
                       (let* ((g (aref groups-vec g-idx))
                              (g-req (req-group-requirement g))
                              (g-rows (req-group-indices g)))
                         ;; Branch A: merge group `g` into each compatible existing class
                         (loop for pos from 0
                               for c in current-classes
                               for c-req = (first c)
                               do (charge ledger :fiber-inference)
                                  (let ((joint (conjoin-requirements c-req g-req target-type
                                                                     :ledger ledger :budget budget)))
                                    (unless (unsatisfiable-requirement-p joint)
                                      (let ((next-classes
                                              (loop for elem in current-classes
                                                    for idx from 0
                                                    collect (if (= idx pos)
                                                                (list joint (append (second elem) g-rows))
                                                                elem))))
                                        (dfs (1+ g-idx) next-classes)))))
                         ;; Branch B: nucleate a new class for group `g` (if within K bound)
                         (when (< k best-k)
                           (dfs (1+ g-idx)
                                (append current-classes
                                        (list (list g-req (copy-list g-rows)))))))))))
        (dfs 0 nil))
      ;; 3. Assemble `fiber-class` records (including any isolated unsatisfiable rows)
      (let ((classes
              (append (loop for c in best-classes
                            for idx from 0
                            collect (make-fiber-class :id idx
                                                      :requirement (first c)
                                                      :rows (second c)))
                      (loop for u-idx in unsat-indices
                            for idx from (length best-classes)
                            collect (make-fiber-class :id idx
                                                      :requirement (aref folded-reqs u-idx)
                                                      :rows (list u-idx))))))
        ;; Canonicalize class ordering and IDs by first-appearance row index in FRAME
        (setf classes (sort classes #'< :key (lambda (c) (reduce #'min (fiber-class-rows c)))))
        (loop for class in classes
              for new-id from 0
              do (setf (fiber-class-id class) new-id
                       (fiber-class-rows class) (sort (copy-list (fiber-class-rows class)) #'<)
                       (fiber-class-keys class) (mapcar (lambda (i) (row-key (aref rows-vec i)))
                                                        (fiber-class-rows class)))
                 (dolist (r-idx (fiber-class-rows class))
                   (setf (aref assignments r-idx) new-id)))
        ;; Build final labels, refined frame (with computed intra-fiber pairs & cross-fiber anchors), and row partition
        (let* ((labels (coerce assignments 'list))
               (part (partition-rows (frame-rows frame) labels ledger))
               (refined-rows
                 (loop for i below n
                       for row = (aref rows-vec i)
                       for cid = (aref assignments i)
                       for class = (nth cid classes)
                       collect (make-row :key (copy-tree (row-key row))
                                         :known (copy-tree (row-known row))
                                         :requirement (copy-tree (fiber-class-requirement class))))))
          (multiple-value-bind (inferred-pairs inferred-anchors)
              (partition-pairs-and-anchors part nil ledger)
            (let ((refined-frame (make-frame (copy-schema schema) refined-rows
                                             :pairs (or (frame-pairs frame) inferred-pairs)
                                             :anchors (or (frame-anchors frame) inferred-anchors))))
              (values classes labels refined-frame part))))))))

(defun fiber-pairs-and-anchors (frame &optional ledger (budget 10000))
  "Compute intra-fiber must-agree `pairs` and cross-fiber must-vary `anchors` from FRAME
via `infer-fibers`. Returns (VALUES pairs anchors refined-frame classes labels partition)."
  (multiple-value-bind (classes labels refined-frame part)
      (infer-fibers frame ledger budget)
    (values (frame-pairs refined-frame)
            (frame-anchors refined-frame)
            refined-frame
            classes
            labels
            part)))

(defun context-label-frame (parent labels &key bindings (label-type :int) (lookup-p t) ledger)
  "Project PARENT rows through BINDINGS (an alist of (child-input-id . parent-expr),
defaulting to all parent inputs) onto singleton requirements for LABELS of type LABEL-TYPE.
Charges evaluation of each context binding expression on LEDGER."
  (let* ((parent-schema (frame-schema parent))
         (parent-inputs (schema-inputs parent-schema))
         (parent-rows (frame-rows parent))
         (effective-bindings
           (or bindings
               (loop for spec in parent-inputs
                     collect (cons (car spec) (var (car spec) (cdr spec))))))
         (child-inputs
           (mapcar (lambda (b)
                     (cons (car b) (expression-type (cdr b) parent-inputs)))
                   effective-bindings)))
    (assert (= (length labels) (length parent-rows)) ()
            "Label count (~D) must match parent row count (~D)"
            (length labels) (length parent-rows))
    (make-frame
     (make-schema :domain (if (eq label-type :bool) (schema-domain parent-schema) label-type)
                  :inputs child-inputs
                  :target label-type
                  :lookup-p lookup-p)
     (loop for row in parent-rows
           for label in labels
           collect (let* ((known
                            (mapcar (lambda (binding)
                                      (let ((run (evaluate (cdr binding) parent-inputs (row-known row)
                                                           :ledger ledger)))
                                        (unless (eq (evaluation-status run) :value)
                                          (error "Context binding did not finish: ~S" run))
                                        (evaluation-value run)))
                                    effective-bindings))
                          (req (singleton-requirement label-type label)))
                     (charge ledger :context-frame (syntax-work req))
                     (make-row :key (copy-tree (row-key row))
                               :known known
                               :requirement req))))))

;;; Operation 4: Heuristic Condensation (condense-heuristic)

(defstruct (heuristic-model (:conc-name heuristic-))
  program
  residual
  (exact-p nil :type boolean)
  (program-bits 0 :type fixnum)
  (residual-bits 0 :type fixnum)
  (run-work 0 :type fixnum)
  (score 0))

(defun condense-heuristic (frame language &key description-limit (work-limit 100000) (run-weight 0) ledger)
  "Direct MDL heuristic synthesis over underconstrained row requirements:
1. Enforce same-input functional determinism on FRAME via `tighten-same-input-requirements`.
2. Enumerate candidate selectors/programs in LANGUAGE up to DESCRIPTION-LIMIT and WORK-LIMIT,
   checking each candidate's outputs directly against the row requirements via `check-requirement`
   and scoring by S(program) + S(residual) + run-weight * W_run(program).
3. Return the best `heuristic-model` (whose deployed `program` drops the training residual)."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (inputs (schema-inputs schema))
         (tightened-reqs (tighten-same-input-requirements frame ledger))
         (refined-rows
           (loop for row in (frame-rows frame)
                 for idx from 0
                 collect (make-row :key (copy-tree (row-key row))
                                   :known (copy-tree (row-known row))
                                   :requirement (aref tightened-reqs idx))))
         (refined-frame (make-frame (copy-schema schema) refined-rows
                                    :pairs (frame-pairs frame) :anchors (frame-anchors frame)))
         (bound (or description-limit (+ (header-size inputs target-type) 18)))
         (scope (make-observation-scope refined-frame language :pairs nil :anchors nil))
         (obs-job (start-observation-search scope :retain-outcomes t)))
    (resume-observation-search obs-job bound work-limit)
    (charge ledger :heuristic-search (ledger-total (observation-job-ledger obs-job)))
    (let ((best-model nil)
          (rows (frame-rows refined-frame)))
      (dolist (record (reverse (observation-job-records obs-job)))
        (when (equal (observed-expression-type record) target-type)
          (let* ((expr (observed-expression-expression record))
                 (prog-bits (description-size expr inputs))
                 (run-work (observed-expression-run-work record))
                 (residual nil)
                 (res-bits 0)
                 (valid-residual-p t))
            (loop for row in rows
                  for outcome in (observed-expression-outcomes record)
                  for row-idx from 0
                  do (let ((satisfied-p
                             (and (eq :value (observation-outcome-status outcome))
                                  (let ((chk (check-requirement (row-requirement row)
                                                                (observation-outcome-value outcome)
                                                                :ledger ledger :type target-type)))
                                    (and (eq :value (evaluation-status chk))
                                         (eq t (evaluation-value chk)))))))
                       (unless satisfied-p
                         (let ((vals (extract-allowed-values (row-requirement row))))
                           (if (and (listp vals) vals)
                               (let ((witness (first vals)))
                                 (push (cons (row-key row) witness) residual)
                                 (incf res-bits (+ (positive-bit-size (1+ row-idx))
                                                   (value-bit-size witness target-type))))
                               (setf valid-residual-p nil))))))
            (when valid-residual-p
              (let* ((score (+ prog-bits res-bits (* run-weight run-work)))
                     (candidate-model
                       (make-heuristic-model :program expr
                                             :residual (nreverse residual)
                                             :exact-p (null residual)
                                             :program-bits prog-bits
                                             :residual-bits res-bits
                                             :run-work run-work
                                             :score score)))
                (when (or (null best-model)
                          (< score (heuristic-score best-model))
                          (and (= score (heuristic-score best-model))
                               (< prog-bits (heuristic-program-bits best-model))))
                  (setf best-model candidate-model)))))))
      best-model)))

;;; Law Corpus Compression (M3B)

(defstruct (law-corpus (:constructor %make-law-corpus)) domain inputs laws packet)

(defun bits-as-values (bits)
  (map 'list (lambda (bit) (= bit 1)) bits))

(defun values-as-bits (values)
  (assert (value-p values (sequence-type :bool)))
  (map 'bit-vector (lambda (value) (if value 1 0)) values))

(defun collect-code-values (writer &optional ledger)
  (let ((values nil))
    (funcall writer (lambda (width value)
                      (charge ledger :packet-assembly width)
                      (loop for i downfrom (1- width) to 0 do
                        (push (logbitp i value) values))))
    (nreverse values)))

(defun law-corpus-type (domain)
  (tuple-type domain (sequence-type (sequence-type :bool))))

(defun make-law-corpus (laws &optional ledger)
  "Snapshot one domain/schema's ordered statements, including duplicate occurrences.
Evidence/provenance are not part of this syntax-compression task."
  (assert laws)
  (let ((domain (law-domain (first laws))) (inputs (law-inputs (first laws))))
    (assert (every (lambda (law) (and (equal domain (law-domain law))
                                      (equal inputs (law-inputs law)))) laws))
    (let* ((copies (mapcar (lambda (law)
                             (let ((eq-args (rest (law-equation law))))
                               (make-law domain inputs (first eq-args) (second eq-args)
                                         :guard (law-guard law))))
                           laws))
           (packets (mapcar (lambda (law)
                              (let ((statement (law-statement law)))
                                (charge ledger :corpus-encoding (syntax-work statement))
                                (collect-code-values (lambda (emit) (emit-bit-model statement inputs emit)) ledger)))
                            copies))
           (literal (lit (law-corpus-type domain) (list 0 packets))))
      (%make-law-corpus :domain (copy-tree domain) :inputs (copy-tree inputs) :laws copies
                        :packet (collect-code-values (lambda (emit) (emit-bit-model literal nil emit)) ledger)))))

(defun decode-law-corpus (packet)
  "Decode a standalone reconstructed corpus into fresh law proposals, never certificates."
  (multiple-value-bind (literal inputs) (decode-model (values-as-bits packet))
    (assert (and (null inputs) (lit-p literal)))
    (let* ((type (ast-type literal)) (domain (second type)) (value (ast-value literal)))
      (assert (equal type (law-corpus-type domain)))
      (assert (eql 0 (first value)))
      (let ((laws
              (loop for bits in (second value) collect
                (multiple-value-bind (statement schema) (decode-model (values-as-bits bits))
                  (assert (and (app-p statement)
                               (equal (op :if :bool) (first statement))
                               (equal (lit :bool t) (third (rest statement)))))
                  (let ((guard (first (rest statement)))
                        (equation (second (rest statement))))
                    (assert (and (app-p equation) (eq := (operator-name (first equation)))))
                    (make-law domain schema (first (rest equation)) (second (rest equation))
                              :guard guard :origin '(:decoded-syntax)))))))
        (assert laws)
        (assert (every (lambda (law) (equal (law-inputs (first laws)) (law-inputs law))) laws))
        laws))))

(defun law-corpus-prefix (corpus &optional ledger)
  (collect-code-values
   (lambda (emit)
     (emit-bit-header nil (law-corpus-type (law-corpus-domain corpus)) emit)
     (funcall emit 2 1) ; literal
     (emit-bit-value 0 (law-corpus-domain corpus) emit)
     (emit-positive (1+ (length (law-corpus-laws corpus))) emit)) ledger))

(defun au-packet-pieces (pattern inputs &optional ledger)
  "Compile a typed AU pattern to fixed packet fragments and typed hole references."
  (let ((pieces nil) (fixed nil))
    (labels ((emit (width value)
               (charge ledger :packet-assembly width)
               (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
             (flush-fixed ()
               (when fixed (push (list :fixed (nreverse fixed)) pieces) (setf fixed nil)))
             (walk (term)
               (charge ledger :au-compilation (syntax-work term))
               (cond
                 ((hole-p term) (flush-fixed) (push term pieces))
                 ((operator-p term) (emit-operator term #'emit))
                 ((not (pattern-has-holes-p term))
                  (emit-bit-expression term inputs (expression-type term inputs) #'emit))
                 (t (assert (app-p term))
                    (emit 2 2) (walk (first term)) (mapc #'walk (rest term))))))
      (emit-bit-header inputs (expression-type pattern inputs t) #'emit)
      (walk pattern) (flush-fixed)
      (nreverse pieces))))

(defun instantiate-packet-pieces (pieces substitution inputs &optional ledger)
  (mapcar
   (lambda (piece)
     (if (and (consp piece) (eq :fixed (first piece)))
         (second piece)
         (let ((entry (assoc (ast-id piece) substitution)))
           (assert entry)
           (assert (equal (ast-type piece) (term-sort (cdr entry) inputs)))
           (charge ledger :au-substitution (syntax-work (cdr entry)))
           (collect-code-values
            (lambda (emit)
              (if (operator-p (cdr entry))
                  (emit-operator (cdr entry) emit)
                  (emit-bit-expression (cdr entry) inputs (ast-type piece) emit)))
            ledger))))
   pieces))

(defun packet-chunks-model (chunks &optional ledger)
  "A normal closed VM program; its dictionary and full occurrence order are encoded."
  (multiple-value-bind (representatives residual) (quotient-values chunks ledger)
    (let ((model (app (op :concat :bool)
                      (quotient-model (sequence-type :bool) representatives residual ledger))))
      (charge ledger :construction (syntax-work model))
      model)))

(defun law-row-pieces-model (corpus rows &optional ledger)
  (assert (= (length rows) (length (law-corpus-laws corpus))))
  (let ((chunks (list (law-corpus-prefix corpus ledger))))
    (map nil (lambda (body)
               (let ((size (reduce #'+ body :key #'length)))
                 (push (collect-code-values (lambda (emit) (emit-positive (1+ size) emit)) ledger) chunks)
                 (dolist (piece body) (push piece chunks)))) rows)
    (packet-chunks-model (nreverse chunks) ledger)))

(defun law-template-model (corpus pattern substitutions &optional ledger)
  (assert (= (length substitutions) (length (law-corpus-laws corpus))))
  (let* ((inputs (law-corpus-inputs corpus))
         (pieces (au-packet-pieces pattern inputs ledger)))
    (law-row-pieces-model corpus (mapcar (lambda (substitution)
                                           (instantiate-packet-pieces pieces substitution inputs ledger))
                                         substitutions) ledger)))

(defstruct law-template-group positions pattern substitutions)

(defun law-syntax-shape (term inputs &optional ledger)
  "A supplied structural view, not a learned equivalence: erase leaf values and
compatible operator names, preserving application shape and all types."
  (charge ledger :law-shape)
  (if (app-p term)
      (list :app (operator-type (first term))
            (mapcar (lambda (child) (law-syntax-shape child inputs ledger)) (rest term)))
      (list :leaf (expression-type term inputs))))

(defun grouped-law-template-model (corpus &optional ledger)
  "One supplied shape partition; AU each group and encode all occurrence ordering."
  (let* ((inputs (law-corpus-inputs corpus)) (statements (mapcar #'law-statement (law-corpus-laws corpus)))
         (table (make-hash-table :test #'equal)) (groups nil)
         (rows (make-array (length statements))))
    (loop for statement in statements for i from 0 do
      (let* ((shape (law-syntax-shape statement inputs ledger)) (group (gethash shape table)))
        (unless group
          (setf group (make-law-template-group) (gethash shape table) group)
          (push group groups))
        (push i (law-template-group-positions group))))
    (setf groups (nreverse groups))
    (let ((vector (coerce statements 'vector)))
      (dolist (group groups)
        (setf (law-template-group-positions group) (nreverse (law-template-group-positions group)))
        (multiple-value-bind (pattern substitutions)
            (anti-unify (mapcar (lambda (i) (aref vector i)) (law-template-group-positions group)) inputs ledger)
          (setf (law-template-group-pattern group) pattern (law-template-group-substitutions group) substitutions)
          (let ((pieces (au-packet-pieces pattern inputs ledger)))
            (loop for i in (law-template-group-positions group) for substitution in substitutions do
              (setf (aref rows i) (instantiate-packet-pieces pieces substitution inputs ledger)))))))
    (values (law-row-pieces-model corpus rows ledger) groups)))

(defun propose-law-compressions (corpus &optional ledger)
  "Four complete proposals: literal, whole-packet dictionary, global/grouped AU."
  (let* ((inputs (law-corpus-inputs corpus))
         (statements (mapcar #'law-statement (law-corpus-laws corpus)))
         (literal (lit (sequence-type :bool) (law-corpus-packet corpus)))
         (chunks (list (law-corpus-prefix corpus ledger))))
    (charge ledger :construction (syntax-work literal))
    (dolist (statement statements)
      (let ((packet (collect-code-values (lambda (emit) (emit-bit-model statement inputs emit)) ledger)))
        (push (append (collect-code-values (lambda (emit) (emit-positive (1+ (length packet)) emit)) ledger)
                      packet) chunks)))
    (multiple-value-bind (pattern substitutions) (anti-unify statements inputs ledger)
      (multiple-value-bind (grouped groups) (grouped-law-template-model corpus ledger)
        (values (list literal (packet-chunks-model (nreverse chunks) ledger)
                      (law-template-model corpus pattern substitutions ledger) grouped)
                pattern substitutions groups)))))

(defun law-corpus-frame (corpus &optional ledger)
  (let ((req (set-requirement (sequence-type :bool) (list (law-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work req))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :law-corpus :known nil :requirement req)))))

;;; Subexpression Occurrence Search & Corpus Abstraction (M6)

(defun patterns-isomorphic-p (pattern-a pattern-b &optional inputs ledger)
  "Check whether PATTERN-A and PATTERN-B are identical up to a sort-preserving
bijection (alpha-renaming) of hole IDs."
  (unless (equal (term-sort pattern-a inputs) (term-sort pattern-b inputs))
    (return-from patterns-isomorphic-p nil))
  (let ((forward nil)
        (reverse nil))
    (labels ((walk (a b)
               (charge ledger :matching)
               (cond
                 ((and (hole-p a) (hole-p b))
                  (and (equal (ast-type a) (ast-type b))
                       (let ((f-entry (assoc (ast-id a) forward))
                             (r-entry (assoc (ast-id b) reverse)))
                         (cond
                           ((and f-entry r-entry)
                            (and (= (cdr f-entry) (ast-id b))
                                 (= (cdr r-entry) (ast-id a))))
                           ((or f-entry r-entry) nil)
                           (t
                            (push (cons (ast-id a) (ast-id b)) forward)
                            (push (cons (ast-id b) (ast-id a)) reverse)
                            t)))))
                 ((or (hole-p a) (hole-p b)) nil)
                 ((equal a b) t)
                 ((and (app-p a) (app-p b)
                       (= (length (rest a)) (length (rest b))))
                  (and (walk (first a) (first b))
                       (every #'walk (rest a) (rest b))))
                 (t nil))))
      (walk pattern-a pattern-b))))

(defun pattern-holes (pattern)
  "Return the ordered list of unique (hole-id . hole-sort) pairs in pre-order."
  (let ((holes nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (unless (assoc (ast-id term) holes)
                    (push (cons (ast-id term) (ast-type term)) holes)))
                 ((app-p term)
                  (walk (first term))
                  (mapc #'walk (rest term))))))
      (walk pattern)
      (nreverse holes))))

(defun pattern-hole-counts (pattern)
  "Return an alist (hole-id . multiplicity) for all holes in PATTERN."
  (let ((counts nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (let ((entry (assoc (ast-id term) counts)))
                    (if entry
                        (incf (cdr entry))
                        (push (cons (ast-id term) 1) counts))))
                 ((app-p term)
                  (walk (first term))
                  (mapc #'walk (rest term))))))
      (walk pattern)
      (nreverse counts))))

(defun subtree-at-path (term path &optional ledger)
  "Return the subexpression of TERM at PATH (a list of 0-based argument indices)."
  (let ((cur term))
    (dolist (idx path cur)
      (charge ledger :occurrence-access)
      (assert (and (app-p cur) (integerp idx) (<= 0 idx) (< idx (length (rest cur)))) ()
              "Invalid occurrence path ~S on ~S" path term)
      (setf cur (nth idx (rest cur))))))

(defun replace-at-path (term path replacement &optional ledger)
  "Return a copy of TERM with the subexpression at PATH replaced by REPLACEMENT."
  (charge ledger :occurrence-wrapper)
  (if (null path)
      replacement
      (let ((idx (first path))
            (args (rest term)))
        (assert (and (app-p term) (integerp idx) (<= 0 idx) (< idx (length args))) ()
                "Invalid replacement path ~S on ~S" path term)
        (apply #'app (first term)
               (loop for child in args
                     for i from 0
                     collect (if (= i idx)
                                 (replace-at-path child (rest path) replacement ledger)
                                 child))))))

(defstruct tree-occurrence
  (tree-index 0 :type fixnum)
  path
  term
  sort
  signature
  wrapper
  (context-hole-id 999 :type fixnum))

(defun collect-tree-occurrences (tree inputs &key (tree-index 0) (context-hole-id 999) ledger)
  "Collect all subexpression occurrences in TREE in pre-order."
  (let ((occurrences nil))
    (labels ((walk (sub rev-path)
               (charge ledger :occurrence-enumeration)
               (let* ((path (nreverse (copy-list rev-path)))
                      (sort (expression-type sub inputs t))
                      (sig (and (app-p sub) (operator-type (first sub))))
                      (wrapper (replace-at-path tree path (hole context-hole-id sort) ledger)))
                 (push (make-tree-occurrence :tree-index tree-index
                                             :path path
                                             :term sub
                                             :sort sort
                                             :signature sig
                                             :wrapper wrapper
                                             :context-hole-id context-hole-id)
                       occurrences)
                 (when (app-p sub)
                   (loop for child in (rest sub)
                         for i from 0
                         do (walk child (cons i rev-path)))))))
      (walk tree nil)
      (nreverse occurrences))))

(defun au-substitutions-frame (pattern substitutions &key keys known inputs ledger)
  "Convert recovered AU SUBSTITUTIONS for PATTERN into an ordinary child frame
whose target is the tuple of quoted hole values `(:tuple (:code inputs hole-sort) ...)`.
When KNOWN is omitted, defaults each row's known input to its occurrence coordinate `(idx)`."
  (let* ((holes (pattern-holes pattern))
         (hole-code-types (mapcar (lambda (h) (code-type inputs (cdr h))) holes))
         (target-type (apply #'tuple-type hole-code-types))
         (effective-known (or known
                              (loop for i below (length substitutions)
                                    collect (list i))))
         (schema-inputs (when (first effective-known)
                          (loop for v in (first effective-known)
                                for i from 0
                                collect (cons i :int))))
         (rows
           (loop for subst in substitutions
                 for idx from 0
                 for key = (if keys (nth idx keys) idx)
                 for row-known = (nth idx effective-known)
                 for tuple-val = (mapcar (lambda (h)
                                           (let ((entry (assoc (car h) subst)))
                                             (assert entry () "Missing binding for hole ~S" (car h))
                                             (cdr entry)))
                                         holes)
                 for req = (set-requirement target-type (list tuple-val))
                 do (charge ledger :au-child-frame (syntax-work req))
                 collect (make-row :key key :known row-known :requirement req))))
    (make-frame (make-schema :inputs schema-inputs :target target-type :lookup-p t) rows)))

(defstruct (tree-corpus (:constructor %make-tree-corpus))
  domain
  inputs
  sort
  trees
  packet)

(defun make-tree-corpus (trees inputs &key domain sort ledger)
  "Snapshot an ordered sequence of typed ASTs under INPUTS into a standalone bit packet."
  (assert trees)
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (inferred-sort (or sort (expression-type (first trees) norm-inputs)))
         (inferred-domain (or domain
                              (if (and (consp inferred-sort) (eq :gf (first inferred-sort)))
                                  inferred-sort
                                  (let ((gf-in (find-if (lambda (spec)
                                                          (and (consp (cdr spec)) (eq :gf (first (cdr spec)))))
                                                        norm-inputs)))
                                    (if gf-in (cdr gf-in) :int)))))
         (copies (mapcar #'copy-tree trees))
         (packets
           (mapcar (lambda (tree)
                     (assert (equal inferred-sort (expression-type tree norm-inputs)))
                     (charge ledger :corpus-encoding (syntax-work tree))
                     (collect-code-values (lambda (emit) (emit-bit-model tree norm-inputs emit)) ledger))
                   copies))
         (literal (lit (law-corpus-type inferred-domain) (list 0 packets))))
    (%make-tree-corpus :domain (copy-tree inferred-domain)
                       :inputs (copy-tree norm-inputs)
                       :sort (copy-tree inferred-sort)
                       :trees copies
                       :packet (collect-code-values (lambda (emit) (emit-bit-model literal nil emit)) ledger))))

(defun decode-tree-corpus (packet)
  "Decode a standalone tree-corpus packet back into fresh ASTs and verify schema consistency."
  (multiple-value-bind (literal top-inputs) (decode-model (values-as-bits packet))
    (assert (and (null top-inputs) (lit-p literal)))
    (let* ((type (ast-type literal))
           (domain (second type))
           (value (ast-value literal)))
      (assert (equal type (law-corpus-type domain)))
      (assert (eql 0 (first value)))
      (let ((trees nil)
            (first-schema nil)
            (first-sort nil))
        (dolist (bits (second value))
          (multiple-value-bind (tree schema) (decode-model (values-as-bits bits))
            (let ((sort (expression-type tree schema)))
              (if (null trees)
                  (setf first-schema schema
                        first-sort sort)
                  (assert (and (equal schema first-schema)
                               (equal sort first-sort))))
              (push tree trees))))
        (assert trees)
        (values (nreverse trees) first-schema first-sort domain)))))

(defun tree-corpus-prefix (corpus &optional ledger)
  (collect-code-values
   (lambda (emit)
     (emit-bit-header nil (law-corpus-type (tree-corpus-domain corpus)) emit)
     (funcall emit 2 1) ; literal
     (emit-bit-value 0 (tree-corpus-domain corpus) emit)
     (emit-positive (1+ (length (tree-corpus-trees corpus))) emit))
   ledger))

(defun tree-corpus-frame (corpus &optional ledger)
  (let ((req (set-requirement (sequence-type :bool) (list (tree-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work req))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :tree-corpus :known nil :requirement req)))))

(defun au-body-pieces (pattern inputs &key include-header-p ledger)
  "Compile a typed AU pattern into fixed bit fragments and hole references.
When INCLUDE-HEADER-P is nil, omits the outer packet header so the body pieces
can be spliced at any occurrence path inside an outer wrapper."
  (let ((pieces nil) (fixed nil))
    (labels ((emit (width value)
               (charge ledger :packet-assembly width)
               (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
             (flush-fixed ()
               (when fixed (push (list :fixed (nreverse fixed)) pieces) (setf fixed nil)))
             (walk (term)
               (charge ledger :au-compilation (syntax-work term))
               (cond
                 ((hole-p term) (flush-fixed) (push term pieces))
                 ((operator-p term) (emit-operator term #'emit))
                 ((not (pattern-has-holes-p term))
                  (emit-bit-expression term inputs (expression-type term inputs) #'emit))
                 (t (assert (app-p term))
                    (emit 2 2) (walk (first term)) (mapc #'walk (rest term))))))
      (when include-header-p
        (emit-bit-header inputs (expression-type pattern inputs t) #'emit))
      (walk pattern)
      (flush-fixed)
      (nreverse pieces))))

(defun tree-occurrence-packet-pieces (tree path body-pieces substitution inputs &key header-in-body-p ledger)
  "Emit the ordered bit pieces of TREE when the subexpression at PATH is factored
through BODY-PIECES and SUBSTITUTION. If PATH is :NONE, emits TREE as a single chunk."
  (let ((root-sort (expression-type tree inputs)))
    (cond
      ((eq path :none)
       (list (collect-code-values (lambda (emit) (emit-bit-model tree inputs emit)) ledger)))
      ((and (null path) header-in-body-p)
       (instantiate-packet-pieces body-pieces substitution inputs ledger))
      (t
       (let ((chunks nil)
             (fixed nil))
         (labels ((emit (width value)
                    (charge ledger :packet-assembly width)
                    (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
                  (flush-fixed ()
                    (when fixed
                      (push (nreverse fixed) chunks)
                      (setf fixed nil)))
                  (walk-wrapper (term rel-path expected-type)
                    (declare (ignore expected-type))
                    (if (null rel-path)
                        (progn
                          (flush-fixed)
                          (dolist (piece-bits (instantiate-packet-pieces body-pieces substitution inputs ledger))
                            (push piece-bits chunks)))
                        (let ((idx (first rel-path))
                              (operator (first term)))
                          (assert (app-p term))
                          (emit 2 2)
                          (emit-operator operator #'emit)
                          (loop for child in (rest term)
                                for child-type in (second (operator-type operator))
                                for k from 0
                                do (if (= k idx)
                                       (walk-wrapper child (rest rel-path) child-type)
                                       (emit-bit-expression child inputs child-type #'emit)))))))
           (emit-bit-header inputs root-sort #'emit)
           (walk-wrapper tree path root-sort)
           (flush-fixed)
           (nreverse chunks)))))))

(defun tree-row-pieces-model (corpus rows &optional ledger)
  (assert (= (length rows) (length (tree-corpus-trees corpus))))
  (let ((chunks (list (tree-corpus-prefix corpus ledger))))
    (map nil (lambda (body)
               (let ((size (reduce #'+ body :key #'length)))
                 (push (collect-code-values (lambda (emit) (emit-positive (1+ size) emit)) ledger) chunks)
                 (dolist (piece body) (push piece chunks))))
         rows)
    (packet-chunks-model (nreverse chunks) ledger)))

(defun corpus-abstraction-model (corpus pattern paths substitutions &optional ledger)
  "Construct a closed VM program reconstructing CORPUS by factoring each tree i
at `(nth i paths)` (or leaving it unfactored when `(eq :none (nth i paths))`)."
  (let* ((trees (tree-corpus-trees corpus))
         (inputs (tree-corpus-inputs corpus))
         (all-root-p (every #'null paths))
         (body-pieces (au-body-pieces pattern inputs :include-header-p all-root-p :ledger ledger))
         (sub-cursor substitutions)
         (rows
           (loop for tree in trees
                 for path in paths
                 collect (if (eq path :none)
                             (tree-occurrence-packet-pieces tree :none nil nil inputs :ledger ledger)
                             (let ((subst (pop sub-cursor)))
                               (tree-occurrence-packet-pieces tree path body-pieces subst inputs
                                                              :header-in-body-p all-root-p
                                                              :ledger ledger))))))
    (tree-row-pieces-model corpus rows ledger)))

(defstruct subexpression-abstraction
  (kind :subexpression)
  pattern
  sort
  occurrences
  substitutions
  wrappers
  paths
  model
  (bits 0 :type fixnum)
  (literal-bits 0 :type fixnum)
  (gain 0 :type fixnum)
  (structural-score 0 :type fixnum))

(defun term-body-bits (term inputs)
  "Return the exact body bit length of a concrete term or operator."
  (if (operator-p term)
      (length (collect-code-values (lambda (emit) (emit-operator term emit))))
      (body-size term inputs)))

(defun occurrence-saved-bits (occ pattern substitution inputs)
  "Exact bit savings inside OCC's tree from factoring `(tree-occurrence-term occ)`
through PATTERN and unique hole bindings in SUBSTITUTION."
  (declare (ignore pattern))
  (let ((sub-bits (body-size (tree-occurrence-term occ) inputs))
        (unique-hole-bits
          (loop for (hole-id . hole-val) in substitution
                sum (term-body-bits hole-val inputs))))
    (- sub-bits unique-hole-bits)))

(defun abstraction-structural-score (pattern occurrences substitutions inputs)
  "Compute the structural bit-sharing utility of PATTERN across OCCURRENCES:
shared fixed template bits across (K - 1) occurrences plus repeated-hole savings
within each occurrence."
  (let ((k (length occurrences)))
    (if (or (< k 2) (null pattern) (hole-p pattern))
        0
        (let* ((first-occ (first occurrences))
               (first-subst (first substitutions))
               (fixed-bits
                 (max 0 (- (body-size (tree-occurrence-term first-occ) inputs)
                           (loop for (hid . mult) in (pattern-hole-counts pattern)
                                 for entry = (assoc hid first-subst)
                                 when entry
                                 sum (* mult (term-body-bits (cdr entry) inputs))))))
               (total-saved
                 (loop for occ in occurrences
                       for subst in substitutions
                       sum (occurrence-saved-bits occ pattern subst inputs))))
          (- total-saved fixed-bits)))))

(defun normalize-trees-with-library (trees inputs rewrite-library &key (budget 100000) ledger)
  "Normalize each tree in TREES using validated REWRITE-LIBRARY in the metered VM."
  (mapcar (lambda (tree)
            (let ((state (start-rewriting tree inputs rewrite-library)))
              (advance-rewriting state budget)
              (charge ledger :rewriting (rewriting-work state))
              (if (eq :complete (rewriting-status state))
                  (rewriting-value state)
                  tree)))
          trees))

(defun compute-tree-locality-positions (n locality-key &optional ledger)
  "Compute the induced position vector (0..N-1) for tree indices under LOCALITY-KEY.
When LOCALITY-KEY is nil, position(i) = i. When LOCALITY-KEY is a function or DSL expression
over `((0 . :int))`, evaluates the key for each tree index i, partitions the indices via
`partition-rows`, and verifies inverse-permutation reassembly via `reassemble-partition`."
  (let ((pos-vec (make-array n)))
    (if (null locality-key)
        (dotimes (i n pos-vec)
          (setf (aref pos-vec i) i))
        (let* ((indices (loop for i below n collect i))
               (labels
                 (loop for i below n
                       collect (if (functionp locality-key)
                                   (progn
                                     (charge ledger :locality-key)
                                     (funcall locality-key i))
                                   (let ((run (evaluate locality-key '((0 . :int)) (list i) :ledger ledger)))
                                     (unless (eq :value (evaluation-status run))
                                       (error "Locality key evaluation failed on ~D: ~S" i run))
                                     (evaluation-value run)))))
               (part (partition-rows indices labels ledger))
               (ordered-indices (apply #'append (partition-groups part))))
          (assert (equal indices (reassemble-partition part ledger)))
          (loop for tree-idx in ordered-indices
                for rank from 0
                do (setf (aref pos-vec tree-idx) rank))
          pos-vec))))

(defun schedule-occurrence-pairs (canonical-pairs tree-pos schedule pair-budget &optional ledger)
  "Order candidate occurrence pairs `(oa . ob)` under SCHEDULE (:CANONICAL, :LOCALITY with 1-in-4
canonical reserve, or :LOCALITY-ONLY restricted to adjacent tree distance <= 1) up to PAIR-BUDGET."
  (assert (member schedule '(:canonical :locality :locality-only)))
  (if (and (eq schedule :canonical) (null pair-budget))
      canonical-pairs
      (flet ((pair-cross-tree-p (p)
               (/= (tree-occurrence-tree-index (car p))
                   (tree-occurrence-tree-index (cdr p))))
             (pair-tree-dist (p)
               (abs (- (aref tree-pos (tree-occurrence-tree-index (car p)))
                       (aref tree-pos (tree-occurrence-tree-index (cdr p))))))
             (pair-path-dist (p)
               (abs (- (length (tree-occurrence-path (car p)))
                       (length (tree-occurrence-path (cdr p))))))
             (pair-depth-sum (p)
               (+ (length (tree-occurrence-path (car p)))
                  (length (tree-occurrence-path (cdr p))))))
        (ecase schedule
          (:canonical
           (if pair-budget
               (subseq canonical-pairs 0 (min pair-budget (length canonical-pairs)))
               canonical-pairs))
          (:locality-only
           (let* ((local-pairs
                    (remove-if-not (lambda (p)
                                     (and (pair-cross-tree-p p)
                                          (<= (pair-tree-dist p) 1)))
                                   canonical-pairs))
                  (sorted (stable-sort (copy-list local-pairs)
                                       (lambda (a b)
                                         (let ((pa (pair-path-dist a))
                                               (pb (pair-path-dist b)))
                                           (if (/= pa pb)
                                               (< pa pb)
                                               (< (pair-depth-sum a) (pair-depth-sum b))))))))
             (charge ledger :locality-scheduling (length sorted))
             (if pair-budget
                 (subseq sorted 0 (min pair-budget (length sorted)))
                 sorted)))
          (:locality
           (let* ((loc-queue
                    (stable-sort (copy-list canonical-pairs)
                                 (lambda (a b)
                                   (let ((ca (pair-cross-tree-p a))
                                         (cb (pair-cross-tree-p b)))
                                     (if (not (eq ca cb))
                                         ca
                                         (let ((da (pair-tree-dist a))
                                               (db (pair-tree-dist b)))
                                           (if (/= da db)
                                               (< da db)
                                               (let ((pa (pair-path-dist a))
                                                     (pb (pair-path-dist b)))
                                                 (if (/= pa pb)
                                                     (< pa pb)
                                                     (< (pair-depth-sum a) (pair-depth-sum b)))))))))))
                  (can-queue (copy-list canonical-pairs))
                  (seen (make-hash-table :test #'equal))
                  (selected nil)
                  (limit (or pair-budget (length canonical-pairs)))
                  (turn 0))
             (loop while (and (< (length selected) limit)
                              (or loc-queue can-queue))
                   do (charge ledger :locality-scheduling)
                      (let* ((reserve-p (= 3 (mod turn 4)))
                             (next-pair nil))
                        (incf turn)
                        (if reserve-p
                            (loop while can-queue
                                  for cand = (pop can-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return))
                            (loop while loc-queue
                                  for cand = (pop loc-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return)))
                        (unless next-pair
                          (loop while loc-queue
                                for cand = (pop loc-queue)
                                unless (gethash cand seen)
                                do (setf next-pair cand) (return))
                          (unless next-pair
                            (loop while can-queue
                                  for cand = (pop can-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return))))
                        (when next-pair
                          (setf (gethash next-pair seen) t)
                          (push next-pair selected))))
             (nreverse selected)))))))

(defun discover-subexpression-abstractions (trees inputs &key domain rewrite-library
                                                           (schedule :canonical) pair-budget locality-key ledger)
  "Search for shared subexpression abstractions across TREES (even when occurrence
paths are hidden under different outer wrappers or unrelated control trees are present).
Supports :SCHEDULE (:CANONICAL, :LOCALITY with 1-in-4 canonical reserve, or :LOCALITY-ONLY),
optional :PAIR-BUDGET, and optional :LOCALITY-KEY (priced on LEDGER).
Returns (VALUES best-compression best-structural proposals corpus normalized-trees)."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (active-trees (if rewrite-library
                           (normalize-trees-with-library trees norm-inputs rewrite-library :ledger ledger)
                           trees))
         (corpus (make-tree-corpus active-trees norm-inputs :domain domain :ledger ledger))
         (n (length active-trees))
         (tree-pos (compute-tree-locality-positions n locality-key ledger))
         (literal-model (lit (sequence-type :bool) (tree-corpus-packet corpus)))
         (literal-bits (description-size literal-model nil))
         (dict-chunks (cons (tree-corpus-prefix corpus ledger)
                            (loop for tree in active-trees
                                  for pkt = (collect-code-values
                                             (lambda (emit) (emit-bit-model tree norm-inputs emit))
                                             ledger)
                                  collect (append (collect-code-values
                                                   (lambda (emit) (emit-positive (1+ (length pkt)) emit))
                                                   ledger)
                                                  pkt))))
         (dict-model (packet-chunks-model dict-chunks ledger))
         (dict-bits (description-size dict-model nil))
         (proposals
           (list (make-subexpression-abstraction
                  :kind :literal
                  :pattern nil
                  :sort (tree-corpus-sort corpus)
                  :paths (make-list n :initial-element :none)
                  :model literal-model
                  :bits literal-bits
                  :literal-bits literal-bits
                  :gain 0
                  :structural-score 0)
                 (make-subexpression-abstraction
                  :kind :dictionary
                  :pattern nil
                  :sort (tree-corpus-sort corpus)
                  :paths (make-list n :initial-element :none)
                  :model dict-model
                  :bits dict-bits
                  :literal-bits literal-bits
                  :gain (- literal-bits dict-bits)
                  :structural-score 0)))
         (per-tree-occs (make-array n))
         (buckets (make-hash-table :test #'equal))
         (candidate-patterns (make-hash-table :test #'equal))
         (evaluated-selections (make-hash-table :test #'equal)))
    (charge ledger :construction (syntax-work literal-model))
    ;; 1. Collect and index all subexpression occurrences across all trees by (sort . signature)
    (loop for tree in active-trees
          for i from 0
          for occs = (collect-tree-occurrences tree norm-inputs :tree-index i :ledger ledger)
          do (setf (aref per-tree-occs i) occs)
             (dolist (occ occs)
               (let ((key (cons (tree-occurrence-sort occ)
                                (tree-occurrence-signature occ))))
                 (push occ (gethash key buckets)))))
    ;; 2. Generate candidate LGG patterns per (sort . signature) bucket
    (labels ((trivial-subexpression-pattern-p (pat)
               (or (hole-p pat)
                   (and (app-p pat)
                        (every #'hole-p pat)
                        (every (lambda (entry) (= 1 (cdr entry)))
                               (pattern-hole-counts pat))))))
      ;; 2a. Collect distinct subterms and candidate occurrence pairs across buckets
      (let ((all-canonical-pairs nil))
        (maphash
         (lambda (bucket-key occs)
           (declare (ignore bucket-key))
           (let ((rev-occs (nreverse occs))
                 (distinct-occs nil)
                 (term-counts (make-hash-table :test #'equal)))
             (dolist (o rev-occs)
               (let ((term (tree-occurrence-term o)))
                 (when (zerop (gethash term term-counts 0))
                   (push o distinct-occs))
                 (incf (gethash term term-counts 0))))
             (setf distinct-occs (nreverse distinct-occs))
             ;; Exact repeated subterms (when unconstrained by pair-budget or locality-only schedule)
             (when (and (null pair-budget) (eq schedule :canonical))
               (dolist (o distinct-occs)
                 (let ((term (tree-occurrence-term o)))
                   (when (and (> (gethash term term-counts 0) 1)
                              (not (trivial-subexpression-pattern-p term))
                              (not (gethash term candidate-patterns)))
                     (setf (gethash term candidate-patterns) (list term term))))))
             (loop for tail on distinct-occs
                   for oa = (first tail)
                   do (dolist (ob (rest tail))
                        (push (cons oa ob) all-canonical-pairs)))))
         buckets)
        (setf all-canonical-pairs (nreverse all-canonical-pairs))
        (dolist (pair (schedule-occurrence-pairs all-canonical-pairs tree-pos schedule pair-budget ledger))
          (let* ((oa (car pair))
                 (ob (cdr pair))
                 (terms (list (tree-occurrence-term oa)
                              (tree-occurrence-term ob)))
                 (pat (anti-unify terms norm-inputs ledger)))
            (unless (or (trivial-subexpression-pattern-p pat)
                        (gethash pat candidate-patterns))
              (setf (gethash pat candidate-patterns) terms)))))
      ;; 2b. Multi-tree LGG relaxation across non-matching trees (when unconstrained by pair-budget)
      (when (and (null pair-budget) (not (eq schedule :locality-only)))
        (let ((seed-entries nil))
          (maphash (lambda (pat witnesses) (push (cons pat witnesses) seed-entries))
                   candidate-patterns)
          (dolist (entry (nreverse seed-entries))
            (let ((cur-pat (car entry))
                  (cur-witnesses (cdr entry)))
              (loop for i below n
                    for tree-occs = (aref per-tree-occs i)
                    for pat-sort = (term-sort cur-pat norm-inputs)
                    unless (some (lambda (o)
                                   (and (equal (tree-occurrence-sort o) pat-sort)
                                        (nth-value 1 (match-pattern cur-pat (tree-occurrence-term o)
                                                                    norm-inputs ledger))))
                                 tree-occs)
                    do (let ((best-relaxed nil)
                             (best-witnesses nil)
                             (best-saved 0))
                         (dolist (o tree-occs)
                           (when (and (equal (tree-occurrence-sort o) pat-sort)
                                      (equal (tree-occurrence-signature o)
                                             (and (app-p cur-pat) (term-sort (first cur-pat) norm-inputs))))
                             (let ((new-witnesses (append cur-witnesses (list (tree-occurrence-term o)))))
                               (multiple-value-bind (relaxed substs)
                                   (anti-unify new-witnesses norm-inputs ledger)
                                 (unless (trivial-subexpression-pattern-p relaxed)
                                   (let ((saved (occurrence-saved-bits o relaxed (car (last substs)) norm-inputs)))
                                     (when (> saved best-saved)
                                       (setf best-saved saved
                                             best-relaxed relaxed
                                             best-witnesses new-witnesses))))))))
                         (when best-relaxed
                           (setf cur-pat best-relaxed
                                 cur-witnesses best-witnesses)
                           (unless (gethash cur-pat candidate-patterns)
                             (setf (gethash cur-pat candidate-patterns) cur-witnesses))))))))))
    ;; Always include aligned whole-tree AU when all trees share the corpus root sort
    (when (> n 1)
      (let ((root-pat (anti-unify active-trees norm-inputs ledger)))
        (unless (gethash root-pat candidate-patterns)
          (setf (gethash root-pat candidate-patterns) active-trees))))
    ;; 3. For each candidate pattern, select optimal matching occurrences per tree, tighten via AU, and price
    (let ((scored-selections nil))
      (labels ((record-occurrence-selection (selected-occs kind)
                 (when (>= (length selected-occs) 2)
                   (let ((sel-key (cons kind
                                        (mapcar (lambda (o) (cons (tree-occurrence-tree-index o)
                                                                  (tree-occurrence-path o)))
                                                selected-occs))))
                     (unless (gethash sel-key evaluated-selections)
                       (setf (gethash sel-key evaluated-selections) t)
                       (multiple-value-bind (tight-pat substs)
                           (anti-unify (mapcar #'tree-occurrence-term selected-occs) norm-inputs ledger)
                         (let ((struct-score (abstraction-structural-score tight-pat selected-occs substs norm-inputs)))
                           (push (list :kind kind
                                       :selected-occs selected-occs
                                       :tight-pat tight-pat
                                       :substs substs
                                       :struct-score struct-score)
                                 scored-selections)))))))
               (price-selection (entry)
                 (let* ((kind (getf entry :kind))
                        (selected-occs (getf entry :selected-occs))
                        (tight-pat (getf entry :tight-pat))
                        (substs (getf entry :substs))
                        (struct-score (getf entry :struct-score))
                        (paths (loop for i below n
                                     for occ = (find i selected-occs :key #'tree-occurrence-tree-index)
                                     collect (if occ (tree-occurrence-path occ) :none)))
                        (wrappers (loop for i below n
                                        for occ = (find i selected-occs :key #'tree-occurrence-tree-index)
                                        collect (when occ (tree-occurrence-wrapper occ))))
                        (model (corpus-abstraction-model corpus tight-pat paths substs ledger))
                        (bits (description-size model nil)))
                   (push (make-subexpression-abstraction
                          :kind kind
                          :pattern tight-pat
                          :sort (term-sort tight-pat norm-inputs)
                          :occurrences selected-occs
                          :substitutions substs
                          :wrappers wrappers
                          :paths paths
                          :model model
                          :bits bits
                          :literal-bits literal-bits
                          :gain (- literal-bits bits)
                          :structural-score struct-score)
                         proposals))))
        ;; Record whole-tree aligned AU explicitly
        (when (> n 1)
          (record-occurrence-selection
           (loop for i below n collect (first (aref per-tree-occs i)))
           :aligned-root))
        ;; Record each candidate pattern across all trees
        (maphash
         (lambda (pat witnesses)
           (declare (ignore witnesses))
           (let ((selected nil))
             (loop for i below n
                   for tree-occs = (aref per-tree-occs i)
                   do (let ((best-occ nil)
                            (best-saved most-negative-fixnum)
                            (best-sub-bits most-positive-fixnum))
                        (dolist (occ tree-occs)
                          (when (equal (tree-occurrence-sort occ) (term-sort pat norm-inputs))
                            (multiple-value-bind (subst matched-p)
                                (match-pattern pat (tree-occurrence-term occ) norm-inputs ledger)
                              (when matched-p
                                (let ((saved (occurrence-saved-bits occ pat subst norm-inputs))
                                      (sub-bits (body-size (tree-occurrence-term occ) norm-inputs)))
                                  (when (or (null best-occ)
                                            (> saved best-saved)
                                            (and (= saved best-saved)
                                                 (< sub-bits best-sub-bits)))
                                    (setf best-occ occ
                                          best-saved saved
                                          best-sub-bits sub-bits)))))))
                        (when best-occ
                          (push best-occ selected))))
             (setf selected (nreverse selected))
             (record-occurrence-selection selected :subexpression)))
         candidate-patterns)
        ;; Price :aligned-root plus top-ranked structural candidates
        (let* ((ordered (stable-sort (nreverse scored-selections)
                                     (lambda (a b)
                                       (> (getf a :struct-score) (getf b :struct-score)))))
               (sub-count 0))
          (dolist (entry ordered)
            (when (or (eq :aligned-root (getf entry :kind))
                      (< sub-count 8))
              (when (eq :subexpression (getf entry :kind))
                (incf sub-count))
              (price-selection entry))))))
    (setf proposals (nreverse proposals))
    (let* ((best-compression
             (first (stable-sort (copy-list proposals)
                                 (lambda (a b)
                                   (or (< (subexpression-abstraction-bits a)
                                          (subexpression-abstraction-bits b))
                                       (and (= (subexpression-abstraction-bits a)
                                               (subexpression-abstraction-bits b))
                                            (> (subexpression-abstraction-structural-score a)
                                               (subexpression-abstraction-structural-score b))))))))
           (non-trivial-abstractions
             (remove-if (lambda (p)
                          (or (member (subexpression-abstraction-kind p) '(:literal :dictionary))
                              (null (subexpression-abstraction-pattern p))
                              (hole-p (subexpression-abstraction-pattern p))))
                        proposals))
           (best-structural
             (or (first (stable-sort (copy-list non-trivial-abstractions)
                                     (lambda (a b)
                                       (or (> (subexpression-abstraction-structural-score a)
                                              (subexpression-abstraction-structural-score b))
                                           (and (= (subexpression-abstraction-structural-score a)
                                                   (subexpression-abstraction-structural-score b))
                                                (< (subexpression-abstraction-bits a)
                                                   (subexpression-abstraction-bits b)))))))
                 best-compression)))
      (values best-compression best-structural proposals corpus active-trees))))

;;; Partitioning, Autonomous View Discovery, and Locality (M7 & M8C)

(defun shuffle-frame-rows (frame permutation &optional ledger)
  "Permute the physical storage order of FRAME's rows according to PERMUTATION
(a bijection of 0..N-1) while preserving declared coordinates and occurrence keys."
  (let* ((rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec)))
    (assert (= n (length permutation)))
    (assert (= n (length (remove-duplicates permutation :test #'eql))))
    (assert (every (lambda (idx) (and (integerp idx) (<= 0 idx) (< idx n))) permutation))
    (charge ledger :orientation n)
    (make-frame (copy-schema (frame-schema frame))
                (loop for idx in permutation
                      for row = (aref rows-vec idx)
                      collect (make-row :key (copy-tree (row-key row))
                                        :known (copy-tree (row-known row))
                                        :requirement (copy-tree (row-requirement row))))
                :pairs (frame-pairs frame)
                :anchors (frame-anchors frame))))

(defstruct partition-view-proposal
  (kind :separate-parts)
  guard
  labels
  partition
  part-models
  model
  conflict
  (bits 0 :type fixnum)
  (run-work 0 :type fixnum))

(defun project-frame-rows (frame bindings &optional ledger)
  "Project FRAME's `row-known` values through BINDINGS (an alist of (child-id . parent-expr))."
  (if (null bindings)
      frame
      (let* ((schema (frame-schema frame))
             (parent-inputs (schema-inputs schema))
             (child-inputs (mapcar (lambda (b)
                                     (cons (car b) (expression-type (cdr b) parent-inputs)))
                                   bindings)))
        (make-frame
         (make-schema :domain (schema-domain schema)
                      :inputs child-inputs
                      :target (schema-target schema)
                      :lookup-p (schema-lookup-p schema))
         (loop for row in (frame-rows frame)
               collect (let ((known
                               (mapcar (lambda (b)
                                         (let ((run (evaluate (cdr b) parent-inputs (row-known row) :ledger ledger)))
                                           (unless (eq :value (evaluation-status run))
                                             (error "View projection binding failed: ~S" run))
                                           (evaluation-value run)))
                                       bindings)))
                         (charge ledger :orientation (length known))
                         (make-row :key (copy-tree (row-key row))
                                   :known known
                                   :requirement (copy-tree (row-requirement row)))))))))

(defun evaluate-guard-partition (frame guard-expr &key child-bindings ledger (budget 100000))
  "Evaluate Boolean GUARD-EXPR on every row of FRAME in the metered VM, split into
TRUE-FRAME and FALSE-FRAME (projected through CHILD-BINDINGS if supplied), and record
the occurrence-preserving `partition` via `partition-rows`.
Returns (VALUES true-frame false-frame labels partition)."
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
  "Solve PART-FRAME via `start-search` (or `start-propagation-search` when PROPAGATION is supplied)
and return the best candidate expression, charging discovery work to LEDGER."
  (if (and propagation (propagation-fallback propagation))
      (let ((psearch (start-propagation-search propagation language)))
        (resume-propagation-search psearch bound work-limit)
        (charge ledger :view-child-search (ledger-total (propagation-search-ledger psearch)))
        (when (propagation-search-best psearch)
          (candidate-expression (propagation-search-best psearch))))
      (let ((job (start-search (if propagation (propagation-frame propagation) part-frame) language)))
        (resume-search job bound work-limit)
        (charge ledger :view-child-search (ledger-total (search-job-ledger job)))
        (when (search-job-best job)
          (candidate-expression (search-job-best job))))))

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

(defun synthesize-supplied-partition-view (frame guard-expr child-language
                                           &key child-bindings child-bound (work-limit 1000000)
                                                decoder child-id child-type solver ledger)
  "Given a supplied Boolean GUARD-EXPR on FRAME:
1. Splits FRAME into TRUE-FRAME and FALSE-FRAME (projected via CHILD-BINDINGS).
2. Immediately checks `frame-conflict-p` on each part (M8C conflict pruning).
3. Recursively synthesizes per-part models to form `:separate-parts` `(if guard M_true M_false)`
   and, when DECODER is supplied, `:shared-decoder` `d(X, (if guard Z_true Z_false))`.
Returns (VALUES proposals conflict-proposal)."
  (let* ((schema (frame-schema frame))
         (parent-inputs (schema-inputs schema))
         (target-type (schema-target schema)))
    (multiple-value-bind (true-frame false-frame labels part)
        (evaluate-guard-partition frame guard-expr :child-bindings child-bindings :ledger ledger)
      (unless (and true-frame false-frame)
        (return-from synthesize-supplied-partition-view (values nil nil)))
      ;; M8C Conflict check on projected subframes
      (let ((conflict (or (frame-conflict-p true-frame :ledger ledger)
                          (frame-conflict-p false-frame :ledger ledger))))
        (when conflict
          (return-from synthesize-supplied-partition-view
            (values nil
                    (make-partition-view-proposal :kind :conflict
                                                  :guard guard-expr
                                                  :labels labels
                                                  :partition part
                                                  :conflict conflict)))))
      (let* ((part-inputs (schema-inputs (frame-schema true-frame)))
             (eff-bound (or child-bound (+ (header-size part-inputs target-type) 48)))
             (proposals nil)
             (true-expr (solve-part-subframe true-frame child-language eff-bound work-limit :ledger ledger))
             (false-expr (when true-expr
                           (solve-part-subframe false-frame child-language eff-bound work-limit :ledger ledger))))
        (when (and true-expr false-expr)
          (let* ((lifted-true (if child-bindings (instantiate true-expr child-bindings :var) true-expr))
                 (lifted-false (if child-bindings (instantiate false-expr child-bindings :var) false-expr))
                 (sep-model (app (op :if target-type) guard-expr lifted-true lifted-false))
                 (sep-bits (description-size sep-model parent-inputs))
                 (sep-work (evaluate-model-run-work sep-model frame ledger)))
            (charge ledger :construction (syntax-work sep-model))
            (when sep-work
              (push (make-partition-view-proposal
                     :kind :separate-parts
                     :guard guard-expr
                     :labels labels
                     :partition part
                     :part-models (list true-expr false-expr)
                     :model sep-model
                     :bits sep-bits
                     :run-work sep-work)
                    proposals))))
        ;; When a shared decoder d(X, Z) is supplied, also synthesize context-dependent child arguments Z_true, Z_false
        (when decoder
          (let* ((eff-child-type (or child-type target-type))
                 (true-parent (make-frame (copy-schema schema)
                                          (loop for row in (frame-rows frame)
                                                for b in labels
                                                when b collect row)))
                 (false-parent (make-frame (copy-schema schema)
                                           (loop for row in (frame-rows frame)
                                                 for b in labels
                                                 unless b collect row)))
                 (true-prop (when solver
                              (propagate-arithmetic-child true-parent decoder child-id child-bindings solver ledger)))
                 (false-prop (when solver
                               (propagate-arithmetic-child false-parent decoder child-id child-bindings solver ledger)))
                 (true-child (if true-prop
                                 (propagation-frame true-prop)
                                 (pullback-frame true-parent decoder child-id eff-child-type child-bindings ledger)))
                 (false-child (if false-prop
                                  (propagation-frame false-prop)
                                  (pullback-frame false-parent decoder child-id eff-child-type child-bindings ledger)))
                 (child-conflict (or (frame-conflict-p true-child :ledger ledger)
                                     (frame-conflict-p false-child :ledger ledger))))
            (if child-conflict
                (return-from synthesize-supplied-partition-view
                  (values (nreverse proposals)
                          (make-partition-view-proposal :kind :conflict
                                                        :guard guard-expr
                                                        :labels labels
                                                        :partition part
                                                        :conflict child-conflict)))
                (let* ((z-inputs (schema-inputs (frame-schema true-child)))
                       (z-lang (make-language (if (eq eff-child-type :int) :int eff-child-type)
                                              z-inputs
                                              :operators (language-operators child-language)
                                              :literals (language-literals child-language)))
                       (z-bound (or child-bound (+ (header-size z-inputs eff-child-type) 48)))
                       (z-true (solve-part-subframe true-child z-lang z-bound work-limit
                                                    :propagation true-prop :ledger ledger))
                       (z-false (when z-true
                                  (solve-part-subframe false-child z-lang z-bound work-limit
                                                       :propagation false-prop :ledger ledger))))
                  (when (and z-true z-false)
                    (let* ((lifted-z-true (if child-bindings (instantiate z-true child-bindings :var) z-true))
                           (lifted-z-false (if child-bindings (instantiate z-false child-bindings :var) z-false))
                           (z-branch (app (op :if eff-child-type) guard-expr lifted-z-true lifted-z-false))
                           (shared-model (instantiate decoder (list (cons child-id z-branch)) :var))
                           (shared-bits (description-size shared-model parent-inputs))
                           (shared-work (evaluate-model-run-work shared-model frame ledger)))
                      (charge ledger :construction (syntax-work shared-model))
                      (when shared-work
                        (push (make-partition-view-proposal
                               :kind :shared-decoder
                               :guard guard-expr
                               :labels labels
                               :partition part
                               :part-models (list z-true z-false)
                               :model shared-model
                               :bits shared-bits
                               :run-work shared-work)
                              proposals))))))))
        (values (nreverse proposals) nil)))))

(defun discover-partition-views (frame guard-language child-language
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
         (bool-frame (make-frame (make-schema :domain (language-domain guard-language)
                                              :inputs parent-inputs
                                              :target :bool)
                                 (loop for row in (frame-rows frame)
                                       collect (make-row :key (copy-tree (row-key row))
                                                         :known (copy-tree (row-known row))
                                                         :requirement (lit :bool t)))))
         (eff-guard-bound (or guard-bound (+ (header-size parent-inputs :bool) 48)))
         (scope (make-observation-scope bool-frame guard-language))
         (obs-job (start-observation-search scope))
         (proposals nil)
         (conflicts nil)
         (seen-partitions (make-hash-table :test #'equal)))
    (resume-observation-search obs-job eff-guard-bound work-limit)
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
            (let* ((members (observation-bucket-members bucket))
                   (best-rec (first (stable-sort (copy-list members) #'<
                                                 :key (lambda (r)
                                                        (description-size (observed-expression-expression r)
                                                                          parent-inputs)))))
                   (guard-expr (observed-expression-expression best-rec)))
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
    (let ((best (first (stable-sort (copy-list proposals)
                                    (lambda (a b)
                                      (or (< (partition-view-proposal-bits a)
                                             (partition-view-proposal-bits b))
                                          (and (= (partition-view-proposal-bits a)
                                                  (partition-view-proposal-bits b))
                                               (< (partition-view-proposal-run-work a)
                                                  (partition-view-proposal-run-work b)))))))))
      (values best proposals conflicts))))
