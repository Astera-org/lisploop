(in-package #:lisploop)

;;; Generic Knowledge Library Serialization & Deserialization

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

(defun knowledge-entry->sexp (entry)
  "Serialize `knowledge-entry` ENTRY into a portable homoiconic plist S-expression."
  (list :id (knowledge-entry-id entry)
        :kind (knowledge-entry-kind entry)
        :domain (copy-tree (knowledge-entry-domain entry))
        :inputs (copy-tree (knowledge-entry-inputs entry))
        :target (copy-tree (knowledge-entry-target entry))
        :expression (ast->sexp (knowledge-entry-expression entry))
        :guard (ast->sexp (knowledge-entry-guard entry))
        :trigger (ast->sexp (knowledge-entry-trigger entry))
        :residual (serialize-hybrid-slot (knowledge-entry-residual entry))
        :auxiliary-code (ast->sexp (knowledge-entry-auxiliary-code entry))
        :status (knowledge-entry-status entry)
        :certificate (serialize-hybrid-slot (knowledge-entry-certificate entry))
        :bits (knowledge-entry-bits entry)
        :gain (knowledge-entry-gain entry)
        :work (knowledge-entry-work entry)
        :edges (copy-tree (knowledge-entry-edges entry))
        :metadata (copy-tree (knowledge-entry-metadata entry))))

(defun sexp->knowledge-entry (plist &optional (library *knowledge-library*))
  "Reconstruct a `knowledge-entry` from its `knowledge-entry->sexp` plist representation."
  (make-knowledge-entry
   :id (getf plist :id)
   :kind (getf plist :kind)
   :domain (getf plist :domain)
   :inputs (getf plist :inputs)
   :target (getf plist :target)
   :expression (sexp->ast (getf plist :expression))
   :guard (sexp->ast (getf plist :guard))
   :trigger (sexp->ast (getf plist :trigger))
   :residual (deserialize-hybrid-slot (getf plist :residual))
   :auxiliary-code (sexp->ast (getf plist :auxiliary-code))
   :status (or (getf plist :status) :empirical)
   :certificate (deserialize-hybrid-slot (getf plist :certificate))
   :bits (or (getf plist :bits) 0)
   :gain (or (getf plist :gain) 0)
   :work (or (getf plist :work) 0)
   :edges (getf plist :edges)
   :metadata (getf plist :metadata)
   :library library))

(defun serialize-knowledge-library (&optional (library *knowledge-library*))
  "Serialize LIBRARY into a self-contained homoiconic S-expression packet."
  (list :knowledge-library
        :encoding-version +encoding-version+
        :version (knowledge-library-version library)
        :function-names (copy-list (knowledge-library-function-names library))
        :de-novo-counter (knowledge-library-de-novo-counter library)
        :entry-counter (knowledge-library-entry-counter library)
        :entries (mapcar #'knowledge-entry->sexp (knowledge-library-entries library))))

(defun deserialize-knowledge-library (sexp &key (target-library nil) ledger)
  "Reconstruct a `knowledge-library` from a `serialize-knowledge-library` S-expression,
installing all entries in priority order (`:function` before `:law`, `:solver`, `:functor`, `:heuristic`)."
  (assert (and (consp sexp) (eq :knowledge-library (first sexp))))
  (let* ((plist (rest sexp))
         (enc-ver (getf plist :encoding-version))
         (lib (if target-library
                  (clear-knowledge-library target-library)
                  (make-knowledge-library)))
         (fn-names (getf plist :function-names))
         (entry-plists (getf plist :entries))
         (ordered-plists
           (stable-sort (copy-list entry-plists)
                        #'<
                        :key (lambda (ep)
                               (let ((spec (find-knowledge-kind-spec (getf ep :kind))))
                                 (if spec (knowledge-kind-spec-priority spec) 50))))))
    (assert (eql +encoding-version+ enc-ver) () "Unsupported knowledge-library encoding version ~S" enc-ver)
    (setf (knowledge-library-de-novo-counter lib) (or (getf plist :de-novo-counter) 0)
          (knowledge-library-entry-counter lib) (or (getf plist :entry-counter) 0)
          (knowledge-library-function-names lib) (copy-list fn-names))
    (flet ((populate ()
             ;; Declare every signature before decoding bodies, including forward
             ;; references and mutually recursive definitions in saved order.
             (dolist (ep entry-plists)
               (when (eq :function (getf ep :kind))
                 (let ((name (canonical-op-name (getf ep :id))))
                   (setf (gethash name *function-definitions*)
                         (%make-function-definition :name name :inputs (copy-tree (getf ep :inputs))
                                                    :return-type (copy-tree (getf ep :target)))))))
             (dolist (fn-name fn-names)
               (let ((kfn (canonical-op-name fn-name)))
                 (unless (member kfn *registered-function-names*)
                   (setf *registered-function-names* (append *registered-function-names* (list kfn))))))
             (let ((installed-by-id (make-hash-table :test #'eq)))
               (dolist (ep ordered-plists)
                 (let ((entry (sexp->knowledge-entry ep lib)))
                   (register-knowledge-entry entry :library lib :ledger ledger)
                   (setf (gethash (knowledge-entry-id entry) installed-by-id) entry)))
               ;; Preserve original chronological entry order
               (setf (knowledge-library-entries lib)
                     (loop for ep in entry-plists
                           for id = (canonical-op-name (getf ep :id))
                           for e = (gethash id installed-by-id)
                           when e collect e)))))
      (if (eq lib *knowledge-library*)
          (populate)
          (with-knowledge-library (lib)
            (populate))))
    (setf (knowledge-library-version lib) (or (getf plist :version) (knowledge-library-version lib)))
    lib))

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
