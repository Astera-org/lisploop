(in-package #:lisploop)

;;; Saving and restoring a knowledge library as a portable S-expression packet.

(defun serialize-hybrid-slot (value)
  "Serialize VALUE as `(:ast ...)` when it is a valid AST node, or `(:data ...)` otherwise."
  (when value
    (if (ignore-errors (ensure-ast-meta value))
        (list :ast (ast->sexp value))
        (list :data (copy-tree value)))))

(defun deserialize-hybrid-slot (encoded)
  "Restore a value serialized by `serialize-hybrid-slot`."
  (when (consp encoded)
    (ecase (first encoded)
      (:ast (sexp->ast (second encoded)))
      (:data (copy-tree (second encoded))))))

(defun descriptor-clause->plist (clause)
  (if (descriptor-clause-p clause)
      (list :id (descriptor-clause-id clause)
            :facet (descriptor-clause-facet clause)
            :tier (descriptor-clause-tier clause)
            :status (descriptor-clause-status clause)
            :weight-bits (descriptor-clause-weight-bits clause)
            :work-cost (descriptor-clause-work-cost clause))
      (copy-tree clause)))

(defun plist->descriptor-clause (plist)
  "Rebuild a clause; a field that is absent or nil in PLIST takes the struct's default."
  (if (descriptor-clause-p plist)
      plist
      (apply #'make-descriptor-clause
             (loop for (key value) on plist by #'cddr
                   when value append (list key value)))))

(defun convert-descriptor-profile (metadata converter)
  "A copy of the entry METADATA plist with each clause of its descriptor profile converted."
  (let ((copy (copy-list metadata)))
    (when (getf copy :descriptor-profile)
      (setf (getf copy :descriptor-profile)
            (mapcar converter (getf copy :descriptor-profile))))
    (copy-tree copy)))

(defparameter +knowledge-entry-slots+
  '((:id knowledge-entry-id :data)
    (:kind knowledge-entry-kind :data)
    (:domain knowledge-entry-domain :data)
    (:inputs knowledge-entry-inputs :data)
    (:target knowledge-entry-target :data)
    (:expression knowledge-entry-expression :ast)
    (:guard knowledge-entry-guard :ast)
    (:trigger knowledge-entry-trigger :ast)
    (:residual knowledge-entry-residual :hybrid)
    (:auxiliary-code knowledge-entry-auxiliary-code :ast)
    (:status knowledge-entry-status :data)
    (:certificate knowledge-entry-certificate :hybrid)
    (:bits knowledge-entry-bits :data)
    (:gain knowledge-entry-gain :data)
    (:work knowledge-entry-work :data)
    (:active-p knowledge-entry-active-p :boolean)
    (:last-used-epoch knowledge-entry-last-used-epoch :data)
    (:edges knowledge-entry-edges :data)
    (:metadata knowledge-entry-metadata :metadata))
  "Each slot of a `knowledge-entry` as (keyword reader encoding). The keyword is both the
packet key and the `make-knowledge-entry` argument.")

(defun knowledge-entry->sexp (entry)
  "Serialize `knowledge-entry` ENTRY into a portable homoiconic plist S-expression."
  (loop for (key reader encoding) in +knowledge-entry-slots+
        for value = (funcall reader entry)
        append (list key (ecase encoding
                           ((:data :boolean) (copy-tree value))
                           (:ast (ast->sexp value))
                           (:hybrid (serialize-hybrid-slot value))
                           (:metadata (convert-descriptor-profile value #'descriptor-clause->plist))))))

(defun sexp->knowledge-entry (plist &optional (library *knowledge-library*))
  "Reconstruct a `knowledge-entry` from its `knowledge-entry->sexp` plist representation.
A slot that is absent from PLIST takes the default of `make-knowledge-entry`."
  (apply #'make-knowledge-entry :library library
         (loop for (key nil encoding) in +knowledge-entry-slots+
               for stored = (getf plist key :%missing%)
               unless (eq stored :%missing%)
                 append (let ((value (ecase encoding
                                       ((:data :boolean) stored)
                                       (:ast (sexp->ast stored))
                                       (:hybrid (deserialize-hybrid-slot stored))
                                       (:metadata (convert-descriptor-profile stored #'plist->descriptor-clause)))))
                          (when (or value (eq encoding :boolean))
                            (list key value))))))

(defun serialize-knowledge-library (&optional (library *knowledge-library*))
  "Serialize LIBRARY into a self-contained homoiconic S-expression packet."
  (list :knowledge-library
        :encoding-version +encoding-version+
        :version (knowledge-library-version library)
        :epoch (knowledge-library-epoch library)
        :function-names (copy-list (knowledge-library-function-names library))
        :de-novo-counter (knowledge-library-de-novo-counter library)
        :entry-counter (knowledge-library-entry-counter library)
        :entries (mapcar #'knowledge-entry->sexp (knowledge-library-entries library))))

(defun deserialize-knowledge-library (sexp &key (target-library nil) ledger)
  "Reconstruct a `knowledge-library` from a `serialize-knowledge-library` S-expression,
installing all entries in priority order (`:function` before `:law`, `:solver`, `:functor`, `:heuristic`)."
  (assert (and (consp sexp) (eq :knowledge-library (first sexp))))
  (let* ((plist (rest sexp))
         (library (if target-library
                      (clear-knowledge-library target-library)
                      (make-knowledge-library)))
         (entry-plists (getf plist :entries)))
    (assert (eql +encoding-version+ (getf plist :encoding-version)) ()
            "Unsupported knowledge-library encoding version ~S" (getf plist :encoding-version))
    (with-knowledge-library (library)
      (setf *de-novo-function-counter* (or (getf plist :de-novo-counter) 0)
            (knowledge-library-entry-counter library) (or (getf plist :entry-counter) 0))
      ;; Declare every signature before decoding bodies, including forward
      ;; references and mutually recursive definitions in saved order.
      (dolist (entry-plist entry-plists)
        (when (eq :function (getf entry-plist :kind))
          (let ((name (canonical-op-name (getf entry-plist :id))))
            (setf (gethash name *function-definitions*)
                  (%make-function-definition :name name
                                             :inputs (copy-tree (getf entry-plist :inputs))
                                             :return-type (copy-tree (getf entry-plist :target)))))))
      (setf *registered-function-names* (mapcar #'canonical-op-name (getf plist :function-names)))
      (let ((installed (make-hash-table :test #'eq)))
        (dolist (entry-plist (stable-sort (copy-list entry-plists) #'<
                                          :key (lambda (entry-plist)
                                                 (knowledge-kind-priority (getf entry-plist :kind)))))
          (let ((entry (sexp->knowledge-entry entry-plist library)))
            (register-knowledge-entry entry :library library :ledger ledger)
            (setf (gethash (knowledge-entry-id entry) installed) entry)))
        ;; Entries were installed in kind order; restore the saved chronological order.
        (setf (knowledge-library-entries library)
              (loop for entry-plist in entry-plists
                    for entry = (gethash (canonical-op-name (getf entry-plist :id)) installed)
                    when entry collect entry))))
    (setf (knowledge-library-version library)
          (or (getf plist :version) (knowledge-library-version library))
          (knowledge-library-epoch library)
          (or (getf plist :epoch) 0))
    library))

(defun save-knowledge-library (pathname &optional (library *knowledge-library*))
  "Write LIBRARY as a canonical homoiconic S-expression file at PATHNAME."
  (with-open-file (stream pathname :direction :output :if-exists :supersede :if-does-not-exist :create)
    (with-standard-io-syntax
      (let ((*print-circle* nil)
            (*print-pretty* t))
        (prin1 (serialize-knowledge-library library) stream)
        (terpri stream))))
  pathname)

(defun load-knowledge-library (pathname &key (library *knowledge-library*) target-library ledger)
  "Load a `knowledge-library` saved by `save-knowledge-library` from PATHNAME."
  (with-open-file (stream pathname :direction :input)
    (with-standard-io-syntax
      (let ((sexp (read stream nil nil)))
        (deserialize-knowledge-library sexp
                                       :target-library (or target-library library)
                                       :ledger ledger)))))

(defun knowledge-library-storage-bits (&optional (library *knowledge-library*))
  "Exact UTF-8 bit length of the canonical printed persistence packet.
This includes schemas, evidence, metadata and duplicated syntax. It is distinct
from conditional DSL body bits used to rank executable search candidates."
  (let ((packet (serialize-knowledge-library library)))
    (* 8 (length
          (sb-ext:string-to-octets
           (with-standard-io-syntax
             (let ((*print-pretty* nil) (*print-circle* nil))
               (write-to-string packet :readably t)))
           :external-format :utf-8)))))
