(in-package #:lisploop)

(defun expression-dependencies (expressions)
  "Portable transitive function snapshots, including calls inside quoted code."
  (let ((seen (make-hash-table :test #'eq)) (definitions nil))
    (labels ((visit (expr &optional scope)
               (walk-typed-ast expr scope
                 (lambda (node lexical-scope)
                   (declare (ignore lexical-scope))
                   (when (operator-p node)
                        (let* ((name (operator-name node))
                               (def (and name (find-function-definition name))))
                          (when (and def (not (gethash name seen)))
                            (setf (gethash name seen) t)
                            (push (list name (copy-tree (function-definition-inputs def))
                                        (copy-tree (function-definition-return-type def))
                                        (ast->sexp (function-definition-body def))
                                        (copy-tree (function-definition-oracle-table def))) definitions)
                            (visit (function-definition-body def) (function-definition-inputs def)))))))))
      (mapc #'visit expressions))
    (sort definitions #'string< :key (lambda (d) (symbol-name (first d))))))

(defun knowledge-statement-snapshot (entry)
  "Evidence binds to semantics, not mutable status flags or global counters."
  (let ((exprs (list (knowledge-entry-expression entry) (knowledge-entry-guard entry)
                     (knowledge-entry-trigger entry) (knowledge-entry-auxiliary-code entry)))
        (meta (knowledge-entry-metadata entry)))
    (list :semantics (list +simulator-version+ +encoding-version+)
          :kind (knowledge-entry-kind entry) :domain (copy-tree (knowledge-entry-domain entry))
          :inputs (copy-tree (knowledge-entry-inputs entry))
          :target (copy-tree (knowledge-entry-target entry))
          :code (mapcar #'ast->sexp exprs)
          :context (copy-tree (list (getf meta :operator) (getf meta :position)
                                   (getf meta :context-map) (getf meta :unique-p)))
          :dependencies (expression-dependencies
                         (append exprs
                                 (loop for edge in (knowledge-entry-edges entry)
                                       when (eq :describes (first edge))
                                         append (loop for name in (rest edge)
                                                      when (defined-function-p name) collect (op name)))
                                 (when (getf meta :operator)
                                         (list (sexp->ast (getf meta :operator)))))))))

(defun attest-knowledge-entry (entry method obligations)
  "Attach checked evidence or an explicitly requested trusted axiom."
  (setf (knowledge-entry-certificate entry)
        (list :method method :obligations (copy-list obligations)
              :snapshot (knowledge-statement-snapshot entry)))
  entry)

(defun knowledge-evidence-current-p (entry obligation &optional snapshot)
  "A status label alone never authorizes semantic elimination. SNAPSHOT is ENTRY's present
statement snapshot, for a caller that has already taken it."
  (let ((certificate (knowledge-entry-certificate entry)))
    (and (listp certificate)
         (member (getf certificate :method) '(:exhaustive :derived :trusted-axiom))
         (member obligation (getf certificate :obligations))
         (equalp (getf certificate :snapshot)
                 (or snapshot (knowledge-statement-snapshot entry))))))
