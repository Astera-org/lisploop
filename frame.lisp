(in-package #:lisploop)

;;; Module 4: frame.lisp
;;; Frames, S-expression requirements, pullbacks, requirement conjunction,
;;; conflict detection, support frames, partitions, and quotients.

(defstruct (row (:constructor %make-row))
  key
  known
  requirement)

(defstruct (frame (:constructor %make-frame))
  schema
  rows
  pairs
  anchors)

(defun snapshot-frame (frame)
  "Own the problem's mutable data before starting a resumable computation."
  (let ((schema (copy-schema (frame-schema frame))))
    (setf (schema-domain schema) (copy-tree (schema-domain schema))
          (schema-inputs schema) (copy-tree (schema-inputs schema))
          (schema-target schema) (copy-tree (schema-target schema)))
    (make-frame schema
                (mapcar (lambda (row)
                          (make-row :key (copy-tree (row-key row))
                                    :known (copy-tree (row-known row))
                                    :requirement (copy-tree (row-requirement row))))
                        (frame-rows frame))
                :pairs (frame-pairs frame) :anchors (frame-anchors frame))))

(defun extract-slot-constraint (conjunct)
  "If CONJUNCT is `(= (at x0 'idx) 'v)` or `(member (at x0 'idx) '(v1 ... vm))` on tuple var 0,
return (VALUES tuple-type idx allowed-values)."
  (labels ((at-var0-slot (term)
             (when (and (app-p term) (eq :at (operator-name (first term))))
               (let ((base (second term))
                     (idx-node (third term)))
                 (when (and (var-p base) (zerop (ast-id base))
                            (consp (ast-type base)) (eq :tuple (first (ast-type base)))
                            (lit-p idx-node) (integerp (ast-value idx-node))
                            (<= 0 (ast-value idx-node)) (< (ast-value idx-node) (length (rest (ast-type base)))))
                   (values (ast-type base) (ast-value idx-node)))))))
    (cond
      ((and (app-p conjunct) (eq := (operator-name (first conjunct))))
       (let ((lhs (second conjunct))
             (rhs (third conjunct)))
         (multiple-value-bind (ttype idx) (at-var0-slot lhs)
           (if (and ttype (lit-p rhs))
               (values ttype idx (list (ast-value rhs)))
               (multiple-value-bind (ttype2 idx2) (at-var0-slot rhs)
                 (when (and ttype2 (lit-p lhs))
                   (values ttype2 idx2 (list (ast-value lhs)))))))))
      ((and (app-p conjunct) (eq :member (operator-name (first conjunct))))
       (let ((lhs (second conjunct))
             (rhs (third conjunct)))
         (multiple-value-bind (ttype idx) (at-var0-slot lhs)
           (when (and ttype (lit-p rhs))
             (values ttype idx (copy-tree (ast-value rhs)))))))
      (t nil))))

(defun cartesian-product-lists (lists)
  (if (null lists)
      (list nil)
      (let ((rest-prod (cartesian-product-lists (rest lists))))
        (loop for item in (first lists)
              append (mapcar (lambda (tail) (cons item tail)) rest-prod)))))

(defun extract-allowed-values (expression)
  "Extract explicit finite values from `(= x0 'v)`, `(member x0 '(v1 ...))`, `'nil`,
or a complete conjunction of coordinate constraints on `(at x0 'i)`; otherwise return :UNKNOWN."
  (cond
    ((and (lit-p expression) (eq :bool (ast-type expression)) (null (ast-value expression)))
     nil)
    ((and (app-p expression) (eq := (operator-name (first expression))))
     (let ((lhs (first (rest expression)))
           (rhs (second (rest expression))))
       (cond
         ((and (var-p lhs) (zerop (ast-id lhs)) (lit-p rhs))
          (list (ast-value rhs)))
         ((and (lit-p lhs) (var-p rhs) (zerop (ast-id rhs)))
          (list (ast-value lhs)))
         (t :unknown))))
    ((and (app-p expression) (eq :member (operator-name (first expression))))
     (let ((lhs (first (rest expression)))
           (rhs (second (rest expression))))
       (if (and (var-p lhs) (zerop (ast-id lhs)) (lit-p rhs))
           (copy-tree (ast-value rhs))
           :unknown)))
    ((and (app-p expression) (eq :if (operator-name (first expression))))
     (let ((conjuncts (extract-conjuncts expression))
           (tuple-type nil)
           (slots nil))
       (dolist (c conjuncts)
         (multiple-value-bind (ttype idx vals) (extract-slot-constraint c)
           (unless ttype
             (return-from extract-allowed-values :unknown))
           (unless tuple-type
             (setf tuple-type ttype
                   slots (make-array (length (rest ttype)) :initial-element :unbound)))
           (unless (equal tuple-type ttype)
             (return-from extract-allowed-values :unknown))
           (setf (aref slots idx)
                 (if (eq :unbound (aref slots idx))
                     vals
                     (intersection (aref slots idx) vals :test #'equal)))))
       (if (and slots (loop for s across slots never (eq s :unbound)))
           (cartesian-product-lists (coerce slots 'list))
           :unknown)))
    (t :unknown)))

(defun singleton-requirement (type value)
  (assert (value-p value type))
  (app (op := type) (var 0 type) (lit type value)))

(defun set-requirement (type values)
  "An explicit finite set of whole values: tuples are never split into marginal sets."
  (assert (every (lambda (v) (value-p v type)) values))
  (app (op :member type) (var 0 type) (lit (sequence-type type) (copy-tree values))))

(defun make-row (&key key known requirement)
  (assert requirement () "make-row requires :requirement")
  (%make-row :key key :known known :requirement requirement))

(defun make-frame (schema rows &key pairs anchors)
  (assert (valid-type-p (schema-target schema)))
  (assert (valid-inputs-p (schema-inputs schema)))
  (assert (= (length rows) (length (remove-duplicates rows :key #'row-key :test #'equal))))
  (dolist (row rows)
    (assert (= (length (row-known row)) (length (schema-inputs schema))))
    (assert (every (lambda (value spec) (value-p value (cdr spec)))
                   (row-known row) (schema-inputs schema)))
    (assert (eq :bool (expression-type (row-requirement row)
                                       (list (cons 0 (schema-target schema)))))))
  (%make-frame :schema schema :rows (copy-list rows)
               :pairs (copy-tree pairs) :anchors (copy-tree anchors)))

(defun find-var-type (expression &optional (id 0))
  (cond
    ((and (var-p expression) (= id (ast-id expression)))
     (ast-type expression))
    ((app-p expression)
     (some (lambda (child) (find-var-type child id)) (rest expression)))
    (t nil)))

(defun check-requirement (requirement value &key (budget 1000000) ledger type)
  (let ((target-type (or type
                         (find-var-type requirement 0)
                         (when (and (app-p requirement)
                                    (member (operator-name (first requirement)) '(:= :member)))
                           (operator-operand-type (first requirement)))
                         :int)))
    (evaluate requirement (list (cons 0 target-type))
              (list value) :budget budget :ledger ledger)))

(defun conjoin-requirements (req1 req2 target-type &key ledger (budget 10000))
  "Conjoin two row requirements over variable 0 of TARGET-TYPE and fold closed subtrees."
  (let ((schema (make-schema :inputs (list (cons 0 target-type)) :target :bool)))
    (fold-constants (bool-and req1 req2) schema :ledger ledger :budget budget)))

(defstruct (frame-conflict (:predicate frame-conflict-struct-p))
  kind
  keys
  known
  expression)

(defun unsatisfiable-requirement-p (expr)
  (and (lit-p expr) (eq :bool (ast-type expr)) (null (ast-value expr))))

(defun frame-conflict-p (frame &key ledger (budget 10000))
  "Detect whether any row requirement in FRAME folds to `nil` or whether rows
sharing identical known inputs have mutually incompatible requirements."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (checker-schema (make-schema :inputs (list (cons 0 target-type)) :target :bool))
         (by-known (make-hash-table :test #'equal)))
    (dolist (row (frame-rows frame))
      (let* ((req (row-requirement row))
             (folded (fold-constants req checker-schema :ledger ledger :budget budget)))
        (when (unsatisfiable-requirement-p folded)
          (return-from frame-conflict-p
            (make-frame-conflict :kind :unsatisfiable-row
                                 :keys (list (row-key row))
                                 :known (row-known row)
                                 :expression folded)))
        (let ((existing (gethash (row-known row) by-known)))
          (if existing
              (let* ((prev-keys (first existing))
                     (prev-req (second existing))
                     (joint (conjoin-requirements prev-req folded target-type
                                                  :ledger ledger :budget budget)))
                (when (unsatisfiable-requirement-p joint)
                  (return-from frame-conflict-p
                    (make-frame-conflict :kind :incompatible-rows
                                         :keys (append (reverse prev-keys) (list (row-key row)))
                                         :known (row-known row)
                                         :expression joint)))
                (setf (gethash (row-known row) by-known)
                      (list (cons (row-key row) prev-keys) joint)))
              (setf (gethash (row-known row) by-known)
                    (list (list (row-key row)) folded))))))
    nil))

(defun orient-observations (types records input-columns target-columns &key lookup-p ledger)
  "Re-use witnessed (key . values) records; orientation performs no simulation."
  (assert (and target-columns
               (null (intersection input-columns target-columns))))
  (let* ((target (if (rest target-columns)
                     (apply #'tuple-type (mapcar (lambda (i) (nth i types)) target-columns))
                     (nth (first target-columns) types)))
         (schema (make-schema :inputs (mapcar (lambda (i) (cons i (nth i types))) input-columns)
                              :target target :lookup-p lookup-p)))
    (make-frame
     schema
     (loop for (key . values) in records collect
       (progn
         (assert (= (length values) (length types)))
         (assert (every #'value-p values types))
         (charge ledger :orientation (+ 1 (loop for value in values for type in types sum (value-work value type))))
         (make-row :key key :known (mapcar (lambda (i) (nth i values)) input-columns)
                   :requirement (set-requirement
                                 target (list (if (rest target-columns)
                                                  (mapcar (lambda (i) (nth i values)) target-columns)
                                                  (nth (first target-columns) values))))))))))

(defun transition-probes (frame output-type &optional ledger)
  "Reorient recorded singleton state transitions into before/after input probes.
The original frame remains available; this conversion executes no transition."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (requirement (lit :bool t))
         (rows nil) (pairs nil))
    (assert (equal (schema-target schema) (apply #'tuple-type (mapcar #'cdr inputs))))
    (dolist (row (frame-rows frame))
      (let ((targets (extract-allowed-values (row-requirement row)))
            (before-key (list (row-key row) :before))
            (after-key (list (row-key row) :after)))
        (assert (and (listp targets) (= (length targets) 1)) ()
                "Transition probes require a recorded singleton successor")
        (push (make-row :key before-key :known (copy-tree (row-known row))
                        :requirement requirement) rows)
        (push (make-row :key after-key :known (copy-tree (first targets))
                        :requirement requirement) rows)
        (push (list before-key after-key) pairs)
        (charge ledger :orientation
                (+ 2 (loop for spec in inputs for before in (row-known row)
                           for after in (first targets)
                           sum (+ (value-work before (cdr spec)) (value-work after (cdr spec))))))))
    (values (make-frame (make-schema :inputs (copy-tree inputs) :target output-type)
                        (nreverse rows) :pairs (nreverse (copy-tree pairs)))
            (nreverse pairs))))

(defun lookup-model (frame &optional ledger)
  "Package actual available witnesses. Reject unavailable or contradictory tables."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (key-type (apply #'tuple-type (mapcar #'cdr inputs)))
         (entry-type (tuple-type key-type (schema-target schema)))
         (groups nil))
    (assert (schema-lookup-p schema))
    (dolist (row (frame-rows frame))
      (let* ((values (extract-allowed-values (row-requirement row)))
             (old (assoc (row-known row) groups :test #'equal)))
        (when (eq values :unknown) (error "No explicit witnesses for lookup"))
        (charge ledger :baseline (+ 1 (loop for value in values sum (value-work value (schema-target schema)))))
        (if old
            (setf (cdr old) (intersection (cdr old) values :test #'equal))
            (push (cons (row-known row) (copy-list values)) groups))))
    (assert (every #'cdr groups) () "Inconsistent requirements for a lookup key")
    (let ((model (app (op :lookup entry-type)
                      (apply #'app (op :tuple key-type)
                             (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs))
                      (lit (sequence-type entry-type)
                           (mapcar (lambda (group) (list (car group) (second group)))
                                   (reverse groups))))))
      (charge ledger :baseline (syntax-work model))
      model)))

(defun pullback-frame (parent decoder child-id child-type bindings &optional ledger)
  "B(z)=A(d(c,z)). BINDINGS is an alist of child input IDs to parent expressions.
The checker closes over encoded observations; the child receives only computed
bindings. No inverse values are enumerated."
  (let* ((schema (frame-schema parent))
         (inputs (schema-inputs schema))
         (decoder-inputs (acons child-id child-type inputs))
         (child-inputs (mapcar (lambda (b) (cons (car b) (expression-type (cdr b) inputs)))
                               bindings)))
    (assert (not (assoc child-id inputs)))
    (assert (equal (schema-target schema) (expression-type decoder decoder-inputs)))
    (make-frame
     (make-schema :inputs child-inputs :target child-type)
     (loop for row in (frame-rows parent) collect
       (let* ((constants (loop for spec in inputs for value in (row-known row)
                               collect (cons (car spec) (lit (cdr spec) value))))
              (closed-decoder (instantiate decoder
                                           (acons child-id (var 0 child-type) constants) :var))
              (predicate (instantiate (row-requirement row)
                                      (list (cons 0 closed-decoder)) :var))
              (known (mapcar
                      (lambda (binding)
                        (let ((run (evaluate (cdr binding) inputs (row-known row) :ledger ledger)))
                          (unless (eq (evaluation-status run) :value)
                            (error "Context binding did not finish: ~S" run))
                          (evaluation-value run))) bindings)))
         (charge ledger :pullback (syntax-work predicate))
         (make-row :key (row-key row) :known known
                   :requirement predicate))))))

(defun compose-model (decoder child-id child-model bindings &optional ledger)
  "Inline the context and child; the resulting ordinary AST pays for duplication."
  (let ((model (instantiate decoder
                            (list (cons child-id (instantiate child-model bindings :var))) :var)))
    (charge ledger :composition (syntax-work model))
    model))

(defun support-frame (scope-or-frame support &optional ledger)
  "Turn an observed membership residual into an ordinary Boolean synthesis frame.
Every occurrence stays present. The predictor receives only the original inputs."
  (let ((frame (if (frame-p scope-or-frame)
                   scope-or-frame
                   (observation-scope-frame scope-or-frame))))
    (assert (= (length support) (length (frame-rows frame))))
    (assert (every (lambda (value) (value-p value :bool)) support))
    (make-frame
     (make-schema :inputs (copy-tree (schema-inputs (frame-schema frame))) :target :bool)
     (loop for row in (frame-rows frame) for member-p in support collect
       (let ((req (set-requirement :bool (list member-p))))
         (charge ledger :guard-frame
                 (+ 1 (syntax-work req)
                    (loop for value in (row-known row)
                          for input in (schema-inputs (frame-schema frame))
                          sum (value-work value (cdr input)))))
         (make-row :key (copy-tree (row-key row)) :known (copy-tree (row-known row)) :requirement req))))))

(defstruct partition positions groups)

(defun partition-rows (rows labels &optional ledger)
  "A supplied partition, with occurrence positions retained as its reassembly data."
  (assert (= (length rows) (length labels)))
  (let ((keys nil) (positions nil) (groups nil))
    (loop for row in rows for label in labels for index from 0 do
      (let ((part (position label keys :test #'equal)))
        (unless part
          (setf part (length keys) keys (append keys (list label))
                groups (append groups (list nil))))
        (push row (nth part groups))
        (push (list index part) positions)
        (charge ledger :partition (1+ (length keys)))))
    (make-partition :positions (nreverse positions) :groups (mapcar #'nreverse groups))))

(defun reassemble-partition (partition &optional ledger)
  (let* ((groups (mapcar #'copy-list (partition-groups partition)))
         (result (make-array (length (partition-positions partition))))
         (seen (make-hash-table)))
    (dolist (position (partition-positions partition))
      (destructuring-bind (index part) position
        (assert (and (not (gethash index seen)) (< -1 index (length result))
                     (< -1 part (length groups)) (nth part groups)))
        (setf (gethash index seen) t
              (aref result index) (pop (nth part groups)))
        (charge ledger :reassembly)))
    (assert (every #'null groups))
    (coerce result 'list)))

(defun quotient-values (values &optional ledger)
  "Return first-occurrence representatives and the complete occurrence-index residual."
  (let ((representatives nil) (residual nil))
    (dolist (value values)
      (let ((index (position value representatives :test #'equal)))
        (unless index
          (setf index (length representatives)
                representatives (append representatives (list value))))
        (charge ledger :quotient (1+ (length representatives)))
        (push index residual)))
    (values representatives (nreverse residual))))

(defun restore-quotient (representatives residual &optional ledger)
  (let ((length (length representatives)))
    (mapcar (lambda (index)
              (checked-position index length)
              (charge ledger :reassembly)
              (nth index representatives)) residual)))

(defun quotient-model (type representatives residual &optional ledger)
  "Construct a reconstructing program charging representatives AND occurrence indexes:
when RESIDUAL is a sequence of integer indices, emits batch `(gather 'R 'residual)`;
when RESIDUAL is an `:int` AST expression, emits per-row `(at 'R residual)`."
  (let ((model (if (ast-kind residual)
                   (app (op :at (sequence-type type))
                        (lit (sequence-type type) representatives)
                        residual)
                   (app (op :gather type)
                        (lit (sequence-type type) representatives)
                        (lit (sequence-type :int) residual)))))
    (charge ledger :construction (syntax-work model))
    model))

(defun partition-model (partition type &optional ledger)
  "Encode all part contents and their inverse permutation, including duplicate values."
  (reassemble-partition partition ledger)
  (let* ((groups (partition-groups partition))
         (offsets (loop with offset = 0 for group in groups
                        collect (prog1 offset (incf offset (length group)))))
         (cursors (make-array (length groups) :initial-element 0))
         (permutation (make-array (length (partition-positions partition)))))
    (dolist (position (partition-positions partition))
      (destructuring-bind (index part) position
        (setf (aref permutation index) (+ (nth part offsets) (aref cursors part)))
        (incf (aref cursors part))))
    (quotient-model type (apply #'append groups) (coerce permutation 'list) ledger)))

(defun partition-pairs-and-anchors (partition-or-rows &optional labels ledger)
  "Derive intra-block must-agree `pairs` and cross-block must-vary `anchors` from a
`partition` (or from PARTITION-OR-ROWS and LABELS via `partition-rows`).
Each block G_k with >= 2 rows contributes a chain of adjacent key pairs
`((k_{k,0} k_{k,1}) (k_{k,1} k_{k,2}) ...)` and representative anchor `k_{k,0}`.
Returns (VALUES pairs anchors partition)."
  (let* ((part (if (partition-p partition-or-rows)
                   partition-or-rows
                   (partition-rows (if (frame-p partition-or-rows)
                                       (frame-rows partition-or-rows)
                                       partition-or-rows)
                                   labels ledger)))
         (pairs nil)
         (anchors nil))
    (dolist (group (partition-groups part))
      (let ((keys (mapcar (lambda (item) (if (row-p item) (row-key item) item)) group)))
        (when (>= (length keys) 2)
          (push (copy-tree (first keys)) anchors)
          (loop for (a b) on keys
                while b
                do (charge ledger :orientation)
                   (push (list (copy-tree a) (copy-tree b)) pairs)))))
    (setf pairs (nreverse pairs)
          anchors (if (>= (length anchors) 2) (nreverse anchors) nil))
    (values pairs anchors part)))

(defun with-frame-linkage (frame &key pairs anchors partition labels ledger)
  "Construct a new `frame` over FRAME's schema and rows carrying updated `:pairs`
and `:anchors` (either supplied directly or derived from `:partition` / `:labels`
via `partition-pairs-and-anchors`)."
  (multiple-value-bind (derived-pairs derived-anchors)
      (if (or partition labels)
          (partition-pairs-and-anchors (or partition (frame-rows frame)) labels ledger)
          (values nil nil))
    (let ((eff-pairs (or pairs derived-pairs))
          (eff-anchors (or anchors derived-anchors)))
      (charge ledger :orientation (length (frame-rows frame)))
      (make-frame (copy-schema (frame-schema frame))
                  (mapcar (lambda (row)
                            (make-row :key (copy-tree (row-key row))
                                      :known (copy-tree (row-known row))
                                      :requirement (copy-tree (row-requirement row))))
                          (frame-rows frame))
                  :pairs eff-pairs
                  :anchors eff-anchors))))
