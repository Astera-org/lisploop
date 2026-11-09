(in-package #:lisploop)

;;; Supplied structural inverter proposals. These constructors are not learned
;;; theories; generated witnesses require independent evidence or forward replay.

(defun map-like-combinator-signature (fdef)
  "If FDEF is a higher-order list-mapping combinator taking `(X0 : (:seq elem))` and
`(X1 : (:code ((0 . elem)) elem))` and returning `(:seq elem)` via `function-body-length-preserving-p`,
return `(VALUES elem-type seq-type code-type)`."
  (when (and (function-definition-p fdef)
             (function-definition-body fdef)
             (= 2 (length (function-definition-inputs fdef))))
    (let* ((inps (function-definition-inputs fdef))
           (t0 (cdr (first inps)))
           (t1 (cdr (second inps)))
           (ret (function-definition-return-type fdef)))
      (when (and (consp t0) (eq :seq (first t0))
                 (equal t0 ret)
                 (code-type-p t1)
                 (= 1 (length (code-inputs t1)))
                 (eql 0 (caar (code-inputs t1)))
                 (equal (second t0) (cdar (code-inputs t1)))
                 (equal (second t0) (code-sort t1))
                 (function-body-length-preserving-p (function-definition-name fdef)
                                                    (function-definition-body fdef)))
        (values (second t0) t0 t1)))))

(defun build-functorial-map-inverter (map-name elem-type seq-type src-ctype elem-solver)
  "Construct a second-order VM guard, witness, and code-inverter AST for inverting
`(:map z 'code) = c` at position 0 using binary element solver ELEM-SOLVER."
  (let* ((meta (knowledge-entry-metadata elem-solver))
         (op-name (or (getf meta :operator-name)
                      (let ((op-ast (sexp->ast (getf meta :operator))))
                        (and (operator-p op-ast) (operator-name op-ast)))))
         (elem-pos (getf meta :position))
         (elem-witness (knowledge-entry-expression elem-solver)))
    (when (and op-name (member elem-pos '(0 1)) elem-witness)
      (let* ((pat-ctype (code-type (list (cons 0 elem-type) (cons 1 elem-type)) elem-type))
             (pat-ast (lit pat-ctype (app (op op-name elem-type)
                                          (var 0 elem-type)
                                          (var 1 elem-type))))
             (known-code (var 0 src-ctype))
             (target-seq (var 1 seq-type))
             (bind-type (tuple-type pat-ctype src-ctype src-ctype))
             (b0 (app (op :code-bind bind-type) pat-ast known-code (lit :int 0)))
             (b1 (app (op :code-bind bind-type) pat-ast known-code (lit :int 1)))
             (var-part (if (zerop elem-pos) b0 b1))
             (const-part (if (zerop elem-pos) b1 b0))
             (subst-tup-type (tuple-type src-ctype src-ctype))
             (subst-type (tuple-type pat-ctype subst-tup-type src-ctype))
             (inv-code-expr (app (op :code-subst subst-type)
                                 (lit pat-ctype elem-witness)
                                 (app (op :tuple subst-tup-type)
                                      const-part
                                      (lit src-ctype (var 0 elem-type)))))
             (match-cond (app (op :code-match (tuple-type pat-ctype src-ctype))
                              pat-ast known-code))
             (var-ok (app (op := src-ctype) var-part (lit src-ctype (var 0 elem-type))))
             (const-ok (app (op := :int) (app (op :code-kind src-ctype) const-part) (lit :int 1)))
             (total-ok (app (op :code-total src-ctype) inv-code-expr))
             (guard-ast (app (op :if :bool)
                             match-cond
                             (bool-and var-ok (bool-and const-ok total-ok))
                             (lit :bool nil)))
             (witness-ast (app (op map-name) target-seq inv-code-expr)))
        (values guard-ast witness-ast inv-code-expr op-name elem-pos)))))

(defun extract-pointwise-binary-step (src-entry elem-type seq-type)
  "If `:function` entry SRC-ENTRY has signature `((0 . seq-type) (1 . elem-type)) -> seq-type`
and applies a binary scalar operator `(op elem param)` or `(op param elem)` to each element
of `X0` with parameter `X1` (either via `:map` + `:code-subst` or direct structural recursion),
return (VALUES op-name elem-pos param-pos)."
  (let ((inputs (knowledge-entry-inputs src-entry))
        (target (knowledge-entry-target src-entry))
        (expr (knowledge-entry-expression src-entry))
        (aux (knowledge-entry-auxiliary-code src-entry)))
    (when (and (= 2 (length inputs))
               (equal (cons 0 seq-type) (first inputs))
               (equal (cons 1 elem-type) (second inputs))
               (equal seq-type target))
      (flet ((check-binary-op (step elem-var param-var)
               (when (and (app-p step)
                          (operator-p (first step))
                          (= 2 (length (rest step))))
                 (let ((op-name (operator-name (first step)))
                       (a0 (second step))
                       (a1 (third step)))
                   (cond
                     ((and (equal a0 elem-var) (equal a1 param-var))
                      (values op-name 0 1))
                     ((and (equal a0 param-var) (equal a1 elem-var))
                      (values op-name 1 0)))))))
        (let ((v0 (var 0 elem-type))
              (v1 (var 1 elem-type)))
          (or (and aux
                   (multiple-value-bind (op-name epos ppos)
                       (check-binary-op aux v0 v1)
                     (when op-name (return-from extract-pointwise-binary-step (values op-name epos ppos)))))
              (when (and (app-p expr) (= 2 (length (rest expr))))
                (let ((code-arg (third expr)))
                  (when (and (app-p code-arg)
                             (eq :code-subst (ast-id code-arg))
                             (lit-p (second code-arg)))
                    (multiple-value-bind (op-name epos ppos)
                        (check-binary-op (ast-value (second code-arg)) v0 v1)
                      (when op-name (return-from extract-pointwise-binary-step (values op-name epos ppos)))))))
              (when (and (app-p expr) (eq :if (ast-id expr)))
                (let ((else-br (fourth expr))
                      (head-x0 (app (op :at seq-type) (var 0 seq-type) (lit :int 0))))
                  (when (and (app-p else-br) (eq :cons (ast-id else-br)))
                    (multiple-value-bind (op-name epos ppos)
                        (check-binary-op (second else-br) head-x0 v1)
                      (when op-name (return-from extract-pointwise-binary-step (values op-name epos ppos)))))))))))))

(defun induce-involution-solvers (library &key (ledger (make-ledger)))
  "Scan `:law` entries in LIBRARY for involution identities `(= (f (f X0)) X0)` over a unary
function or operator `f : tau -> tau` and induce `:unary` `:solver` entries `(f X0)`."
  (let ((induced nil))
    (dolist (law-entry (knowledge-entries-of-kind :law library) (nreverse induced))
      (let ((eq-expr (knowledge-entry-expression law-entry))
            (inputs (knowledge-entry-inputs law-entry)))
        (when (and (= 1 (length inputs))
                   (app-p eq-expr)
                   (eq := (ast-id eq-expr))
                   (= 2 (length (rest eq-expr))))
          (let* ((tau (cdar inputs))
                 (x0 (var (caar inputs) tau))
                 (lhs (second eq-expr))
                 (rhs (third eq-expr))
                 (nested (cond ((equal rhs x0) lhs)
                               ((equal lhs x0) rhs))))
            (when (and nested
                       (app-p nested)
                       (operator-p (first nested))
                       (= 1 (length (rest nested)))
                       (let ((inner (second nested)))
                         (and (app-p inner)
                              (equal (first nested) (first inner))
                              (= 1 (length (rest inner)))
                              (equal (second inner) x0))))
              (let* ((fn-op (first nested))
                     (fn-name (operator-name fn-op))
                     (solver-id (intern (format nil "~A/INVOLUTION-INVERTER" (symbol-name fn-name)) :keyword))
                     (cert-p (knowledge-evidence-current-p law-entry :equivalence))
                     (guard (instantiate (or (knowledge-entry-guard law-entry) (lit :bool t))
                                         (list (cons (caar inputs) (var 0 tau))) :var))
                     (unique-p (and cert-p (equal guard (lit :bool t)))))
                (unless (find-knowledge-entry solver-id library)
                  (push (register-knowledge-solver
                         fn-op
                         :id solver-id
                         :library library
                         :domain (or (knowledge-entry-domain law-entry) tau)
                         :inputs (list (cons 0 tau))
                         :target tau
                         :position :unary
                         :witness (app fn-op (var 0 tau))
                         :guard guard
                         :certified-p cert-p
                         :unique-p unique-p
                         :status (if cert-p :validated :conjecture)
                         :edges (list (list :induced-by (knowledge-entry-id law-entry)))
                         :ledger ledger)
                        induced))))))))))

(defun induce-functorial-solvers (library &key (ledger (make-ledger)))
  "Traverse higher-order `:abstracts` / `:refactored-by` edges, element `:solver` entries, and
involution `:law` entries in LIBRARY to induce second-order `:functor` theories and concrete
`:solver` propagators for:
1. Higher-order combinators `(map z 'code) = c` (using `:code-match`, `:code-bind`, `:code-subst` in the VM),
2. First-order unary functions refactored through those combinators `(fn z) = c`,
3. Parameterized binary sequence functions `(fn xs param) = c` at both position 0 (`xs`) and position 1 (`param`), and
4. Involution functions satisfying `(= (f (f X0)) X0)`."
  (let ((induced nil))
    (dolist (fn-entry (knowledge-entries-of-kind :function library))
      (let* ((map-name (knowledge-entry-id fn-entry))
             (fdef (or (gethash map-name (knowledge-library-functions library))
                       (find-function-definition map-name))))
        (multiple-value-bind (elem-type seq-type src-ctype)
            (map-like-combinator-signature fdef)
          (when elem-type
            (let ((elem-solvers
                    (remove-if-not (lambda (s)
                                     (and (equal elem-type (knowledge-entry-domain s))
                                          (equal elem-type (knowledge-entry-target s))
                                          (equal (knowledge-entry-inputs s)
                                                 (list (cons 0 elem-type) (cons 1 elem-type)))
                                          (member (getf (knowledge-entry-metadata s) :position) '(0 1))))
                                   (knowledge-entries-of-kind :solver library))))
              (when elem-solvers
                (let ((functor-id (intern (format nil "~A/FUNCTOR" (symbol-name map-name)) :keyword)))
                  (unless (find-knowledge-entry functor-id library)
                    (push (register-knowledge-entry
                           (make-knowledge-entry
                            :id functor-id
                            :kind :functor
                            :domain elem-type
                            :inputs (list (cons 0 src-ctype) (cons 1 seq-type))
                            :target seq-type
                            :expression (app (op map-name) (var 1 seq-type) (var 0 src-ctype))
                            :status :conjecture
                            :metadata (list :origin :bootstrap-structural :combinator map-name)
                            :edges (list (list :lifts-inverter map-name))
                            :library library)
                           :library library :ledger ledger)
                          induced))
                  (dolist (esolver elem-solvers)
                    (multiple-value-bind (guard-ast witness-ast inv-code-expr op-name elem-pos)
                        (build-functorial-map-inverter map-name elem-type seq-type src-ctype esolver)
                      (when (and guard-ast witness-ast)
                        (let ((map-solver-id
                                (intern (format nil "~A/INVERT-~A-~D"
                                                (symbol-name map-name)
                                                (symbol-name op-name)
                                                elem-pos)
                                        :keyword))
                              (map-inputs (list (cons 0 src-ctype) (cons 1 seq-type)))
                              ;; Shape recognition and scalar certification do not
                              ;; certify this sequence transformation: the scalar
                              ;; guard and the combinator's semantics need proofs.
                              ;; Keep forward verification and the fallback lane.
                              (cert-p nil))
                          (unless (find-knowledge-entry map-solver-id library)
                            (push (register-knowledge-solver
                                   map-name
                                   :id map-solver-id
                                   :library library
                                   :domain elem-type
                                   :inputs map-inputs
                                   :target seq-type
                                   :position 0
                                   :witness witness-ast
                                   :guard guard-ast
                                   :certified-p cert-p
                                   :unique-p (getf (knowledge-entry-metadata esolver) :unique-p t)
                                   :status (if cert-p :validated :conjecture)
                                   :edges (list (list :induced-by functor-id (knowledge-entry-id esolver)))
                                   :ledger ledger)
                                  induced))
                          ;; Induce unary inverters for unary functions refactored through MAP-NAME
                          (dolist (edge (knowledge-edges-from map-name :abstracts library))
                            (dolist (src-fn (rest edge))
                              (let* ((src-entry (find-knowledge-entry src-fn library))
                                     (step-ast (and src-entry
                                                    (= 1 (length (knowledge-entry-inputs src-entry)))
                                                    (knowledge-entry-auxiliary-code src-entry)))
                                     (unary-id (intern (format nil "~A/INVERTER" (symbol-name src-fn)) :keyword)))
                                (when (and step-ast (null (find-knowledge-entry unary-id library)))
                                  (let ((grun (evaluate guard-ast map-inputs (list step-ast nil) :ledger ledger)))
                                    (when (and (eq :value (evaluation-status grun))
                                               (evaluation-value grun))
                                      (let ((irun (evaluate inv-code-expr (list (cons 0 src-ctype))
                                                            (list step-ast) :ledger ledger)))
                                        (when (eq :value (evaluation-status irun))
                                          (let* ((inv-step-ast (evaluation-value irun))
                                                 (unary-inputs (list (cons 0 seq-type)))
                                                 (unary-witness (app (op map-name)
                                                                     (var 0 seq-type)
                                                                     (lit src-ctype inv-step-ast))))
                                            (push (register-knowledge-solver
                                                   src-fn
                                                   :id unary-id
                                                   :library library
                                                   :domain elem-type
                                                   :inputs unary-inputs
                                                   :target seq-type
                                                   :position :unary
                                                   :witness unary-witness
                                                   :guard (lit :bool t)
                                                   :certified-p cert-p
                                                   :unique-p (getf (knowledge-entry-metadata esolver) :unique-p t)
                                                   :status (if cert-p :validated :conjecture)
                                                   :edges (list (list :induced-by functor-id (knowledge-entry-id esolver)))
                                                   :ledger ledger)
                                                  induced))))))))))))
                  ;; Induce binary sequence (pos 0) and scalar parameter (pos 1) solvers for pointwise binary functions
                  (dolist (src-entry (knowledge-entries-of-kind :function library))
                    (let ((src-fn (knowledge-entry-id src-entry)))
                      (multiple-value-bind (bin-op epos ppos)
                          (extract-pointwise-binary-step src-entry elem-type seq-type)
                        (when bin-op
                          ;; 1. Position 0 solver: invert `(src-fn xs param) = y` for `xs` given `(param, y)`
                          (let* ((seq-esolver
                                   (find-if (lambda (s)
                                              (let ((m (knowledge-entry-metadata s)))
                                                (and (eq bin-op (getf m :operator-name))
                                                     (eql epos (getf m :position)))))
                                            elem-solvers))
                                 (pos0-id (intern (format nil "~A/INVERT-0" (symbol-name src-fn)) :keyword)))
                            (when (and seq-esolver (null (find-knowledge-entry pos0-id library)))
                              (let* ((ewit (knowledge-entry-expression seq-esolver))
                                     (egrd (or (knowledge-entry-guard seq-esolver) (lit :bool t)))
                                     (swapped-wit (instantiate ewit
                                                               (list (cons 0 (var 1 elem-type))
                                                                     (cons 1 (var 0 elem-type)))
                                                               :var))
                                     (bin-ctype (code-type (list (cons 0 elem-type) (cons 1 elem-type)) elem-type))
                                     (tup-type (tuple-type src-ctype elem-type))
                                     (subst-type (tuple-type bin-ctype tup-type src-ctype))
                                     (code-arg (app (op :code-subst subst-type)
                                                    (lit bin-ctype swapped-wit)
                                                    (app (op :tuple tup-type)
                                                         (lit src-ctype (var 0 elem-type))
                                                         (var 0 elem-type))))
                                     (pos0-inputs (list (cons 0 elem-type) (cons 1 seq-type)))
                                     (pos0-witness (app (op map-name) (var 1 seq-type) code-arg))
                                     (pos0-guard (if (member 1 (free-vars egrd) :test #'eql)
                                                     (lit :bool t)
                                                     egrd))
                                     ;; In particular, POS0-GUARD may omit a scalar
                                     ;; guard that depends on each output element.
                                     (cert-p nil))
                                (push (register-knowledge-solver
                                       src-fn
                                       :id pos0-id
                                       :library library
                                       :domain seq-type
                                       :inputs pos0-inputs
                                       :target seq-type
                                       :position 0
                                       :witness pos0-witness
                                       :guard pos0-guard
                                       :certified-p cert-p
                                       :unique-p (getf (knowledge-entry-metadata seq-esolver) :unique-p t)
                                       :status (if cert-p :validated :conjecture)
                                       :edges (list (list :induced-by functor-id (knowledge-entry-id seq-esolver)))
                                       :ledger ledger)
                                      induced))))
                          ;; 2. Position 1 solver: invert `(src-fn xs param) = y` for scalar `param` given `(xs, y)`
                          (let* ((param-esolver
                                   (find-if (lambda (s)
                                              (let ((m (knowledge-entry-metadata s)))
                                                (and (eq bin-op (getf m :operator-name))
                                                     (eql ppos (getf m :position)))))
                                            elem-solvers))
                                 (pos1-id (intern (format nil "~A/INVERT-1" (symbol-name src-fn)) :keyword)))
                            (when (and param-esolver (null (find-knowledge-entry pos1-id library)))
                              (let* ((pwit (knowledge-entry-expression param-esolver))
                                     (pgrd (or (knowledge-entry-guard param-esolver) (lit :bool t)))
                                     (xs-var (var 0 seq-type))
                                     (ys-var (var 1 seq-type))
                                     (head-xs (app (op :at seq-type) xs-var (lit :int 0)))
                                     (head-ys (app (op :at seq-type) ys-var (lit :int 0)))
                                     (head-subs (list (cons 0 head-xs) (cons 1 head-ys)))
                                     (pos1-inputs (list (cons 0 seq-type) (cons 1 seq-type)))
                                     (pos1-witness (instantiate pwit head-subs :var))
                                     (non-empty-cond (app (op :< :int)
                                                          (lit :int 0)
                                                          (app (op :length elem-type) xs-var)))
                                     (same-len-cond (app (op := :int)
                                                         (app (op :length elem-type) xs-var)
                                                         (app (op :length elem-type) ys-var)))
                                     (inst-grd (instantiate pgrd head-subs :var))
                                     (pos1-guard (app (op :if :bool)
                                                      non-empty-cond
                                                      (app (op :if :bool)
                                                           same-len-cond
                                                           inst-grd
                                                           (lit :bool nil))
                                                      (lit :bool nil))))
                                (push (register-knowledge-solver
                                       src-fn
                                       :id pos1-id
                                       :library library
                                       :domain seq-type
                                       :inputs pos1-inputs
                                       :target elem-type
                                       :position 1
                                       :witness pos1-witness
                                       :guard pos1-guard
                                       :certified-p nil
                                       :unique-p (getf (knowledge-entry-metadata param-esolver) :unique-p t)
                                       :status :conjecture
                                       :edges (list (list :induced-by functor-id (knowledge-entry-id param-esolver)))
                                       :ledger ledger)
                                      induced)))))))))))))))))
    (setf induced (nconc (nreverse induced) (induce-involution-solvers library :ledger ledger)
                         (induce-solvers-from-transformers library ledger)))
    induced))

(define-knowledge-kind :functor
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (when (knowledge-entry-expression entry)
      (expression-type (knowledge-entry-expression entry) (knowledge-entry-inputs entry))))
  (:install (entry library ledger)
    (declare (ignore entry library ledger))
    nil)
  (:consolidate (entries library ledger)
    (declare (ignore entries))
    (induce-functorial-solvers library :ledger ledger)))
