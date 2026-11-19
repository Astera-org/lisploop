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

(defun domain-template-bindings (template old-domain new-domain)
  "Bind every type variable in TEMPLATE whose default is OLD-DOMAIN to NEW-DOMAIN."
  (let ((bindings nil))
    (dolist (pair (getf template :defaults) bindings)
      (when (and (type-variable-p (car pair))
                 (equal (cdr pair) old-domain)
                 (not (assoc (car pair) bindings :test #'equal)))
        (push (cons (car pair) new-domain) bindings)))))

(defun solver-template-probe-ast (operator position context-map inputs target)
  "Synthetic equation `(= (operator ... z ...) target-var)` tying a `:solver`'s operator,
context inputs, and unknown target together for constraint-based type unification."
  (let* ((positions (solver-positions position))
         (z-id (next-child-id inputs))
         (z-var (var z-id target))
         (target-pos (position :target context-map))
         (target-spec (nth target-pos inputs))
         (app-expr
           (apply #'app operator
                  (loop for index below (length (second (operator-type operator)))
                        for place = (position index positions)
                        collect (cond ((null place)
                                       (let ((spec (nth (position (list :argument index) context-map
                                                                  :test #'equal)
                                                        inputs)))
                                         (var (car spec) (cdr spec))))
                                      ((rest positions)
                                       (term `(at ,z-var ,place)))
                                      (t z-var))))))
    (values (app (op := (cdr target-spec)) app-expr (var (car target-spec) (cdr target-spec)))
            (cons z-id target))))

(defun infer-ast-templates (inputs target ast-alist &key self-name)
  "Infer polymorphic type roles across INPUTS, TARGET (when non-nil), and `(key . ast)` pairs in
AST-ALIST by unifying primitive signature constraints. Returns a portable template plist."
  (let ((counter 0)
        (substitution (make-hash-table :test #'equal))
        (hole-env nil)
        (defaults nil))
    (labels
        ((fresh (default)
           (let ((v (list :type-variable (incf counter))))
             (push (cons v default) defaults)
             v))
         (shape (type)
           (cond ((eq type :bool) :bool)
                 ((code-type-p type)
                  (let ((sort (code-sort type)))
                    (list :code
                          (mapcar (lambda (s) (cons (car s) (shape (cdr s)))) (code-inputs type))
                          (if (function-sort-p sort)
                              (list :fn (mapcar #'shape (second sort)) (shape (third sort)))
                              (shape sort)))))
                 ((function-sort-p type)
                  (list :fn (mapcar #'shape (second type)) (shape (third type))))
                 ((and (consp type) (member (first type) '(:seq :tuple)))
                  (cons (first type) (mapcar #'shape (rest type))))
                 (t (fresh type))))
         (resolve (type)
           (substitute-type-variables type (lambda (v) (gethash v substitution))))
         (tree-find (needle tree)
           (or (equal needle tree)
               (and (consp tree) (or (tree-find needle (car tree)) (tree-find needle (cdr tree))))))
         (unify (left right)
           (let ((a (resolve left)) (b (resolve right)))
             (cond ((equal a b) nil)
                   ((type-variable-p a)
                    (assert (not (tree-find a b)))
                    (setf (gethash a substitution) b))
                   ((type-variable-p b) (unify b a))
                   ((and (consp a) (consp b))
                    (unify (car a) (car b))
                    (unify (cdr a) (cdr b)))
                   (t (error "Incompatible template types ~S and ~S" a b)))))
         (scope (specs) (mapcar (lambda (s) (cons (car s) (shape (cdr s)))) specs))
         (walk-op (old-op)
           (let ((name (operator-name old-op)))
             (cond
               ((signature-pattern name)
                (destructuring-bind (parameter-pattern argument-patterns result-pattern)
                    (signature-pattern name)
                  (let* ((param (shape (operator-operand-type old-op)))
                         (bound (match-type-pattern parameter-pattern param)))
                    (values (list :op name param)
                            (list :fn (sublis bound argument-patterns) (sublis bound result-pattern))))))
               (t
                (values (list :op name (operator-operand-type old-op))
                        (operator-type old-op))))))
         (walk (expr env self-inputs self-result)
           (case (ast-kind expr)
             (:var (let ((type (cdr (assoc (ast-id expr) env))))
                     (assert type)
                     (values (list :var (ast-id expr) type) type)))
             (:hole (let ((type (or (cdr (assoc (ast-id expr) hole-env))
                                    (let ((shaped (shape (ast-type expr))))
                                      (push (cons (ast-id expr) shaped) hole-env)
                                      shaped))))
                      (values (list :hole (ast-id expr) type) type)))
             (:op (walk-op expr))
             (:lit
              (let ((type (shape (ast-type expr))))
                (if (code-type-p (ast-type expr))
                    (let ((sort (code-sort type)))
                      (if (function-sort-p sort)
                          (multiple-value-bind (op-node op-sig) (walk-op (ast-value expr))
                            (unify op-sig sort)
                            (values (list :lit type op-node) type))
                          (multiple-value-bind (body result)
                              (walk (ast-value expr) (code-inputs type) self-inputs self-result)
                            (unify result sort)
                            (values (list :lit type body) type))))
                    (values (list :lit type (copy-tree (ast-value expr))) type))))
             (:app
              (let* ((head (first expr))
                     (nodes nil) (types nil) (out nil) (op-node nil))
                (dolist (arg (rest expr))
                  (multiple-value-bind (node type) (walk arg env self-inputs self-result)
                    (push node nodes) (push type types)))
                (setf nodes (nreverse nodes) types (nreverse types))
                (if (hole-p head)
                    (multiple-value-bind (hnode htype) (walk head env self-inputs self-result)
                      (let ((hsort (resolve htype)))
                        (assert (function-sort-p hsort))
                        (mapc #'unify types (second hsort))
                        (setf op-node hnode out (third hsort))))
                    (let ((name (ast-id expr))
                          (old-op head)
                          (parameter nil))
                      (flet ((same (a b) (unify a b)))
                        (cond
                          ((and self-name (eq name self-name))
                           (mapc #'same types (mapcar #'cdr self-inputs))
                           (setf out self-result parameter (list :code self-inputs self-result)))
                          ((eq name :at)
                           (same (second types) :int)
                           (let ((container (resolve (first types))))
                             (cond
                               ((eq :tuple (first container))
                                (let ((idx (and (lit-p (third expr)) (ast-value (third expr)))))
                                  (if (and (integerp idx) (<= 0 idx) (< idx (length (rest container))))
                                      (setf out (nth idx (rest container)))
                                      (progn
                                        (setf out (second container))
                                        (dolist (part (rest container)) (same part out)))))
                                (setf parameter (tuple-type container out)))
                               (t
                                (setf parameter container out (second container))))))
                          ((eq name :tuple)
                           (setf out (cons :tuple types) parameter out))
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
                          ((eq name :code-apply)
                           (let* ((fn-ctype (resolve (first types)))
                                  (args-tuple (resolve (second types)))
                                  (c-scope (code-inputs fn-ctype))
                                  (fn-sort (code-sort fn-ctype)))
                             (loop for bt in (rest args-tuple)
                                   for at in (second fn-sort)
                                   do (same bt (list :code c-scope at)))
                             (setf out (list :code c-scope (third fn-sort))
                                   parameter fn-ctype)))
                          ((eq name :code-operator)
                           (let ((res-ctype (resolve (first types))))
                             (setf parameter (shape (operator-operand-type old-op)))
                             (same res-ctype (list :code (code-inputs parameter)
                                                   (third (code-sort parameter))))
                             (setf out parameter)))
                          ((eq name :code-match)
                           (let ((a (resolve (first types)))
                                 (b (resolve (second types))))
                             (same (code-sort a) (code-sort b))
                             (setf out :bool parameter (tuple-type a b))))
                          ((eq name :code-bind)
                           (let ((a (resolve (first types)))
                                 (b (resolve (second types))))
                             (same (third types) :int)
                             (same (code-sort a) (code-sort b))
                             (setf out (shape (ast-type expr)))
                             (same (code-inputs b) (code-inputs out))
                             (setf parameter (tuple-type a b out))))
                          ((eq name :code-child)
                           (let ((a (resolve (first types))))
                             (same (second types) :int)
                             (setf out (shape (ast-type expr)))
                             (same (code-inputs a) (code-inputs out))
                             (setf parameter (tuple-type a out))))
                          ((signature-pattern name)
                           (destructuring-bind (parameter-pattern argument-patterns result-pattern)
                               (signature-pattern name)
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
                           ;; Monomorphic primitives and defined functions stay monomorphic unless retyped.
                           (mapc #'same types (second (operator-type old-op)))
                           (setf out (third (operator-type old-op))
                                 parameter (operator-operand-type old-op)))))
                      (setf op-node (list :op name parameter))))
                (values (list* :app op-node nodes) out)))
             (otherwise (error "Unsupported template node ~S" expr)))))
      (let* ((shaped-inputs (scope inputs))
             (shaped-target (and target (shape target)))
             (walked-asts nil))
        (dolist (pair ast-alist)
          (when (cdr pair)
            (let ((slot-env (if (and (eq :trigger (car pair)) shaped-inputs shaped-target)
                                (list (cons 0 (cdr (first shaped-inputs)))
                                      (cons 1 shaped-target))
                                shaped-inputs)))
              (multiple-value-bind (node result)
                  (walk (cdr pair) slot-env shaped-inputs shaped-target)
                (when (and (member (car pair) '(:expression :z-ref)) shaped-target)
                  (unify result shaped-target))
                (when (member (car pair) '(:guard :trigger :probe))
                  (unify result :bool))
                (push (cons (car pair) node) walked-asts)))))
        (let ((resolved-asts (loop for (k . node) in (nreverse walked-asts)
                                   collect (cons k (resolve node)))))
          (list :inputs (resolve shaped-inputs)
                :target (and shaped-target (resolve shaped-target))
                :asts resolved-asts
                :body (cdr (assoc :expression resolved-asts))
                :defaults (mapcar (lambda (pair) (cons (resolve (car pair)) (cdr pair)))
                                  (nreverse defaults))
                :source (loop for (k . ast) in ast-alist
                              when ast collect (cons k (ast->sexp ast)))))))))

(defun instantiate-template-ast (node template bindings &key self-name self-op)
  "Instantiate a resolved template AST NODE under BINDINGS."
  (when node
    (labels ((fill-type (type) (fill-template-type type template bindings))
             (build (n)
               (ecase (first n)
                 (:var (var (second n) (fill-type (third n))))
                 (:hole (hole (second n) (fill-type (third n))))
                 (:op (if (and self-name (eq (second n) self-name))
                          self-op
                          (op (second n) (fill-type (third n)))))
                 (:lit (let ((type (fill-type (second n))))
                         (lit type (if (code-type-p type)
                                       (build (third n))
                                       (retype-value (third n) type)))))
                 (:app (apply #'app (build (second n)) (mapcar #'build (cddr n)))))))
      (build node))))

(defun infer-function-template (definition)
  "Infer type roles of `function-definition` DEFINITION by unifying primitive constraints."
  (let* ((def (if (function-definition-p definition) definition (find-function-definition definition)))
         (tpl (infer-ast-templates (function-definition-inputs def)
                                   (function-definition-return-type def)
                                   (list (cons :expression (function-definition-body def)))
                                   :self-name (function-definition-name def))))
    (setf (getf tpl :source) (ast->sexp (function-definition-body def)))
    tpl))

(defun entry-function-definition (entry)
  "The definition of ENTRY, a `:function` entry: the registered one, or one made of the entry."
  (or (find-function-definition (knowledge-entry-id entry))
      (%make-function-definition :name (knowledge-entry-id entry)
                                 :inputs (knowledge-entry-inputs entry)
                                 :return-type (knowledge-entry-target entry)
                                 :body (knowledge-entry-expression entry))))

(defun infer-entry-template (entry)
  "Infer a polymorphic template across all AST slots of `knowledge-entry` ENTRY (`:function`,
`:solver`, `:law`, `:descriptor`, `:transformer`, `:motif`, `:decoder-template`, etc.). A
solver's types are tied to its operator's through the equation it solves
(`solver-template-probe-ast`), and its template records the operator under :operator."
  (let* ((inputs (knowledge-entry-inputs entry))
         (target (knowledge-entry-target entry))
         (meta (knowledge-entry-metadata entry))
         (asts (list (cons :expression (knowledge-entry-expression entry))
                     (cons :guard (knowledge-entry-guard entry))
                     (cons :trigger (knowledge-entry-trigger entry))
                     (cons :auxiliary-code (knowledge-entry-auxiliary-code entry)))))
    (cond
      ((eq :function (knowledge-entry-kind entry))
       (infer-function-template (entry-function-definition entry)))
      ((and (eq :solver (knowledge-entry-kind entry)) (getf meta :operator))
       (let* ((operator (sexp->ast (getf meta :operator)))
              (position (getf meta :position)))
         (multiple-value-bind (probe unknown)
             (solver-template-probe-ast operator position
                                        (or (getf meta :context-map)
                                            (solver-context-map operator position))
                                        inputs target)
           (let ((template (infer-ast-templates
                            (append inputs (list unknown)) target
                            (list* (cons :z-ref (var (car unknown) (cdr unknown)))
                                   (cons :probe probe)
                                   asts))))
             ;; The unknown is no input of the solver; the probe applies the operator to it.
             (setf (getf template :operator)
                   (second (third (cdr (assoc :probe (getf template :asts)))))
                   (getf template :inputs) (butlast (getf template :inputs)))
             template))))
      (t (infer-ast-templates inputs target asts)))))

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
                                                           input-types nil)))
         (inputs (loop for (id . nil) in (getf template :inputs) for type in input-types
                       collect (cons id type)))
         (new (define-function new-name inputs target
                (lambda (self)
                  (instantiate-template-ast (getf template :body) template bindings
                                            :self-name (function-definition-name def)
                                            :self-op self))))
         (entry (find-knowledge-entry new-name)))
    (when entry (setf (getf (knowledge-entry-metadata entry) :type-template) template))
    new))

(defun instantiate-entry-template (entry &key bindings domain input-types target id
                                              (register-p nil) (certify-p t)
                                              (library *knowledge-library*) ledger)
  "Instantiate `knowledge-entry` ENTRY across concrete types via constraint-based template
unification. Certificates never copy across types: finite `:solver` and `:law` instantiations
re-certify exhaustively when CERTIFY-P is true; infinite instantiations become conjectures."
  (let* ((src (if (knowledge-entry-p entry) entry (find-knowledge-entry entry library)))
         (kind (knowledge-entry-kind src))
         (template (infer-entry-template src))
         (eff-bindings
           (let ((b (copy-list bindings)))
             (when input-types
               (setf b (bind-template-type (mapcar #'cdr (getf template :inputs)) input-types b)))
             (when target
               (setf b (bind-template-type (getf template :target) target b)))
             (when domain
               (dolist (pair (domain-template-bindings template (knowledge-entry-domain src) domain))
                 (unless (assoc (car pair) b :test #'equal)
                   (push pair b))))
             b))
         (inst-inputs (loop for (vid . vtype) in (getf template :inputs)
                            collect (cons vid (fill-template-type vtype template eff-bindings))))
         (inst-target (and (getf template :target)
                           (fill-template-type (getf template :target) template eff-bindings)))
         (asts (getf template :asts))
         (inst-domain (or domain
                          (infer-domain-from-types
                           (append (when inst-target (list inst-target))
                                   (mapcar #'cdr inst-inputs))))))
    (flet ((slot (key)
             (let ((node (cdr (assoc key asts))))
               (and node (instantiate-template-ast node template eff-bindings)))))
      (case kind
        (:function
         (let ((def (instantiate-function-template (entry-function-definition src)
                                                   (mapcar #'cdr inst-inputs) inst-target
                                                   :name id :register-p register-p)))
           (or (and register-p (find-knowledge-entry (function-definition-name def) library))
               def)))
        (:solver
         (let* ((meta (knowledge-entry-metadata src))
                (inst-op (instantiate-template-ast (getf template :operator) template eff-bindings))
                (finite-p (every #'finite-type-p (cons inst-target (mapcar #'cdr inst-inputs))))
                (solver (make-knowledge-solver
                         inst-op
                         :id (or id (unless register-p (knowledge-entry-id src)))
                         :library (and register-p library)
                         :domain inst-domain
                         :inputs inst-inputs :target inst-target
                         :position (getf meta :position)
                         :context-map (getf meta :context-map)
                         :witness (slot :expression)
                         :guard (slot :guard)
                         :domain-guard (slot :auxiliary-code)
                         :unique-p (if (and finite-p (getf meta :finite-unique-p))
                                       t
                                       (getf meta :unique-p))
                         :necessary-p (getf meta :necessary-p)
                         :certified-p (and certify-p finite-p)
                         :metadata (when (and (not finite-p) (getf meta :finite-unique-p))
                                     (list :finite-unique-p t))
                         :ledger ledger)))
           (if register-p
               (register-knowledge-entry solver :library library :ledger ledger)
               solver)))
        (:law
         (let* ((eq-expr (slot :expression))
                (guard-expr (or (slot :guard) (lit :bool t)))
                (saved-counter (and library (knowledge-library-entry-counter library)))
                (law (make-law inst-domain inst-inputs (second eq-expr) (third eq-expr)
                               :guard guard-expr
                               :origin (list :instantiated-from (knowledge-entry-id src)))))
           (when (and library (not register-p))
             (setf (knowledge-library-entry-counter library) saved-counter))
           (setf (knowledge-entry-id law)
                 (canonical-op-name (or id (if register-p
                                               (knowledge-entry-id law)
                                               (knowledge-entry-id src)))))
           (cond
             ((and certify-p (every #'finite-type-p (mapcar #'cdr inst-inputs)))
              (let ((val (validate-law law 1000000 nil nil)))
                (when ledger
                  (charge ledger :law-checking (ledger-total (law-validation-ledger val))))
                (if register-p
                    (register-knowledge-law val :id id :library library :ledger ledger)
                    (law-validation-law val))))
             (register-p
              (register-knowledge-law law :id id :library library :status :conjecture :ledger ledger))
             (t law))))
        (otherwise
         (let* ((inst-expr (slot :expression))
                (clean-meta (copy-list (knowledge-entry-metadata src)))
                (_ (remf clean-meta :type-template))
                (_2 (when (and inst-expr (getf clean-meta :dependencies))
                      (setf (getf clean-meta :dependencies)
                            (expression-dependencies (list inst-expr)))))
                (built (make-knowledge-entry
                        :id (or id (if register-p
                                       (next-knowledge-entry-id library kind)
                                       (knowledge-entry-id src)))
                        :kind kind
                        :domain inst-domain
                        :inputs inst-inputs
                        :target inst-target
                        :expression inst-expr
                        :guard (or (slot :guard) (lit :bool t))
                        :trigger (slot :trigger)
                        :auxiliary-code (slot :auxiliary-code)
                        :status (if (eq kind :descriptor) :empirical :conjecture)
                        :certificate nil
                        :metadata clean-meta
                        :library (and register-p library))))
           (declare (ignore _ _2))
           (if register-p
               (register-knowledge-entry built :library library :ledger ledger)
               built)))))))

(defun retype-expr (expr old-domain new-domain)
  "Retype EXPR from OLD-DOMAIN to NEW-DOMAIN via constraint-based template unification,
preserving structural `:int` positions (such as `:length` outputs and `:at` indices)."
  (let* ((vars (when (member (ast-kind expr) '(:var :lit :app :hole))
                 (let ((found nil))
                   (labels ((collect-vars (node)
                              (case (ast-kind node)
                                (:var (pushnew (cons (ast-id node) (ast-type node)) found :test #'equal))
                                (:app (mapc #'collect-vars (rest node))))))
                     (collect-vars expr))
                   (sort found #'< :key #'car))))
         (tpl (infer-ast-templates vars nil (list (cons :expr expr))))
         (bindings (domain-template-bindings tpl old-domain new-domain)))
    (instantiate-template-ast (cdr (assoc :expr (getf tpl :asts))) tpl bindings)))

(defun retype-law (law domain)
  "Retype `:law` LAW to DOMAIN via constraint-based unification; no certificate transfers."
  (let* ((old-domain (knowledge-entry-domain law))
         (new-law (instantiate-entry-template law :domain domain :certify-p nil)))
    ;; Reject vacuous retypings where every position remained pinned to OLD-DOMAIN.
    (assert (not (and (equal (knowledge-entry-inputs new-law) (knowledge-entry-inputs law))
                      (equal (knowledge-entry-expression new-law) (knowledge-entry-expression law))
                      (equal (knowledge-entry-guard new-law) (knowledge-entry-guard law)))))
    (when (finite-type-p domain)
      (assert (every #'finite-type-p (mapcar #'cdr (knowledge-entry-inputs new-law)))))
    new-law))

(defun retype-knowledge-laws (library new-domain &key (validate-p t) (samples nil samples-p)
                                                   (work-limit 1000000) ledger)
  "Retype `:law` entries in LIBRARY from their source domain to NEW-DOMAIN, recording
`:retyped-from` edges, optionally validating them in NEW-DOMAIN, and registering non-refuted laws."
  (let ((created nil))
    (dolist (entry (knowledge-entries-of-kind :law library) (nreverse created))
      (let ((new-law (and (not (equal new-domain (knowledge-entry-domain entry)))
                          (ignore-errors (retype-law entry new-domain)))))
        (flet ((register (law-or-validation &rest keys)
                 (push (apply #'register-knowledge-law law-or-validation :library library
                              :edges (list (list :retyped-from (knowledge-entry-id entry)))
                              :ledger ledger keys)
                       created)))
          (cond
            ((null new-law))
            ((some (lambda (existing)
                     (and (equal new-domain (knowledge-entry-domain existing))
                          (equal (knowledge-entry-expression new-law) (knowledge-entry-expression existing))
                          (equal (knowledge-entry-guard new-law) (knowledge-entry-guard existing))))
                   (knowledge-entries-of-kind :law library)))
            (validate-p
             (let ((finished (validate-law new-law work-limit
                                           (or samples-p (not (finite-type-p new-domain))) samples)))
               (charge ledger :law-checking (ledger-total (law-validation-ledger finished)))
               (when (member (law-validation-status finished) '(:validated :conjecture))
                 (register finished))))
            (t (register new-law :status :conjecture))))))))

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
    (dolist (transformer (knowledge-entries-of-kind :transformer library) (nreverse created))
      (let* ((meta (knowledge-entry-metadata transformer))
             (operator (getf meta :solver-operator))
             (scope (knowledge-entry-inputs transformer))
             (output (knowledge-entry-target transformer)))
        (when (and operator (= 1 (length scope)) (code-type-p (cdar scope)))
          (dolist (source (knowledge-entries-of-kind :solver library))
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
