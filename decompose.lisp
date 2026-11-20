(in-package #:lisploop)

;;; Stage B: residual decompositions of a Stage A model, and the heuristic and recursive entry points.

;;; Stage A -> Stage B Residual Pullback Decompositions & Heuristic Synthesis
(defun additive-residual-type-p (type)
  "True when TYPE supports additive displacement decoders (:int, (:gf p), or tuples thereof)."
  (or (eq type :int)
      (gf-type-p type)
      (and (tuple-type-p type)
           (every #'additive-residual-type-p (rest type)))))

(defun make-additive-residual-decoder (base-expr residual-var type)
  "Construct outer decoder d(X, Z) = base(X) + Z for scalar or tuple TYPE."
  (assert (additive-residual-type-p type) () "Unsupported additive residual type ~S" type)
  (if (tuple-type-p type)
      (apply #'app (op :tuple type)
             (loop for part-type in (rest type)
                   for idx from 0
                   collect (make-additive-residual-decoder
                            (app (op :at type) base-expr (lit :int idx))
                            (app (op :at type) residual-var (lit :int idx))
                            part-type)))
      (app (op :+ type) base-expr residual-var)))

(defun make-metric-residual-decoder (operator base-expr residual-var)
  "Construct outer decoder d(X, Z) = OPERATOR(base(X), Z) for a metric decoder of the library."
  (app operator base-expr residual-var))

(defun metric-residual-decompositions (frame program residual language bound solver ledger debug-p
                                       &key packets)
  "Stage B for the library's metric decoders: for each decoder d of the target type that
describes the witness of some row in RESIDUAL, ((row-key . witness) ...), from what PROGRAM
predicts there, propose Y = d(PROGRAM(X), Z). PACKETS, when supplied from `heuristic-packets`,
lets Stage B recognize cached `(:metric-decoder ...)` hits from Stage A without re-evaluating
`metric-delta` in the VM. The child predicts the delta; the decoder's own solver, added to
SOLVER, turns each pulled-back requirement into the delta it replays, and where it has none
the requirement stays as it is."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (child-id (next-child-id inputs))
         (slack (max 18 (- bound (header-size inputs target))))
         (proposals nil))
    (dolist (decoder (metric-decoders target) (nreverse proposals))
      (destructuring-bind (operator entry tag-bits delta-type) decoder
        (declare (ignore tag-bits))
        (let* ((op-sexp (ast->sexp operator))
               (cached-hit-p
                 (and packets
                      (some (lambda (row)
                              (let* ((key (row-key row))
                                     (pkt (cdr (assoc key packets :test #'equal))))
                                (and (consp pkt)
                                     (eq :metric-decoder (first pkt))
                                     (equal (second pkt) op-sexp)
                                     (assoc key residual :test #'equal))))
                            (frame-rows frame)))))
          (when (and (not (and (eq :+ (operator-name operator)) (additive-residual-type-p target)))
                     (or cached-hit-p
                         (some (lambda (row)
                                 (let ((miss (assoc (row-key row) residual :test #'equal)))
                                   (and miss
                                        (multiple-value-bind (predicted ok)
                                            (eval-expr-value program inputs (row-known row) ledger)
                                          (and ok (metric-delta decoder predicted (cdr miss) target ledger))))))
                               (frame-rows frame))))
            (push (make-decomposition
                   :name (list :heuristic-metric (operator-name operator) program)
                   :decoder (make-metric-residual-decoder operator program (var child-id delta-type))
                   :child-id child-id
                   :child-type delta-type
                   :bindings (identity-bindings inputs)
                   :language language
                   :bound (header-bound inputs delta-type slack)
                   :solver (as-propagator-library (list solver (metric-decoder-library decoder)))
                   :provenance (when debug-p
                                 (list :origin :stage-b-metric
                                       :base-program program
                                       :decoder (operator-name operator)
                                       :solver (knowledge-entry-id entry))))
                  proposals)))))))

(defun row-active-for-guard-p (row heuristic-model)
  "True when ROW is a constrained row whose outcome under HEURISTIC-MODEL is resolved,
or when HEURISTIC-MODEL has no concrete residuals and ROW is an unresolved constrained row."
  (and (constrained-row-p row)
       (or (null (heuristic-residual heuristic-model))
           (not (member (row-key row) (heuristic-unresolved-keys heuristic-model) :test #'equal)))))

(defun heuristic-hit-mask (frame heuristic-model)
  "Return the per-row Boolean hit mask (T on satisfied rows, NIL on unary residual rows)."
  (let ((residuals (heuristic-residual heuristic-model))
        (unresolved (heuristic-unresolved-keys heuristic-model)))
    (loop for row in (frame-rows frame)
          for key = (row-key row)
          collect (if residuals
                      (null (assoc key residuals :test #'equal))
                      (not (member key unresolved :test #'equal))))))

(defun default-guard-language (frame language)
  "Construct a Boolean guard language over FRAME's inputs for exception-patching."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (domain (language-domain language))
         (eq-ops (cons (op := domain) (mapcar (lambda (spec) (op := (cdr spec))) inputs)))
         (lt-ops (remove-if-not (lambda (o)
                                  (and (operator-p o) (eq :< (operator-name o))))
                                (language-operators language)))
         (domain-ops (remove-if (lambda (o)
                                  (and (operator-p o)
                                       (or (member (operator-name o) '(:= :< :if))
                                           (and (eq :tuple (operator-name o))
                                                (not (language-operator-p language :at))))))
                                (language-operators language)))
         (seq-empty-constants
           (loop for (nil . type) in inputs
                 when (seq-type-p type)
                   collect (lit type '()))))
    (make-language domain inputs
                   :operators (remove-duplicates (append eq-ops lt-ops (list (op :if :bool)) domain-ops)
                                                 :test #'equal)
                   :literals (if (listp (language-literals language))
                                 (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                                 (language-literals language))
                   :constants (remove-duplicates (append seq-empty-constants (language-constants language))
                                                 :test #'equal))))

(defun observed-predicates (frame language bound work-limit ledger)
  "Search LANGUAGE observationally over FRAME's rows, up to BOUND bits and WORK-LIMIT work
charged to LEDGER as guard search, plus direct 1-step `:bool` `:code-eval` predicates over
FRAME's variables when admitted by LANGUAGE. Returns ((expression . row-values) ...)."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (rows (frame-rows frame))
         (direct-code-preds
           (loop for o in (language-operators language)
                 when (and (operator-p o)
                           (eq :code-eval (operator-name o))
                           (eq :bool (third (operator-type o))))
                   append (let* ((arg-types (second (operator-type o)))
                                 (choices (mapcar (lambda (atype)
                                                    (loop for (id . itype) in inputs
                                                          when (equal itype atype)
                                                            collect (var id itype)))
                                                  arg-types)))
                            (when (every #'consp choices)
                              (loop for args in (cartesian-product-lists choices)
                                    for expr = (apply #'app o args)
                                    for vals = (loop for r in rows
                                                     for run = (evaluate expr inputs (row-known r)
                                                                         :ledger ledger)
                                                     when (eq :value (evaluation-status run))
                                                       collect (evaluation-value run))
                                    when (= (length vals) (length rows))
                                      collect (cons expr vals))))))
         (obs (start-observation-search (make-observation-scope frame language)))
         (obs-before (ledger-total (observation-job-ledger obs))))
    (resume-observation-search obs bound work-limit)
    (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) obs-before))
    (append direct-code-preds
            (loop for bucket in (observation-job-buckets obs)
                  when (eq :bool (observation-bucket-type bucket))
                    collect (cons (observed-expression-expression
                                   (car (last (observation-bucket-members bucket))))
                                  (observation-bucket-values bucket))))))

(defparameter *feature-guard-bits* 54
  "Body-bit bound on a guard that compares two features: room for one measure of an input
against one of another, as two lengths are.")

(defun language-admits-expression-p (expression language)
  "True when EXPRESSION is written in LANGUAGE: over its inputs, with its operators, and with
literals that are its constants or, in its domain, among its literals when it lists any."
  (let ((inputs (language-inputs language))
        (literals (language-literals language))
        (domain (language-domain language)))
    (labels ((admitted-p (node)
               (ecase (ast-kind node)
                 (:var (and (member (cons (ast-id node) (ast-type node)) inputs :test #'equal) t))
                 (:lit (or (and (member node (language-constants language) :test #'equal) t)
                           (and (equal (ast-type node) domain)
                                (or (not (listp literals))
                                    (and (member (ast-value node) literals :test #'equal) t)))))
                 (:app (and (member (first node) (language-operators language) :test #'equal)
                            (every #'admitted-p (rest node)))))))
      (admitted-p expression))))

(defun feature-pair-predicates (buckets inputs row-count bound ledger &optional guard-language)
  "Comparisons of two Stage A features as guard candidates ((expression . row-values) ...):
`=` of two features of one type and `<` of two integer features either way, of at most
BOUND body bits and, when GUARD-LANGUAGE is supplied, written in it
(`language-admits-expression-p`): its comparison at the features' type over features of its
own. BUCKETS, ((expression . row-values) ...), already hold every feature's value on each of
the ROW-COUNT rows, so a comparison is priced by one unit of guard search and no expression
is evaluated."
  (let* ((features (loop for (expression . values) in buckets
                         when (= row-count (length values))
                           collect (list expression (ast-type expression)
                                         (body-size expression inputs) values)))
         (predicates nil))
    (flet ((offer (predicate values)
             (charge ledger :guard-search)
             (when (and (<= (body-size predicate inputs) bound)
                        (or (null guard-language)
                            (language-admits-expression-p predicate guard-language)))
               (push (cons predicate values) predicates))))
      (loop for ((left left-type left-bits left-values) . others) on features do
        (loop for (right right-type right-bits right-values) in others
              ;; A comparison costs more than its operands; one of two literals says nothing.
              when (and (equal left-type right-type)
                        (< (+ left-bits right-bits) bound)
                        (not (and (lit-p left) (lit-p right)))) do
                (offer (term `(= ,left ,right)) (mapcar #'equal left-values right-values))
                (when (and (eq :int left-type)
                           (every #'integerp left-values) (every #'integerp right-values))
                  (offer (term `(< ,left ,right)) (mapcar #'< left-values right-values))
                  (offer (term `(< ,right ,left)) (mapcar #'< right-values left-values))))))
    (nreverse predicates)))

(defun domain-feature-buckets (frame language work-limit ledger)
  "The behaviours on FRAME's rows of the small expressions of LANGUAGE's domain type that
involve no conditional, as ((expression . row-values) ...), oldest first: features for
`feature-pair-predicates` to compare. The search is charged to LEDGER as guard search, up to
WORK-LIMIT."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (domain (language-domain language))
         (rows (frame-rows frame))
         (atomic (derive-language
                  language
                  :operators (remove-if (lambda (o) (and (operator-p o) (eq :if (operator-name o))))
                                        (language-operators language))))
         (obs (start-observation-search
               (make-observation-scope (probe-frame domain inputs (mapcar #'row-known rows)) atomic))))
    (resume-observation-search obs (header-bound inputs domain 28) work-limit)
    (charge ledger :guard-search (ledger-total (observation-job-ledger obs)))
    (loop for bucket in (reverse (observation-job-buckets obs))
          when (= (length rows) (length (observation-bucket-values bucket)))
            collect (cons (observed-expression-expression (car (last (observation-bucket-members bucket))))
                          (observation-bucket-values bucket)))))

(defun find-sound-exception-guard (frame hit-mask guard-language guard-bound work-limit ledger
                                   &key active-mask buckets (feature-bound *feature-guard-bits*))
  "Synthesize a Boolean guard G(X) separating hit and miss rows.
Returns (VALUES guard invert-p): when INVERT-P is NIL, G(X) is T only on hits; when
INVERT-P is T, G(X) is NIL only on hits. Guards are grouped observationally; the most
covering sound one wins (an exact separator covers every hit), then the shortest.
When the guard grammar holds no exact separator within GUARD-BOUND, the comparisons of two
of the Stage A features in BUCKETS compete too, up to FEATURE-BOUND body bits
(`feature-pair-predicates`). A frame whose target is Boolean has Boolean Stage A features,
which no comparison is made of; when BUCKETS hold none of GUARD-LANGUAGE's domain type, a
third of WORK-LIMIT goes to observing some (`domain-feature-buckets`)."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (rows (frame-rows frame))
         (domain (language-domain guard-language))
         (feature-work (if (and (eq :bool (schema-target (frame-schema frame)))
                                (notany (lambda (bucket) (equal domain (ast-type (car bucket)))) buckets)
                                (notany (lambda (row) (member :unresolved (row-known row))) rows))
                           (floor work-limit 3)
                           0))
         (buckets (if (plusp feature-work)
                      (append buckets (domain-feature-buckets frame guard-language feature-work ledger))
                      buckets))
         (work-limit (max 1 (- work-limit feature-work)))
         (eff-active (or active-mask
                         (let ((constrained (mapcar #'constrained-row-p rows)))
                           (if (some #'identity constrained)
                               constrained
                               (make-list (length rows) :initial-element t)))))
         (all-active-p (every #'identity eff-active))
         (active-rows (if all-active-p
                          rows
                          (loop for r in rows for a in eff-active when a collect r)))
         (active-hit-mask (if all-active-p
                              hit-mask
                              (loop for h in hit-mask for a in eff-active when a collect h)))
         (active-frame (if all-active-p
                           frame
                           (derive-frame frame :rows active-rows :pairs nil :anchors nil :edges nil)))
         (input-buckets (when active-rows
                          (loop for (id . type) in inputs
                                for pos from 0
                                for vals = (mapcar (lambda (r) (nth pos (row-known r))) active-rows)
                                unless (member :unresolved vals)
                                  collect (cons (var id type) vals))))
         (active-buckets (append input-buckets
                                 (if (or (null buckets) all-active-p)
                                     buckets
                                     (loop for (expr . vals) in buckets
                                           when (= (length vals) (length rows))
                                             collect (cons expr
                                                           (loop for v in vals for a in eff-active
                                                                 when a collect v))))))
         (predicates (if active-rows
                         (observed-predicates (support-frame active-frame active-hit-mask ledger)
                                              guard-language guard-bound work-limit ledger)
                         nil))
         (active-hits (count t active-hit-mask)))
    (labels ((sound-guard (expr vals)
               ;; (expr invert-p covered-hits bits) when EXPR, in one polarity, holds on hits only.
               (let ((sound-hit-p t) (sound-miss-p t) (hits 0) (inv-hits 0))
                 (loop for v in vals for h in active-hit-mask do
                   (if h (if v (incf hits) (incf inv-hits))
                       (if v (setf sound-hit-p nil) (setf sound-miss-p nil))))
                 (when (or (and sound-hit-p (plusp hits)) (and sound-miss-p (plusp inv-hits)))
                   (let ((use-inv-p (and sound-miss-p (or (not sound-hit-p) (> inv-hits hits)))))
                     (list expr use-inv-p (if use-inv-p inv-hits hits) (description-size expr inputs))))))
             (best-guard (candidates)
               (best-by (loop for (expr . vals) in candidates
                              for guard = (sound-guard expr vals)
                              when guard collect guard)
                        (list :desc #'third) #'fourth)))
      (let ((best (best-guard predicates)))
        (when (and active-buckets active-rows (not (and best (= active-hits (third best)))))
          (setf best (best-by (remove nil (list best
                                                (best-guard (feature-pair-predicates
                                                             active-buckets inputs (length active-rows)
                                                             feature-bound ledger guard-language))))
                              (list :desc #'third) #'fourth)))
        (values (first best) (second best))))))

(defun find-oracle-operator-name (language)
  "Return the operator name of any oracle-backed function in LANGUAGE, or NIL."
  (loop for o in (language-operators language)
        when (operator-p o) do
          (let ((def (find-function-definition (operator-name o))))
            (when (and def (function-definition-oracle-table def))
              (return (operator-name o))))))

(defun model-satisfies-empty-sequence-rows-p (frame hit-mask)
  "True when HIT-MASK is T on every constrained row where some sequence input Xi is '()."
  (let ((inputs (schema-inputs (frame-schema frame)))
        (rows (frame-rows frame)))
    (loop for (nil . type) in inputs
          for pos from 0
          thereis (and (seq-type-p type)
                       (loop for row in rows
                             for hit-p in hit-mask
                             when (empty-sequence-row-p row pos)
                               collect hit-p into hits
                             finally (return (and hits (every #'identity hits))))))))

(defun typed-recursive-call (name inputs replacements)
  "Build a recursive proposal against the callee's schema, not the child schema."
  (let ((definition (and name (find-function-definition name))))
    (when definition
      (let ((arguments nil))
        (dolist (spec (function-definition-inputs definition))
          (let* ((exact (assoc (car spec) inputs))
                 (matches (remove-if-not (lambda (s) (equal (cdr s) (cdr spec))) inputs))
                 (source (if (and exact (equal (cdr exact) (cdr spec))) exact
                             (when (= 1 (length matches)) (first matches)))))
            (unless source (return-from typed-recursive-call nil))
            (push (or (cdr (assoc (car source) replacements)) (var (car source) (cdr source))) arguments)))
        (apply #'app (op name) (nreverse arguments))))))

(defun inductive-projections (seq-specs inputs self-name)
  "Return (VALUES heads steps) for the non-empty case of the sequence inputs SEQ-SPECS:
the head `(at Xi '0)` of each, and the call of SELF-NAME on every tail `(tail Xi)`, or the
bare tails when no such call can be typed against INPUTS."
  (let* ((tails (loop for (id . type) in seq-specs
                      collect (cons id (term `(tail ,(var id type))))))
         (recursive-call (typed-recursive-call self-name inputs tails)))
    (values (loop for (id . type) in seq-specs collect (term `(at ,(var id type) 0)))
            (if recursive-call (list recursive-call) (mapcar #'cdr tails)))))

(defun inductive-child-language (language operators constants bindings inputs self-name)
  "LANGUAGE over the child inputs that BINDINGS project from INPUTS, offering CONSTANTS and
OPERATORS less the destructors, equality, conditional and SELF-NAME that the decoder applies."
  (let ((child-inputs (loop for (id . expr) in bindings
                            collect (cons id (expression-type expr inputs)))))
    (derive-language
     language
     :inputs child-inputs
     :operators (remove-if (lambda (o)
                             (and (operator-p o)
                                  (or (member (operator-name o) (list :at :tail :if self-name))
                                      (and (eq := (operator-name o))
                                           (or self-name
                                               (< (count (operator-operand-type o) child-inputs
                                                         :key #'cdr :test #'equal)
                                                  2))))))
                           operators)
     :constants constants)))

(defun lift-inductive-sequence-context (guard invert-p inputs language child-language child-id eff-self)
  "When GUARD is an empty-sequence check `(= Xi '())` with INVERT-P NIL (so the residual child
lives in the non-empty else branch) and LANGUAGE provides `:at` and/or `:tail`, lift `(at Xi '0)`
and `(<eff-self> ... (tail Xi) ...)` (or `(tail Xi)`) into the child's bindings and grammar.
Returns (VALUES bindings language lifted-seq-id)."
  (let* ((has-at-p (language-operator-p language :at))
         (has-tail-p (language-operator-p language :tail))
         (seq-spec (and (not invert-p)
                        (if eff-self (and has-at-p has-tail-p) (or has-at-p has-tail-p))
                        (assoc (empty-sequence-guard-var-id guard (mapcar #'car inputs)) inputs))))
    (if (null seq-spec)
        (values (identity-bindings inputs) child-language nil)
        (multiple-value-bind (heads steps) (inductive-projections (list seq-spec) inputs eff-self)
          (let* ((proj-exprs (append (when has-at-p heads) (when has-tail-p steps)))
                 (lifted-bindings
                   (if (rest inputs)
                       (append (loop for (id . ty) in inputs
                                     unless (and (null eff-self) (eql id (car seq-spec)))
                                       collect (cons id (var id ty)))
                               (loop for e in proj-exprs
                                     for cid from child-id
                                     collect (cons cid e)))
                       (loop for e in proj-exprs for cid from 0 collect (cons cid e)))))
            (values lifted-bindings
                    (inductive-child-language language
                                              (language-operators language)
                                              (remove (lit (cdr seq-spec) '())
                                                      (language-constants language)
                                                      :test #'equal)
                                              lifted-bindings inputs eff-self)
                    (car seq-spec)))))))

(defun lockstep-inductive-sequence-decomposition (frame language child-language h-model child-id c-bound
                                                  eff-self solver ledger debug-p)
  "When FRAME has >= 2 sequence inputs and LANGUAGE provides `:at` and `:tail`, propose a
lockstep structural recursion decoder `(if (= X_s1 '()) base (if (= X_s2 '()) base Z_child))`
whose child receives `(at X_si '0)` for each sequence input, any non-sequence inputs, and
the lockstep recursive step `(<eff-self> (tail X_s1) (tail X_s2) ...)`."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (seq-specs (remove-if-not #'seq-type-p inputs :key #'cdr))
         (non-seq-specs (remove-if #'seq-type-p inputs :key #'cdr)))
    (when (and (>= (length seq-specs) 2)
               (language-operator-p language :at)
               (language-operator-p language :tail)
               (every (lambda (s)
                        (some (lambda (o)
                                (and (operator-p o)
                                     (eq := (operator-name o))
                                     (equal (cdr s) (operator-operand-type o))))
                              (language-operators language)))
                      seq-specs))
      (let* ((rows (frame-rows frame))
             (seq-positions (mapcar (lambda (s) (position (car s) inputs :key #'car :test #'eql))
                                    seq-specs))
             (empty-rows (remove-if-not
                          (lambda (r) (some (lambda (pos) (empty-sequence-row-p r pos)) seq-positions))
                          rows))
             (non-empty-rows (remove-if-not
                              (lambda (r)
                                (and (constrained-row-p r)
                                     (every (lambda (pos) (consp (nth pos (row-known r))))
                                            seq-positions)))
                              rows)))
        (when (and empty-rows non-empty-rows)
          (let ((cand-exprs nil))
            (flet ((add-cand (e) (when e (pushnew e cand-exprs :test #'equal))))
              (when h-model
                (add-cand (heuristic-program h-model))
                (dolist (alt (heuristic-alternatives h-model))
                  (add-cand (heuristic-program alt))))
              (dolist (s non-seq-specs)
                (when (equal (cdr s) target)
                  (add-cand (var (car s) (cdr s)))))
              (add-cand (lit target (default-value-for-type target))))
            (let ((base-expr
                    (find-if (lambda (expr)
                               (and (every (lambda (r) (row-satisfied-p r expr inputs :ledger ledger))
                                           empty-rows)
                                    (notevery (lambda (r) (row-satisfied-p r expr inputs :ledger ledger))
                                              non-empty-rows)))
                             (nreverse cand-exprs))))
              (when base-expr
                (multiple-value-bind (head-exprs step-exprs)
                    (inductive-projections seq-specs inputs eff-self)
                  (when (or (null eff-self)
                            (some (lambda (r)
                                    (every (lambda (se)
                                             (eq :value (evaluation-status
                                                         (evaluate se inputs (row-known r) :ledger ledger))))
                                           step-exprs))
                                  non-empty-rows))
                    (let* ((has-code-param-p (some (lambda (s) (code-type-p (cdr s))) non-seq-specs))
                         (kept-non-seq-exprs
                           (loop for (oid . otype) in non-seq-specs
                                 unless (and has-code-param-p
                                             (not (code-type-p otype))
                                             (equal base-expr (var oid otype)))
                                   collect (var oid otype)))
                         (lifted-bindings
                           (loop for expr in (append head-exprs kept-non-seq-exprs step-exprs)
                                 for cid from 0
                                 collect (cons cid expr)))
                         (child-lang
                           (inductive-child-language
                            language
                            (language-operators child-language)
                            (remove-if (lambda (c) (and (seq-type-p (ast-type c)) (null (ast-value c))))
                                       (language-constants child-language))
                            lifted-bindings inputs eff-self)))
                    (make-decomposition
                     :name (list :lockstep-inductive (mapcar #'car seq-specs) base-expr)
                     :decoder (reduce (lambda (spec inner)
                                        (term `(if (= ,(var (car spec) (cdr spec)) ()) ,base-expr ,inner)))
                                      seq-specs
                                      :from-end t
                                      :initial-value (var child-id target))
                     :child-id child-id
                     :child-type target
                     :bindings lifted-bindings
                     :language child-lang
                     :bound (max c-bound (header-bound (language-inputs child-lang) target
                                                       (if has-code-param-p 72 40)))
                     :solver solver
                     :provenance (when debug-p
                                   (list :origin :lockstep-inductive-sequence-lift
                                         :base-program base-expr
                                         :lifted-sequence-ids (mapcar #'car seq-specs)
                                         :lifted-bindings lifted-bindings))))))))))))))

(defun heuristic-decompositions (frame language &key heuristic-model child-language guard-language
                                                     description-limit child-bound guard-bound
                                                     (work-limit 50000) (run-weight 0)
                                                     (additive-p t) (conditional-p t)
                                                     self-name solver ledger
                                                     (debug-p *synthesis-debug-mode*))
  "Bridge Stage A heuristic condensation to Stage B recursive synthesis by turning
a non-exact `heuristic-model` into additive displacement and/or conditional
exception-patching `decomposition` proposals. When a conditional guard is an
empty-sequence check `(= Xi '())`, lifts `(at Xi '0)` and `(<self-name> ... (tail Xi) ...)`
into the non-empty branch's child bindings via `lift-inductive-sequence-context`.
Returns (VALUES proposals heuristic-model)."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target (schema-target schema))
         (bound (or description-limit (header-bound inputs target 18)))
         (c-bound (or child-bound bound))
         (code-guard-slack (loop for o in (language-operators language)
                                 when (and (operator-p o)
                                           (eq :code-eval (operator-name o))
                                           (eq :bool (third (operator-type o))))
                                   maximize (+ 16 (application-overhead o))
                                 finally (return 0)))
         (g-bound (or guard-bound
                      (header-bound inputs :bool
                                    (max (+ 18 (* 2 (integer-length (max 0 (1- (length inputs))))))
                                         code-guard-slack))))
         (c-lang (or child-language language))
         (eff-self (or self-name (find-oracle-operator-name language)))
         (has-guard-op-p (some (lambda (o)
                                 (and (operator-p o)
                                      (or (member (operator-name o) '(:= :<))
                                          (eq :bool (third (operator-type o))))))
                               (language-operators language)))
         (empty-seq-frame-p (and (frame-has-empty-sequence-row-p frame)
                                 (or (null eff-self)
                                     (language-operator-p language :at)
                                     (language-operator-p language :tail)
                                     (not has-guard-op-p))))
         (condense-budget (if heuristic-model 0 (max 1 (if conditional-p (floor work-limit 2) work-limit))))
         (h-model (or heuristic-model
                      (condense-heuristic frame language
                                          :description-limit bound
                                          :work-limit condense-budget
                                          :run-weight run-weight
                                          :ledger ledger))))
    (when (or (null h-model)
              (and (heuristic-exact-p h-model)
                   (null (heuristic-unresolved-keys h-model))
                   (or (null eff-self)
                       (expression-calls-operator-p (heuristic-program h-model) eff-self))))
      (return-from heuristic-decompositions (values nil h-model)))
    (let* ((program (heuristic-program h-model))
           (child-id (next-child-id inputs))
           (child-var (var child-id target))
           (bindings (identity-bindings inputs))
           (hit-mask (heuristic-hit-mask frame h-model))
           (proposals nil))
      ;; Path B1: Additive / displacement residual decoder d(X, Z) = pi_hat(X) + Z.
      ;; Purely relational residuals leave no row displacement to synthesize.
      (when (and additive-p (heuristic-total-p h-model) (additive-residual-type-p target)
                 (some #'null hit-mask)
                 (not (and (lit-p program) (eql 0 (ast-value program))))
                 (not (and eff-self (or empty-seq-frame-p (tuple-type-p target)))))
        (push (make-decomposition
               :name (list :heuristic-additive program)
               :decoder (make-additive-residual-decoder program child-var target)
               :child-id child-id
               :child-type target
               :bindings bindings
               :language c-lang
               :bound c-bound
               :solver solver
               :provenance (when debug-p
                             (list :origin :stage-b-additive
                                   :base-program program
                                   :stage-a-score (heuristic-score h-model)
                                   :stage-a-residual (heuristic-residual h-model))))
              proposals))
      ;; Path B1 again, with a metric decoder of the library in place of addition.
      (when (and additive-p (heuristic-total-p h-model) (some #'null hit-mask)
                 (not (and eff-self empty-seq-frame-p)))
        (dolist (proposal (metric-residual-decompositions frame program (heuristic-residual h-model)
                                                          c-lang c-bound solver ledger debug-p
                                                          :packets (heuristic-packets h-model)))
          (push proposal proposals)))
      ;; Path B2: Conditional exception-patching decoder d(X, Z) = (if G pi_hat Z) or (if G_miss Z pi_hat)
      (when (and conditional-p
                 (or (not empty-seq-frame-p)
                     eff-self
                     (some (lambda (name) (language-operator-p language name)) '(:if :at :tail))))
        (let ((lockstep (when empty-seq-frame-p
                          (lockstep-inductive-sequence-decomposition
                           frame language c-lang h-model child-id c-bound eff-self solver ledger debug-p))))
          (if lockstep
              (push lockstep proposals)
              (let* ((candidates (if (or empty-seq-frame-p eff-self)
                                     (cons h-model (heuristic-alternatives h-model))
                                     (list h-model)))
                     (valid-base-p
                       (lambda (m)
                         (and (not (and eff-self
                                        (heuristic-exact-p m)
                                        (null (heuristic-unresolved-keys m))
                                        (not (expression-calls-operator-p (heuristic-program m) eff-self))))
                              (let ((mask (heuristic-hit-mask frame m)))
                                (and (some #'identity mask)
                                     (some #'null mask)
                                     ;; A base case answers every empty-sequence row; a
                                     ;; frame that defines no function has no base case.
                                     (or (not empty-seq-frame-p)
                                         (null eff-self)
                                         (model-satisfies-empty-sequence-rows-p frame mask)))))))
                     (cand-model (find-if valid-base-p candidates)))
                (when cand-model
                  (let ((cand-program (heuristic-program cand-model))
                        (cand-hit-mask (heuristic-hit-mask frame cand-model))
                        (cand-active-mask (loop for row in (frame-rows frame)
                                                collect (row-active-for-guard-p row cand-model)))
                        (g-lang (or guard-language (default-guard-language frame language))))
                    (multiple-value-bind (guard invert-p)
                        (find-sound-exception-guard frame cand-hit-mask g-lang g-bound
                                                    (max 1 (- work-limit condense-budget)) ledger
                                                    :active-mask cand-active-mask
                                                    :buckets (or (heuristic-buckets cand-model)
                                                                 (heuristic-buckets h-model)))
                      (when guard
                        (multiple-value-bind (eff-bindings eff-lang seq-id)
                            (lift-inductive-sequence-context guard invert-p inputs language c-lang child-id eff-self)
                          (push (make-decomposition
                                 :name (list :heuristic-conditional guard cand-program)
                                 :decoder (term (if invert-p
                                                    `(if ,guard ,child-var ,cand-program)
                                                    `(if ,guard ,cand-program ,child-var)))
                                 :child-id child-id
                                 :child-type target
                                 :bindings eff-bindings
                                 :language eff-lang
                                 :bound c-bound
                                 :solver solver
                                 :provenance (when debug-p
                                               (list :origin (if seq-id :inductive-sequence-lift :stage-b-conditional)
                                                     :base-program cand-program
                                                     :guard guard
                                                     :invert-p invert-p
                                                     :lifted-sequence-id seq-id
                                                     :lifted-bindings eff-bindings
                                                     :stage-a-score (heuristic-score cand-model)
                                                     :stage-a-residual (heuristic-residual cand-model)
                                                     :stage-a-unresolved (heuristic-unresolved-keys cand-model))))
                                proposals))))))))))
      (values (nreverse proposals) h-model))))

(defun remove-keys (keys plist)
  "PLIST without the entries whose indicator is in KEYS."
  (loop for (key value) on plist by #'cddr
        unless (member key keys) append (list key value)))

(defun start-heuristic-synthesis (frame language description-limit
                                  &rest keys
                                  &key decompositions child-language child-bound
                                       (condense-budget 20000) (max-depth 2) fibers dependencies
                                       (debug-p *synthesis-debug-mode*)
                                  &allow-other-keys)
  "Launch a `:policy :heuristic` synthesis job in which every node shallower than MAX-DEPTH,
root included, condenses a Stage A model of its own frame and proposes Stage B residual
and higher-order library branches through `heuristic-expander`. LIBRARY narrows every
pulled-back child frame. The other keywords are those of `heuristic-expander`, whose
work limit is CONDENSE-BUDGET, and of `start-synthesis`."
  (let ((c-lang (or child-language language))
        (c-bound (or child-bound description-limit)))
    (apply #'start-synthesis frame language description-limit
           :decompositions (append (selector-decompositions frame c-lang c-bound
                                                            :fibers fibers :dependencies dependencies
                                                            :debug-p debug-p)
                                   decompositions)
           :policy :heuristic
           :max-depth max-depth
           :expand (apply #'heuristic-expander :child-language child-language :child-bound c-bound
                          :work-limit condense-budget :allow-other-keys t keys)
           (remove-keys '(:child-language :child-bound :condense-budget :fibers :dependencies
                          :guard-language :guard-bound :additive-p :conditional-p
                          :library-proposals-p :library-functions :dependency-proposals-p
                          :structural-proposals-p :expanders)
                        keys))))

(defun start-recursive-synthesis (frame language description-limit
                                  &rest keys
                                  &key self-name oracle-table library
                                       (heuristic-budget 5000) (library-proposals-p (not (null library)))
                                  &allow-other-keys)
  "Launch a recursive synthesis job with oracle self-lifting for SELF-NAME (defaulting to
`next-function-name`). Extracts the partial oracle table from FRAME (unless ORACLE-TABLE
is supplied), condenses base-case and guard splits through standard Stage A/B heuristic
synthesis, lifts non-empty sequence projections `(at Xi '0)` and `(<self-name> ... (tail Xi) ...)`
into child frames, and verifies every candidate at the root by executing the concrete
recursive definition in the VM. Other keywords are those of `start-heuristic-synthesis`."
  (let* ((fn-name (or self-name (next-function-name)))
         (inputs (schema-inputs (frame-schema frame)))
         (target (schema-target (frame-schema frame)))
         (eff-oracle (copy-tree (or oracle-table (frame-oracle-table frame))))
         (root-ops (remove-if (lambda (o) (and (operator-p o) (eq fn-name (operator-name o))))
                              (language-operators language)))
         (root-lang (derive-language language :operators root-ops)))
    (define-function fn-name inputs target nil :oracle-table eff-oracle)
    (apply #'start-heuristic-synthesis frame root-lang description-limit
           :self-name fn-name
           :oracle-table eff-oracle
           :heuristic-budget heuristic-budget
           :library-proposals-p library-proposals-p
           keys)))
