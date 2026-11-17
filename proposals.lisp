(in-package #:lisploop)

;;; Decomposition proposals from the library, dependencies, and remembered decoder contexts.

;;; Bounded proposal grammars, including labelled structural bootstrap proposals.
(defun candidate-library-definitions (language &key self-name functions frame)
  "Return higher-order `function-definition`s eligible for `library-decompositions`:
defined functions with a concrete body (excluding SELF-NAME and archived entries) that take
one or more `:code` parameter whose return sort is first-order. When FRAME has sequence types not covered by
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
                 for entry = (find-knowledge-entry name)
                 for def = (and (not (eq name self-name))
                                ;; A function named outright is lifted whatever its standing.
                                (or (member name functions :test #'eq)
                                    (not (or (gethash name *auto-retyped-functions*)
                                             (and entry (not (knowledge-entry-active-p entry))))))
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
                                                   self-name functions solver knowledge ledger
                                                   (debug-p *synthesis-debug-mode*))
  "Propose registered higher-order library definitions (`:fa`, `:fb`, ...) whose return type
matches FRAME's target as `:lift-p t` decompositions. Function-typed (`:code`) parameters
become lifted child frames via `lift-frame`, while unconsumed parent inputs are passed
through `bindings` so `compose-lifted-model` can synthesize `:code-subst` closures. The
decoder templates proposed with them are read from KNOWLEDGE, the knowledge library of the
job, or from the active one when there is none."
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
         (verdicts nil) ; (input-id . verdicts): the candidates' descriptors, evaluated once per input
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
                          (score-entry-by-descriptors
                           fn-name frame p-id
                           :ledger ledger
                           :extra-fo-specs extra-fo-specs
                           :verdicts (cdr (or (assoc p-id verdicts)
                                              (first (push (cons p-id
                                                                 (evaluate-frame-descriptors
                                                                  frame p-id :ledger ledger
                                                                  :describing (mapcar #'function-definition-name defs)))
                                                           verdicts)))))
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
            (learned-decoder-decompositions frame base-lang c-bound solver ledger
                                            :library (or knowledge *knowledge-library*)))))

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
                            :knowledge (synthesis-job-knowledge job)
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

;;; Structural proposals: a value built by an injective constructor is posed slot by slot,
;;; and a tuple among the inputs is offered to the child as its components.

(defparameter *product-arity-limit* 6
  "The most components a tuple, or holes a constructor, may have to be posed slot by slot.")

(defun component-bindings (inputs)
  "Bindings for a child that sees each of INPUTS, a small homogeneous tuple being replaced
by its components `(at X 'j)`. The child's inputs are numbered from 0 in the order of
INPUTS, whatever ids INPUTS carry. Returns (VALUES bindings projected-types)."
  (let ((next -1)
        (projected nil))
    (values
     (loop for (id . type) in inputs
           append (if (and (homogeneous-tuple-type-p type)
                           (<= (length (rest type)) *product-arity-limit*))
                      (progn (pushnew type projected :test #'equal)
                             (loop for index below (length (rest type))
                                   collect (cons (incf next) (term `(at ,(var id type) ,index)))))
                      (list (cons (incf next) (var id type)))))
     projected)))

(defun component-language (language bindings inputs &optional dropped-types)
  "LANGUAGE over the inputs BINDINGS compute from INPUTS, without the `:at` projections and
`:tuple` constructors of DROPPED-TYPES, which a structural proposal has already applied."
  (derive-language language
                   :inputs (binding-inputs bindings inputs)
                   :operators (remove-if (lambda (operator)
                                           (and (operator-p operator)
                                                (member (operator-name operator) '(:at :tuple))
                                                (member (operator-operand-type operator) dropped-types
                                                        :test #'equal)))
                                         (language-operators language))))

(defun rows-pin-values-p (frame)
  "True when FRAME constrains some row and each row it constrains to one explicit value."
  (and (plusp (frame-constrained-row-count frame))
       (every (lambda (row)
                (or (not (constrained-row-p row)) (nth-value 1 (row-singleton-value row))))
              (frame-rows frame))))

(defun product-decompositions (name decoder slots bindings language slack
                               &key slot-languages solver provenance)
  "One proposal for each of SLOTS, ((id . type) ...), the variables of the product DECODER.
All share SLOTS and BINDINGS, so the controller joins their models. Each slot may spend
SLACK body bits beyond its own header, using its corresponding entry in SLOT-LANGUAGES when
supplied (or LANGUAGE otherwise)."
  (loop for (id . type) in slots
        for index from 0
        for slot-lang = (or (and slot-languages (nth index slot-languages)) language)
        collect (make-decomposition
                 :name (list name index) :decoder decoder :child-id id :child-type type
                 :bindings bindings :language slot-lang
                 :bound (header-bound (language-inputs slot-lang) type slack)
                 :slots slots :structural-p t :solver solver
                 :provenance (and provenance (list* :slot index provenance)))))

(defun code-slot-child-language (base-lang raw-ct &key enrich-atoms-p)
  "Derive a child language for a Constructor-AU `:code` slot of type RAW-CT (`(:code scope sort)`):
for `:fn` operator holes, adds quoted operator constants matching SORT from BASE-LANG; for
expression holes when ENRICH-ATOMS-P is true, adds quoted inner variables and literals."
  (let* ((hscope (code-inputs raw-ct))
         (hsort (code-sort raw-ct))
         (base-ops (language-operators base-lang))
         (has-if-p (find :if base-ops :key #'operator-name))
         (extra-ops (when has-if-p (list (op :if raw-ct))))
         (extra-consts
           (cond
             ((function-sort-p hsort)
              (loop for o in base-ops
                    when (and (operator-p o) (equal (operator-type o) hsort))
                      collect (lit raw-ct o)))
             (enrich-atoms-p
              (append (loop for (id . vtype) in hscope
                            when (equal vtype hsort)
                              collect (lit raw-ct (var id vtype)))
                      (when (and (listp (language-literals base-lang))
                                 (equal (language-domain base-lang) hsort))
                        (loop for val in (language-literals base-lang)
                              when (value-p val hsort)
                                collect (lit raw-ct (lit hsort val)))))))))
    (derive-language base-lang
                     :operators (remove-duplicates (append extra-ops base-ops) :test #'equal)
                     :constants (remove-duplicates (append extra-consts (language-constants base-lang))
                                                   :test #'equal))))

(defun operator-slot-feasible-p (slot-lang raw-ct fillings)
  "True when a slot of the operator-code type RAW-CT can take every one of FILLINGS, the
operators that fill its hole in the target trees: each is a constant SLOT-LANG can quote,
or SLOT-LANG has an operator that computes a value of RAW-CT, by which an operator may be
read off an input."
  (or (every (lambda (operator)
               (member (lit raw-ct operator) (language-constants slot-lang) :test #'equal))
             fillings)
      (some (lambda (operator)
              (let ((signature (and (operator-p operator) (operator-type operator))))
                (and signature
                     (equal raw-ct (third signature))
                     ;; A selector that only passes one of its arguments on computes nothing.
                     (notany (lambda (argument) (equal raw-ct argument)) (second signature)))))
            (language-operators slot-lang))))

(defun constructor-au-product (trees scope inputs bindings base-lang slack operator-holes-p
                               &key solver ledger provenance)
  "The product of the holes of the anti-unifier of TREES in SCOPE, with operator holes when
OPERATOR-HOLES-P, as (VALUES proposals pattern); nil when the anti-unifier has no hole, is
one, has more than `*product-arity-limit*`, or has an operator hole no slot could fill
(`operator-slot-feasible-p`). A hole that every tree fills with a literal is lowered to a
slot of the literal's own type when no input of INPUTS is code."
  (let ((outer-code-p (some (lambda (spec) (code-type-p (cdr spec))) inputs))
        (first-slot (next-child-id inputs)))
    (multiple-value-bind (pattern substitutions)
        (anti-unify trees scope ledger :operator-holes-p operator-holes-p)
      (let ((holes (and pattern (pattern-holes pattern))))
        (when (and holes (not (hole-p pattern)) (<= (length holes) *product-arity-limit*))
          (multiple-value-bind (constructor parameters) (compile-au-constructor pattern scope ledger)
            (let ((slots nil) (slot-langs nil) (decoder-subst nil))
              (loop for (hole-id . raw-ct) in parameters
                    for slot-id from first-slot
                    for hsort = (code-sort raw-ct)
                    for fillings = (remove-duplicates
                                    (loop for substitution in substitutions
                                          for filling = (cdr (assoc hole-id substitution))
                                          when filling collect filling)
                                    :test #'equal)
                    do (cond
                         ((and (not (function-sort-p hsort)) (not outer-code-p) fillings
                               (every (lambda (filling)
                                        (and (lit-p filling) (equal hsort (ast-type filling))))
                                      fillings))
                          (push (cons slot-id hsort) slots)
                          (push base-lang slot-langs)
                          (push (cons hole-id
                                      (term `(code-subst ,(lit (code-type (list (cons 0 hsort)) hsort)
                                                               (var 0 hsort))
                                                         (tuple ,(var slot-id hsort)))
                                            raw-ct))
                                decoder-subst))
                         (t
                          (let ((slot-lang (code-slot-child-language
                                            base-lang raw-ct :enrich-atoms-p (not outer-code-p))))
                            (when (and (function-sort-p hsort)
                                       (not (operator-slot-feasible-p slot-lang raw-ct fillings)))
                              (return-from constructor-au-product nil))
                            (push (cons slot-id raw-ct) slots)
                            (push slot-lang slot-langs)
                            (push (cons hole-id (var slot-id raw-ct)) decoder-subst)))))
              (values
               (product-decompositions
                (if operator-holes-p :constructor-au-operators :constructor-au)
                ;; The constructor numbers its holes from 0; the slots must not clash with INPUTS.
                (instantiate constructor (nreverse decoder-subst) :var)
                (nreverse slots) bindings base-lang slack
                :slot-languages (nreverse slot-langs)
                :solver solver
                :provenance (and provenance (append provenance (list :pattern pattern))))
               pattern))))))))

(defun constructor-au-decompositions (trees scope inputs bindings base-lang slack
                                      &key solver ledger provenance)
  "The Constructor-AU products of TREES in SCOPE: the one whose anti-unifier aligns
applications of different operators under an operator hole, when its slots can be filled,
and the one that puts a whole expression there. Both are proposed when they differ, since
either may be the one a child can solve: an operator is quoted or read off an input, an
expression is built or is a subterm of an input."
  (multiple-value-bind (with-operators operator-pattern)
      (constructor-au-product trees scope inputs bindings base-lang slack t
                              :solver solver :ledger ledger :provenance provenance)
    (multiple-value-bind (plain plain-pattern)
        (constructor-au-product trees scope inputs bindings base-lang slack nil
                                :solver solver :ledger ledger :provenance provenance)
      (append with-operators
              (unless (and with-operators (equal operator-pattern plain-pattern))
                plain)))))

(defun structural-decompositions (frame language bound &key solver ledger (debug-p *synthesis-debug-mode*))
  "Proposals that take FRAME's values apart without computing anything, for a child that
may spend the body bits BOUND leaves FRAME. A tuple target whose rows pin its value is the
product of its components. A target of quoted code whose rows pin two or more distinct
trees is the product of the holes of their anti-unifier (including `:fn` operator holes and
lowered value-literal holes). Either way, and for a scalar target, small tuples among the
inputs are replaced by their components."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (slack (max 18 (- bound (header-size inputs target))))
         (first-slot (next-child-id inputs))
         (pinned-p (rows-pin-values-p frame)))
    (multiple-value-bind (bindings projected) (component-bindings inputs)
      (flet ((child-language (&optional built)
               (component-language language bindings inputs (append built projected)))
             (provenance (origin &rest more)
               (when debug-p (list* :origin origin :bindings bindings more))))
        (cond
          ((and pinned-p (tuple-type-p target) (<= 1 (length (rest target)) *product-arity-limit*))
           (let ((slots (loop for type in (rest target)
                              for id from first-slot
                              collect (cons id type))))
             (product-decompositions
              :tuple-product
              (apply #'app (op :tuple target) (loop for (id . type) in slots collect (var id type)))
              slots bindings (child-language (list target)) slack
              :solver solver :provenance (provenance :tuple-product))))
          ((and pinned-p (expression-code-p target))
           (let* ((scope (code-inputs target))
                  (trees (remove-duplicates
                          (loop for row in (frame-rows frame)
                                when (constrained-row-p row) collect (row-singleton-value row))
                          :test #'equal)))
             (when (rest trees)
               (constructor-au-decompositions trees scope inputs bindings (child-language) slack
                                              :solver solver :ledger ledger
                                              :provenance (provenance :constructor-au)))))
          ;; A compound target may need the tuple whole, as an argument or as its own value.
          ((and projected (or (member target '(:int :bool)) (gf-type-p target)))
           (list (make-decomposition
                  :name :components :decoder (var first-slot target) :child-id first-slot
                  :child-type target :bindings bindings :language (child-language)
                  :bound (header-bound (binding-inputs bindings inputs) target slack)
                  :structural-p t :solver solver
                  :provenance (provenance :components)))))))))

(defun structural-expander (&key child-language child-bound)
  "An `:expand` function that proposes `structural-decompositions` of the node's frame."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    ;; A recursive definition is judged as a whole: its slots could not each call it.
    (unless (and (synthesis-job-self-name job) (not (node-in-lifted-library-branch-p node)))
      (let ((inputs (schema-inputs (frame-schema frame))))
        (structural-decompositions
         frame
         (if (and child-language (equal (language-inputs child-language) inputs)) child-language language)
         (or child-bound (expansion-bound node)
             (header-bound inputs (schema-target (frame-schema frame)) 24))
         :solver (synthesis-job-library job)
         :ledger ledger
         :debug-p (synthesis-job-debug-p job))))))

;;; Induced row order: a key along which the target varies little gives the rows a topology.

(define-knowledge-kind :locality-key
  (:priority 50)
  (:validate (entry library)
    (declare (ignore library))
    (assert (eq :int (knowledge-entry-target entry)))
    (assert-entry-expression-type entry)))

(defun canonical-row-order (frame)
  "FRAME's rows in an order fixed by what they know and require, whatever order they are
stored in; rows that know and require the same are ordered by their keys. A known value is
written by its declared type, as `canonical-constraint-rows` writes it."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (flet ((printed (row)
             (with-standard-io-syntax
               (prin1-to-string
                (list (loop for value in (row-known row)
                            for (nil . type) in inputs
                            collect (if (eq value :unresolved)
                                        :unresolved
                                        (ast->sexp (lit type value))))
                      (ast->sexp (row-requirement row))
                      (row-key row))))))
      (mapcar #'cdr (stable-sort (mapcar (lambda (row) (cons (printed row) row)) (frame-rows frame))
                                 #'string< :key #'car)))))

(defparameter *projection-key-slack* 40
  "Body bits a row-order key read off a compound input may take beyond its header.")

(defparameter *projection-key-work* 20000
  "The most work `projection-row-keys` spends observing the accessors of a frame's inputs.")

(defparameter *row-order-star-centres* 8
  "The most targets tried as the centre of the star baseline of `induce-row-order` when a
metric or a metric decoder prices each correction by running a program.")

(defun projection-language (inputs)
  "A language of nothing but the accessors of the compound types among INPUTS: a component
of a tuple, the length and an element of a sequence, and the small literals that index them.
Nil when no input is compound."
  (let ((operators nil) (indices (list 0)))
    (loop for (nil . type) in inputs
          do (cond ((tuple-type-p type)
                    (pushnew (op :at type) operators)
                    (loop for index from 1 below (length (rest type)) do (pushnew index indices)))
                   ((seq-type-p type)
                    (pushnew (op :length type) operators)
                    (pushnew (op :at type) operators))))
    (when operators
      (make-language :int inputs :operators (nreverse operators) :literals (sort indices #'<)))))

(defun projection-row-keys (frame ledger)
  "Integer features of FRAME's compound inputs in the form of Stage A buckets,
((expression . row-values) ...): what a short observation search over the inputs' own
accessors (`projection-language`) finds. The kernel's enumerator writes the expressions and
the VM evaluates them on every row, for work charged to LEDGER; an accessor that fails on a
row, like the first element of an empty sequence, is no feature."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (language (projection-language inputs)))
    (when language
      (let ((job (start-observation-search
                  (make-observation-scope (unconstrained-frame frame :int) language))))
        (resume-observation-search job (header-bound inputs :int *projection-key-slack*)
                                   *projection-key-work*)
        (charge ledger :row-order (ledger-total (observation-job-ledger job)))
        (observation-feature-buckets job)))))

(defun stored-row-keys (frame library ledger)
  "The `:locality-key` entries LIBRARY keeps for FRAME's inputs, each evaluated on FRAME's
rows in the VM on LEDGER, as ((expression . row-values) ...); a key that has no value on
some row is left out."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (loop for entry in (and library (knowledge-entries-of-kind :locality-key library))
          for key = (knowledge-entry-expression entry)
          when (and (knowledge-entry-active-p entry)
                    (equal inputs (knowledge-entry-inputs entry)))
            append (let ((values (loop for row in (frame-rows frame)
                                       collect (multiple-value-bind (value known-p)
                                                   (and (not (member :unresolved (row-known row)))
                                                        (eval-expr-value key inputs (row-known row) ledger))
                                                 (if known-p value (return nil))))))
                     (and values (list (cons key values)))))))

(defun induce-row-order (frame &key buckets ledger (library *knowledge-library*))
  "Look for an integer key k(X) along which FRAME's target varies little. The candidates are
the integer inputs, which cost nothing to read; the integer features in BUCKETS,
((expression . row-values) ...) as Stage A leaves them, or without BUCKETS the features a
short search over the accessors of the compound inputs observes (`projection-row-keys`);
and the keys LIBRARY remembers for these inputs (`stored-row-keys`). Rows are sorted by each
key, ties being broken by `canonical-row-order`, and the targets are priced as a chain: the
first in full, each next one as a correction of the one before, plus the body of the key.
A key is induced when its chain is cheaper than the targets priced one by one and than
their star, every target as a correction of the best single one. Where a frame metric or a
metric decoder prices a correction by running a program, the star tries at most
`*row-order-star-centres*` centres. Returns nil, or (VALUES key edges chain-bits baseline-bits)."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (metric (frame-metric frame))
         (decoders (unless metric (metric-decoders target (or library *knowledge-library*))))
         (stored (frame-rows frame))
         (rows (canonical-row-order frame)))
    (when (and (>= (length rows) 3)
               (every (lambda (row) (nth-value 1 (row-singleton-value row))) rows))
      (labels ((step-bits (before after)
                 (if (or metric decoders)
                     (nth-value 1 (priced-correction before after target
                                                     :metric metric :decoders decoders :ledger ledger))
                     (correction-bit-size before after target)))
               (chain-bits (ordered)
                 (+ (value-bit-size (row-singleton-value (first ordered)) target)
                    (loop for (before after) on ordered
                          while after
                          sum (step-bits (row-singleton-value before) (row-singleton-value after)))))
               (key-values (values)
                 ;; (row . value) for values listed in stored order, or nil unless all are integers
                 (and (= (length values) (length stored))
                      (every #'integerp values)
                      (mapcar #'cons stored values))))
        (let* ((targets (mapcar #'row-singleton-value rows))
               (independent (loop for value in targets sum (value-bit-size value target)))
               (centres (if (or metric decoders)
                            (subseq targets 0 (min *row-order-star-centres* (length targets)))
                            targets))
               (star (loop for centre in centres
                           minimize (+ (value-bit-size centre target)
                                       (loop for value in targets
                                             sum (step-bits centre value)))))
               (baseline (min independent star))
               (candidates
                 (remove-duplicates
                  (append (loop for (id . type) in inputs
                                for position from 0
                                when (eq :int type)
                                  collect (cons (var id type)
                                                (key-values (mapcar (lambda (row) (nth position (row-known row)))
                                                                    stored))))
                          (loop for (expression . values)
                                  in (append (or buckets (projection-row-keys frame ledger))
                                             (stored-row-keys frame library ledger))
                                when (and (eq :int (ast-type expression)) (not (var-p expression))
                                          (not (lit-p expression)))
                                  collect (cons expression (key-values values))))
                  :key #'car :test #'equal :from-end t))
               (best nil))              ; (key ordered-rows bits)
          (loop for (key . by-row) in candidates
                when (and by-row (rest (remove-duplicates (mapcar #'cdr by-row))))
                  do (charge ledger :orientation (length rows))
                     (let* ((ordered (stable-sort (copy-list rows) #'<
                                                  :key (lambda (row) (cdr (assoc row by-row)))))
                            (bits (+ (chain-bits ordered) (body-size key inputs))))
                       (when (or (null best) (< bits (third best))
                                 (and (= bits (third best)) (expression-less-p key (first best) inputs)))
                         (setf best (list key ordered bits)))))
          (when (and best (< (third best) baseline))
            (destructuring-bind (key ordered bits) best
              (values key
                      (append (loop for (before after) on ordered
                                    while after
                                    collect (list :persistence (row-key before) (row-key after)))
                              (let ((first-row (first ordered)) (last-row (car (last ordered))))
                                (unless (equal (row-singleton-value first-row) (row-singleton-value last-row))
                                  (list (list :distinct (row-key first-row) (row-key last-row))))))
                      bits baseline))))))))

(defun with-induced-row-order (frame &key buckets ledger library)
  "FRAME with its rows stored along the chain of an induced key and the chain's edges
attached, and the key, as two values; FRAME itself and nil when no key is induced. With
LIBRARY the key is registered there once as a `:locality-key` for later correspondence search."
  (multiple-value-bind (key edges chain-bits baseline-bits)
      (induce-row-order frame :buckets buckets :ledger ledger :library (or library *knowledge-library*))
    (if (null key)
        (values frame nil)
        (let* ((chain (cons (second (first edges))
                            (loop for (kind nil after) in edges
                                  when (eq kind :persistence) collect after)))
               (inputs (schema-inputs (frame-schema frame))))
          (when (and library
                     (not (find-if (lambda (entry)
                                     (and (knowledge-entry-active-p entry)
                                          (equal inputs (knowledge-entry-inputs entry))
                                          (equal key (knowledge-entry-expression entry))))
                                   (knowledge-entries-of-kind :locality-key library))))
            (register-knowledge-entry
             (make-knowledge-entry :kind :locality-key :inputs inputs :target :int :expression key
                                   :gain (- baseline-bits chain-bits) :status :empirical
                                   :certificate '(:kind :induced-row-order) :library library)
             :library library :ledger ledger))
          (values (derive-frame frame
                                :rows (mapcar (lambda (row-key)
                                                (snapshot-row (find row-key (frame-rows frame)
                                                                    :key #'row-key :test #'equal)))
                                              chain)
                                :edges (append (frame-edges frame) edges))
                  key)))))

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
                                (dependency-proposals-p t) (structural-proposals-p t))
  "An `:expand` function: each node turns its own Stage A model into Stage B additive and
conditional residual branches, sufficient-statistic dependency projections (reusing Stage A's
observation buckets), higher-order library combinator branches when LIBRARY-PROPOSALS-P
is true, and the structural products and projections of its frame when STRUCTURAL-PROPOSALS-P
is, so every proposal competes under Stage A full-path pricing and the 3:1 reserve schedule."
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
                                   :debug-p (synthesis-job-debug-p job)))))
   (when structural-proposals-p
     (structural-expander :child-language child-language :child-bound child-bound))))

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
  ;; A template mentions the functions its decoder calls without being a use of them.
  (:passive t)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (unless (knowledge-entry-descriptor-profile entry)
      (compute-entry-descriptor-profile entry library)))
  (:consolidate (entries library ledger)
    (declare (ignore entries))
    (generalize-decoder-templates library :ledger ledger)))

(defun remember-decoder-template (proposal parent-inputs &key (library *knowledge-library*) ledger work)
  "Store an observed single-child decomposition as typed library syntax, not a family tag.
Multi-slot product proposals are skipped; remembered templates remain empirical proposals."
  (when (decomposition-slots proposal)
    (return-from remember-decoder-template nil))
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

(defun register-derived-decoder-template (decoder child-id child-type parameters origin edges
                                          &key requires-input (library *knowledge-library*) ledger)
  "Register DECODER, an expression over its child CHILD-ID of CHILD-TYPE and PARAMETERS,
((id . type) ...), as a `:decoder-template` the library derived from what it holds, not one
a solved task was seen to use. Its child reads every input of the frame it is posed in
(:bindings :identity). EDGES say what it was derived from, ORIGIN how. REQUIRES-INPUT, a
type, keeps it for frames with an input that is or holds that type. Returns the entry, or
nil when LIBRARY already holds this template."
  (let ((inputs (acons child-id child-type parameters)))
    (unless (find-if (lambda (entry)
                       (and (equal inputs (knowledge-entry-inputs entry))
                            (equal decoder (knowledge-entry-expression entry))
                            (eq :identity (getf (knowledge-entry-metadata entry) :bindings))))
                     (knowledge-entries-of-kind :decoder-template library))
      (register-knowledge-entry
       (make-knowledge-entry :kind :decoder-template :inputs inputs :target (ast-type decoder)
                             :expression decoder :status :empirical :edges edges
                             :metadata (list :origin origin :child-id child-id
                                             :dependencies (expression-dependencies (list decoder))
                                             :lift-p nil :bindings :identity
                                             :requires-input requires-input)
                             :library library)
       :library library :ledger ledger))))

(defun remember-motif-decoder (law decoder child-id &key (library *knowledge-library*) ledger)
  "Keep the decoder that LAW, a conjecture a motif induced, licenses: DECODER is the side of
its equation that computes a function's value by another fold from the sequence CHILD-ID,
so a frame of that value may be posed as the search for such a sequence. The template is
`:licensed-by` LAW and proposed only while LAW stands (`decoder-template-live-p`). The law
stays a conjecture and rewrites nothing; what a proposal built on it yields is verified
like any other. Returns the template, or nil when LIBRARY already holds it."
  (let ((child-type (cdr (assoc child-id (knowledge-entry-inputs law)))))
    (register-derived-decoder-template
     decoder child-id child-type nil :motif-transfer
     (list (list :licensed-by (knowledge-entry-id law)))
     :requires-input child-type :library library :ledger ledger)))

(defun generalize-decoder-templates (library &key ledger)
  "Anti-unify the decoder templates LIBRARY has observed. Templates of pulled-back children
of one type, over parameters of the same types, whose decoders differ in exactly one place
and mention their child nowhere else, share the decoder around that place: it is registered
as a template of its own whose child is what stood there, with the parameters it still
mentions, and the edge (:generalizes ...) to the templates it came from. One that only
repeats a template whose child already stood there is not. Returns the entries added; the
templates it derives are not generalised again, so a second call adds none."
  (let ((groups nil)                    ; ((child-type parameter-types) (entry parameters decoder) ...)
        (added nil))
    (dolist (entry (knowledge-entries-of-kind :decoder-template library))
      (let* ((meta (knowledge-entry-metadata entry))
             (child-id (getf meta :child-id))
             (child-type (cdr (assoc child-id (knowledge-entry-inputs entry)))))
        (when (and (knowledge-entry-active-p entry)
                   (eq :observed-decomposition (getf meta :origin))
                   (not (getf meta :lift-p))
                   child-type
                   (decoder-template-live-p entry library))
          ;; The child is variable 0; the parameters follow, ordered by type.
          (let* ((ordered (stable-sort (remove child-id (copy-list (knowledge-entry-inputs entry)) :key #'car)
                                       #'string<
                                       :key (lambda (parameter)
                                              (with-standard-io-syntax (prin1-to-string (cdr parameter))))))
                 (parameters (loop for (nil . type) in ordered for id from 1 collect (cons id type)))
                 (decoder (instantiate (knowledge-entry-expression entry)
                                       (acons child-id (var 0 child-type)
                                              (loop for (old . type) in ordered
                                                    for (new . nil) in parameters
                                                    collect (cons old (var new type))))
                                       :var))
                 (key (list child-type (mapcar #'cdr parameters)))
                 (group (or (assoc key groups :test #'equal)
                            (first (push (list key) groups)))))
            (push (list entry parameters decoder) (cdr group))))))
    (dolist (group (reverse groups) (nreverse added))
      (destructuring-bind ((child-type parameter-types) . members) group
        (declare (ignore parameter-types))
        (let* ((members (reverse members))
               (parameters (second (first members)))
               (decoders (remove-duplicates (mapcar #'third members) :test #'equal)))
          (when (rest decoders)
            (let* ((pattern (anti-unify decoders (acons 0 child-type parameters) ledger
                                        :operator-holes-p nil))
                   (holes (and pattern (pattern-holes pattern))))
              (when (and holes (null (rest holes)) (not (hole-p pattern))
                         (not (member 0 (free-vars pattern)))
                         (valid-type-p (cdr (first holes))))
                (let* ((type (cdr (first holes)))
                       (decoder (instantiate pattern (list (cons (car (first holes)) (var 0 type))) :hole))
                       (entry (and (not (member decoder decoders :test #'equal))
                                   (register-derived-decoder-template
                                    decoder 0 type
                                    (remove-if-not (lambda (parameter)
                                                     (member (car parameter) (free-vars decoder)))
                                                   parameters)
                                    :template-generalization
                                    (list (cons :generalizes
                                                (mapcar (lambda (member) (knowledge-entry-id (first member)))
                                                        members)))
                                    :library library :ledger ledger))))
                  (when entry (push entry added)))))))))))

(defun type-mentions-p (type part)
  "True when TYPE is PART or is a tuple or sequence that holds it."
  (or (equal type part)
      (and (consp type)
           (member (first type) '(:tuple :seq))
           (some (lambda (inner) (type-mentions-p inner part)) (rest type)))))

(defun template-dependencies-live-p (dependencies library)
  "True when every function dependency in DEPENDENCIES remains currently defined and active."
  (and (every (lambda (dep)
                (let ((entry (find-knowledge-entry (first dep) library)))
                  (and (defined-function-p (first dep))
                       (or (null entry) (knowledge-entry-active-p entry)))))
              dependencies)
       (equalp dependencies
               (expression-dependencies
                (loop for dep in dependencies
                      when (defined-function-p (first dep)) collect (op (first dep)))))))

(defun decoder-template-live-p (entry library)
  "True while the template ENTRY may be proposed: the functions its decoder calls are still
defined as they were and active, and every entry that licenses it is in LIBRARY, active,
and not refuted."
  (and (template-dependencies-live-p (getf (knowledge-entry-metadata entry) :dependencies) library)
       (every (lambda (edge)
                (let ((source (find-knowledge-entry (second edge) library)))
                  (and source
                       (knowledge-entry-active-p source)
                       (not (eq :refuted (knowledge-entry-status source))))))
              (knowledge-edges-from entry :licensed-by library))))

(defun learned-decoder-decompositions (frame language bound solver ledger
                                       &key (library *knowledge-library*))
  "Retrieve the `:decoder-template` entries of LIBRARY that are active and live
(`decoder-template-live-p`) and whose target is FRAME's, under every renaming of their
parameters onto FRAME's inputs of the same types: the templates solved tasks were seen to
use, and those the library derived from them or from its laws at consolidation. At most
`*library-partial-proposal-limit*` are returned."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (cid (next-child-id inputs))
         (proposals nil))
    (dolist (entry (knowledge-entries-of-kind :decoder-template library) (nreverse proposals))
      (let* ((meta (knowledge-entry-metadata entry))
             (old-cid (getf meta :child-id))
             (ctype (cdr (assoc old-cid (knowledge-entry-inputs entry))))
             (params (remove old-cid (knowledge-entry-inputs entry) :key #'car))
             (stored-bindings (getf meta :bindings))
             (required (getf meta :requires-input)))
        (when (and (knowledge-entry-active-p entry)
                   ctype
                   (equal target (knowledge-entry-target entry))
                   (or (null required)
                       (some (lambda (spec) (type-mentions-p (cdr spec) required)) inputs))
                   (decoder-template-live-p entry library))
          (let ((options (mapcar (lambda (param)
                                   (loop for (id . type) in inputs
                                         when (equal type (cdr param)) collect (var id type)))
                                 params))
                (score (+ *learned-template-policy-score*
                          (nth-value 1 (score-entry-by-descriptors
                                        entry frame (caar inputs) :ledger ledger)))))
            (map-cartesian-options
             options
             (lambda (args)
               (when (>= (length proposals) *library-partial-proposal-limit*)
                 (return-from learned-decoder-decompositions (nreverse proposals)))
               (let* ((substitution (acons old-cid (var cid ctype)
                                           (mapcar #'cons (mapcar #'car params) args)))
                      (decoder (instantiate (knowledge-entry-expression entry) substitution :var))
                      (bindings (if (eq :identity stored-bindings)
                                    (identity-bindings inputs)
                                    (mapcar (lambda (b)
                                              (cons (car b)
                                                    (instantiate (sexp->ast (cdr b)) substitution :var)))
                                            stored-bindings))))
                 (charge ledger :template-retrieval (syntax-work decoder))
                 (when (ignore-errors (expression-type decoder (acons cid ctype inputs)))
                   (push (lifted-decomposition
                          (list :learned-template (knowledge-entry-id entry))
                          decoder cid ctype bindings language bound solver
                          :lift-p (getf meta :lift-p) :slack 24 :fallback-p t
                          :policy-score score)
                         proposals)))))))))))

(defun remember-successful-decompositions (job library ledger)
  (let* ((best (synthesis-job-best job))
         (message (find-if (lambda (m) (and (eq :candidate (message-claim m))
                                           (eq best (getf (message-evidence m) :candidate))))
                           (synthesis-job-messages job)))
         (node (and message (find (message-call-id message) (synthesis-job-nodes job) :key #'synthesis-node-id)))
         (entries nil))
    (loop while (and node (synthesis-node-parent node))
          do (let* ((parent (synthesis-node-parent node))
                    ;; A slot of a product is not remembered as a template.
                    (entry (remember-decoder-template
                            (synthesis-node-proposal node)
                            (schema-inputs (frame-schema (synthesis-node-frame parent)))
                            :library library :ledger ledger
                            :work (ledger-total (synthesis-job-ledger job)))))
               (when entry (push entry entries))
               (setf node parent)))
    entries))
