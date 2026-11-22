(in-package #:lisploop)

;;; Pattern matching, typed anti-unification, substitution frames, and shared-subterm covers.

(defun pattern-has-holes-p (term)
  (not (null (pattern-holes term))))

(defun term-sort (term inputs)
  (if (operator-p term)
      (operator-type term)
      (expression-type term inputs t)))

(defun match-pattern (pattern source &optional inputs ledger)
  "Typed first-order matching, including symbols in operator position.
Return substitutions and a success flag; NIL substitutions can be a valid match."
  (unless (equal (term-sort pattern inputs) (term-sort source inputs))
    (return-from match-pattern (values nil nil)))
  (let ((substitutions nil))
    (labels ((walk (p s)
               (charge ledger :matching)
               (cond
                 ((hole-p p)
                  (and (equal (ast-type p) (term-sort s inputs))
                       (let ((entry (assoc (ast-id p) substitutions)))
                         (if entry (equal (cdr entry) s)
                             (progn (push (cons (ast-id p) s) substitutions) t)))))
                 ((equal p s) t)
                 ((and (app-p p) (app-p s)
                       (= (length (rest p)) (length (rest s))))
                  (and (walk (first p) (first s))
                       (every #'walk (rest p) (rest s))))
                 (t nil))))
      (let ((success (walk pattern source)))
        (values (and success (nreverse substitutions)) success)))))

(defun anti-unify (sources &optional inputs ledger &key (operator-holes-p t) keep-application-p)
  "Aligned typed syntactic LGG. Equal disagreement tuples reuse the same hole.
An incompatible operator signature falls back to a whole-expression hole if the
result types agree. Distinct result types have no common typed AST pattern.
Applications whose operators differ but share a signature are aligned under an operator
hole, unless OPERATOR-HOLES-P is false: then only applications of one operator are aligned.
KEEP-APPLICATION-P, if given, is called with the generalised arguments of an aligned
application and its source terms; when it returns false one hole stands for the application."
  (assert sources)
  (let ((disagreements (make-hash-table :test #'equal)) (next-id 0))
    (labels ((same-p (items)
               (every (lambda (item) (equal item (first items))) items))
             (disagreement (terms sort)
               (or (gethash terms disagreements)
                   (setf (gethash terms disagreements) (hole (prog1 next-id (incf next-id)) sort))))
             (generalize (terms)
               (charge ledger :anti-unification (length terms))
               (let ((sorts (mapcar (lambda (term) (term-sort term inputs)) terms))
                     (heads (and (every #'app-p terms) (mapcar #'first terms))))
                 (assert (same-p sorts))
                 (cond
                   ((same-p terms) (first terms))
                   ((and heads (same-p (if operator-holes-p (mapcar #'operator-type heads) heads)))
                    (let ((head (if operator-holes-p (generalize heads) (first heads)))
                          (arguments
                            (loop for i below (length (rest (first terms))) collect
                              (generalize (mapcar (lambda (term) (nth i (rest term))) terms)))))
                      (if (or (null keep-application-p) (funcall keep-application-p arguments terms))
                          (apply #'app head arguments)
                          (disagreement terms (first sorts)))))
                   (t (disagreement terms (first sorts)))))))
      (let ((pattern (generalize sources)))
        (values pattern
                (mapcar (lambda (source)
                          (multiple-value-bind (substitution matched)
                              (match-pattern pattern source inputs ledger)
                            (assert matched)
                            substitution)) sources))))))

(defun code-anti-unify-values (left right in-code-type out-code-type)
  "First-class VM execution of `:code-anti-unify`: compute the aligned first-order LGG of
LEFT and RIGHT (in scope `(code-inputs in-code-type)`), lowering pattern holes `?0, ?1, ...`
onto the extended scope variables of OUT-CODE-TYPE so `:code-match` and `:code-bind` recover
both residual substitutions directly."
  (let* ((in-inputs (code-inputs in-code-type))
         (out-inputs (code-inputs out-code-type))
         (base-len (length in-inputs))
         (extra-specs (subseq out-inputs (min base-len (length out-inputs)))))
    (assert (and (>= (length out-inputs) base-len)
                 (equal in-inputs (subseq out-inputs 0 base-len))))
    (let* ((raw-pattern (anti-unify (list left right) in-inputs nil :operator-holes-p nil))
           (holes (pattern-holes raw-pattern))
           (used nil)
           (hole-map
             (loop for (hid . hsort) in holes
                   for spec = (find-if (lambda (s)
                                         (and (not (member (car s) used))
                                              (equal (cdr s) hsort)))
                                       extra-specs)
                   do (assert spec () "Output code scope ~S lacks variable slot of type ~S for hole ~D"
                              out-code-type hsort hid)
                      (push (car spec) used)
                   collect (cons hid (var (car spec) (cdr spec))))))
      (let ((result (if hole-map
                        (instantiate raw-pattern hole-map :hole)
                        raw-pattern)))
        (assert (value-p result out-code-type))
        result))))

(defun au-substitutions-frame (pattern substitutions &key keys known inputs schema-inputs ledger)
  "The hole fillings that anti-unification recovered, as an ordinary frame: row i requires
the tuple of quoted values `(:tuple (:code inputs hole-sort) ...)` that SUBSTITUTIONS[i]
gives the holes of PATTERN, INPUTS being the scope of the unified terms. KEYS names the
rows, by default their positions. KNOWN holds each row's inputs under SCHEMA-INPUTS,
((id . type) ...); by default a row knows its position `(i)`, and integers given without a
schema are numbered from 0."
  (let* ((holes (pattern-holes pattern))
         (target-type (apply #'tuple-type
                             (mapcar (lambda (hole) (code-type inputs (cdr hole))) holes)))
         (known (or known (loop for i below (length substitutions) collect (list i))))
         (schema-inputs (or schema-inputs
                            (loop for i below (length (first known)) collect (cons i :int)))))
    (make-frame
     (make-schema :inputs schema-inputs :target target-type :lookup-p t)
     (loop for substitution in substitutions
           for index from 0
           for row-known in known
           for fillings = (mapcar (lambda (hole)
                                    (let ((entry (assoc (car hole) substitution)))
                                      (assert entry () "Missing binding for hole ~S" (car hole))
                                      (cdr entry)))
                                  holes)
           for requirement = (set-requirement target-type (list fillings))
           do (charge ledger :au-child-frame (syntax-work requirement))
           collect (make-row :key (if keys (nth index keys) index)
                             :known row-known :requirement requirement)))))

(defun compile-au-constructor (pattern scope &optional ledger)
  "A DSL program maps quoted hole fillings to the instantiated quoted expression.
Operator holes are quoted operator values, not callable host functions."
  (let ((inputs nil))
    (labels ((walk (node)
               (charge ledger :au-lowering (syntax-work node))
               (let ((type (code-type scope (term-sort node scope))))
                 (cond
                   ((hole-p node)
                    (let ((previous (assoc (ast-id node) inputs)))
                      (when previous (assert (equal (cdr previous) type)))
                      (unless previous (push (cons (ast-id node) type) inputs)))
                    (var (ast-id node) type))
                   ((not (pattern-has-holes-p node)) (lit type node))
                   (t (term `(code-apply ,(walk (first node))
                                         (tuple ,@(mapcar #'walk (rest node))))))))))
      (let ((model (walk pattern)))
        (charge ledger :construction (syntax-work model))
        (values model (nreverse inputs))))))

(defun term-references-bound-or-self-p (term bound-vars self-name)
  "True when TERM references any variable ID in BOUND-VARS or calls SELF-NAME."
  (cond
    ((var-p term) (not (null (member (ast-id term) bound-vars :test #'eql))))
    ((app-p term)
     (or (and self-name (operator-p (first term))
              (eq (canonical-op-name self-name) (operator-name (first term))))
         (some (lambda (arg) (term-references-bound-or-self-p arg bound-vars self-name))
               (rest term))))
    (t nil)))

(defun shared-subterm-cover (terms inputs &key bound-vars self-name)
  "Extract an ordered list of subterms A_0, ..., A_{m-1} from TERMS that cover all
references to BOUND-VARS (defaulting to all IDs in INPUTS) and SELF-NAME so each term
in TERMS can be abstracted into a closed :code literal over positional variables X0..X_{m-1}."
  (let* ((norm-inputs (input-alist inputs))
         (eff-vars (or bound-vars (mapcar #'car norm-inputs)))
         (eff-self (when self-name (canonical-op-name self-name)))
         (common-set (make-hash-table :test #'equal))
         (cover nil))
    (labels ((collect-subterms (node table)
               (when (term-references-bound-or-self-p node eff-vars eff-self)
                 (setf (gethash node table) t)
                 (when (app-p node)
                   (dolist (arg (rest node))
                     (collect-subterms arg table)))))
             (atomic-bound-unit-p (node)
               (or (and (var-p node) (member (ast-id node) eff-vars :test #'eql))
                   (and (app-p node) (operator-p (first node))
                        (let ((op-name (operator-name (first node))))
                          (or (and eff-self (eq op-name eff-self) (gethash node common-set))
                              (and (eq op-name :tail)
                                   (var-p (second node))
                                   (member (ast-id (second node)) eff-vars :test #'eql))
                              (and (eq op-name :at)
                                   (var-p (second node))
                                   (member (ast-id (second node)) eff-vars :test #'eql)
                                   (not (term-references-bound-or-self-p (third node) eff-vars eff-self))))))))
             (atomic-units (expr)
               (let ((acc nil))
                 (labels ((walk (n)
                            (when (term-references-bound-or-self-p n eff-vars eff-self)
                              (if (atomic-bound-unit-p n)
                                  (pushnew n acc :test #'equal)
                                  (when (app-p n)
                                    (dolist (arg (rest n))
                                      (walk arg)))))))
                   (walk expr)
                   (nreverse acc)))))
      (when terms
        (let ((tables (mapcar (lambda (term)
                                (let ((tbl (make-hash-table :test #'equal)))
                                  (collect-subterms term tbl)
                                  tbl))
                              terms)))
          (maphash (lambda (sub present)
                     (declare (ignore present))
                     (when (every (lambda (tbl) (gethash sub tbl)) (rest tables))
                       (setf (gethash sub common-set) t)))
                   (first tables))))
      (labels ((extract-from (node)
                 (when (term-references-bound-or-self-p node eff-vars eff-self)
                   (cond
                     ((and (gethash node common-set)
                           ;; Do not collapse the entire root term if all terms were supposed to diverge
                           (not (every (lambda (term) (equal node term)) terms))
                           ;; Keep shared subterm only if none of its atomic bound units appear outside it
                           (let ((node-units (atomic-units node))
                                 (dummy (let ((ntype (expression-type node norm-inputs)))
                                          (lit ntype (default-value-for-type ntype)))))
                             (and node-units
                                  (every (lambda (term)
                                           (let ((rem (replace-subexpression term node dummy)))
                                             (null (intersection node-units (atomic-units rem) :test #'equal))))
                                         terms))))
                      (pushnew node cover :test #'equal))
                     ((atomic-bound-unit-p node)
                      (pushnew node cover :test #'equal))
                     ((app-p node)
                      (dolist (arg (rest node))
                        (extract-from arg)))))))
        (dolist (term terms)
          (extract-from term))
        (stable-sort (nreverse cover)
                     (lambda (a b)
                       (and (not (term-references-bound-or-self-p a nil eff-self))
                            (term-references-bound-or-self-p b nil eff-self))))))))

(defun abstract-over-subterms (expr subterms inputs &optional ledger &key self-name)
  "Replace each subterm A_j in SUBTERMS within EXPR by positional variable `(var j type_j)`
and package the resulting closed body as `(lit (:code ((0 . type_0) ...) ret-type) body)`.
Returns (VALUES code-literal code-type body) or (VALUES nil nil nil) if EXPR still contains
unbound variables or self-calls outside SUBTERMS."
  (let* ((norm-inputs (input-alist inputs))
         (ret-type (expression-type expr norm-inputs))
         (eff-self (when self-name (canonical-op-name self-name)))
         (code-in (loop for sub in subterms
                        for j from 0
                        collect (cons j (expression-type sub norm-inputs))))
         (pairs (loop for sub in subterms
                      for (j . stype) in code-in
                      collect (cons sub (var j stype))))
         (unabstracted-p nil))
    (flet ((rewrite (node meta)
             ;; A covered subterm becomes its parameter. Any variable or self-call that is
             ;; reached outside every covered subterm means the cover is incomplete.
             (let ((match (assoc node pairs :test #'equal)))
               (cond (match (cdr match))
                     ((or (eq :var (ast-meta-kind meta))
                          (and eff-self (eq :app (ast-meta-kind meta))
                               (eq eff-self (ast-meta-id meta))))
                      (setf unabstracted-p t)
                      nil)))))
      (let ((body (map-ast #'rewrite expr :root-first t)))
        (if unabstracted-p
            (values nil nil nil)
            (let ((c-type (code-type code-in ret-type)))
              (charge ledger :construction (syntax-work body))
              (values (lit c-type body) c-type body)))))))

(defun pattern-holes (pattern)
  "Return the ordered list of unique (hole-id . hole-sort) pairs in pre-order."
  (let ((holes nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (unless (assoc (ast-id term) holes)
                    (push (cons (ast-id term) (ast-type term)) holes)))
                 ((app-p term)
                  (walk (first term))
                  (mapc #'walk (rest term))))))
      (walk pattern)
      (nreverse holes))))
