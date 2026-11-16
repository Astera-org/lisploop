(in-package #:lisploop)

(defun type-variable-p (type) (and (consp type) (eq :type-variable (first type))))

(defun substitute-type-variables (tree lookup)
  "TREE with each type variable replaced by the type LOOKUP returns for it, itself
substituted in turn; a variable for which LOOKUP returns nil stays."
  (cond ((type-variable-p tree)
         (let ((replacement (funcall lookup tree)))
           (if replacement (substitute-type-variables replacement lookup) tree)))
        ((consp tree) (cons (substitute-type-variables (car tree) lookup)
                            (substitute-type-variables (cdr tree) lookup)))
        (t tree)))

(defun bind-template-type (pattern actual bindings)
  "BINDINGS, an alist from type variables to types, extended so that PATTERN is ACTUAL; an
error when the two do not match or a variable would need two types."
  (cond ((type-variable-p pattern)
         (let ((old (assoc pattern bindings :test #'equal)))
           (assert (or (null old) (equal actual (cdr old))))
           (if old bindings (acons pattern actual bindings))))
        ((consp pattern)
         (assert (consp actual))
         (bind-template-type (cdr pattern) (cdr actual)
                             (bind-template-type (car pattern) (car actual) bindings)))
        (t (assert (equal pattern actual)) bindings)))

(defun fill-template-type (type template bindings)
  "TYPE with its variables replaced from BINDINGS, and otherwise by TEMPLATE's defaults."
  (substitute-type-variables
   type (lambda (variable)
          (or (cdr (assoc variable bindings :test #'equal))
              (cdr (assoc variable (getf template :defaults) :test #'equal))
              (error "Unbound template type ~S" variable)))))

(defun infer-function-template (definition)
  "Infer type roles by unifying primitive constraints, independently of parameter order.
The result is portable typed syntax; quotations introduce their own variable scopes."
  (let ((counter 0) (substitution (make-hash-table :test #'equal)) (defaults nil))
    (labels
        ((fresh (default)
           (let ((v (list :type-variable (incf counter)))) (push (cons v default) defaults) v))
         (shape (type)
           (cond ((eq type :bool) :bool)
                 ((code-type-p type)
                  (list :code (mapcar (lambda (s) (cons (car s) (shape (cdr s)))) (code-inputs type))
                        (shape (code-sort type))))
                 ((and (consp type) (member (first type) '(:seq :tuple)))
                  (cons (first type) (mapcar #'shape (rest type))))
                 (t (fresh type))))
         (resolve (type)
           (substitute-type-variables type (lambda (v) (gethash v substitution))))
         (unify (left right)
           (let ((a (resolve left)) (b (resolve right)))
             (cond ((equal a b) nil)
                   ((type-variable-p a)
                    (assert (not (tree-find a b))) (setf (gethash a substitution) b))
                   ((type-variable-p b) (unify b a))
                   ((and (consp a) (consp b)) (unify (car a) (car b)) (unify (cdr a) (cdr b)))
                   (t (error "Incompatible template types ~S and ~S" a b)))))
         (tree-find (needle tree)
           (or (equal needle tree) (and (consp tree) (or (tree-find needle (car tree)) (tree-find needle (cdr tree))))))
         (scope (specs) (mapcar (lambda (s) (cons (car s) (shape (cdr s)))) specs))
         (walk (expr env self-inputs self-result)
           (case (ast-kind expr)
             (:var (let ((type (cdr (assoc (ast-id expr) env))))
                     (assert type) (values (list :var (ast-id expr) type) type)))
             (:lit
              (let ((type (shape (ast-type expr))))
                (if (code-type-p (ast-type expr))
                    (multiple-value-bind (body result)
                        (walk (ast-value expr) (code-inputs type) self-inputs self-result)
                      (unify result (code-sort type))
                      (values (list :lit type body) type))
                    (values (list :lit type (copy-tree (ast-value expr))) type))))
             (:app
              (let* ((name (ast-id expr)) (old-op (first expr))
                     (nodes nil) (types nil) (out nil) (parameter nil))
                (dolist (arg (rest expr))
                  (multiple-value-bind (node type) (walk arg env self-inputs self-result)
                    (push node nodes) (push type types)))
                (setf nodes (nreverse nodes) types (nreverse types))
                (flet ((same (a b) (unify a b)))
                  (cond
                    ((eq name (function-definition-name definition))
                     (mapc #'same types (mapcar #'cdr self-inputs))
                     (setf out self-result parameter (list :code self-inputs self-result)))
                    ((eq name :at)
                     (same (second types) :int)
                     (setf parameter (first types) out (second (resolve parameter)))
                     (when (eq :tuple (first (resolve parameter)))
                       (dolist (part (rest (resolve parameter))) (same part out))))
                    ((eq name :tuple) (setf out (cons :tuple types) parameter out))
                    ((eq name :code-eval)
                     (let ((ctype (resolve (first types))))
                       (assert (code-type-p ctype))
                       (mapc #'same (rest types) (mapcar #'cdr (code-inputs ctype)))
                       (setf out (code-sort ctype) parameter ctype)))
                    ((eq name :code-subst)
                     (let* ((source (resolve (first types)))
                            (bindings (resolve (second types)))
                            (old-source (ast-type (second expr)))
                            (old-bindings (ast-type (third expr))))
                       (setf out (shape (ast-type expr)))
                       (same (code-sort source) (code-sort out))
                       (loop for (nil . input-type) in (code-inputs source)
                             for binding-type in (rest bindings)
                             for (nil . old-input) in (code-inputs old-source)
                             for old-binding in (rest old-bindings)
                             do (same binding-type
                                      (if (code-subst-code-binding-p old-binding (ast-type expr) old-input)
                                          (list :code (code-inputs out) input-type)
                                          input-type)))
                       (setf parameter (tuple-type source bindings out))))
                    ((signature-pattern name)
                     (destructuring-bind (parameter-pattern argument-patterns result-pattern)
                         (signature-pattern name)
                       ;; BOUND maps the variables of the primitive's patterns to template types.
                       ;; An argument whose pattern they already determine is unified with it whole.
                       (let ((bound nil))
                         (labels ((constrain (pattern type)
                                    (cond ((and (consp pattern)
                                                (subsetp (pattern-variables pattern)
                                                         (mapcar #'car bound)))
                                           (same type (sublis bound pattern)))
                                          ((consp pattern)
                                           (let ((actual (resolve type)))
                                             (assert (eq (first pattern) (first actual)))
                                             (mapc #'constrain (rest pattern) (rest actual))))
                                          ((keywordp pattern) (same type pattern))
                                          ((assoc pattern bound)
                                           (same (cdr (assoc pattern bound)) type))
                                          (t (push (cons pattern type) bound)))))
                           (mapc #'constrain argument-patterns types)
                           (setf out (sublis bound result-pattern)
                                 parameter (sublis bound parameter-pattern))))))
                    (t
                     ;; Unsupported polymorphic primitives stay monomorphic, never guessed.
                     (mapc #'same types (second (operator-type old-op)))
                     (setf out (third (operator-type old-op)) parameter (operator-operand-type old-op)))))
                (values (list* :app (list :op name parameter) nodes) out)))
             (otherwise (error "Unsupported template node ~S" expr)))))
      (let* ((inputs (scope (function-definition-inputs definition)))
             (target (shape (function-definition-return-type definition))))
        (multiple-value-bind (body result) (walk (function-definition-body definition) inputs inputs target)
          (unify result target)
          (list :inputs (resolve inputs) :target (resolve target) :body (resolve body)
                :defaults (mapcar (lambda (pair) (cons (resolve (car pair)) (cdr pair))) defaults)
                :source (ast->sexp (function-definition-body definition))))))))

(defun instantiate-function-template (definition input-types target &key name (register-p t))
  "Instantiate the inferred schema against complete input/result types, including captures."
  (unless register-p
    ;; Keep recursive operator construction isolated, including name collisions.
    (let ((temporary (deserialize-knowledge-library (serialize-knowledge-library))))
      (return-from instantiate-function-template
        (with-knowledge-library (temporary)
          (instantiate-function-template definition input-types target :name name)))))
  (let* ((def (if (function-definition-p definition) definition (find-function-definition definition)))
         (template (infer-function-template def))
         (new-name (or name (next-function-name)))
         (bindings (bind-template-type (getf template :target) target
                                       (bind-template-type (mapcar #'cdr (getf template :inputs))
                                                           input-types nil))))
    (labels ((fill-type (type) (fill-template-type type template bindings))
             (body (node self)
               (ecase (first node)
                 (:var (var (second node) (fill-type (third node))))
                 (:op (if (eq (second node) (function-definition-name def)) self
                          (op (second node) (fill-type (third node)))))
                 (:lit (let ((type (fill-type (second node))))
                         (lit type (if (code-type-p type) (body (third node) self)
                                       (retype-value (third node) type)))))
                 (:app (apply #'app (body (second node) self) (mapcar (lambda (n) (body n self)) (cddr node)))))))
      (let* ((inputs (loop for (id . nil) in (getf template :inputs) for type in input-types
                           collect (cons id type)))
             (new (define-function new-name inputs target
                    (lambda (self) (body (getf template :body) self))))
             (entry (find-knowledge-entry new-name)))
        (when entry (setf (getf (knowledge-entry-metadata entry) :type-template) template))
        new))))

(defun retype-function-definition (def-or-name new-element-type &key new-name return-element-type
                                                                   (register-p t) auto-p)
  "Compatibility element/result API backed by inferred constraints, not argument positions."
  (let* ((def (if (function-definition-p def-or-name) def-or-name (find-function-definition def-or-name)))
         (template (infer-function-template def))
         (result-element (or return-element-type new-element-type))
         (target (getf template :target))
         (bindings nil)
         (instance-name (or new-name
                            (keyword-id "~A/~A~A" (function-definition-name def)
                                        (type-slug new-element-type)
                                        (if (equal new-element-type result-element) ""
                                            (format nil "->~A" (type-slug result-element)))))))
    (dolist (spec (getf template :inputs))
      (when (seq-type-p (cdr spec))
        (setf bindings (bind-template-type (second (cdr spec)) new-element-type bindings))))
    (unless (eq target :bool)
      (setf bindings (bind-template-type (if (seq-type-p target) (second target) target)
                                         result-element bindings)))
    (let* ((input-types (mapcar (lambda (s) (fill-template-type (cdr s) template bindings))
                                (getf template :inputs)))
           (new-target (fill-template-type target template bindings))
           (old (and register-p (find-function-definition instance-name)))
           (entry (and old (find-knowledge-entry instance-name))))
      (if (and old (equal input-types (mapcar #'cdr (function-definition-inputs old)))
               (equal new-target (function-definition-return-type old))
               entry (equal (getf template :source)
                            (getf (getf (knowledge-entry-metadata entry) :type-template) :source)))
          old
          (let ((instance (instantiate-function-template def input-types new-target
                                                         :name instance-name :register-p register-p)))
            (when auto-p (setf (gethash instance-name *auto-retyped-functions*) t))
            instance)))))

(defun learn-knowledge-transformer (frame language description-limit work-limit
                                     &key id (library *knowledge-library*) metadata)
  "Learn a syntax-to-syntax program with the ordinary synthesis grammar.
Training replay supplies empirical evidence only. Consumers must check any
semantic conclusion independently; a transform is never itself a rewrite law."
  (let* ((schema (frame-schema frame))
         (job (start-search frame language)))
    (assert (code-type-p (schema-target schema)))
    (resume-search job description-limit work-limit)
    (values
     (when (search-job-best job)
       (register-knowledge-entry
        (make-knowledge-entry
         :id id :kind :transformer :inputs (schema-inputs schema) :target (schema-target schema)
         :expression (candidate-expression (search-job-best job)) :status :empirical
         :work (ledger-total (search-job-ledger job))
         :metadata (append (list :origin :synthesized :training-rows (length (frame-rows frame))) metadata)
         :library library)
        :library library))
     job)))

(define-knowledge-kind :transformer
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (assert (code-type-p (knowledge-entry-target entry)))
    (assert-entry-expression-type entry))
  (:consume (entry context ledger)
    (evaluate-guarded-entry entry context ledger)))

(defun induce-solvers-from-transformers (library ledger)
  "Execute learned library programs over quoted solver bodies, without family dispatch.
A transformer may declare an output solver operator/position/context in metadata.
The output is an ordinary conjectural witness, subject to forward replay."
  (let ((created nil))
    (dolist (transformer (active-knowledge-entries-of-kind :transformer library) (nreverse created))
      (let* ((meta (knowledge-entry-metadata transformer))
             (operator (getf meta :solver-operator))
             (scope (knowledge-entry-inputs transformer))
             (output (knowledge-entry-target transformer)))
        (when (and operator (= 1 (length scope)) (code-type-p (cdar scope)))
          (dolist (source (active-knowledge-entries-of-kind :solver library))
            (when (equal (cdar scope) (code-type (knowledge-entry-inputs source) (knowledge-entry-target source)))
              (let* ((id (keyword-id "~A/~A" (knowledge-entry-id transformer) (knowledge-entry-id source)))
                     (run (consume-knowledge-entry transformer (list (knowledge-entry-expression source))
                                                   :library library :ledger ledger)))
                (when (and run (eq :value (evaluation-status run)) (not (find-knowledge-entry id library)))
                  (push (register-knowledge-solver
                         (sexp->ast operator) :id id :library library
                         :inputs (code-inputs output) :target (code-sort output)
                         :position (getf meta :solver-position)
                         :context-map (getf meta :solver-context-map)
                         :witness (evaluation-value run) :unique-p nil
                         :edges (list (list :induced-by (knowledge-entry-id transformer) (knowledge-entry-id source)))
                         :ledger ledger)
                        created))))))))))
