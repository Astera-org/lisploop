(in-package #:lisploop)

;;; Residual relations kept as library entries, and their delayed condensation.

(defun relation-key-type (inputs)
  "The type of the key of a table over INPUTS: the single input, or the tuple of them all."
  (if (= 1 (length inputs))
      (cdar inputs)
      (apply #'tuple-type (mapcar #'cdr inputs))))

(defun member-table-p (table inputs target fallback-p)
  "True when TABLE is a set of keys rather than a lookup table. Only a table for a Boolean
TARGET with nothing to fall back on can be one, and then only if no row is `(key boolean)`."
  (and (eq target :bool)
       (not fallback-p)
       (let ((key-type (relation-key-type inputs)))
         (notany (lambda (row)
                   (and (consp row) (= 2 (length row))
                        (value-p (first row) key-type) (typep (second row) 'boolean)))
                 table))))

(defun compose-hybrid-residual-program (inputs target parametric-expr residual-table &key default)
  "Compose a single VM-executable AST from PARAMETRIC-EXPR (or DEFAULT) and RESIDUAL-TABLE.
When RESIDUAL-TABLE is non-empty, guards `:lookup` with `:member` so keys outside the residual
table fall back cleanly to PARAMETRIC-EXPR (or DEFAULT) without raising an unresolved lookup.
The rows of a lookup table are `(key value)` lists; see `member-table-p` for a set of keys."
  (let ((norm-inputs (input-alist inputs))
        (fallback (cond (parametric-expr parametric-expr)
                        ((null default) nil)
                        ((ast-kind default) default)
                        (t (lit target default)))))
    (if (null residual-table)
        fallback
        (let* ((key-type (relation-key-type norm-inputs))
               (vars (loop for (id . type) in norm-inputs collect (var id type)))
               (key (if (= 1 (length vars))
                        (first vars)
                        (apply #'app (op :tuple key-type) vars))))
          (flet ((member-of (keys)
                   (app (op :member key-type) key (lit (sequence-type key-type) keys))))
            (if (member-table-p residual-table norm-inputs target fallback)
                (member-of residual-table)
                (let* ((row-type (tuple-type key-type target))
                       (lookup (app (op :lookup row-type) key
                                    (lit (sequence-type row-type) residual-table))))
                  (if fallback
                      (app (op :if target) (member-of (mapcar #'first residual-table)) lookup fallback)
                      lookup))))))))

(defun register-knowledge-relation (id table &key
                                               (library *knowledge-library*)
                                               domain
                                               inputs
                                               (target :int)
                                               relation-kind
                                               parametric
                                               default
                                               guard
                                               (status :empirical)
                                               edges
                                               metadata
                                               ledger)
  "Register an irreducible table (:LOOKUP map or :MEMBER set, first-order or second-order over :CODE)
or a hybrid (PARAMETRIC + TABLE) residual program as a :RELATION entry in LIBRARY.
A lookup row may be spelled `(key value)` or `(key . value)` and is stored as a list.
RELATION-KIND, when given, must name the kind of table that TABLE is."
  (let* ((norm-inputs (input-alist inputs))
         (member-p (member-table-p table norm-inputs target (or parametric default)))
         (table (if member-p
                    table
                    (mapcar (lambda (row)
                              (if (listp (cdr row))
                                  (list (first row) (second row))
                                  (list (car row) (cdr row))))
                            table)))
         (rel-ast (compose-hybrid-residual-program norm-inputs target parametric table
                                                   :default default)))
    (assert (or (null relation-kind) (null table)
                (eq relation-kind (if member-p :member :lookup))))
    (register-knowledge-entry
     (make-knowledge-entry
      :id (canonical-op-name id)
      :kind :relation
      :domain domain
      :inputs norm-inputs
      :target target
      :expression parametric
      :guard guard
      :residual table
      :auxiliary-code rel-ast
      :status status
      :certificate (list :kind :empirical-table :rows (length table))
      :bits (if rel-ast
                (body-size rel-ast norm-inputs)
                0)
      :edges edges
      :metadata (append (list :table (copy-tree table) :default default)
                        (copy-tree metadata))
      :library library)
     :library library :ledger ledger)))

(defun consolidate-residual-relations (entries library ledger &key language description-limit
                                                               (work-limit 100000))
  "Delayed structure discovery across empirical :RELATION entries in LIBRARY.
1. Within a single relation entry whose residual table has >= 2 first-order rows, check if an
   algebraic expression compresses the residual table with positive MDL gain (delta-S > 0).
2. Across multiple relation entries sharing (inputs, target) that are individually too small
   to justify a parametric rule, pool their residual tables and test whether a shared expression
   jointly compresses the pooled residuals with positive total MDL gain."
  (let ((condensed nil)
        (by-sig (make-hash-table :test #'equal)))
    (labels ((first-order-table-p (inputs target table)
               (and (consp table)
                    (every (lambda (spec) (not (code-type-p (cdr spec)))) inputs)
                    (not (code-type-p target))))
             (table-rows (entry &optional entry-index)
               ;; The rows of ENTRY's table as (row-key known-inputs value).
               (loop with single-p = (= 1 (length (knowledge-entry-inputs entry)))
                     for (key value) in (knowledge-entry-residual entry)
                     for index from 0
                     collect (list (if entry-index (list entry-index index) index)
                                   (if single-p (list key) key)
                                   value)))
             (find-compressing-expr (inputs target domain rows)
               (let* ((eff-domain (or domain :int))
                      (schema (make-schema :domain eff-domain :inputs inputs :target target))
                      (frame (make-frame
                              schema
                              (loop for (key known value) in rows
                                    collect (make-row :key key :known known
                                                      :requirement (singleton-requirement target value)))))
                      (ops (when (or (eq eff-domain :int)
                                     (gf-type-p eff-domain))
                             (list (op :+ eff-domain) (op :* eff-domain))))
                      (lang (or language
                                (make-language eff-domain inputs :operators ops :literals '(0 1 2 3))))
                      (bound (or description-limit (header-bound inputs target 36)))
                      (search (start-search frame lang)))
                 (loop for step from 1 to 20
                       until (search-job-best search)
                       do (resume-search search bound (min work-limit (* step (ceiling work-limit 20)))))
                 (charge ledger :child-search (ledger-total (search-job-ledger search)))
                 (and (search-job-best search)
                      (candidate-expression (search-job-best search)))))
             (condense (entry expression)
               ;; Replace ENTRY's table by EXPRESSION, crediting the bits this saves.
               (let ((bits (body-size expression (knowledge-entry-inputs entry))))
                 (setf (knowledge-entry-gain entry) (- (knowledge-entry-bits entry) bits)
                       (knowledge-entry-expression entry) expression
                       (knowledge-entry-residual entry) nil
                       (knowledge-entry-auxiliary-code entry) expression
                       (knowledge-entry-status entry) :empirical
                       (knowledge-entry-bits entry) bits)
                 (push entry condensed))))
      ;; Pass 1: Individual relation entries and grouping by signature
      (dolist (entry entries)
        (let ((inputs (knowledge-entry-inputs entry))
              (target (knowledge-entry-target entry))
              (table (knowledge-entry-residual entry)))
          (when (and (null (knowledge-entry-expression entry))
                     (first-order-table-p inputs target table))
            (push entry (gethash (list (knowledge-entry-domain entry) inputs target) by-sig))
            (when (>= (length table) 4)
              (let ((best (find-compressing-expr inputs target (knowledge-entry-domain entry)
                                                 (table-rows entry))))
                (when (and best (< (body-size best inputs) (knowledge-entry-bits entry)))
                  (condense entry best)))))))
      ;; Pass 2: Joint pooling across multiple relations with the same (domain, inputs, target)
      (maphash
       (lambda (sig group)
         (let ((remaining (remove-if #'knowledge-entry-expression (reverse group))))
           (when (>= (length remaining) 2)
             (destructuring-bind (domain inputs target) sig
               (let* ((pooled-rows (loop for entry in remaining
                                         for entry-index from 0
                                         append (table-rows entry entry-index)))
                      (best (when (>= (length pooled-rows) 4)
                              (find-compressing-expr inputs target domain pooled-rows))))
                 ;; Entries store independent AST copies; pay for every copy.
                 (when (and best
                            (< (* (length remaining) (body-size best inputs))
                               (reduce #'+ remaining :key #'knowledge-entry-bits)))
                   (dolist (entry remaining)
                     (condense entry best))))))))
       by-sig)
      (when condensed
        (incf (knowledge-library-version library)))
      (nreverse condensed))))

(define-knowledge-kind :relation
  (:priority 25)
  (:validate (entry library)
    (declare (ignore library))
    (let ((inputs (knowledge-entry-inputs entry))
          (target (knowledge-entry-target entry))
          (expression (knowledge-entry-expression entry))
          (table (knowledge-entry-residual entry)))
      (when (and (null (knowledge-entry-auxiliary-code entry)) (or expression table))
        (setf (knowledge-entry-auxiliary-code entry)
              (compose-hybrid-residual-program
               inputs target expression table
               :default (getf (knowledge-entry-metadata entry) :default))))
      (when (knowledge-entry-auxiliary-code entry)
        (assert (equal target (expression-type (knowledge-entry-auxiliary-code entry) inputs))))))
  (:consume (entry context ledger)
    (let ((program (or (knowledge-entry-auxiliary-code entry)
                       (knowledge-entry-expression entry)))
          (inputs (knowledge-entry-inputs entry)))
      (when (and program (= (length context) (length inputs)))
        (evaluate program inputs context :ledger ledger))))
  (:consolidate (entries library ledger)
    (consolidate-residual-relations entries library ledger)))
