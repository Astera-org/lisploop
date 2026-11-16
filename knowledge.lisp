(in-package #:lisploop)

;;; Persistent knowledge library: typed entries, relational edges, kinds, and active function table.

(defstruct knowledge-kind-spec
  name (priority 50 :type fixnum) validate-fn install-fn consume-fn consolidate-fn)

(defvar *knowledge-kind-specs* nil "Priority-ordered declarative `knowledge-kind-spec` definitions.")
(defvar *consolidation-options* nil "Keyword options of the `consolidate-knowledge-library` call in progress.")

(defun find-knowledge-kind-spec (kind)
  (find (canonical-op-name kind) *knowledge-kind-specs* :key #'knowledge-kind-spec-name :test #'eq))

(defun knowledge-kind-priority (kind)
  (let ((spec (find-knowledge-kind-spec kind))) (if spec (knowledge-kind-spec-priority spec) 50)))

(defmacro define-knowledge-kind (name &body clauses)
  "Declaratively register a knowledge kind in `*knowledge-kind-specs*`."
  (flet ((hook (key) (let ((c (assoc key clauses))) (when c `(lambda ,(second c) ,@(cddr c))))))
    (let ((kind (canonical-op-name name)))
      `(let ((spec (make-knowledge-kind-spec
                    :name ,kind :priority ,(or (second (assoc :priority clauses)) 50)
                    :validate-fn ,(hook :validate) :install-fn ,(hook :install)
                    :consume-fn ,(hook :consume) :consolidate-fn ,(hook :consolidate))))
         (setf *knowledge-kind-specs*
               (stable-sort (cons spec (remove ,kind *knowledge-kind-specs* :key #'knowledge-kind-spec-name :test #'eq))
                            #'< :key #'knowledge-kind-spec-priority))
         ',kind))))

(defstruct descriptor-clause
  id (facet :shape-delta) (tier 1 :type fixnum) (status :empirical) (weight-bits 2 :type fixnum) (work-cost 1 :type fixnum))

(defstruct (knowledge-entry (:constructor %make-knowledge-entry))
  id kind (domain :int) inputs target expression guard trigger residual auxiliary-code
  (status :empirical) certificate (bits 0 :type fixnum) (gain 0 :type fixnum) (work 0 :type fixnum)
  (active-p t) (last-used-epoch 0 :type fixnum) edges metadata executable)

(defstruct (knowledge-library (:constructor %make-knowledge-library))
  (version 0 :type fixnum) (epoch 0 :type fixnum) entries
  (by-id (make-hash-table :test #'eq)) (by-kind (make-hash-table :test #'eq))
  (incoming-edges (make-hash-table :test #'eq)) (functions (make-hash-table :test #'eq))
  stored-function-names (stored-de-novo-counter 0 :type fixnum)
  (rewrite-libraries (make-hash-table :test #'equal)) (propagator-libraries (make-hash-table :test #'equal))
  (compositional-index (make-hash-table :test #'eq)) priority-predictor (entry-counter 0 :type fixnum))

(defun make-knowledge-library () (%make-knowledge-library))

(defvar *knowledge-library* (%make-knowledge-library :functions *function-definitions*)
  "Active persistent store of synthesized functions, laws, algebras, solvers, descriptors, relations, and heuristics.")
(defvar *knowledge-entry-owners* (make-hash-table :test #'eq :weakness :key))
(defvar *syncing-knowledge-library-p* nil)

(defun knowledge-library-function-names (library)
  "The function names registered in LIBRARY's table, in registration order."
  (if (eq library *knowledge-library*) *registered-function-names* (knowledge-library-stored-function-names library)))

(defun knowledge-library-de-novo-counter (library)
  (if (eq library *knowledge-library*) *de-novo-function-counter* (knowledge-library-stored-de-novo-counter library)))

(defun refresh-function-operators ()
  (dolist (name *registered-function-names*) (when (find-function-definition name) (op name)))
  (invalidate-app-meta))

(defun call-with-knowledge-library (library thunk)
  "Call THUNK with LIBRARY active so `*knowledge-library*` and the VM function table belong to LIBRARY."
  (if (eq library *knowledge-library*)
      (funcall thunk)
      (let ((outer *knowledge-library*))
        (assert (eq *function-definitions* (knowledge-library-functions outer)))
        (setf (knowledge-library-stored-function-names outer) *registered-function-names*
              (knowledge-library-stored-de-novo-counter outer) *de-novo-function-counter*)
        (unwind-protect
             (let ((*knowledge-library* library) (*function-definitions* (knowledge-library-functions library))
                   (*registered-function-names* (knowledge-library-stored-function-names library))
                   (*de-novo-function-counter* (knowledge-library-stored-de-novo-counter library)))
               (refresh-function-operators)
               (unwind-protect (funcall thunk)
                 (setf (knowledge-library-stored-function-names library) *registered-function-names*
                       (knowledge-library-stored-de-novo-counter library) *de-novo-function-counter*)))
          (refresh-function-operators)))))

(defmacro with-knowledge-library ((library) &body body)
  "Execute BODY with LIBRARY bound as the active `*knowledge-library*` and function table."
  `(call-with-knowledge-library ,library (lambda () ,@body)))

(defun invalidate-knowledge-caches (library)
  (clrhash (knowledge-library-rewrite-libraries library))
  (clrhash (knowledge-library-propagator-libraries library))
  (incf (knowledge-library-version library)))

(defun next-knowledge-entry-id (&optional (library *knowledge-library*) (kind :entry))
  "Allocate a fresh canonical keyword ID (e.g. :LAW-0, :SOLVER-1) in LIBRARY."
  (let ((prefix (symbol-name (canonical-op-name kind))))
    (loop (let* ((idx (knowledge-library-entry-counter library))
                 (cand (keyword-id "~A-~D" prefix idx)))
            (incf (knowledge-library-entry-counter library))
            (unless (gethash cand (knowledge-library-by-id library)) (return cand))))))

(defun make-knowledge-entry (&key id kind domain inputs target expression guard trigger residual auxiliary-code
                                  (status :empirical) certificate (bits 0) (gain 0) (work 0) (active-p t)
                                  (last-used-epoch 0 last-used-epoch-p) edges metadata (library *knowledge-library*))
  "Construct a canonical `knowledge-entry` with normalized schema and edge links."
  (let* ((kkind (canonical-op-name kind))
         (nin (copy-tree (input-alist inputs)))
         (ntarg (copy-tree (or target (and (schema-p inputs) (schema-target inputs)) :int)))
         (idom (or domain (and (schema-p inputs) (schema-domain inputs))
                   (infer-domain-from-types (cons ntarg (mapcar #'cdr nin)))))
         (kid (if id (canonical-op-name id)
                  (if library (next-knowledge-entry-id library kkind) (keyword-id "~A-0" kkind)))))
    (%make-knowledge-entry
     :id kid :kind kkind :domain (copy-tree idom) :inputs nin :target ntarg :expression expression
     :guard (or guard (lit :bool t)) :trigger trigger :residual residual :auxiliary-code auxiliary-code
     :status status :certificate certificate
     :bits (if (and (zerop bits) expression) (body-size expression nin) bits)
     :gain gain :work work :active-p (not (null active-p))
     :last-used-epoch (if last-used-epoch-p last-used-epoch (if library (knowledge-library-epoch library) 0))
     :edges (copy-tree edges) :metadata (copy-tree metadata))))

(defun assert-entry-expression-type (entry)
  (assert (equal (knowledge-entry-target entry)
                 (expression-type (knowledge-entry-expression entry) (knowledge-entry-inputs entry)))))

(defun find-knowledge-entry (id &optional (library *knowledge-library*))
  "Look up a `knowledge-entry` by ID in LIBRARY in O(1) time."
  (when (and id library) (gethash (canonical-op-name id) (knowledge-library-by-id library))))

(defun knowledge-entry-compositional-name (entry)
  (when (knowledge-entry-p entry) (getf (knowledge-entry-metadata entry) :compositional-name)))

(defun (setf knowledge-entry-compositional-name) (value entry)
  (when (knowledge-entry-p entry)
    (setf (getf (knowledge-entry-metadata entry) :compositional-name) (and value (canonical-op-name value)))))

(defun knowledge-entry-descriptor-profile (entry)
  (when (knowledge-entry-p entry) (getf (knowledge-entry-metadata entry) :descriptor-profile)))

(defun (setf knowledge-entry-descriptor-profile) (value entry)
  (when (knowledge-entry-p entry) (setf (getf (knowledge-entry-metadata entry) :descriptor-profile) value)))

(defun active-knowledge-entry-p (entry)
  "True when ENTRY is non-archived (`active-p = T` and `status /= :inactive`)."
  (and (knowledge-entry-p entry) (knowledge-entry-active-p entry) (not (eq :inactive (knowledge-entry-status entry)))))

(defun find-knowledge-entries-by-address (address &optional (library *knowledge-library*) include-inactive-p)
  "Look up `knowledge-entry` items in LIBRARY by secondary compositional address or descriptor ID."
  (when (and address library)
    (let ((entries (copy-list (gethash (canonical-op-name address) (knowledge-library-compositional-index library)))))
      (if include-inactive-p entries (remove-if-not #'active-knowledge-entry-p entries)))))

(defun knowledge-entries-of-kind (kind &optional (library *knowledge-library*))
  "Return the chronological list of `knowledge-entry` items of KIND in LIBRARY."
  (when library (copy-list (gethash (canonical-op-name kind) (knowledge-library-by-kind library)))))

(defun active-knowledge-entries-of-kind (kind &optional (library *knowledge-library*))
  "Return the chronological list of active `knowledge-entry` items of KIND in LIBRARY."
  (remove-if-not #'active-knowledge-entry-p (knowledge-entries-of-kind kind library)))

(defun knowledge-edges-from (id &optional edge-key (library *knowledge-library*))
  "Return outgoing edges from entry ID (optionally filtered by EDGE-KEY)."
  (let ((entry (if (knowledge-entry-p id) id (find-knowledge-entry id library))))
    (when entry
      (if edge-key
          (let ((kkey (canonical-op-name edge-key)))
            (remove-if-not (lambda (e) (and (consp e) (eq kkey (first e)))) (knowledge-entry-edges entry)))
          (copy-tree (knowledge-entry-edges entry))))))

(defun knowledge-edges-to (target-id &optional edge-key (library *knowledge-library*))
  "Return incoming `(edge-key source-id ...)` links pointing to TARGET-ID."
  (when library
    (let ((incoming (gethash (canonical-op-name target-id) (knowledge-library-incoming-edges library))))
      (if edge-key
          (let ((kkey (canonical-op-name edge-key))) (remove-if-not (lambda (e) (eq kkey (first e))) incoming))
          (copy-list incoming)))))

(defun index-knowledge-edge (entry edge library)
  (dolist (target (rest edge))
    (when (symbolp target)
      (pushnew (list (first edge) (knowledge-entry-id entry))
               (gethash (canonical-op-name target) (knowledge-library-incoming-edges library)) :test #'equal))))

(defun add-knowledge-edge (source edge-key &rest targets)
  "Attach a relational edge `(EDGE-KEY . TARGETS)` to `knowledge-entry` SOURCE."
  (let* ((entry (if (knowledge-entry-p source) source (find-knowledge-entry source *knowledge-library*)))
         (edge (cons (canonical-op-name edge-key)
                     (mapcar (lambda (x) (if (symbolp x) (canonical-op-name x) x)) targets))))
    (assert entry () "Unknown knowledge-entry ~S" source)
    (unless (member edge (knowledge-entry-edges entry) :test #'equal)
      (setf (knowledge-entry-edges entry) (append (knowledge-entry-edges entry) (list edge)))
      (let ((owner (or (gethash entry *knowledge-entry-owners*) *knowledge-library*)))
        (when owner (index-knowledge-edge entry edge owner) (invalidate-knowledge-caches owner))))
    entry))

(defun index-knowledge-entry-compositional-address (entry library)
  (let ((idx (knowledge-library-compositional-index library)))
    (when (knowledge-entry-compositional-name entry)
      (pushnew entry (gethash (canonical-op-name (knowledge-entry-compositional-name entry)) idx) :test #'eq))
    (dolist (c (knowledge-entry-descriptor-profile entry))
      (when (and (descriptor-clause-p c) (descriptor-clause-id c))
        (pushnew entry (gethash (canonical-op-name (descriptor-clause-id c)) idx) :test #'eq)))))

(defun clear-knowledge-indexes (library)
  (dolist (tbl (list (knowledge-library-by-id library) (knowledge-library-by-kind library)
                     (knowledge-library-incoming-edges library) (knowledge-library-rewrite-libraries library)
                     (knowledge-library-propagator-libraries library) (knowledge-library-compositional-index library)))
    (clrhash tbl))
  (setf (knowledge-library-priority-predictor library) nil))

(defun index-knowledge-entry (entry library)
  (let ((kind (knowledge-entry-kind entry)))
    (setf (gethash entry *knowledge-entry-owners*) library
          (gethash (knowledge-entry-id entry) (knowledge-library-by-id library)) entry
          (gethash kind (knowledge-library-by-kind library))
          (append (gethash kind (knowledge-library-by-kind library)) (list entry)))
    (dolist (edge (knowledge-entry-edges entry)) (when (consp edge) (index-knowledge-edge entry edge library)))
    (index-knowledge-entry-compositional-address entry library)))

(defun unindex-knowledge-entry (entry library)
  (let ((id (knowledge-entry-id entry)) (kind (knowledge-entry-kind entry))
        (inc (knowledge-library-incoming-edges library)) (addrs (knowledge-library-compositional-index library)))
    (remhash id (knowledge-library-by-id library))
    (setf (gethash kind (knowledge-library-by-kind library))
          (remove id (gethash kind (knowledge-library-by-kind library)) :key #'knowledge-entry-id))
    (maphash (lambda (tgt es) (setf (gethash tgt inc) (remove id es :key #'second))) inc)
    (maphash (lambda (addr es) (when (member entry es :test #'eq)
                                 (setf (gethash addr addrs) (remove entry es :test #'eq))))
             addrs)
    (remhash entry *knowledge-entry-owners*)))

(declaim (ftype function sync-entry-executable consume-entry-executable))

(defun install-knowledge-entry (entry library ledger)
  (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry))) (*syncing-knowledge-library-p* t))
    (when (and spec (knowledge-kind-spec-install-fn spec))
      (funcall (knowledge-kind-spec-install-fn spec) entry library ledger)))
  (sync-entry-executable entry)
  (index-knowledge-entry-compositional-address entry library))

(defun rebuild-knowledge-library-indexes (&optional (library *knowledge-library*) ledger)
  "Rebuild all derived O(1) lookup tables in LIBRARY from its flat `entries` list."
  (call-with-knowledge-library library
    (lambda ()
      (clear-knowledge-indexes library)
      (let ((fids (loop for e in (knowledge-library-entries library)
                        when (eq :function (knowledge-entry-kind e)) collect (knowledge-entry-id e))))
        (dolist (name (copy-list *registered-function-names*))
          (unless (member name fids)
            (remhash name *function-definitions*)
            (setf *registered-function-names* (remove name *registered-function-names*))))
        (invalidate-app-meta))
      (dolist (e (knowledge-library-entries library)) (index-knowledge-entry e library))
      (dolist (e (stable-sort (copy-list (knowledge-library-entries library)) #'<
                              :key (lambda (x) (knowledge-kind-priority (knowledge-entry-kind x)))))
        (install-knowledge-entry e library ledger))
      (incf (knowledge-library-version library))))
  library)

(defun solo-auto-descriptor-p (entry target-id library)
  (and entry (eq :descriptor (knowledge-entry-kind entry))
       (getf (knowledge-entry-metadata entry) :auto-descriptor)
       (equal (list (list :describes target-id)) (knowledge-edges-from entry :describes library))))

(defun register-knowledge-entry (entry &key (library *knowledge-library*) ledger)
  "Validate, install, and index `knowledge-entry` ENTRY into LIBRARY via its declarative kind spec."
  (call-with-knowledge-library library
    (lambda ()
      (let* ((kind (knowledge-entry-kind entry)) (id (knowledge-entry-id entry))
             (spec (find-knowledge-kind-spec kind)) (existing (gethash id (knowledge-library-by-id library))))
        (when (and spec (knowledge-kind-spec-validate-fn spec))
          (funcall (knowledge-kind-spec-validate-fn spec) entry library))
        (cond (existing
               (when (and (not (eq (knowledge-entry-kind existing) kind))
                          (member (knowledge-entry-kind existing) '(:function :decoder-template)))
                 (dolist (edge (copy-list (knowledge-edges-to id :describes library)))
                   (let ((d (find-knowledge-entry (second edge) library)))
                     (when (solo-auto-descriptor-p d id library)
                       (unindex-knowledge-entry d library)
                       (setf (knowledge-library-entries library)
                             (delete d (knowledge-library-entries library) :test #'eq))))))
               (unindex-knowledge-entry existing library)
               (when (and (eq :function (knowledge-entry-kind existing)) (not (eq :function kind)))
                 (remhash id *function-definitions*)
                 (setf *registered-function-names* (remove id *registered-function-names*)))
               (setf (knowledge-library-entries library)
                     (substitute entry existing (knowledge-library-entries library) :test #'eq)))
              (t (setf (knowledge-library-entries library) (append (knowledge-library-entries library) (list entry)))))
        (index-knowledge-entry entry library)
        (install-knowledge-entry entry library ledger)
        (invalidate-knowledge-caches library)
        entry))))

(defun remove-knowledge-entry (id &optional (library *knowledge-library*) ledger)
  "Remove entry ID (and any auto-derived descriptors describing only ID) from LIBRARY."
  (let* ((kid (canonical-op-name id)) (existing (find-knowledge-entry kid library)))
    (when existing
      (setf (knowledge-library-entries library)
            (remove-if (lambda (e) (or (eq e existing) (solo-auto-descriptor-p e kid library)))
                       (knowledge-library-entries library)))
      (remhash existing *knowledge-entry-owners*)
      (rebuild-knowledge-library-indexes library ledger)
      t)))

(defun consume-knowledge-entry (entry-or-id context &key (library *knowledge-library*) ledger)
  "Evaluate or consume ENTRY-OR-ID on CONTEXT using its `:consume` hook or executable cache."
  (call-with-knowledge-library library
    (lambda ()
      (let ((entry (if (knowledge-entry-p entry-or-id) entry-or-id (find-knowledge-entry entry-or-id library))))
        (when entry
          (let ((spec (find-knowledge-kind-spec (knowledge-entry-kind entry))))
            (if (and spec (knowledge-kind-spec-consume-fn spec))
                (funcall (knowledge-kind-spec-consume-fn spec) entry context ledger)
                (consume-entry-executable entry context ledger))))))))

(defun clear-knowledge-library (&optional (library *knowledge-library*))
  "Reset LIBRARY to an empty knowledge store with an empty function table."
  (call-with-knowledge-library library
    (lambda ()
      (setf (knowledge-library-entries library) nil (knowledge-library-epoch library) 0
            (knowledge-library-entry-counter library) 0)
      (clear-knowledge-indexes library)
      (let ((*syncing-knowledge-library-p* t)) (clear-function-definitions))
      (incf (knowledge-library-version library))))
  library)

(defun recompute-registered-functions-totality ()
  (invalidate-app-meta)
  (loop (let ((changed-p nil))
          (dolist (fname *registered-function-names*)
            (let ((fdef (find-function-definition fname)))
              (when fdef
                (multiple-value-bind (ntot ncond)
                    (if (function-definition-oracle-table fdef) (values nil nil)
                        (analyze-function-body-totality fname (function-definition-inputs fdef)
                                                        (function-definition-body fdef)))
                  (unless (and (eq ntot (function-definition-total-p fdef))
                               (equal ncond (function-definition-conditional-code-params fdef)))
                    (setf (function-definition-total-p fdef) ntot
                          (function-definition-conditional-code-params fdef) ncond changed-p t))))))
          (if changed-p (invalidate-app-meta) (return))))
  (dolist (fname *registered-function-names*)
    (let ((fdef (find-function-definition fname)))
      (when (and fdef (function-definition-body fdef)) (ensure-ast-meta (function-definition-body fdef))))))

(defun record-function-entry (library def)
  (let ((kname (function-definition-name def)) (body (function-definition-body def)))
    (when (and body (null (function-definition-oracle-table def)))
      (let* ((ex (find-knowledge-entry kname library)) (inps (function-definition-inputs def))
             (ret (function-definition-return-type def))
             (same (and ex (equal inps (knowledge-entry-inputs ex)) (equal ret (knowledge-entry-target ex))
                        (equal body (knowledge-entry-expression ex))))
             (pmeta (when ex (loop for (k v) on (knowledge-entry-metadata ex) by #'cddr
                                   when (member k '(:saved-bits :dispatch-work :failed-lift-work :net-utility))
                                     append (list k v)))))
        (register-knowledge-entry
         (make-knowledge-entry
          :id kname :kind :function :inputs inps :target ret :expression body
          :trigger (and same (knowledge-entry-trigger ex)) :residual (and same (knowledge-entry-residual ex))
          :auxiliary-code (and same (knowledge-entry-auxiliary-code ex))
          :status (if (or (function-definition-total-p def) (function-definition-conditional-code-params def))
                      :validated :empirical)
          :certificate (or (and same (knowledge-entry-certificate ex))
                           (when (function-definition-total-p def) '(:kind :structural-totality)))
          :gain (if ex (knowledge-entry-gain ex) 0) :work (if ex (knowledge-entry-work ex) (syntax-work body))
          :active-p (if ex (knowledge-entry-active-p ex) t)
          :last-used-epoch (if same (knowledge-entry-last-used-epoch ex) (knowledge-library-epoch library))
          :edges (and ex (knowledge-entry-edges ex))
          :metadata (append (list :total-p (function-definition-total-p def)
                                  :conditional-code-params (copy-list (function-definition-conditional-code-params def)))
                            pmeta)
          :library library)
         :library library)))))

(defun define-function (name inputs return-type body &key oracle-table)
  "Register a homoiconic Lisp function definition (or oracle table) under NAME."
  (let* ((kname (canonical-op-name name)) (nin (input-alist inputs)))
    (assert (and (not (member kname +operator-names+)) (valid-inputs-p nin) (valid-type-p return-type)))
    (unless (member kname *registered-function-names*)
      (setf *registered-function-names* (append *registered-function-names* (list kname))))
    (let* ((def (%make-function-definition :name kname :inputs (copy-tree nin) :return-type (copy-tree return-type)))
           (self-op (progn (setf (gethash kname *function-definitions*) def)
                           (let ((sym (op kname)) (ct (function-definition-code-type def)))
                             (setf (gethash sym *node-meta*)
                                   (make-ast-meta :kind :op :id kname :type (copy-tree ct)
                                                  :value (compute-operator-signature kname ct)
                                                  :non-var-bits (+ 2 (operator-bit-size kname ct))
                                                  :var-count 0 :syntax-work 2 :total-p t :free-vars nil))
                             sym)))
           (rbody (if (functionp body) (funcall body self-op) body)))
      (when rbody (assert (equal return-type (expression-type rbody nin))))
      (when oracle-table
        (dolist (e oracle-table)
          (assert (and (consp e) (= (length (car e)) (length nin))
                       (every (lambda (v s) (value-p v (cdr s))) (car e) nin) (value-p (cdr e) return-type)))))
      (setf (function-definition-body def) (when rbody (copy-tree rbody))
            (function-definition-oracle-table def) (copy-tree oracle-table))
      (recompute-registered-functions-totality)
      (incf *function-library-version*)
      (unless *syncing-knowledge-library-p* (record-function-entry *knowledge-library* def))
      def)))

(defun set-function-active-implementation (name inputs return-type &key body oracle-table)
  "Lightweight swap between an ORACLE-TABLE and candidate BODY during synthesis verification."
  (let* ((kname (canonical-op-name name)) (nin (input-alist inputs)) (def (find-function-definition kname)))
    (if (and def (equal (function-definition-inputs def) nin)
             (equal (function-definition-return-type def) return-type) (null (function-definition-total-p def)))
        (let ((cbody (when body (copy-tree body))))
          (when cbody (ensure-ast-meta cbody))
          (setf (function-definition-body def) cbody (function-definition-oracle-table def) oracle-table
                (function-definition-total-p def) nil (function-definition-conditional-code-params def) nil)
          def)
        (define-function kname nin return-type body :oracle-table oracle-table))))

(defparameter *auto-retyped-functions* (make-hash-table :test #'eq)
  "Set of function names automatically instantiated via RETYPE-FUNCTION-DEFINITION.")

(defun clear-function-definitions ()
  "Empty the active function table and reset de novo naming."
  (clrhash *function-definitions*) (clrhash *auto-retyped-functions*)
  (setf *registered-function-names* nil *de-novo-function-counter* 0)
  (invalidate-app-meta) (incf *function-library-version*)
  (unless *syncing-knowledge-library-p*
    (let ((lib *knowledge-library*))
      (setf (knowledge-library-entries lib)
            (remove-if (lambda (e) (member (knowledge-entry-kind e) '(:function :descriptor)))
                       (knowledge-library-entries lib)))
      (rebuild-knowledge-library-indexes lib)))
  nil)
