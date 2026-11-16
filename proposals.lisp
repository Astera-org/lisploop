(in-package #:lisploop)

;;; Decomposition proposals from the library, dependencies, product spaces, and remembered templates.

(defun candidate-library-definitions (language &key self-name functions frame)
  "Return higher-order `function-definition`s eligible for `library-decompositions`."
  (let* ((ho-ops (loop for o in (language-operators language) for n = (and (operator-p o) (operator-name o))
                       for d = (and n (find-function-definition n)) when (and d (code-parameters d)) collect n))
         (names (remove-duplicates (or functions ho-ops (reverse *registered-function-names*)) :test #'eq :from-end t))
         (base (loop for n in names for e = (and *knowledge-library* (find-knowledge-entry n *knowledge-library*))
                     for d = (and (not (eq n self-name)) (or (null e) (active-knowledge-entry-p e))
                                  (or (member n functions :test #'eq) (not (gethash n *auto-retyped-functions*)))
                                  (find-function-definition n))
                     when (and d (function-definition-body d) (null (function-definition-oracle-table d))
                               (code-parameters d) (notany (lambda (s) (function-sort-p (code-sort (cdr s)))) (code-parameters d)))
                       collect d)))
    (if (null frame) base
        (let* ((schema (frame-schema frame)) (target (schema-target schema))
               (in-elems (remove-duplicates (loop for (nil . tp) in (schema-inputs schema)
                                                  when (seq-type-p tp) collect (second tp)) :test #'equal))
               (out-elem (if (seq-type-p target) (second target) target))
               retyped)
          (dolist (def base (remove-duplicates (append base (nreverse retyped))
                                               :key #'function-definition-name :test #'eq :from-end t))
            (let* ((sspec (find-if #'seq-type-p (function-definition-inputs def) :key #'cdr))
                   (orig (and sspec (second (cdr sspec)))))
              (when orig
                (dolist (ie in-elems)
                  (unless (equal ie orig)
                    (let ((r (ignore-errors (retype-function-definition (function-definition-name def) ie :auto-p t))))
                      (when r (push r retyped))))
                  (unless (equal ie out-elem)
                    (let ((r (ignore-errors (retype-function-definition (function-definition-name def) ie
                                                                        :return-element-type out-elem :auto-p t))))
                      (when r (push r retyped))))))))))))

(defun candidate-fo-argument-expressions (frame language primary-input-id param-type)
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
         (ppos (and primary-input-id (position primary-input-id inputs :key #'car :test #'eql))) exprs)
    (flet ((add (e) (pushnew e exprs :test #'equal)))
      (dolist (s (schema-available-inputs schema))
        (when (and (not (eql (car s) primary-input-id)) (equal (cdr s) param-type)) (add (var (car s) (cdr s)))))
      (unless (and (seq-type-p param-type) (some #'var-p exprs))
        (when (and ppos (seq-type-p (cdr (nth ppos inputs))) (equal param-type target))
          (dolist (row (frame-rows frame))
            (when (empty-sequence-row-p row ppos)
              (multiple-value-bind (v ok) (row-singleton-value row) (when ok (add (lit param-type v)))))))
        (dolist (c (language-constants language)) (when (equal (ast-type c) param-type) (add c)))
        (when (seq-type-p param-type) (add (lit param-type '())))
        (when (and (eq param-type :int) (listp (language-literals language)))
          (dolist (v (language-literals language)) (when (integerp v) (add (lit :int v)))))
        (add (lit param-type (default-value-for-type param-type))))
      (nreverse exprs))))

(defun library-decoder-compatible-with-empty-rows-p (frame seq-input-id decoder child-id child-type bindings ledger)
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (spos (and seq-input-id (position seq-input-id inputs :key #'car :test #'eql)))
         (erows (when (and spos (seq-type-p (cdr (nth spos inputs))))
                  (remove-if-not (lambda (r) (empty-sequence-row-p r spos)) (frame-rows frame)))))
    (or (null erows)
        (every (lambda (r) (not (unsatisfiable-requirement-p (fold-constants (row-requirement r) :ledger ledger :budget 500))))
               (frame-rows (pullback-frame (make-frame (frame-schema frame) erows) decoder child-id child-type bindings ledger))))))

(defun passthrough-bindings (code-type inputs &optional consumed-ids)
  (loop for (id . tp) in (remove-if (lambda (s) (member (car s) consumed-ids)) inputs)
        for cid from (next-child-id (code-inputs code-type))
        collect (cons cid (var id tp))))

(defun lifted-decomposition (name decoder child-id child-type bindings language bound solver
                             &key slack (lift-p t) fallback-p (policy-score 0) provenance)
  (let ((ci (append (when lift-p (code-inputs child-type))
                    (loop for (id . e) in bindings collect (cons id (ast-type e)))))
        (cs (if lift-p (code-sort child-type) child-type)))
    (make-decomposition
     :name name :decoder decoder :child-id child-id :child-type child-type :bindings bindings
     :language (derive-language language :inputs ci) :bound (if slack (max bound (header-bound ci cs slack)) bound)
     :lift-p lift-p :solver solver :fallback-p fallback-p :policy-score policy-score :provenance provenance)))

(defparameter *filter-map-policy-score* -18)
(defparameter *partial-application-policy-score* 8)
(defparameter *learned-template-policy-score* 6)

(defun aligned-filter-predicate (slices child-inputs language ledger)
  "Shortest Boolean predicate over CHILD-INPUTS keeping the subsequence aligned with outputs."
  (let* ((domain (language-domain language))
         (erows (loop with k = -1 for (iv nil ev) in slices
                      append (loop for x in iv collect (make-row :key (incf k) :known (cons x (copy-tree ev))
                                                                 :requirement (lit :bool t)))))
         (cops (remove-duplicates (append (remove-if-not (lambda (o) (and (operator-p o) (eq :< (operator-name o))))
                                                         (language-operators language))
                                          (cons (op := domain) (mapcar (lambda (s) (op := (cdr s))) child-inputs)))
                                  :test #'equal))
         (lits (if (listp (language-literals language))
                   (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal) '(0 1)))
         (atoms (append (loop for (id . tp) in child-inputs collect (var id tp))
                        (loop for v in lits when (value-p v domain) collect (lit domain v)))))
    (labels ((aligned-p (vals keep)
               (let ((seen (make-hash-table :test #'equal)))
                 (loop for (iv ov ev) in slices
                       for kept = (loop for x in iv when (eq keep (and (pop vals) t)) collect x)
                       always (and (= (length kept) (length ov))
                                   (loop for x in kept for y in ov for k = (cons x ev)
                                         always (equal y (if (nth-value 1 (gethash k seen)) (gethash k seen)
                                                             (setf (gethash k seen) y))))))))
             (best-aligned (obs)
               (let (valid)
                 (loop for (e . vals) in obs do
                   (dolist (keep '(t nil))
                     (when (aligned-p vals keep)
                       (let ((p (if keep e (bool-not e)))) (push (cons (description-size p child-inputs) p) valid)))))
                 (cdr (best-by valid #'car)))))
      (when erows
        (or (best-aligned
             (loop for cmp in cops for tp = (operator-operand-type cmp)
                   append (loop for (a b) in (cartesian-product-lists (list atoms atoms))
                                for e = (and (equal (ast-type a) tp) (equal (ast-type b) tp)
                                             (not (equal a b)) (or (var-p a) (var-p b)) (app cmp a b))
                                for vals = (and e (loop for r in erows for run = (evaluate e child-inputs (row-known r) :ledger ledger)
                                                        when (eq :value (evaluation-status run)) collect (evaluation-value run)))
                                when (and e (= (length vals) (length erows))) collect (cons e vals))))
            (best-aligned
             (observed-predicates (make-frame (make-schema :inputs child-inputs :target :bool) erows)
                                  (derive-language language :inputs child-inputs :operators cops :literals lits :constants nil)
                                  (header-bound child-inputs :bool 20) 3000 ledger)))))))

(defun filter-map-decompositions (frame base-lang defs child-id c-bound solver ledger debug-p)
  (let* ((schema (frame-schema frame)) (avail (schema-available-inputs schema))
         (inputs (schema-inputs schema)) (target (schema-target schema)) proposals)
    (when (seq-type-p target)
      (loop for (p-id . st) in avail for p-pos = (position p-id inputs :key #'car :test #'equal)
            when (seq-type-p st) do
              (let* ((ie (second st)) (re (second target))
                     (examples (loop for r in (frame-rows frame) for iv = (nth p-pos (row-known r))
                                     for (ov ok) = (multiple-value-list (row-singleton-value r))
                                     when (and ok (listp iv) (listp ov)) collect (list r iv ov))))
                (flet ((comb (rt sort)
                         (find-if (lambda (d)
                                    (let ((c (first (code-parameters d))))
                                      (and c (equal (function-definition-return-type d) rt)
                                           (= 2 (length (function-definition-inputs d)))
                                           (find st (function-definition-inputs d) :key #'cdr :test #'equal)
                                           (equal (code-inputs (cdr c)) (list (cons 0 ie)))
                                           (equal (code-sort (cdr c)) sort))))
                                  defs))
                       (call (d ca sa)
                         (if (code-type-p (cdr (first (function-definition-inputs d))))
                             (app (op (function-definition-name d)) ca sa)
                             (app (op (function-definition-name d)) sa ca))))
                  (let ((mdef (comb target re)) (fdef (comb st :bool)))
                    (when (and examples mdef fdef
                               (every (lambda (e) (<= (length (third e)) (length (second e)))) examples)
                               (some (lambda (e) (< (length (third e)) (length (second e)))) examples)
                               (or (not (equal ie re))
                                   (some (lambda (e) (set-difference (third e) (second e) :test #'equal)) examples)))
                      (let* ((mct (cdr (first (code-parameters mdef)))) (fct (cdr (first (code-parameters fdef))))
                             (bindings (passthrough-bindings mct inputs (list p-id)))
                             (ci (append (code-inputs mct) (loop for (id . e) in bindings collect (cons id (ast-type e)))))
                             (pred (aligned-filter-predicate
                                    (loop for (r iv ov) in examples
                                          collect (list iv ov (evaluate-row-bindings bindings inputs (row-known r)
                                                                                     :ledger ledger :allow-unresolved-p t)))
                                    ci base-lang ledger)))
                        (when pred
                          (let* ((mn (function-definition-name mdef)) (fn (function-definition-name fdef))
                                 (dec (call mdef (var child-id mct)
                                            (call fdef (compose-lifted-model (var child-id fct) child-id fct pred bindings ledger)
                                                  (var p-id st)))))
                            (push (lifted-decomposition
                                   (list :library-filter-map mn fn pred) dec child-id mct bindings base-lang c-bound solver
                                   :policy-score *filter-map-policy-score*
                                   :provenance (when debug-p (list :origin :filter-map-expander :map mn :filter fn
                                                                   :predicate pred :decoder dec)))
                                  proposals))))))))))
    (nreverse proposals)))

(defun library-decompositions (frame language &key child-language child-bound self-name functions solver ledger
                                                   (debug-p *synthesis-debug-mode*))
  "Propose registered higher-order library definitions as `:lift-p t` decompositions."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (avail (schema-available-inputs schema)) (target (schema-target schema))
         (c-bound (or child-bound (header-bound inputs target 24))) (base-lang (or child-language language))
         (slack (if (some (lambda (o) (and (operator-p o) (defined-function-p (operator-name o))))
                          (language-operators base-lang))
                    32 24))
         (cid (next-child-id inputs))
         (defs (candidate-library-definitions language :self-name self-name :functions functions :frame frame))
         (ho-defs (loop for d in defs for e = (and (knowledge-library-p solver) (find-knowledge-entry (function-definition-name d) solver))
                        when (and (equal (function-definition-return-type d) target)
                                  (= 1 (length (code-parameters d))) (or (null e) (active-knowledge-entry-p e)))
                          collect d))
         (dlib (or (and (knowledge-library-p solver) solver) *knowledge-library*))
         (eseq (or (car (find-if #'seq-type-p avail :key #'cdr)) (caar avail) (caar inputs)))
         (ho-es (when (and dlib ho-defs)
                  (loop for d in ho-defs for e = (find-knowledge-entry (function-definition-name d) dlib)
                        when (and e (active-knowledge-entry-p e)) collect e)))
         (dscores (make-hash-table :test #'eq)) (dpruned (make-hash-table :test #'eq)) proposals)
    (when ho-es
      (multiple-value-bind (ranked pruned)
          (evaluate-frame-descriptors frame :library dlib :seq-input-id eseq :kind :function :candidates ho-es :ledger ledger)
        (dolist (it ranked) (setf (gethash (getf it :id) dscores) it))
        (dolist (pid pruned) (setf (gethash pid dpruned) t))))
    (dolist (def ho-defs)
      (let* ((fn (function-definition-name def)) (fins (function-definition-inputs def))
             (cspec (first (code-parameters def))) (ctype (cdr cspec))
             (cvar (var cid ctype)) (fos (remove cspec fins)))
        (if (null fos)
            (unless (gethash fn dpruned)
              (let* ((dec (app (op fn) cvar)) (info (gethash fn dscores)) (ps (or (and info (getf info :score-delta)) 0)))
                (push (lifted-decomposition
                       (list :library fn) dec cid ctype (passthrough-bindings ctype inputs)
                       base-lang c-bound solver :policy-score ps
                       :provenance (when debug-p (list :origin :library-expander :function fn :decoder dec
                                                       :policy-score ps :matched-descriptors (and info (getf info :clauses)))))
                      proposals)))
            (destructuring-bind (pspec . efos) fos
              (dolist (spec avail)
                (when (equal (cdr spec) (cdr pspec))
                  (let ((pid (car spec)))
                    (multiple-value-bind (compat ps clauses)
                        (cond ((and (eql pid eseq) (null efos) (gethash fn dpruned)) (values nil most-positive-fixnum nil))
                              ((and (eql pid eseq) (null efos) (gethash fn dscores))
                               (let ((i (gethash fn dscores))) (values t (or (getf i :score-delta) 0) (getf i :clauses))))
                              (t (score-entry-by-descriptors fn frame pid :library dlib :ledger ledger :extra-fo-specs efos)))
                      (when compat
                        (dolist (et (cartesian-product-lists (mapcar (lambda (es) (candidate-fo-argument-expressions frame language pid (cdr es))) efos)))
                          (let* ((al (acons (car pspec) (var pid (cdr spec)) (mapcar #'cons (mapcar #'car efos) et)))
                                 (args (loop for s in fins collect (if (eq s cspec) cvar (cdr (assoc (car s) al :test #'eql)))))
                                 (dec (apply #'app (op fn) args))
                                 (bindings (passthrough-bindings ctype inputs (loop for a in args when (var-p a) collect (ast-id a)))))
                            (when (library-decoder-compatible-with-empty-rows-p frame pid dec cid ctype bindings ledger)
                              (push (lifted-decomposition
                                     (list* :library fn et) dec cid ctype bindings base-lang c-bound solver
                                     :slack slack :policy-score ps
                                     :provenance (when debug-p (list :origin :library-expander :function fn :decoder dec
                                                                     :bindings bindings :policy-score ps :matched-descriptors clauses)))
                                    proposals)))))))))))))
    (append (filter-map-decompositions frame base-lang defs cid c-bound solver ledger debug-p)
            (nreverse proposals)
            (partial-library-decompositions frame base-lang defs cid c-bound solver ledger)
            (learned-decoder-decompositions frame base-lang c-bound solver ledger))))

(defun expansion-bound (node)
  (or (synthesis-node-bound node) (let ((p (synthesis-node-proposal node))) (and p (decomposition-bound p)))))

(defun library-expander (&key child-language child-bound functions)
  "An `:expand` function proposing registered higher-order library combinators as `:lift-p t` decompositions."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    (library-decompositions frame language :child-language child-language
                            :child-bound (or child-bound (expansion-bound node))
                            :self-name (synthesis-job-self-name job) :functions functions
                            :solver (synthesis-job-library job) :ledger ledger :debug-p (synthesis-job-debug-p job))))

(defun combine-expanders (&rest expanders)
  "Compose multiple `:expand` functions into a single expander."
  (lambda (job node frame language h-model ledger)
    (loop for exp in expanders when exp append (funcall exp job node frame language h-model ledger))))

(defun dependency-proposals (frame language child-bound &key (features nil features-p) (include-empty-p t)
                                                             solver (debug-p *synthesis-debug-mode*))
  "Make dependency hypotheses explicit over FEATURES."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (target (schema-target schema)) (cid (next-child-id inputs))
         (base (if features-p (remove-if-not (lambda (f) (expression-respects-availability-p f schema)) features)
                   (mapcar (lambda (s) (var (car s) (cdr s))) (schema-available-inputs schema)))))
    (loop for feat in (if include-empty-p (cons nil base) base)
          collect (make-decomposition
                   :name (list :dependency feat) :decoder (var cid target) :child-id cid :child-type target
                   :bindings (when feat (list (cons 0 feat)))
                   :language (derive-language language :inputs (when feat (list (cons 0 (ast-type feat)))))
                   :bound child-bound :solver solver
                   :provenance (when debug-p (list :origin :dependency :feature feat))))))

(defun sufficient-statistic-values-p (values constrained)
  (let* ((vals (coerce values 'vector)) (n (length vals)) mapping)
    (loop for (idx . out) in constrained
          when (>= idx n) do (return-from sufficient-statistic-values-p nil)
          do (let* ((fv (aref vals idx)) (ex (assoc fv mapping :test #'equal)))
               (cond ((null ex) (push (cons fv out) mapping))
                     ((not (equal (cdr ex) out)) (return-from sufficient-statistic-values-p nil)))))
    (< 1 (length mapping) (length constrained))))

(defun feature-buckets-for-node (node frame language h-model flang fbound work-limit ledger)
  (if (and (null flang) (null fbound) h-model (heuristic-buckets h-model))
      (heuristic-buckets h-model)
      (let* ((schema (frame-schema frame)) (fl (or flang language))
             (fb (or fbound (expansion-bound node) (header-bound (schema-inputs schema) (schema-target schema) 18)))
             (obs (start-observation-search (make-observation-scope (unconstrained-frame frame (language-domain fl))
                                                                    fl :respect-availability-p t))))
        (resume-observation-search obs fb (remaining-work ledger work-limit))
        (charge ledger :feature-search (ledger-total (observation-job-ledger obs)))
        (observation-feature-buckets obs))))

(defun dependency-expander (&key feature-language feature-bound child-language child-bound
                                 (work-limit 100000) sufficient-only-p)
  "An `:expand` function discovering observational feature projections and proposing dependency frames."
  (lambda (job node frame language h-model ledger)
    (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
           (c-lang (if (and child-language (equal (language-inputs child-language) inputs)) child-language language))
           (c-bound (or child-bound (expansion-bound node) (header-bound inputs target 24))))
      (flet ((emit (feats inc-empty-p extra)
               (charge ledger :dependency-proposal (+ extra (reduce #'+ feats :key #'syntax-work :initial-value 0)))
               (dependency-proposals frame c-lang c-bound :features feats :include-empty-p inc-empty-p
                                     :solver (synthesis-job-library job) :debug-p (synthesis-job-debug-p job))))
        (if (not sufficient-only-p)
            (let ((feats (mapcar #'car (feature-buckets-for-node node frame language h-model
                                                                feature-language feature-bound work-limit ledger))))
              (emit feats t (1+ (length feats))))
            (when (and (>= (length inputs) 2) (null (synthesis-job-self-name job))
                       (not (and h-model (heuristic-exact-p h-model) (null (heuristic-unresolved-keys h-model)))))
              (let ((constrained (loop for r in (frame-rows frame) for i from 0
                                       for a = (extract-allowed-values (row-requirement r))
                                       when (and (consp a) (= 1 (length a)) (not (member :unresolved (row-known r))))
                                         collect (cons i (first a)))))
                (when (and (>= (length constrained) 3)
                           (< (length (remove-duplicates constrained :key #'cdr :test #'equal)) (length constrained)))
                  (let* ((buckets (feature-buckets-for-node node frame language h-model
                                                            feature-language feature-bound work-limit ledger))
                         (cands (stable-sort (loop for (e . v) in buckets
                                                   when (and (not (lit-p e)) (not (var-p e))
                                                             (sufficient-statistic-values-p v constrained))
                                                     collect e)
                                             #'< :key #'syntax-work))
                         (feats (subseq cands 0 (min 2 (length cands)))))
                    (when feats (emit feats nil 1)))))))))))

(defun selector-decompositions (frame language bound &key fibers dependencies (debug-p *synthesis-debug-mode*))
  (let* ((inputs (schema-inputs (frame-schema frame))) (target (schema-target (frame-schema frame)))
         (id (next-child-id inputs)))
    (append (when fibers (list (make-decomposition :name :fibers :decoder (var id target) :child-id id :child-type target
                                                   :bindings (identity-bindings inputs) :language language :bound bound
                                                   :fiber-p t :provenance (when debug-p (list :origin :fibers)))))
            (when dependencies (dependency-proposals frame language bound :debug-p debug-p)))))

(defun start-selector-search (frame language description-limit &key (fibers t) dependencies)
  "Price direct selector synthesis alongside optional fiber and dependency proposals."
  (start-synthesis frame language description-limit
                   :decompositions (selector-decompositions frame language description-limit
                                                            :fibers fibers :dependencies dependencies)))

(defun tuple-projection-decompositions (frame language bound &key solver ledger (debug-p *synthesis-debug-mode*))
  "Expose component projections `(at (var id tup-type) 'j)` for small `:tuple` inputs (`2 <= k <= 6`)."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (avail (schema-available-inputs schema)) (target (schema-target schema)))
    (when (some (lambda (s) (and (tuple-type-p (cdr s)) (<= 2 (length (rest (cdr s))) 6))) avail)
      (let ((cid (next-child-id inputs)) (nid -1) bindings)
        (dolist (spec inputs)
          (let ((id (car spec)) (tp (cdr spec)))
            (if (and (tuple-type-p tp) (assoc id avail :test #'equal) (<= 2 (length (rest tp)) 6))
                (dotimes (idx (length (rest tp))) (push (cons (incf nid) (term `(at ,(var id tp) ,idx))) bindings))
                (push (cons (incf nid) (var id tp)) bindings))))
        (setf bindings (nreverse bindings))
        (when (<= (length bindings) 12)
          (charge ledger :tuple-projection (length bindings))
          (let ((ci (binding-inputs bindings inputs)))
            (list (make-decomposition
                   :name :tuple-projection :decoder (var cid target) :child-id cid :child-type target
                   :bindings bindings :language (derive-language language :inputs ci)
                   :bound (max (or bound 0) (header-bound ci target 32)) :structural-p t :solver solver
                   :policy-score (if (tuple-type-p target) -12 -6)
                   :provenance (when debug-p (list :origin :tuple-projection :child-inputs ci))))))))))

(defun product-slot-placeholder (slot-type language)
  (or (find-if (lambda (c) (and (lit-p c) (equal slot-type (ast-type c)))) (language-constants language))
      (unless (and (code-type-p slot-type) (function-sort-p (code-sort slot-type)))
        (lit slot-type (default-value-for-type slot-type)))))

(defun product-decompositions (frame language bound &key solver ledger (debug-p *synthesis-debug-mode*))
  "Propose parallel `product-slots` decompositions for `:tuple` and Constructor-AU `:code` targets."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
         (base-cid (next-child-id inputs)) (bindings (identity-bindings inputs)) proposals)
    (flet ((slot-decomp (name cid stype slang sbound prov)
             (make-decomposition :name name :decoder (var cid stype) :child-id cid :child-type stype
                                 :bindings bindings :language slang :bound sbound :structural-p t
                                 :solver solver :provenance (when debug-p prov)))
           (accept-product (prop)
             (multiple-value-bind (sf conflict) (pullback-product-frames prop frame ledger)
               (when (and sf (null conflict)) (push prop proposals)))))
      (when (and (tuple-type-p target) (<= 2 (length (rest target)) 6))
        (let (slots children dvars (ok-p t))
          (loop for pt in (rest target) for idx from 0 for scid = (+ base-cid idx)
                for sl = (derive-language language :inputs inputs)
                for ph = (product-slot-placeholder pt sl)
                do (if (null ph) (setf ok-p nil)
                       (progn (push (list scid pt pt nil ph) slots) (push (var scid pt) dvars)
                              (push (slot-decomp (list :product-slot idx pt) scid pt sl
                                                 (max (header-bound inputs pt 64) (ceiling (* 3 (or bound 160)) 4))
                                                 (list :origin :product-slot :slot idx :slot-type pt))
                                    children))))
          (when ok-p
            (accept-product (make-decomposition
                             :name (list :tuple-product (length (rest target)))
                             :decoder (apply #'app (op :tuple target) (nreverse dvars))
                             :child-id base-cid :child-type target :bindings bindings
                             :language (derive-language language :inputs inputs)
                             :bound (or bound (header-bound inputs target 48))
                             :children (nreverse children) :product-slots (nreverse slots) :structural-p t
                             :solver solver :policy-score (if (some (lambda (s) (tuple-type-p (cdr s))) inputs) -4 -8)
                             :provenance (when debug-p (list :origin :tuple-product)))))))
      (when (and (code-type-p target) (not (function-sort-p (code-sort target))))
        (let* ((inner-in (code-inputs target)) (crows (remove-if-not #'constrained-row-p (frame-rows frame)))
               (vals (and (>= (length crows) 2) (mapcar (lambda (r) (multiple-value-list (row-singleton-value r))) crows)))
               (sources (mapcar #'first vals)))
          (when (and vals (every #'second vals) (>= (length (remove-duplicates sources :test #'equal)) 2))
            (multiple-value-bind (pattern substitutions) (anti-unify sources inner-in ledger :operator-holes-p t)
              (let ((holes (pattern-holes pattern)))
                (when (and (not (hole-p pattern)) (pattern-has-holes-p pattern) (app-p pattern) holes (<= (length holes) 6))
                  (multiple-value-bind (ctor-model raw-ctor-inputs) (compile-au-constructor pattern inner-in ledger)
                    (let (slots children ctor-subst (ok-p t))
                      (loop for (hid . raw-ct) in raw-ctor-inputs for idx from 0 for scid = (+ base-cid idx)
                            for hsort = (code-sort raw-ct) for fn-p = (function-sort-p hsort)
                            for all-lit-p = (and (not fn-p) (every (lambda (s) (lit-p (cdr (assoc hid s)))) substitutions))
                            for stype = (if all-lit-p hsort raw-ct)
                            for sl = (if all-lit-p (derive-language language :inputs inputs)
                                         (code-slot-child-language language stype :inputs inputs :require-consts-p fn-p))
                            for ph = (and sl (product-slot-placeholder stype sl))
                            do (if (or (null sl) (null ph)) (setf ok-p nil)
                                   (progn (push (cons hid (code-hole-decoder-arg scid hsort raw-ct all-lit-p)) ctor-subst)
                                          (push (list scid stype raw-ct all-lit-p ph) slots)
                                          (push (slot-decomp (list :au-slot idx stype) scid stype sl
                                                             (max (header-bound inputs stype 64) (ceiling (* 3 (or bound 140)) 4))
                                                             (list :origin :constructor-au-slot :hole hid :slot-type stype))
                                                children))))
                      (when ok-p
                        (accept-product (make-decomposition
                                         :name (list :constructor-au pattern)
                                         :decoder (instantiate ctor-model (nreverse ctor-subst) :var)
                                         :child-id base-cid :child-type target :bindings bindings
                                         :language (derive-language language :inputs inputs)
                                         :bound (or bound (header-bound inputs target 48))
                                         :children (nreverse children) :product-slots (nreverse slots)
                                         :product-pattern pattern :structural-p t :solver solver :policy-score -10
                                         :provenance (when debug-p (list :origin :constructor-au :pattern pattern)))))))))))))
      (nreverse proposals))))

(defun product-expander (&key child-bound)
  "An `:expand` function proposing tuple projections and parallel `product-slots` decompositions."
  (lambda (job node frame language h-model ledger)
    (declare (ignore h-model))
    (let* ((bound (or child-bound (expansion-bound node))) (solver (synthesis-job-library job))
           (debug-p (synthesis-job-debug-p job)) (schema (frame-schema frame))
           (inputs (schema-inputs schema)) (target (schema-target schema))
           (products (product-decompositions frame language bound :solver solver :ledger ledger :debug-p debug-p))
           (skip-proj-p (or (and (tuple-type-p target)
                                 (find-if (lambda (p) (and (consp (decomposition-name p))
                                                           (eq :tuple-product (first (decomposition-name p)))))
                                          products))
                            (and (or (seq-type-p target) (code-type-p target))
                                 (not (some (lambda (s)
                                              (and (tuple-type-p (cdr s))
                                                   (some (lambda (et) (or (seq-type-p et) (code-type-p et)
                                                                          (tuple-type-p et) (equal et target)))
                                                         (rest (cdr s)))))
                                            inputs))))))
      (append (unless skip-proj-p
                (tuple-projection-decompositions frame language bound :solver solver :ledger ledger :debug-p debug-p))
              products))))

(defun heuristic-expander (&key child-language guard-language child-bound guard-bound
                                (work-limit 20000) (additive-p t) (conditional-p t)
                                (library-proposals-p t) library-functions (dependency-proposals-p t))
  "Compose product, library, dependency, and Stage A/B heuristic expanders."
  (combine-expanders
   (product-expander :child-bound child-bound)
   (when library-proposals-p
     (library-expander :child-language child-language :child-bound child-bound :functions library-functions))
   (when dependency-proposals-p
     (dependency-expander :child-language child-language :child-bound child-bound
                          :work-limit work-limit :sufficient-only-p (not (eq dependency-proposals-p :all))))
   (lambda (job node frame language h-model ledger)
     (let ((inputs (schema-inputs (frame-schema frame))) (bound (expansion-bound node)))
       (flet ((matching (lang)
                (and lang (not (node-under-product-slot-p node)) (equal (language-inputs lang) inputs) lang)))
         (heuristic-decompositions frame language :heuristic-model h-model
                                   :child-language (matching child-language) :guard-language (matching guard-language)
                                   :description-limit bound :child-bound (or child-bound bound) :guard-bound guard-bound
                                   :work-limit work-limit :run-weight (synthesis-job-run-weight job)
                                   :additive-p additive-p :conditional-p conditional-p
                                   :self-name (synthesis-job-self-name job) :solver (synthesis-job-library job)
                                   :ledger ledger :debug-p (synthesis-job-debug-p job)))))))

(defparameter *library-code-argument-bits* 20)
(defparameter *library-code-argument-work* 1000)
(defparameter *library-partial-proposal-limit* 256)

(defun map-cartesian-options (options function)
  (labels ((visit (rem rev)
             (if (null rem) (funcall function (reverse rev))
                 (dolist (v (first rem)) (visit (rest rem) (cons v rev))))))
    (visit options nil)))

(defun library-code-argument-candidates (type language ledger)
  (let* ((cursor (make-enumerator (derive-language language :inputs (code-inputs type))))
         (cands (remove-if-not (lambda (c) (equal type (ast-type c))) (copy-list (language-constants language)))))
    (loop repeat *library-code-argument-work* while (<= (enumerator-size cursor) *library-code-argument-bits*)
          do (charge ledger :template-enumeration)
             (multiple-value-bind (expr ev) (enumeration-step cursor)
               (when (eq ev :candidate)
                 (index-expression cursor expr)
                 (when (equal (ast-type expr) (code-sort type)) (pushnew (lit type expr) cands :test #'equal)))))
    (nreverse cands)))

(defun partial-library-decompositions (frame language definitions child-id bound solver ledger)
  (let ((inputs (schema-inputs (frame-schema frame))) (target (schema-target (frame-schema frame)))
        (cache (make-hash-table :test #'equal)) proposals)
    (dolist (def definitions (nreverse proposals))
      (let* ((name (function-definition-name def)) (specs (function-definition-inputs def))
             (codes (code-parameters def)) (primary (find-if-not #'code-type-p specs :key #'cdr)))
        (when (and (equal target (function-definition-return-type def))
                   (or (> (length codes) 1) (and primary (not (find (cdr primary) inputs :key #'cdr :test #'equal)))))
          (dolist (sel codes)
            (let* ((ct (cdr sel)) (bnds (passthrough-bindings ct inputs))
                   (opts (loop for s in specs
                               collect (cond ((eq s sel) (list (var child-id ct)))
                                             ((code-type-p (cdr s))
                                              (or (gethash (cdr s) cache)
                                                  (setf (gethash (cdr s) cache) (library-code-argument-candidates (cdr s) language ledger))))
                                             (t (candidate-fo-argument-expressions frame language nil (cdr s)))))))
              (map-cartesian-options opts
               (lambda (args)
                 (when (>= (length proposals) *library-partial-proposal-limit*)
                   (return-from partial-library-decompositions (nreverse proposals)))
                 (let ((dec (apply #'app (op name) args)))
                   (charge ledger :template-construction (syntax-work dec))
                   (push (lifted-decomposition (list :library-partial name (car sel) args)
                                               dec child-id ct bnds language bound solver
                                               :slack 24 :fallback-p t :policy-score *partial-application-policy-score*)
                         proposals)))))))))))

(defun reactivate-or-register-entry (existing elib make-fn ledger)
  (cond ((and existing (not (active-knowledge-entry-p existing)))
         (setf (knowledge-entry-active-p existing) t
               (knowledge-entry-last-used-epoch existing) (knowledge-library-epoch elib))
         (invalidate-knowledge-caches elib) existing)
        (existing existing)
        (t (register-knowledge-entry (funcall make-fn) :library elib :ledger ledger))))

(define-knowledge-kind :decoder-template
  (:priority 40)
  (:validate (entry library) (declare (ignore library)) (assert-entry-expression-type entry))
  (:install (entry library ledger) (declare (ignore ledger))
    (when (and (active-knowledge-entry-p entry) (null (knowledge-entry-descriptor-profile entry)))
      (compute-entry-descriptor-profile entry library))))

(defun remember-decoder-template (proposal parent-inputs &key (library *knowledge-library*) ledger work)
  "Store an observed decomposition as typed `:decoder-template` syntax."
  (when (and proposal (not (decomposition-product-slots proposal))
             (member (decomposition-child-id proposal) (free-vars (decomposition-decoder proposal)) :test #'eql))
    (let* ((cid (decomposition-child-id proposal)) (ctype (decomposition-child-type proposal))
           (inputs (acons cid ctype parent-inputs)) (expr (decomposition-decoder proposal))
           (bindings (mapcar (lambda (b) (cons (car b) (ast->sexp (cdr b)))) (decomposition-bindings proposal)))
           (existing (find-if (lambda (e) (and (equal inputs (knowledge-entry-inputs e))
                                               (equal expr (knowledge-entry-expression e))
                                               (equal bindings (getf (knowledge-entry-metadata e) :bindings))))
                              (knowledge-entries-of-kind :decoder-template library))))
      (reactivate-or-register-entry
       existing library
       (lambda ()
         (make-knowledge-entry
          :kind :decoder-template :inputs inputs :target (ast-type expr) :expression expr
          :work (or work 0) :status :empirical
          :metadata (list :origin :observed-decomposition :child-id cid
                          :dependencies (expression-dependencies (cons expr (mapcar #'cdr (decomposition-bindings proposal))))
                          :lift-p (decomposition-lift-p proposal) :bindings bindings)
          :library library))
       ledger))))

(defun learned-decoder-decompositions (frame language bound solver ledger)
  "Retrieve stored typed contexts and single-hole syntactic AU generalizations."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema))
         (avail (schema-available-inputs schema)) (target (schema-target schema))
         (cid (next-child-id inputs))
         (seq-in-id (or (car (find-if #'seq-type-p avail :key #'cdr)) (caar avail) (caar inputs)))
         (seen (make-hash-table :test #'equal)) (au-groups (make-hash-table :test #'equal))
         (dlib (or (and (knowledge-library-p solver) solver) *knowledge-library*))
         (dscores (make-hash-table :test #'eq))
         (ranked (when (and dlib (active-knowledge-entries-of-kind :decoder-template dlib))
                   (loop for it in (evaluate-frame-descriptors frame :library dlib :seq-input-id seq-in-id
                                                               :kind :decoder-template :ledger ledger)
                         for e = (getf it :entry)
                         do (setf (gethash e dscores) (or (getf it :score-delta) 0)) collect e)))
         proposals)
    (labels ((param-opts (params)
               (mapcar (lambda (p) (loop for (id . tp) in avail when (equal tp (cdr p)) collect (var id tp))) params))
             (emit (name dec ct bnds lift-p ps)
               (let ((sig (list dec ct bnds lift-p)))
                 (unless (gethash sig seen)
                   (setf (gethash sig seen) t)
                   (push (lifted-decomposition name dec cid ct bnds language bound solver
                                               :lift-p lift-p :slack 24 :fallback-p t :policy-score ps)
                         proposals))))
             (try-tpl (name tpl ct tcid params raw-bnds lift-p ps fb-bnds)
               (map-cartesian-options (param-opts params)
                (lambda (args)
                  (when (>= (length proposals) *library-partial-proposal-limit*)
                    (return-from learned-decoder-decompositions (nreverse proposals)))
                  (let* ((sub (acons tcid (var cid ct) (mapcar #'cons (mapcar #'car params) args)))
                         (dec (instantiate tpl sub :var))
                         (bnds (if raw-bnds (mapcar (lambda (b) (cons (car b) (instantiate (sexp->ast (cdr b)) sub :var))) raw-bnds)
                                   fb-bnds)))
                    (charge ledger :template-retrieval (syntax-work dec))
                    (when (ignore-errors (expression-type dec (acons cid ct inputs)))
                      (emit name dec ct bnds lift-p ps)))))))
      (dolist (entry ranked)
        (let* ((meta (knowledge-entry-metadata entry)) (ocid (getf meta :child-id))
               (ct (cdr (assoc ocid (knowledge-entry-inputs entry))))
               (params (remove ocid (knowledge-entry-inputs entry) :key #'car)))
          (when (and ct (equal target (knowledge-entry-target entry))
                     (equalp (getf meta :dependencies)
                             (expression-dependencies (loop for d in (getf meta :dependencies)
                                                            when (defined-function-p (first d)) collect (op (first d))))))
            (let* ((sp (stable-sort (copy-list params) #'string< :key (lambda (p) (prin1-to-string (cdr p)))))
                   (np (loop for (nil . pt) in sp for nid from 1 collect (cons nid pt)))
                   (ns (acons ocid (var 0 ct) (loop for (oid . ot) in sp for (nid . nil) in np collect (cons oid (var nid ot))))))
              (push (list entry np (instantiate (knowledge-entry-expression entry) ns :var))
                    (gethash (list (getf meta :lift-p) ct (mapcar #'cdr np)) au-groups)))
            (try-tpl (list :learned-template (knowledge-entry-id entry))
                     (knowledge-entry-expression entry) ct ocid params (getf meta :bindings)
                     (getf meta :lift-p) (+ *learned-template-policy-score* (gethash entry dscores 0)) nil))))
      (maphash
       (lambda (gkey group)
         (when (>= (length group) 2)
           (let* ((ord (reverse group)) (np (second (first ord))) (exprs (mapcar #'third ord)))
             (when (>= (length (remove-duplicates exprs :test #'equal)) 2)
               (let* ((pat (nth-value 0 (anti-unify exprs (acons 0 (second gkey) np) ledger :operator-holes-p nil)))
                      (holes (pattern-holes pat)))
                 (when (and (not (hole-p pat)) (= 1 (length holes)) (not (member 0 (free-vars pat) :test #'eql)))
                   (let ((nct (cdr (first holes))))
                     (when (valid-type-p nct)
                       (let ((gen (instantiate pat (list (cons (caar holes) (var 0 nct))) :hole)))
                         (unless (var-p gen)
                           (try-tpl (list :learned-template-au (mapcar (lambda (g) (knowledge-entry-id (first g))) ord))
                                    gen nct 0 np nil nil (- *learned-template-policy-score* 3)
                                    (identity-bindings inputs))))))))))))
       au-groups)
      (nreverse proposals))))

(defun remember-successful-decompositions (job library ledger)
  (let* ((best (synthesis-job-best job))
         (msg (find-if (lambda (m) (and (eq :candidate (message-claim m)) (eq best (getf (message-evidence m) :candidate))))
                       (synthesis-job-messages job)))
         (node (and msg (find (message-call-id msg) (synthesis-job-nodes job) :key #'synthesis-node-id)))
         entries)
    (loop while (and node (synthesis-node-parent node))
          do (let* ((parent (synthesis-node-parent node))
                    (e (remember-decoder-template (synthesis-node-proposal node)
                                                   (schema-inputs (frame-schema (synthesis-node-frame parent)))
                                                   :library library :ledger ledger :work (ledger-total (synthesis-job-ledger job)))))
               (when e (push e entries)) (setf node parent)))
    entries))

;;; Order-invariant `sort-by(k(X))` Topology & `:locality-key` Induction

(define-knowledge-kind :locality-key
  (:priority 55)
  (:validate (entry library) (declare (ignore library))
    (assert-entry-expression-type entry) (assert (eq :int (knowledge-entry-target entry)))))

(defun register-knowledge-locality-key (expr inputs &key id (library *knowledge-library*) domain gain metadata ledger)
  "Idempotently register canonical `:int` sorting key EXPR over INPUTS as `:locality-key`."
  (let* ((elib (or library *knowledge-library*)) (ein (copy-tree inputs))
         (edom (or domain (infer-domain-from-types (cons :int (mapcar #'cdr ein)))))
         (existing (find-if (lambda (e) (and (equal edom (knowledge-entry-domain e))
                                             (equal ein (knowledge-entry-inputs e))
                                             (equal expr (knowledge-entry-expression e))))
                            (knowledge-entries-of-kind :locality-key elib))))
    (reactivate-or-register-entry
     existing elib
     (lambda ()
       (make-knowledge-entry
        :id id :kind :locality-key :domain edom :inputs ein :target :int :expression expr
        :status :empirical :gain (or gain 0) :metadata (copy-tree metadata) :library elib
        :bits (if (every (lambda (s) (integerp (car s))) ein) (description-size expr ein) (syntax-work expr))))
     ledger)))

(defun induce-sort-by-topology (frame &key h-model buckets (library *knowledge-library*) (register-p t) ledger)
  "Discover an order-invariant `sort-by(k(X))` chain over resolved singleton rows of FRAME."
  (when (or (frame-edges frame) (< (length (frame-rows frame)) 3))
    (return-from induce-sort-by-topology (values frame nil nil)))
  (let* ((rows (coerce (frame-rows frame) 'vector)) (n-rows (length rows))
         (schema (frame-schema frame)) (inputs (schema-inputs schema))
         (avail (schema-available-inputs schema)) (target (schema-target schema))
         (metric (frame-metric frame)) (elib (or library *knowledge-library*))
         (raw-elig (loop for i below n-rows for r = (aref rows i)
                         for (val ok) = (unless (member :unresolved (row-known r)) (multiple-value-list (row-singleton-value r)))
                         when ok collect (list i r val (prin1-to-string
                                                         (list (loop for v in (row-known r) for (nil . tp) in inputs
                                                                     collect (ast->sexp (lit tp v)))
                                                               (ast->sexp (row-requirement r)) (row-key r)))))))
    (when (< (length raw-elig) 3) (return-from induce-sort-by-topology (values frame nil nil)))
    (let* ((ce (coerce (sort (copy-list raw-elig) #'string< :key #'fourth) 'vector))
           (m (length ce)) (tpbits 0)
           (rbuckets (or buckets (and h-model (heuristic-buckets h-model))))
           (int-id-p (every (lambda (s) (integerp (car s))) inputs))
           cands has-bucket-p)
      (when (< (length (remove-duplicates (map 'list #'third ce) :test #'equal)) 2)
        (return-from induce-sort-by-topology (values frame nil nil)))
      (dotimes (u m)
        (dotimes (v m)
          (unless (= u v)
            (incf tpbits (correction-bit-size (third (aref ce u)) (third (aref ce v)) target t metric elib ledger)))))
      (labels ((add-c (expr vec &optional bp)
                 (when (and (= (length vec) m) (loop for x across vec always (integerp x))
                            (>= (length (remove-duplicates (coerce vec 'list) :test #'eql)) 2))
                   (when bp (setf has-bucket-p t))
                   (push (list expr vec (if int-id-p (description-size expr inputs) (syntax-work expr))
                               (prin1-to-string (ast->sexp expr)))
                         cands)))
               (ev-c (expr)
                 (let ((vs (loop for j below m for run = (evaluate expr inputs (row-known (second (aref ce j))) :ledger ledger)
                                 while (eq :value (evaluation-status run)) collect (evaluation-value run))))
                   (when (= (length vs) m) (add-c expr (coerce vs 'vector))))))
        (dolist (e rbuckets)
          (when (and (eq :int (ast-type (car e))) (= (length (cdr e)) n-rows)
                     (expression-respects-availability-p (car e) schema))
            (let ((rv (coerce (cdr e) 'vector)))
              (add-c (car e) (coerce (loop for j below m collect (aref rv (first (aref ce j)))) 'vector) t))))
        (dolist (s avail)
          (when (eq :int (cdr s))
            (let ((pos (position (car s) inputs :key #'car :test #'equal)))
              (add-c (var (car s) :int) (coerce (loop for j below m collect (nth pos (row-known (second (aref ce j))))) 'vector)))))
        (unless has-bucket-p
          (dolist (s avail)
            (let ((id (car s)) (tp (cdr s)))
              (when (and (tuple-type-p tp) (<= (length (rest tp)) 6))
                (loop for et in (rest tp) for k from 0 when (eq :int et) do (ev-c (term `(at ,(var id tp) ,k)))))
              (when (seq-type-p tp)
                (ev-c (term `(length ,(var id tp))))
                (when (eq :int (second tp)) (ev-c (term `(at ,(var id tp) 0)))))))))
      (setf cands (sort cands (lambda (a b) (or (< (third a) (third b))
                                                (and (= (third a) (third b)) (string< (fourth a) (fourth b)))))))
      (let ((uvecs (make-hash-table :test #'equal)) ucands best btot bksize bsrepr bsorted)
        (dolist (c cands) (let ((vl (coerce (second c) 'list)))
                            (unless (gethash vl uvecs) (setf (gethash vl uvecs) t) (push c ucands))))
        (dolist (c (nreverse ucands))
          (destructuring-bind (expr kvec ksize srepr) c
            (charge ledger :topology-induction 1)
            (let* ((idxs (sort (loop for i below m collect i)
                               (lambda (a b) (let ((ka (aref kvec a)) (kb (aref kvec b)))
                                               (or (< ka kb) (and (= ka kb) (< a b)))))))
                   (cbits (loop for (i j) on idxs while j
                                sum (correction-bit-size (third (aref ce i)) (third (aref ce j)) target t metric elib ledger)))
                   (tot (+ cbits ksize)))
              (when (and (< (* m tot) tpbits)
                         (or (null best) (< tot btot)
                             (and (= tot btot) (or (< ksize bksize) (and (= ksize bksize) (string< srepr bsrepr))))))
                (setf best expr btot tot bksize ksize bsrepr srepr bsorted idxs)))))
        (if (null best) (values frame nil nil)
            (let* ((srows (mapcar (lambda (i) (second (aref ce i))) bsorted))
                   (sys (mapcar (lambda (i) (third (aref ce i))) bsorted))
                   (pedges (loop for (r1 r2) on srows while r2 collect (list :persistence (row-key r1) (row-key r2))))
                   (anchor (loop for ra in srows for ya in sys
                                 thereis (loop for rb in (reverse srows) for yb in (reverse sys)
                                               unless (equal ya yb) return (list :distinct (row-key ra) (row-key rb)))))
                   (lk (when (and register-p elib)
                         (register-knowledge-locality-key
                          best inputs :library elib :domain (schema-domain schema)
                          :gain (- (floor tpbits m) btot) :metadata (list :origin :sort-by-topology) :ledger ledger))))
              (values (derive-frame frame :edges (append pedges (when anchor (list anchor)))) best lk)))))))
