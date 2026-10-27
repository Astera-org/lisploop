(in-package #:lisploop)

(defstruct schema inputs target (lookup-p nil))
(defstruct row key known allowed)
(defstruct (frame (:constructor %make-frame)) schema rows)
(defstruct (allowed (:constructor %make-allowed)) type expression (values :unknown))

(defun finite-allowed (type values)
  "An explicit set of whole values: tuples are never split into marginal sets."
  (assert (every (lambda (v) (value-p v type)) values))
  (%make-allowed :type type :values (copy-tree values)
                 :expression (app (op :member type) (var 0 type)
                                  (lit (sequence-type type) values))))

(defun predicate-allowed (type expression)
  "A typed checker AST with only variable 0 (the proposed value) free."
  (assert (eq :bool (expression-type expression (list (cons 0 type)))))
  (%make-allowed :type type :expression (copy-tree expression)))

(defun make-frame (schema rows)
  (assert (valid-type-p (schema-target schema)))
  (assert (= (length (schema-inputs schema))
             (length (remove-duplicates (schema-inputs schema) :key #'car))))
  (assert (every (lambda (spec)
                   (and (integerp (car spec)) (>= (car spec) 0)
                        (valid-type-p (cdr spec)))) (schema-inputs schema)))
  (assert (= (length rows) (length (remove-duplicates rows :key #'row-key :test #'equal))))
  (dolist (row rows)
    (assert (= (length (row-known row)) (length (schema-inputs schema))))
    (assert (every (lambda (value spec) (value-p value (cdr spec)))
                   (row-known row) (schema-inputs schema)))
    (assert (equal (schema-target schema) (allowed-type (row-allowed row)))))
  (%make-frame :schema schema :rows (copy-list rows)))

(defun check-allowed (allowed value &key (budget 1000000) ledger)
  (evaluate (allowed-expression allowed) (list (cons 0 (allowed-type allowed)))
            (list value) :budget budget :ledger ledger))

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
         (charge ledger :orientation (+ 1 (length values)))
         (make-row :key key :known (mapcar (lambda (i) (nth i values)) input-columns)
                   :allowed (finite-allowed
                             target (list (if (rest target-columns)
                                              (mapcar (lambda (i) (nth i values)) target-columns)
                                              (nth (first target-columns) values))))))))))

(defun lookup-model (frame &optional ledger)
  "Package actual available witnesses. Reject unavailable or contradictory tables."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (key-type (apply #'tuple-type (mapcar #'cdr inputs)))
         (entry-type (tuple-type key-type (schema-target schema)))
         (groups nil))
    (assert (schema-lookup-p schema))
    (dolist (row (frame-rows frame))
      (let* ((values (allowed-values (row-allowed row)))
             (old (assoc (row-known row) groups :test #'equal)))
        (when (eq values :unknown) (error "No explicit witnesses for lookup"))
        (charge ledger :baseline (+ 1 (length values)))
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
      (charge ledger :baseline (description-size model))
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
              (predicate (instantiate (allowed-expression (row-allowed row))
                                      (list (cons 0 closed-decoder)) :var))
              (known (mapcar
                      (lambda (binding)
                        (let ((run (evaluate (cdr binding) inputs (row-known row) :ledger ledger)))
                          (unless (eq (evaluation-status run) :value)
                            (error "Context binding did not finish: ~S" run))
                          (evaluation-value run))) bindings)))
         (charge ledger :pullback (description-size predicate))
         (make-row :key (row-key row) :known known
                   :allowed (predicate-allowed child-type predicate)))))))

(defun compose-model (decoder child-id child-model bindings &optional ledger)
  "Inline the context and child; the resulting ordinary AST pays for duplication."
  (let ((model (instantiate decoder
                            (list (cons child-id (instantiate child-model bindings :var))) :var)))
    (charge ledger :composition (description-size model))
    model))

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
  (mapcar (lambda (index)
            (assert (and (integerp index) (< -1 index (length representatives))))
            (charge ledger :reassembly)
            (nth index representatives)) residual))

(defun quotient-model (type representatives residual &optional ledger)
  "A closed reconstructing program, charging representatives AND occurrence indexes."
  (let ((model (app (op :gather type) (lit (sequence-type type) representatives)
                    (lit (sequence-type :index) residual))))
    (charge ledger :construction (description-size model))
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
