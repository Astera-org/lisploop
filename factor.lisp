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

(defun match-expr (pattern source &optional inputs ledger)
  (match-pattern pattern source inputs ledger))

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

;;; Operation 2.4: Hard-EM Fiber & Partition Inference (infer-fibers)

(defstruct fiber-class
  (id 0 :type fixnum)
  requirement
  rows
  keys)

(defun fiber-tightness-rank (req)
  "Rank requirements by constraint tightness:
   0 = singleton fiber, 1 = finite set (by cardinality), 2 = general predicate."
  (let ((vals (extract-allowed-values req)))
    (cond
      ((and (listp vals) (= 1 (length vals)))
       (list 0 1 (syntax-work req)))
      ((and (listp vals) (> (length vals) 1))
       (list 1 (length vals) (syntax-work req)))
      (t
       (list 2 0 (syntax-work req))))))

(defun tightness-less-p (rank1 rank2)
  (loop for a in rank1 for b in rank2
        when (/= a b) return (< a b)
        finally (return nil)))

(defun normalize-refined-allowed (target-type requirement)
  "Convert a refined requirement AST back to an explicit finite-allowed when possible."
  (let ((vals (extract-allowed-values requirement)))
    (if (listp vals)
        (finite-allowed target-type vals)
        (predicate-allowed target-type requirement))))

(defun infer-fibers (frame &optional ledger (budget 10000))
  "Hard-EM fiber/partition inference over ambiguous or relational row requirements.
Orders rows by constraint tightness (singletons -> small finite sets -> general predicates),
enforces cannot-links via `conjoin-requirements` folding to `nil`, assigns already-satisfied
rows for free (E-step), and merges/nucleates equivalence classes using coverage-vote
amortized DL cost (M-step).
Returns (VALUES classes labels refined-frame partition)."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (checker-schema (make-schema :inputs (list (cons 0 target-type)) :target :bool))
         (rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec))
         (folded-reqs (make-array n))
         (ranks (make-array n))
         (order (loop for i below n collect i))
         (classes nil)
         (assignments (make-array n :initial-element nil)))
    ;; Pre-fold each row's requirement and compute tightness rank
    (loop for i below n
          for row = (aref rows-vec i)
          for folded = (fold-constants (row-requirement row) checker-schema
                                       :ledger ledger :budget budget)
          do (charge ledger :fiber-inference (syntax-work folded))
             (setf (aref folded-reqs i) folded
                   (aref ranks i) (fiber-tightness-rank folded)))
    ;; Sort row indices in confidence order (tightest constraints first)
    (setf order (stable-sort order (lambda (i j)
                                     (tightness-less-p (aref ranks i) (aref ranks j)))))
    ;; Hard-EM E-step & M-step loop
    (loop for pos from 0
          for idx in order
          for row = (aref rows-vec idx)
          for req = (aref folded-reqs idx)
          for remaining-indices = (nthcdr (1+ pos) order)
          do (if (unsatisfiable-requirement-p req)
                 ;; Unsatisfiable row forms its own conflict class
                 (let ((new-class (make-fiber-class :id (length classes)
                                                    :requirement req
                                                    :rows (list idx)
                                                    :keys (list (row-key row)))))
                   (setf classes (append classes (list new-class))
                         (aref assignments idx) (fiber-class-id new-class)))
                 (let ((best-class nil)
                       (best-joint nil)
                       (best-free-p nil)
                       (best-score nil)
                       (best-votes -1))
                   (dolist (class classes)
                     (charge ledger :fiber-inference)
                     (let ((joint (conjoin-requirements (fiber-class-requirement class) req target-type
                                                        :ledger ledger :budget budget)))
                       ;; Cannot-link check: if joint folds to 'nil, row cannot join this class
                       (unless (unsatisfiable-requirement-p joint)
                         (let* ((old-bits (body-size (fiber-class-requirement class) (list (cons 0 target-type))))
                                (new-bits (body-size joint (list (cons 0 target-type))))
                                (free-p (equal joint (fiber-class-requirement class)))
                                (delta-bits (if free-p 0 (max 0 (- new-bits old-bits))))
                                ;; Coverage votes among remaining unassigned rows
                                (votes (1+ (loop for rem-idx in remaining-indices
                                                 for rem-req = (aref folded-reqs rem-idx)
                                                 count (not (unsatisfiable-requirement-p
                                                             (conjoin-requirements joint rem-req target-type
                                                                                   :ledger ledger :budget budget))))))
                                (amortized-score (/ delta-bits (max 1 votes))))
                           (when (or (null best-class)
                                     (and free-p (not best-free-p))
                                     (and (eq free-p best-free-p)
                                          (or (< amortized-score best-score)
                                              (and (= amortized-score best-score)
                                                   (> votes best-votes)))))
                             (setf best-class class
                                   best-joint joint
                                   best-free-p free-p
                                   best-score amortized-score
                                   best-votes votes))))))
                   (if best-class
                       ;; Merge into best compatible class
                       (progn
                         (setf (fiber-class-requirement best-class) best-joint
                               (fiber-class-rows best-class) (append (fiber-class-rows best-class) (list idx))
                               (fiber-class-keys best-class) (append (fiber-class-keys best-class) (list (row-key row)))
                               (aref assignments idx) (fiber-class-id best-class)))
                       ;; Nucleate a new equivalence class
                       (let ((new-class (make-fiber-class :id (length classes)
                                                          :requirement req
                                                          :rows (list idx)
                                                          :keys (list (row-key row)))))
                         (setf classes (append classes (list new-class))
                               (aref assignments idx) (fiber-class-id new-class)))))))
    ;; Build final labels, refined frame, and row partition
    (let* ((labels (coerce assignments 'list))
           (refined-rows
             (loop for i below n
                   for row = (aref rows-vec i)
                   for cid = (aref assignments i)
                   for class = (nth cid classes)
                   collect (make-row :key (copy-tree (row-key row))
                                     :known (copy-tree (row-known row))
                                     :allowed (normalize-refined-allowed
                                               target-type (fiber-class-requirement class)))))
           (refined-frame (make-frame (copy-schema schema) refined-rows
                                      :pairs (frame-pairs frame) :anchors (frame-anchors frame)))
           (part (partition-rows (frame-rows frame) labels ledger)))
      (values classes labels refined-frame part))))

;;; Operation 4: Heuristic Condensation (condense-heuristic)

(defstruct heuristic-model
  program
  residual
  (exact-p nil :type boolean)
  (program-bits 0 :type fixnum)
  (residual-bits 0 :type fixnum)
  (run-work 0 :type fixnum)
  (score 0))

(defun heuristic-program (model) (heuristic-model-program model))
(defun heuristic-residual (model) (heuristic-model-residual model))
(defun heuristic-score (model) (heuristic-model-score model))

(defun condense-heuristic (frame language &key description-limit (work-limit 100000) (run-weight 0) ledger)
  "Two-stage MDL heuristic synthesis:
1. Run Hard-EM `infer-fibers` on FRAME to resolve ambiguous fibers into narrowed requirements.
2. Enumerate candidate selectors/programs in LANGUAGE up to DESCRIPTION-LIMIT and WORK-LIMIT,
   scoring each candidate by S(program) + S(residual) + run-weight * W_run(program), where
   residual is the exact bit cost of encoding mismatched rows.
3. Return the best `heuristic-model` (whose deployed `program` drops the training residual)."
  (multiple-value-bind (classes labels refined-frame)
      (infer-fibers frame ledger)
    (declare (ignore classes labels))
    (let* ((schema (frame-schema refined-frame))
           (target-type (schema-target schema))
           (inputs (schema-inputs schema))
           (bound (or description-limit (+ (header-size inputs target-type) 18)))
           (scope (make-observation-scope refined-frame language))
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
                                    (let ((chk (check-allowed (row-allowed row)
                                                              (observation-outcome-value outcome)
                                                              :ledger ledger)))
                                      (and (eq :value (evaluation-status chk))
                                           (eq t (evaluation-value chk)))))))
                         (unless satisfied-p
                           (let ((vals (allowed-values (row-allowed row))))
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
                            (< score (heuristic-model-score best-model))
                            (and (= score (heuristic-model-score best-model))
                                 (< prog-bits (heuristic-model-program-bits best-model))))
                    (setf best-model candidate-model)))))))
        best-model))))

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
  (let ((allowed (finite-allowed (sequence-type :bool) (list (law-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work (allowed-expression allowed)))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :law-corpus :known nil :allowed allowed)))))
