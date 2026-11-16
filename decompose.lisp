(in-package #:lisploop)

;;; Stage B: residual decompositions of a Stage A model, and the heuristic and recursive entry points.

(defun additive-residual-type-p (type)
  "True when TYPE supports additive displacement decoders (:int, (:gf p), or tuples thereof)."
  (or (eq type :int) (gf-type-p type) (and (tuple-type-p type) (every #'additive-residual-type-p (rest type)))))

(defun make-additive-residual-decoder (base-expr residual-var type)
  "Construct outer decoder d(X, Z) = base(X) + Z for scalar or tuple TYPE."
  (assert (additive-residual-type-p type) () "Unsupported additive residual type ~S" type)
  (if (tuple-type-p type)
      (apply #'app (op :tuple type)
             (loop for pt in (rest type) for i from 0
                   collect (make-additive-residual-decoder (app (op :at type) base-expr (lit :int i))
                                                           (app (op :at type) residual-var (lit :int i)) pt)))
      (app (op :+ type) base-expr residual-var)))

(defun companion-solver-for-metric-decoder (entry library ledger)
  "Find or synthesize a `propagator-library` inverting ENTRY's decoder operator at position 1."
  (let* ((elib (or library *knowledge-library*))
         (dop (getf (knowledge-entry-metadata entry) :decoder-op))
         (matches (remove-if-not (lambda (s) (let ((m (knowledge-entry-metadata s)))
                                               (and (eq dop (getf m :operator-name))
                                                    (equal '(1) (solver-positions (getf m :position))))))
                                 (and elib (knowledge-entries-of-kind :solver elib)))))
    (cond (matches
           (let ((rules (loop for s in matches for r = (knowledge-entry->propagator-rule s (knowledge-statement-snapshot s))
                              when r collect r)))
             (when rules (make-propagator-library :rules rules :versions (vm-versions)))))
          ((and (knowledge-entry-residual entry) (app-p (knowledge-entry-expression entry)))
           (let* ((q (knowledge-entry-residual entry)) (eg (knowledge-entry-guard entry))
                  (g (if (member 1 (free-vars eg)) (lit :bool t) eg))
                  (tgt (knowledge-entry-target entry)))
             (charge ledger :propagator-library (+ (syntax-work q) (syntax-work g)))
             (make-propagator-library
              :rules (list (make-arithmetic-propagator
                            :domain (knowledge-entry-domain entry) :operator (first (knowledge-entry-expression entry))
                            :position 1 :witness q :guard g :certified-p nil :unique-p nil
                            :inputs (list (cons 0 tgt) (cons 1 tgt))))
              :versions (vm-versions)))))))

(defun code-hole-decoder-arg (slot-id hsort raw-ctype all-lit-p)
  (if all-lit-p
      (term `(code-subst ,(lit (code-type (list (cons 0 hsort)) hsort) (var 0 hsort))
                         (tuple ,(var slot-id hsort)))
            raw-ctype)
      (var slot-id raw-ctype)))

(defun make-code-au-residual-decoder (base-expr residual-id target-type frame ledger)
  "Attempt a 1-hole `:code-subst` or Constructor-AU decoder over `:code` TARGET-TYPE."
  (when (and frame (code-type-p target-type) (not (function-sort-p (code-sort target-type))))
    (let* ((scope (code-inputs target-type)) (p-inputs (schema-inputs (frame-schema frame)))
           (cpairs (loop for r in (frame-rows frame) when (constrained-row-p r)
                         append (multiple-value-bind (v ok) (row-singleton-value r) (when ok (list (cons r v))))))
           (singletons (mapcar #'cdr cpairs))
           (extra (make-propagator-library :unfold-constructors-p t :versions (vm-versions))))
      (flet ((valid-dec-p (dec ct)
               (and (valid-type-p ct) (ignore-errors (expression-type dec (acons residual-id ct p-inputs))))))
        (when (and scope cpairs)
          (let (vsubs (ok-p t))
            (dolist (pair cpairs)
              (let* ((run (ignore-errors (evaluate base-expr p-inputs (row-known (car pair)) :budget 2000 :ledger ledger)))
                     (val (and run (eq :value (evaluation-status run)) (evaluation-value run)))
                     (sub (and (consp val) (match-code-var-substitution val (cdr pair) scope))))
                (if (and (consp val) (or sub (equal val (cdr pair)))) (push sub vsubs) (setf ok-p nil))))
            (when (and ok-p (some #'identity vsubs))
              (let ((vids (remove-duplicates (loop for s in vsubs append (mapcar #'car s)) :test #'eql)))
                (when (= 1 (length vids))
                  (let* ((vid (first vids)) (vt (cdr (assoc vid scope :test #'eql)))
                         (reps (loop for s in vsubs for e = (assoc vid s :test #'eql) collect (if e (cdr e) (var vid vt))))
                         (ct (if (and (not (function-sort-p vt)) (every #'lit-p reps)) vt (code-type scope vt)))
                         (tt (cons :tuple (loop for (id . tp) in scope collect (if (eql id vid) ct (code-type scope tp)))))
                         (te (apply #'app (op :tuple tt)
                                    (loop for (id . tp) in scope
                                          collect (if (eql id vid) (var residual-id ct) (lit (code-type scope tp) (var id tp))))))
                         (dec (app (op :code-subst (tuple-type target-type tt target-type)) base-expr te)))
                    (when (and (> (length (remove-duplicates reps :test #'equal)) 1) (valid-dec-p dec ct))
                      (return-from make-code-au-residual-decoder (values dec ct extra)))))))))
        (when singletons
          (let* ((pref (when (lit-p base-expr) (cons (ast-value base-expr) singletons))))
            (dolist (srcs (remove nil (list pref (when (>= (length singletons) 2) singletons))))
              (when (>= (length (remove-duplicates srcs :test #'equal)) 2)
                (multiple-value-bind (pat subs) (anti-unify srcs scope ledger :operator-holes-p t)
                  (when (and (not (hole-p pat)) (= 1 (length (pattern-holes pat))) (app-p pat))
                    (multiple-value-bind (ctor-model rcin) (compile-au-constructor pat scope ledger)
                      (let* ((p0 (first rcin)) (hid (car p0)) (rct (cdr p0)) (hs (code-sort rct))
                             (esubs (if (eq srcs pref) (rest subs) subs))
                             (lit-p (and (not (function-sort-p hs)) esubs
                                         (every (lambda (s) (lit-p (cdr (assoc hid s)))) esubs)))
                             (ct (if lit-p hs rct))
                             (dec (instantiate ctor-model (list (cons hid (code-hole-decoder-arg residual-id hs rct lit-p))) :var)))
                        (when (valid-dec-p dec ct)
                          (return-from make-code-au-residual-decoder (values dec ct extra)))))))))))))))

(defun make-metric-residual-decoder (base-expr residual-id residual-type target-type
                                     &key heuristic-model metric-decoder (library *knowledge-library*) frame ledger)
  "Construct a Stage B residual decoder AST `d(base(X), Z)` for TARGET-TYPE."
  (let* ((elib (or library *knowledge-library*))
         (wid (or metric-decoder (and heuristic-model (heuristic-metric-decoder heuristic-model))))
         (entry (and wid elib (find-knowledge-entry wid elib)))
         (meta (and entry (knowledge-entry-metadata entry))))
    (cond ((and entry (not (eq :inactive (knowledge-entry-status entry)))
                (eq :anti-unify (getf meta :solver-op)) (code-type-p target-type))
           (multiple-value-bind (dec ct extra) (make-code-au-residual-decoder base-expr residual-id target-type frame ledger)
             (when dec (return-from make-metric-residual-decoder (values dec ct extra)))))
          ((and entry (not (eq :inactive (knowledge-entry-status entry)))
                (not (eq :+ (getf meta :decoder-op))) (equal target-type (knowledge-entry-target entry)))
           (let ((dt (or residual-type (getf meta :delta-type) (cdr (second (knowledge-entry-inputs entry))))))
             (return-from make-metric-residual-decoder
               (values (instantiate (knowledge-entry-expression entry) (list (cons 0 base-expr) (cons 1 (var residual-id dt))) :var)
                       dt (companion-solver-for-metric-decoder entry elib ledger))))))
    (when (additive-residual-type-p target-type)
      (let ((rt (or residual-type target-type)))
        (values (make-additive-residual-decoder base-expr (var residual-id rt) target-type) rt nil)))))

(defun row-active-for-guard-p (row hmodel)
  (and (constrained-row-p row)
       (or (null (heuristic-residual hmodel))
           (not (member (row-key row) (heuristic-unresolved-keys hmodel) :test #'equal)))))

(defun heuristic-guard-active-mask (frame model)
  (loop for r in (frame-rows frame) collect (row-active-for-guard-p r model)))

(defun heuristic-hit-mask (frame hmodel)
  (let ((res (heuristic-residual hmodel)) (unres (heuristic-unresolved-keys hmodel)))
    (loop for r in (frame-rows frame) for k = (row-key r)
          collect (if res (null (assoc k res :test #'equal)) (not (member k unres :test #'equal))))))

(defun default-guard-language (frame language)
  "Construct a Boolean guard language over FRAME's inputs for exception-patching."
  (let* ((inputs (schema-inputs (frame-schema frame))) (domain (language-domain language))
         (ops (language-operators language))
         (eq-ops (cons (op := domain) (mapcar (lambda (s) (op := (cdr s))) inputs)))
         (lt-ops (remove-if-not (lambda (o) (and (operator-p o) (eq :< (operator-name o)))) ops))
         (nb-ops (remove-if (lambda (o) (and (consp (operator-type o)) (eq :bool (car (last (operator-type o)))))) ops))
         (eseqs (loop for (nil . tp) in inputs when (seq-type-p tp) collect (lit tp '()))))
    (make-language domain inputs
                   :operators (remove-duplicates (append eq-ops lt-ops (list (op :if :bool)) nb-ops) :test #'equal)
                   :literals (if (listp (language-literals language))
                                 (remove-duplicates (append '(0 1) (language-literals language)) :test #'equal)
                                 (language-literals language))
                   :constants (remove-duplicates (append eseqs (language-constants language)) :test #'equal))))

(defun observed-predicates (frame language bound work-limit ledger)
  "Search LANGUAGE observationally over FRAME's rows; return `((expr . vals) ...)` for `:bool` buckets."
  (let* ((obs (start-observation-search (make-observation-scope frame language)))
         (before (ledger-total (observation-job-ledger obs))))
    (resume-observation-search obs bound work-limit)
    (charge ledger :guard-search (- (ledger-total (observation-job-ledger obs)) before))
    (loop for b in (observation-job-buckets obs) when (eq :bool (observation-bucket-type b))
          collect (cons (observed-expression-expression (car (last (observation-bucket-members b))))
                        (observation-bucket-values b)))))

(defun guard-language-allows-expr-p (expr language)
  (let ((inputs (language-inputs language)) (ops (language-operators language))
        (lits (language-literals language)) (consts (language-constants language))
        (dom (language-domain language)))
    (labels ((ok (n)
               (ecase (ast-kind n)
                 (:var (not (null (member (cons (ast-id n) (ast-type n)) inputs :test #'equal))))
                 (:lit (or (not (null (member n consts :test #'equal)))
                           (and (equal (ast-type n) dom) (value-p (ast-value n) dom)
                                (or (not (listp lits)) (not (null (member (ast-value n) lits :test #'equal)))))))
                 (:app (and (member (first n) ops :test #'equal) (every #'ok (rest n)))))))
      (ok expr))))

(defun sound-guard-record (expr vals hit-mask eff-active inputs)
  (let ((shit t) (smiss t) (hits 0) (ihits 0))
    (loop for v in vals for h in hit-mask for a in eff-active
          when a do (if h (if v (incf hits) (incf ihits)) (if v (setf shit nil) (setf smiss nil))))
    (when (or (and shit (plusp hits)) (and smiss (plusp ihits)))
      (let ((inv-p (and smiss (or (not shit) (> ihits hits)))))
        (list expr inv-p (if inv-p ihits hits) (description-size expr inputs))))))

(defun bucket-pair-sound-guards (frame hit-mask buckets guard-language pair-max-body-bits eff-active ledger)
  "Build sound `(= b_i b_j)` and `(< b_i b_j)` / `(< b_j b_i)` guard records from Stage A BUCKETS."
  (let* ((inputs (schema-inputs (frame-schema frame))) (rcount (length (frame-rows frame)))
         (ops (language-operators guard-language)) by-type records)
    (flet ((fcmp (n bt) (find-if (lambda (o) (and (operator-p o) (eq n (operator-name o)) (equal bt (operator-operand-type o)))) ops))
           (emit (e vals) (when (<= (body-size e inputs) pair-max-body-bits)
                            (let ((r (sound-guard-record e vals hit-mask eff-active inputs))) (when r (push r records))))))
      (dolist (entry buckets)
        (when (and (= (length (cdr entry)) rcount) (guard-language-allows-expr-p (car entry) guard-language))
          (let* ((bt (ast-type (car entry))) (eq-op (fcmp := bt)) (lt-op (when (eq bt :int) (fcmp :< :int))))
            (when (or eq-op lt-op)
              (let ((g (assoc bt by-type :test #'equal)) (item (list (car entry) (cdr entry) eq-op lt-op)))
                (if g (push item (cdr g)) (push (list bt item) by-type)))))))
      (dolist (group by-type (nreverse records))
        (loop for ((bi vi eq-op lt-op) . rest) on (nreverse (cdr group)) do
          (dolist (b rest)
            (destructuring-bind (bj vj _e _l) b
              (declare (ignore _e _l))
              (charge ledger :guard-search 1)
              (when eq-op (emit (if (expression-less-p bi bj inputs) (app eq-op bi bj) (app eq-op bj bi))
                                (mapcar #'equal vi vj)))
              (when (and lt-op (loop for a in eff-active for x in vi for y in vj always (or (not a) (and (integerp x) (integerp y)))))
                (emit (app lt-op bi bj) (loop for a in eff-active for x in vi for y in vj collect (and a (< x y))))
                (emit (app lt-op bj bi) (loop for a in eff-active for x in vi for y in vj collect (and a (< y x))))))))))))

(defun find-sound-exception-guard (frame hit-mask guard-language guard-bound work-limit ledger
                                   &key active-mask buckets (pair-max-body-bits 32))
  "Synthesize a Boolean guard `G(X)` separating hit and miss rows. Returns `(VALUES guard invert-p)`."
  (let* ((inputs (schema-inputs (frame-schema frame))) (rows (frame-rows frame))
         (eff-active (or active-mask (let ((c (mapcar #'constrained-row-p rows)))
                                       (if (some #'identity c) c (make-list (length rows) :initial-element t)))))
         (thits (loop for h in hit-mask for a in eff-active count (and a h)))
         (pg (when buckets (bucket-pair-sound-guards frame hit-mask buckets guard-language pair-max-body-bits eff-active ledger)))
         (exact (best-by (remove-if-not (lambda (g) (= (third g) thits)) pg) #'fourth)))
    (when exact (return-from find-sound-exception-guard (values (first exact) (second exact))))
    (let* ((preds (when (and work-limit (plusp work-limit))
                    (observed-predicates (support-frame frame hit-mask ledger) guard-language guard-bound work-limit ledger)))
           (og (loop for (e . vs) in preds for g = (sound-guard-record e vs hit-mask eff-active inputs) when g collect g))
           (best (best-by (append pg og) (list :desc #'third) #'fourth)))
      (values (first best) (second best)))))

(defun find-oracle-operator-name (language)
  (loop for o in (language-operators language) when (operator-p o)
        do (let ((d (find-function-definition (operator-name o))))
             (when (and d (function-definition-oracle-table d)) (return (operator-name o))))))

(defun model-satisfies-empty-sequence-rows-p (frame hit-mask)
  (loop for (nil . tp) in (schema-inputs (frame-schema frame)) for pos from 0
        thereis (and (seq-type-p tp)
                     (let ((hits (loop for r in (frame-rows frame) for hp in hit-mask
                                       when (empty-sequence-row-p r pos) collect hp)))
                       (and hits (every #'identity hits))))))

(defun typed-recursive-call (name inputs replacements)
  (let ((def (and name (find-function-definition name))))
    (when def
      (let (args)
        (dolist (s (function-definition-inputs def))
          (let* ((ex (assoc (car s) inputs))
                 (m (remove-if-not (lambda (i) (equal (cdr i) (cdr s))) inputs))
                 (src (if (and ex (equal (cdr ex) (cdr s))) ex (when (= 1 (length m)) (first m)))))
            (unless src (return-from typed-recursive-call nil))
            (push (or (cdr (assoc (car src) replacements)) (var (car src) (cdr src))) args)))
        (apply #'app (op name) (nreverse args))))))

(defun inductive-projections (seq-specs inputs self-name)
  (let* ((tails (loop for (id . tp) in seq-specs collect (cons id (term `(tail ,(var id tp))))))
         (rec (typed-recursive-call self-name inputs tails)))
    (values (loop for (id . tp) in seq-specs collect (term `(at ,(var id tp) 0)))
            (if rec (list rec) (mapcar #'cdr tails)))))

(defun inductive-child-language (language operators constants bindings inputs self-name)
  (derive-language language
                   :inputs (loop for (id . e) in bindings collect (cons id (expression-type e inputs)))
                   :operators (remove-if (lambda (o) (and (operator-p o) (member (operator-name o) (list :at :tail := :if self-name))))
                                         operators)
                   :constants constants))

(defun lift-inductive-sequence-context (guard invert-p inputs language child-language child-id eff-self)
  "When GUARD is `(= Xi '())` with INVERT-P NIL, lift `(at Xi 0)` and recursive tail call."
  (let ((ss (and (not invert-p) (language-operator-p language :at) (language-operator-p language :tail)
                 (assoc (empty-sequence-guard-var-id guard (mapcar #'car inputs)) inputs))))
    (if (null ss)
        (values (identity-bindings inputs) child-language nil)
        (multiple-value-bind (heads steps) (inductive-projections (list ss) inputs eff-self)
          (let ((lifted (if (rest inputs)
                            (append (identity-bindings inputs) (list (cons child-id (first heads)) (cons (1+ child-id) (first steps))))
                            (list (cons 0 (first heads)) (cons 1 (first steps))))))
            (values lifted
                    (inductive-child-language language (language-operators language)
                                              (remove (lit (cdr ss) '()) (language-constants language) :test #'equal)
                                              lifted inputs eff-self)
                    (car ss)))))))

(defun lockstep-inductive-sequence-decomposition (frame language child-language h-model child-id c-bound eff-self solver ledger debug-p)
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
         (seq-specs (remove-if-not #'seq-type-p inputs :key #'cdr))
         (non-seq (remove-if #'seq-type-p inputs :key #'cdr)))
    (when (and (>= (length seq-specs) 2) (language-operator-p language :at) (language-operator-p language :tail)
               (every (lambda (s) (some (lambda (o) (and (operator-p o) (eq := (operator-name o))
                                                         (equal (cdr s) (operator-operand-type o))))
                                        (language-operators language)))
                      seq-specs))
      (let* ((rows (frame-rows frame))
             (spos (mapcar (lambda (s) (position (car s) inputs :key #'car :test #'eql)) seq-specs))
             (erows (remove-if-not (lambda (r) (some (lambda (p) (empty-sequence-row-p r p)) spos)) rows))
             (nrows (remove-if-not (lambda (r) (and (constrained-row-p r) (every (lambda (p) (consp (nth p (row-known r)))) spos))) rows)))
        (when (and erows nrows)
          (let (cands)
            (flet ((add (e) (when e (pushnew e cands :test #'equal))))
              (when h-model (add (heuristic-program h-model))
                (dolist (alt (heuristic-alternatives h-model)) (add (heuristic-program alt))))
              (dolist (s non-seq) (when (equal (cdr s) target) (add (var (car s) (cdr s)))))
              (add (lit target (default-value-for-type target))))
            (let ((base (find-if (lambda (e) (and (every (lambda (r) (row-satisfied-p r e inputs :ledger ledger)) erows)
                                                  (notevery (lambda (r) (row-satisfied-p r e inputs :ledger ledger)) nrows)))
                                 (nreverse cands))))
              (when base
                (multiple-value-bind (heads steps) (inductive-projections seq-specs inputs eff-self)
                  (let* ((code-p (some (lambda (s) (code-type-p (cdr s))) non-seq))
                         (kept (loop for (oid . ot) in non-seq
                                     unless (and code-p (not (code-type-p ot)) (equal base (var oid ot))) collect (var oid ot)))
                         (lifted (loop for e in (append heads kept steps) for cid from 0 collect (cons cid e)))
                         (clang (inductive-child-language
                                 language (language-operators child-language)
                                 (remove-if (lambda (c) (and (seq-type-p (ast-type c)) (null (ast-value c))))
                                            (language-constants child-language))
                                 lifted inputs eff-self)))
                    (make-decomposition
                     :name (list :lockstep-inductive (mapcar #'car seq-specs) base)
                     :decoder (reduce (lambda (s inner) (term `(if (= ,(var (car s) (cdr s)) ()) ,base ,inner)))
                                      seq-specs :from-end t :initial-value (var child-id target))
                     :child-id child-id :child-type target :bindings lifted :language clang
                     :bound (max c-bound (header-bound (language-inputs clang) target (if code-p 72 40)))
                     :solver solver :provenance (when debug-p (list :origin :lockstep-inductive-sequence-lift
                                                                   :base-program base :lifted-sequence-ids (mapcar #'car seq-specs)
                                                                   :lifted-bindings lifted)))))))))))))

(defun code-slot-child-language (c-lang child-type &key (inputs (language-inputs c-lang)) require-consts-p)
  (let* ((inner-in (code-inputs child-type)) (hsort (code-sort child-type)) (ops (language-operators c-lang))
         (consts (remove-duplicates
                  (append (remove-if-not (lambda (c) (equal child-type (ast-type c))) (language-constants c-lang))
                          (if (function-sort-p hsort)
                              (loop for o in ops when (and (operator-p o) (equal (operator-type o) hsort))
                                    collect (lit child-type o))
                              (append (loop for (id . tp) in inner-in when (equal tp hsort) collect (lit child-type (var id tp)))
                                      (when (listp (language-literals c-lang))
                                        (loop for v in (language-literals c-lang) when (value-p v hsort)
                                              collect (lit child-type (lit hsort v)))))))
                  :test #'equal)))
    (when (or consts (not require-consts-p))
      (derive-language c-lang :inputs inputs
                       :operators (remove-duplicates (append (when (language-operator-p c-lang :if) (list (op :if child-type))) ops) :test #'equal)
                       :constants consts))))

(defun residual-child-language (c-lang child-type target)
  (cond ((equal child-type target) c-lang)
        ((code-type-p child-type) (code-slot-child-language c-lang child-type))
        (t (derive-language c-lang
                            :operators (remove-if (lambda (o) (and (operator-p o) (defined-function-p (operator-name o))
                                                                   (seq-type-p (function-definition-return-type
                                                                                (find-function-definition (operator-name o))))))
                                                  (language-operators c-lang))
                            :literals (if (and (eq child-type :int) (null (language-literals c-lang)))
                                          '(0 1) (language-literals c-lang))))))

(defun heuristic-decompositions (frame language &key heuristic-model child-language guard-language
                                                     description-limit child-bound guard-bound (work-limit 50000)
                                                     (run-weight 0) (additive-p t) (conditional-p t) self-name solver
                                                     (library *knowledge-library*) ledger (debug-p *synthesis-debug-mode*))
  "Bridge Stage A heuristic condensation to Stage B residual and conditional exception-patching decompositions."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)) (target (schema-target schema))
         (elib (or library (and (knowledge-library-p solver) solver) *knowledge-library*))
         (bound (or description-limit (header-bound inputs target 18))) (c-bound (or child-bound bound))
         (g-bound (or guard-bound (header-bound inputs :bool (if (>= (length inputs) 4) 22 20))))
         (c-lang (or child-language language)) (eff-self (or self-name (find-oracle-operator-name language)))
         (empty-seq-p (frame-has-empty-sequence-row-p frame))
         (cbudget (if heuristic-model 0 (max 1 (if conditional-p (floor work-limit 2) work-limit))))
         (hm (or heuristic-model (condense-heuristic frame language :description-limit bound :work-limit cbudget
                                                     :run-weight run-weight :library elib :ledger ledger))))
    (when (or (null hm) (and (heuristic-exact-p hm) (null (heuristic-unresolved-keys hm))
                             (or (null eff-self) (expression-calls-operator-p (heuristic-program hm) eff-self))))
      (return-from heuristic-decompositions (values nil hm)))
    (let* ((prog (heuristic-program hm)) (cid (next-child-id inputs)) (cvar (var cid target))
           (bindings (identity-bindings inputs)) (hmask (heuristic-hit-mask frame hm))
           (glang (or guard-language (default-guard-language frame language)))
           (valid-p (lambda (m)
                      (and (not (and eff-self (heuristic-exact-p m) (null (heuristic-unresolved-keys m))
                                     (not (expression-calls-operator-p (heuristic-program m) eff-self))))
                           (let ((mask (heuristic-hit-mask frame m)))
                             (and (some #'identity mask) (some #'null mask)
                                  (or (not empty-seq-p) (model-satisfies-empty-sequence-rows-p frame mask)))))))
           (gbudget (if heuristic-model work-limit (max 1 (- work-limit cbudget)))) proposals)
      (when (and heuristic-model conditional-p (not (heuristic-exhausted-p hm)) (<= (heuristic-work-used hm) 6000)
                 (>= work-limit 10000) (not (or (seq-type-p target) (code-type-p target) (tuple-type-p target)))
                 (not (some #'tuple-type-p (mapcar #'cdr inputs))) (not empty-seq-p) (not eff-self))
        (let* ((cand (when (funcall valid-p hm) hm))
               (iexact-p (when (and cand (heuristic-buckets hm))
                           (let* ((m (heuristic-hit-mask frame cand)) (a (heuristic-guard-active-mask frame cand))
                                  (th (loop for h in m for ac in a count (and ac h))))
                             (not (null (some (lambda (g) (= (third g) th))
                                              (bucket-pair-sound-guards frame m (heuristic-buckets hm) glang 32 a ledger))))))))
          (when (and cand (not iexact-p))
            (let* ((before (if ledger (ledger-total ledger) 0))
                   (deeper (condense-heuristic frame language :description-limit bound
                                               :work-limit (max 1 (- work-limit 1500)) :run-weight run-weight
                                               :stop-on-exact-p t :library elib :ledger ledger)))
              (when ledger (setf gbudget (max 1 (- work-limit (- (ledger-total ledger) before)))))
              (when deeper
                (setf hm deeper prog (heuristic-program deeper) hmask (heuristic-hit-mask frame deeper))
                (when (and (heuristic-exact-p deeper) (heuristic-total-p deeper) (null (heuristic-unresolved-keys deeper)))
                  (let* ((dl (or (find-if (lambda (c) (equal target (ast-type c))) (language-constants c-lang))
                                 (unless (and (code-type-p target) (function-sort-p (code-sort target)))
                                   (lit target (default-value-for-type target)))))
                         (clang (when dl (derive-language c-lang :inputs nil :operators nil :literals nil :constants (list dl)))))
                    (when dl
                      (return-from heuristic-decompositions
                        (values (list (make-decomposition
                                       :name (list :heuristic-exact prog) :decoder prog :child-id cid
                                       :child-type target :bindings nil :language clang
                                       :bound (max (description-size dl nil) (header-bound nil target 4))
                                       :solver solver :policy-score -20
                                       :provenance (when debug-p (list :origin :stage-a-exact-continuation :base-program prog
                                                                       :stage-a-score (heuristic-score deeper)))))
                                deeper))))))))))
      (let ((mdec (heuristic-metric-decoder hm)))
        (when (and additive-p (heuristic-total-p hm) (or mdec (additive-residual-type-p target)) (some #'null hmask)
                   (not (and (null mdec) (lit-p prog) (eql 0 (ast-value prog)))) (not (and eff-self empty-seq-p)))
          (multiple-value-bind (dec ct extra)
              (make-metric-residual-decoder prog cid nil target :heuristic-model hm :library elib :frame frame :ledger ledger)
            (when dec
              (push (make-decomposition
                     :name (if mdec (list :heuristic-metric mdec prog) (list :heuristic-additive prog))
                     :decoder dec :child-id cid :child-type ct :bindings bindings
                     :language (residual-child-language c-lang ct target)
                     :bound (if (equal ct target) c-bound (min c-bound (header-bound inputs ct 36)))
                     :solver (cond ((and solver extra) (as-propagator-library (list solver extra) ledger))
                                   (extra extra) (t solver))
                     :policy-score (if mdec -10 0)
                     :provenance (when debug-p (list :origin (if mdec :stage-b-metric :stage-b-additive)
                                                     :metric-decoder mdec :base-program prog
                                                     :stage-a-score (heuristic-score hm)
                                                     :stage-a-residual (heuristic-residual hm))))
                    proposals)))))
      (when (and conditional-p (or (not empty-seq-p) eff-self
                                   (some (lambda (n) (language-operator-p language n)) '(:if :at :tail))))
        (let ((lockstep (when empty-seq-p
                          (lockstep-inductive-sequence-decomposition
                           frame language c-lang hm cid c-bound eff-self solver ledger debug-p))))
          (if lockstep (push lockstep proposals)
              (let ((cm (find-if valid-p (if (or empty-seq-p eff-self) (cons hm (heuristic-alternatives hm)) (list hm)))))
                (when cm
                  (let ((cp (heuristic-program cm)))
                    (multiple-value-bind (guard invert-p)
                        (find-sound-exception-guard frame (heuristic-hit-mask frame cm) glang g-bound gbudget ledger
                                                    :active-mask (heuristic-guard-active-mask frame cm)
                                                    :buckets (heuristic-buckets hm))
                      (when guard
                        (multiple-value-bind (ebinds elang seq-id)
                            (lift-inductive-sequence-context guard invert-p inputs language c-lang cid eff-self)
                          (push (make-decomposition
                                 :name (list :heuristic-conditional guard cp)
                                 :decoder (term (if invert-p `(if ,guard ,cvar ,cp) `(if ,guard ,cp ,cvar)))
                                 :child-id cid :child-type target :bindings ebinds
                                 :language elang :bound c-bound :solver solver
                                 :provenance (when debug-p
                                               (list :origin (if seq-id :inductive-sequence-lift :stage-b-conditional)
                                                     :base-program cp :guard guard :invert-p invert-p
                                                     :lifted-sequence-id seq-id :lifted-bindings ebinds
                                                     :stage-a-score (heuristic-score cm)
                                                     :stage-a-residual (heuristic-residual cm)
                                                     :stage-a-unresolved (heuristic-unresolved-keys cm))))
                                proposals))))))))))
      (values (nreverse proposals) hm))))

(defun remove-keys (keys plist)
  (loop for (k v) on plist by #'cddr unless (member k keys) append (list k v)))

(defun start-heuristic-synthesis (frame language description-limit &rest keys
                                  &key decompositions child-language child-bound (condense-budget 20000)
                                       (max-depth 2) fibers dependencies (debug-p *synthesis-debug-mode*)
                                  &allow-other-keys)
  "Launch a `:policy :heuristic` synthesis job using Stage A condensation and `heuristic-expander`."
  (apply #'start-synthesis frame language description-limit
         :decompositions (append (selector-decompositions frame (or child-language language)
                                                          (or child-bound description-limit)
                                                          :fibers fibers :dependencies dependencies :debug-p debug-p)
                                 decompositions)
         :policy :heuristic :max-depth max-depth
         :expand (apply #'heuristic-expander :child-language child-language :child-bound child-bound
                        :work-limit condense-budget :allow-other-keys t keys)
         (remove-keys '(:child-language :child-bound :condense-budget :fibers :dependencies :guard-language
                        :guard-bound :additive-p :conditional-p :library-proposals-p :library-functions :dependency-proposals-p)
                      keys)))

(defun start-recursive-synthesis (frame language description-limit &rest keys
                                  &key self-name oracle-table library (heuristic-budget 5000)
                                       (library-proposals-p (not (null library)))
                                  &allow-other-keys)
  "Launch a recursive synthesis job with oracle self-lifting for SELF-NAME."
  (let* ((fn (or self-name (next-function-name))) (schema (frame-schema frame))
         (eff-oracle (copy-tree (or oracle-table (frame-oracle-table frame))))
         (rlang (derive-language language
                                 :operators (remove-if (lambda (o) (and (operator-p o) (eq fn (operator-name o))))
                                                       (language-operators language)))))
    (define-function fn (schema-inputs schema) (schema-target schema) nil :oracle-table eff-oracle)
    (apply #'start-heuristic-synthesis frame rlang description-limit
           :self-name fn :oracle-table eff-oracle :heuristic-budget heuristic-budget
           :library-proposals-p library-proposals-p keys)))
