(in-package #:lisploop)

(defvar *knowledge-entry-owners* (make-hash-table :test #'eq :weakness :key))

(defun invalidate-knowledge-caches (library)
  (clrhash (knowledge-library-rewrite-libraries library))
  (clrhash (knowledge-library-propagator-libraries library))
  (incf (knowledge-library-version library)))

;;; Generic Persistent Knowledge Library Lifecycle & Homoiconic AST Serialization

(defun next-knowledge-entry-id (&optional (library *knowledge-library*) (kind :entry))
  "Allocate a fresh canonical keyword ID (e.g. :LAW-0, :SOLVER-1, :REL-2) in LIBRARY."
  (let ((prefix (symbol-name (canonical-op-name kind))))
    (loop
      (let* ((idx (knowledge-library-entry-counter library))
             (cand (intern (format nil "~A-~D" prefix idx) :keyword)))
        (incf (knowledge-library-entry-counter library))
        (unless (gethash cand (knowledge-library-by-id library))
          (return cand))))))

(defun make-knowledge-entry (&key id kind domain inputs target expression guard trigger
                                  residual auxiliary-code (status :empirical) certificate
                                  (bits 0) (gain 0) (work 0) edges metadata
                                  (library *knowledge-library*))
  "Construct a canonical `knowledge-entry` with normalized schema and edge links."
  (let* ((kkind (canonical-op-name kind))
         (norm-inputs (copy-tree (if (schema-p inputs) (schema-inputs inputs) inputs)))
         (norm-target (copy-tree (or target (and (schema-p inputs) (schema-target inputs)) :int)))
         (inferred-domain (or domain
                              (and (schema-p inputs) (schema-domain inputs))
                              (infer-domain-from-types (cons norm-target (mapcar #'cdr norm-inputs)))))
         (kid (if id
                  (canonical-op-name id)
                  (if library
                      (next-knowledge-entry-id library kkind)
                      (intern (format nil "~A-0" (symbol-name kkind)) :keyword))))
         (eff-guard (or guard (lit :bool t)))
         (eff-bits (if (and (zerop bits) expression)
                       (body-size expression norm-inputs)
                       bits)))
    (%make-knowledge-entry
     :id kid
     :kind kkind
     :domain (copy-tree inferred-domain)
     :inputs norm-inputs
     :target norm-target
     :expression expression
     :guard eff-guard
     :trigger trigger
     :residual residual
     :auxiliary-code auxiliary-code
     :status status
     :certificate certificate
     :bits eff-bits
     :gain gain
     :work work
     :edges (copy-tree edges)
     :metadata (copy-tree metadata))))

(defun find-knowledge-entry (id &optional (library *knowledge-library*))
  "Look up a `knowledge-entry` by ID in LIBRARY in O(1) time."
  (when (and id library)
    (gethash (canonical-op-name id) (knowledge-library-by-id library))))

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

(defun add-knowledge-edge (source edge-key &rest targets)
  "Attach a relational edge `(EDGE-KEY . TARGETS)` to `knowledge-entry` SOURCE (or ID in `*knowledge-library*`)."
  (let* ((entry (if (knowledge-entry-p source)
                    source
                    (find-knowledge-entry source *knowledge-library*)))
         (kkey (canonical-op-name edge-key))
         (ktargets (mapcar (lambda (x) (if (symbolp x) (canonical-op-name x) x)) targets))
         (edge (cons kkey ktargets)))
    (assert entry () "Unknown knowledge-entry ~S" source)
    (unless (member edge (knowledge-entry-edges entry) :test #'equal)
      (setf (knowledge-entry-edges entry)
            (append (knowledge-entry-edges entry) (list edge)))
      (let ((owner (or (gethash entry *knowledge-entry-owners*) *knowledge-library*)))
        (when owner
        (dolist (tgt ktargets)
          (when (symbolp tgt)
            (pushnew (list kkey (knowledge-entry-id entry))
                     (gethash tgt (knowledge-library-incoming-edges owner))
                     :test #'equal)))
        (invalidate-knowledge-caches owner))))
    entry))

(defun index-knowledge-entry-edges (entry library)
  (dolist (edge (knowledge-entry-edges entry))
    (when (consp edge)
      (let ((ekey (first edge)))
        (dolist (tgt (rest edge))
          (when (symbolp tgt)
            (let ((ktgt (canonical-op-name tgt)))
              (pushnew (list ekey (knowledge-entry-id entry))
                       (gethash ktgt (knowledge-library-incoming-edges library))
                       :test #'equal))))))))

(defun rebuild-knowledge-library-indexes (&optional (library *knowledge-library*) ledger)
  "Rebuild all derived O(1) lookup tables in LIBRARY from its flat `entries` list,
running each kind's `:install` hook in priority order."
  (clrhash (knowledge-library-by-id library))
  (clrhash (knowledge-library-by-kind library))
  (clrhash (knowledge-library-incoming-edges library))
  (clrhash (knowledge-library-rewrite-libraries library))
  (clrhash (knowledge-library-propagator-libraries library))
  (clrhash (knowledge-library-descriptors library))
  (setf (knowledge-library-priority-predictor library) nil)
  (clrhash (knowledge-library-functions library))
  (setf (knowledge-library-function-names library)
        (loop for entry in (knowledge-library-entries library)
              when (eq :function (knowledge-entry-kind entry)) collect (knowledge-entry-id entry)))
  (when (eq library *knowledge-library*)
    (dolist (name (copy-list *registered-function-names*))
      (unless (member name (knowledge-library-function-names library))
        (remhash name *function-definitions*)
        (setf *registered-function-names* (remove name *registered-function-names*))))
    (invalidate-app-meta))
  (let ((ordered-entries
          (stable-sort (copy-list (knowledge-library-entries library))
                       #'<
                       :key (lambda (e)
                              (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind e))))
                                (if spec (knowledge-kind-spec-priority spec) 50))))))
    (dolist (entry (knowledge-library-entries library))
      (setf (gethash entry *knowledge-entry-owners*) library)
      (setf (gethash (knowledge-entry-id entry) (knowledge-library-by-id library)) entry)
      (setf (gethash (knowledge-entry-kind entry) (knowledge-library-by-kind library))
            (append (gethash (knowledge-entry-kind entry) (knowledge-library-by-kind library))
                    (list entry)))
      (index-knowledge-entry-edges entry library))
    (let ((*knowledge-library* library)
          (*syncing-knowledge-library-p* t))
      (dolist (entry ordered-entries)
        (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry))))
          (when (and spec (knowledge-kind-spec-install-fn spec))
            (funcall (knowledge-kind-spec-install-fn spec) entry library ledger))))))
  (incf (knowledge-library-version library))
  library)

(defun register-knowledge-entry (entry &key (library *knowledge-library*) ledger)
  "Validate, install, and index `knowledge-entry` ENTRY into LIBRARY via its declarative kind spec."
  (unless (eq library *knowledge-library*)
    (return-from register-knowledge-entry
      (call-with-knowledge-library library
        (lambda () (register-knowledge-entry entry :library library :ledger ledger)))))
  (let* ((kind (knowledge-entry-kind entry))
         (id (knowledge-entry-id entry))
         (spec (find-knowledge-kind-spec kind)))
    (when (and spec (knowledge-kind-spec-validate-fn spec))
      (let ((*knowledge-library* library))
        (funcall (knowledge-kind-spec-validate-fn spec) entry library)))
    (let ((existing (gethash id (knowledge-library-by-id library))))
      (when existing
        (setf (gethash (knowledge-entry-kind existing) (knowledge-library-by-kind library))
              (remove id (gethash (knowledge-entry-kind existing) (knowledge-library-by-kind library))
                      :key #'knowledge-entry-id))
        (maphash (lambda (target incoming)
                   (setf (gethash target (knowledge-library-incoming-edges library))
                         (remove id incoming :key #'second)))
                 (knowledge-library-incoming-edges library))
        (when (and (eq :function (knowledge-entry-kind existing))
                   (not (eq :function kind)))
          (remhash id (knowledge-library-functions library))
          (remhash id *function-definitions*)
          (setf (knowledge-library-function-names library) (remove id (knowledge-library-function-names library))
                *registered-function-names* (remove id *registered-function-names*)))
        (remhash existing *knowledge-entry-owners*))
      (if existing
          (setf (knowledge-library-entries library)
                (substitute entry existing (knowledge-library-entries library) :test #'eq))
          (setf (knowledge-library-entries library)
                (append (knowledge-library-entries library) (list entry)))))
    (setf (gethash id (knowledge-library-by-id library)) entry)
    (setf (gethash entry *knowledge-entry-owners*) library)
    (let ((kind-list (gethash kind (knowledge-library-by-kind library))))
      (setf (gethash kind (knowledge-library-by-kind library))
            (if (find id kind-list :key #'knowledge-entry-id :test #'eq)
                (substitute entry id kind-list :key #'knowledge-entry-id :test #'eq)
                (append kind-list (list entry)))))
    (index-knowledge-entry-edges entry library)
    (let ((*knowledge-library* library)
          (*syncing-knowledge-library-p* t))
      (when (and spec (knowledge-kind-spec-install-fn spec))
        (funcall (knowledge-kind-spec-install-fn spec) entry library ledger)))
    (invalidate-knowledge-caches library)
    entry))

(defun remove-knowledge-entry (id &optional (library *knowledge-library*) ledger)
  "Remove entry ID from LIBRARY and rebuild its derived indexes."
  (unless (eq library *knowledge-library*)
    (return-from remove-knowledge-entry
      (call-with-knowledge-library library (lambda () (remove-knowledge-entry id library ledger)))))
  (let* ((kid (canonical-op-name id))
          (existing (gethash kid (knowledge-library-by-id library))))
    (when existing
      (setf (knowledge-library-entries library)
            (remove existing (knowledge-library-entries library) :test #'eq))
      (remhash existing *knowledge-entry-owners*)
      (rebuild-knowledge-library-indexes library ledger)
      t)))

(defun consume-knowledge-entry (entry-or-id context &key (library *knowledge-library*) ledger)
  "Evaluate or consume ENTRY-OR-ID on CONTEXT using its `define-knowledge-kind` `:consume` hook."
  (unless (eq library *knowledge-library*)
    (return-from consume-knowledge-entry
      (call-with-knowledge-library library
        (lambda () (consume-knowledge-entry entry-or-id context :library library :ledger ledger)))))
  (let ((entry (if (knowledge-entry-p entry-or-id)
                   entry-or-id
                   (find-knowledge-entry entry-or-id library))))
    (when entry
      (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry))))
        (if (and spec (knowledge-kind-spec-consume-fn spec))
            (funcall (knowledge-kind-spec-consume-fn spec) entry context ledger)
            (when (and (knowledge-entry-expression entry)
                       (fboundp 'evaluate))
              (funcall 'evaluate
                       (knowledge-entry-expression entry)
                       (knowledge-entry-inputs entry)
                       context
                       :ledger ledger)))))))

(defun clear-knowledge-library (&optional (library *knowledge-library*))
  "Reset LIBRARY to an empty knowledge store."
  (setf (knowledge-library-entries library) nil
        (knowledge-library-function-names library) nil
        (knowledge-library-priority-predictor library) nil
        (knowledge-library-de-novo-counter library) 0
        (knowledge-library-entry-counter library) 0)
  (clrhash (knowledge-library-by-id library))
  (clrhash (knowledge-library-by-kind library))
  (clrhash (knowledge-library-incoming-edges library))
  (clrhash (knowledge-library-functions library))
  (clrhash (knowledge-library-rewrite-libraries library))
  (clrhash (knowledge-library-propagator-libraries library))
  (clrhash (knowledge-library-descriptors library))
  (incf (knowledge-library-version library))
  (when (eq library *knowledge-library*)
    (let ((*syncing-knowledge-library-p* t))
      (clear-function-definitions)))
  library)

(defun sync-function-to-knowledge-library (library def)
  "Synchronize a `function-definition` DEF registered via `define-function` into LIBRARY."
  (let ((kname (function-definition-name def))
        (body (function-definition-body def))
        (oracle (function-definition-oracle-table def)))
    (setf (gethash kname (knowledge-library-functions library)) def
          (knowledge-library-function-names library) (copy-list *registered-function-names*)
          (knowledge-library-de-novo-counter library) *de-novo-function-counter*)
    (when (and body (null oracle))
      (let* ((existing (find-knowledge-entry kname library))
             (inputs (function-definition-inputs def))
             (ret (function-definition-return-type def))
             (same-definition (and existing
                                   (equal inputs (knowledge-entry-inputs existing))
                                   (equal ret (knowledge-entry-target existing))
                                   (equal body (knowledge-entry-expression existing))))
             (bits (body-size body inputs))
             (entry (make-knowledge-entry
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
                     :bits bits
                     :gain (if existing (knowledge-entry-gain existing) 0)
                     :work (if existing (knowledge-entry-work existing) (syntax-work body))
                     :edges (and existing (knowledge-entry-edges existing))
                     :metadata (list :total-p (function-definition-total-p def)
                                     :conditional-code-params
                                     (copy-list (function-definition-conditional-code-params def)))
                     :library library)))
        (let ((*syncing-knowledge-library-p* t))
          (register-knowledge-entry entry :library library))))))

(defun activate-knowledge-library-functions (library)
  "Install LIBRARY's `:function` definitions into the active VM function tables."
  (let ((*syncing-knowledge-library-p* t))
    (clear-function-definitions)
    (let ((fn-entries (knowledge-entries-of-kind :function library)))
      (dolist (kname (knowledge-library-function-names library))
        (unless (member kname *registered-function-names*)
          (setf *registered-function-names* (append *registered-function-names* (list kname)))))
      (dolist (entry fn-entries)
        (let ((kname (knowledge-entry-id entry)))
          (setf (gethash kname *function-definitions*)
                (%make-function-definition :name kname :inputs (copy-tree (knowledge-entry-inputs entry))
                                           :return-type (copy-tree (knowledge-entry-target entry))))
          (unless (member kname *registered-function-names*)
            (setf *registered-function-names* (append *registered-function-names* (list kname))))))
      (dolist (entry fn-entries)
        (let* ((kname (knowledge-entry-id entry))
               (inputs (knowledge-entry-inputs entry))
               (ret (knowledge-entry-target entry))
               (body (knowledge-entry-expression entry))
               (oracle (getf (knowledge-entry-metadata entry) :oracle-table)))
          (define-function kname inputs ret body :oracle-table oracle))))
    (setf *de-novo-function-counter*
          (max *de-novo-function-counter* (knowledge-library-de-novo-counter library)))))

(defmacro with-knowledge-library ((library) &body body)
  "Execute BODY with LIBRARY bound as the active `*knowledge-library*` and its functions
installed in the VM, restoring the outer library's state upon exit."
  (let ((lib-var (gensym "LIB"))
        (outer-lib (gensym "OUTER-LIB"))
        (saved-defs (gensym "SAVED-DEFS"))
        (saved-names (gensym "SAVED-NAMES"))
        (saved-counter (gensym "SAVED-COUNTER")))
    `(let* ((,lib-var ,library)
            (,outer-lib *knowledge-library*)
            (,saved-defs (let (( pairs nil))
                           (maphash (lambda (k v) (push (cons k v) pairs)) *function-definitions*)
                           (nreverse pairs)))
            (,saved-names (copy-list *registered-function-names*))
            (,saved-counter *de-novo-function-counter*))
       (unwind-protect
            (let ((*knowledge-library* ,lib-var))
              (activate-knowledge-library-functions ,lib-var)
              ,@body)
         (let ((*syncing-knowledge-library-p* t))
           (clear-function-definitions)
           (dolist (kname ,saved-names)
             (unless (member kname *registered-function-names*)
               (setf *registered-function-names* (append *registered-function-names* (list kname)))))
           (dolist (pair ,saved-defs)
             (let ((def (cdr pair)))
               (setf (gethash (car pair) *function-definitions*)
                     (%make-function-definition :name (car pair)
                                                :inputs (copy-tree (function-definition-inputs def))
                                                :return-type (copy-tree (function-definition-return-type def))))))
           (dolist (pair ,saved-defs)
             (let ((def (cdr pair)))
               (define-function (car pair)
                                (function-definition-inputs def)
                                (function-definition-return-type def)
                                (function-definition-body def)
                                :oracle-table (function-definition-oracle-table def))))
           (setf *de-novo-function-counter* ,saved-counter
                 *knowledge-library* ,outer-lib))))))

(defun call-with-knowledge-library (library thunk)
  (with-knowledge-library (library) (funcall thunk)))
