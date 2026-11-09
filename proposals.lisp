(in-package #:lisploop)

;;; Bounded proposal grammars, including labelled structural bootstrap proposals.

(defun candidate-library-definitions (language &key self-name functions frame)
  "Return higher-order `function-definition`s eligible for `library-decompositions`:
defined functions with a concrete body (excluding SELF-NAME) that take one or more `:code`
parameter whose return sort is first-order. When FRAME has sequence types not covered by
the base definitions, polymorphically instantiates matching combinators via `retype-function-definition`."
  (let* ((ho-op-names (loop for o in (language-operators language)
                            for name = (and (operator-p o) (operator-name o))
                            for def = (and name (find-function-definition name))
                            when (and def
                                      (some (lambda (spec) (code-type-p (cdr spec)))
                                            (function-definition-inputs def)))
                              collect name))
         (names (remove-duplicates
                 (or functions
                     ho-op-names
                     (reverse *registered-function-names*))
                 :test #'eq
                 :from-end t))
         (base-defs
           (loop for name in names
                 for def = (and (not (eq name self-name))
                                (or (member name functions :test #'eq)
                                    (not (gethash name *auto-retyped-functions*)))
                                (find-function-definition name))
                 when (and def
                           (function-definition-body def)
                           (null (function-definition-oracle-table def))
                           (some (lambda (spec) (code-type-p (cdr spec))) (function-definition-inputs def))
                           (every (lambda (spec) (or (not (code-type-p (cdr spec)))
                                                    (not (function-sort-p (code-sort (cdr spec))))))
                                  (function-definition-inputs def)))
                   collect def)))
    (if (null frame)
        base-defs
        (let* ((schema (frame-schema frame))
               (inputs (schema-inputs schema))
               (target (schema-target schema))
               (in-elems (remove-duplicates
                          (loop for (nil . type) in inputs
                                when (and (consp type) (eq :seq (first type)))
                                  collect (second type))
                          :test #'equal))
               (out-elems (if (and (consp target) (eq :seq (first target)))
                              (list (second target))
                              (list target)))
               (retyped-defs nil))
          (dolist (def base-defs (remove-duplicates (append base-defs (nreverse retyped-defs))
                                                    :key #'function-definition-name :test #'eq :from-end t))
            (let* ((fn-name (function-definition-name def))
                   (seq-spec (find-if (lambda (s) (and (consp (cdr s)) (eq :seq (first (cdr s)))))
                                      (function-definition-inputs def)))
                   (orig-elem (and seq-spec (second (cdr seq-spec)))))
              (when orig-elem
                (dolist (in-e in-elems)
                  (unless (equal in-e orig-elem)
                    (let ((retyped (ignore-errors (retype-function-definition fn-name in-e :auto-p t))))
                      (when retyped (push retyped retyped-defs))))
                  (dolist (out-e out-elems)
                    (unless (and (equal in-e orig-elem) (equal out-e orig-elem))
                      (let ((retyped (ignore-errors
                                      (if (equal in-e out-e)
                                          (retype-function-definition fn-name in-e :auto-p t)
                                          (retype-function-definition fn-name in-e
                                                                      :return-element-type out-e
                                                                      :auto-p t)))))
                        (when retyped (push retyped retyped-defs)))))))))))))

(defun candidate-fo-argument-expressions (frame language primary-input-id param-type)
  "Return candidate AST expressions of PARAM-TYPE to supply a non-primary first-order
parameter (such as a fold base-case accumulator) of a higher-order library combinator."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (primary-pos (and primary-input-id (position primary-input-id inputs :key #'car :test #'eql)))
         (primary-type (and primary-pos (cdr (nth primary-pos inputs))))
         (exprs nil))
    (flet ((add-expr (e) (pushnew e exprs :test #'equal)))
      ;; 1. Unused parent input variables of matching type
      (dolist (spec inputs)
        (when (and (not (eql (car spec) primary-input-id))
                   (equal (cdr spec) param-type))
          (add-expr (var (car spec) (cdr spec)))))
      ;; 2. Empty-sequence row target value, language constants, literals, and default value of PARAM-TYPE
      (unless (and (consp param-type) (eq :seq (first param-type)) (some #'var-p exprs))
        (when (and primary-pos
                   (consp primary-type) (eq :seq (first primary-type))
                   (equal param-type target))
          (dolist (row (frame-rows frame))
            (when (and (not (unconstrained-requirement-p (row-requirement row)))
                       (null (nth primary-pos (row-known row))))
              (let ((allowed (extract-allowed-values (row-requirement row))))
                (when (and (consp allowed) (= 1 (length allowed)))
                  (add-expr (lit param-type (first allowed))))))))
        (dolist (c (language-constants language))
          (when (equal (ast-type c) param-type)
            (add-expr c)))
        (when (and (consp param-type) (eq :seq (first param-type)))
          (add-expr (lit param-type '())))
        (when (and (eq param-type :int) (listp (language-literals language)))
          (dolist (v (language-literals language))
            (when (integerp v)
              (add-expr (lit :int v)))))
        (add-expr (lit param-type (default-value-for-type param-type))))
      (nreverse exprs))))

(defun library-function-descriptor-compatible-p (frame seq-input-id fn-name ledger)
  "Only current necessary-condition evidence authorizes descriptor pruning.
Uncertified descriptors are hints; no function shape implies a hard rejection."
  (let ((inputs (schema-inputs (frame-schema frame)))
        (descriptors
          (remove-if-not
           (lambda (entry)
             (and (knowledge-evidence-current-p entry :necessary)
                  (some (lambda (edge) (member fn-name (rest edge)))
                        (knowledge-edges-from entry :describes *knowledge-library*))))
           (knowledge-entries-of-kind :descriptor *knowledge-library*))))
    (every
     (lambda (descriptor)
       (every
        (lambda (row)
          (let ((values (extract-allowed-values (row-requirement row)))
                (pos (position seq-input-id inputs :key #'car)))
            (if (and pos (listp values) (= 1 (length values))
                     (not (member :unresolved (row-known row))))
                (let* ((guard (knowledge-entry-guard descriptor))
                       (predicate (if (equal guard (lit :bool t))
                                      (knowledge-entry-expression descriptor)
                                      (app (op :if :bool) guard (knowledge-entry-expression descriptor) (lit :bool t))))
                       (run (evaluate predicate
                                     (knowledge-entry-inputs descriptor)
                                     (list (nth pos (row-known row)) (first values))
                                     :ledger ledger)))
                  (or (not (eq :value (evaluation-status run))) (evaluation-value run)))
                t)))
        (frame-rows frame))) descriptors)))

(defun library-decoder-compatible-with-empty-rows-p (frame seq-input-id decoder child-id child-type bindings ledger
                                                     &key fn-name extra-fo-specs)
  "Check that DECODER satisfies any behavioral descriptor (`trigger`) for FN-NAME and does not
immediately contradict any empty-sequence row of FRAME."
  (when (and fn-name (null extra-fo-specs))
    (unless (library-function-descriptor-compatible-p frame seq-input-id fn-name ledger)
      (return-from library-decoder-compatible-with-empty-rows-p nil)))
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (seq-pos (and seq-input-id (position seq-input-id inputs :key #'car :test #'eql)))
         (seq-type (and seq-pos (cdr (nth seq-pos inputs))))
         (empty-rows (when (and seq-pos (consp seq-type) (eq :seq (first seq-type)))
                       (remove-if-not (lambda (row)
                                        (and (not (unconstrained-requirement-p (row-requirement row)))
                                             (null (nth seq-pos (row-known row)))))
                                      (frame-rows frame)))))
    (if (null empty-rows)
        t
        (let* ((sub-frame (make-frame (frame-schema frame) empty-rows))
               (raw (pullback-frame sub-frame decoder child-id child-type bindings ledger))
               (checker-schema (make-schema :inputs (cons (cons 0 child-type)
                                                          (schema-inputs (frame-schema raw)))
                                            :target :bool)))
          (every (lambda (r)
                   (not (unsatisfiable-requirement-p
                         (fold-constants (row-requirement r) checker-schema
                                         :ledger ledger :budget 500))))
                 (frame-rows raw))))))

(defun filter-map-decompositions (frame base-lang defs child-id c-bound solver ledger debug-p)
  "When FRAME transforms a filtered subsequence of a sequence input (`|out| <= |in|` on all rows,
`|out| < |in|` on at least one row, and outputs are not a pure subsequence of inputs), propose
composed `(:map (:filter X_p pred) Z_mapper)` `:lift-p t` decompositions."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema)))
    (when (and (consp target) (eq :seq (first target)))
      (let ((ret-elem (second target))
            (proposals nil))
        (dolist (p-spec inputs (nreverse proposals))
          (when (and (consp (cdr p-spec)) (eq :seq (first (cdr p-spec))))
            (let* ((p-id (car p-spec))
                   (p-pos (position p-id inputs :key #'car :test #'eql))
                   (seq-type (cdr p-spec))
                   (in-elem (second seq-type))
                   (constrained-rows
                     (loop for r in (frame-rows frame)
                           for allowed = (and (not (unconstrained-requirement-p (row-requirement r)))
                                              (extract-allowed-values (row-requirement r)))
                           for in-val = (nth p-pos (row-known r))
                           when (and (not (eq in-val :unresolved))
                                     (listp in-val)
                                     (consp allowed)
                                     (= 1 (length allowed))
                                     (listp (first allowed)))
                             collect (list r in-val (first allowed)))))
              (when (and constrained-rows
                         (every (lambda (entry) (<= (length (third entry)) (length (second entry))))
                                constrained-rows)
                         (some (lambda (entry) (< (length (third entry)) (length (second entry))))
                               constrained-rows)
                         (or (not (equal in-elem ret-elem))
                             (some (lambda (entry)
                                     (some (lambda (y) (not (member y (second entry) :test #'equal)))
                                           (third entry)))
                                   constrained-rows)))
                (let ((map-def
                        (find-if (lambda (d)
                                   (and (equal (function-definition-return-type d) target)
                                        (= 2 (length (function-definition-inputs d)))
                                        (find seq-type (function-definition-inputs d) :key #'cdr :test #'equal)
                                        (let ((cs (find-if (lambda (s) (code-type-p (cdr s)))
                                                           (function-definition-inputs d))))
                                          (and cs
                                               (equal (code-inputs (cdr cs)) (list (cons 0 in-elem)))
                                               (equal (code-sort (cdr cs)) ret-elem)))))
                                 defs))
                      (filter-def
                        (find-if (lambda (d)
                                   (and (equal (function-definition-return-type d) seq-type)
                                        (= 2 (length (function-definition-inputs d)))
                                        (find seq-type (function-definition-inputs d) :key #'cdr :test #'equal)
                                        (let ((cs (find-if (lambda (s) (code-type-p (cdr s)))
                                                           (function-definition-inputs d))))
                                          (and cs
                                               (equal (code-inputs (cdr cs)) (list (cons 0 in-elem)))
                                               (eq (code-sort (cdr cs)) :bool)))))
                                 defs)))
                  (when (and map-def filter-def)
                    (let* ((map-name (function-definition-name map-def))
                           (filter-name (function-definition-name filter-def))
                           (map-code-spec (find-if (lambda (s) (code-type-p (cdr s)))
                                                   (function-definition-inputs map-def)))
                           (map-code-type (cdr map-code-spec))
                           (filter-code-spec (find-if (lambda (s) (code-type-p (cdr s)))
                                                      (function-definition-inputs filter-def)))
                           (filter-code-type (cdr filter-code-spec))
                           (code-in (code-inputs map-code-type))
                           (next-cid (next-child-id code-in))
                           (bindings (loop for (in-id . in-type) in inputs
                                           unless (eql in-id p-id)
                                             collect (prog1 (cons next-cid (var in-id in-type))
                                                       (incf next-cid))))
                           (extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))
                           (child-inputs (append (copy-tree code-in) extra-in))
                           (elem-rows nil)
                           (row-slices nil)
                           (cursor 0))
                      (dolist (entry constrained-rows)
                        (destructuring-bind (r in-val out-val) entry
                          (let ((extra-vals (evaluate-row-bindings bindings inputs (row-known r)
                                                                   :ledger ledger :allow-unresolved-p t))
                                (start cursor))
                            (dolist (x in-val)
                              (push (make-row :key cursor
                                              :known (cons x (copy-tree extra-vals))
                                              :requirement (lit :bool t))
                                    elem-rows)
                              (incf cursor))
                            (push (list start cursor in-val out-val extra-vals) row-slices))))
                      (setf elem-rows (nreverse elem-rows)
                            row-slices (nreverse row-slices))
                      (when elem-rows
                        (let* ((elem-frame (make-frame (make-schema :inputs child-inputs :target :bool) elem-rows))
                               (eq-ops (cons (op := (language-domain base-lang))
                                             (mapcar (lambda (spec) (op := (cdr spec))) child-inputs)))
                               (lt-ops (remove-if-not (lambda (o)
                                                        (and (operator-p o) (eq :< (operator-name o))))
                                                      (language-operators base-lang)))
                               (cmp-ops (remove-duplicates (append lt-ops eq-ops) :test #'equal))
                               (lit-vals (if (listp (language-literals base-lang))
                                             (remove-duplicates (append '(0 1) (language-literals base-lang))
                                                                :test #'equal)
                                             '(0 1)))
                               (var-atoms (mapcar (lambda (s) (var (car s) (cdr s))) child-inputs))
                               (lit-atoms (loop for v in lit-vals
                                                when (value-p v (language-domain base-lang))
                                                  collect (lit (language-domain base-lang) v)))
                               (all-atoms (append var-atoms lit-atoms))
                               (valid-preds nil))
                          (flet ((check-pred-candidate (raw-expr vals)
                                   (dolist (inv-p '(nil t))
                                     (let ((lengths-match-p t)
                                           (consistent-p t)
                                           (seen (make-hash-table :test #'equal)))
                                       (dolist (slice row-slices)
                                         (destructuring-bind (start end in-val out-val extra-vals) slice
                                           (let ((kept (loop for idx from start below end
                                                             for x in in-val
                                                             for v = (nth idx vals)
                                                             when (if inv-p (not v) v)
                                                               collect x)))
                                             (if (/= (length kept) (length out-val))
                                                 (progn (setf lengths-match-p nil) (return))
                                                 (loop for x in kept
                                                       for y in out-val
                                                       for key = (cons x extra-vals)
                                                       do (multiple-value-bind (prev present-p) (gethash key seen)
                                                            (if (and present-p (not (equal prev y)))
                                                                (progn (setf consistent-p nil) (return))
                                                                (setf (gethash key seen) y))))))))
                                       (when (and lengths-match-p consistent-p)
                                         (let ((p-expr (if inv-p (bool-not raw-expr) raw-expr)))
                                           (push (cons (description-size p-expr child-inputs) p-expr)
                                                 valid-preds)))))))
                            (dolist (cop cmp-ops)
                              (let ((op-type (operator-operand-type cop)))
                                (dolist (a all-atoms)
                                  (when (equal (ast-type a) op-type)
                                    (dolist (b all-atoms)
                                      (when (and (equal (ast-type b) op-type)
                                                 (not (equal a b))
                                                 (or (var-p a) (var-p b)))
                                        (let* ((cand (app cop a b))
                                               (vals (loop for erow in elem-rows
                                                           for run = (evaluate cand child-inputs (row-known erow)
                                                                               :ledger ledger)
                                                           when (eq :value (evaluation-status run))
                                                             collect (evaluation-value run))))
                                          (when (= (length vals) (length elem-rows))
                                            (check-pred-candidate cand vals)))))))))
                            (unless valid-preds
                              (let* ((pred-lang (make-language (language-domain base-lang)
                                                               child-inputs
                                                               :operators cmp-ops
                                                               :literals lit-vals
                                                               :constants nil))
                                     (obs (start-observation-search (make-observation-scope elem-frame pred-lang)))
                                     (obs-before (ledger-total (observation-job-ledger obs)))
                                     (pred-bound (+ (header-size child-inputs :bool) 20)))
                                (resume-observation-search obs pred-bound 3000)
                                (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
                                (dolist (bucket (observation-job-buckets obs))
                                  (when (eq :bool (observation-bucket-type bucket))
                                    (check-pred-candidate
                                     (observed-expression-expression
                                      (car (last (observation-bucket-members bucket))))
                                     (observation-bucket-values bucket)))))))
                          (setf valid-preds (sort valid-preds #'< :key #'car))
                          (loop for (nil . pred-expr) in valid-preds
                                repeat 1
                                do (let* ((pred-code-expr
                                            (compose-lifted-model (var child-id filter-code-type)
                                                                  child-id
                                                                  filter-code-type
                                                                  pred-expr
                                                                  bindings
                                                                  ledger))
                                          (filter-call
                                            (if (eql (car (first (function-definition-inputs filter-def)))
                                                     (car filter-code-spec))
                                                (app (op filter-name) pred-code-expr (var p-id seq-type))
                                                (app (op filter-name) (var p-id seq-type) pred-code-expr)))
                                          (child-var (var child-id map-code-type))
                                          (decoder
                                            (if (eql (car (first (function-definition-inputs map-def)))
                                                     (car map-code-spec))
                                                (app (op map-name) child-var filter-call)
                                                (app (op map-name) filter-call child-var)))
                                          (has-seq-in-p (some (lambda (s)
                                                                (and (consp (cdr s)) (eq :seq (first (cdr s)))))
                                                              child-inputs))
                                          (has-seq-ret-p (and (consp ret-elem) (eq :seq (first ret-elem))))
                                          (child-ops
                                            (remove-if
                                             (lambda (o)
                                               (and (operator-p o)
                                                    (let ((oname (operator-name o)))
                                                      (or (and (not (or has-seq-in-p has-seq-ret-p))
                                                               (let ((odef (find-function-definition oname)))
                                                                 (and odef
                                                                      (or (function-definition-oracle-table odef)
                                                                          (some (lambda (s) (code-type-p (cdr s)))
                                                                                (function-definition-inputs odef))))))
                                                          (and (not (eq ret-elem :bool))
                                                               (not (some (lambda (op2)
                                                                            (and (operator-p op2)
                                                                                 (eq :if (operator-name op2))))
                                                                          (language-operators base-lang)))
                                                               (member oname '(:< :=)))
                                                          (and (not has-seq-in-p)
                                                               (member oname '(:at :tail :length)))
                                                          (and (not has-seq-in-p)
                                                               (not has-seq-ret-p)
                                                               (eq oname :cons))
                                                          (and (not has-seq-in-p)
                                                               (eq oname :=)
                                                               (consp (operator-operand-type o))
                                                               (eq :seq (first (operator-operand-type o))))))))
                                             (language-operators base-lang)))
                                          (child-consts
                                            (if (or has-seq-in-p has-seq-ret-p)
                                                (language-constants base-lang)
                                                (remove-if (lambda (c)
                                                             (and (consp (ast-type c))
                                                                  (eq :seq (first (ast-type c)))))
                                                           (language-constants base-lang))))
                                          (c-lang (make-language (language-domain base-lang)
                                                                 child-inputs
                                                                 :operators child-ops
                                                                 :literals (language-literals base-lang)
                                                                 :constants child-consts)))
                                     (push (make-decomposition
                                            :name (list :library-filter-map map-name filter-name pred-expr)
                                            :decoder decoder
                                            :child-id child-id
                                            :child-type map-code-type
                                            :bindings bindings
                                            :language c-lang
                                            :bound c-bound
                                            :lift-p t
                                            :solver solver
                                            :provenance (when debug-p
                                                          (list :origin :filter-map-expander
                                                                :map map-name
                                                                :filter filter-name
                                                                :predicate pred-expr
                                                                :decoder decoder)))
                                           proposals))))))))))))))))

(defun library-decompositions (frame language &key child-language child-bound
                                                   self-name functions solver ledger
                                                   (debug-p *synthesis-debug-mode*))
  "Propose registered higher-order library definitions (`:fa`, `:fb`, ...) whose return type
matches FRAME's target as `:lift-p t` decompositions. Function-typed (`:code`) parameters
become lifted child frames via `lift-frame`, while unconsumed parent inputs are passed
through `bindings` so `compose-lifted-model` can synthesize `:code-subst` closures."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (c-bound (or child-bound (+ (header-size inputs target) 24)))
         (base-lang (or child-language language))
         (child-id (next-child-id inputs))
         (defs (candidate-library-definitions language :self-name self-name :functions functions :frame frame))
         (proposals nil))
    (dolist (def defs)
      (when (and (equal (function-definition-return-type def) target)
                 (= 1 (count-if (lambda (s) (code-type-p (cdr s))) (function-definition-inputs def))))
        (let* ((fn-name (function-definition-name def))
               (fn-inputs (function-definition-inputs def))
               (code-spec (find-if (lambda (s) (code-type-p (cdr s))) fn-inputs))
               (code-param-id (car code-spec))
               (code-param-type (cdr code-spec))
               (code-in (code-inputs code-param-type))
               (ret (code-sort code-param-type))
               (child-var (var child-id code-param-type))
               (fo-specs (remove code-param-id fn-inputs :key #'car :test #'eql)))
          (if (null fo-specs)
              (let* ((decoder (app (op fn-name) child-var))
                     (next-cid (next-child-id code-in))
                     (bindings (loop for (in-id . in-type) in inputs
                                     collect (prog1 (cons next-cid (var in-id in-type))
                                               (incf next-cid))))
                     (extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))
                     (child-inputs (append (copy-tree code-in) extra-in))
                     (c-lang (make-language (language-domain base-lang)
                                            child-inputs
                                            :operators (language-operators base-lang)
                                            :literals (language-literals base-lang)
                                            :constants (language-constants base-lang))))
                (push (make-decomposition
                       :name (list :library fn-name)
                       :decoder decoder
                       :child-id child-id
                       :child-type code-param-type
                       :bindings bindings
                       :language c-lang
                       :bound c-bound
                       :lift-p t
                       :solver solver
                       :provenance (when debug-p
                                     (list :origin :library-expander
                                           :function fn-name
                                           :decoder decoder)))
                      proposals))
              (let ((primary-spec (first fo-specs))
                    (extra-fo-specs (rest fo-specs)))
                (dolist (p-spec inputs)
                  (when (equal (cdr p-spec) (cdr primary-spec))
                    (let* ((p-id (car p-spec))
                           (primary-expr (var p-id (cdr p-spec)))
                           (extra-options
                             (mapcar (lambda (espec)
                                       (candidate-fo-argument-expressions frame language p-id (cdr espec)))
                                     extra-fo-specs)))
                      (dolist (extra-tuple (cartesian-product-lists extra-options))
                        (let* ((fo-alist (cons (cons (car primary-spec) primary-expr)
                                               (mapcar #'cons (mapcar #'car extra-fo-specs) extra-tuple)))
                               (call-args (loop for (param-id . nil) in fn-inputs
                                                collect (if (eql param-id code-param-id)
                                                            child-var
                                                            (cdr (assoc param-id fo-alist :test #'eql)))))
                               (decoder (apply #'app (op fn-name) call-args))
                               (consumed-ids (loop for arg in call-args
                                                   when (var-p arg) collect (ast-id arg)))
                               (next-cid (next-child-id code-in))
                               (bindings (loop for (in-id . in-type) in inputs
                                               unless (member in-id consumed-ids :test #'eql)
                                                 collect (prog1 (cons next-cid (var in-id in-type))
                                                           (incf next-cid)))))
                          (when (library-decoder-compatible-with-empty-rows-p
                                 frame p-id decoder child-id code-param-type bindings ledger
                                 :fn-name fn-name :extra-fo-specs extra-fo-specs)
                            (let* ((extra-in (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))
                                   (child-inputs (append (copy-tree code-in) extra-in))
                                   (child-ops (language-operators base-lang))
                                   (child-consts (language-constants base-lang))
                                   (c-lang (make-language (language-domain base-lang)
                                                          child-inputs
                                                          :operators child-ops
                                                          :literals (language-literals base-lang)
                                                          :constants child-consts))
                                   (eff-c-bound
                                     (max c-bound
                                          (+ (header-size child-inputs ret)
                                             (if (some (lambda (o)
                                                         (and (operator-p o)
                                                              (defined-function-p (operator-name o))))
                                                       child-ops)
                                                 32
                                                 24)))))
                              (push (make-decomposition
                                     :name (cons :library (cons fn-name extra-tuple))
                                     :decoder decoder
                                     :child-id child-id
                                     :child-type code-param-type
                                     :bindings bindings
                                     :language c-lang
                                     :bound eff-c-bound
                                     :lift-p t
                                     :solver solver
                                     :provenance (when debug-p
                                                   (list :origin :library-expander
                                                         :function fn-name
                                                         :decoder decoder
                                                         :bindings bindings)))
                                    proposals)))))))))))))
    (append (filter-map-decompositions frame base-lang defs child-id c-bound solver ledger debug-p)
            (nreverse proposals)
            (partial-library-decompositions frame base-lang defs child-id c-bound solver ledger)
            (learned-decoder-decompositions frame base-lang c-bound solver ledger))))

(defun library-expander (&key child-language child-bound functions)
  "An `:expand` function that proposes registered higher-order library combinators
whose return type matches the node's target as `:lift-p t` decompositions."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    (let* ((proposal (synthesis-node-proposal node))
           (bound (or child-bound
                      (synthesis-node-bound node)
                      (and proposal (decomposition-bound proposal)))))
      (progn
        (library-decompositions frame language
                                :child-language child-language
                                :child-bound bound
                                :self-name (and job (synthesis-job-self-name job))
                                :functions functions
                                :solver (and job (synthesis-job-library job))
                                :ledger ledger
                                :debug-p (and job (synthesis-job-debug-p job)))))))

(defun combine-expanders (&rest expanders)
  "Compose multiple `:expand` functions into a single expander without baked-in policy."
  (lambda (job node frame language h-model ledger)
    (loop for exp in expanders
          when exp
            append (funcall exp job node frame language h-model ledger))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p) (debug-p *synthesis-debug-mode*))
  "Make dependency hypotheses explicit. FEATURES are synthesized DSL expressions;
the default seed vocabulary is each available coordinate and the empty context.
Every hypothesis competes with direct synthesis on the full original frame."
  (let* ((inputs-spec (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (child-id (next-child-id inputs-spec)))
    (loop for feature in (cons nil (if features-p features
                                     (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs-spec)))
          for inputs = (when feature (list (cons 0 (ast-type feature))))
          collect (make-decomposition
                   :name (list :dependency feature) :decoder (var child-id target)
                   :child-id child-id :child-type target :bindings (when feature (list (cons 0 feature)))
                   :language (make-language (language-domain language) inputs :operators (language-operators language)
                                            :literals (language-literals language) :constants (language-constants language))
                   :bound child-bound
                   :provenance (when debug-p (list :origin :dependency :feature feature))))))

(defun selector-decompositions (frame language bound &key fibers dependencies (debug-p *synthesis-debug-mode*))
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (id (next-child-id inputs)))
    (append (when fibers
              (list (make-decomposition :name :fibers :decoder (var id target) :child-id id
                                        :child-type target :bindings (identity-bindings inputs)
                                        :language language :bound bound :fiber-p t
                                        :provenance (when debug-p (list :origin :fibers)))))
            (when dependencies
              (dependency-proposals frame language bound :debug-p debug-p)))))

(defun start-selector-search (frame language description-limit &key (fibers t) dependencies)
  "Price direct selector synthesis alongside optional fiber and dependency proposals."
  (start-synthesis frame language description-limit
                   :decompositions (selector-decompositions frame language description-limit
                                                            :fibers fibers :dependencies dependencies)))

(defun heuristic-expander (&key child-language guard-language child-bound guard-bound
                                (work-limit 20000) (additive-p t) (conditional-p t)
                                (library-proposals-p t) library-functions)
  "An `:expand` function: each node turns its own Stage A model into Stage B additive and
conditional residual branches (plus higher-order library combinator branches when
LIBRARY-PROPOSALS-P is true and no de novo SELF-NAME is active), so every proposal
competes under Stage A full-path pricing and the 3:1 reserve schedule."
  (lambda (job node frame language h-model ledger)
    (let* ((inputs (schema-inputs (frame-schema frame)))
           (proposal (synthesis-node-proposal node))
           (bound (or (synthesis-node-bound node) (and proposal (decomposition-bound proposal)))))
      (flet ((matching (lang) (and lang (equal (language-inputs lang) inputs) lang)))
        (let ((stage-b (progn
                         (heuristic-decompositions frame language
                                                   :heuristic-model h-model
                                                   :child-language (matching child-language)
                                                   :guard-language (matching guard-language)
                                                   :description-limit bound
                                                   :child-bound (or child-bound bound)
                                                   :guard-bound guard-bound
                                                   :work-limit work-limit
                                                   :run-weight (synthesis-job-run-weight job)
                                                   :additive-p additive-p
                                                   :conditional-p conditional-p
                                                   :self-name (synthesis-job-self-name job)
                                                   :solver (synthesis-job-library job)
                                                   :ledger ledger
                                                   :debug-p (synthesis-job-debug-p job))))
              (lib-props (when library-proposals-p
                           (library-decompositions frame language
                                                   :child-language child-language
                                                   :child-bound (or child-bound bound)
                                                   :self-name (and job (synthesis-job-self-name job))
                                                   :functions library-functions
                                                   :solver (and job (synthesis-job-library job))
                                                   :ledger ledger
                                                   :debug-p (and job (synthesis-job-debug-p job))))))
          (append lib-props stage-b))))))

(defparameter *library-code-argument-bits* 20
  "Body-bit bound for quoted sibling parameters in generic partial applications.")
(defparameter *library-code-argument-work* 1000
  "Enumerator cursor budget per sibling code type; supplied constants remain available.")
(defparameter *library-partial-proposal-limit* 256
  "Maximum partial applications emitted in one expansion, without building the Cartesian product.")

(defun map-cartesian-options (options function)
  (labels ((visit (remaining reversed)
             (if (null remaining)
                 (funcall function (reverse reversed))
                 (dolist (value (first remaining))
                   (visit (rest remaining) (cons value reversed))))))
    (visit options nil)))

(defun library-code-argument-candidates (type language ledger)
  "Enumerate ordinary DSL bodies, then quote them; no map/filter-specific grammar."
  (let* ((scope (code-inputs type))
         (lang (make-language (language-domain language) scope
                              :operators (language-operators language)
                              :literals (language-literals language)
                              :constants (language-constants language)))
         (cursor (make-enumerator lang))
         (candidates (remove-if-not (lambda (c) (equal type (ast-type c)))
                                    (copy-list (language-constants language)))))
    (loop repeat *library-code-argument-work*
          while (<= (enumerator-size cursor) *library-code-argument-bits*)
          do (charge ledger :template-enumeration)
             (multiple-value-bind (expr event) (enumeration-step cursor)
               (when (eq event :candidate)
                 (index-expression cursor expr)
                 (when (equal (ast-type expr) (code-sort type))
                   (pushnew (lit type expr) candidates :test #'equal)))))
    (nreverse candidates)))

(defun partial-library-decompositions (frame language definitions child-id bound solver ledger)
  "Lift any code slot while supplying its siblings from a bounded typed grammar.
This path handles multiple code parameters and functions without a matching
primary parent input. All siblings remain explicit ASTs and are replayed at root."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (cache (make-hash-table :test #'equal))
         (proposals nil))
    (dolist (definition definitions (nreverse proposals))
      (let* ((specs (function-definition-inputs definition))
             (codes (remove-if-not (lambda (s) (code-type-p (cdr s))) specs))
             (first-order (remove-if (lambda (s) (code-type-p (cdr s))) specs)))
        (when (and (equal target (function-definition-return-type definition))
                   (or (> (length codes) 1)
                       (and first-order
                            (not (find (cdar first-order) inputs :key #'cdr :test #'equal)))))
          (dolist (selected codes)
            (let* ((ctype (cdr selected))
                   (scope (code-inputs ctype))
                   (next (next-child-id scope))
                   (bindings (loop for (id . type) in inputs
                                   collect (prog1 (cons next (var id type)) (incf next))))
                   (child-inputs (append scope (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings)))
                   (options
                     (loop for spec in specs
                           collect (cond ((eq spec selected) (list (var child-id ctype)))
                                         ((code-type-p (cdr spec))
                                          (or (gethash (cdr spec) cache)
                                              (setf (gethash (cdr spec) cache)
                                                    (library-code-argument-candidates (cdr spec) language ledger))))
                                         (t (candidate-fo-argument-expressions frame language nil (cdr spec)))))))
              (map-cartesian-options options
               (lambda (args)
                (when (>= (length proposals) *library-partial-proposal-limit*)
                  (return-from partial-library-decompositions (nreverse proposals)))
                (let ((decoder (apply #'app (op (function-definition-name definition)) args)))
                  (charge ledger :template-construction (syntax-work decoder))
                  (push (make-decomposition
                         :name (list :library-partial (function-definition-name definition) (car selected) args)
                         :decoder decoder :child-id child-id :child-type ctype :fallback-p t
                         :bindings bindings :lift-p t :solver solver
                         :bound (max bound (+ (header-size child-inputs (code-sort ctype)) 24))
                         :language (make-language (language-domain language) child-inputs
                                                  :operators (language-operators language)
                                                  :literals (language-literals language)
                                                  :constants (language-constants language)))
                        proposals)))))))))))

(define-knowledge-kind :decoder-template
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (assert (equal (knowledge-entry-target entry)
                   (expression-type (knowledge-entry-expression entry) (knowledge-entry-inputs entry))))))

(defun remember-decoder-template (proposal parent-inputs &key (library *knowledge-library*) ledger work)
  "Store an observed decomposition as typed library syntax, not a family tag.
It is a reusable proposal, never evidence that the decoder fits another task."
  (let* ((cid (decomposition-child-id proposal))
         (ctype (decomposition-child-type proposal))
         (inputs (acons cid ctype parent-inputs))
         (expr (decomposition-decoder proposal))
         (bindings (mapcar (lambda (b) (cons (car b) (ast->sexp (cdr b)))) (decomposition-bindings proposal)))
         (existing (find-if (lambda (entry)
                             (and (equal inputs (knowledge-entry-inputs entry))
                                  (equal expr (knowledge-entry-expression entry))
                                  (equal bindings (getf (knowledge-entry-metadata entry) :bindings))))
                           (knowledge-entries-of-kind :decoder-template library))))
    (or existing
        (register-knowledge-entry
         (make-knowledge-entry :kind :decoder-template :inputs inputs :target (ast-type expr)
                               :expression expr :work (or work 0) :status :empirical
                               :metadata (list :origin :observed-decomposition :child-id cid
                                               :dependencies (expression-dependencies
                                                              (cons expr (mapcar #'cdr (decomposition-bindings proposal))))
                                               :lift-p (decomposition-lift-p proposal) :bindings bindings)
                               :library library)
         :library library :ledger ledger))))

(defun learned-decoder-decompositions (frame language bound solver ledger)
  "Retrieve stored typed contexts with arbitrary parameter renaming/reordering."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (cid (next-child-id inputs))
         (proposals nil))
    (dolist (entry (knowledge-entries-of-kind :decoder-template) (nreverse proposals))
      (let* ((meta (knowledge-entry-metadata entry))
             (old-cid (getf meta :child-id))
             (ctype (cdr (assoc old-cid (knowledge-entry-inputs entry))))
             (params (remove old-cid (knowledge-entry-inputs entry) :key #'car))
             (options (mapcar (lambda (param)
                                (loop for (id . type) in inputs when (equal type (cdr param)) collect (var id type)))
                              params)))
        (when (and (equal target (knowledge-entry-target entry))
                   (equalp (getf meta :dependencies)
                           (expression-dependencies
                            (loop for dependency in (getf meta :dependencies)
                                  when (defined-function-p (first dependency)) collect (op (first dependency))))))
          (map-cartesian-options options
           (lambda (args)
             (when (>= (length proposals) *library-partial-proposal-limit*)
               (return-from learned-decoder-decompositions (nreverse proposals)))
             (let* ((substitution (acons old-cid (var cid ctype) (mapcar #'cons (mapcar #'car params) args)))
                    (decoder (instantiate (knowledge-entry-expression entry) substitution :var))
                    (bindings (mapcar (lambda (b) (cons (car b) (instantiate (sexp->ast (cdr b)) substitution :var)))
                                      (getf meta :bindings)))
                    (lift-p (getf meta :lift-p))
                    (child-inputs (append (when lift-p (code-inputs ctype))
                                          (mapcar (lambda (b) (cons (car b) (ast-type (cdr b)))) bindings))))
               (charge ledger :template-retrieval (syntax-work decoder))
               (when (ignore-errors (expression-type decoder (acons cid ctype inputs)))
                 (push (make-decomposition :name (list :learned-template (knowledge-entry-id entry))
                         :decoder decoder :child-id cid :child-type ctype :bindings bindings :lift-p lift-p :fallback-p t
                         :solver solver :bound (max bound (+ (header-size child-inputs (if lift-p (code-sort ctype) ctype)) 24))
                         :language (make-language (language-domain language) child-inputs
                                                  :operators (language-operators language)
                                                  :literals (language-literals language)
                                                  :constants (language-constants language)))
                       proposals))))))))))

(defun remember-successful-decompositions (job library ledger)
  (let* ((best (synthesis-job-best job))
         (message (find-if (lambda (m) (and (eq :candidate (message-claim m))
                                           (eq best (getf (message-evidence m) :candidate))))
                           (synthesis-job-messages job)))
         (node (and message (find (message-call-id message) (synthesis-job-nodes job) :key #'synthesis-node-id)))
         (entries nil))
    (loop while (and node (synthesis-node-parent node))
          do (let ((parent (synthesis-node-parent node)))
               (push (remember-decoder-template (synthesis-node-proposal node)
                       (schema-inputs (frame-schema (synthesis-node-frame parent)))
                       :library library :ledger ledger :work (ledger-total (synthesis-job-ledger job))) entries)
               (setf node parent)))
    entries))
