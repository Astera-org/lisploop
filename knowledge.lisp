(in-package #:lisploop)

;;; The persistent knowledge library: one flat, append-ordered list of typed entries with
;;; relational edges, the kinds that give entries their behaviour, and the function table
;;; the VM dispatches on. Each library owns its function table.

;;; Kinds

(defstruct knowledge-kind-spec
  name
  (priority 50 :type fixnum)
  validate-fn
  install-fn
  consume-fn
  consolidate-fn)

(defvar *knowledge-kind-specs* nil
  "Priority-ordered list of declarative `knowledge-kind-spec` definitions.")

(defvar *consolidation-options* nil
  "Keyword options of the `consolidate-knowledge-library` call in progress, for the
:consolidate hooks that take any (:min-gain, :library-names).")

(defun find-knowledge-kind-spec (kind)
  (find (canonical-op-name kind) *knowledge-kind-specs*
        :key #'knowledge-kind-spec-name :test #'eq))

(defun knowledge-kind-priority (kind)
  "Install and consolidation order of KIND; unregistered kinds sort in the middle."
  (let ((spec (find-knowledge-kind-spec kind)))
    (if spec (knowledge-kind-spec-priority spec) 50)))

(defmacro define-knowledge-kind (name &body clauses)
  "Declaratively register a knowledge kind in `*knowledge-kind-specs*`.
Supported clauses:
  (:priority fixnum)
  (:validate (entry library) &body body)
  (:install (entry library ledger) &body body)
  (:consume (entry context ledger) &body body)
  (:consolidate (entries library ledger) &body body)
A kind without a :consume clause is consumed by evaluating its expression on the context."
  (flet ((hook (key)
           (let ((clause (assoc key clauses)))
             (when clause `(lambda ,(second clause) ,@(cddr clause))))))
    (let ((kind (canonical-op-name name)))
      `(let ((spec (make-knowledge-kind-spec
                    :name ,kind
                    :priority ,(or (second (assoc :priority clauses)) 50)
                    :validate-fn ,(hook :validate)
                    :install-fn ,(hook :install)
                    :consume-fn ,(hook :consume)
                    :consolidate-fn ,(hook :consolidate))))
         (setf *knowledge-kind-specs*
               (stable-sort (cons spec (remove ,kind *knowledge-kind-specs*
                                               :key #'knowledge-kind-spec-name :test #'eq))
                            #'< :key #'knowledge-kind-spec-priority))
         ',kind))))

;;; Entries and libraries

(defstruct descriptor-clause
  id
  (facet :shape-delta)
  (tier 1 :type fixnum)
  (status :empirical)
  (weight-bits 2 :type fixnum)
  (work-cost 1 :type fixnum))

(defstruct (knowledge-entry (:constructor %make-knowledge-entry))
  id
  kind
  (domain :int)
  inputs
  target
  expression
  guard
  trigger
  residual
  auxiliary-code
  (status :empirical)
  certificate
  (bits 0 :type fixnum)
  (gain 0 :type fixnum)
  (work 0 :type fixnum)
  edges
  metadata
  executable)

(defstruct (knowledge-library (:constructor %make-knowledge-library))
  (version 0 :type fixnum)
  entries
  (by-id (make-hash-table :test #'eq))
  (by-kind (make-hash-table :test #'eq))
  (incoming-edges (make-hash-table :test #'eq))
  ;; The library's function table. While the library is active these are the values of
  ;; `*function-definitions*`, `*registered-function-names*` and `*de-novo-function-counter*`;
  ;; the two stored slots are brought up to date when the library stops being active.
  (functions (make-hash-table :test #'eq))
  stored-function-names
  (stored-de-novo-counter 0 :type fixnum)
  (rewrite-libraries (make-hash-table :test #'equal))
  (propagator-libraries (make-hash-table :test #'equal))
  (compositional-index (make-hash-table :test #'eq))
  priority-predictor
  (entry-counter 0 :type fixnum))

(defun make-knowledge-library ()
  (%make-knowledge-library))

(defvar *knowledge-library* (%make-knowledge-library :functions *function-definitions*)
  "Active persistent store of synthesized functions, laws, algebras, solvers, descriptors, relations, and heuristics.")

(defvar *knowledge-entry-owners* (make-hash-table :test #'eq :weakness :key))

(defvar *syncing-knowledge-library-p* nil
  "True while a function definition is being installed from its library entry, so that
defining it does not register the entry again.")

;;; Activation: the active library's function table is the VM's

(defun knowledge-library-function-names (library)
  "The function names registered in LIBRARY's table, in registration order."
  (if (eq library *knowledge-library*)
      *registered-function-names*
      (knowledge-library-stored-function-names library)))

(defun knowledge-library-de-novo-counter (library)
  (if (eq library *knowledge-library*)
      *de-novo-function-counter*
      (knowledge-library-stored-de-novo-counter library)))

(defun refresh-function-operators ()
  "Bring cached operator and application metadata in line with the active function table:
an operator's encoded size depends on its position among the registered names, and an
application's totality on the active definitions."
  (dolist (name *registered-function-names*)
    (when (find-function-definition name)
      (op name)))
  (invalidate-app-meta))

(defun call-with-knowledge-library (library thunk)
  "Call THUNK with LIBRARY active: `*knowledge-library*` is LIBRARY and the VM dispatches on
LIBRARY's own function table. The table is shared, not copied, so definitions made inside
persist in LIBRARY and the outer library's table is untouched."
  (if (eq library *knowledge-library*)
      (funcall thunk)
      (let ((outer *knowledge-library*))
        (assert (eq *function-definitions* (knowledge-library-functions outer)))
        ;; The outer library stops being active: park its live table values in its slots.
        (setf (knowledge-library-stored-function-names outer) *registered-function-names*
              (knowledge-library-stored-de-novo-counter outer) *de-novo-function-counter*)
        (unwind-protect
             (let ((*knowledge-library* library)
                   (*function-definitions* (knowledge-library-functions library))
                   (*registered-function-names* (knowledge-library-stored-function-names library))
                   (*de-novo-function-counter* (knowledge-library-stored-de-novo-counter library)))
               (refresh-function-operators)
               (unwind-protect (funcall thunk)
                 (setf (knowledge-library-stored-function-names library) *registered-function-names*
                       (knowledge-library-stored-de-novo-counter library) *de-novo-function-counter*)))
          (refresh-function-operators)))))

(defmacro with-knowledge-library ((library) &body body)
  "Execute BODY with LIBRARY active; see `call-with-knowledge-library`."
  `(call-with-knowledge-library ,library (lambda () ,@body)))

(defun invalidate-knowledge-caches (library)
  (clrhash (knowledge-library-rewrite-libraries library))
  (clrhash (knowledge-library-propagator-libraries library))
  (incf (knowledge-library-version library)))

;;; Entries

(defun next-knowledge-entry-id (&optional (library *knowledge-library*) (kind :entry))
  "Allocate a fresh canonical keyword ID (e.g. :LAW-0, :SOLVER-1, :REL-2) in LIBRARY."
  (let ((prefix (symbol-name (canonical-op-name kind))))
    (loop
      (let* ((idx (knowledge-library-entry-counter library))
             (cand (keyword-id "~A-~D" prefix idx)))
        (incf (knowledge-library-entry-counter library))
        (unless (gethash cand (knowledge-library-by-id library))
          (return cand))))))

(defun make-knowledge-entry (&key id kind domain inputs target expression guard trigger
                                  residual auxiliary-code (status :empirical) certificate
                                  (bits 0) (gain 0) (work 0) edges metadata
                                  (library *knowledge-library*))
  "Construct a canonical `knowledge-entry` with normalized schema and edge links.
By default the domain is inferred from the types, the guard is true, and BITS is the body
size of EXPRESSION."
  (let* ((kkind (canonical-op-name kind))
         (norm-inputs (copy-tree (input-alist inputs)))
         (norm-target (copy-tree (or target (and (schema-p inputs) (schema-target inputs)) :int)))
         (inferred-domain (or domain
                              (and (schema-p inputs) (schema-domain inputs))
                              (infer-domain-from-types (cons norm-target (mapcar #'cdr norm-inputs)))))
         (kid (if id
                  (canonical-op-name id)
                  (if library
                      (next-knowledge-entry-id library kkind)
                      (keyword-id "~A-0" kkind)))))
    (%make-knowledge-entry
     :id kid
     :kind kkind
     :domain (copy-tree inferred-domain)
     :inputs norm-inputs
     :target norm-target
     :expression expression
     :guard (or guard (lit :bool t))
     :trigger trigger
     :residual residual
     :auxiliary-code auxiliary-code
     :status status
     :certificate certificate
     :bits (if (and (zerop bits) expression)
               (body-size expression norm-inputs)
               bits)
     :gain gain
     :work work
     :edges (copy-tree edges)
     :metadata (copy-tree metadata))))

(defun assert-entry-expression-type (entry)
  "The usual :validate check: ENTRY's expression has ENTRY's target type under its inputs."
  (assert (equal (knowledge-entry-target entry)
                 (expression-type (knowledge-entry-expression entry)
                                  (knowledge-entry-inputs entry)))))

(defun find-knowledge-entry (id &optional (library *knowledge-library*))
  "Look up a `knowledge-entry` by ID in LIBRARY in O(1) time."
  (when (and id library)
    (gethash (canonical-op-name id) (knowledge-library-by-id library))))

(defun knowledge-entry-compositional-name (entry)
  "Return the secondary compositional descriptor address keyword for ENTRY, or NIL."
  (when (knowledge-entry-p entry)
    (getf (knowledge-entry-metadata entry) :compositional-name)))

(defun (setf knowledge-entry-compositional-name) (value entry)
  (when (knowledge-entry-p entry)
    (setf (getf (knowledge-entry-metadata entry) :compositional-name)
          (and value (canonical-op-name value)))))

(defun knowledge-entry-descriptor-profile (entry)
  "Return the list of `descriptor-clause` records for ENTRY."
  (when (knowledge-entry-p entry)
    (getf (knowledge-entry-metadata entry) :descriptor-profile)))

(defun (setf knowledge-entry-descriptor-profile) (value entry)
  (when (knowledge-entry-p entry)
    (setf (getf (knowledge-entry-metadata entry) :descriptor-profile) value)))

(defun find-knowledge-entries-by-address (address &optional (library *knowledge-library*))
  "Look up `knowledge-entry` items in LIBRARY by secondary compositional address or descriptor ID."
  (when (and address library)
    (copy-list (gethash (canonical-op-name address)
                        (knowledge-library-compositional-index library)))))

(defun knowledge-entries-of-kind (kind &optional (library *knowledge-library*))
  "Return the chronological list of `knowledge-entry` items of KIND in LIBRARY."
  (when library
    (copy-list (gethash (canonical-op-name kind) (knowledge-library-by-kind library)))))

(defun knowledge-edges-from (id &optional edge-key (library *knowledge-library*))
  "Return outgoing edges from entry ID (optionally filtered by EDGE-KEY)."
  (let ((entry (if (knowledge-entry-p id) id (find-knowledge-entry id library))))
    (when entry
      (if edge-key
          (let ((kkey (canonical-op-name edge-key)))
            (remove-if-not (lambda (e) (and (consp e) (eq kkey (first e))))
                           (knowledge-entry-edges entry)))
          (copy-tree (knowledge-entry-edges entry))))))

(defun knowledge-edges-to (target-id &optional edge-key (library *knowledge-library*))
  "Return incoming `(edge-key source-id ...)` links pointing to TARGET-ID."
  (when library
    (let* ((ktarg (canonical-op-name target-id))
           (incoming (gethash ktarg (knowledge-library-incoming-edges library))))
      (if edge-key
          (let ((kkey (canonical-op-name edge-key)))
            (remove-if-not (lambda (e) (eq kkey (first e))) incoming))
          (copy-list incoming)))))

;;; Lookup tables derived from the entry list

(defun index-knowledge-edge (entry edge library)
  "Record EDGE of ENTRY under each of its symbolic targets in LIBRARY's incoming-edge table."
  (dolist (target (rest edge))
    (when (symbolp target)
      (pushnew (list (first edge) (knowledge-entry-id entry))
               (gethash (canonical-op-name target) (knowledge-library-incoming-edges library))
               :test #'equal))))

(defun add-knowledge-edge (source edge-key &rest targets)
  "Attach a relational edge `(EDGE-KEY . TARGETS)` to `knowledge-entry` SOURCE (or ID in `*knowledge-library*`)."
  (let* ((entry (if (knowledge-entry-p source)
                    source
                    (find-knowledge-entry source *knowledge-library*)))
         (edge (cons (canonical-op-name edge-key)
                     (mapcar (lambda (x) (if (symbolp x) (canonical-op-name x) x)) targets))))
    (assert entry () "Unknown knowledge-entry ~S" source)
    (unless (member edge (knowledge-entry-edges entry) :test #'equal)
      (setf (knowledge-entry-edges entry)
            (append (knowledge-entry-edges entry) (list edge)))
      (let ((owner (or (gethash entry *knowledge-entry-owners*) *knowledge-library*)))
        (when owner
          (index-knowledge-edge entry edge owner)
          (invalidate-knowledge-caches owner))))
    entry))

(defun index-knowledge-entry-compositional-address (entry library)
  "Register ENTRY under its secondary compositional name and each descriptor clause ID in LIBRARY."
  (let ((idx (knowledge-library-compositional-index library)))
    (when (knowledge-entry-compositional-name entry)
      (pushnew entry (gethash (canonical-op-name (knowledge-entry-compositional-name entry)) idx)
               :test #'eq))
    (dolist (clause (knowledge-entry-descriptor-profile entry))
      (when (and (descriptor-clause-p clause) (descriptor-clause-id clause))
        (pushnew entry (gethash (canonical-op-name (descriptor-clause-id clause)) idx) :test #'eq)))))

(defun clear-knowledge-indexes (library)
  (dolist (table (list (knowledge-library-by-id library)
                       (knowledge-library-by-kind library)
                       (knowledge-library-incoming-edges library)
                       (knowledge-library-rewrite-libraries library)
                       (knowledge-library-propagator-libraries library)
                       (knowledge-library-compositional-index library)))
    (clrhash table))
  (setf (knowledge-library-priority-predictor library) nil))

(defun index-knowledge-entry (entry library)
  "Enter ENTRY into LIBRARY's lookup tables. Its kind's install hook runs separately."
  (let ((kind (knowledge-entry-kind entry)))
    (setf (gethash entry *knowledge-entry-owners*) library
          (gethash (knowledge-entry-id entry) (knowledge-library-by-id library)) entry
          (gethash kind (knowledge-library-by-kind library))
          (append (gethash kind (knowledge-library-by-kind library)) (list entry)))
    (dolist (edge (knowledge-entry-edges entry))
      (when (consp edge)
        (index-knowledge-edge entry edge library)))
    (index-knowledge-entry-compositional-address entry library)))

(defun unindex-knowledge-entry (entry library)
  "Withdraw everything ENTRY contributed to LIBRARY's lookup tables."
  (let ((id (knowledge-entry-id entry))
        (kind (knowledge-entry-kind entry))
        (incoming (knowledge-library-incoming-edges library))
        (addresses (knowledge-library-compositional-index library)))
    (remhash id (knowledge-library-by-id library))
    (setf (gethash kind (knowledge-library-by-kind library))
          (remove id (gethash kind (knowledge-library-by-kind library)) :key #'knowledge-entry-id))
    (maphash (lambda (target edges)
               (setf (gethash target incoming) (remove id edges :key #'second)))
             incoming)
    (maphash (lambda (address entries)
               (when (member entry entries :test #'eq)
                 (setf (gethash address addresses) (remove entry entries :test #'eq))))
             addresses)
    (remhash entry *knowledge-entry-owners*)))

(declaim (ftype function sync-entry-executable consume-entry-executable))

(defun install-knowledge-entry (entry library ledger)
  "Run the install hook of ENTRY's kind, synchronize its derived executable cache, and index any
compositional descriptor addresses attached."
  (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry)))
        (*syncing-knowledge-library-p* t))
    (when (and spec (knowledge-kind-spec-install-fn spec))
      (funcall (knowledge-kind-spec-install-fn spec) entry library ledger)))
  (sync-entry-executable entry)
  (index-knowledge-entry-compositional-address entry library))

(defun rebuild-knowledge-library-indexes (&optional (library *knowledge-library*) ledger)
  "Rebuild all derived O(1) lookup tables in LIBRARY from its flat `entries` list,
running each kind's `:install` hook in priority order."
  (call-with-knowledge-library library
    (lambda ()
      (clear-knowledge-indexes library)
      ;; A definition without a :function entry has nothing to be rebuilt from: drop it.
      (let ((function-ids (loop for entry in (knowledge-library-entries library)
                                when (eq :function (knowledge-entry-kind entry))
                                  collect (knowledge-entry-id entry))))
        (dolist (name (copy-list *registered-function-names*))
          (unless (member name function-ids)
            (remhash name *function-definitions*)
            (setf *registered-function-names* (remove name *registered-function-names*))))
        (invalidate-app-meta))
      (dolist (entry (knowledge-library-entries library))
        (index-knowledge-entry entry library))
      (dolist (entry (stable-sort (copy-list (knowledge-library-entries library)) #'<
                                  :key (lambda (entry)
                                         (knowledge-kind-priority (knowledge-entry-kind entry)))))
        (install-knowledge-entry entry library ledger))
      (incf (knowledge-library-version library))))
  library)

(defun register-knowledge-entry (entry &key (library *knowledge-library*) ledger)
  "Validate, install, and index `knowledge-entry` ENTRY into LIBRARY via its declarative kind spec.
An entry with the same ID is replaced in place in the entry list."
  (call-with-knowledge-library library
    (lambda ()
      (let* ((kind (knowledge-entry-kind entry))
             (id (knowledge-entry-id entry))
             (spec (find-knowledge-kind-spec kind))
             (existing (gethash id (knowledge-library-by-id library))))
        (when (and spec (knowledge-kind-spec-validate-fn spec))
          (funcall (knowledge-kind-spec-validate-fn spec) entry library))
        (cond (existing
               (when (and (not (eq (knowledge-entry-kind existing) kind))
                          (member (knowledge-entry-kind existing) '(:function :decoder-template)))
                 (dolist (edge (copy-list (knowledge-edges-to id :describes library)))
                   (let ((d (find-knowledge-entry (second edge) library)))
                     (when (and d (eq :descriptor (knowledge-entry-kind d))
                                (getf (knowledge-entry-metadata d) :auto-descriptor)
                                (equal (list (list :describes id))
                                       (knowledge-edges-from d :describes library)))
                       (unindex-knowledge-entry d library)
                       (setf (knowledge-library-entries library)
                             (delete d (knowledge-library-entries library) :test #'eq))))))
               (unindex-knowledge-entry existing library)
               (when (and (eq :function (knowledge-entry-kind existing)) (not (eq :function kind)))
                 (remhash id *function-definitions*)
                 (setf *registered-function-names* (remove id *registered-function-names*)))
               (setf (knowledge-library-entries library)
                     (substitute entry existing (knowledge-library-entries library) :test #'eq)))
              (t
               (setf (knowledge-library-entries library)
                     (append (knowledge-library-entries library) (list entry)))))
        (index-knowledge-entry entry library)
        (install-knowledge-entry entry library ledger)
        (invalidate-knowledge-caches library)
        entry))))

(defun remove-knowledge-entry (id &optional (library *knowledge-library*) ledger)
  "Remove entry ID (and any auto-derived descriptors describing only ID) from LIBRARY."
  (let* ((kid (canonical-op-name id))
         (existing (find-knowledge-entry kid library)))
    (when existing
      (setf (knowledge-library-entries library)
            (remove-if (lambda (e)
                         (or (eq e existing)
                             (and (eq :descriptor (knowledge-entry-kind e))
                                  (getf (knowledge-entry-metadata e) :auto-descriptor)
                                  (equal (list (list :describes kid))
                                         (knowledge-edges-from e :describes library)))))
                       (knowledge-library-entries library)))
      (remhash existing *knowledge-entry-owners*)
      (rebuild-knowledge-library-indexes library ledger)
      t)))

(defun consume-knowledge-entry (entry-or-id context &key (library *knowledge-library*) ledger)
  "Evaluate or consume ENTRY-OR-ID on CONTEXT using its `define-knowledge-kind` `:consume` hook.
A kind without one is consumed via ENTRY's synchronized executable cache."
  (call-with-knowledge-library library
    (lambda ()
      (let ((entry (if (knowledge-entry-p entry-or-id)
                       entry-or-id
                       (find-knowledge-entry entry-or-id library))))
        (when entry
          (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry))))
            (if (and spec (knowledge-kind-spec-consume-fn spec))
                (funcall (knowledge-kind-spec-consume-fn spec) entry context ledger)
                (consume-entry-executable entry context ledger))))))))

(defun clear-knowledge-library (&optional (library *knowledge-library*))
  "Reset LIBRARY to an empty knowledge store with an empty function table."
  (call-with-knowledge-library library
    (lambda ()
      (setf (knowledge-library-entries library) nil
            (knowledge-library-entry-counter library) 0)
      (clear-knowledge-indexes library)
      (let ((*syncing-knowledge-library-p* t))
        (clear-function-definitions))
      (incf (knowledge-library-version library))))
  library)

;;; The function table

(defun recompute-registered-functions-totality ()
  "Recompute totality and conditional-code-params across all registered functions until fixed point."
  (invalidate-app-meta)
  (loop
    (let ((changed-p nil))
      (dolist (fname *registered-function-names*)
        (let ((fdef (find-function-definition fname)))
          (when fdef
            (multiple-value-bind (new-total new-cond)
                (if (function-definition-oracle-table fdef)
                    (values nil nil)
                    (analyze-function-body-totality fname
                                                    (function-definition-inputs fdef)
                                                    (function-definition-body fdef)))
              (unless (and (eq new-total (function-definition-total-p fdef))
                           (equal new-cond (function-definition-conditional-code-params fdef)))
                (setf (function-definition-total-p fdef) new-total
                      (function-definition-conditional-code-params fdef) new-cond
                      changed-p t))))))
      (if changed-p
          (invalidate-app-meta)
          (return))))
  (dolist (fname *registered-function-names*)
    (let ((fdef (find-function-definition fname)))
      (when (and fdef (function-definition-body fdef))
        (ensure-ast-meta (function-definition-body fdef))))))

(defun record-function-entry (library def)
  "Keep LIBRARY's :function entry for DEF in step with the definition. Oracle-backed and
bodiless definitions are working state of a synthesis in progress and get no entry."
  (let ((kname (function-definition-name def))
        (body (function-definition-body def)))
    (when (and body (null (function-definition-oracle-table def)))
      (let* ((existing (find-knowledge-entry kname library))
             (inputs (function-definition-inputs def))
             (ret (function-definition-return-type def))
             ;; Programs attached to the old entry describe its body, so they survive only
             ;; when the definition is unchanged.
             (same-definition (and existing
                                   (equal inputs (knowledge-entry-inputs existing))
                                   (equal ret (knowledge-entry-target existing))
                                   (equal body (knowledge-entry-expression existing)))))
        (register-knowledge-entry
         (make-knowledge-entry
          :id kname
          :kind :function
          :inputs inputs
          :target ret
          :expression body
          :trigger (and same-definition (knowledge-entry-trigger existing))
          :residual (and same-definition (knowledge-entry-residual existing))
          :auxiliary-code (and same-definition (knowledge-entry-auxiliary-code existing))
          :status (if (or (function-definition-total-p def)
                          (function-definition-conditional-code-params def))
                      :validated
                      :empirical)
          :certificate (or (and same-definition (knowledge-entry-certificate existing))
                           (when (function-definition-total-p def)
                             '(:kind :structural-totality)))
          :gain (if existing (knowledge-entry-gain existing) 0)
          :work (if existing (knowledge-entry-work existing) (syntax-work body))
          :edges (and existing (knowledge-entry-edges existing))
          :metadata (list :total-p (function-definition-total-p def)
                          :conditional-code-params
                          (copy-list (function-definition-conditional-code-params def)))
          :library library)
         :library library)))))

(defun define-function (name inputs return-type body &key oracle-table)
  "Register a homoiconic Lisp function definition (or oracle table) under NAME in the
active function table, and record it in the active library."
  (let* ((kname (canonical-op-name name))
         (norm-inputs (input-alist inputs)))
    (assert (and (not (member kname +operator-names+))
                 (valid-inputs-p norm-inputs)
                 (valid-type-p return-type)))
    (unless (member kname *registered-function-names*)
      (setf *registered-function-names* (append *registered-function-names* (list kname))))
    (let* ((def (%make-function-definition :name kname
                                           :inputs (copy-tree norm-inputs)
                                           :return-type (copy-tree return-type)))
           (self-op (progn (setf (gethash kname *function-definitions*) def)
                           (let ((sym (op kname))
                                 (ctype (function-definition-code-type def)))
                             (setf (gethash sym *node-meta*)
                                   (make-ast-meta :kind :op :id kname :type (copy-tree ctype)
                                                  :value (compute-operator-signature kname ctype)
                                                  :non-var-bits (+ 2 (operator-bit-size kname ctype))
                                                  :var-count 0 :syntax-work 2
                                                  :total-p t :free-vars nil))
                             sym)))
           (resolved-body (if (functionp body) (funcall body self-op) body)))
      (when resolved-body
        (assert (equal return-type (expression-type resolved-body norm-inputs))))
      (when oracle-table
        (dolist (entry oracle-table)
          (assert (and (consp entry)
                       (= (length (car entry)) (length norm-inputs))
                       (every (lambda (val spec) (value-p val (cdr spec))) (car entry) norm-inputs)
                       (value-p (cdr entry) return-type)))))
      (setf (function-definition-body def) (when resolved-body (copy-tree resolved-body))
            (function-definition-oracle-table def) (copy-tree oracle-table))
      (recompute-registered-functions-totality)
      (incf *function-library-version*)
      (unless *syncing-knowledge-library-p*
        (record-function-entry *knowledge-library* def))
      def)))

(defun set-function-active-implementation (name inputs return-type &key body oracle-table)
  "Lightweight swap of an already-registered recursive function between an ORACLE-TABLE
and an unverified candidate BODY during synthesis verification, without global cache eviction."
  (let* ((kname (canonical-op-name name))
         (norm-inputs (input-alist inputs))
         (def (find-function-definition kname)))
    (if (and def
             (equal (function-definition-inputs def) norm-inputs)
             (equal (function-definition-return-type def) return-type)
             (null (function-definition-total-p def)))
        (let ((copied-body (when body (copy-tree body))))
          (when copied-body (ensure-ast-meta copied-body))
          (setf (function-definition-body def) copied-body
                (function-definition-oracle-table def) oracle-table
                (function-definition-total-p def) nil
                (function-definition-conditional-code-params def) nil)
          def)
        (define-function kname norm-inputs return-type body :oracle-table oracle-table))))

(defparameter *auto-retyped-functions* (make-hash-table :test #'eq)
  "Set of function names automatically instantiated via RETYPE-FUNCTION-DEFINITION during synthesis.")

(defun clear-function-definitions ()
  "Empty the active function table and reset de novo naming. The active library loses its
:function and :descriptor entries with it."
  (clrhash *function-definitions*)
  (clrhash *auto-retyped-functions*)
  (setf *registered-function-names* nil
        *de-novo-function-counter* 0)
  (invalidate-app-meta)
  (incf *function-library-version*)
  (unless *syncing-knowledge-library-p*
    (let ((library *knowledge-library*))
      (setf (knowledge-library-entries library)
            (remove-if (lambda (entry) (member (knowledge-entry-kind entry) '(:function :descriptor)))
                       (knowledge-library-entries library)))
      (rebuild-knowledge-library-indexes library)))
  nil)
