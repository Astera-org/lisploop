(in-package #:lisploop)

;;; Decomposition proposals from the library, dependencies, and remembered decoder contexts.

;;; Bounded proposal grammars, including labelled structural bootstrap proposals.
(defun candidate-library-definitions (language &key self-name functions frame)
  "Return higher-order `function-definition`s eligible for `library-decompositions`:
defined functions with a concrete body (excluding SELF-NAME) that take one or more `:code`
parameter whose return sort is first-order. When FRAME has sequence types not covered by
the base definitions, polymorphically instantiates matching combinators via `retype-function-definition`."
  (let* ((ho-op-names (loop for o in (language-operators language)
                            for name = (and (operator-p o) (operator-name o))
                            for def = (and name (find-function-definition name))
                            when (and def (code-parameters def))
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
                           (code-parameters def)
                           (notany (lambda (spec) (function-sort-p (code-sort (cdr spec))))
                                   (code-parameters def)))
                   collect def)))
    (if (null frame)
        base-defs
        (let* ((schema (frame-schema frame))
               (target (schema-target schema))
               (in-elems (remove-duplicates
                          (loop for (nil . type) in (schema-inputs schema)
                                when (seq-type-p type)
                                  collect (second type))
                          :test #'equal))
               (out-elem (if (seq-type-p target) (second target) target))
               (retyped-defs nil))
          (dolist (def base-defs (remove-duplicates (append base-defs (nreverse retyped-defs))
                                                    :key #'function-definition-name :test #'eq :from-end t))
            (let* ((seq-spec (find-if #'seq-type-p (function-definition-inputs def) :key #'cdr))
                   (orig-elem (and seq-spec (second (cdr seq-spec)))))
              (flet ((retype (in-elem &optional return-elem)
                       (let ((retyped (ignore-errors
                                       (retype-function-definition (function-definition-name def) in-elem
                                                                   :return-element-type return-elem
                                                                   :auto-p t))))
                         (when retyped (push retyped retyped-defs)))))
                (when orig-elem
                  (dolist (in-elem in-elems)
                    (unless (equal in-elem orig-elem) (retype in-elem))
                    (unless (equal in-elem out-elem) (retype in-elem out-elem)))))))))))

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
      (unless (and (seq-type-p param-type) (some #'var-p exprs))
        (when (and primary-pos
                   (seq-type-p primary-type)
                   (equal param-type target))
          (dolist (row (frame-rows frame))
            (when (empty-sequence-row-p row primary-pos)
              (multiple-value-bind (value found-p) (row-singleton-value row)
                (when found-p
                  (add-expr (lit param-type value)))))))
        (dolist (c (language-constants language))
          (when (equal (ast-type c) param-type)
            (add-expr c)))
        (when (seq-type-p param-type)
          (add-expr (lit param-type '())))
        (when (and (eq param-type :int) (listp (language-literals language)))
          (dolist (v (language-literals language))
            (when (integerp v)
              (add-expr (lit :int v)))))
        (add-expr (lit param-type (default-value-for-type param-type))))
      (nreverse exprs))))

(defun library-decoder-compatible-with-empty-rows-p (frame seq-input-id decoder child-id child-type bindings ledger)
  "Check that DECODER does not immediately contradict any empty-sequence row of FRAME."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (seq-pos (and seq-input-id (position seq-input-id inputs :key #'car :test #'eql)))
         (empty-rows (when (and seq-pos (seq-type-p (cdr (nth seq-pos inputs))))
                       (remove-if-not (lambda (row) (empty-sequence-row-p row seq-pos))
                                      (frame-rows frame)))))
    (or (null empty-rows)
        (every (lambda (r)
                 (not (unsatisfiable-requirement-p
                       (fold-constants (row-requirement r) :ledger ledger :budget 500))))
               (frame-rows (pullback-frame (make-frame (frame-schema frame) empty-rows)
                                           decoder child-id child-type bindings ledger))))))

(defun passthrough-bindings (code-type inputs &optional consumed-ids)
  "Bind each parent input not in CONSUMED-IDS to a fresh child variable, numbered after
the parameters of CODE-TYPE, so a lifted child can read what its decoder does not consume."
  (loop for (id . type) in (remove-if (lambda (spec) (member (car spec) consumed-ids)) inputs)
        for child-input-id from (next-child-id (code-inputs code-type))
        collect (cons child-input-id (var id type))))

(defun lifted-decomposition (name decoder child-id child-type bindings language bound solver
                             &key slack (lift-p t) fallback-p (policy-score 0) provenance)
  "A decomposition whose child is the body of DECODER's code slot CHILD-ID: its inputs are
the slot's own parameters followed by one input per binding, and its language is LANGUAGE
over those inputs. SLACK, when given, raises BOUND to at least that many bits beyond the
child's header. With LIFT-P nil the child is the plain value CHILD-ID over the bindings."
  (let ((child-inputs (append (when lift-p (code-inputs child-type))
                              (loop for (id . expression) in bindings
                                    collect (cons id (ast-type expression)))))
        (child-sort (if lift-p (code-sort child-type) child-type)))
    (make-decomposition
     :name name :decoder decoder :child-id child-id :child-type child-type :bindings bindings
     :language (derive-language language :inputs child-inputs)
     :bound (if slack (max bound (header-bound child-inputs child-sort slack)) bound)
     :lift-p lift-p :solver solver :fallback-p fallback-p :policy-score policy-score
     :provenance provenance)))

(defparameter *filter-map-policy-score* -18
  "Policy score of a filter-map proposal, whose predicate already aligns every row.")

(defparameter *partial-application-policy-score* 8
  "Policy score of a partial application whose sibling arguments are enumerated guesses.")

(defparameter *learned-template-policy-score* 6
  "Policy score of a remembered decoder context, before its descriptor evidence.")

(defun aligned-filter-predicate (slices child-inputs language ledger)
  "The shortest Boolean expression over CHILD-INPUTS (an element, then the pass-through
values) that keeps, on every slice (in-val out-val extra-vals), as many elements as the
output has, such that kept elements map to output elements consistently. Comparisons of
two atoms are tried directly; only when none aligns is the comparison grammar searched
observationally. Returns nil when neither offers a predicate."
  (let* ((domain (language-domain language))
         (elem-rows (loop with key = -1
                          for (in-val nil extra-vals) in slices
                          append (loop for x in in-val
                                       collect (make-row :key (incf key)
                                                         :known (cons x (copy-tree extra-vals))
                                                         :requirement (lit :bool t)))))
         (eq-ops (cons (op := domain) (mapcar (lambda (spec) (op := (cdr spec))) child-inputs)))
         (lt-ops (remove-if-not (lambda (o) (and (operator-p o) (eq :< (operator-name o))))
                                (language-operators language)))
         (cmp-ops (remove-duplicates (append lt-ops eq-ops) :test #'equal))
         (literals (if (listp (language-literals language))
                       (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                       '(0 1)))
         (atoms (append (loop for (id . type) in child-inputs collect (var id type))
                        (loop for v in literals when (value-p v domain) collect (lit domain v)))))
    (labels ((aligned-p (vals keep)
               ;; VALS holds a predicate's value on each element row, in slice order.
               (let ((seen (make-hash-table :test #'equal)))
                 (loop for (in-val out-val extra-vals) in slices
                       for kept = (loop for x in in-val
                                        when (eq keep (and (pop vals) t))
                                          collect x)
                       always (and (= (length kept) (length out-val))
                                   (loop for x in kept
                                         for y in out-val
                                         for key = (cons x extra-vals)
                                         always (equal y (if (nth-value 1 (gethash key seen))
                                                             (gethash key seen)
                                                             (setf (gethash key seen) y))))))))
             (best-aligned (observations)
               ;; OBSERVATIONS pairs expressions with their row values; either polarity may align.
               (let ((valid nil))
                 (loop for (expr . vals) in observations
                       do (dolist (keep '(t nil))
                            (when (aligned-p vals keep)
                              (let ((predicate (if keep expr (bool-not expr))))
                                (push (cons (description-size predicate child-inputs) predicate) valid)))))
                 (cdr (best-by valid #'car))))
             (row-values (expr)
               (loop for row in elem-rows
                     for run = (evaluate expr child-inputs (row-known row) :ledger ledger)
                     when (eq :value (evaluation-status run))
                       collect (evaluation-value run))))
      (when elem-rows
        (or (best-aligned
             (loop for cmp in cmp-ops
                   for type = (operator-operand-type cmp)
                   append (loop for (a b) in (cartesian-product-lists (list atoms atoms))
                                for comparison = (and (equal (ast-type a) type)
                                                      (equal (ast-type b) type)
                                                      (not (equal a b))
                                                      (or (var-p a) (var-p b))
                                                      (app cmp a b))
                                for vals = (and comparison (row-values comparison))
                                when (and comparison (= (length vals) (length elem-rows)))
                                  collect (cons comparison vals))))
            (best-aligned
             (observed-predicates (make-frame (make-schema :inputs child-inputs :target :bool) elem-rows)
                                  (derive-language language :inputs child-inputs
                                                            :operators cmp-ops
                                                            :literals literals
                                                            :constants nil)
                                  (header-bound child-inputs :bool 20) 3000 ledger)))))))

(defun filter-map-decompositions (frame base-lang defs child-id c-bound solver ledger debug-p)
  "When FRAME transforms a filtered subsequence of a sequence input (`|out| <= |in|` on all rows,
`|out| < |in|` on at least one row, and outputs are not a pure subsequence of inputs), propose
composed `(:map (:filter X_p pred) Z_mapper)` `:lift-p t` decompositions."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (proposals nil))
    (when (seq-type-p target)
      (loop
        for (p-id . seq-type) in inputs
        for p-pos from 0
        when (seq-type-p seq-type)
          do (let* ((in-elem (second seq-type))
                    (ret-elem (second target))
                    ;; (row in-val out-val) for each row that fixes both sequences
                    (examples (loop for row in (frame-rows frame)
                                    for in-val = (nth p-pos (row-known row))
                                    for (out-val found-p) = (multiple-value-list (row-singleton-value row))
                                    when (and found-p (listp in-val) (listp out-val))
                                      collect (list row in-val out-val))))
               (flet ((combinator (return-type sort)
                        ;; A two-parameter definition over SEQ-TYPE and elementwise code of SORT.
                        (find-if (lambda (d)
                                   (let ((code (first (code-parameters d))))
                                     (and code
                                          (equal (function-definition-return-type d) return-type)
                                          (= 2 (length (function-definition-inputs d)))
                                          (find seq-type (function-definition-inputs d)
                                                :key #'cdr :test #'equal)
                                          (equal (code-inputs (cdr code)) (list (cons 0 in-elem)))
                                          (equal (code-sort (cdr code)) sort))))
                                 defs))
                      (call (def code-argument seq-argument)
                        (if (code-type-p (cdr (first (function-definition-inputs def))))
                            (app (op (function-definition-name def)) code-argument seq-argument)
                            (app (op (function-definition-name def)) seq-argument code-argument))))
                 (let ((map-def (combinator target ret-elem))
                       (filter-def (combinator seq-type :bool)))
                   (when (and examples map-def filter-def
                              (every (lambda (e) (<= (length (third e)) (length (second e)))) examples)
                              (some (lambda (e) (< (length (third e)) (length (second e)))) examples)
                              (or (not (equal in-elem ret-elem))
                                  (some (lambda (e) (set-difference (third e) (second e) :test #'equal))
                                        examples)))
                     (let* ((map-code-type (cdr (first (code-parameters map-def))))
                            (filter-code-type (cdr (first (code-parameters filter-def))))
                            (bindings (passthrough-bindings map-code-type inputs (list p-id)))
                            (child-inputs (append (code-inputs map-code-type)
                                                  (loop for (id . expression) in bindings
                                                        collect (cons id (ast-type expression)))))
                            (predicate
                              (aligned-filter-predicate
                               (loop for (row in-val out-val) in examples
                                     collect (list in-val out-val
                                                   (evaluate-row-bindings bindings inputs (row-known row)
                                                                          :ledger ledger
                                                                          :allow-unresolved-p t)))
                               child-inputs base-lang ledger)))
                       (when predicate
                         (let* ((map-name (function-definition-name map-def))
                                (filter-name (function-definition-name filter-def))
                                (predicate-code
                                  (compose-lifted-model (var child-id filter-code-type) child-id
                                                        filter-code-type predicate bindings ledger))
                                (decoder
                                  (call map-def
                                        (var child-id map-code-type)
                                        (call filter-def predicate-code (var p-id seq-type)))))
                           (push (lifted-decomposition
                                  (list :library-filter-map map-name filter-name predicate)
                                  decoder child-id map-code-type bindings base-lang c-bound solver
                                  :policy-score *filter-map-policy-score*
                                  :provenance (when debug-p
                                                (list :origin :filter-map-expander
                                                      :map map-name
                                                      :filter filter-name
                                                      :predicate predicate
                                                      :decoder decoder)))
                                 proposals))))))))))
    (nreverse proposals)))

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
         (c-bound (or child-bound (header-bound inputs target 24)))
         (base-lang (or child-language language))
         ;; A child that may call defined functions gets more room for its body.
         (slack (if (some (lambda (o) (and (operator-p o) (defined-function-p (operator-name o))))
                          (language-operators base-lang))
                    32
                    24))
         (child-id (next-child-id inputs))
         (defs (candidate-library-definitions language :self-name self-name :functions functions :frame frame))
         (proposals nil))
    (dolist (def defs)
      (when (and (equal (function-definition-return-type def) target)
                 (= 1 (length (code-parameters def))))
        (let* ((fn-name (function-definition-name def))
               (fn-inputs (function-definition-inputs def))
               (code-spec (first (code-parameters def)))
               (code-type (cdr code-spec))
               (child-var (var child-id code-type))
               (fo-specs (remove code-spec fn-inputs)))
          (if (null fo-specs)
              (let ((decoder (app (op fn-name) child-var)))
                (push (lifted-decomposition
                       (list :library fn-name) decoder child-id code-type
                       (passthrough-bindings code-type inputs) base-lang c-bound solver
                       :provenance (when debug-p
                                     (list :origin :library-expander
                                           :function fn-name
                                           :decoder decoder)))
                      proposals))
              (destructuring-bind (primary-spec . extra-fo-specs) fo-specs
                (dolist (p-spec inputs)
                  (when (equal (cdr p-spec) (cdr primary-spec))
                    (let ((p-id (car p-spec)))
                      (multiple-value-bind (compat-p policy-score matched-clauses)
                          (score-entry-by-descriptors fn-name frame p-id
                                                      :ledger ledger
                                                      :extra-fo-specs extra-fo-specs)
                        (when compat-p
                          (let ((extra-options
                                  (mapcar (lambda (espec)
                                            (candidate-fo-argument-expressions frame language p-id (cdr espec)))
                                          extra-fo-specs)))
                            (dolist (extra-tuple (cartesian-product-lists extra-options))
                              (let* ((fo-alist (acons (car primary-spec) (var p-id (cdr p-spec))
                                                      (mapcar #'cons (mapcar #'car extra-fo-specs) extra-tuple)))
                                     (call-args (loop for spec in fn-inputs
                                                      collect (if (eq spec code-spec)
                                                                  child-var
                                                                  (cdr (assoc (car spec) fo-alist :test #'eql)))))
                                     (decoder (apply #'app (op fn-name) call-args))
                                     (bindings (passthrough-bindings
                                                code-type inputs
                                                (loop for arg in call-args
                                                      when (var-p arg) collect (ast-id arg)))))
                                (when (library-decoder-compatible-with-empty-rows-p
                                       frame p-id decoder child-id code-type bindings ledger)
                                  (push (lifted-decomposition
                                         (list* :library fn-name extra-tuple) decoder child-id code-type
                                         bindings base-lang c-bound solver
                                         :slack slack
                                         :policy-score policy-score
                                         :provenance (when debug-p
                                                       (list :origin :library-expander
                                                             :function fn-name
                                                             :decoder decoder
                                                             :bindings bindings
                                                             :policy-score policy-score
                                                             :matched-descriptors matched-clauses)))
                                        proposals)))))))))))))))
    (append (filter-map-decompositions frame base-lang defs child-id c-bound solver ledger debug-p)
            (nreverse proposals)
            (partial-library-decompositions frame base-lang defs child-id c-bound solver ledger)
            (learned-decoder-decompositions frame base-lang c-bound solver ledger))))

(defun expansion-bound (node)
  "The description bound NODE was searched under: its own, or else its proposal's."
  (or (synthesis-node-bound node)
      (let ((proposal (synthesis-node-proposal node)))
        (and proposal (decomposition-bound proposal)))))

(defun library-expander (&key child-language child-bound functions)
  "An `:expand` function that proposes registered higher-order library combinators
whose return type matches the node's target as `:lift-p t` decompositions."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    (library-decompositions frame language
                            :child-language child-language
                            :child-bound (or child-bound (expansion-bound node))
                            :self-name (synthesis-job-self-name job)
                            :functions functions
                            :solver (synthesis-job-library job)
                            :ledger ledger
                            :debug-p (synthesis-job-debug-p job))))

(defun combine-expanders (&rest expanders)
  "Compose multiple `:expand` functions into a single expander without baked-in policy."
  (lambda (job node frame language h-model ledger)
    (loop for exp in expanders
          when exp
            append (funcall exp job node frame language h-model ledger))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p) (include-empty-p t)
                                                             solver (debug-p *synthesis-debug-mode*))
  "Make dependency hypotheses explicit. FEATURES are synthesized DSL expressions;
the default seed vocabulary is each available coordinate and the empty context.
Every hypothesis competes with direct synthesis on the full original frame."
  (let* ((inputs-spec (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (child-id (next-child-id inputs-spec))
         (base-features (if features-p
                            features
                            (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs-spec))))
    (loop for feature in (if include-empty-p (cons nil base-features) base-features)
          for inputs = (when feature (list (cons 0 (ast-type feature))))
          collect (make-decomposition
                   :name (list :dependency feature) :decoder (var child-id target)
                   :child-id child-id :child-type target :bindings (when feature (list (cons 0 feature)))
                   :language (derive-language language :inputs inputs)
                   :bound child-bound :solver solver
                   :provenance (when debug-p (list :origin :dependency :feature feature))))))

(defun sufficient-statistic-values-p (values constrained)
  "True when VALUES across CONSTRAINED `(row-idx . output-val)` pairs strictly merge at least
one fiber (`1 < distinct < |constrained|`) without colliding rows whose required outputs differ."
  (let* ((vals (coerce values 'vector))
         (n (length vals))
         (mapping nil))
    (loop for (idx . out) in constrained
          when (>= idx n) do (return-from sufficient-statistic-values-p nil)
          do (let* ((fval (aref vals idx))
                    (existing (assoc fval mapping :test #'equal)))
               (cond ((null existing) (push (cons fval out) mapping))
                     ((not (equal (cdr existing) out))
                      (return-from sufficient-statistic-values-p nil)))))
    (< 1 (length mapping) (length constrained))))

(defun feature-buckets-for-node (node frame language h-model feature-language feature-bound work-limit ledger)
  "Reuse Stage A's `(expression . values)` feature buckets when compatible, or run a bounded
`start-observation-search` over `feature-language`."
  (if (and (null feature-language) (null feature-bound)
           h-model (heuristic-buckets h-model))
      (heuristic-buckets h-model)
      (let* ((schema (frame-schema frame))
             (f-lang (or feature-language language))
             (f-bound (or feature-bound (expansion-bound node)
                          (header-bound (schema-inputs schema) (schema-target schema) 18)))
             (obs (start-observation-search
                   (make-observation-scope (unconstrained-frame frame (language-domain f-lang)) f-lang))))
        (resume-observation-search obs f-bound (remaining-work ledger work-limit))
        (charge ledger :feature-search (ledger-total (observation-job-ledger obs)))
        (observation-feature-buckets obs))))

(defun dependency-expander (&key feature-language feature-bound child-language child-bound
                                 (work-limit 100000) sufficient-only-p)
  "An `:expand` function that discovers observational feature projections bottom-up (reusing
Stage A's `heuristic-buckets` at zero enumeration cost when available, or running bounded
`start-observation-search`) and proposes pulled-back child frames via `dependency-proposals`.
When SUFFICIENT-ONLY-P is true, only non-trivial collision-consistent features that strictly
compress multi-input level sets are proposed."
  (lambda (job node frame language h-model ledger)
    (let* ((schema (frame-schema frame))
           (inputs (schema-inputs schema))
           (target (schema-target schema))
           (c-lang (if (and child-language (equal (language-inputs child-language) inputs))
                       child-language
                       language))
           (c-bound (or child-bound (expansion-bound node) (header-bound inputs target 24))))
      (if sufficient-only-p
          (when (and (>= (length inputs) 2)
                     (null (synthesis-job-self-name job))
                     (not (and h-model (heuristic-exact-p h-model)
                               (null (heuristic-unresolved-keys h-model)))))
            (let ((constrained
                    (loop for row in (frame-rows frame)
                          for idx from 0
                          for allowed = (extract-allowed-values (row-requirement row))
                          when (and (consp allowed) (= 1 (length allowed))
                                    (not (member :unresolved (row-known row))))
                            collect (cons idx (first allowed)))))
              (when (and (>= (length constrained) 3)
                         (< (length (remove-duplicates constrained :key #'cdr :test #'equal))
                            (length constrained)))
                (let* ((buckets (feature-buckets-for-node node frame language h-model
                                                          feature-language feature-bound work-limit ledger))
                       (candidates (loop for (expr . vals) in buckets
                                         when (and (not (lit-p expr)) (not (var-p expr))
                                                   (sufficient-statistic-values-p vals constrained))
                                           collect expr))
                       (ordered (stable-sort candidates #'< :key #'syntax-work))
                       (features (subseq ordered 0 (min 2 (length ordered)))))
                  (when features
                    (charge ledger :dependency-proposal
                            (+ 1 (reduce #'+ features :key #'syntax-work :initial-value 0)))
                    (dependency-proposals frame c-lang c-bound
                                          :features features
                                          :include-empty-p nil
                                          :solver (synthesis-job-library job)
                                          :debug-p (synthesis-job-debug-p job)))))))
          (let* ((buckets (feature-buckets-for-node node frame language h-model
                                                    feature-language feature-bound work-limit ledger))
                 (features (mapcar #'car buckets)))
            (charge ledger :dependency-proposal
                    (+ 1 (length features) (reduce #'+ features :key #'syntax-work :initial-value 0)))
            (dependency-proposals frame c-lang c-bound
                                  :features features
                                  :include-empty-p t
                                  :solver (synthesis-job-library job)
                                  :debug-p (synthesis-job-debug-p job)))))))

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
                                (library-proposals-p t) library-functions
                                (dependency-proposals-p t))
  "An `:expand` function: each node turns its own Stage A model into Stage B additive and
conditional residual branches, sufficient-statistic dependency projections (reusing Stage A's
observation buckets), and higher-order library combinator branches when LIBRARY-PROPOSALS-P
is true, so every proposal competes under Stage A full-path pricing and the 3:1 reserve schedule."
  (combine-expanders
   (when library-proposals-p
     (library-expander :child-language child-language :child-bound child-bound
                       :functions library-functions))
   (when dependency-proposals-p
     (dependency-expander :child-language child-language :child-bound child-bound
                          :work-limit work-limit
                          :sufficient-only-p (not (eq dependency-proposals-p :all))))
   (lambda (job node frame language h-model ledger)
     (let ((inputs (schema-inputs (frame-schema frame)))
           (bound (expansion-bound node)))
       (flet ((matching (lang) (and lang (equal (language-inputs lang) inputs) lang)))
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
                                   :debug-p (synthesis-job-debug-p job)))))))

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
         (lang (derive-language language :inputs scope))
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
      (let* ((name (function-definition-name definition))
             (specs (function-definition-inputs definition))
             (codes (code-parameters definition))
             (primary (find-if-not #'code-type-p specs :key #'cdr)))
        (when (and (equal target (function-definition-return-type definition))
                   (or (> (length codes) 1)
                       (and primary
                            (not (find (cdr primary) inputs :key #'cdr :test #'equal)))))
          (dolist (selected codes)
            (let* ((ctype (cdr selected))
                   (bindings (passthrough-bindings ctype inputs))
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
                (let ((decoder (apply #'app (op name) args)))
                  (charge ledger :template-construction (syntax-work decoder))
                  (push (lifted-decomposition (list :library-partial name (car selected) args)
                                              decoder child-id ctype bindings language bound solver
                                              :slack 24 :fallback-p t
                                              :policy-score *partial-application-policy-score*)
                        proposals)))))))))))

(define-knowledge-kind :decoder-template
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (unless (knowledge-entry-descriptor-profile entry)
      (compute-entry-descriptor-profile entry library))))

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
                                      (getf meta :bindings))))
               (charge ledger :template-retrieval (syntax-work decoder))
               (when (ignore-errors (expression-type decoder (acons cid ctype inputs)))
                 (push (lifted-decomposition
                        (list :learned-template (knowledge-entry-id entry))
                        decoder cid ctype bindings language bound solver
                        :lift-p (getf meta :lift-p) :slack 24 :fallback-p t
                        :policy-score (+ *learned-template-policy-score*
                                         (nth-value 1 (score-entry-by-descriptors
                                                       entry frame (caar inputs) :ledger ledger))))
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
